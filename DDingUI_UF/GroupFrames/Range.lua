--[[
	ddingUI UnitFrames
	GroupFrames/Range.lua — 스펙 기반 거리 체크

	DandersFrames Range.lua 패턴:
	- specSpells + classFallbacks 테이블
	- 6단계 우선순위: IsSpellInRange → CheckInteractDistance → UnitInRange
	- issecretvalue 방어
	- 공유 타이머 (0.5초 간격)
	- rangeCache per-unit 상태 저장
]]

local _, ns = ...
local GF = ns.GroupFrames

local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitCanAttack = UnitCanAttack
local InCombatLockdown = InCombatLockdown
local CheckInteractDistance = CheckInteractDistance
local UnitInRange = UnitInRange
local IsInGroup = IsInGroup     -- [PERF] rangeTimer 그룹 체크
local IsInRaid = IsInRaid       -- [PERF]
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local issecretvalue = issecretvalue
local SafeBool = ns.SafeBool  -- [REFACTOR] 통합 유틸리티
local pairs = pairs
local wipe = wipe

local C_Spell = C_Spell

-----------------------------------------------
-- Spec-Based Spell Table (DF 패턴)
-- specID → { friendly = spellID, hostile = spellID }
-----------------------------------------------

local specSpells = {
	-- Death Knight
	[250] = { friendly = 49016, hostile = 49998 },    -- Blood: Unholy Frenzy / Death Strike
	[251] = { friendly = nil,   hostile = 49020 },     -- Frost: / Obliterate
	[252] = { friendly = nil,   hostile = 55090 },     -- Unholy: / Scourge Strike

	-- Demon Hunter
	[577] = { friendly = nil,   hostile = 162794 },    -- Havoc: / Chaos Strike
	[581] = { friendly = nil,   hostile = 228477 },    -- Vengeance: / Soul Cleave

	-- Druid
	[102] = { friendly = 8936,  hostile = 190984 },    -- Balance: Regrowth / Solar Wrath
	[103] = { friendly = 8936,  hostile = 5221 },      -- Feral: Regrowth / Shred
	[104] = { friendly = 8936,  hostile = 33917 },     -- Guardian: Regrowth / Mangle
	[105] = { friendly = 8936,  hostile = 5176 },      -- Restoration: Regrowth / Wrath

	-- Evoker
	[1467] = { friendly = 361469, hostile = 362969 },  -- Devastation: Living Flame / Azure Strike
	[1468] = { friendly = 361469, hostile = 362969 },  -- Preservation: Living Flame / Azure Strike
	[1473] = { friendly = 361469, hostile = 362969 },  -- Augmentation: Living Flame / Azure Strike

	-- Hunter
	[253] = { friendly = nil,   hostile = 193455 },    -- Beast Mastery: / Cobra Shot
	[254] = { friendly = nil,   hostile = 185358 },    -- Marksmanship: / Arcane Shot
	[255] = { friendly = nil,   hostile = 259491 },    -- Survival: / Kill Command

	-- Mage
	[62]  = { friendly = nil,   hostile = 44425 },     -- Arcane: / Arcane Barrage
	[63]  = { friendly = nil,   hostile = 133 },       -- Fire: / Fireball
	[64]  = { friendly = nil,   hostile = 116 },       -- Frost: / Frostbolt

	-- Monk
	[268] = { friendly = 116670, hostile = 100780 },   -- Brewmaster: Vivify / Tiger Palm
	[270] = { friendly = 116670, hostile = 100780 },   -- Mistweaver: Vivify / Tiger Palm
	[269] = { friendly = 116670, hostile = 100780 },   -- Windwalker: Vivify / Tiger Palm

	-- Paladin
	[65]  = { friendly = 19750, hostile = 20473 },     -- Holy: Flash of Light / Holy Shock
	[66]  = { friendly = 19750, hostile = 35395 },     -- Protection: Flash of Light / Crusader Strike
	[70]  = { friendly = 19750, hostile = 35395 },     -- Retribution: Flash of Light / Crusader Strike

	-- Priest
	[256] = { friendly = 2061,  hostile = 585 },       -- Discipline: Flash Heal / Smite
	[257] = { friendly = 2061,  hostile = 585 },       -- Holy: Flash Heal / Smite
	[258] = { friendly = 2061,  hostile = 8092 },      -- Shadow: Flash Heal / Mind Blast

	-- Rogue
	[259] = { friendly = nil,   hostile = 1752 },      -- Assassination: / Sinister Strike
	[260] = { friendly = nil,   hostile = 1752 },      -- Outlaw: / Sinister Strike
	[261] = { friendly = nil,   hostile = 1752 },      -- Subtlety: / Sinister Strike

	-- Shaman
	[262] = { friendly = 8004,  hostile = 188196 },    -- Elemental: Healing Surge / Lightning Bolt
	[263] = { friendly = 8004,  hostile = 17364 },     -- Enhancement: Healing Surge / Stormstrike
	[264] = { friendly = 8004,  hostile = 188196 },    -- Restoration: Healing Surge / Lightning Bolt

	-- Warlock
	[265] = { friendly = nil,   hostile = 686 },       -- Affliction: / Shadow Bolt
	[266] = { friendly = nil,   hostile = 686 },       -- Demonology: / Shadow Bolt
	[267] = { friendly = nil,   hostile = 686 },       -- Destruction: / Shadow Bolt

	-- Warrior
	[71]  = { friendly = nil,   hostile = 100 },       -- Arms: / Charge
	[72]  = { friendly = nil,   hostile = 100 },       -- Fury: / Charge
	[73]  = { friendly = nil,   hostile = 100 },       -- Protection: / Charge
}

