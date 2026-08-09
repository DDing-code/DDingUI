--[[
    DDingUI Profile - Standalone Installer UI
    Core/InstallerUI.lua
    StyleLib v1.0.2 design pass
]]
local DUI = unpack(DDingUI_Profile)
local I = DUI:GetModule("Installer")

local ADDON_KEY = "Profile"
local SL = _G.DDingUI_StyleLib
local C = (SL and SL.Colors) or {}
local T = (SL and SL.Tokens) or {}

local FLAT = (SL and SL.GetTexture and SL:GetTexture("flat"))
    or (SL and SL.Textures and SL.Textures.flat)
    or [[Interface\Buttons\WHITE8x8]]

local function FontPath()
    return (SL and SL.GetFont and SL:GetFont("primary"))
        or (SL and SL.Font and SL.Font.path)
        or "Fonts\\2002.TTF"
end

local function FontSize(category, fallback)
    return (SL and SL.GetFontSize and SL:GetFontSize(category))
        or (SL and SL.Font and SL.Font[category])
        or fallback
end

local function Color(path, fallback)
    local cur = C
    for i = 1, #path do
        cur = cur and cur[path[i]]
    end
    return cur or fallback
end

local bgMain      = T.PANEL_BG     or Color({ "bg", "main" },      { 0.10, 0.10, 0.10, 0.95 })
local bgSidebar   = T.SIDEBAR_BG   or Color({ "bg", "sidebar" },   { 0.08, 0.08, 0.08, 0.95 })
local bgInput     = T.INPUT_BG     or Color({ "bg", "input" },     { 0.06, 0.06, 0.06, 0.80 })
local bgHover     = T.BG_HOVER     or Color({ "bg", "hover" },     { 0.20, 0.20, 0.20, 0.60 })
local bgSelected  = T.BG_SELECTED  or Color({ "bg", "selected" },  { 0.18, 0.18, 0.22, 0.80 })
local bgTitlebar  = T.TITLEBAR_BG  or Color({ "bg", "titlebar" },  { 0.12, 0.12, 0.12, 0.98 })
local borderDef   = T.BORDER_DEFAULT or Color({ "border", "default" }, { 0.25, 0.25, 0.25, 0.50 })
local borderSep   = T.BORDER_SEP     or Color({ "border", "separator" }, { 0.20, 0.20, 0.20, 0.40 })
local textNormal  = T.TEXT_NORMAL    or Color({ "text", "normal" },    { 0.85, 0.85, 0.85, 1.0 })
local textHigh    = T.TEXT_HIGHLIGHT or Color({ "text", "highlight" }, { 1.00, 1.00, 1.00, 1.0 })
local textDim     = T.TEXT_DIM       or Color({ "text", "dim" },       { 0.60, 0.60, 0.60, 1.0 })

local acFrom, acTo, acLight, acDark
if SL and SL.GetAccent then
    acFrom, acTo, acLight, acDark = SL.GetAccent(ADDON_KEY)
end
acFrom  = acFrom  or { 1.00, 0.27, 0.27, 1.0 }
acTo    = acTo    or { 0.70, 0.10, 0.10, 1.0 }
acLight = acLight or { 1.00, 0.50, 0.50, 1.0 }
acDark  = acDark  or { 0.55, 0.08, 0.08, 1.0 }

local FRAME_W, FRAME_H = 680, 460
local TITLEBAR_H = 34
local SIDEBAR_W = 176
local NAV_H = 48
local STEP_H = 28
local CONTENT_PAD = 28
local TITLE_LOGO = [[Interface\AddOns\DDingUI_Profile\Media\Textures\logo_wordmark.tga]]

local installerFrame
local currentPage = 1
local installerConfig

local function ApplyBackdrop(frame, bg, border)
    frame:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if bg then frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1) end
    if border then frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1) end
end

local function Solid(parent, color, layer)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return tex
end

