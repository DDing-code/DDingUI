local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Visuals = {}
DDingUI.RestrictedAuraVisuals = Visuals

-- AuraContainer buttons are pooled and reparented, so this module only uses
-- static regions and native AnimationGroups inside their frame hierarchy.
local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local ANTS_ATLAS = "RotationHelper_Ants_Flipbook_2x"
local AUTOCAST_TEXTURE = "Interface\\Artifacts\\Artifacts"
local AUTOCAST_TEX_COORDS = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }
local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local TEXT_MOTION_ALIASES = {
    hover = "float",
    pulse = "breathe",
    flash = "focus",
}
local TEXT_MOTION_PRESETS = {
    fade = true,
    pop = true,
    spring = true,
    breathe = true,
    float = true,
    focus = true,
    spin = true,
}
local TEXT_FADE_DIRECTIONS = {
    NONE = { 0, 0 },
    LEFT = { -14, 0 },
    RIGHT = { 14, 0 },
    UP = { 0, 14 },
    DOWN = { 0, -14 },
}
local TEXT_FADE_OUT_DURATION = 0.22
local textMotionByFrame = setmetatable({}, { __mode = "k" })

local function AddAlpha(group, order, fromAlpha, toAlpha, duration, smoothing)
    local animation = group:CreateAnimation("Alpha")
    animation:SetOrder(order)
    animation:SetFromAlpha(fromAlpha)
    animation:SetToAlpha(toAlpha)
    animation:SetDuration(duration)
    if smoothing then animation:SetSmoothing(smoothing) end
    return animation
end

local function AddScale(group, order, fromScale, toScale, duration, smoothing)
    local animation = group:CreateAnimation("Scale")
    animation:SetOrder(order)
    local setFrom = animation.SetScaleFrom or animation.SetFromScale
    local setTo = animation.SetScaleTo or animation.SetToScale
    if setFrom and setTo then
        setFrom(animation, fromScale, fromScale)
        setTo(animation, toScale, toScale)
    else
        animation:SetScale(toScale / math.max(0.01, fromScale), toScale / math.max(0.01, fromScale))
    end
    animation:SetDuration(duration)
    if smoothing then animation:SetSmoothing(smoothing) end
    return animation
end

local function AddTranslation(group, order, x, y, duration, smoothing)
    local animation = group:CreateAnimation("Translation")
    animation:SetOrder(order)
    animation:SetOffset(x, y)
    animation:SetDuration(duration)
    if smoothing then animation:SetSmoothing(smoothing) end
    return animation
end

local function NormalizeFadeDirection(direction)
    direction = type(direction) == "string" and direction:upper() or "NONE"
    return TEXT_FADE_DIRECTIONS[direction] and direction or "NONE"
end

