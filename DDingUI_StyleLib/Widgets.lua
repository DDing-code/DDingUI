------------------------------------------------------
-- DDingUI_StyleLib :: Widgets
-- UI widget factory – every function's first arg is
-- addonName so the correct accent is auto-applied.
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end
local C    = Lib.Colors
local S    = Lib.Spacing
local F    = Lib.Font
local SOLID = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------
-- Internal helpers
------------------------------------------------------
local function u(tbl) return unpack(tbl) end

local function ApplyBackdrop(frame, bgColor, borderColor)
    frame:SetBackdrop({
        bgFile   = SOLID,
        edgeFile = SOLID,
        edgeSize = 1,
    })
    if bgColor    then frame:SetBackdropColor(u(bgColor)) end
    if borderColor then frame:SetBackdropBorderColor(u(borderColor)) end
end

local function SolidBG(parent, color, layer)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(u(color))
    return tex
end

local function MakeFont(parent, size, flags, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(F.path, size, flags or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    if color then fs:SetTextColor(u(color)) end
    return fs
end

local function CreateScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetAllPoints()

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(1) -- will be updated
    scroll:SetScrollChild(child)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 22)))
    end)

    -- keep child width in sync
    scroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then
            child:SetWidth(w)
        end
    end)

    return scroll, child
end

------------------------------------------------------
-- CreateSeparator
------------------------------------------------------
--- Thin horizontal divider line.
--- @param parent Frame
--- @param opts table|nil  { width, color }
--- @return Texture
function Lib.CreateSeparator(parent, opts)
    opts = opts or {}
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetWidth(opts.width or parent:GetWidth() or 200)
    line:SetColorTexture(u(opts.color or C.border.separator))
    return line
end

------------------------------------------------------
-- CreateSectionHeader
------------------------------------------------------
--- Section title in accent colour with optional underline.
--- @param parent Frame
--- @param addonName string
--- @param text string
--- @param opts table|nil { showLine, isFirst }
--- @return Frame  container frame (anchor this)
function Lib.CreateSectionHeader(parent, addonName, text, opts)
    opts = opts or {}
    local from = Lib.GetAccent(addonName)

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(opts.isFirst and (F.section + 8 + 5) or (F.section + 16 + 8))
    container:SetWidth(parent:GetWidth() or 300)

    local label = MakeFont(container, F.section, nil, from)
    label:SetText(text)
    label:SetJustifyH("LEFT")
    local topOffset = opts.isFirst and -8 or -16
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, topOffset)

    if opts.showLine ~= false then
        local line = container:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
        line:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        line:SetColorTexture(u(C.border.separator))
    end

    container.label = label
    return container
end

------------------------------------------------------
-- CreateButton
------------------------------------------------------
--- Standard button with hover & click flash.
--- @param parent Frame
--- @param addonName string
--- @param text string
--- @param onClick function(self)
--- @param opts table|nil { width, height, disabled }
--- @return Frame
function Lib.CreateButton(parent, addonName, text, onClick, opts)
    opts = opts or {}
    local from = Lib.GetAccent(addonName)

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(opts.width or 120, opts.height or 24)
    ApplyBackdrop(btn, C.bg.input, C.border.default)

    local label = MakeFont(btn, F.normal, nil, C.text.normal)
    label:SetPoint("CENTER")
    label:SetText(text)
    btn.label = label

    -- hover
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(u(C.bg.hover))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(u(C.bg.input))
    end)

    -- click flash
    btn:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(from[1], from[2], from[3], 0.6)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(u(C.bg.input))
    end)

    if onClick then btn:SetScript("OnClick", onClick) end

    -- disabled state helper
    function btn:SetDisabledState(disabled)
        self:SetEnabled(not disabled)
        self:SetAlpha(disabled and 0.50 or 1.0)
    end
    if opts.disabled then btn:SetDisabledState(true) end

    return btn
end

