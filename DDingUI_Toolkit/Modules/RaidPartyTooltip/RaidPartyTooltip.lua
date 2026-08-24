-- DDingUI Toolkit - raid subgroup composition tooltip

local addonName, ns = ...
local L = ns.L
local DDingToolKit = ns.DDingToolKit

local RaidPartyTooltip = {}

local MAX_GROUPS = 8
local SLOTS_PER_GROUP = 5
local MAX_RAID_MEMBERS = 40
local ATTACH_INTERVAL = 0.5

local CLASS_ARMOR = {
    PRIEST = "CLOTH",
    MAGE = "CLOTH",
    WARLOCK = "CLOTH",
    ROGUE = "LEATHER",
    MONK = "LEATHER",
    DRUID = "LEATHER",
    DEMONHUNTER = "LEATHER",
    HUNTER = "MAIL",
    SHAMAN = "MAIL",
    EVOKER = "MAIL",
    WARRIOR = "PLATE",
    PALADIN = "PLATE",
    DEATHKNIGHT = "PLATE",
}

local FALLBACK_CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local FALLBACK_CLASS_ICON_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 },
    MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 },
    SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
    WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
    DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
    MONK = { 0.49609375, 0.7421875, 0.5, 0.75 },
    DEMONHUNTER = { 0.7421875, 0.98828125, 0.5, 0.75 },
    EVOKER = { 0, 0.25, 0.75, 1 },
}

local ARMOR_ORDER = { "CLOTH", "LEATHER", "MAIL", "PLATE" }
local ARMOR_COLORS = {
    CLOTH = { 0.82, 0.84, 0.90 },
    LEATHER = { 0.78, 0.55, 0.32 },
    MAIL = { 0.34, 0.70, 0.84 },
    PLATE = { 0.88, 0.74, 0.38 },
    UNKNOWN = { 0.62, 0.62, 0.64 },
}

local active = false
local db
local hooksComplete = false
local tooltipProcessorRegistered = false
local attachElapsed = 0

local memberButtons = setmetatable({}, { __mode = "k" })
local memberButtonHooks = setmetatable({}, { __mode = "k" })
local standaloneOwners = setmetatable({}, { __mode = "k" })
local standaloneHooks = setmetatable({}, { __mode = "k" })

local attachWatcher = CreateFrame("Frame")
attachWatcher:Hide()

local function GetDB()
    local profile = ns.db and ns.db.profile
    local settings = profile and profile.RaidPartyTooltip
    return type(settings) == "table" and settings or {}
end

local function IsSecret(value)
    local checker = ns.IsSecretValue or issecretvalue
    if type(checker) ~= "function" then return false end
    local ok, result = pcall(checker, value)
    return ok and result == true
end

local function SafeInteger(value, minimum, maximum)
    if IsSecret(value) then return nil end
    local ok, number = pcall(tonumber, value)
    if not ok or IsSecret(number) or type(number) ~= "number" or number ~= number then
        return nil
    end

    number = math.floor(number)
    if minimum and number < minimum then return nil end
    if maximum and number > maximum then return nil end
    return number
end

local function ColorText(text, color)
    color = color or ARMOR_COLORS.UNKNOWN
    local r = math.floor(math.max(0, math.min(1, tonumber(color.r or color[1]) or 1)) * 255 + 0.5)
    local g = math.floor(math.max(0, math.min(1, tonumber(color.g or color[2]) or 1)) * 255 + 0.5)
    local b = math.floor(math.max(0, math.min(1, tonumber(color.b or color[3]) or 1)) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, text or "")
end

local function GetClassName(classFile)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    if type(names) == "table" and type(names[classFile]) == "string" then
        return names[classFile]
    end
    return classFile or L["RPT_UNKNOWN"]
end

local function GetClassColor(classFile)
    local colors = _G.RAID_CLASS_COLORS
    local color = type(colors) == "table" and colors[classFile]
    return type(color) == "table" and color or ARMOR_COLORS.UNKNOWN
end

local function GetClassIconMarkup(classFile)
    local globalCoords = _G.CLASS_ICON_TCOORDS
    local coords = type(globalCoords) == "table" and globalCoords[classFile]
        or FALLBACK_CLASS_ICON_TCOORDS[classFile]
    if type(coords) ~= "table" then return "" end

    local values = {}
    for index = 1, 4 do
        local value = coords[index]
        if IsSecret(value) or type(value) ~= "number" then return "" end
        values[index] = math.floor(value * 256 + 0.5)
    end

    return string.format(
        "|T%s:14:14:0:0:256:256:%d:%d:%d:%d|t ",
        CLASS_ICON_TEXTURE,
        values[1], values[2], values[3], values[4]
    )
end

local function IsCurrentlyInRaid()
    if type(IsInRaid) ~= "function" then return false end
    local ok, result = pcall(IsInRaid)
    return ok and not IsSecret(result) and result == true
end

