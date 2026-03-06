--[[
    DDingToolKit - MythicPlusHelper Config
    Settings UI
]]

local addonName, ns = ...
local MythicPlusHelper = ns.MythicPlusHelper
local UI = ns.UI
local L = ns.L

function MythicPlusHelper:CreateConfigPanel(parent)
    if not self.db then
        self.db = ns.db and ns.db.profile and ns.db.profile.MythicPlusHelper
    end
    if not self.db then
        self.db = {
            enabled = true,
            showTeleports = true,
            showScore = true,
            scale = 1.0,
        }
    end

    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()

    local yOffset = -20

    -- Title
    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    title:SetText(L["MYTHICPLUS_TITLE_FULL"])
    yOffset = yOffset - 40

    -- Description
    local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    desc:SetWidth(400)
    desc:SetJustifyH("LEFT")
    desc:SetText(L["MYTHICPLUS_DESC_FULL"])
    yOffset = yOffset - 50

    -- Enable checkbox
    local enableCheckbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    enableCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    enableCheckbox.Text:SetText(L["MYTHICPLUS_ENABLE_OVERLAY"])
    enableCheckbox:SetChecked(self.db.enabled ~= false)
    enableCheckbox:SetScript("OnClick", function(btn)
        local checked = btn:GetChecked()
        MythicPlusHelper.db.enabled = checked
        MythicPlusHelper:SetOverlaysVisible(checked)
    end)
    yOffset = yOffset - 40

    -- Text size slider
    local scaleLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    scaleLabel:SetText(L["MYTHICPLUS_TEXT_SIZE"])

    local scaleSlider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 120, yOffset)
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

    scaleSlider:SetScript("OnValueChanged", function(slider, value)
        MythicPlusHelper.db.scale = value
        scaleValue:SetText(string.format("%.1f", value))
        MythicPlusHelper:SetTextScale(value)
    end)
    yOffset = yOffset - 50

    -- Open dungeon tab button
    local testButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    testButton:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    testButton:SetSize(150, 25)
    testButton:SetText(L["MYTHICPLUS_OPEN_TAB"])
    testButton:SetScript("OnClick", function()
        MythicPlusHelper:Toggle()
    end)
    yOffset = yOffset - 50

    -- Usage guide
    local helpTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    helpTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    helpTitle:SetText("|cFFFFD100" .. L["MYTHICPLUS_USAGE_TITLE"] .. ":|r")
    yOffset = yOffset - 20

    local helpText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    helpText:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
    helpText:SetWidth(400)
    helpText:SetJustifyH("LEFT")
    helpText:SetText(L["MYTHICPLUS_USAGE_TEXT"])

    return content
end
