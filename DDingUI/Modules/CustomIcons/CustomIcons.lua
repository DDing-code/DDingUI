local ns = select(2, ...)
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local canaccessvalue = canaccessvalue or function() return true end

DDingUI.CustomIcons = DDingUI.CustomIcons or {}
local CustomIcons = DDingUI.CustomIcons

local LSM = LibStub("LibSharedMedia-3.0", true)

-- [REFACTOR] 공통 TextureBorder 유틸리티 (Toolkit.lua) — CustomIcons는 안쪽 보더(inset=true)
local _CreateTextureBorder = DDingUI.CreateTextureBorder
local UpdateTextureBorderColor = DDingUI.UpdateTextureBorderColor
local _UpdateTextureBorderSize = DDingUI.UpdateTextureBorderSize
local ShowTextureBorder = DDingUI.ShowTextureBorder

-- 안쪽 보더 래퍼 (inset=true 자동 전달)
local function CreateTextureBorder(parent, borderSize, r, g, b, a)
    return _CreateTextureBorder(parent, borderSize, r, g, b, a, true)
end
local function UpdateTextureBorderSize(parent, borderSize)
    return _UpdateTextureBorderSize(parent, borderSize, true)
end

-- Forward declarations
local RefreshAllLayouts
local UpdateAllIcons

-- [RACIALS] 종족 특성 매핑 (자동 감지용)
function CustomIcons:GetPlayerRacialSpellID()
    local racials = DDingUI.CustomIconRacials
    return racials and racials:GetSpellID() or nil
end

local function GetPlayerRacialSpellID()
    return CustomIcons:GetPlayerRacialSpellID()
end

function CustomIcons:IsCurrentRacialSpellIcon(iconData)
    if type(iconData) ~= "table" then return false end
    local iconSpellID = tonumber(iconData.id)
    local racialID = tonumber(GetPlayerRacialSpellID())
    return iconSpellID ~= nil and racialID ~= nil and iconSpellID == racialID
end

local function IsFlightHideAlphaLocked()
    local fh = DDingUI.FlightHide
    return fh and (fh.isActive or fh._hiding)
end

-- [REFACTOR] CreateBackdrop은 GUI.lua로 이동됨 → EnsureGUILoaded()에서 lazy-load

-- Runtime containers
local runtime = {
    iconFrames = {},  -- [iconKey] = frame
    groupFrames = {}, -- [groupKey] = frame
    iconFramePool = {}, -- reusable inactive icon frames
    textureCache = {},  -- [stable identity] = resolved texture
    dragState = {},
    pendingSpecReload = false,
    customTimedAuras = {}, -- [spellID] = { startTime, duration, expirationTime, token, iconTexture }
    itemCombatLockouts = {},
    cooldownWatcher = {
        itemTargets = {},
        slotTargets = {},
        itemStates = {},
        slotStates = {},
        pendingIconKeys = {},
        activeTargetCount = 0,
        hasSpellTarget = false,
        kindsInitialized = false,
        evaluatePending = false,
        refreshPending = false,
        refreshAll = false,
        layoutNotify = nil,
    },
    timedAuraDebug = {
        bloodlust = {},
        timespiral = {},
    },
}

-- ------------------------
-- DB helpers
-- ------------------------
local DEFAULT_ICON_SETTINGS = {
    iconSize = 44,
    aspectRatio = 1.0,
    borderSize = 1,
    borderColor = { 0, 0, 0, 1 },
    showCharges = true,
    showCooldown = true,
    showGCDSwipe = false,
    desaturateWhenUnusable = true,
    desaturateOnCooldown = true,
    countSettings = {
        size = 16,
        anchor = "BOTTOMRIGHT",
        offsetX = -2,
        offsetY = 2,
        color = { 1, 1, 1, 1 },
    },
    cooldownSettings = {
        size = 12,
        color = { 1, 1, 1, 1 },
    },
}

local function CopyColor(color)
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], color[4] }
end

-- Infer icon type if missing (for migration from older versions)
local function EnsureIconType(iconData)
    if not iconData then return end
    if iconData.type then return end  -- Already has type

    -- Infer type from data structure
    if iconData.slotID then
        iconData.type = "slot"
    elseif iconData.id then
        -- Try to detect if it's an item or spell
        -- C_Item.GetItemInfo is more reliable for checking if ID is an item
        local itemInfo = C_Item.GetItemInfo(iconData.id)
        if itemInfo then
            iconData.type = "item"
        else
            -- Also try legacy GetItemInfo as fallback
            local itemName = GetItemInfo(iconData.id)
            if itemName then
                iconData.type = "item"
            else
                -- Check if it's a valid spell
                local spellInfo = C_Spell.GetSpellInfo(iconData.id)
                if spellInfo then
                    iconData.type = "spell"
                else
                    -- Default to spell if we can't determine
                    iconData.type = "spell"
                end
            end
        end
    end
end

local function EnsureIconSettings(iconData)
    if not iconData then return end
    EnsureIconType(iconData)  -- Ensure type is set
    iconData.settings = iconData.settings or {}
    local settings = iconData.settings

    -- NOTE: iconSize is intentionally NOT set here to allow group iconSize to be used as fallback
    -- if settings.iconSize == nil then settings.iconSize = DEFAULT_ICON_SETTINGS.iconSize end
    if settings.aspectRatio == nil then settings.aspectRatio = DEFAULT_ICON_SETTINGS.aspectRatio end
    if settings.borderSize == nil then settings.borderSize = DEFAULT_ICON_SETTINGS.borderSize end
    if settings.borderColor == nil then settings.borderColor = CopyColor(DEFAULT_ICON_SETTINGS.borderColor) end
    if settings.showCharges == nil then settings.showCharges = DEFAULT_ICON_SETTINGS.showCharges end
    if settings.showCooldown == nil then settings.showCooldown = DEFAULT_ICON_SETTINGS.showCooldown end
    if settings.showGCDSwipe == nil then settings.showGCDSwipe = DEFAULT_ICON_SETTINGS.showGCDSwipe end
    if settings.desaturateWhenUnusable == nil then settings.desaturateWhenUnusable = DEFAULT_ICON_SETTINGS.desaturateWhenUnusable end
    if settings.desaturateOnCooldown == nil then settings.desaturateOnCooldown = DEFAULT_ICON_SETTINGS.desaturateOnCooldown end

    settings.countSettings = settings.countSettings or {}
    if settings.countSettings.size == nil then settings.countSettings.size = DEFAULT_ICON_SETTINGS.countSettings.size end
    if settings.countSettings.anchor == nil then settings.countSettings.anchor = DEFAULT_ICON_SETTINGS.countSettings.anchor end
    if settings.countSettings.offsetX == nil then settings.countSettings.offsetX = DEFAULT_ICON_SETTINGS.countSettings.offsetX end
    if settings.countSettings.offsetY == nil then settings.countSettings.offsetY = DEFAULT_ICON_SETTINGS.countSettings.offsetY end
    if settings.countSettings.color == nil then settings.countSettings.color = CopyColor(DEFAULT_ICON_SETTINGS.countSettings.color) end

    settings.cooldownSettings = settings.cooldownSettings or {}
    if settings.cooldownSettings.size == nil then settings.cooldownSettings.size = DEFAULT_ICON_SETTINGS.cooldownSettings.size end
    if settings.cooldownSettings.color == nil then settings.cooldownSettings.color = CopyColor(DEFAULT_ICON_SETTINGS.cooldownSettings.color) end

    -- TrinketProc-specific defaults
    if iconData.type == "trinketProc" then
        if settings.procSpellID == nil then settings.procSpellID = 0 end
        if settings.showProcDuration == nil then settings.showProcDuration = true end
        if settings.showItemCooldown == nil then settings.showItemCooldown = true end
        if settings.showProcStacks == nil then settings.showProcStacks = true end
    end
end

local function HasTableEntries(tbl)
    return type(tbl) == "table" and next(tbl) ~= nil
end

local function HasDynamicPayload(db)
    return type(db) == "table"
        and (HasTableEntries(db.groups) or HasTableEntries(db.iconData) or HasTableEntries(db.ungrouped))
end

local function CountTableEntries(tbl)
    if type(tbl) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function CountDynamicPayload(db)
    if type(db) ~= "table" then return 0 end
    return CountTableEntries(db.groups) + CountTableEntries(db.iconData) + CountTableEntries(db.ungrouped)
end

local function FindLegacyDynamicSpec(db)
    if type(db) ~= "table" or type(db.specs) ~= "table" then
        return nil, nil
    end

    local currentSpecID
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            currentSpecID = GetSpecializationInfo(specIndex)
        end
    end

    local source = currentSpecID and db.specs[currentSpecID]
    if HasDynamicPayload(source) then
        return source, currentSpecID
    end

    source = db.specs[0]
    if HasDynamicPayload(source) then
        return source, 0
    end

    for specID, specDB in pairs(db.specs) do
        if HasDynamicPayload(specDB) then
            return specDB, specID
        end
    end

    return nil, nil
end

local function CopyStoredValue(value)
    if type(value) ~= "table" then return value end
    if CopyTable then return CopyTable(value) end
    local copy = {}
    for k, v in pairs(value) do
        copy[CopyStoredValue(k)] = CopyStoredValue(v)
    end
    return copy
end

local function MergeMissingEntries(target, source)
    target = type(target) == "table" and target or {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            if target[key] == nil then
                target[key] = CopyStoredValue(value)
            end
        end
    end
    return target
end

local function ScoreDynamicPayload(db)
    if type(db) ~= "table" then return 0 end
    return (CountTableEntries(db.iconData) * 10)
        + CountTableEntries(db.groups)
        + CountTableEntries(db.ungrouped)
end

local NormalizePresetIconData
local NormalizePresetIconDB

local function FindFallbackDynamicProfile(currentDB, includeDeepSnapshots)
    local profiles = DDingUI.db and DDingUI.db.profiles
    if type(profiles) ~= "table" then return nil, nil, nil, 0 end

    local bestSource, bestProfileName, bestSourceKey
    local bestScore = 0

    local function considerSource(source, profileName, sourceKey)
        local score = ScoreDynamicPayload(source)
        if source and score > bestScore then
            bestSource = source
            bestProfileName = profileName
            bestSourceKey = sourceKey
            bestScore = score
        end
    end

    local function considerDynamicDB(dynDB, profileName, label)
        if type(dynDB) ~= "table" or dynDB == currentDB then return end

        if HasDynamicPayload(dynDB) then
            considerSource(dynDB, profileName, label or "root")
        end

        local legacySource, legacySourceKey = FindLegacyDynamicSpec(dynDB)
        if legacySource then
            considerSource(legacySource, profileName, (label or "root") .. ".specs." .. tostring(legacySourceKey or "?"))
        end
    end

    for profileName, profileDB in pairs(profiles) do
        if type(profileDB) == "table" then
            considerDynamicDB(profileDB.dynamicIcons, profileName, "dynamicIcons")

            local specProfiles = profileDB.specProfiles
            if type(specProfiles) == "table" then
                considerDynamicDB(specProfiles.dynamicIcons, profileName, "specProfiles.dynamicIcons")
            end

            if includeDeepSnapshots then
                local specData = profileDB.specData
                if type(specData) == "table" then
                    for specID, specDB in pairs(specData) do
                        if type(specDB) == "table" then
                            considerDynamicDB(specDB.dynamicIcons, profileName, "specData." .. tostring(specID) .. ".dynamicIcons")
                            local nestedProfiles = specDB.specProfiles
                            if type(nestedProfiles) == "table" then
                                considerDynamicDB(nestedProfiles.dynamicIcons, profileName, "specData." .. tostring(specID) .. ".specProfiles.dynamicIcons")
                            end
                        end
                    end
                end
            end
        end
    end

    return bestSource, bestProfileName, bestSourceKey, bestScore
end

local function GetDynamicDB()
    local profile = DDingUI.db.profile
    local db = rawget(profile, "dynamicIcons")
    if type(db) ~= "table" then
        local defaults = DDingUI.defaults and DDingUI.defaults.profile and DDingUI.defaults.profile.dynamicIcons
        db = type(defaults) == "table" and CopyStoredValue(defaults) or {}
        profile.dynamicIcons = db
    end

    db.iconData = db.iconData or {}
    db.ungrouped = db.ungrouped or {}
    db.groups = db.groups or {}

    -- Older DDingUI builds stored dynamic icons under dynamicIcons.specs[specID].
    -- The current renderer reads dynamicIcons.groups/iconData directly. Merge the
    -- legacy payload back into the root without deleting any newer root entries.
    local hadRootPayload = HasDynamicPayload(db)
    local rootIconCount = CountTableEntries(db.iconData)
    local legacySource, legacySourceKey = FindLegacyDynamicSpec(db)
    if legacySource and not db._legacySpecsPromoted and rootIconCount == 0 then
        db.groups = MergeMissingEntries(db.groups, legacySource.groups)
        db.iconData = MergeMissingEntries(db.iconData, legacySource.iconData)
        db.ungrouped = MergeMissingEntries(db.ungrouped, legacySource.ungrouped)
        db.ungroupedPositions = MergeMissingEntries(db.ungroupedPositions, legacySource.ungroupedPositions)
        if not hadRootPayload then
            db.enabled = legacySource.enabled ~= false
        end
        db._legacySpecsPromoted = legacySourceKey or true
    end

    NormalizePresetIconDB(db)

    return db
end

function CustomIcons:RecoverDynamicIcons(includeDeepSnapshots)
    if not DDingUI.db or not DDingUI.db.profile then return nil end

    local profile = DDingUI.db.profile
    profile.dynamicIcons = profile.dynamicIcons or {}
    local db = profile.dynamicIcons
    db.iconData = db.iconData or {}
    db.ungrouped = db.ungrouped or {}
    db.groups = db.groups or {}

    local source, profileName, sourceKey = FindFallbackDynamicProfile(db, includeDeepSnapshots == true)
    if not source or CountTableEntries(source.iconData) == 0 then
        return db, nil, nil, CountTableEntries(db.groups), CountTableEntries(db.iconData)
    end

    db.groups = MergeMissingEntries(db.groups, source.groups)
    db.iconData = MergeMissingEntries(db.iconData, source.iconData)
    db.ungrouped = MergeMissingEntries(db.ungrouped, source.ungrouped)
    db.ungroupedPositions = MergeMissingEntries(db.ungroupedPositions, source.ungroupedPositions)
    db.enabled = source.enabled ~= false
    db._recoveredFromProfile = profileName or true
    db._recoveredFromSpec = sourceKey
    db._recoveredIconCount = CountTableEntries(source.iconData)
    db._recoveredGroupCount = CountTableEntries(source.groups)
    NormalizePresetIconDB(db)

    return db, profileName, sourceKey, CountTableEntries(db.groups), CountTableEntries(db.iconData)
end

function CustomIcons:GetDynamicIconMigrationReport(includeDeepSnapshots)
    local profile = DDingUI.db and DDingUI.db.profile
    local db = profile and profile.dynamicIcons
    local legacySource, legacySourceKey = FindLegacyDynamicSpec(db)
    local fallbackSource, fallbackProfileName, fallbackSourceKey, fallbackScore = FindFallbackDynamicProfile(db, includeDeepSnapshots == true)

    local report = {
        hasDB = type(db) == "table",
        enabled = db and db.enabled ~= false,
        rootGroups = CountTableEntries(db and db.groups),
        rootIcons = CountTableEntries(db and db.iconData),
        rootUngrouped = CountTableEntries(db and db.ungrouped),
        promotedFrom = db and db._legacySpecsPromoted,
        recoveredFromProfile = db and db._recoveredFromProfile,
        recoveredFromSpec = db and db._recoveredFromSpec,
        legacySpecKey = legacySourceKey,
        legacyGroups = CountTableEntries(legacySource and legacySource.groups),
        legacyIcons = CountTableEntries(legacySource and legacySource.iconData),
        legacyUngrouped = CountTableEntries(legacySource and legacySource.ungrouped),
        fallbackProfile = fallbackProfileName,
        fallbackSourceKey = fallbackSourceKey,
        fallbackScore = fallbackScore or 0,
        fallbackGroups = CountTableEntries(fallbackSource and fallbackSource.groups),
        fallbackIcons = CountTableEntries(fallbackSource and fallbackSource.iconData),
        fallbackUngrouped = CountTableEntries(fallbackSource and fallbackSource.ungrouped),
        includeDeepSnapshots = includeDeepSnapshots == true,
    }

    report.canPromoteLegacy = report.hasDB and not report.promotedFrom and report.rootIcons == 0 and report.legacyIcons > 0
    report.hasFallback = report.fallbackScore > 0 and report.fallbackIcons > 0
    return report
end

local function BuildUniqueDBKey(prefix, targetTable)
    local base = tostring(math.floor((GetTime and GetTime() or 0) * 1000))
    local key = prefix .. base
    local n = 1
    while targetTable and targetTable[key] do
        n = n + 1
        key = prefix .. base .. "_" .. n
    end
    return key
end

local function EnsureLoadConditions(iconData)
    EnsureIconSettings(iconData)
    iconData.settings.loadConditions = iconData.settings.loadConditions or {
        enabled = false,
        specs = {},
        inCombat = false,
        outOfCombat = false,
    }
end

-- ------------------------
-- Icon updates
-- ------------------------
-- [FIX] IsCooldownFrameActive: 이전 패치에서 정의 제거됨 — forward declaration 유지 (nil)
-- L830 호출부도 GetCooldownTimes 기반으로 교체되었으므로 더 이상 보안 필요 없음

-- [CDM CDM 방식] 아이템 → 스펠 쿨다운 매핑
-- 아이템 쿨다운 API가 전투 중 늦게 갱신될 때 스펠 쿨다운으로 폴백
local ITEM_SPELL_MAP = {
    [5512]   = 6262,    -- Healthstone
    [224464] = 452930,  -- Demonic Healthstone
    [255327] = 336126,  -- PvP medallion
    [255616] = 336126,  -- PvP medallion
    [241304] = 1234768, -- Silvermoon Health Potion R2
    [241305] = 1234768, -- Silvermoon Health Potion R1
    [241308] = 1236616, -- Light's Potential R2
    [241309] = 1236616, -- Light's Potential R1
    [245898] = 1236616, -- Light's Potential alt
    [245897] = 1236616, -- Light's Potential alt
    [241288] = 1236994, -- Potion of Recklessness R2
    [241289] = 1236994, -- Potion of Recklessness R1
    [245902] = 1236994, -- Potion of Recklessness alt
    [245903] = 1236994, -- Potion of Recklessness alt
    [241300] = 1234770, -- Lightfused Mana Potion R2
    [241301] = 1234770, -- Lightfused Mana Potion R1
    [245917] = 1234770, -- Lightfused Mana Potion alt
    [245916] = 1234770, -- Lightfused Mana Potion alt
    [211878] = 431416,  -- Algari Healing Potion R1
    [211879] = 431416,  -- Algari Healing Potion R2
    [211880] = 431416,  -- Algari Healing Potion R3
}
local ITEM_COMBAT_LOCKOUT_ITEMS = {
    [5512] = true,
    [224464] = true,
}
local ITEM_COMBAT_LOCKOUT_SPELLS = {
    [6262] = true,
    [452930] = true,
}
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local FALLBACK_SPELL_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
local FALLBACK_ITEM_ICON = "Interface\\Icons\\INV_Potion_93"
local FALLBACK_SLOT_ICON = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01"
local FALLBACK_RACIAL_ICON = "Interface\\Icons\\Spell_magic_polymorphrabbit"
local CUSTOM_ICON_EFFECT_GRACE_SECONDS = 1.5
local CUSTOM_AURA_ICON_TEXTURES = {
    [1236616] = 7548911, -- Light's Potential
    [1236994] = 7548916, -- Potion of Recklessness
    [1239479] = "Interface\\Icons\\INV_12_Profession_Alchemy_VoidPotion_Blue", -- Potion of Devoured Dreams
    [374968] = 4622479, -- Time Spiral
    [2825] = "Interface\\Icons\\Spell_Nature_BloodLust", -- Bloodlust
}
local CUSTOM_AURA_ICON_ITEM_FALLBACKS = {
    [1236616] = 241308, -- Light's Potential
    [1236994] = 241288, -- Potion of Recklessness
    [1239479] = 241294, -- Potion of Devoured Dreams
}

local function IsQuestionTexture(texture)
    if texture == 0 or texture == "" then return true end
    if type(texture) == "string" then
        return texture:gsub("/", "\\"):lower():find("inv_misc_questionmark", 1, true) ~= nil
    end
    return texture == 134400 or texture == QUESTION_MARK_ICON or texture == 0 or texture == ""
end

local function NonQuestionTexture(texture, fallback)
    if texture and not IsQuestionTexture(texture) then return texture end
    if fallback and not IsQuestionTexture(fallback) then return fallback end
    return FALLBACK_SPELL_ICON
end

local function GetCustomAuraPresetIconTexture(spellID)
    local texture = CUSTOM_AURA_ICON_TEXTURES[tonumber(spellID)]
    if texture and not IsQuestionTexture(texture) then return texture end
    return nil
end

local BLOODLUST_AURA_IDS = {
    2825, 32182, 80353, 90355, 160452, 264667, 390386,
    146555, 178207, 230935, 256740, 292686, 309658, 381301, 444257,
}
local BLOODLUST_DEBUFFS = {
    [57723]  = 32182,  -- Exhaustion -> Heroism
    [57724]  = 2825,   -- Sated -> Bloodlust
    [80354]  = 80353,  -- Temporal Displacement -> Time Warp
    [95809]  = 90355,  -- Insanity -> Ancient Hysteria
    [160455] = 264667, -- Fatigued -> Primal Rage
    [264689] = 264667, -- Fatigued -> Primal Rage
    [390435] = 390386, -- Exhaustion -> Fury of the Aspects
}
local bloodlustDebuffInstanceID
local CUSTOM_TIMED_AURA_CONFIGS = {
    [1236616] = { duration = 30, trigger = "spellcast" },   -- Light's Potential
    [1236994] = { duration = 30, trigger = "spellcast" },   -- Potion of Recklessness
    [1239479] = { duration = 10, trigger = "spellcast" },   -- Potion of Devoured Dreams
    [374968]  = { duration = 10, trigger = "timespiral" },  -- Time Spiral
    [2825]    = { duration = 40, trigger = "bloodlust" },   -- Bloodlust family
}
local TIME_SPIRAL_TRIGGERS = {
    [48265] = true, [195072] = true, [189110] = true, [1850] = true,
    [252216] = true, [358267] = true, [186257] = true, [1953] = true,
    [212653] = true, [361138] = true, [119085] = true, [190784] = true,
    [73325] = true, [2983] = true, [192063] = true, [58875] = true,
    [79206] = true, [48020] = true, [6544] = true,
}
local TIME_SPIRAL_GLOW_FILTERS = {
    { talentID = 427640, spells = { 198793, 370965, 195072 } }, -- Inertia -> Vengeful Retreat, The Hunt, Fel Rush
    { talentID = 427794, spells = { 195072 } },                 -- Dash of Chaos -> Fel Rush
    { talentID = 385899, spells = { 385899 } },                 -- Soulburn
}
local TIME_SPIRAL_GLOW_SUPPRESS_SECONDS = 1.5
local timeSpiralGlowSuppressSpells = {}
local timeSpiralSuppressGlowUntil = 0
local AURA_EQUIVALENT_IDS = {}
for _, spellID in ipairs(BLOODLUST_AURA_IDS) do
    AURA_EQUIVALENT_IDS[spellID] = BLOODLUST_AURA_IDS
end

local function GetTimedAuraDebugKey(spellIDOrKey)
    if type(spellIDOrKey) == "string" then
        return spellIDOrKey
    end
    spellIDOrKey = tonumber(spellIDOrKey)
    if spellIDOrKey == 2825 then return "bloodlust" end
    if spellIDOrKey == 374968 then return "timespiral" end
    return nil
end

local function RecordTimedAuraDebug(spellIDOrKey, field, detail)
    local key = GetTimedAuraDebugKey(spellIDOrKey)
    if not key or not field then return nil end

    runtime.timedAuraDebug = runtime.timedAuraDebug or {}
    local bucket = runtime.timedAuraDebug[key]
    if not bucket then
        bucket = {}
        runtime.timedAuraDebug[key] = bucket
    end

    bucket[field] = (tonumber(bucket[field]) or 0) + 1
    bucket.lastEvent = field
    bucket.lastDetail = detail
    bucket.lastAt = GetTime and GetTime() or 0
    return bucket
end

local function RebuildTimeSpiralGlowFilters()
    for spellID in pairs(timeSpiralGlowSuppressSpells) do
        timeSpiralGlowSuppressSpells[spellID] = nil
    end

    for _, entry in ipairs(TIME_SPIRAL_GLOW_FILTERS) do
        local hasTalent = false
        if IsPlayerSpell then
            pcall(function()
                hasTalent = IsPlayerSpell(entry.talentID) == true
            end)
        end
        if hasTalent then
            for _, spellID in ipairs(entry.spells or {}) do
                timeSpiralGlowSuppressSpells[spellID] = true
            end
        end
    end
end

local function SetStableIconTexture(iconFrame, texture, allowFallback)
    if not iconFrame or not iconFrame.icon then return end
    if IsQuestionTexture(texture) then
        texture = nil
    end
    if texture then
        iconFrame._lastResolvedTexture = texture
        if iconFrame._textureCacheKey then
            runtime.textureCache[iconFrame._textureCacheKey] = texture
        end
        iconFrame.icon:SetTexture(texture)
    elseif iconFrame._textureCacheKey and runtime.textureCache[iconFrame._textureCacheKey] then
        iconFrame._lastResolvedTexture = runtime.textureCache[iconFrame._textureCacheKey]
        iconFrame.icon:SetTexture(iconFrame._lastResolvedTexture)
    elseif iconFrame._lastResolvedTexture then
        iconFrame.icon:SetTexture(iconFrame._lastResolvedTexture)
    elseif allowFallback then
        iconFrame.icon:SetTexture(iconFrame._fallbackTexture or FALLBACK_SPELL_ICON)
    end
end

local function ResolveItemTexture(itemID, slotID)
    local tex = nil
    if slotID then
        tex = GetInventoryItemTexture("player", slotID)
        if IsQuestionTexture(tex) then
            tex = nil
        end
    end
    if not tex and itemID and C_Item and C_Item.GetItemIconByID then
        tex = C_Item.GetItemIconByID(itemID)
        if IsQuestionTexture(tex) then
            tex = nil
        end
    end
    if not tex and itemID then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
        tex = itemTexture
        if IsQuestionTexture(tex) then
            tex = nil
        end
    end
    if not tex and itemID and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return tex
end

local function ResolveSpellTexture(spellID, fallbackTexture)
    local tex = GetCustomAuraPresetIconTexture(spellID)
    if tex then return tex end

    tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
    if IsQuestionTexture(tex) then
        tex = nil
    end
    if not tex and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        tex = info and info.iconID
        if IsQuestionTexture(tex) then
            tex = nil
        end
    end
    if not tex then
        local fallbackItemID = CUSTOM_AURA_ICON_ITEM_FALLBACKS[tonumber(spellID)]
        if fallbackItemID then
            tex = ResolveItemTexture(fallbackItemID)
        end
    end
    if not tex and fallbackTexture and not IsQuestionTexture(fallbackTexture) then
        tex = fallbackTexture
    end
    if not tex and C_Spell and C_Spell.RequestLoadSpellData then
        C_Spell.RequestLoadSpellData(spellID)
    end
    return tex
end

function CustomIcons.ResolveCustomTimedAuraStateTexture(spellID, config, iconSpellID)
    if config and config.trigger == "trinket_effect" and config.iconTexture then
        return config.iconTexture
    end
    local stateID = tonumber(spellID)
    local displayID = tonumber(iconSpellID)
    if displayID and displayID ~= stateID then
        local tex = ResolveSpellTexture(displayID)
        if tex and not IsQuestionTexture(tex) then
            return tex
        end
    end
    return ResolveSpellTexture(displayID or stateID, config and config.iconTexture)
end

local function GetStoredIconTexture(iconData)
    if iconData and (iconData.type == "spell" or iconData.type == "aura") then
        local preset = GetCustomAuraPresetIconTexture(iconData.id)
        if preset then return preset end
    end

    local settings = iconData and iconData.settings
    if type(settings) ~= "table" then return nil end
    local texture = settings.iconTexture or settings.fallbackIcon or settings.icon
    if texture and not IsQuestionTexture(texture) then return texture end
    return nil
end

local function EnsureStoredIconTexture(iconData)
    if not iconData then return nil end
    iconData.settings = iconData.settings or {}
    if iconData.type == "spell" or iconData.type == "aura" then
        local preset = GetCustomAuraPresetIconTexture(iconData.id)
        if preset then
            iconData.settings.iconTexture = preset
            iconData.settings.auraIcon = preset
            return preset
        end
    end

    local stored = GetStoredIconTexture(iconData)
    if stored then return stored end

    local texture
    if iconData.type == "item" then
        texture = ResolveItemTexture(iconData.id)
    elseif iconData.type == "spell" or iconData.type == "aura" then
        texture = ResolveSpellTexture(iconData.id)
    elseif iconData.type == "slot" or iconData.type == "trinketProc" then
        local itemID = iconData.slotID and CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID)
        texture = ResolveItemTexture(itemID, iconData.slotID)
    elseif iconData.type == "racial" then
        local racials = DDingUI.CustomIconRacials
        texture = racials and racials:GetTexture(FALLBACK_RACIAL_ICON) or FALLBACK_RACIAL_ICON
    end

    if texture and not IsQuestionTexture(texture) then
        iconData.settings.iconTexture = texture
        return texture
    end
    return nil
