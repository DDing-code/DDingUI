--[[
	ddingUI UnitFrames
	Modules/AuraCache.lua - 중앙 오라 데이터 캐시

	[12.1] DandersFrames BlizzardAuraCache 패턴 완전 차용:
	- Blizzard CompactUnitFrame의 buffFrames/debuffFrames/dispelDebuffFrames 후킹
	- playerDispellable: Blizzard가 결정한 "플레이어 디스펠 가능" 디버프 캐시
	- myBuffs: Blizzard buffFrames에 표시된 내 버프 auraInstanceID 캐시
	- 기존 HARMFUL/HELPFUL 스캔 캐시도 유지 (oUF 프레임용)

	무효화: CompactUnitFrame_UpdateAuras 후킹 + UNIT_AURA 이벤트
	        PLAYER_ENTERING_WORLD 시 전체 초기화
]]

local _, ns = ...

local AuraCache = {}
ns.AuraCache = AuraCache

local C_UnitAuras = C_UnitAuras
local GetTime = GetTime
local wipe = wipe
local issecretvalue = issecretvalue
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local hooksecurefunc = hooksecurefunc
local pairs = pairs
local ipairs = ipairs
local type = type

-- ============================================================
-- 기존 스캔 캐시 (oUF 프레임 및 호환성용)
-- ============================================================

local cache = {}
local frameCounter = 0

local function ScanUnit(unit)
	local data = cache[unit]
	if not data then
		data = { helpful = {}, harmful = {}, frame = 0 }
		cache[unit] = data
	else
		wipe(data.helpful)
		wipe(data.harmful)
	end
	data.frame = frameCounter

	-- HELPFUL 스캔
	local index = 1
	while true do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
		if not auraData then break end
		data.helpful[index] = auraData
		index = index + 1
	end

	-- HARMFUL 스캔
	index = 1
	while true do
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, "HARMFUL")
		if not auraData then break end
		data.harmful[index] = auraData
		index = index + 1
	end

	return data
end

-- ============================================================
-- 프레임 카운터 (OnUpdate로 매 프레임 증가)
-- ============================================================

local counterFrame = CreateFrame("Frame")
counterFrame:Hide()
counterFrame:SetScript("OnUpdate", function()
	frameCounter = frameCounter + 1
end)

function AuraCache:UpdateCounterState()
	if IsInGroup() or IsInRaid() then
		counterFrame:Show()
	else
		counterFrame:Hide()
		wipe(cache)
	end
end

-- ============================================================
-- Public API (기존 호환)
-- ============================================================

function AuraCache:GetHelpful(unit)
	if not unit then return {} end
	local data = cache[unit]
	if data and data.frame == frameCounter then
		return data.helpful
	end
	data = ScanUnit(unit)
	return data.helpful
end

function AuraCache:GetHarmful(unit)
	if not unit then return {} end
	local data = cache[unit]
	if data and data.frame == frameCounter then
		return data.harmful
	end
	data = ScanUnit(unit)
	return data.harmful
end

function AuraCache:Invalidate(unit)
	if unit then
		cache[unit] = nil
	else
		wipe(cache)
	end
end

function AuraCache:GetFrameCounter()
	return frameCounter
end

-- ============================================================
-- BLIZZARD AURA CACHE (DandersFrames 패턴)
-- Blizzard 기본 레이드 프레임의 buffFrames/debuffFrames/dispelDebuffFrames 후킹
-- ============================================================

local BlizzCache = {}
AuraCache.BlizzCache = BlizzCache

-- BlizzCache[unit] = {
--   playerDispellable = { [auraInstanceID] = true },   -- 디스펠 가능 디버프
--   myBuffs = { [auraInstanceID] = true },              -- 내 버프
-- }

local blizzHookActive = false

-- Blizzard 프레임에서 오라 캐시 캡처
local function CaptureFromBlizzardFrame(frame, triggerUpdate)
	if not frame or not frame.unit then return end
	if frame.unitExists == false then return end

	-- 네임플레이트 제외
	local unit = frame.unit
	if unit and type(unit) == "string" and unit:find("nameplate") then return end
	local displayedUnit = frame.displayedUnit
	if displayedUnit and type(displayedUnit) == "string" and displayedUnit:find("nameplate") then return end

	-- 프리뷰/설정 프레임 제외
	local frameName = frame.GetName and type(frame.GetName) == "function" and frame:GetName()
	if frameName then
		if frameName:find("Preview") or frameName:find("Settings") or frameName:find("NamePlate") then
			return
		end
	end

	-- 캐시 초기화
	if not BlizzCache[unit] then
		BlizzCache[unit] = { playerDispellable = {}, myBuffs = {} }
	end

	local unitCache = BlizzCache[unit]
	wipe(unitCache.playerDispellable)
	wipe(unitCache.myBuffs)

	-- 디스펠 가능 디버프 캡처 (dispelDebuffFrames)
	-- Blizzard가 이미 "현재 플레이어가 디스펠 가능한" 디버프만 여기 표시
	if frame.dispelDebuffFrames and type(frame.dispelDebuffFrames) == "table" then
		for _, debuffFrame in ipairs(frame.dispelDebuffFrames) do
			if debuffFrame and debuffFrame.IsShown and debuffFrame:IsShown() and debuffFrame.auraInstanceID then
				unitCache.playerDispellable[debuffFrame.auraInstanceID] = true
			end
		end
	end

	-- 내 버프 캡처 (buffFrames)
	-- Blizzard 레이드 프레임의 buffFrames는 기본적으로 "내가 건 버프"만 표시
	if frame.buffFrames and type(frame.buffFrames) == "table" then
		for _, buffFrame in ipairs(frame.buffFrames) do
			if buffFrame and buffFrame.IsShown and buffFrame:IsShown() and buffFrame.auraInstanceID then
				unitCache.myBuffs[buffFrame.auraInstanceID] = true
			end
		end
	end
