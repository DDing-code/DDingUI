--[[
	ddingUI UnitFrames
	Units/Layout.lua - Cell-inspired minimal modern style

	Config.lua 데이터 구조 기준:
	- 크기: settings.size = { width, height }
	- 체력: flat (healthBarColorType, healthBarColor, etc.)
	- 위젯: settings.widgets.powerBar, settings.widgets.castBar, etc.
	- 위젯 크기: settings.widgets.xxx.size = { width = n, height = n }
]]

local _, ns = ...
local oUF = ns.oUF

local Layout = {}
ns.Layout = Layout

local F = ns.Functions
local C = ns.Constants

-----------------------------------------------
-- API Upvalue Caching
-----------------------------------------------

local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitIsUnit = UnitIsUnit
local UnitHealth = UnitHealth           -- [12.0.1]
local UnitHealthMax = UnitHealthMax     -- [12.0.1]
local issecretvalue = issecretvalue     -- [12.0.1]
local SafeVal = ns.SafeVal              -- [12.0.1] secret → nil 변환
local SafeNum = ns.SafeNum              -- [12.0.1] secret → 0 변환
local unpack = unpack
local select = select
local math_max = math.max

-----------------------------------------------
-- Shared Media Helper
-- [FIX] LSM 표시이름("기본 글꼴","Melli") → 파일 경로 변환
-----------------------------------------------

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local function ResolveLSM(mediaType, val, fallback)
	if not val then return fallback end
	-- 파일 경로(\, / 포함)면 그대로 사용
	if val:find("[/\\]") then return val end
	-- LSM 이름이면 경로로 변환
	if LSM then
		local resolved = LSM:Fetch(mediaType, val)
		if resolved then return resolved end
	end
	return fallback
end

local function GetTexture()
	local raw = ns.db and ns.db.media and ns.db.media.texture or C.FLAT_TEXTURE
	return ResolveLSM("statusbar", raw, C.FLAT_TEXTURE)
end

local function GetFont()
	local db = ns.db and ns.db.media or {}
	local fontPath = ResolveLSM("font", db.font, C.DEFAULT_FONT)
	return fontPath,
		   db.fontSize or C.DEFAULT_FONT_SIZE,
		   db.fontFlags or C.DEFAULT_FONT_FLAGS
end

-- [12.0.1] SetFont 안전 래퍼: 폰트 경로 무효 시 폴백
local FALLBACK_FONT = C.DEFAULT_FONT or "Fonts\\FRIZQT__.TTF"
local function SafeSetFont(fontString, font, size, flags)
	if not fontString then return false end
	size = size or 11
	flags = flags or "OUTLINE"
	local success = fontString:SetFont(font or FALLBACK_FONT, size, flags)
	if not success then
		fontString:SetFont(FALLBACK_FONT, size, flags)
	end
	return true
end

-- 위젯 설정 안전 접근
local function GetWidgetSettings(settings, widgetName)
	return settings and settings.widgets and settings.widgets[widgetName]
end

-- [12.0.1] 구 태그 → ddingui: 태그 자동 마이그레이션 -- [FIX] 스마트 폴백 추가
-- 명시적 매핑 (단축명 → ddingui: 풀네임이 다른 경우만)
local OLD_TO_NEW_TAGS = {
	["name"]           = "ddingui:name:medium",
	["health:percent"] = "ddingui:health:percent",
	["health:current"] = "ddingui:health:current",
	["power:current"]  = "ddingui:power",
	["power:percent"]  = "ddingui:power:percent",
	["level"]          = "ddingui:level",
	["class"]          = "ddingui:classification",
	["status"]         = "ddingui:status",
}

local function MigrateTagString(tagString)
	if not tagString or tagString == "" then return tagString end
	local methods = oUF and oUF.Tags and oUF.Tags.Methods
	return tagString:gsub("%[([^%]]+)%]", function(inner)
		-- 1) 이미 등록된 태그 → 그대로
		if methods and methods[inner] then return "[" .. inner .. "]" end
		-- 2) 명시적 매핑 테이블
		local explicit = OLD_TO_NEW_TAGS[inner]
		if explicit then return "[" .. explicit .. "]" end
		-- 3) ddingui: 프리픽스 자동 폴백 -- [FIX]
		if methods and not inner:find("^ddingui:") then
			local prefixed = "ddingui:" .. inner
			if methods[prefixed] then return "[" .. prefixed .. "]" end
		end
		-- 4) 알 수 없는 태그 → 그대로 (oUF 내장 태그일 수 있음)
		return "[" .. inner .. "]"
	end)
end
ns.MigrateTagString = MigrateTagString

-- [12.0.1] 커스텀 태그 유효성 검증: 등록되지 않은 태그 포함 시 false
local function IsValidCustomTag(tagString)
	if not tagString or tagString == "" then return false end
	-- 마이그레이션 적용 후 검증
	local migrated = MigrateTagString(tagString)
	for tag in migrated:gmatch("%[([^%]]+)%]") do
		if not oUF.Tags.Methods[tag] then
			return false
		end
	end
	return true
end
ns.IsValidCustomTag = IsValidCustomTag

-----------------------------------------------
-- Create Pixel-Perfect Backdrop (수동 텍스처 방식)
-- WoW Backdrop edgeFile은 특정 edgeSize에서 흰색 아티팩트 발생
-- → bgFile만 사용 + 4개 수동 텍스처로 테두리 생성
-----------------------------------------------

local function CreateFrameBackdrop(self)
	local borderSize = F:ScalePixel(C.BORDER_SIZE)

	local bd = CreateFrame("Frame", nil, self)
	bd:SetPoint("TOPLEFT", -borderSize, borderSize)
	bd:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
	bd:SetFrameLevel(math_max(0, self:GetFrameLevel() - 1))

	-- 배경 (중앙 영역) - SetColorTexture로 확실한 색상 적용
	local bgR, bgG, bgB, bgA = unpack(C.FRAME_BG)
	bd.bg = bd:CreateTexture(nil, "BACKGROUND")
	bd.bg:SetPoint("TOPLEFT", borderSize, -borderSize)
	bd.bg:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
	bd.bg:SetColorTexture(bgR, bgG, bgB, bgA)

	-- 수동 테두리 텍스처 4개 (edgeFile 대체)
	local r, g, b, a = unpack(C.BORDER_COLOR)

	local top = bd:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", 0, 0)
	top:SetHeight(borderSize)
	top:SetColorTexture(r, g, b, a)

	local bottom = bd:CreateTexture(nil, "BORDER")
	bottom:SetPoint("BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", 0, 0)
	bottom:SetHeight(borderSize)
	bottom:SetColorTexture(r, g, b, a)

	local left = bd:CreateTexture(nil, "BORDER")
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(borderSize)
	left:SetColorTexture(r, g, b, a)

	local right = bd:CreateTexture(nil, "BORDER")
	right:SetPoint("TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", 0, 0)
	right:SetWidth(borderSize)
	right:SetColorTexture(r, g, b, a)

	bd.borderTextures = { top, bottom, left, right }

	self.Backdrop = bd
	return bd
end

-----------------------------------------------
-- Create Health Bar
-- Config: 체력 설정은 유닛 레벨 flat, 기력바는 widgets.powerBar
-----------------------------------------------

local function CreateHealthBar(self, unit, settings)
	local texture = GetTexture()

	-- 기력바 높이 계산 (체력바 하단 여백)
	-- [12.0.1] 분리형 파워바: anchorToParent == false면 체력바가 전체 높이 사용
	local powerDB = GetWidgetSettings(settings, "powerBar")
	local powerH = 0
	if powerDB and powerDB.enabled ~= false and powerDB.anchorToParent ~= false then
		powerH = (powerDB.size and powerDB.size.height) or C.POWER_HEIGHT
	end

	local inset = 0

	local health = CreateFrame("StatusBar", nil, self)
	health:SetStatusBarTexture(texture)
	health:SetPoint("TOPLEFT", self, "TOPLEFT", inset, -inset)
	health:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -inset, inset + powerH)

	-- [FIX] 초기 색상 설정 (oUF UpdateColor 전 흰/핑크 바 방지)
	health:SetStatusBarColor(0.2, 0.2, 0.2)

	-- Background (darkened class color)
	health.bg = health:CreateTexture(nil, "BACKGROUND")
	health.bg:SetAllPoints()
	health.bg:SetTexture(texture)
	health.bg.multiplier = C.HEALTH_BG_MULTIPLIER
	health.bg:SetVertexColor(0.1, 0.1, 0.1) -- [FIX] 초기 bg 색상

	-- oUF 색상 모드 설정
	local colorType = settings and settings.healthBarColorType or "class"
	if colorType == "custom" then
		local cc = settings.healthBarColor
		if cc then
			health:SetStatusBarColor(cc[1], cc[2], cc[3])
			if health.bg then
				local mu = health.bg.multiplier or C.HEALTH_BG_MULTIPLIER or 0.3
				health.bg:SetVertexColor(cc[1] * mu, cc[2] * mu, cc[3] * mu)
			end
		end
		health.colorClass = false
		health.colorReaction = false
		health.colorSmooth = false
	elseif colorType == "smooth" then
		-- [12.0.1] oUF colorSmooth: UnitHealthPercent + ColorCurve 기반 그라디언트
		health.colorSmooth = true
		health.colorClass = false
		health.colorReaction = false
		health.colorHealth = true -- 폴백: ColorCurve 없는 환경용
	else
		-- class / reaction
		health.colorClass = (colorType == "class")
		health.colorReaction = (colorType == "reaction" or colorType == "class")
		health.colorHealth = true -- 최종 폴백: 종류 없는 유닛용
		health.colorSmooth = false
	end

	-- [ElvUI 패턴] PostUpdateColor: oUF 색상 적용 후 SetStatusBarColor로 동기화
	health.PostUpdateColor = function(element, unit, color)
		if unit and UnitExists(unit) then
			if UnitIsDeadOrGhost(unit) then
				local app = ns.db and ns.db.appearance
				if app and app.deadDesaturate then return end
			end
		end

		local r, g, b
		if color then
			local ok
			ok, r, g, b = pcall(color.GetRGB, color)
			if not ok then r, g, b = nil, nil, nil end
		end

		if not r then
			local owner = element.__owner
			if not owner then return end
			local unitKey = owner._unitKey or (unit and unit:gsub("%d+$", "") or "player")
			local udb = ns.db and ns.db[unitKey]
			if udb and udb.healthBarColorType == "custom" and udb.healthBarColor then
				r, g, b = unpack(udb.healthBarColor)
			elseif unit then
				local reaction = UnitReaction(unit, "player")
				if reaction then
					local fc = FACTION_BAR_COLORS[reaction]
					if fc then r, g, b = fc.r, fc.g, fc.b end
				end
				if not r then
					local _, class = UnitClass(unit)
					local cc = class and RAID_CLASS_COLORS[class]
					if cc then
						r, g, b = cc.r, cc.g, cc.b
					else
						r, g, b = 49/255, 207/255, 37/255
					end
				end
			else
				r, g, b = 49/255, 207/255, 37/255
			end
		end

		element:SetStatusBarColor(r, g, b)

		if element.bg and not element.bg._customColor then
			local mu = element.bg.multiplier or C.HEALTH_BG_MULTIPLIER or 0.3
			element.bg:SetVertexColor(r * mu, g * mu, b * mu)
		end
	end

	-- [FIX] 미적용 옵션 연결: reverseHealthFill
	if settings and settings.reverseHealthFill then
		health:SetReverseFill(true)
	end

	-- 공식 oUF: smoothing은 Enum.StatusBarInterpolation 값이어야 함
	if ns.db and ns.db.smoothBars ~= false then
		health.smoothing = Enum.StatusBarInterpolation.Linear
	end

	-- [ElvUI 패턴] PostUpdate: 텍스트는 oUF Tag가 처리, 여기선 외형만
	health.PostUpdate = function(element, unit, cur, max, lossPerc)
		local owner = element.__owner
		if element._threatOverride then return end
		if ns.Update and ns.Update.UpdateAppearance then
			ns.Update:UpdateAppearance(owner, unit)
		end
	end

	self.Health = health
	return health
end

-----------------------------------------------
-- Create Power Bar (thin strip at bottom / detachable)
-- Config: settings.widgets.powerBar
-- [12.0.1] anchorToParent == false면 분리 모드 (캐스트바 패턴)
-----------------------------------------------

local function CreatePowerBar(self, unit, settings)
	local pDB = GetWidgetSettings(settings, "powerBar")
	if not pDB then return nil end  -- [12.0.1] pDB 자체가 없으면 skip (위젯 정의 없음)

	local texture = GetTexture()
	local powerH = (pDB.size and pDB.size.height) or C.POWER_HEIGHT
	local inset = 0

	local power = CreateFrame("StatusBar", nil, self)
	power:SetStatusBarTexture(texture)
	power:SetStatusBarColor(0.2, 0.2, 0.6) -- [FIX] 초기 색상 (oUF UpdateColor 전 핑크 바 방지)

	-- [12.0.1] 분리/부착 모드
	if not pDB.anchorToParent and pDB.detachedPosition then
		local pos = pDB.detachedPosition
		local w = (pDB.size and pDB.size.width) or self:GetWidth()
		power:SetParent(UIParent)  -- [12.0.1] UIParent로 부모 변경 (strata 독립)
		power:SetSize(w, powerH)
		power:SetPoint(
			pos.point or "BOTTOM",
			self,  -- [FIX] 앵커는 주인 프레임 (UIParent가 아닌 유닛프레임 기준 배치)
			pos.relativePoint or "BOTTOM",
			pos.offsetX or 0,
			pos.offsetY or 0
		)
		-- 분리형 백드롭 -- [12.0.1] explicit size로 taint 방지
		F:CreateBackdrop(power, nil, nil, w, powerH)
		self._powerDetached = true  -- [12.0.1] 분리 상태 플래그
	else
		-- 기존 부착 모드
		power:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", inset, inset)
		power:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -inset, inset)
		power:SetHeight(powerH)
		self._powerDetached = false
	end

	-- Background
	power.bg = power:CreateTexture(nil, "BACKGROUND")
	power.bg:SetAllPoints()
	power.bg:SetTexture(texture)
	power.bg:SetVertexColor(0.06, 0.06, 0.06) -- [FIX] 초기 bg 색상 (기본 white 방지)
	power.bg.multiplier = 0.3

	-- Coloring
	power.colorPower = pDB.colorPower ~= false
	power.colorClass = pDB.colorClass == true
	power.frequentUpdates = (unit == "player")
	-- [FIX] colorPower/colorClass 둘 다 아닐 때 customColor 적용
	if not power.colorPower and not power.colorClass and pDB.customColor then
		power:SetStatusBarColor(unpack(pDB.customColor))
	end

	-- [FIX] PostUpdateColor: oUF 색상 적용 후 SetStatusBarColor 동기화 + bg 색상 (핑크바 방지)
	power.PostUpdateColor = function(element, unit, color, altR, altG, altB)
		local r, g, b
		if altR and altG and altB then
			r, g, b = altR, altG, altB
		elseif color then
			local ok
			ok, r, g, b = pcall(color.GetRGB, color)
			if not ok then r, g, b = 0.2, 0.2, 0.6 end
		else
			r, g, b = 0.2, 0.2, 0.6 -- 기본 파란색 폴백
		end
		element:SetStatusBarColor(r, g, b)
		if element.bg then
			local mu = element.bg.multiplier or 0.3
			element.bg:SetVertexColor(r * mu, g * mu, b * mu)
		end
	end

	-- [ElvUI 패턴] PostUpdate: 기력바 표시/숨김 + 체력바 높이 조정
	power._storedHeight = powerH -- 체력바 조정용
	power.PostUpdate = function(element, unit, cur, min, max)
		local owner = element.__owner
		local bd = element.backdrop
		local shouldHide = not unit or not UnitExists(unit)

		if not shouldHide then
			if not max then
				shouldHide = true
			elseif issecretvalue and issecretvalue(max) then
				shouldHide = true -- [12.0.1] secret → 숨김 (closure 제거)
			else
				local isZero = (max == 0)
				if isZero then
					shouldHide = true
				elseif false then -- (이전 pcall 에러 분기 제거)
					shouldHide = true
				end
			end
		end

		if shouldHide then
			element:Hide()
			if bd then bd:Hide() end
			if owner and owner.Health and not owner._powerDetached then
				owner.Health:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
			end
		else
			element:Show()
			if bd then bd:Show() end
			if owner and owner.Health and not owner._powerDetached then
				owner.Health:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, element._storedHeight or 0)
			end
		end
	end

	-- [FIX] enabled == false면 oUF에 등록하지 않음 (oUF Enable에서 Show() 호출 방지)
	if pDB.enabled == false then
		power:Hide()
		self._powerFrame = power -- 참조만 보관 (나중에 EnableElement 가능)
	else
		self.Power = power
	end

	-- [12.0.1] 분리형 파워바: 유닛 프레임 Hide 시 같이 숨기기 (parent가 UIParent라 자동 안됨)
	if self._powerDetached then
		local pow = power
		self:HookScript("OnHide", function()
			pow:Hide()
			if pow.backdrop then pow.backdrop:Hide() end
		end)
	end

	return power
