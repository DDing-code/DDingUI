------------------------------------------------------
-- DDingUI_StyleLib :: PixelUtil
-- Pixel-perfect rendering system (inspired by AbstractFramework)
-- 모든 Size/Point/Backdrop을 물리 해상도 기반으로 보정
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local GetPhysicalScreenSize = GetPhysicalScreenSize
local math_floor = math.floor

---------------------------------------------------------------------
-- pixel factor
---------------------------------------------------------------------
function Lib.GetPixelFactor()
    local _, physicalHeight = GetPhysicalScreenSize()
    return 768.0 / physicalHeight
end

function Lib.GetBestScale()
    local factor = Lib.GetPixelFactor()
    local mult
    if factor >= 0.71 then      -- 1080p
        mult = 1
    elseif factor >= 0.53 then  -- 1440p
        mult = 1.15
    else                        -- 2160p (4K)
        mult = 1.7
    end
    local result = factor * mult
    -- Clamp 0.5 ~ 1.5, round to 2 decimals
    result = math_floor(result * 100 + 0.5) / 100
    if result < 0.5 then result = 0.5 end
    if result > 1.5 then result = 1.5 end
    return result
end

local function Round(n)
    if n >= 0 then
        return math_floor(n + 0.5)
    else
        return math_floor(n - 0.5) -- negative round
    end
end

function Lib.GetNearestPixelSize(uiUnitSize, layoutScale, minPixels)
    if uiUnitSize == 0 and (not minPixels or minPixels == 0) then
        return 0
    end
    local uiUnitFactor = Lib.GetPixelFactor()
    local numPixels = Round((uiUnitSize * layoutScale) / uiUnitFactor)
    if minPixels then
        if uiUnitSize < 0 then
            if numPixels > -minPixels then numPixels = -minPixels end
        else
            if numPixels < minPixels then numPixels = minPixels end
        end
    end
    return numPixels * uiUnitFactor / layoutScale
end

function Lib.ConvertPixels(desiredPixels, region)
    if region then
        return Lib.GetNearestPixelSize(desiredPixels, region:GetEffectiveScale())
    end
    return Lib.GetNearestPixelSize(desiredPixels, UIParent:GetEffectiveScale())
end

---------------------------------------------------------------------
-- Pixel-Perfect Size
---------------------------------------------------------------------
function Lib.SetPxWidth(region, width, minPixels)
    region._slWidth = width
    region._slMinWidth = minPixels
    region:SetWidth(Lib.GetNearestPixelSize(width, region:GetEffectiveScale(), minPixels))
end

function Lib.SetPxHeight(region, height, minPixels)
    region._slHeight = height
    region._slMinHeight = minPixels
    region:SetHeight(Lib.GetNearestPixelSize(height, region:GetEffectiveScale(), minPixels))
end

function Lib.SetPxSize(region, width, height)
    if width then Lib.SetPxWidth(region, width) end
    if height then Lib.SetPxHeight(region, height) end
end

---------------------------------------------------------------------
-- Pixel-Perfect Point
---------------------------------------------------------------------
function Lib.SetPxPoint(region, ...)
    if not region._slPoints then region._slPoints = {} end

    local point, relativeTo, relativePoint, offsetX, offsetY
    local n = select("#", ...)

    if n == 1 then
        point = ...
    elseif n == 2 then
        if type(select(2, ...)) == "number" then
            point, offsetX = ...
        else
            point, relativeTo = ...
        end
    elseif n == 3 then
        if type(select(2, ...)) == "number" then
            point, offsetX, offsetY = ...
        else
            point, relativeTo, relativePoint = ...
        end
    elseif n == 4 then
        point, relativeTo, offsetX, offsetY = ...
    else
        point, relativeTo, relativePoint, offsetX, offsetY = ...
    end

    offsetX = offsetX or 0
    offsetY = offsetY or 0
    relativeTo = relativeTo or region:GetParent()
    relativePoint = relativePoint or point

    region._slPoints[point] = { point, relativeTo, relativePoint, offsetX, offsetY }

    local es = region:GetEffectiveScale()
    region:SetPoint(point, relativeTo, relativePoint,
        Lib.GetNearestPixelSize(offsetX, es),
        Lib.GetNearestPixelSize(offsetY, es))
