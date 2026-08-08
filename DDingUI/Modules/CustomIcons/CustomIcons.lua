local ns = select(2, ...)
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local SL = _G.DDingUI_StyleLib -- [12.0.1]

DDingUI.CustomIcons = DDingUI.CustomIcons or {}
local CustomIcons = DDingUI.CustomIcons

local ShowTextureBorder = DDingUI.ShowTextureBorder

local IconStyle = DDingUI.CustomIconStyle
local DEFAULT_ICON_SETTINGS = IconStyle.defaultIconSettings
local EnsureIconType = IconStyle.EnsureIconType
local EnsureIconSettings = IconStyle.EnsureIconSettings
local ApplyIconBorder = IconStyle.ApplyIconBorder
local ApplyIconSettings = IconStyle.ApplyIconSettings

local ResolveAnchorPoints = DDingUI.CustomIconLayoutPolicy.ResolveAnchorPoints
local GetStartAnchorForGrowth = DDingUI.CustomIconLayoutPolicy.GetStartAnchorForGrowth
local GetDefaultRowGrowth = DDingUI.CustomIconLayoutPolicy.GetDefaultRowGrowth
local NormalizeRowGrowth = DDingUI.CustomIconLayoutPolicy.NormalizeRowGrowth
local GetStartAnchorForGrowthPair = DDingUI.CustomIconLayoutPolicy.GetStartAnchorForGrowthPair
local BuildDefaultSettings = DDingUI.CustomIconLayoutPolicy.BuildDefaultSettings
local BuildDefaultUngroupedPositionSettings = DDingUI.CustomIconLayoutPolicy.BuildDefaultUngroupedPositionSettings
local NormalizeAnchor = DDingUI.CustomIconLayoutPolicy.NormalizeAnchor

local GetAuraFieldSafe = DDingUI.CustomIconRuntimeValues.GetAuraFieldSafe
local GetAuraSpellIDSafe = DDingUI.CustomIconRuntimeValues.GetAuraSpellIDSafe
local SafeNumber = DDingUI.CustomIconRuntimeValues.SafeNumber
local GetAuraNumberFieldSafe = DDingUI.CustomIconRuntimeValues.GetAuraNumberFieldSafe
local MaxSafeNumber = DDingUI.CustomIconRuntimeValues.MaxSafeNumber
local EvalDesatFromDurObj = DDingUI.CustomIconRuntimeValues.EvalDesatFromDurObj
local GetRealSpellCooldownDuration = DDingUI.CustomIconRuntimeValues.GetRealSpellCooldownDuration
local IsCooldownEnabled = DDingUI.CustomIconRuntimeValues.IsCooldownEnabled
local NormalizeCooldownSpan = DDingUI.CustomIconRuntimeValues.NormalizeCooldownSpan

local HasTableEntries = DDingUI.CustomIconProfileRecovery.HasTableEntries
local HasDynamicPayload = DDingUI.CustomIconProfileRecovery.HasDynamicPayload
local CountTableEntries = DDingUI.CustomIconProfileRecovery.CountTableEntries
local CountDynamicPayload = DDingUI.CustomIconProfileRecovery.CountDynamicPayload
local FindLegacyDynamicSpec = DDingUI.CustomIconProfileRecovery.FindLegacyDynamicSpec
local CopyStoredValue = DDingUI.CustomIconProfileRecovery.CopyStoredValue
local MergeMissingEntries = DDingUI.CustomIconProfileRecovery.MergeMissingEntries
local ScoreDynamicPayload = DDingUI.CustomIconProfileRecovery.ScoreDynamicPayload
local FindFallbackDynamicProfile = DDingUI.CustomIconProfileRecovery.FindFallbackDynamicProfile
local BuildUniqueDBKey = DDingUI.CustomIconProfileRecovery.BuildUniqueDBKey

local IconTextures = DDingUI.CustomIconTextures
local FALLBACK_SPELL_ICON = IconTextures.fallbackSpellIcon
local FALLBACK_ITEM_ICON = IconTextures.fallbackItemIcon
local FALLBACK_SLOT_ICON = IconTextures.fallbackSlotIcon
local FALLBACK_RACIAL_ICON = IconTextures.fallbackRacialIcon
local IsQuestionTexture = IconTextures.IsQuestionTexture
local NonQuestionTexture = IconTextures.NonQuestionTexture
local GetCustomAuraPresetIconTexture = IconTextures.GetCustomAuraPresetIconTexture
local ResolveItemTexture = IconTextures.ResolveItemTexture
local ResolveSpellTexture = IconTextures.ResolveSpellTexture
local GetStoredIconTexture = IconTextures.GetStoredIconTexture
local EnsureStoredIconTexture = IconTextures.EnsureStoredIconTexture

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

