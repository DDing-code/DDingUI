--[[
    DDingToolKit - LFGAlert Config
    LFGAlert Settings Panel
]]

local addonName, ns = ...
local UI = ns.UI
local LFGAlert = ns.LFGAlert
local L = ns.L

-- Get sound options from MediaLibrary
local function GetSoundOptions()
    return ns:GetSoundOptions(true, L["LFGALERT_DEFAULT_SOUND"] or "Ready Check (Default)", "")
end

local channelOptions = {
    { text = L["CHANNEL_MASTER"], value = "Master" },
    { text = L["CHANNEL_SFX"], value = "SFX" },
    { text = L["CHANNEL_MUSIC"], value = "Music" },
    { text = L["CHANNEL_AMBIENCE"], value = "Ambience" },
}

local positionOptions = {
    { text = L["POS_TOP"], value = "TOP" },
    { text = L["POS_CENTER"], value = "CENTER" },
    { text = L["POS_BOTTOM"], value = "BOTTOM" },
}

local animationOptions = {
    { text = L["ANIM_BOUNCE"], value = "bounce" },
    { text = L["ANIM_FADE"], value = "fade" },
    { text = L["ANIM_NONE"], value = "none" },
}

-- Create settings panel
function LFGAlert:CreateConfigPanel(parent)
    local panel = UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)

    local leftCol = 10
    local rightCol = 400
    local yOffset = -10

    -- ===== Alert Method =====
    local alertHeader = UI:CreateSectionHeader(panel, L["ALERT_METHOD"])
    alertHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Sound alert
    local soundCheckbox = UI:CreateCheckbox(panel, L["LFGALERT_SOUND_ENABLED"], function(checked)
        self.db.soundEnabled = checked
    end)
    soundCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    soundCheckbox:SetChecked(self.db.soundEnabled)
    yOffset = yOffset - 30

    -- Screen flash
    local flashCheckbox = UI:CreateCheckbox(panel, L["FLASH_TASKBAR"], function(checked)
        self.db.flashEnabled = checked
    end)
    flashCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    flashCheckbox:SetChecked(self.db.flashEnabled)
    yOffset = yOffset - 30

    -- Screen alert
    local screenCheckbox = UI:CreateCheckbox(panel, L["LFGALERT_SCREEN_DESC"], function(checked)
        self.db.screenAlertEnabled = checked
    end)
    screenCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    screenCheckbox:SetChecked(self.db.screenAlertEnabled)
    yOffset = yOffset - 30

    -- Chat alert
    local chatCheckbox = UI:CreateCheckbox(panel, L["LFGALERT_CHAT_DESC"], function(checked)
        self.db.chatAlert = checked
    end)
    chatCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    chatCheckbox:SetChecked(self.db.chatAlert)
    yOffset = yOffset - 30

    -- Auto open LFG
    local autoOpenCheckbox = UI:CreateCheckbox(panel, L["LFGALERT_AUTO_OPEN_DESC"], function(checked)
        self.db.autoOpenLFG = checked
    end)
    autoOpenCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    autoOpenCheckbox:SetChecked(self.db.autoOpenLFG)
    yOffset = yOffset - 50

    -- ===== Sound Settings =====
    local soundHeader = UI:CreateSectionHeader(panel, L["SOUND_SETTINGS"])
    soundHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

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
    soundDropdown:SetValue(self.db.soundFile)
    panel.soundDropdown = soundDropdown
    yOffset = yOffset - 40

    -- Channel selection
    local channelLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelLabel:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    channelLabel:SetText(L["LFGALERT_SOUND_CHANNEL"])
    channelLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 25

    local channelDropdown = UI:CreateDropdown(panel, 150, channelOptions, function(value)
        self.db.soundChannel = value
    end)
    channelDropdown:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    channelDropdown:SetValue(self.db.soundChannel)

    -- ===== Right Column =====
    local rightYOffset = -10

    -- ===== Screen Alert Settings =====
    local screenHeader = UI:CreateSectionHeader(panel, L["SCREEN_ALERT_SETTINGS"])
    screenHeader:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 30

    -- Position
    local posLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    posLabel:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    posLabel:SetText(L["ALERT_POSITION"])
    posLabel:SetTextColor(unpack(UI.colors.text))
    rightYOffset = rightYOffset - 25

    local posDropdown = UI:CreateDropdown(panel, 150, positionOptions, function(value)
        self.db.alertPosition = value
    end)
    posDropdown:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    posDropdown:SetValue(self.db.alertPosition)
    rightYOffset = rightYOffset - 40

    -- Animation
    local animLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    animLabel:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    animLabel:SetText(L["ANIMATION"])
    animLabel:SetTextColor(unpack(UI.colors.text))
    rightYOffset = rightYOffset - 25

    local animDropdown = UI:CreateDropdown(panel, 150, animationOptions, function(value)
        self.db.alertAnimation = value
    end)
    animDropdown:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    animDropdown:SetValue(self.db.alertAnimation)
    rightYOffset = rightYOffset - 40

    -- Scale
    local scaleSlider = UI:CreateSlider(panel, L["ALERT_SIZE"], 0.5, 2.0, 0.1, function(value)
        self.db.alertScale = value
    end)
    scaleSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    scaleSlider:SetValue(self.db.alertScale)
    rightYOffset = rightYOffset - 60

    -- Duration
    local durationSlider = UI:CreateSlider(panel, L["DISPLAY_DURATION"], 1, 15, 1, function(value)
        self.db.alertDuration = value
    end)
    durationSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    durationSlider:SetValue(self.db.alertDuration)
    rightYOffset = rightYOffset - 70

    -- ===== Conditions =====
    local conditionHeader = UI:CreateSectionHeader(panel, L["CONDITIONS"])
    conditionHeader:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 30

    -- Leader only
    local leaderCheckbox = UI:CreateCheckbox(panel, L["LFGALERT_LEADER_ONLY_DESC"], function(checked)
        self.db.leaderOnly = checked
    end)
    leaderCheckbox:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    leaderCheckbox:SetChecked(self.db.leaderOnly)
    rightYOffset = rightYOffset - 40

    -- Cooldown
    local cooldownSlider = UI:CreateSlider(panel, L["ALERT_COOLDOWN"], 0, 10, 1, function(value)
        self.db.cooldown = value
    end)
    cooldownSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    cooldownSlider:SetValue(self.db.cooldown)

    -- Test alert button
    local testAlertBtn = UI:CreateButton(panel, 150, 35, L["TEST_ALERT"])
    testAlertBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)
    testAlertBtn:SetScript("OnClick", function()
        self:TriggerAlert(1, true)
    end)

    return panel
end
