--[[
	ddingUI UnitFrames
	AuraDesigner/SecretAuras.lua — Secret aura fingerprint tracking
	
	DandersFrames SecretAuras.lua 패턴 기반 (Harrek's ARF 크레딧).
	4-filter 시그니처로 secret spell ID 오라를 식별합니다.
]]

local _, ns = ...

local pairs, ipairs, wipe, type = pairs, ipairs, wipe, type
local GetTime = GetTime
local issecretvalue = issecretvalue or function() return false end
local canaccesstable = canaccesstable or function() return true end

local C_UnitAuras = C_UnitAuras
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitClassBase = UnitClassBase
local GetSpecialization = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)

-- ============================================================
-- MODULE TABLE
-- ============================================================

ns.AuraDesigner = ns.AuraDesigner or {}
local SecretAuras = {}
ns.AuraDesigner.SecretAuras = SecretAuras

-- ============================================================
-- RUNTIME STATE
-- ============================================================

local state = {
	casts   = {},       -- [castSpellId] = GetTime() timestamp
	auras   = {},       -- [unit] = { [auraInstanceID] = "AuraName" }
	extras  = {},       -- spec-specific disambiguation state
	spec    = nil,      -- current player spec key
}

local SecretAuraInfo    -- ns.AuraDesigner.SecretAuraInfo
local SpellIDs          -- ns.AuraDesigner.SpellIDs
local IconTextures      -- ns.AuraDesigner.IconTextures

-- Signature lookup cache
local signatureCache = {}

-- ============================================================
-- FILTER STRINGS
-- ============================================================

local FILTER_RAID     = "PLAYER|HELPFUL|RAID"
local FILTER_RIC      = "PLAYER|HELPFUL|RAID_IN_COMBAT"
local FILTER_EXT      = "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE"
local FILTER_DISP     = "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE"

-- ============================================================
-- SIGNATURE HELPERS
-- ============================================================

local function MakeAuraSignature(passesRaid, passesRic, passesExt, passesDisp)
	return (passesRaid and "1" or "0") .. ":" .. (passesRic and "1" or "0") .. ":"
		.. (passesExt and "1" or "0") .. ":" .. (passesDisp and "1" or "0")
end

local function GetAuraSignatures(spec)
	if signatureCache[spec] then return signatureCache[spec] end

	local signatures = {}
	local specData = SecretAuraInfo and SecretAuraInfo[spec]
	if specData and specData.auras then
		for auraName, auraData in pairs(specData.auras) do
			local sig = auraData.signature
			if sig and sig ~= "" then
				signatures[sig] = auraName
			end
		end
	end
	signatureCache[spec] = signatures
	return signatures
end

local function IsAuraFromPlayer(unit, auraInstanceID)
	if not IsAuraFilteredOutByInstanceID then return false end
	local passesRaid = not IsAuraFilteredOutByInstanceID(unit, auraInstanceID, FILTER_RAID)
	local passesRic  = not IsAuraFilteredOutByInstanceID(unit, auraInstanceID, FILTER_RIC)
	return passesRaid or passesRic
end

local function MatchAuraSignature(unit, aura, spec)
	if not IsAuraFilteredOutByInstanceID then return nil end
	if not aura or not aura.auraInstanceID then return nil end

	-- Skip non-secret auras
	if canaccesstable(aura) and not issecretvalue(aura.spellId) then
		return nil
	end

	local instanceID = aura.auraInstanceID

	-- Must pass at least RAID or RIC
	local passesRaid = not IsAuraFilteredOutByInstanceID(unit, instanceID, FILTER_RAID)
	local passesRic  = not IsAuraFilteredOutByInstanceID(unit, instanceID, FILTER_RIC)
	if not (passesRaid or passesRic) then return nil end

	local passesExt  = not IsAuraFilteredOutByInstanceID(unit, instanceID, FILTER_EXT)
	local passesDisp = not IsAuraFilteredOutByInstanceID(unit, instanceID, FILTER_DISP)

	local signature = MakeAuraSignature(passesRaid, passesRic, passesExt, passesDisp)
	local signatures = GetAuraSignatures(spec)
	return signatures[signature]
end

-- ============================================================
-- SPEC-SPECIFIC DISAMBIGUATION ENGINES
-- ============================================================

