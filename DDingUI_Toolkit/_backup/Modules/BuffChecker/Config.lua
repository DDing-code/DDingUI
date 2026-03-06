--[[
    DDingToolKit - BuffChecker Config
    버프 체크 설정 패널
]]

local addonName, ns = ...
local UI = ns.UI
local BuffChecker = ns.BuffChecker
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = SL and SL.Font.path or "Fonts\\2002.TTF" -- [12.0.1]

-- 글꼴 목록 (LibSharedMedia 사용)
local function GetFontOptions()
    return ns:GetFontOptions()
end

-- 설정 패널 생성
function BuffChecker:CreateConfigPanel(parent)
    -- DB 초기화 확인
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.BuffChecker then
            self.db = ns.db.profile.BuffChecker
        else
            self.db = {
                enabled = false,
                showFood = false,
                showFlask = false,
                showWeapon = false,
                showRune = false,
                instanceOnly = true,
                iconSize = 40,
                scale = 1.0,
                locked = false,
                showText = true,
                textSize = 10,
                textFont = SL_FONT, -- [12.0.1]
                textColor = { r = 1, g = 0.3, b = 0.3 },
                alignment = "CENTER",
                position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 },
            }
        end
    end

    local panel = UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(panel:GetWidth() - 50, 600)
    scrollFrame:SetScrollChild(scrollChild)

    local content = scrollChild
    local leftCol = 10
    local rightCol = 370
    local yOffset = -10

    -- ===== 기본 설정 =====
    local header = UI:CreateSectionHeader(content, L["BUFFCHECKER_TITLE"])
    header:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 35

    -- 설명
    local desc = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    desc:SetText(L["BUFFCHECKER_DESC"])
    desc:SetTextColor(unpack(UI.colors.textDim))
    yOffset = yOffset - 50

    -- 활성화
    local enableCheck = UI:CreateCheckbox(content, L["MODULE_ENABLED"], function(checked)
        self.db.enabled = checked
        if checked then
            self:OnEnable()
        else
            self:OnDisable()
        end
    end)
    enableCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    enableCheck:SetChecked(self.db.enabled)
    yOffset = yOffset - 35

    -- ===== 체크 항목 =====
    local checkHeader = UI:CreateSectionHeader(content, L["BUFFCHECKER_CHECK_ITEMS"])
    checkHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- 음식 체크
    local foodCheck = UI:CreateCheckbox(content, L["BUFFCHECKER_CHECK_FOOD"], function(checked)
        self.db.showFood = checked
    end)
    foodCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    foodCheck:SetChecked(self.db.showFood)
    yOffset = yOffset - 32

    -- 영약 체크
    local flaskCheck = UI:CreateCheckbox(content, L["BUFFCHECKER_CHECK_FLASK"], function(checked)
        self.db.showFlask = checked
    end)
    flaskCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    flaskCheck:SetChecked(self.db.showFlask)
    yOffset = yOffset - 32

    -- 무기 인챈트 체크
    local weaponCheck = UI:CreateCheckbox(content, L["BUFFCHECKER_CHECK_WEAPON"], function(checked)
        self.db.showWeapon = checked
    end)
    weaponCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    weaponCheck:SetChecked(self.db.showWeapon)
    yOffset = yOffset - 32

    -- 룬 체크
    local runeCheck = UI:CreateCheckbox(content, L["BUFFCHECKER_CHECK_RUNE"], function(checked)
        self.db.showRune = checked
    end)
    runeCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    runeCheck:SetChecked(self.db.showRune)
    yOffset = yOffset - 40

    -- ===== 표시 조건 =====
    local condHeader = UI:CreateSectionHeader(content, L["BUFFCHECKER_DISPLAY_CONDITIONS"])
    condHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 35

    -- 인스턴스 전용
    local instanceCheck = UI:CreateCheckbox(content, L["BUFFCHECKER_INSTANCE_ONLY"], function(checked)
        self.db.instanceOnly = checked
    end)
    instanceCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    instanceCheck:SetChecked(self.db.instanceOnly ~= false)
    yOffset = yOffset - 45

    -- 모든 옵션 활성화 버튼
    local allOnBtn = UI:CreateButton(content, 140, 26, L["ALL_CHECK_ON"])
    allOnBtn:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    allOnBtn:SetScript("OnClick", function()
        self.db.showFood = true
        self.db.showFlask = true
        self.db.showWeapon = true
        self.db.showRune = true
        foodCheck:SetChecked(true)
        flaskCheck:SetChecked(true)
        weaponCheck:SetChecked(true)
        runeCheck:SetChecked(true)
    end)

    local allOffBtn = UI:CreateButton(content, 140, 26, L["ALL_CHECK_OFF"])
    allOffBtn:SetPoint("LEFT", allOnBtn, "RIGHT", 10, 0)
    allOffBtn:SetScript("OnClick", function()
        self.db.showFood = false
        self.db.showFlask = false
        self.db.showWeapon = false
        self.db.showRune = false
        foodCheck:SetChecked(false)
        flaskCheck:SetChecked(false)
        weaponCheck:SetChecked(false)
        runeCheck:SetChecked(false)
    end)

    -- ===== 우측 컬럼 =====
    local rightYOffset = -10

    -- ===== 화면 설정 =====
    local screenHeader = UI:CreateSectionHeader(content, L["BUFFCHECKER_DISPLAY_SETTINGS"])
    screenHeader:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 35

    -- 아이콘 크기
    local iconSlider = UI:CreateSlider(content, L["ICON_SIZE"], 20, 80, 5, function(value)
        self.db.iconSize = value
        self:UpdateLayout()
    end)
    iconSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    iconSlider:SetValue(self.db.iconSize or 40)
    rightYOffset = rightYOffset - 60

    -- 전체 크기
    local scaleSlider = UI:CreateSlider(content, L["OVERALL_SIZE"], 0.5, 2.0, 0.1, function(value)
        self.db.scale = value
        local frame = self:GetMainFrame()
        if frame then
            frame:SetScale(value)
        end
    end)
    scaleSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    scaleSlider:SetValue(self.db.scale or 1.0)
    rightYOffset = rightYOffset - 60

    -- 정렬
    local alignLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alignLabel:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    alignLabel:SetText(L["TEXT_ALIGN"] or "정렬")
    alignLabel:SetTextColor(unpack(UI.colors.text))
    rightYOffset = rightYOffset - 22

    local alignDropdown = UI:CreateDropdown(content, 200, {
        { text = L["ALIGN_LEFT"] or "왼쪽", value = "LEFT" },
        { text = L["ALIGN_CENTER"] or "가운데", value = "CENTER" },
        { text = L["ALIGN_RIGHT"] or "오른쪽", value = "RIGHT" },
    })
    alignDropdown:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    alignDropdown:SetValue(self.db.alignment or "CENTER")
    alignDropdown.OnValueChanged = function(_, value)
        self.db.alignment = value
        self:UpdateLayout()
    end
    rightYOffset = rightYOffset - 45

    -- 잠금
    local lockCheck = UI:CreateCheckbox(content, L["POSITION_LOCKED"], function(checked)
        self.db.locked = checked
    end)
    lockCheck:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    lockCheck:SetChecked(self.db.locked)
    rightYOffset = rightYOffset - 40

    -- ===== 텍스트 설정 =====
    local textHeader = UI:CreateSectionHeader(content, L["BUFFCHECKER_TEXT_SETTINGS"])
    textHeader:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 35

    -- 텍스트 표시
    local showTextCheck = UI:CreateCheckbox(content, L["SHOW_TEXT"], function(checked)
        self.db.showText = checked
        self:UpdateTextSettings()
    end)
    showTextCheck:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    showTextCheck:SetChecked(self.db.showText ~= false)
    rightYOffset = rightYOffset - 35

    -- 텍스트 크기
    local textSizeSlider = UI:CreateSlider(content, L["FONT_SIZE"], 8, 20, 1, function(value)
        self.db.textSize = value
        self:UpdateTextSettings()
    end)
    textSizeSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    textSizeSlider:SetValue(self.db.textSize or 10)
    rightYOffset = rightYOffset - 60

    -- 텍스트 글꼴
    local fontLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    fontLabel:SetText(L["BUFFCHECKER_TEXT_FONT"])
    fontLabel:SetTextColor(unpack(UI.colors.text))
    rightYOffset = rightYOffset - 22

    local fontDropdown = UI:CreateDropdown(content, 200, GetFontOptions(), function(value)
        self.db.textFont = value
        self:UpdateTextSettings()
    end)
    fontDropdown:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    local currentFont = self.db.textFont or SL_FONT -- [12.0.1]
    fontDropdown:SetValue(currentFont)
    rightYOffset = rightYOffset - 40

    -- 텍스트 색상
    local color = self.db.textColor or { r = 1, g = 0.3, b = 0.3 }
    local colorBtn = UI:CreateColorButton(content, L["TEXT_COLOR"], {color.r, color.g, color.b}, function(r, g, b)
        self.db.textColor = { r = r, g = g, b = b }
        self:UpdateTextSettings()
    end)
    colorBtn:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    rightYOffset = rightYOffset - 45

    -- 위치 초기화 버튼
    local resetPosBtn = UI:CreateButton(content, 120, 26, L["RESET_POSITION"])
    resetPosBtn:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    resetPosBtn:SetScript("OnClick", function()
        self:ResetPosition()
        print("|cFF00FF00[BuffChecker]|r " .. L["POSITION_RESET"])
    end)

    -- 테스트 버튼 (토글)
    local testBtn = UI:CreateButton(content, 130, 26, L["TEST_ON_OFF"])
    testBtn:SetPoint("LEFT", resetPosBtn, "RIGHT", 10, 0)
    testBtn:SetScript("OnClick", function()
        self:TestMode()
    end)

    return panel
end
