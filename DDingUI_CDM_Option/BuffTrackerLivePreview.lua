local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local GUI = DDingUI.GUI
local SL = _G.DDingUI_StyleLib
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local THEME = GUI.THEME

local Preview = {}
GUI.BuffTrackerLivePreview = Preview

local FALLBACK_ICON = "Interface\\Icons\\Spell_Holy_MagicalSentry"
local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local GLOW_KEY = "_DDingUITrackerPreview"
local VALID_POINTS = {
    CENTER = true,
    TOP = true,
    BOTTOM = true,
    LEFT = true,
    RIGHT = true,
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function ReadSetting(entry, key, fallback)
    if type(entry) ~= "table" then return fallback end
    local settings = entry.settings
    if type(settings) == "table" and settings[key] ~= nil then
        return settings[key]
    end
    local display = entry.display
    if type(display) == "table" and display[key] ~= nil then
        return display[key]
    end
    if entry[key] ~= nil then return entry[key] end
    return fallback
end

local function ReadRootSetting(key, fallback)
    local profile = DDingUI.db and DDingUI.db.profile
    local root = profile and profile.buffTrackerBar
    if type(root) == "table" and root[key] ~= nil then
        return root[key]
    end
    return fallback
end

local function ReadColor(value, fallback)
    fallback = fallback or { 1, 1, 1, 1 }
    if type(value) ~= "table" then
        return fallback[1], fallback[2], fallback[3], fallback[4] or 1
    end
    local r = tonumber(value.r or value[1])
    local g = tonumber(value.g or value[2])
    local b = tonumber(value.b or value[3])
    local a = tonumber(value.a or value[4])
    if not r or not g or not b then
        return fallback[1], fallback[2], fallback[3], fallback[4] or 1
    end
    return r, g, b, a or 1
end

local function ColorTable(value, fallback)
    local r, g, b, a = ReadColor(value, fallback)
    return { r, g, b, a }
end

local function ResolveFont(name)
    if DDingUI.GetFont then
        return DDingUI:GetFont(name) or DEFAULT_FONT
    end
    return DEFAULT_FONT
end

local function ResolveTexture(name)
    if DDingUI.GetTexture then
        return DDingUI:GetTexture(name) or FLAT
    end
    return FLAT
end

local function ResolveIcon(entry)
    if type(entry) ~= "table" then return FALLBACK_ICON end
    local iconSource = ReadSetting(entry, "iconSource", "buff")
    local customIconID = tonumber(ReadSetting(entry, "customIconID", 0)) or 0
    local candidate = iconSource == "custom" and customIconID > 0 and customIconID or entry.icon
    if candidate and candidate ~= 0 then
        if type(candidate) == "number" and C_Spell and C_Spell.GetSpellTexture then
            local spellTexture = C_Spell.GetSpellTexture(candidate)
            if spellTexture then return spellTexture end
        end
        return candidate
    end
    local spellID = tonumber(entry.spellID or (entry.trigger and entry.trigger.spellID))
    if spellID and spellID > 0 and C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID) or FALLBACK_ICON
    end
    return FALLBACK_ICON
end

local function CreateEdges(parent, layer)
    local edges = {}
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        local texture = parent:CreateTexture(nil, layer or "OVERLAY")
        texture:SetColorTexture(1, 1, 1, 1)
        texture:Hide()
        edges[key] = texture
    end
    return edges
end

local function ApplyEdges(edges, target, size, color)
    size = Clamp(size or 0, 0, 8)
    local shown = size > 0
    for _, edge in pairs(edges) do
        edge:SetShown(shown)
    end
    if not shown then return end

    local r, g, b, a = ReadColor(color, { 0, 0, 0, 1 })
    for _, edge in pairs(edges) do
        edge:SetColorTexture(r, g, b, a)
        edge:ClearAllPoints()
    end
    edges.top:SetPoint("TOPLEFT", target, "TOPLEFT", -size, size)
    edges.top:SetPoint("TOPRIGHT", target, "TOPRIGHT", size, size)
    edges.top:SetHeight(size)
    edges.bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -size, -size)
    edges.bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", size, -size)
    edges.bottom:SetHeight(size)
    edges.left:SetPoint("TOPLEFT", target, "TOPLEFT", -size, 0)
    edges.left:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -size, 0)
    edges.left:SetWidth(size)
    edges.right:SetPoint("TOPRIGHT", target, "TOPRIGHT", size, 0)
    edges.right:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", size, 0)
    edges.right:SetWidth(size)
