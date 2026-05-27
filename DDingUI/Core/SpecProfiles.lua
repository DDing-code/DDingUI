local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

DDingUI.SpecProfiles = DDingUI.SpecProfiles or {}
local SP = DDingUI.SpecProfiles

-- Per-specialization full-profile snapshots.
-- v7 is intentionally non-destructive: it only repairs stale CDM source links.
local SPEC_DATA_VERSION = 7

local EXCLUDE_KEYS = {
    specData = true,
    specDataVersion = true,
    profileVersion = true,
    pendingMoverMigration = true,
}

local PRESERVE_MISSING_TOP_LEVEL_KEYS = {
    dynamicIcons = true,
}

local CORE_CDM_GROUPS = {
    Cooldowns = true,
    Buffs = true,
    Utility = true,
}

local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    return GetSpecializationInfo(specIndex)
end

local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and DeepCopy(v) or v
    end
    return copy
end

local function FullSnapshot(settings, defaults, isTopLevel)
    local snapshot = {}

    if settings then
        for k, v in pairs(settings) do
            if not (isTopLevel and EXCLUDE_KEYS[k]) then
                if type(v) == "table" then
                    local subDef = defaults and type(defaults[k]) == "table" and defaults[k] or nil
                    snapshot[k] = FullSnapshot(v, subDef, false)
                else
                    snapshot[k] = v
                end
            end
        end
    end

    if defaults then
        for k, v in pairs(defaults) do
            if not (isTopLevel and EXCLUDE_KEYS[k]) and snapshot[k] == nil then
                snapshot[k] = type(v) == "table" and DeepCopy(v) or v
            end
        end
    end

    return snapshot
end

local function MergeSnapshot(dest, source)
    if type(dest) ~= "table" or type(source) ~= "table" then return end
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(dest[k]) == "table" then
                MergeSnapshot(dest[k], v)
            else
                dest[k] = DeepCopy(v)
            end
        else
            dest[k] = v
        end
    end
end

