local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local GUI = DDingUI.GUI
local SL = _G.DDingUI_StyleLib
local FLAT = SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local THEME = GUI.THEME
local globalFontPath = "Fonts\\2002.TTF"
local CreateBackdrop = GUI.CreateBackdrop

local function CreateStyledButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 100, height or 28)
    btn:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(SL.GetColor("widget"))
    btn:SetBackdropBorderColor(SL.GetColor("border"))

    local gf = DDingUI:GetGlobalFont() or globalFontPath
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetFont(gf, 11, "")
    btn.text:SetShadowOffset(1, -1)
    btn.text:SetShadowColor(0, 0, 0, 1)
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)
    btn.text:SetTextColor(SL.GetColor("text"))

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.2)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.7)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(SL.GetColor("widget"))
        self:SetBackdropBorderColor(SL.GetColor("border"))
    end)

    return btn
end

local function CreateStyledToggle(parent, text, width)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 90, 26)
    btn:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(SL.GetColor("widget"))
    btn:SetBackdropBorderColor(SL.GetColor("border"))

    local gf = DDingUI:GetGlobalFont() or globalFontPath
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetFont(gf, 11, "")
    btn.text:SetShadowOffset(1, -1)
    btn.text:SetShadowColor(0, 0, 0, 1)
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)
    btn.text:SetTextColor(SL.GetColor("dim"))

    btn.isChecked = false

    btn.SetChecked = function(self, checked)
        self.isChecked = checked
        if checked then
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.25)
            self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.8)
            self.text:SetTextColor(SL.GetColor("text"))
        else
            self:SetBackdropColor(SL.GetColor("widget"))
            self:SetBackdropBorderColor(SL.GetColor("border"))
            self.text:SetTextColor(SL.GetColor("dim"))
        end
    end

    btn:SetScript("OnEnter", function(self)
        if not self.isChecked then
            self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.5)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.isChecked then
            self:SetBackdropBorderColor(SL.GetColor("border"))
        end
    end)

    return btn
end

local function CreateStyledInput(parent, width, height, numeric)
    local gf = DDingUI:GetGlobalFont() or globalFontPath
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 140, height or 28)
    container:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    container:SetBackdropColor(SL.GetColor("widget"))
    container:SetBackdropBorderColor(SL.GetColor("border"))

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", 6, -4)
    editBox:SetPoint("BOTTOMRIGHT", -6, 4)
    editBox:SetAutoFocus(false)
    editBox:SetFont(gf, 11, "")
    editBox:SetShadowOffset(1, -1)
    editBox:SetShadowColor(0, 0, 0, 1)
    editBox:SetTextColor(SL.GetColor("text"))
    if numeric then
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(8)
    else
        editBox:SetMaxLetters(50) -- [REFACTOR] 텍스트 모드 (스펠 이름 검색용)
    end

    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    editBox:SetScript("OnEditFocusGained", function()
        container:SetBackdropBorderColor(THEME.borderLight[1], THEME.borderLight[2], THEME.borderLight[3], THEME.borderLight[4] or 0.70)
    end)
    editBox:SetScript("OnEditFocusLost", function()
        container:SetBackdropBorderColor(SL.GetColor("border"))
    end)

    container.editBox = editBox
    container.GetText = function(self) return self.editBox:GetText() end
    container.SetText = function(self, t) self.editBox:SetText(t) end

    return container
end

