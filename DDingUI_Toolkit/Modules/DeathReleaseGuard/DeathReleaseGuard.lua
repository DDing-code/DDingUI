local addonName, ns = ...

local L = ns.L
local DDingToolKit = ns.DDingToolKit

local DeathReleaseGuard = {}
ns.DeathReleaseGuard = DeathReleaseGuard

local DEFAULT_HOLD_DURATION = 1.5
local MAX_ACTIVATION_ATTEMPTS = 12
local ACTIVATION_RETRY_DELAY = 0.05

local watcher
local blocker
local blockerLabel
local blockerProgress
local holdStartedAt
local activationSerial = 0

local function GetSettings()
    local profile = ns.db and ns.db.profile
    return profile and profile.DeathReleaseGuard
end

local function GetHoldDuration()
    local settings = GetSettings()
    local duration = settings and tonumber(settings.holdDuration)
    if not duration or duration < 0.5 then
        return DEFAULT_HOLD_DURATION
    end
    return duration
end

local function ShouldProtect()
    local settings = GetSettings()
    if not settings or settings.enabled == false then
        return false
    end
    if not UnitIsDead("player") or UnitIsGhost("player") then
        return false
    end

    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid" and IsInRaid()
end

local function SetProgress(progress)
    if not blockerProgress or not blocker then return end
    if progress <= 0 then
        blockerProgress:Hide()
        return
    end

    local width = math.max((blocker:GetWidth() or 1) - 4, 1)
    blockerProgress:SetWidth(math.max(width * progress, 1))
    blockerProgress:Show()
end

local function ResetHold()
    holdStartedAt = nil

    if blockerLabel then
        blockerLabel:SetFormattedText(
            L["DEATH_RELEASE_GUARD_HOLD_PROMPT"] or "Hold Ctrl: %.1fs",
            GetHoldDuration()
        )
    end
    SetProgress(0)
end

local function StopProtection()
    activationSerial = activationSerial + 1
    ResetHold()

    if blocker then
        blocker:SetScript("OnUpdate", nil)
        blocker:Hide()
    end
end

local function UpdateHold()
    if not IsControlKeyDown() then
        if holdStartedAt then
            ResetHold()
        end
        return
    end

    local now = GetTimePreciseSec and GetTimePreciseSec() or GetTime()
    holdStartedAt = holdStartedAt or now

    local duration = GetHoldDuration()
    local elapsed = now - holdStartedAt
    local remaining = math.max(duration - elapsed, 0)
    SetProgress(math.min(elapsed / duration, 1))

    if remaining <= 0 then
        blocker:SetScript("OnUpdate", nil)
        blocker:Hide()
        return
    end

    blockerLabel:SetFormattedText(
        L["DEATH_RELEASE_GUARD_HOLD_PROMPT"] or "Hold Ctrl: %.1fs",
        remaining
    )
end

local function BuildBlocker(releaseButton)
    if not blocker then
        blocker = CreateFrame("Button", "DDingUI_Toolkit_DeathReleaseGuard", releaseButton)
        blocker:SetFrameStrata("DIALOG")
        blocker:EnableMouse(true)
        blocker:RegisterForClicks("AnyDown", "AnyUp")
        blocker:SetScript("OnClick", function() end)

        local background = blocker:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.035, 0.04, 0.05, 0.96)

        local border = blocker:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", 0, 0)
        border:SetPoint("TOPRIGHT", 0, 0)
        border:SetHeight(1)
        border:SetColorTexture(1, 0.42, 0, 0.9)

        blockerProgress = blocker:CreateTexture(nil, "ARTWORK")
        blockerProgress:SetPoint("BOTTOMLEFT", 2, 2)
        blockerProgress:SetHeight(3)
        blockerProgress:SetColorTexture(1, 0.42, 0, 1)

        blockerLabel = blocker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        blockerLabel:SetPoint("CENTER")
        blockerLabel:SetTextColor(1, 0.72, 0.35, 1)
    end

    if blocker:GetParent() ~= releaseButton then
        blocker:SetParent(releaseButton)
    end
    blocker:ClearAllPoints()
    blocker:SetAllPoints(releaseButton)
    blocker:SetFrameLevel(releaseButton:GetFrameLevel() + 20)

    return blocker
end

local function FindReleaseButton()
    local visible, popup = StaticPopup_Visible("DEATH")
    if not visible or not popup then return nil end

    if popup.GetButton then
        return popup:GetButton(1)
    end
    return popup.button1
end

local function TryActivate(serial, attempt)
    if serial ~= activationSerial or not ShouldProtect() then return end

    local releaseButton = FindReleaseButton()
    if releaseButton then
        BuildBlocker(releaseButton)
        ResetHold()
        blocker:Show()
        blocker:SetScript("OnUpdate", UpdateHold)
        return
    end

    if attempt < MAX_ACTIVATION_ATTEMPTS then
        C_Timer.After(ACTIVATION_RETRY_DELAY, function()
            TryActivate(serial, attempt + 1)
        end)
    end
end

local function ScheduleProtection()
    StopProtection()
    if not ShouldProtect() then return end

    local serial = activationSerial
    C_Timer.After(ACTIVATION_RETRY_DELAY, function()
        TryActivate(serial, 1)
    end)
end

function DeathReleaseGuard:RefreshSettings()
    if ShouldProtect() then
        ScheduleProtection()
    else
        StopProtection()
    end
end

function DeathReleaseGuard:OnInitialize()
    watcher = watcher or CreateFrame("Frame")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_DEAD" then
            ScheduleProtection()
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:RefreshSettings()
        else
            StopProtection()
        end
    end)
end

function DeathReleaseGuard:OnEnable()
    if not watcher then
        self:OnInitialize()
    end

    watcher:RegisterEvent("PLAYER_DEAD")
    watcher:RegisterEvent("PLAYER_ALIVE")
    watcher:RegisterEvent("PLAYER_UNGHOST")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RefreshSettings()
end

function DeathReleaseGuard:OnDisable()
    if watcher then
        watcher:UnregisterAllEvents()
    end
    StopProtection()
end

DDingToolKit:RegisterModule("DeathReleaseGuard", DeathReleaseGuard)