local NormalizePresetIconData
local NormalizePresetIconDB

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
    NormalizePresetIconDB(db, nil, nil, true)

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
local CUSTOM_ICON_EFFECT_GRACE_SECONDS = 1.5

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
    [29166]   = { duration = 7.8, trigger = "innervate" },  -- Innervate
    [406732]  = { duration = 10, trigger = "spatial_paradox" }, -- Spatial Paradox
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

NormalizePresetIconData, NormalizePresetIconDB = DDingUI.CustomIconProfileNormalization.Create(
    EnsureIconSettings,
    GetCustomAuraPresetIconTexture,
    runtime,
    CUSTOM_TIMED_AURA_CONFIGS,
    AURA_EQUIVALENT_IDS
)

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

    if NormalizePresetIconDB(db, profile, false, true) then
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
        or config.trigger == "innervate"
        or config.trigger == "spatial_paradox"
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
    if DDingUI.CustomIconActiveEffectOverlay then
        DDingUI.CustomIconActiveEffectOverlay:SyncTextStyle(frame)
    end
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
                        if DDingUI.CustomIconActiveEffectOverlay then
                            DDingUI.CustomIconActiveEffectOverlay:SyncTextStyle(frame)
                        end
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
        or frame._ddInactiveAlpha ~= nil
        or frame._ddInactivePlaceholder == true
        or frame._ddManagedAuraExpired == true
        or frame._ddCombatVisible == false
end

function CustomIcons.PrepareInactivePlaceholder(frame, iconData)
    local settings = iconData and iconData.settings
    if not frame or not settings or settings.alwaysShow ~= "on" then return false end

    local alpha = tonumber(settings.inactiveAlpha) or 0.5
    alpha = math.max(0.05, math.min(1, alpha))
    local desaturated = settings.desatInactive ~= "off"

    frame._ddInactivePlaceholder = true
    frame._ddInactiveGray = desaturated and true or nil
    frame._ddForcedInactiveGray = desaturated and true or nil
    frame._ddInactiveAlpha = alpha
    frame._ddManagedAuraExpired = nil
    frame._ddCombatVisible = true
    frame._ddCombatKeepAlive = nil
    return true
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
    local icon = frame.icon or frame.Icon
    if frame._ddInactivePlaceholder or frame._ddInactiveGray then
        if frame.cooldown then
            if frame.cooldown.Clear then frame.cooldown:Clear() end
            if frame.cooldown.Hide then frame.cooldown:Hide() end
        end
        if frame.Cooldown and frame.Cooldown ~= frame.cooldown then
            if frame.Cooldown.Clear then frame.Cooldown:Clear() end
            if frame.Cooldown.Hide then frame.Cooldown:Hide() end
        end
        if frame.count and frame.count.Hide then frame.count:Hide() end
        frame._ddManagedAuraExpired = nil
        frame._ddCombatVisible = true
        frame._ddCombatKeepAlive = nil
        if frame.Show then frame:Show() end
        if frame.SetAlpha then
            local groupAlpha = frame._groupSettings and frame._groupSettings.groupAlpha or 1
            frame:SetAlpha(groupAlpha)
            frame._ddLastGroupAlpha = groupAlpha
        end
        if icon then
            if icon.Show then icon:Show() end
            if icon.SetAlpha then
                local inactiveAlpha = tonumber(frame._ddInactiveAlpha) or 0.5
                icon:SetAlpha(math.max(0.05, math.min(1, inactiveAlpha)))
            end
            if icon.SetDesaturated then icon:SetDesaturated(frame._ddInactiveGray == true) end
            if icon.SetDesaturation then icon:SetDesaturation(frame._ddInactiveGray and 1 or 0) end
        end
        return true
    end
    if frame.SetAlpha then
        frame:SetAlpha(0)
        frame._ddLastGroupAlpha = 0
    end
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
            CustomIcons.PrepareInactivePlaceholder(frame, iconData)
            local keptPlaceholder = CustomIcons.SuppressExpiredIconVisual(frame)
            if frame._ddIsManaged then
                if not keptPlaceholder then
                    frame._ddManagedAuraExpired = true
                end
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
    local target = frame._ddTrinketEffectGlowTarget or frame
    if SL then
        if SL.HidePixelGlow then SL.HidePixelGlow(target, key) end
        if SL.HideAutocastGlow then SL.HideAutocastGlow(target, key) end
        if SL.HideButtonGlow then SL.HideButtonGlow(target, key) end
    end
    local glow = LibStub and LibStub("LibCustomGlow-1.0", true)
    if glow and glow.ProcGlow_Stop then
        glow.ProcGlow_Stop(target, key)
    end
    if frame._ddTrinketEffectGlowType == "Blizzard Glow" and ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(target)
    end
    frame._ddTrinketEffectGlowActive = nil
    frame._ddTrinketEffectGlowType = nil
    frame._ddTrinketEffectGlowSignature = nil
    frame._ddTrinketEffectGlowTarget = nil
end

