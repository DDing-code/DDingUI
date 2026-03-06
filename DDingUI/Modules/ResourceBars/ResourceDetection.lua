local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- Tables
local buildVersion = select(4, GetBuildInfo())
local HAS_UNIT_POWER_PERCENT = type(UnitPowerPercent) == "function"

-- Safely fetch power percent across API variants (12.0 curve vs legacy boolean)
local function SafeUnitPowerPercent(unit, resource, usePredicted)
    if type(UnitPowerPercent) == "function" then
        local ok, pct

        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitPowerPercent, unit, resource, usePredicted, CurveConstants.ScaleTo100)
        else
            ok, pct = pcall(UnitPowerPercent, unit, resource, usePredicted, true)
        end

        if (not ok or pct == nil) then
            ok, pct = pcall(UnitPowerPercent, unit, resource, usePredicted)
        end

        if ok and pct ~= nil then
            return pct
        end
    end

    if UnitPower and UnitPowerMax then
        local cur = UnitPower(unit, resource)
        local max = UnitPowerMax(unit, resource)
        if cur and max and max > 0 then
            return (cur / max) * 100
        end
    end

    return nil
end

local tickedPowerTypes = {
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Essence] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.SoulShards] = true,
    ["MAELSTROM_WEAPON"] = true,
}

local fragmentedPowerTypes = {
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.Essence] = true,
}

-- Export tables for use in other ResourceBars files
DDingUI.ResourceBars = DDingUI.ResourceBars or {}
DDingUI.ResourceBars.tickedPowerTypes = tickedPowerTypes
DDingUI.ResourceBars.fragmentedPowerTypes = fragmentedPowerTypes
DDingUI.ResourceBars.HAS_UNIT_POWER_PERCENT = HAS_UNIT_POWER_PERCENT
DDingUI.ResourceBars.buildVersion = buildVersion

-- RESOURCE DETECTION

local function GetPrimaryResource()
    local playerClass = select(2, UnitClass("player"))
    local primaryResources = {
        ["DEATHKNIGHT"] = Enum.PowerType.RunicPower,
        ["DEMONHUNTER"] = Enum.PowerType.Fury,
        ["DRUID"]       = {
            [0]   = Enum.PowerType.Mana, -- Human
            [1]   = Enum.PowerType.Energy, -- Cat
            [5]   = Enum.PowerType.Rage, -- Bear
            [27]  = Enum.PowerType.Mana, -- Travel
            [31]  = Enum.PowerType.LunarPower, -- Moonkin
        },
        ["EVOKER"]      = Enum.PowerType.Mana,
        ["HUNTER"]      = Enum.PowerType.Focus,
        ["MAGE"]        = Enum.PowerType.Mana,
        ["MONK"]        = {
            [268] = Enum.PowerType.Energy, -- Brewmaster
            [269] = Enum.PowerType.Energy, -- Windwalker
            [270] = Enum.PowerType.Mana, -- Mistweaver
        },
        ["PALADIN"]     = Enum.PowerType.Mana,
        ["PRIEST"]      = {
            [256] = Enum.PowerType.Mana, -- Disciple
            [257] = Enum.PowerType.Mana, -- Holy,
            [258] = Enum.PowerType.Insanity, -- Shadow,
        },
        ["ROGUE"]       = Enum.PowerType.Energy,
        ["SHAMAN"]      = {
            [262] = Enum.PowerType.Maelstrom, -- Elemental
            [263] = Enum.PowerType.Mana, -- Enhancement
            [264] = Enum.PowerType.Mana, -- Restoration
        },
        ["WARLOCK"]     = Enum.PowerType.Mana,
        ["WARRIOR"]     = Enum.PowerType.Rage,
    }

    local spec = GetSpecialization()
    local specID = GetSpecializationInfo(spec)

    -- Druid: form-based
    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        local resource = primaryResources[playerClass][formID or 0]
        -- [FIX] 화신(Incarnation) 등 미등록 폼 ID → UnitPowerType 폴백
        -- 회복 드루이드 화신 변신 시 마나바 사라지는 버그 수정
        if not resource then
            local powerType = UnitPowerType("player")
            if powerType and powerType >= 0 then
                return powerType
            end
            return Enum.PowerType.Mana -- 최후 폴백: 드루이드 기본 마나
        end
        return resource
    end

    if type(primaryResources[playerClass]) == "table" then
        local resource = primaryResources[playerClass][specID]
        -- Fallback: if specID lookup fails (e.g., during spec transition), use UnitPowerType
        if not resource then
            local powerType = UnitPowerType("player")
            if powerType and powerType >= 0 then
                return powerType
            end
        end
        return resource
    else
        return primaryResources[playerClass]
    end
