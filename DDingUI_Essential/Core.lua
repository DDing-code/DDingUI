-- DDingUI_Essential Core -- [ESSENTIAL]
-- 블리자드 기본 UI 스킨 애드온 (미니맵, 채팅, 버프, 퀘스트추적기, 데미지미터, 행동단축바)

local addonName, ns = ...

------------------------------------------------------------------------
-- StyleLib 로드 -- [ESSENTIAL]
------------------------------------------------------------------------
local SL = _G.DDingUI_StyleLib
local FLAT  = SL and SL.Textures and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local FONT  = SL and SL.Font and SL.Font.path or "Fonts\\2002.TTF"
local FONT_DEFAULT = SL and SL.Font and SL.Font.default or "Fonts\\FRIZQT__.TTF"

ns.SL   = SL
ns.FLAT = FLAT
ns.FONT = FONT
ns.FONT_DEFAULT = FONT_DEFAULT

------------------------------------------------------------------------
-- 색상 헬퍼 -- [ESSENTIAL]
------------------------------------------------------------------------
ns.GetColor = function(path)
    -- path: "bg.main", "border.default", "text.normal" 등
    if not SL or not SL.Colors then return 0.1, 0.1, 0.1, 0.9 end
    local parts = {strsplit(".", path)}
    local t = SL.Colors
    for _, key in ipairs(parts) do
        t = t[key]
        if not t then return 0.1, 0.1, 0.1, 0.9 end
    end
    if type(t) == "table" then
        return t[1] or 0.1, t[2] or 0.1, t[3] or 0.1, t[4] or 1
    end
    return 0.1, 0.1, 0.1, 0.9
end

ns.GetColorTable = function(path)
    local r, g, b, a = ns.GetColor(path)
    return {r, g, b, a}
end

------------------------------------------------------------------------
-- 유틸리티 -- [ESSENTIAL]
------------------------------------------------------------------------
function ns.CreateBackdrop(frame, bgColor, borderColor)
    if not frame then return end

    -- ★ BackdropTemplate 강제 주입 (12.x 핵심 — ElvUI Toolkit.lua:252 패턴) -- [ESSENTIAL]
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
        if frame.OnBackdropSizeChanged then
            frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
        end
    end

    local bg = bgColor or {ns.GetColor("bg.main")}
    local bd = borderColor or {ns.GetColor("border.default")}

    frame:SetBackdrop({
        bgFile   = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.9)
    frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1)
end

-- ElvUI + BFI 통합 StripTextures 패턴: 재귀적 하위 프레임 텍스처 제거 -- [ESSENTIAL]
local STRIP_SUBFRAMES = {
    "Inset", "inset", "InsetFrame", "LeftInset", "RightInset",
    "NineSlice", "BG", "Bg", "border", "Border", "Background",
    "BorderFrame", "bottomInset", "BottomInset", "bgLeft", "bgRight",
    "FilligreeOverlay", "PortraitOverlay", "ArtOverlayFrame",
    "Portrait", "portrait", "ScrollFrameBorder",
    "ScrollUpBorder", "ScrollDownBorder",       -- ElvUI 추가분
    "PortraitContainer", "TopTileStreaks",       -- BFI에서 발견: 12.x 핵심 요소
    "ClassBackground",                           -- BFI: 직업 배경 텍스처
}

function ns.StripTextures(frame, killRegions)
    if not frame or not frame.GetRegions then return end
    for _, region in next, { frame:GetRegions() } do
        if region and region.IsObjectType then
            if region:IsObjectType("Texture") then
                -- ★ SetAlpha(0) 사용: Hide() 대신 — 블리자드 Show() 호출 방지 -- [ESSENTIAL]
                region:SetAlpha(0)
                region:SetTexture("")   -- 빈 문자열 = ElvUI ClearTexture 패턴
                if region.SetAtlas then region:SetAtlas("") end
            end
        end
    end

    -- ★ NineSlice 명시적 처리 (BFI 핵심 — 12.x 대부분의 프레임이 NineSlice 사용) -- [ESSENTIAL]
    if frame.NineSlice then
        frame.NineSlice:SetAlpha(0)
    end

    -- 재귀: 알려진 하위 프레임도 텍스처 제거 -- [ESSENTIAL]
    local frameName = frame.GetName and frame:GetName()
    for _, name in next, STRIP_SUBFRAMES do
        local child = frame[name] or (frameName and _G[frameName..name])
        if child and type(child) == "table" then
            if child.SetAlpha then
                child:SetAlpha(0)   -- 하위 프레임 자체를 숨기기 (BFI 패턴)
            end
            if child.GetRegions then
                ns.StripTextures(child, killRegions)
            end
        end
    end
end

function ns.SetFont(fontString, size, flags)
    if not fontString or not fontString.SetFont then return end
    fontString:SetFont(FONT, size or 12, flags or "")
end

--- 프레임에 1px StyleLib 테두리를 생성 (백드롭과 별개)
function ns.CreateBorder(frame, color)
    if not frame or frame._deBorder then return frame._deBorder end
    local bd = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bd:SetAllPoints()
    bd:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
    bd:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    local r, g, b, a
    if color then
        r, g, b, a = color[1], color[2], color[3], color[4]
    else
        r, g, b, a = ns.GetColor("border.default")
    end
    bd:SetBackdropBorderColor(r, g, b, a or 1)
    frame._deBorder = bd
    return bd
end

------------------------------------------------------------------------
-- 범용 핸들러 (목업 디자인 완벽 구현) -- [ESSENTIAL]
------------------------------------------------------------------------

