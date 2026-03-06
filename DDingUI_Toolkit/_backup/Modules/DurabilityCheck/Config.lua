--[[
    DDingToolKit - DurabilityCheck Config
    Durability Check Settings Panel
]]

local addonName, ns = ...
local UI = ns.UI
local DurabilityCheck = ns.DurabilityCheck
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = SL and SL.Font.path or "Fonts\\2002.TTF" -- [12.0.1]

-- Get sound options from MediaLibrary
local function GetSoundOptions()
    return ns:GetSoundOptions(true, L["ANIM_NONE"], "")
end

local channelOptions = {
    { text = L["CHANNEL_MASTER"], value = "Master" },
    { text = L["CHANNEL_SFX"], value = "SFX" },
    { text = L["CHANNEL_MUSIC"], value = "Music" },
}

-- Create settings panel
function DurabilityCheck:CreateConfigPanel(parent)
    local panel = UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)

    local leftCol = 10
    local rightCol = 400
    local yOffset = -10

    -- ===== Basic Settings =====
    local header = UI:CreateSectionHeader(panel, L["DURABILITY_TITLE"])
    header:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 35

    -- Description
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    desc:SetText(L["DURABILITY_DESC_FULL"])
    desc:SetTextColor(unpack(UI.colors.textDim))
    yOffset = yOffset - 70

    -- ===== Display Conditions =====
    local condHeader = UI:CreateSectionHeader(panel, L["DURABILITY_DISPLAY_CONDITIONS"])
    condHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Threshold slider
    local thresholdSlider = UI:CreateSlider(panel, L["DURABILITY_THRESHOLD_DESC"], 5, 100, 5, function(value)
        self.db.threshold = value
        self:CheckDurability()
    end)
    thresholdSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    thresholdSlider:SetValue(self.db.threshold or 25)
    yOffset = yOffset - 60

    local thresholdNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thresholdNote:SetPoint("TOPLEFT", leftCol + 5, yOffset + 10)
    thresholdNote:SetText(L["DURABILITY_THRESHOLD_NOTE"])
    thresholdNote:SetTextColor(0.6, 0.6, 0.6)
    yOffset = yOffset - 30

    -- ===== Alert Settings =====
    local alertHeader = UI:CreateSectionHeader(panel, L["DURABILITY_ALERT_SETTINGS"])
    alertHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Sound alert
    local soundCheck = UI:CreateCheckbox(panel, L["DURABILITY_SOUND_DESC"], function(checked)
        self.db.soundEnabled = checked
    end)
    soundCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    soundCheck:SetChecked(self.db.soundEnabled)
    yOffset = yOffset - 35

    -- Lock position
    local lockCheck = UI:CreateCheckbox(panel, L["POSITION_LOCKED"], function(checked)
        self.db.locked = checked
        self:UpdateLock()
    end)
    lockCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    lockCheck:SetChecked(self.db.locked)
    yOffset = yOffset - 50

    -- Sound selection
    local soundLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soundLabel:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    soundLabel:SetText(L["LFGALERT_SOUND_FILE"])
    soundLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 25

    local soundDropdown = UI:CreateSoundDropdown(panel, 280, GetSoundOptions(), function(value)
        self.db.soundFile = value
    end)
    soundDropdown:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    soundDropdown:SetValue(self.db.soundFile or "")

    -- ===== Right Column =====
    local rightYOffset = -10

    -- ===== Screen Settings =====
    local screenHeader = UI:CreateSectionHeader(panel, L["DURABILITY_SCREEN_SETTINGS"])
    screenHeader:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 30

    -- Scale
    local scaleSlider = UI:CreateSlider(panel, L["ALERT_SIZE"], 0.5, 2.0, 0.1, function(value)
        self.db.scale = value
        self:ApplyPosition()
    end)
    scaleSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    scaleSlider:SetValue(self.db.scale or 1.0)
    rightYOffset = rightYOffset - 60

    -- Title size
    local titleSlider = UI:CreateSlider(panel, L["TITLE_SIZE"], 14, 48, 2, function(value)
        self.db.titleSize = value
        if self.alertFrame and self.alertFrame.title then
            self.alertFrame.title:SetFont(self.db.font or SL_FONT, value, "OUTLINE") -- [12.0.1]
        end
    end)
    titleSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    titleSlider:SetValue(self.db.titleSize or 24)
    rightYOffset = rightYOffset - 60

    -- Percent size
    local percentSlider = UI:CreateSlider(panel, L["PERCENT_SIZE"], 20, 72, 2, function(value)
        self.db.percentSize = value
        if self.alertFrame and self.alertFrame.percent then
            self.alertFrame.percent:SetFont(self.db.font or SL_FONT, value, "OUTLINE") -- [12.0.1]
        end
    end)
    percentSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    percentSlider:SetValue(self.db.percentSize or 36)
    rightYOffset = rightYOffset - 70

    -- Reset position button
    local resetPosBtn = UI:CreateButton(panel, 120, 28, L["RESET_POSITION"])
    resetPosBtn:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    resetPosBtn:SetScript("OnClick", function()
        self.db.position = nil
        self:ApplyPosition()
        print("|cFF00CCFF[DDingUI Toolkit]|r " .. L["DURABILITY_POSITION_RESET_MSG"])
    end)
    rightYOffset = rightYOffset - 50

    -- Drag tip
    local dragNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragNote:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    dragNote:SetText(L["DURABILITY_DRAG_TIP"])
    dragNote:SetTextColor(0.7, 0.7, 0.7)

    -- Test alert button
    local testBtn = UI:CreateButton(panel, 150, 35, L["TEST_ALERT"])
    testBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)
    testBtn:SetScript("OnClick", function()
        self:TestAlert()
    end)

    return panel
end
