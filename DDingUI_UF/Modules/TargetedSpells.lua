--[[
	ddingUI UnitFrames
	Modules/TargetedSpells.lua - 수신 주문 경고

	적이 특정 유닛을 대상으로 주문 시전 시 해당 프레임 강조
	UNIT_SPELLCAST_START 기반 → 대상 유닛의 프레임에 시각 효과
]]

local _, ns = ...

local TargetedSpells = {}
ns.TargetedSpells = TargetedSpells

local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo

-----------------------------------------------
-- 위험 주문 ID 목록 (주요 보스/PvP 주문)
-- 빈 테이블이면 모든 적 시전 감지
-----------------------------------------------
local dangerousSpells = {}

-----------------------------------------------
-- Active Indicators
-----------------------------------------------
local activeIndicators = {} -- [frameGUID] = { texture, timer }

local function GetOrCreateIndicator(frame)
	if frame._targetedSpellIndicator then
		return frame._targetedSpellIndicator
	end

	local indicator = frame:CreateTexture(nil, "OVERLAY", nil, 7)
	indicator:SetAllPoints()
	indicator:SetColorTexture(1, 0.2, 0.1, 0.3)
	indicator:SetBlendMode("ADD")
	indicator:Hide()
	frame._targetedSpellIndicator = indicator

	return indicator
end

local function ShowIndicator(frame, spellID, duration)
	local indicator = GetOrCreateIndicator(frame)

	-- 색상: 위험도에 따라
	local db = ns.db and ns.db.targetedSpells
	if db and db.color then
		indicator:SetColorTexture(db.color[1] or 1, db.color[2] or 0.2, db.color[3] or 0.1, db.color[4] or 0.3)
	end

	indicator:Show()
	indicator._spellID = spellID

	-- 타이머: 시전 완료/취소 시 자동 제거
	if indicator._timer then
		indicator._timer:Cancel()
	end
	local safeTime = math.min(duration or 5, 10) -- 최대 10초
	indicator._timer = C_Timer.NewTimer(safeTime, function()
		indicator:Hide()
		indicator._spellID = nil
	end)
end

local function HideIndicator(frame)
	if not frame._targetedSpellIndicator then return end
	frame._targetedSpellIndicator:Hide()
	frame._targetedSpellIndicator._spellID = nil
	if frame._targetedSpellIndicator._timer then
		frame._targetedSpellIndicator._timer:Cancel()
		frame._targetedSpellIndicator._timer = nil
	end
end

-----------------------------------------------
-- GUID → Frame 매핑
-----------------------------------------------
-- [PERF] O(n²) select(i, GetChildren()) → 캐시 패턴으로 교체
local function FindFrameByGUID(guid)
	if not guid then return nil end

	-- [PERF] GroupFrames unitFrameMap 우선 조회 (O(1))
	local GF = ns.GroupFrames
	if GF and GF.unitFrameMap then
		for unit, frame in pairs(GF.unitFrameMap) do
			if frame and frame:IsVisible() and UnitExists(unit) and UnitGUID(unit) == guid then
				return frame
			end
		end
	end

	-- 개별 프레임 (player/target 등)
	if ns.frames then
		for _, frame in pairs(ns.frames) do
			if frame.unit and UnitExists(frame.unit) and UnitGUID(frame.unit) == guid then
				return frame
			end
		end
	end

	-- 파티 — [PERF] GetChildren() 1회만 호출
	if ns.headers and ns.headers.party then
		local children = { ns.headers.party:GetChildren() }
		for _, child in ipairs(children) do
			if child and child.unit and UnitExists(child.unit) and UnitGUID(child.unit) == guid then
				return child
			end
		end
	end

	-- 레이드 — [PERF] GetChildren() 1회만 호출 (per group)
	if ns.headers then
		for g = 1, 8 do
			local header = ns.headers["raid_group" .. g]
			if header then
				local children = { header:GetChildren() }
				for _, child in ipairs(children) do
					if child and child.unit and UnitExists(child.unit) and UnitGUID(child.unit) == guid then
						return child
					end
				end
			end
		end
	end

	return nil
end

-----------------------------------------------
-- Event Handler
-----------------------------------------------

local eventFrame = CreateFrame("Frame")

local function OnSpellCast(unit)
	if not unit then return end

	-- 적 유닛만 감시
	local reaction = UnitReaction(unit, "player")
	if reaction and reaction > 4 then return end -- friendly = skip

	-- 시전 대상 확인
	local targetUnit = unit .. "target"
	if not UnitExists(targetUnit) then return end

	-- 아군 대상인지 확인
	local targetReaction = UnitReaction(targetUnit, "player")
	if not targetReaction or targetReaction < 5 then return end -- hostile target = skip

	-- 시전 정보
	local name, _, _, startTime, endTime, _, _, _, spellID
	if UnitCastingInfo then
		name, _, _, startTime, endTime, _, _, _, spellID = UnitCastingInfo(unit)
	end
	if not name and UnitChannelInfo then
		name, _, _, startTime, endTime, _, _, _, spellID = UnitChannelInfo(unit)
	end
	if not name then return end

	-- 위험 주문 필터 (비어있으면 모든 적 시전)
	if next(dangerousSpells) and not dangerousSpells[spellID] then return end

	-- 대상 프레임 찾기
	local targetGUID = UnitGUID(targetUnit)
	local targetFrame = FindFrameByGUID(targetGUID)
	if not targetFrame then return end

	-- 시전 시간 계산
	local duration = 3
	if startTime and endTime then
		duration = (endTime - startTime) / 1000
	end

	ShowIndicator(targetFrame, spellID, duration)
end

local function OnSpellStop(unit)
	if not unit then return end

	local targetUnit = unit .. "target"
	if not UnitExists(targetUnit) then return end

	local targetGUID = UnitGUID(targetUnit)
	local frame = FindFrameByGUID(targetGUID)
	if frame then
		HideIndicator(frame)
	end
end

local function OnEvent(self, event, unit, ...)
	if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
		OnSpellCast(unit)
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
		or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		OnSpellStop(unit)
	end
end

-----------------------------------------------
-- Public API
-----------------------------------------------

function TargetedSpells:Enable()
	eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
	eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
	eventFrame:SetScript("OnEvent", OnEvent)
end

function TargetedSpells:Disable()
	eventFrame:UnregisterAllEvents()
	eventFrame:SetScript("OnEvent", nil)

	-- 모든 인디케이터 숨기기
	if ns.frames then
		for _, frame in pairs(ns.frames) do
			HideIndicator(frame)
		end
	end
end

function TargetedSpells:Initialize()
	local db = ns.db and ns.db.targetedSpells
	if not db or db.enabled == false then return end

	-- 위험 주문 로드
	if db.spellList then
		wipe(dangerousSpells)
		for _, id in ipairs(db.spellList) do
			dangerousSpells[id] = true
		end
	end

	self:Enable()
end
