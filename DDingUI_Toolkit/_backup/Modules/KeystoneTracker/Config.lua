--[[
    DDingToolKit - KeystoneTracker Config
    설정 UI
]]

local addonName, ns = ...
local KeystoneTracker = ns.KeystoneTracker
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = SL and SL.Font.path or "Fonts\\2002.TTF" -- [12.0.1]

function KeystoneTracker:CreateConfigPanel(parent)
    if not self.db then
        self.db = ns.db and ns.db.profile and ns.db.profile.KeystoneTracker
    end
    if not self.db then
        self.db = {
            locked = false,
            showInParty = true,
            showInRaid = false,
            scale = 1.0,
            font = SL_FONT, -- [12.0.1]
            fontSize = 12,
            position = {
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                x = 50,
                y = -200,
            },
        }
    end

    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()

    local yOffset = -20

    -- 타이틀
    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    title:SetText(L["KEYSTONETRACKER_TITLE"])
    yOffset = yOffset - 40

    -- 설명
    local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    desc:SetText(L["KEYSTONETRACKER_DESC"])
    desc:SetJustifyH("LEFT")
    yOffset = yOffset - 30

    -- 파티에서 표시
    local partyCheckbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    partyCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    partyCheckbox.Text:SetText(L["KEYSTONETRACKER_SHOW_IN_PARTY"])
    partyCheckbox:SetChecked(self.db.showInParty ~= false)
    partyCheckbox:SetScript("OnClick", function(self)
        KeystoneTracker.db.showInParty = self:GetChecked()
        if KeystoneTracker.UpdateVisibility then KeystoneTracker:UpdateVisibility() end
    end)
    yOffset = yOffset - 30

    -- 레이드에서 표시
    local raidCheckbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    raidCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    raidCheckbox.Text:SetText(L["KEYSTONETRACKER_SHOW_IN_RAID"])
    raidCheckbox:SetChecked(self.db.showInRaid or false)
    raidCheckbox:SetScript("OnClick", function(self)
        KeystoneTracker.db.showInRaid = self:GetChecked()
        if KeystoneTracker.UpdateVisibility then KeystoneTracker:UpdateVisibility() end
    end)
    yOffset = yOffset - 30

    -- 위치 잠금
    local lockCheckbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    lockCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    lockCheckbox.Text:SetText(L["POSITION_LOCKED"])
    lockCheckbox:SetChecked(self.db.locked or false)
    lockCheckbox:SetScript("OnClick", function(self)
        KeystoneTracker.db.locked = self:GetChecked()
    end)
    yOffset = yOffset - 40

    -- 크기 슬라이더
    local scaleLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    scaleLabel:SetText(L["SCALE"])

    local scaleSlider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 100, yOffset)
    scaleSlider:SetSize(150, 17)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetValue(self.db.scale or 1.0)
    scaleSlider.Low:SetText("0.5")
    scaleSlider.High:SetText("2.0")

    local scaleValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleValue:SetPoint("LEFT", scaleSlider, "RIGHT", 10, 0)
    scaleValue:SetText(string.format("%.1f", self.db.scale or 1.0))

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        KeystoneTracker.db.scale = value
        scaleValue:SetText(string.format("%.1f", value))
        local frame = KeystoneTracker:GetMainFrame()
        if frame then
            frame:SetScale(value)
        end
    end)
    yOffset = yOffset - 40

    -- 글꼴 크기 슬라이더
    local fontSizeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontSizeLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    fontSizeLabel:SetText(L["FONT_SIZE"])

    local fontSizeSlider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    fontSizeSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 100, yOffset)
    fontSizeSlider:SetSize(150, 17)
    fontSizeSlider:SetMinMaxValues(8, 20)
    fontSizeSlider:SetValueStep(1)
    fontSizeSlider:SetObeyStepOnDrag(true)
    fontSizeSlider:SetValue(self.db.fontSize or 12)
    fontSizeSlider.Low:SetText("8")
    fontSizeSlider.High:SetText("20")

    local fontSizeValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fontSizeValue:SetPoint("LEFT", fontSizeSlider, "RIGHT", 10, 0)
    fontSizeValue:SetText(tostring(self.db.fontSize or 12))

    fontSizeSlider:SetScript("OnValueChanged", function(self, value)
        KeystoneTracker.db.fontSize = value
        fontSizeValue:SetText(tostring(value))
    end)
    yOffset = yOffset - 50

    -- 테스트/열기 버튼
    local testButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    testButton:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    testButton:SetSize(120, 25)
    testButton:SetText(L["KEYSTONETRACKER_TOGGLE_WINDOW"])
    testButton:SetScript("OnClick", function()
        KeystoneTracker:Toggle()
    end)

    -- 위치 초기화 버튼
    local resetPosButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetPosButton:SetPoint("LEFT", testButton, "RIGHT", 10, 0)
    resetPosButton:SetSize(120, 25)
    resetPosButton:SetText(L["RESET_POSITION"])
    resetPosButton:SetScript("OnClick", function()
        self.db.position = {
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            x = 50,
            y = -200,
        }
        local frame = self:GetMainFrame()
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -200)
        end
    end)
    yOffset = yOffset - 40

    -- 사용법 안내
    local helpTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    helpTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    helpTitle:SetText(L["KEYSTONETRACKER_USAGE_TITLE"])
    yOffset = yOffset - 20

    local helpText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    helpText:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    helpText:SetWidth(350)
    helpText:SetJustifyH("LEFT")
    helpText:SetText(L["KEYSTONETRACKER_USAGE_TEXT"])

    return content
end

-- 메인 프레임 반환
function KeystoneTracker:GetMainFrame()
    return _G["DDingToolKit_KeystoneTrackerFrame"]
end
