local f = CreateFrame("Frame", "SakuriaUIConfig", UIParent, "BackdropTemplate")
f:SetSize(520, 600)
f:SetPoint("CENTER", 0, 200)
f:SetFrameStrata("DIALOG")
f:SetFrameLevel(50)
f:EnableMouse(true)
f:SetMovable(false)

local BORDER_SIZE = 1
local BG_R, BG_G, BG_B = 42/255, 44/255, 44/255 -- #2A2C2C (grey)
local ACCENT_R, ACCENT_G, ACCENT_B = 244/255, 182/255, 203/255 -- #F4B6CB (logo pink)

local RELOAD_HEX  = "FFB8FFB8"
local RELOAD_TEXT = "|c" .. RELOAD_HEX .. "Requires Reload|r"

local NEW_HEX  = "FFF4B6CB"
local NEW_TEXT = "|c" .. NEW_HEX .. "*new*|r"

local CHECKBOX_BG       = 0.32
local CHECKBOX_BG_HOVER = 0.36

local RELOAD_TAG_OFFSET_X = 180
local RIGHT_COL_X = 320
local NEW_TAG_OFFSET_X = 155

-- Changelog here
local UPDATE_BODY = [[
|cFFF4B6CB31.01.2026|r

- Changed Info tab into Changelog tab

|cFFF4B6CB30.01.2026|r

- Added a fancy update popup
- Icon improvements (desaturation/alpha)
- Various bug fixes & code cleaning

|cFFF4B6CB30.01.2026|r

- Fixed GCD tracker not disabling when using slash command

|cFFF4B6CB29.01.2026|r

- Added Boss Mute Option (disables CVars)
- Added Pet Bar fade
- Cleaned up code

|cFFF4B6CB28.01.2026|r

- Complete visual overhaul of the menu

|cFFF4B6CB27.01.2026|r

- Making the name look pretty in game

|cFFF4B6CB27.01.2026|r

- Added new textures
- Hopefully fixed CDM overlay for good

|cFFF4B6CB26.01.2026|r

- Reverting some code changes, overlay removal should not give any lua errors anymore (this thing sucks)

|cFFF4B6CB26.01.2026|r

- Cleaned up some code
- Fixed an overlay issue with Warlocks Burning Rush spell (added support for toggle spells)

|cFFF4B6CB26.01.2026|r

- Removed CDM print


For questions or suggestions visit |cFFF4B6CBdiscord.gg/sakuria|r
]]
f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    insets = { left = BORDER_SIZE, right = BORDER_SIZE, top = BORDER_SIZE, bottom = BORDER_SIZE },
})
f:SetBackdropColor(BG_R, BG_G, BG_B, 1)

local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
border:SetPoint("TOPLEFT", -BORDER_SIZE, BORDER_SIZE)
border:SetPoint("BOTTOMRIGHT", BORDER_SIZE, -BORDER_SIZE)
border:SetFrameStrata(f:GetFrameStrata())
border:SetFrameLevel(f:GetFrameLevel() - 1)
border:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
border:SetBackdropColor(0, 0, 0, 1)

f:Hide()