end

-----------------------------------------------
-- 스타일 헬퍼: 보조 자원바 공통 백드롭/배경 생성
-----------------------------------------------

local function StyleAltBar(bar, texture)
	-- 백드롭 (테두리 + 배경) -- [REFACTOR]
	local bd = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	bd:SetPoint("TOPLEFT", -1, 1)
	bd:SetPoint("BOTTOMRIGHT", 1, -1)
	bd:SetFrameLevel(math_max(0, bar:GetFrameLevel() - 1))
	bd:SetBackdrop({
		bgFile = C.FLAT_TEXTURE,
		edgeFile = C.FLAT_TEXTURE,
		edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	bd:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
	bd:SetBackdropBorderColor(unpack(C.BORDER_COLOR))
	bar.Backdrop = bd

	-- Background
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetTexture(texture)
	bar.bg.multiplier = 0.3
end

-----------------------------------------------
-- Create Alt Power Bar (대체 자원바 - 보스전 등)
-- Config: settings.widgets.altPowerBar
-- [REFACTOR] AlternativePower (보스전 대체 자원바)
-----------------------------------------------

local function CreateAltPowerBar(self, unit, settings)
	local apDB = GetWidgetSettings(settings, "altPowerBar")
	if not apDB then return nil end

	local texture = GetTexture()
	local apH = (apDB.size and apDB.size.height) or 4
	local apW = (apDB.size and apDB.size.width) or self:GetWidth()

	local altPower = CreateFrame("StatusBar", nil, self)
	altPower:SetStatusBarTexture(texture)
	altPower:SetSize(apW, apH)
	altPower:SetFrameLevel(self:GetFrameLevel() + (apDB.frameLevel or 10))

	-- 위치 설정
	local pos = apDB.position
	altPower:SetPoint(
		pos and pos.point or "TOP",
		self,
		pos and pos.relativePoint or "TOP",
		pos and pos.offsetX or 0,
		pos and pos.offsetY or 0
	)

	StyleAltBar(altPower, texture)

	if apDB.enabled == false then
		altPower:Hide()
		self._altPowerFrame = altPower
	else
		self.AlternativePower = altPower -- oUF AlternativePower element
	end

	return altPower
end

-----------------------------------------------
-- Create Additional Power Bar (보조 자원바 - 드루이드 마나 등)
-- [REFACTOR] AdditionalPower (드루이드 마나 등)
-- player 전용: 변신 시 기본 자원(마나) 표시
-----------------------------------------------

local function CreateAdditionalPower(self, unit, settings)
	local texture = GetTexture()
	local inset = 0

	local addPower = CreateFrame("StatusBar", nil, self)
	addPower:SetStatusBarTexture(texture)
	addPower:SetFrameLevel(self:GetFrameLevel() + 3) -- 텍스트보다 낮게
	-- 체력바와 파워바 사이에 얇은 바 (이름 가림 방지) -- [REFACTOR]
	if self.Power then
		addPower:SetPoint("BOTTOMLEFT", self.Power, "TOPLEFT", 0, 0)
		addPower:SetPoint("BOTTOMRIGHT", self.Power, "TOPRIGHT", 0, 0)
	else
		addPower:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", inset, inset)
		addPower:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -inset, inset)
	end
	addPower:SetHeight(4)

	StyleAltBar(addPower, texture)

	addPower.colorPower = true
	addPower.frequentUpdates = true
	local apDB = GetWidgetSettings(settings, "altPowerBar")
	if apDB and apDB.enabled == false then
		addPower:Hide()
		self._additionalPowerFrame = addPower
	else
		self.AdditionalPower = addPower
	end
	return addPower
end

-----------------------------------------------
-- Create Castbar
-- Config: settings.widgets.castBar
-----------------------------------------------

local function CreateCastbar(self, unit, cbDB, ownerWidth)
	if not cbDB then return nil end  -- [12.0.1] cbDB 존재하면 항상 생성 (disabled면 Hide)

	local texture = GetTexture()
	local font, fontSize, fontFlags = GetFont()

	local castbar = CreateFrame("StatusBar", nil, self)
	-- [FIX] 미적용 옵션 연결: castBar-specific texture
	if cbDB.texture then
		local cbTex = cbDB.texture
		if type(cbTex) == "string" and cbTex:find("[/\\]") then
			castbar:SetStatusBarTexture(cbTex)
		else
			castbar:SetStatusBarTexture(texture)
		end
	else
		castbar:SetStatusBarTexture(texture)
	end
	-- [FIX] 미적용 옵션 연결: castBar initial color from Config
	local initColor = (cbDB.colors and cbDB.colors.interruptible) or C.CASTBAR_COLOR
	castbar:SetStatusBarColor(unpack(initColor))

	local cbHeight = (cbDB.size and cbDB.size.height) or 20
	local cbWidth  -- [12.0.1] Backdrop explicit size용 (아이콘 포함 전체 너비)

	-- [FIX] self:GetWidth() → ownerWidth 사용 (secure frame의 secret number 방지)
	local fallbackW = ownerWidth or 200

	-- [REFACTOR] 아이콘 위치를 사이징 전에 결정 (inside 모드에서 바/아이콘 영역 물리 분리)
	local iconPos = cbDB.icon and cbDB.icon.position or "inside-left"
	local iconW = 0
	if iconPos == "inside-left" or iconPos == "inside-right" then
		iconW = cbHeight -- 정사각형 아이콘
	end

	-- 분리/부착 모드
	if not cbDB.anchorToParent and cbDB.detachedPosition then
		local pos = cbDB.detachedPosition
		cbWidth = (cbDB.size and cbDB.size.width) or fallbackW
		castbar:SetSize(cbWidth - iconW, cbHeight)
		-- inside 모드: 아이콘+바 전체 영역이 사용자 지정 위치의 중심에 오도록 보정
		local adjOX = pos.offsetX or 0
		if iconPos == "inside-left" then adjOX = adjOX + iconW / 2 end
		if iconPos == "inside-right" then adjOX = adjOX - iconW / 2 end
		castbar:SetPoint(
			pos.point or "CENTER",
			self,  -- [FIX] 앵커는 주인 프레임 (UIParent가 아닌 유닛프레임 기준 배치)
			pos.relativePoint or "CENTER",
			adjOX,
			pos.offsetY or 0
		)
	else
		local gap = 2 -- [REFACTOR] raw pixel
		cbWidth = fallbackW -- [REFACTOR] 부착형: 항상 부모 너비 사용
		castbar:SetHeight(cbHeight)
		local leftOff = iconPos == "inside-left" and iconW or 0
		local rightOff = iconPos == "inside-right" and -iconW or 0
		castbar:SetPoint("TOPLEFT", self, "BOTTOMLEFT", leftOff, -gap)
		castbar:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", rightOff, -gap)
	end

	-- Backdrop (수동 텍스처 - BackdropTemplate 사용 금지: party/raid secure frame의 OnSizeChanged에서 secret number 크래시)
	do
		local borderSize = F:ScalePixel(C.BORDER_SIZE)
		local bd = CreateFrame("Frame", nil, castbar)
		-- [12.0.1] explicit size: secure frame taint 방지
		-- cbWidth = 전체 너비 (아이콘 포함), castbar는 바 영역만
		bd:SetSize(cbWidth + 2 * borderSize, cbHeight + 2 * borderSize)
		if iconPos == "inside-left" then
			bd:SetPoint("TOPRIGHT", castbar, "TOPRIGHT", borderSize, borderSize)
		elseif iconPos == "inside-right" then
			bd:SetPoint("TOPLEFT", castbar, "TOPLEFT", -borderSize, borderSize)
		else
			bd:SetPoint("CENTER", castbar, "CENTER", 0, 0)
		end
		bd:SetFrameLevel(math_max(0, castbar:GetFrameLevel() - 1))

		local bgR, bgG, bgB, bgA = unpack(C.FRAME_BG)
		bd.bg = bd:CreateTexture(nil, "BACKGROUND")
		bd.bg:SetPoint("TOPLEFT", borderSize, -borderSize)
		bd.bg:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
		bd.bg:SetColorTexture(bgR, bgG, bgB, bgA)

		local r, g, b, a = unpack(C.BORDER_COLOR)
		local top = bd:CreateTexture(nil, "BORDER")
		top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0)
		top:SetHeight(borderSize); top:SetColorTexture(r, g, b, a)
		local bottom = bd:CreateTexture(nil, "BORDER")
		bottom:SetPoint("BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", 0, 0)
		bottom:SetHeight(borderSize); bottom:SetColorTexture(r, g, b, a)
		local left = bd:CreateTexture(nil, "BORDER")
		left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", 0, 0)
		left:SetWidth(borderSize); left:SetColorTexture(r, g, b, a)
		local right = bd:CreateTexture(nil, "BORDER")
		right:SetPoint("TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
		right:SetWidth(borderSize); right:SetColorTexture(r, g, b, a)

		bd.borderTextures = { top, bottom, left, right }
		castbar.backdrop = bd
	end

	-- Background
	castbar.bg = castbar:CreateTexture(nil, "BACKGROUND")
	castbar.bg:SetAllPoints()
	castbar.bg:SetTexture(texture)
	castbar.bg:SetVertexColor(0.08, 0.08, 0.08)

	-- Icon -- [REFACTOR] inside 모드: 아이콘은 바 바깥, backdrop 안쪽에 배치
	local icon = castbar:CreateTexture(nil, "OVERLAY")
	icon:SetSize(cbHeight, cbHeight)
	icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
	-- iconPos는 사이징 전에 이미 결정됨
	if iconPos == "right" then
		icon:SetPoint("LEFT", castbar, "RIGHT", 3, 0)
	elseif iconPos == "inside-right" then
		icon:SetPoint("LEFT", castbar, "RIGHT", 0, 0) -- 바 오른쪽 바깥에 붙임
	elseif iconPos == "none" then
		icon:Hide()
	elseif iconPos == "inside-left" then
		icon:SetPoint("RIGHT", castbar, "LEFT", 0, 0) -- 바 왼쪽 바깥에 붙임
	else -- "left" (외부 좌측)
		icon:SetPoint("RIGHT", castbar, "LEFT", -3, 0)
	end
	castbar.Icon = icon
	castbar._iconPos = iconPos

	-- Icon border: backdrop이 아이콘 영역까지 커버하므로 별도 테두리 불필요

	-- Text -- [REFACTOR] 아이콘이 바 바깥이므로 텍스트는 항상 바 시작점 기준
	castbar.Text = castbar:CreateFontString(nil, "OVERLAY")
	castbar.Text:SetFont(font, fontSize - 1, fontFlags)
	castbar.Text:SetPoint("LEFT", castbar, 4, 0)
	castbar.Text:SetPoint("RIGHT", castbar, -40, 0)
	castbar.Text:SetJustifyH("LEFT")
	castbar.Text:SetWordWrap(false)

	-- Time -- [REFACTOR] 아이콘이 바 바깥이므로 시간은 항상 바 끝점 기준
	castbar.Time = castbar:CreateFontString(nil, "OVERLAY")
	castbar.Time:SetFont(font, fontSize - 1, fontFlags)
	castbar.Time:SetPoint("RIGHT", castbar, -4, 0)
	castbar.Time:SetJustifyH("RIGHT")

	-- CustomTimeText -- [REFACTOR] 시전바 Timer 포맷 옵션
	local timerDB = cbDB.timer
	local timerFmt = (timerDB and timerDB.format) or "remaining"
	castbar._timerFormat = timerFmt
	castbar.CustomTimeText = function(cb, durationObj)
		-- [12.0.1] DurationObject API 사용 (secret-safe C++ 메서드)
		-- GetRemainingDuration / GetDuration / GetElapsedDuration 모두 secret number 내부 처리
		if not durationObj then return end
		local remaining = durationObj:GetRemainingDuration()
		local total = durationObj.GetDuration and durationObj:GetDuration() or cb._totalDuration
		local elapsed = durationObj.GetElapsedDuration and durationObj:GetElapsedDuration()
		local fmt = cb._timerFormat or "remaining"
		if fmt == "remaining/total" and total then
			cb.Time:SetFormattedText("%.1f / %.1f", remaining, total)
		elseif fmt == "elapsed/total" and total and elapsed then
			cb.Time:SetFormattedText("%.1f / %.1f", elapsed, total)
		elseif fmt == "elapsed" and elapsed then
			cb.Time:SetFormattedText("%.1f", elapsed)
		elseif fmt == "total" and total then
			cb.Time:SetFormattedText("%.1f", total)
		else
			cb.Time:SetFormattedText("%.1f", remaining)
		end
	end

	-- Spark -- [FIX] 미적용 옵션 연결: spark width/color from Config
	local sparkDB = cbDB.spark
	local sparkW = (sparkDB and sparkDB.width) or 2
	local sparkColor = (sparkDB and sparkDB.color) or { 1, 1, 1, 0.8 }
	castbar.Spark = castbar:CreateTexture(nil, "OVERLAY")
	castbar.Spark:SetSize(sparkW, cbHeight)
	castbar.Spark:SetTexture(C.FLAT_TEXTURE)
	castbar.Spark:SetVertexColor(unpack(sparkColor))

	-- SafeZone (latency indicator) - player only
	if unit == "player" then
		local safeZone = castbar:CreateTexture(nil, "OVERLAY", nil, 1)
		safeZone:SetTexture(C.FLAT_TEXTURE)
		safeZone:SetVertexColor(0.85, 0.20, 0.20, 0.50)
		castbar.SafeZone = safeZone
	end

	-- Shield (non-interruptible indicator)
	-- [12.0.1] Hide() 대신 alpha=0 + Show() — oUF가 SetAlphaFromBoolean으로 alpha 제어
	-- Hide() 상태에서는 SetAlphaFromBoolean이 효과 없음 (보이지 않으므로)
	castbar.Shield = castbar:CreateTexture(nil, "OVERLAY", nil, 2)
	castbar.Shield:SetSize(14, 14)
	castbar.Shield:SetPoint("CENTER", icon, "CENTER", 0, 0)
	castbar.Shield:SetTexture([[Interface\CastingBar\UI-CastingBar-Small-Shield]])
	castbar.Shield:SetAlpha(0)

	-- Non-interruptible overlay (UnhaltedUF pattern)
	-- [12.0.1] alpha=0 + Show() — ApplyInterruptState에서 SetAlphaFromBoolean으로 제어
	local niOverlay = castbar:CreateTexture(nil, "OVERLAY", nil, 3)
	niOverlay:SetAllPoints()
	niOverlay:SetTexture(C.FLAT_TEXTURE)
	niOverlay:SetVertexColor(0.78, 0.25, 0.25, 1)
	niOverlay:SetAlpha(0)
	castbar.niOverlay = niOverlay

	-- Non-interruptible coloring + overlay
	-- [FIX] 글로벌 ns.Colors.castBar 우선, per-unit cbDB.colors fallback
	castbar._intColor = (ns.Colors and ns.Colors.castBar and ns.Colors.castBar.interruptible) or (cbDB.colors and cbDB.colors.interruptible) or C.CASTBAR_COLOR
	castbar._nonIntColor = (ns.Colors and ns.Colors.castBar and ns.Colors.castBar.nonInterruptible) or (cbDB.colors and cbDB.colors.nonInterruptible) or C.CASTBAR_NOINTERRUPT_COLOR

	-- [12.0.1] Secret boolean 안전한 차단 여부 표시 헬퍼
	-- Shield: oUF가 SetAlphaFromBoolean으로 처리 (alpha=1 보임 / alpha=0 안 보임)
	-- niOverlay: 우리가 SetAlphaFromBoolean으로 처리
	-- 색상: pcall로 secret boolean 방어
	local function ApplyInterruptState(cb)
		local ni = cb.notInterruptible
		-- niOverlay: SetAlphaFromBoolean (secret-safe C++ API)
		-- ni=true(차단 불가) → alpha=0.25 (오버레이 표시)
		-- ni=false(차단 가능) → alpha=0 (오버레이 숨김)
		if cb.niOverlay and cb.niOverlay.SetAlphaFromBoolean then
			cb.niOverlay:SetAlphaFromBoolean(ni, 0.25, 0)
		end
		-- [PERF] pcall+closure 제거: issecretvalue 체크로 secret boolean 방어
		local isNotInt = false
		if ni ~= nil then
			if issecretvalue and issecretvalue(ni) then
				isNotInt = true -- secret → 보수적으로 차단 불가 처리
			elseif ni then
				isNotInt = true
			end
		end
		if isNotInt then
			cb:SetStatusBarColor(unpack(cb._nonIntColor or C.CASTBAR_NOINTERRUPT_COLOR))
		else
			cb:SetStatusBarColor(unpack(cb._intColor or C.CASTBAR_COLOR))
		end
	end

	-- oUF Castbar PostCastStart 콜백
	castbar.PostCastStart = function(cb, u)
		-- [PERF] pcall+closure 제거: issecretvalue 체크로 secret number 방어
		local _, _, _, st, et = UnitCastingInfo(u)
		if st and et and not (issecretvalue and (issecretvalue(st) or issecretvalue(et))) then
			cb._totalDuration = (et - st) / 1000
		end
		ApplyInterruptState(cb)
	end
	castbar.PostChannelStart = function(cb, u)
		-- [PERF] pcall+closure 제거: issecretvalue 체크로 secret number 방어
		local _, _, _, st, et = UnitChannelInfo(u)
		if st and et and not (issecretvalue and (issecretvalue(st) or issecretvalue(et))) then
			cb._totalDuration = (et - st) / 1000
		end
		ApplyInterruptState(cb)
	end
	-- [12.0.1] 시전 중 차단 가능 여부 변경 시에도 갱신
	castbar.PostCastInterruptible = function(cb, u)
		ApplyInterruptState(cb)
	end

	castbar.timeToHold = cbDB.timeToHold or 0.5
	castbar.hideTradeSkills = true

	-- [12.0.1] disabled면 숨기기
	if cbDB.enabled == false then
		castbar:Hide()
		self._castbarFrame = castbar
	else
		self.Castbar = castbar -- oUF Castbar element
	end

	return castbar
end

-----------------------------------------------
-- Create Name Text
-----------------------------------------------

local function CreateNameText(self, unit, settings)
	local font, fontSize, fontFlags = GetFont()

	-- [FIX] 미적용 옵션 연결: Config font 설정 적용
	local nameDB = GetWidgetSettings(settings, "nameText")
	local nFont = nameDB and nameDB.font
	local nSize = (nFont and nFont.size) or fontSize
	local nOutline = (nFont and nFont.outline) or fontFlags
	local nStyle = (nFont and nFont.style) or font

	-- [FIX] TextOverlay에 생성하여 Power bar/Aura 프레임 위에 표시
	local textParent = self.TextOverlay or self.Health
	local name = textParent:CreateFontString(nil, "OVERLAY", nil, 6)
	name:SetFont(nStyle, nSize, nOutline)
	name:SetWordWrap(false) -- [FIX] 한 줄 강제 (긴 이름 줄바꿈 방지)
	name:SetNonSpaceWrap(false)
	name:SetMaxLines(1)

	-- [ESSENTIAL] 그림자 DB 설정 참조 (하드코딩 제거)
	local nameShadow = nameDB and nameDB.font and nameDB.font.shadow
	if nameShadow ~= false then -- nil(미설정) = 기본 켜짐
		name:SetShadowColor(0, 0, 0, 1)
		name:SetShadowOffset(1, -1)
	else
		name:SetShadowOffset(0, 0)
	end

	local baseUnit = unit:gsub("%d", "")
	local customTag = nameDB and nameDB.tag
	local hasCustomTag = customTag and customTag ~= "" and IsValidCustomTag(customTag) -- [12.0.1] 태그 검증

	-- [ElvUI 패턴] 포맷별 태그 문자열 결정 (우선순위: customTag > format > unit default)
	local nameFmt = nameDB and nameDB.format
	local nameTagMap = ns.NAME_FORMAT_TO_TAG
	local nameTagStr = nil
	if hasCustomTag then
		nameTagStr = customTag
	elseif nameFmt and nameTagMap and nameTagMap[nameFmt] then
		nameTagStr = nameTagMap[nameFmt]
	end

	-- 유닛별 기본 태그: 풀네임, 레이아웃 앵커가 잘림 처리
	local defaultTag = "[ddingui:classcolor][ddingui:name]|r"
	local finalTag = nameTagStr or defaultTag

	-- [FIX] 색상 타입에 따른 태그 프리픽스 (NAME_FORMAT_TO_TAG에 classcolor 내장)
	local nameColorType = nameDB and nameDB.color and nameDB.color.type or "class_color"
	if nameColorType == "class_color" then
		-- 기본: classcolor 이미 포함. 누락 시 추가
		if finalTag and not finalTag:find("ddingui:classcolor", 1, true) then
			finalTag = "[ddingui:classcolor]" .. finalTag .. "|r"
		end
	elseif nameColorType == "reaction_color" then
		finalTag = finalTag:gsub("%[ddingui:classcolor%]", "[ddingui:reactioncolor]")
	elseif nameColorType == "power_color" then
		finalTag = finalTag:gsub("%[ddingui:classcolor%]", "[ddingui:powercolor]")
	elseif nameColorType == "custom" then
		-- 커스텀 색상: 태그 색상 제거 (SetTextColor로 처리)
		finalTag = finalTag:gsub("%[ddingui:classcolor%]", "")
		finalTag = finalTag:gsub("|r$", "")
	end
	-- [FIX] showLevel 옵션: 이름 앞에 레벨 표시 삽입/제거
	if nameDB and nameDB.showLevel then
		if finalTag and not finalTag:find("ddingui:level:smart", 1, true) then
			finalTag = finalTag:gsub("%[ddingui:classcolor%]", "[ddingui:classcolor][ddingui:level:smart] ", 1)
		end
	else
		if finalTag then
			finalTag = finalTag:gsub("%[ddingui:level:smart%] ?", "")
			finalTag = finalTag:gsub("%[ddingui:level%] ?", "")
		end
	end

	-- [FIX] 미적용 옵션 연결: position from Config (healthText/powerText와 동일 패턴)
	if nameDB and nameDB.position then
		local pos = nameDB.position
		local defaultPoint, defaultRel, defaultOX, defaultOY, defaultJH
		if baseUnit == "raid" then
			defaultPoint, defaultRel, defaultOX, defaultOY, defaultJH = "CENTER", "CENTER", 0, 0, "CENTER"
		elseif baseUnit == "party" then
			defaultPoint, defaultRel, defaultOX, defaultOY, defaultJH = "LEFT", "LEFT", 4, 0, "LEFT"
		elseif baseUnit == "targettarget" or baseUnit == "focustarget" or baseUnit == "pet" then
			defaultPoint, defaultRel, defaultOX, defaultOY, defaultJH = "CENTER", "CENTER", 0, 0, "CENTER"
		else
			defaultPoint, defaultRel, defaultOX, defaultOY, defaultJH = "LEFT", "LEFT", 4, 0, "LEFT"
		end
		name:SetPoint(pos.point or defaultPoint, self.Health, pos.relativePoint or defaultRel, pos.offsetX or defaultOX, pos.offsetY or defaultOY)
		name:SetJustifyH(defaultJH)
	else
		if baseUnit == "raid" then
			name:SetPoint("CENTER", self.Health, "CENTER", 0, 0)
			name:SetJustifyH("CENTER")
		elseif baseUnit == "party" then
			name:SetPoint("LEFT", self.Health, "LEFT", 4, 0)
			name:SetJustifyH("LEFT")
		elseif baseUnit == "targettarget" or baseUnit == "focustarget" or baseUnit == "pet" then
			name:SetPoint("CENTER", self.Health, "CENTER", 0, 0)
			name:SetJustifyH("CENTER")
		else
			name:SetPoint("LEFT", self.Health, "LEFT", 4, 0)
			name:SetJustifyH("LEFT")
		end
	end
	self:Tag(name, finalTag)
	-- Update.lua에서 접근 가능하도록 프레임에 저장
	self.NameText = name
	return name
end

-----------------------------------------------
-- Create Health Text
-----------------------------------------------

local function CreateHealthText(self, unit, settings)
	local font, fontSize, fontFlags = GetFont()

	-- [FIX] 미적용 옵션 연결: Config font 설정 적용
	local healthDB = GetWidgetSettings(settings, "healthText")
	local hFont = healthDB and healthDB.font
	local hSize = (hFont and hFont.size) or fontSize
	local hOutline = (hFont and hFont.outline) or fontFlags
	local hStyle = (hFont and hFont.style) or font
	local hJustify = (hFont and hFont.justify) or "RIGHT"

	-- [FIX] /reload 시 이전 세션의 잔여 HealthText FontString 정리
	-- CreateFrame이 기존 named 프레임을 재사용하면 old children이 남아있을 수 있음
	if self.HealthText then
		self.HealthText:SetText("")
		self.HealthText:Hide()
	end
	-- Health StatusBar의 기존 FontString들도 정리 (stale text 방지)
	if self.Health then
		local regions = { self.Health:GetRegions() }
		for _, region in ipairs(regions) do
			if region:IsObjectType("FontString") and region ~= self.Health.bg then
				region:SetText("")
				region:Hide()
			end
		end
	end

	-- [FIX] TextOverlay에 생성하여 Power bar/Aura 프레임 위에 표시
	local textParent = self.TextOverlay or self.Health
	local healthText = textParent:CreateFontString(nil, "OVERLAY", nil, 6)
	healthText:SetFont(hStyle, hSize, hOutline)

	-- [FIX] 미적용 옵션 연결: position from Config
	if healthDB and healthDB.position then
		local pos = healthDB.position
		healthText:SetPoint(pos.point or "RIGHT", self.Health, pos.relativePoint or "CENTER", pos.offsetX or -4, pos.offsetY or 0)
	else
		healthText:SetPoint("RIGHT", self.Health, "RIGHT", -4, 0)
	end
	healthText:SetJustifyH(hJustify)

	-- [ESSENTIAL] 그림자 DB 설정 참조 (하드코딩 제거)
	local healthShadow = healthDB and healthDB.font and healthDB.font.shadow
	if healthShadow ~= false then
		healthText:SetShadowColor(0, 0, 0, 1)
		healthText:SetShadowOffset(1, -1)
	else
		healthText:SetShadowOffset(0, 0)
	end
	-- [ElvUI 패턴] 포맷별 태그 문자열로 등록 (포맷 변경 시 태그 문자열이 바뀌어 oUF 캐시 갱신)
	self.HealthText = healthText
	local htFmt = healthDB and healthDB.format or "percentage"
	local htTagMap = ns.HEALTH_FORMAT_TO_TAG
	local htTagStr = (htTagMap and htTagMap[htFmt]) or "[ddingui:ht:pct]"
	-- [FIX] healthText 색상 타입에 따른 태그 프리픽스 추가
	local htColorType = healthDB and healthDB.color and healthDB.color.type or "custom"
	if htColorType == "class_color" then
		htTagStr = "[ddingui:classcolor]" .. htTagStr .. "|r"
	elseif htColorType == "reaction_color" then
		htTagStr = "[ddingui:reactioncolor]" .. htTagStr .. "|r"
	elseif htColorType == "power_color" then
		htTagStr = "[ddingui:powercolor]" .. htTagStr .. "|r"
	end
	self:Tag(healthText, htTagStr)
	return healthText
end

-----------------------------------------------
-- Create Power Text
-----------------------------------------------

local function CreatePowerText(self, unit, settings)
	local font, fontSize, fontFlags = GetFont()

	local ptDB = GetWidgetSettings(settings, "powerText")
	local pFont = ptDB and ptDB.font
	local pSize = (pFont and pFont.size) or (fontSize - 1)
	local pOutline = (pFont and pFont.outline) or fontFlags
	local pStyle = (pFont and pFont.style) or font
	local pJustify = (pFont and pFont.justify) or "RIGHT"

	-- 기존 PowerText 정리 (/reload 스택 방지)
	if self.PowerText then
		self.PowerText:SetText("")
		self.PowerText:Hide()
	end

	-- 기력바 또는 체력바에 앵커
	local anchor = (ptDB and ptDB.anchorToPowerBar and self.Power) or self.Health
	if not anchor then return end

	-- [FIX] TextOverlay에 생성하여 Power bar/Aura 프레임 위에 표시
	local textParent = self.TextOverlay or self.Health
	local powerText = textParent:CreateFontString(nil, "OVERLAY", nil, 6)
	powerText:SetFont(pStyle, pSize, pOutline)

	-- 위치
	if ptDB and ptDB.position then
		local pos = ptDB.position
		powerText:SetPoint(pos.point or "RIGHT", anchor, pos.relativePoint or "CENTER", pos.offsetX or -4, pos.offsetY or 0)
	elseif self.Power and ptDB and ptDB.anchorToPowerBar then
		powerText:SetPoint("CENTER", self.Power, "CENTER", 0, 0)
	else
		powerText:SetPoint("LEFT", self.Health, "LEFT", 4, 0)
	end
	powerText:SetJustifyH(pJustify)

	-- 그림자
	local pShadow = pFont and pFont.shadow
	if pShadow ~= false then
		powerText:SetShadowColor(0, 0, 0, 1)
		powerText:SetShadowOffset(1, -1)
	else
		powerText:SetShadowOffset(0, 0)
	end

	-- 색상: custom일 때만 SetTextColor (나머지는 태그 내부에서 처리)
	local colorOpt = ptDB and ptDB.color
	local colorType = colorOpt and colorOpt.type or "power_color"
	if colorType == "custom" and colorOpt and colorOpt.rgb then
		powerText:SetTextColor(colorOpt.rgb[1] or 1, colorOpt.rgb[2] or 1, colorOpt.rgb[3] or 1)
	end

	-- [ElvUI 패턴] 포맷별 태그 문자열로 등록 (포맷 변경 시 태그 문자열이 바뀌어 oUF 갱신)
	local fmt = ptDB and ptDB.format or "percentage"
	local tagMap = ns.POWER_FORMAT_TO_TAG
	local tagStr = (tagMap and tagMap[fmt]) or "[ddingui:pt:pct]"
	-- [FIX] 색상 타입에 따른 태그 프리픽스 추가
	if colorType == "power_color" then
		tagStr = "[ddingui:powercolor]" .. tagStr .. "|r"
	elseif colorType == "class_color" then
		tagStr = "[ddingui:classcolor]" .. tagStr .. "|r"
	elseif colorType == "reaction_color" then
		tagStr = "[ddingui:reactioncolor]" .. tagStr .. "|r"
	end
	self:Tag(powerText, tagStr)

	self.PowerText = powerText

	-- [12.0.1] disabled면 숨기기
	if ptDB and ptDB.enabled == false then
		powerText:Hide()
	end

	return powerText
end

-----------------------------------------------
-- Create Buffs/Debuffs
-- Config: settings.widgets.buffs, settings.widgets.debuffs
-----------------------------------------------

-- [FIX] 지속시간 포맷 헬퍼 (초 → 표시 문자열)
local function FormatAuraDuration(remaining)
	if remaining >= 86400 then
		return string.format("%dd", math.floor(remaining / 86400))
	elseif remaining >= 3600 then
		return string.format("%dh", math.floor(remaining / 3600))
	elseif remaining >= 60 then
		return string.format("%dm", math.floor(remaining / 60))
	elseif remaining >= 1 then
		return string.format("%d", math.floor(remaining))
	else
		return string.format("%.1f", remaining)
	end
end

-----------------------------------------------
-- [12.0.1] 공유 애니메이션 타이머 (Shared Animation Timer)
-- 개별 OnUpdate 대신 5FPS 공유 타이머로 모든 오라 아이콘 업데이트
-- DandersFrames SharedAnimationTimer 패턴 차용
-----------------------------------------------
local activeAuraButtons = {} -- button → true
local SHARED_TIMER_INTERVAL = 0.2 -- 5FPS
local sharedTimerFrame = CreateFrame("Frame")
local sharedTimerElapsed = 0

-- [12.0.1] 지속시간 색상 그라데이션 (DandersFrames C_CurveUtil 패턴 차용)
-- remaining/total 비율 기반 선형 보간
local function LerpColor(c1, c2, t)
	return
		c1[1] + (c2[1] - c1[1]) * t,
		c1[2] + (c2[2] - c1[2]) * t,
		c1[3] + (c2[3] - c1[3]) * t
end

local function GetDurationGradientColor(remaining, duration, durationColors)
	if duration <= 0 then return nil end
	local ratio = remaining / duration

	local high = durationColors.high or { 1, 1, 1 }
	local medium = durationColors.medium or { 1, 1, 0 }
	local low = durationColors.low or { 1, 0.5, 0 }
	local expiring = durationColors.expiring or { 1, 0, 0 }

	if ratio > 0.5 then
		return high[1], high[2], high[3]
	elseif ratio > 0.25 then
		local t = (ratio - 0.25) / 0.25
		return LerpColor(medium, high, t)
	elseif ratio > 0.1 then
		local t = (ratio - 0.1) / 0.15
		return LerpColor(low, medium, t)
	else
		local t = math.min(ratio / 0.1, 1)
		return LerpColor(expiring, low, t)
	end
end

-- [FIX] 임계값(threshold) 색상: 절대 시간(초) 기준
local function GetDurationThresholdColor(remaining, durationColors)
	local thresholds = durationColors and durationColors.thresholds
	if not thresholds then return nil end
	for _, t in ipairs(thresholds) do
		if remaining < t.time then
			return t.rgb[1], t.rgb[2], t.rgb[3]
		end
	end
	return nil -- threshold에 해당 안 됨 → 기본 색상 유지
end

-- 공유 타이머: 5FPS로 모든 등록된 오라 버튼 업데이트
sharedTimerFrame:SetScript("OnUpdate", function(self, elapsed)
	sharedTimerElapsed = sharedTimerElapsed + elapsed
	if sharedTimerElapsed < SHARED_TIMER_INTERVAL then return end
	sharedTimerElapsed = 0

	local now = GetTime()
	for button in pairs(activeAuraButtons) do
		if not button:IsShown() then
			activeAuraButtons[button] = nil -- 숨겨진 버튼 자동 해제
		elseif button.Duration then
			local exp = button._expirationTime
			if not exp or exp == 0 then
				button.Duration:Hide()
			else
				local remaining = exp - now
				if remaining <= 0 then
					button.Duration:Hide()
					activeAuraButtons[button] = nil
				else
					button.Duration:SetText(FormatAuraDuration(remaining))
					button.Duration:Show()
					-- [12.0.1] gradient/threshold 색상 적용
					local dur = button._totalDuration or 0
					local colorMode = button._durationColorMode
					local colors = button._durationColors
					if colorMode == "gradient" and dur > 0 and colors then
						local r, g, b = GetDurationGradientColor(remaining, dur, colors)
						if r then button.Duration:SetTextColor(r, g, b) end
					elseif colorMode == "threshold" and colors then
						local r, g, b = GetDurationThresholdColor(remaining, colors)
						if r then button.Duration:SetTextColor(r, g, b) end
					end
				end
			end
		end
	end
end)
-- 외부 접근용 (Update.lua에서 font 갱신 시 사용)
ns._activeAuraButtons = activeAuraButtons

-- 오라 아이콘 생성 콜백 — oUF PostCreateButton
local function PostCreateAuraIcon(element, button)
	if type(button) == "number" then
		return nil
	end

	-- [FIX] oUF button.Icon (대문자 I)
	if button.Icon then
		button.Icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
	end

	-- oUF 기본 Overlay 숨기기 (DDingUI는 커스텀 테두리 사용)
	if button.Overlay then button.Overlay:Hide() end

	-- [FIX] 디버프 외곽선: 기본 테두리 없음, 디버프만 dispel 색상 외곽선
	local borderSize = 1
	local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -borderSize, borderSize)
	border:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
	border:SetFrameLevel(button:GetFrameLevel())
	border:SetBackdrop({
		edgeFile = C.FLAT_TEXTURE,
		edgeSize = borderSize,
	})
	border:SetBackdropBorderColor(0, 0, 0, 0) -- [FIX] 기본: 투명 (테두리 없음)
	button._border = border -- [FIX] oUF의 button.border와 충돌 방지

	-- [FIX] DB 기반 폰트 설정 (element._fontDB에서 읽기)
	local fontDB = element._fontDB

	-- 쿨다운 (스파이럴) — [FIX] oUF button.Cooldown (대문자 C)
	if button.Cooldown then
		button.Cooldown:SetReverse(true)
		button.Cooldown:SetHideCountdownNumbers(true) -- 내장 숫자 숨기기 → 커스텀 duration 사용
	end

	-- [FIX] 중첩 수 텍스트: DB 설정 반영 — oUF button.Count (대문자 C)
	if button.Count then
		local sDB = fontDB and fontDB.stacks
		local sSize = (sDB and sDB.size) or 10
		local sOutline = (sDB and sDB.outline) or C.DEFAULT_FONT_FLAGS
		local sStyle = (sDB and sDB.style) or C.DEFAULT_FONT
		SafeSetFont(button.Count, sStyle, sSize, sOutline)
		button.Count:ClearAllPoints()
		local sPoint = (sDB and sDB.point) or "BOTTOMRIGHT"
		local sRelPoint = (sDB and sDB.relativePoint) or "BOTTOMRIGHT"
		local sOX = (sDB and sDB.offsetX) or 2
		local sOY = (sDB and sDB.offsetY) or -1
		button.Count:SetPoint(sPoint, button, sRelPoint, sOX, sOY)
		if sDB and sDB.rgb then
			button.Count:SetTextColor(sDB.rgb[1] or 1, sDB.rgb[2] or 1, sDB.rgb[3] or 1)
		end
	end

	-- [FIX] 지속시간 텍스트: 커스텀 FontString 생성 (CooldownFrame 내장 숫자 대체)
	local dDB = fontDB and fontDB.duration
	local dSize = (dDB and dDB.size) or 10
	local dOutline = (dDB and dDB.outline) or C.DEFAULT_FONT_FLAGS
	local dStyle = (dDB and dDB.style) or C.DEFAULT_FONT
	local dPoint = (dDB and dDB.point) or "CENTER"
	local dRelPoint = (dDB and dDB.relativePoint) or "CENTER"
	local dOX = (dDB and dDB.offsetX) or 0
	local dOY = (dDB and dDB.offsetY) or 0

	if not button.Duration then
		-- cooldown 위에 표시되도록 높은 frameLevel 프레임 사용
		local durParent = CreateFrame("Frame", nil, button)
		durParent:SetAllPoints()
		durParent:SetFrameLevel((button.Cooldown and button.Cooldown:GetFrameLevel() or button:GetFrameLevel()) + 2)
		button.Duration = durParent:CreateFontString(nil, "OVERLAY")
	end
	SafeSetFont(button.Duration, dStyle, dSize, dOutline)
	button.Duration:ClearAllPoints()
	button.Duration:SetPoint(dPoint, button, dRelPoint, dOX, dOY)
	if dDB and dDB.rgb then
		button.Duration:SetTextColor(dDB.rgb[1] or 1, dDB.rgb[2] or 1, dDB.rgb[3] or 1)
	end
	button.Duration:Hide() -- 기본 숨김 (공유 타이머에서 표시)

	-- [12.0.1] 공유 타이머용 초기값 (개별 OnUpdate 제거 → 공유 타이머 사용)
	button._expirationTime = 0
	button._totalDuration = 0
	button._durationColorMode = (fontDB and fontDB.duration and fontDB.duration.colorMode) or "fixed"
	button._durationColors = element._durationColors -- CreateAuras에서 설정
