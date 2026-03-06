-- [GROUP SYSTEM] FrameController: CDM 리빌드 감지 + Reconcile + 프레임 훅 엔진
-- [REFACTOR] CDMHookEngine.lua 대체 — ArcUI FrameController 패턴 기반
-- NotifyListeners 훅으로 CDM 리빌드 즉시 감지, 디바운스 Reconcile로 안정적 처리
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local FrameController = {}
DDingUI.FrameController = FrameController

-- 하위 호환: 기존 CDMHookEngine API도 유지
DDingUI.CDMHookEngine = FrameController

-- ============================================================
-- Locals
-- ============================================================

local pairs = pairs
local wipe = wipe
local tinsert = tinsert
local type = type
local pcall = pcall
local math_abs = math.abs
local tostring = tostring
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

-- canaccessvalue / issecretvalue polyfill
if not canaccessvalue then
    canaccessvalue = function() return true end
end

-- ============================================================
-- CDM 뷰어 정의
-- ============================================================

local CDM_VIEWERS = {
    { globalName = "EssentialCooldownViewer", defaultGroup = "Cooldowns", category = 0 },
    { globalName = "UtilityCooldownViewer",   defaultGroup = "Utility",   category = 1 },
    { globalName = "BuffIconCooldownViewer",  defaultGroup = "Buffs",     category = 2 },
}

-- ============================================================
-- 디바운스 설정 (ArcUI 검증 타이밍)
-- ============================================================

local CONFIG = {
    -- 특성/전문화 변경 지연 (CDM이 여러 번 리빌드)
    DEBOUNCE_TALENT   = 0.6,
    DEBOUNCE_SPEC     = 1.0,
    DEBOUNCE_NORMAL   = 0.15,  -- ScheduleReconcile 하위 호환용
    DEBOUNCE_ONSHOW   = 0.05,  -- [FIX] OnShow/OnHide 디바운스 (기존 nil → 즉시 실행 버그 수정)
    -- [Ayije 패턴] OnUpdate 폴링 제어
    BURST_THROTTLE    = 0.033,  -- ~30fps (dirty 상태에서 빠른 스캔)
    WATCHDOG_THROTTLE = 0.25,   -- 4fps (안정화 후 느린 스캔)
    BURST_TICKS       = 15,     -- burst 모드 틱 수 (전투 진입 시 CDM Layout 안정화)
    IDLE_TIMEOUT      = 2.0,    -- idle 후 OnUpdate 비활성화 (초)
}

-- ============================================================
-- 런타임 맵
-- ============================================================

local idIconMap = {}        -- [cooldownID] = CDM icon frame
local iconSourceMap = {}    -- [cooldownID] = viewerGlobalName
local iconSpellNameMap = {} -- [cooldownID] = spellName (캐시)
local viewerRefs = {}       -- [globalName] = viewer frame reference

-- ============================================================
-- State
-- ============================================================

FrameController.initialized = false
FrameController._callbacks = {}
FrameController._editMode = false
FrameController._postCombatQueue = {}

local state = {
    hooksInstalled = false,
    frameHooksInstalled = {},  -- [frameAddress] = true (중복 훅 방지)
    -- [Ayije 패턴] OnUpdate 폴링 상태
    dirty = false,             -- Reconcile 필요 플래그
    burstTicksRemaining = 0,   -- burst 모드 남은 틱
    lastActivityTime = 0,      -- 마지막 활동 시간
    nextUpdateTime = 0,        -- 다음 OnUpdate 실행 시간
    pollingActive = false,     -- OnUpdate 활성 여부
    -- 이벤트 플래그
    specChangeDetected = false,
    talentChangeDetected = false,
    isProcessing = false,
    pendingReconcile = false,  -- Reconcile() 내부 호환용
    -- 통계
    reconcileCount = 0,
}

-- ============================================================
-- [Ayije 패턴] OnUpdate 폴링 시스템
-- CDM의 아이콘 생명주기(acquire→show→layout)가 여러 프레임에 걸쳐
-- 발생하므로, 이벤트 기반 디바운스 대신 폴링으로 상태 확인.
-- Burst(33ms) → Watchdog(250ms) → Idle(자동 비활성화)
-- ============================================================

local pollingFrame = CreateFrame("Frame")

-- dirty 마킹 — 모든 CDM 훅에서 이것만 호출
local function MarkDirty()
    if state.isProcessing then return end
    state.dirty = true
    state.burstTicksRemaining = CONFIG.BURST_TICKS
    state.lastActivityTime = GetTime()
    state.nextUpdateTime = 0
end

-- 폴링 활성화 (전방 선언)
local EnablePolling

-- 폴링 비활성화 (성능 최적화)
function FrameController:DisablePolling()
    if not state.pollingActive then return end
    state.pollingActive = false
    pollingFrame:SetScript("OnUpdate", nil)
    state.dirty = false
    state.burstTicksRemaining = 0
    state.nextUpdateTime = 0
end

