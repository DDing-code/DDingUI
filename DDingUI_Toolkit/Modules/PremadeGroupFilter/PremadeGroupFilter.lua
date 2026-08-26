--[[
    DDingUI Toolkit - Premade Group Filter
    Compact Retail Group Finder filters and specialization indicators.
]]

local addonName, ns = ...
local L = ns.L
local SL = _G.DDingUI_StyleLib

local PremadeGroupFilter = {}

local SOLID = "Interface\\Buttons\\WHITE8x8"
local FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local P = ns.UI and ns.UI.popupColors or {
    background = { 0.10, 0.10, 0.10, 0.985 }, panel = { 0.075, 0.075, 0.08, 0.97 },
    control = { 0.06, 0.06, 0.06, 0.94 }, input = { 0.045, 0.045, 0.05, 1 },
    hover = { 0.14, 0.14, 0.15, 0.96 }, selected = { 0.10, 0.14, 0.15, 0.96 },
    border = { 0.30, 0.30, 0.32, 0.82 }, borderSoft = { 0.25, 0.25, 0.25, 0.50 },
    separator = { 0.20, 0.20, 0.20, 0.40 }, accent = { 0.16, 0.58, 0.68, 0.80 },
    accentStrong = { 0.16, 0.68, 0.80, 0.92 }, accentText = { 0.42, 0.76, 0.82, 1 },
    text = { 0.85, 0.85, 0.85, 1 }, textBright = { 1, 1, 1, 1 }, textDim = { 0.60, 0.60, 0.60, 1 },
}
local CATEGORY_DUNGEON = 2
local PANEL_WIDTH = 280
local PANEL_BOTTOM_EXTENSION = 16
local MAX_SEASON_DUNGEONS = 8
local DEFAULT_DUNGEON_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local BLOODLUST_CLASSES = {
    EVOKER = true,
    HUNTER = true,
    MAGE = true,
    SHAMAN = true,
}

local VALID_SORT_MODES = {
    DEFAULT = true,
    RATING = true,
    MAPBEST = true,
}

local BLOODLUST_SORT_ORDER = {
    PRESENT = 1,
    FLEX = 2,
    MISSING = 3,
}

local SEARCH_INFO_RENDER_KEYS = {
    "activityIDs",
    "name",
    "censored",
    "isWarMode",
    "isDelisted",
    "voiceChat",
    "generalPlaystyle",
    "numMembers",
    "numBNetFriends",
    "numCharFriends",
    "numGuildMates",
}

local CURRENT_SEASON_MAP_ORDER = { 588, 584, 586, 587, 585, 399, 250, 249 }
local CURRENT_SEASON_ACTIVITY_GROUPS = {
    [588] = 420,
    [584] = 382,
    [586] = 392,
    [587] = 396,
    [585] = 398,
    [399] = 306,
    [250] = 139,
    [249] = 141,
}
local MAP_ORDER_INDEX = {}
for index, mapID in ipairs(CURRENT_SEASON_MAP_ORDER) do
    MAP_ORDER_INDEX[mapID] = index
end

local ROLE_SORT_ORDER = {
    TANK = 1,
    HEALER = 2,
    DAMAGER = 3,
    NONE = 4,
}

local DUNGEON_COMPOSITION_ROLES = {
    "TANK",
    "HEALER",
    "DAMAGER",
    "DAMAGER",
    "DAMAGER",
}

