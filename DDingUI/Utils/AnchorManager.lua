--[[
    DDingUI Utils/AnchorManager.lua
    앵커 시스템 단일 진실 소스 (Single Source of Truth)
    
    모든 Mover/프레임의 앵커 상태를 중앙 관리:
    - Register: 프레임 등록
    - SetAnchor: 위치 변경 (순환 감지 포함)
    - FlushDirty: 변경된 엔트리만 DB에 저장
    - LoadAll: DB → registry 로드
    - GetAllSnapTargets: 통합 스냅 타겟 풀
    
    [v1.0] 2026-03-09
]]

local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- ============================================================
-- 네임스페이스
-- ============================================================
DDingUI.AnchorManager = DDingUI.AnchorManager or {}
local AM = DDingUI.AnchorManager

local math_floor = math.floor
local math_abs = math.abs
local math_min = math.min
local math_max = math.max

-- ============================================================
-- 중앙 레지스트리
-- ============================================================
AM.registry = AM.registry or {}
AM._callbacks = AM._callbacks or {}

-- 소스 상수
AM.SOURCE_CDM = "CDM"
AM.SOURCE_UF  = "UF"
AM.SOURCE_BT  = "BuffTracker"

-- ============================================================
-- 1. Register — 프레임 등록
-- ============================================================

---@param name string 프레임 고유 이름 (예: "DDingUI_PowerBar", "ddingUI_Player")
---@param frame Frame 실제 WoW 프레임 참조
---@param source string "CDM" | "UF" | "BuffTracker"
---@param opts table|nil { attachTo, selfPoint, anchorPoint, offsetX, offsetY, hasBarAnchorFlip }
function AM:Register(name, frame, source, opts)
    if not name or not frame then return end
    opts = opts or {}
    
    self.registry[name] = {
        frame = frame,
        source = source or "CDM",
        attachTo = opts.attachTo or "UIParent",
        selfPoint = opts.selfPoint or "CENTER",
        anchorPoint = opts.anchorPoint or "CENTER",
        offsetX = opts.offsetX or 0,
        offsetY = opts.offsetY or 0,
        hasBarAnchorFlip = opts.hasBarAnchorFlip or false,
        dirty = false,
    }
end

-- ============================================================
-- 2. 순환 앵커 감지 (BFS 그래프 탐색) — Phase 2
-- ============================================================

--- name의 attachTo를 newAttachTo로 변경할 때 순환이 발생하는지 검사
---@param name string 변경 대상
---@param newAttachTo string 새 앵커 대상 이름
---@return boolean true = 순환 발생
function AM:WouldCreateCycle(name, newAttachTo)
    if not name or not newAttachTo then return false end
    if newAttachTo == "UIParent" or newAttachTo == "" then return false end
    if newAttachTo == name then return true end  -- 자기자신
    
    -- BFS: newAttachTo에서 시작 → name에 도달 가능하면 순환
    local visited = { [name] = true }
    local queue = { newAttachTo }
    local maxIter = 50  -- 무한루프 방지
    local iter = 0
    
    while #queue > 0 and iter < maxIter do
        iter = iter + 1
        local current = table.remove(queue, 1)
        if current == name then return true end  -- 순환!
        if visited[current] then
            -- 이미 방문 = 다른 경로로 여기 도착, 순환 아님 (이 경로에서)
        else
            visited[current] = true
            local entry = self.registry[current]
            if entry and entry.attachTo and entry.attachTo ~= "UIParent" and entry.attachTo ~= "" then
                table.insert(queue, entry.attachTo)
            end
            -- 레지스트리에 없는 프레임: _G에서 직접 앵커 체인 추적
            if not entry then
                local gFrame = _G[current]
                if gFrame and gFrame.GetPoint then
                    local ok, _, anchor = pcall(gFrame.GetPoint, gFrame, 1)
                    if ok and anchor and anchor ~= UIParent then
                        local anchorName = anchor:GetName()
                        if anchorName and anchorName ~= "" then
                            table.insert(queue, anchorName)
                        end
                    end
                end
            end
        end
    end
    
    return false