local function Font(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FontPath(), size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    return fs
end

local function DecorateButton(button)
    button.Text = button.Text or button.label
    button.SetText = function(self, text)
        if self.Text then self.Text:SetText(text) end
    end
    button.GetText = function(self)
        return self.Text and self.Text:GetText() or nil
    end
    return button
end

local function CreateButton(parent, text, width, height, onClick, primary)
    local btn
    if SL and SL.CreateButton then
        btn = SL.CreateButton(parent, ADDON_KEY, text or "", onClick, {
            width = width or 120,
            height = height or 26,
            motion = true,
            hoverBg = primary and { acFrom[1], acFrom[2], acFrom[3], 0.16 } or bgHover,
            hoverBorder = { acFrom[1], acFrom[2], acFrom[3], primary and 0.85 or 0.55 },
            normalText = primary and textHigh or textNormal,
            hoverText = textHigh,
        })
    else
        local normalBg = primary and { acDark[1], acDark[2], acDark[3], 0.45 } or bgInput
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(width or 120, height or 26)
        ApplyBackdrop(btn, normalBg, borderDef)
        local label = Font(btn, FontSize("normal", 13), primary and textHigh or textNormal)
        label:SetPoint("CENTER")
        label:SetText(text or "")
        btn.label = label
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(bgHover[1], bgHover[2], bgHover[3], bgHover[4] or 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(normalBg[1], normalBg[2], normalBg[3], normalBg[4] or 1) end)
        if onClick then btn:SetScript("OnClick", onClick) end
    end
    return DecorateButton(btn)
end

local function SetButtonDisabled(button, disabled)
    if button.SetDisabledState then
        button:SetDisabledState(disabled)
    else
        button:SetEnabled(not disabled)
        button:SetAlpha(disabled and 0.45 or 1)
    end
end

local function AddGradientLine(parent, fromColor, toColor, height, top)
    local line
    if SL and SL.CreateHorizontalGradient then
        line = SL.CreateHorizontalGradient(parent, fromColor, toColor, height or 2, "ARTWORK")
    else
        line = parent:CreateTexture(nil, "ARTWORK")
        line:SetHeight(height or 2)
        line:SetColorTexture(fromColor[1], fromColor[2], fromColor[3], fromColor[4] or 1)
    end
    line:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT", parent, top and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
    line:SetPoint(top and "TOPRIGHT" or "BOTTOMRIGHT", parent, top and "TOPRIGHT" or "BOTTOMRIGHT", 0, 0)
    return line
end

local function RegisterSpecialFrame(name)
    for _, registered in ipairs(UISpecialFrames) do
        if registered == name then return end
    end
    tinsert(UISpecialFrames, name)
end

local function ShowPage(pageNum)
    if not installerConfig or not installerFrame then return end

    local pages = installerConfig.Pages
    if not pages or not pages[pageNum] then return end
    currentPage = pageNum

    local f = installerFrame

    f.SubTitle:SetText("")
    f.Desc1:SetText("")
    f.Desc2:SetText("")
    for i = 1, 4 do
        f["Option" .. i]:Hide()
        f["Option" .. i]:SetScript("OnClick", nil)
    end

    PluginInstallFrame = f
    pages[pageNum]()

    local contentW = FRAME_W - SIDEBAR_W - (CONTENT_PAD * 2)
    if installerConfig.tutorialImage and currentPage == 1 then
        f.TutorialImage:SetTexture(installerConfig.tutorialImage)
        f.TutorialImage:SetSize(148, 74)
        f.TutorialImage:Show()
        f.SubTitle:ClearAllPoints()
        f.SubTitle:SetPoint("TOPLEFT", f.TutorialImage, "BOTTOMLEFT", 0, -16)
    else
        f.TutorialImage:Hide()
        f.SubTitle:ClearAllPoints()
        f.SubTitle:SetPoint("TOPLEFT", f.Content, "TOPLEFT", CONTENT_PAD, -36)
    end

    f.SubTitle:SetWidth(contentW)
    f.Desc1:SetWidth(contentW)
    f.Desc2:SetWidth(contentW)

    local visible = {}
    for i = 1, 4 do
        if f["Option" .. i]:IsShown() then
            visible[#visible + 1] = f["Option" .. i]
        end
    end

    local buttonW = 142
    local gap = 10
    local totalW = (#visible * buttonW) + math.max(0, #visible - 1) * gap
    for i, btn in ipairs(visible) do
        btn:SetSize(buttonW, 28)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", f.Desc2, "BOTTOMLEFT", (contentW - totalW) * 0.5 + (i - 1) * (buttonW + gap), -24)
    end

    local numPages = #pages
    SetButtonDisabled(f.Prev, pageNum <= 1)
    f.Next:SetText(pageNum < numPages and "다음" or "닫기")
    f.PageIndicator:SetText(format("%d / %d", pageNum, numPages))

    for i, btn in ipairs(f.StepButtons) do
        local active = i == currentPage
        if active then
            btn.ActiveBg:Show()
            btn.Stripe:Show()
        else
            btn.ActiveBg:Hide()
            btn.Stripe:Hide()
        end
        btn.Number:SetTextColor(active and acFrom[1] or textDim[1], active and acFrom[2] or textDim[2], active and acFrom[3] or textDim[3], 1)
        btn.Text:SetTextColor(active and textHigh[1] or textDim[1], active and textHigh[2] or textDim[2], active and textHigh[3] or textDim[3], 1)
    end
end

local function BuildStepList(f, config)
    for _, btn in ipairs(f.StepButtons) do
        btn:Hide()
    end
    wipe(f.StepButtons)

    local titles = config.StepTitles
    if not titles then return end

    for i = 1, #titles do
        local btn = CreateFrame("Button", nil, f.Sidebar)
        btn:SetSize(SIDEBAR_W - 18, STEP_H)
        btn:SetPoint("TOPLEFT", f.Sidebar, "TOPLEFT", 9, -34 - (i - 1) * (STEP_H + 4))

        btn.Bg = Solid(btn, { 0, 0, 0, 0 })
        btn.ActiveBg = Solid(btn, bgSelected, "BACKGROUND")
        btn.ActiveBg:Hide()

        btn.Stripe = btn:CreateTexture(nil, "ARTWORK")
        btn.Stripe:SetWidth(2)
        btn.Stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        btn.Stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        btn.Stripe:SetColorTexture(acFrom[1], acFrom[2], acFrom[3], 1)
        btn.Stripe:Hide()

        btn.Number = Font(btn, FontSize("small", 11), textDim)
        btn.Number:SetPoint("LEFT", 10, 0)
        btn.Number:SetWidth(20)
        btn.Number:SetJustifyH("RIGHT")
        btn.Number:SetText(i)

        btn.Text = Font(btn, FontSize("small", 11), textDim)
        btn.Text:SetPoint("LEFT", btn.Number, "RIGHT", 8, 0)
        btn.Text:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btn.Text:SetJustifyH("LEFT")
        btn.Text:SetWordWrap(false)
        btn.Text:SetText(titles[i])

        btn:SetScript("OnEnter", function(self)
            if i ~= currentPage then
                self.Bg:SetColorTexture(bgHover[1], bgHover[2], bgHover[3], bgHover[4] or 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self.Bg:SetColorTexture(0, 0, 0, 0)
        end)
        btn:SetScript("OnClick", function()
            ShowPage(i)
        end)

        f.StepButtons[i] = btn
    end
end

local function CreateTitleBar(parent)
    local titleBar
    if SL and SL.CreateTitleBar then
        titleBar = SL.CreateTitleBar(parent, ADDON_KEY, "DDingUI Profile", DUI.version or "")
    else
        titleBar = CreateFrame("Frame", nil, parent)
        titleBar:SetHeight(TITLEBAR_H)
        titleBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
        titleBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
        Solid(titleBar, bgTitlebar)
        AddGradientLine(titleBar, acFrom, acTo, 2, true)

        local title = Font(titleBar, FontSize("title", 14), textHigh)
        title:SetPoint("LEFT", 12, 0)
        title:SetText("|cffffffffDDing|r|cffff4444UI|r |cffffffffProfile|r")

        local version = Font(titleBar, FontSize("small", 11), textDim)
        version:SetText("v" .. tostring(DUI.version or ""))

        local close = CreateButton(titleBar, "X", 28, 24, function()
            if parent.HideAnimated then parent:HideAnimated() else parent:Hide() end
        end)
        close:SetPoint("RIGHT", -5, 0)
        titleBar.titleText = title
        titleBar.verText = version
        titleBar.closeBtn = close
    end

    if titleBar.titleText then
        titleBar.titleText:SetText("")
        titleBar.titleText:Hide()
    end
    if not titleBar.brandLogo then
        titleBar.brandLogo = titleBar:CreateTexture(nil, "ARTWORK")
    end
    titleBar.brandLogo:ClearAllPoints()
    titleBar.brandLogo:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleBar.brandLogo:SetSize(144, 36)
    titleBar.brandLogo:SetTexture(TITLE_LOGO)
    titleBar.brandLogo:SetTexCoord(0, 1, 0, 1)
    titleBar.brandLogo:Show()
    if titleBar.verText then
        titleBar.verText:ClearAllPoints()
        titleBar.verText:SetPoint("LEFT", titleBar.brandLogo, "RIGHT", 5, -1)
    end

    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() parent:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)
    return titleBar
end

local function CreateInstallerFrame()
    if installerFrame then return installerFrame end

    local f = CreateFrame("Frame", "DDingUIInstallerFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f._ddslMotionBaseScale = f:GetScale() or 1

    ApplyBackdrop(f, bgMain, { 0, 0, 0, 1 })

    function f:ShowAnimated()
        if SL and SL.Motion and SL.Motion.EllesmereOpen then
            SL.Motion.EllesmereOpen(self, { baseScale = self._ddslMotionBaseScale })
        else
            self:Show()
        end
    end

    function f:HideAnimated()
        if SL and SL.Motion and SL.Motion.EllesmereClose then
            SL.Motion.EllesmereClose(self, { baseScale = self._ddslMotionBaseScale })
        else
            self:Hide()
        end
    end

    RegisterSpecialFrame("DDingUIInstallerFrame")

    f.TitleBar = CreateTitleBar(f)

    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -TITLEBAR_H)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, NAV_H)
    ApplyBackdrop(sidebar, bgSidebar, nil)
    f.Sidebar = sidebar

    local sideLabel = Font(sidebar, FontSize("small", 11), textDim)
    sideLabel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, -12)
    sideLabel:SetText("PROFILE STEPS")
    f.SideLabel = sideLabel

    local sidebarVersion = Font(sidebar, FontSize("small", 11), textDim)
    sidebarVersion:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 12, 12)
    sidebarVersion:SetText("v" .. tostring(DUI.version or ""))
    f.SidebarVersion = sidebarVersion

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetWidth(1)
    sep:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    sep:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(borderSep[1], borderSep[2], borderSep[3], borderSep[4] or 1)

    f.StepButtons = {}

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 1, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, NAV_H)
    f.Content = content

    local contentShade = content:CreateTexture(nil, "BACKGROUND")
    contentShade:SetPoint("TOPLEFT")
    contentShade:SetPoint("BOTTOMRIGHT")
    contentShade:SetColorTexture(bgMain[1], bgMain[2], bgMain[3], bgMain[4] or 1)

    AddGradientLine(content, { acFrom[1], acFrom[2], acFrom[3], 0.45 }, { acTo[1], acTo[2], acTo[3], 0.05 }, 1, true)

    local img = content:CreateTexture(nil, "ARTWORK")
    img:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_PAD, -28)
    f.TutorialImage = img

    local subTitle = Font(content, FontSize("section", 14) + 1, acFrom)
    subTitle:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_PAD, -36)
    subTitle:SetJustifyH("LEFT")
    f.SubTitle = subTitle

    local desc1 = Font(content, FontSize("normal", 13), textNormal)
    desc1:SetPoint("TOPLEFT", subTitle, "BOTTOMLEFT", 0, -16)
    desc1:SetJustifyH("LEFT")
    if desc1.SetSpacing then desc1:SetSpacing(3) end
    f.Desc1 = desc1

    local desc2 = Font(content, FontSize("small", 11) + 1, textDim)
    desc2:SetPoint("TOPLEFT", desc1, "BOTTOMLEFT", 0, -8)
    desc2:SetJustifyH("LEFT")
    if desc2.SetSpacing then desc2:SetSpacing(3) end
    f.Desc2 = desc2

    local contentSep = content:CreateTexture(nil, "ARTWORK")
    contentSep:SetHeight(1)
    contentSep:SetPoint("LEFT", content, "LEFT", CONTENT_PAD, 0)
    contentSep:SetPoint("RIGHT", content, "RIGHT", -CONTENT_PAD, 0)
    contentSep:SetPoint("TOP", content, "TOP", 0, -118)
    contentSep:SetColorTexture(borderSep[1], borderSep[2], borderSep[3], borderSep[4] or 1)
    f.ContentSeparator = contentSep

    for i = 1, 4 do
        local btn = CreateButton(content, "", 142, 28, nil, true)
        btn:Hide()
        f["Option" .. i] = btn
    end

    local navBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    navBar:SetPoint("BOTTOMLEFT")
    navBar:SetPoint("BOTTOMRIGHT")
    navBar:SetHeight(NAV_H)
    ApplyBackdrop(navBar, bgSidebar, nil)
    AddGradientLine(navBar, { acFrom[1], acFrom[2], acFrom[3], 0.40 }, { acTo[1], acTo[2], acTo[3], 0.10 }, 1, true)

    local prevBtn = CreateButton(navBar, "이전", 94, 26, function()
        if currentPage > 1 then ShowPage(currentPage - 1) end
    end)
    prevBtn:SetPoint("LEFT", navBar, "LEFT", 14, 0)
    f.Prev = prevBtn

    local nextBtn = CreateButton(navBar, "다음", 94, 26, function()
        local numPages = installerConfig and installerConfig.Pages and #installerConfig.Pages or 0
        if currentPage < numPages then
            ShowPage(currentPage + 1)
        else
            if f.HideAnimated then f:HideAnimated() else f:Hide() end
        end
    end, true)
    nextBtn:SetPoint("RIGHT", navBar, "RIGHT", -14, 0)
    f.Next = nextBtn

    local pageInd = Font(navBar, FontSize("small", 11), textDim)
    pageInd:SetPoint("CENTER")
    f.PageIndicator = pageInd

    f:Hide()
    installerFrame = f
    return f
end

function I:ShowStandalone(config)
    if not config then return end
    installerConfig = config
    currentPage = 1

    local f = CreateInstallerFrame()
    BuildStepList(f, config)
    ShowPage(1)
    if f.ShowAnimated then
        f:ShowAnimated()
    else
        f:Show()
    end
end
