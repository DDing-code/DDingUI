from pathlib import Path


aura_path = Path('DDingUI/Modules/ResourceBars/TrackedAuraLegacyFallbackDriver.lua')
duration_path = Path('DDingUI/Modules/ResourceBars/TrackedAuraLegacyDurationDriver.lua')
bar_path = Path('DDingUI/Modules/ResourceBars/BuffTrackerBar.lua')

aura = aura_path.read_text(encoding='utf-8')
duration = duration_path.read_text(encoding='utf-8')
bar = bar_path.read_text(encoding='utf-8')


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1, got {count}')
    return text.replace(old, new, 1)


def replace_slice(text, start_marker, end_marker, replacement, label):
    if text.count(start_marker) != 1:
        raise SystemExit(f'{label} start count={text.count(start_marker)}')
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[:start] + replacement + text[end:]


# Central public wrappers for every BuffTracker C_UnitAuras call site.
aura_marker = '''function Driver.GetAuraInstanceCacheKey(value)
    if Driver.IsSecretValue(value) then return "secret" end
    if type(value) == "number" and value ~= 0 then return value end
    return nil
end

'''
aura_insert = aura_marker + '''function Driver.GetPlayerAuraBySpellID(spellID)
    spellID = tonumber(spellID) or 0
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID
        or not Driver.IsAccessibleNumber(spellID) or spellID <= 0
    then
        return nil
    end

    local auraData
    local ok = pcall(function()
        auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end)
    if not ok then return nil end
    return auraData
end

function Driver.GetAuraDataByInstance(unit, auraInstanceID)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID
        or not Driver.HasAuraInstanceID(auraInstanceID)
    then
        return nil
    end

    local auraData
    local ok = pcall(function()
        auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit or "player", auraInstanceID)
    end)
    if not ok then return nil end
    return auraData
end

function Driver.GetAuraDataAutoUnit(auraInstanceID)
    local auraData = Driver.GetAuraDataByInstance("player", auraInstanceID)
    if Driver.HasAuraResult(auraData) then
        return auraData, "player"
    end

    auraData = Driver.GetAuraDataByInstance("target", auraInstanceID)
    if Driver.HasAuraResult(auraData) then
        return auraData, "target"
    end
    return nil, nil
end

function Driver.GetAuraDataByIndex(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
    local auraData
    local ok = pcall(function()
        auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    end)
    if not ok then return nil end
    return auraData
end

'''
aura = replace_once(aura, aura_marker, aura_insert, 'aura API wrapper insertion')

# Reuse wrappers internally too.
aura = replace_once(
    aura,
    '    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)\n',
    '    local aura = Driver.GetPlayerAuraBySpellID(spellID)\n',
    'tracked player aura wrapper',
)
aura = aura.replace(
    'local aura = C_UnitAuras.GetAuraDataByIndex(',
    'local aura = Driver.GetAuraDataByIndex(',
)

# Duration timing reports whether unavailable timing was protected.
duration = replace_once(
    duration,
    '''local function IsPositivePlainNumber(value)
    return AuraDriver.IsAccessibleNumber(value) and value > 0
end

''',
    '''local function IsPositivePlainNumber(value)
    return AuraDriver.IsAccessibleNumber(value) and value > 0
end

local function IsProtectedNumber(value)
    if AuraDriver.IsSecretValue(value) then return true end
    return type(value) == "number" and not AuraDriver.IsAccessibleNumber(value)
end

''',
    'protected duration helper',
)

