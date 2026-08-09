local ns = select(2, ...)
local DDingUI = ns.Addon

local IconIdentity = {}
DDingUI.CustomIconIdentity = IconIdentity

local LEGACY_PREFIX = "dyn:"
local STABLE_PREFIX = "dynid:"

local function EncodePart(value)
    local text = tostring(value or "")
    return (text:gsub("([^%w_.%-])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function PositiveNumber(value)
    local number = tonumber(value)
    if number and number > 0 then return number end
    return nil
end

local function BuildBaseIdentity(iconData, iconKey)
    if type(iconData) ~= "table" then
        return "legacy:" .. EncodePart(iconKey)
    end

    local iconType = tostring(iconData.type or "unknown")
    local settings = type(iconData.settings) == "table" and iconData.settings or {}
    local effectKey = settings.trinketEffectKey
    if effectKey and effectKey ~= "" then
        return "trinket-effect:" .. EncodePart(effectKey)
    end

    if iconType == "slot" or iconType == "trinketProc" then
        local slotID = PositiveNumber(iconData.slotID)
        if slotID then
            return iconType .. ":slot:" .. tostring(slotID)
        end
    elseif iconType == "totem" then
        local totemSlot = PositiveNumber(iconData.totemSlot)
        if totemSlot then
            return "totem:slot:" .. tostring(totemSlot)
        end
    end

    local id = PositiveNumber(iconData.id)
    if id then
        local identity = iconType .. ":id:" .. tostring(id)
        local stateID = PositiveNumber(settings.customAuraStateID)
        if stateID and stateID ~= id then
            identity = identity .. ":state:" .. tostring(stateID)
        end
        local trigger = settings.customAuraTrigger
        if trigger and trigger ~= "" and trigger ~= "spellcast" then
            identity = identity .. ":trigger:" .. EncodePart(trigger)
        end
        return identity
    end

    if iconType == "racial" then
        return "racial:player"
    end

    return iconType .. ":legacy:" .. EncodePart(iconKey)
end

local function SortedIconKeys(iconDataDB)
    local keys = {}
    for iconKey in pairs(iconDataDB or {}) do
        if type(iconKey) == "string" then
            keys[#keys + 1] = iconKey
        end
    end
    table.sort(keys)
    return keys
end

function IconIdentity:GetPersistentID(iconData, iconKey)
    local persistentID = type(iconData) == "table" and iconData.persistentID
    if type(persistentID) == "string" and persistentID ~= "" then
        return persistentID
    end
    return BuildBaseIdentity(iconData, iconKey)
end

function IconIdentity:EnsureDatabase(db)
    local iconDataDB = db and db.iconData
    if type(iconDataDB) ~= "table" then return false end

    local changed = false
    local used = {}
    local keys = SortedIconKeys(iconDataDB)

    for _, iconKey in ipairs(keys) do
        local iconData = iconDataDB[iconKey]
        local persistentID = type(iconData) == "table" and iconData.persistentID
        if type(persistentID) == "string" and persistentID ~= "" and not used[persistentID] then
            used[persistentID] = iconKey
        elseif type(iconData) == "table" and persistentID ~= nil then
            iconData.persistentID = nil
            changed = true
        end
    end

    for _, iconKey in ipairs(keys) do
        local iconData = iconDataDB[iconKey]
        if type(iconData) == "table" and not iconData.persistentID then
            local base = BuildBaseIdentity(iconData, iconKey)
            local persistentID = base
            local suffix = 2
            while used[persistentID] do
                persistentID = base .. "#" .. tostring(suffix)
                suffix = suffix + 1
            end
            iconData.persistentID = persistentID
            used[persistentID] = iconKey
            changed = true
        end
    end

    return changed
end

function IconIdentity:EnsureIcon(db, iconKey, iconData, validateCollision)
    if type(iconData) ~= "table" then return nil end
    if type(iconData.persistentID) == "string" and iconData.persistentID ~= ""
        and not validateCollision
    then
        return iconData.persistentID
    end

    local used = {}
    for otherKey, otherData in pairs((db and db.iconData) or {}) do
        if otherKey ~= iconKey and type(otherData) == "table"
            and type(otherData.persistentID) == "string" and otherData.persistentID ~= ""
        then
            used[otherData.persistentID] = true
        end
    end

    if type(iconData.persistentID) == "string" and iconData.persistentID ~= ""
        and not used[iconData.persistentID]
    then
        return iconData.persistentID
    end
    iconData.persistentID = nil

    local base = BuildBaseIdentity(iconData, iconKey)
    local persistentID = base
    local suffix = 2
    while used[persistentID] do
        persistentID = base .. "#" .. tostring(suffix)
        suffix = suffix + 1
    end
    iconData.persistentID = persistentID
    return persistentID
end

function IconIdentity:BuildOrderToken(db, iconKey)
    local iconData = db and db.iconData and db.iconData[iconKey]
    if type(iconData) ~= "table" then
        return iconKey and (LEGACY_PREFIX .. tostring(iconKey)) or nil
    end
    local persistentID = self:EnsureIcon(db, iconKey, iconData)
    return persistentID and (STABLE_PREFIX .. persistentID) or nil
end

function IconIdentity:ResolveOrderToken(db, token, allowedKeys)
    if type(token) ~= "string" then return nil end
    local legacyKey = token:match("^dyn:(.+)$")
    if legacyKey then
        if db and db.iconData and db.iconData[legacyKey]
            and (not allowedKeys or allowedKeys[legacyKey])
        then
            return legacyKey
        end
        return nil
    end

    local persistentID = token:match("^dynid:(.+)$")
    if not persistentID then return nil end
    for iconKey, iconData in pairs((db and db.iconData) or {}) do
        if type(iconData) == "table" and iconData.persistentID == persistentID
            and (not allowedKeys or allowedKeys[iconKey])
        then
            return iconKey
        end
    end
    return nil
end

function IconIdentity:TokenMatchesIcon(db, token, iconKey)
    if not iconKey then return false end
    return self:ResolveOrderToken(db, token) == iconKey
end

function IconIdentity:RemoveOrderTokens(profile, iconKey)
    local db = profile and profile.dynamicIcons
    if not (db and iconKey) then return false end

    local stableToken = self:BuildOrderToken(db, iconKey)
    local legacyToken = LEGACY_PREFIX .. tostring(iconKey)
    local groups = profile.groupSystem and profile.groupSystem.groups
    if type(groups) ~= "table" then return false end

    local changed = false
    for _, groupSettings in pairs(groups) do
        local order = type(groupSettings) == "table" and groupSettings.iconOrder
        if type(order) == "table" then
            for index = #order, 1, -1 do
                if order[index] == legacyToken or (stableToken and order[index] == stableToken) then
                    table.remove(order, index)
                    changed = true
                end
            end
        end
    end
    return changed
end

function IconIdentity:NormalizeProfile(profile)
    local db = profile and profile.dynamicIcons
    if type(db) ~= "table" then return false end

    local changed = self:EnsureDatabase(db)
    local groups = profile.groupSystem and profile.groupSystem.groups
    if type(groups) ~= "table" then return changed end

    for _, groupSettings in pairs(groups) do
        local order = type(groupSettings) == "table" and groupSettings.iconOrder
        if type(order) == "table" then
            local normalized = {}
            local seen = {}
            local orderChanged = false
            for _, token in ipairs(order) do
                local normalizedToken = token
                if type(token) == "string" and token:match("^dyn:") then
                    local iconKey = self:ResolveOrderToken(db, token)
                    if iconKey then
                        normalizedToken = self:BuildOrderToken(db, iconKey)
                    end
                end
                if normalizedToken and not seen[normalizedToken] then
                    normalized[#normalized + 1] = normalizedToken
                    seen[normalizedToken] = true
                else
                    orderChanged = true
                end
                if normalizedToken ~= token then orderChanged = true end
            end
            if orderChanged then
                groupSettings.iconOrder = normalized
                changed = true
            end
        end
    end

    return changed
end