end

-- Dynamic secondary resource detection using Blizzard API
-- No more hardcoding - automatically detects what Blizzard shows
local function GetSecondaryResource()
    local playerClass = select(2, UnitClass("player"))
    local primaryPower = UnitPowerType("player")

    -- Special cases that aren't standard PowerTypes
    -- These need manual detection as they use different systems

    -- Brewmaster Monk: Stagger (not a PowerType, uses UnitStagger API)
    if playerClass == "MONK" then
        local spec = GetSpecialization()
        local specID = spec and GetSpecializationInfo(spec)
        if specID == 268 then -- Brewmaster
            return "STAGGER"
        end
    end

    -- Enhancement Shaman: Maelstrom Weapon (buff-based, not PowerType)
    if playerClass == "SHAMAN" then
        local spec = GetSpecialization()
        local specID = spec and GetSpecializationInfo(spec)
        if specID == 263 then -- Enhancement
            return "MAELSTROM_WEAPON"
        end
    end

    -- Demon Hunter 포식 (Feast): Soul Fragments (special UI element)
    -- specID 1480 = 포식 (Havoc/Vengeance have no secondary resource)
    if playerClass == "DEMONHUNTER" then
        local spec = GetSpecialization()
        local specID = spec and GetSpecializationInfo(spec)
        if specID == 1480 then -- 포식
            return "SOUL"
        end
    end

    -- Standard PowerTypes - detect dynamically
    -- These are the "ticked" secondary resources Blizzard shows as separate bars
    local secondaryPowerTypes = {
        Enum.PowerType.ComboPoints,
        Enum.PowerType.HolyPower,
        Enum.PowerType.Chi,
        Enum.PowerType.ArcaneCharges,
        Enum.PowerType.Runes,
        Enum.PowerType.SoulShards,
        Enum.PowerType.Essence,
    }

    -- Mistweaver Monk: Chi exists but shouldn't be shown as secondary resource
    local isMistweaver = false
    if playerClass == "MONK" then
        local spec = GetSpecialization()
        local specID = spec and GetSpecializationInfo(spec)
        if specID == 270 then -- Mistweaver
            isMistweaver = true
        end
    end

    -- Mage: ArcaneCharges only for Arcane spec (specID 62) -- [12.0.1]
    -- WoW API returns UnitPowerMax > 0 for ArcaneCharges on all mage specs
    local isNotArcaneMage = false
    if playerClass == "MAGE" then
        local spec = GetSpecialization()
        local specID = spec and GetSpecializationInfo(spec)
        if specID ~= 62 then -- Not Arcane
            isNotArcaneMage = true
        end
    end

    -- Druid: ComboPoints only available in Cat Form (formID == 1)
    -- Other specs/forms have access to ComboPoints system but don't use it
    local isDruidNotInCatForm = false
    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        if formID ~= 1 then -- Not Cat Form
            isDruidNotInCatForm = true
        end
    end

    for _, powerType in ipairs(secondaryPowerTypes) do
        -- Skip if it's the primary power
        if powerType ~= primaryPower then
            -- Skip Chi for Mistweaver (they have Chi system but don't use it)
            if powerType == Enum.PowerType.Chi and isMistweaver then
                -- skip
            -- Skip ComboPoints for Druid not in Cat Form
            elseif powerType == Enum.PowerType.ComboPoints and isDruidNotInCatForm then
                -- skip
            -- Skip ArcaneCharges for non-Arcane Mage specs -- [12.0.1]
            elseif powerType == Enum.PowerType.ArcaneCharges and isNotArcaneMage then
                -- skip
            else
                local max = UnitPowerMax("player", powerType)
                if max and max > 0 then
                    return powerType
                end
            end
        end
    end

    -- Druid special case: show mana as secondary when in Moonkin form
    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        if formID == 31 then -- Moonkin
            return Enum.PowerType.Mana
        end
    end

    return nil
end

local function GetChargedPowerPoints(resource)
    -- Only attempt for ticked, non-fragmented secondary resources (combo points, holy power, etc.)
    if not resource or fragmentedPowerTypes[resource] or not tickedPowerTypes[resource] then
        return nil
    end

    if type(GetUnitChargedPowerPoints) ~= "function" then
        return nil
    end

    local ok, charged = pcall(GetUnitChargedPowerPoints, "player")
    if not ok or not charged then
        return nil
    end

    local normalized = {}
    for _, index in ipairs(charged) do
        if type(index) == "number" then
            table.insert(normalized, index)
        end
    end

    if #normalized == 0 then
        return nil
    end

    return normalized
end

local function GetResourceColor(resource)
    local color = nil
    
    -- Blizzard PowerType lookup name (fallback)
    local powerName = nil
    if type(resource) == "number" then
        for name, value in pairs(Enum.PowerType) do
            if value == resource then
                powerName = name:gsub("(%u)", "_%1"):gsub("^_", ""):upper()
                break
            end
        end
    end

    if resource == "STAGGER" then
        -- Monk stagger uses dynamic coloring based on configurable thresholds
        local stagger = UnitStagger("player") or 0
        local maxHealth = UnitHealthMax("player") or 1
        local percent = 0
        if maxHealth > 0 then
            percent = (stagger / maxHealth) * 100
        end

        -- Use configurable colors if available, otherwise fall back to defaults
        if percent >= 60 then
            -- Heavy stagger - use configured heavy color or default red
            local heavyColor = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.powerTypeColors and DDingUI.db.profile.powerTypeColors.colors and DDingUI.db.profile.powerTypeColors.colors["STAGGER_HEAVY"]
            color = heavyColor or { r = 1.00, g = 0.42, b = 0.42 }
        elseif percent >= 30 then
            -- Medium stagger - use configured medium color or default yellow
            local mediumColor = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.powerTypeColors and DDingUI.db.profile.powerTypeColors.colors and DDingUI.db.profile.powerTypeColors.colors["STAGGER_MEDIUM"]
            color = mediumColor or { r = 1.00, g = 0.98, b = 0.72 }
        else
            -- Light stagger - use configured light color or default green
            local lightColor = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.powerTypeColors and DDingUI.db.profile.powerTypeColors.colors and DDingUI.db.profile.powerTypeColors.colors["STAGGER_LIGHT"]
            color = lightColor or { r = 0.52, g = 1.00, b = 0.52 }
        end

    elseif resource == "SOUL" then
        -- Demon Hunter soul fragments
        color = { r = 0.64, g = 0.19, b = 0.79 }


    elseif resource == Enum.PowerType.Runes then
        -- Death Knight: spec-specific rune colors
        local specColor = nil
        local powerTypeColors = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.powerTypeColors
        if powerTypeColors and powerTypeColors.colors then
            local spec = GetSpecialization and GetSpecialization()
            local specID = spec and GetSpecializationInfo and GetSpecializationInfo(spec)
            if specID == 250 then
                specColor = powerTypeColors.colors["RUNE_BLOOD"]
            elseif specID == 251 then
                specColor = powerTypeColors.colors["RUNE_FROST"]
            elseif specID == 252 then
                specColor = powerTypeColors.colors["RUNE_UNHOLY"]
            end
        end
        if specColor then
            color = { r = specColor[1], g = specColor[2], b = specColor[3] }
        else
            color = { r = 0.77, g = 0.12, b = 0.23 }
        end

    elseif resource == Enum.PowerType.Essence then
        -- Evoker
        color = { r = 0.20, g = 0.58, b = 0.50 }

    elseif resource == Enum.PowerType.SoulShards then
        -- Warlock soul shards (WARLOCK class color)
        color = { r = 0.58, g = 0.51, b = 0.79 }

    elseif resource == Enum.PowerType.ComboPoints then
        -- Rogue
        color = { r = 1.00, g = 0.96, b = 0.41 }

    elseif resource == Enum.PowerType.Chi then
        -- Monk
        color = { r = 0.00, g = 1.00, b = 0.59 }
    end

    ---------------------------------------------------------

    -- Fallback to Blizzard's power bar colors
    return color
        or GetPowerBarColor(powerName)
        or GetPowerBarColor(resource)
        or GetPowerBarColor("MANA")
end

-- GET RESOURCE VALUES

local function GetPrimaryResourceValue(resource, cfg)
    if not resource then return nil, nil, nil, nil, nil end

    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)
    if max <= 0 then return nil, nil, nil, nil, nil end

    if cfg.showManaAsPercent and resource == Enum.PowerType.Mana then
        local percent = SafeUnitPowerPercent("player", resource, false)
        if percent ~= nil then
            return max, max, current, percent, "percent"
        end
        return max, max, current, math.floor((current / max) * 100 + 0.5), "percent"
    else
        return max, max, current, current, "number"
    end