function RaidPartyTooltip:CollectGroup(subgroup)
    subgroup = SafeInteger(subgroup, 1, MAX_GROUPS)
    local summary = {
        subgroup = subgroup,
        total = 0,
        classes = {},
        unknownClasses = 0,
        armor = { CLOTH = 0, LEATHER = 0, MAIL = 0, PLATE = 0 },
        unknownArmor = 0,
    }

    if not subgroup or not IsCurrentlyInRaid() or type(GetRaidRosterInfo) ~= "function" then
        return summary
    end

    local memberCount = MAX_RAID_MEMBERS
    if type(GetNumGroupMembers) == "function" then
        local ok, value = pcall(GetNumGroupMembers)
        memberCount = ok and SafeInteger(value, 0, MAX_RAID_MEMBERS) or 0
        memberCount = memberCount or 0
    end

    for index = 1, memberCount do
        local ok, _, _, memberGroup, _, _, classFile = pcall(GetRaidRosterInfo, index)
        if ok and SafeInteger(memberGroup, 1, MAX_GROUPS) == subgroup then
            summary.total = summary.total + 1

            if not IsSecret(classFile) and type(classFile) == "string" and classFile ~= "" then
                summary.classes[classFile] = (summary.classes[classFile] or 0) + 1
                local armorType = CLASS_ARMOR[classFile]
                if armorType then
                    summary.armor[armorType] = summary.armor[armorType] + 1
                else
                    summary.unknownArmor = summary.unknownArmor + 1
                end
            else
                summary.unknownClasses = summary.unknownClasses + 1
                summary.unknownArmor = summary.unknownArmor + 1
            end
        end
    end

    return summary
end

