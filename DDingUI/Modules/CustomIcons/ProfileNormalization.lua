local ns = select(2, ...)
local DDingUI = ns.Addon

local ProfileNormalization = {}
DDingUI.CustomIconProfileNormalization = ProfileNormalization

function ProfileNormalization.Create(
    EnsureIconSettings,
    GetCustomAuraPresetIconTexture,
    runtime,
    CUSTOM_TIMED_AURA_CONFIGS,
    AURA_EQUIVALENT_IDS
)
    local NormalizePresetIconData
    local NormalizePresetIconDB
    local normalizedDBs = setmetatable({}, { __mode = "k" })

    local function CompactGroupIconList(icons, iconDataDB)
        if type(icons) ~= "table" then return false end

        local indexed = {}
        local changed = false
        for index, iconKey in pairs(icons) do
            if type(index) == "number" and index >= 1 and index % 1 == 0 then
                indexed[#indexed + 1] = index
            else
                changed = true
            end
        end
        table.sort(indexed)

        local compacted = {}
        local seen = {}
        for _, index in ipairs(indexed) do
            local iconKey = icons[index]
            if type(iconKey) == "string" and iconDataDB[iconKey] and not seen[iconKey] then
                compacted[#compacted + 1] = iconKey
                seen[iconKey] = true
                if index ~= #compacted then
                    changed = true
                end
            else
                changed = true
            end
        end

        if not changed then return false end
        for key in pairs(icons) do
            icons[key] = nil
        end
        for index, iconKey in ipairs(compacted) do
            icons[index] = iconKey
        end
        return true
    end

    NormalizePresetIconData = function(iconData)
        if type(iconData) ~= "table" or not (iconData.type == "spell" or iconData.type == "aura") then return false end
        local preset = GetCustomAuraPresetIconTexture(iconData.id)
        if not preset then return false end

        iconData.settings = iconData.settings or {}
        if iconData.settings.iconTexture ~= preset or iconData.settings.auraIcon ~= preset then
            iconData.settings.iconTexture = preset
            iconData.settings.auraIcon = preset
            return true
        end
        return false
    end

    NormalizePresetIconDB = function(db, ownerProfile, updateRuntime, force)
        local iconDataDB = db and db.iconData
        if type(iconDataDB) ~= "table" then return false end
        if not force and normalizedDBs[db] then return false end

        local changed = false
        for _, iconData in pairs(iconDataDB) do
            EnsureIconSettings(iconData)
            if NormalizePresetIconData(iconData) then
                changed = true
            end
        end

        db.groups = type(db.groups) == "table" and db.groups or {}
        db.ungrouped = type(db.ungrouped) == "table" and db.ungrouped or {}
        db.ungroupedPositions = type(db.ungroupedPositions) == "table" and db.ungroupedPositions or {}

        local activeProfile = DDingUI.db and DDingUI.db.profile
        local profile = ownerProfile or activeProfile
        local iconIdentity = DDingUI.CustomIconIdentity
        if iconIdentity and iconIdentity.NormalizeProfile
            and iconIdentity:NormalizeProfile(profile)
        then
            changed = true
        end
        local touchRuntime = updateRuntime
        if touchRuntime == nil then
            touchRuntime = profile == activeProfile
        end
        local gsGroups = profile and profile.groupSystem and profile.groupSystem.groups
        local referencedSourceGroups = {}
        local cdmSourceGroups = {}
        local orderPreferred = {}

        if type(gsGroups) == "table" then
            for groupName, groupSettings in pairs(gsGroups) do
                local sourceKey = type(groupSettings) == "table" and groupSettings.sourceGroupKey
                if sourceKey then
                    referencedSourceGroups[sourceKey] = true
                    if type(groupName) == "string" then
                        cdmSourceGroups[groupName] = sourceKey
                    end
                end
                local iconOrder = type(groupSettings) == "table" and groupSettings.iconOrder
                if type(iconOrder) == "table" then
                    for _, token in ipairs(iconOrder) do
                        if type(token) == "string" then
                            local iconKey = iconIdentity and iconIdentity.ResolveOrderToken
                                and iconIdentity:ResolveOrderToken(db, token)
                                or token:match("^dyn:(.+)$")
                            if iconKey then
                                orderPreferred[iconKey] = true
                            end
                        end
                    end
                end
            end
        end

        for groupKey, group in pairs(db.groups) do
            local icons = type(group) == "table" and group.icons
            if CompactGroupIconList(icons, iconDataDB) then
                changed = true
            end
        end

        local function AddIconToGroup(group, iconKey)
            if type(group) ~= "table" or not iconKey then return false end
            group.icons = type(group.icons) == "table" and group.icons or {}
            for _, existingKey in ipairs(group.icons) do
                if existingKey == iconKey then return false end
            end
            group.icons[#group.icons + 1] = iconKey
            return true
        end

        local function AddOrderToken(groupSettings, iconKey)
            if type(groupSettings) ~= "table" or not iconKey then return false end
            groupSettings.iconOrder = type(groupSettings.iconOrder) == "table" and groupSettings.iconOrder or {}
            local token = iconIdentity and iconIdentity.BuildOrderToken
                and iconIdentity:BuildOrderToken(db, iconKey)
                or ("dyn:" .. tostring(iconKey))
            for _, existingToken in ipairs(groupSettings.iconOrder) do
                if existingToken == token then return false end
            end
            groupSettings.iconOrder[#groupSettings.iconOrder + 1] = token
            return true
        end

        for sourceKey, group in pairs(db.groups) do
            local linkedGroupName = type(group) == "table" and group.linkedCDMGroup
            local preferredSourceKey = linkedGroupName and cdmSourceGroups[linkedGroupName]
            if preferredSourceKey and preferredSourceKey ~= sourceKey and db.groups[preferredSourceKey] then
                local preferredGroup = db.groups[preferredSourceKey]
                local icons = type(group.icons) == "table" and group.icons
                if type(icons) == "table" then
                    for _, iconKey in ipairs(icons) do
                        if iconDataDB[iconKey] and AddIconToGroup(preferredGroup, iconKey) then
                            changed = true
                            local groupSettings = gsGroups and gsGroups[linkedGroupName]
                            if AddOrderToken(groupSettings, iconKey) then
                                changed = true
                            end
                        end
                    end
                end
                db.groups[sourceKey] = nil
                changed = true
            end
        end

        local memberships = {}
        for groupKey, group in pairs(db.groups) do
            local icons = type(group) == "table" and group.icons
            if type(icons) == "table" then
                for _, iconKey in ipairs(icons) do
                    memberships[iconKey] = memberships[iconKey] or {}
                    memberships[iconKey][groupKey] = true
                end
            end
        end

        local function GetLinkedGroupName(iconKey, iconData)
            local settings = type(iconData) == "table" and iconData.settings
            if type(settings) == "table" and type(settings.targetCDMGroup) == "string" then
                return settings.targetCDMGroup
            end
            for groupKey in pairs(memberships[iconKey] or {}) do
                local group = db.groups[groupKey]
                if type(group) == "table" and type(group.linkedCDMGroup) == "string" then
                    return group.linkedCDMGroup
                end
            end
            return nil
        end

        local function GetAuraIdentity(iconKey, iconData)
            if type(iconData) ~= "table" or iconData.type ~= "aura" then return nil end
            local spellID = tonumber(iconData.id)
            if not spellID then return nil end
            if AURA_EQUIVALENT_IDS[spellID] then
                spellID = 2825
            end
            local settings = type(iconData.settings) == "table" and iconData.settings or nil
            if not CUSTOM_TIMED_AURA_CONFIGS[spellID]
                and not (settings and settings.customAuraDuration)
                and not GetLinkedGroupName(iconKey, iconData)
            then
                return nil
            end
            return (GetLinkedGroupName(iconKey, iconData) or "aura") .. ":" .. tostring(spellID)
        end

        local function GetIconScore(iconKey, iconData)
            local score = 0
            local linkedGroupName = GetLinkedGroupName(iconKey, iconData)
            local preferredSourceKey = linkedGroupName and cdmSourceGroups[linkedGroupName]
            if orderPreferred[iconKey] then
                score = score + 4000
            end
            for groupKey in pairs(memberships[iconKey] or {}) do
                if groupKey == preferredSourceKey then
                    score = score + 3000
                elseif referencedSourceGroups[groupKey] then
                    score = score + 1000
                else
                    score = score + 100
                end
            end
            if db.ungrouped[iconKey] then
                score = score - 10
            end
            return score
        end

        local bestByIdentity = {}
        local removeKeys = {}
        for iconKey, iconData in pairs(iconDataDB) do
            local identity = GetAuraIdentity(iconKey, iconData)
            if identity then
                local currentBest = bestByIdentity[identity]
                if not currentBest then
                    bestByIdentity[identity] = iconKey
                else
                    local score = GetIconScore(iconKey, iconData)
                    local bestScore = GetIconScore(currentBest, iconDataDB[currentBest])
                    if score > bestScore or (score == bestScore and tostring(iconKey) < tostring(currentBest)) then
                        removeKeys[currentBest] = true
                        bestByIdentity[identity] = iconKey
                    else
                        removeKeys[iconKey] = true
                    end
                end
            end
        end

        local function RemoveOrderToken(iconKey)
            if type(gsGroups) ~= "table" then return false end
            local legacyToken = "dyn:" .. tostring(iconKey)
            local stableToken = iconIdentity and iconIdentity.BuildOrderToken
                and iconIdentity:BuildOrderToken(db, iconKey)
            local removed = false
            for _, groupSettings in pairs(gsGroups) do
                local iconOrder = type(groupSettings) == "table" and groupSettings.iconOrder
                if type(iconOrder) == "table" then
                    for i = #iconOrder, 1, -1 do
                        if iconOrder[i] == legacyToken or (stableToken and iconOrder[i] == stableToken) then
                            table.remove(iconOrder, i)
                            removed = true
                        end
                    end
                end
            end
            return removed
        end

        for iconKey in pairs(removeKeys) do
            if RemoveOrderToken(iconKey) then
                changed = true
            end
            iconDataDB[iconKey] = nil
            db.ungrouped[iconKey] = nil
            db.ungroupedPositions[iconKey] = nil
            for _, group in pairs(db.groups) do
                local icons = type(group) == "table" and group.icons
                if type(icons) == "table" then
                    for i = #icons, 1, -1 do
                        if icons[i] == iconKey then
                            table.remove(icons, i)
                        end
                    end
                end
            end
            if touchRuntime then
                local frame = runtime.iconFrames and runtime.iconFrames[iconKey]
                if frame and frame.Hide then
                    frame:Hide()
                end
                if runtime.iconFrames then
                    runtime.iconFrames[iconKey] = nil
                end
            end
            changed = true
        end

        normalizedDBs[db] = true
        return changed
    end


    return NormalizePresetIconData, NormalizePresetIconDB
end
