--[[
	ddingUI UnitFrames
	GroupFrames/Auras.lua — 2단계 아우라 시스템

	Phase 1: hooksecurefunc(CompactUnitFrame_UpdateAuras) → BlizzardAuraCache 캡처
	Phase 2: Secret-safe API로 커스텀 아이콘 렌더링

	DandersFrames Auras.lua 패턴 차용:
	- CaptureAurasFromBlizzardFrame (Phase 1)
	- UpdateAuraIconsDirect (Phase 2)
	- 공유 타이머 (per-icon OnUpdate 제거)
	- Secret-safe: GetAuraDataByAuraInstanceID, GetAuraApplicationDisplayCount,
	  DoesAuraHaveExpirationTime, SetCooldownFromExpirationTime
]]

local _, ns = ...
local GF = ns.GroupFrames

local C_UnitAuras = C_UnitAuras
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local GetTime = GetTime
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue
local IsInGroup = IsInGroup   -- [PERF] colorTimerFrame 그룹 체크
local IsInRaid = IsInRaid     -- [PERF]
local SafeVal = ns.SafeVal   -- [REFACTOR] 통합 유틸리티
local SafeNum = ns.SafeNum   -- [REFACTOR]
local SafeBool = ns.SafeBool -- [REFACTOR]
local C = ns.Constants       -- [FIX] ns.C → ns.Constants

-----------------------------------------------
-- BlizzardAuraCache
-----------------------------------------------

local BlizzardAuraCache = {}  -- unit → { buffs={id=true}, debuffs={id=true}, defensives={id=true}, buffOrder={}, debuffOrder={} }
local BlizzardCacheGUIDMap = {} -- GUID → unit key
local BlizzardCacheValid = {} -- unit → true

GF.BlizzardAuraCache = BlizzardAuraCache

-----------------------------------------------
-- Phase 1: 블리자드 프레임에서 아우라 캡처
-- [PERF] 3단계 최적화:
--   1. 유닛 필터: 파티/레이드/플레이어만 (네임플레이트/보스/아레나 제외)
--   2. 더티 배치: 동일 게임프레임 내 중복 hook 호출 병합
--   3. GUID 역조회 제거: 직접 조회만 (그룹 유닛은 항상 직접 매칭)
-----------------------------------------------

-- [PERF] 유닛 필터: 그룹 유닛만 true
local function IsGroupUnit(unit)
	if unit == "player" then return true end
	local prefix = unit:match("^(%a+)")
	return prefix == "party" or prefix == "raid"
end

-- [PERF] 더티 유닛 큐 (실제 처리는 다음 OnUpdate에서 배치)
local dirtyAuraFrames = {} -- unit → blizzFrame
local hasDirtyAuras = false

-- [REFACTOR] QueueAuraUpdate: 프레임 단위 렌더링 큐 (Cell_UF 패턴)
-- 여러 위젯이 동시에 UpdateAuras 요청 시 1프레임에 1회만 처리
local dirtyRenderFrames = {} -- frame → true
local hasDirtyRender = false

-- [REFACTOR] Phase 1 Core Engine: Direct Scan Logic
-- Instead of hooking Blizzard UI, we iterate C_UnitAuras directly to populate the cache.
-- This decouples DDingUI from the sluggish CompactUnitFrame update loop.

local function ShouldDisplayBuff(unit, aura)
	local auraInstanceID = aura.auraInstanceID
	if not auraInstanceID then return false end
	
	-- 12.0.1+ Native C-Level checks: Avoids ANY 'secret boolean' crashes by running checks in C++.
	-- `IsAuraFilteredOutByInstanceID` returns false if the aura MATCHES the filter.
	
	-- Check if cast by player
	local isPlayer = not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL|PLAYER")
	if isPlayer then return true end
	
	-- Check if it's a raid mechanic/buff
	local isRaid = not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL|RAID")
	if isRaid then return true end
	
	-- Check if it's explicitly marked as important by Blizzard
	if AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.Important then
		local isImportant = not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL|"..AuraUtil.AuraFilters.Important)
		if isImportant then return true end
	end
	
	-- Fallback for boss auras if not caught by raid 
	if SafeBool(aura.isBossAura) then
		return true
	end

	-- 핵심 외생기 수동 검사 (타인이 걸어줘도 표시)
	if GF.IsDefensiveAura and GF:IsDefensiveAura(aura.spellId) then 
		return true 
	end

	return false
end

local function ShouldDisplayDebuff(unit, aura)
	local auraInstanceID = aura.auraInstanceID
	if not auraInstanceID then return false end
	
	-- 12.0.1+ 최신 API 기준: 'nameplateOnly' 잡동사니 제거 및 C-Level 검증 수행
	-- Secret Value 크래시 우려가 있는 속성(isFromPlayerOrPlayerPet) 절대 직접 비교 금지 
	if aura.nameplateOnly and type(aura.nameplateOnly) ~= "userdata" then return false end
	
	-- 기본적으로 파티 프레임상 디버프는 거의 다 띄우되 필터링이 필요할 수 있음
	return true
end

-- ============================================================
-- [DANDERSFRAMES BLIZZARD MODE] — 블리자드 프레임 스크래핑
-- DDingUI의 HideBlizzard.lua는 파티/레이드 프레임을 SetAlpha(0)으로 숨기되
-- 이벤트(UNIT_AURA 포함)는 살려둡니다.
-- 따라서 블리자드 엔진이 buffFrames/debuffFrames를 계속 갱신하고 있으며,
-- 댄더스 프레임과 100% 동일하게 그 데이터를 '그대로' 복사할 수 있습니다.
-- ============================================================

-- 블리자드 CompactUnitFrame이 오라 업데이트를 끝낸 직후 호출되어
-- buffFrames/debuffFrames의 auraInstanceID를 그대로 캐시에 복사합니다.
-- 댄더스의 CaptureAurasFromBlizzardFrame과 100% 동일한 로직입니다.
local function CaptureAurasFromBlizzardFrame(frame)
	if not frame or not frame.unit then return end
	if frame.unitExists == false then return end

	local unit = frame.unit
	if type(unit) ~= "string" then return end
	if unit:find("nameplate") or unit:find("boss") then return end

	local frameName = frame.GetName and frame:GetName()
	if frameName and (frameName:find("Preview") or frameName:find("Settings")) then return end

	if not IsGroupUnit(unit) then return end

	-- 캐시 초기화
	if not BlizzardAuraCache[unit] then
		BlizzardAuraCache[unit] = { buffs = {}, debuffs = {}, defensives = {}, buffOrder = {}, debuffOrder = {} }
	end
	local cache = BlizzardAuraCache[unit]
	wipe(cache.buffs)
	wipe(cache.debuffs)
	wipe(cache.defensives)
	wipe(cache.buffOrder)
	wipe(cache.debuffOrder)
	BlizzardCacheValid[unit] = true

	local guid = SafeVal(UnitGUID(unit))
	if guid then
		BlizzardCacheGUIDMap[guid] = unit
	end

	-- [DANDERSFRAMES 동일] 버프: buffFrames 순서 그대로 복사 (buffOrder 배열로 순서 보존)
	if frame.buffFrames and type(frame.buffFrames) == "table" then
		for _, bf in ipairs(frame.buffFrames) do
			if bf and bf.IsShown and bf:IsShown() and bf.auraInstanceID then
				cache.buffs[bf.auraInstanceID] = true
				cache.buffOrder[#cache.buffOrder + 1] = bf.auraInstanceID
			end
		end
	end

	-- [DANDERSFRAMES 동일] 디버프: debuffFrames 순서 그대로 복사
	if frame.debuffFrames and type(frame.debuffFrames) == "table" then
		for _, df in ipairs(frame.debuffFrames) do
			if df and df.IsShown and df:IsShown() and df.auraInstanceID then
				cache.debuffs[df.auraInstanceID] = true
				cache.debuffOrder[#cache.debuffOrder + 1] = df.auraInstanceID
			end
		end
	end

	-- [DANDERSFRAMES 동일] 해제 가능 디버프
	if frame.dispelDebuffFrames and type(frame.dispelDebuffFrames) == "table" then
		for _, df in ipairs(frame.dispelDebuffFrames) do
			if df and df.IsShown and df:IsShown() and df.auraInstanceID then
				if not cache.debuffs[df.auraInstanceID] then
					cache.debuffs[df.auraInstanceID] = true
					cache.debuffOrder[#cache.debuffOrder + 1] = df.auraInstanceID
				end
			end
		end
	end

	-- 중앙 생존기
	if frame.CenterDefensiveBuff and frame.CenterDefensiveBuff.IsShown 
		and frame.CenterDefensiveBuff:IsShown() and frame.CenterDefensiveBuff.auraInstanceID then
		cache.defensives[frame.CenterDefensiveBuff.auraInstanceID] = true
	end

	-- DDingUI 프레임 렌더링 트리거
	local ourFrame = GF.unitFrameMap[unit]
	if ourFrame and ourFrame.gfEventsEnabled then
		dirtyRenderFrames[ourFrame] = true
		hasDirtyRender = true
		dirtyProcessor:Show()

		if GF.UpdateDefensiveIcon then
			GF:UpdateDefensiveIcon(ourFrame)
		end
	end
end

-- DirectMarkAuraDirty: 블리자드 훅이 아직 캐시를 채우지 않은 유닛용 폴백
local function DirectMarkAuraDirty(unit)
	if not unit or not IsGroupUnit(unit) then return end

	-- 이미 블리자드 훅이 캐시를 채웠다면 렌더링만 트리거
	if BlizzardCacheValid[unit] and BlizzardAuraCache[unit] then
		local frame = GF.unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			dirtyRenderFrames[frame] = true
			hasDirtyRender = true
			dirtyProcessor:Show()
		end
		return
	end

	-- 캐시가 없는 경우에만 C-Level 폴백 스캔 (초기 로딩 등)
	if not BlizzardAuraCache[unit] then
		BlizzardAuraCache[unit] = { buffs = {}, debuffs = {}, defensives = {}, buffOrder = {}, debuffOrder = {} }
	end
	local cache = BlizzardAuraCache[unit]
	wipe(cache.buffs)
	wipe(cache.debuffs)
	wipe(cache.defensives)
	wipe(cache.buffOrder)
	wipe(cache.debuffOrder)
	BlizzardCacheValid[unit] = true

	local guid = SafeVal(UnitGUID(unit))
	if guid then
		BlizzardCacheGUIDMap[guid] = unit
	end

	-- C-Level 폴백: 블리자드 훅 데이터가 없을 때만 작동
	local harmfulRaidFilter = "HARMFUL|RAID"
	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, harmfulRaidFilter)
		if not aura then break end
		if aura.auraInstanceID then
			cache.debuffs[aura.auraInstanceID] = true
			cache.debuffOrder[#cache.debuffOrder + 1] = aura.auraInstanceID
		end
	end

	local frame = GF.unitFrameMap[unit]
	if frame and frame.gfEventsEnabled then
		dirtyRenderFrames[frame] = true
		hasDirtyRender = true
		dirtyProcessor:Show()
	end
end

-- [REFACTOR] QueueAuraUpdate: 프레임 렌더링을 큐에 추가
-- GF:UpdateAuras 직접 호출 대신 이것을 사용하면 1프레임 1회 보장
function GF:QueueAuraUpdate(frame)
	if not frame then return end
	dirtyRenderFrames[frame] = true
	hasDirtyRender = true
	dirtyProcessor:Show()
end

-- [REFACTOR] ProcessDirtyAuras is mostly simplified since Phase A cache injection is gone!
local function ProcessDirtyAuras()
	-- Phase B: 프레임 렌더링 (큐된 모든 프레임 1회씩만)
	if hasDirtyRender then
		hasDirtyRender = false
		local debugMode = ns._debugMode

		for frame in pairs(dirtyRenderFrames) do
			if frame.unit and frame.gfEventsEnabled then
				if debugMode then
					local ok, err = pcall(function()
						GF:UpdateAuras(frame)
						if GF.UpdateDebuffHighlight then GF:UpdateDebuffHighlight(frame) end
						if GF.UpdateDefensiveIcon then GF:UpdateDefensiveIcon(frame) end
						local adEngine = ns.AuraDesigner and ns.AuraDesigner.Engine
						if adEngine and adEngine.hasActiveIndicators then
							adEngine:UpdateGroupFrame(frame)
						end
					end)
					if not ok then ns:PrintDebug("UpdateFrame error: " .. tostring(err)) end
				else
					GF:UpdateAuras(frame)
					if GF.UpdateDebuffHighlight then GF:UpdateDebuffHighlight(frame) end
					if GF.UpdateDefensiveIcon then GF:UpdateDefensiveIcon(frame) end
					local adEngine = ns.AuraDesigner and ns.AuraDesigner.Engine
					if adEngine and adEngine.hasActiveIndicators then
						adEngine:UpdateGroupFrame(frame)
					end
				end
			end
		end
		wipe(dirtyRenderFrames)
	end
end

-- [PERF] 더티 프로세서: Show/Hide로 OnUpdate 활성/비활성화
dirtyProcessor = CreateFrame("Frame")
dirtyProcessor:Hide()
dirtyProcessor:SetScript("OnUpdate", function(self)
	self:Hide()
	ProcessDirtyAuras()
end)

-----------------------------------------------
-- Phase 1: Hook 설정
-----------------------------------------------

function GF:SetupBlizzardHooks()
	-- [REFACTOR] Phase 1 Core Engine: ALL BLIZZARD HOOKS REMOVED.
	-- We dynamically build our own cache via DirectMarkAuraDirty on events.
	
	-- 그룹 변경 시 캐시 리셋
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function()
		wipe(BlizzardAuraCache)
		wipe(BlizzardCacheGUIDMap)
		wipe(BlizzardCacheValid)
		wipe(dirtyRenderFrames)
		hasDirtyRender = false
		dirtyProcessor:Hide()

		-- [PERF] 그룹 상태에 따라 colorTimerFrame 활성/비활성
		if GF.UpdateColorTimerState then
			GF:UpdateColorTimerState()
		end

	end)

	-- [DANDERSFRAMES PATTERN] 캐시 갱신은 CompactUnitFrame_UpdateAuras 훅만 담당!
	-- UNIT_AURA 핸들러는 캐시/렌더를 건드리지 않고, AuraDesigner에게만 페이로드를 전달합니다.
	-- 댄더스 프레임과 동일한 단일 트리거 아키텍처입니다.
	local unitAuraHandler = CreateFrame("Frame")
	-- [PERF] 이벤트 등록은 SetupBlizzardHooks 호출 시에만 (비활성 시 CPU 0)
	unitAuraHandler:RegisterEvent("UNIT_AURA")
	unitAuraHandler:SetScript("OnEvent", function(_, _, unit, updateInfo)
		if not unit or not IsGroupUnit(unit) then return end
		if not GF.headersInitialized then return end

		-- AuraDesigner에게만 페이로드 원본 전달 (캐시/렌더 터치 금지)
		if updateInfo then
			local adAdapter = ns.AuraDesigner and ns.AuraDesigner.Adapter
			if adAdapter and adAdapter.OnUnitAuraEvent then
				local adChanged = adAdapter:OnUnitAuraEvent(unit, updateInfo)
				if adChanged then
					local frame = GF.unitFrameMap[unit]
					if frame and frame.gfEventsEnabled then
						dirtyRenderFrames[frame] = true
						hasDirtyRender = true
						dirtyProcessor:Show()
					end
				end
			end
		end
	end)
	
	-- [DANDERSFRAMES BLIZZARD MODE] CompactUnitFrame_UpdateAuras 훅
	-- 블리자드가 오라 업데이트를 끝낸 직후 buffFrames/debuffFrames를 스크래핑합니다.
	-- 이것이 댄더스 프레임의 핵심 훅이며, DDingUI에서도 동일하게 사용합니다.
	if CompactUnitFrame_UpdateAuras then
		hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
			if not frame or frame.unitExists == false then return end
			CaptureAurasFromBlizzardFrame(frame)
		end)
	end
	if CompactUnitFrame_UpdateBuffs then
		hooksecurefunc("CompactUnitFrame_UpdateBuffs", function(frame)
			if not frame or frame.unitExists == false then return end
			CaptureAurasFromBlizzardFrame(frame)
		end)
	end
	if CompactUnitFrame_UpdateDebuffs then
		hooksecurefunc("CompactUnitFrame_UpdateDebuffs", function(frame)
			if not frame or frame.unitExists == false then return end
			CaptureAurasFromBlizzardFrame(frame)
		end)
	end

	-- [DANDERSFRAMES 동일] CompactUnitFrame_UpdateUnitEvents 훅
	-- 블리자드가 이벤트를 재등록할 때마다 UNIT_AURA만 남기고 나머지를 스트립
	-- DDingUI는 블리자드 프레임을 시각적으로만 숨기므로 이벤트 관리가 필수
	if CompactUnitFrame_UpdateUnitEvents then
		hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
			if not frame or not frame.unit then return end
			local unit = frame.unit
			if not IsGroupUnit(unit) then return end
			-- UNIT_AURA만 유지하고 나머지 불필요한 이벤트 해제
			pcall(function()
				frame:UnregisterAllEvents()
				frame:RegisterUnitEvent("UNIT_AURA", unit)
			end)
		end)
	end
