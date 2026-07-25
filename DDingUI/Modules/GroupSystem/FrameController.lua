-- [GROUP SYSTEM] FrameController: CDM 리빌드 감지 + Reconcile + 프레임 훅 엔진
-- [REFACTOR] CDMHookEngine.lua 대체 — DDingUI FrameController 패턴 기반
-- NotifyListeners 훅으로 CDM 리빌드 즉시 감지, 디바운스 Reconcile로 안정적 처리
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end
local SL = _G.DDingUI_StyleLib

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
local canaccessvalue = canaccessvalue

-- [CDM 패턴] IsSafeNumber: secret value 안전 검증
local function IsSafeNumber(value)
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then
        return false
    end
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return false
    end
    return type(value) == "number"
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
-- 디바운스 설정 (DDingUI 검증 타이밍)
-- ============================================================

local CONFIG = {
    -- 특성/전문화 변경 지연 (CDM이 여러 번 리빌드)
    DEBOUNCE_TALENT   = 0.6,
    DEBOUNCE_SPEC     = 1.0,
    DEBOUNCE_NORMAL   = 0.15,  -- ScheduleReconcile 하위 호환용
    DEBOUNCE_ONSHOW   = 0.05,  -- [FIX] OnShow/OnHide 디바운스 (기존 nil → 즐시 실행 버그 수정)
    SCAN_EMPTY_GRACE  = 2,     -- 일시적인 빈 스캔을 바로 확정하지 않음
    SCAN_PARTIAL_GRACE = 1,    -- 렉/전환 중 부분 스캔 보호
    RETRY_DELAY       = 0.08,
}

-- ============================================================
-- 런타임 맵
-- ============================================================

local function ResetGroupIconLayoutState(frame, resetTarget)
    if not frame then return end
    local gr = DDingUI.GroupRenderer
    if gr and gr.ResetIconLayoutState then
        gr:ResetIconLayoutState(frame, resetTarget)
        return
    end
    frame._ddLastGroupLayoutHash = nil
    frame._ddCurrentContainer = nil
    frame._ddCurrentX = nil
    frame._ddCurrentY = nil
    frame._ddPositionMotion = nil
    if resetTarget then
        frame._ddTargetPoint = nil
        frame._ddTargetRelPoint = nil
        frame._ddTargetX = nil
        frame._ddTargetY = nil
    end
end

local function InvalidateGroupLayoutCaches(resetTargets)
    local gr = DDingUI.GroupRenderer
    if gr and gr.InvalidateLayoutCaches then
        gr:InvalidateLayoutCaches(resetTargets == true)
    end
end

local idIconMap = {}        -- [cooldownID] = CDM icon frame
local iconSourceMap = {}    -- [cooldownID] = viewerGlobalName
local iconSpellNameMap = {} -- [cooldownID] = spellName (캐시)
local iconStateMap = {}     -- [cooldownID] = source visibility
local iconLayoutIndexMap = {} -- [cooldownID] = accessible layout index
local trackedBuffSpellNames = {}
local trackedBuffSpellOrder = {}
local trackedBuffSpellTextures = {}
local viewerRefs = {}       -- [globalName] = viewer frame reference

-- ============================================================
-- State
-- ============================================================

FrameController.initialized = false
FrameController._callbacks = {}
FrameController._editMode = false
FrameController._postCombatQueue = {}

-- [DEBUG] /ddbufflog 토글
local _debugLog = false
local function DLog(...)
    if _debugLog then print("|cff88ccff[FC]|r", ...) end
end
-- GroupRenderer 등에서 접근 가능하도록 노출
FrameController._DLog = DLog
FrameController._isDebugLog = function() return _debugLog end
SLASH_DDBUFFLOG1 = "/ddbufflog"
SlashCmdList["DDBUFFLOG"] = function()
    _debugLog = not _debugLog
    print("|cff00ff00[DDingUI] BuffLog:", _debugLog and "ON" or "OFF", "|r")
end

-- [DEBUG] /ddbuffwatch: 매 프레임 managed 아이콘 가시성 모니터
local _watchFrame = CreateFrame("Frame")
local _watchActive = false
local _watchState = {}  -- [frame] = {shown, alpha, parent, numPts, texShown, texAlpha}
SLASH_DDBUFFWATCH1 = "/ddbuffwatch"
SlashCmdList["DDBUFFWATCH"] = function()
    _watchActive = not _watchActive
    if _watchActive then
        wipe(_watchState)
        _watchFrame:SetScript("OnUpdate", function()
            for cdID, icon in pairs(idIconMap) do
                if icon._ddIsManaged then
                    local shown = icon:IsShown()
                    local alpha = icon:GetAlpha()
                    local p = icon:GetParent()
                    local pname = p and p:GetName() or "nil"
                    local nPts = icon:GetNumPoints()
                    local w, h = icon:GetWidth(), icon:GetHeight()
                    local iconTex = icon.icon or icon.Icon
                    local texShown = iconTex and iconTex:IsShown()
                    local texAlpha = iconTex and iconTex:GetAlpha()
                    local texW = iconTex and iconTex:GetWidth() or 0

                    local wasVisible = _watchState[icon]
                    local isVisible = shown and alpha > 0.01 and nPts > 0 and w > 1

                    if wasVisible and not isVisible then
                        print(string.format(
                            "|cffff0000[WATCH] LOST|r %s: shown=%s alpha=%.2f parent=%s pts=%d w=%.0f h=%.0f tex=%s texA=%.2f texW=%.0f",
                            tostring(cdID), tostring(shown), alpha, pname,
                            nPts, w, h,
                            tostring(texShown), texAlpha or -1, texW
                        ))
                    end

                    _watchState[icon] = isVisible
                end
            end
        end)
        print("|cff00ff00[DDingUI] BuffWatch: ON (per-frame monitoring)|r")
    else
        _watchFrame:SetScript("OnUpdate", nil)
        wipe(_watchState)
        print("|cff00ff00[DDingUI] BuffWatch: OFF|r")
    end
end

local state = {
    hooksInstalled = false,
    frameHooksInstalled = {},  -- [frameAddress] = true (중복 훅 방지)
    dirty = false,
    reconcileDueAt = 0,
    pollingActive = false,
    forceNotify = false,
    -- 이벤트 플래그
    specChangeDetected = false,
    talentChangeDetected = false,
    isProcessing = false,
    pendingReconcile = false,  -- Reconcile() 내부 호환용
    scanCompleted = false,     -- [PERF] Reconcile 내 ScanCDMViewers 완료 플래그 (이중 스캔 방지)
    specChangeVersion = 0,      -- stale delayed refresh guard
    emptyScanStreak = 0,
    partialScanStreak = 0,
    scanHoldActive = false,
    scanHoldStartedAt = 0,
    lastAcceptedScanCount = 0,
    lastPvPInstance = nil,
    acquireSerial = 0,
    -- 통계
    reconcileCount = 0,
}
FrameController._diagCounters = { activeStateChanged = 0, cooldownIDSet = 0, poolRelease = 0 }

-- ============================================================
-- Reconcile requests share one frame driver. The driver exists only while
-- work is pending and runs once after the current CDM update has settled.
-- ============================================================

local pollingFrame = CreateFrame("Frame")

local function MarkDirty(delay, forceNotify)
    if state.specChangeDetected or state.talentChangeDetected then return end
    local now = GetTime()
    local dueAt = now + (type(delay) == "number" and math.max(delay, 0) or CONFIG.DEBOUNCE_NORMAL)
    if state.isProcessing then
        state.pendingReconcile = true
        state.forceNotify = state.forceNotify or forceNotify == true
        return
    end
    state.dirty = true
    state.forceNotify = state.forceNotify or forceNotify == true
    if state.reconcileDueAt == 0 or dueAt < state.reconcileDueAt then
        state.reconcileDueAt = dueAt
    end
end

-- 폴링 활성화 (전방 선언)
local EnablePolling

-- 폴링 비활성화 (성능 최적화)
function FrameController:DisablePolling()
    if state.pollingActive then
        pollingFrame:SetScript("OnUpdate", nil)
    end
    state.pollingActive = false
    state.dirty = false
    state.reconcileDueAt = 0
    state.forceNotify = false
end

EnablePolling = function()
    if state.pollingActive then return end
    if not state.dirty then
        MarkDirty(0, true)
    end
    state.pollingActive = true
    pollingFrame:SetScript("OnUpdate", function()
        if not FrameController.initialized then
            FrameController:DisablePolling()
            return
        end

        local now = GetTime()
        if not state.dirty or now < state.reconcileDueAt then return end

        state.pollingActive = false
        pollingFrame:SetScript("OnUpdate", nil)
        state.reconcileDueAt = 0
        FrameController:Reconcile()
    end)
end
FrameController.EnablePolling = function(self) EnablePolling() end

local function ResetGroupViewerHiddenFlags()
    local gr = DDingUI.GroupRenderer
    if not (gr and gr.groupFrames) then return end
    for _, frame in pairs(gr.groupFrames) do
        if frame._viewerHidden then
            frame._viewerHidden = false
        end
    end
end

local function RestoreGroupFrameState()
    local gr = DDingUI.GroupRenderer
    if not (gr and gr.groupFrames) then return end

    local profile = DDingUI.db and DDingUI.db.profile
    local gs = profile and profile.groupSystem
    local groups = gs and gs.groups
    local fh = DDingUI.FlightHide
    local keepHidden = fh and (fh.isActive or fh._hiding)

    for groupName, frame in pairs(gr.groupFrames) do
        if frame then
            frame._viewerHidden = false
            local settings = groups and groups[groupName]
            if settings and settings.enabled then
                if not keepHidden and frame.SetAlpha then
                    local alpha = settings.groupAlpha or 1
                    pcall(frame.SetAlpha, frame, alpha)
                    frame._ddLastFrameAlpha = alpha
                end
                if not frame:IsShown() then
                    if InCombatLockdown() and frame:GetName() then
                        frame._pendingCombatShow = true
                    else
                        frame:Show()
                    end
                end
            end
        end
    end
end

local function RunViewerTransitionRecovery(reloadMapped, forceFrameControl)
    if not FrameController.initialized then return end
    FrameController:RefreshViewerRefs()
    ResetGroupViewerHiddenFlags()
    if forceFrameControl then
        InvalidateGroupLayoutCaches(true)
        RestoreGroupFrameState()
    end
    if DDingUI.ContainerSync then
        if DDingUI.ContainerSync.RefreshViewerHooks then
            DDingUI.ContainerSync:RefreshViewerHooks()
        elseif DDingUI.ContainerSync.SyncAll then
            DDingUI.ContainerSync:SyncAll()
        end
    end
    if DDingUI.GroupSystem and DDingUI.GroupSystem.enabled then
        if forceFrameControl and DDingUI.GroupSystem.RequestFullUpdate then
            DDingUI.GroupSystem:RequestFullUpdate()
        elseif forceFrameControl and DDingUI.GroupSystem.DoFullUpdate then
            DDingUI.GroupSystem:DoFullUpdate()
        else
            DDingUI.GroupSystem:Refresh()
        end
    end
    if forceFrameControl and DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge.NotifyIconsChanged then
        DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
    end
    if reloadMapped and DDingUI.Movers and DDingUI.Movers.ReloadMappedModulePositions then
        DDingUI.Movers:ReloadMappedModulePositions()
    end
    MarkDirty(0, true)
    if not state.pollingActive then
        EnablePolling()
    end
end

local transitionRecoveryPending = {}

local function ScheduleViewerTransitionRecovery(reloadMapped, forceFrameControl, longTail)
    local delays = longTail and { 0.05, 0.5, 2.0 } or { 0.2, 1.0 }
    for _, delay in pairs(delays) do
        local key = tostring(delay)
        local pending = transitionRecoveryPending[key]
        if pending then
            pending.reloadMapped = pending.reloadMapped or reloadMapped
            pending.forceFrameControl = pending.forceFrameControl or forceFrameControl
        else
            pending = {
                reloadMapped = reloadMapped and true or false,
                forceFrameControl = forceFrameControl and true or false,
            }
            transitionRecoveryPending[key] = pending
            C_Timer.After(delay, function()
                local current = transitionRecoveryPending[key]
                transitionRecoveryPending[key] = nil
                if current then
                    RunViewerTransitionRecovery(current.reloadMapped, current.forceFrameControl)
                end
            end)
        end
    end
