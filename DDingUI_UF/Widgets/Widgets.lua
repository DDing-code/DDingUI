--[[
	ddingUI UnitFrames
	Widgets/Widgets.lua - Cell-style widget framework
]]

local ADDON_NAME, ns = ...

local Widgets = {}
ns.Widgets = Widgets

-----------------------------------------
-- Texture Path
-----------------------------------------
local WHITE_TEXTURE = (_G.DDingUI_StyleLib and _G.DDingUI_StyleLib.Textures and _G.DDingUI_StyleLib.Textures.flat) or [[Interface\Buttons\WHITE8x8]] -- [12.0.1]

-----------------------------------------
-- DDingUI StyleLib Integration
-----------------------------------------
local SL = LibStub and LibStub("DDingUI-StyleLib-1.0", true)
ns.StyleLib = SL

-----------------------------------------
-- Color System (StyleLib → fallback)
-----------------------------------------
local colors, accentColor, accentColorTo
local bgColor, borderColor, hoverColor, disabledColor

if SL then
	local from, to = SL.GetAccent("UnitFrames")
	accentColor   = {from[1], from[2], from[3]}
	accentColorTo = {to[1], to[2], to[3]}
	bgColor       = {SL.Colors.bg.input[1], SL.Colors.bg.input[2], SL.Colors.bg.input[3], SL.Colors.bg.input[4]}
	borderColor   = {0, 0, 0, 1}
	hoverColor    = {SL.Colors.bg.hover[1], SL.Colors.bg.hover[2], SL.Colors.bg.hover[3], SL.Colors.bg.hover[4]}
	disabledColor = {SL.Colors.text.disabled[1], SL.Colors.text.disabled[2], SL.Colors.text.disabled[3], SL.Colors.text.disabled[4]}
	colors = {
		grey   = {SL.Colors.text.dim[1], SL.Colors.text.dim[2], SL.Colors.text.dim[3]},
		yellow = {1, 0.82, 0},
		orange = {1, 0.65, 0},
		red    = {SL.Colors.status.error[1], SL.Colors.status.error[2], SL.Colors.status.error[3]},
		green  = {SL.Colors.status.success[1], SL.Colors.status.success[2], SL.Colors.status.success[3]},
		blue   = {0, 0.5, 0.8},
		cyan   = {0, 0.8, 0.8},
	}
else
	accentColor   = {0.30, 0.85, 0.45}
	accentColorTo = {0.12, 0.55, 0.20}
	bgColor       = {0.06, 0.06, 0.06, 0.80}
	borderColor   = {0, 0, 0, 1}
	hoverColor    = {0.20, 0.20, 0.20, 0.60}
	disabledColor = {0.50, 0.50, 0.50, 1}
	colors = {
		grey   = {0.6, 0.6, 0.6},
		yellow = {1, 0.82, 0},
		orange = {1, 0.65, 0},
		red    = {1, 0.19, 0.19},
		green  = {0.3, 0.8, 0.3},
		blue   = {0, 0.5, 0.8},
		cyan   = {0, 0.8, 0.8},
	}
end

-----------------------------------------
-- Export Colors
-----------------------------------------
function Widgets:GetAccentColor()
	return accentColor[1], accentColor[2], accentColor[3]
end

function Widgets:GetAccentColorTable(alpha)
	if alpha then
		return {accentColor[1], accentColor[2], accentColor[3], alpha}
	end
	return accentColor
end

function Widgets:SetAccentColor(r, g, b)
	accentColor[1] = r
	accentColor[2] = g
	accentColor[3] = b
end

-----------------------------------------
-- Font System (StyleLib → fallback)
-----------------------------------------
local fontPath  = SL and SL.Font.path or "Fonts\\2002.TTF"
local fontSize  = {
	title   = SL and SL.Font.title   or 14,
	section = SL and SL.Font.section  or 14,
	normal  = SL and SL.Font.normal   or 13,
	small   = SL and SL.Font.small    or 11,
}
local textNormal    = SL and SL.Colors.text.normal    or {0.85, 0.85, 0.85, 1}
local textHighlight = SL and SL.Colors.text.highlight or {1, 1, 1, 1}

local font_title = CreateFont("DDINGUI_UF_FONT_TITLE")
font_title:SetFont(fontPath, fontSize.title, "OUTLINE")
font_title:SetTextColor(textHighlight[1], textHighlight[2], textHighlight[3], textHighlight[4])
font_title:SetShadowColor(0, 0, 0, 1)
font_title:SetShadowOffset(1, -1)
font_title:SetJustifyH("CENTER")

local font_normal = CreateFont("DDINGUI_UF_FONT_NORMAL")
font_normal:SetFont(fontPath, fontSize.normal, "")
font_normal:SetTextColor(textNormal[1], textNormal[2], textNormal[3], textNormal[4])
font_normal:SetShadowColor(0, 0, 0, 1)
font_normal:SetShadowOffset(1, -1)
font_normal:SetJustifyH("CENTER")

local font_small = CreateFont("DDINGUI_UF_FONT_SMALL")
font_small:SetFont(fontPath, fontSize.small, "")
font_small:SetTextColor(textNormal[1], textNormal[2], textNormal[3], textNormal[4])
font_small:SetShadowColor(0, 0, 0, 1)
font_small:SetShadowOffset(1, -1)
font_small:SetJustifyH("CENTER")

local font_disabled = CreateFont("DDINGUI_UF_FONT_DISABLED")
font_disabled:SetFont(fontPath, fontSize.normal, "")
font_disabled:SetTextColor(disabledColor[1], disabledColor[2], disabledColor[3], disabledColor[4] or 1)
font_disabled:SetShadowColor(0, 0, 0, 1)
font_disabled:SetShadowOffset(1, -1)
font_disabled:SetJustifyH("CENTER")

local font_accent = CreateFont("DDINGUI_UF_FONT_ACCENT")
font_accent:SetFont(fontPath, fontSize.section, "")
font_accent:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
font_accent:SetShadowColor(0, 0, 0, 1)
font_accent:SetShadowOffset(1, -1)
font_accent:SetJustifyH("CENTER")

-----------------------------------------
-- StylizeFrame
-----------------------------------------
function Widgets:StylizeFrame(frame, color, border)
	if not color then color = bgColor end
	if not border then border = borderColor end

	frame:SetBackdrop({
		bgFile = WHITE_TEXTURE,
		edgeFile = WHITE_TEXTURE,
		edgeSize = 1,
	})
	frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
	frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-----------------------------------------
-- Tooltip System
-----------------------------------------
local function ShowTooltips(widget, anchor, x, y, tooltips)
	if type(tooltips) ~= "table" or #tooltips == 0 then
		GameTooltip:Hide()
		return
	end

	GameTooltip:SetOwner(widget, anchor or "ANCHOR_TOP", x or 0, y or 0)
	GameTooltip:AddLine(tooltips[1])
	for i = 2, #tooltips do
		if tooltips[i] then
			GameTooltip:AddLine("|cffffffff" .. tooltips[i])
		end
	end
	GameTooltip:Show()
end

function Widgets:SetTooltips(widget, anchor, x, y, ...)
	if not widget._tooltipsInited then
		widget._tooltipsInited = true
		widget:HookScript("OnEnter", function()
			ShowTooltips(widget, anchor, x, y, widget.tooltips)
		end)
		widget:HookScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end
	widget.tooltips = {...}
end

-----------------------------------------
-- CreateFrame (styled)
-----------------------------------------
function Widgets:CreateFrame(name, parent, width, height, isTransparent)
	local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
	f:Hide()
	if not isTransparent then
		self:StylizeFrame(f)
	end
	f:EnableMouse(true)
	if width and height then
		f:SetSize(width, height)
	end
	return f
end

