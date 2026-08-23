-- DDingUI Toolkit - CDM-aligned settings controls

local addonName, ns = ...
local Lib = LibStub("DDingUI-StyleLib-1.0")
local C = Lib.Colors
local F = Lib.Font
local Motion = Lib.Motion
local T = Lib.Tokens or {}
local PP = Lib.PP
local SOLID = Lib.Textures and Lib.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local ADDON_KEY = "MJToolkit"

local Controls = {}
ns.ToolkitControls = Controls

local function UnpackColor(color, fallbackAlpha)
    color = color or { 1, 1, 1, fallbackAlpha or 1 }
    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or fallbackAlpha or 1
end

local function Accent()
    local color = Lib.GetAccent(ADDON_KEY)
    return color[1], color[2], color[3]
end

local function ApplyBackdrop(frame, background, border)
    frame:SetBackdrop({
        bgFile = SOLID,
        edgeFile = SOLID,
        edgeSize = 1,
    })
    frame:SetBackdropColor(UnpackColor(background or C.bg.input))
    frame:SetBackdropBorderColor(UnpackColor(border or C.border.default))
end

local function DisablePixelSnap(texture)
    if PP and PP.DisablePixelSnap then
        PP.DisablePixelSnap(texture)
    elseif texture and texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
end

local function MakeFont(parent, size, color, text)
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    fontString:SetFont(F.path, math.max(1, tonumber(size) or F.normal), "")
    fontString:SetTextColor(UnpackColor(color or C.text.normal))
    fontString:SetText(text or "")
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.9)
    return fontString
end

local function SetTooltip(frame, text)
    if not frame or not text or text == "" then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function EnableRightClickMouselook(frame)
    if ns.EnableRightClickMouselook then
        ns:EnableRightClickMouselook(frame)
    elseif Lib.EnableRightClickMouselook then
        Lib.EnableRightClickMouselook(frame)
    end
end

local function CreateRow(parent, labelText, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, height or 30)

    local label = MakeFont(row, F.normal, C.text.normal, labelText)
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetPoint("RIGHT", row, "CENTER", -22, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    row.label = label
    return row
end

local function SetRowDisabled(row, disabled)
    row._disabled = disabled == true
    row:SetAlpha(row._disabled and 0.48 or 1)
    if row.control and row.control.SetEnabled then
        row.control:SetEnabled(not row._disabled)
    end
end

function Controls.CreateSeparator(parent, opts)
    opts = opts or {}
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetWidth(opts.width or parent:GetWidth() or 300)
    line:SetColorTexture(UnpackColor(opts.color or C.border.separator))
    DisablePixelSnap(line)
    return line
end

function Controls.CreateSectionHeader(parent, addonKey, text, opts)
    opts = opts or {}
    local r, g, b = Accent()
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, opts.isFirst and 36 or 48)

    local label = MakeFont(row, F.section, { r, g, b, 1 }, text)
    label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 10)
    label:SetJustifyH("LEFT")

    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 3)
    line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 3)
    line:SetHeight(1)
    line:SetColorTexture(r, g, b, 0.55)
    DisablePixelSnap(line)

    local cap = row:CreateTexture(nil, "OVERLAY")
    cap:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 0, 0)
    cap:SetSize(54, 1)
    cap:SetColorTexture(r, g, b, 1)
    DisablePixelSnap(cap)

    row.label = label
    return row
end

