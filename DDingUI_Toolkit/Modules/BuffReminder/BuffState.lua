--[[
    DDingToolKit - BuffReminder: BuffState (State Engine)
    Full lifecycle state engine with content visibility, aura restriction,
    group scanning, and 7-category buff state computation.
    Ported from BuffReminders/Core/State.lua by zerbi.
]]

local _, ns = ...

local BuffState = {}
ns.BuffState = BuffState

-- ============================================================================
-- UPVALUES & CACHES
-- ============================================================================

local GetTime = GetTime
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local IsPlayerSpell = IsPlayerSpell
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local IsMounted = IsMounted
local UnitIsUnit = UnitIsUnit
local GetInstanceInfo = GetInstanceInfo
local pcall = pcall
local type = type
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert
local wipe = wipe
local floor = math.floor
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemID = GetInventoryItemID
local GetItemInfoInstant = GetItemInfoInstant
local GetUnitName = GetUnitName
local UnitIsPlayer = UnitIsPlayer
local C_UnitAuras = C_UnitAuras

local _, playerClass = UnitClass("player")

-- Buff table references
local RaidBuffs, PresenceBuffs, TargetedBuffs, SelfBuffs, PetBuffs, Consumables, CustomBuffs
local BuffBeneficiaries, SpecBeneficiaries
local COMBAT_SAFE_SPELLS

-- State flags
local inCombat = false
local inReadyCheck = false
local inInstanceEntry = false
local inDelveEntry = false
local inVehicle = false
local inPvPPrepPhase = false
local consumablesDismissed = false
local includeNPCsInCounting = false

-- Caches
local cachedContentType = nil
local cachedInstanceType = nil
local cachedDifficultyKey = nil
local cachedCompetitivePvP = nil
local cachedIsLegacyInstance = nil
local cachedSpecId = nil
local cachedPlayerRole = nil
local cachedOffHandType = nil
local cachedSpellKnowledge = {}
local cachedItemOwnership = {}
local allySpecCache = {}
local lastTargets = {}

-- Valid unit cache (rebuilt each Refresh cycle)
local currentValidUnits = {}

-- Weapon enchant state (fetched once per Refresh cycle)
local currentWeaponEnchants = {
    hasMainHand = false, mainHandID = nil, mainHandExpiration = nil,
    hasOffHand = false, offHandID = nil, offHandExpiration = nil,
    permanentMH = nil, permanentOH = nil,
}

-- Entry storage
BuffState.entries = {}
BuffState.visibleByCategory = {}
BuffState.lastUpdate = 0

-- ============================================================================
-- INIT (called once after data files loaded)
-- ============================================================================

function BuffState.Init()
    local tables = ns.BUFF_TABLES
    if not tables then return end
    RaidBuffs = tables.raid or {}
    PresenceBuffs = tables.presence or {}
    TargetedBuffs = tables.targeted or {}
    SelfBuffs = tables.self or {}
    PetBuffs = tables.pet or {}
    Consumables = tables.consumable or {}
    CustomBuffs = tables.custom or {}
    BuffBeneficiaries = ns.BuffBeneficiaries or {}
    SpecBeneficiaries = ns.SpecBeneficiaries or {}
    COMBAT_SAFE_SPELLS = ns.COMBAT_SAFE_SPELLS or {}
end

-- ============================================================================
-- SPEC & SPELL HELPERS
-- ============================================================================

local function GetPlayerSpecId()
    if cachedSpecId then return cachedSpecId end
    local specIndex = GetSpecialization()
    cachedSpecId = specIndex and GetSpecializationInfo(specIndex) or nil
    return cachedSpecId
end

local function GetPlayerRole()
    if cachedPlayerRole then return cachedPlayerRole end
    local specIndex = GetSpecialization()
    if specIndex then
        local _, _, _, _, role = GetSpecializationInfo(specIndex)
        cachedPlayerRole = role
    end
    return cachedPlayerRole
end

local function IsPlayerSpellCached(spellID)
    local val = cachedSpellKnowledge[spellID]
    if val ~= nil then return val end
    local ok, result = pcall(IsPlayerSpell, spellID)
    val = ok and result == true or false
    cachedSpellKnowledge[spellID] = val
    return val
end

local function HasItemByMode(itemID, mode)
    if not itemID then return false end
    local key = itemID
    if cachedItemOwnership[key] ~= nil then return cachedItemOwnership[key] end
    local ok, count = pcall(C_Item.GetItemCount, itemID, false, true)
    local has = ok and count and count > 0
    cachedItemOwnership[key] = has
    return has
end

-- ============================================================================
-- AURA HELPERS (Combat-safe)
-- ============================================================================

--- Convert spellID field to list
local function AsSpellList(val)
    if type(val) == "table" then return val end
    return { val }
end

--- Check if a spell is on the combat-safe whitelist
local function IsAuraTrackable(buff)
    if not buff.spellID then return false end
    if type(buff.spellID) == "table" then
        for _, id in ipairs(buff.spellID) do
            if COMBAT_SAFE_SPELLS[id] then return true end
        end
        return false
    end
    return COMBAT_SAFE_SPELLS[buff.spellID] == true
end

--- Query aura on unit — combat-safe
local function UnitHasBuff(unit, spellIDs)
    local list = AsSpellList(spellIDs)
    for _, id in ipairs(list) do
        local ok, auraData = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
        if ok and auraData then
            local remaining = nil
            if auraData.expirationTime and auraData.expirationTime > 0 then
                remaining = auraData.expirationTime - GetTime()
            end
            return true, remaining, auraData.sourceUnit
        end
    end
    return false, nil, nil
end

--- Full scan for player-sourced buff
local function UnitHasBuffFromPlayer(unit, spellID)
    local i = 1
    while true do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or not auraData then break end
        if auraData.spellId == spellID and auraData.sourceUnit and UnitIsUnit(auraData.sourceUnit, "player") then
            local remaining = nil
            if auraData.expirationTime and auraData.expirationTime > 0 then
                remaining = auraData.expirationTime - GetTime()
            end
            return true, remaining
        end
        i = i + 1
    end
    return false, nil
