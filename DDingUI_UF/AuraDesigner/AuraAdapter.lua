--[[
	ddingUI UnitFrames
	AuraDesigner/AuraAdapter.lua — C_UnitAuras API bridge + secret aura integration
	
	DandersFrames AuraAdapter.lua 패턴 기반.
	C_UnitAuras API를 통해 유닛 오라를 수집하고,
	정규화된 데이터를 반환합니다. Secret 오라는 SecretAuras 모듈과 통합됩니다.
]]

local _, ns = ...

local pairs, ipairs, wipe, type = pairs, ipairs, wipe, type
local issecretvalue = issecretvalue or function() return false end
local canaccesstable = canaccesstable or function() return true end

local C_UnitAuras = C_UnitAuras
local UnitExists = UnitExists
local UnitClassBase = UnitClassBase
local GetSpecialization = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID

ns.AuraDesigner = ns.AuraDesigner or {}
local Adapter = {}
ns.AuraDesigner.Adapter = Adapter

-- ============================================================
-- REVERSE SPELL ID LOOKUP
-- ============================================================

-- Build runtime lookup: spellID → auraName (per spec)
local reverseSpellLookup = {}

local function BuildReverseLookup(spec)
	if reverseSpellLookup[spec] then return reverseSpellLookup[spec] end

	local lookup = {}
	local AD = ns.AuraDesigner

	-- Main spell IDs
	local spellIDs = AD.SpellIDs and AD.SpellIDs[spec]
	if spellIDs then
		for auraName, spellId in pairs(spellIDs) do
			lookup[spellId] = auraName
		end
	end

	-- Self-only spell IDs (caster buffs)
	local selfOnly = AD.SelfOnlySpellIDs and AD.SelfOnlySpellIDs[spec]
	if selfOnly then
		for spellId, auraName in pairs(selfOnly) do
			lookup[spellId] = auraName
		end
	end

	-- Alternate spell IDs (merged)
	local alts = AD.AlternateSpellIDs and AD.AlternateSpellIDs[spec]
	if alts then
		for spellId, auraName in pairs(alts) do
			if not lookup[spellId] then
				lookup[spellId] = auraName
			end
		end
	end

	reverseSpellLookup[spec] = lookup
	return lookup
end

-- ============================================================
-- ICON LOOKUP
-- ============================================================

local function GetIconTexture(auraName)
	local AD = ns.AuraDesigner
	return AD.IconTextures and AD.IconTextures[auraName]
end

-- ============================================================
-- AURA NORMALIZATION
-- ============================================================

local normalizedPool = {} -- pooled tables
local poolCount = 0

local function AcquireNormalized()
	if poolCount > 0 then
		local t = normalizedPool[poolCount]
		normalizedPool[poolCount] = nil
		poolCount = poolCount - 1
		wipe(t)
		return t
	end
	return {}
end

local function ReleaseNormalized(t)
	if not t then return end
	poolCount = poolCount + 1
	normalizedPool[poolCount] = t
end

local function NormalizeAura(auraName, auraData, auraInstanceID, isSecret)
	local t = AcquireNormalized()
	t.name           = auraName
	t.spellId        = (not isSecret and auraData.spellId) or 0
	t.icon           = GetIconTexture(auraName) or auraData.icon
	t.duration       = auraData.duration
	t.expirationTime = auraData.expirationTime
	t.stacks         = auraData.applications or 0
	t.caster         = auraData.sourceUnit
	t.auraInstanceID = auraInstanceID
	t.isSecret       = isSecret or false
	return t
end

-- ============================================================
-- CORE: GetUnitAuras
-- ============================================================

-- resultCache: unit → { [auraName] = normalizedAura }
-- Recycled between calls to reduce GC pressure
local resultCache = {}

function Adapter:GetUnitAuras(unit, spec)
	if not unit or not UnitExists(unit) then return {} end
	if not spec then return {} end

	-- Release old
	if resultCache[unit] then
		for _, v in pairs(resultCache[unit]) do
			ReleaseNormalized(v)
		end
		wipe(resultCache[unit])
	else
		resultCache[unit] = {}
	end

	local result = resultCache[unit]
	local lookup = BuildReverseLookup(spec)
	local AD = ns.AuraDesigner
	local TrackableAuras = AD.TrackableAuras and AD.TrackableAuras[spec]
	if not TrackableAuras then return result end

	-- Build whitelist of expected aura names for this spec
	local expectedAuras = {}
	for _, info in ipairs(TrackableAuras) do
		expectedAuras[info.name] = true
	end

	-- Phase 1: Non-secret auras (spellID readable)
	local auras = C_UnitAuras.GetUnitAuras and C_UnitAuras.GetUnitAuras(unit, "PLAYER|HELPFUL", 100)
	if auras then
		for _, auraData in ipairs(auras) do
			local spellId = auraData.spellId
			local isSecret = issecretvalue(spellId)

			if not isSecret and spellId then
				local auraName = lookup[spellId]
				if auraName and expectedAuras[auraName] and not result[auraName] then
					result[auraName] = NormalizeAura(auraName, auraData, auraData.auraInstanceID, false)
				end
			end
		end
	end

	-- Phase 2: Secret auras (fingerprint-matched)
	local SecretAurasModule = AD.SecretAuras
	if SecretAurasModule then
		local secretResults = SecretAurasModule:GetUnitAuras(unit, spec)
		if secretResults then
			for auraName, secretData in pairs(secretResults) do
				if expectedAuras[auraName] and not result[auraName] then
					result[auraName] = secretData
					secretData.isSecret = true
				end
			end
		end
	end

	return result
end

-- ============================================================
-- PLAYER SPEC DETECTION
-- ============================================================

function Adapter:GetPlayerSpec()
	local SecretAurasModule = ns.AuraDesigner.SecretAuras
	if SecretAurasModule and SecretAurasModule.GetPlayerSpec then
		return SecretAurasModule:GetPlayerSpec()
	end

	-- Fallback
	if not UnitClassBase or not GetSpecialization then return nil end
	local class = UnitClassBase("player")
	local specNum = GetSpecialization()
	if class and specNum then
		local key = class .. "_" .. specNum
		local AD = ns.AuraDesigner
		return AD.SpecMap and AD.SpecMap[key]
	end
	return nil
end

-- ============================================================
-- CACHE MANAGEMENT
-- ============================================================

function Adapter:FlushCache(unit)
	if unit then
		if resultCache[unit] then
			for _, v in pairs(resultCache[unit]) do
				ReleaseNormalized(v)
			end
			wipe(resultCache[unit])
		end
	else
		for u in pairs(resultCache) do
			for _, v in pairs(resultCache[u]) do
				ReleaseNormalized(v)
			end
			wipe(resultCache[u])
		end
	end
end

function Adapter:InvalidateReverseLookup()
	wipe(reverseSpellLookup)
end
