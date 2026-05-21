local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local canaccessvalue = canaccessvalue or function() return true end

DDingUI.CustomIcons = DDingUI.CustomIcons or {}
local CustomIcons = DDingUI.CustomIcons

-- Lazy-loaded GUI components (DDingUI.GUI is exported after this file loads)
local Widgets, THEME
local CreateCustomScrollBar, GetSafeScrollRange, PropagateMouseWheelRecursive
local CreateStyledButton, CreateStyledToggle, CreateStyledInput, CreateStyledDropdown -- [REFACTOR] GUI.lua에서 로드
local CreateBackdrop -- [REFACTOR] GUI.lua에서 로드
local function EnsureGUILoaded()
    if not Widgets and DDingUI.GUI then
        Widgets = DDingUI.GUI.Widgets
        THEME = DDingUI.GUI.THEME
        CreateCustomScrollBar = DDingUI.GUI.CreateCustomScrollBar
        GetSafeScrollRange = DDingUI.GUI.GetSafeScrollRange
        PropagateMouseWheelRecursive = DDingUI.GUI.PropagateMouseWheelRecursive
        CreateStyledButton = DDingUI.GUI.CreateStyledButton -- [REFACTOR]
        CreateStyledToggle = DDingUI.GUI.CreateStyledToggle -- [REFACTOR]
        CreateStyledInput = DDingUI.GUI.CreateStyledInput -- [REFACTOR]
        CreateStyledDropdown = DDingUI.GUI.CreateStyledDropdown -- [REFACTOR]
        CreateBackdrop = DDingUI.GUI.CreateBackdrop -- [REFACTOR]
    end
    return Widgets and THEME
end

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
local uiState

local SPEC_LIST = {
    {id=62, name="Arcane", classID=8, icon=135932},
    {id=63, name="Fire", classID=8, icon=135810},
    {id=64, name="Frost", classID=8, icon=135846},
    {id=65, name="Holy", classID=2, icon=135920},
    {id=66, name="Protection", classID=2, icon=236264},
    {id=70, name="Retribution", classID=2, icon=135873},
    {id=71, name="Arms", classID=1, icon=132355},
    {id=72, name="Fury", classID=1, icon=132347},
    {id=73, name="Protection", classID=1, icon=132341},
    {id=102, name="Balance", classID=11, icon=136096},
    {id=103, name="Feral", classID=11, icon=132115},
    {id=104, name="Guardian", classID=11, icon=132276},
    {id=105, name="Restoration", classID=11, icon=136041},
    {id=250, name="Blood", classID=6, icon=135770},
    {id=251, name="Frost", classID=6, icon=135773},
    {id=252, name="Unholy", classID=6, icon=135775},
    {id=253, name="Beast Mastery", classID=3, icon=461112},
    {id=254, name="Marksmanship", classID=3, icon=236179},
    {id=255, name="Survival", classID=3, icon=461113},
    {id=256, name="Discipline", classID=5, icon=135940},
    {id=257, name="Holy", classID=5, icon=237542},
    {id=258, name="Shadow", classID=5, icon=136207},
    {id=259, name="Assassination", classID=4, icon=236270},
    {id=260, name="Outlaw", classID=4, icon=236286},
    {id=261, name="Subtlety", classID=4, icon=132320},
    {id=262, name="Elemental", classID=7, icon=136048},
    {id=263, name="Enhancement", classID=7, icon=237581},
    {id=264, name="Restoration", classID=7, icon=136052},
    {id=265, name="Affliction", classID=9, icon=136145},
    {id=266, name="Demonology", classID=9, icon=136172},
    {id=267, name="Destruction", classID=9, icon=136186},
    {id=268, name="Brewmaster", classID=10, icon=608951},
    {id=269, name="Windwalker", classID=10, icon=608953},
    {id=270, name="Mistweaver", classID=10, icon=608952},
    {id=577, name="Havoc", classID=12, icon=1247264},
    {id=581, name="Vengeance", classID=12, icon=1247265},
    {id=1480, name="Devourer", classID=12, icon=7455385},
    {id=1467, name="Devastation", classID=13, icon=4511811},
    {id=1468, name="Preservation", classID=13, icon=4511812},
    {id=1473, name="Augmentation", classID=13, icon=5198700},
}

-- [RACIALS] 종족 특성 매핑 (자동 감지용)
local RACIAL_SPELLS = {
    Orc         = { 20572, 33697, 33702 }, -- Blood Fury
    Tauren      = { 20549 }, -- War Stomp
    NightElf    = { 58984 }, -- Shadowmeld
    Human       = { 59752 }, -- Will to Survive
    Dwarf       = { 20594 }, -- Stoneform
    Scourge     = { 7744 },  -- Will of the Forsaken
    Troll       = { 26297 }, -- Berserking
    BloodElf    = { 202719, 50613, 25046, 69179, 80483, 155145, 129597, 232633, 28730 }, -- Arcane Torrent variants
    Gnome       = { 20589 }, -- Escape Artist
    Draenei     = { 28880 }, -- Gift of the Naaru
    Worgen      = { 68992 }, -- Darkflight
    Goblin      = { 69070 }, -- Rocket Jump
    Pandaren    = { 107079 }, -- Quaking Palm
    VoidElf     = { 256948 }, -- Spatial Rift
    LightforgedDraenei = { 255647 }, -- Light's Judgment
    DarkIronDwarf  = { 265221 }, -- Fireblood
    KulTiran    = { 287712 }, -- Haymaker
    Mechagnome  = { 312924 }, -- Hyper Organic Light Originator
    Nightborne  = { 260364 }, -- Arcane Pulse
    HighmountainTauren = { 255654 }, -- Bull Rush
    MagharOrc   = { 274738 }, -- Ancestral Call
    ZandalariTroll = { 291944 }, -- Regeneratin'
    Vulpera     = { 312411 }, -- Bag of Tricks
    Dracthyr    = { 357214, 368970 }, -- Wing Buffet, Tail Swipe
    EarthenDwarf = { 436344 },
    Haranir     = { 1287685 },
}

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

function CustomIcons:GetPlayerRacialSpellID()
    local _, raceKey = UnitRace("player")
    local raceFile = (raceKey or ""):gsub("%s", ""):gsub("^%l", string.upper)
    local spellList = RACIAL_SPELLS[raceFile]

    if type(spellList) == "table" then
        for _, spellID in ipairs(spellList) do
            if IsSpellInPlayerBook(spellID) then
                return spellID
            end
        end
        return spellList[1] -- fallback
    end
    return spellList
end

local function GetPlayerRacialSpellID()
    return CustomIcons:GetPlayerRacialSpellID()
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
    timedAuraDebug = {
        bloodlust = {},
        timespiral = {},
    },
}

-- UI state containers
local uiFrames = {
    listParent = nil,
    configParent = nil,
    searchBox = nil,
    resultText = nil,
    createFrame = nil,
    loadWindow = nil,
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
    profile.dynamicIcons = profile.dynamicIcons or {}
    local db = profile.dynamicIcons

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
local ITEM_COOLDOWN_MIN_SECONDS = 1.6
local ITEM_COMBAT_LOCKOUT_ITEMS = {
    [5512] = true,
    [224464] = true,
}
local ITEM_COMBAT_LOCKOUT_SPELLS = {
    [6262] = true,
    [452930] = true,
}
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local QUESTION_MARK_TEXTURE = 134400
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
    return texture == QUESTION_MARK_TEXTURE or texture == QUESTION_MARK_ICON or texture == 0 or texture == ""
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
local BLOODLUST_DEBUFF_DURATION_SECONDS = 600
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
local TIMED_AURA_DEBUG_KEYS = {
    [2825] = "bloodlust",
    [374968] = "timespiral",
}
local AURA_EQUIVALENT_IDS = {}
for _, spellID in ipairs(BLOODLUST_AURA_IDS) do
    AURA_EQUIVALENT_IDS[spellID] = BLOODLUST_AURA_IDS
end

local function GetTimedAuraDebugKey(spellIDOrKey)
    if type(spellIDOrKey) == "string" then
        return spellIDOrKey
    end
    return TIMED_AURA_DEBUG_KEYS[tonumber(spellIDOrKey)]
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
        local itemID = iconData.slotID and GetInventoryItemID("player", iconData.slotID)
        texture = ResolveItemTexture(itemID, iconData.slotID)
    elseif iconData.type == "racial" then
        texture = FALLBACK_RACIAL_ICON
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

NormalizePresetIconDB = function(db)
    local iconDataDB = db and db.iconData
    if type(iconDataDB) ~= "table" then return false end

    local changed = false
    for _, iconData in pairs(iconDataDB) do
        if NormalizePresetIconData(iconData) then
            changed = true
        end
    end

    db.groups = type(db.groups) == "table" and db.groups or {}
    db.ungrouped = type(db.ungrouped) == "table" and db.ungrouped or {}
    db.ungroupedPositions = type(db.ungroupedPositions) == "table" and db.ungroupedPositions or {}

    local profile = DDingUI.db and DDingUI.db.profile
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
        local frame = runtime.iconFrames and runtime.iconFrames[iconKey]
        if frame and frame.Hide then
            frame:Hide()
        end
        if runtime.iconFrames then
            runtime.iconFrames[iconKey] = nil
        end
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

    local stateID = spellID
    if AURA_EQUIVALENT_IDS[spellID] then
        stateID = 2825
    end

    local preset = CUSTOM_TIMED_AURA_CONFIGS[stateID]
    local settings = iconData.settings or {}
    local duration = tonumber(settings.customAuraDuration or (preset and preset.duration))
    if not duration or duration <= 0 then return nil end

    return {
        stateID = stateID,
        duration = duration,
        trigger = settings.customAuraTrigger or (preset and preset.trigger) or "spellcast",
        iconTexture = GetStoredIconTexture(iconData) or ResolveSpellTexture(spellID),
    }
end

local function IsEventDrivenCustomTimedAuraConfig(config)
    if not config then return false end
    return config.trigger == "bloodlust" or config.trigger == "timespiral"
end

local function BuildTimedAuraData(spellID, state)
    return {
        spellId = spellID,
        duration = state.duration,
        expirationTime = state.expirationTime,
        applications = 0,
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
            UpdateAllIcons("force")
        end
    end)
end

local MarkCustomTimedAuraExpired
local MarkCustomTimedAuraActive

local function NotifyCustomTimedAuraChanged(forceLayout)
    local mode = forceLayout or "force"
    if UpdateAllIcons then
        UpdateAllIcons(mode)
    end
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        DDingUI.DynamicIconBridge:NotifyIconsChanged(mode == true or mode == "force")
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

local function DeactivateCustomTimedAura(spellID)
    if not runtime.customTimedAuras[spellID] then return false end
    runtime.customTimedAuras[spellID] = nil
    if MarkCustomTimedAuraExpired then
        MarkCustomTimedAuraExpired(spellID)
    end
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
            frame._ddLastDynamicActiveAt = nil
            frame._wasVisibleInGroup = nil
            frame._auraWasActive = false
            if frame.cooldown then
                if frame.cooldown.SetScript then
                    pcall(frame.cooldown.SetScript, frame.cooldown, "OnCooldownDone", nil)
                end
                if frame.cooldown.Clear then
                    pcall(frame.cooldown.Clear, frame.cooldown)
                end
                if frame.cooldown.Hide then
                    pcall(frame.cooldown.Hide, frame.cooldown)
                end
            end
            if frame.count then
                pcall(frame.count.Hide, frame.count)
            end
            if frame._ddIsManaged then
                frame._ddManagedAuraExpired = true
            elseif frame.Hide then
                frame:Hide()
            end
        end
    end
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
                if state and state.iconTexture then
                    SetStableIconTexture(frame, state.iconTexture, true)
                end
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

local function ActivateCustomTimedAura(spellID, config, startTime, iconSpellID)
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

    local token = {}
    local state = {
        startTime = started,
        duration = duration,
        expirationTime = expirationTime,
        token = token,
        iconTexture = iconTexture,
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
                UpdateAllIcons(true)
            end
            if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
                DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
            end
        end
    end)

    return state, changed
end

local function ActivateBloodlustTimedAuraFromAura(aura, iconSpellID, requireWithinWindow)
    local config = CUSTOM_TIMED_AURA_CONFIGS[2825]
    if not config then return false end

    local now = GetTime()
    local active = runtime.customTimedAuras[2825]
    if active and active.expirationTime and active.expirationTime > now then
        local textureChanged = false
        local displaySpellID = tonumber(iconSpellID)
        local iconTexture
        if displaySpellID and displaySpellID ~= 2825 then
            iconTexture = CustomIcons.ResolveCustomTimedAuraStateTexture(2825, config, displaySpellID)
        elseif not active.iconTexture then
            iconTexture = CustomIcons.ResolveCustomTimedAuraStateTexture(2825, config, displaySpellID or 2825)
        end
        if iconTexture and active.iconTexture ~= iconTexture then
            active.iconTexture = iconTexture
            textureChanged = true
        end
        local matchedFrame, hasMatchingIcon, needsLayout
        if MarkCustomTimedAuraActive then
            matchedFrame, hasMatchingIcon, needsLayout = MarkCustomTimedAuraActive(2825, active)
        end
        if needsLayout or textureChanged then
            RecordCustomTimedAuraLink(2825, matchedFrame, hasMatchingIcon)
            NotifyCustomTimedAuraChanged("force")
            if hasMatchingIcon and not matchedFrame and CustomIcons and CustomIcons.LoadDynamicIcons then
                C_Timer.After(0, function()
                    if CustomIcons and CustomIcons.LoadDynamicIcons then
                        CustomIcons:LoadDynamicIcons()
                    end
                    if MarkCustomTimedAuraActive then
                        MarkCustomTimedAuraActive(2825, active)
                    end
                    NotifyCustomTimedAuraChanged("force")
                end)
            end
        end
        bloodlustDebuffInstanceID = GetAuraFieldSafe(aura, "auraInstanceID") or bloodlustDebuffInstanceID
        RecordTimedAuraDebug(2825, "alreadyActive", "debuff")
        return needsLayout or textureChanged
    end

    local auraInstanceID = GetAuraFieldSafe(aura, "auraInstanceID")
    local expirationTime = GetAuraNumberFieldSafe(aura, "expirationTime")
    local duration = GetAuraNumberFieldSafe(aura, "duration")

    if not auraInstanceID or not expirationTime then
        RecordTimedAuraDebug(2825, "debuffSkipped", "missing-instance-or-expiration")
        return false
    end
    if not duration or duration <= 0 then
        duration = BLOODLUST_DEBUFF_DURATION_SECONDS
    end

    local appliedTime = expirationTime - duration
    if requireWithinWindow and (now - appliedTime) >= config.duration then
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

    if not changed then
        changed = SeedBloodlustTimedAura(true)
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

local function AdoptCustomTimedAuraFromAura(iconFrame, iconData, auraData, fallbackSpellID)
    local config = GetCustomTimedAuraConfig(iconData)
    local expirationTime = auraData and SafeNumber(auraData.expirationTime)
    if not config or not expirationTime then return nil end

    local now = GetTime()
    if expirationTime <= now then return nil end

    local duration = SafeNumber(auraData.duration) or tonumber(config.duration) or 0
    if duration <= 0 then
        duration = tonumber(config.duration) or 0
    end
    if duration <= 0 then return nil end

    local auraSpellID = GetAuraSpellIDSafe(auraData) or tonumber(fallbackSpellID) or config.stateID
    local startTime = expirationTime - duration
    local state = ActivateCustomTimedAura(config.stateID, config, startTime, auraSpellID)
    if state and iconFrame then
        iconFrame._ddTimedAuraActiveUntil = state.expirationTime
        iconFrame._cachedAuraSpellID = auraSpellID
    end
    return state
end

local function ResolvePlayerAuraForIcon(iconFrame, iconData)
    if not iconData or iconData.type ~= "aura" or not iconData.id then return nil end

    local timedConfig = GetCustomTimedAuraConfig(iconData)
    local timedAura = timedConfig and GetActiveCustomTimedAura(iconData)
    if timedAura then
        if iconFrame then
            iconFrame._ddTimedAuraActiveUntil = timedAura.expirationTime
            iconFrame._cachedAuraSpellID = GetAuraSpellIDSafe(timedAura) or timedAura.spellId or iconData.id
        end
        return timedAura
    elseif iconFrame then
        local activeUntil = SafeNumber(iconFrame._ddTimedAuraActiveUntil)
        local now = GetTime and GetTime() or 0
        if not (InCombatLockdown and InCombatLockdown() and activeUntil and activeUntil > now) then
            iconFrame._ddTimedAuraActiveUntil = nil
        end
    end

    if IsEventDrivenCustomTimedAuraConfig(timedConfig) then
        if iconFrame then
            iconFrame._ddTimedAuraActiveUntil = nil
            iconFrame._ddAuraActiveUntil = nil
            iconFrame._auraWasActive = false
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
                local expirationTime = SafeNumber(auraData.expirationTime)
                if expirationTime and expirationTime > 0 then
                    iconFrame._ddAuraActiveUntil = expirationTime
                end
            end
            AdoptCustomTimedAuraFromAura(iconFrame, iconData, auraData, spellID)
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
                if aura and aura.name and nameSet[aura.name] then
                    auraData = aura
                    local auraSpellID = GetAuraSpellIDSafe(aura)
                    if iconFrame and auraSpellID then
                        iconFrame._cachedAuraSpellID = auraSpellID
                        local expirationTime = SafeNumber(aura.expirationTime)
                        if expirationTime and expirationTime > 0 then
                            iconFrame._ddAuraActiveUntil = expirationTime
                        end
                    end
                    return true
                end
            end)
        end)
        if auraData then
            AdoptCustomTimedAuraFromAura(iconFrame, iconData, auraData, GetAuraSpellIDSafe(auraData))
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