end

-- ============================================================================
-- GROUP UNIT CACHE
-- ============================================================================

local function BuildValidUnitCache()
    wipe(currentValidUnits)
    local numMembers = GetNumGroupMembers()
    if numMembers <= 0 then
        local _, pClass = UnitClass("player")
        tinsert(currentValidUnits, {
            unit = "player",
            name = GetUnitName("player", true),
            class = pClass,
            isPlayer = true,
        })
        return
    end
    local prefix = IsInRaid() and "raid" or "party"
    local addPlayer = prefix == "party"
    if addPlayer then
        local _, pClass = UnitClass("player")
        tinsert(currentValidUnits, {
            unit = "player",
            name = GetUnitName("player", true),
            class = pClass,
            isPlayer = true,
        })
    end
    for i = 1, numMembers do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            local _, uClass = UnitClass(unit)
            tinsert(currentValidUnits, {
                unit = unit,
                name = GetUnitName(unit, true),
                class = uClass,
                isPlayer = UnitIsPlayer(unit) == true,
            })
        end
    end
    -- Determine if we should count NPCs (e.g., Brann, Valeera in delves)
    includeNPCsInCounting = ns.IsInDelve and ns.IsInDelve() or false
end

-- ============================================================================
-- CONTENT TYPE & VISIBILITY
-- ============================================================================

local CONTENT_TYPE_MAP = {
    none = "openWorld", party = "dungeon", raid = "raid",
    arena = "pvp", pvp = "pvp", scenario = "scenario",
}

local DIFFICULTY_KEY_MAP = {
    [1] = "normal", [2] = "heroic", [23] = "mythic",
    [8] = "mythicPlus", [24] = "timewalking", [205] = "follower",
    [14] = "normal", [15] = "heroic", [16] = "mythic", [17] = "lfr",
    [208] = "delves",
}
local CONTENT_DIFF_DB_KEYS = {
    dungeon = "dungeonDifficulty", raid = "raidDifficulty", scenario = "scenarioDifficulty",
}

local function GetCurrentContentType()
    if cachedContentType then return cachedContentType end
    local _, instanceType, difficultyID = GetInstanceInfo()
    cachedInstanceType = instanceType
    cachedDifficultyKey = DIFFICULTY_KEY_MAP[difficultyID]
    -- Housing detection
    if instanceType == "scenario" and difficultyID == 226 then
        cachedContentType = "housing"
    else
        cachedContentType = CONTENT_TYPE_MAP[instanceType] or "openWorld"
    end
    -- Legacy instance detection
    local expansionID = GetServerExpansionLevel and GetServerExpansionLevel() or 10
    local instanceExpansion = select(9, GetInstanceInfo())
    cachedIsLegacyInstance = instanceExpansion and instanceExpansion < expansionID - 1
    return cachedContentType
end

local function GetCurrentDifficultyKey()
    if cachedDifficultyKey == nil then GetCurrentContentType() end
    return cachedDifficultyKey
end

local function IsCategoryVisibleForContent(category, skipReadyCheck)
    local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
    if not db then return true end
    local catVis = db.categoryVisibility and db.categoryVisibility[category]
    if not catVis then return true end
    local contentType = GetCurrentContentType()
    if catVis[contentType] == false then return false end
    -- Difficulty sub-filter
    local diffKey = GetCurrentDifficultyKey()
    if diffKey then
        local diffDbKey = CONTENT_DIFF_DB_KEYS[contentType]
        local diffTable = diffDbKey and catVis[diffDbKey]
        if diffTable and diffTable[diffKey] == false then return false end
    end
    -- PvP match hiding
    if contentType == "pvp" and catVis.hideInPvPMatch and not inPvPPrepPhase then
        return false
    end
    return true
end

local function IsCustomBuffVisibleForContent(buff)
    if not buff.contentVisibility then return true end
    local contentType = GetCurrentContentType()
    return buff.contentVisibility[contentType] ~= false
end

-- ============================================================================
-- BUFF ENABLED CHECKS
-- ============================================================================

local function GetBuffSettingKey(buff)
    return buff.groupId or buff.key
end

local function IsBuffEnabled(key)
    local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
    if not db or not db.enabledBuffs then return true end
    return db.enabledBuffs[key] ~= false
end

-- ============================================================================
-- CASTER DETECTION
-- ============================================================================

local function HasCasterForBuff(requiredClass, levelRequirement)
    if not requiredClass then return true end
    for _, data in ipairs(currentValidUnits) do
        if data.class == requiredClass then
            return true
        end
    end
    return false
end

-- ============================================================================
-- BENEFICIARIES
-- ============================================================================

local function UnitBenefitsFromBuff(specBenef, classBenef, specId, class)
    if specBenef and specId then return specBenef[specId] ~= nil end
    if classBenef then return classBenef[class] ~= nil end
    return true
end

-- ============================================================================
-- TIME FORMATTING
-- ============================================================================

local function FormatRemainingTime(seconds)
    if seconds >= 3600 then return floor(seconds / 3600) .. "h" end
    if seconds >= 60 then return floor(seconds / 60) .. "m" end
    return floor(seconds) .. "s"
end

local function FormatEatingTime(seconds)
    if seconds <= 0 then return "0" end
    return string.format("%.0f", seconds)
end

-- ============================================================================
-- TRACKING SCOPE
-- ============================================================================

local SCOPE_HIDDEN = { show = false, playerOnly = false }
local SCOPE_PLAYER_ONLY = { show = true, playerOnly = true }
local SCOPE_GROUP = { show = true, playerOnly = false }