function CustomIcons:SetTrackedTrinketEffectGlow(frame, active, iconGlow, inheritedStyle, forceGlow)
    local settings = frame and frame._groupSettings or {}
    local useIconGlow = type(iconGlow) == "table"
    local useAuraGlow = not useIconGlow and settings.auraGlow == true
    local glowEnabled = forceGlow or useIconGlow or useAuraGlow or settings.procGlowEnabled ~= false
    if not active or not glowEnabled
        or (not forceGlow and not useIconGlow and settings.hideActiveState == true)
        or (not useIconGlow and CustomIcons.ManagedVisualLocked(frame))
    then
        self:StopTrackedTrinketEffectGlow(frame)
        return
    end

    local glowType
    local color
    local useBlizzardColor
    local pixelLines
    local pixelFrequency
    local pixelLength
    local pixelThickness
    local autocastParticles
    local autocastFrequency
    local autocastScale
    local buttonFrequency
    local pixelXOffset
    local pixelYOffset
    local pixelBorder
    if useIconGlow then
        useBlizzardColor = iconGlow.glowColorMode == "blizzard"
            or iconGlow.glowType == "blizzard"
        local customType = iconGlow.glowType == "blizzard"
            and "proc" or iconGlow.glowType or "button"
        glowType = customType == "pixel" and "Pixel Glow"
            or customType == "autocast" and "Autocast Shine"
            or customType == "proc" and "Proc Glow"
            or "Action Button Glow"
        if not useBlizzardColor and iconGlow.glowColorMode == "class" then
            local _, classFile = UnitClass("player")
            local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if classColor then
                color = { classColor.r, classColor.g, classColor.b, classColor.a or 1 }
            end
        elseif not useBlizzardColor and (iconGlow.glowColorMode == "custom"
            or (iconGlow.glowColorMode == nil and iconGlow.glowColor)
        ) then
            color = iconGlow.glowColor
        end
        if not useBlizzardColor then
            color = color or { 1, 0.85, 0.1, 1 }
        end
        pixelLines = iconGlow.glowLines or 8
        pixelFrequency = iconGlow.glowSpeed or 0.25
        pixelThickness = iconGlow.glowThickness or 2
        autocastParticles = 4
        autocastFrequency = iconGlow.glowSpeed or 0.25
        autocastScale = 1
        buttonFrequency = iconGlow.glowSpeed or 0.25
        pixelXOffset = 0
        pixelYOffset = 0
        pixelBorder = true
    else
        glowType = useAuraGlow and (settings.auraGlowType or "Pixel Glow")
            or (settings.procGlowType or "Pixel Glow")
        useBlizzardColor = (useAuraGlow and settings.auraGlowColorMode == "blizzard")
            or (not useAuraGlow and settings.procGlowColorMode == "blizzard")
            or glowType == "Blizzard Glow"
        if glowType == "Blizzard Glow" then
            glowType = "Proc Glow"
        end
        color = useAuraGlow and (settings.auraGlowColor or { 0.95, 0.95, 0.32, 1 })
            or (settings.procGlowColor or { 0.95, 0.95, 0.32, 1 })
        if useBlizzardColor then
            color = nil
        end
        pixelLines = useAuraGlow and (settings.auraGlowPixelLines or 8)
            or (settings.procGlowPixelLines or 5)
        pixelFrequency = useAuraGlow and (settings.auraGlowPixelFrequency or 0.25)
            or (settings.procGlowPixelFrequency or 0.25)
        pixelLength = useAuraGlow and settings.auraGlowPixelLength
            or (settings.procGlowPixelLength or 8)
        pixelThickness = useAuraGlow and (settings.auraGlowPixelThickness or 2)
            or (settings.procGlowPixelThickness or 1)
        autocastParticles = useAuraGlow and (settings.auraGlowAutocastParticles or 8)
            or (settings.procGlowAutocastParticles or 8)
        autocastFrequency = useAuraGlow and (settings.auraGlowAutocastFrequency or 0.25)
            or (settings.procGlowAutocastFrequency or 0.25)
        autocastScale = useAuraGlow and (settings.auraGlowAutocastScale or 1)
            or (settings.procGlowAutocastScale or 1)
        buttonFrequency = useAuraGlow and (settings.auraGlowButtonFrequency or 0.25)
            or (settings.procGlowButtonFrequency or 0.25)
        pixelXOffset = -1
        pixelYOffset = -1
        pixelBorder = false
        if type(inheritedStyle) == "table" then
            if inheritedStyle.glowColorMode ~= nil
                or inheritedStyle.glowType == "blizzard"
            then
                useBlizzardColor = inheritedStyle.glowColorMode == "blizzard"
                    or inheritedStyle.glowType == "blizzard"
            end
            local customType = inheritedStyle.glowType == "blizzard"
                and "proc" or inheritedStyle.glowType
            if customType then
                glowType = customType == "pixel" and "Pixel Glow"
                    or customType == "autocast" and "Autocast Shine"
                    or customType == "proc" and "Proc Glow"
                    or "Action Button Glow"
            end
            if not useBlizzardColor and inheritedStyle.glowColorMode == "class" then
                local _, classFile = UnitClass("player")
                local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                if classColor then
                    color = { classColor.r, classColor.g, classColor.b, classColor.a or 1 }
                end
            elseif not useBlizzardColor and (inheritedStyle.glowColorMode == "custom"
                or (inheritedStyle.glowColorMode == nil and inheritedStyle.glowColor)
            ) then
                color = inheritedStyle.glowColor or color
            end
            if useBlizzardColor then
                color = nil
            elseif not color then
                color = { 0.95, 0.95, 0.32, 1 }
            end
            pixelLines = inheritedStyle.glowLines or pixelLines
            pixelFrequency = inheritedStyle.glowSpeed or pixelFrequency
            pixelThickness = inheritedStyle.glowThickness or pixelThickness
            autocastFrequency = inheritedStyle.glowSpeed or autocastFrequency
            buttonFrequency = inheritedStyle.glowSpeed or buttonFrequency
            pixelXOffset = 0
            pixelYOffset = 0
            pixelBorder = true
        end
    end
    local activeOverlay = frame._ddActiveEffectOverlay
    local target = activeOverlay and activeOverlay.token and activeOverlay.frame or frame
    local signature = table.concat({
        useIconGlow and "icon" or useAuraGlow and "aura" or "proc",
        glowType,
        useBlizzardColor and "blizzard" or "tinted",
        tostring(color and (color[1] or color.r) or 0.95),
        tostring(color and (color[2] or color.g) or 0.95),
        tostring(color and (color[3] or color.b) or 0.32),
        tostring(color and (color[4] or color.a) or 1),
        tostring(pixelLines),
        tostring(pixelFrequency),
        tostring(pixelLength),
        tostring(pixelThickness),
        tostring(autocastParticles),
        tostring(autocastFrequency),
        tostring(autocastScale),
        tostring(buttonFrequency),
        tostring(pixelXOffset),
        tostring(pixelYOffset),
        tostring(pixelBorder),
    }, ":")
    if frame._ddTrinketEffectGlowActive
        and frame._ddTrinketEffectGlowSignature == signature
        and frame._ddTrinketEffectGlowTarget == target
    then
        return
    end

    self:StopTrackedTrinketEffectGlow(frame)
    local key = "_DDingUITrinketEffectGlow"
    if glowType == "Autocast Shine" and SL and SL.ShowAutocastGlow then
        SL.ShowAutocastGlow(
            target,
            color,
            math.floor(autocastParticles),
            autocastFrequency,
            autocastScale,
            0,
            0,
            key,
            useBlizzardColor
        )
    elseif glowType == "Action Button Glow" and SL and SL.ShowButtonGlow then
        SL.ShowButtonGlow(target, color, buttonFrequency, key)
    elseif glowType == "Proc Glow" then
        local glow = LibStub and LibStub("LibCustomGlow-1.0", true)
        if glow and glow.ProcGlow_Start then
            glow.ProcGlow_Start(target, {
                color = color,
                startAnim = false,
                xOffset = 0,
                yOffset = 0,
                key = key,
            })
        end
    elseif SL and SL.ShowPixelGlow then
        SL.ShowPixelGlow(
            target,
            color,
            math.floor(pixelLines),
            pixelFrequency,
            pixelLength,
            pixelThickness,
            pixelXOffset,
            pixelYOffset,
            pixelBorder,
            key,
            useBlizzardColor
        )
        glowType = "Pixel Glow"
    end

    frame._ddTrinketEffectGlowActive = true
    frame._ddTrinketEffectGlowType = glowType
    frame._ddTrinketEffectGlowSignature = signature
    frame._ddTrinketEffectGlowTarget = target