end

local function RunPvPTransitionRecovery(event)
    local inPvP = DDingUI.IsPvPInstance and DDingUI:IsPvPInstance() or false
    local changed = state.lastPvPInstance == nil or state.lastPvPInstance ~= inPvP
    state.lastPvPInstance = inPvP

    if changed or event == "PVP_MATCH_STATE_CHANGED" then
        RunViewerTransitionRecovery(true, true)
        ScheduleViewerTransitionRecovery(true, true, true)
    else
        ScheduleViewerTransitionRecovery(true, false)
    end
end

-- 하위 호환: ScheduleReconcile → MarkDirty + EnablePolling
local function ScheduleReconcile(debounceTime, forceNotify)
    if state.specChangeDetected or state.talentChangeDetected then return end
    MarkDirty(debounceTime, forceNotify)
    if FrameController.initialized and not state.pollingActive then
        EnablePolling()
    end
end

function FrameController:_FinishPendingSpecChange(version)
    if version and version ~= state.specChangeVersion then return end
    if not state.specChangeDetected and not state.talentChangeDetected then return end

    state.specChangeDetected = false
    state.talentChangeDetected = false
    state.pendingReconcile = false
    state.dirty = false
    state.reconcileDueAt = 0
    wipe(iconSpellNameMap)

    local function RefreshCompletedTransition()
        if not FrameController.initialized then return end
        if version and version ~= state.specChangeVersion then return end
        if state.specChangeDetected or state.talentChangeDetected then return end

        FrameController:RefreshViewerRefs()
        InvalidateGroupLayoutCaches(true)
        ResetGroupViewerHiddenFlags()
        MarkDirty(0, true)
        if not state.pollingActive then
            EnablePolling()
        end
    end

    C_Timer.After(0, RefreshCompletedTransition)
    C_Timer.After(0.1, RefreshCompletedTransition)
end

function FrameController:_BeginPendingSpecChange(fullChange)
    state.specChangeVersion = state.specChangeVersion + 1
    local version = state.specChangeVersion

    if fullChange then
        state.specChangeDetected = true
    else
        state.talentChangeDetected = true
    end

    state.pendingReconcile = false
    state.dirty = false
    state.reconcileDueAt = 0
    state.forceNotify = false

    C_Timer.After(3, function()
        FrameController:_FinishPendingSpecChange(version)
    end)
end

local function ForceImmediateReconcile()
    if not FrameController.initialized then return end
    ScheduleReconcile(0, true)
end

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

                if self._installPoolHooks then
                    self._installPoolHooks(currentViewer, def.globalName)
                end

                -- 새 뷰어에 Layout/Show/Hide 훅 설치
                if not hookedViewerLayout[currentViewer] then
                    hookedViewerLayout[currentViewer] = true
                    -- [CDM ForceReanchor] 동기 Reconcile 핸들러
                    -- CDM 이벤트 완료 후 즉시 전체 재배치
                    local function PostLayoutHandler()
                        if not FrameController.initialized then return end
                        ScheduleReconcile(0, true)
                    end
                    -- [1] UpdateLayout/Layout 훅 (CDM Main.lua:225)
                    if currentViewer.UpdateLayout then
                        hooksecurefunc(currentViewer, "UpdateLayout", PostLayoutHandler)
                    elseif currentViewer.Layout then
                        hooksecurefunc(currentViewer, "Layout", PostLayoutHandler)
                    end
                    -- [2] RefreshData 훅 — MarkDirty만 (동기 Reconcile 아님!)
                    -- RefreshData는 CDM Release→Re-Acquire 전환 중간에 발생
                    -- 이때 동기 Reconcile → 프레임 미발견 → Hide() → 깜빡임
                    -- Layout/UpdateLayout이 CDM 완료 후 동기 Reconcile 처리
                    if currentViewer.RefreshData then
                        hooksecurefunc(currentViewer, "RefreshData", function()
                            if FrameController.initialized then
                                MarkDirty()
                                if not state.pollingActive then EnablePolling() end
                            end
                        end)
                    end
                    -- [3] RefreshLayout 훅 — MarkDirty만 (동일 이유)
                    if currentViewer.RefreshLayout then
                        hooksecurefunc(currentViewer, "RefreshLayout", function()
                            if FrameController.initialized then
                                MarkDirty()
                                if not state.pollingActive then EnablePolling() end
                            end
                        end)
                    end
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

local function SafeTableField(tbl, key)
    if not tbl or not key then return nil end
    local ok, value = pcall(function()
        return tbl[key]
    end)
    if ok then return value end
    return nil
end

local function GetCooldownInfoSpellID(info)
    if not info then return nil end
    local sid = SafeTableField(info, "overrideTooltipSpellID") or SafeTableField(info, "overrideSpellID") or SafeTableField(info, "spellID")
    local linkedSpellIDs = SafeTableField(info, "linkedSpellIDs")
    if not IsSafeNumber(sid) and type(linkedSpellIDs) == "table" then
        sid = SafeTableField(linkedSpellIDs, 1)
    end
    if IsSafeNumber(sid) and sid > 0 then
        return sid
    end
    return nil
end

local function AddAuraCandidate(list, seen, value)
    if IsSafeNumber(value) and value > 0 and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

local function AddLinkedAuraCandidates(list, seen, linkedSpellIDs)
    if type(linkedSpellIDs) ~= "table" then return end
    pcall(function()
        for _, linkedID in ipairs(linkedSpellIDs) do
            AddAuraCandidate(list, seen, linkedID)
        end
    end)
end

local function AddCooldownInfoAuraCandidates(list, seen, info)
    if type(info) ~= "table" then return end
    AddAuraCandidate(list, seen, SafeTableField(info, "overrideTooltipSpellID"))
    AddAuraCandidate(list, seen, SafeTableField(info, "overrideSpellID"))
    AddAuraCandidate(list, seen, SafeTableField(info, "spellID"))
    AddLinkedAuraCandidates(list, seen, SafeTableField(info, "linkedSpellIDs"))
end

local function BuffFrameHasPlayerAura(frame)
    if not frame then return nil end

    local candidates = {}
    local seen = {}

    if frame.GetAuraSpellID then
        local ok, sid = pcall(frame.GetAuraSpellID, frame)
        if ok then AddAuraCandidate(candidates, seen, sid) end
    end

    local okAura, auraSpellID = pcall(function() return frame.auraSpellID end)
    if okAura then
        AddAuraCandidate(candidates, seen, auraSpellID)
    end

    local okInfo, info = pcall(function()
        if frame.GetCooldownInfo then
            return frame:GetCooldownInfo()
        end
        return frame.cooldownInfo
    end)
    if okInfo then
        AddCooldownInfoAuraCandidates(candidates, seen, info)
    end

    local okCooldownID, cooldownID = pcall(function()
        return frame.cooldownID
    end)
    if okCooldownID and IsSafeNumber(cooldownID)
        and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    then
        local okViewerInfo, viewerInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if okViewerInfo then
            AddCooldownInfoAuraCandidates(candidates, seen, viewerInfo)
        end
    end

    if #candidates == 0 then
        return nil
    end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, sid in ipairs(candidates) do
            local auraData
            local ok = pcall(function()
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(sid)
            end)
            if ok and auraData then
                return true
            end
        end
    end

    return false
end

local function HideManagedBorderLayers(frame)
    if not frame then return end
    if frame.border then
        if frame.border.SetAlpha then pcall(frame.border.SetAlpha, frame.border, 0) end
        if frame.border.Hide then pcall(frame.border.Hide, frame.border) end
    end
    local borders = frame._ddBorders
    if type(borders) == "table" then
        for _, borderTex in ipairs(borders) do
            if borderTex then
                if borderTex.SetAlpha then pcall(borderTex.SetAlpha, borderTex, 0) end
                if borderTex.SetShown then pcall(borderTex.SetShown, borderTex, false) end
                if borderTex.Hide then pcall(borderTex.Hide, borderTex) end
            end
        end
    end
end

local function SuppressStaleBuffFrame(icon)
    if not icon then return end
    icon._ddCDMStaleBuff = true
    icon._ddCombatKeepAlive = nil
    icon._ddCombatVisible = false
    HideManagedBorderLayers(icon)
    local texture = icon.icon or icon.Icon
    if texture and texture.SetAlpha then
        pcall(texture.SetAlpha, texture, 0)
    end
    if icon.cooldown and icon.cooldown.Hide then
        pcall(icon.cooldown.Hide, icon.cooldown)
    end
    if icon.Cooldown and icon.Cooldown.Hide and icon.Cooldown ~= icon.cooldown then
        pcall(icon.Cooldown.Hide, icon.Cooldown)
    end
    if icon.count and icon.count.Hide then
        pcall(icon.count.Hide, icon.count)
    end
    if icon.SetAlpha then
        pcall(icon.SetAlpha, icon, 0)
        icon._ddLastGroupAlpha = 0
    end
    if icon._ddIsManaged and icon.Hide then
        pcall(icon.Hide, icon)
    end
end

local function RestoreStaleBuffFrame(icon)
    if not icon then return end
    icon._ddCDMStaleBuff = nil
    local fh = DDingUI.FlightHide
    if icon.SetAlpha and not (fh and fh.isActive) then
        pcall(icon.SetAlpha, icon, 1)
        icon._ddLastGroupAlpha = 1
    end
    local texture = icon.icon or icon.Icon
    if texture then
        if texture.Show then pcall(texture.Show, texture) end
        if texture.SetAlpha then pcall(texture.SetAlpha, texture, 1) end
    end
end

local function ShouldIncludeCooldownViewerFrame(icon, viewerName)
    if not icon then
        return false
    end

    if viewerName ~= "BuffIconCooldownViewer" then
        if not (icon.IsShown and icon:IsShown()) then
            return false
        end
        return true
    end

    if icon.IsShown and icon:IsShown() then
        return true
    end

    if icon.cooldownInfo then
        return true
    end

    return false
end

local function ReadBuffFrameActiveState(frame)
    if not frame then return nil end

    local active = frame.isActive
    if issecretvalue and issecretvalue(active) then
        return nil
    end
    if type(active) == "boolean" then
        return active
    end
    return nil
end

function FrameController:_ResetAcquiredCooldownFrame(frame)
    if not frame then return end

    local restoreVisuals = frame._ddCDMStaleBuff
        or frame._ddSuppressed
        or frame._ddProvisionalHidden

    frame._ddCDMViewerShown = nil
    frame._ddCDMStaleBuff = nil
    frame._ddLayoutVisible = nil
    frame._ddProvisionalHidden = nil
    frame._ddCombatKeepAlive = nil
    frame._ddCombatVisible = nil
    frame._ddLastCooldownID = nil
    frame._ddLayoutCooldownID = nil
    frame._ddSuppressed = nil
    frame._ddingHidden = nil

    frame._ddIsManaged = nil
    frame._ddContainerRef = nil
    frame._ddOrigState = nil
    ResetGroupIconLayoutState(frame, true)

    if restoreVisuals then
        local texture = frame.icon or frame.Icon
        if texture and texture.SetAlpha then
            texture:SetAlpha(1)
        end
        if frame.SetAlpha and not (DDingUI.FlightHide and DDingUI.FlightHide.isActive) then
            frame:SetAlpha(1)
            frame._ddLastGroupAlpha = 1
        end
    end
end

local function ShouldReplaceCooldownFrame(existing, candidate)
    if not existing then return true end

    local existingShown = existing.IsShown and existing:IsShown() or false
    local candidateShown = candidate.IsShown and candidate:IsShown() or false
    if existingShown ~= candidateShown then
        return candidateShown
    end

    local existingSerial = existing._ddAcquireSerial or 0
    local candidateSerial = candidate._ddAcquireSerial or 0
    if existingSerial ~= candidateSerial then
        return candidateSerial > existingSerial
    end

    return existing._ddIsManaged == true and candidate._ddIsManaged ~= true
