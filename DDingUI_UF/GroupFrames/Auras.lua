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
local C = ns.Constants       -- [FIX] ns.C → ns.Constants

-----------------------------------------------
-- BlizzardAuraCache
-----------------------------------------------

local BlizzardAuraCache = {}  -- unit → { buffs = {id=true}, debuffs = {id=true}, defensives = {id=true} }
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

local dirtyProcessor -- forward declaration (MarkAuraDirty에서 참조)
local isBatchScan = false -- [PERF] ScanBlizzardFrames 배치 모드 플래그

-- [FIX] DandersFrames 완전 복제: hook → 즉시 캡처 → 즉시 렌더링
-- 단, ScanBlizzardFrames 배치 스캔 중에는 즉시 렌더링 건너뜀 (Phase B에서 일괄 처리)
local function MarkAuraDirty(blizzFrame)
	if not blizzFrame then return end
	local unit = blizzFrame.unit
	if not unit then return end

	-- [PERF] 그룹 유닛만 (네임플레이트/보스/아레나 제외 → 최대 90% 호출 차단)
	if not IsGroupUnit(unit) then return end

	dirtyAuraFrames[unit] = blizzFrame
	hasDirtyAuras = true

	-- [FIX] CenterDefensiveBuff 즉시 캡처 (DandersFrames CaptureAurasFromBlizzardFrame 패턴)
	if not BlizzardAuraCache[unit] then
		BlizzardAuraCache[unit] = { buffs = {}, debuffs = {}, defensives = {} }
	end
	if not BlizzardAuraCache[unit].defensives then
		BlizzardAuraCache[unit].defensives = {}
	else
		wipe(BlizzardAuraCache[unit].defensives)
	end
	if blizzFrame.CenterDefensiveBuff then
		local defFrame = blizzFrame.CenterDefensiveBuff
		if defFrame.IsShown and defFrame:IsShown() and defFrame.auraInstanceID then
			BlizzardAuraCache[unit].defensives[defFrame.auraInstanceID] = true
		end
	end

	-- [FIX] DandersFrames 패턴: 즉시 프레임 조회 → 즉시 UpdateDefensiveIcon 호출
	-- [PERF] 배치 스캔 중에는 건너뜀 (85프레임 × 즉시렌더링 = script ran too long 방지)
	if not isBatchScan then
		local ourFrame = GF.unitFrameMap[unit]
		if ourFrame and ourFrame:IsVisible() and GF.UpdateDefensiveIcon then
			GF:UpdateDefensiveIcon(ourFrame)
		end
	end

	dirtyProcessor:Show() -- 나머지 aura(버프/디버프) 처리는 다음 OnUpdate에서 배치
end

-- [REFACTOR] QueueAuraUpdate: 프레임 렌더링을 큐에 추가
-- GF:UpdateAuras 직접 호출 대신 이것을 사용하면 1프레임 1회 보장
function GF:QueueAuraUpdate(frame)
	if not frame then return end
	dirtyRenderFrames[frame] = true
	hasDirtyRender = true
	dirtyProcessor:Show()
end

