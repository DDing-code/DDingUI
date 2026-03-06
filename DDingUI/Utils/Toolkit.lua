local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

if not DDingUI then
	error("DDingUI not found! Toolkit.lua must load after Main.lua")
end

-- ============================================================
-- COMMON UTILITY FUNCTIONS (shared across all modules)
-- ============================================================

-- PixelSnap: Round value to nearest pixel
function DDingUI:PixelSnap(value)
    return math.max(0, math.floor((value or 0) + 0.5))
end

-- Expose as local for faster access
local PixelSnap = function(value)
    return math.max(0, math.floor((value or 0) + 0.5))
end
DDingUI.PixelSnapLocal = PixelSnap

-- GetEffectiveAnchorWidth: 앵커 프레임의 실제 콘텐츠 너비 계산
-- CDM 뷰어는 __cdmIconWidth 사용, ActionBar 등 일반 프레임은 자식 버튼 배치로 계산
-- Returns: width, needsBorderCompensation
--   needsBorderCompensation: true = 아이콘 레이아웃 너비 (__cdmIconWidth) → 바 보더 차감 필요
--                           false = 프레임 자체 너비 (GetWidth) → 이미 보더가 반영된 상태
function DDingUI:GetEffectiveAnchorWidth(frame)
    if not frame then return 0, false end

    -- [FIX/12.0.1] 프록시 앵커로 쿼리가 들어온 경우, 실제 그룹 컨테이너(DDingUI_Group_X)의 너비를 참조하도록 폴백
    if frame.GetName then
        local name = frame:GetName()
        if name then
            if name == "DDingUI_Anchor_Cooldowns" and _G["DDingUI_Group_Cooldowns"] then
                frame = _G["DDingUI_Group_Cooldowns"]
            elseif name == "DDingUI_Anchor_Buffs" and _G["DDingUI_Group_Buffs"] then
                frame = _G["DDingUI_Group_Buffs"]
            elseif name == "DDingUI_Anchor_Utility" and _G["DDingUI_Group_Utility"] then
                frame = _G["DDingUI_Group_Utility"]
            end
        end
    end

    -- CDM 뷰어/그룹 프레임은 아이콘 배치 너비를 직접 저장
    if frame.__cdmIconWidth and frame.__cdmIconWidth > 0 then
        return frame.__cdmIconWidth, true
    end

    -- ActionBar 등: 보이는 자식 프레임의 실제 배치 범위로 계산
    local ok, contentWidth = pcall(function()
        if not frame.GetChildren then return nil end
        local children = {frame:GetChildren()}
        if #children < 2 then return nil end

        local frameLeft = frame:GetLeft()
        local frameRight = frame:GetRight()
        if not frameLeft or not frameRight or (frameRight - frameLeft) <= 0 then return nil end

        local minLeft, maxRight
        for _, child in ipairs(children) do
            if child:IsShown() then
                local l, r = child:GetLeft(), child:GetRight()
                if l and r then
                    minLeft = minLeft and math.min(minLeft, l) or l
                    maxRight = maxRight and math.max(maxRight, r) or r
                end
            end
        end

        if not minLeft or not maxRight or maxRight <= minLeft then return nil end

        -- 스크린 좌표 → 프레임 로컬 좌표 변환
        local screenFrameW = frameRight - frameLeft
        local localFrameW = frame:GetWidth()
        if screenFrameW > 0 and localFrameW > 0 then
            return (maxRight - minLeft) * (localFrameW / screenFrameW)
        end
        return nil
    end)

    if ok and contentWidth and contentWidth > 0 then
        return contentWidth, false
    end

    -- 폴백: 프레임 자체 너비 (보더 차감 불필요)
    return frame:GetWidth(), false
end

-- ============================================================
-- ResolveAnchorFrame: 앵커 이름 → 실제 프레임 해석
-- CDM 뷰어 이름, DDingUI 그룹 이름, 프록시 앵커 이름 모두 지원
-- CDM 뷰어가 재생성 중이면 프록시 앵커로 자동 폴백
-- ============================================================
local ANCHOR_TO_PROXY = {
    -- CDM 뷰어 → 프록시
    ["EssentialCooldownViewer"] = "DDingUI_Anchor_Cooldowns",
    ["UtilityCooldownViewer"]   = "DDingUI_Anchor_Utility",
    ["BuffIconCooldownViewer"]  = "DDingUI_Anchor_Buffs",
    -- DDingUI 그룹 → 프록시
    ["DDingUI_Group_Cooldowns"] = "DDingUI_Anchor_Cooldowns",
    ["DDingUI_Group_Utility"]   = "DDingUI_Anchor_Utility",
    ["DDingUI_Group_Buffs"]     = "DDingUI_Anchor_Buffs",
}

