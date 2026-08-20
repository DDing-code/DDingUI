local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

-- SavedVariables normalization for pre-AuraContainer BuffTracker display styles.
--
-- Old automatic trackers could store a shape inside settings.barStyle while
-- keeping displayType="bar". The 12.1 AuraContainer path deliberately accepts
-- only a real bar for displayType="bar", so those old records would otherwise
-- stay on the compatibility runtime forever.
--
-- This migration promotes the old shape to the modern displayType schema while
-- leaving manual/spell/non-aura trackers untouched. It is intentionally
-- idempotent and re-scans imported/profile-switched data even after the schema
-- version has been stamped.

local Migration = {}
DDingUI.TrackedAuraProfileMigration = Migration

local MIGRATION_VERSION = 1
Migration.VERSION = MIGRATION_VERSION

-- Old circular/square styles were icon-backed CooldownFrames, so the modern
-- icon display is the closest representation. Donut/ring were explicit ring
-- shapes and map to the native AuraContainer ring display.
local LEGACY_STYLE_TARGET = {
    ring = "ring",
    donut = "ring",
    circular = "icon",
    square = "icon",
}

local diagnostics = {
    runs = 0,
    trackersMigrated = 0,
    ringMigrations = 0,
    iconMigrations = 0,
    manualSkipped = 0,
    spellSkipped = 0,
    nonAuraSkipped = 0,
    storedSpecsMigrated = 0,
    lastReason = nil,
    lastChanged = 0,
}

local function CopyValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = CopyValue(child)
    end
    return copy
end