end

local function GetSecondaryResourceValue(resource, cfg)
    if not resource then return nil, nil, nil, nil, nil end

    -- Allow callers to pass config for formatting; fall back to current DB if omitted
    cfg = cfg or (DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.secondaryPowerBar) or {}

    if resource == "STAGGER" then
        local stagger = UnitStagger("player") or 0
        local maxHealth = UnitHealthMax("player") or 1
        return maxHealth, maxHealth, stagger, stagger, "number"
    end

    if resource == "SOUL" then
        -- DH 포식 Soul Fragments (BCM 방식: GetSpellCastCount → StatusBar에 직접 전달)
        -- GetSpellCastCount는 전투 중 secret value를 반환할 수 있음
        -- secret value는 StatusBar:SetValue()에 직접 넘기면 Blizzard 위젯이 처리함

        -- Dynamic max based on Metamorphosis and Soul Glutton talent
        local isInMeta = C_UnitAuras.GetPlayerAuraBySpellID(1217607) ~= nil
        local hasSoulGlutton = C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(1247534)
        local max
        if isInMeta then
            max = 40
        elseif hasSoulGlutton then
            max = 35
        else
            max = 50
        end

        -- Primary: C_Spell.GetSpellCastCount (may return secret value in combat)
        local current = C_Spell.GetSpellCastCount(1217605)

        -- current는 secret value일 수 있으므로 비교/연산 금지
        -- "SOUL_SECRET" 타입으로 반환하여 호출자가 secret-safe 처리
        return max, max, current, current, "SOUL_SECRET"
    end

    if resource == "MAELSTROM_WEAPON" then
        -- Enhancement Shaman Maelstrom Weapon buff tracking
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(344179) -- Maelstrom Weapon
        local current = auraData and auraData.applications or 0
        local max = 10

        return max, max, current, current, "number"
    end

    if resource == Enum.PowerType.Runes then
        local current = 0
        local max = UnitPowerMax("player", resource)
        if max <= 0 then return nil, nil, nil, nil, nil end

        for i = 1, max do
            local runeReady = select(3, GetRuneCooldown(i))
            if runeReady then
                current = current + 1
            end
        end

        if cfg.textFormat == "Percent" or cfg.textFormat == "Percent%" then
            return max, max, current, math.floor((current / max) * 100 + 0.5), "percent"
        else
            return max, max, current, current, "number"
        end
    end

    if resource == Enum.PowerType.SoulShards then
        local current = UnitPower("player", resource, true)
        local max = UnitPowerMax("player", resource, true)
        if max <= 0 then return nil, nil, nil, nil, nil end

        if cfg.textFormat == "Percent" or cfg.textFormat == "Percent%" then
            return max, max, current, math.floor((current / max) * 100 + 0.5), "percent"
        else
            return max, max / 10, current, current / 10, "number"
        end
    end

    -- Default case for all other power types (ComboPoints, Chi, HolyPower, Mana, etc.)
    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)
        if max <= 0 then return nil, nil, nil, nil, nil end

    if cfg.showManaAsPercent and resource == Enum.PowerType.Mana then
        local percent = SafeUnitPowerPercent("player", resource, false)
        if percent ~= nil then
            return max, max, current, percent, "percent"
        end
        return max, max, current, math.floor((current / max) * 100 + 0.5), "percent"
    end

    return max, max, current, current, "number"
