--[[
    DDingToolKit - BuffReminder: BR Core
    CallbackRegistry + Config system + UI factories + constants.
    Ported from BuffReminders by zerbi.
]]

local _, ns = ...

-- ============================================================================
-- SHARED CONSTANTS
-- ============================================================================

ns.BR_TEXCOORD_INSET = 0.08
ns.BR_DEFAULT_BORDER_SIZE = 2
ns.BR_DEFAULT_ICON_ZOOM = 0

-- ============================================================================
-- CALLBACK REGISTRY (Event System)
-- ============================================================================

local CallbackRegistry = CreateFromMixins(CallbackRegistryMixin)
CallbackRegistry:OnLoad()
CallbackRegistry:GenerateCallbackEvents({
    "SettingChanged",
    "DisplayRefresh",
    "VisualsRefresh",
    "LayoutRefresh",
    "FramesReparent",
    "VisibilityRefresh",
    "BuffStateChanged",
})
ns.BR_Callbacks = CallbackRegistry

-- ============================================================================
-- CONFIG SYSTEM
-- ============================================================================

ns.BR_Config = {}
ns.BR_Config.DebugMode = false

-- Helper to get profile db
local function GetDB()
    return ns.db and ns.db.profile and ns.db.profile.BuffReminder
end

-- Root-level settings
local RootSettings = {
    splitCategories = "FramesReparent",
    frameLocked = false,
    position = false,
    buffTrackingMode = false,
    showMissingCountOnly = "DisplayRefresh",
    hideInCombat = "VisibilityRefresh",
    hideExpiringInCombat = "VisibilityRefresh",
    showOnlyInGroup = "VisibilityRefresh",
    hideAllInVehicle = "VisibilityRefresh",
    hideWhileMounted = "VisibilityRefresh",
    hideWhileResting = "VisibilityRefresh",
    hideInLegacyInstances = "VisibilityRefresh",
    hideWhileLeveling = "VisibilityRefresh",
    petPassiveOnlyInCombat = "VisibilityRefresh",
}

-- Per-category settings
local CategorySettingKeys = {
    iconSize = "VisualsRefresh",
    iconWidth = "VisualsRefresh",
    iconZoom = "VisualsRefresh",
    borderSize = "VisualsRefresh",
    textSize = "VisualsRefresh",
    textOffsetX = "VisualsRefresh",
    textOffsetY = "VisualsRefresh",
    iconAlpha = "VisualsRefresh",
    textAlpha = "VisualsRefresh",
    textColor = "VisualsRefresh",
    showExpirationGlow = "DisplayRefresh",
    expirationThreshold = "DisplayRefresh",
    spacing = "LayoutRefresh",
    growDirection = "LayoutRefresh",
    subIconSide = "LayoutRefresh",
    anchorFrame = "LayoutRefresh",
    anchorPoint = "LayoutRefresh",
    priority = "LayoutRefresh",
    showBuffReminder = "VisualsRefresh",
    buffTextSize = "VisualsRefresh",
    buffTextOffsetX = "VisualsRefresh",
    buffTextOffsetY = "VisualsRefresh",
    showText = "VisualsRefresh",
    useCustomAppearance = "VisualsRefresh",
    useCustomGlow = "VisualsRefresh",
    -- Glow (expiring)
    glowType = "VisualsRefresh",
    glowColor = "VisualsRefresh",
    glowSize = "VisualsRefresh",
    glowPixelLines = "VisualsRefresh",
    glowPixelFrequency = "VisualsRefresh",
    glowPixelLength = "VisualsRefresh",
    glowAutocastParticles = "VisualsRefresh",
    glowAutocastFrequency = "VisualsRefresh",
    glowAutocastScale = "VisualsRefresh",
    glowBorderFrequency = "VisualsRefresh",
    glowProcDuration = "VisualsRefresh",
    glowProcStartAnim = "VisualsRefresh",
    glowProcUseCustomColor = "VisualsRefresh",
    glowXOffset = "VisualsRefresh",
    glowYOffset = "VisualsRefresh",
    -- Glow (missing)
    showMissingGlow = "DisplayRefresh",
    missingGlowType = "VisualsRefresh",
    missingGlowColor = "VisualsRefresh",
    missingGlowSize = "VisualsRefresh",
    missingGlowPixelLines = "VisualsRefresh",
    missingGlowPixelFrequency = "VisualsRefresh",
    missingGlowPixelLength = "VisualsRefresh",
    missingGlowAutocastParticles = "VisualsRefresh",
    missingGlowAutocastFrequency = "VisualsRefresh",
    missingGlowAutocastScale = "VisualsRefresh",
    missingGlowBorderFrequency = "VisualsRefresh",
    missingGlowProcDuration = "VisualsRefresh",
    missingGlowProcStartAnim = "VisualsRefresh",
    missingGlowProcUseCustomColor = "VisualsRefresh",
    missingGlowXOffset = "VisualsRefresh",
    missingGlowYOffset = "VisualsRefresh",
    split = "FramesReparent",
    position = false,
    clickable = false,
    clickableHighlight = false,
    showOnlyOnReadyCheck = "DisplayRefresh",
}