end

local function ApplyFont(fontString, fontName, size, outline)
    fontString:SetFont(ResolveFont(fontName), Clamp(size or 12, 6, 48), outline or "OUTLINE")
end

local function ApplyTextAnchor(fontString, target, point, x, y)
    point = VALID_POINTS[point] and point or "CENTER"
    fontString:ClearAllPoints()
    fontString:SetPoint(point, target, point, tonumber(x) or 0, tonumber(y) or 0)
    if point:find("LEFT", 1, true) then
        fontString:SetJustifyH("LEFT")
    elseif point:find("RIGHT", 1, true) then
        fontString:SetJustifyH("RIGHT")
    else
        fontString:SetJustifyH("CENTER")
    end
end

local function StopPreviewEffects(frame)
    if not frame then return end
    if SL and SL.HideAllGlows then
        SL.HideAllGlows(frame, GLOW_KEY)
    end
    local glow = LibStub("LibCustomGlow-1.0", true)
    if glow and glow.ProcGlow_Stop then
        glow.ProcGlow_Stop(frame, GLOW_KEY)
    end
    if frame._previewAnimation and frame._previewAnimation:IsPlaying() then
        frame._previewAnimation:Stop()
    end
    frame._previewAnimation = nil
    frame:SetAlpha(1)
    frame:SetScale(1)
end

local function StartMotion(frame, animationType, iconTexture)
    local group = (animationType == "spin" and iconTexture or frame):CreateAnimationGroup()
    if animationType == "hover" then
        local up = group:CreateAnimation("Translation")
        up:SetOffset(0, 3)
        up:SetDuration(0.35)
        up:SetOrder(1)
        local down = group:CreateAnimation("Translation")
        down:SetOffset(0, -3)
        down:SetDuration(0.35)
        down:SetOrder(2)
    elseif animationType == "pulse" then
        local up = group:CreateAnimation("Scale")
        up:SetScale(1.08, 1.08)
        up:SetDuration(0.4)
        up:SetOrder(1)
        local down = group:CreateAnimation("Scale")
        down:SetScale(1 / 1.08, 1 / 1.08)
        down:SetDuration(0.4)
        down:SetOrder(2)
    elseif animationType == "flash" then
        local out = group:CreateAnimation("Alpha")
        out:SetFromAlpha(1)
        out:SetToAlpha(0.35)
        out:SetDuration(0.4)
        out:SetOrder(1)
        local incoming = group:CreateAnimation("Alpha")
        incoming:SetFromAlpha(0.35)
        incoming:SetToAlpha(1)
        incoming:SetDuration(0.4)
        incoming:SetOrder(2)
    elseif animationType == "spin" then
        local spin = group:CreateAnimation("Rotation")
        spin:SetDegrees(360)
        spin:SetDuration(2)
        spin:SetOrder(1)
    else
        return
    end
    group:SetLooping("REPEAT")
    frame._previewAnimation = group
    group:Play()
end

local function ApplyPreviewEffect(frame, iconTexture, entry)
    StopPreviewEffects(frame)
    local animationType = ReadSetting(entry, "iconAnimation", "button")
    if animationType == "none" then return end
    if animationType == "hover" or animationType == "pulse" or animationType == "flash" or animationType == "spin" then
        StartMotion(frame, animationType, iconTexture)
        return
    end

    local color = ColorTable(ReadSetting(entry, "glowColor"), { 1, 0.9, 0.5, 1 })
    local lines = math.floor(Clamp(ReadSetting(entry, "glowLines", 8), 1, 20))
    local frequency = Clamp(ReadSetting(entry, "glowFrequency", 0.25), 0.05, 2)
    local thickness = Clamp(ReadSetting(entry, "glowThickness", 2), 1, 10)
    local xOffset = tonumber(ReadSetting(entry, "glowXOffset", 0)) or 0
    local yOffset = tonumber(ReadSetting(entry, "glowYOffset", 0)) or 0
    if animationType == "pixel" or animationType == "shine" then
        if SL and SL.ShowPixelGlow then
            SL.ShowPixelGlow(frame, color, lines, frequency, nil, thickness, xOffset, yOffset, false, GLOW_KEY)
        end
    elseif animationType == "autocast" then
        if SL and SL.ShowAutocastGlow then
            SL.ShowAutocastGlow(frame, color, lines, frequency, thickness, xOffset, yOffset, GLOW_KEY)
        end
    elseif animationType == "proc" then
        local glow = LibStub("LibCustomGlow-1.0", true)
        if glow and glow.ProcGlow_Start then
            glow.ProcGlow_Start(frame, { color = color, duration = frequency, startAnim = true, key = GLOW_KEY })
        end
    elseif SL and SL.ShowButtonGlow then
        SL.ShowButtonGlow(frame, color, frequency)
    end