------------------------------------------------------
-- CreateCheckbox
------------------------------------------------------
--- 14×14 checkbox with accent fill + white checkmark.
--- @param parent Frame
--- @param addonName string
--- @param label string
--- @param default boolean
--- @param opts table|nil { onChange(value) }
--- @return Frame  container with .checked boolean and :SetChecked(bool)
function Lib.CreateCheckbox(parent, addonName, label, default, opts)
    opts = opts or {}
    local from = Lib.GetAccent(addonName)

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 20)

    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    ApplyBackdrop(box, C.bg.input, C.border.default)

    -- check fill (accent color only, no glyph) -- [STYLE]
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(from[1], from[2], from[3], 1)
    fill:Hide()

    -- label
    local text = MakeFont(container, F.normal, nil, C.text.normal)
    text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    text:SetText(label)

    -- state
    container.checked = default or false
    local function Refresh()
        if container.checked then fill:Show()
        else fill:Hide() end
    end
    Refresh()

    function container:SetChecked(val)
        self.checked = val
        Refresh()
        if opts.onChange then opts.onChange(val) end
    end

    function container:GetChecked()
        return self.checked
    end

    box:SetScript("OnClick", function()
        container.checked = not container.checked
        Refresh()
        if opts.onChange then opts.onChange(container.checked) end
    end)

    container.box = box
    container.label = text
    return container
end

------------------------------------------------------
-- CreateInputField
------------------------------------------------------
--- Single-line edit box.
--- @param parent Frame
--- @param addonName string
--- @param label string
--- @param default string
--- @param opts table|nil { width, numeric, onEnter(text), onChange(text) }
--- @return Frame  container with .editBox
function Lib.CreateInputField(parent, addonName, label, default, opts)
    opts = opts or {}

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(opts.width or 200, 22)

    -- label
    local lbl = MakeFont(container, F.normal, nil, C.text.normal)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetText(label)

    -- editbox
    local eb = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    eb:SetSize(opts.inputWidth or 120, 22)
    eb:SetPoint("LEFT", lbl, "RIGHT", S.labelGap, 0)
    eb:SetFont(F.path, F.normal, "")
    eb:SetTextColor(u(C.text.highlight))
    eb:SetAutoFocus(false)
    eb:SetTextInsets(4, 4, 0, 0)
    ApplyBackdrop(eb, C.bg.input, C.border.default)

    if opts.numeric then eb:SetNumeric(true) end
    if default then eb:SetText(tostring(default)) end

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if opts.onEnter then opts.onEnter(self:GetText()) end
    end)
    if opts.onChange then
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput then opts.onChange(self:GetText()) end
        end)
    end

    -- focus border
    eb:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(u(C.border.active))
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(u(C.border.default))
    end)

    container.editBox = eb
    container.label = lbl
    return container
end

------------------------------------------------------
-- CreateSlider
------------------------------------------------------
--- Horizontal slider with editable value field.
--- @param parent Frame
--- @param addonName string
--- @param label string
--- @param min number
--- @param max number
--- @param step number
--- @param default number
--- @param opts table|nil { width, onChange(value) }
--- @return Frame  container with .slider, .valueBox
function Lib.CreateSlider(parent, addonName, label, min, max, step, default, opts)
    opts = opts or {}
    local from = Lib.GetAccent(addonName)
    local width = opts.width or 200

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 52)

    -- label
    local lbl = MakeFont(container, F.normal, nil, C.text.normal)
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetText(label)

    -- track background
    local track = CreateFrame("Frame", nil, container, "BackdropTemplate")
    track:SetHeight(6)
    track:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -8)
    track:SetPoint("RIGHT", container, "RIGHT", -64, 0)
    ApplyBackdrop(track, C.bg.input, nil)
    track:SetBackdropBorderColor(0, 0, 0, 0) -- no border on track

    -- clamp default to valid range
    local clamped = math.max(min, math.min(max, tonumber(default) or min))

    -- slider (overlays track, expanded hit area for easier clicking)
    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 10)
    slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -10)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(clamped)
    slider:SetOrientation("HORIZONTAL")
    slider:SetBackdrop(nil)
    slider:EnableMouseWheel(true)
    slider:SetHitRectInsets(0, 0, 0, 0)

    -- thumb
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(16, 16)
    thumb:SetColorTexture(from[1], from[2], from[3], 1)
    slider:SetThumbTexture(thumb)

    -- min / max labels
    local minLabel = MakeFont(container, F.small, nil, C.text.dim)
    minLabel:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -2)
    minLabel:SetText(tostring(min))

    local maxLabel = MakeFont(container, F.small, nil, C.text.dim)
    maxLabel:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -2)
    maxLabel:SetText(tostring(max))

    -- editable value box (right side of track, larger for easier clicking)
    local valBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    valBox:SetSize(56, 22)
    valBox:SetPoint("LEFT", track, "RIGHT", 6, 0)
    valBox:SetFont(F.path, F.normal, "")
    valBox:SetTextColor(u(C.text.highlight))
    valBox:SetJustifyH("CENTER")
    valBox:SetAutoFocus(false)
    valBox:SetNumeric(false) -- allow decimals as text
    valBox:SetTextInsets(4, 4, 0, 0)
    ApplyBackdrop(valBox, C.bg.input, C.border.default)

    -- format helper (reused for initial display and OnValueChanged)
    local decimals = step < 1 and math.max(1, math.ceil(-math.log10(step))) or 0
    local fmtStr = "%." .. decimals .. "f"
    valBox:SetText(string.format(fmtStr, clamped))

    -- sync slider → valBox
    slider:SetScript("OnValueChanged", function(self, value)
        value = tonumber(string.format(fmtStr, value))
        valBox:SetText(tostring(value))
        if opts.onChange then opts.onChange(value) end
    end)

    -- sync valBox → slider
    valBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then
            v = math.max(min, math.min(max, v))
            slider:SetValue(v)
        end
        self:ClearFocus()
    end)
    valBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- mouse wheel on slider
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)

    container.slider = slider
    container.valueBox = valBox
    container.label = lbl
    return container