-----------------------------------------
-- CreateTitledPane (Cell-style: underline only)
-----------------------------------------
function Widgets:CreateTitledPane(parent, title, width, height)
	local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	pane:SetSize(width, height)
	-- No background, transparent pane

	-- Title text (accent color)
	local titleText = pane:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_TITLE")
	pane.title = titleText
	titleText:SetJustifyH("LEFT")
	titleText:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
	titleText:SetText(title)
	titleText:SetPoint("TOPLEFT", 0, 0)

	-- Underline (accent gradient)
	local line
	if SL then
		line = SL.CreateHorizontalGradient(pane,
			{accentColor[1], accentColor[2], accentColor[3], 0.8},
			{accentColorTo[1], accentColorTo[2], accentColorTo[3], 0.15},
			1, "ARTWORK")
	else
		line = pane:CreateTexture(nil, "ARTWORK")
		line:SetHeight(1)
		line:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.8)
	end
	pane.line = line
	line:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -17)
	line:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -17)

	-- Content area
	pane.content = CreateFrame("Frame", nil, pane)
	pane.content:SetPoint("TOPLEFT", 0, -20)
	pane.content:SetPoint("BOTTOMRIGHT", 0, 0)

	function pane:SetTitle(text)
		titleText:SetText(text)
	end

	return pane
end

-----------------------------------------
-- CreateSeparator
-----------------------------------------
function Widgets:CreateSeparator(parent, text, width)
	if not width then width = parent:GetWidth() - 10 end

	local fs = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_TITLE")
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
	fs:SetText(text)

	local line
	if SL then
		line = SL.CreateHorizontalGradient(parent,
			{accentColor[1], accentColor[2], accentColor[3], 0.8},
			{accentColorTo[1], accentColorTo[2], accentColorTo[3], 0.15},
			1, "ARTWORK")
		line:SetWidth(width)
	else
		line = parent:CreateTexture(nil, "ARTWORK")
		line:SetSize(width, 1)
		line:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.8)
	end
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)

	return fs
end

-----------------------------------------
-- CreateButton
-----------------------------------------
function Widgets:CreateButton(parent, text, buttonColor, size, ...)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	if parent then b:SetFrameLevel(parent:GetFrameLevel() + 1) end
	b:SetText(text)
	b:SetSize(size[1], size[2])

	local color, hover
	if buttonColor == "red" then
		color = {0.6, 0.1, 0.1, 0.6}
		hover = {0.6, 0.1, 0.1, 1}
	elseif buttonColor == "green" then
		color = {0.1, 0.6, 0.1, 0.6}
		hover = {0.1, 0.6, 0.1, 1}
	elseif buttonColor == "accent" then
		color = {accentColor[1], accentColor[2], accentColor[3], 0.3}
		hover = {accentColor[1], accentColor[2], accentColor[3], 0.6}
	elseif buttonColor == "accent-hover" then
		color = bgColor
		hover = {accentColor[1], accentColor[2], accentColor[3], 0.6}
	elseif buttonColor == "transparent" then
		color = {0, 0, 0, 0}
		hover = {0.5, 1, 0, 0.7}
	else
		color = bgColor
		hover = hoverColor
	end

	b.color = color
	b.hoverColor = hover

	local fs = b:GetFontString()
	if fs then
		fs:SetWordWrap(false)
		fs:SetPoint("LEFT")
		fs:SetPoint("RIGHT")
	end

	b:SetBackdrop({
		bgFile = WHITE_TEXTURE,
		edgeFile = WHITE_TEXTURE,
		edgeSize = 1,
	})
	b:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
	b:SetBackdropBorderColor(0, 0, 0, 1)
	b:SetPushedTextOffset(0, -1)

	b:SetNormalFontObject(font_normal)
	b:SetHighlightFontObject(font_normal)
	b:SetDisabledFontObject(font_disabled)

	b:SetScript("OnEnter", function(self)
		self:SetBackdropColor(self.hoverColor[1], self.hoverColor[2], self.hoverColor[3], self.hoverColor[4] or 1)
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropColor(self.color[1], self.color[2], self.color[3], self.color[4] or 1)
	end)
	b:SetScript("PostClick", function()
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
	end)

	self:SetTooltips(b, "ANCHOR_TOPLEFT", 0, 3, ...)

	return b
end

-----------------------------------------
-- CreateCheckButton
-----------------------------------------
function Widgets:CreateCheckButton(parent, label, onClick, ...)
	local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
	cb.onClick = onClick

	cb:SetScript("OnClick", function(self)
		PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if cb.onClick then
			cb.onClick(self:GetChecked() and true or false, self)
		end
	end)

	cb.label = cb:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	cb.label:SetText(label)
	cb.label:SetPoint("LEFT", cb, "RIGHT", 5, 0)

	cb:SetSize(14, 14)
	if label and strtrim(label) ~= "" then
		cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 5, 0, 0)
	end

	cb:SetBackdrop({
		bgFile = WHITE_TEXTURE,
		edgeFile = WHITE_TEXTURE,
		edgeSize = 1,
	})
	cb:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.80)
	cb:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

	local checkedTex = cb:CreateTexture(nil, "ARTWORK")
	checkedTex:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.7)
	checkedTex:SetPoint("TOPLEFT", 1, -1)
	checkedTex:SetPoint("BOTTOMRIGHT", -1, 1)

	local highlightTex = cb:CreateTexture(nil, "ARTWORK")
	highlightTex:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.1)
	highlightTex:SetPoint("TOPLEFT", 1, -1)
	highlightTex:SetPoint("BOTTOMRIGHT", -1, 1)

	cb:SetCheckedTexture(checkedTex)
	cb:SetHighlightTexture(highlightTex, "ADD")

	cb:SetScript("OnEnable", function()
		cb.label:SetTextColor(textHighlight[1], textHighlight[2], textHighlight[3], textHighlight[4] or 1)
		checkedTex:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.7)
		cb:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	end)

	cb:SetScript("OnDisable", function()
		cb.label:SetTextColor(disabledColor[1], disabledColor[2], disabledColor[3], disabledColor[4] or 1)
		checkedTex:SetColorTexture(0.4, 0.4, 0.4, 0.7)
		cb:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.4)
	end)

	function cb:SetText(text)
		cb.label:SetText(text)
		if text and strtrim(text) ~= "" then
			cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 5, 0, 0)
		else
			cb:SetHitRectInsets(0, 0, 0, 0)
		end
	end

	self:SetTooltips(cb, "ANCHOR_TOPLEFT", 0, 3, ...)

	return cb
end

