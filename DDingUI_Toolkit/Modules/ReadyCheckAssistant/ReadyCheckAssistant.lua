-- DDingUI Toolkit - Ready Check Assistant

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib

local ReadyCheckAssistant = {}
ns.ReadyCheckAssistant = ReadyCheckAssistant

local DEFAULT_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local CHAT_PREFIX = ns.CHAT_PREFIX -- [STYLE] Core/Core.lua 공통 접두사
-- [STYLE] Match the ready popup width and separate the two optional consumables.
local PANEL_WIDTH = 323
local TITLE_HEIGHT = 28
local ROW_HEIGHT = 26
local ROWS_TOP = TITLE_HEIGHT + 26 -- title bar + pill row
local OPTIONAL_HEIGHT = 14
local PANEL_HEIGHT = ROWS_TOP + 7 * ROW_HEIGHT + OPTIONAL_HEIGHT + 10
-- [STYLE] Toolkit's own item icons; game icons are the fallback when UI/ReadyStatus.lua is absent.
local OWN_ICONS = ns.ReadyStatus and ns.ReadyStatus.ITEM_ICONS or {}
local DURABILITY_ICON = OWN_ICONS.durability or "Interface\\Icons\\Trade_BlackSmithing"

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

local function RS() return ns.ReadyStatus end

-- Every label is 12pt or larger; fontSizes lets OnMediaChanged re-apply the StyleLib font.
local function AddText(parent, size, color, text)
    local label = RS().Text(parent, size, color, text)
    label:SetFont(DEFAULT_FONT, math.max(12, size), "")
    frame.fontSizes[label] = math.max(12, size)
    return label
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
    { key = "flask", row = 2, label = "RAIDPREP_COLUMN_FLASK", icon = OWN_ICONS.flask or 134830 },
    { key = "food", row = 3, label = "RAIDPREP_COLUMN_FOOD", icon = OWN_ICONS.food or 134062 },
    { key = "weapon", row = 4, label = "RAIDPREP_COLUMN_WEAPON", icon = OWN_ICONS.weapon or 135274 },
    { key = "rune", row = 6, optional = true, label = "RAIDPREP_COLUMN_RUNE", rowLabel = "RCA_ROW_RUNE", icon = OWN_ICONS.rune or 134419 },
    { key = "vantus", row = 7, optional = true, label = "RAIDPREP_COLUMN_VANTUS", rowLabel = "RCA_ROW_VANTUS", icon = OWN_ICONS.vantus or 134419 },
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
                customVantusSpellIDs = raidDB.customVantusSpellIDs,
            } }
            scanner.BuildSpellSets(self.consumableScanner)
        end
        local food, flask, rune, foodTime, flaskTime, runeTime, _, icons, vantus, vantusTime =
            scanner.ScanUnitAuras(self.consumableScanner, "player")
        result.food = { value = food, remaining = foodTime, icon = icons and icons.food }
        result.flask = { value = flask, remaining = flaskTime, icon = icons and icons.flask }
        result.rune = { value = rune, remaining = runeTime, icon = icons and icons.rune }
        result.vantus = { value = vantus, remaining = vantusTime, icon = icons and icons.vantus }
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

--- text, state ("ok" | "warn" | "bad" | nil = unknown)
local function ConsumableStatus(item)
    if not item or item.value == nil then return L["RCA_CHECK_UNKNOWN"], nil end
    if item.value == false then return L["RCA_MISSING"], "bad" end
    if item.remaining then
        if item.remaining <= 0 then return L["RCA_MISSING"], "bad" end
        if item.remaining < 60 then
            return string.format(L["RCA_SECONDS_LEFT"], math.ceil(item.remaining)), "warn"
        end
        return string.format(L["RCA_MINUTES_LEFT"], math.floor(item.remaining / 60)), item.value == "LOW" and "warn" or "ok"
    end
    if item.value == "LOW" then return L["RAIDPREP_LOW"], "warn" end
    return L["RCA_ACTIVE"], "ok"
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
        if not definition.optional and (not item or item.value ~= true) then consumableIssues = consumableIssues + 1 end
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

