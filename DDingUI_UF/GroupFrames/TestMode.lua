--[[
	ddingUI UnitFrames
	GroupFrames/TestMode.lua — Cell 스타일 가상 미리보기 시스템

	GF:CreateFrameElements + GF:ApplyLayout 파이프라인 재사용
	Non-secure Button 프레임 (전투 중 생성/파괴 가능)
	DandersFrames 시뮬레이션 패턴: 체력 이벤트 + smooth lerp
]]

local _, ns = ...
local GF = ns.GroupFrames
local C = ns.Constants       -- [REFACTOR] 아이콘 세트 등 상수 참조
local unpack = unpack

local TM = {}
GF.TestMode = TM

local SL = _G.DDingUI_StyleLib
local FLAT = SL and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local GetTime = GetTime
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local math_sin = math.sin
local math_random = math.random
local math_ceil = math.ceil
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor

-----------------------------------------------
-- State
-----------------------------------------------

TM.active = false
TM.partyFrames = {}
TM.raidFrames = {}
TM.partyContainer = nil
TM.raidContainer = nil
TM.simDriver = nil

-- simContainers 참조 (Core/Update.lua에서 선언, Mover.lua에서 접근)
local simContainers = ns.simContainers or {}

-----------------------------------------------
-- 시뮬레이션 상수
-----------------------------------------------

local SIM_TICK = 0.03           -- ~30fps
local SIM_LERP_SPEED = 3.0     -- 체력 보간 속도
local SIM_EVENT_MIN = 0.8
local SIM_EVENT_MAX = 2.5
local SIM_DEATH_CHANCE = 0.04
local SIM_REZ_DELAY = 4.0
local SIM_LOW_HP = 35

-----------------------------------------------
-- 가짜 데이터 (40명, 13직업 다양한 역할/상태)
-----------------------------------------------

local FAKE_MEMBERS = {
	-- Party (5명)
	{ name = "탱커전사",   class = "WARRIOR",      role = "TANK",    hp = 95, power = 80, powerType = 1 },
	{ name = "힐러사제",   class = "PRIEST",       role = "HEALER",  hp = 88, power = 75, powerType = 0 },
	{ name = "화염법사",   class = "MAGE",         role = "DAMAGER", hp = 72, power = 60, powerType = 0 },
	{ name = "암살도적",   class = "ROGUE",        role = "DAMAGER", hp = 81, power = 90, powerType = 3 },
	{ name = "조화드루",   class = "DRUID",        role = "DAMAGER", hp = 65, power = 55, powerType = 0 },
	-- Raid Group 2
	{ name = "수호기사",   class = "PALADIN",      role = "TANK",    hp = 97, power = 85, powerType = 0 },
	{ name = "복원술사",   class = "SHAMAN",       role = "HEALER",  hp = 90, power = 70, powerType = 0 },
	{ name = "파괴술사",   class = "WARLOCK",      role = "DAMAGER", hp = 78, power = 65, powerType = 0 },
	{ name = "사격냥꾼",   class = "HUNTER",       role = "DAMAGER", hp = 83, power = 88, powerType = 2 },
	{ name = "바람수도",   class = "MONK",         role = "DAMAGER", hp = 69, power = 75, powerType = 3 },
	-- Raid Group 3
	{ name = "부정기사",   class = "DEATHKNIGHT",  role = "TANK",    hp = 92, power = 70, powerType = 6 },
	{ name = "신성기사",   class = "PALADIN",      role = "HEALER",  hp = 86, power = 60, powerType = 0 },
	{ name = "고통술사",   class = "WARLOCK",      role = "DAMAGER", hp = 74, power = 50, powerType = 0 },
	{ name = "비전법사",   class = "MAGE",         role = "DAMAGER", hp = 67, power = 45, powerType = 0 },
	{ name = "분노전사",   class = "WARRIOR",      role = "DAMAGER", hp = 80, power = 70, powerType = 1 },
	-- Raid Group 4
	{ name = "양조수도",   class = "MONK",         role = "TANK",    hp = 94, power = 80, powerType = 3 },
	{ name = "회복드루",   class = "DRUID",        role = "HEALER",  hp = 91, power = 65, powerType = 0 },
	{ name = "황천기사",   class = "DEATHKNIGHT",  role = "DAMAGER", hp = 76, power = 55, powerType = 6 },
	{ name = "증강술사",   class = "EVOKER",       role = "DAMAGER", hp = 70, power = 50, powerType = 0 },
	{ name = "악마사냥",   class = "DEMONHUNTER",  role = "DAMAGER", hp = 82, power = 85, powerType = 17 },
	-- Raid Group 5
	{ name = "보호기사",   class = "PALADIN",      role = "TANK",    hp = 96, power = 78, powerType = 0 },
	{ name = "안개수도",   class = "MONK",         role = "HEALER",  hp = 87, power = 72, powerType = 0 },
	{ name = "냉기법사",   class = "MAGE",         role = "DAMAGER", hp = 71, power = 58, powerType = 0 },
	{ name = "무법도적",   class = "ROGUE",        role = "DAMAGER", hp = 79, power = 88, powerType = 3 },
	{ name = "야수냥꾼",   class = "HUNTER",       role = "DAMAGER", hp = 84, power = 92, powerType = 2 },
	-- Raid Group 6
	{ name = "복수사냥",   class = "DEMONHUNTER",  role = "TANK",    hp = 93, power = 80, powerType = 17 },
	{ name = "보존용기",   class = "EVOKER",       role = "HEALER",  hp = 89, power = 68, powerType = 0 },
	{ name = "징벌기사",   class = "PALADIN",      role = "DAMAGER", hp = 75, power = 62, powerType = 0 },
	{ name = "원소술사",   class = "SHAMAN",       role = "DAMAGER", hp = 68, power = 54, powerType = 0 },
	{ name = "균형드루",   class = "DRUID",        role = "DAMAGER", hp = 73, power = 48, powerType = 0 },
	-- Raid Group 7
	{ name = "혈기기사",   class = "DEATHKNIGHT",  role = "TANK",    hp = 91, power = 75, powerType = 6 },
	{ name = "수양사제",   class = "PRIEST",       role = "HEALER",  hp = 85, power = 63, powerType = 0 },
	{ name = "고통사제",   class = "PRIEST",       role = "DAMAGER", hp = 66, power = 44, powerType = 0 },
	{ name = "야성드루",   class = "DRUID",        role = "DAMAGER", hp = 77, power = 86, powerType = 3 },
	{ name = "정밀냥꾼",   class = "HUNTER",       role = "DAMAGER", hp = 81, power = 90, powerType = 2 },
	-- Raid Group 8
	{ name = "방어전사",   class = "WARRIOR",      role = "TANK",    hp = 0,  power = 0,  powerType = 1, isDead = true },
	{ name = "신성사제",   class = "PRIEST",       role = "HEALER",  hp = 0,  power = 0,  powerType = 0, isOffline = true },
	{ name = "파멸술사",   class = "WARLOCK",      role = "DAMAGER", hp = 62, power = 42, powerType = 0 },
	{ name = "강화술사",   class = "SHAMAN",       role = "DAMAGER", hp = 58, power = 38, powerType = 0 },
	{ name = "무기전사",   class = "WARRIOR",      role = "DAMAGER", hp = 85, power = 75, powerType = 1 },
}

-----------------------------------------------
-- 더미 오라 데이터 (버프/디버프/생존기/프라이빗 오라)
-----------------------------------------------

-- 버프 (Arcane Intellect, PW:Fortitude, Battle Shout, Mark of the Wild)
local DUMMY_BUFF_IDS = { 1459, 21562, 6673, 1126 }
-- 디버프 (Shadow Word: Pain, Corruption, Frost Nova, Moonfire)
local DUMMY_DEBUFF_IDS = { 589, 172, 122, 8921 }
-- 생존기 (Ice Block, Divine Shield, AMS, Barkskin)
local DUMMY_DEFENSIVE_IDS = { 45438, 642, 48707, 22812 }
-- 프라이빗 오라 대표 텍스처 (보스 메커닉 디버프 시뮬레이션)
local PRIVATE_AURA_PLACEHOLDER = "Interface\\Icons\\Spell_Fire_FelFlameBreath"

-- 디버프별 디스펠 타입 시뮬레이션 (인덱스 → 디스펠타입)
local DUMMY_DEBUFF_DISPEL = { "Magic", "Curse", "Disease", "Poison" }

-- 쿨다운 주기 (초)
local AURA_COOLDOWN_CYCLE = 13

-- [FIX] 쿨다운 재순환: 만료된 더미 쿨다운을 랜덤 지속시간으로 갱신
local RECYCLE_CHECK_INTERVAL = 0.3
local RECYCLE_MIN_DURATION = 5
local RECYCLE_MAX_DURATION = 25
local recycleElapsed = 0