-----------------------------------------
-- CreateSlider
-----------------------------------------
function Widgets:CreateSlider(name, parent, low, high, width, step, onValueChanged, afterValueChanged, ...)
	local tooltips = {...}
	local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(width, 10) -- [FIX] 드래그 영역 확장 (4→10)

	self:StylizeFrame(slider)
	slider:SetBackdropBorderColor(0, 0, 0, 0) -- no border on track

	-- Label
	local label = slider:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	label:SetText(name)
	label:SetPoint("BOTTOM", slider, "TOP", 0, 2)

	function slider:SetLabel(text)
		label:SetText(text)
	end

	-- Current value editbox
	local editBox = CreateFrame("EditBox", nil, slider, "BackdropTemplate")
	slider.editBox = editBox
	editBox:SetSize(36, 14) -- [FIX] 입력박스 크기 축소 (48→36)
	editBox:SetPoint("TOP", slider, "BOTTOM", 0, -6) -- [FIX] 슬라이더-입력필드 간격
	editBox:SetFontObject(font_normal)
	editBox:SetJustifyH("CENTER")
	editBox:SetAutoFocus(false)
	self:StylizeFrame(editBox)

	editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	editBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local value = tonumber(self:GetText())
		if value and value ~= self.oldValue then
			value = math.max(slider.low, math.min(slider.high, value))
			self:SetText(value)
			slider:SetValue(value)
			if slider.onValueChanged then slider.onValueChanged(value) end
			if slider.afterValueChanged then slider.afterValueChanged(value) end
		else
			self:SetText(self.oldValue)
		end
	end)
	editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	editBox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)

	-- Low/High labels
	local lowText = slider:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	slider.lowText = lowText
	lowText:SetTextColor(colors.grey[1], colors.grey[2], colors.grey[3])
	lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -6)
	lowText:SetPoint("BOTTOM", editBox)

	local highText = slider:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	slider.highText = highText
	highText:SetTextColor(colors.grey[1], colors.grey[2], colors.grey[3])
	highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -6)
	highText:SetPoint("BOTTOM", editBox)

	-- Thumb texture
	local thumb = slider:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.7)
	thumb:SetSize(16, 16) -- [UF-OPTIONS] 잡기 쉽게 크기 증가
	slider:SetThumbTexture(thumb)

	-- Scripts
	local valueBeforeClick
	slider:SetScript("OnEnter", function()
		thumb:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
		valueBeforeClick = slider:GetValue()
		if #tooltips > 0 then
			ShowTooltips(slider, "ANCHOR_TOPLEFT", 0, 3, tooltips)
		end
	end)
	slider:SetScript("OnLeave", function()
		thumb:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.7)
		GameTooltip:Hide()
	end)

	slider.onValueChanged = onValueChanged
	slider.afterValueChanged = afterValueChanged

	local oldValue
	local lastThrottleTime = 0 -- [UF-OPTIONS] 실시간 반영 throttle
	local THROTTLE_INTERVAL = 0.05 -- 50ms

	slider:SetScript("OnValueChanged", function(self, value, userChanged)
		if oldValue == value then return end
		oldValue = value

		if math.floor(value) < value then
			value = tonumber(string.format("%.2f", value))
		end

		editBox:SetText(value)
		editBox.oldValue = value
		if userChanged then
			if slider.onValueChanged then
				slider.onValueChanged(value)
			end
			-- [UF-OPTIONS] 드래그 중 실시간 반영 (throttled)
			if slider.afterValueChanged then
				local now = GetTime()
				if now - lastThrottleTime >= THROTTLE_INTERVAL then
					lastThrottleTime = now
					slider.afterValueChanged(value)
				end
			end
		end
	end)

	slider:SetScript("OnMouseUp", function()
		if not slider:IsEnabled() then return end
		if valueBeforeClick ~= oldValue and slider.afterValueChanged then
			valueBeforeClick = oldValue
			local value = slider:GetValue()
			if math.floor(value) < value then
				value = tonumber(string.format("%.2f", value))
			end
			slider.afterValueChanged(value)
		end
	end)

	slider:SetScript("OnDisable", function()
		label:SetTextColor(disabledColor[1], disabledColor[2], disabledColor[3], disabledColor[4] or 1)
		editBox:SetEnabled(false)
		thumb:SetColorTexture(0.4, 0.4, 0.4, 0.7)
		lowText:SetTextColor(disabledColor[1], disabledColor[2], disabledColor[3], disabledColor[4] or 1)
		highText:SetTextColor(disabledColor[1], disabledColor[2], disabledColor[3], disabledColor[4] or 1)
	end)

	slider:SetScript("OnEnable", function()
		label:SetTextColor(textHighlight[1], textHighlight[2], textHighlight[3], textHighlight[4] or 1)
		editBox:SetEnabled(true)
		thumb:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.7)
		lowText:SetTextColor(colors.grey[1], colors.grey[2], colors.grey[3])
		highText:SetTextColor(colors.grey[1], colors.grey[2], colors.grey[3])
	end)

	function slider:UpdateMinMaxValues(minV, maxV)
		slider:SetMinMaxValues(minV, maxV)
		slider.low = minV
		slider.high = maxV
		lowText:SetText(minV)
		highText:SetText(maxV)
	end
	slider:UpdateMinMaxValues(low, high)
	slider:SetValue(low)

	return slider
end

-----------------------------------------
-- CreateDropdown
-----------------------------------------
-- [DF-FIX] 공유 오버레이: 외부 클릭 시 드롭다운 닫기 + 다중 드롭다운 충돌 방지
local _activeDropdownList = nil
local _dropdownOverlay = nil

local function GetDropdownOverlay()
	if _dropdownOverlay then return _dropdownOverlay end
	_dropdownOverlay = CreateFrame("Button", nil, UIParent)
	_dropdownOverlay:SetAllPoints(UIParent)
	_dropdownOverlay:SetFrameStrata("TOOLTIP")
	_dropdownOverlay:SetFrameLevel(199) -- listFrame(200) 바로 아래
	_dropdownOverlay:EnableMouse(true)
	_dropdownOverlay:Hide()
	_dropdownOverlay:RegisterForClicks("AnyUp")
	_dropdownOverlay:SetScript("OnClick", function()
		if _activeDropdownList then
			_activeDropdownList:Hide()
		end
	end)
	return _dropdownOverlay
end

function Widgets:CreateDropdown(parent, width, ...)
	local dropdown = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	dropdown:SetSize(width, 20)
	self:StylizeFrame(dropdown)
	dropdown:EnableMouse(true)

	dropdown.text = dropdown:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	dropdown.text:SetJustifyH("LEFT")
	dropdown.text:SetPoint("LEFT", 5, 0)
	dropdown.text:SetPoint("RIGHT", -20, 0)
	dropdown.text:SetWordWrap(false)

	-- Arrow (text, not Blizzard texture)
	local arrow = dropdown:CreateFontString(nil, "OVERLAY")
	arrow:SetFont(fontPath, fontSize.normal, "")
	arrow:SetTextColor(colors.grey[1], colors.grey[2], colors.grey[3])
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetText("\226\150\188") -- ▼

	-- List frame (UIParent에 부착 → 부모 ScrollFrame 클리핑 방지) -- [DF-FIX]
	local MAX_VISIBLE_ITEMS = 12
	local ITEM_HEIGHT = 20

	local listFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	dropdown.listFrame = listFrame
	listFrame:SetWidth(width)
	listFrame:SetFrameStrata("TOOLTIP")
	listFrame:SetFrameLevel(200)
	listFrame:Hide()
	self:StylizeFrame(listFrame)

	-- 스크롤 프레임 (리스트 내부)
	local listScroll = CreateFrame("ScrollFrame", nil, listFrame)
	listScroll:SetPoint("TOPLEFT", 1, -1)
	listScroll:SetPoint("BOTTOMRIGHT", -1, 1)
	listScroll:EnableMouseWheel(true)

	local listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetWidth(width - 2)
	listContent:SetHeight(1)
	listScroll:SetScrollChild(listContent)

	listScroll:SetScript("OnMouseWheel", function(self, delta)
		local current = self:GetVerticalScroll()
		local maxScroll = math.max(0, listContent:GetHeight() - listScroll:GetHeight())
		local newScroll = math.max(0, math.min(maxScroll, current - (delta * ITEM_HEIGHT * 2)))
		self:SetVerticalScroll(newScroll)
	end)

	dropdown.items = {}

	function dropdown:SetItems(items)
		if not items then items = {} end
		-- Clear existing
		for _, btn in ipairs(dropdown.items) do
			btn:Hide()
		end
		wipe(dropdown.items)

		local totalHeight = 0
		for i, item in ipairs(items) do
			-- [FIX] BackdropTemplate → 일반 Button + 텍스처 (LSM 100+개 "script ran too long" 방지)
			local btn = CreateFrame("Button", nil, listContent)
			btn:SetSize(width - 2, ITEM_HEIGHT)
			btn:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_HEIGHT)

			local hl = btn:CreateTexture(nil, "BACKGROUND")
			hl:SetAllPoints()
			hl:SetTexture(WHITE_TEXTURE)
			hl:SetVertexColor(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4] or 0.60)
			hl:Hide()
			btn._highlight = hl

			btn.text = btn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
			btn.text:SetJustifyH("LEFT")
			btn.text:SetPoint("LEFT", 5, 0)
			btn.text:SetPoint("RIGHT", -5, 0)
			btn.text:SetText(item.text or item)

			btn.value = item.value or item
			btn.onClick = item.onClick

			btn:SetScript("OnEnter", function(self)
				self._highlight:Show()
			end)
			btn:SetScript("OnLeave", function(self)
				self._highlight:Hide()
			end)
			btn:SetScript("OnClick", function(self)
				dropdown.text:SetText(self.text:GetText())
				dropdown.selected = self.value
				listFrame:Hide()
				PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
				if self.onClick then
					self.onClick(self.value)
				elseif dropdown.onSelect then
					dropdown.onSelect(self.value)
				end
			end)

			table.insert(dropdown.items, btn)
			totalHeight = totalHeight + ITEM_HEIGHT
		end

		listContent:SetHeight(totalHeight)
		-- 리스트가 길면 최대 높이 제한
		local visibleHeight = math.min(totalHeight, MAX_VISIBLE_ITEMS * ITEM_HEIGHT)
		listFrame:SetHeight(visibleHeight + 2)
	end

	function dropdown:SetSelected(value)
		dropdown.selected = value
		for _, btn in ipairs(dropdown.items) do
			if btn.value == value then
				dropdown.text:SetText(btn.text:GetText())
				break
			end
		end
	end

	function dropdown:SetSelectedText(text)
		dropdown.text:SetText(text)
	end

	function dropdown:GetSelected()
		return dropdown.selected
	end

	function dropdown:SetOnSelect(func)
		dropdown.onSelect = func
	end

	dropdown:SetScript("OnMouseDown", function()
		if listFrame:IsShown() then
			listFrame:Hide()
		else
			-- [DF-FIX] 다른 열린 드롭다운 먼저 닫기
			if _activeDropdownList and _activeDropdownList ~= listFrame and _activeDropdownList:IsShown() then
				_activeDropdownList:Hide()
			end
			listFrame:Show()
		end
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
	end)

	local borderActive = SL and SL.Colors.border.active or {0.40, 0.40, 0.40, 0.70}
	dropdown:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(borderActive[1], borderActive[2], borderActive[3], borderActive[4] or 0.70)
	end)
	dropdown:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	end)

	-- [DF-FIX] listFrame을 UIParent에 부착했으므로, 드롭다운 화면 위치 기반으로 동적 배치
	-- 화면 하단에 공간 부족 시 위로 펼침 + 오버레이 표시
	listFrame:SetScript("OnShow", function()
		_activeDropdownList = listFrame
		local overlay = GetDropdownOverlay()
		overlay:Show()

		listFrame:ClearAllPoints()
		local scale = dropdown:GetEffectiveScale()
		local uiScale = UIParent:GetEffectiveScale()
		local left = dropdown:GetLeft() * scale / uiScale
		local bottom = dropdown:GetBottom() * scale / uiScale
		local top = dropdown:GetTop() * scale / uiScale
		local listH = listFrame:GetHeight()

		if bottom - listH - 2 < 0 then
			-- 화면 하단 공간 부족 → 위로 펼침
			listFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, top + 2)
		else
			-- 기본: 아래로 펼침
			listFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, bottom - 2)
		end
		listFrame:SetWidth(dropdown:GetWidth() * scale / uiScale)
	end)

	-- [DF-FIX] listFrame 닫힐 때 오버레이 정리
	listFrame:SetScript("OnHide", function()
		local overlay = GetDropdownOverlay()
		overlay:Hide()
		if _activeDropdownList == listFrame then
			_activeDropdownList = nil
		end
	end)

	-- [DF-FIX] 드롭다운이 숨겨지면 listFrame도 닫기 (UIParent 부착이라 자동 안 됨)
	dropdown:SetScript("OnHide", function()
		listFrame:Hide()
	end)

	self:SetTooltips(dropdown, "ANCHOR_TOPLEFT", 0, 3, ...)

	return dropdown