local function BuildTextMotion(frame, preset, direction)
    local start
    local main

    if preset == "fade" then
        start = frame:CreateAnimationGroup()
        local offset = TEXT_FADE_DIRECTIONS[direction]
        if direction ~= "NONE" then
            AddAlpha(start, 1, 0, 0, 0.001)
            AddTranslation(start, 1, offset[1], offset[2], 0.001)
            AddAlpha(start, 2, 0, 1, 0.28, "OUT")
            AddTranslation(start, 2, -offset[1], -offset[2], 0.28, "OUT")
            AddScale(start, 2, 0.98, 1, 0.28, "OUT")
        else
            AddAlpha(start, 1, 0, 1, 0.28, "OUT")
            AddScale(start, 1, 0.96, 1, 0.28, "OUT")
        end
    elseif preset == "pop" then
        start = frame:CreateAnimationGroup()
        AddAlpha(start, 1, 0, 1, 0.16, "OUT")
        AddScale(start, 1, 0.72, 1.1, 0.22, "OUT")
        AddScale(start, 2, 1.1, 0.98, 0.1, "IN_OUT")
        AddScale(start, 3, 0.98, 1, 0.08, "OUT")
    elseif preset == "spring" then
        start = frame:CreateAnimationGroup()
        AddAlpha(start, 1, 0, 1, 0.14, "OUT")
        AddScale(start, 1, 0.86, 1.06, 0.16, "OUT")
        local up = start:CreateAnimation("Translation")
        up:SetOrder(1)
        up:SetOffset(0, 5)
        up:SetDuration(0.16)
        up:SetSmoothing("OUT")
        AddScale(start, 2, 1.06, 1, 0.22, "IN_OUT")
        local settle = start:CreateAnimation("Translation")
        settle:SetOrder(2)
        settle:SetOffset(0, -5)
        settle:SetDuration(0.22)
        settle:SetSmoothing("IN_OUT")
    elseif preset == "breathe" then
        main = frame:CreateAnimationGroup()
        AddScale(main, 1, 1, 1.035, 0.9, "IN_OUT")
        AddAlpha(main, 1, 1, 0.82, 0.9, "IN_OUT")
        AddScale(main, 2, 1.035, 1, 0.9, "IN_OUT")
        AddAlpha(main, 2, 0.82, 1, 0.9, "IN_OUT")
        main:SetLooping("REPEAT")
    elseif preset == "float" then
        main = frame:CreateAnimationGroup()
        local up = main:CreateAnimation("Translation")
        up:SetOrder(1)
        up:SetOffset(0, 2)
        up:SetDuration(0.8)
        up:SetSmoothing("IN_OUT")
        AddAlpha(main, 1, 1, 0.9, 0.8, "IN_OUT")
        local down = main:CreateAnimation("Translation")
        down:SetOrder(2)
        down:SetOffset(0, -2)
        down:SetDuration(0.8)
        down:SetSmoothing("IN_OUT")
        AddAlpha(main, 2, 0.9, 1, 0.8, "IN_OUT")
        main:SetLooping("REPEAT")
    elseif preset == "focus" then
        main = frame:CreateAnimationGroup()
        AddAlpha(main, 1, 1, 0.58, 0.34, "IN_OUT")
        AddAlpha(main, 2, 0.58, 1, 0.52, "IN_OUT")
        main:SetLooping("REPEAT")
    elseif preset == "spin" then
        main = frame:CreateAnimationGroup()
        local spin = main:CreateAnimation("Rotation")
        spin:SetOrder(1)
        spin:SetDegrees(360)
        spin:SetDuration(2.8)
        main:SetLooping("REPEAT")
    end

    return { start = start, main = main }
end

local function BuildTextExit(frame, direction)
    local finish = frame:CreateAnimationGroup()
    local offset = TEXT_FADE_DIRECTIONS[direction]
    AddAlpha(finish, 1, 1, 0, TEXT_FADE_OUT_DURATION, "IN")
    AddScale(finish, 1, 1, 0.98, TEXT_FADE_OUT_DURATION, "IN")
    if direction ~= "NONE" then
        AddTranslation(finish, 1, offset[1], offset[2], TEXT_FADE_OUT_DURATION, "IN")
    end
    finish:SetToFinalAlpha(true)
    return { finish = finish }
end

local function BuildTextPreview(frame, enterDirection, exitDirection)
    local group = frame:CreateAnimationGroup()
    local enterOffset = TEXT_FADE_DIRECTIONS[enterDirection]
    local exitOffset = TEXT_FADE_DIRECTIONS[exitDirection]

    AddAlpha(group, 1, 0, 0, 0.001)
    AddTranslation(group, 1, enterOffset[1], enterOffset[2], 0.001)
    AddAlpha(group, 2, 0, 1, 0.28, "OUT")
    AddTranslation(group, 2, -enterOffset[1], -enterOffset[2], 0.28, "OUT")
    AddAlpha(group, 3, 1, 1, 0.8)
    AddAlpha(group, 4, 1, 0, TEXT_FADE_OUT_DURATION, "IN")
    AddTranslation(group, 4, exitOffset[1], exitOffset[2], TEXT_FADE_OUT_DURATION, "IN")
    AddAlpha(group, 5, 0, 0, 0.001)
    AddTranslation(group, 5, -exitOffset[1], -exitOffset[2], 0.001)
    AddAlpha(group, 6, 0, 0, 0.3)
    group:SetLooping("REPEAT")
    return { preview = group }
end

function Visuals:StopTextMotion(frame)
    local state = frame and textMotionByFrame[frame]
    local record = state and state.active
    if not record then return end
    if record.start and record.start:IsPlaying() then record.start:Stop() end
    if record.main and record.main:IsPlaying() then record.main:Stop() end
    if record.finish and record.finish:IsPlaying() then record.finish:Stop() end
    if record.preview and record.preview:IsPlaying() then record.preview:Stop() end
    state.active = nil
end