-- 내부: 클래스 컬러 캐시 -- [ESSENTIAL]
local _classColor
local function GetClassColor()
    if not _classColor then
        local classFile = select(2, UnitClass("player"))
        local c = RAID_CLASS_COLORS[classFile]
        _classColor = c and {c.r, c.g, c.b} or {1, 0.82, 0.20}
    end
    return _classColor
end

--- 버튼 스킨: BFI StyleButton 패턴 기반 — 호버/눌림/활성/비활성 전체 상태 -- [ESSENTIAL]
function ns.HandleButton(btn, strip)
    if not btn or btn._ddeSkinned then return end
    btn._ddeSkinned = true

    -- ★ 블리자드 텍스처 완전 제거 (BFI: RemoveTextures + SetXxxTexture) -- [ESSENTIAL]
    if strip ~= false then ns.StripTextures(btn) end
    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end

    -- 버튼 배경: 미묘한 그라데이션 (상단 약간 밝음) -- [ESSENTIAL]
    local bgTop = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgTop:SetTexture(FLAT)
    bgTop:SetPoint("TOPLEFT")
    bgTop:SetPoint("RIGHT")
    bgTop:SetHeight(math.max(1, btn:GetHeight() * 0.5))
    bgTop:SetVertexColor(0.16, 0.16, 0.16, 0.95)

    local bgBot = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgBot:SetTexture(FLAT)
    bgBot:SetPoint("BOTTOMLEFT")
    bgBot:SetPoint("RIGHT")
    bgBot:SetHeight(math.max(1, btn:GetHeight() * 0.5))
    bgBot:SetVertexColor(0.10, 0.10, 0.10, 0.95)

    -- 1px 테두리 -- [ESSENTIAL]
    ns.CreateBorder(btn)

    -- 폰트: StyleLib 폰트 + 자연스러운 색상 -- [ESSENTIAL]
    local text = btn.Text or (btn.GetFontString and btn:GetFontString())
    if text and text.SetFont then
        ns.SetFont(text, (SL and SL.Font and SL.Font.normal) or 13, "")
        text:SetTextColor(0.85, 0.85, 0.85, 1)
    end

    -- 호버: 클래스 컬러 보더 + 텍스트 밝아짐 -- [ESSENTIAL]
    btn:HookScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        local cc = GetClassColor()
        if self._deBorder then
            self._deBorder:SetBackdropBorderColor(cc[1], cc[2], cc[3], 0.9)
        end
        local t = self.Text or (self.GetFontString and self:GetFontString())
        if t then t:SetTextColor(1, 1, 1, 1) end
    end)
    btn:HookScript("OnLeave", function(self)
        if not self:IsEnabled() then return end
        if self._deBorder then
            local r, g, b, a = ns.GetColor("border.default")
            self._deBorder:SetBackdropBorderColor(r, g, b, a or 1)
        end
        local t = self.Text or (self.GetFontString and self:GetFontString())
        if t then t:SetTextColor(0.85, 0.85, 0.85, 1) end
    end)

    -- 눌림: 배경 어둡게 -- [ESSENTIAL]
    btn:HookScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        bgTop:SetVertexColor(0.08, 0.08, 0.08, 0.95)
        bgBot:SetVertexColor(0.06, 0.06, 0.06, 0.95)
    end)
    btn:HookScript("OnMouseUp", function(self)
        bgTop:SetVertexColor(0.16, 0.16, 0.16, 0.95)
        bgBot:SetVertexColor(0.10, 0.10, 0.10, 0.95)
    end)

    -- ★ 활성/비활성 상태 (BFI OnEnable/OnDisable 패턴) -- [ESSENTIAL]
    btn:HookScript("OnEnable", function(self)
        local t = self.Text or (self.GetFontString and self:GetFontString())
        if t then t:SetTextColor(0.85, 0.85, 0.85, 1) end
        bgTop:SetVertexColor(0.16, 0.16, 0.16, 0.95)
        bgBot:SetVertexColor(0.10, 0.10, 0.10, 0.95)
    end)
    btn:HookScript("OnDisable", function(self)
        local t = self.Text or (self.GetFontString and self:GetFontString())
        if t then t:SetTextColor(0.40, 0.40, 0.40, 1) end
        bgTop:SetVertexColor(0.10, 0.10, 0.10, 0.95)
        bgBot:SetVertexColor(0.08, 0.08, 0.08, 0.95)
    end)
end

--- 닫기 버튼: BFI StyleCloseButton — 큰 히트영역 + 호버 빨간 효과 -- [ESSENTIAL]
function ns.HandleCloseButton(btn)
    if not btn or btn._ddeSkinned then return end
    btn._ddeSkinned = true

    ns.StripTextures(btn)
    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end

    btn:SetSize(20, 20)

    -- 1px 테두리 (BFI 패턴: 닫기 버튼도 보더 있음) -- [ESSENTIAL]
    ns.CreateBorder(btn)

    -- 빨간 호버 배경 -- [ESSENTIAL]
    local hoverBG = btn:CreateTexture(nil, "BACKGROUND")
    hoverBG:SetTexture(FLAT)
    hoverBG:SetAllPoints()
    hoverBG:SetVertexColor(0.85, 0.20, 0.20, 0)
    btn._ddeHoverBG = hoverBG

    -- "✕" 라벨 -- [ESSENTIAL]
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 14, "OUTLINE")
    label:SetPoint("CENTER", 0, 0)
    label:SetText("✕")
    label:SetTextColor(0.55, 0.55, 0.55, 1)
    btn._ddeLabel = label

    btn:HookScript("OnEnter", function(self)
        if self._ddeLabel then self._ddeLabel:SetTextColor(1, 1, 1, 1) end
        if self._ddeHoverBG then self._ddeHoverBG:SetVertexColor(0.85, 0.20, 0.20, 0.85) end
        if self._deBorder then self._deBorder:SetBackdropBorderColor(0.85, 0.20, 0.20, 0.8) end
    end)
    btn:HookScript("OnLeave", function(self)
        if self._ddeLabel then self._ddeLabel:SetTextColor(0.55, 0.55, 0.55, 1) end
        if self._ddeHoverBG then self._ddeHoverBG:SetVertexColor(0.85, 0.20, 0.20, 0) end
        if self._deBorder then
            local r, g, b, a = ns.GetColor("border.default")
            self._deBorder:SetBackdropBorderColor(r, g, b, a or 1)
        end
    end)
