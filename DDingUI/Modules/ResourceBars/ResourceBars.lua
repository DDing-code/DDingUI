local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local C_Timer = _G.C_Timer
local GetTime = _G.GetTime

-- Create namespace
DDingUI.ResourceBars = DDingUI.ResourceBars or {}
local ResourceBars = DDingUI.ResourceBars

-- IMPORTANT: Use weak table to store DDingUI data instead of adding fields to Blizzard frames
-- This prevents taint propagation that causes secret value errors in WoW 12.0+
local FrameData = setmetatable({}, { __mode = "k" })  -- weak keys

local function GetFrameData(frame)
    if not frame then return nil end
    if not FrameData[frame] then
        FrameData[frame] = {}
    end
    return FrameData[frame]
end

local function IsHooked(frame, hookName)
    local data = FrameData[frame]
    return data and data[hookName]
end

local function SetHooked(frame, hookName)
    GetFrameData(frame)[hookName] = true
end

-- Update throttling to prevent flashing and improve performance
local lastPrimaryUpdate = 0
local lastSecondaryUpdate = 0
local UPDATE_THROTTLE = 0.066  -- 66ms minimum between updates (~15fps)

-- Grace Period (DDingUI style) - don't hide bars during spec/level changes
-- CDM frames may not have loaded new spec's abilities yet
local GRACE_PERIOD_DURATION = 5.0  -- seconds
local gracePeriodUntil = 0

-- Check if we're in grace period (exported for PrimaryPowerBar/SecondaryPowerBar)
function ResourceBars.IsInGracePeriod()
    return GetTime() < gracePeriodUntil
end

-- 바의 마지막 너비를 자동너비 폴백용으로 저장
local function SaveBarFallbackWidth(bar)
    if not bar then return end
    if bar._lastWidth and bar._lastWidth > 0 then
        bar._graceFallbackWidth = bar._lastWidth
    end
end

-- Invalidate cached position/size values (force recalculation)
local function InvalidateBarCaches()
    if DDingUI.powerBar then
        -- 자동너비 폴백용 마지막 너비 저장
        SaveBarFallbackWidth(DDingUI.powerBar)
        DDingUI.powerBar._lastAnchor = nil
        DDingUI.powerBar._lastAnchorPoint = nil
        DDingUI.powerBar._lastOffsetX = nil
        DDingUI.powerBar._lastOffsetY = nil
        DDingUI.powerBar._lastWidth = nil
        DDingUI.powerBar._lastHeight = nil
        DDingUI.powerBar._lastCfgWidth = nil
        -- Retry 플래그 리셋 - OnSpecChanged에서 새로운 retry 스케줄 허용
        DDingUI.powerBar._anchorRetryScheduled = nil
        DDingUI.powerBar._anchorRetryCount = 0
    end
    if DDingUI.secondaryPowerBar then
        SaveBarFallbackWidth(DDingUI.secondaryPowerBar)
        DDingUI.secondaryPowerBar._lastAnchor = nil
        DDingUI.secondaryPowerBar._lastAnchorPoint = nil
        DDingUI.secondaryPowerBar._lastOffsetX = nil
        DDingUI.secondaryPowerBar._lastOffsetY = nil
        DDingUI.secondaryPowerBar._lastWidth = nil
        DDingUI.secondaryPowerBar._lastHeight = nil
        DDingUI.secondaryPowerBar._lastCfgWidth = nil
        -- Retry 플래그 리셋
        DDingUI.secondaryPowerBar._anchorRetryScheduled = nil
        DDingUI.secondaryPowerBar._anchorRetryCount = 0
    end
end

-- Get functions from sub-modules
local GetPrimaryResource = ResourceBars.GetPrimaryResource
local GetSecondaryResource = ResourceBars.GetSecondaryResource

local runeUpdateTicker = nil
local soulFragmentTicker = nil
local staggerUpdateTicker = nil
local specialResourceEventFrame = nil
local specialResourceMode = nil
local maelstromAuraInstanceID = nil
local soulMetaAuraInstanceID = nil
local specChangeTimers = {}
local shapeshiftSettleTimers = {}
local soulMetaSettleTimers = {}
local viewerSettleTimers = {}
local transitionRefreshTimers = {}
local VIEWER_SHOW_SETTLE_DELAYS = { 0.1, 0.3 }
local VIEWER_HIDE_SETTLE_DELAYS = { 0.05 }
local LEVEL_REFRESH_DELAYS = { 0.3, 1.5 }
local LOADING_REFRESH_DELAYS = { 0.5, 2.0 }

