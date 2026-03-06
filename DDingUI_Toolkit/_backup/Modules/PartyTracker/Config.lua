--[[
    DDingToolKit - PartyTracker Config
    Party Tracker Settings Panel
]]

local addonName, ns = ...
local UI = ns.UI
local PartyTracker = ns.PartyTracker
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = SL and SL.Font.path or "Fonts\\2002.TTF" -- [12.0.1]

-- Font list (LibSharedMedia)
local function GetFontOptions()
    return ns:GetFontOptions()
end

-- StatusBar texture list (LibSharedMedia)
local function GetStatusBarOptions()
    return ns:GetStatusBarOptions()
end


-- Create settings panel
function PartyTracker:CreateConfigPanel(parent)
    -- DB initialization check
    if not self.db then
        self.db = ns.db and ns.db.profile and ns.db.profile.PartyTracker
    end

    -- Use defaults if db is still nil
    if not self.db then
        self.db = {
            enabled = false,
            showInParty = false,
            showInRaid = false,
            showManaBar = false,
            showManaText = false,
            locked = false,
            iconSize = 33,
            scale = 1.0,
            font = SL_FONT, -- [12.0.1]
            fontSize = 14,
            manaBarWidth = 60,
            manaBarHeight = 10,
            manaBarOffsetX = 4,
            manaBarOffsetY = 6,
        }
    end

    -- Main container
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 0)

    -- Scroll content frame
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(parent:GetWidth() - 40, 780)
    scrollFrame:SetScrollChild(scrollChild)

    local leftCol = 10
    local rightCol = 380
    local yOffset = -10

    -- ===== Module Enable =====
    local enableHeader = UI:CreateSectionHeader(scrollChild, L["PARTYTRACKER_MODULE_ENABLE"])
    enableHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Module enable
    local enableCheckbox = UI:CreateCheckbox(scrollChild, L["PARTYTRACKER_ENABLE_DESC"], function(checked)
        self.db.enabled = checked
    end)
    enableCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    enableCheckbox:SetChecked(self.db.enabled)
    yOffset = yOffset - 40

    -- ===== Display Settings =====
    local displayHeader = UI:CreateSectionHeader(scrollChild, L["PARTYTRACKER_DISPLAY_SETTINGS"])
    displayHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Show in party
    local partyCheckbox = UI:CreateCheckbox(scrollChild, L["PARTYTRACKER_SHOW_PARTY"], function(checked)
        self.db.showInParty = checked
        self:UpdateVisibility()
    end)
    partyCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    partyCheckbox:SetChecked(self.db.showInParty)
    yOffset = yOffset - 30

    -- Show in raid
    local raidCheckbox = UI:CreateCheckbox(scrollChild, L["PARTYTRACKER_SHOW_RAID"], function(checked)
        self.db.showInRaid = checked
        self:UpdateVisibility()
    end)
    raidCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    raidCheckbox:SetChecked(self.db.showInRaid)
    yOffset = yOffset - 30

    -- Show mana bar
    local manaBarCheckbox = UI:CreateCheckbox(scrollChild, L["PARTYTRACKER_SHOW_MANA_BAR"], function(checked)
        self.db.showManaBar = checked
    end)
    manaBarCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    manaBarCheckbox:SetChecked(self.db.showManaBar)
    yOffset = yOffset - 30

    -- Show mana text
    local manaTextCheckbox = UI:CreateCheckbox(scrollChild, L["PARTYTRACKER_SHOW_MANA_TEXT"], function(checked)
        self.db.showManaText = checked
    end)
    manaTextCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    manaTextCheckbox:SetChecked(self.db.showManaText)
    yOffset = yOffset - 30

    -- Lock position
    local lockCheckbox = UI:CreateCheckbox(scrollChild, L["POSITION_LOCKED"], function(checked)
        self.db.locked = checked
    end)
    lockCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    lockCheckbox:SetChecked(self.db.locked)
    yOffset = yOffset - 40

    -- ===== Separate Mana Frame Settings =====
    local separateHeader = UI:CreateSectionHeader(scrollChild, L["PARTYTRACKER_SEPARATE_MANA"] or "힐러 마나 분리")
    separateHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Separate mana frame
    local separateCheckbox = UI:CreateCheckbox(scrollChild, L["PARTYTRACKER_SEPARATE_MANA_DESC"] or "힐러 마나를 별도 프레임으로 분리", function(checked)
        self:ToggleSeparateManaFrame(checked)
    end)
    separateCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    separateCheckbox:SetChecked(self.db.separateManaFrame)
    yOffset = yOffset - 30

    -- Mana frame lock
    local manaLockCheckbox = UI:CreateCheckbox(scrollChild, L["PARTYTRACKER_MANA_LOCKED"] or "힐러 마나 프레임 잠금", function(checked)
        self.db.manaLocked = checked
    end)
    manaLockCheckbox:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    manaLockCheckbox:SetChecked(self.db.manaLocked)
    yOffset = yOffset - 30

    -- Mana frame scale
    local manaScaleSlider = UI:CreateSlider(scrollChild, L["PARTYTRACKER_MANA_SCALE"] or "힐러 마나 프레임 크기", 0.5, 2.0, 0.1, function(value)
        self.db.manaScale = value
        local frame = self:GetManaFrame()
        if frame then
            frame:SetScale(value)
        end
    end)
    manaScaleSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    manaScaleSlider:SetValue(self.db.manaScale or 1.0)
    yOffset = yOffset - 50

    -- Reset mana position button
    local resetManaPosBtn = UI:CreateButton(scrollChild, 150, 30, L["PARTYTRACKER_MANA_POSITION_RESET"] or "마나 프레임 위치 초기화")
    resetManaPosBtn:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    resetManaPosBtn:SetScript("OnClick", function()
        self:ResetManaPosition()
        print("|cFF00FF00[DDingUI Toolkit]|r " .. (L["PARTYTRACKER_MANA_POSITION_RESET_MSG"] or "힐러 마나 프레임 위치가 초기화되었습니다."))
    end)
    yOffset = yOffset - 50

    -- ===== Size Settings =====
    local sizeHeader = UI:CreateSectionHeader(scrollChild, L["PARTYTRACKER_SIZE_SETTINGS"])
    sizeHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Icon size
    local iconSizeSlider = UI:CreateSlider(scrollChild, L["ICON_SIZE"], 20, 60, 1, function(value)
        self.db.iconSize = value
        self:UpdateIconSize()
    end)
    iconSizeSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    iconSizeSlider:SetValue(self.db.iconSize or 33)
    yOffset = yOffset - 50

    -- Overall size
    local scaleSlider = UI:CreateSlider(scrollChild, L["OVERALL_SIZE"], 0.5, 2.0, 0.1, function(value)
        self.db.scale = value
        local frame = self:GetMainFrame()
        if frame then
            frame:SetScale(value)
        end
    end)
    scaleSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    scaleSlider:SetValue(self.db.scale or 1.0)
    yOffset = yOffset - 50

    -- ===== Font Settings =====
    local fontHeader = UI:CreateSectionHeader(scrollChild, L["PARTYTRACKER_FONT_SETTINGS"])
    fontHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Font selection
    local fontLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    fontLabel:SetText(L["FONT"])
    fontLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 25

    local fontDropdown = UI:CreateFontDropdown(scrollChild, 200, GetFontOptions(), function(value)
        self.db.font = value
        self:UpdateFonts()
    end)
    fontDropdown:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    fontDropdown:SetValue(self.db.font or SL_FONT) -- [12.0.1]
    yOffset = yOffset - 40

    -- Font size
    local fontSizeSlider = UI:CreateSlider(scrollChild, L["FONT_SIZE"], 8, 24, 1, function(value)
        self.db.fontSize = value
        self:UpdateFonts()
    end)
    fontSizeSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    fontSizeSlider:SetValue(self.db.fontSize or 14)
    yOffset = yOffset - 50

    -- ===== Mana Bar Settings =====
    local manaBarHeader = UI:CreateSectionHeader(scrollChild, L["PARTYTRACKER_MANA_BAR_SETTINGS"])
    manaBarHeader:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Mana bar width
    local manaBarWidthSlider = UI:CreateSlider(scrollChild, L["PARTYTRACKER_MANA_BAR_WIDTH"], 30, 120, 5, function(value)
        self.db.manaBarWidth = value
        self:UpdateManaBarSize()
    end)
    manaBarWidthSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    manaBarWidthSlider:SetValue(self.db.manaBarWidth or 60)
    yOffset = yOffset - 50

    -- Mana bar height
    local manaBarHeightSlider = UI:CreateSlider(scrollChild, L["PARTYTRACKER_MANA_BAR_HEIGHT"], 4, 20, 1, function(value)
        self.db.manaBarHeight = value
        self:UpdateManaBarSize()
    end)
    manaBarHeightSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    manaBarHeightSlider:SetValue(self.db.manaBarHeight or 10)
    yOffset = yOffset - 50

    -- Mana bar X offset
    local manaBarOffsetXSlider = UI:CreateSlider(scrollChild, L["PARTYTRACKER_MANA_BAR_OFFSET_X"], -50, 100, 1, function(value)
        self.db.manaBarOffsetX = value
        self:UpdateManaBarPosition()
    end)
    manaBarOffsetXSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    manaBarOffsetXSlider:SetValue(self.db.manaBarOffsetX or 4)
    yOffset = yOffset - 50

    -- Mana bar Y offset
    local manaBarOffsetYSlider = UI:CreateSlider(scrollChild, L["PARTYTRACKER_MANA_BAR_OFFSET_Y"], -30, 30, 1, function(value)
        self.db.manaBarOffsetY = value
        self:UpdateManaBarPosition()
    end)
    manaBarOffsetYSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    manaBarOffsetYSlider:SetValue(self.db.manaBarOffsetY or 6)
    yOffset = yOffset - 50

    -- Mana bar texture (dropdown)
    local textureLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textureLabel:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    textureLabel:SetText(L["PARTYTRACKER_MANA_BAR_TEXTURE"])
    textureLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 30

    local textureDropdown = UI:CreateStatusBarDropdown(scrollChild, 220, GetStatusBarOptions(), function(value)
        self.db.manaBarTexture = value
        self:UpdateManaBarTexture()
    end)
    textureDropdown:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    textureDropdown:SetValue(self.db.manaBarTexture or "Interface\\TargetingFrame\\UI-StatusBar")
    yOffset = yOffset - 50

    -- ===== Buttons =====
    -- Test button
    local testBtn = UI:CreateButton(scrollChild, 120, 30, L["TEST"])
    testBtn:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    testBtn:SetScript("OnClick", function()
        self:TestMode()
    end)

    -- Reset position button
    local resetPosBtn = UI:CreateButton(scrollChild, 120, 30, L["RESET_POSITION"])
    resetPosBtn:SetPoint("LEFT", testBtn, "RIGHT", 10, 0)
    resetPosBtn:SetScript("OnClick", function()
        self:ResetPosition()
        print("|cFF00FF00[DDingUI Toolkit]|r " .. L["PARTYTRACKER_POSITION_RESET"])
    end)

    -- ===== Right Column =====
    local rightYOffset = -10

    -- ===== Info =====
    local infoHeader = UI:CreateSectionHeader(scrollChild, L["PARTYTRACKER_INFO_TITLE"])
    infoHeader:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 25

    local infoText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    infoText:SetText(L["PARTYTRACKER_INFO_TEXT"])
    infoText:SetTextColor(unpack(UI.colors.textDim))
    infoText:SetJustifyH("LEFT")
    rightYOffset = rightYOffset - 200

    -- ===== Healer Classes =====
    local healerHeader = UI:CreateSectionHeader(scrollChild, L["PARTYTRACKER_HEALERS_TITLE"])
    healerHeader:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 25

    local healerText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    healerText:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    healerText:SetText(L["PARTYTRACKER_HEALERS_TEXT"])
    healerText:SetTextColor(unpack(UI.colors.textDim))
    healerText:SetJustifyH("LEFT")

    return container
end