local function CreateStyledDropdown(parent, options, width)
    local gf = DDingUI:GetGlobalFont() or globalFontPath
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 200, 28)
    container:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    container:SetBackdropColor(SL.GetColor("widget"))
    container:SetBackdropBorderColor(SL.GetColor("border"))

    container.text = container:CreateFontString(nil, "OVERLAY")
    container.text:SetFont(gf, 11, "")
    container.text:SetShadowOffset(1, -1)
    container.text:SetShadowColor(0, 0, 0, 1)
    container.text:SetPoint("LEFT", 8, 0)
    container.text:SetPoint("RIGHT", -20, 0)
    container.text:SetJustifyH("LEFT")
    container.text:SetTextColor(SL.GetColor("text"))

    local arrow = container:CreateFontString(nil, "OVERLAY")
    arrow:SetFont(gf, 10, "")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("\226\150\188") -- ▼
    arrow:SetTextColor(SL.GetColor("dim"))

    container.selectedValue = nil
    container.options = options

    local menu = CreateFrame("Frame", nil, container, "BackdropTemplate")
    menu:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width or 200)
    menu:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    menu:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], THEME.bgDark[4] or 0.95)
    menu:SetBackdropBorderColor(SL.GetColor("border"))
    menu:SetFrameStrata("TOOLTIP")
    menu:Hide()
    container.menu = menu

    local function BuildMenu()
        local buttons = menu.buttons or {}
        for _, btn in ipairs(buttons) do btn:Hide() end

        local yOffset = -4
        for i, opt in ipairs(options) do
            local btn = buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, menu)
                btn:SetHeight(22)
                btn.text = btn:CreateFontString(nil, "OVERLAY")
                btn.text:SetFont(gf, 11, "")
                btn.text:SetShadowOffset(1, -1)
                btn.text:SetShadowColor(0, 0, 0, 1)
                btn.text:SetPoint("LEFT", 8, 0)
                btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
                btn.highlight:SetAllPoints()
                btn.highlight:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.2)
                buttons[i] = btn
            end
            btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, yOffset)
            btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, yOffset)
            btn.text:SetText(opt.text)
            btn.text:SetTextColor(SL.GetColor("text"))
            btn:SetScript("OnClick", function()
                container.selectedValue = opt.slotID
                container.text:SetText(opt.text)
                menu:Hide()
            end)
            btn:Show()
            yOffset = yOffset - 22
        end
        menu.buttons = buttons
        menu:SetHeight(math.abs(yOffset) + 4)
    end

    container:SetScript("OnMouseDown", function()
        if menu:IsShown() then
            menu:Hide()
        else
            BuildMenu()
            menu:Show()
        end
    end)

    container:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.5)
    end)
    container:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(SL.GetColor("border"))
    end)

    menu:SetScript("OnShow", function()
        menu:SetPropagateKeyboardInput(true)
    end)

    container.SetText = function(self, t) self.text:SetText(t) end

    return container
end

-- ============================================
-- Modal Overlay Utility -- [REFACTOR] CDM 패턴 이식
-- ============================================

local function CreateModalOverlay(parentFrame, width, height)
    local parent = parentFrame or UIParent
    local overlay = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    overlay:SetAllPoints(parent)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel(parent:GetFrameLevel() + 50)
    overlay:EnableMouse(true)
    overlay:Hide()

    local overlayBg = overlay:CreateTexture(nil, "BACKGROUND")
    overlayBg:SetAllPoints()
    overlayBg:SetColorTexture(0, 0, 0, 0.4)

    local window = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    window:SetSize(width or 420, height or 520)
    window:SetPoint("CENTER", parent, "CENTER")
    window:EnableMouse(true)
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(overlay:GetFrameLevel() + 5)
    CreateBackdrop(window, THEME.bgDark, THEME.border)
    window:SetScript("OnMouseDown", function() end)

    -- 닫기 버튼
    local closeBtn = CreateStyledButton(window, "X", 24, 24)
    closeBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() overlay:Hide() end)

    -- 배경 클릭 = 모달 닫기
    overlay:SetScript("OnMouseDown", function() overlay:Hide() end)
    overlay:SetScript("OnShow", function() window:Show() end)
    window:HookScript("OnHide", function() overlay:Hide() end)

    overlay.window = window
    overlay.closeBtn = closeBtn
    return overlay
end

-- ============================================
-- Expand/Collapse Row Utility -- [REFACTOR] CDM 아코디언 패턴 이식
-- ============================================

local ROW_HEIGHT_COLLAPSED = 32
local ROW_HEIGHT_EXPANDED = 132
local ROW_SPACING = 4