function Visuals:ApplyTextMotion(frame, motionType, direction)
    self:StopTextMotion(frame)
    if not frame or type(motionType) ~= "string" then return false end

    local preset = TEXT_MOTION_ALIASES[motionType:lower()] or motionType:lower()
    if not TEXT_MOTION_PRESETS[preset] then return false end
    direction = preset == "fade" and NormalizeFadeDirection(direction) or "NONE"

    local state = textMotionByFrame[frame]
    if not state then
        state = { presets = {}, exits = {}, previews = {} }
        textMotionByFrame[frame] = state
    end
    local key = preset .. ":" .. direction
    local record = state.presets[key]
    if not record then
        record = BuildTextMotion(frame, preset, direction)
        state.presets[key] = record
    end
    state.active = record
    if record.start then record.start:Play() end
    if record.main then record.main:Play() end
    return true
end

function Visuals:ApplyTextExit(frame, motionType, direction)
    self:StopTextMotion(frame)
    if not frame or type(motionType) ~= "string" or motionType:lower() ~= "fade" then return nil end

    direction = NormalizeFadeDirection(direction)
    local state = textMotionByFrame[frame]
    if not state then
        state = { presets = {}, exits = {}, previews = {} }
        textMotionByFrame[frame] = state
    end
    local record = state.exits[direction]
    if not record then
        record = BuildTextExit(frame, direction)
        state.exits[direction] = record
    end
    state.active = record
    record.finish:Play()
    return TEXT_FADE_OUT_DURATION
end

function Visuals:ApplyTextPreviewMotion(frame, motionType, enterDirection, exitDirection)
    if type(motionType) ~= "string" or motionType:lower() ~= "fade" then
        return self:ApplyTextMotion(frame, motionType, enterDirection)
    end

    self:StopTextMotion(frame)
    enterDirection = NormalizeFadeDirection(enterDirection)
    exitDirection = NormalizeFadeDirection(exitDirection)
    local state = textMotionByFrame[frame]
    if not state then
        state = { presets = {}, exits = {}, previews = {} }
        textMotionByFrame[frame] = state
    end
    local key = enterDirection .. ":" .. exitDirection
    local record = state.previews[key]
    if not record then
        record = BuildTextPreview(frame, enterDirection, exitDirection)
        state.previews[key] = record
    end
    state.active = record
    record.preview:Play()
    return true
end

local function ResolveGlowType(style)
    local value = style and (style.iconAnimation or style.glowType)
    if type(value) ~= "string" then return nil end

    value = value:lower()
    if value == "none" or TEXT_MOTION_ALIASES[value] or TEXT_MOTION_PRESETS[value]
    then
        return nil
    elseif value:find("proc", 1, true) or value:find("blizzard", 1, true) then
        return "proc"
    elseif value:find("auto", 1, true) then
        return "autocast"
    elseif value:find("pixel", 1, true) or value:find("shine", 1, true) then
        return "pixel"
    end
    return "button"
end

local function ResolveColor(style, glowType)
    local color = style and style.glowColor
    if style and style.glowBlizzard then
        if glowType == "pixel" or glowType == "autocast" then
            return 1, 210 / 255, 0, 1, true
        end
        return 1, 1, 1, 1, false
    end
    if type(color) == "table" then
        return color[1] or color.r or 1,
            color[2] or color.g or 1,
            color[3] or color.b or 1,
            color[4] or color.a or 1,
            true
    end
    if glowType == "pixel" or glowType == "autocast" then
        return 1, 210 / 255, 0, 1, true
    end
    return 1, 1, 1, 1, false
end

local function ResolveDuration(style, glowType)
    local value
    if glowType == "autocast" then
        value = style.glowAutocastFrequency or style.glowFrequency
    elseif glowType == "button" then
        value = style.glowButtonFrequency or style.glowFrequency
    else
        value = style.glowFrequency
    end
    return Clamp(value or 0.8, 0.05, 10)
end

local function CreateHost(button, style, scale)
    local host = CreateFrame("Frame", nil, button)
    local xOffset = tonumber(style.glowXOffset) or 0
    local yOffset = tonumber(style.glowYOffset) or 0
    local width = math.max(1, tonumber(button:GetWidth()) or 1)
    local height = math.max(1, tonumber(button:GetHeight()) or 1)
    host:SetSize(width * scale + (xOffset * 2), height * scale + (yOffset * 2))
    host:SetPoint("CENTER", button, "CENTER")
    host:SetFrameLevel(button:GetFrameLevel() + 6)
    host:EnableMouse(false)
    return host, width, height