end

-- Export functions
DDingUI.ResourceBars.GetPrimaryResource = GetPrimaryResource
DDingUI.ResourceBars.GetSecondaryResource = GetSecondaryResource
DDingUI.ResourceBars.GetResourceColor = GetResourceColor
DDingUI.ResourceBars.GetPrimaryResourceValue = GetPrimaryResourceValue
DDingUI.ResourceBars.GetSecondaryResourceValue = GetSecondaryResourceValue
DDingUI.ResourceBars.GetChargedPowerPoints = GetChargedPowerPoints

-- Debug slash command
SLASH_DDUIRES1 = "/dduires"
SlashCmdList["DDUIRES"] = function()
    local playerClass = select(2, UnitClass("player"))
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec)
    local primary = GetPrimaryResource()
    local secondary = GetSecondaryResource()

    print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Resource Debug") -- [STYLE]
    print("  Class: " .. tostring(playerClass))
    print("  Spec Index: " .. tostring(spec))
    print("  Spec ID: " .. tostring(specID))
    print("  Primary: " .. tostring(primary))
    print("  Secondary: " .. tostring(secondary))

    if secondary then
        local max, maxDisp, cur, disp, valType = GetSecondaryResourceValue(secondary, {})
        print("  Secondary Value: " .. tostring(disp) .. "/" .. tostring(maxDisp) .. " (" .. tostring(valType) .. ")")
    end
end