local function CreateFlatButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)

    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    b:SetBackdropColor(0.22, 0.22, 0.22, 1)

    local edge = CreateFrame("Frame", nil, b, "BackdropTemplate")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetFrameLevel(b:GetFrameLevel() - 1)
    edge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    edge:SetBackdropColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    b._edge = edge

    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(1, 1, 1, 1)
    b:SetFontString(label)

    b:SetScript("OnEnter", function(self)
        self:GetFontString():SetTextColor(0.9, 0.9, 0.9, 1)
        self:SetBackdropColor(0.26, 0.26, 0.26, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:GetFontString():SetTextColor(1, 1, 1, 1)
        self:SetBackdropColor(0.22, 0.22, 0.22, 1)
    end)

    return b
end

-- Header
local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
title:SetPoint("TOP", f, "TOP", 0, -20)
title:SetText("|cffffffffSakuria|r|cFFF4B6CBUI|r")

local logo = f:CreateTexture(nil, "ARTWORK")
logo:SetTexture("Interface\\AddOns\\SakuriaUI\\media\\sakuLogo.png")
logo:SetSize(60, 60)
logo:SetPoint("TOP", title, "BOTTOM", 0, -6)

local copyright = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
copyright:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
copyright:SetText("©2026 Sakuria")

local close = CreateFrame("Button", nil, f)
close:SetSize(34, 34)
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
close:SetFrameLevel(f:GetFrameLevel() + 50)

local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
closeText:SetText("×")
closeText:SetTextColor(1, 1, 1, 1)

do
    local font, _, flags = closeText:GetFont()
    closeText:SetFont(font, 26, flags or "OUTLINE")
end

close:SetScript("OnEnter", function() closeText:SetTextColor(0.9, 0.9, 0.9, 1) end)
close:SetScript("OnLeave", function() closeText:SetTextColor(1, 1, 1, 1) end)
close:SetScript("OnClick", function() f:Hide() end)

local reloadBtn = CreateFlatButton(f, "RELOAD UI", 150, 28)
reloadBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 34)
reloadBtn:SetScript("OnClick", function() ReloadUI() end)

local function EnsureDB()
    if SakuriaUI and SakuriaUI.GetDB then
        SakuriaUI:GetDB()
    else
        SakuriaUI_DB = SakuriaUI_DB or {}
    end
    SakuriaUI_DB.fadeBars = SakuriaUI_DB.fadeBars or {}
end

local function SetCheckboxTooltip(cb, descText)
    if not cb then return end
    cb._ttDesc = descText or ""

    cb:HookScript("OnEnter", function(self)
        if not self._ttDesc or self._ttDesc == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._ttDesc, 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)

    cb:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Checkbox
local function CreateModernCheckbox(parent, labelText, size)
    size = size or 25

    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(size, size)

    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cb)
    bg:SetDrawLayer("BACKGROUND", 1)
    bg:SetColorTexture(CHECKBOX_BG, CHECKBOX_BG, CHECKBOX_BG, 1)
    cb._bg = bg

    local fill = cb:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    fill:Hide()
    cb._fill = fill

    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetAllPoints(cb)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetVertexColor(0, 0, 0, 1)
    check:Hide()
    cb._check = check

    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 10, 0)
    text:SetText(labelText or "")
    cb.Text = text

    function cb:UpdateVisual()
        local checked = self:GetChecked()
        self._fill:SetShown(checked)
        self._check:SetShown(checked)
    end

    cb:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(CHECKBOX_BG_HOVER, CHECKBOX_BG_HOVER, CHECKBOX_BG_HOVER, 1)
    end)
    cb:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(CHECKBOX_BG, CHECKBOX_BG, CHECKBOX_BG, 1)
    end)

    return cb
end

-- Tabs
local TabBar = CreateFrame("Frame", nil, f)
TabBar:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + BORDER_SIZE, -140)
TabBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14 - BORDER_SIZE, -140)
TabBar:SetHeight(28)
TabBar:SetFrameLevel(f:GetFrameLevel() + 20)

local barLine = TabBar:CreateTexture(nil, "ARTWORK")
barLine:SetPoint("BOTTOMLEFT", TabBar, "BOTTOMLEFT", 0, 0)
barLine:SetPoint("BOTTOMRIGHT", TabBar, "BOTTOMRIGHT", 0, 0)
barLine:SetHeight(1)
barLine:SetColorTexture(1, 1, 1, 0.08)

local Tabs, Pages = {}, {}
local ActiveTab = 1

local function SetTabState(tab, selected)
    if selected then
        tab._underline:Show()
        tab:GetFontString():SetTextColor(1, 1, 1, 1)
    else
        tab._underline:Hide()
        tab:GetFontString():SetTextColor(0.75, 0.75, 0.75, 1)
    end