end

function CustomIcons:UpdateDynamicIconProcGlow(frame, iconData)
    local custom = iconData and iconData.settings and iconData.settings.customStateGlow
    local mode = custom and custom.procGlowMode
    local activeEffectOverlay = DDingUI.CustomIconActiveEffectOverlay
    local isItemActiveEffect = iconData and iconData.type == "item"
        and activeEffectOverlay
        and activeEffectOverlay.SupportsActiveEffect
        and activeEffectOverlay:SupportsActiveEffect(iconData.id, iconData.settings)
    if isItemActiveEffect
        and activeEffectOverlay.ShouldShowGlow
        and not activeEffectOverlay:ShouldShowGlow(iconData)
    then
        self:StopTrackedTrinketEffectGlow(frame)
        return
    end
    local displayMode = isItemActiveEffect and iconData.settings.activeEffectDisplayMode
    local forceGlow = displayMode == "both" or displayMode == "glow"
        or displayMode == "glow_duration"
    local hasStyleOverride = custom and (
        custom.glowType ~= nil
        or custom.glowColorMode ~= nil
        or custom.glowColor ~= nil
        or custom.glowLines ~= nil
        or custom.glowSpeed ~= nil
        or custom.glowThickness ~= nil
    )
    local procActive = frame and frame._ddCustomIconProcActive == true
    if procActive then
        frame._ddInactiveGray = nil
        frame._ddForcedInactiveGray = nil
        frame._ddInactiveAlpha = nil
        frame._ddInactivePlaceholder = nil
        frame._ddManagedAuraExpired = nil
        frame._ddCombatVisible = nil
        self.RestoreActiveIconVisual(frame)
    end
    if isItemActiveEffect and custom
        and (mode == "on" or custom.activeGlow == true)
    then
        self:SetTrackedTrinketEffectGlow(frame, procActive, custom, nil, forceGlow)
        return
    end
    if mode == "on" then
        self:StopTrackedTrinketEffectGlow(frame)
        return
    end
    if mode == "off" or (custom and custom.activeGlow == true) then
        self:StopTrackedTrinketEffectGlow(frame)
        return
    end
    self:SetTrackedTrinketEffectGlow(
        frame,
        procActive,
        nil,
        hasStyleOverride and custom or nil,
        forceGlow
    )