local function ApplySnapshot(dest, source, isTopLevel)
    if type(dest) ~= "table" or type(source) ~= "table" then return end

    local toRemove
    for k in pairs(dest) do
        if not (isTopLevel and (EXCLUDE_KEYS[k] or PRESERVE_MISSING_TOP_LEVEL_KEYS[k])) and source[k] == nil then
            if not toRemove then toRemove = {} end
            toRemove[#toRemove + 1] = k
        end
    end
    if toRemove then
        for _, k in ipairs(toRemove) do
            dest[k] = nil
        end
    end

    for k, v in pairs(source) do
        if type(v) == "table" then
            if isTopLevel and PRESERVE_MISSING_TOP_LEVEL_KEYS[k] then
                -- Keep legacy snapshots that do not have this key from wiping user data,
                -- but when a spec snapshot does have it, treat it as the spec's complete state.
                dest[k] = DeepCopy(v)
            elseif type(dest[k]) == "table" then
                ApplySnapshot(dest[k], v, false)
            else
                dest[k] = DeepCopy(v)
            end
        else
            dest[k] = v
        end
    end
end

local function RepairStaleHybridSources(profile)
    local gs = profile and profile.groupSystem
    local groups = gs and gs.groups
    if not groups then return end

    local dynGroups = profile.dynamicIcons and profile.dynamicIcons.groups
    for groupName in pairs(CORE_CDM_GROUPS) do
        local group = groups[groupName]
        if group then
            group.groupType = "cdm"
            if group.sourceGroupKey and (not dynGroups or not dynGroups[group.sourceGroupKey]) then
                group.sourceGroupKey = nil
            end
        end
    end
end

local function ResetIconGroupsForFreshSpec(profile)
    if not profile then return end

    profile.dynamicIcons = {
        enabled = true,
        groups = {},
        iconData = {},
        ungrouped = {},
        ungroupedPositions = {},
    }

    local gs = profile.groupSystem
    local groups = gs and gs.groups
    if not groups then return end

    local toRemove
    for groupName, group in pairs(groups) do
        if group and group.groupType == "dynamic" then
            if not toRemove then toRemove = {} end
            toRemove[#toRemove + 1] = groupName
        elseif group and group.sourceGroupKey then
            group.sourceGroupKey = nil
        end
    end
    if toRemove then
        for _, groupName in ipairs(toRemove) do
            groups[groupName] = nil
        end
    end
end

local function MigrateSpecData()
    if not DDingUI.db or not DDingUI.db.profile then return end

    if DDingUI.db.char then
        DDingUI.db.char.specData = nil
        DDingUI.db.char.specDataVersion = nil
        DDingUI.db.char.specDataProfileKey = nil
    end

    local profile = DDingUI.db.profile
    local ver = profile.specDataVersion or 0
    if ver >= SPEC_DATA_VERSION then return end

    if profile.specData then
        for _, snapshot in pairs(profile.specData) do
            RepairStaleHybridSources(snapshot)
        end
    end
    RepairStaleHybridSources(profile)

    profile.specDataVersion = SPEC_DATA_VERSION
end

SP.lastSpecID = nil
SP._saveTimer = nil

function SP:SaveCurrentSpec()
    local specID = self.lastSpecID or GetCurrentSpecID()
    if not specID or not DDingUI.db or not DDingUI.db.profile then return end

    DDingUI.db.profile.specData = DDingUI.db.profile.specData or {}
    local defaults = DDingUI.defaults and DDingUI.defaults.profile
    DDingUI.db.profile.specData[specID] = FullSnapshot(DDingUI.db.profile, defaults, true)
end

function SP:LoadSpec(specID)
    if not specID or not DDingUI.db or not DDingUI.db.profile then return false end
    local specData = DDingUI.db.profile.specData
    local snapshot = specData and specData[specID]
    if not snapshot then return false end

    local snapshotHasDynamicIcons = type(snapshot.dynamicIcons) == "table"
    local defaults = DDingUI.defaults and DDingUI.defaults.profile
    if defaults then
        snapshot = FullSnapshot(snapshot, defaults, true)
    end
    if not snapshotHasDynamicIcons then
        snapshot.dynamicIcons = nil
    end

    ApplySnapshot(DDingUI.db.profile, snapshot, true)
    RepairStaleHybridSources(DDingUI.db.profile)
    return true
end

function SP:OnSpecChanged(newSpecID)
    if not newSpecID or not DDingUI.db or not DDingUI.db.profile then return end

    if self._saveTimer then
        self._saveTimer:Cancel()
        self._saveTimer = nil
    end

    if self.lastSpecID and self.lastSpecID ~= newSpecID then
        self:SaveCurrentSpec()
    end

    local loaded = self:LoadSpec(newSpecID)
    self.lastSpecID = newSpecID

    if not loaded then
        local p = DDingUI.db.profile

        if p.powerBar then
            p.powerBar.markers = {}
            p.powerBar.markerBarColors = {}
            p.powerBar.markerColorChange = false
        end
        if p.secondaryPowerBar then
            p.secondaryPowerBar.markers = {}
            p.secondaryPowerBar.markerBarColors = {}
            p.secondaryPowerBar.markerColorChange = false
        end
        ResetIconGroupsForFreshSpec(p)

        RepairStaleHybridSources(p)
        self:SaveCurrentSpec()
    end

    C_Timer.After(0.1, function()
        if DDingUI.RefreshAll then
            DDingUI:RefreshAll()
        end
    end)
end

function SP:MarkDirty()
    if self._saveTimer then
        self._saveTimer:Cancel()
    end
    self._saveTimer = C_Timer.NewTimer(2, function()
        SP:SaveCurrentSpec()
        SP._saveTimer = nil
    end)
end

function SP:Initialize()
    if DDingUI.db and DDingUI.db.char and DDingUI.db.char.specProfilesEnabled == false then
        return
    end

    MigrateSpecData()
    self.lastSpecID = GetCurrentSpecID()

    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        self.eventFrame:RegisterEvent("PLAYER_LOGOUT")
        self.eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
                local newSpecID = GetCurrentSpecID()
                if newSpecID then
                    SP:OnSpecChanged(newSpecID)
                end
            elseif event == "PLAYER_ENTERING_WORLD" then
                local specID = GetCurrentSpecID()
                if specID then
                    SP.lastSpecID = specID
                    if DDingUI.db.profile.specData and DDingUI.db.profile.specData[specID] then
                        SP:LoadSpec(specID)
                        C_Timer.After(0.1, function()
                            if DDingUI.RefreshAll then DDingUI:RefreshAll() end
                        end)
                    else
                        SP:SaveCurrentSpec()
                    end
                end
            elseif event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
                if SP._saveTimer then
                    SP._saveTimer:Cancel()
                    SP._saveTimer = nil
                end
                SP:SaveCurrentSpec()
            end
        end)
    end

    if DDingUI.db and DDingUI.db.RegisterCallback then
        DDingUI.db.RegisterCallback(SP, "OnProfileChanged", "OnProfileSwitched")
        DDingUI.db.RegisterCallback(SP, "OnProfileCopied", "OnProfileSwitched")
        DDingUI.db.RegisterCallback(SP, "OnProfileReset", "OnProfileSwitched")
    end

    local specID = GetCurrentSpecID()
    if specID and DDingUI.db and DDingUI.db.profile then
        DDingUI.db.profile.specData = DDingUI.db.profile.specData or {}
        if not DDingUI.db.profile.specData[specID] then
            self:SaveCurrentSpec()
        end
    end
end

function SP:OnProfileSwitched()
    if self._saveTimer then
        self._saveTimer:Cancel()
        self._saveTimer = nil
    end

    MigrateSpecData()
    local specID = GetCurrentSpecID()
    if not specID then return end

    self.lastSpecID = specID
    if DDingUI.db.profile.specData and DDingUI.db.profile.specData[specID] then
        self:LoadSpec(specID)
        C_Timer.After(0.1, function()
            if DDingUI.RefreshAll then DDingUI:RefreshAll() end
        end)
    else
        self:SaveCurrentSpec()
    end
end

SP.MODULE_KEYS = {
    { key = "general",           name = "General",            profileKeys = {"general"} },
    { key = "cdmGroups",         name = "Default CDM Groups", profileKeys = {"viewers", "__cdmGroups"} },
    { key = "dynamicGroups",     name = "Dynamic Groups",     profileKeys = {"__dynamicGroups"} },
    { key = "shortcutIcons",     name = "Shortcut Icons",     profileKeys = {"customIcons"} },
    { key = "resourceBars",      name = "Resource Bars",      profileKeys = {"powerBar", "secondaryPowerBar"} },
    { key = "iconCustomization", name = "Icon Customization", profileKeys = {"iconCustomization"} },
    { key = "castBar",           name = "Cast Bar",           profileKeys = {"castBar"} },
    { key = "buffTrackerBar",    name = "Aura Tracker",       profileKeys = {"buffTrackerBar"} },
    { key = "buffBarViewer",     name = "Buff Viewer",        profileKeys = {"buffBarViewer"} },
}

function SP:GetAvailableSpecs()
    local result = {}
    local specData = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.specData
    if not specData then return result end
    for specID in pairs(specData) do
        result[specID] = specID
    end
    return result
end

function SP:GetSpecName(specID)
    if not specID then return "?" end

    local numSpecs = GetNumSpecializations()
    for i = 1, numSpecs do
        local id, name = GetSpecializationInfo(i)
        if id == specID then
            return name
        end
    end

    if GetSpecializationInfoByID then
        local _, sName, _, _, _, _, className = GetSpecializationInfoByID(specID)
        if sName then
            return (className and (className .. " - ") or "") .. sName
        end
    end
    return "Spec " .. tostring(specID)
end

function SP:GetAllSavedSpecs()
    local result = {}
    local specData = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.specData
    if not specData then return result end

    local currentSpecID = self.lastSpecID
    for specID in pairs(specData) do
        if specID ~= currentSpecID then
            result[specID] = self:GetSpecName(specID)
        end
    end
    return result
end

local function EnsureProfileTable(profile, key)
    profile[key] = profile[key] or {}
    return profile[key]
end

local function EnsureDynamicDB(profile)
    local db = EnsureProfileTable(profile, "dynamicIcons")
    db.enabled = db.enabled ~= false
    db.groups = db.groups or {}
    db.iconData = db.iconData or {}
    db.ungrouped = db.ungrouped or {}
    db.ungroupedPositions = db.ungroupedPositions or {}
    return db
end

local function EnsureGroupSystemDB(profile)
    local gs = EnsureProfileTable(profile, "groupSystem")
    gs.groups = gs.groups or {}
    gs.spellAssignments = gs.spellAssignments or {}
    gs.deletedGroups = gs.deletedGroups or {}
    return gs
end

local function GetModuleDefaults(moduleKey)
    local defaults = DDingUI.defaults and DDingUI.defaults.profile
    if defaults and defaults[moduleKey] ~= nil then
        return defaults[moduleKey]
    end

    defaults = DDingUI.db and DDingUI.db.defaults and DDingUI.db.defaults.profile
    return defaults and defaults[moduleKey]
end

local function RemoveDynamicSourceGroup(profile, sourceKey)
    if not sourceKey then return end
    local dynDB = profile and profile.dynamicIcons
    if not dynDB or not dynDB.groups then return end

    local group = dynDB.groups[sourceKey]
    if group and group.icons then
        for _, iconKey in ipairs(group.icons) do
            if dynDB.iconData then dynDB.iconData[iconKey] = nil end
            if dynDB.ungrouped then dynDB.ungrouped[iconKey] = nil end
            if dynDB.ungroupedPositions then dynDB.ungroupedPositions[iconKey] = nil end
        end
    end

    dynDB.groups[sourceKey] = nil
end

local function CopyDynamicSourceGroup(sourceProfile, destProfile, sourceKey)
    local sourceDyn = sourceProfile and sourceProfile.dynamicIcons
    local sourceGroup = sourceDyn and sourceDyn.groups and sourceDyn.groups[sourceKey]
    if not sourceGroup then return false end

    local destDyn = EnsureDynamicDB(destProfile)
    destDyn.groups[sourceKey] = DeepCopy(sourceGroup)

    if sourceDyn.iconData and sourceGroup.icons then
        for _, iconKey in ipairs(sourceGroup.icons) do
            if sourceDyn.iconData[iconKey] then
                destDyn.iconData[iconKey] = DeepCopy(sourceDyn.iconData[iconKey])
            end
            if sourceDyn.ungrouped and sourceDyn.ungrouped[iconKey] ~= nil then
                destDyn.ungrouped[iconKey] = DeepCopy(sourceDyn.ungrouped[iconKey])
            end
            if sourceDyn.ungroupedPositions and sourceDyn.ungroupedPositions[iconKey] then
                destDyn.ungroupedPositions[iconKey] = DeepCopy(sourceDyn.ungroupedPositions[iconKey])
            end
        end
    end

    return true
end

local function IsCDMSourceGroup(profile, sourceKey)
    if not sourceKey then return false end

    local gs = profile and profile.groupSystem
    local groups = gs and gs.groups
    if groups then
        for groupName in pairs(CORE_CDM_GROUPS) do
            local group = groups[groupName]
            if group and group.sourceGroupKey == sourceKey then
                return true
            end
        end
    end

    local dynGroup = profile and profile.dynamicIcons and profile.dynamicIcons.groups
        and profile.dynamicIcons.groups[sourceKey]
    return dynGroup and CORE_CDM_GROUPS[dynGroup.linkedCDMGroup] == true
end

local function CopyCDMGroupsFromSource(sourceProfile)
    local destProfile = DDingUI.db and DDingUI.db.profile
    local sourceGS = sourceProfile and sourceProfile.groupSystem
    local sourceGroups = sourceGS and sourceGS.groups
    if not destProfile or not sourceGS or not sourceGroups then return false end

    local destGS = EnsureGroupSystemDB(destProfile)
    local oldSourceKeys = {}
    for groupName in pairs(CORE_CDM_GROUPS) do
        local group = destGS.groups[groupName]
        if group and group.sourceGroupKey then
            oldSourceKeys[group.sourceGroupKey] = true
        end
    end
    for sourceKey in pairs(oldSourceKeys) do
        RemoveDynamicSourceGroup(destProfile, sourceKey)
    end

    for k, v in pairs(sourceGS) do
        if k ~= "groups" and k ~= "spellAssignments" and k ~= "deletedGroups" then
            destGS[k] = type(v) == "table" and DeepCopy(v) or v
        end
    end

    local newSourceKeys = {}
    for groupName in pairs(CORE_CDM_GROUPS) do
        local sourceGroup = sourceGroups[groupName]
        if sourceGroup then
            destGS.groups[groupName] = DeepCopy(sourceGroup)
            destGS.groups[groupName].groupType = "cdm"
            if destGS.deletedGroups then
                destGS.deletedGroups[groupName] = nil
            end
            if sourceGroup.sourceGroupKey then
                newSourceKeys[sourceGroup.sourceGroupKey] = true
            end
        end
    end

    local assignmentsToRemove
    for spellName, assignedGroup in pairs(destGS.spellAssignments or {}) do
        if CORE_CDM_GROUPS[assignedGroup] then
            if not assignmentsToRemove then assignmentsToRemove = {} end
            assignmentsToRemove[#assignmentsToRemove + 1] = spellName
        end
    end
    if assignmentsToRemove then
        for _, spellName in ipairs(assignmentsToRemove) do
            destGS.spellAssignments[spellName] = nil
        end
    end
    for spellName, assignedGroup in pairs(sourceGS.spellAssignments or {}) do
        if CORE_CDM_GROUPS[assignedGroup] then
            destGS.spellAssignments[spellName] = assignedGroup
        end
    end

    local sourceDyn = sourceProfile.dynamicIcons
    for sourceKey, dynGroup in pairs((sourceDyn and sourceDyn.groups) or {}) do
        local linkedGroup = dynGroup.linkedCDMGroup
        if CORE_CDM_GROUPS[linkedGroup] then
            newSourceKeys[sourceKey] = true
            if destGS.groups[linkedGroup] then
                destGS.groups[linkedGroup].sourceGroupKey = sourceKey
            end
        end
    end
    for sourceKey in pairs(newSourceKeys) do
        CopyDynamicSourceGroup(sourceProfile, destProfile, sourceKey)
    end

    return true
end

local function CopyDynamicGroupsFromSource(sourceProfile)
    local destProfile = DDingUI.db and DDingUI.db.profile
    if not destProfile or not sourceProfile then return false end

    local destGS = EnsureGroupSystemDB(destProfile)
    local destDyn = EnsureDynamicDB(destProfile)

    local removeSourceKeys = {}
    for groupName, group in pairs(destGS.groups) do
        if group and group.groupType == "dynamic" then
            if group.sourceGroupKey then
                removeSourceKeys[group.sourceGroupKey] = true
            end
            destGS.groups[groupName] = nil
        end
    end
    for sourceKey, dynGroup in pairs(destDyn.groups) do
        if not IsCDMSourceGroup(destProfile, sourceKey) then
            removeSourceKeys[sourceKey] = true
        elseif dynGroup and dynGroup.linkedCDMGroup and not CORE_CDM_GROUPS[dynGroup.linkedCDMGroup] then
            removeSourceKeys[sourceKey] = true
        end
    end
    for sourceKey in pairs(removeSourceKeys) do
        RemoveDynamicSourceGroup(destProfile, sourceKey)
    end

    local sourceDyn = sourceProfile.dynamicIcons
    if sourceDyn and sourceDyn.enabled ~= nil then
        destDyn.enabled = sourceDyn.enabled ~= false
    end

    local copiedSourceKeys = {}
    for sourceKey in pairs((sourceDyn and sourceDyn.groups) or {}) do
        if not IsCDMSourceGroup(sourceProfile, sourceKey) then
            if CopyDynamicSourceGroup(sourceProfile, destProfile, sourceKey) then
                copiedSourceKeys[sourceKey] = true
            end
        end
    end

    local sourceGS = sourceProfile.groupSystem
    for groupName, group in pairs((sourceGS and sourceGS.groups) or {}) do
        local hasSource = group and (not group.sourceGroupKey or copiedSourceKeys[group.sourceGroupKey])
        if group and group.groupType == "dynamic" and hasSource and not IsCDMSourceGroup(sourceProfile, group.sourceGroupKey) then
            destGS.groups[groupName] = DeepCopy(group)
            if group.sourceGroupKey then
                copiedSourceKeys[group.sourceGroupKey] = true
            end
            if destGS.deletedGroups then
                destGS.deletedGroups[groupName] = nil
            end
        end
    end

    for sourceKey in pairs(copiedSourceKeys) do
        if destGS.deletedGroups then
            destGS.deletedGroups["dyn_" .. tostring(sourceKey)] = nil
        end
    end

    return sourceDyn ~= nil or sourceGS ~= nil
end

local function CopyWholeModuleFromSource(sourceProfile, moduleKey, useDefaults)
    if moduleKey == "__cdmGroups" then
        return CopyCDMGroupsFromSource(sourceProfile)
    elseif moduleKey == "__dynamicGroups" then
        return CopyDynamicGroupsFromSource(sourceProfile)
    end

    if not sourceProfile or not sourceProfile[moduleKey] then return false end

    local copied
    if useDefaults then
        copied = FullSnapshot(sourceProfile[moduleKey], GetModuleDefaults(moduleKey), false)
    else
        copied = DeepCopy(sourceProfile[moduleKey])
    end

    local destProfile = DDingUI.db and DDingUI.db.profile
    if not destProfile then return false end

    if type(destProfile[moduleKey]) == "table" and type(copied) == "table" then
        ApplySnapshot(destProfile[moduleKey], copied, false)
    else
        destProfile[moduleKey] = copied
    end
    return true
end

function SP:CopyModulesFromCharSpec(charKey, specID, moduleKeys)
    return self:CopyModulesFromSpec(specID, moduleKeys)
end

function SP:CopyModulesFromSpec(sourceSpecID, moduleKeys)
    if not sourceSpecID or not moduleKeys or #moduleKeys == 0 then return false end
    local specData = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.specData
    if not specData then return false end

    local snapshot = specData[sourceSpecID]
    if not snapshot then return false end

    local copiedAny = false
    for _, moduleKey in ipairs(moduleKeys) do
        copiedAny = CopyWholeModuleFromSource(snapshot, moduleKey, false) or copiedAny
    end

    self:SaveCurrentSpec()
    return copiedAny
end

function SP:CopyModulesFromProfile(sourceProfileKey, moduleKeys)
    if not sourceProfileKey or not moduleKeys or #moduleKeys == 0 then return false end
    if not DDingUI.db or not DDingUI.db.profiles then return false end

    local sourceProfile = DDingUI.db.profiles[sourceProfileKey]
    if not sourceProfile then return false end

    local copiedAny = false
    for _, moduleKey in ipairs(moduleKeys) do
        copiedAny = CopyWholeModuleFromSource(sourceProfile, moduleKey, true) or copiedAny
    end

    self:SaveCurrentSpec()
    return copiedAny
end

function SP:AddSpecProfileOptions() end
function SP:IsEnabled() return true end
function SP:IsAnyModuleEnabled() return true end

function SP:GetCurrentSpecInfo()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID, specName, _, specIcon = GetSpecializationInfo(specIndex)
    return specIndex, specID, specName, specIcon
end

function SP:GetAllSpecInfo()
    local specs = {}
    local numSpecs = GetNumSpecializations()
    for i = 1, numSpecs do
        local specID, specName, _, specIcon = GetSpecializationInfo(i)
        if specID then
            specs[i] = { index = i, id = specID, name = specName, icon = specIcon }
        end
    end
    return specs, numSpecs
end