end

local function SelectTab(id)
    ActiveTab = id
    for i, tab in ipairs(Tabs) do
        SetTabState(tab, i == id)
        if Pages[i] then
            Pages[i]:SetShown(i == id)
        end
    end
end

local function CreateFlatTab(id, text, anchor)
    local b = CreateFrame("Button", nil, TabBar)
    b:SetHeight(28)
    b:SetID(id)

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(text)
    b:SetFontString(fs)

    b:SetWidth(fs:GetStringWidth() + 26)

    b:SetScript("OnEnter", function(self)
        if self:GetID() ~= ActiveTab then
            self:GetFontString():SetTextColor(0.9, 0.9, 0.9, 1)
        end
    end)
    b:SetScript("OnLeave", function(self)
        if self:GetID() ~= ActiveTab then
            self:GetFontString():SetTextColor(0.75, 0.75, 0.75, 1)
        end
    end)

    local u = b:CreateTexture(nil, "ARTWORK")
    u:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 10, 0)
    u:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -10, 0)
    u:SetHeight(2)
    u:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    u:Hide()
    b._underline = u

    b:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)

    if anchor then
        b:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
    else
        b:SetPoint("LEFT", TabBar, "LEFT", 0, 0)
    end

    Tabs[id] = b
    return b
end

local function CreateTabPage(id)
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + BORDER_SIZE, -176)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16 - BORDER_SIZE, 70)
    page:SetFrameLevel(f:GetFrameLevel() + 5)
    page:Hide()
    Pages[id] = page
    return page
end

CreateFlatTab(1, "General")
CreateFlatTab(2, "Bars", Tabs[1])
CreateFlatTab(3, "CDM", Tabs[2])
CreateFlatTab(4, "Changelog", Tabs[3])

local pageGeneral   = CreateTabPage(1)
local pageBars      = CreateTabPage(2)
local pageCooldowns = CreateTabPage(3)
local pageChangelog = CreateTabPage(4)

local checkboxMap, lastByPage = {}, {}
local CHECKBOX_SIZE, RIGHT_CHECKBOX_SIZE = 25, 23

local function CreateReloadTag(parent, rowCheckbox)
    local tag = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tag:SetText(RELOAD_TEXT)
    tag:SetPoint("LEFT", rowCheckbox, "LEFT", RELOAD_TAG_OFFSET_X, 0)
    tag:Show()
    return tag
end

local function CreateNewTag(parent, rowCheckbox)
    local tag = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tag:SetText(NEW_TEXT)
    tag:SetPoint("LEFT", rowCheckbox, "LEFT", NEW_TAG_OFFSET_X, 0)
    tag:Show()
    return tag
end

local rightColumn = {}

local function AddCheckbox(parent, label, key, requiresReload, tooltipDesc, isNew)
    local cb = CreateModernCheckbox(parent, label, CHECKBOX_SIZE)

    local last = lastByPage[parent]
    if last then
        cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
    else
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, -18)
    end

    EnsureDB()
    cb:SetChecked(SakuriaUI_DB[key])
    cb:UpdateVisual()

    checkboxMap[key] = cb
    SetCheckboxTooltip(cb, tooltipDesc or "")

    cb:SetScript("OnClick", function(self)
        EnsureDB()
        SakuriaUI_DB[key] = self:GetChecked()
        self:UpdateVisual()

        if key == "iconFlower" and SakuriaUI and SakuriaUI.IsReady and SakuriaUI:IsReady() then
            if SakuriaUI_DisableCleanIcons then SakuriaUI_DisableCleanIcons() end
            if SakuriaUI_EnableCleanIcons then SakuriaUI_EnableCleanIcons() end
        end

        if SakuriaUI and SakuriaUI.Modules and SakuriaUI.Modules[key] then
            if SakuriaUI.IsReady and SakuriaUI:IsReady() then
                if self:GetChecked() then
                    if SakuriaUI.Modules[key].Enable then SakuriaUI.Modules[key].Enable() end
                else
                    if SakuriaUI.Modules[key].Disable then SakuriaUI.Modules[key].Disable() end
                end
            else
                ReloadUI()
            end
        end
    end)
	
	if isNew then
    CreateNewTag(parent, cb)
	end

	if requiresReload then
    CreateReloadTag(parent, cb)
	end

    lastByPage[parent] = cb
    return cb
