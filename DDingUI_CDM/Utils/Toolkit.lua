local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

if not DDingUI then
	error("DDingUI not found! Toolkit.lua must load after Main.lua")
end

-- ============================================================
-- COMMON UTILITY FUNCTIONS (shared across all modules)
-- ============================================================

-- [FIX] WoW 12.0: EasyMenu / UIDropDownMenuTemplate 제거됨 → MenuUtil 기반 polyfill
if not EasyMenu and MenuUtil and MenuUtil.CreateContextMenu then
    EasyMenu = function(menuList, _, anchorFrame, x, y, displayMode)
        MenuUtil.CreateContextMenu(anchorFrame, function(ownerRegion, rootDescription)
            for _, item in ipairs(menuList) do
                if item.isTitle then
                    rootDescription:CreateTitle(item.text or "")
                elseif item.isSeparator then
                    rootDescription:CreateDivider()
                elseif item.hasArrow and item.menuList then
                    local sub = rootDescription:CreateButton(item.text or "")
                    for _, subItem in ipairs(item.menuList) do
                        if subItem.isTitle then
                            sub:CreateTitle(subItem.text or "")
                        else
                            sub:CreateButton(subItem.text or "", function()
                                if subItem.func then subItem.func() end
                            end)
                        end
                    end
                else
                    rootDescription:CreateButton(item.text or "", function()
                        if item.func then item.func() end
                    end)
                end
            end
        end)
    end
end

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
    local fallbackWidth = frame:GetWidth()
    -- [FIX] 0 또는 nil 반환 방지 — CDM 뷰어 재생성 중 GetWidth()=0 대응
    -- 0을 반환하면 자원바가 너비=0이 되어 사라짐
    if not fallbackWidth or fallbackWidth <= 0 then
        return nil, false
    end
    return fallbackWidth, false
end

-- ============================================================
-- [REFACTOR] 자동 너비("앵커 너비에 맞춤", width = 0) 공통 해석
-- 주 자원·보조 자원·시전·추적 막대·강화효과 막대와 옵션 대시보드가 모두 이 함수만 쓴다.
-- 고정 상한(600/1000)은 없다. 비정상 값은 0 이하·NaN·secret·UIParent 폭 초과뿐이다.
-- ============================================================
local AUTO_WIDTH_FALLBACK = 200

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

--- 막대 폭으로 쓸 수 있는 값인지: 숫자, secret 아님, NaN 아님, 0 초과, UIParent 폭 이하.
function DDingUI:IsUsableAutoWidth(value)
    if type(value) ~= "number" or IsSecretValue(value) or value ~= value then return false end
    if value <= 0 then return false end
    local limit = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    if type(limit) == "number" and not IsSecretValue(limit) and limit > 0 and value > limit then
        return false
    end
    return true
end

-- 다른 DDingUI 막대에 붙은 경우: 그 막대의 프레임 폭을 그대로 쓴다(바깥 테두리가 이미 같은 규칙).
local function IsDDingUIBarAnchor(addon, anchor)
    if anchor == addon.powerBar or anchor == addon.secondaryPowerBar
        or anchor == addon.castBar or anchor == addon.buffTrackerBar then
        return true
    end
    local name = anchor.GetName and anchor:GetName()
    return type(name) == "string" and name:match("^DDingUIBuffTracker") ~= nil
end

local function AutoWidthAnchorKey(anchor)
    local name = anchor and anchor.GetName and anchor:GetName()
    return name or anchor or false
end

--- 앵커에 맞춘 막대 폭.
-- anchor: 앵커 프레임. borderSize: 막대의 바깥 테두리 설정값(ScaleBorder 전, 안쪽 테두리 막대는 0).
-- opts.owner: 마지막 정상 폭을 기억할 막대(또는 상태 테이블). 앵커 이름이 바뀌면 초기화한다.
-- opts.noStore: owner에 기록하지 않는다(옵션 미리보기). opts.fallback: 정상값이 한 번도 없을 때 폭.
-- Returns width, resolved (true면 이번 앵커에서 계산된 값, false면 마지막 정상값 또는 fallback).
function DDingUI:ResolveAutoWidth(anchor, borderSize, opts)
    opts = opts or {}
    local owner = opts.owner
    local key = AutoWidthAnchorKey(anchor)
    if owner and not opts.noStore and owner._ddAutoWidthAnchor ~= key then
        owner._ddAutoWidthAnchor = key
        owner._ddLastAutoWidth = nil
    end

    local width
    if anchor and anchor ~= UIParent then
        local ok, effective, needsBorderComp = pcall(function()
            if IsDDingUIBarAnchor(self, anchor) then return anchor:GetWidth(), false end
            return self:GetEffectiveAnchorWidth(anchor)
        end)
        if ok and self:IsUsableAutoWidth(effective) then
            if needsBorderComp then
                local border = tonumber(borderSize) or 1
                border = self.ScaleBorder and self:ScaleBorder(border) or border
                effective = effective - 2 * border
            end
            effective = PixelSnap(effective)
            if self:IsUsableAutoWidth(effective) then width = effective end
        end
    end

    if width then
        if owner and not opts.noStore then owner._ddLastAutoWidth = width end
        return width, true
    end
    local last = owner and owner._ddAutoWidthAnchor == key and owner._ddLastAutoWidth
    if self:IsUsableAutoWidth(last) then return last, false end
    return opts.fallback or AUTO_WIDTH_FALLBACK, false
end

