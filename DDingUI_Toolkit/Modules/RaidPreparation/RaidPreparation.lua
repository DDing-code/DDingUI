-- DDingUI Toolkit - Raid Preparation

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib

local RaidPreparation = {}
ns.RaidPreparation = RaidPreparation

local COMM_PREFIX = "DDTREADY"
local DURABILITY_PREFIX = "LibDRBLT"
-- [STYLE] Compact ready-check strip with separate optional items, no title bar.
-- Shared visuals (icons, badges, status colours, buttons) live in UI/ReadyStatus.lua.
local FRAME_WIDTH, FRAME_HEIGHT = 412, 92
local GAUGE_SEGMENTS = 10

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

-- [12.0.1] Boss auras linked from ko.wowhead.com/spell=1276718 (Radiant rune).
local VANTUS_IDS = {
    [1276685] = true, [1276705] = true, [1276709] = true, [1276691] = true,
    [1300174] = true, [1276712] = true, [1276669] = true, [1276715] = true,
    [1276687] = true, [1276682] = true,
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
RaidPreparation.RaidBuffs = RAID_BUFFS
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
    self.vantusIDs = ParseSpellIDs(db.customVantusSpellIDs, CopyTable(VANTUS_IDS)) -- [REFACTOR]
end

function RaidPreparation:ScanUnitAuras(unit)
    if not SafeBooleanCall(UnitExists, unit) or not SafeBooleanCall(UnitIsConnected, unit) then
        return nil, nil, nil, nil, nil, nil, nil
    end
    local db = self.db or {}
    local minimumSeconds = Clamp(db.minimumBuffMinutes, 0, 60, 10) * 60
    local food, flask, rune, vantus = false, false, false, false
    local foodRemaining, flaskRemaining, runeRemaining, vantusRemaining
    local icons = {}
    local incomplete = false
    local vantusUnknown = false
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
            local auraName = SafeString(aura.name)
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
            -- [12.0.1] Public names cover new boss runes without guessing their IDs.
            if spellID and self.vantusIDs[spellID]
                or auraName and (auraName:find("반투스 룬", 1, true) == 1 or auraName:find("Vantus Rune", 1, true) == 1) then
                vantus, vantusRemaining = MergeStatus(vantus, longEnough, remaining)
                icons.vantus = icon or icons.vantus
            elseif IsSecret(aura.name) then
                vantusUnknown = true
            end
        end
    end
    if incomplete then
        if food == false then food = nil end
        if flask == false then flask = nil end
        if rune == false then rune = nil end
        if vantus == false then vantus = nil end
        raidBuffsFound = nil
    end
    if vantusUnknown and vantus == false then vantus = nil end
    return food, flask, rune, foodRemaining, flaskRemaining, runeRemaining, raidBuffsFound, icons, vantus, vantusRemaining
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
    local food, flask, rune, foodRemaining, flaskRemaining, runeRemaining, raidBuffsFound, _, vantus, vantusRemaining = self:ScanUnitAuras(unit)
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
        vantus = vantus,
        foodRemaining = foodRemaining,
        flaskRemaining = flaskRemaining,
        runeRemaining = runeRemaining,
        vantusRemaining = vantusRemaining,
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
                record.raidBuffsFound, record.icons, record.vantus, record.vantusRemaining = self:ScanUnitAuras(unit)
            self:ApplyRaidBuffStatus(self.roster)
            break
        end
    end
end


-- Status messages (report sent, no permission, test roster) go to chat; the strip has no status line.
function RaidPreparation:SetStatus(message, kind)
    message = SafeString(message)
    if not message then return end
    self.lastStatus = { text = message, kind = kind }
    if kind == "error" and ns.PrintError then
        ns.PrintError(message)
    elseif ns.Print then
        ns.Print(message)
    end
end

-- [STYLE] Item icons (same order and same Toolkit icons in both ready-check windows).
-- Game icons stay as the fallback when UI/ReadyStatus.lua is not loaded.
local OWN_ICONS = ns.ReadyStatus and ns.ReadyStatus.ITEM_ICONS or {}
local ITEMS = {
    { key = "food", label = "RAIDPREP_COLUMN_FOOD", option = "checkFood", icon = OWN_ICONS.food or 134062 },
    { key = "flask", label = "RAIDPREP_COLUMN_FLASK", option = "checkFlask", icon = OWN_ICONS.flask or 134830 },
    { key = "raidBuff", label = "RAIDPREP_COLUMN_RAIDBUFF", option = "checkRaidBuffs",
      icon = OWN_ICONS.raidBuff or "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    { key = "weapon", label = "RAIDPREP_COLUMN_WEAPON", option = "checkWeaponEnchant", icon = OWN_ICONS.weapon or 135274 },
    { key = "durability", label = "RAIDPREP_COLUMN_DURABILITY", option = "checkDurability",
      icon = OWN_ICONS.durability or "Interface\\Icons\\Trade_BlackSmithing" },
    { key = "rune", label = "RCA_ROW_RUNE", option = "checkRune", optional = true, icon = OWN_ICONS.rune or 134419 },
    { key = "vantus", label = "RCA_ROW_VANTUS", option = "checkVantus", optional = true, icon = OWN_ICONS.vantus or 134419 },
}
RaidPreparation.Items = ITEMS

local function RS() return ns.ReadyStatus end

--- "ok" | "warn" (short time / low durability) | "bad" (missing) | "unknown" | "off" (check disabled)
function RaidPreparation:GetItemState(record, item)
    local db = self.db or {}
    if db[item.option] == false then return "off" end
    local value = record[item.key]
    if item.key == "durability" then
        if type(value) ~= "number" then return "unknown" end
        return value >= Clamp(db.durabilityThreshold, 1, 100, 30) and "ok" or "warn"
    end
    if value == true then return "ok" end
    if value == "LOW" then return "warn" end
    if value == false then return "bad" end
    return "unknown"
end

local function ItemDetail(self, record, item, state)
    if item.key == "durability" and type(record.durability) == "number" then
        return string.format("%d%%", math.floor(record.durability + 0.5))
    end
    if item.key == "raidBuff" and state == "bad" then
        local detail = self:GetRaidBuffReportDetail(record)
        return detail ~= "" and detail or nil
    end
    if state == "warn" then return L["RAIDPREP_LOW"] end
    return nil
end

function RaidPreparation:SummarizeItems(source)
    local summary = {}
    for _, item in ipairs(ITEMS) do
        local entry = { item = item, bad = {}, warn = {}, unknown = {}, off = false }
        for _, record in ipairs(source) do
            local state = self:GetItemState(record, item)
            if state == "off" then
                entry.off = true
                break
            elseif state == "bad" or state == "warn" or state == "unknown" then
                local list = entry[state]
                list[#list + 1] = record
            end
        end
        entry.problems = #entry.bad + #entry.warn
        if entry.off then
            entry.state = nil
        elseif entry.problems > 0 then
            entry.state = item.optional and "opt" or (#entry.bad > 0 and "bad" or "warn")
        elseif #entry.unknown == 0 and #source > 0 then
            entry.state = "ok"
        end
        summary[#summary + 1] = entry
    end
    return summary
end

local function ShowItemTooltip(cell)
    if not GameTooltip or not cell.entry then return end
    local entry = cell.entry
    local styles = RS()
    GameTooltip:SetOwner(cell, "ANCHOR_TOP")
    local title = L[entry.item.label]
    if entry.item.optional then title = title .. " · " .. L["RAIDPREP_OPTIONAL_LABEL"] end
    GameTooltip:AddLine(title, styles.RGB(styles.Token("text", "highlight")))
    if entry.off then
        GameTooltip:AddLine(L["RAIDPREP_ITEM_OFF"], styles.RGB(styles.Color(nil)))
    elseif entry.problems == 0 and #entry.unknown == 0 then
        GameTooltip:AddLine(L["RAIDPREP_ALL_OK"], styles.RGB(styles.Color("ok")))
    end
    for _, state in ipairs({ "bad", "warn" }) do
        for _, record in ipairs(entry[state]) do
            local detail = ItemDetail(RaidPreparation, record, entry.item, state)
            local r, g, b = GetClassColor(record.classToken)
            GameTooltip:AddLine(ShortName(record.name) .. (detail and ("  " .. detail) or ""), r, g, b)
        end
    end
    if #entry.unknown > 0 then
        local names = {}
        for _, record in ipairs(entry.unknown) do names[#names + 1] = ShortName(record.name) end
        GameTooltip:AddLine(L["RAIDPREP_UNKNOWN_GROUP"] .. ": " .. table.concat(names, ", "),
            styles.RGB(styles.Color(nil)))
    end
    if entry.item.optional then
        GameTooltip:AddLine(L["RAIDPREP_OPTIONAL_NOTE"], styles.RGB(styles.Token("text", "dim")))
    end
    GameTooltip:Show()
end
RaidPreparation.ShowItemTooltip = ShowItemTooltip

local function ShowReadyTooltip(area)
    if not GameTooltip or not area.groups then return end
    local styles = RS()
    GameTooltip:SetOwner(area, "ANCHOR_TOP")
    GameTooltip:AddLine(area.headline or L["RAIDPREP_TITLE"], styles.RGB(styles.Token("text", "highlight")))
    local any = false
    for _, group in ipairs(area.groups) do
        if #group.records > 0 then
            any = true
            GameTooltip:AddLine(group.label, styles.RGB(styles.Color(group.state)))
            for _, record in ipairs(group.records) do
                GameTooltip:AddLine(ShortName(record.name), GetClassColor(record.classToken))
            end
        end
    end
    if not any then GameTooltip:AddLine(L["RAIDPREP_ALL_OK"], styles.RGB(styles.Color("ok"))) end
    GameTooltip:Show()
end

function RaidPreparation:Refresh()
    if not frame or not self.db then return end
    self:UpdateDynamicRoster()
    local styles = RS()
    local source = self.roster or {}
    local ready, checks = 0, 0
    local declinedRecords, waitingRecords = {}, {}
    for _, record in ipairs(source) do
        if record.ready == true then ready = ready + 1
        elseif record.ready == false then declinedRecords[#declinedRecords + 1] = record
        else waitingRecords[#waitingRecords + 1] = record end
        if not self:IsRecordComplete(record, false) then checks = checks + 1 end
    end
    local total = #source
    local declined = #declinedRecords
    self.fullyReady = total > 0 and ready == total and checks == 0

    local countState = self.fullyReady and "ok" or (total == 0 and nil or "warn")
    frame.count:SetText(tostring(ready))
    frame.count:SetTextColor(styles.Unpack(styles.Color(countState)))
    frame.total:SetText("/" .. total)
    frame.headline:SetText(self.fullyReady and L["RAIDPREP_COMPLETE"]
        or total == 0 and L["RAIDPREP_NO_GROUP"]
        or L["RAIDPREP_INCOMPLETE"])
    frame.replies:SetText(string.format(L["RAIDPREP_REPLIES"], ready + declined))
    frame.countArea.headline = frame.headline:GetText()
    frame.countArea.groups = {
        { label = L["RAIDPREP_NOT_READY"], state = "bad", records = declinedRecords },
        { label = L["RAIDPREP_WAITING"], state = "warn", records = waitingRecords },
    }

    local filled = total > 0 and math.floor(ready / total * GAUGE_SEGMENTS) or 0
    if ready == total and total > 0 then filled = GAUGE_SEGMENTS end
    for index, segment in ipairs(frame.gauge.segments) do
        if index <= filled then
            styles.Tint(segment, styles.Color("ok"))
        else
            styles.Tint(segment, styles.Token("bg", "input"))
        end
    end

    local summary = self:SummarizeItems(source)
    self.itemSummary = summary
    for index, cell in ipairs(frame.icons) do
        local entry = summary[index]
        cell.entry = entry
        cell:SetState(entry.state)
        cell:SetBadge(entry.problems, entry.state)
        cell:SetAlpha(entry.off and 0.35 or 1)
    end
    frame.hint:SetText(self.testMode and L["RAIDPREP_STATUS_TEST"] or L["RAIDPREP_ICON_HINT"])
    frame.reportButton:SetDisabledState(not self:CanReport())

    if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner and owner.raidPrepItem and frame:IsShown() then ShowItemTooltip(owner)
        elseif owner == frame.countArea and frame:IsShown() then ShowReadyTooltip(owner) end
    end

    if not self.fullyReady then frame.closeElapsed = nil; frame:SetAlpha(1) end
    if self.fullyReady and frame.autoOpened and not self.testMode and frame:IsShown() then
        frame.closeElapsed = frame.closeElapsed or 0
    end
end
RaidPreparation.ShowReadyTooltip = ShowReadyTooltip

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
        food = {}, flask = {}, rune = {}, vantus = {}, raidBuff = {}, weapon = {}, durability = {}, unknown = {},
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
        -- [REFACTOR] Optional deficiencies are reported only when explicitly enabled.
        if self.db.reportOptional == true then
            for _, kind in ipairs({ "rune", "vantus" }) do
                local option = kind == "rune" and "checkRune" or "checkVantus"
                if self.db[option] ~= false and record[kind] ~= true then
                    if record[kind] == nil then hasUnknown = true else groups[kind][#groups[kind] + 1] = name end
                end
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
    local order = { "food", "flask", "raidBuff", "weapon", "durability", "unknown", "rune", "vantus" }
    local labels = {
        food = L["RAIDPREP_REPORT_FOOD"], flask = L["RAIDPREP_REPORT_FLASK"],
        rune = L["RAIDPREP_REPORT_RUNE"], raidBuff = L["RAIDPREP_REPORT_RAIDBUFF"],
        vantus = L["RAIDPREP_REPORT_VANTUS"],
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
            vantus = index % 5 ~= 0,
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
            vantusRemaining = 3600,
        }
    end
    self.testRoster = result
    self.roster = result
end

function RaidPreparation:CreateFrame()
    if frame then return frame end
    local styles = RS()
    frame = CreateFrame("Frame", "DDingUIToolkitRaidPreparationFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    -- [STYLE] rounded 10 strip on bg.main, no title bar
    styles.Round(frame, styles.Radius("card", 10), styles.Token("bg", "main"), styles.Token("border", "default"))
    frame:SetScript("OnDragStart", function(self)
        if not SafeBooleanCall(InCombatLockdown) then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        RaidPreparation.db.position = {point=point, relativePoint=relativePoint,
            x=math.floor((SafeNumber(x) or 0) + 0.5), y=math.floor((SafeNumber(y) or 0) + 0.5)}
    end)
    frame:SetScript("OnHide", function(self)
        self.closeElapsed = nil
        self.autoOpened = false
        self:SetAlpha(1)
        local owner = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
        if owner and owner.raidPrepItem then GameTooltip:Hide() end
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

    -- Row 1: ready count | headline + replies over the 10-step gauge | 보고 · 갱신 · X
    frame.count = styles.Text(frame, 22, styles.Color("warn"), "0")
    frame.count:SetPoint("TOPLEFT", 12, -9)
    frame.total = styles.Text(frame, 16, styles.Color(nil), "/0")
    frame.total:SetPoint("BOTTOMLEFT", frame.count, "BOTTOMRIGHT", 1, 1)
    frame.countArea = CreateFrame("Frame", nil, frame)
    frame.countArea:SetPoint("TOPLEFT", 6, -4)
    frame.countArea:SetSize(72, 36)
    frame.countArea:EnableMouse(true)
    frame.countArea.raidPrepItem = false
    frame.countArea:SetScript("OnEnter", function(self) ShowReadyTooltip(self) end)
    frame.countArea:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    frame.closeButton = styles.CreateCloseButton(frame, function() frame:Hide() end)
    frame.closeButton:SetPoint("TOPRIGHT", -8, -10)
    frame.refreshButton = styles.CreateTextButton(frame, L["RAIDPREP_REFRESH_SHORT"], function()
        RaidPreparation.testMode = false
        RaidPreparation:RequestStatuses()
        RaidPreparation:Refresh()
    end)
    frame.refreshButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -4, 0)
    frame.reportButton = styles.CreateTextButton(frame, L["RAIDPREP_REPORT_SHORT"], function()
        RaidPreparation:SendReport(false)
    end)
    frame.reportButton:SetPoint("RIGHT", frame.refreshButton, "LEFT", -4, 0)

    local gaugeLeft = 78
    local gaugeRight = FRAME_WIDTH - 8 - 18 - 4 - frame.refreshButton:GetWidth() - 4 - frame.reportButton:GetWidth() - 8
    local gaugeWidth = math.max(60, gaugeRight - gaugeLeft)
    frame.gauge = CreateFrame("Frame", nil, frame)
    frame.gauge:SetPoint("TOPLEFT", gaugeLeft, -30)
    frame.gauge:SetSize(gaugeWidth, 6)
    frame.gauge.segments = {}
    local segmentWidth = (gaugeWidth - (GAUGE_SEGMENTS - 1) * 2) / GAUGE_SEGMENTS
    for index = 1, GAUGE_SEGMENTS do
        local segment = styles.RoundFill(frame.gauge:CreateTexture(nil, "ARTWORK"), styles.Radius("track", 2))
        segment:SetPoint("TOPLEFT", (index - 1) * (segmentWidth + 2), 0)
        segment:SetSize(segmentWidth, 6)
        frame.gauge.segments[index] = segment
    end
    frame.replies = styles.Text(frame, 12, styles.Color(nil), "")
    frame.replies:SetPoint("BOTTOMRIGHT", frame.gauge, "TOPRIGHT", 0, 3)
    frame.replies:SetJustifyH("RIGHT")
    frame.headline = styles.Text(frame, 12, styles.Token("text", "highlight"), "")
    frame.headline:SetPoint("BOTTOMLEFT", frame.gauge, "TOPLEFT", 0, 3)
    frame.headline:SetPoint("RIGHT", frame.replies, "LEFT", -6, 0)

    -- [STYLE] Five required icons | two optional icons with neutral badges.
    frame.icons = {}
    local size = styles.RAID_ICON
    for index, item in ipairs(ITEMS) do
        local cell = styles.CreateIcon(frame, size)
        cell:SetPoint("TOPLEFT", 12 + (index - 1) * (size + 8) + (item.optional and 9 or 0), -46)
        cell:SetIcon(item.icon)
        cell:EnableMouse(true)
        cell.raidPrepItem = true
        cell.item = item
        cell:SetScript("OnEnter", ShowItemTooltip)
        cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame.icons[index] = cell
    end
    frame.optionalDivider = frame:CreateTexture(nil, "ARTWORK")
    frame.optionalDivider:SetPoint("TOPLEFT", 212, -50)
    frame.optionalDivider:SetSize(1, 24)
    frame.optionalDivider:SetColorTexture(styles.Unpack(styles.Token("border", "default")))
    local hintLeft = 12 + #ITEMS * (size + 8) + 9
    frame.hint = styles.Text(frame, 12, styles.Color(nil), L["RAIDPREP_ICON_HINT"])
    frame.hint:SetPoint("TOPLEFT", hintLeft, -46)
    frame.hint:SetSize(FRAME_WIDTH - hintLeft - 12, size)
    frame.hint:SetJustifyH("RIGHT")
    frame.hint:SetWordWrap(true)

    table.insert(UISpecialFrames, frame:GetName())
    frame:Hide()
    self.frame = frame
    return frame
end

function RaidPreparation:ApplySettings()
    if SafeBooleanCall(InCombatLockdown) then self.settingsPending = true; return end -- [12.0.1]
    self.settingsPending = nil
    self.db = EnsureDB()
    if not self.db then return end
    self:BuildSpellSets()
    if self.roster and not self.testMode then self:CollectRoster() end
    if self.roster then self:ApplyRaidBuffStatus(self.roster) end
    local display = self:CreateFrame()
    display:SetScale(Clamp(self.db.scale, 0.7, 1.4, 1))
    display:ClearAllPoints()
    local position = self.db.position
    display:SetPoint(position.point or "CENTER", UIParent, position.relativePoint or "CENTER",
        Clamp(position.x, -1200, 1200, 0), Clamp(position.y, -800, 800, 10))
    self:Refresh()
    if ns.ReadyCheckAssistant then -- [REFACTOR] Share updated custom spell IDs with the personal panel.
        ns.ReadyCheckAssistant.consumableScanner = nil
        ns.ReadyCheckAssistant:Refresh()
    end
end

function RaidPreparation:ShowWindow(testMode, automatic)
    if SafeBooleanCall(InCombatLockdown) then return end
    self.db = self.db or EnsureDB()
    if not self.db then return end
    self.testMode = testMode == true
    if self.testMode then self:BuildTestRoster() else self:CollectRoster() end
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
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if active then RaidPreparation:RegisterLibDurability() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and RaidPreparation.settingsPending then RaidPreparation:ApplySettings() end
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