end

-- ============================================================
-- [CDM] itemFramePool.Release 훅
-- CDM이 버프 만료 시 pool에서 Release() 호출
-- Release된 프레임: EnumerateActive()에서 제거 + Hide() 호출
-- DDingUI가 reparent한 프레임은 CDM viewer로 복원 필요
-- ============================================================

if not FrameController._poolReleaseHooked then
    FrameController._poolReleaseHooked = true
    -- [CDM REACTIVE] Pool Acquire/Release → Reconcile만 트리거
    -- 상태 변경 없음: Reconcile이 매번 전체 재배치
    FrameController._installPoolHooks = function(viewer, globalName)
        if not viewer or not viewer.itemFramePool then return end
        if viewer._ddPoolHooked then return end
        viewer._ddPoolHooked = true
        -- Pool.Release: dirty만 표시 (Reconcile 즉시 트리거 안 함 → Layout 완료 후 Reconcile)
        -- Pool.Release는 CDM Layout 중간에 발생 → 즉시 Reconcile하면 미완성 상태 스캔
        hooksecurefunc(viewer.itemFramePool, "Release", function()
            FrameController._diagCounters.poolRelease = FrameController._diagCounters.poolRelease + 1
            if FrameController.initialized then
                MarkDirty()
                if not state.pollingActive then EnablePolling() end
            end
        end)
        -- Pool.Acquire: dirty만 표시 (CDM Main.lua:411 패턴)
        hooksecurefunc(viewer.itemFramePool, "Acquire", function()
            if FrameController.initialized then
                MarkDirty()
                if not state.pollingActive then EnablePolling() end
            end
        end)
    end
end

-- [DIAG] /ddbuffdiag — CDM buff pool 진단
SLASH_DDBUFFDIAG1 = "/ddbuffdiag"
SlashCmdList["DDBUFFDIAG"] = function()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer.itemFramePool then
        print("|cffff4444BuffIconCooldownViewer not found|r")
        return
    end
    local counters = FrameController._diagCounters or {}
    print("|cff00ff00=== /ddbuffdiag ===|r")
    print("|cffffcc00Hook Counters:|r")
    print("  OnActiveStateChanged: " .. (counters.activeStateChanged or "?"))
    print("  OnCooldownIDSet: " .. (counters.cooldownIDSet or "?"))
    print("  Pool Release: " .. (counters.poolRelease or "?"))
    print("|cffffcc00Pool State:|r")
    local activeCount, shownCount, hiddenCount, managedCount = 0, 0, 0, 0
    for icon in viewer.itemFramePool:EnumerateActive() do
        activeCount = activeCount + 1
        local shown = icon:IsShown()
        local managed = icon._ddIsManaged
        local cdmActive = ReadBuffFrameActiveState(icon)
        local parent = icon:GetParent()
        local parentName = parent and (parent:GetName() or "anon") or "nil"
        if shown then shownCount = shownCount + 1 end
        if not shown then hiddenCount = hiddenCount + 1 end
        if managed then managedCount = managedCount + 1 end
        local cdStr = icon.cooldownID and tostring(icon.cooldownID) or "nil"
        -- 스펠 이름 + 아이콘 알파 + C_UnitAuras 체크
        local spellName = "?"
        local iconAlpha = icon:GetAlpha()
        local auraActive = "?"
        pcall(function()
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo and icon.cooldownID then
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID)
                if info then
                    local sid = info.spellID or (info.linkedSpellIDs and info.linkedSpellIDs[1]) or 0
                    spellName = C_Spell.GetSpellName(sid) or "?"
                    -- C_UnitAuras 체크
                    if sid and sid > 0 then
                        local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
                        auraActive = aura and "YES" or "no"
                    end
                end
            end
        end)
        print(string.format("  #%d [%s] layout=%s auraSID=%s cdmA=%s managed=%s alpha=%.1f aura=%s parent=%s",
            activeCount, spellName,
            tostring(icon.layoutIndex), tostring(icon.auraSpellID ~= nil), tostring(cdmActive), tostring(managed), iconAlpha, auraActive, parentName))
    end
    print(string.format("|cffffcc00Summary: Active=%d Shown=%d Hidden=%d Managed=%d|r",
        activeCount, shownCount, hiddenCount, managedCount))
end

-- [DIAG] /ddpipeline — 전투 중 파이프라인 전 단계 덤프
SLASH_DDPIPELINE1 = "/ddpipeline"
SlashCmdList["DDPIPELINE"] = function()
    local combat = InCombatLockdown() and "|cffff4444YES|r" or "|cff44ff44no|r"
    print("|cff00ff00=== /ddpipeline === Combat: " .. combat .. "|r")

    -- 1단계: BuffIcon 뷰어 raw 스캔
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer.itemFramePool then
        print("|cffff4444BuffIconCooldownViewer not found|r")
        return
    end

    print("|cffffcc00[Stage 1] Raw BuffIcon Pool Scan:|r")
    local poolCount = 0
    for icon in viewer.itemFramePool:EnumerateActive() do
        poolCount = poolCount + 1
        local cdID = "?"
        pcall(function() cdID = tostring(icon.cooldownID) end)
        local shown = icon:IsShown()
        local auraSID = "nil"
        pcall(function()
            if icon.auraSpellID ~= nil then
                if type(issecretvalue) == "function" and issecretvalue(icon.auraSpellID) then
                    auraSID = "SECRET"
                else
                    auraSID = tostring(icon.auraSpellID)
                end
            end
        end)
        local isActiveFn = "N/A"
        pcall(function()
            if icon.IsActive and type(icon.IsActive) == "function" then
                local v = icon:IsActive()
                if v == nil then isActiveFn = "nil"
                elseif type(issecretvalue) == "function" and issecretvalue(v) then isActiveFn = "SECRET"
                else isActiveFn = tostring(v) end
            end
        end)
        local hasCdInfo = icon.cooldownInfo and "YES" or "no"
        local managed = icon._ddIsManaged and "YES" or "no"
        local parent = icon:GetParent()
        local pName = parent and (parent:GetName() or "anon") or "nil"
        local alpha = string.format("%.1f", icon:GetAlpha())

        -- GetSpellIDForIcon 시도
        local spellIDResult = "nil"
        pcall(function()
            local fc = DDingUI.CDMHookEngine
            if fc and fc.GetSpellIDForIcon then
                local sid = fc:GetSpellIDForIcon(icon)
                if sid then spellIDResult = tostring(sid) end
            end
        end)

        -- 캐시된 spellName
        local cachedName = "nil"
        pcall(function()
            local fc = DDingUI.CDMHookEngine
            if fc and fc.GetSpellNameForID and icon.cooldownID then
                local n = fc:GetSpellNameForID(icon.cooldownID)
                if n then cachedName = n end
            end
        end)

        -- ClassifyIcon 결과
        local classResult = "nil"
        pcall(function()
            local gm = DDingUI.GroupManager
            if gm and gm.ClassifyIcon and icon.cooldownID then
                local g = gm:ClassifyIcon(icon.cooldownID)
                if g then classResult = g end
            end
        end)

        print(string.format("  #%d cd=%s shown=%s auraSID=%s isActive=%s cdInfo=%s managed=%s alpha=%s parent=%s",
            poolCount, cdID, tostring(shown), auraSID, isActiveFn, hasCdInfo, managed, alpha, pName))
        print(string.format("       spellID=%s cachedName=%s classify=%s",
            spellIDResult, cachedName, classResult))
    end
    print("|cffffcc00Pool total: " .. poolCount .. "|r")

    -- 2단계: idIconMap 상태
    print("|cffffcc00[Stage 2] idIconMap (BuffIcon only):|r")
    local mapCount = 0
    for cooldownID, icon in pairs(idIconMap) do
        local src = iconSourceMap[cooldownID]
        if src == "BuffIconCooldownViewer" then
            mapCount = mapCount + 1
            local name = iconSpellNameMap[cooldownID] or "nil"
            print(string.format("  cd=%s name=%s managed=%s",
                tostring(cooldownID), name, tostring(icon._ddIsManaged or false)))
        end
    end
    print("|cffffcc00BuffIcon in idIconMap: " .. mapCount .. "|r")

    -- 3단계: spellAssignments
    print("|cffffcc00[Stage 3] spellAssignments:|r")
    local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    if gs and gs.spellAssignments then
        for spellName, groupName in pairs(gs.spellAssignments) do
            -- 그룹 존재/활성 여부도 함께 출력
            local gInfo = "NOT_IN_GROUPS"
            if gs.groups and gs.groups[groupName] then
                local g = gs.groups[groupName]
                gInfo = string.format("enabled=%s type=%s", tostring(g.enabled), tostring(g.groupType or "static"))
            end
            print(string.format("  '%s' → '%s' [%s]", tostring(spellName), tostring(groupName), gInfo))
        end
    else
        print("  (none)")
    end

    -- 4단계: 모든 그룹 상태
    print("|cffffcc00[Stage 4] All Groups:|r")
    if gs and gs.groups then
        for name, g in pairs(gs.groups) do
            print(string.format("  '%s': enabled=%s type=%s", name, tostring(g.enabled), tostring(g.groupType or "static")))
        end
    else
        print("  (no groups)")
    end
end

-- ============================================================
-- 맵 빌드 (스캔)
-- ============================================================

