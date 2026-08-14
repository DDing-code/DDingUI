--[[
    DDingToolKit - BuffReminder: Consumable Memory
    Tracks which consumable the player last used per spec.
    Ported from BuffReminders by zerbi.
]]

local _, ns = ...

local GetItemSpell = GetItemSpell

-- ============================================================================
-- FLEETING FLASK DETECTION
-- ============================================================================

local function IsFleetingItem(itemID)
    return ns.FLEETING_FLASK_ITEMS and ns.FLEETING_FLASK_ITEMS[itemID] or false
end

local fleetingSpellIDs = nil

local function IsFleetingSpell(spellID)
    if not fleetingSpellIDs then
        fleetingSpellIDs = {}
        for itemID in pairs(ns.FLEETING_FLASK_ITEMS or {}) do
            local ok, _, sid = pcall(GetItemSpell, itemID)
            if ok and sid then
                fleetingSpellIDs[sid] = true
            end
        end
    end
    return fleetingSpellIDs[spellID] or false
end

-- ============================================================================
-- REMEMBER / READ
-- ============================================================================

local function Remember(specId, category, spellID, updateOnly)
    if not specId or not category or not spellID then
        return
    end
    local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
    if not db then return end

    local mem = db.rememberedConsumables
    -- Fast path: already remembered
    if mem and mem[specId] and mem[specId][category] == spellID then
        return
    end
    -- updateOnly mode: only overwrite existing entry
    if updateOnly and not (mem and mem[specId] and mem[specId][category]) then
        return
    end
    if not mem then
        mem = {}
        db.rememberedConsumables = mem
    end
    if not mem[specId] then
        mem[specId] = {}
    end
    mem[specId][category] = spellID
end

local function GetRemembered(specId, category)
    if not specId then
        return nil
    end
    local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
    if not db then return nil end
    local mem = db.rememberedConsumables
    return mem and mem[specId] and mem[specId][category]
end

-- ============================================================================
-- CLICK-TO-CAST REMEMBER (PostClick path)
-- ============================================================================

local function RememberChoice(itemID, buffFrame)
    if not itemID or not buffFrame or buffFrame.buffCategory ~= "consumable" then
        return
    end
    if IsFleetingItem(itemID) then
        return
    end
    local ok, _, useSpellID = pcall(GetItemSpell, itemID)
    if not ok or not useSpellID then
        return
    end
    local resolvedFrame = buffFrame.mainFrame or buffFrame
    local cat = ns.BUFF_KEY_TO_CATEGORY and ns.BUFF_KEY_TO_CATEGORY[resolvedFrame.key]
    local specIndex = GetSpecialization()
    local specId = specIndex and GetSpecializationInfo(specIndex)
    if not cat or not specId then
        return
    end
    Remember(specId, cat, useSpellID)
end

-- ============================================================================
-- COUNT-DELTA TRACKING
-- ============================================================================

local previousCounts = {}

local function DetectConsumedItems(buckets, specId)
    if not specId then
        return
    end
    local isEating = ns.BuffState and ns.BuffState.IsPlayerEating and ns.BuffState.IsPlayerEating()
    for category, oldItems in pairs(previousCounts) do
        if category == "food" or category == "weapon" then
            for itemID, old in pairs(oldItems) do
                if old.useSpellID then
                    local newBucket = buckets[category] and buckets[category][itemID]
                    local newCount = newBucket and newBucket.count or 0
                    if newCount < old.count then
                        if category ~= "food" or isEating then
                            Remember(specId, category, old.useSpellID)
                        end
                    end
                end
            end
        end
    end
end

local function SnapshotCounts(buckets)
    for category, catTable in pairs(previousCounts) do
        if not buckets[category] then
            previousCounts[category] = nil
        else
            wipe(catTable)
        end
    end
    for category, entries in pairs(buckets) do
        if not previousCounts[category] then
            previousCounts[category] = {}
        end
        local catTable = previousCounts[category]
        for itemID, item in pairs(entries) do
            local prev = catTable[itemID]
            if prev then
                prev.count = item.count
                prev.useSpellID = item.useSpellID
            else
                catTable[itemID] = { count = item.count, useSpellID = item.useSpellID }
            end
        end
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

ns.ConsumableMemory = {
    Remember = Remember,
    GetRemembered = GetRemembered,
    IsFleetingSpell = IsFleetingSpell,
    IsFleetingItem = IsFleetingItem,
    RememberChoice = RememberChoice,
    DetectConsumedItems = DetectConsumedItems,
    SnapshotCounts = SnapshotCounts,
}

-- Backward compatibility alias
ns.BuffMemory = ns.ConsumableMemory