end

local function FitSize(canvas, width, height, horizontalPadding, verticalPadding)
    local availableWidth = math.max(40, (canvas:GetWidth() or 420) - (horizontalPadding or 36))
    local availableHeight = math.max(20, (canvas:GetHeight() or 80) - (verticalPadding or 28))
    local scale = math.min(1, availableWidth / width, availableHeight / height)
    return math.max(1, width * scale), math.max(1, height * scale), scale
end

local function FitBarSize(canvas, width, height, horizontalPadding, verticalPadding)
    local canvasWidth = canvas:GetWidth() or 0
    local canvasHeight = canvas:GetHeight() or 0
    if canvasWidth < 160 then canvasWidth = 420 end
    if canvasHeight < 50 then canvasHeight = 80 end

    local availableWidth = math.max(40, canvasWidth - (horizontalPadding or 36))
    local availableHeight = math.max(20, canvasHeight - (verticalPadding or 28))
    return math.max(1, math.min(width, availableWidth)), math.max(1, math.min(height, availableHeight))
end

local function SetCooldownSample(cooldown, texture, color, reverse)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetReverse(reverse == true)
    cooldown:SetSwipeTexture(texture or FLAT, 1, 1, 1, 1)
    local r, g, b, a = ReadColor(color, { 0, 0, 0, 0.65 })
    cooldown:SetSwipeColor(r, g, b, a)
    cooldown:SetCooldown(GetTime() - 9.6, 30)
end

local function CreateBarVisual(canvas)
    local host = CreateFrame("Frame", nil, canvas)
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetAllPoints(host)
    bar:SetMinMaxValues(0, 1)
    local background = host:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(host)
    local edges = CreateEdges(host)
    local tickFrame = CreateFrame("Frame", nil, host)
    tickFrame:SetAllPoints(host)
    tickFrame:SetFrameLevel(bar:GetFrameLevel() + 1)
    local textFrame = CreateFrame("Frame", nil, host)
    textFrame:SetAllPoints(host)
    textFrame:SetFrameLevel(tickFrame:GetFrameLevel() + 1)
    local stacks = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local duration = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    host.bar = bar
    host.background = background
    host.edges = edges
    host.tickFrame = tickFrame
    host.ticks = {}
    host.stacks = stacks
    host.duration = duration
    return host
end

local function CreateIconVisual(canvas)
    local host = CreateFrame("Frame", nil, canvas)
    local icon = host:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(host)
    local cooldown = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
    cooldown:SetAllPoints(host)
    local edges = CreateEdges(host, "OVERLAY")
    local stacks = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local duration = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    host.icon = icon
    host.cooldown = cooldown
    host.edges = edges
    host.stacks = stacks
    host.duration = duration
    return host
end

local function CreateRingVisual(canvas)
    local host = CreateFrame("Frame", nil, canvas)
    local border = host:CreateTexture(nil, "BACKGROUND", nil, -1)
    local background = host:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(host)
    local cooldown = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
    cooldown:SetAllPoints(host)
    local duration = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    duration:SetPoint("CENTER")
    host.border = border
    host.background = background
    host.cooldown = cooldown
    host.duration = duration
    return host
end

local function CreateTextVisual(canvas)
    local host = CreateFrame("Frame", nil, canvas)
    local icon = host:CreateTexture(nil, "ARTWORK")
    local value = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local duration = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    host.icon = icon
    host.value = value
    host.duration = duration
    return host
end

local function CreatePassiveVisual(canvas)
    local host = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    host:SetSize(210, 46)
    host:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    host:SetBackdropColor(THEME.panelRaised[1], THEME.panelRaised[2], THEME.panelRaised[3], 1)
    host:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.9)
    local icon = host:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, -2)
    local detail = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 9, 2)
    host.icon = icon
    host.title = title
    host.detail = detail
    return host
end