end

-- [COMPAT] 외부에서 호출 가능한 폴백 (GF:ScheduleBlizzardFrameScan 호출 처)
function GF:ScanBlizzardFrames() end
function GF:ScheduleBlizzardFrameScan() end

-----------------------------------------------
-- Phase 1: 캐시 조회 (GUID 폴백)
-----------------------------------------------

local function FindCacheForUnit(unit)
	-- 직접 조회
	if BlizzardCacheValid[unit] then
		return BlizzardAuraCache[unit]
	end

	-- GUID로 역조회 -- [REFACTOR] SafeVal 통일
	local guid = SafeVal(UnitGUID(unit))
	if guid then
		local cacheUnit = BlizzardCacheGUIDMap[guid]
		if cacheUnit and BlizzardCacheValid[cacheUnit] then
			return BlizzardAuraCache[cacheUnit]
		end
	end

	return nil
end

-----------------------------------------------
-- Phase 2: Secret-Safe 렌더링 헬퍼
-----------------------------------------------

-- SafeSetTexture: SetTexture는 C++에서 secret 처리 → nil/secret 모두 안전
-- [FIX] "if texture then"은 secret value에서 크래시 → 조건 제거
local function SafeSetTexture(icon, texture)
	if icon and icon.texture then
		-- texture가 nil이면 Clear, secret이면 C++이 해석, 일반값이면 그대로 설정
		icon.texture:SetTexture(texture)
	end
end

-- [DANDERSFRAMES 동일] SafeSetCooldown: 항상 호출 (C++ 내부에서 중복 값 무시)
local function SafeSetCooldown(cooldown, expirationTime, duration)
	if not cooldown then return end
	if not expirationTime or not duration then
		if cooldown.Clear then cooldown:Clear() end
		return
	end
	if cooldown.SetCooldownFromExpirationTime then
		cooldown:SetCooldownFromExpirationTime(expirationTime, duration)
	else
		local startTime = expirationTime - duration
		if startTime > 0 and duration > 0 then
			cooldown:SetCooldown(startTime, duration)
		end
	end
end

-----------------------------------------------
-- Phase 2: UpdateAuras — 아우라 아이콘 렌더링
-----------------------------------------------

function GF:UpdateAuras(frame)
	if not frame or not frame.unit then return end
	local unit = frame.unit
	if not UnitExists(unit) then return end

	-- [DANDERSFRAMES 동일] 캐시 기반 렌더링 (orderList 사용)
	self:UpdateAuraIconsDirect(frame, frame.buffIcons, nil, unit, "BUFF")
	self:UpdateAuraIconsDirect(frame, frame.debuffIcons, nil, unit, "DEBUFF")
end

-----------------------------------------------
-- Phase 2: UpdateAuraIconsDirect
-- [DANDERSFRAMES 동일] buffOrder/debuffOrder 배열 순서대로 렌더링
-----------------------------------------------

-----------------------------------------------
-- [FIX] ColorCurve (DandersFrame 패턴: lazy 생성)
-- dispelColorCurve: 아이콘 테두리용 (None=빨강, 모든 타입 색상)
-- highlightCurve: 프레임 하이라이트용 (None=alpha 0, 디스펠 가능 타입만)
-----------------------------------------------

-- [FIX] DandersFrames Dispel.lua 패턴: dispelType 숫자 상수
-- SpellDispelType enum: None=0, Magic=1, Curse=2, Disease=3, Poison=4, Enrage=9, Bleed=11
-- Enrage/Bleed는 표준 디스펠 타입이 아님 → 디스펠 하이라이트에서 제외해야 함
-- 블러드러스트(Sated/Exhaustion)는 dispelType=nil(None)이지만,
-- Enrage(9)/Bleed(11)이 빨간색으로 표시되면 출혈과 혼동됨
local DISPEL_TYPE_ENRAGE = 9
local DISPEL_TYPE_BLEED = 11

local function BuildDispelCurve(includeNone)
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)

	local dc = C and C.DISPEL_COLORS or {}
	local none    = dc.none    or { 0.80, 0.00, 0.00 }
	local magic   = dc.Magic   or { 0.20, 0.60, 1.00 }
	local curse   = dc.Curse   or { 0.60, 0.00, 1.00 }
	local disease = dc.Disease or { 0.60, 0.40, 0.00 }
	local poison  = dc.Poison  or { 0.00, 0.60, 0.00 }
	local bleed   = dc.Bleed   or { 0.80, 0.00, 0.00 }

	curve:AddPoint(0,  CreateColor(none[1], none[2], none[3], includeNone and 1 or 0))  -- None
	curve:AddPoint(1,  CreateColor(magic[1],   magic[2],   magic[3],   1))  -- Magic
	curve:AddPoint(2,  CreateColor(curse[1],   curse[2],   curse[3],   1))  -- Curse
	curve:AddPoint(3,  CreateColor(disease[1], disease[2], disease[3], 1))  -- Disease
	curve:AddPoint(4,  CreateColor(poison[1],  poison[2],  poison[3],  1))  -- Poison
	-- [FIX] Enrage(9)/Bleed(11): Bleed 전용 색상 사용 (DandersFrames 패턴)
	curve:AddPoint(9,  CreateColor(bleed[1], bleed[2], bleed[3], includeNone and 1 or 0))  -- Enrage
	curve:AddPoint(11, CreateColor(bleed[1], bleed[2], bleed[3], includeNone and 1 or 0))  -- Bleed

	return curve
end

-- [FIX] Bleed 전용 curve: dispelType=9(Enrage)/11(Bleed)만 alpha=1, 나머지 alpha=0
-- UpdateDebuffHighlight SLOW PATH에서 Bleed/Enrage 탐지에 사용
local bleedDetectCurve

local function GetBleedDetectCurve()
	if not bleedDetectCurve and C_CurveUtil and C_CurveUtil.CreateColorCurve then
		local ok, curve = pcall(function()
			local c = C_CurveUtil.CreateColorCurve()
			c:SetType(Enum.LuaCurveType.Step)
			local dc = C and C.DISPEL_COLORS or {}
			local bleed = dc.Bleed or { 0.80, 0.00, 0.00 }
			-- 모든 타입을 등록하되, Bleed/Enrage만 alpha=1
			c:AddPoint(0,  CreateColor(0, 0, 0, 0))  -- None
			c:AddPoint(1,  CreateColor(0, 0, 0, 0))  -- Magic
			c:AddPoint(2,  CreateColor(0, 0, 0, 0))  -- Curse
			c:AddPoint(3,  CreateColor(0, 0, 0, 0))  -- Disease
			c:AddPoint(4,  CreateColor(0, 0, 0, 0))  -- Poison
			c:AddPoint(9,  CreateColor(bleed[1], bleed[2], bleed[3], 1))  -- Enrage
			c:AddPoint(11, CreateColor(bleed[1], bleed[2], bleed[3], 1))  -- Bleed
			return c
		end)
		if ok and curve then
			bleedDetectCurve = curve
		end
	end
	return bleedDetectCurve
end

local dispelColorCurve
local highlightCurve

local function GetDispelColorCurve()
	if not dispelColorCurve and C_CurveUtil and C_CurveUtil.CreateColorCurve then
		-- [FIX] pcall 보호: Enum.LuaCurveType 등 API 변경 시 silent failure 방지
		local ok, curve = pcall(BuildDispelCurve, true)
		if ok and curve then
			dispelColorCurve = curve
		end
	end
	return dispelColorCurve
end

local function GetHighlightCurve()
	if not highlightCurve and C_CurveUtil and C_CurveUtil.CreateColorCurve then
		-- [FIX] pcall 보호: Enum.LuaCurveType 등 API 변경 시 silent failure 방지
		local ok, curve = pcall(BuildDispelCurve, false)
		if ok and curve then
			highlightCurve = curve
		end
	end
	return highlightCurve
end