function Controls.CreateButton(parent, addonKey, text, onClick, opts)
    opts = opts or {}
    local r, g, b = Accent()
    local buttonColors = T.MakeButtonColors and T.MakeButtonColors({ r, g, b, 1 })
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(opts.width or 160, opts.height or 28)
    ApplyBackdrop(
        button,
        buttonColors and { buttonColors[1], buttonColors[2], buttonColors[3], buttonColors[4] } or C.bg.input,
        buttonColors and { buttonColors[9], buttonColors[10], buttonColors[11], buttonColors[12] } or C.border.default
    )
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local label = MakeFont(button, F.normal, C.text.normal, text)
    label:SetPoint("CENTER")
    button.label = label

    local hoverMotion
    local buttonHover = Motion and (Motion.ButtonHover or Motion.InterfaceButton)
    if buttonHover then
        hoverMotion = buttonHover(button, {
            normalBg = buttonColors and { buttonColors[1], buttonColors[2], buttonColors[3], buttonColors[4] } or C.bg.input,
            hoverBg = C.bg.hover,
            normalBorder = buttonColors and { buttonColors[9], buttonColors[10], buttonColors[11], buttonColors[12] } or C.border.default,
            hoverBorder = { r, g, b, 0.85 },
            text = label,
            normalText = C.text.normal,
            hoverText = C.text.highlight,
            duration = 0.10,
            bind = true,
        })
    else
        button:SetScript("OnEnter", function(self)
            self:SetBackdropColor(UnpackColor(C.bg.hover))
            self:SetBackdropBorderColor(r, g, b, 0.85)
            label:SetTextColor(UnpackColor(C.text.highlight))
        end)
        button:SetScript("OnLeave", function(self)
            self:SetBackdropColor(UnpackColor(C.bg.input))
            self:SetBackdropBorderColor(UnpackColor(C.border.default))
            label:SetTextColor(UnpackColor(C.text.normal))
        end)
    end

    button:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        self:SetBackdropColor(r, g, b, 0.42)
        label:SetPoint("CENTER", 0, -1)
    end)
    button:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        label:SetPoint("CENTER", 0, 0)
        if hoverMotion and hoverMotion.SetTarget then
            hoverMotion:SetTarget(self:IsMouseOver() and 1 or 0)
        else
            self:SetBackdropColor(UnpackColor(self:IsMouseOver() and C.bg.hover or C.bg.input))
        end
    end)
    if onClick then
        button:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "LeftButton" then
                onClick(self)
            end
        end)
    end

    function button:SetDisabledState(disabled)
        self:SetEnabled(not disabled)
        self:SetAlpha(disabled and 0.48 or 1)
    end

    SetTooltip(button, opts.tooltip)
    EnableRightClickMouselook(button)
    return button
end

function Controls.CreateCheckbox(parent, addonKey, labelText, default, opts)
    opts = opts or {}
    local r, g, b = Accent()
    local CB = T.CB or {
        BOX_R = 0.075, BOX_G = 0.113, BOX_B = 0.141,
        BRD_A = 0.25, ACT_BRD_A = 0.70, SIZE = 14, CHECK_INSET = 2,
    }
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(560, opts.height or 28)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local label = MakeFont(row, F.normal, C.text.normal, labelText)
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -42, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetSize(CB.SIZE, CB.SIZE)
    box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    ApplyBackdrop(box, { CB.BOX_R, CB.BOX_G, CB.BOX_B, 1 }, { 1, 1, 1, CB.BRD_A })

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", CB.CHECK_INSET, -CB.CHECK_INSET)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -CB.CHECK_INSET, CB.CHECK_INSET)
    fill:SetColorTexture(r, g, b, 1)
    DisablePixelSnap(fill)

    local check = MakeFont(box, 12, C.text.highlight, "")
    check:SetPoint("CENTER", box, "CENTER", 0, 0)

    row.checked = default == true

    local function Refresh()
        fill:SetShown(row.checked)
        check:SetText(row.checked and "" or "")
        box:SetBackdropBorderColor(UnpackColor(
            row.checked and { r, g, b, CB.ACT_BRD_A } or { 1, 1, 1, CB.BRD_A }
        ))
    end

    function row:SetChecked(value, silent)
        local nextValue = value == true
        local changed = self.checked ~= nextValue
        self.checked = nextValue
        Refresh()
        if changed and not silent and opts.onChange then
            opts.onChange(self.checked)
        end
    end

    function row:GetChecked()
        return self.checked
    end

    function row:SetDisabledState(disabled)
        SetRowDisabled(self, disabled)
    end

    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or self._disabled then return end
        self:SetChecked(not self.checked)
    end)
    row:SetScript("OnEnter", function()
        label:SetTextColor(UnpackColor(C.text.highlight))
        box:SetBackdropBorderColor(r, g, b, 0.9)
    end)
    row:SetScript("OnLeave", function()
        label:SetTextColor(UnpackColor(C.text.normal))
        Refresh()
    end)

    row.label = label
    row.box = box
    row.control = row
    Refresh()
    SetTooltip(row, opts.tooltip)
    EnableRightClickMouselook(row)
    return row
end