end

-- [FIX] 기존 오라 아이콘의 폰트/위치를 DB 기준으로 라이브 업데이트
local function RefreshAuraFonts(element)
	if not element then return end
	local fontDB = element._fontDB
	if not fontDB then return end

	for i = 1, (element.createdButtons or 0) do
		local button = element[i]
		if button then
			-- Count (중첩 수) 폰트
			if button.Count then
				local sDB = fontDB.stacks
				SafeSetFont(button.Count, (sDB and sDB.style) or C.DEFAULT_FONT,
					(sDB and sDB.size) or 10, (sDB and sDB.outline) or C.DEFAULT_FONT_FLAGS)
				button.Count:ClearAllPoints()
				button.Count:SetPoint(
					(sDB and sDB.point) or "BOTTOMRIGHT", button,
					(sDB and sDB.relativePoint) or "BOTTOMRIGHT",
					(sDB and sDB.offsetX) or 2, (sDB and sDB.offsetY) or -1)
				if sDB and sDB.rgb then
					button.Count:SetTextColor(sDB.rgb[1] or 1, sDB.rgb[2] or 1, sDB.rgb[3] or 1)
				end
			end
			-- Duration (지속시간) 폰트
			if button.Duration then
				local dDB = fontDB.duration
				SafeSetFont(button.Duration, (dDB and dDB.style) or C.DEFAULT_FONT,
					(dDB and dDB.size) or 10, (dDB and dDB.outline) or C.DEFAULT_FONT_FLAGS)
				button.Duration:ClearAllPoints()
				button.Duration:SetPoint(
					(dDB and dDB.point) or "CENTER", button,
					(dDB and dDB.relativePoint) or "CENTER",
					(dDB and dDB.offsetX) or 0, (dDB and dDB.offsetY) or 0)
				if dDB and dDB.rgb then
					button.Duration:SetTextColor(dDB.rgb[1] or 1, dDB.rgb[2] or 1, dDB.rgb[3] or 1)
				end
				button._durationColorMode = (dDB and dDB.colorMode) or "fixed"
			end
		end
	end
