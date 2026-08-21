local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local Base = DDingUI and DDingUI.GUIBase
local Widgets = Base and Base.Widgets

if not Widgets then return end

local SL = _G.DDingUI_StyleLib
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local THEME = Base.THEME or {}

local ON_BACKGROUND = { 0.18, 0.075, 0.02, 1 }
local OFF_BACKGROUND = { 0.055, 0.06, 0.07, 1 }
local OFF_HOVER_BACKGROUND = { 0.085, 0.065, 0.05, 1 }
local OFF_BORDER = { 0.36, 0.38, 0.42, 1 }
local OFF_THUMB = { 0.68, 0.70, 0.74, 1 }
local OFF_TEXT = { 0.76, 0.78, 0.82, 1 }

local function GetAccent()
    local accent = THEME.accent
    if type(accent) == "table" then
        return accent[1] or 1, accent[2] or 0.4, accent[3] or 0, accent[4] or 1
    end
    return 1, 0.4, 0, 1
end

local function SetColor(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

local function SetBackdropColor(frame, color)
    frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
end

local function SetBackdropBorderColor(frame, color)
    frame:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
end

local function RefreshSwitchVisual(checkbox)
    if not checkbox or not checkbox._ddingSwitchStyled then return end

    local checked = checkbox.isChecked == true
    local hovered = checkbox._ddingSwitchHovered == true
    local accentR, accentG, accentB, accentA = GetAccent()

    checkbox._ddingSwitchThumb:ClearAllPoints()
    checkbox._ddingSwitchText:ClearAllPoints()

    if checked then
        SetBackdropColor(checkbox, ON_BACKGROUND)
        checkbox:SetBackdropBorderColor(accentR, accentG, accentB, accentA)
        checkbox._ddingSwitchThumb:SetColorTexture(accentR, accentG, accentB, 1)
        checkbox._ddingSwitchThumb:SetPoint("RIGHT", checkbox, "RIGHT", -3, 0)
        checkbox._ddingSwitchText:SetPoint("LEFT", checkbox, "LEFT", 5, 0)
        checkbox._ddingSwitchText:SetText("ON")
        checkbox._ddingSwitchText:SetTextColor(1, 0.76, 0.48, 1)
    else
        SetBackdropColor(checkbox, hovered and OFF_HOVER_BACKGROUND or OFF_BACKGROUND)
        if hovered then
            checkbox:SetBackdropBorderColor(accentR, accentG, accentB, 0.9)
        else
            SetBackdropBorderColor(checkbox, OFF_BORDER)
        end
        SetColor(checkbox._ddingSwitchThumb, OFF_THUMB)
        checkbox._ddingSwitchThumb:SetPoint("LEFT", checkbox, "LEFT", 3, 0)
        checkbox._ddingSwitchText:SetPoint("RIGHT", checkbox, "RIGHT", -4, 0)
        checkbox._ddingSwitchText:SetText("OFF")
        checkbox._ddingSwitchText:SetTextColor(OFF_TEXT[1], OFF_TEXT[2], OFF_TEXT[3], OFF_TEXT[4])
    end
end

function Widgets.StyleToggleSwitch(checkbox)
    if not checkbox then return end
    if checkbox._ddingSwitchStyled then
        RefreshSwitchVisual(checkbox)
        return
    end

    checkbox._ddingSwitchStyled = true
    checkbox:SetSize(46, 20)
    checkbox:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    if checkbox.check then checkbox.check:Hide() end
    local highlight = checkbox.GetHighlightTexture and checkbox:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end

    local thumb = checkbox:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 14)
    checkbox._ddingSwitchThumb = thumb

    local stateText = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stateText:SetJustifyH("CENTER")
    stateText:SetShadowOffset(0, 0)
    checkbox._ddingSwitchText = stateText

    checkbox.SetChecked = function(owner, checked)
        owner.isChecked = checked == true
        if owner.check then owner.check:Hide() end
        RefreshSwitchVisual(owner)
    end

    checkbox.RefreshSwitchVisual = RefreshSwitchVisual
    checkbox:HookScript("OnEnter", function(owner)
        owner._ddingSwitchHovered = true
        RefreshSwitchVisual(owner)
    end)
    checkbox:HookScript("OnLeave", function(owner)
        owner._ddingSwitchHovered = false
        RefreshSwitchVisual(owner)
    end)
    checkbox:HookScript("OnEnable", function(owner)
        RefreshSwitchVisual(owner)
    end)
    checkbox:HookScript("OnDisable", function(owner)
        RefreshSwitchVisual(owner)
    end)

    checkbox:SetChecked(checkbox.isChecked)
end