end

-----------------------------------------
-- CreateColorPicker
-----------------------------------------
function Widgets:CreateColorPicker(parent, label, hasOpacity, onChange)
	local cp = CreateFrame("Button", nil, parent, "BackdropTemplate")
	cp:SetSize(14, 14)
	cp:SetBackdrop({
		bgFile = WHITE_TEXTURE,
		edgeFile = WHITE_TEXTURE,
		edgeSize = 1,
	})
	cp:SetBackdropBorderColor(0, 0, 0, 1)

	cp.label = cp:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	cp.label:SetText(label)
	cp.label:SetPoint("LEFT", cp, "RIGHT", 5, 0)

	local cpBorderActive = SL and SL.Colors.border.active or {0.40, 0.40, 0.40, 0.70}
	cp:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(cpBorderActive[1], cpBorderActive[2], cpBorderActive[3], cpBorderActive[4] or 0.70)
	end)
	cp:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	end)

	cp.color = {1, 1, 1, 1}
	cp.hasOpacity = hasOpacity
	cp.onChange = onChange

	function cp:SetColor(r, g, b, a)
		if type(r) == "table" then
			cp.color = {r[1], r[2], r[3], r[4] or 1}
		else
			cp.color = {r, g, b, a or 1}
		end
		cp:SetBackdropColor(cp.color[1], cp.color[2], cp.color[3], cp.color[4])
	end

	function cp:GetColor()
		return cp.color
	end

	cp:SetScript("OnClick", function()
		local r, g, b, a = unpack(cp.color)
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			opacity = a,
			hasOpacity = cp.hasOpacity,
			swatchFunc = function()
				local newR, newG, newB = ColorPickerFrame:GetColorRGB()
				local newA = cp.hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
				cp:SetColor(newR, newG, newB, newA)
				if cp.onChange then cp.onChange(newR, newG, newB, newA) end
			end,
			cancelFunc = function()
				cp:SetColor(r, g, b, a)
				if cp.onChange then cp.onChange(r, g, b, a) end
			end,
		})
	end)

	cp:SetScript("OnEnable", function()
		cp.label:SetTextColor(textHighlight[1], textHighlight[2], textHighlight[3], textHighlight[4] or 1)
	end)
	cp:SetScript("OnDisable", function()
		cp.label:SetTextColor(disabledColor[1], disabledColor[2], disabledColor[3], disabledColor[4] or 1)
	end)

	return cp
end

-----------------------------------------
-- CreateEditBox
-----------------------------------------
function Widgets:CreateEditBox(parent, width, height, isNumeric)
	local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	self:StylizeFrame(eb)
	eb:SetFontObject(font_normal)
	eb:SetJustifyH("LEFT")
	eb:SetJustifyV("MIDDLE")
	eb:SetSize(width, height)
	eb:SetTextInsets(5, 5, 0, 0)
	eb:SetAutoFocus(false)
	eb:SetNumeric(isNumeric)

	-- Placeholder text
	local placeholder = eb:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	placeholder:SetPoint("LEFT", 5, 0)
	placeholder:SetTextColor(disabledColor[1], disabledColor[2], disabledColor[3], disabledColor[4] or 1)
	placeholder:Hide()
	eb.placeholder = placeholder

	function eb:SetPlaceholder(text)
		placeholder:SetText(text)
		if self:GetText() == "" then
			placeholder:Show()
		end
	end

	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
		placeholder:Hide()
	end)
	eb:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		if self:GetText() == "" then
			placeholder:Show()
		end
	end)
	eb:SetScript("OnTextChanged", function(self)
		if self:GetText() == "" and not self:HasFocus() then
			placeholder:Show()
		else
			placeholder:Hide()
		end
	end)
	eb:SetScript("OnDisable", function(self) self:SetTextColor(0.5, 0.5, 0.5, 1) end)
	eb:SetScript("OnEnable", function(self) self:SetTextColor(1, 1, 1, 1) end)

	return eb
end