end
ns._RefreshAuraFonts = RefreshAuraFonts -- [FIX] Update.lua / Options.lua에서 호출

-----------------------------------------------
-- [AURA-FILTER] Secret-Safe Aura Filter (12.0.1)
-- WoW 12.x: isBossAura, isFromPlayerOrPlayerPet, isRaid, dispelName 등
--   모두 secret value 가능 → boolean context에서 직접 테스트하면 taint 크래시
-- spellId/name/icon/duration/sourceUnit → secret 가능 → issecretvalue() 가드 필수
-----------------------------------------------

-- SafeVal/SafeNum은 파일 상단에서 선언 (line 33-34)

-- [FIX] 전투 중 secret value 방어 헬퍼 (ElvUI auraskip.lua 방식)
-- 1차: 직접 API 호출 — 가장 확실한 방법 (양방향 필터 체크)
-- 2차: non-secret 필드 fallback (unit 없을 때)
-- 3차: oUF processData의 isPlayerAura
local function GetIsMine(auraData, unit)
	-- [FIX] 1차: 직접 API 호출 (ElvUI InstanceFiltered 방식)
	-- HELPFUL|PLAYER, HARMFUL|PLAYER 양쪽 모두 체크 → isHarmfulAura 의존 없음
	if unit and auraData.auraInstanceID then
		local notFilteredH = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
			unit, auraData.auraInstanceID, "HELPFUL|PLAYER"
		)
		local notFilteredD = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
			unit, auraData.auraInstanceID, "HARMFUL|PLAYER"
		)
		return notFilteredH or notFilteredD
	end
	-- 2차: non-secret 필드 (unit 없을 때만)
	local val = SafeVal(auraData.isFromPlayerOrPlayerPet)
	if val ~= nil then return val end
	-- 3차: oUF processData
	if auraData.isPlayerAura ~= nil then return auraData.isPlayerAura end
	return nil -- 판단 불가
end

-- [AURA-FILTER] 글로벌 블랙/화이트리스트 (spellId 기반 → secret guard 필요)
local function CheckGlobalFilters(auraType, spellID)
	spellID = SafeVal(spellID) -- [REFACTOR] secret → nil
	if not spellID then return nil end -- nil = 판단 보류

	local globalFilters = ns.AuraFilters and ns.AuraFilters[auraType]
	if not globalFilters then return nil end

	if globalFilters.blacklist and globalFilters.blacklist[spellID] then
		return false -- 블랙리스트: 거부
	end
	if globalFilters.whitelist and globalFilters.whitelist[spellID] then
		return true -- 화이트리스트: 즉시 통과
	end
	return nil -- 판단 보류 → 다음 필터로
end

-- [AURA-FILTER] duration 기반 필터 (secret guard)
-- [FIX] duration이 secret이면 판단 불가 → 숨기지 않음 (보이는 게 안전)
local function CheckDurationFilter(filter, auraData)
	local rawDur = auraData.duration
	-- secret value면 duration 판별 불가 → 필터 통과 (숨기지 않음)
	if rawDur ~= nil and issecretvalue and issecretvalue(rawDur) then return true end
	local duration = tonumber(rawDur) or 0

	if filter.hideNoDuration and duration == 0 then return false end
	local maxDur = filter.maxDuration or 0
	if maxDur > 0 and duration > 0 and duration > maxDur then return false end
	return true
end

-- ============================================================
-- [AURA-FILTER] Blizzard Aura Cache (DandersFrames 방식)
-- HideBlizzard.lua가 CompactRaidFrameManager를 SetAlpha(0)으로 숨기되
-- 이벤트는 유지 → CompactUnitFrame_UpdateAuras hook이 정상 발동
-- hook에서 IsShown()으로 Blizzard가 실제 표시하는 버프만 캐시
-- ============================================================
local BlizzardAuraCache = {}  -- unit → { buffs={}, debuffs={} }
local BlizzardCacheGUIDMap = {} -- GUID → unit key (캐시 유닛 키 역매핑)
local BlizzardCacheValid = {}  -- unit → true (hook이 최소 1회 호출되어 캐시가 유효함)

local function CaptureBlizzardAuras(frame)
	if not frame or not frame.unit then return end
	if frame.unitExists == false then return end

	local unit = frame.unit
	if type(unit) ~= "string" then return end
	if unit:find("nameplate") then return end

	local frameName = frame.GetName and frame:GetName()
	if frameName and (frameName:find("Preview") or frameName:find("Settings")) then return end

	-- GUID 매핑 (oUF unit ≠ Blizzard unit 일 때 역매핑용)
	local guid = UnitGUID(unit)
	if guid then
		BlizzardCacheGUIDMap[guid] = unit
	end

	BlizzardCacheValid[unit] = true -- hook 호출됨 → 캐시 유효

	if not BlizzardAuraCache[unit] then
		BlizzardAuraCache[unit] = { buffs = {}, debuffs = {} }
	end
	local cache = BlizzardAuraCache[unit]
	wipe(cache.buffs)
	wipe(cache.debuffs)

	-- Blizzard buffFrames: IsShown() = 프레임 자체 상태 (부모 alpha 무관)
	if frame.buffFrames then
		for _, bf in ipairs(frame.buffFrames) do
			if bf and bf.IsShown and bf:IsShown() and bf.auraInstanceID then
				cache.buffs[bf.auraInstanceID] = true
			end
		end
	end

	if frame.debuffFrames then
		for _, df in ipairs(frame.debuffFrames) do
			if df and df.IsShown and df:IsShown() and df.auraInstanceID then
				cache.debuffs[df.auraInstanceID] = true
			end
		end
	end

	if frame.dispelDebuffFrames then
		for _, df in ipairs(frame.dispelDebuffFrames) do
			if df and df.IsShown and df:IsShown() and df.auraInstanceID then
				cache.debuffs[df.auraInstanceID] = true
			end
		end
	end
end

-- Hook: CompactUnitFrame_UpdateAuras 완료 후 캐시 갱신
if CompactUnitFrame_UpdateAuras then
	hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
		if frame and frame.unit and frame.unitExists ~= false then
			CaptureBlizzardAuras(frame)
		end
	end)
end
if CompactUnitFrame_UpdateBuffs then
	hooksecurefunc("CompactUnitFrame_UpdateBuffs", function(frame)
		if frame and frame.unit and frame.unitExists ~= false then
			CaptureBlizzardAuras(frame)
		end
	end)
end

-- 그룹 변경 시 캐시 무효화
local blizzCacheWatcher = CreateFrame("Frame")
blizzCacheWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
blizzCacheWatcher:SetScript("OnEvent", function()
	wipe(BlizzardAuraCache)
	wipe(BlizzardCacheGUIDMap)
	wipe(BlizzardCacheValid)
end)

-- ============================================================
-- [AURA-FILTER] Blizzard 버프 필터
-- 1) 캐시 히트 → Blizzard가 실제 표시하는 버프만 (DandersFrames 동일)
-- 2) 캐시 미스 → SpellGetVisibilityInfo fallback (oUF가 disable한 유닛용)
-- ============================================================
local function FindCacheForUnit(unit)
	-- 직접 매치 (BlizzardCacheValid 체크: hook이 1회 이상 호출되었을 때만)
	if BlizzardCacheValid[unit] then
		return BlizzardAuraCache[unit]
	end
	-- GUID 역매핑: oUF "player" ↔ Blizzard "raid1", oUF "party1" ↔ Blizzard "raid3" 등
	local guid = UnitGUID(unit)
	if guid then
		local cacheUnit = BlizzardCacheGUIDMap[guid]
		if cacheUnit and BlizzardCacheValid[cacheUnit] then
			return BlizzardAuraCache[cacheUnit]
		end
	end
	return nil
end

