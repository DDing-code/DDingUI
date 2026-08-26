local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Compat = {}
DDingUI.CDMCompat = Compat

local type = type
local ipairs = ipairs
local pairs = pairs
local floor = math.floor
local canaccessvalue = canaccessvalue
local issecretvalue = issecretvalue

local cooldownInfoCache = {}
local categorySetCache = {}
local categoryLookupCache = {}
local spellIDCache = {}
local spellIdentityCache = {}
local frameCache = setmetatable({}, { __mode = "k" })
local framesByCooldownID = {}
local hookedPools = setmetatable({}, { __mode = "k" })
local groupBuffItemsCache
local hiddenGroupBuffSpellSetCache
local hiddenGroupBuffSpellSetReady = false
local categoryDefinitionsCache
local generation = 0

local NUMBER_FIELDS = {
    "cooldownID",
    "spellID",
    "displaySpellID",
    "spellCategoryID",
    "overrideSpellID",
    "overrideTooltipSpellID",
    "equipSlot",
    "buffSlot",
    "linkedSpellID",
    "lastItemIDForCategory",
    "lastItemIDForCategoryIcon",
    "flags",
    "category",
}

local BOOLEAN_FIELDS = {
    "selfAura",
    "hasAura",
    "charges",
    "isKnown",
    "isInvisible",
}

local CATEGORY_SPECS = {
    { name = "Essential", fallback = 0, bucket = "Essential", viewerName = "EssentialCooldownViewer", defaultGroup = "Cooldowns", isAura = false },
    { name = "Utility", fallback = 1, bucket = "Utility", viewerName = "UtilityCooldownViewer", defaultGroup = "Utility", isAura = false },
    { name = "TrackedBuff", fallback = 2, bucket = "Buff", viewerName = "BuffIconCooldownViewer", defaultGroup = "Buffs", isAura = true },
    { name = "TrackedBar", fallback = 3, bucket = "Buff", viewerName = "BuffBarCooldownViewer", defaultGroup = "Buffs", isAura = true },
    { name = "GroupBuff", fallback = 4, bucket = "Buff", viewerName = "BuffIconCooldownViewer", defaultGroup = "Buffs", isAura = true },
    { name = "SpecAgnosticEssential", fallback = 5, bucket = "Essential", viewerName = "EssentialCooldownViewer", defaultGroup = "Cooldowns", isAura = false },
    { name = "SpecAgnosticTracked", fallback = 6, bucket = "Buff", viewerName = "BuffIconCooldownViewer", defaultGroup = "Buffs", isAura = true },
    { name = "EquipSlotEssential", fallback = 7, bucket = "Essential", viewerName = "EssentialCooldownViewer", defaultGroup = "Cooldowns", isAura = false },
    { name = "EquipSlotTracked", fallback = 8, bucket = "Buff", viewerName = "BuffIconCooldownViewer", defaultGroup = "Buffs", isAura = true },
}

local function IsSecret(value)
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then
        return true
    end
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

function Compat:IsPublicValue(value)
    return not IsSecret(value)
end

function Compat:IsPublicNumber(value)
    if IsSecret(value) or type(value) ~= "number" then
        return false
    end
    return value == value
end

function Compat:IsUsableID(value)
    return self:IsPublicNumber(value) and value > 0 and value == floor(value)
end

function Compat:IsPublicString(value)
    return not IsSecret(value) and type(value) == "string"
end

function Compat:GetFrameActiveState(frame)
    if not frame then return nil end

    if type(frame.IsActive) == "function" then
        local ok, active = pcall(frame.IsActive, frame)
        if ok and not IsSecret(active) and type(active) == "boolean" then
            return active
        end
    end

    local active = frame.isActive
    if not IsSecret(active) and type(active) == "boolean" then
        return active
    end
    return nil
end