-- 디스펠 타입 우선순위 (상수)
local dispelPriority = { Magic = 4, Curse = 3, Disease = 2, Poison = 1 }

local durationColorCache = {}
local BuildDurationColorInfo, GetDurationColorInfo -- Forward declaration

-- [DANDERSFRAMES 동일] 단일 아이콘 업데이트 헬퍼
local function ApplyAuraToIcon(icon, auraData, auraInstanceID, unit, auraType)
	-- 같은 오라가 같은 슬롯에 이미 표시 중이면 스킵 (DandersFrames 동일 로직)
	if icon.auraInstanceID == auraInstanceID and icon:IsShown() then
		return
	end

	-- 텍스처 (SetTexture는 C++에서 secret 처리)
	SafeSetTexture(icon, auraData.icon)

	-- 쿨다운 설정 (DandersFrames 패턴: DoesAuraHaveExpirationTime -> SafeSetCooldown)
	-- [FIX] 0초 깜빡임 방지: DandersFrames와 정확히 동일한 로직으로 수정
	icon.expirationTime = nil
	icon.auraDuration = nil
	icon.hasExpiration = false

	if C_UnitAuras.DoesAuraHaveExpirationTime then
		icon.hasExpiration = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
		icon.expirationTime = auraData.expirationTime
		icon.auraDuration = auraData.duration
	else
		if auraData.expirationTime and auraData.expirationTime > 0 then
			icon.expirationTime = auraData.expirationTime
			icon.hasExpiration = true
		end
		if auraData.duration and auraData.duration > 0 then
			icon.auraDuration = auraData.duration
		end
	end

	-- [DANDERSFRAMES 동일] Set cooldown (항상 호출, C++이 중복 처리)
	SafeSetCooldown(icon.cooldown, auraData.expirationTime, auraData.duration)
	


	-- Show/hide cooldown (swipe + native countdown text) based on whether aura expires
	-- Hiding the cooldown frame also hides the native countdown text (as its child)
	-- This is the primary mechanism for hiding duration text on permanent buffs
	-- [DANDERSFRAMES 동일] cooldown Show/Hide
	if icon.cooldown then
		if icon.cooldown.SetShownFromBoolean then
			icon.cooldown:SetShownFromBoolean(icon.hasExpiration, true, false)
		else
			icon.cooldown:Show()
		end
	end

	-- 텍스트 색상 초기화 (cooldown 텍스트 컬러 지정은 항상 적용, 무한일 땐 C++ 단에서 어차피 안 그림)
	if icon.nativeCooldownText then
		local frame = icon.unitFrame or icon:GetParent():GetParent()
		local frameType = frame.isRaidFrame and "raid" or "party"
		local info = GetDurationColorInfo(frameType, auraType)
		icon.nativeCooldownText:SetTextColor(info.rgb[1], info.rgb[2], info.rgb[3], 1)
	end

	-- [FIX] 스택 수 (DandersFrame 패턴: SetText가 C++ 레벨에서 secret 처리)
	icon.count:SetText("")
	if C_UnitAuras.GetAuraApplicationDisplayCount then
		local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
		if stackText then
			icon.count:SetText(stackText)
		end
	end

	-- [FIX] 디버프 테두리 색 (종류별 색상) — ColorCurve API (secret-safe)
	if auraType == "DEBUFF" then
		local db = GF:GetFrameDB(icon.unitFrame or icon:GetParent():GetParent())
		local debuffsDB = db and db.widgets and db.widgets.debuffs or {}
		local showTypeBorder = debuffsDB.showDispelTypeBorder ~= false

		if showTypeBorder and auraInstanceID and C_UnitAuras.GetAuraDispelTypeColor then
			local curve = GetDispelColorCurve()
			if curve then
				local borderColor = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
				if borderColor then
					icon.border:SetVertexColor(borderColor:GetRGBA())
				else
					icon.border:SetVertexColor(0, 0, 0, 0.8)
				end
			else
				icon.border:SetVertexColor(0, 0, 0, 0.8)
			end
		else
			icon.border:SetVertexColor(0, 0, 0, 0.8)
		end
	else
		icon.border:SetVertexColor(0, 0, 0, 0.8)
	end

	if icon.duration then
		icon.duration:Hide()
	end

	icon.auraInstanceID = auraInstanceID
	icon:Show()
end

function GF:UpdateAuraIconsDirect(frame, icons, cacheSet, unit, auraType)
	if not icons then return end

	local maxIcons = #icons
	local isDebuff = (auraType == "DEBUFF")

	-- [DANDERSFRAMES 동일] 캐시에서 순서 배열 가져오기
	local cache = BlizzardAuraCache[unit]
	local orderList = cache and (auraType == "BUFF" and cache.buffOrder or cache.debuffOrder)

	if orderList and #orderList > 0 then
		-- [DANDERSFRAMES 동일] Dedup: defensives에 이미 표시된 오라는 버프칸에서 제외
		local dedupSet = (not isDebuff) and cache.defensives or nil

		-- 레이드 시너지 버프 필터 준비
		local hideRaidBuffs = false
		local raidBuffIcons = nil
		if not isDebuff then
			local pf = ns.db and ns.db.party and ns.db.party.widgets
				and ns.db.party.widgets.buffs and ns.db.party.widgets.buffs.filter
			local rf = ns.db and ns.db.raid and ns.db.raid.widgets
				and ns.db.raid.widgets.buffs and ns.db.raid.widgets.buffs.filter
			local mrf = ns.db and ns.db.mythicRaid and ns.db.mythicRaid.widgets
				and ns.db.mythicRaid.widgets.buffs and ns.db.mythicRaid.widgets.buffs.filter
			hideRaidBuffs = (pf and pf.hideRaidBuffs) or (rf and rf.hideRaidBuffs) or (mrf and mrf.hideRaidBuffs) or false
			if hideRaidBuffs then
				raidBuffIcons = ns.GetRaidSynergyBuffIcons()
			end
		end

		-- HoT 화이트리스트 준비
		local db = GF:GetFrameDB(frame)
		local widgetKey = isDebuff and "debuffs" or "buffs"
		local widgetDB = db and db.widgets and db.widgets[widgetKey]
		local filter = widgetDB and widgetDB.filter

		-- [DANDERSFRAMES 동일] 순서 배열대로 아이콘 적용 (자체 정렬 없음)
		local displayedCount = 0
		for i = 1, #orderList do
			if displayedCount >= maxIcons then break end
			local auraInstanceID = orderList[i]
			if not auraInstanceID then break end

			-- [DANDERSFRAMES 동일] Dedup 체크
			if dedupSet and dedupSet[auraInstanceID] then
				-- 이미 DefensiveBar에서 표시 중 → 스킵
			else
				local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
				if auraData then
					local skipAura = false

					-- 레이드 시너지 버프 필터
					if not skipAura and hideRaidBuffs then
						local spellID = SafeVal(auraData.spellId)
						if spellID and ns.RaidSynergyBuffs[spellID] then
							skipAura = true
						elseif not spellID and auraData.icon then
							local iconTex = auraData.icon
							if not (issecretvalue and issecretvalue(iconTex)) and raidBuffIcons and raidBuffIcons[iconTex] then
								skipAura = true
							end
						end
					end

					-- HoT 화이트리스트
					if not skipAura and not isDebuff and filter and filter.useHotWhitelist then
						local hotCache = HotAuraCache[unit]
						if hotCache and not hotCache[auraInstanceID] then
							skipAura = true
						end
					end

					if not skipAura then
						displayedCount = displayedCount + 1
						ApplyAuraToIcon(icons[displayedCount], auraData, auraInstanceID, unit, auraType)
					end
				end
			end
		end

		-- [DANDERSFRAMES 동일] 남은 아이콘 완전 정리
		for i = displayedCount + 1, maxIcons do
			local icon = icons[i]
			icon.auraInstanceID = nil
			icon.expirationTime = nil
			icon.auraDuration = nil
			icon.hasExpiration = nil
			if icon.duration then icon.duration:Hide() end
			icon:Hide()
		end
	else
		-- 캐시 없음 → 전부 숨김
		for i = 1, maxIcons do
			local icon = icons[i]
			icon.auraInstanceID = nil
			icon.expirationTime = nil
			icon.auraDuration = nil
			icon.hasExpiration = nil
			if icon.duration then icon.duration:Hide() end
			icon:Hide()
		end
	end
end

-----------------------------------------------
-- [FIX] 지속시간 색상 타이머 (DandersFrame 패턴)
-- 텍스트 자체는 네이티브 CooldownFrame이 C++ 레벨에서 자동 갱신 (secret-safe)
-- 색상만 Lua에서 1초 간격 갱신:
--   fixed: DB rgb 고정 색상
--   gradient: EvaluateRemainingPercent (Linear curve, 비율 기반)
--   threshold: EvaluateRemainingDuration (Step curve, 초 기준 임계값)
-----------------------------------------------

-- durationColorCache = {} -- "party_BUFF" → { mode, curve, rgb, evaluateMethod } (Moved up)

