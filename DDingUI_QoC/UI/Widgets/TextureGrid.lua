--[[
    DDingToolKit - TextureGrid Widget
    텍스처 썸네일 그리드 스크롤 위젯
]]

local addonName, ns = ...
local UI = ns.UI

-- 그리드 설정 (2:1 비율)
local THUMBNAIL_WIDTH = 96
local THUMBNAIL_HEIGHT = 48
local GRID_COLUMNS = 3
local GRID_SPACING = 8
local GRID_PADDING = 8

-- 썸네일 버튼 생성
local function CreateThumbnailButton(parent, index)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT)
    button:SetBackdrop(UI.backdrop)
    button:SetBackdropColor(unpack(UI.colors.panel))
    button:SetBackdropBorderColor(unpack(UI.colors.border))
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- 텍스처
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", 2, -2)
    texture:SetPoint("BOTTOMRIGHT", -2, 2)
    button.texture = texture

    -- 선택 표시
    local selectedOverlay = button:CreateTexture(nil, "OVERLAY")
    selectedOverlay:SetAllPoints()
    selectedOverlay:SetColorTexture(unpack(UI.colors.selected))
    selectedOverlay:Hide()
    button.selectedOverlay = selectedOverlay

    -- 체크마크
    local checkMark = button:CreateTexture(nil, "OVERLAY")
    checkMark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkMark:SetSize(24, 24)
    checkMark:SetPoint("CENTER")
    checkMark:Hide()
    button.checkMark = checkMark

    -- 호버 효과
    button:SetScript("OnEnter", function(self)
        if not self.isSelected then
            self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
            self:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
        end
        if self.onHover then
            self.onHover(self, self.texturePath, self.textureName)
        end
    end)

    button:SetScript("OnLeave", function(self)
        if not self.isSelected then
            self:SetBackdropBorderColor(unpack(UI.colors.border))
            self:SetBackdropColor(unpack(UI.colors.panel))
        end
        if self.onHoverEnd then
            self.onHoverEnd(self)
        end
    end)

    -- 클릭 이벤트
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if self.onRightClick then
                self.onRightClick(self, self.texturePath, self.textureName)
            end
        else
            if self.onClick then
                self.onClick(self, self.texturePath, self.textureName)
            end
        end
    end)

    -- 선택 상태 설정
    function button:SetSelected(selected)
        self.isSelected = selected
        if selected then
            self.selectedOverlay:Show()
            self.checkMark:Show()
            self:SetBackdropBorderColor(unpack(UI.colors.accent))
        else
            self.selectedOverlay:Hide()
            self.checkMark:Hide()
            self:SetBackdropBorderColor(unpack(UI.colors.border))
        end
    end

    -- 텍스처 데이터 설정
    function button:SetTextureData(texturePath, textureName)
        self.texturePath = texturePath
        self.textureName = textureName
        self.texture:SetTexture(texturePath)
    end

    return button
end