-- [PERF] 배치 처리: 동일 유닛 3x hook → 1x 처리
local function ProcessDirtyAuras()
	-- Phase A: BlizzardAuraCache 캡처 (hook으로 인한 더티)
	if hasDirtyAuras then
		hasDirtyAuras = false

		for unit, blizzFrame in pairs(dirtyAuraFrames) do
			-- 캐시 초기화 (defensives는 MarkAuraDirty에서 즉시 캡처됨 → 여기서 wipe 안 함)
			if not BlizzardAuraCache[unit] then
				BlizzardAuraCache[unit] = { buffs = {}, debuffs = {}, defensives = {} }
			else
				wipe(BlizzardAuraCache[unit].buffs)
				wipe(BlizzardAuraCache[unit].debuffs)
				if not BlizzardAuraCache[unit].defensives then
					BlizzardAuraCache[unit].defensives = {}
				end
			end

			BlizzardCacheValid[unit] = true

			-- GUID 매핑 -- [REFACTOR] SafeVal 통일
			local guid = SafeVal(UnitGUID(unit))
			if guid then
				BlizzardCacheGUIDMap[guid] = unit
			end

			-- 버프 캡처: IsShown() + auraInstanceID
			if blizzFrame.buffFrames then
				for i = 1, #blizzFrame.buffFrames do
					local buffFrame = blizzFrame.buffFrames[i]
					if buffFrame and buffFrame:IsShown() and buffFrame.auraInstanceID then
						BlizzardAuraCache[unit].buffs[buffFrame.auraInstanceID] = true
					end
				end
			end

			-- 디버프 캡처
			if blizzFrame.debuffFrames then
				for i = 1, #blizzFrame.debuffFrames do
					local debuffFrame = blizzFrame.debuffFrames[i]
					if debuffFrame and debuffFrame:IsShown() and debuffFrame.auraInstanceID then
						BlizzardAuraCache[unit].debuffs[debuffFrame.auraInstanceID] = true
					end
				end
			end

			-- 디스펠 가능 디버프
			if blizzFrame.dispelDebuffFrames then
				for i = 1, #blizzFrame.dispelDebuffFrames do
					local dispelFrame = blizzFrame.dispelDebuffFrames[i]
					if dispelFrame and dispelFrame:IsShown() and dispelFrame.auraInstanceID then
						BlizzardAuraCache[unit].debuffs[dispelFrame.auraInstanceID] = true
					end
				end
			end

			-- [FIX] CenterDefensiveBuff: MarkAuraDirty에서 즉시 캡처됨
			-- Phase A(지연)에서 읽으면 CompactUnitFrame_UpdateCenterStatusIcon이
			-- 상태를 변경한 후일 수 있어 캡처 유실 가능 → hook 시점 즉시 캡처로 변경

			-- 캡처 완료 → 렌더 큐에 추가 (직접 UpdateAuras 대신)
			local frame = GF.unitFrameMap[unit]
			if frame and frame.gfEventsEnabled then
				dirtyRenderFrames[frame] = true
				hasDirtyRender = true
			end
		end

		wipe(dirtyAuraFrames)
	end

	-- Phase B: 프레임 렌더링 (큐된 모든 프레임 1회씩만)
	if hasDirtyRender then
		hasDirtyRender = false

		for frame in pairs(dirtyRenderFrames) do
			if frame.unit and frame.gfEventsEnabled then
				-- [FIX] 개별 프레임 업데이트를 독립적으로 실행
				-- UpdateAuras 에러가 DebuffHighlight/DefensiveIcon 호출을 차단하지 않도록
				local auraOk, auraErr = pcall(GF.UpdateAuras, GF, frame)
				if not auraOk and ns._debugMode then
					ns:PrintDebug("UpdateAuras error: " .. tostring(auraErr))
				end
				-- [FIX] 아우라 갱신 후 디버프 하이라이트도 갱신
				if GF.UpdateDebuffHighlight then
					GF:UpdateDebuffHighlight(frame)
				end
				-- [12.0.1] 생존기 아이콘도 캐시 기반으로 갱신
				if GF.UpdateDefensiveIcon then
					GF:UpdateDefensiveIcon(frame)
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
	-- [PERF] 모든 hook이 경량 MarkAuraDirty → 실제 처리는 다음 OnUpdate에서 배치
	if CompactUnitFrame_UpdateAuras then
		hooksecurefunc("CompactUnitFrame_UpdateAuras", MarkAuraDirty)
	end
	if CompactUnitFrame_UpdateBuffs then
		hooksecurefunc("CompactUnitFrame_UpdateBuffs", MarkAuraDirty)
	end
	if CompactUnitFrame_UpdateDebuffs then
		hooksecurefunc("CompactUnitFrame_UpdateDebuffs", MarkAuraDirty)
	end

	-- [FIX] CenterDefensiveBuff 전용 hook (UpdateAuras와 별도로 호출될 수 있음)
	if CompactUnitFrame_UpdateCenterStatusIcon then
		hooksecurefunc("CompactUnitFrame_UpdateCenterStatusIcon", MarkAuraDirty)
	end

	-- 그룹 변경 시 캐시 리셋
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function()
		wipe(BlizzardAuraCache)
		wipe(BlizzardCacheGUIDMap)
		wipe(BlizzardCacheValid)
		wipe(dirtyAuraFrames)
		wipe(dirtyRenderFrames) -- [REFACTOR] 렌더 큐도 초기화
		hasDirtyAuras = false
		hasDirtyRender = false
		dirtyProcessor:Hide()

		-- [PERF] 그룹 상태에 따라 colorTimerFrame 활성/비활성
		if GF.UpdateColorTimerState then
			GF:UpdateColorTimerState()
		end

		-- [FIX] 초기 블리자드 프레임 스캔 (Cell 패턴)
		-- hook이 아직 발동하지 않은 시점에서 CenterDefensiveBuff 캡처
		GF:ScheduleBlizzardFrameScan()
	end)
