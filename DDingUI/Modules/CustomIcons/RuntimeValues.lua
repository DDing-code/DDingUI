local ns = select(2, ...)
local DDingUI = ns.Addon
local canaccessvalue = canaccessvalue or function() return true end

local RuntimeValues = {}
DDingUI.CustomIconRuntimeValues = RuntimeValues

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

RuntimeValues.GetAuraFieldSafe = GetAuraFieldSafe
RuntimeValues.GetAuraSpellIDSafe = GetAuraSpellIDSafe
RuntimeValues.SafeNumber = SafeNumber
RuntimeValues.GetAuraNumberFieldSafe = GetAuraNumberFieldSafe
RuntimeValues.MaxSafeNumber = MaxSafeNumber
RuntimeValues.EvalDesatFromDurObj = EvalDesatFromDurObj
RuntimeValues.GetRealSpellCooldownDuration = GetRealSpellCooldownDuration
RuntimeValues.IsCooldownEnabled = IsCooldownEnabled
RuntimeValues.NormalizeCooldownSpan = NormalizeCooldownSpan
