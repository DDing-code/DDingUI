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

local function ResolveGlowType(style)
    local value = style and (style.iconAnimation or style.glowType)
    if type(value) ~= "string" then return nil end

    value = value:lower()
    if value == "none" or value == "hover" or value == "pulse"
        or value == "flash" or value == "spin"
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
