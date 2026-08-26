-- DDingUI Toolkit - raid subgroup composition tooltip

local addonName, ns = ...
local L = ns.L
local DDingToolKit = ns.DDingToolKit

local RaidPartyTooltip = {}

local MAX_GROUPS = 8
local SLOTS_PER_GROUP = 5
local MAX_RAID_MEMBERS = 40
local RAID_LFG_CATEGORY_ID = 3
local TOOLTIP_HEADER_FONT_SIZE = 15
local TOOLTIP_SECTION_FONT_SIZE = 14
local TOOLTIP_BODY_FONT_SIZE = 14
local CLASS_ICON_SIZE = 16
local ROLE_ICON_SIZE = 16
local ROLE_CLASSES_PER_ROW = 4

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
local ROLE_ORDER = { "TANK", "DAMAGER", "HEALER", "NONE" }
local ROLE_ATLAS = {
    TANK = "groupfinder-icon-role-large-tank",
    DAMAGER = "groupfinder-icon-role-large-dps",
    HEALER = "groupfinder-icon-role-large-heal",
}
local ROLE_COLORS = {
    TANK = { 0.42, 0.68, 1.00 },
    DAMAGER = { 1.00, 0.46, 0.38 },
    HEALER = { 0.38, 0.90, 0.52 },
    NONE = { 0.72, 0.72, 0.76 },
}
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
local lfgTooltipHooked = false

local memberButtons = setmetatable({}, { __mode = "k" })
local memberButtonHooks = setmetatable({}, { __mode = "k" })
local standaloneOwners = setmetatable({}, { __mode = "k" })
local standaloneHooks = setmetatable({}, { __mode = "k" })
local styledTooltips = setmetatable({}, { __mode = "k" })

local attachWatcher = CreateFrame("Frame")
attachWatcher:RegisterEvent("ADDON_LOADED")

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

local function SafeTableField(tableValue, key)
    if IsSecret(tableValue) or type(tableValue) ~= "table" then return nil, false end
    local ok, value = pcall(function() return tableValue[key] end)
    if not ok or IsSecret(value) then return nil, false end
    return value, true
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
        "|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t ",
        CLASS_ICON_TEXTURE,
        CLASS_ICON_SIZE,
        CLASS_ICON_SIZE,
        values[1], values[2], values[3], values[4]
    )
end

local function NormalizeRole(role)
    if IsSecret(role) or type(role) ~= "string" then return "NONE" end
    if role == "TANK" or role == "DAMAGER" or role == "HEALER" then return role end
    return "NONE"
end

local function GetRoleIconMarkup(role)
    local atlas = ROLE_ATLAS[role]
    if atlas then
        return string.format("|A:%s:%d:%d|a ", atlas, ROLE_ICON_SIZE, ROLE_ICON_SIZE)
    end
    return "|cffffcc00?|r "
end

local function CreateRoleClassCounts()
    return {
        TANK = {},
        DAMAGER = {},
        HEALER = {},
        NONE = {},
    }
end

local function CreateUnknownClassCounts()
    return {
        TANK = 0,
        DAMAGER = 0,
        HEALER = 0,
        NONE = 0,
    }
end

local function AddSummaryMember(summary, classFile, role)
    role = NormalizeRole(role)
    summary.total = summary.total + 1

    if not IsSecret(classFile) and type(classFile) == "string" and classFile ~= "" then
        summary.classes[classFile] = (summary.classes[classFile] or 0) + 1
        local roleClasses = summary.roleClasses[role]
        roleClasses[classFile] = (roleClasses[classFile] or 0) + 1

        local armorType = CLASS_ARMOR[classFile]
        if armorType then
            summary.armor[armorType] = summary.armor[armorType] + 1
        else
            summary.unknownArmor = summary.unknownArmor + 1
        end
        return
    end

    summary.unknownClasses = summary.unknownClasses + 1
    summary.unknownClassesByRole[role] = summary.unknownClassesByRole[role] + 1
    summary.unknownArmor = summary.unknownArmor + 1
end