end

------------------------------------------------------
-- CreateDropdown
------------------------------------------------------
--- Custom dropdown (no Blizzard templates).
--- @param parent Frame
--- @param addonName string
--- @param label string
--- @param options table  { {text, value}, ... } or { "text", ... }
--- @param default any  value or text of initial selection
--- @param opts table|nil { width, onChange(value, text) }
--- @return Frame  container with :SetValue(v), :GetValue()
function Lib.CreateDropdown(parent, addonName, label, options, default, opts)
    opts = opts or {}
    local width = opts.width or 160

    -- normalise options to {text, value} pairs
    local items = {}
    for _, o in ipairs(options) do
        if type(o) == "table" then
            items[#items + 1] = { text = o.text or o[1], value = o.value or o[2] or o[1] }
        else
            items[#items + 1] = { text = tostring(o), value = o }
        end
    end

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width + 80, 24)

    -- label
    local lbl = MakeFont(container, F.normal, nil, C.text.normal)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetText(label)

    -- button (closed state)
    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetSize(width, 24)
    btn:SetPoint("LEFT", lbl, "RIGHT", S.labelGap, 0)
    ApplyBackdrop(btn, C.bg.input, C.border.default)

    local selectedText = MakeFont(btn, F.normal, nil, C.text.normal)
    selectedText:SetPoint("LEFT", 6, 0)
    selectedText:SetPoint("RIGHT", -20, 0)
    selectedText:SetJustifyH("LEFT")
    selectedText:SetWordWrap(false)

    local arrow = MakeFont(btn, F.normal, nil, C.text.dim)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("\226\150\188") -- ▼

    -- current value
    container._value = nil
    container._text  = ""

    local function SetDisplay(text, value)
        container._value = value
        container._text  = text
        selectedText:SetText(text)
    end

    -- set initial
    for _, item in ipairs(items) do
        if item.value == default or item.text == default then
            SetDisplay(item.text, item.value)
            break
        end
    end
    if container._value == nil and #items > 0 then
        SetDisplay(items[1].text, items[1].value)
    end

    -- dropdown list frame (FULLSCREEN_DIALOG 로 z-order 보장)
    local MAX_VISIBLE = opts.maxVisible or 10
    if #items == 0 then
        -- 빈 드롭다운 열지 않음
        btn:SetScript("OnClick", function() end)
        dropdown.btn = btn
        dropdown.SetOptions = function() end
        return dropdown
    end
    local totalH = #items * 22 + 2
    local visibleH = math.min(totalH, MAX_VISIBLE * 22 + 2)
    local needsScroll = #items > MAX_VISIBLE

    local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
    list:SetWidth(width)
    list:SetHeight(visibleH)
    ApplyBackdrop(list, C.bg.main, C.border.default)
    list:Hide()

    -- 스크롤 지원: 항목이 많으면 ScrollFrame 사용
    local rowParent = list
    if needsScroll then
        local listScroll = CreateFrame("ScrollFrame", nil, list)
        listScroll:SetPoint("TOPLEFT", 1, -1)
        listScroll:SetPoint("BOTTOMRIGHT", -1, 1)

        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetWidth(width - 2)
        listChild:SetHeight(totalH)
        listScroll:SetScrollChild(listChild)

        listScroll:EnableMouseWheel(true)
        listScroll:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local maxS = math.max(0, listChild:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 22)))
        end)
        rowParent = listChild
    end

    -- backdrop click-away catcher
    local catcher = CreateFrame("Button", nil, list)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(math.max(0, list:GetFrameLevel() - 1))
    catcher:SetAllPoints(UIParent)
    catcher:SetScript("OnClick", function() list:Hide(); catcher:Hide() end)
    catcher:EnableMouseWheel(true)
    catcher:SetScript("OnMouseWheel", function() list:Hide(); catcher:Hide() end)
    catcher:Hide()

    -- populate options
    for i, item in ipairs(items) do
        local row = CreateFrame("Button", nil, rowParent)
        row:SetSize(width - 2, 22)
        row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", needsScroll and 0 or 1, -(needsScroll and ((i - 1) * 22) or (1 + (i - 1) * 22)))

        local rowBG = SolidBG(row, { 0, 0, 0, 0 })
        local rowText = MakeFont(row, F.normal, nil, C.text.normal)
        rowText:SetPoint("LEFT", 6, 0)
        rowText:SetText(item.text)

        row:SetScript("OnEnter", function() rowBG:SetColorTexture(u(C.bg.hover)) end)
        row:SetScript("OnLeave", function() rowBG:SetColorTexture(0, 0, 0, 0) end)
        row:SetScript("OnClick", function()
            SetDisplay(item.text, item.value)
            list:Hide()
            catcher:Hide()
            if opts.onChange then opts.onChange(item.value, item.text) end
        end)
    end

    -- toggle
    btn:SetScript("OnClick", function()
        if list:IsShown() then
            list:Hide(); catcher:Hide()
        else
            list:Show(); catcher:Show()
        end
    end)

    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(u(C.bg.hover)) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropColor(u(C.bg.input)) end)

    function container:SetValue(val)
        for _, item in ipairs(items) do
            if item.value == val then
                SetDisplay(item.text, item.value)
                return
            end
        end
    end
    function container:GetValue() return self._value end
    function container:GetText()  return self._text end

    container.button = btn
    container.label  = lbl
    return container
