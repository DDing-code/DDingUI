--[[
	DDingUI DF Plugin
	FlightFade.lua - Flight/Mount/Vehicle Fade System

	DDingUI_UF의 FlightHide 시스템을 DandersFrames에 포팅.
	비행/탈것/비히클 탑승 시 프레임을 부드럽게 페이드아웃합니다.
]]

local FlightFade = {}
DDingUI_DF_FlightFade = FlightFade

-- ============================================================
-- STATE
-- ============================================================

FlightFade.isActive = false
FlightFade._hiding = false
FlightFade._currentAlpha = 1

local settings = nil  -- reference to db.flightFade
local wasHidden = false
local currentAlpha = 1
local targetAlpha = 1
local FADE_DURATION = 0.5
local CHECK_INTERVAL = 0.5
local checkElapsed = 0
local onUpdateFrame = nil
local abs = math.abs

-- ============================================================
-- CONDITION CHECKS
-- ============================================================

local function ShouldHide()
	if not settings then return false end

	-- 인스턴스 밖에서만 적용 옵션
	if settings.hideOutsideInstanceOnly then
		local _, instanceType = IsInInstance()
		if instanceType and instanceType ~= "none" then
			return false
		end
	end

	if settings.hideWhileFlying and IsFlying() then return true end
	if settings.hideWhileMounted and IsMounted() then return true end
	if settings.hideInVehicle and UnitInVehicle("player") then return true end

	return false
end

local function AnyEnabled()
	if not settings then return false end
	return settings.hideWhileFlying or settings.hideWhileMounted or settings.hideInVehicle
end

-- ============================================================
-- ALPHA APPLICATION
-- DandersFrames API를 사용하여 프레임 알파 제어
-- ============================================================

local function ApplyAlpha(alpha)
	currentAlpha = alpha
	FlightFade._currentAlpha = alpha

	-- DandersFrames 공개 API를 통해 프레임 접근
	-- 파티 컨테이너
	local partyContainer = DandersFrames_GetPartyContainer and DandersFrames_GetPartyContainer()
	if partyContainer and partyContainer.SetAlpha then
		partyContainer:SetAlpha(alpha)
	end

	-- 파티 헤더
	local partyHeader = DandersFrames_GetPartyHeader and DandersFrames_GetPartyHeader()
	if partyHeader and partyHeader.SetAlpha then
		partyHeader:SetAlpha(alpha)
	end

	-- 레이드 컨테이너
	local raidContainer = DandersFrames_GetRaidContainer and DandersFrames_GetRaidContainer()
	if raidContainer and raidContainer.SetAlpha then
		raidContainer:SetAlpha(alpha)
	end

	-- 레이드 그룹 헤더 (1-8)
	if DandersFrames_GetRaidGroupHeader then
		for i = 1, 8 do
			local rh = DandersFrames_GetRaidGroupHeader(i)
			if rh and rh.SetAlpha then
				rh:SetAlpha(alpha)
			end
		end
	end

	-- 플랫 레이드 헤더
	local flatHeader = DandersFrames_GetFlatRaidHeader and DandersFrames_GetFlatRaidHeader()
	if flatHeader and flatHeader.SetAlpha then
		flatHeader:SetAlpha(alpha)
	end

	-- Pinned 프레임 컨테이너
	if DandersFrames_GetPinnedContainer then
		for i = 1, 2 do
			local pc = DandersFrames_GetPinnedContainer(i)
			if pc and pc.SetAlpha then
				pc:SetAlpha(alpha)
			end
		end
	end
end

-- ============================================================
-- ONUPDATE HANDLER (Smooth interpolation)
-- ============================================================

local function OnUpdate(_, elapsed)
	if not AnyEnabled() then
		if currentAlpha < 1 or FlightFade.isActive then
			FlightFade.isActive = false
			FlightFade._hiding = false
			targetAlpha = 1
			ApplyAlpha(1)
		else
			if onUpdateFrame then
				onUpdateFrame:SetScript("OnUpdate", nil)
			end
			return
		end
	else
		checkElapsed = checkElapsed + elapsed
		if checkElapsed >= CHECK_INTERVAL then
			checkElapsed = 0
			local shouldHide = ShouldHide()
			if shouldHide and not wasHidden then
				wasHidden = true
				targetAlpha = 0
				FlightFade._hiding = true
			elseif not shouldHide and wasHidden then
				wasHidden = false
				targetAlpha = 1
				FlightFade.isActive = false
				FlightFade._hiding = false
				ApplyAlpha(1)
			end
		end
	end

	-- Smooth interpolation
	local fadeDuration = (settings and settings.fadeDuration) or FADE_DURATION
	if currentAlpha ~= targetAlpha then
		local speed = elapsed / fadeDuration
		local diff = targetAlpha - currentAlpha
		if abs(diff) <= speed then
			currentAlpha = targetAlpha
		else
			currentAlpha = currentAlpha + (diff > 0 and speed or -speed)
		end
		ApplyAlpha(currentAlpha)
		if currentAlpha == 0 then
			FlightFade.isActive = true
		end
	end
end

-- ============================================================
-- PUBLIC METHODS
-- ============================================================

function FlightFade:Initialize(dbSettings)
	settings = dbSettings
	if AnyEnabled() then
		self:EnsureOnUpdate()
	end
end

function FlightFade:EnsureOnUpdate()
	if not onUpdateFrame then
		onUpdateFrame = CreateFrame("Frame")
	end
	onUpdateFrame:SetScript("OnUpdate", OnUpdate)
end

function FlightFade:ForceShow()
	wasHidden = false
	currentAlpha = 1
	targetAlpha = 1
	FlightFade.isActive = false
	FlightFade._hiding = false
	ApplyAlpha(1)
	if onUpdateFrame then
		onUpdateFrame:SetScript("OnUpdate", nil)
	end
end
