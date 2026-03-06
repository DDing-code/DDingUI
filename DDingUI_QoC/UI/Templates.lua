--[[
    DDingToolKit - Templates
    공통 UI 위젯 템플릿
]]

local addonName, ns = ...
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local UI = ns.UI

-- 스타일이 적용된 프레임 생성
function UI:CreatePanel(parent, width, height, name)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetSize(width or 100, height or 100)
    frame:SetBackdrop(self.backdrop)
    frame:SetBackdropColor(unpack(self.colors.panel))
    frame:SetBackdropBorderColor(unpack(self.colors.border))
    return frame
end

-- 메인 스타일 프레임 (드래그 가능)
function UI:CreateMainFrame(parent, width, height, name)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetSize(width or 800, height or 600)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(self.backdrop)
    frame:SetBackdropColor(unpack(self.colors.background))
    frame:SetBackdropBorderColor(unpack(self.colors.border))
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    return frame
end

-- 타이틀바 생성
function UI:CreateTitleBar(parent, title)
    local titleBar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(36)
    titleBar:SetBackdrop(self.backdrop)
    titleBar:SetBackdropColor(0, 0, 0, 0.9)
    titleBar:SetBackdropBorderColor(unpack(self.colors.border))
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() parent:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)

    -- 타이틀 텍스트 (이름만 그라디언트)
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 12, 0)
    -- 글자별 그라디언트 (파랑 → 하늘색)
    local function ApplyGradientText(text)
        local len = strlenutf8(text)
        if len == 0 then return text end
        local result = ""
        local i = 0
        for char in string.gmatch(text, "([%z\1-\127\194-\244][\128-\191]*)") do
            local ratio = i / math.max(len - 1, 1)
            local r = math.floor((0.3 + ratio * 0.2) * 255)
            local g = math.floor((0.6 + ratio * 0.3) * 255)
            local b = 255
            result = result .. string.format("|cFF%02X%02X%02X%s", r, g, b, char)
            i = i + 1
        end
        return result .. "|r"
    end
    -- 색상코드가 이미 있으면 그라디언트 적용 안 함
    local displayTitle = title or "DDingQoC"
    local name, version = displayTitle:match("^(.-)%s*(v[%d%.]+)$")
    if name and version then
        if name:find("|c") then
            titleText:SetText(name .. " |cFFAAAAAA" .. version .. "|r")
        else
            titleText:SetText(ApplyGradientText(name) .. " |cFFAAAAAA" .. version .. "|r")
        end
    else
        if displayTitle:find("|c") then
            titleText:SetText(displayTitle)
        else
            titleText:SetText(ApplyGradientText(displayTitle))
        end
    end
    titleBar.title = titleText

    -- 닫기 버튼
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetScript("OnClick", function() parent:Hide() end)
    titleBar.closeButton = closeBtn

    return titleBar
end

-- 스타일이 적용된 버튼
function UI:CreateButton(parent, width, height, text)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 100, height or 28)
    btn:SetBackdrop(self.backdrop)
    btn:SetBackdropColor(unpack(self.colors.panel))
    btn:SetBackdropBorderColor(unpack(self.colors.border))

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text or "Button")
    btn.text:SetTextColor(unpack(self.colors.text))

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
        self:SetBackdropColor(unpack(UI.colors.panelLight))
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
        self:SetBackdropColor(unpack(UI.colors.panel))
    end)

    btn:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(unpack(UI.colors.accent))
    end)

    btn:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(unpack(UI.colors.panelLight))
    end)

    return btn
end

-- 스타일이 적용된 체크박스
function UI:CreateCheckbox(parent, label, onClick)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(24)

    local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    checkbox:SetPoint("LEFT")
    checkbox:SetSize(24, 24)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
    text:SetText(label or "")
    text:SetTextColor(unpack(self.colors.text))

    container:SetWidth(checkbox:GetWidth() + text:GetStringWidth() + 10)
    container.checkbox = checkbox
    container.label = text

    if onClick then
        checkbox:SetScript("OnClick", function(self)
            onClick(self:GetChecked())
        end)
    end

    function container:SetChecked(checked)
        self.checkbox:SetChecked(checked)
    end

    function container:GetChecked()
        return self.checkbox:GetChecked()
    end

    function container:SetLabel(newLabel)
        self.label:SetText(newLabel)
        self:SetWidth(self.checkbox:GetWidth() + self.label:GetStringWidth() + 10)
    end

    return container
end