end

------------------------------------------------------
-- CreateGradientText
------------------------------------------------------
--- Per-character colour gradient using |cff escape codes.
--- @param addonName string   accent preset key
--- @param text string
--- @return string  colour-escaped text
function Lib.CreateGradientText(addonName, text)
    local from, to = Lib.GetAccent(addonName)
    local chars = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = char
    end
    if #chars == 0 then return text end
    local result = ""
    for i, char in ipairs(chars) do
        local t = (i - 1) / math.max(1, #chars - 1)
        local r = from[1] + (to[1] - from[1]) * t
        local g = from[2] + (to[2] - from[2]) * t
        local b = from[3] + (to[3] - from[3]) * t
        result = result .. string.format("|cff%02x%02x%02x%s|r",
            math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5), char)
    end
    return result
end

------------------------------------------------------
-- CreateAddonTitle / GetChatPrefix  -- [STYLE]
------------------------------------------------------
--- "DDing" (blue) + "UI" (orange) + addon display name (accent gradient).
--- @param addonKey string       accent preset key (e.g. "CDM", "UnitFrames")
--- @param displayName string|nil  text after "DDingUI " (e.g. "CooldownManager")
--- @return string  colour-escaped title
function Lib.CreateAddonTitle(addonKey, displayName)
    local prefix = "|cffffffffDDing|r|cffffa300UI|r"
    if displayName and displayName ~= "" then
        return prefix .. " " .. Lib.CreateGradientText(addonKey, displayName)
    end
    return prefix
end

--- Chat/print prefix:  DDingUI AddonName:
--- @param addonKey string       accent preset key
--- @param displayName string|nil  text after "DDingUI "
--- @return string  colour-escaped prefix ending with ":"
function Lib.GetChatPrefix(addonKey, displayName)
    return Lib.CreateAddonTitle(addonKey, displayName) .. "|cff888888:|r "