-- Defaults settings
local DefaultSettingKeys = {
    iconSize = "VisualsRefresh",
    iconWidth = "VisualsRefresh",
    iconZoom = "VisualsRefresh",
    borderSize = "VisualsRefresh",
    textSize = "VisualsRefresh",
    textOffsetX = "VisualsRefresh",
    textOffsetY = "VisualsRefresh",
    iconAlpha = "VisualsRefresh",
    textAlpha = "VisualsRefresh",
    textColor = "VisualsRefresh",
    spacing = "LayoutRefresh",
    growDirection = "LayoutRefresh",
    showExpirationGlow = "DisplayRefresh",
    expirationThreshold = "DisplayRefresh",
    glowType = "VisualsRefresh",
    glowColor = "VisualsRefresh",
    glowSize = "VisualsRefresh",
    glowPixelLines = "VisualsRefresh",
    glowPixelFrequency = "VisualsRefresh",
    glowPixelLength = "VisualsRefresh",
    glowAutocastParticles = "VisualsRefresh",
    glowAutocastFrequency = "VisualsRefresh",
    glowAutocastScale = "VisualsRefresh",
    glowBorderFrequency = "VisualsRefresh",
    glowProcDuration = "VisualsRefresh",
    glowProcStartAnim = "VisualsRefresh",
    glowProcUseCustomColor = "VisualsRefresh",
    glowXOffset = "VisualsRefresh",
    glowYOffset = "VisualsRefresh",
    showMissingGlow = "DisplayRefresh",
    missingGlowType = "VisualsRefresh",
    missingGlowColor = "VisualsRefresh",
    missingGlowSize = "VisualsRefresh",
    missingGlowPixelLines = "VisualsRefresh",
    missingGlowPixelFrequency = "VisualsRefresh",
    missingGlowPixelLength = "VisualsRefresh",
    missingGlowAutocastParticles = "VisualsRefresh",
    missingGlowAutocastFrequency = "VisualsRefresh",
    missingGlowAutocastScale = "VisualsRefresh",
    missingGlowBorderFrequency = "VisualsRefresh",
    missingGlowProcDuration = "VisualsRefresh",
    missingGlowProcStartAnim = "VisualsRefresh",
    missingGlowProcUseCustomColor = "VisualsRefresh",
    missingGlowXOffset = "VisualsRefresh",
    missingGlowYOffset = "VisualsRefresh",
    showConsumablesWithoutItems = "DisplayRefresh",
    delveFoodOnly = "DisplayRefresh",
    delveFoodTimer = "DisplayRefresh",
    freeConsumableMode = "DisplayRefresh",
    freeConsumableVisibility = "DisplayRefresh",
    healthstoneVisibility = "DisplayRefresh",
    healthstoneLowStock = "DisplayRefresh",
    healthstoneThreshold = "DisplayRefresh",
    soulstoneVisibility = "DisplayRefresh",
    soulstoneHideCooldown = "DisplayRefresh",
    consumableDisplayMode = "DisplayRefresh",
    consumableTextScale = "VisualsRefresh",
    showConsumableTooltips = false,
    petDisplayMode = "DisplayRefresh",
    petLabels = "DisplayRefresh",
    petLabelScale = "DisplayRefresh",
    petSpecIconOnHover = "DisplayRefresh",
    useFelDomination = "DisplayRefresh",
    fontFace = "VisualsRefresh",
    position = false,
}

local ValidCategories = {
    main = true,
    raid = true, presence = true, targeted = true,
    self = true, pet = true, consumable = true, custom = true,
}

