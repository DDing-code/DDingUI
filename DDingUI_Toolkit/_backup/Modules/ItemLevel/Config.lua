--[[
    DDingToolKit - ItemLevel Config
    Item Level Module Settings Panel (with scroll)
]]

local addonName, ns = ...
local UI = ns.UI
local DDingToolKit = ns.DDingToolKit
local L = ns.L

local ItemLevel = DDingToolKit:GetModule("ItemLevel")
if not ItemLevel then return end

-- Create settings panel
function ItemLevel:CreateConfigPanel(parent)
    local scrollContainer = UI:CreateScrollablePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20, 650)
    scrollContainer:SetPoint("TOPLEFT", 10, -10)

    local panel = scrollContainer.content
    local db = self.db

    local yOffset = -10

    -- Display Settings Section
    local displayHeader = UI:CreateSectionHeader(panel, L["ITEMLEVEL_DISPLAY_SETTINGS"])
    displayHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Show item level
    local ilvlCheckbox = UI:CreateCheckbox(panel, L["ITEMLEVEL_SHOW_ILVL"], function(checked)
        db.showItemLevel = checked
        self:Refresh()
    end)
    ilvlCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    ilvlCheckbox:SetChecked(db.showItemLevel)
    yOffset = yOffset - 30

    -- Show enchant
    local enchCheckbox = UI:CreateCheckbox(panel, L["ITEMLEVEL_SHOW_ENCHANT"], function(checked)
        db.showEnchant = checked
        self:Refresh()
    end)
    enchCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    enchCheckbox:SetChecked(db.showEnchant)
    yOffset = yOffset - 30

    -- Show gems
    local gemCheckbox = UI:CreateCheckbox(panel, L["ITEMLEVEL_SHOW_GEMS"], function(checked)
        db.showGems = checked
        self:Refresh()
    end)
    gemCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    gemCheckbox:SetChecked(db.showGems)
    yOffset = yOffset - 30

    -- Show average item level
    local avgCheckbox = UI:CreateCheckbox(panel, L["ITEMLEVEL_SHOW_AVG"], function(checked)
        db.showAverageIlvl = checked
        self:Refresh()
    end)
    avgCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    avgCheckbox:SetChecked(db.showAverageIlvl)
    yOffset = yOffset - 30

    -- Show enhanced stats
    local statCheckbox = UI:CreateCheckbox(panel, L["ITEMLEVEL_SHOW_ENHANCED"], function(checked)
        db.showEnhancedStats = checked
        self:Refresh()
    end)
    statCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    statCheckbox:SetChecked(db.showEnhancedStats)
    yOffset = yOffset - 40

    -- Your Character Settings Section
    local selfHeader = UI:CreateSectionHeader(panel, L["ITEMLEVEL_SELF_SETTINGS"])
    selfHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Item level font size
    local selfIlvlSlider = UI:CreateSlider(panel, L["ITEMLEVEL_SELF_ILVL_SIZE"], 8, 20, 1, function(value)
        db.selfIlvlSize = value
        ItemLevel:Refresh()
    end)
    selfIlvlSlider:SetPoint("TOPLEFT", 15, yOffset)
    selfIlvlSlider:SetValue(db.selfIlvlSize)
    yOffset = yOffset - 55

    -- Enchant font size
    local selfEnchSlider = UI:CreateSlider(panel, L["ITEMLEVEL_SELF_ENCHANT_SIZE"], 8, 16, 1, function(value)
        db.selfEnchantSize = value
        ItemLevel:Refresh()
    end)
    selfEnchSlider:SetPoint("TOPLEFT", 15, yOffset)
    selfEnchSlider:SetValue(db.selfEnchantSize)
    yOffset = yOffset - 55

    -- Gem icon size
    local selfGemSlider = UI:CreateSlider(panel, L["ITEMLEVEL_SELF_GEM_SIZE"], 10, 24, 1, function(value)
        db.selfGemSize = value
        ItemLevel:Refresh()
    end)
    selfGemSlider:SetPoint("TOPLEFT", 15, yOffset)
    selfGemSlider:SetValue(db.selfGemSize)
    yOffset = yOffset - 55

    -- Average item level size
    local selfAvgSlider = UI:CreateSlider(panel, L["ITEMLEVEL_SELF_AVG_SIZE"], 12, 24, 1, function(value)
        db.selfAvgSize = value
        ItemLevel:Refresh()
    end)
    selfAvgSlider:SetPoint("TOPLEFT", 15, yOffset)
    selfAvgSlider:SetValue(db.selfAvgSize)
    yOffset = yOffset - 55

    -- Inspect Settings Section
    local inspHeader = UI:CreateSectionHeader(panel, L["ITEMLEVEL_INSPECT_SETTINGS"])
    inspHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Inspect item level font size
    local inspIlvlSlider = UI:CreateSlider(panel, L["ITEMLEVEL_INSPECT_ILVL_SIZE"], 8, 20, 1, function(value)
        db.inspIlvlSize = value
    end)
    inspIlvlSlider:SetPoint("TOPLEFT", 15, yOffset)
    inspIlvlSlider:SetValue(db.inspIlvlSize)
    yOffset = yOffset - 55

    -- Inspect enchant font size
    local inspEnchSlider = UI:CreateSlider(panel, L["ITEMLEVEL_INSPECT_ENCHANT_SIZE"], 8, 16, 1, function(value)
        db.inspEnchantSize = value
    end)
    inspEnchSlider:SetPoint("TOPLEFT", 15, yOffset)
    inspEnchSlider:SetValue(db.inspEnchantSize)
    yOffset = yOffset - 55

    -- Inspect gem icon size
    local inspGemSlider = UI:CreateSlider(panel, L["ITEMLEVEL_INSPECT_GEM_SIZE"], 10, 24, 1, function(value)
        db.inspGemSize = value
    end)
    inspGemSlider:SetPoint("TOPLEFT", 15, yOffset)
    inspGemSlider:SetValue(db.inspGemSize)
    yOffset = yOffset - 60

    -- Reset to default button
    local resetBtn = UI:CreateButton(panel, 150, 28, L["RESET_TO_DEFAULT"])
    resetBtn:SetPoint("TOPLEFT", 15, yOffset)
    resetBtn:SetScript("OnClick", function()
        -- Reset to defaults
        local defaults = ns.defaults.profile.ItemLevel
        for key, value in pairs(defaults) do
            db[key] = value
        end

        -- Update UI
        ilvlCheckbox:SetChecked(db.showItemLevel)
        enchCheckbox:SetChecked(db.showEnchant)
        gemCheckbox:SetChecked(db.showGems)
        avgCheckbox:SetChecked(db.showAverageIlvl)
        statCheckbox:SetChecked(db.showEnhancedStats)
        selfIlvlSlider:SetValue(db.selfIlvlSize)
        selfEnchSlider:SetValue(db.selfEnchantSize)
        selfGemSlider:SetValue(db.selfGemSize)
        selfAvgSlider:SetValue(db.selfAvgSize)
        inspIlvlSlider:SetValue(db.inspIlvlSize)
        inspEnchSlider:SetValue(db.inspEnchantSize)
        inspGemSlider:SetValue(db.inspGemSize)

        self:Refresh()
        print("|cFF00CCFFDDingUI Toolkit:|r " .. L["ITEMLEVEL_RESET_MSG"])
    end)

    return scrollContainer
end