function Controls.CreateInputField(parent, addonKey, labelText, default, opts)
    opts = opts or {}
    local r, g, b = Accent()
    local row = CreateRow(parent, labelText, opts.height or 30)

    local editBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    editBox:SetSize(opts.inputWidth or 220, 24)
    editBox:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    ApplyBackdrop(editBox, C.bg.input, C.border.default)
    editBox:SetFont(F.path, math.max(1, F.normal), "")
    editBox:SetTextColor(UnpackColor(C.text.highlight))
    editBox:SetTextInsets(7, 7, 0, 0)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(opts.maxLetters or 256)
    editBox:SetText(default == nil and "" or tostring(default))
    if opts.numeric then editBox:SetNumeric(true) end

    local lastCommitted = editBox:GetText()
    local function Commit()
        local value = editBox:GetText()
        if value == lastCommitted then return end
        lastCommitted = value
        if opts.onEnter then opts.onEnter(value) end
        if opts.onChange then opts.onChange(value) end
    end

    editBox:SetScript("OnEnter", function(self)
        if not self:HasFocus() then
            self:SetBackdropBorderColor(r, g, b, 0.7)
        end
    end)
    editBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then
            self:SetBackdropBorderColor(UnpackColor(C.border.default))
        end
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(r, g, b, 1)
        self:HighlightText()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(UnpackColor(C.border.default))
        self:HighlightText(0, 0)
        Commit()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        Commit()
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(lastCommitted)
        self:ClearFocus()
    end)

    function row:SetValue(value, silent)
        local text = value == nil and "" or tostring(value)
        lastCommitted = text
        editBox:SetText(text)
        if not silent and opts.onChange then opts.onChange(text) end
    end

    function row:GetValue()
        return editBox:GetText()
    end

    function row:SetDisabledState(disabled)
        SetRowDisabled(self, disabled)
        editBox:EnableMouse(not disabled)
        editBox:EnableKeyboard(not disabled)
    end

    row.editBox = editBox
    row.control = editBox
    SetTooltip(row, opts.tooltip)
    EnableRightClickMouselook(row)
    return row
end

local function DecimalPlaces(step)
    local value = math.abs(tonumber(step) or 1)
    if value >= 1 then return 0 end
    if value >= 0.1 then return 1 end
    if value >= 0.01 then return 2 end
    return 3
end