function FrameController:ScanCDMViewers()
    local previousCount = 0
    for _ in pairs(idIconMap) do previousCount = previousCount + 1 end

    local nextIdIconMap = {}
    local nextIconSourceMap = {}
    local nextIconSpellNameMap = {}
    local nextIconStateMap = {}
    local nextIconLayoutIndexMap = {}
    local nextTrackedBuffSpellNames = {}
    local nextTrackedBuffSpellOrder = {}
    local nextTrackedBuffSpellTextures = {}
    local scannedViewers = 0
    local activeFrameCount = 0
    local hiddenFrameCount = 0
    local unsafeKeyCount = 0

    -- [REPARENT] DDingUI 프로필 참조 — 뷰어 활성화 상태 확인
    local profile = DDingUI.db and DDingUI.db.profile
    local viewerProfiles = profile and profile.viewers
    local bridge = DDingUI.DynamicIconBridge
    local suppressed = bridge and bridge.GetSuppressedSpellIDs and bridge:GetSuppressedSpellIDs()

    for globalName, viewer in pairs(viewerRefs) do
        local shouldScan = true

        -- [REPARENT] DDingUI에서 비활성화된 뷰어는 스캔하지 않음
        local vp = viewerProfiles and viewerProfiles[globalName]
        if vp and vp.enabled == false then
            shouldScan = false
        end

        -- [FIX] cooldownID + IsShown 체크: CDM이 Hide한 비활성 버프는 분류/렌더링 제외
        -- 단, 숨겨진 아이콘에도 OnShow 훅을 설치하여 CDM이 Show 시 Reconcile 트리거
        if shouldScan and viewer.itemFramePool then
            scannedViewers = scannedViewers + 1
            -- [CDM] Buff viewer: pool Release 훅 설치 (최초 1회)
            if FrameController._installPoolHooks then
                FrameController._installPoolHooks(viewer, globalName)
            end

            for icon in viewer.itemFramePool:EnumerateActive() do
                local cooldownID = icon.cooldownID
                if IsSafeNumber(cooldownID) and not icon.isEditing then
                    local keySafe = true
                    activeFrameCount = activeFrameCount + 1
                    local sourceShown = icon.IsShown and icon:IsShown() or false
                    if globalName == "BuffIconCooldownViewer" then
                        local active = ReadBuffFrameActiveState(icon)
                        if active ~= nil then
                            sourceShown = active == true and not icon._ddCDMStaleBuff
                        elseif icon._ddCDMStaleBuff then
                            sourceShown = false
                        end
                    end
                    icon._ddSourceViewer = globalName
                    icon._ddCDMViewerShown = sourceShown and true or false
                    local trackedBuffName
                    if globalName == "BuffIconCooldownViewer" then
                        local spellID = self:GetSpellIDForIcon(icon)
                        if spellID and C_Spell and C_Spell.GetSpellInfo then
                            local spellInfo = C_Spell.GetSpellInfo(spellID)
                            if spellInfo and spellInfo.name then
                                trackedBuffName = "buff_" .. spellInfo.name
                                nextTrackedBuffSpellNames[trackedBuffName] = true
                                nextTrackedBuffSpellTextures[trackedBuffName] = spellInfo.iconID
                                local layoutIndex = icon.layoutIndex
                                if not (issecretvalue and issecretvalue(layoutIndex))
                                    and type(layoutIndex) == "number"
                                then
                                    nextTrackedBuffSpellOrder[trackedBuffName] = layoutIndex
                                end
                            end
                        end
                    end
                    local shouldInclude = ShouldIncludeCooldownViewerFrame(icon, globalName)
                    if globalName == "BuffIconCooldownViewer" then
                        if shouldInclude and sourceShown then
                            RestoreStaleBuffFrame(icon)
                        end
                        if not icon._ddStaleBuffAlphaHooked then
                            hooksecurefunc(icon, "SetAlpha", function(self, alpha)
                                if self._ddCDMStaleBuff and alpha and alpha > 0 then
                                    self:SetAlpha(0)
                                end
                            end)
                            icon._ddStaleBuffAlphaHooked = true
                        end
                    end
                    if not shouldInclude then
                        hiddenFrameCount = hiddenFrameCount + 1
                    end
                    if not shouldInclude and _debugLog then
                        local pname = icon:GetParent() and icon:GetParent():GetName() or "?"
                        DLog("  SKIP hidden:", tostring(icon.cooldownID), "managed=" .. tostring(icon._ddIsManaged), "alpha=" .. string.format("%.2f", icon:GetAlpha()), "parent=" .. pname)
                    end
                    if shouldInclude then
                        -- [FIX] CDM 중복 억제 (DDingUI auraSpellID + CDM 분리 패턴)
                        -- CDM cooldownID ≠ spell ID → auraSpellID(실제 spell ID) 사용
                        -- 매칭 시 _ddIsManaged 설정 → CDM Layout 훅이 자동으로 뷰어에서 분리
                        if suppressed then
                            local isSuppressed = false
                            local auraSpellID = icon.auraSpellID
                            if IsSafeNumber(auraSpellID) and suppressed[auraSpellID] then
                                isSuppressed = true
                            elseif suppressed[cooldownID] then
                                isSuppressed = true
                            end
                            if isSuppressed then
                                -- SetAlpha(0) + SetAlpha 훅으로 숨김 (Hide 대신 → OnHide 미발동)
                                icon._ddSuppressed = true
                                icon:SetAlpha(0)
                                -- [FIX] SetAlpha 훅: CDM이 SetAlpha(1) 호출해도 즉시 재적용
                                if not icon._ddSuppressAlphaHooked then
                                    hooksecurefunc(icon, "SetAlpha", function(self, alpha)
                                        if self._ddSuppressed and alpha and alpha > 0 then
                                            self:SetAlpha(0)
                                        end
                                    end)
                                    icon._ddSuppressAlphaHooked = true
                                end
                                shouldInclude = false
                            elseif icon._ddSuppressed then
                                -- 억제 해제: 더 이상 suppressed 아닌 아이콘 복원
                                icon._ddSuppressed = false
                                icon:SetAlpha(1)
                            end
                        end
                    end
                    if shouldInclude and keySafe then
                        local existing = nextIdIconMap[cooldownID]
                        if ShouldReplaceCooldownFrame(existing, icon) then
                            nextIdIconMap[cooldownID] = icon
                            nextIconSourceMap[cooldownID] = globalName
                            nextIconStateMap[cooldownID] = sourceShown and true or false
                            local layoutIndex = icon.layoutIndex
                            if IsSafeNumber(layoutIndex) then
                                nextIconLayoutIndexMap[cooldownID] = layoutIndex
                            end

                            local name = trackedBuffName or self:GetSpellName(icon)
                            if name then
                                nextIconSpellNameMap[cooldownID] = name
                            end
                        end

                        if not icon._fcShowHideHooked then
                            icon:HookScript("OnShow", function(self)
                                if self._ddSuppressed then self:SetAlpha(0); return end
                                if self._ddCDMStaleBuff then
                                    RestoreStaleBuffFrame(self)
                                end
                                if not FrameController.initialized then return end
                                -- managed 프레임 즉시 복원 (Essential 뷰어는 Layout 없이 Show만 호출할 수 있음)
                                if self._ddIsManaged and self._ddTargetPoint then
                                    self:SetParent(UIParent)
                                    self:ClearAllPoints()
                                    self:SetPoint(
                                        self._ddTargetPoint,
                                        self._ddContainerRef,
                                        self._ddTargetRelPoint or "CENTER",
                                        self._ddTargetX or 0,
                                        self._ddTargetY or 0
                                    )
                                    if self:GetAlpha() < 0.01 then
                                        local fh = DDingUI.FlightHide
                                        if not (fh and fh.isActive) then
                                            self:SetAlpha(1)
                                        end
                                    end
                                end
                                ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
                            end)
                            icon:HookScript("OnHide", function(self)
                                if not FrameController.initialized then return end
                                ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
                            end)
                            icon._fcShowHideHooked = true
                        end
                    else
                        -- 숨겨진 아이콘에도 OnShow/OnHide 훅 설치
                        if not icon._fcShowHideHooked then
                            icon:HookScript("OnShow", function(self)
                                if self._ddCDMStaleBuff then
                                    RestoreStaleBuffFrame(self)
                                end
                                if not FrameController.initialized then return end
                                ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
                            end)
                            icon:HookScript("OnHide", function(self)
                                if not FrameController.initialized then return end
                                ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
                            end)
                            icon._fcShowHideHooked = true
                        end
                        -- iconSourceMap은 저장 (나중에 ClassifyIcon에서 참조)
                        if keySafe then
                            nextIconSourceMap[cooldownID] = globalName
                        end
                    end
                end
            end
        end
    end

    local nextCount = 0
    for _ in pairs(nextIdIconMap) do nextCount = nextCount + 1 end

    local emptyDrop = previousCount > 0 and nextCount == 0 and scannedViewers > 0
    local partialDrop = previousCount > 1 and nextCount > 0 and nextCount < previousCount
    local hiddenTransition = hiddenFrameCount > 0 or activeFrameCount == 0 or unsafeKeyCount > 0
    local holdScan = false

    if emptyDrop and state.emptyScanStreak < CONFIG.SCAN_EMPTY_GRACE then
        state.emptyScanStreak = state.emptyScanStreak + 1
        state.partialScanStreak = 0
        holdScan = true
    elseif partialDrop and hiddenTransition and state.partialScanStreak < CONFIG.SCAN_PARTIAL_GRACE then
        state.partialScanStreak = state.partialScanStreak + 1
        holdScan = true
    end

    if holdScan then
        state.scanHoldActive = true
        state.scanHoldStartedAt = GetTime and GetTime() or 0
        DLog("ScanHold: prev=" .. previousCount .. " next=" .. nextCount .. " active=" .. activeFrameCount .. " hidden=" .. hiddenFrameCount .. " unsafe=" .. unsafeKeyCount)
        return false
    end

    local changes = { ids = {}, topologyChanged = false }
    for cooldownID, icon in pairs(idIconMap) do
        if nextIdIconMap[cooldownID] ~= icon
            or nextIconSourceMap[cooldownID] ~= iconSourceMap[cooldownID]
            or nextIconSpellNameMap[cooldownID] ~= iconSpellNameMap[cooldownID]
            or nextIconStateMap[cooldownID] ~= iconStateMap[cooldownID]
            or nextIconLayoutIndexMap[cooldownID] ~= iconLayoutIndexMap[cooldownID]
        then
            changes.ids[cooldownID] = true
            changes.topologyChanged = true
        end
    end
    for cooldownID in pairs(nextIdIconMap) do
        if idIconMap[cooldownID] == nil then
            changes.ids[cooldownID] = true
            changes.topologyChanged = true
        end
    end

    wipe(idIconMap)
    wipe(iconSourceMap)
    wipe(iconSpellNameMap)
    wipe(iconStateMap)
    wipe(iconLayoutIndexMap)
    wipe(trackedBuffSpellNames)
    wipe(trackedBuffSpellOrder)
    wipe(trackedBuffSpellTextures)
    for cooldownID, icon in pairs(nextIdIconMap) do
        idIconMap[cooldownID] = icon
    end
    for cooldownID, sourceName in pairs(nextIconSourceMap) do
        iconSourceMap[cooldownID] = sourceName
    end
    for cooldownID, spellName in pairs(nextIconSpellNameMap) do
        iconSpellNameMap[cooldownID] = spellName
    end
    for cooldownID, visible in pairs(nextIconStateMap) do
        iconStateMap[cooldownID] = visible
    end
    for cooldownID, layoutIndex in pairs(nextIconLayoutIndexMap) do
        iconLayoutIndexMap[cooldownID] = layoutIndex
    end
    for spellName in pairs(nextTrackedBuffSpellNames) do
        trackedBuffSpellNames[spellName] = true
        trackedBuffSpellOrder[spellName] = nextTrackedBuffSpellOrder[spellName]
        trackedBuffSpellTextures[spellName] = nextTrackedBuffSpellTextures[spellName]
    end

    state.emptyScanStreak = 0
    state.partialScanStreak = 0
    state.scanHoldActive = false
    state.lastAcceptedScanCount = nextCount

    -- [DEBUG] 스캔 결과 요약
    if _debugLog then
        local count = 0
        for _ in pairs(idIconMap) do count = count + 1 end
        DLog("ScanDone: idIconMap=" .. count .. " entries")
    end

    -- [CDM REACTIVE] 고아 정리 없음.
    -- 매 Reconcile마다 EnumerateActive() → idIconMap 재구축 → 전체 재배치.
    -- 이전 상태와 비교하지 않으므로 고아 개념 자체가 불필요.
    return true, changes
end

-- 하위 호환 별칭
FrameController.RebuildMaps = FrameController.ScanCDMViewers

-- [FIX] FlightHide용 idIconMap 접근자
function FrameController:GetIdIconMap()
    return idIconMap
end

-- ============================================================
-- Reconcile (핵심 파이프라인)
-- CDM 스캔 → 콜백 알림 → 상태 리셋
-- ============================================================

function FrameController:Reconcile()
    if not self.initialized then
        state.pendingReconcile = false
        return
    end

    if state.specChangeDetected or state.talentChangeDetected then
        state.pendingReconcile = false
        state.dirty = false
        state.reconcileDueAt = 0
        state.forceNotify = false
        return false
    end

    -- [FIX] 블리자드 편집모드 중 Reconcile 완전 차단
    -- CDM이 편집모드용 테스트 프레임을 생성/파괴하면서 cooldownID에 secret value 할당
    -- 이 상태에서 ScanCDMViewers가 프레임을 순회하면 Taint 발생
    if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then
        state.dirty = true  -- 편집모드 퇴장 후 다시 스캔하도록 dirty 유지
        return
    end

    state.isProcessing = true
    state.pendingReconcile = false
    state.dirty = false
    local forceNotify = state.forceNotify
    state.forceNotify = false
    local _rc = state.reconcileCount or 0
    DLog("Reconcile #" .. _rc, "talent=" .. tostring(state.talentChangeDetected))

    -- [CDM REACTIVE] 특성 변경 시에도 기존 맵은 스캔 안정화까지 유지.
    -- 전환 중 빈 pool이 들어와도 기존 아이콘을 바로 release하지 않기 위함.
    if state.talentChangeDetected then
        wipe(iconSpellNameMap)
    end

    -- 1. CDM 뷰어 스캔 (맵 재구축)
    -- 전환 중 보류된 스캔은 기존 맵을 유지한 채 다음 틱에서 다시 시도한다.
    local scanAccepted, changes = self:ScanCDMViewers()
    if scanAccepted == false then
        state.isProcessing = false
        MarkDirty(CONFIG.RETRY_DELAY, forceNotify)
        if not state.pollingActive then
            EnablePolling()
        end
        return false
    end

    -- 2. 콜백 알림 (GroupInit → DoFullUpdate)
    -- [PERF] scanCompleted 플래그: NotifyUpdate → DoFullUpdate에서 ScanCDMViewers 이중 호출 방지
    state.scanCompleted = true
    if forceNotify or (changes and changes.topologyChanged) then
        changes = changes or { ids = {}, topologyChanged = false }
        changes.forceLayout = forceNotify == true
        self:NotifyUpdate(changes)
    end
    state.scanCompleted = false

    -- 3. [COOLDOWN TIMER] 만료 감지는 SetupFrameInContainer에서 alpha=0으로 처리
    -- CDM pool sync 불필요 — 매 Reconcile 틱마다 cooldown 시간 체크

    -- 4. 상태 플래그 리셋
    local needsFollowup = state.pendingReconcile
    state.specChangeDetected = false
    state.talentChangeDetected = false
    state.isProcessing = false
    state.dirty = false
    if needsFollowup then
        MarkDirty(CONFIG.DEBOUNCE_ONSHOW, true)
    end
    state.reconcileCount = state.reconcileCount + 1
    if needsFollowup and not state.pollingActive then
        EnablePolling()
    end
    return true