end

------------------------------------------------------
-- CreateSearchBox
------------------------------------------------------
--- Search input with icon, placeholder, clear button.
--- @param parent Frame
--- @param width number
--- @param opts table|nil { placeholder, onTextChanged(text) }
--- @return Frame  search frame with :SetOnTextChanged(), :GetText(), :SetText(), :Clear()
function Lib.CreateSearchBox(parent, width, opts)
    opts = opts or {}
    local search = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    search:SetSize(width or 200, 24)
    ApplyBackdrop(search, C.bg.input, { 0, 0, 0, 1 })

    -- search icon
    search.icon = search:CreateTexture(nil, "ARTWORK")
    search.icon:SetSize(14, 14)
    search.icon:SetPoint("LEFT", 6, 0)
    search.icon:SetTexture([[Interface\Common\UI-Searchbox-Icon]])
    search.icon:SetVertexColor(0.6, 0.6, 0.6)

    -- editbox
    search.editBox = CreateFrame("EditBox", nil, search)
    search.editBox:SetPoint("LEFT", search.icon, "RIGHT", 4, 0)
    search.editBox:SetPoint("RIGHT", -24, 0)
    search.editBox:SetHeight(20)
    search.editBox:SetFont(F.path, F.normal, "")
    search.editBox:SetShadowOffset(1, -1)
    search.editBox:SetShadowColor(0, 0, 0, 1)
    search.editBox:SetAutoFocus(false)
    search.editBox:SetJustifyH("LEFT")

    -- placeholder
    search.placeholder = MakeFont(search, F.normal, nil, C.text.disabled)
    search.placeholder:SetText(opts.placeholder or "\234\178\128\236\131\137...")
    search.placeholder:SetPoint("LEFT", search.editBox, "LEFT", 0, 0)
    search.placeholder:SetJustifyH("LEFT")

    -- clear button
    search.clearBtn = CreateFrame("Button", nil, search)
    search.clearBtn:SetSize(16, 16)
    search.clearBtn:SetPoint("RIGHT", -4, 0)
    search.clearBtn:SetNormalTexture([[Interface\Buttons\UI-StopButton]])
    local clearTex = search.clearBtn:GetNormalTexture()
    if clearTex then clearTex:SetVertexColor(0.6, 0.6, 0.6) end
    search.clearBtn:Hide()

    search.clearBtn:SetScript("OnEnter", function(self)
        local tex = self:GetNormalTexture()
        if tex then tex:SetVertexColor(1, 0.3, 0.3) end
    end)
    search.clearBtn:SetScript("OnLeave", function(self)
        local tex = self:GetNormalTexture()
        if tex then tex:SetVertexColor(0.6, 0.6, 0.6) end
    end)
    search.clearBtn:SetScript("OnClick", function()
        search.editBox:SetText("")
        search.editBox:ClearFocus()
    end)

    search.editBox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        search.placeholder:SetShown(text == "")
        search.clearBtn:SetShown(text ~= "")
        if search.onTextChanged then search.onTextChanged(text) end
    end)
    search.editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search.editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    function search:SetOnTextChanged(func) search.onTextChanged = func end
    function search:Clear() search.editBox:SetText("") end
    function search:GetText() return search.editBox:GetText() end
    function search:SetText(text) search.editBox:SetText(text) end

    if opts.onTextChanged then search.onTextChanged = opts.onTextChanged end

    return search
end

