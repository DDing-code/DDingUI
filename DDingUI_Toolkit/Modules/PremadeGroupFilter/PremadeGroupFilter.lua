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
local CURRENT_SEASON_ACTIVITY_MAPS = {
    [1933] = 588,
    [1949] = 584,
    [1952] = 586,
    [1950] = 587,
    [1951] = 585,
    [1176] = 399,
    [504] = 250,
    [514] = 249,
    [661] = 249,
}

local MAP_ORDER_INDEX = {}
local MAP_BY_ACTIVITY_GROUP = {}
for index, mapID in ipairs(CURRENT_SEASON_MAP_ORDER) do
    MAP_ORDER_INDEX[mapID] = index
    MAP_BY_ACTIVITY_GROUP[CURRENT_SEASON_ACTIVITY_GROUPS[mapID]] = mapID
end

local ROLE_SORT_ORDER = {
    TANK = 1,
    HEALER = 2,
    DAMAGER = 3,
    NONE = 4,
}

local VALID_SORT_MODES = {
    DEFAULT = true,
    RATING = true,
    MAPBEST = true,
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
local rawResults = {}
local lastMatchCount = 0
local lastTotalCount = 0
local specializationLookup
local specializationRows = setmetatable({}, { __mode = "k" })
local leaderScoreRows = setmetatable({}, { __mode = "k" })
local seasonDungeons = {}
local raiderIOAnchorHooked = false
local raiderIOAnchorUpdating = false
local raiderIORetryScheduled = false

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
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

local function ResolveActivityMapID(activityID)
    activityID = SafeNumber(activityID, nil)
    if not activityID then return nil end
    activityID = math.floor(activityID)

    local mapID = CURRENT_SEASON_ACTIVITY_MAPS[activityID]
    if mapID then return mapID end
    if not C_LFGList or not C_LFGList.GetActivityInfoTable then return nil end

    local ok, activityInfo = pcall(C_LFGList.GetActivityInfoTable, activityID)
    if not ok or IsSecret(activityInfo) or type(activityInfo) ~= "table" then return nil end
    local activityGroupID = SafeNumber(activityInfo.groupFinderActivityGroupID, nil)
    return activityGroupID and MAP_BY_ACTIVITY_GROUP[math.floor(activityGroupID)] or nil
end

local function GetResultChallengeMapID(searchResultInfo)
    if IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then return nil end

    local activityIDs = searchResultInfo.activityIDs
    if not IsSecret(activityIDs) and type(activityIDs) == "table" then
        for _, activityID in ipairs(activityIDs) do
            local mapID = ResolveActivityMapID(activityID)
            if mapID then return mapID end
        end
    end
    return ResolveActivityMapID(searchResultInfo.activityID)
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

local function IsSearchPanelReady(searchPanel)
    if IsSecret(searchPanel) or searchPanel == nil then return false end

    local results = searchPanel.results
    local applications = searchPanel.applications
    return not IsSecret(results) and type(results) == "table"
        and not IsSecret(applications) and type(applications) == "table"
end

local function GetDisplayedResultCount(results, applications)
    local total = #results
    if IsSecret(applications) or type(applications) ~= "table" then return total end

    local resultSet = {}
    for _, resultID in ipairs(results) do
        if not IsSecret(resultID) and resultID ~= nil then resultSet[resultID] = true end
    end
    for _, resultID in ipairs(applications) do
        if not IsSecret(resultID) and resultID ~= nil and not resultSet[resultID] then
            total = total + 1
        end
    end
    return total
end

local function GetMemberCounts(resultID)
    if IsSecret(resultID) or not C_LFGList
        or not C_LFGList.GetSearchResultMemberCounts then
        return {}
    end
    local ok, counts = pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
    if not ok or IsSecret(counts) or type(counts) ~= "table" then return {} end
    return counts
end

local function GetMemberCount(source, key)
    if IsSecret(source) or type(source) ~= "table" then return 0 end
    return math.max(0, SafeNumber(source[key], 0) or 0)
end

local function MemberCountsHaveBloodlust(counts)
    if IsSecret(counts) or type(counts) ~= "table" then return false end
    local classesByRole = counts.classesByRole
    if IsSecret(classesByRole) or type(classesByRole) ~= "table" then return false end

    for _, roleClasses in pairs(classesByRole) do
        if not IsSecret(roleClasses) and type(roleClasses) == "table" then
            for rawClassToken, count in pairs(roleClasses) do
                local classToken = SafeString(rawClassToken, nil)
                if classToken and BLOODLUST_CLASSES[classToken]
                    and (SafeNumber(count, 0) or 0) > 0 then
                    return true
                end
            end
        end
    end
    return false
end

local function SearchingPartyHasBloodlust()
    if not UnitExists or not UnitClass then return false end
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        local exists = UnitExists(unit)
        if not IsSecret(exists) and exists then
            local ok, _, classToken = pcall(UnitClass, unit)
            classToken = ok and SafeString(classToken, nil) or nil
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
    local units = { "player", "party1", "party2", "party3", "party4" }

    for _, unit in ipairs(units) do
        local exists = UnitExists and UnitExists(unit)
        if not IsSecret(exists) and exists then
            roles.total = roles.total + 1
            local role = UnitGroupRolesAssigned
                and SafeString(UnitGroupRolesAssigned(unit), nil) or nil
            if unit == "player" and (not role or role == "NONE") then
                role = GetPlayerSpecializationRole()
            end
            if roles[role] ~= nil then roles[role] = roles[role] + 1 end
        end
    end

    if roles.total == 0 then
        roles.total = 1
        local role = GetPlayerSpecializationRole()
        if role then roles[role] = 1 end
    end
    return roles
end

local function IsPartyFit(counts, listingMembers, partyRoles)
    if partyRoles.total + listingMembers > 5 then return false end
    if partyRoles.TANK + GetMemberCount(counts, "TANK") > 1 then return false end
    if partyRoles.HEALER + GetMemberCount(counts, "HEALER") > 1 then return false end
    local listingDamage = GetMemberCount(counts, "DAMAGER") + GetMemberCount(counts, "NOROLE")
    if partyRoles.DAMAGER + listingDamage > 3 then return false end
    return true
end

local function IsBloodlustFit(counts, listingMembers, partyRoles, partyHasBloodlust)
    if partyHasBloodlust or MemberCountsHaveBloodlust(counts) then return true end
    if partyRoles.total + listingMembers > 5 then return false end

    local healerCount = partyRoles.HEALER + GetMemberCount(counts, "HEALER")
    local damageCount = partyRoles.DAMAGER
        + GetMemberCount(counts, "DAMAGER")
        + GetMemberCount(counts, "NOROLE")
    return healerCount < 1 or damageCount < 3
end

local function GetMapBest(searchResultInfo)
    if IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then return 0 end
    local best = 0

    local function ReadScoreInfo(scoreInfo)
        if IsSecret(scoreInfo) or type(scoreInfo) ~= "table" then return end
        local direct = math.max(0, SafeNumber(scoreInfo.bestRunLevel, 0) or 0)
        if direct > best then best = direct end
        for _, entry in pairs(scoreInfo) do
            if not IsSecret(entry) and type(entry) == "table" then
                local level = math.max(0, SafeNumber(entry.bestRunLevel, 0) or 0)
                if level > best then best = level end
            end
        end
    end

    ReadScoreInfo(searchResultInfo.leaderDungeonScoreInfo)
    ReadScoreInfo(searchResultInfo.leaderBestDungeonScoreInfo)
    return best
end

local function BuildResultModel(resultID, originalIndex, partyRoles, partyHasBloodlust)
    if IsSecret(resultID) or resultID == nil
        or not C_LFGList or not C_LFGList.GetSearchResultInfo then
        return nil
    end

    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if not ok or IsSecret(info) or type(info) ~= "table" then return nil end

    local counts = GetMemberCounts(resultID)
    local members = math.max(0, SafeNumber(info.numMembers, 0) or 0)
    local applied, declined = GetApplicationState(resultID, info)
    local friends = GetMemberCount(info, "numBNetFriends")
        + GetMemberCount(info, "numCharFriends")
        + GetMemberCount(info, "numGuildMates")

    return {
        id = resultID,
        originalIndex = originalIndex,
        hasTank = GetMemberCount(counts, "TANK") > 0,
        hasHealer = GetMemberCount(counts, "HEALER") > 0,
        partyFit = IsPartyFit(counts, members, partyRoles),
        bloodlustFit = IsBloodlustFit(counts, members, partyRoles, partyHasBloodlust),
        rating = math.max(0, SafeNumber(info.leaderOverallDungeonScore, 0) or 0),
        mapBest = GetMapBest(info),
        mapID = GetResultChallengeMapID(info),
        friends = friends,
        applied = applied,
        declined = declined,
    }
end

local function PassesFilters(model, db)
    if not model then return true end
    if model.applied then return true end
    if db.needMyRole and not model.partyFit then return false end
    if db.bloodlustFit and not model.bloodlustFit then return false end
    if db.requireTank and not model.hasTank then return false end
    if db.requireHealer and not model.hasHealer then return false end
    if HasDungeonSelection(db) and not IsDungeonSelected(db, model.mapID) then return false end

    local minRating = math.max(0, SafeNumber(db.minLeaderRating, 0) or 0)
    local minMapBest = math.max(0, SafeNumber(db.minMapBest, 0) or 0)
    if minRating > 0 and model.rating < minRating then return false end
    if minMapBest > 0 and model.mapBest < minMapBest then return false end
    return true
end

local function CompareRecords(left, right, sortMode)
    local a, b = left.model, right.model
    if (a == nil) ~= (b == nil) then return a ~= nil end
    if not a then return left.index < right.index end
    if a.applied ~= b.applied then return a.applied end

    local aSocial = a.friends > 0
    local bSocial = b.friends > 0
    if aSocial ~= bSocial then return aSocial end

    if sortMode == "RATING" and a.rating ~= b.rating then
        return a.rating > b.rating
    end
    if sortMode == "MAPBEST" and a.mapBest ~= b.mapBest then
        return a.mapBest > b.mapBest
    end
    return a.originalIndex < b.originalIndex
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
    local classesByRole = counts.classesByRole
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

local function HideSpecializationRow(row)
    local frames = specializationRows[row]
    if not frames then return end
    for _, frame in pairs(frames) do
        frame:Hide()
        if frame.defaultIcon and frame.defaultAlpha ~= nil
            and frame.defaultIcon.SetAlpha then
            frame.defaultIcon:SetAlpha(frame.defaultAlpha)
        end
        frame.defaultIcon = nil
        frame.defaultAlpha = nil
    end
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
        frame.defaultIcon = defaultIcon
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

    button.label = CreateText(button, 12, { 0.72, 0.75, 0.80, 1 })
    button.label:SetPoint("LEFT", 12, 0)
    button.label:SetPoint("RIGHT", -8, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetText(label)

    function button:UpdateVisual()
        if self.active then
            self:SetBackdropColor(0.035, 0.20, 0.26, 0.96)
            self:SetBackdropBorderColor(0.10, 0.72, 0.90, 0.95)
            self.accent:SetColorTexture(0.10, 0.82, 1.00, 1)
            self.label:SetTextColor(0.90, 0.97, 1.00, 1)
        elseif self.hovered then
            self:SetBackdropColor(0.09, 0.10, 0.13, 0.96)
            self:SetBackdropBorderColor(0.30, 0.34, 0.41, 0.95)
            self.accent:SetColorTexture(0.30, 0.34, 0.41, 0.8)
            self.label:SetTextColor(0.88, 0.90, 0.94, 1)
        else
            self:SetBackdropColor(0.045, 0.05, 0.07, 0.94)
            self:SetBackdropBorderColor(0.15, 0.17, 0.21, 0.95)
            self.accent:SetColorTexture(0.15, 0.17, 0.21, 0.8)
            self.label:SetTextColor(0.68, 0.71, 0.77, 1)
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
    control:SetBackdropColor(0.045, 0.05, 0.07, 0.94)
    control:SetBackdropBorderColor(0.15, 0.17, 0.21, 0.95)

    control.label = CreateText(control, 11, { 0.72, 0.75, 0.80, 1 })
    control.label:SetPoint("LEFT", 10, 0)
    control.label:SetPoint("RIGHT", -64, 0)
    control.label:SetJustifyH("LEFT")
    control.label:SetText(label)

    control.edit = CreateFrame("EditBox", nil, control, "BackdropTemplate")
    control.edit:SetSize(48, 24)
    control.edit:SetPoint("RIGHT", -6, 0)
    control.edit:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    control.edit:SetBackdropColor(0.015, 0.018, 0.025, 1)
    control.edit:SetBackdropBorderColor(0.20, 0.23, 0.29, 1)
    control.edit:SetFont(FONT, 12, "OUTLINE")
    control.edit:SetTextColor(0.90, 0.94, 0.98, 1)
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
        edit:SetBackdropBorderColor(0.10, 0.72, 0.90, 1)
    end)

    function control:SetValue(value)
        value = math.floor(Clamp(value, 0, maximum))
        self.value = value
        if not self.edit:HasFocus() then self.edit:SetText(tostring(value)) end
        if value > 0 then
            self:SetBackdropBorderColor(0.10, 0.58, 0.74, 0.95)
            self.label:SetTextColor(0.82, 0.94, 1.00, 1)
        else
            self:SetBackdropBorderColor(0.15, 0.17, 0.21, 0.95)
            self.label:SetTextColor(0.72, 0.75, 0.80, 1)
        end
        if not self.edit:HasFocus() then
            self.edit:SetBackdropBorderColor(0.20, 0.23, 0.29, 1)
        end
    end

    return control
end

local function CreateSegmentButton(parent, label, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    button:RegisterForClicks("LeftButtonUp")

    button.label = CreateText(button, 11, { 0.66, 0.69, 0.74, 1 })
    button.label:SetPoint("CENTER")
    button.label:SetText(label)

    button.line = button:CreateTexture(nil, "ARTWORK")
    button.line:SetPoint("BOTTOMLEFT", 1, 1)
    button.line:SetPoint("BOTTOMRIGHT", -1, 1)
    button.line:SetHeight(2)

    function button:UpdateVisual()
        if self.active then
            self:SetBackdropColor(0.035, 0.20, 0.26, 0.96)
            self:SetBackdropBorderColor(0.10, 0.72, 0.90, 0.95)
            self.line:SetColorTexture(0.10, 0.82, 1.00, 1)
            self.label:SetTextColor(0.92, 0.98, 1.00, 1)
        elseif self.hovered then
            self:SetBackdropColor(0.09, 0.10, 0.13, 0.96)
            self:SetBackdropBorderColor(0.28, 0.31, 0.37, 0.95)
            self.line:SetColorTexture(0.28, 0.31, 0.37, 0.8)
            self.label:SetTextColor(0.86, 0.88, 0.92, 1)
        else
            self:SetBackdropColor(0.045, 0.05, 0.07, 0.94)
            self:SetBackdropBorderColor(0.15, 0.17, 0.21, 0.95)
            self.line:SetColorTexture(0.15, 0.17, 0.21, 0.8)
            self.label:SetTextColor(0.66, 0.69, 0.74, 1)
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

    button.label = CreateText(button, 10, { 0.67, 0.70, 0.76, 1 })
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 5, 0)
    button.label:SetPoint("RIGHT", -4, 0)
    button.label:SetJustifyH("LEFT")
    if button.label.SetWordWrap then button.label:SetWordWrap(false) end

    function button:UpdateVisual()
        if self.active then
            self:SetBackdropColor(0.035, 0.20, 0.26, 0.96)
            self:SetBackdropBorderColor(0.10, 0.72, 0.90, 0.95)
            self.icon:SetAlpha(1)
            self.label:SetTextColor(0.90, 0.97, 1.00, 1)
        elseif self.hovered then
            self:SetBackdropColor(0.09, 0.10, 0.13, 0.96)
            self:SetBackdropBorderColor(0.30, 0.34, 0.41, 0.95)
            self.icon:SetAlpha(0.92)
            self.label:SetTextColor(0.88, 0.90, 0.94, 1)
        else
            self:SetBackdropColor(0.045, 0.05, 0.07, 0.94)
            self:SetBackdropBorderColor(0.15, 0.17, 0.21, 0.95)
            self.icon:SetAlpha(0.72)
            self.label:SetTextColor(0.67, 0.70, 0.76, 1)
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
    local text = CreateText(parent, 10, { 0.37, 0.69, 0.79, 1 })
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

    if type(self.db.selectedDungeons) ~= "table" then self.db.selectedDungeons = {} end
    if self.db.showLeaderScore == nil then self.db.showLeaderScore = true end
    self.db.uiRevision = 4
    if not VALID_SORT_MODES[self.db.sortMode] then self.db.sortMode = "DEFAULT" end
    for _, key in ipairs(OBSOLETE_DB_KEYS) do self.db[key] = nil end
end

function PremadeGroupFilter:PublishResults(results)
    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    if not IsSearchPanelReady(searchPanel)
        or IsSecret(results) or type(results) ~= "table" then
        return false
    end

    searchPanel.results = results
    searchPanel.totalResults = GetDisplayedResultCount(results, searchPanel.applications)
    if LFGListSearchPanel_UpdateResults then LFGListSearchPanel_UpdateResults(searchPanel) end
    return true
end

function PremadeGroupFilter:ApplyCurrentResults()
    if not self.enabled or not self.db then return end
    local searchPanel = _G.LFGListFrame and LFGListFrame.SearchPanel
    if not IsSearchPanelReady(searchPanel) then return end

    lastTotalCount = #rawResults
    local categoryID = SafeNumber(searchPanel.categoryID, 0) or 0
    if categoryID ~= CATEGORY_DUNGEON then
        lastMatchCount = lastTotalCount
        self:PublishResults(CopyArray(rawResults))
        self:RefreshPanel()
        return
    end

    local partyRoles = GetSearchingPartyRoles()
    local partyHasBloodlust = SearchingPartyHasBloodlust()
    local passed = {}
    for index, resultID in ipairs(rawResults) do
        local model = BuildResultModel(resultID, index, partyRoles, partyHasBloodlust)
        if PassesFilters(model, self.db) then
            passed[#passed + 1] = { id = resultID, index = index, model = model }
        end
    end

    local sortMode = VALID_SORT_MODES[self.db.sortMode] and self.db.sortMode or "DEFAULT"
    if sortMode ~= "DEFAULT" and #passed > 1 then
        table.sort(passed, function(left, right)
            return CompareRecords(left, right, sortMode)
        end)
    end

    local filtered = {}
    for index, record in ipairs(passed) do filtered[index] = record.id end
    lastMatchCount = #filtered
    self:PublishResults(filtered)
    self:RefreshPanel()
end

function PremadeGroupFilter:CaptureSearchResults(searchPanel)
    if not self.enabled or not self.db or not IsSearchPanelReady(searchPanel) then return end
    rawResults = CopyArray(searchPanel.results)
    self:ApplyCurrentResults()
end

function PremadeGroupFilter:UpdateSetting(key, value)
    if not self.db then return end
    self.db[key] = value
    self:RefreshPanel()
    self:ApplyCurrentResults()
    self:RefreshSpecializationRows()
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
    self:ApplyCurrentResults()
end

function PremadeGroupFilter:UpdateDungeonSelection(mapID, selected)
    if not self.db then return end
    mapID = SafeNumber(mapID, nil)
    if not mapID then return end
    if type(self.db.selectedDungeons) ~= "table" then self.db.selectedDungeons = {} end

    local key = tostring(math.floor(mapID))
    self.db.selectedDungeons[key] = selected == true and true or nil
    self:RefreshPanel()
    self:ApplyCurrentResults()
end

function PremadeGroupFilter:ClearDungeonSelection()
    if not self.db then return end
    self.db.selectedDungeons = {}
    self:RefreshPanel()
    self:ApplyCurrentResults()
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
    if not self.enabled or not self.db or self.db.showSpecIcons == false then return end
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

    local frames = GetSpecializationFrames(row, defaultIcons)
    for memberIndex = 1, #members do
        local slotIndex = #defaultIcons - memberIndex + 1
        local defaultIcon = defaultIcons[slotIndex]
        if IsSecret(defaultIcon) or not defaultIcon or not defaultIcon.SetAlpha
            or not frames[slotIndex] then
            HideSpecializationRow(row)
            return
        end
    end

    local isDelisted = SafeBoolean(searchResultInfo.isDelisted, false)
    local alpha = isDelisted and 0.45 or 1

    for memberIndex, member in ipairs(members) do
        local slotIndex = #defaultIcons - memberIndex + 1
        local frame = frames[slotIndex]
        local defaultIcon = defaultIcons[slotIndex]
        local ok, defaultAlpha = pcall(defaultIcon.GetAlpha, defaultIcon)
        frame.defaultIcon = defaultIcon
        frame.defaultAlpha = ok and (SafeNumber(defaultAlpha, 1) or 1) or 1
        defaultIcon:SetAlpha(0)

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
        frame.icon:SetDesaturated(isDelisted)
        frame.icon:SetAlpha(alpha)
        frame.crown:SetShown(
            self.db.specIconLeaderMarker ~= false and member.isLeader == true
        )
        frame.crown:SetDesaturated(isDelisted)
        frame.crown:SetAlpha(alpha)
        frame:Show()
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

function PremadeGroupFilter:UpdateResultRow(row)
    if not row then return end
    if not self.enabled or not self.db
        or (self.db.showSpecIcons == false and self.db.showLeaderScore == false) then
        HideSpecializationRow(row)
        HideLeaderScoreRow(row)
        return
    end

    local resultID = row.resultID
    if IsSecret(resultID) or resultID == nil
        or not C_LFGList or not C_LFGList.GetSearchResultInfo then
        HideSpecializationRow(row)
        HideLeaderScoreRow(row)
        return
    end

    local ok, searchResultInfo = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if not ok or IsSecret(searchResultInfo) or type(searchResultInfo) ~= "table" then
        HideSpecializationRow(row)
        HideLeaderScoreRow(row)
        return
    end
    local applied, declined = GetApplicationState(resultID, searchResultInfo)
    self:UpdateSpecializationRow(row, resultID, searchResultInfo, applied, declined)
    self:UpdateLeaderScoreRow(row, resultID, searchResultInfo, applied, declined)
end

function PremadeGroupFilter:HideAllSpecializationRows()
    for row in pairs(specializationRows) do HideSpecializationRow(row) end
end

function PremadeGroupFilter:HideAllLeaderScoreRows()
    for row in pairs(leaderScoreRows) do HideLeaderScoreRow(row) end
end

function PremadeGroupFilter:RefreshSpecializationRows()
    if not self.enabled or not self.db then
        self:HideAllSpecializationRows()
        self:HideAllLeaderScoreRows()
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
        if PremadeGroupFilter.enabled then
            PremadeGroupFilter:UpdateResultRow(row)
        else
            HideSpecializationRow(row)
            HideLeaderScoreRow(row)
        end
    end)
    self:RefreshSpecializationRows()
end

function PremadeGroupFilter:CreateSidePanel()
    if sidePanel or not _G.PVEFrame then return sidePanel end

    local panel = CreateFrame(
        "Frame", "DDingToolKit_PremadeGroupFilterPanel", PVEFrame, "BackdropTemplate"
    )
    panel:SetWidth(PANEL_WIDTH)
    panel:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    panel:SetBackdropColor(0.018, 0.022, 0.032, 0.97)
    panel:SetBackdropBorderColor(0.12, 0.15, 0.19, 1)
    panel:SetFrameLevel((PVEFrame:GetFrameLevel() or 1) + 20)
    panel:Hide()

    panel.topAccent = panel:CreateTexture(nil, "ARTWORK")
    panel.topAccent:SetPoint("TOPLEFT", 1, -1)
    panel.topAccent:SetPoint("TOPRIGHT", -1, -1)
    panel.topAccent:SetHeight(2)
    panel.topAccent:SetColorTexture(0.10, 0.82, 1.00, 1)

    panel.title = CreateText(panel, 15, { 0.87, 0.94, 0.98, 1 })
    panel.title:SetPoint("TOPLEFT", 14, -14)
    panel.title:SetText(L["PGF_PANEL_TITLE"] or L["PGF_TITLE"] or "Party Filter")

    panel.count = CreateText(panel, 11, { 0.40, 0.72, 0.82, 1 })
    panel.count:SetPoint("TOPRIGHT", -14, -16)
    panel.count:SetJustifyH("RIGHT")

    panel.headerLine = panel:CreateTexture(nil, "ARTWORK")
    panel.headerLine:SetPoint("TOPLEFT", 12, -43)
    panel.headerLine:SetPoint("TOPRIGHT", -12, -43)
    panel.headerLine:SetHeight(1)
    panel.headerLine:SetColorTexture(0.14, 0.17, 0.21, 0.9)

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

    panel.mapBest = CreateNumberControl(
        panel,
        L["PGF_MIN_MAP_BEST_SHORT"] or "Map Best",
        PANEL_WIDTH - 28,
        40,
        function(value) PremadeGroupFilter:UpdateSetting("minMapBest", value) end
    )
    panel.mapBest:SetPoint("TOPLEFT", panel.rating, "BOTTOMLEFT", 0, -5)

    panel.sortTitle = CreateSectionLabel(panel, L["PGF_SORT_SECTION"] or "Sorting")
    panel.sortTitle:SetPoint("TOPLEFT", 14, -398)

    panel.reset = CreateSegmentButton(
        panel,
        L["PGF_RESET_SHORT"] or "Reset",
        function() PremadeGroupFilter:ResetFilters() end
    )
    panel.reset:SetSize(54, 20)
    panel.reset:SetPoint("TOPRIGHT", -14, -393)

    panel.sortButtons = {}
    local segmentWidth = math.floor((PANEL_WIDTH - 32) / 3)
    local sortDefinitions = {
        { "DEFAULT", L["PGF_SORT_DEFAULT_SHORT"] or "Default" },
        { "RATING", L["PGF_SORT_RATING"] or "Rating" },
        { "MAPBEST", L["PGF_SORT_MAP_BEST"] or "Map Best" },
    }
    local function SelectSortMode(mode)
        return function()
            PremadeGroupFilter:UpdateSetting("sortMode", mode)
        end
    end
    for index, definition in ipairs(sortDefinitions) do
        local mode = definition[1]
        local button = CreateSegmentButton(panel, definition[2], SelectSortMode(mode))
        button:SetSize(segmentWidth, 28)
        if index == 1 then
            button:SetPoint("TOPLEFT", 14, -414)
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
    sidePanel.mapBest:SetValue(self.db.minMapBest)
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
    if categoryID ~= CATEGORY_DUNGEON then self:HideAllLeaderScoreRows() end
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
        self:AttachSpecializationHook()
        self:CaptureSearchResults(LFGListFrame.SearchPanel)
        self:UpdatePanelVisibility()
        return true
    end
    if not _G.LFGListFrame or not LFGListFrame.SearchPanel or not _G.PVEFrame then return false end

    hooksAttached = true
    seasonDungeons = BuildSeasonDungeonData()
    self:CreateSidePanel()
    self:AttachSpecializationHook()

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
            rawResults = {}
            lastMatchCount = 0
            lastTotalCount = 0
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
            PremadeGroupFilter:ApplyCurrentResults()
            PremadeGroupFilter:UpdatePanelVisibility()
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
    self:StartAttachWatcher()
    self:ScheduleRaiderIOAnchorUpdate()
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if PremadeGroupFilter.enabled then PremadeGroupFilter:RefreshSeasonDungeons() end
        end)
    end
end

function PremadeGroupFilter:OnDisable()
    if hooksAttached then self:PublishResults(CopyArray(rawResults)) end
    self.enabled = false
    if attachTicker then
        attachTicker:Cancel()
        attachTicker = nil
    end
    self:HideAllSpecializationRows()
    self:HideAllLeaderScoreRows()
    if sidePanel then sidePanel:Hide() end
    self:UpdateRaiderIOAnchor()
end

DDingToolKit:RegisterModule("PremadeGroupFilter", PremadeGroupFilter)
