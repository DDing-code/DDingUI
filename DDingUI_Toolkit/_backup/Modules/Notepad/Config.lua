--[[
    DDingToolKit - Notepad Config
    Notepad Module Settings Panel
]]

local addonName, ns = ...
local UI = ns.UI
local DDingToolKit = ns.DDingToolKit
local L = ns.L

local Notepad = DDingToolKit:GetModule("Notepad")
if not Notepad then return end

-- Create settings panel
function Notepad:CreateConfigPanel(parent)
    local panel = UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    local db = self.db

    local yOffset = -10

    -- Basic Settings Section
    local settingsHeader = UI:CreateSectionHeader(panel, L["NOTEPAD_BASIC_SETTINGS"])
    settingsHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Show PVE button
    local pveCheckbox = UI:CreateCheckbox(panel, L["NOTEPAD_SHOW_PVE_BUTTON"], function(checked)
        db.showPVEButton = checked
        self:UpdateSettings()
    end)
    pveCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    pveCheckbox:SetChecked(db.showPVEButton)
    yOffset = yOffset - 40

    -- Usage Section
    local usageHeader = UI:CreateSectionHeader(panel, L["USAGE"])
    usageHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 25

    local usageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    usageText:SetPoint("TOPLEFT", 15, yOffset)
    usageText:SetWidth(parent:GetWidth() - 60)
    usageText:SetJustifyH("LEFT")
    usageText:SetText(L["NOTEPAD_USAGE_TEXT"])
    usageText:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 80

    -- Quick Access Section
    local quickHeader = UI:CreateSectionHeader(panel, L["QUICK_ACCESS"])
    quickHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Open notepad button
    local openBtn = UI:CreateButton(panel, 150, 28, L["NOTEPAD_OPEN"])
    openBtn:SetPoint("TOPLEFT", 15, yOffset)
    openBtn:SetScript("OnClick", function()
        self:ToggleMainFrame()
    end)
    yOffset = yOffset - 50

    -- Saved Notes Info Section
    local infoHeader = UI:CreateSectionHeader(panel, L["SAVED_NOTES"])
    infoHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 25

    local infoText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOPLEFT", 15, yOffset)
    infoText:SetTextColor(unpack(UI.colors.textDim))

    local function UpdateMemoCount()
        local count = db.savedNotes and #db.savedNotes or 0
        infoText:SetText(string.format(L["NOTEPAD_COUNT"], count))
    end
    UpdateMemoCount()

    -- Update memo count when panel is shown
    panel:SetScript("OnShow", UpdateMemoCount)

    return panel
end