------------------------------------------------------
-- CreateTitleBar
------------------------------------------------------
--- Title bar with accent gradient line, name, version, close button.
--- @param parent Frame
--- @param addonName string
--- @param title string
--- @param version string
--- @param opts table|nil { showScale }
--- @return Frame  titleBar frame
function Lib.CreateTitleBar(parent, addonName, title, version, opts)
    opts = opts or {}
    local from, to = Lib.GetAccent(addonName)

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(34)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
    SolidBG(bar, C.bg.titlebar)

    -- accent gradient line (2px, inside bar top edge)
    local accentLine = Lib.CreateHorizontalGradient(bar, from, to, 2)
    accentLine:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    accentLine:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)

    -- title text: "DDingUI Xxx" → DDing(white)+UI(orange)+Xxx(accent gradient)
    local titleText = MakeFont(bar, F.title, nil, { 1, 1, 1, 1 })
    titleText:SetPoint("LEFT", 10, 0)
    local displayName = title and title:match("^DDingUI%s+(.+)$")
    if displayName then
        titleText:SetText(Lib.CreateAddonTitle(addonName, displayName))
    else
        titleText:SetText(Lib.CreateGradientText(addonName, title))
    end

    -- version text (normal colour)
    local verText = MakeFont(bar, F.small, nil, C.text.dim)
    verText:SetPoint("LEFT", titleText, "RIGHT", 6, 0)
    verText:SetText("v" .. (version or ""))

    -- close button (UF 통일: 28x24)
    local closeBtn = CreateFrame("Button", nil, bar)
    closeBtn:SetSize(28, 24)
    closeBtn:SetPoint("RIGHT", -5, 0)

    local closeText = MakeFont(closeBtn, F.normal, nil, C.text.dim)
    closeText:SetPoint("CENTER")
    closeText:SetText("X")

    closeBtn:SetScript("OnEnter", function()
        closeText:SetTextColor(u(C.status.error))
    end)
    closeBtn:SetScript("OnLeave", function()
        closeText:SetTextColor(u(C.text.dim))
    end)
    closeBtn:SetScript("OnClick", function()
        parent:Hide()
    end)

    bar.accentLine = accentLine
    bar.titleText  = titleText
    bar.verText    = verText
    bar.closeBtn   = closeBtn
    return bar
end