-- ============================================================
-- [REFACTOR] 앵커 폭 변경 알림
-- 그룹 렌더러가 아이콘 줄 폭을 실제로 바꾸면(또는 막대 폭이 바뀌면) 한 프레임 모아 한 번 보낸다.
-- 리스너는 order 순서(주 자원 → 보조 → 시전 → 추적 → 강화효과)로 호출되고,
-- 막대 폭이 바뀐 막대는 다시 알려 막대에 붙은 막대가 다음 프레임에 연쇄 갱신된다.
-- ============================================================
local anchorWidthListeners = {}
local anchorWidthPending = {}
local anchorWidthScheduled = false

local function FlushAnchorWidthChanges()
    anchorWidthScheduled = false
    local keys = anchorWidthPending
    anchorWidthPending = {}
    for _, listener in ipairs(anchorWidthListeners) do
        local ok, err = pcall(listener.fn, keys)
        if not ok then
            local handler = geterrorhandler and geterrorhandler()
            if handler then handler(err) end -- report, but keep the other bars updating
        end
    end
end

function DDingUI:RegisterAnchorWidthListener(fn, order)
    if type(fn) ~= "function" then return end
    anchorWidthListeners[#anchorWidthListeners + 1] = { fn = fn, order = tonumber(order) or 100 }
    table.sort(anchorWidthListeners, function(a, b) return a.order < b.order end)
end

function DDingUI:NotifyAnchorWidthChanged(key)
    anchorWidthPending[key or "anchor"] = true
    if anchorWidthScheduled then return end
    anchorWidthScheduled = true
    C_Timer.After(0, FlushAnchorWidthChanges)
end

-- ============================================================
-- [REFACTOR] 레이아웃 미리보기 강제 표시 (옵션 대시보드가 열린 동안)
-- 편집 모드와 같은 경로로 꺼진 강화효과·커스텀 아이콘을 실제로 띄운다. 전투 밖에서만 켜지고,
-- 전투가 시작되면 즉시 꺼진다. 저장 값은 쓰지 않는다(런타임 필드만).
-- 켜져 있는 동안 커스텀 오라·아이콘 상태·조건 동작의 소리는 재생하지 않는다.
-- ============================================================
function DDingUI:IsLayoutPreviewForced()
    return self._layoutPreviewForced == true and not InCombatLockdown()
end

local function RefreshForcedLayout(addon)
    local bridge = addon.DynamicIconBridge
    if bridge and bridge.NotifyIconsChanged then bridge:NotifyIconsChanged(true) end
    local groupSystem = addon.GroupSystem
    if groupSystem and groupSystem.RequestFullUpdate then groupSystem:RequestFullUpdate() end
end

--- on=true는 전투 밖에서만 적용된다. Returns the resulting state.
function DDingUI:SetLayoutPreviewForced(on)
    on = on == true and not InCombatLockdown()
    if (self._layoutPreviewForced == true) == on then return on end
    self._layoutPreviewForced = on or nil
    RefreshForcedLayout(self)
    return on
end

local layoutPreviewCombatFrame = CreateFrame("Frame")
layoutPreviewCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
layoutPreviewCombatFrame:SetScript("OnEvent", function()
    if DDingUI._layoutPreviewForced then
        DDingUI._layoutPreviewForced = nil
        RefreshForcedLayout(DDingUI)
    end
end)

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

    -- 2. bt:<uid> 패턴: 오라 uid → 현재 인덱스 → 프레임 해석
    local uid = name:match("^bt:(.+)$")
    if uid and DDingUI.FindTrackedBuffByUID then
        local idx, buff = DDingUI.FindTrackedBuffByUID(uid)
        if idx and buff then
            local displayType = buff.displayType or "bar"
            local frameName
            if displayType == "icon" then
                frameName = "DDingUIBuffTrackerIcon" .. idx
            elseif displayType == "text" then
                frameName = "DDingUIBuffTrackerText" .. idx
            else
                frameName = "DDingUIBuffTrackerBar" .. idx
            end
            local frame = _G[frameName]
            if frame then return frame end
        end
    end

    -- 3. 직접 _G에서 찾기 (DDingUI_UF 프레임 포함: ddingUI_Player, ddingUI_Target 등)
    local frame = _G[name]
    if frame then return frame end

    -- 4. UIParent 폴백
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

local function DisablePixelSnap(frame)
	if not CanAccessFrame(frame) then
		return
	end

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

	-- Never hook shared widget metatables here. Blizzard action buttons use the
	-- same methods, so a global post-hook contaminates their protected state.
	-- DDingUI-owned regions opt in through SetInside/SetOutside instead.
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

-- ============================================================
-- [FIX CDM] 쿨다운 탈색 판단용 CurveDataProvider (CDM CDM Constants.lua 동일 패턴)
-- desatDurationObject:EvaluateRemainingDuration(curve, 0) → 0 or 1 (Step)
-- DesaturationCurve : 남은 시간 > 0 → 1 (쿨다운 중 = 회색)
-- GCDFilterCurve    : 남은 시간 > 1.6s → 1 (GCD 이상 쿨다운만 회색)
-- ============================================================
if C_CurveUtil and C_CurveUtil.CreateCurve then
    DDingUI._DesaturationCurve = C_CurveUtil.CreateCurve()
    DDingUI._DesaturationCurve:SetType(Enum.LuaCurveType.Step)
    DDingUI._DesaturationCurve:AddPoint(0, 0)
    DDingUI._DesaturationCurve:AddPoint(0.001, 1)

    DDingUI._GCDFilterCurve = C_CurveUtil.CreateCurve()
    DDingUI._GCDFilterCurve:SetType(Enum.LuaCurveType.Step)
    DDingUI._GCDFilterCurve:AddPoint(0, 0)
    DDingUI._GCDFilterCurve:AddPoint(1.6, 1)
end
