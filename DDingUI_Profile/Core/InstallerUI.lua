--[[
    DDingUI Profile - Standalone Installer UI
    Core/InstallerUI.lua
    ElvUI 없이도 프로필 설치가 가능하도록 독자 UI 제공
    -- [12.0.1]
]]
local DUI = unpack(DDingUI_Profile)
local I = DUI:GetModule("Installer")

-- StyleLib 참조
local SL = _G.DDingUI_StyleLib
local FLAT = (SL and SL.Textures and SL.Textures.flat) or [[Interface\Buttons\WHITE8x8]]
local FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"

-- Colors (딥 nil 체크)
local bgMain     = (SL and SL.Colors and SL.Colors.bg and SL.Colors.bg.main) or {0.10, 0.10, 0.10, 0.95}
local bgSidebar   = (SL and SL.Colors and SL.Colors.bg and SL.Colors.bg.sidebar) or {0.08, 0.08, 0.08, 0.95}
local bgHover     = (SL and SL.Colors and SL.Colors.bg and SL.Colors.bg.hover) or {0.20, 0.20, 0.20, 0.60}
local borderColor = (SL and SL.Colors and SL.Colors.border and SL.Colors.border.default) or {0.25, 0.25, 0.25, 0.50}
local textNormal  = (SL and SL.Colors and SL.Colors.text and SL.Colors.text.normal) or {0.85, 0.85, 0.85, 1.0}
local textHigh    = (SL and SL.Colors and SL.Colors.text and SL.Colors.text.highlight) or {1.00, 1.00, 1.00, 1.0}
local textDim     = (SL and SL.Colors and SL.Colors.text and SL.Colors.text.dim) or {0.60, 0.60, 0.60, 1.0}

-- Accent
local acFrom, acTo, acLight, acDark
if SL and SL.GetAccent then
    acFrom, acTo, acLight, acDark = SL.GetAccent("Profile")
end
acFrom  = acFrom  or {0.00, 0.80, 1.00}
acTo    = acTo    or {0.00, 0.50, 0.80}
acLight = acLight or {0.30, 0.90, 1.00}
acDark  = acDark  or {0.00, 0.40, 0.65}

-- Layout constants
local FRAME_W, FRAME_H = 640, 440
local TITLEBAR_H = 34
local SIDEBAR_W = 150
local NAV_H = 38
local STEP_H = 22

-- State
local installerFrame
local currentPage = 1
local installerConfig

-------------------------------------------------------
-- Helper: Styled Button
-------------------------------------------------------
local function CreateBtn(parent, w, h, r, g, b)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w or 120, h or 26)
    btn:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = {left=0,right=0,top=0,bottom=0} })

    local br, bg, bb = r or bgHover[1], g or bgHover[2], b or bgHover[3]
    btn:SetBackdropColor(br, bg, bb, 0.85)
    btn:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])

    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT, 12, "")
    text:SetPoint("CENTER")
    text:SetTextColor(textHigh[1], textHigh[2], textHigh[3])
    btn.Text = text

    -- SetText 래핑 (WoW Button API 호환)
    btn.SetText = function(self, str) self.Text:SetText(str) end
    btn.GetText = function(self) return self.Text:GetText() end

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(math.min(br + 0.08, 1), math.min(bg + 0.08, 1), math.min(bb + 0.08, 1), 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(br, bg, bb, 0.85)
    end)

    return btn
end