local function BlizzardBuffFilter(auraData, unit)
	-- 1) 캐시 경로: Blizzard가 실제 표시하는 버프만 (정확한 매치)
	local cache = FindCacheForUnit(unit)
	if cache then
		local auraInstanceID = auraData.auraInstanceID
		if auraInstanceID then
			return cache.buffs[auraInstanceID] == true
		end
		return false
	end

	-- 2) 캐시 없음 fallback: SpellGetVisibilityInfo 직접 판정
	if SafeVal(auraData.isBossAura) then return true end
	if SafeVal(auraData.isRaid) then return true end

	local spellId = SafeVal(auraData.spellId) -- [REFACTOR]
	if not spellId then return false end

	local visType = UnitAffectingCombat("player") and "RAID_INCOMBAT" or "RAID_OUTOFCOMBAT"
	local hasCustom, alwaysShowMine, showForMySpec = SpellGetVisibilityInfo(spellId, visType)

	if hasCustom then
		return showForMySpec or (alwaysShowMine and SafeVal(auraData.isFromPlayerOrPlayerPet))
	end

	-- Blizzard 기본: 내가 건 버프 + duration <= 120초
	if SafeVal(auraData.isFromPlayerOrPlayerPet) then
		local dur = SafeNum(auraData.duration, 0) -- [REFACTOR]
		if dur > 0 and dur <= 120 then return true end
	end

	return false
end

-- [AURA-FILTER] 메인 버프 필터 (party/raid/target/focus 등)
local function FilterBuffs(filter, auraData, unit)
	-- 0) 보스 버프는 항상 통과 (secret guard)
	if SafeVal(auraData.isBossAura) then return true end

	-- 1) onlyMine: 내가 건 버프만 (secret guard)
	if filter.onlyMine then
		local isMine = GetIsMine(auraData, unit)
		if isMine == false then return false end
		-- nil(판별 불가) → 통과 (전투 중 보이는 게 안전)
	end

	-- [FIX] 그룹 프레임 (party/raid) 필터
	if not filter.onlyMine then
		local baseUnit = unit and unit:gsub("%d", "")
		if baseUnit == "party" or baseUnit == "raid" then
			-- 블리자드 파티프레임 필터: SpellGetVisibilityInfo API
			if filter.useBlizzardFilter then
				return BlizzardBuffFilter(auraData, unit)
			end
			-- fallback: 내 버프 + 보스 + 레이드만
			local isBoss = SafeVal(auraData.isBossAura)
			local isRaidAura = SafeVal(auraData.isRaid)
			local isMine = GetIsMine(auraData, unit)
			-- [FIX] 전투 중 전부 secret(nil) → 표시 (안 보이는 것보다 나음)
			if isMine ~= nil or isBoss ~= nil or isRaidAura ~= nil then
				if not (isMine or isBoss or isRaidAura) then
					return false
				end
			end
		end
	end

	-- 2) duration 필터
	if not CheckDurationFilter(filter, auraData) then return false end

	-- 3) showBossAura (기본 true, 위에서 이미 처리됨)
	-- 4) showRaid
	-- 이 시점에서 기본 통과
	return true
end

-- [AURA-FILTER] 메인 디버프 필터 (party/raid/target/focus 등)
local function FilterDebuffs(filter, auraData, unit)
	-- 0) showAll: 전부 표시 모드
	if filter.showAll then
		return CheckDurationFilter(filter, auraData)
	end

	-- 1) 보스 디버프 → 항상 표시 (secret guard)
	if filter.showBossAura ~= false and SafeVal(auraData.isBossAura) then return true end

	-- 2) 블리자드 레이드 디버프 → 항상 표시 (secret guard)
	if filter.showRaid and SafeVal(auraData.isRaid) then return true end

	-- 3) 해제 가능한 디버프만 모드 (secret guard)
	if filter.onlyDispellable then
		if SafeVal(auraData.dispelName) then return true end
		if SafeVal(auraData.isBossAura) then return true end
		local isMine = GetIsMine(auraData, unit)
		if isMine then return true end
		-- [FIX] 전투 중 전부 secret(nil) → 표시 (판별 불가 시 숨기지 않음)
		if SafeVal(auraData.dispelName) == nil and SafeVal(auraData.isBossAura) == nil and isMine == nil then
			return true
		end
		return false
	end

	-- 4) onlyMine: 내 디버프만 (secret guard)
	if filter.onlyMine then
		local isMine = GetIsMine(auraData, unit)
		if isMine == false then return false end
		-- nil(판별 불가) → 통과 (전투 중 보이는 게 안전)
	end

	-- 5) duration 필터
	if not CheckDurationFilter(filter, auraData) then return false end

	-- 6) 기본: 내 것 + 보스 표시 (secret guard)
	local isMine = GetIsMine(auraData, unit)
	local isBoss = SafeVal(auraData.isBossAura)
	-- [FIX] 전투 중 전부 secret(nil) → 표시 (판별 불가)
	if isMine ~= nil or isBoss ~= nil then
		return isMine or isBoss or false
	end
	return true -- 전부 secret → 보이는 게 안전
end

-- [12.0.1] FilterDefensives 제거 — CenterDefensiveBuff API 100% 의존
-- 개별 유닛 프레임(player/target/focus)에서 생존기 트래커 불필요
ns.FilterDefensives = nil

-- [AURA-FILTER] 통합 CustomFilter 콜백 (oUF Buffs/Debuffs element용)
local function ConfigBasedAuraFilter(element, unit, auraData)
	if not auraData then return false end

	-- [FIX] 파티/레이드 헤더 내 플레이어 프레임 감지
	-- showPlayer=true일 때 unit="player"이지만 그룹 필터(party/raid)를 적용해야 함
	-- unit은 변경하지 않음 (캐시/GUID 조회에 "player" 그대로 사용)
	local isPlayerInGroup = false
	local filterBaseUnit = nil -- settings 참조용 오버라이드 (party/raid)
	if unit == "player" then
		-- [REFACTOR] oUF-headerType → _unitKey 체크 (oUF 의존 제거)
		local owner = element.__owner
		if owner and (owner._unitKey == "party" or owner._unitKey == "raid") then
			isPlayerInGroup = true
			filterBaseUnit = owner._unitKey
		end
	end

	local isDebuff = SafeVal(auraData.isHarmfulAura)
	local auraType = isDebuff and "debuffs" or "buffs"
	local baseUnit = filterBaseUnit or unit:gsub("%d", "")
	local settings = ns.db[baseUnit]
	local filter = settings and settings.widgets and settings.widgets[auraType] and settings.widgets[auraType].filter

	-- 1) 글로벌 블랙/화이트리스트 (secret-safe)
	local globalResult = CheckGlobalFilters(auraType, auraData.spellId)
	if globalResult ~= nil then return globalResult end

	-- 1.5) [FIX] 레이드 시너지 버프 숨기기 (spellId 1차 + 아이콘 텍스처 2차 fallback)
	-- 파티/레이드 어느 쪽이든 켜져 있으면 그룹 프레임에 적용
	local hideRaidBuffs = not isDebuff and filter and filter.hideRaidBuffs
	if not hideRaidBuffs and not isDebuff and (baseUnit == "party" or baseUnit == "raid") then
		local otherKey = baseUnit == "party" and "raid" or "party"
		local otherFilter = ns.db[otherKey] and ns.db[otherKey].widgets
			and ns.db[otherKey].widgets.buffs and ns.db[otherKey].widgets.buffs.filter
		hideRaidBuffs = otherFilter and otherFilter.hideRaidBuffs
	end
	if hideRaidBuffs then
		-- 1차: spellId 직접 매칭 (전투 밖에서 확실)
		local spellID = SafeVal(auraData.spellId)
		if spellID and ns.RaidSynergyBuffs[spellID] then
			return false
		end
		-- 2차: 아이콘 텍스처 매칭 (spellId가 secret일 때 fallback)
		if not spellID then
			local iconTex = auraData.icon
			if iconTex and not (issecretvalue and issecretvalue(iconTex)) then
				local raidBuffIcons = ns.GetRaidSynergyBuffIcons()
				if raidBuffIcons and raidBuffIcons[iconTex] then
					return false
				end
			end
		end
	end

	-- 2) 파티/레이드 내 플레이어 프레임: 블리자드 파티프레임 필터
	-- SpellGetVisibilityInfo: Blizzard 파티/레이드 프레임 내부 필터 동일
	if isPlayerInGroup and not isDebuff and filter and filter.useBlizzardFilter then
		return BlizzardBuffFilter(auraData, unit)
	end

	-- 3) per-unit 필터 없으면 기본 동작 (secret guard)
	if not filter then
		if isDebuff then
			-- [FIX] 전투 중 secret → 표시 (판별 불가 시 숨기지 않음)
			local isMine = GetIsMine(auraData, unit)
			local isBoss = SafeVal(auraData.isBossAura)
			if isMine ~= nil or isBoss ~= nil then
				return isMine or isBoss or false
			end
			return true -- 전부 secret → 보이는 게 안전
		else
			-- [FIX] 전투 중 secret → 표시
			local isMine = GetIsMine(auraData, unit)
			if isMine ~= nil then return isMine end
			return true -- secret → 보이는 게 안전
		end
	end

	-- 4) 타입별 필터
	if isDebuff then
		return FilterDebuffs(filter, auraData, unit)
	else
		return FilterBuffs(filter, auraData, unit)
	end
end

-- [AURA-FILTER] 오라 정렬: non-secret 필드 기반 우선순위 정렬
-- 디버프: Boss > Raid > Dispellable > Mine > Others
-- 버프: Mine > Boss > Others
local function SortAuras(element, a, b)
	if not a or not b then return false end
	local aData = a._data
	local bData = b._data
	if not aData or not bData then return false end

	-- 우선순위 점수 계산 (높을수록 먼저, secret guard)
	local function GetPriority(data, isDebuff)
		local score = 0
		if SafeVal(data.isBossAura) then score = score + 100 end
		if SafeVal(data.isRaid) then score = score + 50 end
		if isDebuff and SafeVal(data.dispelName) then score = score + 30 end
		if SafeVal(data.isFromPlayerOrPlayerPet) then score = score + 20 end
		return score
	end

	local isDebuff = element.showDebuffType -- debuffs element에만 있음
	local aPri = GetPriority(aData, isDebuff)
	local bPri = GetPriority(bData, isDebuff)

	if aPri ~= bPri then return aPri > bPri end

	-- 동일 우선순위: auraInstanceID 순서 (안정 정렬)
	local aID = aData.auraInstanceID or 0
	local bID = bData.auraInstanceID or 0
	-- auraInstanceID는 항상 non-secret
	if aID ~= bID then return aID < bID end

	return false
end

-- 오라 아이콘 업데이트 콜백 — oUF PostUpdateButton
-- 시그니처: element:PostUpdateButton(button, unit, data, position)
local function PostUpdateAuraIcon(element, button, unit, data, position)
	if not button or not data then return end

	-- [FIX] oUF Overlay 강제 숨김 (showDebuffType=true일 때 oUF가 매번 다시 Show함 → 이중 테두리)
	if button.Overlay then button.Overlay:Hide() end

	-- [FIX] 디버프 외곽선: 디버프만 dispel 타입 색상, 버프는 테두리 없음(투명)
	if button._border then
		if SafeVal(data.isHarmfulAura) then
			local dtype = SafeVal(data.dispelName)
			local color = dtype and C.DISPEL_COLORS[dtype] or C.DISPEL_COLORS.none
			if color then
				button._border:SetBackdropBorderColor(color[1], color[2], color[3], 1)
			else
				button._border:SetBackdropBorderColor(0.8, 0, 0, 1) -- fallback: 빨강
			end
		else
			button._border:SetBackdropBorderColor(0, 0, 0, 0) -- 버프: 투명
		end
	end

	-- [FIX] secret icon 방어: data.icon이 진짜 nil일 때만 폴백
	-- oUF가 SetTexture(secretValue)를 호출하면 C++에서 정상 렌더링됨
	-- SafeVal로 secret → nil 변환 후 덮어쓰면 oUF가 설정한 올바른 텍스처를 파괴함
	if button.Icon and data.icon == nil then
		button.Icon:SetTexture(136243) -- Interface\\Icons\\INV_Misc_QuestionMark
	end

	-- [FIX] Duration 위치 재적용: 전투 중 위치 초기화 방지
	-- PostCreateAuraIcon에서 설정한 위치가 외부 요인으로 변경될 수 있음
	if button.Duration and element._fontDB then
		local dDB = element._fontDB.duration
		if dDB and (dDB.point or dDB.offsetX or dDB.offsetY) then
			button.Duration:ClearAllPoints()
			button.Duration:SetPoint(
				dDB.point or "CENTER", button,
				dDB.relativePoint or "CENTER",
				dDB.offsetX or 0, dDB.offsetY or 0)
		end
	end

	-- [REFACTOR] 지속시간 텍스트: 공유 타이머에 등록/해제
	if button.Duration then
		local dur = SafeNum(data.duration, 0)
		local expTime = SafeNum(data.expirationTime, 0)

		-- [FIX] secret duration 판별: SafeNum이 0이지만 원본이 secret인 경우
		local isSecretDuration = dur == 0 and issecretvalue and issecretvalue(data.duration)

		if dur > 0 and expTime > 0 then
			-- 일반 (비 secret) → 커스텀 Duration 텍스트 사용
			if button.Cooldown then
				button.Cooldown:SetHideCountdownNumbers(true)
			end
			button._expirationTime = expTime
			button._totalDuration = dur -- [12.0.1] gradient용 전체 지속시간
			-- 공유 타이머 등록
			activeAuraButtons[button] = true

			local remaining = expTime - GetTime()
			if remaining > 0 then
				button.Duration:SetText(FormatAuraDuration(remaining))
				button.Duration:Show()
				-- 즉시 gradient/threshold 색상 적용
				local cm = button._durationColorMode
				local dc = button._durationColors
				if cm == "gradient" and dc then
					local r, g, b = GetDurationGradientColor(remaining, dur, dc)
					if r then button.Duration:SetTextColor(r, g, b) end
				elseif cm == "threshold" and dc then
					local r, g, b = GetDurationThresholdColor(remaining, dc)
					if r then button.Duration:SetTextColor(r, g, b) end
				end
			else
				button.Duration:Hide()
			end
		elseif isSecretDuration then
			-- [FIX] 전투 중 secret duration → Cooldown 네이티브 카운트다운 사용
			-- oUF가 SetCooldownFromDurationObject로 Cooldown 설정 완료 → 네이티브 텍스트 표시
			button._expirationTime = 0
			button._totalDuration = 0
			activeAuraButtons[button] = nil
			button.Duration:Hide() -- 커스텀 텍스트 숨기기
			if button.Cooldown then
				button.Cooldown:SetHideCountdownNumbers(false) -- 네이티브 카운트다운 표시
			end
		else
			-- 영구 버프 (duration == 0, 비 secret) → 타이머 해제
			button._expirationTime = 0
			button._totalDuration = 0
			activeAuraButtons[button] = nil
			button.Duration:Hide()
		end
	end

	-- auraData 참조 보관 (SortAuras에서 사용)
	button._data = data
end

