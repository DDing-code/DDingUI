-- DDingUI Toolkit - Raid Groups

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib

local RaidGroups = {}
ns.RaidGroups = RaidGroups

local FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local P = ns.UI and ns.UI.popupColors or {
    background = { 0.10, 0.10, 0.10, 0.985 }, header = { 0.12, 0.12, 0.12, 1 },
    panel = { 0.075, 0.075, 0.08, 0.97 }, panelAlt = { 0.088, 0.088, 0.095, 0.96 },
    control = { 0.06, 0.06, 0.06, 0.94 }, input = { 0.045, 0.045, 0.05, 1 },
    hover = { 0.14, 0.14, 0.15, 0.96 }, selected = { 0.10, 0.14, 0.15, 0.96 },
    border = { 0.30, 0.30, 0.32, 0.82 }, borderSoft = { 0.25, 0.25, 0.25, 0.50 },
    separator = { 0.20, 0.20, 0.20, 0.40 }, accent = { 0.16, 0.58, 0.68, 0.80 },
    accentStrong = { 0.16, 0.68, 0.80, 0.92 }, accentText = { 0.42, 0.76, 0.82, 1 },
    primary = { 0.09, 0.18, 0.20, 0.98 }, primaryHover = { 0.11, 0.23, 0.26, 1 },
    primaryBorder = { 0.16, 0.50, 0.57, 0.84 }, primaryBorderHover = { 0.20, 0.62, 0.70, 0.94 },
    text = { 0.85, 0.85, 0.85, 1 }, textBright = { 1, 1, 1, 1 }, textDim = { 0.60, 0.60, 0.60, 1 },
}
local MAX_GROUPS = 8
local SLOTS_PER_GROUP = 5
local MAX_SLOTS = MAX_GROUPS * SLOTS_PER_GROUP

local active = false
local frame
local launcher
local eventFrame = CreateFrame("Frame")
local selectedSlot
local dragKind
local dragIndex
local dragName
local applyState
local refreshPending = false
local rosterOffset = 0
local savedOffset = 0

local BALANCE_ODD_EVEN = "ODD_EVEN"
local BALANCE_CONTIGUOUS = "CONTIGUOUS"
local POSITION_MELEE = "MELEE"
local POSITION_RANGED = "RANGED"
local PLACEMENT_ORDER = { TANK = 1, MELEE = 2, RANGED = 3, HEALER = 4 }

local DAMAGE_SPEC_POSITION = {
    [62] = POSITION_RANGED, [63] = POSITION_RANGED, [64] = POSITION_RANGED,
    [70] = POSITION_MELEE, [71] = POSITION_MELEE, [72] = POSITION_MELEE,
    [102] = POSITION_RANGED, [103] = POSITION_MELEE,
    [251] = POSITION_MELEE, [252] = POSITION_MELEE,
    [253] = POSITION_RANGED, [254] = POSITION_RANGED, [255] = POSITION_MELEE,
    [258] = POSITION_RANGED,
    [259] = POSITION_MELEE, [260] = POSITION_MELEE, [261] = POSITION_MELEE,
    [262] = POSITION_RANGED, [263] = POSITION_MELEE,
    [265] = POSITION_RANGED, [266] = POSITION_RANGED, [267] = POSITION_RANGED,
    [269] = POSITION_MELEE,
    [577] = POSITION_MELEE,
    [1467] = POSITION_RANGED, [1473] = POSITION_RANGED,
    [1480] = POSITION_RANGED,
}

local MELEE_DAMAGE_CLASSES = {
    WARRIOR = true,
    PALADIN = true,
    ROGUE = true,
    DEATHKNIGHT = true,
    MONK = true,
    DEMONHUNTER = true,
}

local groupSpecCache = {}
local libSpecRegistered = false

local function IsSecret(value)
    return (ns.IsSecretValue and ns.IsSecretValue(value))
        or (issecretvalue and issecretvalue(value))
        or false
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

local function NormalizePosition(position)
    position = SafeString(position)
    if position == POSITION_MELEE then return POSITION_MELEE end
    if position == POSITION_RANGED or position == "RANGE" then return POSITION_RANGED end
    return nil
end

local function CacheGroupSpec(name, specID, position)
    local key = NormalizeName(name)
    if not key then return end
    local data = {
        specID = SafeNumber(specID),
        position = NormalizePosition(position),
    }
    groupSpecCache[key] = data
    local shortKey = NormalizeName(ShortName(name))
    if shortKey and shortKey ~= key then groupSpecCache[shortKey] = data end
end

local function GetCachedGroupSpec(name)
    return groupSpecCache[NormalizeName(name)] or groupSpecCache[NormalizeName(ShortName(name))]
end

local function GetUnitSpecID(unit)
    local getter = GetInspectSpecialization
        or (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization)
    if type(getter) ~= "function" then return nil end
    local ok, specID = pcall(getter, unit)
    specID = ok and SafeNumber(specID) or nil
    if not specID or specID <= 0 then return nil end
    return math.floor(specID)
end

local function GetDamagePosition(record)
    if not record then return POSITION_RANGED end
    local position = NormalizePosition(record.damagePosition)
        or DAMAGE_SPEC_POSITION[SafeNumber(record.specID)]
    if position then return position end
    return MELEE_DAMAGE_CLASSES[SafeString(record.classToken)] and POSITION_MELEE or POSITION_RANGED
end

local function GetPlacementCategory(record)
    if record and record.role == "TANK" then return "TANK" end
    if record and record.role == "HEALER" then return "HEALER" end
    return GetDamagePosition(record)
end

local function GetClassKey(record)
    return (record and SafeString(record.classToken)) or "UNKNOWN"
end

local function RegisterSpecializationTracking()
    if libSpecRegistered or not LibStub then return end
    local libSpec = LibStub("LibSpecialization", true)
    if not libSpec or type(libSpec.RegisterGroup) ~= "function" then return end
    local ok = pcall(libSpec.RegisterGroup, RaidGroups, function(specID, _, position, sender)
        CacheGroupSpec(sender, specID, position)
    end)
    libSpecRegistered = ok == true
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
    if type(profile.RaidGroups) ~= "table" then
        local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.RaidGroups
        profile.RaidGroups = CopyTable(defaults)
    end
    local db = profile.RaidGroups
    if type(db.currentLayout) ~= "table" then db.currentLayout = {} end
    if type(db.savedLayouts) ~= "table" then db.savedLayouts = {} end
    if type(db.position) ~= "table" then
        db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 20 }
    end
    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.RaidGroups or {}
    if db.balancePattern ~= BALANCE_ODD_EVEN and db.balancePattern ~= BALANCE_CONTIGUOUS then
        db.balancePattern = defaults.balancePattern == BALANCE_CONTIGUOUS and BALANCE_CONTIGUOUS or BALANCE_ODD_EVEN
    end
    if db.showLauncher == nil then db.showLauncher = defaults.showLauncher ~= false end
    if db.launcherRaidOnly == nil then db.launcherRaidOnly = defaults.launcherRaidOnly ~= false end
    if type(db.launcherPosition) ~= "table" then
        db.launcherPosition = CopyTable(defaults.launcherPosition)
        if next(db.launcherPosition) == nil then
            db.launcherPosition = { point = "LEFT", relativePoint = "LEFT", x = 12, y = 80 }
        end
    end
    return db
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
    button:SetSize(width or 112, 27)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.label = AddText(button, 11, P.text, label)
    button.label:SetPoint("LEFT", 7, 0)
    button.label:SetPoint("RIGHT", -7, 0)
    button.label:SetJustifyH("CENTER")
    button.label:SetWordWrap(false)

    local function ApplyVisual(state)
        if primary then
            if state == "hover" then
                SetBackdrop(button, P.primaryHover, P.primaryBorderHover)
            else
                SetBackdrop(button, P.primary, P.primaryBorder)
            end
            button.label:SetTextColor(unpack(P.textBright))
        else
            if state == "hover" then
                SetBackdrop(button, P.hover, P.border)
            else
                SetBackdrop(button, P.control, P.borderSoft)
            end
            button.label:SetTextColor(unpack(P.text))
        end
    end

    button:SetScript("OnEnter", function() ApplyVisual("hover") end)
    button:SetScript("OnLeave", function() ApplyVisual("normal") end)
    ApplyVisual("normal")
    return button