local function StoreCooldownSpan(iconFrame, prefix, start, duration)
    if not iconFrame or not prefix or not start or not duration then return end
    iconFrame[prefix .. "Start"] = start
    iconFrame[prefix .. "Duration"] = duration
    iconFrame[prefix .. "Until"] = start + duration
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

local function GetStoredCooldownSpan(iconFrame, prefix)
    if not iconFrame or not prefix then return nil, nil end

    local expiresAt = SafeNumber(iconFrame[prefix .. "Until"])
    local now = GetTime and GetTime() or 0
    if expiresAt and expiresAt > now then
        return iconFrame[prefix .. "Start"], iconFrame[prefix .. "Duration"]
    end

    ClearCooldownSpan(iconFrame, prefix)
    return nil, nil
end

local function GetRealSpellCooldownDuration(spellID)
    if not spellID or not C_Spell then return nil, false end

    local isRealCooldown = false
    if C_Spell.GetSpellCooldown then
        pcall(function()
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.isActive and cdInfo.isOnGCD ~= true then
                isRealCooldown = true
            end
        end)
    end

    if not isRealCooldown then return nil, false end
    if C_Spell.GetSpellCooldownDuration then
        return C_Spell.GetSpellCooldownDuration(spellID), true
    end
    return nil, false
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
    if not IsCooldownEnabled(enable) then return nil, nil, false end

    local safeStart = SafeNumber(start)
    local safeDuration = SafeNumber(duration)
    if safeStart and safeDuration then
        if safeDuration > ITEM_COOLDOWN_MIN_SECONDS then
            return safeStart, safeDuration, true
        end
        return nil, nil, false
    end

    -- In combat, item cooldown APIs can return protected numeric values.
    -- Cooldown:SetCooldown can consume those directly, so keep the raw span.
    if start ~= nil and duration ~= nil then
        return start, duration, false
    end
    return nil, nil, false
end

local function ReadInventoryCooldownSpan(slotID)
    if not slotID or not GetInventoryItemCooldown then return nil, nil, false end

    local start, duration, enable
    pcall(function()
        start, duration, enable = GetInventoryItemCooldown("player", slotID)
    end)
    return NormalizeCooldownSpan(start, duration, enable)
end

local function ReadItemCooldownSpan(itemID)
    if not itemID then return nil, nil, false end

    local function readWith(getter)
        local start, duration, enable
        pcall(function()
            start, duration, enable = getter(itemID)
        end)
        return NormalizeCooldownSpan(start, duration, enable)
    end

    if C_Container and C_Container.GetItemCooldown then
        local start, duration, safeSpan = readWith(C_Container.GetItemCooldown)
        if start then return start, duration, safeSpan end
    end
    if C_Item and C_Item.GetItemCooldown then
        local start, duration, safeSpan = readWith(C_Item.GetItemCooldown)
        if start then return start, duration, safeSpan end
    end
    if GetItemCooldown then
        local start, duration, safeSpan = readWith(GetItemCooldown)
        if start then return start, duration, safeSpan end
    end
    return nil, nil, false
end

local function ResolveItemCooldownSpan(iconFrame, prefix, itemID, slotID)
    local start, duration, safeSpan = ReadInventoryCooldownSpan(slotID)
    if not start then
        start, duration, safeSpan = ReadItemCooldownSpan(itemID)
    end
    if start and duration then
        if safeSpan then
            StoreCooldownSpan(iconFrame, prefix, start, duration)
        end
        return start, duration, true, safeSpan
    end

    start, duration = GetStoredCooldownSpan(iconFrame, prefix)
    if start and duration then
        return start, duration, true, true
    end

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

    if safeSpan ~= false and C_DurationUtil and C_DurationUtil.CreateDuration then
        if not iconFrame[durObjKey] then
            iconFrame[durObjKey] = C_DurationUtil.CreateDuration()
        end
        iconFrame[durObjKey]:SetTimeFromStart(start, duration)
        iconFrame.cooldown:SetCooldownFromDurationObject(iconFrame[durObjKey])
        return true
    end

    local ok = pcall(iconFrame.cooldown.SetCooldown, iconFrame.cooldown, start, duration)
    return ok == true
end

local function UpdateItemIcon(iconFrame, iconData)
    local itemID = iconData.id
    if not itemID or not iconFrame then return end

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

    -- [CDM 패턴] 아이템 쿨다운 (GetItemCooldown 최우선 -> GetSpellCooldownDuration 폴백)
    local itemSpellID = ResolveUsableItemSpellID(iconFrame, activeItemID, settings)
    EnsureCooldownSpanOwner(iconFrame, "_ddItemCooldown", activeItemID)

    local desatDurationObject = nil
    local desatSpellID = nil
    local itemCooldownActive = false
    local itemCombatLocked = IsItemCombatLocked(activeItemID)
    -- GetItemCooldown can briefly return 0 in combat; keep a cached valid span as fallback.
    if itemSpellID then
        -- 스펠 ID가 매핑된 아이템: CDM의 최우선 ItemCD 시도, 실패시 SpellDur 사용
        local realDur = nil
        if C_Spell and C_Spell.GetSpellCooldownDuration then
            realDur = C_Spell.GetSpellCooldownDuration(itemSpellID)
        end

        local itemCdStart, itemCdDuration, hasItemCooldown, itemCdSafe =
            ResolveItemCooldownSpan(iconFrame, "_ddItemCooldown", activeItemID)

        desatDurationObject = realDur
        desatSpellID = itemSpellID

        if hasItemCooldown then
            if ApplyCooldownSpan(iconFrame, "_itemDurObj", itemCdStart, itemCdDuration, itemCdSafe) then
                itemCooldownActive = true
            else
                iconFrame.cooldown:Clear()
            end
        elseif realDur then
            iconFrame.cooldown:SetCooldownFromDurationObject(realDur)
        else
            iconFrame.cooldown:Clear()
        end
    else
        -- [Fallback] 스펠 ID 없는 아이템 (비전투/제한적 작동)
        local itemCdStart, itemCdDuration, hasItemCooldown, itemCdSafe =
            ResolveItemCooldownSpan(iconFrame, "_ddItemCooldown", activeItemID)

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
    if iconData.settings and iconData.settings.showCooldown == false then
        iconFrame.cooldown:Hide()
    else
        iconFrame.cooldown:Show()
    end

    -- 아이템 카운트 표시
    if iconFrame.count then
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

    iconFrame.icon:SetDesaturated(false)
    iconFrame.icon:SetDesaturation(desatVal)

    -- OnUpdate 루프: isOnRealCD (safe boolean)으로만 진입 판단 — desatVal 비교 금지
    if itemCombatLocked then
        if iconFrame._cdmDesatUpdater then
            iconFrame._cdmDesatUpdater:Hide()
        end
    elseif itemIsOnRealCD then
        if not iconFrame._cdmDesatUpdater then
            iconFrame._cdmDesatUpdater = CreateFrame("Frame", nil, iconFrame)
            iconFrame._cdmDesatUpdater:SetScript("OnUpdate", function(self)
                local stillOnRealCD = false
                pcall(function()
                    local cdInfo = C_Spell.GetSpellCooldown(self.spellID)
                    if cdInfo and cdInfo.isActive and cdInfo.isOnGCD ~= true then
                        stillOnRealCD = true
                    end
                end)
                if stillOnRealCD and self.durObj then
                    self.targetIcon:SetDesaturation(EvalDesatFromDurObj(self.durObj, false))
                else
                    self.targetIcon:SetDesaturation(0)
                    self:Hide()
                end
            end)
        end
        iconFrame._cdmDesatUpdater.spellID = desatSpellID
        iconFrame._cdmDesatUpdater.durObj = desatDurationObject
        iconFrame._cdmDesatUpdater.targetIcon = iconFrame.icon
        iconFrame._cdmDesatUpdater:Show()
    elseif iconFrame._cdmDesatUpdater then
        iconFrame._cdmDesatUpdater:Hide()
    end

    iconFrame.icon:SetAlpha(1.0)
    iconFrame.icon:SetAlpha(1.0)
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

    -- 충전 카운트 표시
    local charges = isChargeSpell and chargeInfo.currentCharges
    local hasChargesText = false
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

    -- [FIX CDM] Swipe/Edge 스타일 (변경 없음)
    if not (iconData.settings and iconData.settings.showCooldown == false) then
        if isChargeSpell then
            pcall(iconFrame.cooldown.SetSwipeColor, iconFrame.cooldown, 0, 0, 0, 0)
            pcall(iconFrame.cooldown.SetDrawEdge, iconFrame.cooldown, cooldownSet)
            if iconFrame.cooldown.SetDrawSwipe then
                pcall(iconFrame.cooldown.SetDrawSwipe, iconFrame.cooldown, true)
            end
        else
            pcall(iconFrame.cooldown.SetSwipeColor, iconFrame.cooldown, 0, 0, 0, 0.8)
            pcall(iconFrame.cooldown.SetDrawEdge, iconFrame.cooldown, false)
            if iconFrame.cooldown.SetDrawSwipe then
                pcall(iconFrame.cooldown.SetDrawSwipe, iconFrame.cooldown, true)
            end
        end
    else
        pcall(iconFrame.cooldown.SetDrawEdge, iconFrame.cooldown, false)
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
    iconFrame.icon:SetDesaturation(desatValue)

    -- OnUpdate 루프: isOnRealCD (safe boolean)만으로 진입 결정 — desatValue 비교 금지
    if usable and allowDesat and desatDurObj and isOnRealCD then
        if not iconFrame._cdmDesatUpdater then
            iconFrame._cdmDesatUpdater = CreateFrame("Frame", nil, iconFrame)
            iconFrame._cdmDesatUpdater:SetScript("OnUpdate", function(self)
                local stillOnRealCD = false
                pcall(function()
                    local cdInfo = C_Spell.GetSpellCooldown(self.spellID)
                    if cdInfo and cdInfo.isActive and cdInfo.isOnGCD ~= true then
                        stillOnRealCD = true
                    end
                end)
                if stillOnRealCD and self.durObj then
                    self.targetIcon:SetDesaturation(EvalDesatFromDurObj(self.durObj, false))
                else
                    self.targetIcon:SetDesaturation(0)
                    self:Hide()
                end
            end)
        end
        iconFrame._cdmDesatUpdater.spellID = spellID
        iconFrame._cdmDesatUpdater.durObj = desatDurObj
        iconFrame._cdmDesatUpdater.targetIcon = iconFrame.icon
        iconFrame._cdmDesatUpdater:Show()
    elseif iconFrame._cdmDesatUpdater then
        iconFrame._cdmDesatUpdater:Hide()
    end

    iconFrame.icon:SetAlpha(1.0)
end

local function UpdateSlotIcon(iconFrame, iconData)
    local slotID = iconData.slotID
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID then
        SetStableIconTexture(iconFrame, nil, not iconFrame._ddIsManaged)
        iconFrame.cooldown:Clear()
        iconFrame.count:Hide()
        return
    end

    iconFrame._textureCacheKey = "slot:" .. tostring(slotID)
    SetStableIconTexture(iconFrame, ResolveItemTexture(itemID, slotID), true)
    EnsureCooldownSpanOwner(iconFrame, "_ddSlotCooldown", itemID)

    -- [CDM 패턴] enable == 1 + canaccessvalue + C_DurationUtil
    local start, duration, hasCooldown, safeSpan = ResolveItemCooldownSpan(iconFrame, "_ddSlotCooldown", itemID, slotID)
    local itemSpellID = ResolveUsableItemSpellID(iconFrame, itemID, iconData.settings)
    local spellDurObj = itemSpellID and GetRealSpellCooldownDuration(itemSpellID)

    local onCooldown = false
    pcall(function()
        if start and duration and hasCooldown then
            onCooldown = ApplyCooldownSpan(iconFrame, "_slotDurObj", start, duration, safeSpan)
            if not onCooldown then iconFrame.cooldown:Clear() end
            return
        end
        if start and duration and hasCooldown then
            if type(duration) == "number" and not canaccessvalue(duration) then
                -- secret value: 쿨다운 중이지만 수치 불명 → 탈색만 적용
                onCooldown = true
                iconFrame.cooldown:Clear()
            elseif type(duration) == "number" and duration > 1.5 then
                onCooldown = true
                if not iconFrame._slotDurObj then
                    iconFrame._slotDurObj = C_DurationUtil.CreateDuration()
                end
                iconFrame._slotDurObj:SetTimeFromStart(start, duration)
                StoreCooldownSpan(iconFrame, "_ddSlotCooldown", start, duration)
                iconFrame.cooldown:SetCooldownFromDurationObject(iconFrame._slotDurObj)
            else
                iconFrame.cooldown:Clear()
            end
        else
            iconFrame.cooldown:Clear()
        end
    end)
    if not onCooldown and spellDurObj then
        iconFrame.cooldown:SetCooldownFromDurationObject(spellDurObj)
        onCooldown = true
    end

    if iconData.settings and iconData.settings.showCooldown == false then
        iconFrame.cooldown:Hide()
    else
        if onCooldown then
            iconFrame.cooldown:Show()
        else
            iconFrame.cooldown:Hide()
        end
    end

    local allowDesat = not (iconData.settings and iconData.settings.desaturateOnCooldown == false)
    iconFrame.icon:SetDesaturation(allowDesat and onCooldown and 1 or 0)