local function CopyPublicInfo(info, fallbackCooldownID)
    if IsSecret(info) or type(info) ~= "table" then return nil end

    local copy = {}
    for _, key in ipairs(NUMBER_FIELDS) do
        local value = info[key]
        if Compat:IsPublicNumber(value) then
            copy[key] = value
        end
    end

    if not copy.cooldownID and Compat:IsUsableID(fallbackCooldownID) then
        copy.cooldownID = fallbackCooldownID
    end

    for _, key in ipairs(BOOLEAN_FIELDS) do
        local value = info[key]
        if not IsSecret(value) and type(value) == "boolean" then
            copy[key] = value
        end
    end

    local linkedSpellIDs = info.linkedSpellIDs
    copy.linkedSpellIDs = {}
    if not IsSecret(linkedSpellIDs) and type(linkedSpellIDs) == "table" then
        for _, spellID in ipairs(linkedSpellIDs) do
            if Compat:IsUsableID(spellID) then
                copy.linkedSpellIDs[#copy.linkedSpellIDs + 1] = spellID
            end
        end
    end

    return copy
end

local function MergeInfo(target, source)
    if type(target) ~= "table" then return source end
    if type(source) ~= "table" then return target end

    for _, key in ipairs(NUMBER_FIELDS) do
        if source[key] ~= nil then
            target[key] = source[key]
        end
    end
    for _, key in ipairs(BOOLEAN_FIELDS) do
        if source[key] ~= nil then
            target[key] = source[key]
        end
    end
    if source.linkedSpellIDs and #source.linkedSpellIDs > 0 then
        target.linkedSpellIDs = source.linkedSpellIDs
    elseif not target.linkedSpellIDs then
        target.linkedSpellIDs = {}
    end
    return target
end

function Compat:SanitizeCooldownInfo(info, fallbackCooldownID)
    return CopyPublicInfo(info, fallbackCooldownID)
end

function Compat:GetCooldownInfo(cooldownID, forceRefresh)
    if not self:IsUsableID(cooldownID) then return nil end
    if not forceRefresh and cooldownInfoCache[cooldownID] then
        return cooldownInfoCache[cooldownID]
    end

    local api = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if type(api) ~= "function" then
        return cooldownInfoCache[cooldownID]
    end

    local ok, rawInfo = pcall(api, cooldownID)
    if not ok or type(rawInfo) ~= "table" then
        return cooldownInfoCache[cooldownID]
    end

    local cleanInfo = CopyPublicInfo(rawInfo, cooldownID)
    if cleanInfo then
        cooldownInfoCache[cooldownID] = MergeInfo(cooldownInfoCache[cooldownID], cleanInfo)
    end
    return cooldownInfoCache[cooldownID]
end

function Compat:GetCategory(categoryName)
    if type(categoryName) ~= "string" then return nil end
    local categories = Enum and Enum.CooldownViewerCategory
    local value = categories and categories[categoryName]
    if self:IsPublicNumber(value) then
        return value
    end

    for _, spec in ipairs(CATEGORY_SPECS) do
        if spec.name == categoryName and self:IsPublicNumber(spec.fallback) then
            return spec.fallback
        end
    end
    return nil
end

function Compat:GetCategoryDefinitions()
    if categoryDefinitionsCache then
        return categoryDefinitionsCache
    end
    local definitions = {}
    for _, spec in ipairs(CATEGORY_SPECS) do
        local category = self:GetCategory(spec.name)
        if self:IsPublicNumber(category) then
            definitions[#definitions + 1] = {
                name = spec.name,
                category = category,
                bucket = spec.bucket,
                viewerName = spec.viewerName,
                defaultGroup = spec.defaultGroup,
                isAura = spec.isAura,
            }
        end
    end
    categoryDefinitionsCache = definitions
    return categoryDefinitionsCache
end

function Compat:GetCategorySet(category, allowUnlearned, forceRefresh)
    if not self:IsPublicNumber(category) then return nil end
    local cacheKey = tostring(category) .. (allowUnlearned and ":all" or ":known")
    if not forceRefresh and categorySetCache[cacheKey] then
        return categorySetCache[cacheKey]
    end

    local api = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
    if type(api) ~= "function" then
        return categorySetCache[cacheKey]
    end

    local ok, rawIDs = pcall(api, category, allowUnlearned == true)
    if not ok or IsSecret(rawIDs) or type(rawIDs) ~= "table" then
        return categorySetCache[cacheKey]
    end

    local cleanIDs = {}
    local seen = {}
    for _, cooldownID in ipairs(rawIDs) do
        if self:IsUsableID(cooldownID) and not seen[cooldownID] then
            seen[cooldownID] = true
            cleanIDs[#cleanIDs + 1] = cooldownID
        end
    end
    categorySetCache[cacheKey] = cleanIDs
    return cleanIDs
end

function Compat:GetCategoryLookup(category, allowUnlearned, forceRefresh)
    if not self:IsPublicNumber(category) then return nil end
    local cacheKey = tostring(category) .. (allowUnlearned and ":all" or ":known")
    if not forceRefresh and categoryLookupCache[cacheKey] then
        return categoryLookupCache[cacheKey]
    end

    local cooldownIDs = self:GetCategorySet(category, allowUnlearned, forceRefresh)
    if type(cooldownIDs) ~= "table" then return nil end

    local lookup = {}
    for _, cooldownID in ipairs(cooldownIDs) do
        if self:IsUsableID(cooldownID) then
            lookup[cooldownID] = true
        end
    end
    categoryLookupCache[cacheKey] = lookup
    return lookup
end

function Compat:GetHiddenGroupBuffSpellSet(forceRefresh)
    if hiddenGroupBuffSpellSetReady and not forceRefresh then
        return hiddenGroupBuffSpellSetCache
    end

    local settings = _G.CooldownViewerSettings
    if not settings or type(settings.GetLayoutManager) ~= "function"
        or type(_G.CooldownManagerLayout_GetHiddenGroupBuffs) ~= "function"
    then
        return nil
    end

    local okManager, layoutManager = pcall(settings.GetLayoutManager, settings)
    if not okManager or not layoutManager or type(layoutManager.GetActiveLayout) ~= "function" then
        return nil
    end

    local accessOnly = Enum and Enum.CDMLayoutMode and Enum.CDMLayoutMode.AccessOnly or false
    local okLayout, layout = pcall(layoutManager.GetActiveLayout, layoutManager, accessOnly)
    if not okLayout or not layout then return nil end

    local okList, hiddenSpellIDs = pcall(_G.CooldownManagerLayout_GetHiddenGroupBuffs, layout)
    if not okList or IsSecret(hiddenSpellIDs) or type(hiddenSpellIDs) ~= "table" then
        return nil
    end

    local lookup = {}
    for _, spellID in ipairs(hiddenSpellIDs) do
        if self:IsUsableID(spellID) then
            lookup[spellID] = true
        end
    end
    hiddenGroupBuffSpellSetCache = lookup
    hiddenGroupBuffSpellSetReady = true
    return hiddenGroupBuffSpellSetCache
end

function Compat:GetProviderEntryDisposition(cooldownID, providerInfo, rawInfo, liveCategoryLookup, hiddenGroupBuffSpells)
    if not self:IsUsableID(cooldownID) then return nil end

    local merged = self:SanitizeCooldownInfo(providerInfo, cooldownID)
    local raw = self:SanitizeCooldownInfo(rawInfo, cooldownID)
    local category = merged and merged.category
    local categories = Enum and Enum.CooldownViewerCategory
    local hiddenActive = categories and categories.HiddenActive or -1
    local hiddenPassive = categories and categories.HiddenPassive or -2

    if category == hiddenActive or category == hiddenPassive then
        return "hidden"
    end

    local groupBuff = self:GetCategory("GroupBuff")
    local specEssential = self:GetCategory("SpecAgnosticEssential")
    local specTracked = self:GetCategory("SpecAgnosticTracked")
    local equipEssential = self:GetCategory("EquipSlotEssential")
    local equipTracked = self:GetCategory("EquipSlotTracked")
    local needsRaw = category == nil or category == groupBuff
        or category == specEssential or category == specTracked
        or category == equipEssential or category == equipTracked

    if needsRaw and not raw then
        raw = self:GetCooldownInfo(cooldownID)
    end
    if category == nil and raw then
        category = raw.category
    end
    if not self:IsPublicNumber(category) then return nil end

    if category == groupBuff then
        local spellID = merged and merged.spellID or raw and raw.spellID
        local hiddenSet = hiddenGroupBuffSpells
        if hiddenSet == nil then
            hiddenSet = self:GetHiddenGroupBuffSpellSet()
        end
        if self:IsUsableID(spellID) and type(hiddenSet) == "table" and hiddenSet[spellID] then
            return "hidden"
        end
        return nil
    end

    local isSelfMappedCategory = category == specEssential or category == specTracked
        or category == equipEssential or category == equipTracked
    if not isSelfMappedCategory or not raw then return nil end

    local lookup = liveCategoryLookup
    if lookup == nil then
        lookup = self:GetCategoryLookup(category, true)
    end
    if type(lookup) == "table" and next(lookup) and not lookup[cooldownID] then
        return "removed"
    end
    if raw.isKnown == false then
        return "removed"
    end
    return nil
end

function Compat:IsKnownSpell(spellID)
    if not self:IsUsableID(spellID) or type(IsPlayerSpell) ~= "function" then return nil end
    local ok, known = pcall(IsPlayerSpell, spellID)
    if not ok or IsSecret(known) or type(known) ~= "boolean" then return nil end
    return known
end

function Compat:GetBaseSpellID(spellID)
    if not self:IsUsableID(spellID) then return nil end
    local api = C_Spell and C_Spell.GetBaseSpell
    if type(api) == "function" then
        local ok, baseSpellID = pcall(api, spellID)
        if ok and self:IsUsableID(baseSpellID) then
            return baseSpellID
        end
    end
    return spellID
end

function Compat:GetLiveOverrideSpellID(spellID)
    if not self:IsUsableID(spellID) then return nil end
    local api = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    if type(api) == "function" then
        local ok, overrideSpellID = pcall(api, spellID)
        if ok and self:IsUsableID(overrideSpellID) then
            return overrideSpellID
        end
    end
    return spellID
end

function Compat:GetCooldownSpellIdentity(cooldownID, info, preferredSpellID, forceRefresh)
    if not self:IsUsableID(cooldownID) then return nil end
    local cached = spellIdentityCache[cooldownID]
    if cached and #cached.spellIDs > 0 and not forceRefresh
        and (not self:IsUsableID(preferredSpellID) or cached.idSet[preferredSpellID])
    then
        return cached
    end

    local sourceInfo = self:SanitizeCooldownInfo(info, cooldownID)
    local apiInfo = self:GetCooldownInfo(cooldownID, forceRefresh == true)
    if sourceInfo and apiInfo then
        sourceInfo = MergeInfo(sourceInfo, apiInfo)
    else
        sourceInfo = sourceInfo or apiInfo
    end
    local identity = { spellIDs = {}, idSet = {}, names = {}, nameSet = {} }

    local function AddNameForID(spellID)
        local api = C_Spell and C_Spell.GetSpellName
        if type(api) ~= "function" then return end
        local ok, name = pcall(api, spellID)
        if ok and self:IsPublicString(name) and name ~= "" and not identity.nameSet[name] then
            identity.nameSet[name] = true
            identity.names[#identity.names + 1] = name
        end
    end

    local function AddSpellID(spellID)
        if not self:IsUsableID(spellID) or identity.idSet[spellID] then return end
        identity.idSet[spellID] = true
        identity.spellIDs[#identity.spellIDs + 1] = spellID
        AddNameForID(spellID)
    end

    local displaySpellID = sourceInfo and sourceInfo.displaySpellID
    if not self:IsUsableID(displaySpellID) then displaySpellID = nil end
    local primarySpellID = sourceInfo and sourceInfo.spellID
    if not self:IsUsableID(primarySpellID) and sourceInfo and type(sourceInfo.linkedSpellIDs) == "table" then
        primarySpellID = sourceInfo.linkedSpellIDs[1]
    end
    if not self:IsUsableID(primarySpellID) and sourceInfo then
        primarySpellID = sourceInfo.overrideSpellID
    end

    local canonicalSpellID = self:GetBaseSpellID(primarySpellID or preferredSpellID)
    local liveSpellID = self:GetLiveOverrideSpellID(canonicalSpellID or primarySpellID)
    local liveSpellKnown = self:IsKnownSpell(liveSpellID)
    local overrideSpellKnown = sourceInfo and self:IsKnownSpell(sourceInfo.overrideSpellID)
    local preferred = self:IsUsableID(preferredSpellID) and preferredSpellID or nil
    if not preferred and liveSpellKnown == true then
        preferred = liveSpellID
    end
    if not preferred and overrideSpellKnown == true then
        preferred = sourceInfo.overrideSpellID
    end
    local fallbackOverride = sourceInfo and sourceInfo.overrideSpellID
    if not self:IsUsableID(fallbackOverride) then fallbackOverride = nil end
    local fallbackTooltip = sourceInfo and sourceInfo.overrideTooltipSpellID
    if not self:IsUsableID(fallbackTooltip) then fallbackTooltip = nil end
    preferred = preferred or displaySpellID or primarySpellID or fallbackOverride or fallbackTooltip

    AddSpellID(preferred)
    AddSpellID(displaySpellID)
    if liveSpellKnown == true then AddSpellID(liveSpellID) end
    if overrideSpellKnown == true then
        AddSpellID(sourceInfo.overrideSpellID)
    end
    AddSpellID(primarySpellID)
    AddSpellID(canonicalSpellID)
    if sourceInfo then
        AddSpellID(sourceInfo.linkedSpellID)
        AddSpellID(sourceInfo.overrideSpellID)
        AddSpellID(sourceInfo.overrideTooltipSpellID)
        if type(sourceInfo.linkedSpellIDs) == "table" then
            for _, linkedSpellID in ipairs(sourceInfo.linkedSpellIDs) do
                AddSpellID(linkedSpellID)
                AddSpellID(self:GetBaseSpellID(linkedSpellID))
            end
        end
    end

    identity.preferredSpellID = identity.spellIDs[1]
    identity.canonicalSpellID = canonicalSpellID or self:GetBaseSpellID(identity.preferredSpellID)
    spellIdentityCache[cooldownID] = identity.preferredSpellID and identity or nil
    return identity
end

function Compat:FindSpellMapValue(map, cooldownID, fallbackName, isBuff)
    if type(map) ~= "table" then return nil end
    if self:IsPublicString(fallbackName) and fallbackName ~= "" and map[fallbackName] ~= nil then
        return map[fallbackName], fallbackName
    end

    local identity = self:GetCooldownSpellIdentity(cooldownID)
    if not identity then return nil end
    for _, rawName in ipairs(identity.names) do
        local key = rawName
        if isBuff and rawName:sub(1, 5) ~= "buff_" then
            key = "buff_" .. rawName
        end
        if map[key] ~= nil then
            return map[key], key
        end
    end
    return nil
end

function Compat:ResolveInfoSpellID(info)
    if IsSecret(info) or type(info) ~= "table" then return nil end

    if self:IsUsableID(info.overrideSpellID) then
        return info.overrideSpellID
    end
    if self:IsUsableID(info.linkedSpellID) then
        return info.linkedSpellID
    end

    local linkedSpellIDs = info.linkedSpellIDs
    if not IsSecret(linkedSpellIDs) and type(linkedSpellIDs) == "table" then
        for _, spellID in ipairs(linkedSpellIDs) do
            if self:IsUsableID(spellID) then
                return spellID
            end
        end
    end

    if self:IsUsableID(info.spellID) then
        return info.spellID
    end
    return nil
end

function Compat:RememberFrame(frame, cooldownID)
    if not frame or not self:IsUsableID(cooldownID) then return nil end
    local data = frameCache[frame]
    if not data then
        data = {}
        frameCache[frame] = data
    elseif data.cooldownID ~= cooldownID then
        local previousFrames = framesByCooldownID[data.cooldownID]
        if previousFrames then
            previousFrames[frame] = nil
            if not next(previousFrames) then
                framesByCooldownID[data.cooldownID] = nil
            end
        end
        data.spellID = nil
    end
    data.cooldownID = cooldownID

    local frames = framesByCooldownID[cooldownID]
    if not frames then
        frames = setmetatable({}, { __mode = "k" })
        framesByCooldownID[cooldownID] = frames
    end
    frames[frame] = true
    return cooldownID
end

function Compat:ForgetFrame(frame)
    if not frame then return end
    local data = frameCache[frame]
    local cooldownID = data and data.cooldownID
    if cooldownID then
        local frames = framesByCooldownID[cooldownID]
        if frames then
            frames[frame] = nil
            if not next(frames) then
                framesByCooldownID[cooldownID] = nil
            end
        end
    end
    frameCache[frame] = nil
end

function Compat:FindFrameByCooldownID(cooldownID, preferBar)
    if not self:IsUsableID(cooldownID) then return nil end
    local frames = framesByCooldownID[cooldownID]
    if not frames then return nil end

    local activeBar, activeIcon, inactiveBar, inactiveIcon
    for frame in pairs(frames) do
        local data = frameCache[frame]
        if data and data.cooldownID == cooldownID then
            local isBar = frame.Bar ~= nil
            local isActive = self:GetFrameActiveState(frame) == true

            if isBar then
                if isActive then activeBar = frame else inactiveBar = inactiveBar or frame end
            else
                if isActive then activeIcon = frame else inactiveIcon = inactiveIcon or frame end
            end
        else
            frames[frame] = nil
        end
    end

    if not next(frames) then
        framesByCooldownID[cooldownID] = nil
    end
    if preferBar then
        return activeBar or activeIcon or inactiveBar or inactiveIcon
    end
    return activeIcon or activeBar or inactiveIcon or inactiveBar
end

function Compat:TrackViewerPool(viewer)
    local pool = viewer and viewer.itemFramePool
    if not pool or hookedPools[pool] or type(pool.Release) ~= "function" then return end
    hookedPools[pool] = true
    hooksecurefunc(pool, "Release", function(_, frame)
        Compat:ForgetFrame(frame)
    end)
end

function Compat:GetFrameCooldownID(frame)
    if not frame then return nil end

    local function Accept(value)
        if Compat:IsUsableID(value) then
            return Compat:RememberFrame(frame, value)
        end
        return nil
    end

    if type(frame.GetCooldownID) == "function" then
        local ok, value = pcall(frame.GetCooldownID, frame)
        if ok then
            local cooldownID = Accept(value)
            if cooldownID then return cooldownID end
        end
    end

    local cooldownID = Accept(frame.cooldownID)
    if cooldownID then return cooldownID end

    local info = frame.cooldownInfo
    if not IsSecret(info) and type(info) == "table" then
        cooldownID = Accept(info.cooldownID)
        if cooldownID then return cooldownID end
    end

    local data = frameCache[frame]
    -- CDM rebuilds can expose nil or secret IDs for a frame briefly. The pool
    -- release hook is the authoritative end of this cached frame identity.
    return data and data.cooldownID or nil
end

function Compat:GetFrameCooldownInfo(frame)
    if not frame then return nil end
    local cooldownID = self:GetFrameCooldownID(frame)
    local rawInfo

    if type(frame.GetCooldownInfo) == "function" then
        local ok, value = pcall(frame.GetCooldownInfo, frame)
        if ok and not IsSecret(value) and type(value) == "table" then
            rawInfo = value
        end
    end
    local frameInfo = frame.cooldownInfo
    if not rawInfo and not IsSecret(frameInfo) and type(frameInfo) == "table" then
        rawInfo = frameInfo
    end

    local cleanInfo = CopyPublicInfo(rawInfo, cooldownID)
    if cooldownID and cleanInfo then
        cooldownInfoCache[cooldownID] = MergeInfo(cooldownInfoCache[cooldownID], cleanInfo)
        return cooldownInfoCache[cooldownID]
    end
    return cleanInfo or self:GetCooldownInfo(cooldownID)
end

function Compat:ResolveFrameSpellID(frame)
    if not frame then return nil end
    local cooldownID = self:GetFrameCooldownID(frame)
    local data = frameCache[frame]

    local function Accept(spellID)
        if not Compat:IsUsableID(spellID) then return nil end
        if not data then
            data = {}
            frameCache[frame] = data
        end
        data.cooldownID = cooldownID or data.cooldownID
        data.spellID = spellID
        if cooldownID then
            spellIDCache[cooldownID] = spellID
        end
        return spellID
    end

    if type(frame.GetSpellID) == "function" then
        local ok, spellID = pcall(frame.GetSpellID, frame)
        if ok then
            spellID = Accept(spellID)
            if spellID then return spellID end
        end
    end

    if type(frame.GetAuraSpellID) == "function" then
        local ok, spellID = pcall(frame.GetAuraSpellID, frame)
        if ok then
            spellID = Accept(spellID)
            if spellID then return spellID end
        end
    end

    if data and self:IsUsableID(data.spellID) then
        return data.spellID
    end
    if cooldownID and self:IsUsableID(spellIDCache[cooldownID]) then
        return spellIDCache[cooldownID]
    end

    local spellID = self:ResolveInfoSpellID(self:GetFrameCooldownInfo(frame))
    if not spellID and cooldownID then
        spellID = self:ResolveInfoSpellID(self:GetCooldownInfo(cooldownID))
    end
    return Accept(spellID)
end

function Compat:GetGroupBuffItems(forceRefresh)
    if groupBuffItemsCache and not forceRefresh then
        return groupBuffItemsCache
    end

    local api = C_CooldownViewer and C_CooldownViewer.GetGroupBuffItems
    if type(api) ~= "function" then
        return groupBuffItemsCache or {}
    end

    local ok, rawItems = pcall(api)
    if not ok or IsSecret(rawItems) or type(rawItems) ~= "table" then
        return groupBuffItemsCache or {}
    end

    local items = {}
    for _, rawItem in ipairs(rawItems) do
        if not IsSecret(rawItem) and type(rawItem) == "table" and self:IsUsableID(rawItem.spellID) then
            local item = { spellID = rawItem.spellID }
            if self:IsPublicString(rawItem.name) then item.name = rawItem.name end
            if self:IsPublicNumber(rawItem.iconID) then item.iconID = rawItem.iconID end
            if self:IsPublicNumber(rawItem.flags) then item.flags = rawItem.flags end
            if not IsSecret(rawItem.isKnown) and type(rawItem.isKnown) == "boolean" then
                item.isKnown = rawItem.isKnown
            end
            items[#items + 1] = item
        end
    end
    groupBuffItemsCache = items
    return items
end

function Compat:IsSettingsOpen()
    local settings = _G.CooldownViewerSettings
    return settings and type(settings.IsShown) == "function" and settings:IsShown() or false
end

function Compat:GetGeneration()
    return generation
end

function Compat:Invalidate()
    generation = generation + 1
    wipe(cooldownInfoCache)
    wipe(categorySetCache)
    wipe(categoryLookupCache)
    wipe(spellIDCache)
    wipe(spellIdentityCache)
    categoryDefinitionsCache = nil
    -- Frame IDs stay valid until pool release. Keep their last public values so
    -- a data update during combat cannot erase the only readable identity.
    groupBuffItemsCache = nil
    hiddenGroupBuffSpellSetCache = nil
    hiddenGroupBuffSpellSetReady = false
end
