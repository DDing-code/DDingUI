--[[
    DDingToolKit - CombatTimer Config
    Combat Timer Settings Panel (with scroll)
]]

local addonName, ns = ...
local UI = ns.UI
local CombatTimer = ns.CombatTimer
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = SL and SL.Font.path or "Fonts\\2002.TTF" -- [12.0.1]

-- Font list (from LibSharedMedia)
local function GetFontOptions()
    return ns:GetFontOptions()
end

-- Sound list
local function GetSoundOptions()
    return ns:GetSoundOptions(true, L["ANIM_NONE"], "")
end

-- Alignment options
local alignOptions = {
    { text = L["ALIGN_LEFT"], value = "LEFT" },
    { text = L["ALIGN_CENTER"], value = "CENTER" },
    { text = L["ALIGN_RIGHT"], value = "RIGHT" },
}

-- Create settings panel
function CombatTimer:CreateConfigPanel(parent)
    local scrollContainer = UI:CreateScrollablePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20, 700)
    scrollContainer:SetPoint("TOPLEFT", 10, -10)

    local panel = scrollContainer.content
    local yOffset = -10

    -- ===== Display Settings =====
    local displayHeader = UI:CreateSectionHeader(panel, L["COMBATTIMER_DISPLAY_SETTINGS"])
    displayHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Show milliseconds
    local msCheckbox = UI:CreateCheckbox(panel, L["COMBATTIMER_SHOW_MS"], function(checked)
        self.db.showMilliseconds = checked
        self:UpdateFrameStyle()
    end)
    msCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    msCheckbox:SetChecked(self.db.showMilliseconds)
    yOffset = yOffset - 30

    -- Show background
    local bgCheckbox = UI:CreateCheckbox(panel, L["COMBATTIMER_SHOW_BG"], function(checked)
        self.db.showBackground = checked
        self:UpdateFrameStyle()
    end)
    bgCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    bgCheckbox:SetChecked(self.db.showBackground)
    yOffset = yOffset - 30

    -- Color by time
    local colorTimeCheckbox = UI:CreateCheckbox(panel, L["COMBATTIMER_COLOR_BY_TIME"], function(checked)
        self.db.colorByTime = checked
    end)
    colorTimeCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    colorTimeCheckbox:SetChecked(self.db.colorByTime)
    yOffset = yOffset - 30

    -- Lock position
    local lockCheckbox = UI:CreateCheckbox(panel, L["POSITION_LOCKED"], function(checked)
        self.db.locked = checked
    end)
    lockCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    lockCheckbox:SetChecked(self.db.locked)
    yOffset = yOffset - 35

    -- Text alignment
    local alignLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alignLabel:SetPoint("TOPLEFT", 15, yOffset)
    alignLabel:SetText(L["TEXT_ALIGN"])
    alignLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 25

    local alignDropdown = UI:CreateDropdown(panel, 120, alignOptions, function(value)
        self.db.textAlign = value
        self:UpdateFrameStyle()
    end)
    alignDropdown:SetPoint("TOPLEFT", 15, yOffset)
    alignDropdown:SetValue(self.db.textAlign or "CENTER")
    yOffset = yOffset - 50

    -- ===== Font Settings =====
    local fontHeader = UI:CreateSectionHeader(panel, L["COMBATTIMER_FONT_SETTINGS"])
    fontHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Font selection
    local fontLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", 15, yOffset)
    fontLabel:SetText(L["FONT"])
    fontLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 25

    local fontDropdown = UI:CreateFontDropdown(panel, 200, GetFontOptions(), function(value)
        self.db.font = value
        self:UpdateFrameStyle()
    end)
    fontDropdown:SetPoint("TOPLEFT", 15, yOffset)
    fontDropdown:SetValue(self.db.font or SL_FONT) -- [12.0.1]
    yOffset = yOffset - 50

    -- Font size
    local fontSizeSlider = UI:CreateSlider(panel, L["FONT_SIZE"], 12, 48, 1, function(value)
        self.db.fontSize = value
        self:UpdateFrameStyle()
    end)
    fontSizeSlider:SetPoint("TOPLEFT", 15, yOffset)
    fontSizeSlider:SetValue(self.db.fontSize or 26)
    yOffset = yOffset - 55

    -- Text color
    local colorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("TOPLEFT", 15, yOffset)
    colorLabel:SetText(L["TEXT_COLOR"])
    colorLabel:SetTextColor(unpack(UI.colors.text))

    local colorBtn = UI:CreateColorButton(panel, "", self.db.textColor, function(r, g, b, a)
        self.db.textColor[1] = r
        self.db.textColor[2] = g
        self.db.textColor[3] = b
        self.db.textColor[4] = a or 1
        self:UpdateFrameStyle()
    end)
    colorBtn:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
    yOffset = yOffset - 40

    -- Overall size
    local scaleSlider = UI:CreateSlider(panel, L["OVERALL_SIZE"], 0.5, 2.0, 0.1, function(value)
        self.db.scale = value
        self:UpdateFrameStyle()
    end)
    scaleSlider:SetPoint("TOPLEFT", 15, yOffset)
    scaleSlider:SetValue(self.db.scale or 1.0)
    yOffset = yOffset - 55

    -- Background opacity
    local bgAlphaSlider = UI:CreateSlider(panel, L["BACKGROUND_ALPHA"], 0, 1, 0.1, function(value)
        self.db.bgAlpha = value
        self:UpdateFrameStyle()
    end)
    bgAlphaSlider:SetPoint("TOPLEFT", 15, yOffset)
    bgAlphaSlider:SetValue(self.db.bgAlpha or 0.5)
    yOffset = yOffset - 55

    -- ===== Alert Settings =====
    local alertHeader = UI:CreateSectionHeader(panel, L["COMBATTIMER_ALERT_SETTINGS"])
    alertHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Sound on combat start
    local soundStartCheckbox = UI:CreateCheckbox(panel, L["COMBATTIMER_SOUND_ON_START"], function(checked)
        self.db.soundOnStart = checked
    end)
    soundStartCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    soundStartCheckbox:SetChecked(self.db.soundOnStart)
    yOffset = yOffset - 30

    -- Print to chat
    local printChatCheckbox = UI:CreateCheckbox(panel, L["COMBATTIMER_PRINT_TO_CHAT"], function(checked)
        self.db.printToChat = checked
    end)
    printChatCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    printChatCheckbox:SetChecked(self.db.printToChat)
    yOffset = yOffset - 50

    -- ===== Timing Settings =====
    local timingHeader = UI:CreateSectionHeader(panel, L["COMBATTIMER_TIMING_SETTINGS"])
    timingHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Hide delay after combat ends
    local hideDelaySlider = UI:CreateSlider(panel, L["COMBATTIMER_HIDE_DELAY"], 0, 10, 1, function(value)
        self.db.hideDelay = value
    end)
    hideDelaySlider:SetPoint("TOPLEFT", 15, yOffset)
    hideDelaySlider:SetValue(self.db.hideDelay or 3)
    yOffset = yOffset - 70

    -- ===== Buttons =====
    -- Test button
    local testBtn = UI:CreateButton(panel, 140, 35, L["TEST"])
    testBtn:SetPoint("TOPLEFT", 15, yOffset)
    testBtn:SetScript("OnClick", function()
        self:TestTimer()
    end)

    -- Reset position button
    local resetPosBtn = UI:CreateButton(panel, 140, 35, L["RESET_POSITION"])
    resetPosBtn:SetPoint("LEFT", testBtn, "RIGHT", 20, 0)
    resetPosBtn:SetScript("OnClick", function()
        self:ResetPosition()
        print("|cFF00FF00[DDingUI Toolkit]|r " .. L["COMBATTIMER_POSITION_RESET"])
    end)

    return scrollContainer
end