end

-- ============================================================
-- SpellName 안전 추출
-- ============================================================

function FrameController:GetSpellIDForIcon(icon)
    if not icon then return nil end

    local sourceName = icon.cooldownID and iconSourceMap[icon.cooldownID]
    local parent = icon.GetParent and icon:GetParent()
    if sourceName == "BuffIconCooldownViewer" or parent == viewerRefs["BuffIconCooldownViewer"] then
        local info = icon.GetCooldownInfo and icon:GetCooldownInfo() or icon.cooldownInfo
        local sid = GetCooldownInfoSpellID(info)
        if sid then return sid end
    end

    -- 1. [CDM 패턴] GetAuraSpellID — pcall 불필요 (전투 중 안전)
    if icon.GetAuraSpellID then
        local sid = icon:GetAuraSpellID()
        if IsSafeNumber(sid) and sid > 0 then
            return sid
        end
    end

    -- 2. [CDM 패턴] Raw cooldownInfo 메타테이블 스캐닝
    local info = icon.GetCooldownInfo and icon:GetCooldownInfo() or icon.cooldownInfo
    local sid = GetCooldownInfoSpellID(info)
    if sid then return sid end

    -- 3. [최후수단] GetSpellID — 전투 중 secret value 가능성 있음
    if icon.GetSpellID then
        local sid = icon:GetSpellID()
        if IsSafeNumber(sid) and sid > 0 then
            return sid
        end
    end

    return nil
end

function FrameController:GetSpellName(icon)
    local spellID = self:GetSpellIDForIcon(icon)
    if not spellID then return nil end

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
-- [REPARENT] DDingUI SetupFrameInContainer 패턴 기반
-- ============================================================

function FrameController:SetupFrameInContainer(frame, container, targetW, targetH, cooldownID)
    if not frame or not container then return end
    local needsLayoutReset = frame._ddContainerRef ~= container or frame._ddLayoutCooldownID ~= cooldownID
    if needsLayoutReset then
        ResetGroupIconLayoutState(frame, true)
    end

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
    -- CDM CDM 패턴: 아이콘을 UIParent 자식으로 두고 컨테이너는 앵커 참조만
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
    frame._ddLayoutCooldownID = cooldownID
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

    -- 8. [FIX] 고아 정리(alpha=0)에서 복원: 관리 등록 시 alpha 명시적 복원
    -- CDM 패턴은 CDM 가시성을 신뢰하지만, DDingUI 자체의 고아 정리에서
    -- SetAlpha(0)이 적용된 프레임은 CDM Show() 후에도 alpha=0이 유지됨
    -- → 관리 등록 시점에 alpha=1로 복원해야 UpdateGroup의 alpha 루프 전에 보임
    frame._ddProvisionalHidden = nil

    -- [FIX] FlightHide 활성 중이면 새 아이콘도 알파 0 적용
    local fh = DDingUI.FlightHide
    if fh and fh.isActive then
        frame:SetAlpha(0)
    elseif frame:GetAlpha() < 0.01 then
        -- 고아 정리 등으로 alpha=0이면 즉시 복원
        frame:SetAlpha(1)
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
    ResetGroupIconLayoutState(frame, true)

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
    frame._ddLayoutCooldownID = nil
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

    -- [HOOK] SetSize 스냅백: CDM이 managed 프레임 크기 변경 시 DDingUI 크기로 복원
    -- 드루이드 변신 등으로 CDM이 Layout 후 추가 SetSize 호출 → 종횡비 깨짐 방지
    if not frame._ddSetSizeHooked then
        hooksecurefunc(frame, "SetSize", function(self, w, h)
            if self._ddSettingSize then return end
            if self._ddIsManaged and self._ddTargetWidth then
                if math_abs(w - self._ddTargetWidth) > 0.5 or math_abs(h - self._ddTargetHeight) > 0.5 then
                    self._ddSettingSize = true
                    self:SetSize(self._ddTargetWidth, self._ddTargetHeight)
                    self._ddSettingSize = false
                end
            end
        end)
        frame._ddSetSizeHooked = true
    end

    -- [HOOK] SetScale 스냅백: CDM이 managed 프레임 스케일 변경 시 1로 복원
    if not frame._ddSetScaleHooked then
        hooksecurefunc(frame, "SetScale", function(self, scale)
            if self._ddSettingScale then return end
            if self._ddIsManaged and math_abs(scale - 1) > 0.01 then
                self._ddSettingScale = true
                self:SetScale(1)
                self._ddSettingScale = false
            end
        end)
        frame._ddSetScaleHooked = true
    end

    -- [HOOK] ClearAllPoints 스냅백: CDM Layout이 앵커 제거 → DDingUI 앵커 즉시 복원
    -- CDM이 ClearAllPoints() + SetPoint(뷰어기준) 호출 → pts=0 순간 발생 → 렌더링 안 됨
    if not frame._ddClearPointsHooked then
        hooksecurefunc(frame, "ClearAllPoints", function(self)
            if self._ddSettingPosition then return end
            if self._ddIsManaged and self._ddTargetPoint and self._ddContainerRef then
                self._ddSettingPosition = true
                self:SetPoint(
                    self._ddTargetPoint,
                    self._ddContainerRef,
                    self._ddTargetRelPoint or "CENTER",
                    self._ddTargetX or 0,
                    self._ddTargetY or 0
                )
                self._ddSettingPosition = false
            end
        end)
        frame._ddClearPointsHooked = true
    end

    -- [HOOK] SetPoint 스냅백: CDM Layout이 뷰어 기준으로 SetPoint → DDingUI 앵커로 복원
    if not frame._ddSetPointHooked then
        hooksecurefunc(frame, "SetPoint", function(self, point, relativeTo, ...)
            if self._ddSettingPosition then return end
            if self._ddIsManaged and self._ddContainerRef then
                -- CDM이 뷰어 기준으로 SetPoint → DDingUI 컨테이너 기준으로 교체
                if relativeTo ~= self._ddContainerRef then
                    self._ddSettingPosition = true
                    self:ClearAllPoints()
                    self:SetPoint(
                        self._ddTargetPoint,
                        self._ddContainerRef,
                        self._ddTargetRelPoint or "CENTER",
                        self._ddTargetX or 0,
                        self._ddTargetY or 0
                    )
                    self._ddSettingPosition = false
                end
            end
        end)
        frame._ddSetPointHooked = true
    end

    if not frame._fcShowHideHooked then
        frame:HookScript("OnShow", function(self)
            DLog("OnShow", tostring(self.cooldownID), "managed=" .. tostring(self._ddIsManaged), "sup=" .. tostring(self._ddSuppressed), "pt=" .. tostring(self._ddTargetPoint))
            if self._ddSuppressed then self:SetAlpha(0); return end
            if not FrameController.initialized then return end
            -- managed 프레임 즉시 복원
            if self._ddIsManaged and self._ddTargetPoint then
                DLog("  → instant restore to", tostring(self._ddContainerRef and self._ddContainerRef:GetName()))
                self:SetParent(UIParent)
                self:ClearAllPoints()
                self:SetPoint(
                    self._ddTargetPoint,
                    self._ddContainerRef,
                    self._ddTargetRelPoint or "CENTER",
                    self._ddTargetX or 0,
                    self._ddTargetY or 0
                )
                if self:GetAlpha() < 0.01 then
                    local fh = DDingUI.FlightHide
                    if not (fh and fh.isActive) then
                        self:SetAlpha(1)
                        DLog("  → alpha restored to 1")
                    end
                end
            else
                DLog("  → NO instant restore (managed=" .. tostring(self._ddIsManaged) .. " pt=" .. tostring(self._ddTargetPoint) .. ")")
            end
            ScheduleReconcile(CONFIG.DEBOUNCE_ONSHOW)
        end)
        frame:HookScript("OnHide", function(self)
            DLog("OnHide", tostring(self.cooldownID), "managed=" .. tostring(self._ddIsManaged))
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
                if state.specChangeDetected or state.talentChangeDetected then return end
                ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
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

            if frame then
                state.acquireSerial = state.acquireSerial + 1
                frame._ddAcquireSerial = state.acquireSerial
                FrameController:_ResetAcquiredCooldownFrame(frame)
            end

            -- [CDM 패턴] acquire 시 scale 강제 1 (CDM이 변경할 수 있음)
            if frame and frame.SetScale then
                frame:SetScale(1)
            end

            -- 이미 managed 프레임이면 즉시 re-parent (CDM이 viewer 자식으로 되돌린 것 복구)
            if frame and frame._ddIsManaged and frame._ddContainerRef then
                frame:SetParent(UIParent)
                frame:SetFrameStrata("MEDIUM")
                local container = frame._ddContainerRef
                if container then
                    frame:SetFrameLevel(container:GetFrameLevel() + 10)
                end

                -- [CDM Phase 1: 스냅백 훅 삭제] 이전 LayoutGroup 위치로 즉시 복원하던 코드를 주석 처리합니다.
                -- 대신 MarkDirty()를 통해 큐가 터질 때 Watchdog이 좌표를 갱신하게 둡니다.
                -- if frame._ddTargetPoint then
                --     frame:ClearAllPoints()
                --     frame:SetPoint(...)
                -- end
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
            if itemFrame._ddIsManaged then
                ResetGroupIconLayoutState(itemFrame, false)
                local container = itemFrame._ddContainerRef
                if container then
                    container._lastCombinedLayoutHash = nil
                    container._lastDynHash = nil
                end
            end
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
                                    -- [CDM Phase 1: 스냅백 삭제]
                                    -- Layout 직후 다시 뺏어오는 행위 삭제. Reconcile 엔진이 일괄 처리합니다.
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
            -- [CDM 패턴] OnHide 복원: 블리자드가 뷰어를 Hide()해도 즉시 다시 Show
            -- 스펙 변경/레벨업 등에서 뷰어가 사라지는 것 방지
            viewer:HookScript("OnHide", function(self)
                if InCombatLockdown() then return end
                -- 로딩 화면 중에는 재표시하지 않음
                if FrameController._loadingScreenActive then return end
                if state.specChangeDetected or state.talentChangeDetected then return end
                C_Timer.After(0, function()
                    if InCombatLockdown() then return end
                    if state.specChangeDetected or state.talentChangeDetected then return end
                    if not self:IsShown() then
                        self:Show()
                    end
                end)
            end)
        end
    end

    -- [CDM 패턴 C] Provisional Reparent — 리로드 직후 비관리 아이콘 즉시 reparent
    -- OnCooldownIDSet에서 아이콘이 아직 managed가 아니더라도,
    -- ClassifyIcon으로 하이재킹 대상 판별 → 즉시 SetParent(UIParent) + 그룹 컨테이너 CENTER
    -- CDM Layout이 뷰어 내부에 배치하기 전에 reparent 완료
    local function ProvisionalReparent(frame)
        if not frame then return end
        if frame._ddIsManaged then return end  -- 이미 관리 중이면 snap-back으로 처리됨
        if frame.isEditing then return end

        -- cooldownID 가져오기
        local cooldownID = frame.cooldownID
        if not cooldownID then return end
        if issecretvalue and issecretvalue(cooldownID) then return end

        -- ClassifyIcon으로 하이재킹 대상 그룹 판별
        local GroupManager = DDingUI.GroupManager
        if not GroupManager then return end
        local groupName = GroupManager:ClassifyIcon(cooldownID)
        if not groupName then return end

        -- 그룹 컨테이너가 있으면 즉시 reparent + 임시 위치
        local GroupRenderer = DDingUI.GroupRenderer
        local container = GroupRenderer and GroupRenderer.groupFrames and GroupRenderer.groupFrames[groupName]
        if container then
            -- [CDM Phase 2] 중앙에 모이는 팝업 현상 방지를 위해 큐 처리 전까지 우주 밖으로 날려버림 (Provisional Placement)
            frame:SetParent(UIParent)
            frame:SetFrameStrata("MEDIUM")
            frame:SetFrameLevel(container:GetFrameLevel() + 10)
            frame._ddSettingPosition = true
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 9999, -9999)
            frame._ddSettingPosition = false
        else
            -- 컨테이너 없으면 alpha=0으로 숨김 (DoFullUpdate에서 복원)
            frame._ddProvisionalHidden = true
            frame:SetAlpha(0)
        end
    end

    -- [HOOK E] Mixin.OnCooldownIDSet — 아이콘 생성 즉시 감지 (CDM 핵심 패턴)
    -- CDM이 아이콘에 cooldownID를 할당하는 시점 → 가장 빠른 감지 타이밍
    -- HOOK C(SetCooldownID)보다 먼저 실행되어 managed 프레임 즉시 snap-back
    if CooldownViewerBuffIconItemMixin and CooldownViewerBuffIconItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffIconItemMixin, "OnCooldownIDSet", function(frame)
            FrameController._diagCounters.cooldownIDSet = FrameController._diagCounters.cooldownIDSet + 1
            if not FrameController.initialized then return end
            if frame and frame.isEditing then return end
            if frame and frame._ddCDMStaleBuff then
                RestoreStaleBuffFrame(frame)
            end
            if frame and frame.SetScale then frame:SetScale(1) end
            -- managed 프레임 즉시 snap-back
            if frame and frame._ddIsManaged and frame._ddContainerRef then
                local parent = frame:GetParent()
                if parent and parent ~= UIParent then
                    frame:SetParent(UIParent)
                    frame:SetFrameStrata("MEDIUM")
                    if frame._ddContainerRef then
                        frame:SetFrameLevel(frame._ddContainerRef:GetFrameLevel() + 10)
                    end
                    -- [CDM Phase 1: 스냅백 훅 삭제] 이전 LayoutGroup 위치로 즉시 복원하던 코드를 제거.
                    -- if frame._ddTargetPoint then ... end
                end
                -- [FIX] 고아 정리 alpha=0 → 관리 상태 복원 시 즉시 alpha=1
                if frame:GetAlpha() < 0.01 and not (DDingUI.FlightHide and DDingUI.FlightHide.isActive) then
                    frame:SetAlpha(1)
                end
            else
                -- [CDM 패턴 C] 비관리 아이콘: provisional reparent
                -- Wait for the completed pool scan to assign the final anchor.
            end
            MarkDirty()
            if not state.pollingActive then EnablePolling() end
        end)
    end

    if CooldownViewerEssentialItemMixin and CooldownViewerEssentialItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerEssentialItemMixin, "OnCooldownIDSet", function(frame)
            if not FrameController.initialized then return end
            if frame and frame.isEditing then return end
            if frame and frame.SetScale then frame:SetScale(1) end
            if frame and frame._ddIsManaged and frame._ddContainerRef then
                local parent = frame:GetParent()
                if parent and parent ~= UIParent then
                    frame:SetParent(UIParent)
                    frame:SetFrameStrata("MEDIUM")
                    if frame._ddContainerRef then
                        frame:SetFrameLevel(frame._ddContainerRef:GetFrameLevel() + 10)
                    end
                    -- [CDM Phase 1: 스냅백 삭제]
                    -- if frame._ddTargetPoint then ... end
                end
                -- [FIX] 고아 정리 alpha=0 → 관리 상태 복원 시 즉시 alpha=1
                if frame:GetAlpha() < 0.01 and not (DDingUI.FlightHide and DDingUI.FlightHide.isActive) then
                    frame:SetAlpha(1)
                end
            else
                -- [CDM 패턴 C] 비관리 아이콘: provisional reparent
                ProvisionalReparent(frame)
            end
            MarkDirty()
            if not state.pollingActive then EnablePolling() end
        end)
    end

    if CooldownViewerUtilityItemMixin and CooldownViewerUtilityItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerUtilityItemMixin, "OnCooldownIDSet", function(frame)
            if not FrameController.initialized then return end
            if frame and frame.isEditing then return end
            if frame and frame.SetScale then frame:SetScale(1) end
            if frame and frame._ddIsManaged and frame._ddContainerRef then
                local parent = frame:GetParent()
                if parent and parent ~= UIParent then
                    frame:SetParent(UIParent)
                    frame:SetFrameStrata("MEDIUM")
                    if frame._ddContainerRef then
                        frame:SetFrameLevel(frame._ddContainerRef:GetFrameLevel() + 10)
                    end
                    -- [CDM Phase 1: 스냅백 삭제]
                    -- if frame._ddTargetPoint then ... end
                end
            else
                -- [CDM 패턴 C] 비관리 아이콘: provisional reparent
                ProvisionalReparent(frame)
            end
            MarkDirty()
            if not state.pollingActive then EnablePolling() end
        end)
    end

    -- [HOOK G] BuffBar Mixin OnCooldownIDSet (CDM 패턴 — DDingUI 누락 보완)
    if CooldownViewerBuffBarItemMixin and CooldownViewerBuffBarItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffBarItemMixin, "OnCooldownIDSet", function(frame)
            if not FrameController.initialized then return end
            if frame and frame.isEditing then return end
            if frame and frame.SetScale then frame:SetScale(1) end
            MarkDirty()
            if not state.pollingActive then EnablePolling() end
        end)
    end

    -- [HOOK H] BuffBar OnActiveStateChanged (CDM 패턴)
    if CooldownViewerBuffBarItemMixin and CooldownViewerBuffBarItemMixin.OnActiveStateChanged then
        hooksecurefunc(CooldownViewerBuffBarItemMixin, "OnActiveStateChanged", function(frame)
            if not FrameController.initialized then return end
            MarkDirty()
            if not state.pollingActive then EnablePolling() end
        end)
    end

    -- [HOOK I] Buff OnActiveStateChanged (CDM 패턴)
    if CooldownViewerBuffIconItemMixin and CooldownViewerBuffIconItemMixin.OnActiveStateChanged then
        hooksecurefunc(CooldownViewerBuffIconItemMixin, "OnActiveStateChanged", function(frame)
            FrameController._diagCounters.activeStateChanged = FrameController._diagCounters.activeStateChanged + 1
            if not FrameController.initialized then return end
            MarkDirty()
            if not state.pollingActive then EnablePolling() end
        end)
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
    if not IsSafeNumber(cooldownID) then return nil end
    return idIconMap[cooldownID]