-- 스타일이 적용된 슬라이더
function UI:CreateSlider(parent, label, min, max, step, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 50)

    -- 라벨
    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT")
    labelText:SetText(label or "")
    labelText:SetTextColor(unpack(self.colors.text))

    -- 값 표시
    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetPoint("TOPRIGHT")
    valueText:SetTextColor(unpack(self.colors.textDim))

    -- 슬라이더
    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -8)
    slider:SetPoint("TOPRIGHT", valueText, "BOTTOMRIGHT", 0, -8)
    slider:SetHeight(16)
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("")
    slider.High:SetText("")
    slider.Text:SetText("")

    slider:SetScript("OnValueChanged", function(self, value)
        valueText:SetText(string.format("%.1f", value))
        if onChange then
            onChange(value)
        end
    end)

    container.label = labelText
    container.value = valueText
    container.slider = slider

    function container:SetValue(value)
        self.slider:SetValue(value)
    end

    function container:GetValue()
        return self.slider:GetValue()
    end

    return container
end

-- 스타일이 적용된 드롭다운 (스크롤 지원)
function UI:CreateDropdown(parent, width, options, onSelect)
    local MAX_VISIBLE_ITEMS = 8
    local ITEM_HEIGHT = 24

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 200, 28)
    container:SetBackdrop(self.backdrop)
    container:SetBackdropColor(unpack(self.colors.panel))
    container:SetBackdropBorderColor(unpack(self.colors.border))

    -- 선택된 텍스트
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 10, 0)
    text:SetPoint("RIGHT", -25, 0)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(self.colors.text))
    container.text = text

    -- 화살표
    local arrow = container:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")

    -- 드롭다운 리스트
    local dropdown = CreateFrame("Frame", nil, container, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -2)
    dropdown:SetWidth(width or 200)
    dropdown:SetBackdrop(self.backdrop)
    dropdown:SetBackdropColor(unpack(self.colors.background))
    dropdown:SetBackdropBorderColor(unpack(self.colors.border))
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:Hide()
    container.dropdown = dropdown

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, dropdown, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
    dropdown.scrollFrame = scrollFrame

    -- 스크롤바 스타일링
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -3, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -3, 18)
    end

    -- 스크롤 컨텐츠
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width and (width - 24) or 176)
    scrollFrame:SetScrollChild(scrollChild)
    dropdown.scrollChild = scrollChild

    -- 옵션들
    container.options = options or {}
    container.selectedValue = nil
    container.buttons = {}

    function container:SetOptions(newOptions)
        self.options = newOptions
        self:RefreshOptions()
    end

    function container:RefreshOptions()
        -- 기존 버튼 제거
        for _, btn in ipairs(self.buttons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(self.buttons)

        local numOptions = #self.options
        local needsScroll = numOptions > MAX_VISIBLE_ITEMS
        local visibleHeight = math.min(numOptions, MAX_VISIBLE_ITEMS) * ITEM_HEIGHT + 4
        local contentHeight = numOptions * ITEM_HEIGHT

        -- 드롭다운 높이 설정
        self.dropdown:SetHeight(visibleHeight)
        self.dropdown.scrollChild:SetHeight(contentHeight)

        -- 스크롤바 표시/숨기기
        if scrollBar then
            if needsScroll then
                scrollBar:Show()
                scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
            else
                scrollBar:Hide()
                scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
            end
        end

        -- 새 버튼 생성
        for i, option in ipairs(self.options) do
            local btn = CreateFrame("Button", nil, self.dropdown.scrollChild)
            btn:SetHeight(ITEM_HEIGHT)
            btn:SetPoint("TOPLEFT", 0, -(i-1) * ITEM_HEIGHT)
            btn:SetPoint("TOPRIGHT", 0, -(i-1) * ITEM_HEIGHT)

            local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btnText:SetPoint("LEFT", 8, 0)
            btnText:SetText(option.text)
            btnText:SetTextColor(unpack(UI.colors.text))
            btn.label = btnText

            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(unpack(UI.colors.hover))

            btn:SetScript("OnClick", function()
                self.selectedValue = option.value
                self.text:SetText(option.text)
                self.dropdown:Hide()
                if onSelect then
                    onSelect(option.value, option.text)
                end
                if self.OnValueChanged then
                    self:OnValueChanged(option.value)
                end
            end)

            table.insert(self.buttons, btn)
        end
    end

    function container:SetValue(value)
        self.selectedValue = value
        for _, option in ipairs(self.options) do
            if option.value == value then
                self.text:SetText(option.text)
                return
            end
        end
    end

    function container:GetValue()
        return self.selectedValue
    end

    -- 클릭으로 열기/닫기
    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function(self)
        if self.dropdown:IsShown() then
            self.dropdown:Hide()
        else
            self:RefreshOptions()
            self.dropdown.scrollFrame:SetVerticalScroll(0)
            self.dropdown:Show()
        end
    end)

    container:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
    end)

    container:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    -- 마우스 휠 스크롤
    dropdown:EnableMouseWheel(true)
    dropdown:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local newScroll = current - (delta * ITEM_HEIGHT * 2)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end)

    -- 외부 클릭 시 닫기
    dropdown:SetScript("OnShow", function(self)
        self:SetFrameLevel(container:GetFrameLevel() + 10)
    end)

    container:RefreshOptions()

    return container