local function GetTrackingScope(trackingMode, buffClass, category, hasCaster, castOnOthers)
    if not hasCaster then return SCOPE_HIDDEN end
    if trackingMode == "my_buffs" and buffClass ~= playerClass then return SCOPE_HIDDEN end
    if trackingMode == "personal" then
        if category == "presence" and (buffClass ~= playerClass or castOnOthers) then return SCOPE_HIDDEN end
        return SCOPE_PLAYER_ONLY
    elseif trackingMode == "smart" then
        local isMyClass = buffClass == playerClass
        if category == "raid" then
            return isMyClass and SCOPE_GROUP or SCOPE_PLAYER_ONLY
        else
            return (isMyClass and not castOnOthers) and SCOPE_PLAYER_ONLY or SCOPE_GROUP
        end
    elseif trackingMode == "my_buffs" then
        if category == "presence" and not castOnOthers then
            return SCOPE_PLAYER_ONLY
        end
        return SCOPE_GROUP
    else
        return SCOPE_GROUP
    end
end

-- ============================================================================
-- BUFF STATE FUNCTIONS
-- ============================================================================

local function CountMissingBuff(spellIDs, buffKey, playerOnly)
    local missing, total, minRemaining = 0, 0, nil
    local beneficiaries = BuffBeneficiaries and BuffBeneficiaries[buffKey]
    local specBeneficiaries = SpecBeneficiaries and SpecBeneficiaries[buffKey]

    if playerOnly or #currentValidUnits <= 1 then
        if not UnitBenefitsFromBuff(specBeneficiaries, beneficiaries, GetPlayerSpecId(), playerClass) then
            return 0, 0, nil
        end
        total = 1
        local hasBuff, remaining = UnitHasBuff("player", spellIDs)
        if not hasBuff then
            missing = 1
        elseif remaining then
            minRemaining = remaining
        end
        return missing, total, minRemaining
    end

    for _, data in ipairs(currentValidUnits) do
        if data.isPlayer or (includeNPCsInCounting and not inCombat) then
            if UnitBenefitsFromBuff(specBeneficiaries, beneficiaries, allySpecCache[data.name], data.class) then
                total = total + 1
                local hasBuff, remaining = UnitHasBuff(data.unit, spellIDs)
                if not hasBuff then
                    missing = missing + 1
                elseif remaining then
                    if not minRemaining or remaining < minRemaining then
                        minRemaining = remaining
                    end
                end
            end
        end
    end
    return missing, total, minRemaining
end

local function HasPresenceBuff(spellIDs, playerOnly)
    if playerOnly or #currentValidUnits <= 1 then
        local hasBuff, remaining = UnitHasBuff("player", spellIDs)
        return hasBuff, remaining, nil
    end
    local minRemaining, found, targetEntry = nil, false, nil
    for _, data in ipairs(currentValidUnits) do
        if data.isPlayer or includeNPCsInCounting then
            local hasBuff, remaining = UnitHasBuff(data.unit, spellIDs)
            if hasBuff then
                found = true
                if not targetEntry and not UnitIsUnit(data.unit, "player") then
                    targetEntry = data
                end
                if remaining then
                    if not minRemaining or remaining < minRemaining then minRemaining = remaining end
                else
                    return true, nil, targetEntry
                end
            end
        end
    end
    return found, minRemaining, targetEntry
end

local function IsPlayerBuffActive(spellID, role)
    local minRemaining, targetEntry = nil, nil
    for _, data in ipairs(currentValidUnits) do
        if data.isPlayer or includeNPCsInCounting then
            if not role or UnitGroupRolesAssigned(data.unit) == role then
                local hasBuff, remaining, sourceUnit = UnitHasBuff(data.unit, spellID)
                if hasBuff then
                    local isFromPlayer = sourceUnit and UnitIsUnit(sourceUnit, "player")
                    if not isFromPlayer then
                        isFromPlayer, remaining = UnitHasBuffFromPlayer(data.unit, spellID)
                    end
                    if isFromPlayer then
                        if not targetEntry and not UnitIsUnit(data.unit, "player") then
                            targetEntry = data
                        end
                        if not remaining then return true, nil, targetEntry end
                        if not minRemaining or remaining < minRemaining then minRemaining = remaining end
                    end
                end
            end
        end
    end
    return minRemaining ~= nil, minRemaining, targetEntry
end

local function ShouldShowTargetedBuff(spellIDs, requiredClass, beneficiaryRole, requireSpecId, buffKey, casterBuffId)
    if playerClass ~= requiredClass then return nil end
    if requireSpecId and GetPlayerSpecId() ~= requireSpecId then return nil end
    local spellID = (type(spellIDs) == "table" and spellIDs[1] or spellIDs)
    if not IsPlayerSpellCached(spellID) then return nil end
    if GetNumGroupMembers() == 0 then return nil end

    if casterBuffId then
        local hasBuff, remaining = UnitHasBuff("player", casterBuffId)
        if buffKey and not inCombat then
            if hasBuff then
                local foundTarget = false
                for _, data in ipairs(currentValidUnits) do
                    if not UnitIsUnit(data.unit, "player") then
                        local targetHas = UnitHasBuff(data.unit, spellIDs)
                        if targetHas and data.name then
                            local existing = lastTargets[buffKey]
                            if existing then
                                existing.name = data.name; existing.class = data.class
                            else
                                lastTargets[buffKey] = { name = data.name, class = data.class }
                            end
                            foundTarget = true; break
                        end
                    end
                end
                if not foundTarget then lastTargets[buffKey] = nil end
            end
        end
        return not hasBuff, remaining
    end

    local isActive, remaining, targetEntry = IsPlayerBuffActive(spellID, beneficiaryRole)
    if buffKey then
        if targetEntry and targetEntry.name then
            local existing = lastTargets[buffKey]
            if existing then
                existing.name = targetEntry.name; existing.class = targetEntry.class
            else
                lastTargets[buffKey] = { name = targetEntry.name, class = targetEntry.class }
            end
        elseif isActive then
            lastTargets[buffKey] = nil
        end
    end
    return not isActive, remaining