end

function FrameController:GetIconSource(cooldownID)
    if not IsSafeNumber(cooldownID) then return nil end
    return iconSourceMap[cooldownID]
end

function FrameController:IsScanHoldActive()
    if not state.scanHoldActive then return false end
    local now = GetTime and GetTime() or 0
    return (now - (state.scanHoldStartedAt or 0)) < 1.0
end

function FrameController:GetSpellNameForID(cooldownID)
    if not IsSafeNumber(cooldownID) then return nil end
    return iconSpellNameMap[cooldownID]
end

function FrameController:GetTrackedBuffSpellNames()
    return trackedBuffSpellNames
end

function FrameController:GetTrackedBuffSpellOrder()
    return trackedBuffSpellOrder
end

function FrameController:GetTrackedBuffSpellTextures()
    return trackedBuffSpellTextures
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
    return state.specChangeDetected or state.talentChangeDetected or false
end

-- [PERF] Reconcile 체인에서 ScanCDMViewers가 이미 완료되었는지 조회
-- DoFullUpdate에서 이중 스캔 방지용
function FrameController:IsScanCompleted()
    return state.scanCompleted or false
end

-- ============================================================
-- 옵저버 패턴
-- ============================================================

function FrameController:RegisterCallback(func)
    self._callbacks[#self._callbacks + 1] = func
end

function FrameController:NotifyUpdate(changes)
    for _, cb in pairs(self._callbacks) do
        local ok, err = pcall(cb, "reconcile", changes)
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
                -- [FIX] 편집모드 테스트 프레임 스킵
                if not icon.isEditing then
                    -- [FIX] pcall 래핑 — WoW 12.0+ 보호 함수 Taint 방지
                    pcall(function()
                        if not InCombatLockdown() then
                            icon:SetPropagateMouseClicks(true)
                        end
                        icon:SetMouseClickEnabled(true)
                        icon:SetMouseMotionEnabled(true)
                    end)

                    -- 클릭 핸들러 (중복 방지)
                    if not icon._gsClickHooked then
                        icon._gsClickHooked = true
                        icon:SetScript("OnMouseDown", function(self, button)
                            if not FrameController._editMode then return end
                            if button == "LeftButton" and IsControlKeyDown() then
                                FrameController:ShowGroupAssignPopup(self)
                            elseif button == "RightButton" then
                                FrameController:ShowGroupAssignPopup(self)
                            end
                        end)
                    end
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
                -- [FIX] 편집모드 테스트 프레임 스킵
                if not icon.isEditing then
                    -- [FIX] pcall 래핑 — WoW 12.0+ 보호 함수 Taint 방지
                    pcall(function()
                        if not InCombatLockdown() then
                            icon:SetPropagateMouseClicks(false)
                        end
                        icon:SetMouseClickEnabled(false)
                        icon:SetMouseMotionEnabled(false)
                    end)
                end
            end
        end
    end
end

-- ============================================================
-- 그룹 선택 팝업 (EasyMenu)
-- ============================================================

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
        },
    }

    local assignmentItems = {
        {
            text = L["Auto (Default)"] or "자동 (기본)",
            func = function()
                GroupManager:UnassignSpell(spellName)
                if DDingUI.GroupSystem then DDingUI.GroupSystem:Refresh() end
            end,
        },
    }
    for _, group in ipairs(groups) do
        local groupName = group.name
        assignmentItems[#assignmentItems + 1] = {
            text = groupName,
            func = function()
                GroupManager:AssignSpell(spellName, groupName)
                if DDingUI.GroupSystem then DDingUI.GroupSystem:Refresh() end
            end,
        }
    end
    menuList[#menuList + 1] = {
        text = L["Group Assignment"] or "Group Assignment",
        menuList = assignmentItems,
    }
    menuList[#menuList + 1] = { isSeparator = true }

    local customizer = DDingUI.IconCustomization
    if customizer and customizer.GetIconContext and customizer.BuildContextMenuItems then
        local spellID, viewerType = customizer:GetIconContext(icon)
        local items = customizer:BuildContextMenuItems(spellID, viewerType)
        for _, item in ipairs(items or {}) do
            menuList[#menuList + 1] = item
        end
    end

    if SL and SL.ShowCascadingMenu then
        SL.ShowCascadingMenu(icon, menuList, "TOPLEFT", "BOTTOMLEFT", 0, -2)
    end
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
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- [FIX] 전투 진입 시 즉시 재스캔
    -- [CDM 패턴] LOADING_SCREEN — OnHide 복원에서 로딩 중 재표시 방지
    eventFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
    eventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "LOADING_SCREEN_ENABLED" then
            FrameController._loadingScreenActive = true
            return
        elseif event == "LOADING_SCREEN_DISABLED" then
            FrameController._loadingScreenActive = false
            -- [CDM 패턴] 로딩 화면 끝 → 뷰어 재셋업 + 전체 큐
            if FrameController.initialized then
                FrameController:RefreshViewerRefs()
                MarkDirty()
                if not state.pollingActive then EnablePolling() end
                ScheduleViewerTransitionRecovery(true, true, true)
            end
            return
        end

        if not FrameController.initialized then return end

        if event == "PLAYER_ENTERING_WORLD" or event == "PVP_MATCH_STATE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
            RunPvPTransitionRecovery(event)
            return
        end

        if event == "PLAYER_REGEN_DISABLED" then
            -- [FIX] 전투 진입 시 CDM이 아이콘을 Show하므로 burst 재시작
            -- 첫 전투 시 강화효과 정렬 지연 방지
            MarkDirty()
            if not state.pollingActive then
                EnablePolling()
            end
            return

        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LEVEL_UP" then
            FrameController:_BeginPendingSpecChange(true)
        elseif event == "TRAIT_CONFIG_UPDATED" then
            if state.specChangeDetected then return end
            FrameController:_BeginPendingSpecChange(false)

        elseif event == "SPELLS_CHANGED" then
            if state.specChangeDetected or state.talentChangeDetected then
                FrameController:_FinishPendingSpecChange(state.specChangeVersion)
            else
                ScheduleReconcile(CONFIG.DEBOUNCE_NORMAL)
            end
        end
    end)
    self._eventFrame = eventFrame

    self.initialized = true
    self._initTime = GetTime() -- [DIAG] 진단 시간 기준점

    -- [CDM 패턴] OnUpdate 폴링 시작 — CDM 아이콘 상태를 자동 감지
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
    wipe(iconStateMap)
    wipe(iconLayoutIndexMap)
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
    ScheduleReconcile(0, true)
end

-- ============================================================
-- [DEBUG] /ddbuffdump — 버프 아이콘 상태 정밀 덤프
-- ============================================================
SLASH_DDBUFFDUMP1 = "/ddbuffdump"
SlashCmdList["DDBUFFDUMP"] = function()
    local P = function(...) print("|cff00ff00[DDingUI BuffDump]|r", ...) end
    P("=== CDM Pool State ===")
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then P("BuffIconCooldownViewer NOT FOUND") return end

    local activeCount, activeShown, activeHidden = 0, 0, 0
    if viewer.itemFramePool then
        for frame in viewer.itemFramePool:EnumerateActive() do
            activeCount = activeCount + 1
            if frame:IsShown() then
                activeShown = activeShown + 1
            else
                activeHidden = activeHidden + 1
            end
        end
    end
    P("Active pool:", activeCount, "Shown:", activeShown, "Hidden:", activeHidden)

    P("=== idIconMap (BuffIcon entries) ===")
    local mapCount = 0
    for cid, icon in pairs(idIconMap) do
        local src = iconSourceMap[cid]
        if src == "BuffIconCooldownViewer" then
            mapCount = mapCount + 1
            local parentName = icon:GetParent() and icon:GetParent():GetName() or "unnamed"
            -- [DIAG] spellID 캐싱 상태 + C_CooldownViewer 실시간 조회
            local cachedSID = icon._ddCachedSpellID or "nil"
            local liveSID = "?"
            local auraActive = "?"
            pcall(function()
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cid)
                if info then
                    local sid = (info.linkedSpellIDs and info.linkedSpellIDs[1])
                        or info.overrideSpellID or info.spellID
                    liveSID = tostring(sid) .. " type=" .. type(sid)
                    if sid and type(sid) == "number" and sid > 0 then
                        local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
                        auraActive = aura and "YES" or "NO"
                    end
                else
                    liveSID = "info=nil"
                end
            end)
            P("  CID:", cid, "Cached:", cachedSID, "Live:", liveSID, "Aura:", auraActive, "Shown:", icon:IsShown(), "Alpha:", icon:GetAlpha())
        end
    end
    P("idIconMap buff entries:", mapCount)

    P("=== GroupRenderer Managed Icons ===")
    local GR = DDingUI.GroupRenderer
    if GR and GR.groupFrames then
        for groupName, groupFrame in pairs(GR.groupFrames) do
            if groupFrame._managedIcons then
                local count = 0
                for i, icon in pairs(groupFrame._managedIcons) do
                    if icon then count = count + 1 end
                end
                if count > 0 then
                    P("Group:", groupName, "Icons:", count)
                    for i, icon in pairs(groupFrame._managedIcons) do
                        if icon then
                            local parentName = icon:GetParent() and icon:GetParent():GetName() or "unnamed"
                            local src = icon.cooldownID and iconSourceMap[icon.cooldownID] or "?"
                            P("  [" .. i .. "] CID:", icon.cooldownID or "nil", "Src:", src, "Shown:", icon:IsShown(), "Alpha:", string.format("%.2f", icon:GetAlpha()), "Parent:", parentName, "Managed:", tostring(icon._ddIsManaged))
                        end
                    end
                end
            end
        end
    end
    P("=== Done ===")