end

local function ResolveTrinketProcAuraForIcon(iconFrame, iconData)
    if not iconData then return nil end

    local slotID = iconData.slotID
    if not slotID then return nil end

    local itemID = GetInventoryItemID("player", slotID)
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
                    if a and a.name == spellInfo.name then
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
            local duration = SafeNumber(auraData.duration)
            iconFrame._ddProcActiveUntil = SafeNumber(auraData.expirationTime)
                or (duration and (now + duration))
                or (now + 0.75)
        end
    end
    return auraData, procSpellID, itemID
end

local function UpdateTrinketProcIcon(iconFrame, iconData)
    local slotID = iconData.slotID
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID then
        SetStableIconTexture(iconFrame, nil, not iconFrame._ddIsManaged)
        iconFrame.cooldown:Clear()
        iconFrame.count:Hide()
        return
    end

    iconFrame._textureCacheKey = "trinketProc:" .. tostring(slotID)
    -- Update trinket item texture
    SetStableIconTexture(iconFrame, ResolveItemTexture(itemID, slotID), true)
    EnsureCooldownSpanOwner(iconFrame, "_ddTrinketCooldown", itemID)

    -- Determine proc spell ID (auto-detect or manual override)
    local settings = iconData.settings or {}
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
                        if a and a.name == spellInfo.name then
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
        procActive = true
        local now = GetTime and GetTime() or 0
        iconFrame._ddLastProcActiveAt = now
        local auraDuration = SafeNumber(auraData.duration)
        local auraExpiration = SafeNumber(auraData.expirationTime)
        iconFrame._ddProcActiveUntil = auraExpiration
            or (auraDuration and (now + auraDuration))
            or (now + 0.75)

        -- [Visuals: Active Buff]
        iconFrame.cooldown:SetReverse(true)

        -- 프록 버프 지속시간
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

        -- [FIX] 글로우를 아이콘 외부로 확장하여 스와이프와 겹치지 않는 테두리로 사용
        -- 스와이프는 아이콘 내부에만 그려지므로, 외곽으로 벗어난 글로우는 항상 보임
        -- xOffset/yOffset으로 아이콘 경계 밖 8px 추가 확장
        local LCG = LibStub("LibCustomGlow-1.0", true)
        if LCG and LCG.ProcGlow_Start then
            LCG.ProcGlow_Start(iconFrame, {
                color = {0.95, 0.95, 0.32, 1},
                startAnim = true,
                xOffset = 8,
                yOffset = 8,
            })
        end

        -- 스택 수
        if settings.showProcStacks ~= false then
            local stacks = auraData.applications or 0
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
            -- [CDM 패턴] enable == 1 + canaccessvalue + C_DurationUtil
            local start, duration, hasCooldown, safeSpan = ResolveItemCooldownSpan(iconFrame, "_ddTrinketCooldown", itemID, slotID)
            local itemSpellID = ResolveUsableItemSpellID(iconFrame, itemID, settings)
            local spellDurObj = itemSpellID and GetRealSpellCooldownDuration(itemSpellID)
            local onCooldown = false
            pcall(function()
                if start and duration and hasCooldown then
                    onCooldown = ApplyCooldownSpan(iconFrame, "_trinketDurObj", start, duration, safeSpan)
                    if not onCooldown then iconFrame.cooldown:Clear() end
                    return
                end
                if false then
                    if type(duration) == "number" and not canaccessvalue(duration) then
                        -- secret value: 쿨다운 중이지만 수치 불명 → 탈색만 적용
                        onCooldown = true
                        iconFrame.cooldown:Clear()
                    elseif type(duration) == "number" and duration > 1.5 then
                        onCooldown = true
                        if not iconFrame._trinketDurObj then
                            iconFrame._trinketDurObj = C_DurationUtil.CreateDuration()
                        end
                        iconFrame._trinketDurObj:SetTimeFromStart(start, duration)
                        StoreCooldownSpan(iconFrame, "_ddTrinketCooldown", start, duration)
                        iconFrame.cooldown:SetCooldownFromDurationObject(iconFrame._trinketDurObj)
                    else
                        iconFrame.cooldown:Clear()
                    end
                else
                    iconFrame.cooldown:Clear()
                end
            end)
            if not onCooldown and spellDurObj then
                iconFrame.cooldown:SetCooldownFromDurationObject(spellDurObj)
                onCooldown = true
            end
            if settings.showCooldown ~= false and onCooldown then
                iconFrame.cooldown:Show()
            else
                iconFrame.cooldown:Hide()
            end
            local allowDesat = not (settings.desaturateOnCooldown == false)
            iconFrame.icon:SetDesaturation(allowDesat and onCooldown and 1 or 0)
        else
            iconFrame.cooldown:Clear()
            iconFrame.cooldown:Hide()
            iconFrame.icon:SetDesaturated(false)
        end
        iconFrame.count:Hide()
    end
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
                        if a and a.name == spellInfo.name then
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

    if not auraData and InCombatLockdown and InCombatLockdown() then
        local activeUntil = SafeNumber(iconFrame._ddTimedAuraActiveUntil) or SafeNumber(iconFrame._ddAuraActiveUntil)
        local now = GetTime and GetTime() or 0
        if activeUntil and activeUntil > now then
            iconFrame._auraWasActive = true
            CustomIcons.ApplyManagedGroupTextOptions(iconFrame)
            return
        end
        if HasRecentEffectState(iconFrame, now) then
            iconFrame._auraWasActive = false
            ScheduleEffectGraceUpdate(iconFrame)
            CustomIcons.ApplyManagedGroupTextOptions(iconFrame)
            return
        end
    end

    local auraExpirationTime = auraData and SafeNumber(auraData.expirationTime)
    if auraExpirationTime and auraExpirationTime > 0 then
        iconFrame._ddAuraActiveUntil = auraExpirationTime
    elseif not auraData then
        iconFrame._ddAuraActiveUntil = nil
    end

    local activeTexture = auraData and (auraData.icon or auraData.iconID)
    if activeTexture then
        SetStableIconTexture(iconFrame, activeTexture, true)
    end

    local isActive = (auraData ~= nil)
    local wasActive = iconFrame._auraWasActive

    if isActive ~= wasActive then
        iconFrame._auraWasActive = isActive
    end

    if auraData then
        -- [FIX] 버프 스와이프 방향: fill-up (CDM 패턴)
        iconFrame.cooldown:SetReverse(true)

        -- 활성: duration 쿨다운 + 스택 표시
        pcall(function()
            local auraDuration = SafeNumber(auraData.duration)
            local auraExpiration = SafeNumber(auraData.expirationTime)
            if auraDuration and auraDuration > 0 and auraExpiration then
                local startTime = auraExpiration - auraDuration
                iconFrame.cooldown:SetCooldown(startTime, auraDuration)
            else
                iconFrame.cooldown:Clear()
            end
        end)
        if settings.showCooldown ~= false then
            iconFrame.cooldown:Show()
        else
            iconFrame.cooldown:Hide()
        end

        local stacks = auraData.applications or 0
        if stacks > 1 and settings.showCharges ~= false then
            pcall(iconFrame.count.SetText, iconFrame.count, stacks)
            iconFrame.count:Show()
        else
            iconFrame.count:Hide()
        end

        iconFrame.icon:SetDesaturated(false)
        iconFrame.icon:SetAlpha(1.0)
        -- [FIX] managed 프레임은 GroupRenderer가 Show/Hide 관리
        if not iconFrame._ddIsManaged then
            iconFrame:Show()
        end
    else
        -- 비활성: 쿨다운 클리어 + 숨김
        iconFrame.cooldown:Clear()
        iconFrame.cooldown:Hide()
        iconFrame.count:Hide()

        if allowDesat then
            iconFrame.icon:SetDesaturated(true)
        else
            iconFrame.icon:SetDesaturated(false)
        end
        iconFrame.icon:SetAlpha(1.0)
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
            if frame then
                seenStateIDs[config.stateID] = true
                frame._ddTimedAuraActiveUntil = state.expirationTime
                frame._ddLastAuraActiveAt = now
                frame._ddLastDynamicActiveAt = now
                frame._wasVisibleInGroup = true
                frame._auraWasActive = true
                frame._ddManagedAuraExpired = nil
                if state.iconTexture then
                    SetStableIconTexture(frame, state.iconTexture, true)
                end
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
-- 호출해도 실제 실행은 다음 프레임에 단 1회만 수행 (C_Timer.After(0) 배치 처리)
local _pendingIconUpdate = false
local _iconUpdateSeq = 0
local _pendingIconLayoutNotify = false

local function GetDynamicLayoutStateToken(frame, iconData)
    if not frame or not iconData then return nil end
    if iconData.type ~= "aura" and iconData.type ~= "trinketProc" then return nil end

    local now = GetTime and GetTime() or 0
    local activeUntil = MaxSafeNumber(frame._ddTimedAuraActiveUntil, frame._ddAuraActiveUntil, frame._ddProcActiveUntil)
    local active = frame._auraWasActive == true
        or frame._trinketProcWasActive == true
        or (activeUntil and activeUntil > now)
        or (InCombatLockdown and InCombatLockdown() and HasRecentEffectState(frame, now))

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

local function ExecuteUpdateAllIcons()
    local layoutStateChanged = false

    local function ReapplyManagedGroupText(frame)
        CustomIcons.ApplyManagedGroupTextOptions(frame)
    end

    for iconKey, frame in pairs(runtime.iconFrames) do
        if frame then
            local db = GetDynamicDB()
            local iconData = db.iconData and db.iconData[iconKey]
            if iconData and (frame:IsVisible() or iconData.type == "aura" or iconData.type == "trinketProc" or frame._ddIsManaged) then
                local beforeLayoutState = GetDynamicLayoutStateToken(frame, iconData)

                if not frame._ddIsManaged then
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
                    UpdateSpellIconFrame(frame, iconData)
                elseif iconData.type == "racial" then
                    local racialID = GetPlayerRacialSpellID()
                    if racialID then
                        UpdateSpellIconFrame(frame, {id = racialID, settings = iconData.settings})
                    end
                elseif iconData.type == "slot" then
                    UpdateSlotIcon(frame, iconData)
                elseif iconData.type == "trinketProc" then
                    UpdateTrinketProcIcon(frame, iconData)
                elseif iconData.type == "aura" then
                    UpdateAuraIcon(frame, iconData)
                end
                ReapplyManagedGroupText(frame)

                local afterLayoutState = GetDynamicLayoutStateToken(frame, iconData)
                if beforeLayoutState and afterLayoutState and beforeLayoutState ~= afterLayoutState then
                    layoutStateChanged = true
                end
            end
        end
    end

    return layoutStateChanged
end

-- [CDM 패턴] 공개 진입점 — 이벤트 핸들러는 이 함수만 호출
-- 같은 틱 내 다수 호출을 1회로 병합, 다음 프레임에 실행
UpdateAllIcons = function(needsLayoutNotify)
    if needsLayoutNotify then
        QueueIconLayoutNotify(needsLayoutNotify)
    end
    if _pendingIconUpdate then return end
    _pendingIconUpdate = true
    _iconUpdateSeq = _iconUpdateSeq + 1
    local capturedSeq = _iconUpdateSeq
    C_Timer.After(0, function()
        if capturedSeq ~= _iconUpdateSeq then return end  -- 더 최신 요청이 있으면 스킵
        _pendingIconUpdate = false
        local notifyLayout = _pendingIconLayoutNotify
        _pendingIconLayoutNotify = false
        local layoutStateChanged = ExecuteUpdateAllIcons()
        if notifyLayout and DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
            local forceLayout = notifyLayout == true or notifyLayout == "force"
            if forceLayout or layoutStateChanged then
                DDingUI.DynamicIconBridge:NotifyIconsChanged(forceLayout)
            end
        end
    end)
end