end

-- 에디트 박스
function UI:CreateEditBox(parent, width, height)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 200, height or 28)
    container:SetBackdrop(self.backdrop)
    container:SetBackdropColor(unpack(self.colors.panel))
    container:SetBackdropBorderColor(unpack(self.colors.border))

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", 8, -4)
    editBox:SetPoint("BOTTOMRIGHT", -8, 4)
    editBox:SetFontObject("GameFontNormal")
    editBox:SetTextColor(unpack(self.colors.text))
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if container.OnEnterPressed then
            container:OnEnterPressed()
        end
    end)

    container.editBox = editBox

    container:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
    end)

    container:SetScript("OnLeave", function(self)
        if not self.editBox:HasFocus() then
            self:SetBackdropBorderColor(unpack(UI.colors.border))
        end
    end)

    editBox:SetScript("OnEditFocusGained", function()
        container:SetBackdropBorderColor(unpack(UI.colors.borderFocus))
    end)

    editBox:SetScript("OnEditFocusLost", function()
        container:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    function container:SetText(text)
        self.editBox:SetText(text or "")
    end

    function container:GetText()
        return self.editBox:GetText()
    end

    return container
end

-- 섹션 헤더
function UI:CreateSectionHeader(parent, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetText(text or "")
    header:SetTextColor(unpack(self.colors.warning))
    return header
end

-- 구분선
function UI:CreateDivider(parent, width)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetSize(width or 100, 1)
    divider:SetColorTexture(unpack(self.colors.border))
    return divider
end

-- 색상 선택 버튼
function UI:CreateColorButton(parent, label, initialColor, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(160, 28)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)
    text:SetTextColor(unpack(self.colors.text))

    local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    btn:SetSize(24, 24)
    btn:SetPoint("LEFT", text, "RIGHT", 10, 0)
    btn:SetBackdrop(self.backdrop)
    btn:SetBackdropBorderColor(unpack(self.colors.border))

    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 3, -3)
    swatch:SetPoint("BOTTOMRIGHT", -3, 3)
    local r, g, b, a = initialColor[1] or 1, initialColor[2] or 1, initialColor[3] or 1, initialColor[4] or 1
    swatch:SetColorTexture(r, g, b, a)
    btn.swatch = swatch

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    btn:SetScript("OnClick", function()
        local curR, curG, curB, curA = initialColor[1], initialColor[2], initialColor[3], initialColor[4] or 1

        -- 색상 선택기 열기
        local info = {}
        info.r = curR
        info.g = curG
        info.b = curB
        info.a = curA  -- WoW 12.0+ API
        info.opacity = 1 - curA  -- 이전 버전 호환
        info.hasOpacity = true
        info.previousValues = { curR, curG, curB, curA }

        info.swatchFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            -- WoW 12.0+는 GetColorAlpha() 사용, 이전 버전은 OpacitySliderFrame 사용
            local newA
            if ColorPickerFrame.GetColorAlpha then
                newA = ColorPickerFrame:GetColorAlpha()
            elseif OpacitySliderFrame then
                newA = 1 - OpacitySliderFrame:GetValue()
            else
                newA = 1
            end
            swatch:SetColorTexture(newR, newG, newB, newA)
            initialColor[1] = newR
            initialColor[2] = newG
            initialColor[3] = newB
            initialColor[4] = newA
            if onChange then
                onChange(newR, newG, newB, newA)
            end
        end

        info.opacityFunc = function()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA
            if ColorPickerFrame.GetColorAlpha then
                newA = ColorPickerFrame:GetColorAlpha()
            elseif OpacitySliderFrame then
                newA = 1 - OpacitySliderFrame:GetValue()
            else
                newA = 1
            end
            swatch:SetColorTexture(newR, newG, newB, newA)
            initialColor[1] = newR
            initialColor[2] = newG
            initialColor[3] = newB
            initialColor[4] = newA
            if onChange then
                onChange(newR, newG, newB, newA)
            end
        end

        info.cancelFunc = function(prev)
            -- WoW 12.0+는 prev.a 사용, 이전 버전은 prev.opacity 사용
            local prevA = prev.a or (prev.opacity and (1 - prev.opacity)) or 1
            swatch:SetColorTexture(prev.r, prev.g, prev.b, prevA)
            initialColor[1] = prev.r
            initialColor[2] = prev.g
            initialColor[3] = prev.b
            initialColor[4] = prevA
        end

        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    function frame:SetColor(r, g, b, a)
        swatch:SetColorTexture(r, g, b, a or 1)
        initialColor[1] = r
        initialColor[2] = g
        initialColor[3] = b
        initialColor[4] = a or 1
    end

    return frame
end

-- 스크롤 가능한 패널
function UI:CreateScrollablePanel(parent, width, height, contentHeight)
    -- 컨테이너 프레임
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or parent:GetWidth() - 20, height or parent:GetHeight() - 20)

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 0)

    -- 스크롤바 스타일링
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -2, 18)
    end

    -- 컨텐츠 프레임 (실제 내용이 들어갈 곳)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(width and (width - 24) or (parent:GetWidth() - 44), contentHeight or 800)
    scrollFrame:SetScrollChild(content)

    container.scrollFrame = scrollFrame
    container.content = content

    -- 마우스 휠 스크롤
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local newScroll = current - (delta * 40)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end)

    return container
