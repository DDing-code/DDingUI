-- DDingUI_Essential: Minimap Module -- [ESSENTIAL]
-- SakuriaUI 스타일 미니맵 스킨: 사각형, 이너섀도, 픽셀퍼펙트, 클린 다크 테마
-- 참조: SakuriaUI/modules/minimap.lua, ElvUI/Game/Shared/Modules/Maps/Minimap.lua

local _, ns = ...

local MinimapSkin = {}

------------------------------------------------------------------------
-- StyleLib 참조 -- [ESSENTIAL]
------------------------------------------------------------------------
local SL      = _G.DDingUI_StyleLib
local C       = SL and SL.Colors
local F       = SL and SL.Font
local FLAT    = SL and SL.Textures and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local SL_FONT = F and F.path or "Fonts\\2002.TTF"

local function GetC(category, key)
    return (C and C[category] and C[category][key]) or nil
end

local function Unpack(tbl, fr, fg, fb, fa)
    if tbl then return tbl[1], tbl[2], tbl[3], tbl[4] or 1 end
    return fr or 0.1, fg or 0.1, fb or 0.1, fa or 0.9
end

------------------------------------------------------------------------
-- PixelUtil 헬퍼 -- [ESSENTIAL]
------------------------------------------------------------------------
local PU = PixelUtil
local function SnapSize(frame, w, h)
    if PU and PU.SetSize then PU.SetSize(frame, w, h) else frame:SetSize(w, h) end
end
local function SnapPoint(frame, p, rel, rp, x, y)
    if PU and PU.SetPoint then PU.SetPoint(frame, p, rel, rp, x, y) else frame:SetPoint(p, rel, rp, x, y) end
end

------------------------------------------------------------------------
-- 로컬 캐시 -- [ESSENTIAL]
------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local GetMinimapZoneText = GetMinimapZoneText
local InCombatLockdown = InCombatLockdown

local C_PvP = C_PvP
local GetZonePVPInfo = (C_PvP and C_PvP.GetZonePVPInfo) or GetZonePVPInfo

local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster

-- 악센트 캐시 (Enable 시 설정) -- [ESSENTIAL]
local accentFrom, accentTo

------------------------------------------------------------------------
-- 상수 (SakuriaUI 스타일) -- [ESSENTIAL]
------------------------------------------------------------------------
local BORDER_SIZE   = 1       -- 1px 검정 테두리
local SHADOW_SIZE   = 3       -- 외곽 그림자 크기
local HOLDER_PAD    = 2       -- holder 패딩

------------------------------------------------------------------------
-- 존 텍스트 PVP 색상 (StyleLib status 색상 활용) -- [ESSENTIAL]
------------------------------------------------------------------------
local PVP_COLORS = {
    sanctuary = GetC("text", "highlight") or { 0.04, 0.58, 0.84 },
    friendly  = GetC("status", "success") or { 0.05, 0.85, 0.03 },
    hostile   = GetC("status", "error")   or { 0.84, 0.03, 0.03 },
    contested = GetC("status", "warning") or { 0.90, 0.85, 0.05 },
    combat    = GetC("status", "error")   or { 0.84, 0.03, 0.03 },
    arena     = GetC("status", "error")   or { 0.84, 0.03, 0.03 },
}
local PVP_DEFAULT_COLOR = GetC("status", "warning") or { 0.90, 0.85, 0.05 }

local function GetZoneColor()
    local pvpType = GetZonePVPInfo and GetZonePVPInfo()
    local c = PVP_COLORS[pvpType] or PVP_DEFAULT_COLOR
    return c[1], c[2], c[3]
end

------------------------------------------------------------------------
-- 존 텍스트 업데이트 -- [ESSENTIAL]
------------------------------------------------------------------------
local function UpdateZoneText()
    if not MinimapSkin.zoneText then return end
    local text = GetMinimapZoneText()
    if text and #text > 46 then
        text = text:sub(1, 46) .. "..."
    end
    MinimapSkin.zoneText:SetText(text or "")
    MinimapSkin.zoneText:SetTextColor(GetZoneColor())
end