local function CreateAuras(self, unit, settings)
	local buffDB = GetWidgetSettings(settings, "buffs")
	local debuffDB = GetWidgetSettings(settings, "debuffs")

	-- [FIX] 아이콘 정렬 방향 헬퍼: 1차/2차 방향 → oUF 속성 매핑
	-- growDir: 1차 방향 (RIGHT/LEFT/DOWN/UP)
	-- colGrowDir: 2차 방향 (줄 바꿈 방향)
	-- oUF 속성: growthX, growthY, maxCols, initialAnchor, SetPosition
	local function ApplyAuraGrowth(element, growDir, colGrowDir, maxPerLine, hSpacing, vSpacing, iconSize, num)
		local isVerticalPrimary = (growDir == "DOWN" or growDir == "UP")

		if isVerticalPrimary then
			-- 세로 1차: 커스텀 SetPosition 필요 (oUF는 가로 1차만 지원)
			local maxRows = math_max(1, maxPerLine)
			local maxColCount = math_max(1, math.ceil(num / maxRows))
			element:SetSize(iconSize * maxColCount + hSpacing * (maxColCount - 1), iconSize * maxRows + vSpacing * (maxRows - 1))

			-- 앵커 결정: 1차(세로) + 2차(가로) 조합
			local ySign = (growDir == "DOWN") and -1 or 1
			local xSign = (colGrowDir == "LEFT") and -1 or 1
			if growDir == "DOWN" and colGrowDir == "LEFT" then
				element.initialAnchor = "TOPRIGHT"
			elseif growDir == "DOWN" then
				element.initialAnchor = "TOPLEFT"
			elseif growDir == "UP" and colGrowDir == "LEFT" then
				element.initialAnchor = "BOTTOMRIGHT"
			else
				element.initialAnchor = "BOTTOMLEFT"
			end

			-- oUF 기본값 (SetPosition 오버라이드에서 직접 사용하므로 형식상 설정)
			element.growthX = (colGrowDir == "LEFT") and "LEFT" or "RIGHT"
			element.growthY = growDir
			element.maxCols = maxColCount -- oUF fallback용

			-- [12.0.1] 세로 1차 커스텀 SetPosition 오버라이드
			element.SetPosition = function(el, from, to)
				local w = el.width or el.size or 16
				local h = el.height or el.size or 16
				local sX = w + (el.spacingX or el.spacing or 0)
				local sY = h + (el.spacingY or el.spacing or 0)
				local anchor = el.initialAnchor or "BOTTOMLEFT"
				for i = from, to do
					local button = el[i]
					if not button then break end
					local row = (i - 1) % maxRows        -- 세로 인덱스 (1차)
					local col = math.floor((i - 1) / maxRows) -- 가로 인덱스 (2차)
					button:ClearAllPoints()
					button:SetPoint(anchor, el, anchor, col * sX * xSign, row * sY * ySign)
				end
			end
		else
			-- 가로 1차: oUF 기본 SetPosition 사용
			local maxCols = math_max(1, maxPerLine)
			local maxRowCount = math_max(1, math.ceil(num / maxCols))
			element:SetSize(iconSize * maxCols + hSpacing * (maxCols - 1), iconSize * maxRowCount + vSpacing * (maxRowCount - 1))

			element.growthX = (growDir == "LEFT") and "LEFT" or "RIGHT"
			element.growthY = (colGrowDir == "DOWN") and "DOWN" or "UP"
			element.maxCols = maxCols

			-- 앵커 결정: 1차(가로) + 2차(세로) 조합
			if growDir == "LEFT" and colGrowDir == "DOWN" then
				element.initialAnchor = "TOPRIGHT"
			elseif growDir == "LEFT" then
				element.initialAnchor = "BOTTOMRIGHT"
			elseif colGrowDir == "DOWN" then
				element.initialAnchor = "TOPLEFT"
			else
				element.initialAnchor = "BOTTOMLEFT"
			end

			element.SetPosition = nil -- oUF 기본 사용
		end
	end

	if buffDB then -- [12.0.1] 항상 생성 (disabled면 Hide)
		local buffs = CreateFrame("Frame", nil, self)
		local buffScale = buffDB.scale or 1.0 -- [12.0.1] 확대 비율
		local iconSize = ((buffDB.size and buffDB.size.width) or 24) * buffScale
		local num = buffDB.maxIcons or 10
		local hSpacing = (buffDB.spacing and buffDB.spacing.horizontal) or 2
		local vSpacing = (buffDB.spacing and buffDB.spacing.vertical) or 2
		local numPerLine = buffDB.numPerLine or num

		-- [FIX] 미적용 옵션 연결: position from Config
		if buffDB.position then
			local pos = buffDB.position
			buffs:SetPoint(pos.point or "BOTTOMLEFT", self, pos.relativePoint or "TOPLEFT", pos.offsetX or 0, pos.offsetY or 2)
		else
			buffs:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 5)
		end

		buffs.size = iconSize
		buffs.num = num
		buffs.spacingX = hSpacing -- [FIX] oUF 속성명 수정 (spacing-x → spacingX)
		buffs.spacingY = vSpacing -- [FIX] oUF 속성명 수정 (spacing-y → spacingY)
		buffs.spacing = hSpacing  -- oUF fallback

		-- [FIX] 1차/2차 방향 지원 (기존 orientation → growDirection + columnGrowDirection)
		local growDir = buffDB.growDirection or "RIGHT"
		local colGrowDir = buffDB.columnGrowDirection or "UP"
		-- 하위호환: 기존 orientation 값 변환
		if not buffDB.growDirection and buffDB.orientation then
			local orient = buffDB.orientation
			if orient == "RIGHT_TO_LEFT" then growDir, colGrowDir = "LEFT", "UP"
			elseif orient == "TOP_TO_BOTTOM" then growDir, colGrowDir = "DOWN", "RIGHT"
			elseif orient == "BOTTOM_TO_TOP" then growDir, colGrowDir = "UP", "RIGHT"
			else growDir, colGrowDir = "RIGHT", "UP" end
		end
		ApplyAuraGrowth(buffs, growDir, colGrowDir, numPerLine, hSpacing, vSpacing, iconSize, num)

		buffs._fontDB = buffDB.font -- [FIX] PostCreateAuraIcon에서 사용
		buffs._durationColors = buffDB.durationColors -- [12.0.1] gradient 색상
		-- [FIX] 파티/레이드 API 레벨 필터
		-- useBlizzardFilter: 모든 버프를 받아서 BlizzardBuffFilter가 결정 (DandersFrames 동일)
		-- 아닐 경우: HELPFUL|PLAYER (내가 건 버프만)
		local uk = self._unitKey
		if uk == "party" or uk == "raid" then
			local unitDB = ns.db[uk]
			local useBlizFilter = unitDB and unitDB.widgets and unitDB.widgets.buffs
				and unitDB.widgets.buffs.filter and unitDB.widgets.buffs.filter.useBlizzardFilter
			if useBlizFilter then
				buffs.filter = "HELPFUL" -- BlizzardBuffFilter가 전체 필터링
			else
				buffs.filter = "HELPFUL|PLAYER"
			end
		end
		-- oUF Auras 콜백
		buffs.PostCreateButton = PostCreateAuraIcon
		buffs.PostUpdateButton = PostUpdateAuraIcon
		buffs.FilterAura = ConfigBasedAuraFilter
		buffs.SortAuras = SortAuras

		-- [12.0.1] disabled면 숨기기
		if buffDB.enabled == false then
			buffs:Hide()
			self._buffsFrame = buffs
		else
			self.Buffs = buffs
		end
	end

	if debuffDB then -- [12.0.1] 항상 생성 (disabled면 Hide)
		local debuffs = CreateFrame("Frame", nil, self)
		local debuffScale = debuffDB.scale or 1.0 -- [12.0.1] 확대 비율
		local iconSize = ((debuffDB.size and debuffDB.size.width) or 28) * debuffScale
		local num = debuffDB.maxIcons or 8
		local hSpacing = (debuffDB.spacing and debuffDB.spacing.horizontal) or 2
		local vSpacing = (debuffDB.spacing and debuffDB.spacing.vertical) or 2
		local numPerLine = debuffDB.numPerLine or num

		local baseUnit = unit:gsub("%d", "")
		-- [FIX] 미적용 옵션 연결: position from Config
		if debuffDB.position then
			local pos = debuffDB.position
			debuffs:SetPoint(pos.point or "BOTTOMRIGHT", self, pos.relativePoint or "TOPRIGHT", pos.offsetX or 0, pos.offsetY or 2)
		elseif baseUnit == "raid" then
			debuffs:SetPoint("CENTER", self.Health, "CENTER", 0, 0)
		elseif self.Buffs then
			debuffs:SetPoint("LEFT", self.Buffs, "RIGHT", 8, 0)
		else
			debuffs:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 5)
		end

		debuffs.size = iconSize
		debuffs.num = num
		debuffs.spacingX = hSpacing -- [FIX] oUF 속성명 수정
		debuffs.spacingY = vSpacing -- [FIX] oUF 속성명 수정
		debuffs.spacing = hSpacing

		-- [FIX] 1차/2차 방향 지원
		local growDir = debuffDB.growDirection or "LEFT"
		local colGrowDir = debuffDB.columnGrowDirection or "UP"
		-- 하위호환: 기존 orientation 값 변환
		if not debuffDB.growDirection and debuffDB.orientation then
			local orient = debuffDB.orientation
			if orient == "LEFT_TO_RIGHT" then growDir, colGrowDir = "RIGHT", "UP"
			elseif orient == "TOP_TO_BOTTOM" then growDir, colGrowDir = "DOWN", "RIGHT"
			elseif orient == "BOTTOM_TO_TOP" then growDir, colGrowDir = "UP", "RIGHT"
			else growDir, colGrowDir = "LEFT", "UP" end
		end
		-- raid 중앙 배치 특수 처리
		if baseUnit == "raid" and not debuffDB.position and not debuffDB.growDirection then
			debuffs.initialAnchor = "CENTER"
		end
		ApplyAuraGrowth(debuffs, growDir, colGrowDir, numPerLine, hSpacing, vSpacing, iconSize, num)

		debuffs.showDebuffType = true
		debuffs._fontDB = debuffDB.font -- [FIX] PostCreateAuraIcon에서 사용
		debuffs._durationColors = debuffDB.durationColors -- [12.0.1] gradient 색상
		-- oUF Auras 콜백
		debuffs.PostCreateButton = PostCreateAuraIcon
		debuffs.PostUpdateButton = PostUpdateAuraIcon
		debuffs.FilterAura = ConfigBasedAuraFilter
		debuffs.SortAuras = SortAuras

		-- [12.0.1] disabled면 숨기기
		if debuffDB.enabled == false then
			debuffs:Hide()
			self._debuffsFrame = debuffs
		else
			self.Debuffs = debuffs
		end
	end

	-- [12.0.1] 개별 유닛 프레임 생존기 트래커 제거
	-- CenterDefensiveBuff API는 CompactUnitFrame(그룹 프레임)에만 존재
	-- player/target/focus 등 oUF 프레임에서는 생존기 별도 표시 불필요
end

-----------------------------------------------
-- Create Health Prediction
-----------------------------------------------

local function CreateHealthPrediction(self, settings) -- [FIX] 미적용 옵션 연결: settings 파라미터 추가
	local texture = GetTexture()
	local health = self.Health

	-- [FIX] 미적용 옵션 연결: Config에서 색상/텍스처 읽기
	local hpDB = GetWidgetSettings(settings, "healPrediction")
	local sbDB = GetWidgetSettings(settings, "shieldBar")
	local haDB = GetWidgetSettings(settings, "healAbsorb")

	-- [REFACTOR] 색상은 전역 ns.Colors에서, 텍스처는 per-unit에서
	local hpColor = (ns.Colors and ns.Colors.healPrediction and ns.Colors.healPrediction.color) or { 0, 1, 0.5, 0.4 }
	local hpTex = (hpDB and hpDB.texture) or texture
	local sbColor = (ns.Colors and ns.Colors.shieldBar and ns.Colors.shieldBar.shieldColor) or { 1, 1, 0, 0.4 }
	local sbTex = (sbDB and sbDB.texture) or texture
	local haColor = (ns.Colors and ns.Colors.healAbsorb and ns.Colors.healAbsorb.color) or { 1, 0.1, 0.1, 0.5 }
	local haTex = (haDB and haDB.texture) or texture

	-- HealthPrediction: StatusBar 기반 힐예측 바
	-- healingAll: 전체 힐 예측 (healingPlayer + healingOther 대체)
	local healingAll = CreateFrame("StatusBar", nil, health)
	healingAll:SetStatusBarTexture(hpTex)
	healingAll:GetStatusBarTexture():SetVertexColor(unpack(hpColor))
	healingAll:SetPoint("TOP")
	healingAll:SetPoint("BOTTOM")
	healingAll:SetPoint("LEFT", health:GetStatusBarTexture(), "RIGHT")
	healingAll:SetWidth(health:GetWidth())
	healingAll:SetFrameLevel(health:GetFrameLevel() + 1)

	-- damageAbsorb: 데미지 흡수량
	local damageAbsorb = CreateFrame("StatusBar", nil, health)
	damageAbsorb:SetStatusBarTexture(sbTex)
	damageAbsorb:GetStatusBarTexture():SetVertexColor(unpack(sbColor))
	damageAbsorb:SetPoint("TOP")
	damageAbsorb:SetPoint("BOTTOM")
	damageAbsorb:SetPoint("LEFT", healingAll:GetStatusBarTexture(), "RIGHT")
	damageAbsorb:SetWidth(health:GetWidth())
	damageAbsorb:SetFrameLevel(health:GetFrameLevel() + 1)

	-- healAbsorb: 힐 흡수량 (역방향, Necrotic Wound 등)
	local haPos = haDB and haDB.anchorPoint or "LEFT"
	local healAbsorb = CreateFrame("StatusBar", nil, health)
	healAbsorb:SetStatusBarTexture(haTex)
	healAbsorb:GetStatusBarTexture():SetVertexColor(unpack(haColor))
	healAbsorb:SetPoint("TOP")
	healAbsorb:SetPoint("BOTTOM")
	if haPos == "LEFT" then
		healAbsorb:SetPoint("LEFT", health:GetStatusBarTexture(), "LEFT")
		healAbsorb:SetReverseFill(false)
	else
		healAbsorb:SetPoint("RIGHT", health:GetStatusBarTexture(), "RIGHT")
		healAbsorb:SetReverseFill(true)
	end
	healAbsorb:SetWidth(health:GetWidth())
	healAbsorb:SetFrameLevel(health:GetFrameLevel() + 1)

	-- [REFACTOR] 오버힐 글로우 텍스처 (체력바 끝에 4px 얇은 글로우)
	-- Cell_UF HealPrediction 패턴: overHealGlow + overHealGlowReverse (수평/수직)
	local overHealGlow = health:CreateTexture(nil, "OVERLAY", nil, 3)
	overHealGlow:SetTexture(C.FLAT_TEXTURE)
	overHealGlow:SetVertexColor(0, 1, 0, 0)  -- 초기 투명
	overHealGlow:SetBlendMode("ADD")
	-- 수평 기본 배치 (우측 끝) — PostUpdate에서 방향에 따라 재배치
	overHealGlow:SetPoint("TOP", health)
	overHealGlow:SetPoint("BOTTOM", health)
	overHealGlow:SetPoint("RIGHT", health)
	overHealGlow:SetWidth(4)

	-- reverseFill 시 반대편 (좌측 끝)
	local overHealGlowReverse = health:CreateTexture(nil, "OVERLAY", nil, 3)
	overHealGlowReverse:SetTexture(C.FLAT_TEXTURE)
	overHealGlowReverse:SetVertexColor(0, 1, 0, 0)  -- 초기 투명
	overHealGlowReverse:SetBlendMode("ADD")
	overHealGlowReverse:SetPoint("TOP", health)
	overHealGlowReverse:SetPoint("BOTTOM", health)
	overHealGlowReverse:SetPoint("LEFT", health)
	overHealGlowReverse:SetWidth(4)
	overHealGlowReverse:Hide()

	-- [FIX] overDamageAbsorb 인디케이터: 피해흡수량이 체력바를 초과할 때 글로우 표시
	local overDamageAbsorbGlow = health:CreateTexture(nil, "OVERLAY", nil, 3)
	overDamageAbsorbGlow:SetTexture([[Interface\RaidFrame\Shield-Overshield]])
	overDamageAbsorbGlow:SetBlendMode("ADD")
	overDamageAbsorbGlow:SetPoint("TOP", health, "TOPRIGHT", -4, 3)
	overDamageAbsorbGlow:SetPoint("BOTTOM", health, "BOTTOMRIGHT", -4, -3)
	overDamageAbsorbGlow:SetWidth(8)

	local hdData = {
		healingAll = healingAll,
		damageAbsorb = damageAbsorb,
		healAbsorb = healAbsorb,
		overDamageAbsorbIndicator = overDamageAbsorbGlow,  -- [FIX] 초과 피해흡수 인디케이터
		damageAbsorbClampMode = 1,  -- [FIX] 1 = Missing Health 클램프 → 체력바 범위 내에서만 표시
		incomingHealOverflow = 1.0,
		overHealGlow = overHealGlow,
		overHealGlowReverse = overHealGlowReverse,
	}

	-- [12.0.1] disabled면 등록하지 않음
	if hpDB and hpDB.enabled == false and (not sbDB or sbDB.enabled == false) and (not haDB or haDB.enabled == false) then
		healingAll:Hide()
		damageAbsorb:Hide()
		healAbsorb:Hide()
		self._healthPredictionFrame = hdData
	else
		self.HealthPrediction = hdData
	end

	-- 오버힐 감지 → 글로우 표시 (oUF HealthPrediction PostUpdate)
	self.HealthPrediction.PostUpdate = function(element, unit)
		local glow = element.overHealGlow
		local glowReverse = element.overHealGlowReverse
		if not glow then return end

		-- [12.0.1] calculator에서 오버힐 여부 직접 판정 (secret-safe)
		-- GetIncomingHeals() → allHeal, playerHeal, otherHeal, healClamped
		-- healClamped > 0 = maxHP를 초과하는 힐량 존재
		-- 주의: healClamped 자체가 secret boolean/number일 수 있음 → issecretvalue 체크 필수
		local isOverheal = false
		if element.values then
			local ok, _, _, _, healClamped = pcall(element.values.GetIncomingHeals, element.values)
			if ok and healClamped ~= nil and not (issecretvalue and issecretvalue(healClamped)) then
				-- healClamped가 clean number인 경우에만 비교
				local clampedNum = tonumber(healClamped)
				if clampedNum then
					isOverheal = clampedNum > 0
				end
			end
		end

		-- 글로우 색상: StyleLib 악센트 또는 기본 초록
		local glowR, glowG, glowB = 0.3, 1.0, 0.5
		local _SL = _G.DDingUI_StyleLib -- [REFACTOR]
		local accent = _SL and _SL.GetAccent and _SL.GetAccent("UnitFrames")
		if accent and accent.from then
			glowR, glowG, glowB = accent.from[1] or glowR, accent.from[2] or glowG, accent.from[3] or glowB
		end

		if isOverheal then
			-- 수평 방향 기준: reverseFill이면 좌측, 아니면 우측
			local isReverse = health.GetReverseFill and health:GetReverseFill()
			if isReverse then
				glow:SetVertexColor(glowR, glowG, glowB, 0)
				glow:Hide()
				glowReverse:SetVertexColor(glowR, glowG, glowB, 0.7)
				glowReverse:Show()
			else
				glow:SetVertexColor(glowR, glowG, glowB, 0.7)
				glow:Show()
				glowReverse:SetVertexColor(glowR, glowG, glowB, 0)
				glowReverse:Hide()
			end
		else
			glow:SetVertexColor(glowR, glowG, glowB, 0)
			glow:Hide()
			glowReverse:SetVertexColor(glowR, glowG, glowB, 0)
			glowReverse:Hide()
		end
	end
