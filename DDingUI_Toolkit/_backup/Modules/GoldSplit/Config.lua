--[[
    DDingToolKit - GoldSplit Config
    GoldSplit Settings Panel
]]

local addonName, ns = ...
local UI = ns.UI
local GoldSplit = ns.GoldSplit
local L = ns.L

local chatOptions = {
    { text = L["GOLDSPLIT_SAY"], value = "SAY" },
    { text = L["GOLDSPLIT_PARTY"], value = "PARTY" },
    { text = L["GOLDSPLIT_RAID"], value = "RAID" },
}

-- Create settings panel
function GoldSplit:CreateConfigPanel(parent)
    local panel = UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)

    local yOffset = -10

    -- ===== Basic Settings =====
    local header = UI:CreateSectionHeader(panel, L["GOLDSPLIT_TITLE_FULL"])
    header:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 40

    -- Description
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", 15, yOffset)
    desc:SetWidth(400)
    desc:SetJustifyH("LEFT")
    desc:SetText(L["GOLDSPLIT_DESC_FULL"])
    desc:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 120

    -- ===== Chat Settings =====
    local chatHeader = UI:CreateSectionHeader(panel, L["CHAT_SETTINGS"])
    chatHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Chat channel
    local chatLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatLabel:SetPoint("TOPLEFT", 15, yOffset)
    chatLabel:SetText(L["GOLDSPLIT_DEFAULT_CHANNEL"])
    chatLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 25

    local chatDropdown = UI:CreateDropdown(panel, 150, chatOptions, function(value)
        self.db.chatType = value
    end)
    chatDropdown:SetPoint("TOPLEFT", 15, yOffset)
    chatDropdown:SetValue(self.db.chatType or "SAY")
    yOffset = yOffset - 50

    -- Note
    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", 15, yOffset)
    note:SetText(L["GOLDSPLIT_NOTE"])
    note:SetTextColor(0.7, 0.7, 0.7)
    yOffset = yOffset - 40

    -- ===== Position Settings =====
    local posHeader = UI:CreateSectionHeader(panel, L["GOLDSPLIT_POSITION_SETTINGS"])
    posHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- Lock position
    local lockCheck = UI:CreateCheckbox(panel, L["POSITION_LOCKED"], function(checked)
        self.db.locked = checked
    end)
    lockCheck:SetPoint("TOPLEFT", 15, yOffset)
    lockCheck:SetChecked(self.db.locked)
    yOffset = yOffset - 35

    -- Reset position button
    local resetPosBtn = UI:CreateButton(panel, 120, 28, L["RESET_POSITION"])
    resetPosBtn:SetPoint("TOPLEFT", 15, yOffset)
    resetPosBtn:SetScript("OnClick", function()
        self.db.position = nil
        self:ApplyPosition()
        print("|cFFFFA500[GoldSplit]|r " .. L["GOLDSPLIT_POSITION_RESET_MSG"])
    end)
    yOffset = yOffset - 50

    -- Drag tip
    local dragNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragNote:SetPoint("TOPLEFT", 15, yOffset)
    dragNote:SetText(L["GOLDSPLIT_DRAG_TIP"])
    dragNote:SetTextColor(0.7, 0.7, 0.7)

    -- Open window button
    local openBtn = UI:CreateButton(panel, 160, 40, L["GOLDSPLIT_OPEN_WINDOW"])
    openBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)
    openBtn:SetBackdropColor(unpack(UI.colors.accent))
    openBtn.text:SetTextColor(1, 1, 1)
    openBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
        self:SetBackdropColor(unpack(UI.colors.accentHover))
    end)
    openBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
        self:SetBackdropColor(unpack(UI.colors.accent))
    end)
    openBtn:SetScript("OnClick", function()
        GoldSplit:Show()
        ns.ConfigUI:Hide() -- [REFACTOR] ns.MainFrame → ns.ConfigUI
    end)

    return panel
end