new_read_timing = '''function Driver.ReadTiming(unit, auraInstanceID)
    if not AuraDriver.HasAuraInstanceID(auraInstanceID)
        or not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID
    then
        return nil, nil, nil, false
    end

    local duration, expirationTime, remaining
    local protected = false
    local ok = pcall(function()
        local auraData = AuraDriver.GetAuraDataByInstance(unit or "player", auraInstanceID)
        if not AuraDriver.HasAuraResult(auraData) then return end
        if AuraDriver.IsSecretValue(auraData) then
            protected = true
            return
        end

        local rawDuration = auraData.duration
        local rawExpirationTime = auraData.expirationTime
        if IsProtectedNumber(rawDuration) or IsProtectedNumber(rawExpirationTime) then
            protected = true
            return
        end

        if IsPositivePlainNumber(rawDuration) then
            duration = rawDuration
        end
        if IsPositivePlainNumber(rawExpirationTime) then
            expirationTime = rawExpirationTime
        end
        if expirationTime then
            remaining = expirationTime - GetTime()
            if remaining < 0 then remaining = 0 end
        end
    end)
    if not ok then
        return nil, nil, nil, true
    end
    return duration, expirationTime, remaining, protected
end

'''
duration = replace_slice(
    duration,
    'function Driver.ReadTiming(unit, auraInstanceID)\n',
    '-- GetAuraDuration may return a protected number.',
    new_read_timing,
    'ReadTiming replacement',
)

# BuffTrackerBar no longer owns C_UnitAuras access.
bar = replace_once(bar, 'local C_UnitAuras = C_UnitAuras\n', '', 'remove C_UnitAuras local')
bar = replace_once(
    bar,
    '            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)\n',
    '            local auraData = LegacyAuraDriver.GetPlayerAuraBySpellID(spellID)\n',
    'auto detect spell aura',
)

auto_unit_old = '''        -- player 먼저 시도, 없으면 target 시도 (CDM 방식)
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
        local unit = "player"
        if not auraData then
            auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("target", auraInstanceID)
            unit = "target"
        end
'''
auto_unit_new = '''        -- player 먼저 시도, 없으면 target 시도 (fallback driver owns API access)
        local auraData, unit = LegacyAuraDriver.GetAuraDataAutoUnit(auraInstanceID)
'''
bar = replace_once(bar, auto_unit_old, auto_unit_new, 'auto detect instance aura')

# Dead local helper: no call sites remain.
bar = replace_slice(
    bar,
    '-- Get buff data by spell ID (uses GetPlayerAuraBySpellID to avoid secret value errors)\n',
    '-- barFillMode: "stacks" (기본) or "duration"\n',
    '',
    'dead GetBuffData helper',
)

bar = replace_once(
    bar,
    '        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(specCfg.spellID)\n',
    '        local auraData = LegacyAuraDriver.GetPlayerAuraBySpellID(specCfg.spellID)\n',
    'debug buff check',
)
bar = replace_once(
    bar,
    '        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")\n',
    '        local aura = LegacyAuraDriver.GetAuraDataByIndex("player", i, "HELPFUL")\n',
    'debug buff listing',
)

alert_replacement = '''local function GetAlertAuraTiming(hasData, auraInstanceID, unit)
    if not hasData or not HasAuraInstanceID(auraInstanceID) then return nil, nil, false end
    if IsSecretValue(auraInstanceID) then return nil, nil, true end

    local durationValue, _, remaining, protected = LegacyDurationDriver.ReadTiming(unit, auraInstanceID)
    if protected then return nil, nil, true end
    if not IsAccessibleNumber(remaining) or not IsAccessibleNumber(durationValue) then
        return nil, nil, false
    end
    return remaining, durationValue, false
end

'''
bar = replace_slice(
    bar,
    'local function GetAlertAuraTiming(hasData, auraInstanceID, unit)\n',
    '-- Evaluate all triggers for a tracked buff, return per-trigger results + combined result.\n',
    alert_replacement,
    'alert timing boundary',
)

bar = replace_once(
    bar,
    '        pcall(function() apiResult = C_UnitAuras.GetPlayerAuraBySpellID(cooldownID) ~= nil end)\n',
    '        pcall(function() apiResult = HasAuraResult(LegacyAuraDriver.GetPlayerAuraBySpellID(cooldownID)) end)\n',
    'debug API result',
)

aura_path.write_text(aura, encoding='utf-8')
duration_path.write_text(duration, encoding='utf-8')
bar_path.write_text(bar, encoding='utf-8')