end

-----------------------------------------------
-- Create Custom Text -- [12.0.1]
-- Config: settings.widgets.customText
-----------------------------------------------

local function CreateCustomText(self, unit, settings)
	local ctDB = GetWidgetSettings(settings, "customText")
	if not ctDB then return end

	self._customTexts = {}
	for key, textDB in pairs(ctDB.texts or {}) do
		local ctParent = self.TextOverlay or self.Health -- [FIX] 오버레이 프레임 사용
		local fs = ctParent:CreateFontString(nil, "OVERLAY")
		local font, fontSize, fontFlags = GetFont()
		local tFont = textDB.font
		fs:SetFont(
			(tFont and tFont.style) or font,
			(tFont and tFont.size) or fontSize,
			(tFont and tFont.outline) or fontFlags
		)
		if textDB.position then
			local pos = textDB.position
			fs:SetPoint(pos.point or "CENTER", self.Health, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 0)
		else
			fs:SetPoint("CENTER", self.Health, "CENTER", 0, 0)
		end
		fs:SetJustifyH((tFont and tFont.justify) or "CENTER")

		local tag = MigrateTagString(textDB.textFormat or "")
		if tag ~= textDB.textFormat then textDB.textFormat = tag end -- DB도 업데이트
		if tag ~= "" and IsValidCustomTag(tag) then
			self:Tag(fs, tag)
			-- [FIX] 즉시 태그 평가 → 텍스트 표시
			if fs.UpdateTag then fs:UpdateTag() end
		end

		-- [12.0.1] disabled면 숨기기
		if not textDB.enabled or not (textDB.textFormat and textDB.textFormat ~= "") then
			fs:Hide()
		end

		self._customTexts[key] = fs
	end
end

-----------------------------------------------
-- Create Indicators (Raid/Group)
-----------------------------------------------

local function CreateIndicators(self, unit, settings)
	local baseUnit = unit:gsub("%d", "")

	-- [REFACTOR] 아이콘 세트 참조
	local iconSet = C.ICON_SETS[ns.db.iconSet or "default"] or C.ICON_SETS["default"]

	-- [FIX] 미적용 옵션 연결: Config에서 크기/위치 읽기
	local raidIconDB = GetWidgetSettings(settings, "raidIcon")
	local roleIconDB = GetWidgetSettings(settings, "roleIcon")
	local readyCheckDB = GetWidgetSettings(settings, "readyCheckIcon")
	local resurrectDB = GetWidgetSettings(settings, "resurrectIcon")
	local leaderDB = GetWidgetSettings(settings, "leaderIcon")

	-- Raid Target Icon - Health 위에 표시 (sublevel 7)
	local riSize = (raidIconDB and raidIconDB.size and raidIconDB.size.width) or 14
	local raidIcon = self.Health:CreateTexture(nil, "OVERLAY", nil, 7)
	raidIcon:SetSize(riSize, riSize)
	if raidIconDB and raidIconDB.position then
		local pos = raidIconDB.position
		raidIcon:SetPoint(pos.point or "TOP", self.Health, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 12)
	else
		raidIcon:SetPoint("CENTER", self.Health, "TOP", 0, 0)
	end
	if raidIconDB and raidIconDB.enabled == false then
		raidIcon:Hide()
		self._raidTargetIndicatorFrame = raidIcon
	else
		self.RaidTargetIndicator = raidIcon
	end

	-- Group Role (tank/healer/dps) - Health 위에 표시 (sublevel 7)
	if baseUnit == "party" or baseUnit == "raid" or baseUnit == "player" then
		local roSize = (roleIconDB and roleIconDB.size and roleIconDB.size.width) or 14
		local roleIcon = self.Health:CreateTexture(nil, "OVERLAY", nil, 7)
		roleIcon:SetSize(roSize, roSize)
		if roleIconDB and roleIconDB.position then
			local pos = roleIconDB.position
			roleIcon:SetPoint(pos.point or "TOPRIGHT", self, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 0)
		else
			local roleOffset = 2
			roleIcon:SetPoint("TOPLEFT", self, "TOPLEFT", roleOffset, -roleOffset)
		end
		-- [REFACTOR] 아이콘 세트 기반 역할 텍스처/좌표 (개별 텍스처 모드 지원)
		local roleSetData = iconSet.role
		if roleSetData.texture then
			roleIcon:SetTexture(roleSetData.texture)
		end
		-- oUF GroupRoleIndicator Override 콜백
		roleIcon.UpdateRole = function(frame, event)
			local element = frame.GroupRoleIndicator
			local role = UnitGroupRolesAssigned(frame.unit)
			-- 그룹 역할이 없으면 전문화 기반 역할 사용
			if (not role or role == "NONE") and frame.unit == "player" then
				local specIndex = GetSpecialization()
				if specIndex then
					role = GetSpecializationRole(specIndex) or "NONE"
				end
			end
			-- [REFACTOR] 런타임 아이콘 세트 참조 (개별 텍스처 모드 지원)
			local curSet = C.ICON_SETS[ns.db.iconSet or "default"] or C.ICON_SETS["default"]
			if curSet.role.textures and curSet.role.textures[role] then
				element:SetTexture(curSet.role.textures[role])
				element:SetTexCoord(0, 1, 0, 1)
				element:Show()
			elseif curSet.role.coords and curSet.role.coords[role] then
				element:SetTexture(curSet.role.texture)
				element:SetTexCoord(unpack(curSet.role.coords[role]))
				element:Show()
			else
				element:Hide()
			end
		end
		if roleIconDB and roleIconDB.enabled == false then
			roleIcon:Hide()
			self._groupRoleIndicatorFrame = roleIcon
		else
			self.GroupRoleIndicator = roleIcon
		end
	end

	-- Ready Check - Health 위에 표시 (sublevel 7)
	if baseUnit == "player" or baseUnit == "party" or baseUnit == "raid" then
		local rcSize = (readyCheckDB and readyCheckDB.size and readyCheckDB.size.width) or 16
		local readyCheck = self.Health:CreateTexture(nil, "OVERLAY", nil, 7)
		readyCheck:SetSize(rcSize, rcSize)
		if readyCheckDB and readyCheckDB.position then
			local pos = readyCheckDB.position
			readyCheck:SetPoint(pos.point or "CENTER", self, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 0)
		else
			readyCheck:SetPoint("CENTER", self, "CENTER", 0, 0)
		end
		if readyCheckDB and readyCheckDB.enabled == false then
			readyCheck:Hide()
			self._readyCheckIndicatorFrame = readyCheck
		else
			self.ReadyCheckIndicator = readyCheck
		end
	end

	-- Resurrect - Health 위에 표시 (sublevel 7)
	if baseUnit == "player" or baseUnit == "party" or baseUnit == "raid" then
		local resSize = (resurrectDB and resurrectDB.size and resurrectDB.size.width) or 20
		local resurrect = self.Health:CreateTexture(nil, "OVERLAY", nil, 7)
		resurrect:SetSize(resSize, resSize)
		if resurrectDB and resurrectDB.position then
			local pos = resurrectDB.position
			resurrect:SetPoint(pos.point or "CENTER", self, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 0)
		else
			resurrect:SetPoint("CENTER", self, "CENTER", 0, 0)
		end
		if resurrectDB and resurrectDB.enabled == false then
			resurrect:Hide()
			self._resurrectIndicatorFrame = resurrect
		else
			self.ResurrectIndicator = resurrect
		end
	end

	-- Leader Icon - Health 위에 표시 (sublevel 7)
	-- [FIX] 항상 생성 (런타임 enable/disable 지원 - reload 불필요)
	if baseUnit == "party" or baseUnit == "raid" or baseUnit == "player" then
		local ldSize = (leaderDB and leaderDB.size and leaderDB.size.width) or 14
		local leader = self.Health:CreateTexture(nil, "OVERLAY", nil, 7)
		leader:SetSize(ldSize, ldSize)
		leader:SetTexture(iconSet.leader) -- [REFACTOR] 아이콘 세트 적용
		leader._iconSetTexture = iconSet.leader -- [REFACTOR] oUF Update에서 커스텀 텍스처 유지
		if leaderDB and leaderDB.position then
			local pos = leaderDB.position
			leader:SetPoint(pos.point or "TOPLEFT", self, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 12)
		else
			leader:SetPoint("TOPLEFT", self, "TOPLEFT", 2, 2)
		end
		if leaderDB and leaderDB.enabled == false then
			leader:Hide()
			self._leaderIndicatorFrame = leader
		else
			self.LeaderIndicator = leader
		end
	end

	-- Combat Indicator (player only)
	-- [FIX] 항상 생성 (런타임 enable/disable 지원)
	if baseUnit == "player" then
		local combatDB = GetWidgetSettings(settings, "combatIcon")
		local cbSize = (combatDB and combatDB.size and combatDB.size.width) or 20
		local combat = self.Health:CreateTexture(nil, "OVERLAY", nil, 7)
		combat:SetSize(cbSize, cbSize)
		combat:SetTexture(iconSet.combat) -- [REFACTOR] 아이콘 세트 적용
		if iconSet.combatCoords then
			combat:SetTexCoord(unpack(iconSet.combatCoords))
		end
		if combatDB and combatDB.position then
			local pos = combatDB.position
			combat:SetPoint(pos.point or "CENTER", self, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 0)
		else
			combat:SetPoint("CENTER", self, "CENTER", 0, 0)
		end
		if combatDB and combatDB.enabled == false then
			combat:Hide()
			self._combatIndicatorFrame = combat
		else
			self.CombatIndicator = combat
		end
	end

	-- Resting Indicator (player only)
	-- [FIX] 항상 생성 (런타임 enable/disable 지원)
	if baseUnit == "player" then
		local restDB = GetWidgetSettings(settings, "restingIcon")
		local rstSize = (restDB and restDB.size and restDB.size.width) or 18
		local resting = self.Health:CreateTexture(nil, "OVERLAY", nil, 7)
		resting:SetSize(rstSize, rstSize)
		-- [REFACTOR] 커스텀 아이콘 세트 텍스처 적용
		resting._iconSetTexture = iconSet.resting
		if iconSet.restingCoords then
			resting._iconSetCoords = iconSet.restingCoords
		end
		if restDB and restDB.position then
			local pos = restDB.position
			resting:SetPoint(pos.point or "TOPLEFT", self, pos.relativePoint or "CENTER", pos.offsetX or -15, pos.offsetY or 10)
		else
			resting:SetPoint("TOPLEFT", self, "TOPLEFT", -15, 10)
		end
		
		if restDB and restDB.enabled == false then
			resting:Hide()
			self._restingIndicatorFrame = resting
		else
			self.RestingIndicator = resting
		end

		-- hideAtMaxLevel: oUF RestingIndicator PostUpdate 콜백
		if restDB and restDB.hideAtMaxLevel then
			self.RestingIndicator.PostUpdate = function(element, isResting)
				if isResting then
					local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or MAX_PLAYER_LEVEL or 80
					if UnitLevel("player") >= maxLevel then
						element:Hide()
					end
				end
			end
		end
	end

	-- Threat (glow border effect)
	if baseUnit == "party" or baseUnit == "raid" then
		local threat = CreateFrame("Frame", nil, self, "BackdropTemplate")
		local threatBorder = 2 -- [REFACTOR] raw pixel
		threat:SetPoint("TOPLEFT", -threatBorder, threatBorder)
		threat:SetPoint("BOTTOMRIGHT", threatBorder, -threatBorder)
		threat:SetFrameLevel(math_max(0, self:GetFrameLevel() - 2))
		threat:SetBackdrop({
			edgeFile = C.FLAT_TEXTURE,
			edgeSize = threatBorder,
		})
		threat:SetBackdropBorderColor(0, 0, 0, 0)
		threat:Hide()

		-- [FIX] 미적용 옵션 연결: threat Config 참조 저장
		local threatDB = GetWidgetSettings(settings, "threat")
		if threatDB and threatDB.enabled == false then
			self._threatIndicatorFrame = threat
		else
			self.ThreatIndicator = threat
			if threatDB then
				self.ThreatIndicator._colors = threatDB.colors
				self.ThreatIndicator._style = threatDB.style
			end
		end

		-- oUF ThreatIndicator PostUpdate 콜백
		self.ThreatIndicator.PostUpdate = function(element, unit, status, color)
			local r, g, b
			-- [FIX] 미적용 옵션 연결: Config threat.colors 우선 적용
			if element._colors and status and element._colors[status] then
				local cc = element._colors[status]
				r, g, b = cc[1], cc[2], cc[3]
			elseif color then
				r, g, b = color:GetRGB()
			end

			if status and status > 0 then
				element:SetBackdropBorderColor(r or 1, g or 0, b or 0, 0.8)
				element:Show()
				-- Aggro on health bar (옵션)
				local frame = element:GetParent()
				if ns.db.aggroOnHealthBar and frame and frame.Health then
					frame.Health._threatOverride = { r or 1, g or 0, b or 0 }
					frame.Health:SetStatusBarColor(r or 1, g or 0, b or 0)
				end
			else
				element:Hide()
				-- Threat 해제 → health 색상 복구
				local frame = element:GetParent()
				if frame and frame.Health and frame.Health._threatOverride then
					frame.Health._threatOverride = nil
					-- oUF Health ForceUpdate로 색상 복구
				end
			end
		end
	end
end

-----------------------------------------------
-- Create Range Check
-----------------------------------------------

local function CreateRange(self)
	-- oUF Range element
	local oorAlpha = (ns.db and ns.db.outOfRangeAlpha) or C.OUT_OF_RANGE_ALPHA
	self.Range = {
		insideAlpha = 1,
		outsideAlpha = oorAlpha,
	}
end

-----------------------------------------------
-- Create ClassPower (Combo Points, Holy Power, etc.)
-- Config: settings.widgets.classBar
-----------------------------------------------

local function CreateClassPower(self, settings)
	local cpDB = GetWidgetSettings(settings, "classBar")
	if not cpDB or cpDB.enabled == false then return end

	local cpHeight = (cpDB.size and cpDB.size.height) or 4
	local maxPower = 10
	-- [FIX] 미적용 옵션 연결: classBar.texture
	local cpTexture = cpDB.texture and cpDB.texture or GetTexture()

	local bars = {}

	for i = 1, maxPower do
		local bar = CreateFrame("StatusBar", nil, self)
		bar:SetStatusBarTexture(cpTexture)
		bar:SetStatusBarColor(unpack(C.CLASSPOWER_COLORS.COMBO_POINTS))
		bar:SetHeight(cpHeight)
		bar:SetFrameLevel(self:GetFrameLevel() + 5)

		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetTexture(GetTexture())
		bg:SetVertexColor(0.08, 0.08, 0.08)

		bars[i] = bar
	end

	local function PostUpdate(element, cur, max, hasMaxChanged, powerType)
		if not max or max == 0 then
			for i = 1, #element do
				element[i]:Hide()
			end
			return
		end

		-- [FIX] 미적용 옵션 연결: Config spacing/sameSizeAsHealthBar
		local totalWidth = self:GetWidth() - 2
		if cpDB.sameSizeAsHealthBar ~= false and self.Health then
			totalWidth = self.Health:GetWidth()
		end
		local gap = cpDB.spacing or 1
		local barWidth = (totalWidth - (max - 1) * gap) / max

		for i = 1, max do
			element[i]:ClearAllPoints()
			element[i]:SetWidth(barWidth)
			element[i]:Show()

			if i == 1 then
				-- [FIX] 미적용 옵션 연결: classBar.position
				if cpDB.position then
					local pos = cpDB.position
					element[i]:SetPoint(pos.point or "BOTTOMLEFT", self, pos.relativePoint or "TOPLEFT", pos.offsetX or 0, pos.offsetY or 2)
				else
					element[i]:SetPoint("BOTTOMLEFT", self.Health, "TOPLEFT", 0, 1)
				end
			else
				element[i]:SetPoint("LEFT", element[i - 1], "RIGHT", gap, 0)
			end

			local color = C.CLASSPOWER_COLORS[powerType] or C.CLASSPOWER_COLORS.COMBO_POINTS
			element[i]:SetStatusBarColor(unpack(color))
		end

		for i = max + 1, #element do
			element[i]:Hide()
		end
	end

	bars.PostUpdate = PostUpdate
	self.ClassPower = bars