BuildDurationColorInfo = function(frameType, auraType)
	local db = frameType == "raid" and GF:GetRaidDB() or GF:GetPartyDB()
	local widgets = db and db.widgets
	local auraDB = auraType == "DEBUFF" and (widgets and widgets.debuffs) or (widgets and widgets.buffs)
	if not auraDB then return { mode = "fixed", rgb = { 1, 1, 1 } } end

	local fontDB = auraDB.font and auraDB.font.duration
	local mode = fontDB and fontDB.colorMode or "fixed"
	local rgb = fontDB and fontDB.rgb or { 1, 1, 1 }
	local info = { mode = mode, rgb = rgb, curve = nil }

	if mode ~= "fixed" and C_CurveUtil and C_CurveUtil.CreateColorCurve then
		local dc = auraDB.durationColors
		if dc then
			if mode == "gradient" then
				local curve = C_CurveUtil.CreateColorCurve()
				curve:SetType(Enum.LuaCurveType.Linear)
				local exp = dc.expiring or { 1, 0, 0 }
				local low = dc.low or { 1, 0.5, 0 }
				local med = dc.medium or { 1, 1, 0 }
				local hi  = dc.high or { 1, 1, 1 }
				curve:AddPoint(0,    CreateColor(exp[1], exp[2], exp[3], 1))
				curve:AddPoint(0.10, CreateColor(low[1], low[2], low[3], 1))
				curve:AddPoint(0.25, CreateColor(med[1], med[2], med[3], 1))
				curve:AddPoint(0.50, CreateColor(hi[1],  hi[2],  hi[3],  1))
				info.curve = curve
				info.evaluateMethod = "percent"
				-- [TEST MODE] 수동 그라데이션 평가용 원시 데이터
				info.gradientPoints = {
					{ pct = 0,    rgb = exp },
					{ pct = 0.10, rgb = low },
					{ pct = 0.25, rgb = med },
					{ pct = 0.50, rgb = hi },
				}
			elseif mode == "threshold" then
				local thresholds = dc.thresholds
				if thresholds and #thresholds > 0 then
					local curve = C_CurveUtil.CreateColorCurve()
					curve:SetType(Enum.LuaCurveType.Step)
					-- 시간 오름차순 정렬
					local sorted = {}
					for i, t in ipairs(thresholds) do sorted[i] = t end
					table.sort(sorted, function(a, b) return a.time < b.time end)
					-- 첫 임계값 미만: 첫 색상
					local first = sorted[1].rgb
					curve:AddPoint(0, CreateColor(first[1], first[2], first[3], 1))
					-- 각 임계값 경계: 다음 색상
					for i = 2, #sorted do
						local c = sorted[i].rgb
						curve:AddPoint(sorted[i-1].time, CreateColor(c[1], c[2], c[3], 1))
					end
					-- 마지막 임계값 초과: 기본 색상 (fixed rgb)
					curve:AddPoint(sorted[#sorted].time, CreateColor(rgb[1], rgb[2], rgb[3], 1))
					info.curve = curve
					info.evaluateMethod = "duration"
					-- [TEST MODE] 수동 임계값 평가용 원시 데이터
					info.rawThresholds = sorted
				end
			end
		end
	end

	return info
end

GetDurationColorInfo = function(frameType, auraType)
	local key = frameType .. "_" .. auraType
	if not durationColorCache[key] then
		durationColorCache[key] = BuildDurationColorInfo(frameType, auraType)
	end
	return durationColorCache[key]
end

-- 설정 변경 시 캐시 리셋
function GF:ResetDurationColorCache()
	wipe(durationColorCache)
end

-- [TEST MODE] 쿨다운 프레임에서 남은 시간 계산 (테스트모드 더미 아이콘용)
local function GetIconRemainingTime(icon)
	if not icon.cooldown then return nil, nil end
	local start, duration
	if icon.cooldown.GetCooldownTimes then
		start, duration = icon.cooldown:GetCooldownTimes()
		if start and duration then
			-- GetCooldownTimes returns milliseconds (WoW 11.x+)
			start = start / 1000
			duration = duration / 1000
		end
	end
	if not start or not duration or duration <= 0 then return nil, nil end
	local remaining = (start + duration) - GetTime()
	if remaining < 0 then remaining = 0 end
	return remaining, duration
end

-- [TEST MODE] 임계값/그라데이션 수동 평가 (C_UnitAuras 없이)
local function EvalDurationColor(info, remaining, totalDuration)
	if info.mode == "threshold" and info.rawThresholds then
		-- Step 평가: 남은 시간이 어느 구간에 해당하는지 찾기
		local thresholds = info.rawThresholds
		for i = 1, #thresholds do
			if remaining < thresholds[i].time then
				local c = thresholds[i].rgb
				return c[1], c[2], c[3]
			end
		end
		-- 모든 임계값 초과: 기본 색상
		return info.rgb[1], info.rgb[2], info.rgb[3]
	elseif info.mode == "gradient" and info.gradientPoints then
		-- 남은 비율 기반 선형 보간
		local pct = totalDuration > 0 and (remaining / totalDuration) or 0
		if pct < 0 then pct = 0 end
		if pct > 1 then pct = 1 end
		local points = info.gradientPoints
		for i = 1, #points - 1 do
			if pct <= points[i + 1].pct then
				local span = points[i + 1].pct - points[i].pct
				local t = span > 0 and ((pct - points[i].pct) / span) or 0
				local c1, c2 = points[i].rgb, points[i + 1].rgb
				return c1[1] + t * (c2[1] - c1[1]),
				       c1[2] + t * (c2[2] - c1[2]),
				       c1[3] + t * (c2[3] - c1[3])
			end
		end
		local last = points[#points].rgb
		return last[1], last[2], last[3]
	end
	return info.rgb[1], info.rgb[2], info.rgb[3]
end

-- [PERF] colorTimerFrame: 그룹에 있을 때만 실행 (솔로 시 불필요한 OnUpdate 방지)
local colorTimerFrame = CreateFrame("Frame")
local colorTimerElapsed = 0
local colorTimerTestElapsed = 0  -- [FIX] 테스트모드 별도 카운터 (0.2초 갱신)
colorTimerFrame:Hide() -- 기본 비활성

colorTimerFrame:SetScript("OnUpdate", function(self, elapsed)
	colorTimerElapsed = colorTimerElapsed + elapsed
	colorTimerTestElapsed = colorTimerTestElapsed + elapsed

	-- [EXISTING] 실제 프레임 (GF.allFrames): C_UnitAuras API 사용 — 1초 간격
	local doRealFrames = colorTimerElapsed >= 1.0
	if doRealFrames then
		colorTimerElapsed = 0
	end

	-- [EXISTING] 실제 프레임: 1초 간격 (C_UnitAuras API 호출 비용 절감)
	if doRealFrames and GF.headersInitialized and C_UnitAuras and C_UnitAuras.GetAuraDuration then
		for _, frame in pairs(GF.allFrames) do
			if frame and frame:IsVisible() and frame.unit then
				local frameType = frame.isRaidFrame and "raid" or "party"

				for _iconPass = 1, 2 do -- [PERF] ipairs({...}) 임시 테이블 제거
				local iconList = _iconPass == 1 and frame.buffIcons or frame.debuffIcons
					if iconList then
						for _, icon in ipairs(iconList) do
							if icon:IsShown() and icon.auraInstanceID and icon.nativeCooldownText and icon.cooldown then
								local info = GetDurationColorInfo(frameType, icon.auraType or "BUFF")

								if info.mode ~= "fixed" and info.curve then
									local durationObj = C_UnitAuras.GetAuraDuration(frame.unit, icon.auraInstanceID)
									-- durationObj.EvaluateRemainingPercent 유무로 실제 지속시간이 있는지 검증 (DandersFrame 패턴)
									if durationObj and durationObj.EvaluateRemainingPercent then
										local result
										if info.evaluateMethod == "percent" then
											result = durationObj:EvaluateRemainingPercent(info.curve)
										elseif info.evaluateMethod == "duration" and durationObj.EvaluateRemainingDuration then
											result = durationObj:EvaluateRemainingDuration(info.curve)
										end
										
										if result and result.GetRGB then
											icon.nativeCooldownText:SetTextColor(result:GetRGB())
										elseif result and result.r then
											icon.nativeCooldownText:SetTextColor(result.r, result.g, result.b, 1)
										else
											icon.nativeCooldownText:SetTextColor(info.rgb[1], info.rgb[2], info.rgb[3], 1)
										end
									end
								end
							end
						end
					end
				end

				-- [FIX] 생존기 아이콘 텍스트를 매초마다 흰색으로 덮어쓰는 구조 삭제
				-- 고정 색상은 OnUpdate 타이머에서 변경할 필요가 없으며, 지속시간 0초 버프 시 깜빡임(Flashing) 버그의 원인이 됨

				-- [HOT-TRACKER] gradient는 프레임-레벨 (OnUpdate 불필요)
			end
		end
	end

	-- [TEST MODE] 테스트 프레임: 0.2초 간격 (API 호출 없이 쿨다운 수학만 사용)
	if colorTimerTestElapsed >= 0.2 then
		colorTimerTestElapsed = 0
		local TM = GF.TestMode
		if TM and TM.active then
			for _tmPass = 1, 2 do
				local tmFrames = _tmPass == 1 and TM.partyFrames or TM.raidFrames
				if tmFrames then
					for _, frame in ipairs(tmFrames) do
						if frame and frame:IsVisible() then
							local frameType = frame.isRaidFrame and "raid" or "party"

							for _iconPass = 1, 2 do
								local iconList = _iconPass == 1 and frame.buffIcons or frame.debuffIcons
								if iconList then
									for _, icon in ipairs(iconList) do
										if icon:IsShown() and icon.nativeCooldownText then
											local auraType = icon.auraType or (_iconPass == 1 and "BUFF" or "DEBUFF")
											local info = GetDurationColorInfo(frameType, auraType)

											if info.mode == "fixed" or (not info.rawThresholds and not info.gradientPoints) then
												icon.nativeCooldownText:SetTextColor(info.rgb[1], info.rgb[2], info.rgb[3], 1)
											else
												local remaining, totalDuration = GetIconRemainingTime(icon)
												if remaining then
													local r, g, b = EvalDurationColor(info, remaining, totalDuration)
													icon.nativeCooldownText:SetTextColor(r, g, b, 1)
												else
													icon.nativeCooldownText:SetTextColor(info.rgb[1], info.rgb[2], info.rgb[3], 1)
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
		end
	end
end)

-- [P1] 색상 타이머 필요 여부 판별: gradient/threshold 모드가 하나라도 있으면 true
local function NeedsColorTimer()
	-- 테스트 모드면 항상 필요
	if GF.TestMode and GF.TestMode.active then return true end

	-- 파티/레이드/미시크 모든 설정 확인
	local profiles = { ns.db and ns.db.party, ns.db and ns.db.raid, ns.db and ns.db.mythicRaid }
	for _, profile in ipairs(profiles) do
		if profile and profile.widgets then
			for _, widgetKey in ipairs({ "buffs", "debuffs" }) do
				local w = profile.widgets[widgetKey]
				local fontDB = w and w.font and w.font.duration
				if fontDB and fontDB.colorMode and fontDB.colorMode ~= "fixed" then
					return true
				end
			end
		end
	end
	return false
end

-- [PERF] colorTimerFrame 그룹 상태 감시: 그룹 진입 시 Show, 아니면 Hide
-- [P1] fixed 색상 모드에서는 colorTimerFrame 완전 비활성 (120+ API 호출/초 절감)
function GF:UpdateColorTimerState()
	if GF.headersInitialized and (IsInGroup() or IsInRaid()) and NeedsColorTimer() then
		colorTimerFrame:Show()
	elseif GF.TestMode and GF.TestMode.active then
		colorTimerFrame:Show()
	else
		colorTimerFrame:Hide()
		colorTimerElapsed = 0
	end
end

-----------------------------------------------
-- [FIX] Debuff Highlight (DandersFrames Dispel.lua 완전 복제)
-- StatusBar + ColorCurve + SetVertexColor(secret:GetRGBA())
-- Lua에서 secret value를 절대 읽거나 비교하지 않음
-----------------------------------------------

-- [DandersFrames 패턴] 통합 ColorCurve: 모든 dispel type (bleed/enrage 포함)
-- alpha가 0이면 해당 타입의 보더가 투명 → "감지"할 필요 없음
local unifiedHighlightCurve = nil

local function GetUnifiedHighlightCurve()
	if unifiedHighlightCurve then return unifiedHighlightCurve end
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end

	local ok, curve = pcall(function()
		local c = C_CurveUtil.CreateColorCurve()
		c:SetType(Enum.LuaCurveType.Step)

		local dc = C and C.DISPEL_COLORS or {}
		local magic   = dc.Magic   or { 0.20, 0.60, 1.00 }
		local curse   = dc.Curse   or { 0.60, 0.00, 1.00 }
		local disease = dc.Disease or { 0.60, 0.40, 0.00 }
		local poison  = dc.Poison  or { 0.00, 0.60, 0.00 }
		local bleed   = dc.Bleed   or { 1.00, 0.00, 0.00 }

		-- None(0) → alpha=0: 일반 디버프에는 투명 (보더 없음)
		c:AddPoint(0,    CreateColor(0, 0, 0, 0))
		-- 디스펠 가능 타입: alpha=1 (보더 표시)
		c:AddPoint(1,    CreateColor(magic[1],   magic[2],   magic[3],   1))  -- Magic
		c:AddPoint(2,    CreateColor(curse[1],   curse[2],   curse[3],   1))  -- Curse
		c:AddPoint(3,    CreateColor(disease[1], disease[2], disease[3], 1))  -- Disease
		c:AddPoint(4,    CreateColor(poison[1],  poison[2],  poison[3],  1))  -- Poison
		-- Enrage(9)/Bleed(11): alpha=1로 bleed 색상 표시
		c:AddPoint(9,    CreateColor(bleed[1], bleed[2], bleed[3], 1))  -- Enrage
		c:AddPoint(9.5,  CreateColor(0, 0, 0, 0))  -- Step overflow 차단
		c:AddPoint(11,   CreateColor(bleed[1], bleed[2], bleed[3], 1))  -- Bleed
		c:AddPoint(11.5, CreateColor(0, 0, 0, 0))  -- Step overflow 차단

		return c
	end)

	if ok and curve then
		unifiedHighlightCurve = curve
	end
	return unifiedHighlightCurve
end

-- [DandersFrames 패턴] ColorCurve 무효화 (설정 변경 시)
function GF:InvalidateDebuffHighlightCurve()
	unifiedHighlightCurve = nil
	-- 기존 커브도 무효화
	dispelColorCurve = nil
	highlightCurve = nil
end

function GF:UpdateDebuffHighlight(frame)
	if not frame or not frame.unit or not frame.debuffHighlight then return end

	-- DB에서 설정 읽기
	local db = self:GetFrameDB(frame)
	local dhDB = db and db.widgets and db.widgets.debuffHighlight
	if not dhDB or dhDB.enabled == false then
		self:HideDebuffHighlight(frame)
		return
	end

	local unit = frame.unit
	if not UnitExists(unit) then
		self:HideDebuffHighlight(frame)
		return
	end

	local showNonDispellable = dhDB.showNonDispellable

	-- ============================================================
	-- DandersFrames Dispel.lua:1370-1441 완전 복제
	-- ============================================================

	local dc = C and C.DISPEL_COLORS or {}
	local foundDispellable = false
	local lastDispellableID = nil
	local lastDispelType = nil  -- nil=표준 디스펠, 11=Bleed, 9=Enrage

	-- FAST PATH: playerDispellable 캐시 (O(1))
	-- 표준 디스펠 가능 디버프 (Magic/Curse/Disease/Poison 및 특성상 가능한 Bleed 등)
	local blizzCache = ns.AuraCache and ns.AuraCache.BlizzCache and ns.AuraCache.BlizzCache[unit]
	if blizzCache and blizzCache.playerDispellable then
		local auraInstanceID = next(blizzCache.playerDispellable)
		if auraInstanceID then
			foundDispellable = true
			lastDispellableID = auraInstanceID
		end
	end

	if foundDispellable and lastDispellableID then
		if not dispelColorCurve then dispelColorCurve = BuildDispelCurve(true) end
		if C_UnitAuras.GetAuraDispelTypeColor then
			local colorObj = C_UnitAuras.GetAuraDispelTypeColor(unit, lastDispellableID, dispelColorCurve)
			if colorObj then
				self:ShowDebuffHighlightColor(frame, colorObj, dhDB)
				return
			end
		end
		-- fallback for when colorObj fails (should not happen)
		local c = dc.Magic or { 0.20, 0.60, 1.00 }
		self:ShowDebuffHighlight(frame, c[1], c[2], c[3], dhDB)
	elseif showNonDispellable then
		-- SLOW PATH: Bleed/Enrage 디버프 탐지 (디스펠 불가 → playerDispellable에 없음)
		-- bleedDetectCurve: Bleed(11)/Enrage(9)만 alpha=1, 나머지 alpha=0
		local bCurve = GetBleedDetectCurve()
		if bCurve and C_UnitAuras.GetAuraDispelTypeColor then
			local foundBleed = false
			local bleedAuraID = nil
			-- ForEachAura로 HARMFUL 디버프 순회
			if C_UnitAuras.ForEachAura then
				C_UnitAuras.ForEachAura(unit, "HARMFUL", nil, function(auraData)
					if foundBleed then return false end
					local aid = auraData.auraInstanceID
					if aid and not (issecretvalue and issecretvalue(aid)) then
						local colorObj = C_UnitAuras.GetAuraDispelTypeColor(unit, aid, bCurve)
						if colorObj then
							local _, _, _, a = colorObj:GetRGBA()
							if a and a > 0 then
								foundBleed = true
								bleedAuraID = aid
								return false -- stop iteration
							end
						end
					end
					return false -- continue
				end, true) -- usePackedAuraData=true
			end
			if foundBleed and bleedAuraID then
				-- bleedDetectCurve는 감지 전용이지만 색상도 포함 → 직접 사용
				if not dispelColorCurve then dispelColorCurve = BuildDispelCurve(true) end
				local colorObj = C_UnitAuras.GetAuraDispelTypeColor(unit, bleedAuraID, dispelColorCurve)
				if colorObj then
					self:ShowDebuffHighlightColor(frame, colorObj, dhDB)
					return
				end
				-- fallback: 직접 bleed 색상 사용
				local bleedC = dc.Bleed or { 1.00, 0.00, 0.00 }
				self:ShowDebuffHighlight(frame, bleedC[1], bleedC[2], bleedC[3], dhDB)
				return
			end
		end
		-- Bleed/Enrage도 없으면 숨기기
		self:HideDebuffHighlight(frame)
	else
		-- 디스펠 가능 디버프 없음 + showNonDispellable 비활성 → 하이라이트 숨김
		self:HideDebuffHighlight(frame)
	end
end

-- [FIX] Color 객체를 직접 전달하는 하이라이트 (secret-safe)
-- [FIX] 기본 보더 숨김/복원 — ns 공유 함수 우선, 없으면 로컬 fallback
-- Update.lua와 Auras.lua에서 동일한 함수를 사용하여 상태 불일치 방지
local function UpdateBaseBorderVisibility(frame)
	-- ns.UpdateBorderVisibility가 있으면 공유 함수 사용 (Update.lua에서 등록)
	if ns.UpdateBorderVisibility then
		ns.UpdateBorderVisibility(frame)
		return
	end
	-- fallback: 인라인 구현
	if not frame then return end
	local activeBorder = nil
	if frame._threatBorderActive then
		activeBorder = "threat"
	elseif frame.debuffHighlightActive then
		activeBorder = "debuff"
	elseif frame._highlightBorderActive then
		activeBorder = "highlight"
	else
		activeBorder = "base"
	end
	if frame.threatBorder then
		if activeBorder == "threat" then frame.threatBorder:Show() else frame.threatBorder:Hide() end
	end
	if frame.debuffHighlight and frame.debuffHighlight.border then
		if activeBorder == "debuff" then frame.debuffHighlight.border:Show() else frame.debuffHighlight.border:Hide() end
	end
	if frame.highlightBorder then
		if activeBorder == "highlight" then frame.highlightBorder:Show() else frame.highlightBorder:Hide() end
	end
	if frame.border then
		if activeBorder == "base" then
			local GF = ns.GroupFrames
			if GF then
				local db = GF:GetFrameDB(frame)
				local borderDB = db and db.border
				if not borderDB or borderDB.enabled ~= false then
					frame.border:Show()
				end
			end
		else
			frame.border:Hide()
		end
	end
end

-- [FIX] 그라디언트 레이아웃 적용 헬퍼 (DandersFrames 패턴)
-- overlayMode="gradient" 일 때 4면 가장자리 텍스처의 위치/크기/블렌드 설정
local function ApplyGradientLayout(hl, dhDB, healthBar)
	if not hl or not healthBar then return end

	local style = (dhDB and dhDB.gradientStyle) or "EDGE"
	local size = (dhDB and dhDB.gradientSize) or 0.35
	local blendMode = (dhDB and dhDB.gradientBlendMode) or "ADD"

	-- 프레임 크기 기반 그라디언트 영역 계산
	local parentH = healthBar:GetHeight() or 36
	local parentW = healthBar:GetWidth() or 120

	-- 블렌드 모드 적용
	if hl.gradientTop then hl.gradientTop:SetBlendMode(blendMode) end
	if hl.gradientBottom then hl.gradientBottom:SetBlendMode(blendMode) end
	if hl.gradientLeft then hl.gradientLeft:SetBlendMode(blendMode) end
	if hl.gradientRight then hl.gradientRight:SetBlendMode(blendMode) end

	if style == "EDGE" then
		-- 4면 가장자리 그라디언트 (DandersFrames EDGE 패턴)
		local edgeH = parentH * size
		local edgeW = parentW * size

		if hl.gradientTop then
			hl.gradientTop:ClearAllPoints()
			hl.gradientTop:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
			hl.gradientTop:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
			hl.gradientTop:SetHeight(edgeH)
		end
		if hl.gradientBottom then
			hl.gradientBottom:ClearAllPoints()
			hl.gradientBottom:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
			hl.gradientBottom:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
			hl.gradientBottom:SetHeight(edgeH)
		end
		if hl.gradientLeft then
			hl.gradientLeft:ClearAllPoints()
			hl.gradientLeft:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
			hl.gradientLeft:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
			hl.gradientLeft:SetWidth(edgeW)
		end
		if hl.gradientRight then
			hl.gradientRight:ClearAllPoints()
			hl.gradientRight:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
			hl.gradientRight:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
			hl.gradientRight:SetWidth(edgeW)
		end
	elseif style == "TOP_BOTTOM" then
		-- 위아래 그라데이션 (좌우 없음)
		local h = parentH * size
		if hl.gradientTop then
			hl.gradientTop:ClearAllPoints()
			hl.gradientTop:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
			hl.gradientTop:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
			hl.gradientTop:SetHeight(h)
		end
		if hl.gradientBottom then
			hl.gradientBottom:ClearAllPoints()
			hl.gradientBottom:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
			hl.gradientBottom:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
			hl.gradientBottom:SetHeight(h)
		end
	elseif style == "TOP" then
		local h = parentH * size
		if hl.gradientTop then
			hl.gradientTop:ClearAllPoints()
			hl.gradientTop:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
			hl.gradientTop:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
			hl.gradientTop:SetHeight(h)
		end
	elseif style == "BOTTOM" then
		local h = parentH * size
		if hl.gradientBottom then
			hl.gradientBottom:ClearAllPoints()
			hl.gradientBottom:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
			hl.gradientBottom:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
			hl.gradientBottom:SetHeight(h)
		end
	else -- "FULL"
		if hl.gradientTop then
			hl.gradientTop:ClearAllPoints()
			hl.gradientTop:SetAllPoints(healthBar)
		end
	end
end

-- [FIX] 그라디언트 색상 적용 헬퍼
-- SetGradient API: 가장자리(불투명) → 중앙(투명) 방향 페이드
local function ApplyGradientColors(hl, r, g, b, a, dhDB)
	local alpha = (dhDB and dhDB.overlayAlpha) or 0.25
	local style = (dhDB and dhDB.gradientStyle) or "EDGE"
	-- [FIX] GradientV.tga 프리베이크 텍스처 사용 → SetGradient 불필요
	-- 텍스처 자체에 알파 그라데이션이 내장되어 있으므로 SetVertexColor만으로 페이드 효과 달성
	-- secret value에서도 안전 (SetVertexColor는 C++ 함수)

	if style == "EDGE" then
		if hl.gradientTop then
			hl.gradientTop:SetVertexColor(r, g, b, a)
			hl.gradientTop:SetAlpha(alpha)
			hl.gradientTop:Show()
		end
		if hl.gradientBottom then
			hl.gradientBottom:SetVertexColor(r, g, b, a)
			hl.gradientBottom:SetAlpha(alpha)
			hl.gradientBottom:Show()
		end
		if hl.gradientLeft then
			hl.gradientLeft:SetVertexColor(r, g, b, a)
			hl.gradientLeft:SetAlpha(alpha)
			hl.gradientLeft:Show()
		end
		if hl.gradientRight then
			hl.gradientRight:SetVertexColor(r, g, b, a)
			hl.gradientRight:SetAlpha(alpha)
			hl.gradientRight:Show()
		end
	elseif style == "TOP_BOTTOM" then
		if hl.gradientTop then
			hl.gradientTop:SetVertexColor(r, g, b, a)
			hl.gradientTop:SetAlpha(alpha)
			hl.gradientTop:Show()
		end
		if hl.gradientBottom then
			hl.gradientBottom:SetVertexColor(r, g, b, a)
			hl.gradientBottom:SetAlpha(alpha)
			hl.gradientBottom:Show()
		end
		if hl.gradientLeft then hl.gradientLeft:Hide() end
		if hl.gradientRight then hl.gradientRight:Hide() end
	elseif style == "TOP" then
		if hl.gradientTop then
			hl.gradientTop:SetVertexColor(r, g, b, a)
			hl.gradientTop:SetAlpha(alpha)
			hl.gradientTop:Show()
		end
		if hl.gradientBottom then hl.gradientBottom:Hide() end
		if hl.gradientLeft then hl.gradientLeft:Hide() end
		if hl.gradientRight then hl.gradientRight:Hide() end
	elseif style == "BOTTOM" then
		if hl.gradientBottom then
			hl.gradientBottom:SetVertexColor(r, g, b, a)
			hl.gradientBottom:SetAlpha(alpha)
			hl.gradientBottom:Show()
		end
		if hl.gradientTop then hl.gradientTop:Hide() end
		if hl.gradientLeft then hl.gradientLeft:Hide() end
		if hl.gradientRight then hl.gradientRight:Hide() end
	else -- "FULL"
		if hl.gradientTop then
			hl.gradientTop:SetVertexColor(r, g, b, a)
			hl.gradientTop:SetAlpha(alpha)
			hl.gradientTop:Show()
		end
		if hl.gradientBottom then hl.gradientBottom:Hide() end
		if hl.gradientLeft then hl.gradientLeft:Hide() end
		if hl.gradientRight then hl.gradientRight:Hide() end
	end
end

-- [FIX] 그라디언트 숨김 헬퍼
local function HideAllGradients(hl)
	if hl.gradientTop then hl.gradientTop:Hide() end
	if hl.gradientBottom then hl.gradientBottom:Hide() end
	if hl.gradientLeft then hl.gradientLeft:Hide() end
	if hl.gradientRight then hl.gradientRight:Hide() end
end

function GF:ShowDebuffHighlightColor(frame, color, dhDB)
	if not frame.debuffHighlight or not color then return end
	local oldState = frame.debuffHighlightActive
	frame.debuffHighlightActive = true -- [12.0.1] 우선순위 플래그
	if not oldState then self:ApplyHealthColor(frame) end

	local hl = frame.debuffHighlight
	local overlayAlpha = (dhDB and dhDB.overlayAlpha) or 0.25
	local borderSize = (dhDB and dhDB.borderSize) or 0
	local overlayMode = (dhDB and dhDB.overlayMode) or "gradient"

	-- Border: [DandersFrames 패턴] SetColorFromSecret로 secret color 직접 전달
	if hl.border and borderSize > 0 then
		-- [FIX] border size 캐싱: 동일 값이면 SetHeight/SetWidth 스킵
		if hl.border._cachedSize ~= borderSize then
			if hl.border.top then
				hl.border.top:SetHeight(borderSize)
				hl.border.bottom:SetHeight(borderSize)
				hl.border.left:SetWidth(borderSize)
				hl.border.right:SetWidth(borderSize)
			end
			hl.border._cachedSize = borderSize
		end
		-- [DandersFrames 패턴] secret color를 StatusBar 텍스처에 직접 전달
		-- C++이 alpha=0이면 투명 렌더링, alpha>0이면 해당 색상 렌더링
		if hl.border.SetColorFromSecret then
			hl.border:SetColorFromSecret(color)
		end
	end

	-- [FIX] Overlay 모드 분기: solid vs gradient
	-- GradientV.tga 프리베이크 텍스처 사용 → SetVertexColor만으로 그라데이션 적용
	-- SetVertexColor는 C++ 함수이므로 secret RGBA도 직접 처리 가능 (secret-safe)
	if overlayMode == "gradient" then
		if hl.overlay then hl.overlay:SetAlpha(0) end
		ApplyGradientLayout(hl, dhDB, frame.healthBar)
		ApplyGradientColors(hl, color:GetRGBA())
	else
		-- 기존 solid 모드
		HideAllGradients(hl)
		if hl.overlay then
			hl.overlay:SetVertexColor(color:GetRGBA())  -- secret RGBA 전달
			hl.overlay:SetAlpha(overlayAlpha)
		end
	end
	UpdateBaseBorderVisibility(frame)  -- [FIX] 기본 보더 숨김
end

function GF:ShowDebuffHighlight(frame, r, g, b, dhDB)
	if not frame.debuffHighlight then return end
	local oldState = frame.debuffHighlightActive
	frame.debuffHighlightActive = true -- [12.0.1] 우선순위 플래그
	if not oldState then self:ApplyHealthColor(frame) end

	local hl = frame.debuffHighlight
	local overlayAlpha = (dhDB and dhDB.overlayAlpha) or 0.25
	local borderSize = (dhDB and dhDB.borderSize) or 0
	local overlayMode = (dhDB and dhDB.overlayMode) or "gradient"

	-- Border 색상 + 두께 (borderSize=0이면 보더 스킵)
	if hl.border and borderSize > 0 then
		-- [FIX] border size 캐싱: 동일 값이면 SetHeight/SetWidth 스킵
		if hl.border._cachedSize ~= borderSize then
			if hl.border.top then
				hl.border.top:SetHeight(borderSize)
				hl.border.bottom:SetHeight(borderSize)
				hl.border.left:SetWidth(borderSize)
				hl.border.right:SetWidth(borderSize)
			end
			hl.border._cachedSize = borderSize
		end
		hl.border:SetColor(r, g, b, 1)
		-- Show/Hide는 UpdateBaseBorderVisibility가 우선순위 기반으로 관리
	end

	-- [FIX] Overlay 모드 분기: solid vs gradient (a=1 하드코딩)
	if overlayMode == "gradient" then
		if hl.overlay then hl.overlay:SetAlpha(0) end
		ApplyGradientLayout(hl, dhDB, frame.healthBar)
		ApplyGradientColors(hl, r, g, b, 1, dhDB)
	else
		HideAllGradients(hl)
		if hl.overlay then
			hl.overlay:SetVertexColor(r, g, b, 1)
			hl.overlay:SetAlpha(overlayAlpha)
		end
	end
	UpdateBaseBorderVisibility(frame) -- [FIX] 기본 보더 숨김
end

function GF:HideDebuffHighlight(frame)
	if not frame.debuffHighlight then return end
	local oldState = frame.debuffHighlightActive
	frame.debuffHighlightActive = false -- [12.0.1] 우선순위 플래그
	if oldState then self:ApplyHealthColor(frame) end

	local hl = frame.debuffHighlight
	if hl.border then
		hl.border:SetColor(0, 0, 0, 0)
		-- [FIX] 텍스처 크기도 리셋 → 디버프 borderSize(2px)가 남아
		-- hl.border가 Hide 실패/지연 시 두꺼운 보더가 보이는 문제 방지
		if hl.border.top then
			hl.border.top:SetHeight(0)
			hl.border.bottom:SetHeight(0)
			hl.border.left:SetWidth(0)
			hl.border.right:SetWidth(0)
		end
		hl.border._cachedSize = nil -- 캐시 무효화
		hl.border:Hide()
	end
	if hl.overlay then
		hl.overlay:SetAlpha(0)
	end
	-- [FIX] 그라디언트 텍스처도 숨김
	HideAllGradients(hl)

	-- [FIX] 기본 보더 크기 복원 (디버프 하이라이트가 2px로 설정한 후
	-- 기본 보더로 돌아갈 때 DB 값으로 확실히 리셋)
	if frame.border and frame.border.top then
		local db = GF:GetFrameDB(frame)
		local baseBorderSize = db and db.border and db.border.size or 1
		frame.border.top:SetHeight(baseBorderSize)
		frame.border.bottom:SetHeight(baseBorderSize)
		frame.border.left:SetWidth(baseBorderSize)
		frame.border.right:SetWidth(baseBorderSize)
	end

	UpdateBaseBorderVisibility(frame) -- [FIX] 기본 보더 복원
end

-----------------------------------------------
-- [FIX] Private Aura Anchors (DandersFrame 패턴)
-- C_UnitAuras.AddPrivateAuraAnchor는 전투 중에도 호출 가능
-----------------------------------------------

function GF:UpdatePrivateAuraAnchors(frame)
	if not frame or not frame.privateAuraAnchors then return end

	-- 기존 앵커 해제
	for _, anchor in ipairs(frame.privateAuraAnchors) do
		if anchor._auraAnchorID then
			C_UnitAuras.RemovePrivateAuraAnchor(anchor._auraAnchorID)
			anchor._auraAnchorID = nil
		end
	end

	-- unit이 없으면 종료
	if not frame.unit or not UnitExists(frame.unit) then return end

	-- [FIX] DB enabled 체크
	local db = GF:GetFrameDB(frame)
	local paDB = db and db.widgets and db.widgets.privateAuras
	if paDB and paDB.enabled == false then return end

	-- AddPrivateAuraAnchor API 확인
	if not C_UnitAuras.AddPrivateAuraAnchor then return end

	for i, anchor in ipairs(frame.privateAuraAnchors) do
		local w, h = anchor:GetSize()
		-- [FIX] DB에서 borderScale, showCountdownFrame, showCountdownNumbers 읽기
		local paBorderScale = paDB and paDB.borderScale or 0.6
		local paShowCooldown = paDB and paDB.showCountdownFrame ~= false
		local paShowNumbers = paDB and paDB.showCountdownNumbers ~= false
		local auraAnchorInfo = {
			unitToken = frame.unit,
			auraIndex = i,
			parent = anchor,
			showCountdownFrame = paShowCooldown,
			showCountdownNumbers = paShowNumbers,
			iconInfo = {
				iconWidth = w,
				iconHeight = h,
				iconAnchor = {
					point = "CENTER",
					relativeTo = anchor,
					relativePoint = "CENTER",
					offsetX = 0,
					offsetY = 0,
				},
				borderScale = paBorderScale,
			},
			-- [FIX] durationAnchor: 지속시간 텍스트 위치 커스터마이즈
			durationAnchor = {
				point = "CENTER",
				relativeTo = anchor,
				relativePoint = "CENTER",
				offsetX = 0,
				offsetY = 0,
			},
		}
		local ok, anchorID = pcall(C_UnitAuras.AddPrivateAuraAnchor, auraAnchorInfo)
		if ok and anchorID then
			anchor._auraAnchorID = anchorID

			-- [FIX] 포스트-생성 스키닝: 블리자드가 만든 자식 프레임들 재스타일
			-- ElvUI/BigWigs 패턴: GetChildren/GetRegions로 자식 요소 탐색 후 재스타일
			C_Timer.After(0, function()
				if not anchor:IsShown() then return end
				-- 자식 프레임 스킨 (쿨다운, 카운트다운 텍스트 등)
				local children = { anchor:GetChildren() }
				for _, child in ipairs(children) do
					-- 쿨다운 프레임의 FontString (카운트다운 텍스트) 크기 조절
					local regions = { child:GetRegions() }
					for _, region in ipairs(regions) do
						if region:GetObjectType() == "FontString" then
							local fontPath, _, fontFlags = region:GetFont()
							if fontPath then
								local fontSize = paDB and paDB.durationFontSize or 10
								region:SetFont(fontPath, fontSize, fontFlags or "OUTLINE")
							end
						elseif region:GetObjectType() == "Texture" then
							-- 아이콘 텍스처: texcoord 크롭 적용
							local texFile = region:GetTexture()
							if texFile and type(texFile) == "number" then
								region:SetTexCoord(0.08, 0.92, 0.08, 0.92)
							end
						end
					end
					-- 재귀: 쿨다운 안의 카운트다운 프레임
					local subChildren = { child:GetChildren() }
					for _, sub in ipairs(subChildren) do
						local subRegions = { sub:GetRegions() }
						for _, region in ipairs(subRegions) do
							if region:GetObjectType() == "FontString" then
								local fontPath, _, fontFlags = region:GetFont()
								if fontPath then
									local fontSize = paDB and paDB.durationFontSize or 10
									region:SetFont(fontPath, fontSize, fontFlags or "OUTLINE")
								end
							end
						end
					end
				end
				-- 앵커 자체의 regions (블리자드 border 텍스처 등)
				local anchorRegions = { anchor:GetRegions() }
				for _, region in ipairs(anchorRegions) do
					if region:GetObjectType() == "Texture" then
						local texFile = region:GetTexture()
						-- 보더 텍스처 (icon이 아닌 것)는 숨기거나 축소
						if texFile and type(texFile) ~= "number" then
							-- 보더 텍스처 인셋 조정 (1px 보더)
							region:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
							region:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 1, -1)
						end
					end
				end
			end)
		end
	end
end

-- 모든 프레임의 프라이빗 오라 앵커 갱신
function GF:RefreshAllPrivateAuras()
	for _, frame in pairs(self.allFrames) do
		if frame and frame:IsVisible() then
			self:UpdatePrivateAuraAnchors(frame)
		end
	end
end

-----------------------------------------------
-- [12.0.1] Defensive Icons — GroupFrames 구현
-- CenterDefensiveBuff API 100% 의존 (DandersFrames 패턴)
-- Blizzard CompactUnitFrame_UpdateAuras가 결정한 생존기만 표시
-- spellID 화이트리스트 제거 → 패치마다 유지보수 불필요
-----------------------------------------------

-- [12.0.1] pcall 기반 단일 아이콘 표시 헬퍼
-- module-level state로 closure 회피 (DandersFrames 패턴)
local DefIconState = {
	unit = nil,
	auraInstanceID = nil,
	auraData = nil,
	textureSet = false,
}

local function GetDefAuraData()
	DefIconState.auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(DefIconState.unit, DefIconState.auraInstanceID)
end

local function SetDefIconTexture()
	DefIconState.btn.Icon:SetTexture(DefIconState.auraData.icon)
	DefIconState.textureSet = true
end

local function SetDefIconCooldown()
	local cd = DefIconState.btn.Cooldown
	local ad = DefIconState.auraData
	if cd.SetCooldownFromExpirationTime and ad.expirationTime and ad.duration then
		cd:SetCooldownFromExpirationTime(ad.expirationTime, ad.duration)
	end
end

local function ShowDefensiveBtn(btn, unit, auraInstanceID, auraData, showDuration, showStack)
	-- [PERF] pcall 제거: SetTexture/SetCooldownFromExpirationTime은 C-API, secret-safe
	if auraData.icon then
		btn.Icon:SetTexture(auraData.icon)
	else
		btn.Icon:SetTexture(136243) -- fallback
	end

	-- 쿨다운 (secret-safe API: SetCooldownFromExpirationTime)
	local cd = btn.Cooldown
	if cd.SetCooldownFromExpirationTime and auraData.expirationTime and auraData.duration then
		cd:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
	end

	-- 쿨다운 스파이럴 표시 (DoesAuraHaveExpirationTime — secret-safe)
	if btn.Cooldown.SetShownFromBoolean and C_UnitAuras.DoesAuraHaveExpirationTime then
		local hasExp = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
		btn.Cooldown:SetShownFromBoolean(hasExp, true, false)
	else
		btn.Cooldown:Show()
	end

	-- [12.0.1] Duration 텍스트: 네이티브 쿨다운 카운트다운 사용 (일반 버프 아이콘과 동일)
	-- C++ 레벨에서 secret value 자동 처리 → 전투 중에도 정상 표시
	if btn.nativeCooldownText and showDuration then
		if C_UnitAuras.DoesAuraHaveExpirationTime then
			local hasExp = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
			if btn.nativeCooldownText.SetShownFromBoolean then
				btn.nativeCooldownText:SetShownFromBoolean(hasExp, true, false)
			else
				btn.nativeCooldownText:Show()
			end
		else
			btn.nativeCooldownText:Show()
		end
		-- [FIX] 초기 색상 리셋 (이전 아이콘의 색상 잔존 방지)
		btn.nativeCooldownText:SetTextColor(1, 1, 1, 1)
	elseif btn.nativeCooldownText then
		btn.nativeCooldownText:Hide()
	end

	-- auraInstanceID 저장 (타이머 색상 업데이트용)
	btn.auraInstanceID = auraInstanceID

	-- Stacks (secret-safe API: GetAuraApplicationDisplayCount)
	if btn.Count and showStack then
		if C_UnitAuras.GetAuraApplicationDisplayCount then
			local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
			if stackText then
				btn.Count:SetText(stackText)
				btn.Count:Show()
			else
				btn.Count:Hide()
			end
		else
			btn.Count:Hide()
		end
	elseif btn.Count then
		btn.Count:Hide()
	end

	btn:Show()
end

function GF:UpdateDefensiveIcon(frame)
	if not frame or not frame.defensiveIcons then return end
	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		for _, btn in ipairs(frame.defensiveIcons) do
			btn:Hide()
		end
		return
	end

	local db = self:GetFrameDB(frame)
	local defDB = db and db.widgets and db.widgets.defensives
	if not defDB or not defDB.enabled then
		for _, btn in ipairs(frame.defensiveIcons) do
			btn:Hide()
		end
		return
	end

	local maxIcons = defDB.maxIcons or 4
	local showDuration = defDB.showDuration ~= false
	local showStack = defDB.showStack

	local shown = 0

	-- [12.0.1] CenterDefensiveBuff API 100% 의존 (DandersFrames 패턴)
	-- Blizzard가 CompactUnitFrame_UpdateAuras에서 결정한 생존기만 표시
	-- spellID 화이트리스트 불필요 → 패치마다 유지보수 제거
	local cache = BlizzardAuraCache[unit]
	if cache and cache.defensives then
		for auraInstanceID in pairs(cache.defensives) do
			if shown >= maxIcons then break end

			-- [PERF] pcall 제거: GetAuraDataByAuraInstanceID는 C-API, nil 반환 시 안전
			local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)

			if auraData then
				shown = shown + 1
				local btn = frame.defensiveIcons[shown]
				if btn then
					ShowDefensiveBtn(btn, unit, auraInstanceID, auraData, showDuration, showStack)
				end
			end
		end
	end

	-- 나머지 숨기기
	for i = shown + 1, #frame.defensiveIcons do
		local btn = frame.defensiveIcons[i]
		if btn then
			btn:Hide()
		end
	end
end

-- 모든 프레임의 생존기 아이콘 갱신
function GF:RefreshAllDefensives()
	for _, frame in pairs(self.allFrames) do
		if frame and frame:IsVisible() then
			self:UpdateDefensiveIcon(frame)
		end
	end
end

-- =============================================
-- [HOT-TRACKER] HoT 트래커 시스템
-- HARF 필터 패턴 기반 + 델타 업데이트 + 5가지 표시 유형
-- =============================================

local HotAuraCache = {}      -- unit → { [auraInstanceID] = hotName, ... }
local PlayerSpecKey = nil     -- "RestorationDruid" 등
local HotSpecData = ns.HotSpecData
local HotSpecMap = ns.HotSpecMap

GF.HotAuraCache = HotAuraCache

-- [PERF] UpdateHotIndicatorsForFrame용 재사용 테이블 (GC 방지)
local _activeHots = {}
local _seenHots = {}

-----------------------------------------------
-- 플레이어 전문화 감지
-----------------------------------------------

local function UpdatePlayerSpec()
	local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
	if specIndex then
		local specID = GetSpecializationInfo(specIndex)
		PlayerSpecKey = specID and HotSpecMap[specID] or nil
	else
		PlayerSpecKey = nil
	end
end

-- [HOT-TRACKER] Options.lua에서 접근할 수 있도록 getter 노출
function GF:GetPlayerSpecKey()
	return PlayerSpecKey
end

-----------------------------------------------
-- HoT 식별: 4-filter + points 패턴 매칭 (Secret-V5 안정성 강화)
-- [12.1] 개선:
--   1. issecretvalue() 직접 사용 (SafeVal 대신) → secret 여부 정확 감지
--   2. secret 필터 → 퍼지 매칭 (points + 알려진 필터만 비교)
--   3. BlizzCache.myBuffs 사전 필터 (내 버프 아닌 오라 제외)
-----------------------------------------------

local function MatchHotAura(unit, aura)
	if not PlayerSpecKey or not HotSpecData then return nil end
	local specData = HotSpecData[PlayerSpecKey]
	if not specData or not specData.auras then return nil end

	local aid = aura.auraInstanceID

	-- 4-filter 호출
	local filtRaid = C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aid, "PLAYER|HELPFUL|RAID")
	local filtRic  = C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aid, "PLAYER|HELPFUL|RAID_IN_COMBAT")
	local filtExt  = C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aid, "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE")
	local filtDisp = C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aid, "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE")

	-- points 개수 (secret table 방어)
	local pointCount = 0
	if aura.points then
		local ok, len = pcall(function() return #aura.points end)
		if ok and len then pointCount = len end
	end

	-- [12.1] issecretvalue 직접 사용: SafeVal 대신 정확한 secret 감지
	local raidSecret = issecretvalue and issecretvalue(filtRaid)
	local ricSecret  = issecretvalue and issecretvalue(filtRic)
	local extSecret  = issecretvalue and issecretvalue(filtExt)
	local dispSecret = issecretvalue and issecretvalue(filtDisp)

	local hasSecret = raidSecret or ricSecret or extSecret or dispSecret

	-- 필터 결과 변환 (secret이 아닌 것만)
	local passesRaid = raidSecret and nil or (not filtRaid)
	local passesRic  = ricSecret  and nil or (not filtRic)
	local passesExt  = extSecret  and nil or (not filtExt)
	local passesDisp = dispSecret and nil or (not filtDisp)

	if not hasSecret then
		-- === EXACT MATCH: 모든 필터 알려짐 → 정확 매칭 ===
		for hotName, hotData in pairs(specData.auras) do
			if hotData.points == pointCount
			   and hotData.raid == passesRaid
			   and hotData.ric == passesRic
			   and hotData.ext == passesExt
			   and hotData.disp == passesDisp then
				return hotName
			end
		end
		return nil
	end

	-- === FUZZY MATCH: secret 필터 존재 → points + 알려진 필터만 비교 ===
	-- secret 필터는 와일드카드 처리 (어떤 값이든 매칭)
	local bestMatch = nil
	local bestScore = 0

	for hotName, hotData in pairs(specData.auras) do
		if hotData.points == pointCount then
			local score = 1 -- points 매칭 = 1점
			local mismatch = false

			-- 알려진 필터만 비교
			if passesRaid ~= nil then
				if hotData.raid == passesRaid then score = score + 1
				else mismatch = true end
			end
			if passesRic ~= nil then
				if hotData.ric == passesRic then score = score + 1
				else mismatch = true end
			end
			if passesExt ~= nil then
				if hotData.ext == passesExt then score = score + 1
				else mismatch = true end
			end
			if passesDisp ~= nil then
				if hotData.disp == passesDisp then score = score + 1
				else mismatch = true end
			end

			if not mismatch and score > bestScore then
				bestScore = score
				bestMatch = hotName
			end
		end
	end

	return bestMatch
end

-----------------------------------------------
-- 유닛이 추적 대상인지 확인
-----------------------------------------------

local function IsTrackedUnit(unit)
	if not unit then return false end
	local prefix = unit:match("^(%a+)")
	return prefix == "party" or prefix == "raid" or unit == "player"
end

-----------------------------------------------
-- 델타 업데이트 처리 (안정성 강화 V2)
-- [12.1] 개선:
--   1. isFullUpdate 시 캐시 전체 wipe 대신 소프트 리빌드
--      (기존 매치 보존 → 깜빡임 방지)
--   2. BlizzCache.myBuffs 사전 필터: Blizzard가 인정한 내 버프만 시도
--   3. 변동 없으면 UI 갱신 스킵 (불필요 Show/Hide 반복 방지)
-----------------------------------------------

function GF:ProcessHotDelta(unit, updateInfo)
	if not PlayerSpecKey then return end

	local needsUIUpdate = false

	if updateInfo and updateInfo.isFullUpdate then
		-- [12.1] 소프트 리빌드: 전체 wipe 대신 기존 매치 보존
		-- 기존 캐시 백업 → 재스캔 → 결과가 같으면 UI 갱신 스킵
		local oldCache = HotAuraCache[unit]
		local newCache = {}

		local ok, allAuras = pcall(C_UnitAuras.GetUnitAuras, unit, "PLAYER|HELPFUL")
		if ok and allAuras then
			-- BlizzCache.myBuffs 사전 필터
			local myBuffs = ns.AuraCache and ns.AuraCache:GetMyBuffs(unit)

			for _, aura in ipairs(allAuras) do
				local auraInstanceID = aura.auraInstanceID
				if auraInstanceID then
					-- [FIX] secret auraInstanceID 방어: secret key로 테이블 조회 시 항상 nil
					-- → myBuffs 필터 + previousMatch 보존 모두 실패 → HoT 전부 탈락
					local isSecretID = issecretvalue and issecretvalue(auraInstanceID)

					-- [12.1] BlizzCache 사전 필터: myBuffs에 없으면 스킵
					-- (BlizzCache 미사용 시 또는 secret ID일 때 필터 없이 진행)
					local passesBlizzFilter = true
					if myBuffs and not isSecretID then
						passesBlizzFilter = myBuffs[auraInstanceID]
					end

					if passesBlizzFilter then
						-- 기존 매치가 있으면 재사용 (비전투→전투 전환 시 보존)
						local previousMatch = not isSecretID and oldCache and oldCache[auraInstanceID]
						local hotName = MatchHotAura(unit, aura)

						if hotName then
							if not isSecretID then
								newCache[auraInstanceID] = hotName
							end
						elseif previousMatch then
							-- [12.1] MatchHotAura 실패 (secret) + 기존 매치 존재
							-- → 기존 매치 보존 (깜빡임 방지)
							newCache[auraInstanceID] = previousMatch
						end
					end
				end
			end
		end

		-- [FIX] secret auraInstanceID가 포함된 경우:
		-- secret key는 newCache에 삽입되지 않으므로 oldCache와 비교 시 "삭제"로 감지됨
		-- → 실제 변동이 아닌 false positive UI 갱신 방지
		-- oldCache의 모든 엔트리가 newCache에 존재하면 (non-secret 기준) 변동 없음
		if oldCache then
			-- 기존 vs 신규 비교
			for id, name in pairs(newCache) do
				if not oldCache[id] or oldCache[id] ~= name then
					needsUIUpdate = true
					break
				end
			end
			if not needsUIUpdate then
				for id in pairs(oldCache) do
					if not newCache[id] then
						-- [FIX] oldCache에만 있는 엔트리: MatchHotAura가 성공적으로 재매칭했을 수도 있음
						-- (secret ID 전환 → 새 ID로 들어감)
						-- 실제 삭제인지 확인: 해당 aura가 아직 존재하는지 체크
						local stillExists = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id)
						if not stillExists then
							needsUIUpdate = true
							break
						else
							-- 오라는 존재하지만 secret ID로 재스캔되어 newCache에 들어가지 못함
							-- → 기존 매치 보존
							newCache[id] = oldCache[id]
						end
					end
				end
			end
		else
			-- 기존 캐시 없음 → 갱신 필요
			needsUIUpdate = (next(newCache) ~= nil)
		end

		HotAuraCache[unit] = newCache
	else
		-- 캐시 초기화 (첫 호출 시)
		if not HotAuraCache[unit] then
			needsUIUpdate = true
			HotAuraCache[unit] = {}
			local ok, allAuras = pcall(C_UnitAuras.GetUnitAuras, unit, "PLAYER|HELPFUL")
			if ok and allAuras then
				local myBuffs = ns.AuraCache and ns.AuraCache:GetMyBuffs(unit)
				for _, aura in ipairs(allAuras) do
					local auraInstanceID = aura.auraInstanceID
					if auraInstanceID then
						local passesBlizzFilter = true
						if myBuffs then passesBlizzFilter = myBuffs[auraInstanceID] end
						if passesBlizzFilter then
							local hotName = MatchHotAura(unit, aura)
							if hotName then
								HotAuraCache[unit][auraInstanceID] = hotName
							end
						end
					end
				end
			end
		end

		if not updateInfo then updateInfo = {} end

		-- 제거된 오라 (O(1) 삭제)
		if updateInfo.removedAuraInstanceIDs then
			for _, auraId in ipairs(updateInfo.removedAuraInstanceIDs) do
				if HotAuraCache[unit][auraId] then
					HotAuraCache[unit][auraId] = nil
					needsUIUpdate = true
				end
			end
		end

		-- 추가된 오라
		if updateInfo.addedAuras then
			local myBuffs = ns.AuraCache and ns.AuraCache:GetMyBuffs(unit)
			for _, aura in ipairs(updateInfo.addedAuras) do
				local auraInstanceID = aura.auraInstanceID
				if auraInstanceID and not HotAuraCache[unit][auraInstanceID] then
					local passesBlizzFilter = true
					if myBuffs then passesBlizzFilter = myBuffs[auraInstanceID] end
					if passesBlizzFilter then
						local hotName = MatchHotAura(unit, aura)
						if hotName then
							HotAuraCache[unit][auraInstanceID] = hotName
							needsUIUpdate = true
						end
					end
				end
			end
		end
	end

	-- [12.1] 캐시 변동이 없으면 UI 갱신 건너뛰기 (깜빡임 방지)
	if needsUIUpdate then
		self:UpdateHotIndicatorsForUnit(unit)
	end
