-- LEGACY / NOT LOADED: DDingUI.toc does not load this file.
-- Active GroupSystem path: FrameController -> GroupManager -> GroupRenderer -> DynamicIconBridge -> GroupInit.
-- [GROUP SYSTEM] BuffFrameManager: 독립 버프 프레임 관리
-- CDM BuffIconCooldownViewer의 네이티브 프레임을 숨기고,
-- 자체 생성한 독립 프레임으로 버프를 표시
-- ★ 커스텀 오라와 동일한 패턴 — CDM과 싸우지 않음
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local BuffFrameManager = {}
DDingUI.BuffFrameManager = BuffFrameManager

-- ============================================================
-- Locals
-- ============================================================

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local pcall = pcall
local type = type
local GetTime = GetTime
local math_abs = math.abs
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell

-- ============================================================
-- State
-- ============================================================

local initialized = false
local framePool = {}         -- [spellID] = independent frame (재사용)
local activeFrames = {}      -- [spellID] = true (현재 활성)
local activeList = {}        -- 정렬된 활성 프레임 배열 (GroupRenderer 제공용)
local hiddenCDMFrames = {}   -- [frame] = cooldownID (숨김 추적)
local auraCache = {}         -- [spellID] = { icon, duration, expirationTime, count, ... }
local buffSpellIDs = {}      -- 모니터링 대상 spellID 목록

local BUFF_VIEWER_NAME = "BuffIconCooldownViewer"

-- ============================================================
-- 프레임 생성 (CustomIcons.CreateBaseIcon 패턴)
-- ============================================================

local function CreateBuffFrame(spellID)
    local name = "DDingUI_BuffFrame_" .. spellID
    local frame = CreateFrame("Button", name, UIParent, "BackdropTemplate")
    frame:SetSize(40, 40)

    -- ARTWORK 레이어 (BackdropTemplate보다 위)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border
    local border = CreateFrame("Frame", nil, frame)
    border:SetFrameLevel(frame:GetFrameLevel() + 1)
    border:SetAllPoints(frame)
    border:Hide()

    -- Cooldown (duration 스와이프)
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints(frame)
    cd:SetFrameLevel(frame:GetFrameLevel() + 1)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd:SetHideCountdownNumbers(false)
    cd:SetReverse(false)

    -- Count text layer
    local countLayer = CreateFrame("Frame", nil, frame)
    countLayer:SetFrameLevel(frame:GetFrameLevel() + 2)
    countLayer:SetAllPoints(frame)

    local count = countLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetJustifyH("RIGHT")
    count:SetTextColor(1, 1, 1, 1)
    count:SetShadowOffset(0, 0)
    count:SetShadowColor(0, 0, 0, 1)

    frame.icon = icon
    frame.cooldown = cd
    frame.Cooldown = cd  -- SkinIcon 호환 (대문자)
    frame.count = count
    frame.border = border
    frame._buffSpellID = spellID
    frame._isBuffFrame = true

    frame:EnableMouse(true)
    frame:Hide()  -- 비활성 상태로 시작

    return frame
end

-- ============================================================
-- 프레임 Pool 관리
-- ============================================================

local function GetOrCreateFrame(spellID)
    if framePool[spellID] then
        return framePool[spellID]
    end
    local frame = CreateBuffFrame(spellID)
    framePool[spellID] = frame
    return frame
end

-- ============================================================
-- 오라 상태 추적 (UNIT_AURA)
-- ============================================================

local function UpdateAuraState(spellID)
    local auraData = nil
    pcall(function()
        auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end)

    if auraData then
        local cache = auraCache[spellID]
        if not cache then
            cache = {}
            auraCache[spellID] = cache
        end
        cache.active = true
        cache.duration = auraData.duration or 0
        cache.expirationTime = auraData.expirationTime or 0
        cache.applications = auraData.applications or 0
        cache.icon = auraData.icon
        cache.name = auraData.name
        return true
    else
        if auraCache[spellID] then
            auraCache[spellID].active = false
        end
        return false
    end
end

local function ApplyAuraToFrame(frame, spellID)
    local cache = auraCache[spellID]
    if not cache or not cache.active then
        frame:Hide()
        activeFrames[spellID] = nil
        return
    end

    -- 텍스처 설정
    if cache.icon and frame.icon then
        frame.icon:SetTexture(cache.icon)
    elseif frame.icon then
        -- C_Spell 폴백
        local spellInfo = C_Spell and C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.iconID then
            frame.icon:SetTexture(spellInfo.iconID)
        end
    end

    -- 쿨다운(duration) 설정
    if frame.cooldown then
        if cache.duration and cache.duration > 0 and cache.expirationTime and cache.expirationTime > 0 then
            local startTime = cache.expirationTime - cache.duration
            frame.cooldown:SetCooldown(startTime, cache.duration)
        else
            frame.cooldown:Clear()
        end
    end

    -- 중첩 수
    if frame.count then
        if cache.applications and cache.applications > 1 then
            frame.count:SetText(cache.applications)
            frame.count:Show()
        else
            frame.count:SetText("")
            frame.count:Hide()
        end
    end

    frame:Show()
    activeFrames[spellID] = true