local function GetCooldownRemaining(cooldown)
	if not cooldown then return 0, 0 end
	local start, duration
	if cooldown.GetCooldownTimes then
		start, duration = cooldown:GetCooldownTimes()
		if start and duration then
			start = start / 1000
			duration = duration / 1000
		end
	end
	if not start or not duration or duration <= 0 then return 0, 0 end
	local remaining = (start + duration) - GetTime()
	return remaining, duration
end

local function RecycleExpiredCooldowns()
	local now = GetTime()
	for _pass = 1, 2 do
		local frameList = _pass == 1 and TM.partyFrames or TM.raidFrames
		if frameList then
			for _, frame in ipairs(frameList) do
				if frame and frame:IsVisible() then
					for _iconPass = 1, 2 do
						local iconList = _iconPass == 1 and frame.buffIcons or frame.debuffIcons
						if iconList then
							for _, icon in ipairs(iconList) do
								if icon:IsShown() and icon.cooldown then
									local remaining = GetCooldownRemaining(icon.cooldown)
									if remaining <= 0 then
										local newDuration = math_random(RECYCLE_MIN_DURATION, RECYCLE_MAX_DURATION)
										icon.cooldown:SetCooldown(now, newDuration)
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

-----------------------------------------------
-- 더미 오라 적용
-----------------------------------------------