local function CreateGroupVisual(canvas)
    local host = CreateFrame("Frame", nil, canvas)
    host.slots = {}
    for index = 1, 6 do
        local slot = CreateFrame("Frame", nil, host, "BackdropTemplate")
        slot:SetSize(30, 30)
        slot:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        slot:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], 1)
        slot:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon = icon
        host.slots[index] = slot
    end
    return host
end

local function RenderBar(preview, entry)
    local host = preview.barVisual
    local width = tonumber(ReadSetting(entry, "width", 0)) or 0
    if width <= 0 then
        width = tonumber(ReadRootSetting("width", 0)) or 0
    end
    if width <= 0 then
        local attachTo = ReadSetting(entry, "attachTo", ReadRootSetting("attachTo", "UIParent"))
        local anchor = DDingUI.ResolveAnchorFrame and DDingUI:ResolveAnchorFrame(attachTo) or UIParent
        local resolver = DDingUI.ResourceBars and DDingUI.ResourceBars.ResolveTrackerAutoWidth
        width = resolver and resolver(nil, anchor, ReadSetting(entry, "borderSize", ReadRootSetting("borderSize", 1))) or 200
    elseif DDingUI.Scale then
        width = DDingUI:Scale(width)
    end
    local height = Clamp(ReadSetting(entry, "height", ReadRootSetting("height", 6)), 2, 160)
    if DDingUI.Scale then height = DDingUI:Scale(height) end
    local orientation = ReadSetting(entry, "barOrientation", "HORIZONTAL")
    if orientation == "VERTICAL" then width, height = height, width end
    width, height = FitBarSize(preview.canvas, width, height, 42, 34)

    host:SetSize(width, height)
    host:ClearAllPoints()
    host:SetPoint("CENTER", preview.canvas, "CENTER", 0, -5)
    host.bar:SetOrientation(orientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL")
    host.bar:SetReverseFill(ReadSetting(entry, "barReverseFill", false) == true)
    host.bar:SetStatusBarTexture(ResolveTexture(ReadSetting(entry, "texture", ReadRootSetting("texture"))))
    local barColor = ReadSetting(entry, "barColor") or { 1, 0.8, 0, 1 }
    if SL and SL.ApplyBarColor then
        SL.ApplyBarColor(host.bar, barColor)
    else
        local r, g, b, a = ReadColor(barColor, { 1, 0.8, 0, 1 })
        host.bar:SetStatusBarColor(r, g, b, a)
    end
    local br, bg, bb, ba = ReadColor(ReadSetting(entry, "bgColor", ReadRootSetting("bgColor")), { 0.15, 0.15, 0.15, 1 })
    host.background:SetColorTexture(br, bg, bb, ba)
    local borderSize = ReadSetting(entry, "borderSize", ReadRootSetting("borderSize", 1))
    if DDingUI.ScaleBorder then borderSize = DDingUI:ScaleBorder(borderSize) end
    ApplyEdges(host.edges, host, borderSize, ReadSetting(entry, "borderColor", ReadRootSetting("borderColor")))

    local fillMode = ReadSetting(entry, "barFillMode", "duration")
    local maximum = math.max(1, tonumber(ReadSetting(entry, "maxStacks", 1)) or 1)
    local sampleStacks = math.min(2, maximum)
    host.bar:SetMinMaxValues(0, fillMode == "stacks" and maximum or 30)
    host.bar:SetValue(fillMode == "stacks" and sampleStacks or 20.4)

    for _, tick in ipairs(host.ticks) do tick:Hide() end
    local positions = fillMode == "duration" and ReadSetting(entry, "durationTickPositions", {}) or nil
    if type(positions) ~= "table" then positions = {} end
    local count = fillMode == "duration" and #positions
        or (ReadSetting(entry, "showTicks", true) ~= false and maximum > 1 and maximum - 1 or 0)
    local tickWidth = math.max(1, DDingUI.Scale and DDingUI:Scale(ReadSetting(entry, "tickWidth", 2)) or 2)
    for index = 1, count do
        local position = fillMode == "duration" and tonumber(positions[index]) or (index / maximum)
        if position and position > 0 and position < 1 then
            local tick = host.ticks[index]
            if not tick then
                tick = host.tickFrame:CreateTexture(nil, "OVERLAY")
                tick:SetColorTexture(0, 0, 0, 1)
                host.ticks[index] = tick
            end
            tick:ClearAllPoints()
            if orientation == "VERTICAL" then
                tick:SetPoint("BOTTOM", host.tickFrame, "BOTTOM", 0, position * height)
                tick:SetSize(width, tickWidth)
            else
                tick:SetPoint("LEFT", host.tickFrame, "LEFT", position * width, 0)
                tick:SetSize(tickWidth, height)
            end
            tick:Show()
        end
    end

    local showStacks = ReadSetting(entry, "showStacksText", true) ~= false
    host.stacks:SetShown(showStacks)
    if showStacks then
        ApplyFont(host.stacks, ReadSetting(entry, "textFont"), ReadSetting(entry, "textSize", 12), ReadSetting(entry, "textOutline", "OUTLINE"))
        host.stacks:SetText(tostring(sampleStacks))
        local tr, tg, tb, ta = ReadColor(ReadSetting(entry, "textColor"), { 1, 1, 1, 1 })
        host.stacks:SetTextColor(tr, tg, tb, ta)
        ApplyTextAnchor(host.stacks, host, ReadSetting(entry, "textAlign", "CENTER"), ReadSetting(entry, "textX", 0), ReadSetting(entry, "textY", 0))
    end

    local showDuration = ReadSetting(entry, "showDurationText", false) == true
    host.duration:SetShown(showDuration)
    if showDuration then
        local decimals = math.floor(Clamp(ReadSetting(entry, "durationDecimals", 1), 0, 2))
        ApplyFont(host.duration, ReadSetting(entry, "durationTextFont"), ReadSetting(entry, "durationTextSize", 10), ReadSetting(entry, "durationTextOutline", "OUTLINE"))
        host.duration:SetText(string.format("%." .. decimals .. "f", 8.3))
        local dr, dg, db, da = ReadColor(ReadSetting(entry, "durationTextColor"), { 1, 1, 1, 1 })
        host.duration:SetTextColor(dr, dg, db, da)
        ApplyTextAnchor(host.duration, host, ReadSetting(entry, "durationTextAlign", "CENTER"), ReadSetting(entry, "durationTextX", 0), ReadSetting(entry, "durationTextY", 0))
    end
    host:SetAlpha(entry.disabled and 0.45 or 1)
    host:Show()
end

local function RenderIcon(preview, entry)
    local host = preview.iconVisual
    local size = Clamp(ReadSetting(entry, "iconSize", 32), 8, 160)
    local aspect = Clamp(ReadSetting(entry, "iconAspectRatio", 1), 0.25, 4)
    local width, height, scale = FitSize(preview.canvas, size * aspect, size, 70, 22)
    host:SetSize(width, height)
    host:ClearAllPoints()
    host:SetPoint("CENTER", preview.canvas, "CENTER", 0, -3)
    host.icon:SetTexture(ResolveIcon(entry))
    local zoom = Clamp(ReadSetting(entry, "iconZoom", 0.08), 0, 0.45)
    host.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    host.icon:SetDesaturated(entry.disabled or ReadSetting(entry, "iconDesaturate", false) == true)
    ApplyEdges(host.edges, host, ReadSetting(entry, "showIconBorder", true) == false and 0 or ReadSetting(entry, "iconBorderSize", 1), ReadSetting(entry, "iconBorderColor"))
    SetCooldownSample(host.cooldown, FLAT, { 0, 0, 0, 0.58 }, false)

    local showStacks = ReadSetting(entry, "iconShowStackText", true) ~= false
    host.stacks:SetShown(showStacks)
    if showStacks then
        ApplyFont(host.stacks, ReadSetting(entry, "iconStackTextFont"), (ReadSetting(entry, "iconStackTextSize", 12) or 12) * scale, ReadSetting(entry, "iconStackTextOutline", "OUTLINE"))
        host.stacks:SetText("2")
        local sr, sg, sb, sa = ReadColor(ReadSetting(entry, "iconStackTextColor"), { 1, 1, 1, 1 })
        host.stacks:SetTextColor(sr, sg, sb, sa)
        ApplyTextAnchor(host.stacks, host, ReadSetting(entry, "iconStackTextAnchor", "BOTTOMRIGHT"), (tonumber(ReadSetting(entry, "iconStackTextOffsetX", -2)) or -2) * scale, (tonumber(ReadSetting(entry, "iconStackTextOffsetY", 2)) or 2) * scale)
    end

    local showDuration = ReadSetting(entry, "showDurationText", false) == true
    host.duration:SetShown(showDuration)
    if showDuration then
        local decimals = math.floor(Clamp(ReadSetting(entry, "durationDecimals", 1), 0, 2))
        ApplyFont(host.duration, ReadSetting(entry, "durationTextFont"), (ReadSetting(entry, "durationTextSize", 10) or 10) * scale, ReadSetting(entry, "durationTextOutline", "OUTLINE"))
        host.duration:SetText(string.format("%." .. decimals .. "f", 8.3))
        local dr, dg, db, da = ReadColor(ReadSetting(entry, "durationTextColor"), { 1, 1, 1, 1 })
        host.duration:SetTextColor(dr, dg, db, da)
        ApplyTextAnchor(host.duration, host, ReadSetting(entry, "durationTextAlign", "CENTER"), (tonumber(ReadSetting(entry, "durationTextX", 0)) or 0) * scale, (tonumber(ReadSetting(entry, "durationTextY", 0)) or 0) * scale)
    end
    host:SetAlpha(entry.disabled and 0.45 or 1)
    host:Show()
    if not entry.disabled then ApplyPreviewEffect(host, host.icon, entry) end
end

local function RenderRing(preview, entry)
    local host = preview.ringVisual
    local size = Clamp(ReadSetting(entry, "ringSize", 32), 8, 160)
    local width, height, scale = FitSize(preview.canvas, size, size, 70, 18)
    host:SetSize(width, height)
    host:ClearAllPoints()
    host:SetPoint("CENTER", preview.canvas, "CENTER", 0, -3)
    local thickness = math.floor(Clamp(ReadSetting(entry, "ringThickness", 20), 10, 40) / 10 + 0.5) * 10
    local ringTexture = string.format("Interface\\AddOns\\DDingUI_CDM\\Media\\Textures\\Ring_%dpx.tga", thickness)
    host.background:SetTexture(ringTexture)
    local br, bg, bb, ba = ReadColor(ReadSetting(entry, "ringBgColor"), { 0.15, 0.15, 0.15, 1 })
    host.background:SetVertexColor(br, bg, bb, ba)
    local borderSize = Clamp(ReadSetting(entry, "ringBorderSize", 2), 0, 8) * scale
    host.border:ClearAllPoints()
    host.border:SetPoint("CENTER", host, "CENTER")
    host.border:SetSize(width + borderSize * 2, height + borderSize * 2)
    host.border:SetTexture(ringTexture)
    local rr, rg, rb, ra = ReadColor(ReadSetting(entry, "ringBorderColor"), { 0, 0, 0, 1 })
    host.border:SetVertexColor(rr, rg, rb, ra)
    host.border:SetShown(borderSize > 0)
    SetCooldownSample(host.cooldown, ringTexture, ReadSetting(entry, "ringColor"), ReadSetting(entry, "ringReverse", false) ~= true)
    if host.cooldown.SetUseCircularEdge then host.cooldown:SetUseCircularEdge(true) end
    local showText = ReadSetting(entry, "ringShowText", true) ~= false
    host.duration:SetShown(showText)
    if showText then
        local decimals = math.floor(Clamp(ReadSetting(entry, "ringDurationDecimals", 1), 0, 2))
        ApplyFont(host.duration, ReadSetting(entry, "ringTextFont", ReadSetting(entry, "durationTextFont")), (ReadSetting(entry, "ringTextSize", ReadSetting(entry, "durationTextSize", 10)) or 10) * scale, ReadSetting(entry, "ringTextOutline", "OUTLINE"))
        host.duration:SetText(string.format("%." .. decimals .. "f", 8.3))
        local tr, tg, tb, ta = ReadColor(ReadSetting(entry, "ringTextColor", ReadSetting(entry, "durationTextColor")), { 1, 1, 1, 1 })
        host.duration:SetTextColor(tr, tg, tb, ta)
        host.duration:ClearAllPoints()
        host.duration:SetPoint("CENTER", host, "CENTER", (tonumber(ReadSetting(entry, "ringTextX", 0)) or 0) * scale, (tonumber(ReadSetting(entry, "ringTextY", 0)) or 0) * scale)
    end
    host:SetAlpha(entry.disabled and 0.45 or 1)
    host:Show()
end

local function RenderText(preview, entry)
    local host = preview.textVisual
    local textSize = Clamp(ReadSetting(entry, "textModeSize", 24), 6, 72)
    local showIcon = ReadSetting(entry, "textShowIcon", true) ~= false
    local iconSize = Clamp(ReadSetting(entry, "textIconSize", 24), 8, 96)
    local displayMode = ReadSetting(entry, "textDisplayMode", "stacks")
    local value = "2"
    if displayMode == "duration" then
        local decimals = math.floor(Clamp(ReadSetting(entry, "durationDecimals", 1), 0, 2))
        value = string.format("%." .. decimals .. "f", 8.3)
    elseif displayMode == "name" then
        value = entry.name or (L["Unnamed Tracker"] or "Unnamed Tracker")
    elseif displayMode == "custom" then
        value = ReadSetting(entry, "customText", "")
        if value == "" then value = entry.name or "" end
    end
    ApplyFont(host.value, ReadSetting(entry, "textModeFont"), textSize, ReadSetting(entry, "textModeOutline", "OUTLINE"))
    host.value:SetText(value)
    local tr, tg, tb, ta = ReadColor(ReadSetting(entry, "textModeColor"), { 1, 1, 1, 1 })
    host.value:SetTextColor(tr, tg, tb, ta)
    local textWidth = math.min(300, math.max(30, host.value:GetStringWidth() + 4))
    local totalWidth = textWidth + (showIcon and iconSize + 6 or 0)
    local width, height, scale = FitSize(preview.canvas, totalWidth, math.max(iconSize, textSize + 6), 42, 24)
    host:SetSize(width, height)
    host:ClearAllPoints()
    host:SetPoint("CENTER", preview.canvas, "CENTER", 0, -3)
    host.icon:SetShown(showIcon)
    host.value:ClearAllPoints()
    if showIcon then
        local scaledIcon = iconSize * scale
        host.icon:SetSize(scaledIcon, scaledIcon)
        host.icon:SetPoint("LEFT", host, "LEFT", 0, 0)
        host.icon:SetTexture(ResolveIcon(entry))
        host.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        host.value:SetPoint("LEFT", host.icon, "RIGHT", 6, 0)
    else
        host.value:SetPoint("CENTER", host, "CENTER", 0, 0)
    end
    host.duration:Hide()
    host:SetAlpha(entry.disabled and 0.45 or 1)
    host:Show()
end

local function RenderPassive(preview, entry, displayType)
    local host = preview.passiveVisual
    host:ClearAllPoints()
    host:SetPoint("CENTER", preview.canvas, "CENTER", 0, -3)
    host.icon:SetTexture(ResolveIcon(entry))
    host.icon:SetDesaturated(entry.disabled == true)
    host.title:SetText(entry.name or (L["Unnamed Tracker"] or "Unnamed Tracker"))
    host.detail:SetText(displayType == "sound" and (ReadSetting(entry, "soundFile", "None") or "None") or (L["Trigger"] or "Trigger"))
    host:SetAlpha(entry.disabled and 0.45 or 1)
    host:Show()
end

local function RenderGroup(preview, entry, trackedBuffs)
    local host = preview.groupVisual
    local children = entry.controlledChildren or {}
    local settings = entry.groupSettings or {}
    local direction = settings.growthDirection or "RIGHT"
    local horizontal = direction == "LEFT" or direction == "RIGHT"
    local count = math.min(#children, #host.slots)
    local spacing = Clamp(settings.growthSpacing or 2, 0, 16)
    local slotSize = 30
    local width = horizontal and (count * slotSize + math.max(0, count - 1) * spacing) or slotSize
    local height = horizontal and slotSize or (count * slotSize + math.max(0, count - 1) * spacing)
    host:SetSize(math.max(1, width), math.max(1, height))
    host:ClearAllPoints()
    host:SetPoint("CENTER", preview.canvas, "CENTER", 0, -3)
    for index, slot in ipairs(host.slots) do
        slot:Hide()
        slot:ClearAllPoints()
        if index <= count then
            local child = trackedBuffs and trackedBuffs[children[index]]
            slot.icon:SetTexture(ResolveIcon(child))
            if index == 1 then
                if direction == "LEFT" then
                    slot:SetPoint("TOPRIGHT", host, "TOPRIGHT")
                elseif direction == "UP" then
                    slot:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
                else
                    slot:SetPoint("TOPLEFT", host, "TOPLEFT")
                end
            elseif horizontal then
                if direction == "LEFT" then
                    slot:SetPoint("RIGHT", host.slots[index - 1], "LEFT", -spacing, 0)
                else
                    slot:SetPoint("LEFT", host.slots[index - 1], "RIGHT", spacing, 0)
                end
            else
                if direction == "UP" then
                    slot:SetPoint("BOTTOM", host.slots[index - 1], "TOP", 0, spacing)
                else
                    slot:SetPoint("TOP", host.slots[index - 1], "BOTTOM", 0, -spacing)
                end
            end
            slot:Show()
        end
    end
    host:SetAlpha(entry.disabled and 0.45 or 1)
    host:SetShown(count > 0)
    if count == 0 then preview.emptyText:Show() end
end

local function AppendFingerprint(parts, value, depth, seen)
    local valueType = type(value)
    if valueType ~= "table" then
        parts[#parts + 1] = valueType .. "=" .. tostring(value)
        return
    end
    if depth <= 0 or seen[value] then
        parts[#parts + 1] = "table"
        return
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key)
        AppendFingerprint(parts, value[key], depth - 1, seen)
    end
    seen[value] = nil
end

function Preview:GetSignature(entry, trackedBuffs)
    local parts = {}
    AppendFingerprint(parts, entry, 4, {})
    if entry and entry.isGroup and trackedBuffs then
        for _, childIndex in ipairs(entry.controlledChildren or {}) do
            AppendFingerprint(parts, trackedBuffs[childIndex], 2, {})
        end
    end
    return table.concat(parts, "|")
end

function Preview:Create(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetHeight(126)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.96)
    frame:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.72)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText(L["Live Preview"] or "Live Preview")
    title:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", title, "RIGHT", 8, 0)
    name:SetPoint("RIGHT", frame, "RIGHT", -92, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetTextColor(THEME.textBright[1], THEME.textBright[2], THEME.textBright[3], 1)
    local mode = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mode:SetPoint("TOPRIGHT", -12, -9)
    mode:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)

    local canvas = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", 10, -28)
    canvas:SetPoint("BOTTOMRIGHT", -10, 8)
    canvas:SetBackdrop({ bgFile = FLAT })
    canvas:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], 0.9)
    frame.canvas = canvas
    frame.title = title
    frame.name = name
    frame.mode = mode
    frame.barVisual = CreateBarVisual(canvas)
    frame.iconVisual = CreateIconVisual(canvas)
    frame.ringVisual = CreateRingVisual(canvas)
    frame.textVisual = CreateTextVisual(canvas)
    frame.passiveVisual = CreatePassiveVisual(canvas)
    frame.groupVisual = CreateGroupVisual(canvas)
    frame.visuals = {
        frame.barVisual,
        frame.iconVisual,
        frame.ringVisual,
        frame.textVisual,
        frame.passiveVisual,
        frame.groupVisual,
    }

    local emptyText = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER")
    emptyText:SetText(L["Select a tracker to preview"] or "Select a tracker to preview")
    emptyText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.9)
    frame.emptyText = emptyText

    function frame:ResetVisuals()
        StopPreviewEffects(self.iconVisual)
        for _, visual in ipairs(self.visuals) do visual:Hide() end
        self.emptyText:Hide()
    end

    function frame:Refresh(entry, trackedBuffs)
        self:ResetVisuals()
        self._entry = entry
        self._trackedBuffs = trackedBuffs
        if not entry then
            self.name:SetText("")
            self.mode:SetText("")
            self.emptyText:Show()
            return
        end

        local displayType = entry.isGroup and "group" or (entry.displayType or "bar")
        self.name:SetText(entry.name or (L["Unnamed Tracker"] or "Unnamed Tracker"))
        self.mode:SetText(displayType:upper())
        if displayType == "bar" then
            RenderBar(self, entry)
        elseif displayType == "icon" then
            RenderIcon(self, entry)
        elseif displayType == "ring" then
            RenderRing(self, entry)
        elseif displayType == "text" then
            RenderText(self, entry)
        elseif displayType == "group" then
            RenderGroup(self, entry, trackedBuffs)
        else
            RenderPassive(self, entry, displayType)
        end
    end

    frame:SetScript("OnHide", function(self)
        StopPreviewEffects(self.iconVisual)
    end)
    frame:Refresh(nil)
    return frame
end

GUI.CreateTrackerLivePreview = function(parent)
    return Preview:Create(parent)
end