end

function CustomIcons:ApplyActiveTrinketEffectState(iconFrame, state, settings)
    if not iconFrame or not state then return false end
    settings = settings or {}
    iconFrame._ddInactiveGray = nil
    iconFrame._ddForcedInactiveGray = nil
    iconFrame._ddInactiveAlpha = nil
    iconFrame._ddInactivePlaceholder = nil
    iconFrame._ddManagedAuraExpired = nil
    iconFrame._ddCombatVisible = nil
    CustomIcons.RestoreActiveIconVisual(iconFrame)
    CustomIcons.StopIconDesatUpdater(iconFrame)
    iconFrame._ddCustomIconActive = true
    iconFrame._ddCustomIconProcActive = true
    iconFrame._ddCustomIconReady = false
    if iconFrame.icon then
        iconFrame.icon:SetDesaturated(false)
        iconFrame.icon:SetDesaturation(0)
    end
    local showDuration = settings.showCooldown ~= false
        and settings.showProcDuration ~= false
    ApplyCustomTimedAuraCooldownFrame(iconFrame, state, showDuration)
    if iconFrame.count then
        if settings.showProcStacks ~= false and state.stacks and state.stacks > 1 then
            iconFrame.count:SetText(state.stacks)
            iconFrame.count:Show()
        else
            iconFrame.count:SetText("")
            iconFrame.count:Hide()
        end
    end
    return true
end

function CustomIcons:ApplyTrackedTrinketEffect(iconFrame, iconData, itemID)
    if iconFrame then
        iconFrame._ddCustomIconActive = false
        iconFrame._ddCustomIconProcActive = false
    end
    local settings = iconData and iconData.settings
    local registry = DDingUI.TrinketEffects
    if not settings or settings.trackTrinketEffect ~= true
        or not registry or not registry.GetActiveEffectForItem
    then
        return false
    end

    return self:ApplyActiveTrinketEffectState(
        iconFrame,
        registry:GetActiveEffectForItem(itemID),
        settings
    )
end