end

-----------------------------------------------
-- 캐시 리셋
-----------------------------------------------

function GF:ResetHotCache(unit)
	if unit then
		HotAuraCache[unit] = nil
	else
		wipe(HotAuraCache)
	end
end

-- [PERF] 벌크 리빌드: wipe 후 모든 유닛을 한번에 스캔하여 lazy 풀스캔 폭풍 방지
function GF:RebuildHotCache()
	wipe(HotAuraCache)
	if not PlayerSpecKey then
		self:RefreshAllHotIndicators()
		return
	end
	-- 모든 보이는 프레임의 유닛을 한번에 스캔
	for _, frame in pairs(self.allFrames) do
		if frame and frame:IsVisible() and frame.unit then
			local unit = frame.unit
			HotAuraCache[unit] = {}
			local ok, allAuras = pcall(C_UnitAuras.GetUnitAuras, unit, "PLAYER|HELPFUL")
			if ok and allAuras then
				local myBuffs = ns.AuraCache and ns.AuraCache:GetMyBuffs(unit)
				for _, aura in ipairs(allAuras) do
					local auraInstanceID = aura.auraInstanceID
					if auraInstanceID then
						local passesBlizzFilter = true
						if myBuffs then passesBlizzFilter = myBuffs[auraInstanceID] end
						if passesBlizzFilter then
							local hotName = MatchHotAura(unit, aura)
							if hotName then
								HotAuraCache[unit][auraInstanceID] = hotName
							end
						end
					end
				end
			end
		end
	end
	self:RefreshAllHotIndicators()
