--[[
	ddingUI UnitFrames
	GroupFrames/Core.lua — 그룹 프레임 모듈 코어

	oUF 대신 SecureGroupHeaderTemplate 직접 사용
	DandersFrames 패턴: 중앙 이벤트 디스패치 + unitFrameMap O(1) 조회
]]

local _, ns = ...

local GF = {}
ns.GroupFrames = GF

-- StyleLib
local SL = _G.DDingUI_StyleLib
local FLAT = SL and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local SL_FONT = SL and SL.Font.path or "Fonts\\2002.TTF"

-----------------------------------------------
-- API Upvalue Caching
-----------------------------------------------

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local wipe = wipe
local pairs = pairs
local GetTime = GetTime
local C_Timer = C_Timer
local SecureButton_GetModifiedUnit = SecureButton_GetModifiedUnit
local issecretvalue = issecretvalue
local SafeVal = ns.SafeVal   -- [REFACTOR] 통합 유틸리티

-----------------------------------------------
-- State
-----------------------------------------------

GF.initialized = false
GF.headersInitialized = false

-- O(1) unit → frame lookup (DF 패턴)
GF.unitFrameMap = {}

-- GUID 캐시 (유닛 변경 감지용)
GF.unitGuidCache = {}

-- 파티/레이드 헤더 참조
GF.partyHeader = nil
GF.raidHeaders = {} -- [1-8]

-- 모든 그룹 프레임 (순회용)
GF.allFrames = {}

-- [FIX] 전투 중 지연된 레이아웃 큐
GF.combatDeferredLayouts = {}

-----------------------------------------------
-- 전투 중 secure layout 지연 처리
-----------------------------------------------

function GF:DeferSecureLayout(frame)
	self.combatDeferredLayouts[frame] = true
	-- 전용 이벤트 프레임 생성 (1회)
	if not self._combatDeferFrame then
		self._combatDeferFrame = CreateFrame("Frame")
		self._combatDeferFrame:SetScript("OnEvent", function(evFrame, event)
			if event == "PLAYER_REGEN_ENABLED" then
				evFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
				-- 전투 종료 → 지연된 프레임에 ApplyLayout 재실행
				for deferredFrame in pairs(GF.combatDeferredLayouts) do
					if deferredFrame and deferredFrame:IsVisible() then
						GF:ApplyLayout(deferredFrame)
					end
				end
				wipe(GF.combatDeferredLayouts)
			end
		end)
	end
	self._combatDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-----------------------------------------------
-- Unit Frame Map 관리
-----------------------------------------------

function GF:RebuildUnitFrameMap()
	wipe(self.unitFrameMap)
	wipe(self.unitGuidCache)

	for _, frame in pairs(self.allFrames) do
		if frame and frame:IsVisible() then
			-- [FIX] frame.unit 손실 방어: SecureButton에서 현재 유닛 재확인
			local unit = frame.unit
			if not unit and frame.gfIsHeaderChild then
				local secUnit = SecureButton_GetModifiedUnit(frame)
				if secUnit and secUnit ~= "" then
					frame.unit = secUnit
					unit = secUnit
				end
			end
			if unit then
				self.unitFrameMap[unit] = frame
				-- [REFACTOR] UnitGUID는 secret string 반환 가능
				local guid = SafeVal(UnitGUID(unit))
				self.unitGuidCache[unit] = guid
			end
			-- [FIX] 프라이빗 오라 앵커 갱신
			if self.UpdatePrivateAuraAnchors then
				self:UpdatePrivateAuraAnchors(frame)
			end
		end
	end

	-- [PERF] HoT 캐시 벌크 리빌드 (lazy 풀스캔 폭풍 방지)
	if self.RebuildHotCache then
		self:RebuildHotCache()
	else
		self:ResetHotCache()
		self:RefreshAllHotIndicators()
	end
end

function GF:GetFrameForUnit(unit)
	return self.unitFrameMap[unit]
end

-----------------------------------------------
-- DB 접근 헬퍼
-----------------------------------------------

function GF:GetPartyDB()
	return ns.db and ns.db.party or {}
end

function GF:GetRaidDB()
	return ns.db and ns.db.raid or {}
end

function GF:GetFrameDB(frame)
	if frame and frame.isRaidFrame then
		-- [MYTHIC-RAID] 활성 레이드 DB 반환 (신화 레이드 감지 시 mythicRaid DB)
		if self.GetActiveRaidDB then
			return self:GetActiveRaidDB()
		end
		return self:GetRaidDB()
	end
	return self:GetPartyDB()