end

local function CreateInput(parent, width)
    local input = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    input:SetSize(width, 25)
    input:SetAutoFocus(false)
    input:SetFont(FONT, 11, "")
    input:SetTextColor(unpack(P.textBright))
    input:SetTextInsets(7, 7, 0, 0)
    SetBackdrop(input, P.input, P.borderSoft)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(P.accentStrong)) end)
    input:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(P.borderSoft)) end)
    return input
end

local ROLE_ATLAS = {
    TANK = "groupfinder-icon-role-large-tank",
    HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}

local function SetRoleTexture(texture, role)
    role = SafeString(role)
    local atlas = role and ROLE_ATLAS[role]
    if atlas and texture.SetAtlas then
        local ok = pcall(texture.SetAtlas, texture, atlas, true)
        if ok then
            texture:SetShown(true)
            return
        end
    end
    texture:SetTexture(nil)
    texture:Hide()
end

local function GetClassColor(classToken)
    classToken = SafeString(classToken)
    local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if not color then return 0.82, 0.85, 0.90 end
    return color.r or 0.82, color.g or 0.85, color.b or 0.90
end

local function GetReadableClassColor(classToken)
    local r, g, b = GetClassColor(classToken)
    local lift = 0.14
    return r + ((1 - r) * lift), g + ((1 - g) * lift), b + ((1 - b) * lift), r, g, b
end

function RaidGroups:SetStatus(message, kind)
    if not frame then return end
    frame.status:SetText(SafeString(message) or "")
    if kind == "error" then
        frame.status:SetTextColor(1.00, 0.34, 0.30, 1)
    elseif kind == "success" then
        frame.status:SetTextColor(0.32, 1.00, 0.56, 1)
    elseif kind == "working" then
        frame.status:SetTextColor(0.25, 0.82, 1.00, 1)
    else
        frame.status:SetTextColor(0.60, 0.66, 0.73, 1)
    end
end