end

-- ============================================================
-- Blizzard 레이드 프레임 전체 스캔
-- ============================================================

local function ScanAllBlizzardFrames()
	-- 파티 프레임
	for i = 1, 5 do
		local frame = _G["CompactPartyFrameMember" .. i]
		if frame and frame.unit and frame.unitExists ~= false then
			CaptureFromBlizzardFrame(frame, false)
		end
	end

	-- 레이드 프레임
	for i = 1, 40 do
		local frame = _G["CompactRaidFrame" .. i]
		if frame and frame.unit and frame.unitExists ~= false then
			CaptureFromBlizzardFrame(frame, false)
		end
	end

	-- 레이드 그룹 프레임
	for group = 1, 8 do
		for member = 1, 5 do
			local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
			if frame and frame.unit and frame.unitExists ~= false then
				CaptureFromBlizzardFrame(frame, false)
			end
		end
	end
end

-- ============================================================
-- Blizzard 후킹 설정
-- ============================================================

local function SetupBlizzardHooks()
	if blizzHookActive then return end

	if CompactUnitFrame_UpdateAuras then
		hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
			if not frame or frame.unitExists == false then return end
			CaptureFromBlizzardFrame(frame, false)
		end)
		blizzHookActive = true
	end

	if CompactUnitFrame_UpdateBuffs then
		hooksecurefunc("CompactUnitFrame_UpdateBuffs", function(frame)
			if not frame or frame.unitExists == false then return end
			CaptureFromBlizzardFrame(frame, false)
		end)
	end

	if CompactUnitFrame_UpdateDebuffs then
		hooksecurefunc("CompactUnitFrame_UpdateDebuffs", function(frame)
			if not frame or frame.unitExists == false then return end
			CaptureFromBlizzardFrame(frame, false)
		end)
	end
end

-- ============================================================
-- BlizzCache Public API
-- ============================================================

-- 유닛의 디스펠 가능 디버프 auraInstanceID 반환 (첫 번째)
function AuraCache:GetPlayerDispellable(unit)
	local unitCache = BlizzCache[unit]
	if not unitCache then return nil end
	return next(unitCache.playerDispellable) -- 첫 번째 auraInstanceID 반환
end

-- 유닛에 디스펠 가능 디버프가 있는지 여부
function AuraCache:HasPlayerDispellable(unit)
	local unitCache = BlizzCache[unit]
	if not unitCache then return false end
	return next(unitCache.playerDispellable) ~= nil
end

-- 유닛의 모든 디스펠 가능 디버프 auraInstanceID 세트 반환
function AuraCache:GetAllPlayerDispellable(unit)
	local unitCache = BlizzCache[unit]
	if not unitCache then return nil end
	return unitCache.playerDispellable
end

-- 유닛에 내 버프가 있는지 여부 (HoT 추적용)
function AuraCache:UnitHasMyBuff(unit)
	local unitCache = BlizzCache[unit]
	if not unitCache then return false end
	return next(unitCache.myBuffs) ~= nil
end

-- 유닛의 내 버프 auraInstanceID 세트 반환
function AuraCache:GetMyBuffs(unit)
	local unitCache = BlizzCache[unit]
	if not unitCache then return nil end
	return unitCache.myBuffs
end

-- BlizzCache 전체 반환 (디버깅용)
function AuraCache:GetBlizzCache()
	return BlizzCache
end

-- BlizzCache 활성 여부
function AuraCache:IsBlizzHookActive()
	return blizzHookActive
end

-- ============================================================
-- 이벤트 처리
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, unit)
	if event == "UNIT_AURA" then
		if unit then
			ScanUnit(unit)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		wipe(cache)
		wipe(BlizzCache)
		AuraCache:UpdateCounterState()

		-- Blizzard 후킹 설정 (첫 진입 시)
		SetupBlizzardHooks()

		-- 지연 스캔 (Blizzard 프레임 초기화 대기)
		C_Timer.After(0.5, ScanAllBlizzardFrames)
		C_Timer.After(1.5, ScanAllBlizzardFrames)
	elseif event == "GROUP_ROSTER_UPDATE" then
		AuraCache:UpdateCounterState()

		-- 로스터 변경 시 재스캔
		C_Timer.After(0.3, ScanAllBlizzardFrames)
		C_Timer.After(1.0, ScanAllBlizzardFrames)
	end
end)