-- 폴링 활성화
EnablePolling = function()
    if state.pollingActive then
        MarkDirty() -- 이미 활성이면 dirty만 표시
        return
    end
    MarkDirty()
    state.pollingActive = true
    pollingFrame:SetScript("OnUpdate", function(_, elapsed)
        if not FrameController.initialized then
            FrameController:DisablePolling()
            return
        end

        local now = GetTime()
        if now < state.nextUpdateTime then return end

        -- throttle: dirty/burst면 빠르게, 아니면 느리게
        local throttle = (state.dirty or state.burstTicksRemaining > 0)
            and CONFIG.BURST_THROTTLE
            or CONFIG.WATCHDOG_THROTTLE
        state.nextUpdateTime = now + throttle

        -- Reconcile 실행
        if not state.isProcessing then
            FrameController:Reconcile()
        end

        -- burst 소모
        if state.burstTicksRemaining > 0 then
            state.burstTicksRemaining = state.burstTicksRemaining - 1
        end

        -- idle 체크 — 일정 시간 변경 없으면 비활성화
        if not state.dirty
            and state.burstTicksRemaining <= 0
            and (now - state.lastActivityTime) >= CONFIG.IDLE_TIMEOUT
        then
            FrameController:DisablePolling()
        end
    end)
end
FrameController.EnablePolling = function(self) EnablePolling() end

-- 하위 호환: ScheduleReconcile → MarkDirty + EnablePolling
local function ScheduleReconcile(debounceTime)
    MarkDirty()
    if FrameController.initialized and not state.pollingActive then
        EnablePolling()
    end
end

-- ============================================================
-- 뷰어 탐색
-- ============================================================

local function FindViewers()
    local found = 0
    wipe(viewerRefs)
    for _, def in pairs(CDM_VIEWERS) do
        local viewer = _G[def.globalName]
        if viewer and viewer.itemFramePool then
            viewerRefs[def.globalName] = viewer
            found = found + 1
        end
    end
    return found
end

-- [FIX] 뷰어 참조 갱신: 특성 변경/레벨업 시 Blizzard가 뷰어를 재생성하면
-- viewerRefs가 구 객체를 가리키므로 갱신 필요 (CDMHookEngine RefreshViewers 패턴)
local hookedViewerLayout = {} -- 뷰어별 Layout/Show/Hide 훅 중복 방지

function FrameController:RefreshViewerRefs()
    local changed = false
    for _, def in pairs(CDM_VIEWERS) do
        local currentViewer = _G[def.globalName]
        if currentViewer and currentViewer.itemFramePool then
            local oldViewer = viewerRefs[def.globalName]
            if oldViewer ~= currentViewer then
                -- 새 뷰어 감지 → 참조 갱신
                viewerRefs[def.globalName] = currentViewer
                changed = true

                -- 새 뷰어에 Layout/Show/Hide 훅 설치
                if not hookedViewerLayout[currentViewer] then
                    hookedViewerLayout[currentViewer] = true
                    hooksecurefunc(currentViewer, "Layout", function()
                        if FrameController.initialized then
                            if currentViewer.itemFramePool then
                                for icon in currentViewer.itemFramePool:EnumerateActive() do
                                    if icon._ddIsManaged and icon._ddContainerRef then
                                        local parent = icon:GetParent()
                                        if parent and parent ~= UIParent then
                                            icon:SetParent(UIParent)
                                            icon:SetFrameStrata("MEDIUM")
                                            local container = icon._ddContainerRef
                                            if container then
                                                icon:SetFrameLevel(container:GetFrameLevel() + 10)
                                            end
                                            if icon._ddTargetPoint then
                                                icon._ddSettingPosition = true
                                                icon:ClearAllPoints()
                                                icon:SetPoint(
                                                    icon._ddTargetPoint,
                                                    icon._ddContainerRef,
                                                    icon._ddTargetRelPoint or "CENTER",
                                                    icon._ddTargetX or 0,
                                                    icon._ddTargetY or 0
                                                )
                                                icon._ddSettingPosition = false
                                            end
                                        end
                                    end
                                end
                            end
                            ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
                        end
                    end)
                    hooksecurefunc(currentViewer, "Show", function()
                        if FrameController.initialized then
                            ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
                        end
                    end)
                    hooksecurefunc(currentViewer, "Hide", function()
                        if FrameController.initialized then
                            ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
                        end
                    end)
                end
            end
        end
    end
    if changed then
        -- 맵 재구축 (새 뷰어의 아이콘 풀을 다시 읽어야 함)
        self:ScanCDMViewers()
        -- ContainerSync도 새 뷰어에 훅 재설치
        local ContainerSync = DDingUI.ContainerSync
        if ContainerSync and ContainerSync.RefreshViewerHooks then
            ContainerSync:RefreshViewerHooks()
        end
    end
    return changed
end

-- ============================================================
-- 맵 빌드 (스캔)
-- ============================================================