------------------------------------------------------
-- CreateTreeMenu
------------------------------------------------------
--- Collapsible tree menu for left sidebar.
--- @param parent Frame  container frame (sidebar area)
--- @param addonName string
--- @param menuData table  { {text, key, children={...}}, ... }
--- @param opts table|nil  { onSelect(key), defaultKey }
--- @return Frame  treeFrame with :SetMenuData(), :SetSelected(key), .onSelect
function Lib.CreateTreeMenu(parent, addonName, menuData, opts)
    opts = opts or {}
    local from = Lib.GetAccent(addonName)
    local ITEM_H = 22
    local ITEM_H_ICON = 26        -- icon이 있는 항목은 약간 더 높게
    local ICON_SIZE = 20           -- 스펠 아이콘 크기
    local INDENT = 16
    -- UF 통일: 선택 상태 색상 커스터마이즈 (기본: C.bg.selected)
    local selColor = opts.selectedColor or C.bg.selected

    local tree = CreateFrame("Frame", nil, parent)
    tree:SetAllPoints()
    SolidBG(tree, C.bg.sidebar)

    local scroll, child = CreateScrollFrame(tree)

    -- state
    local expanded  = {}
    local selectedKey = opts.defaultKey
    tree.onSelect = opts.onSelect
    tree.onRightClick = opts.onRightClick
    tree._buttons = {}

    -- flatten visible items
    local function Flatten(data, result, level)
        result = result or {}; level = level or 0
        for _, item in ipairs(data) do
            local hasKids = item.children and #item.children > 0
            result[#result + 1] = {
                text = item.text, key = item.key,
                level = level, hasChildren = hasKids,
                icon = item.icon,              -- 스펠 아이콘 텍스처 ID
                iconCoords = item.iconCoords,  -- 선택적 텍스처 좌표
                desc = item.desc,              -- tooltip 설명
                disabled = item.disabled,      -- 비활성 상태
            }
            if hasKids and expanded[item.key] then
                Flatten(item.children, result, level + 1)
            end
        end
        return result
    end

    local function Refresh()
        local visible = Flatten(menuData)
        -- hide all
        for _, b in ipairs(tree._buttons) do b:Hide() end

        local yOffset = 0
        for i, item in ipairs(visible) do
            local rowH = item.icon and ITEM_H_ICON or ITEM_H
            local btn = tree._buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, child)
                btn:SetHeight(ITEM_H)
                btn._bg   = SolidBG(btn, { 0, 0, 0, 0 })
                btn._icon = MakeFont(btn, F.normal, nil, C.text.dim)
                btn._icon:SetPoint("LEFT", 4, 0)
                btn._text = MakeFont(btn, F.normal, nil, C.text.normal)
                -- accent stripe on left edge (selected indicator) -- [STYLE]
                btn._stripe = btn:CreateTexture(nil, "OVERLAY")
                btn._stripe:SetWidth(2)
                btn._stripe:SetPoint("TOPLEFT", 0, 0)
                btn._stripe:SetPoint("BOTTOMLEFT", 0, 0)
                btn._stripe:SetColorTexture(from[1], from[2], from[3], 1)
                btn._stripe:Hide()
                -- 스펠 아이콘 텍스처 (Phase 1 WA-style)
                btn._spellIcon = btn:CreateTexture(nil, "ARTWORK")
                btn._spellIcon:SetSize(ICON_SIZE, ICON_SIZE)
                btn._spellIcon:Hide()
                tree._buttons[i] = btn
            end

            btn:SetHeight(rowH)
            btn:Show()
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -yOffset)
            btn:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            yOffset = yOffset + rowH + S.treeItemGap

            local indent = item.level * INDENT + 4
            local textLeft  -- 텍스트 시작 X 좌표

            btn._icon:ClearAllPoints()
            btn._icon:SetPoint("LEFT", indent, 0)
            if item.hasChildren then
                btn._icon:SetText(expanded[item.key] and "\226\150\188" or "\226\150\182") -- ▼ or ▶
                btn._icon:Show()
                textLeft = indent + 14
            else
                btn._icon:Hide()
                textLeft = indent + (item.level > 0 and 14 or 0)
            end

            -- 스펠 아이콘 표시
            if item.icon then
                btn._spellIcon:ClearAllPoints()
                btn._spellIcon:SetPoint("LEFT", textLeft, 0)
                btn._spellIcon:SetTexture(item.icon)
                if item.iconCoords then
                    btn._spellIcon:SetTexCoord(unpack(item.iconCoords))
                else
                    btn._spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                btn._spellIcon:Show()
                btn._text:ClearAllPoints()
                btn._text:SetPoint("LEFT", btn._spellIcon, "RIGHT", 4, 0)
                btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            else
                btn._spellIcon:Hide()
                btn._text:ClearAllPoints()
                btn._text:SetPoint("LEFT", textLeft, 0)
                btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            end

            btn._text:SetText(item.text)

            -- selection highlight (selColor: opts.selectedColor or C.bg.selected)
            if item.key == selectedKey then
                btn._bg:SetColorTexture(u(selColor))
                btn._text:SetTextColor(from[1], from[2], from[3], 1) -- [STYLE] accent color
                if btn._stripe then btn._stripe:Show() end -- [STYLE]
            else
                btn._bg:SetColorTexture(0, 0, 0, 0)
                btn._text:SetTextColor(u(C.text.normal))
                if btn._stripe then btn._stripe:Hide() end -- [STYLE]
            end

            -- hover
            local key = item.key
            local hasKids = item.hasChildren
            local itemDesc = item.desc
            local itemDisabled = item.disabled

            -- 비활성 트래커 시각적 표시
            if itemDisabled and key ~= selectedKey then
                btn._text:SetTextColor(0.45, 0.45, 0.45, 0.7)
                if btn._spellIcon:IsShown() then
                    btn._spellIcon:SetDesaturated(true)
                    btn._spellIcon:SetAlpha(0.5)
                end
            else
                if btn._spellIcon:IsShown() then
                    btn._spellIcon:SetDesaturated(false)
                    btn._spellIcon:SetAlpha(1.0)
                end
            end

            btn:SetScript("OnEnter", function(self)
                if key ~= selectedKey then
                    self._bg:SetColorTexture(u(C.bg.hover))
                end
                -- Tooltip (WeakAuras-style)
                if itemDesc then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 0)
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(item.text or "", 1, 0.82, 0)
                    for line in itemDesc:gmatch("[^\n]+") do
                        GameTooltip:AddLine(line, 1, 1, 1, true)
                    end
                    if itemDisabled then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cffff4444비활성|r", 1, 0.3, 0.3)
                    end
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if key ~= selectedKey then
                    self._bg:SetColorTexture(0, 0, 0, 0)
                end
                GameTooltip:Hide()
            end)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- [12.0.1] 우클릭 지원
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if tree.onRightClick then
                        tree.onRightClick(key, item.text, self)
                    end
                    return
                end
                if hasKids then
                    expanded[key] = not expanded[key]
                end
                selectedKey = key
                Refresh()
                if tree.onSelect then tree.onSelect(key) end
            end)
        end

        -- update scroll child height
        child:SetHeight(math.max(yOffset, tree:GetHeight()))
    end

    function tree:SetMenuData(data, expandAll)
        menuData = data
        if expandAll then
            local function expandRecursive(items)
                for _, item in ipairs(items) do
                    if item.children and #item.children > 0 then
                        expanded[item.key] = true
                        expandRecursive(item.children)
                    end
                end
            end
            expandRecursive(data)
        end
        Refresh()
    end

    function tree:SetSelected(key)
        selectedKey = key
        Refresh()
    end

    function tree:GetSelected()
        return selectedKey
    end

    -- initial render (deferred until frame has size)
    local initialRefreshDone = false
    tree:SetScript("OnShow", function(self)
        self:SetScript("OnShow", nil) -- once
        if not initialRefreshDone then
            initialRefreshDone = true
            Refresh()
        end
    end)
    -- also refresh if data was provided (deferred, but skip if OnShow already ran)
    if menuData and #menuData > 0 then
        C_Timer.After(0, function()
            if not initialRefreshDone then
                initialRefreshDone = true
                Refresh()
            end
        end)
    end

    return tree
