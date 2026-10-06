------------------------------------------------------
-- DDingUI_StyleLib :: Gradient
-- Gradient texture utilities
------------------------------------------------------
local ADDON_NAME = ...
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end
if Lib.__ddingStyleLibLoadOwner ~= ADDON_NAME and Lib.CreateHorizontalGradient then return end

--- Create a horizontal gradient texture attached to parent.
--- @param parent Frame
--- @param fromColor table {r,g,b,a}
--- @param toColor table {r,g,b,a}
--- @param height number|nil  defaults to 2
--- @param layer string|nil   draw layer, defaults to "ARTWORK"
--- @return Texture
function Lib.CreateHorizontalGradient(parent, fromColor, toColor, height, layer)
    height = height or 2
    layer  = layer or "ARTWORK"

    local tex = parent:CreateTexture(nil, layer)
    tex:SetHeight(height)
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient(
        "HORIZONTAL",
        CreateColor(fromColor[1], fromColor[2], fromColor[3], fromColor[4] or 1),
        CreateColor(toColor[1],   toColor[2],   toColor[3],   toColor[4] or 1)
    )
    return tex
end

--- Create a vertical gradient texture.
--- @param parent Frame
--- @param topColor table {r,g,b,a}
--- @param bottomColor table {r,g,b,a}
--- @param width number|nil  defaults to 2
--- @param layer string|nil  draw layer
--- @return Texture
function Lib.CreateVerticalGradient(parent, topColor, bottomColor, width, layer)
    width = width or 2
    layer = layer or "ARTWORK"

    local tex = parent:CreateTexture(nil, layer)
    tex:SetWidth(width)
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient(
        "VERTICAL",
        CreateColor(bottomColor[1], bottomColor[2], bottomColor[3], bottomColor[4] or 1),
        CreateColor(topColor[1],    topColor[2],    topColor[3],    topColor[4] or 1)
    )
    return tex
end

--- Apply accent gradient from-colour to a FontString (solid, since WoW has no per-glyph gradient).
--- @param fontString FontString
--- @param addonName string
function Lib.ApplyAccentToText(fontString, addonName)
    local from = Lib.GetAccent(addonName)
    fontString:SetTextColor(from[1], from[2], from[3], from[4] or 1)
end

local function ReadColor(color, fallback)
    color = type(color) == "table" and color or fallback or { 1, 1, 1, 1 }
    return color[1] or color.r or 1,
        color[2] or color.g or 1,
        color[3] or color.b or 1,
        color[4] or color.a or 1
end

local function GradientDirection(color)
    return color and color.gradientOrientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL"
end

local WHITE_GRADIENT_COLOR = CreateColor(1, 1, 1, 1)
local gradientColorCache = setmetatable({}, { __mode = "k" })

local function GradientColorObjects(color, r, g, b, a, er, eg, eb, ea)
    local cached = gradientColorCache[color]
    if not cached
        or cached.r ~= r or cached.g ~= g or cached.b ~= b or cached.a ~= a
        or cached.er ~= er or cached.eg ~= eg or cached.eb ~= eb or cached.ea ~= ea then
        cached = {
            r = r, g = g, b = b, a = a,
            er = er, eg = eg, eb = eb, ea = ea,
            first = CreateColor(r, g, b, a),
            second = CreateColor(er, eg, eb, ea),
        }
        gradientColorCache[color] = cached
    end
    return cached.first, cached.second
end

function Lib.IsGradientBarColor(color)
    return type(color) == "table"
        and color.gradientMode == "GRADIENT"
        and type(color.gradientColor) == "table"
end

function Lib.CopyBarColorMetadata(target, source)
    if type(target) ~= "table" then return target end
    if type(source) ~= "table" then
        target.gradientMode = nil
        target.gradientColor = nil
        target.gradientOrientation = nil
        return target
    end

    target.gradientMode = source.gradientMode
    target.gradientOrientation = source.gradientOrientation
    if type(source.gradientColor) == "table" then
        target.gradientColor = {
            source.gradientColor[1] or source.gradientColor.r or 1,
            source.gradientColor[2] or source.gradientColor.g or 1,
            source.gradientColor[3] or source.gradientColor.b or 1,
            source.gradientColor[4] or source.gradientColor.a or 1,
        }
    else
        target.gradientColor = nil
    end
    return target
end

function Lib.ApplyBarColor(statusBar, color, fallback)
    if not statusBar then return end

    local r, g, b, a = ReadColor(color, fallback)
    local texture = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    if not texture or not texture.SetGradient then
        statusBar:SetStatusBarColor(r, g, b, a)
        return
    end

    if Lib.IsGradientBarColor(color) then
        local er, eg, eb, ea = ReadColor(color.gradientColor, color)
        local first, second = GradientColorObjects(color, r, g, b, a, er, eg, eb, ea)
        statusBar:SetStatusBarColor(1, 1, 1, 1)
        texture:SetGradient(
            GradientDirection(color),
            first,
            second
        )
        statusBar._ddingBarGradientActive = true
    else
        if statusBar._ddingBarGradientActive then
            texture:SetGradient("HORIZONTAL", WHITE_GRADIENT_COLOR, WHITE_GRADIENT_COLOR)
            statusBar._ddingBarGradientActive = nil
        end
        statusBar:SetStatusBarColor(r, g, b, a)
    end
end

function Lib.ApplyBarColorToTexture(texture, color, fallback)
    if not texture then return end
    local r, g, b, a = ReadColor(color, fallback)
    local er, eg, eb, ea = r, g, b, a
    local direction = "HORIZONTAL"
    if Lib.IsGradientBarColor(color) then
        er, eg, eb, ea = ReadColor(color.gradientColor, color)
        direction = GradientDirection(color)
    end

    if texture.SetGradient then
        if texture.SetVertexColor then texture:SetVertexColor(1, 1, 1, 1) end
        texture:SetGradient(
            direction,
            CreateColor(r, g, b, a),
            CreateColor(er, eg, eb, ea)
        )
    else
        texture:SetVertexColor(r, g, b, a)
    end
end