end

NormalizePresetIconData = function(iconData)
    if type(iconData) ~= "table" or not (iconData.type == "spell" or iconData.type == "aura") then return false end
    local preset = GetCustomAuraPresetIconTexture(iconData.id)
    if not preset then return false end

    iconData.settings = iconData.settings or {}
    if iconData.settings.iconTexture ~= preset or iconData.settings.auraIcon ~= preset then
        iconData.settings.iconTexture = preset
        iconData.settings.auraIcon = preset
        return true
    end
    return false
end

NormalizePresetIconDB = function(db, ownerProfile, updateRuntime)
    local iconDataDB = db and db.iconData
    if type(iconDataDB) ~= "table" then return false end

    local changed = false
    for _, iconData in pairs(iconDataDB) do
        EnsureIconSettings(iconData)
        if NormalizePresetIconData(iconData) then
            changed = true
        end
    end

    db.groups = type(db.groups) == "table" and db.groups or {}
    db.ungrouped = type(db.ungrouped) == "table" and db.ungrouped or {}
    db.ungroupedPositions = type(db.ungroupedPositions) == "table" and db.ungroupedPositions or {}

    local activeProfile = DDingUI.db and DDingUI.db.profile
    local profile = ownerProfile or activeProfile
    local touchRuntime = updateRuntime
    if touchRuntime == nil then
        touchRuntime = profile == activeProfile
    end
    local gsGroups = profile and profile.groupSystem and profile.groupSystem.groups
    local referencedSourceGroups = {}
    local cdmSourceGroups = {}
    local orderPreferred = {}

    if type(gsGroups) == "table" then
        for groupName, groupSettings in pairs(gsGroups) do
            local sourceKey = type(groupSettings) == "table" and groupSettings.sourceGroupKey
            if sourceKey then
                referencedSourceGroups[sourceKey] = true
                if type(groupName) == "string" then
                    cdmSourceGroups[groupName] = sourceKey
                end
            end
            local iconOrder = type(groupSettings) == "table" and groupSettings.iconOrder
            if type(iconOrder) == "table" then
                for _, token in ipairs(iconOrder) do
                    if type(token) == "string" then
                        local iconKey = token:match("^dyn:(.+)$")
                        if iconKey then
                            orderPreferred[iconKey] = true
                        end
                    end
                end
            end
        end
    end

    local memberships = {}
    for groupKey, group in pairs(db.groups) do
        local icons = type(group) == "table" and group.icons
        if type(icons) == "table" then
            local seenInGroup = {}
            for i = #icons, 1, -1 do
                local iconKey = icons[i]
                if type(iconKey) ~= "string" or not iconDataDB[iconKey] or seenInGroup[iconKey] then
                    table.remove(icons, i)
                    changed = true
                else
                    seenInGroup[iconKey] = true
                    memberships[iconKey] = memberships[iconKey] or {}
                    memberships[iconKey][groupKey] = true
                end
            end
        end
    end

    local function AddIconToGroup(group, iconKey)
        if type(group) ~= "table" or not iconKey then return false end
        group.icons = type(group.icons) == "table" and group.icons or {}
        for _, existingKey in ipairs(group.icons) do
            if existingKey == iconKey then return false end
        end
        group.icons[#group.icons + 1] = iconKey
        return true
    end

    local function AddOrderToken(groupSettings, iconKey)
        if type(groupSettings) ~= "table" or not iconKey then return false end
        groupSettings.iconOrder = type(groupSettings.iconOrder) == "table" and groupSettings.iconOrder or {}
        local token = "dyn:" .. tostring(iconKey)
        for _, existingToken in ipairs(groupSettings.iconOrder) do
            if existingToken == token then return false end
        end
        groupSettings.iconOrder[#groupSettings.iconOrder + 1] = token
        return true
    end

    for sourceKey, group in pairs(db.groups) do
        local linkedGroupName = type(group) == "table" and group.linkedCDMGroup
        local preferredSourceKey = linkedGroupName and cdmSourceGroups[linkedGroupName]
        if preferredSourceKey and preferredSourceKey ~= sourceKey and db.groups[preferredSourceKey] then
            local preferredGroup = db.groups[preferredSourceKey]
            local icons = type(group.icons) == "table" and group.icons
            if type(icons) == "table" then
                for _, iconKey in ipairs(icons) do
                    if iconDataDB[iconKey] and AddIconToGroup(preferredGroup, iconKey) then
                        changed = true
                        local groupSettings = gsGroups and gsGroups[linkedGroupName]
                        if AddOrderToken(groupSettings, iconKey) then
                            changed = true
                        end
                    end
                end
            end
            db.groups[sourceKey] = nil
            changed = true
        end
    end

    memberships = {}
    for groupKey, group in pairs(db.groups) do
        local icons = type(group) == "table" and group.icons
        if type(icons) == "table" then
            for _, iconKey in ipairs(icons) do
                memberships[iconKey] = memberships[iconKey] or {}
                memberships[iconKey][groupKey] = true
            end
        end
    end

    local function GetLinkedGroupName(iconKey, iconData)
        local settings = type(iconData) == "table" and iconData.settings
        if type(settings) == "table" and type(settings.targetCDMGroup) == "string" then
            return settings.targetCDMGroup
        end
        for groupKey in pairs(memberships[iconKey] or {}) do
            local group = db.groups[groupKey]
            if type(group) == "table" and type(group.linkedCDMGroup) == "string" then
                return group.linkedCDMGroup
            end
        end
        return nil
    end

    local function GetAuraIdentity(iconKey, iconData)
        if type(iconData) ~= "table" or iconData.type ~= "aura" then return nil end
        local spellID = tonumber(iconData.id)
        if not spellID then return nil end
        if AURA_EQUIVALENT_IDS[spellID] then
            spellID = 2825
        end
        local settings = type(iconData.settings) == "table" and iconData.settings or nil
        if not CUSTOM_TIMED_AURA_CONFIGS[spellID]
            and not (settings and settings.customAuraDuration)
            and not GetLinkedGroupName(iconKey, iconData)
        then
            return nil
        end
        return (GetLinkedGroupName(iconKey, iconData) or "aura") .. ":" .. tostring(spellID)
    end

    local function GetIconScore(iconKey, iconData)
        local score = 0
        local linkedGroupName = GetLinkedGroupName(iconKey, iconData)
        local preferredSourceKey = linkedGroupName and cdmSourceGroups[linkedGroupName]
        if orderPreferred[iconKey] then
            score = score + 4000
        end
        for groupKey in pairs(memberships[iconKey] or {}) do
            if groupKey == preferredSourceKey then
                score = score + 3000
            elseif referencedSourceGroups[groupKey] then
                score = score + 1000
            else
                score = score + 100
            end
        end
        if db.ungrouped[iconKey] then
            score = score - 10
        end
        return score
    end

    local bestByIdentity = {}
    local removeKeys = {}
    for iconKey, iconData in pairs(iconDataDB) do
        local identity = GetAuraIdentity(iconKey, iconData)
        if identity then
            local currentBest = bestByIdentity[identity]
            if not currentBest then
                bestByIdentity[identity] = iconKey
            else
                local score = GetIconScore(iconKey, iconData)
                local bestScore = GetIconScore(currentBest, iconDataDB[currentBest])
                if score > bestScore or (score == bestScore and tostring(iconKey) < tostring(currentBest)) then
                    removeKeys[currentBest] = true
                    bestByIdentity[identity] = iconKey
                else
                    removeKeys[iconKey] = true
                end
            end
        end
    end

    local function RemoveOrderToken(iconKey)
        if type(gsGroups) ~= "table" then return false end
        local token = "dyn:" .. tostring(iconKey)
        local removed = false
        for _, groupSettings in pairs(gsGroups) do
            local iconOrder = type(groupSettings) == "table" and groupSettings.iconOrder
            if type(iconOrder) == "table" then
                for i = #iconOrder, 1, -1 do
                    if iconOrder[i] == token then
                        table.remove(iconOrder, i)
                        removed = true
                    end
                end
            end
        end
        return removed
    end

    for iconKey in pairs(removeKeys) do
        iconDataDB[iconKey] = nil
        db.ungrouped[iconKey] = nil
        db.ungroupedPositions[iconKey] = nil
        if RemoveOrderToken(iconKey) then
            changed = true
        end
        for _, group in pairs(db.groups) do
            local icons = type(group) == "table" and group.icons
            if type(icons) == "table" then
                for i = #icons, 1, -1 do
                    if icons[i] == iconKey then
                        table.remove(icons, i)
                    end
                end
            end
        end
        if touchRuntime then
            local frame = runtime.iconFrames and runtime.iconFrames[iconKey]
            if frame and frame.Hide then
                frame:Hide()
            end
            if runtime.iconFrames then
                runtime.iconFrames[iconKey] = nil
            end
        end
        changed = true
    end

    return changed
end

function CustomIcons:NormalizeStoredProfile(profile)
    if type(profile) ~= "table" then return false end

    local db = rawget(profile, "dynamicIcons")
    if type(db) ~= "table" then return false end

    db.groups = type(db.groups) == "table" and db.groups or {}
    db.iconData = type(db.iconData) == "table" and db.iconData or {}
    db.ungrouped = type(db.ungrouped) == "table" and db.ungrouped or {}
    db.ungroupedPositions = type(db.ungroupedPositions) == "table" and db.ungroupedPositions or {}

    local changed = false
    local groupSystem = rawget(profile, "groupSystem")
    local gsGroups = type(groupSystem) == "table" and groupSystem.groups
    if type(gsGroups) == "table" then
        for _, groupName in ipairs({ "Cooldowns", "Buffs", "Utility" }) do
            local groupSettings = gsGroups[groupName]
            if type(groupSettings) == "table" then
                groupSettings.groupType = "cdm"

                local preferredKey = groupSettings.sourceGroupKey
                local preferredGroup = preferredKey and db.groups[preferredKey]
                if preferredGroup and preferredGroup.linkedCDMGroup == nil then
                    preferredGroup.linkedCDMGroup = groupName
                    changed = true
                end

                if not preferredGroup or preferredGroup.linkedCDMGroup ~= groupName then
                    local orderSet = {}
                    for _, token in ipairs(groupSettings.iconOrder or {}) do
                        if type(token) == "string" then
                            local iconKey = token:match("^dyn:(.+)$")
                            if iconKey then
                                orderSet[iconKey] = true
                            end
                        end
                    end

                    local bestKey
                    local bestMatches = -1
                    local bestCount = -1
                    for sourceKey, sourceGroup in pairs(db.groups) do
                        if type(sourceGroup) == "table" and sourceGroup.linkedCDMGroup == groupName then
                            local matches = 0
                            local count = 0
                            for _, iconKey in ipairs(sourceGroup.icons or {}) do
                                count = count + 1
                                if orderSet[iconKey] then
                                    matches = matches + 1
                                end
                            end
                            if matches > bestMatches
                                or (matches == bestMatches and count > bestCount)
                                or (matches == bestMatches and count == bestCount
                                    and (not bestKey or tostring(sourceKey) < tostring(bestKey)))
                            then
                                bestKey = sourceKey
                                bestMatches = matches
                                bestCount = count
                            end
                        end
                    end

                    if groupSettings.sourceGroupKey ~= bestKey then
                        groupSettings.sourceGroupKey = bestKey
                        changed = true
                    end
                end
            end
        end
    end

    if NormalizePresetIconDB(db, profile, false) then
        changed = true
    end
    return changed
end

local function AddAuraCandidate(candidates, seen, spellID)
    spellID = tonumber(spellID)
    if spellID and spellID > 0 and not seen[spellID] then
        seen[spellID] = true
        candidates[#candidates + 1] = spellID
    end
end

local function AddAuraCandidatesFromValue(candidates, seen, value)
    if type(value) == "number" then
        AddAuraCandidate(candidates, seen, value)
    elseif type(value) == "string" then
        for id in string.gmatch(value, "(%d+)") do
            AddAuraCandidate(candidates, seen, id)
        end
    elseif type(value) == "table" then
        for _, id in pairs(value) do
            AddAuraCandidatesFromValue(candidates, seen, id)
        end
    end
end

local function BuildAuraCandidateIDs(iconFrame, iconData)
    local candidates, seen = {}, {}
    local spellID = iconData and tonumber(iconData.id)
    AddAuraCandidate(candidates, seen, iconFrame and iconFrame._cachedAuraSpellID)
    AddAuraCandidate(candidates, seen, spellID)

    local equivalentIDs = spellID and AURA_EQUIVALENT_IDS[spellID]
    if equivalentIDs then
        AddAuraCandidatesFromValue(candidates, seen, equivalentIDs)
    end

    local settings = iconData and iconData.settings
    if settings then
        AddAuraCandidatesFromValue(candidates, seen, settings.auraAliases)
        -- Legacy bloodlust quick-add used fallbackItems for spell aliases.
        if iconData.type == "aura" then
            AddAuraCandidatesFromValue(candidates, seen, settings.fallbackItems)
        end
    end

    return candidates
end

local function GetCustomTimedAuraConfig(iconData)
    if not iconData or iconData.type ~= "aura" then return nil end

    local spellID = tonumber(iconData.id)
    if not spellID then return nil end

    local settings = iconData.settings or {}
    local stateID = tonumber(settings.customAuraStateID) or spellID
    if AURA_EQUIVALENT_IDS[spellID] then
        stateID = 2825
    end

    local preset = CUSTOM_TIMED_AURA_CONFIGS[stateID]
    local duration = tonumber((preset and preset.duration) or settings.customAuraDuration)
    if not duration or duration <= 0 then return nil end

    return {
        stateID = stateID,
        duration = duration,
        trigger = (preset and preset.trigger) or settings.customAuraTrigger or "spellcast",
        iconTexture = (preset and preset.iconTexture) or GetStoredIconTexture(iconData) or ResolveSpellTexture(spellID),
    }
end

local function IsEventDrivenCustomTimedAuraConfig(config)
    if not config then return false end
    return config.trigger == "bloodlust"
        or config.trigger == "timespiral"
        or config.trigger == "trinket_effect"
end

local function BuildTimedAuraData(spellID, state)
    return {
        spellId = spellID,
        startTime = state.startTime,
        duration = state.duration,
        expirationTime = state.expirationTime,
        applications = tonumber(state.stacks) or 0,
        icon = state.iconTexture,
        __ddinguiTimedAura = true,
    }
end

local function GetAuraFieldSafe(aura, key)
    if not aura or not key then return nil end
    local ok, value = pcall(function()
        return aura[key]
    end)
    if ok then return value end
    return nil
end

local function GetAuraSpellIDSafe(aura)
    if not aura then return nil end
    local ok, spellID = pcall(function()
        local sid = GetAuraFieldSafe(aura, "spellId")
        if not sid then return nil end
        if type(sid) == "number" then
            if canaccessvalue and not canaccessvalue(sid) then
                return nil
            end
            return sid
        end
        return tonumber(sid)
    end)
    if ok then
        local safeOK, value = pcall(function()
            if spellID == nil then return nil end
            local spellIDType = type(spellID)
            if spellIDType == "number" then
                if canaccessvalue and not canaccessvalue(spellID) then
                    return nil
                end
                return spellID
            end
            if spellIDType == "string" then
                return tonumber(spellID)
            end
            return nil
        end)
        if safeOK then return value end
    end
    return nil
end

local function SafeNumber(value)
    if value == nil then return nil end
    if issecretvalue then
        local okSecret, secret = pcall(issecretvalue, value)
        if okSecret and secret then return nil end
    end
    local valueType = type(value)
    if valueType == "number" then
        if canaccessvalue and not canaccessvalue(value) then
            return nil
        end
        return value
    end
    if valueType == "string" then return tonumber(value) end
    return nil
end

function CustomIcons.GetEquippedSlotItemID(iconFrame, slotID)
    if not slotID or not GetInventoryItemID then return nil end

    local ok, rawItemID = pcall(GetInventoryItemID, "player", slotID)
    local itemID = ok and SafeNumber(rawItemID)
    if itemID then
        if iconFrame then
            iconFrame._lastInventoryItemID = itemID
            iconFrame._lastInventoryItemAt = GetTime and GetTime() or 0
        end
        return itemID
    end

    return iconFrame and iconFrame._lastInventoryItemID or nil
end

local function GetAuraNumberFieldSafe(aura, key)
    return SafeNumber(GetAuraFieldSafe(aura, key))
end

local function MaxSafeNumber(...)
    local best
    for i = 1, select("#", ...) do
        local value = SafeNumber(select(i, ...))
        if value and value > 0 and (not best or value > best) then
            best = value
        end
    end
    return best
end

local function HasRecentEffectState(iconFrame, now)
    if not iconFrame then return false end
    now = now or (GetTime and GetTime()) or 0
    local lastActive = MaxSafeNumber(iconFrame._ddLastDynamicActiveAt, iconFrame._ddLastAuraActiveAt, iconFrame._ddLastProcActiveAt)
    return lastActive and (now - lastActive) <= CUSTOM_ICON_EFFECT_GRACE_SECONDS
end

local function ScheduleEffectGraceUpdate(iconFrame)
    if not iconFrame or iconFrame._ddEffectGraceUpdatePending then return end
    iconFrame._ddEffectGraceUpdatePending = true
    C_Timer.After(CUSTOM_ICON_EFFECT_GRACE_SECONDS + 0.05, function()
        if iconFrame then
            iconFrame._ddEffectGraceUpdatePending = nil
        end
        if UpdateAllIcons then
            UpdateAllIcons("force", "aura")
        end
    end)
end

local MarkCustomTimedAuraExpired
local MarkCustomTimedAuraActive

local function NotifyCustomTimedAuraChanged(forceLayout)
    local mode = forceLayout or "force"
    if UpdateAllIcons then
        UpdateAllIcons(mode, "aura")
    end
end

function CustomIcons.ApplyManagedGroupTextOptions(frame)
    if not (frame and frame._ddIsManaged) then return end
    local renderer = DDingUI.GroupRenderer
    if not (renderer and renderer.ApplyDynamicIconTextOptions) then return end
    local container = frame._ddContainerRef
    frame._ddDynamicTextRetryCount = nil
    renderer:ApplyDynamicIconTextOptions(
        frame,
        frame._ddGroupName or (container and container._groupName),
        frame._groupSettings or (container and container._groupSettings)
    )
    if frame._ddManagedTextRetryPending then return end
    frame._ddManagedTextRetryPending = true
    local retryDelays = { 0, 0.05, 0.2 }
    local remainingRetries = #retryDelays
    for _, delay in ipairs(retryDelays) do
        C_Timer.After(delay, function()
            if frame and frame._ddManagedTextRetryPending then
                if frame._ddIsManaged then
                    local retryRenderer = DDingUI.GroupRenderer
                    if retryRenderer and retryRenderer.ApplyDynamicIconTextOptions then
                        local retryContainer = frame._ddContainerRef
                        frame._ddDynamicTextRetryCount = nil
                        retryRenderer:ApplyDynamicIconTextOptions(
                            frame,
                            frame._ddGroupName or (retryContainer and retryContainer._groupName),
                            frame._groupSettings or (retryContainer and retryContainer._groupSettings)
                        )
                    end
                end
                remainingRetries = remainingRetries - 1
                if remainingRetries <= 0 then
                    frame._ddManagedTextRetryPending = nil
                end
            end
        end)
    end
end

function CustomIcons.ManagedVisualLocked(frame)
    if not (frame and frame._ddIsManaged) then return false end
    return frame._ddInactiveGray == true
        or frame._ddForcedInactiveGray == true
        or frame._ddManagedAuraExpired == true
        or frame._ddCombatVisible == false
end

function CustomIcons.StopIconDesatUpdater(frame)
    local updater = frame and frame._cdmDesatUpdater
    if not updater then return end
    updater:Hide()
    updater.ownerFrame = nil
    updater.spellID = nil
    updater.durObj = nil
    updater.targetIcon = nil
end

function CustomIcons.RestoreActiveIconVisual(frame)
    if not frame then return end
    if CustomIcons.ManagedVisualLocked(frame) then
        CustomIcons.StopIconDesatUpdater(frame)
        return
    end
    if frame.Show then
        frame:Show()
    end
    local alphaLocked = IsFlightHideAlphaLocked()
    if frame.SetAlpha and not alphaLocked then
        frame:SetAlpha(1)
        frame._ddLastGroupAlpha = 1
    end
    local icon = frame.icon or frame.Icon
    if icon then
        if icon.Show then icon:Show() end
        if icon.SetAlpha and not alphaLocked then icon:SetAlpha(1) end
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        if icon.SetDesaturation then icon:SetDesaturation(0) end
    end
    frame._ddManagedAuraExpired = nil
    frame._ddCombatKeepAlive = nil
    frame._ddCombatVisible = nil
    frame._ddCombatMissingSince = nil
end

function CustomIcons.HideManagedIconBorderLayers(frame)
    if not frame then return end
    if frame.border then
        if ShowTextureBorder then
            ShowTextureBorder(frame.border, false)
        end
        if frame.border.SetAlpha then
            frame.border:SetAlpha(0)
        end
        if frame.border.Hide then
            frame.border:Hide()
        end
    end
    local borders = frame._ddBorders
    if type(borders) == "table" then
        for _, borderTex in ipairs(borders) do
            if borderTex then
                if borderTex.SetAlpha then borderTex:SetAlpha(0) end
                if borderTex.SetShown then borderTex:SetShown(false) end
                if borderTex.Hide then borderTex:Hide() end
            end
        end
    end
end

function CustomIcons.SuppressExpiredIconVisual(frame)
    if not frame then return end
    if frame.SetAlpha then
        frame:SetAlpha(0)
        frame._ddLastGroupAlpha = 0
    end
    local icon = frame.icon or frame.Icon
    if icon and icon.SetAlpha then
        icon:SetAlpha(0)
    end
    if frame.cooldown then
        if frame.cooldown.Clear then frame.cooldown:Clear() end
        if frame.cooldown.Hide then frame.cooldown:Hide() end
    end
    if frame.Cooldown and frame.Cooldown ~= frame.cooldown then
        if frame.Cooldown.Clear then frame.Cooldown:Clear() end
        if frame.Cooldown.Hide then frame.Cooldown:Hide() end
    end
    if frame.count and frame.count.Hide then
        frame.count:Hide()
    end
    CustomIcons.HideManagedIconBorderLayers(frame)
    frame._ddCombatKeepAlive = nil
    frame._ddCombatVisible = false
    frame._ddCombatMissingSince = nil
    if frame.Hide then
        frame:Hide()
    end
end

local function DeactivateCustomTimedAura(spellID)
    if not runtime.customTimedAuras[spellID] then return false end
    runtime.customTimedAuras[spellID] = nil
    if MarkCustomTimedAuraExpired then
        MarkCustomTimedAuraExpired(spellID)
    end
    return true
end

function CustomIcons.ClearExpiredCustomTimedAuras()
    if not runtime.customTimedAuras then return false end
    local now = GetTime and GetTime() or 0
    local changed = false
    for spellID, state in pairs(runtime.customTimedAuras) do
        local expirationTime = state and SafeNumber(state.expirationTime)
        if not expirationTime or expirationTime <= now then
            if DeactivateCustomTimedAura(spellID) then
                changed = true
            end
        end
    end
    return changed
end

local function ResetAuraCooldownSpanCache(frame)
    if not frame then return end
    frame._ddAuraCooldownMode = nil
    frame._ddAuraCooldownStart = nil
    frame._ddAuraCooldownDuration = nil
end

local function ShouldApplyAuraCooldownSpan(frame, startTime, duration, mode)
    if not frame then return false end
    if frame._ddAuraCooldownMode == mode
        and frame._ddAuraCooldownStart
        and frame._ddAuraCooldownDuration
        and math.abs(frame._ddAuraCooldownStart - startTime) <= 0.05
        and math.abs(frame._ddAuraCooldownDuration - duration) <= 0.05
    then
        return false
    end
    frame._ddAuraCooldownMode = mode
    frame._ddAuraCooldownStart = startTime
    frame._ddAuraCooldownDuration = duration
    return true
end

MarkCustomTimedAuraExpired = function(spellID)
    local db = GetDynamicDB()
    local iconDataByKey = db and db.iconData
    if not iconDataByKey then return end

    for iconKey, frame in pairs(runtime.iconFrames) do
        local iconData = iconDataByKey[iconKey]
        local config = GetCustomTimedAuraConfig(iconData)
        if config and config.stateID == spellID and frame then
            frame._ddTimedAuraActiveUntil = nil
            frame._ddAuraActiveUntil = nil
            frame._ddProcActiveUntil = nil
            frame._ddLastDynamicActiveAt = nil
            frame._ddLastAuraActiveAt = nil
            frame._ddLastProcActiveAt = nil
            frame._wasVisibleInGroup = nil
            frame._auraWasActive = false
            frame._trinketProcWasActive = false
            ResetAuraCooldownSpanCache(frame)
            if frame.cooldown then
                if frame.cooldown.SetScript then
                    frame.cooldown:SetScript("OnCooldownDone", nil)
                end
                if frame.cooldown.Clear then
                    frame.cooldown:Clear()
                end
                if frame.cooldown.Hide then
                    frame.cooldown:Hide()
                end
            end
            if frame.count then
                frame.count:Hide()
            end
            CustomIcons.SuppressExpiredIconVisual(frame)
            if frame._ddIsManaged then
                frame._ddManagedAuraExpired = true
            elseif frame.Hide then
                frame:Hide()
            end
        end
    end
end

local function ApplyCustomTimedAuraCooldownFrame(frame, state, showCooldown)
    if not frame or not state or not frame.cooldown then return end
    local startTime = tonumber(state.startTime)
    local duration = tonumber(state.duration)
    if not startTime or not duration or duration <= 0 then return end

    if ShouldApplyAuraCooldownSpan(frame, startTime, duration, "timed") then
        if frame.cooldown.SetReverse then
            frame.cooldown:SetReverse(true)
        end

        if C_DurationUtil and C_DurationUtil.CreateDuration and frame.cooldown.SetCooldownFromDurationObject then
            frame._customTimedAuraDuration = frame._customTimedAuraDuration or C_DurationUtil.CreateDuration()
            local okObj = pcall(frame._customTimedAuraDuration.SetTimeFromStart, frame._customTimedAuraDuration, startTime, duration)
            if okObj then
                local okSet = pcall(frame.cooldown.SetCooldownFromDurationObject, frame.cooldown, frame._customTimedAuraDuration)
                if not okSet then
                    pcall(frame.cooldown.SetCooldownFromDurationObject, frame.cooldown, frame._customTimedAuraDuration, true)
                end
            else
                pcall(frame.cooldown.SetCooldown, frame.cooldown, startTime, duration)
            end
        else
            pcall(frame.cooldown.SetCooldown, frame.cooldown, startTime, duration)
        end
    end

    local hideNumbers = frame._groupSettings and frame._groupSettings.hideDurationText
    if frame.cooldown.SetHideCountdownNumbers then
        frame.cooldown:SetHideCountdownNumbers(hideNumbers and true or false)
    end
    frame.cooldown.noCooldownCount = hideNumbers and true or nil

    if showCooldown == false then
        if frame.cooldown.Hide then
            frame.cooldown:Hide()
        end
    else
        if frame.cooldown.SetDrawSwipe then
            frame.cooldown:SetDrawSwipe(true)
        end
        if frame.cooldown.Show then
            frame.cooldown:Show()
        end
    end
end

function CustomIcons:StopTrackedTrinketEffectGlow(frame)
    if not frame or not frame._ddTrinketEffectGlowActive then return end
    local key = "_DDingUITrinketEffectGlow"
    if SL then
        if SL.HidePixelGlow then SL.HidePixelGlow(frame, key) end
        if SL.HideAutocastGlow then SL.HideAutocastGlow(frame, key) end
        if SL.HideButtonGlow then SL.HideButtonGlow(frame, key) end
    end
    local glow = LibStub and LibStub("LibCustomGlow-1.0", true)
    if glow and glow.ProcGlow_Stop then
        glow.ProcGlow_Stop(frame, key)
    end
    if frame._ddTrinketEffectGlowType == "Blizzard Glow" and ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(frame)
    end
    frame._ddTrinketEffectGlowActive = nil
    frame._ddTrinketEffectGlowType = nil
    frame._ddTrinketEffectGlowSignature = nil
end

function CustomIcons:SetTrackedTrinketEffectGlow(frame, active)
    local settings = frame and frame._groupSettings or {}
    if not active or settings.procGlowEnabled == false or CustomIcons.ManagedVisualLocked(frame) then
        self:StopTrackedTrinketEffectGlow(frame)
        return
    end

    local glowType = settings.procGlowType or "Pixel Glow"
    local color = settings.procGlowColor or { 0.95, 0.95, 0.32, 1 }
    local signature = table.concat({
        glowType,
        tostring(color[1] or color.r or 0.95),
        tostring(color[2] or color.g or 0.95),
        tostring(color[3] or color.b or 0.32),
        tostring(color[4] or color.a or 1),
        tostring(settings.procGlowPixelLines or 5),
        tostring(settings.procGlowPixelFrequency or 0.25),
        tostring(settings.procGlowPixelLength or 8),
        tostring(settings.procGlowPixelThickness or 1),
    }, ":")
    if frame._ddTrinketEffectGlowActive and frame._ddTrinketEffectGlowSignature == signature then
        return
    end

    self:StopTrackedTrinketEffectGlow(frame)
    local key = "_DDingUITrinketEffectGlow"
    if glowType == "Blizzard Glow" then
        if ActionButton_ShowOverlayGlow then ActionButton_ShowOverlayGlow(frame) end
    elseif glowType == "Autocast Shine" and SL and SL.ShowAutocastGlow then
        SL.ShowAutocastGlow(
            frame,
            color,
            math.floor(settings.procGlowAutocastParticles or 8),
            settings.procGlowAutocastFrequency or 0.25,
            settings.procGlowAutocastScale or 1,
            0,
            0,
            key
        )
    elseif glowType == "Action Button Glow" and SL and SL.ShowButtonGlow then
        SL.ShowButtonGlow(frame, color, settings.procGlowButtonFrequency or 0.25, key)
    elseif glowType == "Proc Glow" then
        local glow = LibStub and LibStub("LibCustomGlow-1.0", true)
        if glow and glow.ProcGlow_Start then
            glow.ProcGlow_Start(frame, {
                color = color,
                startAnim = false,
                xOffset = 0,
                yOffset = 0,
                key = key,
            })
        end
    elseif SL and SL.ShowPixelGlow then
        SL.ShowPixelGlow(
            frame,
            color,
            math.floor(settings.procGlowPixelLines or 5),
            settings.procGlowPixelFrequency or 0.25,
            settings.procGlowPixelLength or 8,
            settings.procGlowPixelThickness or 1,
            -1,
            -1,
            false,
            key
        )
        glowType = "Pixel Glow"
    end

    frame._ddTrinketEffectGlowActive = true
    frame._ddTrinketEffectGlowType = glowType
    frame._ddTrinketEffectGlowSignature = signature
end

function CustomIcons:ApplyTrackedTrinketEffect(iconFrame, iconData, itemID)
    if iconFrame then
        iconFrame._ddCustomIconActive = false
    end
    local settings = iconData and iconData.settings
    local registry = DDingUI.TrinketEffects
    if not settings or settings.trackTrinketEffect ~= true
        or not registry or not registry.GetActiveEffectForItem
    then
        self:StopTrackedTrinketEffectGlow(iconFrame)
        return false
    end

    local state = registry:GetActiveEffectForItem(itemID)
    if not state or CustomIcons.ManagedVisualLocked(iconFrame) then
        self:StopTrackedTrinketEffectGlow(iconFrame)
        return false
    end

    CustomIcons.StopIconDesatUpdater(iconFrame)
    iconFrame._ddCustomIconActive = true
    iconFrame._ddCustomIconReady = false
    if iconFrame.icon then
        iconFrame.icon:SetDesaturated(false)
        iconFrame.icon:SetDesaturation(0)
    end
    ApplyCustomTimedAuraCooldownFrame(iconFrame, state, settings.showCooldown ~= false)
    if iconFrame.count then
        if state.stacks and state.stacks > 1 then
            iconFrame.count:SetText(state.stacks)
            iconFrame.count:Show()
        else
            iconFrame.count:SetText("")
            iconFrame.count:Hide()
        end
    end
    self:SetTrackedTrinketEffectGlow(iconFrame, true)
    return true
end

function CustomIcons:UpdateDynamicIconStateGlow(frame, iconData)
    local customizer = DDingUI.IconCustomization
    if not customizer or not customizer.UpdateDynamicIconGlow then return end
    local settings = iconData and iconData.settings and iconData.settings.customStateGlow
    local trigger = settings and settings.glowTrigger
    if not trigger then
        trigger = iconData and (iconData.type == "aura" or iconData.type == "trinketProc") and "active" or "ready"
    end
    local shouldGlow
    if trigger == "active" then
        shouldGlow = frame._ddCustomIconActive == true
    else
        shouldGlow = frame._ddCustomIconReady == true
    end
    customizer:UpdateDynamicIconGlow(frame, settings, shouldGlow)
end

MarkCustomTimedAuraActive = function(spellID, state)
    local db = GetDynamicDB()
    local iconDataByKey = db and db.iconData
    if not iconDataByKey then return false end

    local matchedFrame = false
    local hasMatchingIcon = false
    local needsLayout = false
    local now = GetTime and GetTime() or 0
    for iconKey, iconData in pairs(iconDataByKey) do
        local config = GetCustomTimedAuraConfig(iconData)
        if config and config.stateID == spellID then
            hasMatchingIcon = true
            local frame = runtime.iconFrames[iconKey]
            if not frame and CustomIcons.EnsureDynamicIconFrame then
                frame = CustomIcons:EnsureDynamicIconFrame(iconKey, iconData)
            end
            if frame then
                matchedFrame = true
                if not frame._ddIsManaged or not (frame.IsShown and frame:IsShown()) then
                    needsLayout = true
                end
                frame._ddTimedAuraActiveUntil = state and state.expirationTime or nil
                frame._ddLastAuraActiveAt = now
                frame._ddLastDynamicActiveAt = now
                frame._wasVisibleInGroup = true
                frame._auraWasActive = true
                frame._ddManagedAuraExpired = nil
                frame._ddCombatVisible = nil
                frame._ddInactiveGray = nil
                frame._ddForcedInactiveGray = nil
                if state and state.iconTexture then
                    SetStableIconTexture(frame, state.iconTexture, true)
                end
                local settings = iconData.settings or {}
                ApplyCustomTimedAuraCooldownFrame(frame, state, settings.showCooldown ~= false)
                CustomIcons.RestoreActiveIconVisual(frame)
                CustomIcons.ApplyManagedGroupTextOptions(frame)
            else
                needsLayout = true
            end
        end
    end
    return matchedFrame, hasMatchingIcon, needsLayout
end

local function CountCustomTimedAuraLinks(spellID)
    local db = GetDynamicDB()
    local iconDataByKey = db and db.iconData
    if not iconDataByKey then return 0, 0 end

    local iconCount, frameCount = 0, 0
    for iconKey, iconData in pairs(iconDataByKey) do
        local config = GetCustomTimedAuraConfig(iconData)
        if config and config.stateID == spellID then
            iconCount = iconCount + 1
            if runtime.iconFrames[iconKey] then
                frameCount = frameCount + 1
            end
        end
    end
    return iconCount, frameCount
end

local function RecordCustomTimedAuraLink(spellID, matchedFrame, hasMatchingIcon)
    local bucket = RecordTimedAuraDebug(spellID, "activated", tostring(spellID))
    if not bucket then return end

    local iconCount, frameCount = CountCustomTimedAuraLinks(spellID)
    bucket.lastMatchedFrame = matchedFrame == true
    bucket.lastHasMatchingIcon = hasMatchingIcon == true
    bucket.iconCount = iconCount
    bucket.frameCount = frameCount
end

local function ActivateCustomTimedAura(spellID, config, startTime, iconSpellID, stateOptions)
    spellID = tonumber(spellID)
    if not spellID or not config then return nil, false end

    local duration = tonumber(config.duration) or 0
    if duration <= 0 then return nil, false end

    local now = GetTime()
    local started = tonumber(startTime) or now
    local expirationTime = started + duration
    if expirationTime <= now then
        return nil, DeactivateCustomTimedAura(spellID)
    end

    local old = runtime.customTimedAuras[spellID]
    local iconTexture = CustomIcons.ResolveCustomTimedAuraStateTexture(spellID, config, iconSpellID)
    local changed = not old
        or math.abs((old.startTime or 0) - started) > 0.05
        or math.abs((old.expirationTime or 0) - expirationTime) > 0.05
        or (iconTexture and old.iconTexture ~= iconTexture)
        or (tonumber(old and old.stacks) or 0) ~= (tonumber(stateOptions and stateOptions.stacks) or 0)

    local token = {}
    local state = {
        startTime = started,
        duration = duration,
        expirationTime = expirationTime,
        token = token,
        iconTexture = iconTexture,
        stacks = tonumber(stateOptions and stateOptions.stacks) or 0,
    }
    runtime.customTimedAuras[spellID] = state
    local matchedFrame, hasMatchingIcon, needsLayout
    if MarkCustomTimedAuraActive then
        matchedFrame, hasMatchingIcon, needsLayout = MarkCustomTimedAuraActive(spellID, state)
    end
    if changed or needsLayout then
        RecordCustomTimedAuraLink(spellID, matchedFrame, hasMatchingIcon)
        NotifyCustomTimedAuraChanged("force")
        if hasMatchingIcon and not matchedFrame and CustomIcons and CustomIcons.LoadDynamicIcons then
            C_Timer.After(0, function()
                if CustomIcons and CustomIcons.LoadDynamicIcons then
                    CustomIcons:LoadDynamicIcons()
                end
                if MarkCustomTimedAuraActive then
                    MarkCustomTimedAuraActive(spellID, state)
                end
                NotifyCustomTimedAuraChanged("force")
            end)
        end
    end

    C_Timer.After((expirationTime - now) + 0.05, function()
        local current = runtime.customTimedAuras and runtime.customTimedAuras[spellID]
        if current and current.token == token then
            DeactivateCustomTimedAura(spellID)
            if UpdateAllIcons then
                UpdateAllIcons(true, "aura")
            end
        end
    end)

    return state, changed
end

local function ActivateBloodlustTimedAuraFromAura(aura, iconSpellID, requireWithinWindow)
    local config = CUSTOM_TIMED_AURA_CONFIGS[2825]
    if not config then return false end
    local iconCount = CountCustomTimedAuraLinks(2825)
    if iconCount <= 0 then return false end

    local now = GetTime()
    local active = runtime.customTimedAuras[2825]
    if active and active.expirationTime and active.expirationTime > now then
        bloodlustDebuffInstanceID = GetAuraFieldSafe(aura, "auraInstanceID") or bloodlustDebuffInstanceID
        RecordTimedAuraDebug(2825, "alreadyActive", "debuff")
        return false
    end

    local auraInstanceID = GetAuraFieldSafe(aura, "auraInstanceID")
    local expirationTime = GetAuraNumberFieldSafe(aura, "expirationTime")
    local duration = GetAuraNumberFieldSafe(aura, "duration")

    if not auraInstanceID or not expirationTime then
        RecordTimedAuraDebug(2825, "debuffSkipped", "missing-instance-or-expiration")
        return false
    end
    if not duration or duration <= 0 then
        duration = 600
    end

    local appliedTime = expirationTime - duration
    if requireWithinWindow and (now - appliedTime) >= 40 then
        return false
    end

    local _, changed = ActivateCustomTimedAura(2825, config, appliedTime, iconSpellID or 2825)
    bloodlustDebuffInstanceID = auraInstanceID
    return changed
end

local function SeedBloodlustTimedAura(requireWithinWindow)
    bloodlustDebuffInstanceID = nil
    local sawCandidate = false
    for debuffID, lustBuffID in pairs(BLOODLUST_DEBUFFS) do
        local auraData
        pcall(function()
            auraData = C_UnitAuras.GetPlayerAuraBySpellID(debuffID)
        end)
        if auraData then
            sawCandidate = true
            RecordTimedAuraDebug(2825, "seedMatch", tostring(debuffID) .. "->" .. tostring(lustBuffID))
        end
        if auraData
            and GetAuraFieldSafe(auraData, "auraInstanceID")
            and GetAuraNumberFieldSafe(auraData, "expirationTime")
            and ActivateBloodlustTimedAuraFromAura(auraData, lustBuffID, requireWithinWindow)
        then
            return true
        end
    end

    if not sawCandidate then
        RecordTimedAuraDebug(2825, "seedMiss", requireWithinWindow and "window" or "open")
    end
    return false
end

local function ScanBloodlustTimedAura(updateInfo)
    RecordTimedAuraDebug(2825, "unitAura", (updateInfo and updateInfo.isFullUpdate) and "full" or "partial")
    if not updateInfo or updateInfo.isFullUpdate then
        return SeedBloodlustTimedAura(true)
    end

    local changed = false
    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            local sid = GetAuraSpellIDSafe(aura)
            local lustBuffID = sid and BLOODLUST_DEBUFFS[sid]
            if lustBuffID then
                RecordTimedAuraDebug(2825, "unitAuraMatch", tostring(sid) .. "->" .. tostring(lustBuffID))
            end
            if lustBuffID
                and GetAuraFieldSafe(aura, "auraInstanceID")
                and GetAuraNumberFieldSafe(aura, "expirationTime")
                and ActivateBloodlustTimedAuraFromAura(aura, lustBuffID, false)
            then
                changed = true
                break
            end
        end
    end

    if bloodlustDebuffInstanceID and updateInfo.removedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            if id == bloodlustDebuffInstanceID then
                bloodlustDebuffInstanceID = nil
                break
            end
        end
    end

    return changed
end

local function GetActiveCustomTimedAura(iconData)
    local config = GetCustomTimedAuraConfig(iconData)
    if not config then return nil end

    local state = runtime.customTimedAuras[config.stateID]
    if not state then return nil end

    local now = GetTime()
    if state.expirationTime and state.expirationTime > now then
        return BuildTimedAuraData(config.stateID, state)
    end

    DeactivateCustomTimedAura(config.stateID)
    return nil
end

local function ResolvePlayerAuraForIcon(iconFrame, iconData)
    if not iconData or iconData.type ~= "aura" or not iconData.id then return nil end

    local timedConfig = GetCustomTimedAuraConfig(iconData)
    if timedConfig then
        local timedAura = GetActiveCustomTimedAura(iconData)
        if timedAura then
            if iconFrame then
                iconFrame._ddTimedAuraActiveUntil = GetAuraNumberFieldSafe(timedAura, "expirationTime")
                iconFrame._cachedAuraSpellID = GetAuraSpellIDSafe(timedAura) or GetAuraNumberFieldSafe(timedAura, "spellId") or iconData.id
            end
            return timedAura
        end
        if iconFrame then
            iconFrame._ddTimedAuraActiveUntil = nil
            iconFrame._ddAuraActiveUntil = nil
            iconFrame._auraWasActive = false
            iconFrame._ddManagedAuraExpired = true
        end
        return nil
    end

    local candidates = BuildAuraCandidateIDs(iconFrame, iconData)
    for _, spellID in ipairs(candidates) do
        local auraData
        pcall(function()
            auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        end)
        if auraData then
            if iconFrame then
                iconFrame._cachedAuraSpellID = GetAuraSpellIDSafe(auraData) or spellID
                local expirationTime = GetAuraNumberFieldSafe(auraData, "expirationTime")
                if expirationTime and expirationTime > 0 then
                    iconFrame._ddAuraActiveUntil = expirationTime
                end
            end
            return auraData
        end
    end

    local nameSet = {}
    for _, spellID in ipairs(candidates) do
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            nameSet[info.name] = true
        end
    end

    if next(nameSet) and AuraUtil and AuraUtil.ForEachAura then
        local auraData
        pcall(function()
            AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
                local auraName = GetAuraFieldSafe(aura, "name")
                if auraName and nameSet[auraName] then
                    auraData = aura
                    local auraSpellID = GetAuraSpellIDSafe(aura)
                    if iconFrame and auraSpellID then
                        iconFrame._cachedAuraSpellID = auraSpellID
                        local expirationTime = GetAuraNumberFieldSafe(aura, "expirationTime")
                        if expirationTime and expirationTime > 0 then
                            iconFrame._ddAuraActiveUntil = expirationTime
                        end
                    end
                    return true
                end
            end)
        end)
        if auraData then
            return auraData
        end
    end

    return nil
end

-- Item cooldown APIs can briefly report zero immediately after combat item use.
-- Keep the last valid cooldown span until it expires instead of hiding the count.

-- [FIX CDM] IsCooldownFrameActive 제거 — 대신 EvaluateRemainingDuration(GCDFilterCurve)로 frame-perfect 쿨다운 감지
local function EvalDesatFromDurObj(durObj, isOnGCD)
    local DDingUI = ns.Addon
    local desatCurve = isOnGCD
        and (DDingUI and DDingUI._GCDFilterCurve)
        or  (DDingUI and DDingUI._DesaturationCurve)
    if desatCurve and durObj and durObj.EvaluateRemainingDuration then
        local ok, v = pcall(durObj.EvaluateRemainingDuration, durObj, desatCurve, 0)
        if ok and type(v) == "number" then return v end
    end
    -- fallback: curve 미생성 환경 (WoW 구 버전) — durObj가 있고 GCD가 아니면 1
    if durObj and not isOnGCD then return 1 end
    return 0
end

local function ResolveUsableItemSpellID(iconFrame, itemID, settings)
    if not itemID then return nil end

    local itemSpellID = ITEM_SPELL_MAP[itemID] or (settings and settings.itemSpellID)
    if itemSpellID then return itemSpellID end

    if iconFrame and iconFrame._cachedSpellItemID == itemID then
        return iconFrame._cachedSpellID
    end

    if C_Item and C_Item.GetItemSpell then
        pcall(function()
            local _, sid = C_Item.GetItemSpell(itemID)
            if sid then
                itemSpellID = sid
                if iconFrame then
                    iconFrame._cachedSpellID = sid
                    iconFrame._cachedSpellItemID = itemID
                end
            end
        end)
    end

    return itemSpellID
end

local function ClearCooldownSpan(iconFrame, prefix)
    if not iconFrame or not prefix then return end
    iconFrame[prefix .. "Start"] = nil
    iconFrame[prefix .. "Duration"] = nil
    iconFrame[prefix .. "Until"] = nil
end

local function EnsureCooldownSpanOwner(iconFrame, prefix, ownerID)
    if not iconFrame or not prefix then return end
    local ownerKey = prefix .. "OwnerID"
    if iconFrame[ownerKey] ~= ownerID then
        ClearCooldownSpan(iconFrame, prefix)
        iconFrame[ownerKey] = ownerID
    end
end

local function GetRealSpellCooldownDuration(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil, false end
    return C_Spell.GetSpellCooldownDuration(spellID), true
end

local function IsCooldownEnabled(enable)
    if enable == nil then return true end
    if enable == true then return true end
    local value = SafeNumber(enable)
    if value then return value == 1 end
    local ok, enabled = pcall(function()
        return enable == 1
    end)
    if ok then return enabled == true end
    return true
end

local function NormalizeCooldownSpan(start, duration, enable)
    local observed = start ~= nil or duration ~= nil or enable ~= nil
    if not IsCooldownEnabled(enable) then return nil, nil, false, observed end

    local safeStart = SafeNumber(start)
    local safeDuration = SafeNumber(duration)
    if safeStart and safeDuration then
        if safeDuration > 1.6 then
            return safeStart, safeDuration, true, true
        end
        return nil, nil, false, true
    end

    -- In combat, item cooldown APIs can return protected numeric values.
    -- Cooldown:SetCooldown can consume those directly, so keep the raw span.
    if start ~= nil and duration ~= nil then
        return start, duration, false, true
    end
    return nil, nil, false, observed
end

local function ReadInventoryCooldownSpan(slotID)
    if not slotID or not GetInventoryItemCooldown then return nil, nil, false, false end

    local start, duration, enable
    pcall(function()
        start, duration, enable = GetInventoryItemCooldown("player", slotID)
    end)
    return NormalizeCooldownSpan(start, duration, enable)
end

local function ReadItemCooldownSpan(itemID)
    if not itemID then return nil, nil, false, false end

    local function readWith(getter)
        local start, duration
        pcall(function()
            start, duration = getter(itemID)
        end)
        return NormalizeCooldownSpan(start, duration, nil)
    end

    if C_Container and C_Container.GetItemCooldown then
        local start, duration, safeSpan, observed = readWith(C_Container.GetItemCooldown)
        if start then return start, duration, safeSpan end
        if observed then return nil, nil, false, true end
    end
    if C_Item and C_Item.GetItemCooldown then
        local start, duration, safeSpan, observed = readWith(C_Item.GetItemCooldown)
        if start then return start, duration, safeSpan end
        if observed then return nil, nil, false, true end
    end
    if GetItemCooldown then
        local start, duration, safeSpan, observed = readWith(GetItemCooldown)
        if start then return start, duration, safeSpan end
        if observed then return nil, nil, false, true end
    end
    return nil, nil, false, false
end

local function FindEquippedItemSlot(itemID)
    itemID = SafeNumber(itemID)
    if not itemID or not GetInventoryItemID then return nil end

    for _, slotID in ipairs({ 13, 14 }) do
        local equippedID = CustomIcons.GetEquippedSlotItemID(nil, slotID)
        if SafeNumber(equippedID) == itemID then
            return slotID
        end
    end
    return nil
end

local function ResolveItemCooldownSpan(iconFrame, prefix, itemID, slotID, spellID)
    local equippedSlotID = slotID or FindEquippedItemSlot(itemID)
    local start, duration, safeSpan, observed = ReadInventoryCooldownSpan(equippedSlotID)
    if not start and not observed then
        start, duration, safeSpan, observed = ReadItemCooldownSpan(itemID)
    end
    if start and duration then
        return start, duration, true, safeSpan
    end

    ClearCooldownSpan(iconFrame, prefix)
    return nil, nil, false, false
end

local function SetItemCombatLockout(itemID, active)
    if not ITEM_COMBAT_LOCKOUT_ITEMS[itemID] then return end
    runtime.itemCombatLockouts = runtime.itemCombatLockouts or {}
    if active then
        for lockedItemID in pairs(ITEM_COMBAT_LOCKOUT_ITEMS) do
            runtime.itemCombatLockouts[lockedItemID] = true
        end
    else
        runtime.itemCombatLockouts[itemID] = nil
    end
end

local function ClearItemCombatLockouts()
    runtime.itemCombatLockouts = {}
end

local function IsItemCombatLocked(itemID)
    return itemID and runtime.itemCombatLockouts and runtime.itemCombatLockouts[itemID] == true
end

local function MarkItemCombatLockoutFromSpell(spellID)
    spellID = SafeNumber(spellID)
    if not spellID or not ITEM_COMBAT_LOCKOUT_SPELLS[spellID] then return false end
    if not InCombatLockdown or not InCombatLockdown() then return false end

    for itemID, mappedSpellID in pairs(ITEM_SPELL_MAP) do
        if mappedSpellID == spellID and ITEM_COMBAT_LOCKOUT_ITEMS[itemID] then
            SetItemCombatLockout(itemID, true)
            return true
        end
    end
    return false
end

local function ApplyCooldownSpan(iconFrame, durObjKey, start, duration, safeSpan)
    if not iconFrame or not iconFrame.cooldown or not start or not duration then return false end
    local managedVisualLocked = CustomIcons.ManagedVisualLocked(iconFrame)
    if iconFrame.cooldown.SetReverse then
        iconFrame.cooldown:SetReverse(false)
    end

    if C_DurationUtil and C_DurationUtil.CreateDuration then
        if not iconFrame[durObjKey] then
            iconFrame[durObjKey] = C_DurationUtil.CreateDuration()
        end
        local okObj = pcall(iconFrame[durObjKey].SetTimeFromStart, iconFrame[durObjKey], start, duration)
        if okObj then
            local okSet = pcall(iconFrame.cooldown.SetCooldownFromDurationObject, iconFrame.cooldown, iconFrame[durObjKey], true)
            if not okSet then
                okSet = pcall(iconFrame.cooldown.SetCooldownFromDurationObject, iconFrame.cooldown, iconFrame[durObjKey])
            end
            if okSet then
                if not managedVisualLocked and iconFrame.cooldown.SetDrawSwipe then
                    iconFrame.cooldown:SetDrawSwipe(true)
                end
                if not managedVisualLocked and iconFrame.cooldown.Show then
                    iconFrame.cooldown:Show()
                end
                return true
            end
        end
    end

    if CooldownFrame_Set then
        local okFrameSet = pcall(CooldownFrame_Set, iconFrame.cooldown, start, duration, 1, false)
        if okFrameSet then
            if not managedVisualLocked and iconFrame.cooldown.SetDrawSwipe then
                iconFrame.cooldown:SetDrawSwipe(true)
            end
            if not managedVisualLocked and iconFrame.cooldown.Show then
                iconFrame.cooldown:Show()
            end
            return true
        end
    end

    local ok = pcall(iconFrame.cooldown.SetCooldown, iconFrame.cooldown, start, duration)
    if ok then
        if not managedVisualLocked and iconFrame.cooldown.SetDrawSwipe then
            iconFrame.cooldown:SetDrawSwipe(true)
        end
        if not managedVisualLocked and iconFrame.cooldown.Show then
            iconFrame.cooldown:Show()
        end
    end
    return ok == true
end

local function ApplyInventorySlotCooldown(iconFrame, durObjKey, slotID)
    local spanPrefix = durObjKey
    if durObjKey == "_slotDurObj" then
        spanPrefix = "_ddSlotCooldown"
    elseif durObjKey == "_trinketDurObj" then
        spanPrefix = "_ddTrinketCooldown"
    end

    local start, duration, safeSpan = ReadInventoryCooldownSpan(slotID)

    if start and duration then
        if ApplyCooldownSpan(iconFrame, durObjKey, start, duration, safeSpan) then
            return true
        end
    end

    ClearCooldownSpan(iconFrame, spanPrefix)
    if iconFrame and iconFrame.cooldown then
        iconFrame.cooldown:Clear()
    end
    return false
end

function runtime.ApplyTrinketSlotCooldown(iconFrame, slotID)
    if not (iconFrame and iconFrame.cooldown and slotID) then return false end
    return ApplyInventorySlotCooldown(iconFrame, "_trinketDurObj", slotID)
end

function runtime.ApplyCooldownDurationObject(iconFrame, durationObject)
    if not (iconFrame and iconFrame.cooldown and durationObject) then return false end
    local managedVisualLocked = CustomIcons.ManagedVisualLocked(iconFrame)
    if iconFrame.cooldown.SetReverse then
        iconFrame.cooldown:SetReverse(false)
    end
    if not managedVisualLocked and iconFrame.cooldown.Show then
        iconFrame.cooldown:Show()
    end
    local ok = pcall(iconFrame.cooldown.SetCooldownFromDurationObject, iconFrame.cooldown, durationObject)
    if not ok then
        ok = pcall(iconFrame.cooldown.SetCooldownFromDurationObject, iconFrame.cooldown, durationObject, true)
    end
    if ok then
        if not managedVisualLocked and iconFrame.cooldown.SetDrawSwipe then
            iconFrame.cooldown:SetDrawSwipe(true)
        end
        if iconFrame.cooldown.IsShown then
            return iconFrame.cooldown:IsShown()
        end
    end
    return ok == true
end

local function UpdateItemIcon(iconFrame, iconData)
    local itemID = iconData.id
    if not itemID or not iconFrame then return end
    CustomIcons.RestoreActiveIconVisual(iconFrame)
    local managedVisualLocked = CustomIcons.ManagedVisualLocked(iconFrame)

    local settings = iconData.settings
    local includeCharges = settings and settings.showCharges
    local itemCount = C_Item.GetItemCount(itemID, false, includeCharges, false)
    local activeItemID = itemID
    local usedFallback = false
    local previousCombatCount = iconFrame._ddCombatItemCount

    -- Fallback item logic: if primary item count is 0 and fallbackItems are configured
    if (itemCount == 0 or itemCount == nil) and settings and settings.fallbackItems then
        local fallbackItems = settings.fallbackItems
        if type(fallbackItems) == "string" and fallbackItems ~= "" then
            -- Parse comma-separated item IDs
            for fallbackID in string.gmatch(fallbackItems, "(%d+)") do
                local fID = tonumber(fallbackID)
                if fID then
                    local fCount = C_Item.GetItemCount(fID, false, includeCharges, false)
                    if fCount and fCount > 0 then
                        activeItemID = fID
                        itemCount = fCount
                        usedFallback = true
                        break
                    end
                end
            end
        end
    end

    if ITEM_COMBAT_LOCKOUT_ITEMS[activeItemID] and InCombatLockdown and InCombatLockdown() then
        local currentCount = SafeNumber(itemCount)
        if previousCombatCount and currentCount and currentCount < previousCombatCount then
            SetItemCombatLockout(activeItemID, true)
        end
    end
    iconFrame._ddCombatItemCount = SafeNumber(itemCount)

    iconFrame._textureCacheKey = activeItemID and ("item:" .. tostring(activeItemID)) or iconFrame._textureCacheKey
    local itemTexture = ResolveItemTexture(activeItemID)
    if itemTexture then
        iconFrame._originalTexture = itemTexture
    end
    SetStableIconTexture(iconFrame, itemTexture, true)

    -- [CDM] Item cooldown uses item cooldown first, then mapped spell duration.
    EnsureCooldownSpanOwner(iconFrame, "_ddItemCooldown", activeItemID)
    if CustomIcons:ApplyTrackedTrinketEffect(iconFrame, iconData, activeItemID) then
        return
    end

    local itemSpellID = ResolveUsableItemSpellID(iconFrame, activeItemID, settings)
    local desatDurationObject = nil
    local desatSpellID = nil
    local itemCooldownActive = false
    local itemSpellCooldownActive = false
    local itemCombatLocked = IsItemCombatLocked(activeItemID)
    if itemSpellID then
        -- 스펠 ID가 매핑된 아이템: CDM의 최우선 ItemCD 시도, 실패시 SpellDur 사용
        local realDur = GetRealSpellCooldownDuration(itemSpellID)

        local itemCdStart, itemCdDuration, hasItemCooldown, itemCdSafe =
            ResolveItemCooldownSpan(iconFrame, "_ddItemCooldown", activeItemID, nil, itemSpellID)

        desatDurationObject = realDur
        desatSpellID = itemSpellID

        if hasItemCooldown then
            if ApplyCooldownSpan(iconFrame, "_itemDurObj", itemCdStart, itemCdDuration, itemCdSafe) then
                itemCooldownActive = true
            else
                iconFrame.cooldown:Clear()
            end
        elseif realDur then
            pcall(function()
                local cdInfo = C_Spell.GetSpellCooldown(itemSpellID)
                if cdInfo and cdInfo.isActive and cdInfo.isOnGCD ~= true then
                    itemSpellCooldownActive = true
                end
            end)
            if itemSpellCooldownActive then
                iconFrame.cooldown:SetCooldownFromDurationObject(realDur)
            else
                iconFrame.cooldown:Clear()
            end
        else
            iconFrame.cooldown:Clear()
        end
    else
        -- [Fallback] 스펠 ID 없는 아이템 (비전투/제한적 작동)
        local itemCdStart, itemCdDuration, hasItemCooldown, itemCdSafe =
            ResolveItemCooldownSpan(iconFrame, "_ddItemCooldown", activeItemID, nil, itemSpellID)

        if hasItemCooldown then
            if ApplyCooldownSpan(iconFrame, "_itemDurObj", itemCdStart, itemCdDuration, itemCdSafe) then
                itemCooldownActive = true
            else
                iconFrame.cooldown:Clear()
            end
        else
            iconFrame.cooldown:Clear()
        end
    end

    -- 쿨다운 프레임 Show/Hide
    if not managedVisualLocked then
        if iconData.settings and iconData.settings.showCooldown == false then
            iconFrame.cooldown:Hide()
        elseif itemCooldownActive or itemSpellCooldownActive then
            iconFrame.cooldown:Show()
        else
            iconFrame.cooldown:Hide()
        end
    end

    -- 아이템 카운트 표시
    if iconFrame.count and not managedVisualLocked then
        pcall(iconFrame.count.SetText, iconFrame.count, itemCount or 0)
        if iconData.settings and iconData.settings.showCharges == false then
            iconFrame.count:Hide()
        else
            iconFrame.count:Show()
        end
    end

    -- [CDM 패턴] 탈색 처리
    local allowCooldownDesat = not (iconData.settings and iconData.settings.desaturateOnCooldown == false)
    local allowUnusableDesat = not (iconData.settings and iconData.settings.desaturateWhenUnusable == false)

    local showEmptyItem = (itemCount == 0 or itemCount == nil)
    local desatVal = 0

    -- [FIX] OnUpdate 진입 조건: cdInfo.isActive (safe boolean) 사용 — secret number 비교 금지
    local itemIsOnRealCD = false

    if itemCombatLocked then
        if iconFrame.cooldown then
            iconFrame.cooldown:Clear()
        end
        if allowCooldownDesat or allowUnusableDesat then desatVal = 1 end
    elseif itemCooldownActive then
        if allowCooldownDesat then desatVal = 1 end
    elseif showEmptyItem then
        if allowUnusableDesat then desatVal = 1 end
    elseif allowCooldownDesat and desatDurationObject and desatSpellID then
        -- isOnRealCD: boolean (safe) — secret number 비교 없음
        pcall(function()
            local cdInfo = C_Spell.GetSpellCooldown(desatSpellID)
            if cdInfo and cdInfo.isActive and cdInfo.isOnGCD ~= true then
                itemIsOnRealCD = true
                -- isOnGCD는 이미 false이므로 EvalDesatFromDurObj에 false 전달
            end
        end)
        if itemIsOnRealCD then
            -- EvaluateRemainingDuration 결과(secret)는 비교 없이 SetDesaturation에 직접 전달
            desatVal = EvalDesatFromDurObj(desatDurationObject, false)
        end
    end

    if managedVisualLocked then
        CustomIcons.StopIconDesatUpdater(iconFrame)
    else
        iconFrame.icon:SetDesaturated(false)
        iconFrame.icon:SetDesaturation(desatVal)
    end

    -- Cooldown events and OnCooldownDone own desaturation state changes.
    CustomIcons.StopIconDesatUpdater(iconFrame)

    if not managedVisualLocked and not IsFlightHideAlphaLocked() then
        iconFrame.icon:SetAlpha(1.0)
    end
    iconFrame._ddCustomIconActive = false
    iconFrame._ddCustomIconReady = not itemCombatLocked
        and not itemCooldownActive
        and not itemSpellCooldownActive
        and not showEmptyItem
end

local function UpdateSpellIconFrame(iconFrame, iconData)
    local spellID = iconData.id
    if not spellID or not iconFrame then return end

    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local ok, overrideID = pcall(C_SpellBook.FindSpellOverrideByID, spellID)
        if ok and overrideID and overrideID ~= spellID then
            spellID = overrideID
        end
    end

    iconFrame._textureCacheKey = "spell:" .. tostring(spellID)
    -- 텍스처동적 갱신 (오버라이드/누락 초기로드 대응)
    iconFrame._fallbackTexture = GetStoredIconTexture(iconData) or iconFrame._fallbackTexture or FALLBACK_SPELL_ICON
    SetStableIconTexture(iconFrame, ResolveSpellTexture(spellID, iconFrame._fallbackTexture), true)
    local managedVisualLocked = CustomIcons.ManagedVisualLocked(iconFrame)

    local allowDesat = not (iconData.settings and iconData.settings.desaturateOnCooldown == false)
    local allowUnusableDesat = not (iconData.settings and iconData.settings.desaturateWhenUnusable == false)

    -- 쿨다운 정보
    local chargeInfo
    pcall(function()
        chargeInfo = C_Spell.GetSpellCharges(spellID)
    end)

    local CCD = C_Spell.GetSpellChargeDuration(spellID)
    local SCD = C_Spell.GetSpellCooldownDuration(spellID)
    local isChargeSpell = chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1

    local isOnGCD = false
    if SCD then
        pcall(function()
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.isOnGCD then isOnGCD = true end
        end)
    end

    -- [CDM 패턴] 쿨다운 DurationObject 선택
    -- CCD(ChargeDuration)가 존재하면 충전 쿨다운, 없으면 SCD(SpellCooldown) 사용
    -- currentCharges/maxCharges 값 비교 불필요 (secret value taint 방지)
    local durObj
    if isChargeSpell and CCD then
        durObj = CCD
    else
        durObj = SCD
    end

    -- [FIX 깜빡임] 쿨다운 상태 캐싱 — 동일 상태 재Set/Clear 방지
    -- GCD 진입/해제 시 durObj 변화가 없으면 cooldown 프레임을 건드리지 않음
    local cooldownSet = false
    local newCDState = (durObj and not isOnGCD) and "set" or "clear"
    if newCDState == "set" then
        pcall(function()
            iconFrame.cooldown:SetCooldownFromDurationObject(durObj)
            if iconFrame.cooldownProbe then iconFrame.cooldownProbe:SetCooldownFromDurationObject(durObj) end
        end)
        cooldownSet = true
    else
        iconFrame.cooldown:Clear()
        if iconFrame.cooldownProbe then iconFrame.cooldownProbe:Clear() end
    end
    iconFrame._lastCDState = newCDState

    if not managedVisualLocked then
        if iconData.settings and iconData.settings.showCooldown == false then
            iconFrame.cooldown:Hide()
        else
            iconFrame.cooldown:Show()
            local hideNumbers = iconFrame._groupSettings and iconFrame._groupSettings.hideDurationText
            if iconFrame.cooldown.SetHideCountdownNumbers then
                iconFrame.cooldown:SetHideCountdownNumbers(hideNumbers and true or false)
            end
            iconFrame.cooldown.noCooldownCount = hideNumbers and true or nil
        end
    end

    -- 충전 카운트 표시
    local charges = isChargeSpell and chargeInfo.currentCharges
    local hasChargesText = false
    if not managedVisualLocked then
        if not isChargeSpell or (iconData.settings and iconData.settings.showCharges == false) or charges == nil then
            pcall(iconFrame.count.SetText, iconFrame.count, "")
            iconFrame.count:Hide()
        else
            hasChargesText = pcall(iconFrame.count.SetText, iconFrame.count, charges)
            if hasChargesText then
                iconFrame.count:Show()
            else
                pcall(iconFrame.count.SetText, iconFrame.count, "")
                iconFrame.count:Hide()
            end
        end
    end

    -- [FIX CDM] Swipe/Edge 스타일 (변경 없음)
    if not managedVisualLocked and not (iconData.settings and iconData.settings.showCooldown == false) then
        if isChargeSpell then
            iconFrame.cooldown:SetSwipeColor(0, 0, 0, 0)
            iconFrame.cooldown:SetDrawEdge(cooldownSet)
            if iconFrame.cooldown.SetDrawSwipe then
                iconFrame.cooldown:SetDrawSwipe(true)
            end
        else
            iconFrame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
            iconFrame.cooldown:SetDrawEdge(false)
            if iconFrame.cooldown.SetDrawSwipe then
                iconFrame.cooldown:SetDrawSwipe(true)
            end
        end
    elseif not managedVisualLocked then
        iconFrame.cooldown:SetDrawEdge(false)
    end

    -- 사용가능 여부
    local usable = true
    if C_Spell and C_Spell.IsSpellUsable then
        local okUsable, usableVal = pcall(C_Spell.IsSpellUsable, spellID)
        if okUsable then usable = usableVal == true end
    elseif IsUsableSpell then
        local okUsable, usableVal = pcall(IsUsableSpell, spellID)
        if okUsable then usable = usableVal == true end
    end

    -- [FIX CDM] EvaluateRemainingDuration 기반 탈색
    -- secret number를 비교하지 않음 — cdInfo.isActive (safe boolean)으로 OnUpdate 진입 결정
    local desatDurObj = SCD
    local desatValue = 0
    local isOnRealCD = false  -- safe boolean

    if usable then
        if allowDesat then
            -- 1단계: safe boolean으로 쿨다운 활성 여부 판단
            pcall(function()
                local cdInfo = C_Spell.GetSpellCooldown(spellID)
                if cdInfo and cdInfo.isActive and cdInfo.isOnGCD ~= true then
                    isOnRealCD = true
                end
            end)
            -- 2단계: secret number는 비교 없이 SetDesaturation에만 전달
            -- [FIX 깜빡임] GCD 진입 시 탈색값 보존 — isOnGCD면 이전 값 유지, 없으면 0
            if desatDurObj then
                if isOnGCD then
                    -- GCD 중: 직전 탈색값을 그대로 유지 (흰색↔회색 교번 방지)
                    desatValue = iconFrame._lastDesatValue or 0
                else
                    desatValue = EvalDesatFromDurObj(desatDurObj, false)
                    iconFrame._lastDesatValue = desatValue
                end
            end
        end
    else
        if allowUnusableDesat then
            desatValue = 1
        end
        iconFrame._lastDesatValue = nil  -- unusable 상태 전환 시 캐시 초기화
    end
    if managedVisualLocked then
        CustomIcons.StopIconDesatUpdater(iconFrame)
    else
        iconFrame.icon:SetDesaturation(desatValue)
    end

    CustomIcons.StopIconDesatUpdater(iconFrame)

    if not managedVisualLocked and not IsFlightHideAlphaLocked() then
        iconFrame.icon:SetAlpha(1.0)
    end
    iconFrame._ddCustomIconActive = false
    iconFrame._ddCustomIconReady = usable and not isOnRealCD
end

local function UpdateRacialIconFrame(iconFrame, iconData)
    if not iconFrame or not iconData then return end
    local racialID = GetPlayerRacialSpellID()
    if not racialID then return end

    local sourceSettings = iconData.settings
    if type(sourceSettings) ~= "table" then
        sourceSettings = {}
        iconData.settings = sourceSettings
    end

    local racials = DDingUI.CustomIconRacials
    local texture = racials and racials:GetTexture(FALLBACK_RACIAL_ICON)

    local racialSettings = {}
    for key, value in pairs(sourceSettings) do
        racialSettings[key] = value
    end
    racialSettings.iconTexture = texture or sourceSettings.iconTexture or FALLBACK_RACIAL_ICON
    racialSettings.fallbackIcon = racialSettings.iconTexture
    racialSettings.desaturateWhenUnusable = false
    racialSettings.desaturateOnCooldown = false
    racialSettings.showCharges = false

    iconFrame._type = "racial"
    iconFrame._racialSpellID = racialID
    iconFrame._fallbackTexture = racialSettings.iconTexture or FALLBACK_RACIAL_ICON
    iconFrame._textureCacheKey = "racial:" .. tostring(racialID)
    SetStableIconTexture(iconFrame, racialSettings.iconTexture, true)

    local managedVisualLocked = CustomIcons.ManagedVisualLocked(iconFrame)
    CustomIcons.StopIconDesatUpdater(iconFrame)

    local cdInfo
    local durObj
    pcall(function()
        cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(racialID)
        durObj = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(racialID)
    end)

    local onCooldown = cdInfo and cdInfo.isActive == true and cdInfo.isOnGCD ~= true and durObj
    if iconFrame.cooldown then
        if iconFrame.cooldown.SetReverse then iconFrame.cooldown:SetReverse(false) end
        if iconFrame.cooldown.SetDrawEdge then iconFrame.cooldown:SetDrawEdge(false) end
        if iconFrame.cooldown.SetDrawSwipe then iconFrame.cooldown:SetDrawSwipe(true) end
        if iconFrame.cooldown.SetSwipeColor then iconFrame.cooldown:SetSwipeColor(0, 0, 0, 0.8) end

        if onCooldown then
            pcall(iconFrame.cooldown.SetCooldownFromDurationObject, iconFrame.cooldown, durObj)
            if not managedVisualLocked and racialSettings.showCooldown ~= false then
                iconFrame.cooldown:Show()
            end
        else
            iconFrame.cooldown:Clear()
            iconFrame.cooldown:Hide()
        end
    end

    if iconFrame.cooldownProbe then
        if onCooldown then
            pcall(iconFrame.cooldownProbe.SetCooldownFromDurationObject, iconFrame.cooldownProbe, durObj)
        else
            iconFrame.cooldownProbe:Clear()
        end
    end

    if iconFrame.count then
        pcall(iconFrame.count.SetText, iconFrame.count, "")
        iconFrame.count:Hide()
    end

    if iconFrame.icon and not CustomIcons.ManagedVisualLocked(iconFrame) then
        if onCooldown then
            iconFrame.icon:SetDesaturated(true)
            iconFrame.icon:SetDesaturation(1)
        else
            iconFrame.icon:SetDesaturated(false)
            iconFrame.icon:SetDesaturation(0)
        end
    end
    iconFrame._ddCustomIconActive = false
    iconFrame._ddCustomIconReady = not onCooldown
end

local function UpdateSlotIcon(iconFrame, iconData)
    local slotID = iconData.slotID
    local itemID = CustomIcons.GetEquippedSlotItemID(iconFrame, slotID)
    CustomIcons.RestoreActiveIconVisual(iconFrame)
    local managedVisualLocked = CustomIcons.ManagedVisualLocked(iconFrame)

    iconFrame._textureCacheKey = "slot:" .. tostring(slotID)
    SetStableIconTexture(iconFrame, ResolveItemTexture(itemID, slotID), true)
    if itemID then
        EnsureCooldownSpanOwner(iconFrame, "_ddSlotCooldown", itemID)
    end
    if CustomIcons:ApplyTrackedTrinketEffect(iconFrame, iconData, itemID) then
        return
    end

    local onCooldown = ApplyInventorySlotCooldown(iconFrame, "_slotDurObj", slotID)
    if not managedVisualLocked then
        if iconData.settings and iconData.settings.showCooldown == false then
            iconFrame.cooldown:Hide()
        elseif onCooldown then
            iconFrame.cooldown:Show()
        else
            iconFrame.cooldown:Hide()
        end
    end

    local allowDesat = not (iconData.settings and iconData.settings.desaturateOnCooldown == false)
    if not managedVisualLocked then
        iconFrame.icon:SetDesaturation(allowDesat and onCooldown and 1 or 0)
    end
    iconFrame._ddCustomIconActive = false
    iconFrame._ddCustomIconReady = itemID ~= nil and not onCooldown
end

local function ResolveTrinketProcAuraForIcon(iconFrame, iconData)
    if not iconData then return nil end

    local slotID = iconData.slotID
    if not slotID then return nil end

    local itemID = CustomIcons.GetEquippedSlotItemID(iconFrame, slotID)
    if not itemID then return nil end

    local settings = iconData.settings or {}
    local procSpellID = settings.procSpellID
    local hasProcID = false
    pcall(function() hasProcID = procSpellID and procSpellID > 0 end)

    if not hasProcID then
        pcall(function()
            local _, spellID = C_Item.GetItemSpell(itemID)
            procSpellID = spellID
        end)
        pcall(function() hasProcID = procSpellID and procSpellID > 0 end)
    end

    if not hasProcID then
        if iconFrame then iconFrame._trinketProcWasActive = false end
        return nil
    end

    local auraData = nil
    pcall(function()
        auraData = C_UnitAuras.GetPlayerAuraBySpellID(procSpellID)
    end)

    if not auraData and iconFrame and iconFrame._cachedBuffSpellID then
        pcall(function()
            auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconFrame._cachedBuffSpellID)
        end)
        if not auraData then
            iconFrame._cachedBuffSpellID = nil
        end
    end

    if not auraData then
        pcall(function()
            local spellInfo = C_Spell.GetSpellInfo(procSpellID)
            if spellInfo and spellInfo.name then
                AuraUtil.ForEachAura("player", "HELPFUL", nil, function(a)
                    local auraName = GetAuraFieldSafe(a, "name")
                    if auraName == spellInfo.name then
                        auraData = a
                        local auraSpellID = GetAuraSpellIDSafe(a)
                        if iconFrame and auraSpellID and auraSpellID ~= procSpellID then
                            iconFrame._cachedBuffSpellID = auraSpellID
                        end
                        return true
                    end
                end)
            end
        end)
    end

    if iconFrame then
        iconFrame._trinketProcWasActive = auraData ~= nil
        if auraData then
            local now = GetTime and GetTime() or 0
            iconFrame._ddLastProcActiveAt = now
            local duration = GetAuraNumberFieldSafe(auraData, "duration")
            iconFrame._ddProcActiveUntil = GetAuraNumberFieldSafe(auraData, "expirationTime")
                or (duration and (now + duration))
                or (now + 0.75)
        end
    end
    return auraData, procSpellID, itemID
end

local function UpdateTrinketProcIcon(iconFrame, iconData)
    local slotID = iconData.slotID
    local itemID = CustomIcons.GetEquippedSlotItemID(iconFrame, slotID)
    CustomIcons.RestoreActiveIconVisual(iconFrame)
    local managedVisualLocked = CustomIcons.ManagedVisualLocked(iconFrame)

    iconFrame._textureCacheKey = "trinketProc:" .. tostring(slotID)
    -- Update trinket item texture
    SetStableIconTexture(iconFrame, ResolveItemTexture(itemID, slotID), true)
    if itemID then
        EnsureCooldownSpanOwner(iconFrame, "_ddTrinketCooldown", itemID)
    end

    local settings = iconData.settings or {}

    if settings.showItemCooldown ~= false then
        iconFrame._trinketProcWasActive = false
        iconFrame._ddProcActiveUntil = nil
        if iconFrame.count and not managedVisualLocked then
            iconFrame.count:Hide()
        end
        if iconFrame.cooldown and iconFrame.cooldown.SetReverse then
            iconFrame.cooldown:SetReverse(false)
        end
        local LCG = LibStub("LibCustomGlow-1.0", true)
        if LCG and LCG.ProcGlow_Stop then
            LCG.ProcGlow_Stop(iconFrame)
        end

        local onCooldown = runtime.ApplyTrinketSlotCooldown(iconFrame, slotID)
        if not managedVisualLocked then
            if settings.showCooldown ~= false and onCooldown then
                iconFrame.cooldown:Show()
            else
                iconFrame.cooldown:Hide()
            end
        end
        local allowDesat = not (settings.desaturateOnCooldown == false)
        if not managedVisualLocked then
            iconFrame.icon:SetDesaturation(allowDesat and onCooldown and 1 or 0)
        end
        iconFrame._ddCustomIconActive = false
        iconFrame._ddCustomIconReady = not onCooldown
        return
    end

    -- Determine proc spell ID (auto-detect or manual override)
    local procSpellID = settings.procSpellID

    -- [12.0.1] Secret value safe comparison (procSpellID > 0 can error with secret values)
    local hasProcID = false
    pcall(function() hasProcID = procSpellID and procSpellID > 0 end)

    if not hasProcID then
        pcall(function()
            local spellName, spellID = C_Item.GetItemSpell(itemID)
            procSpellID = spellID
        end)
        pcall(function() hasProcID = procSpellID and procSpellID > 0 end)
    end

    -- [REFACTOR] 3-method buff detection for on-use trinket compatibility
    -- Method A: Direct spell ID → Method B: Cached buff ID → Method C: Name scan
    local procActive = false
    local auraData = nil

    if hasProcID then
        -- Method A: Direct spell ID lookup (O(1), handles most trinkets)
        pcall(function()
            auraData = C_UnitAuras.GetPlayerAuraBySpellID(procSpellID)
        end)

        -- Method B: Cached buff spell ID from previous successful name scan (O(1))
        if not auraData and iconFrame._cachedBuffSpellID then
            pcall(function()
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconFrame._cachedBuffSpellID)
            end)
            if not auraData then
                iconFrame._cachedBuffSpellID = nil  -- cache invalidation
            end
        end

        -- Method C: Spell name scan (on-use trinkets where cast spell ID ≠ buff spell ID)
        if not auraData then
            pcall(function()
                local spellInfo = C_Spell.GetSpellInfo(procSpellID)
                if spellInfo and spellInfo.name then
                    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(a)
                        local auraName = GetAuraFieldSafe(a, "name")
                        if auraName == spellInfo.name then
                            auraData = a
                            -- Cache actual buff spell ID for fast future lookups
                            local auraSpellID = GetAuraSpellIDSafe(a)
                            if auraSpellID and auraSpellID ~= procSpellID then
                                iconFrame._cachedBuffSpellID = auraSpellID
                            end
                            return true  -- stop iteration
                        end
                    end)
                end
            end)
        end
    end

    if auraData then
        iconFrame._ddInactiveGray = nil
        iconFrame._ddForcedInactiveGray = nil
        iconFrame._ddManagedAuraExpired = nil
        iconFrame._ddCombatVisible = nil
        managedVisualLocked = false
        procActive = true
        local now = GetTime and GetTime() or 0
        iconFrame._ddLastProcActiveAt = now
        local auraDuration = GetAuraNumberFieldSafe(auraData, "duration")
        local auraExpiration = GetAuraNumberFieldSafe(auraData, "expirationTime")
        iconFrame._ddProcActiveUntil = auraExpiration
            or (auraDuration and (now + auraDuration))
            or (now + 0.75)

        -- [Visuals: Active Buff]
        iconFrame.cooldown:SetReverse(true)

        -- Proc buff duration
        if settings.showProcDuration ~= false then
            pcall(function()
                if auraDuration and auraDuration > 0 and auraExpiration then
                    local startTime = auraExpiration - auraDuration
                    iconFrame.cooldown:SetCooldown(startTime, auraDuration)
                else
                    iconFrame.cooldown:Clear()
                end
            end)
            if settings.showCooldown ~= false then
                iconFrame.cooldown:Show()
            end
        end

        -- Proc stacks
        if settings.showProcStacks ~= false then
            local stacks = GetAuraNumberFieldSafe(auraData, "applications") or 0
            if stacks > 1 then
                iconFrame.count:SetText(stacks)
                iconFrame.count:Show()
            else
                iconFrame.count:Hide()
            end
        end
        iconFrame.icon:SetDesaturated(false)
    end

    -- 2. Proc not active → show item cooldown as fallback
    if not procActive then
        -- [Visuals: Reset]
        iconFrame.cooldown:SetReverse(false)
        local LCG = LibStub("LibCustomGlow-1.0", true)
        if LCG and LCG.ProcGlow_Stop then
            LCG.ProcGlow_Stop(iconFrame)
        end


        if settings.showItemCooldown ~= false then
            local onCooldown = ApplyInventorySlotCooldown(iconFrame, "_trinketDurObj", slotID)
            if not managedVisualLocked then
                if settings.showCooldown ~= false and onCooldown then
                    iconFrame.cooldown:Show()
                else
                    iconFrame.cooldown:Hide()
                end
            end
            local allowDesat = not (settings.desaturateOnCooldown == false)
            if not managedVisualLocked then
                iconFrame.icon:SetDesaturation(allowDesat and onCooldown and 1 or 0)
            end
        else
            if not managedVisualLocked then
                iconFrame.cooldown:Clear()
                iconFrame.cooldown:Hide()
                iconFrame.icon:SetDesaturated(false)
            end
        end
        if iconFrame.count and not managedVisualLocked then
            iconFrame.count:Hide()
        end
    end
    iconFrame._ddCustomIconActive = procActive == true
    iconFrame._ddCustomIconReady = procActive ~= true