end

-- ============================================================
-- CDM 버프 프레임 숨김 (DDingUI 3중 Hook)
-- ============================================================

local function HideCDMFrame(frame, cooldownID)
    if not frame then return end
    if frame._ddBuffHidden then return end  -- 이미 숨김

    frame._ddBuffHidden = true
    frame._ddBuffHiddenCdID = cooldownID
    frame:Hide()
    hiddenCDMFrames[frame] = cooldownID

    -- Show hook
    if not frame._ddBuffShowHooked then
        hooksecurefunc(frame, "Show", function(self)
            if self._ddBuffHidden then
                -- cooldownID 변경됐으면 (프레임 재활용) 해제 여부 체크
                if self._ddBuffHiddenCdID then
                    local currentID = self.cooldownID
                    if currentID and currentID ~= self._ddBuffHiddenCdID then
                        -- 재활용된 프레임: 새 ID가 관리 대상인지 확인
                        if not BuffFrameManager:ShouldHideSpell(currentID) then
                            self._ddBuffHidden = nil
                            self._ddBuffHiddenCdID = nil
                            hiddenCDMFrames[self] = nil
                            return  -- CDM이 보여줘도 됨
                        else
                            -- 새 ID도 관리 대상 → 숨김 유지
                            self._ddBuffHiddenCdID = currentID
                            hiddenCDMFrames[self] = currentID
                        end
                    end
                end
                self:Hide()
            end
        end)
        frame._ddBuffShowHooked = true
    end

    -- SetShown hook
    if not frame._ddBuffSetShownHooked then
        hooksecurefunc(frame, "SetShown", function(self, shown)
            if shown and self._ddBuffHidden then
                self:Hide()
            end
        end)
        frame._ddBuffSetShownHooked = true
    end
end

local function UnhideCDMFrame(frame)
    if not frame then return end
    frame._ddBuffHidden = nil
    frame._ddBuffHiddenCdID = nil
    hiddenCDMFrames[frame] = nil
    -- Show는 하지 않음 — CDM이 필요할 때 자체적으로 Show 호출
end

-- ============================================================
-- CDM BuffViewer Pool 스캔 + 숨김 적용
-- ============================================================

local function ScanAndHideCDMBuffs()
    local viewer = _G[BUFF_VIEWER_NAME]
    if not viewer or not viewer.itemFramePool then return end

    for frame in viewer.itemFramePool:EnumerateActive() do
        if frame and frame.cooldownID then
            if BuffFrameManager:ShouldHideSpell(frame.cooldownID) then
                HideCDMFrame(frame, frame.cooldownID)
            end
        end
    end
end

-- ============================================================
-- 모니터링 대상 SpellID 수집
-- ============================================================

local function CollectBuffSpellIDs()
    wipe(buffSpellIDs)

    local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    if not gs or not gs.groups then return end

    -- 버프 그룹 목록 수집 (CDM "Buffs" + 커스텀 autoFilter=HELPFUL)
    local buffGroups = {}
    for gName, gSettings in pairs(gs.groups) do
        if gSettings.enabled then
            -- CDM Buffs 그룹: "Buffs" → BuffIconCooldownViewer
            if gName == "Buffs" then
                buffGroups[gName] = true
            -- 커스텀 버프 그룹: autoFilter == "HELPFUL"
            elseif gSettings.autoFilter == "HELPFUL" then
                buffGroups[gName] = true
            end
        end
    end

    -- CDM BuffViewer의 active pool에서 spellID를 직접 읽음
    local viewer = _G[BUFF_VIEWER_NAME]
    if not viewer or not viewer.itemFramePool then return end

    for frame in viewer.itemFramePool:EnumerateActive() do
        if frame and frame.cooldownID and type(frame.cooldownID) == "number" then
            -- BuffIconCooldownViewer에 있는 프레임은 모두 버프
            -- ClassifyIcon으로 특정 버프 그룹에 할당된 경우 그 그룹 사용
            -- 아니면 기본 "Buffs" 그룹
            local targetGroup = "Buffs"
            local GM = DDingUI.GroupManager
            if GM then
                local groupName = GM:ClassifyIcon(frame.cooldownID, frame)
                if groupName and buffGroups[groupName] then
                    targetGroup = groupName
                end
            end
            if buffGroups[targetGroup] then
                buffSpellIDs[frame.cooldownID] = targetGroup
            end
        end
    end