end

--- 에디트박스: BFI StyleEditBox 패턴 — RemoveRegions + NineSlice + 포커스 글로우 -- [ESSENTIAL]
function ns.HandleEditBox(editBox)
    if not editBox or editBox._ddeSkinned then return end
    editBox._ddeSkinned = true

    ns.StripTextures(editBox)

    -- BFI RemoveRegions 패턴: EditBox 특유의 Left/Mid/Right 서브프레임 제거 -- [ESSENTIAL]
    local editName = editBox.GetName and editBox:GetName()
    local regionParts = {
        "Left", "FocusLeft", "Right", "FocusRight",
        "Center", "Mid", "Middle", "FocusMid",
    }
    for _, part in next, regionParts do
        local r = editBox[part] or (editName and _G[editName..part])
        if r and r.SetAlpha then
            r:SetAlpha(0)
            if r.Hide then r:Hide() end
        end
    end

    -- NineSlice 명시적 제거 -- [ESSENTIAL]
    if editBox.NineSlice then editBox.NineSlice:SetAlpha(0) end

    -- 다크 배경 -- [ESSENTIAL]
    local bg = editBox:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(FLAT)
    bg:SetVertexColor(ns.GetColor("bg.input"))

    -- 1px 테두리 -- [ESSENTIAL]
    ns.CreateBorder(editBox)

    -- 폰트 -- [ESSENTIAL]
    ns.SetFont(editBox, (SL and SL.Font and SL.Font.normal) or 13, "")

    -- 포커스 효과: 클래스 컬러 보더 -- [ESSENTIAL]
    editBox:HookScript("OnEditFocusGained", function(self)
        if self._deBorder then
            local cc = GetClassColor()
            self._deBorder:SetBackdropBorderColor(cc[1], cc[2], cc[3], 0.8)
        end
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        if self._deBorder then
            local r, g, b, a = ns.GetColor("border.default")
            self._deBorder:SetBackdropBorderColor(r, g, b, a or 1)
        end
    end)
end

--- 탭 스킨: BFI StyleTab 패턴 — 배경 + 선택 인디케이터 + 호버 -- [ESSENTIAL]
function ns.HandleTab(tab)
    if not tab or tab._ddeSkinned then return end
    tab._ddeSkinned = true

    ns.StripTextures(tab)

    -- 탭 배경 (BFI: CreateBackdrop 패턴) -- [ESSENTIAL]
    ns.CreateBackdrop(tab, {0.10, 0.10, 0.10, 0.85}, {0.18, 0.18, 0.18, 0.5})

    -- 폰트 -- [ESSENTIAL]
    local text = tab.Text or tab:GetFontString()
    if text then
        ns.SetFont(text, (SL and SL.Font and SL.Font.normal) or 13, "")
        text:SetTextColor(0.65, 0.65, 0.65, 1)
        -- 텍스트 센터 고정 (BFI PanelTemplates_SelectTab 패턴) -- [ESSENTIAL]
        text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end

    -- 하단 선택 인디케이터 (2px 클래스 컬러) -- [ESSENTIAL]
    local cc = GetClassColor()
    local indicator = tab:CreateTexture(nil, "OVERLAY")
    indicator:SetTexture(FLAT)
    indicator:SetHeight(2)
    indicator:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 1, 0)
    indicator:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 0)
    indicator:SetVertexColor(cc[1], cc[2], cc[3], 0)  -- 기본 숨김
    tab._ddeIndicator = indicator

    -- 호버 -- [ESSENTIAL]
    tab:HookScript("OnEnter", function(self)
        local t = self.Text or self:GetFontString()
        if t and not self._ddeSelected then t:SetTextColor(1, 1, 1, 1) end
    end)
    tab:HookScript("OnLeave", function(self)
        local t = self.Text or self:GetFontString()
        if t and not self._ddeSelected then t:SetTextColor(0.65, 0.65, 0.65, 1) end
    end)
end

-- ★ PanelTemplates_UpdateTabs 후킹 (BFI 핵심 — 탭 선택 상태 시각 동기화) -- [ESSENTIAL]
do
    local function GetTabByIndex(frame, index)
        return (frame.Tabs and frame.Tabs[index])
            or _G[(frame:GetName() or "").."Tab"..index]
    end

    local function UpdateTabVisuals(frame)
        if not frame.selectedTab then return end
        for i = 1, (frame.numTabs or 0) do
            local tab = GetTabByIndex(frame, i)
            if tab and tab._ddeSkinned then
                local cc = GetClassColor()
                if i == frame.selectedTab then
                    -- 선택된 탭 -- [ESSENTIAL]
                    tab._ddeSelected = true
                    if tab._ddeIndicator then
                        tab._ddeIndicator:SetVertexColor(cc[1], cc[2], cc[3], 1)
                    end
                    local t = tab.Text or tab:GetFontString()
                    if t then t:SetTextColor(1, 1, 1, 1) end
                else
                    -- 비선택 탭 -- [ESSENTIAL]
                    tab._ddeSelected = false
                    if tab._ddeIndicator then
                        tab._ddeIndicator:SetVertexColor(0, 0, 0, 0)
                    end
                    local t = tab.Text or tab:GetFontString()
                    if t then t:SetTextColor(0.65, 0.65, 0.65, 1) end
                end
            end
        end
    end

    if _G.PanelTemplates_UpdateTabs then
        hooksecurefunc("PanelTemplates_UpdateTabs", UpdateTabVisuals)
    end