function DDingUI:ResolveAnchorFrame(name)
    if not name or name == "" or name == "UIParent" then
        return UIParent
    end

    -- 1. CDM 뷰어 또는 그룹 이름이면 항상 프록시로 리다이렉트
    -- CDM 뷰어는 alpha=0으로 숨겨져 있으므로 직접 앵커하면 안 됨
    local proxyName = ANCHOR_TO_PROXY[name]
    if proxyName then
        local proxy = _G[proxyName]
        if proxy then return proxy end
    end

    -- 2. 직접 _G에서 찾기 (DDingUI_UF 프레임 포함: ddingUI_Player, ddingUI_Target 등)
    local frame = _G[name]
    if frame then return frame end

    -- 3. UIParent 폴백
    return UIParent
end

-- [CDM↔UF 호환] UF 프레임 이름 목록 (attachTo 드롭다운/프레임 피커에서 사용)
DDingUI.UF_ANCHOR_FRAMES = {
    { name = "ddingUI_Player",       display = "UF: 플레이어" },
    { name = "ddingUI_Target",       display = "UF: 대상" },
    { name = "ddingUI_TargetTarget", display = "UF: 대상의 대상" },
    { name = "ddingUI_Focus",        display = "UF: 초점" },
    { name = "ddingUI_FocusTarget",  display = "UF: 초점의 대상" },
    { name = "ddingUI_Pet",          display = "UF: 소환수" },
    { name = "ddingUI_Boss1",        display = "UF: 보스1" },
}

-- ============================================================
-- Shared TextureBorder Utilities (taint-safe, no SetBackdrop)
-- 4개 모듈(PrimaryPowerBar, SecondaryPowerBar, BuffTrackerBar, CustomIcons)에서 공유
-- ============================================================

--- CreateTextureBorder: 프레임에 텍스처 기반 보더 생성/업데이트
-- @param parent 보더를 붙일 프레임
-- @param borderSize 보더 두께 (px)
-- @param r,g,b,a 보더 색상
-- @param inset true = 안쪽 보더 (CustomIcons), false/nil = 바깥쪽 보더 (ResourceBars)
function DDingUI.CreateTextureBorder(parent, borderSize, r, g, b, a, inset)
    parent.__dduiBorders = parent.__dduiBorders or {}
    local borders = parent.__dduiBorders

    if #borders == 0 then
        local function CreateBorderTex()
            local tex = parent:CreateTexture(nil, "OVERLAY")
            tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
            return tex
        end
        borders[1] = CreateBorderTex()  -- top
        borders[2] = CreateBorderTex()  -- bottom
        borders[3] = CreateBorderTex()  -- left
        borders[4] = CreateBorderTex()  -- right
        parent.__dduiBorders = borders
    end

    local top, bottom, left, right = borders[1], borders[2], borders[3], borders[4]
    local off = inset and 0 or borderSize  -- 안쪽: 오프셋 0, 바깥쪽: borderSize

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", -off, off)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", off, off)
    top:SetHeight(borderSize)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -off, -off)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", off, -off)
    bottom:SetHeight(borderSize)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", -off, off)
    left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -off, -off)
    left:SetWidth(borderSize)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", off, off)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", off, -off)
    right:SetWidth(borderSize)

    return borders
end

function DDingUI.UpdateTextureBorderColor(parent, r, g, b, a)
    local borders = parent.__dduiBorders
    if not borders then return end
    for _, tex in ipairs(borders) do
        tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end
end

function DDingUI.UpdateTextureBorderSize(parent, borderSize, inset)
    local borders = parent.__dduiBorders
    if not borders or #borders < 4 then return end

    local top, bottom, left, right = borders[1], borders[2], borders[3], borders[4]
    local off = inset and 0 or borderSize

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", -off, off)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", off, off)
    top:SetHeight(borderSize)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -off, -off)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", off, -off)
    bottom:SetHeight(borderSize)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", -off, off)
    left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -off, -off)
    left:SetWidth(borderSize)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", off, off)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", off, -off)
    right:SetWidth(borderSize)
