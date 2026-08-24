-- DDingUI Toolkit - Ready Check Assistant

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib

local ReadyCheckAssistant = {}
ns.ReadyCheckAssistant = ReadyCheckAssistant

local DEFAULT_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local P = ns.UI and ns.UI.popupColors or {
    background = { 0.10, 0.10, 0.10, 0.985 }, control = { 0.06, 0.06, 0.06, 0.94 },
    hover = { 0.14, 0.14, 0.15, 0.96 }, footer = { 0.075, 0.075, 0.08, 0.98 },
    border = { 0.30, 0.30, 0.32, 0.82 }, borderSoft = { 0.25, 0.25, 0.25, 0.50 },
    separator = { 0.20, 0.20, 0.20, 0.40 }, accent = { 0.16, 0.58, 0.68, 0.80 },
    accentText = { 0.42, 0.76, 0.82, 1 }, primary = { 0.09, 0.18, 0.20, 0.98 },
    primaryHover = { 0.11, 0.23, 0.26, 1 }, primaryBorder = { 0.16, 0.50, 0.57, 0.84 },
    primaryBorderHover = { 0.20, 0.62, 0.70, 0.94 }, text = { 0.85, 0.85, 0.85, 1 },
    textBright = { 1, 1, 1, 1 }, textDim = { 0.60, 0.60, 0.60, 1 },
}
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit")
    or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: "
local PANEL_HEIGHT = 196
local COMPACT_PANEL_HEIGHT = 160
local ACTION_BUTTON_WIDTH = 100
local ACTION_BUTTON_HEIGHT = 26

local active = false
local editPreview = false
local readyCheckOpen = false
local readyCheckSerial = 0
local shownAt = 0
local lastReportAt = 0
local frame
local eventFrame = CreateFrame("Frame")

local SLOT_LABELS = {
    [1] = _G.HEADSLOT or "Head",
    [2] = _G.NECKSLOT or "Neck",
    [3] = _G.SHOULDERSLOT or "Shoulder",
    [4] = _G.SHIRTSLOT or "Shirt",
    [5] = _G.CHESTSLOT or "Chest",
    [6] = _G.WAISTSLOT or "Waist",
    [7] = _G.LEGSSLOT or "Legs",
    [8] = _G.FEETSLOT or "Feet",
    [9] = _G.WRISTSLOT or "Wrist",
    [10] = _G.HANDSSLOT or "Hands",
    [11] = _G.FINGER0SLOT or "Finger 1",
    [12] = _G.FINGER1SLOT or "Finger 2",
    [13] = _G.TRINKET0SLOT or "Trinket 1",
    [14] = _G.TRINKET1SLOT or "Trinket 2",
    [15] = _G.BACKSLOT or "Back",
    [16] = _G.MAINHANDSLOT or "Main Hand",
    [17] = _G.SECONDARYHANDSLOT or "Off Hand",
}

local function IsSecret(value)
    return (ns.IsSecretValue and ns.IsSecretValue(value))
        or (issecretvalue and issecretvalue(value))
        or false
end

local function SafeNumber(value)
    if IsSecret(value) or value == nil then return nil end
    local ok, number = pcall(tonumber, value)
    if not ok or IsSecret(number) then return nil end
    return number
end

local function SafeString(value)
    if IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

local function SafeBooleanCall(func, ...)
    if not func then return false end
    local ok, value = pcall(func, ...)
    if not ok or IsSecret(value) then return false end
    return value and true or false
end

local function Clamp(value, minimum, maximum, fallback)
    value = SafeNumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

local function Trim(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function EnsureDB()
    local profile = ns.db and ns.db.profile
    if not profile then return nil end
    if type(profile.ReadyCheckAssistant) ~= "table" then
        local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.ReadyCheckAssistant
        profile.ReadyCheckAssistant = defaults and ns:DeepCopy(defaults) or {}
    end
    return profile.ReadyCheckAssistant
end

local function SetBackdrop(target, background, border)
    target:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
    })
    target:SetBackdropColor(unpack(background))
    target:SetBackdropBorderColor(unpack(border))