function Controls.CreateSlider(parent, addonKey, labelText, minimum, maximum, step, default, opts)
    opts = opts or {}
    minimum = tonumber(minimum) or 0
    maximum = tonumber(maximum) or 100
    step = math.max(0.0001, tonumber(step) or 1)

    local r, g, b = Accent()
    local SL = T.SL or {
        TRACK_R = 0.08, TRACK_G = 0.10, TRACK_B = 0.12,
        TRACK_A = 0.95, TRACK_H = 4, FILL_A = 0.75, THUMB_SZ = 12,
    }
    local row = CreateRow(parent, labelText, opts.height or 36)

    local valueBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    valueBox:SetSize(54, 24)
    valueBox:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    ApplyBackdrop(valueBox, C.bg.input, C.border.default)
    valueBox:SetFont(F.path, math.max(1, F.small), "")
    valueBox:SetTextColor(UnpackColor(C.text.highlight))
    valueBox:SetTextInsets(4, 4, 0, 0)
    valueBox:SetJustifyH("CENTER")
    valueBox:SetAutoFocus(false)

    local track = CreateFrame("Frame", nil, row, "BackdropTemplate")
    track:SetHeight(SL.TRACK_H)
    track:SetPoint("LEFT", row, "CENTER", 12, 0)
    track:SetPoint("RIGHT", valueBox, "LEFT", -18, 0)
    ApplyBackdrop(track, { SL.TRACK_R, SL.TRACK_G, SL.TRACK_B, SL.TRACK_A }, { 0, 0, 0, 0 })

    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetHeight(SL.TRACK_H)
    fill:SetColorTexture(r, g, b, SL.FILL_A)
    DisablePixelSnap(fill)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 6)
    slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -6)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(math.max(8, SL.THUMB_SZ - 3), SL.THUMB_SZ + 1)
    thumb:SetColorTexture(r, g, b, 1)
    DisablePixelSnap(thumb)
    slider:SetThumbTexture(thumb)

    local decimals = DecimalPlaces(step)
    local formatString = "%." .. decimals .. "f"
    local updating = false
    local currentValue

    local function Normalize(value)
        value = tonumber(value) or minimum
        value = math.max(minimum, math.min(maximum, value))
        value = minimum + math.floor(((value - minimum) / step) + 0.5) * step
        return math.max(minimum, math.min(maximum, value))
    end

    local function UpdateVisual(value)
        local range = maximum - minimum
        local progress = range > 0 and ((value - minimum) / range) or 0
        fill:SetWidth(math.max(1, (track:GetWidth() or 1) * progress))
        valueBox:SetText(string.format(formatString, value))
    end

    local function SetValue(value, silent)
        value = Normalize(value)
        local changed = currentValue ~= value
        currentValue = value
        updating = true
        slider:SetValue(value)
        UpdateVisual(value)
        updating = false
        if changed and not silent and opts.onChange then opts.onChange(value) end
    end

    slider:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        value = Normalize(value)
        local changed = currentValue ~= value
        currentValue = value
        UpdateVisual(value)
        if changed and opts.onChange then opts.onChange(value) end
    end)
    slider:SetScript("OnMouseWheel", function(_, delta)
        if row._disabled then return end
        SetValue(slider:GetValue() + (delta > 0 and step or -step))
    end)
    slider:SetScript("OnEnter", function()
        thumb:SetColorTexture(1, 1, 1, 1)
    end)
    slider:SetScript("OnLeave", function()
        thumb:SetColorTexture(r, g, b, 1)
    end)
    track:SetScript("OnSizeChanged", function()
        UpdateVisual(slider:GetValue())
    end)

    valueBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(r, g, b, 1)
        self:HighlightText()
    end)
    valueBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(UnpackColor(C.border.default))
        SetValue(self:GetText())
    end)
    valueBox:SetScript("OnEnterPressed", function(self)
        SetValue(self:GetText())
        self:ClearFocus()
    end)
    valueBox:SetScript("OnEscapePressed", function(self)
        UpdateVisual(slider:GetValue())
        self:ClearFocus()
    end)

    function row:SetValue(value, silent)
        SetValue(value, silent)
    end

    function row:GetValue()
        return slider:GetValue()
    end

    function row:SetDisabledState(disabled)
        SetRowDisabled(self, disabled)
        slider:EnableMouse(not disabled)
        valueBox:EnableMouse(not disabled)
        valueBox:EnableKeyboard(not disabled)
    end

    row.slider = slider
    row.valueBox = valueBox
    row.control = slider
    SetValue(default, true)
    SetTooltip(row, opts.tooltip)
    EnableRightClickMouselook(row)
    return row
end