------------------------------------------------------------------------
-- 마우스 휠 줌 -- [ESSENTIAL]
------------------------------------------------------------------------
local function OnMouseWheel(_, delta)
    if not Minimap then return end
    local zoomIn  = Minimap.ZoomIn  or _G.MinimapZoomIn
    local zoomOut = Minimap.ZoomOut or _G.MinimapZoomOut
    if delta > 0 then
        if zoomIn and zoomIn.Click then zoomIn:Click() end
    elseif delta < 0 then
        if zoomOut and zoomOut.Click then zoomOut:Click() end
    end
end

------------------------------------------------------------------------
-- 마우스 Enter/Leave -- [ESSENTIAL]
------------------------------------------------------------------------
local function OnMinimapEnter()
    if MinimapSkin._ztBg then
        MinimapSkin._ztBg:Show()
        UpdateZoneText()
    end
end

local function OnMinimapLeave()
    if MinimapSkin._ztBg then
        MinimapSkin._ztBg:Hide()
    end
end

------------------------------------------------------------------------
-- 불필요한 프레임 숨기기 -- [ESSENTIAL]
------------------------------------------------------------------------
local function KillFrame(frame)
    if not frame then return end
    frame:Hide()
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
    if frame.SetAlpha then
        frame:SetAlpha(0)
    end
end

local function HideDefaultElements()
    local framesToKill = {
        _G.MinimapBorderTop,
        _G.MinimapBorder,
        _G.MiniMapWorldMapButton,
        _G.MinimapToggleButton,
        _G.MinimapNorthTag,
        _G.MiniMapMailBorder,
        Minimap and Minimap.ZoomIn,
        Minimap and Minimap.ZoomOut,
        _G.MinimapZoomIn,
        _G.MinimapZoomOut,
    }

    for _, f in ipairs(framesToKill) do
        KillFrame(f)
    end

    -- 나침반 텍스처 숨기기 -- [ESSENTIAL]
    if _G.MinimapCompassTexture then
        _G.MinimapCompassTexture:SetAlpha(0)
        _G.MinimapCompassTexture:Hide()
    end

    -- MinimapBackdrop 숨기기 -- [ESSENTIAL]
    if _G.MinimapBackdrop then
        _G.MinimapBackdrop:Hide()
    end

    -- MinimapCluster 텍스처 제거 -- [ESSENTIAL]
    if MinimapCluster then
        ns.StripTextures(MinimapCluster)
        if MinimapCluster.BorderTop then
            ns.StripTextures(MinimapCluster.BorderTop)
        end
        if MinimapCluster.Tracking and MinimapCluster.Tracking.Background then
            ns.StripTextures(MinimapCluster.Tracking.Background)
        end
        MinimapCluster:EnableMouse(false)
    end

    -- Zone 텍스트 버튼 숨기기 -- [ESSENTIAL]
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Hide()
        if MinimapCluster.ZoneTextButton.UnregisterAllEvents then
            MinimapCluster.ZoneTextButton:UnregisterAllEvents()
        end
    elseif _G.MinimapZoneTextButton then
        _G.MinimapZoneTextButton:Hide()
    end

    -- MiniMapTracking 배경 제거 -- [ESSENTIAL]
    if _G.MiniMapTracking then
        if _G.MiniMapTracking.Background then
            _G.MiniMapTracking.Background:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Blob Ring 제거 -- [ESSENTIAL]
------------------------------------------------------------------------
local function RemoveBlobRings()
    if not Minimap then return end
    if Minimap.SetArchBlobRingAlpha then Minimap:SetArchBlobRingAlpha(0) end
    if Minimap.SetArchBlobRingScalar then Minimap:SetArchBlobRingScalar(0) end
    if Minimap.SetQuestBlobRingAlpha then Minimap:SetQuestBlobRingAlpha(0) end
    if Minimap.SetQuestBlobRingScalar then Minimap:SetQuestBlobRingScalar(0) end
end

------------------------------------------------------------------------
-- 사각형 마스크 적용 -- [ESSENTIAL]
------------------------------------------------------------------------
local function ApplySquareMask()
    if not Minimap or not Minimap.SetMaskTexture then return end
    Minimap:SetMaskTexture(130937)
end