end

-- 탭 버튼
function UI:CreateTabButton(parent, text, width, onClick)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(width or 100, 32)
    tab:SetBackdrop(self.backdrop)
    tab:SetBackdropColor(unpack(self.colors.tabInactive))
    tab:SetBackdropBorderColor(unpack(self.colors.border))

    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(text or "Tab")
    tab.text:SetTextColor(unpack(self.colors.textDim))

    tab.isActive = false

    function tab:SetActive(active)
        self.isActive = active
        if active then
            self:SetBackdropColor(unpack(UI.colors.tabActive))
            self.text:SetTextColor(unpack(UI.colors.text))
        else
            self:SetBackdropColor(unpack(UI.colors.tabInactive))
            self.text:SetTextColor(unpack(UI.colors.textDim))
        end
    end

    tab:SetScript("OnEnter", function(self)
        if not self.isActive then
            self:SetBackdropColor(unpack(UI.colors.panelLight))
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if not self.isActive then
            self:SetBackdropColor(unpack(UI.colors.tabInactive))
        end
    end)

    tab:SetScript("OnClick", function(self)
        if onClick then
            onClick(self)
        end
    end)

    return tab
end

-------------------------------------------------
-- WeakAuras 스타일 미디어 드롭다운
-------------------------------------------------

-- 사운드 드롭다운 (미리듣기 버튼 포함)
function UI:CreateSoundDropdown(parent, width, options, onSelect)
    local MAX_VISIBLE_ITEMS = 8
    local ITEM_HEIGHT = 28

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 250, 28)
    container:SetBackdrop(self.backdrop)
    container:SetBackdropColor(unpack(self.colors.panel))
    container:SetBackdropBorderColor(unpack(self.colors.border))

    -- 선택된 텍스트
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 10, 0)
    text:SetPoint("RIGHT", -50, 0)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(self.colors.text))
    container.text = text

    -- 미리듣기 버튼
    local playBtn = CreateFrame("Button", nil, container)
    playBtn:SetSize(20, 20)
    playBtn:SetPoint("RIGHT", -25, 0)
    playBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    playBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    playBtn:SetScript("OnClick", function()
        if container.selectedValue and container.selectedValue ~= "" then
            PlaySoundFile(container.selectedValue, "Master")
        end
    end)
    playBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("미리듣기", 1, 1, 1)
        GameTooltip:Show()
    end)
    playBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 화살표
    local arrow = container:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")

    -- 드롭다운 리스트
    local dropdown = CreateFrame("Frame", nil, container, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -2)
    dropdown:SetWidth(width or 250)
    dropdown:SetBackdrop(self.backdrop)
    dropdown:SetBackdropColor(unpack(self.colors.background))
    dropdown:SetBackdropBorderColor(unpack(self.colors.border))
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:Hide()
    container.dropdown = dropdown

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, dropdown, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
    dropdown.scrollFrame = scrollFrame

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -3, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -3, 18)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width and (width - 24) or 226)
    scrollFrame:SetScrollChild(scrollChild)
    dropdown.scrollChild = scrollChild

    container.options = options or {}
    container.selectedValue = nil
    container.buttons = {}

    function container:SetOptions(newOptions)
        self.options = newOptions
        self:RefreshOptions()
    end

    function container:RefreshOptions()
        for _, btn in ipairs(self.buttons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(self.buttons)

        local numOptions = #self.options
        local needsScroll = numOptions > MAX_VISIBLE_ITEMS
        local visibleHeight = math.min(numOptions, MAX_VISIBLE_ITEMS) * ITEM_HEIGHT + 4
        local contentHeight = numOptions * ITEM_HEIGHT

        self.dropdown:SetHeight(visibleHeight)
        self.dropdown.scrollChild:SetHeight(contentHeight)

        if scrollBar then
            if needsScroll then
                scrollBar:Show()
                scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
            else
                scrollBar:Hide()
                scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
            end
        end

        for i, option in ipairs(self.options) do
            local btn = CreateFrame("Button", nil, self.dropdown.scrollChild)
            btn:SetHeight(ITEM_HEIGHT)
            btn:SetPoint("TOPLEFT", 0, -(i-1) * ITEM_HEIGHT)
            btn:SetPoint("TOPRIGHT", 0, -(i-1) * ITEM_HEIGHT)

            -- 미리듣기 버튼
            local itemPlayBtn = CreateFrame("Button", nil, btn)
            itemPlayBtn:SetSize(18, 18)
            itemPlayBtn:SetPoint("LEFT", 4, 0)
            itemPlayBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            itemPlayBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            itemPlayBtn:SetScript("OnClick", function(self)
                if option.value and option.value ~= "" then
                    PlaySoundFile(option.value, "Master")
                end
                self:GetParent():GetParent():GetParent():GetParent():GetParent().dropdown:Hide()
            end)

            local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btnText:SetPoint("LEFT", 28, 0)
            btnText:SetPoint("RIGHT", -4, 0)
            btnText:SetJustifyH("LEFT")
            btnText:SetText(option.text)
            btnText:SetTextColor(unpack(UI.colors.text))
            btn.label = btnText

            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(unpack(UI.colors.hover))

            btn:SetScript("OnClick", function()
                self.selectedValue = option.value
                self.text:SetText(option.text)
                self.dropdown:Hide()
                if onSelect then
                    onSelect(option.value, option.text)
                end
            end)

            table.insert(self.buttons, btn)
        end
    end

    function container:SetValue(value)
        self.selectedValue = value
        for _, option in ipairs(self.options) do
            if option.value == value then
                self.text:SetText(option.text)
                return
            end
        end
    end

    function container:GetValue()
        return self.selectedValue
    end

    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function(self)
        if self.dropdown:IsShown() then
            self.dropdown:Hide()
        else
            self:RefreshOptions()
            self.dropdown.scrollFrame:SetVerticalScroll(0)
            self.dropdown:Show()
        end
    end)

    container:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
    end)

    container:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    dropdown:EnableMouseWheel(true)
    dropdown:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local newScroll = current - (delta * ITEM_HEIGHT * 2)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end)

    dropdown:SetScript("OnShow", function(self)
        self:SetFrameLevel(container:GetFrameLevel() + 10)
    end)

    container:RefreshOptions()
    return container