end

local function ShouldShowSelfBuff(spellID, requiredClass, enchantID, requiresSpell, excludeSpell,
                                   buffIdOverride, customCheck, requireSpecId, skipSpellKnownCheck, requiresBuffWithEnchant)
    if requiredClass and playerClass ~= requiredClass then return nil end
    if requireSpecId and GetPlayerSpecId() ~= requireSpecId then return nil end
    if requiresSpell and not IsPlayerSpellCached(requiresSpell) then return nil end
    if excludeSpell and IsPlayerSpellCached(excludeSpell) then return nil end
    if customCheck then return customCheck() end
    if not skipSpellKnownCheck then
        if type(spellID) == "number" then
            if not IsPlayerSpellCached(spellID) then return nil end
        else
            local knowsAny = false
            for _, id in ipairs(spellID) do
                if IsPlayerSpellCached(id) then knowsAny = true; break end
            end
            if not knowsAny then return nil end
        end
    end
    if enchantID then
        local hasEnchant = currentWeaponEnchants.mainHandID == enchantID or currentWeaponEnchants.offHandID == enchantID
        if requiresBuffWithEnchant then
            local hasBuff = UnitHasBuff("player", buffIdOverride or spellID)
            return not (hasEnchant and hasBuff)
        end
        return not hasEnchant
    end
    local hasBuff = UnitHasBuff("player", buffIdOverride or spellID)
    return not hasBuff
end

-- ============================================================================
-- EATING STATE
-- ============================================================================

ns.EATING_AURA_ICON = 133950
local EATING_AURA_ICON = ns.EATING_AURA_ICON
local eatingAuraInstanceID = nil

local function IsPlayerEating() return eatingAuraInstanceID ~= nil end

local function ScanEatingState()
    eatingAuraInstanceID = nil
    local i = 1
    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    while ok and auraData do
        if auraData.icon == EATING_AURA_ICON then
            eatingAuraInstanceID = auraData.auraInstanceID; return
        end
        i = i + 1
        ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    end
end

local function UpdateEatingState(updateInfo)
    if not updateInfo then return end
    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            if aura.icon == EATING_AURA_ICON then
                eatingAuraInstanceID = aura.auraInstanceID; break
            end
        end
    end
    if updateInfo.removedAuraInstanceIDs and eatingAuraInstanceID then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            if id == eatingAuraInstanceID then eatingAuraInstanceID = nil; break end
        end
    end
end


local function GetEatingExpirationTime()
    if not eatingAuraInstanceID then return nil end
    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", eatingAuraInstanceID)
    if not ok or not auraData or not auraData.expirationTime or auraData.expirationTime == 0 then return nil end
    return auraData.expirationTime
end

-- ============================================================================
-- CONSUMABLE CHECKS
-- ============================================================================

local function IsFreeConsumable(buff)
    if buff.freeConsumable then return true end
    if buff.permanentRuneItemIDs then
        for _, itemID in ipairs(buff.permanentRuneItemIDs) do
            if HasItemByMode(itemID) then return true end
        end
    end
    return false
end

local function IsInCompetitivePvP()
    if cachedCompetitivePvP ~= nil then return cachedCompetitivePvP end
    local contentType = GetCurrentContentType()
    if contentType ~= "pvp" then cachedCompetitivePvP = false; return false end
    local result = cachedInstanceType == "arena" or (C_PvP.IsRatedMap and C_PvP.IsRatedMap() == true)
    cachedCompetitivePvP = result; return result
end

local function ShouldShowConsumableBuff(buff)
    if buff.spellID then
        local spellList = AsSpellList(buff.spellID)
        for _, id in ipairs(spellList) do
            local hasBuff, remaining = UnitHasBuff("player", id)
            if hasBuff then
                local CM = ns.ConsumableMemory
                if CM and buff.consumableCategory and not CM.IsFleetingSpell(id) then
                    CM.Remember(GetPlayerSpecId(), buff.consumableCategory, id, true)
                end
                return false, remaining, id
            end
        end
    end
    if buff.buffIconID then
        local i = 1
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        while ok and auraData do
            if auraData.icon == buff.buffIconID then
                local remaining = nil
                if auraData.expirationTime and auraData.expirationTime > 0 then
                    remaining = auraData.expirationTime - GetTime()
                end
                return false, remaining
            end
            i = i + 1
            ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        end
    end
    if buff.checkWeaponEnchant then
        if currentWeaponEnchants.hasMainHand then
            local remaining = currentWeaponEnchants.mainHandExpiration and (currentWeaponEnchants.mainHandExpiration / 1000) or nil
            return false, remaining
        end
    end
    if buff.checkWeaponEnchantOH then
        if currentWeaponEnchants.hasOffHand then
            local remaining = currentWeaponEnchants.offHandExpiration and (currentWeaponEnchants.offHandExpiration / 1000) or nil
            return false, remaining
        end
    end
    if buff.itemID then
        local itemList = type(buff.itemID) == "table" and buff.itemID or { buff.itemID }
        local totalCount = 0
        for _, id in ipairs(itemList) do
            local ok2, count = pcall(C_Item.GetItemCount, id, false, true)
            if ok2 and count then totalCount = totalCount + count end
        end
        if totalCount > 0 then return false, nil, nil, totalCount end
    end
    if not buff.spellID and not buff.buffIconID and not buff.checkWeaponEnchant
        and not buff.checkWeaponEnchantOH and not buff.itemID then
        return false, nil
    end
    return true, nil
end