end

local function SafeSetBackdrop(frame, backdropInfo, borderColor)
    if not frame or not frame.SetBackdrop then return end
        if InCombatLockdown() then
            if not DDingUI.__cdmPendingBackdrops then
                DDingUI.__cdmPendingBackdrops = {}
            end
        DDingUI.__cdmPendingBackdrops[frame] = {backdropInfo = backdropInfo, borderColor = borderColor}
            if not DDingUI.__cdmBackdropEventFrame then
                local eventFrame = CreateFrame("Frame")
                eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:SetScript("OnEvent", function()
                for pending, settings in pairs(DDingUI.__cdmPendingBackdrops) do
                    if pending and pending.SetBackdrop then
                        pcall(pending.SetBackdrop, pending, settings.backdropInfo)
                                        if settings.borderColor then
                            pcall(pending.SetBackdropBorderColor, pending, unpack(settings.borderColor))
                        end
                            end
                        end
                        DDingUI.__cdmPendingBackdrops = {}
                end)
                DDingUI.__cdmBackdropEventFrame = eventFrame
            end
        return
    end

    pcall(frame.SetBackdrop, frame, backdropInfo)
    if borderColor then
        pcall(frame.SetBackdropBorderColor, frame, unpack(borderColor))
    end
end

local function ApplyIconBorder(iconFrame, settings)
    if not iconFrame or not iconFrame.border then return end
    local edgeSize = settings.borderSize or 0
    if edgeSize <= 0 then
        ShowTextureBorder(iconFrame.border, false)
        iconFrame.border:Hide()
        return
    end

    -- Use texture-based borders (no SetBackdrop = no taint)
    local borderColor = settings.borderColor or {0, 0, 0, 1}
    if not iconFrame.border.__dduiBorders then
        CreateTextureBorder(iconFrame.border, edgeSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    else
        UpdateTextureBorderSize(iconFrame.border, edgeSize)
        UpdateTextureBorderColor(iconFrame.border, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    end
    ShowTextureBorder(iconFrame.border, true)
    iconFrame.border:Show()
end

local function BuildCountSettings(iconSettings)
    local cs = iconSettings.countSettings or {}
    return {
        size = cs.size or 16,
        anchor = cs.anchor or "BOTTOMRIGHT",
        offsetX = cs.offsetX or -2,
        offsetY = cs.offsetY or 2,
        color = cs.color or {1, 1, 1, 1},
        font = cs.font,  -- Font name from LSM, nil means use global font
    }
end

local function ApplyCooldownTextStyle(cooldown, iconData)
    if not cooldown or not cooldown.GetRegions then return end

    local fontString
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            fontString = region
            break
        end
    end
    if not fontString then return end

    local cds = (iconData.settings and iconData.settings.cooldownSettings) or {}
    local fontPath = DDingUI:GetGlobalFont()
    local size = cds.size or 12
    local color = cds.color or { 1, 1, 1, 1 }

    -- Reuse general viewer shadow offsets for consistency
    local shadowOffsetX = 1
    local shadowOffsetY = -1
    if DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.viewers and DDingUI.db.profile.viewers.general then
        shadowOffsetX = DDingUI.db.profile.viewers.general.cooldownShadowOffsetX or shadowOffsetX
        shadowOffsetY = DDingUI.db.profile.viewers.general.cooldownShadowOffsetY or shadowOffsetY
    end

    local _, _, flags = fontString:GetFont()
    fontString:SetFont(fontPath, size, flags)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fontString:SetShadowOffset(shadowOffsetX, shadowOffsetY)
end

local function ApplyAspectRatioCrop(texture, aspect, baseZoom)
    if not texture or not texture.SetTexCoord then return end

    aspect = tonumber(aspect) or 1.0
    if aspect <= 0 then aspect = 1.0 end

    baseZoom = tonumber(baseZoom) or 0
    if baseZoom < 0 then baseZoom = 0 end
    if baseZoom > 0.499 then baseZoom = 0.499 end

    local left, right, top, bottom = baseZoom, 1 - baseZoom, baseZoom, 1 - baseZoom
    local regionW = right - left
    local regionH = bottom - top

    if regionW > 0 and regionH > 0 and aspect ~= 1.0 then
        local currentRatio = regionW / regionH
        if aspect > currentRatio then
            local desiredH = regionW / aspect
            local cropH = (regionH - desiredH) / 2
            top = top + cropH
            bottom = bottom - cropH
        elseif aspect < currentRatio then
            local desiredW = regionH * aspect
            local cropW = (regionW - desiredW) / 2
            left = left + cropW
            right = right - cropW
        end
    end

    texture:SetTexCoord(left, right, top, bottom)
end

local function ApplyIconSettings(iconFrame, iconData, groupSettings)
    EnsureIconSettings(iconData)
    local settings = iconData.settings or {}
    -- Use icon's own size if useOwnSize is true, otherwise fall back to group size, then default
    local size
    if settings.useOwnSize then
        size = settings.iconSize or DEFAULT_ICON_SETTINGS.iconSize
    else
        size = settings.iconSize or (groupSettings and groupSettings.iconSize) or DEFAULT_ICON_SETTINGS.iconSize
    end
    local aspect = settings.aspectRatio or 1.0
    local width = size
    local height = size
    if aspect > 1.0 then
        height = size / aspect
    elseif aspect < 1.0 then
        width = size * aspect
    end
    -- [FIX] DynamicIconBridge 관리 아이콘은 GroupSystem이 크기를 관리하므로 건너뜀
    -- CustomIcons의 aspectRatio와 GroupSystem의 aspectRatioCrop이 다르면
    -- SetSize → snap-back 훅 → 1프레임 깜빡임 발생 방지
    if not iconFrame._ddIsManaged then
        iconFrame:SetSize(width, height)
    end

    if iconFrame.icon and not iconFrame._ddIsManaged then
        iconFrame.icon:ClearAllPoints()
        iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
        iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
        -- Mirror CooldownViewer behavior: crop instead of stretching when aspect ratio changes.
        ApplyAspectRatioCrop(iconFrame.icon, aspect, 0.08)
    end

    ApplyIconBorder(iconFrame, {
        borderSize = settings.borderSize or DEFAULT_ICON_SETTINGS.borderSize,
        borderColor = settings.borderColor or DEFAULT_ICON_SETTINGS.borderColor,
    })

    local managedGroupSettings = groupSettings
        or iconFrame._groupSettings
        or (iconFrame._ddContainerRef and iconFrame._ddContainerRef._groupSettings)
    local groupOwnsText = iconFrame._ddIsManaged and managedGroupSettings
    if not groupOwnsText then
        local cs = BuildCountSettings(settings)
        local fontPath = DDingUI:GetGlobalFont()
        if cs.font and LSM then
            local fetchedFont = LSM:Fetch("font", cs.font)
            if fetchedFont then
                fontPath = fetchedFont
            end
        end
        if fontPath and cs.size and tonumber(cs.size) > 0 then
            -- pcall to safely set font just in case path is invalid
            pcall(function() iconFrame.count:SetFont(fontPath, tonumber(cs.size), "OUTLINE") end)
        else
            pcall(function() iconFrame.count:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE") end)
        end
        if cs.color then
            iconFrame.count:SetTextColor(unpack(cs.color))
        end
        iconFrame.count:ClearAllPoints()
        iconFrame.count:SetPoint(cs.anchor, iconFrame, cs.anchor, cs.offsetX, cs.offsetY)

        -- Apply cooldown text settings
        local cooldownSettings = settings.cooldownSettings or {size = 12, color = {1, 1, 1, 1}}
        if iconFrame.cooldown.SetCountdownFont then
            local cdFontPath = DDingUI:GetGlobalFont()
            iconFrame.cooldown:SetCountdownFont(cdFontPath, cooldownSettings.size, "OUTLINE")
        end
        ApplyCooldownTextStyle(iconFrame.cooldown, iconData)
    end
    -- Note: Cooldown text color is not directly controllable with standard WoW cooldown frames.
    -- The color setting is saved but may not be applied depending on WoW API limitations.
end

-- ------------------------
-- Aura (buff/debuff) icon update — trinketProc 패턴 기반
-- CDM reparent가 아닌 독립 프레임으로 buff 추적
-- ------------------------


local function UpdateAuraIcon(iconFrame, iconData)
    local spellID = iconData.id
    if not spellID or not iconFrame then return end

    local settings = iconData.settings or {}
    local allowDesat = not (settings.desaturateOnCooldown == false)
    local timedOnly = IsEventDrivenCustomTimedAuraConfig(GetCustomTimedAuraConfig(iconData))
    iconFrame._textureCacheKey = "aura:" .. tostring(spellID)
    iconFrame._fallbackTexture = GetStoredIconTexture(iconData) or iconFrame._fallbackTexture or FALLBACK_SPELL_ICON
    if not timedOnly then
        SetStableIconTexture(iconFrame, ResolveSpellTexture(spellID, iconFrame._fallbackTexture), true)
    end

    -- 1. buff 활성 여부 확인
    local auraData = ResolvePlayerAuraForIcon(iconFrame, iconData)
    if not timedOnly then
        pcall(function()
            if not auraData then
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            end
        end)
    end

    -- spellName 기반 폴백 (buff spellID ≠ spell spellID인 경우)
    if not timedOnly and not auraData and not iconFrame._cachedAuraSpellID then
        local now = GetTime()
        if not iconFrame._lastAuraScan or (now - iconFrame._lastAuraScan) > 1.0 then
            iconFrame._lastAuraScan = now
            pcall(function()
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                if spellInfo and spellInfo.name then
                    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(a)
                        local auraName = GetAuraFieldSafe(a, "name")
                        if auraName == spellInfo.name then
                            auraData = a
                            local auraSpellID = GetAuraSpellIDSafe(a)
                            if auraSpellID and auraSpellID ~= spellID then
                                iconFrame._cachedAuraSpellID = auraSpellID
                            end
                            return true
                        end
                    end)
                end
            end)
        end
    end

    -- 캐시된 buff spellID로 재시도
    if not timedOnly and not auraData and iconFrame._cachedAuraSpellID then
        pcall(function()
            if not auraData then
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconFrame._cachedAuraSpellID)
            end
        end)
    end

    local auraExpirationTime = auraData and GetAuraNumberFieldSafe(auraData, "expirationTime")
    if auraExpirationTime and auraExpirationTime > 0 then
        iconFrame._ddAuraActiveUntil = auraExpirationTime
    elseif not auraData then
        iconFrame._ddAuraActiveUntil = nil
    end

    local auraTexture = auraData and (GetAuraFieldSafe(auraData, "icon") or GetAuraFieldSafe(auraData, "iconID"))
    local activeTexture
    if auraData and GetAuraFieldSafe(auraData, "__ddinguiTimedAura") then
        activeTexture = auraTexture or GetStoredIconTexture(iconData)
    else
        activeTexture = GetStoredIconTexture(iconData) or auraTexture
    end
    if activeTexture then
        SetStableIconTexture(iconFrame, activeTexture, true)
    end

    local isActive = (auraData ~= nil)
    iconFrame._ddCustomIconActive = isActive
    iconFrame._ddCustomIconReady = not isActive
    local wasActive = iconFrame._auraWasActive
    local stateChanged = isActive ~= wasActive

    if stateChanged then
        iconFrame._auraWasActive = isActive
    end

    if auraData then
        -- [FIX] 버프 스와이프 방향: fill-up (CDM 패턴)
        -- 활성: duration 쿨다운 + 스택 표시
        pcall(function()
            local auraDuration = GetAuraNumberFieldSafe(auraData, "duration")
            local auraExpiration = GetAuraNumberFieldSafe(auraData, "expirationTime")
            if auraDuration and auraDuration > 0 and auraExpiration then
                local startTime = GetAuraNumberFieldSafe(auraData, "startTime") or (auraExpiration - auraDuration)
                local isTimedAura = GetAuraFieldSafe(auraData, "__ddinguiTimedAura")
                local cooldownMode = isTimedAura and "timedAura" or "aura"
                if ShouldApplyAuraCooldownSpan(iconFrame, startTime, auraDuration, cooldownMode) then
                    iconFrame.cooldown:SetReverse(true)
                    if isTimedAura
                        and C_DurationUtil and C_DurationUtil.CreateDuration
                        and iconFrame.cooldown.SetCooldownFromDurationObject
                    then
                        iconFrame._customTimedAuraDuration = iconFrame._customTimedAuraDuration or C_DurationUtil.CreateDuration()
                        iconFrame._customTimedAuraDuration:SetTimeFromStart(startTime, auraDuration)
                        iconFrame.cooldown:SetCooldownFromDurationObject(iconFrame._customTimedAuraDuration)
                    else
                        iconFrame.cooldown:SetCooldown(startTime, auraDuration)
                    end
                end
            else
                ResetAuraCooldownSpanCache(iconFrame)
                iconFrame.cooldown:Clear()
            end
        end)
        if settings.showCooldown ~= false then
            iconFrame.cooldown:Show()
        else
            iconFrame.cooldown:Hide()
        end

        local stacks = GetAuraNumberFieldSafe(auraData, "applications") or 0
        if stacks > 1 and settings.showCharges ~= false then
            pcall(iconFrame.count.SetText, iconFrame.count, stacks)
            iconFrame.count:Show()
        else
            iconFrame.count:Hide()
        end

        iconFrame._ddManagedAuraExpired = nil
        iconFrame._ddCombatVisible = nil
        iconFrame._ddCombatKeepAlive = nil
        iconFrame._ddInactiveGray = nil
        iconFrame._ddForcedInactiveGray = nil
        local managedAlpha = 1
        if iconFrame._groupSettings and iconFrame._groupSettings.groupAlpha ~= nil then
            managedAlpha = iconFrame._groupSettings.groupAlpha
        end
        local alphaLocked = IsFlightHideAlphaLocked()
        if iconFrame.SetAlpha and not alphaLocked then
            iconFrame:SetAlpha(managedAlpha)
            iconFrame._ddLastGroupAlpha = managedAlpha
        end
        iconFrame.icon:SetDesaturated(false)
        iconFrame.icon:SetDesaturation(0)
        if not alphaLocked then
            iconFrame.icon:SetAlpha(1.0)
        end
        iconFrame:Show()
    else
        -- 비활성: 쿨다운 클리어 + 숨김
        iconFrame.cooldown:Clear()
        iconFrame.cooldown:Hide()
        iconFrame.count:Hide()
        ResetAuraCooldownSpanCache(iconFrame)
        iconFrame._ddTimedAuraActiveUntil = nil
        iconFrame._ddAuraActiveUntil = nil
        iconFrame._ddLastDynamicActiveAt = nil
        iconFrame._ddLastAuraActiveAt = nil
        iconFrame._wasVisibleInGroup = nil
        iconFrame._auraWasActive = false
        iconFrame._customTimedAuraDuration = nil

        if allowDesat then
            iconFrame.icon:SetDesaturated(true)
        else
            iconFrame.icon:SetDesaturated(false)
        end
        if iconFrame._ddIsManaged then
            iconFrame._ddManagedAuraExpired = true
            CustomIcons.SuppressExpiredIconVisual(iconFrame)
            if stateChanged and DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
                DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
            end
        else
            if not IsFlightHideAlphaLocked() then
                iconFrame.icon:SetAlpha(1.0)
            end
        end
        -- [FIX] managed 프레임은 GroupRenderer가 Show/Hide 관리
        if not iconFrame._ddIsManaged then
            iconFrame:Hide()
        end
    end
    CustomIcons.ApplyManagedGroupTextOptions(iconFrame)
end

function CustomIcons:ResolvePlayerAuraForIcon(iconFrame, iconData)
    return ResolvePlayerAuraForIcon(iconFrame, iconData)
end

function CustomIcons:GetActiveCustomTimedAuraForIcon(iconData)
    return GetActiveCustomTimedAura(iconData)
end

function CustomIcons:ActivateExternalTimedAura(stateID, duration, iconTexture, stacks, startTime)
    stateID = tonumber(stateID)
    duration = tonumber(duration)
    if not stateID or not duration or duration <= 0 then return false end
    local _, changed = ActivateCustomTimedAura(stateID, {
        stateID = stateID,
        duration = duration,
        trigger = "trinket_effect",
        iconTexture = iconTexture,
    }, startTime, stateID, { stacks = stacks })
    return changed == true
end

function CustomIcons:DeactivateExternalTimedAura(stateID)
    stateID = tonumber(stateID)
    if not stateID then return false end
    return DeactivateCustomTimedAura(stateID)
end

function CustomIcons:IsCustomTimedAuraIcon(iconData)
    return GetCustomTimedAuraConfig(iconData) ~= nil
end

local function IconListContains(iconList, iconKey)
    if type(iconList) ~= "table" or not iconKey then return false end
    for _, key in ipairs(iconList) do
        if key == iconKey then
            return true
        end
    end
    return false
end

local function GroupOrderContainsDynamicIcon(groupSettings, iconKey)
    local order = groupSettings and groupSettings.iconOrder
    if type(order) ~= "table" or not iconKey then return false end
    local token = "dyn:" .. tostring(iconKey)
    for _, value in ipairs(order) do
        if value == token then
            return true
        end
    end
    return false
end

local function IsIconLinkedToCDMGroup(db, iconKey, iconData, groupName, groupSettings)
    if not iconKey or not iconData or not groupName then return false end

    local settings = iconData.settings or {}
    if settings.targetCDMGroup == groupName then
        return true
    end

    if GroupOrderContainsDynamicIcon(groupSettings, iconKey) then
        return true
    end

    local sourceKey = groupSettings and groupSettings.sourceGroupKey
    local sourceGroup = sourceKey and db and db.groups and db.groups[sourceKey]
    if IconListContains(sourceGroup and sourceGroup.icons, iconKey) then
        return true
    end

    for _, linkedGroup in pairs((db and db.groups) or {}) do
        if linkedGroup and linkedGroup.linkedCDMGroup == groupName and IconListContains(linkedGroup.icons, iconKey) then
            return true
        end
    end

    return false
end

function CustomIcons:GetActiveCustomTimedAuraEntriesForCDMGroup(groupName, groupSettings)
    if CustomIcons.ClearExpiredCustomTimedAuras then
        CustomIcons.ClearExpiredCustomTimedAuras()
    end
    local db = GetDynamicDB()
    local iconDataByKey = db and db.iconData
    if not iconDataByKey then return nil end

    local now = GetTime and GetTime() or 0
    local result
    local seenStateIDs = {}
    for iconKey, iconData in pairs(iconDataByKey) do
        local config = GetCustomTimedAuraConfig(iconData)
        local state = config and runtime.customTimedAuras[config.stateID]
        if state and state.expirationTime and state.expirationTime > now
            and IsIconLinkedToCDMGroup(db, iconKey, iconData, groupName, groupSettings)
            and not seenStateIDs[config.stateID]
        then
            local frame = runtime.iconFrames[iconKey]
            if not frame and CustomIcons.EnsureDynamicIconFrame then
                frame = CustomIcons:EnsureDynamicIconFrame(iconKey, iconData)
            end
            if frame then
                seenStateIDs[config.stateID] = true
                frame._ddTimedAuraActiveUntil = state.expirationTime
                frame._ddLastAuraActiveAt = now
                frame._ddLastDynamicActiveAt = now
                frame._wasVisibleInGroup = true
                frame._auraWasActive = true
                frame._ddManagedAuraExpired = nil
                frame._ddCombatVisible = nil
                frame._ddInactiveGray = nil
                frame._ddForcedInactiveGray = nil
                if state.iconTexture then
                    SetStableIconTexture(frame, state.iconTexture, true)
                end
                CustomIcons.RestoreActiveIconVisual(frame)
                CustomIcons.ApplyManagedGroupTextOptions(frame)
                result = result or {}
                result[#result + 1] = {
                    iconKey = iconKey,
                    frame = frame,
                    iconData = iconData,
                    active = true,
                    combatVisible = true,
                }
            end
        end
    end

    return result
end

function CustomIcons:ResolveTrinketProcAuraForIcon(iconFrame, iconData)
    return ResolveTrinketProcAuraForIcon(iconFrame, iconData)
end

-- ------------------------
-- Event-based update system
-- ------------------------

-- [CDM 패턴] 디바운스 상태 — 같은 틱에 여러 이벤트가 동시에 UpdateAllIcons를
-- 호출해도 실제 실행은 재사용 디스패치 프레임에서 단 1회만 수행
local _pendingIconUpdate = false
local _pendingIconLayoutNotify = false
local _iconUpdateDispatchTimer
local _iconUpdateDueAt = 0

local function GetDynamicLayoutStateToken(frame, iconData)
    if not frame or not iconData then return nil end
    if iconData.type ~= "aura" and iconData.type ~= "trinketProc" then return nil end
    local expiredManagedAura = iconData.type == "aura" and frame._ddManagedAuraExpired
    if expiredManagedAura then return "inactive" end

    local now = GetTime and GetTime() or 0
    if iconData.type == "aura" then
        if CustomIcons.IsCustomTimedAuraIcon and CustomIcons:IsCustomTimedAuraIcon(iconData) then
            return CustomIcons:GetActiveCustomTimedAuraForIcon(iconData) and "active" or "inactive"
        end
        return frame._auraWasActive == true and "active" or "inactive"
    end

    local activeUntil = MaxSafeNumber(frame._ddTimedAuraActiveUntil, frame._ddAuraActiveUntil, frame._ddProcActiveUntil)
    local active = frame._auraWasActive == true
        or frame._trinketProcWasActive == true
        or (activeUntil and activeUntil > now)
        or (not expiredManagedAura and InCombatLockdown and InCombatLockdown() and HasRecentEffectState(frame, now))

    return active and "active" or "inactive"
end

local function QueueIconLayoutNotify(mode)
    if not mode then return end
    if mode == true or mode == "force" then
        _pendingIconLayoutNotify = "force"
    elseif _pendingIconLayoutNotify ~= "force" then
        _pendingIconLayoutNotify = mode
    end
end

local function ExecuteUpdateAllIcons(filter)
    local layoutStateChanged = false
    if CustomIcons.ClearExpiredCustomTimedAuras and CustomIcons.ClearExpiredCustomTimedAuras() then
        layoutStateChanged = true
    end

    local function ReapplyManagedGroupText(frame)
        CustomIcons.ApplyManagedGroupTextOptions(frame)
    end

    local db = GetDynamicDB()
    local cooldownOnly = filter == "cooldown"
    for iconKey, frame in pairs(runtime.iconFrames) do
        if frame then
            local iconData = db and db.iconData and db.iconData[iconKey]
            local iconType = iconData and iconData.type
            local typeMatches = true
            if filter == "aura" then
                typeMatches = iconType == "aura" or iconType == "trinketProc"
            elseif filter == "item" then
                typeMatches = iconType == "item" or iconType == "slot" or iconType == "trinketProc"
            elseif filter == "cooldown" then
                typeMatches = iconType == "item" or iconType == "slot" or iconType == "trinketProc" or iconType == "spell" or iconType == "racial"
            end
            if iconData and typeMatches and (frame:IsVisible() or iconType == "aura" or iconType == "trinketProc" or frame._ddIsManaged) then
                local okUpdate, err = pcall(function()
                    local beforeLayoutState = GetDynamicLayoutStateToken(frame, iconData)

                    if not frame._ddIsManaged and not cooldownOnly then
                        ApplyIconSettings(frame, iconData, frame._groupSettings)
                    else
                        if frame.count and not frame._fontInitialized then
                            local fontPath = DDingUI:GetGlobalFont() or STANDARD_TEXT_FONT
                            pcall(frame.count.SetFont, frame.count, fontPath, 16, "OUTLINE")
                            frame._fontInitialized = true
                        end
                    end
                    if iconData.type == "item" then
                        UpdateItemIcon(frame, iconData)
                    elseif iconData.type == "spell" then
                        if CustomIcons:IsCurrentRacialSpellIcon(iconData) then
                            UpdateRacialIconFrame(frame, iconData)
                        else
                            UpdateSpellIconFrame(frame, iconData)
                        end
                    elseif iconData.type == "racial" then
                        UpdateRacialIconFrame(frame, iconData)
                    elseif iconData.type == "slot" then
                        UpdateSlotIcon(frame, iconData)
                    elseif iconData.type == "trinketProc" then
                        UpdateTrinketProcIcon(frame, iconData)
                    elseif iconData.type == "aura" then
                        UpdateAuraIcon(frame, iconData)
                    end
                    CustomIcons:UpdateDynamicIconStateGlow(frame, iconData)
                    ReapplyManagedGroupText(frame)

                    local afterLayoutState = GetDynamicLayoutStateToken(frame, iconData)
                    if beforeLayoutState and afterLayoutState and beforeLayoutState ~= afterLayoutState then
                        layoutStateChanged = true
                    end
                end)
                if okUpdate then
                    frame._ddLastUpdateError = nil
                else
                    frame._ddLastUpdateError = tostring(err)
                end
            end
        end
    end

    return layoutStateChanged
end

-- [CDM 패턴] 공개 진입점 — 이벤트 핸들러는 이 함수만 호출
-- 같은 틱 내 다수 호출을 1회로 병합, 다음 프레임에 실행
local function RunPendingIconUpdate(now)
    _pendingIconUpdate = false
    local notifyLayout = _pendingIconLayoutNotify
    _pendingIconLayoutNotify = false
    local updateFilter = runtime.pendingIconUpdateFilter
    runtime.pendingIconUpdateFilter = nil
    runtime.lastIconUpdateAt = GetTime and GetTime() or now
    local layoutStateChanged = ExecuteUpdateAllIcons(updateFilter)
    if notifyLayout and DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        local forceLayout = notifyLayout == true or notifyLayout == "force"
        if forceLayout or layoutStateChanged then
            DDingUI.DynamicIconBridge:NotifyIconsChanged(forceLayout)
        end
    end
end

local function ScheduleCustomIconWork()
    if runtime.customIconDispatchRunning then return end

    local now = GetTime and GetTime() or 0
    local dueAt
    local watcher = runtime.cooldownWatcher
    if watcher and (watcher.evaluatePending or watcher.refreshPending) then
        dueAt = now
    end
    if _pendingIconUpdate and (not dueAt or _iconUpdateDueAt < dueAt) then
        dueAt = _iconUpdateDueAt
    end
    if runtime.refreshAllLayoutsPending then
        local layoutDueAt = runtime.layoutRefreshDueAt or now
        if not dueAt or layoutDueAt < dueAt then
            dueAt = layoutDueAt
        end
    end
    if not dueAt then return end

    if _iconUpdateDispatchTimer and runtime.customIconDispatchDueAt
        and runtime.customIconDispatchDueAt <= dueAt
    then
        return
    end
    if _iconUpdateDispatchTimer then
        _iconUpdateDispatchTimer:Cancel()
    end

    runtime.customIconDispatchDueAt = dueAt
    _iconUpdateDispatchTimer = C_Timer.NewTimer(math.max(0, dueAt - now), function()
        _iconUpdateDispatchTimer = nil
        runtime.customIconDispatchDueAt = nil
        runtime.customIconDispatchRunning = true

        local dispatchNow = GetTime and GetTime() or 0
        local currentWatcher = runtime.cooldownWatcher
        if currentWatcher and currentWatcher.evaluatePending and runtime.EvaluateCustomCooldownWatches then
            currentWatcher.evaluatePending = false
            runtime.EvaluateCustomCooldownWatches()
        end
        if currentWatcher and currentWatcher.refreshPending and runtime.FlushCustomCooldownIconRefresh then
            runtime.FlushCustomCooldownIconRefresh()
        end
        if _pendingIconUpdate and _iconUpdateDueAt <= dispatchNow + 0.001 then
            RunPendingIconUpdate(dispatchNow)
        end
        if runtime.refreshAllLayoutsPending
            and (runtime.layoutRefreshDueAt or 0) <= dispatchNow + 0.001
            and runtime.RunBridgeLayoutRefresh
        then
            runtime.RunBridgeLayoutRefresh()
        end

        runtime.customIconDispatchRunning = false
        ScheduleCustomIconWork()
    end)
end

UpdateAllIcons = function(needsLayoutNotify, filter)
    if needsLayoutNotify then
        QueueIconLayoutNotify(needsLayoutNotify)
    end
    if filter then
        if runtime.pendingIconUpdateFilter ~= "all" then
            if filter == "all" or not runtime.pendingIconUpdateFilter then
                runtime.pendingIconUpdateFilter = filter
            elseif runtime.pendingIconUpdateFilter ~= filter then
                runtime.pendingIconUpdateFilter = "all"
            end
        end
    elseif not runtime.pendingIconUpdateFilter then
        runtime.pendingIconUpdateFilter = "all"
    end
    if _pendingIconUpdate then return end
    _pendingIconUpdate = true
    local now = GetTime and GetTime() or 0
    local inCombat = InCombatLockdown and InCombatLockdown()
    local minInterval = inCombat and 0.08 or 0.02
    if filter == "aura" then
        minInterval = inCombat and 0.12 or 0.04
    end
    local elapsed = now - (runtime.lastIconUpdateAt or 0)
    local delay = elapsed >= minInterval and 0 or (minInterval - elapsed)
    _iconUpdateDueAt = now + delay
    ScheduleCustomIconWork()
end

local function HandleCooldownDone(cooldownFrame)
    local parent = cooldownFrame and cooldownFrame:GetParent()
    local iconKey = parent and parent._iconKey
    if iconKey and runtime.UpdateDynamicIcon then
        runtime.UpdateDynamicIcon(iconKey)
        return
    end
    UpdateAllIcons(nil, "cooldown")
end

local function ForceManagedGroupLayoutRefresh()
    local gr = DDingUI and DDingUI.GroupRenderer
    if gr and gr.InvalidateLayoutCaches then
        gr:InvalidateLayoutCaches(true)
    end

    local bridge = DDingUI and DDingUI.DynamicIconBridge
    if bridge and bridge.NotifyIconsChanged then
        bridge:NotifyIconsChanged(true)
    elseif DDingUI and DDingUI.GroupSystem and DDingUI.GroupSystem.RequestFullUpdate then
        DDingUI.GroupSystem:RequestFullUpdate()
    end
end

local function ScheduleSpecReload()
    if InCombatLockdown and InCombatLockdown() then
        runtime.pendingSpecReload = true
        if not runtime.deferredSpecReloadFrame then
            runtime.deferredSpecReloadFrame = CreateFrame("Frame")
            runtime.deferredSpecReloadFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                runtime.pendingSpecReload = false
                ScheduleSpecReload()
            end)
        end
        runtime.deferredSpecReloadFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        if UpdateAllIcons then
            UpdateAllIcons("aura", "aura")
        end
        return
    end

    if runtime.pendingSpecReload then return end
    runtime.pendingSpecReload = true

    -- [FIX] 다단계 재시도: CDM 뷰어 재생성 대기
    -- Phase 1 (0.3s): 빠른 초기 갱신
    C_Timer.After(0.3, function()
        runtime.pendingSpecReload = false
        -- trinket proc 캐시 무효화
        for _, frame in pairs(runtime.iconFrames or {}) do
            if frame then frame._cachedBuffSpellID = nil end
        end
        if CustomIcons and CustomIcons.LoadDynamicIcons then
            CustomIcons:LoadDynamicIcons()
        else
            if RefreshAllLayouts then RefreshAllLayouts() end
            UpdateAllIcons(nil, "all")
        end
    end)
    -- Phase 2 (1.5s): CDM 안정화 후 최종 갱신
    C_Timer.After(1.5, function()
        if CustomIcons and CustomIcons.LoadDynamicIcons then
            CustomIcons:LoadDynamicIcons()
        else
            if RefreshAllLayouts then RefreshAllLayouts() end
            UpdateAllIcons(nil, "all")
        end
        ForceManagedGroupLayoutRefresh()
    end)