end

-- 폰트 드롭다운 (폰트 미리보기 포함)
function UI:CreateFontDropdown(parent, width, options, onSelect)
    local MAX_VISIBLE_ITEMS = 8
    local ITEM_HEIGHT = 26

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 220, 28)
    container:SetBackdrop(self.backdrop)
    container:SetBackdropColor(unpack(self.colors.panel))
    container:SetBackdropBorderColor(unpack(self.colors.border))

    -- 선택된 텍스트 (해당 폰트로 표시)
    local text = container:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", 10, 0)
    text:SetPoint("RIGHT", -25, 0)
    text:SetJustifyH("LEFT")
    container.text = text

    -- 화살표
    local arrow = container:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")

    -- 드롭다운 리스트
    local dropdown = CreateFrame("Frame", nil, container, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -2)
    dropdown:SetWidth(width or 220)
    dropdown:SetBackdrop(self.backdrop)
    dropdown:SetBackdropColor(unpack(self.colors.background))
    dropdown:SetBackdropBorderColor(unpack(self.colors.border))
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:Hide()
    container.dropdown = dropdown

    local scrollFrame = CreateFrame("ScrollFrame", nil, dropdown, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
    dropdown.scrollFrame = scrollFrame

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -3, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -3, 18)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width and (width - 24) or 196)
    scrollFrame:SetScrollChild(scrollChild)
    dropdown.scrollChild = scrollChild

    container.options = options or {}
    container.selectedValue = nil
    container.buttons = {}

    -- 폰트 적용 함수
    local function ApplyFont(fontString, fontPath, size)
        local success = pcall(function()
            fontString:SetFont(fontPath, size or 12, "")
        end)
        if not success then
            fontString:SetFont(SL and SL.Font.path or "Fonts\\2002.TTF", size or 12, "") -- [12.0.1]
        end
    end

    function container:SetOptions(newOptions)
        self.options = newOptions
        self:RefreshOptions()
    end

    function container:RefreshOptions()
        for _, btn in ipairs(self.buttons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(self.buttons)

        local numOptions = #self.options
        local needsScroll = numOptions > MAX_VISIBLE_ITEMS
        local visibleHeight = math.min(numOptions, MAX_VISIBLE_ITEMS) * ITEM_HEIGHT + 4
        local contentHeight = numOptions * ITEM_HEIGHT

        self.dropdown:SetHeight(visibleHeight)
        self.dropdown.scrollChild:SetHeight(contentHeight)

        if scrollBar then
            if needsScroll then
                scrollBar:Show()
                scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
            else
                scrollBar:Hide()
                scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
            end
        end

        for i, option in ipairs(self.options) do
            local btn = CreateFrame("Button", nil, self.dropdown.scrollChild)
            btn:SetHeight(ITEM_HEIGHT)
            btn:SetPoint("TOPLEFT", 0, -(i-1) * ITEM_HEIGHT)
            btn:SetPoint("TOPRIGHT", 0, -(i-1) * ITEM_HEIGHT)

            -- 폰트 이름을 해당 폰트로 표시
            local btnText = btn:CreateFontString(nil, "OVERLAY")
            btnText:SetPoint("LEFT", 8, 0)
            btnText:SetPoint("RIGHT", -4, 0)
            btnText:SetJustifyH("LEFT")
            ApplyFont(btnText, option.value, 13)
            btnText:SetText(option.text)
            btnText:SetTextColor(unpack(UI.colors.text))
            btn.label = btnText

            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(unpack(UI.colors.hover))

            btn:SetScript("OnClick", function()
                self.selectedValue = option.value
                ApplyFont(self.text, option.value, 12)
                self.text:SetText(option.text)
                self.text:SetTextColor(unpack(UI.colors.text))
                self.dropdown:Hide()
                if onSelect then
                    onSelect(option.value, option.text)
                end
            end)

            table.insert(self.buttons, btn)
        end
    end

    function container:SetValue(value)
        self.selectedValue = value
        for _, option in ipairs(self.options) do
            if option.value == value then
                ApplyFont(self.text, option.value, 12)
                self.text:SetText(option.text)
                self.text:SetTextColor(unpack(UI.colors.text))
                return
            end
        end
        -- 기본값
        self.text:SetFont(SL and SL.Font.path or "Fonts\\2002.TTF", 12, "") -- [12.0.1]
        self.text:SetText(value or "")
        self.text:SetTextColor(unpack(UI.colors.text))
    end

    function container:GetValue()
        return self.selectedValue
    end

    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function(self)
        if self.dropdown:IsShown() then
            self.dropdown:Hide()
        else
            self:RefreshOptions()
            self.dropdown.scrollFrame:SetVerticalScroll(0)
            self.dropdown:Show()
        end
    end)

    container:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
    end)

    container:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    dropdown:EnableMouseWheel(true)
    dropdown:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local newScroll = current - (delta * ITEM_HEIGHT * 2)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end)

    dropdown:SetScript("OnShow", function(self)
        self:SetFrameLevel(container:GetFrameLevel() + 10)
    end)

    container:RefreshOptions()
    return container
