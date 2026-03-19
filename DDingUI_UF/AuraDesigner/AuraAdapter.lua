--[[
	ddingUI UnitFrames
	AuraDesigner/AuraAdapter.lua — C_UnitAuras API bridge + secret aura integration
	
	[REFACTOR] DandersFrames 패턴: UNIT_AURA incremental 캐시 기반.
	전체 스캔은 isFullUpdate 또는 초기 로딩 시에만 수행.
	일반 업데이트는 addedAuras/removedAuraInstanceIDs/updatedAuraInstanceIDs로 패치.
]]

local _, ns = ...

local pairs, ipairs, wipe, type, next = pairs, ipairs, wipe, type, next
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

local reverseSpellLookup = {}

local function BuildReverseLookup(spec)
	if reverseSpellLookup[spec] then return reverseSpellLookup[spec] end

	local lookup = {}
	local AD = ns.AuraDesigner

	local spellIDs = AD.SpellIDs and AD.SpellIDs[spec]
	if spellIDs then
		for auraName, spellId in pairs(spellIDs) do
			lookup[spellId] = auraName
		end
	end

	local selfOnly = AD.SelfOnlySpellIDs and AD.SelfOnlySpellIDs[spec]
	if selfOnly then
		for spellId, auraName in pairs(selfOnly) do
			lookup[spellId] = auraName
		end
	end

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
-- [REFACTOR] expectedAuras 캐시 (spec 변경 시 1회 구축)
-- ============================================================

local expectedAurasCache = {} -- spec → { [auraName] = true }

local function GetExpectedAuras(spec)
	if expectedAurasCache[spec] then return expectedAurasCache[spec] end
	local AD = ns.AuraDesigner
	local TrackableAuras = AD.TrackableAuras and AD.TrackableAuras[spec]
	if not TrackableAuras then return {} end
	local expected = {}
	for _, info in ipairs(TrackableAuras) do
		expected[info.name] = true
	end
	expectedAurasCache[spec] = expected
	return expected
end

-- ============================================================
-- AURA NORMALIZATION (object pool)
-- ============================================================

local normalizedPool = {}
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
-- [REFACTOR] INCREMENTAL AURA CACHE (DandersFrames 패턴)
-- ============================================================

-- auraCache[unit] = { [auraInstanceID] = { auraName, normalized } }
-- matchedCache[unit] = { [auraName] = normalizedAura }  (최종 결과)
local auraCache = {}     -- unit → { [auraInstanceID] = normalizedAura }
local matchedCache = {}  -- unit → { [auraName] = normalizedAura }

-- [REFACTOR] 전체 스캔 (isFullUpdate 또는 초기화 시)
local function FullScan(unit, spec, lookup, expectedAuras)
	-- 기존 캐시 정리
	if auraCache[unit] then
		for _, v in pairs(auraCache[unit]) do ReleaseNormalized(v) end
		wipe(auraCache[unit])
	else
		auraCache[unit] = {}
	end
	if matchedCache[unit] then
		wipe(matchedCache[unit])
	else
		matchedCache[unit] = {}
	end

	local cache = auraCache[unit]
	local matched = matchedCache[unit]

	-- Phase 1: Non-secret auras
	local auras = C_UnitAuras.GetUnitAuras and C_UnitAuras.GetUnitAuras(unit, "PLAYER|HELPFUL", 100)
	if auras then
		for _, auraData in ipairs(auras) do
			local spellId = auraData.spellId
			local isSecret = issecretvalue(spellId)

			if not isSecret and spellId then
				local auraName = lookup[spellId]
				if auraName and expectedAuras[auraName] then
					local norm = NormalizeAura(auraName, auraData, auraData.auraInstanceID, false)
					cache[auraData.auraInstanceID] = norm
					if not matched[auraName] then
						matched[auraName] = norm
					end
				end
			end
		end
	end

	-- Phase 2: Secret auras
	local AD = ns.AuraDesigner
	local SecretAurasModule = AD.SecretAuras
	if SecretAurasModule then
		local secretResults = SecretAurasModule:GetUnitAuras(unit, spec)
		if secretResults then
			for auraName, secretData in pairs(secretResults) do
				if expectedAuras[auraName] and not matched[auraName] then
					matched[auraName] = secretData
					secretData.isSecret = true
					if secretData.auraInstanceID then
						cache[secretData.auraInstanceID] = secretData
					end
				end
			end
		end
	end
end

-- ============================================================
-- [REFACTOR] OnUnitAuraEvent: incremental 캐시 업데이트
-- P2 UNIT_AURA 핸들러에서 호출됨
-- ============================================================