-- 전문화 미감지 시 클래스 폴백
local classFallbacks = {
	DEATHKNIGHT = { friendly = nil,   hostile = 49998 },
	DEMONHUNTER = { friendly = nil,   hostile = 162794 },
	DRUID       = { friendly = 8936,  hostile = 5176 },
	EVOKER      = { friendly = 361469, hostile = 362969 },
	HUNTER      = { friendly = nil,   hostile = 193455 },
	MAGE        = { friendly = nil,   hostile = 133 },
	MONK        = { friendly = 116670, hostile = 100780 },
	PALADIN     = { friendly = 19750, hostile = 35395 },
	PRIEST      = { friendly = 2061,  hostile = 585 },
	ROGUE       = { friendly = nil,   hostile = 1752 },
	SHAMAN      = { friendly = 8004,  hostile = 188196 },
	WARLOCK     = { friendly = nil,   hostile = 686 },
	WARRIOR     = { friendly = nil,   hostile = 100 },
}

-- 부활 주문 (죽은 대상 범위 체크용)
local rezSpellByClass = {
	DRUID       = 20484,   -- Rebirth
	PRIEST      = 2006,    -- Resurrection
	PALADIN     = 7328,    -- Redemption
	SHAMAN      = 2008,    -- Ancestral Spirit
	MONK        = 115178,  -- Resuscitate
	DEATHKNIGHT = 61999,   -- Raise Ally
	EVOKER      = 361227,  -- Return
}

-----------------------------------------------
-- State
-----------------------------------------------

local currentFriendlySpell = nil
local currentHostileSpell = nil
local currentRezSpell = nil
local rangeCache = {}

-----------------------------------------------
-- Spell Resolution (전문화 변경 시 갱신)
-----------------------------------------------

local function RefreshRangeSpells()
	currentFriendlySpell = nil
	currentHostileSpell = nil
	currentRezSpell = nil
	wipe(rangeCache)

	local specIndex = GetSpecialization()
	local specID = specIndex and GetSpecializationInfo(specIndex) or nil

	local spellData = nil
	if specID and specSpells[specID] then
		spellData = specSpells[specID]
	else
		-- 클래스 폴백
		local _, className = UnitClass("player")
		if className and classFallbacks[className] then
			spellData = classFallbacks[className]
		end
	end

	if spellData then
		currentFriendlySpell = spellData.friendly
		currentHostileSpell = spellData.hostile
	end

	-- 부활 주문
	local _, playerClass = UnitClass("player")
	if playerClass and rezSpellByClass[playerClass] then
		currentRezSpell = rezSpellByClass[playerClass]
	end
end

-----------------------------------------------
-- CheckUnitRange: 6단계 우선순위 체인
-----------------------------------------------

