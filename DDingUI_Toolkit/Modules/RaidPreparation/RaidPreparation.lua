-- DDingUI Toolkit - Raid Preparation

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib

local RaidPreparation = {}
ns.RaidPreparation = RaidPreparation

local FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local P = ns.UI and ns.UI.popupColors or {
    background = { 0.10, 0.10, 0.10, 0.985 }, header = { 0.12, 0.12, 0.12, 1 },
    panel = { 0.075, 0.075, 0.08, 0.97 }, panelAlt = { 0.088, 0.088, 0.095, 0.96 },
    control = { 0.06, 0.06, 0.06, 0.94 }, hover = { 0.14, 0.14, 0.15, 0.96 },
    border = { 0.30, 0.30, 0.32, 0.82 }, borderSoft = { 0.25, 0.25, 0.25, 0.50 },
    separator = { 0.20, 0.20, 0.20, 0.40 }, accent = { 0.16, 0.58, 0.68, 0.80 },
    accentText = { 0.42, 0.76, 0.82, 1 }, primary = { 0.09, 0.18, 0.20, 0.98 },
    primaryHover = { 0.11, 0.23, 0.26, 1 }, primaryBorder = { 0.16, 0.50, 0.57, 0.84 },
    primaryBorderHover = { 0.20, 0.62, 0.70, 0.94 }, text = { 0.85, 0.85, 0.85, 1 },
    textBright = { 1, 1, 1, 1 }, textDim = { 0.60, 0.60, 0.60, 1 },
}
local COMM_PREFIX = "DDTREADY"
local DURABILITY_PREFIX = "LibDRBLT"
local ROW_HEIGHT = 54
local VISIBLE_ROWS = 9

-- Current retail lists follow the 12.1 MRT RaidCheck data. Custom IDs can be
-- added in the module options without waiting for an addon update.
local FOOD_IDS = {
    [308488] = true, [308506] = true, [308434] = true, [308514] = true,
    [327708] = true, [327706] = true, [327709] = true, [308525] = true,
    [327707] = true, [308637] = true, [308474] = true, [308504] = true,
    [308430] = true, [308509] = true, [327704] = true, [327701] = true,
    [327705] = true, [327702] = true, [382145] = true, [382150] = true,
    [382146] = true, [382149] = true, [396092] = true, [382246] = true,
    [382247] = true, [382152] = true, [382153] = true, [382157] = true,
    [382230] = true, [382231] = true, [382232] = true, [382154] = true,
    [382155] = true, [382156] = true, [382234] = true, [382235] = true,
    [382236] = true,
}

local FLASK_IDS = {
    [1236763] = true, [1239355] = true, [1235057] = true, [1239755] = true,
    [1236767] = true, [1235111] = true, [1235110] = true, [1235108] = true,
    [432021] = true, [432473] = true, [431971] = true, [431972] = true,
    [431974] = true, [431973] = true,
}

local RUNE_IDS = {
    [224001] = true, [270058] = true, [317065] = true, [347901] = true,
    [367405] = true, [393438] = true, [453250] = true, [1234969] = true,
    [1242347] = true, [1264426] = true,
}

-- 12.1 raid-wide class buffs, aligned with MRT RaidCheck's current retail list.
local RAID_BUFFS = {
    {
        key = "attackPower", option = "raidBuffAttackPower", providerClass = "WARRIOR",
        labelKey = "RAIDPREP_BUFF_ATTACK_POWER", shortLabelKey = "RAIDPREP_BUFF_SHORT_ATTACK_POWER",
        spellIDs = { [6673] = true },
    },
    {
        key = "stamina", option = "raidBuffStamina", providerClass = "PRIEST",
        labelKey = "RAIDPREP_BUFF_STAMINA", shortLabelKey = "RAIDPREP_BUFF_SHORT_STAMINA",
        spellIDs = { [21562] = true },
    },
    {
        key = "intellect", option = "raidBuffIntellect", providerClass = "MAGE",
        labelKey = "RAIDPREP_BUFF_INTELLECT", shortLabelKey = "RAIDPREP_BUFF_SHORT_INTELLECT",
        spellIDs = { [1459] = true },
    },
    {
        key = "versatility", option = "raidBuffVersatility", providerClass = "DRUID",
        labelKey = "RAIDPREP_BUFF_VERSATILITY", shortLabelKey = "RAIDPREP_BUFF_SHORT_VERSATILITY",
        spellIDs = { [1126] = true },
    },
    {
        key = "mastery", option = "raidBuffMastery", providerClass = "SHAMAN",
        labelKey = "RAIDPREP_BUFF_MASTERY", shortLabelKey = "RAIDPREP_BUFF_SHORT_MASTERY",
        spellIDs = { [462854] = true },
    },
    {
        key = "movement", option = "raidBuffMovement", providerClass = "EVOKER",
        labelKey = "RAIDPREP_BUFF_MOVEMENT", shortLabelKey = "RAIDPREP_BUFF_SHORT_MOVEMENT",
        spellIDs = {
            [381732] = true, [381741] = true, [381746] = true, [381748] = true,
            [381749] = true, [381750] = true, [381751] = true, [381752] = true,
            [381753] = true, [381754] = true, [381756] = true, [381757] = true,
            [381758] = true,
        },
    },
}

local RAID_BUFF_BY_SPELL_ID = {}
for _, definition in ipairs(RAID_BUFFS) do
    for spellID in pairs(definition.spellIDs) do
        RAID_BUFF_BY_SPELL_ID[spellID] = definition.key
    end
end

local active = false
local frame
local eventFrame = CreateFrame("Frame")
local refreshPending = false
local readySerial = 0
local scrollOffset = 0
local readyCheckActive = false
local durabilityRequestAt = 0
local durabilityReplyAt = {}

local function IsSecret(value)
    return (ns.IsSecretValue and ns.IsSecretValue(value))
        or (issecretvalue and issecretvalue(value))
        or false
end

local function IsSecretTable(value)
    if IsSecret(value) then return true end
    if issecrettable and type(value) == "table" then
        local ok, result = pcall(issecrettable, value)
        return ok and result == true
    end
    return false
end

local function SafeString(value)
    if value == nil or IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

local function SafeNumber(value)
    if value == nil or IsSecret(value) then return nil end
    local ok, number = pcall(tonumber, value)
    if not ok or number == nil or IsSecret(number) then return nil end
    return number
end

local function SafeBoolean(value)
    if value == nil or IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function SafeBooleanCall(func, ...)
    if type(func) ~= "function" then return false end
    local ok, value = pcall(func, ...)
    if not ok then return false end
    return SafeBoolean(value) == true