function TM:ApplyDummyAuras(f, fakeData)
	if not f then return end

	local isDead = fakeData and (fakeData.isDead or fakeData.isOffline)
	local db = GF:GetFrameDB(f)
	local widgets = db and db.widgets or {}
	local now = GetTime()

	-- [12.0.1] 더미 오라 아이콘에 네이티브 쿨다운 텍스트 표시 헬퍼
	local function ShowDummyNativeCooldown(icon, auraDB, cdStart, cdDuration)
		if not icon.nativeCooldownText then return end
		local showDur = auraDB.showDuration ~= false
		if showDur then
			icon.nativeCooldownText:Show()
			-- [12.0.1] duration 색상 (DB font.duration.rgb → fixed mode only for preview)
			local fontDB = auraDB.font and auraDB.font.duration
			if fontDB and fontDB.rgb then
				icon.nativeCooldownText:SetTextColor(fontDB.rgb[1], fontDB.rgb[2], fontDB.rgb[3], 1)
			else
				icon.nativeCooldownText:SetTextColor(1, 1, 1, 1)
			end
		else
			icon.nativeCooldownText:Hide()
		end
	end

	-- ===== 버프 아이콘 =====
	local buffsDB = widgets.buffs or {}
	if f.buffIcons and buffsDB.enabled ~= false and not isDead then
		local maxIcons = buffsDB.maxIcons or 10
		local numBuffs = math_min(#DUMMY_BUFF_IDS, #f.buffIcons, maxIcons)
		local showStack = buffsDB.showStack ~= false

		for i = 1, numBuffs do
			local icon = f.buffIcons[i]
			if icon then
				-- 아이콘 텍스처 설정
				local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(DUMMY_BUFF_IDS[i])
				if info and info.iconID then
					icon.texture:SetTexture(info.iconID)
				else
					icon.texture:SetTexture(136243)
				end
				icon.texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
				-- 테두리 (버프 = 검정)
				if icon.border then
					icon.border:SetVertexColor(0, 0, 0, 0.8)
				end
				-- 쿨다운 (시차 적용으로 각각 다른 위치에서 시작)
				local offset = (i - 1) * 3
				if icon.cooldown then
					-- [FIX] SetCooldownFromExpirationTime 사용 (네이티브 카운트다운 텍스트 활성화)
					local expirationTime = now - offset + AURA_COOLDOWN_CYCLE
					if icon.cooldown.SetCooldownFromExpirationTime then
						icon.cooldown:SetCooldownFromExpirationTime(expirationTime, AURA_COOLDOWN_CYCLE)
					else
						icon.cooldown:SetCooldown(now - offset, AURA_COOLDOWN_CYCLE)
					end
				end
				-- [12.0.1] 스택 텍스트: DB showStack 참조
				if icon.count then
					if showStack and i == 1 then
						icon.count:SetText("2")
						icon.count:Show()
					else
						icon.count:SetText("")
						icon.count:Hide()
					end
				end
				-- [12.0.1] 커스텀 duration 숨김 (네이티브 카운트다운 사용)
				if icon.duration then icon.duration:Hide() end
				-- [TEST MODE] colorTimerFrame 수동 평가용 auraType 태깅
				icon.auraType = "BUFF"
				-- [12.0.1] 네이티브 쿨다운 텍스트: DB showDuration + 색상 반영
				ShowDummyNativeCooldown(icon, buffsDB, now - offset, AURA_COOLDOWN_CYCLE)
				icon:Show()
			end
		end
		-- 나머지 숨김
		for i = numBuffs + 1, #f.buffIcons do
			if f.buffIcons[i] then f.buffIcons[i]:Hide() end
		end
	elseif f.buffIcons then
		for _, icon in ipairs(f.buffIcons) do
			if icon then icon:Hide() end
		end
	end

	-- ===== 디버프 아이콘 =====
	local debuffsDB = widgets.debuffs or {}
	if f.debuffIcons and debuffsDB.enabled ~= false and not isDead then
		-- 일부 프레임에만 디버프 표시 (다양한 상태 시뮬레이션)
		local showDebuffs = fakeData and (fakeData.hp or 100) < 85
		local maxIcons = debuffsDB.maxIcons or 8
		local numDebuffs = showDebuffs and math_min(#DUMMY_DEBUFF_IDS, #f.debuffIcons, maxIcons) or 0
		-- 최소 1-2개만 표시 (실제 상황처럼)
		numDebuffs = math_min(numDebuffs, 2)
		local showStack = debuffsDB.showStack ~= false

		for i = 1, numDebuffs do
			local icon = f.debuffIcons[i]
			if icon then
				local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(DUMMY_DEBUFF_IDS[i])
				if info and info.iconID then
					icon.texture:SetTexture(info.iconID)
				else
					icon.texture:SetTexture(136243)
				end
				icon.texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
				-- 테두리: 디스펠 타입별 색상 (Auras.lua와 동일: alpha 0.8)
				if icon.border then
					local dispelType = DUMMY_DEBUFF_DISPEL[((i - 1) % #DUMMY_DEBUFF_DISPEL) + 1]
					local dc = C and C.DISPEL_COLORS and C.DISPEL_COLORS[dispelType] or { 0.8, 0, 0 }
					icon.border:SetVertexColor(dc[1], dc[2], dc[3], 0.8)
				end
				local offset = (i - 1) * 4 + 1
				if icon.cooldown then
					-- [FIX] SetCooldownFromExpirationTime 사용 (네이티브 카운트다운 텍스트 활성화)
					local expirationTime = now - offset + AURA_COOLDOWN_CYCLE
					if icon.cooldown.SetCooldownFromExpirationTime then
						icon.cooldown:SetCooldownFromExpirationTime(expirationTime, AURA_COOLDOWN_CYCLE)
					else
						icon.cooldown:SetCooldown(now - offset, AURA_COOLDOWN_CYCLE)
					end
				end
				-- [12.0.1] 스택: 디버프도 DB showStack 참조 (1번만 스택 3 표시)
				if icon.count then
					if showStack and i == 1 then
						icon.count:SetText("3")
						icon.count:Show()
					else
						icon.count:SetText("")
						icon.count:Hide()
					end
				end
				-- [12.0.1] 커스텀 duration 숨김 + 네이티브 카운트다운 DB 반영
				if icon.duration then icon.duration:Hide() end
				-- [TEST MODE] colorTimerFrame 수동 평가용 auraType 태깅
				icon.auraType = "DEBUFF"
				ShowDummyNativeCooldown(icon, debuffsDB, now - offset, AURA_COOLDOWN_CYCLE)
				icon:Show()
			end
		end
		for i = numDebuffs + 1, #f.debuffIcons do
			if f.debuffIcons[i] then f.debuffIcons[i]:Hide() end
		end
	elseif f.debuffIcons then
		for _, icon in ipairs(f.debuffIcons) do
			if icon then icon:Hide() end
		end
	end

	-- ===== 생존기 아이콘 =====
	local defDB = widgets.defensives or {}
	if f.defensiveIcons and defDB.enabled ~= false and not isDead then
		-- 탱/힐에게만 생존기 표시 (실전 시뮬레이션)
		local showDef = fakeData and (fakeData.role == "TANK" or fakeData.role == "HEALER")
		local numDef = showDef and math_min(#DUMMY_DEFENSIVE_IDS, #f.defensiveIcons) or 0
		numDef = math_min(numDef, 1) -- 보통 1개만 활성
		local defShowDuration = defDB.showDuration ~= false -- [12.0.1]
		local defShowStack = defDB.showStack -- [12.0.1]

		for i = 1, numDef do
			local btn = f.defensiveIcons[i]
			if btn then
				local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(DUMMY_DEFENSIVE_IDS[i])
				if info and info.iconID then
					btn.Icon:SetTexture(info.iconID)
				else
					btn.Icon:SetTexture(136243)
				end
				btn.Icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
				-- 생존기 테두리 (실제 프레임과 동일: 검정)
				if btn.border then
					btn.border:SetVertexColor(0, 0, 0, 0.8)
				end
				local offset = (i - 1) * 2 + 2
				local defCycleDuration = AURA_COOLDOWN_CYCLE + 5
				if btn.Cooldown then
					-- [FIX] SetCooldownFromExpirationTime 사용 (네이티브 카운트다운 텍스트 활성화)
					local expirationTime = now - offset + defCycleDuration
					if btn.Cooldown.SetCooldownFromExpirationTime then
						btn.Cooldown:SetCooldownFromExpirationTime(expirationTime, defCycleDuration)
					else
						btn.Cooldown:SetCooldown(now - offset, defCycleDuration)
					end
				end
				-- [12.0.1] 생존기 네이티브 카운트다운: DB showDuration 참조
				if btn.nativeCooldownText then
					if defShowDuration then
						btn.nativeCooldownText:Show()
					else
						btn.nativeCooldownText:Hide()
					end
				end
				-- [12.0.1] 생존기 스택: DB showStack 참조
				if btn.Count then
					if defShowStack then
						btn.Count:SetText("1")
						btn.Count:Show()
					else
						btn.Count:Hide()
					end
				end
				btn:Show()
			end
		end
		for i = numDef + 1, #f.defensiveIcons do
			if f.defensiveIcons[i] then f.defensiveIcons[i]:Hide() end
		end
	elseif f.defensiveIcons then
		for _, btn in ipairs(f.defensiveIcons) do
			if btn then btn:Hide() end
		end
	end

	-- ===== 프라이빗 오라 (플레이스홀더) =====
	local paDB = widgets.privateAuras or {}
	if f.privateAuraAnchors and paDB.enabled ~= false and not isDead then
		-- 일부 프레임에만 프라이빗 오라 표시
		local showPA = fakeData and (fakeData.role == "HEALER")
		local numPA = showPA and math_min(1, #f.privateAuraAnchors) or 0

		for i = 1, numPA do
			local anchor = f.privateAuraAnchors[i]
			if anchor then
				-- [FIX] 배경 생성 (1회) — 아이콘 뒤 어두운 배경
				if not anchor._testBG then
					anchor._testBG = anchor:CreateTexture(nil, "BACKGROUND")
					anchor._testBG:SetAllPoints()
					anchor._testBG:SetTexture(FLAT)
					anchor._testBG:SetVertexColor(0.05, 0.05, 0.05, 0.9)
				end
				-- 플레이스홀더 텍스처 생성 (1회)
				if not anchor._testIcon then
					anchor._testIcon = anchor:CreateTexture(nil, "ARTWORK")
					anchor._testIcon:SetAllPoints()
					anchor._testIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				end
				-- [12.0.1] 프라이빗 오라 눈 아이콘
				anchor._testIcon:SetTexture(PRIVATE_AURA_PLACEHOLDER)
				anchor._testIcon:Show()
				anchor._testBG:Show()
				-- Create.lua에서 생성한 빨간 테두리 표시
				anchor:Show()
			end
		end
		for i = numPA + 1, #f.privateAuraAnchors do
			local anchor = f.privateAuraAnchors[i]
			if anchor then
				if anchor._testIcon then anchor._testIcon:Hide() end
				if anchor._testBG then anchor._testBG:Hide() end
				anchor:Hide()
			end
		end
	elseif f.privateAuraAnchors then
		for _, anchor in ipairs(f.privateAuraAnchors) do
			if anchor then
				if anchor._testIcon then anchor._testIcon:Hide() end
				if anchor._testBG then anchor._testBG:Hide() end
				anchor:Hide()
			end
		end
	end

	-- ===== 디버프 하이라이트 (테두리 + 오버레이) =====
	-- [12.0.1] 디버프 아이콘과 독립적으로 각 디스펠 타입별 하이라이트 분산 표시
	local dhDB = widgets.debuffHighlight or {}
	if f.debuffHighlight and dhDB.enabled ~= false and not isDead then
		local idx = (f._testIdx or 1)
		-- 5개 슬롯 순환: Magic → 없음 → Curse → Disease → Poison
		local slot = ((idx - 1) % 5) + 1
		if slot == 2 then
			-- 일부 프레임은 하이라이트 없음 (정상 상태 시뮬레이션)
			GF:HideDebuffHighlight(f)
		else
			local dispelMap = { "Magic", nil, "Curse", "Disease", "Poison" }
			local dispelType = dispelMap[slot]
			if dispelType then
				local dc = C and C.DISPEL_COLORS and C.DISPEL_COLORS[dispelType] or { 0.8, 0, 0 }
				GF:ShowDebuffHighlight(f, dc[1], dc[2], dc[3], dhDB)
			else
				GF:HideDebuffHighlight(f)
			end
		end
	elseif f.debuffHighlight then
		GF:HideDebuffHighlight(f)
	end
end

-----------------------------------------------
-- 더미 오라 정리
-----------------------------------------------

function TM:ClearDummyAuras(f)
	if not f then return end
	if f.buffIcons then
		for _, icon in ipairs(f.buffIcons) do
			if icon then
				if icon.cooldown then icon.cooldown:SetCooldown(0, 0) end
				icon:Hide()
			end
		end
	end
	if f.debuffIcons then
		for _, icon in ipairs(f.debuffIcons) do
			if icon then
				if icon.cooldown then icon.cooldown:SetCooldown(0, 0) end
				icon:Hide()
			end
		end
	end
	if f.defensiveIcons then
		for _, btn in ipairs(f.defensiveIcons) do
			if btn then
				if btn.Cooldown then btn.Cooldown:SetCooldown(0, 0) end
				btn:Hide()
			end
		end
	end
	if f.privateAuraAnchors then
		for _, anchor in ipairs(f.privateAuraAnchors) do
			if anchor then
				if anchor._testIcon then anchor._testIcon:Hide() end
				if anchor._testBG then anchor._testBG:Hide() end
				anchor:Hide()
			end
		end
	end
	-- [12.0.1] 디버프 하이라이트 정리
	if f.debuffHighlight then
		GF:HideDebuffHighlight(f)
	end
end

-----------------------------------------------
-- 컨테이너 생성 헬퍼
-----------------------------------------------

local function CreateGroupContainer(name, parent)
	local existing = _G[name]
	if existing then
		existing:SetParent(parent or UIParent)
		existing:Show()
		return existing
	end

	local container = CreateFrame("Frame", name, parent or UIParent)
	container:SetFrameStrata("TOOLTIP")
	container:SetFrameLevel(499)
	container:EnableMouse(false)
	container:SetClampedToScreen(true)

	return container
end

-----------------------------------------------
-- Mover 위치 가져오기 헬퍼
-----------------------------------------------

local function SetContainerFromMover(container, moverName, fallbackDB, fallbackPoint, fallbackX, fallbackY)
	container:ClearAllPoints()

	-- Mover 위치 우선
	local mover = _G[moverName]
	if mover then
		local left, top = mover:GetLeft(), mover:GetTop()
		if left and top then
			container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			return
		end
	end

	-- DB 위치
	if fallbackDB and fallbackDB.position then
		local pos = fallbackDB.position
		if type(pos[1]) == "string" then
			local relativeTo = pos[2] and (_G[pos[2]] or UIParent) or UIParent
			container:SetPoint(pos[1], relativeTo, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
			return
		elseif pos.point then
			container:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0)
			return
		end
	end

	-- 최종 폴백
	container:SetPoint(fallbackPoint or "TOPLEFT", UIParent, fallbackPoint or "TOPLEFT", fallbackX or 20, fallbackY or -40)
end

-----------------------------------------------
-- 테스트 프레임 생성 — GF 파이프라인 재사용
-----------------------------------------------

function TM:CreateTestFrame(name, parent, isRaid, fakeData)
	local existing = _G[name]
	local f

	if existing then
		-- 기존 프레임 재사용: 위젯은 이미 생성됨 → gfElementsCreated 유지
		f = existing
		f:SetParent(parent or UIParent)
		f.isRaidFrame = isRaid
		f._fakeData = fakeData
	else
		-- 새 프레임 생성
		f = CreateFrame("Button", name, parent or UIParent)
		f.isRaidFrame = isRaid
		f._fakeData = fakeData
	end

	f:SetFrameStrata("TOOLTIP")
	f:SetFrameLevel(500)
	f.gfIsTestFrame = true
	f.gfEventsEnabled = false  -- 중앙 이벤트 디스패치 스킵
	f.unit = nil

	-- GF 파이프라인: 위젯 생성 (gfElementsCreated=true면 스킵) + 레이아웃 적용
	GF:CreateFrameElements(f)
	GF:ApplyLayout(f)

	-- 가짜 데이터 적용
	TM:ApplyFakeData(f, fakeData)

	return f
end

-----------------------------------------------
-- 가짜 데이터 → 위젯 적용
-----------------------------------------------

function TM:ApplyFakeData(f, data)
	if not f or not data then return end

	local cc = RAID_CLASS_COLORS[data.class]
	local db = GF:GetFrameDB(f) -- 전체 섹션에서 공유

	-- 이름 — Update.lua:UpdateName 로직과 동일
	if f.nameText then
		local widgets = db.widgets or {}
		local nameDB = widgets.nameText or {}
		local colorOpt = nameDB.color or {}
		local nameColorType = colorOpt.type or "class_color"

		if nameColorType == "class_color" then
			if cc then
				f.nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
			else
				f.nameText:SetTextColor(1, 1, 1, 1)
			end
		elseif nameColorType == "custom" then
			local rgb = colorOpt.rgb or { 1, 1, 1 }
			f.nameText:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
		else
			f.nameText:SetTextColor(1, 1, 1, 1)
		end
		f.nameText:SetText(data.name)
	end

	-- 체력바 — [12.0.1] DB 설정(colorType) 기반 색상 적용
	if f.healthBar then
		f.healthBar:SetMinMaxValues(0, 100)
		f.healthBar:SetValue(data.hp)

		local colorType = db.healthBarColorType or "class"
		local ufColors = ns.Colors and ns.Colors.unitFrames
		local r, g, b = 0.2, 0.8, 0.2

		if data.isDead then
			local dc = ufColors and ufColors.deathColor or { 0.47, 0.47, 0.47, 1 }
			r, g, b = dc[1], dc[2], dc[3]
		elseif data.isOffline then
			local oc = ufColors and ufColors.offlineColor or { 0.5, 0.5, 0.5, 1 }
			r, g, b = oc[1], oc[2], oc[3]
		elseif colorType == "class" then
			if cc then r, g, b = cc.r, cc.g, cc.b end
		elseif colorType == "custom" then
			local c = db.healthBarColor or { 0.2, 0.8, 0.2, 1 }
			r, g, b = c[1], c[2], c[3]
		elseif colorType == "smooth" then
			local pct = (data.hp or 100) / 100
			if pct > 0.5 then
				local t = (pct - 0.5) * 2
				r, g, b = 1 - t, 0.8 + 0.2 * t, 0
			else
				local t = pct * 2
				r, g, b = 1, t * 0.8, 0
			end
		end

		f.healthBar:SetStatusBarColor(r, g, b, 1)
	end

	-- [12.0.1] 힐예측/보호막 미리보기
	local widgets = db.widgets or {}
	local hpDB = widgets.healPrediction or {}
	local sbDB = widgets.shieldBar or {}
	if f.healPredictionBar and hpDB.enabled ~= false then
		local healthFill = f.healthBar and f.healthBar:GetStatusBarTexture()
		if healthFill then
			local barW = f.healthBar:GetWidth()
			f.healPredictionBar:ClearAllPoints()
			f.healPredictionBar:SetPoint("TOPLEFT", healthFill, "TOPRIGHT", 0, 0)
			f.healPredictionBar:SetPoint("BOTTOMLEFT", healthFill, "BOTTOMRIGHT", 0, 0)
			f.healPredictionBar:SetWidth(barW)
			f.healPredictionBar:SetMinMaxValues(0, 100)
			f.healPredictionBar:SetValue(math_min(100 - data.hp, 15)) -- 미리보기: 최대 15%
			-- [FIX] ns.Colors 글로벌 색상 우선 적용
			local hpColor = (ns.Colors and ns.Colors.healPrediction and ns.Colors.healPrediction.color) or hpDB.color or { 0, 1, 0.5, 0.4 }
			f.healPredictionBar:SetStatusBarColor(hpColor[1], hpColor[2], hpColor[3], hpColor[4] or 0.4)
			f.healPredictionBar:Show()
		end
	end
	if f.absorbBar and sbDB.enabled ~= false then
		local healthFill = f.healthBar and f.healthBar:GetStatusBarTexture()
		local anchor = f.healPredictionBar and f.healPredictionBar:IsShown()
			and f.healPredictionBar:GetStatusBarTexture() or healthFill
		if anchor then
			local barW = f.healthBar:GetWidth()
			local shieldAmount = 15 -- 미리보기: 15% 보호막
			local deficit = 100 - data.hp
			local isFullHP = data.hp >= 99.5
			local hasOverShield = shieldAmount > deficit
			-- [FIX] ns.Colors 글로벌 색상 우선 적용 (Update.lua와 동일)
			local sbColor = (ns.Colors and ns.Colors.shieldBar and ns.Colors.shieldBar.shieldColor) or sbDB.color or { 1, 1, 0, 0.4 }
			-- 초과 보호막 전용 색상 (Update.lua:674과 동일)
			local osColor = (ns.Colors and ns.Colors.shieldBar and ns.Colors.shieldBar.overshieldColor) or sbDB.overshieldColor or sbColor

			if isFullHP then
				-- [12.0.1] 풀피: absorbBar 클리핑됨 → overShieldBar(ReverseFill)로 표시
				f.absorbBar:Hide()
				if f.overShieldBar then
					f.overShieldBar:SetMinMaxValues(0, 100)
					f.overShieldBar:SetValue(shieldAmount)
					f.overShieldBar:SetStatusBarColor(osColor[1], osColor[2], osColor[3], osColor[4] or 0.4)
					f.overShieldBar:Show()
				end
				if f.overShieldGlow and f.overShieldBar then
					local osTex = f.overShieldBar:GetStatusBarTexture()
					if osTex then
						f.overShieldGlow:ClearAllPoints()
						f.overShieldGlow:SetPoint("TOP", osTex, "TOPLEFT", 0, 0)
						f.overShieldGlow:SetPoint("BOTTOM", osTex, "BOTTOMLEFT", 0, 0)
						f.overShieldGlow:SetWidth(3)
					end
					f.overShieldGlow:SetVertexColor(osColor[1], osColor[2], osColor[3], 0.8)
					f.overShieldGlow:Show()
				end
			else
				-- 비풀피: absorbBar 정상 + 초과분은 overShieldBar
				f.absorbBar:ClearAllPoints()
				f.absorbBar:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
				f.absorbBar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
				f.absorbBar:SetWidth(barW)
				f.absorbBar:SetMinMaxValues(0, 100)
				f.absorbBar:SetValue(shieldAmount)
				f.absorbBar:SetStatusBarColor(sbColor[1], sbColor[2], sbColor[3], sbColor[4] or 0.4)
				f.absorbBar:Show()

				if hasOverShield and f.overShieldBar then
					f.overShieldBar:SetMinMaxValues(0, 100)
					f.overShieldBar:SetValue(shieldAmount)
					f.overShieldBar:SetStatusBarColor(osColor[1], osColor[2], osColor[3], (osColor[4] or 0.4) * 0.7)
					f.overShieldBar:Show()
				elseif f.overShieldBar then
					f.overShieldBar:Hide()
				end
				if hasOverShield and f.overShieldGlow and f.overShieldBar then
					local osTex = f.overShieldBar:GetStatusBarTexture()
					if osTex then
						f.overShieldGlow:ClearAllPoints()
						f.overShieldGlow:SetPoint("TOP", osTex, "TOPLEFT", 0, 0)
						f.overShieldGlow:SetPoint("BOTTOM", osTex, "BOTTOMLEFT", 0, 0)
						f.overShieldGlow:SetWidth(3)
					end
					f.overShieldGlow:SetVertexColor(osColor[1], osColor[2], osColor[3], 0.8)
					f.overShieldGlow:Show()
				elseif f.overShieldGlow then
					f.overShieldGlow:Hide()
				end
			end
		end
	end

	-- 체력 텍스트 — Update.lua:UpdateHealthText 로직과 동일
	if f.healthText then
		local widgets = db.widgets or {}
		local htDB = widgets.healthText or {}
		if htDB.enabled ~= false then
			local fmt = htDB.format or "percentage"
			if fmt == "percentage" then
				f.healthText:SetFormattedText("%.0f%%", data.hp)
			elseif fmt == "current" then
				f.healthText:SetText(math_floor(data.hp * 10000) .. "")
			elseif fmt == "deficit" then
				local deficit = 100 - data.hp
				if deficit > 0 then
					f.healthText:SetFormattedText("-%.0f%%", deficit)
				else
					f.healthText:SetText("")
				end
			elseif fmt == "current-max" then
				f.healthText:SetFormattedText("%.0fk/1M", data.hp * 10)
			else
				f.healthText:SetFormattedText("%.0f%%", data.hp)
			end
			-- 체력 텍스트 색상 (Update.lua와 동일)
			local colorOpt = htDB.color or {}
			local htColorType = colorOpt.type or "custom"
			if htColorType == "class_color" then
				if cc then
					f.healthText:SetTextColor(cc.r, cc.g, cc.b, 1)
				else
					f.healthText:SetTextColor(1, 1, 1, 1)
				end
			elseif htColorType == "custom" then
				local rgb = colorOpt.rgb or { 1, 1, 1 }
				f.healthText:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
			else
				f.healthText:SetTextColor(1, 1, 1, 1)
			end
			f.healthText:Show()
		else
			f.healthText:Hide()
		end
	end

	-- 파워바
	if f.powerBar then
		local widgets = db.widgets or {}
		local pwDB = widgets.powerBar or {}
		if pwDB.enabled ~= false then
			f.powerBar:SetMinMaxValues(0, 100)
			f.powerBar:SetValue(data.power or 80)
			-- 파워 타입별 색상 (Update.lua:UpdatePower와 동일)
			local pColor = PowerBarColor[data.powerType or 0]
			if pColor then
				f.powerBar:SetStatusBarColor(pColor.r or 0.5, pColor.g or 0.5, pColor.b or 0.5, 1)
			end
			-- 파워바 배경 (Create.lua와 동일: 검정 0.8)
			if f.powerBar.bg then
				f.powerBar.bg:SetVertexColor(0, 0, 0, 0.8)
			end
		end
	end

	-- 역할 아이콘 — Update.lua:UpdateRoleIcon 로직과 동일
	if f.roleIcon then
		local widgets = db.widgets or {}
		local roleDB = widgets.roleIcon or {}
		if roleDB.enabled == false then
			f.roleIcon:Hide()
		else
			local roleKey = data.role or "DAMAGER"
			-- [FIX] 역할별 필터: showTank/showHealer/showDPS (Update.lua와 동일)
			local filtered = false
			if roleKey == "TANK" and roleDB.showTank == false then filtered = true
			elseif roleKey == "HEALER" and roleDB.showHealer == false then filtered = true
			elseif roleKey == "DAMAGER" and roleDB.showDPS == false then filtered = true
			end
			if filtered then
				f.roleIcon:Hide()
			else
				local iconSet = C.ICON_SETS[ns.db.iconSet or "default"] or C.ICON_SETS["default"]
				if iconSet.role.textures and iconSet.role.textures[roleKey] then
					f.roleIcon:SetTexture(iconSet.role.textures[roleKey])
					f.roleIcon:SetTexCoord(0, 1, 0, 1)
					f.roleIcon:Show()
				elseif iconSet.role.coords and iconSet.role.coords[roleKey] then
					f.roleIcon:SetTexture(iconSet.role.texture)
					f.roleIcon:SetTexCoord(unpack(iconSet.role.coords[roleKey]))
					f.roleIcon:Show()
				else
					f.roleIcon:Hide()
				end
			end
		end
	end

	-- 상태 (죽음/오프라인) — 실제 프레임(Update.lua) 로직과 동일
	local ufColors = ns.Colors and ns.Colors.unitFrames
	local appearance = ns.db and ns.db.appearance or {}
	if data.isDead then
		local dc = ufColors and ufColors.deathColor or { 0.47, 0.47, 0.47, 1 }
		if f.statusText then
			f.statusText:SetText("Dead")
			f.statusText:Show()
		end
		if f.healthBar then f.healthBar:SetValue(0) end
		if f.healthText then f.healthText:Hide() end
		if f.nameText then f.nameText:SetTextColor(dc[1], dc[2], dc[3]) end
		f:SetAlpha(appearance.deadAlpha or C.DEAD_ALPHA)
	elseif data.isOffline then
		local oc = ufColors and ufColors.offlineColor or { 0.5, 0.5, 0.5, 1 }
		if f.statusText then
			f.statusText:SetText("Offline")
			f.statusText:Show()
		end
		if f.healthBar then
			f.healthBar:SetValue(0)
			f.healthBar:SetStatusBarColor(oc[1], oc[2], oc[3])
		end
		if f.healthText then f.healthText:Hide() end
		if f.nameText then f.nameText:SetTextColor(oc[1], oc[2], oc[3]) end
		f:SetAlpha(appearance.offlineAlpha or C.OFFLINE_ALPHA)
	else
		if f.statusText then f.statusText:Hide() end
		f:SetAlpha(1)
	end

	-- [12.0.1] 더미 오라 적용 (버프/디버프/생존기/프라이빗 오라)
	TM:ApplyDummyAuras(f, data)
end

-----------------------------------------------
-- 시뮬레이션 상태 초기화
-----------------------------------------------

local function InitSimState(frame, fakeData)
	local cc = RAID_CLASS_COLORS[fakeData.class] or { r = 1, g = 1, b = 1 }

	-- [12.0.1] DB colorType 기반 시뮬레이션 색상 결정
	local db = GF:GetFrameDB(frame)
	local colorType = db.healthBarColorType or "class"
	local simR, simG, simB = cc.r, cc.g, cc.b
	if colorType == "custom" then
		local c = db.healthBarColor or { 0.2, 0.8, 0.2, 1 }
		simR, simG, simB = c[1], c[2], c[3]
	end
	-- smooth은 시뮬레이션 틱에서 체력% 기반으로 실시간 계산

	local initCurrent = fakeData.isDead and 0 or (30 + math_random(40))
	local initTarget = fakeData.isDead and 0 or (60 + math_random(40))

	frame._sim = {
		class = fakeData.class,
		color = { r = simR, g = simG, b = simB },
		colorType = colorType, -- [12.0.1]
		currentHP = initCurrent,
		targetHP = initTarget,
		currentPower = fakeData.power or 50,
		targetPower = fakeData.power or 50,
		isDead = fakeData.isDead or false,
		isOffline = fakeData.isOffline or false,
		-- [FIX] 초기 사망 유닛은 deathTimer를 충분히 설정 (즉시 부활 방지)
		deathTimer = fakeData.isDead and (SIM_REZ_DELAY + math_random() * 2) or 0,
		nextEventTime = 0.3 + math_random() * 1.0,
		isHealing = false,
		healAmount = 0,
		healTimer = 0,
	}
end

-----------------------------------------------
-- 시뮬레이션 이벤트 처리
-----------------------------------------------

local function ProcessSimEvent(frame)
	local sim = frame._sim
	if not sim or sim.isDead or sim.isOffline then return end

	local roll = math_random()

	if roll < SIM_DEATH_CHANCE then
		sim.targetHP = 0
		sim.isDead = true
		sim.deathTimer = SIM_REZ_DELAY + math_random() * 2
		return
	end

	if roll < 0.55 then
		local dmg = 5 + math_random(35)
		sim.targetHP = math_max(1, sim.targetHP - dmg)
		if sim.targetHP < SIM_LOW_HP and math_random() < 0.3 then
			sim.targetHP = math_max(1, sim.targetHP - math_random(10))
		end
	else
		local heal = 10 + math_random(40)
		local newHP = math_min(100, sim.targetHP + heal)
		sim.isHealing = true
		sim.healAmount = newHP - sim.targetHP
		sim.healTimer = 0.6 + math_random() * 0.4
		sim.targetHP = newHP
	end

	sim.targetPower = math_min(100, math_max(0, sim.targetPower + math_random(-20, 30)))
	sim.nextEventTime = SIM_EVENT_MIN + math_random() * (SIM_EVENT_MAX - SIM_EVENT_MIN)
end

-----------------------------------------------
-- 프레임 비주얼 업데이트 (매 틱)
-- GroupFrames 위젯명: healthBar, nameText, healthText, powerBar, statusText
-----------------------------------------------

local function UpdateFrameVisual(frame, dt)
	local sim = frame._sim
	if not sim then return end

	-- 오프라인은 정적
	if sim.isOffline then return end

	-- 사망 상태 — ns.Colors + DB appearance 참조
	if sim.isDead then
		local ufColors = ns.Colors and ns.Colors.unitFrames
		local dc = ufColors and ufColors.deathColor or { 0.47, 0.47, 0.47, 1 }
		local appearance = ns.db and ns.db.appearance or {}
		sim.deathTimer = sim.deathTimer - dt
		if sim.deathTimer <= 0 then
			sim.isDead = false
			sim.targetHP = 40 + math_random(30)
			sim.currentHP = sim.targetHP * 0.5
			if frame.statusText then frame.statusText:Hide() end
			if frame.healthText then frame.healthText:Show() end
			if frame.nameText then
				-- 부활 시 이름 색상 복원 (DB nameText.color.type 기반)
				local fakeData = frame._fakeData
				local revDB = GF:GetFrameDB(frame)
				local revWidgets = revDB.widgets or {}
				local revNameDB = revWidgets.nameText or {}
				local revColorOpt = revNameDB.color or {}
				local revColorType = revColorOpt.type or "class_color"

				if revColorType == "class_color" then
					local fcc = fakeData and RAID_CLASS_COLORS[fakeData.class]
					if fcc then
						frame.nameText:SetTextColor(fcc.r, fcc.g, fcc.b, 1)
					else
						frame.nameText:SetTextColor(1, 1, 1, 1)
					end
				elseif revColorType == "custom" then
					local rgb = revColorOpt.rgb or { 1, 1, 1 }
					frame.nameText:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
				else
					frame.nameText:SetTextColor(1, 1, 1, 1)
				end
			end
			frame:SetAlpha(1)
		else
			sim.currentHP = math_max(0, sim.currentHP - dt * 80)
			if frame.healthBar then
				frame.healthBar:SetValue(sim.currentHP)
				frame.healthBar:SetStatusBarColor(dc[1], dc[2], dc[3])
			end
			frame:SetAlpha(appearance.deadAlpha or C.DEAD_ALPHA)
			if frame.healthText then frame.healthText:Hide() end
			if frame.statusText then
				frame.statusText:SetText("Dead")
				frame.statusText:Show()
			end
			if frame.nameText then
				frame.nameText:SetTextColor(dc[1], dc[2], dc[3])
			end
			return
		end
	end

	-- 체력 보간 (smooth lerp)
	if sim.currentHP ~= sim.targetHP then
		local diff = sim.targetHP - sim.currentHP
		local step = diff * SIM_LERP_SPEED * dt
		if math_abs(step) < 0.1 then
			step = (diff > 0) and 0.1 or -0.1
		end
		if math_abs(step) > math_abs(diff) then
			sim.currentHP = sim.targetHP
		else
			sim.currentHP = sim.currentHP + step
		end
		sim.currentHP = math_max(0, math_min(100, sim.currentHP))
	end

	-- 기력 보간
	if sim.currentPower ~= sim.targetPower then
		local diff = sim.targetPower - sim.currentPower
		local step = diff * 2.0 * dt
		if math_abs(step) < 0.1 then step = (diff > 0) and 0.1 or -0.1 end
		if math_abs(step) > math_abs(diff) then
			sim.currentPower = sim.targetPower
		else
			sim.currentPower = sim.currentPower + step
		end
		sim.currentPower = math_max(0, math_min(100, sim.currentPower))
	end

	-- 체력바 갱신 — [12.0.1] colorType 기반 색상 (Update.lua:ApplyHealthColor와 동일)
	if frame.healthBar then
		frame.healthBar:SetValue(sim.currentHP)

		local hp = sim.currentHP
		local r, g, b

		if sim.colorType == "smooth" then
			-- 그라디언트: 체력% 기반 빨강→노랑→초록
			local pct = hp / 100
			if pct > 0.5 then
				local t = (pct - 0.5) * 2
				r, g, b = 1 - t, 0.8 + 0.2 * t, 0
			else
				local t = pct * 2
				r, g, b = 1, t * 0.8, 0
			end
		else
			-- class/custom/reaction: 고정 색상 (실제 프레임과 동일)
			r, g, b = sim.color.r, sim.color.g, sim.color.b
		end

		frame.healthBar:SetStatusBarColor(r, g, b, 1)
	end

	-- [12.0.1] 힐예측 바 동기화 (체력 변화에 따라 비율 갱신)
	if frame.healPredictionBar and frame.healPredictionBar:IsShown() then
		local deficit = 100 - sim.currentHP
		frame.healPredictionBar:SetValue(math_min(deficit, 15))
	end

	-- [12.0.1] 보호막 동기화 (DandersFrames 패턴: 풀피 → overShieldBar, 비풀피 → absorbBar)
	local shieldSim = 15  -- 시뮬레이션 보호막 고정값
	local deficitSim = 100 - sim.currentHP
	local isSimFullHP = sim.currentHP >= 99.5
	local hasOver = shieldSim > deficitSim

	if isSimFullHP then
		-- 풀피: absorbBar 클리핑됨 → overShieldBar로 표시
		if frame.absorbBar then frame.absorbBar:Hide() end
		if frame.overShieldBar then
			frame.overShieldBar:SetMinMaxValues(0, 100)
			frame.overShieldBar:SetValue(shieldSim)
			frame.overShieldBar:Show()
		end
		if frame.overShieldGlow and frame.overShieldBar then
			local osTex = frame.overShieldBar:GetStatusBarTexture()
			if osTex then
				frame.overShieldGlow:ClearAllPoints()
				frame.overShieldGlow:SetPoint("TOP", osTex, "TOPLEFT", 0, 0)
				frame.overShieldGlow:SetPoint("BOTTOM", osTex, "BOTTOMLEFT", 0, 0)
				frame.overShieldGlow:SetWidth(3)
			end
			frame.overShieldGlow:Show()
		end
	else
		-- 비풀피: absorbBar 정상 + 초과분 overShieldBar
		if frame.absorbBar then frame.absorbBar:Show() end
		if frame.overShieldBar then
			if hasOver then
				frame.overShieldBar:SetMinMaxValues(0, 100)
				frame.overShieldBar:SetValue(shieldSim)
				frame.overShieldBar:Show()
			else
				frame.overShieldBar:Hide()
			end
		end
		if frame.overShieldGlow then
			if hasOver and frame.overShieldBar then
				local osTex = frame.overShieldBar:GetStatusBarTexture()
				if osTex then
					frame.overShieldGlow:ClearAllPoints()
					frame.overShieldGlow:SetPoint("TOP", osTex, "TOPLEFT", 0, 0)
					frame.overShieldGlow:SetPoint("BOTTOM", osTex, "BOTTOMLEFT", 0, 0)
					frame.overShieldGlow:SetWidth(3)
				end
				frame.overShieldGlow:Show()
			else
				frame.overShieldGlow:Hide()
			end
		end
	end

	-- 기력바 갱신
	if frame.powerBar and frame.powerBar:IsShown() then
		frame.powerBar:SetValue(sim.currentPower)
	end

	-- 체력 텍스트 갱신
	if frame.healthText and frame.healthText:IsShown() then
		local pct = math_floor(sim.currentHP + 0.5)
		if pct >= 100 then
			frame.healthText:SetText("")
		else
			frame.healthText:SetFormattedText("%d%%", pct)
		end
	end

	frame:SetAlpha(1)
end

-----------------------------------------------
-- 시뮬레이션 틱
-----------------------------------------------

local simElapsed = 0

local function SimulationTick(self, elapsed)
	if not TM.active then return end

	simElapsed = simElapsed + elapsed
	if simElapsed < SIM_TICK then return end
	local dt = simElapsed
	simElapsed = 0

	local ok, err = pcall(function()
		local allFrames = {}
		for _, f in ipairs(TM.partyFrames) do allFrames[#allFrames + 1] = f end
		for _, f in ipairs(TM.raidFrames) do allFrames[#allFrames + 1] = f end

		for _, frame in ipairs(allFrames) do
			if frame and frame._sim then
				frame._sim.nextEventTime = frame._sim.nextEventTime - dt
				if frame._sim.nextEventTime <= 0 then
					ProcessSimEvent(frame)
				end
				UpdateFrameVisual(frame, dt)
			end
		end
	end)

	if not ok then
		ns.Debug("TestMode sim error: " .. tostring(err))
	end

	-- [FIX] 만료된 쿨다운 재순환 (랜덤 지속시간으로 갱신)
	recycleElapsed = recycleElapsed + elapsed
	if recycleElapsed >= RECYCLE_CHECK_INTERVAL then
		recycleElapsed = 0
		RecycleExpiredCooldowns()
	end
end

-----------------------------------------------
-- 성장방향 배치 헬퍼
-----------------------------------------------

local function PositionFrame(f, index, container, w, h, spacing, growDir, totalCount)
	f:ClearAllPoints()
	local i = index - 1 -- 0-based

	if growDir == "H_CENTER" then
		-- [FIX] 가로 중앙 정렬: 컨테이너 중심 기준으로 좌우 대칭 배치
		local totalW = totalCount * w + (totalCount - 1) * spacing
		local startX = -totalW / 2
		f:SetPoint("TOPLEFT", container, "TOP", startX + i * (w + spacing), 0)
	elseif growDir == "V_CENTER" then
		-- [FIX] 세로 중앙 정렬: 컨테이너 중심 기준으로 상하 대칭 배치
		local totalH = totalCount * h + (totalCount - 1) * spacing
		local startY = totalH / 2
		f:SetPoint("TOPLEFT", container, "LEFT", 0, startY - i * (h + spacing))
	elseif growDir == "DOWN" then
		f:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i * (h + spacing)))
	elseif growDir == "UP" then
		f:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, i * (h + spacing))
	elseif growDir == "RIGHT" then
		f:SetPoint("TOPLEFT", container, "TOPLEFT", i * (w + spacing), 0)
	elseif growDir == "LEFT" then
		f:SetPoint("TOPRIGHT", container, "TOPRIGHT", -(i * (w + spacing)), 0)
	else
		f:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i * (h + spacing)))
	end
end

-----------------------------------------------
-- 파티 테스트 활성화
-----------------------------------------------

function TM:EnablePartyTest()
	local pdb = ns.db.party or {}
	if pdb.enabled == false then return end

	local w = (pdb.size and pdb.size[1]) or 120
	local h = (pdb.size and pdb.size[2]) or 36
	local spacing = pdb.spacing or 4
	local growDir = pdb.growDirection or "DOWN"
	local numMembers = pdb.showPlayer and 5 or 4

	-- 성장 방향 기반 컨테이너 크기
	local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
	local containerW, containerH
	if priIsVert then
		containerW = w
		containerH = numMembers * h + (numMembers - 1) * spacing
	else
		containerW = numMembers * w + (numMembers - 1) * spacing
		containerH = h
	end

	TM.partyContainer = CreateGroupContainer("ddingUI_GF_TestPartyContainer", UIParent)
	TM.partyContainer:SetSize(containerW, containerH)
	SetContainerFromMover(TM.partyContainer, "ddingUI_Mover_Party", pdb, "TOPLEFT", 20, -40)
	TM.partyContainer:Show()

	-- simContainers에 등록 (Mover.lua 호환)
	simContainers.party = TM.partyContainer

	-- 프레임 생성
	wipe(TM.partyFrames)
	for i = 1, numMembers do
		local data = FAKE_MEMBERS[i] or FAKE_MEMBERS[1]
		local f = TM:CreateTestFrame("ddingUI_GF_TestParty" .. i, TM.partyContainer, false, data)
		f:SetSize(w, h)
		f._testIdx = i -- [12.0.1] 디버프 하이라이트 색상 분산용
		PositionFrame(f, i, TM.partyContainer, w, h, spacing, growDir, numMembers)
		InitSimState(f, data)
		f:Show()
		TM.partyFrames[i] = f
	end
end

-----------------------------------------------
-- 레이드 테스트 활성화
-----------------------------------------------

function TM:EnableRaidTest()
	-- [MYTHIC-RAID] 활성 레이드 DB 참조
	local GF = ns.GroupFrames
	local rdb = (GF and GF.GetActiveRaidDB and GF:GetActiveRaidDB()) or ns.db.raid or {}
	if rdb.enabled == false then return end

	local w = (rdb.size and rdb.size[1]) or 66
	local h = (rdb.size and rdb.size[2]) or 46
	local spacingY = rdb.spacingY or rdb.spacing or 3
	local gSpacing = rdb.groupSpacing or 5
	local growDir = rdb.growDirection or "DOWN"

	-- 미리보기 인원수
	local moverDB = (ns.db and ns.db.mover) or {}
	local previewCount = moverDB.previewRaidCount or 20
	local previewGroups = math_ceil(previewCount / 5)

	-- [FIX] 성장 방향 기반 컨테이너 크기 + 그룹 간 배치 방향
	-- H_CENTER: 유닛 가로 → 그룹 세로(DOWN), V_CENTER: 유닛 세로 → 그룹 가로(RIGHT)
	local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
	local groupGrowDir = rdb.groupGrowDirection
	if not groupGrowDir then
		if priIsVert or growDir == "H_CENTER" then
			-- H_CENTER: 유닛이 가로지만 그룹은 세로. DOWN/UP/V_CENTER: 그룹 오른쪽
			groupGrowDir = (growDir == "H_CENTER") and "DOWN" or "RIGHT"
		else
			groupGrowDir = "DOWN"
		end
	end
	local groupIsHorz = (groupGrowDir == "RIGHT" or groupGrowDir == "LEFT")

	local containerW, containerH
	if groupIsHorz then
		-- 그룹 가로: 컨테이너 가로 = 그룹수 × w, 세로 = 5멤버 × h
		containerW = previewGroups * w + (previewGroups - 1) * gSpacing
		containerH = 5 * h + 4 * spacingY
	else
		-- 그룹 세로: 컨테이너 가로 = 5멤버 × w, 세로 = 그룹수 × h
		containerW = 5 * w + 4 * spacingY
		containerH = previewGroups * h + (previewGroups - 1) * gSpacing
	end

	TM.raidContainer = CreateGroupContainer("ddingUI_GF_TestRaidContainer", UIParent)
	TM.raidContainer:SetSize(containerW, containerH)
	SetContainerFromMover(TM.raidContainer, "ddingUI_Mover_Raid", rdb, "TOPLEFT", 20, -100)
	TM.raidContainer:Show()

	simContainers.raid = TM.raidContainer

	-- 프레임 생성 (그룹별 5명 × N그룹)
	wipe(TM.raidFrames)
	local membersPerGroup = 5
	for i = 1, previewCount do
		local groupIdx = math_ceil(i / membersPerGroup) - 1
		local memberIdx = (i - 1) % membersPerGroup

		local data = FAKE_MEMBERS[i] or FAKE_MEMBERS[((i - 1) % #FAKE_MEMBERS) + 1]
		local f = TM:CreateTestFrame("ddingUI_GF_TestRaid" .. i, TM.raidContainer, true, data)
		f:SetSize(w, h)
		f._testIdx = i -- [12.0.1] 디버프 하이라이트 색상 분산용
		f:ClearAllPoints()

		local xOff, yOff

		if growDir == "H_CENTER" then
			-- [FIX] 가로 중앙 정렬: 유닛 가로 중앙, 그룹 세로 배치
			local rowW = membersPerGroup * w + (membersPerGroup - 1) * spacingY
			local startX = -rowW / 2
			xOff = startX + memberIdx * (w + spacingY)
			yOff = -(groupIdx * (h + gSpacing))
			f:SetPoint("TOPLEFT", TM.raidContainer, "TOP", xOff, yOff)
		elseif growDir == "V_CENTER" then
			-- [FIX] 세로 중앙 정렬: 유닛 세로 중앙, 그룹 가로 배치
			local colH = membersPerGroup * h + (membersPerGroup - 1) * spacingY
			local startY = colH / 2
			xOff = groupIdx * (w + gSpacing)
			yOff = startY - memberIdx * (h + spacingY)
			f:SetPoint("TOPLEFT", TM.raidContainer, "LEFT", xOff, yOff)
		elseif groupIsHorz then
			xOff = groupIdx * (w + gSpacing)
			yOff = -(memberIdx * (h + spacingY))
			f:SetPoint("TOPLEFT", TM.raidContainer, "TOPLEFT", xOff, yOff)
		else
			xOff = memberIdx * (w + spacingY)
			yOff = -(groupIdx * (h + gSpacing))
			f:SetPoint("TOPLEFT", TM.raidContainer, "TOPLEFT", xOff, yOff)
		end

		InitSimState(f, data)
		f:Show()
		TM.raidFrames[i] = f
	end
end

-----------------------------------------------
-- 시뮬레이션 시작/중지
-----------------------------------------------

function TM:StartSimulation()
	if not TM.simDriver then
		TM.simDriver = CreateFrame("Frame", "ddingUI_GF_TestSimDriver", UIParent)
	end
	TM.simDriver:SetScript("OnUpdate", SimulationTick)
	TM.simDriver:Show()
end

function TM:StopSimulation()
	if TM.simDriver then
		TM.simDriver:SetScript("OnUpdate", nil)
		TM.simDriver:Hide()
	end
end

-----------------------------------------------
-- 실제 헤더 숨기기/보이기
-----------------------------------------------

function TM:HideRealHeaders()
	if InCombatLockdown() then return end

	if GF.partyHeader and GF.partyHeader:IsShown() then
		GF.partyHeader:Hide()
	end
	for _, header in ipairs(GF.raidHeaders or {}) do
		if header and header:IsShown() then
			header:Hide()
		end
	end
end

function TM:ShowRealHeaders()
	if InCombatLockdown() then return end

	-- [FIX] Header visibility는 state driver가 제어하므로
	-- 단순 Show()가 아닌 attribute driver를 통해 복원해야 할 수 있음
	-- 하지만 편집모드 종료 후 그룹 변경 이벤트가 다시 트리거하므로 Show()로 충분
	if GF.partyHeader then
		GF.partyHeader:Show()
	end
	for _, header in ipairs(GF.raidHeaders or {}) do
		if header then
			header:Show()
		end
	end
end

-----------------------------------------------
-- 테스트 프레임 파괴
-----------------------------------------------

function TM:DestroyTestFrames()
	for _, f in ipairs(TM.partyFrames) do
		if f then
			TM:ClearDummyAuras(f) -- [12.0.1] 오라 쿨다운 정리
			f:Hide()
			f:ClearAllPoints()
			f._sim = nil
		end
	end
	wipe(TM.partyFrames)

	for _, f in ipairs(TM.raidFrames) do
		if f then
			TM:ClearDummyAuras(f) -- [12.0.1] 오라 쿨다운 정리
			f:Hide()
			f:ClearAllPoints()
			f._sim = nil
		end
	end
	wipe(TM.raidFrames)

	if TM.partyContainer then
		TM.partyContainer:Hide()
	end
	if TM.raidContainer then
		TM.raidContainer:Hide()
	end
end

-----------------------------------------------
-- 공개 API: Enable / Disable
-----------------------------------------------

function TM:Enable()
	if TM.active then return end
	if InCombatLockdown() then
		ns.Print("|cffff0000전투 중에는 테스트모드를 시작할 수 없습니다.|r")
		return
	end

	-- simContainers 참조 갱신 (Core/Update.lua에서 선언됨)
	simContainers = ns.simContainers or simContainers

	TM:HideRealHeaders()
	TM:EnablePartyTest()
	TM:EnableRaidTest()
	TM:StartSimulation()

	TM.active = true
	recycleElapsed = 0 -- [FIX] 쿨다운 재순환 타이머 리셋

	-- [TEST MODE] colorTimerFrame 활성화 (임계값/그라데이션 지속시간 색상 갱신)
	if GF.UpdateColorTimerState then
		GF:UpdateColorTimerState()
	end

	ns.Debug("GroupFrames TestMode enabled: "
		.. #TM.partyFrames .. " party, "
		.. #TM.raidFrames .. " raid")
end

function TM:Disable()
	if not TM.active then return end

	TM:StopSimulation()
	TM:DestroyTestFrames()
	TM:ShowRealHeaders()

	-- simContainers에서 party/raid 제거 (개인유닛은 Core/Update.lua가 관리)
	simContainers.party = nil
	simContainers.raid = nil

	TM.active = false

	-- [TEST MODE] colorTimerFrame 비활성화 (솔로 시 불필요)
	if GF.UpdateColorTimerState then
		GF:UpdateColorTimerState()
	end

	ns.Debug("GroupFrames TestMode disabled")
end

-----------------------------------------------
-- 설정 변경 시 실시간 갱신
-----------------------------------------------

function TM:RefreshAll()
	if not TM.active then return end

	-- 파티: 전체 재생성 (크기/방향 변경 가능)
	TM:DestroyPartyFrames()
	TM:EnablePartyTest()

	-- 레이드: 전체 재생성
	TM:DestroyRaidFrames()
	TM:EnableRaidTest()
end

function TM:RefreshParty()
	if not TM.active then return end
	TM:DestroyPartyFrames()
	TM:EnablePartyTest()
end

function TM:RefreshRaid()
	if not TM.active then return end
	TM:DestroyRaidFrames()
	TM:EnableRaidTest()
end

-- [FIX] 프라이빗 오라만 경량 갱신 (DandersFrame UpdateAllTestBossDebuffs 패턴)
-- 전체 프레임 재생성 없이 위치/크기/비주얼만 업데이트
function TM:RefreshPrivateAuras()
	if not TM.active then return end
	local GF = ns.GroupFrames
	local allTestFrames = {}
	for _, f in ipairs(TM.partyFrames) do allTestFrames[#allTestFrames + 1] = f end
	for _, f in ipairs(TM.raidFrames) do allTestFrames[#allTestFrames + 1] = f end

	for _, f in ipairs(allTestFrames) do
		if f and f.privateAuraAnchors then
			-- DB에서 최신 설정 읽기
			local db = GF:GetFrameDB(f)
			if not db then break end
			local widgets = db.widgets or {}
			local paDB = widgets.privateAuras or {}

			-- 앵커 크기/위치 재계산 (Create.lua ApplyLayout과 동일)
			local paScale = paDB.scale or 1.0
			local paSizeDB = paDB.size or {}
			local paW = (paSizeDB.width or 24) * paScale
			local paH = (paSizeDB.height or 24) * paScale
			local paSpacingDB = paDB.spacing or {}
			local paHSpacing = paSpacingDB.horizontal or 2
			local paPos = paDB.position or {}
			local paMax = paDB.maxAuras or 2
			local paPoint = paPos.point or "CENTER"
			local paRelPoint = paPos.relativePoint or "CENTER"
			local paOX = paPos.offsetX or 0
			local paOY = paPos.offsetY or 0

			for i = 1, #f.privateAuraAnchors do
				local anchor = f.privateAuraAnchors[i]
				if anchor then
					anchor:SetSize(paW, paH)
					anchor:ClearAllPoints()
					local offset = ((i - 1) - (paMax - 1) / 2) * (paW + paHSpacing)
					anchor:SetPoint(paPoint, f, paRelPoint, paOX + offset, paOY)
				end
			end

			-- 비주얼 갱신 (ApplyDummyAuras 프라이빗 오라 섹션 재실행)
			local isDead = f._fakeData and f._fakeData.isDead
			if paDB.enabled ~= false and not isDead then
				local fakeData = f._fakeData
				local showPA = fakeData and (fakeData.role == "HEALER")
				local numPA = showPA and math_min(1, #f.privateAuraAnchors) or 0

				for i = 1, numPA do
					local anchor = f.privateAuraAnchors[i]
					if anchor then
						if not anchor._testBG then
							anchor._testBG = anchor:CreateTexture(nil, "BACKGROUND")
							anchor._testBG:SetAllPoints()
							anchor._testBG:SetTexture(FLAT)
							anchor._testBG:SetVertexColor(0.05, 0.05, 0.05, 0.9)
						end
						if not anchor._testIcon then
							anchor._testIcon = anchor:CreateTexture(nil, "ARTWORK")
							anchor._testIcon:SetAllPoints()
							anchor._testIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
						end
						anchor._testIcon:SetTexture(PRIVATE_AURA_PLACEHOLDER)
						anchor._testIcon:Show()
						anchor._testBG:Show()
						anchor:Show()
					end
				end
				for i = numPA + 1, #f.privateAuraAnchors do
					local anchor = f.privateAuraAnchors[i]
					if anchor then
						if anchor._testIcon then anchor._testIcon:Hide() end
						if anchor._testBG then anchor._testBG:Hide() end
						anchor:Hide()
					end
				end
			else
				for _, anchor in ipairs(f.privateAuraAnchors) do
					if anchor then
						if anchor._testIcon then anchor._testIcon:Hide() end
						if anchor._testBG then anchor._testBG:Hide() end
						anchor:Hide()
					end
				end
			end
		end
	end
end

-- 개별 파괴 헬퍼
function TM:DestroyPartyFrames()
	for _, f in ipairs(TM.partyFrames) do
		if f then TM:ClearDummyAuras(f); f:Hide(); f._sim = nil end
	end
	wipe(TM.partyFrames)
	if TM.partyContainer then TM.partyContainer:Hide() end
end

function TM:DestroyRaidFrames()
	for _, f in ipairs(TM.raidFrames) do
		if f then TM:ClearDummyAuras(f); f:Hide(); f._sim = nil end
	end
	wipe(TM.raidFrames)
	if TM.raidContainer then TM.raidContainer:Hide() end
end

-----------------------------------------------
-- 전투 진입 시 자동 종료
-----------------------------------------------

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function()
	if TM.active then
		TM:Disable()
		ns.Print("|cffff0000전투 진입 — 테스트모드 자동 종료|r")
	end
end)