end

-- ============================================================
-- 3. barAnchorFlip 단일 변환 — Phase 3
-- ============================================================

-- DB 저장값(anchorPoint) → 실제 SetPoint용 anchorPoint
-- "바를 앵커 위에 놓으려면" anchorPoint=BOTTOM → SetPoint에서 selfPoint=BOTTOM, anchorPoint=TOP
local function FlipBarAnchor(anchorPt)
    if anchorPt == "TOP" then return "BOTTOM" end
    if anchorPt == "BOTTOM" then return "TOP" end
    return anchorPt
end

-- 실제 SetPoint anchorPoint → DB 저장용 anchorPoint (역변환)
local function UnflipBarAnchor(anchorPt)
    return FlipBarAnchor(anchorPt)  -- 대칭이라 동일
end

AM.FlipBarAnchor = FlipBarAnchor
AM.UnflipBarAnchor = UnflipBarAnchor

-- ============================================================
-- 4. SetAnchor — 유일한 위치 변경 진입점
-- ============================================================

---@param name string 프레임 이름
---@param attachTo string 앵커 대상 이름 ("UIParent" 또는 프레임 이름)
---@param selfPt string 자기 앵커 포인트
---@param anchorPt string 대상 앵커 포인트
---@param oX number X 오프셋
---@param oY number Y 오프셋
---@return boolean success
function AM:SetAnchor(name, attachTo, selfPt, anchorPt, oX, oY)
    local entry = self.registry[name]
    if not entry then return false end
    
    attachTo = attachTo or "UIParent"
    selfPt = selfPt or "CENTER"
    anchorPt = anchorPt or "CENTER"
    oX = math_floor((oX or 0) + 0.5)
    oY = math_floor((oY or 0) + 0.5)
    
    -- [Phase 2] 순환 앵커 검사
    if attachTo ~= "UIParent" and attachTo ~= "" then
        if self:WouldCreateCycle(name, attachTo) then
            -- 순환 감지: UIParent로 폴백
            if DDingUI.Print then
                DDingUI:Print("|cffff0000순환 앵커 감지:|r " .. name .. " → " .. attachTo .. " (UIParent로 전환)")
            end
            attachTo = "UIParent"
            selfPt = "CENTER"
            anchorPt = "CENTER"
        end
    end
    
    -- 레지스트리 업데이트
    entry.attachTo = attachTo
    entry.selfPoint = selfPt
    entry.anchorPoint = anchorPt
    entry.offsetX = oX
    entry.offsetY = oY
    entry.dirty = true
    
    -- 즉시 프레임에 적용
    local frame = entry.frame
    if frame and not InCombatLockdown() then
        local anchorFrame = UIParent
        if attachTo ~= "UIParent" and attachTo ~= "" then
            -- CDM ResolveAnchorFrame 사용 (있으면)
            if DDingUI.ResolveAnchorFrame then
                anchorFrame = DDingUI:ResolveAnchorFrame(attachTo)
            else
                anchorFrame = _G[attachTo] or UIParent
            end
        end
        
        -- [Phase 3] barAnchorFlip 처리
        local actualSelfPt = selfPt
        local actualAnchorPt = anchorPt
        if entry.hasBarAnchorFlip then
            actualAnchorPt = FlipBarAnchor(anchorPt)
            -- selfPoint도 동일하게 반전 (바가 위에 놓이려면 selfPt도 반전)
            actualSelfPt = FlipBarAnchor(selfPt)
        end
        
        local fW, fH = frame:GetSize()
        frame:ClearAllPoints()
        frame:SetPoint(actualSelfPt, anchorFrame, actualAnchorPt, oX, oY)
        if fW and fW > 0 and fH and fH > 0 then
            frame:SetSize(fW, fH)
        end
    end
    
    -- 콜백 발행
    for _, cb in ipairs(self._callbacks) do
        pcall(cb, "ANCHOR_CHANGED", name, entry)
    end
    
    return true