end

local function Clamp(value, minimum, maximum, fallback)
    value = SafeNumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

local function Trim(value)
    value = SafeString(value) or ""
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeName(value)
    value = Trim(value)
    if value == "" then return nil end
    return value:lower()
end

local function ShortName(value)
    value = SafeString(value)
    if not value then return "?" end
    if Ambiguate then
        local ok, result = pcall(Ambiguate, value, "short")
        result = ok and SafeString(result) or nil
        if result then return result end
    end
    return value:match("^[^-]+") or value
end

local function CopyTable(source)
    if type(source) ~= "table" then return {} end
    if ns.DeepCopy then return ns:DeepCopy(source) end
    local result = {}
    for key, value in pairs(source) do
        result[key] = type(value) == "table" and CopyTable(value) or value
    end
    return result
end

local function EnsureDB()
    local profile = ns.db and ns.db.profile
    if not profile then return nil end
    if type(profile.RaidPreparation) ~= "table" then
        local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.RaidPreparation
        profile.RaidPreparation = CopyTable(defaults)
    end
    local db = profile.RaidPreparation
    if type(db.position) ~= "table" then
        db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 10 }
    end
    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.RaidPreparation or {}
    if db.checkRaidBuffs == nil then db.checkRaidBuffs = defaults.checkRaidBuffs ~= false end
    for _, definition in ipairs(RAID_BUFFS) do
        if db[definition.option] == nil then db[definition.option] = defaults[definition.option] ~= false end
    end
    return db
end

local function ParseSpellIDs(text, destination)
    destination = destination or {}
    text = SafeString(text) or ""
    for token in text:gmatch("%d+") do
        local spellID = tonumber(token)
        if spellID and spellID > 0 then destination[spellID] = true end
    end
    return destination
end

local function SetBackdrop(target, background, border)
    target:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    target:SetBackdropColor(unpack(background))
    target:SetBackdropBorderColor(unpack(border))
end

local function AddText(parent, size, color, text)
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    fontString:SetFont(FONT, size, "")
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fontString:SetText(text or "")
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.9)
    return fontString
end

local function CreateButton(parent, label, width, primary)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 100, 27)
    button:RegisterForClicks("LeftButtonUp")
    button.label = AddText(button, 11, P.text, label)
    button.label:SetPoint("LEFT", 7, 0)
    button.label:SetPoint("RIGHT", -7, 0)
    button.label:SetJustifyH("CENTER")
    button.label:SetWordWrap(false)

    local function ApplyVisual(state)
        if primary then
            SetBackdrop(button,
                state == "hover" and P.primaryHover or P.primary,
                state == "hover" and P.primaryBorderHover or P.primaryBorder)
            button.label:SetTextColor(unpack(P.textBright))
        else
            SetBackdrop(button,
                state == "hover" and P.hover or P.control,
                state == "hover" and P.border or P.borderSoft)
            button.label:SetTextColor(unpack(P.text))
        end
    end

    button:SetScript("OnEnter", function() ApplyVisual("hover") end)
    button:SetScript("OnLeave", function() ApplyVisual("normal") end)
    ApplyVisual("normal")
    return button
end

local function GetClassColor(classToken)
    classToken = SafeString(classToken)
    local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if not color then return 0.82, 0.85, 0.90 end
    return color.r or 0.82, color.g or 0.85, color.b or 0.90
end

local function IsAuraLongEnough(expirationTime, minimumSeconds)
    expirationTime = SafeNumber(expirationTime)
    if expirationTime == nil or expirationTime == 0 then return true, nil end
    local now = SafeNumber(GetTime and GetTime()) or 0
    local remaining = expirationTime - now
    return remaining > 0 and remaining >= minimumSeconds, math.max(0, remaining)
end

local function MergeStatus(current, isLongEnough, remaining)
    if isLongEnough then return true, remaining end
    if current ~= true then return "LOW", remaining end
    return current, remaining
end

function RaidPreparation:BuildSpellSets()
    local db = self.db or EnsureDB() or {}
    self.foodIDs = ParseSpellIDs(db.customFoodSpellIDs, CopyTable(FOOD_IDS))
    self.flaskIDs = ParseSpellIDs(db.customFlaskSpellIDs, CopyTable(FLASK_IDS))
    self.runeIDs = ParseSpellIDs(db.customRuneSpellIDs, CopyTable(RUNE_IDS))
end

function RaidPreparation:ScanUnitAuras(unit)
    if not SafeBooleanCall(UnitExists, unit) or not SafeBooleanCall(UnitIsConnected, unit) then
        return nil, nil, nil, nil, nil, nil, nil
    end
    local db = self.db or {}
    local minimumSeconds = Clamp(db.minimumBuffMinutes, 0, 60, 10) * 60
    local food, flask, rune = false, false, false
    local foodRemaining, flaskRemaining, runeRemaining
    local icons = {}
    local incomplete = false
    local raidBuffsFound = {}
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, hidden = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or IsSecret(hidden) or hidden == true then
            return nil, nil, nil, nil, nil, nil, nil
        end
    end

    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return nil, nil, nil, nil, nil, nil, nil
    end
    for index = 1, 80 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
        if not ok then incomplete = true; break end
        if IsSecretTable(aura) then incomplete = true
        elseif aura == nil then break
        end
        if not IsSecretTable(aura) and type(aura) == "table" then
            if IsSecret(aura.spellId) then incomplete = true; raidBuffsFound = nil end
            local spellID = SafeNumber(aura.spellId)
            local icon = SafeNumber(aura.icon)
            local longEnough, remaining = IsAuraLongEnough(aura.expirationTime, minimumSeconds)
            local raidBuffKey = spellID and RAID_BUFF_BY_SPELL_ID[spellID]
            if raidBuffKey and raidBuffsFound then raidBuffsFound[raidBuffKey] = true end
            if spellID and self.foodIDs[spellID]
                or (icon and (icon == 136000 or icon == 134062 or icon == 132805 or icon == 133950)) then
                food, foodRemaining = MergeStatus(food, longEnough, remaining)
                icons.food = icon or icons.food
            elseif spellID and self.flaskIDs[spellID] then
                flask, flaskRemaining = MergeStatus(flask, longEnough, remaining)
                icons.flask = icon or icons.flask
            elseif spellID and self.runeIDs[spellID] then
                rune, runeRemaining = MergeStatus(rune, longEnough, remaining)
                icons.rune = icon or icons.rune
            end
        end
    end
    if incomplete then
        if food == false then food = nil end
        if flask == false then flask = nil end
        if rune == false then rune = nil end
        raidBuffsFound = nil
    end
    return food, flask, rune, foodRemaining, flaskRemaining, runeRemaining, raidBuffsFound, icons
