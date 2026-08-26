local ns = select(2, ...)
local DDingUI = ns.Addon

local ProfileRecovery = {}
DDingUI.CustomIconProfileRecovery = ProfileRecovery

local function HasTableEntries(tbl)
    return type(tbl) == "table" and next(tbl) ~= nil
end

local function HasDynamicPayload(db)
    return type(db) == "table"
        and (HasTableEntries(db.groups) or HasTableEntries(db.iconData) or HasTableEntries(db.ungrouped))
end

local function CountTableEntries(tbl)
    if type(tbl) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function CountDynamicPayload(db)
    if type(db) ~= "table" then return 0 end
    return CountTableEntries(db.groups) + CountTableEntries(db.iconData) + CountTableEntries(db.ungrouped)
end

local function FindLegacyDynamicSpec(db)
    if type(db) ~= "table" or type(db.specs) ~= "table" then
        return nil, nil
    end

    local currentSpecID
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            currentSpecID = GetSpecializationInfo(specIndex)
        end
    end

    local source = currentSpecID and db.specs[currentSpecID]
    if HasDynamicPayload(source) then
        return source, currentSpecID
    end

    source = db.specs[0]
    if HasDynamicPayload(source) then
        return source, 0
    end

    for specID, specDB in pairs(db.specs) do
        if HasDynamicPayload(specDB) then
            return specDB, specID
        end
    end

    return nil, nil
end

local function CopyStoredValue(value)
    if type(value) ~= "table" then return value end
    if CopyTable then return CopyTable(value) end
    local copy = {}
    for k, v in pairs(value) do
        copy[CopyStoredValue(k)] = CopyStoredValue(v)
    end
    return copy
end

local function MergeMissingEntries(target, source)
    target = type(target) == "table" and target or {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            if target[key] == nil then
                target[key] = CopyStoredValue(value)
            end
        end
    end
    return target
end

local function ScoreDynamicPayload(db)
    if type(db) ~= "table" then return 0 end
    return (CountTableEntries(db.iconData) * 10)
        + CountTableEntries(db.groups)
        + CountTableEntries(db.ungrouped)
end

local function FindFallbackDynamicProfile(currentDB, includeDeepSnapshots)
    local profiles = DDingUI.db and DDingUI.db.profiles
    if type(profiles) ~= "table" then return nil, nil, nil, 0 end

    local bestSource, bestProfileName, bestSourceKey
    local bestScore = 0

    local function considerSource(source, profileName, sourceKey)
        local score = ScoreDynamicPayload(source)
        if source and score > bestScore then
            bestSource = source
            bestProfileName = profileName
            bestSourceKey = sourceKey
            bestScore = score
        end
    end

    local function considerDynamicDB(dynDB, profileName, label)
        if type(dynDB) ~= "table" or dynDB == currentDB then return end

        if HasDynamicPayload(dynDB) then
            considerSource(dynDB, profileName, label or "root")
        end

        local legacySource, legacySourceKey = FindLegacyDynamicSpec(dynDB)
        if legacySource then
            considerSource(legacySource, profileName, (label or "root") .. ".specs." .. tostring(legacySourceKey or "?"))
        end
    end

    for profileName, profileDB in pairs(profiles) do
        if type(profileDB) == "table" then
            considerDynamicDB(profileDB.dynamicIcons, profileName, "dynamicIcons")

            local specProfiles = profileDB.specProfiles
            if type(specProfiles) == "table" then
                considerDynamicDB(specProfiles.dynamicIcons, profileName, "specProfiles.dynamicIcons")
            end

            if includeDeepSnapshots then
                local specData = profileDB.specData
                if type(specData) == "table" then
                    for specID, specDB in pairs(specData) do
                        if type(specDB) == "table" then
                            considerDynamicDB(specDB.dynamicIcons, profileName, "specData." .. tostring(specID) .. ".dynamicIcons")
                            local nestedProfiles = specDB.specProfiles
                            if type(nestedProfiles) == "table" then
                                considerDynamicDB(nestedProfiles.dynamicIcons, profileName, "specData." .. tostring(specID) .. ".specProfiles.dynamicIcons")
                            end
                        end
                    end
                end
            end
        end
    end

    return bestSource, bestProfileName, bestSourceKey, bestScore
end

local function BuildUniqueDBKey(prefix, targetTable)
    local base = tostring(math.floor((GetTime and GetTime() or 0) * 1000))
    local key = prefix .. base
    local n = 1
    while targetTable and targetTable[key] do
        n = n + 1
        key = prefix .. base .. "_" .. n
    end
    return key
end

ProfileRecovery.HasTableEntries = HasTableEntries
ProfileRecovery.HasDynamicPayload = HasDynamicPayload
ProfileRecovery.CountTableEntries = CountTableEntries
ProfileRecovery.CountDynamicPayload = CountDynamicPayload
ProfileRecovery.FindLegacyDynamicSpec = FindLegacyDynamicSpec
ProfileRecovery.CopyStoredValue = CopyStoredValue
ProfileRecovery.MergeMissingEntries = MergeMissingEntries
ProfileRecovery.ScoreDynamicPayload = ScoreDynamicPayload
ProfileRecovery.FindFallbackDynamicProfile = FindFallbackDynamicProfile
ProfileRecovery.BuildUniqueDBKey = BuildUniqueDBKey
