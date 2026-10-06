------------------------------------------------------
-- DDingUI_StyleLib :: Widgets
-- UI widget factory – every function's first arg is
-- addonName so the correct accent is auto-applied.
------------------------------------------------------
local ADDON_NAME = ...
local MAJOR = "DDingUI-FX-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end
if Lib.__ddingStyleLibLoadOwner ~= ADDON_NAME and Lib.EnableRightClickMouselook then return end
local C    = Lib.Colors
local S    = Lib.Spacing
local F    = Lib.Font
local Motion = Lib.Motion
local T    = Lib.Tokens
local PP   = Lib.PP
local SOLID = Lib.Textures and Lib.Textures.flat or "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------
-- Internal helpers
------------------------------------------------------
local function u(tbl) return unpack(tbl) end

local rightMouseLookActive = false
local rightMouseLookWatcher

local function StopRightButtonMouselook()
    if not rightMouseLookActive then return end
    rightMouseLookActive = false
    if rightMouseLookWatcher then
        rightMouseLookWatcher:Hide()
    end
    if MouselookStop then
        pcall(MouselookStop)
    end
end

local function EnsureRightMouseLookWatcher()
    if rightMouseLookWatcher then return rightMouseLookWatcher end

    rightMouseLookWatcher = CreateFrame("Frame")
    rightMouseLookWatcher:Hide()
    rightMouseLookWatcher:SetScript("OnUpdate", function()
        if IsMouseButtonDown and IsMouseButtonDown("RightButton") then return end
        StopRightButtonMouselook()
    end)
    return rightMouseLookWatcher
end

local function StartRightButtonMouselook()
    if IsMouseButtonDown and not IsMouseButtonDown("RightButton") then return end
    if not MouselookStart then return end

    local ok = pcall(MouselookStart)
    if ok then
        rightMouseLookActive = true
        EnsureRightMouseLookWatcher():Show()
    end
end

local function EnableRightClickMouselook(frame)
    if not frame or frame._ddingRightClickMouselook then return end
    frame._ddingRightClickMouselook = true
    if frame.EnableMouse then
        frame:EnableMouse(true)
    end
    frame:HookScript("OnMouseDown", function(_, button)
        if button == "RightButton" then
            StartRightButtonMouselook()
        end
    end)
    frame:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            StopRightButtonMouselook()
        end
    end)
end

Lib.StartRightButtonMouselook = StartRightButtonMouselook
Lib.StopRightButtonMouselook = StopRightButtonMouselook
Lib.EnableRightClickMouselook = EnableRightClickMouselook

local function ApplyBackdrop(frame, bgColor, borderColor, radius)
    -- [STYLE] StyleLib 1.3: rounded surfaces keep the backdrop colour API (see Lib.MakeRounded)
    if radius and Lib.Rounded and Lib.MakeRounded then
        Lib.MakeRounded(frame, radius, bgColor, borderColor)
        return
    end
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

------------------------------------------------------
-- Rounded surfaces + logo rings (StyleLib 1.3)  -- [STYLE]
-- Textures come from Media/ (built by DDingUI_StyleLib/tools/build_media.py):
-- white superellipse 9-slice masks tinted with SetVertexColor.
------------------------------------------------------
Lib.MediaPath = Lib.MediaPath or (ADDON_NAME == "DDingUI_StyleLib"
    and "Interface\\AddOns\\DDingUI_StyleLib\\Media\\"
    or ("Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Libs\\DDingUI_StyleLib\\Media\\"))
local MEDIA = Lib.MediaPath
if Lib.Rounded == nil then Lib.Rounded = true end
Lib.Radius = Lib.Radius or { window = 14, card = 10, row = 8, control = 6, check = 4, track = 2 }

local ROUND_RADII = { 2, 3, 4, 6, 8, 10, 14 }
local ROUND_MARGIN = { [2] = 3, [3] = 4, [4] = 6, [6] = 8, [8] = 11, [10] = 13, [14] = 19 }

local function PickRadius(r)
    r = tonumber(r) or 6
    local best = ROUND_RADII[1]
    for _, v in ipairs(ROUND_RADII) do
        if math.abs(v - r) < math.abs(best - r) then best = v end
    end
    return best
end

--- Turn a texture into a rounded 9-slice (fill or 1px border). Tint with SetVertexColor.
function Lib.RoundTexture(tex, radius, border)
    if not tex then return end
    radius = PickRadius(radius)
    tex:SetTexture(MEDIA .. "ddsl_round" .. radius .. (border and "_border" or ""))
    tex._ddslRoundTex = radius -- RowHover/tweens tint with SetVertexColor instead of SetColorTexture
    local m = ROUND_MARGIN[radius]
    if tex.SetTextureSliceMargins then
        tex:SetTextureSliceMargins(m, m, m, m)
        if tex.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    end
    return tex
end