end

-- [FIX] 블리자드 프레임 직접 스캔 (Cell 패턴 — hook 미발동 시 fallback)
-- [PERF] isBatchScan 플래그로 즉시 렌더링 억제 → Phase B에서 일괄 처리
function GF:ScanBlizzardFrames()
	isBatchScan = true -- 즉시 렌더링 억제 (85프레임 × UpdateDefensiveIcon 방지)

	-- 파티 프레임
	for i = 1, 5 do
		local frame = _G["CompactPartyFrameMember" .. i]
		if frame and frame.unit then
			MarkAuraDirty(frame)
		end
	end
	-- 레이드 프레임
	for i = 1, 40 do
		local frame = _G["CompactRaidFrame" .. i]
		if frame and frame.unit then
			MarkAuraDirty(frame)
		end
	end
	-- 레이드 그룹 프레임
	for group = 1, 8 do
		for member = 1, 5 do
			local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
			if frame and frame.unit then
				MarkAuraDirty(frame)
			end
		end
	end

	isBatchScan = false -- 즉시 렌더링 복원
end

-- [PERF] 시차 스캔 스케줄: 3회 → 1회 (0.5s만 — 충분한 대기 후 1회 스캔)
function GF:ScheduleBlizzardFrameScan()
	C_Timer.After(0.5, function() GF:ScanBlizzardFrames() end)
end

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

-- SafeSetCooldown: SetCooldownFromExpirationTime 사용 (11.1+ API)
local function SafeSetCooldown(cooldown, expirationTime, duration)
	if not cooldown then return end
	if not expirationTime or not duration then
		cooldown:Clear()
		return
	end

	-- SetCooldownFromExpirationTime는 secret-safe (C++ 레벨)
	if cooldown.SetCooldownFromExpirationTime then
		cooldown:SetCooldownFromExpirationTime(expirationTime, duration)
	else
		-- 폴백: CooldownFrame_Set (구 API)
		local startTime = expirationTime - duration
		if startTime > 0 and duration > 0 then
			cooldown:SetCooldown(startTime, duration)
		else
			cooldown:Clear()
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

	-- 캐시 조회
	local cache = FindCacheForUnit(unit)

	-- 버프 렌더링
	self:UpdateAuraIconsDirect(frame, frame.buffIcons, cache and cache.buffs, unit, "BUFF")

	-- 디버프 렌더링
	self:UpdateAuraIconsDirect(frame, frame.debuffIcons, cache and cache.debuffs, unit, "DEBUFF")
end

-----------------------------------------------
-- Phase 2: UpdateAuraIconsDirect -- [REFACTOR] auraIs* 필드 기반 우선순위 정렬 추가
-- cacheSet: { [auraInstanceID] = true } (블리자드가 승인한 아우라 목록)
-----------------------------------------------

-- [REFACTOR] 오라 우선순위 점수 계산 (높을수록 먼저 표시)
local SafeBool = ns.SafeBool
local sortBuffer = {} -- 재사용 정렬 버퍼

-- [PERF] 정렬 함수를 모듈 레벨로 (매 호출 시 클로저 생성 방지)
local function SortByPriorityDesc(a, b)
	return a.priority > b.priority
end

local function CalcAuraPriority(auraData, isDebuff)
	local score = 0
	if SafeBool(auraData.isBossAura) then score = score + 100 end
	if SafeBool(auraData.isRaid) then score = score + 50 end
	if isDebuff and SafeVal(auraData.dispelName) then score = score + 30 end
	if SafeBool(auraData.isFromPlayerOrPlayerPet) then score = score + 20 end
	-- duration이 짧을수록 긴급 → 약간 가산
	local dur = SafeNum(auraData.duration, 0)
	if dur > 0 and dur <= 30 then score = score + 10 end
	return score
end

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

