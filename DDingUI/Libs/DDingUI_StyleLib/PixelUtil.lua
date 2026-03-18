------------------------------------------------------
-- DDingUI_StyleLib :: PixelUtil
-- Pixel-perfect rendering system
-- EllesmereUI PP / PanelPP 시스템 완전 이식 + 기존 API 하위 호환
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local GetPhysicalScreenSize = GetPhysicalScreenSize
local math_floor = math.floor
local type = type

---------------------------------------------------------------------
-- PP (Pixel Perfect) — EllesmereUI 음수 모듈로 스냅 알고리즘
-- 모든 UIParent 자식 프레임에 적용
---------------------------------------------------------------------
local PP = {}
Lib.PP = PP

-- 물리 해상도 (세션 내 일정, 스케일 변경 시 갱신)
PP.physicalWidth, PP.physicalHeight = GetPhysicalScreenSize()

-- 768 = WoW 참조 높이; 스케일 1.0에서 1 물리 픽셀의 WoW 좌표 크기
PP.perfect = 768 / PP.physicalHeight

-- mult = 현재 UIParent 스케일에서 1 물리 픽셀의 크기
-- UI 스케일 변경 시 재계산
PP.mult = PP.perfect / (UIParent and UIParent:GetScale() or 1)

--- UIParent 스케일 변경 시 mult 재계산
function PP.UpdateMult()
    PP.physicalWidth, PP.physicalHeight = GetPhysicalScreenSize()
    PP.perfect = 768 / PP.physicalHeight
    PP.mult = PP.perfect / (UIParent:GetScale() or 1)
end

--- 값을 가장 가까운 물리 픽셀 경계로 스냅
--- EllesmereUI의 음수 모듈로 알고리즘 — floor(x/m+0.5)*m 보다 부동소수점 오차 적음
--- @param x number  스냅할 값
--- @return number   물리 픽셀 경계에 맞춘 값
function PP.Scale(x)
    if x == 0 then return 0 end
    local m = PP.mult
    if m == 1 then return math_floor(x + 0.5) end
    local y = m > 1 and m or -m
    return x - x % (x < 0 and y or -y)
end

--- 픽셀 스냅 SetSize
--- @param frame Frame
--- @param w number  너비
--- @param h number|nil  높이 (nil이면 w와 동일)
function PP.Size(frame, w, h)
    local sw = PP.Scale(w)
    frame:SetSize(sw, h and PP.Scale(h) or sw)
end

--- 픽셀 스냅 SetWidth
function PP.Width(frame, w)
    frame:SetWidth(PP.Scale(w))
end

--- 픽셀 스냅 SetHeight
function PP.Height(frame, h)
    frame:SetHeight(PP.Scale(h))
end

--- 픽셀 스냅 SetPoint — 숫자 오프셋 인자만 스냅
--- PP.Point(obj, "TOPLEFT", parent, "TOPLEFT", 10, -10)
--- PP.Point(obj, "CENTER", parent, "CENTER", 0, 0)
function PP.Point(obj, arg1, arg2, arg3, arg4, arg5)
    if not arg2 then arg2 = obj:GetParent() end
    if type(arg2) == "number" then arg2 = PP.Scale(arg2) end
    if type(arg3) == "number" then arg3 = PP.Scale(arg3) end
    if type(arg4) == "number" then arg4 = PP.Scale(arg4) end
    if type(arg5) == "number" then arg5 = PP.Scale(arg5) end
    obj:SetPoint(arg1, arg2, arg3, arg4, arg5)
end

--- 프레임 내부에 픽셀 스냅 앵커링 (TOPLEFT + BOTTOMRIGHT)
--- @param obj Region  배치할 리전
--- @param anchor Frame|nil  기준 프레임 (nil이면 부모)
--- @param xOff number|nil  좌우 오프셋 (기본 1)
--- @param yOff number|nil  상하 오프셋 (기본 1)
function PP.SetInside(obj, anchor, xOff, yOff)
    if not anchor then anchor = obj:GetParent() end
    local x = PP.Scale(xOff or 1)
    local y = PP.Scale(yOff or 1)
    obj:ClearAllPoints()
    PP.DisablePixelSnap(obj)
    obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
    obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
end

--- 프레임 외부에 픽셀 스냅 앵커링
function PP.SetOutside(obj, anchor, xOff, yOff)
    if not anchor then anchor = obj:GetParent() end
    local x = PP.Scale(xOff or 1)
    local y = PP.Scale(yOff or 1)
    obj:ClearAllPoints()
    PP.DisablePixelSnap(obj)
    obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -x, y)
    obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x, -y)
end

--- WoW 내장 픽셀 스냅 비활성화
--- SetColorTexture() 호출 시 WoW가 스냅을 재활성화하므로
--- PixelSnapDisabled 플래그로 중복 호출 방지 + 색 변경 후 재호출 필요
--- StatusBar의 내부 텍스처도 처리
--- @param obj Region  텍스처/프레임/상태바
function PP.DisablePixelSnap(obj)
    if not obj or obj.PixelSnapDisabled then return end
    if obj.SetSnapToPixelGrid then
        obj:SetSnapToPixelGrid(false)
        obj:SetTexelSnappingBias(0)
    elseif obj.GetStatusBarTexture then
        local tex = obj:GetStatusBarTexture()
        if type(tex) == "table" and tex.SetSnapToPixelGrid then
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
        end
    end
    obj.PixelSnapDisabled = true