--- Give a frame a rounded fill + border while keeping SetBackdropColor/SetBackdropBorderColor
--- working (hover tweens and refresh code keep calling them). Safe to call again to recolour.
function Lib.MakeRounded(frame, radius, bgColor, borderColor)
    if not frame or not frame.CreateTexture then return nil end
    local st = frame._ddslRounded
    if not st then
        if frame.SetBackdrop then pcall(frame.SetBackdrop, frame, nil) end
        st = { bg = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 } }
        st.fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        st.fill:SetAllPoints()
        st.edge = frame:CreateTexture(nil, "BORDER", nil, -8)
        st.edge:SetAllPoints()
        frame._ddslRounded = st
        frame.SetBackdropColor = function(_, r, g, b, a)
            st.bg = { r, g, b, a or 1 }
            st.fill:SetVertexColor(r, g, b, a or 1)
        end
        frame.SetBackdropBorderColor = function(_, r, g, b, a)
            st.border = { r, g, b, a or 1 }
            st.edge:SetVertexColor(r, g, b, a or 1)
        end
        frame.GetBackdropColor = function() return u(st.bg) end
        frame.GetBackdropBorderColor = function() return u(st.border) end
        -- A later SetBackdrop(info) only toggles visibility; the surface stays rounded.
        frame.SetBackdrop = function(_, info)
            st.fill:SetShown(info ~= nil)
            st.edge:SetShown(info ~= nil)
        end
    end
    st.radius = PickRadius(radius)
    Lib.RoundTexture(st.fill, st.radius)
    Lib.RoundTexture(st.edge, st.radius, true)
    frame:SetBackdropColor(u(bgColor or st.bg))
    frame:SetBackdropBorderColor(u(borderColor or st.border))
    return st
end

-- Crop of the right ring inside ddsl_rings/ddsl_ring_right (256x215 canvas).
local RIGHT_RING_COORD = { 0.27, 0.98, 0.02, 0.98 }
local RINGS_ASPECT = 256 / 215

--- Series logo as two interlocked ring textures; :PlayLink() slides them together.
function Lib.CreateLogoRings(parent, height, color)
    height = height or 22
    local w = math.floor(height * RINGS_ASPECT + 0.5)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, height)
    local left = f:CreateTexture(nil, "ARTWORK", nil, 1)
    left:SetTexture(MEDIA .. "ddsl_ring_left")
    left:SetSize(w, height)
    left:SetPoint("CENTER")
    local right = f:CreateTexture(nil, "ARTWORK", nil, 2)
    right:SetTexture(MEDIA .. "ddsl_ring_right")
    right:SetSize(w, height)
    right:SetPoint("CENTER")
    f.leftRing, f.rightRing = left, right

    function f:SetColor(r, g, b, a)
        left:SetVertexColor(r, g, b, a or 1)
        right:SetVertexColor(r, g, b, a or 1)
        f.color = { r, g, b, a or 1 }
    end
    if color then f:SetColor(color[1], color[2], color[3], color[4] or 1) end

    local function Place(d, alpha)
        left:SetPoint("CENTER", f, "CENTER", -d, 0)
        right:SetPoint("CENTER", f, "CENTER", d, 0)
        left:SetAlpha(alpha)
        right:SetAlpha(alpha)
    end

    function f:PlayLink(distance)
        if not Motion or not Motion.Tween then return end
        distance = distance or math.max(2, height * 0.14)
        Motion.Tween(f, 1, 0, 0.28, {
            key = "logoLink", delay = 0.06, ease = "outBack",
            onUpdate = function(_, v)
                local move = Motion.AllowsMovement and Motion.AllowsMovement()
                Place(move and distance * v or 0, 1 - 0.8 * math.max(0, v))
            end,
            onFinish = function() Place(0, 1) end,
        })
    end
    return f
end

--- Small open ring (right half of the logo) for list status markers.
function Lib.CreateStatusRing(parent, size, color)
    size = size or 11
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(MEDIA .. "ddsl_ring_right")
    tex:SetTexCoord(u(RIGHT_RING_COORD))
    tex:SetSize(math.floor(size * 0.89 + 0.5), size)
    if color then tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
    return tex
end

--- Faint series-logo watermark in a corner of a content card (alpha 0.05 by default).
function Lib.AddWatermark(parent, addonName, opts)
    opts = opts or {}
    local from = Lib.GetAccent(addonName)
    local h = opts.height or 200
    local tex = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    tex:SetTexture(MEDIA .. "ddsl_rings")
    tex:SetSize(math.floor(h * RINGS_ASPECT + 0.5), h)
    tex:SetPoint(opts.point or "BOTTOMRIGHT", parent, opts.point or "BOTTOMRIGHT", opts.x or -18, opts.y or 18)
    tex:SetVertexColor(from[1], from[2], from[3], opts.alpha or 0.05)
    return tex
end

--- Small interlocked-rings bullet (section headers).
function Lib.CreateRingBullet(parent, addonName, height)
    local from = Lib.GetAccent(addonName)
    height = height or 11
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(MEDIA .. "ddsl_rings")
    tex:SetSize(math.floor(height * RINGS_ASPECT + 0.5), height)
    tex:SetVertexColor(from[1], from[2], from[3], 1)
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
    local indent = 0
    if Lib.Rounded and opts.bullet ~= false then -- [STYLE] series ring bullet
        local bullet = Lib.CreateRingBullet(container, addonName, 11)
        bullet:SetPoint("LEFT", label, "LEFT", -(bullet:GetWidth() + 7), 0)
        indent = bullet:GetWidth() + 7
        container.bullet = bullet
    end
    label:SetPoint("TOPLEFT", container, "TOPLEFT", indent, topOffset)

    if opts.showLine ~= false then
        local line = container:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -indent, -4)
        line:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        line:SetColorTexture(u(C.border.separator))
    end

    container.label = label
    return container
end