end

function RaidPreparation:GetSelfDurability()
    local currentTotal, maximumTotal, broken = 0, 0, 0
    for slot = 1, 18 do
        local ok, current, maximum = pcall(GetInventoryItemDurability, slot)
        current = ok and SafeNumber(current) or nil
        maximum = ok and SafeNumber(maximum) or nil
        if current and maximum and maximum > 0 then
            currentTotal = currentTotal + current
            maximumTotal = maximumTotal + maximum
            if current == 0 then broken = broken + 1 end
        end
    end
    if maximumTotal <= 0 then return 0, broken end
    return (currentTotal / maximumTotal) * 100, broken
end

function RaidPreparation:GetSelfGearStatus()
    local durability = self:GetSelfDurability()

    local mainHand, offHand
    if GetWeaponEnchantInfo then
        local ok, main, _, _, _, off = pcall(GetWeaponEnchantInfo)
        if ok then
            mainHand = SafeBoolean(main)
            offHand = SafeBoolean(off)
        end
    end
    return durability, mainHand, offHand
end

function RaidPreparation:GetCommChannel()
    if SafeBooleanCall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if SafeBooleanCall(IsInRaid) then return "RAID" end
    if SafeBooleanCall(IsInGroup) then return "PARTY" end
    return nil
end

local function EncodeBoolean(value)
    if value == true then return "1" end
    if value == false then return "0" end
    return "?"
end

local function DecodeBoolean(value)
    if value == "1" then return true end
    if value == "0" then return false end
    return nil
end

function RaidPreparation:SendComm(message, target)
    message = SafeString(message)
    if not message or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    local channel = target and "WHISPER" or self:GetCommChannel()
    if not channel then return false end
    return pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, message, channel, target)
end

function RaidPreparation:BroadcastStatus(nonce, target)
    nonce = SafeString(nonce) or "0"
    local durability, mainHand, offHand = self:GetSelfGearStatus()
    local durabilityText = durability and tostring(math.floor(durability + 0.5)) or "?"
    self:SendComm(table.concat({ "S", nonce, durabilityText, EncodeBoolean(mainHand), EncodeBoolean(offHand) }, "|"), target)
end

function RaidPreparation:RequestStatuses()
    self.remote = {}
    self.nonce = tostring(math.floor((SafeNumber(GetTime and GetTime()) or 0) * 10))
    self:SendComm("Q|" .. self.nonce)
    self:RequestDurability()
end

function RaidPreparation:AnnounceReadyCheckStatus()
    self.remote = {}
    self.nonce = nil
    self:RequestDurability()
    local serial = readySerial
    C_Timer.After(0.2, function()
        if active and readySerial == serial then RaidPreparation:BroadcastStatus("0") end
    end)
end

function RaidPreparation:StoreRemote(sender, durability, mainHand, offHand)
    sender = SafeString(sender)
    if not sender then return end
    self.remote = self.remote or {}
    local key = NormalizeName(sender)
    local shortKey = NormalizeName(ShortName(sender))
    local record = self:GetRemote(sender) or {}
    local durabilityValue = SafeNumber(durability)
    if durabilityValue then record.durability = Clamp(durabilityValue, 0, 100, 0) end
    if mainHand ~= nil then record.mainHand = DecodeBoolean(mainHand) end
    if offHand ~= nil then record.offHand = DecodeBoolean(offHand) end
    record.receivedAt = SafeNumber(GetTime and GetTime()) or 0
    if key then self.remote[key] = record end
    if shortKey then self.remote[shortKey] = record end
end

function RaidPreparation:GetRemote(name)
    local key = NormalizeName(name)
    local shortKey = NormalizeName(ShortName(name))
    return self.remote and ((key and self.remote[key]) or (shortKey and self.remote[shortKey])) or nil
end

function RaidPreparation:StoreDurability(sender, durability, broken)
    self:StoreRemote(sender, durability)
    local record = self:GetRemote(sender)
    local brokenCount = SafeNumber(broken)
    if record and brokenCount then record.broken = math.max(0, math.floor(brokenCount)) end
end

function RaidPreparation:OnLibDurability(percent, broken, playerName)
    if not active then return end
    playerName = SafeString(playerName)
    if not playerName then return end
    self:StoreDurability(playerName, percent, broken)
    self:ScheduleRefresh(0.05)
end

function RaidPreparation:RegisterLibDurability()
    if self.libDurability then return true end
    local library = LibStub and LibStub("LibDurability", true)
    if not library or type(library.Register) ~= "function" then return false end
    local ok = pcall(library.Register, library, self, "OnLibDurability")
    if not ok then return false end
    self.libDurability = library
    return true
end

function RaidPreparation:UnregisterLibDurability()
    local library = self.libDurability
    if library and type(library.Unregister) == "function" then
        pcall(library.Unregister, library, self)
    end
    self.libDurability = nil
end

function RaidPreparation:SendDurabilityMessage(message, channel)
    message = SafeString(message)
    channel = SafeString(channel) or self:GetCommChannel()
    if not message or not channel or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    if channel ~= "RAID" and channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" then return false end
    return pcall(C_ChatInfo.SendAddonMessage, DURABILITY_PREFIX, message, channel)
end

function RaidPreparation:BroadcastDurability(channel)
    local durability, broken = self:GetSelfDurability()
    local message = string.format("%d,%d", math.floor(durability + 0.5), broken)
    return self:SendDurabilityMessage(message, channel)
end

function RaidPreparation:RequestDurability()
    if self:RegisterLibDurability() then
        local ok = pcall(self.libDurability.RequestDurability, self.libDurability)
        if ok then return true end
    end

    local durability, broken = self:GetSelfDurability()
    local ok, playerName = pcall(UnitNameUnmodified or UnitName, "player")
    playerName = ok and SafeString(playerName) or nil
    if playerName then self:StoreDurability(playerName, durability, broken) end

    local now = SafeNumber(GetTime and GetTime()) or 0
    if now - durabilityRequestAt < 4 then return false end
    durabilityRequestAt = now
    return self:SendDurabilityMessage("R")
end

