--[[
    DDingToolKit - FocusInterrupt Config
    포커스 차단 시전바 설정 패널
]]

local addonName, ns = ...
local UI = ns.UI
local FocusInterrupt = ns.FocusInterrupt
local L = ns.L

-- StatusBar texture list (LibSharedMedia)
local function GetStatusBarOptions()
    return ns:GetStatusBarOptions()
end

local function GetSoundOptions()
    return ns:GetSoundOptions(true, L["FOCUSINTERRUPT_DEFAULT_SOUND"] or "Raid Warning (Default)", "")
end

function FocusInterrupt:CreateConfigPanel(parent)
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.FocusInterrupt then
            self.db = ns.db.profile.FocusInterrupt
        else
            return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
        end
    end

    local scrollContainer = UI:CreateScrollablePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20, 980)
    scrollContainer:SetPoint("TOPLEFT", 10, -10)

    local panel = scrollContainer.content
    local yOffset = -10

    -- 설명
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", 10, yOffset)
    desc:SetText(L["FOCUSINTERRUPT_DESC"])
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetWidth(panel:GetWidth() - 30)
    desc:SetJustifyH("LEFT")
    yOffset = yOffset - 50

    -- 활성화
    local enableCheckbox = UI:CreateCheckbox(panel, L["MODULE_ENABLED"], function(checked)
        self.db.enabled = checked
        if checked then
            self:OnEnable()
        else
            self:OnDisable()
        end
    end)
    enableCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    enableCheckbox:SetChecked(self.db.enabled)
    yOffset = yOffset - 35

    -- ===== 바 설정 =====
    local barHeader = UI:CreateSectionHeader(panel, L["FOCUSINTERRUPT_BAR_SETTINGS"])
    barHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- 바 너비
    local widthSlider = UI:CreateSlider(panel, L["FOCUSINTERRUPT_BAR_WIDTH"], 100, 500, 5, function(value)
        self.db.barWidth = value
        self:UpdateStyle()
    end)
    widthSlider:SetPoint("TOPLEFT", 15, yOffset)
    widthSlider:SetValue(self.db.barWidth or 280)
    yOffset = yOffset - 55

    -- 바 높이
    local heightSlider = UI:CreateSlider(panel, L["FOCUSINTERRUPT_BAR_HEIGHT"], 15, 60, 1, function(value)
        self.db.barHeight = value
        self:UpdateStyle()
    end)
    heightSlider:SetPoint("TOPLEFT", 15, yOffset)
    heightSlider:SetValue(self.db.barHeight or 30)
    yOffset = yOffset - 55

    -- 배경 투명도
    local bgAlphaSlider = UI:CreateSlider(panel, L["BACKGROUND_ALPHA"], 0, 1, 0.1, function(value)
        self.db.bgAlpha = value
        self:UpdateStyle()
    end)
    bgAlphaSlider:SetPoint("TOPLEFT", 15, yOffset)
    bgAlphaSlider:SetValue(self.db.bgAlpha or 0.3)
    yOffset = yOffset - 55

    -- 글꼴 크기
    local fontSizeSlider = UI:CreateSlider(panel, L["FONT_SIZE"], 8, 24, 1, function(value)
        self.db.fontSize = value
        self:UpdateStyle()
    end)
    fontSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
    fontSizeSlider:SetValue(self.db.fontSize or 12)
    yOffset = yOffset - 55

    -- 전체 크기
    local scaleSlider = UI:CreateSlider(panel, L["OVERALL_SIZE"], 0.5, 2.0, 0.1, function(value)
        self.db.scale = value
        self:UpdateStyle()
    end)
    scaleSlider:SetPoint("TOPLEFT", 15, yOffset)
    scaleSlider:SetValue(self.db.scale or 1.0)
    yOffset = yOffset - 55

    -- 바 텍스쳐
    local textureLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textureLabel:SetPoint("TOPLEFT", 15, yOffset)
    textureLabel:SetText(L["FOCUSINTERRUPT_TEXTURE"])
    textureLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 5

    local textureDropdown = UI:CreateStatusBarDropdown(panel, 220, GetStatusBarOptions(), function(value)
        self.db.texture = value
        self:UpdateStyle()
    end)
    textureDropdown:SetPoint("TOPLEFT", 15, yOffset)
    textureDropdown:SetValue(self.db.texture or "Interface\\TargetingFrame\\UI-StatusBar")
    yOffset = yOffset - 45

    -- ===== 차단 설정 =====
    local intHeader = UI:CreateSectionHeader(panel, L["FOCUSINTERRUPT_INT_SETTINGS"])
    intHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- 차단 불가 시 숨김
    local notIntHideCheckbox = UI:CreateCheckbox(panel, L["FOCUSINTERRUPT_NOTINT_HIDE"], function(checked)
        self.db.notInterruptibleHide = checked
    end)
    notIntHideCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    notIntHideCheckbox:SetChecked(self.db.notInterruptibleHide)
    yOffset = yOffset - 30

    -- 쿨다운 시 숨김
    local cdHideCheckbox = UI:CreateCheckbox(panel, L["FOCUSINTERRUPT_CD_HIDE"], function(checked)
        self.db.cooldownHide = checked
    end)
    cdHideCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    cdHideCheckbox:SetChecked(self.db.cooldownHide)
    yOffset = yOffset - 30

    -- 차단 아이콘 표시
    local kickIconCheckbox = UI:CreateCheckbox(panel, L["FOCUSINTERRUPT_SHOW_KICK_ICON"], function(checked)
        self.db.showKickIcon = checked
    end)
    kickIconCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    kickIconCheckbox:SetChecked(self.db.showKickIcon)
    yOffset = yOffset - 30

    -- 차단자 이름 표시
    local showInterrupterCheckbox = UI:CreateCheckbox(panel, L["FOCUSINTERRUPT_SHOW_INTERRUPTER"], function(checked)
        self.db.showInterrupter = checked
    end)
    showInterrupterCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    showInterrupterCheckbox:SetChecked(self.db.showInterrupter)
    yOffset = yOffset - 30

    -- 대상 표시
    local showTargetCheckbox = UI:CreateCheckbox(panel, L["FOCUSINTERRUPT_SHOW_TARGET"], function(checked)
        self.db.showTarget = checked
    end)
    showTargetCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    showTargetCheckbox:SetChecked(self.db.showTarget)
    yOffset = yOffset - 30

    -- 시간 표시
    local showTimeCheckbox = UI:CreateCheckbox(panel, L["FOCUSINTERRUPT_SHOW_TIME"], function(checked)
        self.db.showTime = checked
    end)
    showTimeCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    showTimeCheckbox:SetChecked(self.db.showTime)
    yOffset = yOffset - 30

    -- 사운드 끄기
    local muteCheckbox = UI:CreateCheckbox(panel, L["FOCUSINTERRUPT_MUTE"], function(checked)
        self.db.mute = checked
    end)
    muteCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    muteCheckbox:SetChecked(self.db.mute)
    yOffset = yOffset - 35

    -- 알림 사운드
    local soundFileLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soundFileLabel:SetPoint("TOPLEFT", 15, yOffset)
    soundFileLabel:SetText(L["LFGALERT_SOUND_FILE"])
    soundFileLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 25

    local soundDropdown = UI:CreateSoundDropdown(panel, 280, GetSoundOptions(), function(value)
        self.db.soundFile = value
    end)
    soundDropdown:SetPoint("TOPLEFT", 15, yOffset)
    soundDropdown:SetValue(self.db.soundFile or "")
    yOffset = yOffset - 50

    -- 차단됨 페이드 시간
    local fadeSlider = UI:CreateSlider(panel, L["FOCUSINTERRUPT_FADE_TIME"], 0, 2, 0.25, function(value)
        self.db.interruptedFadeTime = value
    end)
    fadeSlider:SetPoint("TOPLEFT", 15, yOffset)
    fadeSlider:SetValue(self.db.interruptedFadeTime or 0.75)
    yOffset = yOffset - 55

    -- 차단 아이콘 크기
    local kickSizeSlider = UI:CreateSlider(panel, L["FOCUSINTERRUPT_KICK_ICON_SIZE"], 15, 60, 1, function(value)
        self.db.kickIconSize = value
        self:UpdateStyle()
    end)
    kickSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
    kickSizeSlider:SetValue(self.db.kickIconSize or 30)
    yOffset = yOffset - 55

    -- ===== 색상 설정 =====
    local colorHeader = UI:CreateSectionHeader(panel, L["FOCUSINTERRUPT_COLOR_SETTINGS"])
    colorHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- 차단 가능 색상
    local intColorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    intColorLabel:SetPoint("TOPLEFT", 15, yOffset)
    intColorLabel:SetText(L["FOCUSINTERRUPT_INTERRUPTIBLE_COLOR"])
    intColorLabel:SetTextColor(unpack(UI.colors.text))

    local intColorBtn = UI:CreateColorButton(panel, "", self.db.interruptibleColor, function(r, g, b)
        self.db.interruptibleColor = { r, g, b }
    end)
    intColorBtn:SetPoint("LEFT", intColorLabel, "RIGHT", 10, 0)
    yOffset = yOffset - 30

    -- 차단 불가 색상
    local notIntColorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notIntColorLabel:SetPoint("TOPLEFT", 15, yOffset)
    notIntColorLabel:SetText(L["FOCUSINTERRUPT_NOTINT_COLOR"])
    notIntColorLabel:SetTextColor(unpack(UI.colors.text))

    local notIntColorBtn = UI:CreateColorButton(panel, "", self.db.notInterruptibleColor, function(r, g, b)
        self.db.notInterruptibleColor = { r, g, b }
    end)
    notIntColorBtn:SetPoint("LEFT", notIntColorLabel, "RIGHT", 10, 0)
    yOffset = yOffset - 30

    -- 쿨다운 색상
    local cdColorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cdColorLabel:SetPoint("TOPLEFT", 15, yOffset)
    cdColorLabel:SetText(L["FOCUSINTERRUPT_CD_COLOR"])
    cdColorLabel:SetTextColor(unpack(UI.colors.text))

    local cdColorBtn = UI:CreateColorButton(panel, "", self.db.cooldownColor, function(r, g, b)
        self.db.cooldownColor = { r, g, b }
    end)
    cdColorBtn:SetPoint("LEFT", cdColorLabel, "RIGHT", 10, 0)
    yOffset = yOffset - 30

    -- 차단됨 색상
    local intdColorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    intdColorLabel:SetPoint("TOPLEFT", 15, yOffset)
    intdColorLabel:SetText(L["FOCUSINTERRUPT_INTERRUPTED_COLOR"])
    intdColorLabel:SetTextColor(unpack(UI.colors.text))

    local intdColorBtn = UI:CreateColorButton(panel, "", self.db.interruptedColor, function(r, g, b)
        self.db.interruptedColor = { r, g, b }
    end)
    intdColorBtn:SetPoint("LEFT", intdColorLabel, "RIGHT", 10, 0)
    yOffset = yOffset - 40

    -- ===== 버튼 =====
    local testBtn = UI:CreateButton(panel, 140, 35, L["TEST_ON_OFF"])
    testBtn:SetPoint("TOPLEFT", 15, yOffset)
    testBtn:SetScript("OnClick", function()
        self:TestMode()
    end)

    local resetPosBtn = UI:CreateButton(panel, 140, 35, L["RESET_POSITION"])
    resetPosBtn:SetPoint("LEFT", testBtn, "RIGHT", 20, 0)
    resetPosBtn:SetScript("OnClick", function()
        self:ResetPosition()
        print("|cFF00FF00[DDingUI Toolkit]|r " .. L["POSITION_RESET"])
    end)

    return scrollContainer
end