-----------------------------------------
-- CreateScrollFrame
-----------------------------------------
function Widgets:CreateScrollFrame(parent)
	-- Simple scroll frame without default template (cleaner)
	local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
	parent.scrollFrame = scrollFrame
	scrollFrame:SetPoint("TOPLEFT", 5, -5)
	scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)
	scrollFrame:EnableMouseWheel(true)

	local content = CreateFrame("Frame", nil, scrollFrame)
	scrollFrame.content = content
	content:SetWidth(scrollFrame:GetWidth() or (parent:GetWidth() - 10))
	content:SetHeight(1)
	scrollFrame:SetScrollChild(content)

	-- Mouse wheel scrolling (CDM style: safe scroll range)
	local function OnMouseWheel(self, delta)
		local ok = pcall(function()
			local current = scrollFrame:GetVerticalScroll()
			local childH = content:GetHeight() or 0
			local frameH = scrollFrame:GetHeight() or 0
			local maxScroll = math.max(0, childH - frameH)
			local newScroll = math.max(0, math.min(maxScroll, current - (delta * 40)))
			scrollFrame:SetVerticalScroll(newScroll)
		end)
	end
	scrollFrame:SetScript("OnMouseWheel", OnMouseWheel)

	-- Update content width when parent resizes
	scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
		content:SetWidth(w)
	end)

	function scrollFrame:SetContentHeight(height)
		content:SetHeight(height)
	end

	-- [DF-FIX] LoadPage에서 스크롤 프레임 높이 재계산 시 사용
	-- 위젯 렌더링이 늦게 되는 경우를 대비하여 여러 번 호출
	function scrollFrame:UpdateContentHeightDelayed(contentFrame)
		if contentFrame.scrollFrame then
			contentFrame.scrollFrame:ResetScroll()
			-- 다중 타이밍 업데이트: 위젯 렌더링 완료 보장
			for _, delay in ipairs({ 0.05, 0.2, 0.5 }) do
				C_Timer.After(delay, function()
					if contentFrame.scrollFrame and contentFrame.scrollFrame.UpdateContentHeight then
						contentFrame.scrollFrame:UpdateContentHeight()
					end
				end)
			end
		end
	end

	function scrollFrame:ResetScroll()
		scrollFrame:SetVerticalScroll(0)
	end

	-- 자식 위젯의 content 높이를 자동 계산 (재귀적으로 최하단 탐색)
	-- CDM 패턴: 높이 설정 후 현재 스크롤 위치도 안전 범위로 clamp
	function scrollFrame:UpdateContentHeight()
		local function GetDeepBottom(frame, parentOffsetY)
			local maxBottom = 0
			-- 자식 프레임 탐색
			local ok1, children = pcall(frame.GetChildren, frame)
			if ok1 and children then
				for _, child in ipairs({ children }) do
					if child and child:IsShown() then
						local nPoints = child:GetNumPoints()
						if nPoints > 0 then
							local ok2, _, _, _, _, offsetY = pcall(child.GetPoint, child)
							if ok2 then
								local absY = parentOffsetY + (-(offsetY or 0))
								local h = child:GetHeight() or 0
								local bottom = absY + h
								if bottom > maxBottom then maxBottom = bottom end
								-- 재귀: 자식의 자식도 탐색
								local deepBottom = GetDeepBottom(child, absY)
								if deepBottom > maxBottom then maxBottom = deepBottom end
							end
						end
					end
				end
			end
			-- Region (FontString 등)
			local ok3, regions = pcall(frame.GetRegions, frame)
			if ok3 and regions then
				for _, region in ipairs({ regions }) do
					if region and region:IsShown() and region.GetPoint then
						local ok4, _, _, _, _, offsetY = pcall(region.GetPoint, region)
						if ok4 then
							local bottom = parentOffsetY + (-(offsetY or 0)) + (region:GetHeight() or 0)
							if bottom > maxBottom then maxBottom = bottom end
						end
					end
				end
			end
			return maxBottom
		end

		local maxBottom = GetDeepBottom(content, 0)
		-- 최소 높이: 스크롤 영역보다 작으면 스크롤 불필요
		local minHeight = scrollFrame:GetHeight() or 100
		local newHeight = math.max(maxBottom + 30, minHeight)
		content:SetHeight(newHeight)
		
		-- CDM 패턴: 높이 변경 후 현재 스크롤 위치를 안전 범위로 clamp
		local currentScroll = scrollFrame:GetVerticalScroll()
		local maxScroll = math.max(0, newHeight - (scrollFrame:GetHeight() or 0))
		if currentScroll > maxScroll then
			scrollFrame:SetVerticalScroll(maxScroll)
		end
	end

	-- 자식 위젯에 마우스휠 이벤트 전파 (HookScript)
	function scrollFrame:PropagateMouseWheel(frame)
		if frame and frame.EnableMouseWheel then
			frame:EnableMouseWheel(true)
			frame:SetScript("OnMouseWheel", OnMouseWheel)
		end
	end

	return scrollFrame
end

-----------------------------------------
-- Enable/Disable Helper
-----------------------------------------
function Widgets:SetEnabled(isEnabled, ...)
	for _, widget in pairs({...}) do
		if widget:IsObjectType("FontString") then
			if isEnabled then
				widget:SetTextColor(1, 1, 1, 1)
			else
				widget:SetTextColor(0.5, 0.5, 0.5, 1)
			end
		elseif widget:IsObjectType("Texture") then
			widget:SetDesaturated(not isEnabled)
		elseif widget.SetEnabled then
			widget:SetEnabled(isEnabled)
		elseif isEnabled then
			widget:Show()
		else
			widget:Hide()
		end
	end
end

-----------------------------------------
-- CreateToggleButton (Modern On/Off Switch)
-----------------------------------------
function Widgets:CreateToggleButton(parent, label, onChange)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(40 + (label and 100 or 0), 20)

	local toggle = CreateFrame("Button", nil, container, "BackdropTemplate")
	toggle:SetSize(40, 20)
	toggle:SetPoint("LEFT", 0, 0)

	toggle.value = false
	toggle.onChange = onChange

	-- Track background
	toggle:SetBackdrop({
		bgFile = WHITE_TEXTURE,
		edgeFile = WHITE_TEXTURE,
		edgeSize = 1,
	})
	toggle:SetBackdropBorderColor(0, 0, 0, 1)

	-- Knob
	toggle.knob = toggle:CreateTexture(nil, "OVERLAY")
	toggle.knob:SetSize(16, 16)
	toggle.knob:SetTexture(WHITE_TEXTURE)
	toggle.knob:SetVertexColor(1, 1, 1)

	-- Label
	if label then
		toggle.label = container:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		toggle.label:SetText(label)
		toggle.label:SetPoint("LEFT", toggle, "RIGHT", 8, 0)
		toggle.label:SetJustifyH("LEFT")
	end

	function toggle:SetValue(value)
		self.value = value
		if value then
			self:SetBackdropColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
			self.knob:ClearAllPoints()
			self.knob:SetPoint("RIGHT", -2, 0)
		else
			self:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
			self.knob:ClearAllPoints()
			self.knob:SetPoint("LEFT", 2, 0)
		end
	end

	function toggle:GetValue()
		return self.value
	end

	toggle:SetScript("OnClick", function(self)
		self:SetValue(not self.value)
		PlaySound(self.value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if self.onChange then
			self.onChange(self.value)
		end
	end)

	toggle:SetScript("OnEnter", function(self)
		if self.value then
			self:SetBackdropColor(accentColor[1], accentColor[2], accentColor[3], 1)
		else
			self:SetBackdropColor(0.4, 0.4, 0.4, 0.8)
		end
	end)

	toggle:SetScript("OnLeave", function(self)
		if self.value then
			self:SetBackdropColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
		else
			self:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
		end
	end)

	toggle:SetValue(false)

	container.toggle = toggle
	container.SetValue = function(_, v) toggle:SetValue(v) end
	container.GetValue = function() return toggle:GetValue() end

	return container
end

-----------------------------------------
-- CreateSearchBox
-----------------------------------------
function Widgets:CreateSearchBox(parent, width)
	local search = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	search:SetSize(width, 24)
	self:StylizeFrame(search)

	-- Search icon
	search.icon = search:CreateTexture(nil, "ARTWORK")
	search.icon:SetSize(14, 14)
	search.icon:SetPoint("LEFT", 6, 0)
	search.icon:SetTexture([[Interface\Common\UI-Searchbox-Icon]])
	search.icon:SetVertexColor(0.6, 0.6, 0.6)

	-- EditBox
	search.editBox = CreateFrame("EditBox", nil, search)
	search.editBox:SetPoint("LEFT", search.icon, "RIGHT", 4, 0)
	search.editBox:SetPoint("RIGHT", -24, 0)
	search.editBox:SetHeight(20)
	search.editBox:SetFontObject(font_normal)
	search.editBox:SetAutoFocus(false)
	search.editBox:SetJustifyH("LEFT")

	-- Placeholder text
	search.placeholder = search:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	search.placeholder:SetText("검색...")
	search.placeholder:SetTextColor(0.5, 0.5, 0.5)
	search.placeholder:SetPoint("LEFT", search.editBox, "LEFT", 0, 0)
	search.placeholder:SetJustifyH("LEFT")

	-- Clear button
	search.clearBtn = CreateFrame("Button", nil, search)
	search.clearBtn:SetSize(16, 16)
	search.clearBtn:SetPoint("RIGHT", -4, 0)
	search.clearBtn:SetNormalTexture([[Interface\Buttons\UI-StopButton]])
	search.clearBtn:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
	search.clearBtn:Hide()

	search.clearBtn:SetScript("OnEnter", function(self)
		self:GetNormalTexture():SetVertexColor(1, 0.3, 0.3)
	end)
	search.clearBtn:SetScript("OnLeave", function(self)
		self:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
	end)
	search.clearBtn:SetScript("OnClick", function()
		search.editBox:SetText("")
		search.editBox:ClearFocus()
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
	end)

	search.editBox:SetScript("OnTextChanged", function(self, userInput)
		local text = self:GetText()
		search.placeholder:SetShown(text == "")
		search.clearBtn:SetShown(text ~= "")
		if search.onTextChanged then
			search.onTextChanged(text)
		end
	end)

	search.editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	search.editBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)

	function search:SetOnTextChanged(func)
		search.onTextChanged = func
	end

	function search:Clear()
		search.editBox:SetText("")
	end

	function search:GetText()
		return search.editBox:GetText()
	end

	function search:SetText(text)
		search.editBox:SetText(text)
	end

	return search
