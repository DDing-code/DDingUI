--[[
    DDingToolKit - CastingAlert Config
    적 시전 알림 설정 패널
]]

local addonName, ns = ...
local UI = ns.UI
local CastingAlert = ns.CastingAlert
local L = ns.L

local function GetSoundOptions()
    return ns:GetSoundOptions(true, L["CASTINGALERT_DEFAULT_SOUND"] or "Raid Warning (Default)", "")
end

function CastingAlert:CreateConfigPanel(parent)
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.CastingAlert then
            self.db = ns.db.profile.CastingAlert
        else
            return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
        end
    end

    local scrollContainer = UI:CreateScrollablePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20, 800)
    scrollContainer:SetPoint("TOPLEFT", 10, -10)

    local panel = scrollContainer.content
    local yOffset = -10

    -- 설명
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", 10, yOffset)
    desc:SetText(L["CASTINGALERT_DESC"])
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetWidth(panel:GetWidth() - 30)
    desc:SetJustifyH("LEFT")
    yOffset = yOffset - 40

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

    -- ===== 표시 설정 =====
    local displayHeader = UI:CreateSectionHeader(panel, L["CASTINGALERT_DISPLAY_SETTINGS"])
    displayHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- 나를 대상으로 하는 스킬만 표시
    local onlyMeCheckbox = UI:CreateCheckbox(panel, L["CASTINGALERT_ONLY_TARGETING_ME"], function(checked)
        self.db.onlyTargetingMe = checked
    end)
    onlyMeCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    onlyMeCheckbox:SetChecked(self.db.onlyTargetingMe)
    yOffset = yOffset - 30

    -- 타겟 시전도 표시
    local showTargetCheckbox = UI:CreateCheckbox(panel, L["CASTINGALERT_SHOW_TARGET"], function(checked)
        self.db.showTarget = checked
    end)
    showTargetCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    showTargetCheckbox:SetChecked(self.db.showTarget)
    yOffset = yOffset - 30

    -- 최대 표시 수
    local maxShowSlider = UI:CreateSlider(panel, L["CASTINGALERT_MAX_SHOW"], 1, 15, 1, function(value)
        self.db.maxShow = value
    end)
    maxShowSlider:SetPoint("TOPLEFT", 15, yOffset)
    maxShowSlider:SetValue(self.db.maxShow or 10)
    yOffset = yOffset - 55

    -- 아이콘 크기
    local iconSizeSlider = UI:CreateSlider(panel, L["ICON_SIZE"], 20, 80, 1, function(value)
        self.db.iconSize = value
        self:UpdateStyle()
    end)
    iconSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
    iconSizeSlider:SetValue(self.db.iconSize or 35)
    yOffset = yOffset - 55

    -- 글꼴 크기
    local fontSizeSlider = UI:CreateSlider(panel, L["FONT_SIZE"], 10, 30, 1, function(value)
        self.db.fontSize = value
        self:UpdateStyle()
    end)
    fontSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
    fontSizeSlider:SetValue(self.db.fontSize or 18)
    yOffset = yOffset - 55

    -- 비타겟 투명도
    local dimAlphaSlider = UI:CreateSlider(panel, L["CASTINGALERT_DIM_ALPHA"], 0, 1, 0.1, function(value)
        self.db.dimAlpha = value
    end)
    dimAlphaSlider:SetPoint("TOPLEFT", 15, yOffset)
    dimAlphaSlider:SetValue(self.db.dimAlpha or 0.4)
    yOffset = yOffset - 55

    -- 전체 크기
    local scaleSlider = UI:CreateSlider(panel, L["OVERALL_SIZE"], 0.5, 2.0, 0.1, function(value)
        self.db.scale = value
        self:UpdateStyle()
    end)
    scaleSlider:SetPoint("TOPLEFT", 15, yOffset)
    scaleSlider:SetValue(self.db.scale or 1.0)
    yOffset = yOffset - 55

    -- 업데이트 주기
    local rateSlider = UI:CreateSlider(panel, L["CASTINGALERT_UPDATE_RATE"], 0.1, 0.5, 0.05, function(value)
        self.db.updateRate = value
    end)
    rateSlider:SetPoint("TOPLEFT", 15, yOffset)
    rateSlider:SetValue(self.db.updateRate or 0.2)
    yOffset = yOffset - 70

    -- ===== 사운드 설정 =====
    local soundHeader = UI:CreateSectionHeader(panel, L["CASTINGALERT_SOUND_SETTINGS"])
    soundHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- 동시 시전 사운드 알림
    local soundCheckbox = UI:CreateCheckbox(panel, L["CASTINGALERT_SOUND_ENABLED"], function(checked)
        self.db.soundEnabled = checked
    end)
    soundCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    soundCheckbox:SetChecked(self.db.soundEnabled)
    yOffset = yOffset - 35

    -- 사운드 기준 개수
    local thresholdSlider = UI:CreateSlider(panel, L["CASTINGALERT_SOUND_THRESHOLD"], 1, 5, 1, function(value)
        self.db.soundThreshold = value
    end)
    thresholdSlider:SetPoint("TOPLEFT", 15, yOffset)
    thresholdSlider:SetValue(self.db.soundThreshold or 2)
    yOffset = yOffset - 55

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
