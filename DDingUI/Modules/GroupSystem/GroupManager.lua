-- [GROUP SYSTEM] GroupManager: 그룹 관리 + CDM 뷰어 기반 분류 엔진
-- [REFACTOR] AuraEngine 기반 → CDMHookEngine 뷰어 기반으로 전환
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupManager = {}
DDingUI.GroupManager = GroupManager

-- Locals
local pairs = pairs
local type = type
local wipe = wipe

-- ============================================================
-- 프로필 접근 헬퍼
-- ============================================================

local function GetGroupSystemSettings()
    local profile = DDingUI.db and DDingUI.db.profile
    return profile and profile.groupSystem
end

local function GetGroupSettings(groupName)
    local gs = GetGroupSystemSettings()
    return gs and gs.groups and gs.groups[groupName]
end

local function GetSpellAssignments()
    local gs = GetGroupSystemSettings()
    return gs and gs.spellAssignments or {}
end

local function SaveCurrentSpecNow()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
end

local function BuildCDMOrderToken(spellName)
    if not spellName or spellName == "" then return nil end
    return "cdm:" .. tostring(spellName)
end

local function IsBuffSpellKey(spellName)
    return type(spellName) == "string" and spellName:match("^buff_") ~= nil
end

local function IsBuffGroup(groupName, groupSettings)
    if groupName == "Buffs" then return true end
    return groupSettings and groupSettings.groupCategory == "buff"
end

local function CanAssignCDMSpellToGroup(spellName, groupName, groupSettings)
    if not groupSettings then return false end
    if groupSettings.groupType ~= "dynamic" then return true end
    return IsBuffSpellKey(spellName) and IsBuffGroup(groupName, groupSettings)
end

local function GetUnassignedBuffSpells(gs, create)
    if not gs then return nil end
    if type(gs.unassignedBuffSpells) ~= "table" then
        if not create then return nil end
        gs.unassignedBuffSpells = {}
    end
    return gs.unassignedBuffSpells
end

local function BuildDynamicOrderToken(iconKey)
    if not iconKey or iconKey == "" then return nil end
    return "dyn:" .. tostring(iconKey)
end

local function IsCDMOrderToken(token)
    return type(token) == "string" and (token:match("^cdm:") or token:match("^cdm_id:"))
end

local function SafeNumber(value)
    if value == nil then return nil end
    local ok, result = pcall(function()
        if issecretvalue and issecretvalue(value) then return nil end
        return tonumber(value)
    end)
    if ok then return result end
    return nil
end

local pvpIconOrderCache = {}
local copiedBuffConversionSignature
local cdmBuffMatchContext
local cdmBuffMatchContextAt = 0
local cdmBuffMatchContextTTL = 0.5
local classifiedGroups = {}
local classificationByID = {}
local classificationRoutes

local function IsPvPInstance()
    return DDingUI.IsPvPInstance and DDingUI:IsPvPInstance()
end

local RemoveTokenFromList
local InsertCDMTokenByDefaultOrder

local function BuildOrderMap(groupSettings)
    local map = {}
    local order = groupSettings and groupSettings.iconOrder
    if type(order) ~= "table" then return map end
    for index, token in ipairs(order) do
        if type(token) == "string" and token ~= "" and not map[token] then
            map[token] = index
        end
    end
    return map
end

local function BuildEntryOrderToken(entry)
    if not entry then return nil end
    local spellName = entry.spellName
    if (not spellName or spellName == "") and entry.cooldownID then
        local cdm = DDingUI.CDMHookEngine or DDingUI.FrameController
        pcall(function()
            if cdm and cdm.GetSpellNameForID then
                spellName = cdm:GetSpellNameForID(entry.cooldownID)
            end
        end)
    end
    if spellName and spellName ~= "" then
        return BuildCDMOrderToken(spellName)
    end
    local cooldownID = SafeNumber(entry.cooldownID)
    if cooldownID then
        return "cdm_id:" .. tostring(cooldownID)
    end
    return nil
end

local function SafeLayoutIndexForEntry(entry)
    if not entry then return 0 end
    local icon = entry.icon
    if icon then
        local layoutIndex = SafeNumber(icon.layoutIndex)
        if layoutIndex then return layoutIndex end
        local iconCooldownID = SafeNumber(icon.cooldownID)
        if iconCooldownID then return iconCooldownID end
    end
    local cooldownID = SafeNumber(entry.cooldownID)
    if cooldownID then return cooldownID end
    return 0
end

local function CompareByCurrentLayout(a, b)
    local aLayout = SafeLayoutIndexForEntry(a)
    local bLayout = SafeLayoutIndexForEntry(b)
    if aLayout ~= bLayout then return aLayout < bLayout end

    local aCooldownID = SafeNumber(a and a.cooldownID) or 0
    local bCooldownID = SafeNumber(b and b.cooldownID) or 0
    if aCooldownID ~= bCooldownID then return aCooldownID < bCooldownID end

    return tostring(a and a._ddGroupOrderToken or "") < tostring(b and b._ddGroupOrderToken or "")
end