end

local function AddRightCheckbox(parent, label, barKey, anchor, tooltipDesc)
    local cb = CreateModernCheckbox(parent, label, RIGHT_CHECKBOX_SIZE)

    if anchor then
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    else
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", RIGHT_COL_X, -18)
    end

    EnsureDB()
    cb:SetChecked(SakuriaUI_DB.fadeBars[barKey] ~= false)
    cb:UpdateVisual()

    SetCheckboxTooltip(cb, tooltipDesc or "")

    cb:SetScript("OnClick", function(self)
        EnsureDB()
        SakuriaUI_DB.fadeBars[barKey] = self:GetChecked()
        self:UpdateVisual()

        if SakuriaUI and SakuriaUI.IsReady and SakuriaUI:IsReady() and SakuriaUI_DB.fadeActionBars then
            if SakuriaUI_DisableFadeActionBars then SakuriaUI_DisableFadeActionBars() end
            if SakuriaUI_EnableFadeActionBars then SakuriaUI_EnableFadeActionBars() end
        end
    end)

    rightColumn[#rightColumn + 1] = cb
    return cb
end

local function UpdateRightColumn()
    EnsureDB()
    local show = SakuriaUI_DB.fadeActionBars

    for _, cb in ipairs(rightColumn) do
        cb:SetShown(show)
        if cb.Text then cb.Text:SetShown(show) end
    end
end

AddCheckbox(pageGeneral, "Crosshair", "crosshair", false, "Shows a green crosshair on your character while you are in combat")
AddCheckbox(pageGeneral, "Mute Boss Sounds", "bossMute", false, "Mutes Blizzard audio only during Boss encounters and enables them again after the fight is over", true)

AddCheckbox(pageBars, "Fade Action Bars", "fadeActionBars", true, "When enabled, selected action bars fade out until you hover them")

local bar1 = AddRightCheckbox(pageBars, "Bar 1", "MainActionBar", nil, "Fades Bar 1")
local bar2 = AddRightCheckbox(pageBars, "Bar 2", "MultiBarBottomLeft", bar1, "Fades Bar 2")
local bar3 = AddRightCheckbox(pageBars, "Bar 3", "MultiBarBottomRight", bar2, "Fades Bar 3")
local bar4 = AddRightCheckbox(pageBars, "Bar 4", "MultiBarRight", bar3, "Fades Bar 4")
local bar5 = AddRightCheckbox(pageBars, "Bar 5", "MultiBarLeft", bar4, "Fades Bar 5")
local bar6 = AddRightCheckbox(pageBars, "Bar 6", "MultiBar5", bar5, "Fades Bar 6")
local bar7 = AddRightCheckbox(pageBars, "Bar 7", "MultiBar6", bar6, "Fades Bar 7")
local bar8 = AddRightCheckbox(pageBars, "Bar 8", "MultiBar7", bar7, "Fades Bar 8")

AddCheckbox(pageBars, "Fade Stance Bar", "fadeStanceBar", true, "Fades the stance bar")
AddCheckbox(pageBars, "Fade Menu Bar", "hideMenuBar", true, "Fades the menu bar")
AddCheckbox(pageBars, "Fade Pet Bar", "fadePetBar", true, "Fades the pet bar")
AddCheckbox(pageBars, "Flower Backdrop", "iconFlower", false, "Adds a decorative Sakura as backdrop for the action bars")
AddCheckbox(pageBars, "Hide Bag Bar", "hideBagBar", false, "Hides the bag bar")

AddCheckbox(pageCooldowns, "Disable Spell Overlay", "disableAuraOverlay", true, "Removes the yellow overlay from spells in CDM")

-- Changelog tab (scrolling only here)
do
    local clTitle = pageChangelog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    clTitle:SetPoint("TOPLEFT", pageChangelog, "TOPLEFT", 24, -18)
	clTitle:SetText("|cffffffffChange|r|cFFF4B6CBlog|r")

    local sf = CreateFrame("ScrollFrame", nil, pageChangelog, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", clTitle, "BOTTOMLEFT", 0, -12)
    sf:SetPoint("BOTTOMRIGHT", pageChangelog, "BOTTOMRIGHT", -24, 16)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)

    local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(2)

    local function UpdateChangelogLayout()
        local w = sf:GetWidth()
        if not w or w <= 0 then return end

        text:SetWidth(w - 28)
        text:SetText(UPDATE_BODY)

        local h = math.ceil(text:GetStringHeight() or 1)
        child:SetSize(w - 28, h + 2)
    end

    sf:SetScript("OnShow", UpdateChangelogLayout)
    sf:SetScript("OnSizeChanged", UpdateChangelogLayout)

    local function SkinChangelogScrollBar(scrollFrame)
        local sb = scrollFrame.ScrollBar
        if not sb then return end

        -- Hide Blizzard textures
        if sb.GetRegions then
            for i = 1, select("#", sb:GetRegions()) do
                local r = select(i, sb:GetRegions())
                if r and r.GetObjectType and r:GetObjectType() == "Texture" then
                    r:SetAlpha(0)
                end
            end
        end

        sb:SetWidth(18)

        -- Track background
        if not sb._track then
            local track = CreateFrame("Frame", nil, sb, "BackdropTemplate")
            track:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, -18)
            track:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 18)
            track:SetFrameLevel(sb:GetFrameLevel() - 1)
            track:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            track:SetBackdropColor(0.22, 0.22, 0.22, 1)

            local trackBorder = CreateFrame("Frame", nil, track, "BackdropTemplate")
            trackBorder:SetPoint("TOPLEFT", -1, 1)
            trackBorder:SetPoint("BOTTOMRIGHT", 1, -1)
            trackBorder:SetFrameLevel(track:GetFrameLevel() - 1)
            trackBorder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            trackBorder:SetBackdropColor(0, 0, 0, 1)

            sb._track = track
        end

        -- Arrow buttons
        local function SkinArrow(btn)
            if not btn then return end
            btn:SetSize(18, 18)

            if btn.GetRegions then
                for i = 1, select("#", btn:GetRegions()) do
                    local r = select(i, btn:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "Texture" then
                        r:SetAlpha(0)
                    end
                end
            end
            if btn.Normal then btn.Normal:SetAlpha(0) end
            if btn.Pushed then btn.Pushed:SetAlpha(0) end
            if btn.Disabled then btn.Disabled:SetAlpha(0) end
            if btn.Highlight then btn.Highlight:SetAlpha(0) end

            if btn._skin then return end

            local skin = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            skin:SetAllPoints(btn)
            skin:SetFrameLevel(btn:GetFrameLevel() + 5)

            skin:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            skin:SetBackdropColor(0.22, 0.22, 0.22, 1)

            local edge = CreateFrame("Frame", nil, skin, "BackdropTemplate")
            edge:SetPoint("TOPLEFT", -1, 1)
            edge:SetPoint("BOTTOMRIGHT", 1, -1)
            edge:SetFrameLevel(skin:GetFrameLevel() - 1)
            edge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            edge:SetBackdropColor(0, 0, 0, 1)

            -- Square
            local sq = skin:CreateTexture(nil, "OVERLAY")
            sq:SetPoint("CENTER", skin, "CENTER", 0, 0)
            sq:SetSize(10, 10)
            sq:SetColorTexture(0.8, 0.8, 0.8, 1)

            btn._skin = skin
            btn._sq = sq

            btn:HookScript("OnEnter", function(self)
                if self._skin then self._skin:SetBackdropColor(0.26, 0.26, 0.26, 1) end
                if self._sq then self._sq:SetVertexColor(0.95, 0.95, 0.95, 1) end
            end)
            btn:HookScript("OnLeave", function(self)
                if self._skin then self._skin:SetBackdropColor(0.22, 0.22, 0.22, 1) end
                if self._sq then self._sq:SetVertexColor(1, 1, 1, 1) end
            end)
        end

        SkinArrow(sb.ScrollUpButton)
        SkinArrow(sb.ScrollDownButton)

        if sb.ScrollUpButton then
            sb.ScrollUpButton:ClearAllPoints()
            sb.ScrollUpButton:SetPoint("TOP", sb, "TOP", 0, 0)
        end
        if sb.ScrollDownButton then
            sb.ScrollDownButton:ClearAllPoints()
            sb.ScrollDownButton:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
        end

        -- Pink thumb
        local thumb = sb:GetThumbTexture()
        if thumb then
            thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
            thumb:SetVertexColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            thumb:SetWidth(12)
        end

        if not sb._thumbShowHooked then
            sb._thumbShowHooked = true
            sb:HookScript("OnShow", function(self)
                local t = self:GetThumbTexture()
                if t then
                    t:SetTexture("Interface\\Buttons\\WHITE8x8")
                    t:SetVertexColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                    t:SetWidth(12)
                end
            end)
        end
    end

    SkinChangelogScrollBar(sf)
end

SelectTab(1)

f:SetScript("OnShow", function()
    EnsureDB()

    for key, cb in pairs(checkboxMap) do
        if SakuriaUI_DB[key] ~= nil then
            cb:SetChecked(SakuriaUI_DB[key])
            cb:UpdateVisual()
        end
    end

    bar1:SetChecked(SakuriaUI_DB.fadeBars.MainActionBar ~= false);       bar1:UpdateVisual()
    bar2:SetChecked(SakuriaUI_DB.fadeBars.MultiBarBottomLeft ~= false);  bar2:UpdateVisual()
    bar3:SetChecked(SakuriaUI_DB.fadeBars.MultiBarBottomRight ~= false); bar3:UpdateVisual()
    bar4:SetChecked(SakuriaUI_DB.fadeBars.MultiBarRight ~= false);       bar4:UpdateVisual()
    bar5:SetChecked(SakuriaUI_DB.fadeBars.MultiBarLeft ~= false);        bar5:UpdateVisual()
    bar6:SetChecked(SakuriaUI_DB.fadeBars.MultiBar5 ~= false);           bar6:UpdateVisual()
    bar7:SetChecked(SakuriaUI_DB.fadeBars.MultiBar6 ~= false);           bar7:UpdateVisual()
    bar8:SetChecked(SakuriaUI_DB.fadeBars.MultiBar7 ~= false);           bar8:UpdateVisual()

    UpdateRightColumn()
end)

checkboxMap["fadeActionBars"]:HookScript("OnClick", function()
    UpdateRightColumn()

    if SakuriaUI and SakuriaUI.IsReady and SakuriaUI:IsReady() then
        if SakuriaUI_DisableFadeActionBars then SakuriaUI_DisableFadeActionBars() end
        if SakuriaUI_DB.fadeActionBars then
            if SakuriaUI_EnableFadeActionBars then SakuriaUI_EnableFadeActionBars() end
        end
    end
end)

SLASH_SAKURIAUI1 = "/sui"
SLASH_SAKURIAUI2 = "/sakuria"
SlashCmdList["SAKURIAUI"] = function()
    if f:IsShown() then f:Hide() else f:Show() end
end