------------------------------------------------------
-- CreateButton
------------------------------------------------------
--- Standard button with smooth hover & click flash.
--- @param parent Frame
--- @param addonName string
--- @param text string
--- @param onClick function(self)
--- @param opts table|nil { width, height, disabled, hoverMotion, motion, flash }
--- @return Frame
function Lib.CreateButton(parent, addonName, text, onClick, opts)
    opts = opts or {}
    local from = Lib.GetAccent(addonName)

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(opts.width or 120, opts.height or 24)
    ApplyBackdrop(btn, C.bg.input, C.border.default, Lib.Radius.control)

    local label = MakeFont(btn, F.normal, nil, C.text.normal)
    label:SetPoint("CENTER")
    label:SetText(text)
    btn.label = label

    local hoverMotion
    if Motion and opts.hoverMotion ~= false then
        hoverMotion = Motion.ButtonHover(btn, {
            normalBg = opts.normalBg or C.bg.input,
            hoverBg = opts.hoverBg or C.bg.hover,
            normalBorder = opts.normalBorder or C.border.default,
            hoverBorder = opts.hoverBorder or { from[1], from[2], from[3], opts.hoverBorderAlpha or 0.65 },
            text = label,
            normalText = opts.normalText or C.text.normal,
            hoverText = opts.hoverText or C.text.highlight,
            duration = opts.hoverDuration or 0.10,
            bind = true,
        })
    else
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(u(C.bg.hover))
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(u(C.bg.input))
        end)
    end

    -- click flash
    btn:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            StartRightButtonMouselook()
            return
        end
        if Motion and hoverMotion then Motion.Stop(self, "buttonHover") end
        self:SetBackdropColor(from[1], from[2], from[3], 0.6)
        if Motion and opts.motion == true then
            self._ddslMotionBaseScale = self._ddslMotionBaseScale or self:GetScale() or 1
            Motion.Press(self, { baseScale = self._ddslMotionBaseScale })
        end
    end)
    btn:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            StopRightButtonMouselook()
            return
        end
        if hoverMotion then
            hoverMotion:SetTarget((self.IsMouseOver and self:IsMouseOver()) and 1 or 0)
        else
            self:SetBackdropColor(u(C.bg.input))
        end
        if Motion then
            if opts.motion == true then
                self._ddslMotionBaseScale = self._ddslMotionBaseScale or self:GetScale() or 1
                Motion.Release(self, { baseScale = self._ddslMotionBaseScale })
            end
            if opts.flash ~= false then
                Motion.EdgeFlash(self, from[1], from[2], from[3], {
                    thickness = opts.flashThickness or 2,
                    alpha = opts.flashAlpha or 0.75,
                    duration = opts.flashDuration or 0.28,
                })
            end
        end
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

    local CB = T and T.CB or { BOX_R=0.075, BOX_G=0.113, BOX_B=0.141, BRD_A=0.25, ACT_BRD_A=0.70, SIZE=14, CHECK_INSET=2 }
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(CB.SIZE, CB.SIZE)
    box:SetPoint("LEFT", 0, 0)
    ApplyBackdrop(box, { CB.BOX_R, CB.BOX_G, CB.BOX_B, 1 }, { 1, 1, 1, CB.BRD_A }, Lib.Radius.check)

    -- check fill (accent color only, no glyph) -- [STYLE]
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", CB.CHECK_INSET, -CB.CHECK_INSET)
    fill:SetPoint("BOTTOMRIGHT", -CB.CHECK_INSET, CB.CHECK_INSET)
    if Lib.Rounded then -- [STYLE] rounded check fill
        Lib.RoundTexture(fill, 2)
        fill:SetVertexColor(from[1], from[2], from[3], 1)
    else
        fill:SetColorTexture(from[1], from[2], from[3], 1)
    end
    if PP then PP.DisablePixelSnap(fill) end
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
        -- [STYLE] check pop: the fill grows out of the box centre (0.16s, outBack)
        if container.checked and Motion and Motion.Tween then
            local inset = CB.CHECK_INSET
            Motion.Tween(fill, inset + 2, inset, 0.16, {
                key = "checkPop", ease = "outBack",
                onUpdate = function(tex, v)
                    tex:ClearAllPoints()
                    tex:SetPoint("TOPLEFT", v, -v)
                    tex:SetPoint("BOTTOMRIGHT", -v, v)
                end,
            })
        end
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
    ApplyBackdrop(eb, C.bg.input, C.border.default, Lib.Radius.control)

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
--- Series slider spec (StyleLib 1.2): wide hit area, thick track, big thumb, short width. -- [STYLE]
Lib.SliderSpec = {
    trackWidth = 180, trackHeight = 6, hitHeight = 28,
    thumbSize = 16, thumbHover = 18,          -- solid thumb
    thumbWidth = 24, thumbHeight = 14,        -- legacy dimensions for independent callers
    valueWidth = 56, valueHeight = 24, valueGap = 8,
}