end

local function CreatePanelButton(parent, label, primary)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
    button:RegisterForClicks("LeftButtonUp")

    button.label = button:CreateFontString(nil, "OVERLAY")
    button.label:SetFont(DEFAULT_FONT, 11, "OUTLINE")
    button.label:SetPoint("LEFT", 8, 0)
    button.label:SetPoint("RIGHT", -8, 0)
    button.label:SetJustifyH("CENTER")
    button.label:SetWordWrap(false)
    button.label:SetText(label)

    local function ApplyVisual(state)
        if primary then
            if state == "pressed" then
                SetBackdrop(button, P.primary, P.primaryBorder)
            elseif state == "hover" then
                SetBackdrop(button, P.primaryHover, P.primaryBorderHover)
            else
                SetBackdrop(button, P.primary, P.primaryBorder)
            end
            button.label:SetTextColor(unpack(P.textBright))
        else
            if state == "pressed" then
                SetBackdrop(button, P.control, P.borderSoft)
            elseif state == "hover" then
                SetBackdrop(button, P.hover, P.border)
            else
                SetBackdrop(button, P.control, P.borderSoft)
            end
            button.label:SetTextColor(unpack(P.text))
        end
    end

    button:SetScript("OnEnter", function(self)
        self._hovered = true
        ApplyVisual("hover")
    end)
    button:SetScript("OnLeave", function(self)
        self._hovered = false
        ApplyVisual("normal")
    end)
    button:SetScript("OnMouseDown", function()
        ApplyVisual("pressed")
    end)
    button:SetScript("OnMouseUp", function(self)
        ApplyVisual(self._hovered and "hover" or "normal")
    end)
    button:SetScript("OnHide", function(self)
        self._hovered = false
        ApplyVisual("normal")
    end)

    ApplyVisual("normal")
    return button
end

local function SetStatusIcon(texture, atlas)
    if not frame then return end
    if atlas and frame.statusIcon.SetAtlas then
        frame.statusIcon:SetAtlas(atlas)
    else
        frame.statusIcon:SetTexture(texture)
    end
end

local function NormalizeExpectedName(value)
    return Trim(value):lower()
end

local function MatchesExpectedLoadout(currentName, expectedNames)
    local current = NormalizeExpectedName(currentName)
    local expected = Trim(expectedNames)
    if expected == "" then return nil end
    if current == "" then return false end

    for candidate in expected:gmatch("[^,;\r\n]+") do
        if current == NormalizeExpectedName(candidate) then
            return true
        end
    end
    return false
end

function ReadyCheckAssistant:GetSpecializationInfo()
    local specIndex
    if GetSpecialization then
        local ok, value = pcall(GetSpecialization)
        if ok then specIndex = SafeNumber(value) end
    end

    if specIndex and GetSpecializationInfo then
        local ok, specID, specName, _, specIcon = pcall(GetSpecializationInfo, specIndex)
        if ok then
            return {
                id = SafeNumber(specID),
                name = SafeString(specName) or L["RCA_UNKNOWN_SPEC"],
                icon = SafeNumber(specIcon) or 134400,
            }
        end
    end

    local className
    if UnitClass then
        local ok, value = pcall(UnitClass, "player")
        if ok then className = SafeString(value) end
    end
    return {
        id = nil,
        name = className or L["RCA_UNKNOWN_SPEC"],
        icon = 134400,
    }
end