function RaidPreparation:HandleDurabilityComm(message, channel, sender)
    if self.libDurability or self:RegisterLibDurability() then return end
    message = SafeString(message)
    channel = SafeString(channel)
    sender = SafeString(sender)
    if not message or not channel or not sender then return end

    if message == "R" then
        local now = SafeNumber(GetTime and GetTime()) or 0
        local lastReply = durabilityReplyAt[channel] or 0
        if now - lastReply >= 4 then
            durabilityReplyAt[channel] = now
            self:BroadcastDurability(channel)
        end
        return
    end

    local durability, broken = message:match("^(%d+),(%d+)$")
    if durability and broken then
        self:StoreDurability(sender, durability, broken)
        self:ScheduleRefresh(0.05)
    end
end

function RaidPreparation:HandleComm(message, sender)
    message = SafeString(message)
    sender = SafeString(sender)
    if not message or not sender then return end
    local messageType, nonce, durability, mainHand, offHand = strsplit("|", message)
    if messageType == "Q" then
        nonce = SafeString(nonce)
        if nonce then self:BroadcastStatus(nonce, sender) end
    elseif messageType == "S" then
        nonce = SafeString(nonce)
        if nonce and (nonce == "0" or (self.nonce and nonce == self.nonce)) then
            self:StoreRemote(sender, durability, mainHand, offHand)
            self:ScheduleRefresh(0.05)
        end
    end
end

local function GetFullUnitName(unit)
    if UnitFullName then
        local ok, name, realm = pcall(UnitFullName, unit)
        name = ok and SafeString(name) or nil
        realm = ok and SafeString(realm) or nil
        if name then
            if realm and realm ~= "" then return name .. "-" .. realm end
            return name
        end
    end
    local ok, name = pcall(UnitName, unit)
    return ok and SafeString(name) or nil
end

function RaidPreparation:GetReadyStatus(name)
    local key = NormalizeName(name)
    local shortKey = NormalizeName(ShortName(name))
    if not self.ready then return nil end
    local value = key and self.ready[key]
    if value == nil and shortKey then value = self.ready[shortKey] end
    return value
end

function RaidPreparation:SetReadyStatus(unit, status)
    unit = SafeString(unit)
    if not unit then return end
    local name = GetFullUnitName(unit)
    if not name and UnitName then
        local ok, value = pcall(UnitName, unit)
        name = ok and SafeString(value) or nil
    end
    if not name then return end
    status = SafeBoolean(status)
    self.ready = self.ready or {}
    local key = NormalizeName(name)
    local shortKey = NormalizeName(ShortName(name))
    if key then self.ready[key] = status end
    if shortKey then self.ready[shortKey] = status end
end

