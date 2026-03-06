import re

file_path = r'G:\wow2\World of Warcraft\_retail_\Interface\AddOns\DDingUI_UF\Modules\Options.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Replace categoryData
new_category_data = """local categoryData = {
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
			{ id = "personal.power", text = "자원바 / 시전바" },
			{ id = "personal.auras", text = "오라 (버프/디버프)" },
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
			{ id = "group.health", text = "체력바 / 자원바" },
			{ id = "group.auras", text = "오라 / 생존기" },
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
}"""

text = re.sub(r'local categoryData = \{.*?\n\}\n\n-+\n-- Page Builders', new_category_data + '\n\n-----------------------------------------------\n-- Page Builders', text, flags=re.DOTALL)

# 2. Setup Shared Tabbing
setup_tabs = """local pageBuilders = {}
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
end"""

text = re.sub(r'local pageBuilders = \{\}.*?return nil\nend', setup_tabs, text, flags=re.DOTALL)

# 3. Add Tab Manager and rewrite pageBuilders registering
tab_manager = """
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
	
	local featureContainer = CreateFrame("Frame", nil, parent)
	featureContainer:SetPoint("TOPLEFT", headerContainer, "BOTTOMLEFT", 0, -10)
	featureContainer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	
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
			
			copyBtn.text:SetText(destName .. " 설정으로 덮어쓰기")
			
			copyBtn:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(destName .. " 설정 복사")
				GameTooltip:AddLine("현재 탭의 설정을 " .. destName .. " 프레임으로 동일하게 복사합니다.\n(DandersFrames 스타일 실시간 동기화)", 1, 1, 1, true)
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

		featureFn(featureContainer, selectedUnit)
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
pageBuilders["personal.power"] = function(p) BuildSharedFeaturePage(p, "personal", function(c, u) BuildUnitPowerPage(c, u); BuildUnitCastBarPage(c, u) end) end
pageBuilders["personal.auras"] = function(p) BuildSharedFeaturePage(p, "personal", function(c, u) BuildUnitAurasPage(c, u, "buffs"); BuildUnitAurasPage(c, u, "debuffs"); BuildDefensivesPage(c, u) end) end
pageBuilders["personal.privateauras"] = function(p) BuildSharedFeaturePage(p, "personal", BuildPrivateAurasPage) end
pageBuilders["personal.texts"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitTextsPage) end
pageBuilders["personal.indicators"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitIndicatorsPage) end
pageBuilders["personal.effects"] = function(p) BuildSharedFeaturePage(p, "personal", function(c, u) BuildThreatHighlightPage(c, u); BuildDebuffHighlightPage(c, u) end) end
pageBuilders["personal.fader"] = function(p) BuildSharedFeaturePage(p, "personal", BuildFaderPage) end
pageBuilders["personal.healprediction"] = function(p) BuildSharedFeaturePage(p, "personal", BuildHealPredictionPage) end
pageBuilders["personal.customtext"] = function(p) BuildSharedFeaturePage(p, "personal", BuildCustomTextPage) end

-- Map group pages
pageBuilders["group.general"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitGeneralPage) end
pageBuilders["group.layout"] = function(p) BuildSharedFeaturePage(p, "group", BuildGroupLayoutPage) end
pageBuilders["group.health"] = function(p) BuildSharedFeaturePage(p, "group", function(c, u) BuildUnitHealthPage(c, u); BuildUnitPowerPage(c, u) end) end
pageBuilders["group.auras"] = function(p) BuildSharedFeaturePage(p, "group", function(c, u) BuildUnitAurasPage(c, u, "buffs"); BuildUnitAurasPage(c, u, "debuffs"); BuildDefensivesPage(c, u) end) end
pageBuilders["group.privateauras"] = function(p) BuildSharedFeaturePage(p, "group", BuildPrivateAurasPage) end
pageBuilders["group.indicators"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitIndicatorsPage) end
pageBuilders["group.texts"] = function(p) BuildSharedFeaturePage(p, "group", BuildUnitTextsPage) end
pageBuilders["group.debuffhighlight"] = function(p) BuildSharedFeaturePage(p, "group", BuildDebuffHighlightPage) end
pageBuilders["group.dispels"] = function(p) BuildSharedFeaturePage(p, "group", BuildDispelsPage) end
pageBuilders["group.fader"] = function(p) BuildSharedFeaturePage(p, "group", BuildFaderPage) end
pageBuilders["group.healprediction"] = function(p) BuildSharedFeaturePage(p, "group", BuildHealPredictionPage) end
pageBuilders["group.effects"] = function(p) BuildSharedFeaturePage(p, "group", BuildThreatHighlightPage) end
pageBuilders["group.customtext"] = function(p) BuildSharedFeaturePage(p, "group", BuildCustomTextPage) end
"""

text = re.sub(r'-- Unit frame pages.*?pageBuilders\["hottracker"\]', tab_manager + '\npageBuilders["hottracker"]', text, flags=re.DOTALL)

# 4. Remove the Copy to Raid duplicate logic we added to CreatePageHeader
text = re.sub(r'-- \[DandersFrames 스타일 카테고리/유닛 복사 기능\].*?return header', 'return header', text, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print('Updated everything.')