local function ResolveRaidMemberRole(index, combatRole)
    local assignedRole
    if type(UnitGroupRolesAssigned) == "function" then
        local ok, value = pcall(UnitGroupRolesAssigned, "raid" .. index)
        if ok and not IsSecret(value) then assignedRole = NormalizeRole(value) end
    end
    if assignedRole and assignedRole ~= "NONE" then return assignedRole end
    return NormalizeRole(combatRole)
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
        roleClasses = CreateRoleClassCounts(),
        unknownClasses = 0,
        unknownClassesByRole = CreateUnknownClassCounts(),
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
        local ok, name, rank, memberGroup, level, className, classFile, zone, online,
            isDead, legacyRole, isMasterLooter, combatRole = pcall(GetRaidRosterInfo, index)
        if ok and SafeInteger(memberGroup, 1, MAX_GROUPS) == subgroup then
            AddSummaryMember(summary, classFile, ResolveRaidMemberRole(index, combatRole))
        end
    end

    return summary
end

function RaidPartyTooltip:CollectSearchResult(resultID)
    resultID = SafeInteger(resultID, 1)
    local api = _G.C_LFGList
    if not resultID or type(api) ~= "table"
        or type(api.GetSearchResultPlayerInfo) ~= "function" then
        return nil
    end

    local expectedMembers
    if type(api.GetSearchResultInfo) == "function" then
        local ok, resultInfo = pcall(api.GetSearchResultInfo, resultID)
        if ok then
            local value, accessible = SafeTableField(resultInfo, "numMembers")
            if accessible then
                expectedMembers = SafeInteger(value, 0, MAX_RAID_MEMBERS)
            end
        end
    end

    if expectedMembers == 0 then return nil end

    local summary = {
        total = 0,
        classes = {},
        roleClasses = CreateRoleClassCounts(),
        unknownClasses = 0,
        unknownClassesByRole = CreateUnknownClassCounts(),
        armor = { CLOTH = 0, LEATHER = 0, MAIL = 0, PLATE = 0 },
        unknownArmor = 0,
    }
    local memberLimit = expectedMembers or MAX_RAID_MEMBERS

    for index = 1, memberLimit do
        local ok, memberInfo = pcall(api.GetSearchResultPlayerInfo, resultID, index)
        if not ok then return nil end
        if IsSecret(memberInfo) then return nil end
        if memberInfo == nil then
            if expectedMembers then return nil end
            break
        end

        local classFile, accessible = SafeTableField(memberInfo, "classFilename")
        if not accessible or type(classFile) ~= "string" or classFile == "" then
            return nil
        end

        local assignedRole, roleAccessible = SafeTableField(memberInfo, "assignedRole")
        AddSummaryMember(summary, classFile, roleAccessible and assignedRole or "NONE")
    end

    if summary.total == 0 or (expectedMembers and summary.total ~= expectedMembers) then
        return nil
    end
    return summary
end