local DynamicRoots = {
    enabledBuffs = "DisplayRefresh",
    categoryVisibility = "DisplayRefresh",
    splitCategories = "FramesReparent",
    readyCheckOnlyOverrides = "DisplayRefresh",
    detachedIcons = "FramesReparent",
}

local function ValidatePath(segments)
    if #segments == 0 then return false, nil end
    local root = segments[1]

    local isRootSetting = RootSettings[root] ~= nil
    if isRootSetting then
        if #segments == 1 then return true, RootSettings[root] end
        if root == "position" and #segments == 2 then return true, nil end
        return false, nil
    end

    if root == "defaults" then
        if #segments == 1 then return true, nil end
        if #segments == 2 then
            local setting = segments[2]
            if DefaultSettingKeys[setting] ~= nil then return true, DefaultSettingKeys[setting] end
            return false, nil
        end
        return false, nil
    end

    if root == "categorySettings" then
        if #segments < 2 then return true, nil end
        local category = segments[2]
        if not ValidCategories[category] then return false, nil end
        if #segments == 2 then return true, nil end
        if #segments == 3 then
            local setting = segments[3]
            if CategorySettingKeys[setting] ~= nil then return true, CategorySettingKeys[setting] end
            return false, nil
        end
        return false, nil
    end

    if DynamicRoots[root] then return true, DynamicRoots[root] end
    return false, nil
end

function ns.BR_Config.IsValidPath(path)
    local segments = {}
    for segment in path:gmatch("[^.]+") do
        table.insert(segments, segment)
    end
    return ValidatePath(segments)
end