end

--- 프레임 스킨: BFI StyleTitledFrame 패턴 기반 완전 리팩토링 -- [ESSENTIAL]
function ns.HandleFrame(frame, template)
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true

    local name = frame.GetName and frame:GetName()

    -- ★ Step 1: 블리자드 요소 완전 제거 (BFI RemoveNineSliceAndBackground 패턴) -- [ESSENTIAL]
    ns.StripTextures(frame)

    -- NineSlice 명시적 처리 (StripTextures에서도 하지만 확실하게) -- [ESSENTIAL]
    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end

    -- PortraitContainer 숨기기 (BFI 핵심 — Portrait 아닌 PortraitContainer!) -- [ESSENTIAL]
    if frame.PortraitContainer then frame.PortraitContainer:SetAlpha(0) end

    -- Portrait 숨기기 (기존 패턴 유지) -- [ESSENTIAL]
    local portrait = frame.Portrait or frame.portrait or (name and _G[name.."Portrait"])
    local portraitOverlay = frame.PortraitOverlay or (name and _G[name.."PortraitOverlay"])
    local artOverlay = frame.ArtOverlayFrame or (name and _G[name.."ArtOverlayFrame"])
    if portrait then portrait:SetAlpha(0) end
    if portraitOverlay then portraitOverlay:SetAlpha(0) end
    if artOverlay then artOverlay:SetAlpha(0) end

    -- TopTileStreaks (타이틀 장식선) -- [ESSENTIAL]
    if frame.TopTileStreaks then frame.TopTileStreaks:SetAlpha(0) end

    -- Inset 처리 -- [ESSENTIAL]
    local inset = frame.Inset or (name and _G[name.."Inset"])
    if inset then ns.StripTextures(inset) end

    -- ★ Step 2: 메인 백드롭 — 진한 다크 + 은은한 테두리 -- [ESSENTIAL]
    ns.CreateBackdrop(frame, {0.08, 0.08, 0.08, 0.97}, {0.18, 0.18, 0.18, 0.7})

    -- ★ Step 3: 타이틀바 (26px) — BFI BFIHeader 패턴 -- [ESSENTIAL]
    local titleBar = frame:CreateTexture(nil, "ARTWORK", nil, -6)
    titleBar:SetTexture(FLAT)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(26)
    titleBar:SetVertexColor(0.14, 0.14, 0.14, 1)

    -- 타이틀바 하단 구분선 (1px) -- [ESSENTIAL]
    local sep = frame:CreateTexture(nil, "ARTWORK", nil, -5)
    sep:SetTexture(FLAT)
    sep:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetVertexColor(0.22, 0.22, 0.22, 0.8)

    -- ★ Step 4: 클래스 컬러 악센트 라인 (최상단 2px) -- [ESSENTIAL]
    local cc = GetClassColor()
    local accent = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    accent:SetTexture(FLAT)
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    accent:SetVertexColor(cc[1], cc[2], cc[3], 1)

    -- ★ Step 5: 타이틀 텍스트 — 센터 앵커 (BFI 패턴) -- [ESSENTIAL]
    local titleText
    if frame.TitleContainer and frame.TitleContainer.TitleText then
        titleText = frame.TitleContainer.TitleText
    elseif frame.TitleText then
        titleText = frame.TitleText
    elseif name then
        titleText = _G[name.."TitleText"]
    end
    if titleText and titleText.SetFont then
        titleText:SetFont(FONT, (SL and SL.Font and SL.Font.title) or 14, "")
        titleText:SetTextColor(0.90, 0.90, 0.90, 1)
        -- 타이틀을 헤더 센터에 앵커 -- [ESSENTIAL]
        titleText:ClearAllPoints()
        titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    end

    -- Header (ESC 메뉴 등 헤더 배너) -- [ESSENTIAL]
    local header = frame.Header
    if header then
        ns.StripTextures(header)
        header:ClearAllPoints()
        header:SetPoint("TOP", frame, "TOP", 0, 7)
    end

    -- ★ Step 6: CloseButton — 위치 재설정 (BFI 패턴) -- [ESSENTIAL]
    local closeBtn = frame.CloseButton or (name and _G[name.."CloseButton"])
    if closeBtn then
        ns.HandleCloseButton(closeBtn)
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -4)
    end

    -- ★ Step 7: 탭 자동 스킨 — frame.Tabs[i] 신규 패턴 포함 -- [ESSENTIAL]
    if frame.Tabs then
        for i, tab in ipairs(frame.Tabs) do
            ns.HandleTab(tab)
        end
    end
    for i = 1, 10 do
        local tab = (name and _G[name.."Tab"..i]) or frame["Tab"..i]
        if tab and not tab._ddeSkinned then ns.HandleTab(tab) end
    end
end

--- StatusBar 진행바 색상 그라데이션 (빨강→노랑→초록)
function ns.ColorGradient(perc, ...)
    if perc >= 1 then
        return select(select('#', ...) - 2, ...)
    elseif perc <= 0 then
        return ...
    end
    local num = select('#', ...) / 3
    local segment, relperc = math.modf(perc * (num - 1))
    local r1, g1, b1, r2, g2, b2
    r1, g1, b1 = select((segment * 3) + 1, ...)
    r2, g2, b2 = select((segment * 3) + 4, ...)
    return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