end

-----------------------------------------------
-- 중앙 이벤트 디스패치 (DF 패턴)
-----------------------------------------------

local eventFrame = CreateFrame("Frame")

-- 유닛별 이벤트 (고빈도, 먼저 처리)
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("UNIT_MAXPOWER")
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
eventFrame:RegisterEvent("UNIT_CONNECTION")
-- 흡수/힐 예측
eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
eventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
-- 상태 아이콘
eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")
eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
eventFrame:RegisterEvent("UNIT_PHASE")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
-- 위협/하이라이트 -- [12.0.1]
eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
-- 글로벌 이벤트
eventFrame:RegisterEvent("RAID_TARGET_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
eventFrame:RegisterEvent("READY_CHECK_FINISHED")
eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")

local lastMapRebuild = 0

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
	if not GF.headersInitialized then return end

	local unitFrameMap = GF.unitFrameMap

	-- ============================
	-- UNIT_HEALTH / UNIT_MAXHEALTH
	-- ============================
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]

		-- self-healing: 맵 miss → 재구축 (1초 쿨다운)
		if not frame and (unit:match("^raid%d") or unit:match("^party%d") or unit == "player") then
			local now = GetTime()
			if (now - lastMapRebuild) > 1.0 then
				lastMapRebuild = now
				GF:RebuildUnitFrameMap()
				frame = unitFrameMap[unit]
			end
		end

		if frame and frame.gfEventsEnabled then
			if GF.UpdateHealthFast then
				GF:UpdateHealthFast(frame)
			end
			-- [12.0.1] maxHealth 변경 → 힐예측/보호막 비율 갱신
			if GF.UpdateHealPrediction then
				GF:UpdateHealPrediction(frame)
			end
		end
		return
	end

	-- ============================
	-- UNIT_AURA
	-- ============================
	if event == "UNIT_AURA" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			-- [FIX] BlizzardAuraCache hook이 발동하지 않는 유닛(파티)에 대해
			-- UNIT_AURA 이벤트에서 직접 아우라 업데이트 큐에 추가
			-- hook 기반 캐시가 있으면 ProcessDirtyAuras에서 중복 방지됨
			if GF.QueueAuraUpdate then
				GF:QueueAuraUpdate(frame)
			end
			-- 생존기 아이콘: ProcessDirtyAuras Phase B에서 캐시 구축 후 자동 호출
			-- [PERF] 디버프 하이라이트: ProcessDirtyAuras Phase B에서 이미 호출됨 (중복 제거)
			-- [HOT-TRACKER] HoT 추적 업데이트 (Auras.lua 이벤트 프레임에서 독립 처리)
			-- UNIT_AURA는 hotEventFrame에서 직접 처리하므로 여기서는 생략
		end
		return
	end

	-- ============================
	-- UNIT_POWER / UNIT_MAXPOWER / UNIT_DISPLAYPOWER
	-- ============================
	if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			if GF.UpdatePower then
				GF:UpdatePower(frame)
			end
		end
		return
	end

	-- ============================
	-- UNIT_NAME_UPDATE
	-- ============================
	if event == "UNIT_NAME_UPDATE" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			if GF.UpdateName then
				GF:UpdateName(frame)
			end
		end
		return
	end

	-- ============================
	-- UNIT_CONNECTION
	-- ============================
	if event == "UNIT_CONNECTION" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			if GF.FullFrameRefresh then
				GF:FullFrameRefresh(frame)
			end
		end
		return
	end

	-- ============================
	-- 흡수/힐 예측
	-- ============================
	if event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_PREDICTION" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			if GF.UpdateAbsorb then GF:UpdateAbsorb(frame) end
			if GF.UpdateHealPrediction then GF:UpdateHealPrediction(frame) end
		end
		return
	end

	-- ============================
	-- 상태 아이콘 이벤트
	-- ============================
	if event == "INCOMING_RESURRECT_CHANGED" or event == "INCOMING_SUMMON_CHANGED" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			if GF.UpdateStatusIcons then GF:UpdateStatusIcons(frame) end
		end
		return
	end

	if event == "UNIT_PHASE" or event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			if GF.UpdateStatusIcons then GF:UpdateStatusIcons(frame) end
			-- [FIX] 사망/부활/오프라인 상태 변경 시 체력바 색상도 갱신
			-- UNIT_HEALTH 시점에는 UnitIsDead()가 아직 false일 수 있음
			if GF.ApplyHealthColor then GF:ApplyHealthColor(frame) end
		end
		return
	end

	if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			if GF.FullFrameRefresh then
				C_Timer.After(0, function()
					if frame and frame.unit then GF:FullFrameRefresh(frame) end
				end)
			end
		end
		return
	end

	-- ============================
	-- UNIT_THREAT_SITUATION_UPDATE -- [12.0.1]
	-- ============================
	if event == "UNIT_THREAT_SITUATION_UPDATE" then
		local unit = arg1
		if not unit then return end
		local frame = unitFrameMap[unit]
		if frame and frame.gfEventsEnabled then
			if GF.UpdateThreat then GF:UpdateThreat(frame) end
		end
		return
	end

	-- ============================
	-- PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED -- [12.0.1]
	-- ============================
	if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
		for _, frame in pairs(GF.allFrames) do
			if frame and frame.gfEventsEnabled and frame:IsVisible() then
				if GF.UpdateHighlight then GF:UpdateHighlight(frame) end
			end
		end
		return
	end

	-- ============================
	-- 글로벌 이벤트 (전체 프레임 순회)
	-- ============================
	if event == "RAID_TARGET_UPDATE" then
		for _, frame in pairs(GF.allFrames) do
			if frame and frame.gfEventsEnabled and frame:IsVisible() then
				if GF.UpdateRaidTargetIcon then GF:UpdateRaidTargetIcon(frame) end
			end
		end
		return
	end

	if event == "PLAYER_ROLES_ASSIGNED" then
		for _, frame in pairs(GF.allFrames) do
			if frame and frame.gfEventsEnabled and frame:IsVisible() then
				if GF.UpdateRoleIcon then GF:UpdateRoleIcon(frame) end
			end
		end
		return
	end

	if event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" or event == "READY_CHECK_FINISHED" then
		for _, frame in pairs(GF.allFrames) do
			if frame and frame.gfEventsEnabled and frame:IsVisible() then
				if GF.UpdateReadyCheck then GF:UpdateReadyCheck(frame, event) end
			end
		end
		return
	end

	if event == "PARTY_LEADER_CHANGED" then
		for _, frame in pairs(GF.allFrames) do
			if frame and frame.gfEventsEnabled and frame:IsVisible() then
				if GF.UpdateLeaderIcon then GF:UpdateLeaderIcon(frame) end
			end
		end
		return
	end