------------------------------------------------------------------------
-- 이너 섀도 오버레이 생성 (SakuriaUI 패턴) -- [ESSENTIAL]
------------------------------------------------------------------------
local function CreateInnerShadow(parent)
    local shadow = CreateFrame("Frame", nil, parent)
    shadow:SetFrameLevel(parent:GetFrameLevel() + 15)
    shadow:ClearAllPoints()
    shadow:SetAllPoints(parent)

    -- 상단 이너 섀도 (위에서 아래로 그라데이션) -- [ESSENTIAL]
    local top = shadow:CreateTexture(nil, "OVERLAY", nil, 7)
    top:SetTexture(FLAT)
    top:SetVertexColor(0, 0, 0, 0.4)
    top:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.4))
    top:SetHeight(12)
    SnapPoint(top, "TOPLEFT", shadow, "TOPLEFT", 0, 0)
    SnapPoint(top, "TOPRIGHT", shadow, "TOPRIGHT", 0, 0)

    -- 하단 이너 섀도 -- [ESSENTIAL]
    local bottom = shadow:CreateTexture(nil, "OVERLAY", nil, 7)
    bottom:SetTexture(FLAT)
    bottom:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.3), CreateColor(0, 0, 0, 0))
    bottom:SetHeight(8)
    SnapPoint(bottom, "BOTTOMLEFT", shadow, "BOTTOMLEFT", 0, 0)
    SnapPoint(bottom, "BOTTOMRIGHT", shadow, "BOTTOMRIGHT", 0, 0)

    return shadow
end

