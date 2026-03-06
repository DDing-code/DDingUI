--[[
    DDingToolKit - AutoRepair Config
    Auto Repair Settings Panel
]]

local addonName, ns = ...
local UI = ns.UI
local AutoRepair = ns.AutoRepair
local L = ns.L

-- Create settings panel
function AutoRepair:CreateConfigPanel(parent)
    local panel = UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)

    local leftCol = 10
    local yOffset = -10

    -- 제목
    local header = UI:CreateSectionHeader(panel, L["AUTOREPAIR_TITLE"])
    header:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 35

    -- 설명
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    desc:SetText(L["AUTOREPAIR_DESC"])
    desc:SetTextColor(unpack(UI.colors.textDim))
    yOffset = yOffset - 40

    -- 길드 금고 사용
    local guildCheck = UI:CreateCheckbox(panel, L["AUTOREPAIR_USE_GUILD_BANK"], function(checked)
        self.db.useGuildBank = checked
    end)
    guildCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    guildCheck:SetChecked(self.db.useGuildBank)
    yOffset = yOffset - 25

    -- 길드 금고 설명
    local guildNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    guildNote:SetPoint("TOPLEFT", leftCol + 30, yOffset)
    guildNote:SetText(L["AUTOREPAIR_GUILD_BANK_NOTE"])
    guildNote:SetTextColor(0.6, 0.6, 0.6)
    yOffset = yOffset - 35

    -- 채팅 출력
    local chatCheck = UI:CreateCheckbox(panel, L["AUTOREPAIR_CHAT_OUTPUT"], function(checked)
        self.db.chatOutput = checked
    end)
    chatCheck:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    chatCheck:SetChecked(self.db.chatOutput)

    return panel
end