local function BuildOrderedClassEntries(classCounts, unknownCount, showIcons)
    local entries = {}
    local seen = {}

    local function AddFromOrder(order)
        if type(order) ~= "table" then return end
        for _, classFile in ipairs(order) do
            local count = classCounts[classFile]
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
    for classFile, count in pairs(classCounts) do
        if count > 0 and not seen[classFile] then
            remaining[#remaining + 1] = classFile
        end
    end
    table.sort(remaining)
    AddFromOrder(remaining)

    if unknownCount > 0 then
        entries[#entries + 1] = ColorText(L["RPT_UNKNOWN"], ARMOR_COLORS.UNKNOWN)
            .. " |cffffffff" .. unknownCount .. "|r"
    end
    return entries
end

local function BuildClassEntries(summary, showIcons)
    local rows = {}
    local roleClasses = summary.roleClasses or CreateRoleClassCounts()
    local unknownByRole = summary.unknownClassesByRole or CreateUnknownClassCounts()

    for _, role in ipairs(ROLE_ORDER) do
        local entries = BuildOrderedClassEntries(
            roleClasses[role] or {},
            unknownByRole[role] or 0,
            showIcons
        )
        local roleHeader = GetRoleIconMarkup(role)
            .. ColorText(L["RPT_ROLE_" .. role], ROLE_COLORS[role])

        if #entries == 0 then
            if role ~= "NONE" then
                rows[#rows + 1] = roleHeader
                rows[#rows + 1] = "    "
                    .. ColorText(L["RPT_ROLE_EMPTY"], ARMOR_COLORS.UNKNOWN)
            end
        else
            rows[#rows + 1] = roleHeader
            for first = 1, #entries, ROLE_CLASSES_PER_ROW do
                local chunk = {}
                local last = math.min(first + ROLE_CLASSES_PER_ROW - 1, #entries)
                for index = first, last do
                    chunk[#chunk + 1] = entries[index]
                end
                rows[#rows + 1] = "    " .. table.concat(chunk, "  ")
            end
        end
    end
    return rows
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

local function RestoreTooltipFonts(tooltip)
    local state = styledTooltips[tooltip]
    if not state then return end

    for fontString, original in pairs(state.originals) do
        if original.fontObject and type(fontString.SetFontObject) == "function" then
            fontString:SetFontObject(original.fontObject)
        elseif original.fontPath and type(fontString.SetFont) == "function" then
            fontString:SetFont(original.fontPath, original.fontSize, original.fontFlags)
        end
    end
    state.originals = {}
end

local function GetTooltipFontState(tooltip)
    local state = styledTooltips[tooltip]
    if state then return state end

    state = { originals = {} }
    styledTooltips[tooltip] = state

    if type(tooltip.HookScript) == "function" then
        tooltip:HookScript("OnHide", RestoreTooltipFonts)
        pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", RestoreTooltipFonts)
    end
    return state
end

local function SetLatestTooltipLineFontSize(tooltip, fontSize)
    if not tooltip or type(tooltip.GetName) ~= "function" or type(tooltip.NumLines) ~= "function" then
        return
    end

    local tooltipName = tooltip:GetName()
    local lineIndex = tooltip:NumLines()
    if type(tooltipName) ~= "string" or type(lineIndex) ~= "number" then return end

    local state = GetTooltipFontState(tooltip)
    for _, side in ipairs({ "Left", "Right" }) do
        local fontString = _G[tooltipName .. "Text" .. side .. lineIndex]
        if fontString and type(fontString.GetFont) == "function" and type(fontString.SetFont) == "function" then
            local fontPath, currentSize, fontFlags = fontString:GetFont()
            if type(fontPath) == "string" and fontPath ~= "" then
                if not state.originals[fontString] then
                    state.originals[fontString] = {
                        fontObject = type(fontString.GetFontObject) == "function" and fontString:GetFontObject() or nil,
                        fontPath = fontPath,
                        fontSize = currentSize,
                        fontFlags = fontFlags,
                    }
                end
                fontString:SetFont(fontPath, fontSize, fontFlags)
            end
        end
    end
end

local function AddSizedLine(tooltip, text, r, g, b, fontSize)
    tooltip:AddLine(text, r, g, b)
    SetLatestTooltipLineFontSize(tooltip, fontSize)
end

local function AddSizedDoubleLine(tooltip, leftText, rightText, lr, lg, lb, rr, rg, rb, fontSize)
    tooltip:AddDoubleLine(leftText, rightText, lr, lg, lb, rr, rg, rb)
    SetLatestTooltipLineFontSize(tooltip, fontSize)
end

local function AddSingleColumnRows(tooltip, entries)
    for _, entry in ipairs(entries) do
        AddSizedLine(tooltip, entry, 1, 1, 1, TOOLTIP_BODY_FONT_SIZE)
    end
end

local function AddGroupSummary(tooltip, subgroup, append)
    if not active or not tooltip then return end

    local settings = db or GetDB()
    local summary = RaidPartyTooltip:CollectGroup(subgroup)
    if not append then tooltip:ClearLines() end
    if append then tooltip:AddLine(" ") end

    AddSizedDoubleLine(
        tooltip,
        string.format(L["RPT_GROUP_TITLE"], subgroup),
        string.format(L["RPT_MEMBER_COUNT"], summary.total),
        0.35, 0.82, 0.92,
        0.76, 0.78, 0.82,
        TOOLTIP_HEADER_FONT_SIZE
    )

    if summary.total == 0 then
        AddSizedLine(tooltip, L["RPT_NO_MEMBERS"], 0.62, 0.62, 0.64, TOOLTIP_BODY_FONT_SIZE)
        return
    end

    if settings.showClassCounts ~= false then
        tooltip:AddLine(" ")
        AddSizedLine(tooltip, L["RPT_CLASS_SECTION"], 0.35, 0.82, 0.92, TOOLTIP_SECTION_FONT_SIZE)
        AddSingleColumnRows(tooltip, BuildClassEntries(summary, settings.showClassIcons ~= false))
    end

    if settings.showArmorCounts ~= false then
        tooltip:AddLine(" ")
        AddSizedLine(tooltip, L["RPT_ARMOR_SECTION"], 0.35, 0.82, 0.92, TOOLTIP_SECTION_FONT_SIZE)
        AddSingleColumnRows(tooltip, BuildArmorEntries(summary, settings.showZeroArmor ~= false))
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

local function HookMemberButton(button)
    if not button or type(button.HookScript) ~= "function" then return false end
    memberButtons[button] = true

    if not memberButtonHooks[button] then
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

local function GetCurrentLFGCategory()
    local frame = _G.LFGListFrame
    if not frame then return nil end

    local searchPanel = frame.SearchPanel
    local categoryID = searchPanel and SafeInteger(searchPanel.categoryID, 1)
    if categoryID then return categoryID end

    local categorySelection = frame.CategorySelection
    return categorySelection and SafeInteger(categorySelection.selectedCategory, 1) or nil
end

local function AppendSearchResultSummary(tooltip, resultID)
    if not active or not tooltip or not db or db.showOnPremadeRaid == false then return end
    if GetCurrentLFGCategory() ~= RAID_LFG_CATEGORY_ID then return end

    local summary = RaidPartyTooltip:CollectSearchResult(resultID)
    if not summary then return end

    tooltip:AddLine(" ")
    AddSizedDoubleLine(
        tooltip,
        L["RPT_LFG_TITLE"],
        string.format(L["RPT_MEMBER_COUNT"], summary.total),
        0.35, 0.82, 0.92,
        0.76, 0.78, 0.82,
        TOOLTIP_HEADER_FONT_SIZE
    )

    if db.showClassCounts ~= false then
        tooltip:AddLine(" ")
        AddSizedLine(tooltip, L["RPT_CLASS_SECTION"], 0.35, 0.82, 0.92, TOOLTIP_SECTION_FONT_SIZE)
        AddSingleColumnRows(tooltip, BuildClassEntries(summary, db.showClassIcons ~= false))
    end

    if db.showArmorCounts ~= false then
        tooltip:AddLine(" ")
        AddSizedLine(tooltip, L["RPT_ARMOR_SECTION"], 0.35, 0.82, 0.92, TOOLTIP_SECTION_FONT_SIZE)
        AddSingleColumnRows(tooltip, BuildArmorEntries(summary, db.showZeroArmor ~= false))
    end
    tooltip:Show()
end

function RaidPartyTooltip:AttachLFGTooltip()
    if lfgTooltipHooked then return true end
    if type(_G.hooksecurefunc) ~= "function"
        or type(_G.LFGListUtil_SetSearchEntryTooltip) ~= "function" then
        return false
    end

    local ok = pcall(_G.hooksecurefunc, "LFGListUtil_SetSearchEntryTooltip", AppendSearchResultSummary)
    lfgTooltipHooked = ok
    return ok
end

function RaidPartyTooltip:AttachBlizzardRaidUI()
    if hooksComplete then return true end
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

    self:AttachBlizzardRaidUI()
    self:AttachLFGTooltip()
end

function RaidPartyTooltip:OnDisable()
    active = false

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

attachWatcher:SetScript("OnEvent", function(_, event, loadedAddon)
    if event ~= "ADDON_LOADED" or not active then return end
    if loadedAddon == "Blizzard_RaidUI" then
        RaidPartyTooltip:AttachBlizzardRaidUI()
    elseif loadedAddon == "Blizzard_GroupFinder" then
        RaidPartyTooltip:AttachLFGTooltip()
    end
end)

DDingToolKit:RegisterModule("RaidPartyTooltip", RaidPartyTooltip)
