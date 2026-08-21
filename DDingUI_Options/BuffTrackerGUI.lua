local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local GUI = DDingUI.GUI
local SL = _G.DDingUI_StyleLib
local FLAT = SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local Tokens = SL.Tokens
local WR = SL.WidgetRefresh
local THEME = GUI.THEME
local Widgets = GUI.Widgets
local CreateCustomScrollBar = GUI.CreateCustomScrollBar
local DDingUI_GetPopupEditBox = GUI.GetPopupEditBox

local function RenderOptions(...)
    return GUI.RenderOptions(...)
end

local CreateTrackerLivePreview = GUI.CreateTrackerLivePreview

local function CreateAuraCatalogPane(parent, createScrollBar)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pane:SetBackdrop({ bgFile = FLAT })
    pane:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.98)

    local heading = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 12, -12)
    heading:SetText(L["Aura Catalog"] or "Aura Catalog")
    heading:SetTextColor(THEME.textBright[1], THEME.textBright[2], THEME.textBright[3], 1)

    local subtitle = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
    subtitle:SetText(L["Search and add tracked auras"] or "Search and add tracked auras")
    subtitle:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.9)

    local separator = pane:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", 10, -46)
    separator:SetPoint("TOPRIGHT", -10, -46)
    separator:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.5)

    local scroll = CreateFrame("ScrollFrame", nil, pane)
    scroll:SetPoint("TOPLEFT", 10, -56)
    scroll:SetPoint("BOTTOMRIGHT", -14, 8)
    scroll:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    child.scrollFrame = scroll

    local scrollBar = createScrollBar(pane, scroll)
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 3, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 3, 0)
    scroll.ScrollBar = scrollBar

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 42)))
        if scrollBar.UpdateThumbPosition then scrollBar.UpdateThumbPosition() end
    end)

    local embed = CreateFrame("Frame", nil, child)
    embed:SetPoint("TOPLEFT", 0, 0)
    embed:SetPoint("RIGHT", child, "RIGHT", 0, 0)
    embed._ddingCatalogContentFrame = child
    embed._ddingCatalogTopOffset = 0
    embed._ddingCatalogBottomPadding = 16

    local grid = DDingUI.CreateCDMIconGridWidget and DDingUI.CreateCDMIconGridWidget(embed)
    if grid then
        grid:ClearAllPoints()
        grid:SetPoint("TOPLEFT", embed, "TOPLEFT", 0, 0)
        grid:SetPoint("RIGHT", embed, "RIGHT", 0, 0)
    end

    scroll:SetScript("OnSizeChanged", function(self, width)
        if not width or width < 1 then return end
        child:SetWidth(math.max(1, width))
        if DDingUI.UpdateCDMIconGrid then DDingUI.UpdateCDMIconGrid() end
    end)
    child:SetScript("OnSizeChanged", function()
        if scrollBar.UpdateThumbPosition then scrollBar.UpdateThumbPosition() end
    end)

    pane.scrollFrame = scroll
    pane.scrollChild = child
    pane.grid = grid
    return pane
end

local function GetTrackerOptionCategory(key, order)
    local normalized = tostring(key or ""):lower()

    if normalized:find("_alertactionsheader", 1, true)
        or normalized:find("_alertaction", 1, true)
        or normalized:find("_alertaddaction", 1, true)
    then
        return "actions"
    end

    if normalized:find("_activation", 1, true)
        or normalized:find("_alertheader", 1, true)
        or normalized:find("_alertenabled", 1, true)
        or normalized:find("_alerttrigger", 1, true)
        or normalized:find("_alertaddtrigger", 1, true)
        or normalized:find("_soundtrigger", 1, true)
        or normalized:find("_soundstartdelay", 1, true)
        or normalized:find("_soundendbefore", 1, true)
        or normalized:find("_soundinterval", 1, true)
    then
        return "conditions"
    end

    if normalized:find("text", 1, true) then
        return "text"
    end

    if normalized:find("attachto", 1, true)
        or normalized:find("anchorpoint", 1, true)
        or normalized:find("selfpoint", 1, true)
        or normalized:find("offsetx", 1, true)
        or normalized:find("offsety", 1, true)
        or normalized:find("pickframe", 1, true)
        or normalized:find("framestrata", 1, true)
        or normalized:match("_width$")
        or normalized:match("_height$")
    then
        return "position"
    end

    if normalized:find("_icon", 1, true)
        or normalized:find("_bar", 1, true)
        or normalized:find("_ring", 1, true)
        or normalized:find("_glow", 1, true)
        or normalized:find("_border", 1, true)
        or normalized:find("_texture", 1, true)
        or normalized:find("_color", 1, true)
        or normalized:find("_smooth", 1, true)
        or normalized:find("_tick", 1, true)
        or normalized:find("_sound", 1, true)
        or normalized:find("_hidewhenzero", 1, true)
        or normalized:find("_showincombat", 1, true)
        or normalized:find("_onlyincombat", 1, true)
    then
        return "appearance"
    end

    if type(order) == "number" and order >= 8 then
        return "conditions"
    end
    return "general"
end

local function CreateModernTrackerTabDefinitions()
    local definitions = {
        { key = "general", name = L["General"] or "General" },
        { key = "appearance", name = L["Appearance"] or "Appearance" },
        { key = "position", name = L["Position"] or "Position" },
        { key = "text", name = L["Text"] or "Text" },
        { key = "conditions", name = L["Conditions"] or "Conditions" },
        { key = "actions", name = L["Actions"] or "Actions" },
    }
    for _, definition in ipairs(definitions) do
        local category = definition.key
        definition.filter = function(key, order)
            return GetTrackerOptionCategory(key, order) == category
        end
    end
    return definitions
end

local ModernTrackerEditor = {}

function ModernTrackerEditor:IsHidden(option)
    if not option or option.hidden == nil then return false end
    if type(option.hidden) == "function" then
        local ok, hidden = pcall(option.hidden)
        return ok and hidden == true
    end
    return option.hidden == true
end

function ModernTrackerEditor:ResolveLabel(option, fallback)
    local label = option and option.name or fallback or ""
    if type(label) == "function" then
        local ok, value = pcall(label, { option = option })
        if not ok then ok, value = pcall(label) end
        label = ok and value or fallback or ""
    end
    label = tostring(label or fallback or "")
    label = label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    label = label:gsub("|T.-|t", ""):gsub("\n", " ")
    label = label:gsub("━", ""):gsub("─", "")
    return label:match("^%s*(.-)%s*$") or label
end

function ModernTrackerEditor:CloneOption(option, label)
    local copy = {}
    for key, value in pairs(option or {}) do copy[key] = value end
    copy.name = label or self:ResolveLabel(option)
    return copy
end

function ModernTrackerEditor:AddWidget(parent, widget)
    if not widget then return end
    parent.widgets = parent.widgets or {}
    parent.widgets[#parent.widgets + 1] = widget
end

function ModernTrackerEditor:CreateSection(parent, yOffset, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(30)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if GUI.StyleFontString then GUI.StyleFontString(label) end
    label:SetPoint("LEFT", 0, 2)
    label:SetText(text)
    label:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 1)
    line:SetPoint("BOTTOMRIGHT", 0, 1)
    line:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.38)
    if line.SetSnapToPixelGrid then
        line:SetSnapToPixelGrid(false)
        line:SetTexelSnappingBias(0)
    end

    self:AddWidget(parent, frame)
    return yOffset + 38
end

function ModernTrackerEditor:StyleToggleAsSwitch(widget)
    local checkbox = widget and widget.checkbox
    if not checkbox then return end

    checkbox:SetSize(44, 20)
    if checkbox.check then checkbox.check:Hide() end

    local knob = checkbox:CreateTexture(nil, "OVERLAY")
    knob:SetSize(14, 14)
    knob:SetColorTexture(1, 1, 1, 1)
    checkbox._modernKnob = knob

    checkbox.SetChecked = function(owner, checked)
        owner.isChecked = checked == true
        if owner.check then owner.check:Hide() end
        owner._modernKnob:ClearAllPoints()
        if owner.isChecked then
            owner:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            owner:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            owner._modernKnob:SetPoint("RIGHT", owner, "RIGHT", -3, 0)
        else
            owner:SetBackdropColor(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 1)
            owner:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.8)
            owner._modernKnob:SetPoint("LEFT", owner, "LEFT", 3, 0)
        end
    end
    checkbox:SetChecked(checkbox.isChecked)
end

function ModernTrackerEditor:CallSet(option, value)
    if not option or not option.set then return end
    if type(option.set) == "function" then
        option.set({ option = option }, value)
    end
    local profiles = DDingUI.SpecProfiles
    if profiles and profiles.MarkDirty then profiles:MarkDirty() end
end

function ModernTrackerEditor:CreateSegmented(parent, option, yOffset, labelText, orderedValues)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(32)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if GUI.StyleFontString then GUI.StyleFontString(label) end
    label:SetPoint("LEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)

    local values = type(option.values) == "function" and option.values({ option = option }) or option.values or {}
    local current = type(option.get) == "function" and option.get({ option = option }) or nil
    local group = CreateFrame("Frame", nil, frame)
    group:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    group:SetSize(#orderedValues * 52, 26)
    local buttons = {}

    local function RefreshButtons()
        current = type(option.get) == "function" and option.get({ option = option }) or current
        for _, button in ipairs(buttons) do
            local active = button._value == current
            if active then
                button:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.18)
                button:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)
                button._label:SetTextColor(THEME.accentLight[1], THEME.accentLight[2], THEME.accentLight[3], 1)
            else
                button:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], 0.95)
                button:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.72)
                button._label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            end
        end
    end

    for index, value in ipairs(orderedValues) do
        local button = CreateFrame("Button", nil, group, "BackdropTemplate")
        button:SetSize(52, 26)
        button:SetPoint("LEFT", group, "LEFT", (index - 1) * 52, 0)
        button:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        button._value = value
        button._label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if GUI.StyleFontString then GUI.StyleFontString(button._label) end
        button._label:SetPoint("CENTER", 0, 1)
        button._label:SetText(values[value] or value)
        button:SetScript("OnClick", function(owner)
            current = owner._value
            ModernTrackerEditor:CallSet(option, current)
            RefreshButtons()
        end)
        button:SetScript("OnEnter", function(owner)
            if owner._value ~= current then
                owner:SetBackdropColor(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], 0.72)
            end
        end)
        button:SetScript("OnLeave", RefreshButtons)
        buttons[#buttons + 1] = button
    end

    frame.Refresh = RefreshButtons
    RefreshButtons()
    self:AddWidget(parent, frame)
    return yOffset + 38
end

function ModernTrackerEditor:CreateSourceRow(parent, sourceOption, catalogOption, yOffset)
    local copy = self:CloneOption(sourceOption, rawget(L, "Source Spell") or "Source Spell")
    local widget = Widgets.CreateInput(parent, copy, yOffset, {})
    if widget.editBox and catalogOption and not self:IsHidden(catalogOption) then
        widget.editBox:ClearAllPoints()
        widget.editBox:SetPoint("RIGHT", widget, "RIGHT", -34, 0)
        widget.editBox:SetWidth(166)

        local catalogButton = CreateFrame("Button", nil, widget, "BackdropTemplate")
        catalogButton:SetSize(26, 24)
        catalogButton:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
        catalogButton:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        catalogButton:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], 1)
        catalogButton:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.8)
        local icon = catalogButton:CreateTexture(nil, "ARTWORK")
        icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetVertexColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        catalogButton:SetScript("OnClick", function()
            if type(catalogOption.func) == "function" then catalogOption.func({ option = catalogOption }) end
        end)
        catalogButton:SetScript("OnEnter", function(owner)
            owner:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            icon:SetVertexColor(THEME.accentLight[1], THEME.accentLight[2], THEME.accentLight[3], 1)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(rawget(L, "Choose from Catalog") or "Choose from Catalog")
            GameTooltip:Show()
        end)
        catalogButton:SetScript("OnLeave", function(owner)
            owner:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.8)
            icon:SetVertexColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            GameTooltip:Hide()
        end)
    end
    self:AddWidget(parent, widget)
    return yOffset + 38
end