end

local function HandleCustomTimedAuraEvent(event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        local unit, _, _, spellID = ...
        if unit ~= "player" then return false end
        spellID = SafeNumber(spellID)
        if spellID and timeSpiralGlowSuppressSpells[spellID] then
            RecordTimedAuraDebug(374968, "suppressArmed", tostring(spellID))
            timeSpiralSuppressGlowUntil = GetTime() + TIME_SPIRAL_GLOW_SUPPRESS_SECONDS
        end
        return false
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" then return false end
        spellID = SafeNumber(spellID)
        local changed = false
        local activated = {}
        local db = GetDynamicDB()
        local iconDataByKey = db and db.iconData
        if spellID and type(iconDataByKey) == "table" then
            for _, iconData in pairs(iconDataByKey) do
                if type(iconData) == "table" and iconData.type == "aura" then
                    local config = GetCustomTimedAuraConfig(iconData)
                    local iconSpellID = SafeNumber(iconData.id)
                    local stateID = config and SafeNumber(config.stateID)
                    if config and config.trigger == "spellcast"
                        and (iconSpellID == spellID or stateID == spellID)
                        and not activated[stateID or spellID]
                    then
                        activated[stateID or spellID] = true
                        local _, didChange = ActivateCustomTimedAura(stateID or spellID, config, nil, iconSpellID or spellID)
                        changed = didChange or changed
                    end
                end
            end
        end
        return changed
    end

    if event == "UNIT_AURA" then
        local unit, updateInfo = ...
        if unit ~= "player" then return false end
        return ScanBloodlustTimedAura(updateInfo)
    end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellID = SafeNumber(...)
        if spellID and TIME_SPIRAL_TRIGGERS[spellID] then
            RecordTimedAuraDebug(374968, "glowShow", tostring(spellID))
            if GetTime() < timeSpiralSuppressGlowUntil then
                RecordTimedAuraDebug(374968, "suppressed", tostring(spellID))
                return false
            end
            local iconCount = CountCustomTimedAuraLinks(374968)
            local active = runtime.customTimedAuras[374968]
            if iconCount <= 0 or (active and active.expirationTime and active.expirationTime > GetTime()) then return false end
            local _, changed = ActivateCustomTimedAura(374968, CUSTOM_TIMED_AURA_CONFIGS[374968])
            return changed
        end
        return false
    end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellID = SafeNumber(...)
        if spellID and TIME_SPIRAL_TRIGGERS[spellID] then
            RecordTimedAuraDebug(374968, "glowHide", tostring(spellID))
            return DeactivateCustomTimedAura(374968)
        end
        return false
    end

    if event == "PLAYER_DEAD" then
        local changed = false
        for spellID in pairs(runtime.customTimedAuras or {}) do
            changed = DeactivateCustomTimedAura(spellID) or changed
        end
        return changed
    end

    return false
end

local function HasItemCooldownIcon()
    local watcher = runtime.cooldownWatcher
    if watcher and watcher.kindsInitialized then
        return (watcher.activeTargetCount or 0) > 0, watcher.hasSpellTarget == true
    end

    local db = GetDynamicDB()
    local hasItemCooldownIcon = false
    local hasSpellCooldownIcon = false
    for _, iconData in pairs((db and db.iconData) or {}) do
        if iconData.type == "item" or iconData.type == "slot" or iconData.type == "trinketProc" then
            hasItemCooldownIcon = true
        elseif iconData.type == "spell" or iconData.type == "racial" then
            hasSpellCooldownIcon = true
        end
        if hasItemCooldownIcon and hasSpellCooldownIcon then
            return true, true
        end
    end
    return hasItemCooldownIcon, hasSpellCooldownIcon
end

local function RefreshItemCooldownIcons(needsLayoutNotify)
    if runtime.QueueCustomCooldownIconRefresh then
        runtime.QueueCustomCooldownIconRefresh(needsLayoutNotify)
    else
        UpdateAllIcons(needsLayoutNotify, "item")
    end
end

local function ClearRacialCooldownCache()
    local racials = DDingUI.CustomIconRacials
    if racials and racials.ClearCache then
        racials:ClearCache()
    end
end

local function EnsureEventFrame()
    if runtime.eventFrame then return end
    runtime.eventFrame = CreateFrame("Frame")

    -- Register for events that should trigger icon updates
    runtime.eventFrame:RegisterEvent("BAG_UPDATE")                    -- Bag contents change
    runtime.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")            -- Coalesced bag count changes
    runtime.eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")           -- Item cooldown changes
    runtime.eventFrame:RegisterEvent("ITEM_COUNT_CHANGED")             -- Item counts change
    runtime.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")          -- Spell cooldowns change
    runtime.eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")           -- Spell charges change
    runtime.eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")            -- Spells become usable/unusable (often at cooldown end)
    runtime.eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")      -- Cooldown updates (reliable at cooldown end)
    runtime.eventFrame:RegisterEvent("ARENA_COOLDOWNS_UPDATE")
    runtime.eventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    runtime.eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")         -- Equipment changes
    runtime.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")       -- Equipment changes (alternative event)
    runtime.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")  -- Spec change
    runtime.eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")   -- Talent group/spec change (alternative event)
    runtime.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")           -- Talent changes for Time Spiral glow filters
    runtime.eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")           -- Talent changes for Time Spiral glow filters
    runtime.eventFrame:RegisterEvent("SPELLS_CHANGED")                -- Spellbook changes (often after spec change)
    runtime.eventFrame:RegisterUnitEvent("UNIT_AURA", "player")        -- Trinket proc/custom buff tracking
    runtime.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")          -- World load trigger
    runtime.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")           -- Clear healthstone-style combat lockouts
    runtime.eventFrame:RegisterEvent("PLAYER_DEAD")
    runtime.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    runtime.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    runtime.eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    runtime.eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    RebuildTimeSpiralGlowFilters()

    runtime.eventFrame:SetScript("OnEvent", function(self, event, ...)
        local arg1 = ...

        if event == "PLAYER_ENTERING_WORLD" then
            runtime.loginTime = runtime.loginTime or GetTime()
            ClearRacialCooldownCache()
            RebuildTimeSpiralGlowFilters()
            C_Timer.After(0.2, function()
                UpdateAllIcons("force", "all")
            end)
            C_Timer.After(1.0, function() ScheduleSpecReload() end)
            return
        end

        if event == "PLAYER_REGEN_ENABLED" then
            ClearItemCombatLockouts()
            if runtime.RequestCustomCooldownWatchRegistration then
                runtime.RequestCustomCooldownWatchRegistration()
            end
            RefreshItemCooldownIcons()
            return
        end

        -- Only update for events that affect the player
        if event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_AURA" then
            if arg1 ~= "player" then return end
        end

        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
            return
        end

        if event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "ACTIVE_TALENT_GROUP_CHANGED"
            or event == "PLAYER_TALENT_UPDATE"
            or event == "TRAIT_CONFIG_UPDATED"
            or event == "SPELLS_CHANGED"
        then
            ClearRacialCooldownCache()
            RebuildTimeSpiralGlowFilters()
            ScheduleSpecReload()
            return
        end

        local customTimedChanged = HandleCustomTimedAuraEvent(event, ...)
        local succeededSpellID = event == "UNIT_SPELLCAST_SUCCEEDED" and SafeNumber(select(3, ...)) or nil
        local isRacialSpellcast = succeededSpellID and succeededSpellID == GetPlayerRacialSpellID()
        if event == "UNIT_SPELLCAST_SENT" then return end
        if (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
            or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            and not customTimedChanged then
            return
        end
        local isItemCooldownEvent = event == "UNIT_SPELLCAST_SUCCEEDED"
            or event == "BAG_UPDATE_COOLDOWN"
            or event == "SPELL_UPDATE_COOLDOWN"
            or event == "ACTIONBAR_UPDATE_COOLDOWN"
            or event == "ARENA_COOLDOWNS_UPDATE"
            or event == "PVP_MATCH_STATE_CHANGED"
            or event == "SPELL_UPDATE_USABLE"
            or event == "ITEM_COUNT_CHANGED"
            or event == "BAG_UPDATE_DELAYED"
        local isSpellCooldownEvent = event == "SPELL_UPDATE_COOLDOWN"
            or event == "SPELL_UPDATE_CHARGES"
            or event == "SPELL_UPDATE_USABLE"
        local isCooldownInventoryEvent = event == "UNIT_INVENTORY_CHANGED"
            or event == "PLAYER_EQUIPMENT_CHANGED"
            or event == "BAG_UPDATE"
        local hasItemCooldownIcon, hasSpellCooldownIcon = false, false
        if isItemCooldownEvent or isSpellCooldownEvent or isCooldownInventoryEvent then
            hasItemCooldownIcon, hasSpellCooldownIcon = HasItemCooldownIcon()
        end
        if hasItemCooldownIcon and succeededSpellID then
            MarkItemCombatLockoutFromSpell(succeededSpellID)
        end
        if event == "UNIT_SPELLCAST_SUCCEEDED" and not customTimedChanged and not hasItemCooldownIcon and not isRacialSpellcast then
            return
        end
        if (isItemCooldownEvent or isSpellCooldownEvent or isCooldownInventoryEvent) and not customTimedChanged and not hasItemCooldownIcon and not hasSpellCooldownIcon then
            return
        end

        -- Update all icons when relevant events fire.
        local needsLayoutNotify = nil
        if event == "UNIT_INVENTORY_CHANGED"
            or event == "PLAYER_EQUIPMENT_CHANGED"
        then
            needsLayoutNotify = "force"
        elseif customTimedChanged or event == "UNIT_AURA" then
            needsLayoutNotify = "aura"
        end

        if hasItemCooldownIcon and (isItemCooldownEvent or isCooldownInventoryEvent) then
            if event == "BAG_UPDATE_COOLDOWN" and runtime.QueueEvaluateCustomCooldownWatches then
                runtime.QueueEvaluateCustomCooldownWatches()
            else
                RefreshItemCooldownIcons(needsLayoutNotify)
            end
            if customTimedChanged then
                UpdateAllIcons(needsLayoutNotify, "aura")
            end
            if isRacialSpellcast or (isSpellCooldownEvent and hasSpellCooldownIcon) then
                UpdateAllIcons(nil, "cooldown")
            end
            return
        end

        local updateFilter = nil
        if customTimedChanged or event == "UNIT_AURA" then
            updateFilter = "aura"
        elseif (isSpellCooldownEvent and hasSpellCooldownIcon)
            or isItemCooldownEvent
            or event == "UNIT_INVENTORY_CHANGED"
            or event == "PLAYER_EQUIPMENT_CHANGED"
            or event == "BAG_UPDATE"
        then
            updateFilter = "cooldown"
        end
        UpdateAllIcons(needsLayoutNotify, updateFilter)
    end)
end

local function BuildTimedAuraDebugBucket(key, spellID)
    local source = runtime.timedAuraDebug and runtime.timedAuraDebug[key] or {}
    local data = {}
    for field, value in pairs(source) do
        data[field] = value
    end

    local active = runtime.customTimedAuras and runtime.customTimedAuras[spellID]
    local now = GetTime and GetTime() or 0
    data.active = active and active.expirationTime and active.expirationTime > now or false
    data.expiresIn = data.active and (active.expirationTime - now) or nil
    data.icons, data.frames = CountCustomTimedAuraLinks(spellID)
    data.currentHasIcon = data.icons > 0
    data.currentMatchedFrame = data.frames > 0
    return data
end

function CustomIcons:GetTimedAuraDebugStatus()
    return {
        bloodlust = BuildTimedAuraDebugBucket("bloodlust", 2825),
        timespiral = BuildTimedAuraDebugBucket("timespiral", 374968),
    }
end

function CustomIcons:PrintTimedAuraDebugStatus()
    local status = self:GetTimedAuraDebugStatus()
    local prefix = "|cffffffffDDing|r|cffffa300UI|r timed aura: "

    local function count(data, key)
        return tonumber(data and data[key]) or 0
    end

    local function boolText(value)
        return value and "yes" or "no"
    end

    local function optionalBoolText(value)
        if value == nil then return "-" end
        return value and "yes" or "no"
    end

    local function printBucket(label, data)
        data = data or {}
        local expires = data.expiresIn and string.format("%.1f", data.expiresIn) or "-"
        print(prefix .. string.format("%s active=%s expires=%s icons=%d frames=%d",
            label,
            boolText(data.active),
            expires,
            tonumber(data.icons) or 0,
            tonumber(data.frames) or 0))
        print(prefix .. string.format("%s events unitAura=%d unitMatch=%d seed=%d glowShow=%d glowHide=%d suppressed=%d activated=%d",
            label,
            count(data, "unitAura"),
            count(data, "unitAuraMatch"),
            count(data, "seedMatch"),
            count(data, "glowShow"),
            count(data, "glowHide"),
            count(data, "suppressed"),
            count(data, "activated")))
        print(prefix .. string.format("%s link currentFrame=%s currentIcon=%s lastFrame=%s lastIcon=%s last=%s detail=%s",
            label,
            boolText(data.currentMatchedFrame),
            boolText(data.currentHasIcon),
            optionalBoolText(data.lastMatchedFrame),
            optionalBoolText(data.lastHasMatchingIcon),
            tostring(data.lastEvent or "-"),
            tostring(data.lastDetail or "-")))
    end

    printBucket("Bloodlust", status.bloodlust)
    printBucket("TimeSpiral", status.timespiral)
end

SLASH_DDTIMEDAURA1 = "/ddtimed"
SLASH_DDTIMEDAURA2 = "/ddtimedaura"
SlashCmdList["DDTIMEDAURA"] = function()
    if DDingUI and DDingUI.CustomIcons and DDingUI.CustomIcons.PrintTimedAuraDebugStatus then
        DDingUI.CustomIcons:PrintTimedAuraDebugStatus()
    end
end

-- ------------------------
-- Visual helpers
-- ------------------------
local function GetAnchorFrame(anchorName)
    if not anchorName or anchorName == "" then
        return UIParent
    end
    return _G[anchorName] or UIParent
end

local function IsSpellInPlayerBook(spellID)
    if not spellID then return false end

    -- Use the new Dragonflight API that checks if spell is actually known for current spec
    -- Includes handling of spell overrides/replacements
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.FindBaseSpellByID and C_SpellBook.FindSpellOverrideByID and Enum and Enum.SpellBookSpellBank then
        local bank = Enum.SpellBookSpellBank.Player

        -- Direct check first
        local ok, result = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
        if ok and result then
            return true
        end

        -- Check base spell if this might be an override
        ok, result = pcall(C_SpellBook.FindBaseSpellByID, spellID)
        if ok and result and result ~= spellID then
            ok, result = pcall(C_SpellBook.IsSpellKnown, result, bank)
            if ok and result then
                return true
            end
        end

        -- Check override spell if this might be a base
        ok, result = pcall(C_SpellBook.FindSpellOverrideByID, spellID)
        if ok and result and result ~= spellID then
            ok, result = pcall(C_SpellBook.IsSpellKnown, result, bank)
            if ok and result then
                return true
            end
        end

        return false
    end

    -- Fallback to old API for backward compatibility
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, result = pcall(C_SpellBook.IsSpellInSpellBook, spellID)
        if ok then
            return result == true
        end
    end

    -- Fallback: assume available if API missing/failed
    return true
end

local function IsIconLoadable(iconData)
    if not iconData then return false end
    if iconData.type == "spell" then
        return IsSpellInPlayerBook(iconData.id)
    elseif iconData.type == "racial" then
        local racialID = GetPlayerRacialSpellID()
        return racialID ~= nil
    end
    return true
end

-- (moved above UpdateSpellIconFrame via forward declaration)

local function GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local id = GetSpecializationInfo(specIndex)
        return id
    end
    return nil
end

local function ShouldIconSpawn(iconData)
    if not iconData then return false end
    -- Spellbook gating
    if iconData.type == "spell" and not IsSpellInPlayerBook(iconData.id) then
        return false
    elseif iconData.type == "racial" then
        local racialID = GetPlayerRacialSpellID()
        if not racialID then return false end
    end

    EnsureLoadConditions(iconData)
    local lc = iconData.settings.loadConditions or {}
    if not lc.enabled then
        return true
    end


    -- Spec conditions
    if lc.specs then
        local anySpecSet = false
        for _, v in pairs(lc.specs) do
            if v then anySpecSet = true break end
        end
        if anySpecSet then
            local currentSpec = GetCurrentSpecID()
            if not currentSpec or not lc.specs[currentSpec] then
                return false
            end
        end
    end

    return true
end

local function ResolveAnchorPoints(anchorPoint)
    if anchorPoint == "TOPLEFT" then
        return "BOTTOMLEFT", "TOPLEFT"
    elseif anchorPoint == "TOPRIGHT" then
        return "BOTTOMRIGHT", "TOPRIGHT"
    elseif anchorPoint == "BOTTOMLEFT" then
        return "TOPLEFT", "BOTTOMLEFT"
    elseif anchorPoint == "BOTTOMRIGHT" then
        return "TOPRIGHT", "BOTTOMRIGHT"
    elseif anchorPoint == "TOP" then
        return "BOTTOM", "TOP"
    elseif anchorPoint == "BOTTOM" then
        return "TOP", "BOTTOM"
    elseif anchorPoint == "LEFT" then
        return "RIGHT", "LEFT"
    elseif anchorPoint == "RIGHT" then
        return "LEFT", "RIGHT"
    end
    return "CENTER", "CENTER"
end

-- ------------------------
-- Base icon creation
-- ------------------------
local function CreateBaseIcon(name, parent)
    local frame = CreateFrame("Button", name, parent, "BackdropTemplate")
    frame:SetSize(40, 40)

    -- [FIX] ARTWORK 레이어 사용: BackdropTemplate의 backdrop이 BACKGROUND 레이어를 차지하므로
    -- BACKGROUND에 icon을 만들면 backdrop에 가려져 투명하게 보임
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border frame (texture-based, no SetBackdrop = no taint)
    local border = CreateFrame("Frame", nil, frame)
    border:SetFrameLevel(frame:GetFrameLevel() + 1)
    border:SetAllPoints(frame)
    border:Hide()

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints(frame)
    cd:SetFrameLevel(frame:GetFrameLevel() + 1)
    -- Edge highlight is enabled dynamically (e.g. charge recharge), default off.
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd:SetHideCountdownNumbers(false)
    cd:SetReverse(false)

    -- Probe cooldown: used for cooldown-state checks without being affected by user "Hide Cooldown" setting.
    local cdProbe = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cdProbe:SetAllPoints(frame)
    cdProbe:SetDrawEdge(false)
    cdProbe:SetDrawSwipe(true)
    cdProbe:SetSwipeColor(0, 0, 0, 0)
    cdProbe:SetHideCountdownNumbers(true)
    cdProbe:SetReverse(false)
    cdProbe:SetAlpha(0)

    -- Charge probe: used to detect whether a charge is recharging (show swipe) without affecting main cooldown state.
    local cdChargeProbe = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cdChargeProbe:SetAllPoints(frame)
    cdChargeProbe:SetDrawEdge(false)
    cdChargeProbe:SetDrawSwipe(true)
    cdChargeProbe:SetSwipeColor(0, 0, 0, 0)
    cdChargeProbe:SetHideCountdownNumbers(true)
    cdChargeProbe:SetReverse(false)
    cdChargeProbe:SetAlpha(0)

    cd:SetScript("OnCooldownDone", HandleCooldownDone)
    cdProbe:SetScript("OnCooldownDone", HandleCooldownDone)
    cdChargeProbe:SetScript("OnCooldownDone", HandleCooldownDone)

    local countLayer = CreateFrame("Frame", nil, frame)
    countLayer:SetFrameLevel(frame:GetFrameLevel() + 2)
    countLayer:SetAllPoints(frame)

    -- [FIX] Define template "NumberFontNormal" to prevent "Font not set" on SetText before SetFont is executed.
    local count = countLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetJustifyH("RIGHT")
    count:SetTextColor(1, 1, 1, 1)
    count:SetShadowOffset(0, 0)
    count:SetShadowColor(0, 0, 0, 1)

    frame.icon = icon
    frame.cooldown = cd
    frame.Cooldown = cd
    frame.cooldownProbe = cdProbe
    frame.cooldownChargeProbe = cdChargeProbe
    frame.count = count
    frame.Applications = countLayer
    countLayer.Applications = count
    frame.border = border

    frame:EnableMouse(true)
    return frame
end

local function ResetDynamicIconFrame(frame)
    if not frame then return end

    local bridge = DDingUI.DynamicIconBridge
    if bridge and bridge.ReleaseFrame and (frame._ddIsManaged or frame._ddIconKey) then
        bridge:ReleaseFrame(frame, frame._ddIconKey or frame._iconKey)
    end

    if frame._cdmDesatUpdater then
        frame._cdmDesatUpdater:Hide()
        frame._cdmDesatUpdater.spellID = nil
        frame._cdmDesatUpdater.durObj = nil
        frame._cdmDesatUpdater.targetIcon = nil
    end

    if frame._DDingUIAssistFlipbook then
        frame._DDingUIAssistFlipbook:SetAlpha(0)
        if frame._DDingUIAssistFlipbook.Anim and frame._DDingUIAssistFlipbook.Anim:IsPlaying() then
            frame._DDingUIAssistFlipbook.Anim:Stop()
        end
    end
    if SL then
        if SL.HidePixelGlow then
            SL.HidePixelGlow(frame, "_DDingUIAssistGlow")
            SL.HidePixelGlow(frame, "_DDingUICustomGlow")
        end
        if SL.HideAutocastGlow then
            SL.HideAutocastGlow(frame, "_DDingUIAssistGlow")
            SL.HideAutocastGlow(frame, "_DDingUICustomGlow")
        end
        if SL.HideButtonGlow then
            SL.HideButtonGlow(frame)
        end
    end
    CustomIcons:StopTrackedTrinketEffectGlow(frame)
    if DDingUI.IconCustomization and DDingUI.IconCustomization.ClearDynamicIconGlow then
        DDingUI.IconCustomization:ClearDynamicIconGlow(frame)
    end
    local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then
        LCG.ProcGlow_Stop(frame, "_DDingUIAssistGlow")
        LCG.ProcGlow_Stop(frame, "_DDingUICustomGlow")
    end

    if frame.cooldown then
        frame.cooldown:Clear()
        frame.cooldown:Hide()
        frame.cooldown:SetDrawEdge(false)
        frame.cooldown:SetDrawSwipe(true)
        frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
        frame.cooldown:SetHideCountdownNumbers(false)
        frame.cooldown.noCooldownCount = nil
    end
    if frame.cooldownProbe then
        frame.cooldownProbe:Clear()
        frame.cooldownProbe:Hide()
    end
    if frame.cooldownChargeProbe then
        frame.cooldownChargeProbe:Clear()
        frame.cooldownChargeProbe:Hide()
    end
    if frame.count then
        frame.count:SetText("")
        frame.count:Hide()
    end
    CustomIcons.HideManagedIconBorderLayers(frame)
    if frame.icon then
        frame.icon:ClearAllPoints()
        frame.icon:SetAllPoints(frame)
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        frame.icon:SetTexture(nil)
        frame.icon:SetAlpha(1)
        frame.icon:SetDesaturation(0)
    end

    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)
    frame:SetSize(40, 40)
    frame:SetScale(1)
    frame:SetAlpha(1)
    frame:EnableMouse(true)

    frame._type = nil
    frame._itemID = nil
    frame._spellID = nil
    frame._slotID = nil
    frame._iconKey = nil
    frame._groupSettings = nil
    frame._textureCacheKey = nil
    frame._fallbackTexture = nil
    frame._lastResolvedTexture = nil
    frame._originalTexture = nil
    frame._cachedSpellItemID = nil
    frame._cachedSpellID = nil
    frame._auraWasActive = nil
    frame._wasVisibleInGroup = nil
    frame._ddManagedAuraExpired = nil
    frame._ddIsManaged = nil
    frame._ddIconKey = nil
    frame._ddOrigState = nil
    frame._ddContainerRef = nil
    frame._ddTargetPoint = nil
    frame._ddTargetRelPoint = nil
    frame._ddTargetX = nil
    frame._ddTargetY = nil
    frame._ddTargetWidth = nil
    frame._ddTargetHeight = nil
    frame._ddSuppressed = nil
    frame._ddSourceViewer = nil
    frame._DDingUIAssistViewerName = nil
    frame._DDingUIAssistGlowActive = nil
    frame._ddCustomIconActive = nil
    frame._ddCustomIconReady = nil
end

local function AcquireDynamicIconFrame(name, parent)
    local frame = table.remove(runtime.iconFramePool)
    if frame then
        frame._ddInIconPool = nil
        frame:SetParent(parent)
        frame:SetSize(40, 40)
        frame:SetScale(1)
        frame:SetAlpha(1)
        frame:EnableMouse(true)
        return frame
    end
    return CreateBaseIcon(name, parent)
end

local function ReleaseDynamicIconFrame(iconKey, frame)
    if not frame or frame._ddInIconPool then return end
    ResetDynamicIconFrame(frame)
    frame._ddInIconPool = true
    runtime.iconFramePool[#runtime.iconFramePool + 1] = frame
end

-- ------------------------
-- Icon creation per type
-- ------------------------
local function CreateItemIcon(iconKey, iconData, parent)
    local itemID = iconData.id
    if not itemID then return nil end

    -- [FIX] CDM 방식: 프레임은 항상 생성, 텍스처만 나중에 업데이트
    -- GetItemInfo가 nil이어도 프레임은 만들어야 GroupSystem이 추적 가능
    local itemName = GetItemInfo(itemID)
    if not itemName and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end

    local frame = AcquireDynamicIconFrame("DDingUI_DynItem_" .. iconKey, parent)
    frame._type = "item"
    frame._itemID = itemID
    frame._iconKey = iconKey
    frame._textureCacheKey = "item:" .. tostring(itemID)
    frame._fallbackTexture = FALLBACK_ITEM_ICON
    SetStableIconTexture(frame, ResolveItemTexture(itemID), true)
    return frame
end

local function CreateSpellIcon(iconKey, iconData, parent)
    local spellID = iconData.id
    if not spellID then return nil end
    -- [FIX] 스펠북 체크는 IsIconActive에서 하므로 여기서는 프레임만 생성
    -- 유저가 추가한 스펠이 현재 특성에 없더라도 프레임은 존재해야 함

    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if not spellInfo then
        if C_Spell and C_Spell.RequestLoadSpellData then
            C_Spell.RequestLoadSpellData(spellID)
        end
    end

    local frame = AcquireDynamicIconFrame("DDingUI_DynSpell_" .. iconKey, parent)
    frame._type = "spell"
    frame._spellID = spellID
    frame._iconKey = iconKey
    frame._textureCacheKey = "spell:" .. tostring(spellID)
    frame._fallbackTexture = GetStoredIconTexture(iconData) or FALLBACK_SPELL_ICON
    SetStableIconTexture(frame, ResolveSpellTexture(spellID, frame._fallbackTexture), true)
    return frame
end

local function CreateSlotIcon(iconKey, iconData, parent)
    local slotID = iconData.slotID
    if not slotID then return nil end

    local prefix = (iconData.type == "trinketProc") and "DDingUI_DynTrinket_" or "DDingUI_DynSlot_"
    local frame = AcquireDynamicIconFrame(prefix .. iconKey, parent)
    frame._type = iconData.type or "slot"
    frame._slotID = slotID
    frame._iconKey = iconKey
    frame._textureCacheKey = (iconData.type or "slot") .. ":" .. tostring(slotID)
    frame._fallbackTexture = FALLBACK_SLOT_ICON

    -- [FIX] 텍스처 항상 설정 — GetItemInfo 캐시 미스 시에도 아이콘 보이도록
    local itemID = CustomIcons.GetEquippedSlotItemID(frame, slotID)
    local tex = nil
    if itemID then
        -- GetItemInfo보다 GetInventoryItemTexture가 더 신뢰할 수 있음 (캐시 불필요)
        tex = GetInventoryItemTexture("player", slotID)
        if not tex then
            local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            tex = itemTexture
        end
        if not tex and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    SetStableIconTexture(frame, tex or ResolveItemTexture(itemID, slotID), true)
    return frame
end

local function CreateAuraIcon(iconKey, iconData, parent)
    local spellID = iconData.id
    if not spellID then return nil end

    local frame = AcquireDynamicIconFrame("DDingUI_DynAura_" .. iconKey, parent)
    frame._type = "aura"
    frame._spellID = spellID
    frame._iconKey = iconKey
    frame._textureCacheKey = "aura:" .. tostring(spellID)
    frame._fallbackTexture = GetStoredIconTexture(iconData) or FALLBACK_SPELL_ICON

    -- 텍스처: C_Spell.GetSpellTexture → GetSpellInfo.iconID 폴백
    SetStableIconTexture(frame, ResolveSpellTexture(spellID, frame._fallbackTexture), true)
    return frame
end

local function CreateDynamicIcon(iconKey, iconData, parent)
    if iconData.type == "item" then
        return CreateItemIcon(iconKey, iconData, parent)
    elseif iconData.type == "spell" then
        local frame = CreateSpellIcon(iconKey, iconData, parent)
        if frame and CustomIcons:IsCurrentRacialSpellIcon(iconData) then
            frame._type = "racial"
            frame._racialSpellID = GetPlayerRacialSpellID()
            UpdateRacialIconFrame(frame, iconData)
        end
        return frame
    elseif iconData.type == "slot" then
        return CreateSlotIcon(iconKey, iconData, parent)
    elseif iconData.type == "trinketProc" then
        return CreateSlotIcon(iconKey, iconData, parent)  -- Reuse slot icon frame
    elseif iconData.type == "aura" then
        return CreateAuraIcon(iconKey, iconData, parent)
    elseif iconData.type == "racial" then
        local racialID = GetPlayerRacialSpellID()
        if not racialID then return nil end
        -- 임시 테이블로 CreateSpellIcon을 호출하여 데이터 오염 방지
        local frame = CreateSpellIcon(iconKey, {id = racialID, settings = iconData.settings}, parent)
        if frame then
            frame._type = "racial"
            frame._racialSpellID = racialID
            frame._fallbackTexture = FALLBACK_RACIAL_ICON
            UpdateRacialIconFrame(frame, iconData)
        end
        return frame
    end
    return nil
end

local function UpdateDynamicIcon(iconKey)
    local db = GetDynamicDB()
    local iconData = db.iconData[iconKey]
    local frame = runtime.iconFrames[iconKey]
    if not iconData or not frame then return end

    -- Group settings are stored on the frame during LayoutGroup
    ApplyIconSettings(frame, iconData, frame._groupSettings)
    if iconData.type == "item" then
        UpdateItemIcon(frame, iconData)
    elseif iconData.type == "spell" then
        if CustomIcons:IsCurrentRacialSpellIcon(iconData) then
            UpdateRacialIconFrame(frame, iconData)
        else
            UpdateSpellIconFrame(frame, iconData)
        end
    elseif iconData.type == "racial" then
        UpdateRacialIconFrame(frame, iconData)
    elseif iconData.type == "slot" then
        UpdateSlotIcon(frame, iconData)
    elseif iconData.type == "trinketProc" then
        UpdateTrinketProcIcon(frame, iconData)
    elseif iconData.type == "aura" then
        UpdateAuraIcon(frame, iconData)
    end
    CustomIcons:UpdateDynamicIconStateGlow(frame, iconData)
    if frame._ddIsManaged then
        CustomIcons.ApplyManagedGroupTextOptions(frame)
    end
end

runtime.UpdateDynamicIcon = UpdateDynamicIcon

function CustomIcons:RefreshDynamicIcon(iconKey)
    if iconKey and runtime.UpdateDynamicIcon then
        runtime.UpdateDynamicIcon(iconKey)
    end
end

function runtime.ClearCustomCooldownTable(tbl)
    if not tbl then return end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function runtime.NormalizeCustomCooldownState(startTime, duration, enable)
    return startTime or 0, duration or 0, enable or 0
end

function runtime.PopulateCustomCooldownState(state, startTime, duration, enable)
    if not state then return end
    startTime, duration, enable = runtime.NormalizeCustomCooldownState(startTime, duration, enable)
    state.startTime = startTime
    state.duration = duration
    state.enable = enable
    local isActive = false
    pcall(function()
        isActive = enable == 1 and startTime > 0 and duration > 0
    end)
    state.isActive = isActive
    local readyTime = nil
    if isActive then
        pcall(function()
            readyTime = startTime + duration
        end)
    end
    state.readyTime = readyTime
end

function runtime.UpdateCustomCooldownStateIfChanged(state, startTime, duration, enable)
    if not state then return false end
    startTime, duration, enable = runtime.NormalizeCustomCooldownState(startTime, duration, enable)
    local same = false
    pcall(function()
        same = state.startTime == startTime and state.duration == duration and state.enable == enable
    end)
    if same then return false end
    runtime.PopulateCustomCooldownState(state, startTime, duration, enable)
    return true
end

function runtime.ReadCustomItemCooldown(itemID)
    local startTime, duration, enable
    if C_Container and C_Container.GetItemCooldown then
        pcall(function()
            startTime, duration, enable = C_Container.GetItemCooldown(itemID)
        end)
    end
    return startTime, duration, enable
end

function runtime.ReadCustomSlotCooldown(slotID)
    local startTime, duration, enable
    if GetInventoryItemCooldown then
        pcall(function()
            startTime, duration, enable = GetInventoryItemCooldown("player", slotID)
        end)
    end
    return startTime, duration, enable
end

function runtime.EvaluateCustomCooldownWatches()
    local watcher = runtime.cooldownWatcher
    if not watcher or (watcher.activeTargetCount or 0) <= 0 then return end
    local changed = {}

    for itemID, iconKeys in pairs(watcher.itemTargets) do
        local state = watcher.itemStates[itemID]
        if not state then
            state = {}
            watcher.itemStates[itemID] = state
        end
        if runtime.UpdateCustomCooldownStateIfChanged(state, runtime.ReadCustomItemCooldown(itemID)) then
            for iconKey in pairs(iconKeys) do
                changed[iconKey] = true
            end
        end
    end

    for slotID, iconKeys in pairs(watcher.slotTargets) do
        local state = watcher.slotStates[slotID]
        if not state then
            state = {}
            watcher.slotStates[slotID] = state
        end
        if runtime.UpdateCustomCooldownStateIfChanged(state, runtime.ReadCustomSlotCooldown(slotID)) then
            for iconKey in pairs(iconKeys) do
                changed[iconKey] = true
            end
        end
    end

    if next(changed) then
        runtime.QueueCustomCooldownIconRefresh(nil, changed)
    end
end

function runtime.FlushCustomCooldownIconRefresh()
    local watcher = runtime.cooldownWatcher
    if not watcher then return end
    local keys = watcher.pendingIconKeys
    local refreshAll = watcher.refreshAll
    local notify = watcher.layoutNotify

    watcher.refreshPending = false
    watcher.refreshAll = false
    watcher.layoutNotify = nil

    if refreshAll then
        runtime.ClearCustomCooldownTable(keys)
        for _, targetMap in ipairs({ watcher.itemTargets, watcher.slotTargets }) do
            for _, iconKeys in pairs(targetMap) do
                for iconKey in pairs(iconKeys) do
                    keys[iconKey] = true
                end
            end
        end
    end

    for iconKey in pairs(keys) do
        if runtime.UpdateDynamicIcon then
            pcall(runtime.UpdateDynamicIcon, iconKey)
        end
        keys[iconKey] = nil
    end

    if notify and DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        DDingUI.DynamicIconBridge:NotifyIconsChanged(notify == true or notify == "force")
    end
end

function runtime.EnsureCustomCooldownWatcher()
    local watcher = runtime.cooldownWatcher
    if not watcher then return nil end
    return watcher
end

function runtime.QueueEvaluateCustomCooldownWatches()
    local watcher = runtime.EnsureCustomCooldownWatcher()
    if not watcher or (watcher.activeTargetCount or 0) <= 0 or watcher.evaluatePending then return end
    watcher.evaluatePending = true
    ScheduleCustomIconWork()
end

function runtime.QueueCustomCooldownIconRefresh(needsLayoutNotify, iconKeys)
    local watcher = runtime.EnsureCustomCooldownWatcher()
    if not watcher then
        UpdateAllIcons(needsLayoutNotify, "item")
        return
    end
    if iconKeys then
        for iconKey in pairs(iconKeys) do
            watcher.pendingIconKeys[iconKey] = true
        end
    else
        watcher.refreshAll = true
    end
    if needsLayoutNotify == true or needsLayoutNotify == "force" then
        watcher.layoutNotify = "force"
    elseif needsLayoutNotify and watcher.layoutNotify ~= "force" then
        watcher.layoutNotify = needsLayoutNotify
    end
    watcher.refreshPending = true
    ScheduleCustomIconWork()
end

function runtime.AddCustomCooldownTarget(targets, id, iconKey)
    local safeID = SafeNumber(id)
    if not safeID or not iconKey then return end
    targets[safeID] = targets[safeID] or {}
    targets[safeID][iconKey] = true
end

function runtime.AddCustomFallbackItemTargets(settings, iconKey)
    if type(settings) ~= "table" or type(settings.fallbackItems) ~= "string" then return end
    for itemText in string.gmatch(settings.fallbackItems, "(%d+)") do
        runtime.AddCustomCooldownTarget(runtime.cooldownWatcher.itemTargets, itemText, iconKey)
    end
end

function runtime.PrimeCustomCooldownWatcherStates()
    local watcher = runtime.cooldownWatcher
    runtime.ClearCustomCooldownTable(watcher.itemStates)
    runtime.ClearCustomCooldownTable(watcher.slotStates)
    for itemID in pairs(watcher.itemTargets) do
        watcher.itemStates[itemID] = {}
        runtime.PopulateCustomCooldownState(watcher.itemStates[itemID], runtime.ReadCustomItemCooldown(itemID))
    end
    for slotID in pairs(watcher.slotTargets) do
        watcher.slotStates[slotID] = {}
        runtime.PopulateCustomCooldownState(watcher.slotStates[slotID], runtime.ReadCustomSlotCooldown(slotID))
    end
end

function runtime.RegisterCustomCooldownWatches()
    local watcher = runtime.EnsureCustomCooldownWatcher()
    if not watcher then return end
    local db = GetDynamicDB()
    runtime.ClearCustomCooldownTable(watcher.itemTargets)
    runtime.ClearCustomCooldownTable(watcher.slotTargets)
    watcher.activeTargetCount = 0
    watcher.hasSpellTarget = false

    for iconKey, frame in pairs(runtime.iconFrames) do
        local iconData = frame and db.iconData and db.iconData[iconKey]
        if iconData then
            if iconData.type == "item" then
                runtime.AddCustomCooldownTarget(watcher.itemTargets, iconData.id, iconKey)
                runtime.AddCustomFallbackItemTargets(iconData.settings, iconKey)
            elseif iconData.type == "slot" then
                runtime.AddCustomCooldownTarget(watcher.slotTargets, iconData.slotID, iconKey)
            elseif iconData.type == "trinketProc" and (not iconData.settings or iconData.settings.showItemCooldown ~= false) then
                runtime.AddCustomCooldownTarget(watcher.slotTargets, iconData.slotID, iconKey)
            elseif iconData.type == "spell" or iconData.type == "racial" then
                watcher.hasSpellTarget = true
            end
        end
    end

    for _ in pairs(watcher.itemTargets) do
        watcher.activeTargetCount = watcher.activeTargetCount + 1
    end
    for _ in pairs(watcher.slotTargets) do
        watcher.activeTargetCount = watcher.activeTargetCount + 1
    end

    runtime.PrimeCustomCooldownWatcherStates()
    watcher.kindsInitialized = true
end

function runtime.RequestCustomCooldownWatchRegistration()
    local watcher = runtime.cooldownWatcher
    if InCombatLockdown and InCombatLockdown() then
        watcher.registrationPending = true
        return
    end
    watcher.registrationPending = false
    runtime.RegisterCustomCooldownWatches()
end

-- ------------------------
-- Group layout
-- ------------------------
local function GetStartAnchorForGrowth(growth)
    if growth == "LEFT" then
        return "TOPRIGHT"
    elseif growth == "UP" then
        return "BOTTOMLEFT"
    end
    return "TOPLEFT"
end

local function GetDefaultRowGrowth(growth)
    if growth == "LEFT" or growth == "RIGHT" then
        return "DOWN"
    end
    return "RIGHT"
end

local function NormalizeRowGrowth(growth, rowGrowth)
    if growth == "LEFT" or growth == "RIGHT" then
        if rowGrowth ~= "UP" and rowGrowth ~= "DOWN" then
            return "DOWN"
        end
        return rowGrowth
    end
    if rowGrowth ~= "LEFT" and rowGrowth ~= "RIGHT" then
        return "RIGHT"
    end
    return rowGrowth
end

local function GetStartAnchorForGrowthPair(growth, rowGrowth)
    local g = growth or "RIGHT"
    local rg = NormalizeRowGrowth(g, rowGrowth or GetDefaultRowGrowth(g))

    local top = (g == "LEFT" or g == "RIGHT" or rg == "DOWN")
    local left = (g == "RIGHT" or rg == "RIGHT")

    if top and left then return "TOPLEFT" end
    if top and not left then return "TOPRIGHT" end
    if not top and left then return "BOTTOMLEFT" end
    return "BOTTOMRIGHT"
end

local function BuildDefaultSettings(growth)
    local g = growth or "RIGHT"
    local rg = NormalizeRowGrowth(g, GetDefaultRowGrowth(g))
    local startAnchor = GetStartAnchorForGrowthPair(g, rg)
    return {
        growthDirection = g,
        rowGrowthDirection = rg,
        anchorFrom = startAnchor,
        anchorTo = startAnchor,
        spacing = 5,
        iconSize = 40,
        maxIconsPerRow = 10,
        position = {x = 0, y = -200},
    }
end

local function BuildDefaultUngroupedPositionSettings()
    local settings = BuildDefaultSettings("RIGHT")
    settings.anchorFrom = "CENTER"
    settings.anchorTo = "CENTER"
    settings.position = { x = 0, y = 0 }
    return settings
end

local function NormalizeAnchor(settings)
    if not settings then return end
    if settings.anchorPoint and not settings.anchorFrom and not settings.anchorTo then
        settings.anchorFrom = settings.anchorPoint
        settings.anchorTo = settings.anchorPoint
        settings.anchorPoint = nil
    end
    if settings.anchorPoint then
        settings.anchorPoint = nil
    end
    settings.rowGrowthDirection = settings.rowGrowthDirection or GetDefaultRowGrowth(settings.growthDirection or "RIGHT")
    settings.rowGrowthDirection = NormalizeRowGrowth(settings.growthDirection or "RIGHT", settings.rowGrowthDirection)
    if settings.maxIconsPerRow == nil and settings.maxColumns ~= nil then
        settings.maxIconsPerRow = settings.maxColumns
        settings.maxColumns = nil
    end
    settings.anchorFrom = settings.anchorFrom or GetStartAnchorForGrowthPair(settings.growthDirection or "RIGHT", settings.rowGrowthDirection)
    settings.anchorTo = settings.anchorTo or settings.anchorFrom
end

local function GetGroupSettings(groupKey)
    local db = GetDynamicDB()
    if groupKey == "ungrouped" then
        db.ungroupedSettings = db.ungroupedSettings or BuildDefaultSettings("RIGHT")
        NormalizeAnchor(db.ungroupedSettings)
        return db.ungroupedSettings
    end
    if db.iconData[groupKey] and db.ungrouped[groupKey] then
        db.ungroupedPositions = db.ungroupedPositions or {}
        db.ungroupedPositions[groupKey] = db.ungroupedPositions[groupKey] or BuildDefaultUngroupedPositionSettings()
        NormalizeAnchor(db.ungroupedPositions[groupKey])
        return db.ungroupedPositions[groupKey]
    end
    if db.groups[groupKey] then
        db.groups[groupKey].settings = db.groups[groupKey].settings or BuildDefaultSettings(db.groups[groupKey].growthDirection or "RIGHT")
        NormalizeAnchor(db.groups[groupKey].settings)
        return db.groups[groupKey].settings
    end
    local defaults = BuildDefaultSettings("RIGHT")
    NormalizeAnchor(defaults)
    return defaults
end

local function GetGroupDisplayName(groupKey)
    if groupKey == "ungrouped" then
        return L["Ungrouped"] or "Ungrouped"
    end
    local db = GetDynamicDB()
    if db.iconData[groupKey] and db.ungrouped[groupKey] then
        local iconData = db.iconData[groupKey]
        if iconData then
            if iconData.type == "item" then
                return GetItemInfo(iconData.id) or ((L["Item"] or "Item") .. " " .. iconData.id)
            elseif iconData.type == "spell" then
                local info = C_Spell.GetSpellInfo(iconData.id)
                return (info and info.name) or ((L["Spell"] or "Spell") .. " " .. iconData.id)
            elseif iconData.type == "slot" then
                return ((L["Slot"] or "Slot") .. " " .. (iconData.slotID or ""))
            elseif iconData.type == "trinketProc" then
                local iid = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID or 13)
                local itemName = iid and GetItemInfo(iid)
                return itemName or ("Trinket " .. (iconData.slotID == 14 and "2" or "1"))
            end
        end
    end
    local group = db.groups[groupKey]
    if group and group.name and group.name ~= "" then
        return group.name
    end
    return groupKey
end

local function EnsureGroupFrame(groupKey, settings)
    settings = settings or GetGroupSettings(groupKey)
    NormalizeAnchor(settings)
    if runtime.groupFrames[groupKey] then
        return runtime.groupFrames[groupKey]
    end

    -- Create the main container frame
    local container = CreateFrame("Frame", "DDingUI_DynGroup_" .. groupKey, UIParent)
    container:SetSize(100, 100) -- Initial size, will be recalculated
    container:SetMovable(true) -- Container itself must be movable
    container:SetClampedToScreen(true)

    -- Note: Legacy anchor system removed - Movers system (/dduimove) handles positioning

    container._settings = settings
    container._groupKey = groupKey

    -- Position the container
    if settings.position then
        local anchorFrame = GetAnchorFrame(settings.anchorFrame)
        local containerPoint = settings.anchorFrom or GetStartAnchorForGrowth(settings.growthDirection or "RIGHT")
        local anchorPoint = settings.anchorTo or containerPoint
        container:ClearAllPoints()
        container:SetPoint(containerPoint, anchorFrame, anchorPoint, settings.position.x or 0, settings.position.y or 0)
    else
        local containerPoint = GetStartAnchorForGrowth(settings.growthDirection or "RIGHT")
        container:SetPoint(containerPoint, UIParent, containerPoint, 0, -200)
    end

    runtime.groupFrames[groupKey] = container
    return container
end

local function LayoutGroup(groupKey, iconKeys)
    -- [DYNAMIC] GroupSystem이 활성이면 레이아웃 스킵 (GroupRenderer가 대신 처리)
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        return
    end
    local db = GetDynamicDB()
    local groupSettings = GetGroupSettings(groupKey)
    local growth = groupSettings.growthDirection or "RIGHT"
    local settings = groupSettings
    growth = settings.growthDirection or growth
    settings.rowGrowthDirection = settings.rowGrowthDirection or GetDefaultRowGrowth(growth)
    settings.rowGrowthDirection = NormalizeRowGrowth(growth, settings.rowGrowthDirection)

    if not iconKeys or #iconKeys == 0 then
        local container = runtime.groupFrames[groupKey]
        if container then
            container:Hide()
        end
        return
    end

    local container = EnsureGroupFrame(groupKey, settings)
    container:Show()

    local spacing = settings.spacing or 5
    local maxPerRow = settings.maxIconsPerRow
    if maxPerRow == nil and settings.maxColumns ~= nil then
        maxPerRow = settings.maxColumns
        settings.maxIconsPerRow = maxPerRow
        settings.maxColumns = nil
    end
    maxPerRow = maxPerRow or 10

    local iconSizes = {}

    for _, iconKey in ipairs(iconKeys) do
        local iconFrame = runtime.iconFrames[iconKey]
        if iconFrame then
            local iconData = db.iconData[iconKey]
            local borderSize = 0
            -- Store group settings on the frame for later use (UpdateDynamicIcon, UpdateAllIcons)
            iconFrame._groupSettings = groupSettings
            if iconData then
                ApplyIconSettings(iconFrame, iconData, groupSettings)
                borderSize = math.max((iconData.settings and iconData.settings.borderSize) or 0, 0)
            end
            local w, h = iconFrame:GetWidth(), iconFrame:GetHeight()
            table.insert(iconSizes, {width = w + borderSize * 2, height = h + borderSize * 2, border = borderSize})
        end
    end

    local startAnchor = GetStartAnchorForGrowthPair(growth, settings.rowGrowthDirection)

    local function borderInsetForAnchor(anchor, border)
        if not border or border <= 0 then return 0, 0 end
        local dx = (anchor:find("LEFT") and border) or -border
        local dy = (anchor:find("TOP") and -border) or border
        return dx, dy
    end

    -- Layout in offsets relative to container startAnchor (x right+, y up+)
    local positions = {}
    local minLeft, maxRight = 0, 0
    local minBottom, maxTop = 0, 0

    local rowBaseX, rowBaseY = 0, 0
    local along = 0
    local rowThickness = 0
    local countInRow = 0
    local iconGrowthIsHorizontal = (growth == "LEFT" or growth == "RIGHT")

    local function advanceRow()
        local step = rowThickness + spacing
        local rg = settings.rowGrowthDirection
        if rg == "RIGHT" then
            rowBaseX = rowBaseX + step
        elseif rg == "LEFT" then
            rowBaseX = rowBaseX - step
        elseif rg == "UP" then
            rowBaseY = rowBaseY + step
        else -- DOWN
            rowBaseY = rowBaseY - step
        end
        along = 0
        rowThickness = 0
        countInRow = 0
    end

    local function accumulateBounds(anchor, xOff, yOff, w, h)
        local left, right, top, bottom
        if anchor == "TOPLEFT" then
            left, right = xOff, xOff + w
            top, bottom = yOff, yOff - h
        elseif anchor == "TOPRIGHT" then
            right, left = xOff, xOff - w
            top, bottom = yOff, yOff - h
        elseif anchor == "BOTTOMLEFT" then
            left, right = xOff, xOff + w
            bottom, top = yOff, yOff + h
        else -- BOTTOMRIGHT
            right, left = xOff, xOff - w
            bottom, top = yOff, yOff + h
        end
        minLeft = math.min(minLeft, left)
        maxRight = math.max(maxRight, right)
        minBottom = math.min(minBottom, bottom)
        maxTop = math.max(maxTop, top)
    end

    for i, iconSize in ipairs(iconSizes) do
        local w, h = iconSize.width, iconSize.height
        local xOff, yOff = rowBaseX, rowBaseY

        if growth == "RIGHT" then
            xOff = rowBaseX + along
        elseif growth == "LEFT" then
            xOff = rowBaseX - along
        elseif growth == "UP" then
            yOff = rowBaseY + along
        else -- DOWN
            yOff = rowBaseY - along
        end

        positions[i] = {x = xOff, y = yOff, width = w, height = h, border = iconSize.border or 0}
        accumulateBounds(startAnchor, xOff, yOff, w, h)

        countInRow = countInRow + 1
        if iconGrowthIsHorizontal then
            along = along + w + spacing
            rowThickness = math.max(rowThickness, h)
        else
            along = along + h + spacing
            rowThickness = math.max(rowThickness, w)
        end

        if countInRow >= maxPerRow then
            advanceRow()
        end
    end

    local contentWidth = maxRight - minLeft
    local contentHeight = maxTop - minBottom
    if contentWidth <= 0 then
        contentWidth = container._lastLayoutW or 1
    end
    if contentHeight <= 0 then
        contentHeight = container._lastLayoutH or 1
    end

    for i, iconKey in ipairs(iconKeys) do
        local iconFrame = runtime.iconFrames[iconKey]
        local pos = positions[i]
        if iconFrame and pos then
            local dx, dy = borderInsetForAnchor(startAnchor, pos.border or 0)
            iconFrame:ClearAllPoints()
            iconFrame:SetParent(container)
            iconFrame:SetPoint(startAnchor, container, startAnchor, (pos.x or 0) + dx, (pos.y or 0) + dy)
            iconFrame:Show()
        end
    end

    container:SetSize(contentWidth, contentHeight)
    container._lastLayoutW = contentWidth
    container._lastLayoutH = contentHeight

    -- Re-apply anchor using stored anchor points
    if settings.position then
        local containerPoint = settings.anchorFrom or startAnchor
        local anchorFrame = GetAnchorFrame(settings.anchorFrame)
        local anchorPoint = settings.anchorTo or containerPoint
        container:ClearAllPoints()
        container:SetPoint(containerPoint, anchorFrame, anchorPoint, settings.position.x or 0, settings.position.y or 0)
    end
end

function runtime.RunBridgeLayoutRefresh()
    runtime.refreshAllLayoutsPending = nil
    runtime.layoutRefreshDueAt = nil
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
    end
end

local function QueueBridgeLayoutRefresh(delay)
    if runtime.refreshAllLayoutsPending then return end
    runtime.refreshAllLayoutsPending = true
    runtime.layoutRefreshDueAt = (GetTime and GetTime() or 0) + (delay or 0)
    ScheduleCustomIconWork()
end

local function RefreshAllLayouts()
    if runtime.RequestCustomCooldownWatchRegistration then
        runtime.RequestCustomCooldownWatchRegistration()
    end
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        QueueBridgeLayoutRefresh((InCombatLockdown and InCombatLockdown()) and 0.12 or 0.04)
        return
    end

    -- SpecProfiles 자동 저장 트리거 (동적 아이콘 설정 변경 감지)
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
    local db = GetDynamicDB()

    -- Build ungrouped list (one anchor per ungrouped icon)
    local ungroupedKeys = {}
    for iconKey, _ in pairs(db.ungrouped) do
        table.insert(ungroupedKeys, iconKey)
    end
    table.sort(ungroupedKeys)
    for _, iconKey in ipairs(ungroupedKeys) do
        db.ungroupedPositions = db.ungroupedPositions or {}
        db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
        if ShouldIconSpawn(db.iconData[iconKey]) then
            LayoutGroup(iconKey, {iconKey})
        else
            local cont = runtime.groupFrames[iconKey]
            if cont then cont:Hide() end
            local frame = runtime.iconFrames[iconKey]
            if frame then frame:Hide() end
        end
    end

    -- Groups
    for groupKey, group in pairs(db.groups) do
        -- Check if group is enabled (default true for backwards compatibility)
        if group.enabled == false then
            -- Hide all icons in disabled group
            for _, k in ipairs(group.icons or {}) do
                local frame = runtime.iconFrames[k]
                if frame then frame:Hide() end
            end
            local container = runtime.groupFrames[groupKey]
            if container then container:Hide() end
        else
            local keys = {}
            local seen = {}
            for _, k in ipairs(group.icons or {}) do
                if db.iconData[k] and not seen[k] and ShouldIconSpawn(db.iconData[k]) then
                    table.insert(keys, k)
                    seen[k] = true
                else
                    local frame = runtime.iconFrames[k]
                    if frame then frame:Hide() end
                end
            end
            LayoutGroup(groupKey, keys)
        end
    end
end

local function FindIconGroup(iconKey, db)
    if db.ungrouped[iconKey] then return "ungrouped" end
    for gk, group in pairs(db.groups) do
        for _, k in ipairs(group.icons or {}) do
            if k == iconKey then
                return gk
            end
        end
    end
    return "ungrouped"
end

function CustomIcons:EnsureDynamicIconFrame(iconKey, iconData)
    if not iconKey then return nil end

    local frame = runtime.iconFrames[iconKey]
    if frame then return frame end

    local db = GetDynamicDB()
    iconData = iconData or (db.iconData and db.iconData[iconKey])
    if not iconData then return nil end

    EnsureLoadConditions(iconData)
    if not IsIconLoadable(iconData) then return nil end

    local groupKey = FindIconGroup(iconKey, db)
    local settings
    if groupKey == "ungrouped" or db.ungrouped[iconKey] then
        db.ungroupedPositions = db.ungroupedPositions or {}
        db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
        settings = db.ungroupedPositions[iconKey]
        groupKey = iconKey
    else
        settings = GetGroupSettings(groupKey)
    end

    frame = CreateDynamicIcon(iconKey, iconData, EnsureGroupFrame(groupKey, settings))
    if frame then
        runtime.iconFrames[iconKey] = frame
        if runtime.RequestCustomCooldownWatchRegistration then
            runtime.RequestCustomCooldownWatchRegistration()
        end
    end
    return frame
end

function CustomIcons:LoadDynamicIcons()
    EnsureEventFrame()
    local db = GetDynamicDB()

    -- 프로필 변경 시 기존 프레임 정리: db에 없는 아이콘 제거
    for iconKey, frame in pairs(runtime.iconFrames) do
        if not db.iconData[iconKey] then
            ReleaseDynamicIconFrame(iconKey, frame)
            runtime.iconFrames[iconKey] = nil
        end
    end
    -- 기존 그룹 프레임도 정리
    for groupKey, container in pairs(runtime.groupFrames) do
        if not db.groups[groupKey] and not db.ungrouped[groupKey] and not db.iconData[groupKey] then
            container:Hide()
            container:SetParent(nil)
            runtime.groupFrames[groupKey] = nil
        end
    end

    -- [FIX] 프레임 생성 실패한 아이콘 수집 (아이템 캐시 미준비 등)
    local pendingKeys = {}
    local timeSinceLogin = GetTime() - (runtime.loginTime or GetTime())
    for iconKey, iconData in pairs(db.iconData) do
        EnsureLoadConditions(iconData)
        local isLoadable = IsIconLoadable(iconData)

        -- [FIX] 로그인 직후(10초 이내) 스펠북이 준비 안 되어 false를 반환하는 경우 실패로 간주하지 않고 재시도 대기열에 추가
        if not isLoadable and timeSinceLogin < 10 then
            pendingKeys[#pendingKeys + 1] = iconKey
            if iconData.type == "spell" and iconData.id and C_Spell and C_Spell.RequestLoadSpellData then
                pcall(C_Spell.RequestLoadSpellData, iconData.id)
            end
        elseif isLoadable then
            local groupKey = FindIconGroup(iconKey, db)
            local settings
            if groupKey == "ungrouped" or db.ungrouped[iconKey] then
                db.ungroupedPositions = db.ungroupedPositions or {}
                db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
                settings = db.ungroupedPositions[iconKey]
                groupKey = iconKey
            else
                settings = GetGroupSettings(groupKey)
            end
            local parent = EnsureGroupFrame(groupKey, settings)
            local frame = runtime.iconFrames[iconKey]
            if not frame then
                frame = CreateDynamicIcon(iconKey, iconData, parent)
                if frame then
                    runtime.iconFrames[iconKey] = frame
                else
                    -- 프레임 생성 실패 → 재시도 목록에 추가
                    pendingKeys[#pendingKeys + 1] = iconKey
                    -- 아이템 데이터 프리로드 요청
                    if iconData.type == "item" and iconData.id and C_Item and C_Item.RequestLoadItemDataByID then
                        C_Item.RequestLoadItemDataByID(iconData.id)
                    elseif iconData.type == "trinketProc" and iconData.slotID then
                        local itemID = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID)
                        if itemID and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                    elseif iconData.type == "slot" and iconData.slotID then
                        local itemID = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID)
                        if itemID and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                    elseif iconData.type == "spell" and iconData.id then
                        if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, iconData.id) end
                    end
                end
            end
            if frame then
                frame._ddDeferredLoadRelease = nil
            end
        else
            -- Hide/clear frames for spells not in the spellbook
            local frame = runtime.iconFrames[iconKey]
            if frame then
                if InCombatLockdown and InCombatLockdown() then
                    frame._ddDeferredLoadRelease = true
                    if iconData.type == "spell" and iconData.id and C_Spell and C_Spell.RequestLoadSpellData then
                        pcall(C_Spell.RequestLoadSpellData, iconData.id)
                    end
                else
                    ReleaseDynamicIconFrame(iconKey, frame)
                    runtime.iconFrames[iconKey] = nil
                end
            end
        end
    end

    -- [FIX] GroupSystem이 활성이면 CustomIcons 자체 프레임을 즉시 숨김
    -- CreateDynamicIcon이 Show()를 호출하여 리로드 시 회색 프레임이 잠깐 보이는 것 방지
    -- GroupSystem이 자체 레이아웃으로 관리하므로 CustomIcons 프레임은 보일 필요 없음
    local bridge = DDingUI.DynamicIconBridge
    if bridge and bridge:IsActive() then
        for _, frame in pairs(runtime.iconFrames) do
            if frame and frame.Hide and not frame._ddIsManaged then
                frame:Hide()
            end
        end
        for _, container in pairs(runtime.groupFrames) do
            if container and container.Hide then
                container:Hide()
            end
        end
    end

    RefreshAllLayouts()
    -- Initial update to ensure icons show correct state
    UpdateAllIcons(nil, "all")

    -- [FIX] 프레임 생성 실패한 아이콘 재시도 (아이템/스펠 캐시 로드 대기)
    if #pendingKeys > 0 then
        local attempts = 0
        local maxAttempts = 5
        local retryTimer
        retryTimer = C_Timer.NewTicker(1.0, function()
            attempts = attempts + 1
            local stillPending = {}
            for _, iconKey in ipairs(pendingKeys) do
                if not runtime.iconFrames[iconKey] then
                    local iconData = db.iconData[iconKey]
                    if iconData then
                        local groupKey = FindIconGroup(iconKey, db)
                        local settings
                        if groupKey == "ungrouped" or db.ungrouped[iconKey] then
                            settings = db.ungroupedPositions and db.ungroupedPositions[iconKey]
                            groupKey = iconKey
                        else
                            settings = GetGroupSettings(groupKey)
                        end
                        local parent = EnsureGroupFrame(groupKey, settings)
                        local frame = CreateDynamicIcon(iconKey, iconData, parent)
                        if frame then
                            runtime.iconFrames[iconKey] = frame
                        else
                            stillPending[#stillPending + 1] = iconKey
                        end
                    end
                end
            end
            pendingKeys = stillPending
            if #pendingKeys == 0 or attempts >= maxAttempts then
                if retryTimer then retryTimer:Cancel() end
                RefreshAllLayouts()
                UpdateAllIcons(nil, "all")
            end
        end)
    end
end

function CustomIcons:CreateCustomIconsTrackerFrame()
    if not DDingUI.db.profile.customIcons.enabled then return nil end

    -- Create the main container frame (for backwards compatibility)
    if not DDingUI.customIconsTrackerFrame then
        DDingUI.customIconsTrackerFrame = CreateFrame("Frame", "DDingUI_CustomIconsTrackerFrame", UIParent)
        DDingUI.customIconsTrackerFrame:SetSize(200, 40)
        DDingUI.customIconsTrackerFrame:SetFrameStrata("MEDIUM")
        DDingUI.customIconsTrackerFrame:SetClampedToScreen(true)
        DDingUI.customIconsTrackerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
        DDingUI.customIconsTrackerFrame._DDingUI_CustomIconsTracker = true
    end

    -- Load all dynamic icons
    self:LoadDynamicIcons()

    return DDingUI.customIconsTrackerFrame
end

-- ------------------------
-- Public API
-- ------------------------

-- [FIX] FlightHide에서 다이나믹 그룹 프레임 알파 적용을 위한 getter
function CustomIcons:GetRuntimeFrames()
    return runtime
end

local CDM_SOURCE_GROUP_NAMES = {
    Cooldowns = "Essential Cooldowns",
    Buffs = "Buffs",
    Utility = "Utility Cooldowns",
}

local function GetDynamicGroupIconCount(group)
    return group and group.icons and #group.icons or 0
end

local function BuildDynamicIconOrderSet(groupSettings)
    local order = groupSettings and groupSettings.iconOrder
    if type(order) ~= "table" then return nil, 0 end

    local set, count = {}, 0
    for _, token in ipairs(order) do
        if type(token) == "string" then
            local iconKey = token:match("^dyn:(.+)$")
            if iconKey and not set[iconKey] then
                set[iconKey] = true
                count = count + 1
            end
        end
    end

    if count == 0 then return nil, 0 end
    return set, count
end

local function CountDynamicIconOrderMatches(sourceGroup, orderSet)
    if not (sourceGroup and sourceGroup.icons and orderSet) then return 0 end

    local matches = 0
    for _, iconKey in ipairs(sourceGroup.icons) do
        if orderSet[iconKey] then
            matches = matches + 1
        end
    end
    return matches
end

local function FindBestSourceGroupForCDMGroup(db, groupName, groupSettings)
    if not (db and db.groups and groupName) then return nil end

    local preferredKey = groupSettings and groupSettings.sourceGroupKey
    local orderSet = BuildDynamicIconOrderSet(groupSettings)
    local bestKey, bestGroup, bestCount, bestOrderMatches
    local function Consider(sourceKey, sourceGroup)
        if not sourceKey or not sourceGroup or sourceGroup.linkedCDMGroup ~= groupName then return end
        local count = GetDynamicGroupIconCount(sourceGroup)
        local orderMatches = CountDynamicIconOrderMatches(sourceGroup, orderSet)
        if not bestKey
            or orderMatches > bestOrderMatches
            or (orderMatches == bestOrderMatches and count > bestCount)
            or (orderMatches == bestOrderMatches and count == bestCount and sourceKey == preferredKey)
            or (orderMatches == bestOrderMatches and count == bestCount and sourceKey ~= preferredKey and bestKey ~= preferredKey and tostring(sourceKey) < tostring(bestKey))
        then
            bestKey = sourceKey
            bestGroup = sourceGroup
            bestCount = count
            bestOrderMatches = orderMatches
        end
    end

    if preferredKey then
        Consider(preferredKey, db.groups[preferredKey])
    end
    for sourceKey, sourceGroup in pairs(db.groups) do
        Consider(sourceKey, sourceGroup)
    end

    return bestKey, bestGroup
end

function CustomIcons:GetOrCreateSourceGroupForCDMGroup(groupName, displayName)
    if type(groupName) ~= "string" or groupName == "" then return nil end

    local profile = DDingUI.db and DDingUI.db.profile
    if not profile then return nil end

    local gs = rawget(profile, "groupSystem")
    if type(gs) ~= "table" then
        local defaults = DDingUI.defaults and DDingUI.defaults.profile and DDingUI.defaults.profile.groupSystem
        gs = type(defaults) == "table" and CopyStoredValue(defaults) or {}
        profile.groupSystem = gs
    end

    local groupDefaults = DDingUI.defaults
        and DDingUI.defaults.profile
        and DDingUI.defaults.profile.groupSystem
        and DDingUI.defaults.profile.groupSystem.groups
    if type(gs.groups) ~= "table" then
        gs.groups = type(groupDefaults) == "table" and CopyStoredValue(groupDefaults) or {}
    end

    local groupSettings = rawget(gs.groups, groupName)
    if type(groupSettings) ~= "table" then
        local defaultGroup = type(groupDefaults) == "table" and groupDefaults[groupName]
        groupSettings = type(defaultGroup) == "table" and CopyStoredValue(defaultGroup) or {}
        gs.groups[groupName] = groupSettings
    end
    if not groupSettings.name then
        groupSettings.name = displayName or CDM_SOURCE_GROUP_NAMES[groupName] or groupName
    end
    if groupSettings.enabled == nil then
        groupSettings.enabled = true
    end

    local db = GetDynamicDB()
    local sourceKey, sourceGroup = FindBestSourceGroupForCDMGroup(db, groupName, groupSettings)
    if sourceKey and sourceGroup then
        groupSettings.sourceGroupKey = sourceKey
        sourceGroup.linkedCDMGroup = groupName
        sourceGroup.enabled = groupSettings.enabled ~= false
        return sourceKey
    end

    sourceKey = self:CreateDynamicGroup(displayName or groupSettings.name or CDM_SOURCE_GROUP_NAMES[groupName] or groupName)
    if not sourceKey then return nil end

    sourceGroup = db.groups and db.groups[sourceKey]
    if sourceGroup then
        sourceGroup.linkedCDMGroup = groupName
        sourceGroup.enabled = groupSettings.enabled ~= false
    end

    groupSettings.sourceGroupKey = sourceKey
    groupSettings.groupType = "cdm"
    return sourceKey
end

function CustomIcons:EnsureCDMSourceGroups()
    if not (DDingUI.db and DDingUI.db.profile) then return false end

    GetDynamicDB()
    local changed = false
    for _, groupName in ipairs({ "Cooldowns", "Buffs", "Utility" }) do
        local profile = DDingUI.db.profile
        local gs = profile and profile.groupSystem
        local before = gs and gs.groups and gs.groups[groupName] and gs.groups[groupName].sourceGroupKey
        local sourceKey = self:GetOrCreateSourceGroupForCDMGroup(groupName, CDM_SOURCE_GROUP_NAMES[groupName] or groupName)
        if sourceKey and sourceKey ~= before then
            changed = true
        end
    end
    return changed
end

function CustomIcons:AddIconToCDMGroup(groupName, iconData, displayName)
    if type(iconData) ~= "table" then return nil end

    local groupManager = DDingUI.GroupManager
    if groupManager and groupManager.AssignMatchingCDMBuffIcon then
        local assignedSpellName = groupManager:AssignMatchingCDMBuffIcon(iconData, groupName)
        if assignedSpellName then
            local groupSystem = DDingUI.GroupSystem
            if groupSystem and groupSystem.RequestFullUpdate then
                groupSystem:RequestFullUpdate()
            end
            return assignedSpellName
        end
    end

    local sourceKey = self:GetOrCreateSourceGroupForCDMGroup(groupName, displayName)
    if not sourceKey then return nil end

    iconData.settings = iconData.settings or {}
    iconData.settings.targetCDMGroup = groupName

    if iconData.type == "aura" and iconData.id then
        local db = GetDynamicDB()
        local newID = tonumber(iconData.id)
        if newID and AURA_EQUIVALENT_IDS[newID] then
            newID = 2825
        end
        for existingKey, existingData in pairs((db and db.iconData) or {}) do
            if type(existingData) == "table" and existingData.type == "aura" then
                local existingID = tonumber(existingData.id)
                if existingID and AURA_EQUIVALENT_IDS[existingID] then
                    existingID = 2825
                end
                local existingSettings = existingData.settings
                if newID and existingID == newID
                    and type(existingSettings) == "table"
                    and existingSettings.targetCDMGroup == groupName
                then
                    self:MoveIconToGroup(existingKey, sourceKey)
                    return existingKey, sourceKey
                end
            end
        end
    end

    local iconKey = self:AddDynamicIcon(iconData)
    if iconKey then
        self:MoveIconToGroup(iconKey, sourceKey)
    end

    return iconKey, sourceKey
end

function CustomIcons:AddDynamicIcon(iconData)
    local db = GetDynamicDB()
    local iconKey = iconData.key
    if not iconKey or db.iconData[iconKey] then
        iconKey = BuildUniqueDBKey("icon_", db.iconData)
    end
    iconData.key = iconKey
    EnsureIconSettings(iconData)
    EnsureLoadConditions(iconData)
    EnsureStoredIconTexture(iconData)

    db.iconData[iconKey] = iconData
    EnsureLoadConditions(db.iconData[iconKey])
    db.ungrouped[iconKey] = true
    db.ungroupedPositions = db.ungroupedPositions or {}
    db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()

    -- Build frame — CreateDynamicIcon은 항상 프레임 반환 (CDM 방식)
    local frame = CreateDynamicIcon(iconKey, iconData, EnsureGroupFrame(iconKey, db.ungroupedPositions[iconKey]))
    if frame then
        runtime.iconFrames[iconKey] = frame
        UpdateDynamicIcon(iconKey)
        RefreshAllLayouts()
    end

    CustomIcons:RefreshDynamicListUI()
    -- [FIX] SpecProfiles 즉시 저장 — 리로드 시 LoadSpec이 이전 스냅샷으로 복원하여 데이터 손실 방지
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    return iconKey
end

function CustomIcons:RemoveDynamicIcon(iconKey)
    local db = GetDynamicDB()
    db.iconData[iconKey] = nil
    db.ungrouped[iconKey] = nil
    if db.ungroupedPositions then
        db.ungroupedPositions[iconKey] = nil
    end
    for _, group in pairs(db.groups) do
        for i = #group.icons, 1, -1 do
            if group.icons[i] == iconKey then
                table.remove(group.icons, i)
            end
        end
    end

    local frame = runtime.iconFrames[iconKey]
    if frame then
        ReleaseDynamicIconFrame(iconKey, frame)
        runtime.iconFrames[iconKey] = nil
    end

    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
end

function CustomIcons:CreateDynamicGroup(name)
    local db = GetDynamicDB()
    local key = BuildUniqueDBKey("group_", db.groups)
    local startAnchor = GetStartAnchorForGrowthPair("RIGHT", "DOWN")
    db.groups[key] = {
        name = name or (L["New Group"] or "New Group"),
        enabled = true,
        icons = {},
        settings = {
            growthDirection = "RIGHT",
            rowGrowthDirection = "DOWN",
            anchorFrom = startAnchor,
            anchorTo = startAnchor,
            spacing = 5,
            maxIconsPerRow = 10,
            -- No default position - will be set when first icon is added
        },
    }
    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    return key
end

function CustomIcons:RemoveGroup(groupKey)
    local db = GetDynamicDB()
    local group = db.groups[groupKey]
    if not group then return end

    -- 그룹 내 아이콘들을 실제로 삭제
    local iconsToRemove = {}
    for _, iconKey in ipairs(group.icons or {}) do
        iconsToRemove[#iconsToRemove + 1] = iconKey
    end
    -- [FIX] DynamicIconBridge managed 상태도 정리 (DestroyGroup의 ReleaseFrame이 복원하는 것 방지)
    local bridge = DDingUI.DynamicIconBridge
    for _, iconKey in ipairs(iconsToRemove) do
        -- iconData 삭제
        db.iconData[iconKey] = nil
        db.ungrouped[iconKey] = nil
        if db.ungroupedPositions then
            db.ungroupedPositions[iconKey] = nil
        end
        -- bridge managed 상태 정리 (DestroyGroup→ReleaseFrame이 orig.parent로 복원하는 것 방지)
        local frame = runtime.iconFrames[iconKey]
        if frame then
            if bridge and bridge.ReleaseFrame then
                bridge:ReleaseFrame(frame, iconKey)
            end
            ReleaseDynamicIconFrame(iconKey, frame)
            runtime.iconFrames[iconKey] = nil
        end
    end

    db.groups[groupKey] = nil
    local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    if gs and gs.groups then
        for gsGroupKey, settings in pairs(gs.groups) do
            if settings and settings.sourceGroupKey == groupKey then
                if settings.groupType == "dynamic" then
                    gs.groups[gsGroupKey] = nil
                    if gs.deletedGroups then
                        gs.deletedGroups[gsGroupKey] = true
                    end
                else
                    settings.sourceGroupKey = nil
                    settings._missingDynamicSource = nil
                    settings._missingDynamicSourceKey = nil
                end
            end
        end
    end
    -- [FIX] 그룹 컨테이너 프레임도 정리 (고스트 컨테이너 방지)
    local container = runtime.groupFrames and runtime.groupFrames[groupKey]
    if container then
        container:Hide()
        runtime.groupFrames[groupKey] = nil
    end
    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
    CustomIcons:RefreshDynamicConfigUI()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
end

function CustomIcons:MoveIconToGroup(iconKey, targetGroup)
    local db = GetDynamicDB()
    local function removeFromGroup(gkey)
        local group = db.groups[gkey]
        if not group or not group.icons then return end
        for i = #group.icons, 1, -1 do
            if group.icons[i] == iconKey then
                table.remove(group.icons, i)
            end
        end
    end

    if targetGroup == "ungrouped" then
        db.ungrouped[iconKey] = true
        db.ungroupedPositions = db.ungroupedPositions or {}
        db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
    else
        db.ungrouped[iconKey] = nil
        if db.ungroupedPositions then
            db.ungroupedPositions[iconKey] = nil
        end
        if db.groups[targetGroup] then
            db.groups[targetGroup].icons = db.groups[targetGroup].icons or {}
            -- Ensure the icon is not already present to avoid duplicates
            removeFromGroup(targetGroup)

            if db.groups[targetGroup].linkedCDMGroup and db.iconData[iconKey] then
                db.iconData[iconKey].settings = db.iconData[iconKey].settings or {}
                db.iconData[iconKey].settings.targetCDMGroup = db.groups[targetGroup].linkedCDMGroup
            end

            -- If this is the first icon in the group, position the group at the icon's current location
            if #db.groups[targetGroup].icons == 0 then
                local iconFrame = runtime.iconFrames[iconKey]
                if iconFrame then
                    local iconX, iconY = iconFrame:GetCenter()
                    if iconX and iconY then
                        -- Convert from world coordinates to relative coordinates
                        local uiScale = UIParent:GetEffectiveScale()
                        iconX = iconX / uiScale
                        iconY = iconY / uiScale

                        -- Get the current anchor frame
                        local settings = db.groups[targetGroup].settings or {}
                        local anchorFrame = GetAnchorFrame(settings.anchorFrame)

                        -- Calculate position relative to anchor frame
                        local anchorX, anchorY = anchorFrame:GetCenter()
                        anchorX = anchorX / uiScale
                        anchorY = anchorY / uiScale

                        settings.position = {
                            x = iconX - anchorX,
                            y = iconY - anchorY
                        }
                        db.groups[targetGroup].settings = settings
                    end
                end
            end

            table.insert(db.groups[targetGroup].icons, iconKey)
        end
    end

    -- Remove from other groups
    for gk, group in pairs(db.groups) do
        for i = #group.icons, 1, -1 do
            if group.icons[i] == iconKey and gk ~= targetGroup then
                table.remove(group.icons, i)
            end
        end
    end

    -- Destroy standalone container when moving into a group
    if targetGroup ~= "ungrouped" then
        local cont = runtime.groupFrames[iconKey]
        if cont then
            cont:Hide()
            runtime.groupFrames[iconKey] = nil
        end
    end

    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
    -- [FIX] SpecProfiles 즉시 저장 — MoveIconToGroup 후 스냅샷 갱신
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    -- [FIX] GroupSystem 옵션 트리 재빌드 — 할당 목록에 새 아이콘 즉시 표시
    if DDingUI.RefreshConfigGUI then
        DDingUI:RefreshConfigGUI(true)
    end
end

function CustomIcons:ReorderIconInGroup(groupKey, iconKey, targetKey, insertAfter)
    local db = GetDynamicDB()
    if groupKey == "ungrouped" then
        -- preserve set semantics for ungrouped; sorting not needed
        return false
    end
    local group = db.groups[groupKey]
    if not group or not group.icons then return false end

    local srcIdx, dstIdx
    for i, k in ipairs(group.icons) do
        if k == iconKey then srcIdx = i end
        if k == targetKey then dstIdx = i end
    end
    if not srcIdx or not dstIdx or srcIdx == dstIdx then return false end

    local moving = table.remove(group.icons, srcIdx)
    if srcIdx < dstIdx then
        dstIdx = dstIdx - 1
    end

    local insertIdx = insertAfter and (dstIdx + 1) or dstIdx
    if insertIdx < 1 then insertIdx = 1 end
    if insertIdx > #group.icons + 1 then insertIdx = #group.icons + 1 end
    table.insert(group.icons, insertIdx, moving)

    RefreshAllLayouts()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    return true
end

-- [FIX] 방향 이동 (↑위/↓아래): 그룹 내 아이콘 순서 변경
function CustomIcons:MoveIconInGroup(groupKey, iconKey, direction)
    local db = GetDynamicDB()
    local group = db.groups[groupKey]
    if not group or not group.icons then return end

    local currentIndex
    for i, k in ipairs(group.icons) do
        if k == iconKey then
            currentIndex = i
            break
        end
    end
    if not currentIndex then return end

    local newIndex
    if direction == "up" then
        newIndex = currentIndex - 1
    elseif direction == "down" then
        newIndex = currentIndex + 1
    end
    if not newIndex or newIndex < 1 or newIndex > #group.icons then return end

    -- swap
    group.icons[currentIndex], group.icons[newIndex] = group.icons[newIndex], group.icons[currentIndex]

    RefreshAllLayouts()
    -- SpecProfiles 즉시 저장
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
end

-- Options-only UI bridge. The Options addon replaces the no-op refresh methods when loaded.
CustomIcons.OptionsAPI = {
    runtime = runtime,
    defaultIconSettings = DEFAULT_ICON_SETTINGS,
    fallbackItemIcon = FALLBACK_ITEM_ICON,
    fallbackRacialIcon = FALLBACK_RACIAL_ICON,
    fallbackSlotIcon = FALLBACK_SLOT_ICON,
    fallbackSpellIcon = FALLBACK_SPELL_ICON,
    ApplyIconBorder = ApplyIconBorder,
    EnsureEventFrame = EnsureEventFrame,
    EnsureIconType = EnsureIconType,
    EnsureLoadConditions = EnsureLoadConditions,
    GetAnchorFrame = GetAnchorFrame,
    GetDefaultRowGrowth = GetDefaultRowGrowth,
    GetDynamicDB = GetDynamicDB,
    GetGroupDisplayName = GetGroupDisplayName,
    GetPlayerRacialSpellID = GetPlayerRacialSpellID,
    GetStartAnchorForGrowthPair = GetStartAnchorForGrowthPair,
    GetStoredIconTexture = GetStoredIconTexture,
    NonQuestionTexture = NonQuestionTexture,
    NormalizeRowGrowth = NormalizeRowGrowth,
    RefreshAllLayouts = RefreshAllLayouts,
    ReleaseDynamicIconFrame = ReleaseDynamicIconFrame,
    ResolveAnchorPoints = ResolveAnchorPoints,
    ResolveItemTexture = ResolveItemTexture,
    ResolveSpellTexture = ResolveSpellTexture,
    UpdateDynamicIcon = UpdateDynamicIcon,
}

function CustomIcons:RefreshDynamicListUI() end
function CustomIcons:RefreshDynamicConfigUI() end

-- Expose runtime data for external access (Movers system)
CustomIcons.GetGroupFrames = function() return runtime.groupFrames end
CustomIcons.runtime = runtime

-- Auto-load saved icons when DB is available
if DDingUI.db and DDingUI.db.profile then
    CustomIcons:LoadDynamicIcons()
end

-- Missing functions expected by Main.lua
function CustomIcons:ApplyCustomIconsLayout()
    if RefreshAllLayouts then
        RefreshAllLayouts()
    end
end

-- Stub functions for Trinkets/Defensives trackers (not implemented)
function CustomIcons:CreateTrinketsTrackerFrame()
    return nil
end

function CustomIcons:CreateDefensivesTrackerFrame()
    return nil
end

function CustomIcons:ApplyTrinketsLayout()
    -- Not implemented
end

function CustomIcons:ApplyDefensivesLayout()
    -- Not implemented
end

-- [DYNAMIC] GroupSystem DynamicIconBridge용 API
-- 모든 활성 아이콘 프레임 반환 (runtime.iconFrames 참조)
function CustomIcons:GetAllIconFrames()
    return runtime.iconFrames
end

-- [INTEGRATION] GroupRenderer가 직접 호출할 수 있도록 export
CustomIcons.CreateDynamicIcon = CreateDynamicIcon
CustomIcons.UpdateDynamicIcon = UpdateDynamicIcon
CustomIcons.GetDynamicDB = GetDynamicDB