local function HandleCooldownDone(cooldownFrame)
    local parent = cooldownFrame and cooldownFrame:GetParent()
    local iconKey = parent and parent._iconKey
    if iconKey and runtime.UpdateDynamicIcon then
        runtime.UpdateDynamicIcon(iconKey)
        return
    end
    UpdateAllIcons()
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
            UpdateAllIcons("aura")
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
            UpdateAllIcons()
        end
    end)
    -- Phase 2 (1.5s): CDM 안정화 후 최종 갱신
    C_Timer.After(1.5, function()
        if CustomIcons and CustomIcons.LoadDynamicIcons then
            CustomIcons:LoadDynamicIcons()
        else
            if RefreshAllLayouts then RefreshAllLayouts() end
            UpdateAllIcons()
        end
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
        local itemLocked = MarkItemCombatLockoutFromSpell(spellID)
        local config = CUSTOM_TIMED_AURA_CONFIGS[spellID]
        if config and config.trigger == "spellcast" then
            local _, changed = ActivateCustomTimedAura(spellID, config)
            return changed or itemLocked
        end
        return itemLocked
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

    return false
end

local function HasItemCooldownIcon()
    local db = GetDynamicDB()
    for _, iconData in pairs((db and db.iconData) or {}) do
        if iconData.type == "item" or iconData.type == "slot" or iconData.type == "trinketProc" then
            return true
        end
    end
    return false
end

local function RefreshItemCooldownIcons(needsLayoutNotify)
    UpdateAllIcons(needsLayoutNotify)
    C_Timer.After(0.05, function() UpdateAllIcons(needsLayoutNotify) end)
    C_Timer.After(0.20, function() UpdateAllIcons(needsLayoutNotify) end)
    C_Timer.After(0.50, function() UpdateAllIcons(needsLayoutNotify) end)
    C_Timer.After(1.00, function() UpdateAllIcons(needsLayoutNotify) end)
    C_Timer.After(2.00, function() UpdateAllIcons(needsLayoutNotify) end)
    C_Timer.After(3.00, function() UpdateAllIcons(needsLayoutNotify) end)
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
    runtime.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    runtime.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    runtime.eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    runtime.eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    RebuildTimeSpiralGlowFilters()

    runtime.eventFrame:SetScript("OnEvent", function(self, event, ...)
        local arg1 = ...

        if event == "PLAYER_ENTERING_WORLD" then
            runtime.loginTime = runtime.loginTime or GetTime()
            RebuildTimeSpiralGlowFilters()
            local function seedBloodlust()
                if ScanBloodlustTimedAura({ isFullUpdate = true }) then
                    UpdateAllIcons("force")
                end
            end
            C_Timer.After(0.2, seedBloodlust)
            C_Timer.After(1.0, seedBloodlust)
            -- Force reload layout after loading screen to catch delayed cache/spellbook states
            C_Timer.After(1.0, function() ScheduleSpecReload() end)
            C_Timer.After(3.0, function() ScheduleSpecReload() end)
            return
        end

        if event == "PLAYER_REGEN_ENABLED" then
            ClearItemCombatLockouts()
            RefreshItemCooldownIcons("force")
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
            RebuildTimeSpiralGlowFilters()
            ScheduleSpecReload()
            return
        end

        local customTimedChanged = HandleCustomTimedAuraEvent(event, ...)
        if event == "UNIT_SPELLCAST_SENT" then return end
        if (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
            or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            and not customTimedChanged then
            return
        end
        local hasItemCooldownIcon = (event == "UNIT_SPELLCAST_SUCCEEDED"
            or event == "BAG_UPDATE_COOLDOWN"
            or event == "ITEM_COUNT_CHANGED"
            or event == "BAG_UPDATE_DELAYED")
            and HasItemCooldownIcon()
        if event == "UNIT_SPELLCAST_SUCCEEDED" and not customTimedChanged and not hasItemCooldownIcon then
            return
        end

        -- Update all icons when relevant events fire.
        local needsLayoutNotify = nil
        if customTimedChanged
            or event == "UNIT_INVENTORY_CHANGED"
            or event == "PLAYER_EQUIPMENT_CHANGED"
            or event == "BAG_UPDATE"
            or event == "BAG_UPDATE_DELAYED"
            or event == "ITEM_COUNT_CHANGED"
        then
            needsLayoutNotify = "force"
        elseif event == "UNIT_AURA" then
            needsLayoutNotify = "aura"
        end

        if hasItemCooldownIcon then
            RefreshItemCooldownIcons(needsLayoutNotify)
            return
        end

        UpdateAllIcons(needsLayoutNotify)
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
        return racialID and IsSpellInPlayerBook(racialID)
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
        if not racialID or not IsSpellInPlayerBook(racialID) then return false end
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

function CustomIcons:ShowLoadConditionsWindow(iconKey, iconData)
    EnsureLoadConditions(iconData)
    -- If a window already exists, discard it and rebuild to guarantee fresh bindings
    if uiFrames.loadWindow then
        uiFrames.loadWindow:Hide()
        uiFrames.loadWindow = nil
    end

    local lc = iconData.settings.loadConditions

    local f = CreateFrame("Frame", "DDingUI_LoadConditions", UIParent, "BackdropTemplate")
    f:SetSize(360, 460)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    f:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.95)
    f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
    f.title:SetShadowOffset(1, -1)
    f.title:SetShadowColor(0, 0, 0, 1)
    f.title:SetPoint("TOP", f, "TOP", 0, -10)
    f.title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    f.title:SetText(L["Load Conditions"] or "Load Conditions")

    f.close = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.close:SetSize(24, 24)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f.close:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    f.close:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
    f.close:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
    local closeText = f.close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
    closeText:SetShadowOffset(1, -1)
    closeText:SetShadowColor(0, 0, 0, 1)
    closeText:SetPoint("CENTER", 0, 1)
    closeText:SetText("×")
    closeText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    f.close:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.8, 0.2, 0.2, 1)
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
        closeText:SetTextColor(1, 1, 1, 1)
    end)
    f.close:SetScript("OnLeave", function(self)
        self:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
        self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        closeText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    end)
    f.close:SetScript("OnClick", function() f:Hide() end)

    -- Enable toggle (DDingUI style)
    local enableBtn = CreateFrame("CheckButton", nil, f, "BackdropTemplate")
    enableBtn:SetSize(14, 14)
    enableBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
    enableBtn:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    enableBtn:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
    enableBtn:SetBackdropBorderColor(0, 0, 0, 1)
    local enableCheck = enableBtn:CreateTexture(nil, "OVERLAY")
    enableCheck:SetPoint("TOPLEFT", 1, -1)
    enableCheck:SetPoint("BOTTOMRIGHT", -1, 1)
    enableCheck:SetGradient("HORIZONTAL",
        CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),
        CreateColor(THEME.accentDark[1], THEME.accentDark[2], THEME.accentDark[3], 1))
    enableBtn:SetCheckedTexture(enableCheck)
    local enableHighlight = enableBtn:CreateTexture(nil, "ARTWORK")
    enableHighlight:SetAllPoints()
    enableHighlight:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.1)
    enableBtn:SetHighlightTexture(enableHighlight, "ADD")
    local enableLabel = enableBtn:CreateFontString(nil, "OVERLAY")
    enableLabel:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
    enableLabel:SetShadowOffset(1, -1)
    enableLabel:SetShadowColor(0, 0, 0, 1)
    enableLabel:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
    enableLabel:SetPoint("LEFT", enableBtn, "RIGHT", 6, 0)
    enableLabel:SetText(L["Enable Load Conditions"] or "Enable Load Conditions")
    enableBtn:SetChecked(lc.enabled == true)
    enableBtn:SetScript("OnClick", function(self)
        lc.enabled = self:GetChecked() or false
        if RefreshAllLayouts then RefreshAllLayouts() end
    end)

    -- Specs header
    local specHeader = f:CreateFontString(nil, "OVERLAY")
    specHeader:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 13, "")
    specHeader:SetShadowOffset(1, -1)
    specHeader:SetShadowColor(0, 0, 0, 1)
    specHeader:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    specHeader:SetPoint("TOPLEFT", enableBtn, "BOTTOMLEFT", 4, -12)
    specHeader:SetText(L["By Specialization"] or "By Specialization")

    -- Spec scroll (DDingUI custom scrollbar)
    local specScroll = CreateFrame("ScrollFrame", nil, f)
    specScroll:SetPoint("TOPLEFT", specHeader, "BOTTOMLEFT", -4, -8)
    specScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)

    local specChild = CreateFrame("Frame", nil, specScroll)
    specChild:SetWidth(300)
    specChild:SetHeight(400)
    specScroll:SetScrollChild(specChild)

    if CreateCustomScrollBar then
        local specScrollBar = CreateCustomScrollBar(f, specScroll)
        specScrollBar:SetPoint("TOPLEFT", specScroll, "TOPRIGHT", 4, 0)
        specScrollBar:SetPoint("BOTTOMLEFT", specScroll, "BOTTOMRIGHT", 4, 0)
        specScroll.ScrollBar = specScrollBar
    end

    local y = 0
    lc.specs = lc.specs or {}
    for _, spec in ipairs(SPEC_LIST) do
        local row = CreateFrame("Frame", nil, specChild)
        row:SetSize(280, 26)
        row:SetPoint("TOPLEFT", specChild, "TOPLEFT", 0, -y)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        icon:SetTexture(spec.icon)

        local name = row:CreateFontString(nil, "OVERLAY")
        name:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        name:SetShadowOffset(1, -1)
        name:SetShadowColor(0, 0, 0, 1)
        name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetText(spec.name)

        local toggle = CreateFrame("CheckButton", nil, row, "BackdropTemplate")
        toggle:SetSize(14, 14)
        toggle:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        toggle:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        toggle:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
        toggle:SetBackdropBorderColor(0, 0, 0, 1)
        local toggleCheck = toggle:CreateTexture(nil, "OVERLAY")
        toggleCheck:SetPoint("TOPLEFT", 1, -1)
        toggleCheck:SetPoint("BOTTOMRIGHT", -1, 1)
        toggleCheck:SetGradient("HORIZONTAL",
            CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),
            CreateColor(THEME.accentDark[1], THEME.accentDark[2], THEME.accentDark[3], 1))
        toggle:SetCheckedTexture(toggleCheck)
        local toggleHL = toggle:CreateTexture(nil, "ARTWORK")
        toggleHL:SetAllPoints()
        toggleHL:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.1)
        toggle:SetHighlightTexture(toggleHL, "ADD")
        toggle:SetChecked(lc.specs[spec.id] == true)
        toggle:SetScript("OnClick", function(self)
            lc.specs[spec.id] = self:GetChecked() or false
            if RefreshAllLayouts then RefreshAllLayouts() end
        end)

        y = y + 28
    end
    specChild:SetHeight(y)

    uiFrames.loadWindow = f
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
    if frame.border then
        frame.border:Hide()
    end
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
    local itemID = GetInventoryItemID("player", slotID)
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
        return CreateSpellIcon(iconKey, iconData, parent)
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
        local frame = CreateSpellIcon(iconKey, {id = racialID}, parent)
        if frame then
            frame._type = "racial"
            frame._fallbackTexture = FALLBACK_RACIAL_ICON
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
        UpdateSpellIconFrame(frame, iconData)
    elseif iconData.type == "racial" then
        local racialID = GetPlayerRacialSpellID()
        if racialID then
            UpdateSpellIconFrame(frame, {id = racialID, settings = iconData.settings})
        end
    elseif iconData.type == "slot" then
        UpdateSlotIcon(frame, iconData)
    elseif iconData.type == "trinketProc" then
        UpdateTrinketProcIcon(frame, iconData)
    elseif iconData.type == "aura" then
        UpdateAuraIcon(frame, iconData)
    end
    if frame._ddIsManaged then
        CustomIcons.ApplyManagedGroupTextOptions(frame)
    end
end

runtime.UpdateDynamicIcon = UpdateDynamicIcon

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
                local iid = GetInventoryItemID("player", iconData.slotID or 13)
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

local function RefreshAllLayouts()
    -- SpecProfiles 자동 저장 트리거 (동적 아이콘 설정 변경 감지)
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end

    -- [DYNAMIC] GroupSystem이 활성이면 레이아웃 스킵 → GroupSystem 업데이트 트리거
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
        return
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
                        local itemID = GetInventoryItemID("player", iconData.slotID)
                        if itemID and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                    elseif iconData.type == "slot" and iconData.slotID then
                        local itemID = GetInventoryItemID("player", iconData.slotID)
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
    UpdateAllIcons()

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
                -- 새로 생성된 프레임이 있으면 레이아웃 갱신 + GroupSystem 알림
                RefreshAllLayouts()
                UpdateAllIcons()
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

    profile.groupSystem = profile.groupSystem or {}
    local gs = profile.groupSystem
    gs.groups = gs.groups or {}

    local groupSettings = gs.groups[groupName]
    if not groupSettings then
        groupSettings = {
            name = displayName or CDM_SOURCE_GROUP_NAMES[groupName] or groupName,
            enabled = true,
            groupType = "cdm",
        }
        gs.groups[groupName] = groupSettings
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
    groupSettings.groupType = groupSettings.groupType or "cdm"
    return sourceKey
end

function CustomIcons:AddIconToCDMGroup(groupName, iconData, displayName)
    if type(iconData) ~= "table" then return nil end

    local groupManager = DDingUI.GroupManager
    if groupManager and groupManager.AssignMatchingCDMBuffIcon then
        local assignedSpellName = groupManager:AssignMatchingCDMBuffIcon(iconData, groupName)
        if assignedSpellName then
            C_Timer.After(0.05, function()
                local gs = DDingUI.GroupSystem
                if gs and gs.Refresh then
                    gs:Refresh()
                end
            end)
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
                    C_Timer.After(0.05, function()
                        local gs = DDingUI.GroupSystem
                        if gs and gs.Refresh then
                            gs:Refresh()
                        end
                    end)
                    return existingKey, sourceKey
                end
            end
        end
    end

    local iconKey = self:AddDynamicIcon(iconData)
    if iconKey then
        self:MoveIconToGroup(iconKey, sourceKey)
        C_Timer.After(0.05, function()
            local gs = DDingUI.GroupSystem
            if gs and gs.Refresh then
                gs:Refresh()
            end
        end)
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

    -- [FIX] GroupSystem 즉시 갱신 — 디바운스 우회하여 아이콘 바로 표시
    C_Timer.After(0.1, function()
        local bridge = DDingUI.DynamicIconBridge
        if bridge and bridge:IsActive() then
            local gs = DDingUI.GroupSystem
            if gs and gs.Refresh then
                gs:Refresh()
            end
        end
    end)

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
    if uiState and uiState.selectedGroup == groupKey then
        uiState.selectedGroup = nil
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
    -- [FIX] GroupSystem 즉시 갱신 — MoveIconToGroup 후 바로 아이콘 표시
    C_Timer.After(0.1, function()
        local bridge = DDingUI.DynamicIconBridge
        if bridge and bridge:IsActive() then
            local gs = DDingUI.GroupSystem
            if gs and gs.Refresh then
                gs:Refresh()
            end
        end
    end)
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

-- ------------------------
-- GUI (lightweight WeakAuras-like list)
-- ------------------------
uiState = {
    searchText = "",
    selectedIcon = nil,
    selectedGroup = nil,
    collapsedGroups = {},
    selectedIcons = {},  -- Multi-select: { [iconKey] = true }
    multiSelectMode = false,
}

local function MatchesSearch(iconKey, iconData)
    if uiState.searchText == "" then return true end
    local query = string.lower(uiState.searchText)
    local name = ""
    if iconData.type == "item" then
        name = GetItemInfo(iconData.id) or ((L["Item"] or "Item") .. " " .. iconData.id)
    elseif iconData.type == "spell" then
        local info = C_Spell.GetSpellInfo(iconData.id)
        name = (info and info.name) or ((L["Spell"] or "Spell") .. " " .. iconData.id)
    elseif iconData.type == "slot" then
        name = ((L["Slot"] or "Slot") .. " " .. (iconData.slotID or ""))
    elseif iconData.type == "trinketProc" then
        local iid = GetInventoryItemID("player", iconData.slotID or 13)
        name = (iid and GetItemInfo(iid)) or ("Trinket " .. (iconData.slotID == 14 and "2" or "1"))
    end
    name = string.lower(tostring(name))
    local idStr = tostring(iconData.id or iconData.slotID or "")
    return name:find(query) or idStr:find(query)
end