function FrameController:ScanCDMViewers()
    wipe(idIconMap)
    wipe(iconSourceMap)

    -- [REPARENT] DDingUI 프로필 참조 — 뷰어 활성화 상태 확인
    local profile = DDingUI.db and DDingUI.db.profile
    local viewerProfiles = profile and profile.viewers

    for globalName, viewer in pairs(viewerRefs) do
        local shouldScan = true
        local skipReason = ""

        -- [REPARENT] DDingUI에서 비활성화된 뷰어는 스캔하지 않음
        local vp = viewerProfiles and viewerProfiles[globalName]
        if vp and vp.enabled == false then
            shouldScan = false
            skipReason = "disabled"
        end

        -- [FIX] Ayije 패턴: cooldownID + IsShown 체크
        -- CDM이 Hide()한 비활성 버프는 스캔에서 제외
        -- CDM의 Show/Hide는 OnShow 훅으로 감지하여 Reconcile 트리거
        if shouldScan and viewer.itemFramePool then
            for icon in viewer.itemFramePool:EnumerateActive() do
                -- [FIX] isEditing 프레임 무시 (EditMode 종료 시 블리자드 코드 Taint 에러 방지)
                if icon.cooldownID and icon:IsShown() and not icon.isEditing then
                    idIconMap[icon.cooldownID] = icon
                    iconSourceMap[icon.cooldownID] = globalName

                    if not iconSpellNameMap[icon.cooldownID] then
                        local name = self:GetSpellName(icon)
                        if name then
                            iconSpellNameMap[icon.cooldownID] = name
                        end
                    end
                end
            end
        end
    end
end

-- 하위 호환 별칭
FrameController.RebuildMaps = FrameController.ScanCDMViewers

-- ============================================================
-- Reconcile (핵심 파이프라인)
-- CDM 스캔 → 콜백 알림 → 상태 리셋
-- ============================================================

function FrameController:Reconcile()
    if not self.initialized then
        state.pendingReconcile = false
        return
    end

    state.isProcessing = true
    state.pendingReconcile = false

    -- 1. CDM 뷰어 스캔 (맵 재구축)
    self:ScanCDMViewers()

    -- 2. 콜백 알림 (GroupInit → DoFullUpdate)
    self:NotifyUpdate()

    -- 3. 상태 플래그 리셋
    state.specChangeDetected = false
    state.talentChangeDetected = false
    state.isProcessing = false
    state.dirty = false -- [Ayije] 이번 스캔 완료 → dirty 해제
    state.reconcileCount = state.reconcileCount + 1
    -- OnUpdate 폴링이 watchdog(250ms)으로 자동 재스캔 → 수동 followup 불필요
end

-- ============================================================
-- SpellName 안전 추출
-- ============================================================

function FrameController:GetSpellName(icon)
    if not icon or not icon.GetSpellID then return nil end

    local ok, spellID = pcall(icon.GetSpellID, icon)
    if not ok or not spellID then return nil end
    if not canaccessvalue(spellID) then return nil end

    -- FindBaseSpellByID로 기본 스펠 ID 가져오기
    local baseID = spellID
    local okBase, result = pcall(function()
        if C_SpellBook and C_SpellBook.FindBaseSpellByID then
            return C_SpellBook.FindBaseSpellByID(spellID)
        elseif FindBaseSpellByID then
            return FindBaseSpellByID(spellID)
        end
        return spellID
    end)
    if okBase and result then baseID = result end

    -- SpellInfo에서 이름 추출
    local okInfo, spellInfo = pcall(function()
        if C_Spell and C_Spell.GetSpellInfo then
            return C_Spell.GetSpellInfo(baseID)
        end
    end)
    if not okInfo or not spellInfo or not spellInfo.name then return nil end

    -- [REPARENT] 버프 뷰어 소속이면 "buff_" 접두사 (같은 이름 구분)
    -- reparent 후 GetParent()는 DDingUI 컨테이너 → iconSourceMap 사용
    local prefix = ""
    local sourceName = icon.cooldownID and iconSourceMap[icon.cooldownID]
    if sourceName == "BuffIconCooldownViewer" then
        prefix = "buff_"
    elseif not sourceName then
        -- fallback: 아직 iconSourceMap에 없는 경우 (최초 스캔 중)
        local parent = icon:GetParent()
        if parent == viewerRefs["BuffIconCooldownViewer"] then
            prefix = "buff_"
        end
    end

    return prefix .. spellInfo.name
end

-- ============================================================
-- SetupFrameInContainer (핵심: CDM 아이콘을 DDingUI 컨테이너로 이관)
-- [REPARENT] ArcUI SetupFrameInContainer 패턴 기반
-- ============================================================