local function BuildCurrentCDMTokenOrder(iconList)
    local entries = {}
    for _, entry in ipairs(iconList or {}) do
        if IsCDMOrderToken(entry and entry._ddGroupOrderToken) then
            entries[#entries + 1] = entry
        end
    end
    table.sort(entries, CompareByCurrentLayout)

    local tokens, seen = {}, {}
    for _, entry in ipairs(entries) do
        local token = entry._ddGroupOrderToken
        if token and not seen[token] then
            tokens[#tokens + 1] = token
            seen[token] = true
        end
    end
    return tokens
end

local function SyncStableCDMOrder(groupSettings, iconList)
    if not groupSettings then return nil end

    local stableOrder = groupSettings._cdmStableOrder
    if type(stableOrder) ~= "table" then
        stableOrder = {}
        local manualOrder = type(groupSettings.iconOrder) == "table" and groupSettings.iconOrder or {}
        for _, token in ipairs(manualOrder) do
            if IsCDMOrderToken(token) then
                stableOrder[#stableOrder + 1] = token
            end
        end
        groupSettings._cdmStableOrder = stableOrder
    end

    local seen, orderMap = {}, {}
    for index, token in ipairs(stableOrder) do
        if IsCDMOrderToken(token) and not orderMap[token] then
            seen[token] = true
            orderMap[token] = index
        end
    end

    local hasMissingToken = false
    for _, entry in ipairs(iconList or {}) do
        local token = entry and entry._ddGroupOrderToken
        if IsCDMOrderToken(token) and not seen[token] then
            hasMissingToken = true
            break
        end
    end
    if not hasMissingToken then return orderMap end

    local currentOrder = BuildCurrentCDMTokenOrder(iconList)
    for _, token in ipairs(currentOrder) do
        if not seen[token] then
            if InsertCDMTokenByDefaultOrder then
                InsertCDMTokenByDefaultOrder(stableOrder, seen, currentOrder, token)
            else
                stableOrder[#stableOrder + 1] = token
                seen[token] = true
            end
        end
    end

    wipe(orderMap)
    for index, token in ipairs(stableOrder) do
        if IsCDMOrderToken(token) and not orderMap[token] then
            orderMap[token] = index
        end
    end
    return orderMap
end

local function SortIconListForGroup(groupName, iconList, groupSettings)
    if type(iconList) ~= "table" then return end

    local orderMap = BuildOrderMap(groupSettings)
    for _, entry in ipairs(iconList) do
        entry._ddGroupOrderToken = BuildEntryOrderToken(entry)
    end
    local stableOrderMap = SyncStableCDMOrder(groupSettings, iconList)

    local function StableOrderForEntry(entry)
        local token = entry and entry._ddGroupOrderToken
        return (token and stableOrderMap and stableOrderMap[token]) or SafeLayoutIndexForEntry(entry)
    end

    local function CompareByStableOrder(a, b)
        local aOrder = StableOrderForEntry(a)
        local bOrder = StableOrderForEntry(b)
        if aOrder ~= bOrder then return aOrder < bOrder end
        return CompareByCurrentLayout(a, b)
    end

    local function ExplicitRank(entry)
        local token = entry and entry._ddGroupOrderToken
        return token and orderMap[token] or nil
    end

    local cdmAnchors = {}
    for _, entry in ipairs(iconList) do
        local token = entry and entry._ddGroupOrderToken
        local rank = ExplicitRank(entry)
        if rank and IsCDMOrderToken(token) then
            cdmAnchors[#cdmAnchors + 1] = {
                layout = StableOrderForEntry(entry),
                rank = rank,
            }
        end
    end
    table.sort(cdmAnchors, function(a, b)
        return (a.layout or 0) < (b.layout or 0)
    end)

    local function ImplicitCDMRank(entry)
        local token = entry and entry._ddGroupOrderToken
        if not token or orderMap[token] or not IsCDMOrderToken(token) then return nil end

        local layout = StableOrderForEntry(entry)
        local prevAnchor, nextAnchor
        for _, anchor in ipairs(cdmAnchors) do
            if anchor.layout < layout then
                prevAnchor = anchor
            elseif anchor.layout > layout then
                nextAnchor = anchor
                break
            end
        end

        if prevAnchor and nextAnchor and nextAnchor.rank > prevAnchor.rank then
            local span = nextAnchor.layout - prevAnchor.layout
            if span > 0 then
                local ratio = (layout - prevAnchor.layout) / span
                return prevAnchor.rank + ((nextAnchor.rank - prevAnchor.rank) * ratio) + (layout * 0.001)
            end
        elseif prevAnchor then
            return prevAnchor.rank + 500 + (layout * 0.001)
        elseif nextAnchor then
            return nextAnchor.rank - 500 + (layout * 0.001)
        end

        return nil
    end

    if not IsPvPInstance() then
        pvpIconOrderCache[groupName] = nil
        table.sort(iconList, function(a, b)
            local aRank = ExplicitRank(a) or ImplicitCDMRank(a)
            local bRank = ExplicitRank(b) or ImplicitCDMRank(b)
            if aRank or bRank then
                aRank = aRank or 100000000 + StableOrderForEntry(a)
                bRank = bRank or 100000000 + StableOrderForEntry(b)
                if aRank ~= bRank then return aRank < bRank end
            end
            return CompareByStableOrder(a, b)
        end)
        return
    end

    table.sort(iconList, function(a, b)
        local aRank = ExplicitRank(a) or ImplicitCDMRank(a)
        local bRank = ExplicitRank(b) or ImplicitCDMRank(b)
        if aRank or bRank then
            aRank = aRank or 100000000 + StableOrderForEntry(a)
            bRank = bRank or 100000000 + StableOrderForEntry(b)
            if aRank ~= bRank then return aRank < bRank end
        end
        return CompareByStableOrder(a, b)
    end)

    local cache = pvpIconOrderCache[groupName]
    if not cache then
        cache = { ranks = {}, nextRank = 1 }
        pvpIconOrderCache[groupName] = cache
    end
    for index, entry in ipairs(iconList) do
        local token = entry._ddGroupOrderToken
        if token and not cache.ranks[token] then
            local prevRank, nextRank
            for i = index - 1, 1, -1 do
                local prevToken = iconList[i] and iconList[i]._ddGroupOrderToken
                if prevToken and cache.ranks[prevToken] then
                    prevRank = cache.ranks[prevToken]
                    break
                end
            end
            for i = index + 1, #iconList do
                local nextToken = iconList[i] and iconList[i]._ddGroupOrderToken
                if nextToken and cache.ranks[nextToken] then
                    nextRank = cache.ranks[nextToken]
                    break
                end
            end

            if prevRank and nextRank and nextRank > prevRank then
                cache.ranks[token] = (prevRank + nextRank) / 2
            elseif prevRank then
                cache.ranks[token] = prevRank + 0.5
            elseif nextRank then
                cache.ranks[token] = nextRank - 0.5
            else
                cache.ranks[token] = cache.nextRank
                cache.nextRank = cache.nextRank + 1
            end
            if cache.ranks[token] >= cache.nextRank then
                cache.nextRank = cache.ranks[token] + 1
            end
        end
    end

    table.sort(iconList, function(a, b)
        local aRank = ExplicitRank(a)
        local bRank = ExplicitRank(b)
        if aRank or bRank then
            aRank = aRank or 100000000 + (cache.ranks[a and a._ddGroupOrderToken] or StableOrderForEntry(a))
            bRank = bRank or 100000000 + (cache.ranks[b and b._ddGroupOrderToken] or StableOrderForEntry(b))
            if aRank ~= bRank then return aRank < bRank end
        end

        local aCached = cache.ranks[a and a._ddGroupOrderToken]
        local bCached = cache.ranks[b and b._ddGroupOrderToken]
        if aCached or bCached then
            aCached = aCached or 100000000 + StableOrderForEntry(a)
            bCached = bCached or 100000000 + StableOrderForEntry(b)
            if aCached ~= bCached then return aCached < bCached end
        end
        return CompareByStableOrder(a, b)
    end)
end

local function CollectCurrentDefaultCDMTokens(gs, groupName)
    local tokens, seen, entries = {}, {}, {}
    local cdm = DDingUI.CDMHookEngine or DDingUI.FrameController
    if not cdm then return tokens, seen end

    local map
    local ok = pcall(function()
        if cdm.GetIdIconMap then
            map = cdm:GetIdIconMap()
        elseif cdm.GetIconMap then
            map = cdm:GetIconMap()
        end
    end)
    if not ok or type(map) ~= "table" then return tokens, seen end

    local unassignedBuffs = GetUnassignedBuffSpells(gs, false)
    for cooldownID, icon in pairs(map) do
        local viewerName, defaultGroup, spellName
        pcall(function()
            if cdm.GetIconSource then viewerName = cdm:GetIconSource(cooldownID) end
        end)
        pcall(function()
            if cdm.GetDefaultGroupForViewer then defaultGroup = cdm:GetDefaultGroupForViewer(viewerName) end
        end)

        if defaultGroup == groupName then
            pcall(function()
                if cdm.GetSpellNameForID then spellName = cdm:GetSpellNameForID(cooldownID) end
            end)
            if not spellName and icon then
                pcall(function()
                    if cdm.GetSpellName then spellName = cdm:GetSpellName(icon) end
                end)
            end

            local token = BuildCDMOrderToken(spellName)
            local assigned = spellName and gs and gs.spellAssignments and gs.spellAssignments[spellName]
            local blocked = spellName and unassignedBuffs and unassignedBuffs[spellName]
            if token and not blocked and (not assigned or assigned == groupName) then
                entries[#entries + 1] = {
                    token = token,
                    order = SafeNumber(icon and icon.layoutIndex) or 99999,
                    cooldownID = SafeNumber(cooldownID) or 0,
                }
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.cooldownID ~= b.cooldownID then return a.cooldownID < b.cooldownID end
        return tostring(a.token) < tostring(b.token)
    end)

    for _, entry in ipairs(entries) do
        local token = entry.token
        if token and not seen[token] then
            tokens[#tokens + 1] = token
            seen[token] = true
        end
    end

    return tokens, seen
end

RemoveTokenFromList = function(list, token)
    if type(list) ~= "table" or not token then return false end
    local changed = false
    for i = #list, 1, -1 do
        if list[i] == token then
            table.remove(list, i)
            changed = true
        end
    end
    return changed
end

local function HasToken(list, token)
    if type(list) ~= "table" or not token then return false end
    for _, existing in ipairs(list) do
        if existing == token then return true end
    end
    return false
end

local function FindTokenIndex(list, token)
    if type(list) ~= "table" or not token then return nil end
    for index, existing in ipairs(list) do
        if existing == token then return index end
    end
    return nil
end

InsertCDMTokenByDefaultOrder = function(list, seen, orderedCDM, token)
    if type(list) ~= "table" or type(orderedCDM) ~= "table" or not token or seen[token] then return end

    local defaultIndex
    for index, existing in ipairs(orderedCDM) do
        if existing == token then
            defaultIndex = index
            break
        end
    end
    if not defaultIndex then return end

    for index = defaultIndex + 1, #orderedCDM do
        local nextToken = orderedCDM[index]
        local insertIndex = FindTokenIndex(list, nextToken)
        if insertIndex then
            table.insert(list, insertIndex, token)
            seen[token] = true
            return
        end
    end

    for index = defaultIndex - 1, 1, -1 do
        local prevToken = orderedCDM[index]
        local insertIndex = FindTokenIndex(list, prevToken)
        if insertIndex then
            table.insert(list, insertIndex + 1, token)
            seen[token] = true
            return
        end
    end

    list[#list + 1] = token
    seen[token] = true
end

local function RemoveTokenFromAllGroups(gs, token, exceptGroup)
    if not gs or not gs.groups or not token then return false end
    local changed = false
    for groupName, settings in pairs(gs.groups) do
        if groupName ~= exceptGroup and settings and RemoveTokenFromList(settings.iconOrder, token) then
            changed = true
        end
    end
    return changed
end

local function GetLinkedDynamicIcons(groupSettings)
    local sourceKey = groupSettings and groupSettings.sourceGroupKey
    if not sourceKey then return nil end
    local profile = DDingUI.db and DDingUI.db.profile
    local dynDB = profile and profile.dynamicIcons
    local sourceGroup = dynDB and dynDB.groups and dynDB.groups[sourceKey]
    return sourceGroup and sourceGroup.icons
end

local function NormalizeGroupIconOrder(gs, groupName)
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings then return nil end

    local valid = {}
    local orderedCDM = {}
    local orderedManualCDM = {}
    local orderedDynamic = {}
    local currentCDMSeen

    orderedCDM, currentCDMSeen = CollectCurrentDefaultCDMTokens(gs, groupName)
    for _, token in ipairs(orderedCDM) do
        valid[token] = true
    end

    if gs.spellAssignments then
        for spellName, assignedGroup in pairs(gs.spellAssignments) do
            if assignedGroup == groupName then
                local token = BuildCDMOrderToken(spellName)
                if token then
                    valid[token] = true
                    if not currentCDMSeen[token] then
                        orderedManualCDM[#orderedManualCDM + 1] = token
                    end
                end
            end
        end
    end
    table.sort(orderedManualCDM)

    local dynamicIcons = GetLinkedDynamicIcons(groupSettings)
    if type(dynamicIcons) == "table" then
        for _, iconKey in ipairs(dynamicIcons) do
            local token = BuildDynamicOrderToken(iconKey)
            if token then
                valid[token] = true
                orderedDynamic[#orderedDynamic + 1] = token
            end
        end
    end

    local normalized = {}
    local seen = {}
    if type(groupSettings.iconOrder) == "table" then
        for _, token in ipairs(groupSettings.iconOrder) do
            if (valid[token] or IsCDMOrderToken(token)) and not seen[token] then
                normalized[#normalized + 1] = token
                seen[token] = true
            end
        end
    end

    for _, token in ipairs(orderedCDM) do
        if not seen[token] then
            InsertCDMTokenByDefaultOrder(normalized, seen, orderedCDM, token)
        end
    end
    for _, token in ipairs(orderedManualCDM) do
        if not seen[token] then
            normalized[#normalized + 1] = token
            seen[token] = true
        end
    end
    for _, token in ipairs(orderedDynamic) do
        if not seen[token] then
            normalized[#normalized + 1] = token
            seen[token] = true
        end
    end

    groupSettings.iconOrder = normalized
    return normalized
end

local function AppendGroupIconOrderToken(gs, groupName, token)
    local groupSettings = gs and gs.groups and gs.groups[groupName]
    if not groupSettings or not token then return false end
    NormalizeGroupIconOrder(gs, groupName)
    groupSettings.iconOrder = groupSettings.iconOrder or {}
    if HasToken(groupSettings.iconOrder, token) then return false end
    groupSettings.iconOrder[#groupSettings.iconOrder + 1] = token
    return true
end

local function ReplaceGroupOrderToken(groupSettings, oldToken, newToken)
    local order = groupSettings and groupSettings.iconOrder
    if type(order) ~= "table" or not oldToken or not newToken then return false end

    local changed = false
    local primaryIndex
    for i, token in ipairs(order) do
        if token == oldToken then
            order[i] = newToken
            primaryIndex = i
            changed = true
            break
        end
    end

    if primaryIndex then
        for i = #order, 1, -1 do
            local token = order[i]
            if token == oldToken or (token == newToken and i ~= primaryIndex) then
                table.remove(order, i)
                changed = true
            end
        end
    end
    return changed
end

local function GetCopiedCDMBuffSpellName(iconData)
    if not iconData or (iconData.type ~= "spell" and iconData.type ~= "aura") then return nil end
    local settings = iconData.settings
    if not settings or settings.copiedFromCDM ~= true then return nil end

    if IsBuffSpellKey(settings.sourceSpellName) then
        return settings.sourceSpellName
    end

    local spellID = tonumber(iconData.id)
    if not spellID or spellID <= 0 then return nil end
    local ok, info = pcall(function()
        return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    end)
    local spellName = ok and info and info.name
    if type(spellName) == "string" and spellName ~= "" and not (issecretvalue and issecretvalue(spellName)) then
        return "buff_" .. spellName
    end
    return nil
end

local function AddCandidateName(names, name)
    if type(name) ~= "string" or name == "" then return end
    if issecretvalue and issecretvalue(name) then return end
    names[name:match("^buff_(.+)") or name] = true
end

local function AddCandidateSpellID(ids, names, spellID)
    spellID = SafeNumber(spellID)
    if not spellID or spellID <= 0 then return end
    ids[spellID] = true
    local ok, info = pcall(function()
        return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    end)
    if ok and info then
        AddCandidateName(names, type(info) == "table" and info.name or info)
    end
    local okName, spellName = pcall(function()
        return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    end)
    if okName then
        AddCandidateName(names, spellName)
    end
end

local function AddCandidateValue(ids, names, value)
    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        AddCandidateSpellID(ids, names, value)
        value = SafeNumber(value)
        if value and C_Spell then
            local okBase, baseID = pcall(function()
                return C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(value)
            end)
            if okBase and baseID and baseID ~= value then
                AddCandidateSpellID(ids, names, baseID)
            end
            local okOverride, overrideID = pcall(function()
                return C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(value)
            end)
            if okOverride and overrideID and overrideID ~= value then
                AddCandidateSpellID(ids, names, overrideID)
            end
        end
    elseif valueType == "table" then
        for _, spellID in pairs(value) do
            AddCandidateValue(ids, names, spellID)
        end
    end
end

local function BuildDynamicIconCandidateSets(iconData)
    local ids, names = {}, {}
    if not iconData or (iconData.type ~= "spell" and iconData.type ~= "aura") then return ids, names end
    AddCandidateValue(ids, names, iconData.id)
    local settings = iconData.settings
    if settings then
        AddCandidateName(names, settings.sourceSpellName)
        AddCandidateValue(ids, names, settings.auraAliases)
        AddCandidateValue(ids, names, settings.fallbackItems)
    end
    return ids, names
end

local function MatchesCandidateID(ids, spellID)
    spellID = SafeNumber(spellID)
    return spellID and ids[spellID] == true
end

local function GetNormalizedBuffSpellName(spellName)
    if type(spellName) ~= "string" or spellName == "" then return nil end
    if issecretvalue and issecretvalue(spellName) then return nil end
    if IsBuffSpellKey(spellName) then return spellName end
    return "buff_" .. spellName
end

local function GetFirstCandidateName(names)
    for name in pairs(names or {}) do
        return name
    end
    return nil
end

local function IconMatchesCandidateIDs(icon, cooldownID, ids)
    if MatchesCandidateID(ids, cooldownID) then return true end
    if icon then
        local okAura, auraSpellID = pcall(function() return icon.auraSpellID end)
        if okAura and MatchesCandidateID(ids, auraSpellID) then return true end
        local okInfo, cooldownInfo = pcall(function() return icon.cooldownInfo end)
        if okInfo and type(cooldownInfo) == "table" then
            if MatchesCandidateID(ids, cooldownInfo.overrideTooltipSpellID)
                or MatchesCandidateID(ids, cooldownInfo.overrideSpellID)
                or MatchesCandidateID(ids, cooldownInfo.spellID)
            then
                return true
            end
            if type(cooldownInfo.linkedSpellIDs) == "table" then
                for _, linkedID in ipairs(cooldownInfo.linkedSpellIDs) do
                    if MatchesCandidateID(ids, linkedID) then return true end
                end
            end
        end
    end
    if cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if ok and type(info) == "table" then
            if MatchesCandidateID(ids, info.overrideTooltipSpellID)
                or MatchesCandidateID(ids, info.overrideSpellID)
                or MatchesCandidateID(ids, info.spellID)
            then
                return true
            end
            if type(info.linkedSpellIDs) == "table" then
                for _, linkedID in ipairs(info.linkedSpellIDs) do
                    if MatchesCandidateID(ids, linkedID) then return true end
                end
            end
        end
    end
    return false
end

local function GetSpellNameFromID(spellID)
    spellID = SafeNumber(spellID)
    if not spellID or spellID <= 0 then return nil end
    local okInfo, info = pcall(function()
        return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    end)
    if okInfo and type(info) == "table" then
        if type(info.name) == "string" and info.name ~= "" and not (issecretvalue and issecretvalue(info.name)) then
            return info.name
        end
    end
    local okName, name = pcall(function()
        return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    end)
    if okName and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
        return name
    end
    return nil
end

local function GetCooldownInfoPreferredSpellID(info)
    if type(info) ~= "table" then return nil end
    return SafeNumber(info.overrideTooltipSpellID)
        or SafeNumber(info.overrideSpellID)
        or SafeNumber(info.spellID)
end

local function CooldownInfoMatchesCandidates(info, ids, names)
    if type(info) ~= "table" then return false end
    if MatchesCandidateID(ids, info.overrideTooltipSpellID)
        or MatchesCandidateID(ids, info.overrideSpellID)
        or MatchesCandidateID(ids, info.spellID)
    then
        return true
    end
    if type(info.linkedSpellIDs) == "table" then
        for _, linkedID in ipairs(info.linkedSpellIDs) do
            if MatchesCandidateID(ids, linkedID) then return true end
        end
    end
    local preferredName = GetSpellNameFromID(GetCooldownInfoPreferredSpellID(info))
    return preferredName and names[preferredName] == true
end

local function AddCDMBuffMatchName(context, spellName)
    local normalized = GetNormalizedBuffSpellName(spellName)
    if not normalized then return end
    local cleanName = spellName:match("^buff_(.+)") or spellName
    context.names[cleanName] = normalized
end

local function AddCDMBuffMatchID(context, spellID, normalizedSpellName)
    spellID = SafeNumber(spellID)
    if not spellID or not normalizedSpellName then return end
    context.ids[spellID] = normalizedSpellName
end

local function AddCooldownInfoToBuffMatchContext(context, info, normalizedSpellName)
    if type(info) ~= "table" then return end
    local preferredName = GetSpellNameFromID(GetCooldownInfoPreferredSpellID(info))
    if preferredName then
        AddCDMBuffMatchName(context, preferredName)
        normalizedSpellName = normalizedSpellName or GetNormalizedBuffSpellName(preferredName)
    end
    AddCDMBuffMatchID(context, info.overrideTooltipSpellID, normalizedSpellName)
    AddCDMBuffMatchID(context, info.overrideSpellID, normalizedSpellName)
    AddCDMBuffMatchID(context, info.spellID, normalizedSpellName)
    if type(info.linkedSpellIDs) == "table" then
        for _, linkedID in ipairs(info.linkedSpellIDs) do
            AddCDMBuffMatchID(context, linkedID, normalizedSpellName)
        end
    end
end

local function BuildCDMBuffMatchContext()
    local context = { ids = {}, names = {} }
    local cdm = DDingUI.CDMHookEngine or DDingUI.FrameController
    if not cdm then return context end

    local map
    local okMap = pcall(function()
        if cdm.GetIdIconMap then
            map = cdm:GetIdIconMap()
        elseif cdm.GetIconMap then
            map = cdm:GetIconMap()
        end
    end)
    if not okMap or type(map) ~= "table" then return context end

    for cooldownID, icon in pairs(map) do
        local viewerName, defaultGroup, spellName
        pcall(function()
            if cdm.GetIconSource then viewerName = cdm:GetIconSource(cooldownID) end
        end)
        pcall(function()
            if cdm.GetDefaultGroupForViewer then defaultGroup = cdm:GetDefaultGroupForViewer(viewerName) end
        end)
        if defaultGroup == "Buffs" or viewerName == "BuffIconCooldownViewer" then
            pcall(function()
                if cdm.GetSpellNameForID then spellName = cdm:GetSpellNameForID(cooldownID) end
            end)
            if not spellName and icon then
                pcall(function()
                    if cdm.GetSpellName then spellName = cdm:GetSpellName(icon) end
                end)
            end
            local normalizedSpellName = GetNormalizedBuffSpellName(spellName)
            if spellName then
                AddCDMBuffMatchName(context, spellName)
            end
            AddCDMBuffMatchID(context, cooldownID, normalizedSpellName)
            if icon then
                pcall(function()
                    AddCDMBuffMatchID(context, icon.auraSpellID, normalizedSpellName)
                end)
                pcall(function()
                    AddCooldownInfoToBuffMatchContext(context, icon.cooldownInfo, normalizedSpellName)
                end)
            end
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                if okInfo then
                    AddCooldownInfoToBuffMatchContext(context, info, normalizedSpellName)
                end
            end
        end
    end

    return context
end

local function GetCDMBuffMatchContext()
    local now = GetTime and GetTime() or 0
    if cdmBuffMatchContext and (now - cdmBuffMatchContextAt) < cdmBuffMatchContextTTL then
        return cdmBuffMatchContext
    end
    cdmBuffMatchContext = BuildCDMBuffMatchContext()
    cdmBuffMatchContextAt = now
    return cdmBuffMatchContext
end

local function FindInCDMBuffMatchContext(iconData, context)
    if not context then return nil end
    local ids, names = BuildDynamicIconCandidateSets(iconData)
    for name in pairs(names) do
        if context.names[name] then
            return context.names[name]
        end
    end
    for spellID in pairs(ids) do
        if context.ids[spellID] then
            return context.ids[spellID]
        end
    end
    return nil
end

local function FindMatchingCooldownViewerBuffSpellName(iconData)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
    if not (Enum and Enum.CooldownViewerCategory) then return nil end

    local ids, names = BuildDynamicIconCandidateSets(iconData)
    if not next(ids) and not next(names) then return nil end

    local categories = Enum.CooldownViewerCategory
    local categoryNames = { "TrackedBuff", "Essential", "Utility", "TrackedBar" }
    local seenCooldownIDs = {}

    for _, categoryName in ipairs(categoryNames) do
        local categoryID = categories[categoryName]
        if categoryID then
            local okSet, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, categoryID, true)
            if okSet and type(cooldownIDs) == "table" then
                for _, cooldownID in ipairs(cooldownIDs) do
                    local safeCooldownID = SafeNumber(cooldownID)
                    if safeCooldownID and not seenCooldownIDs[safeCooldownID] then
                        seenCooldownIDs[safeCooldownID] = true
                        local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, safeCooldownID)
                        if okInfo and CooldownInfoMatchesCandidates(info, ids, names) then
                            local spellName = GetSpellNameFromID(GetCooldownInfoPreferredSpellID(info)) or GetFirstCandidateName(names)
                            return GetNormalizedBuffSpellName(spellName)
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function FindMatchingCDMBuffSpellName(iconData)
    local viewerSpellName = FindMatchingCooldownViewerBuffSpellName(iconData)
    if viewerSpellName then return viewerSpellName end

    local ids, names = BuildDynamicIconCandidateSets(iconData)
    if not next(ids) and not next(names) then return nil end

    local cdm = DDingUI.CDMHookEngine or DDingUI.FrameController
    if not cdm then return nil end

    local map
    local okMap = pcall(function()
        if cdm.GetIdIconMap then
            map = cdm:GetIdIconMap()
        elseif cdm.GetIconMap then
            map = cdm:GetIconMap()
        end
    end)
    if not okMap or type(map) ~= "table" then return nil end

    for cooldownID, icon in pairs(map) do
        local viewerName, defaultGroup, spellName
        pcall(function()
            if cdm.GetIconSource then viewerName = cdm:GetIconSource(cooldownID) end
        end)
        pcall(function()
            if cdm.GetDefaultGroupForViewer then defaultGroup = cdm:GetDefaultGroupForViewer(viewerName) end
        end)
        if defaultGroup == "Buffs" or viewerName == "BuffIconCooldownViewer" then
            pcall(function()
                if cdm.GetSpellNameForID then spellName = cdm:GetSpellNameForID(cooldownID) end
            end)
            if not spellName and icon then
                pcall(function()
                    if cdm.GetSpellName then spellName = cdm:GetSpellName(icon) end
                end)
            end
            local cleanSpellName = spellName and (spellName:match("^buff_(.+)") or spellName)
            if cleanSpellName and names[cleanSpellName] then
                return GetNormalizedBuffSpellName(spellName)
            end
            if IconMatchesCandidateIDs(icon, cooldownID, ids) then
                return GetNormalizedBuffSpellName(spellName or cleanSpellName or GetFirstCandidateName(names))
            end
        end
    end
    return nil
end

local function GetCDMBuffSpellNameForDynamicIcon(iconData)
    return GetCopiedCDMBuffSpellName(iconData) or FindMatchingCDMBuffSpellName(iconData)
end

local function ConvertCopiedBuffDynamicIcons(gs)
    if DDingUI._convertingCopiedBuffIcons then return false end
    if not gs or not gs.groups then return false end

    local profile = DDingUI.db and DDingUI.db.profile
    local dynDB = profile and profile.dynamicIcons
    local iconDataDB = dynDB and dynDB.iconData
    local ci = DDingUI.CustomIcons
    if not iconDataDB or not ci or not ci.RemoveDynamicIcon then return false end

    local converted = {}
    local matchContext
    for groupName, groupSettings in pairs(gs.groups) do
        if groupSettings and IsBuffGroup(groupName, groupSettings) then
            local sourceKey = groupSettings.sourceGroupKey
            local dynGroup = sourceKey and dynDB.groups and dynDB.groups[sourceKey]
            if dynGroup and dynGroup.icons then
                for _, iconKey in ipairs(dynGroup.icons) do
                    local iconData = iconDataDB[iconKey]
                    local spellName = GetCopiedCDMBuffSpellName(iconData)
                    if not spellName then
                        matchContext = matchContext or GetCDMBuffMatchContext()
                        spellName = FindInCDMBuffMatchContext(iconData, matchContext)
                    end
                    if spellName then
                        converted[#converted + 1] = {
                            groupName = groupName,
                            groupSettings = groupSettings,
                            iconKey = iconKey,
                            spellName = spellName,
                        }
                    end
                end
            end
        end
    end
    if #converted == 0 then return false end

    if not gs.spellAssignments then gs.spellAssignments = {} end
    DDingUI._convertingCopiedBuffIcons = true

    for _, entry in ipairs(converted) do
        local newToken = BuildCDMOrderToken(entry.spellName)
        if newToken then
            if gs.spellAssignments[entry.spellName] ~= entry.groupName then
                RemoveTokenFromAllGroups(gs, newToken)
            end
            gs.spellAssignments[entry.spellName] = entry.groupName
            local unassignedBuffs = GetUnassignedBuffSpells(gs, false)
            if unassignedBuffs then
                unassignedBuffs[entry.spellName] = nil
            end
            AppendGroupIconOrderToken(gs, entry.groupName, newToken)
            ReplaceGroupOrderToken(entry.groupSettings, BuildDynamicOrderToken(entry.iconKey), newToken)
        end
    end

    for _, entry in ipairs(converted) do
        pcall(ci.RemoveDynamicIcon, ci, entry.iconKey)
    end

    DDingUI._convertingCopiedBuffIcons = nil
    return true
end

local function AppendSignatureValues(parts, value)
    if type(value) ~= "table" then
        parts[#parts + 1] = tostring(value or "")
        return
    end

    local values = {}
    for _, entry in pairs(value) do
        local safeValue = SafeNumber(entry)
        if safeValue then
            values[#values + 1] = tostring(safeValue)
        elseif type(entry) == "string" then
            values[#values + 1] = entry
        end
    end
    table.sort(values)
    parts[#parts + 1] = table.concat(values, ",")
end

local function BuildCopiedBuffConversionSignature(gs)
    local profile = DDingUI.db and DDingUI.db.profile
    local dynDB = profile and profile.dynamicIcons
    local iconDataDB = dynDB and dynDB.iconData
    local dynamicGroups = dynDB and dynDB.groups
    local parts = {}

    if gs and gs.groups and iconDataDB and dynamicGroups then
        local groupNames = {}
        for groupName, groupSettings in pairs(gs.groups) do
            if groupSettings and IsBuffGroup(groupName, groupSettings) and groupSettings.sourceGroupKey then
                groupNames[#groupNames + 1] = groupName
            end
        end
        table.sort(groupNames)

        for _, groupName in ipairs(groupNames) do
            local groupSettings = gs.groups[groupName]
            local sourceKey = groupSettings.sourceGroupKey
            local dynGroup = dynamicGroups[sourceKey]
            parts[#parts + 1] = groupName
            parts[#parts + 1] = tostring(sourceKey)
            for _, iconKey in ipairs((dynGroup and dynGroup.icons) or {}) do
                local iconData = iconDataDB[iconKey]
                local settings = iconData and iconData.settings
                parts[#parts + 1] = tostring(iconKey)
                parts[#parts + 1] = tostring(iconData and iconData.type or "")
                parts[#parts + 1] = tostring(SafeNumber(iconData and iconData.id) or "")
                parts[#parts + 1] = tostring(settings and settings.copiedFromCDM == true)
                parts[#parts + 1] = tostring(settings and settings.sourceSpellName or "")
                AppendSignatureValues(parts, settings and settings.auraAliases)
                AppendSignatureValues(parts, settings and settings.fallbackItems)
            end
        end
    end

    local cdm = DDingUI.CDMHookEngine or DDingUI.FrameController
    local map = cdm and ((cdm.GetIdIconMap and cdm:GetIdIconMap()) or (cdm.GetIconMap and cdm:GetIconMap()))
    local cooldownIDs = {}
    if type(map) == "table" then
        for cooldownID in pairs(map) do
            local safeCooldownID = SafeNumber(cooldownID)
            if safeCooldownID then
                cooldownIDs[#cooldownIDs + 1] = safeCooldownID
            end
        end
    end
    table.sort(cooldownIDs)
    for _, cooldownID in ipairs(cooldownIDs) do
        parts[#parts + 1] = tostring(cooldownID)
    end

    return table.concat(parts, "\31")
end

local function NormalizeGroupOrders(gs)
    if not gs or not gs.groups then return nil end

    local list = {}
    for name, settings in pairs(gs.groups) do
        list[#list + 1] = {
            name = name,
            settings = settings,
            order = tonumber(settings and settings.order) or 999,
        }
    end

    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.name) < tostring(b.name)
    end)

    for i, entry in ipairs(list) do
        if entry.settings then
            entry.settings.order = i
        end
    end

    return list
end

-- ============================================================
-- 그룹 CRUD (변경 없음)
-- ============================================================

function GroupManager:GetGroups()
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups then return {} end

    return NormalizeGroupOrders(gs) or {}
end

function GroupManager:GetGroupByName(groupName)
    return GetGroupSettings(groupName)
end

function GroupManager:CreateGroup(name, settings)
    local gs = GetGroupSystemSettings()
    if not gs then return false end
    if gs.groups[name] then return false end -- 이미 존재

    -- 최대 order 찾기
    local maxOrder = 0
    for _, g in pairs(gs.groups) do
        if g.order and g.order > maxOrder then
            maxOrder = g.order
        end
    end

    -- 기본 그룹 설정 복사 + 오버라이드
    local defaults = {
        order = maxOrder + 1,
        groupType = "dynamic",
        groupCategory = "skill", -- "skill" | "buff" (사용자 변경 가능)
        autoFilter = "ALL",
        enabled = true,
        iconSize = 32,
        aspectRatioCrop = 1.0,
        spacing = 2,
        zoom = 0.08,
        borderSize = 1,
        borderColor = { 0, 0, 0, 1 },
        direction = "RIGHT",
        growDirection = "DOWN",
        rowLimit = 8,
        swipeColor = { 0, 0, 0, 0.8 },
        swipeReverse = true,
        showInactiveIcons = false,
        iconMotion = true,
        iconMotionDuration = 0.18,
        anchorPoint = "CENTER",
        offsetX = 0,
        offsetY = 0,
    }

    if settings then
        for k, v in pairs(settings) do
            defaults[k] = v
        end
    end

    gs.groups[name] = defaults
    -- 삭제 기록에서 제거 (사용자가 다시 만든 것)
    if gs.deletedGroups then gs.deletedGroups[name] = nil end

    -- [FIX] 생성 즉시 CustomIcons 그룹 연결 (sourceGroupKey가 없으면 UpdateDynamicGroup이 hide 처리)
    -- CDM CDM처럼: 그룹 생성 시점에 모든 필요한 데이터를 즉시 준비
    local ci = DDingUI.CustomIcons
    if ci and ci.CreateDynamicGroup and not defaults.sourceGroupKey then
        local sourceKey = ci:CreateDynamicGroup(name)
        if sourceKey then
            defaults.sourceGroupKey = sourceKey
        end
    end

    SaveCurrentSpecNow()
    return true
end

function GroupManager:DeleteGroup(name)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups[name] then return false end

    -- 이 그룹에 할당된 스펠도 정리
    if gs.spellAssignments then
        for spellKey, assignedGroup in pairs(gs.spellAssignments) do
            if assignedGroup == name then
                gs.spellAssignments[spellKey] = nil
            end
        end
    end

    -- 삭제 기록 (SyncDynamicGroups가 재생성하지 않도록)
    if not gs.deletedGroups then gs.deletedGroups = {} end
    gs.deletedGroups[name] = true

    gs.groups[name] = nil
    SaveCurrentSpecNow()
    return true
end

function GroupManager:RenameGroup(oldName, newName)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups[oldName] or gs.groups[newName] then return false end

    gs.groups[newName] = gs.groups[oldName]
    gs.groups[oldName] = nil

    -- 스펠 할당도 업데이트
    if gs.spellAssignments then
        for spellKey, assignedGroup in pairs(gs.spellAssignments) do
            if assignedGroup == oldName then
                gs.spellAssignments[spellKey] = newName
            end
        end
    end

    SaveCurrentSpecNow()
    return true
end

function GroupManager:ReorderGroup(sourceName, targetName, insertAfter)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups or not sourceName or not targetName then return false end
    if sourceName == targetName then return false end
    if not gs.groups[sourceName] or not gs.groups[targetName] then return false end

    local list = NormalizeGroupOrders(gs)
    if not list then return false end

    local sourceIndex, targetIndex
    for i, entry in ipairs(list) do
        if entry.name == sourceName then sourceIndex = i end
        if entry.name == targetName then targetIndex = i end
    end
    if not sourceIndex or not targetIndex or sourceIndex == targetIndex then return false end

    local moving = table.remove(list, sourceIndex)
    if sourceIndex < targetIndex then
        targetIndex = targetIndex - 1
    end

    local insertIndex = insertAfter and (targetIndex + 1) or targetIndex
    if insertIndex < 1 then insertIndex = 1 end
    if insertIndex > #list + 1 then insertIndex = #list + 1 end
    table.insert(list, insertIndex, moving)

    for i, entry in ipairs(list) do
        if entry.settings then
            entry.settings.order = i
        end
    end

    SaveCurrentSpecNow()
    return true
end

-- ============================================================
-- 스펠 수동 할당 (키: spellName)
-- [REFACTOR] spellID → spellName 기반으로 변경
-- ============================================================

function GroupManager:AssignSpell(spellName, groupName)
    local gs = GetGroupSystemSettings()
    if not gs then return false end
    local group = gs.groups and gs.groups[groupName]
    if not CanAssignCDMSpellToGroup(spellName, groupName, group) then
        return false
    end
    if not gs.spellAssignments then gs.spellAssignments = {} end
    local token = BuildCDMOrderToken(spellName)
    local previousGroup = gs.spellAssignments[spellName]
    if previousGroup ~= groupName then
        RemoveTokenFromAllGroups(gs, token)
    end
    local unassignedBuffs = IsBuffSpellKey(spellName) and GetUnassignedBuffSpells(gs, false)
    if unassignedBuffs then
        unassignedBuffs[spellName] = nil
    end
    gs.spellAssignments[spellName] = groupName
    AppendGroupIconOrderToken(gs, groupName, token)
    SaveCurrentSpecNow()
    return true
end

function GroupManager:UnassignSpell(spellName, opts)
    local gs = GetGroupSystemSettings()
    if not gs then return false end
    if gs.spellAssignments then
        gs.spellAssignments[spellName] = nil
    end
    if opts and opts.toUnassignedBuffPool and IsBuffSpellKey(spellName) then
        local unassignedBuffs = GetUnassignedBuffSpells(gs, true)
        unassignedBuffs[spellName] = true
    end
    RemoveTokenFromAllGroups(gs, BuildCDMOrderToken(spellName))
    SaveCurrentSpecNow()
    return true
end

function GroupManager:MoveSpellToUnassigned(spellName)
    return self:UnassignSpell(spellName, { toUnassignedBuffPool = true })
end

function GroupManager:AssignMatchingCDMBuffIcon(iconData, groupName)
    local gs = GetGroupSystemSettings()
    local group = gs and gs.groups and gs.groups[groupName]
    if not IsBuffGroup(groupName, group) then return nil end

    local spellName = GetCDMBuffSpellNameForDynamicIcon(iconData)
    if not spellName then return nil end
    if self:AssignSpell(spellName, groupName) then
        return spellName
    end
    return nil
end

function GroupManager:NormalizeGroupIconOrder(groupName)
    local gs = GetGroupSystemSettings()
    return NormalizeGroupIconOrder(gs, groupName)
end

function GroupManager:ReorderGroupIcon(groupName, sourceToken, targetToken, insertAfter, dropAction)
    local gs = GetGroupSystemSettings()
    if not gs or not groupName or not sourceToken or not targetToken then return false end
    if sourceToken == targetToken then return false end

    local order = NormalizeGroupIconOrder(gs, groupName)
    if type(order) ~= "table" then return false end

    local sourceIndex, targetIndex
    for i, token in ipairs(order) do
        if token == sourceToken then sourceIndex = i end
        if token == targetToken then targetIndex = i end
    end
    if not sourceIndex or not targetIndex or sourceIndex == targetIndex then return false end

    if dropAction == "swap" then
        order[sourceIndex], order[targetIndex] = order[targetIndex], order[sourceIndex]
        SaveCurrentSpecNow()
        return true
    end

    local moving = table.remove(order, sourceIndex)
    if sourceIndex < targetIndex then
        targetIndex = targetIndex - 1
    end

    local insertIndex = insertAfter and (targetIndex + 1) or targetIndex
    if insertIndex < 1 then insertIndex = 1 end
    if insertIndex > #order + 1 then insertIndex = #order + 1 end
    table.insert(order, insertIndex, moving)

    SaveCurrentSpecNow()
    return true
end

function GroupManager:ReorderAssignedSpell(groupName, spellName, targetSpellName, insertAfter)
    return self:ReorderGroupIcon(groupName, BuildCDMOrderToken(spellName), BuildCDMOrderToken(targetSpellName), insertAfter)
end

function GroupManager:PruneInvalidAssignments()
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups then return false end

    local converted = false
    local conversionSignature = BuildCopiedBuffConversionSignature(gs)
    if conversionSignature ~= copiedBuffConversionSignature then
        cdmBuffMatchContext = nil
        cdmBuffMatchContextAt = 0
        converted = ConvertCopiedBuffDynamicIcons(gs)
        copiedBuffConversionSignature = BuildCopiedBuffConversionSignature(gs)
    end
    if not gs.spellAssignments then return converted == true end
    local toRemove
    for spellName, groupName in pairs(gs.spellAssignments) do
        local group = gs.groups[groupName]
        if not CanAssignCDMSpellToGroup(spellName, groupName, group) then
            if not toRemove then toRemove = {} end
            toRemove[#toRemove + 1] = spellName
        end
    end

    if not toRemove then
        if converted and DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
            DDingUI.SpecProfiles:MarkDirty()
        end
        return converted == true
    end
    for _, spellName in ipairs(toRemove) do
        gs.spellAssignments[spellName] = nil
        RemoveTokenFromAllGroups(gs, BuildCDMOrderToken(spellName))
    end

    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
    return true
end

function GroupManager:GetSpellAssignment(spellName)
    local assignments = GetSpellAssignments()
    return assignments[spellName]
end

-- ============================================================
-- CDM 뷰어 기반 분류 엔진
-- [REFACTOR] ClassifyAura(auraData) → ClassifyIcon(cooldownID)
-- ============================================================

local VIEWER_FILTERS = {
    EssentialCooldownViewer = "COOLDOWN",
    UtilityCooldownViewer = "UTILITY",
    BuffIconCooldownViewer = "HELPFUL",
}

local function BuildClassificationRoutes(gs)
    local routes = { viewer = {} }
    local filterGroups = {}
    local filterOrders = {}
    local firstOrder = math.huge

    for name, settings in pairs((gs and gs.groups) or {}) do
        if settings.enabled then
            local order = tonumber(settings.order) or 999
            if order < firstOrder then
                routes.first = name
                firstOrder = order
            end

            local filterType = settings.autoFilter
            if filterType and (not filterOrders[filterType] or order < filterOrders[filterType]) then
                filterGroups[filterType] = name
                filterOrders[filterType] = order
            end
        end
    end

    routes.all = filterGroups.ALL
    for viewerName, filterType in pairs(VIEWER_FILTERS) do
        routes.viewer[viewerName] = filterGroups[filterType]
    end
    return routes
end

local function ResolveCDMGroup(gs, groupName, spellKey)
    if not groupName then return nil end
    local group = gs.groups[groupName]
    if not CanAssignCDMSpellToGroup(spellKey, groupName, group) then return nil end
    return groupName
end

local function ClassifyIconWithContext(cooldownID, CDMHookEngine, gs, routes)
    local spellName = CDMHookEngine:GetSpellNameForID(cooldownID)

    -- [Fix C] 캐시 미스 시 아이콘에서 직접 추출 (전투 중 secret value 해제 즉시 반영)
    if not spellName then
        local icon = CDMHookEngine:GetIconFrame(cooldownID)
        if icon and CDMHookEngine.GetSpellName then
            spellName = CDMHookEngine:GetSpellName(icon)
        end
    end

    local cleanSpellName
    if spellName then
        cleanSpellName = spellName:match("^buff_(.+)") or spellName
    end

    -- [REMOVED] 0순위 다이나믹 그룹 하이재킹 제거
    -- DynamicIconBridge가 CustomIcons 프레임을 직접 제공하므로
    -- CDM 아이콘을 커스텀 그룹으로 분류하면 중복 발생 (CDM 프레임 + CustomIcons 프레임)

    -- 1순위: 수동 할당 (spellName 기반)
    -- 일반 dynamic 그룹은 CustomIcons 전용으로 유지한다. buff 그룹만 CDM 원본 재배치를 허용한다.
    if spellName and gs.spellAssignments and gs.spellAssignments[spellName] then
        local assigned = ResolveCDMGroup(gs, gs.spellAssignments[spellName], spellName)
        if assigned and gs.groups[assigned] and gs.groups[assigned].enabled then
            return assigned, spellName
        end
    end

    local unassignedBuffs = IsBuffSpellKey(spellName) and GetUnassignedBuffSpells(gs, false)
    if unassignedBuffs and unassignedBuffs[spellName] then
        return nil, spellName
    end

    -- 2순위: 뷰어 소스 기반 자동 분류 (기본 그룹)
    local viewerName = CDMHookEngine:GetIconSource(cooldownID)
    if gs.autoClassify then
        local defaultGroup = CDMHookEngine:GetDefaultGroupForViewer(viewerName)
        if defaultGroup and gs.groups[defaultGroup] and gs.groups[defaultGroup].enabled then
            local result = ResolveCDMGroup(gs, defaultGroup, spellName)
            if result then return result, spellName end
        end
    end

    -- 3순위: autoFilter 매칭
    if viewerName then
        local filterGroup = routes.viewer[viewerName]
        local result = ResolveCDMGroup(gs, filterGroup, spellName)
        if result then return result, spellName end
    end

    -- 4순위: autoFilter = "ALL" 그룹
    local allGroup = routes.all
    local allResult = ResolveCDMGroup(gs, allGroup, spellName)
    if allResult then return allResult, spellName end

    -- 5순위: 첫 번째 활성 그룹
    return ResolveCDMGroup(gs, routes.first, spellName), spellName
end

function GroupManager:ClassifyIcon(cooldownID)
    local CDMHookEngine = DDingUI.CDMHookEngine
    if not CDMHookEngine then return nil end

    local gs = GetGroupSystemSettings()
    if not gs then return nil end

    local groupName = ClassifyIconWithContext(
        cooldownID,
        CDMHookEngine,
        gs,
        classificationRoutes or BuildClassificationRoutes(gs)
    )
    return groupName
end

-- 뷰어 이름 → autoFilter 매칭
function GroupManager:FindGroupByViewerFilter(viewerName)
    local filterMap = {
        ["EssentialCooldownViewer"] = "COOLDOWN",
        ["UtilityCooldownViewer"] = "UTILITY",
        ["BuffIconCooldownViewer"] = "HELPFUL",
    }
    local filterType = filterMap[viewerName]
    if filterType then
        return self:FindGroupByFilter(filterType)
    end
    return nil
end

-- autoFilter로 그룹 찾기 (변경 없음)
function GroupManager:FindGroupByFilter(filterType)
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups then return nil end

    local best = nil
    local bestOrder = 9999

    for name, settings in pairs(gs.groups) do
        if settings.enabled and settings.autoFilter == filterType then
            local order = settings.order or 999
            if order < bestOrder then
                best = name
                bestOrder = order
            end
        end
    end

    return best
end

-- 첫 번째 활성 그룹 (변경 없음)
function GroupManager:GetFirstEnabledGroup()
    local gs = GetGroupSystemSettings()
    if not gs or not gs.groups then return nil end

    local best = nil
    local bestOrder = 9999

    for name, settings in pairs(gs.groups) do
        if settings.enabled then
            local order = settings.order or 999
            if order < bestOrder then
                best = name
                bestOrder = order
            end
        end
    end

    return best
end

-- ============================================================
-- CDMHookEngine 맵 기반 전체 분류
-- [REFACTOR] allData(auraData 배열) → idIconMap(cooldownID→icon) 순회
-- ============================================================

function GroupManager:ClassifyAll()
    local CDMHookEngine = DDingUI.CDMHookEngine
    if not CDMHookEngine then return classifiedGroups end

    local idIconMap = CDMHookEngine:GetIconMap()
    self:PruneInvalidAssignments()
    wipe(classificationByID)
    for _, iconList in pairs(classifiedGroups) do
        wipe(iconList)
    end
    wipe(classifiedGroups)

    -- 빈 그룹 초기화
    local gs = GetGroupSystemSettings()
    if not gs then return classifiedGroups end
    classificationRoutes = BuildClassificationRoutes(gs)
    if gs and gs.groups then
        for name, settings in pairs(gs.groups) do
            if settings.enabled then
                classifiedGroups[name] = {}
            end
        end
    end

    -- 각 cooldownID를 그룹에 배치
    for cooldownID, icon in pairs(idIconMap) do
        local groupName, spellName = ClassifyIconWithContext(cooldownID, CDMHookEngine, gs, classificationRoutes)
        local iconList = groupName and classifiedGroups[groupName]
        if iconList then
            local entry = {
                cooldownID = cooldownID,
                icon = icon,
                spellName = spellName,
            }
            iconList[#iconList + 1] = entry
            classificationByID[cooldownID] = {
                groupName = groupName,
                entry = entry,
            }
        end
    end

    for groupName, iconList in pairs(classifiedGroups) do
        SortIconListForGroup(groupName, iconList, gs and gs.groups and gs.groups[groupName])
    end

    return classifiedGroups
end

local function RemoveClassifiedEntry(iconList, target)
    if not iconList or not target then return end
    for index = #iconList, 1, -1 do
        if iconList[index] == target then
            table.remove(iconList, index)
            return
        end
    end
end

function GroupManager:ClassifyChanged(changedIDs)
    if type(changedIDs) ~= "table" then
        local classified = self:ClassifyAll()
        local touchedGroups = {}
        for groupName in pairs(classified) do
            touchedGroups[groupName] = true
        end
        return classified, touchedGroups
    end

    local CDMHookEngine = DDingUI.CDMHookEngine
    local gs = GetGroupSystemSettings()
    if not CDMHookEngine or not gs or not gs.groups then
        return classifiedGroups, {}
    end

    local idIconMap = CDMHookEngine:GetIconMap()
    local touchedGroups = {}
    classificationRoutes = BuildClassificationRoutes(gs)

    for cooldownID in pairs(changedIDs) do
        local previous = classificationByID[cooldownID]
        if previous then
            RemoveClassifiedEntry(classifiedGroups[previous.groupName], previous.entry)
            touchedGroups[previous.groupName] = true
            classificationByID[cooldownID] = nil
        end

        local icon = idIconMap[cooldownID]
        if icon then
            local groupName, spellName = ClassifyIconWithContext(cooldownID, CDMHookEngine, gs, classificationRoutes)
            if groupName and gs.groups[groupName] and gs.groups[groupName].enabled then
                local iconList = classifiedGroups[groupName]
                if not iconList then
                    iconList = {}
                    classifiedGroups[groupName] = iconList
                end
                local entry = {
                    cooldownID = cooldownID,
                    icon = icon,
                    spellName = spellName,
                }
                iconList[#iconList + 1] = entry
                classificationByID[cooldownID] = {
                    groupName = groupName,
                    entry = entry,
                }
                touchedGroups[groupName] = true
            end
        end
    end

    for groupName in pairs(touchedGroups) do
        SortIconListForGroup(groupName, classifiedGroups[groupName], gs.groups[groupName])
    end

    return classifiedGroups, touchedGroups
end

function GroupManager:InvalidateClassificationCache()
    classificationRoutes = nil
    copiedBuffConversionSignature = nil
    cdmBuffMatchContext = nil
    cdmBuffMatchContextAt = 0
    wipe(classificationByID)
    for _, iconList in pairs(classifiedGroups) do
        wipe(iconList)
    end
    wipe(classifiedGroups)
end