end

-- 텍스처/배경 드롭다운 (미리보기 썸네일 포함)
function UI:CreateTextureDropdown(parent, width, options, onSelect)
    local MAX_VISIBLE_ITEMS = 6
    local ITEM_HEIGHT = 36

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 220, 32)
    container:SetBackdrop(self.backdrop)
    container:SetBackdropColor(unpack(self.colors.panel))
    container:SetBackdropBorderColor(unpack(self.colors.border))

    -- 미리보기 썸네일
    local preview = container:CreateTexture(nil, "ARTWORK")
    preview:SetSize(24, 24)
    preview:SetPoint("LEFT", 4, 0)
    preview:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    container.preview = preview

    -- 선택된 텍스트
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", preview, "RIGHT", 8, 0)
    text:SetPoint("RIGHT", -25, 0)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(self.colors.text))
    container.text = text

    -- 화살표
    local arrow = container:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")

    -- 드롭다운 리스트
    local dropdown = CreateFrame("Frame", nil, container, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -2)
    dropdown:SetWidth(width or 220)
    dropdown:SetBackdrop(self.backdrop)
    dropdown:SetBackdropColor(unpack(self.colors.background))
    dropdown:SetBackdropBorderColor(unpack(self.colors.border))
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:Hide()
    container.dropdown = dropdown

    local scrollFrame = CreateFrame("ScrollFrame", nil, dropdown, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
    dropdown.scrollFrame = scrollFrame

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -3, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -3, 18)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width and (width - 24) or 196)
    scrollFrame:SetScrollChild(scrollChild)
    dropdown.scrollChild = scrollChild

    container.options = options or {}
    container.selectedValue = nil
    container.buttons = {}

    function container:SetOptions(newOptions)
        self.options = newOptions
        self:RefreshOptions()
    end

    function container:RefreshOptions()
        for _, btn in ipairs(self.buttons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(self.buttons)

        local numOptions = #self.options
        local needsScroll = numOptions > MAX_VISIBLE_ITEMS
        local visibleHeight = math.min(numOptions, MAX_VISIBLE_ITEMS) * ITEM_HEIGHT + 4
        local contentHeight = numOptions * ITEM_HEIGHT

        self.dropdown:SetHeight(visibleHeight)
        self.dropdown.scrollChild:SetHeight(contentHeight)

        if scrollBar then
            if needsScroll then
                scrollBar:Show()
                scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
            else
                scrollBar:Hide()
                scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
            end
        end

        for i, option in ipairs(self.options) do
            local btn = CreateFrame("Button", nil, self.dropdown.scrollChild)
            btn:SetHeight(ITEM_HEIGHT)
            btn:SetPoint("TOPLEFT", 0, -(i-1) * ITEM_HEIGHT)
            btn:SetPoint("TOPRIGHT", 0, -(i-1) * ITEM_HEIGHT)

            -- 썸네일 미리보기
            local thumb = btn:CreateTexture(nil, "ARTWORK")
            thumb:SetSize(28, 28)
            thumb:SetPoint("LEFT", 4, 0)
            if option.value and option.value ~= "" then
                thumb:SetTexture(option.value)
                thumb:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            else
                thumb:SetColorTexture(0.2, 0.2, 0.2, 0.5)
            end

            local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btnText:SetPoint("LEFT", thumb, "RIGHT", 8, 0)
            btnText:SetPoint("RIGHT", -4, 0)
            btnText:SetJustifyH("LEFT")
            btnText:SetText(option.text)
            btnText:SetTextColor(unpack(UI.colors.text))
            btn.label = btnText

            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(unpack(UI.colors.hover))

            btn:SetScript("OnClick", function()
                self.selectedValue = option.value
                self.text:SetText(option.text)
                if option.value and option.value ~= "" then
                    self.preview:SetTexture(option.value)
                    self.preview:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                    self.preview:Show()
                else
                    self.preview:Hide()
                end
                self.dropdown:Hide()
                if onSelect then
                    onSelect(option.value, option.text)
                end
            end)

            table.insert(self.buttons, btn)
        end
    end

    function container:SetValue(value)
        self.selectedValue = value
        for _, option in ipairs(self.options) do
            if option.value == value then
                self.text:SetText(option.text)
                if option.value and option.value ~= "" then
                    self.preview:SetTexture(option.value)
                    self.preview:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                    self.preview:Show()
                else
                    self.preview:Hide()
                end
                return
            end
        end
        self.text:SetText("")
        self.preview:Hide()
    end

    function container:GetValue()
        return self.selectedValue
    end

    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function(self)
        if self.dropdown:IsShown() then
            self.dropdown:Hide()
        else
            self:RefreshOptions()
            self.dropdown.scrollFrame:SetVerticalScroll(0)
            self.dropdown:Show()
        end
    end)

    container:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
    end)

    container:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    dropdown:EnableMouseWheel(true)
    dropdown:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local newScroll = current - (delta * ITEM_HEIGHT * 2)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end)

    dropdown:SetScript("OnShow", function(self)
        self:SetFrameLevel(container:GetFrameLevel() + 10)
    end)

    container:RefreshOptions()
    return container