function FrameController:SetupFrameInContainer(frame, container, targetW, targetH, cooldownID)
    if not frame or not container then return end

    -- 1. 원래 상태 저장 (최초 1회, GroupRenderer SaveOriginalState 패턴)
    if not frame._ddOrigState then
        frame._ddOrigState = {
            parent = frame:GetParent(),
            width = frame:GetWidth(),
            height = frame:GetHeight(),
            scale = frame:GetScale(),
            points = {},
        }
        local numPoints = frame:GetNumPoints()
        for i = 1, numPoints do
            local point, relTo, relPoint, x, y = frame:GetPoint(i)
            frame._ddOrigState.points[i] = { point, relTo, relPoint, x, y }
        end
    end

    -- 2. SetParent(UIParent) + 컨테이너 참조 저장 -- [REPARENT]
    -- Ayije CDM 패턴: 아이콘을 UIParent 자식으로 두고 컨테이너는 앵커 참조만
    -- → CDM Layout이 뷰어 기준으로 재배치해도 parent 계층에 영향 없음
    frame:SetParent(UIParent)
    frame._ddContainerRef = container
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(container:GetFrameLevel() + 10)

    -- 3. 스케일 강제 1
    frame._ddSettingScale = true
    frame:SetScale(1)
    frame._ddSettingScale = false

    -- 4. 타겟 크기 설정 + 적용
    frame._ddTargetWidth = targetW
    frame._ddTargetHeight = targetH
    frame._ddSettingSize = true
    frame:SetSize(targetW, targetH)
    frame._ddSettingSize = false

    -- 5. 프레임 훅 설치 (ClearAllPoints/SetScale/SetSize/SetFrameStrata snap-back)
    self:InstallFrameHooks(frame)

    -- 6. 관리 태그
    frame._ddLastCooldownID = cooldownID
    frame._ddIsManaged = true

    -- 7. 초기 위치 설정 — 앵커 없는 상태 방지 + HOOK snap-back 타겟 보장
    -- [REPARENT] 새 아이콘: container CENTER(0,0) 초기 위치
    -- 기존 아이콘: 이전 _ddTargetPoint 유지 (LayoutGroup이 최종 위치 갱신)
    if not frame._ddTargetPoint then
        frame._ddTargetPoint = "CENTER"
        frame._ddTargetRelPoint = "CENTER"
        frame._ddTargetX = 0
        frame._ddTargetY = 0
    end

    frame._ddSettingPosition = true
    frame:ClearAllPoints()
    frame:SetPoint(
        frame._ddTargetPoint,
        container,
        frame._ddTargetRelPoint or "CENTER",
        frame._ddTargetX or 0,
        frame._ddTargetY or 0
    )
    frame._ddSettingPosition = false

    -- 8. Alpha + Show -- [REPARENT]
    -- UIParent 자식이므로 컨테이너 숨김 상태를 수동 체크
    -- ScanCDMViewers에서 IsShown() 체크 완료 → 여기 도달 = CDM이 Show한 아이콘
    local sourceViewerName = cooldownID and iconSourceMap[cooldownID]
    local sourceViewer = sourceViewerName and _G[sourceViewerName]
    local viewerVisible = not sourceViewer or sourceViewer:IsShown()

    -- [FIX] alpha 리셋 — CDM 뷰어 alpha=0 은닉 또는 CDM 내부 로직에 의해
    -- 아이콘 alpha가 0으로 남아있을 수 있음 (re-parent해도 개별 alpha 유지)
    -- [FIX] BuffTrackerBar가 _ddingHidden으로 숨긴 프레임은 alpha 유지 (깜빡임 방지)
    if not frame._ddingHidden then
        frame:SetAlpha(1)
    end

    if container:IsShown() and viewerVisible then
        frame:Show()
    else
        frame:Hide()
    end

    -- [FIX] FlightHide 활성 중이면 새 아이콘도 알파 0 적용
    local fh = DDingUI.FlightHide
    if fh and fh.isActive then
        frame:SetAlpha(0)
    end
end

-- ============================================================
-- ReleaseFrameFromContainer (CDM 아이콘을 원래 상태로 복원)
-- ============================================================

function FrameController:ReleaseFrameFromContainer(frame)
    if not frame then return end

    local orig = frame._ddOrigState
    if not orig then return end

    -- 관리 태그 먼저 정리 — HOOK 6 (SetParent snap-back) 방지
    frame._ddIsManaged = nil

    -- [REPARENT] 원래 parent로 복원 (핵심 — CDM 뷰어로 되돌리기)
    if orig.parent then
        frame:SetParent(orig.parent)
    end

    -- 크기/스케일 복원
    frame._ddSettingSize = true
    frame:SetSize(orig.width, orig.height)
    frame._ddSettingSize = false

    frame._ddSettingScale = true
    frame:SetScale(orig.scale)
    frame._ddSettingScale = false

    -- 나머지 관리 태그 정리
    frame._ddTargetPoint = nil
    frame._ddTargetRelPoint = nil
    frame._ddTargetX = nil
    frame._ddTargetY = nil
    frame._ddTargetWidth = nil
    frame._ddTargetHeight = nil
    frame._ddContainerRef = nil  -- [REPARENT]
    frame._ddLastCooldownID = nil
    frame._ddOrigState = nil

    -- 포인트는 복원하지 않음 — CDM Layout()이 TriggerCDMRelayout 시 재배치할 것
end

-- ============================================================
-- 프레임 훅 설치 (Blizzard CDM 탈환 방지)
-- SetParent 후 CDM이 ClearAllPoints/SetScale/SetSize를 호출하면 snap-back
-- ============================================================