end

function DDingUI.ShowTextureBorder(parent, show)
    local borders = parent.__dduiBorders
    if not borders then return end
    for _, tex in ipairs(borders) do
        tex:SetShown(show)
    end
end



local _G = _G
local type = type
local getmetatable = getmetatable
local hooksecurefunc = hooksecurefunc
local tonumber = tonumber

local EnumerateFrames = EnumerateFrames
local CreateFrame = CreateFrame

local issecurevalue = issecurevalue
local issecretvalue = issecretvalue -- [12.0.1] secret table 방어

local function CanAccessFrame(frame)
	if not frame then
		return false
	end

	-- [12.0.1] secret table 값은 인덱싱 자체가 에러 → 먼저 차단
	if issecretvalue and issecretvalue(frame) then
		return false
	end

	if issecurevalue and issecurevalue(frame) then
		return false
	end

	if frame.IsForbidden then
		local ok, forbidden = pcall(frame.IsForbidden, frame)
		if not ok or forbidden then
			return false
		end
	end

	return true
end

local function WatchPixelSnap(frame, snap)
	if not CanAccessFrame(frame) then
		return
	end

	if frame.PixelSnapDisabled and snap then
		frame.PixelSnapDisabled = nil
	end
end

local function DisablePixelSnap(frame)
	if not CanAccessFrame(frame) then
		return
	end

	if not frame.PixelSnapDisabled then
		if frame.SetSnapToPixelGrid then
			frame:SetSnapToPixelGrid(false)
			frame:SetTexelSnappingBias(0)
		elseif frame.GetStatusBarTexture then
			local texture = frame:GetStatusBarTexture()
			if type(texture) == 'table' and texture.SetSnapToPixelGrid then
				texture:SetSnapToPixelGrid(false)
				texture:SetTexelSnappingBias(0)
			end
		end

		frame.PixelSnapDisabled = true
	end
end

local function Size(frame, width, height, ...)
	local w = DDingUI:Scale(width)
	frame:SetSize(w, (height and DDingUI:Scale(height)) or w, ...)
end

local function Width(frame, width, ...)
	frame:SetWidth(DDingUI:Scale(width), ...)
end

local function Height(frame, height, ...)
	frame:SetHeight(DDingUI:Scale(height), ...)
end

local function Point(obj, arg1, arg2, arg3, arg4, arg5, ...)
	if not arg2 then arg2 = obj:GetParent() end

	if type(arg2)=='number' then arg2 = DDingUI:Scale(arg2) end
	if type(arg3)=='number' then arg3 = DDingUI:Scale(arg3) end
	if type(arg4)=='number' then arg4 = DDingUI:Scale(arg4) end
	if type(arg5)=='number' then arg5 = DDingUI:Scale(arg5) end

	obj:SetPoint(arg1, arg2, arg3, arg4, arg5, ...)
end

local function GrabPoint(obj, pointValue)
	if type(pointValue) == 'string' then
		local pointIndex = tonumber(pointValue)
		if not pointIndex then
			for i = 1, obj:GetNumPoints() do
				local point, relativeTo, relativePoint, xOfs, yOfs = obj:GetPoint(i)
				if not point then
					break
				elseif point == pointValue then
					return point, relativeTo, relativePoint, xOfs, yOfs
				end
			end
		end

		pointValue = pointIndex
	end

	return obj:GetPoint(pointValue)
end

local function SetPointsRestricted(frame)
	if frame and not pcall(frame.GetPoint, frame) then
		return true
	end
end

local function NudgePoint(obj, xAxis, yAxis, noScale, pointValue, clearPoints)
	if not xAxis then xAxis = 0 end
	if not yAxis then yAxis = 0 end

	local x = (noScale and xAxis) or DDingUI:Scale(xAxis)
	local y = (noScale and yAxis) or DDingUI:Scale(yAxis)

	local point, relativeTo, relativePoint, xOfs, yOfs = GrabPoint(obj, pointValue)

	if clearPoints or SetPointsRestricted(obj) then
		obj:ClearAllPoints()
	end

	obj:SetPoint(point, relativeTo, relativePoint, xOfs + x, yOfs + y)
end