end

-- ============================================================
-- 전체 업데이트 (UNIT_AURA 시 호출)
-- ============================================================

local function FullUpdate()
    if not initialized then return end

    -- 1. CDM BuffViewer에서 모니터링 대상 수집
    CollectBuffSpellIDs()

    -- 2. CDM 버프 프레임 숨김
    ScanAndHideCDMBuffs()

    -- 3. 각 spellID의 오라 상태 갱신 + 독립 프레임 업데이트
    -- 비활성 프레임 정리
    for spellID in pairs(activeFrames) do
        if not buffSpellIDs[spellID] then
            local frame = framePool[spellID]
            if frame then frame:Hide() end
            activeFrames[spellID] = nil
        end
    end

    for spellID, groupName in pairs(buffSpellIDs) do
        local frame = GetOrCreateFrame(spellID)
        local isActive = UpdateAuraState(spellID)

        if isActive then
            ApplyAuraToFrame(frame, spellID)
        else
            frame:Hide()
            activeFrames[spellID] = nil
        end
    end

    -- 4. 활성 프레임 목록 갱신 (그룹별)
    wipe(activeList)
    for spellID in pairs(activeFrames) do
        local frame = framePool[spellID]
        if frame and frame:IsShown() then
            activeList[#activeList + 1] = {
                spellID = spellID,
                frame = frame,
                groupName = buffSpellIDs[spellID],
            }
        end
    end

    -- spellID 정렬 (결정적 순서)
    table.sort(activeList, function(a, b)
        return a.spellID < b.spellID
    end)
end

-- ============================================================
-- Public API
-- ============================================================

function BuffFrameManager:ShouldHideSpell(cooldownID)
    return buffSpellIDs[cooldownID] ~= nil
end

--- 특정 그룹에 속하는 활성 버프 프레임 목록 반환
--- GroupRenderer가 호출
---@param groupName string
---@return table[] { icon = frame, isDynBridge = false }
function BuffFrameManager:GetActiveFramesForGroup(groupName)
    local result = {}
    for _, entry in ipairs(activeList) do
        if entry.groupName == groupName then
            result[#result + 1] = {
                icon = entry.frame,
                isBuffFrame = true,
                spellID = entry.spellID,
            }
        end
    end
    return result
end

--- 전체 갱신
function BuffFrameManager:Update()
    FullUpdate()
end

--- 초기화
function BuffFrameManager:Initialize()
    if initialized then return end
    initialized = true

    -- UNIT_AURA 이벤트 등록
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:SetScript("OnEvent", function(self, event, unit)
        if unit ~= "player" then return end
        -- 독립 프레임 상태만 갱신
        -- GroupInit의 UNIT_AURA→DoFullUpdate 체인이 GroupRenderer를 트리거하므로
        -- 여기서 DoFullUpdate를 호출하면 이중 실행됨
        FullUpdate()
    end)

    -- CDM BuffViewer Layout 훅 — CDM이 아이콘을 보여주면 즉시 숨김
    local viewer = _G[BUFF_VIEWER_NAME]
    if viewer then
        if viewer.Layout then
            hooksecurefunc(viewer, "Layout", function()
                if initialized then ScanAndHideCDMBuffs() end
            end)
        end
        if viewer.UpdateLayout then
            hooksecurefunc(viewer, "UpdateLayout", function()
                if initialized then ScanAndHideCDMBuffs() end
            end)
        end
    end

    -- 즉시 초기 스캔 (CDM 뷰어가 이미 준비된 경우)
    FullUpdate()

    -- CDM 뷰어가 아직 준비 안 됐을 수 있으므로 폴백
    C_Timer.After(0.5, function()
        if initialized then FullUpdate() end
    end)
    C_Timer.After(2.0, function()
        if initialized then FullUpdate() end
    end)
end

--- 종료
function BuffFrameManager:Shutdown()
    if not initialized then return end
    initialized = false

    -- CDM 프레임 숨김 해제
    for frame in pairs(hiddenCDMFrames) do
        UnhideCDMFrame(frame)
    end
    wipe(hiddenCDMFrames)

    -- 독립 프레임 숨김
    for _, frame in pairs(framePool) do
        frame:Hide()
    end
    wipe(activeFrames)
    wipe(activeList)
    wipe(auraCache)
    wipe(buffSpellIDs)
end

--- 프레임 pool 접근 (디버그용)
function BuffFrameManager:GetFramePool()
    return framePool
end

function BuffFrameManager:IsInitialized()
    return initialized
end