end

function Lib.ClearPxPoints(region)
    region:ClearAllPoints()
    if region._slPoints then wipe(region._slPoints) end
end

function Lib.SetPxInside(region, relativeTo, offset)
    relativeTo = relativeTo or region:GetParent()
    offset = offset or 0
    Lib.ClearPxPoints(region)
    Lib.SetPxPoint(region, "TOPLEFT", relativeTo, "TOPLEFT", offset, -offset)
    Lib.SetPxPoint(region, "BOTTOMRIGHT", relativeTo, "BOTTOMRIGHT", -offset, offset)
end

function Lib.SetOnePixelInside(region, relativeTo)
    Lib.SetPxInside(region, relativeTo, 1)
end

---------------------------------------------------------------------
-- Pixel-Perfect Backdrop
---------------------------------------------------------------------
function Lib.SetPxBackdrop(region, backdropInfo)
    if not region.SetBackdrop then
        Mixin(region, BackdropTemplateMixin)
    end

    local info = {}
    for k, v in pairs(backdropInfo) do
        info[k] = v
    end

    local es = region:GetEffectiveScale()

    if info.edgeSize then
        region._slEdgeSize = info.edgeSize
        info.edgeSize = Lib.GetNearestPixelSize(info.edgeSize, es)
    end

    if info.insets then
        region._slInsets = {}
        local newInsets = {}
        for k, v in pairs(info.insets) do
            region._slInsets[k] = v
            newInsets[k] = Lib.GetNearestPixelSize(v, es)
        end
        info.insets = newInsets
    end

    region:SetBackdrop(info)
end

--- 기본 DDingUI 스타일 backdrop 적용 (1px 테두리)
function Lib.ApplyPixelBackdrop(frame, borderSize)
    borderSize = borderSize or 1
    local flat = Lib.Textures.flat
    Lib.SetPxBackdrop(frame, {
        bgFile = flat,
        edgeFile = flat,
        edgeSize = borderSize,
        insets = { left = borderSize, right = borderSize, top = borderSize, bottom = borderSize },
    })
end

---------------------------------------------------------------------
-- Re-apply (스케일 변경 시 재적용)
---------------------------------------------------------------------
function Lib.RePxSize(region)
    if region._slWidth then
        Lib.SetPxWidth(region, region._slWidth, region._slMinWidth)
    end
    if region._slHeight then
        Lib.SetPxHeight(region, region._slHeight, region._slMinHeight)
    end
end

function Lib.RePxPoint(region)
    if not region._slPoints or not next(region._slPoints) then return end
    region:ClearAllPoints()
    local es = region:GetEffectiveScale()
    for _, t in pairs(region._slPoints) do
        region:SetPoint(t[1], t[2], t[3],
            Lib.GetNearestPixelSize(t[4], es),
            Lib.GetNearestPixelSize(t[5], es))
    end
end

function Lib.RePxBorder(region)
    if not region.GetBackdrop then return end
    local bd = region:GetBackdrop()
    if not bd then return end
    if not (region._slEdgeSize or region._slInsets) then return end

    local r, g, b, a = region:GetBackdropColor()
    local br, bg, bb, ba = region:GetBackdropBorderColor()
    local es = region:GetEffectiveScale()

    if region._slEdgeSize then
        bd.edgeSize = Lib.GetNearestPixelSize(region._slEdgeSize, es)
    end
    if region._slInsets then
        bd.insets = {}
        for k, v in pairs(region._slInsets) do
            bd.insets[k] = Lib.GetNearestPixelSize(v, es)
        end
    end

    region:SetBackdrop(bd)
    region:SetBackdropColor(r, g, b, a)
    region:SetBackdropBorderColor(br, bg, bb, ba)
end

--- 모든 Pixel-Perfect 속성 재적용
function Lib.UpdatePixels(region)
    Lib.RePxSize(region)
    Lib.RePxPoint(region)
    Lib.RePxBorder(region)
end