end

-----------------------------------------
-- CreateCategoryButton (TreeView Node)
-----------------------------------------
function Widgets:CreateCategoryButton(parent, data, level)
	local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
	btn:SetHeight(22)

	btn.data = data
	btn.level = level or 0
	btn.isExpanded = false
	btn.isSelected = false

	-- Background
	btn:SetBackdrop({
		bgFile = WHITE_TEXTURE,
	})
	btn:SetBackdropColor(0, 0, 0, 0)

	local indent = btn.level * 16

	-- Expand/Collapse arrow (if has children)
	if data.children and #data.children > 0 then
		btn.arrow = btn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		btn.arrow:SetPoint("LEFT", indent + 4, 0)
		btn.arrow:SetText("▶")
		btn.arrow:SetTextColor(0.6, 0.6, 0.6)
	end

	-- Icon (optional)
	local iconOffset = (data.children and #data.children > 0) and 16 or 0
	if data.icon then
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetSize(16, 16)
		btn.icon:SetPoint("LEFT", indent + 4 + iconOffset, 0)
		btn.icon:SetTexture(data.icon)
		iconOffset = iconOffset + 20
	end

	-- Text
	btn.text = btn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	btn.text:SetPoint("LEFT", indent + 4 + iconOffset, 0)
	btn.text:SetPoint("RIGHT", -4, 0)
	btn.text:SetJustifyH("LEFT")
	btn.text:SetText(data.text or data.id)
	btn.text:SetTextColor(0.85, 0.85, 0.85)

	function btn:SetExpanded(expanded)
		self.isExpanded = expanded
		if self.arrow then
			self.arrow:SetText(expanded and "▼" or "▶")
		end
	end

	function btn:SetSelected(selected)
		self.isSelected = selected
		if selected then
			self:SetBackdropColor(accentColor[1], accentColor[2], accentColor[3], 0.3)
			self.text:SetTextColor(1, 1, 1)
			if self.arrow then self.arrow:SetTextColor(1, 1, 1) end
		else
			self:SetBackdropColor(0, 0, 0, 0)
			self.text:SetTextColor(0.85, 0.85, 0.85)
			if self.arrow then self.arrow:SetTextColor(0.6, 0.6, 0.6) end
		end
	end

	btn:SetScript("OnEnter", function(self)
		if not self.isSelected then
			self:SetBackdropColor(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4])
		end
	end)

	btn:SetScript("OnLeave", function(self)
		if not self.isSelected then
			self:SetBackdropColor(0, 0, 0, 0)
		end
	end)

	btn:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
		if self.onClick then
			self.onClick(self)
		end
	end)

	return btn
end

-----------------------------------------
-- Anchor Points List
-----------------------------------------
local anchorPoints = {
	"TOPLEFT", "TOP", "TOPRIGHT",
	"LEFT", "CENTER", "RIGHT",
	"BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

local anchorPointLabels = {
	TOPLEFT = "좌상단",
	TOP = "상단",
	TOPRIGHT = "우상단",
	LEFT = "좌측",
	CENTER = "중앙",
	RIGHT = "우측",
	BOTTOMLEFT = "좌하단",
	BOTTOM = "하단",
	BOTTOMRIGHT = "우하단",
}

-----------------------------------------
-- CreateAnchorDropdown
-----------------------------------------
function Widgets:CreateAnchorDropdown(parent, width, label, onChange)
	local dropdown = self:CreateDropdown(parent, width)

	if label then
		dropdown.labelText = dropdown:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
		dropdown.labelText:SetText(label)
		dropdown.labelText:SetPoint("BOTTOM", dropdown, "TOP", 0, 2)
	end

	local items = {}
	for _, point in ipairs(anchorPoints) do
		table.insert(items, {
			text = anchorPointLabels[point] or point,
			value = point,
			onClick = function(value)
				if onChange then onChange(value) end
			end,
		})
	end
	dropdown:SetItems(items)

	function dropdown:SetAnchor(point)
		dropdown:SetSelected(point)
	end

	function dropdown:GetAnchor()
		return dropdown:GetSelected()
	end

	return dropdown
end

-----------------------------------------
-- CreatePositionEditor
-----------------------------------------
function Widgets:CreatePositionEditor(parent, width, onChange)
	local editor = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	editor:SetSize(width or 280, 100)

	editor.position = {
		point = "CENTER",
		relativePoint = "CENTER",
		offsetX = 0,
		offsetY = 0,
	}
	editor.onChange = onChange

	-- Title
	local title = editor:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_TITLE")
	title:SetText("위치")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetTextColor(accentColor[1], accentColor[2], accentColor[3])

	-- Point dropdown
	local pointLabel = editor:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	pointLabel:SetText("기준점")
	pointLabel:SetPoint("TOPLEFT", 0, -22)

	local pointDropdown = self:CreateDropdown(editor, 90)
	pointDropdown:SetPoint("TOPLEFT", pointLabel, "BOTTOMLEFT", 0, -2)
	local pointItems = {}
	for _, p in ipairs(anchorPoints) do
		table.insert(pointItems, {
			text = anchorPointLabels[p] or p,
			value = p,
			onClick = function(value)
				editor.position.point = value
				if editor.onChange then editor.onChange(editor.position) end
			end,
		})
	end
	pointDropdown:SetItems(pointItems)
	editor.pointDropdown = pointDropdown

	-- RelativePoint dropdown
	local relLabel = editor:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	relLabel:SetText("상대 기준점")
	relLabel:SetPoint("LEFT", pointLabel, "RIGHT", 100, 0)

	local relDropdown = self:CreateDropdown(editor, 90)
	relDropdown:SetPoint("TOPLEFT", relLabel, "BOTTOMLEFT", 0, -2)
	local relItems = {}
	for _, p in ipairs(anchorPoints) do
		table.insert(relItems, {
			text = anchorPointLabels[p] or p,
			value = p,
			onClick = function(value)
				editor.position.relativePoint = value
				if editor.onChange then editor.onChange(editor.position) end
			end,
		})
	end
	relDropdown:SetItems(relItems)
	editor.relDropdown = relDropdown

	-- OffsetX slider
	local offsetXSlider = self:CreateSlider("X 오프셋", editor, -150, 150, 120, 1, nil, function(value)
		editor.position.offsetX = value
		if editor.onChange then editor.onChange(editor.position) end
	end)
	offsetXSlider:SetPoint("TOPLEFT", pointDropdown, "BOTTOMLEFT", 0, -30)
	editor.offsetXSlider = offsetXSlider

	-- OffsetY slider
	local offsetYSlider = self:CreateSlider("Y 오프셋", editor, -150, 150, 120, 1, nil, function(value)
		editor.position.offsetY = value
		if editor.onChange then editor.onChange(editor.position) end
	end)
	offsetYSlider:SetPoint("LEFT", offsetXSlider, "RIGHT", 30, 0)
	editor.offsetYSlider = offsetYSlider

	function editor:SetPosition(pos)
		if not pos then return end
		self.position = {
			point = pos.point or "CENTER",
			relativePoint = pos.relativePoint or "CENTER",
			offsetX = pos.offsetX or 0,
			offsetY = pos.offsetY or 0,
		}
		pointDropdown:SetSelected(self.position.point)
		relDropdown:SetSelected(self.position.relativePoint)
		offsetXSlider:SetValue(self.position.offsetX)
		offsetYSlider:SetValue(self.position.offsetY)
	end

	function editor:GetPosition()
		return self.position
	end

	return editor
end

-----------------------------------------
-- CreateFontSelector
-----------------------------------------
function Widgets:CreateFontSelector(parent, width, onChange)
	local selector = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	selector:SetSize(width or 280, 100)

	selector.fontOpt = {
		size = 12,
		outline = "OUTLINE",
		shadow = false,
		style = STANDARD_TEXT_FONT,
		justify = "CENTER",
	}
	selector.onChange = onChange

	-- Title
	local title = selector:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_TITLE")
	title:SetText("폰트")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetTextColor(accentColor[1], accentColor[2], accentColor[3])

	-- Size slider
	local sizeSlider = self:CreateSlider("크기", selector, 6, 32, 80, 1, nil, function(value)
		selector.fontOpt.size = value
		if selector.onChange then selector.onChange(selector.fontOpt) end
	end)
	sizeSlider:SetPoint("TOPLEFT", 0, -25)
	selector.sizeSlider = sizeSlider

	-- Outline dropdown
	local outlineLabel = selector:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	outlineLabel:SetText("외곽선")
	outlineLabel:SetPoint("LEFT", sizeSlider, "RIGHT", 30, 10)

	local outlineDropdown = self:CreateDropdown(selector, 100)
	outlineDropdown:SetPoint("TOPLEFT", outlineLabel, "BOTTOMLEFT", 0, -2)
	outlineDropdown:SetItems({
		{ text = "없음", value = "NONE" },
		{ text = "얇게", value = "OUTLINE" },
		{ text = "두껍게", value = "THICKOUTLINE" },
	})
	outlineDropdown:SetOnSelect(function(value)
		selector.fontOpt.outline = value
		if selector.onChange then selector.onChange(selector.fontOpt) end
	end)
	selector.outlineDropdown = outlineDropdown

	-- Shadow checkbox
	local shadowCheck = self:CreateCheckButton(selector, "그림자", function(checked)
		selector.fontOpt.shadow = checked
		if selector.onChange then selector.onChange(selector.fontOpt) end
	end)
	shadowCheck:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -25)
	selector.shadowCheck = shadowCheck

	-- Justify dropdown
	local justifyLabel = selector:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	justifyLabel:SetText("정렬")
	justifyLabel:SetPoint("LEFT", shadowCheck, "RIGHT", 80, 0)

	local justifyDropdown = self:CreateDropdown(selector, 80)
	justifyDropdown:SetPoint("LEFT", justifyLabel, "RIGHT", 10, 0)
	justifyDropdown:SetItems({
		{ text = "왼쪽", value = "LEFT" },
		{ text = "중앙", value = "CENTER" },
		{ text = "오른쪽", value = "RIGHT" },
	})
	justifyDropdown:SetOnSelect(function(value)
		selector.fontOpt.justify = value
		if selector.onChange then selector.onChange(selector.fontOpt) end
	end)
	selector.justifyDropdown = justifyDropdown

	function selector:SetFont(fontOpt)
		if not fontOpt then return end
		self.fontOpt = {
			size = fontOpt.size or 12,
			outline = fontOpt.outline or "OUTLINE",
			shadow = fontOpt.shadow or false,
			style = fontOpt.style or STANDARD_TEXT_FONT,
			justify = fontOpt.justify or "CENTER",
		}
		sizeSlider:SetValue(self.fontOpt.size)
		outlineDropdown:SetSelected(self.fontOpt.outline)
		shadowCheck:SetChecked(self.fontOpt.shadow)
		justifyDropdown:SetSelected(self.fontOpt.justify)
	end

	function selector:GetFont()
		return self.fontOpt
	end

	return selector