local function PointXY(obj, xOffset, yOffset, noScale, pointValue, clearPoints)
	local x = xOffset and ((noScale and xOffset) or DDingUI:Scale(xOffset))
	local y = yOffset and ((noScale and yOffset) or DDingUI:Scale(yOffset))

	local point, relativeTo, relativePoint, xOfs, yOfs = GrabPoint(obj, pointValue)

	if clearPoints or SetPointsRestricted(obj) then
		obj:ClearAllPoints()
	end

	obj:SetPoint(point, relativeTo, relativePoint, x or xOfs, y or yOfs)
end

local function SetOutside(obj, anchor, xOffset, yOffset, anchor2, noScale)
	if not anchor then anchor = obj:GetParent() end

	if not xOffset then xOffset = 1 end
	if not yOffset then yOffset = 1 end
	local x = (noScale and xOffset) or DDingUI:Scale(xOffset)
	local y = (noScale and yOffset) or DDingUI:Scale(yOffset)

	if SetPointsRestricted(obj) or obj:GetPoint() then
		obj:ClearAllPoints()
	end

	DisablePixelSnap(obj)
	obj:SetPoint('TOPLEFT', anchor, 'TOPLEFT', -x, y)
	obj:SetPoint('BOTTOMRIGHT', anchor2 or anchor, 'BOTTOMRIGHT', x, -y)
end

local function SetInside(obj, anchor, xOffset, yOffset, anchor2, noScale)
	if not anchor then anchor = obj:GetParent() end

	if not xOffset then xOffset = 1 end
	if not yOffset then yOffset = 1 end
	local x = (noScale and xOffset) or DDingUI:Scale(xOffset)
	local y = (noScale and yOffset) or DDingUI:Scale(yOffset)

	if SetPointsRestricted(obj) or obj:GetPoint() then
		obj:ClearAllPoints()
	end

	DisablePixelSnap(obj)
	obj:SetPoint('TOPLEFT', anchor, 'TOPLEFT', x, -y)
	obj:SetPoint('BOTTOMRIGHT', anchor2 or anchor, 'BOTTOMRIGHT', -x, y)
end

local API = {
	Size = Size,
	Point = Point,
	Width = Width,
	Height = Height,
	PointXY = PointXY,
	GrabPoint = GrabPoint,
	NudgePoint = NudgePoint,
	SetOutside = SetOutside,
	SetInside = SetInside,
}

local function AddAPI(object)
	local mk = getmetatable(object).__index
	for method, func in next, API do
		if not object[method] then
			mk[method] = func
		end
	end

	if not object.DisabledPixelSnap and (mk.SetSnapToPixelGrid or mk.SetStatusBarTexture or mk.SetColorTexture or mk.SetVertexColor or mk.CreateTexture or mk.SetTexCoord or mk.SetTexture) then
		if mk.SetSnapToPixelGrid then hooksecurefunc(mk, 'SetSnapToPixelGrid', WatchPixelSnap) end
		if mk.SetStatusBarTexture then hooksecurefunc(mk, 'SetStatusBarTexture', DisablePixelSnap) end
		if mk.SetColorTexture then hooksecurefunc(mk, 'SetColorTexture', DisablePixelSnap) end
		if mk.SetVertexColor then hooksecurefunc(mk, 'SetVertexColor', DisablePixelSnap) end
		if mk.CreateTexture then hooksecurefunc(mk, 'CreateTexture', DisablePixelSnap) end
		if mk.SetTexCoord then hooksecurefunc(mk, 'SetTexCoord', DisablePixelSnap) end
		if mk.SetTexture then hooksecurefunc(mk, 'SetTexture', DisablePixelSnap) end

		mk.DisabledPixelSnap = true
	end
end

local handled = { Frame = true }
local object = CreateFrame('Frame')
AddAPI(object)
AddAPI(object:CreateTexture())
AddAPI(object:CreateFontString())
if object.CreateMaskTexture then
	AddAPI(object:CreateMaskTexture())
end

object = EnumerateFrames()
while object do
	-- [12.0.1] secret table 방어: 인덱싱 전 체크
	if not (issecretvalue and issecretvalue(object)) then
		local ok, objType = pcall(object.GetObjectType, object)
		if ok and objType then
			local ok2, forbidden = pcall(object.IsForbidden, object)
			if ok2 and not forbidden and not handled[objType] then
				AddAPI(object)
				handled[objType] = true
			end
		end
	end

	object = EnumerateFrames(object)
end

AddAPI(_G.GameFontNormal)
AddAPI(CreateFrame('ScrollFrame'))

