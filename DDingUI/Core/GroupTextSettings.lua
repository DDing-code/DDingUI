local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupTextSettings = {}
DDingUI.GroupTextSettings = GroupTextSettings

GroupTextSettings.SCHEMA_VERSION = 2
GroupTextSettings.CORE_GROUP_VIEWERS = {
    Cooldowns = "EssentialCooldownViewer",
    Buffs = "BuffIconCooldownViewer",
    Utility = "UtilityCooldownViewer",
}

GroupTextSettings.DEFAULTS = {
    hideCountText = false,
    countTextSize = 14,
    countTextColor = { 1, 1, 1, 1 },
    chargeTextAnchor = "BOTTOMRIGHT",
    countTextOffsetX = 0,
    countTextOffsetY = 0,
    hideCooldownText = false,
    cooldownFontSize = 18,
    cooldownTextColor = { 1, 1, 1, 1 },
    cooldownTextAnchor = "CENTER",
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownShadowOffsetX = 0,
    cooldownShadowOffsetY = 0,
    cooldownTextFormat = "auto",
    hideDurationText = false,
    durationTextAnchor = "TOP",
    durationTextOffsetX = 0,
    durationTextOffsetY = 0,
    durationTextSize = 12,
    durationTextColor = { 1, 1, 1, 1 },
}

GroupTextSettings.KEYS = {
    "hideCountText", "countTextFont", "countTextSize", "countTextColor",
    "chargeTextAnchor", "countTextOffsetX", "countTextOffsetY",
    "hideCooldownText", "cooldownFont", "cooldownFontSize", "cooldownTextColor",
    "cooldownTextAnchor", "cooldownTextOffsetX", "cooldownTextOffsetY",
    "cooldownShadowOffsetX", "cooldownShadowOffsetY", "cooldownTextFormat",
    "hideDurationText", "durationTextFont", "durationTextAnchor",
    "durationTextOffsetX", "durationTextOffsetY", "durationTextSize", "durationTextColor",
}

local function CopyValue(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = type(child) == "table" and CopyValue(child) or child
    end
    for index = 1, 4 do
        if copy[index] == nil and value[index] ~= nil then
            copy[index] = value[index]
        end
    end
    return copy
end

function GroupTextSettings:Resolve(groupSettings, primaryKey, fallbackKey)
    if type(groupSettings) == "table" then
        local value = primaryKey and groupSettings[primaryKey]
        if value ~= nil then return value end

        value = fallbackKey and groupSettings[fallbackKey]
        if value ~= nil then return value end
    end

    local value = primaryKey and self.DEFAULTS[primaryKey]
    if value ~= nil then return value end
    return fallbackKey and self.DEFAULTS[fallbackKey] or nil
end

function GroupTextSettings:NormalizeProfile(profile)
    local groupSystem = type(profile) == "table" and profile.groupSystem
    local groups = type(groupSystem) == "table" and groupSystem.groups
    if type(groups) ~= "table" then return false end

    local changed = false
    if type(profile.viewers) ~= "table" then
        profile.viewers = {}
        changed = true
    end

    for groupName, group in pairs(groups) do
        if type(group) == "table" then
            local viewerName = self.CORE_GROUP_VIEWERS[groupName]
            local viewer = viewerName and profile.viewers[viewerName]
            if viewerName and type(viewer) ~= "table" then
                viewer = {}
                profile.viewers[viewerName] = viewer
                changed = true
            end

            local schemaVersion = tonumber(rawget(group, "_groupTextSchemaVersion")) or 0
            if schemaVersion < self.SCHEMA_VERSION and type(viewer) == "table" then
                for _, key in ipairs(self.KEYS) do
                    if rawget(group, key) == nil and viewer[key] ~= nil then
                        group[key] = CopyValue(viewer[key])
                        changed = true
                    end
                end
            end

            for _, key in ipairs(self.KEYS) do
                local value = rawget(group, key)
                if value == nil and self.DEFAULTS[key] ~= nil then
                    value = CopyValue(self.DEFAULTS[key])
                    group[key] = value
                    changed = true
                end

                if type(viewer) == "table" then
                    viewer[key] = CopyValue(value)
                end
            end

            if schemaVersion < self.SCHEMA_VERSION then
                group._groupTextSchemaVersion = self.SCHEMA_VERSION
                changed = true
            end
        end
    end

    return changed
end