local MAELSTROM_WEAPON_SPELL_ID = 344179
local SOUL_META_SPELL_ID = 1217607

local function CancelTimerList(timers)
    for _, timer in pairs(timers) do
        if timer and not timer:IsCancelled() then
            timer:Cancel()
        end
    end
    wipe(timers)
end

local function ScheduleTimerList(timers, delays, callback)
    CancelTimerList(timers)
    for index, delay in ipairs(delays) do
        timers[index] = C_Timer.NewTimer(delay, function()
            timers[index] = nil
            callback(index)
        end)
    end
end

local function IsSafeNumber(value)
    if type(value) ~= "number" then
        return false
    end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        return ok and accessible
    end
    return true
end

local function GetCurrentSpecID()
    local spec = GetSpecialization and GetSpecialization()
    return spec and GetSpecializationInfo and GetSpecializationInfo(spec)
end

local function StopSoulFragmentTicker()
    if soulFragmentTicker then
        soulFragmentTicker:Cancel()
        soulFragmentTicker = nil
    end
end

local function StartSoulFragmentTicker()
    if soulFragmentTicker then return end

    soulFragmentTicker = C_Timer.NewTicker(0.1, function()
        local cfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.secondaryPowerBar
        if cfg and cfg.enabled == false then
            StopSoulFragmentTicker()
            return
        end

        local playerClass = select(2, UnitClass("player"))
        if playerClass ~= "DEMONHUNTER" then
            StopSoulFragmentTicker()
            return
        end

        local resource = GetSecondaryResource and GetSecondaryResource()
        if resource == "SOUL" then
            ResourceBars:UpdateSecondaryPowerBar()
        else
            StopSoulFragmentTicker()
        end
    end)
end

local function StopRuneUpdateTicker()
    if runeUpdateTicker then
        runeUpdateTicker:Cancel()
        runeUpdateTicker = nil
    end
end

local function StopStaggerUpdateTicker()
    if staggerUpdateTicker then
        staggerUpdateTicker:Cancel()
        staggerUpdateTicker = nil
    end
end

local function HasActiveStagger()
    local stagger = UnitStagger and (UnitStagger("player") or 0) or 0
    return IsSafeNumber(stagger) and stagger > 0
end

local function StartStaggerUpdateTicker()
    if staggerUpdateTicker then return end
    staggerUpdateTicker = C_Timer.NewTicker(0.1, function()
        local cfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.secondaryPowerBar
        if cfg and cfg.enabled == false then
            StopStaggerUpdateTicker()
            return
        end

        if GetSecondaryResource and GetSecondaryResource() == "STAGGER" then
            ResourceBars:UpdateSecondaryPowerBar()
            if not InCombatLockdown() and not HasActiveStagger() then
                StopStaggerUpdateTicker()
            end
        else
            StopStaggerUpdateTicker()
        end
    end)
end

local function AreRunesRecharging()
    if type(GetRuneCooldown) ~= "function" then
        return false
    end

    local maxRunes = UnitPowerMax("player", Enum.PowerType.Runes) or 0
    if maxRunes <= 0 then
        maxRunes = 6
    end

    for i = 1, maxRunes do
        local start, duration, runeReady = GetRuneCooldown(i)
        if not runeReady and ((duration and duration > 0) or (start and start > 0)) then
            return true
        end
    end

    return false
end

local function StartRuneUpdateTicker()
    if runeUpdateTicker then return end

    runeUpdateTicker = C_Timer.NewTicker(0.1, function()
        local cfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.secondaryPowerBar
        if cfg and cfg.enabled == false then
            StopRuneUpdateTicker()
            return
        end

        local resource = GetSecondaryResource()
        if resource == Enum.PowerType.Runes and AreRunesRecharging() then
            lastSecondaryUpdate = GetTime()
            ResourceBars:UpdateSecondaryPowerBar()
        else
            StopRuneUpdateTicker()
        end
    end)
end