end

------------------------------------------------------------------------
-- Phase 1: BFI급 유틸 함수 — HandleScrollBar/CheckButton/StatusBar/Dropdown/Icon/ItemButton
------------------------------------------------------------------------

--- 스크롤바 스킨: BFI StyleScrollBar 패턴 — Track 배경 + Thumb 클래스컬러 + 화살표 -- [ESSENTIAL]
function ns.HandleScrollBar(scrollBar)
    if not scrollBar or scrollBar._ddeSkinned then return end
    scrollBar._ddeSkinned = true

    ns.StripTextures(scrollBar)

    -- Back/Forward 화살표 버튼 -- [ESSENTIAL]
    local function StyleArrow(arrow, text)
        if not arrow then return end
        ns.StripTextures(arrow)
        if arrow.Texture then arrow.Texture:SetAlpha(0) end

        -- 심플 화살표 라벨 -- [ESSENTIAL]
        local label = arrow:CreateFontString(nil, "OVERLAY")
        label:SetFont(FONT, 12, "OUTLINE")
        label:SetPoint("CENTER", 0, 0)
        label:SetText(text)
        label:SetTextColor(0.55, 0.55, 0.55, 1)
        arrow._ddeLabel = label

        arrow:HookScript("OnEnter", function(self)
            if self._ddeLabel then self._ddeLabel:SetTextColor(1, 1, 1, 1) end
        end)
        arrow:HookScript("OnLeave", function(self)
            if self._ddeLabel then self._ddeLabel:SetTextColor(0.55, 0.55, 0.55, 1) end
        end)
    end

    StyleArrow(scrollBar.Back, "▲")
    StyleArrow(scrollBar.Forward, "▼")

    -- Track 배경 -- [ESSENTIAL]
    if scrollBar.Track then
        ns.StripTextures(scrollBar.Track)
        ns.CreateBackdrop(scrollBar.Track, {0.06, 0.06, 0.06, 0.6}, {0.15, 0.15, 0.15, 0.4})
    end

    -- Thumb 클래스 컬러 -- [ESSENTIAL]
    local thumb = scrollBar.GetThumb and scrollBar:GetThumb()
    if thumb then
        if thumb.DisableDrawLayer then
            thumb:DisableDrawLayer("ARTWORK")
            thumb:DisableDrawLayer("BACKGROUND")
        end

        -- Thumb 오버레이 프레임 -- [ESSENTIAL]
        local cc = GetClassColor()
        local overlay = CreateFrame("Frame", nil, thumb, "BackdropTemplate")
        overlay:SetAllPoints(thumb)
        overlay:SetFrameLevel(math.max(0, thumb:GetFrameLevel() + 1))
        overlay:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        overlay:SetBackdropColor(cc[1], cc[2], cc[3], 0.6)
        overlay:SetBackdropBorderColor(cc[1], cc[2], cc[3], 0.3)
        overlay:EnableMouse(false)
        scrollBar._ddeThumb = overlay

        -- Thumb 호버 -- [ESSENTIAL]
        if thumb.EnableMouseMotion then thumb:EnableMouseMotion(true) end
        thumb:HookScript("OnEnter", function()
            overlay:SetBackdropColor(cc[1], cc[2], cc[3], 0.9)
        end)
        thumb:HookScript("OnLeave", function()
            overlay:SetBackdropColor(cc[1], cc[2], cc[3], 0.6)
        end)
    end
end

--- 체크버튼 스킨: BFI StyleCheckButton 패턴 — 다크 배경 + 클래스 컬러 체크마크 -- [ESSENTIAL]
function ns.HandleCheckButton(checkBtn)
    if not checkBtn or checkBtn._ddeSkinned then return end
    checkBtn._ddeSkinned = true

    ns.StripTextures(checkBtn)

    -- 배경 프레임 (15x15) -- [ESSENTIAL]
    local bg = CreateFrame("Frame", nil, checkBtn, "BackdropTemplate")
    bg:SetSize(16, 16)
    bg:SetPoint("CENTER", checkBtn, "CENTER", 0, 0)
    bg:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    bg:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    bg:SetBackdropBorderColor(ns.GetColor("border.default"))
    bg:SetFrameLevel(math.max(0, checkBtn:GetFrameLevel()))
    checkBtn._ddeBG = bg

    -- 체크 텍스처: 클래스 컬러 사각형 -- [ESSENTIAL]
    local cc = GetClassColor()
    local checked = checkBtn:CreateTexture(nil, "ARTWORK")
    checked:SetTexture(FLAT)
    checked:SetPoint("TOPLEFT", bg, "TOPLEFT", 2, -2)
    checked:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -2, 2)
    checked:SetVertexColor(cc[1], cc[2], cc[3], 0.8)
    checkBtn:SetCheckedTexture(checked)

    -- 하이라이트 -- [ESSENTIAL]
    local highlight = checkBtn:CreateTexture(nil, "ARTWORK")
    highlight:SetTexture(FLAT)
    highlight:SetAllPoints(checked)
    highlight:SetVertexColor(cc[1], cc[2], cc[3], 0.15)
    checkBtn:SetHighlightTexture(highlight)

    -- 비활성 체크 텍스처 -- [ESSENTIAL]
    local disabled = checkBtn:CreateTexture(nil, "ARTWORK")
    disabled:SetTexture(FLAT)
    disabled:SetAllPoints(checked)
    disabled:SetVertexColor(0.4, 0.4, 0.4, 0.5)
    checkBtn:SetDisabledCheckedTexture(disabled)

    -- 상태 후킹 -- [ESSENTIAL]
    checkBtn:HookScript("OnEnable", function(self)
        if self._ddeBG then self._ddeBG:SetBackdropBorderColor(ns.GetColor("border.default")) end
    end)
    checkBtn:HookScript("OnDisable", function(self)
        if self._ddeBG then self._ddeBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5) end
    end)

    -- 라벨 폰트 -- [ESSENTIAL]
    local text = checkBtn.Text or checkBtn.text or (checkBtn.GetFontString and checkBtn:GetFontString())
    if text and text.SetFont then
        ns.SetFont(text, (SL and SL.Font and SL.Font.normal) or 12, "")
    end
