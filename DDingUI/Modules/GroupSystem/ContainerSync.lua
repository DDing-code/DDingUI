-- [GROUP SYSTEM] ContainerSync: CDM 뷰어 ↔ DDingUI 컨테이너 동기화
-- [REPARENT] SetParent 후 빈 CDM 뷰어를 은닉하고, Blizzard 탈환 시 snap-back
-- ArcUI CDMContainerSync 패턴 기반 — Push 방식, hooksecurefunc only
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local ContainerSync = {}
DDingUI.ContainerSync = ContainerSync

-- ============================================================
-- Locals
-- ============================================================

local pairs = pairs
local wipe = wipe
local math_abs = math.abs
local pcall = pcall
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

-- ============================================================
-- CDM 뷰어 이름
-- ============================================================

local CDM_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

-- ============================================================
-- State
-- ============================================================

local viewerState = {}  -- [viewerName] = { hidden, origW, origH, origPoints }
local pushing = false   -- true while we are setting viewer properties
local hooksInstalled = setmetatable({}, { __mode = "k" }) -- [viewer object] = true (weak key, 뷰어 재생성 대응)
local snapPending = {}  -- [viewerName] = true (debounce)
local initialized = false

-- ============================================================
-- Helpers
-- ============================================================

-- [FIX] Blizzard Edit Mode만 감지 (CDM 뷰어 표시 기준)
-- DDingUI Mover 모드에서는 CDM 뷰어를 숨긴 채 유지
local function IsInBlizzardEditMode()
    return EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
end

-- 뷰어별 관리 아이콘 수 계산 -- [REPARENT]
-- SetParent 후에도 itemFramePool:EnumerateActive()는 동작 (ObjectPool은 parent 무관)
local function CountManagedIcons(viewerName)
    local viewer = _G[viewerName]
    if not viewer or not viewer.itemFramePool then return 0, 0 end

    local total = 0
    local managed = 0
    for icon in viewer.itemFramePool:EnumerateActive() do
        total = total + 1
        if icon._ddIsManaged then
            managed = managed + 1
        end
    end
    return managed, total
end

-- 뷰어 원래 상태 저장
local function SaveViewerState(viewerName)
    if viewerState[viewerName] then return end

    local viewer = _G[viewerName]
    if not viewer then return end

    local state = {
        hidden = false,
        origW = viewer:GetWidth(),
        origH = viewer:GetHeight(),
        origPoints = {},
    }

    local numPoints = viewer:GetNumPoints()
    for i = 1, numPoints do
        local point, relTo, relPoint, x, y = viewer:GetPoint(i)
        state.origPoints[i] = { point, relTo, relPoint, x, y }
    end

    viewerState[viewerName] = state
end

-- ============================================================
-- 뷰어 은닉 / 복원
-- [REFACTOR] alpha=0만 사용 (크기/위치 불변)
-- 이유: 1x1 축소 시 CDM이 오버플로우로 아이콘을 숨겨서 스캔 누락 발생
--       alpha=0이면 CDM Layout은 정상 동작, 뷰어만 안 보임
-- ============================================================

