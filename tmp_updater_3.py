import re

file_path = r'G:\wow2\World of Warcraft\_retail_\Interface\AddOns\DDingUI_UF\Modules\Options.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# Add classbar back as a standalone function
classbar_fn = r"""
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
end
-----------------------------------------------
-- Feature Routing System (DandersFrames Style)"""

text = text.replace("-- Feature Routing System (DandersFrames Style)", classbar_fn)

# Add to categoryData
cat_replace = """{ id = "personal.castbar", text = "시전바" },
			{ id = "personal.classbar", text = "직업 자원" },
			{ id = "personal.altpower", text = "보조 자원" },"""
text = re.sub(r'\{ id = "personal.castbar", text = "시전바" \},', cat_replace, text)

# Map the builders
builder_add = """pageBuilders["personal.castbar"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitCastBarPage) end
pageBuilders["personal.classbar"] = function(p) BuildSharedFeaturePage(p, "personal", BuildUnitClassBarPage) end
pageBuilders["personal.altpower"] = function(p) BuildSharedFeaturePage(p, "personal", BuildAltPowerBarPage) end"""
text = re.sub(r'pageBuilders\["personal.castbar"\] =.*?end', builder_add, text)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print('Restored classbar.')