local function PassesPreChecks(buff, presentClasses, db)
    if buff.visibilityCondition and not buff.visibilityCondition() then return false end
    if buff.readyCheckOnly and not inReadyCheck then
        local overrides = db and db.readyCheckOnlyOverrides
        local settingKey = buff.groupId or buff.key
        if not overrides or overrides[settingKey] ~= false then return false end
    end
    if buff.class then
        local trackingMode = db and db.buffTrackingMode
        if trackingMode == "my_buffs" and buff.class ~= playerClass then return false end
        if presentClasses and not presentClasses[buff.class] then return false end
    end
    if buff.excludeSpellID and IsPlayerSpellCached(buff.excludeSpellID) then return false end
    if buff.excludeIfSpellKnown then
        for _, spellID in ipairs(buff.excludeIfSpellKnown) do
            if IsPlayerSpellCached(spellID) then return false end
        end
    end
    return true
end

-- ============================================================================
-- ENTRY MANAGEMENT
-- ============================================================================

local function GetOrCreateEntry(key, category, sortOrder)
    if not BuffState.entries[key] then
        BuffState.entries[key] = {
            key = key, category = category, sortOrder = sortOrder or 0,
            visible = false, displayType = "text", shouldGlow = false,
        }
    end
    return BuffState.entries[key]
end

local function SetEntryText(entry, overlayText, glowEnabled)
    entry.visible = true
    entry.displayType = "text"
    entry.overlayText = overlayText
    entry.shouldGlow = glowEnabled
end

local function GetCategoryGlowSettings(cat)
    local Config = ns.BR_Config
    local exGlow = Config.GetCategorySetting(cat, "showExpirationGlow") ~= false
    local missGlow = Config.GetCategorySetting(cat, "showMissingGlow") ~= false
    local threshold = (Config.GetCategorySetting(cat, "expirationThreshold") or 15) * 60
    return exGlow, missGlow, threshold
end

local function TrySetEntryExpiring(entry, remaining, threshold, shouldGlow)
    if remaining and remaining < threshold then
        entry.visible = true
        entry.displayType = "expiring"
        entry.expiringTime = remaining
        entry.countText = FormatRemainingTime(remaining)
        entry.shouldGlow = shouldGlow
        return true
    end
    return false
end

-- ============================================================================
-- MAIN REFRESH
-- ============================================================================