end

--- 4-edge 텍스처 보더 생성 (Backdrop 미사용, 물리 1px)
--- 이미 생성된 경우 캐시된 테이블 반환
--- @param frame Frame
--- @param r number|nil  빨강 (기본 0)
--- @param g number|nil  초록 (기본 0)
--- @param b number|nil  파랑 (기본 0)
--- @param a number|nil  투명도 (기본 1)
--- @return table  { top, bottom, left, right, SetColor=fn }
function PP.CreateBorder(frame, r, g, b, a)
    if frame._ppBorders then return frame._ppBorders end
    r, g, b, a = r or 0, g or 0, b or 0, a or 1
    local brd = {}
    for i = 1, 4 do
        brd[i] = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        brd[i]:SetColorTexture(r, g, b, a)
        PP.DisablePixelSnap(brd[i])
    end
    local s = PP.Scale(1)
    -- top
    brd[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    brd[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    brd[1]:SetHeight(s)
    -- bottom
    brd[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    brd[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    brd[2]:SetHeight(s)
    -- left
    brd[3]:SetPoint("TOPLEFT", brd[1], "BOTTOMLEFT", 0, 0)
    brd[3]:SetPoint("BOTTOMLEFT", brd[2], "TOPLEFT", 0, 0)
    brd[3]:SetWidth(s)
    -- right
    brd[4]:SetPoint("TOPRIGHT", brd[1], "BOTTOMRIGHT", 0, 0)
    brd[4]:SetPoint("BOTTOMRIGHT", brd[2], "TOPRIGHT", 0, 0)
    brd[4]:SetWidth(s)

    --- 보더 색상 일괄 변경
    function brd:SetColor(cr, cg, cb, ca)
        for i = 1, 4 do
            self[i]:SetColorTexture(cr, cg, cb, ca or 1)
            -- SetColorTexture 후 PixelSnap 플래그 리셋 필요
            self[i].PixelSnapDisabled = nil
            PP.DisablePixelSnap(self[i])
        end
    end

    frame._ppBorders = brd
    return brd
end

--- 보더 두께 업데이트 (스케일 변경 후)
--- @param frame Frame
--- @param r number|nil  새 색상 (nil이면 기존 유지)
--- @param g number|nil
--- @param b number|nil
--- @param a number|nil
function PP.UpdateBorder(frame, r, g, b, a)
    local brd = frame._ppBorders
    if not brd then return end
    local s = PP.Scale(1)
    brd[1]:SetHeight(s)
    brd[2]:SetHeight(s)
    brd[3]:SetWidth(s)
    brd[4]:SetWidth(s)
    if r then
        brd:SetColor(r, g, b, a)
    end
end

---------------------------------------------------------------------
-- PanelPP — 옵션 패널 전용 PP 컨텍스트
-- 패널의 userScale이 UIParent와 다를 때 독립 스냅 수행
---------------------------------------------------------------------
local PanelPP = {}
Lib.PanelPP = PanelPP

-- mult = 1 / userScale (패널 좌표에서의 1 물리 픽셀 크기)
PanelPP.mult = 1

--- 패널 스케일 변경 시 호출
--- @param userScale number|nil  사용자 지정 패널 스케일 (기본 1.0)
function PanelPP.UpdateMult(userScale)
    userScale = userScale or 1.0
    if userScale == 0 then userScale = 1 end
    PanelPP.mult = 1 / userScale
end

--- 패널 전용 픽셀 스냅 — PP.Scale과 동일 알고리즘, 다른 mult
function PanelPP.Scale(x)
    if x == 0 then return 0 end
    local m = PanelPP.mult
    if m == 1 then return math_floor(x + 0.5) end
    local y = m > 1 and m or -m
    return x - x % (x < 0 and y or -y)
end

function PanelPP.Size(frame, w, h)
    local sw = PanelPP.Scale(w)
    frame:SetSize(sw, h and PanelPP.Scale(h) or sw)
end

function PanelPP.Width(frame, w)
    frame:SetWidth(PanelPP.Scale(w))
end

function PanelPP.Height(frame, h)
    frame:SetHeight(PanelPP.Scale(h))
end

function PanelPP.Point(obj, arg1, arg2, arg3, arg4, arg5)
    if not arg2 then arg2 = obj:GetParent() end
    if type(arg2) == "number" then arg2 = PanelPP.Scale(arg2) end
    if type(arg3) == "number" then arg3 = PanelPP.Scale(arg3) end
    if type(arg4) == "number" then arg4 = PanelPP.Scale(arg4) end
    if type(arg5) == "number" then arg5 = PanelPP.Scale(arg5) end
    obj:SetPoint(arg1, arg2, arg3, arg4, arg5)
end

function PanelPP.SetInside(obj, anchor, xOff, yOff)
    if not anchor then anchor = obj:GetParent() end
    local x = PanelPP.Scale(xOff or 1)
    local y = PanelPP.Scale(yOff or 1)
    obj:ClearAllPoints()
    PP.DisablePixelSnap(obj)  -- DisablePixelSnap은 스케일 무관
    obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
    obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
end

function PanelPP.SetOutside(obj, anchor, xOff, yOff)
    if not anchor then anchor = obj:GetParent() end
    local x = PanelPP.Scale(xOff or 1)
    local y = PanelPP.Scale(yOff or 1)
    obj:ClearAllPoints()
    PP.DisablePixelSnap(obj)
    obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -x, y)
    obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x, -y)
end

-- DisablePixelSnap은 스케일 무관 — PP 것 재사용
PanelPP.DisablePixelSnap = PP.DisablePixelSnap

--- 패널 전용 4-edge 보더
function PanelPP.CreateBorder(frame, r, g, b, a)
    if frame._ppBorders then return frame._ppBorders end
    r, g, b, a = r or 0, g or 0, b or 0, a or 1
    local brd = {}
    for i = 1, 4 do
        brd[i] = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        brd[i]:SetColorTexture(r, g, b, a)
        PP.DisablePixelSnap(brd[i])
    end
    local s = PanelPP.Scale(1)
    brd[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    brd[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    brd[1]:SetHeight(s)
    brd[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    brd[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    brd[2]:SetHeight(s)
    brd[3]:SetPoint("TOPLEFT", brd[1], "BOTTOMLEFT", 0, 0)
    brd[3]:SetPoint("BOTTOMLEFT", brd[2], "TOPLEFT", 0, 0)
    brd[3]:SetWidth(s)
    brd[4]:SetPoint("TOPRIGHT", brd[1], "BOTTOMRIGHT", 0, 0)
    brd[4]:SetPoint("BOTTOMRIGHT", brd[2], "TOPRIGHT", 0, 0)
    brd[4]:SetWidth(s)

    function brd:SetColor(cr, cg, cb, ca)
        for i = 1, 4 do
            self[i]:SetColorTexture(cr, cg, cb, ca or 1)
            self[i].PixelSnapDisabled = nil
            PP.DisablePixelSnap(self[i])
        end
    end

    frame._ppBorders = brd
    return brd
end

function PanelPP.UpdateBorder(frame, r, g, b, a)
    local brd = frame._ppBorders
    if not brd then return end
    local s = PanelPP.Scale(1)
    brd[1]:SetHeight(s)
    brd[2]:SetHeight(s)
    brd[3]:SetWidth(s)
    brd[4]:SetWidth(s)
    if r then brd:SetColor(r, g, b, a) end
end

---------------------------------------------------------------------
-- UI 스케일 변경 이벤트 리스너
---------------------------------------------------------------------
local scaleWatcher = CreateFrame("Frame")
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleWatcher:SetScript("OnEvent", function()
    PP.UpdateMult()
    -- PanelPP는 사용자가 직접 UpdateMult(scale) 호출해야 함
    -- 여기서는 PP 전역만 갱신
end)

---------------------------------------------------------------------
-- 하위 호환 API (기존 코드가 Lib.SetPxSize 등을 호출하는 경우)
-- 내부적으로 PP 시스템 사용하도록 브릿지
---------------------------------------------------------------------

local function Round(n)
    if n >= 0 then
        return math_floor(n + 0.5)
    else
        return math_floor(n - 0.5)
    end
end

--- @deprecated  PP.Scale() 사용 권장
function Lib.GetPixelFactor()
    return PP.perfect
end

function Lib.GetBestScale()
    local factor = PP.perfect
    local mult
    if factor >= 0.71 then      -- 1080p
        mult = 1
    elseif factor >= 0.53 then  -- 1440p
        mult = 1.15
    else                        -- 2160p (4K)
        mult = 1.7
    end
    local result = factor * mult
    result = math_floor(result * 100 + 0.5) / 100
    if result < 0.5 then result = 0.5 end
    if result > 1.5 then result = 1.5 end
    return result
end

function Lib.GetNearestPixelSize(uiUnitSize, layoutScale, minPixels)
    if uiUnitSize == 0 and (not minPixels or minPixels == 0) then
        return 0
    end
    local uiUnitFactor = PP.perfect
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

-- 기존 SetPx* API — 내부적으로 PP.Scale 활용하도록 개선
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

-- 편의 별명: PP.DisablePixelSnap을 Lib에서도 접근 가능하게
Lib.DisablePixelSnap = PP.DisablePixelSnap

---------------------------------------------------------------------
-- Pixel-Perfect Backdrop (하위 호환)
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
-- Re-apply (스케일 변경 시 재적용) — 하위 호환
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

function Lib.UpdatePixels(region)
    Lib.RePxSize(region)
    Lib.RePxPoint(region)
    Lib.RePxBorder(region)
end