local function SeedMaelstromAura()
    local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(MAELSTROM_WEAPON_SPELL_ID)
    maelstromAuraInstanceID = aura and aura.auraInstanceID or nil
end

local function SeedSoulMetaAura()
    local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(SOUL_META_SPELL_ID)
    soulMetaAuraInstanceID = aura and aura.auraInstanceID or nil
end

local function AuraUpdateHasSpell(info, spellID, trackedInstanceID)
    if not info or info.isFullUpdate then
        return true
    end

    if info.addedAuras then
        for _, aura in ipairs(info.addedAuras) do
            if IsSafeNumber(aura.spellId) and aura.spellId == spellID then
                return true
            end
        end
    end

    if trackedInstanceID and info.updatedAuraInstanceIDs then
        for _, id in ipairs(info.updatedAuraInstanceIDs) do
            if id == trackedInstanceID then
                return true
            end
        end
    end

    if trackedInstanceID and info.removedAuraInstanceIDs then
        for _, id in ipairs(info.removedAuraInstanceIDs) do
            if id == trackedInstanceID then
                return true
            end
        end
    end

    return false
end

local function OnStaggerResourceEvent()
    if GetSecondaryResource and GetSecondaryResource() ~= "STAGGER" then
        StopStaggerUpdateTicker()
        return
    end

    local now = GetTime()
    if now - lastSecondaryUpdate >= UPDATE_THROTTLE then
        lastSecondaryUpdate = now
        ResourceBars:UpdateSecondaryPowerBar()
    end

    if InCombatLockdown() or HasActiveStagger() then
        StartStaggerUpdateTicker()
    else
        StopStaggerUpdateTicker()
    end
end

local function ScheduleSoulMetaSettle()
    gracePeriodUntil = GetTime() + GRACE_PERIOD_DURATION
    StartSoulFragmentTicker()
    ResourceBars:UpdateSecondaryPowerBar()

    CancelTimerList(soulMetaSettleTimers)
    local function DoSettleUpdate()
        ResourceBars:UpdateSecondaryPowerBar()
    end
    soulMetaSettleTimers[1] = C_Timer.NewTimer(0.3, DoSettleUpdate)
    soulMetaSettleTimers[2] = C_Timer.NewTimer(0.7, DoSettleUpdate)
    soulMetaSettleTimers[3] = C_Timer.NewTimer(1.5, DoSettleUpdate)
    soulMetaSettleTimers[4] = C_Timer.NewTimer(GRACE_PERIOD_DURATION + 0.5, DoSettleUpdate)
end

local function OnSpecialResourceEvent(_, event, unit, info)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        OnStaggerResourceEvent()
        return
    end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if unit == "player" then
            OnStaggerResourceEvent()
        end
        return
    end
    if event ~= "UNIT_AURA" or unit ~= "player" then
        return
    end

    local resource = GetSecondaryResource and GetSecondaryResource()
    if resource == "MAELSTROM_WEAPON" then
        if not AuraUpdateHasSpell(info, MAELSTROM_WEAPON_SPELL_ID, maelstromAuraInstanceID) then
            return
        end
        SeedMaelstromAura()
        ResourceBars:UpdateSecondaryPowerBar()
        return
    end

    if resource == "SOUL" then
        if not AuraUpdateHasSpell(info, SOUL_META_SPELL_ID, soulMetaAuraInstanceID) then
            return
        end
        local wasInMeta = soulMetaAuraInstanceID ~= nil
        SeedSoulMetaAura()
        if wasInMeta and not soulMetaAuraInstanceID then
            ScheduleSoulMetaSettle()
        else
            StartSoulFragmentTicker()
            ResourceBars:UpdateSecondaryPowerBar()
        end
    end
end

local function SetSpecialResourceMode(mode)
    if specialResourceMode == mode then
        return
    end

    if not specialResourceEventFrame then
        specialResourceEventFrame = CreateFrame("Frame")
        specialResourceEventFrame:SetScript("OnEvent", OnSpecialResourceEvent)
    end

    specialResourceEventFrame:UnregisterAllEvents()
    specialResourceMode = mode

    if mode == "stagger" then
        specialResourceEventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
        specialResourceEventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
        specialResourceEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        specialResourceEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif mode == "maelstrom" or mode == "soul" then
        specialResourceEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    end
end