function ModernTrackerEditor:FindOption(args, suffix)
    for key, option in pairs(args or {}) do
        if key:sub(-#suffix) == suffix and not self:IsHidden(option) then
            return option, key
        end
    end
end

function ModernTrackerEditor:CreateStandardWidget(parent, key, option, yOffset)
    if self:IsHidden(option) then return yOffset end
    local label = self:ResolveLabel(option, key)
    if label == "" and option.type ~= "description" then return yOffset end
    local clean = self:CloneOption(option, label)
    local widget
    local height

    if clean.type == "toggle" then
        widget = Widgets.CreateToggle(parent, clean, yOffset, {})
        self:StyleToggleAsSwitch(widget)
        height = 34
    elseif clean.type == "range" then
        widget = Widgets.CreateRange(parent, clean, yOffset, {})
        height = 38
    elseif clean.type == "select" then
        widget = Widgets.CreateSelect(parent, clean, yOffset, {}, key, { key })
        height = 42
    elseif clean.type == "color" then
        widget = Widgets.CreateColor(parent, clean, yOffset, {})
        height = 34
    elseif clean.type == "input" then
        widget = Widgets.CreateInput(parent, clean, yOffset, {})
        height = clean.multiline and 158 or 36
    elseif clean.type == "execute" then
        widget = Widgets.CreateExecute(parent, clean, yOffset, {})
        height = 34
    elseif clean.type == "header" then
        return self:CreateSection(parent, yOffset, label)
    elseif clean.type == "description" then
        local technical = key:find("_spellInfo", 1, true) ~= nil
        if technical then return yOffset end
        local isSection = key:lower():find("header", 1, true) ~= nil
            or tostring(option.name or ""):find("━", 1, true) ~= nil
        if isSection and label ~= "" then
            return self:CreateSection(parent, yOffset, label)
        end
        widget = Widgets.CreateDescription(parent, clean, yOffset, {})
        height = math.max(28, widget:GetHeight() + 4)
    end

    if widget then
        self:AddWidget(parent, widget)
        return yOffset + height
    end
    return yOffset
end

function ModernTrackerEditor:GetSortedOptions(args, excluded)
    local sorted = {}
    for key, option in pairs(args or {}) do
        if not excluded[key] and not self:IsHidden(option) then
            sorted[#sorted + 1] = { key = key, option = option }
        end
    end
    table.sort(sorted, function(left, right)
        local leftOrder = left.option.order or 999
        local rightOrder = right.option.order or 999
        if leftOrder == rightOrder then return left.key < right.key end
        return leftOrder < rightOrder
    end)
    return sorted
end

function ModernTrackerEditor:Render(parent, scrollFrame, scrollBar, tabGroup, context)
    if not tabGroup or not tabGroup.key then return false end
    local args = tabGroup.args or {}
    local yOffset = 14
    local excluded = {}

    if tabGroup.key == "general" then
        yOffset = self:CreateSection(parent, yOffset, rawget(L, "Tracker Settings") or "Tracker Settings")

        local enabled, enabledKey = self:FindOption(args, "_enabled")
        if enabled then
            excluded[enabledKey] = true
            yOffset = self:CreateStandardWidget(parent, enabledKey, enabled, yOffset)
        end

        local entry = context.entry
        if entry then
            local nameOption = {
                type = "input",
                name = rawget(L, "Tracker Name") or "Tracker Name",
                get = function() return entry.name or "" end,
                set = function(_, value)
                    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
                    if value == "" then return end
                    entry.name = value
                    if DDingUI.UpdateBuffTrackerBar then DDingUI:UpdateBuffTrackerBar() end
                    if context.panel.RefreshList then context.panel:RefreshList() end
                    if context.panel.RefreshLivePreview then context.panel:RefreshLivePreview(true) end
                    local profiles = DDingUI.SpecProfiles
                    if profiles and profiles.MarkDirty then profiles:MarkDirty() end
                end,
            }
            yOffset = self:CreateStandardWidget(parent, "trackerName", nameOption, yOffset)
        end

        local displayType, displayKey = self:FindOption(args, "_displayType")
        if displayType then
            excluded[displayKey] = true
            yOffset = self:CreateSegmented(parent, displayType, yOffset,
                rawget(L, "Display Type") or "Display Type",
                { "bar", "icon", "ring", "text", "sound", "trigger" })
        end

        yOffset = self:CreateSection(parent, yOffset + 4, rawget(L, "Tracking Source") or "Tracking Source")
        local trackingMode, trackingModeKey = self:FindOption(args, "_trackingMode")
        if trackingMode then
            excluded[trackingModeKey] = true
            yOffset = self:CreateStandardWidget(parent, trackingModeKey, trackingMode, yOffset)
        end

        local sourceOption, sourceKey = self:FindOption(args, "_changeSpellID")
        if not sourceOption then sourceOption, sourceKey = self:FindOption(args, "_spellID") end
        local catalogOption, catalogKey = self:FindOption(args, "_openCatalog")
        if sourceOption then
            excluded[sourceKey] = true
            if catalogKey then excluded[catalogKey] = true end
            yOffset = self:CreateSourceRow(parent, sourceOption, catalogOption, yOffset)
        end

        local spellInfo, spellInfoKey = self:FindOption(args, "_spellInfo")
        if spellInfo then excluded[spellInfoKey] = true end
        local spellHeader, spellHeaderKey = self:FindOption(args, "_spellHeader")
        if spellHeader then excluded[spellHeaderKey] = true end

        local remaining = self:GetSortedOptions(args, excluded)
        if #remaining > 0 then
            yOffset = self:CreateSection(parent, yOffset + 4, rawget(L, "Tracker Behavior") or "Tracker Behavior")
            for _, item in ipairs(remaining) do
                yOffset = self:CreateStandardWidget(parent, item.key, item.option, yOffset)
            end
        end
    else
        local sectionNames = {
            appearance = rawget(L, "Appearance Settings") or "Appearance Settings",
            position = rawget(L, "Position and Size") or "Position and Size",
            text = rawget(L, "Text Settings") or "Text Settings",
            conditions = rawget(L, "Condition Settings") or "Condition Settings",
            actions = rawget(L, "Action Settings") or "Action Settings",
        }
        yOffset = self:CreateSection(parent, yOffset, sectionNames[tabGroup.key] or tabGroup.name)
        local sorted = self:GetSortedOptions(args, excluded)
        for _, item in ipairs(sorted) do
            yOffset = self:CreateStandardWidget(parent, item.key, item.option, yOffset)
        end
    end

    if yOffset <= 52 then
        local empty = {
            type = "description",
            name = rawget(L, "No options in this section") or "No options in this section.",
        }
        yOffset = self:CreateStandardWidget(parent, "empty", empty, yOffset)
    end

    parent:SetHeight(math.max(yOffset + 24, scrollFrame:GetHeight() or 1))
    C_Timer.After(0.02, function()
        if scrollBar and scrollBar.UpdateThumbPosition then scrollBar.UpdateThumbPosition() end
    end)
    return true
end

function GUI.CreateBuffTrackerPanel(contentFrame, parentFrame)
    -- contentFrame = scrollChild, parentFrame = main frame
    local contentArea = parentFrame.contentArea

    -- 기존 스크롤 UI 숨기기 (커스텀 패널이 대체)
    parentFrame.scrollFrame:Hide()
    if parentFrame.scrollBar then parentFrame.scrollBar:Hide() end

    -- 기존 패널 재사용 (레이아웃 변경 시에는 강제 재생성)
    if contentArea._btPanel then
        -- 리스트 버튼 정리 후 재생성
        for _, btn in ipairs(contentArea._btPanel.listButtons or {}) do
            btn:Hide()
            btn:SetParent(nil)
        end
        contentArea._btPanel.listButtons = {}
        contentArea._btPanel:Hide()
        contentArea._btPanel:SetParent(nil)
        contentArea._btPanel = nil
    end

    local SIDE_W = 220
    local CATALOG_W = 300
    local ITEM_H = math.max(Tokens and Tokens.ROW_H or 22, 30)
    local TAB_H  = Tokens and Tokens.TABBAR_H or 32

    -- [FIX] GUI용 trackedBuffs 획득 헬퍼 (GetDisplayOrder와 동일한 소스)
    local function GetTrackedBuffsForGUI()
        if DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec then
            local specIdx = GetSpecialization and GetSpecialization() or 1
            local specID = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx) or 0
            return DDingUI.db.global.trackedBuffsPerSpec[specID] or {}
        end
        local rootCfg = DDingUI.db.profile.buffTrackerBar
        return rootCfg and rootCfg.trackedBuffs or {}
    end

    -- [DDINGUI] WidgetRefresh 컨텍스트 생성
    local wrCtx = WR and WR.CreateContext("CDM_BuffTracker") or nil

    -- ─── 메인 컨테이너 ───
    local btPanel = CreateFrame("Frame", nil, contentArea)
    btPanel:SetAllPoints(contentArea)
    btPanel:SetFrameStrata("DIALOG")
    btPanel:SetFrameLevel(contentArea:GetFrameLevel() + 5)
    btPanel._wrCtx = wrCtx
    contentArea._btPanel = btPanel

    -- ─── 좌측 패널: 트래커 리스트 ───
    local leftPanel = CreateFrame("Frame", nil, btPanel, "BackdropTemplate")
    leftPanel:SetPoint("TOPLEFT", 0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", 0, 0)
    leftPanel:SetWidth(SIDE_W)
    leftPanel:SetBackdrop({bgFile = FLAT})
    leftPanel:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 1)

    local sidebarTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sidebarTitle:SetPoint("TOPLEFT", 12, -12)
    sidebarTitle:SetText(L["Custom Aura"] or "Custom Aura")
    sidebarTitle:SetTextColor(THEME.textBright[1], THEME.textBright[2], THEME.textBright[3], 1)

    local sidebarCount = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sidebarCount:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -12, -14)
    sidebarCount:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.9)

    -- 검색 바
    local searchFrame = CreateFrame("Frame", nil, leftPanel)
    searchFrame:SetPoint("TOPLEFT", 8, -38)
    searchFrame:SetPoint("TOPRIGHT", -8, -38)
    searchFrame:SetHeight(28)

    -- Preview 토글 버튼 (검색바 오른쪽)
    local PREVIEW_BTN_W = 22
    local previewBtn = CreateFrame("Button", nil, searchFrame, "BackdropTemplate")
    previewBtn:SetSize(PREVIEW_BTN_W + 4, 28)
    previewBtn:SetPoint("RIGHT", searchFrame, "RIGHT", 0, 0)
    previewBtn:SetBackdrop({bgFile = FLAT, edgeFile = FLAT, edgeSize = 1})
    previewBtn:SetBackdropColor(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 1)
    previewBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.6)

    local previewIcon = previewBtn:CreateTexture(nil, "ARTWORK")
    previewIcon:SetSize(14, 14)
    previewIcon:SetPoint("CENTER", 0, 0)
    previewIcon:SetAtlas("socialqueuing-icon-eye")

    -- Preview state tracking
    local isPreviewOn = DDingUI.IsBuffTrackerPreviewEnabled and DDingUI:IsBuffTrackerPreviewEnabled() or false
    local function UpdatePreviewButtonVisual()
        if isPreviewOn then
            previewBtn:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.35)
            previewBtn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.8)
            previewIcon:SetDesaturated(false)
            previewIcon:SetAlpha(1)
        else
            previewBtn:SetBackdropColor(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 1)
            previewBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.6)
            previewIcon:SetDesaturated(true)
            previewIcon:SetAlpha(0.5)
        end
    end
    UpdatePreviewButtonVisual()

    previewBtn:SetScript("OnClick", function()
        if DDingUI.ToggleBuffTrackerPreview then
            DDingUI:ToggleBuffTrackerPreview()
            isPreviewOn = DDingUI:IsBuffTrackerPreviewEnabled()
            UpdatePreviewButtonVisual()
        end
    end)
    previewBtn:SetScript("OnEnter", function(self)
        previewBtn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        previewIcon:SetDesaturated(false)
        previewIcon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Preview Mode"] or "Preview Mode")
        GameTooltip:AddLine(L["Show all tracked buffs for configuration (ignores hideWhenZero)"] or "Show all tracked buffs for configuration (ignores hideWhenZero)", 0.7, 0.7, 0.7, true)
        if isPreviewOn then
            GameTooltip:AddLine("\n|cff00ff00ON|r — " .. (L["Click to disable preview"] or "Click to disable"), 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine("\n|cffff6600OFF|r — " .. (L["Click to enable preview"] or "Click to enable"), 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    previewBtn:SetScript("OnLeave", function()
        UpdatePreviewButtonVisual()
        GameTooltip:Hide()
    end)

    -- 검색 입력 배경 (Preview 버튼 왼쪽까지)
    local searchInputFrame = CreateFrame("Frame", nil, searchFrame, "BackdropTemplate")
    searchInputFrame:SetPoint("TOPLEFT", 0, 0)
    searchInputFrame:SetPoint("BOTTOMRIGHT", previewBtn, "BOTTOMLEFT", -3, 0)
    searchInputFrame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    searchInputFrame:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], THEME.input[4] or 0.8)
    searchInputFrame:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.65)

    local trackerSearchIcon = searchInputFrame:CreateTexture(nil, "ARTWORK")
    trackerSearchIcon:SetSize(13, 13)
    trackerSearchIcon:SetPoint("LEFT", 7, 0)
    trackerSearchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    trackerSearchIcon:SetVertexColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.85)

    local searchBox = CreateFrame("EditBox", nil, searchInputFrame)
    searchBox:SetAllPoints()
    searchBox:SetFontObject(GameFontNormalSmall)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(25, 6, 0, 0)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        if btPanel.RefreshList then btPanel:RefreshList(self:GetText()) end
    end)

    -- placeholder
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 25, 0)
    searchPlaceholder:SetText(L["Search trackers..."] or "Search trackers...")
    searchBox:SetScript("OnEditFocusGained", function() searchPlaceholder:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchPlaceholder:Show() end
    end)

    -- 트래커 스크롤 리스트
    local listScroll = CreateFrame("ScrollFrame", nil, leftPanel)
    listScroll:SetPoint("TOPLEFT", searchFrame, "BOTTOMLEFT", -5, -4)
    listScroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", 0, 0)
    listScroll:EnableMouseWheel(true)

    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(SIDE_W)
    listScroll:SetScrollChild(listChild)

    listScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = math.max(0, listChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 22)))
    end)

    -- ─── 구분선 ───
    local divider = btPanel:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.6)
    -- [DDINGUI] PP: disable pixel snap for crisp 1px
    if divider.SetSnapToPixelGrid then
        divider:SetSnapToPixelGrid(false)
        divider:SetTexelSnappingBias(0)
    end
    divider:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 0, 0)

    -- ─── 우측 카탈로그: 검색과 추가를 편집 화면에 상시 노출 ───
    local catalogPanel = CreateAuraCatalogPane(btPanel, CreateCustomScrollBar)
    catalogPanel:SetPoint("TOPRIGHT", btPanel, "TOPRIGHT", 0, 0)
    catalogPanel:SetPoint("BOTTOMRIGHT", btPanel, "BOTTOMRIGHT", 0, 0)
    catalogPanel:SetWidth(CATALOG_W)

    local catalogDivider = btPanel:CreateTexture(nil, "ARTWORK")
    catalogDivider:SetWidth(1)
    catalogDivider:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.6)
    catalogDivider:SetPoint("TOPRIGHT", catalogPanel, "TOPLEFT", 0, 0)
    catalogDivider:SetPoint("BOTTOMRIGHT", catalogPanel, "BOTTOMLEFT", 0, 0)

    -- ─── 중앙 패널: 미리보기 + 탭 + 설정 ───
    local rightPanel = CreateFrame("Frame", nil, btPanel)
    rightPanel:SetPoint("TOPLEFT", divider, "TOPRIGHT", 0, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", catalogDivider, "BOTTOMLEFT", 0, 0)

    local livePreview = CreateTrackerLivePreview(rightPanel)
    livePreview:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -10)
    livePreview:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -10, -10)

    -- 탭 바
    local tabBar = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
    tabBar:SetPoint("TOPLEFT", livePreview, "BOTTOMLEFT", -10, -8)
    tabBar:SetPoint("TOPRIGHT", livePreview, "BOTTOMRIGHT", 10, -8)
    tabBar:SetHeight(TAB_H)
    tabBar:SetBackdrop({bgFile = FLAT})
    tabBar:SetBackdropColor(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 0.95)

    -- 탭 콘텐츠 (스크롤 영역)
    local tabScrollFrame = CreateFrame("ScrollFrame", nil, rightPanel)
    tabScrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -2)
    tabScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -12, 2)
    tabScrollFrame:EnableMouseWheel(true)

    local tabChild = CreateFrame("Frame", nil, tabScrollFrame)
    tabChild:SetWidth(tabScrollFrame:GetWidth() or 400)
    tabChild.widgets = {}
    tabScrollFrame:SetScrollChild(tabChild)

    -- 탭 콘텐츠 너비 동기화
    tabScrollFrame:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w and w > 0 then tabChild:SetWidth(w - 1) end
    end)

    tabScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = math.max(0, tabChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 25)))
    end)

    -- 커스텀 스크롤바 (우측 탭 콘텐츠용)
    local tabScrollBar = CreateCustomScrollBar(rightPanel, tabScrollFrame)
    tabScrollBar:SetPoint("TOPLEFT", tabScrollFrame, "TOPRIGHT", 3, 0)
    tabScrollBar:SetPoint("BOTTOMLEFT", tabScrollFrame, "BOTTOMRIGHT", 3, 0)
    tabScrollFrame.ScrollBar = tabScrollBar

    -- scrollChild 높이 변경 시 스크롤바 업데이트
    tabChild:SetScript("OnSizeChanged", function()
        C_Timer.After(0.02, function()
            if tabScrollBar and tabScrollBar.UpdateThumbPosition then
                tabScrollBar.UpdateThumbPosition()
            end
        end)
    end)

    -- 참조 저장
    btPanel.leftPanel = leftPanel
    btPanel.rightPanel = rightPanel
    btPanel.catalogPanel = catalogPanel
    btPanel.livePreview = livePreview
    btPanel.sidebarCount = sidebarCount
    btPanel.searchBox = searchBox
    btPanel.previewBtn = previewBtn
    btPanel.listScroll = listScroll
    btPanel.listChild = listChild
    btPanel.tabBar = tabBar
    btPanel.tabScrollFrame = tabScrollFrame
    btPanel.tabChild = tabChild
    btPanel.tabScrollBar = tabScrollBar
    btPanel.selectedIndex = nil
    btPanel.selectedTab = nil
    btPanel.tabButtons = {}
    btPanel.listButtons = {}
    btPanel._parentFrame = parentFrame

    -- ─── 헬퍼: 탭 콘텐츠 위젯 정리 ───
    local function ClearTabContent()
        if tabChild.widgets then
            for i = #tabChild.widgets, 1, -1 do
                local w = tabChild.widgets[i]
                if w then w:Hide(); w:SetParent(nil) end
            end
        end
        tabChild.widgets = {}
        if tabChild.subScrollChild then
            if tabChild.subScrollChild.widgets then
                for i = #tabChild.subScrollChild.widgets, 1, -1 do
                    local w = tabChild.subScrollChild.widgets[i]
                    if w then w:Hide(); w:SetParent(nil) end
                end
            end
            tabChild.subScrollChild:Hide()
            tabChild.subScrollChild:SetParent(nil)
            tabChild.subScrollChild = nil
        end
        if tabChild.subTabButtons then
            for _, button in ipairs(tabChild.subTabButtons) do
                button:Hide()
                button:SetParent(nil)
            end
            tabChild.subTabButtons = nil
        end
        if tabChild.subTabContainer then
            tabChild.subTabContainer:Hide()
            tabChild.subTabContainer:SetParent(nil)
            tabChild.subTabContainer = nil
        end
        if tabChild.subContentArea then
            tabChild.subContentArea:Hide()
            tabChild.subContentArea:SetParent(nil)
            tabChild.subContentArea = nil
        end
        tabChild:SetHeight(1)
        tabScrollFrame:SetVerticalScroll(0)
    end

    function btPanel:RefreshLivePreview(force)
        local entry
        local trackedBuffs = GetTrackedBuffsForGUI()
        if type(self.selectedIndex) == "number" then
            entry = trackedBuffs[self.selectedIndex]
        end
        local signature = livePreview.GetSignature
            and livePreview:GetSignature(entry, trackedBuffs)
            or tostring(entry)
        if not force and self._previewSignature == signature then return end
        self._previewSignature = signature
        livePreview:Refresh(entry, trackedBuffs)
    end

    livePreview:SetScript("OnUpdate", function(self, elapsed)
        self._refreshElapsed = (self._refreshElapsed or 0) + elapsed
        if self._refreshElapsed < 0.2 then return end
        self._refreshElapsed = 0
        btPanel:RefreshLivePreview()
    end)
    livePreview:SetScript("OnSizeChanged", function()
        btPanel:RefreshLivePreview(true)
    end)

    -- ─── 트래커 리스트 렌더링 ───
    function btPanel:RefreshList(searchQueryRaw)
        local searchQ = (searchQueryRaw or searchBox:GetText() or ""):lower()
        local rootCfg = DDingUI.db.profile.buffTrackerBar
        local trackedBuffs = GetTrackedBuffsForGUI()  -- [FIX] global per-spec 소스
        sidebarCount:SetText(tostring(#trackedBuffs))

        -- 기존 버튼 숨기기
        for _, btn in ipairs(self.listButtons) do btn:Hide() end

        local yOff = 0
        local btnIdx = 0

        -- ─── 상단 고정 항목 ───
        local staticItems = {
            { key = "wizard", name = "|cffff6a00+ " .. (L["New Tracker"] or "New Tracker") .. "|r" },
        }
        for _, si in ipairs(staticItems) do
            btnIdx = btnIdx + 1
            local btn = self.listButtons[btnIdx]
            if not btn then
                btn = CreateFrame("Button", nil, listChild)
                btn:SetHeight(ITEM_H + 2)
                btn._bg = btn:CreateTexture(nil, "BACKGROUND")
                btn._bg:SetAllPoints()
                btn._bg:SetColorTexture(0, 0, 0, 0)
                btn._stripe = btn:CreateTexture(nil, "OVERLAY")
                btn._stripe:SetWidth(2)
                btn._stripe:SetPoint("TOPLEFT", 0, 0)
                btn._stripe:SetPoint("BOTTOMLEFT", 0, 0)
                btn._stripe:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                btn._stripe:Hide()
                btn._text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn._text:SetPoint("LEFT", 10, 0)
                btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                btn._text:SetJustifyH("LEFT")
                self.listButtons[btnIdx] = btn
            end
            btn:Show()
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -yOff)
            btn:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)
            btn._text:SetText(si.name)
            btn._text:ClearAllPoints()
            btn._text:SetPoint("LEFT", 10, 0)
            btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)

            if self.selectedIndex == si.key then
                btn._bg:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.15)
                btn._stripe:Show()
            else
                btn._bg:SetColorTexture(0, 0, 0, 0)
                btn._stripe:Hide()
            end

            local siKey = si.key
            btn:SetScript("OnEnter", function(self)
                if btPanel.selectedIndex ~= siKey then
                    self._bg:SetColorTexture(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], 0.6)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if btPanel.selectedIndex ~= siKey then
                    self._bg:SetColorTexture(0, 0, 0, 0)
                end
            end)
            btn:SetScript("OnClick", function()
                if si.action then
                    si.action()
                else
                    btPanel:SelectStatic(siKey)
                end
            end)

            yOff = yOff + (ITEM_H + 2) + 1
        end

        -- ─── 구분선 ───
        yOff = yOff + 4
        btnIdx = btnIdx + 1
        local sep = self.listButtons[btnIdx]
        if not sep then
            sep = CreateFrame("Frame", nil, listChild)
            sep:SetHeight(1)
            sep._line = sep:CreateTexture(nil, "ARTWORK")
            sep._line:SetAllPoints()
            sep._line:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.3)
            -- [DDINGUI] PP
            if sep._line.SetSnapToPixelGrid then
                sep._line:SetSnapToPixelGrid(false)
                sep._line:SetTexelSnappingBias(0)
            end
            self.listButtons[btnIdx] = sep
        end
        sep:Show()
        sep:ClearAllPoints()
        sep:SetPoint("TOPLEFT", listChild, "TOPLEFT", 8, -yOff)
        sep:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
        yOff = yOff + 6

        -- ─── 트래커 리스트 헤더 ───
        btnIdx = btnIdx + 1
        local hdr = self.listButtons[btnIdx]
        if not hdr then
            hdr = CreateFrame("Frame", nil, listChild)
            hdr:SetHeight(16)
            hdr._text = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hdr._text:SetPoint("LEFT", 8, 0)
            hdr._text:SetJustifyH("LEFT")
            self.listButtons[btnIdx] = hdr
        end
        hdr:Show()
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -yOff)
        hdr:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)
        hdr._text:SetText("|cff888888" .. (L["Tracked Buffs"] or "Tracked Buffs") .. " (" .. #trackedBuffs .. ")|r")
        yOff = yOff + 18

        -- GetDisplayOrder로 계층적 렌더링 (그룹 + 자식)
        local displayOrder = DDingUI.GetDisplayOrder and DDingUI.GetDisplayOrder(false) or {}

        for _, entry in ipairs(displayOrder) do
            local i = entry.index
            local buff = trackedBuffs[i]
            if buff then  -- buff가 nil이면 건너뛰기

            local buffName = buff.name or "Unknown"
            if not buff.isGroup and buff.spellID and buff.spellID > 0 then
                local ok, spellName = pcall(C_Spell.GetSpellName, buff.spellID)
                if ok and spellName then buffName = spellName end
            end

            -- 검색 필터
            local passFilter = (searchQ == "" or buffName:lower():find(searchQ, 1, true))
            if passFilter then

            btnIdx = btnIdx + 1
            local btn = self.listButtons[btnIdx]
            if not btn then
                btn = CreateFrame("Button", nil, listChild)
                btn:SetHeight(ITEM_H)
                btn._bg = btn:CreateTexture(nil, "BACKGROUND")
                btn._bg:SetAllPoints()
                btn._bg:SetColorTexture(0, 0, 0, 0)
                -- accent stripe (좌측 2px)
                btn._stripe = btn:CreateTexture(nil, "OVERLAY")
                btn._stripe:SetWidth(2)
                btn._stripe:SetPoint("TOPLEFT", 0, 0)
                btn._stripe:SetPoint("BOTTOMLEFT", 0, 0)
                btn._stripe:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                -- [DDINGUI] PP + accent 등록
                if btn._stripe.SetSnapToPixelGrid then
                    btn._stripe:SetSnapToPixelGrid(false)
                    btn._stripe:SetTexelSnappingBias(0)
                end
                if WR then WR.RegAccent("solid", btn._stripe) end
                btn._stripe:Hide()
                -- 접기/펼치기 화살표 (그룹용)
                btn._arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn._arrow:SetPoint("LEFT", 6, 0)
                btn._arrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                btn._arrow:Hide()
                -- 스펠 아이콘
                btn._icon = btn:CreateTexture(nil, "ARTWORK")
                btn._icon:SetSize(20, 20)
                btn._icon:SetPoint("LEFT", 6, 0)
                btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                -- 이름 텍스트
                btn._text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn._text:SetPoint("LEFT", btn._icon, "RIGHT", 4, 0)
                btn._text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                btn._text:SetJustifyH("LEFT")
                -- 타입 태그 텍스트 (우측)
                btn._typeTag = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn._typeTag:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
                btn._typeTag:SetJustifyH("RIGHT")
                btn._typeTag:Hide()
                -- enable/disable 토글 (우측 끝 작은 동그라미)
                btn._toggle = CreateFrame("Button", nil, btn)
                btn._toggle:SetSize(10, 10)
                btn._toggle:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                btn._toggle._dot = btn._toggle:CreateTexture(nil, "OVERLAY")
                btn._toggle._dot:SetAllPoints()
                btn._toggle._dot:SetColorTexture(0.27, 0.93, 0.27, 1)
                btn._toggle:Hide()

                -- [DRAG] 드롭 하이라이트 (그룹 위에 드래그 시 표시)
                btn._dropHL = btn:CreateTexture(nil, "OVERLAY", nil, 6)
                btn._dropHL:SetAllPoints()
                btn._dropHL:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.25)
                btn._dropHL:Hide()

                -- [GROUP] 우측 접기/펼치기 화살표 버튼
                btn._expandBtn = CreateFrame("Button", nil, btn)
                btn._expandBtn:SetSize(18, ITEM_H)
                btn._expandBtn:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
                btn._expandBtn._text = btn._expandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn._expandBtn._text:SetAllPoints()
                btn._expandBtn._text:SetJustifyH("CENTER")
                btn._expandBtn._text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                btn._expandBtn:Hide()

                btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                btn:RegisterForDrag("LeftButton")
                self.listButtons[btnIdx] = btn
            end

            btn:Show()
            btn:ClearAllPoints()

            -- 깊이에 따른 들여쓰기 (16px per depth level)
            local indent = (entry.depth or 0) * 16
            btn:SetPoint("TOPLEFT", listChild, "TOPLEFT", indent, -yOff)
            btn:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)

            -- 초기화
            btn._typeTag:Hide()
            btn._toggle:Hide()

            if entry.isGroup then
                -- ─── 그룹 항목 렌더링 ───
                local childCount = buff.controlledChildren and #buff.controlledChildren or 0
                local arrowChar = (buff.expanded ~= false) and "▼" or "▶"
                btn._arrow:SetText(arrowChar)
                btn._arrow:Show()
                btn._arrow:ClearAllPoints()
                btn._arrow:SetPoint("LEFT", indent + 4, 0)

                btn._icon:Hide()
                btn._text:ClearAllPoints()
                btn._text:SetPoint("LEFT", btn._arrow, "RIGHT", 4, 0)
                btn._text:SetPoint("RIGHT", btn._expandBtn, "LEFT", -2, 0)
                btn._text:SetText(buffName .. "  |cff555555(" .. childCount .. ")|r")

                -- 우측 접기/펼치기 화살표 버튼
                local expandChar = (buff.expanded ~= false) and "▲" or "▼"
                btn._expandBtn._text:SetText(expandChar)
                btn._expandBtn:Show()
                local gIdx2 = i
                btn._expandBtn:SetScript("OnClick", function()
                    local wasExpanded = trackedBuffs[gIdx2].expanded ~= false  -- nil = 열림
                    trackedBuffs[gIdx2].expanded = not wasExpanded
                    btPanel:RefreshList()
                end)
                btn._expandBtn:SetScript("OnEnter", function(self)
                    self._text:SetTextColor(THEME.textBright[1], THEME.textBright[2], THEME.textBright[3])
                end)
                btn._expandBtn:SetScript("OnLeave", function(self)
                    self._text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                end)

                -- 그룹 활성 상태 dot
                btn._toggle:Show()
                btn._toggle:ClearAllPoints()
                btn._toggle:SetPoint("RIGHT", btn._expandBtn, "LEFT", -2, 0)
                if buff.disabled then
                    btn._text:SetTextColor(0.4, 0.4, 0.4)
                    btn._arrow:SetTextColor(0.4, 0.4, 0.4)
                    btn._toggle._dot:SetColorTexture(0.4, 0.4, 0.4, 0.6)
                else
                    btn._text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
                    btn._arrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                    btn._toggle._dot:SetColorTexture(0.27, 0.93, 0.27, 1)
                end

                local gIdx = i
                btn._toggle:SetScript("OnClick", function()
                    trackedBuffs[gIdx].disabled = not trackedBuffs[gIdx].disabled
                    DDingUI:UpdateBuffTrackerBar()
                    btPanel:RefreshList()
                end)
            else
                -- ─── 일반 트래커 항목 렌더링 ───
                btn._arrow:Hide()
                btn._expandBtn:Hide()

                -- 아이콘 위치 조정 (들여쓰기 반영)
                btn._icon:ClearAllPoints()
                btn._icon:SetPoint("LEFT", indent + 6, 0)
                if buff.icon then
                    btn._icon:SetTexture(buff.icon)
                    btn._icon:Show()
                else
                    btn._icon:Hide()
                end

                -- 타입 태그 [BAR] / [ICON] 등
                local dType = (buff.displayType or "bar"):upper()
                btn._typeTag:SetText("|cff555555" .. dType .. "|r")
                btn._typeTag:ClearAllPoints()
                btn._typeTag:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
                btn._typeTag:Show()

                -- enable/disable dot
                btn._toggle:Show()
                btn._toggle:ClearAllPoints()
                btn._toggle:SetPoint("RIGHT", btn, "RIGHT", -4, 0)

                btn._text:ClearAllPoints()
                btn._text:SetPoint("LEFT", btn._icon, "RIGHT", 4, 0)
                btn._text:SetPoint("RIGHT", btn._typeTag, "LEFT", -4, 0)
                btn._text:SetText(buffName)

                -- [REFACTOR] 버프/능력 이름 색상 분기
                local isAura = buff.isAura
                if isAura == nil then
                    -- 폴백: CDMScanner에서 확인
                    local cdID = buff.cooldownID or (buff.trigger and buff.trigger.cooldownID)
                    if cdID and DDingUI.CDMScanner then
                        local cdmEntry = DDingUI.CDMScanner.GetEntry(cdID)
                        if cdmEntry then isAura = cdmEntry.isAura end
                    end
                end
                -- 색상: 버프=따뜻한 주황, 능력=하늘색
                local nameR, nameG, nameB
                if isAura then
                    nameR, nameG, nameB = 0.95, 0.78, 0.40  -- 버프: warm gold
                else
                    nameR, nameG, nameB = 0.55, 0.85, 1.00  -- 능력: sky blue
                end

                if buff.disabled then
                    btn._text:SetTextColor(0.4, 0.4, 0.4)
                    btn._icon:SetAlpha(0.4)
                    btn._toggle._dot:SetColorTexture(0.4, 0.4, 0.4, 0.6)
                else
                    btn._text:SetTextColor(nameR, nameG, nameB)
                    btn._icon:SetAlpha(1.0)
                    btn._toggle._dot:SetColorTexture(0.27, 0.93, 0.27, 1)
                end

                local tIdx = i
                btn._toggle:SetScript("OnClick", function()
                    trackedBuffs[tIdx].disabled = not trackedBuffs[tIdx].disabled
                    DDingUI:UpdateBuffTrackerBar()
                    btPanel:RefreshList()
                end)
            end

            -- [DDINGUI] 얼룩말 줄무늬 + 선택 하이라이트
            local rowAlpha = Tokens and Tokens.RowBgAlpha(btnIdx) or 0
            if self.selectedIndex == i then
                -- 선택됨: accent 배경 + stripe 표시 + 펄스
                btn._bg:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.18)
                if not entry.isGroup then
                    btn._text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
                end
                btn._stripe:Show()
            else
                -- 비선택: 얼룩말 배경
                btn._bg:SetColorTexture(1, 1, 1, rowAlpha)
                btn._stripe:Hide()
            end

            -- [DDINGUI] 3단계 호버 (bg + text 동시 변환)
            local idx = i
            local isGroup = entry.isGroup
            local normalTextR, normalTextG, normalTextB
            if self.selectedIndex == i then
                normalTextR = THEME.accent[1]
                normalTextG = THEME.accent[2]
                normalTextB = THEME.accent[3]
            elseif isGroup and not (buff.disabled) then
                normalTextR = THEME.accent[1]
                normalTextG = THEME.accent[2]
                normalTextB = THEME.accent[3]
            elseif buff.disabled then
                normalTextR, normalTextG, normalTextB = 0.4, 0.4, 0.4
            else
                -- [REFACTOR] 버프/능력 색상 사용
                if buff.isAura then
                    normalTextR, normalTextG, normalTextB = 0.95, 0.78, 0.40
                elseif buff.isAura == false then
                    normalTextR, normalTextG, normalTextB = 0.55, 0.85, 1.00
                else
                    normalTextR = THEME.text[1]
                    normalTextG = THEME.text[2]
                    normalTextB = THEME.text[3]
                end
            end

            btn:SetScript("OnEnter", function(self)
                if btPanel.selectedIndex ~= idx then
                    -- 호버: 배경 밝아짐 + 텍스트 밝아짐
                    local hoverBgA = Tokens and Tokens.BTN_BG_HA or 0.15
                    self._bg:SetColorTexture(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], hoverBgA + 0.45)
                    self._text:SetTextColor(THEME.textBright[1], THEME.textBright[2], THEME.textBright[3])
                    -- 호버 시 stripe 살짝 표시 (accent 30% 투명)
                    self._stripe:SetAlpha(0.3)
                    self._stripe:Show()
                end
                -- 툴팁
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(buffName, 1, 1, 1)
                if isGroup then
                    local cc = trackedBuffs[idx] and trackedBuffs[idx].controlledChildren or {}
                    GameTooltip:AddLine((L["Group"] or "Group") .. " (" .. #cc .. " " .. (L["children"] or "children") .. ")", 0.7, 0.7, 0.7)
                else
                    local b = trackedBuffs[idx]
                    if b then
                        GameTooltip:AddLine((b.displayType or "bar"):upper(), THEME.accent[1], THEME.accent[2], THEME.accent[3])
                        local idText = b.spellID and b.spellID > 0 and ("Spell ID: " .. b.spellID) or (b.cooldownID and ("CDM ID: " .. b.cooldownID) or "")
                        if idText ~= "" then GameTooltip:AddLine(idText, 0.5, 0.5, 0.5) end
                        if b.parentGroup then
                            local pg = trackedBuffs[b.parentGroup]
                            if pg then GameTooltip:AddLine("→ " .. (pg.name or "Group"), 0.4, 0.4, 0.8) end
                        end
                    end
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                if btPanel.selectedIndex ~= idx then
                    -- [DDINGUI] 3단계 복원: 얼룩말 배경 + 원래 텍스트 + stripe 숨김
                    self._bg:SetColorTexture(1, 1, 1, rowAlpha)
                    self._text:SetTextColor(normalTextR, normalTextG, normalTextB)
                    self._stripe:Hide()
                end
                GameTooltip:Hide()
            end)
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if isGroup then
                        btPanel:ShowGroupContextMenu(idx, self)
                    else
                        btPanel:ShowTrackerContextMenu(idx, self)
                    end
                    return
                end
                if isGroup then
                    -- 왼클릭: 그룹 설정 선택 (접기/펼치기는 우측 화살표 버튼)
                    btPanel.selectedIndex = idx
                    btPanel:RefreshList()
                    btPanel:RenderGroupSettings(idx)
                else
                    btPanel:SelectTracker(idx)
                end
            end)

            -- [DRAG] 드래그 앤 드롭: 순서 변경 + 그룹 편입
            btn:RegisterForDrag("LeftButton")
            do
                local dragIdx = idx
                local dragIsGroup = isGroup
                btn:SetScript("OnDragStart", function(self)
                    btPanel._dragIndex = dragIdx
                    btPanel._dragIsGroup = dragIsGroup
                    btPanel._dragBtn = self
                    self:SetAlpha(0.4)
                    -- 드래그 레이블
                    if not btPanel._dragLabel then
                        btPanel._dragLabel = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    end
                    btPanel._dragLabel:SetText("|cffcccccc" .. buffName .. "|r")
                    btPanel._dragLabel:Show()
                    -- 삽입 인디케이터
                    if not btPanel._insertBar then
                        btPanel._insertBar = listChild:CreateTexture(nil, "OVERLAY", nil, 7)
                        btPanel._insertBar:SetHeight(2)
                        btPanel._insertBar:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                    end
                    if not btPanel._insertGlow then
                        btPanel._insertGlow = listChild:CreateTexture(nil, "OVERLAY", nil, 6)
                        btPanel._insertGlow:SetHeight(8)
                        btPanel._insertGlow:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.3)
                    end
                    btPanel._insertBar:Hide()
                    btPanel._insertGlow:Hide()
                    btPanel._dropTarget = nil
                    -- 그룹 드롭 하이라이트 (비그룹을 그룹 위에 드래그 시)
                    if not dragIsGroup then
                        for bi = 1, #btPanel.listButtons do
                            local b = btPanel.listButtons[bi]
                            if b and b:IsShown() and b._entryIsGroup and b._dropHL then
                                b._dropHL:Show()
                            end
                        end
                    end
                    -- OnUpdate: 삽입 위치 추적
                    listChild:SetScript("OnUpdate", function(_, elapsed)
                        local label = btPanel._dragLabel
                        if label and label:IsShown() then
                            local cx, cy = GetCursorPosition()
                            local scale = UIParent:GetEffectiveScale()
                            label:ClearAllPoints()
                            label:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx/scale + 12, cy/scale)
                        end
                        -- 삽입 인디케이터 위치 계산
                        local bestBtn, bestDist, bestPos = nil, 9999, nil
                        for bi = 1, #btPanel.listButtons do
                            local b = btPanel.listButtons[bi]
                            if b and b:IsShown() and b._entryIndex and b._entryIndex ~= btPanel._dragIndex then
                                local top = b:GetTop()
                                local bot = b:GetBottom()
                                local cx2, cy2 = GetCursorPosition()
                                local s2 = UIParent:GetEffectiveScale()
                                local curY = cy2 / s2
                                if top and bot then
                                    -- 상단 삽입점
                                    local distTop = math.abs(curY - top)
                                    if distTop < bestDist then
                                        bestDist = distTop
                                        bestBtn = b
                                        bestPos = "before"
                                    end
                                    -- 하단 삽입점
                                    local distBot = math.abs(curY - bot)
                                    if distBot < bestDist then
                                        bestDist = distBot
                                        bestBtn = b
                                        bestPos = "after"
                                    end
                                end
                            end
                        end
                        if bestBtn and bestDist < 20 then
                            local bar = btPanel._insertBar
                            local glow = btPanel._insertGlow
                            bar:ClearAllPoints()
                            glow:ClearAllPoints()
                            if bestPos == "before" then
                                bar:SetPoint("TOPLEFT", bestBtn, "TOPLEFT", 5, 1)
                                bar:SetPoint("TOPRIGHT", bestBtn, "TOPRIGHT", -5, 1)
                                glow:SetPoint("TOPLEFT", bestBtn, "TOPLEFT", 2, 4)
                                glow:SetPoint("TOPRIGHT", bestBtn, "TOPRIGHT", -2, 4)
                            else
                                bar:SetPoint("BOTTOMLEFT", bestBtn, "BOTTOMLEFT", 5, -1)
                                bar:SetPoint("BOTTOMRIGHT", bestBtn, "BOTTOMRIGHT", -5, -1)
                                glow:SetPoint("BOTTOMLEFT", bestBtn, "BOTTOMLEFT", 2, -4)
                                glow:SetPoint("BOTTOMRIGHT", bestBtn, "BOTTOMRIGHT", -2, -4)
                            end
                            bar:Show()
                            glow:Show()
                            btPanel._dropTarget = { index = bestBtn._entryIndex, pos = bestPos }
                        else
                            if btPanel._insertBar then btPanel._insertBar:Hide() end
                            if btPanel._insertGlow then btPanel._insertGlow:Hide() end
                            btPanel._dropTarget = nil
                        end
                    end)
                end)
                btn:SetScript("OnDragStop", function(self)
                    self:SetAlpha(1.0)
                    if btPanel._dragLabel then btPanel._dragLabel:Hide() end
                    if btPanel._insertBar then btPanel._insertBar:Hide() end
                    if btPanel._insertGlow then btPanel._insertGlow:Hide() end
                    listChild:SetScript("OnUpdate", nil)
                    -- 드롭 하이라이트 전부 숨김
                    for bi = 1, #btPanel.listButtons do
                        local b = btPanel.listButtons[bi]
                        if b and b._dropHL then b._dropHL:Hide() end
                    end
                    local fromIdx = btPanel._dragIndex
                    local fromIsGroup = btPanel._dragIsGroup
                    btPanel._dragIndex = nil
                    btPanel._dragIsGroup = nil
                    btPanel._dragBtn = nil
                    if not fromIdx then return end
                    local tb = GetTrackedBuffsForGUI()
                    -- 1) 비그룹 → 그룹 위에 드롭 = 그룹 편입
                    if not fromIsGroup then
                        for bi = 1, #btPanel.listButtons do
                            local b = btPanel.listButtons[bi]
                            if b and b:IsShown() and b._entryIsGroup and b:IsMouseOver() then
                                local groupIdx = b._entryIndex
                                if groupIdx and groupIdx ~= fromIdx then
                                    local tracker = tb[fromIdx]
                                    local group = tb[groupIdx]
                                    if tracker and group and group.isGroup then
                                        -- 이전 그룹에서 제거
                                        if tracker.parentGroup then
                                            local oldGroup = tb[tracker.parentGroup]
                                            if oldGroup and oldGroup.controlledChildren then
                                                for ci = #oldGroup.controlledChildren, 1, -1 do
                                                    if oldGroup.controlledChildren[ci] == fromIdx then
                                                        table.remove(oldGroup.controlledChildren, ci)
                                                    end
                                                end
                                            end
                                        end
                                        tracker.parentGroup = groupIdx
                                        if not group.controlledChildren then group.controlledChildren = {} end
                                        table.insert(group.controlledChildren, fromIdx)
                                        group.expanded = true
                                        DDingUI:UpdateBuffTrackerBar()
                                        btPanel:RefreshList()
                                    end
                                end
                                return
                            end
                        end
                    end
                    -- 2) 순서 변경 (삽입 인디케이터 위치)
                    local target = btPanel._dropTarget
                    btPanel._dropTarget = nil
                    if target and target.index and target.index ~= fromIdx then
                        local toIdx = target.index
                        local sourceEntry = tb[fromIdx]
                        local targetEntry = tb[toIdx]
                        if not fromIsGroup
                            and sourceEntry
                            and targetEntry
                            and sourceEntry.parentGroup
                            and sourceEntry.parentGroup == targetEntry.parentGroup
                            and DDingUI.ReorderTrackedBuffInGroup
                            and DDingUI.ReorderTrackedBuffInGroup(
                                fromIdx,
                                toIdx,
                                target.pos == "after"
                            )
                        then
                            DDingUI:UpdateBuffTrackerBar()
                            btPanel:RefreshList()
                            return
                        end
                        -- 배열에서 순서 변경
                        if fromIdx ~= toIdx and tb[fromIdx] then
                            -- 이동 전: 각 엔트리에 원래 인덱스 태그
                            for ri = 1, #tb do
                                tb[ri]._origIdx = ri
                            end
                            local item = table.remove(tb, fromIdx)
                            -- fromIdx 제거 후 toIdx 조정
                            if fromIdx < toIdx then
                                toIdx = toIdx - 1
                            end
                            if target.pos == "after" then
                                toIdx = toIdx + 1
                            end
                            toIdx = math.max(1, math.min(toIdx, #tb + 1))
                            table.insert(tb, toIdx, item)
                            -- 인덱스 매핑 테이블 생성: oldIdx → newIdx
                            local idxMap = {}
                            for ni = 1, #tb do
                                if tb[ni]._origIdx then
                                    idxMap[tb[ni]._origIdx] = ni
                                end
                            end
                            -- parentGroup 재매핑
                            for ri = 1, #tb do
                                if tb[ri].parentGroup then
                                    tb[ri].parentGroup = idxMap[tb[ri].parentGroup] or tb[ri].parentGroup
                                end
                            end
                            -- controlledChildren 재매핑
                            for ri = 1, #tb do
                                if tb[ri].isGroup and tb[ri].controlledChildren then
                                    local newCC = {}
                                    for _, oldCI in ipairs(tb[ri].controlledChildren) do
                                        local newCI = idxMap[oldCI]
                                        if newCI then
                                            table.insert(newCC, newCI)
                                        end
                                    end
                                    tb[ri].controlledChildren = newCC
                                end
                            end
                            -- attachTo 재매핑 (DDingUIBuffTrackerBar/Icon/Text + 인덱스)
                            local ATTACH_PATTERNS = {
                                "DDingUIBuffTrackerBar",
                                "DDingUIBuffTrackerIcon",
                                "DDingUIBuffTrackerText",
                            }
                            for ri = 1, #tb do
                                local d = tb[ri].display
                                local s = tb[ri].settings
                                for _, pat in ipairs(ATTACH_PATTERNS) do
                                    -- display.attachTo
                                    if d and type(d.attachTo) == "string" then
                                        local oldNum = tonumber(d.attachTo:match("^" .. pat .. "(%d+)$"))
                                        if oldNum and idxMap[oldNum] then
                                            d.attachTo = pat .. idxMap[oldNum]
                                        end
                                    end
                                    -- settings.attachTo
                                    if s and type(s.attachTo) == "string" then
                                        local oldNum = tonumber(s.attachTo:match("^" .. pat .. "(%d+)$"))
                                        if oldNum and idxMap[oldNum] then
                                            s.attachTo = pat .. idxMap[oldNum]
                                        end
                                    end
                                end
                            end
                            -- 임시 태그 제거
                            for ri = 1, #tb do
                                tb[ri]._origIdx = nil
                            end
                            DDingUI:UpdateBuffTrackerBar()
                            btPanel:RefreshList()
                        end
                    end
                end)
            end
            -- 버튼에 메타데이터 저장 (드래그 드롭 시 식별용)
            btn._entryIndex = i
            btn._entryIsGroup = entry.isGroup

            yOff = yOff + ITEM_H + 1
            end -- passFilter
            end -- buff
        end -- for displayOrder

        listChild:SetHeight(math.max(yOff, listScroll:GetHeight()))
    end

    -- ─── 우클릭 컨텍스트 메뉴 (트래커/그룹 공용) ───
    local _ctxFrame = nil  -- 재사용 가능한 컨텍스트 메뉴 프레임

    local function CreateContextMenu()
        if _ctxFrame then return _ctxFrame end
        local f = CreateFrame("Frame", "DDingUI_BT_ContextMenu", UIParent, "BackdropTemplate")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(300)
        f:SetClampedToScreen(true)
        f:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            tile = false, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        f:SetBackdropColor(THEME.bgMain[1], THEME.bgMain[2], THEME.bgMain[3], 0.98)
        f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.8)
        f:Hide()
        f._items = {}

        -- ESC로 닫기
        tinsert(UISpecialFrames, "DDingUI_BT_ContextMenu")

        -- 다른 곳 클릭 시 닫기
        f:SetScript("OnShow", function()
            f:SetScript("OnUpdate", function()
                if not f:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                    f:Hide()
                end
            end)
        end)
        f:SetScript("OnHide", function()
            f:SetScript("OnUpdate", nil)
        end)

        _ctxFrame = f
        return f
    end

    local function ShowContextMenuItems(anchorBtn, items)
        local f = CreateContextMenu()

        -- 기존 아이템 숨기기
        for _, item in ipairs(f._items) do item:Hide() end

        local ITEM_W = 160
        local ITEM_H_CTX = 22
        local PAD = 4

        for i, entry in ipairs(items) do
            local btn = f._items[i]
            if not btn then
                btn = CreateFrame("Button", nil, f)
                btn._text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn._text:SetPoint("LEFT", 8, 0)
                btn._text:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
                btn._text:SetJustifyH("LEFT")
                btn._check = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn._check:SetPoint("RIGHT", -6, 0)
                btn._check:SetJustifyH("RIGHT")
                btn:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.3)
                end)
                btn:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0, 0, 0, 0)
                end)
                f._items[i] = btn
            end

            btn:SetSize(ITEM_W, ITEM_H_CTX)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD - (i - 1) * ITEM_H_CTX)
            btn._text:SetText(entry.text)
            btn._text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])

            if entry.checked then
                btn._check:SetText("|cff44ee44✓|r")
                btn._check:Show()
            else
                btn._check:SetText("")
                btn._check:Hide()
            end

            if entry.isSeparator then
                btn._text:SetText("|cff444444─────────────────|r")
                btn:SetScript("OnClick", nil)
                btn:EnableMouse(false)
            else
                btn:EnableMouse(true)
                local func = entry.func
                btn:SetScript("OnClick", function()
                    f:Hide()
                    if func then func() end
                end)
            end

            btn:Show()
        end

        local totalH = PAD * 2 + #items * ITEM_H_CTX
        f:SetSize(ITEM_W + PAD * 2, totalH)

        -- 앵커 버튼 우측에 표시
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 2, 0)
        f:Show()
        f:Raise()
    end

    -- ─── 트래커 우클릭 컨텍스트 메뉴 ───
    function btPanel:ShowTrackerContextMenu(idx, anchorBtn)
        local trackedBuffs = GetTrackedBuffsForGUI()
        local buff = trackedBuffs[idx]
        if not buff then return end

        local currentType = buff.displayType or "bar"
        local items = {}

        -- 표시 형식 변경 서브메뉴
        local DISPLAY_TYPES = {
            { id = "bar",   name = "BAR",   desc = L["Bar"] or "바" },
            { id = "icon",  name = "ICON",  desc = L["Icon"] or "아이콘" },
            { id = "ring",  name = "RING",  desc = L["Ring"] or "링" },
            { id = "text",  name = "TEXT",  desc = L["Text"] or "텍스트" },
            { id = "sound", name = "SOUND", desc = L["Sound"] or "사운드" },
        }

        items[#items + 1] = {
            text = "|cff88ccff" .. (L["Display Type"] or "표시 형식") .. "|r",
            isSeparator = false,
            func = nil,
        }

        for _, dt in ipairs(DISPLAY_TYPES) do
            local dtId = dt.id
            items[#items + 1] = {
                text = "    " .. dt.name .. "  |cff888888" .. dt.desc .. "|r",
                checked = currentType == dtId,
                func = function()
                    trackedBuffs[idx].displayType = dtId
                    DDingUI:UpdateBuffTrackerBar()
                    btPanel:RefreshList()
                    -- 우측 패널도 갱신
                    if btPanel.selectedIndex == idx then
                        btPanel:RenderTrackerTabs(idx)
                    end
                end,
            }
        end

        items[#items + 1] = { isSeparator = true, text = "" }

        -- 복제
        items[#items + 1] = {
            text = L["Duplicate"] or "복제",
            func = function()
                local copy = {}
                for k, v in pairs(buff) do
                    if type(v) == "table" then
                        copy[k] = {}
                        for kk, vv in pairs(v) do copy[k][kk] = vv end
                    else
                        copy[k] = v
                    end
                end
                copy.name = (copy.name or "Copy") .. " (Copy)"
                table.insert(trackedBuffs, idx + 1, copy)
                DDingUI:UpdateBuffTrackerBar()
                btPanel:RefreshList()
            end,
        }

        -- 활성/비활성 토글
        local toggleText = buff.disabled
            and ("|cff44ee44" .. (L["Enable"] or "활성화") .. "|r")
            or ("|cffaaaaaa" .. (L["Disable"] or "비활성화") .. "|r")
        items[#items + 1] = {
            text = toggleText,
            func = function()
                trackedBuffs[idx].disabled = not trackedBuffs[idx].disabled
                DDingUI:UpdateBuffTrackerBar()
                btPanel:RefreshList()
            end,
        }

        items[#items + 1] = { isSeparator = true, text = "" }

        -- 삭제
        items[#items + 1] = {
            text = "|cffff4444" .. (L["Delete"] or "삭제") .. "|r",
            func = function()
                DDingUI.ConfirmRemoveTrackedBuff(idx)
            end,
        }

        ShowContextMenuItems(anchorBtn, items)
    end

    -- ─── 그룹 우클릭 컨텍스트 메뉴 ───
    function btPanel:ShowGroupContextMenu(idx, anchorBtn)
        local trackedBuffs = GetTrackedBuffsForGUI()
        local group = trackedBuffs[idx]
        if not group then return end

        local items = {}

        -- 활성/비활성 토글
        local toggleText = group.disabled
            and ("|cff44ee44" .. (L["Enable"] or "활성화") .. "|r")
            or ("|cffaaaaaa" .. (L["Disable"] or "비활성화") .. "|r")
        items[#items + 1] = {
            text = toggleText,
            func = function()
                trackedBuffs[idx].disabled = not trackedBuffs[idx].disabled
                DDingUI:UpdateBuffTrackerBar()
                btPanel:RefreshList()
            end,
        }

        -- 이름 변경 (그룹 설정 패널 열기)
        items[#items + 1] = {
            text = L["Rename"] or "이름 변경",
            func = function()
                btPanel.selectedIndex = idx
                btPanel:RefreshList()
                btPanel:RenderGroupSettings(idx)
            end,
        }

        items[#items + 1] = { isSeparator = true, text = "" }

        -- 삭제 (그룹 해체)
        items[#items + 1] = {
            text = "|cffff4444" .. (L["Delete Group"] or "그룹 삭제") .. "|r",
            func = function()
                -- 자식들을 최상위로 해제
                if group.controlledChildren then
                    for _, childIdx in ipairs(group.controlledChildren) do
                        local child = trackedBuffs[childIdx]
                        if child then child.parentGroup = nil end
                    end
                end
                table.remove(trackedBuffs, idx)
                -- 인덱스 재매핑
                for ri = 1, #trackedBuffs do
                    if trackedBuffs[ri].parentGroup then
                        if trackedBuffs[ri].parentGroup == idx then
                            trackedBuffs[ri].parentGroup = nil
                        elseif trackedBuffs[ri].parentGroup > idx then
                            trackedBuffs[ri].parentGroup = trackedBuffs[ri].parentGroup - 1
                        end
                    end
                    if trackedBuffs[ri].controlledChildren then
                        local newCC = {}
                        for _, ci in ipairs(trackedBuffs[ri].controlledChildren) do
                            if ci ~= idx then
                                local newCI = ci > idx and ci - 1 or ci
                                newCC[#newCC + 1] = newCI
                            end
                        end
                        trackedBuffs[ri].controlledChildren = newCC
                    end
                end
                DDingUI:UpdateBuffTrackerBar()
                btPanel:RefreshList()
                ClearTabContent()
            end,
        }

        ShowContextMenuItems(anchorBtn, items)
    end

    -- ─── 트래커 선택 → 우측 탭 렌더링 ───
    function btPanel:SelectTracker(index)
        self.selectedIndex = index
        self:RefreshList()
        self:RefreshLivePreview()
        self:RenderTrackerTabs(index)
    end

    function btPanel:SelectStatic(key)
        self.selectedIndex = key
        self:RefreshList()
        self:RefreshLivePreview()
        self:RenderStaticPage(key)
    end

    -- ─── 그룹 선택 → 그룹 설정 렌더링 ───
    function btPanel:RenderGroupSettings(groupIdx)
        ClearTabContent()
        self:RefreshLivePreview()

        -- 탭 바 숨기기 (그룹 설정은 단일 설정 화면)
        tabBar:Show()
        for _, tb in ipairs(self.tabButtons) do tb:Hide() end

        -- 탭 바에 그룹 설정 탭들 표시
        tabScrollFrame:ClearAllPoints()
        tabScrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 5, -3)
        tabScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -12, 2)

        -- 그룹 설정용 탭 정의 (위치 + 정렬 + 동작)
        local groupTabs = {
            { name = L["Position"] or "Position",  filter = {"positionHeader", "attachTo", "anchorPoint", "selfPoint", "offsetX", "offsetY", "frameStrata"} },
            { name = L["Layout"] or "Layout",      filter = {"groupName", "groupEnabled", "layoutHeader", "growthDirection", "growthSpacing", "sortMode", "loadHeader", "loadCombatOnly", "loadInstanceType", "childrenHeader", "noChildren"} },
            { name = L["Actions"] or "Actions",    filter = {"actionsHeader", "actionsEnabled", "set_add_spacer", "set_add"} },
        }

        -- 전체 그룹 옵션 가져오기
        local allGroupOpts = DDingUI.CreateGroupOptions and DDingUI.CreateGroupOptions(groupIdx) or {}

        -- children 옵션도 Layout 탭에 포함
        -- set_* 동적 키는 Actions 탭에 포함
        for key, opt in pairs(allGroupOpts) do
            if key:match("^child%d+_") then
                table.insert(groupTabs[2].filter, key)
            elseif key:match("^set_") then
                table.insert(groupTabs[3].filter, key)
            end
        end

        -- 탭 버튼 렌더링
        local tabXOff = 5
        for ti, tabDef in ipairs(groupTabs) do
            local tb = self.tabButtons[ti]
            if not tb then
                tb = CreateFrame("Button", nil, tabBar)
                tb:SetHeight(TAB_H - 2)
                tb._bg = tb:CreateTexture(nil, "BACKGROUND")
                tb._bg:SetAllPoints()
                tb._underline = tb:CreateTexture(nil, "OVERLAY")
                tb._underline:SetHeight(2)
                tb._underline:SetPoint("BOTTOMLEFT", 0, 0)
                tb._underline:SetPoint("BOTTOMRIGHT", 0, 0)
                tb._underline:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                -- [DDINGUI] PP
                if tb._underline.SetSnapToPixelGrid then
                    tb._underline:SetSnapToPixelGrid(false)
                    tb._underline:SetTexelSnappingBias(0)
                end
                tb._label = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                tb._label:SetPoint("CENTER", 0, 1)
                self.tabButtons[ti] = tb
            end
            tb:Show()
            tb._label:SetText(tabDef.name)

            local clampedTab = self.selectedTab
            if not clampedTab or clampedTab > #groupTabs then clampedTab = 1 end
            local isActive = (clampedTab == ti)
            if isActive then
                tb._label:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
                tb._underline:Show()
                tb._bg:SetColorTexture(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 0.5)
            else
                tb._label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                tb._underline:Hide()
                tb._bg:SetColorTexture(0, 0, 0, 0)
            end

            local textW = tb._label:GetStringWidth()
            tb:SetWidth(math.max(textW + 20, 70))
            tb:ClearAllPoints()
            tb:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", tabXOff, 1)
            tabXOff = tabXOff + tb:GetWidth() + 2

            -- 클릭 핸들러
            local tabIdx = ti
            tb:SetScript("OnClick", function()
                self.selectedTab = tabIdx
                self:RenderGroupSettings(groupIdx)
            end)
            tb:SetScript("OnEnter", function(self)
                if not isActive then
                    self._bg:SetColorTexture(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], 0.4)
                end
            end)
            tb:SetScript("OnLeave", function(self)
                if not isActive then
                    self._bg:SetColorTexture(0, 0, 0, 0)
                end
            end)
        end

        -- 나머지 탭 버튼 숨기기
        for ti = #groupTabs + 1, #self.tabButtons do
            self.tabButtons[ti]:Hide()
        end

        -- 활성 탭의 필터에 맞는 옵션만 렌더링
        local activeTab = self.selectedTab or 1
        if activeTab > #groupTabs then activeTab = 1 end  -- 트래커 탭 값 오염 방지
        local filterKeys = {}
        for _, key in ipairs(groupTabs[activeTab].filter) do
            filterKeys[key] = true
        end

        local filteredOpts = {}
        for key, opt in pairs(allGroupOpts) do
            if filterKeys[key] then
                filteredOpts[key] = opt
            end
        end

        -- tabChild.scrollFrame 참조 설정 (RenderOptions 내부 스크롤바 갱신 지원)
        tabChild.scrollFrame = tabScrollFrame

        local pageOpts = { type = "group", name = groupTabs[activeTab].name, args = filteredOpts }
        RenderOptions(tabChild, pageOpts, {}, parentFrame)

        -- 높이 갱신 (딜레이 포함, inline group 확장 후 높이 재계산)
        local function UpdateTabHeight()
            -- tabChild 높이를 위젯 기반으로 재측정
            local maxBottom = 0
            if tabChild.widgets then
                for _, w in ipairs(tabChild.widgets) do
                    if w and w:IsShown() and w.GetBottom and w.GetTop then
                        local wb = w:GetBottom()
                        local wt = w:GetTop()
                        local tct = tabChild:GetTop()
                        if wb and tct then
                            local widgetBottom = tct - wb
                            if widgetBottom > maxBottom then
                                maxBottom = widgetBottom
                            end
                        end
                    end
                end
            end
            if maxBottom > 0 then
                tabChild:SetHeight(maxBottom + 50)
            end
            if tabScrollBar and tabScrollBar.UpdateThumbPosition then
                tabScrollBar.UpdateThumbPosition()
            end
        end
        C_Timer.After(0.05, UpdateTabHeight)
        C_Timer.After(0.15, UpdateTabHeight)
    end

    -- ─── 그룹 우클릭 컨텍스트 메뉴 ───
    function btPanel:ShowGroupContextMenu(groupIdx, anchorBtn)
        local trackedBuffs = GetTrackedBuffsForGUI()  -- [FIX] global per-spec 소스
        if not trackedBuffs[groupIdx] then return end

        local group = trackedBuffs[groupIdx]

        local menuFrame = CreateFrame("Frame", "DDingUI_BT_GroupCtxMenu", UIParent)
        local childCount = group.controlledChildren and #group.controlledChildren or 0
        local menuList = {
            { text = group.name or "Group", isTitle = true, notCheckable = true },
            { text = group.disabled and (L["Enable"] or "Enable") or (L["Disable"] or "Disable"), notCheckable = true, func = function()
                trackedBuffs[groupIdx].disabled = not trackedBuffs[groupIdx].disabled
                DDingUI:UpdateBuffTrackerBar()
                self:RefreshList()
            end },
            { text = L["Rename"] or "Rename", notCheckable = true, func = function()
                StaticPopupDialogs["DDINGUI_RENAME_GROUP"] = {
                    text = L["Enter new group name:"] or "Enter new group name:",
                    button1 = L["OK"] or "OK",
                    button2 = L["Cancel"] or "Cancel",
                    hasEditBox = true,
                    OnAccept = function(dlg)
                        local eb = DDingUI_GetPopupEditBox(dlg)
                        local newName = eb and eb:GetText()
                        if newName and newName ~= "" then
                            trackedBuffs[groupIdx].name = newName
                            DDingUI:UpdateBuffTrackerBar()
                            btPanel:RefreshList()
                        end
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                }
                local popup = StaticPopup_Show("DDINGUI_RENAME_GROUP")
                if popup then
                    local eb = DDingUI_GetPopupEditBox(popup)
                    if eb then eb:SetText(group.name or ""); eb:HighlightText() end
                end
            end },
            { text = "|cffff4444" .. (L["Delete Group"] or "Delete Group") .. " (" .. childCount .. ")|r", notCheckable = true, func = function()
                -- 확인 팝업
                local groupName = group.name or "Group"
                StaticPopupDialogs["DDINGUI_DELETE_GROUP_CONFIRM"] = {
                    text = string.format(
                        (L["Delete group '%s' and all %d children?\nThis cannot be undone."] or "Delete group '%s' and all %d children?\nThis cannot be undone."),
                        groupName, childCount
                    ),
                    button1 = L["Delete"] or "Delete",
                    button2 = L["Cancel"] or "Cancel",
                    OnAccept = function()
                        local tb = GetTrackedBuffsForGUI()
                        -- 삭제할 인덱스 수집 (그룹 자신 + 모든 자식)
                        local toRemove = { groupIdx }
                        local children = tb[groupIdx] and tb[groupIdx].controlledChildren or {}
                        for _, childIdx in ipairs(children) do
                            table.insert(toRemove, childIdx)
                        end
                        -- 인덱스 내림차순 정렬 후 삭제 (앞에서 지우면 인덱스 밀림 방지)
                        table.sort(toRemove, function(a, b) return a > b end)
                        for _, removeIdx in ipairs(toRemove) do
                            table.remove(tb, removeIdx)
                        end
                        -- 남은 항목들의 parentGroup / controlledChildren 인덱스 재계산
                        for idx, entry in ipairs(tb) do
                            -- parentGroup 정리
                            if entry.parentGroup then
                                local newPG = entry.parentGroup
                                for _, removeIdx in ipairs(toRemove) do
                                    if entry.parentGroup == removeIdx then
                                        entry.parentGroup = nil
                                        newPG = nil
                                        break
                                    elseif entry.parentGroup > removeIdx then
                                        newPG = newPG - 1
                                    end
                                end
                                entry.parentGroup = newPG
                            end
                            -- controlledChildren 정리
                            if entry.controlledChildren then
                                local newCC = {}
                                for _, ci in ipairs(entry.controlledChildren) do
                                    local removed = false
                                    local newCI = ci
                                    for _, removeIdx in ipairs(toRemove) do
                                        if ci == removeIdx then removed = true; break end
                                        if ci > removeIdx then newCI = newCI - 1 end
                                    end
                                    if not removed then
                                        table.insert(newCC, newCI)
                                    end
                                end
                                entry.controlledChildren = newCC
                            end
                        end
                        DDingUI:UpdateBuffTrackerBar()
                        if btPanel.selectedIndex == groupIdx then
                            btPanel.selectedIndex = nil
                            ClearTabContent()
                            tabBar:Hide()
                        end
                        btPanel:RefreshList()
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    showAlert = true,
                    preferredIndex = 3,
                }
                StaticPopup_Show("DDINGUI_DELETE_GROUP_CONFIRM")
            end },
            { text = L["Move Up"] or "Move Up", notCheckable = true, disabled = groupIdx <= 1, func = function()
                if DDingUI.MoveTrackedBuff then
                    DDingUI.MoveTrackedBuff(groupIdx, -1)
                    DDingUI:UpdateBuffTrackerBar()
                    self:RefreshList()
                end
            end },
            { text = L["Move Down"] or "Move Down", notCheckable = true, disabled = groupIdx >= #trackedBuffs, func = function()
                if DDingUI.MoveTrackedBuff then
                    DDingUI.MoveTrackedBuff(groupIdx, 1)
                    DDingUI:UpdateBuffTrackerBar()
                    self:RefreshList()
                end
            end },
        }
        EasyMenu(menuList, menuFrame, anchorBtn, 0, 0, "MENU")
    end

    -- ─── 중앙 작업 탭 렌더링 ───
    -- flat options를 order 범위 + key prefix로 탭으로 자동 분류
    function btPanel:RenderTrackerTabs(index)
        ClearTabContent()
        self:RefreshLivePreview()

        -- 기존 탭 버튼 숨기기
        for _, tb in ipairs(self.tabButtons) do tb:Hide() end

        -- 탭 바 표시 + 컨텐츠 위치 조정
        tabBar:Show()
        tabScrollFrame:ClearAllPoints()
        tabScrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 5, -3)
        tabScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -12, 2)

        -- skipCollapsible=true로 옵션 가져오기 (항상 expanded, header/remove/spacer 없음)
        local allOpts = ns.CreateTrackedBuffOptions(index, 0, true)

        -- displayType 확인
        local trackedBuffs = GetTrackedBuffsForGUI()  -- [FIX] global per-spec 소스
        local buff = trackedBuffs[index]
        local dType = buff and buff.displayType or "bar"

        -- ─── 탭 정의 (order 범위 + key prefix) ───
        -- 각 탭은 { name, filter } 형태
        -- filter(key, order) → true면 해당 탭에 포함
        local tabDefs = {}
        if false then
        local function KeyHasAny(key, ...)
            for i = 1, select("#", ...) do
                local fragment = select(i, ...)
                if key:find(fragment, 1, true) then
                    return true
                end
            end
            return false
        end

        -- 1. 기본 설정 (모든 displayType에 공통)
        tabDefs[#tabDefs + 1] = {
            name = L["General"] or "General",
            filter = function(key, order)
                -- order 0~1.09 범위 (enabled, displayType, frameStrata, trackingMode, manual 관련)
                -- Spell bar/color/text 키는 Bar/Text 탭으로 이동되었으므로 제외
                if key:find("_spellFillDirection", 1, true) or key:find("_spellRechargeColor", 1, true)
                   or key:find("_spellFullChargeColor", 1, true) or key:find("_spellReadyStyle", 1, true)
                   or key:find("_spellReadyColor", 1, true) or key:find("_spellColorCurve", 1, true)
                   or key:find("_spellShowReadyText", 1, true) or key:find("_spellHeader", 1, true)
                   or key:find("_barFillMode", 1, true) then
                    return false
                end
                return order >= 0 and order < 1.1
            end,
        }

        -- 2. displayType별 전용 탭
        if dType == "icon" then
            tabDefs[#tabDefs + 1] = {
                name = L["Icon"] or "Icon",
                childGroups = "tab",
                sections = {
                    {
                        key = "visibility",
                        name = L["Visibility"],
                        filter = function(key)
                            return key:find("_showInactiveIcon", 1, true)
                                or key:find("_iconShowInCombat", 1, true)
                                or key:find("_iconOnlyInCombat", 1, true)
                                or key:find("_showOnlyWhenInactive", 1, true)
                                or key:find("_iconDesaturate", 1, true)
                        end,
                    },
                    {
                        key = "appearance",
                        name = L["Appearance"] or "Appearance",
                        filter = function(key)
                            return key:find("_iconSource", 1, true)
                                or key:find("_customIconID", 1, true)
                                or key:find("_iconSize", 1, true)
                                or key:find("_showIconBorder", 1, true)
                                or key:find("_iconBorderSize", 1, true)
                                or key:find("_iconBorderColor", 1, true)
                                or key:find("_iconZoom", 1, true)
                                or key:find("_iconAspectRatio", 1, true)
                        end,
                    },
                    {
                        key = "position",
                        name = L["Position"] or "Position",
                        filter = function(key)
                            return key:find("_iconAttachTo", 1, true)
                                or key:find("_iconAnchorPoint", 1, true)
                                or key:find("_iconSelfPoint", 1, true)
                                or key:find("_iconOffsetX", 1, true)
                                or key:find("_iconOffsetY", 1, true)
                        end,
                    },
                    {
                        key = "stackText",
                        name = L["Stack Text"],
                        filter = function(key)
                            return key:find("_iconStack", 1, true) ~= nil
                        end,
                    },
                    {
                        key = "durationText",
                        name = L["Duration Text"] or "Duration Text",
                        filter = function(key)
                            return key:find("_showDurationText", 1, true)
                                or key:find("_durationTextFont", 1, true)
                                or key:find("_durationTextSize", 1, true)
                                or key:find("_durationTextAlign", 1, true)
                                or key:find("_durationTextX", 1, true)
                                or key:find("_durationTextY", 1, true)
                                or key:find("_durationTextColor", 1, true)
                                or key:find("_durationDecimals", 1, true)
                                or key:find("_durationWarning", 1, true)
                        end,
                    },
                    {
                        key = "effects",
                        name = L["Effects"],
                        filter = function(key)
                            return key:find("_iconAnimation", 1, true)
                                or key:find("_glowWhenInactive", 1, true)
                                or key:find("_glowColor", 1, true)
                                or key:find("_glowLines", 1, true)
                                or key:find("_glowFrequency", 1, true)
                                or key:find("_glowThickness", 1, true)
                                or key:find("_glowXOffset", 1, true)
                                or key:find("_glowYOffset", 1, true)
                        end,
                    },
                },
            }
        elseif dType == "sound" then
            tabDefs[#tabDefs + 1] = {
                name = L["Sound"] or "Sound",
                childGroups = "tab",
                sections = {
                    {
                        key = "playback",
                        name = L["Playback"],
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_soundFile",
                                "_soundCustomPath",
                                "_testSound",
                                "_soundChannel"
                            )
                        end,
                    },
                    {
                        key = "trigger",
                        name = L["Trigger"] or "Trigger",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_soundTrigger",
                                "_soundStartDelay",
                                "_soundEndBefore",
                                "_soundInterval"
                            )
                        end,
                    },
                },
            }
        elseif dType == "text" then
            tabDefs[#tabDefs + 1] = {
                name = L["Text"] or "Text",
                childGroups = "tab",
                sections = {
                    {
                        key = "visibility",
                        name = L["Visibility"],
                        filter = function(key)
                            return KeyHasAny(key, "_hideWhenZero", "_showInCombat", "_onlyInCombat")
                        end,
                    },
                    {
                        key = "content",
                        name = L["Content"],
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_textDisplayMode",
                                "_customText",
                                "_textShowIcon",
                                "_textIconSize"
                            )
                        end,
                    },
                    {
                        key = "appearance",
                        name = L["Appearance"] or "Appearance",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_textModeSize",
                                "_textModeFont",
                                "_textModeColor",
                                "_textModeOutline"
                            )
                        end,
                    },
                    {
                        key = "position",
                        name = L["Position"] or "Position",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_textAnchorTo",
                                "_textAnchorPoint",
                                "_textSelfPoint",
                                "_textModeOffsetX",
                                "_textModeOffsetY"
                            )
                        end,
                    },
                    {
                        key = "durationText",
                        name = L["Duration Text"] or "Duration Text",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_showDurationText",
                                "_durationTextFont",
                                "_durationTextSize",
                                "_durationTextAlign",
                                "_durationTextX",
                                "_durationTextY",
                                "_durationTextColor",
                                "_durationDecimals",
                                "_durationWarning"
                            )
                        end,
                    },
                    {
                        key = "effects",
                        name = L["Effects"],
                        filter = function(key)
                            return key:find("_textAnimation", 1, true)
                                or key:find("_textGlow", 1, true)
                        end,
                    },
                },
            }
        elseif dType == "ring" then
            tabDefs[#tabDefs + 1] = {
                name = L["Ring"] or "Ring",
                childGroups = "tab",
                sections = {
                    {
                        key = "visibility",
                        name = L["Visibility"],
                        filter = function(key)
                            return KeyHasAny(key, "_hideWhenZero", "_showInCombat", "_onlyInCombat")
                        end,
                    },
                    {
                        key = "appearance",
                        name = L["Appearance"] or "Appearance",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_ringSize",
                                "_ringThickness",
                                "_ringReverse",
                                "_ringColor",
                                "_ringBgColor",
                                "_ringBorderSize",
                                "_ringBorderColor"
                            )
                        end,
                    },
                    {
                        key = "position",
                        name = L["Position"] or "Position",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_ringAttachTo",
                                "_ringPickFrame",
                                "_ringAnchorPoint",
                                "_ringSelfPoint",
                                "_ringOffsetX",
                                "_ringOffsetY"
                            )
                        end,
                    },
                    {
                        key = "centerText",
                        name = L["Center Text"],
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_ringShowText",
                                "_ringTextSize",
                                "_ringTextFont",
                                "_ringTextColor",
                                "_ringDurationDecimals"
                            )
                        end,
                    },
                    {
                        key = "durationText",
                        name = L["Duration Text"] or "Duration Text",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_showDurationText",
                                "_durationTextFont",
                                "_durationTextSize",
                                "_durationTextAlign",
                                "_durationTextX",
                                "_durationTextY",
                                "_durationTextColor",
                                "_durationDecimals",
                                "_durationWarning"
                            )
                        end,
                    },
                },
            }
        elseif dType == "bar" then
            tabDefs[#tabDefs + 1] = {
                name = L["Bar"] or "Bar",
                childGroups = "tab",
                sections = {
                    {
                        key = "visibility",
                        name = L["Visibility"],
                        filter = function(key)
                            return KeyHasAny(key, "_hideWhenZero", "_showInCombat", "_onlyInCombat")
                        end,
                    },
                    {
                        key = "appearance",
                        name = L["Appearance"] or "Appearance",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_barFillMode",
                                "_barColor",
                                "_barBgColor",
                                "_smoothProgress",
                                "_barOrientation",
                                "_barReverseFill",
                                "_borderSize",
                                "_borderColor",
                                "_texture",
                                "_spellFillDirection",
                                "_spellRechargeColor",
                                "_spellFullChargeColor",
                                "_spellReadyStyle",
                                "_spellReadyColor",
                                "_spellColorCurve"
                            )
                        end,
                    },
                    {
                        key = "position",
                        name = L["Position"] or "Position",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_attachTo",
                                "_pickFrame",
                                "_anchorPoint",
                                "_selfPoint",
                                "_offsetX",
                                "_offsetY",
                                "_width",
                                "_height"
                            )
                        end,
                    },
                    {
                        key = "stackText",
                        name = L["Stack Text"],
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_showStacksText",
                                "_textFont",
                                "_textSize",
                                "_textAlign",
                                "_textX",
                                "_textY",
                                "_textColor",
                                "_spellShowReadyText"
                            )
                        end,
                    },
                    {
                        key = "durationText",
                        name = L["Duration Text"] or "Duration Text",
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_showDurationText",
                                "_durationTextFont",
                                "_durationTextSize",
                                "_durationTextAlign",
                                "_durationTextX",
                                "_durationTextY",
                                "_durationTextColor",
                                "_durationDecimals",
                                "_durationWarning"
                            )
                        end,
                    },
                    {
                        key = "ticks",
                        name = L["Ticks"],
                        filter = function(key)
                            return KeyHasAny(
                                key,
                                "_durationTickPositions",
                                "_showTicks",
                                "_tickWidth"
                            )
                        end,
                    },
                },
            }
        end

        -- 마지막: 알림 탭 (모든 displayType 공통, order 8+)
        tabDefs[#tabDefs + 1] = {
            name = L["Actions"] or "Actions",
            filter = function(key, order)
                return key:find("_alert") ~= nil or order >= 8
            end,
        }
        end
        tabDefs = CreateModernTrackerTabDefinitions()

        -- ─── 각 탭의 옵션 분류 ───
        local tabGroups = {}
        local function CollectOptions(filter)
            local args = {}
            local hasVisible = false
            for key, opt in pairs(allOpts) do
                local oOrder = opt.order or 999
                if filter(key, oOrder) then
                    args[key] = opt
                    local isHidden = false
                    if type(opt.hidden) == "function" then
                        local ok, result = pcall(opt.hidden)
                        isHidden = ok and result
                    elseif opt.hidden then
                        isHidden = true
                    end
                    if not isHidden then hasVisible = true end
                end
            end
            return args, hasVisible
        end

        for i, def in ipairs(tabDefs) do
            if def.sections then
                local sectionGroups = {}
                local hasVisible = false
                for sectionOrder, section in ipairs(def.sections) do
                    local sectionArgs, sectionVisible = CollectOptions(section.filter)
                    if sectionVisible and next(sectionArgs) then
                        sectionGroups[section.key] = {
                            type = "group",
                            name = section.name,
                            order = sectionOrder,
                            args = sectionArgs,
                        }
                        if sectionVisible then hasVisible = true end
                    end
                end
                tabGroups[i] = {
                    key = def.key,
                    name = def.name,
                    args = sectionGroups,
                    hasVisible = hasVisible,
                    childGroups = def.childGroups,
                }
            else
                local args, hasVisible = CollectOptions(def.filter)
                tabGroups[i] = { key = def.key, name = def.name, args = args, hasVisible = hasVisible }
            end
        end

        -- ─── 탭 버튼 생성 ───
        local tabX = 5
        local visibleTabIdx = 0
        local firstVisibleTab = nil

        for i, tg in ipairs(tabGroups) do
            -- 빈 탭은 건너뛰기
            if tg.hasVisible then
                visibleTabIdx = visibleTabIdx + 1
                local btnIdx = visibleTabIdx
                local tb = self.tabButtons[btnIdx]
                if not tb then
                    tb = CreateFrame("Button", nil, tabBar)
                    tb:SetHeight(TAB_H - 2)
                    tb._bg = tb:CreateTexture(nil, "BACKGROUND")
                    tb._bg:SetAllPoints()
                    tb._bg:SetColorTexture(0, 0, 0, 0)
                    tb._underline = tb:CreateTexture(nil, "OVERLAY")
                    tb._underline:SetHeight(2)
                    tb._underline:SetPoint("BOTTOMLEFT", 0, 0)
                    tb._underline:SetPoint("BOTTOMRIGHT", 0, 0)
                    tb._underline:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                    tb._underline:Hide()
                    tb._label = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    tb._label:SetPoint("CENTER", 0, 1)
                    self.tabButtons[btnIdx] = tb
                end

                tb:Show()
                tb._label:SetText(tg.name)
                tb._label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                tb._underline:Hide()
                tb._bg:SetColorTexture(0, 0, 0, 0)

                local textW = tb._label:GetStringWidth()
                tb:SetWidth(math.max(textW + 20, 50))
                tb:ClearAllPoints()
                tb:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", tabX, 1)
                tabX = tabX + tb:GetWidth() + 2

                -- hover
                tb:SetScript("OnEnter", function(self)
                    if not self._active then
                        self._bg:SetColorTexture(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], 0.3)
                    end
                end)
                tb:SetScript("OnLeave", function(self)
                    if not self._active then
                        self._bg:SetColorTexture(0, 0, 0, 0)
                    end
                end)

                -- 탭 클릭
                local tabGroup = tg
                tb:SetScript("OnClick", function()
                    btPanel:ShowTab(tabGroup, btnIdx)
                end)

                if not firstVisibleTab then
                    firstVisibleTab = { group = tg, idx = btnIdx }
                end
            end
        end

        -- 첫 번째 탭 자동 선택 (또는 이전 선택 복원)
        if self.selectedTab and self.tabButtons[self.selectedTab] and self.tabButtons[self.selectedTab]:IsShown() then
            -- 이전 탭 복원 시도
            for i, tg in ipairs(tabGroups) do
                if tg.hasVisible then
                    local tb = self.tabButtons[self.selectedTab]
                    if tb and tb._label and tb._label:GetText() == tg.name then
                        btPanel:ShowTab(tg, self.selectedTab)
                        return
                    end
                end
            end
        end
        if firstVisibleTab then
            btPanel:ShowTab(firstVisibleTab.group, firstVisibleTab.idx)
        end
    end

    -- ─── 탭 콘텐츠 표시 ───
    function btPanel:ShowTab(tabGroup, btnIdx)
        ClearTabContent()

        -- 모든 탭 비활성화
        for _, tb in ipairs(self.tabButtons) do
            if tb:IsShown() then
                tb._active = false
                tb._underline:Hide()
                tb._bg:SetColorTexture(0, 0, 0, 0)
                tb._label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            end
        end

        -- 선택된 탭 활성화
        local activeBtn = self.tabButtons[btnIdx]
        if activeBtn then
            activeBtn._active = true
            activeBtn._underline:Show()
            activeBtn._bg:SetColorTexture(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 0.5)
            activeBtn._label:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
        end
        self.selectedTab = btnIdx

        -- 탭 콘텐츠 렌더링
        tabChild.scrollFrame = tabScrollFrame
        tabChild._nestedTabContentArea = rightPanel
        tabChild._insideBuffTrackerPanel = true
        if tabGroup.childGroups == "tab" and tabChild._activeSubTabKey then
            parentFrame._requestedSubTabPath = { tabChild._activeSubTabKey }
        else
            parentFrame._requestedSubTabPath = nil
        end
        local trackedBuffs = GetTrackedBuffsForGUI()
        local selectedEntry = type(self.selectedIndex) == "number" and trackedBuffs[self.selectedIndex] or nil
        local handled = ModernTrackerEditor:Render(tabChild, tabScrollFrame, tabScrollBar, tabGroup, {
            entry = selectedEntry,
            index = self.selectedIndex,
            panel = self,
            parentFrame = parentFrame,
        })
        if not handled then
            local pageOpts = {
                type = "group",
                name = tabGroup.name,
                args = tabGroup.args,
                childGroups = tabGroup.childGroups,
            }
            RenderOptions(tabChild, pageOpts, {}, parentFrame)
        end

        -- 높이 갱신
        C_Timer.After(0.05, function()
            if tabScrollBar and tabScrollBar.UpdateThumbPosition then
                tabScrollBar.UpdateThumbPosition()
            end
        end)
    end

    -- ─── 정적 페이지 (개요, 마법사, 카탈로그, 글로벌) ───
    function btPanel:RenderStaticPage(key)
        ClearTabContent()
        self:RefreshLivePreview()
        if key == "catalog" then
            key = "wizard"
            self.selectedIndex = "wizard"
            if DDingUI.FocusCDMIconGridSearch then DDingUI.FocusCDMIconGridSearch() end
        end
        -- 탭 바 숨기기 (정적 페이지는 탭 없음)
        tabBar:Hide()
        for _, tb in ipairs(self.tabButtons) do tb:Hide() end

        -- 컨텐츠 영역 재배치 (탭바 숨김이므로 상단부터)
        tabScrollFrame:ClearAllPoints()
        tabScrollFrame:SetPoint("TOPLEFT", livePreview, "BOTTOMLEFT", -5, -8)
        tabScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -12, 2)

        local pageOpts = nil
        if key == "wizard" then
            -- 새 트래커 추가 페이지
            pageOpts = {
                type = "group",
                name = "New Tracker",
                args = {
                    desc = {
                        type = "description",
                        name = "|cffaaaaaa" .. (L["Select a buff from the CDM Catalog, or add one manually."] or "Select a buff from the CDM Catalog, or add one manually.") .. "|r",
                        order = 1,
                        fontSize = "medium",
                    },
                    spacer = {type = "description", name = " ", order = 1.5, width = "full"},
                    manualAdd = {
                        type = "execute",
                        name = "|cff00ff00+ " .. (L["Manual Add"] or "Manual Add") .. "|r",
                        desc = L["Add a manual tracked buff with trigger/spender spells"] or "Add a manual tracked buff with trigger/spender spells",
                        order = 2,
                        width = "full",
                        func = function()
                            DDingUI.AddManualTrackedBuff()
                            if btPanel.RefreshList then btPanel:RefreshList() end
                        end,
                    },
                    spellAdd = {
                        type = "execute",
                        name = "|cff00ccff+ " .. (L["Spell Cooldown"] or "Spell Cooldown") .. "|r",
                        desc = L["Add a spell cooldown tracker (uses C_Spell API)"] or "Add a spell cooldown tracker (uses C_Spell API)",
                        order = 2.2,
                        width = "full",
                        func = function()
                            DDingUI.AddSpellTrackedBuff()
                            if btPanel.RefreshList then btPanel:RefreshList() end
                        end,
                    },
                    newGroup = {
                        type = "execute",
                        name = "|cff8888ff+ " .. (L["New Group"] or "New Group") .. "|r",
                        desc = L["Create a new group to organize trackers"] or "Create a new group to organize trackers",
                        order = 2.5,
                        width = "full",
                        func = function()
                            DDingUI.CreateTrackerGroup()
                            if btPanel.RefreshList then btPanel:RefreshList() end
                        end,
                    },
                    gotoCatalog = {
                        type = "execute",
                        name = L["Open CDM Catalog"] or "Open CDM Catalog",
                        desc = L["Go to CDM Catalog to select auras"] or "Go to CDM Catalog to select auras",
                        order = 3,
                        width = "full",
                        func = function()
                            if DDingUI.FocusCDMIconGridSearch then
                                DDingUI.FocusCDMIconGridSearch()
                            end
                        end,
                    },
                },
            }
        end

        if pageOpts then
            RenderOptions(tabChild, pageOpts, {}, parentFrame)
        end

        -- 높이 갱신
        C_Timer.After(0.05, function()
            if tabScrollBar and tabScrollBar.UpdateThumbPosition then
                tabScrollBar.UpdateThumbPosition()
            end
        end)
    end

    -- 외부(옵션)에서 카탈로그 열기 지원
    DDingUI.OpenAuraCatalog = function()
        if btPanel and btPanel.catalogPanel then btPanel.catalogPanel:Show() end
        if DDingUI.FocusCDMIconGridSearch then DDingUI.FocusCDMIconGridSearch() end
    end

    -- ─── 우클릭 컨텍스트 메뉴 ───
    function btPanel:ShowTrackerContextMenu(index, anchorBtn)
        local trackedBuffs = GetTrackedBuffsForGUI()  -- [FIX] global per-spec 소스
        if not trackedBuffs[index] then return end

        local buff = trackedBuffs[index]
        local buffName = buff.name or "Tracker #" .. index

        -- 심플 드롭다운 메뉴
        local menuFrame = CreateFrame("Frame", "DDingUI_BT_CtxMenu2", UIParent)
        local menuList = {
            { text = buffName, isTitle = true, notCheckable = true },
            { text = buff.disabled and (L["Enable"] or "Enable") or (L["Disable"] or "Disable"), notCheckable = true, func = function()
                trackedBuffs[index].disabled = not trackedBuffs[index].disabled
                DDingUI:UpdateBuffTrackerBar()
                self:RefreshList()
            end },
            { text = L["Rename"] or "Rename", notCheckable = true, func = function()
                StaticPopupDialogs["DDINGUI_RENAME_TRACKER"] = {
                    text = L["Enter new name:"] or "Enter new name:",
                    button1 = L["OK"] or "OK",
                    button2 = L["Cancel"] or "Cancel",
                    hasEditBox = true,
                    OnAccept = function(dlg)
                        local eb = DDingUI_GetPopupEditBox(dlg)
                        local newName = eb and eb:GetText()
                        if newName and newName ~= "" then
                            trackedBuffs[index].name = newName
                            DDingUI:UpdateBuffTrackerBar()
                            btPanel:RefreshList()
                            -- 선택된 상태면 탭도 갱신
                            if btPanel.selectedIndex == index then
                                btPanel:RenderTrackerTabs(index)
                            end
                        end
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                }
                local popup = StaticPopup_Show("DDINGUI_RENAME_TRACKER")
                if popup then
                    local eb = DDingUI_GetPopupEditBox(popup)
                    if eb then eb:SetText(buffName); eb:HighlightText() end
                end
            end },
            { text = L["Duplicate"] or "Duplicate", notCheckable = true, func = function()
                if DDingUI.DuplicateTrackedBuff then
                    DDingUI.DuplicateTrackedBuff(index)
                    DDingUI:UpdateBuffTrackerBar()
                    self:RefreshList()
                end
            end },
            { text = L["Move Up"] or "Move Up", notCheckable = true, disabled = index <= 1, func = function()
                if DDingUI.MoveTrackedBuff then
                    DDingUI.MoveTrackedBuff(index, -1)
                    DDingUI:UpdateBuffTrackerBar()
                    self:RefreshList()
                end
            end },
            { text = L["Move Down"] or "Move Down", notCheckable = true, disabled = index >= #trackedBuffs, func = function()
                if DDingUI.MoveTrackedBuff then
                    DDingUI.MoveTrackedBuff(index, 1)
                    DDingUI:UpdateBuffTrackerBar()
                    self:RefreshList()
                end
            end },
        }

        -- ─── Move to Group 서브메뉴 ───
        local groupSubmenu = {}
        -- trackedBuffs는 이미 위에서 GetTrackedBuffsForGUI()로 가져옴
        for gi, entry in ipairs(trackedBuffs) do
            if entry.isGroup and gi ~= index then
                local gName = entry.name or ("Group #" .. gi)
                local isAlreadyInGroup = (buff.parentGroup == gi)
                table.insert(groupSubmenu, {
                    text = (isAlreadyInGroup and "|cff44ee44✓ " or "") .. gName,
                    notCheckable = true,
                    func = function()
                        if isAlreadyInGroup then
                            DDingUI.RemoveFromGroup(index)
                        else
                            DDingUI.AddToGroup(index, gi)
                        end
                        self:RefreshList()
                    end,
                })
            end
        end
        if #groupSubmenu > 0 then
            table.insert(menuList, {
                text = L["Move to Group"] or "Move to Group",
                notCheckable = true,
                hasArrow = true,
                menuList = groupSubmenu,
            })
        end

        -- Remove from Group (if in a group)
        if buff.parentGroup then
            local parentName = trackedBuffs[buff.parentGroup] and trackedBuffs[buff.parentGroup].name or "Group"
            table.insert(menuList, {
                text = "|cffff8800" .. (L["Remove from"] or "Remove from") .. " " .. parentName .. "|r",
                notCheckable = true,
                func = function()
                    DDingUI.RemoveFromGroup(index)
                    self:RefreshList()
                end,
            })
        end

        -- Delete (항상 마지막)
        table.insert(menuList, {
            text = "|cffff4444" .. (L["Delete"] or "Delete") .. "|r", notCheckable = true, func = function()
                if DDingUI.RemoveTrackedBuff then
                    DDingUI.RemoveTrackedBuff(index)
                    DDingUI:UpdateBuffTrackerBar()
                    if self.selectedIndex == index then
                        self.selectedIndex = nil
                        ClearTabContent()
                        tabBar:Hide()
                    end
                    self:RefreshList()
                end
            end,
        })

        EasyMenu(menuList, menuFrame, anchorBtn, 0, 0, "MENU")
    end

    -- ─── 초기 렌더링 ───
    btPanel:RefreshList()

    -- 첫 번째 트래커 자동 선택 (있으면), 없으면 wizard
    local trackedBuffs = GetTrackedBuffsForGUI()  -- [FIX] global per-spec 소스
    if #trackedBuffs > 0 then
        -- 첫 번째 비그룹 항목 찾기
        local firstNonGroup = nil
        for i, entry in ipairs(trackedBuffs) do
            if not entry.isGroup then firstNonGroup = i; break end
        end
        if firstNonGroup then
            btPanel:SelectTracker(firstNonGroup)
        elseif trackedBuffs[1] and trackedBuffs[1].isGroup then
            btPanel.selectedIndex = 1
            btPanel:RefreshList()
            btPanel:RenderGroupSettings(1)
        end
    else
        btPanel:SelectStatic("wizard")
    end
end
