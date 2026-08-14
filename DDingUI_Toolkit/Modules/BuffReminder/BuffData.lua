--[[
    DDingToolKit - BuffReminder: Buff Data Tables
    Full 7-category buff definitions (raid/presence/targeted/self/pet/consumable/custom).
    Ported from BuffReminders by zerbi.
]]

local _, ns = ...

local min = math.min
local GetSpellTexture = C_Spell.GetSpellTexture
local _, playerClass = UnitClass("player")

-- ============================================================================
-- DK RUNEFORGE DATA
-- ============================================================================

local DK_RUNEFORGES = {
    { enchantID = 3368, spellID = 53344, key = "fallenCrusader" },
    { enchantID = 3370, spellID = 53343, key = "razorice" },
    { enchantID = 3847, spellID = 62158, key = "stoneskinGargoyle" },
    { enchantID = 6241, spellID = 326805, key = "sanguination" },
    { enchantID = 6242, spellID = 326855, key = "spellwarding" },
    { enchantID = 6244, spellID = 326977, key = "unendingThirst" },
    { enchantID = 6245, spellID = 327082, key = "apocalypse" },
}
ns.DK_RUNEFORGES = DK_RUNEFORGES

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function IsNotEarthen()
    if not ns.playerRace then
        local _, raceToken = UnitRace("player")
        ns.playerRace = raceToken
    end
    return ns.playerRace ~= "EarthenDwarf"
end

local function IsInDelve()
    local difficultyID = select(3, GetInstanceInfo())
    return difficultyID == 208
end
ns.IsInDelve = IsInDelve

local function IsPetOnPassive()
    if not UnitExists("pet") then
        return nil
    end
    for i = 1, NUM_PET_ACTION_SLOTS do
        local name, _, _, isActive = GetPetActionInfo(i)
        if name == "PET_MODE_PASSIVE" and isActive then
            return true
        end
    end
    return nil
end

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
ns.GetSpellName = GetSpellNameCached

-- Targeted click macro builder
local function TargetedClickMacro(buffKey)
    return function(spellID)
        local name = GetSpellNameCached(spellID) or ""
        local lastTarget = ns.BuffState and ns.BuffState.GetLastTarget and ns.BuffState.GetLastTarget(buffKey)
        if lastTarget then
            return "/cast [@" .. lastTarget .. ",help,nodead][@mouseover,help,nodead][@target,help,nodead][] " .. name
        end
        return "/cast [@mouseover,help,nodead][@target,help,nodead][] " .. name
    end
end

-- ============================================================================
-- ROGUE POISON SYSTEM
-- ============================================================================

local poisonLethal = { 381664, 2823, 315584, 8679 }
local poisonNonLethal = { 381637, 5761, 3408 }

local poisonCache = {
    time = -1,
    activeL = 0, activeNL = 0,
    requiredL = 0, requiredNL = 0,
    knownL = 0, knownNL = 0,
    missingL = nil, missingNL = nil,
    minRemaining = nil, expiringID = nil,
    nextCastID = nil,
}

local function ScanPoisonCategory(poisons, now)
    local active, known, missing = 0, 0, nil
    local minRem, expID = nil, nil
    for _, id in ipairs(poisons) do
        local isKnown = IsPlayerSpell(id)
        if isKnown then known = known + 1 end
        local auraData
        pcall(function() auraData = C_UnitAuras.GetUnitAuraBySpellID("player", id) end)
        if auraData then
            active = active + 1
            if auraData.expirationTime and auraData.expirationTime > 0 then
                local rem = auraData.expirationTime - now
                if not minRem or rem < minRem then
                    minRem = rem
                    expID = id
                end
            end
        elseif isKnown and not missing then
            missing = id
        end
    end
    return active, known, missing, minRem, expID
end