function Lib.CreateSlider(parent, addonName, label, min, max, step, default, opts)
    opts = opts or {}
    local from = Lib.GetAccent(addonName)
    local SPEC = Lib.SliderSpec
    local valueArea = SPEC.valueWidth + SPEC.valueGap
    local width = opts.width or (SPEC.trackWidth + valueArea)

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 48)

    -- label
    local lbl = MakeFont(container, F.normal, nil, C.text.normal)
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetText(label)

    -- track background (6px, value box sits on the right)
    local track = CreateFrame("Frame", nil, container, "BackdropTemplate")
    track:SetHeight(SPEC.trackHeight)
    track:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -14)
    track:SetPoint("RIGHT", container, "RIGHT", -valueArea, 0)
    ApplyBackdrop(track, C.bg.input, C.border.default, Lib.Radius.track)

    -- accent fill from the left edge to the thumb
    local fillTex = track:CreateTexture(nil, "ARTWORK")
    local minFill = 1
    if Lib.Rounded then -- [STYLE] pill fill spans the whole rounded track
        fillTex:SetPoint("TOPLEFT", 0, 0)
        fillTex:SetPoint("BOTTOMLEFT", 0, 0)
        Lib.RoundTexture(fillTex, Lib.Radius.track)
        fillTex:SetVertexColor(from[1], from[2], from[3], 1)
        minFill = SPEC.trackHeight
    else
        fillTex:SetPoint("TOPLEFT", 1, -1)
        fillTex:SetPoint("BOTTOMLEFT", 1, 1)
        fillTex:SetColorTexture(from[1], from[2], from[3], 1)
    end
    fillTex:SetWidth(minFill)
    if PP then PP.DisablePixelSnap(fillTex) end

    -- clamp default to valid range
    local clamped = math.max(min, math.min(max, tonumber(default) or min))

    -- slider: 28px tall hit area centred on the track
    local pad = (SPEC.hitHeight - SPEC.trackHeight) / 2
    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", track, "TOPLEFT", 0, pad)
    slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -pad)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(clamped)
    slider:SetOrientation("HORIZONTAL")
    slider:SetBackdrop(nil)
    slider:EnableMouseWheel(true)

    -- solid thumb (16px, grows to 18px on hover)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    local tw, th = SPEC.thumbSize, SPEC.thumbSize
    thumb:SetColorTexture(u(C.text.normal))
    thumb:SetSize(tw, th)
    slider:SetThumbTexture(thumb)

    local function UpdateFill(value)
        local w = track:GetWidth() - 2
        if not w or w <= 0 then return end
        local range = max - min
        local pct = range > 0 and ((value or slider:GetValue()) - min) / range or 0
        fillTex:SetWidth(math.max(minFill, w * math.max(0, math.min(1, pct))))
    end
    track:SetScript("OnSizeChanged", function() UpdateFill() end)

    if Motion and Motion.Hover then
        Motion.Hover(slider, {
            key = "sliderHover", duration = 0.09, ease = "outCubic", hook = true,
            apply = function(_, t)
                local k = 1 + 0.12 * t
                thumb:SetSize(tw * k, th * k)
                local n, h = C.text.normal, C.text.highlight
                thumb:SetColorTexture(n[1] + (h[1] - n[1]) * t, n[2] + (h[2] - n[2]) * t, n[3] + (h[3] - n[3]) * t, 1)
                track:SetBackdropBorderColor(u(t > 0.5 and C.border.active or C.border.default))
            end,
        })
    end

    -- min / max labels
    local minLabel = MakeFont(container, F.small, nil, C.text.dim)
    minLabel:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -4)
    minLabel:SetText(tostring(min))

    local maxLabel = MakeFont(container, F.small, nil, C.text.dim)
    maxLabel:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -4)
    maxLabel:SetText(tostring(max))

    -- editable value box (right of the track)
    local valBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    valBox:SetSize(SPEC.valueWidth, SPEC.valueHeight)
    valBox:SetPoint("LEFT", track, "RIGHT", SPEC.valueGap, 0)
    valBox:SetFont(F.path, F.normal, "")
    valBox:SetTextColor(u(C.text.highlight))
    valBox:SetJustifyH("CENTER")
    valBox:SetAutoFocus(false)
    valBox:SetNumeric(false) -- allow decimals as text
    ApplyBackdrop(valBox, C.bg.input, C.border.default, Lib.Radius.control)

    -- format helper (reused for initial display and OnValueChanged)
    local decimals = step < 1 and math.max(1, math.ceil(-math.log10(step))) or 0
    local fmtStr = "%." .. decimals .. "f"
    valBox:SetText(string.format(fmtStr, clamped))

    -- sync slider → valBox
    slider:SetScript("OnValueChanged", function(self, value)
        value = tonumber(string.format(fmtStr, value))
        valBox:SetText(tostring(value))
        UpdateFill(value)
        if opts.onChange then opts.onChange(value) end
    end)
    UpdateFill(clamped)

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
            local text = o.text or o.label or o[1]
            local value
            if o.value ~= nil then
                value = o.value
            elseif o[2] ~= nil then
                value = o[2]
            else
                value = o[1] or text
            end
            items[#items + 1] = { text = tostring(text or value or ""), value = value }
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
    ApplyBackdrop(btn, C.bg.input, C.border.default, Lib.Radius.control)
    btn:RegisterForClicks("LeftButtonUp")
    EnableRightClickMouselook(btn)

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
        btn:SetScript("OnClick", function() end)
        container.button = btn
        container.label = lbl
        container.SetOptions = function() end
        function container:SetValue() end
        function container:GetValue() return self._value end
        function container:GetText() return self._text end
        return container
    end
    local totalH = #items * 22 + 2
    local visibleH = math.min(totalH, MAX_VISIBLE * 22 + 2)
    local needsScroll = #items > MAX_VISIBLE

    local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
    list:SetWidth(width)
    list:SetHeight(visibleH)
    ApplyBackdrop(list, C.bg.main, C.border.default, Lib.Radius.row)
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
        row:RegisterForClicks("LeftButtonUp")
        EnableRightClickMouselook(row)

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
--- "DDing" (white) + "UI" (orange) + addon display name (accent gradient).
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
-- Series minimap button  -- [STYLE]
------------------------------------------------------
local MINIMAP_TEXT = {
    koKR = { left = "좌클릭", right = "우클릭", drag = "드래그",
             leftDesc = "설정 창 열기/닫기", rightDesc = "편집 모드 · 위치 조정", dragDesc = "버튼 위치 이동" },
    enUS = { left = "Left-click", right = "Right-click", drag = "Drag",
             leftDesc = "Toggle settings", rightDesc = "Edit mode / adjust position", dragDesc = "Move button" },
}

--- Series tooltip: addon title, then left/right/drag lines (action white, description 0.7, two spaces).
--- @param tooltip GameTooltip
--- @param addonKey string       accent preset key
--- @param displayName string    text after "DDingUI "
--- @param opts table|nil { leftText, rightText, dragText } override descriptions; rightText=false hides the line
function Lib.AddMinimapTooltip(tooltip, addonKey, displayName, opts)
    opts = opts or {}
    local t = MINIMAP_TEXT[GetLocale and GetLocale()] or MINIMAP_TEXT.enUS
    tooltip:SetText(Lib.CreateAddonTitle(addonKey, displayName))
    tooltip:AddLine("|cffffffff" .. t.left .. "|r  " .. (opts.leftText or t.leftDesc), 0.7, 0.7, 0.7)
    if opts.rightText ~= false then
        tooltip:AddLine("|cffffffff" .. t.right .. "|r  " .. (opts.rightText or t.rightDesc), 0.7, 0.7, 0.7)
    end
    tooltip:AddLine("|cffffffff" .. t.drag .. "|r  " .. (opts.dragText or t.dragDesc), 0.7, 0.7, 0.7)
end

--- Series minimap button (LibDataBroker-1.1 + LibDBIcon-1.0, same as CDM/Toolkit/RaidHelper).
--- The addon must embed both libraries; returns nil when they (or the saved position table) are missing.
--- @param opts table {
---   key          string   LDB/LibDBIcon name (usually the addon folder name)
---   addonKey     string   accent preset key for the tooltip title
---   displayName  string   text after "DDingUI "
---   icon         string   addon's own icon texture path
---   db           table    LibDBIcon saved table ({ hide, minimapPos })
---   onLeftClick  function|nil  default action: toggle settings window
---   onRightClick function|nil  default action: edit mode / position adjust
---   leftText, rightText, dragText  string|nil  tooltip description overrides (see AddMinimapTooltip)
--- }
--- @return table|nil dataObject, table|nil LibDBIcon
function Lib.CreateMinimapButton(opts)
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if not (opts and opts.key and opts.db and LDB and LibDBIcon) then return nil end

    local rightText = opts.rightText
    if rightText == nil and not opts.onRightClick then
        rightText = false -- no right-click action: hide the line
    end
    local tooltipOpts = {
        leftText = opts.leftText,
        rightText = rightText,
        dragText = opts.dragText,
    }
    local dataObj = LDB:GetDataObjectByName(opts.key) or LDB:NewDataObject(opts.key, {
        type = "launcher",
        icon = opts.icon,
        label = "DDingUI " .. (opts.displayName or opts.key),
        OnClick = function(_, button)
            if button == "LeftButton" and opts.onLeftClick then
                opts.onLeftClick()
            elseif button == "RightButton" and opts.onRightClick then
                opts.onRightClick()
            end
        end,
        OnTooltipShow = function(tooltip)
            Lib.AddMinimapTooltip(tooltip, opts.addonKey, opts.displayName, tooltipOpts)
        end,
    })
    if not dataObj then return nil end

    if not LibDBIcon:IsRegistered(opts.key) then
        LibDBIcon:Register(opts.key, dataObj, opts.db)
    end
    return dataObj, LibDBIcon
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
    ApplyBackdrop(search, C.bg.input, { 0, 0, 0, 1 }, Lib.Radius.control)

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
    bar.bg = SolidBG(bar, C.bg.titlebar)

    -- accent gradient line (2px, inside bar top edge)
    local accentLine = Lib.CreateHorizontalGradient(bar, from, to, 2)
    accentLine:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    accentLine:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)

    -- [STYLE] StyleLib 1.3: on a rounded window the bar is part of the window surface;
    -- a rectangular bar background or edge line would poke out of the rounded corners.
    local roundedParent = parent._ddslRounded or opts.rounded
    if roundedParent then
        bar.bg:Hide()
        accentLine:Hide()
    end

    -- Suite headers use the fixed white/orange wordmark and a separate series gradient.
    local titleText = MakeFont(bar, F.title, nil, { 1, 1, 1, 1 })
    titleText:SetPoint("LEFT", 10, 0)
    local displayName = title and title:match("^DDingUI%s+(.+)$")
    local brandFolder = ({
        CDM = "DDingUI_CDM",
        MJToolkit = "DDingUI_Toolkit",
        RaidHelper = "DDingUI_RaidHelper",
        FX = "DDingUI_FX",
    })[addonName]
    if displayName and brandFolder then
        -- [STYLE] StyleLib 1.3: the series symbol is built from the two ring pieces of
        -- Branding/DDingUI_Symbol_Orange.png, tinted with each addon's logo colour, and the
        -- rings slide together whenever the window opens.
        local logoColor = ({ CDM = { 1, 0.416, 0, 1 } })[addonName] or from
        local logo = Lib.CreateLogoRings(bar, 22, logoColor)
        logo:SetPoint("LEFT", bar, "LEFT", 10, 0)
        if parent.HookScript then
            parent:HookScript("OnShow", function() logo:PlayLink() end)
        end
        bar.brandLogo = logo
        local brand = bar:CreateTexture(nil, "ARTWORK")
        brand:SetTexture("Interface\\AddOns\\" .. brandFolder .. "\\Media\\logo_wordmark.tga")
        -- Sample only the fixed white/orange typography; the symbol has its own colour.
        brand:SetTexCoord(184 / 512, 464 / 512, 20 / 128, 108 / 128)
        brand:SetSize(70, 22)
        brand:SetPoint("LEFT", logo, "RIGHT", 8, 0)
        brand:SetVertexColor(1, 1, 1, 1)
        bar.brandTexture = brand
        titleText:ClearAllPoints()
        titleText:SetPoint("LEFT", brand, "RIGHT", 8, 0)
        titleText:SetText(Lib.CreateGradientText(addonName, displayName))
    elseif displayName then
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
        if parent.HideAnimated then
            parent:HideAnimated()
        elseif Motion then
            Motion.PanelClose(parent)
        else
            parent:Hide()
        end
    end)

    bar.accentLine = accentLine
    bar.titleText  = titleText
    bar.verText    = verText
    bar.closeBtn   = closeBtn
    -- [STYLE] C12: 시리즈 공통 "편집 모드" 버튼. opts.editMode = { onClick = fn, isActive = fn }
    -- 닫기(와 GUI 크기) 왼쪽에 놓이고, isActive()가 참이면 "편집 중"으로 바뀐다.
    if opts.editMode and opts.editMode.onClick then
        local em = opts.editMode
        local editBtn = Lib.CreateButton(bar, addonName, "편집 모드", function() em.onClick() end,
            { width = 76, height = 22 })
        editBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
        function editBtn:Refresh()
            local active = em.isActive and em.isActive() or false
            if self.label then self.label:SetText(active and "편집 중" or "편집 모드") end
        end
        editBtn:Refresh()
        bar.editButton = editBtn
    end
    if opts.scale then
        bar.scaleControl = Lib.CreateTitleScaleControl(bar, addonName, opts.scale)
        -- 순서(오른쪽→왼쪽): 닫기 · 편집 모드 · GUI 크기
        bar.scaleControl:SetPoint("RIGHT", bar.editButton or closeBtn, "LEFT", -8, 0)
    end
    return bar
