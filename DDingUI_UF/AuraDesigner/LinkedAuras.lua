--[[
	ddingUI UnitFrames
	AuraDesigner/LinkedAuras.lua — 추론 기반 오라 추적
	
	DandersFrames LinkedAuras.lua 패턴 기반.
	특정 오라가 직접 관찰 불가능할 때, 관련 오라나 캐스트로부터 추론.
	예: 공생 관계 — 시전자에게 474754가 있으면 대상에게 474750/474760 표시
]]

local _, ns = ...

local pairs, ipairs = pairs, ipairs
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local GetTime = GetTime

local C_UnitAuras = C_UnitAuras
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras

-- Secret value handling (Midnight 12.0+ safe — DandersFrames pattern)
local issecretvalue = issecretvalue or function() return false end

ns.AuraDesigner = ns.AuraDesigner or {}
local LinkedAuras = {}
ns.AuraDesigner.LinkedAuras = LinkedAuras

-- ============================================================
-- STATE
-- ============================================================

local state = {
	links = {},  -- [unit] = { [auraName] = { spellId, icon, duration, expirationTime, stacks, sourceUnit } }
}

-- ============================================================
-- PROCESSING
-- ============================================================

-- Process linked aura rules for a unit
-- Returns: table of extra aura data that should be merged into the adapter result
function LinkedAuras:ProcessUnit(unit, spec, existingAuras)
	local AD = ns.AuraDesigner
	local rules = AD.LinkedAuraRules and AD.LinkedAuraRules[spec]
	if not rules then return nil end

	local extras = nil

	for auraName, rule in pairs(rules) do
		if rule.type == "caster_to_target" then
			-- 시전자(플레이어)에게 sourceSpellID가 있으면,
			-- 해당 유닛에서 targetSpellIDs 중 하나를 찾아 auraName으로 표시
			local hasSource = false
			if existingAuras and existingAuras[auraName] then
				hasSource = true
			else
				-- 플레이어에서 직접 확인
				if GetUnitAuras and UnitExists("player") then
					local playerAuras = GetUnitAuras("player", "HELPFUL", 100)
					if playerAuras then
						for _, aData in ipairs(playerAuras) do
							local sid = aData.spellId
							if sid and not issecretvalue(sid) and sid == rule.sourceSpellID then
								hasSource = true
								break
							end
						end
					end
				end
			end

			if hasSource and rule.targetSpellIDs then
				-- 대상 유닛에서 targetSpellIDs 검색
				if UnitExists(unit) and not UnitIsUnit(unit, "player") and GetUnitAuras then
					local unitAuras = GetUnitAuras(unit, "HELPFUL", 100)
					if unitAuras then
						for _, aData in ipairs(unitAuras) do
							for _, targetId in ipairs(rule.targetSpellIDs) do
								local sid = aData.spellId
								if sid and not issecretvalue(sid) and sid == targetId then
									if not extras then extras = {} end
									local iconTex = AD.IconTextures and AD.IconTextures[auraName]
									extras[auraName] = {
										spellId = targetId,
										icon = iconTex or aData.icon,
										duration = aData.duration,
										expirationTime = aData.expirationTime,
										stacks = aData.applications or 0,
										caster = aData.sourceUnit,
										auraInstanceID = aData.auraInstanceID,
										isSecret = false,
										isLinked = true,
									}
									break
								end
							end
							if extras and extras[auraName] then break end
						end
					end
				end
			end
		end
	end

	return extras
end

-- ============================================================
-- CACHE MANAGEMENT
-- ============================================================

function LinkedAuras:FlushCache(unit)
	if unit then
		state.links[unit] = nil
	else
		wipe(state.links)
	end
end