function FrameController:InstallFrameHooks(frame)
    if not frame then return end
    local addr = tostring(frame)
    if state.frameHooksInstalled[addr] then return end

    -- [HOOK 1] ClearAllPoints snap-back -- [REPARENT] _ddContainerRef 사용
    if not frame._fcClearPointsHooked then
        hooksecurefunc(frame, "ClearAllPoints", function(self)
            if self._ddSettingPosition then return end
            if not self._ddIsManaged then return end

            local container = self._ddContainerRef
            if container and self._ddTargetPoint then
                self._ddSettingPosition = true
                self:SetPoint(
                    self._ddTargetPoint,
                    container,
                    self._ddTargetRelPoint or "CENTER",
                    self._ddTargetX or 0,
                    self._ddTargetY or 0
                )
                self._ddSettingPosition = false
            end
        end)
        frame._fcClearPointsHooked = true
    end

    -- [HOOK 2] SetScale → force 1 -- [REPARENT] _ddIsManaged 체크
    if not frame._fcScaleHooked then
        hooksecurefunc(frame, "SetScale", function(self, scale)
            if self._ddSettingScale then return end
            if not self._ddIsManaged then return end

            -- secret value 방어
            if issecretvalue and issecretvalue(scale) then return end

            if math_abs((scale or 1) - 1) > 0.01 then
                self._ddSettingScale = true
                self:SetScale(1)
                self._ddSettingScale = false
            end
        end)
        frame._fcScaleHooked = true
    end

    -- [HOOK 3] SetSize → 타겟 사이즈 강제 -- [REPARENT] _ddIsManaged 체크
    if not frame._fcSizeHooked then
        hooksecurefunc(frame, "SetSize", function(self, w, h)
            if self._ddSettingSize then return end
            if not self._ddIsManaged then return end

            -- secret value 방어
            if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return end

            -- 타겟 사이즈가 설정되어 있고, CDM이 다른 값으로 변경하려 할 때
            local targetW = self._ddTargetWidth
            local targetH = self._ddTargetHeight
            if targetW and targetH then
                local dw = math_abs((w or 0) - targetW)
                local dh = math_abs((h or 0) - targetH)
                if dw > 0.5 or dh > 0.5 then
                    self._ddSettingSize = true
                    self:SetSize(targetW, targetH)
                    self._ddSettingSize = false
                end
            end
        end)
        frame._fcSizeHooked = true
    end

    -- [HOOK 4] SetFrameStrata → MEDIUM 강제 -- [REPARENT] _ddIsManaged 체크
    if not frame._fcStrataHooked then
        hooksecurefunc(frame, "SetFrameStrata", function(self, strata)
            if self._ddSettingStrata then return end

            if self._ddIsManaged and strata ~= "MEDIUM" then
                self._ddSettingStrata = true
                self:SetFrameStrata("MEDIUM")
                self._ddSettingStrata = false
            end
        end)
        frame._fcStrataHooked = true
    end

    -- [HOOK 5] SetPoint → CDM의 모든 재배치 시도를 snap-back -- [REPARENT]
    -- UIParent 자식이므로 CDM의 SetPoint(CENTER,viewer,...)는 뷰어 기준으로 이동시킴
    -- → _ddContainerRef 기준으로 즉시 복원
    if not frame._fcSetPointHooked then
        hooksecurefunc(frame, "SetPoint", function(self)
            if self._ddSettingPosition then return end
            if not self._ddIsManaged then return end

            local container = self._ddContainerRef
            if not container then return end
            if not self._ddTargetPoint then return end

            -- 우리 코드가 아닌 SetPoint → 우리 레이아웃 위치로 복원
            self._ddSettingPosition = true
            self:ClearAllPoints()
            self:SetPoint(
                self._ddTargetPoint,
                container,
                self._ddTargetRelPoint or "CENTER",
                self._ddTargetX or 0,
                self._ddTargetY or 0
            )
            self._ddSettingPosition = false
        end)
        frame._fcSetPointHooked = true
    end

    -- [HOOK 6] OnShow/OnHide → CDM이 아이콘을 Show/Hide하면 Reconcile 트리거
    -- 이미 OnAcquireItemFrame 등에서 전역 훅으로 설치했더라도 안전하게 중복 방지
    if not frame._fcShowHideHooked then
        frame:HookScript("OnShow", function(self)
            if not FrameController.initialized then return end
            ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
        end)
        frame:HookScript("OnHide", function(self)
            if not FrameController.initialized then return end
            ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
        end)
        frame._fcShowHideHooked = true
    end

    state.frameHooksInstalled[addr] = true
end

-- ============================================================
-- CDM 훅 설치 (NotifyListeners + OnAcquireItemFrame + SetCooldownID)
-- ============================================================

-- [FIX] hookedViewerLayout 재선언 제거 — L200의 선언을 공유하여 훅 중복 방지