function Controls.CreateColor(parent, addonKey, labelText, default, opts)
    opts = opts or {}
    local r, g, b = Accent()
    local row = CreateRow(parent, labelText, opts.height or 30)
    local color = default or { 1, 1, 1, 1 }

    local function CreateSwatch(width)
        local button = CreateFrame("Button", nil, row, "BackdropTemplate")
        button:SetSize(width or 34, 20)
        ApplyBackdrop(button, C.bg.input, C.border.default)
        local texture = button:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
        texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        button:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(r, g, b, 1)
        end)
        button:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(UnpackColor(C.border.default))
        end)
        return button, texture
    end

    local supportsGradient = opts.supportsGradient == true
    local swatch, preview = CreateSwatch(supportsGradient and 50 or 34)
    swatch:SetPoint("RIGHT", row, "RIGHT", supportsGradient and -76 or 0, 0)
    local modeButton
    local endSwatch
    local endPreview
    local directionButton

    local function ReadColor()
        return color[1] or color.r or 1,
            color[2] or color.g or 1,
            color[3] or color.b or 1,
            color[4] or color.a or 1
    end

    local function Refresh()
        local baseR, baseG, baseB, baseA = ReadColor()
        local isGradient = supportsGradient and Lib.IsGradientBarColor and Lib.IsGradientBarColor(color)
        local endColor = color.gradientColor
        if type(endColor) ~= "table" then
            endColor = { baseR * 0.55, baseG * 0.55, baseB * 0.55, baseA }
        end
        if isGradient then
            preview:SetColorTexture(1, 1, 1, 1)
            preview:SetGradient(
                color.gradientOrientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL",
                CreateColor(baseR, baseG, baseB, baseA),
                CreateColor(UnpackColor(endColor))
            )
        else
            preview:SetColorTexture(baseR, baseG, baseB, baseA)
        end
        if not supportsGradient then return end

        modeButton.label:SetText(isGradient and (GetLocale() == "koKR" and "그라데이션" or "Gradient") or (GetLocale() == "koKR" and "단색" or "Solid"))
        endSwatch:SetShown(isGradient)
        directionButton:SetShown(isGradient)
        endPreview:SetColorTexture(UnpackColor(endColor))
        directionButton.label:SetText(color.gradientOrientation == "VERTICAL" and (GetLocale() == "koKR" and "세로" or "Vertical") or (GetLocale() == "koKR" and "가로" or "Horizontal"))
    end

    local function Apply(nextR, nextG, nextB, nextA, silent)
        local previous = color
        color = { nextR, nextG, nextB, nextA or 1 }
        if Lib.CopyBarColorMetadata then
            Lib.CopyBarColorMetadata(color, previous)
        end
        Refresh()
        if not silent and opts.onChange then
            opts.onChange(nextR, nextG, nextB, nextA or 1)
        end
    end

    local function OpenPicker(oldR, oldG, oldB, oldA, onApply, onCancel)
        local function PickerAlpha()
            if ColorPickerFrame.GetColorAlpha then
                return ColorPickerFrame:GetColorAlpha()
            end
            if OpacitySliderFrame then
                return 1 - OpacitySliderFrame:GetValue()
            end
            return oldA
        end
        local info = {
            r = oldR,
            g = oldG,
            b = oldB,
            opacity = 1 - oldA,
            hasOpacity = opts.hasAlpha == true,
            swatchFunc = function()
                local nextR, nextG, nextB = ColorPickerFrame:GetColorRGB()
                local nextA = opts.hasAlpha and PickerAlpha() or oldA
                onApply(nextR, nextG, nextB, nextA)
            end,
            opacityFunc = function()
                local nextR, nextG, nextB = ColorPickerFrame:GetColorRGB()
                onApply(nextR, nextG, nextB, PickerAlpha())
            end,
            cancelFunc = function()
                if onCancel then onCancel(oldR, oldG, oldB, oldA) end
            end,
        }
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame.hasOpacity = info.hasOpacity
            ColorPickerFrame.opacity = info.opacity
            ColorPickerFrame.func = info.swatchFunc
            ColorPickerFrame.opacityFunc = info.opacityFunc
            ColorPickerFrame.cancelFunc = info.cancelFunc
            ColorPickerFrame:SetColorRGB(oldR, oldG, oldB)
            ColorPickerFrame:Show()
        end
    end

    swatch:SetScript("OnClick", function()
        if row._disabled then return end
        local oldR, oldG, oldB, oldA = ReadColor()
        OpenPicker(oldR, oldG, oldB, oldA, function(nextR, nextG, nextB, nextA)
            Apply(nextR, nextG, nextB, nextA)
        end, function()
            Apply(oldR, oldG, oldB, oldA)
        end)
    end)

    if supportsGradient then
        local function CreateTextButton(width)
            local button = CreateFrame("Button", nil, row, "BackdropTemplate")
            button:SetSize(width, 20)
            ApplyBackdrop(button, C.bg.input, C.border.default)
            button.label = MakeFont(button, F.small, C.text.normal, "")
            button.label:SetPoint("CENTER")
            return button
        end

        modeButton = CreateTextButton(70)
        modeButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        endSwatch, endPreview = CreateSwatch(34)
        endSwatch:SetPoint("RIGHT", swatch, "LEFT", -4, 0)
        directionButton = CreateTextButton(48)
        directionButton:SetPoint("RIGHT", endSwatch, "LEFT", -4, 0)

        local function CommitGradient()
            Refresh()
            if opts.onGradientChange then opts.onGradientChange(color) end
        end

        modeButton:SetScript("OnClick", function()
            if row._disabled then return end
            local baseR, baseG, baseB, baseA = ReadColor()
            color.gradientMode = color.gradientMode == "GRADIENT" and "SOLID" or "GRADIENT"
            color.gradientColor = color.gradientColor or { baseR * 0.55, baseG * 0.55, baseB * 0.55, baseA }
            color.gradientOrientation = color.gradientOrientation or "HORIZONTAL"
            CommitGradient()
        end)

        directionButton:SetScript("OnClick", function()
            if row._disabled then return end
            color.gradientOrientation = color.gradientOrientation == "VERTICAL" and "HORIZONTAL" or "VERTICAL"
            CommitGradient()
        end)

        endSwatch:SetScript("OnClick", function()
            if row._disabled then return end
            local endColor = color.gradientColor or { ReadColor() }
            local oldColor = { UnpackColor(endColor) }
            OpenPicker(oldColor[1], oldColor[2], oldColor[3], oldColor[4], function(nextR, nextG, nextB, nextA)
                color.gradientColor = { nextR, nextG, nextB, nextA or 1 }
                CommitGradient()
            end, function()
                color.gradientColor = oldColor
                CommitGradient()
            end)
        end)
    end

    function row:SetColor(nextR, nextG, nextB, nextA, silent)
        Apply(nextR, nextG, nextB, nextA, silent)
    end

    function row:GetColor()
        return ReadColor()
    end

    function row:GetColorSpec()
        return color
    end

    function row:SetDisabledState(disabled)
        SetRowDisabled(self, disabled)
        swatch:SetEnabled(not disabled)
        if modeButton then modeButton:SetEnabled(not disabled) end
        if endSwatch then endSwatch:SetEnabled(not disabled) end
        if directionButton then directionButton:SetEnabled(not disabled) end
    end

    row.swatch = swatch
    row.gradientModeButton = modeButton
    row.gradientEndSwatch = endSwatch
    row.gradientDirectionButton = directionButton
    row.control = swatch
    Refresh()
    SetTooltip(row, opts.tooltip)
    EnableRightClickMouselook(row)
    return row