function ReadyCheckAssistant:GetLoadoutInfo(specID)
    if not specID or not C_ClassTalents or not C_Traits or not C_Traits.GetConfigInfo then
        return L["RCA_UNKNOWN_LOADOUT"], false
    end

    local configID
    if C_ClassTalents.GetLastSelectedSavedConfigID then
        local ok, value = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
        if ok then configID = SafeNumber(value) end
    end
    if not configID and C_ClassTalents.GetActiveConfigID then
        local ok, value = pcall(C_ClassTalents.GetActiveConfigID)
        if ok then configID = SafeNumber(value) end
    end
    if not configID then return L["RCA_UNKNOWN_LOADOUT"], false end

    local ok, configInfo = pcall(C_Traits.GetConfigInfo, configID)
    if not ok or IsSecret(configInfo) or type(configInfo) ~= "table" then
        return L["RCA_UNKNOWN_LOADOUT"], false
    end

    local name = SafeString(configInfo.name)
    if not name or Trim(name) == "" then
        return L["RCA_UNSAVED_LOADOUT"], false
    end
    return name, true
end

function ReadyCheckAssistant:GetDurabilityInfo()
    local db = self.db or EnsureDB() or {}
    local threshold = Clamp(db.minDurabilityPercent, 1, 100, 25)
    local sum = 0
    local count = 0
    local lowest = 100
    local lowSlots = {}

    for slotID = 1, 17 do
        local ok, current, maximum = pcall(GetInventoryItemDurability, slotID)
        if ok then
            current = SafeNumber(current)
            maximum = SafeNumber(maximum)
            if current and maximum and maximum > 0 then
                local percent = math.max(0, math.min(100, (current / maximum) * 100))
                sum = sum + percent
                count = count + 1
                lowest = math.min(lowest, percent)
                if percent < threshold then
                    lowSlots[#lowSlots + 1] = {
                        slotID = slotID,
                        label = SLOT_LABELS[slotID] or tostring(slotID),
                        percent = percent,
                    }
                end
            end
        end
    end

    table.sort(lowSlots, function(a, b)
        if a.percent == b.percent then return a.slotID < b.slotID end
        return a.percent < b.percent
    end)

    return {
        average = count > 0 and (sum / count) or 100,
        lowest = count > 0 and lowest or 100,
        lowSlots = lowSlots,
        threshold = threshold,
    }
end

function ReadyCheckAssistant:GetGroupContext()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and SafeBooleanCall(C_ChallengeMode.IsChallengeModeActive) then
        return "MPLUS"
    end

    if GetInstanceInfo then
        local ok, _, instanceType = pcall(GetInstanceInfo)
        if ok and not IsSecret(instanceType) then
            if instanceType == "party" then return "MPLUS" end
            if instanceType == "raid" then return "RAID" end
        end
    end
    if SafeBooleanCall(IsInRaid) then return "RAID" end
    return "PARTY"
end

function ReadyCheckAssistant:GetExpectedLoadout(context)
    local db = self.db or EnsureDB() or {}
    if context == "MPLUS" then return Trim(db.mplusLoadouts) end
    if context == "RAID" then return Trim(db.raidLoadouts) end
    return ""
end

function ReadyCheckAssistant:CollectSnapshot()
    local spec = self:GetSpecializationInfo()
    local loadoutName, loadoutKnown = self:GetLoadoutInfo(spec.id)
    local durability = self:GetDurabilityInfo()
    local context = self:GetGroupContext()
    local expected = self:GetExpectedLoadout(context)
    local loadoutMatch = MatchesExpectedLoadout(loadoutKnown and loadoutName or "", expected)

    local status = "READY"
    if #durability.lowSlots > 0 then
        status = "REPAIR"
    elseif loadoutMatch == false then
        status = loadoutKnown and "LOADOUT" or "UNKNOWN"
    end

    return {
        specID = spec.id,
        specName = spec.name,
        specIcon = spec.icon,
        loadoutName = loadoutName,
        loadoutKnown = loadoutKnown,
        expectedLoadout = expected,
        loadoutMatch = loadoutMatch,
        context = context,
        durability = durability,
        status = status,
    }
end