local function InstallCDMHooks()
    if state.hooksInstalled then return end

    -- [HOOK A] LayoutManager.NotifyListeners — CDM 리빌드 감지 (핵심)
    if CooldownViewerSettings then
        local layoutMgr = CooldownViewerSettings:GetLayoutManager()
        if layoutMgr and layoutMgr.NotifyListeners then
            hooksecurefunc(layoutMgr, "NotifyListeners", function()
                if not FrameController.initialized then return end

                -- 컨텍스트에 따른 디바운스 시간 결정
                if state.specChangeDetected then
                    ScheduleReconcile(CONFIG.DEBOUNCE_SPEC)
                elseif state.talentChangeDetected then
                    ScheduleReconcile(CONFIG.DEBOUNCE_TALENT)
                else
                    ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
                end
            end)
        end
    end

    -- [HOOK B] CooldownViewerMixin.OnAcquireItemFrame — 새 프레임 생성 감지
    -- [FIX] 이미 managed 프레임이 re-acquire되면 즉시 re-parent + snap-back
    -- CDM OnAcquireItemFrame은 frame을 viewer 자식으로 만듦 → LayoutMixin이 C++ 레벨로
    -- 위치를 설정하면 hooksecurefunc 우회 → 디바운스(0.15s) 동안 CDM 위치에 보임
    -- 즉시 UIParent로 되돌리면 LayoutMixin 영향권에서 벗어남
    if CooldownViewerMixin and CooldownViewerMixin.OnAcquireItemFrame then
        hooksecurefunc(CooldownViewerMixin, "OnAcquireItemFrame", function(viewer, frame)
            if not FrameController.initialized then return end

            -- [FIX] EditMode의 테스트 프레임은 무시하여 Taint 및 에러 방지
            if frame and frame.isEditing then return end

            -- 이미 managed 프레임이면 즉시 re-parent (CDM이 viewer 자식으로 되돌린 것 복구)
            if frame and frame._ddIsManaged and frame._ddContainerRef then
                frame:SetParent(UIParent)
                frame:SetFrameStrata("MEDIUM")
                local container = frame._ddContainerRef
                if container then
                    frame:SetFrameLevel(container:GetFrameLevel() + 10)
                end

                -- snap-back: 이전 LayoutGroup 위치로 즉시 복원
                if frame._ddTargetPoint then
                    frame._ddSettingPosition = true
                    frame:ClearAllPoints()
                    frame:SetPoint(
                        frame._ddTargetPoint,
                        frame._ddContainerRef,
                        frame._ddTargetRelPoint or "CENTER",
                        frame._ddTargetX or 0,
                        frame._ddTargetY or 0
                    )
                    frame._ddSettingPosition = false
                end
            end

            -- 블리자드 CDM이 프레임을 풀에서 꺼낼 때 OnShow/OnHide를 미리 잡아둠
            -- 이렇게 해야 비관리 프레임이 out-of-combat에서 Show될 때 누락되지 않음
            if frame and not frame._fcShowHideHooked then
                frame:HookScript("OnShow", function(self)
                    if not FrameController.initialized then return end
                    ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
                end)
                frame:HookScript("OnHide", function(self)
                    if not FrameController.initialized then return end
                    ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
                end)
                frame._fcShowHideHooked = true
            end

            -- 이미 managed 프레임: snap-back으로 즉시 처리됨 → 일반 디바운스
            -- 새 프레임(프록 등): OnShow 수준의 짧은 debounce로 배치 대기
            if frame and frame._ddIsManaged then
                ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
            else
                ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
            end
        end)
    end

    -- [HOOK C] CooldownViewerItemDataMixin.SetCooldownID — 리셔플 감지
    if CooldownViewerItemDataMixin and CooldownViewerItemDataMixin.SetCooldownID then
        hooksecurefunc(CooldownViewerItemDataMixin, "SetCooldownID", function(itemFrame, cooldownID)
            if not FrameController.initialized then return end

            -- [FIX] EditMode의 테스트 프레임은 무시하여 Taint 에러 방지
            if itemFrame and itemFrame.isEditing then return end

            -- [FIX] 비관리 프레임에 대해서도 쿨다운 ID 변경 시 Reconcile 트리거해야
            -- 전투 외에 나타나는 버프를 정확한 시점에 hook 할 수 있음


            -- cooldownID 실제 변경 시에만 처리
            local prevCdID = itemFrame._ddLastCooldownID
            if prevCdID and prevCdID == cooldownID then return end
            itemFrame._ddLastCooldownID = cooldownID

            ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
        end)
    end

    -- [HOOK D] 뷰어별 Layout/Show/Hide (기존 CDMHookEngine 패턴 유지)
    for globalName, viewer in pairs(viewerRefs) do
        if not hookedViewerLayout[viewer] then
            hookedViewerLayout[viewer] = true
            hooksecurefunc(viewer, "Layout", function()
                if FrameController.initialized then
                    -- [FIX] Layout 후 managed 아이콘이 viewer 자식으로 복귀했는지 체크
                    -- CDM LayoutMixin이 C++로 위치를 설정하면 hooksecurefunc 우회됨
                    -- 즉시 UIParent로 re-parent하여 다음 Layout에서 영향 안 받게 함
                    if viewer.itemFramePool then
                        for icon in viewer.itemFramePool:EnumerateActive() do
                            if icon._ddIsManaged and icon._ddContainerRef then
                                local parent = icon:GetParent()
                                if parent and parent ~= UIParent then
                                    icon:SetParent(UIParent)
                                    icon:SetFrameStrata("MEDIUM")
                                    local container = icon._ddContainerRef
                                    if container then
                                        icon:SetFrameLevel(container:GetFrameLevel() + 10)
                                    end
                                    -- snap-back
                                    if icon._ddTargetPoint then
                                        icon._ddSettingPosition = true
                                        icon:ClearAllPoints()
                                        icon:SetPoint(
                                            icon._ddTargetPoint,
                                            icon._ddContainerRef,
                                            icon._ddTargetRelPoint or "CENTER",
                                            icon._ddTargetX or 0,
                                            icon._ddTargetY or 0
                                        )
                                        icon._ddSettingPosition = false
                                    end
                                end
                            end
                        end
                    end
                    ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
                end
            end)
            hooksecurefunc(viewer, "Show", function()
                if FrameController.initialized then
                    ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
                end
            end)
            hooksecurefunc(viewer, "Hide", function()
                if FrameController.initialized then
                    ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
                end
            end)
        end
    end

    state.hooksInstalled = true
end

-- ============================================================
-- 공개 API: 맵 조회 (기존 CDMHookEngine 호환)
-- ============================================================