local function HideViewer(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end
    -- [REFACTOR] SetAlpha는 보호 함수가 아님 → 전투 중에도 안전
    local state = viewerState[viewerName]
    if not state then return end
    if state.hidden then return end

    pushing = true
    viewer:SetAlpha(0)
    -- [FIX] 마우스 차단 해제 — 숨겨진 뷰어 + 자식 아이콘이 앵커 클릭을 가로막는 문제 방지
    viewer:EnableMouse(false)
    if viewer.EnableMouseWheel then viewer:EnableMouseWheel(false) end
    -- [FIX] itemFramePool 순회 — SetParent(UIParent)된 관리 아이콘도 포함
    if viewer.itemFramePool then
        for icon in viewer.itemFramePool:EnumerateActive() do
            if icon.EnableMouse then icon:EnableMouse(false) end
        end
    end
    pushing = false

    state.hidden = true
end

local function ShowViewer(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end

    local state = viewerState[viewerName]
    if not state then return end
    if not state.hidden then return end

    pushing = true
    viewer:SetAlpha(1)
    -- [FIX] 마우스 복원 — Edit Mode에서 뷰어 조작 가능
    viewer:EnableMouse(true)
    if viewer.EnableMouseWheel then viewer:EnableMouseWheel(true) end
    -- [FIX] itemFramePool 순회 — SetParent(UIParent)된 관리 아이콘도 포함
    if viewer.itemFramePool then
        for icon in viewer.itemFramePool:EnumerateActive() do
            if icon.EnableMouse then icon:EnableMouse(true) end
        end
    end
    pushing = false

    state.hidden = false
end

-- ============================================================
-- Snap-back: Blizzard가 뷰어를 변경하면 다시 은닉 -- [REPARENT]
-- ============================================================

local function ScheduleSnapBack(viewerName)
    if snapPending[viewerName] then return end
    snapPending[viewerName] = true

    C_Timer.After(0, function()
        snapPending[viewerName] = false

        if not initialized then return end
        if IsInBlizzardEditMode() then return end
        -- [REFACTOR] InCombatLockdown 제거: SetAlpha는 보호 함수가 아님

        local state = viewerState[viewerName]
        if not state or not state.hidden then return end

        local viewer = _G[viewerName]
        if not viewer then return end

        -- [REFACTOR] alpha 확인 (크기/위치는 안 건드리므로)
        if viewer:GetAlpha() > 0.01 then
            HideViewer(viewerName)
        end
    end)
end

-- ============================================================
-- 뷰어 훅 설치 (hooksecurefunc — 절대 함수 교체 안 함) -- [REPARENT]
-- ============================================================

local function SetupViewerHooks(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end

    -- [FIX] 뷰어 객체 자체를 키로 사용 → 재생성된 새 뷰어에도 훅 설치 가능
    if hooksInstalled[viewer] then return end

    hooksInstalled[viewer] = true

    -- [HOOK 1] SetSize → 은닉 상태에서 Blizzard가 크기 변경 시 snap-back
    hooksecurefunc(viewer, "SetSize", function()
        if pushing then return end
        if IsInBlizzardEditMode() then return end
        local state = viewerState[viewerName]
        if state and state.hidden then
            ScheduleSnapBack(viewerName)
        end
    end)

    -- [HOOK 2] SetPoint → 은닉 상태에서 Blizzard가 위치 변경 시 snap-back
    hooksecurefunc(viewer, "SetPoint", function()
        if pushing then return end
        if IsInBlizzardEditMode() then return end
        local state = viewerState[viewerName]
        if state and state.hidden then
            ScheduleSnapBack(viewerName)
        end
    end)

    -- [HOOK 3] RefreshLayout → Layout의 근원 — snap-back
    if viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", function()
            if pushing then return end
            if IsInBlizzardEditMode() then return end
            local state = viewerState[viewerName]
            if state and state.hidden then
                ScheduleSnapBack(viewerName)
            end
        end)
    end

    -- [HOOK 4] SetIsEditing → Edit Mode 진입/퇴장 대응
    if viewer.SetIsEditing then
        hooksecurefunc(viewer, "SetIsEditing", function(_, editing)
            if pushing then return end
            if not editing then
                -- Edit Mode 퇴장 → 다시 동기화
                C_Timer.After(0.3, function()
                    if initialized then
                        ContainerSync:SyncViewer(viewerName)
                    end
                end)
            end
        end)
    end

    -- [HOOK 5] SetAlpha → 은닉 상태에서 CDM이 alpha 변경 시 즉시 snap-back
    -- 로그인 직후 CDM이 뷰어 alpha를 1로 리셋 → 아이콘이 CDM 위치에서 잠깐 보이는 문제 방지
    hooksecurefunc(viewer, "SetAlpha", function(_, alpha)
        if pushing then return end
        if IsInBlizzardEditMode() then return end
        -- secret value 방어
        if issecretvalue and issecretvalue(alpha) then return end
        local state = viewerState[viewerName]
        if state and state.hidden and type(alpha) == "number" and alpha > 0.01 then
            pushing = true
            viewer:SetAlpha(0)
            pushing = false
        end
    end)

    -- [HOOK 6] UpdateShownState → 보이기 상태 변경 대응
    if viewer.UpdateShownState then
        hooksecurefunc(viewer, "UpdateShownState", function()
            if pushing then return end
            if IsInBlizzardEditMode() then return end
            local state = viewerState[viewerName]
            if state and state.hidden then
                ScheduleSnapBack(viewerName)
            end
        end)
    end

    -- [HOOK 7] OnShow/OnHide → 그룹 프레임 표시 상태 동기화
    -- CDM이 뷰어를 Show/Hide하면 (전투 진입/퇴장 등) 그룹 프레임에 전파
    -- ContainerSync는 alpha=0만 사용하므로 CDM의 Show/Hide는 독립적
    viewer:HookScript("OnShow", function()
        if pushing then return end
        if IsInBlizzardEditMode() then return end
        C_Timer.After(0, function()
            if initialized and DDingUI.GroupRenderer and DDingUI.GroupRenderer.SyncViewerVisibility then
                DDingUI.GroupRenderer:SyncViewerVisibility(viewerName)
            end
        end)
    end)

    viewer:HookScript("OnHide", function()
        if pushing then return end
        if IsInBlizzardEditMode() then return end
        C_Timer.After(0, function()
            if initialized and DDingUI.GroupRenderer and DDingUI.GroupRenderer.SyncViewerVisibility then
                DDingUI.GroupRenderer:SyncViewerVisibility(viewerName)
            end
        end)
    end)
end

-- ============================================================
-- 조회 API (ViewerLayout 등 외부 모듈용) -- [REPARENT]
-- ============================================================

-- 뷰어가 ContainerSync에 의해 은닉 상태인지 조회
ContainerSync._isViewerHidden = function(viewerName)
    local state = viewerState[viewerName]
    return state and state.hidden or false
end

-- ============================================================
-- 동기화 API -- [REPARENT]
-- ============================================================

-- 단일 뷰어 동기화
-- [FIX] GroupSystem 활성 시 스캔 대상 뷰어는 항상 숨김 (alpha=0)
-- managed 0→1 전환 시 뷰어가 잠깐 보이는 플래시 방지
-- DDingUI에서 비활성화된 뷰어만 원래 상태 유지
function ContainerSync:SyncViewer(viewerName)
    if not initialized then return end

    -- [FIX] GroupSystem이 활성이고 hideDefaultViewers가 true이면
    -- 개별 viewers.enabled 상태와 무관하게 항상 숨김
    -- 구 프로필에서 viewers.BuffIconCooldownViewer.enabled = false일 때
    -- ShowViewer로 CDM이 보이던 버그 수정
    local profile = DDingUI.db and DDingUI.db.profile
    local gs = profile and profile.groupSystem
    if gs and gs.enabled and gs.hideDefaultViewers ~= false then
        HideViewer(viewerName)
    else
        -- GroupSystem 비활성 또는 hideDefaultViewers = false → 기존 로직
        local vp = profile and profile.viewers and profile.viewers[viewerName]
        if vp and vp.enabled == false then
            ShowViewer(viewerName)
            return
        end
        HideViewer(viewerName)
    end

    -- 미관리 아이콘이 있으면 FrameController에게 재스캔 요청
    local managed, total = CountManagedIcons(viewerName)
    if managed > 0 and managed < total then
        local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
        if fc and fc.ForceReconcile then
            C_Timer.After(0.3, function()
                if initialized and not IsInBlizzardEditMode() then
                    fc:ForceReconcile()
                end
            end)
        end
    end
end

-- 전체 동기화
function ContainerSync:SyncAll()
    if not initialized then return end
    if IsInBlizzardEditMode() then return end

    for _, viewerName in pairs(CDM_VIEWER_NAMES) do
        self:SyncViewer(viewerName)
    end
end

-- 단일 뷰어 복원
function ContainerSync:RestoreViewer(viewerName)
    ShowViewer(viewerName)
end

-- 전체 복원
function ContainerSync:RestoreAll()
    for _, viewerName in pairs(CDM_VIEWER_NAMES) do
        ShowViewer(viewerName)
    end
end

-- ============================================================
-- Edit Mode 대응 -- [REPARENT]
-- ============================================================

-- Blizzard Edit Mode 진입/퇴장 훅
if EditModeManagerFrame then
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if not initialized then return end
        -- Edit Mode 진입 → 뷰어 복원 (Blizzard가 조작할 수 있게)
        pushing = true
        C_Timer.After(0.1, function()
            pushing = false
            for _, viewerName in pairs(CDM_VIEWER_NAMES) do
                ShowViewer(viewerName)
            end
        end)
    end)

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        if not initialized then return end
        -- Edit Mode 퇴장 → FrameController 재스캔 + 뷰어 동기화
        -- [REPARENT] 편집모드 중 CDM이 아이콘을 재배치했을 수 있으므로 ForceReconcile
        local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
        if fc and fc.ForceReconcile then
            C_Timer.After(0.2, function()
                if initialized and not IsInBlizzardEditMode() then
                    fc:ForceReconcile()
                end
            end)
        end
        C_Timer.After(0.5, function()
            if initialized and not IsInBlizzardEditMode() then
                ContainerSync:SyncAll()
            end
        end)
    end)