local function CreateIconNode(parent, iconKey, iconData, groupKey)
    local node = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    node:SetSize(240, 42)
    node:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    -- [STYLE] bg.input 기본, bg.hover 호버, bg.selected 선택
    node:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.80)
    node:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.5)
    node._iconKey = iconKey
    node._hover = false

    local function applyNodeHighlight()
        local isSelected = uiState.selectedIcon == iconKey
        local isMultiSelected = uiState.selectedIcons[iconKey]
        -- [STYLE] default=bgWidget, hover=bgLight, selected=bgMedium
        local bg = THEME.bgWidget
        local border = THEME.border
        local alpha = 0.80
        if isSelected or isMultiSelected then
            bg = THEME.bgMedium
            border = THEME.accent
            alpha = 0.80
        elseif node._hover then
            bg = THEME.bgLight
            border = {THEME.borderLight[1], THEME.borderLight[2], THEME.borderLight[3]}
            alpha = 0.60
        end
        node:SetBackdropColor(bg[1], bg[2], bg[3], alpha)
        node:SetBackdropBorderColor(border[1], border[2], border[3], isSelected and 1 or 0.5)
    end

    -- Multi-select checkbox (UF 통일: 14x14, 그라디언트 체크)
    local checkbox = CreateFrame("Button", nil, node, "BackdropTemplate")
    checkbox:SetSize(14, 14)
    checkbox:SetPoint("LEFT", node, "LEFT", 6, 0)
    checkbox:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    checkbox._checked = uiState.selectedIcons[iconKey] or false

    -- 체크 마크 텍스쳐 (UF 통일: 전체 채우기 그라디언트)
    local checkTex = checkbox:CreateTexture(nil, "OVERLAY")
    checkTex:SetPoint("TOPLEFT", 1, -1)
    checkTex:SetPoint("BOTTOMRIGHT", -1, 1)
    checkTex:SetColorTexture(1, 1, 1, 1)
    checkTex:SetGradient("HORIZONTAL",
        CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),
        CreateColor(THEME.accentDark[1], THEME.accentDark[2], THEME.accentDark[3], 1)
    )
    checkTex:Hide()

    local function updateCheckboxVisual()
        if checkbox._checked then
            checkbox:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
            checkbox:SetBackdropBorderColor(0, 0, 0, 1)
            checkTex:Show()
        else
            checkbox:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
            checkbox:SetBackdropBorderColor(0, 0, 0, 1)
            checkTex:Hide()
        end
    end
    updateCheckboxVisual()
    -- 하이라이트
    local cbHighlight = checkbox:CreateTexture(nil, "ARTWORK")
    cbHighlight:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.1)
    cbHighlight:SetPoint("TOPLEFT", 1, -1)
    cbHighlight:SetPoint("BOTTOMRIGHT", -1, 1)
    cbHighlight:Hide()
    checkbox:SetScript("OnEnter", function(self)
        if not self._checked then cbHighlight:Show() end
    end)
    checkbox:SetScript("OnLeave", function(self)
        cbHighlight:Hide()
    end)
    checkbox:SetScript("OnClick", function(self)
        self._checked = not self._checked
        if self._checked then
            uiState.selectedIcons[iconKey] = true
        else
            uiState.selectedIcons[iconKey] = nil
        end
        -- Count selected icons
        local count = 0
        for _ in pairs(uiState.selectedIcons) do count = count + 1 end
        uiState.multiSelectMode = count > 0
        if count > 0 then
            uiState.selectedIcon = nil
            uiState.selectedGroup = nil
        end
        updateCheckboxVisual()
        applyNodeHighlight()
        CustomIcons:RefreshDynamicConfigUI()
    end)

    node.iconTex = node:CreateTexture(nil, "ARTWORK")
    node.iconTex:SetSize(32, 32)
    node.iconTex:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    node.iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    if iconData.type == "item" then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(iconData.id)
        node.iconTex:SetTexture(NonQuestionTexture(tex, ResolveItemTexture(iconData.id) or FALLBACK_ITEM_ICON))
    elseif iconData.type == "spell" or iconData.type == "aura" then
        local stored = GetStoredIconTexture(iconData)
        node.iconTex:SetTexture(NonQuestionTexture(ResolveSpellTexture(iconData.id, stored), stored or FALLBACK_SPELL_ICON))
    elseif iconData.type == "slot" or iconData.type == "trinketProc" then
        local iid = GetInventoryItemID("player", iconData.slotID)
        local _, _, _, _, _, _, _, _, _, tex = iid and GetItemInfo(iid)
        node.iconTex:SetTexture(NonQuestionTexture(tex, ResolveItemTexture(iid, iconData.slotID) or FALLBACK_SLOT_ICON))
    elseif iconData.type == "racial" then
        local racialID = GetPlayerRacialSpellID()
        if racialID then
            if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                local ok, overrideID = pcall(C_SpellBook.FindSpellOverrideByID, racialID)
                if ok and overrideID and overrideID ~= racialID then
                    racialID = overrideID
                end
            end
            local info = C_Spell.GetSpellInfo(racialID)
            local tex = (info and info.iconID) or C_Spell.GetSpellTexture(racialID)
            node.iconTex:SetTexture(NonQuestionTexture(tex, FALLBACK_RACIAL_ICON))
        else
            node.iconTex:SetTexture(FALLBACK_RACIAL_ICON)
        end
    else
        node.iconTex:SetTexture(FALLBACK_SPELL_ICON)
    end

    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
    local label = node:CreateFontString(nil, "OVERLAY")
    label:SetFont(globalFont, 11, "")
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetPoint("LEFT", node.iconTex, "RIGHT", 6, 6)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)

    local displayName = ""
    if iconData.type == "item" then
        displayName = GetItemInfo(iconData.id) or ((L["Item"] or "Item") .. " ID: " .. iconData.id)
    elseif iconData.type == "spell" or iconData.type == "aura" then
        local info = C_Spell.GetSpellInfo(iconData.id)
        displayName = (info and info.name) or ((L["Spell"] or "Spell") .. " ID: " .. iconData.id)
    elseif iconData.type == "slot" then
        displayName = (L["Slot"] or "Slot") .. " " .. tostring(iconData.slotID or "")
    elseif iconData.type == "trinketProc" then
        local iid = GetInventoryItemID("player", iconData.slotID or 13)
        displayName = (iid and GetItemInfo(iid)) or ("Trinket " .. (iconData.slotID == 14 and "2" or "1"))
    elseif iconData.type == "racial" then
        local racialID = GetPlayerRacialSpellID()
        if racialID then
            if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                local ok, overrideID = pcall(C_SpellBook.FindSpellOverrideByID, racialID)
                if ok and overrideID and overrideID ~= racialID then
                    racialID = overrideID
                end
            end
            local info = C_Spell.GetSpellInfo(racialID)
            displayName = (info and info.name) or "Racial Trait"
        else
            displayName = "Racial Trait"
        end
    end
    label:SetText(displayName)

    local badge = node:CreateFontString(nil, "OVERLAY")
    badge:SetFont(globalFont, 10, "")
    badge:SetShadowOffset(1, -1)
    badge:SetShadowColor(0, 0, 0, 1)
    badge:SetPoint("LEFT", label, "LEFT", 0, -12)
    badge:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.9)
    badge:SetText(string.upper(iconData.type))

    local deleteBtn = CreateFrame("Button", nil, node, "BackdropTemplate")
    deleteBtn:SetSize(16, 16)
    deleteBtn:SetPoint("TOPRIGHT", node, "TOPRIGHT", -4, -4)
    deleteBtn:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    deleteBtn:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
    deleteBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.50)
    local deleteBtnText = deleteBtn:CreateFontString(nil, "OVERLAY")
    deleteBtnText:SetFont(globalFont, 11, "")
    deleteBtnText:SetPoint("CENTER", 0, 1)
    deleteBtnText:SetText("×")
    deleteBtnText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    deleteBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(THEME.error[1], THEME.error[2], THEME.error[3], 0.9)
        self:SetBackdropBorderColor(THEME.error[1], THEME.error[2], THEME.error[3], 1)
        deleteBtnText:SetTextColor(1, 1, 1, 1)
    end)
    deleteBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
        self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.50)
        deleteBtnText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    end)
    deleteBtn:SetScript("OnClick", function()
        CustomIcons:ConfirmDeleteIcon(iconKey, displayName)
    end)

    node:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            -- Clear multi-select and select single icon
            uiState.selectedIcons = {}
            uiState.multiSelectMode = false
            uiState.selectedIcon = iconKey
            uiState.selectedGroup = nil
            CustomIcons:RefreshDynamicListUI()
            CustomIcons:RefreshDynamicConfigUI()
        end
    end)
    node:SetScript("OnEnter", function()
        node._hover = true
        applyNodeHighlight()
        if runtime.dragState.dragging then
            runtime.dragState.targetGroup = groupKey
            runtime.dragState.dropBefore = iconKey
        end
    end)
    node:SetScript("OnLeave", function()
        node._hover = false
        applyNodeHighlight()
        if runtime.dragState.dragging then
            runtime.dragState.dropBefore = nil
        end
    end)

    node:RegisterForDrag("LeftButton")
    node:SetScript("OnDragStart", function()
        runtime.dragState.iconKey = iconKey
        runtime.dragState.sourceGroup = groupKey
        runtime.dragState.dropBefore = nil
        runtime.dragState.dragging = true
        node:SetAlpha(0.35)
    end)
    node:SetScript("OnDragStop", function()
        if runtime.dragState.dragging then
            local targetGroup = runtime.dragState.targetGroup or runtime.dragState.sourceGroup
            local beforeKey = runtime.dragState.dropBefore
            if targetGroup then
                if targetGroup ~= runtime.dragState.sourceGroup then
                    CustomIcons:MoveIconToGroup(iconKey, targetGroup)
                end
                CustomIcons:ReorderIconInGroup(targetGroup, iconKey, beforeKey)
            end
        end
        runtime.dragState.iconKey = nil
        runtime.dragState.targetGroup = nil
        runtime.dragState.dropBefore = nil
        runtime.dragState.dragging = false
        node:SetAlpha(1)
        CustomIcons:RefreshDynamicListUI()
    end)

    applyNodeHighlight()
    return node
end

-- UI containers
local uiFrames = {
    listParent = nil,
    configParent = nil,
    searchBox = nil,
    resultText = nil,
    createFrame = nil,
    loadWindow = nil,
}

-- [REFACTOR] CreateStyledButton/Toggle/Input/Dropdown → DDingUI.GUI로 이동 (EnsureGUILoaded에서 로드)

function CustomIcons:RefreshDynamicListUI()
    if not uiFrames.listParent then return end
    if not EnsureGUILoaded() then return end
    local db = GetDynamicDB()
    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"

    -- Clear children
    for _, child in ipairs({uiFrames.listParent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local y = -5

    -- Multi-select buttons
    local selectBtnFrame = CreateFrame("Frame", nil, uiFrames.listParent)
    selectBtnFrame:SetPoint("TOPLEFT", uiFrames.listParent, "TOPLEFT", 0, y)
    selectBtnFrame:SetSize(240, 24)

    local selectAllBtn = CreateStyledButton(selectBtnFrame, "전체 선택", 75, 22)
    selectAllBtn:SetPoint("LEFT", selectBtnFrame, "LEFT", 0, 0)
    selectAllBtn:SetScript("OnClick", function()
        -- Select all visible icons
        for iconKey, _ in pairs(db.iconData) do
            uiState.selectedIcons[iconKey] = true
        end
        local count = 0
        for _ in pairs(uiState.selectedIcons) do count = count + 1 end
        uiState.multiSelectMode = count > 0
        if count > 0 then
            uiState.selectedIcon = nil
            uiState.selectedGroup = nil
        end
        CustomIcons:RefreshDynamicListUI()
        CustomIcons:RefreshDynamicConfigUI()
    end)

    local deselectAllBtn = CreateStyledButton(selectBtnFrame, "선택 해제", 75, 22)
    deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 4, 0)
    deselectAllBtn:SetScript("OnClick", function()
        uiState.selectedIcons = {}
        uiState.multiSelectMode = false
        CustomIcons:RefreshDynamicListUI()
        CustomIcons:RefreshDynamicConfigUI()
    end)

    -- Selected count
    local selectedCount = 0
    for _ in pairs(uiState.selectedIcons) do selectedCount = selectedCount + 1 end
    local countText = selectBtnFrame:CreateFontString(nil, "OVERLAY")
    countText:SetFont(globalFont, 10, "")
    countText:SetShadowOffset(1, -1)
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetPoint("LEFT", deselectAllBtn, "RIGHT", 8, 0)
    if selectedCount > 0 then
        countText:SetText("|cff00ff00" .. selectedCount .. "개 선택됨|r")
    else
        countText:SetText("")
    end

    y = y - 30
    local shown = 0
    local total = 0

    local function renderSection(title, iconKeys, groupKey)
        local isCollapsed = uiState.collapsedGroups[groupKey] == true
        local isSelectedGroup = uiState.selectedGroup == groupKey
        local headerHover = false
        -- Check if this group is disabled (only for actual groups, not ungrouped)
        local group = db.groups[groupKey]
        local isDisabled = group and group.enabled == false

        local box = CreateFrame("Frame", nil, uiFrames.listParent, "BackdropTemplate")
        box:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        })
        -- [STYLE] 그룹 헤더 bg.widget, border.default
        box:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.80)
        box:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.50)
        box:SetPoint("TOPLEFT", uiFrames.listParent, "TOPLEFT", -2, y)
        box:SetPoint("TOPRIGHT", uiFrames.listParent, "TOPRIGHT", 2, y)

        local header = CreateFrame("Button", nil, box)
        header:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
        header:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -4)
        header:SetHeight(22)

        local headerText = header:CreateFontString(nil, "OVERLAY")
        headerText:SetFont(globalFont, 11, "")
        headerText:SetShadowOffset(1, -1)
        headerText:SetShadowColor(0, 0, 0, 1)
        headerText:SetPoint("LEFT", header, "LEFT", 4, 0)
        if isDisabled then
            headerText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.6)
            headerText:SetText(title .. " |cff888888[OFF]|r")
        else
            headerText:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            headerText:SetText(title)
        end

        local arrowBtn = CreateFrame("Button", nil, header, "BackdropTemplate")
        arrowBtn:SetSize(20, 20)
        arrowBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
        arrowBtn:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        arrowBtn:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.8)
        arrowBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.50)
        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        local arrowText = arrowBtn:CreateFontString(nil, "OVERLAY")
        arrowText:SetFont(globalFont, 11, "")
        arrowText:SetShadowOffset(1, -1)
        arrowText:SetShadowColor(0, 0, 0, 1)
        arrowText:SetPoint("CENTER", 0, 0)
        arrowText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        local function updateArrow()
            if uiState.collapsedGroups[groupKey] == true then
                arrowText:SetText("▶")
            else
                arrowText:SetText("▼")
            end
        end
        updateArrow()
        arrowBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.2)
            self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
            arrowText:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
        end)
        arrowBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.8)
            self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.50)
            arrowText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        end)

        local function applyBoxHighlight()
            -- [STYLE] default=bgWidget, selected=bgMedium, hover=accent border
            local bg = isSelectedGroup and THEME.bgMedium or THEME.bgWidget
            local alpha = isSelectedGroup and 0.80 or 0.80
            local border = (isSelectedGroup or headerHover) and THEME.accent or THEME.border
            local borderAlpha = (isSelectedGroup or headerHover) and 1 or 0.50
            -- Dim disabled groups
            if isDisabled then
                alpha = alpha * 0.5
                border = THEME.border
                borderAlpha = 0.3
            end
            box:SetBackdropColor(bg[1], bg[2], bg[3], alpha)
            box:SetBackdropBorderColor(border[1], border[2], border[3], borderAlpha)
        end
        applyBoxHighlight()

        header:SetScript("OnEnter", function()
            headerHover = true
            if runtime.dragState.iconKey then
                runtime.dragState.targetGroup = groupKey
            end
            applyBoxHighlight()
        end)
        header:SetScript("OnLeave", function()
            headerHover = false
            if runtime.dragState.targetGroup == groupKey then
                runtime.dragState.targetGroup = nil
            end
            applyBoxHighlight()
        end)
        header:SetScript("OnMouseUp", function()
            uiState.selectedGroup = groupKey
            uiState.selectedIcon = nil
            isSelectedGroup = true
            applyBoxHighlight()
            CustomIcons:RefreshDynamicListUI()
            CustomIcons:RefreshDynamicConfigUI()
        end)
        header:SetScript("OnClick", nil)

        arrowBtn:SetScript("OnClick", function()
            uiState.collapsedGroups[groupKey] = not (uiState.collapsedGroups[groupKey] == true)
            CustomIcons:RefreshDynamicListUI()
        end)

        local innerY = -28
        if not isCollapsed then
            for _, iconKey in ipairs(iconKeys) do
                local iconData = db.iconData[iconKey]
                if iconData then
                    total = total + 1
                    if MatchesSearch(iconKey, iconData) then
                        local node = CreateIconNode(box, iconKey, iconData, groupKey)
                        node:SetPoint("TOPLEFT", box, "TOPLEFT", 8, innerY)
                        innerY = innerY - 46
                        shown = shown + 1
                    end
                end
            end
        else
            -- Count totals even when collapsed for result text
            for _, iconKey in ipairs(iconKeys) do
                if db.iconData[iconKey] then
                    total = total + 1
                end
            end
        end

        local boxHeight = math.abs(innerY) + 8
        box:SetHeight(boxHeight)
        y = y - boxHeight - 8
    end

    -- Ungrouped
    local ungroupedKeys = {}
    for k in pairs(db.ungrouped) do
        table.insert(ungroupedKeys, k)
    end
    table.sort(ungroupedKeys)
    renderSection(L["Ungrouped Icons"] or "Ungrouped Icons", ungroupedKeys, "ungrouped")

    for groupKey, group in pairs(db.groups) do
        local keys = {}
        local seen = {}
        for _, k in ipairs(group.icons or {}) do
            if db.iconData[k] and not seen[k] then
                table.insert(keys, k)
                seen[k] = true
            end
        end
        renderSection(GetGroupDisplayName(groupKey), keys, groupKey)
    end

    if uiFrames.resultText then
        uiFrames.resultText:SetText(string.format("Showing %d of %d icons", shown, total))
    end

    uiFrames.listParent:SetHeight(math.abs(y) + 20)

    -- 자식 위젯 위에서도 스크롤 가능하도록 마우스 휠 전파
    local listScroll = uiFrames.listParent:GetParent()
    if listScroll and PropagateMouseWheelRecursive then
        PropagateMouseWheelRecursive(uiFrames.listParent, listScroll)
    end