end

-- ============================================================
-- 5. GetAnchor — 레지스트리에서 현재 앵커 상태 조회
-- ============================================================

function AM:GetAnchor(name)
    return self.registry[name]
end

function AM:GetAttachTo(name)
    local entry = self.registry[name]
    return entry and entry.attachTo or "UIParent"
end

-- ============================================================
-- 6. FlushDirty — dirty인 엔트리만 DB에 저장
-- ============================================================

function AM:FlushDirty()
    for name, entry in pairs(self.registry) do
        if entry.dirty then
            self:SaveEntryToDB(name, entry)
            entry.dirty = false
        end
    end
end

-- 개별 엔트리 DB 저장 (소스별 분기)
function AM:SaveEntryToDB(name, entry)
    if not entry then return end
    
    if entry.source == AM.SOURCE_CDM then
        self:SaveCDMEntry(name, entry)
    elseif entry.source == AM.SOURCE_UF then
        self:SaveUFEntry(name, entry)
    elseif entry.source == AM.SOURCE_BT then
        self:SaveCDMEntry(name, entry)  -- BuffTracker는 CDM DB 사용
    end
end

-- CDM DB 저장
function AM:SaveCDMEntry(name, entry)
    if not DDingUI.db or not DDingUI.db.profile then return end
    
    local profile = DDingUI.db.profile
    if not profile.movers then profile.movers = {} end
    
    -- [Phase 3] barAnchorFlip 저장용: 실제 anchorPoint를 DB용으로 변환 (불필요: 이미 DB 형식)
    local pt = entry.selfPoint or "CENTER"
    local anchorPt = entry.anchorPoint or "CENTER"
    local attachFrame = entry.attachTo or "UIParent"
    
    -- movers 문자열 형식 저장 (레거시 호환)
    profile.movers[name] = string.format("%s,%s,%s,%d,%d",
        pt, attachFrame, anchorPt,
        entry.offsetX or 0, entry.offsetY or 0
    )
end

-- UF DB 저장
function AM:SaveUFEntry(name, entry)
    -- UF ns는 DDingUI_UF의 ns이므로 직접 접근 불가
    -- → 콜백을 통해 UF Mover가 자체 저장
    -- FlushDirty에서 UF 콜백 트리거
    for _, cb in ipairs(self._callbacks) do
        pcall(cb, "SAVE_UF_ENTRY", name, entry)
    end
end

-- ============================================================
-- 7. LoadAll — DB → registry 로드 (CDM/UF 공용)
-- ============================================================

-- CDM movers 로드
function AM:LoadCDMMovers()
    if not DDingUI.db or not DDingUI.db.profile or not DDingUI.db.profile.movers then return end
    
    for name, str in pairs(DDingUI.db.profile.movers) do
        if type(str) == "string" then
            local pt, attachName, anchorPt, x, y = strsplit(",", str)
            x = tonumber(x) or 0
            y = tonumber(y) or 0
            
            local entry = self.registry[name]
            if entry then
                entry.selfPoint = pt or "CENTER"
                entry.attachTo = attachName or "UIParent"
                entry.anchorPoint = anchorPt or "CENTER"
                entry.offsetX = x
                entry.offsetY = y
                entry.dirty = false
            end
        end
    end
end

-- ============================================================
-- 8. 콜백 등록
-- ============================================================

function AM:RegisterCallback(func)
    if type(func) == "function" then
        table.insert(self._callbacks, func)
    end
end

-- ============================================================
-- 9. 통합 스냅 타겟 풀 — Phase 4
-- ============================================================