local function RefreshSpecialResourceTracking()
    local resource = GetSecondaryResource and GetSecondaryResource()
    local specID = GetCurrentSpecID()

    if resource == Enum.PowerType.Runes and AreRunesRecharging() then
        StartRuneUpdateTicker()
    else
        StopRuneUpdateTicker()
    end

    if resource == "SOUL" then
        SeedSoulMetaAura()
        StartSoulFragmentTicker()
    else
        StopSoulFragmentTicker()
        soulMetaAuraInstanceID = nil
    end

    if resource == "STAGGER" and specID == 268 then
        SetSpecialResourceMode("stagger")
        OnStaggerResourceEvent()
    elseif resource == "MAELSTROM_WEAPON" and specID == 263 then
        SetSpecialResourceMode("maelstrom")
        SeedMaelstromAura()
    elseif resource == "SOUL" then
        SetSpecialResourceMode("soul")
    else
        SetSpecialResourceMode(nil)
        StopStaggerUpdateTicker()
        maelstromAuraInstanceID = nil
    end
end

-- EVENT HANDLER

function ResourceBars:OnUnitPower(_, unit)
    -- Be forgiving: if unit is nil or not "player", still update.
    -- It's cheap and avoids missing power updates.
    if unit and unit ~= "player" then
        return
    end

    local now = GetTime()
    if now - lastPrimaryUpdate >= UPDATE_THROTTLE then
        self:UpdatePowerBar()
        lastPrimaryUpdate = now
    end
    if now - lastSecondaryUpdate >= UPDATE_THROTTLE then
        self:UpdateSecondaryPowerBar()
        lastSecondaryUpdate = now
    end
end

function ResourceBars:OnRuneEvent()
    local cfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.secondaryPowerBar
    if cfg and cfg.enabled == false then
        StopRuneUpdateTicker()
        return
    end

    local resource = GetSecondaryResource()
    if resource ~= Enum.PowerType.Runes then
        StopRuneUpdateTicker()
        return
    end

    local now = GetTime()
    if now - lastSecondaryUpdate >= UPDATE_THROTTLE then
        lastSecondaryUpdate = now
        self:UpdateSecondaryPowerBar()
    end

    if AreRunesRecharging() then
        StartRuneUpdateTicker()
    else
        StopRuneUpdateTicker()
    end
end

-- REFRESH

function ResourceBars:RefreshAll()
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
    if self.UpdateBuffTrackerBar then
        self:UpdateBuffTrackerBar()
    end
end

local function UpdateBarsForViewerSettle(includeBuffTracker)
    ResourceBars:UpdatePowerBar()
    ResourceBars:UpdateSecondaryPowerBar()
    if includeBuffTracker and ResourceBars.UpdateBuffTrackerBar then
        ResourceBars:UpdateBuffTrackerBar()
    end
end

-- EVENT HANDLERS

