------------------------------------------------------
-- DDingUI_StyleLib :: Gradient
-- Gradient texture utilities
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

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