end

-- ============================================================
-- [DIAG] /ddbuffdiag — 버프 분류 진단
-- ============================================================
SLASH_DDBUFFDIAG1 = "/ddbuffdiag"
SlashCmdList["DDBUFFDIAG"] = function()
    local P = function(...) print("|cff00ccff[BuffDiag]|r", ...) end
    P("=== 버프 분류 진단 ===")

    -- 1. 각 뷰어별 아이콘 스캔
    local viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
    for _, vName in ipairs(viewers) do
        local v = _G[vName]
        if v and v.itemFramePool then
            local total, shown, hasAura = 0, 0, 0
            local samples = {}
            for icon in v.itemFramePool:EnumerateActive() do
                total = total + 1
                if icon:IsShown() then shown = shown + 1 end
                pcall(function()
                    if icon.auraSpellID then hasAura = hasAura + 1 end
                end)
                if #samples < 5 and icon.cooldownID then
                    local sid = "?"
                    pcall(function()
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID)
                        if info then
                            sid = tostring((info.linkedSpellIDs and info.linkedSpellIDs[1]) or info.spellID or "?")
                            local n = C_Spell.GetSpellName(tonumber(sid) or 0)
                            if n then sid = sid .. "(" .. n .. ")" end
                        end
                    end)
                    samples[#samples+1] = string.format("  CID:%s Shown:%s Aura:%s SID:%s",
                        tostring(icon.cooldownID), tostring(icon:IsShown()),
                        tostring(icon.auraSpellID ~= nil), sid)
                end
            end
            P(vName, "Total:", total, "Shown:", shown, "HasAura:", hasAura)
            for _, s in ipairs(samples) do P(s) end
        else
            P(vName, "= NOT FOUND")
        end
    end

    -- 2. 프로필 그룹 목록 + autoClassify 상태
    local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    if gs then
        P("--- 프로필 그룹 ---")
        P("  autoClassify:", tostring(gs.autoClassify))
        if gs.groups then
            for groupName, groupSettings in pairs(gs.groups) do
                P("  [" .. groupName .. "] enabled:" .. tostring(groupSettings.enabled)
                    .. " type:" .. (groupSettings.groupType or "cdm")
                    .. " autoFilter:" .. (groupSettings.autoFilter or "nil"))
            end
        else
            P("  groups = nil!")
        end
    else
        P("  groupSystem = nil!")
    end

    -- 3. 프로필 spellAssignments
    if gs and gs.spellAssignments then
        P("--- spellAssignments ---")
        local count = 0
        for spell, group in pairs(gs.spellAssignments) do
            P("  ", spell, "→", group)
            count = count + 1
        end
        if count == 0 then P("  (없음)") end
    else
        P("--- spellAssignments: nil ---")
    end

    -- 3. 그룹별 아이콘 분류 결과
    P("--- 그룹별 분류 ---")
    local GroupManager = DDingUI.GroupManager
    if GroupManager and GroupManager.ClassifyIcon then
        local classified = {}
        for cooldownID, icon in pairs(idIconMap) do
            local group = GroupManager:ClassifyIcon(cooldownID)
            classified[group or "nil"] = (classified[group or "nil"] or 0) + 1
        end
        for g, c in pairs(classified) do
            P("  ", g, ":", c, "icons")
        end
    end

    P("=== Done ===")
end

