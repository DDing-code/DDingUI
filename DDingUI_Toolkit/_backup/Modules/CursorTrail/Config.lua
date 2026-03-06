--[[
    DDingToolKit - CursorTrail Config
    CursorTrail Settings Panel
]]

local addonName, ns = ...
local UI = ns.UI
local CursorTrail = ns.CursorTrail
local L = ns.L

-- Blend mode options
local blendModeOptions = {
    { text = L["CURSORTRAIL_BLEND_ADD"], value = "ADD" },
    { text = L["CURSORTRAIL_BLEND_BLEND"], value = "BLEND" },
}

-- Layer options
local layerOptions = {
    { text = L["CURSORTRAIL_LAYER_TOP"], value = "TOOLTIP" },
    { text = L["CURSORTRAIL_LAYER_BG"], value = "BACKGROUND" },
}

-- Create settings panel
function CursorTrail:CreateConfigPanel(parent)
    -- DB 초기화 확인
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.CursorTrail then
            self.db = ns.db.profile.CursorTrail
        else
            return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
        end
    end

    local panel = UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(panel:GetWidth() - 50, 850)
    scrollFrame:SetScrollChild(scrollChild)

    local content = scrollChild
    local leftCol = 10
    local rightCol = 380
    local yOffset = -10

    -- ===== Basic Settings =====
    local header1 = UI:CreateSectionHeader(content, L["CURSORTRAIL_BASIC_SETTINGS"])
    header1:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    local enabledCB = UI:CreateCheckbox(content, L["CURSORTRAIL_ENABLE"], function(checked)
        self.db.enabled = checked
        if checked then
            if not CursorTrail.db then return end
            CursorTrail:OnEnable()
        else
            CursorTrail:OnDisable()
        end
    end)
    enabledCB:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    enabledCB:SetChecked(self.db.enabled)
    yOffset = yOffset - 40

    -- ===== Presets =====
    local header2 = UI:CreateSectionHeader(content, L["CURSORTRAIL_COLOR_PRESETS"])
    header2:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    local presetLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    presetLabel:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    presetLabel:SetText(L["PRESET"] .. ":")
    presetLabel:SetTextColor(unpack(UI.colors.text))

    local presetDropdown = UI:CreateDropdown(content, 180, ns.CursorTrailPresetList, function(value)
        self.db.preset = value
        if value ~= "custom" then
            self:ApplyPreset(value)
        end
    end)
    presetDropdown:SetPoint("LEFT", presetLabel, "RIGHT", 15, 0)
    presetDropdown:SetValue(self.db.preset or "custom")
    yOffset = yOffset - 45

    -- ===== Color Settings =====
    local header3 = UI:CreateSectionHeader(content, L["CURSORTRAIL_COLOR_SETTINGS"])
    header3:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    -- Color count slider
    local colorCountSlider = UI:CreateSlider(content, L["CURSORTRAIL_COLOR_NUM"], 1, 10, 1, function(value)
        self.db.colorCount = value
        self.db.preset = "custom"
    end)
    colorCountSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    colorCountSlider:SetValue(self.db.colorCount or 8)
    yOffset = yOffset - 55

    -- Color buttons (2 columns)
    local colorButtonsStartY = yOffset
    for i = 1, 10 do
        local row = math.ceil(i / 2)
        local col = (i - 1) % 2

        local xPos = leftCol + 5 + (col * 170)
        local yPos = colorButtonsStartY - ((row - 1) * 35)

        local colorBtn = UI:CreateColorButton(content, string.format(L["CURSORTRAIL_COLOR_N"], i), self.db.colors[i], function(r, g, b, a)
            self.db.colors[i] = { r, g, b, a }
            self.db.preset = "custom"
        end)
        colorBtn:SetPoint("TOPLEFT", xPos, yPos)
    end
    yOffset = colorButtonsStartY - (5 * 35) - 20

    -- ===== Color Flow =====
    local header4 = UI:CreateSectionHeader(content, L["CURSORTRAIL_COLOR_FLOW"])
    header4:SetPoint("TOPLEFT", leftCol, yOffset)
    yOffset = yOffset - 30

    local flowCB = UI:CreateCheckbox(content, L["CURSORTRAIL_COLOR_FLOW_DESC"], function(checked)
        self.db.colorFlow = checked
        self.db.preset = "custom"
    end)
    flowCB:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    flowCB:SetChecked(self.db.colorFlow)
    yOffset = yOffset - 35

    local flowSpeedSlider = UI:CreateSlider(content, L["CURSORTRAIL_FLOW_SPEED"], 0.1, 5.0, 0.1, function(value)
        self.db.colorFlowSpeed = value
    end)
    flowSpeedSlider:SetPoint("TOPLEFT", leftCol + 5, yOffset)
    flowSpeedSlider:SetValue(self.db.colorFlowSpeed or 0.6)
    yOffset = yOffset - 55

    -- ===== Right Column: Appearance =====
    local rightYOffset = -10

    local header5 = UI:CreateSectionHeader(content, L["CURSORTRAIL_APPEARANCE"])
    header5:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 30

    -- Width
    local widthSlider = UI:CreateSlider(content, L["WIDTH"], 10, 200, 5, function(value)
        self.db.width = value
    end)
    widthSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    widthSlider:SetValue(self.db.width or 60)
    rightYOffset = rightYOffset - 55

    -- Height
    local heightSlider = UI:CreateSlider(content, L["HEIGHT"], 10, 200, 5, function(value)
        self.db.height = value
    end)
    heightSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    heightSlider:SetValue(self.db.height or 60)
    rightYOffset = rightYOffset - 55

    -- Alpha
    local alphaSlider = UI:CreateSlider(content, L["TRANSPARENCY"], 0.1, 1.0, 0.1, function(value)
        self.db.alpha = value
    end)
    alphaSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    alphaSlider:SetValue(self.db.alpha or 1.0)
    rightYOffset = rightYOffset - 55

    -- Texture
    local textureLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textureLabel:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    textureLabel:SetText(L["TEXTURE"] .. ":")
    textureLabel:SetTextColor(unpack(UI.colors.text))
    rightYOffset = rightYOffset - 25

    local textureDropdown = UI:CreateDropdown(content, 180, ns.CursorTrailTextureList, function(value)
        self.db.texture = value
        self:ApplySettings()
    end)
    textureDropdown:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    textureDropdown:SetValue(self.db.texture or "Interface\\COMMON\\Indicator-Yellow")
    rightYOffset = rightYOffset - 45

    -- Blend mode
    local blendLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    blendLabel:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    blendLabel:SetText(L["CURSORTRAIL_BLEND_MODE"] .. ":")
    blendLabel:SetTextColor(unpack(UI.colors.text))
    rightYOffset = rightYOffset - 25

    local blendDropdown = UI:CreateDropdown(content, 180, blendModeOptions, function(value)
        self.db.blendMode = value
        self:ApplySettings()
    end)
    blendDropdown:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    blendDropdown:SetValue(self.db.blendMode or "ADD")
    rightYOffset = rightYOffset - 50

    -- ===== Performance =====
    local header6 = UI:CreateSectionHeader(content, L["CURSORTRAIL_PERFORMANCE"])
    header6:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 25

    -- Warning text
    local warningText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warningText:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    warningText:SetText(L["CURSORTRAIL_PERFORMANCE_WARNING"])
    rightYOffset = rightYOffset - 25

    -- Dot lifetime
    local lifetimeSlider = UI:CreateSlider(content, L["CURSORTRAIL_DOT_LIFETIME"], 0.1, 1.0, 0.05, function(value)
        self.db.lifetime = value
    end)
    lifetimeSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    lifetimeSlider:SetValue(self.db.lifetime or 0.25)
    rightYOffset = rightYOffset - 55

    -- Max dot count
    local maxDotsSlider = UI:CreateSlider(content, L["CURSORTRAIL_MAX_DOTS"], 100, 2000, 100, function(value)
        self.db.maxDots = value
        self:CreateElementPool()
    end)
    maxDotsSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    maxDotsSlider:SetValue(self.db.maxDots or 800)
    rightYOffset = rightYOffset - 55

    -- Dot spacing
    local distanceSlider = UI:CreateSlider(content, L["CURSORTRAIL_DOT_SPACING"], 1, 50, 1, function(value)
        self.db.dotDistance = value
    end)
    distanceSlider:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    distanceSlider:SetValue(self.db.dotDistance or 2)
    rightYOffset = rightYOffset - 60

    -- ===== Display Conditions =====
    local header7 = UI:CreateSectionHeader(content, L["CURSORTRAIL_DISPLAY_CONDITIONS"])
    header7:SetPoint("TOPLEFT", rightCol, rightYOffset)
    rightYOffset = rightYOffset - 30

    local combatCB = UI:CreateCheckbox(content, L["CURSORTRAIL_COMBAT_ONLY"], function(checked)
        self.db.onlyInCombat = checked
    end)
    combatCB:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    combatCB:SetChecked(self.db.onlyInCombat)
    rightYOffset = rightYOffset - 30

    local instanceCB = UI:CreateCheckbox(content, L["CURSORTRAIL_HIDE_INSTANCE"], function(checked)
        self.db.hideInInstance = checked
    end)
    instanceCB:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    instanceCB:SetChecked(self.db.hideInInstance)
    rightYOffset = rightYOffset - 40

    -- Layer
    local layerLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    layerLabel:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    layerLabel:SetText(L["CURSORTRAIL_DISPLAY_LAYER"] .. ":")
    layerLabel:SetTextColor(unpack(UI.colors.text))
    rightYOffset = rightYOffset - 25

    local layerDropdown = UI:CreateDropdown(content, 180, layerOptions, function(value)
        self.db.layer = value
        self:ApplySettings()
    end)
    layerDropdown:SetPoint("TOPLEFT", rightCol + 5, rightYOffset)
    layerDropdown:SetValue(self.db.layer or "TOOLTIP")

    return panel
end