-- [REFACTOR] 단일 아이콘 업데이트 헬퍼 (중복 제거)
local function ApplyAuraToIcon(icon, auraData, auraInstanceID, unit, auraType)
	-- 텍스처 (SetTexture는 C++에서 secret 처리)
	SafeSetTexture(icon, auraData.icon)

	-- 쿨다운 스와이프
	SafeSetCooldown(icon.cooldown, auraData.expirationTime, auraData.duration)

	-- [FIX] 스택 수 (DandersFrame 패턴: SetText가 C++ 레벨에서 secret 처리)
	icon.count:SetText("")
	if C_UnitAuras.GetAuraApplicationDisplayCount then
		local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
		if stackText then
			icon.count:SetText(stackText) -- secret string → C++에서 안전하게 렌더링
		end
	end

	-- [FIX] 디버프 테두리 색 (종류별 색상) — ColorCurve API (secret-safe)
	-- [DandersFrames 패턴] GetRGBA() 결과를 비교 없이 SetVertexColor에 직접 전달
	-- 커브에 alpha 포함: None=alpha 0(투명), Magic/Curse등=alpha 1(표시)
	if auraType == "DEBUFF" then
		local db = GF:GetFrameDB(icon.unitFrame or icon:GetParent():GetParent())
		local debuffsDB = db and db.widgets and db.widgets.debuffs or {}
		local showTypeBorder = debuffsDB.showDispelTypeBorder ~= false -- 기본 true

		if showTypeBorder and auraInstanceID and C_UnitAuras.GetAuraDispelTypeColor then
			local curve = GetDispelColorCurve()
			if curve then
				local borderColor = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
				if borderColor then
					-- [DandersFrames 패턴] secret RGBA를 C++ SetVertexColor에 직접 전달
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

	-- [FIX] 지속시간 표시: 네이티브 쿨다운 텍스트 사용 (secret-safe, C++ 레벨)
	-- 커스텀 duration FontString은 비활성 (중복 방지)
	if icon.duration then
		icon.duration:Hide()
	end
	-- SetShownFromBoolean: secret boolean 안전하게 처리
	if icon.nativeCooldownText and C_UnitAuras.DoesAuraHaveExpirationTime then
		local hasExpiration = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
		if icon.nativeCooldownText.SetShownFromBoolean then
			icon.nativeCooldownText:SetShownFromBoolean(hasExpiration, true, false)
		else
			icon.nativeCooldownText:Show() -- fallback: 항상 표시
		end
		-- [FIX] 초기 색상 리셋 (1초 타이머 대기 중 이전 아이콘의 빨간색/임계값 색상 잔존 방지)
		-- 새 오라는 남은 시간이 길므로 흰색(기본)으로 초기화, 1초 후 colorTimer가 정확한 색상 적용
		icon.nativeCooldownText:SetTextColor(1, 1, 1, 1)
	end

	-- auraInstanceID 저장 (툴팁용)
	icon.auraInstanceID = auraInstanceID
	icon:Show()
end

