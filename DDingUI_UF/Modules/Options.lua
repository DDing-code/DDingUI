--[[
	ddingUI UnitFrames
	Modules/Options.lua - Cell_UnitFrames 스타일 상세 옵션 패널
]]

local ADDON_NAME, ns = ...
local Widgets = ns.Widgets
local Config = ns.Config

local Options = {}
ns.Options = Options

-- LibSharedMedia
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-----------------------------------------------
-- Forward Declarations
-----------------------------------------------
local LoadPage  -- [FIX] 파일 후반부(Search System)에서 할당, 전역 참조 방지
local ShowTagReference, HideTagReference  -- Tag Reference Panel 섹션에서 할당

-----------------------------------------------
-- Constants
-----------------------------------------------
local PANEL_WIDTH = 920
local PANEL_HEIGHT = 620
local SIDEBAR_WIDTH = 200
local CONTENT_WIDTH = PANEL_WIDTH - SIDEBAR_WIDTH - 20
local TOPBAR_HEIGHT = 30
-- [12.0.1] Preview 시스템 제거 → TestMode로 대체

-----------------------------------------------
-- Unit Names
-----------------------------------------------
local UnitNames = {
	player = "플레이어",
	target = "대상",
	targettarget = "대상의 대상",
	focus = "주시 대상",
	focustarget = "주시 대상의 대상",
	pet = "소환수",
	boss = "우두머리",
	arena = "투기장",
	party = "파티",
	raid = "공격대",
	mythicRaid = "신화 공격대",
}

local WidgetNames = {
	nameText = "이름",
	healthText = "체력 텍스트",
	powerText = "자원 텍스트",
	levelText = "레벨 텍스트",
	customText = "사용자 정의 텍스트",
	buffs = "버프",
	debuffs = "디버프",
	dispels = "해제",
	raidIcon = "공격대 아이콘",
	roleIcon = "역할 아이콘",
	leaderIcon = "파티장 아이콘",
	combatIcon = "전투 아이콘",
	readyCheckIcon = "준비 확인",
	restingIcon = "휴식 아이콘",
	resurrectIcon = "부활 아이콘",
	summonIcon = "소환 아이콘",
	shieldBar = "보호막 바",
	castBar = "시전바",
	classBar = "직업 자원",
	altPowerBar = "대체 자원 바",
	powerBar = "자원 바",
	healPrediction = "치유 예측",
	healAbsorb = "치유 흡수",
	fader = "페이드",
	highlight = "하이라이트",
	threat = "위협",
}

-----------------------------------------------
-- Shared Dropdown Data
-----------------------------------------------

-- LSM에서 텍스처 리스트를 동적으로 생성
local function GetTextureList()
	local list = {}
	if LSM then
		local names = LSM:List(LSM.MediaType.STATUSBAR)
		if names then
			for _, name in ipairs(names) do
				table.insert(list, { text = name, value = LSM:Fetch(LSM.MediaType.STATUSBAR, name) })
			end
		end
	end
	-- 최소 1개 보장 (LSM 없을 때)
	if #list == 0 then
		list = {
			{ text = "단색 (기본)", value = [[Interface\Buttons\WHITE8x8]] },
			{ text = "Blizzard", value = [[Interface\TargetingFrame\UI-StatusBar]] },
			{ text = "Blizzard Raid", value = [[Interface\RaidFrame\Raid-Bar-Hp-Fill]] },
			{ text = "Minimalist", value = [[Interface\TargetingFrame\UI-TargetingFrame-BarFill]] },
		}
	end
	return list
end

-- LSM에서 폰트 리스트를 동적으로 생성
local function GetFontList()
	local list = {}
	if LSM then
		local names = LSM:List(LSM.MediaType.FONT)
		if names then
			for _, name in ipairs(names) do
				table.insert(list, { text = name, value = LSM:Fetch(LSM.MediaType.FONT, name) })
			end
		end
	end
	if #list == 0 then
		list = {
			{ text = "기본 글꼴", value = [[Fonts\2002.TTF]] },
			{ text = "굵은 글꼴", value = [[Fonts\2002B.TTF]] },
			{ text = "Friz Quadrata", value = [[Fonts\FRIZQT__.TTF]] },
		}
	end
	return list
end

-- LSM 이름으로 경로 찾기 (역방향)
local function FindLSMName(mediaType, path)
	if not LSM or not path then return nil end
	local hashTable = LSM:HashTable(mediaType)
	if hashTable then
		for name, p in pairs(hashTable) do
			if p == path then return name end
		end
	end
	return nil
end

local OrientationList = {
	{ text = "왼→오", value = "LEFT_TO_RIGHT" },
	{ text = "오→왼", value = "RIGHT_TO_LEFT" },
	{ text = "위→아래", value = "TOP_TO_BOTTOM" },
	{ text = "아래→위", value = "BOTTOM_TO_TOP" },
}

local HealthFormatList = {
	{ text = "퍼센트", value = "percentage" },
	{ text = "현재값", value = "current" },
	{ text = "현재/최대", value = "current-max" },
	{ text = "손실량", value = "deficit" },
	{ text = "현재 (퍼센트)", value = "current-percentage" },
	{ text = "퍼센트 | 현재값", value = "percent-current" }, -- [UF-OPTIONS]
	{ text = "현재값 | 퍼센트", value = "current-percent" }, -- [UF-OPTIONS]
}

-- [UF-OPTIONS] separator 선택 목록
local SeparatorList = {
	{ text = "/", value = "/" },
	{ text = "|", value = " | " },
	{ text = "-", value = " - " },
	{ text = "·", value = " · " },
}

local NameFormatList = {
	{ text = "이름", value = "name" },
	{ text = "이름 (약어)", value = "name:abbrev" },
	{ text = "이름 (짧게)", value = "name:short" },
}

-- Helper: set enabled state for child controls
local function SetChildrenEnabled(children, enabled)
	local alpha = enabled and 1 or 0.4
	for _, child in ipairs(children) do
		if child.SetAlpha then child:SetAlpha(alpha) end
		if child.SetEnabled then child:SetEnabled(enabled) end
		if child.EnableMouse then child:EnableMouse(enabled) end
	end
end

-- Helper: safely get widget config
local function GetWidgetConfig(unit, widgetKey)
	local settings = ns.db[unit]
	if not settings or not settings.widgets then return nil end
	return settings.widgets[widgetKey]
end