end

-- Batch edit state (temporary values before applying)
local batchEditState = {
    iconSize = 40,
    aspectRatio = 1.0,
    borderSize = 1,
    borderColor = {1, 1, 1, 1},
    showCooldown = true,
    showCharges = true,
    desaturateOnCooldown = true,
    desaturateWhenUnusable = true,
    showGCDSwipe = false,
}

function CustomIcons:ApplyBatchSettings(settings)
    local db = GetDynamicDB()
    for iconKey, _ in pairs(uiState.selectedIcons) do
        local iconData = db.iconData[iconKey]
        if iconData then
            iconData.settings = iconData.settings or {}
            for key, val in pairs(settings) do
                if key == "borderColor" then
                    iconData.settings.borderColor = {unpack(val)}
                else
                    iconData.settings[key] = val
                end
            end
            if runtime.UpdateDynamicIcon then
                runtime.UpdateDynamicIcon(iconKey)
            end
        end
    end
    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
end

function CustomIcons:RefreshDynamicConfigUI()
    if not uiFrames.configParent then return end
    if not EnsureGUILoaded() then return end
    -- 자식 프레임 정리
    for _, child in ipairs({uiFrames.configParent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    -- FontString/Texture 등 Region 정리
    for _, region in ipairs({uiFrames.configParent:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end

    local db = GetDynamicDB()

    -- Check for multi-select mode
    local selectedCount = 0
    for _ in pairs(uiState.selectedIcons) do selectedCount = selectedCount + 1 end

    if selectedCount > 1 then
        -- Batch Edit UI
        local y = 0

        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        local header = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
        header:SetFont(globalFont, 14, "")
        header:SetShadowOffset(1, -1)
        header:SetShadowColor(0, 0, 0, 1)
        header:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
        header:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        header:SetText(selectedCount .. "개 아이콘 일괄 편집")
        y = y + 30

        local desc = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
        desc:SetFont(globalFont, 10, "")
        desc:SetShadowOffset(1, -1)
        desc:SetShadowColor(0, 0, 0, 1)
        desc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
        desc:SetText("아래 설정을 조정 후 '일괄 적용' 버튼을 눌러주세요")
        desc:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        y = y + 25

        -- Icon Size
        local sizeSlider = Widgets.CreateRange(uiFrames.configParent, {
            name = "아이콘 크기",
            min = 16, max = 128, step = 1,
            get = function() return batchEditState.iconSize end,
            set = function(_, val) batchEditState.iconSize = val end,
            width = "full",
        }, y, {})
        sizeSlider.slider:SetObeyStepOnDrag(true)
        sizeSlider.slider:SetValue(batchEditState.iconSize)
        y = y + 36

        -- Aspect Ratio
        local aspectSlider = Widgets.CreateRange(uiFrames.configParent, {
            name = "종횡비",
            min = 0.5, max = 2.0, step = 0.01,
            get = function() return batchEditState.aspectRatio end,
            set = function(_, val) batchEditState.aspectRatio = val end,
            width = "full",
        }, y, {})
        aspectSlider.slider:SetObeyStepOnDrag(true)
        aspectSlider.slider:SetValue(batchEditState.aspectRatio)
        y = y + 36

        -- Border Size
        local borderSlider = Widgets.CreateRange(uiFrames.configParent, {
            name = "테두리 크기",
            min = 0, max = 10, step = 1,
            get = function() return batchEditState.borderSize end,
            set = function(_, val) batchEditState.borderSize = val end,
            width = "full",
        }, y, {})
        borderSlider.slider:SetObeyStepOnDrag(true)
        borderSlider.slider:SetValue(batchEditState.borderSize)
        y = y + 36

        -- Border Color
        Widgets.CreateColor(uiFrames.configParent, {
            name = "테두리 색상",
            get = function() return unpack(batchEditState.borderColor) end,
            set = function(_, r, g, b, a) batchEditState.borderColor = {r, g, b, a} end,
            width = "full",
        }, y)
        y = y + 40

        -- Toggles
        Widgets.CreateToggle(uiFrames.configParent, {
            name = "쿨다운 표시",
            get = function() return batchEditState.showCooldown end,
            set = function(_, val) batchEditState.showCooldown = val end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "충전/횟수 표시",
            get = function() return batchEditState.showCharges end,
            set = function(_, val) batchEditState.showCharges = val end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "쿨다운 시 흑백",
            get = function() return batchEditState.desaturateOnCooldown end,
            set = function(_, val) batchEditState.desaturateOnCooldown = val end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "사용 불가 시 흑백",
            get = function() return batchEditState.desaturateWhenUnusable end,
            set = function(_, val) batchEditState.desaturateWhenUnusable = val end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "GCD 스와이프 표시",
            get = function() return batchEditState.showGCDSwipe end,
            set = function(_, val) batchEditState.showGCDSwipe = val end,
            width = "full",
        }, y)
        y = y + 40

        -- Apply Button
        Widgets.CreateExecute(uiFrames.configParent, {
            name = "|cff00ff00일괄 적용|r",
            func = function()
                CustomIcons:ApplyBatchSettings({
                    iconSize = batchEditState.iconSize,
                    aspectRatio = batchEditState.aspectRatio,
                    borderSize = batchEditState.borderSize,
                    borderColor = batchEditState.borderColor,
                    showCooldown = batchEditState.showCooldown,
                    showCharges = batchEditState.showCharges,
                    desaturateOnCooldown = batchEditState.desaturateOnCooldown,
                    desaturateWhenUnusable = batchEditState.desaturateWhenUnusable,
                    showGCDSwipe = batchEditState.showGCDSwipe,
                })
                print(((SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: ") .. "|cff00ff00" .. selectedCount .. "개 아이콘에 설정이 적용되었습니다.|r") -- [STYLE]
            end,
            width = "full",
        }, y)
        y = y + 50

        -- Delete Selected Button
        local deleteBtn = Widgets.CreateExecute(uiFrames.configParent, {
            name = "|cffff4040선택 삭제 (" .. selectedCount .. "개)|r",
            func = function()
                CustomIcons:ConfirmDeleteSelected()
            end,
            width = "full",
        }, y)
        if deleteBtn and deleteBtn.text then
            deleteBtn.text:SetTextColor(0.90, 0.25, 0.25, 1)
        end

        return  -- Don't show single icon config
    end

    local iconKey = uiState.selectedIcon
    local groupKey = uiState.selectedGroup
    local iconData = iconKey and db.iconData[iconKey]
    if iconData then
        EnsureIconType(iconData)  -- Ensure type is set for config UI
    end
    local selectedGroup = groupKey and db.groups[groupKey]

    local y = 0
    local function addSlider(text, min, max, step, getter, setter)
        local slider = Widgets.CreateRange(uiFrames.configParent, {
            name = text,
            min = min,
            max = max,
            step = step,
            get = function() return getter() end,
            set = function(_, val)
                setter(val)
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y, {})  -- Pass empty optionsTable
        slider.slider:SetObeyStepOnDrag(true)
        slider.slider:SetValue(getter())
        y = y + 36
    end

    local function showIconConfig()
        addSlider(L["Icon Size"] or "Icon Size", 16, 128, 1, function() return iconData.settings.iconSize or 40 end, function(val) iconData.settings.iconSize = val end)

        -- Use Own Size toggle (ignore group size)
        Widgets.CreateToggle(uiFrames.configParent, {
            name = L["Use Own Size"] or "Use Own Size",
            desc = L["Ignore group icon size and use this icon's own size setting"] or "Ignore group icon size and use this icon's own size setting",
            get = function() return iconData.settings.useOwnSize or false end,
            set = function(_, val)
                iconData.settings.useOwnSize = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
            end,
            width = "full",
        }, y)
        y = y + 30

        addSlider(L["Aspect Ratio"] or "Aspect Ratio", 0.5, 2.0, 0.01, function() return iconData.settings.aspectRatio or 1.0 end, function(val) iconData.settings.aspectRatio = val end)
        addSlider(L["Border Size"] or "Border Size", 0, 10, 1, function() return iconData.settings.borderSize or DEFAULT_ICON_SETTINGS.borderSize end, function(val) iconData.settings.borderSize = val end)

        -- Border Color
        Widgets.CreateColor(uiFrames.configParent, {
            name = L["Border Color"] or "Border Color",
            get = function() return unpack(iconData.settings.borderColor or {1, 1, 1, 1}) end,
            set = function(_, r, g, b, a)
                iconData.settings.borderColor = {r, g, b, a}
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        addSlider(L["Count Size"] or "Count Size", 4, 64, 1, function() return (iconData.settings.countSettings and iconData.settings.countSettings.size) or 16 end, function(val)
            iconData.settings.countSettings = iconData.settings.countSettings or {}
            iconData.settings.countSettings.size = val
        end)

        -- Count Font Type
        do
            local fontValues = {}
            if LSM then
                local hashTable = LSM:HashTable("font")
                for name, _ in pairs(hashTable) do
                    fontValues[name] = name
                end
            end
            Widgets.CreateSelect(uiFrames.configParent, {
                name = L["Count Font Type"] or "Count Font Type",
                values = fontValues,
                get = function()
                    local cs = iconData.settings.countSettings or {}
                    return cs.font or (DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.general and DDingUI.db.profile.general.globalFont) or "Expressway"
                end,
                set = function(_, val)
                    iconData.settings.countSettings = iconData.settings.countSettings or {}
                    iconData.settings.countSettings.font = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                    RefreshAllLayouts()
                    CustomIcons:RefreshDynamicListUI()
                end,
                width = "full",
            }, y, nil, nil, nil)
            y = y + 40
        end

        -- Count Color
        Widgets.CreateColor(uiFrames.configParent, {
            name = L["Count Color"] or "Count Color",
            get = function()
                local cs = iconData.settings.countSettings or {}
                return unpack(cs.color or {1, 1, 1, 1})
            end,
            set = function(_, r, g, b, a)
                iconData.settings.countSettings = iconData.settings.countSettings or {}
                iconData.settings.countSettings.color = {r, g, b, a}
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        -- Count X Offset
        addSlider(L["Count X Offset"] or "Count X Offset", -50, 50, 1, function()
            local cs = iconData.settings.countSettings or {}
            return cs.offsetX or -2
        end, function(val)
            iconData.settings.countSettings = iconData.settings.countSettings or {}
            iconData.settings.countSettings.offsetX = val
            if iconKey and runtime.UpdateDynamicIcon then
                runtime.UpdateDynamicIcon(iconKey)
            end
            RefreshAllLayouts()
            CustomIcons:RefreshDynamicListUI()
        end)

        -- Count Y Offset
        addSlider(L["Count Y Offset"] or "Count Y Offset", -50, 50, 1, function()
            local cs = iconData.settings.countSettings or {}
            return cs.offsetY or 2
        end, function(val)
            iconData.settings.countSettings = iconData.settings.countSettings or {}
            iconData.settings.countSettings.offsetY = val
            if iconKey and runtime.UpdateDynamicIcon then
                runtime.UpdateDynamicIcon(iconKey)
            end
            RefreshAllLayouts()
            CustomIcons:RefreshDynamicListUI()
        end)

        -- Count Anchor Point
        Widgets.CreateSelect(uiFrames.configParent, {
            name = L["Count Anchor Point"] or "Count Anchor Point",
            values = {
                TOPLEFT = L["Top Left"] or "Top Left",
                TOP = L["Top"] or "Top",
                TOPRIGHT = L["Top Right"] or "Top Right",
                LEFT = L["Left"] or "Left",
                RIGHT = L["Right"] or "Right",
                BOTTOMLEFT = L["Bottom Left"] or "Bottom Left",
                BOTTOM = L["Bottom"] or "Bottom",
                BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
            },
            get = function()
                local cs = iconData.settings.countSettings or {}
                return cs.anchor or "BOTTOMRIGHT"
            end,
            set = function(_, val)
                iconData.settings.countSettings = iconData.settings.countSettings or {}
                iconData.settings.countSettings.anchor = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y, nil, nil, nil)
        y = y + 40

        -- Cooldown Text Size
        addSlider(L["Cooldown Text Size"] or "Cooldown Text Size", 4, 64, 1, function()
            local cds = iconData.settings.cooldownSettings or {}
            return cds.size or 12
        end, function(val)
            iconData.settings.cooldownSettings = iconData.settings.cooldownSettings or {}
            iconData.settings.cooldownSettings.size = val
        end)

        -- Cooldown Text Color
        Widgets.CreateColor(uiFrames.configParent, {
            name = "Cooldown Text Color",
            get = function()
                local cds = iconData.settings.cooldownSettings or {}
                return unpack(cds.color or {1, 1, 1, 1})
            end,
            set = function(_, r, g, b, a)
                iconData.settings.cooldownSettings = iconData.settings.cooldownSettings or {}
                iconData.settings.cooldownSettings.color = {r, g, b, a}
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "Show Cooldown",
            get = function() return iconData.settings.showCooldown ~= false end,
            set = function(_, val)
                iconData.settings.showCooldown = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "Show GCD Swipe",
            get = function() return iconData.settings.showGCDSwipe == true end,
            set = function(_, val)
                iconData.settings.showGCDSwipe = val == true
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "Show Charges/Count",
            get = function() return iconData.settings.showCharges ~= false end,
            set = function(_, val)
                iconData.settings.showCharges = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        -- TrinketProc-specific settings
        if iconData.type == "trinketProc" then
            -- Separator
            local trinketHeader = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
            trinketHeader:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 12, "")
            trinketHeader:SetShadowOffset(1, -1)
            trinketHeader:SetShadowColor(0, 0, 0, 1)
            trinketHeader:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            trinketHeader:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            trinketHeader:SetText("━━━ Trinket Proc Settings ━━━")
            trinketHeader:SetJustifyH("LEFT")
            y = y + 24

            Widgets.CreateInput(uiFrames.configParent, {
                name = "Proc Spell ID (0 = Auto)",
                get = function() return tostring(iconData.settings.procSpellID or 0) end,
                set = function(_, val)
                    iconData.settings.procSpellID = tonumber(val) or 0
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                end,
                width = "full",
            }, y)
            y = y + 30

            local procDesc = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
            procDesc:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 10, "")
            procDesc:SetShadowOffset(1, -1)
            procDesc:SetShadowColor(0, 0, 0, 1)
            procDesc:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            procDesc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            procDesc:SetText("0: Use: 효과 자동 감지 / 수동: 패시브 프록 spellID 입력")
            procDesc:SetJustifyH("LEFT")
            y = y + 20

            Widgets.CreateToggle(uiFrames.configParent, {
                name = "Show Proc Duration",
                get = function() return iconData.settings.showProcDuration ~= false end,
                set = function(_, val)
                    iconData.settings.showProcDuration = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                end,
                width = "full",
            }, y)
            y = y + 32

            Widgets.CreateToggle(uiFrames.configParent, {
                name = "Show Item Cooldown",
                get = function() return iconData.settings.showItemCooldown ~= false end,
                set = function(_, val)
                    iconData.settings.showItemCooldown = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                end,
                width = "full",
            }, y)
            y = y + 32

            Widgets.CreateToggle(uiFrames.configParent, {
                name = "Show Proc Stacks",
                get = function() return iconData.settings.showProcStacks ~= false end,
                set = function(_, val)
                    iconData.settings.showProcStacks = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                end,
                width = "full",
            }, y)
            y = y + 32
        end

        -- Fallback Item IDs (show for item type or unknown type with id)
        local isItemType = (iconData.type == "item") or (iconData.type ~= "spell" and iconData.type ~= "slot" and iconData.type ~= "trinketProc" and iconData.id)
        if isItemType then
            Widgets.CreateInput(uiFrames.configParent, {
                name = "Fallback Item IDs",
                get = function() return iconData.settings.fallbackItems or "" end,
                set = function(_, val)
                    iconData.settings.fallbackItems = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                    RefreshAllLayouts()
                end,
                width = "full",
            }, y)
            y = y + 30

            local fallbackDesc = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
            fallbackDesc:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 10, "")
            fallbackDesc:SetShadowOffset(1, -1)
            fallbackDesc:SetShadowColor(0, 0, 0, 1)
            fallbackDesc:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            fallbackDesc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            fallbackDesc:SetText("예: 3성 물약ID, 2성ID, 1성ID (쉼표 구분)")
            fallbackDesc:SetJustifyH("LEFT")
            y = y + 20
        end

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "Desaturate on Cooldown",
            get = function() return iconData.settings.desaturateOnCooldown ~= false end,
            set = function(_, val)
                iconData.settings.desaturateOnCooldown = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "Desaturate When Unusable",
            get = function() return iconData.settings.desaturateWhenUnusable ~= false end,
            set = function(_, val)
                iconData.settings.desaturateWhenUnusable = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateExecute(uiFrames.configParent, {
            name = L["Load Conditions..."] or "Load Conditions...",
            func = function() CustomIcons:ShowLoadConditionsWindow(iconKey, iconData) end,
            width = "full",
        }, y)
        y = y + 40

        -- Update scroll child height
        uiFrames.configParent:SetHeight(y + 20)
        -- 마우스 휠 전파 (아이콘 설정)
        if uiFrames.configScroll and PropagateMouseWheelRecursive then
            PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
        end
    end

    local function ensureGroupDefaults(group)
        group.settings = group.settings or {}
        local s = group.settings
        s.growthDirection = s.growthDirection or "RIGHT"
        s.rowGrowthDirection = s.rowGrowthDirection or GetDefaultRowGrowth(s.growthDirection)
        s.rowGrowthDirection = NormalizeRowGrowth(s.growthDirection, s.rowGrowthDirection)
        if s.maxIconsPerRow == nil and s.maxColumns ~= nil then
            s.maxIconsPerRow = s.maxColumns
            s.maxColumns = nil
        end
        if s.anchorPoint and not s.anchorFrom and not s.anchorTo then
            s.anchorFrom = s.anchorPoint
            s.anchorTo = s.anchorPoint
            s.anchorPoint = nil
        end
        s.anchorFrom = s.anchorFrom or GetStartAnchorForGrowthPair(s.growthDirection, s.rowGrowthDirection)
        s.anchorTo = s.anchorTo or s.anchorFrom
        s.spacing = s.spacing or 5
        s.iconSize = s.iconSize or 40
        s.position = s.position or {x = 100, y = -100}
        s.anchorFrame = s.anchorFrame or ""
    end

    local function showGroupConfig()
        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        if not selectedGroup then
            local label = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
            label:SetFont(globalFont, 13, "")
            label:SetShadowOffset(1, -1)
            label:SetShadowColor(0, 0, 0, 1)
            label:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, 20)
            label:SetText("Select an icon or group")
            label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            return
        end
        ensureGroupDefaults(selectedGroup)
        local s = selectedGroup.settings

        -- Enabled toggle at the top
        Widgets.CreateToggle(uiFrames.configParent, {
            name = "Enable Group",
            desc = "Show or hide all icons in this group",
            get = function() return selectedGroup.enabled ~= false end,
            set = function(_, val)
                selectedGroup.enabled = val
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 35

        Widgets.CreateInput(uiFrames.configParent, {
            name = "Group Name",
            get = function() return selectedGroup.name or "" end,
            set = function(_, val)
                selectedGroup.name = val or "Group"
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        Widgets.CreateSelect(uiFrames.configParent, {
            name = "Growth Direction",
            values = {RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down"},
            get = function() return s.growthDirection end,
            set = function(_, val)
                s.growthDirection = val
                s.rowGrowthDirection = NormalizeRowGrowth(val, s.rowGrowthDirection or GetDefaultRowGrowth(val))
                s.anchorFrom = GetStartAnchorForGrowthPair(val, s.rowGrowthDirection)
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "normal",
        }, y, nil, nil, nil)
        y = y + 40

        Widgets.CreateSelect(uiFrames.configParent, {
            name = "Row Growth",
            values = {RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down"},
            get = function() return s.rowGrowthDirection end,
            set = function(_, val)
                s.rowGrowthDirection = NormalizeRowGrowth(s.growthDirection or "RIGHT", val)
                s.anchorFrom = GetStartAnchorForGrowthPair(s.growthDirection or "RIGHT", s.rowGrowthDirection)
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "normal",
        }, y, nil, nil, nil)
        y = y + 40

        Widgets.CreateSelect(uiFrames.configParent, {
            name = "Anchor Frame Point",
            values = {
                TOPLEFT="TOPLEFT", TOP="TOP", TOPRIGHT="TOPRIGHT",
                LEFT="LEFT", CENTER="CENTER", RIGHT="RIGHT",
                BOTTOMLEFT="BOTTOMLEFT", BOTTOM="BOTTOM", BOTTOMRIGHT="BOTTOMRIGHT",
            },
            get = function() return s.anchorTo end,
            set = function(_, val)
                s.anchorTo = val
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y, nil, nil, nil)
        y = y + 40

        addSlider(L["Icon Size"] or "Icon Size", 16, 128, 1, function() return s.iconSize or 40 end, function(val) s.iconSize = val end)

        -- Apply size to all icons in group button
        Widgets.CreateExecute(uiFrames.configParent, {
            name = L["Apply Size to All Icons"] or "Apply Size to All Icons",
            func = function()
                if selectedGroup and selectedGroup.icons then
                    for _, iKey in ipairs(selectedGroup.icons) do
                        local iData = db.iconData[iKey]
                        if iData and iData.settings then
                            iData.settings.iconSize = nil  -- Clear individual size
                            iData.settings.useOwnSize = false  -- Use group size
                        end
                    end
                    RefreshAllLayouts()
                    CustomIcons:RefreshDynamicListUI()
                    print(((SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: ") .. "|cff00ff00Applied group size to all icons|r") -- [STYLE]
                end
            end,
            width = "full",
        }, y)
        y = y + 35

        addSlider(L["Spacing"] or "Spacing", -10, 10, 1, function() return s.spacing or 5 end, function(val) s.spacing = val end)
        addSlider(L["Max Icons Per Row"] or "Max Icons Per Row", 1, 40, 1, function() return s.maxIconsPerRow or 10 end, function(val) s.maxIconsPerRow = val end)
        addSlider(L["Position X"] or "Position X", -1000, 1000, 1, function() return (s.position and s.position.x) or 0 end, function(val)
            s.position = s.position or {}
            s.position.x = val
        end)
        addSlider(L["Position Y"] or "Position Y", -1000, 1000, 1, function() return (s.position and s.position.y) or 0 end, function(val)
            s.position = s.position or {}
            s.position.y = val
        end)

        Widgets.CreateInput(uiFrames.configParent, {
            name = "Anchor Frame",
            get = function() return s.anchorFrame or "" end,
            set = function(_, val)
                s.anchorFrame = val or ""
                if not s.anchorFrame or s.anchorFrame == "" then
                    s.anchorFrame = ""
                end
                -- Avoid rebuilding the config UI while typing; just update layout shortly after change
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.05, RefreshAllLayouts)
                else
                    RefreshAllLayouts()
                end
            end,
            width = "full",
        }, y)
        y = y + 30

        -- 앵커 선택 버튼: 마우스로 프레임 직접 선택
        local pickBtn = Widgets.CreateExecute(uiFrames.configParent, {
            name = "앵커 선택 (마우스 클릭)",
            func = function()
                DDingUI:StartFramePicker(function(frameName)
                    s.anchorFrame = frameName or ""
                    RefreshAllLayouts()
                    CustomIcons:RefreshDynamicConfigUI()
                end)
            end,
            width = "full",
        }, y)
        if pickBtn and pickBtn.text then
            pickBtn.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        end
        y = y + 40

        local deleteGroupBtn = Widgets.CreateExecute(uiFrames.configParent, {
            name = "Delete Group",
            func = function()
                CustomIcons:ConfirmDeleteGroup(groupKey, selectedGroup.name or groupKey)
            end,
            width = "full",
        }, y)
        -- [STYLE] Delete 버튼: status.error 컬러 텍스트
        if deleteGroupBtn and deleteGroupBtn.text then
            deleteGroupBtn.text:SetTextColor(0.90, 0.25, 0.25, 1)
        end
        y = y + 40

        -- Update scroll child height
        uiFrames.configParent:SetHeight(y + 20)
        -- 마우스 휠 전파 (그룹 설정)
        if uiFrames.configScroll and PropagateMouseWheelRecursive then
            PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
        end
    end

    if iconData then
        showIconConfig()
        return
    end
    if selectedGroup then
        showGroupConfig()
        return
    end

    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
    local label = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
    label:SetFont(globalFont, 13, "")
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, 20)
    label:SetText("Select an icon or group")
    label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)

    -- 자식 위젯 위에서도 스크롤 가능하도록 마우스 휠 전파
    if uiFrames.configScroll and PropagateMouseWheelRecursive then
        PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
    end
end

function CustomIcons:ConfirmDeleteIcon(iconKey, label)
    if not EnsureGUILoaded() then return end
    if not uiFrames.confirmFrame then
        local f = CreateFrame("Frame", "DDingUI_DynIconConfirm", UIParent, "BackdropTemplate")
        f:SetSize(320, 140)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)

        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        f.text:SetShadowOffset(1, -1)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetPoint("TOP", f, "TOP", 0, -38)
        f.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)

        f.confirm = CreateStyledButton(f, "Confirm", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)

        f.cancel = CreateStyledButton(f, "Cancel", 100, 26)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)

        f:Hide()
        uiFrames.confirmFrame = f
    end

    local f = uiFrames.confirmFrame
    f.title:SetText(L["Confirm Deletion"] or "Confirm Deletion")
    f.text:SetText((L["Delete \"%s\"?\nThis cannot be undone."] or "Delete \"%s\"?\nThis cannot be undone."):format(label or "icon"))
    f.confirm:SetScript("OnClick", function()
        f:Hide()
        CustomIcons:RemoveDynamicIcon(iconKey)
    end)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:Show()
end

function CustomIcons:ConfirmDeleteGroup(groupKey, label)
    if not EnsureGUILoaded() then return end
    if not uiFrames.confirmGroupFrame then
        local f = CreateFrame("Frame", "DDingUI_DynGroupConfirm", UIParent, "BackdropTemplate")
        f:SetSize(320, 160)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(0.90, 0.25, 0.25, 1)  -- Red for warning (THEME error color)

        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        f.text:SetShadowOffset(1, -1)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetPoint("TOP", f, "TOP", 0, -38)
        f.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        f.text:SetWidth(280)
        f.text:SetJustifyH("CENTER")

        f.confirm = CreateStyledButton(f, "Delete", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        f.confirm:SetBackdropColor(0.5, 0.1, 0.1, 1)  -- Red tint for delete

        f.cancel = CreateStyledButton(f, "Cancel", 100, 26)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)

        f:Hide()
        uiFrames.confirmGroupFrame = f
    end

    local f = uiFrames.confirmGroupFrame
    f.title:SetText(L["Delete Group?"] or "Delete Group?")
    f.text:SetText((L["Are you sure you want to delete group \"%s\"?\n\nAll icons in this group will be deleted.\nThis cannot be undone."] or "Are you sure you want to delete group \"%s\"?\n\nAll icons in this group will be deleted.\nThis cannot be undone."):format(label or "group"))
    f.confirm:SetScript("OnClick", function()
        f:Hide()
        CustomIcons:RemoveGroup(groupKey)
    end)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:Show()
end

function CustomIcons:ConfirmDeleteSelected()
    if not EnsureGUILoaded() then return end
    if not uiState.selectedIcons then return end

    local count = 0
    for _ in pairs(uiState.selectedIcons) do
        count = count + 1
    end
    if count == 0 then return end

    if not uiFrames.confirmBatchFrame then
        local f = CreateFrame("Frame", "DDingUI_DynBatchConfirm", UIParent, "BackdropTemplate")
        f:SetSize(320, 160)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(0.90, 0.25, 0.25, 1)

        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        f.text:SetShadowOffset(1, -1)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetPoint("TOP", f, "TOP", 0, -38)
        f.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        f.text:SetWidth(280)
        f.text:SetJustifyH("CENTER")

        f.confirm = CreateStyledButton(f, "Delete", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        f.confirm:SetBackdropColor(0.5, 0.1, 0.1, 1)

        f.cancel = CreateStyledButton(f, "Cancel", 100, 26)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)

        f:Hide()
        uiFrames.confirmBatchFrame = f
    end

    local f = uiFrames.confirmBatchFrame
    f.title:SetText(L["Delete Selected?"] or "Delete Selected?")
    f.text:SetText((L["Are you sure you want to delete %d selected icons?\n\nThis cannot be undone."] or "Are you sure you want to delete %d selected icons?\n\nThis cannot be undone."):format(count))
    f.confirm:SetScript("OnClick", function()
        f:Hide()
        local db = GetDynamicDB()
        for iconKey in pairs(uiState.selectedIcons) do
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
        end
        uiState.selectedIcons = {}
        uiState.multiSelectMode = false
        RefreshAllLayouts()
        CustomIcons:RefreshDynamicListUI()
        CustomIcons:RefreshDynamicConfigUI()
    end)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:Show()
end

function CustomIcons:BuildDynamicIconsUI(parent)
    EnsureEventFrame()

    -- Ensure GUI components are loaded
    if not EnsureGUILoaded() then
        print(((SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: ") .. "|cffff0000Dynamic Icons: GUI not loaded yet|r") -- [STYLE]
        return
    end

    -- 이전 uiFrames 참조 초기화 (재진입 시 잔상 방지)
    uiFrames.listParent = nil
    uiFrames.configParent = nil
    uiFrames.configScroll = nil
    uiFrames.searchBox = nil
    uiFrames.resultText = nil

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)

    -- Search bar
    local search = Widgets.CreateInput(container, {
        name = "Search by name or ID...",
        width = "full",
        get = function() return uiState.searchText end,
        set = function(_, val)
            uiState.searchText = val or ""
            CustomIcons:RefreshDynamicListUI()
        end,
    }, 0)
    if search.editBox then
        search.editBox:SetHeight(28)
    end

    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
    local resultText = container:CreateFontString(nil, "OVERLAY")
    resultText:SetFont(globalFont, 10, "")
    resultText:SetShadowOffset(1, -1)
    resultText:SetShadowColor(0, 0, 0, 1)
    if search.editBox then
        resultText:SetPoint("TOPLEFT", search.editBox, "BOTTOMLEFT", 4, -6)
    else
        resultText:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -34)
    end
    resultText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    uiFrames.resultText = resultText

    -- Buttons
    local createIconBtn = Widgets.CreateExecute(container, {
        name = "+ Create Icon",
        func = function() CustomIcons:ShowCreateIconDialog() end,
        width = "normal",
    }, 40)
    -- [STYLE] 악센트 텍스트
    if createIconBtn.text then createIconBtn.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1) end
    if search.editBox then
        createIconBtn:SetPoint("TOPLEFT", search.editBox, "BOTTOMLEFT", 0, -18)
    else
        createIconBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -52)
    end

    local createGroupBtn = Widgets.CreateExecute(container, {
        name = "+ " .. (L["New Group"] or "Create Group"),
        func = function()
            CustomIcons:CreateDynamicGroup(L["New Group"] or "New Group")
        end,
        width = "normal",
    }, 40)
    -- [STYLE] 악센트 텍스트
    if createGroupBtn.text then createGroupBtn.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1) end
    createGroupBtn:SetPoint("LEFT", createIconBtn, "RIGHT", 8, 0)

    -- Left list scroll (DDingUI custom scrollbar)
    local listScroll = CreateFrame("ScrollFrame", nil, container)
    listScroll:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -80)
    listScroll:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    listScroll:SetWidth(260)

    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(250)
    listChild:SetHeight(400)
    listScroll:SetScrollChild(listChild)

    local listScrollBar = CreateCustomScrollBar(container, listScroll)
    listScrollBar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 4, 0)
    listScrollBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 4, 0)
    listScroll.ScrollBar = listScrollBar

    uiFrames.listParent = listChild

    -- [STYLE] 좌우 구분선 (border.separator)
    local separator = container:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 5, 0)
    separator:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 5, 0)
    separator:SetColorTexture(0.20, 0.20, 0.20, 0.40)

    -- [STYLE] 우측 설정 영역: bg.sidebar 배경, border.default 테두리
    local configContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    configContainer:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 12, 0)
    configContainer:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    CreateBackdrop(configContainer, THEME.bgDark, THEME.border)

    local configScroll = CreateFrame("ScrollFrame", nil, configContainer)
    configScroll:SetPoint("TOPLEFT", configContainer, "TOPLEFT", 8, -8)
    configScroll:SetPoint("BOTTOMRIGHT", configContainer, "BOTTOMRIGHT", -14, 8)

    local configChild = CreateFrame("Frame", nil, configScroll)
    configChild:SetWidth(configScroll:GetWidth() or 400)
    configChild:SetHeight(800)  -- Will be adjusted dynamically
    configScroll:SetScrollChild(configChild)

    local configScrollBar = CreateCustomScrollBar(configContainer, configScroll)
    configScrollBar:SetPoint("TOPLEFT", configScroll, "TOPRIGHT", 4, 0)
    configScrollBar:SetPoint("BOTTOMLEFT", configScroll, "BOTTOMRIGHT", 4, 0)
    configScroll.ScrollBar = configScrollBar

    uiFrames.configParent = configChild
    uiFrames.configScroll = configScroll

    CustomIcons:RefreshDynamicListUI()
    CustomIcons:RefreshDynamicConfigUI()
end

-- Creation dialog
CustomIcons.slotOptions = CustomIcons.slotOptions or {
    {text = "Trinket 0 (Slot 13)", slotID = 13},
    {text = "Trinket 1 (Slot 14)", slotID = 14},
    {text = "Main Hand (16)", slotID = 16},
    {text = "Off Hand (17)", slotID = 17},
    {text = "Head (1)", slotID = 1},
    {text = "Neck (2)", slotID = 2},
    {text = "Shoulder (3)", slotID = 3},
    {text = "Back (15)", slotID = 15},
    {text = "Chest (5)", slotID = 5},
    {text = "Wrist (9)", slotID = 9},
    {text = "Hands (10)", slotID = 10},
    {text = "Waist (6)", slotID = 6},
    {text = "Legs (7)", slotID = 7},
    {text = "Feet (8)", slotID = 8},
    {text = "Finger 0 (11)", slotID = 11},
    {text = "Finger 1 (12)", slotID = 12},
}

-- Keep dropdown menus above the create dialog so they don't get obscured
function CustomIcons.RaiseDropDownMenus()
    for i = 1, 2 do
        local list = _G["DropDownList"..i]
        if list then
            list:SetFrameStrata("TOOLTIP")
            if uiFrames.createFrame then
                list:SetFrameLevel(uiFrames.createFrame:GetFrameLevel() + 10)
            end
            if not list.__dduiStrataHooked then
                list:HookScript("OnShow", CustomIcons.RaiseDropDownMenus)
                list.__dduiStrataHooked = true
            end
        end
    end
end

function CustomIcons:ShowCreateIconDialog()
    if not EnsureGUILoaded() then return end
    if not uiFrames.createFrame then
        local f = CreateFrame("Frame", "DDingUI_DynIconCreate", UIParent, "BackdropTemplate")
        f:SetSize(360, 200)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        CreateBackdrop(f, THEME.bgDark, THEME.border)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(globalFont, 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        f.title:SetText("Create Icon")

        -- Type toggle buttons (styled)
        f.typeButtons = {}
        local types = { {key = "spell", label = "Spell"}, {key = "item", label = "Item"}, {key = "slot", label = "Slot"}, {key = "trinketProc", label = "Trinket"}, {key = "racial", label = "Racial"} }
        local spacing = 75
        local startX = -((#types - 1) * spacing) / 2
        for idx, info in ipairs(types) do
            local btn = CreateStyledToggle(f, info.label, 80)
            btn:SetPoint("TOP", f, "TOP", startX + (idx - 1) * spacing, -42)
            btn:SetScript("OnClick", function()
                for _, b in pairs(f.typeButtons) do b:SetChecked(false) end
                btn:SetChecked(true)
                f.selectedType = info.key
                if info.key == "slot" then
                    f.idInput:Hide()
                    f.idLabel:Hide()
                    f.slotDropdown:Show()
                    f.slotLabel:Show()
                    if f.trinketDropdown then f.trinketDropdown:Hide() end
                    if f.trinketLabel then f.trinketLabel:Hide() end
                elseif info.key == "trinketProc" then
                    f.idInput:Hide()
                    f.idLabel:Hide()
                    f.slotDropdown:Hide()
                    f.slotLabel:Hide()
                    if f.trinketDropdown then f.trinketDropdown:Show() end
                    if f.trinketLabel then f.trinketLabel:Show() end
                elseif info.key == "racial" then
                    f.idInput:Hide()
                    f.idLabel:Hide()
                    f.slotDropdown:Hide()
                    f.slotLabel:Hide()
                    if f.trinketDropdown then f.trinketDropdown:Hide() end
                    if f.trinketLabel then f.trinketLabel:Hide() end
                else
                    f.idInput:Show()
                    f.idLabel:Show()
                    f.slotDropdown:Hide()
                    f.slotLabel:Hide()
                    if f.trinketDropdown then f.trinketDropdown:Hide() end
                    if f.trinketLabel then f.trinketLabel:Hide() end
                end
            end)
            f.typeButtons[info.key] = btn
        end
        f.typeButtons.spell:SetChecked(true)
        f.selectedType = "spell"

        -- ID input (styled)
        local idLabel = f:CreateFontString(nil, "OVERLAY")
        idLabel:SetFont(globalFont, 11, "")
        idLabel:SetShadowOffset(1, -1)
        idLabel:SetShadowColor(0, 0, 0, 1)
        idLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -78)
        idLabel:SetText("Spell or Item ID")
        idLabel:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        f.idLabel = idLabel

        local idBox = CreateStyledInput(f, 200, 28, true)
        idBox:SetPoint("TOPLEFT", idLabel, "BOTTOMLEFT", 0, -4)
        f.idInput = idBox

        -- Slot dropdown (styled)
        local slotLabel = f:CreateFontString(nil, "OVERLAY")
        slotLabel:SetFont(globalFont, 11, "")
        slotLabel:SetShadowOffset(1, -1)
        slotLabel:SetShadowColor(0, 0, 0, 1)
        slotLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -78)
        slotLabel:SetText("Equipment Slot")
        slotLabel:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        slotLabel:Hide()
        f.slotLabel = slotLabel

        local dropdown = CreateStyledDropdown(f, CustomIcons.slotOptions, 200)
        dropdown:SetPoint("TOPLEFT", slotLabel, "BOTTOMLEFT", 0, -4)
        dropdown:SetText("Select Slot")
        dropdown:Hide()
        f.slotDropdown = dropdown
        f.selectedSlot = CustomIcons.slotOptions[1].slotID
        dropdown.selectedValue = CustomIcons.slotOptions[1].slotID

        -- Trinket slot dropdown (for trinketProc type)
        local trinketSlotOptions = {
            {text = "Trinket 1 (Slot 13)", slotID = 13},
            {text = "Trinket 2 (Slot 14)", slotID = 14},
        }
        local trinketLabel = f:CreateFontString(nil, "OVERLAY")
        trinketLabel:SetFont(globalFont, 11, "")
        trinketLabel:SetShadowOffset(1, -1)
        trinketLabel:SetShadowColor(0, 0, 0, 1)
        trinketLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -78)
        trinketLabel:SetText("Trinket Slot")
        trinketLabel:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        trinketLabel:Hide()
        f.trinketLabel = trinketLabel

        local trinketDD = CreateStyledDropdown(f, trinketSlotOptions, 200)
        trinketDD:SetPoint("TOPLEFT", trinketLabel, "BOTTOMLEFT", 0, -4)
        trinketDD:SetText("Trinket 1 (Slot 13)")
        trinketDD:Hide()
        f.trinketDropdown = trinketDD
        trinketDD.selectedValue = 13

        -- Buttons (styled)
        f.confirm = CreateStyledButton(f, "Create", 100, 28)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)

        f.cancel = CreateStyledButton(f, "Cancel", 100, 28)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
        f.cancel:SetScript("OnClick", function() f:Hide() end)

        f.confirm:SetScript("OnClick", function()
            local t = f.selectedType
            if t == "slot" then
                local slotID = f.slotDropdown.selectedValue or CustomIcons.slotOptions[1].slotID
                CustomIcons:AddDynamicIcon({type = "slot", slotID = slotID})
            elseif t == "trinketProc" then
                local slotID = f.trinketDropdown.selectedValue or 13
                CustomIcons:AddDynamicIcon({type = "trinketProc", slotID = slotID})
            elseif t == "racial" then
                CustomIcons:AddDynamicIcon({type = "racial", id = 0})
            else
                local idVal = f.idInput:GetText() or ""
                -- String (spell name) or Number (spell ID) allowed
                local numId = tonumber(idVal)
                if not numId and idVal ~= "" then
                    local info = C_Spell.GetSpellInfo(idVal)
                    if info and info.spellID then numId = info.spellID end
                end

                if not numId or numId <= 0 then
                    UIErrorsFrame:AddMessage("Enter a valid ID or Spell Name", 1, 0, 0)
                    return
                end
                CustomIcons:AddDynamicIcon({type = t, id = numId})
            end
            f:Hide()
        end)

        uiFrames.createFrame = f
    end

    uiFrames.createFrame:Show()
end

-- Hook into GUI renderer
CustomIcons.BuildDynamicIconsUI = CustomIcons.BuildDynamicIconsUI
CustomIcons.RefreshDynamicListUI = CustomIcons.RefreshDynamicListUI
CustomIcons.RefreshDynamicConfigUI = CustomIcons.RefreshDynamicConfigUI
CustomIcons.ApplyIconBorder = ApplyIconBorder
CustomIcons.ResolveAnchorPoints = ResolveAnchorPoints
CustomIcons.GetAnchorFrame = GetAnchorFrame
CustomIcons.ShowLoadConditionsWindow = CustomIcons.ShowLoadConditionsWindow

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