local function BuildClassEntries(summary, showIcons)
    local entries = {}
    local seen = {}

    local function AddFromOrder(order)
        if type(order) ~= "table" then return end
        for _, classFile in ipairs(order) do
            local count = summary.classes[classFile]
            if count and count > 0 and not seen[classFile] then
                seen[classFile] = true
                local icon = showIcons and GetClassIconMarkup(classFile) or ""
                entries[#entries + 1] = icon .. ColorText(GetClassName(classFile), GetClassColor(classFile))
                    .. " |cffffffff" .. count .. "|r"
            end
        end
    end

    AddFromOrder(_G.CLASS_SORT_ORDER)
    AddFromOrder(FALLBACK_CLASS_ORDER)

    local remaining = {}
    for classFile, count in pairs(summary.classes) do
        if count > 0 and not seen[classFile] then
            remaining[#remaining + 1] = classFile
        end
    end
    table.sort(remaining)
    AddFromOrder(remaining)

    if summary.unknownClasses > 0 then
        entries[#entries + 1] = ColorText(L["RPT_UNKNOWN"], ARMOR_COLORS.UNKNOWN)
            .. " |cffffffff" .. summary.unknownClasses .. "|r"
    end
    return entries
end

local function BuildArmorEntries(summary, showZero)
    local entries = {}
    for _, armorType in ipairs(ARMOR_ORDER) do
        local count = summary.armor[armorType] or 0
        if showZero or count > 0 then
            entries[#entries + 1] = ColorText(L["RPT_ARMOR_" .. armorType], ARMOR_COLORS[armorType])
                .. " |cffffffff" .. count .. "|r"
        end
    end
    if summary.unknownArmor > 0 then
        entries[#entries + 1] = ColorText(L["RPT_UNKNOWN"], ARMOR_COLORS.UNKNOWN)
            .. " |cffffffff" .. summary.unknownArmor .. "|r"
    end
    return entries
end

local function AddPairedRows(tooltip, entries)
    for index = 1, #entries, 2 do
        tooltip:AddDoubleLine(entries[index], entries[index + 1] or "", 1, 1, 1, 1, 1, 1)
    end
end

local function AddGroupSummary(tooltip, subgroup, append)
    if not active or not tooltip then return end

    local settings = db or GetDB()
    local summary = RaidPartyTooltip:CollectGroup(subgroup)
    if not append then tooltip:ClearLines() end
    if append then tooltip:AddLine(" ") end

    tooltip:AddDoubleLine(
        string.format(L["RPT_GROUP_TITLE"], subgroup),
        string.format(L["RPT_MEMBER_COUNT"], summary.total),
        0.35, 0.82, 0.92,
        0.76, 0.78, 0.82
    )

    if summary.total == 0 then
        tooltip:AddLine(L["RPT_NO_MEMBERS"], 0.62, 0.62, 0.64)
        return
    end

    if settings.showClassCounts ~= false then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["RPT_CLASS_SECTION"], 0.35, 0.82, 0.92)
        AddPairedRows(tooltip, BuildClassEntries(summary, settings.showClassIcons ~= false))
    end

    if settings.showArmorCounts ~= false then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["RPT_ARMOR_SECTION"], 0.35, 0.82, 0.92)
        AddPairedRows(tooltip, BuildArmorEntries(summary, settings.showZeroArmor ~= false))
    end
end

local function ResolveMemberGroup(button)
    if not button then return nil end

    local subgroup = SafeInteger(button.subgroup, 1, MAX_GROUPS)
    if subgroup then return subgroup end

    local raidIndex = SafeInteger(button.id, 1, MAX_RAID_MEMBERS)
    if not raidIndex and type(button.GetID) == "function" then
        local ok, value = pcall(button.GetID, button)
        if ok then raidIndex = SafeInteger(value, 1, MAX_RAID_MEMBERS) end
    end
    if not raidIndex or type(GetRaidRosterInfo) ~= "function" then return nil end

    local ok, _, _, memberGroup = pcall(GetRaidRosterInfo, raidIndex)
    return ok and SafeInteger(memberGroup, 1, MAX_GROUPS) or nil
end

local function ShowStandalone(owner)
    if not active or not owner or not GameTooltip then return end
    local data = standaloneOwners[owner]
    if not data then return end

    local settings = db or GetDB()
    if data.location == "SLOT" and settings.showOnEmptySlots == false then return end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    AddGroupSummary(GameTooltip, data.subgroup, false)
    GameTooltip:Show()
end

local function HideStandalone(owner)
    if not GameTooltip or not owner then return end
    local isOwned = type(GameTooltip.IsOwned) == "function" and GameTooltip:IsOwned(owner)
    if not isOwned and type(GameTooltip.GetOwner) == "function" then
        isOwned = GameTooltip:GetOwner() == owner
    end
    if isOwned then GameTooltip:Hide() end
end

local function HookStandalone(owner, subgroup, location)
    if not owner or type(owner.HookScript) ~= "function" then return false end
    standaloneOwners[owner] = { subgroup = subgroup, location = location }
    if not standaloneHooks[owner] then
        standaloneHooks[owner] = true
        owner:HookScript("OnEnter", ShowStandalone)
        owner:HookScript("OnLeave", HideStandalone)
    end
    return true
end

local function AppendToMemberTooltip(tooltip)
    if not active or not tooltip or not db or db.showOnMembers == false then return end
    if type(tooltip.GetOwner) ~= "function" then return end

    local owner = tooltip:GetOwner()
    if not owner or not memberButtons[owner] then return end

    local subgroup = ResolveMemberGroup(owner)
    if not subgroup then return end
    AddGroupSummary(tooltip, subgroup, true)
    tooltip:Show()
end

local function RegisterTooltipProcessor()
    if tooltipProcessorRegistered then return true end
    if not TooltipDataProcessor or type(TooltipDataProcessor.AddTooltipPostCall) ~= "function" then
        return false
    end
    if not Enum or not Enum.TooltipDataType or not Enum.TooltipDataType.Unit then
        return false
    end

    local ok = pcall(function()
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AppendToMemberTooltip)
    end)
    tooltipProcessorRegistered = ok
    return ok
end

local function HookMemberButton(button)
    if not button then return false end
    memberButtons[button] = true

    if not tooltipProcessorRegistered and type(button.HookScript) == "function" and not memberButtonHooks[button] then
        memberButtonHooks[button] = true
        button:HookScript("OnEnter", function(owner)
            if not active or not db or db.showOnMembers == false or not GameTooltip then return end
            local subgroup = ResolveMemberGroup(owner)
            if subgroup then
                AddGroupSummary(GameTooltip, subgroup, true)
                GameTooltip:Show()
            end
        end)
    end
    return true
end

function RaidPartyTooltip:AttachBlizzardRaidUI()
    RegisterTooltipProcessor()
    local complete = true

    for subgroup = 1, MAX_GROUPS do
        local label = _G["RaidGroup" .. subgroup .. "Label"]
        if not HookStandalone(label, subgroup, "LABEL") then complete = false end

        for slot = 1, SLOTS_PER_GROUP do
            local slotButton = _G["RaidGroup" .. subgroup .. "Slot" .. slot]
            if not HookStandalone(slotButton, subgroup, "SLOT") then complete = false end
        end
    end

    for index = 1, MAX_RAID_MEMBERS do
        if not HookMemberButton(_G["RaidGroupButton" .. index]) then complete = false end
    end

    hooksComplete = complete
    if complete then attachWatcher:Hide() end
    return complete
end

function RaidPartyTooltip:OnInitialize()
    self.db = GetDB()
    db = self.db
    self.initialized = true
end

function RaidPartyTooltip:OnEnable()
    self.db = GetDB()
    db = self.db
    active = true

    if not self:AttachBlizzardRaidUI() then
        attachElapsed = 0
        attachWatcher:Show()
    end
end

function RaidPartyTooltip:OnDisable()
    active = false
    attachWatcher:Hide()

    if GameTooltip and type(GameTooltip.GetOwner) == "function" then
        local owner = GameTooltip:GetOwner()
        if owner and (memberButtons[owner] or standaloneOwners[owner]) then
            GameTooltip:Hide()
        end
    end
end

function RaidPartyTooltip:ApplySettings()
    self.db = GetDB()
    db = self.db
end

attachWatcher:SetScript("OnUpdate", function(_, elapsed)
    if not active or hooksComplete then return end
    attachElapsed = attachElapsed + (tonumber(elapsed) or 0)
    if attachElapsed < ATTACH_INTERVAL then return end
    attachElapsed = 0
    RaidPartyTooltip:AttachBlizzardRaidUI()
end)

DDingToolKit:RegisterModule("RaidPartyTooltip", RaidPartyTooltip)