function RaidGroups:CollectRoster()
    local roster = {}
    local byName = {}
    if not SafeBooleanCall(IsInRaid) then
        self.roster = roster
        self.rosterByName = byName
        return roster
    end

    local count = SafeNumber(GetNumGroupMembers and GetNumGroupMembers()) or 0
    count = math.min(MAX_SLOTS, math.max(0, math.floor(count)))
    for index = 1, count do
        local ok, name, rank, subgroup, level, className, classToken, zone, online, dead,
            legacyRole, isMasterLooter, combatRole
        ok, name, rank, subgroup, level, className, classToken, zone, online, dead,
            legacyRole, isMasterLooter, combatRole = pcall(GetRaidRosterInfo, index)
        name = ok and SafeString(name) or nil
        subgroup = ok and SafeNumber(subgroup) or nil
        classToken = ok and SafeString(classToken) or nil
        if name and subgroup and subgroup >= 1 and subgroup <= MAX_GROUPS then
            local unit = "raid" .. index
            local unitRole
            if UnitGroupRolesAssigned then
                local roleOK, value = pcall(UnitGroupRolesAssigned, unit)
                unitRole = roleOK and SafeString(value) or nil
            end
            if not unitRole or unitRole == "NONE" then unitRole = SafeString(combatRole) end
            if unitRole ~= "TANK" and unitRole ~= "HEALER" and unitRole ~= "DAMAGER" then
                unitRole = "DAMAGER"
            end
            local cachedSpec = GetCachedGroupSpec(name)
            local specID = cachedSpec and cachedSpec.specID or GetUnitSpecID(unit)
            local damagePosition = cachedSpec and cachedSpec.position or DAMAGE_SPEC_POSITION[specID]
            if specID and not cachedSpec then CacheGroupSpec(name, specID, damagePosition) end
            local record = {
                name = name,
                key = NormalizeName(name),
                index = index,
                subgroup = math.floor(subgroup),
                rank = SafeNumber(rank) or 0,
                classToken = classToken,
                role = unitRole,
                specID = specID,
                damagePosition = damagePosition,
                online = SafeBoolean(online),
                dead = SafeBoolean(dead),
            }
            roster[#roster + 1] = record
            if record.key then byName[record.key] = record end
        end
    end

    table.sort(roster, function(a, b)
        if a.subgroup ~= b.subgroup then return a.subgroup < b.subgroup end
        return a.index < b.index
    end)
    self.roster = roster
    self.rosterByName = byName
    return roster
end

function RaidGroups:WriteRosterToLayout(roster)
    local db = self.db or EnsureDB()
    if not db then return false end
    for index = 1, MAX_SLOTS do db.currentLayout[index] = nil end
    local groupCounts = {}
    for _, record in ipairs(roster or {}) do
        local group = SafeNumber(record.subgroup)
        if group and group >= 1 and group <= MAX_GROUPS then
            group = math.floor(group)
            groupCounts[group] = (groupCounts[group] or 0) + 1
            local slot = ((group - 1) * SLOTS_PER_GROUP) + groupCounts[group]
            if slot <= MAX_SLOTS then db.currentLayout[slot] = record.name end
        end
    end
    return true
end

function RaidGroups:LoadCurrentRoster()
    local db = self.db or EnsureDB()
    if not db then return end
    local roster = self:CollectRoster()
    db.selectedLayoutName = ""
    if frame then frame.layoutName:SetText("") end
    self:WriteRosterToLayout(roster)
    selectedSlot = nil
    self.testMode = false
    self.preTestLayout = nil
    self.preTestLayoutName = nil
    self:Refresh()
    if #roster > 0 then
        self:SetStatus(string.format(L["RAIDGROUPS_STATUS_IMPORTED"], #roster), "success")
    else
        self:SetStatus(L["RAIDGROUPS_STATUS_NOT_IN_RAID"], "error")
    end
end

function RaidGroups:BuildTestRoster()
    local classes = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN", "HUNTER", "SHAMAN", "WARLOCK", "MONK", "DEMONHUNTER", "EVOKER" }
    local roster = {}
    local byName = {}
    for index = 1, 20 do
        local role = index <= 4 and "TANK" or (index <= 8 and "HEALER" or "DAMAGER")
        local name = string.format("%s %02d", L["RAIDGROUPS_TEST_PLAYER"], index)
        local record = {
            name = name,
            key = NormalizeName(name),
            index = index,
            subgroup = math.floor((index - 1) / 5) + 1,
            rank = index == 1 and 2 or 0,
            classToken = classes[((index - 1) % #classes) + 1],
            role = role,
            online = true,
            dead = false,
        }
        roster[#roster + 1] = record
        byName[record.key] = record
    end
    self.roster = roster
    self.rosterByName = byName
    local db = self.db or EnsureDB()
    for index = 1, MAX_SLOTS do db.currentLayout[index] = nil end
    for index, record in ipairs(roster) do db.currentLayout[index] = record.name end
end

function RaidGroups:FindLayoutSlot(name)
    local key = NormalizeName(name)
    if not key or not self.db then return nil end
    for index = 1, MAX_SLOTS do
        if NormalizeName(self.db.currentLayout[index]) == key then return index end
    end
    return nil
end

function RaidGroups:PlaceName(name, targetSlot)
    name = SafeString(name)
    targetSlot = SafeNumber(targetSlot)
    if not name or not targetSlot or targetSlot < 1 or targetSlot > MAX_SLOTS then return end
    targetSlot = math.floor(targetSlot)
    local layout = self.db.currentLayout
    local sourceSlot = self:FindLayoutSlot(name)
    if sourceSlot == targetSlot then
        selectedSlot = nil
        self:Refresh()
        return
    end
    if sourceSlot then
        layout[sourceSlot], layout[targetSlot] = layout[targetSlot], layout[sourceSlot]
    else
        layout[targetSlot] = name
    end
    selectedSlot = nil
    self:Refresh()
end

function RaidGroups:HandleSlotClick(index, button)
    if button == "RightButton" then
        self.db.currentLayout[index] = nil
        selectedSlot = nil
        self:Refresh()
        return
    end
    if selectedSlot then
        if selectedSlot == index then
            selectedSlot = nil
        else
            local layout = self.db.currentLayout
            layout[selectedSlot], layout[index] = layout[index], layout[selectedSlot]
            selectedSlot = nil
        end
    else
        selectedSlot = index
    end
    self:Refresh()
end

function RaidGroups:GetUnassignedRoster()
    local assigned = {}
    for index = 1, MAX_SLOTS do
        local key = NormalizeName(self.db.currentLayout[index])
        if key then assigned[key] = true end
    end
    local result = {}
    for _, record in ipairs(self.roster or {}) do
        if record.key and not assigned[record.key] then result[#result + 1] = record end
    end
    table.sort(result, function(a, b)
        local ar = PLACEMENT_ORDER[GetPlacementCategory(a)] or 5
        local br = PLACEMENT_ORDER[GetPlacementCategory(b)] or 5
        if ar ~= br then return ar < br end
        return ShortName(a.name) < ShortName(b.name)
    end)
    return result
end

function RaidGroups:GetBalanceGroupOrder(groupCount)
    groupCount = math.max(1, math.min(MAX_GROUPS, math.floor(SafeNumber(groupCount) or 1)))
    local firstSide, secondSide = {}, {}
    if self.db and self.db.balancePattern == BALANCE_CONTIGUOUS then
        local split = math.ceil(groupCount / 2)
        for group = 1, split do firstSide[#firstSide + 1] = group end
        for group = split + 1, groupCount do secondSide[#secondSide + 1] = group end
    else
        for group = 1, groupCount do
            local side = group % 2 == 1 and firstSide or secondSide
            side[#side + 1] = group
        end
    end

    local order = {}
    for index = 1, math.max(#firstSide, #secondSide) do
        if firstSide[index] then order[#order + 1] = firstSide[index] end
        if secondSide[index] then order[#order + 1] = secondSide[index] end
    end
    return order, firstSide, secondSide
end

local function BuildGroupTiers(firstSide, secondSide, fromBack)
    local tiers = {}
    local maximum = math.max(#firstSide, #secondSide)
    for depth = 0, maximum - 1 do
        local tier = {}
        local firstIndex = fromBack and (#firstSide - depth) or (depth + 1)
        local secondIndex = fromBack and (#secondSide - depth) or (depth + 1)
        local firstGroup = firstSide[firstIndex]
        local secondGroup = secondSide[secondIndex]
        if firstGroup then tier[#tier + 1] = firstGroup end
        if secondGroup and secondGroup ~= firstGroup then tier[#tier + 1] = secondGroup end
        if #tier > 0 then tiers[#tiers + 1] = tier end
    end
    return tiers
end

function RaidGroups:SetBalancePattern(pattern)
    if pattern ~= BALANCE_CONTIGUOUS then pattern = BALANCE_ODD_EVEN end
    self.db.balancePattern = pattern
    self:UpdateBalancePatternButton()
end

function RaidGroups:UpdateBalancePatternButton()
    if not frame or not frame.patternButton or not self.db then return end
    if self.db.balancePattern == BALANCE_CONTIGUOUS then
        frame.patternButton.label:SetText(L["RAIDGROUPS_PATTERN_CONTIGUOUS_SHORT"])
    else
        frame.patternButton.label:SetText(L["RAIDGROUPS_PATTERN_ODD_EVEN_SHORT"])
    end
end

function RaidGroups:AutoBalance()
    local roster = self.testMode and (self.roster or {}) or self:CollectRoster()
    if #roster == 0 then
        self:SetStatus(L["RAIDGROUPS_STATUS_NOT_IN_RAID"], "error")
        return
    end

    local groupCount = math.max(1, math.min(MAX_GROUPS, math.ceil(#roster / SLOTS_PER_GROUP)))
    local _, firstSide, secondSide = self:GetBalanceGroupOrder(groupCount)
    local frontGroupTiers = BuildGroupTiers(firstSide, secondSide, false)
    local backGroupTiers = BuildGroupTiers(firstSide, secondSide, true)
    local groups = {}
    local groupSide = {}
    local sideClassCounts = { {}, {} }
    local sideMembers = { 0, 0 }
    for _, group in ipairs(firstSide) do groupSide[group] = 1 end
    for _, group in ipairs(secondSide) do groupSide[group] = 2 end
    for group = 1, groupCount do
        groups[group] = {
            members = {},
            roles = { TANK = 0, HEALER = 0, MELEE = 0, RANGED = 0 },
            classes = {},
        }
    end

    local buckets = { TANK = {}, MELEE = {}, RANGED = {}, HEALER = {} }
    for _, record in ipairs(roster) do
        local category = GetPlacementCategory(record)
        if record.role ~= "TANK" and record.role ~= "HEALER" then record.damagePosition = category end
        buckets[category][#buckets[category] + 1] = record
    end

    for _, category in ipairs({ "TANK", "HEALER", "MELEE", "RANGED" }) do
        table.sort(buckets[category], function(a, b)
            local aClass = GetClassKey(a)
            local bClass = GetClassKey(b)
            if aClass ~= bClass then return aClass < bClass end
            local ai = SafeNumber(a.index) or MAX_SLOTS + 1
            local bi = SafeNumber(b.index) or MAX_SLOTS + 1
            if ai ~= bi then return ai < bi end
            return ShortName(a.name) < ShortName(b.name)
        end)
    end

    local function AddToGroup(record, category, group)
        local target = groups[group]
        local side = groupSide[group] or 1
        local classKey = GetClassKey(record)
        target.members[#target.members + 1] = record
        target.roles[category] = target.roles[category] + 1
        target.classes[classKey] = (target.classes[classKey] or 0) + 1
        sideClassCounts[side][classKey] = (sideClassCounts[side][classKey] or 0) + 1
        sideMembers[side] = sideMembers[side] + 1
    end

    local function DistributeBucket(category, tiers)
        for _, record in ipairs(buckets[category]) do
            local selected
            local classKey = GetClassKey(record)
            for _, tier in ipairs(tiers) do
                for _, group in ipairs(tier) do
                    local target = groups[group]
                    local current = selected and groups[selected]
                    local targetSide = groupSide[group] or 1
                    local currentSide = selected and (groupSide[selected] or 1)
                    local targetClassCount = sideClassCounts[targetSide][classKey] or 0
                    local currentClassCount = currentSide and (sideClassCounts[currentSide][classKey] or 0)
                    if #target.members < SLOTS_PER_GROUP
                        and (not current
                            or targetClassCount < currentClassCount
                            or (targetClassCount == currentClassCount
                                and (#target.members < #current.members
                                    or (#target.members == #current.members
                                        and (target.roles[category] < current.roles[category]
                                            or (target.roles[category] == current.roles[category]
                                                and sideMembers[targetSide] < sideMembers[currentSide])))))) then
                        selected = group
                    end
                end
                if selected then break end
            end
            if selected then AddToGroup(record, category, selected) end
        end
    end

    DistributeBucket("TANK", frontGroupTiers)
    DistributeBucket("HEALER", backGroupTiers)
    DistributeBucket("MELEE", frontGroupTiers)
    DistributeBucket("RANGED", backGroupTiers)

    for index = 1, MAX_SLOTS do self.db.currentLayout[index] = nil end
    for group = 1, groupCount do
        table.sort(groups[group].members, function(a, b)
            local ar = PLACEMENT_ORDER[GetPlacementCategory(a)] or 5
            local br = PLACEMENT_ORDER[GetPlacementCategory(b)] or 5
            if ar ~= br then return ar < br end
            local ai = SafeNumber(a.index) or MAX_SLOTS + 1
            local bi = SafeNumber(b.index) or MAX_SLOTS + 1
            if ai ~= bi then return ai < bi end
            return ShortName(a.name) < ShortName(b.name)
        end)
        for slot, record in ipairs(groups[group].members) do
            self.db.currentLayout[((group - 1) * SLOTS_PER_GROUP) + slot] = record.name
        end
    end
    selectedSlot = nil
    self:Refresh()
    local patternLabel = self.db.balancePattern == BALANCE_CONTIGUOUS
        and L["RAIDGROUPS_PATTERN_CONTIGUOUS"] or L["RAIDGROUPS_PATTERN_ODD_EVEN"]
    self:SetStatus(string.format(L["RAIDGROUPS_STATUS_BALANCED_PATTERN"], patternLabel), "success")
end

function RaidGroups:ClearLayout()
    for index = 1, MAX_SLOTS do self.db.currentLayout[index] = nil end
    selectedSlot = nil
    self:Refresh()
    self:SetStatus(L["RAIDGROUPS_STATUS_CLEARED"], "normal")
end

function RaidGroups:SaveLayout()
    local name = frame and Trim(frame.layoutName:GetText()) or ""
    if name == "" then
        self:SetStatus(L["RAIDGROUPS_STATUS_NAME_REQUIRED"], "error")
        return
    end
    name = name:sub(1, 32)
    local found
    for _, saved in ipairs(self.db.savedLayouts) do
        if NormalizeName(saved.name) == NormalizeName(name) then
            saved.name = name
            saved.slots = CopyTable(self.db.currentLayout)
            saved.updatedAt = time and time() or 0
            found = true
            break
        end
    end
    if not found then
        self.db.savedLayouts[#self.db.savedLayouts + 1] = {
            name = name,
            slots = CopyTable(self.db.currentLayout),
            updatedAt = time and time() or 0,
        }
    end
    self.db.selectedLayoutName = name
    frame.layoutName:SetText(name)
    self:RefreshSavedLayouts()
    self:SetStatus(string.format(L["RAIDGROUPS_STATUS_SAVED"], name), "success")
end

function RaidGroups:LoadSavedLayout(index)
    local saved = self.db.savedLayouts[index]
    if type(saved) ~= "table" or type(saved.slots) ~= "table" then return end
    self.db.currentLayout = CopyTable(saved.slots)
    self.db.selectedLayoutName = SafeString(saved.name) or ""
    frame.layoutName:SetText(self.db.selectedLayoutName)
    selectedSlot = nil
    self:Refresh()
    self:SetStatus(string.format(L["RAIDGROUPS_STATUS_LOADED"], self.db.selectedLayoutName), "success")
end

function RaidGroups:DeleteSavedLayout(index)
    local saved = self.db.savedLayouts[index]
    if not saved then return end
    local name = SafeString(saved.name) or ""
    table.remove(self.db.savedLayouts, index)
    if self.db.selectedLayoutName == name then
        self.db.selectedLayoutName = ""
        if frame then frame.layoutName:SetText("") end
    end
    self:RefreshSavedLayouts()
    self:SetStatus(string.format(L["RAIDGROUPS_STATUS_DELETED"], name), "normal")
end

function RaidGroups:NormalizeFixedRosterPosition(roster)
    local fixedRecord
    for _, record in ipairs(roster or {}) do
        if record.index == 1 then
            fixedRecord = record
            break
        end
    end
    if not fixedRecord then return false end
    local slot = self:FindLayoutSlot(fixedRecord.name)
    if not slot then return false end
    local firstSlot = (math.floor((slot - 1) / SLOTS_PER_GROUP) * SLOTS_PER_GROUP) + 1
    if slot == firstSlot then return false end
    local layout = self.db.currentLayout
    for index = slot, firstSlot + 1, -1 do layout[index] = layout[index - 1] end
    layout[firstSlot] = fixedRecord.name
    return true
end

function RaidGroups:ValidateApply()
    if self.testMode then return nil, L["RAIDGROUPS_STATUS_TEST"] end
    if SafeBooleanCall(InCombatLockdown) then return nil, L["RAIDGROUPS_ERROR_COMBAT"] end
    if not SafeBooleanCall(IsInRaid) then return nil, L["RAIDGROUPS_STATUS_NOT_IN_RAID"] end
    if not (SafeBooleanCall(UnitIsGroupLeader, "player") or SafeBooleanCall(UnitIsGroupAssistant, "player")) then
        return nil, L["RAIDGROUPS_ERROR_PERMISSION"]
    end

    local roster = self:CollectRoster()
    local normalized = self:NormalizeFixedRosterPosition(roster)
    local plan = { groups = {}, positions = {}, expectedCount = #roster }
    local counts = {}
    local assigned = 0
    for index = 1, MAX_SLOTS do
        local name = SafeString(self.db.currentLayout[index])
        if name then
            local key = NormalizeName(name)
            if not key or plan.groups[key] then return nil, L["RAIDGROUPS_ERROR_DUPLICATE"] end
            if not self.rosterByName[key] then
                return nil, string.format(L["RAIDGROUPS_ERROR_NOT_IN_RAID"], ShortName(name))
            end
            local group = math.floor((index - 1) / SLOTS_PER_GROUP) + 1
            counts[group] = (counts[group] or 0) + 1
            if counts[group] > SLOTS_PER_GROUP then return nil, L["RAIDGROUPS_ERROR_GROUP_FULL"] end
            plan.groups[key] = group
            plan.positions[key] = counts[group]
            assigned = assigned + 1
        end
    end
    if assigned ~= #roster then
        return nil, string.format(L["RAIDGROUPS_ERROR_INCOMPLETE"], assigned, #roster)
    end
    return plan, nil, normalized
end

function RaidGroups:FinishApply(success, message)
    applyState = nil
    self:SetStatus(message, success and "success" or "error")
    self:CollectRoster()
    self:Refresh()
    if success and self.db.autoCloseAfterApply and frame then frame:Hide() end
end

function RaidGroups:ScheduleApply(delay)
    if not applyState or applyState.scheduled then return end
    local serial = applyState.serial
    applyState.scheduled = true
    C_Timer.After(delay or 0.35, function()
        if not applyState or applyState.serial ~= serial then return end
        applyState.scheduled = false
        RaidGroups:ProcessApply()
    end)
end

function RaidGroups:ProcessApply()
    local state = applyState
    if not state then return end
    if SafeBooleanCall(InCombatLockdown) then
        self:FinishApply(false, L["RAIDGROUPS_ERROR_COMBAT"])
        return
    end
    state.attempts = state.attempts + 1
    if state.attempts > 120 then
        self:FinishApply(false, L["RAIDGROUPS_ERROR_TIMEOUT"])
        return
    end

    local roster = self:CollectRoster()
    if state.orderSwap then
        if #roster ~= state.expectedCount then
            self:FinishApply(false, L["RAIDGROUPS_ERROR_ROSTER_CHANGED"])
            return
        end
        local orderSwap = state.orderSwap
        local pair = orderSwap[orderSwap.step]
        local leftIndex = pair and SafeNumber(UnitInRaid and UnitInRaid(pair[1]))
        local rightIndex = pair and SafeNumber(UnitInRaid and UnitInRaid(pair[2]))
        local ok = leftIndex and rightIndex and SwapRaidSubgroup
            and pcall(SwapRaidSubgroup, leftIndex, rightIndex)
        if not ok then
            self:FinishApply(false, L["RAIDGROUPS_ERROR_APPLY_FAILED"])
            return
        end
        orderSwap.step = orderSwap.step + 1
        if not orderSwap[orderSwap.step] then state.orderSwap = nil end
        self:SetStatus(string.format(L["RAIDGROUPS_STATUS_ORDERING"], orderSwap.mismatchCount), "working")
        self:ScheduleApply(0.35)
        return
    end

    local groupCounts = {}
    local groupPositions = {}
    local currentPositions = {}
    local recordsByGroupPosition = {}
    local mismatches = {}
    local matched = 0
    for _, record in ipairs(roster) do
        groupCounts[record.subgroup] = (groupCounts[record.subgroup] or 0) + 1
        groupPositions[record.subgroup] = (groupPositions[record.subgroup] or 0) + 1
        local currentPosition = groupPositions[record.subgroup]
        if record.key then currentPositions[record.key] = currentPosition end
        recordsByGroupPosition[record.subgroup] = recordsByGroupPosition[record.subgroup] or {}
        recordsByGroupPosition[record.subgroup][currentPosition] = record
        local target = record.key and state.desired[record.key]
        if target then matched = matched + 1 end
        if target and target ~= record.subgroup then
            record.targetGroup = target
            mismatches[#mismatches + 1] = record
        end
    end
    if #roster ~= state.expectedCount or matched ~= state.expectedCount then
        self:FinishApply(false, L["RAIDGROUPS_ERROR_ROSTER_CHANGED"])
        return
    end
    if #mismatches == 0 then
        local positionMismatchCount = 0
        local candidate
        local swapTarget
        for _, record in ipairs(roster) do
            local desiredPosition = record.key and state.desiredPositions[record.key]
            local currentPosition = record.key and currentPositions[record.key]
            if desiredPosition and currentPosition and desiredPosition ~= currentPosition then
                positionMismatchCount = positionMismatchCount + 1
                if not candidate and record.index ~= 1 then
                    local occupant = recordsByGroupPosition[record.subgroup]
                        and recordsByGroupPosition[record.subgroup][desiredPosition]
                    if occupant and occupant.index ~= 1 then
                        candidate = record
                        swapTarget = occupant
                    end
                end
            end
        end
        if positionMismatchCount == 0 then
            self:FinishApply(true, L["RAIDGROUPS_STATUS_APPLIED"])
            return
        end

        local bridge
        if candidate then
            for _, record in ipairs(roster) do
                if record.index ~= 1 and record.subgroup ~= candidate.subgroup then
                    bridge = record
                    break
                end
            end
        end
        if not candidate or not swapTarget or not bridge or not SwapRaidSubgroup then
            self:FinishApply(false, L["RAIDGROUPS_ERROR_APPLY_FAILED"])
            return
        end

        state.orderSwap = {
            step = 1,
            mismatchCount = positionMismatchCount,
            { candidate.name, bridge.name },
            { candidate.name, swapTarget.name },
            { swapTarget.name, bridge.name },
        }
        self:SetStatus(string.format(L["RAIDGROUPS_STATUS_ORDERING"], positionMismatchCount), "working")
        self:ScheduleApply(0)
        return
    end

    local candidate
    for _, record in ipairs(mismatches) do
        if (groupCounts[record.targetGroup] or 0) < SLOTS_PER_GROUP then
            candidate = record
            break
        end
    end

    local ok
    if candidate and SetRaidSubgroup then
        ok = pcall(SetRaidSubgroup, candidate.index, candidate.targetGroup)
    else
        candidate = mismatches[1]
        local swapTarget
        local fallback
        for _, occupant in ipairs(roster) do
            if occupant.subgroup == candidate.targetGroup then
                local occupantTarget = occupant.key and state.desired[occupant.key]
                if occupantTarget and occupantTarget ~= occupant.subgroup then
                    fallback = fallback or occupant
                    if occupantTarget == candidate.subgroup then
                        swapTarget = occupant
                        break
                    end
                end
            end
        end
        swapTarget = swapTarget or fallback
        if swapTarget and SwapRaidSubgroup then
            ok = pcall(SwapRaidSubgroup, candidate.index, swapTarget.index)
        end
    end

    if not ok then
        self:FinishApply(false, L["RAIDGROUPS_ERROR_APPLY_FAILED"])
        return
    end
    self:SetStatus(string.format(L["RAIDGROUPS_STATUS_APPLYING"], #mismatches), "working")
    self:ScheduleApply(0.45)
end

function RaidGroups:StartApply()
    local plan, errorMessage, normalized = self:ValidateApply()
    if not plan then
        self:SetStatus(errorMessage, "error")
        return
    end
    if normalized then self:Refresh() end
    applyState = {
        desired = plan.groups,
        desiredPositions = plan.positions,
        expectedCount = plan.expectedCount,
        attempts = 0,
        serial = (GetTime and GetTime() or 0) .. ":" .. tostring(math.random(1000, 9999)),
    }
    self:SetStatus(L["RAIDGROUPS_STATUS_APPLY_START"], "working")
    self:ProcessApply()
end

function RaidGroups:RefreshSavedLayouts()
    if not frame then return end
    local maxOffset = math.max(0, #self.db.savedLayouts - #frame.savedRows)
    savedOffset = math.max(0, math.min(savedOffset, maxOffset))
    frame.savedTitle:SetText(string.format("%s  %d", L["RAIDGROUPS_SAVED_LAYOUTS"], #self.db.savedLayouts))
    local hasScroll = #self.db.savedLayouts > #frame.savedRows
    frame.savedScrollTrack:SetShown(hasScroll)
    frame.savedScrollThumb:SetShown(hasScroll)
    if hasScroll then
        local trackHeight = 75
        local thumbHeight = math.max(20, math.floor(trackHeight * (#frame.savedRows / #self.db.savedLayouts) + 0.5))
        local travel = trackHeight - thumbHeight
        local ratio = maxOffset > 0 and (savedOffset / maxOffset) or 0
        frame.savedScrollThumb:SetHeight(thumbHeight)
        frame.savedScrollThumb:ClearAllPoints()
        frame.savedScrollThumb:SetPoint("TOP", frame.savedScrollTrack, "TOP", 0, -math.floor(travel * ratio + 0.5))
    end
    for rowIndex, row in ipairs(frame.savedRows) do
        local savedIndex = savedOffset + rowIndex
        local saved = self.db.savedLayouts[savedIndex]
        if saved then
            row.savedIndex = savedIndex
            row.label:SetText(SafeString(saved.name) or L["RAIDGROUPS_UNNAMED_LAYOUT"])
            row:Show()
        else
            row.savedIndex = nil
            row:Hide()
        end
    end
end

function RaidGroups:Refresh()
    if not frame or not self.db then return end
    local layout = self.db.currentLayout
    local assigned = {}
    for index, slot in ipairs(frame.slots) do
        local name = SafeString(layout[index])
        local record = name and self.rosterByName and self.rosterByName[NormalizeName(name)]
        slot.playerName = name
        if name then
            local textR, textG, textB, r, g, b = GetReadableClassColor(record and record.classToken)
            local useClassColor = self.db.colorNames ~= false
            if index == selectedSlot then
                slot:SetBackdropColor(unpack(P.selected))
            elseif useClassColor then
                slot:SetBackdropColor(0.05 + (r * 0.025), 0.05 + (g * 0.025), 0.055 + (b * 0.025), 0.96)
            else
                slot:SetBackdropColor(unpack(P.control))
            end
            slot.name:SetText(ShortName(name))
            if useClassColor then
                slot.name:SetTextColor(textR, textG, textB, 1)
                slot:SetBackdropBorderColor(r * 0.58, g * 0.58, b * 0.58, 0.82)
                slot.classAccent:SetColorTexture(r, g, b, 0.78)
                slot.classAccent:Show()
            else
                slot.name:SetTextColor(unpack(P.text))
                slot:SetBackdropBorderColor(unpack(P.borderSoft))
                slot.classAccent:Hide()
            end
            SetRoleTexture(slot.roleIcon, self.db.showRoleIcons ~= false and record and record.role or nil)
            local key = NormalizeName(name)
            if key then assigned[key] = true end
        else
            slot:SetBackdropColor(unpack(index == selectedSlot and P.selected or P.control))
            slot.name:SetText(L["RAIDGROUPS_EMPTY_SLOT"])
            slot.name:SetTextColor(0.32, 0.36, 0.42, 1)
            slot:SetBackdropBorderColor(unpack(P.borderSoft))
            slot.classAccent:Hide()
            SetRoleTexture(slot.roleIcon, nil)
        end
    end

    for group = 1, MAX_GROUPS do
        local count = 0
        for slot = 1, SLOTS_PER_GROUP do
            if layout[((group - 1) * SLOTS_PER_GROUP) + slot] then count = count + 1 end
        end
        frame.groupFrames[group].count:SetText(string.format("%d/%d", count, SLOTS_PER_GROUP))
    end

    local unassigned = self:GetUnassignedRoster()
    local maxRosterOffset = math.max(0, #unassigned - #frame.rosterRows)
    rosterOffset = math.max(0, math.min(rosterOffset, maxRosterOffset))
    local hasRosterScroll = #unassigned > #frame.rosterRows
    frame.rosterScrollTrack:SetShown(hasRosterScroll)
    frame.rosterScrollThumb:SetShown(hasRosterScroll)
    if hasRosterScroll then
        local trackHeight = #frame.rosterRows * 22
        local thumbHeight = math.max(24, math.floor(trackHeight * (#frame.rosterRows / #unassigned) + 0.5))
        local travel = trackHeight - thumbHeight
        local ratio = maxRosterOffset > 0 and (rosterOffset / maxRosterOffset) or 0
        frame.rosterScrollThumb:SetHeight(thumbHeight)
        frame.rosterScrollThumb:ClearAllPoints()
        frame.rosterScrollThumb:SetPoint("TOP", frame.rosterScrollTrack, "TOP", 0, -math.floor(travel * ratio + 0.5))
    end
    frame.unassignedCount:SetText(string.format("%d", #unassigned))
    for rowIndex, row in ipairs(frame.rosterRows) do
        local record = unassigned[rosterOffset + rowIndex]
        if record then
            row.record = record
            row.name:SetText(ShortName(record.name))
            local textR, textG, textB, r, g, b = GetReadableClassColor(record.classToken)
            local useClassColor = self.db.colorNames ~= false
            row._classColor = useClassColor and { r, g, b } or nil
            if useClassColor then
                row.name:SetTextColor(textR, textG, textB, 1)
                row:SetBackdropColor(0.05 + (r * 0.022), 0.05 + (g * 0.022), 0.055 + (b * 0.022), 0.94)
                row:SetBackdropBorderColor(r * 0.54, g * 0.54, b * 0.54, 0.76)
                row.classAccent:SetColorTexture(r, g, b, 0.78)
                row.classAccent:Show()
            else
                row.name:SetTextColor(unpack(P.text))
                row:SetBackdropColor(unpack(P.control))
                row:SetBackdropBorderColor(unpack(P.borderSoft))
                row.classAccent:Hide()
            end
            SetRoleTexture(row.roleIcon, self.db.showRoleIcons ~= false and record.role or nil)
            row:Show()
        else
            row.record = nil
            row._classColor = nil
            row:Hide()
        end
    end
    self:UpdateBalancePatternButton()
    self:RefreshSavedLayouts()
end

function RaidGroups:CreateLauncher()
    if launcher then return launcher end
    launcher = CreateFrame("Button", "DDingUIToolkitRaidGroupsLauncher", UIParent, "BackdropTemplate")
    launcher:SetSize(34, 34)
    launcher:SetFrameStrata("HIGH")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    launcher:EnableMouse(true)
    launcher:RegisterForClicks("LeftButtonUp")
    launcher:RegisterForDrag("LeftButton")
    SetBackdrop(launcher, P.panel, P.border)

    launcher.cells = {}
    for index = 1, 4 do
        local cell = launcher:CreateTexture(nil, "ARTWORK")
        cell:SetSize(8, 8)
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        cell:SetPoint("TOPLEFT", 8 + (column * 10), -8 - (row * 10))
        cell:SetColorTexture(index == 1 and 0.42 or 0.16, index == 1 and 0.76 or 0.58,
            index == 1 and 0.82 or 0.68, 0.86)
        launcher.cells[index] = cell
    end

    launcher:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(P.hover))
        self:SetBackdropBorderColor(unpack(P.accentStrong))
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["RAIDGROUPS_LAUNCHER_TOOLTIP"], 0.25, 0.84, 1.00)
            GameTooltip:AddLine(L["RAIDGROUPS_LAUNCHER_TOOLTIP_DESC"], 0.72, 0.78, 0.84)
            GameTooltip:Show()
        end
    end)
    launcher:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(P.panel))
        self:SetBackdropBorderColor(unpack(P.border))
        if GameTooltip then GameTooltip:Hide() end
    end)
    launcher:SetScript("OnClick", function() RaidGroups:ToggleWindow() end)
    launcher:SetScript("OnDragStart", function(self)
        if not SafeBooleanCall(InCombatLockdown) then self:StartMoving() end
    end)
    launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        RaidGroups.db.launcherPosition.point = point
        RaidGroups.db.launcherPosition.relativePoint = relativePoint
        RaidGroups.db.launcherPosition.x = math.floor((SafeNumber(x) or 0) + 0.5)
        RaidGroups.db.launcherPosition.y = math.floor((SafeNumber(y) or 0) + 0.5)
    end)
    launcher:Hide()
    return launcher
end

function RaidGroups:UpdateLauncherVisibility()
    if not launcher then return end
    local shouldShow = active and self.db and self.db.showLauncher ~= false
    if shouldShow and self.db.launcherRaidOnly == true then shouldShow = SafeBooleanCall(IsInRaid) end
    launcher:SetShown(shouldShow == true)
end

function RaidGroups:ApplyLauncherSettings()
    local button = self:CreateLauncher()
    button:ClearAllPoints()
    local position = self.db.launcherPosition or {}
    button:SetPoint(position.point or "LEFT", UIParent, position.relativePoint or "LEFT",
        Clamp(position.x, -1600, 1600, 12), Clamp(position.y, -1000, 1000, 80))
    self:UpdateLauncherVisibility()
end

function RaidGroups:CreateFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "DDingUIToolkitRaidGroupsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(902, 560)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(300)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    SetBackdrop(frame, P.background, P.border)

    frame:SetScript("OnDragStart", function(self)
        if not SafeBooleanCall(InCombatLockdown) then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        RaidGroups.db.position.point = point
        RaidGroups.db.position.relativePoint = relativePoint
        RaidGroups.db.position.x = math.floor((SafeNumber(x) or 0) + 0.5)
        RaidGroups.db.position.y = math.floor((SafeNumber(y) or 0) + 0.5)
    end)

    frame.header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(42)
    SetBackdrop(frame.header, P.header, P.header)
    frame.accent = frame.header:CreateTexture(nil, "ARTWORK")
    frame.accent:SetPoint("BOTTOMLEFT")
    frame.accent:SetPoint("BOTTOMRIGHT")
    frame.accent:SetHeight(1)
    frame.accent:SetColorTexture(unpack(P.accent))

    frame.title = AddText(frame.header, 16, P.textBright, L["RAIDGROUPS_TITLE"])
    frame.title:SetPoint("LEFT", 16, 0)
    frame.subtitle = AddText(frame.header, 10, P.textDim, L["RAIDGROUPS_SUBTITLE"])
    frame.subtitle:SetPoint("LEFT", frame.title, "RIGHT", 12, -1)

    frame.close = CreateButton(frame.header, "X", 28, false)
    frame.close:SetSize(28, 25)
    frame.close:SetPoint("RIGHT", -9, 0)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.groupFrames = {}
    frame.slots = {}
    for group = 1, MAX_GROUPS do
        local groupFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        local column = (group - 1) % 4
        local row = math.floor((group - 1) / 4)
        groupFrame:SetSize(150, 174)
        groupFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (column * 158), -57 - (row * 182))
        SetBackdrop(groupFrame, P.panel, P.borderSoft)
        groupFrame.title = AddText(groupFrame, 12, P.accentText, string.format(L["RAIDGROUPS_GROUP_FORMAT"], group))
        groupFrame.title:SetPoint("TOPLEFT", 8, -7)
        groupFrame.count = AddText(groupFrame, 10, P.textDim, "0/5")
        groupFrame.count:SetPoint("TOPRIGHT", -8, -8)
        frame.groupFrames[group] = groupFrame

        for groupSlot = 1, SLOTS_PER_GROUP do
            local index = ((group - 1) * SLOTS_PER_GROUP) + groupSlot
            local slot = CreateFrame("Button", nil, groupFrame, "BackdropTemplate")
            slot:SetSize(134, 24)
            slot:SetPoint("TOPLEFT", 8, -28 - ((groupSlot - 1) * 27))
            slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot:RegisterForDrag("LeftButton")
            SetBackdrop(slot, P.control, P.borderSoft)
            slot.classAccent = slot:CreateTexture(nil, "ARTWORK")
            slot.classAccent:SetSize(3, 18)
            slot.classAccent:SetPoint("LEFT", 1, 0)
            slot.classAccent:Hide()
            slot.roleIcon = slot:CreateTexture(nil, "ARTWORK")
            slot.roleIcon:SetSize(17, 17)
            slot.roleIcon:SetPoint("LEFT", 4, 0)
            slot.name = AddText(slot, 10, P.text, "")
            slot.name:SetPoint("LEFT", slot.roleIcon, "RIGHT", 3, 0)
            slot.name:SetPoint("RIGHT", -4, 0)
            slot.name:SetJustifyH("LEFT")
            slot.name:SetWordWrap(false)
            slot:SetScript("OnClick", function(_, button) RaidGroups:HandleSlotClick(index, button) end)
            slot:SetScript("OnDragStart", function()
                if slot.playerName then
                    dragKind = "slot"
                    dragIndex = index
                    selectedSlot = index
                    RaidGroups:Refresh()
                end
            end)
            slot:SetScript("OnReceiveDrag", function()
                if dragKind == "slot" and dragIndex and dragIndex ~= index then
                    local layout = RaidGroups.db.currentLayout
                    layout[dragIndex], layout[index] = layout[index], layout[dragIndex]
                elseif dragKind == "roster" and dragIndex then
                    if dragName then RaidGroups:PlaceName(dragName, index) end
                end
                dragKind, dragIndex, dragName, selectedSlot = nil, nil, nil, nil
                RaidGroups:Refresh()
            end)
            frame.slots[index] = slot
        end
    end

    frame.side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.side:SetSize(232, 356)
    frame.side:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -57)
    SetBackdrop(frame.side, P.panel, P.borderSoft)
    frame.sideTitle = AddText(frame.side, 12, P.text, L["RAIDGROUPS_ROSTER"])
    frame.sideTitle:SetPoint("TOPLEFT", 10, -9)
    frame.unassignedCount = AddText(frame.side, 10, P.accentText, "0")
    frame.unassignedCount:SetPoint("TOPRIGHT", -10, -10)

    frame.rosterRows = {}
    for rowIndex = 1, 12 do
        local row = CreateFrame("Button", nil, frame.side, "BackdropTemplate")
        row:SetSize(210, 21)
        row:SetPoint("TOPLEFT", 10, -30 - ((rowIndex - 1) * 22))
        row:RegisterForClicks("LeftButtonUp")
        row:RegisterForDrag("LeftButton")
        SetBackdrop(row, P.control, P.borderSoft)
        row.classAccent = row:CreateTexture(nil, "ARTWORK")
        row.classAccent:SetSize(3, 15)
        row.classAccent:SetPoint("LEFT", 1, 0)
        row.classAccent:Hide()
        row.roleIcon = row:CreateTexture(nil, "ARTWORK")
        row.roleIcon:SetSize(15, 15)
        row.roleIcon:SetPoint("LEFT", 4, 0)
        row.name = AddText(row, 10, P.text, "")
        row.name:SetPoint("LEFT", row.roleIcon, "RIGHT", 4, 0)
        row.name:SetPoint("RIGHT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(P.accent)) end)
        row:SetScript("OnLeave", function(self)
            local color = self._classColor
            if color then
                self:SetBackdropBorderColor(color[1] * 0.54, color[2] * 0.54, color[3] * 0.54, 0.76)
            else
                self:SetBackdropBorderColor(unpack(P.borderSoft))
            end
        end)
        row:SetScript("OnClick", function(self)
            if not self.record then return end
            local target = selectedSlot
            if not target then
                for index = 1, MAX_SLOTS do
                    if not RaidGroups.db.currentLayout[index] then target = index break end
                end
            end
            if target then RaidGroups:PlaceName(self.record.name, target) end
        end)
        row:SetScript("OnDragStart", function(self)
            if self.record then
                dragKind = "roster"
                dragIndex = self.record.index
                dragName = self.record.name
            end
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            delta = SafeNumber(delta) or 0
            local unassigned = RaidGroups:GetUnassignedRoster()
            local maximum = math.max(0, #unassigned - #frame.rosterRows)
            rosterOffset = math.max(0, math.min(maximum, rosterOffset - math.floor(delta * 3)))
            RaidGroups:Refresh()
        end)
        frame.rosterRows[rowIndex] = row
    end
    frame.rosterScrollTrack = frame.side:CreateTexture(nil, "BACKGROUND")
    frame.rosterScrollTrack:SetSize(2, 12 * 22)
    frame.rosterScrollTrack:SetPoint("TOPRIGHT", -5, -30)
    frame.rosterScrollTrack:SetColorTexture(unpack(P.separator))
    frame.rosterScrollThumb = frame.side:CreateTexture(nil, "ARTWORK")
    frame.rosterScrollThumb:SetWidth(4)
    frame.rosterScrollThumb:SetPoint("TOP", frame.rosterScrollTrack, "TOP")
    frame.rosterScrollThumb:SetColorTexture(unpack(P.accent))

    frame.savedTitle = AddText(frame.side, 11, P.textDim, L["RAIDGROUPS_SAVED_LAYOUTS"])
    frame.savedTitle:SetPoint("TOPLEFT", 10, -298)
    frame.layoutName = CreateInput(frame.side, 143)
    frame.layoutName:SetPoint("TOPLEFT", 10, -317)
    frame.layoutName:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        RaidGroups:SaveLayout()
    end)
    frame.saveButton = CreateButton(frame.side, L["RAIDGROUPS_SAVE"], 61, true)
    frame.saveButton:SetSize(61, 25)
    frame.saveButton:SetPoint("LEFT", frame.layoutName, "RIGHT", 6, 0)
    frame.saveButton:SetScript("OnClick", function() RaidGroups:SaveLayout() end)

    frame.savedRows = {}
    for rowIndex = 1, 3 do
        local row = CreateFrame("Button", nil, frame, "BackdropTemplate")
        row:SetSize(204, 23)
        row:SetPoint("TOPLEFT", frame.side, "BOTTOMLEFT", 10, -8 - ((rowIndex - 1) * 26))
        SetBackdrop(row, P.control, P.borderSoft)
        row.label = AddText(row, 10, P.text, "")
        row.label:SetPoint("LEFT", 7, 0)
        row.label:SetPoint("RIGHT", -28, 0)
        row.label:SetJustifyH("LEFT")
        row.delete = CreateButton(row, "X", 22, false)
        row.delete:SetSize(20, 19)
        row.delete:SetPoint("RIGHT", -2, 0)
        row:SetScript("OnClick", function(self) if self.savedIndex then RaidGroups:LoadSavedLayout(self.savedIndex) end end)
        row.delete:SetScript("OnClick", function()
            if row.savedIndex then RaidGroups:DeleteSavedLayout(row.savedIndex) end
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            delta = SafeNumber(delta) or 0
            local maximum = math.max(0, #RaidGroups.db.savedLayouts - #frame.savedRows)
            savedOffset = math.max(0, math.min(maximum, savedOffset - math.floor(delta)))
            RaidGroups:RefreshSavedLayouts()
        end)
        frame.savedRows[rowIndex] = row
    end
    frame.savedScrollTrack = frame:CreateTexture(nil, "BACKGROUND")
    frame.savedScrollTrack:SetSize(2, 75)
    frame.savedScrollTrack:SetPoint("TOPRIGHT", frame.side, "BOTTOMRIGHT", -4, -8)
    frame.savedScrollTrack:SetColorTexture(unpack(P.separator))
    frame.savedScrollThumb = frame:CreateTexture(nil, "ARTWORK")
    frame.savedScrollThumb:SetWidth(4)
    frame.savedScrollThumb:SetPoint("TOP", frame.savedScrollTrack, "TOP")
    frame.savedScrollThumb:SetColorTexture(unpack(P.accent))

    frame.status = AddText(frame, 10, P.textDim, L["RAIDGROUPS_STATUS_READY"])
    frame.status:SetPoint("BOTTOMLEFT", 15, 47)
    frame.status:SetPoint("RIGHT", -15, 47)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)

    frame.importButton = CreateButton(frame, L["RAIDGROUPS_IMPORT_CURRENT"], 126, false)
    frame.importButton:SetPoint("BOTTOMLEFT", 14, 13)
    frame.importButton:SetScript("OnClick", function() RaidGroups:LoadCurrentRoster() end)
    frame.patternButton = CreateButton(frame, L["RAIDGROUPS_PATTERN_ODD_EVEN_SHORT"], 108, false)
    frame.patternButton:SetPoint("LEFT", frame.importButton, "RIGHT", 7, 0)
    frame.patternButton:SetScript("OnClick", function()
        RaidGroups:SetBalancePattern(RaidGroups.db.balancePattern == BALANCE_CONTIGUOUS
            and BALANCE_ODD_EVEN or BALANCE_CONTIGUOUS)
    end)
    frame.patternButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(P.hover))
        self:SetBackdropBorderColor(unpack(P.border))
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["RAIDGROUPS_BALANCE_PATTERN"], 0.25, 0.84, 1.00)
            GameTooltip:AddLine(L["RAIDGROUPS_BALANCE_PATTERN_DESC"], 0.72, 0.78, 0.84, true)
            GameTooltip:Show()
        end
    end)
    frame.patternButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(P.control))
        self:SetBackdropBorderColor(unpack(P.borderSoft))
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame.balanceButton = CreateButton(frame, L["RAIDGROUPS_AUTO_BALANCE"], 116, false)
    frame.balanceButton:SetPoint("LEFT", frame.patternButton, "RIGHT", 7, 0)
    frame.balanceButton:SetScript("OnClick", function() RaidGroups:AutoBalance() end)
    frame.clearButton = CreateButton(frame, L["RAIDGROUPS_CLEAR"], 70, false)
    frame.clearButton:SetPoint("LEFT", frame.balanceButton, "RIGHT", 7, 0)
    frame.clearButton:SetScript("OnClick", function() RaidGroups:ClearLayout() end)
    frame.applyButton = CreateButton(frame, L["RAIDGROUPS_APPLY"], 124, true)
    frame.applyButton:SetPoint("BOTTOMRIGHT", -14, 13)
    frame.applyButton:SetScript("OnClick", function() RaidGroups:StartApply() end)

    table.insert(UISpecialFrames, frame:GetName())
    frame:Hide()
    frame:SetScript("OnShow", function(self)
        if self.Raise then self:Raise() end
    end)
    frame:SetScript("OnHide", function()
        RaidGroups:RestoreTestState()
        dragKind, dragIndex, dragName, selectedSlot = nil, nil, nil, nil
    end)
    self.frame = frame
    return frame
end

function RaidGroups:ApplySettings()
    self.db = EnsureDB()
    if not self.db then return end
    local display = self:CreateFrame()
    display:SetScale(Clamp(self.db.scale, 0.7, 1.4, 1))
    display:ClearAllPoints()
    local position = self.db.position
    display:SetPoint(position.point or "CENTER", UIParent, position.relativePoint or "CENTER",
        Clamp(position.x, -1200, 1200, 0), Clamp(position.y, -800, 800, 20))
    self:ApplyLauncherSettings()
    self:Refresh()
end

function RaidGroups:RestoreTestState()
    if not self.testMode then return end
    if self.preTestLayout and self.db then
        self.db.currentLayout = self.preTestLayout
        self.db.selectedLayoutName = self.preTestLayoutName or ""
    end
    self.preTestLayout = nil
    self.preTestLayoutName = nil
    self.testMode = false
end

function RaidGroups:ShowWindow(testMode)
    self.db = self.db or EnsureDB()
    if not self.db then return end
    if testMode == true then
        if not self.testMode then
            self.preTestLayout = CopyTable(self.db.currentLayout)
            self.preTestLayoutName = self.db.selectedLayoutName
        end
        self.testMode = true
        self:BuildTestRoster()
    else
        self:RestoreTestState()
        self:CollectRoster()
    end
    self:ApplySettings()
    frame.layoutName:SetText(self.db.selectedLayoutName or "")
    frame:Show()
    if frame.Raise then frame:Raise() end
    self:Refresh()
end

function RaidGroups:ToggleWindow()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:ShowWindow(false)
    end
end

function RaidGroups:TestMode()
    if frame and frame:IsShown() and self.testMode then
        self:RestoreTestState()
        frame:Hide()
    else
        self:ShowWindow(true)
        self:SetStatus(L["RAIDGROUPS_STATUS_TEST"], "normal")
    end
end

function RaidGroups:ResetPosition()
    self.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 20 }
    self:ApplySettings()
end

function RaidGroups:ResetLauncherPosition()
    self.db.launcherPosition = { point = "LEFT", relativePoint = "LEFT", x = 12, y = 80 }
    self:ApplyLauncherSettings()
end

function RaidGroups:OnInitialize()
    self.db = EnsureDB()
    RegisterSpecializationTracking()
    self.initialized = true
end

function RaidGroups:OnEnable()
    self.db = EnsureDB()
    RegisterSpecializationTracking()
    active = true
    self:CollectRoster()
    self:ApplyLauncherSettings()
end

function RaidGroups:OnDisable()
    active = false
    applyState = nil
    self:RestoreTestState()
    if frame then frame:Hide() end
    if launcher then launcher:Hide() end
end

eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    if not active then return end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        RaidGroups:UpdateLauncherVisibility()
    end
    if event == "PLAYER_REGEN_ENABLED" and applyState then
        RaidGroups:ScheduleApply(0.1)
    elseif event == "GROUP_ROSTER_UPDATE" and applyState then
        RaidGroups:ScheduleApply(0.12)
    elseif frame and frame:IsShown() and not RaidGroups.testMode and not refreshPending then
        refreshPending = true
        C_Timer.After(0.15, function()
            refreshPending = false
            if active and frame and frame:IsShown() and not RaidGroups.testMode then
                RaidGroups:CollectRoster()
                RaidGroups:Refresh()
            end
        end)
    end
end)

SLASH_DDINGTOOLKITRAIDGROUPS1 = "/ddrg"
SlashCmdList.DDINGTOOLKITRAIDGROUPS = function() RaidGroups:ToggleWindow() end

DDingToolKit:RegisterModule("RaidGroups", RaidGroups)