end)

-----------------------------------------------
-- 초기화
-----------------------------------------------

function GF:Initialize()
	if self.initialized then return end

	-- 헤더 생성
	if GF.CreateHeaders then
		GF:CreateHeaders()
	end

	self.initialized = true
	ns.Debug("GroupFrames module initialized")
end

-- 전체 프레임 갱신 (설정 변경 시)
function GF:UpdateAll()
	if InCombatLockdown() then return end

	-- [FIX] 지속시간 색상 캐시 리셋 (설정 변경 반영)
	if self.ResetDurationColorCache then self:ResetDurationColorCache() end

	for _, frame in pairs(self.allFrames) do
		if frame and frame:IsVisible() then
			-- [FIX] frame.unit 손실 방어
			if not frame.unit and frame.gfIsHeaderChild then
				local secUnit = SecureButton_GetModifiedUnit(frame)
				if secUnit and secUnit ~= "" then
					frame.unit = secUnit
					self.unitFrameMap[secUnit] = frame
				end
			end
			if frame.unit then
				if GF.ApplyLayout then GF:ApplyLayout(frame) end
				if GF.FullFrameRefresh then GF:FullFrameRefresh(frame) end
			end
		end
	end
end

-- 전체 프레임 풀 리프레시 (데이터만, 레이아웃 변경 없이)
function GF:RefreshAll()
	for _, frame in pairs(self.allFrames) do
		if frame and frame:IsVisible() then
			-- [FIX] frame.unit 손실 방어: SecureButton에서 현재 유닛 재확인
			if not frame.unit and frame.gfIsHeaderChild then
				local secUnit = SecureButton_GetModifiedUnit(frame)
				if secUnit and secUnit ~= "" then
					frame.unit = secUnit
					self.unitFrameMap[secUnit] = frame
				end
			end
			if frame.unit then
				if GF.FullFrameRefresh then GF:FullFrameRefresh(frame) end
			end
		end
	end
end
