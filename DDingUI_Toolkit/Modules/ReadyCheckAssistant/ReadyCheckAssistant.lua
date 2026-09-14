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
local PANEL_HEIGHT = 340
local COMPACT_PANEL_HEIGHT = 286
local ACTION_BUTTON_HEIGHT = 31
local ICON_PATH = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\ReadyCheckIcons.tga"
local ICONS = { alert = 0, check = 1, close = 2, talent = 3, repair = 4, chat = 5, open = 6,
    flask = 7, food = 8, rune = 9, weapon = 10, spec = 11 }
local READY_COLOR = { 0.51, 0.78, 0.64, 1 }
local WARNING_COLOR = { 0.89, 0.73, 0.47, 1 }
local REPAIR_COLOR = { 0.93, 0.58, 0.53, 1 }

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

local function AddText(parent, size, color, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetFont(DEFAULT_FONT, size, "")
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 0.5)
    label:SetTextColor(unpack(color))
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetText(text or "")
    frame.fontSizes[label] = size
    return label
end

local function SetIcon(texture, name, color)
    local index = ICONS[name]
    texture:SetTexture(ICON_PATH)
    texture:SetTexCoord(index / 16, (index + 1) / 16, 0, 1)
    texture:SetVertexColor(unpack(color))
end

local function AddIcon(parent, name, size, color)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    SetIcon(icon, name, color)
    return icon
end

local function SetCheckStatus(label, icon, text, symbol, color)
    label:SetText(text)
    label:SetTextColor(unpack(color))
    label:SetWidth(label:GetStringWidth())
    icon:SetShown(symbol ~= nil)
    if symbol then SetIcon(icon, symbol, color) end
end

local function CreatePanelButton(parent, label, symbol)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(200, ACTION_BUTTON_HEIGHT)
    button:RegisterForClicks("LeftButtonUp")

    button.label = AddText(button, 12, P.text, label)
    button.label:SetPoint("CENTER", 10, 0)
    button.label:SetJustifyH("CENTER")
    button.icon = AddIcon(button, symbol, 14, P.text)
    button.icon:SetPoint("RIGHT", button.label, "LEFT", -7, 0)

    local function ApplyVisual(state)
        if button.primary then
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

    function button:SetPrimary(primary)
        self.primary = primary
        ApplyVisual(self._hovered and "hover" or "normal")
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


local CONSUMABLES = {
    { key = "flask", label = "RAIDPREP_COLUMN_FLASK", icon = 134830 },
    { key = "food", label = "RAIDPREP_COLUMN_FOOD", icon = 134062 },
    { key = "rune", label = "RAIDPREP_COLUMN_RUNE", icon = 134419 },
    { key = "weapon", label = "RAIDPREP_COLUMN_WEAPON", icon = 135274 },
}

function ReadyCheckAssistant:GetConsumables()
    local result = {}
    local scanner = ns.RaidPreparation
    if scanner then
        -- Reuse the raid module's spell lists without enabling its UI or comms.
        if not self.consumableScanner then
            local raidDB = ns.db and ns.db.profile and ns.db.profile.RaidPreparation or {}
            self.consumableScanner = { db = {
                minimumBuffMinutes = 0,
                customFoodSpellIDs = raidDB.customFoodSpellIDs,
                customFlaskSpellIDs = raidDB.customFlaskSpellIDs,
                customRuneSpellIDs = raidDB.customRuneSpellIDs,
            } }
            scanner.BuildSpellSets(self.consumableScanner)
        end
        local food, flask, rune, foodTime, flaskTime, runeTime, _, icons =
            scanner.ScanUnitAuras(self.consumableScanner, "player")
        result.food = { value = food, remaining = foodTime, icon = icons and icons.food }
        result.flask = { value = flask, remaining = flaskTime, icon = icons and icons.flask }
        result.rune = { value = rune, remaining = runeTime, icon = icons and icons.rune }
    end
    local weapon = {}
    if GetWeaponEnchantInfo then
        local ok, main, expiration, _, _, off, offExpiration = pcall(GetWeaponEnchantInfo)
        if ok and not IsSecret(main) and not IsSecret(off) then
            local mainTime, offTime = SafeNumber(expiration), SafeNumber(offExpiration)
            if main == true or off == true then
                weapon.value = true
                local milliseconds = main == true and mainTime or offTime
                weapon.remaining = milliseconds and milliseconds / 1000
            elseif main == false and (off == false or off == nil) then
                weapon.value = false
            end
        end
    end
    result.weapon = weapon
    return result