function CustomIcons:UpdateDynamicIconStateGlow(frame, iconData)
    local customizer = DDingUI.IconCustomization
    if not customizer or not customizer.UpdateDynamicIconGlow then return end
    local settings = iconData and iconData.settings and iconData.settings.customStateGlow
    local activeEffectOverlay = DDingUI.CustomIconActiveEffectOverlay
    local isItemActiveEffect = iconData and iconData.type == "item"
        and activeEffectOverlay
        and activeEffectOverlay.SupportsActiveEffect
        and activeEffectOverlay:SupportsActiveEffect(iconData.id, iconData.settings)
    local active = frame._ddCustomIconActive == true
    local procActive = frame._ddCustomIconProcActive == true
    local ready = frame._ddCustomIconReady == true
    local shouldGlow = false
    if settings then
        if settings.procGlowMode == "on" and procActive then
            shouldGlow = not isItemActiveEffect
        elseif settings.activeGlow == true and active then
            shouldGlow = not isItemActiveEffect
        elseif settings.maxChargesGlow == true and frame._ddCustomIconAtMaxCharges == true then
            shouldGlow = true
        elseif settings.cooldownReadyGlow == true and ready then
            shouldGlow = true
        elseif settings.readyGlow == true then
            local trigger = settings.glowTrigger
                or (iconData
                    and (iconData.type == "aura"
                        or iconData.type == "trinketProc"
                        or iconData.type == "totem"
                        or (iconData.type == "item"
                            and iconData.settings
                            and tonumber(iconData.settings.activeEffectDuration)))
                    and "active"
                    or "ready")
            if trigger == "active" then
                shouldGlow = active
            else
                shouldGlow = ready
            end
        end
    end
    if customizer.ApplyDynamicIconState then
        customizer:ApplyDynamicIconState(frame, iconData and iconData.settings, active, ready)
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
                frame._ddInactiveAlpha = nil
                frame._ddInactivePlaceholder = nil
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
    local activeEffectOverlay = DDingUI.CustomIconActiveEffectOverlay
    local activeEffectOwnsCooldown = activeEffectOverlay
        and activeEffectOverlay.ShouldSuppressBaseCooldown
        and activeEffectOverlay:ShouldSuppressBaseCooldown(iconData)

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
    iconFrame._ddItemCountEmpty = itemCount == nil or itemCount == 0

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
        if activeEffectOwnsCooldown then
            iconFrame.cooldown:Hide()
        elseif iconData.settings and iconData.settings.showCooldown == false then
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

    local showEmptyItem = iconFrame._ddItemCountEmpty == true
    local desatVal = 0

    -- [FIX] OnUpdate 진입 조건: cdInfo.isActive (safe boolean) 사용 — secret number 비교 금지
    local itemIsOnRealCD = false

    if activeEffectOwnsCooldown then
        desatVal = 0
    elseif itemCombatLocked then
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
    iconFrame._ddCustomIconReady = not activeEffectOwnsCooldown
        and not itemCombatLocked
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
    local maxCharges = chargeInfo and chargeInfo.maxCharges
    if issecretvalue and issecretvalue(maxCharges) then maxCharges = nil end
    local isChargeSpell = type(maxCharges) == "number" and maxCharges > 1
    local chargeRecharging = chargeInfo and chargeInfo.isActive
    if issecretvalue and issecretvalue(chargeRecharging) then chargeRecharging = nil end
    iconFrame._ddCustomIconAtMaxCharges = isChargeSpell and chargeRecharging == false or false

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
    local racialAuraActive = racials and racials:IsAuraActive(racialID) or false
    local racialProcActive = racialAuraActive
        or (runtime.racialProcGlowOverlayActive == true)
        or ((runtime.racialProcGlowUntil or 0) > GetTime())
    if racialProcActive then
        iconFrame._ddInactiveGray = nil
        iconFrame._ddForcedInactiveGray = nil
        iconFrame._ddInactiveAlpha = nil
        iconFrame._ddInactivePlaceholder = nil
        iconFrame._ddManagedAuraExpired = nil
        iconFrame._ddCombatVisible = nil
        managedVisualLocked = false
        CustomIcons.RestoreActiveIconVisual(iconFrame)
    end

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
    iconFrame._ddCustomIconProcActive = racialProcActive
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
    local registry = DDingUI.TrinketEffects
    local trackedState = registry and registry.GetActiveEffectForItem
        and registry:GetActiveEffectForItem(itemID)
    if CustomIcons:ApplyActiveTrinketEffectState(iconFrame, trackedState, settings) then
        return
    end

    local auraData = ResolveTrinketProcAuraForIcon(iconFrame, iconData)
    local procActive = auraData ~= nil
    if auraData then
        iconFrame._ddInactiveGray = nil
        iconFrame._ddForcedInactiveGray = nil
        iconFrame._ddInactiveAlpha = nil
        iconFrame._ddInactivePlaceholder = nil
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
        iconFrame._ddProcActiveUntil = nil
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
    iconFrame._ddCustomIconProcActive = procActive == true
    iconFrame._ddCustomIconReady = procActive ~= true
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
        iconFrame._ddInactiveAlpha = nil
        iconFrame._ddInactivePlaceholder = nil
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
            local keepInactive = CustomIcons.PrepareInactivePlaceholder(iconFrame, iconData)
            iconFrame._ddManagedAuraExpired = keepInactive and nil or true
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

function CustomIcons:RefreshTrackedTrinketEffectIcons()
    local db = GetDynamicDB()
    for iconKey, iconData in pairs((db and db.iconData) or {}) do
        local tracksEffect = iconData and (
            iconData.type == "trinketProc"
            or (iconData.settings and iconData.settings.trackTrinketEffect == true)
        )
        if tracksEffect and runtime.UpdateDynamicIcon then
            runtime.UpdateDynamicIcon(iconKey)
        end
    end
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
    if changed then
        self:RefreshTrackedTrinketEffectIcons()
    end
    return changed == true
end

function CustomIcons:DeactivateExternalTimedAura(stateID)
    stateID = tonumber(stateID)
    if not stateID then return false end
    local changed = DeactivateCustomTimedAura(stateID)
    if changed then
        self:RefreshTrackedTrinketEffectIcons()
        NotifyCustomTimedAuraChanged("force")
    end
    return changed
end

function CustomIcons:IsCustomTimedAuraIcon(iconData)
    return GetCustomTimedAuraConfig(iconData) ~= nil
end