function FrameController:GetIconMap()
    return idIconMap
end

function FrameController:GetIconFrame(cooldownID)
    return idIconMap[cooldownID]
end

function FrameController:GetIconSource(cooldownID)
    return iconSourceMap[cooldownID]
end

function FrameController:GetSpellNameForID(cooldownID)
    return iconSpellNameMap[cooldownID]
end

function FrameController:GetDefaultGroupForViewer(globalName)
    for _, def in pairs(CDM_VIEWERS) do
        if def.globalName == globalName then
            return def.defaultGroup
        end
    end
    return nil
end

function FrameController:GetViewerDefs()
    return CDM_VIEWERS
end

function FrameController:GetViewerRef(globalName)
    return viewerRefs[globalName]
end

function FrameController:IsProcessing()
    return state.isProcessing
end

-- [FIX] 스펙 변경 진행 중인지 외부 조회 (GroupInit에서 빈 그룹 숨김 방지용)
function FrameController:IsSpecChangePending()
    return state.specChangeDetected or false
end

-- ============================================================
-- 옵저버 패턴
-- ============================================================

function FrameController:RegisterCallback(func)
    self._callbacks[#self._callbacks + 1] = func
end

function FrameController:NotifyUpdate()
    for _, cb in pairs(self._callbacks) do
        local ok, err = pcall(cb, "reconcile")
        if not ok then
            -- 콜백 에러 무시 (안전성)
        end
    end
end

-- ============================================================
-- 편집모드: Ctrl+Click 그룹 재배치
-- ============================================================

function FrameController:EnableEditModeClicks()
    self._editMode = true
    for globalName, viewer in pairs(viewerRefs) do
        if viewer.itemFramePool then
            for icon in viewer.itemFramePool:EnumerateActive() do
                if not InCombatLockdown() then
                    icon:SetPropagateMouseClicks(true)
                else
                    tinsert(self._postCombatQueue, function()
                        icon:SetPropagateMouseClicks(true)
                    end)
                end
                icon:SetMouseClickEnabled(true)
                icon:SetMouseMotionEnabled(true)

                -- 클릭 핸들러 (중복 방지)
                if not icon._gsClickHooked then
                    icon._gsClickHooked = true
                    icon:SetScript("OnMouseDown", function(self, button)
                        if not FrameController._editMode then return end
                        if button == "LeftButton" and IsControlKeyDown() then
                            FrameController:ShowGroupAssignPopup(self)
                        end
                    end)
                end
            end
        end
    end
end

function FrameController:DisableEditModeClicks()
    self._editMode = false
    for globalName, viewer in pairs(viewerRefs) do
        if viewer.itemFramePool then
            for icon in viewer.itemFramePool:EnumerateActive() do
                if not InCombatLockdown() then
                    icon:SetPropagateMouseClicks(false)
                else
                    tinsert(self._postCombatQueue, function()
                        icon:SetPropagateMouseClicks(false)
                    end)
                end
                icon:SetMouseClickEnabled(false)
                icon:SetMouseMotionEnabled(false)
            end
        end
    end
end

-- ============================================================
-- 그룹 선택 팝업 (EasyMenu)
-- ============================================================

local menuFrame = CreateFrame("Frame", "DDingUI_GroupAssignMenu", UIParent, "UIDropDownMenuTemplate")

function FrameController:ShowGroupAssignPopup(icon)
    if not icon or not icon.cooldownID then return end

    local spellName = self:GetSpellNameForID(icon.cooldownID) or self:GetSpellName(icon)
    if not spellName then return end

    local GroupManager = DDingUI.GroupManager
    if not GroupManager then return end

    local groups = GroupManager:GetGroups()
    local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

    local menuList = {
        {
            text = spellName,
            isTitle = true,
            notCheckable = true,
        },
        {
            text = L["Auto (Default)"] or "자동 (기본)",
            notCheckable = true,
            func = function()
                GroupManager:UnassignSpell(spellName)
                if DDingUI.GroupSystem then
                    DDingUI.GroupSystem:Refresh()
                end
            end,
        },
    }

    for _, group in ipairs(groups) do
        tinsert(menuList, {
            text = group.name,
            notCheckable = true,
            func = function()
                GroupManager:AssignSpell(spellName, group.name)
                if DDingUI.GroupSystem then
                    DDingUI.GroupSystem:Refresh()
                end
            end,
        })
    end

    EasyMenu(menuList, menuFrame, "cursor", 0, 0, "MENU")
end

-- ============================================================
-- 초기화 / 종료
-- ============================================================

function FrameController:Initialize()
    if self.initialized then return true end

    -- CMI 충돌 감지
    if _G.CooldownManagerInfiniteDB or (C_AddOns and C_AddOns.IsAddOnLoaded("CooldownManagerInfinite")) then
        if DDingUI.Print then
            DDingUI:Print("|cffff4444[GroupSystem]|r CooldownManagerInfinite detected. Conflicts may occur.")
        end
    end

    -- 뷰어 탐색
    local found = FindViewers()
    if found == 0 then
        return false -- 뷰어 미로드
    end

    -- CDM 훅 설치 (NotifyListeners + OnAcquireItemFrame + SetCooldownID + Layout/Show/Hide)
    InstallCDMHooks()

    -- 초기 맵 빌드
    self:ScanCDMViewers()

    -- 전투 해제 시 대기열 실행
    local regenFrame = CreateFrame("Frame")
    regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    regenFrame:SetScript("OnEvent", function()
        for _, fn in pairs(FrameController._postCombatQueue) do
            pcall(fn)
        end
        wipe(FrameController._postCombatQueue)
    end)
    self._regenFrame = regenFrame

    -- 전문화 변경 이벤트
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_LEVEL_UP")  -- [FIX] 레벨업 시 CDM 뷰어 재생성 감지
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- [FIX] 전투 진입 시 즉시 재스캔
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if not FrameController.initialized then return end

        if event == "PLAYER_REGEN_DISABLED" then
            -- [FIX] 전투 진입 시 CDM이 아이콘을 Show하므로 burst 재시작
            -- 첫 전투 시 강화효과 정렬 지연 방지
            MarkDirty()
            if not state.pollingActive then
                EnablePolling()
            end
            return

        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LEVEL_UP" then
            state.specChangeDetected = true
            wipe(iconSpellNameMap) -- 캐시 초기화
            ScheduleReconcile(CONFIG.DEBOUNCE_SPEC)

            -- [FIX] CDM이 뷰어를 재생성할 시간 대기 후 참조 갱신 + 앵커 재적용
            C_Timer.After(1.5, function()
                if not FrameController.initialized then return end
                FrameController:RefreshViewerRefs()

                -- [FIX] _viewerHidden 강제 리셋
                -- CDM 뷰어 재생성 시 기존 OnHide 훅으로 _viewerHidden=true가 남아
                -- LayoutGroup이 영구 차단되는 것을 방지
                local gr = DDingUI.GroupRenderer
                if gr and gr.groupFrames then
                    for _, frame in pairs(gr.groupFrames) do
                        if frame._viewerHidden then
                            frame._viewerHidden = false
                        end
                    end
                end

                -- GroupSystem 앵커 재적용 (그룹 프레임 → 뷰어 앵커 갱신)
                if DDingUI.GroupSystem and DDingUI.GroupSystem.enabled then
                    DDingUI.GroupSystem:Refresh()
                end
                -- 매핑 모듈 위치 재적용 (시전바 등 → 그룹 프레임 앵커 갱신)
                if DDingUI.Movers and DDingUI.Movers.ReloadMappedModulePositions then
                    DDingUI.Movers:ReloadMappedModulePositions()
                end
            end)
            -- 안정화 패스: CDM Layout이 지연될 수 있으므로
            C_Timer.After(3.0, function()
                if not FrameController.initialized then return end
                FrameController:RefreshViewerRefs()

                -- [FIX] 안정화 패스에서도 _viewerHidden 리셋
                local gr = DDingUI.GroupRenderer
                if gr and gr.groupFrames then
                    for _, frame in pairs(gr.groupFrames) do
                        if frame._viewerHidden then
                            frame._viewerHidden = false
                        end
                    end
                end

                -- [FIX] 안정화 패스에서도 Refresh 호출
                if DDingUI.GroupSystem and DDingUI.GroupSystem.enabled then
                    DDingUI.GroupSystem:Refresh()
                end
            end)

        elseif event == "TRAIT_CONFIG_UPDATED" then
            -- 전문화 변경 중이면 무시 (SPEC이 처리)
            if state.specChangeDetected then return end
            state.talentChangeDetected = true
            wipe(iconSpellNameMap)
            ScheduleReconcile(CONFIG.DEBOUNCE_TALENT)

        elseif event == "SPELLS_CHANGED" then
            ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
        end
    end)
    self._eventFrame = eventFrame

    self.initialized = true
    self._initTime = GetTime() -- [DIAG] 진단 시간 기준점

    -- [Ayije 패턴] OnUpdate 폴링 시작 — CDM 아이콘 상태를 자동 감지
    -- 초기화 직후 burst 모드로 빠르게 스캔 → 안정화 후 watchdog → idle 비활성화
    EnablePolling()

    return true