end

function Controls.CreateSearchBox(parent, width, opts)
    opts = opts or {}
    local r, g, b = Accent()
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width or 220, opts.height or 28)
    ApplyBackdrop(frame, C.bg.input, C.border.default)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", frame, "LEFT", 8, 0)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetVertexColor(UnpackColor(C.text.dim))

    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    editBox:SetPoint("RIGHT", frame, "RIGHT", -26, 0)
    editBox:SetHeight(22)
    editBox:SetFont(F.path, math.max(1, F.normal), "")
    editBox:SetTextColor(UnpackColor(C.text.highlight))
    editBox:SetAutoFocus(false)

    local placeholder = MakeFont(frame, F.normal, C.text.dim, opts.placeholder or SEARCH or "Search")
    placeholder:SetPoint("LEFT", editBox, "LEFT", 0, 0)

    local clear = CreateFrame("Button", nil, frame)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
    local clearText = MakeFont(clear, F.normal, C.text.dim, "x")
    clearText:SetPoint("CENTER")
    clear:Hide()

    local callback
    editBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        placeholder:SetShown(text == "")
        clear:SetShown(text ~= "")
        if callback then callback(text) end
    end)
    editBox:SetScript("OnEditFocusGained", function()
        frame:SetBackdropBorderColor(r, g, b, 1)
    end)
    editBox:SetScript("OnEditFocusLost", function()
        frame:SetBackdropBorderColor(UnpackColor(C.border.default))
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
        else
            self:ClearFocus()
        end
    end)
    clear:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:SetFocus()
    end)
    clear:SetScript("OnEnter", function()
        clearText:SetTextColor(r, g, b, 1)
    end)
    clear:SetScript("OnLeave", function()
        clearText:SetTextColor(UnpackColor(C.text.dim))
    end)

    function frame:SetOnTextChanged(fn)
        callback = fn
    end

    function frame:GetText()
        return editBox:GetText()
    end

    function frame:SetText(text)
        editBox:SetText(text or "")
    end

    frame.editBox = editBox
    frame.clearButton = clear
    EnableRightClickMouselook(frame)
    return frame
end

Controls.UnpackColor = UnpackColor
Controls.ApplyBackdrop = ApplyBackdrop
Controls.MakeFont = MakeFont
Controls.SetTooltip = SetTooltip
Controls.EnableRightClickMouselook = EnableRightClickMouselook