function Adapter:OnUnitAuraEvent(unit, updateInfo, spec)
	if not unit or not updateInfo then return false end
	if not spec then
		local Engine = ns.AuraDesigner.Engine
		spec = Engine and Engine:ResolveSpec()
	end
	if not spec then return false end

	local lookup = BuildReverseLookup(spec)
	local expectedAuras = GetExpectedAuras(spec)
	if not next(expectedAuras) then return false end

	-- isFullUpdate → 전체 재스캔
	if updateInfo.isFullUpdate then
		FullScan(unit, spec, lookup, expectedAuras)
		return true
	end

	-- 캐시 초기화 (아직 없으면 full scan)
	if not auraCache[unit] then
		FullScan(unit, spec, lookup, expectedAuras)
		return true
	end

	local cache = auraCache[unit]
	local matched = matchedCache[unit]
	if not matched then
		matched = {}
		matchedCache[unit] = matched
	end
	local changed = false

	-- 제거된 오라
	if updateInfo.removedAuraInstanceIDs then
		for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
			local norm = cache[auraInstanceID]
			if norm then
				-- matchedCache에서도 제거 (같은 auraName의 다른 인스턴스가 있을 수 있음)
				if norm.name and matched[norm.name] == norm then
					matched[norm.name] = nil
				end
				ReleaseNormalized(norm)
				cache[auraInstanceID] = nil
				changed = true
			end
		end
	end

	-- 추가된 오라
	if updateInfo.addedAuras then
		for _, auraData in next, updateInfo.addedAuras do
			if auraData.auraInstanceID then
				local spellId = auraData.spellId
				local isSecret = issecretvalue(spellId)

				if not isSecret and spellId then
					local auraName = lookup[spellId]
					if auraName and expectedAuras[auraName] then
						local norm = NormalizeAura(auraName, auraData, auraData.auraInstanceID, false)
						-- 기존 인스턴스 교체
						if cache[auraData.auraInstanceID] then
							ReleaseNormalized(cache[auraData.auraInstanceID])
						end
						cache[auraData.auraInstanceID] = norm
						matched[auraName] = norm
						changed = true
					end
				end
			end
		end
	end

	-- 업데이트된 오라 (stacks/duration 변경)
	if updateInfo.updatedAuraInstanceIDs then
		for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
			local existing = cache[auraInstanceID]
			if existing then
				-- 최신 데이터로 갱신
				local auraData = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
				if auraData then
					existing.duration       = auraData.duration
					existing.expirationTime = auraData.expirationTime
					existing.stacks         = auraData.applications or existing.stacks
					changed = true
				end
			end
		end
	end

	-- 제거 후 matchedCache 재구축 (같은 auraName의 다른 인스턴스가 있는 경우)
	if changed then
		-- matchedCache에 hole이 생겼으면 cache에서 재매칭
		for auraInstanceID, norm in pairs(cache) do
			if norm.name and not matched[norm.name] then
				matched[norm.name] = norm
			end
		end
	end

	return changed
end

-- ============================================================
-- CORE: GetUnitAuras (캐시 읽기 전용 — 전체 스캔 불필요)
-- ============================================================

function Adapter:GetUnitAuras(unit, spec)
	if not unit or not UnitExists(unit) then return {} end
	if not spec then return {} end

	-- 캐시가 없으면 full scan (최초 호출 또는 캐시 미스)
	if not matchedCache[unit] then
		local lookup = BuildReverseLookup(spec)
		local expectedAuras = GetExpectedAuras(spec)
		FullScan(unit, spec, lookup, expectedAuras)
	end

	return matchedCache[unit] or {}
end

-- ============================================================
-- PLAYER SPEC DETECTION
-- ============================================================

function Adapter:GetPlayerSpec()
	local SecretAurasModule = ns.AuraDesigner.SecretAuras
	if SecretAurasModule and SecretAurasModule.GetPlayerSpec then
		return SecretAurasModule:GetPlayerSpec()
	end

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
		if auraCache[unit] then
			for _, v in pairs(auraCache[unit]) do ReleaseNormalized(v) end
			wipe(auraCache[unit])
		end
		if matchedCache[unit] then wipe(matchedCache[unit]) end
	else
		for u in pairs(auraCache) do
			for _, v in pairs(auraCache[u]) do ReleaseNormalized(v) end
			wipe(auraCache[u])
		end
		wipe(auraCache)
		for u in pairs(matchedCache) do wipe(matchedCache[u]) end
		wipe(matchedCache)
	end
end

function Adapter:InvalidateReverseLookup()
	wipe(reverseSpellLookup)
	wipe(expectedAurasCache) -- expectedAuras도 리빌드 필요
end