local function IconListContains(iconList, iconKey)
    if type(iconList) ~= "table" or not iconKey then return false end
    for _, key in pairs(iconList) do
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
                frame._ddInactiveAlpha = nil
                frame._ddInactivePlaceholder = nil
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
    if iconData.type == "item" then
        local hideWhenEmpty = iconData.settings and iconData.settings.hideWhenEmpty == true
        return hideWhenEmpty and frame._ddItemCountEmpty == true and "hidden" or "visible"
    end
    if iconData.type == "totem" then
        return frame._ddTotemActive == true and "active" or "inactive"
    end
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
                typeMatches = iconType == "aura"
                    or iconType == "trinketProc"
                    or iconType == "racial"
                    or (iconType == "spell" and CustomIcons:IsCurrentRacialSpellIcon(iconData))
            elseif filter == "item" then
                typeMatches = iconType == "item" or iconType == "slot" or iconType == "trinketProc"
            elseif filter == "cooldown" then
                typeMatches = iconType == "item" or iconType == "slot" or iconType == "trinketProc" or iconType == "spell" or iconType == "racial"
            end
            if iconData and typeMatches and (frame._ddNeedsInitialUpdate or frame:IsVisible() or iconType == "aura" or iconType == "trinketProc" or iconType == "totem" or frame._ddIsManaged) then
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
                    frame._ddCustomIconAtMaxCharges = false
                    frame._ddCustomIconProcActive = false
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
                    elseif iconData.type == "totem" then
                        local totems = DDingUI.CustomIconTotems
                        if totems and totems.UpdateFrame then
                            totems:UpdateFrame(frame, iconData, true, false)
                        end
                    end
                    if DDingUI.CustomIconActiveEffectOverlay then
                        DDingUI.CustomIconActiveEffectOverlay:ApplyFrame(frame, iconData)
                        if iconData.type == "item" then
                            frame._ddCustomIconProcActive = frame._ddCustomIconProcActive == true
                                or DDingUI.CustomIconActiveEffectOverlay:IsProcActive(iconData)
                        end
                    end
                    CustomIcons:UpdateDynamicIconProcGlow(frame, iconData)
                    CustomIcons:UpdateDynamicIconStateGlow(frame, iconData)
                    ReapplyManagedGroupText(frame)

                    local afterLayoutState = GetDynamicLayoutStateToken(frame, iconData)
                    if beforeLayoutState and afterLayoutState and beforeLayoutState ~= afterLayoutState then
                        layoutStateChanged = true
                    end
                end)
                if okUpdate then
                    frame._ddLastUpdateError = nil
                    frame._ddNeedsInitialUpdate = nil
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
        if spellID and AURA_EQUIVALENT_IDS[spellID] == BLOODLUST_AURA_IDS then
            local config = CUSTOM_TIMED_AURA_CONFIGS[2825]
            local active = runtime.customTimedAuras[2825]
            if config
                and CountCustomTimedAuraLinks(2825) > 0
                and not (active and active.expirationTime and active.expirationTime > GetTime())
            then
                RecordTimedAuraDebug(2825, "spellcast", tostring(spellID))
                local _, didChange = ActivateCustomTimedAura(2825, config, nil, spellID)
                changed = didChange or changed
            elseif active and active.expirationTime and active.expirationTime > GetTime() then
                RecordTimedAuraDebug(2825, "alreadyActive", "spellcast")
            end
        end
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

local function SetCustomIconEventsEnabled(enabled)
    local frame = runtime.eventFrame
    if not enabled then
        if frame then
            frame:UnregisterAllEvents()
        end
        runtime.customIconEventsRegistered = false
        if runtime.loadRetryTicker then
            runtime.loadRetryTicker:Cancel()
            runtime.loadRetryTicker = nil
        end
        if _iconUpdateDispatchTimer then
            _iconUpdateDispatchTimer:Cancel()
            _iconUpdateDispatchTimer = nil
        end
        runtime.customIconDispatchDueAt = nil
        runtime.pendingIconUpdateFilter = nil
        runtime.refreshAllLayoutsPending = false
        runtime.layoutRefreshDueAt = nil
        _pendingIconUpdate = false
        _pendingIconLayoutNotify = false
        return
    end

    if not frame or runtime.customIconEventsRegistered then return end
    runtime.customIconEventsRegistered = true
    frame:RegisterEvent("BAG_UPDATE")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    frame:RegisterEvent("ITEM_COUNT_CHANGED")
    frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    frame:RegisterEvent("SPELL_UPDATE_CHARGES")
    frame:RegisterEvent("SPELL_UPDATE_USABLE")
    frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    frame:RegisterEvent("ARENA_COOLDOWNS_UPDATE")
    frame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_DEAD")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
end