end

-----------------------------------------
-- CreateEnhancedColorPicker
-----------------------------------------
function Widgets:CreateEnhancedColorPicker(parent, label, hasOpacity, onChange)
	local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	container:SetSize(200, 25)

	container.colorOpt = {
		rgb = { 1, 1, 1 },
		type = "custom",
	}
	container.hasOpacity = hasOpacity
	container.onChange = onChange

	-- Color swatch button
	local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
	swatch:SetSize(18, 18)
	swatch:SetPoint("LEFT", 0, 0)
	swatch:SetBackdrop({
		bgFile = WHITE_TEXTURE,
		edgeFile = WHITE_TEXTURE,
		edgeSize = 1,
	})
	swatch:SetBackdropBorderColor(0, 0, 0, 1)
	container.swatch = swatch

	-- Label
	local labelText = container:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
	labelText:SetText(label or "색상")
	labelText:SetPoint("LEFT", swatch, "RIGHT", 5, 0)
	container.label = labelText

	-- Type dropdown
	local typeDropdown = self:CreateDropdown(container, 90)
	typeDropdown:SetPoint("LEFT", labelText, "RIGHT", 10, 0)
	typeDropdown:SetItems({
		{ text = "사용자 정의", value = "custom" },
		{ text = "직업 색상", value = "class_color" },
		{ text = "기력 색상", value = "power_color" },
		{ text = "진영 색상", value = "reaction_color" },
		{ text = "체력 그라데이션", value = "health_gradient" },
	})
	typeDropdown:SetOnSelect(function(value)
		container.colorOpt.type = value
		if value == "class_color" then
			local classColor = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
			if classColor then
				container.colorOpt.rgb = { classColor.r, classColor.g, classColor.b }
				swatch:SetBackdropColor(classColor.r, classColor.g, classColor.b, 1)
			end
		end
		if container.onChange then container.onChange(container.colorOpt) end
	end)
	container.typeDropdown = typeDropdown

	-- Color picker click
	swatch:SetScript("OnClick", function()
		local r, g, b = container.colorOpt.rgb[1], container.colorOpt.rgb[2], container.colorOpt.rgb[3]
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			opacity = 1,
			hasOpacity = container.hasOpacity,
			swatchFunc = function()
				local newR, newG, newB = ColorPickerFrame:GetColorRGB()
				container.colorOpt.rgb = { newR, newG, newB }
				container.colorOpt.type = "custom"
				swatch:SetBackdropColor(newR, newG, newB, 1)
				typeDropdown:SetSelected("custom")
				if container.onChange then container.onChange(container.colorOpt) end
			end,
			cancelFunc = function()
				swatch:SetBackdropColor(r, g, b, 1)
			end,
		})
	end)

	swatch:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
	end)
	swatch:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0, 0, 0, 1)
	end)

	function container:SetColor(colorOpt)
		if not colorOpt then return end
		self.colorOpt = {
			rgb = colorOpt.rgb or { 1, 1, 1 },
			type = colorOpt.type or "custom",
		}
		swatch:SetBackdropColor(self.colorOpt.rgb[1], self.colorOpt.rgb[2], self.colorOpt.rgb[3], 1)
		typeDropdown:SetSelected(self.colorOpt.type)
	end

	function container:GetColor()
		return self.colorOpt
	end

	container:SetColor({ rgb = { 1, 1, 1 }, type = "custom" })

	return container
end