-- Helper function to hook viewer OnShow (called from Initialize and OnSpecChanged)
-- Returns true if any viewer is currently shown
local function HookViewerOnShow()
    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
    }
    local anyShown = false
    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        -- Check if viewer exists and doesn't have our hook yet
        -- (new frames created after spec change won't have the flag)
        if viewer then
            -- Use FrameData weak table to avoid tainting Blizzard frames
            if not IsHooked(viewer, "resourceBarWatching") then
                SetHooked(viewer, "resourceBarWatching")
                viewer:HookScript("OnShow", function()
                    ScheduleTimerList(viewerSettleTimers, VIEWER_SHOW_SETTLE_DELAYS, function()
                        UpdateBarsForViewerSettle(false)
                    end)
                end)
                -- OnHide 훅 추가: viewer가 숨겨지면 자원바를 UIParent로 폴백
                viewer:HookScript("OnHide", function()
                    -- Grace period는 전문화 변경 시에만 설정 (폼 변경 시에는 제외)
                    -- 폼 변경은 자원 타입이 의도적으로 변경되므로 이전 바를 정상적으로 숨겨야 함
                    if not ResourceBars._shapeshiftInProgress then
                        gracePeriodUntil = math.max(gracePeriodUntil, GetTime() + GRACE_PERIOD_DURATION)
                    end

                    ScheduleTimerList(viewerSettleTimers, VIEWER_HIDE_SETTLE_DELAYS, function()
                        UpdateBarsForViewerSettle(true)
                    end)
                end)
            end
            -- Track if any viewer is shown (for immediate update after hook)
            if viewer:IsShown() then
                anyShown = true
            end
        end
    end
    return anyShown
end

-- [FIX] 이전 spec 변경 타이머 취소용
local specChangeQueued = false

local specChangeDispatchDelay = 0
local specChangeDispatchFrame = CreateFrame("Frame")
specChangeDispatchFrame:Hide()
specChangeDispatchFrame:SetScript("OnUpdate", function(self, elapsed)
    specChangeDispatchDelay = specChangeDispatchDelay - (elapsed or 0)
    if specChangeDispatchDelay > 0 then
        return
    end

    self:Hide()
    specChangeQueued = false
    ResourceBars:OnSpecChanged()
end)

local function QueueSpecChangedRefresh()
    if specChangeQueued then
        return
    end
    specChangeQueued = true
    specChangeDispatchDelay = 0.05
    specChangeDispatchFrame:Show()
end

function ResourceBars:OnSpecChanged()
    -- DDingUI-style Grace Period approach:
    -- 1. Invalidate caches
    -- 2. Set grace period (don't hide bars during this time)
    -- 3. Progressive updates with previous timer cancellation
    -- 4. Final cleanup update after grace period ends

    -- 1. Invalidate cached position/size values
    InvalidateBarCaches()

    -- 2. Set grace period - bars won't be hidden due to missing anchor during this time
    gracePeriodUntil = GetTime() + GRACE_PERIOD_DURATION

    local function DoUpdate()
        -- Re-hook viewer OnShow in case Blizzard recreated the frames
        HookViewerOnShow()

        local now = GetTime()
        lastPrimaryUpdate = now
        lastSecondaryUpdate = now
        self:UpdatePowerBar()
        self:UpdateSecondaryPowerBar()

        RefreshSpecialResourceTracking()
    end

    -- [FIX] 이전 spec 변경 타이머 취소 — 연속 변경 시 중복 업데이트 방지
    CancelTimerList(specChangeTimers)

    -- 3. Progressive updates (6→4회로 단축, 이전 타이머 취소)
    specChangeTimers[1] = C_Timer.NewTimer(0.3, DoUpdate)
    specChangeTimers[2] = C_Timer.NewTimer(1.0, DoUpdate)
    specChangeTimers[3] = C_Timer.NewTimer(2.0, DoUpdate)
    -- 4. Final cleanup update after grace period ends + buffer
    specChangeTimers[4] = C_Timer.NewTimer(GRACE_PERIOD_DURATION + 0.5, DoUpdate)
end

function ResourceBars:OnShapeshiftChanged()
    -- Druid form changes affect primary/secondary resources
    -- Mark form change to prevent viewer OnHide from setting grace period
    -- (Grace period is for spec changes; form changes intentionally change resources)
    ResourceBars._shapeshiftInProgress = true

    local now = GetTime()
    lastPrimaryUpdate = now
    lastSecondaryUpdate = now
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
    RefreshSpecialResourceTracking()

    CancelTimerList(shapeshiftSettleTimers)

    local function DoSettleUpdate()
        ResourceBars:UpdatePowerBar()
        ResourceBars:UpdateSecondaryPowerBar()
    end

    shapeshiftSettleTimers[1] = C_Timer.NewTimer(0.2, DoSettleUpdate)
    shapeshiftSettleTimers[2] = C_Timer.NewTimer(0.5, DoSettleUpdate)
    shapeshiftSettleTimers[3] = C_Timer.NewTimer(1.0, function()
        ResourceBars._shapeshiftInProgress = nil
        shapeshiftSettleTimers[3] = nil
    end)
end

-- INITIALIZATION

function ResourceBars:Initialize()
    -- Register additional events
    DDingUI:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function()
        QueueSpecChangedRefresh()
    end)
    -- Talent changes can affect CDM viewer layouts, which affects auto-width
    DDingUI:RegisterEvent("PLAYER_TALENT_UPDATE", function()
        QueueSpecChangedRefresh()
    end)
    DDingUI:RegisterEvent("TRAIT_CONFIG_UPDATED", function()
        QueueSpecChangedRefresh()
    end)
    DDingUI:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
        ResourceBars:OnShapeshiftChanged()
    end)
    DDingUI:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        ResourceBars:OnUnitPower()
    end)

    -- Level up event - CDM이 뷰어를 재설정할 수 있으므로 grace period 필요
    -- grace period 없이 RefreshAll만 호출하면 앵커 일시 소실 → CENTER fallback 발생
    DDingUI:RegisterEvent("PLAYER_LEVEL_UP", function()
        -- [FIX] Grace period 설정: 레벨업 시 앵커 일시 소실 대응
        gracePeriodUntil = GetTime() + GRACE_PERIOD_DURATION
        InvalidateBarCaches()

        ScheduleTimerList(transitionRefreshTimers, LEVEL_REFRESH_DELAYS, function(index)
            if index > 1 then
                HookViewerOnShow()
            end
            ResourceBars:RefreshAll()
        end)
    end)

    -- CDM 뷰어 OnShow 감시 (앵커 프레임이 다시 나타날 때 자원바 업데이트)
    C_Timer.After(2.0, HookViewerOnShow)

    -- [FIX] 인스턴스 전환 시 뷰어 재생성 대응 (훅 재설치 + 업데이트)
    DDingUI:RegisterEvent("LOADING_SCREEN_DISABLED", function()
        gracePeriodUntil = GetTime() + GRACE_PERIOD_DURATION
        InvalidateBarCaches()
        ScheduleTimerList(transitionRefreshTimers, LOADING_REFRESH_DELAYS, function()
            HookViewerOnShow()
            ResourceBars:RefreshAll()
        end)
    end)

    -- Vehicle/Override bar events (탈것, 변신 등)
    DDingUI:RegisterEvent("UNIT_ENTERED_VEHICLE", function(_, unit)
        if unit == "player" then ResourceBars:OnShapeshiftChanged() end
    end)
    DDingUI:RegisterEvent("UNIT_EXITED_VEHICLE", function(_, unit)
        if unit == "player" then ResourceBars:OnShapeshiftChanged() end
    end)
    DDingUI:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR", function()
        ResourceBars:OnShapeshiftChanged()
    end)
    DDingUI:RegisterEvent("UPDATE_POSSESS_BAR", function()
        ResourceBars:OnShapeshiftChanged()
    end)

    -- POWER UPDATES (RegisterUnitEvent으로 플레이어만 필터링)
    local powerEventFrame = CreateFrame("Frame")
    powerEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    powerEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    powerEventFrame:SetScript("OnEvent", function(_, event, unit)
        ResourceBars:OnUnitPower(_, unit)
    end)

    -- RUNES: rune cooldown progression does not reliably trigger UNIT_POWER_* updates,
    -- so we listen to rune-specific events and optionally poll while runes are recharging.
    DDingUI:RegisterEvent("RUNE_POWER_UPDATE", function()
        ResourceBars:OnRuneEvent()
    end)
    DDingUI:RegisterEvent("RUNE_TYPE_UPDATE", function()
        ResourceBars:OnRuneEvent()
    end)

    RefreshSpecialResourceTracking()

    -- Initial update (delayed to ensure anchor frames are ready)
    C_Timer.After(0.1, function()
        ResourceBars:UpdatePowerBar()
        ResourceBars:UpdateSecondaryPowerBar()
        if ResourceBars.UpdateBuffTrackerBar then
            ResourceBars:UpdateBuffTrackerBar()
        end
    end)

    -- Also update after a short delay to catch any late-loading frames
    C_Timer.After(0.5, function()
        ResourceBars:UpdatePowerBar()
        ResourceBars:UpdateSecondaryPowerBar()
        if ResourceBars.UpdateBuffTrackerBar then
            ResourceBars:UpdateBuffTrackerBar()
        end
    end)

    -- Initialize buff tracker
    if ResourceBars.InitializeBuffTracker then
        ResourceBars:InitializeBuffTracker()
    end
end

-- Expose event handlers to main addon for backwards compatibility
DDingUI.OnUnitPower = function(self, _, unit) return ResourceBars:OnUnitPower(_, unit) end
DDingUI.OnSpecChanged = function(self) return ResourceBars:OnSpecChanged() end
DDingUI.OnShapeshiftChanged = function(self) return ResourceBars:OnShapeshiftChanged() end