local function EnsureEventFrame()
    if runtime.eventFrame then
        SetCustomIconEventsEnabled(true)
        return
    end
    runtime.eventFrame = CreateFrame("Frame")
    SetCustomIconEventsEnabled(true)
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
        local activeEffectChanged = succeededSpellID
            and DDingUI.CustomIconActiveEffectOverlay
            and DDingUI.CustomIconActiveEffectOverlay:HandleSpellcast(succeededSpellID)
        local isRacialSpellcast = succeededSpellID and succeededSpellID == GetPlayerRacialSpellID()
        local racialOverlayChanged = false
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
            or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
        then
            local overlaySpellID = SafeNumber(...)
            if overlaySpellID and overlaySpellID == GetPlayerRacialSpellID() then
                runtime.racialProcGlowOverlayActive = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
                racialOverlayChanged = true
            end
        elseif isRacialSpellcast then
            runtime.racialProcGlowToken = (runtime.racialProcGlowToken or 0) + 1
            local token = runtime.racialProcGlowToken
            runtime.racialProcGlowUntil = GetTime() + 1.25
            C_Timer.After(1.3, function()
                if runtime.racialProcGlowToken == token then
                    runtime.racialProcGlowUntil = nil
                    UpdateAllIcons(nil, "cooldown")
                end
            end)
        end
        if event == "UNIT_SPELLCAST_SENT" then return end
        if (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
            or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            and not customTimedChanged
            and not racialOverlayChanged
        then
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
        if event == "UNIT_SPELLCAST_SUCCEEDED"
            and not customTimedChanged
            and not activeEffectChanged
            and not hasItemCooldownIcon
            and not isRacialSpellcast
        then
            return
        end
        if (isItemCooldownEvent or isSpellCooldownEvent or isCooldownInventoryEvent)
            and not customTimedChanged
            and not activeEffectChanged
            and not hasItemCooldownIcon
            and not hasSpellCooldownIcon
        then
            return
        end

        -- Update all icons when relevant events fire.
        local needsLayoutNotify = nil
        if event == "UNIT_INVENTORY_CHANGED"
            or event == "PLAYER_EQUIPMENT_CHANGED"
        then
            needsLayoutNotify = "force"
        elseif event == "ITEM_COUNT_CHANGED"
            or event == "BAG_UPDATE"
            or event == "BAG_UPDATE_DELAYED"
        then
            needsLayoutNotify = "item"
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
local GetAnchorFrame,
    IsIconLoadable,
    ShouldIconSpawn,
    ReleaseDynamicIconFrame,
    CreateDynamicIcon,
    UpdateDynamicIcon = DDingUI.CustomIconFrameLifecycle.Create(
        runtime,
        CustomIcons,
        SL,
        ApplyIconSettings,
        EnsureLoadConditions,
        FALLBACK_ITEM_ICON,
        FALLBACK_RACIAL_ICON,
        FALLBACK_SLOT_ICON,
        FALLBACK_SPELL_ICON,
        GetDynamicDB,
        GetPlayerRacialSpellID,
        GetStoredIconTexture,
        HandleCooldownDone,
        ResolveItemTexture,
        ResolveSpellTexture,
        SetStableIconTexture,
        UpdateAuraIcon,
        UpdateItemIcon,
        UpdateRacialIconFrame,
        UpdateSlotIcon,
        UpdateSpellIconFrame,
        UpdateTrinketProcIcon
    )

function CustomIcons:RefreshDynamicIcon(iconKey)
    if iconKey and runtime.UpdateDynamicIcon then
        runtime.UpdateDynamicIcon(iconKey)
    end
end

DDingUI.CustomIconCooldownWatcher.Attach(
    runtime,
    ScheduleCustomIconWork,
    UpdateAllIcons,
    SafeNumber,
    GetDynamicDB
)

-- ------------------------
-- Group layout
-- ------------------------
local GetGroupSettings, GetGroupDisplayName, EnsureGroupFrame
GetGroupSettings,
    GetGroupDisplayName,
    EnsureGroupFrame,
    RefreshAllLayouts = DDingUI.CustomIconDynamicLayout.Create(
        runtime,
        CustomIcons,
        L,
        ApplyIconSettings,
        BuildDefaultSettings,
        BuildDefaultUngroupedPositionSettings,
        NormalizeAnchor,
        GetStartAnchorForGrowth,
        GetDefaultRowGrowth,
        NormalizeRowGrowth,
        GetStartAnchorForGrowthPair,
        GetDynamicDB,
        GetAnchorFrame,
        ShouldIconSpawn,
        IsIconLoadable,
        EnsureLoadConditions,
        CreateDynamicIcon,
        ReleaseDynamicIconFrame,
        ScheduleCustomIconWork,
        UpdateAllIcons,
        EnsureEventFrame,
        SetCustomIconEventsEnabled
    )

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
    EnsureEventFrame()

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
    if DDingUI.CustomIconActiveEffectOverlay then
        DDingUI.CustomIconActiveEffectOverlay:ClearIcon(iconKey)
    end
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
    if not next(db.iconData) then
        SetCustomIconEventsEnabled(false)
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
    if not next(db.iconData) then
        SetCustomIconEventsEnabled(false)
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