end

--- 상태바 스킨: BFI StyleProgressBar 패턴 — FLAT 텍스처 + 다크 배경 -- [ESSENTIAL]
function ns.HandleStatusBar(statusBar)
    if not statusBar or statusBar._ddeSkinned then return end
    statusBar._ddeSkinned = true

    ns.StripTextures(statusBar)

    -- 배경 -- [ESSENTIAL]
    local bg = statusBar:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetTexture(FLAT)
    bg:SetVertexColor(0.06, 0.06, 0.06, 0.85)
    statusBar._ddeBG = bg

    -- 바 텍스처 교체 -- [ESSENTIAL]
    statusBar:SetStatusBarTexture(FLAT)

    -- 1px 테두리 -- [ESSENTIAL]
    ns.CreateBorder(statusBar)

    -- 텍스트 폰트 교체 -- [ESSENTIAL]
    local text = statusBar.Text or statusBar.text
    if text and text.SetFont then
        ns.SetFont(text, (SL and SL.Font and SL.Font.small) or 11, "OUTLINE")
    end
end

--- 드롭다운 스킨: BFI StyleDropdownButton 패턴 — 배경 + 화살표 + 호버 -- [ESSENTIAL]
function ns.HandleDropdown(dropdown)
    if not dropdown or dropdown._ddeSkinned then return end
    dropdown._ddeSkinned = true

    ns.StripTextures(dropdown)
    if dropdown.NineSlice then dropdown.NineSlice:SetAlpha(0) end

    -- 배경 -- [ESSENTIAL]
    ns.CreateBackdrop(dropdown, {0.10, 0.10, 0.10, 0.9}, {0.20, 0.20, 0.20, 0.7})

    -- 내부 Button (있는 경우) 숨기기 -- [ESSENTIAL]
    if dropdown.Arrow then dropdown.Arrow:SetAlpha(0) end
    if dropdown.Button then
        ns.StripTextures(dropdown.Button)
        dropdown.Button:SetAlpha(0.5) -- 클릭 영역은 유지
    end

    -- 화살표 아이콘 -- [ESSENTIAL]
    local arrow = dropdown:CreateFontString(nil, "OVERLAY")
    arrow:SetFont(FONT, 12, "")
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
    arrow:SetText("▼")
    arrow:SetTextColor(0.55, 0.55, 0.55, 1)
    dropdown._ddeArrow = arrow

    -- 텍스트 폰트 -- [ESSENTIAL]
    local text = dropdown.Text or dropdown.text
    if text and text.SetFont then
        ns.SetFont(text, (SL and SL.Font and SL.Font.normal) or 12, "")
        text:SetTextColor(0.85, 0.85, 0.85, 1)
    end

    -- 호버 -- [ESSENTIAL]
    dropdown:HookScript("OnEnter", function(self)
        if self._ddeArrow then self._ddeArrow:SetTextColor(1, 1, 1, 1) end
        local t = self.Text or self.text
        if t then t:SetTextColor(1, 1, 1, 1) end
    end)
    dropdown:HookScript("OnLeave", function(self)
        if self._ddeArrow then self._ddeArrow:SetTextColor(0.55, 0.55, 0.55, 1) end
        local t = self.Text or self.text
        if t and t.SetTextColor then t:SetTextColor(0.85, 0.85, 0.85, 1) end
    end)
end

--- 아이콘 스킨: BFI StyleIcon 패턴 — TexCoord 크롭 + 보더 -- [ESSENTIAL]
function ns.HandleIcon(icon, parent, createBorder)
    if not icon then return end

    -- TexCoord 크롭 (BFI 기본: 0.08, 0.92) -- [ESSENTIAL]
    if icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- 보더 생성 (옵션) -- [ESSENTIAL]
    if createBorder ~= false then
        local borderParent = parent or (icon.GetParent and icon:GetParent())
        if borderParent and not borderParent._ddeIconBorder then
            local bd = CreateFrame("Frame", nil, borderParent, "BackdropTemplate")
            bd:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
            bd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
            bd:SetFrameLevel(math.max(0, borderParent:GetFrameLevel()))
            bd:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
            bd:SetBackdropBorderColor(0, 0, 0, 1)
            borderParent._ddeIconBorder = bd
        end
    end
end