-------------------------------------------------------
-- Navigate to page
-------------------------------------------------------
local function ShowPage(pageNum)
    if not installerConfig or not installerFrame then return end

    local pages = installerConfig.Pages
    if not pages or not pages[pageNum] then return end
    currentPage = pageNum

    local f = installerFrame

    -- Reset content
    f.SubTitle:SetText("")
    f.Desc1:SetText("")
    f.Desc2:SetText("")
    for i = 1, 4 do
        f["Option"..i]:Hide()
        f["Option"..i]:SetScript("OnClick", nil)
    end

    -- 페이지 함수가 PluginInstallFrame을 참조하므로 전역 설정
    PluginInstallFrame = f

    -- 페이지 실행
    pages[pageNum]()

    -- 표시된 옵션 버튼 재배치 (가운데 정렬)
    local visible = {}
    for i = 1, 4 do
        if f["Option"..i]:IsShown() then
            visible[#visible + 1] = f["Option"..i]
        end
    end
    local totalW = #visible * 155 - 15
    for i, btn in ipairs(visible) do
        btn:ClearAllPoints()
        btn:SetPoint("TOP", f.Desc2, "BOTTOM", -totalW/2 + (i-1)*155 + 70, -24)
    end

    -- 네비게이션 업데이트
    local numPages = #pages
    f.Prev:SetEnabled(pageNum > 1)
    f.Prev:SetAlpha(pageNum > 1 and 1 or 0.35)

    if pageNum < numPages then
        f.Next:SetText("다음 ▶")
    else
        f.Next:SetText("닫기")
    end

    f.PageIndicator:SetText(format("%d / %d", pageNum, numPages))

    -- 스텝 하이라이트
    for i, btn in ipairs(f.StepButtons) do
        if i == currentPage then
            btn.ActiveBg:Show()
            btn.ActiveBg:SetVertexColor(acFrom[1]*0.25, acFrom[2]*0.25, acFrom[3]*0.25, 0.8)
            btn.Text:SetTextColor(acFrom[1], acFrom[2], acFrom[3])
        else
            btn.ActiveBg:Hide()
            btn.Text:SetTextColor(textDim[1], textDim[2], textDim[3])
        end
    end

    -- Tutorial image — ElvUI PluginInstaller 호환
    if installerConfig.tutorialImage and currentPage == 1 then
        f.TutorialImage:SetTexture(installerConfig.tutorialImage)
        if installerConfig.tutorialImageSize then
            f.TutorialImage:SetSize(installerConfig.tutorialImageSize[1], installerConfig.tutorialImageSize[2])
        else
            f.TutorialImage:SetSize(256, 128)
        end
        f.TutorialImage:Show()
        f.SubTitle:ClearAllPoints()
        f.SubTitle:SetPoint("TOP", f.TutorialImage, "BOTTOM", 0, -10)
    else
        f.TutorialImage:Hide()
        f.SubTitle:ClearAllPoints()
        f.SubTitle:SetPoint("TOP", f.Content, "TOP", 0, -24)
    end
end

-------------------------------------------------------
-- Build Step List
-------------------------------------------------------
local function BuildStepList(f, config)
    for _, btn in ipairs(f.StepButtons) do btn:Hide() end
    wipe(f.StepButtons)

    local titles = config.StepTitles
    if not titles then return end

    for i = 1, #titles do
        local btn = CreateFrame("Button", nil, f.Sidebar)
        btn:SetSize(SIDEBAR_W - 8, STEP_H)
        btn:SetPoint("TOPLEFT", f.Sidebar, "TOPLEFT", 4, -8 - (i-1) * STEP_H)

        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(FONT, 11, "")
        text:SetPoint("LEFT", 10, 0)
        text:SetPoint("RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        text:SetTextColor(textDim[1], textDim[2], textDim[3])
        btn.Text = text

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture(FLAT)
        highlight:SetAllPoints()
        highlight:SetVertexColor(bgHover[1], bgHover[2], bgHover[3], 0.3)

        local activeBg = btn:CreateTexture(nil, "BACKGROUND")
        activeBg:SetTexture(FLAT)
        activeBg:SetAllPoints()
        activeBg:Hide()
        btn.ActiveBg = activeBg

        btn.Text:SetText(format("%d. %s", i, titles[i]))
        btn:SetScript("OnClick", function() ShowPage(i) end)

        f.StepButtons[i] = btn
    end
end

-------------------------------------------------------
-- Create Installer Frame
-------------------------------------------------------
local function CreateInstallerFrame()
    if installerFrame then return installerFrame end

    local f = CreateFrame("Frame", "DDingUIInstallerFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    -- Main backdrop
    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = {left=0,right=0,top=0,bottom=0} })
    f:SetBackdropColor(bgMain[1], bgMain[2], bgMain[3], bgMain[4])
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- ESC로 닫기
    tinsert(UISpecialFrames, "DDingUIInstallerFrame")

    ----- Title Bar -----
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(TITLEBAR_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetTexture(FLAT)
    titleBg:SetAllPoints()
    titleBg:SetVertexColor(0.12, 0.12, 0.12, 1)

    -- 악센트 라인
    local accentLine = titleBar:CreateTexture(nil, "OVERLAY")
    accentLine:SetTexture(FLAT)
    accentLine:SetHeight(2)
    accentLine:SetPoint("BOTTOMLEFT")
    accentLine:SetPoint("BOTTOMRIGHT")
    accentLine:SetVertexColor(acFrom[1], acFrom[2], acFrom[3], 1)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(FONT, 14, "")
    titleText:SetPoint("LEFT", 14, 0)
    titleText:SetText("|cffffffffDDing|r|cffffa300UI|r |cffffffffProfile|r")

    -- 닫기 버튼
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(TITLEBAR_H - 8, TITLEBAR_H - 8)
    closeBtn:SetPoint("RIGHT", -6, 0)
    local closeX = closeBtn:CreateFontString(nil, "OVERLAY")
    closeX:SetFont(FONT, 16, "")
    closeX:SetPoint("CENTER", 0, 1)
    closeX:SetText("×")
    closeX:SetTextColor(textDim[1], textDim[2], textDim[3])
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeX:SetTextColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeX:SetTextColor(textDim[1], textDim[2], textDim[3]) end)

    ----- Sidebar (Step List) -----
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetPoint("TOPLEFT", 0, -TITLEBAR_H)
    sidebar:SetPoint("BOTTOMLEFT", 0, NAV_H)
    sidebar:SetBackdrop({ bgFile = FLAT })
    sidebar:SetBackdropColor(bgSidebar[1], bgSidebar[2], bgSidebar[3], bgSidebar[4])
    f.Sidebar = sidebar

    -- 구분선
    local sep = f:CreateTexture(nil, "OVERLAY")
    sep:SetTexture(FLAT)
    sep:SetWidth(1)
    sep:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    sep:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
    sep:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])

    f.StepButtons = {}

    ----- Content Area -----
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 1, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, NAV_H)
    f.Content = content

    -- Tutorial Image (로고) — ElvUI PluginInstaller와 동일 크기/위치
    local img = content:CreateTexture(nil, "ARTWORK")
    img:SetSize(256, 128)
    img:SetPoint("TOP", content, "TOP", 0, -16)
    f.TutorialImage = img

    -- SubTitle
    local subTitle = content:CreateFontString(nil, "OVERLAY")
    subTitle:SetFont(FONT, 15, "")
    subTitle:SetPoint("TOP", img, "BOTTOM", 0, -10)
    subTitle:SetTextColor(acFrom[1], acFrom[2], acFrom[3])
    f.SubTitle = subTitle

    -- Desc1
    local desc1 = content:CreateFontString(nil, "OVERLAY")
    desc1:SetFont(FONT, 13, "")
    desc1:SetPoint("TOP", subTitle, "BOTTOM", 0, -14)
    desc1:SetWidth(FRAME_W - SIDEBAR_W - 50)
    desc1:SetJustifyH("CENTER")
    desc1:SetTextColor(textNormal[1], textNormal[2], textNormal[3])
    f.Desc1 = desc1

    -- Desc2
    local desc2 = content:CreateFontString(nil, "OVERLAY")
    desc2:SetFont(FONT, 12, "")
    desc2:SetPoint("TOP", desc1, "BOTTOM", 0, -8)
    desc2:SetWidth(FRAME_W - SIDEBAR_W - 50)
    desc2:SetJustifyH("CENTER")
    desc2:SetTextColor(textDim[1], textDim[2], textDim[3])
    f.Desc2 = desc2

    -- Option Buttons (1~4)
    for i = 1, 4 do
        local btn = CreateBtn(content, 140, 28, acFrom[1]*0.35, acFrom[2]*0.35, acFrom[3]*0.35)
        btn:SetBackdropBorderColor(acFrom[1]*0.5, acFrom[2]*0.5, acFrom[3]*0.5, 1)
        btn.Text:SetTextColor(acFrom[1], acFrom[2], acFrom[3])
        btn:Hide()
        f["Option"..i] = btn
    end

    ----- Navigation Bar -----
    local navBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    navBar:SetPoint("BOTTOMLEFT")
    navBar:SetPoint("BOTTOMRIGHT")
    navBar:SetHeight(NAV_H)
    navBar:SetBackdrop({ bgFile = FLAT })
    navBar:SetBackdropColor(bgSidebar[1], bgSidebar[2], bgSidebar[3], 1)

    local navSep = navBar:CreateTexture(nil, "OVERLAY")
    navSep:SetTexture(FLAT)
    navSep:SetHeight(1)
    navSep:SetPoint("TOPLEFT")
    navSep:SetPoint("TOPRIGHT")
    navSep:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])

    -- 이전 버튼
    local prevBtn = CreateBtn(navBar, 90, 24)
    prevBtn:SetPoint("LEFT", 12, 0)
    prevBtn:SetText("◀ 이전")
    prevBtn:SetScript("OnClick", function()
        if currentPage > 1 then ShowPage(currentPage - 1) end
    end)
    f.Prev = prevBtn

    -- 다음 버튼
    local nextBtn = CreateBtn(navBar, 90, 24, acFrom[1]*0.35, acFrom[2]*0.35, acFrom[3]*0.35)
    nextBtn:SetBackdropBorderColor(acFrom[1]*0.5, acFrom[2]*0.5, acFrom[3]*0.5, 1)
    nextBtn.Text:SetTextColor(acFrom[1], acFrom[2], acFrom[3])
    nextBtn:SetPoint("RIGHT", -12, 0)
    nextBtn:SetText("다음 ▶")
    nextBtn:SetScript("OnClick", function()
        local numPages = installerConfig and installerConfig.Pages and #installerConfig.Pages or 0
        if currentPage < numPages then
            ShowPage(currentPage + 1)
        else
            f:Hide()
        end
    end)
    f.Next = nextBtn

    -- 페이지 표시
    local pageInd = navBar:CreateFontString(nil, "OVERLAY")
    pageInd:SetFont(FONT, 11, "")
    pageInd:SetPoint("CENTER")
    pageInd:SetTextColor(textDim[1], textDim[2], textDim[3])
    f.PageIndicator = pageInd

    f:Hide()
    installerFrame = f
    return f
end

-------------------------------------------------------
-- Public API: Show standalone installer
-------------------------------------------------------
function I:ShowStandalone(config)
    if not config then return end
    installerConfig = config
    currentPage = 1

    local f = CreateInstallerFrame()
    BuildStepList(f, config)
    ShowPage(1)
    f:Show()
end
