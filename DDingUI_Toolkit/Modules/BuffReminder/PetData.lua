--[[
    DDingToolKit - BuffReminder: Pet Data
    Builds per-class lists of pet summon actions for expanded pet icons.
    Ported from BuffReminders by zerbi.
]]

local _, ns = ...

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

---@class PetAction
---@field key string
---@field spellID number
---@field spellName string
---@field icon number
---@field label string
---@field sortOrder number
---@field petFamily? string
---@field petSpecIcon? number
---@field petSpiritBeast? boolean

-- Hunter Call Pet spell IDs (Call Pet 1 through Call Pet 5)
local CALL_PET_SPELLS = { 883, 83242, 83243, 83244, 83245 }

-- Revive Pet spell ID
local REVIVE_PET = 982

-- Hunter pet spec → ability icon texture
local PET_SPEC_ICONS = {
    Cunning = 348567,
    Ferocity = 136224,
    Tenacity = 571585,
}

-- Warlock Summon Demon flyout ID
local SUMMON_DEMON_FLYOUT = 10

-- Warlock summon spell ID → short pet name
local WARLOCK_PET_NAMES = {
    [688] = "Imp",
    [697] = "Voidwalker",
    [691] = "Felhunter",
    [366222] = "Sayaad",
    [30146] = "Felguard",
}

-- Resolve Spirit Beast family name
local SPIRIT_BEAST_FAMILY = (C_CreatureInfo.GetCreatureFamilyInfo(46) or {}).name or "Spirit Beast"

-- Spell name cache
local spellNameCache = {}
local function GetSpellNameCached(spellID)
    local name = spellNameCache[spellID]
    if name == nil then
        name = C_Spell.GetSpellName(spellID) or false
        spellNameCache[spellID] = name
    end
    return name or nil
end

---Build hunter pet actions from stable info
local function BuildHunterActions()
    -- MM Hunters don't use pets unless they have Unbreakable Bond
    local specIndex = GetSpecialization()
    local specId = specIndex and GetSpecializationInfo(specIndex)
    if specId == 254 and not IsPlayerSpell(1223323) then
        return nil
    end

    local canUseExotic = IsPlayerSpell(53270)
    local actions = {}
    local order = 0

    for slotIndex, spellID in ipairs(CALL_PET_SPELLS) do
        if IsPlayerSpell(spellID) then
            local info = C_StableInfo.GetStablePetInfo(slotIndex)
            if info and info.name and info.icon and (not info.isExotic or canUseExotic) then
                order = order + 1
                actions[#actions + 1] = {
                    key = "pet_action_" .. spellID,
                    spellID = spellID,
                    spellName = GetSpellNameCached(spellID),
                    icon = info.icon,
                    label = info.name,
                    sortOrder = order,
                    petFamily = info.specialization,
                    petSpecIcon = PET_SPEC_ICONS[info.specialization],
                    petSpiritBeast = info.familyName == SPIRIT_BEAST_FAMILY or nil,
                }
            end
        end
    end

    -- Add Revive Pet at the end
    if #actions > 0 and IsPlayerSpell(REVIVE_PET) then
        order = order + 1
        local icon = C_Spell.GetSpellTexture(REVIVE_PET)
        if icon then
            actions[#actions + 1] = {
                key = "pet_action_" .. REVIVE_PET,
                spellID = REVIVE_PET,
                spellName = GetSpellNameCached(REVIVE_PET),
                icon = icon,
                label = "소환수 부활",
                sortOrder = order,
            }
        end
    end

    return #actions > 0 and actions or nil
end

---Build warlock pet actions from the Summon Demon flyout
local function BuildWarlockActions()
    local ok, _, _, numSlots, isKnown = pcall(GetFlyoutInfo, SUMMON_DEMON_FLYOUT)
    if not ok or not isKnown or not numSlots then
        return nil
    end

    local actions = {}
    local order = 0

    for i = 1, numSlots do
        local slotOk, spellID, _, slotIsKnown = pcall(GetFlyoutSlotInfo, SUMMON_DEMON_FLYOUT, i)
        if slotOk and spellID and slotIsKnown then
            local info = C_Spell.GetSpellInfo(spellID)
            if info then
                order = order + 1
                actions[#actions + 1] = {
                    key = "pet_action_" .. spellID,
                    spellID = spellID,
                    spellName = info.name,
                    icon = info.iconID,
                    label = WARLOCK_PET_NAMES[spellID] or info.name,
                    sortOrder = order,
                }
            end
        end
    end

    if #actions == 0 then
        return nil
    end

    -- Demonology: default to last action (Felguard) in generic mode
    local specIndex = GetSpecialization()
    local specId = specIndex and GetSpecializationInfo(specIndex)
    if specId == 266 then
        actions.genericIndex = #actions
    end

    return actions
end

-- Single-action pet spell ID → short pet name
local SINGLE_PET_NAMES = {
    [46584] = "Ghoul",
    [31687] = "Water Elemental",
}

---Build a single-action list for a given spell
local function BuildSingleAction(spellID)
    if not IsPlayerSpell(spellID) then
        return nil
    end
    local info = C_Spell.GetSpellInfo(spellID)
    if not info then
        return nil
    end
    return {
        {
            key = "pet_action_" .. spellID,
            spellID = spellID,
            spellName = info.name,
            icon = info.iconID,
            label = SINGLE_PET_NAMES[spellID] or info.name,
            sortOrder = 1,
        },
    }
end

---Build a single Felguard summon action for "wrong pet" click-to-cast
local function BuildFelguardAction()
    local spellID = 30146
    if not IsPlayerSpell(spellID) then
        return nil
    end
    local info = C_Spell.GetSpellInfo(spellID)
    if not info then
        return nil
    end
    return {
        {
            key = "pet_action_" .. spellID,
            spellID = spellID,
            spellName = info.name,
            icon = info.iconID,
            label = "펠가드",
            sortOrder = 1,
        },
    }
end

-- Cached pet actions (rebuilt on spec/talent/stable changes)
local cachedActions = nil
local cacheValid = false

local CLASS_PET_BUILDERS = {
    HUNTER = BuildHunterActions,
    WARLOCK = BuildWarlockActions,
    DEATHKNIGHT = function() return BuildSingleAction(46584) end,
    MAGE = function() return BuildSingleAction(31687) end,
}

local function GetPetActions(class)
    if cacheValid then
        return cachedActions
    end
    local builder = CLASS_PET_BUILDERS[class]
    cachedActions = builder and builder() or nil
    cacheValid = true
    return cachedActions
end

local function InvalidatePetActions()
    cacheValid = false
    cachedActions = nil
end

-- Export
ns.PetHelpers = {
    REVIVE_PET_ID = REVIVE_PET,
    GetPetActions = GetPetActions,
    GetFelguardAction = BuildFelguardAction,
    InvalidatePetActions = InvalidatePetActions,
}