end

-----------------------------------------------
-- outline 테두리 설정 헬퍼
-----------------------------------------------

local function SetHotOutlineBorder(outline, size, color)
	if not outline then return end
	local r, g, b, a = color[1] or 0.3, color[2] or 0.85, color[3] or 0.45, color[4] or 1
	outline.top:SetHeight(size)
	outline.top:SetColorTexture(r, g, b, a)
	outline.bottom:SetHeight(size)
	outline.bottom:SetColorTexture(r, g, b, a)
	outline.left:SetWidth(size)
	outline.left:SetColorTexture(r, g, b, a)
	outline.right:SetWidth(size)
	outline.right:SetColorTexture(r, g, b, a)
end

-----------------------------------------------
-- UpdateHotIndicators — 5가지 표시 유형 갱신
-----------------------------------------------

function GF:UpdateHotIndicatorsForUnit(unit)
	-- GetFrameForUnit (Core.lua)이 있으면 최적 경로, 없으면 allFrames 순회
	local frame = self.GetFrameForUnit and self:GetFrameForUnit(unit)
	if frame and frame.hotIndicators then
		self:UpdateHotIndicatorsForFrame(frame)
		return
	end
	-- fallback: allFrames 순회
	if not self.allFrames then return end
	for _, f in pairs(self.allFrames) do
		if f and f.unit == unit and f.hotIndicators then
			self:UpdateHotIndicatorsForFrame(f)
			return
		end
	end