-----------------------------------------
-- CreateAuraFilterList
-----------------------------------------
function Widgets:CreateAuraFilterList(parent, width, height, onChange)
	local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	list:SetSize(width or 300, height or 200)
	self:StylizeFrame(list)

	list.spellIds = {}
	list.onChange = onChange

	-- Title
	local title = list:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_TITLE")
	title:SetText("주문 목록")
	title:SetPoint("TOPLEFT", 5, -5)
	title:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
	list.title = title

	-- Add button
	local addBtn = self:CreateButton(list, "+", "accent", { 24, 24 })
	addBtn:SetPoint("TOPRIGHT", -5, -3)

	-- Input editbox
	local inputBox = self:CreateEditBox(list, width - 40, 20, true)
	inputBox:SetPoint("TOPLEFT", 5, -25)
	list.inputBox = inputBox

	-- Scroll frame for list
	local scrollFrame = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 5, -50)
	scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

	local content = CreateFrame("Frame", nil, scrollFrame)
	content:SetWidth(width - 30)
	content:SetHeight(1)
	scrollFrame:SetScrollChild(content)
	list.content = content

	-- Style scrollbar
	local scrollBar = scrollFrame.ScrollBar
	if scrollBar then
		scrollBar:ClearAllPoints()
		scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", -16, -16)
		scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -16, 16)
	end

	list.items = {}

	local function RefreshList()
		for _, item in ipairs(list.items) do
			item:Hide()
			item:ClearAllPoints()
		end
		wipe(list.items)

		local yOffset = 0
		for spellId, _ in pairs(list.spellIds) do
			local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
			row:SetSize(content:GetWidth(), 22)
			row:SetPoint("TOPLEFT", 0, yOffset)

			-- Spell ID text
			local idText = row:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
			idText:SetText(tostring(spellId))
			idText:SetPoint("LEFT", 5, 0)

			-- Spell name (from cache if available)
			local spellInfo = C_Spell.GetSpellInfo(spellId)
			if spellInfo and spellInfo.name then
				local nameText = row:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
				nameText:SetText(spellInfo.name)
				nameText:SetPoint("LEFT", idText, "RIGHT", 10, 0)
				nameText:SetTextColor(0.6, 0.6, 0.6)
			end

			-- Remove button
			local removeBtn = CreateFrame("Button", nil, row)
			removeBtn:SetSize(16, 16)
			removeBtn:SetPoint("RIGHT", -2, 0)
			removeBtn:SetNormalTexture([[Interface\Buttons\UI-StopButton]])
			removeBtn:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
			removeBtn:SetScript("OnEnter", function(self)
				self:GetNormalTexture():SetVertexColor(1, 0.3, 0.3)
			end)
			removeBtn:SetScript("OnLeave", function(self)
				self:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
			end)
			removeBtn:SetScript("OnClick", function()
				list.spellIds[spellId] = nil
				RefreshList()
				if list.onChange then list.onChange(list.spellIds) end
			end)

			table.insert(list.items, row)
			yOffset = yOffset - 22
		end

		content:SetHeight(math.max(1, math.abs(yOffset)))
	end

	-- Add spell
	addBtn:SetScript("OnClick", function()
		local text = inputBox:GetText()
		local spellId = tonumber(text)
		if spellId and spellId > 0 then
			list.spellIds[spellId] = true
			inputBox:SetText("")
			RefreshList()
			if list.onChange then list.onChange(list.spellIds) end
		end
	end)

	inputBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local spellId = tonumber(self:GetText())
		if spellId and spellId > 0 then
			list.spellIds[spellId] = true
			self:SetText("")
			RefreshList()
			if list.onChange then list.onChange(list.spellIds) end
		end
	end)

	function list:SetSpellIds(ids)
		wipe(self.spellIds)
		if ids then
			for id, v in pairs(ids) do
				self.spellIds[id] = v
			end
		end
		RefreshList()
	end

	function list:GetSpellIds()
		return self.spellIds
	end

	function list:SetTitle(text)
		title:SetText(text)
	end

	return list
end

-----------------------------------------
-- CreateSizeEditor
-----------------------------------------
function Widgets:CreateSizeEditor(parent, width, onChange)
	local editor = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	editor:SetSize(width or 200, 60)

	editor.size = { width = 20, height = 20 }
	editor.onChange = onChange

	-- Title
	local title = editor:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_TITLE")
	title:SetText("크기")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetTextColor(accentColor[1], accentColor[2], accentColor[3])

	-- Width slider
	local widthSlider = self:CreateSlider("너비", editor, 1, 500, 90, 1, nil, function(value)
		editor.size.width = value
		if editor.onChange then editor.onChange(editor.size) end
	end)
	widthSlider:SetPoint("TOPLEFT", 0, -20)
	editor.widthSlider = widthSlider

	-- Height slider
	local heightSlider = self:CreateSlider("높이", editor, 1, 500, 90, 1, nil, function(value)
		editor.size.height = value
		if editor.onChange then editor.onChange(editor.size) end
	end)
	heightSlider:SetPoint("LEFT", widthSlider, "RIGHT", 20, 0)
	editor.heightSlider = heightSlider

	function editor:SetSize(size)
		if not size then return end
		self.size = {
			width = size.width or size[1] or 20,
			height = size.height or size[2] or 20,
		}
		widthSlider:SetValue(self.size.width)
		heightSlider:SetValue(self.size.height)
	end

	function editor:GetSize()
		return self.size
	end

	return editor
end

-----------------------------------------
-- CreateTreeView
-----------------------------------------
function Widgets:CreateTreeView(parent, width, height)
	local tree = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	tree:SetSize(width, height)

	-- Scroll frame (no template - we'll make our own minimal scrollbar)
	local scrollFrame = CreateFrame("ScrollFrame", nil, tree)
	scrollFrame:SetPoint("TOPLEFT", 0, 0)
	scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
	scrollFrame:EnableMouseWheel(true)

	local content = CreateFrame("Frame", nil, scrollFrame)
	content:SetWidth(width - 5)
	content:SetHeight(1)
	scrollFrame:SetScrollChild(content)

	tree.scrollFrame = scrollFrame
	tree.content = content
	tree.nodes = {}
	tree.data = {}
	tree.expanded = {}
	tree.selected = nil
	tree.onSelect = nil
	tree.filterText = ""

	-- Mouse wheel scrolling
	scrollFrame:SetScript("OnMouseWheel", function(self, delta)
		local current = self:GetVerticalScroll()
		local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
		local newScroll = math.max(0, math.min(maxScroll, current - (delta * 22)))
		self:SetVerticalScroll(newScroll)
	end)

	function tree:SetData(data)
		self.data = data
		-- Default expand top-level
		for _, item in ipairs(data) do
			self.expanded[item.id] = true
		end
		self:Refresh()
	end

	function tree:Refresh()
		-- Clear existing nodes
		for _, node in ipairs(self.nodes) do
			node:Hide()
			node:ClearAllPoints()
		end
		wipe(self.nodes)

		local yOffset = 0
		local nodeWidth = self.content:GetWidth()

		local function matchesFilter(item)
			if self.filterText == "" then return true end
			local searchText = self.filterText:lower()
			if item.text and item.text:lower():find(searchText, 1, true) then
				return true
			end
			if item.children then
				for _, child in ipairs(item.children) do
					if matchesFilter(child) then return true end
				end
			end
			return false
		end

		local function renderNode(item, level)
			if not matchesFilter(item) then return end

			local node = Widgets:CreateCategoryButton(self.content, item, level)
			node:SetPoint("TOPLEFT", 0, yOffset)
			node:SetWidth(nodeWidth)
			node:SetExpanded(self.expanded[item.id])
			node:SetSelected(self.selected == item.id)

			node.onClick = function(btn)
				-- If has children, only toggle expand (don't load page)
				if item.children and #item.children > 0 then
					self.expanded[item.id] = not self.expanded[item.id]
					self:Refresh()
					return
				end

				-- Leaf node: select and load page
				self.selected = item.id
				-- [FIX] Refresh 먼저 호출 → onSelect 에러 시에도 선택 표시 갱신됨
				self:Refresh()

				-- Callback only for leaf nodes
				if self.onSelect then
					self.onSelect(item.id)
				end
			end

			table.insert(self.nodes, node)
			yOffset = yOffset - 22

			-- Render children if expanded
			if item.children and self.expanded[item.id] then
				for _, child in ipairs(item.children) do
					renderNode(child, level + 1)
				end
			end
		end

		for _, item in ipairs(self.data) do
			renderNode(item, 0)
		end

		self.content:SetHeight(math.max(1, math.abs(yOffset)))
	end

	function tree:SetOnSelect(func)
		self.onSelect = func
	end

	function tree:SelectCategory(categoryId)
		self.selected = categoryId

		-- Auto-expand parent categories
		local parts = {}
		for part in string.gmatch(categoryId, "[^.]+") do
			table.insert(parts, part)
		end

		local path = ""
		for i = 1, #parts - 1 do
			path = (path == "") and parts[i] or (path .. "." .. parts[i])
			self.expanded[path] = true
		end

		self:Refresh()

		if self.onSelect then
			self.onSelect(categoryId)
		end
	end

	function tree:ExpandCategory(categoryId)
		self.expanded[categoryId] = true
		self:Refresh()
	end

	function tree:CollapseCategory(categoryId)
		self.expanded[categoryId] = false
		self:Refresh()
	end

	function tree:ExpandAll()
		local function expandRecursive(items)
			for _, item in ipairs(items) do
				self.expanded[item.id] = true
				if item.children then
					expandRecursive(item.children)
				end
			end
		end
		expandRecursive(self.data)
		self:Refresh()
	end

	function tree:CollapseAll()
		wipe(self.expanded)
		self:Refresh()
	end

	function tree:Filter(searchText)
		self.filterText = searchText or ""
		-- When filtering, expand all matching parents
		if self.filterText ~= "" then
			self:ExpandAll()
		end
		self:Refresh()
	end

	function tree:GetSelected()
		return self.selected
	end

	return tree
end