-- 텍스처 그리드 생성
function UI:CreateTextureGrid(parent, width, height)
    local frame = self:CreatePanel(parent, width, height)

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -20, 5)
    frame.scrollFrame = scrollFrame

    -- 스크롤 차일드
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    local gridWidth = GRID_COLUMNS * (THUMBNAIL_WIDTH + GRID_SPACING) + GRID_PADDING * 2
    scrollChild:SetWidth(gridWidth)
    scrollChild:SetHeight(1)
    frame.scrollChild = scrollChild

    -- 스크롤바
    local scrollbar = CreateFrame("Slider", nil, frame, "BackdropTemplate")
    scrollbar:SetPoint("TOPRIGHT", -3, -5)
    scrollbar:SetPoint("BOTTOMRIGHT", -3, 5)
    scrollbar:SetWidth(14)
    scrollbar:SetBackdrop(self.backdrop)
    scrollbar:SetBackdropColor(unpack(self.colors.panel))
    scrollbar:SetBackdropBorderColor(unpack(self.colors.border))
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetMinMaxValues(0, 1)
    scrollbar:SetValue(0)
    scrollbar:SetValueStep(20)
    scrollbar:SetObeyStepOnDrag(false)
    frame.scrollbar = scrollbar

    -- 스크롤바 썸
    local thumb = scrollbar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
    thumb:SetSize(12, 40)
    thumb:SetColorTexture(unpack(self.colors.accent))
    scrollbar:SetThumbTexture(thumb)

    -- 스크롤 이벤트
    scrollbar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollbar:GetValue()
        local min, max = scrollbar:GetMinMaxValues()
        local step = 40
        if delta > 0 then
            scrollbar:SetValue(math.max(min, current - step))
        else
            scrollbar:SetValue(math.min(max, current + step))
        end
    end)

    scrollFrame:EnableMouseWheel(true)

    -- 데이터
    frame.buttons = {}
    frame.selectedButton = nil
    frame.textures = {}

    -- 레이아웃 업데이트
    function frame:LayoutThumbnails()
        local numTextures = #self.textures
        local numRows = math.ceil(numTextures / GRID_COLUMNS)
        local contentHeight = numRows * (THUMBNAIL_HEIGHT + GRID_SPACING) + GRID_PADDING * 2

        local scrollHeight = self.scrollFrame:GetHeight()
        if scrollHeight < 10 then scrollHeight = 350 end
        self.scrollChild:SetHeight(math.max(contentHeight, scrollHeight))

        for i, btn in ipairs(self.buttons) do
            if i <= numTextures then
                local row = math.floor((i - 1) / GRID_COLUMNS)
                local col = (i - 1) % GRID_COLUMNS
                local x = GRID_PADDING + col * (THUMBNAIL_WIDTH + GRID_SPACING)
                local y = -GRID_PADDING - row * (THUMBNAIL_HEIGHT + GRID_SPACING)

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", x, y)
                btn:Show()
            else
                btn:Hide()
            end
        end

        local maxScroll = math.max(0, contentHeight - self.scrollFrame:GetHeight())
        self.scrollbar:SetMinMaxValues(0, maxScroll)
        self.scrollbar:SetValue(0)

        if maxScroll == 0 then
            self.scrollbar:Hide()
        else
            self.scrollbar:Show()
        end
    end

    -- 텍스처 목록 설정
    function frame:SetTextures(textures)
        self.textures = textures or {}

        local numNeeded = #self.textures
        while #self.buttons < numNeeded do
            local btn = CreateThumbnailButton(self.scrollChild, #self.buttons + 1)
            btn.onClick = function(clickedBtn, path, name)
                self:SelectTexture(clickedBtn)
            end
            btn.onRightClick = function(clickedBtn, path, name)
                if self.onTextureRightClick then
                    self.onTextureRightClick(path, name)
                end
            end
            btn.onHover = function(hoveredBtn, path, name)
                if self.onTextureHover then
                    self.onTextureHover(path, name)
                end
            end
            btn.onHoverEnd = function(hoveredBtn)
                if self.onTextureHoverEnd then
                    self.onTextureHoverEnd()
                end
            end
            table.insert(self.buttons, btn)
        end

        for i, textureData in ipairs(self.textures) do
            local btn = self.buttons[i]
            btn:SetTextureData(textureData.path, textureData.name)
            btn:SetSelected(false)
        end

        self:LayoutThumbnails()
    end

    -- 텍스처 선택
    function frame:SelectTexture(button)
        if self.selectedButton then
            self.selectedButton:SetSelected(false)
        end
        self.selectedButton = button
        button:SetSelected(true)

        if self.onTextureSelected then
            self.onTextureSelected(button.texturePath, button.textureName)
        end
    end

    -- 경로로 선택
    function frame:SelectTextureByPath(texturePath)
        for _, btn in ipairs(self.buttons) do
            if btn.texturePath == texturePath then
                self:SelectTexture(btn)
                return true
            end
        end
        return false
    end

    -- 선택된 경로 가져오기
    function frame:GetSelectedTexturePath()
        if self.selectedButton then
            return self.selectedButton.texturePath
        end
        return nil
    end

    -- OnShow
    frame:SetScript("OnShow", function(self)
        C_Timer.After(0.01, function()
            if self.textures and #self.textures > 0 then
                self:LayoutThumbnails()
            end
        end)
    end)

    return frame
end