-- Helper: safely set widget value
-- [FIX] 위젯 값 변경 시 미리보기 + 실제 프레임 즉시 갱신
local function SetWidgetValue(unit, widgetKey, path, value)
	if not ns.db[unit] then return end
	if not ns.db[unit].widgets then ns.db[unit].widgets = {} end
	if not ns.db[unit].widgets[widgetKey] then ns.db[unit].widgets[widgetKey] = {} end

	local tbl = ns.db[unit].widgets[widgetKey]
	local parts = { strsplit(".", path) }
	for i = 1, #parts - 1 do
		if not tbl[parts[i]] then tbl[parts[i]] = {} end
		tbl = tbl[parts[i]]
	end
	tbl[parts[#parts]] = value
	-- [12.0.1] Preview 제거됨 → TestMode가 편집모드에서 실시간 반영
end

-----------------------------------------------
-- Category Data (TreeView Structure)
-----------------------------------------------
local categoryData = {
	{
		id = "general",
		text = "일반",
		children = {
			{ id = "general.global", text = "전역 설정" },
			{ id = "general.media", text = "미디어" },
			{ id = "general.colors", text = "색상" },
			{ id = "general.modules", text = "모듈" },
			{ id = "general.profiles", text = "프로필" },
		},
	},
	{
		id = "personal",
		text = "개인 프레임",
		children = {
			{ id = "personal.general", text = "기본 설정" },
			{ id = "personal.health", text = "체력바" },
			{ id = "personal.power", text = "자원바" },
			{ id = "personal.castbar", text = "시전바" },
			{ id = "personal.classbar", text = "직업 자원" },
			{ id = "personal.altpower", text = "보조 자원" },
			{ id = "personal.buffs", text = "버프" },
			{ id = "personal.debuffs", text = "디버프" },
			{ id = "personal.defensives", text = "생존기" },
			{ id = "personal.privateauras", text = "프라이빗 오라" },
			{ id = "personal.texts", text = "텍스트" },
			{ id = "personal.indicators", text = "인디케이터" },
			{ id = "personal.effects", text = "위협 상태 / 하이라이트" },
			{ id = "personal.fader", text = "페이드" },
			{ id = "personal.healprediction", text = "치유 예측" },
			{ id = "personal.customtext", text = "커스텀 텍스트" },
		},
	},
	{
		id = "group",
		text = "그룹 프레임",
		children = {
			{ id = "group.general", text = "기본 설정" },
			{ id = "group.layout", text = "레이아웃" },
			{ id = "group.health", text = "체력바" },
			{ id = "group.power", text = "자원바" },
			{ id = "group.buffs", text = "버프" },
			{ id = "group.debuffs", text = "디버프" },
			{ id = "group.defensives", text = "생존기" },
			{ id = "group.privateauras", text = "프라이빗 오라" },
			{ id = "group.indicators", text = "인디케이터" },
			{ id = "group.texts", text = "텍스트" },
			{ id = "group.debuffhighlight", text = "디버프 하이라이트" },
			{ id = "group.dispels", text = "해제" },
			{ id = "group.fader", text = "페이드" },
			{ id = "group.healprediction", text = "치유 예측" },
			{ id = "group.effects", text = "위협 상태 / 하이라이트" },
			{ id = "group.customtext", text = "커스텀 텍스트" },
		},
	},
	{
		id = "hottracker",
		text = "HoT 추적",
	},
}

-----------------------------------------------
-- Page Builders
-----------------------------------------------
local pageBuilders = {}
local currentPage = nil
local contentFrame = nil
-- [PREVIEW] previewPanel/previewUnit 제거 → ns.Preview 사용

local TabSelections = {
	personal = "player",
	group = "party"
}

local PersonalTabs = {
	{ text = "플레이어", value = "player" },
	{ text = "대상", value = "target" },
	{ text = "대상의 대상", value = "targettarget" },
	{ text = "주시 대상", value = "focus" },
	{ text = "주시 대상의 대상", value = "focustarget" },
	{ text = "소환수", value = "pet" },
	{ text = "우두머리", value = "boss" },
	{ text = "투기장", value = "arena" },
}

local GroupTabs = {
	{ text = "파티", value = "party" },
	{ text = "공격대", value = "raid" },
	{ text = "신화 공격대", value = "mythicRaid" },
}

-- Utility function to get unit from category path
local function GetUnitFromCategory(categoryId)
	local parts = { strsplit(".", categoryId) }
	local section = parts[1]
	
	if section == "personal" then return TabSelections.personal end
	if section == "group" then return TabSelections.group end

	if #parts >= 2 then
		local unit = parts[2]
		if section == "unitframes" or section == "groupframes" or section == "enemyframes" then
			return unit
		end
	end
	return nil
end

-- Clear content frame
local function ClearContent()
	if contentFrame and contentFrame.content then
		contentFrame.content._skipAutoHeight = false -- [FIX] 다른 페이지 로드 시 초기화
		-- Hide and release all children
		for _, child in ipairs({ contentFrame.content:GetChildren() }) do
			child:Hide()
			child:SetParent(nil)
		end
		-- Also hide font strings
		for _, region in ipairs({ contentFrame.content:GetRegions() }) do
			region:Hide()
			region:SetParent(nil)
		end
		-- Reset scroll position
		if contentFrame.scrollFrame then
			contentFrame.scrollFrame:SetVerticalScroll(0)
		end
	end
end

-- Common page header
local function CreatePageHeader(parent, title, description)
	local header = Widgets:CreateTitledPane(parent, title, CONTENT_WIDTH - 20, 40)
	header:SetPoint("TOPLEFT", 10, -10)

	if description then
		local desc = header:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
		desc:SetText(description)
		desc:SetTextColor(0.7, 0.7, 0.7)
		desc:SetPoint("TOPLEFT", header.line, "BOTTOMLEFT", 0, -5)
	end
	
	return header
end

-----------------------------------------------
-- General Pages
-----------------------------------------------

pageBuilders["general.global"] = function(parent)
	local header = CreatePageHeader(parent, "전역 설정", "모든 유닛 프레임에 적용되는 전역 설정")

	local yOffset = -60

	-- 아이콘 세트 -- [REFACTOR]
	local iconSetSep = Widgets:CreateSeparator(parent, "아이콘 세트", CONTENT_WIDTH - 40)
	iconSetSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local iconSetLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	iconSetLabel:SetText("전투/역할/리더 아이콘 세트")
	iconSetLabel:SetPoint("TOPLEFT", 15, yOffset)

	local iconSetItems = {}
	local C = ns.Constants
	if C and C.ICON_SETS then
		for key, setData in pairs(C.ICON_SETS) do
			table.insert(iconSetItems, { text = setData.label or key, value = key })
		end
	end
	local iconSetDropdown = Widgets:CreateDropdown(parent, 150)
	iconSetDropdown:SetPoint("TOPLEFT", iconSetLabel, "BOTTOMLEFT", 0, -5)
	iconSetDropdown:SetItems(iconSetItems)
	iconSetDropdown:SetOnSelect(function(value)
		ns.db.iconSet = value
		if ns.Update and ns.Update.RefreshAll then ns.Update:RefreshAll() end
	end)
	iconSetDropdown:SetSelected(ns.db.iconSet or "default")
	yOffset = yOffset - 55

	-- Fading section
	local fadeSep = Widgets:CreateSeparator(parent, "페이딩 설정", CONTENT_WIDTH - 40)
	fadeSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Out of range alpha
	local rangeSlider = Widgets:CreateSlider("범위 밖 투명도", parent, 0, 1, 150, 0.05, nil, function(value)
		ns.db.outOfRangeAlpha = value
		if ns.db.appearance then ns.db.appearance.oorAlpha = value end
		if ns.Update then ns.Update:RefreshFading() end
	end)
	rangeSlider:SetPoint("TOPLEFT", 15, yOffset)
	rangeSlider:SetValue(ns.db.outOfRangeAlpha or 0.4)
	yOffset = yOffset - 50

	-- Dead alpha
	local deadSlider = Widgets:CreateSlider("사망 시 투명도", parent, 0, 1, 150, 0.05, nil, function(value)
		if not ns.db.appearance then ns.db.appearance = {} end
		ns.db.appearance.deadAlpha = value
		ns.db.deadAlpha = value -- legacy compat
		if ns.Update and ns.Update.RefreshAll then ns.Update:RefreshAll() end -- [FIX-OPTION]
	end)
	deadSlider:SetPoint("TOPLEFT", 15, yOffset)
	deadSlider:SetValue(ns.db.appearance and ns.db.appearance.deadAlpha or ns.db.deadAlpha or 0.6)

	-- Offline alpha
	local offlineSlider = Widgets:CreateSlider("오프라인 투명도", parent, 0, 1, 150, 0.05, nil, function(value)
		if not ns.db.appearance then ns.db.appearance = {} end
		ns.db.appearance.offlineAlpha = value
		ns.db.offlineAlpha = value -- legacy compat
		if ns.Update and ns.Update.RefreshAll then ns.Update:RefreshAll() end -- [FIX-OPTION]
	end)
	offlineSlider:SetPoint("LEFT", deadSlider, "RIGHT", 40, 0)
	offlineSlider:SetValue(ns.db.appearance and ns.db.appearance.offlineAlpha or ns.db.offlineAlpha or 0.6)
	yOffset = yOffset - 55

	-- Core systems section
	local coreSep = Widgets:CreateSeparator(parent, "코어 시스템", CONTENT_WIDTH - 40)
	coreSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Smooth bars
	local smoothCheck = Widgets:CreateCheckButton(parent, "부드러운 바 애니메이션", function(checked)
		ns.db.smoothBars = checked
		if ns.Update then ns.Update:RefreshAll() end
	end)
	smoothCheck:SetPoint("TOPLEFT", 15, yOffset)
	smoothCheck:SetChecked(ns.db.smoothBars ~= false)

	-- Pixel perfect
	local pixelCheck = Widgets:CreateCheckButton(parent, "픽셀 퍼펙트 모드", function(checked)
		ns.db.pixelPerfect = checked
		if ns.Update then ns.Update:RefreshAll() end
	end)
	pixelCheck:SetPoint("LEFT", smoothCheck, "RIGHT", 160, 0)
	pixelCheck:SetChecked(ns.db.pixelPerfect ~= false)
	yOffset = yOffset - 35

	-- [FIX] 사망/오프라인 회색 처리 체크박스 삭제 → 색상 탭에서 조절

	-- Number Format section (ElvUI numberPrefixStyle 패턴)
	local numSep = Widgets:CreateSeparator(parent, "숫자 표시 형식", CONTENT_WIDTH - 40)
	numSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local numFormatLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	numFormatLabel:SetText("단위 표기")
	numFormatLabel:SetPoint("TOPLEFT", 15, yOffset)

	local numFormatDropdown = Widgets:CreateDropdown(parent, 180)
	numFormatDropdown:SetPoint("TOPLEFT", numFormatLabel, "BOTTOMLEFT", 0, -5)
	numFormatDropdown:SetItems({
		{ text = "서양식 (K, M, B)", value = "WESTERN" },
		{ text = "동양식 (만, 억, 조)", value = "KOREAN" },
	})
	numFormatDropdown:SetOnSelect(function(value)
		ns.db.numberFormat = value
		if ns.BuildAbbreviateConfig then ns.BuildAbbreviateConfig() end
		if ns.Update and ns.Update.RefreshNumberFormat then
			ns.Update:RefreshNumberFormat()
		elseif ns.Update and ns.Update.RefreshAll then
			ns.Update:RefreshAll()
		end
	end)
	numFormatDropdown:SetSelected(ns.db.numberFormat or "WESTERN")

	-- Decimal length
	local decLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	decLabel:SetText("소수점 자릿수")
	decLabel:SetPoint("LEFT", numFormatLabel, "RIGHT", 220, 0)

	local decSlider = Widgets:CreateSlider("", parent, 0, 2, 120, 1, nil, function(value)
		ns.db.decimalLength = value
		if ns.BuildAbbreviateConfig then ns.BuildAbbreviateConfig() end
		if ns.Update and ns.Update.RefreshNumberFormat then
			ns.Update:RefreshNumberFormat()
		elseif ns.Update and ns.Update.RefreshAll then
			ns.Update:RefreshAll()
		end
	end)
	decSlider:SetPoint("TOPLEFT", decLabel, "BOTTOMLEFT", 0, -5)
	decSlider:SetValue(ns.db.decimalLength or 1)
	yOffset = yOffset - 55

	-- Display Hide section
	local hideSep = Widgets:CreateSeparator(parent, "표시 숨기기", CONTENT_WIDTH - 40)
	hideSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local hideFlying = Widgets:CreateCheckButton(parent, "비행 시 숨기기", function(checked)
		ns.db.hideWhileFlying = checked
		if ns.FlightHide then
			if checked then ns.FlightHide:EnsureOnUpdate() else ns.FlightHide:ForceShow() end
		end
	end)
	hideFlying:SetPoint("TOPLEFT", 15, yOffset)
	hideFlying:SetChecked(ns.db.hideWhileFlying or false)

	local hideMounted = Widgets:CreateCheckButton(parent, "탈것 탑승 시 숨기기", function(checked)
		ns.db.hideWhileMounted = checked
		if ns.FlightHide then
			if checked then ns.FlightHide:EnsureOnUpdate() else ns.FlightHide:ForceShow() end
		end
	end)
	hideMounted:SetPoint("LEFT", hideFlying, "RIGHT", 160, 0)
	hideMounted:SetChecked(ns.db.hideWhileMounted or false)
	yOffset = yOffset - 30

	local hideVehicle = Widgets:CreateCheckButton(parent, "비히클 시 숨기기", function(checked)
		ns.db.hideInVehicle = checked
		if ns.FlightHide then
			if checked then ns.FlightHide:EnsureOnUpdate() else ns.FlightHide:ForceShow() end
		end
	end)
	hideVehicle:SetPoint("TOPLEFT", 15, yOffset)
	hideVehicle:SetChecked(ns.db.hideInVehicle or false)

	local hideOutsideInstance = Widgets:CreateCheckButton(parent, "인스턴스 밖에서만", function(checked)
		ns.db.hideOutsideInstanceOnly = checked
	end)
	hideOutsideInstance:SetPoint("LEFT", hideVehicle, "RIGHT", 160, 0)
	hideOutsideInstance:SetChecked(ns.db.hideOutsideInstanceOnly or false)
	parent:SetHeight(math.abs(yOffset) + 50)
	parent._skipAutoHeight = true
end

pageBuilders["general.media"] = function(parent)
	local header = CreatePageHeader(parent, "미디어 설정", "폰트와 텍스처 설정")

	local yOffset = -60

	-- Texture section
	local texSep = Widgets:CreateSeparator(parent, "StatusBar 텍스처", CONTENT_WIDTH - 40)
	texSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local texLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	texLabel:SetText("기본 텍스처")
	texLabel:SetPoint("TOPLEFT", 15, yOffset)

	-- 저장된 텍스처 경로 또는 LSM 이름으로 복원
	local currentTex = ns.db.media and ns.db.media.texture or [[Interface\Buttons\WHITE8x8]]
	if ns.db.media and ns.db.media.textureName and LSM then
		local resolved = LSM:Fetch(LSM.MediaType.STATUSBAR, ns.db.media.textureName)
		if resolved then currentTex = resolved end
	end

	-- Preview (드롭다운보다 먼저 선언 - 클로저에서 참조)
	local texPreview = parent:CreateTexture(nil, "ARTWORK")
	texPreview:SetSize(120, 16)
	texPreview:SetTexture(currentTex)
	texPreview:SetVertexColor(0.2, 0.6, 0.4)

	local texDropdown = Widgets:CreateDropdown(parent, 200)
	texDropdown:SetPoint("TOPLEFT", texLabel, "BOTTOMLEFT", 0, -5)
	texDropdown:SetItems(GetTextureList())
	texDropdown:SetOnSelect(function(value)
		if not ns.db.media then ns.db.media = {} end
		ns.db.media.texture = value
		ns.db.media.textureName = FindLSMName("statusbar", value)
		texPreview:SetTexture(value)
		if ns.Update then ns.Update:RefreshMedia() end
	end)
	texDropdown:SetSelected(currentTex)

	texPreview:SetPoint("LEFT", texDropdown, "RIGHT", 20, 0)
	yOffset = yOffset - 60

	-- [FIX] "모두 이 텍스쳐로 변경" 버튼
	local applyAllBtn = Widgets:CreateButton(parent, "모두 이 텍스쳐로 변경", "accent", {180, 26})
	applyAllBtn:SetPoint("TOPLEFT", 15, yOffset)
	applyAllBtn:SetScript("OnClick", function()
		local tex = ns.db.media and ns.db.media.texture
		local texName = ns.db.media and ns.db.media.textureName
		if not tex then return end
		local allUnits = {"player","target","targettarget","focus","focustarget","pet","party","raid","mythicRaid","boss","arena"}
		for _, unitKey in ipairs(allUnits) do
			local udb = ns.db[unitKey]
			if udb and udb.widgets then
				for _, wKey in ipairs({"health","power","castbar"}) do
					local w = udb.widgets[wKey]
					if w then
						w.texture = tex
						w.textureName = texName
					end
				end
			end
		end
		if ns.Update then ns.Update:RefreshMedia() end
		ns.Print("모든 유닛에 전역 텍스쳐 적용 완료")
	end)
	yOffset = yOffset - 35

	-- Font section
	local fontSep = Widgets:CreateSeparator(parent, "기본 폰트", CONTENT_WIDTH - 40)
	fontSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- 저장된 폰트 경로 또는 LSM 이름으로 복원
	local currentFont = ns.db.media and ns.db.media.font or [[Fonts\2002.TTF]]
	if ns.db.media and ns.db.media.fontName and LSM then
		local resolved = LSM:Fetch(LSM.MediaType.FONT, ns.db.media.fontName)
		if resolved then currentFont = resolved end
	end

	-- Font preview (드롭다운보다 먼저 선언 - 클로저에서 참조)
	local fontPreview = parent:CreateFontString(nil, "OVERLAY")
	fontPreview:SetFont(currentFont, 13, "OUTLINE")
	fontPreview:SetText("가나다 ABC 123")
	fontPreview:SetTextColor(0.9, 0.9, 0.9)

	-- Font face dropdown (LSM 기반)
	local fontFaceLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	fontFaceLabel:SetText("폰트 서체")
	fontFaceLabel:SetPoint("TOPLEFT", 15, yOffset)

	local fontFaceDropdown = Widgets:CreateDropdown(parent, 200)
	fontFaceDropdown:SetPoint("TOPLEFT", fontFaceLabel, "BOTTOMLEFT", 0, -5)
	fontFaceDropdown:SetItems(GetFontList())
	fontFaceDropdown:SetOnSelect(function(value)
		if not ns.db.media then ns.db.media = {} end
		ns.db.media.font = value
		ns.db.media.fontName = FindLSMName("font", value)
		fontPreview:SetFont(value, 13, "OUTLINE")
		if ns.Update then ns.Update:RefreshMedia() end
	end)
	fontFaceDropdown:SetSelected(currentFont)

	fontPreview:SetPoint("LEFT", fontFaceDropdown, "RIGHT", 20, 0)
	yOffset = yOffset - 60

	-- Font selector (size + outline + shadow + justify)
	local fontSelector = Widgets:CreateFontSelector(parent, 350, function(fontOpt)
		if not ns.db.media then ns.db.media = {} end
		ns.db.media.fontSize = fontOpt.size
		ns.db.media.fontFlags = fontOpt.outline
		if ns.Update then ns.Update:RefreshMedia() end
	end)
	fontSelector:SetPoint("TOPLEFT", 15, yOffset)
	fontSelector:SetFont({
		size = ns.db.media and ns.db.media.fontSize or 11,
		outline = ns.db.media and ns.db.media.fontFlags or "OUTLINE",
		shadow = false,
		justify = "CENTER",
	})
	parent:SetHeight(math.abs(yOffset) + 50)
	parent._skipAutoHeight = true
end

pageBuilders["general.colors"] = function(parent)
	local header = CreatePageHeader(parent, "색상 설정", "전역 색상 및 시각적 설정")

	-- Ensure ns.Colors exists
	if not ns.Colors then ns.Colors = {} end

	-- Helper: 색상 변경 후 모든 프레임 갱신 + SavedVariables에 자동 저장
	local function RefreshColors()
		-- [FIX] ns.Colors 전체를 ddingUI_UFDB.global.colors에 저장
		if ddingUI_UFDB and ns.Colors then
			ddingUI_UFDB.global = ddingUI_UFDB.global or {}
			ddingUI_UFDB.global.colors = {}
			for category, data in pairs(ns.Colors) do
				if type(data) == "table" then
					ddingUI_UFDB.global.colors[category] = {}
					for k, v in pairs(data) do
						if type(v) == "table" then
							ddingUI_UFDB.global.colors[category][k] = { v[1], v[2], v[3], v[4] }
						else
							ddingUI_UFDB.global.colors[category][k] = v
						end
					end
				end
			end
		end
		-- [FIX] Constants에 동기화 (RestoreColors와 동일 로직)
		local C = ns.Constants
		if C and ns.Colors.reaction then
			local rc = ns.Colors.reaction
			if rc.friendly then
				for i = 5, 8 do C.REACTION_COLORS[i] = { rc.friendly[1], rc.friendly[2], rc.friendly[3] } end
			end
			if rc.neutral then
				C.REACTION_COLORS[4] = { rc.neutral[1], rc.neutral[2], rc.neutral[3] }
			end
			if rc.hostile then
				for i = 1, 3 do C.REACTION_COLORS[i] = { rc.hostile[1], rc.hostile[2], rc.hostile[3] } end
			end
		end
		-- [FIX] oUF.colors.tapped 동기화
		local _oUF = ns.oUF
		if ns.Colors.reaction and ns.Colors.reaction.tapped and _oUF and _oUF.colors then
			local t = ns.Colors.reaction.tapped
			if _oUF.colors.tapped and _oUF.colors.tapped.SetRGBA then
				_oUF.colors.tapped:SetRGBA(t[1], t[2], t[3], 1)
			else
				_oUF.colors.tapped = _oUF:CreateColor(t[1], t[2], t[3])
			end
		end
		if C and ns.Colors.castBar then
			if ns.Colors.castBar.interruptible then
				local cc = ns.Colors.castBar.interruptible
				C.CASTBAR_COLOR = { cc[1], cc[2], cc[3] }
			end
			if ns.Colors.castBar.nonInterruptible then
				local cc = ns.Colors.castBar.nonInterruptible
				C.CASTBAR_NOINTERRUPT_COLOR = { cc[1], cc[2], cc[3] }
			end
		end
		if ns.Update then ns.Update:RefreshAll() end
	end

	local yOffset = -60

	-- Unit Frame Colors Section
	local unitSep = Widgets:CreateSeparator(parent, "유닛 프레임 색상", CONTENT_WIDTH - 40)
	unitSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Death Color
	local deathColorCP = Widgets:CreateColorPicker(parent, "사망 시 색상", true, function(r, g, b, a)
		if not ns.Colors.unitFrames then ns.Colors.unitFrames = {} end
		ns.Colors.unitFrames.deathColor = { r, g, b, a }
		RefreshColors()
	end)
	deathColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local deathc = ns.Colors.unitFrames and ns.Colors.unitFrames.deathColor or { 0.47, 0.47, 0.47, 1 }
	deathColorCP:SetColor(deathc[1], deathc[2], deathc[3], deathc[4])

	-- [UF-OPTIONS] 오프라인 색상
	local offlineColorCP = Widgets:CreateColorPicker(parent, "오프라인 시 색상", true, function(r, g, b, a)
		if not ns.Colors.unitFrames then ns.Colors.unitFrames = {} end
		ns.Colors.unitFrames.offlineColor = { r, g, b, a }
		RefreshColors()
	end)
	offlineColorCP:SetPoint("LEFT", deathColorCP, "RIGHT", 180, 0)
	local offc = ns.Colors.unitFrames and ns.Colors.unitFrames.offlineColor or { 0.5, 0.5, 0.5, 1 }
	offlineColorCP:SetColor(offc[1], offc[2], offc[3], offc[4])

	yOffset = yOffset - 40

	-- Reaction Colors Section
	local reactionSep = Widgets:CreateSeparator(parent, "반응 색상", CONTENT_WIDTH - 40)
	reactionSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Friendly
	local friendlyCP = Widgets:CreateColorPicker(parent, "우호적", true, function(r, g, b, a)
		if not ns.Colors.reaction then ns.Colors.reaction = {} end
		ns.Colors.reaction.friendly = { r, g, b, a }
		RefreshColors()
	end)
	friendlyCP:SetPoint("TOPLEFT", 15, yOffset)
	local fc = ns.Colors.reaction and ns.Colors.reaction.friendly or { 0.29, 0.69, 0.3, 1 }
	friendlyCP:SetColor(fc[1], fc[2], fc[3], fc[4])

	-- Hostile
	local hostileCP = Widgets:CreateColorPicker(parent, "적대적", true, function(r, g, b, a)
		if not ns.Colors.reaction then ns.Colors.reaction = {} end
		ns.Colors.reaction.hostile = { r, g, b, a }
		RefreshColors()
	end)
	hostileCP:SetPoint("LEFT", friendlyCP, "RIGHT", 180, 0)
	local hc = ns.Colors.reaction and ns.Colors.reaction.hostile or { 0.78, 0.25, 0.25, 1 }
	hostileCP:SetColor(hc[1], hc[2], hc[3], hc[4])
	yOffset = yOffset - 30

	-- Neutral
	local neutralCP = Widgets:CreateColorPicker(parent, "중립", true, function(r, g, b, a)
		if not ns.Colors.reaction then ns.Colors.reaction = {} end
		ns.Colors.reaction.neutral = { r, g, b, a }
		RefreshColors()
	end)
	neutralCP:SetPoint("TOPLEFT", 15, yOffset)
	local nc = ns.Colors.reaction and ns.Colors.reaction.neutral or { 0.85, 0.77, 0.36, 1 }
	neutralCP:SetColor(nc[1], nc[2], nc[3], nc[4])

	-- Tapped
	local tappedCP = Widgets:CreateColorPicker(parent, "선점됨", true, function(r, g, b, a)
		if not ns.Colors.reaction then ns.Colors.reaction = {} end
		ns.Colors.reaction.tapped = { r, g, b, a }
		RefreshColors()
	end)
	tappedCP:SetPoint("LEFT", neutralCP, "RIGHT", 180, 0)
	local tc = ns.Colors.reaction and ns.Colors.reaction.tapped or { 0.5, 0.5, 0.5, 1 }
	tappedCP:SetColor(tc[1], tc[2], tc[3], tc[4])
	yOffset = yOffset - 40

	-- Cast Bar Colors Section
	local castSep = Widgets:CreateSeparator(parent, "시전바 색상", CONTENT_WIDTH - 40)
	castSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Interruptible
	local interruptCP = Widgets:CreateColorPicker(parent, "차단 가능", true, function(r, g, b, a)
		if not ns.Colors.castBar then ns.Colors.castBar = {} end
		ns.Colors.castBar.interruptible = { r, g, b, a }
		RefreshColors()
	end)
	interruptCP:SetPoint("TOPLEFT", 15, yOffset)
	local intc = ns.Colors.castBar and ns.Colors.castBar.interruptible or { 0.2, 0.57, 0.5, 1 }
	interruptCP:SetColor(intc[1], intc[2], intc[3], intc[4])

	-- Non-interruptible
	local noninterruptCP = Widgets:CreateColorPicker(parent, "차단 불가", true, function(r, g, b, a)
		if not ns.Colors.castBar then ns.Colors.castBar = {} end
		ns.Colors.castBar.nonInterruptible = { r, g, b, a }
		RefreshColors()
	end)
	noninterruptCP:SetPoint("LEFT", interruptCP, "RIGHT", 180, 0)
	local nic = ns.Colors.castBar and ns.Colors.castBar.nonInterruptible or { 0.43, 0.43, 0.43, 1 }
	noninterruptCP:SetColor(nic[1], nic[2], nic[3], nic[4])
	yOffset = yOffset - 40

	-- Shield / Heal Section
	local shieldSep = Widgets:CreateSeparator(parent, "보호막 / 치유 예측", CONTENT_WIDTH - 40)
	shieldSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Shield Color
	local shieldCP = Widgets:CreateColorPicker(parent, "보호막", true, function(r, g, b, a)
		if not ns.Colors.shieldBar then ns.Colors.shieldBar = {} end
		ns.Colors.shieldBar.shieldColor = { r, g, b, a }
		RefreshColors()
	end)
	shieldCP:SetPoint("TOPLEFT", 15, yOffset)
	local sc = ns.Colors.shieldBar and ns.Colors.shieldBar.shieldColor or { 1, 1, 0, 0.4 }
	shieldCP:SetColor(sc[1], sc[2], sc[3], sc[4])

	-- Overshield Color
	local overshieldCP = Widgets:CreateColorPicker(parent, "초과 보호막", true, function(r, g, b, a)
		if not ns.Colors.shieldBar then ns.Colors.shieldBar = {} end
		ns.Colors.shieldBar.overshieldColor = { r, g, b, a }
		RefreshColors()
	end)
	overshieldCP:SetPoint("LEFT", shieldCP, "RIGHT", 180, 0)
	local osc = ns.Colors.shieldBar and ns.Colors.shieldBar.overshieldColor or { 1, 1, 1, 0.8 }
	overshieldCP:SetColor(osc[1], osc[2], osc[3], osc[4])
	yOffset = yOffset - 30

	-- Heal Prediction
	local healCP = Widgets:CreateColorPicker(parent, "치유 예측", true, function(r, g, b, a)
		if not ns.Colors.healPrediction then ns.Colors.healPrediction = {} end
		ns.Colors.healPrediction.color = { r, g, b, a }
		RefreshColors()
	end)
	healCP:SetPoint("TOPLEFT", 15, yOffset)
	local hepc = ns.Colors.healPrediction and ns.Colors.healPrediction.color or { 0, 1, 0.5, 0.4 }
	healCP:SetColor(hepc[1], hepc[2], hepc[3], hepc[4])

	-- Over Heal
	local overHealCP = Widgets:CreateColorPicker(parent, "초과 치유", true, function(r, g, b, a)
		if not ns.Colors.healPrediction then ns.Colors.healPrediction = {} end
		ns.Colors.healPrediction.overHealColor = { r, g, b, a }
		RefreshColors()
	end)
	overHealCP:SetPoint("LEFT", healCP, "RIGHT", 180, 0)
	local ohpc = ns.Colors.healPrediction and ns.Colors.healPrediction.overHealColor or { 1, 1, 1, 0.3 }
	overHealCP:SetColor(ohpc[1], ohpc[2], ohpc[3], ohpc[4])
	yOffset = yOffset - 30

	-- Heal Absorb
	local healAbsorbCP = Widgets:CreateColorPicker(parent, "치유 흡수", true, function(r, g, b, a)
		if not ns.Colors.healAbsorb then ns.Colors.healAbsorb = {} end
		ns.Colors.healAbsorb.color = { r, g, b, a }
		RefreshColors()
	end)
	healAbsorbCP:SetPoint("TOPLEFT", 15, yOffset)
	local hac = ns.Colors.healAbsorb and ns.Colors.healAbsorb.color or { 1, 0.1, 0.1, 0.5 }
	healAbsorbCP:SetColor(hac[1], hac[2], hac[3], hac[4])
	yOffset = yOffset - 40

	-- Highlight Colors Section
	local highlightSep = Widgets:CreateSeparator(parent, "하이라이트 색상", CONTENT_WIDTH - 40)
	highlightSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Target Highlight
	local targetHighlightCP = Widgets:CreateColorPicker(parent, "대상 하이라이트", true, function(r, g, b, a)
		if not ns.Colors.highlight then ns.Colors.highlight = {} end
		ns.Colors.highlight.target = { r, g, b, a }
		RefreshColors()
	end)
	targetHighlightCP:SetPoint("TOPLEFT", 15, yOffset)
	local thc = ns.Colors.highlight and ns.Colors.highlight.target or { 1, 0.3, 0.3, 1 }
	targetHighlightCP:SetColor(thc[1], thc[2], thc[3], thc[4])

	-- Hover Highlight
	local hoverHighlightCP = Widgets:CreateColorPicker(parent, "마우스오버 하이라이트", true, function(r, g, b, a)
		if not ns.Colors.highlight then ns.Colors.highlight = {} end
		ns.Colors.highlight.hover = { r, g, b, a }
		RefreshColors()
	end)
	hoverHighlightCP:SetPoint("LEFT", targetHighlightCP, "RIGHT", 180, 0)
	local hhc = ns.Colors.highlight and ns.Colors.highlight.hover or { 1, 1, 1, 0.3 }
	hoverHighlightCP:SetColor(hhc[1], hhc[2], hhc[3], hhc[4])
	yOffset = yOffset - 45

	-- ===== Power (Resource) Colors ===== -- [UF-OPTIONS]
	local powerSep = Widgets:CreateSeparator(parent, "자원 바 색상", CONTENT_WIDTH - 40)
	powerSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	if not ns.Colors.power then ns.Colors.power = {} end
	local powerTypes = {
		{ key = "MANA",        name = "마나",       def = { 0.31, 0.45, 0.63, 1 } },
		{ key = "RAGE",        name = "분노",       def = { 0.78, 0.25, 0.25, 1 } },
		{ key = "ENERGY",      name = "기력",       def = { 0.65, 0.63, 0.35, 1 } },
		{ key = "FOCUS",       name = "집중",       def = { 0.71, 0.43, 0.27, 1 } },
		{ key = "RUNIC_POWER", name = "룬 마력",    def = { 0.00, 0.82, 1.00, 1 } },
		{ key = "LUNAR_POWER", name = "천공의 힘",  def = { 0.30, 0.52, 0.90, 1 } },
		{ key = "MAELSTROM",   name = "소용돌이",   def = { 0.00, 0.50, 1.00, 1 } },
		{ key = "INSANITY",    name = "광기",       def = { 0.40, 0.00, 0.80, 1 } },
		{ key = "FURY",        name = "분노(DH)",   def = { 0.79, 0.26, 0.99, 1 } },
		{ key = "PAIN",        name = "고통",       def = { 1.00, 0.61, 0.00, 1 } },
	}
	for idx, pt in ipairs(powerTypes) do
		local ptCP = Widgets:CreateColorPicker(parent, pt.name, true, function(r, g, b, a)
			ns.Colors.power[pt.key] = { r, g, b, a }
			-- Constants.POWER_COLORS에도 반영 (런타임)
			if ns.Constants and ns.Constants.POWER_COLORS then
				ns.Constants.POWER_COLORS[pt.key] = { r, g, b }
			end
			-- oUF.colors.power 동기화
			local oUF = ns.oUF
			if oUF and oUF.colors and oUF.colors.power then
				local existing = oUF.colors.power[pt.key]
				if existing and existing.SetRGBA then
					existing:SetRGBA(r, g, b, 1)
				else
					oUF.colors.power[pt.key] = oUF:CreateColor(r, g, b)
				end
			end
			-- [FIX] SavedVariables에 저장 (ddingUI_UFDB.global.powerColors)
			if ddingUI_UFDB then
				ddingUI_UFDB.global = ddingUI_UFDB.global or {}
				ddingUI_UFDB.global.powerColors = ddingUI_UFDB.global.powerColors or {}
				ddingUI_UFDB.global.powerColors[pt.key] = { r, g, b, a }
			end
			RefreshColors()
		end)
		local col = (idx - 1) % 2
		local row = math.floor((idx - 1) / 2)
		if col == 0 then
			ptCP:SetPoint("TOPLEFT", 15, yOffset - row * 30)
		else
			ptCP:SetPoint("TOPLEFT", 15 + 330, yOffset - row * 30)
		end
		-- [FIX] SavedVariables에서 저장된 색상 우선 로드
		local savedPC = ddingUI_UFDB and ddingUI_UFDB.global and ddingUI_UFDB.global.powerColors and ddingUI_UFDB.global.powerColors[pt.key]
		local pc = savedPC or ns.Colors.power[pt.key] or pt.def
		ptCP:SetColor(pc[1], pc[2], pc[3], pc[4] or 1)
	end
	yOffset = yOffset - (math.ceil(#powerTypes / 2) * 30) - 10

	-- ===== Class Resource Colors =====
	local crSep = Widgets:CreateSeparator(parent, "직업 자원 색상", CONTENT_WIDTH - 40)
	crSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Combo Points
	local cpLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	cpLabel:SetText("콤보 포인트 (1~7)")
	cpLabel:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 20

	if not ns.Colors.comboPoints then ns.Colors.comboPoints = {} end
	for i = 1, 7 do
		local def = { 0.76, 0.3, 0.3, 1 }
		if i == 2 then def = { 0.79, 0.56, 0.3, 1 }
		elseif i == 3 then def = { 0.82, 0.82, 0.3, 1 }
		elseif i == 4 then def = { 0.56, 0.79, 0.3, 1 }
		elseif i == 5 then def = { 0.43, 0.77, 0.3, 1 }
		elseif i == 6 then def = { 0.3, 0.76, 0.3, 1 }
		elseif i == 7 then def = { 0.36, 0.82, 0.54, 1 } end

		local cpCP = Widgets:CreateColorPicker(parent, tostring(i), false, function(r, g, b)
			ns.Colors.comboPoints[i] = { r, g, b, 1 }
			RefreshColors()
		end)
		local xOff = 15 + ((i - 1) % 7) * 85
		cpCP:SetPoint("TOPLEFT", xOff, yOffset)
		local c = ns.Colors.comboPoints[i] or def
		cpCP:SetColor(c[1], c[2], c[3], c[4] or 1)
	end
	yOffset = yOffset - 35

	-- Charged combo point
	local chargedCP = Widgets:CreateColorPicker(parent, "충전됨", false, function(r, g, b)
		ns.Colors.comboPoints.charged = { r, g, b, 1 }
		RefreshColors()
	end)
	chargedCP:SetPoint("TOPLEFT", 15, yOffset)
	local chc = ns.Colors.comboPoints.charged or { 0.15, 0.64, 1, 1 }
	chargedCP:SetColor(chc[1], chc[2], chc[3], chc[4] or 1)
	yOffset = yOffset - 35

	-- Holy Power
	if not ns.Colors.classResources then ns.Colors.classResources = {} end
	local hpCP = Widgets:CreateColorPicker(parent, "신성한 힘", true, function(r, g, b, a)
		ns.Colors.classResources.holyPower = { r, g, b, a }
		RefreshColors()
	end)
	hpCP:SetPoint("TOPLEFT", 15, yOffset)
	local hp = ns.Colors.classResources.holyPower or { 0.9, 0.89, 0.04, 1 }
	hpCP:SetColor(hp[1], hp[2], hp[3], hp[4])

	-- Arcane Charges
	local acCP = Widgets:CreateColorPicker(parent, "비전 충전", true, function(r, g, b, a)
		ns.Colors.classResources.arcaneCharges = { r, g, b, a }
		RefreshColors()
	end)
	acCP:SetPoint("LEFT", hpCP, "RIGHT", 180, 0)
	local ac = ns.Colors.classResources.arcaneCharges or { 0, 0.62, 1, 1 }
	acCP:SetColor(ac[1], ac[2], ac[3], ac[4])
	yOffset = yOffset - 30

	-- Soul Shards
	local ssCP = Widgets:CreateColorPicker(parent, "영혼 조각", true, function(r, g, b, a)
		ns.Colors.classResources.soulShards = { r, g, b, a }
		RefreshColors()
	end)
	ssCP:SetPoint("TOPLEFT", 15, yOffset)
	local ss = ns.Colors.classResources.soulShards or { 0.58, 0.51, 0.8, 1 }
	ssCP:SetColor(ss[1], ss[2], ss[3], ss[4])
	yOffset = yOffset - 35

	-- Runes
	local runeSep = Widgets:CreateSeparator(parent, "룬 (죽음의 기사)", CONTENT_WIDTH - 40)
	runeSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	if not ns.Colors.runes then ns.Colors.runes = {} end
	local runeTypes = { { key = "blood", name = "혈기" }, { key = "frost", name = "냉기" }, { key = "unholy", name = "부정" } }
	for idx, rt in ipairs(runeTypes) do
		local runeCP = Widgets:CreateColorPicker(parent, rt.name, false, function(r, g, b)
			ns.Colors.runes[rt.key] = { r, g, b, 1 }
			RefreshColors()
		end)
		if idx == 1 then
			runeCP:SetPoint("TOPLEFT", 15, yOffset)
		else
			runeCP:SetPoint("LEFT", 15 + (idx - 1) * 180, 0)
			runeCP:SetPoint("TOP", 0, yOffset)
		end
		local rc = ns.Colors.runes[rt.key] or { 1, 0.24, 0.24, 1 }
		runeCP:SetColor(rc[1], rc[2], rc[3], rc[4] or 1)
	end
	yOffset = yOffset - 35

	-- Chi
	local chiSep = Widgets:CreateSeparator(parent, "기 (수도사)", CONTENT_WIDTH - 40)
	chiSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	if not ns.Colors.chi then ns.Colors.chi = {} end
	for i = 1, 6 do
		local def = { 0.72, 0.77, 0.31, 1 }
		if i == 2 then def = { 0.58, 0.74, 0.36, 1 }
		elseif i == 3 then def = { 0.49, 0.72, 0.38, 1 }
		elseif i == 4 then def = { 0.38, 0.7, 0.42, 1 }
		elseif i == 5 then def = { 0.26, 0.67, 0.46, 1 }
		elseif i == 6 then def = { 0.13, 0.64, 0.5, 1 } end

		local chiCP = Widgets:CreateColorPicker(parent, tostring(i), false, function(r, g, b)
			ns.Colors.chi[i] = { r, g, b, 1 }
			RefreshColors()
		end)
		local xOff = 15 + ((i - 1) % 6) * 90
		chiCP:SetPoint("TOPLEFT", xOff, yOffset)
		local c = ns.Colors.chi[i] or def
		chiCP:SetColor(c[1], c[2], c[3], c[4] or 1)
	end
	yOffset = yOffset - 35

	-- Essence (Evoker)
	local essSep = Widgets:CreateSeparator(parent, "정수 (기원사)", CONTENT_WIDTH - 40)
	essSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	if not ns.Colors.essence then ns.Colors.essence = {} end
	local essCP = Widgets:CreateColorPicker(parent, "정수 색상", true, function(r, g, b, a)
		for ei = 1, 6 do
			ns.Colors.essence[ei] = { r, g, b, a }
		end
		RefreshColors()
	end)
	essCP:SetPoint("TOPLEFT", 15, yOffset)
	local esc = ns.Colors.essence[1] or { 0.2, 0.57, 0.5, 1 }
	essCP:SetColor(esc[1], esc[2], esc[3], esc[4])
	parent:SetHeight(math.abs(yOffset) + 50)
	parent._skipAutoHeight = true
end

-----------------------------------------------
-- Modules Page
-----------------------------------------------

pageBuilders["general.modules"] = function(parent)
	local header = CreatePageHeader(parent, "모듈 설정", "추가 기능 모듈 활성화/비활성화")

	local yOffset = -60

	-- ClickCasting
	local ccSep = Widgets:CreateSeparator(parent, "클릭 캐스팅", CONTENT_WIDTH - 40)
	ccSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local ccDesc = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	ccDesc:SetText("유닛프레임 클릭 시 수정키 조합으로 주문 시전 (전투 중 변경 불가)")
	ccDesc:SetTextColor(0.6, 0.6, 0.6)
	ccDesc:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 20

	local ccCheck = Widgets:CreateCheckButton(parent, "클릭 캐스팅 활성화", function(checked)
		if not ns.db.clickCasting then ns.db.clickCasting = { enabled = false, bindings = {} } end
		ns.db.clickCasting.enabled = checked
		if ns.ClickCasting then
			if checked then
				ns.ClickCasting:Initialize()
			else
				ns.ClickCasting:RemoveFromAllFrames()
			end
		end
	end)
	ccCheck:SetPoint("TOPLEFT", 15, yOffset)
	ccCheck:SetChecked(ns.db.clickCasting and ns.db.clickCasting.enabled)
	yOffset = yOffset - 30

	-- [OPTION-ADD] 클릭 캐스팅 바인딩 편집기
	local ccBindings = ns.db.clickCasting and ns.db.clickCasting.bindings or {}

	local ccModifierList = {
		{ text = "없음", value = "none" },
		{ text = "Shift", value = "shift" },
		{ text = "Ctrl", value = "ctrl" },
		{ text = "Alt", value = "alt" },
		{ text = "Shift+Ctrl", value = "shift-ctrl" },
		{ text = "Shift+Alt", value = "shift-alt" },
		{ text = "Ctrl+Alt", value = "ctrl-alt" },
	}
	local ccButtonList = {
		{ text = "좌클릭", value = "1" },
		{ text = "우클릭", value = "2" },
		{ text = "휠클릭", value = "3" },
		{ text = "버튼4", value = "4" },
		{ text = "버튼5", value = "5" },
	}

	-- Binding list display
	local ccListFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	ccListFrame:SetSize(CONTENT_WIDTH - 40, 100)
	ccListFrame:SetPoint("TOPLEFT", 15, yOffset)
	local SL = ns.StyleLib
	Widgets:StylizeFrame(ccListFrame, SL and SL.Colors.bg.input or { 0.06, 0.06, 0.06, 0.9 })
	yOffset = yOffset - 105

	local ccListText = ccListFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	ccListText:SetPoint("TOPLEFT", 5, -5)
	ccListText:SetPoint("BOTTOMRIGHT", -5, 5)
	ccListText:SetJustifyH("LEFT")
	ccListText:SetJustifyV("TOP")
	ccListText:SetWordWrap(true)

	local function RefreshBindingList()
		local lines = {}
		local bindings = ns.db.clickCasting and ns.db.clickCasting.bindings or {}
		for i, b in ipairs(bindings) do
			local modName = b.modifier == "none" and "" or (b.modifier .. "+")
			local btnName = b.button == "1" and "좌" or b.button == "2" and "우" or b.button == "3" and "휠" or ("버튼" .. b.button)
			local spellName = b.spellId and GetSpellInfo(b.spellId) or ("ID:" .. tostring(b.spellId or "?"))
			lines[#lines + 1] = i .. ". " .. modName .. btnName .. " → " .. spellName
		end
		ccListText:SetText(#lines > 0 and table.concat(lines, "\n") or "(바인딩 없음)")
	end
	RefreshBindingList()

	-- Add binding controls
	local ccModDropdown = Widgets:CreateDropdown(parent, 100)
	ccModDropdown:SetPoint("TOPLEFT", 15, yOffset)
	ccModDropdown:SetItems(ccModifierList)
	ccModDropdown:SetSelected("none")

	local ccBtnDropdown = Widgets:CreateDropdown(parent, 80)
	ccBtnDropdown:SetPoint("LEFT", ccModDropdown, "RIGHT", 10, 0)
	ccBtnDropdown:SetItems(ccButtonList)
	ccBtnDropdown:SetSelected("1")

	-- [UF-OPTIONS] 선택된 주문 표시 영역
	local ccSelectedFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	ccSelectedFrame:SetSize(160, 24)
	ccSelectedFrame:SetPoint("LEFT", ccBtnDropdown, "RIGHT", 10, 0)
	local SL2 = ns.StyleLib
	Widgets:StylizeFrame(ccSelectedFrame, SL2 and SL2.Colors.bg.input or { 0.06, 0.06, 0.06, 0.9 })

	local ccSelectedIcon = ccSelectedFrame:CreateTexture(nil, "ARTWORK")
	ccSelectedIcon:SetPoint("LEFT", 4, 0)
	ccSelectedIcon:SetSize(18, 18)
	ccSelectedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	ccSelectedIcon:SetTexCoord(0.15, 0.85, 0.15, 0.85)

	local ccSelectedText = ccSelectedFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	ccSelectedText:SetPoint("LEFT", ccSelectedIcon, "RIGHT", 4, 0)
	ccSelectedText:SetPoint("RIGHT", -4, 0)
	ccSelectedText:SetJustifyH("LEFT")
	ccSelectedText:SetText("주문 선택...")
	ccSelectedText:SetTextColor(0.5, 0.5, 0.5)

	local ccSelectedSpellId = nil -- 선택된 스펠 ID 추적

	local function SetSelectedSpell(spellId, spellName, spellIcon)
		ccSelectedSpellId = spellId
		if spellId and spellName then
			ccSelectedIcon:SetTexture(spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
			ccSelectedText:SetText(spellName)
			ccSelectedText:SetTextColor(1, 1, 1)
		else
			ccSelectedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			ccSelectedText:SetText("주문 선택...")
			ccSelectedText:SetTextColor(0.5, 0.5, 0.5)
		end
	end

	-- [UF-OPTIONS] 스펠 선택 버튼 (스펠북 브라우저 팝업)
	local ccSpellPickBtn = Widgets:CreateButton(parent, "스펠북", "accent", { 60, 24 })
	ccSpellPickBtn:SetPoint("LEFT", ccSelectedFrame, "RIGHT", 5, 0)
	ccSpellPickBtn:SetScript("OnClick", function()
		-- 스펠북 검색 팝업 생성/표시
		if not ns._spellPickerPopup then
			local popup = CreateFrame("Frame", "DDingUI_UF_SpellPicker", UIParent, "BackdropTemplate")
			popup:SetSize(300, 380)
			popup:SetPoint("CENTER", 0, 50)
			popup:SetFrameStrata("FULLSCREEN_DIALOG")
			popup:SetFrameLevel(100)
			popup:SetMovable(true)
			popup:EnableMouse(true)
			popup:RegisterForDrag("LeftButton")
			popup:SetScript("OnDragStart", popup.StartMoving)
			popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
			local popSL = ns.StyleLib
			Widgets:StylizeFrame(popup, popSL and popSL.Colors.bg.main or { 0.08, 0.08, 0.08, 0.97 })
			popup:Hide()

			-- 타이틀
			local titleText = popup:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
			titleText:SetPoint("TOPLEFT", 10, -10)
			titleText:SetText("스펠북에서 주문 선택")
			titleText:SetTextColor(1, 1, 1)

			-- 닫기 버튼
			local closeBtn = Widgets:CreateButton(popup, "X", "red", { 24, 24 })
			closeBtn:SetPoint("TOPRIGHT", -6, -6)
			closeBtn:SetScript("OnClick", function() popup:Hide() end)

			-- 검색창
			local searchBox = CreateFrame("EditBox", nil, popup, "BackdropTemplate")
			Widgets:StylizeFrame(searchBox, popSL and popSL.Colors.bg.input or { 0.06, 0.06, 0.06, 0.9 })
			searchBox:SetFontObject(GameFontHighlightSmall)
			searchBox:SetSize(280, 24)
			searchBox:SetPoint("TOPLEFT", 10, -35)
			searchBox:SetTextInsets(8, 8, 0, 0)
			searchBox:SetAutoFocus(false)

			local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
			searchPlaceholder:SetPoint("LEFT", 8, 0)
			searchPlaceholder:SetText("주문 이름 검색...")
			searchPlaceholder:SetTextColor(0.5, 0.5, 0.5)

			searchBox:SetScript("OnEditFocusGained", function() searchPlaceholder:Hide() end)
			searchBox:SetScript("OnEditFocusLost", function()
				if searchBox:GetText() == "" then searchPlaceholder:Show() end
			end)
			searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

			-- 스크롤 영역
			local scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
			scrollFrame:SetPoint("TOPLEFT", 10, -65)
			scrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)

			local scrollChild = CreateFrame("Frame", nil, scrollFrame)
			scrollChild:SetSize(250, 1)
			scrollFrame:SetScrollChild(scrollChild)

			local spellRows = {}

			-- [UF-OPTIONS] 스펠북 검색 함수 (C_SpellBook API, WoW 12.0+)
			local function SearchSpellbook(searchText)
				local results = {}
				searchText = searchText and searchText:lower() or ""

				-- C_SpellBook API 존재 확인
				if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then return results end

				local bookType = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
				local numTabs = C_SpellBook.GetNumSpellBookSkillLines()

				for tabIdx = 1, numTabs do
					local skillInfo = C_SpellBook.GetSpellBookSkillLineInfo(tabIdx)
					if skillInfo and not skillInfo.shouldHide then
						local offset = skillInfo.itemIndexOffset
						local numSlots = skillInfo.numSpellBookItems

						for i = 1, numSlots do
							local slotIndex = offset + i
							local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, bookType)

							if itemInfo and itemInfo.itemType == Enum.SpellBookItemType.Spell then
								local isPassive = C_SpellBook.IsSpellBookItemPassive(slotIndex, bookType)
								local spellId = itemInfo.spellID

								if spellId and not isPassive then
									local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
									local spellName = spellInfo and spellInfo.name
									local spellIcon = spellInfo and spellInfo.iconID
										or (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId))
										or 134400

									if spellName then
										local matchesSearch = searchText == "" or spellName:lower():find(searchText, 1, true)
										if matchesSearch then
											table.insert(results, {
												id = spellId,
												name = spellName,
												icon = spellIcon,
											})
										end
									end
								end
							end
						end
					end
				end

				-- 이름순 정렬
				table.sort(results, function(a, b) return a.name < b.name end)
				return results
			end

			local function PopulateList(searchText)
				for _, row in ipairs(spellRows) do
					row:Hide()
				end

				local spells = SearchSpellbook(searchText)
				local yPos = 0
				local maxResults = 50

				for i, spell in ipairs(spells) do
					if i > maxResults then break end

					local row = spellRows[i]
					if not row then
						row = CreateFrame("Button", nil, scrollChild)
						row:SetSize(250, 24)

						local icon = row:CreateTexture(nil, "ARTWORK")
						icon:SetPoint("LEFT", 2, 0)
						icon:SetSize(20, 20)
						icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
						row.icon = icon

						local name = row:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
						name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
						name:SetJustifyH("LEFT")
						row.name = name

						local idText = row:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
						idText:SetPoint("RIGHT", -4, 0)
						idText:SetTextColor(0.5, 0.5, 0.5)
						row.idText = idText

						local hl = row:CreateTexture(nil, "HIGHLIGHT")
						hl:SetAllPoints()
						local accentColor = (popSL and popSL.GetAccent) and popSL.GetAccent("UnitFrames")
						local hlR, hlG, hlB = 0.3, 0.85, 0.45
						if accentColor and accentColor.from then hlR, hlG, hlB = accentColor.from[1], accentColor.from[2], accentColor.from[3] end
						hl:SetColorTexture(hlR, hlG, hlB, 0.25)

						spellRows[i] = row
					end

					row.icon:SetTexture(spell.icon)
					row.name:SetText(spell.name)
					row.name:SetTextColor(1, 1, 1)
					row.idText:SetText(spell.id)
					row:SetPoint("TOPLEFT", 0, -yPos)

					row:SetScript("OnClick", function()
						if popup.onSelect then
							popup.onSelect(spell.id, spell.name, spell.icon)
						end
						popup:Hide()
					end)

					row:Show()
					yPos = yPos + 26
				end

				scrollChild:SetHeight(math.max(1, yPos))
			end

			searchBox:SetScript("OnTextChanged", function(self)
				local text = self:GetText()
				if text == "" and not self:HasFocus() then searchPlaceholder:Show()
				else searchPlaceholder:Hide() end
				PopulateList(text)
			end)

			popup.PopulateList = PopulateList
			ns._spellPickerPopup = popup
		end

		-- 콜백 설정 및 표시
		ns._spellPickerPopup.onSelect = function(spellId, spellName, spellIcon)
			SetSelectedSpell(spellId, spellName, spellIcon)
		end
		ns._spellPickerPopup:Show()
		ns._spellPickerPopup.PopulateList("")
	end)

	-- [UF-OPTIONS] 직접 ID 입력 (보조)
	local ccSpellIdLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	ccSpellIdLabel:SetPoint("LEFT", ccSpellPickBtn, "RIGHT", 10, 0)
	ccSpellIdLabel:SetText("또는 ID:")
	ccSpellIdLabel:SetTextColor(0.5, 0.5, 0.5)

	local ccSpellInput = Widgets:CreateEditBox(parent, 60, 24, true)
	ccSpellInput:SetPlaceholder("ID")
	ccSpellInput:SetPoint("LEFT", ccSpellIdLabel, "RIGHT", 4, 0)
	ccSpellInput:SetScript("OnEnterPressed", function(self)
		local spellId = tonumber(self:GetText())
		if spellId then
			local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
			local spellName = spellInfo and spellInfo.name or ("ID:" .. spellId)
			local spellIcon = spellInfo and spellInfo.iconID or 134400
			SetSelectedSpell(spellId, spellName, spellIcon)
		end
		self:ClearFocus()
	end)
	yOffset = yOffset - 30

	local ccAddBtn = Widgets:CreateButton(parent, "바인딩 추가", "accent", { 90, 24 })
	ccAddBtn:SetPoint("TOPLEFT", 15, yOffset)
	ccAddBtn:SetScript("OnClick", function()
		local mod = ccModDropdown:GetSelected() or "none"
		local btn = ccBtnDropdown:GetSelected() or "1"

		-- 스펠북 선택 or 직접 ID 입력
		local spellId = ccSelectedSpellId or tonumber(ccSpellInput:GetText())
		if not spellId then return end

		if not ns.db.clickCasting then ns.db.clickCasting = { enabled = false, bindings = {} } end
		if not ns.db.clickCasting.bindings then ns.db.clickCasting.bindings = {} end
		table.insert(ns.db.clickCasting.bindings, { modifier = mod, button = btn, spellId = spellId })
		ccSpellInput:SetText("")
		SetSelectedSpell(nil) -- 선택 초기화
		RefreshBindingList()
		if ns.ClickCasting and ns.db.clickCasting.enabled then ns.ClickCasting:Initialize() end
	end)

	local ccRemoveBtn = Widgets:CreateButton(parent, "마지막 삭제", "red", { 80, 24 })
	ccRemoveBtn:SetPoint("LEFT", ccAddBtn, "RIGHT", 10, 0)
	ccRemoveBtn:SetScript("OnClick", function()
		local bindings = ns.db.clickCasting and ns.db.clickCasting.bindings
		if bindings and #bindings > 0 then
			table.remove(bindings)
			RefreshBindingList()
			if ns.ClickCasting and ns.db.clickCasting.enabled then ns.ClickCasting:Initialize() end
		end
	end)
	yOffset = yOffset - 40

	-- Targeted Spells
	local tsSep = Widgets:CreateSeparator(parent, "수신 주문 경고", CONTENT_WIDTH - 40)
	tsSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local tsDesc = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	tsDesc:SetText("적이 아군을 대상으로 주문 시전 시 해당 프레임 강조 표시")
	tsDesc:SetTextColor(0.6, 0.6, 0.6)
	tsDesc:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 20

	local tsCheck = Widgets:CreateCheckButton(parent, "수신 주문 경고 활성화", function(checked)
		if not ns.db.targetedSpells then ns.db.targetedSpells = { enabled = false } end
		ns.db.targetedSpells.enabled = checked
		if ns.TargetedSpells then
			if checked then
				ns.TargetedSpells:Initialize()
			else
				ns.TargetedSpells:Disable()
			end
		end
	end)
	tsCheck:SetPoint("TOPLEFT", 15, yOffset)
	tsCheck:SetChecked(ns.db.targetedSpells and ns.db.targetedSpells.enabled)
	yOffset = yOffset - 30

	-- [OPTION-ADD] 수신 주문 경고 색상
	local tsColorCP = Widgets:CreateColorPicker(parent, "경고 색상", true, function(r, g, b, a)
		if not ns.db.targetedSpells then ns.db.targetedSpells = {} end
		ns.db.targetedSpells.color = { r, g, b, a }
		if ns.TargetedSpells and ns.TargetedSpells.ForceUpdateAll then
			ns.TargetedSpells:ForceUpdateAll()
		end
	end)
	tsColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local tsc = ns.db.targetedSpells and ns.db.targetedSpells.color or { 1, 0.2, 0.1, 0.3 }
	tsColorCP:SetColor(tsc[1], tsc[2], tsc[3], tsc[4])
	yOffset = yOffset - 45

	-- My Buff Indicators
	local mbSep = Widgets:CreateSeparator(parent, "내 버프 인디케이터", CONTENT_WIDTH - 40)
	mbSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local mbDesc = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	mbDesc:SetText("내가 시전한 버프가 대상에 적용 시 체력바 하단에 색상 바 표시 (HoT 추적)")
	mbDesc:SetTextColor(0.6, 0.6, 0.6)
	mbDesc:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 20

	local mbCheck = Widgets:CreateCheckButton(parent, "내 버프 인디케이터 활성화", function(checked)
		if not ns.db.myBuffIndicators then ns.db.myBuffIndicators = { enabled = false } end
		ns.db.myBuffIndicators.enabled = checked
		if ns.MyBuffIndicators then
			if checked then
				ns.MyBuffIndicators:Initialize()
			else
				ns.MyBuffIndicators:Disable()
			end
		end
	end)
	mbCheck:SetPoint("TOPLEFT", 15, yOffset)
	mbCheck:SetChecked(ns.db.myBuffIndicators and ns.db.myBuffIndicators.enabled)
	yOffset = yOffset - 35

	local mbMaxSlider = Widgets:CreateSlider("최대 표시 수", parent, 1, 8, 120, 1, nil, function(value)
		if not ns.db.myBuffIndicators then ns.db.myBuffIndicators = {} end
		ns.db.myBuffIndicators.maxIndicators = value
		if ns.MyBuffIndicators then ns.MyBuffIndicators:ForceUpdateAll() end
	end)
	mbMaxSlider:SetPoint("TOPLEFT", 15, yOffset)
	mbMaxSlider:SetValue(ns.db.myBuffIndicators and ns.db.myBuffIndicators.maxIndicators or 3)

	local mbHeightSlider = Widgets:CreateSlider("바 높이", parent, 1, 8, 120, 1, nil, function(value)
		if not ns.db.myBuffIndicators then ns.db.myBuffIndicators = {} end
		ns.db.myBuffIndicators.barHeight = value
		if ns.MyBuffIndicators then ns.MyBuffIndicators:ForceUpdateAll() end
	end)
	mbHeightSlider:SetPoint("LEFT", mbMaxSlider, "RIGHT", 40, 0)
	mbHeightSlider:SetValue(ns.db.myBuffIndicators and ns.db.myBuffIndicators.barHeight or 3)
	yOffset = yOffset - 60

	-- [OPTION-ADD] 내 버프 인디케이터 간격/위치/색상
	local mbSpacingSlider = Widgets:CreateSlider("간격", parent, 0, 5, 120, 1, nil, function(value)
		if not ns.db.myBuffIndicators then ns.db.myBuffIndicators = {} end
		ns.db.myBuffIndicators.spacing = value
		if ns.MyBuffIndicators then ns.MyBuffIndicators:ForceUpdateAll() end
	end)
	mbSpacingSlider:SetPoint("TOPLEFT", 15, yOffset)
	mbSpacingSlider:SetValue(ns.db.myBuffIndicators and ns.db.myBuffIndicators.spacing or 1)

	local mbPosLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	mbPosLabel:SetText("위치")
	mbPosLabel:SetTextColor(0.7, 0.7, 0.7)
	mbPosLabel:SetPoint("LEFT", mbSpacingSlider, "RIGHT", 50, 18)
	local mbPosDropdown = Widgets:CreateDropdown(parent, 120)
	mbPosDropdown:SetPoint("TOPLEFT", mbPosLabel, "BOTTOMLEFT", 0, -3)
	mbPosDropdown:SetItems({
		{ text = "하단", value = "BOTTOM" },
		{ text = "상단", value = "TOP" },
	})
	mbPosDropdown:SetSelected(ns.db.myBuffIndicators and ns.db.myBuffIndicators.position or "BOTTOM")
	mbPosDropdown.OnValueChanged = function(_, value)
		if not ns.db.myBuffIndicators then ns.db.myBuffIndicators = {} end
		ns.db.myBuffIndicators.position = value
		if ns.MyBuffIndicators then ns.MyBuffIndicators:ForceUpdateAll() end
	end
	yOffset = yOffset - 60

	local mbColorCP = Widgets:CreateColorPicker(parent, "기본 색상 (nil=클래스색)", true, function(r, g, b, a)
		if not ns.db.myBuffIndicators then ns.db.myBuffIndicators = {} end
		ns.db.myBuffIndicators.defaultColor = { r, g, b, a }
		if ns.MyBuffIndicators then ns.MyBuffIndicators:ForceUpdateAll() end
	end)
	mbColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local mbc = ns.db.myBuffIndicators and ns.db.myBuffIndicators.defaultColor
	if mbc then
		mbColorCP:SetColor(mbc[1], mbc[2], mbc[3], mbc[4])
	else
		-- 클래스 색상 기본값 표시
		local _, class = UnitClass("player")
		local cc = RAID_CLASS_COLORS[class or "WARRIOR"]
		mbColorCP:SetColor(cc and cc.r or 0.2, cc and cc.g or 0.8, cc and cc.b or 0.2, 0.7)
	end

	local mbColorResetBtn = Widgets:CreateButton(parent, "클래스색 복원", nil, { 90, 22 })
	mbColorResetBtn:SetPoint("LEFT", mbColorCP, "RIGHT", 10, 0)
	mbColorResetBtn:SetScript("OnClick", function()
		if not ns.db.myBuffIndicators then ns.db.myBuffIndicators = {} end
		ns.db.myBuffIndicators.defaultColor = nil
		local _, cls = UnitClass("player")
		local cc2 = RAID_CLASS_COLORS[cls or "WARRIOR"]
		mbColorCP:SetColor(cc2 and cc2.r or 0.2, cc2 and cc2.g or 0.8, cc2 and cc2.b or 0.2, 0.7)
		if ns.MyBuffIndicators then ns.MyBuffIndicators:ForceUpdateAll() end
	end)
	yOffset = yOffset - 45

	-- [AURA-FILTER] PrivateAuras → 별도 BuildPrivateAurasPage로 이전됨 (생략)

	-- Dispel Highlight
	local dhSep = Widgets:CreateSeparator(parent, "해제 강조", CONTENT_WIDTH - 40)
	dhSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local dhDesc = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	dhDesc:SetText("해제 가능한 디버프 존재 시 프레임 테두리 색상 강조 (파티/레이드)")
	dhDesc:SetTextColor(0.6, 0.6, 0.6)
	dhDesc:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 20

	local dhCheck = Widgets:CreateCheckButton(parent, "해제 강조 활성화", function(checked)
		if not ns.db.dispelHighlight then ns.db.dispelHighlight = { enabled = true } end
		ns.db.dispelHighlight.enabled = checked
		ns.Print("해제 강조 변경은 /reload 후 적용됩니다.")
	end)
	dhCheck:SetPoint("TOPLEFT", 15, yOffset)
	dhCheck:SetChecked(ns.db.dispelHighlight and ns.db.dispelHighlight.enabled ~= false)

	local dhDispelOnlyCheck = Widgets:CreateCheckButton(parent, "해제 가능한 것만 표시", function(checked)
		if not ns.db.dispelHighlight then ns.db.dispelHighlight = {} end
		ns.db.dispelHighlight.onlyShowDispellable = checked
	end)
	dhDispelOnlyCheck:SetPoint("LEFT", dhCheck, "RIGHT", 180, 0)
	dhDispelOnlyCheck:SetChecked(ns.db.dispelHighlight and ns.db.dispelHighlight.onlyShowDispellable ~= false)
	yOffset = yOffset - 50

	-- [OPTION-ADD] 해제 강조 모드 및 상세 설정
	local dhModeDropdown = Widgets:CreateDropdown(parent, 130)
	dhModeDropdown:SetPoint("TOPLEFT", 15, yOffset)
	dhModeDropdown:SetItems({
		{ text = "테두리 색상", value = "border" },
		{ text = "글로우 효과", value = "glow" },
		{ text = "그라데이션", value = "gradient" },
		{ text = "아이콘", value = "icon" },
	})
	dhModeDropdown:SetSelected(ns.db.dispelHighlight and ns.db.dispelHighlight.mode or "border")

	local dhModeLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	dhModeLabel:SetText("강조 모드")
	dhModeLabel:SetTextColor(0.7, 0.7, 0.7)
	dhModeLabel:SetPoint("BOTTOM", dhModeDropdown, "TOP", 0, 2)

	-- 모드별 조건부 컨트롤
	-- Glow 설정
	local dhGlowTypeDropdown = Widgets:CreateDropdown(parent, 120)
	dhGlowTypeDropdown:SetPoint("LEFT", dhModeDropdown, "RIGHT", 30, 0)
	dhGlowTypeDropdown:SetItems({
		{ text = "픽셀", value = "pixel" },
		{ text = "빛남", value = "shine" },
		{ text = "전문기 효과", value = "proc" },
	})
	dhGlowTypeDropdown:SetSelected(ns.db.dispelHighlight and ns.db.dispelHighlight.glowType or "pixel")
	dhGlowTypeDropdown.OnValueChanged = function(_, value)
		if not ns.db.dispelHighlight then ns.db.dispelHighlight = {} end
		ns.db.dispelHighlight.glowType = value
		ns.Print("해제 강조 변경은 /reload 후 적용됩니다.")
	end

	local dhGlowLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	dhGlowLabel:SetText("글로우 타입")
	dhGlowLabel:SetTextColor(0.7, 0.7, 0.7)
	dhGlowLabel:SetPoint("BOTTOM", dhGlowTypeDropdown, "TOP", 0, 2)

	local dhGlowThickSlider = Widgets:CreateSlider("글로우 두께", parent, 1, 8, 120, 1, nil, function(value)
		if not ns.db.dispelHighlight then ns.db.dispelHighlight = {} end
		ns.db.dispelHighlight.glowThickness = value
		ns.Print("해제 강조 변경은 /reload 후 적용됩니다.")
	end)
	dhGlowThickSlider:SetPoint("LEFT", dhGlowTypeDropdown, "RIGHT", 30, 0)
	dhGlowThickSlider:SetValue(ns.db.dispelHighlight and ns.db.dispelHighlight.glowThickness or 2)
	yOffset = yOffset - 65

	-- Gradient 설정
	local dhGradAlphaSlider = Widgets:CreateSlider("그라데이션 투명도", parent, 0, 1, 160, 0.05, nil, function(value)
		if not ns.db.dispelHighlight then ns.db.dispelHighlight = {} end
		ns.db.dispelHighlight.gradientAlpha = value
		ns.Print("해제 강조 변경은 /reload 후 적용됩니다.")
	end)
	dhGradAlphaSlider:SetPoint("TOPLEFT", 15, yOffset)
	dhGradAlphaSlider:SetValue(ns.db.dispelHighlight and ns.db.dispelHighlight.gradientAlpha or 0.4)

	-- Icon 설정
	local dhIconSizeSlider = Widgets:CreateSlider("아이콘 크기", parent, 8, 32, 120, 1, nil, function(value)
		if not ns.db.dispelHighlight then ns.db.dispelHighlight = {} end
		ns.db.dispelHighlight.iconSize = value
		ns.Print("해제 강조 변경은 /reload 후 적용됩니다.")
	end)
	dhIconSizeSlider:SetPoint("LEFT", dhGradAlphaSlider, "RIGHT", 40, 0)
	dhIconSizeSlider:SetValue(ns.db.dispelHighlight and ns.db.dispelHighlight.iconSize or 14)

	local dhIconPosDropdown = Widgets:CreateDropdown(parent, 120)
	dhIconPosDropdown:SetPoint("LEFT", dhIconSizeSlider, "RIGHT", 30, 0)
	dhIconPosDropdown:SetItems({
		{ text = "우측상단", value = "TOPRIGHT" },
		{ text = "좌측상단", value = "TOPLEFT" },
		{ text = "우측하단", value = "BOTTOMRIGHT" },
		{ text = "좌측하단", value = "BOTTOMLEFT" },
		{ text = "중앙", value = "CENTER" },
	})
	dhIconPosDropdown:SetSelected(ns.db.dispelHighlight and ns.db.dispelHighlight.iconPosition or "TOPRIGHT")
	dhIconPosDropdown.OnValueChanged = function(_, value)
		if not ns.db.dispelHighlight then ns.db.dispelHighlight = {} end
		ns.db.dispelHighlight.iconPosition = value
		ns.Print("해제 강조 변경은 /reload 후 적용됩니다.")
	end

	local dhIconPosLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	dhIconPosLabel:SetText("아이콘 위치")
	dhIconPosLabel:SetTextColor(0.7, 0.7, 0.7)
	dhIconPosLabel:SetPoint("BOTTOM", dhIconPosDropdown, "TOP", 0, 2)
	yOffset = yOffset - 60

	-- 모드 변경 시 조건부 표시/숨기기
	local dhGlowWidgets = { dhGlowTypeDropdown, dhGlowLabel, dhGlowThickSlider }
	local dhGradWidgets = { dhGradAlphaSlider }
	local dhIconWidgets = { dhIconSizeSlider, dhIconPosDropdown, dhIconPosLabel }

	local function UpdateDispelModeWidgets(mode)
		for _, w in ipairs(dhGlowWidgets) do w:SetAlpha(mode == "glow" and 1 or 0.3) end
		for _, w in ipairs(dhGradWidgets) do w:SetAlpha(mode == "gradient" and 1 or 0.3) end
		for _, w in ipairs(dhIconWidgets) do w:SetAlpha(mode == "icon" and 1 or 0.3) end
	end
	UpdateDispelModeWidgets(ns.db.dispelHighlight and ns.db.dispelHighlight.mode or "border")

	dhModeDropdown.OnValueChanged = function(_, value)
		if not ns.db.dispelHighlight then ns.db.dispelHighlight = {} end
		ns.db.dispelHighlight.mode = value
		UpdateDispelModeWidgets(value)
		ns.Print("해제 강조 변경은 /reload 후 적용됩니다.")
	end

	-- Health Gradient
	local hgSep = Widgets:CreateSeparator(parent, "체력 그라데이션", CONTENT_WIDTH - 40)
	hgSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local hgDesc = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	hgDesc:SetText("체력 비율에 따라 체력바 색상을 그라데이션으로 표시 (빨강 → 노랑 → 초록)")
	hgDesc:SetTextColor(0.6, 0.6, 0.6)
	hgDesc:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 20

	-- [OPTION-ADD] 체력 그라데이션 활성화 + 3색 피커
	local hgCheck = Widgets:CreateCheckButton(parent, "체력 그라데이션 활성화", function(checked)
		if not ns.db.healthGradient then ns.db.healthGradient = { enabled = false, colors = { 1, 0, 0, 1, 1, 0, 0, 1, 0 } } end
		ns.db.healthGradient.enabled = checked
		ns.Print("체력 그라데이션 변경은 /reload 후 적용됩니다.")
	end)
	hgCheck:SetPoint("TOPLEFT", 15, yOffset)
	hgCheck:SetChecked(ns.db.healthGradient and ns.db.healthGradient.enabled)
	yOffset = yOffset - 30

	local hgColors = ns.db.healthGradient and ns.db.healthGradient.colors or { 1, 0, 0, 1, 1, 0, 0, 1, 0 }

	local hgLowCP = Widgets:CreateColorPicker(parent, "위험 (0%)", false, function(r, g, b)
		if not ns.db.healthGradient then ns.db.healthGradient = { enabled = false, colors = { 1, 0, 0, 1, 1, 0, 0, 1, 0 } } end
		ns.db.healthGradient.colors[1] = r
		ns.db.healthGradient.colors[2] = g
		ns.db.healthGradient.colors[3] = b
	end)
	hgLowCP:SetPoint("TOPLEFT", 15, yOffset)
	hgLowCP:SetColor(hgColors[1], hgColors[2], hgColors[3])

	local hgMidCP = Widgets:CreateColorPicker(parent, "보통 (50%)", false, function(r, g, b)
		if not ns.db.healthGradient then ns.db.healthGradient = { enabled = false, colors = { 1, 0, 0, 1, 1, 0, 0, 1, 0 } } end
		ns.db.healthGradient.colors[4] = r
		ns.db.healthGradient.colors[5] = g
		ns.db.healthGradient.colors[6] = b
	end)
	hgMidCP:SetPoint("LEFT", hgLowCP, "RIGHT", 110, 0)
	hgMidCP:SetColor(hgColors[4], hgColors[5], hgColors[6])

	local hgHighCP = Widgets:CreateColorPicker(parent, "안전 (100%)", false, function(r, g, b)
		if not ns.db.healthGradient then ns.db.healthGradient = { enabled = false, colors = { 1, 0, 0, 1, 1, 0, 0, 1, 0 } } end
		ns.db.healthGradient.colors[7] = r
		ns.db.healthGradient.colors[8] = g
		ns.db.healthGradient.colors[9] = b
	end)
	hgHighCP:SetPoint("LEFT", hgMidCP, "RIGHT", 110, 0)
	hgHighCP:SetColor(hgColors[7], hgColors[8], hgColors[9])
	parent:SetHeight(math.abs(yOffset) + 50)
	parent._skipAutoHeight = true
end

pageBuilders["general.profiles"] = function(parent)
	local header = CreatePageHeader(parent, "프로필 관리", "설정 프로필 생성, 전환, 가져오기/내보내기")

	local yOffset = -60
	local Profiles = ns.Profiles

	-- Current profile section
	local currentSep = Widgets:CreateSeparator(parent, "현재 프로필", CONTENT_WIDTH - 40)
	currentSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Profile dropdown
	local profileDropdown = Widgets:CreateDropdown(parent, 200)
	profileDropdown:SetPoint("TOPLEFT", 15, yOffset)

	local function UpdateProfileList()
		local items = {}
		local profiles = Profiles and Profiles:GetList() or { "Default" }
		local current = Profiles and Profiles:GetCurrent() or "Default"

		for _, name in ipairs(profiles) do
			table.insert(items, {
				text = name,
				value = name,
			})
		end

		profileDropdown:SetItems(items)
		profileDropdown:SetSelected(current)
	end
	UpdateProfileList()

	profileDropdown:SetOnSelect(function(value)
		if Profiles then
			Profiles:Switch(value)
			if currentPage then LoadPage(currentPage) end -- [REFACTOR] 프로필 전환 후 UI 갱신
		end
	end)

	-- Switch button
	local switchBtn = Widgets:CreateButton(parent, "전환", "class", { 60, 26 })
	switchBtn:SetPoint("LEFT", profileDropdown, "RIGHT", 10, 0)
	switchBtn:SetScript("OnClick", function()
		local selected = profileDropdown:GetSelected()
		if Profiles and selected then
			Profiles:Switch(selected)
			if currentPage then LoadPage(currentPage) end -- [REFACTOR] 프로필 전환 후 UI 갱신
		end
	end)

	yOffset = yOffset - 45

	-- New profile section
	local newSep = Widgets:CreateSeparator(parent, "프로필 생성", CONTENT_WIDTH - 40)
	newSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- New profile name input
	local newNameLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	newNameLabel:SetText("새 프로필 이름:")
	newNameLabel:SetPoint("TOPLEFT", 15, yOffset)

	local newNameEdit = Widgets:CreateEditBox(parent, 200, 24)
	newNameEdit:SetPoint("LEFT", newNameLabel, "RIGHT", 10, 0)
	newNameEdit:SetPlaceholder("프로필 이름 입력...")
	yOffset = yOffset - 35

	-- Copy from dropdown
	local copyLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	copyLabel:SetText("복사 원본:")
	copyLabel:SetPoint("TOPLEFT", 15, yOffset)

	local copyDropdown = Widgets:CreateDropdown(parent, 200)
	copyDropdown:SetPoint("LEFT", copyLabel, "RIGHT", 10, 0)

	local function UpdateCopyDropdown()
		local items = { { text = "(새로 만들기)", value = nil } }
		local profiles = Profiles and Profiles:GetList() or { "Default" }
		for _, name in ipairs(profiles) do
			table.insert(items, { text = name, value = name })
		end
		copyDropdown:SetItems(items)
		copyDropdown:SetSelected(nil)
	end
	UpdateCopyDropdown()
	yOffset = yOffset - 35

	-- Create button
	local createBtn = Widgets:CreateButton(parent, "프로필 생성", "green", { 120, 28 })
	createBtn:SetPoint("TOPLEFT", 15, yOffset)
	createBtn:SetScript("OnClick", function()
		local name = newNameEdit:GetText()
		if name and name ~= "" and Profiles then
			local copyFrom = copyDropdown:GetSelected()
			local success, err = Profiles:Create(name, copyFrom)
			if success then
				newNameEdit:SetText("")
				UpdateProfileList()
				UpdateCopyDropdown()
			else
				ns.Print("오류: " .. (err or "알 수 없는 오류"))
			end
		else
			ns.Print("프로필 이름을 입력하세요.")
		end
	end)

	-- Delete button
	local deleteBtn = Widgets:CreateButton(parent, "프로필 삭제", "red", { 120, 28 })
	deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 10, 0)
	deleteBtn:SetScript("OnClick", function()
		local selected = profileDropdown:GetSelected()
		if selected and selected ~= "Default" and Profiles then
			StaticPopup_Show("DDINGUI_UF_DELETE_PROFILE", selected, nil, selected) -- [REFACTOR] 4번째 인수=data
		elseif selected == "Default" then
			ns.Print("기본 프로필은 삭제할 수 없습니다.")
		end
	end)

	yOffset = yOffset - 50

	-- Reset section
	local resetSep = Widgets:CreateSeparator(parent, "프로필 초기화", CONTENT_WIDTH - 40)
	resetSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local resetBtn = Widgets:CreateButton(parent, "현재 프로필 초기화", "red", { 150, 28 })
	resetBtn:SetPoint("TOPLEFT", 15, yOffset)
	resetBtn:SetScript("OnClick", function()
		StaticPopup_Show("DDINGUI_UF_RESET_PROFILE")
	end)

	yOffset = yOffset - 50

	-- [SPEC-SWITCH] 전문화별 프로필 자동 전환 섹션
	do
		local specSep = Widgets:CreateSeparator(parent, "전문화별 프로필 자동 전환", CONTENT_WIDTH - 40)
		specSep:SetPoint("TOPLEFT", 15, yOffset)
		yOffset = yOffset - 35

		local spDB = Profiles and Profiles:GetSpecProfilesDB()

		-- 마스터 토글
		local specToggle = Widgets:CreateCheckButton(parent, "전문화 변경 시 프로필 자동 전환", function(checked)
			local db = Profiles and Profiles:GetSpecProfilesDB()
			if db then
				db.enabled = checked
			end
		end)
		specToggle:SetPoint("TOPLEFT", 15, yOffset)
		specToggle:SetChecked(spDB and spDB.enabled or false)
		yOffset = yOffset - 30

		-- 전문화 목록 (동적 감지)
		local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
		local currentSpecIndex = GetSpecialization and GetSpecialization()

		if numSpecs > 0 then
			-- 현재 직업명
			local _, className = UnitClass("player")
			local localizedClass = UnitClass("player")
			local classLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
			classLabel:SetText("현재 직업: |cffffffff" .. (localizedClass or "알 수 없음") .. "|r")
			classLabel:SetPoint("TOPLEFT", 15, yOffset)
			yOffset = yOffset - 30

			-- 프로필 목록 아이템 생성 헬퍼
			local function BuildProfileItems()
				local items = { { text = "(없음)", value = "" } }
				local profiles = Profiles and Profiles:GetList() or {}
				for _, name in ipairs(profiles) do
					table.insert(items, { text = name, value = name })
				end
				return items
			end

			-- 전문화별 드롭다운
			local specDropdowns = {}
			for i = 1, numSpecs do
				local specID, specName, _, specIcon = GetSpecializationInfo(i)
				if specID and specName then
					local isCurrent = (i == currentSpecIndex)

					-- 아이콘
					local icon = parent:CreateTexture(nil, "ARTWORK")
					icon:SetSize(20, 20)
					icon:SetPoint("TOPLEFT", 15, yOffset)
					icon:SetTexture(specIcon)
					icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

					-- 전문화 이름
					local nameLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
					if isCurrent then
						local SL = _G.DDingUI_StyleLib
					local accent = SL and SL.GetAccent and SL.GetAccent("UnitFrames")
					local ar, ag, ab = 0.30, 0.85, 0.45
						if accent and accent.from then
							ar, ag, ab = accent.from[1] or ar, accent.from[2] or ag, accent.from[3] or ab
						end
						nameLabel:SetText(string.format("|cff%02x%02x%02x%s (현재)|r",
							math.floor(ar * 255 + 0.5), math.floor(ag * 255 + 0.5), math.floor(ab * 255 + 0.5),
							specName))
					else
						nameLabel:SetText(specName)
					end
					nameLabel:SetPoint("LEFT", icon, "RIGHT", 8, 0)

					-- 드롭다운
					local specDD = Widgets:CreateDropdown(parent, 180)
					specDD:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
					specDD:SetItems(BuildProfileItems())

					-- 현재 매핑 값 설정
					local currentMapping = spDB and spDB.mappings and spDB.mappings[specID] or ""
					specDD:SetSelected(currentMapping)

					specDD:SetOnSelect(function(value)
						local db = Profiles and Profiles:GetSpecProfilesDB()
						if db then
							db.mappings = db.mappings or {}
							if value == "" then
								db.mappings[specID] = nil
							else
								db.mappings[specID] = value
							end
						end
					end)

					specDropdowns[specID] = specDD
					yOffset = yOffset - 30
				end
			end
		else
			local noSpecLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
			noSpecLabel:SetText("|cff999999전문화 정보를 불러올 수 없습니다.|r")
			noSpecLabel:SetPoint("TOPLEFT", 15, yOffset)
			yOffset = yOffset - 25
		end
	end

	yOffset = yOffset - 20

	-- Import/Export section
	local importSep = Widgets:CreateSeparator(parent, "가져오기 / 내보내기", CONTENT_WIDTH - 40)
	importSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Export button
	local exportBtn = Widgets:CreateButton(parent, "내보내기", "class", { 100, 28 })
	exportBtn:SetPoint("TOPLEFT", 15, yOffset)
	exportBtn:SetScript("OnClick", function()
		if Profiles then
			local exportStr = Profiles:Export()
			if exportStr then
				StaticPopup_Show("DDINGUI_UF_EXPORT_STRING", nil, nil, { exportString = exportStr })
			end
		end
	end)

	-- Import button
	local importBtn = Widgets:CreateButton(parent, "가져오기", "class", { 100, 28 })
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
	importBtn:SetScript("OnClick", function()
		StaticPopup_Show("DDINGUI_UF_IMPORT_STRING")
	end)

	yOffset = yOffset - 50

	-- Static popups
	StaticPopupDialogs["DDINGUI_UF_DELETE_PROFILE"] = {
		text = "'%s' 프로필을 삭제하시겠습니까?",
		button1 = "삭제",
		button2 = "취소",
		OnAccept = function(self, data)
			if Profiles then
				Profiles:Delete(data)
				UpdateProfileList()
				UpdateCopyDropdown()
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	StaticPopupDialogs["DDINGUI_UF_RESET_PROFILE"] = {
		text = "현재 프로필을 기본값으로 초기화하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
		button1 = "초기화",
		button2 = "취소",
		OnAccept = function()
			if Profiles then
				Profiles:ResetCurrent()
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	StaticPopupDialogs["DDINGUI_UF_RESET_CONFIRM"] = {
		text = "정말로 모든 설정을 초기화하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
		button1 = "확인",
		button2 = "취소",
		OnAccept = function()
			ddingUI_UFDB = nil
			ReloadUI()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	StaticPopupDialogs["DDINGUI_UF_EXPORT_STRING"] = {
		text = "프로필 내보내기\n아래 문자열을 복사하세요:",
		button1 = "확인",
		hasEditBox = true,
		editBoxWidth = 350,
		OnShow = function(self, data)
			local eb = self.editBox or self.EditBox
			if eb then
				eb:SetText(data.exportString)
				eb:HighlightText()
				eb:SetFocus()
			end
		end,
		EditBoxOnEscapePressed = function(self)
			self:GetParent():Hide()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	StaticPopupDialogs["DDINGUI_UF_IMPORT_STRING"] = {
		text = "프로필 가져오기\n내보내기 문자열을 붙여넣으세요:",
		button1 = "가져오기",
		button2 = "취소",
		hasEditBox = true,
		editBoxWidth = 350,
		OnAccept = function(self)
			local eb = self.editBox or self.EditBox
			local str = eb and eb:GetText()
			if str and str ~= "" and Profiles then
				local success, result = Profiles:Import(str)
				if success then
					ns.Print("프로필 가져오기 완료: " .. result)
				else
					ns.Print("오류: " .. (result or "알 수 없는 오류"))
				end
			end
		end,
		EditBoxOnEscapePressed = function(self)
			self:GetParent():Hide()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	parent:SetHeight(math.abs(yOffset) + 50)
	parent._skipAutoHeight = true
end

-----------------------------------------------
-- [REFACTOR] 유닛 미리보기 사이드바 시스템
-- 유닛 서브페이지 전환 시 왼쪽에 고정 표시
-----------------------------------------------

-- [12.0.1] Preview → TestMode 전환: 편집모드 프리뷰 실시간 갱신
-- 설정 변경 시 편집모드 프레임에 즉시 반영
local function RefreshCurrentPreview()
	if not currentPage then return end
	local unit = GetUnitFromCategory(currentPage)
	if unit and ns.Update and ns.Update.RefreshPreview then
		ns.Update:RefreshPreview(unit)
	end
end


-----------------------------------------------
-- Unit Frame General Page Builder

local function BuildUnitGeneralPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 기본 설정", "프레임 크기, 위치, 외형 설정")

	local settings = ns.db[unit]
	if not settings then return end

	local yOffset = -60

	-- Enable checkbox
	local enableCheck = Widgets:CreateCheckButton(parent, "활성화", function(checked)
		ns.db[unit].enabled = checked
		if ns.Update then
			ns.Update:UpdateEnabled(unit) -- [FIX] 활성화/비활성화 즉시 반영
			if checked then
				ns.Update:RefreshUnit(unit)
			end
		end
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(settings.enabled)
	yOffset = yOffset - 35

	-- Size section
	local sizeSep = Widgets:CreateSeparator(parent, "크기", CONTENT_WIDTH - 40)
	sizeSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Width slider
	local widthSlider = Widgets:CreateSlider("너비", parent, 50, 400, 120, 1, nil, function(value)
		if not ns.db[unit].size then ns.db[unit].size = {} end
		ns.db[unit].size[1] = value
		if ns.Update and ns.Update.UpdateSize then
			ns.Update:UpdateSize(unit)
		end
		RefreshCurrentPreview() -- [REFACTOR] 사이드바 미리보기 갱신
	end)
	widthSlider:SetPoint("TOPLEFT", 15, yOffset)
	widthSlider:SetValue(settings.size and settings.size[1] or 200)

	-- Height slider
	local heightSlider = Widgets:CreateSlider("높이", parent, 10, 100, 120, 1, nil, function(value)
		if not ns.db[unit].size then ns.db[unit].size = {} end
		ns.db[unit].size[2] = value
		if ns.Update and ns.Update.UpdateSize then
			ns.Update:UpdateSize(unit)
		end
		RefreshCurrentPreview() -- [REFACTOR] 사이드바 미리보기 갱신
	end)
	heightSlider:SetPoint("LEFT", widthSlider, "RIGHT", 30, 0)
	heightSlider:SetValue(settings.size and settings.size[2] or 40)
	yOffset = yOffset - 55

	-- Anchor options (if unit supports parent anchoring)
	if settings.anchorToParent ~= nil then
		local anchorSep = Widgets:CreateSeparator(parent, "앵커 설정", CONTENT_WIDTH - 40)
		anchorSep:SetPoint("TOPLEFT", 15, yOffset)
		yOffset = yOffset - 35

		local anchorCheck = Widgets:CreateCheckButton(parent, "부모 프레임에 연결", function(checked)
			ns.db[unit].anchorToParent = checked
			if ns.Update and ns.Update.UpdateAnchor then
				ns.Update:UpdateAnchor(unit)
			end
		end)
		anchorCheck:SetPoint("TOPLEFT", 15, yOffset)
		anchorCheck:SetChecked(settings.anchorToParent)
		yOffset = yOffset - 30

		if settings.anchorPosition then
			local posEditor = Widgets:CreatePositionEditor(parent, 280, function(pos)
				ns.db[unit].anchorPosition = pos
				if ns.Update and ns.Update.UpdateAnchor then
					ns.Update:UpdateAnchor(unit)
				end
			end)
			posEditor:SetPoint("TOPLEFT", 15, yOffset)
			posEditor:SetPosition(settings.anchorPosition)
			yOffset = yOffset - 110
		end
	end

	-- [OPTION-CLEANUP] healthBarColorType, reverseHealthFill, barOrientation 제거 - Health 페이지에 이미 있음

	-- Border section
	local borderSep = Widgets:CreateSeparator(parent, "테두리", CONTENT_WIDTH - 40)
	borderSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local borderEnabled = Widgets:CreateCheckButton(parent, "테두리 표시", function(checked)
		if not ns.db[unit].border then ns.db[unit].border = {} end
		ns.db[unit].border.enabled = checked
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview() -- [REFACTOR] 사이드바 미리보기 갱신
	end)
	borderEnabled:SetPoint("TOPLEFT", 15, yOffset)
	borderEnabled:SetChecked(settings.border and settings.border.enabled ~= false)

	local borderSizeSlider = Widgets:CreateSlider("두께", parent, 0.1, 3, 80, 0.1, nil, function(value)
		if not ns.db[unit].border then ns.db[unit].border = {} end
		ns.db[unit].border.size = value
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	borderSizeSlider:SetPoint("LEFT", borderEnabled, "RIGHT", 120, 0)
	borderSizeSlider:SetValue(settings.border and settings.border.size or 1)
	yOffset = yOffset - 35

	local borderColorCP = Widgets:CreateColorPicker(parent, "테두리 색상", true, function(r, g, b, a)
		if not ns.db[unit].border then ns.db[unit].border = {} end
		ns.db[unit].border.color = { r, g, b, a }
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview() -- [REFACTOR] 사이드바 미리보기 갱신
	end)
	borderColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local bc = settings.border and settings.border.color or { 0, 0, 0, 1 }
	borderColorCP:SetColor(bc[1], bc[2], bc[3], bc[4])
	yOffset = yOffset - 35

	-- [12.0.1] Boss/Arena 전용: 간격 + 성장방향
	if unit == "boss" or unit == "arena" then
		local layoutSep = Widgets:CreateSeparator(parent, "배치", CONTENT_WIDTH - 40)
		layoutSep:SetPoint("TOPLEFT", 15, yOffset)
		yOffset = yOffset - 35

		local spacingSlider = Widgets:CreateSlider("간격", parent, 0, 120, 120, 1, nil, function(value)
			ns.db[unit].spacing = value
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
			RefreshCurrentPreview()
		end)
		spacingSlider:SetPoint("TOPLEFT", 15, yOffset)
		spacingSlider:SetValue(settings.spacing or 48)

		local growItems = {
			{ text = "아래로", value = "DOWN" },
			{ text = "위로", value = "UP" },
		}
		local growDropdown = Widgets:CreateDropdown(parent, 120)
		growDropdown:SetPoint("LEFT", spacingSlider, "RIGHT", 30, 0)
		growDropdown:SetItems(growItems)
		growDropdown:SetSelected(settings.growDirection or "DOWN")
		growDropdown:SetOnSelect(function(value)
			ns.db[unit].growDirection = value
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
			RefreshCurrentPreview()
		end)

		-- 성장방향 라벨
		local growLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		growLabel:SetText("성장 방향")
		growLabel:SetPoint("BOTTOMLEFT", growDropdown, "TOPLEFT", 0, 4)

		yOffset = yOffset - 55
	end

	-- [CDM 호환] 독립 유닛의 attachTo/selfPoint/anchorPoint 설정
	-- (anchorToParent를 사용하는 종속 유닛은 위 부모 앵커 섹션 사용)
	if settings.attachTo ~= nil or (unit == "player" or unit == "target" or unit == "focus" or unit == "boss" or unit == "arena") then
		local cdmSep = Widgets:CreateSeparator(parent, "CDM 앵커 연결", CONTENT_WIDTH - 40)
		cdmSep:SetPoint("TOPLEFT", 15, yOffset)
		yOffset = yOffset - 35

		-- attachTo 드롭다운
		local attachLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		attachLabel:SetText("연결 대상 프레임")
		attachLabel:SetPoint("TOPLEFT", 15, yOffset)

		local attachItems = {
			{ text = "UIParent (화면)", value = "UIParent" },
		}
		-- [CDM 호환] CDM 프록시 앵커 동적 감지 (DDingUI CDM 로드 시에만 표시)
		local CDM_PROXIES = {
			{ name = "DDingUI_Anchor_Cooldowns", label = "CDM: 핵심 능력" },
			{ name = "DDingUI_Anchor_Buffs",     label = "CDM: 강화 효과" },
			{ name = "DDingUI_Anchor_Utility",   label = "CDM: 보조 능력" },
		}
		for _, proxy in ipairs(CDM_PROXIES) do
			if _G[proxy.name] then
				table.insert(attachItems, { text = proxy.label, value = proxy.name })
			end
		end
		-- [CDM 호환] CDM 그룹 프레임 (동적 감지)
		local CDM_GROUPS = {
			{ name = "DDingUI_Group_Cooldowns", label = "CDM 그룹: 핵심" },
			{ name = "DDingUI_Group_Buffs",     label = "CDM 그룹: 강화" },
			{ name = "DDingUI_Group_Utility",   label = "CDM 그룹: 보조" },
		}
		for _, grp in ipairs(CDM_GROUPS) do
			if _G[grp.name] then
				table.insert(attachItems, { text = grp.label, value = grp.name })
			end
		end
		-- DDingUI_UF 프레임 추가
		local ufFrames = {
			{ text = "UF: 플레이어", value = "ddingUI_Player" },
			{ text = "UF: 대상", value = "ddingUI_Target" },
			{ text = "UF: 초점", value = "ddingUI_Focus" },
			{ text = "UF: 소환수", value = "ddingUI_Pet" },
			{ text = "UF: 보스1", value = "ddingUI_Boss1" },
		}
		for _, ufItem in ipairs(ufFrames) do
			-- 자기 자신은 제외
			local frameName = unit == "player" and "ddingUI_Player"
				or unit == "target" and "ddingUI_Target"
				or unit == "focus" and "ddingUI_Focus"
				or nil
			if ufItem.value ~= frameName then
				table.insert(attachItems, ufItem)
			end
		end

		local attachDropdown = Widgets:CreateDropdown(parent, 200)
		attachDropdown:SetPoint("TOPLEFT", attachLabel, "BOTTOMLEFT", 0, -5)
		attachDropdown:SetItems(attachItems)
		attachDropdown:SetSelected(settings.attachTo or "UIParent")
		attachDropdown:SetOnSelect(function(value)
			ns.db[unit].attachTo = value
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		end)
		yOffset = yOffset - 55

		-- selfPoint / anchorPoint 드롭다운
		local ANCHOR_POINTS = {
			{ text = "TOPLEFT", value = "TOPLEFT" },
			{ text = "TOP", value = "TOP" },
			{ text = "TOPRIGHT", value = "TOPRIGHT" },
			{ text = "LEFT", value = "LEFT" },
			{ text = "CENTER", value = "CENTER" },
			{ text = "RIGHT", value = "RIGHT" },
			{ text = "BOTTOMLEFT", value = "BOTTOMLEFT" },
			{ text = "BOTTOM", value = "BOTTOM" },
			{ text = "BOTTOMRIGHT", value = "BOTTOMRIGHT" },
		}

		local spLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		spLabel:SetText("기준점 (Self)")
		spLabel:SetPoint("TOPLEFT", 15, yOffset)

		local spDropdown = Widgets:CreateDropdown(parent, 130)
		spDropdown:SetPoint("TOPLEFT", spLabel, "BOTTOMLEFT", 0, -5)
		spDropdown:SetItems(ANCHOR_POINTS)
		spDropdown:SetSelected(settings.selfPoint or settings.anchorPoint or "CENTER")
		spDropdown:SetOnSelect(function(value)
			ns.db[unit].selfPoint = value
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		end)

		local apLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		apLabel:SetText("앵커 포인트")
		apLabel:SetPoint("TOPLEFT", 200, yOffset)

		local apDropdown = Widgets:CreateDropdown(parent, 130)
		apDropdown:SetPoint("TOPLEFT", apLabel, "BOTTOMLEFT", 0, -5)
		apDropdown:SetItems(ANCHOR_POINTS)
		apDropdown:SetSelected(settings.anchorPoint or "CENTER")
		apDropdown:SetOnSelect(function(value)
			ns.db[unit].anchorPoint = value
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		end)
		yOffset = yOffset - 55

		-- X/Y 오프셋 슬라이더
		local attachXSlider = Widgets:CreateSlider("X 오프셋", parent, -500, 500, 120, 1, nil, function(value)
			if not ns.db[unit].position then ns.db[unit].position = { 0, 0 } end
			ns.db[unit].position[1] = value
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		end)
		attachXSlider:SetPoint("TOPLEFT", 15, yOffset)
		local posX = settings.position and settings.position[1]
		if type(posX) == "string" and settings.position[4] then posX = settings.position[4] end -- {point, rel, relPt, x, y} 형식
		posX = tonumber(posX) or 0
		if posX ~= posX or posX < -500 or posX > 500 then posX = 0 end -- NaN/범위 방어
		attachXSlider:SetValue(posX)

		local attachYSlider = Widgets:CreateSlider("Y 오프셋", parent, -500, 500, 120, 1, nil, function(value)
			if not ns.db[unit].position then ns.db[unit].position = { 0, 0 } end
			ns.db[unit].position[2] = value
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		end)
		attachYSlider:SetPoint("LEFT", attachXSlider, "RIGHT", 30, 0)
		local posY = settings.position and settings.position[2]
		if type(posY) == "string" and settings.position[5] then posY = settings.position[5] end -- {point, rel, relPt, x, y} 형식
		posY = tonumber(posY) or 0
		if posY ~= posY or posY < -500 or posY > 500 then posY = 0 end -- NaN/범위 방어
		attachYSlider:SetValue(posY)
		yOffset = yOffset - 55

		-- 초기화 버튼
		local resetAnchorBtn = Widgets:CreateButton(parent, "앵커 초기화", "red", { 100, 24 })
		resetAnchorBtn:SetPoint("TOPLEFT", 15, yOffset)
		resetAnchorBtn:SetScript("OnClick", function()
			ns.db[unit].attachTo = "UIParent"
			ns.db[unit].selfPoint = ns.defaults[unit] and ns.defaults[unit].selfPoint or "CENTER"
			ns.db[unit].anchorPoint = ns.defaults[unit] and ns.defaults[unit].anchorPoint or "CENTER"
			ns.db[unit].position = ns.defaults[unit] and ns.defaults[unit].position and { ns.defaults[unit].position[1], ns.defaults[unit].position[2] } or { 0, 0 }
			attachDropdown:SetSelected("UIParent")
			spDropdown:SetSelected(ns.db[unit].selfPoint)
			apDropdown:SetSelected(ns.db[unit].anchorPoint)
			attachXSlider:SetValue(ns.db[unit].position[1])
			attachYSlider:SetValue(ns.db[unit].position[2])
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		end)
		yOffset = yOffset - 35
	end

	-- Background section
	local bgSep = Widgets:CreateSeparator(parent, "배경", CONTENT_WIDTH - 40)
	bgSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local bgColorCP = Widgets:CreateColorPicker(parent, "배경 색상", true, function(r, g, b, a)
		if not ns.db[unit].background then ns.db[unit].background = {} end
		ns.db[unit].background.color = { r, g, b, a }
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview() -- [REFACTOR] 사이드바 미리보기 갱신
	end)
	bgColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local bgc = settings.background and settings.background.color or { 0.08, 0.08, 0.08, 0.85 }
	bgColorCP:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
	yOffset = yOffset - 45

	-- ===== Copy Settings =====
	local copySep = Widgets:CreateSeparator(parent, "설정 복사", CONTENT_WIDTH - 40)
	copySep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local copyLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	copyLabel:SetText("다른 유닛에서 복사:")
	copyLabel:SetPoint("TOPLEFT", 15, yOffset)

	local allUnits = { "player", "target", "targettarget", "focus", "focustarget", "pet", "party", "raid", "mythicRaid", "boss", "arena" }
	local copyItems = {}
	for _, u in ipairs(allUnits) do
		if u ~= unit then
			table.insert(copyItems, { text = UnitNames[u] or u, value = u })
		end
	end

	local copyDropdown = Widgets:CreateDropdown(parent, 140)
	copyDropdown:SetPoint("TOPLEFT", copyLabel, "BOTTOMLEFT", 0, -5)
	copyDropdown:SetItems(copyItems)

	local copyBtn = Widgets:CreateButton(parent, "복사", "class", { 60, 26 })
	copyBtn:SetPoint("LEFT", copyDropdown, "RIGHT", 10, 0)
	copyBtn:SetScript("OnClick", function()
		local sourceUnit = copyDropdown:GetSelected()
		if not sourceUnit or not ns.db[sourceUnit] then return end

		-- Deep copy source to current unit (preserve enabled/position)
		local CopyDeep
		CopyDeep = function(src)
			if type(src) ~= "table" then return src end
			local dst = {}
			for k, v in pairs(src) do dst[k] = CopyDeep(v) end
			return dst
		end

		local oldEnabled = ns.db[unit].enabled
		local oldPosition = ns.db[unit].position
		local oldSize = ns.db[unit].size

		-- Copy everything except position/enabled
		for k, v in pairs(ns.db[sourceUnit]) do
			if k ~= "enabled" and k ~= "position" and k ~= "size" then
				ns.db[unit][k] = CopyDeep(v)
			end
		end

		ns.db[unit].enabled = oldEnabled
		ns.db[unit].position = oldPosition
		ns.db[unit].size = oldSize

		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		ns.Print(UnitNames[sourceUnit] .. " → " .. unitName .. " 설정 복사 완료")
		RefreshCurrentPreview()
		if currentPage then LoadPage(currentPage) end
	end)
	yOffset = yOffset - 60

	-- ===== Reset to Defaults =====
	local resetSep = Widgets:CreateSeparator(parent, "초기화", CONTENT_WIDTH - 40)
	resetSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local resetBtn = Widgets:CreateButton(parent, "이 유닛 기본값으로 초기화", "red", { 200, 28 })
	resetBtn:SetPoint("TOPLEFT", 15, yOffset)
	resetBtn:SetScript("OnClick", function()
		StaticPopupDialogs["DDINGUI_UF_RESET_UNIT"] = {
			text = unitName .. " 설정을 기본값으로 초기화하시겠습니까?",
			button1 = "초기화",
			button2 = "취소",
			OnAccept = function()
				if ns.defaults and ns.defaults[unit] then
					local CopyDeep
					CopyDeep = function(src)
						if type(src) ~= "table" then return src end
						local dst = {}
						for k, v in pairs(src) do dst[k] = CopyDeep(v) end
						return dst
					end
					ns.db[unit] = CopyDeep(ns.defaults[unit])
					if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
					ns.Print(unitName .. " 설정이 기본값으로 초기화되었습니다.")
					RefreshCurrentPreview()
					-- Reload current page
					if currentPage then LoadPage(currentPage) end
				end
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
		}
		StaticPopup_Show("DDINGUI_UF_RESET_UNIT")
	end)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Health Page Builder
-----------------------------------------------
local function BuildUnitHealthPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 체력바", "체력바 상세 설정")

	local settings = ns.db[unit]
	if not settings then return end

	local yOffset = -60

	-- Health bar color type
	local colorSep = Widgets:CreateSeparator(parent, "색상 설정", CONTENT_WIDTH - 40)
	colorSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Color type dropdown
	local colorTypeLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	colorTypeLabel:SetText("체력바 색상")
	colorTypeLabel:SetPoint("TOPLEFT", 15, yOffset)

	local colorTypeDropdown = Widgets:CreateDropdown(parent, 120)
	colorTypeDropdown:SetPoint("TOPLEFT", colorTypeLabel, "BOTTOMLEFT", 0, -5)
	colorTypeDropdown:SetItems({
		{ text = "직업 색상", value = "class" },
		{ text = "진영 색상", value = "reaction" },
		{ text = "그라디언트", value = "smooth" },
		{ text = "사용자 정의", value = "custom" },
	})
	colorTypeDropdown:SetOnSelect(function(value)
		ns.db[unit].healthBarColorType = value
		if ns.Update and ns.Update.UpdateHealth then
			ns.Update:UpdateHealth(unit)
		end
		RefreshCurrentPreview()
	end)
	colorTypeDropdown:SetSelected(settings.healthBarColorType or "class")
	yOffset = yOffset - 55

	-- Custom health color
	local healthCP = Widgets:CreateColorPicker(parent, "사용자 정의 색상", false, function(r, g, b)
		ns.db[unit].healthBarColor = { r, g, b, 1 }
		if ns.Update and ns.Update.UpdateHealth then
			ns.Update:UpdateHealth(unit)
		end
		RefreshCurrentPreview()
	end)
	healthCP:SetPoint("TOPLEFT", 15, yOffset)
	local hc = settings.healthBarColor or { 0.2, 0.2, 0.2, 1 }
	healthCP:SetColor(hc[1], hc[2], hc[3], hc[4])
	yOffset = yOffset - 35

	-- Loss color section
	local lossSep = Widgets:CreateSeparator(parent, "손실 체력 색상", CONTENT_WIDTH - 40)
	lossSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Loss color type
	local lossTypeLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	lossTypeLabel:SetText("손실 체력 색상")
	lossTypeLabel:SetPoint("TOPLEFT", 15, yOffset)

	local lossTypeDropdown = Widgets:CreateDropdown(parent, 120)
	lossTypeDropdown:SetPoint("TOPLEFT", lossTypeLabel, "BOTTOMLEFT", 0, -5)
	lossTypeDropdown:SetItems({
		{ text = "사용자 정의", value = "custom" },
		{ text = "직업 색상 (어둡게)", value = "class_dark" },
	})
	lossTypeDropdown:SetOnSelect(function(value)
		ns.db[unit].healthLossColorType = value
		if ns.Update and ns.Update.UpdateHealth then
			ns.Update:UpdateHealth(unit)
		end
		RefreshCurrentPreview()
	end)
	lossTypeDropdown:SetSelected(settings.healthLossColorType or "custom")
	yOffset = yOffset - 55

	-- Loss color picker
	local lossCP = Widgets:CreateColorPicker(parent, "손실 체력 색상", false, function(r, g, b)
		ns.db[unit].healthLossColor = { r, g, b, 1 }
		if ns.Update and ns.Update.UpdateHealth then
			ns.Update:UpdateHealth(unit)
		end
		RefreshCurrentPreview()
	end)
	lossCP:SetPoint("TOPLEFT", 15, yOffset)
	local lc = settings.healthLossColor or { 0.5, 0.1, 0.1, 1 }
	lossCP:SetColor(lc[1], lc[2], lc[3], lc[4])
	yOffset = yOffset - 40

	-- Texture section
	local texSep = Widgets:CreateSeparator(parent, "텍스처", CONTENT_WIDTH - 40)
	texSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- [OPTION-CLEANUP] useHealthBarTexture 토글 제거 - 텍스처 선택이 있으면 별도 토글 불필요

	local texLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	texLabel:SetText("체력바 텍스처")
	texLabel:SetPoint("TOPLEFT", 15, yOffset)

	local texDropdown = Widgets:CreateDropdown(parent, 180)
	texDropdown:SetPoint("TOPLEFT", texLabel, "BOTTOMLEFT", 0, -5)
	texDropdown:SetItems(GetTextureList())
	texDropdown:SetOnSelect(function(value)
		ns.db[unit].healthBarTexture = value
		if ns.Update and ns.Update.UpdateHealth then ns.Update:UpdateHealth(unit) end
		RefreshCurrentPreview()
	end)
	texDropdown:SetSelected(settings.healthBarTexture or [[Interface\Buttons\WHITE8x8]])
	yOffset = yOffset - 60

	-- Options section
	local optSep = Widgets:CreateSeparator(parent, "체력바 옵션", CONTENT_WIDTH - 40)
	optSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local reverseCheck = Widgets:CreateCheckButton(parent, "체력바 채움 방향 반전", function(checked)
		ns.db[unit].reverseHealthFill = checked
		if ns.Update and ns.Update.UpdateHealth then ns.Update:UpdateHealth(unit) end
		RefreshCurrentPreview()
	end)
	reverseCheck:SetPoint("TOPLEFT", 15, yOffset)
	reverseCheck:SetChecked(settings.reverseHealthFill)
	yOffset = yOffset - 40

	-- [FIX] 배경 옵션 추가
	local hBgSep = Widgets:CreateSeparator(parent, "배경", CONTENT_WIDTH - 40)
	hBgSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local hBgTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	hBgTexLabel:SetText("배경 텍스처")
	hBgTexLabel:SetPoint("TOPLEFT", 15, yOffset)

	local hBgTexDropdown = Widgets:CreateDropdown(parent, 180)
	hBgTexDropdown:SetPoint("TOPLEFT", hBgTexLabel, "BOTTOMLEFT", 0, -5)
	hBgTexDropdown:SetItems(GetTextureList())
	hBgTexDropdown:SetOnSelect(function(value)
		ns.db[unit].healthBgTexture = value
		if ns.Update and ns.Update.UpdateHealth then ns.Update:UpdateHealth(unit) end
		RefreshCurrentPreview()
	end)
	hBgTexDropdown:SetSelected(settings.healthBgTexture or [[Interface\Buttons\WHITE8x8]])
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Power Page Builder
-----------------------------------------------
local function BuildUnitPowerPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 자원 바", "자원 바 상세 설정")

	local settings = ns.db[unit]
	if not settings then return end
	local powerWidget = settings.widgets and settings.widgets.powerBar

	local yOffset = -60

	local powerChildren = {}

	-- Enable
	local enableCheck = Widgets:CreateCheckButton(parent, "자원 바 활성화", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.powerBar then
			ns.db[unit].widgets.powerBar.enabled = checked
		end
		if ns.Update and ns.Update.UpdatePower then
			ns.Update:UpdatePower(unit)
		end
		RefreshCurrentPreview()
		SetChildrenEnabled(powerChildren, checked)
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(powerWidget and powerWidget.enabled)
	yOffset = yOffset - 35

	-- Size section
	local sizeSep = Widgets:CreateSeparator(parent, "크기", CONTENT_WIDTH - 40)
	sizeSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Height slider
	local heightSlider = Widgets:CreateSlider("높이", parent, 1, 30, 120, 1, nil, function(value)
		if ns.db[unit].widgets and ns.db[unit].widgets.powerBar then
			if not ns.db[unit].widgets.powerBar.size then ns.db[unit].widgets.powerBar.size = {} end
			ns.db[unit].widgets.powerBar.size.height = value
		end
		if ns.Update and ns.Update.UpdatePower then
			ns.Update:UpdatePower(unit)
		end
		RefreshCurrentPreview()
	end)
	heightSlider:SetPoint("TOPLEFT", 15, yOffset)
	heightSlider:SetValue(powerWidget and powerWidget.size and powerWidget.size.height or 4)

	-- Width slider
	local widthSlider = Widgets:CreateSlider("너비", parent, 20, 400, 120, 1, nil, function(value)
		if ns.db[unit].widgets and ns.db[unit].widgets.powerBar then
			if not ns.db[unit].widgets.powerBar.size then ns.db[unit].widgets.powerBar.size = {} end
			ns.db[unit].widgets.powerBar.size.width = value
		end
		if ns.Update and ns.Update.UpdatePower then
			ns.Update:UpdatePower(unit)
		end
		RefreshCurrentPreview()
	end)
	widthSlider:SetPoint("LEFT", heightSlider, "RIGHT", 30, 0)
	widthSlider:SetValue(powerWidget and powerWidget.size and powerWidget.size.width or 200)
	yOffset = yOffset - 55

	-- Same width as health bar
	local sameWidthCheck = Widgets:CreateCheckButton(parent, "체력바와 같은 너비 사용", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.powerBar then
			ns.db[unit].widgets.powerBar.sameWidthAsHealthBar = checked
		end
		if ns.Update and ns.Update.UpdatePower then
			ns.Update:UpdatePower(unit)
		end
		RefreshCurrentPreview()
	end)
	sameWidthCheck:SetPoint("TOPLEFT", 15, yOffset)
	sameWidthCheck:SetChecked(powerWidget and powerWidget.sameWidthAsHealthBar)
	yOffset = yOffset - 35

	-- Color section
	local colorSep = Widgets:CreateSeparator(parent, "색상", CONTENT_WIDTH - 40)
	colorSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Color by power type
	local colorPowerCheck = Widgets:CreateCheckButton(parent, "자원 유형별 색상 사용", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.powerBar then
			ns.db[unit].widgets.powerBar.colorPower = checked
		end
		if ns.Update and ns.Update.UpdatePower then
			ns.Update:UpdatePower(unit)
		end
		RefreshCurrentPreview()
	end)
	colorPowerCheck:SetPoint("TOPLEFT", 15, yOffset)
	colorPowerCheck:SetChecked(powerWidget and powerWidget.colorPower)
	yOffset = yOffset - 35

	-- Color by class
	local colorClassCheck = Widgets:CreateCheckButton(parent, "직업 색상 사용", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.powerBar then
			ns.db[unit].widgets.powerBar.colorClass = checked
		end
		if ns.Update and ns.Update.UpdatePower then
			ns.Update:UpdatePower(unit)
		end
		RefreshCurrentPreview()
	end)
	colorClassCheck:SetPoint("TOPLEFT", 15, yOffset)
	colorClassCheck:SetChecked(powerWidget and powerWidget.colorClass)
	yOffset = yOffset - 35

	-- Custom power bar color
	local powerCustomCP = Widgets:CreateColorPicker(parent, "사용자 지정 색상", true, function(r, g, b, a)
		if ns.db[unit].widgets and ns.db[unit].widgets.powerBar then
			ns.db[unit].widgets.powerBar.customColor = { r, g, b, a }
		end
		if ns.Update and ns.Update.UpdatePower then
			ns.Update:UpdatePower(unit)
		end
		RefreshCurrentPreview()
	end)
	powerCustomCP:SetPoint("TOPLEFT", 15, yOffset)
	local customC = powerWidget and powerWidget.customColor or { 0.0, 0.44, 1.0, 1 }
	powerCustomCP:SetColor(customC[1], customC[2], customC[3], customC[4])
	yOffset = yOffset - 40

	-- [OPTION-CLEANUP] hideIfEmpty/hideIfFull 제거 - autoHide로 통합
	-- [OPTION-CLEANUP] usePowerBarTexture 토글 제거 - 텍스처 선택이 있으면 별도 토글 불필요

	-- Visibility options
	local visSep = Widgets:CreateSeparator(parent, "표시 조건", CONTENT_WIDTH - 40)
	visSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local hideCombatCheck = Widgets:CreateCheckButton(parent, "전투 중이 아닐 때 숨기기", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.powerBar then
			ns.db[unit].widgets.powerBar.hideOutOfCombat = checked
		end
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end -- [FIX-OPTION]
		RefreshCurrentPreview()
	end)
	hideCombatCheck:SetPoint("TOPLEFT", 15, yOffset)
	hideCombatCheck:SetChecked(powerWidget and powerWidget.hideOutOfCombat)
	yOffset = yOffset - 40

	-- Texture section
	local texSep = Widgets:CreateSeparator(parent, "텍스처", CONTENT_WIDTH - 40)
	texSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local powerTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	powerTexLabel:SetText("자원 바 텍스처")
	powerTexLabel:SetPoint("TOPLEFT", 15, yOffset)

	local powerTexDropdown = Widgets:CreateDropdown(parent, 180)
	powerTexDropdown:SetPoint("TOPLEFT", powerTexLabel, "BOTTOMLEFT", 0, -5)
	powerTexDropdown:SetItems(GetTextureList())
	powerTexDropdown:SetOnSelect(function(value)
		ns.db[unit].powerBarTexture = value
		if ns.Update and ns.Update.UpdatePower then ns.Update:UpdatePower(unit) end
		RefreshCurrentPreview()
	end)
	powerTexDropdown:SetSelected(settings.powerBarTexture or [[Interface\Buttons\WHITE8x8]])

	local pBgTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	pBgTexLabel:SetText("배경 텍스처")
	pBgTexLabel:SetPoint("LEFT", powerTexLabel, "RIGHT", 200, 0)

	local pBgTexDropdown = Widgets:CreateDropdown(parent, 180)
	pBgTexDropdown:SetPoint("TOPLEFT", pBgTexLabel, "BOTTOMLEFT", 0, -5)
	pBgTexDropdown:SetItems(GetTextureList())
	pBgTexDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "powerBar", "background.texture", value)
		if ns.Update and ns.Update.UpdatePower then ns.Update:UpdatePower(unit) end
		RefreshCurrentPreview()
	end)
	local pBgTex = powerWidget and powerWidget.background and powerWidget.background.texture or [[Interface\Buttons\WHITE8x8]]
	pBgTexDropdown:SetSelected(pBgTex)
	yOffset = yOffset - 65

	-- [FIX] 자원 바 배경 색상
	local pBgColorCP = Widgets:CreateColorPicker(parent, "배경 색상", true, function(r, g, b, a)
		SetWidgetValue(unit, "powerBar", "background.color", { r, g, b, a })
		if ns.Update and ns.Update.UpdatePower then ns.Update:UpdatePower(unit) end
		RefreshCurrentPreview()
	end)
	pBgColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local pBgCol = powerWidget and powerWidget.background and powerWidget.background.color or { 0, 0, 0, 0.7 }
	pBgColorCP:SetColor(pBgCol[1], pBgCol[2], pBgCol[3], pBgCol[4] or 0.7)
	yOffset = yOffset - 40

	-- Orientation
	local orientSep = Widgets:CreateSeparator(parent, "방향 및 분리", CONTENT_WIDTH - 40)
	orientSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local orientLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	orientLabel:SetText("바 채움 방향")
	orientLabel:SetPoint("TOPLEFT", 15, yOffset)

	local orientDropdown = Widgets:CreateDropdown(parent, 120)
	orientDropdown:SetPoint("TOPLEFT", orientLabel, "BOTTOMLEFT", 0, -5)
	orientDropdown:SetItems(OrientationList)
	orientDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "powerBar", "orientation", value)
		if ns.Update and ns.Update.UpdatePower then ns.Update:UpdatePower(unit) end
		RefreshCurrentPreview()
	end)
	orientDropdown:SetSelected(powerWidget and powerWidget.orientation or "LEFT_TO_RIGHT")
	yOffset = yOffset - 55

	-- Detach from parent
	local detachCheck = Widgets:CreateCheckButton(parent, "프레임에서 분리", function(checked)
		SetWidgetValue(unit, "powerBar", "anchorToParent", not checked)
		if ns.Update and ns.Update.UpdatePower then ns.Update:UpdatePower(unit) end
		RefreshCurrentPreview()
	end)
	detachCheck:SetPoint("TOPLEFT", 15, yOffset)
	detachCheck:SetChecked(powerWidget and not powerWidget.anchorToParent)
	yOffset = yOffset - 35

	-- Position editor (for detached)
	local powerPosEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, "powerBar", "detachedPosition", pos)
		if ns.Update and ns.Update.UpdatePower then ns.Update:UpdatePower(unit) end
		RefreshCurrentPreview()
	end)
	powerPosEditor:SetPoint("TOPLEFT", 15, yOffset)
	powerPosEditor:SetPosition(powerWidget and powerWidget.detachedPosition or { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", offsetX = 0, offsetY = 0 })

	for _, c in ipairs({ sizeSep, heightSlider, sameWidthCheck, colorSep, colorPowerCheck, colorClassCheck, powerCustomCP, visSep, hideCombatCheck, texSep, powerTexLabel, powerTexDropdown, orientSep, orientLabel, orientDropdown, detachCheck, powerPosEditor }) do
		powerChildren[#powerChildren + 1] = c
	end
	SetChildrenEnabled(powerChildren, powerWidget and powerWidget.enabled)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Cast Bar Page Builder
-----------------------------------------------
local function BuildUnitCastBarPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 시전바", "시전바 상세 설정")

	local settings = ns.db[unit]
	if not settings then return end
	local castBar = settings.widgets and settings.widgets.castBar

	local yOffset = -60

	local castBarChildren = {}

	-- Enable
	local enableCheck = Widgets:CreateCheckButton(parent, "시전바 활성화", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			ns.db[unit].widgets.castBar.enabled = checked
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
		SetChildrenEnabled(castBarChildren, checked)
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(castBar and castBar.enabled)
	yOffset = yOffset - 35

	-- Detach from frame
	local detachCheck = Widgets:CreateCheckButton(parent, "프레임에서 분리", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			ns.db[unit].widgets.castBar.anchorToParent = not checked
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
	end)
	detachCheck:SetPoint("TOPLEFT", 15, yOffset)
	detachCheck:SetChecked(castBar and not castBar.anchorToParent)
	yOffset = yOffset - 35

	-- Size section
	local sizeSep = Widgets:CreateSeparator(parent, "크기", CONTENT_WIDTH - 40)
	sizeSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- Width slider
	local widthSlider = Widgets:CreateSlider("너비", parent, 50, 400, 120, 1, nil, function(value)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			if not ns.db[unit].widgets.castBar.size then ns.db[unit].widgets.castBar.size = {} end
			ns.db[unit].widgets.castBar.size.width = value
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
	end)
	widthSlider:SetPoint("TOPLEFT", 15, yOffset)
	widthSlider:SetValue(castBar and castBar.size and castBar.size.width or 200)

	-- Height slider
	local heightSlider = Widgets:CreateSlider("높이", parent, 10, 50, 120, 1, nil, function(value)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			if not ns.db[unit].widgets.castBar.size then ns.db[unit].widgets.castBar.size = {} end
			ns.db[unit].widgets.castBar.size.height = value
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
	end)
	heightSlider:SetPoint("LEFT", widthSlider, "RIGHT", 30, 0)
	heightSlider:SetValue(castBar and castBar.size and castBar.size.height or 20)
	yOffset = yOffset - 55

	-- Icon section
	local iconSep = Widgets:CreateSeparator(parent, "아이콘", CONTENT_WIDTH - 40)
	iconSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local iconCheck = Widgets:CreateCheckButton(parent, "주문 아이콘 표시", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			if not ns.db[unit].widgets.castBar.icon then ns.db[unit].widgets.castBar.icon = {} end
			ns.db[unit].widgets.castBar.icon.enabled = checked
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
	end)
	iconCheck:SetPoint("TOPLEFT", 15, yOffset)
	iconCheck:SetChecked(castBar and castBar.icon and castBar.icon.enabled)
	yOffset = yOffset - 30

	local iconPosLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	iconPosLabel:SetText("아이콘 위치")
	iconPosLabel:SetPoint("TOPLEFT", 15, yOffset)

	local iconPosDropdown = Widgets:CreateDropdown(parent, 120)
	iconPosDropdown:SetPoint("TOPLEFT", iconPosLabel, "BOTTOMLEFT", 0, -5)
	iconPosDropdown:SetItems({
		{ text = "내부 좌측", value = "inside-left" },
		{ text = "내부 우측", value = "inside-right" },
		{ text = "외부 좌측", value = "left" },
		{ text = "외부 우측", value = "right" },
	})
	iconPosDropdown:SetOnSelect(function(value)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			if not ns.db[unit].widgets.castBar.icon then ns.db[unit].widgets.castBar.icon = {} end
			ns.db[unit].widgets.castBar.icon.position = value
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
	end)
	iconPosDropdown:SetSelected(castBar and castBar.icon and castBar.icon.position or "inside-left")
	yOffset = yOffset - 55

	-- Text section
	local textSep = Widgets:CreateSeparator(parent, "텍스트", CONTENT_WIDTH - 40)
	textSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local spellCheck = Widgets:CreateCheckButton(parent, "주문 이름 표시", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			ns.db[unit].widgets.castBar.showSpell = checked
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
	end)
	spellCheck:SetPoint("TOPLEFT", 15, yOffset)
	spellCheck:SetChecked(castBar and castBar.showSpell)

	local timerCheck = Widgets:CreateCheckButton(parent, "시간 표시", function(checked)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			if not ns.db[unit].widgets.castBar.timer then ns.db[unit].widgets.castBar.timer = {} end
			ns.db[unit].widgets.castBar.timer.enabled = checked
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
	end)
	timerCheck:SetPoint("LEFT", spellCheck, "RIGHT", 120, 0)
	timerCheck:SetChecked(castBar and castBar.timer and castBar.timer.enabled)
	yOffset = yOffset - 35

	-- Timer Format 드롭다운 -- [REFACTOR]
	local timerFmtLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	timerFmtLabel:SetText("타이머 표시 형식")
	timerFmtLabel:SetPoint("TOPLEFT", 15, yOffset)

	local timerFmtDropdown = Widgets:CreateDropdown(parent, 130)
	timerFmtDropdown:SetPoint("TOPLEFT", timerFmtLabel, "BOTTOMLEFT", 0, -5)
	timerFmtDropdown:SetItems({
		{ text = "남은 시간", value = "remaining" },
		{ text = "남은/전체", value = "remaining/total" },
		{ text = "시전/전체", value = "elapsed/total" },
		{ text = "시전 시간", value = "elapsed" },
		{ text = "전체 시간", value = "total" },
	})
	timerFmtDropdown:SetOnSelect(function(value)
		if ns.db[unit].widgets and ns.db[unit].widgets.castBar then
			if not ns.db[unit].widgets.castBar.timer then ns.db[unit].widgets.castBar.timer = {} end
			ns.db[unit].widgets.castBar.timer.format = value
		end
		if ns.Update and ns.Update.UpdateCastBar then
			ns.Update:UpdateCastBar(unit)
		end
		RefreshCurrentPreview()
	end)
	timerFmtDropdown:SetSelected(castBar and castBar.timer and castBar.timer.format or "remaining")
	yOffset = yOffset - 55

	-- Font sizes
	local spellFontSlider = Widgets:CreateSlider("주문 폰트", parent, 6, 20, 100, 1, nil, function(value)
		SetWidgetValue(unit, "castBar", "spell.size", value)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	spellFontSlider:SetPoint("TOPLEFT", 15, yOffset)
	spellFontSlider:SetValue(castBar and castBar.spell and castBar.spell.size or 11)

	local timerFontSlider = Widgets:CreateSlider("타이머 폰트", parent, 6, 20, 100, 1, nil, function(value)
		SetWidgetValue(unit, "castBar", "timer.size", value)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	timerFontSlider:SetPoint("LEFT", spellFontSlider, "RIGHT", 30, 0)
	timerFontSlider:SetValue(castBar and castBar.timer and castBar.timer.size or 11)
	yOffset = yOffset - 55

	-- Texture section -- [FIX] 시전바 텍스처/배경 텍스처 선택 추가
	local cbTexSep = Widgets:CreateSeparator(parent, "텍스처", CONTENT_WIDTH - 40)
	cbTexSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local cbTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	cbTexLabel:SetText("시전바 텍스처")
	cbTexLabel:SetPoint("TOPLEFT", 15, yOffset)

	local cbTexDropdown = Widgets:CreateDropdown(parent, 180)
	cbTexDropdown:SetPoint("TOPLEFT", cbTexLabel, "BOTTOMLEFT", 0, -5)
	cbTexDropdown:SetItems(GetTextureList())
	cbTexDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "castBar", "texture", value)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	cbTexDropdown:SetSelected(castBar and castBar.texture or [[Interface\Buttons\WHITE8x8]])

	local cbBgTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	cbBgTexLabel:SetText("배경 텍스처")
	cbBgTexLabel:SetPoint("LEFT", cbTexLabel, "RIGHT", 200, 0)

	local cbBgTexDropdown = Widgets:CreateDropdown(parent, 180)
	cbBgTexDropdown:SetPoint("TOPLEFT", cbBgTexLabel, "BOTTOMLEFT", 0, -5)
	cbBgTexDropdown:SetItems(GetTextureList())
	cbBgTexDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "castBar", "colors.backgroundTexture", value)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	cbBgTexDropdown:SetSelected(castBar and castBar.colors and castBar.colors.backgroundTexture or [[Interface\Buttons\WHITE8x8]])
	yOffset = yOffset - 65

	-- Color options
	local colorsSep = Widgets:CreateSeparator(parent, "색상 옵션", CONTENT_WIDTH - 40)
	colorsSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local useClassColorCheck = Widgets:CreateCheckButton(parent, "직업 색상 사용", function(checked)
		SetWidgetValue(unit, "castBar", "useClassColor", checked)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	useClassColorCheck:SetPoint("TOPLEFT", 15, yOffset)
	useClassColorCheck:SetChecked(castBar and castBar.useClassColor)

	local onlyInterruptCheck = Widgets:CreateCheckButton(parent, "차단 가능만 표시", function(checked)
		SetWidgetValue(unit, "castBar", "onlyShowInterrupt", checked)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	onlyInterruptCheck:SetPoint("LEFT", useClassColorCheck, "RIGHT", 150, 0)
	onlyInterruptCheck:SetChecked(castBar and castBar.onlyShowInterrupt)
	yOffset = yOffset - 35

	-- Cast bar colors
	local castColors = castBar and castBar.colors or {}
	local intColorCP = Widgets:CreateColorPicker(parent, "차단 가능 색상", true, function(r, g, b, a)
		SetWidgetValue(unit, "castBar", "colors.interruptible", { r, g, b, a })
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	intColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local ic = castColors.interruptible or { 0.2, 0.57, 0.5, 1 }
	intColorCP:SetColor(ic[1], ic[2], ic[3], ic[4])

	local nonIntColorCP = Widgets:CreateColorPicker(parent, "차단 불가 색상", true, function(r, g, b, a)
		SetWidgetValue(unit, "castBar", "colors.nonInterruptible", { r, g, b, a })
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	nonIntColorCP:SetPoint("LEFT", intColorCP, "RIGHT", 180, 0)
	local nic = castColors.nonInterruptible or { 0.43, 0.43, 0.43, 1 }
	nonIntColorCP:SetColor(nic[1], nic[2], nic[3], nic[4])
	yOffset = yOffset - 30

	local bgColorCP = Widgets:CreateColorPicker(parent, "시전바 배경", true, function(r, g, b, a)
		SetWidgetValue(unit, "castBar", "colors.background", { r, g, b, a })
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	bgColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local bgc = castColors.background or { 0, 0, 0, 0.8 }
	bgColorCP:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
	yOffset = yOffset - 40

	-- Spark section
	local sparkSep = Widgets:CreateSeparator(parent, "스파크 (진행 표시)", CONTENT_WIDTH - 40)
	sparkSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local sparkCheck = Widgets:CreateCheckButton(parent, "스파크 표시", function(checked)
		SetWidgetValue(unit, "castBar", "spark.enabled", checked)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	sparkCheck:SetPoint("TOPLEFT", 15, yOffset)
	sparkCheck:SetChecked(castBar and castBar.spark and castBar.spark.enabled ~= false)

	local sparkWidthSlider = Widgets:CreateSlider("스파크 두께", parent, 1, 6, 80, 1, nil, function(value)
		SetWidgetValue(unit, "castBar", "spark.width", value)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	sparkWidthSlider:SetPoint("LEFT", sparkCheck, "RIGHT", 120, 0)
	sparkWidthSlider:SetValue(castBar and castBar.spark and castBar.spark.width or 2)
	yOffset = yOffset - 40

	-- Position when detached
	local posSep = Widgets:CreateSeparator(parent, "분리 시 위치", CONTENT_WIDTH - 40)
	posSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local castPosEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, "castBar", "detachedPosition", pos)
		if ns.Update and ns.Update.UpdateCastBar then ns.Update:UpdateCastBar(unit) end
		RefreshCurrentPreview()
	end)
	castPosEditor:SetPoint("TOPLEFT", 15, yOffset)
	castPosEditor:SetPosition(castBar and castBar.detachedPosition or { point = "CENTER", relativePoint = "CENTER", offsetX = 0, offsetY = 0 })

	for _, c in ipairs({ detachCheck, sizeSep, widthSlider, heightSlider, iconSep, iconCheck, iconPosLabel, iconPosDropdown, textSep, spellCheck, timerCheck, spellFontSlider, timerFontSlider, colorsSep, useClassColorCheck, onlyInterruptCheck, intColorCP, nonIntColorCP, bgColorCP, sparkSep, sparkCheck, sparkWidthSlider, posSep, castPosEditor }) do
		castBarChildren[#castBarChildren + 1] = c
	end
	SetChildrenEnabled(castBarChildren, castBar and castBar.enabled)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- [12.0.1] Common Icon Options Section Builders
-- buffs/debuffs/defensives/privateAuras 공통 섹션 재사용
-----------------------------------------------

-- 아이콘 변경 후 갱신 공통 루틴
local function IconRefresh(unit, widgetKey)
	if widgetKey == "privateAuras" then
		-- [FIX] 프라이빗 오라 앵커 즉시 갱신 (reload 불필요)
		local GF = ns.GroupFrames
		if GF and GF.RefreshAllPrivateAuras then
			GF:RefreshAllPrivateAuras()
		end
		-- [FIX] 테스트모드 프라이빗 오라도 즉시 갱신
		local TM = GF and GF.TestMode
		if TM and TM.active then
			TM:RefreshPrivateAuras()
		end
	else
		if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
		-- [FIX] 지속시간 색상 캐시 리셋 (임계값/그라데이션 설정 변경 즉시 반영)
		local GF = ns.GroupFrames
		if GF and GF.ResetDurationColorCache and (widgetKey == "buffs" or widgetKey == "debuffs") then
			GF:ResetDurationColorCache()
		end
		-- [FIX] 오라 폰트 라이브 업데이트 (기존 아이콘에도 즉시 반영)
		if ns._RefreshAuraFonts and (widgetKey == "buffs" or widgetKey == "debuffs") then
			local frame = ns.frames[unit]
			if frame then
				local element = widgetKey == "buffs" and frame.Buffs or frame.Debuffs
				if element then
					local unitDB = ns.db[unit]
					local wDB = unitDB and unitDB.widgets and unitDB.widgets[widgetKey]
					if wDB then
						element._fontDB = wDB.font
						element._durationColors = wDB.durationColors
					end
					ns._RefreshAuraFonts(element)
				end
			end
		end
		RefreshCurrentPreview()
	end
end

-- 공통 앵커 아이템 목록
local ICON_ANCHOR_ITEMS = {
	{ text = "CENTER", value = "CENTER" },
	{ text = "TOP", value = "TOP" },
	{ text = "BOTTOM", value = "BOTTOM" },
	{ text = "LEFT", value = "LEFT" },
	{ text = "RIGHT", value = "RIGHT" },
	{ text = "TOPLEFT", value = "TOPLEFT" },
	{ text = "TOPRIGHT", value = "TOPRIGHT" },
	{ text = "BOTTOMLEFT", value = "BOTTOMLEFT" },
	{ text = "BOTTOMRIGHT", value = "BOTTOMRIGHT" },
}

-- 1. 크기 섹션: 너비, 높이, 확대 비율, 최대 개수
local function BuildIconSizeSection(parent, unit, widgetKey, yOffset)
	local db = GetWidgetConfig(unit, widgetKey) or {}

	local sep = Widgets:CreateSeparator(parent, "크기 및 배치", CONTENT_WIDTH - 40)
	sep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- 너비
	local wSlider = Widgets:CreateSlider("너비", parent, 8, 60, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, "size.width", value)
		IconRefresh(unit, widgetKey)
	end)
	wSlider:SetPoint("TOPLEFT", 15, yOffset)
	wSlider:SetValue(db.size and db.size.width or 24)

	-- 높이
	local hSlider = Widgets:CreateSlider("높이", parent, 8, 60, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, "size.height", value)
		IconRefresh(unit, widgetKey)
	end)
	hSlider:SetPoint("LEFT", wSlider, "RIGHT", 30, 0)
	hSlider:SetValue(db.size and db.size.height or 24)
	yOffset = yOffset - 55

	-- 확대 비율 (50~200 = 0.5x~2.0x)
	local scaleSlider = Widgets:CreateSlider("확대 비율(%)", parent, 50, 200, 100, 5, nil, function(value)
		SetWidgetValue(unit, widgetKey, "scale", value / 100)
		IconRefresh(unit, widgetKey)
	end)
	scaleSlider:SetPoint("TOPLEFT", 15, yOffset)
	scaleSlider:SetValue(math.floor((db.scale or 1.0) * 100 + 0.5))

	-- 최대 개수
	local maxVal = widgetKey == "privateAuras" and 5 or 20
	local maxKey = widgetKey == "privateAuras" and "maxAuras" or "maxIcons"
	local maxSlider = Widgets:CreateSlider("최대 개수", parent, 1, maxVal, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, maxKey, value)
		IconRefresh(unit, widgetKey)
	end)
	maxSlider:SetPoint("LEFT", scaleSlider, "RIGHT", 30, 0)
	maxSlider:SetValue(db[maxKey] or 4)
	yOffset = yOffset - 55

	return yOffset
end

-- 2. 레이아웃 섹션: 줄당 개수, 수평/수직 간격
local function BuildIconLayoutSection(parent, unit, widgetKey, yOffset)
	local db = GetWidgetConfig(unit, widgetKey) or {}

	local perLineSlider = Widgets:CreateSlider("줄당 개수", parent, 1, 10, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, "numPerLine", value)
		IconRefresh(unit, widgetKey)
	end)
	perLineSlider:SetPoint("TOPLEFT", 15, yOffset)
	perLineSlider:SetValue(db.numPerLine or 5)
	yOffset = yOffset - 55

	local hSpacingSlider = Widgets:CreateSlider("수평 간격", parent, 0, 10, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, "spacing.horizontal", value)
		IconRefresh(unit, widgetKey)
	end)
	hSpacingSlider:SetPoint("TOPLEFT", 15, yOffset)
	hSpacingSlider:SetValue(db.spacing and db.spacing.horizontal or 2)

	local vSpacingSlider = Widgets:CreateSlider("수직 간격", parent, 0, 10, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, "spacing.vertical", value)
		IconRefresh(unit, widgetKey)
	end)
	vSpacingSlider:SetPoint("LEFT", hSpacingSlider, "RIGHT", 30, 0)
	vSpacingSlider:SetValue(db.spacing and db.spacing.vertical or 2)
	yOffset = yOffset - 55

	return yOffset
end

-- 3. 성장 방향 섹션: 1차/2차 방향
local function BuildIconGrowthSection(parent, unit, widgetKey, yOffset)
	local db = GetWidgetConfig(unit, widgetKey) or {}

	local sep = Widgets:CreateSeparator(parent, "방향", CONTENT_WIDTH - 40)
	sep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local growLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	growLabel:SetText("1차 방향")
	growLabel:SetPoint("TOPLEFT", 15, yOffset)

	local growDropdown = Widgets:CreateDropdown(parent, 120)
	growDropdown:SetPoint("TOPLEFT", growLabel, "BOTTOMLEFT", 0, -5)
	growDropdown:SetItems({
		{ text = "오른쪽", value = "RIGHT" },
		{ text = "왼쪽", value = "LEFT" },
		{ text = "아래로", value = "DOWN" },
		{ text = "위로", value = "UP" },
	})
	growDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, widgetKey, "growDirection", value)
		IconRefresh(unit, widgetKey)
	end)
	-- 하위호환: orientation → growDirection
	local defaultGrow = db.growDirection or "RIGHT"
	if not db.growDirection and db.orientation then
		local o = db.orientation
		if o == "RIGHT_TO_LEFT" then defaultGrow = "LEFT"
		elseif o == "TOP_TO_BOTTOM" then defaultGrow = "DOWN"
		elseif o == "BOTTOM_TO_TOP" then defaultGrow = "UP"
		else defaultGrow = "RIGHT" end
	end
	growDropdown:SetSelected(defaultGrow)

	local colGrowLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	colGrowLabel:SetText("2차 방향")
	colGrowLabel:SetPoint("LEFT", growLabel, "RIGHT", 140, 0)

	local colGrowDropdown = Widgets:CreateDropdown(parent, 120)
	colGrowDropdown:SetPoint("TOPLEFT", colGrowLabel, "BOTTOMLEFT", 0, -5)
	colGrowDropdown:SetItems({
		{ text = "오른쪽", value = "RIGHT" },
		{ text = "왼쪽", value = "LEFT" },
		{ text = "아래로", value = "DOWN" },
		{ text = "위로", value = "UP" },
	})
	colGrowDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, widgetKey, "columnGrowDirection", value)
		IconRefresh(unit, widgetKey)
	end)
	local defaultColGrow = db.columnGrowDirection or "UP"
	if not db.columnGrowDirection and db.orientation then
		local o = db.orientation
		if o == "TOP_TO_BOTTOM" or o == "BOTTOM_TO_TOP" then defaultColGrow = "RIGHT"
		else defaultColGrow = "UP" end
	end
	colGrowDropdown:SetSelected(defaultColGrow)
	yOffset = yOffset - 55

	return yOffset
end

-- 4. 위치 편집기 섹션
local function BuildIconPositionSection(parent, unit, widgetKey, yOffset)
	local db = GetWidgetConfig(unit, widgetKey) or {}

	local sep = Widgets:CreateSeparator(parent, "위치", CONTENT_WIDTH - 40)
	sep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local posEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, widgetKey, "position", pos)
		IconRefresh(unit, widgetKey)
	end)
	posEditor:SetPoint("TOPLEFT", 15, yOffset)
	posEditor:SetPosition(db.position or { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", offsetX = 0, offsetY = 2 })
	yOffset = yOffset - 120

	return yOffset
end

-- 5. 표시 옵션 섹션 (showDuration, showStack, showTooltip, clickThrough, hideInCombat)
local function BuildIconDisplaySection(parent, unit, widgetKey, yOffset, opts)
	local db = GetWidgetConfig(unit, widgetKey) or {}
	opts = opts or {}

	local sep = Widgets:CreateSeparator(parent, "표시 옵션", CONTENT_WIDTH - 40)
	sep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- 지속시간 + 중첩
	local durationCheck = Widgets:CreateCheckButton(parent, "지속시간 표시", function(checked)
		SetWidgetValue(unit, widgetKey, "showDuration", checked)
		IconRefresh(unit, widgetKey)
	end)
	durationCheck:SetPoint("TOPLEFT", 15, yOffset)
	durationCheck:SetChecked(db.showDuration ~= false)

	local stackCheck = Widgets:CreateCheckButton(parent, "중첩 표시", function(checked)
		SetWidgetValue(unit, widgetKey, "showStack", checked)
		IconRefresh(unit, widgetKey)
	end)
	stackCheck:SetPoint("LEFT", durationCheck, "RIGHT", 100, 0)
	stackCheck:SetChecked(db.showStack ~= false)
	yOffset = yOffset - 30

	-- 툴팁
	local tooltipCheck = Widgets:CreateCheckButton(parent, "툴팁 표시", function(checked)
		SetWidgetValue(unit, widgetKey, "showTooltip", checked)
	end)
	tooltipCheck:SetPoint("TOPLEFT", 15, yOffset)
	tooltipCheck:SetChecked(db.showTooltip ~= false)
	yOffset = yOffset - 30

	-- 클릭 투과 + 전투 중 숨기기
	local clickThroughCheck = Widgets:CreateCheckButton(parent, "클릭 투과", function(checked)
		SetWidgetValue(unit, widgetKey, "clickThrough", checked)
		IconRefresh(unit, widgetKey)
	end)
	clickThroughCheck:SetPoint("TOPLEFT", 15, yOffset)
	clickThroughCheck:SetChecked(db.clickThrough)

	local hideInCombatCheck = Widgets:CreateCheckButton(parent, "전투 중 숨기기", function(checked)
		SetWidgetValue(unit, widgetKey, "hideInCombat", checked)
		IconRefresh(unit, widgetKey)
	end)
	hideInCombatCheck:SetPoint("LEFT", clickThroughCheck, "RIGHT", 110, 0)
	hideInCombatCheck:SetChecked(db.hideInCombat)
	yOffset = yOffset - 35

	return yOffset
end

-- 6. 글꼴 상세 섹션 (duration or stacks)
local function BuildIconFontSection(parent, unit, widgetKey, fontSubKey, sectionTitle, yOffset)
	local db = GetWidgetConfig(unit, widgetKey) or {}
	local fontDB = db.font and db.font[fontSubKey] or {}

	local sep = Widgets:CreateSeparator(parent, sectionTitle, CONTENT_WIDTH - 40)
	sep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	-- 글꼴 크기
	local sizeSlider = Widgets:CreateSlider("글꼴 크기", parent, 6, 24, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, "font." .. fontSubKey .. ".size", value)
		IconRefresh(unit, widgetKey)
	end)
	sizeSlider:SetPoint("TOPLEFT", 15, yOffset)
	sizeSlider:SetValue(fontDB.size or 10)

	-- 아웃라인
	local outlineDropdown = Widgets:CreateDropdown(parent, 120)
	outlineDropdown:SetPoint("LEFT", sizeSlider, "RIGHT", 30, 0)
	outlineDropdown:SetItems({
		{ text = "없음", value = "NONE" },
		{ text = "얇게", value = "OUTLINE" },
		{ text = "두껍게", value = "THICKOUTLINE" },
	})
	outlineDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, widgetKey, "font." .. fontSubKey .. ".outline", value)
		IconRefresh(unit, widgetKey)
	end)
	outlineDropdown:SetSelected(fontDB.outline or "OUTLINE")
	local outlineLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	outlineLabel:SetText("아웃라인")
	outlineLabel:SetPoint("BOTTOMLEFT", outlineDropdown, "TOPLEFT", 0, 3)
	yOffset = yOffset - 55

	-- 기준점 + 상대 기준점
	local pointLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	pointLabel:SetText("기준점")
	pointLabel:SetPoint("TOPLEFT", 15, yOffset)
	local pointDropdown = Widgets:CreateDropdown(parent, 110)
	pointDropdown:SetPoint("TOPLEFT", pointLabel, "BOTTOMLEFT", 0, -3)
	pointDropdown:SetItems(ICON_ANCHOR_ITEMS)
	pointDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, widgetKey, "font." .. fontSubKey .. ".point", value)
		IconRefresh(unit, widgetKey)
	end)
	pointDropdown:SetSelected(fontDB.point or "CENTER")

	local relLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	relLabel:SetText("상대 기준점")
	relLabel:SetPoint("LEFT", pointLabel, "RIGHT", 130, 0)
	local relDropdown = Widgets:CreateDropdown(parent, 110)
	relDropdown:SetPoint("TOPLEFT", relLabel, "BOTTOMLEFT", 0, -3)
	relDropdown:SetItems(ICON_ANCHOR_ITEMS)
	relDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, widgetKey, "font." .. fontSubKey .. ".relativePoint", value)
		IconRefresh(unit, widgetKey)
	end)
	relDropdown:SetSelected(fontDB.relativePoint or "CENTER")
	yOffset = yOffset - 50

	-- X/Y 오프셋
	local oxSlider = Widgets:CreateSlider("X 오프셋", parent, -20, 20, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, "font." .. fontSubKey .. ".offsetX", value)
		IconRefresh(unit, widgetKey)
	end)
	oxSlider:SetPoint("TOPLEFT", 15, yOffset)
	oxSlider:SetValue(fontDB.offsetX or 0)

	local oySlider = Widgets:CreateSlider("Y 오프셋", parent, -20, 20, 100, 1, nil, function(value)
		SetWidgetValue(unit, widgetKey, "font." .. fontSubKey .. ".offsetY", value)
		IconRefresh(unit, widgetKey)
	end)
	oySlider:SetPoint("LEFT", oxSlider, "RIGHT", 30, 0)
	oySlider:SetValue(fontDB.offsetY or 0)
	yOffset = yOffset - 55

	-- 색상 모드 (duration만)
	if fontSubKey == "duration" then
		local colorLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
		colorLabel:SetText("색상 모드")
		colorLabel:SetPoint("TOPLEFT", 15, yOffset)
		local colorDropdown = Widgets:CreateDropdown(parent, 130)
		colorDropdown:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -3)
		colorDropdown:SetItems({
			{ text = "고정 색상", value = "fixed" },
			{ text = "시간 그라데이션", value = "gradient" },
			{ text = "임계값 색상", value = "threshold" },
		})
		colorDropdown:SetOnSelect(function(value)
			SetWidgetValue(unit, widgetKey, "font." .. fontSubKey .. ".colorMode", value)
			IconRefresh(unit, widgetKey)
		end)
		colorDropdown:SetSelected(fontDB.colorMode or "fixed")
		yOffset = yOffset - 55

		-- [FIX] 임계값 색상 편집 UI (threshold 모드 전용)
		local thresholdSep = Widgets:CreateSeparator(parent, "임계값 색상 (초 단위)", CONTENT_WIDTH - 40)
		thresholdSep:SetPoint("TOPLEFT", 15, yOffset)
		yOffset = yOffset - 30

		-- durationColors에서 thresholds 읽기
		local auraDB = GetWidgetConfig(unit, widgetKey) or {}
		local dColors = auraDB.durationColors or {}
		local thresholds = dColors.thresholds or {
			{ time = 3, rgb = { 1, 0, 0 } },
			{ time = 5, rgb = { 1, 0.5, 0 } },
			{ time = 10, rgb = { 1, 1, 0 } },
		}

		local thresholdLabels = { "임계값 1", "임계값 2", "임계값 3" }
		for idx = 1, 3 do
			local t = thresholds[idx] or { time = idx * 3, rgb = { 1, 1, 1 } }

			local tSlider = Widgets:CreateSlider(thresholdLabels[idx] .. " (초)", parent, 1, 60, 80, 1, nil, function(value)
				local curThresholds = (GetWidgetConfig(unit, widgetKey) or {}).durationColors
					and (GetWidgetConfig(unit, widgetKey)).durationColors.thresholds
				if curThresholds and curThresholds[idx] then
					curThresholds[idx].time = value
					IconRefresh(unit, widgetKey)
				end
			end)
			tSlider:SetPoint("TOPLEFT", 15 + (idx - 1) * 130, yOffset)
			tSlider:SetValue(t.time)

			local tCP = Widgets:CreateColorPicker(parent, "", false, function(r, g, b)
				local curThresholds = (GetWidgetConfig(unit, widgetKey) or {}).durationColors
					and (GetWidgetConfig(unit, widgetKey)).durationColors.thresholds
				if curThresholds and curThresholds[idx] then
					curThresholds[idx].rgb = { r, g, b }
					IconRefresh(unit, widgetKey)
				end
			end)
			tCP:SetPoint("TOPLEFT", 15 + (idx - 1) * 130, yOffset - 40)
			tCP:SetColor(t.rgb[1], t.rgb[2], t.rgb[3])
		end
		yOffset = yOffset - 80
	end

	return yOffset