function GF:UpdateAuraIconsDirect(frame, icons, cacheSet, unit, auraType)
	if not icons then return end

	local maxIcons = #icons
	local isDebuff = (auraType == "DEBUFF")

	-- [FIX] cacheSet이 nil인 경우 (HideBlizzard가 파티프레임 이벤트 해제 → hook 미발동)
	-- C_UnitAuras.ForEachAura로 직접 수집하여 fallback
	local effectiveCacheSet = cacheSet
	local fallbackCache = nil
	if not effectiveCacheSet and UnitExists(unit) then
		fallbackCache = {}
		local filter = isDebuff and "HARMFUL" or "HELPFUL"
		local function collector(auraData)
			if auraData and auraData.auraInstanceID then
				fallbackCache[auraData.auraInstanceID] = true
			end
		end
		if C_UnitAuras.ForEachAura then
			C_UnitAuras.ForEachAura(unit, filter, nil, collector)
		elseif AuraUtil and AuraUtil.ForEachAura then
			AuraUtil.ForEachAura(unit, filter, nil, collector)
		end
		effectiveCacheSet = next(fallbackCache) and fallbackCache or nil
	end

	if effectiveCacheSet then
		-- [FIX] per-unit 필터 로드 (블랙리스트/화이트리스트 + 레이드 버프 숨기기)
		local db = GF:GetFrameDB(frame)
		local widgetKey = isDebuff and "debuffs" or "buffs"
		local widgetDB = db and db.widgets and db.widgets[widgetKey]
		local filter = widgetDB and widgetDB.filter

		-- [FIX] 레이드 시너지 버프 필터 준비 (hideRaidBuffs용)
		-- 파티/레이드 어느 쪽이든 켜져 있으면 모든 그룹 프레임에 적용
		local hideRaidBuffs = false
		if not isDebuff then
			local pf = ns.db and ns.db.party and ns.db.party.widgets
				and ns.db.party.widgets.buffs and ns.db.party.widgets.buffs.filter
			local rf = ns.db and ns.db.raid and ns.db.raid.widgets
				and ns.db.raid.widgets.buffs and ns.db.raid.widgets.buffs.filter
			local mrf = ns.db and ns.db.mythicRaid and ns.db.mythicRaid.widgets
				and ns.db.mythicRaid.widgets.buffs and ns.db.mythicRaid.widgets.buffs.filter
			hideRaidBuffs = (pf and pf.hideRaidBuffs) or (rf and rf.hideRaidBuffs) or (mrf and mrf.hideRaidBuffs) or false
		end
		local raidBuffIcons = nil
		if hideRaidBuffs then
			raidBuffIcons = ns.GetRaidSynergyBuffIcons()
		end

		-- 1) auraData 수집 + 우선순위 계산 + 필터링
		local count = 0
		for auraInstanceID in pairs(effectiveCacheSet) do
			local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
			if auraData then
				local shouldShow = true

				-- [FIX] 레이드 시너지 버프 필터 (spellId 1차 + 아이콘 텍스처 2차 fallback)
				if hideRaidBuffs then
					-- 1차: spellId 직접 매칭 (전투 밖에서 확실)
					local spellID = SafeVal(auraData.spellId)
					if spellID and ns.RaidSynergyBuffs[spellID] then
						shouldShow = false
					elseif not spellID and auraData.icon then
						-- 2차: 아이콘 텍스처 매칭 (spellId가 secret일 때)
						local iconTex = auraData.icon
						if not (issecretvalue and issecretvalue(iconTex)) and raidBuffIcons and raidBuffIcons[iconTex] then
							shouldShow = false
						end
					end
				end

				-- [12.0.1] HoT 목록 기반 화이트리스트 (패턴 매칭 결과 재활용)
				if shouldShow and not isDebuff and filter and filter.useHotWhitelist then
					local hotCache = HotAuraCache[unit]
					if hotCache then
						-- HotAuraCache에 있는 auraInstanceID만 통과
						if not hotCache[auraInstanceID] then
							shouldShow = false
						end
					end
				end

				if shouldShow then
					count = count + 1
					-- [PERF] 테이블 재사용: 기존 엔트리 객체 재활용 (GC 압력 감소)
					local entry = sortBuffer[count]
					if not entry then
						entry = {}
						sortBuffer[count] = entry
					end
					entry.id = auraInstanceID
					entry.data = auraData
					entry.priority = CalcAuraPriority(auraData, isDebuff)
				end
			end
		end
		-- 이전 호출의 잔여 엔트리 정리 (sort 정확성 보장)
		for i = count + 1, #sortBuffer do
			sortBuffer[i] = nil
		end

		-- 2) 우선순위 정렬 (높은 점수 먼저) -- [PERF] 모듈 레벨 sort 함수 사용
		if count > 1 then
			table.sort(sortBuffer, SortByPriorityDesc)
		end

		-- 3) 정렬된 순서로 아이콘 적용
		local iconIndex = 1
		for i = 1, count do
			if iconIndex > maxIcons then break end
			local entry = sortBuffer[i]
			ApplyAuraToIcon(icons[iconIndex], entry.data, entry.id, unit, auraType)
			iconIndex = iconIndex + 1
		end

		-- 남은 아이콘 숨기기
		for i = iconIndex, maxIcons do
			icons[i]:Hide()
			icons[i].auraInstanceID = nil
		end
	else
		-- 캐시도 없고 fallback도 없으면 전부 숨김
		for i = 1, maxIcons do
			icons[i]:Hide()
			icons[i].auraInstanceID = nil
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

local durationColorCache = {} -- "party_BUFF" → { mode, curve, rgb, evaluateMethod }

local function BuildDurationColorInfo(frameType, auraType)
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