function ReadyCheckAssistant:CreateFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "DDingToolKit_ReadyCheckAssistantFrame", UIParent, "BackdropTemplate")
    frame:SetSize(390, PANEL_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    SetBackdrop(frame, P.background, P.border)

    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetPoint("TOPLEFT", 1, -1)
    frame.accent:SetPoint("BOTTOMLEFT", 1, 1)
    frame.accent:SetWidth(3)
    frame.accent:SetColorTexture(unpack(P.accent))

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFont(DEFAULT_FONT, 14, "OUTLINE")
    frame.title:SetPoint("TOPLEFT", 16, -13)
    frame.title:SetTextColor(unpack(P.textBright))
    frame.title:SetText(L["RCA_PANEL_TITLE"])

    frame.context = frame:CreateFontString(nil, "OVERLAY")
    frame.context:SetFont(DEFAULT_FONT, 11, "OUTLINE")
    frame.context:SetPoint("TOPRIGHT", -14, -15)
    frame.context:SetTextColor(unpack(P.accentText))

    frame.divider = frame:CreateTexture(nil, "ARTWORK")
    frame.divider:SetPoint("TOPLEFT", 14, -36)
    frame.divider:SetPoint("TOPRIGHT", -14, -36)
    frame.divider:SetHeight(1)
    frame.divider:SetColorTexture(unpack(P.separator))

    frame.specIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.specIcon:SetSize(36, 36)
    frame.specIcon:SetPoint("TOPLEFT", 16, -48)
    frame.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.specText = frame:CreateFontString(nil, "OVERLAY")
    frame.specText:SetFont(DEFAULT_FONT, 13, "OUTLINE")
    frame.specText:SetPoint("TOPLEFT", frame.specIcon, "TOPRIGHT", 10, -1)
    frame.specText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -49)
    frame.specText:SetHeight(16)
    frame.specText:SetJustifyH("LEFT")
    frame.specText:SetJustifyV("MIDDLE")

    frame.loadoutText = frame:CreateFontString(nil, "OVERLAY")
    frame.loadoutText:SetFont(DEFAULT_FONT, 12, "OUTLINE")
    frame.loadoutText:SetPoint("TOPLEFT", frame.specText, "BOTTOMLEFT", 0, -4)
    frame.loadoutText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -69)
    frame.loadoutText:SetHeight(15)
    frame.loadoutText:SetJustifyH("LEFT")
    frame.loadoutText:SetJustifyV("MIDDLE")
    frame.loadoutText:SetWordWrap(false)

    frame.statusIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.statusIcon:SetSize(24, 24)
    frame.statusIcon:SetPoint("TOPRIGHT", -14, -50)

    frame.durabilityBar = CreateFrame("StatusBar", nil, frame)
    frame.durabilityBar:SetPoint("TOPLEFT", 16, -96)
    frame.durabilityBar:SetPoint("TOPRIGHT", -16, -96)
    frame.durabilityBar:SetHeight(18)
    frame.durabilityBar:SetStatusBarTexture(FLAT)
    frame.durabilityBar:SetMinMaxValues(0, 100)
    frame.durabilityBar.background = frame.durabilityBar:CreateTexture(nil, "BACKGROUND")
    frame.durabilityBar.background:SetAllPoints()
    frame.durabilityBar.background:SetColorTexture(unpack(P.control))

    frame.durabilityText = frame.durabilityBar:CreateFontString(nil, "OVERLAY")
    frame.durabilityText:SetFont(DEFAULT_FONT, 11, "OUTLINE")
    frame.durabilityText:SetPoint("CENTER")
    frame.durabilityText:SetTextColor(1, 1, 1, 1)

    frame.detailText = frame:CreateFontString(nil, "OVERLAY")
    frame.detailText:SetFont(DEFAULT_FONT, 10, "OUTLINE")
    frame.detailText:SetPoint("TOPLEFT", frame.durabilityBar, "BOTTOMLEFT", 0, -6)
    frame.detailText:SetPoint("TOPRIGHT", frame.durabilityBar, "BOTTOMRIGHT", 0, -6)
    frame.detailText:SetHeight(12)
    frame.detailText:SetJustifyH("LEFT")
    frame.detailText:SetJustifyV("MIDDLE")
    frame.detailText:SetTextColor(unpack(P.textDim))
    frame.detailText:SetWordWrap(false)

    frame.statusBackground = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.statusBackground:SetPoint("TOPLEFT", 14, -134)
    frame.statusBackground:SetPoint("TOPRIGHT", -14, -134)
    frame.statusBackground:SetHeight(18)
    frame.statusBackground:SetColorTexture(unpack(P.control))

    frame.statusText = frame:CreateFontString(nil, "OVERLAY")
    frame.statusText:SetFont(DEFAULT_FONT, 11, "OUTLINE")
    frame.statusText:SetPoint("TOPLEFT", frame.statusBackground, "TOPLEFT", 6, -2)
    frame.statusText:SetPoint("BOTTOMRIGHT", frame.statusBackground, "BOTTOMRIGHT", -6, 2)
    frame.statusText:SetJustifyH("LEFT")
    frame.statusText:SetJustifyV("MIDDLE")
    frame.statusText:SetWordWrap(false)

    frame.footerBackground = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    frame.footerBackground:SetPoint("BOTTOMLEFT", 1, 1)
    frame.footerBackground:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.footerBackground:SetHeight(38)
    frame.footerBackground:SetColorTexture(unpack(P.footer))

    frame.footerDivider = frame:CreateTexture(nil, "ARTWORK")
    frame.footerDivider:SetPoint("BOTTOMLEFT", 14, 39)
    frame.footerDivider:SetPoint("BOTTOMRIGHT", -14, 39)
    frame.footerDivider:SetHeight(1)
    frame.footerDivider:SetColorTexture(unpack(P.separator))

    frame.openTalentsButton = CreatePanelButton(frame, L["RCA_OPEN_TALENTS"], false)
    frame.openTalentsButton:SetScript("OnClick", function()
        if SafeBooleanCall(InCombatLockdown) then return end
        if PlayerSpellsUtil and PlayerSpellsUtil.TogglePlayerSpellsFrame then
            pcall(PlayerSpellsUtil.TogglePlayerSpellsFrame, 2)
        end
    end)

    frame.reportButton = CreatePanelButton(frame, L["RCA_REPORT_BUTTON"], true)
    frame.reportButton:SetScript("OnClick", function()
        ReadyCheckAssistant:SendReport(false)
    end)

    frame:SetScript("OnUpdate", function()
        if editPreview or not readyCheckOpen or GetTime() - shownAt < 0.25 then return end
        local readyFrame = _G.ReadyCheckFrame
        if readyFrame and not readyFrame:IsShown() then
            ReadyCheckAssistant:Hide()
        end
    end)

    frame:Hide()
    self.frame = frame
    return frame