function RaidPreparation:ApplyRaidBuffStatus(roster)
    roster = type(roster) == "table" and roster or {}
    local providerClasses = {}
    for _, record in ipairs(roster) do
        if record.classToken then providerClasses[record.classToken] = true end
    end

    local expected = {}
    if self.db and self.db.checkRaidBuffs ~= false then
        for _, definition in ipairs(RAID_BUFFS) do
            if self.db[definition.option] ~= false and providerClasses[definition.providerClass] then
                expected[#expected + 1] = definition
            end
        end
    end
    self.expectedRaidBuffs = expected

    for _, record in ipairs(roster) do
        local found = record.raidBuffsFound
        record.raidBuffCount = 0
        record.raidBuffTotal = #expected
        record.raidBuffMissing = {}
        if type(found) ~= "table" then
            record.raidBuff = nil
        elseif #expected == 0 then
            record.raidBuff = true
        else
            for _, definition in ipairs(expected) do
                if found[definition.key] then
                    record.raidBuffCount = record.raidBuffCount + 1
                else
                    record.raidBuffMissing[#record.raidBuffMissing + 1] = L[definition.labelKey]
                end
            end
            record.raidBuff = record.raidBuffCount == record.raidBuffTotal
        end
    end
end

function RaidPreparation:GetRaidBuffReportDetail(record)
    local missing = {}
    local missingSet = {}
    for _, label in ipairs(record.raidBuffMissing or {}) do missingSet[label] = true end
    for _, definition in ipairs(self.expectedRaidBuffs or {}) do
        local fullLabel = L[definition.labelKey]
        if missingSet[fullLabel] then missing[#missing + 1] = L[definition.shortLabelKey] end
    end
    return table.concat(missing, "/")
end

function RaidPreparation:BuildRecord(unit, name, subgroup, index, classToken, role, rank)
    name = SafeString(name)
    if not name then return nil end
    subgroup = math.floor(SafeNumber(subgroup) or 1)
    local food, flask, rune, foodRemaining, flaskRemaining, runeRemaining, raidBuffsFound = self:ScanUnitAuras(unit)
    local remote
    if SafeBooleanCall(UnitIsUnit, unit, "player") then
        local durability, mainHand, offHand = self:GetSelfGearStatus()
        remote = { durability = durability, mainHand = mainHand, offHand = offHand }
    else
        remote = self:GetRemote(name)
    end
    local durability = remote and remote.durability or nil
    local weapon = remote and remote.mainHand or nil
    return {
        unit = unit,
        name = name,
        key = NormalizeName(name),
        subgroup = subgroup,
        index = index,
        classToken = SafeString(classToken),
        role = SafeString(role) or "NONE",
        rank = SafeNumber(rank) or 0,
        food = food,
        flask = flask,
        rune = rune,
        foodRemaining = foodRemaining,
        flaskRemaining = flaskRemaining,
        runeRemaining = runeRemaining,
        raidBuffsFound = raidBuffsFound,
        weapon = weapon,
        offHand = remote and remote.offHand or nil,
        durability = durability,
        ready = self:GetReadyStatus(name),
    }
end

function RaidPreparation:CollectRoster()
    if self.testMode and self.testRoster then return self.testRoster end
    local result = {}
    if SafeBooleanCall(IsInRaid) then
        local count = math.min(40, math.floor(SafeNumber(GetNumGroupMembers and GetNumGroupMembers()) or 0))
        for index = 1, count do
            local ok, name, rank, subgroup, _, _, classToken, _, _, _, role = pcall(GetRaidRosterInfo, index)
            if ok then
                local record = self:BuildRecord("raid" .. index, name, subgroup, index, classToken, role, rank)
                if record then result[#result + 1] = record end
            end
        end
    elseif self.db.raidOnly ~= true and (SafeBooleanCall(IsInGroup) or SafeBooleanCall(UnitExists, "player")) then
        local units = { "player" }
        local count = math.min(4, math.floor(SafeNumber(GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0))
        for index = 1, count do units[#units + 1] = "party" .. index end
        for index, unit in ipairs(units) do
            local name = GetFullUnitName(unit)
            local classToken
            local ok, _, value = pcall(UnitClass, unit)
            if ok then classToken = SafeString(value) end
            local role
            if UnitGroupRolesAssigned then
                local roleOK, value = pcall(UnitGroupRolesAssigned, unit)
                role = roleOK and SafeString(value) or nil
            end
            local record = self:BuildRecord(unit, name, 1, index, classToken, role, 0)
            if record then result[#result + 1] = record end
        end
    end

    table.sort(result, function(a, b)
        if a.subgroup ~= b.subgroup then return a.subgroup < b.subgroup end
        return a.index < b.index
    end)
    self:ApplyRaidBuffStatus(result)
    self.roster = result
    return result
end

function RaidPreparation:IsCheckedValue(value, kind)
    local db = self.db or {}
    if kind == "food" and db.checkFood == false then return true end
    if kind == "flask" and db.checkFlask == false then return true end
    if kind == "rune" and db.checkRune == false then return true end
    if kind == "weapon" and db.checkWeaponEnchant == false then return true end
    if kind == "durability" and db.checkDurability == false then return true end
    if kind == "raidBuff" and db.checkRaidBuffs == false then return true end
    if kind == "durability" then
        return type(value) == "number" and value >= Clamp(db.durabilityThreshold, 1, 100, 30)
    end
    return value == true
end

function RaidPreparation:IsRecordComplete(record, includeReady)
    if not self:IsCheckedValue(record.food, "food") then return false end
    if not self:IsCheckedValue(record.flask, "flask") then return false end
    if not self:IsCheckedValue(record.rune, "rune") then return false end
    if not self:IsCheckedValue(record.raidBuff, "raidBuff") then return false end
    if not self:IsCheckedValue(record.weapon, "weapon") then return false end
    if not self:IsCheckedValue(record.durability, "durability") then return false end
    if includeReady and record.ready ~= true then return false end
    return true
end

function RaidPreparation:UpdateDynamicRoster()
    if self.testMode then return end
    for _, record in ipairs(self.roster or {}) do
        record.ready = self:GetReadyStatus(record.name)
        local remote
        if SafeBooleanCall(UnitIsUnit, record.unit, "player") then
            local durability, mainHand, offHand = self:GetSelfGearStatus()
            remote = { durability = durability, mainHand = mainHand, offHand = offHand }
        else
            remote = self:GetRemote(record.name)
        end
        record.durability = remote and remote.durability or nil
        record.weapon = remote and remote.mainHand or nil
        record.offHand = remote and remote.offHand or nil
    end
end

function RaidPreparation:RefreshUnitAura(unit)
    unit = SafeString(unit)
    if not unit or self.testMode then return end
    for _, record in ipairs(self.roster or {}) do
        if record.unit == unit then
            record.food, record.flask, record.rune,
                record.foodRemaining, record.flaskRemaining, record.runeRemaining,
                record.raidBuffsFound = self:ScanUnitAuras(unit)
            self:ApplyRaidBuffStatus(self.roster)
            break
        end
    end
end


function RaidPreparation:SetStatus(message, kind)
    if not frame then return end
    frame.status:SetText(SafeString(message) or "")
    if kind == "error" then
        frame.status:SetTextColor(1.00, 0.34, 0.30, 1)
    elseif kind == "success" then
        frame.status:SetTextColor(0.32, 1.00, 0.56, 1)
    else
        frame.status:SetTextColor(0.58, 0.64, 0.71, 1)
    end
end

local CHECK_COLUMNS = {
    { "food", "RAIDPREP_COLUMN_FOOD" }, { "flask", "RAIDPREP_COLUMN_FLASK" },
    { "rune", "RAIDPREP_COLUMN_RUNE" }, { "raidBuff", "RAIDPREP_COLUMN_RAIDBUFF" },
    { "weapon", "RAIDPREP_COLUMN_WEAPON" }, { "durability", "RAIDPREP_COLUMN_DURABILITY" },
}

function RaidPreparation:GetVisibleRoster()
    local filtered = {}
    for _, record in ipairs(self.roster or {}) do
        if not self:IsRecordComplete(record, true) then filtered[#filtered + 1] = record end
    end
    return filtered
end

function RaidPreparation:Refresh()
    if not frame or not self.db then return end
    self:UpdateDynamicRoster()
    local source = self.roster or {}
    local ready, declined, checks = 0, 0, 0
    for _, record in ipairs(source) do
        if record.ready == true then ready = ready + 1
        elseif record.ready == false then declined = declined + 1 end
        if not self:IsRecordComplete(record, false) then checks = checks + 1 end
    end
    local total = #source
    local waiting = total - ready - declined
    self.fullyReady = total > 0 and ready == total and checks == 0
    frame.summary:SetText(string.format(L["RAIDPREP_RESPONSES"], ready + declined, total))
    frame.headline:SetText(self.fullyReady and L["RAIDPREP_COMPLETE"]
        or total == 0 and L["RAIDPREP_NO_GROUP"]
        or waiting == 0 and declined == 0 and L["RAIDPREP_RESPONDED"]
        or L["RAIDPREP_INCOMPLETE"])
    frame.headline:SetTextColor(unpack(self.fullyReady and {0.54, 0.75, 0.64, 1} or {0.85, 0.74, 0.52, 1}))
    frame.counts:SetText(string.format(L["RAIDPREP_COUNTS"], ready, declined, waiting))
    frame.checks:SetText(string.format(L["RAIDPREP_CHECK_COUNT"], checks))
    local roster = self:GetVisibleRoster()
    self.visibleRoster = roster
    local maxOffset = math.max(0, math.ceil(#roster / 3) - 3) * 3
    scrollOffset = math.max(0, math.min(scrollOffset, maxOffset))
    local lines = math.max(1, math.min(3, math.ceil(#roster / 3)))
    frame:SetHeight(210 + lines * ROW_HEIGHT)
    frame.scrollTrack:SetShown(maxOffset > 0)
    frame.scrollThumb:SetShown(maxOffset > 0)
    if maxOffset > 0 then
        local trackHeight = lines * ROW_HEIGHT
        local thumbHeight = math.max(20, trackHeight * VISIBLE_ROWS / #roster)
        frame.scrollTrack:SetHeight(trackHeight)
        frame.scrollThumb:SetHeight(thumbHeight)
        frame.scrollThumb:ClearAllPoints()
        frame.scrollThumb:SetPoint("TOP", frame.scrollTrack, "TOP", 0, -(trackHeight - thumbHeight) * scrollOffset / maxOffset)
    end
    frame.empty:SetShown(#roster == 0)
    frame.empty:SetText(self.fullyReady and L["RAIDPREP_COMPLETE"] or L["RAIDPREP_STATUS_READY"])
    for index, row in ipairs(frame.rows) do
        local record = roster[scrollOffset + index]
        row.record = record
        row:SetShown(record ~= nil)
        if record then
            row.name:SetText(ShortName(record.name))
            row.name:SetTextColor(GetClassColor(record.classToken))
            local issues = {}
            for _, column in ipairs(CHECK_COLUMNS) do
                local value = record[column[1]]
                if not self:IsCheckedValue(value, column[1]) then
                    issues[#issues + 1] = L[column[2]] .. (value == nil and " ?" or "")
                end
            end
            if record.ready ~= true then
                issues[#issues + 1] = record.ready == false and L["RAIDPREP_NOT_READY"] or L["RAIDPREP_WAITING"]
            end
            row.detail:SetText(table.concat(issues, " / "))
            row.tooltipLines = issues
            if self.db.checkRaidBuffs ~= false and record.raidBuff == false then
                for _, buff in ipairs(record.raidBuffMissing or {}) do issues[#issues + 1] = buff end
            end
        end
    end
    if not self.fullyReady then frame.closeElapsed = nil; frame:SetAlpha(1) end
    if self.fullyReady and frame.autoOpened and not self.testMode and frame:IsShown() then
        frame.closeElapsed = frame.closeElapsed or 0
    end
end

function RaidPreparation:ScheduleRefresh(delay)
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(delay or 0.15, function()
        refreshPending = false
        if active and frame and frame:IsShown() then RaidPreparation:Refresh() end
    end)
end

function RaidPreparation:ScheduleRosterRefresh(delay)
    if self.rosterRefreshPending then return end
    self.rosterRefreshPending = true
    C_Timer.After(delay or 0.2, function()
        RaidPreparation.rosterRefreshPending = false
        if active and not RaidPreparation.testMode then
            RaidPreparation:CollectRoster()
            if frame and frame:IsShown() then RaidPreparation:Refresh() end
        end
    end)
end

function RaidPreparation:CanOpenAutomatically()
    if self.db.raidOnly == true and not SafeBooleanCall(IsInRaid) then return false end
    if self.db.leaderOnly == true
        and not (SafeBooleanCall(UnitIsGroupLeader, "player") or SafeBooleanCall(UnitIsGroupAssistant, "player")) then
        return false
    end
    return true
end

function RaidPreparation:CanReport()
    if not SafeBooleanCall(IsInRaid) then return true end
    return SafeBooleanCall(UnitIsGroupLeader, "player") or SafeBooleanCall(UnitIsGroupAssistant, "player")
end

function RaidPreparation:GetReportChannel()
    if SafeBooleanCall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if SafeBooleanCall(IsInRaid) then return "RAID" end
    if SafeBooleanCall(IsInGroup) then return "PARTY" end
    return nil
end

function RaidPreparation:BuildReportGroups()
    local groups = {
        food = {}, flask = {}, rune = {}, raidBuff = {}, weapon = {}, durability = {}, unknown = {},
    }
    for _, record in ipairs(self:CollectRoster()) do
        local name = ShortName(record.name)
        local hasUnknown = false
        if self.db.checkFood ~= false and record.food ~= true then
            if record.food == nil then hasUnknown = true else groups.food[#groups.food + 1] = name end
        end
        if self.db.checkFlask ~= false and record.flask ~= true then
            if record.flask == nil then hasUnknown = true else groups.flask[#groups.flask + 1] = name end
        end
        if self.db.checkRune ~= false and record.rune ~= true then
            if record.rune == nil then hasUnknown = true else groups.rune[#groups.rune + 1] = name end
        end
        if self.db.checkRaidBuffs ~= false and (record.raidBuffTotal or 0) > 0 and record.raidBuff ~= true then
            if record.raidBuff == nil then
                hasUnknown = true
            else
                local detail = self:GetRaidBuffReportDetail(record)
                groups.raidBuff[#groups.raidBuff + 1] = name .. (detail ~= "" and " (" .. detail .. ")" or "")
            end
        end
        if self.db.checkWeaponEnchant ~= false and record.weapon ~= true then
            if record.weapon == nil then hasUnknown = true else groups.weapon[#groups.weapon + 1] = name end
        end
        if self.db.checkDurability ~= false then
            if record.durability == nil then
                hasUnknown = true
            elseif record.durability < Clamp(self.db.durabilityThreshold, 1, 100, 30) then
                groups.durability[#groups.durability + 1] = name
            end
        end
        if hasUnknown and self.db.reportUnknown == true then groups.unknown[#groups.unknown + 1] = name end
    end
    return groups
end

local function SplitReport(label, names)
    local messages = {}
    local current = label
    for _, name in ipairs(names) do
        local addition = (#current > #label and ", " or "") .. name
        if #current + #addition > 220 then
            messages[#messages + 1] = current
            current = label .. name
        else
            current = current .. addition
        end
    end
    if #current > #label then messages[#messages + 1] = current end
    return messages
end

function RaidPreparation:SendReport(automatic)
    if self.testMode then
        self:SetStatus(L["RAIDPREP_STATUS_TEST"], "error")
        return false
    end
    if not self:CanReport() then
        self:SetStatus(L["RAIDPREP_REPORT_PERMISSION"], "error")
        return false
    end
    local channel = self:GetReportChannel()
    if not channel then
        self:SetStatus(L["RAIDPREP_REPORT_NO_GROUP"], "error")
        return false
    end
    local groups = self:BuildReportGroups()
    local order = { "food", "flask", "rune", "raidBuff", "weapon", "durability", "unknown" }
    local labels = {
        food = L["RAIDPREP_REPORT_FOOD"], flask = L["RAIDPREP_REPORT_FLASK"],
        rune = L["RAIDPREP_REPORT_RUNE"], raidBuff = L["RAIDPREP_REPORT_RAIDBUFF"],
        weapon = L["RAIDPREP_REPORT_WEAPON"],
        durability = L["RAIDPREP_REPORT_DURABILITY"], unknown = L["RAIDPREP_REPORT_UNKNOWN"],
    }
    local messages = {}
    for _, key in ipairs(order) do
        local parts = SplitReport(labels[key], groups[key])
        for _, message in ipairs(parts) do messages[#messages + 1] = message end
    end
    if #messages == 0 then messages[1] = L["RAIDPREP_REPORT_ALL_READY"] end
    for index, message in ipairs(messages) do
        C_Timer.After((index - 1) * 0.25, function()
            pcall(SendChatMessage, message, channel)
        end)
    end
    self:SetStatus(automatic and L["RAIDPREP_STATUS_AUTO_REPORTED"] or L["RAIDPREP_STATUS_REPORTED"], "success")
    return true
end

function RaidPreparation:BuildTestRoster()
    local classes = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN", "HUNTER", "SHAMAN", "WARLOCK", "MONK", "DEMONHUNTER", "EVOKER" }
    local result = {}
    for index = 1, 20 do
        result[index] = {
            unit = "none",
            name = string.format("%s %02d", L["RAIDPREP_TEST_PLAYER"], index),
            key = "test" .. index,
            subgroup = math.floor((index - 1) / 5) + 1,
            index = index,
            classToken = classes[((index - 1) % #classes) + 1],
            role = index <= 4 and "TANK" or (index <= 8 and "HEALER" or "DAMAGER"),
            food = index % 6 ~= 0,
            flask = index % 5 ~= 0 and true or "LOW",
            rune = index % 4 ~= 0,
            raidBuff = index % 6 ~= 0,
            raidBuffCount = index % 6 ~= 0 and 6 or 4,
            raidBuffTotal = 6,
            raidBuffMissing = index % 6 ~= 0 and {} or {
                L["RAIDPREP_BUFF_INTELLECT"], L["RAIDPREP_BUFF_MASTERY"],
            },
            weapon = index % 7 == 0 and nil or index % 3 ~= 0,
            durability = index % 8 == 0 and 18 or (72 + (index % 20)),
            ready = index % 5 ~= 0,
            foodRemaining = 2400,
            flaskRemaining = index % 5 == 0 and 240 or 3600,
            runeRemaining = 3600,
        }
    end
    self.testRoster = result
    self.roster = result
end

function RaidPreparation:CreateFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "DDingUIToolkitRaidPreparationFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 264)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:RegisterForDrag("LeftButton")
    SetBackdrop(frame, P.background, P.border)
    frame:SetScript("OnDragStart", function(self)
        if not SafeBooleanCall(InCombatLockdown) then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        RaidPreparation.db.position = {point=point, relativePoint=relativePoint,
            x=math.floor((SafeNumber(x) or 0) + 0.5), y=math.floor((SafeNumber(y) or 0) + 0.5)}
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        scrollOffset = scrollOffset - math.floor(SafeNumber(delta) or 0) * 3
        RaidPreparation:Refresh()
    end)
    frame:SetScript("OnHide", function(self)
        self.closeElapsed = nil
        self.autoOpened = false
        self:SetAlpha(1)
        if GameTooltip and GameTooltip:GetOwner() and GameTooltip:GetOwner().raidPrepRow then GameTooltip:Hide() end
    end)
    frame:SetScript("OnUpdate", function(self, elapsed)
        if self.closeElapsed == nil then return end
        if not active or not self.autoOpened or RaidPreparation.testMode or not RaidPreparation.fullyReady then
            self.closeElapsed = nil; self:SetAlpha(1); return
        end
        self.closeElapsed = self.closeElapsed + elapsed
        self:SetAlpha(math.max(0, 1 - math.max(0, self.closeElapsed - 1.5) / 0.25))
        if self.closeElapsed >= 1.75 then self:Hide() end
    end)
    frame.header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(38)
    SetBackdrop(frame.header, P.header, P.header)
    frame.title = AddText(frame.header, 13, P.text, L["RAIDPREP_TITLE"])
    frame.title:SetPoint("LEFT", 16, 0)
    frame.close = CreateButton(frame.header, "X", 28, false)
    frame.close:SetPoint("RIGHT", -8, 0)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.headline = AddText(frame, 23, {0.85,0.74,0.52,1}, "")
    frame.headline:SetPoint("TOPLEFT", 18, -57)
    frame.headline:SetSize(400, 32)
    frame.headline:SetJustifyH("LEFT")
    frame.headline:SetWordWrap(false)
    frame.summary = AddText(frame, 20, P.textBright, "")
    frame.summary:SetPoint("TOPRIGHT", -18, -60)
    frame.summary:SetSize(170, 28)
    frame.summary:SetJustifyH("RIGHT")
    frame.hint = AddText(frame, 12, P.textDim, L["RAIDPREP_CHECK_HINT"])
    frame.hint:SetPoint("TOPLEFT", 18, -96)
    frame.counts = AddText(frame, 13, P.text, "")
    frame.counts:SetPoint("TOPLEFT", 18, -132)
    frame.checks = AddText(frame, 13, {0.85,0.74,0.52,1}, "")
    frame.checks:SetPoint("TOPRIGHT", -18, -132)
    for _, y in ipairs({-39,-120,-160}) do
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 1, y); line:SetPoint("TOPRIGHT", -1, y)
        line:SetHeight(1); line:SetColorTexture(unpack(P.separator))
    end
    frame.rows = {}
    for index = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row.raidPrepRow = true
        row:SetSize(194, ROW_HEIGHT - 6)
        row:SetPoint("TOPLEFT", 18 + ((index-1) % 3) * 204, -171 - math.floor((index-1)/3)*ROW_HEIGHT)
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", frame:GetScript("OnMouseWheel"))
        row.name = AddText(row, 13, P.text, "")
        row.name:SetPoint("TOPLEFT"); row.name:SetSize(190, 19)
        row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.detail = AddText(row, 11, P.textDim, "")
        row.detail:SetPoint("TOPLEFT", 0, -21); row.detail:SetSize(190, 23)
        row.detail:SetJustifyH("LEFT"); row.detail:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
            if not self.record or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ShortName(self.record.name), GetClassColor(self.record.classToken))
            for _, text in ipairs(self.tooltipLines or {}) do GameTooltip:AddLine(text, 0.85, 0.74, 0.52, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame.rows[index] = row
    end
    frame.empty = AddText(frame, 13, {0.54,0.75,0.64,1}, "")
    frame.empty:SetPoint("TOPLEFT", 18, -184)
    frame.scrollTrack = frame:CreateTexture(nil, "BACKGROUND")
    frame.scrollTrack:SetPoint("TOPRIGHT", -8, -171); frame.scrollTrack:SetWidth(2)
    frame.scrollTrack:SetColorTexture(unpack(P.separator))
    frame.scrollThumb = frame:CreateTexture(nil, "ARTWORK")
    frame.scrollThumb:SetWidth(4); frame.scrollThumb:SetColorTexture(unpack(P.accent))
    frame.status = AddText(frame, 11, P.textDim, L["RAIDPREP_UNKNOWN_HINT"])
    frame.status:SetPoint("BOTTOMLEFT", 18, 20); frame.status:SetSize(350, 18)
    frame.status:SetJustifyH("LEFT"); frame.status:SetWordWrap(false)
    frame.reportButton = CreateButton(frame, L["RAIDPREP_REPORT"], 108, false)
    frame.reportButton:SetPoint("BOTTOMRIGHT", -14, 13)
    frame.reportButton:SetScript("OnClick", function() RaidPreparation:SendReport(false) end)
    frame.refreshButton = CreateButton(frame, L["RAIDPREP_REFRESH"], 82, false)
    frame.refreshButton:SetPoint("RIGHT", frame.reportButton, "LEFT", -6, 0)
    frame.refreshButton:SetScript("OnClick", function()
        RaidPreparation.testMode = false
        RaidPreparation:RequestStatuses()
        RaidPreparation:Refresh()
    end)
    table.insert(UISpecialFrames, frame:GetName())
    frame:Hide()
    self.frame = frame
    return frame
end

function RaidPreparation:ApplySettings()
    self.db = EnsureDB()
    if not self.db then return end
    self:BuildSpellSets()
    if self.roster then self:ApplyRaidBuffStatus(self.roster) end
    local display = self:CreateFrame()
    display:SetScale(Clamp(self.db.scale, 0.7, 1.4, 1))
    display:ClearAllPoints()
    local position = self.db.position
    display:SetPoint(position.point or "CENTER", UIParent, position.relativePoint or "CENTER",
        Clamp(position.x, -1200, 1200, 0), Clamp(position.y, -800, 800, 10))
    self:Refresh()
end

function RaidPreparation:ShowWindow(testMode, automatic)
    if SafeBooleanCall(InCombatLockdown) then return end
    self.db = self.db or EnsureDB()
    if not self.db then return end
    self.testMode = testMode == true
    if self.testMode then self:BuildTestRoster() else self:CollectRoster() end
    scrollOffset = 0
    self:ApplySettings()
    frame.autoOpened = automatic == true
    frame.closeElapsed = nil
    frame:SetAlpha(1)
    frame:Show()
    self:Refresh()
end

function RaidPreparation:ToggleWindow()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:ShowWindow(false)
        self:RequestStatuses()
        self:Refresh()
    end
end

function RaidPreparation:TestMode()
    if frame and frame:IsShown() and self.testMode then
        self.testMode = false
        frame:Hide()
    else
        self:ShowWindow(true)
        self:SetStatus(L["RAIDPREP_STATUS_TEST"], "normal")
    end
end

function RaidPreparation:ResetPosition()
    self.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 10 }
    self:ApplySettings()
end

function RaidPreparation:HandleReadyCheck(initiator)
    readySerial = readySerial + 1
    readyCheckActive = true
    local serial = readySerial
    self.ready = {}
    local name = SafeString(initiator)
    if name and NormalizeName(name) then
        self.ready[NormalizeName(name)] = true
        self.ready[NormalizeName(ShortName(name))] = true
    end
    self.testMode = false
    self:AnnounceReadyCheckStatus()
    if self.db.autoOpen ~= false and self:CanOpenAutomatically() then self:ShowWindow(false, true) end
    C_Timer.After(0.4, function()
        if active and serial == readySerial and frame and frame:IsShown() then RaidPreparation:Refresh() end
    end)
    C_Timer.After(1.5, function()
        if not active or serial ~= readySerial then return end
        if frame and frame:IsShown() then RaidPreparation:Refresh() end
        if RaidPreparation.db.autoReport == true then RaidPreparation:SendReport(true) end
    end)
end

function RaidPreparation:HandleReadyFinished()
    readyCheckActive = false
    if self.db.closeAfterReadyCheck ~= true then return end
    local serial = readySerial
    C_Timer.After(Clamp(self.db.closeDelay, 0, 30, 5), function()
        if active and serial == readySerial and frame and frame.autoOpened and not RaidPreparation.fullyReady then frame:Hide() end
    end)
end

function RaidPreparation:OnInitialize()
    self.db = EnsureDB()
    self.remote = {}
    self.ready = {}
    self:BuildSpellSets()
    self.initialized = true
end

function RaidPreparation:OnEnable()
    self.db = EnsureDB()
    self.remote = self.remote or {}
    self.ready = self.ready or {}
    self:BuildSpellSets()
    active = true
    self:RegisterLibDurability()
end

function RaidPreparation:OnDisable()
    active = false
    readyCheckActive = false
    self.testMode = false
    self:UnregisterLibDurability()
    if frame then frame:Hide() end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, DURABILITY_PREFIX)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
eventFrame:RegisterEvent("READY_CHECK_FINISHED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if active then RaidPreparation:RegisterLibDurability() end
        return
    end
    if not active then return end
    if event == "READY_CHECK" then
        RaidPreparation:HandleReadyCheck(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if frame then frame:Hide() end
    elseif event == "READY_CHECK_CONFIRM" then
        local unit, status = ...
        RaidPreparation:SetReadyStatus(unit, status)
        RaidPreparation:ScheduleRefresh(0.05)
    elseif event == "READY_CHECK_FINISHED" then
        RaidPreparation:HandleReadyFinished()
        RaidPreparation:ScheduleRefresh(0.05)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        prefix = SafeString(prefix)
        if prefix == COMM_PREFIX then
            RaidPreparation:HandleComm(message, sender)
        elseif prefix == DURABILITY_PREFIX then
            RaidPreparation:HandleDurabilityComm(message, channel, sender)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        readyCheckActive = false
        RaidPreparation.remote = {}
        RaidPreparation.ready = {}
        if frame then frame:Hide() end
    elseif event == "UNIT_AURA" then
        if readyCheckActive or (frame and frame:IsShown()) then
            local unit = ...
            RaidPreparation:RefreshUnitAura(unit)
            if frame and frame:IsShown() then RaidPreparation:ScheduleRefresh(0.12) end
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if readyCheckActive or (frame and frame:IsShown()) then
            RaidPreparation:ScheduleRosterRefresh(0.2)
        else
            RaidPreparation.roster = nil
        end
    elseif frame and frame:IsShown() and not RaidPreparation.testMode then
        RaidPreparation:ScheduleRefresh(0.12)
    end
end)

SLASH_DDINGTOOLKITRAIDPREPARATION1 = "/ddprep"
SlashCmdList.DDINGTOOLKITRAIDPREPARATION = function() RaidPreparation:ToggleWindow() end

DDingToolKit:RegisterModule("RaidPreparation", RaidPreparation)