end

function FrameController:Shutdown()
    self.initialized = false

    -- 이벤트 프레임 정리
    if self._regenFrame then
        self._regenFrame:UnregisterAllEvents()
        self._regenFrame = nil
    end
    if self._eventFrame then
        self._eventFrame:UnregisterAllEvents()
        self._eventFrame = nil
    end

    -- 폴링/디바운스 리셋
    self:DisablePolling()
    state.pendingReconcile = false
    state.specChangeDetected = false
    state.talentChangeDetected = false
    state.isProcessing = false
    state.reconcileCount = 0

    -- 편집모드 해제
    self:DisableEditModeClicks()

    -- 맵 정리
    wipe(idIconMap)
    wipe(iconSourceMap)
    wipe(iconSpellNameMap)
    wipe(self._callbacks)
    wipe(self._postCombatQueue)
    -- frameHooksInstalled는 wipe하지 않음 (hooksecurefunc는 제거 불가)
end

-- ============================================================
-- 수동 Reconcile 트리거 (외부에서 호출 가능)
-- ============================================================

function FrameController:ForceReconcile()
    if not self.initialized then return end
    state.reconcileCount = 0
    self._initTime = GetTime() -- [DIAG] 진단 리셋 (15초간 다시 출력)
    ScheduleReconcile(0) -- 즉시
end