end

------------------------------------------------------
-- CreateSettingsPanel
------------------------------------------------------
--- Full settings panel skeleton: titlebar + tree + scrollable content.
--- @param addonName string
--- @param title string
--- @param version string
--- @param opts table|nil { width, height, minWidth, minHeight, menuWidth }
--- @return table { frame, titleBar, treeFrame, contentScroll, contentChild }
function Lib.CreateSettingsPanel(addonName, title, version, opts)
    opts = opts or {}
    local w = opts.width  or 700
    local h = opts.height or 500
    local menuW = opts.menuWidth or 180

    -- main frame (기존 프레임 존재 시 재사용)
    local panelName = "DDingUI_" .. addonName .. "_Panel"
    local existingFrame = _G[panelName]
    if existingFrame then
        existingFrame:Show()
        return existingFrame._panelResult or { frame = existingFrame }
    end
    local frame = CreateFrame("Frame", panelName, UIParent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    ApplyBackdrop(frame, C.bg.main, { 0, 0, 0, 1 })

    -- draggable
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- resizable
    frame:SetResizable(true)
    frame:SetResizeBounds(opts.minWidth or 600, opts.minHeight or 400)

    -- resize grip (ElvUI-style L-shape)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(28, 28)
    grip:SetPoint("BOTTOMRIGHT", -5, 5)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)

    local gripV = grip:CreateTexture(nil, "OVERLAY")
    gripV:SetSize(5, 20)
    gripV:SetPoint("BOTTOMRIGHT", 0, 0)
    gripV:SetColorTexture(1, 1, 1, 1)

    local gripH = grip:CreateTexture(nil, "OVERLAY")
    gripH:SetSize(20, 5)
    gripH:SetPoint("BOTTOMRIGHT", 0, 0)
    gripH:SetColorTexture(1, 1, 1, 1)

    -- ESC to close (중복 등록 방지)
    local frameName = frame:GetName()
    local alreadyRegistered = false
    for _, name in ipairs(UISpecialFrames) do
        if name == frameName then alreadyRegistered = true; break end
    end
    if not alreadyRegistered then
        tinsert(UISpecialFrames, frameName)
    end

    -- title bar (handles drag)
    local titleBar = Lib.CreateTitleBar(frame, addonName, title, version)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)

    -- vertical divider between tree & content
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetColorTexture(u(C.border.separator))
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", menuW, -35)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", menuW, 0)

    -- tree menu area (left)
    local treeFrame = CreateFrame("Frame", nil, frame)
    treeFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -35)
    treeFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    treeFrame:SetWidth(menuW)

    -- content area (right, scrollable)
    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", menuW + 1, -35)
    contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)

    local contentScroll, contentChild = CreateScrollFrame(contentFrame)

    -- hide by default; caller shows when ready
    frame:Hide()

    local result = {
        frame        = frame,
        titleBar     = titleBar,
        treeFrame    = treeFrame,
        contentScroll = contentScroll,
        contentChild = contentChild,
        divider      = divider,
    }
    frame._panelResult = result
    return result
end