--- 아이템 버튼 스킨: BFI StyleItemButton 패턴 — 아이콘+등급 보더+하이라이트 -- [ESSENTIAL]
function ns.HandleItemButton(button)
    if not button or button._ddeSkinned then return end
    button._ddeSkinned = true

    local name = button.GetName and button:GetName()

    -- 아이콘 TexCoord -- [ESSENTIAL]
    local icon = (name and _G[name.."IconTexture"]) or button.IconTexture or button.Icon or button.icon
    if icon then
        ns.HandleIcon(icon, button)
    end

    -- NormalTexture 숨기기 -- [ESSENTIAL]
    local normTex = button.NormalTexture or (name and _G[name.."NormalTexture"])
        or (button.GetNormalTexture and button:GetNormalTexture())
    if normTex then normTex:SetAlpha(0) end

    -- 하이라이트: 흰색 오버레이 -- [ESSENTIAL]
    local ht = button.GetHighlightTexture and button:GetHighlightTexture()
    if ht then
        ht:SetTexture(FLAT)
        ht:SetVertexColor(1, 1, 1, 0.15)
        if icon then
            ht:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            ht:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Pushed 텍스처 -- [ESSENTIAL]
    local pt = button.GetPushedTexture and button:GetPushedTexture()
    if pt then
        pt:SetTexture(FLAT)
        pt:SetVertexColor(1, 0.82, 0, 0.2)
        if icon then
            pt:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            pt:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- IconBorder: 등급별 색상 동기화 (BFI 핵심) -- [ESSENTIAL]
    local iconBorder = button.IconBorder or (name and _G[name.."IconBorder"])
    if iconBorder then
        iconBorder:SetAlpha(0) -- 블리자드 테두리 숨기기

        -- SetVertexColor 후킹 → 커스텀 보더 색상 동기화 -- [ESSENTIAL]
        if button._ddeIconBorder or (icon and icon:GetParent() and icon:GetParent()._ddeIconBorder) then
            local bd = button._ddeIconBorder or icon:GetParent()._ddeIconBorder
            hooksecurefunc(iconBorder, "SetVertexColor", function(_, r, g, b, a)
                if bd then bd:SetBackdropBorderColor(r, g, b, a or 1) end
            end)
            hooksecurefunc(iconBorder, "Hide", function()
                if bd then bd:SetBackdropBorderColor(0, 0, 0, 1) end
            end)
            hooksecurefunc(iconBorder, "Show", function(self)
                if bd and self.IsShown and self:IsShown() then
                    -- 현재 색상 유지
                end
            end)
        end
    end
end