end

-- ============================================================
-- 전투 안전: 전투 종료 후 재동기화 -- [REPARENT]
-- ============================================================

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if not initialized then return end
    if IsInBlizzardEditMode() then return end
    C_Timer.After(0.1, function()
        if initialized then
            ContainerSync:SyncAll()
        end
    end)
end)

-- ============================================================
-- 초기화 / 종료 -- [REPARENT]
-- ============================================================

function ContainerSync:Initialize()
    if initialized then return end

    -- 뷰어 상태 저장 + 훅 설치
    for _, viewerName in pairs(CDM_VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            SaveViewerState(viewerName)
            SetupViewerHooks(viewerName)
        end
    end

    initialized = true

    -- [FIX] 초기화 시 즉시 숨김 → 로딩 중 뷰어 깜빡거림 방지
    self:SyncAll()

    -- [FIX] 블리자드 CDM이 뷰어를 재생성하는 동안 발생하는 플래커(Flicker) 방지
    -- 뷰어가 재생성되면 새로 만들어진 객체는 alpha=1로 설정되어 화면에 나타납니다.
    -- RefreshViewers가 0.5초 뒤에 훅을 재설치하기 전까지 이 프레임들이 노출되는 것을 막기 위해
    -- 로딩 초기 3초간 OnUpdate로 매우 적극적으로 alpha=0을 강제합니다.
    local profile = DDingUI.db and DDingUI.db.profile
    local gs = profile and profile.groupSystem
    local hideDefault = gs and gs.enabled and gs.hideDefaultViewers ~= false
    
    if hideDefault then
        local enforceTicks = 0
        local enforceThrottle = 0  -- [PERF] 매 프레임 → 0.1초 스로틀
        local enforceFrame = CreateFrame("Frame")
        enforceFrame:SetScript("OnUpdate", function(self, elapsed)
            enforceTicks = enforceTicks + elapsed
            if enforceTicks > 3.0 then
                self:SetScript("OnUpdate", nil)
                return
            end
            -- [PERF] 0.1초 간격으로만 alpha 검사 (매 프레임 → ~10fps)
            enforceThrottle = enforceThrottle + elapsed
            if enforceThrottle < 0.1 then return end
            enforceThrottle = 0
            for _, viewerName in pairs(CDM_VIEWER_NAMES) do
                local viewer = _G[viewerName]
                if viewer and viewer:GetAlpha() > 0.01 then
                    viewer:SetAlpha(0)
                end
            end
        end)
    end

    -- 안정화 패스 (CDM 지연 Layout 대응)
    for _, delay in pairs({ 1, 3 }) do
        C_Timer.After(delay, function()
            if initialized then
                self:SyncAll()
            end
        end)
    end
end

-- [FIX] 뷰어 재생성 시 훅 재설치 + 상태 재동기화
-- CDMHookEngine:RefreshViewers()에서 호출
function ContainerSync:RefreshViewerHooks()
    if not initialized then return end
    for _, viewerName in pairs(CDM_VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer and not hooksInstalled[viewer] then
            SaveViewerState(viewerName)
            SetupViewerHooks(viewerName)
        end
    end
    self:SyncAll()
end

function ContainerSync:Shutdown()
    if not initialized then return end
    initialized = false

    -- 모든 뷰어 복원
    self:RestoreAll()

    -- 상태 정리
    wipe(viewerState)
    wipe(snapPending)
    -- hooksInstalled는 wipe하지 않음 (hooksecurefunc는 제거 불가)
end
