--[[
	ddingUI UnitFrames
	Modules/MyBuffIndicators.lua - 내 버프 인디케이터

	내가 시전한 버프가 대상에 적용된 경우 그라디언트 오버레이로 표시
	힐러가 HoT 추적할 때 유용
]]

local _, ns = ...

local MyBuffIndicators = {}
ns.MyBuffIndicators = MyBuffIndicators

local C_UnitAuras = C_UnitAuras
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local oUF = ns.oUF

-----------------------------------------------
-- 추적할 버프 목록 (spellID → 색상)
-- 비어있으면 모든 내 버프 표시
-----------------------------------------------
local trackedBuffs = {}

-----------------------------------------------
-- 인디케이터 생성/관리
-----------------------------------------------

local function GetOrCreateIndicator(frame, index)
	if not frame._myBuffIndicators then
		frame._myBuffIndicators = {}
	end

	local indicator = frame._myBuffIndicators[index]
	if indicator then return indicator end

	-- 프레임 하단에 작은 색상 바 형태
	local bar = frame.Health:CreateTexture(nil, "OVERLAY", nil, 2)
	bar:SetHeight(3)
	bar:Hide()
	frame._myBuffIndicators[index] = bar

	return bar
end

local function HideAllIndicators(frame)
	if not frame._myBuffIndicators then return end
	for _, bar in pairs(frame._myBuffIndicators) do
		bar:Hide()
	end
end

-----------------------------------------------
-- 프레임 업데이트
-----------------------------------------------

local function UpdateFrame(frame)
	if not frame or not frame.Health then return end
	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		HideAllIndicators(frame)
		return
	end

	HideAllIndicators(frame)

	local db = ns.db and ns.db.myBuffIndicators
	if not db or not db.enabled then return end -- [FIX] nil == false는 false이므로 not db.enabled 사용

	local maxIndicators = db.maxIndicators or 3
	local barHeight = db.barHeight or 3
	local spacing = db.spacing or 1
	local position = db.position or "BOTTOM" -- BOTTOM or TOP

	local found = 0

	-- [12.0.1] AuraCache 우선 사용, 없으면 직접 스캔
	local helpfulAuras
	if ns.AuraCache then
		helpfulAuras = ns.AuraCache:GetHelpful(unit)
	end

	if helpfulAuras then
		-- 캐시에서 읽기
		for _, auraData in ipairs(helpfulAuras) do
			if found >= maxIndicators then break end

			local isMyBuff = false
			local isFromPlayer = auraData.isFromPlayerOrPlayerPet
			if isFromPlayer ~= nil and oUF:NotSecretValue(isFromPlayer) then
				isMyBuff = isFromPlayer
			elseif auraData.sourceUnit and oUF:NotSecretValue(auraData.sourceUnit) then
				isMyBuff = UnitIsUnit(auraData.sourceUnit, "player")
			end

			if isMyBuff then
				local spellID = auraData.spellId
				if spellID and not oUF:NotSecretValue(spellID) then
					spellID = nil
				end
				local showIt = true
				if next(trackedBuffs) and not trackedBuffs[spellID] then
					showIt = false
				end

				if showIt then
					found = found + 1
					local bar = GetOrCreateIndicator(frame, found)
					bar:SetHeight(barHeight)
					bar:ClearAllPoints()
					local barWidth = frame.Health:GetWidth() / maxIndicators - spacing
					if barWidth < 2 then barWidth = 2 end
					if position == "TOP" then
						bar:SetPoint("TOPLEFT", frame.Health, "TOPLEFT",
							(found - 1) * (barWidth + spacing), 0)
					else
						bar:SetPoint("BOTTOMLEFT", frame.Health, "BOTTOMLEFT",
							(found - 1) * (barWidth + spacing), 0)
					end
					bar:SetWidth(barWidth)
					local color
					if trackedBuffs[spellID] then
						color = trackedBuffs[spellID]
					elseif db.defaultColor then
						color = db.defaultColor
					else
						local _, class = UnitClass("player")
						local cc = RAID_CLASS_COLORS[class]
						if cc then
							color = { cc.r, cc.g, cc.b, 0.7 }
						else
							color = { 0.2, 0.8, 0.2, 0.7 }
						end
					end
					bar:SetColorTexture(color[1] or 0.2, color[2] or 0.8, color[3] or 0.2, color[4] or 0.7)
					bar:Show()
				end
			end
		end
	else
		-- 폴백: 직접 스캔
		local index = 1
		while found < maxIndicators do
			local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
			if not auraData then break end

			local isMyBuff = false
			local isFromPlayer = auraData.isFromPlayerOrPlayerPet
			if isFromPlayer ~= nil and oUF:NotSecretValue(isFromPlayer) then
				isMyBuff = isFromPlayer
			elseif auraData.sourceUnit and oUF:NotSecretValue(auraData.sourceUnit) then
				isMyBuff = UnitIsUnit(auraData.sourceUnit, "player")
			end

			if isMyBuff then
				local spellID = auraData.spellId
				if spellID and not oUF:NotSecretValue(spellID) then
					spellID = nil
				end
				local showIt = true
				if next(trackedBuffs) and not trackedBuffs[spellID] then
					showIt = false
				end

				if showIt then
					found = found + 1
					local bar = GetOrCreateIndicator(frame, found)
					bar:SetHeight(barHeight)
					bar:ClearAllPoints()
					local barWidth = frame.Health:GetWidth() / maxIndicators - spacing
					if barWidth < 2 then barWidth = 2 end
					if position == "TOP" then
						bar:SetPoint("TOPLEFT", frame.Health, "TOPLEFT",
							(found - 1) * (barWidth + spacing), 0)
					else
						bar:SetPoint("BOTTOMLEFT", frame.Health, "BOTTOMLEFT",
							(found - 1) * (barWidth + spacing), 0)
					end
					bar:SetWidth(barWidth)
					local color
					if trackedBuffs[spellID] then
						color = trackedBuffs[spellID]
					elseif db.defaultColor then
						color = db.defaultColor
					else
						local _, class = UnitClass("player")
						local cc = RAID_CLASS_COLORS[class]
						if cc then
							color = { cc.r, cc.g, cc.b, 0.7 }
						else
							color = { 0.2, 0.8, 0.2, 0.7 }
						end
					end
					bar:SetColorTexture(color[1] or 0.2, color[2] or 0.8, color[3] or 0.2, color[4] or 0.7)
					bar:Show()
				end
			end

			index = index + 1
		end
	end