end

------------------------------------------------------
-- Title-bar "GUI 크기" control (series standard, from CDM)  -- [STYLE]
------------------------------------------------------
--- @param parent Frame  title bar
--- @param addonName string  accent key
--- @param cfg table { get=function()->number, set=function(value), target=Frame (window),
---                    min=0.5, max=1.5, step=0.05, label="GUI 크기" }
--- @return Frame container (caller anchors it; 184x24)
function Lib.CreateTitleScaleControl(parent, addonName, cfg)
    cfg = cfg or {}
    local from = Lib.GetAccent(addonName)
    local lo, hi, step = cfg.min or 0.5, cfg.max or 1.5, cfg.step or 0.05
    local target = cfg.target or parent:GetParent()
    local trackW = 56

    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(184, 24)

    local lbl = MakeFont(box, F.small, nil, C.text.dim)
    lbl:SetPoint("LEFT", box, "LEFT", 0, 0)
    lbl:SetText(cfg.label or (GetLocale and GetLocale() == "koKR" and "GUI 크기" or "GUI Scale"))

    local valueText = MakeFont(box, F.small, nil, C.text.normal)
    valueText:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    valueText:SetWidth(36)
    valueText:SetJustifyH("RIGHT")

    local track = CreateFrame("Frame", nil, box, "BackdropTemplate")
    track:SetSize(trackW, 6)
    track:SetPoint("RIGHT", valueText, "LEFT", -6, 0)
    ApplyBackdrop(track, C.bg.input, C.border.default, Lib.Radius.track)

    local fillTex = track:CreateTexture(nil, "ARTWORK")
    local minFill = 1
    if Lib.Rounded then -- [STYLE] pill fill
        fillTex:SetPoint("TOPLEFT", 0, 0)
        fillTex:SetPoint("BOTTOMLEFT", 0, 0)
        Lib.RoundTexture(fillTex, Lib.Radius.track)
        fillTex:SetVertexColor(from[1], from[2], from[3], 1)
        minFill = 6
    else
        fillTex:SetPoint("TOPLEFT", 1, -1)
        fillTex:SetPoint("BOTTOMLEFT", 1, 1)
        fillTex:SetColorTexture(from[1], from[2], from[3], 1)
    end

    local slider = CreateFrame("Slider", nil, box)
    slider:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 10)
    slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -10)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(lo, hi)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 14)
    thumb:SetColorTexture(u(C.text.normal))
    slider:SetThumbTexture(thumb)

    local function Snap(v)
        v = math.max(lo, math.min(hi, tonumber(v) or 1))
        return math.floor(v / step + 0.5) * step
    end

    local function Show(v)
        valueText:SetText(string.format("%.0f%%", v * 100))
        local pct = (hi > lo) and (v - lo) / (hi - lo) or 0
        fillTex:SetWidth(math.max(minFill, (trackW - 2) * pct))
    end

    local function Apply(v)
        v = Snap(v)
        if cfg.set then cfg.set(v) end
        if target then
            if target.SetBaseScale then target:SetBaseScale(v) else target:SetScale(v) end
        end
    end

    local current = Snap(cfg.get and cfg.get() or 1)
    slider:SetValue(current)
    Show(current)

    slider:SetScript("OnValueChanged", function(self, v)
        v = Snap(v)
        self._pending = v
        Show(v)
    end)
    slider:SetScript("OnMouseUp", function(self)
        Apply(self._pending or self:GetValue())
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        local v = Snap(self:GetValue() + (delta > 0 and step or -step))
        self:SetValue(v)
        Apply(v)
    end)

    if Motion and Motion.Hover then
        Motion.Hover(slider, {
            key = "scaleHover", duration = 0.09, hook = true,
            apply = function(_, t)
                thumb:SetSize(10, 14 + 2 * t)
                track:SetBackdropBorderColor(u(t > 0.5 and C.border.active or C.border.default))
            end,
            onEnter = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
                GameTooltip:SetText(lbl:GetText(), 1, 1, 1)
                GameTooltip:AddLine(GetLocale and GetLocale() == "koKR" and "휠 또는 드래그로 설정 창 크기 조절 (50~150%)"
                    or "Wheel or drag to scale this window (50-150%)", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end,
            onLeave = function() GameTooltip:Hide() end,
        })
    end

    function box:Refresh()
        local v = Snap(cfg.get and cfg.get() or 1)
        slider:SetValue(v)
        Show(v)
    end

    box.slider = slider
    box.valueText = valueText
    return box
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
                icon = item.icon,
                iconCoords = item.iconCoords,
                disabled = item.disabled,
                desc = item.desc,
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

        for i, item in ipairs(visible) do
            local btn = tree._buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, child)
                btn:SetHeight(ITEM_H)
                btn._bg   = SolidBG(btn, { 0, 0, 0, 0 })
                btn._icon = MakeFont(btn, F.normal, nil, C.text.dim)
                btn._icon:SetPoint("LEFT", 4, 0)
                btn._text = MakeFont(btn, F.normal, nil, C.text.normal)
                btn._spellIcon = btn:CreateTexture(nil, "ARTWORK")
                btn._spellIcon:SetSize(16, 16)
                btn._spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                btn._spellIcon:Hide()
                -- accent stripe on left edge (selected indicator) -- [STYLE]
                btn._stripe = btn:CreateTexture(nil, "OVERLAY")
                btn._stripe:SetWidth(2)
                btn._stripe:SetPoint("TOPLEFT", 0, 0)
                btn._stripe:SetPoint("BOTTOMLEFT", 0, 0)
                btn._stripe:SetColorTexture(from[1], from[2], from[3], 1)
                btn._stripe:Hide()
                tree._buttons[i] = btn
            end

            btn:Show()
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -((i - 1) * (ITEM_H + S.treeItemGap)))
            btn:SetPoint("RIGHT", child, "RIGHT", 0, 0)

            local indent = item.level * INDENT + 4
            btn._icon:ClearAllPoints()
            btn._icon:SetPoint("LEFT", indent, 0)

            if item.icon then
                btn._spellIcon:SetTexture(item.icon)
                btn._spellIcon:ClearAllPoints()
                if item.iconCoords then
                    btn._spellIcon:SetTexCoord(unpack(item.iconCoords))
                else
                    btn._spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                btn._spellIcon:Show()
            else
                btn._spellIcon:Hide()
            end

            local hasSpellIcon = item.icon and true or false

            if item.hasChildren then
                btn._icon:SetText(expanded[item.key] and "\226\150\188" or "\226\150\182") -- ▼ or ▶
                btn._icon:Show()
                if hasSpellIcon then
                    btn._spellIcon:SetPoint("LEFT", indent + 14, 0)
                    btn._text:ClearAllPoints()
                    btn._text:SetPoint("LEFT", indent + 14 + 20, 0)
                    btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                else
                    btn._text:ClearAllPoints()
                    btn._text:SetPoint("LEFT", indent + 14, 0)
                    btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                end
            else
                btn._icon:Hide()
                local baseIndent = indent + (item.level > 0 and 14 or 0)
                if hasSpellIcon then
                    btn._spellIcon:SetPoint("LEFT", baseIndent, 0)
                    btn._text:ClearAllPoints()
                    btn._text:SetPoint("LEFT", baseIndent + 20, 0)
                    btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                else
                    btn._text:ClearAllPoints()
                    btn._text:SetPoint("LEFT", baseIndent, 0)
                    btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                end
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

            if item.disabled then
                btn._text:SetTextColor(0.4, 0.4, 0.4, 1)
                if btn._spellIcon then btn._spellIcon:SetAlpha(0.4) end
            else
                if btn._spellIcon then btn._spellIcon:SetAlpha(1.0) end
            end

            -- hover + tooltip
            local key = item.key
            local hasKids = item.hasChildren
            local itemDesc = item.desc
            local itemText = item.text
            btn:SetScript("OnEnter", function(self)
                if key ~= selectedKey then
                    self._bg:SetColorTexture(u(C.bg.hover))
                end
                if itemDesc and itemDesc ~= "" then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(itemText or "", 1, 1, 1)
                    GameTooltip:AddLine(itemDesc, 0.8, 0.8, 0.8, true)
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
            btn:SetScript("OnMouseDown", function(_, button)
                if button == "RightButton" and not tree.onRightClick then
                    StartRightButtonMouselook()
                end
            end)
            btn:SetScript("OnMouseUp", function(_, button)
                if button == "RightButton" and not tree.onRightClick then
                    StopRightButtonMouselook()
                end
            end)
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
        local total = #visible * (ITEM_H + S.treeItemGap)
        child:SetHeight(math.max(total, tree:GetHeight()))
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
-- AllowOffscreen -- [STYLE]
------------------------------------------------------
Lib.OffscreenKeep = 64 -- 화면 안에 항상 남기는 폭/높이(px)

--- 설정창을 화면 가장자리 밖으로 걸쳐 둘 수 있게 한다.
--- 좌우·아래로는 keep 픽셀만 남기고 밀어낼 수 있고, 위쪽(제목줄)은 화면 안에 남아
--- 언제든 다시 잡아 끌 수 있다. 창 크기가 바뀌면 범위를 다시 계산한다.
--- @param frame Frame
--- @param keep number|nil 화면 안에 남길 픽셀 (기본 Lib.OffscreenKeep)
function Lib.AllowOffscreen(frame, keep)
    if not frame or not frame.SetClampRectInsets then return end
    frame._ddslOffscreenKeep = keep or frame._ddslOffscreenKeep or Lib.OffscreenKeep
    local function apply(self)
        local k = self._ddslOffscreenKeep or Lib.OffscreenKeep
        local x = math.max(0, (self:GetWidth() or 0) - k)
        local y = math.max(0, (self:GetHeight() or 0) - k)
        self:SetClampRectInsets(x, -x, 0, y)
    end
    frame:SetClampedToScreen(true)
    apply(frame)
    if not frame._ddslOffscreenHooked then
        frame._ddslOffscreenHooked = true
        frame:HookScript("OnSizeChanged", apply)
    end
end

------------------------------------------------------
-- CreateSettingsPanel
------------------------------------------------------
--- Full settings panel skeleton: titlebar + tree + scrollable content.
--- @param addonName string
--- @param title string
--- @param version string
--- @param opts table|nil { width, height, minWidth, minHeight, menuWidth, scale, editMode }
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
        if existingFrame.ShowAnimated then
            existingFrame:ShowAnimated()
        else
            existingFrame:Show()
        end
        return existingFrame._panelResult or { frame = existingFrame }
    end
    local frame = CreateFrame("Frame", panelName, UIParent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    ApplyBackdrop(frame, C.bg.main, C.border.default, Lib.Radius.window)
    frame._ddslMotionBaseScale = frame:GetScale() or 1

    local function IsPanelAnimating()
        local jobs = frame._ddslMotionJobs
        return jobs and (jobs.panelOpen or jobs.panelClose) and true or false
    end

    local function MotionOpts(motionOpts)
        motionOpts = motionOpts or {}
        -- [STYLE] A scale set after creation (e.g. saved GUI 크기) is the new base while idle;
        -- previously the creation-time 1.0 was reused and every open reset the window size.
        if not IsPanelAnimating() then
            frame._ddslMotionBaseScale = frame:GetScale() or frame._ddslMotionBaseScale or 1
        end
        motionOpts.baseScale = motionOpts.baseScale or frame._ddslMotionBaseScale
        return motionOpts
    end

    function frame:SetBaseScale(scale)
        scale = tonumber(scale) or 1
        if Motion then
            Motion.Stop(self, "panelOpen", true)   -- finish the open so alpha lands on 1
            Motion.Stop(self, "panelClose")        -- never finish a close here (it would hide)
            self:SetAlpha(1)
        end
        self._ddslMotionBaseScale = scale
        self:SetScale(scale)
    end

    function frame:ShowAnimated(motionOpts)
        if Motion then
            Motion.PanelOpen(self, MotionOpts(motionOpts))
        else
            self:Show()
        end
    end

    function frame:HideAnimated(motionOpts)
        if Motion then
            Motion.PanelClose(self, MotionOpts(motionOpts))
        else
            self:Hide()
        end
    end

    -- draggable
    frame:SetMovable(true)
    Lib.AllowOffscreen(frame) -- [STYLE] 가장자리 밖으로 걸쳐 둘 수 있게

    -- resizable
    frame:SetResizable(true)
    frame:SetResizeBounds(opts.minWidth or 600, opts.minHeight or 400)

    -- Compact L-shaped resize grip.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(28, 28)
    grip:SetPoint("BOTTOMRIGHT", -5, 5)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)
    EnableRightClickMouselook(grip)

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
    local titleBar = Lib.CreateTitleBar(frame, addonName, title, version,
        { scale = opts.scale, editMode = opts.editMode }) -- [STYLE] C12 편집 모드 버튼도 전달
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)
    EnableRightClickMouselook(titleBar)

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
    EnableRightClickMouselook(treeFrame)

    -- content area (right, scrollable)
    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", menuW + 1, -35)
    contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)

    local contentScroll, contentChild = CreateScrollFrame(contentFrame)
    EnableRightClickMouselook(contentFrame)
    EnableRightClickMouselook(contentScroll)
    EnableRightClickMouselook(frame)

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