-- Preservation Evoker: VerdantEmbrace vs Lifebind
local function ParsePreservationEvokerBuffs(unit, addedAuras)
	if not addedAuras then return end

	local unitAuras = state.auras[unit]
	if not unitAuras then return end

	if not state.extras.ve then state.extras.ve = {} end

	for _, aura in ipairs(addedAuras) do
		if IsAuraFromPlayer(unit, aura.auraInstanceID) and unitAuras[aura.auraInstanceID] == "VerdantEmbrace" then
			if not state.extras.ve[unit] then
				state.extras.ve[unit] = { buffs = {}, timer = false }
			end
			local veTable = state.extras.ve[unit]
			veTable.buffs[#veTable.buffs + 1] = aura.auraInstanceID
			if not veTable.timer then
				veTable.timer = true
				C_Timer.After(0.1, function()
					if #veTable.buffs == 2 then
						unitAuras[veTable.buffs[1]] = "Lifebind"
					elseif #veTable.buffs == 1 then
						if UnitIsUnit(unit, "player") then
							unitAuras[veTable.buffs[1]] = "Lifebind"
						end
					end
					wipe(veTable.buffs)
					veTable.timer = false
				end)
			end
		end
	end
end

-- Augmentation Evoker: EbonMight vs SensePower
local function ParseAugmentationEvokerBuffs(unit, addedAuras)
	if not addedAuras then return end
	if not UnitIsUnit(unit, "player") then return end

	local unitAuras = state.auras[unit]
	if not unitAuras then return end

	for _, aura in ipairs(addedAuras) do
		if unitAuras[aura.auraInstanceID] == "SensePower" then
			unitAuras[aura.auraInstanceID] = "EbonMight"
		end
	end
end

local specEngines = {
	PreservationEvoker = ParsePreservationEvokerBuffs,
	AugmentationEvoker = ParseAugmentationEvokerBuffs,
}

-- ============================================================
-- UNIT INITIALIZATION
-- ============================================================

local function InitUnit(unit, spec)
	if not GetUnitAuras then return end
	if not SecretAuraInfo or not SecretAuraInfo[spec] then return end

	state.auras[unit] = state.auras[unit] or {}
	local unitAuras = state.auras[unit]

	local auras = GetUnitAuras(unit, "PLAYER|HELPFUL", 100)
	if not auras then return end

	for _, auraData in ipairs(auras) do
		local matched = MatchAuraSignature(unit, auraData, spec)
		if matched then
			unitAuras[auraData.auraInstanceID] = matched
		end
	end

	local engine = specEngines[spec]
	if engine then
		local fakeAdded = {}
		for instanceID in pairs(unitAuras) do
			fakeAdded[#fakeAdded + 1] = { auraInstanceID = instanceID }
		end
		if #fakeAdded > 0 then
			engine(unit, fakeAdded)
		end
	end
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================

local eventFrame = CreateFrame("Frame")

local function UpdatePlayerSpec()
	if not UnitClassBase or not GetSpecialization then return end
	local class = UnitClassBase("player")
	local specNum = GetSpecialization()
	if class and specNum then
		local key = class .. "_" .. specNum
		local AD = ns.AuraDesigner
		state.spec = AD and AD.SpecMap and AD.SpecMap[key] or nil
	end
end

local function OnEvent(self, event, ...)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, _, spellId = ...
		if not state.spec or not spellId then return end
		local info = SecretAuraInfo and SecretAuraInfo[state.spec]
		if info and info.casts and info.casts[spellId] then
			state.casts[spellId] = GetTime()
		end

	elseif event == "UNIT_AURA" then
		local unit, updateInfo = ...
		if not state.spec or not unit then return end
		if not SecretAuraInfo or not SecretAuraInfo[state.spec] then return end
		if not UnitExists(unit) then return end

		if not state.auras[unit] then
			InitUnit(unit, state.spec)
			return
		end

		local unitAuras = state.auras[unit]

		-- Remove expired
		if updateInfo and updateInfo.removedAuraInstanceIDs then
			for _, auraId in ipairs(updateInfo.removedAuraInstanceIDs) do
				unitAuras[auraId] = nil
			end
		end

		-- Match new auras
		if updateInfo and updateInfo.addedAuras then
			for _, aura in ipairs(updateInfo.addedAuras) do
				if not unitAuras[aura.auraInstanceID] then
					local matched = MatchAuraSignature(unit, aura, state.spec)
					if matched then
						unitAuras[aura.auraInstanceID] = matched
					end
				end
			end
		end

		-- Disambiguation
		local engine = specEngines[state.spec]
		if engine and updateInfo and updateInfo.addedAuras then
			engine(unit, updateInfo.addedAuras)
		end

	elseif event == "GROUP_ROSTER_UPDATE" then
		for unit in pairs(state.auras) do
			if not UnitExists(unit) then
				state.auras[unit] = nil
			end
		end

	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		UpdatePlayerSpec()
		wipe(state.casts)
		wipe(state.auras)
		wipe(state.extras)
		wipe(signatureCache)

	elseif event == "PLAYER_LOGIN" then
		local AD = ns.AuraDesigner
		SecretAuraInfo = AD and AD.SecretAuraInfo
		SpellIDs       = AD and AD.SpellIDs
		IconTextures   = AD and AD.IconTextures
		UpdatePlayerSpec()
	end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

-- ============================================================
-- PUBLIC API
-- ============================================================

function SecretAuras:GetUnitAuras(unit, spec)
	if not unit or not spec then return {} end
	if not SecretAuraInfo or not SecretAuraInfo[spec] then return {} end

	if not state.auras[unit] then
		InitUnit(unit, spec)
	end

	local unitAuras = state.auras[unit]
	if not unitAuras then return {} end

	local result = {}
	local spellIDs = SpellIDs and SpellIDs[spec]

	for auraInstanceID, auraName in pairs(unitAuras) do
		local live = GetAuraDataByAuraInstanceID and GetAuraDataByAuraInstanceID(unit, auraInstanceID)
		if live then
			local knownSpellId = spellIDs and spellIDs[auraName]
			local iconTex = IconTextures and IconTextures[auraName]
			result[auraName] = {
				spellId         = knownSpellId or 0,
				icon            = iconTex or (live.icon),
				duration        = live.duration,
				expirationTime  = live.expirationTime,
				stacks          = live.applications,
				caster          = live.sourceUnit,
				auraInstanceID  = auraInstanceID,
				secret          = true,
			}
		else
			unitAuras[auraInstanceID] = nil
		end
	end

	return result
end

function SecretAuras:MatchAura(unit, auraData, spec)
	return MatchAuraSignature(unit, auraData, spec)
end

function SecretAuras:RecordMatch(unit, auraInstanceID, auraName)
	if not state.auras[unit] then state.auras[unit] = {} end
	state.auras[unit][auraInstanceID] = auraName
end

function SecretAuras:GetPlayerSpec()
	return state.spec
end