end

-----------------------------------------------
-- 이벤트 처리
-----------------------------------------------

local eventFrame = CreateFrame("Frame")
local throttleTimers = {}

local function OnAuraChange(self, event, unit)
	if not unit then return end

	-- 쓰로틀: 같은 유닛 연속 업데이트 방지
	if throttleTimers[unit] then return end
	throttleTimers[unit] = true

	C_Timer.After(0.05, function()
		throttleTimers[unit] = nil

		-- 해당 유닛의 프레임 찾기
		if ns.frames then
			for _, frame in pairs(ns.frames) do
				if frame.unit == unit then
					UpdateFrame(frame)
				end
			end
		end

		-- 파티/레이드 프레임 -- [PERF] GetChildren() 1회만 호출
		if ns.headers then
			local party = ns.headers.party
			if party then
				local children = { party:GetChildren() }
				for _, child in ipairs(children) do
					if child and child.unit == unit then
						UpdateFrame(child)
					end
				end
			end

			for g = 1, 8 do
				local header = ns.headers["raid_group" .. g]
				if header then
					local children = { header:GetChildren() }
					for _, child in ipairs(children) do
						if child and child.unit == unit then
							UpdateFrame(child)
						end
					end
				end
			end
		end
	end)
end

-----------------------------------------------
-- Public API
-----------------------------------------------

function MyBuffIndicators:Enable()
	eventFrame:RegisterEvent("UNIT_AURA")
	eventFrame:SetScript("OnEvent", OnAuraChange)
end

function MyBuffIndicators:Disable()
	eventFrame:UnregisterAllEvents()
	eventFrame:SetScript("OnEvent", nil)

	-- 모든 인디케이터 숨기기
	if ns.frames then
		for _, frame in pairs(ns.frames) do
			HideAllIndicators(frame)
		end
	end
end

function MyBuffIndicators:ForceUpdateAll()
	if ns.frames then
		for _, frame in pairs(ns.frames) do
			UpdateFrame(frame)
		end
	end
end

function MyBuffIndicators:Initialize()
	local db = ns.db and ns.db.myBuffIndicators
	if not db or not db.enabled then return end -- [FIX] nil == false는 false이므로 not db.enabled 사용

	-- 추적 버프 로드
	if db.trackedSpells then
		wipe(trackedBuffs)
		for spellID, color in pairs(db.trackedSpells) do
			trackedBuffs[spellID] = color
		end
	end

	self:Enable()
end