function BuffState.Refresh()
    local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
    if not db then return end
    if not RaidBuffs then BuffState.Init() end

    -- Reset entries
    for _, entry in pairs(BuffState.entries) do
        entry.visible = false; entry.shouldGlow = false
        entry.countText = nil; entry.overlayText = nil
        entry.expiringTime = nil; entry.isEating = nil
        entry.eatingExpirationTime = nil; entry.petActions = nil
        entry.dynamicIcon = nil; entry.glowKindOverride = nil
    end

    BuildValidUnitCache()

    -- Weapon enchants
    local hasMain, mainExp, _, mainID, hasOff, offExp, _, offID = GetWeaponEnchantInfo()
    currentWeaponEnchants.hasMainHand = hasMain or false
    currentWeaponEnchants.mainHandID = mainID
    currentWeaponEnchants.mainHandExpiration = mainExp
    currentWeaponEnchants.hasOffHand = hasOff or false
    currentWeaponEnchants.offHandID = offID
    currentWeaponEnchants.offHandExpiration = offExp
    local mhLink = GetInventoryItemLink("player", 16)
    currentWeaponEnchants.permanentMH = mhLink and tonumber(mhLink:match("item:%d+:(%d+)")) or nil
    local ohLink = GetInventoryItemLink("player", 17)
    currentWeaponEnchants.permanentOH = ohLink and tonumber(ohLink:match("item:%d+:(%d+)")) or nil

    local trackingMode = db.buffTrackingMode
    local missingCountOnly = db.showMissingCountOnly
    local isAuraRestricted = BuffState.IsRestricted()
    local hideExpiring = isAuraRestricted and db.hideExpiringInCombat ~= false

    -- ========================================================================
    -- RAID BUFFS
    -- ========================================================================
    local raidVisible = IsCategoryVisibleForContent("raid")
    local raidExGlow, raidMissGlow, raidThreshold = GetCategoryGlowSettings("raid")
    for i, buff in ipairs(RaidBuffs) do
        local entry = GetOrCreateEntry(buff.key, "raid", i)
        local scope = GetTrackingScope(trackingMode, buff.class, "raid", HasCasterForBuff(buff.class, buff.levelRequired))
        if IsBuffEnabled(buff.key) and raidVisible and scope.show then
            local missing, total, minRemaining = CountMissingBuff(buff.spellID, buff.key, scope.playerOnly)
            if missing > 0 then
                entry.visible = true; entry.displayType = "count"
                local buffed = total - missing
                entry.countText = scope.playerOnly and ""
                    or (missingCountOnly and tostring(missing) or (buffed .. "/" .. total))
                entry.shouldGlow = raidMissGlow
                if minRemaining and minRemaining < raidThreshold then entry.expiringTime = minRemaining end
            elseif not hideExpiring then
                TrySetEntryExpiring(entry, minRemaining, raidThreshold, raidExGlow)
            end
        end
    end

    -- ========================================================================
    -- SELF BUFFS (before presence for suppressedByEntry)
    -- ========================================================================
    local selfVisible = IsCategoryVisibleForContent("self")
    local selfExGlow, selfMissGlow, selfThreshold = GetCategoryGlowSettings("self")
    for i, buff in ipairs(SelfBuffs) do
        local entry = GetOrCreateEntry(buff.key, "self", i)
        local settingKey = buff.groupId or buff.key
        if buff.showOnInstanceEntry then
            if inInstanceEntry and selfVisible
                and (not buff.class or buff.class == playerClass)
                and IsBuffEnabled(settingKey)
                and (not buff.customCheck or buff.customCheck(isAuraRestricted)) then
                SetEntryText(entry, buff.overlayText, selfMissGlow)
            end
        else
            if selfVisible and IsBuffEnabled(settingKey) then
                local trackable = IsAuraTrackable(buff)
                if not isAuraRestricted or trackable then
                    local shouldShow = ShouldShowSelfBuff(
                        buff.spellID, buff.class, buff.enchantID,
                        buff.requiresSpellID, buff.excludeSpellID,
                        buff.buffIdOverride, buff.customCheck,
                        buff.requireSpecId, nil, buff.requiresBuffWithEnchant)
                    local wantPresent = buff.showWhenPresent
                    local show = (wantPresent and shouldShow == false) or (not wantPresent and shouldShow)
                    if show then
                        SetEntryText(entry, buff.overlayText, selfMissGlow)
                        entry.iconByRole = buff.iconByRole
                        if buff.getNextCastID then
                            local castID = buff.getNextCastID()
                            entry.dynamicIcon = castID and C_Spell.GetSpellTexture(castID)
                        end
                        if not entry.dynamicIcon and buff.getDynamicIcon then
                            entry.dynamicIcon = buff.getDynamicIcon()
                        end
                    elseif shouldShow == false and not wantPresent and not buff.enchantID
                        and not buff.noExpirationGlow and not hideExpiring then
                        local remaining
                        if buff.getExpirationInfo then
                            remaining = buff.getExpirationInfo()
                        elseif buff.buffIdOverride or buff.spellID then
                            _, remaining = UnitHasBuff("player", buff.buffIdOverride or buff.spellID)
                        end
                        TrySetEntryExpiring(entry, remaining, selfThreshold, selfExGlow)
                    end
                end
            end
        end
    end

    -- ========================================================================
    -- PRESENCE BUFFS
    -- ========================================================================
    local presenceVisible = IsCategoryVisibleForContent("presence")
    local presExGlow, presMissGlow, presThreshold = GetCategoryGlowSettings("presence")
    for i, buff in ipairs(PresenceBuffs) do
        local entry = GetOrCreateEntry(buff.key, "presence", i)
        local suppressed = false
        if buff.suppressedByEntry then
            local suppressor = BuffState.entries[buff.suppressedByEntry]
            suppressed = suppressor and suppressor.visible
        end
        if not suppressed then
            local scope = GetTrackingScope(trackingMode, buff.class, "presence",
                HasCasterForBuff(buff.class, buff.levelRequired), buff.castOnOthers)
            local readyCheckOk = not buff.readyCheckOnly or inReadyCheck
            if buff.key == "soulstone" and not readyCheckOk then
                local ssMode = db.defaults and db.defaults.soulstoneVisibility or "readyCheck"
                if ssMode == "always" then readyCheckOk = true
                elseif ssMode == "casterOnly" then readyCheckOk = playerClass == "WARLOCK" end
            end
            if not readyCheckOk then
                local overrides = db.readyCheckOnlyOverrides
                local overrideKey = buff.groupId or buff.key
                readyCheckOk = overrides and overrides[overrideKey] == false
            end
            local showBuff = presenceVisible and readyCheckOk and scope.show
                and (not buff.groupOnly or #currentValidUnits > 1)
            if showBuff and IsBuffEnabled(buff.key) then
                local trackable = IsAuraTrackable(buff)
                if not isAuraRestricted or trackable then
                    local hasBuff, minRemaining, targetEntry = HasPresenceBuff(buff.spellID, scope.playerOnly)
                    local customOk = true
                    if not hasBuff and buff.customCheck then
                        local result = buff.customCheck(isAuraRestricted)
                        if result == false then customOk = false end
                    end
                    if not hasBuff and customOk then
                        SetEntryText(entry, buff.overlayText, presMissGlow)
                    elseif not buff.noExpirationGlow and not hideExpiring then
                        TrySetEntryExpiring(entry, minRemaining, presThreshold, presExGlow)
                    end
                    if buff.castOnOthers and hasBuff and not inCombat then
                        if targetEntry and targetEntry.name then
                            local existing = lastTargets[buff.key]
                            if existing then
                                existing.name = targetEntry.name; existing.class = targetEntry.class
                            else
                                lastTargets[buff.key] = { name = targetEntry.name, class = targetEntry.class }
                            end
                        else
                            lastTargets[buff.key] = nil
                        end
                    end
                end
            end
        end
    end

    -- ========================================================================
    -- TARGETED BUFFS
    -- ========================================================================
    local targetedVisible = IsCategoryVisibleForContent("targeted")
    local targExGlow, targMissGlow, targThreshold = GetCategoryGlowSettings("targeted")
    for i, buff in ipairs(TargetedBuffs) do
        local entry = GetOrCreateEntry(buff.key, "targeted", i)
        local settingKey = GetBuffSettingKey(buff)
        if targetedVisible and IsBuffEnabled(settingKey) then
            local trackable = IsAuraTrackable(buff)
            if (not isAuraRestricted or trackable) and PassesPreChecks(buff, nil, db) then
                local shouldShow, remaining = ShouldShowTargetedBuff(
                    buff.spellID, buff.class, buff.beneficiaryRole,
                    buff.requireSpecId, buff.key, buff.casterBuffId)
                if shouldShow then
                    SetEntryText(entry, buff.overlayText, targMissGlow)
                elseif shouldShow == false and not hideExpiring then
                    TrySetEntryExpiring(entry, remaining, targThreshold, targExGlow)
                end
            end
        end
    end

    -- ========================================================================
    -- PET BUFFS
    -- ========================================================================
    local petVisible = IsCategoryVisibleForContent("pet")
    if IsMounted() then petVisible = false end
    local petPassiveHidden = db.petPassiveOnlyInCombat and not UnitAffectingCombat("player")
    local _, petMissGlow = GetCategoryGlowSettings("pet")
    for i, buff in ipairs(PetBuffs) do
        local entry = GetOrCreateEntry(buff.key, "pet", i)
        local settingKey = buff.groupId or buff.key
        if IsBuffEnabled(settingKey) and petVisible and not (buff.key == "petPassive" and petPassiveHidden) then
            local shouldShow = ShouldShowSelfBuff(
                buff.spellID, buff.class, buff.enchantID,
                buff.requiresSpellID, buff.excludeSpellID,
                buff.buffIdOverride, buff.customCheck,
                buff.requireSpecId, nil, buff.requiresBuffWithEnchant)
            if shouldShow then
                SetEntryText(entry, buff.overlayText, petMissGlow)
                entry.iconByRole = buff.iconByRole
                if buff.getPetActions then
                    local actions = buff.getPetActions()
                    if actions and #actions > 0 then entry.petActions = actions end
                elseif buff.groupId == "pets" and ns.PetHelpers then
                    local actions = ns.PetHelpers.GetPetActions(playerClass)
                    if actions and #actions > 0 then entry.petActions = actions end
                end
            end
        end
    end

    -- ========================================================================
    -- CONSUMABLE BUFFS
    -- ========================================================================
    local consumableVisible = IsCategoryVisibleForContent("consumable")
    local consExGlow, consMissGlow, consThreshold = GetCategoryGlowSettings("consumable")
    local competitivePvP = IsInCompetitivePvP()
    if consumablesDismissed then consumableVisible = false end
    for i, buff in ipairs(Consumables) do
        local entry = GetOrCreateEntry(buff.key, "consumable", i)
        local settingKey = buff.groupId or buff.key
        if buff.showOnInstanceEntry then
            if inDelveEntry and consumableVisible and IsBuffEnabled(settingKey) and PassesPreChecks(buff, nil, db) then
                local shouldShow = ShouldShowConsumableBuff(buff)
                if shouldShow then SetEntryText(entry, buff.overlayText, consMissGlow) end
            end
        else
            local requiredClass = buff.class or buff.casterClass
            local hasCaster = not requiredClass or HasCasterForBuff(requiredClass, buff.levelRequired)
            if IsBuffEnabled(settingKey) and consumableVisible
                and not (competitivePvP and buff.disabledInCompetitivePvP)
                and hasCaster then
                local trackable = IsAuraTrackable(buff)
                if (not isAuraRestricted or trackable) and PassesPreChecks(buff, nil, db) then
                    local shouldShow, remainingTime, activeSpellID, itemCount = ShouldShowConsumableBuff(buff)
                    if shouldShow then
                        SetEntryText(entry, buff.overlayText, consMissGlow)
                    elseif buff.key == "healthstone" and itemCount and db.defaults and db.defaults.healthstoneLowStock then
                        local hsThreshold = db.defaults.healthstoneThreshold or 1
                        if itemCount <= hsThreshold then
                            SetEntryText(entry, tostring(itemCount), consMissGlow)
                            entry.glowKindOverride = "expiring"
                        end
                    elseif not buff.noExpirationGlow and not hideExpiring then
                        if TrySetEntryExpiring(entry, remainingTime, consThreshold, consExGlow) then
                            if activeSpellID and type(buff.spellID) == "table" then
                                local ok2, tex = pcall(C_Spell.GetSpellTexture, activeSpellID)
                                entry.dynamicIcon = ok2 and tex or nil
                            end
                        end
                    end
                    if entry.visible and buff.key == "food" then
                        entry.isEating = IsPlayerEating()
                        if entry.isEating then entry.eatingExpirationTime = GetEatingExpirationTime() end
                    end
                end
            end
        end
    end

    -- ========================================================================
    -- CUSTOM BUFFS
    -- ========================================================================
    local customExGlow, customMissGlow, customThreshold = GetCategoryGlowSettings("custom")
    for i, buff in ipairs(CustomBuffs) do
        local entry = GetOrCreateEntry(buff.key, "custom", i)
        local settingKey = buff.groupId or buff.key
        local trackable = IsAuraTrackable(buff)
        local shouldProcess = (not isAuraRestricted or trackable)
            and IsBuffEnabled(settingKey)
            and IsCustomBuffVisibleForContent(buff)
        if shouldProcess and buff.requireSpellKnown then
            local spellIDs2 = AsSpellList(buff.spellID)
            local knowsAny = false
            for _, spellID2 in ipairs(spellIDs2) do
                if IsPlayerSpellCached(spellID2) then knowsAny = true; break end
            end
            if not knowsAny then shouldProcess = false end
        end
        if shouldProcess then
            local gateItemID = buff.requireItemID or buff.castItemID
            if gateItemID and not HasItemByMode(gateItemID, buff.requireItemMode) then
                shouldProcess = false
            end
        end
        if shouldProcess then
            local shouldShow = ShouldShowSelfBuff(
                buff.spellID, buff.class, buff.enchantID,
                buff.requiresSpellID, buff.excludeSpellID,
                buff.buffIdOverride, buff.customCheck,
                buff.requireSpecId, true, buff.requiresBuffWithEnchant)
            local wantPresent = buff.showWhenPresent
            local show = (wantPresent and shouldShow == false) or (not wantPresent and shouldShow)
            if show then
                SetEntryText(entry, buff.overlayText, customMissGlow)
            elseif not show and shouldShow ~= nil and not buff.enchantID and not hideExpiring
                and (buff.buffIdOverride or buff.spellID) then
                local _, remaining = UnitHasBuff("player", buff.buffIdOverride or buff.spellID)
                TrySetEntryExpiring(entry, remaining, customThreshold, customExGlow)
            end
        end
    end

    -- ========================================================================
    -- BUILD CATEGORY LISTS
    -- ========================================================================
    for _, list in pairs(BuffState.visibleByCategory) do wipe(list) end
    for _, entry in pairs(BuffState.entries) do
        if entry.visible then
            local cat = entry.category
            if not BuffState.visibleByCategory[cat] then BuffState.visibleByCategory[cat] = {} end
            tinsert(BuffState.visibleByCategory[cat], entry)
        end
    end
    for _, list in pairs(BuffState.visibleByCategory) do
        local sorted = true
        for j = 2, #list do
            if list[j].sortOrder < list[j - 1].sortOrder then sorted = false; break end
        end
        list._sorted = sorted
    end
    BuffState.lastUpdate = GetTime()

    -- Fire event
    if ns.BR_Callbacks then ns.BR_Callbacks:TriggerEvent("BuffStateChanged") end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function BuffState.GetEntry(key) return BuffState.entries[key] end
function BuffState.SetPlayerClass(class) playerClass = class end
function BuffState.SetReadyCheckState(state) inReadyCheck = state end
function BuffState.GetReadyCheckState() return inReadyCheck end
function BuffState.SetInstanceEntryState(state) inInstanceEntry = state end
function BuffState.SetDelveEntryState(state) inDelveEntry = state end
function BuffState.SetInVehicle(state) inVehicle = state end
function BuffState.GetInVehicle() return inVehicle end
function BuffState.SetConsumablesDismissed(state) consumablesDismissed = state end
function BuffState.GetConsumablesDismissed() return consumablesDismissed end
function BuffState.SetInCombat(state) inCombat = state end
function BuffState.SetPvPPrepPhase(state) inPvPPrepPhase = state end

function BuffState.IsRestricted()
    return inCombat
        or GetCurrentDifficultyKey() == "mythicPlus"
        or (GetCurrentContentType() == "pvp" and not inPvPPrepPhase)
end

function BuffState.IsLegacyInstance()
    if cachedIsLegacyInstance == nil then GetCurrentContentType() end
    return cachedIsLegacyInstance or false
end

function BuffState.ShouldTriggerDungeonEntry()
    if GetNumGroupMembers() <= 1 then return false end
    if GetCurrentContentType() ~= "dungeon" then return false end
    local diffKey = GetCurrentDifficultyKey()
    return diffKey ~= "mythicPlus" and diffKey ~= "follower"
end

function BuffState.ShouldTriggerDelveEntry()
    return ns.IsInDelve and ns.IsInDelve()
end

-- Cache invalidation
function BuffState.InvalidateContentTypeCache()
    cachedContentType = nil; cachedInstanceType = nil
    cachedDifficultyKey = nil; cachedCompetitivePvP = nil
    cachedIsLegacyInstance = nil
end

function BuffState.InvalidateSpecCache()
    cachedSpecId = nil; cachedPlayerRole = nil
end

function BuffState.InvalidateSpellCache()
    wipe(cachedSpellKnowledge)
    cachedSpecId = nil; cachedPlayerRole = nil
end

function BuffState.InvalidateItemCache()
    wipe(cachedItemOwnership)
end

local function ResolveOffHandType()
    if cachedOffHandType == nil then
        local offhandItemID = GetInventoryItemID("player", 17)
        if not offhandItemID then
            cachedOffHandType = "none"
        else
            local _, _, _, _, _, itemClassID, itemSubClassID = GetItemInfoInstant(offhandItemID)
            if itemClassID == 2 then cachedOffHandType = "weapon"
            elseif itemClassID == 4 and itemSubClassID == 6 then cachedOffHandType = "shield"
            else cachedOffHandType = "none" end
        end
    end
end

function BuffState.HasOffHandWeapon()
    ResolveOffHandType(); return cachedOffHandType == "weapon"
end

function BuffState.HasShield()
    ResolveOffHandType(); return cachedOffHandType == "shield"
end

function BuffState.GetOffHandEnchantID()
    return currentWeaponEnchants.offHandID
end

function BuffState.GetPermanentWeaponEnchantID(slot)
    if slot == 16 then return currentWeaponEnchants.permanentMH end
    return currentWeaponEnchants.permanentOH
end

function BuffState.InvalidateOffHandCache()
    cachedOffHandType = nil
end

function BuffState.GetPlayerRole() return GetPlayerRole() end

function BuffState.GetLastTarget(buffKey)
    local entry = lastTargets[buffKey]
    return entry and entry.name
end

-- ============================================================================
-- EXPORT STATE HELPERS
-- ============================================================================

ns.StateHelpers = {
    GetPlayerSpecId = GetPlayerSpecId,
    FormatRemainingTime = FormatRemainingTime,
    FormatEatingTime = FormatEatingTime,
    IsPlayerEating = IsPlayerEating,
    UpdateEatingState = UpdateEatingState,
    ScanEatingState = ScanEatingState,
    GetEatingExpirationTime = GetEatingExpirationTime,
    GetCurrentContentType = GetCurrentContentType,
    IsCategoryVisibleForContent = IsCategoryVisibleForContent,
    GetBuffSettingKey = GetBuffSettingKey,
    IsBuffEnabled = IsBuffEnabled,
    GetLastTarget = BuffState.GetLastTarget,
}

-- ============================================================================
-- LIBSPECIALIZATION INTEGRATION
-- ============================================================================

local LibSpec = LibStub and LibStub("LibSpecialization", true)
if LibSpec then
    local specFrame = CreateFrame("Frame")
    specFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    specFrame:SetScript("OnEvent", function()
        local currentNames = {}
        currentNames[GetUnitName("player", true)] = true
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local name = GetUnitName("raid" .. i, true)
                if name then currentNames[name] = true end
            end
        else
            for i = 1, GetNumGroupMembers() - 1 do
                local name = GetUnitName("party" .. i, true)
                if name then currentNames[name] = true end
            end
        end
        for name in pairs(allySpecCache) do
            if not currentNames[name] then allySpecCache[name] = nil end
        end
    end)

    local callbackTable = {}
    LibSpec.RegisterGroup(callbackTable, function(specId, _role, _position, sender)
        if not sender then return end
        local oldSpec = allySpecCache[sender]
        if oldSpec == specId then return end
        allySpecCache[sender] = specId
        if oldSpec and BuffState.Refresh then BuffState.Refresh() end
    end)
end