local function CheckUnitRange(unit)
	-- 자기 자신
	if UnitIsUnit(unit, "player") then return true end

	-- 유닛 존재 여부
	if not UnitExists(unit) then return true end

	-- 적대 대상
	if UnitCanAttack("player", unit) then
		if currentHostileSpell and C_Spell and C_Spell.IsSpellInRange then
			local inRange = ns.SafeVal(C_Spell.IsSpellInRange(currentHostileSpell, unit)) -- [REFACTOR]
			if inRange ~= nil then
				return inRange
			end
		end
		return true
	end

	-- ===== 우호 대상 (파티/레이드) =====
	local spellReturnedNil = false

	-- Priority 1: IsSpellInRange + Friendly 주문
	if currentFriendlySpell and C_Spell and C_Spell.IsSpellInRange then
		local inRange = ns.SafeVal(C_Spell.IsSpellInRange(currentFriendlySpell, unit)) -- [REFACTOR]
		if inRange ~= nil then
			return inRange
		else
			spellReturnedNil = true
		end
	end

	-- Priority 2: 죽은 대상 + Rez 주문
	if currentRezSpell and UnitIsDeadOrGhost(unit) then
		if C_Spell and C_Spell.IsSpellInRange then
			local inRange = ns.SafeVal(C_Spell.IsSpellInRange(currentRezSpell, unit)) -- [REFACTOR]
			if inRange ~= nil then
				return inRange
			end
			-- secret → nil → fall through
		end
	end

	-- Priority 3: 비전투 시 CheckInteractDistance (~28yd)
	if not InCombatLockdown() then
		return CheckInteractDistance(unit, 4)
	end

	-- Priority 4: NIL-ON-ALIVE — Friendly 주문이 nil + 살아있는 연결된 대상 → 범위 밖
	if spellReturnedNil and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
		return false
	end

	-- Priority 5: UnitInRange 폴백 (secret 방어) -- [REFACTOR]
	if UnitInRange then
		local rawInRange, rawChecked = UnitInRange(unit)
		local inRange = ns.SafeVal(rawInRange)
		local checked = ns.SafeVal(rawChecked)
		if inRange == nil or checked == nil then
			return true -- secret → 안전 기본값
		end
		if checked and not inRange then
			return false
		end
	end

	-- Priority 6: 기본값 (안전 — 프레임이 사라지는 것보다 낫다)
	return true
end

-----------------------------------------------
-- UpdateRange: 프레임별 범위 상태 갱신
-----------------------------------------------

local RANGE_IN_ALPHA = 1.0
local RANGE_OUT_ALPHA = 0.55

function GF:UpdateRange(frame)
	if not frame or not frame.unit then return end

	local inRange = CheckUnitRange(frame.unit)
	local cached = rangeCache[frame.unit]

	-- 캐시 히트: 동일 상태 + 프레임 이미 적용됨 → 스킵
	if cached == inRange and frame.gfInRange == inRange then
		return
	end

	rangeCache[frame.unit] = inRange
	frame.gfInRange = inRange

	-- 알파 적용 (FlightHide 상태 존중)
	local targetAlpha = inRange and RANGE_IN_ALPHA or RANGE_OUT_ALPHA
	local FH = ns.FlightHide
	if FH and (FH._hiding or FH.isActive) then
		targetAlpha = targetAlpha * (FH._currentAlpha or 0)
	end
	frame:SetAlpha(targetAlpha)
end

-----------------------------------------------
-- 공유 범위 타이머 (0.5초 간격)
-----------------------------------------------

local RANGE_TIMER_INTERVAL = 0.5
-- [PERF] rangeTimerFrame: Show/Hide로 그룹 시에만 OnUpdate 실행 (솔로 시 비활성)
local rangeTimerFrame = CreateFrame("Frame")
local rangeTimerElapsed = 0
rangeTimerFrame:Hide() -- 기본 비활성

rangeTimerFrame:SetScript("OnUpdate", function(self, elapsed)
	rangeTimerElapsed = rangeTimerElapsed + elapsed
	if rangeTimerElapsed < RANGE_TIMER_INTERVAL then return end
	rangeTimerElapsed = 0

	if not GF.headersInitialized then return end

	for _, frame in pairs(GF.allFrames) do
		if frame and frame:IsVisible() and frame.unit then
			GF:UpdateRange(frame)
		end
	end
end)

function GF:StartRangeTimer()
	-- 초기 주문 해석
	RefreshRangeSpells()

	-- [PERF] 그룹 시에만 범위 타이머 활성화
	self:UpdateRangeTimerState()

	-- 이벤트: 전문화 변경 / 전투 상태 변경 / 그룹 변경 시 상태 갱신
	local eventWatcher = CreateFrame("Frame")
	eventWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	eventWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	eventWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	eventWatcher:RegisterEvent("GROUP_ROSTER_UPDATE") -- [PERF] 그룹 상태 감시
	eventWatcher:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_SPECIALIZATION_CHANGED" then
			RefreshRangeSpells()
		elseif event == "GROUP_ROSTER_UPDATE" then
			GF:UpdateRangeTimerState()
		else
			-- 전투 시작/종료: CheckInteractDistance 가용성 변경
			wipe(rangeCache)
		end
	end)
end

-- [PERF] 범위 타이머 Show/Hide 제어
function GF:UpdateRangeTimerState()
	if GF.headersInitialized and (IsInGroup() or IsInRaid()) then
		rangeTimerFrame:Show()
	else
		rangeTimerFrame:Hide()
		rangeTimerElapsed = 0
		wipe(rangeCache)
	end
end
