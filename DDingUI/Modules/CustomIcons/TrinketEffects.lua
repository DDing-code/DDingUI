local _, ns = ...
local DDingUI = ns and (ns.Addon or ns.DDingUI)
if not DDingUI then return end

local TrinketEffects = {}
DDingUI.TrinketEffects = TrinketEffects

local specsByKey = {}
local specsBySpell = {}
local specsByItem = {}
local states = {}
local eventFrame
local effectEventsRegistered = false
local normalizeQueued = false
local purgeQueued = false

local function IsPublicNumber(value)
    if type(value) ~= "number" then return false end
    return not (issecretvalue and issecretvalue(value))
end

local function Register(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" then return end
    specsByKey[spec.key] = spec
    if IsPublicNumber(spec.spellID) then
        specsBySpell[spec.spellID] = spec
    end
    if type(spec.spellMap) == "table" then
        for spellID in pairs(spec.spellMap) do
            if IsPublicNumber(spellID) then
                specsBySpell[spellID] = spec
            end
        end
    end
    if IsPublicNumber(spec.itemID) then
        specsByItem[spec.itemID] = specsByItem[spec.itemID] or {}
        specsByItem[spec.itemID][#specsByItem[spec.itemID] + 1] = spec
    end
end

Register({
    key = "trinket_249343_a", spellID = 1266686, itemID = 249343,
    iconID = 7636702, duration = 12, mode = "extend",
    inheritCapRatio = 0.30, trigger = "cooldown_update", requireEquipped = true,
})
Register({
    key = "trinket_249343_b", spellID = 1266687, itemID = 249343,
    iconID = 2032577, duration = 12, mode = "stack_decay",
    trigger = "cooldown_update", requireEquipped = true,
})
Register({
    key = "trinket_249344", spellID = 1259633, itemID = 249344,
    iconID = 7636709, duration = 15, cooldown = 90, mode = "active_cooldown",
    trigger = "spell_success", requireEquipped = true,
})
Register({
    key = "trinket_249339", spellID = 1260633, itemID = 249339,
    iconID = 7636711, duration = 1, cooldown = 120, mode = "active_cooldown",
    trigger = "spell_success", requireEquipped = true,
})
Register({
    key = "trinket_249346", spellID = 1260459, itemID = 249346,
    iconID = 7636706, duration = 15, cooldown = 90, mode = "active_cooldown",
    trigger = "spell_success", requireEquipped = true,
})
Register({
    key = "trinket_193701", spellID = 383781, itemID = 193701,
    iconID = 133876, duration = 20, cooldown = 120, mode = "active_cooldown",
    trigger = "spell_success", requireEquipped = true,
})
Register({
    key = "trinket_250256", spellID = 1263318, itemID = 250256,
    iconID = 4644003, duration = 10, mode = "refresh",
    trigger = "cooldown_update", requireEquipped = true,
})
Register({
    key = "trinket_249808", spellID = 1258283, itemID = 249808,
    iconID = 7636705, duration = 30, cooldown = 90, mode = "active_cooldown",
    trigger = "spell_success", requireEquipped = true,
})
Register({
    key = "trinket_1302265", displaySpellID = 1302265,
    spellMap = {
        [1287770] = { iconID = 236313 },
        [1287771] = { iconID = 464604 },
        [1287774] = { iconID = 135788 },
        [1287772] = { iconID = 1033914 },
    },
    duration = 10, mode = "stack_decay", trigger = "cooldown_update",
})

local function IsEquipped(spec)
    if spec.requireEquipped ~= true or not spec.itemID then return true end
    if C_Item and C_Item.IsEquippedItem then
        local ok, equipped = pcall(C_Item.IsEquippedItem, spec.itemID)
        if ok then return equipped == true end
    end
    return GetInventoryItemID("player", 13) == spec.itemID
        or GetInventoryItemID("player", 14) == spec.itemID
end

local function ResolveIcon(spec, triggerSpellID)
    local mapped = spec.spellMap and triggerSpellID and spec.spellMap[triggerSpellID]
    if mapped and mapped.iconID then return mapped.iconID end
    if spec.iconID then return spec.iconID end
    local spellID = spec.displaySpellID or spec.spellID or triggerSpellID
    return spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
end

local function Publish(spec, state, duration, triggerSpellID)
    local customIcons = DDingUI.CustomIcons
    if not customIcons or not customIcons.ActivateExternalTimedAura then return end
    local stateID = spec.displaySpellID or spec.spellID or triggerSpellID
    if not stateID then return end
    customIcons:ActivateExternalTimedAura(
        stateID,
        duration,
        ResolveIcon(spec, triggerSpellID),
        state.stacks,
        state.startedAt
    )
end

local function PruneStacks(state, now)
    local kept = {}
    for _, expiration in ipairs(state.stackExpiries or {}) do
        if expiration > now then kept[#kept + 1] = expiration end
    end
    state.stackExpiries = kept
    state.stacks = #kept
end

local function RefreshStackState(spec)
    local state = states[spec.key]
    if not state then return end
    local now = GetTime()
    PruneStacks(state, now)
    local stateID = spec.displaySpellID or spec.spellID
    if state.stacks == 0 then
        states[spec.key] = nil
        if DDingUI.CustomIcons and DDingUI.CustomIcons.DeactivateExternalTimedAura and stateID then
            DDingUI.CustomIcons:DeactivateExternalTimedAura(stateID)
        end
        return
    end
    local latest = state.stackExpiries[#state.stackExpiries]
    local duration = math.max(0.05, latest - now)
    state.startedAt = now
    Publish(spec, state, duration, state.triggerSpellID)
end

local function Trigger(spec, triggerSpellID)
    if not spec or not IsEquipped(spec) then return end
    local now = GetTime()
    local baseDuration = tonumber(spec.duration) or 0
    if baseDuration <= 0 then return end

    local state = states[spec.key] or { stackExpiries = {}, stacks = 0 }
    states[spec.key] = state
    state.triggerSpellID = triggerSpellID

    local duration = baseDuration
    if spec.mode == "stack_decay" then
        PruneStacks(state, now)
        state.stackExpiries[#state.stackExpiries + 1] = now + baseDuration
        state.stacks = #state.stackExpiries
        C_Timer.After(baseDuration + 0.05, function() RefreshStackState(spec) end)
    elseif spec.mode == "extend" then
        local remaining = math.max(0, (state.expiresAt or 0) - now)
        local cap = tonumber(spec.inheritCapSeconds) or (baseDuration * (tonumber(spec.inheritCapRatio) or 0))
        duration = baseDuration + math.min(remaining, cap)
        state.stacks = 0
    else
        state.stacks = 0
    end

    state.startedAt = now
    state.expiresAt = now + duration
    Publish(spec, state, duration, triggerSpellID)
end

function TrinketEffects:GetEffectsForItem(itemID)
    itemID = tonumber(itemID)
    return itemID and specsByItem[itemID] or nil
end

function TrinketEffects:GetActiveEffectForItem(itemID)
    local now = GetTime()
    local best
    for _, spec in ipairs(self:GetEffectsForItem(itemID) or {}) do
        local state = states[spec.key]
        local expirationTime = state and tonumber(state.expiresAt)
        if expirationTime and expirationTime > now
            and (not best or expirationTime > best.expirationTime)
        then
            local startTime = tonumber(state.startedAt) or now
            best = {
                key = spec.key,
                spellID = spec.displaySpellID or spec.spellID,
                iconTexture = ResolveIcon(spec, state.triggerSpellID),
                startTime = startTime,
                duration = expirationTime - startTime,
                expirationTime = expirationTime,
                stacks = tonumber(state.stacks) or 0,
            }
        end
    end
    return best
end

function TrinketEffects:BuildAuraPayloads(itemID)
    local result = {}
    for _, spec in ipairs(self:GetEffectsForItem(itemID) or {}) do
        local stateID = spec.displaySpellID or spec.spellID
        if stateID then
            result[#result + 1] = {
                type = "aura",
                id = stateID,
                settings = {
                    customAuraStateID = stateID,
                    customAuraDuration = spec.duration,
                    customAuraTrigger = "trinket_effect",
                    iconTexture = ResolveIcon(spec),
                    fallbackIcon = ResolveIcon(spec),
                    trinketEffectKey = spec.key,
                    trinketItemID = spec.itemID,
                },
            }
        end
    end
    return result
end

local function NormalizeSavedEffectIcons()
    local profile = DDingUI.db and DDingUI.db.profile
    local dynamicIcons = profile and profile.dynamicIcons
    local changed = false
    for _, iconData in pairs((dynamicIcons and dynamicIcons.iconData) or {}) do
        local settings = iconData and iconData.settings
        local spec = settings and specsByKey[settings.trinketEffectKey]
        if iconData and iconData.type == "aura" and spec then
            local stateID = spec.displaySpellID or spec.spellID
            local texture = ResolveIcon(spec)
            if stateID and iconData.id ~= stateID then
                iconData.id = stateID
                changed = true
            end
            if texture and settings.iconTexture ~= texture then
                settings.iconTexture = texture
                changed = true
            end
            if texture and settings.fallbackIcon ~= texture then
                settings.fallbackIcon = texture
                changed = true
            end
            if settings.customAuraStateID ~= stateID
                or settings.customAuraDuration ~= spec.duration
                or settings.customAuraTrigger ~= "trinket_effect"
            then
                settings.customAuraStateID = stateID
                settings.customAuraDuration = spec.duration
                settings.customAuraTrigger = "trinket_effect"
                changed = true
            end
        end
    end

    if changed and DDingUI.CustomIcons and DDingUI.CustomIcons.LoadDynamicIcons then
        DDingUI.CustomIcons:LoadDynamicIcons()
    end
end

local function PurgeUnequippedStates()
    local customIcons = DDingUI.CustomIcons
    for key, state in pairs(states) do
        local spec = specsByKey[key]
        if spec and not IsEquipped(spec) then
            states[key] = nil
            local stateID = spec.displaySpellID or spec.spellID or (state and state.triggerSpellID)
            if stateID and customIcons and customIcons.DeactivateExternalTimedAura then
                customIcons:DeactivateExternalTimedAura(stateID)
            end
        end
    end
end

local function HasTrackedEffectIcons()
    local profile = DDingUI.db and DDingUI.db.profile
    local dynamicIcons = profile and profile.dynamicIcons
    for _, iconData in pairs((dynamicIcons and dynamicIcons.iconData) or {}) do
        local settings = iconData and iconData.settings
        if iconData and iconData.type == "trinketProc" then
            return true
        end
        if settings and (
            settings.trackTrinketEffect == true
            or specsByKey[settings.trinketEffectKey] ~= nil
        ) then
            return true
        end
    end
    return false
end

function TrinketEffects:RefreshEventRegistration()
    local enabled = HasTrackedEffectIcons()
    if enabled == effectEventsRegistered then return end
    effectEventsRegistered = enabled
    if enabled then
        eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    else
        eventFrame:UnregisterAllEvents()
    end
end

local function QueueNormalizeSavedEffects()
    if normalizeQueued then return end
    normalizeQueued = true
    C_Timer.After(0, function()
        normalizeQueued = false
        NormalizeSavedEffectIcons()
        TrinketEffects:RefreshEventRegistration()
    end)
end

local function QueuePurgeUnequippedStates()
    if purgeQueued then return end
    purgeQueued = true
    C_Timer.After(0, function()
        purgeQueued = false
        PurgeUnequippedStates()
    end)
end

eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        QueueNormalizeSavedEffects()
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
        QueuePurgeUnequippedStates()
        return
    end
    local spellID, baseSpellID
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit
        unit, _, spellID = ...
        if unit ~= "player" or not IsPublicNumber(spellID) then return end
    else
        spellID, baseSpellID = ...
        if not IsPublicNumber(spellID) then spellID = nil end
        if not IsPublicNumber(baseSpellID) then baseSpellID = nil end
        if not spellID and not baseSpellID then return end
    end

    local spec = (spellID and specsBySpell[spellID]) or (baseSpellID and specsBySpell[baseSpellID])
    if not spec then return end
    local expected = event == "UNIT_SPELLCAST_SUCCEEDED" and "spell_success" or "cooldown_update"
    if spec.trigger ~= expected then return end
    Trigger(spec, spellID or baseSpellID)
end)

local function RefreshEffectEvents()
    TrinketEffects:RefreshEventRegistration()
end

if DDingUI.CustomIcons and hooksecurefunc then
    hooksecurefunc(DDingUI.CustomIcons, "AddDynamicIcon", RefreshEffectEvents)
    hooksecurefunc(DDingUI.CustomIcons, "RemoveDynamicIcon", RefreshEffectEvents)
    hooksecurefunc(DDingUI.CustomIcons, "RemoveGroup", RefreshEffectEvents)
    hooksecurefunc(DDingUI.CustomIcons, "LoadDynamicIcons", RefreshEffectEvents)
end

QueueNormalizeSavedEffects()