end

function ReadyCheckAssistant:ApplySettings()
    self.db = EnsureDB()
    if not self.db then return end
    local display = self:CreateFrame()
    local db = self.db
    local width = Clamp(db.width, 320, 560, 390)
    local showDetails = db.showLowSlots ~= false
    local showTalentsButton = db.showOpenTalentsButton ~= false
    local showReportButton = db.showReportButton ~= false
    local showActions = showTalentsButton or showReportButton
    local anchorSide = db.anchorSide == "ABOVE" and "ABOVE" or "BELOW"
    local readyFrame = _G.ReadyCheckFrame

    display:SetSize(width, showActions and PANEL_HEIGHT or COMPACT_PANEL_HEIGHT)
    display:SetScale(Clamp(db.scale, 0.6, 1.8, 1))
    display:ClearAllPoints()
    if readyFrame then
        if anchorSide == "ABOVE" then
            display:SetPoint("BOTTOM", readyFrame, "TOP", Clamp(db.offsetX, -500, 500, 0), Clamp(db.offsetY, -300, 300, 8))
        else
            display:SetPoint("TOP", readyFrame, "BOTTOM", Clamp(db.offsetX, -500, 500, 0), Clamp(db.offsetY, -300, 300, -8))
        end
    else
        display:SetPoint("CENTER", UIParent, "CENTER", Clamp(db.offsetX, -500, 500, 0), Clamp(db.offsetY, -300, 300, -160))
    end

    display.detailText:SetShown(showDetails)
    display.openTalentsButton:SetShown(showTalentsButton)
    display.reportButton:SetShown(showReportButton)
    display.footerBackground:SetShown(showActions)
    display.footerDivider:SetShown(showActions)

    display.reportButton:ClearAllPoints()
    display.openTalentsButton:ClearAllPoints()
    if showReportButton then
        display.reportButton:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", -14, 7)
    end
    if showTalentsButton then
        if showReportButton then
            display.openTalentsButton:SetPoint("RIGHT", display.reportButton, "LEFT", -8, 0)
        else
            display.openTalentsButton:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", -14, 7)
        end
    end
    self:Refresh()