------------------------------------------------------------------------
-- 모듈 시스템 -- [ESSENTIAL]
------------------------------------------------------------------------
ns.modules = {}
ns.onDemandSkins = {}  -- ★ Skins/*.lua 파일이 먼저 로드되므로 여기서 초기화 -- [ESSENTIAL]

function ns:RegisterModule(name, module)
    self.modules[name] = module
end

function ns:EnableModule(name)
    local mod = self.modules[name]
    if mod and mod.Enable then
        local ok, err = pcall(mod.Enable, mod)
        if not ok then
            local _pfx = SL and SL.GetChatPrefix and SL.GetChatPrefix("Essential", "Essential") or "|cffffffffDDing|r|cffffa300UI|r |cffffd133Essential|r: " -- [STYLE]
            print(_pfx .. "|cffff0000" .. name .. " 모듈 에러: " .. tostring(err) .. "|r")
        end
    end
end

function ns:DisableModule(name)
    local mod = self.modules[name]
    if mod and mod.Disable then
        mod:Disable()
    end
end

------------------------------------------------------------------------
-- StyleLib 악센트 등록 -- [ESSENTIAL]
------------------------------------------------------------------------
if SL and SL.RegisterAddon then
    SL.RegisterAddon("Essential") -- [ESSENTIAL-DESIGN] AccentPresets.Essential 노란색 사용
end

------------------------------------------------------------------------
-- 기본 DB -- [ESSENTIAL]
------------------------------------------------------------------------
local defaults = {
    general = { -- [ESSENTIAL-DESIGN]
        scale = 1.0,
    },
    minimap = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        shape = "square",           -- 사각형/원형
        size = 180,                 -- 100~300, step 10
        hideButtons = false,        -- 미니맵 버튼 숨기기
        mouseoverButtons = true,    -- 마우스오버 시 버튼 표시
        clock = true,               -- 시계 표시
        zoneText = true,
        mouseWheel = true,
        coordinates = {             -- [ESSENTIAL] 좌표 표시
            enabled = true,
            format = "%.1f",
            updateInterval = 0.5,
        },
        performanceInfo = {         -- [ESSENTIAL] MS/FPS 표시
            enabled = true,
            showMS = true,
            showFPS = true,
            updateInterval = 1,
        },
    },
    minimapButtonBar = { -- [ESSENTIAL-DESIGN] 미니맵 버튼 바
        enabled = true,
        buttonSize = 28,            -- 20~40
        buttonsPerRow = 6,          -- 3~12
        spacing = 2,                -- 0~8
        backdrop = true,
        backdropAlpha = 0.6,        -- 0~1
    },
    chat = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        backdropAlpha = 0.75,       -- 배경 투명도 0~1
        tabFontSize = 12,           -- 탭 폰트 크기 8~16
        fadeTime = 30,              -- 페이드 시간 0~60, step 5
        editboxSkin = true,         -- 입력창 스킨
        scrollButtonSkin = true,    -- 스크롤 버튼 스킨
        -- 하위 호환 유지
        backdrop = true,
        editboxFontSize = 13,
        copyButton = true,
        urlDetect = true,
        classColors = true,
        shortenChannels = false,
        whisperSound = true,        -- [ESSENTIAL] 위스퍼 수신 사운드
    },
    buffs = { -- [ESSENTIAL-DESIGN] 기존 호환 유지
        enabled = true,
        iconTrim = true,
        durationFontSize = 11,
        countFontSize = 12,
        iconSize = 32,              -- [ESSENTIAL] 아이콘 크기 20~48
        growDirection = "LEFT",     -- [ESSENTIAL] LEFT/RIGHT
        wrapAfter = 12,             -- [ESSENTIAL] 줄바꿈 기준 4~20
        sortMethod = "TIME",        -- [ESSENTIAL] TIME/INDEX/NAME
    },
    quest = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        backdropAlpha = 0.8,        -- 배경 투명도 0~1
        headerFontSize = 14,        -- 헤더 폰트 크기 10~18
        itemFontSize = 11,          -- 항목 폰트 크기 8~14
        progressBarHeight = 4,      -- 진행바 높이 2~12
        -- 하위 호환 유지
        progressBar = true,
        timerBar = true,
        headerSkin = true,
    },
    meter = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        detailsSkin = true,         -- Details 스킨
        barHeight = 16,             -- 바 높이 12~24
        barFontSize = 11,           -- 폰트 크기 8~14
        titlebarSkin = true,        -- 타이틀바 스킨
        titleFontSize = 12,
        embedSkin = false,          -- [ESSENTIAL] ElvUI 스타일 임베드 스킨
        combatShow = false,         -- [ESSENTIAL] 전투 시 자동 표시
    },
    actionbars = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        buttonSkin = true,          -- 버튼 스킨
        cooldownFontSize = 14,      -- 쿨다운 폰트 크기 8~18
        hotkeyFontSize = 11,        -- 키바인드 폰트 크기 6~14
        barBackground = false,      -- 바 배경 표시
        barBackgroundAlpha = 0.3,   -- 바 배경 투명도 0~1
        microMenuSkin = true,       -- 마이크로메뉴 스킨
        bagButtonSkin = true,       -- 가방 버튼 스킨
        -- 하위 호환 유지
        iconTrim = true,
        cleanIcons = true,
        slotBackgroundAlpha = 0.3,
        cooldownDesaturate = true,
        cooldownDimAlpha = 0.8,
        shortenKeybinds = true,
        macroName = true,
        macroNameFontSize = 10,
        macroNameMaxChars = 5,
        countFontSize = 14,
        hideBlizzardArt = true,
        fadeBars = {
            MainActionBar = false,
            MultiBarBottomLeft = false,
            MultiBarBottomRight = false,
            MultiBarRight = false,
            MultiBarLeft = false,
            MultiBar5 = false,
            MultiBar6 = false,
            MultiBar7 = false,
        },
        fadeStanceBar = false,
        fadePetBar = false,
        fadeAlpha = 0,
        fadeDuration = 0.3,
        hideMenuBar = false,
        hideBagBar = false,
    },
    skins = { -- [ESSENTIAL] 블리자드 UI 스킨
        enabled = true,
        gameMenu = true,
        staticPopup = true,
        tooltip = true,
        dropdown = true,
        readyCheck = true,
        lfgPopup = true,
        ghostFrame = true,
        phase2 = true,          -- OnDemand: CharacterFrame, SpellBook 등
    },
}

------------------------------------------------------------------------
-- 이벤트 처리 -- [ESSENTIAL]
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- SavedVariables 초기화 (이전 DDing_EssentialDB → DDingUI_EssentialDB 마이그레이션)
        if not DDingUI_EssentialDB then
            DDingUI_EssentialDB = DDing_EssentialDB or {}
            DDing_EssentialDB = nil -- 구버전 정리
        end
        local db = DDingUI_EssentialDB
        -- 딥 머지: 기존 DB에 새 키 추가 (기존 값 유지, 3단계 깊이) -- [ESSENTIAL]
        for k, v in pairs(defaults) do
            if db[k] == nil then
                db[k] = CopyTable(v)
            elseif type(v) == "table" then
                for subK, subV in pairs(v) do
                    if db[k][subK] == nil then
                        if type(subV) == "table" then
                            db[k][subK] = CopyTable(subV)
                        else
                            db[k][subK] = subV
                        end
                    elseif type(subV) == "table" and type(db[k][subK]) == "table" then
                        -- 3단계: fadeBars 등 중첩 테이블 머지 -- [ESSENTIAL]
                        for subSubK, subSubV in pairs(subV) do
                            if db[k][subK][subSubK] == nil then
                                db[k][subK][subSubK] = subSubV
                            end
                        end
                    end
                end
            end
        end
        ns.db = db
        ns.defaults = defaults -- [ESSENTIAL-DESIGN] Config.lua Reset 참조용

    elseif event == "PLAYER_LOGIN" then
        -- StyleLib 재확인 (다른 애드온이 나중에 로드될 수 있음)
        if not SL then
            SL = _G.DDingUI_StyleLib
            ns.SL = SL
            if SL then
                FLAT = SL.Textures and SL.Textures.flat or FLAT
                FONT = SL.Font and SL.Font.path or FONT
                ns.FLAT = FLAT
                ns.FONT = FONT
                -- 악센트 재등록 -- [ESSENTIAL-DESIGN]
                if SL.RegisterAddon then
                    SL.RegisterAddon("Essential") -- AccentPresets.Essential 노란색 사용
                end
            end
        end

        -- 모듈 활성화
        for name, mod in pairs(ns.modules) do
            local dbEntry = ns.db[name]
            if dbEntry and dbEntry.enabled ~= false then
                ns:EnableModule(name)
            end
        end

        -- [CONTROLLER] MediaChanged 콜백 등록
        if SL and SL.RegisterCallback then
            SL.RegisterCallback(ns, "MediaChanged", function()
                -- 폰트/텍스처 변수 갱신
                SL = _G.DDingUI_StyleLib
                ns.SL = SL
                FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
                FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
                FONT_DEFAULT = (SL and SL.Font and SL.Font.default) or "Fonts\\FRIZQT__.TTF"
                ns.FLAT = FLAT
                ns.FONT = FONT
                ns.FONT_DEFAULT = FONT_DEFAULT
            end)
        end

        self:UnregisterAllEvents()
    end
end)

ns.frame = frame