end

local function ConsumableStatus(item)
    if not item or item.value == nil then return L["RCA_CHECK_UNKNOWN"], P.textDim end
    if item.value == false then return L["RCA_MISSING"], WARNING_COLOR end
    if item.remaining then
        if item.remaining <= 0 then return L["RCA_MISSING"], WARNING_COLOR end
        if item.remaining < 60 then
            return string.format(L["RCA_SECONDS_LEFT"], math.ceil(item.remaining)), WARNING_COLOR
        end
        return string.format(L["RCA_MINUTES_LEFT"], math.floor(item.remaining / 60)), READY_COLOR
    end
    return L["RCA_ACTIVE"], READY_COLOR
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
    elseif not loadoutKnown then
        status = "UNKNOWN"
    elseif loadoutMatch == false then
        status = "LOADOUT"
    end

    local consumables = self:GetConsumables()
    local consumableIssues = 0
    for _, definition in ipairs(CONSUMABLES) do
        local item = consumables[definition.key]
        if not item or item.value ~= true then consumableIssues = consumableIssues + 1 end
    end
    if status == "READY" and consumableIssues > 0 then status = "CONSUMABLES" end
    return {
        consumables = consumables,
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
        issueCount = consumableIssues + (#durability.lowSlots > 0 and 1 or 0) + ((not loadoutKnown or loadoutMatch == false) and 1 or 0),
    }
end

function ReadyCheckAssistant:CreateFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "DDingToolKit_ReadyCheckAssistantFrame", UIParent, "BackdropTemplate")
    frame.fontSizes = {}
    frame:SetSize(720, PANEL_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    SetBackdrop(frame, P.background, P.border)

    local function Text(key, size, color, text, x, y, width)
        local label = AddText(frame, size, color, text)
        label:SetPoint("TOPLEFT", x, -y)
        label:SetHeight(size + 6)
        if width then
            label:SetWidth(width)
        else
            label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -y)
        end
        frame[key] = label
        return label
    end

    frame.headerBackground = frame:CreateTexture(nil, "BACKGROUND")
    frame.headerBackground:SetPoint("TOPLEFT", 1, -1)
    frame.headerBackground:SetPoint("TOPRIGHT", -1, -1)
    frame.headerBackground:SetHeight(37)
    frame.headerBackground:SetColorTexture(unpack(P.header or P.hover))

    Text("title", 13, P.textBright, L["RCA_PANEL_TITLE"], 16, 10)
    frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -142, -10)
    frame.context = AddText(frame, 11, P.textDim)
    frame.context:SetPoint("TOPRIGHT", -48, -10)
    frame.context:SetSize(80, 18)
    frame.context:SetJustifyH("RIGHT")

    frame.closeButton = CreateFrame("Button", nil, frame)
    frame.closeButton:SetSize(24, 24)
    frame.closeButton:SetPoint("TOPRIGHT", -11, -7)
    frame.closeButton.icon = AddIcon(frame.closeButton, "close", 16, P.textDim)
    frame.closeButton.icon:SetPoint("CENTER")
    frame.closeButton:SetHighlightTexture(FLAT)
    frame.closeButton:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    frame.closeButton:SetScript("OnClick", function()
        editPreview = false
        ReadyCheckAssistant:Hide()
    end)

    frame.statusBackground = frame:CreateTexture(nil, "BACKGROUND")
    frame.statusBackground:SetPoint("TOPLEFT", 1, -39)
    frame.statusBackground:SetPoint("TOPRIGHT", -1, -39)
    frame.statusBackground:SetHeight(64)
    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetPoint("TOPLEFT", 1, -39)
    frame.accent:SetSize(3, 64)
    frame.statusIcon = AddIcon(frame, "check", 25, READY_COLOR)
    frame.statusIcon:SetPoint("TOPLEFT", 20, -58)
    Text("statusText", 18, P.textBright, "", 57, 51)
    Text("statusDetail", 11, P.textDim, "", 57, 77)

    frame.specIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.specIcon:SetPoint("TOPLEFT", 16, -113)
    frame.specIcon:SetSize(24, 24)
    Text("specText", 13, P.accentText, "", 49, 113, 112)
    Text("loadoutText", 12, P.text, "", 171, 113)
    Text("expectedText", 11, P.textDim, "", 49, 140)
    frame.loadoutStatus = AddText(frame, 11, P.textDim)
    frame.loadoutStatus:SetPoint("TOPRIGHT", -16, -140)
    frame.loadoutStatus:SetHeight(18)
    frame.loadoutStatus:SetJustifyH("RIGHT")
    frame.loadoutStatusIcon = AddIcon(frame, "check", 13, READY_COLOR)
    frame.loadoutStatusIcon:SetPoint("RIGHT", frame.loadoutStatus, "LEFT", -5, 0)

    for _, y in ipairs({38, 164}) do
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 16, -y)
        line:SetPoint("TOPRIGHT", -16, -y)
        line:SetHeight(1)
        line:SetColorTexture(0.20, 0.20, 0.21, 1)
    end
    frame.cells = {}
    for index = 1, 5 do
        local cell = CreateFrame("Frame", nil, frame)
        cell:EnableMouse(true)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("TOP", cell, "TOP", 0, 0)
        cell.icon:SetSize(32, 32)
        cell.label = AddText(cell, 12, P.text)
        cell.label:SetPoint("TOPLEFT", 4, -40)
        cell.label:SetPoint("TOPRIGHT", -4, -40)
        cell.label:SetHeight(18)
        cell.label:SetJustifyH("CENTER")
        cell.value = AddText(cell, 11, P.textDim)
        cell.value:SetPoint("TOPLEFT", 4, -63)
        cell.value:SetPoint("TOPRIGHT", -4, -63)
        cell.value:SetHeight(18)
        cell.value:SetJustifyH("CENTER")
        cell.label:SetText(index == 5 and L["RAIDPREP_COLUMN_DURABILITY"] or L[CONSUMABLES[index].label])
        if index > 1 then
            cell.divider = cell:CreateTexture(nil, "ARTWORK")
            cell.divider:SetPoint("TOPLEFT", 0, 0)
            cell.divider:SetSize(1, 82)
            cell.divider:SetColorTexture(0.20, 0.20, 0.21, 1)
        end
        cell:SetScript("OnEnter", function()
            if not GameTooltip then return end
            GameTooltip:SetOwner(cell, "ANCHOR_TOP")
            GameTooltip:SetText(cell.label:GetText())
            GameTooltip:AddLine(cell.tooltip or cell.value:GetText(), 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame.cells[index] = cell
    end
    Text("detailText", 11, P.textDim, "", 16, 264)

    frame.footerBackground = frame:CreateTexture(nil, "BACKGROUND")
    frame.footerBackground:SetPoint("BOTTOMLEFT", 1, 1)
    frame.footerBackground:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.footerBackground:SetHeight(53)
    frame.footerBackground:SetColorTexture(unpack(P.footer))
    frame.footerDivider = frame:CreateTexture(nil, "ARTWORK")
    frame.footerDivider:SetPoint("BOTTOMLEFT", 1, 54)
    frame.footerDivider:SetPoint("BOTTOMRIGHT", -1, 54)
    frame.footerDivider:SetHeight(1)
    frame.footerDivider:SetColorTexture(0.20, 0.20, 0.21, 1)

    frame.openTalentsButton = CreatePanelButton(frame, L["RCA_OPEN_TALENTS"], "open")
    frame.openTalentsButton:SetScript("OnClick", function()
        if SafeBooleanCall(InCombatLockdown) then return end
        if PlayerSpellsUtil and PlayerSpellsUtil.TogglePlayerSpellsFrame then
            pcall(PlayerSpellsUtil.TogglePlayerSpellsFrame, 2)
        end
    end)
    frame.reportButton = CreatePanelButton(frame, L["RCA_REPORT_BUTTON"], "chat")
    frame.reportButton:SetScript("OnClick", function()
        ReadyCheckAssistant:SendReport(false)
    end)

    frame:SetScript("OnUpdate", function()
        if readyCheckOpen and not editPreview and GetTime() - shownAt >= 0.25 then
            local readyFrame = _G.ReadyCheckFrame
            if readyFrame and not readyFrame:IsShown() then ReadyCheckAssistant:Hide(); return end
        end
        if GetTime() >= (frame.nextRefresh or 0) then
            frame.nextRefresh = GetTime() + 1
            ReadyCheckAssistant:Refresh()
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
    local width = Clamp(db.width, 560, 900, 720)
    db.width = width
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

    for index, cell in ipairs(display.cells) do
        local cellWidth = (width - 32) / 5
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", display, "TOPLEFT", 16 + (index - 1) * cellWidth, -178)
        cell:SetSize(cellWidth, 82)
    end
    display.expectedText:ClearAllPoints()
    display.expectedText:SetPoint("TOPLEFT", 49, -140)
    display.expectedText:SetSize(width - 235, 18)
    self.consumableScanner = nil
    display.detailText:SetShown(showDetails)
    display.openTalentsButton:SetShown(showTalentsButton)
    display.reportButton:SetShown(showReportButton)
    display.footerBackground:SetShown(showActions)
    display.footerDivider:SetShown(showActions)

    display.reportButton:ClearAllPoints()
    display.openTalentsButton:ClearAllPoints()
    local buttonWidth = showTalentsButton and showReportButton and (width - 40) / 2 or width - 32
    display.openTalentsButton:SetWidth(buttonWidth)
    display.reportButton:SetWidth(buttonWidth)
    display.openTalentsButton:SetPoint("BOTTOMLEFT", display, "BOTTOMLEFT", 16, 12)
    display.reportButton:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", -16, 12)
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
    return table.concat(parts, " \194\183 ")
end

function ReadyCheckAssistant:Refresh()
    if not frame or not self.db then return end
    local snapshot = self:CollectSnapshot()
    self.snapshot = snapshot

    frame.context:SetText(L["RCA_CONTEXT_" .. snapshot.context] or snapshot.context)
    frame.specText:SetText(snapshot.specName)
    SetIcon(frame.specIcon, "spec", P.accentText)
    frame.loadoutText:SetText(snapshot.loadoutName)
    frame.expectedText:SetText(L["RCA_EXPECTED"] .. ": " .. (snapshot.expectedLoadout ~= "" and snapshot.expectedLoadout or L["RCA_NOT_CONFIGURED"]))
    frame.expectedText:SetTextColor(unpack(snapshot.expectedLoadout ~= "" and P.accentText or P.textDim))

    local talentSummary
    if not snapshot.loadoutKnown then
        SetCheckStatus(frame.loadoutStatus, frame.loadoutStatusIcon, L["RCA_CHECK_UNKNOWN"], "alert", WARNING_COLOR)
        talentSummary = L["RCA_SUMMARY_UNKNOWN"]
    elseif snapshot.loadoutMatch == false then
        SetCheckStatus(frame.loadoutStatus, frame.loadoutStatusIcon, L["RCA_CHECK_MISMATCH"], "alert", WARNING_COLOR)
        talentSummary = L["RCA_SUMMARY_MISMATCH"]
    elseif snapshot.loadoutMatch == true then
        SetCheckStatus(frame.loadoutStatus, frame.loadoutStatusIcon, L["RCA_CHECK_MATCH"], "check", READY_COLOR)
        talentSummary = L["RCA_SUMMARY_MATCH"]
    else
        SetCheckStatus(frame.loadoutStatus, frame.loadoutStatusIcon, L["RCA_NOT_CONFIGURED"], nil, P.textDim)
        talentSummary = L["RCA_SUMMARY_UNSET"]
    end
    local talentIssue = not snapshot.loadoutKnown or snapshot.loadoutMatch == false
    frame.loadoutText:SetTextColor(unpack(talentIssue and WARNING_COLOR or P.text))
    frame.openTalentsButton:SetPrimary(talentIssue)

    local durability = snapshot.durability
    local needsRepair = #durability.lowSlots > 0
    local durabilityColor = needsRepair and REPAIR_COLOR or READY_COLOR
    local durabilityCell = frame.cells[5]
    SetIcon(durabilityCell.icon, "repair", durabilityColor)
    durabilityCell.value:SetText(string.format("%s %d%%", L["RCA_LOWEST"], math.floor(durability.lowest + 0.5)))
    durabilityCell.value:SetTextColor(unpack(durabilityColor))
    durabilityCell.tooltip = string.format(L["RCA_AVERAGE_FORMAT"], math.floor(durability.average + 0.5))
        .. "\n" .. string.format(L["RCA_THRESHOLD_FORMAT"], durability.threshold)
        .. "\n" .. FormatLowSlots(durability.lowSlots, 17)
    frame.detailText:SetText(FormatLowSlots(durability.lowSlots, 2))
    frame.detailText:SetTextColor(unpack(needsRepair and REPAIR_COLOR or P.textDim))
    local missing = {}
    for index, definition in ipairs(CONSUMABLES) do
        local item = snapshot.consumables[definition.key]
        local text, color = ConsumableStatus(item)
        local cell = frame.cells[index]
        SetIcon(cell.icon, definition.key, color)
        cell.value:SetText(text)
        cell.value:SetTextColor(unpack(color))
        cell.tooltip = text
        if not item or item.value ~= true then missing[#missing + 1] = L[definition.label] end
    end

    local hasIssues = snapshot.issueCount > 0
    local summaryColor = hasIssues and WARNING_COLOR or READY_COLOR
    SetIcon(frame.statusIcon, hasIssues and "alert" or "check", summaryColor)
    frame.accent:SetColorTexture(unpack(summaryColor))
    frame.statusBackground:SetColorTexture(unpack(hasIssues and { 0.153, 0.137, 0.114, 1 } or { 0.118, 0.161, 0.137, 1 }))
    frame.statusText:SetText(hasIssues and string.format(L["RCA_SUMMARY_ISSUES_FORMAT"], snapshot.issueCount) or L["RCA_STATUS_READY"])
    if talentIssue then missing[#missing + 1] = talentSummary end
    if needsRepair then missing[#missing + 1] = L["RCA_REPAIR_NEEDED"] end
    frame.statusDetail:SetText(#missing > 0 and table.concat(missing, " / ") or (talentSummary .. " / " .. L["RCA_SUMMARY_DURABILITY"]))
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
    if #snapshot.durability.lowSlots > 0 then
        message = message .. string.format(L["RCA_REPORT_REPAIR"], #snapshot.durability.lowSlots)
    end
    if not snapshot.loadoutKnown then
        message = message .. L["RCA_REPORT_UNKNOWN"]
    elseif snapshot.loadoutMatch == false then
        message = message .. string.format(L["RCA_REPORT_LOADOUT"], snapshot.expectedLoadout)
    end
    for _, definition in ipairs(CONSUMABLES) do
        local item = snapshot.consumables and snapshot.consumables[definition.key]
        if not item or item.value ~= true then
            message = message .. " / " .. L[definition.label] .. ": " .. ConsumableStatus(item)
        end
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
    DEFAULT_FONT = (SL and SL.Font and SL.Font.path) or DEFAULT_FONT
    if frame then
        for label, size in pairs(frame.fontSizes) do
            label:SetFont(DEFAULT_FONT, size, "")
        end
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

eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
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
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if not active then return end
    if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then return end
    if event == "READY_CHECK" then
        ReadyCheckAssistant:HandleReadyCheck()
    elseif event == "READY_CHECK_FINISHED" or event == "PLAYER_ENTERING_WORLD" then
        ReadyCheckAssistant:Hide()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ReadyCheckAssistant.db and ReadyCheckAssistant.db.hideInCombat ~= false then
            ReadyCheckAssistant:Hide()
        end
    elseif frame and frame:IsShown() then
        if frame.refreshPending then return end
        frame.refreshPending = true
        C_Timer.After(0.1, function()
            if frame then frame.refreshPending = false end
            if active and frame and frame:IsShown() then ReadyCheckAssistant:Refresh() end
        end)
    end
end)

DDingToolKit:RegisterModule("ReadyCheckAssistant", ReadyCheckAssistant)