------------------------------------------------------------------------
-- Holder 프레임 생성 (SakuriaUI 스타일) -- [ESSENTIAL]
------------------------------------------------------------------------
local function CreateHolder()
    if MinimapSkin._holderCreated then return MinimapSkin.holder end

    local mmWidth  = Minimap:GetWidth()
    local mmHeight = Minimap:GetHeight()

    local holder = CreateFrame("Frame", "DDingEssentialMinimapHolder", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    SnapSize(holder, mmWidth + HOLDER_PAD * 2, mmHeight + HOLDER_PAD * 2)
    SnapPoint(holder, "TOPRIGHT", UIParent, "TOPRIGHT", -5, -5)
    holder:SetFrameStrata("BACKGROUND")
    holder:SetFrameLevel(0)

    -- 1px 검정 테두리 + 다크 배경 (SakuriaUI 패턴) -- [ESSENTIAL]
    holder:SetBackdrop({
        bgFile   = FLAT,
        edgeFile = FLAT,
        edgeSize = BORDER_SIZE,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    holder:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    holder:SetBackdropBorderColor(0, 0, 0, 1)

    -- 외곽 그림자 프레임 -- [ESSENTIAL]
    local shadowFrame = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
    shadowFrame:SetFrameLevel(math.max(0, holder:GetFrameLevel() - 1))
    shadowFrame:ClearAllPoints()
    SnapPoint(shadowFrame, "TOPLEFT", holder, "TOPLEFT", -SHADOW_SIZE, SHADOW_SIZE)
    SnapPoint(shadowFrame, "BOTTOMRIGHT", holder, "BOTTOMRIGHT", SHADOW_SIZE, -SHADOW_SIZE)
    shadowFrame:SetBackdrop({
        bgFile   = FLAT,
        edgeFile = FLAT,
        edgeSize = SHADOW_SIZE,
        insets   = { left = SHADOW_SIZE, right = SHADOW_SIZE, top = SHADOW_SIZE, bottom = SHADOW_SIZE },
    })
    shadowFrame:SetBackdropColor(0, 0, 0, 0)
    shadowFrame:SetBackdropBorderColor(0, 0, 0, 0.45)
    holder._shadow = shadowFrame

    -- Minimap을 holder에 배치 -- [ESSENTIAL]
    Minimap:ClearAllPoints()
    Minimap:SetParent(holder)
    SnapPoint(Minimap, "CENTER", holder, "CENTER", 0, 0)
    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(10)

    -- 이너 섀도 오버레이 -- [ESSENTIAL]
    MinimapSkin._innerShadow = CreateInnerShadow(Minimap)

    -- MinimapBackdrop 위치 동기화 -- [ESSENTIAL]
    if _G.MinimapBackdrop then
        _G.MinimapBackdrop:ClearAllPoints()
        _G.MinimapBackdrop:SetAllPoints(Minimap)
    end

    MinimapSkin.holder = holder
    MinimapSkin._holderCreated = true
    return holder
end

------------------------------------------------------------------------
-- 존 텍스트 오버레이 생성 (SakuriaUI 스타일) -- [ESSENTIAL]
------------------------------------------------------------------------
local function CreateZoneText()
    if MinimapSkin.zoneText then return end

    -- 존 텍스트 배경 바 (반투명 다크) -- [ESSENTIAL]
    local ztBg = CreateFrame("Frame", nil, Minimap)
    ztBg:SetFrameLevel(Minimap:GetFrameLevel() + 16)
    ztBg:SetHeight(18)
    ztBg:ClearAllPoints()
    SnapPoint(ztBg, "TOPLEFT", Minimap, "TOPLEFT", 0, 0)
    SnapPoint(ztBg, "TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)

    local ztBgTex = ztBg:CreateTexture(nil, "BACKGROUND")
    ztBgTex:SetTexture(FLAT)
    ztBgTex:SetVertexColor(0, 0, 0, 0.55)
    ztBgTex:SetAllPoints()
    ztBg:Hide()
    MinimapSkin._ztBg = ztBg

    local zt = ztBg:CreateFontString(nil, "OVERLAY")
    SnapPoint(zt, "CENTER", ztBg, "CENTER", 0, 0)
    zt:SetWidth(Minimap:GetWidth() - 10)
    zt:SetJustifyH("CENTER")
    zt:SetJustifyV("MIDDLE")
    zt:SetWordWrap(false)
    ns.SetFont(zt, F and F.small or 11, "OUTLINE")
    zt:SetShadowColor(0, 0, 0, 1)
    zt:SetShadowOffset(1, -1)

    MinimapSkin.zoneText = zt
end

------------------------------------------------------------------------
-- 시계 폰트 + 미니맵 하단 재배치 (SakuriaUI 스타일) -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinClock()
    local clockBtn = _G.TimeManagerClockButton
    if not clockBtn then return end

    ns.StripTextures(clockBtn)

    -- 시계를 미니맵 하단에 배치 -- [ESSENTIAL]
    clockBtn:ClearAllPoints()
    if MinimapSkin.holder then
        SnapPoint(clockBtn, "TOP", MinimapSkin.holder, "BOTTOM", 0, -2)
    else
        SnapPoint(clockBtn, "TOP", Minimap, "BOTTOM", 0, -4)
    end
    clockBtn:SetFrameStrata("LOW")
    clockBtn:SetFrameLevel(15)

    local text = clockBtn:GetFontString() or (clockBtn.GetRegions and select(1, clockBtn:GetRegions()))
    if text and text.SetFont then
        ns.SetFont(text, F and F.small or 11, "OUTLINE")
        local r, g, b = Unpack(GetC("text", "dim"), 0.55, 0.55, 0.55)
        text:SetTextColor(r, g, b)
        text:SetShadowColor(0, 0, 0, 0.8)
        text:SetShadowOffset(1, -1)
    end

    if _G.TimeManagerClockTicker and _G.TimeManagerClockTicker.SetFont then
        ns.SetFont(_G.TimeManagerClockTicker, F and F.small or 11, "OUTLINE")
        _G.TimeManagerClockTicker:SetShadowColor(0, 0, 0, 0.8)
        _G.TimeManagerClockTicker:SetShadowOffset(1, -1)
    end
end

------------------------------------------------------------------------
-- HybridMinimap 지원 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SetupHybridMinimap()
    local hybrid = _G.HybridMinimap
    if not hybrid then return end
    if hybrid.MapCanvas and hybrid.MapCanvas.SetMaskTexture then
        hybrid.MapCanvas:SetMaskTexture(130937)
    end
    if hybrid.CircleMask then
        ns.StripTextures(hybrid.CircleMask)
    end
    if hybrid.MapCanvas then
        hybrid.MapCanvas:SetScript("OnMouseWheel", OnMouseWheel)
    end
end

------------------------------------------------------------------------
-- GetMinimapShape 글로벌 훅 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SetMinimapShape()
    function GetMinimapShape()
        return "SQUARE"
    end
end

------------------------------------------------------------------------
-- 우클릭 마이크로 메뉴 (ElvUI 참조) -- [ESSENTIAL]
------------------------------------------------------------------------
local function CreateRightClickMenu()
    if MinimapSkin._menuCreated then return end
    MinimapSkin._menuCreated = true

    local menuFrame = CreateFrame("Frame", "DDingEssentialMinimapMenu", UIParent, "UIDropDownMenuTemplate")

    local menuItems = {
        { text = "|cffffd133DDingUI Essential|r", isTitle = true, notCheckable = true }, -- [ESSENTIAL-DESIGN]
        { text = " ", isTitle = true, notCheckable = true },
        { text = "설정 열기 (/des)", notCheckable = true, func = function()
            SlashCmdList["DDINGUIESSENTIAL"]()
        end },
        { text = " ", isTitle = true, notCheckable = true },
        { text = "게임 메뉴", isTitle = true, notCheckable = true },
        { text = "캐릭터 정보", notCheckable = true, func = function()
            ToggleCharacter("PaperDollFrame")
        end },
        { text = "주문서", notCheckable = true, func = function()
            if PlayerSpellsFrame then
                if PlayerSpellsFrame:IsShown() then
                    HideUIPanel(PlayerSpellsFrame)
                else
                    ShowUIPanel(PlayerSpellsFrame)
                end
            elseif ToggleSpellBook then
                ToggleSpellBook("spell")
            end
        end },
        { text = "특성", notCheckable = true, func = function()
            if ClassTalentFrame then
                if ClassTalentFrame:IsShown() then
                    HideUIPanel(ClassTalentFrame)
                else
                    ShowUIPanel(ClassTalentFrame)
                end
            elseif ToggleTalentFrame then
                ToggleTalentFrame()
            end
        end },
        { text = "업적", notCheckable = true, func = function()
            ToggleAchievementFrame()
        end },
        { text = "수집품", notCheckable = true, func = function()
            if CollectionsJournal then
                ToggleCollectionsJournal()
            end
        end },
        { text = "던전 찾기", notCheckable = true, func = function()
            if PVEFrame then
                ToggleLFDParentFrame()
            end
        end },
        { text = "모험 안내서", notCheckable = true, func = function()
            if EncounterJournal then
                ToggleEncounterJournal()
            end
        end },
        { text = " ", isTitle = true, notCheckable = true },
        { text = "닫기", notCheckable = true, func = function()
            CloseDropDownMenus()
        end },
    }

    -- HookScript: 블리자드 원본이 보안 컨텍스트에서 먼저 실행 (PingLocation 보호) -- [ESSENTIAL]
    Minimap:HookScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            EasyMenu(menuItems, menuFrame, "cursor", 0, 0, "MENU")
        elseif button == "MiddleButton" then
            -- 미니맵 추적 드롭다운 (블리자드 기본) -- [ESSENTIAL]
            if MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button then
                MinimapCluster.Tracking.Button:Click()
            end
        end
        -- 좌클릭: 원본 핸들러가 이미 PingLocation() 호출 완료 -- [ESSENTIAL]
    end)
end

------------------------------------------------------------------------
-- DDingUI 미니맵 버튼 생성 (SakuriaUI 스타일) -- [ESSENTIAL]
------------------------------------------------------------------------
local function CreateMinimapButton()
    if MinimapSkin._buttonCreated then return end
    MinimapSkin._buttonCreated = true

    local btnSize = 22
    local aR, aG, aB = 1.00, 0.82, 0.20 -- [ESSENTIAL-DESIGN] Essential accent 노란색
    if accentFrom then aR, aG, aB = accentFrom[1], accentFrom[2], accentFrom[3] end

    local btn = CreateFrame("Button", "DDingUIEssentialMinimapButton", Minimap,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    SnapSize(btn, btnSize, btnSize)
    SnapPoint(btn, "BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -3, 3)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(25)

    -- 1px 검정 테두리 + 다크 배경 (holder와 통일) -- [STYLE]
    btn:SetBackdrop({
        bgFile   = FLAT,
        edgeFile = FLAT,
        edgeSize = BORDER_SIZE,
    })
    local bgR, bgG, bgB = Unpack(GetC("bg", "sidebar"), 0.08, 0.08, 0.08)
    btn:SetBackdropColor(bgR, bgG, bgB, 0.92)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    -- 악센트 하단 라인 (2px, 악센트 색상) -- [STYLE]
    local accentLine = btn:CreateTexture(nil, "OVERLAY")
    accentLine:SetTexture(FLAT)
    accentLine:SetVertexColor(aR, aG, aB, 0.8)
    accentLine:SetHeight(1)
    SnapPoint(accentLine, "BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
    SnapPoint(accentLine, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn._accentLine = accentLine

    -- "D" 아이콘 -- [ESSENTIAL]
    local icon = btn:CreateFontString(nil, "OVERLAY")
    icon:SetFont(SL_FONT, F and F.small or 11, "OUTLINE") -- [STYLE]
    icon:SetPoint("CENTER", 0, 1)
    icon:SetText("D")
    icon:SetTextColor(aR, aG, aB, 1)
    icon:SetShadowColor(0, 0, 0, 0.8)
    icon:SetShadowOffset(1, -1)
    btn._icon = icon

    -- 호버 효과 (악센트 글로우) -- [ESSENTIAL]
    btn:SetScript("OnEnter", function(self)
        local hv = (C and C.bg and C.bg.hover) or { 0.20, 0.20, 0.20, 0.60 }
        self:SetBackdropColor(hv[1], hv[2], hv[3], hv[4] or 0.95)
        self:SetBackdropBorderColor(aR * 0.5, aG * 0.5, aB * 0.5, 0.8)
        self._accentLine:SetVertexColor(aR, aG, aB, 1)
        self._icon:SetTextColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("DDingUI Essential", aR, aG, aB)
        GameTooltip:AddLine("좌클릭: 설정 열기", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("우클릭: 마이크로 메뉴", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(bgR, bgG, bgB, 0.92)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        self._accentLine:SetVertexColor(aR, aG, aB, 0.8)
        self._icon:SetTextColor(aR, aG, aB, 1)
        GameTooltip:Hide()
    end)

    -- 클릭 -- [ESSENTIAL]
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            SlashCmdList["DDINGUIESSENTIAL"]()
        elseif button == "RightButton" then
            local onMouseUp = Minimap:GetScript("OnMouseUp")
            if onMouseUp then onMouseUp(Minimap, "RightButton") end
        end
    end)

    MinimapSkin.minimapButton = btn
end

------------------------------------------------------------------------
-- 좌표 + MS/FPS 오버레이 -- [ESSENTIAL]
------------------------------------------------------------------------
local coordFrame, coordText, perfText

local function CreateInfoOverlay()
    local db = ns.db and ns.db.minimap or {}

    -- 공통 배경 프레임 (미니맵 하단)
    coordFrame = CreateFrame("Frame", nil, Minimap)
    coordFrame:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 0, 0)
    coordFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
    coordFrame:SetHeight(16)
    coordFrame:SetFrameLevel(Minimap:GetFrameLevel() + 3)

    -- 반투명 배경
    local bg = coordFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local cbg = (C and C.bg and C.bg.sidebar) or { 0.08, 0.08, 0.08, 0.95 }
    bg:SetColorTexture(cbg[1], cbg[2], cbg[3], 0.5) -- [STYLE]

    local fontPath = SL_FONT
    local fontSize = F and F.small or 11 -- [STYLE]
    local textColor = (C and C.text and C.text.normal) or { 0.85, 0.85, 0.85, 1 }

    -- 좌표 텍스트 (좌측) -- [ESSENTIAL]
    local coordDB = db.coordinates
    if not coordDB or coordDB.enabled ~= false then
        coordText = coordFrame:CreateFontString(nil, "OVERLAY")
        coordText:SetFont(fontPath, fontSize, "OUTLINE")
        coordText:SetPoint("LEFT", coordFrame, "LEFT", 4, 0)
        coordText:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
        coordText:SetText("0.0, 0.0")
    end

    -- MS/FPS 텍스트 (우측) -- [ESSENTIAL]
    local perfDB = db.performanceInfo
    if not perfDB or perfDB.enabled ~= false then
        perfText = coordFrame:CreateFontString(nil, "OVERLAY")
        perfText:SetFont(fontPath, fontSize, "OUTLINE")
        perfText:SetPoint("RIGHT", coordFrame, "RIGHT", -4, 0)
        perfText:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
        perfText:SetText("0ms | 0fps")
    end

    MinimapSkin.coordFrame = coordFrame
end

local function UpdateCoordinates()
    if not coordText then return end
    local db = ns.db and ns.db.minimap
    local coordDB = db and db.coordinates
    if coordDB and coordDB.enabled == false then
        coordText:SetText("")
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        coordText:SetText("")
        return
    end

    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        coordText:SetText("")
        return
    end

    local x, y = pos:GetXY()
    if x and y then
        local fmt = (coordDB and coordDB.format) or "%.1f"
        coordText:SetText(format(fmt .. ", " .. fmt, x * 100, y * 100))
    else
        coordText:SetText("")
    end
end

local function UpdatePerformance()
    if not perfText then return end
    local db = ns.db and ns.db.minimap
    local perfDB = db and db.performanceInfo
    if perfDB and perfDB.enabled == false then
        perfText:SetText("")
        return
    end

    local showMS = not perfDB or perfDB.showMS ~= false
    local showFPS = not perfDB or perfDB.showFPS ~= false

    local parts = {}

    if showMS then
        local _, _, _, worldMS = GetNetStats()
        worldMS = math.floor(worldMS + 0.5)
        -- StyleLib status 색상 기반 -- [STYLE]
        local msColor
        local sOk  = (C and C.status and C.status.success) or { 0.30, 0.80, 0.30 }
        local sWrn = (C and C.status and C.status.warning) or { 0.90, 0.75, 0.20 }
        local sErr = (C and C.status and C.status.error)   or { 0.90, 0.25, 0.25 }
        if worldMS < 50 then
            msColor = string.format("|cff%02x%02x%02x", math.floor(sOk[1]*255+0.5), math.floor(sOk[2]*255+0.5), math.floor(sOk[3]*255+0.5))
        elseif worldMS < 100 then
            msColor = string.format("|cff%02x%02x%02x", math.floor(sWrn[1]*255+0.5), math.floor(sWrn[2]*255+0.5), math.floor(sWrn[3]*255+0.5))
        else
            msColor = string.format("|cff%02x%02x%02x", math.floor(sErr[1]*255+0.5), math.floor(sErr[2]*255+0.5), math.floor(sErr[3]*255+0.5))
        end
        parts[#parts + 1] = msColor .. worldMS .. "ms|r"
    end

    if showFPS then
        local fps = math.floor(GetFramerate() + 0.5)
        parts[#parts + 1] = fps .. "fps"
    end

    perfText:SetText(table.concat(parts, " | "))
end

local coordTimer, perfTimer

local function StartInfoTimers()
    local db = ns.db and ns.db.minimap or {}

    -- 좌표 타이머 -- [ESSENTIAL]
    local coordDB = db.coordinates
    if coordText and (not coordDB or coordDB.enabled ~= false) then
        local interval = (coordDB and coordDB.updateInterval) or 0.5
        coordTimer = C_Timer.NewTicker(interval, UpdateCoordinates)
        UpdateCoordinates()
    end

    -- 성능 정보 타이머 -- [ESSENTIAL]
    local perfDB = db.performanceInfo
    if perfText and (not perfDB or perfDB.enabled ~= false) then
        local interval = (perfDB and perfDB.updateInterval) or 1
        perfTimer = C_Timer.NewTicker(interval, UpdatePerformance)
        UpdatePerformance()
    end
end

------------------------------------------------------------------------
-- 동적 크기 업데이트 (Config에서 호출) -- [ESSENTIAL]
------------------------------------------------------------------------
function MinimapSkin:UpdateSize(newSize)
    if not Minimap or not newSize then return end
    SnapSize(Minimap, newSize, newSize)
    if self.holder then
        SnapSize(self.holder, newSize + HOLDER_PAD * 2, newSize + HOLDER_PAD * 2)
        if self.holder._shadow then
            self.holder._shadow:ClearAllPoints()
            SnapPoint(self.holder._shadow, "TOPLEFT", self.holder, "TOPLEFT", -SHADOW_SIZE, SHADOW_SIZE)
            SnapPoint(self.holder._shadow, "BOTTOMRIGHT", self.holder, "BOTTOMRIGHT", SHADOW_SIZE, -SHADOW_SIZE)
        end
    end
end

------------------------------------------------------------------------
-- 이벤트 프레임 -- [ESSENTIAL]
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(_, event, arg1)
    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        UpdateZoneText()
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TimeManager" then
            SkinClock()
        elseif arg1 == "Blizzard_HybridMinimap" then
            SetupHybridMinimap()
        end
    end
end

------------------------------------------------------------------------
-- Enable -- [ESSENTIAL]
------------------------------------------------------------------------
function MinimapSkin:Enable()
    if self._deSkinned then return end

    if not Minimap then
        local _pfx = SL and SL.GetChatPrefix and SL.GetChatPrefix("Essential", "Essential") or "|cffffffffDDing|r|cffffa300UI|r |cffffd133Essential|r: " -- [STYLE]
        print(_pfx .. "|cffff0000Minimap 프레임을 찾을 수 없습니다.|r")
        return
    end

    -- StyleLib 재확인 -- [ESSENTIAL]
    if not SL then
        SL = _G.DDingUI_StyleLib
        C = SL and SL.Colors
        F = SL and SL.Font
    end

    -- 악센트 캐시 -- [ESSENTIAL]
    if SL and SL.GetAccent then
        local from, to = SL.GetAccent("Essential")
        accentFrom = from
        accentTo = to
    end

    -- DB 설정 읽기 -- [ESSENTIAL]
    local db = ns.db and ns.db.minimap or {}

    -- 1. 사각형 마스크 -- [ESSENTIAL]
    ApplySquareMask()

    -- 2. 기본 UI 숨기기 -- [ESSENTIAL]
    HideDefaultElements()

    -- 3. Blob Ring 제거 -- [ESSENTIAL]
    RemoveBlobRings()

    -- 4. Holder 프레임 + StyleLib 테두리 -- [ESSENTIAL]
    CreateHolder()

    -- 5. 미니맵 크기 적용 (픽셀퍼펙트) -- [ESSENTIAL]
    local mmSize = db.size or 180
    SnapSize(Minimap, mmSize, mmSize)
    if MinimapSkin.holder then
        SnapSize(MinimapSkin.holder, mmSize + HOLDER_PAD * 2, mmSize + HOLDER_PAD * 2)
        -- 그림자도 크기 동기화 -- [ESSENTIAL]
        if MinimapSkin.holder._shadow then
            MinimapSkin.holder._shadow:ClearAllPoints()
            SnapPoint(MinimapSkin.holder._shadow, "TOPLEFT", MinimapSkin.holder, "TOPLEFT", -SHADOW_SIZE, SHADOW_SIZE)
            SnapPoint(MinimapSkin.holder._shadow, "BOTTOMRIGHT", MinimapSkin.holder, "BOTTOMRIGHT", SHADOW_SIZE, -SHADOW_SIZE)
        end
    end

    -- 6. 마우스 휠 줌 -- [ESSENTIAL]
    if db.mouseWheel ~= false then
        Minimap:EnableMouseWheel(true)
        Minimap:SetScript("OnMouseWheel", OnMouseWheel)
    end

    -- 7. 마우스오버 존 텍스트 -- [ESSENTIAL]
    if db.zoneText ~= false then
        CreateZoneText()
        Minimap:HookScript("OnEnter", OnMinimapEnter)
        Minimap:HookScript("OnLeave", OnMinimapLeave)
    end

    -- 8. 시계 폰트 -- [ESSENTIAL]
    if db.clock ~= false and _G.TimeManagerClockButton then
        SkinClock()
    end

    -- 9. HybridMinimap -- [ESSENTIAL]
    if _G.HybridMinimap then
        SetupHybridMinimap()
    end

    -- 10. GetMinimapShape 오버라이드 -- [ESSENTIAL]
    SetMinimapShape()

    -- 11. 우클릭 마이크로 메뉴 -- [ESSENTIAL]
    CreateRightClickMenu()

    -- 12. DDingUI 미니맵 버튼 -- [ESSENTIAL]
    CreateMinimapButton()

    -- 13. 이벤트 등록 -- [ESSENTIAL]
    eventFrame:RegisterEvent("ZONE_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:SetScript("OnEvent", OnEvent)

    -- 14. 초기 존 텍스트 업데이트 -- [ESSENTIAL]
    if db.zoneText ~= false then
        UpdateZoneText()
    end

    -- 15. 좌표 + MS/FPS 오버레이 -- [ESSENTIAL]
    CreateInfoOverlay()
    StartInfoTimers()

    self._deSkinned = true
end

------------------------------------------------------------------------
-- Disable -- [ESSENTIAL]
------------------------------------------------------------------------
function MinimapSkin:Disable()
    eventFrame:UnregisterAllEvents()
    if coordTimer then coordTimer:Cancel() coordTimer = nil end
    if perfTimer then perfTimer:Cancel() perfTimer = nil end
end

------------------------------------------------------------------------
-- 등록 -- [ESSENTIAL]
------------------------------------------------------------------------
ns:RegisterModule("minimap", MinimapSkin)