end

-----------------------------------------------
-- Highlight System (Target/Focus/Hover borders)
-- [12.0.1] Target/Focus/Hover 보더 (SOLID)
-- Frame levels: Focus(+8), Target/Selection(+9), Hover(+10)
-----------------------------------------------

-- 하이라이트 보더 프레임 생성 (BackdropTemplate SOLID)
local function CreateHighlightBorder(parent, levelOffset)
	local thickness = F:ScalePixel(C.BORDER_SIZE)
	local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -thickness, thickness)
	border:SetPoint("BOTTOMRIGHT", thickness, -thickness)
	border:SetFrameLevel(math_max(0, parent:GetFrameLevel() + levelOffset))
	border:SetBackdrop({
		edgeFile = C.FLAT_TEXTURE,
		edgeSize = thickness,
	})
	border:SetBackdropBorderColor(1, 1, 1, 1)
	border:Hide()
	return border
end

-- [12.0.1] 하이라이트 프레임 생성
local function CreateHighlight(self, settings)
	local hlDB = GetWidgetSettings(settings, "highlight")
	if not hlDB or hlDB.enabled == false then return end

	local highlight = {}
	highlight._db = hlDB

	-- 1. Target 보더 (frameLevel + 9) -- [12.0.1]
	if hlDB.target then
		highlight.target = CreateHighlightBorder(self, C.HIGHLIGHT_LEVELS.TARGET)
	end

	-- 2. Focus 보더 (frameLevel + 8) -- [12.0.1]
	if hlDB.focus then
		highlight.focus = CreateHighlightBorder(self, C.HIGHLIGHT_LEVELS.FOCUS)
	end

	-- 3. Hover 보더 (frameLevel + 10) -- [12.0.1]
	if hlDB.hover then
		highlight.hover = CreateHighlightBorder(self, C.HIGHLIGHT_LEVELS.HOVER)

		-- 체력바 오버레이 (mouseover 시각 피드백)
		local overlayTex = self.Health:CreateTexture(nil, "OVERLAY", nil, 1)
		overlayTex:SetAllPoints()
		overlayTex:SetTexture(C.FLAT_TEXTURE)
		overlayTex:SetVertexColor(1, 1, 1, 0)
		self.highlightTex = overlayTex
	end

	-- OnEnter/OnLeave (Hover 스크립트 처리)
	self:SetScript("OnEnter", function(frame)
		if frame.highlightTex then
			frame.highlightTex:SetVertexColor(1, 1, 1, 0.08)
		end
		if frame.Highlight and frame.Highlight.hover and hlDB.hover then
			-- [FIX] ns.Colors.highlight.hover 글로벌 색상 우선 적용
			local color = (ns.Colors and ns.Colors.highlight and ns.Colors.highlight.hover) or hlDB.hoverColor or { 1, 1, 1, 0.3 }
			frame.Highlight.hover:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
			frame.Highlight.hover:Show()
		end
		if frame.unit then
			UnitFrame_OnEnter(frame)
		end
	end)

	self:SetScript("OnLeave", function(frame)
		if frame.highlightTex then
			frame.highlightTex:SetVertexColor(1, 1, 1, 0)
		end
		if frame.Highlight and frame.Highlight.hover then
			frame.Highlight.hover:Hide()
		end
		UnitFrame_OnLeave(frame)
	end)

	-- oUF Highlight element
	self.Highlight = highlight
end

-----------------------------------------------
-- Status Text Overlay (Dead/Offline/AFK)
-----------------------------------------------

local function CreateStatusText(self)
	local font, fontSize, fontFlags = GetFont()

	local stParent = self.TextOverlay or self.Health -- [FIX] 오버레이 프레임 사용
	local statusText = stParent:CreateFontString(nil, "OVERLAY", nil, 5)
	statusText:SetFont(font, fontSize, fontFlags)
	statusText:SetPoint("CENTER", self.Health, "CENTER", 0, 0)
	statusText:SetTextColor(0.8, 0.8, 0.8)
	-- [ESSENTIAL] StatusText는 항상 그림자 (설정 없음)
	statusText:SetShadowColor(0, 0, 0, 1)
	statusText:SetShadowOffset(1, -1)

	self:Tag(statusText, "[ddingui:status]")
	self.StatusText = statusText
end

-----------------------------------------------
-- Main Style Function
-----------------------------------------------

function Layout:StyleUnit(self, unit)
	if not unit then
		unit = self:GetAttribute("unit")
	end
	if not unit then
		unit = "party"
	end

	-- [FIX] 파티/레이드 헤더 자식: _unitKey 설정 (player→party 매핑)
	local parentFrame = self:GetParent()
	if parentFrame then
		local headerName = parentFrame:GetName()
		if headerName then
			if headerName:find("ddingUI_Party") then
				self._unitKey = "party"
			elseif headerName:find("ddingUI_Raid") then
				self._unitKey = "raid"
			end
		end
	end
	if not self._unitKey then
		self._unitKey = unit:gsub("%d+$", "")
	end

	local baseUnit = unit:gsub("%d", "")
	local settings = ns.Config:GetUnitSettings(baseUnit)

	-- Frame size (Config: settings.size = { width, height })
	local frameW = (settings.size and settings.size[1]) or 200
	local frameH = (settings.size and settings.size[2]) or 40
	self:SetSize(frameW, frameH)

	-- Click targeting
	self:RegisterForClicks("AnyUp")
	self:SetAttribute("type", "target")
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")

	-- [FIX] WoW 템플릿(PingableUnitFrameTemplate 등) 기본 텍스처 제거
	-- Button 프레임이 가질 수 있는 기본 NormalTexture/HighlightTexture 숨기기
	if self.SetNormalTexture then self:SetNormalTexture("") end
	if self.SetHighlightTexture then self:SetHighlightTexture("") end
	if self.SetPushedTexture then self:SetPushedTexture("") end
	-- WoW 11.x 선택 하이라이트 / NineSlice 제거
	if self.selectionHighlight then self.selectionHighlight:SetAlpha(0) end
	if self.Selection then self.Selection:SetAlpha(0) end
	if self.NineSlice then self.NineSlice:SetAlpha(0) end

	-- Frame backdrop (1px black border + dark bg)
	CreateFrameBackdrop(self)

	-- Health bar
	CreateHealthBar(self, unit, settings)

	-- Power bar
	CreatePowerBar(self, unit, settings)

	-- [FIX] 텍스트 오버레이 프레임: Health/Power 위에 텍스트가 보이도록
	-- FontString은 부모 프레임의 레벨에 종속 → Power bar 프레임 아래로 가려짐
	-- 별도 오버레이 프레임을 높은 레벨로 생성하여 텍스트를 항상 위에 표시
	if not self.TextOverlay then
		local overlay = CreateFrame("Frame", nil, self)
		overlay:SetAllPoints(self)
		overlay:SetFrameLevel(self:GetFrameLevel() + 10) -- Power/Aura 프레임보다 위
		self.TextOverlay = overlay
	end

	-- Alt Power bar (대체 자원바 - 보스전) + Additional Power (보조 자원바 - 드루이드 마나 등) -- [REFACTOR]
	if baseUnit == "player" then
		CreateAltPowerBar(self, unit, settings)
		CreateAdditionalPower(self, unit, settings)
	end

	-- Name text
	CreateNameText(self, unit, settings)

	-- Health text (individual frames only)
	if baseUnit == "player" or baseUnit == "target" or baseUnit == "focus" or baseUnit == "boss" or baseUnit == "arena" then
		CreateHealthText(self, unit, settings)
	end

	-- Power text (individual frames only) -- [12.0.1]
	if baseUnit == "player" or baseUnit == "target" or baseUnit == "focus" then
		CreatePowerText(self, unit, settings)
	end

	-- Party: health percent on right -- [12.0.1] Config 태그 지원
	if baseUnit == "party" then
		-- [FIX] 기존 HealthText 정리 (/reload 스택 방지)
		if self.HealthText then
			self.HealthText:SetText("")
			self.HealthText:Hide()
		end
		local font, fontSize, fontFlags = GetFont()
		local partyTextParent = self.TextOverlay or self.Health -- [FIX] 오버레이 프레임 사용
		local hpText = partyTextParent:CreateFontString(nil, "OVERLAY")
		hpText:SetFont(font, fontSize - 1, fontFlags)
		hpText:SetPoint("RIGHT", self.Health, "RIGHT", -3, 0)
		hpText:SetJustifyH("RIGHT")
		hpText:SetShadowColor(0, 0, 0, 1)
		hpText:SetShadowOffset(1, -1)
		-- [ElvUI 패턴] 포맷별 태그 문자열로 등록
		self.HealthText = hpText
		local partyHtFmt = (settings.widgets and settings.widgets.healthText and settings.widgets.healthText.format) or "percentage"
		local partyHtTagMap = ns.HEALTH_FORMAT_TO_TAG
		local partyHtTagStr = (partyHtTagMap and partyHtTagMap[partyHtFmt]) or "[ddingui:ht:pct]"
		-- [FIX] healthText 색상 타입에 따른 태그 프리픽스 추가
		local partyHtDB = settings.widgets and settings.widgets.healthText
		local partyHtColorType = partyHtDB and partyHtDB.color and partyHtDB.color.type or "custom"
		if partyHtColorType == "class_color" then
			partyHtTagStr = "[ddingui:classcolor]" .. partyHtTagStr .. "|r"
		elseif partyHtColorType == "reaction_color" then
			partyHtTagStr = "[ddingui:reactioncolor]" .. partyHtTagStr .. "|r"
		elseif partyHtColorType == "power_color" then
			partyHtTagStr = "[ddingui:powercolor]" .. partyHtTagStr .. "|r"
		end
		self:Tag(hpText, partyHtTagStr)
	end

	-- Castbar -- [12.0.1] party/raid 제외 (인스턴스 secret value → Backdrop 크래시 방지)
	if baseUnit ~= "party" and baseUnit ~= "raid" then
		local castBarDB = GetWidgetSettings(settings, "castBar")
		if castBarDB then
			CreateCastbar(self, unit, castBarDB, frameW)
		end
	end

	-- Auras
	CreateAuras(self, unit, settings)

	-- Health Prediction (player, party, raid, focus)
	if baseUnit == "player" or baseUnit == "party" or baseUnit == "raid" or baseUnit == "focus" then
		CreateHealthPrediction(self, settings) -- [FIX] 미적용 옵션 연결: settings 전달
	end

	-- ClassPower (player only)
	if baseUnit == "player" then
		CreateClassPower(self, settings)
	end

	-- Custom Text -- [12.0.1]
	CreateCustomText(self, unit, settings)

	-- Indicators
	CreateIndicators(self, unit, settings)

	-- Range (group frames)
	if baseUnit == "party" or baseUnit == "raid" then
		CreateRange(self)
	end

	-- Status text (raid/party)
	if baseUnit == "party" or baseUnit == "raid" then
		CreateStatusText(self)
	end

	-- PrivateAuras (per-unit 설정 우선, 글로벌 fallback)
	-- [12.0.1] 새 DB 구조: size.width/height, spacing.horizontal/vertical, scale, position, columnGrowDirection
	-- [12.0.1] boss/arena는 프라이빗 오라 미지원 (적 유닛에 불필요)
	do
		local paDB = (baseUnit ~= "boss" and baseUnit ~= "arena")
			and ((settings and settings.widgets and settings.widgets.privateAuras)
				or (ns.db and ns.db.privateAuras))
		if paDB and paDB.enabled ~= false then
			local paScale = paDB.scale or 1.0
			local sizeDB = paDB.size or {}
			local iconW = (sizeDB.width or paDB.iconSize or 24) * paScale -- [12.0.1] iconSize 하위호환
			local iconH = (sizeDB.height or paDB.iconSize or 24) * paScale
			local num = paDB.maxAuras or 2
			-- [12.0.1] spacing: 테이블 또는 숫자 (하위호환)
			local hSpacing, vSpacing
			if type(paDB.spacing) == "table" then
				hSpacing = paDB.spacing.horizontal or 2
				vSpacing = paDB.spacing.vertical or 2
			else
				hSpacing = paDB.spacing or 2
				vSpacing = paDB.spacing or 2
			end
			local growDir = paDB.growDirection or "RIGHT"
			local container = CreateFrame("Frame", nil, self)

			-- [FIX] growDirection → oUF growthX/growthY/initialAnchor 매핑
			local isVertical = (growDir == "DOWN" or growDir == "UP")
			if growDir == "LEFT" then
				container.growthX = "LEFT"
				container.growthY = "UP"
				container.initialAnchor = "RIGHT"
				container:SetSize(iconW * num + hSpacing * (num - 1), iconH)
			elseif growDir == "DOWN" then
				container.growthX = "RIGHT"
				container.growthY = "DOWN"
				container.initialAnchor = "TOP"
				container:SetSize(iconW, iconH * num + vSpacing * (num - 1))
			elseif growDir == "UP" then
				container.growthX = "RIGHT"
				container.growthY = "UP"
				container.initialAnchor = "BOTTOM"
				container:SetSize(iconW, iconH * num + vSpacing * (num - 1))
			else -- RIGHT
				container.growthX = "RIGHT"
				container.growthY = "UP"
				container.initialAnchor = "LEFT"
				container:SetSize(iconW * num + hSpacing * (num - 1), iconH)
			end

			-- [12.0.1] position DB 적용
			if paDB.position then
				local pos = paDB.position
				container:SetPoint(pos.point or "CENTER", self.Health, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 0)
			else
				container:SetPoint("CENTER", self.Health, "CENTER", 0, 0)
			end
			container.size = iconW -- oUF PrivateAuras element
			container.num = num
			container.spacingX = hSpacing
			container.spacingY = vSpacing
			container.maxCols = isVertical and 1 or num
			self.PrivateAuras = container
		end
	end

	-- DispelHighlight (party, raid, target, focus) -- [12.0.1] 4가지 모드: border, glow, gradient, icon
	if baseUnit == "party" or baseUnit == "raid" or baseUnit == "target" or baseUnit == "focus" then
		local dhDB = ns.db and ns.db.dispelHighlight
		if dhDB and dhDB.enabled ~= false then
			-- 메인 프레임 (border 모드용 BackdropTemplate)
			local dispelHL = CreateFrame("Frame", nil, self, "BackdropTemplate")
			local dhBorder = 2 -- [REFACTOR] raw pixel
			dispelHL:SetPoint("TOPLEFT", -dhBorder, dhBorder)
			dispelHL:SetPoint("BOTTOMRIGHT", dhBorder, -dhBorder)
			dispelHL:SetFrameLevel(math_max(0, self:GetFrameLevel() - 1))
			dispelHL:SetBackdrop({
				edgeFile = C.FLAT_TEXTURE,
				edgeSize = dhBorder,
			})
			dispelHL:SetBackdropBorderColor(0, 0, 0, 0)
			dispelHL:Hide()

			-- 설정값 전달 -- [12.0.1]
			dispelHL.onlyShowDispellable = dhDB.onlyShowDispellable ~= false
			dispelHL._mode = dhDB.mode or "border"            -- [12.0.1]
			dispelHL._glowType = dhDB.glowType or "pixel"     -- [12.0.1]
			dispelHL._glowThickness = dhDB.glowThickness or 2 -- [12.0.1]
			dispelHL._gradientAlpha = dhDB.gradientAlpha or 0.4 -- [12.0.1]
			dispelHL._iconSize = dhDB.iconSize or 14           -- [12.0.1]
			dispelHL._iconPosition = dhDB.iconPosition or "TOPRIGHT" -- [12.0.1]
			dispelHL._colors = dhDB.colors                         -- [FIX] 커스텀 색상 테이블

			self.DispelHighlight = dispelHL
		end
	end

	-- Highlight system (Target/Focus/Hover borders) -- [12.0.1]
	CreateHighlight(self, settings)
end