local function CreateExpandableRow(parent, rowData, expandedRef, onRepositionAll)
    local gf = DDingUI:GetGlobalFont() or globalFontPath
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT_COLLAPSED)
    CreateBackdrop(row, THEME.bgWidget, THEME.border)
    row.spellID = rowData.spellID
    row.isExpanded = false

    -- 아이콘
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    if rowData.iconTexture then
        icon:SetTexture(rowData.iconTexture)
    end
    row.icon = icon

    -- 스펠 이름
    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(gf, 11, "")
    nameText:SetShadowOffset(1, -1)
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    nameText:SetText(rowData.name or ("Spell " .. (rowData.spellID or "?")))
    nameText:SetTextColor(SL.GetColor("text"))
    row.nameText = nameText

    -- 확장 화살표
    local arrowText = row:CreateFontString(nil, "OVERLAY")
    arrowText:SetFont(gf, 10, "")
    arrowText:SetPoint("RIGHT", row, "RIGHT", -32, 0)
    arrowText:SetText("\226\150\182") -- ▶
    arrowText:SetTextColor(SL.GetColor("dim"))
    row.arrowText = arrowText

    -- X 삭제 버튼
    local removeBtn = CreateStyledButton(row, "X", 22, 22)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    if rowData.onRemove then
        removeBtn:SetScript("OnClick", function() rowData.onRemove(rowData.spellID) end)
    end
    row.removeBtn = removeBtn

    -- subPanel (확장 시 보이는 상세 설정)
    local subPanel = CreateFrame("Frame", nil, row)
    subPanel:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -ROW_HEIGHT_COLLAPSED)
    subPanel:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    subPanel:SetHeight(ROW_HEIGHT_EXPANDED - ROW_HEIGHT_COLLAPSED)
    subPanel:Hide()
    row.subPanel = subPanel

    -- subPanel 기본 컨텐츠 빌더 (rowData.buildSubPanel 콜백)
    if rowData.buildSubPanel then
        rowData.buildSubPanel(subPanel, rowData)
    end

    -- UpdateExpandState
    function row:UpdateExpandState()
        self.isExpanded = (expandedRef.current == self.spellID)
        self:SetHeight(self.isExpanded and ROW_HEIGHT_EXPANDED or ROW_HEIGHT_COLLAPSED)
        self.subPanel:SetShown(self.isExpanded)
        self.arrowText:SetText(self.isExpanded and "\226\150\188" or "\226\150\182") -- ▼ or ▶
    end

    function row:GetDynamicHeight()
        return self.isExpanded and ROW_HEIGHT_EXPANDED or ROW_HEIGHT_COLLAPSED
    end

    -- 클릭 토글 (아코디언)
    local clickArea = CreateFrame("Button", nil, row)
    clickArea:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    clickArea:SetPoint("BOTTOMRIGHT", removeBtn, "BOTTOMLEFT", -4, 0)
    clickArea:SetHeight(ROW_HEIGHT_COLLAPSED)
    clickArea:SetScript("OnClick", function()
        if expandedRef.current == row.spellID then
            expandedRef.current = nil
        else
            expandedRef.current = row.spellID
        end
        if onRepositionAll then onRepositionAll() end
    end)

    -- 호버 효과
    clickArea:SetScript("OnEnter", function()
        row:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.5)
    end)
    clickArea:SetScript("OnLeave", function()
        if not row.isExpanded then
            row:SetBackdropBorderColor(SL.GetColor("border"))
        end
    end)

    return row
end

local function RepositionExpandableRows(container)
    if not container or not container.rowFrames then return end
    local yOffset = 0
    for _, rowFrame in ipairs(container.rowFrames) do
        if rowFrame:IsShown() then
            rowFrame:ClearAllPoints()
            rowFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOffset)
            rowFrame:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            if rowFrame.UpdateExpandState then
                rowFrame:UpdateExpandState()
            end
            local h = (rowFrame.GetDynamicHeight and rowFrame:GetDynamicHeight()) or ROW_HEIGHT_COLLAPSED
            yOffset = yOffset + h + ROW_SPACING
        end
    end
    container:SetHeight(math.max(yOffset, 1))
end

-- ============================================
-- Export Public API
-- ============================================

GUI.CreateStyledButton = CreateStyledButton
GUI.CreateStyledToggle = CreateStyledToggle
GUI.CreateStyledInput = CreateStyledInput
GUI.CreateStyledDropdown = CreateStyledDropdown
GUI.CreateModalOverlay = CreateModalOverlay
GUI.CreateExpandableRow = CreateExpandableRow
GUI.RepositionExpandableRows = RepositionExpandableRows
GUI.ROW_HEIGHT_COLLAPSED = ROW_HEIGHT_COLLAPSED
GUI.ROW_HEIGHT_EXPANDED = ROW_HEIGHT_EXPANDED
GUI.ROW_SPACING = ROW_SPACING