local EMPTY_ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local EMPTY_ROLE_TEXCOORDS = {
    TANK = { 0 / 64, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

local OBSOLETE_DB_KEYS = {
    "filterEnabled",
    "requireLust",
    "requireBattleRes",
    "minMembers",
    "maxMembers",
    "maxAgeMinutes",
    "hideApplied",
    "hideDeclined",
    "advancedEnabled",
    "advancedExpression",
    "lastValidExpression",
    "presets",
    "selectedPreset",
    "alertEnabled",
    "alertMinMatches",
    "alertCooldown",
    "alertSoundEnabled",
    "alertScreenEnabled",
    "alertChatEnabled",
    "alertSoundFile",
    "alertSoundCustomPath",
    "alertSoundChannel",
    "alertScale",
    "alertDuration",
}

local sidePanel
local attachTicker
local hooksAttached = false
local specEntryHooked = false
local resultSortHooked = false
local lastMatchCount = 0
local lastTotalCount = 0
local specializationLookup
local specializationRows = setmetatable({}, { __mode = "k" })
local leaderScoreRows = setmetatable({}, { __mode = "k" })
local resultAssistRows = setmetatable({}, { __mode = "k" })
local nativeResultOrder = {}
local seasonDungeons = {}
local raiderIOAnchorHooked = false
local raiderIOAnchorUpdating = false
local raiderIORetryScheduled = false
local resultRefreshPending = false
local chatRestrictionState

local ADVANCED_FILTER_BOOLEAN_KEYS = {
    "needsTank",
    "needsHealer",
    "needsDamage",
    "needsMyClass",
    "hasTank",
    "hasHealer",
    "difficultyNormal",
    "difficultyHeroic",
    "difficultyMythic",
    "difficultyMythicPlus",
    "generalPlaystyle1",
    "generalPlaystyle2",
    "generalPlaystyle3",
    "generalPlaystyle4",
}

local OWNED_FILTER_BOOLEAN_KEYS = {
    "needsTank",
    "needsHealer",
    "needsDamage",
    "hasTank",
    "hasHealer",
}

local function IsSecret(value)
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then return true end
    if type(issecretvalue) == "function" and issecretvalue(value) then return true end
    if type(issecrettable) == "function" and type(value) == "table" then
        local ok, secret = pcall(issecrettable, value)
        if not ok or secret then return true end
    end
    return false
end

local function SafeNumber(value, fallback)
    if IsSecret(value) or value == nil then return fallback end
    local number = tonumber(value)
    if IsSecret(number) or number == nil then return fallback end
    return number
end

local function SafeString(value, fallback)
    if IsSecret(value) or value == nil or type(value) ~= "string" then return fallback end
    return value
end

local function SafeBoolean(value, fallback)
    if IsSecret(value) or value == nil then return fallback end
    return value == true
end

local function IsChatRestricted()
    local restrictionType = Enum and Enum.AddOnRestrictionType
        and Enum.AddOnRestrictionType.Chat or 5
    local inactiveState = Enum and Enum.AddOnRestrictionState
        and Enum.AddOnRestrictionState.Inactive or 0

    if chatRestrictionState ~= nil and chatRestrictionState ~= inactiveState then
        return true
    end
    if not C_RestrictedActions then return false end

    if C_RestrictedActions.GetAddOnRestrictionState then
        local ok, state = pcall(
            C_RestrictedActions.GetAddOnRestrictionState, restrictionType
        )
        if ok and not IsSecret(state) and state ~= nil then
            return state ~= inactiveState
        end
    end
    if C_RestrictedActions.IsAddOnRestrictionActive then
        local ok, active = pcall(
            C_RestrictedActions.IsAddOnRestrictionActive, restrictionType
        )
        return ok and not IsSecret(active) and active == true
    end
    return false
end

local function IsCombatLocked()
    if not InCombatLockdown then return false end
    local ok, locked = pcall(InCombatLockdown)
    return ok and not IsSecret(locked) and locked == true
end

local function Clamp(value, minimum, maximum)
    value = SafeNumber(value, minimum) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function CopyArray(source)
    local copy = {}
    if IsSecret(source) or type(source) ~= "table" then return copy end
    for index = 1, #source do copy[index] = source[index] end
    return copy
end

local function AddSeasonMapID(mapIDs, seen, mapID)
    mapID = SafeNumber(mapID, nil)
    if not mapID then return end
    mapID = math.floor(mapID)
    if mapID <= 0 or seen[mapID] then return end
    seen[mapID] = true
    mapIDs[#mapIDs + 1] = mapID
end

local function BuildSeasonDungeonData()
    local mapIDs, seen = {}, {}
    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local ok, runtimeMaps = pcall(C_ChallengeMode.GetMapTable)
        if ok and not IsSecret(runtimeMaps) and type(runtimeMaps) == "table" then
            for _, mapID in ipairs(runtimeMaps) do AddSeasonMapID(mapIDs, seen, mapID) end
        end
    end

    if #mapIDs == 0 then
        for _, mapID in ipairs(CURRENT_SEASON_MAP_ORDER) do
            AddSeasonMapID(mapIDs, seen, mapID)
        end
    elseif #mapIDs < MAX_SEASON_DUNGEONS then
        for _, mapID in ipairs(CURRENT_SEASON_MAP_ORDER) do
            AddSeasonMapID(mapIDs, seen, mapID)
        end
    end

    table.sort(mapIDs, function(left, right)
        local leftOrder = MAP_ORDER_INDEX[left] or 1000 + left
        local rightOrder = MAP_ORDER_INDEX[right] or 1000 + right
        if leftOrder ~= rightOrder then return leftOrder < rightOrder end
        return left < right
    end)

    local data = {}
    for index = 1, math.min(#mapIDs, MAX_SEASON_DUNGEONS) do
        local mapID = mapIDs[index]
        local name = string.format("Map %d", mapID)
        local texture = DEFAULT_DUNGEON_ICON
        if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            local ok, runtimeName, _, _, runtimeTexture =
                pcall(C_ChallengeMode.GetMapUIInfo, mapID)
            if ok then
                name = SafeString(runtimeName, name) or name
                texture = SafeNumber(runtimeTexture, nil)
                    or SafeString(runtimeTexture, DEFAULT_DUNGEON_ICON)
                    or DEFAULT_DUNGEON_ICON
            end
        end
        data[#data + 1] = {
            mapID = mapID,
            activityGroupID = CURRENT_SEASON_ACTIVITY_GROUPS[mapID],
            name = name,
            texture = texture,
        }
    end
    return data
end

local function GetSeasonDungeons()
    if #seasonDungeons == 0 then seasonDungeons = BuildSeasonDungeonData() end
    return seasonDungeons
end

local function IsDungeonSelected(db, mapID)
    if not db or type(db.selectedDungeons) ~= "table" then return false end
    mapID = SafeNumber(mapID, nil)
    return mapID ~= nil and db.selectedDungeons[tostring(math.floor(mapID))] == true
end

local function HasDungeonSelection(db)
    for _, dungeon in ipairs(GetSeasonDungeons()) do
        if IsDungeonSelected(db, dungeon.mapID) then return true end
    end
    return false
end

local function GetMemberCounts(resultID)
    if IsSecret(resultID) or not C_LFGList
        or not C_LFGList.GetSearchResultMemberCounts then
        return {}, false
    end
    local ok, counts = pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
    if not ok or IsSecret(counts) or type(counts) ~= "table" then return {}, false end
    return counts, true
end

local function GetMemberCount(source, key)
    if IsSecret(source) or type(source) ~= "table" then return 0 end
    return math.max(0, SafeNumber(source[key], 0) or 0)
end

local function MemberCountsHaveBloodlust(counts)
    if IsSecret(counts) or type(counts) ~= "table" then return nil end
    local classesByRole = counts.classesByRole
    if IsSecret(classesByRole) or type(classesByRole) ~= "table" then return nil end

    for rawRole, roleClasses in pairs(classesByRole) do
        if IsSecret(rawRole) or IsSecret(roleClasses) or type(roleClasses) ~= "table" then
            return nil
        end
        for rawClassToken, rawCount in pairs(roleClasses) do
            if IsSecret(rawClassToken) or IsSecret(rawCount) then return nil end
            local classToken = SafeString(rawClassToken, nil)
            local count = SafeNumber(rawCount, 0) or 0
            classToken = classToken and string.upper(classToken) or nil
            if classToken and BLOODLUST_CLASSES[classToken] and count > 0 then
                return true
            end
        end
    end
    return false
end

local function SearchingPartyHasBloodlust()
    if not UnitExists or not UnitClass then return false end
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        local okExists, exists = pcall(UnitExists, unit)
        if okExists and not IsSecret(exists) and exists == true then
            local okClass, _, classToken = pcall(UnitClass, unit)
            classToken = okClass and SafeString(classToken, nil) or nil
            if classToken and BLOODLUST_CLASSES[classToken] then return true end
        end
    end
    return false
end

local function GetApplicationState(resultID, searchResultInfo)
    if IsSecret(resultID) or not C_LFGList or not C_LFGList.GetApplicationInfo then
        return false, false
    end

    local ok, _, appStatus, pendingStatus = pcall(C_LFGList.GetApplicationInfo, resultID)
    if not ok then return false, false end
    appStatus = SafeString(appStatus, "none") or "none"
    pendingStatus = SafeString(pendingStatus, nil)

    local declined = appStatus:find("^declined") ~= nil
    if not declined and type(searchResultInfo) == "table" then
        local partyGUID = SafeString(searchResultInfo.partyGUID, nil)
        local declines = _G.LFGListFrame and LFGListFrame.declines
        local remembered = partyGUID and type(declines) == "table"
            and SafeString(declines[partyGUID], nil) or nil
        if remembered and remembered:find("^declined") then declined = true end
    end

    local pending = pendingStatus ~= nil and pendingStatus ~= "cancelled"
    return appStatus ~= "none" or pending, declined
end

local function GetPlayerSpecializationRole()
    if not GetSpecialization or not GetSpecializationRole then return nil end
    local specIndex = GetSpecialization()
    if IsSecret(specIndex) or specIndex == nil then return nil end
    local role = SafeString(GetSpecializationRole(specIndex), nil)
    if ROLE_SORT_ORDER[role] and role ~= "NONE" then return role end
    return nil
end

local function GetSearchingPartyRoles()
    local roles = { TANK = 0, HEALER = 0, DAMAGER = 0, total = 0 }
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        local okExists, exists = pcall(UnitExists, unit)
        if okExists and not IsSecret(exists) and exists == true then
            roles.total = roles.total + 1
            local role
            if UnitGroupRolesAssigned then
                local okRole, assignedRole = pcall(UnitGroupRolesAssigned, unit)
                role = okRole and SafeString(assignedRole, nil) or nil
            end
            if unit == "player" and (not role or role == "NONE") then
                role = GetPlayerSpecializationRole()
            end
            if role and roles[role] ~= nil then roles[role] = roles[role] + 1 end
        end
    end

    if roles.total == 0 then
        roles.total = 1
        local role = GetPlayerSpecializationRole()
        if role then roles[role] = 1 end
    end
    return roles
end

local function GetBloodlustStatus(counts, listingMembers, partyRoles, partyHasBloodlust)
    local listingHasBloodlust = MemberCountsHaveBloodlust(counts)
    if listingHasBloodlust == nil then return nil end
    if partyHasBloodlust or listingHasBloodlust then return "PRESENT" end

    listingMembers = math.max(0, SafeNumber(listingMembers, 0) or 0)
    if partyRoles.total + listingMembers > 5 then return "MISSING" end

    local healerCount = partyRoles.HEALER + GetMemberCount(counts, "HEALER")
    local damageCount = partyRoles.DAMAGER
        + GetMemberCount(counts, "DAMAGER")
        + GetMemberCount(counts, "NOROLE")
    if healerCount < 1 or damageCount < 3 then return "FLEX" end
    return "MISSING"
end

local function GetMapBest(searchResultInfo)
    if IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then return 0, false end
    local best = 0
    local valid = true

    local function ReadScoreInfo(scoreInfo)
        if IsSecret(scoreInfo) then
            valid = false
            return
        end
        if scoreInfo == nil then return end
        if type(scoreInfo) ~= "table" then
            valid = false
            return
        end
        local rawDirect = scoreInfo.bestRunLevel
        if IsSecret(rawDirect) then valid = false end
        local direct = math.max(0, SafeNumber(rawDirect, 0) or 0)
        if direct > best then best = direct end
        for _, entry in pairs(scoreInfo) do
            if IsSecret(entry) then
                valid = false
            elseif type(entry) == "table" then
                local rawLevel = entry.bestRunLevel
                if IsSecret(rawLevel) then valid = false end
                local level = math.max(0, SafeNumber(rawLevel, 0) or 0)
                if level > best then best = level end
            end
        end
    end

    ReadScoreInfo(searchResultInfo.leaderDungeonScoreInfo)
    ReadScoreInfo(searchResultInfo.leaderBestDungeonScoreInfo)
    return best, valid
end

local function AddSpecializationLookupEntry(lookup, classToken, classID, specIndex, sex)
    if not GetSpecializationInfoForClassID then return end
    local ok, specID, specName, description, specIcon
    if sex then
        ok, specID, specName, description, specIcon =
            pcall(GetSpecializationInfoForClassID, classID, specIndex, sex)
    else
        ok, specID, specName, description, specIcon =
            pcall(GetSpecializationInfoForClassID, classID, specIndex)
    end
    if not ok then return end

    specName = SafeString(specName, nil)
    specIcon = SafeNumber(specIcon, nil)
    if classToken and specName and specIcon then
        lookup[classToken .. "\031" .. specName] = specIcon
    end
end

local function GetSpecializationLookup()
    if specializationLookup then return specializationLookup end
    specializationLookup = {}
    if not GetClassInfo or not GetSpecializationInfoForClassID then
        return specializationLookup
    end

    local numClasses = 13
    if GetNumClasses then
        local ok, value = pcall(GetNumClasses)
        if ok then numClasses = math.floor(Clamp(value, 1, 32)) end
    end
    local getSpecCount = (C_SpecializationInfo
        and C_SpecializationInfo.GetNumSpecializationsForClassID)
        or GetNumSpecializationsForClassID
    if not getSpecCount then return specializationLookup end

    for classID = 1, numClasses do
        local ok, _, classToken = pcall(GetClassInfo, classID)
        classToken = ok and SafeString(classToken, nil) or nil
        if classToken then
            local countOK, count = pcall(getSpecCount, classID)
            count = countOK and math.floor(Clamp(count, 0, 8)) or 0
            for specIndex = 1, count do
                AddSpecializationLookupEntry(specializationLookup, classToken, classID, specIndex)
                AddSpecializationLookupEntry(specializationLookup, classToken, classID, specIndex, 2)
                AddSpecializationLookupEntry(specializationLookup, classToken, classID, specIndex, 3)
            end
        end
    end
    return specializationLookup
end

local function GetClassSortIndex(classToken)
    if type(CLASS_SORT_ORDER) ~= "table" then return 99 end
    for index, token in ipairs(CLASS_SORT_ORDER) do
        if token == classToken then return index end
    end
    return 99
end

local function GetRoleClassOrder(resultID)
    local order = {}
    local counts = GetMemberCounts(resultID)
    local classesByRole = not IsSecret(counts) and type(counts) == "table"
        and counts.classesByRole or nil
    local roleOrder = type(LFG_LIST_GROUP_DATA_ROLE_ORDER) == "table"
        and LFG_LIST_GROUP_DATA_ROLE_ORDER
        or { "TANK", "HEALER", "DAMAGER" }

    for _, rawRole in ipairs(roleOrder) do
        local role = SafeString(rawRole, nil)
        if role then
            local classOrder = {}
            order[role] = classOrder
            local roleClasses = not IsSecret(classesByRole)
                and type(classesByRole) == "table"
                and classesByRole[role] or nil
            if not IsSecret(roleClasses) and type(roleClasses) == "table" then
                local index = 1
                for rawClassToken in pairs(roleClasses) do
                    local classToken = SafeString(rawClassToken, nil)
                    if classToken then
                        classOrder[classToken] = index
                        index = index + 1
                    end
                end
            end
        end
    end
    return order
end

local function BuildSpecializationMembers(resultID, memberCount)
    local members = {}
    local lookup = GetSpecializationLookup()
    local roleClassOrder = GetRoleClassOrder(resultID)
    memberCount = math.floor(Clamp(memberCount, 0, 5))

    for memberIndex = 1, memberCount do
        local member = {
            originalIndex = memberIndex,
            role = "NONE",
            classOrder = 99,
        }
        local ok, playerInfo = pcall(
            C_LFGList.GetSearchResultPlayerInfo, resultID, memberIndex
        )
        if ok and not IsSecret(playerInfo) and type(playerInfo) == "table" then
            local role = SafeString(playerInfo.assignedRole, "NONE") or "NONE"
            local classToken = SafeString(playerInfo.classFilename, nil)
            local specName = SafeString(playerInfo.specName, nil)
            member.role = ROLE_SORT_ORDER[role] and role or "NONE"
            member.classToken = classToken
            local roleOrder = roleClassOrder[member.role]
            member.classOrder = roleOrder and roleOrder[classToken]
                or GetClassSortIndex(classToken)
            member.isLeader = SafeBoolean(playerInfo.isLeader, false)
            if classToken and specName then
                member.specIcon = lookup[classToken .. "\031" .. specName]
            end
        end
        members[#members + 1] = member
    end

    table.sort(members, function(left, right)
        local leftRole = ROLE_SORT_ORDER[left.role] or ROLE_SORT_ORDER.NONE
        local rightRole = ROLE_SORT_ORDER[right.role] or ROLE_SORT_ORDER.NONE
        if leftRole ~= rightRole then return leftRole < rightRole end
        if left.classOrder ~= right.classOrder then return left.classOrder < right.classOrder end
        return left.originalIndex < right.originalIndex
    end)
    return members
end

local function BuildDungeonCompositionSlots(members)
    local slots = {}
    local overflow = {}

    for index, role in ipairs(DUNGEON_COMPOSITION_ROLES) do
        slots[index] = { role = role }
    end

    for _, member in ipairs(members) do
        local assigned = false
        if member.role ~= "NONE" then
            for _, slot in ipairs(slots) do
                if not slot.member and slot.role == member.role then
                    slot.member = member
                    assigned = true
                    break
                end
            end
        end
        if not assigned then overflow[#overflow + 1] = member end
    end

    local nextEmpty = 1
    for _, member in ipairs(overflow) do
        while slots[nextEmpty] and slots[nextEmpty].member do
            nextEmpty = nextEmpty + 1
        end
        if slots[nextEmpty] then slots[nextEmpty].member = member end
    end

    return slots
end

local function SetEmptyRoleSlot(frame, role, isDelisted)
    local coords = EMPTY_ROLE_TEXCOORDS[role] or EMPTY_ROLE_TEXCOORDS.DAMAGER
    local iconAlpha = isDelisted and 0.26 or 0.52
    local borderAlpha = isDelisted and 0.24 or 0.55

    frame.border:SetShown(true)
    frame.border:SetColorTexture(0.20, 0.24, 0.30, borderAlpha)
    frame.icon:ClearAllPoints()
    frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.icon:SetTexture(EMPTY_ROLE_TEXTURE)
    frame.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    frame.icon:SetDesaturated(true)
    frame.icon:SetVertexColor(0.76, 0.82, 0.90, 1)
    frame.icon:SetAlpha(iconAlpha)
    frame.crown:Hide()
    frame:Show()
end

local function HideSpecializationRow(row)
    local frames = specializationRows[row]
    if not frames then return end
    for _, frame in pairs(frames) do frame:Hide() end
end

local function GetSpecializationFrames(row, defaultIcons)
    local frames = specializationRows[row]
    if not frames then
        frames = {}
        specializationRows[row] = frames
    end

    for iconIndex, defaultIcon in ipairs(defaultIcons) do
        local frame = frames[iconIndex]
        if not frame then
            frame = CreateFrame("Frame", nil, row)
            frame:EnableMouse(false)
            frame:SetFrameLevel((row:GetFrameLevel() or 1) + 12)

            frame.border = frame:CreateTexture(nil, "ARTWORK")
            frame.border:SetAllPoints()

            frame.icon = frame:CreateTexture(nil, "OVERLAY")
            frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            frame.crown = frame:CreateTexture(nil, "OVERLAY", nil, 2)
            frame.crown:SetSize(10, 6)
            frame.crown:SetPoint("TOP", frame, "TOP", 0, 3)
            frame.crown:SetAtlas("groupfinder-icon-leader", false, "LINEAR")

            frames[iconIndex] = frame
        end
        frame:ClearAllPoints()
        frame:SetAllPoints(defaultIcon)
        frame:Hide()
    end
    for iconIndex = #defaultIcons + 1, #frames do frames[iconIndex]:Hide() end
    return frames
end

local function GetClassColor(classToken)
    local color
    if classToken and C_ClassColor and C_ClassColor.GetClassColor then
        color = C_ClassColor.GetClassColor(classToken)
    end
    if not color and classToken and type(RAID_CLASS_COLORS) == "table" then
        color = RAID_CLASS_COLORS[classToken]
    end
    if IsSecret(color) or type(color) ~= "table" then return 0.25, 0.28, 0.35 end
    return SafeNumber(color.r, 0.25) or 0.25,
        SafeNumber(color.g, 0.28) or 0.28,
        SafeNumber(color.b, 0.35) or 0.35
end

local function CreateText(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT, size, "OUTLINE")
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetJustifyV("MIDDLE")
    return text
end

local function HideLeaderScoreRow(row)
    local frame = leaderScoreRows[row]
    if frame then frame:Hide() end
end

local function GetLeaderScoreFrame(row)
    local frame = leaderScoreRows[row]
    if frame then return frame end

    frame = CreateFrame("Frame", nil, row)
    frame:SetSize(42, 30)
    frame:SetPoint("RIGHT", row, "RIGHT", -115, 0)
    frame:SetFrameLevel((row:GetFrameLevel() or 1) + 12)
    frame:EnableMouse(false)

    frame.rating = CreateText(frame, 10, { 1, 1, 1, 1 })
    frame.rating:SetPoint("TOPRIGHT", 0, -1)
    frame.rating:SetSize(42, 14)
    frame.rating:SetJustifyH("RIGHT")

    frame.best = CreateText(frame, 10, { 0.45, 0.88, 0.58, 1 })
    frame.best:SetPoint("BOTTOMRIGHT", 0, 1)
    frame.best:SetSize(42, 14)
    frame.best:SetJustifyH("RIGHT")

    leaderScoreRows[row] = frame
    return frame
end

local function HideResultAssistRow(row)
    local frame = resultAssistRows[row]
    if frame then frame:Hide() end
end

local function GetResultAssistFrame(row)
    local frame = resultAssistRows[row]
    if frame then return frame end

    frame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    frame:SetSize(24, 10)
    frame:SetPoint("TOPRIGHT", row, "TOPRIGHT", -115, -1)
    frame:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    frame:SetFrameLevel((row:GetFrameLevel() or 1) + 13)
    frame:EnableMouse(false)

    frame.blood = CreateText(frame, 8, { 0.72, 0.90, 0.74, 1 })
    frame.blood:SetSize(22, 9)
    frame.blood:SetPoint("CENTER")
    frame.blood:SetJustifyH("CENTER")

    resultAssistRows[row] = frame
    return frame
end

local function GetDungeonScoreColor(rating)
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        local ok, color = pcall(C_ChallengeMode.GetDungeonScoreRarityColor, rating)
        if ok and not IsSecret(color) and type(color) == "table" then
            return SafeNumber(color.r, 1) or 1,
                SafeNumber(color.g, 1) or 1,
                SafeNumber(color.b, 1) or 1
        end
    end
    return 1, 1, 1
end

local function SetGameTooltipTitle(text)
    GameTooltip:ClearLines()
    if GameTooltip_SetTitle then
        GameTooltip_SetTitle(GameTooltip, text, nil, true)
    else
        GameTooltip:SetText(text)
    end
end

local function SetTooltip(frame, text)
    if not frame or not text then return end
    frame:SetScript("OnEnter", function(self)
        if self.UpdateVisual then
            self.hovered = true
            self:UpdateVisual()
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        SetGameTooltipTitle(text)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if self.UpdateVisual then
            self.hovered = false
            self:UpdateVisual()
        end
        GameTooltip:Hide()
    end)
end

local function CreateToggleControl(parent, label, width, onToggle, tooltip)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 32)
    button:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    button:RegisterForClicks("LeftButtonUp")

    button.accent = button:CreateTexture(nil, "ARTWORK")
    button.accent:SetPoint("TOPLEFT", 0, -1)
    button.accent:SetPoint("BOTTOMLEFT", 0, 1)
    button.accent:SetWidth(3)

    button.label = CreateText(button, 12, P.text)
    button.label:SetPoint("LEFT", 12, 0)
    button.label:SetPoint("RIGHT", -8, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetText(label)

    function button:UpdateVisual()
        if self.active then
            self:SetBackdropColor(unpack(P.selected))
            self:SetBackdropBorderColor(unpack(P.accent))
            self.accent:SetColorTexture(unpack(P.accentStrong))
            self.label:SetTextColor(unpack(P.textBright))
        elseif self.hovered then
            self:SetBackdropColor(unpack(P.hover))
            self:SetBackdropBorderColor(unpack(P.border))
            self.accent:SetColorTexture(unpack(P.border))
            self.label:SetTextColor(unpack(P.text))
        else
            self:SetBackdropColor(unpack(P.control))
            self:SetBackdropBorderColor(unpack(P.borderSoft))
            self.accent:SetColorTexture(unpack(P.borderSoft))
            self.label:SetTextColor(unpack(P.textDim))
        end
    end

    function button:SetActive(active)
        self.active = active == true
        self:UpdateVisual()
    end

    button:SetScript("OnClick", function(self)
        onToggle(not self.active)
    end)
    button:SetActive(false)
    SetTooltip(button, tooltip or label)
    return button
end

local function CreateNumberControl(parent, label, width, maximum, onCommit)
    local control = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    control:SetSize(width, 36)
    control:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    control:SetBackdropColor(unpack(P.control))
    control:SetBackdropBorderColor(unpack(P.borderSoft))

    control.label = CreateText(control, 11, P.text)
    control.label:SetPoint("LEFT", 10, 0)
    control.label:SetPoint("RIGHT", -64, 0)
    control.label:SetJustifyH("LEFT")
    control.label:SetText(label)

    control.edit = CreateFrame("EditBox", nil, control, "BackdropTemplate")
    control.edit:SetSize(48, 24)
    control.edit:SetPoint("RIGHT", -6, 0)
    control.edit:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    control.edit:SetBackdropColor(unpack(P.input))
    control.edit:SetBackdropBorderColor(unpack(P.borderSoft))
    control.edit:SetFont(FONT, 12, "OUTLINE")
    control.edit:SetTextColor(unpack(P.textBright))
    control.edit:SetJustifyH("CENTER")
    control.edit:SetAutoFocus(false)
    control.edit:SetNumeric(true)
    control.edit:SetMaxLetters(4)

    local committing = false
    local function Commit(edit)
        if committing then return end
        if edit.cancelCommit then
            edit.cancelCommit = nil
            edit:SetText(tostring(control.value or 0))
            return
        end
        committing = true
        local value = math.floor(Clamp(edit:GetText(), 0, maximum))
        edit:ClearFocus()
        onCommit(value)
        committing = false
    end

    control.edit:SetScript("OnEnterPressed", Commit)
    control.edit:SetScript("OnEditFocusLost", Commit)
    control.edit:SetScript("OnEscapePressed", function(edit)
        edit.cancelCommit = true
        edit:ClearFocus()
    end)
    control.edit:SetScript("OnEditFocusGained", function(edit)
        edit:HighlightText()
        edit:SetBackdropBorderColor(unpack(P.accentStrong))
    end)

    function control:SetValue(value)
        value = math.floor(Clamp(value, 0, maximum))
        self.value = value
        if not self.edit:HasFocus() then self.edit:SetText(tostring(value)) end
        if value > 0 then
            self:SetBackdropBorderColor(unpack(P.accent))
            self.label:SetTextColor(unpack(P.text))
        else
            self:SetBackdropBorderColor(unpack(P.borderSoft))
            self.label:SetTextColor(unpack(P.textDim))
        end
        if not self.edit:HasFocus() then
            self.edit:SetBackdropBorderColor(unpack(P.borderSoft))
        end
    end

    return control
end

local function CreateSegmentButton(parent, label, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    button:RegisterForClicks("LeftButtonUp")

    button.label = CreateText(button, 11, P.textDim)
    button.label:SetPoint("CENTER")
    button.label:SetText(label)

    button.line = button:CreateTexture(nil, "ARTWORK")
    button.line:SetPoint("BOTTOMLEFT", 1, 1)
    button.line:SetPoint("BOTTOMRIGHT", -1, 1)
    button.line:SetHeight(2)

    function button:UpdateVisual()
        if self.active then
            self:SetBackdropColor(unpack(P.selected))
            self:SetBackdropBorderColor(unpack(P.accent))
            self.line:SetColorTexture(unpack(P.accentStrong))
            self.label:SetTextColor(unpack(P.textBright))
        elseif self.hovered then
            self:SetBackdropColor(unpack(P.hover))
            self:SetBackdropBorderColor(unpack(P.border))
            self.line:SetColorTexture(unpack(P.border))
            self.label:SetTextColor(unpack(P.text))
        else
            self:SetBackdropColor(unpack(P.control))
            self:SetBackdropBorderColor(unpack(P.borderSoft))
            self.line:SetColorTexture(unpack(P.borderSoft))
            self.label:SetTextColor(unpack(P.textDim))
        end
    end

    function button:SetActive(active)
        self.active = active == true
        self:UpdateVisual()
    end

    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        self.hovered = true
        self:UpdateVisual()
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        self:UpdateVisual()
    end)
    button:SetActive(false)
    if tooltip then SetTooltip(button, tooltip) end
    return button
end

local function CreateDungeonButton(parent, width, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 26)
    button:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    button:RegisterForClicks("LeftButtonUp")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("LEFT", 4, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.label = CreateText(button, 10, P.textDim)
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 5, 0)
    button.label:SetPoint("RIGHT", -4, 0)
    button.label:SetJustifyH("LEFT")
    if button.label.SetWordWrap then button.label:SetWordWrap(false) end

    function button:UpdateVisual()
        if self.active then
            self:SetBackdropColor(unpack(P.selected))
            self:SetBackdropBorderColor(unpack(P.accent))
            self.icon:SetAlpha(1)
            self.label:SetTextColor(unpack(P.textBright))
        elseif self.hovered then
            self:SetBackdropColor(unpack(P.hover))
            self:SetBackdropBorderColor(unpack(P.border))
            self.icon:SetAlpha(0.92)
            self.label:SetTextColor(unpack(P.text))
        else
            self:SetBackdropColor(unpack(P.control))
            self:SetBackdropBorderColor(unpack(P.borderSoft))
            self.icon:SetAlpha(0.72)
            self.label:SetTextColor(unpack(P.textDim))
        end
    end

    function button:SetActive(active)
        self.active = active == true
        self:UpdateVisual()
    end

    function button:SetDungeon(dungeon)
        if not dungeon then
            self.mapID = nil
            self.fullName = nil
            self:Hide()
            return
        end
        self.mapID = dungeon.mapID
        self.fullName = dungeon.name
        self.icon:SetTexture(dungeon.texture or DEFAULT_DUNGEON_ICON)
        self.label:SetText(dungeon.name or "?")
        self:Show()
    end

    button:SetScript("OnClick", function(self)
        if self.mapID then onClick(self.mapID, not self.active) end
    end)
    button:SetScript("OnEnter", function(self)
        self.hovered = true
        self:UpdateVisual()
        if self.fullName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            SetGameTooltipTitle(self.fullName)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        self:UpdateVisual()
        GameTooltip:Hide()
    end)
    button:SetActive(false)
    return button
end

local function CreateSectionLabel(parent, label)
    local text = CreateText(parent, 10, P.accentText)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    return text
end

function PremadeGroupFilter:NormalizeDatabase()
    if not self.db then return end

    local revision = SafeNumber(self.db.uiRevision, 0) or 0
    if revision < 2 then
        self.db.needMyRole = false
        self.db.requireTank = false
        self.db.requireHealer = false
        self.db.minLeaderRating = 0
        self.db.minMapBest = 0
        self.db.sortMode = "DEFAULT"
    end
    if revision < 4 then self.db.bloodlustFit = false end
    if revision < 5 then
        self.db.minMapBest = 0
    end

    if type(self.db.selectedDungeons) ~= "table" then self.db.selectedDungeons = {} end
    if self.db.showLeaderScore == nil then self.db.showLeaderScore = true end
    self.db.uiRevision = 5
    if not VALID_SORT_MODES[self.db.sortMode] then self.db.sortMode = "DEFAULT" end
    for _, key in ipairs(OBSOLETE_DB_KEYS) do self.db[key] = nil end
end

local function CopyAdvancedFilterOptions(source)
    if IsSecret(source) or type(source) ~= "table" then return nil end

    local copy = {}
    for _, key in ipairs(ADVANCED_FILTER_BOOLEAN_KEYS) do
        copy[key] = SafeBoolean(source[key], false) == true
    end
    copy.minimumRating = math.max(0, SafeNumber(source.minimumRating, 0) or 0)
    copy.activities = CopyArray(source.activities)
    return copy
end

local function GetNativeFilterOptions()
    if not C_LFGList or not C_LFGList.GetAdvancedFilter then
        return nil
    end
    local ok, options = pcall(C_LFGList.GetAdvancedFilter)
    if not ok then return nil end
    return CopyAdvancedFilterOptions(options)
end

local function BuildSelectedActivityGroups(db)
    local groups, seen = {}, {}
    if not HasDungeonSelection(db) then return groups end

    for _, dungeon in ipairs(GetSeasonDungeons()) do
        local groupID = SafeNumber(dungeon.activityGroupID, nil)
        if groupID and IsDungeonSelected(db, dungeon.mapID) then
            groupID = math.floor(groupID)
            if groupID > 0 and not seen[groupID] then
                seen[groupID] = true
                groups[#groups + 1] = groupID
            end
        end
    end
    table.sort(groups)
    return groups
end

local function CaptureOwnedNativeFilter(options)
    local backup = {
        activities = CopyArray(options.activities),
        minimumRating = math.max(0, SafeNumber(options.minimumRating, 0) or 0),
    }
    for _, key in ipairs(OWNED_FILTER_BOOLEAN_KEYS) do
        backup[key] = options[key] == true
    end
    return backup
end

local function ApplyOwnedNativeFilter(options, db)
    for _, key in ipairs({ "needsTank", "needsHealer", "needsDamage" }) do
        options[key] = false
    end
    if db.needMyRole == true then
        local role = GetPlayerSpecializationRole()
        if role == "TANK" then
            options.needsTank = true
        elseif role == "HEALER" then
            options.needsHealer = true
        elseif role == "DAMAGER" then
            options.needsDamage = true
        end
    end

    options.hasTank = db.requireTank == true
    options.hasHealer = db.requireHealer == true
    options.minimumRating = math.floor(Clamp(db.minLeaderRating or 0, 0, 5000))
    options.activities = BuildSelectedActivityGroups(db)
end

local function RestoreOwnedNativeFilter(options, backup)
    backup = type(backup) == "table" and backup or {}
    for _, key in ipairs(OWNED_FILTER_BOOLEAN_KEYS) do
        options[key] = backup[key] == true
    end
    options.minimumRating = math.max(0, SafeNumber(backup.minimumRating, 0) or 0)
    options.activities = CopyArray(backup.activities)
end

local function SaveNativeFilterOptions(options)
    if not options or not C_LFGList or not C_LFGList.SaveAdvancedFilter then
        return false
    end
    return pcall(C_LFGList.SaveAdvancedFilter, options)
end

function PremadeGroupFilter:RefreshResultCount()
    if IsChatRestricted() or not C_LFGList or not C_LFGList.GetFilteredSearchResults then
        return
    end

    local ok, total, results = pcall(C_LFGList.GetFilteredSearchResults)
    if not ok or IsSecret(results) or type(results) ~= "table" then return end
    local filteredCount = #results
    lastMatchCount = filteredCount
    lastTotalCount = math.max(filteredCount, SafeNumber(total, filteredCount) or filteredCount)
    self:RefreshPanel()
end

local function CopySafeResultIDs(source)
    if IsSecret(source) or type(source) ~= "table" then return nil end
    local copy = {}
    for index = 1, #source do
        local resultID = SafeNumber(source[index], nil)
        if not resultID then return nil end
        copy[index] = math.floor(resultID)
    end
    return copy
end

local function ContainsSecretValue(source, depth)
    if IsSecret(source) then return true end
    if type(source) ~= "table" or depth <= 0 then return false end
    for key, value in pairs(source) do
        if IsSecret(key) or IsSecret(value) then return true end
        if type(value) == "table" and ContainsSecretValue(value, depth - 1) then
            return true
        end
    end
    return false
end

local function CanSafelyRenderResult(resultID, searchResultInfo)
    if IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then return false end
    for _, key in ipairs(SEARCH_INFO_RENDER_KEYS) do
        if IsSecret(searchResultInfo[key]) then return false end
    end

    local activityIDs = searchResultInfo.activityIDs
    if type(activityIDs) ~= "table" or #activityIDs == 0
        or ContainsSecretValue(activityIDs, 1) then
        return false
    end
    if not C_LFGList or not C_LFGList.GetApplicationInfo then return false end

    local counts, countsValid = GetMemberCounts(resultID)
    if not countsValid or ContainsSecretValue(counts, 3) then return false end

    local ok, applicationID, appStatus, pendingStatus, appDuration =
        pcall(C_LFGList.GetApplicationInfo, resultID)
    if not ok or IsSecret(applicationID) or IsSecret(appStatus)
        or IsSecret(pendingStatus) or IsSecret(appDuration) then
        return false
    end
    return true
end

local function CanSafelyRefreshRows(order)
    if type(order) ~= "table" or #order == 0 then return true end
    if not C_LFGList or not C_LFGList.GetSearchResultInfo then return false end
    local resultID = SafeNumber(order[1], nil)
    if not resultID then return false end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    return ok and CanSafelyRenderResult(resultID, info)
end

local function CanSafelyRefreshSearchPanel(searchPanel, order)
    if not searchPanel or IsSecret(searchPanel.applications)
        or type(searchPanel.applications) ~= "table"
        or ContainsSecretValue(searchPanel.applications, 1)
        or not CanSafelyRefreshRows(order) then
        return false
    end

    for _, rawResultID in ipairs(searchPanel.applications) do
        local resultID = SafeNumber(rawResultID, nil)
        if not resultID then return false end
        local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
        if not ok or not CanSafelyRenderResult(resultID, info) then return false end
    end

    local selectedResult = searchPanel.selectedResult
    if IsSecret(selectedResult) then return false end
    if selectedResult ~= nil then
        selectedResult = SafeNumber(selectedResult, nil)
        if not selectedResult then return false end
        local ok, info = pcall(C_LFGList.GetSearchResultInfo, selectedResult)
        if not ok or not CanSafelyRenderResult(selectedResult, info) then return false end
    end
    return true
end

function PremadeGroupFilter:CaptureNativeResultOrder(searchPanel)
    if not searchPanel then return false end
    local copy = CopySafeResultIDs(searchPanel.results)
    if not copy then return false end
    nativeResultOrder = copy
    return true
end

function PremadeGroupFilter:BuildDisplayOrder(baseOrder)
    if IsChatRestricted() or IsCombatLocked() or not self.enabled or not self.db
        or not C_LFGList or not C_LFGList.GetSearchResultInfo then
        return nil
    end

    baseOrder = CopySafeResultIDs(baseOrder)
    if not baseOrder then return nil end
    local sortMode = VALID_SORT_MODES[self.db.sortMode] and self.db.sortMode or "DEFAULT"
    local sortBloodlust = self.db.bloodlustFit == true
    local partyRoles = sortBloodlust and GetSearchingPartyRoles() or nil
    local partyHasBloodlust = sortBloodlust and SearchingPartyHasBloodlust() or false
    local records = {}

    for index, resultID in ipairs(baseOrder) do
        local infoOK, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
        if not infoOK or IsSecret(info) or type(info) ~= "table" then return nil end
        for _, key in ipairs(SEARCH_INFO_RENDER_KEYS) do
            if IsSecret(info[key]) then return nil end
        end
        if index == 1 and not CanSafelyRenderResult(resultID, info) then return nil end

        local record = { id = resultID, originalIndex = index, rating = 0, mapBest = 0 }
        if sortMode == "RATING" or sortMode == "MAPBEST" then
            local rawRating = info.leaderOverallDungeonScore
            if IsSecret(rawRating) then return nil end
            record.rating = math.max(0, SafeNumber(rawRating, 0) or 0)
        end
        if sortMode == "MAPBEST" then
            local validBest
            record.mapBest, validBest = GetMapBest(info)
            if not validBest then return nil end
        end
        if sortBloodlust then
            local counts, countsValid = GetMemberCounts(resultID)
            if not countsValid or ContainsSecretValue(counts, 3) then return nil end
            local rawMembers = info.numMembers
            if IsSecret(rawMembers) then return nil end
            local status = GetBloodlustStatus(
                counts,
                SafeNumber(rawMembers, 0) or 0,
                partyRoles,
                partyHasBloodlust
            )
            record.bloodlustOrder = status and BLOODLUST_SORT_ORDER[status] or nil
            if not record.bloodlustOrder then return nil end
        end
        records[#records + 1] = record
    end

    if sortBloodlust or sortMode ~= "DEFAULT" then
        table.sort(records, function(left, right)
            if sortBloodlust and left.bloodlustOrder ~= right.bloodlustOrder then
                return left.bloodlustOrder < right.bloodlustOrder
            end
            if sortMode == "RATING" and left.rating ~= right.rating then
                return left.rating > right.rating
            end
            if sortMode == "MAPBEST" then
                if left.mapBest ~= right.mapBest then return left.mapBest > right.mapBest end
                if left.rating ~= right.rating then return left.rating > right.rating end
            end
            return left.originalIndex < right.originalIndex
        end)
    end

    local order = {}
    for index, record in ipairs(records) do order[index] = record.id end
    if not CanSafelyRefreshRows(order) then return nil end
    return order
end

function PremadeGroupFilter:ApplyDisplayOrder(searchPanel, baseOrder)
    if not searchPanel or IsSecret(searchPanel.results)
        or type(searchPanel.results) ~= "table" then
        return false
    end
    local currentOrder = CopySafeResultIDs(searchPanel.results)
    if not currentOrder then return false end
    local order = self:BuildDisplayOrder(baseOrder or currentOrder)
    if not order or #order ~= #currentOrder then return false end
    if not CanSafelyRefreshSearchPanel(searchPanel, order) then return false end
    local changed = false
    for index, resultID in ipairs(order) do
        if currentOrder[index] ~= resultID then
            changed = true
            break
        end
    end
    if not changed then return true, false end
    for index, resultID in ipairs(order) do searchPanel.results[index] = resultID end
    return true, true
end

function PremadeGroupFilter:RefreshCurrentDisplayOrder()
    if IsChatRestricted() or IsCombatLocked() or not self.enabled then return false end
    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
    if categoryID ~= CATEGORY_DUNGEON then return false end

    local baseOrder = #nativeResultOrder > 0 and nativeResultOrder
        or (searchPanel and searchPanel.results)
    local applied, changed = self:ApplyDisplayOrder(searchPanel, baseOrder)
    if not applied then return false end
    if not changed then return true end
    if not LFGListSearchPanel_UpdateResults then return false end
    local ok = pcall(LFGListSearchPanel_UpdateResults, searchPanel)
    return ok == true
end

function PremadeGroupFilter:RestoreCurrentDisplayOrder()
    if IsChatRestricted() or IsCombatLocked() then return false end
    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local currentOrder = searchPanel and CopySafeResultIDs(searchPanel.results) or nil
    local baseOrder = CopySafeResultIDs(nativeResultOrder)
    if not currentOrder or not baseOrder or #currentOrder ~= #baseOrder
        or not CanSafelyRefreshSearchPanel(searchPanel, baseOrder) then
        return false
    end

    local changed = false
    for index, resultID in ipairs(baseOrder) do
        if currentOrder[index] ~= resultID then changed = true break end
    end
    if not changed then return true end
    for index, resultID in ipairs(baseOrder) do searchPanel.results[index] = resultID end
    if not LFGListSearchPanel_UpdateResults then return false end
    return pcall(LFGListSearchPanel_UpdateResults, searchPanel)
end

local function BuildFilteredNativeOrder(filteredOrder)
    local filtered = {}
    for _, resultID in ipairs(filteredOrder) do filtered[resultID] = true end

    local order, added = {}, {}
    for _, resultID in ipairs(nativeResultOrder) do
        if filtered[resultID] then
            order[#order + 1] = resultID
            added[resultID] = true
        end
    end
    for _, resultID in ipairs(filteredOrder) do
        if not added[resultID] then
            order[#order + 1] = resultID
            added[resultID] = true
        end
    end
    return order
end

local function WriteResultOrder(target, order)
    if IsSecret(target) or type(target) ~= "table" or type(order) ~= "table" then
        return false
    end

    local previousLength = #target
    for index, resultID in ipairs(order) do target[index] = resultID end
    for index = previousLength, #order + 1, -1 do target[index] = nil end
    return true
end

function PremadeGroupFilter:RefreshFilteredResultList()
    if IsChatRestricted() or IsCombatLocked() or not self.enabled or not self.db
        or not C_LFGList or not C_LFGList.GetFilteredSearchResults
        or not LFGListSearchPanel_UpdateResults then
        return false
    end

    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
    if categoryID ~= CATEGORY_DUNGEON or IsSecret(searchPanel.searching)
        or searchPanel.searching == true then
        return false
    end

    local currentOrder = CopySafeResultIDs(searchPanel.results)
    if not currentOrder then return false end
    local ok, totalResults, filteredResults = pcall(C_LFGList.GetFilteredSearchResults)
    if not ok or IsSecret(totalResults) then return false end
    local filteredOrder = CopySafeResultIDs(filteredResults)
    if not filteredOrder then return false end

    local baseOrder = BuildFilteredNativeOrder(filteredOrder)
    local displayOrder = self:BuildDisplayOrder(baseOrder)
    if not displayOrder or not CanSafelyRefreshSearchPanel(searchPanel, displayOrder) then
        return false
    end

    local previousNativeOrder = CopySafeResultIDs(nativeResultOrder) or {}
    local previousTotalResults = SafeNumber(searchPanel.totalResults, #currentOrder) or #currentOrder
    local previousMatchCount, previousTotalCount = lastMatchCount, lastTotalCount
    nativeResultOrder = CopySafeResultIDs(baseOrder) or {}
    if not WriteResultOrder(searchPanel.results, displayOrder) then
        nativeResultOrder = previousNativeOrder
        return false
    end

    local filteredCount = #displayOrder
    local totalCount = math.max(filteredCount, SafeNumber(totalResults, filteredCount) or filteredCount)
    searchPanel.totalResults = totalCount
    lastMatchCount = filteredCount
    lastTotalCount = totalCount

    local updateOK = pcall(LFGListSearchPanel_UpdateResults, searchPanel)
    if not updateOK then
        WriteResultOrder(searchPanel.results, currentOrder)
        searchPanel.totalResults = previousTotalResults
        nativeResultOrder = previousNativeOrder
        lastMatchCount, lastTotalCount = previousMatchCount, previousTotalCount
        return false
    end

    self:RefreshPanel()
    self:RefreshSpecializationRows()
    return true
end

function PremadeGroupFilter:RequestFilterResultRefresh()
    return self:RefreshFilteredResultList()
end

function PremadeGroupFilter:RequestNativeSearchRefresh()
    if IsChatRestricted() or IsCombatLocked()
        or type(securecallfunction) ~= "function"
        or type(LFGListSearchPanel_DoSearch) ~= "function" then
        return false
    end
    if type(issecurevariable) == "function"
        and not issecurevariable("LFGListSearchPanel_DoSearch") then
        return false
    end

    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
    if categoryID ~= CATEGORY_DUNGEON or IsSecret(searchPanel.searching)
        or searchPanel.searching == true then
        return false
    end
    return pcall(securecallfunction, LFGListSearchPanel_DoSearch, searchPanel)
end

function PremadeGroupFilter:QueueResultRefresh()
    if resultRefreshPending then return end
    resultRefreshPending = true

    local function Refresh()
        resultRefreshPending = false
        if not PremadeGroupFilter.enabled then return end
        if IsChatRestricted() or IsCombatLocked() then
            PremadeGroupFilter:HideAllSpecializationRows()
            PremadeGroupFilter:HideAllLeaderScoreRows()
            PremadeGroupFilter:HideAllResultAssistRows()
            return
        end
        PremadeGroupFilter:RequestFilterResultRefresh()
        PremadeGroupFilter:RefreshResultCount()
        PremadeGroupFilter:RefreshCurrentDisplayOrder()
        PremadeGroupFilter:RefreshSpecializationRows()
        PremadeGroupFilter:UpdatePanelVisibility()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Refresh)
    else
        Refresh()
    end
end

function PremadeGroupFilter:ApplyNativeFilters(requestSearch)
    if not self.enabled or not self.db or IsCombatLocked() then
        return false
    end
    local options = GetNativeFilterOptions()
    if not options then return false end

    local backup = not self.db.nativeFilterApplied
        and CaptureOwnedNativeFilter(options) or nil
    ApplyOwnedNativeFilter(options, self.db)
    if not SaveNativeFilterOptions(options) then return false end

    if backup then self.db.nativeFilterBackup = backup end
    self.db.nativeFilterApplied = true
    if requestSearch == true then self:RequestNativeSearchRefresh() end
    self:QueueResultRefresh()
    return true
end

function PremadeGroupFilter:RestoreNativeFilters(db)
    if not db or db.nativeFilterApplied ~= true then return false end
    local options = GetNativeFilterOptions()
    if not options then return false end

    RestoreOwnedNativeFilter(options, db.nativeFilterBackup)
    if not SaveNativeFilterOptions(options) then return false end

    db.nativeFilterApplied = nil
    db.nativeFilterBackup = nil
    return true
end

function PremadeGroupFilter:ApplyCurrentResults(requestSearch)
    return self:ApplyNativeFilters(requestSearch)
end

function PremadeGroupFilter:CaptureSearchResults()
    if not self.enabled or not self.db then return end
    self:QueueResultRefresh()
end

function PremadeGroupFilter:UpdateSetting(key, value)
    if not self.db then return end
    self.db[key] = value
    self:RefreshPanel()
    if key == "bloodlustFit" or key == "sortMode" then
        self:RefreshCurrentDisplayOrder()
        self:RefreshSpecializationRows()
        return
    end
    self:ApplyCurrentResults(true)
    self:RefreshSpecializationRows()
end

function PremadeGroupFilter:SetSortMode(mode)
    if not VALID_SORT_MODES[mode] then mode = "DEFAULT" end
    self:UpdateSetting("sortMode", mode)
end

function PremadeGroupFilter:ResetFilters()
    if not self.db then return end
    self.db.selectedDungeons = {}
    self.db.needMyRole = false
    self.db.bloodlustFit = false
    self.db.requireTank = false
    self.db.requireHealer = false
    self.db.minLeaderRating = 0
    self.db.minMapBest = 0
    self.db.sortMode = "DEFAULT"
    self:RefreshPanel()
    self:ApplyCurrentResults(true)
    self:RefreshCurrentDisplayOrder()
    self:RefreshSpecializationRows()
end

function PremadeGroupFilter:UpdateDungeonSelection(mapID, selected)
    if not self.db then return end
    mapID = SafeNumber(mapID, nil)
    if not mapID then return end
    if type(self.db.selectedDungeons) ~= "table" then self.db.selectedDungeons = {} end

    local key = tostring(math.floor(mapID))
    self.db.selectedDungeons[key] = selected == true and true or nil
    self:RefreshPanel()
    self:ApplyCurrentResults(true)
end

function PremadeGroupFilter:ClearDungeonSelection()
    if not self.db then return end
    self.db.selectedDungeons = {}
    self:RefreshPanel()
    self:ApplyCurrentResults(true)
end

function PremadeGroupFilter:RefreshSeasonDungeons()
    seasonDungeons = BuildSeasonDungeonData()
    if sidePanel and sidePanel.dungeonButtons then
        for index, button in ipairs(sidePanel.dungeonButtons) do
            button:SetDungeon(seasonDungeons[index])
        end
    end
    self:RefreshPanel()
    self:ApplyCurrentResults()
end

function PremadeGroupFilter:UpdateSpecializationRow(
    row, resultID, searchResultInfo, applied, declined
)
    if not row then return end
    HideSpecializationRow(row)
    if IsChatRestricted() or not self.enabled or not self.db
        or self.db.showSpecIcons == false then
        return
    end
    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
    if categoryID ~= CATEGORY_DUNGEON then return end
    if not C_LFGList or not C_LFGList.GetSearchResultInfo
        or not C_LFGList.GetSearchResultPlayerInfo then
        return
    end

    local enumerate = row.DataDisplay and row.DataDisplay.Enumerate
    local defaultIcons = enumerate and enumerate.Icons
    if IsSecret(defaultIcons) or type(defaultIcons) ~= "table" or #defaultIcons == 0 then return end
    if enumerate.IsShown and not enumerate:IsShown() then return end

    if resultID == nil then resultID = row.resultID end
    if IsSecret(resultID) or resultID == nil then return end
    if IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then
        local ok
        ok, searchResultInfo = pcall(C_LFGList.GetSearchResultInfo, resultID)
        if not ok or IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then return end
    end

    if applied == nil or declined == nil then
        applied, declined = GetApplicationState(resultID, searchResultInfo)
    end
    if applied or declined then return end

    local members = BuildSpecializationMembers(
        resultID, SafeNumber(searchResultInfo.numMembers, 0) or 0
    )
    if #members == 0 or #members > #defaultIcons then return end
    for _, member in ipairs(members) do
        if not member.specIcon then return end
    end

    local useDungeonComposition = #defaultIcons >= #DUNGEON_COMPOSITION_ROLES
    local displaySlots = {}
    if useDungeonComposition then
        displaySlots = BuildDungeonCompositionSlots(members)
    else
        for index, member in ipairs(members) do
            displaySlots[index] = { member = member }
        end
    end

    local frames = GetSpecializationFrames(row, defaultIcons)
    for displayIndex = 1, #displaySlots do
        local slotIndex = #defaultIcons - displayIndex + 1
        local defaultIcon = defaultIcons[slotIndex]
        if IsSecret(defaultIcon) or not defaultIcon or not frames[slotIndex] then
            HideSpecializationRow(row)
            return
        end
    end

    local isDelisted = SafeBoolean(searchResultInfo.isDelisted, false)
    local alpha = isDelisted and 0.45 or 1

    for displayIndex, displaySlot in ipairs(displaySlots) do
        local slotIndex = #defaultIcons - displayIndex + 1
        local frame = frames[slotIndex]

        local member = displaySlot.member
        if not member then
            SetEmptyRoleSlot(frame, displaySlot.role, isDelisted)
        else
            local showBorder = self.db.specIconClassBorder ~= false
            frame.border:SetShown(showBorder)
            frame.icon:ClearAllPoints()
            if showBorder then
                local red, green, blue = GetClassColor(member.classToken)
                if isDelisted then red, green, blue = 0.20, 0.22, 0.25 end
                frame.border:SetColorTexture(red, green, blue, alpha)
                frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
                frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            else
                frame.icon:SetAllPoints()
            end
            frame.icon:SetTexture(member.specIcon)
            frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            frame.icon:SetDesaturated(isDelisted)
            frame.icon:SetVertexColor(1, 1, 1, 1)
            frame.icon:SetAlpha(alpha)
            frame.crown:SetShown(
                self.db.specIconLeaderMarker ~= false and member.isLeader == true
            )
            frame.crown:SetDesaturated(isDelisted)
            frame.crown:SetAlpha(alpha)
            frame:Show()
        end
    end
end

function PremadeGroupFilter:UpdateLeaderScoreRow(
    row, resultID, searchResultInfo, applied, declined
)
    if not row then return end
    HideLeaderScoreRow(row)
    if not self.enabled or not self.db or self.db.showLeaderScore == false then return end
    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
    if categoryID ~= CATEGORY_DUNGEON then return end
    if not C_LFGList or not C_LFGList.GetSearchResultInfo then return end

    if resultID == nil then resultID = row.resultID end
    if IsSecret(resultID) or resultID == nil then return end
    if IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then
        local ok
        ok, searchResultInfo = pcall(C_LFGList.GetSearchResultInfo, resultID)
        if not ok or IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then return end
    end

    if applied == nil or declined == nil then
        applied, declined = GetApplicationState(resultID, searchResultInfo)
    end
    if applied or declined then return end

    local rating = math.max(0, SafeNumber(searchResultInfo.leaderOverallDungeonScore, 0) or 0)
    if rating <= 0 then return end
    local best = GetMapBest(searchResultInfo)
    local frame = GetLeaderScoreFrame(row)
    local isDelisted = SafeBoolean(searchResultInfo.isDelisted, false)
    local red, green, blue = GetDungeonScoreColor(rating)
    if isDelisted then red, green, blue = 0.50, 0.52, 0.56 end

    frame.rating:SetText(tostring(math.floor(rating + 0.5)))
    frame.rating:SetTextColor(red, green, blue, 1)
    frame.best:SetText(best > 0 and ("+" .. math.floor(best)) or "")
    frame.best:SetTextColor(
        isDelisted and 0.50 or 0.45,
        isDelisted and 0.52 or 0.88,
        isDelisted and 0.56 or 0.58,
        1
    )
    frame:Show()
end

function PremadeGroupFilter:UpdateResultAssistRow(
    row, resultID, searchResultInfo, applied, declined
)
    if not row then return end
    HideResultAssistRow(row)
    if IsChatRestricted() or IsCombatLocked() or not self.enabled or not self.db then
        return
    end

    local showBloodStatus = self.db.bloodlustFit == true
    if not showBloodStatus then return end

    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
    if categoryID ~= CATEGORY_DUNGEON then return end

    if resultID == nil then resultID = row.resultID end
    resultID = SafeNumber(resultID, nil)
    if not resultID then return end
    resultID = math.floor(resultID)

    if IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then
        if not C_LFGList or not C_LFGList.GetSearchResultInfo then return end
        local ok
        ok, searchResultInfo = pcall(C_LFGList.GetSearchResultInfo, resultID)
        if not ok or IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then
            return
        end
    end

    if applied == nil or declined == nil then
        applied, declined = GetApplicationState(resultID, searchResultInfo)
    end
    if applied or declined then return end

    local bloodStatus
    if showBloodStatus then
        local counts, countsValid = GetMemberCounts(resultID)
        if countsValid then
            bloodStatus = GetBloodlustStatus(
                counts,
                SafeNumber(searchResultInfo.numMembers, 0) or 0,
                GetSearchingPartyRoles(),
                SearchingPartyHasBloodlust()
            )
        end
    end

    if not bloodStatus then return end

    local frame = GetResultAssistFrame(row)
    frame.blood:SetText("")

    if bloodStatus == "PRESENT" then
        frame.blood:SetText("BL")
        frame.blood:SetTextColor(0.45, 0.90, 0.55, 1)
        frame:SetBackdropColor(0.04, 0.16, 0.08, 0.88)
        frame:SetBackdropBorderColor(0.22, 0.58, 0.30, 0.88)
    elseif bloodStatus == "FLEX" then
        frame.blood:SetText("BL+")
        frame.blood:SetTextColor(1.00, 0.78, 0.30, 1)
        frame:SetBackdropColor(0.18, 0.12, 0.03, 0.88)
        frame:SetBackdropBorderColor(0.66, 0.44, 0.12, 0.88)
    elseif bloodStatus == "MISSING" then
        frame.blood:SetText("BL-")
        frame.blood:SetTextColor(1.00, 0.42, 0.42, 1)
        frame:SetBackdropColor(0.18, 0.04, 0.04, 0.88)
        frame:SetBackdropBorderColor(0.64, 0.18, 0.18, 0.88)
    else
        frame:SetBackdropColor(unpack(P.control))
        frame:SetBackdropBorderColor(unpack(P.borderSoft))
    end
    frame:Show()
end

function PremadeGroupFilter:UpdateResultRow(row)
    if not row then return end
    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
    if IsChatRestricted() or IsCombatLocked() or categoryID ~= CATEGORY_DUNGEON
        or not self.enabled or not self.db
        or (self.db.showSpecIcons == false
            and self.db.showLeaderScore == false
            and self.db.bloodlustFit ~= true) then
        HideSpecializationRow(row)
        HideLeaderScoreRow(row)
        HideResultAssistRow(row)
        return
    end

    local resultID = row.resultID
    if IsSecret(resultID) or resultID == nil
        or not C_LFGList or not C_LFGList.GetSearchResultInfo then
        HideSpecializationRow(row)
        HideLeaderScoreRow(row)
        HideResultAssistRow(row)
        return
    end

    local ok, searchResultInfo = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if not ok or IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then
        HideSpecializationRow(row)
        HideLeaderScoreRow(row)
        HideResultAssistRow(row)
        return
    end
    local applied, declined = GetApplicationState(resultID, searchResultInfo)
    self:UpdateSpecializationRow(row, resultID, searchResultInfo, applied, declined)
    self:UpdateLeaderScoreRow(row, resultID, searchResultInfo, applied, declined)
    self:UpdateResultAssistRow(row, resultID, searchResultInfo, applied, declined)
end

function PremadeGroupFilter:HideAllSpecializationRows()
    for row in pairs(specializationRows) do HideSpecializationRow(row) end
end

function PremadeGroupFilter:HideAllLeaderScoreRows()
    for row in pairs(leaderScoreRows) do HideLeaderScoreRow(row) end
end

function PremadeGroupFilter:HideAllResultAssistRows()
    for row in pairs(resultAssistRows) do HideResultAssistRow(row) end
end

function PremadeGroupFilter:RefreshSpecializationRows()
    if IsChatRestricted() or IsCombatLocked() or not self.enabled or not self.db then
        self:HideAllSpecializationRows()
        self:HideAllLeaderScoreRows()
        self:HideAllResultAssistRows()
        return
    end

    local scrollBox = _G.LFGListFrame
        and LFGListFrame.SearchPanel
        and LFGListFrame.SearchPanel.ScrollBox
    if not scrollBox or not scrollBox.GetFrames then return end
    local ok, rows = pcall(scrollBox.GetFrames, scrollBox)
    if not ok or IsSecret(rows) or type(rows) ~= "table" then return end
    for _, row in pairs(rows) do self:UpdateResultRow(row) end
end

function PremadeGroupFilter:AttachSpecializationHook()
    if specEntryHooked or not LFGListSearchEntry_Update then
        self:RefreshSpecializationRows()
        return
    end
    specEntryHooked = true
    hooksecurefunc("LFGListSearchEntry_Update", function(row)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if PremadeGroupFilter.enabled then
                    PremadeGroupFilter:UpdateResultRow(row)
                else
                    HideSpecializationRow(row)
                    HideLeaderScoreRow(row)
                    HideResultAssistRow(row)
                end
            end)
        elseif not PremadeGroupFilter.enabled then
            HideSpecializationRow(row)
            HideLeaderScoreRow(row)
            HideResultAssistRow(row)
        end
    end)
    self:RefreshSpecializationRows()
end

function PremadeGroupFilter:AttachResultSortHook()
    if resultSortHooked or not LFGListUtil_SortSearchResults then return end
    resultSortHooked = true
    hooksecurefunc("LFGListUtil_SortSearchResults", function(searchPanel)
        if not PremadeGroupFilter.enabled or not PremadeGroupFilter.db
            or IsChatRestricted() or IsCombatLocked() then
            return
        end
        local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
        if categoryID ~= CATEGORY_DUNGEON
            or not PremadeGroupFilter:CaptureNativeResultOrder(searchPanel) then
            return
        end

        local sortMode = VALID_SORT_MODES[PremadeGroupFilter.db.sortMode]
            and PremadeGroupFilter.db.sortMode or "DEFAULT"
        if PremadeGroupFilter.db.bloodlustFit == true or sortMode ~= "DEFAULT" then
            PremadeGroupFilter:ApplyDisplayOrder(searchPanel, nativeResultOrder)
        end
    end)
end

function PremadeGroupFilter:CreateSidePanel()
    if sidePanel or not _G.PVEFrame then return sidePanel end

    local panel = CreateFrame(
        "Frame", "DDingToolKit_PremadeGroupFilterPanel", PVEFrame, "BackdropTemplate"
    )
    panel:SetWidth(PANEL_WIDTH)
    panel:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    panel:SetBackdropColor(unpack(P.background))
    panel:SetBackdropBorderColor(unpack(P.border))
    panel:SetFrameLevel((PVEFrame:GetFrameLevel() or 1) + 20)
    panel:Hide()

    panel.topAccent = panel:CreateTexture(nil, "ARTWORK")
    panel.topAccent:SetPoint("TOPLEFT", 1, -1)
    panel.topAccent:SetPoint("TOPRIGHT", -1, -1)
    panel.topAccent:SetHeight(2)
    panel.topAccent:SetColorTexture(unpack(P.accent))

    panel.title = CreateText(panel, 15, P.textBright)
    panel.title:SetPoint("TOPLEFT", 14, -14)
    panel.title:SetText(L["PGF_PANEL_TITLE"] or L["PGF_TITLE"] or "Party Filter")

    panel.count = CreateText(panel, 11, P.accentText)
    panel.count:SetPoint("TOPRIGHT", -14, -16)
    panel.count:SetJustifyH("RIGHT")

    panel.headerLine = panel:CreateTexture(nil, "ARTWORK")
    panel.headerLine:SetPoint("TOPLEFT", 12, -43)
    panel.headerLine:SetPoint("TOPRIGHT", -12, -43)
    panel.headerLine:SetHeight(1)
    panel.headerLine:SetColorTexture(unpack(P.separator))

    panel.dungeonTitle = CreateSectionLabel(
        panel, L["PGF_DUNGEON_SECTION"] or "Dungeons"
    )
    panel.dungeonTitle:SetPoint("TOPLEFT", 14, -55)

    panel.dungeonAll = CreateSegmentButton(
        panel,
        L["PGF_DUNGEON_ALL"] or "All",
        function() PremadeGroupFilter:ClearDungeonSelection() end
    )
    panel.dungeonAll:SetSize(44, 20)
    panel.dungeonAll:SetPoint("TOPRIGHT", -14, -50)

    panel.dungeonButtons = {}
    local dungeonButtonWidth = math.floor((PANEL_WIDTH - 32) / 2)
    local dungeonData = GetSeasonDungeons()
    for index = 1, MAX_SEASON_DUNGEONS do
        local button = CreateDungeonButton(
            panel,
            dungeonButtonWidth,
            function(mapID, selected)
                PremadeGroupFilter:UpdateDungeonSelection(mapID, selected)
            end
        )
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        button:SetPoint("TOPLEFT", 14 + column * (dungeonButtonWidth + 4), -70 - row * 30)
        button:SetDungeon(dungeonData[index])
        panel.dungeonButtons[index] = button
    end

    panel.compositionTitle = CreateSectionLabel(
        panel, L["PGF_COMPOSITION_SECTION"] or "Composition"
    )
    panel.compositionTitle:SetPoint("TOPLEFT", 14, -197)

    local halfWidth = math.floor((PANEL_WIDTH - 34) / 2)
    panel.role = CreateToggleControl(
        panel,
        L["PGF_NEED_MY_ROLE"] or "Role Available",
        halfWidth,
        function(value) PremadeGroupFilter:UpdateSetting("needMyRole", value) end,
        L["PGF_NEED_MY_ROLE_TOOLTIP"]
    )
    panel.role:SetPoint("TOPLEFT", 14, -213)

    panel.bloodlust = CreateToggleControl(
        panel,
        L["PGF_BLOODLUST_FIT"] or "Bloodlust Fit",
        halfWidth,
        function(value) PremadeGroupFilter:UpdateSetting("bloodlustFit", value) end,
        L["PGF_BLOODLUST_FIT_TOOLTIP"]
    )
    panel.bloodlust:SetPoint("TOPRIGHT", -14, -213)

    panel.tank = CreateToggleControl(
        panel,
        L["PGF_REQUIRE_TANK"] or "Has Tank",
        halfWidth,
        function(value) PremadeGroupFilter:UpdateSetting("requireTank", value) end
    )
    panel.tank:SetPoint("TOPLEFT", panel.role, "BOTTOMLEFT", 0, -5)

    panel.healer = CreateToggleControl(
        panel,
        L["PGF_REQUIRE_HEALER"] or "Has Healer",
        halfWidth,
        function(value) PremadeGroupFilter:UpdateSetting("requireHealer", value) end
    )
    panel.healer:SetPoint("TOPRIGHT", panel.bloodlust, "BOTTOMRIGHT", 0, -5)

    panel.scoreTitle = CreateSectionLabel(panel, L["PGF_SCORE_SECTION"] or "Score")
    panel.scoreTitle:SetPoint("TOPLEFT", 14, -293)

    panel.rating = CreateNumberControl(
        panel,
        L["PGF_MIN_RATING_SHORT"] or "Leader Rating",
        PANEL_WIDTH - 28,
        5000,
        function(value) PremadeGroupFilter:UpdateSetting("minLeaderRating", value) end
    )
    panel.rating:SetPoint("TOPLEFT", 14, -309)

    panel.reset = CreateSegmentButton(
        panel,
        L["PGF_RESET_SHORT"] or "Reset",
        function() PremadeGroupFilter:ResetFilters() end
    )
    panel.reset:SetSize(54, 20)
    panel.reset:SetPoint("TOPRIGHT", -14, -288)

    panel.sortTitle = CreateSectionLabel(panel, L["PGF_SORT_SECTION"] or "Sorting")
    panel.sortTitle:SetPoint("TOPLEFT", 14, -359)

    panel.sortButtons = {}
    local segmentWidth = math.floor((PANEL_WIDTH - 32) / 3)
    local sortDefinitions = {
        { "DEFAULT", L["PGF_SORT_DEFAULT_SHORT"] or "Default" },
        { "RATING", L["PGF_SORT_RATING"] or "Rating" },
        { "MAPBEST", L["PGF_SORT_MAP_BEST"] or "Map" },
    }
    local function SelectSortMode(mode)
        return function() PremadeGroupFilter:SetSortMode(mode) end
    end
    for index, definition in ipairs(sortDefinitions) do
        local mode = definition[1]
        local button = CreateSegmentButton(
            panel,
            definition[2],
            SelectSortMode(mode),
            L["PGF_SORT_ASSIST_TOOLTIP"]
        )
        button:SetSize(segmentWidth, 28)
        if index == 1 then
            button:SetPoint("TOPLEFT", 14, -375)
        else
            button:SetPoint("LEFT", panel.sortButtons[index - 1], "RIGHT", 2, 0)
        end
        panel.sortButtons[index] = button
        panel.sortButtons[mode] = button
    end

    sidePanel = panel
    self:PositionSidePanel()
    self:RefreshPanel()
    return panel
end

function PremadeGroupFilter:UpdateRaiderIOAnchor()
    local anchor = _G.RaiderIO_ProfileTooltipAnchor
    if not anchor or not anchor.GetPoint or not anchor.SetPoint then return end

    if not raiderIOAnchorHooked and hooksecurefunc then
        raiderIOAnchorHooked = true
        hooksecurefunc(anchor, "SetPoint", function(_, _, relativeTo)
            if raiderIOAnchorUpdating or not PremadeGroupFilter.enabled then return end
            if relativeTo == _G.PVEFrame or relativeTo == sidePanel then
                PremadeGroupFilter:UpdateRaiderIOAnchor()
            end
        end)
    end

    local ok, point, relativeTo, relativePoint, offsetX, offsetY =
        pcall(anchor.GetPoint, anchor, 1)
    point = ok and SafeString(point, nil) or nil
    relativePoint = ok and SafeString(relativePoint, nil) or nil
    offsetX = ok and (SafeNumber(offsetX, 0) or 0) or 0
    offsetY = ok and (SafeNumber(offsetY, 0) or 0) or 0
    if not point or not relativePoint then return end
    if relativeTo ~= _G.PVEFrame and relativeTo ~= sidePanel then return end

    local panelOnRight = self.enabled and sidePanel and sidePanel:IsShown()
        and sidePanel._attachedSide == "RIGHT"
    local target = panelOnRight and sidePanel or _G.PVEFrame
    if not target or relativeTo == target then return end

    raiderIOAnchorUpdating = true
    anchor:ClearAllPoints()
    anchor:SetPoint(point, target, relativePoint, offsetX, offsetY)
    raiderIOAnchorUpdating = false
end

function PremadeGroupFilter:ScheduleRaiderIOAnchorUpdate()
    if raiderIORetryScheduled or not C_Timer or not C_Timer.After then return end
    raiderIORetryScheduled = true
    C_Timer.After(1, function()
        if PremadeGroupFilter.enabled then PremadeGroupFilter:UpdateRaiderIOAnchor() end
    end)
    C_Timer.After(4, function()
        raiderIORetryScheduled = false
        if PremadeGroupFilter.enabled then PremadeGroupFilter:UpdateRaiderIOAnchor() end
    end)
end

function PremadeGroupFilter:PositionSidePanel()
    if not sidePanel or not _G.PVEFrame or not _G.UIParent then return end

    local frameRight = SafeNumber(PVEFrame:GetRight(), nil)
    local frameLeft = SafeNumber(PVEFrame:GetLeft(), nil)
    local screenRight = SafeNumber(UIParent:GetRight(), nil)
    local useLeft = frameRight and frameLeft and screenRight
        and (screenRight - frameRight) < (PANEL_WIDTH + 8)
        and frameLeft > (PANEL_WIDTH + 8)

    sidePanel:ClearAllPoints()
    if useLeft then
        sidePanel._attachedSide = "LEFT"
        sidePanel:SetPoint("TOPRIGHT", PVEFrame, "TOPLEFT", -4, 0)
        sidePanel:SetPoint("BOTTOMRIGHT", PVEFrame, "BOTTOMLEFT", -4, -PANEL_BOTTOM_EXTENSION)
    else
        sidePanel._attachedSide = "RIGHT"
        sidePanel:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", 4, 0)
        sidePanel:SetPoint("BOTTOMLEFT", PVEFrame, "BOTTOMRIGHT", 4, -PANEL_BOTTOM_EXTENSION)
    end
    if sidePanel:IsShown() then self:UpdateRaiderIOAnchor() end
end

function PremadeGroupFilter:RefreshPanel()
    if not sidePanel or not self.db then return end
    sidePanel.count:SetText(string.format(
        L["PGF_RESULT_COUNT_FORMAT"] or "%d / %d", lastMatchCount, lastTotalCount
    ))
    sidePanel.role:SetActive(self.db.needMyRole == true)
    sidePanel.bloodlust:SetActive(self.db.bloodlustFit == true)
    sidePanel.tank:SetActive(self.db.requireTank == true)
    sidePanel.healer:SetActive(self.db.requireHealer == true)
    sidePanel.rating:SetValue(self.db.minLeaderRating)
    sidePanel.dungeonAll:SetActive(not HasDungeonSelection(self.db))
    for _, button in ipairs(sidePanel.dungeonButtons) do
        button:SetActive(button.mapID ~= nil and IsDungeonSelected(self.db, button.mapID))
    end

    local sortMode = VALID_SORT_MODES[self.db.sortMode] and self.db.sortMode or "DEFAULT"
    for _, mode in ipairs({ "DEFAULT", "RATING", "MAPBEST" }) do
        sidePanel.sortButtons[mode]:SetActive(mode == sortMode)
    end
end

function PremadeGroupFilter:UpdatePanelVisibility()
    if not self.enabled or not self.db or not sidePanel then
        if sidePanel then sidePanel:Hide() end
        self:UpdateRaiderIOAnchor()
        return
    end

    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    local categoryID = searchPanel and SafeNumber(searchPanel.categoryID, 0) or 0
    if categoryID ~= CATEGORY_DUNGEON then
        self:HideAllLeaderScoreRows()
        self:HideAllResultAssistRows()
    end
    local visible = self.db.showPanel ~= false
        and _G.PVEFrame and PVEFrame:IsShown()
        and searchPanel and searchPanel:IsShown()
        and LFGListFrame.activePanel == searchPanel
        and categoryID == CATEGORY_DUNGEON

    if visible then
        self:PositionSidePanel()
        sidePanel:Show()
    else
        sidePanel:Hide()
    end
    self:UpdateRaiderIOAnchor()
end

function PremadeGroupFilter:AttachGroupFinder()
    if hooksAttached then
        self:AttachResultSortHook()
        self:AttachSpecializationHook()
        if #nativeResultOrder == 0 then
            self:CaptureNativeResultOrder(LFGListFrame.SearchPanel)
        end
        self:CaptureSearchResults(LFGListFrame.SearchPanel)
        self:UpdatePanelVisibility()
        return true
    end
    if not _G.LFGListFrame or not LFGListFrame.SearchPanel or not _G.PVEFrame then return false end

    hooksAttached = true
    seasonDungeons = BuildSeasonDungeonData()
    self:CreateSidePanel()
    self:AttachResultSortHook()
    self:AttachSpecializationHook()
    self:CaptureNativeResultOrder(LFGListFrame.SearchPanel)

    if LFGListSearchPanel_UpdateResultList then
        hooksecurefunc("LFGListSearchPanel_UpdateResultList", function(searchPanel)
            if PremadeGroupFilter.enabled then
                PremadeGroupFilter:CaptureSearchResults(searchPanel)
                PremadeGroupFilter:UpdatePanelVisibility()
            end
        end)
    end

    if LFGListSearchPanel_SetCategory then
        hooksecurefunc("LFGListSearchPanel_SetCategory", function()
            if not PremadeGroupFilter.enabled then return end
            lastMatchCount = 0
            lastTotalCount = 0
            nativeResultOrder = {}
            PremadeGroupFilter:HideAllSpecializationRows()
            PremadeGroupFilter:HideAllLeaderScoreRows()
            PremadeGroupFilter:HideAllResultAssistRows()
            PremadeGroupFilter:RefreshPanel()
            PremadeGroupFilter:UpdatePanelVisibility()
        end)
    end

    if LFGListFrame_SetActivePanel then
        hooksecurefunc("LFGListFrame_SetActivePanel", function()
            if PremadeGroupFilter.enabled then PremadeGroupFilter:UpdatePanelVisibility() end
        end)
    end

    LFGListFrame.SearchPanel:HookScript("OnShow", function()
        if PremadeGroupFilter.enabled then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if PremadeGroupFilter.enabled then
                        PremadeGroupFilter:ApplyCurrentResults()
                        PremadeGroupFilter:UpdatePanelVisibility()
                    end
                end)
            else
                PremadeGroupFilter:UpdatePanelVisibility()
            end
        end
    end)
    LFGListFrame.SearchPanel:HookScript("OnHide", function()
        if PremadeGroupFilter.enabled then PremadeGroupFilter:UpdatePanelVisibility() end
    end)
    PVEFrame:HookScript("OnHide", function()
        if sidePanel then sidePanel:Hide() end
        PremadeGroupFilter:UpdateRaiderIOAnchor()
    end)
    PVEFrame:HookScript("OnSizeChanged", function()
        if sidePanel and PVEFrame:IsShown() then PremadeGroupFilter:PositionSidePanel() end
    end)

    self:CaptureSearchResults(LFGListFrame.SearchPanel)
    self:UpdatePanelVisibility()
    self:ScheduleRaiderIOAnchorUpdate()
    return true
end

function PremadeGroupFilter:StartAttachWatcher()
    if self:AttachGroupFinder() then return end
    if attachTicker or not C_Timer or not C_Timer.NewTicker then return end

    attachTicker = C_Timer.NewTicker(1, function(ticker)
        if not PremadeGroupFilter.enabled then
            ticker:Cancel()
            attachTicker = nil
            return
        end
        if PremadeGroupFilter:AttachGroupFinder() then
            ticker:Cancel()
            attachTicker = nil
        end
    end)
end

function PremadeGroupFilter:ApplySettings()
    self.db = ns.db and ns.db.profile and ns.db.profile.PremadeGroupFilter or self.db
    if not self.db then return end
    self:NormalizeDatabase()
    self:RefreshPanel()
    self:ApplyCurrentResults()
    self:RefreshCurrentDisplayOrder()
    self:RefreshSpecializationRows()
    self:UpdatePanelVisibility()
end

function PremadeGroupFilter:OnInitialize()
    self.db = ns.db.profile.PremadeGroupFilter
    self:NormalizeDatabase()
end

function PremadeGroupFilter:OnEnable()
    self.enabled = true
    self.db = self.db or (ns.db and ns.db.profile and ns.db.profile.PremadeGroupFilter)
    if not self.db then return end
    self:NormalizeDatabase()
    seasonDungeons = BuildSeasonDungeonData()
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then
        pcall(C_MythicPlus.RequestMapInfo)
    end
    self:ApplyNativeFilters()
    self:StartAttachWatcher()
    self:ScheduleRaiderIOAnchorUpdate()
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if PremadeGroupFilter.enabled then PremadeGroupFilter:RefreshSeasonDungeons() end
        end)
    end
end

function PremadeGroupFilter:OnDisable()
    self:RestoreNativeFilters(self.db)
    self:RestoreCurrentDisplayOrder()
    self.enabled = false
    if attachTicker then
        attachTicker:Cancel()
        attachTicker = nil
    end
    self:HideAllSpecializationRows()
    self:HideAllLeaderScoreRows()
    self:HideAllResultAssistRows()
    nativeResultOrder = {}
    if sidePanel then sidePanel:Hide() end
    self:UpdateRaiderIOAnchor()
end

local restrictionWatcher = CreateFrame("Frame")
restrictionWatcher:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
restrictionWatcher:RegisterEvent("PLAYER_LOGIN")
restrictionWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
restrictionWatcher:RegisterEvent("PLAYER_ROLES_ASSIGNED")
restrictionWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
restrictionWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
restrictionWatcher:SetScript("OnEvent", function(_, event, restrictionType, state)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local chatType = Enum and Enum.AddOnRestrictionType
            and Enum.AddOnRestrictionType.Chat or 5
        if IsSecret(restrictionType) or restrictionType ~= chatType then return end

        chatRestrictionState = IsSecret(state) and 2 or state
        local inactiveState = Enum and Enum.AddOnRestrictionState
            and Enum.AddOnRestrictionState.Inactive or 0
        if chatRestrictionState ~= inactiveState then
            PremadeGroupFilter:HideAllSpecializationRows()
            PremadeGroupFilter:HideAllLeaderScoreRows()
            PremadeGroupFilter:HideAllResultAssistRows()
            return
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if PremadeGroupFilter.enabled then
                    PremadeGroupFilter:QueueResultRefresh()
                else
                    local profile = ns.db and ns.db.profile
                    local db = profile and profile.PremadeGroupFilter
                    PremadeGroupFilter:RestoreNativeFilters(db)
                end
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        PremadeGroupFilter:HideAllSpecializationRows()
        PremadeGroupFilter:HideAllLeaderScoreRows()
        PremadeGroupFilter:HideAllResultAssistRows()
    elseif event == "PLAYER_REGEN_ENABLED" and PremadeGroupFilter.enabled then
        PremadeGroupFilter:QueueResultRefresh()
    elseif (event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED")
        and PremadeGroupFilter.enabled then
        PremadeGroupFilter:QueueResultRefresh()
    elseif event == "PLAYER_LOGIN" and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local profile = ns.db and ns.db.profile
            if not profile or not profile.PremadeGroupFilter then return end
            local moduleEnabled = profile.modules
                and profile.modules.PremadeGroupFilter == true
            if not moduleEnabled then
                PremadeGroupFilter:RestoreNativeFilters(profile.PremadeGroupFilter)
            end
        end)
    end
end)

DDingToolKit:RegisterModule("PremadeGroupFilter", PremadeGroupFilter)