end

local function FormatLowSlots(lowSlots, maximum)
    if #lowSlots == 0 then return L["RCA_NO_LOW_SLOTS"] end
    local parts = {}
    maximum = math.max(1, maximum or 3)
    for index = 1, math.min(#lowSlots, maximum) do
        local slot = lowSlots[index]
        parts[#parts + 1] = string.format("%s %d%%", slot.label, math.floor(slot.percent + 0.5))
    end
    if #lowSlots > maximum then
        parts[#parts + 1] = string.format(L["RCA_MORE_SLOTS"], #lowSlots - maximum)
    end
    return table.concat(parts, "  |  ")
end

function ReadyCheckAssistant:Refresh()
    if not frame or not self.db then return end
    local snapshot = self:CollectSnapshot()
    self.snapshot = snapshot

    frame.context:SetText(L["RCA_CONTEXT_" .. snapshot.context] or snapshot.context)
    frame.specIcon:SetTexture(snapshot.specIcon)
    frame.specText:SetText(string.format(L["RCA_SPEC_FORMAT"], snapshot.specName))

    local loadoutText = string.format(L["RCA_LOADOUT_FORMAT"], snapshot.loadoutName)
    if snapshot.expectedLoadout ~= "" then
        loadoutText = loadoutText .. string.format(L["RCA_EXPECTED_SUFFIX"], snapshot.expectedLoadout)
    end
    frame.loadoutText:SetText(loadoutText)
    if snapshot.loadoutMatch == false then
        frame.loadoutText:SetTextColor(1.00, 0.56, 0.28, 1)
    elseif snapshot.loadoutMatch == true then
        frame.loadoutText:SetTextColor(0.38, 1.00, 0.58, 1)
    else
        frame.loadoutText:SetTextColor(0.82, 0.86, 0.92, 1)
    end

    local durability = snapshot.durability
    local lowest = math.floor(durability.lowest + 0.5)
    local average = math.floor(durability.average + 0.5)
    frame.durabilityBar:SetValue(durability.lowest)
    frame.durabilityText:SetText(string.format(L["RCA_DURABILITY_FORMAT"], lowest, average))
    frame.detailText:SetText(FormatLowSlots(durability.lowSlots, 3))

    if #durability.lowSlots > 0 then
        frame.durabilityBar:SetStatusBarColor(1.00, 0.22, 0.20, 1)
    elseif durability.lowest < 50 then
        frame.durabilityBar:SetStatusBarColor(1.00, 0.62, 0.22, 1)
    else
        frame.durabilityBar:SetStatusBarColor(0.20, 0.82, 0.46, 1)
    end

    if snapshot.status == "REPAIR" then
        SetStatusIcon("Interface\\RaidFrame\\ReadyCheck-NotReady", "UI-LFG-DeclineMark")
        frame.statusText:SetText(string.format(L["RCA_STATUS_REPAIR"], #durability.lowSlots, durability.threshold))
        frame.statusText:SetTextColor(1.00, 0.30, 0.28, 1)
        frame.accent:SetColorTexture(1.00, 0.22, 0.20, 1)
        frame.statusBackground:SetColorTexture(0.18, 0.045, 0.05, 0.94)
        frame:SetBackdropBorderColor(0.72, 0.18, 0.18, 1)
    elseif snapshot.status == "LOADOUT" then
        SetStatusIcon("Interface\\RaidFrame\\ReadyCheck-Waiting", "UI-LFG-PendingMark")
        frame.statusText:SetText(L["RCA_STATUS_LOADOUT"])
        frame.statusText:SetTextColor(1.00, 0.68, 0.25, 1)
        frame.accent:SetColorTexture(1.00, 0.62, 0.18, 1)
        frame.statusBackground:SetColorTexture(0.17, 0.11, 0.035, 0.94)
        frame:SetBackdropBorderColor(0.62, 0.43, 0.16, 1)
    elseif snapshot.status == "UNKNOWN" then
        SetStatusIcon("Interface\\RaidFrame\\ReadyCheck-Waiting", "UI-LFG-PendingMark")
        frame.statusText:SetText(L["RCA_STATUS_UNKNOWN"])
        frame.statusText:SetTextColor(0.90, 0.74, 0.36, 1)
        frame.accent:SetColorTexture(0.88, 0.66, 0.20, 1)
        frame.statusBackground:SetColorTexture(0.15, 0.12, 0.045, 0.94)
        frame:SetBackdropBorderColor(0.54, 0.42, 0.18, 1)
    else
        SetStatusIcon("Interface\\RaidFrame\\ReadyCheck-Ready", "UI-LFG-ReadyMark")
        frame.statusText:SetText(L["RCA_STATUS_READY"])
        frame.statusText:SetTextColor(0.34, 1.00, 0.56, 1)
        frame.accent:SetColorTexture(0.20, 0.82, 0.46, 1)
        frame.statusBackground:SetColorTexture(0.035, 0.15, 0.09, 0.94)
        frame:SetBackdropBorderColor(0.18, 0.56, 0.34, 1)
    end
end

function ReadyCheckAssistant:Show(isPreview)
    if not active and not isPreview then return false end
    if self.db and self.db.hideInCombat ~= false and SafeBooleanCall(InCombatLockdown) and not isPreview then
        return false
    end
    local display = self:CreateFrame()
    self:ApplySettings()
    shownAt = GetTime()
    display:Show()
    return true
end

function ReadyCheckAssistant:Hide()
    readyCheckOpen = false
    if frame then frame:Hide() end
end

function ReadyCheckAssistant:GetReportChannel()
    if SafeBooleanCall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if SafeBooleanCall(IsInRaid) then return "RAID" end
    if SafeBooleanCall(IsInGroup) then return "PARTY" end
    return nil
end

function ReadyCheckAssistant:BuildReport(snapshot)
    local message = string.format(
        L["RCA_REPORT_BASE"],
        snapshot.specName,
        snapshot.loadoutName,
        math.floor(snapshot.durability.average + 0.5)
    )
    if snapshot.status == "REPAIR" then
        message = message .. string.format(L["RCA_REPORT_REPAIR"], #snapshot.durability.lowSlots)
    elseif snapshot.status == "LOADOUT" then
        message = message .. string.format(L["RCA_REPORT_LOADOUT"], snapshot.expectedLoadout)
    elseif snapshot.status == "UNKNOWN" then
        message = message .. L["RCA_REPORT_UNKNOWN"]
    end
    return message
end

function ReadyCheckAssistant:SendReport(isAutomatic)
    self.db = self.db or EnsureDB()
    if not self.db then return false end
    local snapshot = self.snapshot or self:CollectSnapshot()
    if isAutomatic and self.db.reportOnlyProblems ~= false and snapshot.status == "READY" then
        return false
    end
    local now = GetTime()
    if now - lastReportAt < 2 then return false end
    lastReportAt = now

    local message = self:BuildReport(snapshot)
    local channel = self:GetReportChannel()
    if not channel or not SendChatMessage then
        print(CHAT_PREFIX .. message)
        return false
    end
    local ok = pcall(SendChatMessage, message, channel)
    return ok
end

function ReadyCheckAssistant:HandleReadyCheck()
    if not active then return end
    readyCheckSerial = readyCheckSerial + 1
    local serial = readyCheckSerial
    readyCheckOpen = true
    C_Timer.After(0.1, function()
        if not active or not readyCheckOpen or serial ~= readyCheckSerial then return end
        local shown = ReadyCheckAssistant:Show(false)
        if shown and ReadyCheckAssistant.db.autoReport == true then
            ReadyCheckAssistant:SendReport(true)
        end
    end)
end

function ReadyCheckAssistant:SaveCurrentLoadout(context)
    self.db = self.db or EnsureDB()
    if not self.db then return false end
    local spec = self:GetSpecializationInfo()
    local name, known = self:GetLoadoutInfo(spec.id)
    if not known then
        print(CHAT_PREFIX .. L["RCA_SAVE_LOADOUT_FAILED"])
        return false
    end
    if context == "MPLUS" then
        self.db.mplusLoadouts = name
    else
        self.db.raidLoadouts = name
    end
    print(CHAT_PREFIX .. string.format(L["RCA_SAVE_LOADOUT_SUCCESS"], name))
    self:Refresh()
    return true
end

function ReadyCheckAssistant:OnInitialize()
    self.db = EnsureDB()
    self.initialized = true
end

function ReadyCheckAssistant:OnEnable()
    self.db = EnsureDB()
    active = true
    self:CreateFrame()
    self:ApplySettings()
end

function ReadyCheckAssistant:OnDisable()
    active = false
    editPreview = false
    readyCheckOpen = false
    if frame then frame:Hide() end
end

function ReadyCheckAssistant:OnMediaChanged()
    if frame then
        frame.title:SetFont(DEFAULT_FONT, 14, "OUTLINE")
        frame.context:SetFont(DEFAULT_FONT, 11, "OUTLINE")
        frame.specText:SetFont(DEFAULT_FONT, 13, "OUTLINE")
        frame.loadoutText:SetFont(DEFAULT_FONT, 12, "OUTLINE")
        frame.durabilityText:SetFont(DEFAULT_FONT, 11, "OUTLINE")
        frame.detailText:SetFont(DEFAULT_FONT, 10, "OUTLINE")
        frame.statusText:SetFont(DEFAULT_FONT, 11, "OUTLINE")
        frame.openTalentsButton.label:SetFont(DEFAULT_FONT, 11, "OUTLINE")
        frame.reportButton.label:SetFont(DEFAULT_FONT, 11, "OUTLINE")
    end
    self:ApplySettings()
end

function ReadyCheckAssistant:TestMode()
    if editPreview then
        self:ExitEditPreview()
    else
        self:EnterEditPreview()
    end
end

function ReadyCheckAssistant:EnterEditPreview()
    editPreview = true
    self.db = self.db or EnsureDB()
    self:Show(true)
end

function ReadyCheckAssistant:RefreshEditPreview()
    if editPreview then self:ApplySettings() end
end

function ReadyCheckAssistant:ExitEditPreview()
    editPreview = false
    if readyCheckOpen then
        self:Show(false)
    elseif frame then
        frame:Hide()
    end
end

eventFrame:RegisterEvent("READY_CHECK")
eventFrame:RegisterEvent("READY_CHECK_FINISHED")
eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("MERCHANT_CLOSED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    if not active then return end
    if event == "READY_CHECK" then
        ReadyCheckAssistant:HandleReadyCheck()
    elseif event == "READY_CHECK_FINISHED" or event == "PLAYER_ENTERING_WORLD" then
        ReadyCheckAssistant:Hide()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ReadyCheckAssistant.db and ReadyCheckAssistant.db.hideInCombat ~= false then
            ReadyCheckAssistant:Hide()
        end
    elseif frame and frame:IsShown() then
        C_Timer.After(0.1, function()
            if active and frame and frame:IsShown() then ReadyCheckAssistant:Refresh() end
        end)
    end
end)

DDingToolKit:RegisterModule("ReadyCheckAssistant", ReadyCheckAssistant)