local function GetDurationColorInfo(frameType, auraType)
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
							if icon:IsShown() and icon.auraInstanceID and icon.nativeCooldownText then
								local info = GetDurationColorInfo(frameType, icon.auraType or "BUFF")

								if info.mode == "fixed" or not info.curve then
									icon.nativeCooldownText:SetTextColor(info.rgb[1], info.rgb[2], info.rgb[3], 1)
								else
									local durationObj = C_UnitAuras.GetAuraDuration(frame.unit, icon.auraInstanceID)
									if durationObj then
										local result
										if info.evaluateMethod == "percent" and durationObj.EvaluateRemainingPercent then
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

				-- [12.0.1] 생존기 네이티브 카운트다운 텍스트 색상 업데이트 (일반 버프와 동일)
				if frame.defensiveIcons then
					for _, btn in ipairs(frame.defensiveIcons) do
						if btn:IsShown() and btn.nativeCooldownText and btn.auraInstanceID then
							-- 기본 흰색 (생존기는 gradient 미적용, 고정 색상)
							btn.nativeCooldownText:SetTextColor(1, 1, 1, 1)
						end
					end
				end

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

-- [PERF] colorTimerFrame 그룹 상태 감시: 그룹 진입 / 테스트모드 시 Show, 아니면 Hide
function GF:UpdateColorTimerState()
	if GF.headersInitialized and (IsInGroup() or IsInRaid()) then
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
	else
		-- 디스펠 가능 디버프 없음 → 하이라이트 숨김
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
	-- [FIX] CreateColor는 C++ 함수라 secret value인 a도 정상 처리됨
	local solidColor = CreateColor(r, g, b, a)
	local clearColor = CreateColor(r, g, b, 0)

	if style == "EDGE" then
		-- Top: 불투명(상) → 투명(하)
		if hl.gradientTop then
			hl.gradientTop:SetGradient("VERTICAL", clearColor, solidColor)
			hl.gradientTop:SetAlpha(alpha)
			hl.gradientTop:Show()
		end
		-- Bottom: 불투명(하) → 투명(상)
		if hl.gradientBottom then
			hl.gradientBottom:SetGradient("VERTICAL", solidColor, clearColor)
			hl.gradientBottom:SetAlpha(alpha)
			hl.gradientBottom:Show()
		end
		-- Left: 불투명(좌) → 투명(우)
		if hl.gradientLeft then
			hl.gradientLeft:SetGradient("HORIZONTAL", solidColor, clearColor)
			hl.gradientLeft:SetAlpha(alpha)
			hl.gradientLeft:Show()
		end
		-- Right: 불투명(우) → 투명(좌)
		if hl.gradientRight then
			hl.gradientRight:SetGradient("HORIZONTAL", clearColor, solidColor)
			hl.gradientRight:SetAlpha(alpha)
			hl.gradientRight:Show()
		end
	elseif style == "TOP_BOTTOM" then
		-- 위아래 그라데이션 (좌우 없음)
		if hl.gradientTop then
			hl.gradientTop:SetGradient("VERTICAL", clearColor, solidColor)
			hl.gradientTop:SetAlpha(alpha)
			hl.gradientTop:Show()
		end
		if hl.gradientBottom then
			hl.gradientBottom:SetGradient("VERTICAL", solidColor, clearColor)
			hl.gradientBottom:SetAlpha(alpha)
			hl.gradientBottom:Show()
		end
		if hl.gradientLeft then hl.gradientLeft:Hide() end
		if hl.gradientRight then hl.gradientRight:Hide() end
	elseif style == "TOP" then
		if hl.gradientTop then
			hl.gradientTop:SetGradient("VERTICAL", clearColor, solidColor)
			hl.gradientTop:SetAlpha(alpha)
			hl.gradientTop:Show()
		end
		if hl.gradientBottom then hl.gradientBottom:Hide() end
		if hl.gradientLeft then hl.gradientLeft:Hide() end
		if hl.gradientRight then hl.gradientRight:Hide() end
	elseif style == "BOTTOM" then
		if hl.gradientBottom then
			hl.gradientBottom:SetGradient("VERTICAL", solidColor, clearColor)
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
	-- [DandersFrames 핵심] SetGradient + CreateColor는 secret value에서 에러 발생
	-- 대신 SetVertexColor(color:GetRGBA())로 직접 적용 (C++ 함수, secret 수용)
	if overlayMode == "gradient" then
		-- [FIX] secret Color → SetGradient + CreateColor 불가 (secret value 에러)
		-- SetVertexColor는 C++ 함수이므로 secret RGBA 직접 처리 가능
		if hl.overlay then hl.overlay:SetAlpha(0) end
		ApplyGradientLayout(hl, dhDB, frame.healthBar)
		local style = (dhDB and dhDB.gradientStyle) or "EDGE"
		local blendMode = (dhDB and dhDB.gradientBlendMode) or "ADD"

		if style == "EDGE" then
			if hl.gradientTop then
				hl.gradientTop:SetVertexColor(color:GetRGBA())
				hl.gradientTop:SetBlendMode(blendMode)
				hl.gradientTop:SetAlpha(overlayAlpha)
				hl.gradientTop:Show()
			end
			if hl.gradientBottom then
				hl.gradientBottom:SetVertexColor(color:GetRGBA())
				hl.gradientBottom:SetBlendMode(blendMode)
				hl.gradientBottom:SetAlpha(overlayAlpha)
				hl.gradientBottom:Show()
			end
			if hl.gradientLeft then
				hl.gradientLeft:SetVertexColor(color:GetRGBA())
				hl.gradientLeft:SetBlendMode(blendMode)
				hl.gradientLeft:SetAlpha(overlayAlpha)
				hl.gradientLeft:Show()
			end
			if hl.gradientRight then
				hl.gradientRight:SetVertexColor(color:GetRGBA())
				hl.gradientRight:SetBlendMode(blendMode)
				hl.gradientRight:SetAlpha(overlayAlpha)
				hl.gradientRight:Show()
			end
		elseif style == "TOP_BOTTOM" then
			if hl.gradientTop then
				hl.gradientTop:SetVertexColor(color:GetRGBA())
				hl.gradientTop:SetBlendMode(blendMode)
				hl.gradientTop:SetAlpha(overlayAlpha)
				hl.gradientTop:Show()
			end
			if hl.gradientBottom then
				hl.gradientBottom:SetVertexColor(color:GetRGBA())
				hl.gradientBottom:SetBlendMode(blendMode)
				hl.gradientBottom:SetAlpha(overlayAlpha)
				hl.gradientBottom:Show()
			end
			if hl.gradientLeft then hl.gradientLeft:Hide() end
			if hl.gradientRight then hl.gradientRight:Hide() end
		elseif style == "TOP" then
			if hl.gradientTop then
				hl.gradientTop:SetVertexColor(color:GetRGBA())
				hl.gradientTop:SetBlendMode(blendMode)
				hl.gradientTop:SetAlpha(overlayAlpha)
				hl.gradientTop:Show()
			end
			if hl.gradientBottom then hl.gradientBottom:Hide() end
			if hl.gradientLeft then hl.gradientLeft:Hide() end
			if hl.gradientRight then hl.gradientRight:Hide() end
		elseif style == "BOTTOM" then
			if hl.gradientBottom then
				hl.gradientBottom:SetVertexColor(color:GetRGBA())
				hl.gradientBottom:SetBlendMode(blendMode)
				hl.gradientBottom:SetAlpha(overlayAlpha)
				hl.gradientBottom:Show()
			end
			if hl.gradientTop then hl.gradientTop:Hide() end
			if hl.gradientLeft then hl.gradientLeft:Hide() end
			if hl.gradientRight then hl.gradientRight:Hide() end
		else -- "FULL"
			if hl.gradientTop then
				hl.gradientTop:SetVertexColor(color:GetRGBA())
				hl.gradientTop:SetAlpha(overlayAlpha)
				hl.gradientTop:Show()
			end
			if hl.gradientBottom then hl.gradientBottom:Hide() end
			if hl.gradientLeft then hl.gradientLeft:Hide() end
			if hl.gradientRight then hl.gradientRight:Hide() end
		end
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
		local auraAnchorInfo = {
			unitToken = frame.unit,
			auraIndex = i,
			parent = anchor,
			showCountdownFrame = true,
			showCountdownNumbers = true,
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
			},
		}
		local ok, anchorID = pcall(C_UnitAuras.AddPrivateAuraAnchor, auraAnchorInfo)
		if ok and anchorID then
			anchor._auraAnchorID = anchorID
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
-----------------------------------------------

local hotEventFrame = CreateFrame("Frame")
hotEventFrame:RegisterEvent("UNIT_AURA")
hotEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
hotEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hotEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
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