local function RefreshPoisonCache()
    local now = GetTime()
    if poisonCache.time == now then return end
    poisonCache.time = now

    local activeL, knownL, missingL, minRemL, expIDL = ScanPoisonCategory(poisonLethal, now)
    local activeNL, knownNL, missingNL, minRemNL, expIDNL = ScanPoisonCategory(poisonNonLethal, now)

    poisonCache.activeL = activeL
    poisonCache.activeNL = activeNL
    poisonCache.knownL = knownL
    poisonCache.knownNL = knownNL
    poisonCache.missingL = missingL
    poisonCache.missingNL = missingNL

    local hasDTB = IsPlayerSpell(381801)
    poisonCache.requiredL = min(knownL, hasDTB and 2 or 1)
    poisonCache.requiredNL = min(knownNL, hasDTB and 2 or 1)

    if minRemL and minRemNL then
        if minRemL <= minRemNL then
            poisonCache.minRemaining = minRemL
            poisonCache.expiringID = expIDL
        else
            poisonCache.minRemaining = minRemNL
            poisonCache.expiringID = expIDNL
        end
    elseif minRemL then
        poisonCache.minRemaining = minRemL
        poisonCache.expiringID = expIDL
    elseif minRemNL then
        poisonCache.minRemaining = minRemNL
        poisonCache.expiringID = expIDNL
    else
        poisonCache.minRemaining = nil
        poisonCache.expiringID = nil
    end

    local needL = missingL and activeL < poisonCache.requiredL
    local needNL = missingNL and activeNL < poisonCache.requiredNL

    if needL and activeL <= activeNL then
        poisonCache.nextCastID = missingL
    elseif needNL then
        poisonCache.nextCastID = missingNL
    elseif needL then
        poisonCache.nextCastID = missingL
    else
        poisonCache.nextCastID = nil
    end
end

local function GetNextPoisonCastID()
    RefreshPoisonCache()
    return poisonCache.nextCastID
end

local function GetPoisonExpirationInfo()
    RefreshPoisonCache()
    return poisonCache.minRemaining, poisonCache.expiringID
end

-- ============================================================================
-- BUFF TABLES
-- ============================================================================