end

function GF:UpdateHotIndicatorsForFrame(frame)
	if not frame or not frame.hotIndicators then return end

	local unit = frame.unit
	if not unit then
		for _, ind in ipairs(frame.hotIndicators) do ind:Hide() end
		if frame.hotOutline then frame.hotOutline:Hide() end
		if frame.hotGradient then frame.hotGradient:Hide() end
		return
	end

	local db = self:GetFrameDB(frame)
	local hotDB = db and db.widgets and db.widgets.hotTracker
	-- [HOT-TRACKER] 힐러 자동 활성화: PlayerSpecKey가 있으면 enabled 무시하고 활성화
	if not hotDB or (not hotDB.enabled and not PlayerSpecKey) then
		for _, ind in ipairs(frame.hotIndicators) do ind:Hide() end
		if frame.hotOutline then frame.hotOutline:Hide() end
		if frame.hotGradient then frame.hotGradient:Hide() end
		if frame.hotHealthColorActive then
			frame.hotHealthColorActive = false
			frame.hotHealthColorData = nil
			self:ApplyHealthColor(frame) -- [FIX] 원래 색상 복원
		end
		return
	end

	local cache = HotAuraCache[unit]
	local auraSettings = hotDB.auraSettings or {}
	local defaults = ns.AURA_DISPLAY_DEFAULTS
	-- [PERF] 활성 HoT 수집: 모듈 레벨 재사용 테이블 (GC 방지)
	wipe(_seenHots)
	local activeCount = 0
	if cache and PlayerSpecKey then
		for instanceID, hotName in pairs(cache) do
			if not _seenHots[hotName] then
				_seenHots[hotName] = true
				local auraKey = PlayerSpecKey .. "." .. hotName
				local auraCfg = auraSettings[auraKey] or defaults
				if auraCfg.enabled ~= false then
					activeCount = activeCount + 1
					local entry = _activeHots[activeCount]
					if not entry then
						entry = {}
						_activeHots[activeCount] = entry
					end
					entry.name = hotName
					entry.instanceID = instanceID
					entry.cfg = auraCfg
				end
			end
		end
	end
	-- 이전 호출의 잔여 엔트리 정리
	for i = activeCount + 1, #_activeHots do
		_activeHots[i] = nil
	end
	-- [FIX] hotName으로 정렬: pairs() 순서가 비결정적이므로
	-- 매 호출마다 인디케이터 슬롯 할당이 바뀌어 깜빡임이 발생하는 문제 방지
	if activeCount > 1 then
		table.sort(_activeHots, function(a, b) return a.name < b.name end)
	end

	-- 프레임-레벨 플래그 (per-aura 중 하나라도 활성이면 적용)
	local outlineCfg, healthColorCfg, gradientCfg = nil, nil, nil

	-- === 인디케이터-레벨 표시 (per-aura 설정) ===
	for i = 1, #frame.hotIndicators do
		local ind = frame.hotIndicators[i]
		if not ind then break end

		local hotInfo = _activeHots[i]
		if hotInfo then
			ind.hotName = hotInfo.name
			ind.auraInstanceID = hotInfo.instanceID
			local ac = hotInfo.cfg -- per-aura config

			-- [12.0.1] 텍스트 전용 모드: 아이콘 숨기고 카운트다운 텍스트만 표시
			ind.texture:Hide()
			if ind.border then ind.border:Hide() end

			-- 바 (per-aura 설정에 따라)
			if ind.durationBar then
				if ac.bar and ac.bar.enabled then
					local okDur2, dur2 = pcall(C_UnitAuras.GetAuraDuration, unit, hotInfo.instanceID)
					if okDur2 and dur2 then
						local barC = ac.bar.color or defaults.bar.color
						ind.durationBar:SetStatusBarColor(barC[1], barC[2], barC[3], barC[4] or 0.8)
						ind.durationBar:SetHeight(ac.bar.thickness or 3)
						ind.durationBar:Show()
					else
						ind.durationBar:Hide()
					end
				else
					ind.durationBar:Hide()
				end
			end

			-- [12.0.1] 쿨다운 텍스트 제거됨 — 쿨다운 프레임 숨김
			ind.cooldown:Hide()

			-- 프레임-레벨 플래그 수집 (첫 번째 활성된 것 사용)
			if not outlineCfg and ac.outline and ac.outline.enabled then
				outlineCfg = ac.outline
			end
			if not healthColorCfg and ac.healthColor and ac.healthColor.enabled then
				healthColorCfg = ac.healthColor
			end
			if not gradientCfg and ac.gradient and ac.gradient.enabled then
				gradientCfg = ac.gradient
			end

			ind:Show()
		else
			-- 비활성 슬롯
			ind:Hide()
			ind.hotName = nil
			ind.auraInstanceID = nil
			if ind.durationBar then ind.durationBar:Hide() end
		end
	end

	-- === 프레임-레벨: OUTLINE (per-aura 중 하나라도 활성이면) ===
	if outlineCfg and frame.hotOutline then
		local oc = outlineCfg.color or defaults.outline.color
		local os = outlineCfg.size or 2
		SetHotOutlineBorder(frame.hotOutline, os, oc)
		frame.hotOutline:Show()
	elseif frame.hotOutline then
		frame.hotOutline:Hide()
	end

	-- === 프레임-레벨: GRADIENT (per-aura 중 하나라도 활성이면, 지정색→투명) ===
	if gradientCfg and frame.hotGradient then
		local gc = gradientCfg.color or defaults.gradient.color or { 0.3, 0.85, 0.45 }
		local ga = gradientCfg.alpha or defaults.gradient.alpha or 0.4
		frame.hotGradient:SetGradient("VERTICAL",
			CreateColor(gc[1], gc[2], gc[3], ga),
			CreateColor(gc[1], gc[2], gc[3], 0)
		)
		frame.hotGradient:Show()
	elseif frame.hotGradient then
		frame.hotGradient:Hide()
	end

	-- === 프레임-레벨: HEALTHCOLOR (per-aura 중 하나라도 활성이면) ===
	if healthColorCfg and frame.healthBar then
		local hc = healthColorCfg.color or defaults.healthColor.color
		frame.hotHealthColorActive = true
		frame.hotHealthColorData = hc
		self:ApplyHealthColor(frame)
	else
		if frame.hotHealthColorActive then
			frame.hotHealthColorActive = false
			frame.hotHealthColorData = nil
			self:ApplyHealthColor(frame) -- [FIX] 원래 색상 복원
		end
	end