--- 모든 등록 프레임의 Rect 정보를 반환 (스냅 대상)
---@param excludeName string|nil 제외할 프레임 이름
---@return table[] targets
function AM:GetAllSnapTargets(excludeName)
    local targets = {}
    for name, entry in pairs(self.registry) do
        if name ~= excludeName then
            local frame = entry.frame
            if frame and frame:IsShown() and frame.GetCenter then
                local cx, cy = frame:GetCenter()
                if cx then
                    local w, h = frame:GetSize()
                    if w and w > 0 and h and h > 0 then
                        targets[#targets + 1] = {
                            name = name,
                            label = name,
                            frame = frame,
                            source = entry.source,
                            cx = cx, cy = cy,
                            w = w, h = h,
                            left = cx - w / 2,
                            right = cx + w / 2,
                            bottom = cy - h / 2,
                            top = cy + h / 2,
                        }
                    end
                end
            end
        end
    end
    return targets
end

-- ============================================================
-- 10. 유틸리티
-- ============================================================

-- 전체 엔트리 수
function AM:GetCount()
    local count = 0
    for _ in pairs(self.registry) do count = count + 1 end
    return count
end

-- dirty 엔트리 수
function AM:GetDirtyCount()
    local count = 0
    for _, entry in pairs(self.registry) do
        if entry.dirty then count = count + 1 end
    end
    return count
end

-- 전체 초기화 (프로필 전환용)
function AM:ClearAll()
    wipe(self.registry)
end

-- 디버그 출력
function AM:DebugPrint()
    print("|cff00ccffAnchorManager|r: " .. self:GetCount() .. " entries, " .. self:GetDirtyCount() .. " dirty")
    for name, e in pairs(self.registry) do
        print(string.format("  %s [%s] → %s (%s→%s) offset(%d,%d) %s",
            name, e.source, e.attachTo, e.selfPoint, e.anchorPoint,
            e.offsetX, e.offsetY, e.dirty and "|cffff0000DIRTY|r" or ""))
    end
end

-- ============================================================
-- 11. ATTACH_TO_PROXY 통합 매핑 — Phase 5
-- ============================================================

AM.PROXY_MAP = {
    -- CDM 뷰어 → 프록시
    ["EssentialCooldownViewer"] = "DDingUI_Anchor_Cooldowns",
    ["UtilityCooldownViewer"]   = "DDingUI_Anchor_Utility",
    ["BuffIconCooldownViewer"]  = "DDingUI_Anchor_Buffs",
    -- DDingUI 그룹 → 프록시
    ["DDingUI_Group_Cooldowns"] = "DDingUI_Anchor_Cooldowns",
    ["DDingUI_Group_Utility"]   = "DDingUI_Anchor_Utility",
    ["DDingUI_Group_Buffs"]     = "DDingUI_Anchor_Buffs",
    -- 구버전 호환
    ["DDingUIPowerBar"]         = "DDingUI_Anchor_Cooldowns",
}

--- 레거시 앵커 이름 → 프록시 앵커 이름 변환
function AM:ResolveProxy(anchorName)
    if not anchorName then return "UIParent" end
    return self.PROXY_MAP[anchorName] or anchorName
end

--- DB 마이그레이션: movers 테이블의 레거시 앵커 이름을 프록시로 변환
function AM:MigrateLegacyProxies()
    if not DDingUI.db or not DDingUI.db.profile or not DDingUI.db.profile.movers then return end
    
    local migrated = 0
    for name, str in pairs(DDingUI.db.profile.movers) do
        if type(str) == "string" then
            local pt, attachName, anchorPt, x, y = strsplit(",", str)
            local newAttach = self.PROXY_MAP[attachName]
            if newAttach then
                DDingUI.db.profile.movers[name] = string.format("%s,%s,%s,%s,%s",
                    pt, newAttach, anchorPt or pt, x or "0", y or "0"
                )
                migrated = migrated + 1
            end
        end
    end
    
    if migrated > 0 and DDingUI.Print then
        DDingUI:Print(string.format("|cff00ff00AnchorManager|r: %d개 레거시 앵커 마이그레이션 완료", migrated))
    end
end