end

-----------------------------------------------
-- Auras Page Builder (Buffs/Debuffs)
-- [12.0.1] 공통 헬퍼 사용으로 리팩터링
-----------------------------------------------
local function BuildUnitAurasPage(parent, unit, auraType)
	local unitName = UnitNames[unit] or unit
	local auraName = auraType == "buffs" and "버프" or "디버프"
	local header = CreatePageHeader(parent, unitName .. " " .. auraName, auraName .. " 상세 설정")

	local settings = ns.db[unit]
	if not settings then return end
	local auras = settings.widgets and settings.widgets[auraType]

	local yOffset = -60

	-- Enable
	local enableCheck = Widgets:CreateCheckButton(parent, auraName .. " 활성화", function(checked)
		SetWidgetValue(unit, auraType, "enabled", checked)
		IconRefresh(unit, auraType)
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(auras and auras.enabled)
	yOffset = yOffset - 35

	-- [12.0.1] 공통 헬퍼 사용
	yOffset = BuildIconSizeSection(parent, unit, auraType, yOffset)
	yOffset = BuildIconLayoutSection(parent, unit, auraType, yOffset)
	yOffset = BuildIconDisplaySection(parent, unit, auraType, yOffset)
	yOffset = BuildIconFontSection(parent, unit, auraType, "duration", "지속시간 텍스트 상세", yOffset)
	yOffset = BuildIconFontSection(parent, unit, auraType, "stacks", "중첩 텍스트 상세", yOffset)

	-- [AURA-FILTER] Filter section — secret-safe 필터 (non-secret 필드만 사용, buffs/debuffs 고유)
	local filterSep = Widgets:CreateSeparator(parent, "필터", CONTENT_WIDTH - 40)
	filterSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local filter = auras and auras.filter or {}

	-- 공통: 내가 건 것만
	local mineCheck = Widgets:CreateCheckButton(parent, "내가 건 것만 표시", function(checked)
		SetWidgetValue(unit, auraType, "filter.onlyMine", checked)
		if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
		RefreshCurrentPreview()
	end)
	mineCheck:SetPoint("TOPLEFT", 15, yOffset)
	mineCheck:SetChecked(filter.onlyMine)

	-- 공통: 보스 오라 항상 표시
	local bossCheck = Widgets:CreateCheckButton(parent, "보스 오라 항상 표시", function(checked)
		SetWidgetValue(unit, auraType, "filter.showBossAura", checked)
		if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
		RefreshCurrentPreview()
	end)
	bossCheck:SetPoint("LEFT", mineCheck, "RIGHT", 140, 0)
	bossCheck:SetChecked(filter.showBossAura ~= false)
	yOffset = yOffset - 30

	-- 공통: 레이드 오라 표시
	local raidCheck = Widgets:CreateCheckButton(parent, "블리자드 레이드 오라 표시", function(checked)
		SetWidgetValue(unit, auraType, "filter.showRaid", checked)
		if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
		RefreshCurrentPreview()
	end)
	raidCheck:SetPoint("TOPLEFT", 15, yOffset)
	raidCheck:SetChecked(filter.showRaid)
	yOffset = yOffset - 30

	-- 파티/레이드 버프 전용: 블리자드 파티프레임 필터 (SpellGetVisibilityInfo)
	if auraType == "buffs" and (unit == "party" or unit == "raid" or unit == "mythicRaid") then
		local blizzFilterCheck = Widgets:CreateCheckButton(parent, "블리자드 파티프레임 필터", function(checked)
			SetWidgetValue(unit, auraType, "filter.useBlizzardFilter", checked)
			if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
			RefreshCurrentPreview()
		end)
		blizzFilterCheck:SetPoint("TOPLEFT", 15, yOffset)
		blizzFilterCheck:SetChecked(filter.useBlizzardFilter)
		blizzFilterCheck.tooltipText = "블리자드 기본 파티프레임과 동일한 버프 표시 기준 사용\n(SpellGetVisibilityInfo API)"
		yOffset = yOffset - 30
	end

	-- [FIX] 버프 전용: 레이드 시너지 버프 숨기기 (인내, 전투 외침, 야생의 징표 등)
	if auraType == "buffs" then
		local hideRaidBuffsCheck = Widgets:CreateCheckButton(parent, "레이드 시너지 버프 숨기기", function(checked)
			SetWidgetValue(unit, auraType, "filter.hideRaidBuffs", checked)
			if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
			-- GroupFrames 갱신
			local GF = ns.GroupFrames
			if GF and GF.headersInitialized and GF.QueueAuraUpdate then
				for _, f in pairs(GF.allFrames or {}) do
					GF:QueueAuraUpdate(f)
				end
			end
			RefreshCurrentPreview()
		end)
		hideRaidBuffsCheck:SetPoint("TOPLEFT", 15, yOffset)
		hideRaidBuffsCheck:SetChecked(filter.hideRaidBuffs)
		hideRaidBuffsCheck.tooltipText = "신의 권능: 인내, 전투 외침, 신비한 지능 등\n레이드 시너지 버프를 버프 바에서 숨깁니다"
		yOffset = yOffset - 30

		-- [12.0.1] HoT 목록 기반 화이트리스트
		local hotWhitelistCheck = Widgets:CreateCheckButton(parent, "HoT 목록 기반 필터", function(checked)
			SetWidgetValue(unit, auraType, "filter.useHotWhitelist", checked)
			-- GroupFrames 갱신
			local GF = ns.GroupFrames
			if GF and GF.headersInitialized and GF.QueueAuraUpdate then
				for _, f in pairs(GF.allFrames or {}) do
					GF:QueueAuraUpdate(f)
				end
			end
			RefreshCurrentPreview()
		end)
		hotWhitelistCheck:SetPoint("TOPLEFT", 15, yOffset)
		hotWhitelistCheck:SetChecked(filter.useHotWhitelist)
		hotWhitelistCheck.tooltipText = "HoT 트래커에 등록된 스킬만 버프 아이콘에 표시합니다\n(현재 전문화의 추적 대상 HoT만 통과)"
		yOffset = yOffset - 30
	end

	-- 디버프 전용 필터
	if auraType == "debuffs" then
		local dispelOnlyCheck = Widgets:CreateCheckButton(parent, "해제 가능한 것만 표시", function(checked)
			SetWidgetValue(unit, auraType, "filter.onlyDispellable", checked)
			if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
			RefreshCurrentPreview()
		end)
		dispelOnlyCheck:SetPoint("TOPLEFT", 15, yOffset)
		dispelOnlyCheck:SetChecked(filter.onlyDispellable)

		local showAllCheck = Widgets:CreateCheckButton(parent, "전부 표시 (필터 무시)", function(checked)
			SetWidgetValue(unit, auraType, "filter.showAll", checked)
			if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
			RefreshCurrentPreview()
		end)
		showAllCheck:SetPoint("LEFT", dispelOnlyCheck, "RIGHT", 140, 0)
		showAllCheck:SetChecked(filter.showAll)
		yOffset = yOffset - 30
	end

	-- 공통: 지속시간 필터
	local hideNoDurCheck = Widgets:CreateCheckButton(parent, "지속시간 없는 것 숨기기", function(checked)
		SetWidgetValue(unit, auraType, "filter.hideNoDuration", checked)
		if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
		RefreshCurrentPreview()
	end)
	hideNoDurCheck:SetPoint("TOPLEFT", 15, yOffset)
	hideNoDurCheck:SetChecked(filter.hideNoDuration)
	yOffset = yOffset - 30

	-- 최대 지속시간 (secret guard: duration이 secret이면 필터 스킵)
	local maxDurSlider = Widgets:CreateSlider("최대 지속시간(초, 0=무제한)", parent, 0, 600, 200, 1, nil, function(value)
		SetWidgetValue(unit, auraType, "filter.maxDuration", value)
		if ns.Update and ns.Update.UpdateAuras then ns.Update:UpdateAuras(unit) end
		RefreshCurrentPreview()
	end)
	maxDurSlider:SetPoint("TOPLEFT", 15, yOffset)
	maxDurSlider:SetValue(filter.maxDuration or 0)
	yOffset = yOffset - 60

	-- [12.0.1] 방향 및 위치 — 공통 헬퍼 사용
	yOffset = BuildIconGrowthSection(parent, unit, auraType, yOffset)
	yOffset = BuildIconPositionSection(parent, unit, auraType, yOffset)

	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- [AURA-FILTER] Defensives Page Builder (생존기/외생기)
-- party/raid 전용 상위 카테고리
-----------------------------------------------
local function BuildDefensivesPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 생존기", "생존기/외부 생존기 별도 표시 설정")

	local settings = ns.db[unit]
	if not settings then return end
	local defDB = settings.widgets and settings.widgets.defensives

	local yOffset = -60

	-- Enable
	local enableCheck = Widgets:CreateCheckButton(parent, "생존기 별도 표시 활성화", function(checked)
		SetWidgetValue(unit, "defensives", "enabled", checked)
		IconRefresh(unit, "defensives")
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(defDB and defDB.enabled)
	yOffset = yOffset - 35

	local desc = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	desc:SetText("생존기/외생기는 별도 영역에 표시됩니다. 인스턴스에서 spellId가 secret이면 표시되지 않습니다.")
	desc:SetTextColor(0.6, 0.6, 0.6)
	desc:SetWidth(CONTENT_WIDTH - 40)
	desc:SetJustifyH("LEFT")
	desc:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 25

	-- [고유] 타입 필터
	local typeSep = Widgets:CreateSeparator(parent, "표시 종류", CONTENT_WIDTH - 40)
	typeSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local defCheck = Widgets:CreateCheckButton(parent, "개인 생존기", function(checked)
		SetWidgetValue(unit, "defensives", "showDefensives", checked)
		IconRefresh(unit, "defensives")
	end)
	defCheck:SetPoint("TOPLEFT", 15, yOffset)
	defCheck:SetChecked(defDB and defDB.showDefensives ~= false)

	local extCheck = Widgets:CreateCheckButton(parent, "외부 생존기", function(checked)
		SetWidgetValue(unit, "defensives", "showExternals", checked)
		IconRefresh(unit, "defensives")
	end)
	extCheck:SetPoint("LEFT", defCheck, "RIGHT", 110, 0)
	extCheck:SetChecked(defDB and defDB.showExternals ~= false)
	yOffset = yOffset - 30

	local mineCheck = Widgets:CreateCheckButton(parent, "내가 건 것만", function(checked)
		SetWidgetValue(unit, "defensives", "onlyMine", checked)
		IconRefresh(unit, "defensives")
	end)
	mineCheck:SetPoint("TOPLEFT", 15, yOffset)
	mineCheck:SetChecked(defDB and defDB.onlyMine)
	yOffset = yOffset - 35

	-- [12.0.1] 공통 헬퍼 사용 — buffs/debuffs와 동일한 옵션 구조
	yOffset = BuildIconSizeSection(parent, unit, "defensives", yOffset)
	yOffset = BuildIconLayoutSection(parent, unit, "defensives", yOffset)
	yOffset = BuildIconDisplaySection(parent, unit, "defensives", yOffset)
	yOffset = BuildIconFontSection(parent, unit, "defensives", "duration", "지속시간 텍스트 상세", yOffset)
	yOffset = BuildIconFontSection(parent, unit, "defensives", "stacks", "중첩 텍스트 상세", yOffset)
	yOffset = BuildIconGrowthSection(parent, unit, "defensives", yOffset)
	yOffset = BuildIconPositionSection(parent, unit, "defensives", yOffset)

	-- [고유] 스펠 목록 안내
	local listSep = Widgets:CreateSeparator(parent, "등록된 생존기 목록", CONTENT_WIDTH - 40)
	listSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 25

	local listDesc = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	listDesc:SetText("CenterDefensiveBuff API 기반 — Blizzard가 결정한 생존기만 표시")
	listDesc:SetTextColor(0.6, 0.6, 0.6)
	listDesc:SetPoint("TOPLEFT", 15, yOffset)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- [AURA-FILTER] Private Auras Page Builder (프라이빗 오라)
-- party/raid 전용 상위 카테고리
-- 기존 모듈 페이지의 PrivateAuras 섹션을 독립 페이지로 분리
-----------------------------------------------
local function BuildPrivateAurasPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 프라이빗 오라", "블리자드 비공개 오라 표시 설정")

	local yOffset = -60

	local desc = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	desc:SetText("블리자드가 직접 제어하는 비공개 오라 (보스 메커닉 디버프 등).\n인스턴스 내에서 secret으로 보호되는 오라를 블리자드 UI가 직접 표시합니다.")
	desc:SetTextColor(0.6, 0.6, 0.6)
	desc:SetWidth(CONTENT_WIDTH - 40)
	desc:SetJustifyH("LEFT")
	desc:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 50

	-- Enable
	local paDB = GetWidgetConfig(unit, "privateAuras") or {}
	local paCheck = Widgets:CreateCheckButton(parent, "프라이빗 오라 표시", function(checked)
		SetWidgetValue(unit, "privateAuras", "enabled", checked)
		IconRefresh(unit, "privateAuras")
	end)
	paCheck:SetPoint("TOPLEFT", 15, yOffset)
	paCheck:SetChecked(paDB.enabled ~= false)
	yOffset = yOffset - 35

	-- [12.0.1] 공통 헬퍼 사용 (WoW API 범위 내만)
	yOffset = BuildIconSizeSection(parent, unit, "privateAuras", yOffset)
	yOffset = BuildIconLayoutSection(parent, unit, "privateAuras", yOffset)
	yOffset = BuildIconGrowthSection(parent, unit, "privateAuras", yOffset)
	yOffset = BuildIconPositionSection(parent, unit, "privateAuras", yOffset)

	-- 글꼴/표시옵션/필터 섹션 없음 (블리자드 API 제약 — 렌더링 직접 관리)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Text Page Builder
-----------------------------------------------
local function BuildUnitTextsPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 텍스트", "텍스트 위젯 설정 (폰트, 위치, 색상, 형식)")

	local settings = ns.db[unit]
	if not settings then return end

	local yOffset = -60

	-- ===== Name Text Section =====
	local nameSep = Widgets:CreateSeparator(parent, "이름 텍스트", CONTENT_WIDTH - 40)
	nameSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local nameWidget = GetWidgetConfig(unit, "nameText")

	local nameCheck = Widgets:CreateCheckButton(parent, "이름 표시", function(checked)
		SetWidgetValue(unit, "nameText", "enabled", checked)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	nameCheck:SetPoint("TOPLEFT", 15, yOffset)
	nameCheck:SetChecked(nameWidget and nameWidget.enabled)
	yOffset = yOffset - 30

	-- Show Level
	local showLevelCheck = Widgets:CreateCheckButton(parent, "레벨 표시", function(checked)
		SetWidgetValue(unit, "nameText", "showLevel", checked)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	showLevelCheck:SetPoint("TOPLEFT", 15, yOffset)
	showLevelCheck:SetChecked(nameWidget and nameWidget.showLevel)
	yOffset = yOffset - 30

	-- Name format
	local nameFormatLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	nameFormatLabel:SetText("이름 형식")
	nameFormatLabel:SetPoint("TOPLEFT", 15, yOffset)

	local nameFormatDropdown = Widgets:CreateDropdown(parent, 130)
	nameFormatDropdown:SetPoint("TOPLEFT", nameFormatLabel, "BOTTOMLEFT", 0, -5)
	nameFormatDropdown:SetItems(NameFormatList)
	nameFormatDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "nameText", "format", value)
		SetWidgetValue(unit, "nameText", "tag", "") -- [FIX] format 변경 시 옛 custom tag 초기화
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	nameFormatDropdown:SetSelected(nameWidget and nameWidget.format or "name")
	yOffset = yOffset - 55

	-- Name font
	local nameFontSelector = Widgets:CreateFontSelector(parent, 350, function(fontOpt)
		SetWidgetValue(unit, "nameText", "font", fontOpt)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	nameFontSelector:SetPoint("TOPLEFT", 15, yOffset)
	nameFontSelector:SetFont(nameWidget and nameWidget.font or { size = 12, outline = "OUTLINE", shadow = false, justify = "LEFT" })
	yOffset = yOffset - 110

	-- Name color
	local nameColorPicker = Widgets:CreateEnhancedColorPicker(parent, "이름 색상", false, function(colorOpt)
		SetWidgetValue(unit, "nameText", "color", colorOpt)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	nameColorPicker:SetPoint("TOPLEFT", 15, yOffset)
	nameColorPicker:SetColor(nameWidget and nameWidget.color or { rgb = { 1, 1, 1 }, type = "class_color" })
	yOffset = yOffset - 35

	-- Name position
	local namePosEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, "nameText", "position", pos)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	namePosEditor:SetPoint("TOPLEFT", 15, yOffset)
	namePosEditor:SetPosition(nameWidget and nameWidget.position or { point = "TOPLEFT", relativePoint = "CENTER", offsetX = 2, offsetY = 8 })
	yOffset = yOffset - 120

	-- ===== Health Text Section =====
	local healthSep = Widgets:CreateSeparator(parent, "체력 텍스트", CONTENT_WIDTH - 40)
	healthSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local healthWidget = GetWidgetConfig(unit, "healthText")

	local healthCheck = Widgets:CreateCheckButton(parent, "체력 텍스트 표시", function(checked)
		SetWidgetValue(unit, "healthText", "enabled", checked)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	healthCheck:SetPoint("TOPLEFT", 15, yOffset)
	healthCheck:SetChecked(healthWidget and healthWidget.enabled)
	yOffset = yOffset - 30

	-- Health format
	local healthFormatLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	healthFormatLabel:SetText("체력 형식")
	healthFormatLabel:SetPoint("TOPLEFT", 15, yOffset)

	local healthFormatDropdown = Widgets:CreateDropdown(parent, 150)
	healthFormatDropdown:SetPoint("TOPLEFT", healthFormatLabel, "BOTTOMLEFT", 0, -5)
	healthFormatDropdown:SetItems(HealthFormatList)
	healthFormatDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "healthText", "format", value)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	healthFormatDropdown:SetSelected(healthWidget and healthWidget.format or "percentage")

	-- [UF-OPTIONS] separator 드롭다운
	local sepLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	sepLabel:SetText("구분자")
	sepLabel:SetPoint("LEFT", healthFormatLabel, "RIGHT", 200, 0)

	local sepDropdown = Widgets:CreateDropdown(parent, 80)
	sepDropdown:SetPoint("TOPLEFT", sepLabel, "BOTTOMLEFT", 0, -5)
	sepDropdown:SetItems(SeparatorList)
	sepDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "healthText", "separator", value)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	sepDropdown:SetSelected(healthWidget and healthWidget.separator or "/")

	yOffset = yOffset - 55

	-- Health font
	local healthFontSelector = Widgets:CreateFontSelector(parent, 350, function(fontOpt)
		SetWidgetValue(unit, "healthText", "font", fontOpt)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	healthFontSelector:SetPoint("TOPLEFT", 15, yOffset)
	healthFontSelector:SetFont(healthWidget and healthWidget.font or { size = 11, outline = "OUTLINE", shadow = false, justify = "RIGHT" })
	yOffset = yOffset - 110

	-- Health color
	local healthColorPicker = Widgets:CreateEnhancedColorPicker(parent, "체력 텍스트 색상", false, function(colorOpt)
		SetWidgetValue(unit, "healthText", "color", colorOpt)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	healthColorPicker:SetPoint("TOPLEFT", 15, yOffset)
	healthColorPicker:SetColor(healthWidget and healthWidget.color or { rgb = { 1, 1, 1 }, type = "custom" })
	yOffset = yOffset - 35

	-- [OPTION-CLEANUP] healthText.hideIfFull/hideIfEmpty 제거 - displayFormat으로 충분

	local deadStatusCheck = Widgets:CreateCheckButton(parent, "사망 상태 표시", function(checked)
		SetWidgetValue(unit, "healthText", "showDeadStatus", checked)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	deadStatusCheck:SetPoint("TOPLEFT", 15, yOffset)
	deadStatusCheck:SetChecked(healthWidget and healthWidget.showDeadStatus ~= false)
	yOffset = yOffset - 35

	-- Health position
	local healthPosEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, "healthText", "position", pos)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	healthPosEditor:SetPoint("TOPLEFT", 15, yOffset)
	healthPosEditor:SetPosition(healthWidget and healthWidget.position or { point = "RIGHT", relativePoint = "CENTER", offsetX = 0, offsetY = 0 })
	yOffset = yOffset - 120

	-- ===== Power Text Section =====
	local powerSep = Widgets:CreateSeparator(parent, "자원 텍스트", CONTENT_WIDTH - 40)
	powerSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local powerWidget = GetWidgetConfig(unit, "powerText")

	local powerCheck = Widgets:CreateCheckButton(parent, "자원 텍스트 표시", function(checked)
		SetWidgetValue(unit, "powerText", "enabled", checked)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	powerCheck:SetPoint("TOPLEFT", 15, yOffset)
	powerCheck:SetChecked(powerWidget and powerWidget.enabled)
	yOffset = yOffset - 30

	-- Power format
	local powerFormatLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	powerFormatLabel:SetText("자원 형식")
	powerFormatLabel:SetPoint("TOPLEFT", 15, yOffset)

	local powerFormatDropdown = Widgets:CreateDropdown(parent, 150)
	powerFormatDropdown:SetPoint("TOPLEFT", powerFormatLabel, "BOTTOMLEFT", 0, -5)
	powerFormatDropdown:SetItems({
		{ text = "퍼센트", value = "percentage" },
		{ text = "현재값", value = "current" },
		{ text = "현재/최대", value = "current-max" },
		{ text = "손실량", value = "deficit" },
		{ text = "스마트", value = "smart" },
		{ text = "현재(퍼센트)", value = "current-percentage" },
		{ text = "퍼센트/현재", value = "percent-current" },
		{ text = "현재/퍼센트", value = "current-percent" },
	})
	powerFormatDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "powerText", "format", value)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	powerFormatDropdown:SetSelected(powerWidget and powerWidget.format or "percentage")
	yOffset = yOffset - 55

	-- Power font
	local powerFontSelector = Widgets:CreateFontSelector(parent, 350, function(fontOpt)
		SetWidgetValue(unit, "powerText", "font", fontOpt)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	powerFontSelector:SetPoint("TOPLEFT", 15, yOffset)
	powerFontSelector:SetFont(powerWidget and powerWidget.font or { size = 10, outline = "OUTLINE", shadow = false, justify = "RIGHT" })
	yOffset = yOffset - 110

	-- Power color
	local powerColorPicker = Widgets:CreateEnhancedColorPicker(parent, "자원 색상", false, function(colorOpt)
		SetWidgetValue(unit, "powerText", "color", colorOpt)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	powerColorPicker:SetPoint("TOPLEFT", 15, yOffset)
	powerColorPicker:SetColor(powerWidget and powerWidget.color or { rgb = { 1, 1, 1 }, type = "power_color" })
	yOffset = yOffset - 35

	local anchorPowerCheck = Widgets:CreateCheckButton(parent, "자원 바에 고정", function(checked)
		SetWidgetValue(unit, "powerText", "anchorToPowerBar", checked)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	anchorPowerCheck:SetPoint("TOPLEFT", 15, yOffset)
	anchorPowerCheck:SetChecked(powerWidget and powerWidget.anchorToPowerBar)
	yOffset = yOffset - 35

	-- Power position
	local powerPosEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, "powerText", "position", pos)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
	end)
	powerPosEditor:SetPoint("TOPLEFT", 15, yOffset)
	powerPosEditor:SetPosition(powerWidget and powerWidget.position or { point = "BOTTOMRIGHT", relativePoint = "CENTER", offsetX = 0, offsetY = 0 })
	yOffset = yOffset - 120

	-- [OPTION-CLEANUP] levelText 카테고리 전체 제거 - Retail(만렙)에서 무의미
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Layout Page Builder (Party/Raid)
-----------------------------------------------
local function BuildGroupLayoutPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 레이아웃", "그룹 배치 설정")

	local settings = ns.db[unit]
	if not settings then return end

	local yOffset = -60

	-- Growth direction
	local growthLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	growthLabel:SetText("성장 방향")
	growthLabel:SetPoint("TOPLEFT", 15, yOffset)

	local growthDropdown = Widgets:CreateDropdown(parent, 120)
	growthDropdown:SetPoint("TOPLEFT", growthLabel, "BOTTOMLEFT", 0, -5)
	growthDropdown:SetItems({
		{ text = "아래로", value = "DOWN" },
		{ text = "위로", value = "UP" },
		{ text = "오른쪽", value = "RIGHT" },
		{ text = "왼쪽", value = "LEFT" },
		{ text = "가로 중앙", value = "H_CENTER" },
		{ text = "세로 중앙", value = "V_CENTER" },
	})
	growthDropdown:SetOnSelect(function(value)
		ns.db[unit].growDirection = value
		if ns.Update and ns.Update.UpdateLayout then
			ns.Update:UpdateLayout(unit)
		end
		RefreshCurrentPreview()
	end)
	growthDropdown:SetSelected(settings.growDirection or "DOWN")

	-- [FIX] 2차 성장 방향 (열 방향)
	local colGrowLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	colGrowLabel:SetText("2차 방향")
	colGrowLabel:SetPoint("LEFT", growthLabel, "RIGHT", 140, 0)

	local colGrowDropdown = Widgets:CreateDropdown(parent, 120)
	colGrowDropdown:SetPoint("TOPLEFT", colGrowLabel, "BOTTOMLEFT", 0, -5)
	colGrowDropdown:SetItems({
		{ text = "오른쪽", value = "RIGHT" },
		{ text = "왼쪽", value = "LEFT" },
		{ text = "아래로", value = "DOWN" },
		{ text = "위로", value = "UP" },
	})
	colGrowDropdown:SetOnSelect(function(value)
		ns.db[unit].columnGrowDirection = value
		-- [FIX] raid/mythicRaid는 groupGrowDirection도 동시에 설정 (그룹 간 배치 방향)
		if unit == "raid" or unit == "mythicRaid" then
			ns.db[unit].groupGrowDirection = value
		end
		if ns.Update and ns.Update.UpdateLayout then
			ns.Update:UpdateLayout(unit)
		end
		RefreshCurrentPreview()
	end)
	colGrowDropdown:SetSelected(((unit == "raid" or unit == "mythicRaid") and settings.groupGrowDirection) or settings.columnGrowDirection or "RIGHT")
	yOffset = yOffset - 55

	-- Spacing
	if unit == "raid" or unit == "mythicRaid" then
		local spacingXSlider = Widgets:CreateSlider("수평 간격", parent, 0, 20, 100, 1, nil, function(value)
			ns.db[unit].spacingX = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		spacingXSlider:SetPoint("TOPLEFT", 15, yOffset)
		spacingXSlider:SetValue(settings.spacingX or 3)

		local spacingYSlider = Widgets:CreateSlider("수직 간격", parent, 0, 20, 100, 1, nil, function(value)
			ns.db[unit].spacingY = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		spacingYSlider:SetPoint("LEFT", spacingXSlider, "RIGHT", 30, 0)
		spacingYSlider:SetValue(settings.spacingY or 3)
		yOffset = yOffset - 55

		-- Group spacing
		local groupSpacingSlider = Widgets:CreateSlider("그룹 간격", parent, 0, 30, 100, 1, nil, function(value)
			ns.db[unit].groupSpacing = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		groupSpacingSlider:SetPoint("TOPLEFT", 15, yOffset)
		groupSpacingSlider:SetValue(settings.groupSpacing or 5)
		yOffset = yOffset - 55

		-- Units per column
		local unitsPerColSlider = Widgets:CreateSlider("열당 유닛 수", parent, 1, 10, 100, 1, nil, function(value)
			ns.db[unit].unitsPerColumn = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		unitsPerColSlider:SetPoint("TOPLEFT", 15, yOffset)
		unitsPerColSlider:SetValue(settings.unitsPerColumn or 5)

		-- Max columns
		local maxColSlider = Widgets:CreateSlider("최대 열 수", parent, 1, 10, 100, 1, nil, function(value)
			ns.db[unit].maxColumns = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		maxColSlider:SetPoint("LEFT", unitsPerColSlider, "RIGHT", 30, 0)
		maxColSlider:SetValue(settings.maxColumns or 8)
		yOffset = yOffset - 55

		-- Group by
		local groupByLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		groupByLabel:SetText("그룹 기준")
		groupByLabel:SetPoint("TOPLEFT", 15, yOffset)

		local groupByDropdown = Widgets:CreateDropdown(parent, 120)
		groupByDropdown:SetPoint("TOPLEFT", groupByLabel, "BOTTOMLEFT", 0, -5)
		groupByDropdown:SetItems({
			{ text = "그룹", value = "GROUP" },
			{ text = "역할", value = "ROLE" },
			{ text = "직업", value = "CLASS" },
		})
		groupByDropdown:SetOnSelect(function(value)
			ns.db[unit].groupBy = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		groupByDropdown:SetSelected(settings.groupBy or "GROUP")
		yOffset = yOffset - 55

		-- Max groups -- [12.0.1]
		local maxGroupsSlider = Widgets:CreateSlider("최대 그룹 수", parent, 1, 8, 100, 1, nil, function(value)
			ns.db[unit].maxGroups = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		maxGroupsSlider:SetPoint("TOPLEFT", 15, yOffset)
		maxGroupsSlider:SetValue(settings.maxGroups or 8)

		-- Sort direction -- [12.0.1]
		local sortDirLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		sortDirLabel:SetText("정렬 방향")
		sortDirLabel:SetPoint("LEFT", maxGroupsSlider, "RIGHT", 30, 10)

		local sortDirDropdown = Widgets:CreateDropdown(parent, 120)
		sortDirDropdown:SetPoint("TOPLEFT", sortDirLabel, "BOTTOMLEFT", 0, -5)
		sortDirDropdown:SetItems({
			{ text = "오름차순", value = "ASC" },
			{ text = "내림차순", value = "DESC" },
		})
		sortDirDropdown:SetOnSelect(function(value)
			ns.db[unit].sortDir = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		sortDirDropdown:SetSelected(settings.sortDir or "ASC")
		yOffset = yOffset - 55

		-- Sort method -- [12.0.1]
		local sortMethodLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		sortMethodLabel:SetText("정렬 기준")
		sortMethodLabel:SetPoint("TOPLEFT", 15, yOffset)

		local sortMethodDropdown = Widgets:CreateDropdown(parent, 120)
		sortMethodDropdown:SetPoint("TOPLEFT", sortMethodLabel, "BOTTOMLEFT", 0, -5)
		sortMethodDropdown:SetItems({
			{ text = "인덱스", value = "INDEX" },
			{ text = "이름", value = "NAME" },
		})
		sortMethodDropdown:SetOnSelect(function(value)
			ns.db[unit].sortBy = value -- [FIX-OPTION] Config.lua 키 일치: sortBy
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		sortMethodDropdown:SetSelected(settings.sortBy or "INDEX") -- [FIX-OPTION]
		yOffset = yOffset - 55
	else
		-- Party spacing (1차 방향 간격)
		local spacingSlider = Widgets:CreateSlider("1차 간격", parent, 0, 20, 100, 1, nil, function(value)
			ns.db[unit].spacing = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		spacingSlider:SetPoint("TOPLEFT", 15, yOffset)
		spacingSlider:SetValue(settings.spacing or 4)

		-- Party 2차 간격 (열 간격)
		local spacingXSlider = Widgets:CreateSlider("2차 간격", parent, 0, 20, 100, 1, nil, function(value)
			ns.db[unit].spacingX = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		spacingXSlider:SetPoint("LEFT", spacingSlider, "RIGHT", 30, 0)
		spacingXSlider:SetValue(settings.spacingX or 4)
		yOffset = yOffset - 55

		-- Group by
		local partyGroupByLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		partyGroupByLabel:SetText("그룹 기준")
		partyGroupByLabel:SetPoint("TOPLEFT", 15, yOffset)

		local partyGroupByDropdown = Widgets:CreateDropdown(parent, 120)
		partyGroupByDropdown:SetPoint("TOPLEFT", partyGroupByLabel, "BOTTOMLEFT", 0, -5)
		partyGroupByDropdown:SetItems({
			{ text = "그룹", value = "GROUP" },
			{ text = "역할", value = "ROLE" },
			{ text = "직업", value = "CLASS" },
		})
		partyGroupByDropdown:SetOnSelect(function(value)
			ns.db[unit].groupBy = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		partyGroupByDropdown:SetSelected(settings.groupBy or "GROUP")

		-- Sort direction (같은 줄 오른쪽)
		local partySortDirLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		partySortDirLabel:SetText("정렬 방향")
		partySortDirLabel:SetPoint("LEFT", partyGroupByLabel, "RIGHT", 135, 0)

		local partySortDirDropdown = Widgets:CreateDropdown(parent, 120)
		partySortDirDropdown:SetPoint("TOPLEFT", partySortDirLabel, "BOTTOMLEFT", 0, -5)
		partySortDirDropdown:SetItems({
			{ text = "오름차순", value = "ASC" },
			{ text = "내림차순", value = "DESC" },
		})
		partySortDirDropdown:SetOnSelect(function(value)
			ns.db[unit].sortDir = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		partySortDirDropdown:SetSelected(settings.sortDir or "ASC")
		yOffset = yOffset - 55

		-- Sort method
		local partySortMethodLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		partySortMethodLabel:SetText("정렬 기준")
		partySortMethodLabel:SetPoint("TOPLEFT", 15, yOffset)

		local partySortMethodDropdown = Widgets:CreateDropdown(parent, 120)
		partySortMethodDropdown:SetPoint("TOPLEFT", partySortMethodLabel, "BOTTOMLEFT", 0, -5)
		partySortMethodDropdown:SetItems({
			{ text = "인덱스", value = "INDEX" },
			{ text = "이름", value = "NAME" },
		})
		partySortMethodDropdown:SetOnSelect(function(value)
			ns.db[unit].sortBy = value
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		partySortMethodDropdown:SetSelected(settings.sortBy or "INDEX")
		yOffset = yOffset - 55

		-- Show player in party
		local showPlayerCheck = Widgets:CreateCheckButton(parent, "파티에서 플레이어 표시", function(checked)
			ns.db[unit].showPlayer = checked
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		showPlayerCheck:SetPoint("TOPLEFT", 15, yOffset)
		showPlayerCheck:SetChecked(settings.showPlayer)
		yOffset = yOffset - 30

		-- Show in raid
		local showInRaidCheck = Widgets:CreateCheckButton(parent, "레이드에서도 표시", function(checked)
			ns.db[unit].showInRaid = checked
			if ns.Update and ns.Update.UpdateLayout then
				ns.Update:UpdateLayout(unit)
			end
			RefreshCurrentPreview()
		end)
		showInRaidCheck:SetPoint("TOPLEFT", 15, yOffset)
		showInRaidCheck:SetChecked(settings.showInRaid)
	end
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Heal Prediction Page Builder
-----------------------------------------------
local function BuildHealPredictionPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 치유 예측", "치유 예측, 치유 흡수, 보호막 바 설정")

	local settings = ns.db[unit]
	if not settings then return end

	local yOffset = -60

	local hpChildren = {}
	local haChildren = {}
	local sbChildren = {}

	-- ===== Heal Prediction =====
	local hpSep = Widgets:CreateSeparator(parent, "치유 예측 (Incoming Heal)", CONTENT_WIDTH - 40)
	hpSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local hpWidget = GetWidgetConfig(unit, "healPrediction")

	local hpEnable = Widgets:CreateCheckButton(parent, "치유 예측 표시", function(checked)
		SetWidgetValue(unit, "healPrediction", "enabled", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(hpChildren, checked)
	end)
	hpEnable:SetPoint("TOPLEFT", 15, yOffset)
	hpEnable:SetChecked(hpWidget and hpWidget.enabled)
	yOffset = yOffset - 30

	local overHealCheck = Widgets:CreateCheckButton(parent, "초과 치유 표시", function(checked)
		SetWidgetValue(unit, "healPrediction", "overHeal", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	overHealCheck:SetPoint("TOPLEFT", 15, yOffset)
	overHealCheck:SetChecked(hpWidget and hpWidget.overHeal)
	yOffset = yOffset - 35

	-- 치유 예측 텍스처
	local hpTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	hpTexLabel:SetText("텍스처")
	hpTexLabel:SetPoint("TOPLEFT", 15, yOffset)
	local hpTexDropdown = Widgets:CreateDropdown(parent, 200)
	hpTexDropdown:SetPoint("TOPLEFT", hpTexLabel, "BOTTOMLEFT", 0, -5)
	hpTexDropdown:SetItems(GetTextureList())
	hpTexDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "healPrediction", "texture", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	local hpTexCur = hpWidget and hpWidget.texture or (ns.db and ns.db.media and ns.db.media.texture) or [[Interface\Buttons\WHITE8x8]]
	hpTexDropdown:SetSelected(hpTexCur)

	hpChildren[#hpChildren + 1] = overHealCheck
	hpChildren[#hpChildren + 1] = hpTexDropdown
	SetChildrenEnabled(hpChildren, hpWidget and hpWidget.enabled)
	yOffset = yOffset - 55

	-- ===== Heal Absorb =====
	local haSep = Widgets:CreateSeparator(parent, "치유 흡수 (Anti-Heal)", CONTENT_WIDTH - 40)
	haSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local haWidget = GetWidgetConfig(unit, "healAbsorb")

	local haEnable = Widgets:CreateCheckButton(parent, "치유 흡수 표시", function(checked)
		SetWidgetValue(unit, "healAbsorb", "enabled", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(haChildren, checked)
	end)
	haEnable:SetPoint("TOPLEFT", 15, yOffset)
	haEnable:SetChecked(haWidget and haWidget.enabled)
	yOffset = yOffset - 35

	-- 치유 흡수 텍스처
	local haTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	haTexLabel:SetText("텍스처")
	haTexLabel:SetPoint("TOPLEFT", 15, yOffset)
	local haTexDropdown = Widgets:CreateDropdown(parent, 200)
	haTexDropdown:SetPoint("TOPLEFT", haTexLabel, "BOTTOMLEFT", 0, -5)
	haTexDropdown:SetItems(GetTextureList())
	haTexDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "healAbsorb", "texture", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	local haTexCur = haWidget and haWidget.texture or (ns.db and ns.db.media and ns.db.media.texture) or [[Interface\Buttons\WHITE8x8]]
	haTexDropdown:SetSelected(haTexCur)

	local haAnchorLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	haAnchorLabel:SetText("정렬 방향")
	haAnchorLabel:SetPoint("LEFT", haTexDropdown, "RIGHT", 30, 0)
	local haAnchorDropdown = Widgets:CreateDropdown(parent, 120)
	haAnchorDropdown:SetPoint("TOPLEFT", haAnchorLabel, "BOTTOMLEFT", 0, -5)
	haAnchorDropdown:SetItems({
		{ text = "왼쪽", value = "LEFT" },
		{ text = "오른쪽", value = "RIGHT" },
	})
	haAnchorDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "healAbsorb", "anchorPoint", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	haAnchorDropdown:SetSelected(haWidget and haWidget.anchorPoint or "LEFT")

	yOffset = yOffset - 55

	-- ===== Shield Bar =====
	local sbSep = Widgets:CreateSeparator(parent, "보호막 바 (Absorb Shield)", CONTENT_WIDTH - 40)
	sbSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local sbWidget = GetWidgetConfig(unit, "shieldBar")

	local sbEnable = Widgets:CreateCheckButton(parent, "보호막 바 표시", function(checked)
		SetWidgetValue(unit, "shieldBar", "enabled", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(sbChildren, checked)
	end)
	sbEnable:SetPoint("TOPLEFT", 15, yOffset)
	sbEnable:SetChecked(sbWidget and sbWidget.enabled)
	yOffset = yOffset - 30

	local overShieldCheck = Widgets:CreateCheckButton(parent, "초과 보호막 표시", function(checked)
		SetWidgetValue(unit, "shieldBar", "overShield", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	overShieldCheck:SetPoint("TOPLEFT", 15, yOffset)
	overShieldCheck:SetChecked(sbWidget and sbWidget.overShield)

	local reverseFillCheck = Widgets:CreateCheckButton(parent, "채움 반전", function(checked)
		SetWidgetValue(unit, "shieldBar", "reverseFill", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	reverseFillCheck:SetPoint("LEFT", overShieldCheck, "RIGHT", 150, 0)
	reverseFillCheck:SetChecked(sbWidget and sbWidget.reverseFill)
	yOffset = yOffset - 35

	-- 보호막 텍스처
	local sbTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	sbTexLabel:SetText("텍스처")
	sbTexLabel:SetPoint("TOPLEFT", 15, yOffset)
	local sbTexDropdown = Widgets:CreateDropdown(parent, 200)
	sbTexDropdown:SetPoint("TOPLEFT", sbTexLabel, "BOTTOMLEFT", 0, -5)
	sbTexDropdown:SetItems(GetTextureList())
	sbTexDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "shieldBar", "texture", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	local sbTexCur = sbWidget and sbWidget.texture or (ns.db and ns.db.media and ns.db.media.texture) or [[Interface\Buttons\WHITE8x8]]
	sbTexDropdown:SetSelected(sbTexCur)

	for _, c in ipairs({ haTexDropdown, haAnchorLabel, haAnchorDropdown }) do haChildren[#haChildren + 1] = c end
	for _, c in ipairs({ overShieldCheck, reverseFillCheck, sbTexDropdown }) do sbChildren[#sbChildren + 1] = c end
	SetChildrenEnabled(haChildren, haWidget and haWidget.enabled)
	SetChildrenEnabled(sbChildren, sbWidget and sbWidget.enabled)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Dispels Page Builder
-----------------------------------------------
local function BuildDispelsPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 해제", "해제 가능한 디버프 오버레이 설정")

	local settings = ns.db[unit]
	if not settings then return end
	local dispels = settings.widgets and settings.widgets.dispels

	local yOffset = -60

	local dispelChildren = {}
	local debuffChecks = {}

	local enableCheck = Widgets:CreateCheckButton(parent, "해제 오버레이 활성화", function(checked)
		SetWidgetValue(unit, "dispels", "enabled", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(dispelChildren, checked)
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(dispels and dispels.enabled)
	yOffset = yOffset - 35

	-- Highlight type
	local hlTypeLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	hlTypeLabel:SetText("하이라이트 방식")
	hlTypeLabel:SetPoint("TOPLEFT", 15, yOffset)

	local hlTypeDropdown = Widgets:CreateDropdown(parent, 120)
	hlTypeDropdown:SetPoint("TOPLEFT", hlTypeLabel, "BOTTOMLEFT", 0, -5)
	hlTypeDropdown:SetItems({
		{ text = "현재 디버프", value = "current" },
		{ text = "전체 프레임", value = "entire" },
	})
	hlTypeDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "dispels", "highlightType", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	hlTypeDropdown:SetSelected(dispels and dispels.highlightType or "current")
	yOffset = yOffset - 55

	-- Only dispellable
	local onlyDispelCheck = Widgets:CreateCheckButton(parent, "해제 가능한 것만 표시", function(checked)
		SetWidgetValue(unit, "dispels", "onlyShowDispellable", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	onlyDispelCheck:SetPoint("TOPLEFT", 15, yOffset)
	onlyDispelCheck:SetChecked(dispels and dispels.onlyShowDispellable)
	yOffset = yOffset - 40

	-- Debuff types
	local typeSep = Widgets:CreateSeparator(parent, "해제 유형", CONTENT_WIDTH - 40)
	typeSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local debuffTypes = {
		{ key = "magic", name = "마법" },
		{ key = "curse", name = "저주" },
		{ key = "disease", name = "질병" },
		{ key = "poison", name = "독" },
		{ key = "bleed", name = "출혈" },
		{ key = "enrage", name = "격노" },
	}

	local col = 0
	for _, dt in ipairs(debuffTypes) do
		local check = Widgets:CreateCheckButton(parent, dt.name, function(checked)
			SetWidgetValue(unit, "dispels", dt.key, checked)
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
			RefreshCurrentPreview()
		end)
		if col == 0 then
			check:SetPoint("TOPLEFT", 15, yOffset)
		elseif col == 1 then
			check:SetPoint("TOPLEFT", 135, yOffset)
		else
			check:SetPoint("TOPLEFT", 255, yOffset)
			col = -1
			yOffset = yOffset - 30
		end
		check:SetChecked(dispels and dispels[dt.key])
		debuffChecks[#debuffChecks + 1] = check
		col = col + 1
	end
	if col > 0 then yOffset = yOffset - 30 end
	yOffset = yOffset - 10

	-- Icon style
	local iconSep = Widgets:CreateSeparator(parent, "아이콘", CONTENT_WIDTH - 40)
	iconSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local iconStyleLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	iconStyleLabel:SetText("아이콘 스타일")
	iconStyleLabel:SetPoint("TOPLEFT", 15, yOffset)

	local iconStyleDropdown = Widgets:CreateDropdown(parent, 100)
	iconStyleDropdown:SetPoint("TOPLEFT", iconStyleLabel, "BOTTOMLEFT", 0, -5)
	iconStyleDropdown:SetItems({
		{ text = "없음", value = "none" },
		{ text = "아이콘", value = "icon" },
	})
	iconStyleDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "dispels", "iconStyle", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	iconStyleDropdown:SetSelected(dispels and dispels.iconStyle or "none")
	yOffset = yOffset - 55

	-- Icon size
	local iconSizeSlider = Widgets:CreateSlider("아이콘 크기", parent, 8, 32, 100, 1, nil, function(value)
		SetWidgetValue(unit, "dispels", "size", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	iconSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
	iconSizeSlider:SetValue(dispels and dispels.size or 12)
	yOffset = yOffset - 60

	-- Position
	local posSep = Widgets:CreateSeparator(parent, "위치", CONTENT_WIDTH - 40)
	posSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local posEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, "dispels", "position", pos)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	posEditor:SetPoint("TOPLEFT", 15, yOffset)
	posEditor:SetPosition(dispels and dispels.position or { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", offsetX = -4, offsetY = 4 })

	for _, c in ipairs({ hlTypeLabel, hlTypeDropdown, onlyDispelCheck, typeSep, iconSep, iconStyleLabel, iconStyleDropdown, iconSizeSlider, posSep, posEditor }) do
		dispelChildren[#dispelChildren + 1] = c
	end
	for _, c in ipairs(debuffChecks) do dispelChildren[#dispelChildren + 1] = c end
	SetChildrenEnabled(dispelChildren, dispels and dispels.enabled)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Threat / Highlight Page Builder
-----------------------------------------------
local function BuildThreatHighlightPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 위협/하이라이트", "위협 표시 및 하이라이트 설정")

	local settings = ns.db[unit]
	if not settings then return end

	local yOffset = -60

	local threatChildren = {}
	local hlChildren = {}

	-- ===== Threat =====
	local threatSep = Widgets:CreateSeparator(parent, "위협 표시", CONTENT_WIDTH - 40)
	threatSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local threatWidget = GetWidgetConfig(unit, "threat")

	local threatEnable = Widgets:CreateCheckButton(parent, "위협 표시 활성화", function(checked)
		SetWidgetValue(unit, "threat", "enabled", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(threatChildren, checked)
	end)
	threatEnable:SetPoint("TOPLEFT", 15, yOffset)
	threatEnable:SetChecked(threatWidget and threatWidget.enabled)
	yOffset = yOffset - 35

	-- Style
	local styleLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	styleLabel:SetText("위협 스타일")
	styleLabel:SetPoint("TOPLEFT", 15, yOffset)

	local styleDropdown = Widgets:CreateDropdown(parent, 100)
	styleDropdown:SetPoint("TOPLEFT", styleLabel, "BOTTOMLEFT", 0, -5)
	styleDropdown:SetItems({
		{ text = "테두리", value = "border" },
		{ text = "글로우", value = "glow" },
	})
	styleDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "threat", "style", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	styleDropdown:SetSelected(threatWidget and threatWidget.style or "border")

	local borderSizeSlider = Widgets:CreateSlider("테두리 두께", parent, 0.1, 3, 80, 0.1, nil, function(value)
		SetWidgetValue(unit, "threat", "borderSize", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	borderSizeSlider:SetPoint("LEFT", styleDropdown, "RIGHT", 30, 0)
	borderSizeSlider:SetValue(threatWidget and threatWidget.borderSize or 1)
	yOffset = yOffset - 60

	-- Threat colors
	local threatColors = threatWidget and threatWidget.colors or {}

	local lowThreatCP = Widgets:CreateColorPicker(parent, "높은 위협", true, function(r, g, b, a)
		SetWidgetValue(unit, "threat", "colors", { [0] = { 0.5, 0.5, 0.5, 0 }, [1] = { r, g, b, a }, [2] = threatColors[2] or { 1, 0.6, 0, 1 }, [3] = threatColors[3] or { 1, 0, 0, 1 } })
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	lowThreatCP:SetPoint("TOPLEFT", 15, yOffset)
	local ltc = threatColors[1] or { 1, 1, 0.47, 1 }
	lowThreatCP:SetColor(ltc[1], ltc[2], ltc[3], ltc[4])

	local highThreatCP = Widgets:CreateColorPicker(parent, "최고 위협", true, function(r, g, b, a)
		SetWidgetValue(unit, "threat", "colors", { [0] = { 0.5, 0.5, 0.5, 0 }, [1] = threatColors[1] or { 1, 1, 0.47, 1 }, [2] = { r, g, b, a }, [3] = threatColors[3] or { 1, 0, 0, 1 } })
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	highThreatCP:SetPoint("LEFT", lowThreatCP, "RIGHT", 180, 0)
	local htc = threatColors[2] or { 1, 0.6, 0, 1 }
	highThreatCP:SetColor(htc[1], htc[2], htc[3], htc[4])
	yOffset = yOffset - 30

	local tankingCP = Widgets:CreateColorPicker(parent, "탱킹 중", true, function(r, g, b, a)
		SetWidgetValue(unit, "threat", "colors", { [0] = { 0.5, 0.5, 0.5, 0 }, [1] = threatColors[1] or { 1, 1, 0.47, 1 }, [2] = threatColors[2] or { 1, 0.6, 0, 1 }, [3] = { r, g, b, a } })
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	tankingCP:SetPoint("TOPLEFT", 15, yOffset)
	local tkc = threatColors[3] or { 1, 0, 0, 1 }
	tankingCP:SetColor(tkc[1], tkc[2], tkc[3], tkc[4])
	yOffset = yOffset - 45

	-- ===== Highlight =====
	local hlSep = Widgets:CreateSeparator(parent, "하이라이트", CONTENT_WIDTH - 40)
	hlSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local hlWidget = GetWidgetConfig(unit, "highlight")

	local hlEnable = Widgets:CreateCheckButton(parent, "하이라이트 활성화", function(checked)
		SetWidgetValue(unit, "highlight", "enabled", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(hlChildren, checked)
	end)
	hlEnable:SetPoint("TOPLEFT", 15, yOffset)
	hlEnable:SetChecked(hlWidget and hlWidget.enabled)
	yOffset = yOffset - 30

	local hoverCheck = Widgets:CreateCheckButton(parent, "마우스오버 하이라이트", function(checked)
		SetWidgetValue(unit, "highlight", "hover", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	hoverCheck:SetPoint("TOPLEFT", 15, yOffset)
	hoverCheck:SetChecked(hlWidget and hlWidget.hover)

	local targetCheck = Widgets:CreateCheckButton(parent, "대상 하이라이트", function(checked)
		SetWidgetValue(unit, "highlight", "target", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	targetCheck:SetPoint("LEFT", hoverCheck, "RIGHT", 150, 0)
	targetCheck:SetChecked(hlWidget and hlWidget.target)
	yOffset = yOffset - 35

	local hlSizeSlider = Widgets:CreateSlider("테두리 두께", parent, 0.1, 3, 80, 0.1, nil, function(value)
		SetWidgetValue(unit, "highlight", "size", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	hlSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
	hlSizeSlider:SetValue(hlWidget and hlWidget.size or 1)
	yOffset = yOffset - 55

	local targetColorCP = Widgets:CreateColorPicker(parent, "대상 색상", true, function(r, g, b, a)
		SetWidgetValue(unit, "highlight", "targetColor", { r, g, b, a })
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	targetColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local tcc = hlWidget and hlWidget.targetColor or { 1, 0.3, 0.3, 1 }
	targetColorCP:SetColor(tcc[1], tcc[2], tcc[3], tcc[4])

	local hoverColorCP = Widgets:CreateColorPicker(parent, "마우스오버 색상", true, function(r, g, b, a)
		SetWidgetValue(unit, "highlight", "hoverColor", { r, g, b, a })
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	hoverColorCP:SetPoint("LEFT", targetColorCP, "RIGHT", 180, 0)
	local hcc = hlWidget and hlWidget.hoverColor or { 1, 1, 1, 0.3 }
	hoverColorCP:SetColor(hcc[1], hcc[2], hcc[3], hcc[4])

	for _, c in ipairs({ styleLabel, styleDropdown, borderSizeSlider, lowThreatCP, highThreatCP, tankingCP }) do
		threatChildren[#threatChildren + 1] = c
	end
	for _, c in ipairs({ hoverCheck, targetCheck, hlSizeSlider, targetColorCP, hoverColorCP }) do
		hlChildren[#hlChildren + 1] = c
	end
	SetChildrenEnabled(threatChildren, threatWidget and threatWidget.enabled)
	SetChildrenEnabled(hlChildren, hlWidget and hlWidget.enabled)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Debuff Highlight Page Builder (그룹 프레임 전용)
-----------------------------------------------
local function BuildDebuffHighlightPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 디버프 하이라이트", "해제 가능한 디버프가 있을 때 프레임을 강조합니다")

	local settings = ns.db[unit]
	if not settings then return end

	local yOffset = -60
	local children = {}

	local dhWidget = GetWidgetConfig(unit, "debuffHighlight")

	-- 활성화 체크박스
	local enableCheck = Widgets:CreateCheckButton(parent, "디버프 하이라이트 활성화", function(checked)
		SetWidgetValue(unit, "debuffHighlight", "enabled", checked)
		local GF = ns.GroupFrames
		if GF and GF.RefreshAll then GF:RefreshAll() end
		SetChildrenEnabled(children, checked)
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(dhWidget and dhWidget.enabled ~= false)
	yOffset = yOffset - 35

	-- 테두리 두께 슬라이더
	local borderSizeSlider = Widgets:CreateSlider("테두리 두께", parent, 1, 5, 80, 1, nil, function(value)
		SetWidgetValue(unit, "debuffHighlight", "borderSize", value)
		local GF = ns.GroupFrames
		if GF and GF.RefreshAll then GF:RefreshAll() end
	end)
	borderSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
	borderSizeSlider:SetValue(dhWidget and dhWidget.borderSize or 2)
	yOffset = yOffset - 55

	-- 오버레이 투명도 슬라이더
	local overlaySlider = Widgets:CreateSlider("오버레이 투명도", parent, 0, 1, 80, 0.05, nil, function(value)
		SetWidgetValue(unit, "debuffHighlight", "overlayAlpha", value)
		local GF = ns.GroupFrames
		if GF and GF.RefreshAll then GF:RefreshAll() end
	end)
	overlaySlider:SetPoint("LEFT", borderSizeSlider, "RIGHT", 80, 0)
	overlaySlider:SetValue(dhWidget and dhWidget.overlayAlpha or 0.25)
	yOffset = yOffset - 10

	-- 해제 불가 디버프도 표시
	local nonDispelCheck = Widgets:CreateCheckButton(parent, "해제 불가 디버프도 표시", function(checked)
		SetWidgetValue(unit, "debuffHighlight", "showNonDispellable", checked)
		local GF = ns.GroupFrames
		if GF and GF.RefreshAll then GF:RefreshAll() end
	end)
	nonDispelCheck:SetPoint("TOPLEFT", 15, yOffset)
	nonDispelCheck:SetChecked(dhWidget and dhWidget.showNonDispellable)
	yOffset = yOffset - 40

	-- 디스펠 타입별 색상 설정
	local colorSep = Widgets:CreateSeparator(parent, "디스펠 타입 색상", CONTENT_WIDTH - 40)
	colorSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local C = ns.Constants
	local dispelTypes = {
		{ key = "Magic",   name = "마법" },
		{ key = "Curse",   name = "저주" },
		{ key = "Disease", name = "질병" },
		{ key = "Poison",  name = "독" },
		{ key = "Bleed",   name = "출혈/격노" },
	}

	local col = 0
	for _, dt in ipairs(dispelTypes) do
		local dc = C and C.DISPEL_COLORS and C.DISPEL_COLORS[dt.key] or { 1, 1, 1 }

		local cp = Widgets:CreateColorPicker(parent, dt.name, false, function(r, g, b)
			-- C.DISPEL_COLORS 직접 업데이트
			if C and C.DISPEL_COLORS then
				C.DISPEL_COLORS[dt.key] = { r, g, b }
			end
			-- ColorCurve 무효화 (새 색상 반영)
			local GF = ns.GroupFrames
			if GF and GF.InvalidateDebuffHighlightCurve then
				GF:InvalidateDebuffHighlightCurve()
			end
			if GF and GF.RefreshAll then GF:RefreshAll() end
		end)

		if col == 0 then
			cp:SetPoint("TOPLEFT", 15, yOffset)
		elseif col == 1 then
			cp:SetPoint("TOPLEFT", 180, yOffset)
		else
			cp:SetPoint("TOPLEFT", 345, yOffset)
			col = -1
			yOffset = yOffset - 30
		end
		cp:SetColor(dc[1], dc[2], dc[3], 1)
		children[#children + 1] = cp
		col = col + 1
	end
	if col > 0 then yOffset = yOffset - 30 end

	-- [FIX] 디버프 아이콘 종류별 테두리 옵션
	yOffset = yOffset - 10
	local debuffBorderSep = Widgets:CreateSeparator(parent, "디버프 아이콘", CONTENT_WIDTH - 40)
	debuffBorderSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local debuffsWidget = settings and settings.widgets and settings.widgets.debuffs
	local debuffBorderCheck = Widgets:CreateCheckButton(parent, "디버프 아이콘 종류별 테두리 색상", function(checked)
		SetWidgetValue(settings, "debuffs", "showDispelTypeBorder", checked)
		local GF = ns.GroupFrames
		if GF and GF.RefreshAll then GF:RefreshAll() end
	end)
	debuffBorderCheck:SetPoint("TOPLEFT", 15, yOffset)
	debuffBorderCheck:SetChecked(debuffsWidget and debuffsWidget.showDispelTypeBorder ~= false)
	yOffset = yOffset - 30

	for _, c in ipairs({ borderSizeSlider, overlaySlider, nonDispelCheck, colorSep, debuffBorderSep, debuffBorderCheck }) do
		children[#children + 1] = c
	end
	SetChildrenEnabled(children, dhWidget and dhWidget.enabled ~= false)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Fader Page Builder
-----------------------------------------------
local function BuildFaderPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 페이드", "조건에 따라 프레임을 자동으로 투명하게")

	local settings = ns.db[unit]
	if not settings then return end
	local fader = settings.widgets and settings.widgets.fader

	local yOffset = -60

	-- Collect child controls for conditional enable
	local faderChildren = {}

	local enableCheck = Widgets:CreateCheckButton(parent, "페이드 시스템 활성화", function(checked)
		SetWidgetValue(unit, "fader", "enabled", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(faderChildren, checked)
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(fader and fader.enabled)
	yOffset = yOffset - 40

	-- Conditions
	local condSep = Widgets:CreateSeparator(parent, "페이드 조건 (체크 시 불투명 유지)", CONTENT_WIDTH - 40)
	condSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local rangeCheck = Widgets:CreateCheckButton(parent, "사거리 내", function(checked)
		SetWidgetValue(unit, "fader", "range", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	rangeCheck:SetPoint("TOPLEFT", 15, yOffset)
	rangeCheck:SetChecked(fader and fader.range)

	local combatCheck = Widgets:CreateCheckButton(parent, "전투 중", function(checked)
		SetWidgetValue(unit, "fader", "combat", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	combatCheck:SetPoint("LEFT", rangeCheck, "RIGHT", 100, 0)
	combatCheck:SetChecked(fader and fader.combat)

	local hoverCheck = Widgets:CreateCheckButton(parent, "마우스오버", function(checked)
		SetWidgetValue(unit, "fader", "hover", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	hoverCheck:SetPoint("LEFT", combatCheck, "RIGHT", 100, 0)
	hoverCheck:SetChecked(fader and fader.hover)
	yOffset = yOffset - 30

	local targetCheck = Widgets:CreateCheckButton(parent, "대상일 때", function(checked)
		SetWidgetValue(unit, "fader", "target", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	targetCheck:SetPoint("TOPLEFT", 15, yOffset)
	targetCheck:SetChecked(fader and fader.target)

	local unitTargetCheck = Widgets:CreateCheckButton(parent, "유닛이 대상일 때", function(checked)
		SetWidgetValue(unit, "fader", "unitTarget", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	unitTargetCheck:SetPoint("LEFT", targetCheck, "RIGHT", 100, 0)
	unitTargetCheck:SetChecked(fader and fader.unitTarget)
	yOffset = yOffset - 45

	-- Alpha settings
	local alphaSep = Widgets:CreateSeparator(parent, "투명도 설정", CONTENT_WIDTH - 40)
	alphaSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local maxAlphaSlider = Widgets:CreateSlider("최대 투명도", parent, 0.1, 1, 120, 0.05, nil, function(value)
		SetWidgetValue(unit, "fader", "maxAlpha", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	maxAlphaSlider:SetPoint("TOPLEFT", 15, yOffset)
	maxAlphaSlider:SetValue(fader and fader.maxAlpha or 1)

	local minAlphaSlider = Widgets:CreateSlider("최소 투명도", parent, 0, 1, 120, 0.05, nil, function(value)
		SetWidgetValue(unit, "fader", "minAlpha", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	minAlphaSlider:SetPoint("LEFT", maxAlphaSlider, "RIGHT", 30, 0)
	minAlphaSlider:SetValue(fader and fader.minAlpha or 0.35)
	yOffset = yOffset - 55

	local fadeDurSlider = Widgets:CreateSlider("전환 시간 (초)", parent, 0, 1, 120, 0.05, nil, function(value)
		SetWidgetValue(unit, "fader", "fadeDuration", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	fadeDurSlider:SetPoint("TOPLEFT", 15, yOffset)
	fadeDurSlider:SetValue(fader and fader.fadeDuration or 0.25)

	for _, c in ipairs({ condSep, rangeCheck, combatCheck, hoverCheck, targetCheck, unitTargetCheck, alphaSep, maxAlphaSlider, minAlphaSlider, fadeDurSlider }) do
		faderChildren[#faderChildren + 1] = c
	end
	SetChildrenEnabled(faderChildren, fader and fader.enabled)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Custom Text Page Builder (3 slots)
-----------------------------------------------
local function BuildCustomTextPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 커스텀 텍스트", "최대 3개의 자유 텍스트 위젯 설정")

	local settings = ns.db[unit]
	if not settings then return end
	local ctWidget = settings.widgets and settings.widgets.customText

	local yOffset = -60

	local ctChildren = {}

	local ctEnable = Widgets:CreateCheckButton(parent, "커스텀 텍스트 시스템 활성화", function(checked)
		SetWidgetValue(unit, "customText", "enabled", checked)
		if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(ctChildren, checked)
	end)
	ctEnable:SetPoint("TOPLEFT", 15, yOffset)
	ctEnable:SetChecked(ctWidget and ctWidget.enabled)
	yOffset = yOffset - 40

	local texts = ctWidget and ctWidget.texts or {}

	local CustomTextFormatList = {
		{ text = "없음 (직접 입력)", value = "" },
		{ text = "[이름]", value = "[ddingui:name:medium]" },
		{ text = "[이름 (짧은)]", value = "[ddingui:name:short]" },
		{ text = "[체력%]", value = "[ddingui:health:percent]" },
		{ text = "[체력]", value = "[ddingui:health:current]" },
		{ text = "[체력/최대]", value = "[ddingui:health:current-max]" },
		{ text = "[자원]", value = "[ddingui:power]" },
		{ text = "[자원%]", value = "[ddingui:power:percent]" },
		{ text = "[레벨]", value = "[ddingui:level]" },
		{ text = "[등급]", value = "[ddingui:classification]" },
		{ text = "[상태]", value = "[ddingui:status]" },
		{ text = "[직업색+이름]", value = "[ddingui:classcolor][ddingui:name:medium]|r" },
	}

	local slotNames = { "text1", "text2", "text3" }
	local slotLabels = { "텍스트 슬롯 1", "텍스트 슬롯 2", "텍스트 슬롯 3" }

	for i, slotKey in ipairs(slotNames) do
		local slot = texts[slotKey] or {}

		local slotSep = Widgets:CreateSeparator(parent, slotLabels[i], CONTENT_WIDTH - 40)
		slotSep:SetPoint("TOPLEFT", 15, yOffset)
		yOffset = yOffset - 35
		ctChildren[#ctChildren + 1] = slotSep

		local slotEnable = Widgets:CreateCheckButton(parent, slotLabels[i] .. " 활성화", function(checked)
			SetWidgetValue(unit, "customText", "texts." .. slotKey .. ".enabled", checked)
			if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
			RefreshCurrentPreview()
		end)
		slotEnable:SetPoint("TOPLEFT", 15, yOffset)
		slotEnable:SetChecked(slot.enabled)
		ctChildren[#ctChildren + 1] = slotEnable
		yOffset = yOffset - 30

		-- Text format
		local fmtLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		fmtLabel:SetText("텍스트 형식")
		fmtLabel:SetPoint("TOPLEFT", 15, yOffset)
		ctChildren[#ctChildren + 1] = fmtLabel

		local fmtDropdown = Widgets:CreateDropdown(parent, 150)
		fmtDropdown:SetPoint("TOPLEFT", fmtLabel, "BOTTOMLEFT", 0, -5)
		fmtDropdown:SetItems(CustomTextFormatList)

		-- [UF-OPTIONS] 직접 입력 EditBox + 태그 안내
		local customTagInput = Widgets:CreateEditBox(parent, 250, 24)
		customTagInput:SetPoint("LEFT", fmtDropdown, "RIGHT", 10, 0)
		customTagInput:SetPlaceholder("예: [name] - [health:percent]")
		customTagInput:SetText(slot.textFormat or "")
		ctChildren[#ctChildren + 1] = customTagInput

		local tagHelpText = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
		tagHelpText:SetText("태그: [name] [health:percent] [absorb] [classcolor] [power] [level] 등 (자동 변환됨)")
		tagHelpText:SetTextColor(0.5, 0.5, 0.5)
		tagHelpText:SetPoint("TOPLEFT", fmtDropdown, "BOTTOMLEFT", 0, -3)
		ctChildren[#ctChildren + 1] = tagHelpText

		-- "직접 입력" 선택 시에만 EditBox 표시
		local function UpdateCustomTagVisibility(selectedValue)
			if selectedValue == "" then
				customTagInput:Show()
				tagHelpText:Show()
			else
				customTagInput:Hide()
				tagHelpText:Hide()
			end
		end

		customTagInput:SetScript("OnEnterPressed", function(self)
			local text = self:GetText()
			SetWidgetValue(unit, "customText", "texts." .. slotKey .. ".textFormat", text)
			-- [FIX] 태그 입력 시 슬롯 + 시스템 자동 활성화
			if text and text ~= "" then
				SetWidgetValue(unit, "customText", "texts." .. slotKey .. ".enabled", true)
				SetWidgetValue(unit, "customText", "enabled", true)
				slotEnable:SetChecked(true)
				ctEnable:SetChecked(true)
				SetChildrenEnabled(ctChildren, true)
			end
			if ns.Update and ns.Update.UpdateCustomText then ns.Update:UpdateCustomText(ns.frames[unit], unit) end
			if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
			RefreshCurrentPreview()
			self:ClearFocus()
		end)

		fmtDropdown:SetOnSelect(function(value)
			if value ~= "" then
				-- 프리셋 선택 시 EditBox도 동기화
				customTagInput:SetText(value)
				-- [FIX] 프리셋 선택 시 슬롯 + 시스템 자동 활성화
				SetWidgetValue(unit, "customText", "texts." .. slotKey .. ".enabled", true)
				SetWidgetValue(unit, "customText", "enabled", true)
				slotEnable:SetChecked(true)
				ctEnable:SetChecked(true)
				SetChildrenEnabled(ctChildren, true)
			end
			SetWidgetValue(unit, "customText", "texts." .. slotKey .. ".textFormat", value)
			if ns.Update and ns.Update.UpdateCustomText then ns.Update:UpdateCustomText(ns.frames[unit], unit) end
			if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
			RefreshCurrentPreview()
			UpdateCustomTagVisibility(value)
		end)
		fmtDropdown:SetSelected(slot.textFormat or "")
		ctChildren[#ctChildren + 1] = fmtDropdown
		UpdateCustomTagVisibility(slot.textFormat or "")
		yOffset = yOffset - 70

		-- Font
		local slotFont = Widgets:CreateFontSelector(parent, 350, function(fontOpt)
			SetWidgetValue(unit, "customText", "texts." .. slotKey .. ".font", fontOpt)
			if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
			RefreshCurrentPreview()
		end)
		slotFont:SetPoint("TOPLEFT", 15, yOffset)
		slotFont:SetFont(slot.font or { size = 12, outline = "OUTLINE", shadow = false, justify = "CENTER" })
		ctChildren[#ctChildren + 1] = slotFont
		yOffset = yOffset - 110

		-- Color
		local slotColor = Widgets:CreateEnhancedColorPicker(parent, "색상", false, function(colorOpt)
			SetWidgetValue(unit, "customText", "texts." .. slotKey .. ".color", colorOpt)
			if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
			RefreshCurrentPreview()
		end)
		slotColor:SetPoint("TOPLEFT", 15, yOffset)
		slotColor:SetColor(slot.color or { rgb = { 1, 1, 1 }, type = "custom" })
		ctChildren[#ctChildren + 1] = slotColor
		yOffset = yOffset - 35

		-- Position
		local slotPos = Widgets:CreatePositionEditor(parent, 350, function(pos)
			SetWidgetValue(unit, "customText", "texts." .. slotKey .. ".position", pos)
			if ns.Update and ns.Update.UpdateTexts then ns.Update:UpdateTexts(unit) end
			RefreshCurrentPreview()
		end)
		slotPos:SetPoint("TOPLEFT", 15, yOffset)
		slotPos:SetPosition(slot.position or { point = "CENTER", relativePoint = "CENTER", offsetX = 0, offsetY = 0 })
		ctChildren[#ctChildren + 1] = slotPos
		yOffset = yOffset - 130
	end

	SetChildrenEnabled(ctChildren, ctWidget and ctWidget.enabled)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Alt Power Bar Page Builder
-----------------------------------------------
local function BuildAltPowerBarPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 보조 자원 바", "보조 자원 바 (대체 파워) 설정")

	local settings = ns.db[unit]
	if not settings then return end
	local apWidget = settings.widgets and settings.widgets.altPowerBar

	local yOffset = -60

	local apChildren = {}

	local apEnable = Widgets:CreateCheckButton(parent, "보조 자원 바 활성화", function(checked)
		SetWidgetValue(unit, "altPowerBar", "enabled", checked)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
		SetChildrenEnabled(apChildren, checked)
	end)
	apEnable:SetPoint("TOPLEFT", 15, yOffset)
	apEnable:SetChecked(apWidget and apWidget.enabled)
	yOffset = yOffset - 40

	-- [OPTION-CLEANUP] sameSizeAsHealthBar 제거 - 커스텀 크기 설정이면 충분
	-- [OPTION-CLEANUP] hideIfEmpty/hideIfFull/hideOutOfCombat 제거 - autoHide로 통합

	-- Size section
	local sizeSep = Widgets:CreateSeparator(parent, "크기", CONTENT_WIDTH - 40)
	sizeSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local widthSlider = Widgets:CreateSlider("너비", parent, 30, 400, 120, 1, nil, function(value)
		SetWidgetValue(unit, "altPowerBar", "size.width", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	widthSlider:SetPoint("TOPLEFT", 15, yOffset)
	widthSlider:SetValue(apWidget and apWidget.size and apWidget.size.width or 200)

	local heightSlider = Widgets:CreateSlider("높이", parent, 1, 30, 120, 1, nil, function(value)
		SetWidgetValue(unit, "altPowerBar", "size.height", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	heightSlider:SetPoint("LEFT", widthSlider, "RIGHT", 30, 0)
	heightSlider:SetValue(apWidget and apWidget.size and apWidget.size.height or 4)
	yOffset = yOffset - 60

	-- Position section
	local posSep = Widgets:CreateSeparator(parent, "위치", CONTENT_WIDTH - 40)
	posSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local posEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, "altPowerBar", "position", pos)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	posEditor:SetPoint("TOPLEFT", 15, yOffset)
	posEditor:SetPosition(apWidget and apWidget.position or { point = "TOPLEFT", relativePoint = "TOPLEFT", offsetX = 0, offsetY = 0 })

	yOffset = yOffset - 120

	-- Texture section -- [FIX] 보조 자원 바 텍스처/배경 옵션 추가
	local apTexSep = Widgets:CreateSeparator(parent, "텍스처", CONTENT_WIDTH - 40)
	apTexSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local apTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	apTexLabel:SetText("바 텍스처")
	apTexLabel:SetPoint("TOPLEFT", 15, yOffset)

	local apTexDropdown = Widgets:CreateDropdown(parent, 180)
	apTexDropdown:SetPoint("TOPLEFT", apTexLabel, "BOTTOMLEFT", 0, -5)
	apTexDropdown:SetItems(GetTextureList())
	apTexDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "altPowerBar", "texture", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	apTexDropdown:SetSelected(apWidget and apWidget.texture or [[Interface\Buttons\WHITE8x8]])

	local apBgTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	apBgTexLabel:SetText("배경 텍스처")
	apBgTexLabel:SetPoint("LEFT", apTexLabel, "RIGHT", 200, 0)

	local apBgTexDropdown = Widgets:CreateDropdown(parent, 180)
	apBgTexDropdown:SetPoint("TOPLEFT", apBgTexLabel, "BOTTOMLEFT", 0, -5)
	apBgTexDropdown:SetItems(GetTextureList())
	apBgTexDropdown:SetOnSelect(function(value)
		SetWidgetValue(unit, "altPowerBar", "background.texture", value)
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	local apBgTex = apWidget and apWidget.background and apWidget.background.texture or [[Interface\Buttons\WHITE8x8]]
	apBgTexDropdown:SetSelected(apBgTex)
	yOffset = yOffset - 65

	-- Background color
	local apBgColorCP = Widgets:CreateColorPicker(parent, "배경 색상", true, function(r, g, b, a)
		SetWidgetValue(unit, "altPowerBar", "background.color", { r, g, b, a })
		if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unit) end
		RefreshCurrentPreview()
	end)
	apBgColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local apBgCol = apWidget and apWidget.background and apWidget.background.color or { 0.08, 0.08, 0.08, 0.85 }
	apBgColorCP:SetColor(apBgCol[1], apBgCol[2], apBgCol[3], apBgCol[4] or 0.85)
	yOffset = yOffset - 35

	for _, c in ipairs({ sizeSep, widthSlider, heightSlider, posSep, posEditor, apTexSep, apTexLabel, apTexDropdown, apBgTexLabel, apBgTexDropdown, apBgColorCP }) do
		apChildren[#apChildren + 1] = c
	end
	SetChildrenEnabled(apChildren, apWidget and apWidget.enabled)
	parent:SetHeight(math.abs(yOffset) + 50)
end

-----------------------------------------------
-- Icons Page Builder (Combat + Resting)
-----------------------------------------------
-----------------------------------------------
-- Unified Indicators Page Builder
-- 모든 유닛에 사용: raidIcon(전체) + combatIcon/restingIcon(player) + roleIcon/leaderIcon(전체) + readyCheck/resurrect/summon(party/raid)
-----------------------------------------------
local function BuildIndicatorBlock(parent, unit, key, name, defaultSize, yOffset)
	local widget = GetWidgetConfig(unit, key)
	local children = {}

	local sep = Widgets:CreateSeparator(parent, name, CONTENT_WIDTH - 40)
	sep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local enableCheck = Widgets:CreateCheckButton(parent, name .. " 표시", function(checked)
		SetWidgetValue(unit, key, "enabled", checked)
		if ns.Update and ns.Update.UpdateIndicators then
			ns.Update:UpdateIndicators(unit)
		end
		RefreshCurrentPreview()
		SetChildrenEnabled(children, checked)
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(widget and widget.enabled)
	yOffset = yOffset - 30

	local sizeSlider = Widgets:CreateSlider("크기", parent, 8, 48, 180, 1, nil, function(value)
		SetWidgetValue(unit, key, "size.width", value)
		SetWidgetValue(unit, key, "size.height", value)
		if ns.Update and ns.Update.UpdateIndicators then
			ns.Update:UpdateIndicators(unit)
		end
		RefreshCurrentPreview()
	end)
	sizeSlider:SetPoint("TOPLEFT", 15, yOffset)
	sizeSlider:SetValue(widget and widget.size and widget.size.width or defaultSize)
	yOffset = yOffset - 55

	local posEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue(unit, key, "position", pos)
		if ns.Update and ns.Update.UpdateIndicators then
			ns.Update:UpdateIndicators(unit)
		end
		RefreshCurrentPreview()
	end)
	posEditor:SetPoint("TOPLEFT", 15, yOffset)
	posEditor:SetPosition(widget and widget.position or { point = "CENTER", relativePoint = "CENTER", offsetX = 0, offsetY = 0 })

	for _, c in ipairs({ sizeSlider, posEditor }) do
		children[#children + 1] = c
	end
	SetChildrenEnabled(children, widget and widget.enabled)
	yOffset = yOffset - 125

	return yOffset
end

-- [FIX] 역할 아이콘 — 탱커/힐러/딜러 개별 표시 체크박스
local function BuildRoleFilterChecks(parent, unit, yOffset)
	local roleWidget = GetWidgetConfig(unit, "roleIcon")

	local GF = ns.GroupFrames
	local function OnRoleFilterChanged()
		if GF and GF.RefreshAll then GF:RefreshAll() end
		RefreshCurrentPreview()
	end

	local tankCheck = Widgets:CreateCheckButton(parent, "탱커", function(checked)
		SetWidgetValue(unit, "roleIcon", "showTank", checked)
		OnRoleFilterChanged()
	end)
	tankCheck:SetPoint("TOPLEFT", 30, yOffset)
	tankCheck:SetChecked(roleWidget and roleWidget.showTank ~= false)

	local healerCheck = Widgets:CreateCheckButton(parent, "힐러", function(checked)
		SetWidgetValue(unit, "roleIcon", "showHealer", checked)
		OnRoleFilterChanged()
	end)
	healerCheck:SetPoint("LEFT", tankCheck.label, "RIGHT", 15, 0)
	healerCheck:SetChecked(roleWidget and roleWidget.showHealer ~= false)

	local dpsCheck = Widgets:CreateCheckButton(parent, "딜러", function(checked)
		SetWidgetValue(unit, "roleIcon", "showDPS", checked)
		OnRoleFilterChanged()
	end)
	dpsCheck:SetPoint("LEFT", healerCheck.label, "RIGHT", 15, 0)
	dpsCheck:SetChecked(roleWidget and roleWidget.showDPS ~= false)

	return yOffset - 30
end

local function BuildUnitIndicatorsPage(parent, unit)
	local unitName = UnitNames[unit] or unit
	local header = CreatePageHeader(parent, unitName .. " 인디케이터", "아이콘 및 인디케이터 설정")

	local settings = ns.db[unit]
	if not settings then return end

	local yOffset = -60

	-- ===== Raid Icon ===== (모든 유닛)
	yOffset = BuildIndicatorBlock(parent, unit, "raidIcon", "공격대 아이콘", 16, yOffset)

	-- ===== Role / Leader / ReadyCheck / Resurrect / Summon ===== (party/raid)
	local isGroup = (unit == "party" or unit == "raid" or unit == "mythicRaid")
	if isGroup then
		yOffset = BuildIndicatorBlock(parent, unit, "roleIcon", "역할 아이콘", 14, yOffset)
		yOffset = BuildRoleFilterChecks(parent, unit, yOffset)
		yOffset = BuildIndicatorBlock(parent, unit, "leaderIcon", "파티장 아이콘", 14, yOffset)
		yOffset = BuildIndicatorBlock(parent, unit, "readyCheckIcon", "준비 확인", 20, yOffset)
		yOffset = BuildIndicatorBlock(parent, unit, "resurrectIcon", "부활", 20, yOffset)
		yOffset = BuildIndicatorBlock(parent, unit, "summonIcon", "소환", 20, yOffset)
	end

	-- ===== Combat / Resting ===== (player only)
	if unit == "player" then
		yOffset = BuildIndicatorBlock(parent, unit, "combatIcon", "전투 아이콘", 20, yOffset)

		-- 휴식 아이콘은 hideAtMaxLevel 추가 옵션이 있으므 별도 처리
		local restWidget = GetWidgetConfig(unit, "restingIcon")
		local restChildren = {}

		local restSep = Widgets:CreateSeparator(parent, "휴식 아이콘", CONTENT_WIDTH - 40)
		restSep:SetPoint("TOPLEFT", 15, yOffset)
		yOffset = yOffset - 35

		local restEnable = Widgets:CreateCheckButton(parent, "휴식 아이콘 표시", function(checked)
			SetWidgetValue(unit, "restingIcon", "enabled", checked)
			if ns.Update and ns.Update.UpdateIndicators then ns.Update:UpdateIndicators(unit) end
			RefreshCurrentPreview()
			SetChildrenEnabled(restChildren, checked)
		end)
		restEnable:SetPoint("TOPLEFT", 15, yOffset)
		restEnable:SetChecked(restWidget and restWidget.enabled)
		yOffset = yOffset - 30

		local hideMaxCheck = Widgets:CreateCheckButton(parent, "최대 레벨일 때 숨기기", function(checked)
			SetWidgetValue(unit, "restingIcon", "hideAtMaxLevel", checked)
			if ns.Update and ns.Update.UpdateIndicators then ns.Update:UpdateIndicators(unit) end
			RefreshCurrentPreview()
		end)
		hideMaxCheck:SetPoint("TOPLEFT", 15, yOffset)
		hideMaxCheck:SetChecked(restWidget and restWidget.hideAtMaxLevel ~= false)
		yOffset = yOffset - 35

		local restSizeSlider = Widgets:CreateSlider("크기", parent, 8, 40, 180, 1, nil, function(value)
			SetWidgetValue(unit, "restingIcon", "size.width", value)
			SetWidgetValue(unit, "restingIcon", "size.height", value)
			if ns.Update and ns.Update.UpdateIndicators then ns.Update:UpdateIndicators(unit) end
			RefreshCurrentPreview()
		end)
		restSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
		restSizeSlider:SetValue(restWidget and restWidget.size and restWidget.size.width or 18)
		yOffset = yOffset - 55

		local restPosEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
			SetWidgetValue(unit, "restingIcon", "position", pos)
			if ns.Update and ns.Update.UpdateIndicators then ns.Update:UpdateIndicators(unit) end
			RefreshCurrentPreview()
		end)
		restPosEditor:SetPoint("TOPLEFT", 15, yOffset)
		restPosEditor:SetPosition(restWidget and restWidget.position or { point = "TOPLEFT", relativePoint = "CENTER", offsetX = -15, offsetY = 10 })

		for _, c in ipairs({ hideMaxCheck, restSizeSlider, restPosEditor }) do
			restChildren[#restChildren + 1] = c
		end
		SetChildrenEnabled(restChildren, restWidget and restWidget.enabled)
		yOffset = yOffset - 130

		-- ===== Role / Leader ===== (player도 파티에서 보이므로)
		yOffset = BuildIndicatorBlock(parent, unit, "roleIcon", "역할 아이콘", 14, yOffset)
		yOffset = BuildRoleFilterChecks(parent, unit, yOffset)
		yOffset = BuildIndicatorBlock(parent, unit, "leaderIcon", "파티장 아이콘", 14, yOffset)
	end
	parent:SetHeight(math.abs(yOffset) + 50)
end

-- (Legacy BuildIconsPage / BuildRaidIndicatorsPage 제거됨 - BuildUnitIndicatorsPage로 통합)

-----------------------------------------------
-- Register Page Builders
-----------------------------------------------


-----------------------------------------------

-- [RESTORED] Classbar & Altpower
local function BuildUnitClassBarPage(parent, unit)
	if unit ~= "player" then 
		local noData = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		noData:SetText("직업 자원 및 보조 자원은 플레이어 프레임에서만 설정할 수 있습니다.")
		noData:SetPoint("CENTER", parent, "CENTER", 0, 0)
		return 
	end

	local header = CreatePageHeader(parent, "플레이어 직업 자원", "직업별 자원 바 설정")

	local settings = ns.db.player
	if not settings then return end
	local classBar = settings.widgets and settings.widgets.classBar

	local yOffset = -60

	local enableCheck = Widgets:CreateCheckButton(parent, "직업 자원 바 활성화", function(checked)
		if ns.db.player.widgets and ns.db.player.widgets.classBar then
			ns.db.player.widgets.classBar.enabled = checked
		end
		if ns.Update and ns.Update.UpdateClassBar then
			ns.Update:UpdateClassBar("player")
		end
	end)
	enableCheck:SetPoint("TOPLEFT", 15, yOffset)
	enableCheck:SetChecked(classBar and classBar.enabled)
	yOffset = yOffset - 35

	local heightSlider = Widgets:CreateSlider("높이", parent, 2, 20, 100, 1, nil, function(value)
		if ns.db.player.widgets and ns.db.player.widgets.classBar then
			if not ns.db.player.widgets.classBar.size then ns.db.player.widgets.classBar.size = {} end
			ns.db.player.widgets.classBar.size.height = value
		end
		if ns.Update and ns.Update.UpdateClassBar then
			ns.Update:UpdateClassBar("player")
		end
	end)
	heightSlider:SetPoint("TOPLEFT", 15, yOffset)
	heightSlider:SetValue(classBar and classBar.size and classBar.size.height or 6)

	local spacingSlider = Widgets:CreateSlider("간격", parent, 0, 10, 100, 1, nil, function(value)
		if ns.db.player.widgets and ns.db.player.widgets.classBar then
			ns.db.player.widgets.classBar.spacing = value
		end
		if ns.Update and ns.Update.UpdateClassBar then
			ns.Update:UpdateClassBar("player")
		end
	end)
	spacingSlider:SetPoint("LEFT", heightSlider, "RIGHT", 30, 0)
	spacingSlider:SetValue(classBar and classBar.spacing or 2)
	yOffset = yOffset - 55

	local hideOOCCheck = Widgets:CreateCheckButton(parent, "전투 중이 아닐 때 숨기기", function(checked)
		if ns.db.player.widgets and ns.db.player.widgets.classBar then
			ns.db.player.widgets.classBar.hideOutOfCombat = checked
		end
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	hideOOCCheck:SetPoint("TOPLEFT", 15, yOffset)
	hideOOCCheck:SetChecked(classBar and classBar.hideOutOfCombat)
	yOffset = yOffset - 35

	-- Same size as health bar
	local sameSizeCheck = Widgets:CreateCheckButton(parent, "체력바와 같은 너비", function(checked)
		SetWidgetValue("player", "classBar", "sameSizeAsHealthBar", checked)
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	sameSizeCheck:SetPoint("TOPLEFT", 15, yOffset)
	sameSizeCheck:SetChecked(classBar and classBar.sameSizeAsHealthBar ~= false)

	-- Vertical fill
	local verticalFillCheck = Widgets:CreateCheckButton(parent, "수직 채움", function(checked)
		SetWidgetValue("player", "classBar", "verticalFill", checked)
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	verticalFillCheck:SetPoint("LEFT", sameSizeCheck, "RIGHT", 150, 0)
	verticalFillCheck:SetChecked(classBar and classBar.verticalFill)
	yOffset = yOffset - 40

	-- Position
	local posSep = Widgets:CreateSeparator(parent, "위치", CONTENT_WIDTH - 40)
	posSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local classPosEditor = Widgets:CreatePositionEditor(parent, 350, function(pos)
		SetWidgetValue("player", "classBar", "position", pos)
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	classPosEditor:SetPoint("TOPLEFT", 15, yOffset)
	classPosEditor:SetPosition(classBar and classBar.position or { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", offsetX = 0, offsetY = 2 })
	yOffset = yOffset - 115

	-- Texture section
	local texSep = Widgets:CreateSeparator(parent, "텍스처", CONTENT_WIDTH - 40)
	texSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local texLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	texLabel:SetText("직업 자원 바 텍스처")
	texLabel:SetPoint("TOPLEFT", 15, yOffset)

	local texDropdown = Widgets:CreateDropdown(parent, 180)
	texDropdown:SetPoint("TOPLEFT", texLabel, "BOTTOMLEFT", 0, -5)
	texDropdown:SetItems(GetTextureList())
	texDropdown:SetOnSelect(function(value)
		SetWidgetValue("player", "classBar", "texture", value)
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	texDropdown:SetSelected(classBar and classBar.texture or [[Interface\\Buttons\\WHITE8x8]])
	yOffset = yOffset - 65

	-- Border section
	local borderSep = Widgets:CreateSeparator(parent, "테두리", CONTENT_WIDTH - 40)
	borderSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local borderEnable = Widgets:CreateCheckButton(parent, "테두리 표시", function(checked)
		SetWidgetValue("player", "classBar", "border.enabled", checked)
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	borderEnable:SetPoint("TOPLEFT", 15, yOffset)
	borderEnable:SetChecked(classBar and classBar.border and classBar.border.enabled ~= false)

	local borderSizeSlider = Widgets:CreateSlider("두께", parent, 0.1, 3, 80, 0.1, nil, function(value)
		SetWidgetValue("player", "classBar", "border.size", value)
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	borderSizeSlider:SetPoint("LEFT", borderEnable, "RIGHT", 120, 0)
	borderSizeSlider:SetValue(classBar and classBar.border and classBar.border.size or 1)
	yOffset = yOffset - 35

	local borderColorCP = Widgets:CreateColorPicker(parent, "테두리 색상", true, function(r, g, b, a)
		SetWidgetValue("player", "classBar", "border.color", { r, g, b, a })
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	borderColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local bCol = classBar and classBar.border and classBar.border.color or { 0, 0, 0, 1 }
	borderColorCP:SetColor(bCol[1], bCol[2], bCol[3], bCol[4] or 1)
	yOffset = yOffset - 35

	-- Background section
	local bgSep = Widgets:CreateSeparator(parent, "배경", CONTENT_WIDTH - 40)
	bgSep:SetPoint("TOPLEFT", 15, yOffset)
	yOffset = yOffset - 35

	local bgEnable = Widgets:CreateCheckButton(parent, "배경 표시", function(checked)
		SetWidgetValue("player", "classBar", "background.enabled", checked)
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	bgEnable:SetPoint("TOPLEFT", 15, yOffset)
	bgEnable:SetChecked(classBar and classBar.background and classBar.background.enabled ~= false)
	yOffset = yOffset - 30

	local bgColorCP = Widgets:CreateColorPicker(parent, "배경 색상", true, function(r, g, b, a)
		SetWidgetValue("player", "classBar", "background.color", { r, g, b, a })
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	bgColorCP:SetPoint("TOPLEFT", 15, yOffset)
	local bgCol = classBar and classBar.background and classBar.background.color or { 0.05, 0.05, 0.05, 0.8 }
	bgColorCP:SetColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.8)
	yOffset = yOffset - 35

	local cpBgTexLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	cpBgTexLabel:SetText("배경 텍스처")
	cpBgTexLabel:SetPoint("TOPLEFT", 15, yOffset)

	local cpBgTexDropdown = Widgets:CreateDropdown(parent, 180)
	cpBgTexDropdown:SetPoint("TOPLEFT", cpBgTexLabel, "BOTTOMLEFT", 0, -5)
	cpBgTexDropdown:SetItems(GetTextureList())
	cpBgTexDropdown:SetOnSelect(function(value)
		SetWidgetValue("player", "classBar", "background.texture", value)
		if ns.Update and ns.Update.UpdateClassBar then ns.Update:UpdateClassBar("player") end
	end)
	local cpBgTex = classBar and classBar.background and classBar.background.texture or [[Interface\\Buttons\\WHITE8x8]]
	cpBgTexDropdown:SetSelected(cpBgTex)
	parent:SetHeight(math.abs(yOffset) + 50)
end
-----------------------------------------------
-- Feature Routing System (DandersFrames Style)
-----------------------------------------------
-- [DandersFrames 스타일 카테고리/유닛 복사 기능]은 탭 내부에서 렌더링하도록 이관

local function BuildSharedFeaturePage(parent, groupType, featureFn)
	local tabs = (groupType == "personal") and PersonalTabs or GroupTabs
	
	local headerContainer = CreateFrame("Frame", nil, parent)
	headerContainer:SetSize(CONTENT_WIDTH - 20, 40)
	headerContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
	
	local titleLabel = headerContainer:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	titleLabel:SetPoint("LEFT", headerContainer, "LEFT", 5, 0)
	titleLabel:SetText((groupType == "personal") and "개인 설정 대상:" or "그룹 설정 대상:")
	titleLabel:SetTextColor(1, 0.82, 0)
	
	local dropdown = Widgets:CreateDropdown(headerContainer, 150)
	dropdown:SetPoint("LEFT", titleLabel, "RIGHT", 15, 0)
	dropdown:SetItems(tabs)
	
	local sep = headerContainer:CreateTexture(nil, "BACKGROUND")
	sep:SetPoint("TOPLEFT", headerContainer, "BOTTOMLEFT", 0, 0)
	sep:SetPoint("TOPRIGHT", headerContainer, "BOTTOMRIGHT", 0, 0)
	sep:SetHeight(1)
	sep:SetColorTexture(0.3, 0.3, 0.3, 0.5)

	-- 버튼 영역
	local btnContainer = CreateFrame("Frame", nil, headerContainer)
	btnContainer:SetSize(200, 24)
	btnContainer:SetPoint("RIGHT", headerContainer, "RIGHT", -5, 0)

	local copyBtn = Widgets:CreateButton(btnContainer, "다른 그룹으로 오버라이드", "accent", {180, 24})
	copyBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
	-- [CDM-STYLE] featureContainer: TOPLEFT+TOPRIGHT만 사용 (세로 앵커 충돌 없음)
	-- → featureFn 내부의 parent:SetHeight(N) 호출이 정상 작동
	local featureContainer = CreateFrame("Frame", nil, parent)
	featureContainer:SetPoint("TOPLEFT", headerContainer, "BOTTOMLEFT", 0, -10)
	featureContainer:SetPoint("TOPRIGHT", headerContainer, "BOTTOMRIGHT", 0, -10)
	
	-- [CDM-STYLE] SetHeight 후킹: 각 페이지(featureFn)의 정확한 높이 계산값을
	-- parent(contentFrame.content)에 안전하게 적용하고 GetBottom 자동 탐색을 스킵함.
	local origSetHeight = featureContainer.SetHeight
	featureContainer.SetHeight = function(self, h)
		origSetHeight(self, h)
		if h and h > 0 then
			parent:SetHeight(80 + h)
			parent._skipAutoHeight = true -- 자동 높이 탐색(버그 원인) 스킵 프래그
			if contentFrame and contentFrame.scrollFrame and contentFrame.scrollFrame.UpdateContentHeight then
				contentFrame.scrollFrame:UpdateContentHeight()
			end
		end
	end
	
	local function RenderFeature()
		local selectedUnit = TabSelections[groupType]
		
		-- 내부 렌더링 전 지우기
		for _, child in ipairs({ featureContainer:GetChildren() }) do
			child:Hide()
			child:SetParent(nil)
		end
		for _, region in ipairs({ featureContainer:GetRegions() }) do
			region:Hide()
			region:SetParent(nil)
		end
		
		-- 버튼 갱신
		if groupType == "group" and (selectedUnit == "party" or selectedUnit == "raid" or selectedUnit == "mythicRaid") then
			copyBtn:Show()
			local destUnit = (selectedUnit == "party") and "raid" or "party"
			local destName = UnitNames[destUnit] or destUnit
			
			copyBtn:SetText(destName .. " 설정으로 덮어쓰기")
			
			copyBtn:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(destName .. " 설정 복사")
				GameTooltip:AddLine("현재 탭의 설정을 " .. destName .. " 프레임으로 동일하게 복사합니다.\\n(DandersFrames 스타일 실시간 동기화)", 1, 1, 1, true)
				GameTooltip:Show()
			end)
			copyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
			
			copyBtn:SetScript("OnClick", function()
				local srcDB = ns.db[selectedUnit]
				local destDB = ns.db[destUnit]
				local copyFn = ns.Config and ns.Config.CopyDeep
				if not srcDB or not destDB or not copyFn then return end
				
				-- Copy logic based on current page feature
				local parts = { strsplit(".", currentPage) }
				local category = parts[2]
				
				if category == "general" then
					destDB.enabled = srcDB.enabled
					if srcDB.size then destDB.size = copyFn(srcDB.size) end
					destDB.showPlayer = srcDB.showPlayer
					destDB.showInRaid = srcDB.showInRaid
					destDB.anchorToParent = srcDB.anchorToParent
				elseif category == "layout" then
					if srcDB.position then destDB.position = copyFn(srcDB.position) end
					destDB.anchorPoint = srcDB.anchorPoint
					destDB.spacing = srcDB.spacing
					destDB.spacingX = srcDB.spacingX
					destDB.spacingY = srcDB.spacingY
					destDB.growth = srcDB.growth
					destDB.growDirection = srcDB.growDirection
					destDB.columnGrowDirection = srcDB.columnGrowDirection
					destDB.maxColumns = srcDB.maxColumns
					destDB.unitsPerColumn = srcDB.unitsPerColumn
					destDB.maxGroups = srcDB.maxGroups
					destDB.groupBy = srcDB.groupBy
					destDB.sortBy = srcDB.sortBy
					destDB.sortDir = srcDB.sortDir
					destDB.sortByRole = srcDB.sortByRole
				else
					if srcDB.widgets and destDB.widgets and srcDB.widgets[category] then
						destDB.widgets[category] = copyFn(srcDB.widgets[category])
					end
				end
				
				ns.Print((UnitNames[selectedUnit] or selectedUnit) .. "의 카테고리 설정을 " .. destName .. " 프레임에 동일하게 적용했습니다.")
				if ns.Update and ns.Update.RefreshAll then ns.Update:RefreshAll() end
				RenderFeature() -- 리프레쉬
			end)
		else
			copyBtn:Hide()
		end

		-- [CDM-STYLE] pre-expand → 위젯 배치 중 클리핑 방지
		parent:SetHeight(5000)

		-- featureFn 실행
		featureFn(featureContainer, selectedUnit)

		-- 네이티브 WoW 좌표 기반 다중 패스 높이 탐색 실행
		if contentFrame and contentFrame.scrollFrame and contentFrame.scrollFrame.UpdateContentHeightDelayed then
			contentFrame.scrollFrame:UpdateContentHeightDelayed(contentFrame)
		end
	end
	
	dropdown:SetOnSelect(function(value)
		TabSelections[groupType] = value
		RenderFeature()
	end)
	dropdown:SetSelected(TabSelections[groupType])
	
	RenderFeature()
end

-- Map personal pages
pageBuilders["personal.general"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitGeneralPage) end
pageBuilders["personal.health"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitHealthPage) end
pageBuilders["personal.power"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitPowerPage) end
pageBuilders["personal.castbar"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitCastBarPage) end
pageBuilders["personal.classbar"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitClassBarPage) end
pageBuilders["personal.altpower"] = function(p) BuildSharedFeaturePage(p, "personal", BuildAltPowerBarPage) end
pageBuilders["personal.buffs"] = function(p) BuildSharedFeaturePage(p, "personal", function(c, u) BuildUnitAurasPage(c, u, "buffs") end) end
pageBuilders["personal.debuffs"] = function(p) BuildSharedFeaturePage(p, "personal", function(c, u) BuildUnitAurasPage(c, u, "debuffs") end) end
pageBuilders["personal.defensives"] = function(p) BuildSharedFeaturePage(p, "personal", BuildDefensivesPage) end
pageBuilders["personal.privateauras"] = function(p) BuildSharedFeaturePage(p, "personal", BuildPrivateAurasPage) end
pageBuilders["personal.texts"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitTextsPage) end
pageBuilders["personal.indicators"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitIndicatorsPage) end
pageBuilders["personal.effects"] = function(p) BuildSharedFeaturePage(p, "personal", BuildThreatHighlightPage) end
pageBuilders["personal.fader"] = function(p) BuildSharedFeaturePage(p, "personal", BuildFaderPage) end
pageBuilders["personal.healprediction"] = function(p) BuildSharedFeaturePage(p, "personal", BuildHealPredictionPage) end
pageBuilders["personal.customtext"] = function(p) BuildSharedFeaturePage(p, "personal", BuildCustomTextPage) end

-- Map group pages
pageBuilders["group.general"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitGeneralPage) end
pageBuilders["group.layout"] = function(p) BuildSharedFeaturePage(p, "group", BuildGroupLayoutPage) end
pageBuilders["group.health"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitHealthPage) end
pageBuilders["group.power"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitPowerPage) end
pageBuilders["group.buffs"] = function(p) BuildSharedFeaturePage(p, "group", function(c, u) BuildUnitAurasPage(c, u, "buffs") end) end
pageBuilders["group.debuffs"] = function(p) BuildSharedFeaturePage(p, "group", function(c, u) BuildUnitAurasPage(c, u, "debuffs") end) end
pageBuilders["group.defensives"] = function(p) BuildSharedFeaturePage(p, "group", BuildDefensivesPage) end
pageBuilders["group.privateauras"] = function(p) BuildSharedFeaturePage(p, "group", BuildPrivateAurasPage) end
pageBuilders["group.indicators"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitIndicatorsPage) end
pageBuilders["group.texts"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitTextsPage) end
pageBuilders["group.debuffhighlight"] = function(p) BuildSharedFeaturePage(p, "group", BuildDebuffHighlightPage) end
pageBuilders["group.dispels"] = function(p) BuildSharedFeaturePage(p, "group", BuildDispelsPage) end
pageBuilders["group.fader"] = function(p) BuildSharedFeaturePage(p, "group", BuildFaderPage) end
pageBuilders["group.healprediction"] = function(p) BuildSharedFeaturePage(p, "group", BuildHealPredictionPage) end
pageBuilders["group.effects"] = function(p) BuildSharedFeaturePage(p, "group", BuildThreatHighlightPage) end
pageBuilders["group.customtext"] = function(p) BuildSharedFeaturePage(p, "group", BuildCustomTextPage) end

local HOT_SPEC_DISPLAY = {
	["RestorationDruid"] = "회복 드루이드",
	["PreservationEvoker"] = "보존 기원사",
	["HolyPaladin"] = "신성 성기사",
	["HolyPriest"] = "신성 사제",
	["DisciplinePriest"] = "수양 사제",
	["RestorationShaman"] = "복원 주술사",
	["MistweaverMonk"] = "운무 수도사",
}

local HOT_AURA_DISPLAY = {
	["Rejuvenation"] = "회복",
	["Lifebloom"] = "피어나는 생명",
	["Wild Growth"] = "급속 성장",
	["Regrowth"] = "재생",
	["Cenarion Ward"] = "세나리온 수호물",
	["Spring Blossoms"] = "봄꽃",
	["Dream Breath"] = "꿈의 숨결",
	["Reversion"] = "되감기",
	["Echo"] = "메아리",
	["Glimmer of Light"] = "빛의 자취",
	["Beacon of Light"] = "빛의 봉화",
	["Renew"] = "소생",
	["Atonement"] = "속죄",
	["Riptide"] = "성난 해일",
	["Earth Shield"] = "대지의 방패",
	["Enveloping Mist"] = "포용의 안개",
	["Renewing Mist"] = "소생의 안개",
	["Essence Font"] = "정수의 샘",
}

-- ===== HoT Tracker 유틸 함수 (Aura Designer에서 사용) =====
-- DB 경로: ns.db.party.widgets.hotTracker.auraSettings["SpecKey.AuraName"]

local function GetAuraCfg(specKey, auraName)
	local db = ns.db and ns.db.party
	local hotDB = db and db.widgets and db.widgets.hotTracker
	local auraSettings = hotDB and hotDB.auraSettings
	if auraSettings then
		local key = specKey .. "." .. auraName
		return auraSettings[key] or ns.AURA_DISPLAY_DEFAULTS or {}
	end
	return ns.AURA_DISPLAY_DEFAULTS or {}
end

local function EnsureAuraCfg(specKey, auraName)
	local db = ns.db and ns.db.party
	if not db then return {} end
	if not db.widgets then db.widgets = {} end
	if not db.widgets.hotTracker then db.widgets.hotTracker = {} end
	if not db.widgets.hotTracker.auraSettings then db.widgets.hotTracker.auraSettings = {} end
	local key = specKey .. "." .. auraName
	if not db.widgets.hotTracker.auraSettings[key] then
		local defaults = ns.AURA_DISPLAY_DEFAULTS or {}
		db.widgets.hotTracker.auraSettings[key] = {
			enabled = true,
			bar = defaults.bar and { enabled = defaults.bar.enabled, thickness = defaults.bar.thickness, color = { unpack(defaults.bar.color) } } or { enabled = false, thickness = 3, color = { 0.3, 0.85, 0.45, 0.8 } },
			gradient = defaults.gradient and { enabled = defaults.gradient.enabled, color = { unpack(defaults.gradient.color) }, alpha = defaults.gradient.alpha } or { enabled = false, color = { 0.3, 0.85, 0.45 }, alpha = 0.4 },
			healthColor = defaults.healthColor and { enabled = defaults.healthColor.enabled, color = { unpack(defaults.healthColor.color) } } or { enabled = false, color = { 0.3, 0.85, 0.45, 1 } },
			outline = defaults.outline and { enabled = defaults.outline.enabled, size = defaults.outline.size, color = { unpack(defaults.outline.color) } } or { enabled = false, size = 2, color = { 0.3, 0.85, 0.45, 1 } },
		}
	end
	return db.widgets.hotTracker.auraSettings[key]
end

local function SetAuraCfg(specKey, auraName, cfg)
	local db = ns.db and ns.db.party
	if not db or not db.widgets or not db.widgets.hotTracker or not db.widgets.hotTracker.auraSettings then return end
	local key = specKey .. "." .. auraName
	db.widgets.hotTracker.auraSettings[key] = cfg
end

local function HotRefreshAll()
	local GF = ns.GroupFrames
	if GF and GF.RefreshAllHotIndicators then
		GF:RefreshAllHotIndicators()
	end
end

pageBuilders["hottracker"] = function(parent)
	local header = CreatePageHeader(parent, "HoT 추적 (Aura Designer)", "힐러 HoT 버프를 아우라 디자이너 형태로 관리합니다")
	local yOffset = -60

	local GF = ns.GroupFrames
	local HotSpecData = ns.HotSpecData
	local defaults = ns.AURA_DISPLAY_DEFAULTS

	-- 현재 전문화 표시
	local specLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	specLabel:SetPoint("TOPLEFT", 15, yOffset)
	local curSpecKey = (GF and GF.GetPlayerSpecKey) and GF:GetPlayerSpecKey() or nil
	local specDisplay = curSpecKey and HOT_SPEC_DISPLAY[curSpecKey] or "감지 안 됨"
	specLabel:SetText("현재 전문화: |cff00ff00" .. specDisplay .. "|r")
	
	-- 전문화 선택 드롭다운
	local specList = {}
	if HotSpecData then
		for specKey in pairs(HotSpecData) do
			local display = HOT_SPEC_DISPLAY[specKey] or specKey
			table.insert(specList, { text = display, value = specKey })
		end
		table.sort(specList, function(a, b) return a.text < b.text end)
	end

	local selectedSpec = curSpecKey
	local selectedAura = nil

	local specDropdown
	if #specList > 0 then
		specDropdown = Widgets:CreateDropdown(parent, 200)
		specDropdown:SetPoint("LEFT", specLabel, "RIGHT", 30, 0)
		specDropdown:SetItems(specList)
		if selectedSpec and HotSpecData[selectedSpec] then
			specDropdown:SetSelected(selectedSpec)
		end
	end

	yOffset = yOffset - 40

	-- 메인 컨테이너
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(CONTENT_WIDTH - 30, 480)
	container:SetPoint("TOPLEFT", 15, yOffset)

	-- ===== 좌우 분할 패널 (DandersFrames Aura Designer 레이아웃) =====
	local leftPanel = CreateFrame("Frame", nil, container)
	leftPanel:SetSize(220, 480)
	leftPanel:SetPoint("TOPLEFT", 0, 0)

	local vSep = container:CreateTexture(nil, "BACKGROUND")
	vSep:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 5, 0)
	vSep:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 5, 0)
	vSep:SetWidth(1)
	vSep:SetColorTexture(0.3, 0.3, 0.3, 0.5)

	local rightPanel = CreateFrame("Frame", nil, container)
	rightPanel:SetPoint("TOPLEFT", vSep, "TOPRIGHT", 15, 0)
	rightPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

	local auraWidgets = {}
	local detailWidgets = {}
	
	local BuildAuraList, BuildDetailPanel

	local function ClearDetailWidgets()
		for _, w in ipairs(detailWidgets) do
			w:Hide()
			w:SetParent(nil)
		end
		wipe(detailWidgets)
	end

	-- ===== 우측: 개별 오라 상세 설정 패널 =====
	BuildDetailPanel = function(specKey, auraName)
		ClearDetailWidgets()
		if not auraName then return end

		local ac = EnsureAuraCfg(specKey, auraName)
		local displayName = HOT_AURA_DISPLAY[auraName] or auraName
		local dy = -10

		-- 제목 (우측 패널)
		local title = rightPanel:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		title:SetPoint("TOPLEFT", 10, dy)
		title:SetText("|cff00ff00" .. displayName .. "|r 상세 설정")
		table.insert(detailWidgets, title)

		local titleSep = Widgets:CreateSeparator(rightPanel, "", CONTENT_WIDTH - 280)
		titleSep:SetPoint("TOPLEFT", 10, dy - 20)
		table.insert(detailWidgets, titleSep)
		dy = dy - 40

		-- 1. 활성화 토글
		local enableCheck = Widgets:CreateCheckButton(rightPanel, "추적 활성화", function(checked)
			local ac2 = EnsureAuraCfg(specKey, auraName)
			ac2.enabled = checked
			SetAuraCfg(specKey, auraName, ac2)
			HotRefreshAll()
			BuildAuraList(specKey)
		end)
		enableCheck:SetPoint("TOPLEFT", 10, dy)
		enableCheck:SetChecked(ac.enabled ~= false)
		table.insert(detailWidgets, enableCheck)
		dy = dy - 45

		-- 2. 바 (남은 시간 막대)
		local barCheck = Widgets:CreateCheckButton(rightPanel, "바 (남은 시간 막대)", function(checked)
			if not ac.bar then ac.bar = { enabled = false, thickness = 3, color = { unpack(defaults.bar.color) } } end
			ac.bar.enabled = checked
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		barCheck:SetPoint("TOPLEFT", 10, dy)
		barCheck:SetChecked(ac.bar and ac.bar.enabled or false)
		table.insert(detailWidgets, barCheck)
		dy = dy - 30

		local barThickSlider = Widgets:CreateSlider("두께", rightPanel, 1, 8, 120, 1, nil, function(value)
			if not ac.bar then ac.bar = {} end
			ac.bar.thickness = value
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		barThickSlider:SetPoint("TOPLEFT", 30, dy)
		barThickSlider:SetValue(ac.bar and ac.bar.thickness or 3)
		table.insert(detailWidgets, barThickSlider)
		
		local barColorCP = Widgets:CreateColorPicker(rightPanel, "바 색상", true, function(r, g, b, a)
			if not ac.bar then ac.bar = {} end
			ac.bar.color = { r, g, b, a }
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		barColorCP:SetPoint("LEFT", barThickSlider, "RIGHT", 40, -10)
		local bc = ac.bar and ac.bar.color or defaults.bar.color
		barColorCP:SetColor(bc[1], bc[2], bc[3], bc[4] or 0.8)
		table.insert(detailWidgets, barColorCP)
		dy = dy - 55

		-- 3. 그라데이션 (프레임 오버레이)
		local gradCheck = Widgets:CreateCheckButton(rightPanel, "그라데이션 (프레임 오버레이)", function(checked)
			if not ac.gradient then ac.gradient = { enabled = false, color = { unpack(defaults.gradient.color) }, alpha = defaults.gradient.alpha } end
			ac.gradient.enabled = checked
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		gradCheck:SetPoint("TOPLEFT", 10, dy)
		gradCheck:SetChecked(ac.gradient and ac.gradient.enabled or false)
		table.insert(detailWidgets, gradCheck)
		dy = dy - 30

		local gradAlphaSlider = Widgets:CreateSlider("투명도", rightPanel, 0.1, 1.0, 120, 0.05, nil, function(value)
			if not ac.gradient then ac.gradient = {} end
			ac.gradient.alpha = value
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		gradAlphaSlider:SetPoint("TOPLEFT", 30, dy)
		gradAlphaSlider:SetValue(ac.gradient and ac.gradient.alpha or defaults.gradient.alpha or 0.4)
		table.insert(detailWidgets, gradAlphaSlider)

		local gradCP = Widgets:CreateColorPicker(rightPanel, "그라데이션 색상", false, function(r, g, b)
			if not ac.gradient then ac.gradient = {} end
			ac.gradient.color = { r, g, b }
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		gradCP:SetPoint("LEFT", gradAlphaSlider, "RIGHT", 40, -10)
		local gc = ac.gradient and ac.gradient.color or defaults.gradient.color or { 0.3, 0.85, 0.45 }
		gradCP:SetColor(gc[1], gc[2], gc[3], 1)
		table.insert(detailWidgets, gradCP)
		dy = dy - 55

		-- 4. 체력바 색상
		local hcCheck = Widgets:CreateCheckButton(rightPanel, "체력바 전체 색상 오버라이드", function(checked)
			if not ac.healthColor then ac.healthColor = { enabled = false, color = { unpack(defaults.healthColor.color) } } end
			ac.healthColor.enabled = checked
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		hcCheck:SetPoint("TOPLEFT", 10, dy)
		hcCheck:SetChecked(ac.healthColor and ac.healthColor.enabled or false)
		table.insert(detailWidgets, hcCheck)
		dy = dy - 30

		local hcCP = Widgets:CreateColorPicker(rightPanel, "적용될 체력바 색상", true, function(r, g, b, a)
			if not ac.healthColor then ac.healthColor = {} end
			ac.healthColor.color = { r, g, b, a }
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		hcCP:SetPoint("TOPLEFT", 30, dy)
		local hcC = ac.healthColor and ac.healthColor.color or defaults.healthColor.color
		hcCP:SetColor(hcC[1], hcC[2], hcC[3], hcC[4] or 1)
		table.insert(detailWidgets, hcCP)
		dy = dy - 45

		-- 5. 외곽선
		local outCheck = Widgets:CreateCheckButton(rightPanel, "외곽선 (프레임 테두리 하이라이트)", function(checked)
			if not ac.outline then ac.outline = { enabled = false, size = 2, color = { unpack(defaults.outline.color) } } end
			ac.outline.enabled = checked
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		outCheck:SetPoint("TOPLEFT", 10, dy)
		outCheck:SetChecked(ac.outline and ac.outline.enabled or false)
		table.insert(detailWidgets, outCheck)
		dy = dy - 30

		local outSizeSlider = Widgets:CreateSlider("두께", rightPanel, 1, 5, 120, 1, nil, function(value)
			if not ac.outline then ac.outline = {} end
			ac.outline.size = value
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		outSizeSlider:SetPoint("TOPLEFT", 30, dy)
		outSizeSlider:SetValue(ac.outline and ac.outline.size or 2)
		table.insert(detailWidgets, outSizeSlider)

		local outCP = Widgets:CreateColorPicker(rightPanel, "외곽선 색상", true, function(r, g, b, a)
			if not ac.outline then ac.outline = {} end
			ac.outline.color = { r, g, b, a }
			SetAuraCfg(specKey, auraName, ac)
			HotRefreshAll()
		end)
		outCP:SetPoint("LEFT", outSizeSlider, "RIGHT", 40, -10)
		local oc = ac.outline and ac.outline.color or defaults.outline.color
		outCP:SetColor(oc[1], oc[2], oc[3], oc[4] or 1)
		table.insert(detailWidgets, outCP)
	end
	
	-- ===== 좌측: 오라 목록 =====
	local function ClearAuraWidgets()
		for _, w in ipairs(auraWidgets) do
			w:Hide()
			w:SetParent(nil)
		end
		wipe(auraWidgets)
	end

	BuildAuraList = function(specKey)
		ClearAuraWidgets()
		if not HotSpecData or not HotSpecData[specKey] then return end

		local specData = HotSpecData[specKey]
		local ay = -10

		local listTitle = leftPanel:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		listTitle:SetPoint("TOPLEFT", 5, ay)
		listTitle:SetText("디자이너 목록")
		listTitle:SetTextColor(1, 0.82, 0)
		table.insert(auraWidgets, listTitle)
		ay = ay - 30

		local sortedBuffs = {}
		for buffName in pairs(specData.auras) do
			table.insert(sortedBuffs, buffName)
		end
		table.sort(sortedBuffs)

		local buffButtons = {}
		for _, buffName in ipairs(sortedBuffs) do
			local auraCfg = GetAuraCfg(specKey, buffName)
			local displayName = HOT_AURA_DISPLAY[buffName] or buffName
			local isEnabled = (auraCfg.enabled ~= false)

			local btn = Widgets:CreateButton(leftPanel, displayName, "transparent", { 200, 24 })
			btn:SetPoint("TOPLEFT", 5, ay)
			
			-- 현재 선택 중인 상태 시각적 피드백
			local fs = btn:GetFontString()
			if selectedAura == buffName then
				btn:SetBackdropColor(0.2, 0.6, 0.2, 0.6)
				if fs then fs:SetTextColor(0, 1, 0, 1) end
			else
				if fs then
					if isEnabled then
						fs:SetTextColor(1, 1, 1, 1)
					else
						fs:SetTextColor(0.5, 0.5, 0.5, 1)
					end
				end
			end

			btn:SetScript("OnClick", function()
				selectedAura = buffName
				BuildAuraList(specKey)
				BuildDetailPanel(specKey, buffName)
			end)
			
			-- ON/OFF 배지
			local statusFS = btn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
			statusFS:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
			if isEnabled then
				statusFS:SetText("|cff00ff00ON|r")
			else
				statusFS:SetText("|cff888888OFF|r")
			end
			
			table.insert(auraWidgets, btn)
			table.insert(buffButtons, btn)
			ay = ay - 26
		end

		ay = ay - 10
		local allOnBtn = Widgets:CreateButton(leftPanel, "모조리 켜기", "accent", { 95, 22 })
		allOnBtn:SetPoint("TOPLEFT", 5, ay)
		allOnBtn:SetScript("OnClick", function()
			for _, buffName in ipairs(sortedBuffs) do
				local ac = EnsureAuraCfg(specKey, buffName)
				ac.enabled = true
				SetAuraCfg(specKey, buffName, ac)
			end
			HotRefreshAll()
			BuildAuraList(specKey)
			if selectedAura then BuildDetailPanel(specKey, selectedAura) end
		end)
		table.insert(auraWidgets, allOnBtn)

		local allOffBtn = Widgets:CreateButton(leftPanel, "모조리 끄기", "red", { 95, 22 })
		allOffBtn:SetPoint("LEFT", allOnBtn, "RIGHT", 10, 0)
		allOffBtn:SetScript("OnClick", function()
			for _, buffName in ipairs(sortedBuffs) do
				local ac = EnsureAuraCfg(specKey, buffName)
				ac.enabled = false
				SetAuraCfg(specKey, buffName, ac)
			end
			HotRefreshAll()
			BuildAuraList(specKey)
			if selectedAura then BuildDetailPanel(specKey, selectedAura) end
		end)
		table.insert(auraWidgets, allOffBtn)
	end
	
	if specDropdown then
		specDropdown:SetOnSelect(function(value)
			selectedSpec = value
			selectedAura = nil
			ClearDetailWidgets()
			BuildAuraList(value)
			
			-- 첫 번째 오라 자동 선택 (전문화 변경 시)
			if HotSpecData and HotSpecData[selectedSpec] then
				local sortedBuffs = {}
				for buffName in pairs(HotSpecData[selectedSpec].auras) do
					table.insert(sortedBuffs, buffName)
				end
				table.sort(sortedBuffs)
				if #sortedBuffs > 0 then
					selectedAura = sortedBuffs[1]
					BuildAuraList(selectedSpec)
					BuildDetailPanel(selectedSpec, selectedAura)
				end
			end
		end)
	end

	-- 초기 빌드
	if selectedSpec then
		-- 첫 번째 오라 자동 선택
		local sortedBuffs = {}
		if HotSpecData and HotSpecData[selectedSpec] then
			for buffName in pairs(HotSpecData[selectedSpec].auras) do
				table.insert(sortedBuffs, buffName)
			end
			table.sort(sortedBuffs)
			if #sortedBuffs > 0 and not selectedAura then
				selectedAura = sortedBuffs[1]
			end
		end
		
		BuildAuraList(selectedSpec)
		if selectedAura then
			BuildDetailPanel(selectedSpec, selectedAura)
		end
	end
	
	parent:SetHeight(math.abs(yOffset) + 550)
end

-----------------------------------------------
-- Search System (카테고리 검색)
-----------------------------------------------
-- LoadPage, ShowTagReference, HideTagReference는 파일 상단에서 forward declaration됨
local searchIndex = nil
local searchMode = false
local preSearchPage = nil
local searchDebounceTimer = nil
local searchWidgets = {}

-- categoryData 전체를 평탄화하여 검색 인덱스 생성
-- [REFACTOR] 카테고리별 위젯 라벨 키워드 맵 (pageBuilder 내부 위젯 라벨 검색용)
local PAGE_KEYWORDS = {
	-- 일반 페이지
	colors = { "색상", "사망 시 색상", "오프라인 시 색상", "정수 색상", "자원바 색상", "클래스 색상", "반응 색상", "배경 색상", "초과 치유", "보호막", "치유 흡수" },
	modules = { "모듈", "활성화", "자원바", "시전바", "버프", "디버프", "치유 예측", "하이라이트", "위협", "경고 색상", "기본 색상", "텍스처" },
	media = { "폰트", "텍스처", "글꼴", "상태바" },
	layout = { "레이아웃", "크기", "너비", "높이", "간격", "방향" },
	-- 유닛별 페이지
	general = { "크기", "너비", "높이", "테두리", "테두리 색상", "테두리 두께", "배경 색상", "활성화", "프레임 레벨" },
	health = { "체력", "색상", "사용자 정의 색상", "손실 체력 색상", "클래스 색상", "반응 색상", "텍스처", "방향" },
	power = { "자원", "자원바", "색상", "사용자 지정 색상", "높이", "텍스처", "활성화", "분리", "자원 타입" },
	castbar = { "시전바", "캐스트바", "색상", "차단 가능 색상", "차단 불가 색상", "높이", "아이콘", "타이머", "배경", "텍스처" },
	buffs = { "버프", "크기", "간격", "갯수", "성장 방향", "필터", "내 버프만", "레이드 버프", "시너지", "인내", "전투 외침", "지속시간", "중첩", "글꼴", "아웃라인", "기준점", "색상 모드", "그라데이션" },
	debuffs = { "디버프", "크기", "간격", "갯수", "성장 방향", "필터", "해제 가능", "지속시간", "중첩", "글꼴", "아웃라인", "기준점", "색상 모드", "그라데이션" },
	defensives = { "생존기", "외생기", "외부 생존기", "개인 생존기", "크기", "간격", "아이콘", "지속시간", "중첩", "글꼴", "아웃라인", "기준점", "색상 모드", "그라데이션" },
	privateauras = { "프라이빗 오라", "비공개 오라", "블리자드 오라", "보스 메커닉" },
	texts = { "텍스트", "이름", "체력", "자원", "색상", "이름 색상", "체력 텍스트 색상", "자원 색상", "폰트", "크기", "형식", "위치" },
	healprediction = { "치유 예측", "텍스처", "초과 치유", "치유 흡수", "보호막", "초과 보호막", "채움 반전" },
	icons = { "아이콘", "레이드 아이콘", "역할 아이콘", "리더 아이콘", "전투 아이콘", "휴식 아이콘", "부활 아이콘", "소환 아이콘", "준비 확인", "크기", "위치" },
	effects = { "효과", "하이라이트", "대상 색상", "마우스오버 색상", "위협", "색상" },
	fader = { "페이더", "투명도", "전투", "마우스오버" },
	classbar = { "클래스 자원", "특성 자원", "테두리 색상", "배경 색상", "크기", "높이", "너비", "간격" },
	customtext = { "사용자 정의 텍스트", "커스텀 텍스트", "색상", "태그", "폰트" },
	indicators = { "표시기", "아이콘", "역할", "준비 확인", "크기", "위치" },
	dispels = { "해제", "디스펠", "하이라이트", "색상" },
	grouplayout = { "그룹 레이아웃", "방향", "간격", "정렬", "그룹당 인원" },
	-- HoT 트래커 검색 키워드
	["hottracker"] = { "HoT", "핫", "추적", "버프", "텍스트", "바", "그라데이션", "체력바 색상", "외곽선", "전문화", "드루이드", "기원사", "성기사", "사제", "수도사", "주술사" },
}

local function BuildSearchIndex()
	local index = {}

	local function indexRecursive(items, breadcrumbParts)
		for _, item in ipairs(items) do
			if item.children and #item.children > 0 then
				local newParts = {}
				for _, p in ipairs(breadcrumbParts) do
					newParts[#newParts + 1] = p
				end
				newParts[#newParts + 1] = item.text
				indexRecursive(item.children, newParts)
			else
				-- Leaf node → 검색 대상
				local breadcrumb = table.concat(breadcrumbParts, "  >  ")
				local parentPath = table.concat(breadcrumbParts, ".")

				-- pageType 추출 (마지막 dot 이후)
				local keywords = { item.text:lower() }
				local parts = { strsplit(".", item.id) }
				local pageType = parts[#parts]

				-- PAGE_KEYWORDS에서 위젯 라벨 키워드 추가
				local pageKW = PAGE_KEYWORDS[pageType]
				if pageKW then
					for _, kw in ipairs(pageKW) do
						keywords[#keywords + 1] = kw:lower()
					end
				end

				-- WidgetNames에서 추가 키워드
				for wKey, wName in pairs(WidgetNames) do
					local wKeyLower = wKey:lower()
					if pageType == wKeyLower
						or (pageType == "texts" and (wKeyLower == "nametext" or wKeyLower == "healthtext" or wKeyLower == "powertext" or wKeyLower == "leveltext"))
						or (pageType == "icons" and (wKeyLower == "raidicon" or wKeyLower == "roleicon" or wKeyLower == "leadericon" or wKeyLower == "combaticon"))
					then
						keywords[#keywords + 1] = wName:lower()
					end
				end

				index[#index + 1] = {
					name = item.text,
					nameLower = item.text:lower(),
					categoryId = item.id,
					breadcrumb = breadcrumb,
					parentPath = parentPath,
					keywords = keywords,
				}
			end
		end
	end

	indexRecursive(categoryData, {})
	return index
end

-- 검색 결과 위젯 정리
local function ClearSearchWidgets()
	for i = #searchWidgets, 1, -1 do
		local w = searchWidgets[i]
		if w then w:Hide(); w:SetParent(nil) end
	end
	wipe(searchWidgets)
end

-- Breadcrumb badge 생성 (클릭 → 해당 카테고리로 이동)
local function CreateSearchBadge(parent, text, yOffset, onClick)
	local SL = ns.StyleLib
	local FLAT = SL and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
	local accentColor = SL and SL.GetAccent("UnitFrames") or { 0.30, 0.85, 0.45 }
	local dimColor = SL and SL.Colors.text.dim or { 0.45, 0.45, 0.45 }
	local widgetBg = SL and SL.Colors.bg.widget or { 0.14, 0.14, 0.14, 0.9 }

	local badge = CreateFrame("Button", nil, parent, "BackdropTemplate")
	badge:SetBackdrop({
		bgFile = FLAT,
		edgeFile = FLAT,
		edgeSize = 1,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	badge:SetBackdropColor(widgetBg[1], widgetBg[2], widgetBg[3], widgetBg[4] or 0.9)
	badge:SetBackdropBorderColor(0, 0, 0, 1)

	local fs = badge:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	fs:SetText(text)
	fs:SetTextColor(dimColor[1], dimColor[2], dimColor[3], 1)
	fs:SetPoint("LEFT", 8, 0)
	badge._text = fs

	local textWidth = fs:GetStringWidth() or 80
	badge:SetSize(textWidth + 16, 20)
	badge:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)

	badge:SetScript("OnEnter", function(self)
		self._text:SetTextColor(accentColor[1], accentColor[2], accentColor[3], 1)
		self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
	end)
	badge:SetScript("OnLeave", function(self)
		self._text:SetTextColor(dimColor[1], dimColor[2], dimColor[3], 1)
		self:SetBackdropBorderColor(0, 0, 0, 1)
	end)

	if onClick then
		badge:SetScript("OnClick", onClick)
	end

	return badge
end

-- 검색 결과를 콘텐츠 영역에 렌더링
local function RenderSearchResults(parent, results, treeViewRef, searchBoxRef)
	ClearSearchWidgets()

	local SL = ns.StyleLib
	local accentColor = SL and SL.GetAccent("UnitFrames") or { 0.30, 0.85, 0.45 }
	local dimColor = SL and SL.Colors.text.dim or { 0.45, 0.45, 0.45 }
	local yOffset = 15

	-- 헤더
	local headerFrame = CreateFrame("Frame", nil, parent)
	headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
	headerFrame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
	headerFrame:SetHeight(28)
	searchWidgets[#searchWidgets + 1] = headerFrame

	local headerText = headerFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	headerText:SetPoint("TOPLEFT", 0, 0)

	if #results > 0 then
		headerText:SetText("검색 결과  |cff999999(" .. #results .. "개 발견)|r")
	else
		headerText:SetText("|cff999999검색 결과 없음|r")
	end

	-- 밑줄 그라데이션
	local FLAT = SL and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
	local underline = headerFrame:CreateTexture(nil, "ARTWORK")
	underline:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -4)
	underline:SetPoint("RIGHT", headerFrame, "RIGHT", 0, 0)
	underline:SetHeight(1)
	underline:SetTexture(FLAT)
	underline:SetGradient("HORIZONTAL",
		CreateColor(accentColor[1], accentColor[2], accentColor[3], 0.6),
		CreateColor(dimColor[1], dimColor[2], dimColor[3], 0.15)
	)

	yOffset = yOffset + 36

	if #results == 0 then
		parent:SetHeight(yOffset + 50)
		return
	end

	-- parentPath로 그룹화
	local groups = {}
	local groupOrder = {}
	for _, entry in ipairs(results) do
		if not groups[entry.parentPath] then
			groups[entry.parentPath] = {
				breadcrumb = entry.breadcrumb,
				items = {},
			}
			groupOrder[#groupOrder + 1] = entry.parentPath
		end
		table.insert(groups[entry.parentPath].items, entry)
	end

	-- 각 그룹 렌더링
	for _, pathKey in ipairs(groupOrder) do
		local group = groups[pathKey]

		-- 첫 항목의 categoryId로 네비게이션 (그룹 내 첫 리프)
		local firstCatId = group.items[1].categoryId

		local badge = CreateSearchBadge(parent, group.breadcrumb, yOffset, function()
			-- 검색 모드 해제
			searchMode = false
			preSearchPage = nil
			-- 검색 박스 비우기
			if searchBoxRef then
				searchBoxRef:Clear()
				searchBoxRef.editBox:ClearFocus()
			end
			-- 해당 카테고리로 이동
			if treeViewRef then
				treeViewRef:SelectCategory(firstCatId)
			end
		end)
		searchWidgets[#searchWidgets + 1] = badge
		yOffset = yOffset + 24

		-- 그룹 내 각 항목 (카테고리 페이지 이름)
		for _, entry in ipairs(group.items) do
			local itemBtn = CreateFrame("Button", nil, parent)
			itemBtn:SetHeight(22)
			itemBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 26, -yOffset)
			itemBtn:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
			searchWidgets[#searchWidgets + 1] = itemBtn

			local bullet = itemBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
			bullet:SetText("|cff666666•|r  " .. entry.name)
			bullet:SetPoint("LEFT", 0, 0)
			bullet:SetJustifyH("LEFT")

			itemBtn:SetScript("OnEnter", function()
				bullet:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
			end)
			itemBtn:SetScript("OnLeave", function()
				bullet:SetTextColor(1, 1, 1)
			end)
			itemBtn:SetScript("OnClick", function()
				searchMode = false
				preSearchPage = nil
				if searchBoxRef then
					searchBoxRef:Clear()
					searchBoxRef.editBox:ClearFocus()
				end
				if treeViewRef then
					treeViewRef:SelectCategory(entry.categoryId)
				end
			end)

			yOffset = yOffset + 22
		end

		yOffset = yOffset + 8 -- 그룹 간 여백
	end

	-- 스크롤 높이 업데이트
	parent:SetHeight(yOffset + 50)
end

-- 검색 실행
local function PerformSearch(query, treeViewRef, searchBoxRef)
	if not searchIndex then
		searchIndex = BuildSearchIndex()
	end

	local queryLower = query:lower()
	local results = {}

	for _, entry in ipairs(searchIndex) do
		local matched = false
		-- 이름 매칭
		if entry.nameLower:find(queryLower, 1, true) then
			matched = true
		end
		-- 키워드 매칭 (WidgetNames)
		if not matched and entry.keywords then
			for _, kw in ipairs(entry.keywords) do
				if kw:find(queryLower, 1, true) then
					matched = true
					break
				end
			end
		end
		-- 경로 매칭
		if not matched and entry.breadcrumb then
			if entry.breadcrumb:lower():find(queryLower, 1, true) then
				matched = true
			end
		end
		if matched then
			results[#results + 1] = entry
		end
	end

	-- 검색 모드 진입
	if not searchMode then
		preSearchPage = currentPage
		searchMode = true
	end

	-- 콘텐츠 영역 정리 후 검색 결과 렌더링
	ClearContent()
	HideTagReference()

	if contentFrame and contentFrame.content then
		RenderSearchResults(contentFrame.content, results, treeViewRef, searchBoxRef)
		-- 스크롤 초기화
		if contentFrame.scrollFrame then
			contentFrame.scrollFrame:SetVerticalScroll(0)
			C_Timer.After(0.05, function()
				if contentFrame.scrollFrame and contentFrame.scrollFrame.UpdateContentHeight then
					contentFrame.scrollFrame:UpdateContentHeight()
				end
			end)
		end
	end
end

-- 검색 해제 (이전 페이지 복원)
local function ClearSearch()
	if not searchMode then return end
	searchMode = false

	ClearSearchWidgets()

	if preSearchPage then
		LoadPage(preSearchPage)
		preSearchPage = nil
	end
end

-----------------------------------------------
-- Load Page
-----------------------------------------------

LoadPage = function(categoryId)
	if not contentFrame or not contentFrame.content then
		ns.Debug("LoadPage: contentFrame nil for", categoryId)
		return
	end

	-- Only load if page builder exists
	local builder = pageBuilders[categoryId]
	if not builder then
		ns.Debug("LoadPage: no builder for", categoryId)
		return
	end
	ns.Debug("LoadPage:", categoryId)

	-- 커스텀 텍스트 페이지면 태그 레퍼런스 패널 표시
	local unit = GetUnitFromCategory(categoryId)
	if categoryId:find("%.customtext$") then
		ShowTagReference()
	else
		HideTagReference()
	end

	ClearContent()
	builder(contentFrame.content)
	currentPage = categoryId

	-- 스크롤 초기화 및 컨텐츠 높이 자동 계산 (CDM 패턴: 1회 지연 계산)
	if contentFrame.scrollFrame then
		contentFrame.scrollFrame:ResetScroll()
		C_Timer.After(0.1, function()
			if contentFrame.scrollFrame and contentFrame.scrollFrame.UpdateContentHeight then
				contentFrame.scrollFrame:UpdateContentHeight()
			end
		end)
	end
end

-----------------------------------------------
-- Tag Reference Panel (커스텀 텍스트 메뉴 진입 시 오른쪽에 표시)
-----------------------------------------------
local mainFrame = nil  -- forward declaration (CreateOptionsPanel에서 할당)
local tagRefPanel = nil

local TAG_REF_WIDTH = 280
local TAG_REF_SECTIONS = {
	{ title = "이름", tags = {
		{ "[ddingui:name]", "풀네임" },
		{ "[ddingui:name:short]", "짧은 이름 (8자)" },
		{ "[ddingui:name:medium]", "중간 이름 (14자)" },
		{ "[ddingui:name:raid]", "레이드용 (6자)" },
		{ "[ddingui:name:veryshort]", "매우 짧은 (4자)" },
		{ "[ddingui:name:abbrev]", "약칭" },
		{ "[ddingui:name:role]", "역할아이콘 + 이름" },
	}},
	{ title = "체력", tags = {
		{ "[ddingui:health]", "스마트 (풀이면 이름)" },
		{ "[ddingui:health:db]", "DB 형식 자동" },
		{ "[ddingui:health:percent]", "퍼센트 (100% 숨김)" },
		{ "[ddingui:health:percent-full]", "퍼센트 (항상 표시)" },
		{ "[ddingui:health:current]", "현재값" },
		{ "[ddingui:health:max]", "최대값" },
		{ "[ddingui:health:current-max]", "현재 / 최대" },
		{ "[ddingui:health:current-percent]", "현재 | 퍼센트" },
		{ "[ddingui:health:deficit]", "감소량" },
		{ "[ddingui:health:raid]", "레이드 (100% 숨김)" },
		{ "[ddingui:health:healeronly]", "힐러전용 감소량" },
		{ "[ddingui:health:absorb]", "현재 + 보호막" },
	}},
	{ title = "자원", tags = {
		{ "[ddingui:power]", "자원 현재값" },
		{ "[ddingui:power:percent]", "자원 퍼센트" },
		{ "[ddingui:power:current-max]", "자원 / 최대" },
		{ "[ddingui:power:deficit]", "자원 감소량" },
		{ "[ddingui:power:healeronly]", "힐러전용 자원" },
	}},
	{ title = "보호막 / 흡수 / 힐", tags = {
		{ "[ddingui:absorb]", "보호막 (피해흡수)" },
		{ "[ddingui:absorb:percent]", "보호막 퍼센트" },
		{ "[ddingui:healabsorb]", "힐 흡수 (괴사일격 등)" },
		{ "[ddingui:incheal]", "수신 힐량" },
	}},
	{ title = "색상 (앞에 붙이고 |r로 종료)", tags = {
		{ "[ddingui:classcolor]", "직업 색상" },
		{ "[ddingui:healthcolor]", "체력비율 색상" },
		{ "[ddingui:powercolor]", "자원타입 색상" },
		{ "[ddingui:reactioncolor]", "우호/적대 색상" },
	}},
	{ title = "상태 / 레벨 / 분류", tags = {
		{ "[ddingui:status]", "죽음/오프라인/AFK" },
		{ "[ddingui:level]", "레벨" },
		{ "[ddingui:level:smart]", "스마트레벨 (보스/엘리트)" },
		{ "[ddingui:classification]", "+/R/B 분류" },
	}},
	{ title = "oUF 빌트인", tags = {
		{ "[name]", "이름" },
		{ "[perhp]", "체력%" },
		{ "[perpp]", "자원%" },
		{ "[curhp]", "현재체력 (raw)" },
		{ "[maxhp]", "최대체력" },
		{ "[missinghp]", "부족체력" },
		{ "[curpp] / [maxpp]", "자원" },
		{ "[level]", "레벨" },
		{ "[dead]", "죽음" },
		{ "[offline]", "오프라인" },
		{ "[threat]", "위협" },
		{ "[raidcolor]", "직업색" },
		{ "[powercolor]", "자원색" },
	}},
	{ title = "조합 예시", tags = {
		{ "[ddingui:classcolor][ddingui:name:medium]|r", "직업색 이름" },
		{ "[ddingui:healthcolor][ddingui:health:percent]|r", "체력색 퍼센트" },
		{ "[ddingui:health:current] ([ddingui:absorb])", "체력 (보호막)" },
	}},
}

local function CreateTagReferencePanel()
	if tagRefPanel then return tagRefPanel end

	local SL = ns.StyleLib

	tagRefPanel = CreateFrame("Frame", "ddingUI_UF_TagRef", UIParent, "BackdropTemplate")
	tagRefPanel:SetSize(TAG_REF_WIDTH, PANEL_HEIGHT)
	tagRefPanel:SetFrameStrata("DIALOG")
	tagRefPanel:SetFrameLevel(100)
	tagRefPanel:EnableMouse(true)
	tagRefPanel:Hide()

	Widgets:StylizeFrame(tagRefPanel, SL and SL.Colors.bg.main or { 0.1, 0.1, 0.1, 0.95 })

	-- Title bar
	local titleBar = CreateFrame("Frame", nil, tagRefPanel, "BackdropTemplate")
	titleBar:SetHeight(TOPBAR_HEIGHT)
	titleBar:SetPoint("TOPLEFT", 0, 0)
	titleBar:SetPoint("TOPRIGHT", 0, 0)
	Widgets:StylizeFrame(titleBar, SL and SL.Colors.bg.titlebar or { 0.12, 0.12, 0.12, 0.98 })

	-- Accent line
	if SL then
		local from, to = SL.GetAccent("UnitFrames")
		local accentLine = SL.CreateHorizontalGradient(titleBar, from, to, 2, "OVERLAY")
		accentLine:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
		accentLine:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 0, 0)
	end

	local titleText = titleBar:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_TITLE")
	if SL then
		titleText:SetText(SL.CreateAddonTitle("UnitFrames", "태그 레퍼런스")) -- [STYLE]
	else
		titleText:SetText("태그 레퍼런스")
	end
	titleText:SetPoint("LEFT", 10, 0)

	-- Copy EditBox (상단 고정, 클릭한 태그가 여기에 표시됨)
	local copyBox = CreateFrame("EditBox", nil, tagRefPanel, "BackdropTemplate")
	copyBox:SetSize(TAG_REF_WIDTH - 16, 22)
	copyBox:SetPoint("TOPLEFT", 8, -(TOPBAR_HEIGHT + 6))
	copyBox:SetAutoFocus(false)
	copyBox:SetFontObject("DDINGUI_UF_FONT_NORMAL")
	copyBox:SetTextColor(0.5, 0.82, 1)
	copyBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	copyBox:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
	copyBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)
	copyBox:SetTextInsets(6, 6, 0, 0)
	copyBox:SetText("태그를 클릭하면 여기에 복사됩니다")
	copyBox:SetCursorPosition(0)
	copyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	copyBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	tagRefPanel._copyBox = copyBox

	-- 안내 텍스트
	local hintText = tagRefPanel:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	hintText:SetPoint("TOPLEFT", copyBox, "BOTTOMLEFT", 0, -2)
	hintText:SetTextColor(0.4, 0.4, 0.4)
	hintText:SetText("클릭 → 복사 | Ctrl+C로 붙여넣기")
	hintText:SetJustifyH("LEFT")

	-- Scroll area (EditBox + 안내 아래)
	local scrollFrame = CreateFrame("ScrollFrame", nil, tagRefPanel)
	scrollFrame:SetPoint("TOPLEFT", 5, -(TOPBAR_HEIGHT + 44))
	scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)
	scrollFrame:EnableMouseWheel(true)

	local content = CreateFrame("Frame", nil, scrollFrame)
	content:SetWidth(TAG_REF_WIDTH - 10)
	content:SetHeight(1)
	scrollFrame:SetScrollChild(content)

	scrollFrame:SetScript("OnMouseWheel", function(self, delta)
		local current = scrollFrame:GetVerticalScroll()
		local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
		local newScroll = math.max(0, math.min(maxScroll, current - (delta * 30)))
		scrollFrame:SetVerticalScroll(newScroll)
	end)

	scrollFrame:SetScript("OnSizeChanged", function(self, w)
		content:SetWidth(w)
	end)

	-- Build content
	local yOff = -5
	local accentR, accentG, accentB = 0.30, 0.85, 0.45
	if SL then
		local from = SL.GetAccent("UnitFrames")
		if from then accentR, accentG, accentB = from[1], from[2], from[3] end
	end

	for _, section in ipairs(TAG_REF_SECTIONS) do
		-- Section header
		local header = content:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_ACCENT")
		header:SetPoint("TOPLEFT", 5, yOff)
		header:SetText(section.title)
		header:SetJustifyH("LEFT")
		header:SetTextColor(accentR, accentG, accentB)
		yOff = yOff - 18

		-- Divider line
		local line = content:CreateTexture(nil, "ARTWORK")
		line:SetHeight(1)
		line:SetPoint("TOPLEFT", 5, yOff)
		line:SetPoint("RIGHT", content, "RIGHT", -5, 0)
		line:SetColorTexture(accentR, accentG, accentB, 0.3)
		yOff = yOff - 5

		for _, tagInfo in ipairs(section.tags) do
			local tagName, desc = tagInfo[1], tagInfo[2]

			-- Clickable row (Button)
			local row = CreateFrame("Button", nil, content)
			row:SetSize(TAG_REF_WIDTH - 14, 30)
			row:SetPoint("TOPLEFT", 2, yOff)

			-- Hover highlight
			local rowHL = row:CreateTexture(nil, "HIGHLIGHT")
			rowHL:SetAllPoints()
			rowHL:SetColorTexture(1, 1, 1, 0.05)

			-- Tag code (NORMAL 폰트)
			local tagFs = row:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
			tagFs:SetPoint("TOPLEFT", 6, -2)
			tagFs:SetWidth(TAG_REF_WIDTH - 26)
			tagFs:SetJustifyH("LEFT")
			tagFs:SetText("|cff80d0ff" .. tagName .. "|r")

			-- Description (SMALL 폰트)
			local descFs = row:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
			descFs:SetPoint("TOPLEFT", 12, -15)
			descFs:SetWidth(TAG_REF_WIDTH - 32)
			descFs:SetJustifyH("LEFT")
			descFs:SetTextColor(0.55, 0.55, 0.55)
			descFs:SetText(desc)

			-- Click → copy to editbox
			row:SetScript("OnClick", function()
				copyBox:SetText(tagName)
				copyBox:SetFocus()
				copyBox:HighlightText()
			end)

			-- 마우스휠 전파
			row:EnableMouseWheel(true)
			row:SetScript("OnMouseWheel", function(_, delta)
				local current = scrollFrame:GetVerticalScroll()
				local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
				local newScroll = math.max(0, math.min(maxScroll, current - (delta * 30)))
				scrollFrame:SetVerticalScroll(newScroll)
			end)

			yOff = yOff - 32
		end

		yOff = yOff - 6  -- section gap
	end

	content:SetHeight(math.abs(yOff) + 20)

	return tagRefPanel
end

ShowTagReference = function()
	if not mainFrame or not mainFrame:IsShown() then return end
	local panel = CreateTagReferencePanel()
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 4, 0)
	panel:SetHeight(mainFrame:GetHeight())
	panel:Show()
end

HideTagReference = function()
	if tagRefPanel then tagRefPanel:Hide() end
end

-----------------------------------------------
-- Create Options Panel
-----------------------------------------------

local function CreateOptionsPanel()
	if mainFrame then return mainFrame end

	-- Main frame
	mainFrame = Widgets:CreateFrame("ddingUI_UF_Options", UIParent, PANEL_WIDTH, PANEL_HEIGHT)
	mainFrame:SetPoint("CENTER")
	mainFrame:SetFrameStrata("DIALOG")
	mainFrame:SetMovable(true)
	mainFrame:EnableMouse(true)
	mainFrame:RegisterForDrag("LeftButton")
	mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
	mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

	-- [REFACTOR] 옵션 창 닫힐 때 태그 레퍼런스도 숨김
	mainFrame:SetScript("OnHide", function()
		HideTagReference()
	end)
	mainFrame:SetClampedToScreen(true)
	mainFrame:SetResizable(true)
	mainFrame:SetResizeBounds(700, 500)
	local SL = ns.StyleLib
	Widgets:StylizeFrame(mainFrame, SL and SL.Colors.bg.main or { 0.1, 0.1, 0.1, 0.95 })

	-- Resize grip (L-shape, bottom-right)
	local grip = CreateFrame("Button", nil, mainFrame)
	grip:SetSize(28, 28)
	grip:SetPoint("BOTTOMRIGHT", -5, 5)
	grip:SetFrameLevel(mainFrame:GetFrameLevel() + 20)
	grip:RegisterForDrag("LeftButton")
	grip:SetScript("OnDragStart", function() mainFrame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnDragStop", function()
		mainFrame:StopMovingOrSizing()
		-- 태그 레퍼런스 패널 높이 동기화
		if tagRefPanel and tagRefPanel:IsShown() then
			tagRefPanel:SetHeight(mainFrame:GetHeight())
		end
	end)

	local gripV = grip:CreateTexture(nil, "OVERLAY")
	gripV:SetSize(5, 20)
	gripV:SetPoint("BOTTOMRIGHT", 0, 0)
	gripV:SetColorTexture(1, 1, 1, 1)

	local gripH = grip:CreateTexture(nil, "OVERLAY")
	gripH:SetSize(20, 5)
	gripH:SetPoint("BOTTOMRIGHT", 0, 0)
	gripH:SetColorTexture(1, 1, 1, 1)

	-- Top bar
	local topBar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
	topBar:SetHeight(TOPBAR_HEIGHT)
	topBar:SetPoint("TOPLEFT", 0, 0)
	topBar:SetPoint("TOPRIGHT", 0, 0)
	Widgets:StylizeFrame(topBar, SL and SL.Colors.bg.titlebar or { 0.12, 0.12, 0.12, 0.98 })

	-- Accent gradient line (top of title bar)
	if SL then
		local from, to = SL.GetAccent("UnitFrames")
		local accentLine = SL.CreateHorizontalGradient(topBar, from, to, 2, "OVERLAY")
		accentLine:SetPoint("TOPLEFT", topBar, "TOPLEFT", 0, 0)
		accentLine:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", 0, 0)
	end

	-- Title (accent colored)
	local title = topBar:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_TITLE")
	if SL then
		title:SetText(SL.CreateAddonTitle("UnitFrames", "UnitFrames")) -- [STYLE]
	else
		title:SetText("DDingUI UnitFrames")
	end
	title:SetPoint("LEFT", 10, 0)

	-- [REFACTOR] 상단 프로필 전환바 제거 — 프로필 관리는 프로필 페이지에서만

	-- Close button
	local closeBtn = Widgets:CreateButton(topBar, "X", "red", { 28, 24 })
	closeBtn:SetPoint("RIGHT", -5, 0)
	closeBtn:SetScript("OnClick", function()
		mainFrame:Hide()
	end)

	-- [ESSENTIAL] 편집모드 버튼 (타이틀바로 이동)
	local editBtn = Widgets:CreateButton(topBar, "편집모드", "accent", {80, 22})
	editBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
	editBtn:SetScript("OnClick", function()
		ns.db.locked = false
		if ns.Mover then ns.Mover:UnlockAll() end
		if ns.Update then ns.Update:EnableEditMode() end
		RefreshCurrentPreview()
	end)

	-- Search box
	local searchBox = Widgets:CreateSearchBox(topBar, 200)
	searchBox:SetPoint("RIGHT", editBtn, "LEFT", -10, 0)

	-- Sidebar
	local sidebar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
	sidebar:SetWidth(SIDEBAR_WIDTH)
	sidebar:SetPoint("TOPLEFT", 0, -TOPBAR_HEIGHT)
	sidebar:SetPoint("BOTTOMLEFT", 0, 0)
	Widgets:StylizeFrame(sidebar, SL and SL.Colors.bg.sidebar or { 0.08, 0.08, 0.08, 0.95 })
	mainFrame._sidebar = sidebar

	-- TreeView
	local treeView = Widgets:CreateTreeView(sidebar, SIDEBAR_WIDTH - 5, PANEL_HEIGHT - TOPBAR_HEIGHT - 10)
	treeView:SetPoint("TOPLEFT", 2, -5)
	treeView:SetData(categoryData)
	Options._treeView = treeView -- [EDITMODE] Mover 우클릭에서 접근용

	-- Vertical divider between sidebar and content
	local divider = mainFrame:CreateTexture(nil, "ARTWORK")
	divider:SetWidth(1)
	local sepColor = SL and SL.Colors.border.separator or {0.20, 0.20, 0.20, 0.40}
	divider:SetColorTexture(sepColor[1], sepColor[2], sepColor[3], sepColor[4] or 0.40)
	divider:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", SIDEBAR_WIDTH, -TOPBAR_HEIGHT)
	divider:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", SIDEBAR_WIDTH, 0)

	-- [12.0.1] Preview 시스템 제거 → TestMode로 대체

	-- Content area
	contentFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
	contentFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
	contentFrame:SetPoint("BOTTOMRIGHT", -5, 5)
	Widgets:StylizeFrame(contentFrame, SL and SL.Colors.bg.main or { 0.10, 0.10, 0.10, 0.95 })

	-- Content scroll frame
	local contentScroll = Widgets:CreateScrollFrame(contentFrame)
	contentFrame.scrollFrame = contentScroll
	contentFrame.content = contentScroll.content

	-- Connect search to treeview + content search
	searchBox:SetOnTextChanged(function(text)
		treeView:Filter(text)

		-- 디바운스 타이머 취소
		if searchDebounceTimer then
			searchDebounceTimer:Cancel()
			searchDebounceTimer = nil
		end

		if text and text ~= "" then
			-- 0.2초 디바운스 후 콘텐츠 검색
			searchDebounceTimer = C_Timer.NewTimer(0.2, function()
				PerformSearch(text, treeView, searchBox)
			end)
		else
			ClearSearch()
		end
	end)

	-- Connect treeview selection to page loading
	treeView:SetOnSelect(function(categoryId)
		LoadPage(categoryId)
	end)

	-- Default selection
	treeView:SelectCategory("general.global")

	-- ESC to close
	table.insert(UISpecialFrames, "ddingUI_UF_Options")

	return mainFrame
end

-----------------------------------------------
-- Public API
-----------------------------------------------

function Options:Initialize()
	-- Nothing to do on init
end

function Options:Toggle()
	local panel = CreateOptionsPanel()
	if panel:IsShown() then
		panel:Hide()
	else
		panel:Show()
	end
end

function Options:Show()
	local panel = CreateOptionsPanel()
	panel:Show()
end

function Options:Hide()
	if mainFrame then
		mainFrame:Hide()
	end
end

function Options:IsShown()
	return mainFrame and mainFrame:IsShown()
end

-- [EDITMODE] Mover 우클릭 → 해당 유닛 설정 페이지로 이동
function Options:OpenUnit(unitKey)
	if not unitKey then return end
	local panel = CreateOptionsPanel()
	panel:Show()
	-- unitKey → categoryId 변환
	local categoryId = "unitframes." .. unitKey .. ".general"
	if self._treeView then
		self._treeView:SelectCategory(categoryId)
	end
end

-- ns.OpenConfig 글로벌 접근점
ns.OpenConfig = function(unitKey)
	if ns.Options then
		ns.Options:OpenUnit(unitKey)
	end
end