ns.BUFF_TABLES = {
    ---@type RaidBuff[]
    raid = {
        {
            spellID = { 1459, 432778 },
            key = "intellect",
            name = "신비한 지능",
            class = "MAGE",
            levelRequired = 8,
        },
        { spellID = 6673, key = "attackPower", name = "전투의 외침", class = "WARRIOR", levelRequired = 10 },
        {
            spellID = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 },
            castSpellID = 364342,
            key = "bronze",
            name = "청동의 축복",
            class = "EVOKER",
            levelRequired = 30,
        },
        {
            spellID = { 1126, 432661 },
            key = "versatility",
            name = "야생의 징표",
            class = "DRUID",
            levelRequired = 10,
        },
        { spellID = 21562, key = "stamina", name = "인내의 기도", class = "PRIEST", levelRequired = 10 },
        { spellID = 462854, key = "skyfury", name = "하늘분노", class = "SHAMAN", levelRequired = 16 },
    },

    ---@type PresenceBuff[]
    presence = {
        {
            spellID = { 381637, 5761 },
            key = "atrophicNumbingPoison",
            name = "약화/무감독",
            class = "ROGUE",
            levelRequired = 80,
            overlayText = "독\n누락",
            groupOnly = true,
            suppressedByEntry = "roguePoisons",
        },
        {
            spellID = 465,
            key = "devotionAura",
            name = "헌신의 오라",
            class = "PALADIN",
            levelRequired = 10,
            overlayText = "오라\n누락",
        },
        {
            spellID = 20707,
            key = "soulstone",
            name = "영혼석",
            class = "WARLOCK",
            levelRequired = 13,
            overlayText = "영혼석\n누락",
            readyCheckOnly = true,
            castOnOthers = true,
            noExpirationGlow = true,
            customCheck = function(isRestricted)
                if playerClass ~= "WARLOCK" then return nil end
                local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
                if not (db and db.defaults and db.defaults.soulstoneHideCooldown) then return nil end
                if isRestricted then return false end
                local ok, result = pcall(function()
                    local info = C_Spell.GetSpellCooldown(20707)
                    return not info or info.duration == 0
                end)
                return not ok or result
            end,
            clickMacro = function(spellID)
                local name = GetSpellNameCached(spellID) or ""
                local lastTarget = ns.BuffState and ns.BuffState.GetLastTarget and ns.BuffState.GetLastTarget("soulstone")
                if lastTarget then
                    return "/cast [@" .. lastTarget .. ",help,nodead][@mouseover,help,nodead][@target,help,nodead][@player] " .. name
                end
                local numMembers = GetNumGroupMembers()
                if numMembers > 0 then
                    local prefix = IsInRaid() and "raid" or "party"
                    for i = 1, numMembers do
                        local unitId = prefix .. i
                        if UnitExists(unitId) and not UnitIsDeadOrGhost(unitId) then
                            if UnitGroupRolesAssigned(unitId) == "HEALER" then
                                local healerName = GetUnitName(unitId, true)
                                if healerName then
                                    return "/cast [@" .. healerName .. ",help,nodead][@mouseover,help,nodead][@target,help,nodead][@player] " .. name
                                end
                            end
                        end
                    end
                end
                return "/cast [@mouseover,help,nodead][@target,help,nodead][@player] " .. name
            end,
        },
    },

    ---@type TargetedBuff[]
    targeted = {
        {
            spellID = 156910, key = "beaconOfFaith", name = "신념의 봉화", class = "PALADIN",
            overlayText = "봉화\n누락", groupId = "beacons", requireSpecId = 65,
            glowDetectable = true, clickMacro = TargetedClickMacro("beaconOfFaith"),
        },
        {
            spellID = 53563, key = "beaconOfLight", name = "빛의 봉화", class = "PALADIN",
            overlayText = "봉화\n누락", groupId = "beacons", requireSpecId = 65,
            glowDetectable = true, excludeSpellID = 200025, displayIcon = 236247,
            clickMacro = TargetedClickMacro("beaconOfLight"),
        },
        {
            spellID = 360827, key = "blisteringScales", name = "불타는 비늘", class = "EVOKER",
            beneficiaryRole = "TANK", overlayText = "비늘\n누락", requireSpecId = 1473,
            requiresSpellID = 360827, clickMacro = TargetedClickMacro("blisteringScales"),
        },
        {
            spellID = 974, key = "earthShieldOthers", name = "대지의 보호막", class = "SHAMAN",
            overlayText = "보호막\n누락", clickMacro = TargetedClickMacro("earthShieldOthers"),
        },
        {
            spellID = 369459, key = "sourceOfMagic", name = "마력의 원천", class = "EVOKER",
            beneficiaryRole = "HEALER", overlayText = "원천\n누락",
            clickMacro = TargetedClickMacro("sourceOfMagic"),
        },
        {
            spellID = 474750, casterBuffId = 474754, key = "symbioticRelationship", name = "공생 관계", class = "DRUID",
            overlayText = "공생\n누락", clickMacro = TargetedClickMacro("symbioticRelationship"),
        },
    },

    ---@type SelfBuff[]
    self = {
        {
            spellID = 205022, buffIdOverride = 210126, castSpellID = 1459,
            key = "arcaneFamiliar", name = "비전 소환수", class = "MAGE", overlayText = "소환수\n누락",
        },
        {
            spellID = { 403264, 403265 }, key = "evokerAttunement", name = "조율", class = "EVOKER",
            overlayText = "조율\n누락", requireSpecId = 1473, requiresSpellID = 403208,
        },
        {
            spellID = 29893, castSpellID = 29893, key = "soulwell", name = "영혼의 우물", class = "WARLOCK",
            overlayText = "우물\n생성", showOnInstanceEntry = true,
            customCheck = function(isRestricted)
                if isRestricted then return false end
                local ok, result = pcall(function()
                    local info = C_Spell.GetSpellCooldown(29893)
                    return not info or info.duration == 0
                end)
                return not ok or result
            end,
        },
        {
            spellID = 108503, buffIdOverride = 196099, key = "grimoireOfSacrifice",
            name = "희생의 마법서", class = "WARLOCK", overlayText = "마법서\n누락",
        },
        {
            spellID = 111400, key = "burningRush", name = "타오르는 질주", class = "WARLOCK",
            overlayText = "질주\n활성", showWhenPresent = true, glowDetectable = true,
        },
        -- Paladin weapon rites
        {
            spellID = 433583, key = "riteOfAdjuration", name = "보호의 의식", class = "PALADIN",
            overlayText = "의식\n누락", enchantID = 7144, buffIdOverride = 433584,
            requiresBuffWithEnchant = true, groupId = "paladinRites",
            clickMacro = function(spellID)
                return "/cast " .. (GetSpellNameCached(spellID) or "") .. "\n/use 16"
            end,
        },
        {
            spellID = 433568, key = "riteOfSanctification", name = "성화의 의식", class = "PALADIN",
            overlayText = "의식\n누락", enchantID = 7143, buffIdOverride = 433550,
            requiresBuffWithEnchant = true, groupId = "paladinRites",
            clickMacro = function(spellID)
                return "/cast " .. (GetSpellNameCached(spellID) or "") .. "\n/use 16"
            end,
        },
        -- Rogue poisons
        {
            displayIcon = 136242, castSpellID = 315584,
            key = "roguePoisons", name = "도적 독", class = "ROGUE", overlayText = "독\n바르기",
            customCheck = function()
                RefreshPoisonCache()
                if poisonCache.knownL == 0 and poisonCache.knownNL == 0 then return nil end
                return poisonCache.activeL < poisonCache.requiredL or poisonCache.activeNL < poisonCache.requiredNL
            end,
            getNextCastID = GetNextPoisonCastID,
            getExpirationInfo = GetPoisonExpirationInfo,
            clickMacro = function()
                local castID = GetNextPoisonCastID()
                if not castID then
                    local _, expiringID = GetPoisonExpirationInfo()
                    castID = expiringID
                end
                if castID then return "/cast " .. (GetSpellNameCached(castID) or "") end
                return ""
            end,
        },
        -- DK Runeforge (Main Hand)
        {
            displayIcon = 237523, key = "dkRuneMH", name = "룬 각인 (주무기)", class = "DEATHKNIGHT",
            overlayText = "룬\n변경", noExpirationGlow = true, groupId = "dkRunes",
            customCheck = function()
                if ns.BuffState and ns.BuffState.IsRestricted and ns.BuffState.IsRestricted() then return nil end
                local specIndex = GetSpecialization()
                local specId = specIndex and GetSpecializationInfo(specIndex)
                local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
                local prefs = db and db.dkRunePreferences
                local specPrefs = prefs and prefs[specId]
                if not specPrefs then return nil end
                local isDW = ns.BuffState and ns.BuffState.HasOffHandWeapon and ns.BuffState.HasOffHandWeapon()
                local accepted = specPrefs[isDW and "dw_mainhand" or "mainhand"]
                if not accepted or not next(accepted) then return nil end
                local current = ns.BuffState and ns.BuffState.GetPermanentWeaponEnchantID and ns.BuffState.GetPermanentWeaponEnchantID(16)
                return not accepted[current]
            end,
            getDynamicIcon = function()
                local specIndex = GetSpecialization()
                local specId = specIndex and GetSpecializationInfo(specIndex)
                local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
                local prefs = db and db.dkRunePreferences
                local specPrefs = prefs and prefs[specId]
                if not specPrefs then return nil end
                local isDW = ns.BuffState and ns.BuffState.HasOffHandWeapon and ns.BuffState.HasOffHandWeapon()
                local accepted = specPrefs[isDW and "dw_mainhand" or "mainhand"]
                if accepted then
                    for _, rune in ipairs(DK_RUNEFORGES) do
                        if accepted[rune.enchantID] then return GetSpellTexture(rune.spellID) end
                    end
                end
            end,
        },
        -- DK Runeforge (Off Hand)
        {
            displayIcon = 237523, key = "dkRuneOH", name = "룬 각인 (보조무기)", class = "DEATHKNIGHT",
            overlayText = "룬\n변경", noExpirationGlow = true, groupId = "dkRunes",
            customCheck = function()
                if ns.BuffState and ns.BuffState.IsRestricted and ns.BuffState.IsRestricted() then return nil end
                if not (ns.BuffState and ns.BuffState.HasOffHandWeapon and ns.BuffState.HasOffHandWeapon()) then return nil end
                local specIndex = GetSpecialization()
                local specId = specIndex and GetSpecializationInfo(specIndex)
                local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
                local prefs = db and db.dkRunePreferences
                local specPrefs = prefs and prefs[specId]
                if not specPrefs then return nil end
                local accepted = specPrefs.dw_offhand
                if not accepted or not next(accepted) then return nil end
                local current = ns.BuffState and ns.BuffState.GetPermanentWeaponEnchantID and ns.BuffState.GetPermanentWeaponEnchantID(17)
                return not accepted[current]
            end,
            getDynamicIcon = function()
                local specIndex = GetSpecialization()
                local specId = specIndex and GetSpecializationInfo(specIndex)
                local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
                local prefs = db and db.dkRunePreferences
                local specPrefs = prefs and prefs[specId]
                local accepted = specPrefs and specPrefs.dw_offhand
                if accepted then
                    for _, rune in ipairs(DK_RUNEFORGES) do
                        if accepted[rune.enchantID] then return GetSpellTexture(rune.spellID) end
                    end
                end
            end,
        },
        -- Shadow Priest
        {
            spellID = 232698, key = "shadowform", name = "어둠의 형상", class = "PRIEST",
            overlayText = "형상\n누락", buffIdOverride = { 232698, 194249 }, noExpirationGlow = true,
        },
        -- Shaman imbues
        {
            spellID = 382021, key = "earthlivingWeapon", name = "대지의 생명 무기", class = "SHAMAN",
            overlayText = "무기\n누락", enchantID = 6498, groupId = "shamanImbues",
        },
        {
            spellID = 318038, key = "flametongueWeapon", name = "화염혀 무기", class = "SHAMAN",
            overlayText = "무기\n누락", enchantID = 5400, groupId = "shamanImbues",
        },
        {
            spellID = 457481, key = "tidecallersGuard", name = "조수소환사의 수호", class = "SHAMAN",
            overlayText = "수호\n누락", enchantID = 7528, requireSpecId = 264, groupId = "shamanImbues",
            customCheck = function()
                if not IsPlayerSpell(457481) then return nil end
                if not (ns.BuffState and ns.BuffState.HasShield and ns.BuffState.HasShield()) then return nil end
                return ns.BuffState.GetOffHandEnchantID() ~= 7528
            end,
        },
        {
            spellID = 33757, key = "windfuryWeapon", name = "질풍의 무기", class = "SHAMAN",
            overlayText = "무기\n누락", enchantID = 5401, groupId = "shamanImbues",
        },
        -- Shaman shields
        {
            spellID = 974, buffIdOverride = 383648, key = "earthShieldSelfEO",
            name = "자가 대지 보호막", class = "SHAMAN", overlayText = "보호막\n누락",
            requiresSpellID = 383010, groupId = "shamanShields", displaySpells = 974,
        },
        {
            spellID = { 192106, 52127 }, key = "waterLightningShieldEO",
            name = "번개/물의 보호막", class = "SHAMAN", overlayText = "보호막\n누락",
            requiresSpellID = 383010, groupId = "shamanShields", displaySpells = 192106,
            iconByRole = { HEALER = 52127, DAMAGER = 192106, TANK = 192106 },
        },
        {
            spellID = { 974, 192106, 52127 }, key = "shamanShieldBasic",
            name = "보호막 (기본)", class = "SHAMAN", overlayText = "보호막\n누락",
            excludeSpellID = 383010, groupId = "shamanShields", displaySpells = 52127,
            iconByRole = { HEALER = 52127, DAMAGER = 192106, TANK = 192106 },
        },
    },

    ---@type SelfBuff[]
    pet = {
        {
            key = "petPassive", name = "소환수 수동",
            overlayText = "소환수\n수동", displayIcon = 132311,
            customCheck = IsPetOnPassive,
        },
        {
            key = "hunterPet", name = "사냥꾼 소환수", class = "HUNTER",
            overlayText = "소환수\n부재", displayIcon = 132161, groupId = "pets",
            customCheck = function()
                local specIndex = GetSpecialization()
                local specId = specIndex and GetSpecializationInfo(specIndex)
                if specId == 254 and not IsPlayerSpell(1223323) then return nil end
                return not UnitExists("pet") or UnitIsDead("pet") or nil
            end,
        },
        {
            displayIcon = 1100170, key = "unholyPet", name = "부활한 구울", class = "DEATHKNIGHT",
            overlayText = "소환수\n부재", requireSpecId = 252, groupId = "pets",
            customCheck = function() return not UnitExists("pet") end,
        },
        {
            key = "warlockPet", name = "흑마법사 소환수", class = "WARLOCK",
            overlayText = "소환수\n부재", displayIcon = 136082,
            excludeSpellID = 108503, groupId = "pets",
            customCheck = function() return not UnitExists("pet") end,
        },
        {
            displayIcon = 135862, key = "frostMagePet", name = "물의 정령", class = "MAGE",
            overlayText = "소환수\n부재", requireSpecId = 64, requiresSpellID = 31687, groupId = "pets",
            customCheck = function() return not UnitExists("pet") end,
        },
        {
            key = "warlockWrongPet", name = "잘못된 소환수", class = "WARLOCK",
            overlayText = "소환수\n변경", displayIcon = 136216,
            excludeSpellID = 108503, requireSpecId = 266, groupId = "pets",
            customCheck = function()
                if not UnitExists("pet") then return false end
                local name, familyID = UnitCreatureFamily("pet")
                return familyID ~= 29 and name ~= "Felguard"
            end,
            getPetActions = function()
                return ns.PetHelpers and ns.PetHelpers.GetFelguardAction and ns.PetHelpers.GetFelguardAction()
            end,
        },
    },

    ---@type CustomBuff[]
    custom = {},

    ---@type ConsumableBuff[]
    consumable = {
        -- Augment Rune
        {
            spellID = { 1234969, 1242347, 453250, 393438, 1264426, 347901 },
            displaySpells = { 1264426, 1234969 },
            key = "rune", name = "증강 룬", overlayText = "룬\n누락",
            permanentRuneItemIDs = { 243191, 259085 },
            groupId = "rune", consumableCategory = "rune",
            disabledInCompetitivePvP = true,
        },
        -- Flasks
        {
            spellID = {
                432021, 431971, 431972, 431973, 431974, 432473,
                1235057, 1235108, 1235110, 1235111, 1239355,
            },
            displaySpells = { 1235111, 1235110, 1235108, 1235057, 1239355 },
            key = "flask", name = "영약", overlayText = "영약\n누락",
            groupId = "flask", consumableCategory = "flask",
            disabledInCompetitivePvP = true,
        },
        -- Delve Food
        {
            spellID = 442522, key = "delveFood", name = "탐험 음식", overlayText = "음식\n누락",
            groupId = "delveFood", showOnInstanceEntry = true,
            visibilityCondition = IsInDelve, disabledInCompetitivePvP = true,
        },
        -- Food
        {
            buffIconID = 136000, key = "food", name = "음식", overlayText = "음식\n누락",
            groupId = "food", consumableCategory = "food", displayIcon = 136000,
            visibilityCondition = IsNotEarthen, disabledInCompetitivePvP = true,
        },
        -- Healthstone
        {
            itemID = { 5512, 224464 }, castSpellID = 29893,
            key = "healthstone", name = "생명석", casterClass = "WARLOCK",
            overlayText = "생명석\n누락", groupId = "healthstone", displayIcon = 538745,
            freeConsumable = true,
            clickMacro = function()
                local spellID = (GetNumGroupMembers() > 0 and IsInInstance()) and 29893 or 6201
                local name = GetSpellNameCached(spellID)
                return "/cast " .. (name or "")
            end,
        },
        -- Weapon Buffs (Main Hand)
        {
            checkWeaponEnchant = true, key = "weaponBuff", name = "무기 강화",
            overlayText = "무기\n강화", groupId = "weaponBuff",
            displayIcon = { 7548987, 7548941, 7548938 },
            consumableCategory = "weapon",
            excludeIfSpellKnown = { 382021, 318038, 33757, 433583, 433568 },
            visibilityCondition = function()
                return not (ns.BuffState and ns.BuffState.IsRestricted and ns.BuffState.IsRestricted())
            end,
            disabledInCompetitivePvP = true,
        },
        -- Weapon Buffs (Off Hand)
        {
            checkWeaponEnchantOH = true, key = "weaponBuffOH", name = "보조무기 강화",
            overlayText = "무기\n강화", groupId = "weaponBuff",
            displayIcon = { 7548987, 7548941, 7548938 },
            consumableCategory = "weapon",
            excludeIfSpellKnown = { 382021, 318038, 33757, 433583, 433568 },
            visibilityCondition = function()
                return not (ns.BuffState and ns.BuffState.IsRestricted and ns.BuffState.IsRestricted())
                    and (ns.BuffState and ns.BuffState.HasOffHandWeapon and ns.BuffState.HasOffHandWeapon())
            end,
            disabledInCompetitivePvP = true,
        },
    },
}

-- Derive buff key → consumable category mapping
local buffKeyToCategory = {}
for _, buff in ipairs(ns.BUFF_TABLES.consumable) do
    if buff.consumableCategory then
        buffKeyToCategory[buff.key] = buff.consumableCategory
    end
end
ns.BUFF_KEY_TO_CATEGORY = buffKeyToCategory

-- Buff groups
ns.BuffGroups = {
    beacons = { displayName = "봉화" },
    dkRunes = { displayName = "DK 룬" },
    shamanImbues = { displayName = "주술사 강화" },
    paladinRites = { displayName = "성기사 의식" },
    pets = { displayName = "소환수" },
    shamanShields = { displayName = "주술사 보호막" },
    flask = { displayName = "영약" },
    food = { displayName = "음식" },
    delveFood = { displayName = "탐험 음식" },
    healthstone = { displayName = "생명석" },
    rune = { displayName = "증강 룬" },
    weaponBuff = { displayName = "무기 강화" },
}

-- State helpers (forward references, populated by BuffState.lua)
ns.StateHelpers = ns.StateHelpers or {}