-- ============================================================
-- [DEBUG] /ddalpha — 아이콘 alpha 상태 진단
-- 투명도 0 문제 디버깅용: 모든 managed 아이콘의 alpha/플래그 출력
-- ============================================================
SLASH_DDALPHA1 = "/ddalpha"
SlashCmdList["DDALPHA"] = function()
    local P = function(...) print("|cff00ff00[DDAlpha]|r", ...) end
    P("=== Alpha 진단 시작 ===")

    -- 1. FlightHide 상태
    local fh = DDingUI.FlightHide
    if fh then
        P("FlightHide: isActive=", tostring(fh.isActive), " _hiding=", tostring(fh._hiding))
    else
        P("FlightHide: 모듈 없음")
    end

    -- 2. GroupRenderer 프레임별 상태
    local GroupRenderer = DDingUI.GroupRenderer
    if GroupRenderer and GroupRenderer.groupFrames then
        for groupName, frame in pairs(GroupRenderer.groupFrames) do
            local gs = DDingUI.GroupSystem and DDingUI.GroupSystem.db
            local groupSettings = gs and gs.groups and gs.groups[groupName]
            local groupAlpha = groupSettings and groupSettings.groupAlpha or 1.0
            P("--- 그룹: ", groupName, " containerAlpha=", string.format("%.2f", frame:GetAlpha()), " groupAlpha설정=", groupAlpha, " shown=", tostring(frame:IsShown()))

            if frame._managedIcons then
                local total = 0
                local hidden = 0
                for i = 1, (frame._iconCount or #frame._managedIcons) do
                    local ic = frame._managedIcons[i]
                    if ic then
                        total = total + 1
                        local alpha = ic:GetAlpha()
                        if alpha < 0.01 then
                            hidden = hidden + 1
                            -- 상세 출력 (alpha=0인 아이콘만)
                            local flags = ""
                            if ic._ddSuppressed then flags = flags .. " SUPPRESSED" end
                            if ic._ddDynBridgeHidden then flags = flags .. " DYNBRIDGE_HIDDEN" end
                            if ic._ddingHidden then flags = flags .. " DDING_HIDDEN" end
                            if ic._ddProvisionalHidden then flags = flags .. " PROVISIONAL" end
                            if ic._ddSuppressAlphaHooked then flags = flags .. " ALPHA_HOOKED" end
                            if ic._ddDynBridgeAlphaHooked then flags = flags .. " BRIDGE_ALPHA_HOOKED" end
                            local cdID = "?"
                            pcall(function() cdID = tostring(ic.cooldownID) end)
                            local auraID = "?"
                            pcall(function() auraID = tostring(ic.auraSpellID) end)
                            P("  [HIDDEN] alpha=", string.format("%.2f", alpha),
                              " cdID=", cdID,
                              " auraID=", auraID,
                              " managed=", tostring(ic._ddIsManaged),
                              " shown=", tostring(ic:IsShown()),
                              flags)
                        end
                    end
                end
                P("  합계: ", total, "개 중 ", hidden, "개 alpha=0")
            end
        end
    else
        P("GroupRenderer 없음")
    end

    -- 3. CDM 뷰어 직접 스캔 (managed 아닌 아이콘도 포함)
    P("--- CDM 뷰어 직접 스캔 ---")
    local viewers = {"EssentialCooldownViewer", "BuffIconCooldownViewer", "UtilityCooldownViewer"}
    for _, vName in ipairs(viewers) do
        local v = _G[vName]
        if v and v.itemFramePool then
            local total = 0
            local alphaZero = 0
            for icon in v.itemFramePool:EnumerateActive() do
                total = total + 1
                local a = icon:GetAlpha()
                if a < 0.01 then
                    alphaZero = alphaZero + 1
                    if alphaZero <= 5 then  -- 처음 5개만 상세 출력
                        local flags = ""
                        if icon._ddSuppressed then flags = flags .. " SUPPRESSED" end
                        if icon._ddDynBridgeHidden then flags = flags .. " DYNBRIDGE_HIDDEN" end
                        if icon._ddingHidden then flags = flags .. " DDING_HIDDEN" end
                        if icon._ddSuppressAlphaHooked then flags = flags .. " ALPHA_HOOKED" end
                        if icon._ddDynBridgeAlphaHooked then flags = flags .. " BRIDGE_ALPHA_HOOKED" end
                        local cdID = "?"
                        pcall(function() cdID = tostring(icon.cooldownID) end)
                        P("  ", vName, " [a=0]",
                          " cdID=", cdID,
                          " managed=", tostring(icon._ddIsManaged),
                          flags)
                    end
                end
            end
            P("  ", vName, ": ", total, "개 활성 중 ", alphaZero, "개 alpha=0")
        end
    end

    P("=== Alpha 진단 완료 ===")
end

-- ============================================================
-- [DEBUG] /ddwatch — SetAlpha(0) 실시간 호출 추적
-- BuffIcon 프레임에 SetAlpha 훅을 설치하여 alpha=0 호출 시
-- 스택 트레이스 출력. /ddwatch 다시 입력하면 중지.
-- ============================================================
local ddWatchActive = false
SLASH_DDWATCH1 = "/ddwatch"
SlashCmdList["DDWATCH"] = function()
    local P = function(...) print("|cffff8800[DDWatch]|r", ...) end

    if ddWatchActive then
        ddWatchActive = false
        P("감시 중지. (훅은 제거 불가, /reload 필요)")
        return
    end

    ddWatchActive = true
    P("SetAlpha(0) 호출 추적 시작. BuffIcon 프레임에 훅 설치 중...")

    local bv = _G["BuffIconCooldownViewer"]
    if not bv or not bv.itemFramePool then
        P("|cffff0000BuffIconCooldownViewer 없음!|r")
        return
    end

    local hookCount = 0
    for icon in bv.itemFramePool:EnumerateActive() do
        -- 프레임 자체의 SetAlpha 훅
        if not icon._ddWatchAlphaHooked then
            icon._ddWatchAlphaHooked = true
            hookCount = hookCount + 1
            hooksecurefunc(icon, "SetAlpha", function(self, alpha)
                if not ddWatchActive then return end
                if type(alpha) ~= "number" then return end
                if alpha < 0.01 then
                    local cdID = "?"
                    pcall(function() cdID = tostring(self.cooldownID) end)
                    local isMgd = self._ddIsManaged and "Y" or "N"
                    local parent = self:GetParent()
                    local pName = parent and (parent:GetName() or "?") or "nil"
                    local stack = debugstack(2, 5, 0)
                    P("|cffff0000[FRAME→0]|r cd=", cdID,
                      " mgd=", isMgd,
                      " parent=", pName,
                      " sup=", tostring(self._ddSuppressed or false))
                    P("  stack: ", stack)
                end
            end)
        end

        -- 아이콘 텍스처의 SetAlpha 훅
        local texObj = icon.icon or icon.Icon
        if texObj and not texObj._ddWatchTexAlphaHooked then
            texObj._ddWatchTexAlphaHooked = true
            hooksecurefunc(texObj, "SetAlpha", function(self, alpha)
                if not ddWatchActive then return end
                if type(alpha) ~= "number" then return end
                if alpha < 0.01 then
                    local parentFrame = self:GetParent()
                    local cdID = "?"
                    pcall(function() cdID = tostring(parentFrame and parentFrame.cooldownID) end)
                    local stack = debugstack(2, 5, 0)
                    P("|cffff6600[TEX→0]|r cd=", cdID)
                    P("  stack: ", stack)
                end
            end)
        end

        -- Hide() 훅도 설치
        if not icon._ddWatchHideHooked then
            icon._ddWatchHideHooked = true
            hooksecurefunc(icon, "Hide", function(self)
                if not ddWatchActive then return end
                if self._ddIsManaged and self:GetParent() == UIParent then
                    local cdID = "?"
                    pcall(function() cdID = tostring(self.cooldownID) end)
                    local stack = debugstack(2, 5, 0)
                    P("|cffff00ff[HIDE]|r cd=", cdID, " (managed, UIParent)")
                    P("  stack: ", stack)
                end
            end)
        end
    end

    P(hookCount, "개 프레임에 훅 설치 완료. 투명 발생 시 자동 출력됩니다.")
end


-- ============================================================
-- [DEBUG] /dddump — 전체 아이콘 프레임 덤프
-- 투명도 문제 발생 시 실행: 모든 CDM/Dynamic 아이콘 상태 출력
-- ============================================================
SLASH_DDDUMP1 = "/dddump"
SlashCmdList["DDDUMP"] = function()
    local P = function(...) print("|cff00ffff[DDDump]|r", ...) end
    P("=== 전체 아이콘 덤프 시작 ===")

    -- 1. 모든 CDM 뷰어 풀의 모든 아이콘
    local viewers = {"EssentialCooldownViewer", "BuffIconCooldownViewer", "UtilityCooldownViewer"}
    for _, vName in ipairs(viewers) do
        local v = _G[vName]
        if v and v.itemFramePool then
            P("--- ", vName, " (viewer alpha=", string.format("%.2f", v:GetAlpha()), " shown=", tostring(v:IsShown()), ") ---")
            local count = 0
            for icon in v.itemFramePool:EnumerateActive() do
                count = count + 1
                local fA = icon:GetAlpha()
                local shown = icon:IsShown()
                local texObj = icon.icon or icon.Icon
                local tA = texObj and texObj.GetAlpha and texObj:GetAlpha() or -1
                local tShown = texObj and texObj.IsShown and texObj:IsShown()
                local hasTex = true
                pcall(function() hasTex = (texObj and texObj:GetTexture()) ~= nil end)

                -- 비정상 상태만 출력 (alpha=0, 텍스처 없음, hidden 등)
                local problem = false
                local issues = ""
                if fA < 0.01 then issues = issues .. " fA=0"; problem = true end
                if tA >= 0 and tA < 0.01 then issues = issues .. " tA=0"; problem = true end
                if not shown then issues = issues .. " HIDDEN"; problem = true end
                if tShown == false then issues = issues .. " TEX_HIDDEN"; problem = true end
                if not hasTex then issues = issues .. " NO_TEX"; problem = true end

                if problem then
                    local cdID = "?"
                    pcall(function() cdID = tostring(icon.cooldownID) end)
                    local auraID = "?"
                    pcall(function() auraID = tostring(icon.auraSpellID) end)
                    local parent = icon:GetParent()
                    local parentName = parent and (parent:GetName() or "unnamed") or "nil"
                    local flags = ""
                    if icon._ddIsManaged then flags = flags .. " MGD" end
                    if icon._ddSuppressed then flags = flags .. " SUP" end
                    if icon._ddDynBridgeHidden then flags = flags .. " DYN" end
                    if icon._ddingHidden then flags = flags .. " BTB" end
                    P("  #", count, issues,
                      " cd=", cdID, " aura=", auraID,
                      " parent=", parentName, flags)
                end
            end
            P("  총: ", count, "개 활성")
        end
    end

    -- 2. 그룹별 managed 아이콘 상태
    local GR = DDingUI.GroupRenderer
    if GR and GR.groupFrames then
        P("--- GroupRenderer 그룹 ---")
        for gName, frame in pairs(GR.groupFrames) do
            local iconCount = frame._iconCount or 0
            local totalManaged = frame._managedIcons and #frame._managedIcons or 0
            P("  ", gName, ": _iconCount=", iconCount, " totalManagedArr=", totalManaged,
              " containerAlpha=", string.format("%.2f", frame:GetAlpha()),
              " shown=", tostring(frame:IsShown()))

            if frame._managedIcons then
                for i = 1, math.max(iconCount, totalManaged) do
                    local ic = frame._managedIcons[i]
                    if ic then
                        local fA = ic:GetAlpha()
                        local shown = ic:IsShown()
                        local texObj = ic.icon or ic.Icon
                        local tA = texObj and texObj.GetAlpha and texObj:GetAlpha() or -1
                        local tShown = texObj and texObj.IsShown and texObj:IsShown()

                        local problem = false
                        local issues = ""
                        if fA < 0.01 then issues = issues .. " fA=0"; problem = true end
                        if tA >= 0 and tA < 0.01 then issues = issues .. " tA=0"; problem = true end
                        if not shown then issues = issues .. " HIDDEN"; problem = true end
                        if tShown == false then issues = issues .. " TEX_HIDDEN"; problem = true end
                        if i > iconCount then issues = issues .. " STALE(>"..iconCount..")"; problem = true end

                        if problem then
                            local cdID = "?"
                            pcall(function() cdID = tostring(ic.cooldownID) end)
                            P("    [", i, "]", issues, " cd=", cdID, " fA=", string.format("%.2f", fA))
                        end
                    end
                end
            end
        end
    end
    -- 3. CDM BuffIcon 분류 파이프라인 추적 (핵심 진단)
    P("--- BuffIcon 분류 파이프라인 ---")
    local bv2 = _G["BuffIconCooldownViewer"]
    if bv2 and bv2.itemFramePool then
        local CDMHook = DDingUI.CDMHookEngine
        local GM = DDingUI.GroupManager
        local bridge = DDingUI.DynamicIconBridge
        local suppressed = bridge and bridge.GetSuppressedSpellIDs and bridge:GetSuppressedSpellIDs() or {}

        for icon in bv2.itemFramePool:EnumerateActive() do
            local cdID = "?"
            pcall(function() cdID = tostring(icon.cooldownID) end)
            local isShown = icon:IsShown()
            local isMgd = icon._ddIsManaged
            local fA = icon:GetAlpha()

            -- spellName 해소
            local spellName = "?"
            pcall(function()
                if CDMHook then
                    spellName = CDMHook:GetSpellNameForID(icon.cooldownID) or "nil"
                end
            end)

            -- suppress 체크
            local isSup = false
            pcall(function()
                if icon.auraSpellID and suppressed[icon.auraSpellID] then isSup = true end
            end)
            if not isSup then
                pcall(function()
                    if icon.cooldownID and suppressed[icon.cooldownID] then isSup = true end
                end)
            end

            -- 그룹 분류
            local classGroup = "?"
            pcall(function()
                if GM then classGroup = GM:ClassifyIcon(icon.cooldownID) or "nil" end
            end)

            -- idIconMap 포함 여부
            local inMap = false
            pcall(function()
                if idIconMap and idIconMap[icon.cooldownID] then inMap = true end
            end)

            -- 상태 요약
            local status = ""
            if not isShown then status = status .. " NOT_SHOWN" end
            if isSup then status = status .. " SUPPRESSED" end
            if icon._ddSuppressed then status = status .. " _ddSUP" end
            if icon._ddDynBridgeHidden then status = status .. " _ddDYN" end
            if icon._ddingHidden then status = status .. " _ddBTB" end
            if isMgd then status = status .. " MANAGED" end
            if not inMap then status = status .. " NOT_IN_MAP" end
            if fA < 0.01 then status = status .. " fA=0" end

            local parent = icon:GetParent()
            local pName = parent and (parent:GetName() or "?") or "nil"

            P("  cd=", cdID,
              " spell=", spellName,
              " group=", classGroup,
              " parent=", pName,
              status)
        end
    end

    -- 4. idIconMap 전체 (FrameController 내부 맵)
    P("--- idIconMap 내용 ---")
    local mapCount = 0
    if idIconMap then
        for cid, icon in pairs(idIconMap) do
            mapCount = mapCount + 1
        end
    end
    P("  총 ", mapCount, "개 엔트리")

    P("=== 전체 아이콘 덤프 완료 ===")
end