end

local function CreateFlipBook(host, atlas, r, g, b, a, tint, duration)
    local texture = host:CreateTexture(nil, "OVERLAY", nil, 7)
    texture:SetAllPoints(host)
    texture:SetAtlas(atlas, false)
    texture:SetBlendMode("ADD")
    texture:SetDesaturated(tint)
    texture:SetVertexColor(r, g, b, a)

    local animation = texture:CreateAnimationGroup()
    animation:SetLooping("REPEAT")
    local flipBook = animation:CreateAnimation("FlipBook")
    flipBook:SetFlipBookRows(6)
    flipBook:SetFlipBookColumns(5)
    flipBook:SetFlipBookFrames(30)
    flipBook:SetDuration(duration)
    animation:Play()
end

local function CreatePulse(host, alpha, duration)
    local animation = host:CreateAnimationGroup()
    animation:SetLooping("REPEAT")
    local fadeIn = animation:CreateAnimation("Alpha")
    fadeIn:SetOrder(1)
    fadeIn:SetFromAlpha(math.max(0.05, alpha * 0.3))
    fadeIn:SetToAlpha(alpha)
    fadeIn:SetDuration(duration * 0.5)
    local fadeOut = animation:CreateAnimation("Alpha")
    fadeOut:SetOrder(2)
    fadeOut:SetFromAlpha(alpha)
    fadeOut:SetToAlpha(math.max(0.05, alpha * 0.3))
    fadeOut:SetDuration(duration * 0.5)
    animation:Play()
end

local function CreatePixelGlow(button, style, r, g, b, a, duration)
    local host = CreateHost(button, style, 1)
    local thickness = math.max(1, tonumber(style.glowThickness) or 2)
    local edges = {}
    for index = 1, 4 do
        local edge = host:CreateTexture(nil, "OVERLAY", nil, 7)
        edge:SetTexture(SOLID_TEXTURE)
        edge:SetBlendMode("ADD")
        edge:SetVertexColor(r, g, b, a)
        edges[index] = edge
    end
    edges[1]:SetPoint("TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT")
    edges[1]:SetHeight(thickness)
    edges[2]:SetPoint("BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT")
    edges[2]:SetHeight(thickness)
    edges[3]:SetPoint("TOPLEFT")
    edges[3]:SetPoint("BOTTOMLEFT")
    edges[3]:SetWidth(thickness)
    edges[4]:SetPoint("TOPRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT")
    edges[4]:SetWidth(thickness)
    CreatePulse(host, a, duration)
    return host
end

local function CreateAutocastGlow(button, style, r, g, b, a, duration)
    local host, width, height = CreateHost(button, style, 1)
    local scale = Clamp(style.glowScale or 1, 0.5, 5)
    local size = math.max(4, math.min(width, height) * 0.18 * scale)
    local points = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
    for _, point in ipairs(points) do
        local sparkle = host:CreateTexture(nil, "OVERLAY", nil, 7)
        sparkle:SetTexture(AUTOCAST_TEXTURE)
        sparkle:SetTexCoord(unpack(AUTOCAST_TEX_COORDS))
        sparkle:SetBlendMode("ADD")
        sparkle:SetDesaturated(true)
        sparkle:SetVertexColor(r, g, b, a)
        sparkle:SetSize(size, size)
        sparkle:SetPoint(point, host, point)
    end
    CreatePulse(host, a, duration)
    return host
end

function Visuals:ApplyGlow(button, style)
    if not button or type(style) ~= "table" or style.glowEnabled == false
        or style.glowWhenInactive == true
    then
        return nil
    end

    local glowType = ResolveGlowType(style)
    if not glowType then return nil end
    local r, g, b, a, tint = ResolveColor(style, glowType)
    local duration = ResolveDuration(style, glowType)

    if glowType == "pixel" then
        return CreatePixelGlow(button, style, r, g, b, a, duration)
    elseif glowType == "autocast" then
        return CreateAutocastGlow(button, style, r, g, b, a, duration)
    end

    local host = CreateHost(button, style, glowType == "proc" and 1.4 or 1.5)
    CreateFlipBook(host, glowType == "proc" and PROC_ATLAS or ANTS_ATLAS, r, g, b, a, tint, duration)
    return host
end