local function FirstDefined(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value ~= nil then return value end
    end
    return nil
end

local function SetIfNil(settings, key, value)
    if settings[key] ~= nil or value == nil then return false end
    settings[key] = CopyValue(value)
    return true
end

local function GetCurrentSpecID()
    if not GetSpecialization or not GetSpecializationInfo then return nil end
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return tonumber(specID)
end

local function LegacyBarPosition(settings, rootCfg, trackerIndex)
    rootCfg = rootCfg or {}
    trackerIndex = tonumber(trackerIndex) or 1

    local attachTo = settings.attachTo or rootCfg.attachTo or "DDingUI_Anchor_Cooldowns"
    local anchorPoint = settings.anchorPoint or rootCfg.anchorPoint or "BOTTOM"

    if settings.offsetX ~= nil and settings.offsetY ~= nil then
        return attachTo, anchorPoint, settings.offsetX, settings.offsetY
    end

    local stackIndex = math.max(0, trackerIndex - 1)
    local growthDirection = settings.growthDirection or rootCfg.growthDirection or "DOWN"
    local growthSpacing = settings.growthSpacing or rootCfg.growthSpacing or 20
    local baseX = rootCfg.offsetX or 0
    local baseY = rootCfg.offsetY or 18

    if growthDirection == "UP" then
        return attachTo, anchorPoint, baseX, baseY + (stackIndex * growthSpacing)
    elseif growthDirection == "LEFT" then
        return attachTo, anchorPoint, baseX - (stackIndex * growthSpacing), baseY
    elseif growthDirection == "RIGHT" then
        return attachTo, anchorPoint, baseX + (stackIndex * growthSpacing), baseY
    end
    return attachTo, anchorPoint, baseX, baseY - (stackIndex * growthSpacing)
end

local function IsAutomaticAuraTracker(tracker, oldStyle)
    if type(tracker) ~= "table" or tracker.isGroup then return false end
    if (tracker.displayType or "bar") ~= "bar" then return false end
    if not LEGACY_STYLE_TARGET[oldStyle] then return false end

    if tracker.trackingMode == "manual" then
        diagnostics.manualSkipped = diagnostics.manualSkipped + 1
        return false
    end
    if tracker.trackingMode == "spell"
        or (type(tracker.trigger) == "table" and tracker.trigger.type == "spell")
    then
        diagnostics.spellSkipped = diagnostics.spellSkipped + 1
        return false
    end
    if tracker.isAura == false then
        diagnostics.nonAuraSkipped = diagnostics.nonAuraSkipped + 1
        return false
    end
    return true
end

function Migration:NormalizeTracker(tracker, rootCfg, trackerIndex)
    if type(tracker) ~= "table" then return false end
    local settings = tracker.settings
    if type(settings) ~= "table" then return false end

    local oldStyle = settings.barStyle
    local targetType = LEGACY_STYLE_TARGET[oldStyle]
    if not targetType or not IsAutomaticAuraTracker(tracker, oldStyle) then
        return false
    end

    rootCfg = rootCfg or {}
    local attachTo, anchorPoint, offsetX, offsetY = LegacyBarPosition(settings, rootCfg, trackerIndex)
    local effectiveHeight = FirstDefined(settings.height, rootCfg.height, 4)
    local effectiveBorderSize = FirstDefined(settings.borderSize, rootCfg.borderSize, 1)
    local effectiveBorderColor = FirstDefined(settings.borderColor, rootCfg.borderColor, { 0, 0, 0, 1 })

    tracker.displayType = targetType
    -- Clear the legacy discriminator without deleting it outright; explicit
    -- "bar" is harmless for ring/icon and makes a future switch back to bar
    -- AuraContainer-compatible.
    settings.barStyle = "bar"

    if targetType == "ring" then
        SetIfNil(settings, "ringSize", effectiveHeight)
        SetIfNil(settings, "ringColor", FirstDefined(settings.barColor, rootCfg.barColor, { 1, 0.8, 0, 1 }))
        SetIfNil(settings, "ringBgColor", FirstDefined(settings.bgColor, rootCfg.bgColor, { 0.15, 0.15, 0.15, 1 }))
        SetIfNil(settings, "ringBorderColor", effectiveBorderColor)
        -- Legacy ring rendering used a fixed two-pixel outer expansion.
        SetIfNil(settings, "ringBorderSize", 2)
        SetIfNil(settings, "ringAnchorPoint", anchorPoint)
        SetIfNil(settings, "ringOffsetX", offsetX)
        SetIfNil(settings, "ringOffsetY", offsetY)
        SetIfNil(settings, "ringSelfPoint", FirstDefined(settings.selfPoint, rootCfg.selfPoint))
        diagnostics.ringMigrations = diagnostics.ringMigrations + 1
    else
        SetIfNil(settings, "iconSize", effectiveHeight)
        SetIfNil(settings, "iconAttachTo", attachTo)
        SetIfNil(settings, "iconAnchorPoint", anchorPoint)
        SetIfNil(settings, "iconOffsetX", offsetX)
        SetIfNil(settings, "iconOffsetY", offsetY)
        SetIfNil(settings, "iconBorderSize", effectiveBorderSize)
        SetIfNil(settings, "iconBorderColor", effectiveBorderColor)
        SetIfNil(settings, "showIconBorder", effectiveBorderSize > 0)
        if settings.iconShowStackText == nil and settings.showStacksText ~= nil then
            settings.iconShowStackText = settings.showStacksText == true
        end
        diagnostics.iconMigrations = diagnostics.iconMigrations + 1
    end

    diagnostics.trackersMigrated = diagnostics.trackersMigrated + 1
    return true
end

local function NormalizeTrackerList(list, rootCfg)
    if type(list) ~= "table" then return 0 end
    local changed = 0
    for key, tracker in pairs(list) do
        if type(tracker) == "table" then
            local trackerIndex = type(key) == "number" and key or 1
            if Migration:NormalizeTracker(tracker, rootCfg, trackerIndex) then
                changed = changed + 1
            end
        end
    end
    return changed
end

local function NormalizeBuffTrackerConfig(rootCfg, seen)
    if type(rootCfg) ~= "table" then return 0 end
    seen = seen or {}
    if seen[rootCfg] then return 0 end
    seen[rootCfg] = true

    local changed = NormalizeTrackerList(rootCfg.trackedBuffs, rootCfg)

    if type(rootCfg.trackedBuffsPerSpec) == "table" then
        for _, list in pairs(rootCfg.trackedBuffsPerSpec) do
            changed = changed + NormalizeTrackerList(list, rootCfg)
        end
    end

    -- Very old profiles could keep per-spec BuffTracker configs here. Walk them
    -- as configs rather than assuming a particular historical shape.
    if type(rootCfg.specs) == "table" then
        for _, specCfg in pairs(rootCfg.specs) do
            changed = changed + NormalizeBuffTrackerConfig(specCfg, seen)
        end
    end

    return changed
end

function Migration:NormalizeProfileSnapshot(profile)
    if type(profile) ~= "table" then return 0 end
    return NormalizeBuffTrackerConfig(profile.buffTrackerBar)
end

function Migration:NormalizeCurrentProfile()
    local db = DDingUI.db
    local profile = db and db.profile
    if type(profile) ~= "table" then return 0 end

    local changed = self:NormalizeProfileSnapshot(profile)
    -- specDataBase is a full profile snapshot and is safe to normalize directly.
    if type(profile.specDataBase) == "table" then
        changed = changed + self:NormalizeProfileSnapshot(profile.specDataBase)
    end
    return changed
end

function Migration:NormalizeGlobalStore()
    local db = DDingUI.db
    local global = db and db.global
    if type(global) ~= "table" then return 0 end

    local changed = 0
    local store = global.trackedBuffsPerSpec
    if type(store) == "table" then
        local currentSpecID = GetCurrentSpecID()
        local currentRootCfg = db.profile and db.profile.buffTrackerBar or nil
        for specKey, list in pairs(store) do
            -- Profile-level visual defaults may differ by specialization. Only
            -- borrow the currently loaded profile defaults for the matching
            -- global spec; other specs use legacy hard defaults until their full
            -- SpecProfiles snapshot is normalized.
            local rootCfg = currentSpecID and tonumber(specKey) == currentSpecID and currentRootCfg or nil
            changed = changed + NormalizeTrackerList(list, rootCfg)
        end
    end
    global.trackedAuraSchemaVersion = MIGRATION_VERSION
    return changed
end

function Migration:Run(reason)
    if not DDingUI.db then return 0 end
    diagnostics.runs = diagnostics.runs + 1
    diagnostics.lastReason = reason

    local changed = self:NormalizeGlobalStore() + self:NormalizeCurrentProfile()
    diagnostics.lastChanged = changed
    return changed
end

function Migration:GetDiagnostics()
    local result = { version = MIGRATION_VERSION }
    for key, value in pairs(diagnostics) do result[key] = value end
    return result
end

-- Stored spec snapshots are delta-encoded. Mutate them only through the public
-- SpecProfiles expander after its own asynchronous data migration has finished;
-- editing partial delta trackers directly could misclassify an inherited manual
-- tracker as automatic.
function Migration:QueueStoredSpecMigration()
    if self._storedSpecMigrationQueued then return end
    local SP = DDingUI.SpecProfiles
    if not SP or type(SP.MutateStoredSpecs) ~= "function" or not C_Timer or not C_Timer.After then
        return
    end

    self._storedSpecMigrationQueued = true
    local attempts = 0
    local function TryMigrate()
        attempts = attempts + 1
        if not DDingUI.db then
            Migration._storedSpecMigrationQueued = nil
            return
        end
        if SP._migrationProfile then
            if attempts < 100 then
                C_Timer.After(0.1, TryMigrate)
            else
                Migration._storedSpecMigrationQueued = nil
            end
            return
        end

        Migration._storedSpecMigrationQueued = nil
        SP:MutateStoredSpecs(function(snapshot)
            local changed = Migration:NormalizeProfileSnapshot(snapshot)
            if changed > 0 then
                diagnostics.storedSpecsMigrated = diagnostics.storedSpecsMigrated + changed
                return true
            end
            return false
        end)
    end
    C_Timer.After(0, TryMigrate)
end

local function InstallLifecycleHooks()
    local SP = DDingUI.SpecProfiles
    if SP and not SP._trackedAuraProfileMigrationWrapped then
        SP._trackedAuraProfileMigrationWrapped = true

        if type(SP.Initialize) == "function" then
            local originalInitialize = SP.Initialize
            SP.Initialize = function(self, ...)
                Migration:Run("spec-initialize")
                local result = originalInitialize(self, ...)
                Migration:QueueStoredSpecMigration()
                return result
            end
        end

        if type(SP.SaveCurrentSpec) == "function" then
            local originalSave = SP.SaveCurrentSpec
            SP.SaveCurrentSpec = function(self, ...)
                Migration:NormalizeGlobalStore()
                Migration:NormalizeCurrentProfile()
                return originalSave(self, ...)
            end
        end

        if type(SP.LoadSpec) == "function" then
            local originalLoad = SP.LoadSpec
            SP.LoadSpec = function(self, ...)
                local loaded = originalLoad(self, ...)
                if loaded then
                    local changed = Migration:NormalizeCurrentProfile()
                    if changed > 0 and type(self.MarkDirty) == "function" then
                        self:MarkDirty()
                    end
                end
                return loaded
            end
        end
    end

    if not DDingUI._trackedAuraProfileChangedWrapped and type(DDingUI.OnProfileChanged) == "function" then
        DDingUI._trackedAuraProfileChangedWrapped = true
        local originalProfileChanged = DDingUI.OnProfileChanged
        DDingUI.OnProfileChanged = function(self, ...)
            Migration:Run("profile-changed")
            Migration:QueueStoredSpecMigration()
            return originalProfileChanged(self, ...)
        end
    end

    if not DDingUI._trackedAuraImportWrapped and type(DDingUI.ImportProfileFromString) == "function" then
        DDingUI._trackedAuraImportWrapped = true
        local originalImport = DDingUI.ImportProfileFromString
        DDingUI.ImportProfileFromString = function(self, ...)
            local ok, message = originalImport(self, ...)
            if ok then
                local changed = Migration:Run("profile-import")
                Migration:QueueStoredSpecMigration()
                if changed > 0 and self.RefreshAll then
                    self:RefreshAll()
                end
            end
            return ok, message
        end
    end

    local ResourceBars = DDingUI.ResourceBars
    if ResourceBars and not ResourceBars._trackedAuraProfileMigrationWrapped
        and type(ResourceBars.Initialize) == "function"
    then
        ResourceBars._trackedAuraProfileMigrationWrapped = true
        local originalResourceInitialize = ResourceBars.Initialize
        ResourceBars.Initialize = function(self, ...)
            Migration:Run("resource-initialize")
            return originalResourceInitialize(self, ...)
        end
    end
end

InstallLifecycleHooks()