end

-- 상태바 텍스처 드롭다운 (가로 미리보기 포함)
function UI:CreateStatusBarDropdown(parent, width, options, onSelect)
    local MAX_VISIBLE_ITEMS = 6
    local ITEM_HEIGHT = 32

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 220, 32)
    container:SetBackdrop(self.backdrop)
    container:SetBackdropColor(unpack(self.colors.panel))
    container:SetBackdropBorderColor(unpack(self.colors.border))

    -- 미리보기 상태바
    local previewBar = CreateFrame("StatusBar", nil, container)
    previewBar:SetSize(60, 16)
    previewBar:SetPoint("LEFT", 6, 0)
    previewBar:SetMinMaxValues(0, 1)
    previewBar:SetValue(0.7)
    previewBar:SetStatusBarColor(0.2, 0.6, 1.0)
    container.previewBar = previewBar

    -- 선택된 텍스트
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", previewBar, "RIGHT", 8, 0)
    text:SetPoint("RIGHT", -25, 0)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(self.colors.text))
    container.text = text

    -- 화살표
    local arrow = container:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")

    -- 드롭다운 리스트
    local dropdown = CreateFrame("Frame", nil, container, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -2)
    dropdown:SetWidth(width or 220)
    dropdown:SetBackdrop(self.backdrop)
    dropdown:SetBackdropColor(unpack(self.colors.background))
    dropdown:SetBackdropBorderColor(unpack(self.colors.border))
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:Hide()
    container.dropdown = dropdown

    local scrollFrame = CreateFrame("ScrollFrame", nil, dropdown, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
    dropdown.scrollFrame = scrollFrame

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -3, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -3, 18)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width and (width - 24) or 196)
    scrollFrame:SetScrollChild(scrollChild)
    dropdown.scrollChild = scrollChild

    container.options = options or {}
    container.selectedValue = nil
    container.buttons = {}

    function container:SetOptions(newOptions)
        self.options = newOptions
        self:RefreshOptions()
    end

    function container:RefreshOptions()
        for _, btn in ipairs(self.buttons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(self.buttons)

        local numOptions = #self.options
        local needsScroll = numOptions > MAX_VISIBLE_ITEMS
        local visibleHeight = math.min(numOptions, MAX_VISIBLE_ITEMS) * ITEM_HEIGHT + 4
        local contentHeight = numOptions * ITEM_HEIGHT

        self.dropdown:SetHeight(visibleHeight)
        self.dropdown.scrollChild:SetHeight(contentHeight)

        if scrollBar then
            if needsScroll then
                scrollBar:Show()
                scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
            else
                scrollBar:Hide()
                scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
            end
        end

        for i, option in ipairs(self.options) do
            local btn = CreateFrame("Button", nil, self.dropdown.scrollChild)
            btn:SetHeight(ITEM_HEIGHT)
            btn:SetPoint("TOPLEFT", 0, -(i-1) * ITEM_HEIGHT)
            btn:SetPoint("TOPRIGHT", 0, -(i-1) * ITEM_HEIGHT)

            -- 상태바 미리보기
            local barPreview = CreateFrame("StatusBar", nil, btn)
            barPreview:SetSize(50, 14)
            barPreview:SetPoint("LEFT", 6, 0)
            barPreview:SetMinMaxValues(0, 1)
            barPreview:SetValue(0.7)
            if option.value and option.value ~= "" then
                barPreview:SetStatusBarTexture(option.value)
            end
            barPreview:SetStatusBarColor(0.2, 0.6, 1.0)

            local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btnText:SetPoint("LEFT", barPreview, "RIGHT", 8, 0)
            btnText:SetPoint("RIGHT", -4, 0)
            btnText:SetJustifyH("LEFT")
            btnText:SetText(option.text)
            btnText:SetTextColor(unpack(UI.colors.text))
            btn.label = btnText

            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(unpack(UI.colors.hover))

            btn:SetScript("OnClick", function()
                self.selectedValue = option.value
                self.text:SetText(option.text)
                if option.value and option.value ~= "" then
                    self.previewBar:SetStatusBarTexture(option.value)
                end
                self.dropdown:Hide()
                if onSelect then
                    onSelect(option.value, option.text)
                end
            end)

            table.insert(self.buttons, btn)
        end
    end

    function container:SetValue(value)
        self.selectedValue = value
        for _, option in ipairs(self.options) do
            if option.value == value then
                self.text:SetText(option.text)
                if option.value and option.value ~= "" then
                    self.previewBar:SetStatusBarTexture(option.value)
                end
                return
            end
        end
    end

    function container:GetValue()
        return self.selectedValue
    end

    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function(self)
        if self.dropdown:IsShown() then
            self.dropdown:Hide()
        else
            self:RefreshOptions()
            self.dropdown.scrollFrame:SetVerticalScroll(0)
            self.dropdown:Show()
        end
    end)

    container:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
    end)

    container:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    dropdown:EnableMouseWheel(true)
    dropdown:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        local newScroll = current - (delta * ITEM_HEIGHT * 2)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end)

    dropdown:SetScript("OnShow", function(self)
        self:SetFrameLevel(container:GetFrameLevel() + 10)
    end)

    container:RefreshOptions()
    return container
end