end

-- 모든 프레임의 HoT 인디케이터 갱신
function GF:RefreshAllHotIndicators()
	if not self.allFrames then return end
	for _, frame in pairs(self.allFrames) do
		if frame and frame:IsVisible() then
			self:UpdateHotIndicatorsForFrame(frame)
		end
	end
end

-----------------------------------------------
-- [HOT-TRACKER] 이벤트 프레임 (Phase 6)
-- [PERF] 이벤트 등록은 StartHotTracker() 호출 시에만 수행
-----------------------------------------------

local hotEventFrame = CreateFrame("Frame")
hotEventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "UNIT_AURA" then
		local unit, updateInfo = ...
		if PlayerSpecKey and IsTrackedUnit(unit) and GF.headersInitialized then
			GF:ProcessHotDelta(unit, updateInfo)
		end
	elseif event == "PLAYER_SPECIALIZATION_CHANGED"
		or event == "PLAYER_ENTERING_WORLD" then
		UpdatePlayerSpec()
		GF:ResetHotCache()
		-- 짧은 지연 후 전체 갱신 (프레임 초기화 대기)
		C_Timer.After(0.5, function()
			if GF.headersInitialized then
				GF:RefreshAllHotIndicators()
			end
		end)
	elseif event == "GROUP_ROSTER_UPDATE" then
		GF:ResetHotCache()
		if GF.headersInitialized then
			GF:RefreshAllHotIndicators()
		end
	end
end)

-- [PERF] Initialize 시점에 호출 (비활성 시 CPU 0)
function GF:StartHotTracker()
	if hotEventFrame._registered then return end
	hotEventFrame._registered = true
	hotEventFrame:RegisterEvent("UNIT_AURA")
	hotEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	hotEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	hotEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
end