function ns.BR_Config.Set(path, value)
    local db = GetDB()
    if not db then return end

    local segments = {}
    for segment in path:gmatch("[^.]+") do
        table.insert(segments, segment)
    end
    if #segments == 0 then return end

    local isValid, validatedRefreshType = ValidatePath(segments)
    if not isValid and ns.BR_Config.DebugMode then
        print("|cffff6600DDingToolKit BR:|r Invalid config path: " .. path)
    end

    local parent = db
    for i = 1, #segments - 1 do
        local key = segments[i]
        if parent[key] == nil then parent[key] = {} end
        parent = parent[key]
    end

    local finalKey = segments[#segments]
    local oldValue = parent[finalKey]
    if oldValue == value then return end

    parent[finalKey] = value
    CallbackRegistry:TriggerEvent("SettingChanged", path, value, oldValue)
    if validatedRefreshType then
        CallbackRegistry:TriggerEvent(validatedRefreshType, path)
    end
end

function ns.BR_Config.Get(path, default)
    local db = GetDB()
    if not db then return default end

    local current = db
    for segment in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return default end
        current = current[segment]
        if current == nil then return default end
    end
    return current
end

function ns.BR_Config.SetMulti(changes)
    local db = GetDB()
    if not db then return end

    local refreshTypes = {}
    for path, value in pairs(changes) do
        local segments = {}
        for segment in path:gmatch("[^.]+") do
            table.insert(segments, segment)
        end
        if #segments > 0 then
            local isValid, validatedRefreshType = ValidatePath(segments)
            if not isValid and ns.BR_Config.DebugMode then
                print("|cffff6600DDingToolKit BR:|r Invalid config path: " .. path)
            end
            local parent = db
            for i = 1, #segments - 1 do
                local key = segments[i]
                if parent[key] == nil then parent[key] = {} end
                parent = parent[key]
            end
            local finalKey = segments[#segments]
            local oldValue = parent[finalKey]
            if oldValue ~= value then
                parent[finalKey] = value
                CallbackRegistry:TriggerEvent("SettingChanged", path, value, oldValue)
                if validatedRefreshType then refreshTypes[validatedRefreshType] = true end
            end
        end
    end
    for refreshType in pairs(refreshTypes) do
        CallbackRegistry:TriggerEvent(refreshType)
    end
end

-- ============================================================================
-- CATEGORY SETTING INHERITANCE
-- ============================================================================

local AppearanceKeys = {
    iconSize = true, iconWidth = true, textSize = true,
    textOffsetX = true, textOffsetY = true,
    iconAlpha = true, textAlpha = true, textColor = true,
    spacing = true, iconZoom = true, borderSize = true,
    growDirection = true, showExpirationGlow = true,
    showMissingGlow = true, expirationThreshold = true,
}

local GlowKeys = {
    glowType = true, glowColor = true, glowSize = true,
    glowPixelLines = true, glowPixelFrequency = true, glowPixelLength = true,
    glowAutocastParticles = true, glowAutocastFrequency = true, glowAutocastScale = true,
    glowBorderFrequency = true, glowProcDuration = true, glowProcStartAnim = true,
    glowProcUseCustomColor = true, glowXOffset = true, glowYOffset = true,
    missingGlowType = true, missingGlowColor = true, missingGlowSize = true,
    missingGlowPixelLines = true, missingGlowPixelFrequency = true, missingGlowPixelLength = true,
    missingGlowAutocastParticles = true, missingGlowAutocastFrequency = true, missingGlowAutocastScale = true,
    missingGlowBorderFrequency = true, missingGlowProcDuration = true, missingGlowProcStartAnim = true,
    missingGlowProcUseCustomColor = true, missingGlowXOffset = true, missingGlowYOffset = true,
}

function ns.BR_Config.GetCategorySetting(category, key)
    local db = GetDB()
    if not db then return nil end

    local catSettings = db.categorySettings and db.categorySettings[category]
    if not catSettings then
        return db.defaults and db.defaults[key]
    end

    if AppearanceKeys[key] then
        if not catSettings.useCustomAppearance then
            return db.defaults and db.defaults[key]
        end
        return catSettings[key]
    end

    if GlowKeys[key] then
        if not catSettings.useCustomAppearance or not catSettings.useCustomGlow then
            return db.defaults and db.defaults[key]
        end
        return catSettings[key]
    end

    local value = catSettings[key]
    if value ~= nil then return value end
    return db.defaults and db.defaults[key]
end

function ns.BR_Config.HasCustomAppearance(category)
    local db = GetDB()
    if not db or not db.categorySettings or not db.categorySettings[category] then return false end
    return db.categorySettings[category].useCustomAppearance == true
end

function ns.BR_Config.HasCustomGlow(category)
    local db = GetDB()
    if not db or not db.categorySettings or not db.categorySettings[category] then return false end
    local cat = db.categorySettings[category]
    return cat.useCustomAppearance == true and cat.useCustomGlow == true
end

-- ============================================================================
-- SHARED UI FACTORIES
-- ============================================================================

function ns.BR_CreatePanel(name, width, height, options)
    options = options or {}
    local isModal = options.modal
    local bgColor = options.bgColor or (isModal and { 0.15, 0.15, 0.15, 0.98 } or { 0.1, 0.1, 0.1, 0.95 })
    local borderColor = options.borderColor or (isModal and { 0.5, 0.5, 0.5, 1 } or { 0.3, 0.3, 0.3, 1 })

    local panel = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(unpack(bgColor))
    panel:SetBackdropBorderColor(unpack(borderColor))
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata(options.strata or "DIALOG")
    if options.level then panel:SetFrameLevel(options.level) end
    if isModal then
        panel:EnableKeyboard(true)
        panel:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then return end
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                self:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
    elseif options.escClose and name then
        tinsert(UISpecialFrames, name)
    end
    return panel
end

function ns.BR_CreateSectionHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, y)
    header:SetText("|cffffcc00" .. text .. "|r")
    return header, y - 18
end

function ns.BR_CreateBuffIcon(parent, size, textureID)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexCoord(ns.BR_TEXCOORD_INSET, 1 - ns.BR_TEXCOORD_INSET, ns.BR_TEXCOORD_INSET, 1 - ns.BR_TEXCOORD_INSET)
    if textureID then icon:SetTexture(textureID) end
    return icon
end

-- ============================================================================
-- CLASS SPEC OPTIONS (for custom buff spec filtering)
-- ============================================================================

local CLASS_IDS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4,
    PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
    WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}

ns.BR_CLASS_SPEC_OPTIONS = {}
for token, classID in pairs(CLASS_IDS) do
    local specs = {}
    for i = 1, 4 do
        local specID, name = GetSpecializationInfoForClassID(classID, i)
        if specID then
            table.insert(specs, { value = specID, label = name })
        end
    end
    table.sort(specs, function(a, b) return a.label < b.label end)
    local opts = { { value = nil, label = "모두" } }
    for _, spec in ipairs(specs) do
        table.insert(opts, spec)
    end
    ns.BR_CLASS_SPEC_OPTIONS[token] = opts
end

-- Component registries (populated by BR_Components.lua)
ns.BR_Components = {}
ns.BR_RefreshableComponents = {}