local function OpenTalents()
    if SafeBooleanCall(InCombatLockdown) then return end
    if PlayerSpellsUtil and PlayerSpellsUtil.TogglePlayerSpellsFrame then
        pcall(PlayerSpellsUtil.TogglePlayerSpellsFrame, 2)
    end
end
ReadyCheckAssistant.OpenTalents = OpenTalents

local function ShowRowTooltip(row)
    if not GameTooltip or not row.tooltipTitle then return end
    local styles = RS()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.tooltipTitle, styles.RGB(styles.Token("text", "highlight")))
    for _, line in ipairs(row.tooltipLines or {}) do
        GameTooltip:AddLine(line, styles.RGB(styles.Token("text", "normal")))
    end
    if row.clickHint then
        GameTooltip:AddLine(row.clickHint, styles.RGB(styles.Color(nil)))
    end
    if row.optional then
        GameTooltip:AddLine(L["RAIDPREP_OPTIONAL_NOTE"], styles.RGB(styles.Token("text", "dim")))
    end
    GameTooltip:Show()
end

function ReadyCheckAssistant:CreateFrame()
    if frame then return frame end
    local styles = RS()

    frame = CreateFrame("Frame", "DDingToolKit_ReadyCheckAssistantFrame", UIParent, "BackdropTemplate")
    frame.fontSizes = {}
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    styles.Round(frame, styles.Radius("window", 14), styles.Token("bg", "main"), styles.Token("border", "default"))

    local function Close()
        editPreview = false
        ReadyCheckAssistant:Hide()
    end

    -- Series title bar: logo rings + "DDingUI Toolkit · 준비 점검" + X
    local title = "DDingUI Toolkit \194\183 " .. L["RCA_PANEL_SHORT"]
    if SL and SL.CreateTitleBar then
        local bar = SL.CreateTitleBar(frame, "MJToolkit", title, "", { rounded = true })
        bar:SetHeight(TITLE_HEIGHT)
        if bar.verText then bar.verText:Hide() end
        bar.titleText:SetPoint("RIGHT", bar.closeBtn, "LEFT", -6, 0) -- [STYLE] narrow popup widths
        bar.titleText:SetWordWrap(false)
        bar.closeBtn:SetScript("OnClick", Close)
        frame.titleBar = bar
        frame.closeButton = bar.closeBtn
    else
        frame.titleText = AddText(frame, 12, styles.Token("text", "highlight"), title)
        frame.titleText:SetPoint("TOPLEFT", 12, -7)
        frame.closeButton = styles.CreateCloseButton(frame, Close)
        frame.closeButton:SetPoint("TOPRIGHT", -8, -5)
    end

    -- Pill row: issue count (left), context (right)
    frame.summaryPill = styles.CreatePill(frame)
    frame.summaryPill:SetPoint("TOPLEFT", 12, -(TITLE_HEIGHT + 2))
    frame.contextPill = styles.CreatePill(frame)
    frame.contextPill:SetPoint("TOPRIGHT", -12, -(TITLE_HEIGHT + 2))
    frame.fontSizes[frame.summaryPill.text] = 12
    frame.fontSizes[frame.contextPill.text] = 12

    -- [STYLE] Required rows, then a quiet optional group.
    frame.rows = {}
    for index = 1, 7 do
        local row = CreateFrame("Button", nil, frame)
        row.optional = index > 5
        row:SetPoint("TOPLEFT", 12, -(ROWS_TOP + (index - 1) * ROW_HEIGHT + (row.optional and OPTIONAL_HEIGHT or 0)))
        row:SetSize(PANEL_WIDTH - 24, ROW_HEIGHT)
        row.card = styles.RoundFill(row:CreateTexture(nil, "BACKGROUND"), styles.Radius("row", 8))
        row.card:SetPoint("TOPLEFT", -6, 0)
        row.card:SetPoint("BOTTOMRIGHT", 6, 0)
        row.card:Hide()
        row.cell = styles.CreateIcon(row, styles.PERSONAL_ICON)
        row.cell:SetPoint("LEFT", 0, 0)
        row.status = AddText(row, 12, styles.Color(nil), "")
        row.status:SetPoint("RIGHT", 0, 0)
        row.status:SetJustifyH("RIGHT")
        row.label = AddText(row, 12, styles.Token("text", "normal"), "")
        row.label:SetPoint("LEFT", row.cell, "RIGHT", 10, 0)
        row.label:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
        row:EnableMouse(true)
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame.rows[index] = row
    end
    frame.optionalHeader = CreateFrame("Frame", nil, frame)
    frame.optionalHeader:SetPoint("TOPLEFT", 12, -(ROWS_TOP + 5 * ROW_HEIGHT))
    frame.optionalHeader:SetSize(PANEL_WIDTH - 24, OPTIONAL_HEIGHT)
    frame.optionalHeader.label = AddText(frame.optionalHeader, 12, styles.Token("text", "dim"), L["RAIDPREP_OPTIONAL_LABEL"])
    frame.optionalHeader.label:SetPoint("LEFT", 0, 0)
    local divider = frame.optionalHeader:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("LEFT", frame.optionalHeader.label, "RIGHT", 8, 0)
    divider:SetPoint("RIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(styles.Unpack(styles.Token("border", "default")))
    frame.talentRow = frame.rows[1]
    frame.talentRow.cell:SetRound(true)
    frame.talentRow:RegisterForClicks("LeftButtonUp")
    frame.talentRow:SetScript("OnClick", OpenTalents) -- [STYLE] replaces the "특성 열기" button
    frame.talentRow.clickHint = L["RCA_TALENT_CLICK_HINT"]

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
    if SafeBooleanCall(InCombatLockdown) then self.settingsPending = true; return end
    self.settingsPending = nil
    self.db = EnsureDB()
    if not self.db then return end
    local display = self:CreateFrame()
    local db = self.db
    local anchorSide = db.anchorSide == "ABOVE" and "ABOVE" or "BELOW"
    local readyFrame = _G.ReadyCheckFrame

    display:SetScale(Clamp(db.scale, 0.6, 1.8, 1))
    local width = readyFrame and SafeNumber(readyFrame:GetWidth())
    width = width and width >= 200 and width <= 600 and width or PANEL_WIDTH
    -- [STYLE] Equal visible widths even when the two frames use different scales.
    local readyScale = readyFrame and readyFrame.GetEffectiveScale and SafeNumber(readyFrame:GetEffectiveScale())
    local panelScale = display.GetEffectiveScale and SafeNumber(display:GetEffectiveScale())
    if readyScale and readyScale > 0 and panelScale and panelScale > 0 then width = width * readyScale / panelScale end
    local optional = db.showOptional ~= false
    display:SetSize(width, optional and PANEL_HEIGHT or ROWS_TOP + 5 * ROW_HEIGHT + 10)
    for _, row in ipairs(display.rows) do
        row:SetWidth(width - 24)
        row:SetShown(not row.optional or optional)
    end
    display.optionalHeader:SetWidth(width - 24)
    display.optionalHeader:SetShown(optional)
    if not optional and GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner == display.rows[6] or owner == display.rows[7] then GameTooltip:Hide() end
    end
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
    self.consumableScanner = nil
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

local function SetRow(row, icon, label, status, state)
    local styles = RS()
    row.cell:SetIcon(icon)
    row.cell:SetState(state)
    row.label:SetText(label)
    row.status:SetText(status)
    row.status:SetTextColor(styles.Unpack(styles.Color(state)))
    row.state = state
    if state == "bad" or state == "warn" then
        styles.Tint(row.card, styles.Color(state), 0.10)
        row.card:Show()
    else
        row.card:Hide()
    end
end

function ReadyCheckAssistant:Refresh()
    if not frame or not self.db then return end
    local snapshot = self:CollectSnapshot()
    self.snapshot = snapshot
    local styles = RS()

    frame.contextPill:SetPill(L["RCA_CONTEXT_" .. snapshot.context] or snapshot.context, nil)
    if snapshot.issueCount > 0 then
        frame.summaryPill:SetPill(string.format(L["RCA_SUMMARY_ISSUES_FORMAT"], snapshot.issueCount), "warn")
    else
        frame.summaryPill:SetPill(L["RCA_NO_ISSUES"], "ok")
    end
    -- [STYLE] Keep the pills separate when matching a scaled or skinned popup.
    local available = frame:GetWidth() - 24
    if snapshot.issueCount > 0 and frame.summaryPill:GetWidth() + frame.contextPill:GetWidth() + 8 > available then
        frame.summaryPill:SetPill(string.format(L["RCA_SUMMARY_SHORT_FORMAT"], snapshot.issueCount), "warn")
    end
    frame.contextPill:SetShown(frame.summaryPill:GetWidth() + frame.contextPill:GetWidth() + 8 <= available)

    -- Talents: "특성 · <기준 이름>" + 일치 / 불일치 / 미설정
    local talentStatus, talentState
    if not snapshot.loadoutKnown then
        talentStatus, talentState = L["RCA_CHECK_UNKNOWN"], "warn"
    elseif snapshot.loadoutMatch == false then
        talentStatus, talentState = L["RCA_CHECK_MISMATCH"], "bad"
    elseif snapshot.loadoutMatch == true then
        talentStatus, talentState = L["RCA_STATUS_MATCH"], "ok"
    else
        talentStatus, talentState = L["RCA_NOT_CONFIGURED"], nil
    end
    local talentName = snapshot.expectedLoadout ~= "" and snapshot.expectedLoadout or snapshot.loadoutName
    local talentRow = frame.talentRow
    SetRow(talentRow, snapshot.specIcon, string.format(L["RCA_TALENT_ROW"], talentName), talentStatus, talentState)
    talentRow.tooltipTitle = snapshot.specName
    talentRow.tooltipLines = {
        L["RCA_CURRENT"] .. ": " .. snapshot.loadoutName,
        L["RCA_EXPECTED"] .. ": " .. (snapshot.expectedLoadout ~= "" and snapshot.expectedLoadout or L["RCA_NOT_CONFIGURED"]),
    }

    for _, definition in ipairs(CONSUMABLES) do
        local item = snapshot.consumables[definition.key]
        local text, state = ConsumableStatus(item)
        if definition.optional and state ~= "ok" then state = nil end
        local row = frame.rows[definition.row]
        SetRow(row, (item and item.icon) or definition.icon, L[definition.rowLabel or definition.label], text, state)
        row.tooltipTitle = L[definition.rowLabel or definition.label]
        row.tooltipLines = { text }
    end

    -- Durability: "최저 91%"
    local durability = snapshot.durability
    local needsRepair = #durability.lowSlots > 0
    local durabilityRow = frame.rows[5]
    SetRow(durabilityRow, DURABILITY_ICON, L["RAIDPREP_COLUMN_DURABILITY"],
        string.format("%s %d%%", L["RCA_LOWEST"], math.floor(durability.lowest + 0.5)),
        needsRepair and "bad" or "ok")
    durabilityRow.tooltipTitle = L["RAIDPREP_COLUMN_DURABILITY"]
    durabilityRow.tooltipLines = {
        string.format(L["RCA_AVERAGE_FORMAT"], math.floor(durability.average + 0.5)),
        string.format(L["RCA_THRESHOLD_FORMAT"], durability.threshold),
        FormatLowSlots(durability.lowSlots, 17),
    }

    if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        for _, row in ipairs(frame.rows) do
            if owner == row then ShowRowTooltip(row) end
        end
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
        if not definition.optional and (not item or item.value ~= true) then
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
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" and ReadyCheckAssistant.settingsPending then ReadyCheckAssistant:ApplySettings() end
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
