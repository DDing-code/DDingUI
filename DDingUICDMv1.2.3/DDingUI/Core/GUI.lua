local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

-- ============================================
-- DDingUI Theme - derived from DDingUI_StyleLib
-- [REFACTOR] AceGUI → StyleLib: 하드코딩 팔레트 → StyleLib Single Source of Truth
-- ============================================
-- Collapsible group state storage (per-session)
-- false = expanded by default
local CollapsedGroups = {
    ["customIcons.header.header"] = false,           -- 동적아이콘
    ["iconCustomization.header.header"] = false,     -- 아이콘 커스터마이징
}

local SL = _G.DDingUI_StyleLib -- [12.0.1]
assert(SL, "DDingUI_StyleLib must be loaded before GUI.lua") -- [12.0.1]
local SLC = SL.Colors
local FLAT = SL.Textures.flat or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local acFrom, acTo, acLight, acDark = SL.GetAccent("CDM")

local THEME = {
    -- 액센트 (StyleLib accent preset "CDM")
    accent      = acFrom,                  -- primary accent
    accentLight = acLight,                 -- hover / light variant
    accentDark  = acDark,                  -- pressed / dark variant
    accentBlue  = acTo,                    -- gradient end

    -- 배경 (StyleLib Colors.bg)
    bgDark   = SLC.bg.sidebar,
    bgMain   = SLC.bg.main,
    bgTop    = SLC.bg.gradTop,
    bgBottom = SLC.bg.gradBottom,
    bgMedium = SLC.bg.selected,
    bgLight  = SLC.bg.hoverLight,
    bgWidget = SLC.bg.widget,
    bgHover  = SLC.bg.hover,

    -- 보더 (StyleLib Colors.border)
    border       = SLC.border.default,
    borderLight  = SLC.border.active,
    borderAccent = {acFrom[1], acFrom[2], acFrom[3], 1},

    -- 텍스트 (StyleLib Colors.text)
    text       = SLC.text.normal,
    textDim    = SLC.text.dim,
    textBright = SLC.text.highlight,
    gold       = {acFrom[1], acFrom[2], acFrom[3], 1},

    -- 인풋 (StyleLib Colors.bg.input)
    input = SLC.bg.input,

    -- 상태 색상 (StyleLib Colors.status)
    success = SLC.status.success,
    warning = SLC.status.warning,
    error   = SLC.status.error,
}

-- ============================================
-- 모듈 레벨 글로벌 폰트 경로 (CreateConfigFrame 이전에도 안전하게 접근 가능)
-- ============================================
local globalFontPath = "Fonts\\2002.TTF"

-- ============================================
-- 안전한 스크롤 범위 계산 (Secret Value 문제 방지)
-- GetVerticalScrollRange()는 EditMode에서 secret value를 반환할 수 있음
-- 대신 scrollChild의 높이를 직접 계산하여 사용
-- ============================================
local function GetSafeScrollRange(scrollFrame)
    if not scrollFrame then return 0 end
    local scrollChild = scrollFrame:GetScrollChild()
    if scrollChild then
        local ok, result = pcall(function()
            local childHeight = scrollChild:GetHeight() or 0
            local frameHeight = scrollFrame:GetHeight() or 0
            return math.max(0, childHeight - frameHeight)
        end)
        if ok then return result end
    end
    return 0
end

-- ============================================
local function StyleFontString(fontString)
    if not fontString then return end

    -- Always use DDingUI's global font for GUI elements
    local globalFontPath = DDingUI:GetGlobalFont()
    local currentFont, size, flags = fontString:GetFont()

    -- Preserve size, default to 12 if not found
    size = size or 12

    -- UF 통일: 그림자 적용 (1, -1)
    flags = ""

    -- Apply global font if available, otherwise use existing font
    if globalFontPath then
        fontString:SetFont(globalFontPath, size, flags)
    elseif currentFont and size then
        fontString:SetFont(currentFont, size, flags)
    end

    -- UF 스타일 그림자
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 1)
end

-- ============================================
-- Hover highlight 효과 (프레임 알파 기반)
-- ============================================
local function AddHoverHighlight(frame)
    frame:SetScript("OnEnter", function(self) self:SetAlpha(1.0) end)
    frame:SetScript("OnLeave", function(self) self:SetAlpha(0.7) end)
    frame:SetAlpha(0.7)
end

-- ============================================
-- FadeIn / FadeOut (11.x 호환: UIFrameFadeIn 제거됨)
-- ============================================
local function FadeIn(frame, duration)
    if not frame then return end
    if UIFrameFadeIn then
        UIFrameFadeIn(frame, duration or 0.2, frame:GetAlpha(), 1)
    else
        frame:SetAlpha(1)
    end
end

local function FadeOut(frame, duration)
    if not frame then return end
    if UIFrameFadeOut then
        UIFrameFadeOut(frame, duration or 0.2, frame:GetAlpha(), 0)
    else
        frame:SetAlpha(0)
    end
end

local function StyleEditBox(editBox, fontObjectName)
    if not editBox then return end

    -- Always use DDingUI's global font for GUI elements
    local globalFontPath = DDingUI:GetGlobalFont()

    -- Get size from font object if provided, otherwise from edit box
    local size = 12
    if fontObjectName and _G[fontObjectName] then
        local fontObject = _G[fontObjectName]
        local _, fontObjectSize = fontObject:GetFont()
        if fontObjectSize then
            size = fontObjectSize
        end
    else
        local _, editBoxSize = editBox:GetFont()
        if editBoxSize then
            size = editBoxSize
        end
    end

    -- Apply global font (UF 통일: 그림자 적용)
    if globalFontPath then
        editBox:SetFont(globalFontPath, size, "")
    end

    -- UF 스타일 그림자
    editBox:SetShadowOffset(1, -1)
    editBox:SetShadowColor(0, 0, 0, 1)
end

-- ============================================
-- Backdrop 생성 함수 (둥근 모서리 지원)
-- ============================================
local function CreateBackdrop(parent, bgColor, borderColor, edgeSize, rounded)
    if not parent then return end

    edgeSize = edgeSize or 1

    local backdrop
    if rounded then
        -- 둥근 모서리 backdrop
        backdrop = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        }
    else
        -- 기본 직각 backdrop
        backdrop = {
            bgFile = FLAT,
            edgeFile = FLAT,
            tile = false,
            tileSize = 0,
            edgeSize = edgeSize,
            insets = { left = edgeSize, right = edgeSize, top = edgeSize, bottom = edgeSize }
        }
    end

    -- BackdropTemplate이 없으면 Mixin 시도
    if not parent.SetBackdrop then
        if Mixin and BackdropTemplateMixin then
            Mixin(parent, BackdropTemplateMixin)
        end
    end

    if parent.SetBackdrop then
        parent:SetBackdrop(backdrop)

        -- 배경색 설정 (기본값: 어두운 회색)
        if bgColor and type(bgColor) == "table" then
            parent:SetBackdropColor(bgColor[1] or 0.1, bgColor[2] or 0.1, bgColor[3] or 0.1, bgColor[4] or 1)
        else
            parent:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end

        -- 테두리색 설정 (둥근 모서리면 투명하게)
        if rounded then
            parent:SetBackdropBorderColor(0, 0, 0, 0)
        elseif borderColor and type(borderColor) == "table" then
            parent:SetBackdropBorderColor(borderColor[1] or 0.2, borderColor[2] or 0.2, borderColor[3] or 0.2, borderColor[4] or 1)
        else
            parent:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        end
    end
end

-- ============================================
-- 그림자 효과 (깊이감)
-- ============================================
local function CreateShadow(frame, size)
    if frame.shadow then return frame.shadow end
    size = size or 3

    local shadow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    shadow:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -size, size)
    shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size, -size)
    shadow:SetBackdrop({
        bgFile = FLAT,
        edgeFile = "Interface\\GLUES\\Common\\TextPanel-Border",
        edgeSize = size * 3,
        insets = { left = size, right = size, top = size, bottom = size }
    })
    shadow:SetBackdropColor(0, 0, 0, 0)
    shadow:SetBackdropBorderColor(0, 0, 0, 0.5)

    frame.shadow = shadow
    return shadow
end

-- ============================================
-- 그라데이션 배경 생성 (ElvUI 스타일)
-- ============================================
local function CreateGradientBackground(parent, topColor, bottomColor)
    if not parent then return nil end
    topColor = topColor or THEME.bgTop
    bottomColor = bottomColor or THEME.bgBottom

    local gradient = parent:CreateTexture(nil, "BACKGROUND")
    gradient:SetAllPoints()
    gradient:SetColorTexture(1, 1, 1, 1)
    gradient:SetGradient("VERTICAL",
        CreateColor(bottomColor[1], bottomColor[2], bottomColor[3], bottomColor[4] or 1),
        CreateColor(topColor[1], topColor[2], topColor[3], topColor[4] or 1)
    )
    parent.gradientBg = gradient
    return gradient
end

-- ============================================
-- UF 통일: 글자별 그라디언트 텍스트 생성
-- ============================================
local function CreateGradientText(text, startColor, endColor)
    startColor = startColor or THEME.accent
    endColor = endColor or THEME.accentBlue
    local chars = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        table.insert(chars, char)
    end
    local charCount = #chars
    if charCount == 0 then return text end
    local result = ""
    for i, char in ipairs(chars) do
        local t = (i - 1) / math.max(1, charCount - 1)
        local r = startColor[1] + (endColor[1] - startColor[1]) * t
        local g = startColor[2] + (endColor[2] - startColor[2]) * t
        local b = startColor[3] + (endColor[3] - startColor[3]) * t
        local hex = string.format("%02x%02x%02x",
            math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5)
        )
        result = result .. "|cff" .. hex .. char .. "|r"
    end
    return result
end

-- ============================================
-- 액센트 그라데이션 생성 (보라 → 파랑)
-- ============================================
local function CreateAccentGradient(parent, direction)
    if not parent then return nil end
    direction = direction or "HORIZONTAL"  -- 기본: 좌(보라) → 우(파랑)

    local gradient = parent:CreateTexture(nil, "ARTWORK")
    gradient:SetAllPoints()
    gradient:SetColorTexture(1, 1, 1, 1)

    if direction == "HORIZONTAL" then
        gradient:SetGradient("HORIZONTAL",
            CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),      -- 보라 (좌)
            CreateColor(THEME.accentBlue[1], THEME.accentBlue[2], THEME.accentBlue[3], 1)  -- 파랑 (우)
        )
    else
        gradient:SetGradient("VERTICAL",
            CreateColor(THEME.accentBlue[1], THEME.accentBlue[2], THEME.accentBlue[3], 1),  -- 파랑 (하)
            CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)       -- 보라 (상)
        )
    end

    parent.accentGradient = gradient
    return gradient
end

-- ============================================
-- 커스텀 스크롤바 생성
-- ============================================
local function CreateCustomScrollBar(parent, scrollFrame)
    local scrollBar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    scrollBar:SetWidth(8)

    -- 스크롤바 트랙 배경
    scrollBar:SetBackdrop({
        bgFile = FLAT,
        edgeFile = nil,
    })
    scrollBar:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.5)

    -- 스크롤바 썸 (드래그 가능한 부분)
    local thumb = CreateFrame("Button", nil, scrollBar, "BackdropTemplate")
    thumb:SetWidth(8)
    thumb:SetHeight(40)
    thumb:SetBackdrop({
        bgFile = FLAT,
        edgeFile = nil,
    })
    thumb:SetBackdropColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
    thumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)
    scrollBar.thumb = thumb

    -- 썸 호버 효과
    thumb:SetScript("OnEnter", function(self)
        self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.8)
    end)
    thumb:SetScript("OnLeave", function(self)
        if not self.isDragging then
            self:SetBackdropColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        end
    end)

    -- 드래그 기능 (OnMouseDown/OnMouseUp 방식)
    thumb:EnableMouse(true)
    thumb.isDragging = false

    thumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.isDragging = true
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            self.dragStartY = cursorY / scale
            self.dragStartScroll = scrollFrame:GetVerticalScroll()
        end
    end)

    thumb:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.isDragging = false
            if not self:IsMouseOver() then
                self:SetBackdropColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
            end
        end
    end)

    thumb:SetScript("OnUpdate", function(self)
        if self.isDragging then
            -- 마우스 버튼이 놓였는지 확인 (thumb 바깥에서 놓았을 때도 감지)
            if not IsMouseButtonDown("LeftButton") then
                self.isDragging = false
                if not self:IsMouseOver() then
                    self:SetBackdropColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
                end
                return
            end

            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local currentY = cursorY / scale
            local deltaY = self.dragStartY - currentY

            local scrollRange = GetSafeScrollRange(scrollFrame)
            local trackHeight = scrollBar:GetHeight() - thumb:GetHeight()

            if trackHeight > 0 and scrollRange > 0 then
                local scrollDelta = (deltaY / trackHeight) * scrollRange
                local newScroll = math.max(0, math.min(scrollRange, self.dragStartScroll + scrollDelta))
                scrollFrame:SetVerticalScroll(newScroll)
                -- Thumb 위치는 아래에서 동기화됨
            end
        end
    end)

    -- 스크롤 위치에 따라 썸 위치 업데이트
    local lastScrollPos = 0
    local function UpdateThumbPosition()
        local scrollRange = GetSafeScrollRange(scrollFrame)
        local currentScroll = scrollFrame:GetVerticalScroll()

        if scrollRange <= 0 then
            thumb:Hide()
            return
        end

        thumb:Show()
        local trackHeight = scrollBar:GetHeight()
        local thumbHeight = math.max(20, trackHeight * (trackHeight / (trackHeight + scrollRange)))
        thumb:SetHeight(thumbHeight)

        local maxOffset = trackHeight - thumbHeight
        local offset = (currentScroll / scrollRange) * maxOffset
        thumb:SetPoint("TOP", scrollBar, "TOP", 0, -offset)
    end

    scrollBar.UpdateThumbPosition = UpdateThumbPosition

    -- 마우스 휠 스크롤
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local ok = pcall(function()
            local current = self:GetVerticalScroll()
            local range = GetSafeScrollRange(self)
            local step = 40

            local newScroll = current - (delta * step)
            newScroll = math.max(0, math.min(range, newScroll))
            self:SetVerticalScroll(newScroll)
            UpdateThumbPosition()
        end)
    end)

    -- 스크롤 변경 시 썸 위치 업데이트
    scrollFrame:HookScript("OnScrollRangeChanged", function()
        C_Timer.After(0.01, UpdateThumbPosition)
    end)

    -- 스크롤 위치 변경 감지 및 동기화 (드래그 스크롤 등 모든 방식 지원)
    scrollBar:SetScript("OnUpdate", function(self, elapsed)
        local ok, currentScroll = pcall(scrollFrame.GetVerticalScroll, scrollFrame)
        if ok and currentScroll ~= lastScrollPos then
            lastScrollPos = currentScroll
            UpdateThumbPosition()
        end
    end)

    -- 트랙 클릭 시 해당 위치로 이동
    scrollBar:EnableMouse(true)
    scrollBar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local localY = (cursorY / scale) - self:GetBottom()
            local trackHeight = self:GetHeight()
            local scrollRange = GetSafeScrollRange(scrollFrame)

            local percent = 1 - (localY / trackHeight)
            local newScroll = percent * scrollRange
            newScroll = math.max(0, math.min(scrollRange, newScroll))
            scrollFrame:SetVerticalScroll(newScroll)
            UpdateThumbPosition()
        end
    end)

    return scrollBar
end

-- 마우스 휠 전파: 자식 프레임 위에서도 ScrollFrame이 스크롤되도록
-- scrollChild (또는 그 자식)에서 EnableMouseWheel → 부모 ScrollFrame으로 전파
local function PropagateMouseWheelToScroll(frame, scrollFrame)
    if not frame or not scrollFrame then return end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local handler = scrollFrame:GetScript("OnMouseWheel")
        if handler then
            handler(scrollFrame, delta)
        end
    end)
end

-- 재귀: frame 및 모든 자식에게 마우스 휠 전파 설정
local function PropagateMouseWheelRecursive(frame, scrollFrame)
    if not frame or not scrollFrame then return end
    PropagateMouseWheelToScroll(frame, scrollFrame)
    if frame.GetChildren then
        for _, child in ipairs({frame:GetChildren()}) do
            PropagateMouseWheelRecursive(child, scrollFrame)
        end
    end
end

-- ============================================
-- 커스텀 드롭다운 생성 (DDingUI 테마 + 스크롤)
-- ============================================
local activeDropdown = nil  -- 현재 열린 드롭다운 트래킹

local function CreateCustomDropdown(parent, width)
    width = width or 150
    local maxVisibleItems = 10
    local itemHeight = 20

    local dropdown = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dropdown:SetSize(width, 20)

    -- 메인 버튼 배경 (외각선 최소화)
    dropdown:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    dropdown:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 1)
    dropdown:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일: 솔리드 블랙

    -- 선택된 텍스트
    local selectedText = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(selectedText)
    selectedText:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    selectedText:SetPoint("RIGHT", dropdown, "RIGHT", -20, 0)
    selectedText:SetJustifyH("LEFT")
    selectedText:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
    selectedText:SetText("Select...")
    dropdown.selectedText = selectedText

    -- 화살표 아이콘
    local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(arrow)
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
    arrow:SetText("▼")
    arrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    dropdown.arrow = arrow

    -- 드롭다운 리스트 프레임
    local listFrame = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    listFrame:SetWidth(width)
    listFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    listFrame:SetFrameStrata("TOOLTIP")
    listFrame:SetFrameLevel(1000)
    listFrame:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    listFrame:SetBackdropColor(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 1)
    listFrame:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일: 솔리드 블랙
    listFrame:Hide()
    dropdown.listFrame = listFrame

    -- 스크롤바 트랙 (배경)
    local scrollbarWidth = 8
    local scrollbarTrack = CreateFrame("Frame", nil, listFrame, "BackdropTemplate")
    scrollbarTrack:SetWidth(scrollbarWidth)
    scrollbarTrack:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, -2)
    scrollbarTrack:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -2, 2)
    scrollbarTrack:SetBackdrop({
        bgFile = FLAT,
    })
    scrollbarTrack:SetBackdropColor(0, 0, 0, 0.3)
    scrollbarTrack:Hide()
    dropdown.scrollbarTrack = scrollbarTrack

    -- 스크롤바 썸 (드래그 가능)
    local scrollbarThumb = CreateFrame("Button", nil, scrollbarTrack, "BackdropTemplate")
    scrollbarThumb:SetWidth(scrollbarWidth)
    scrollbarThumb:SetHeight(30)
    scrollbarThumb:SetPoint("TOP", scrollbarTrack, "TOP", 0, 0)
    scrollbarThumb:SetBackdrop({
        bgFile = FLAT,
    })
    scrollbarThumb:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
    scrollbarThumb:EnableMouse(true)
    scrollbarThumb.isDragging = false
    dropdown.scrollbarThumb = scrollbarThumb

    -- 썸 호버 효과
    scrollbarThumb:SetScript("OnEnter", function(self)
        if not self.isDragging then
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)
        end
    end)
    scrollbarThumb:SetScript("OnLeave", function(self)
        if not self.isDragging then
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
        end
    end)

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, listFrame)
    scrollFrame:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -2 - scrollbarWidth - 2, 2)
    dropdown.scrollFrame = scrollFrame

    -- 스크롤 자식 프레임
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width - 4 - scrollbarWidth - 2)
    scrollFrame:SetScrollChild(scrollChild)
    dropdown.scrollChild = scrollChild

    dropdown.items = {}
    dropdown.currentValue = nil
    dropdown.onValueChanged = nil

    -- 스크롤바 위치 업데이트 함수
    local function UpdateScrollbarThumb()
        local maxScroll = GetSafeScrollRange(scrollFrame)
        if maxScroll <= 0 then
            scrollbarTrack:Hide()
            return
        end
        scrollbarTrack:Show()

        local trackHeight = scrollbarTrack:GetHeight()
        local thumbHeight = math.max(20, trackHeight * (trackHeight / (trackHeight + maxScroll)))
        scrollbarThumb:SetHeight(thumbHeight)

        local currentScroll = scrollFrame:GetVerticalScroll()
        local thumbRange = trackHeight - thumbHeight
        local thumbOffset = (currentScroll / maxScroll) * thumbRange
        scrollbarThumb:ClearAllPoints()
        scrollbarThumb:SetPoint("TOP", scrollbarTrack, "TOP", 0, -thumbOffset)
    end

    -- 스크롤바 드래그 (OnMouseDown/OnMouseUp 방식으로 변경)
    scrollbarThumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.isDragging = true
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            self.dragStartY = cursorY / scale
            self.dragStartScroll = scrollFrame:GetVerticalScroll()
        end
    end)

    scrollbarThumb:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.isDragging = false
            if self:IsMouseOver() then
                self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)
            else
                self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
            end
        end
    end)

    scrollbarThumb:SetScript("OnUpdate", function(self)
        if self.isDragging then
            -- 마우스 버튼이 놓였는지 확인 (thumb 바깥에서 놓았을 때도 감지)
            if not IsMouseButtonDown("LeftButton") then
                self.isDragging = false
                if self:IsMouseOver() then
                    self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)
                else
                    self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
                end
                return
            end

            -- 델타 방식으로 스크롤 계산 (CreateCustomScrollBar와 동일한 패턴)
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local currentY = cursorY / scale
            local deltaY = self.dragStartY - currentY

            local maxScroll = GetSafeScrollRange(scrollFrame)
            local trackHeight = scrollbarTrack:GetHeight()
            local thumbHeight = self:GetHeight()
            local thumbRange = trackHeight - thumbHeight

            if thumbRange > 0 and maxScroll > 0 then
                local scrollDelta = (deltaY / thumbRange) * maxScroll
                local newScroll = math.max(0, math.min(maxScroll, self.dragStartScroll + scrollDelta))
                scrollFrame:SetVerticalScroll(newScroll)
                UpdateScrollbarThumb()  -- thumb 위치는 이 함수에서 업데이트
            end
        end
    end)

    -- 트랙 클릭 시 해당 위치로 스크롤
    scrollbarTrack:EnableMouse(true)
    scrollbarTrack:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            cursorY = cursorY / scale

            local trackTop = self:GetTop()
            local trackHeight = self:GetHeight()
            local thumbHeight = scrollbarThumb:GetHeight()
            local clickOffset = trackTop - cursorY

            local thumbRange = trackHeight - thumbHeight
            local maxScroll = GetSafeScrollRange(scrollFrame)

            if thumbRange > 0 and maxScroll > 0 then
                local targetThumbOffset = clickOffset - (thumbHeight / 2)
                targetThumbOffset = math.max(0, math.min(thumbRange, targetThumbOffset))
                local newScroll = (targetThumbOffset / thumbRange) * maxScroll
                scrollFrame:SetVerticalScroll(newScroll)
                UpdateScrollbarThumb()
            end
        end
    end)

    -- 마우스 휠 스크롤
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = GetSafeScrollRange(scrollFrame)
        local step = itemHeight * 2
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        scrollFrame:SetVerticalScroll(newScroll)
        UpdateScrollbarThumb()
    end)

    dropdown.UpdateScrollbarThumb = UpdateScrollbarThumb

    -- 호버 효과
    dropdown:EnableMouse(true)
    dropdown:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        arrow:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    end)
    dropdown:SetScript("OnLeave", function(self)
        if not listFrame:IsShown() then
            self:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
            arrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        end
    end)

    -- 클릭 시 리스트 토글
    dropdown:SetScript("OnMouseDown", function(self)
        if listFrame:IsShown() then
            listFrame:Hide()
            if activeDropdown == self then
                activeDropdown = nil
            end
        else
            if activeDropdown and activeDropdown ~= self and activeDropdown.listFrame then
                activeDropdown.listFrame:Hide()
            end
            activeDropdown = self
            listFrame:Show()
        end
    end)

    -- 리스트 프레임 닫기 처리
    listFrame:SetScript("OnHide", function()
        dropdown:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
        arrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    end)

    -- 외부 클릭 시 닫기
    listFrame:SetScript("OnShow", function(self)
        scrollFrame:SetVerticalScroll(0)
        C_Timer.After(0.01, function()
            if dropdown.UpdateScrollbarThumb then
                dropdown.UpdateScrollbarThumb()
            end
        end)
        self:SetScript("OnUpdate", function()
            if not dropdown:IsMouseOver() and not self:IsMouseOver() and not scrollbarTrack:IsMouseOver() then
                if IsMouseButtonDown("LeftButton") and not scrollbarThumb.isDragging then
                    self:Hide()
                    if activeDropdown == dropdown then
                        activeDropdown = nil
                    end
                end
            end
        end)
    end)

    -- 옵션 설정 함수
    function dropdown:SetOptions(values, currentKey)
        -- 기존 아이템을 풀에 보관 (메모리 누수 방지)
        if not self._itemPool then self._itemPool = {} end
        for _, item in ipairs(self.items) do
            item:Hide()
            item:ClearAllPoints()
            tinsert(self._itemPool, item)
        end
        wipe(self.items)

        local yOffset = 2
        local itemCount = 0

        -- Helper to detect if value is a file path (LSM returns paths as values)
        local function isFilePath(str)
            if type(str) ~= "string" then return false end
            return str:match("^Interface\\") or str:match("%.ogg$") or str:match("%.mp3$") or str:match("%.ttf$") or str:match("%.tga$") or str:match("%.blp$")
        end

        -- 키를 정렬해서 ABC 순으로 표시
        local sortedKeys = {}
        for key in pairs(values) do
            sortedKeys[#sortedKeys + 1] = key
        end
        table.sort(sortedKeys, function(a, b)
            return tostring(a):upper() < tostring(b):upper()
        end)

        for _, key in ipairs(sortedKeys) do
            local value = values[key]
            -- For LSM HashTables, value is a path - use key (name) as display text
            -- For normal selects, value is the display text
            local displayText = isFilePath(value) and tostring(key) or value
            itemCount = itemCount + 1
            local item = self._itemPool and tremove(self._itemPool) or CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
            item:SetParent(scrollChild)
            item:SetHeight(itemHeight)
            item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, -yOffset)
            item:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -2, -yOffset)

            item:SetBackdrop({
                bgFile = FLAT,
            })

            -- 왼쪽 액센트 바 (선택 표시용) - 보라→파랑 그라데이션
            local accentBar = item:CreateTexture(nil, "ARTWORK")
            accentBar:SetWidth(2)
            accentBar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
            accentBar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
            accentBar:SetColorTexture(1, 1, 1, 1)
            accentBar:SetGradient("VERTICAL",
                CreateColor(THEME.accentBlue[1], THEME.accentBlue[2], THEME.accentBlue[3], 1),  -- 파랑 (하)
                CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)       -- 보라 (상)
            )
            item.accentBar = accentBar

            local isSelected = (key == currentKey)
            if isSelected then
                item:SetBackdropColor(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 0.5)
                accentBar:Show()
            else
                item:SetBackdropColor(0, 0, 0, 0)
                accentBar:Hide()
            end

            local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            StyleFontString(itemText)
            itemText:SetPoint("LEFT", item, "LEFT", 10, 0)  -- 왼쪽 여백 늘림 (액센트 바 공간)
            itemText:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(displayText)

            if isSelected then
                itemText:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
            else
                itemText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            end

            item.key = key
            item.displayText = displayText
            item.text = itemText

            -- 호버 효과 - 배경만 살짝 밝게
            item:SetScript("OnEnter", function(self)
                if self.key ~= dropdown.currentValue then
                    self:SetBackdropColor(THEME.bgLight[1], THEME.bgLight[2], THEME.bgLight[3], 0.6)
                    self.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
                end
            end)
            item:SetScript("OnLeave", function(self)
                if self.key == dropdown.currentValue then
                    self:SetBackdropColor(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 0.5)
                    self.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
                else
                    self:SetBackdropColor(0, 0, 0, 0)
                    self.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
                end
            end)

            -- 클릭 시 선택
            item:SetScript("OnClick", function(self)
                dropdown.currentValue = self.key
                selectedText:SetText(self.displayText)
                listFrame:Hide()
                if activeDropdown == dropdown then
                    activeDropdown = nil
                end

                if dropdown.onValueChanged then
                    dropdown.onValueChanged(self.key)
                end

                for _, itm in ipairs(dropdown.items) do
                    if itm.key == self.key then
                        itm:SetBackdropColor(THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 0.5)
                        itm.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
                        itm.accentBar:Show()
                    else
                        itm:SetBackdropColor(0, 0, 0, 0)
                        itm.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
                        itm.accentBar:Hide()
                    end
                end
            end)

            table.insert(self.items, item)
            yOffset = yOffset + itemHeight
        end

        -- 스크롤 자식 높이 설정
        scrollChild:SetHeight(yOffset + 2)

        -- 리스트 높이 설정 (최대 maxVisibleItems개)
        local visibleItems = math.min(itemCount, maxVisibleItems)
        local listHeight = visibleItems * itemHeight + 6
        listFrame:SetHeight(listHeight)

        -- 현재 값 설정
        if currentKey and values[currentKey] then
            self.currentValue = currentKey
            -- LSM HashTable의 경우 경로가 아닌 이름(key)을 표시
            local displayText = isFilePath(values[currentKey]) and tostring(currentKey) or values[currentKey]
            selectedText:SetText(displayText)
        end

        -- 스크롤바 업데이트 (딜레이)
        C_Timer.After(0.01, function()
            if dropdown.UpdateScrollbarThumb then
                dropdown.UpdateScrollbarThumb()
            end
        end)
    end

    function dropdown:SetDefaultText(text)
        selectedText:SetText(text)
    end

    function dropdown:GetValue()
        return self.currentValue
    end

    function dropdown:SetValue(key, displayText)
        self.currentValue = key
        if displayText then
            selectedText:SetText(displayText)
        end
    end

    return dropdown
end

-- Main Config Frame
local ConfigFrame = nil

-- ============================================
-- 탭 버튼 - 상단 가로 배치 (Details! 스타일)
-- ============================================
local function CreateTabButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(28)

    -- 배경 설정
    btn:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    btn:SetBackdropColor(0, 0, 0, 0)  -- 기본 투명
    btn:SetBackdropBorderColor(0, 0, 0, 0)

    -- 라벨 (먼저 생성해서 너비 측정)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(label)
    label:SetText(text)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)  -- 미선택: 흰색

    -- 텍스트 너비 기반 버튼 크기
    local textWidth = label:GetStringWidth()
    btn:SetWidth(math.max(textWidth + 28, 70))
    label:SetPoint("CENTER", btn, "CENTER", 0, 1)

    -- 하단 액센트 라인 (활성 시) - 보라→파랑 그라데이션
    local accentLine = btn:CreateTexture(nil, "OVERLAY")
    accentLine:SetHeight(2)
    accentLine:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    accentLine:SetColorTexture(1, 1, 1, 1)
    accentLine:SetGradient("HORIZONTAL",
        CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),      -- 보라 (좌)
        CreateColor(THEME.accentBlue[1], THEME.accentBlue[2], THEME.accentBlue[3], 1)  -- 파랑 (우)
    )
    accentLine:Hide()

    -- 호버 효과
    btn:SetScript("OnEnter", function(self)
        if not self.active then
            self:SetBackdropColor(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], 0.3)
        end
    end)

    btn:SetScript("OnLeave", function(self)
        if not self.active then
            self:SetBackdropColor(0, 0, 0, 0)
        end
    end)

    btn:SetScript("OnClick", function(self)
        onClick(self)
    end)

    btn.label = label
    btn.active = false
    btn.accentLine = accentLine

    btn.SetActive = function(self, active)
        self.active = active
        if active then
            self.accentLine:Show()
            self:SetBackdropColor(0, 0, 0, 0)
            self.label:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)  -- 선택: 보라색
        else
            self.accentLine:Hide()
            self:SetBackdropColor(0, 0, 0, 0)
            self.label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)  -- 미선택: 흰색
        end
    end

    return btn
end

local Widgets = {}

if not Widgets._dropdownScaleHooked and ToggleDropDownMenu then
    Widgets._dropdownScaleHooked = true
    hooksecurefunc("ToggleDropDownMenu", function(level, value, dropDownFrame, anchorName, xOffset, yOffset, menuList, button, autoHideDelay)
        if dropDownFrame and dropDownFrame._ddinguiDropdownScale then
            C_Timer.After(0.01, function()
                for i = 1, (UIDROPDOWNMENU_MAXLEVELS or 2) do
                    local listFrame = _G["DropDownList" .. i]
                    if listFrame and listFrame:IsShown() and listFrame.dropdown == dropDownFrame then
                        listFrame:SetScale(dropDownFrame._ddinguiDropdownScale)
                        break
                    end
                end
            end)
        end
    end)
end

local function ResolveGetSet(method, optionsTable, option, ...)
    if not method then
        return nil
    end
    local info = {
        handler = optionsTable and optionsTable.handler,
        option = option,
        arg = option and option.arg,
    }

    local result
    if type(method) == "function" then
        result = method(info, ...)
    elseif type(method) == "string" then
        local handler = optionsTable and optionsTable.handler
        if handler and handler[method] then
            result = handler[method](handler, info, ...)
        end
    end

    -- set 호출 후 SpecProfiles 스냅샷 갱신 (전문화별 프로필 보호)
    if select("#", ...) > 0 then
        local SP = DDingUI and DDingUI.SpecProfiles
        if SP and SP.MarkDirty then
            SP:MarkDirty()
        end
    end

    return result
end

local function ResolveDisabled(disabled, optionsTable, option)
    if not disabled then
        return false
    end
    if type(disabled) == "function" then
        local info = {
            handler = optionsTable and optionsTable.handler,
            option = option,
            arg = option and option.arg,
        }
        return disabled(info) == true
    elseif type(disabled) == "string" then
        local handler = optionsTable and optionsTable.handler
        if handler and handler[disabled] then
            local info = {
                handler = handler,
                option = option,
                arg = option and option.arg,
            }
            return handler[disabled](handler, info) == true
        end
    elseif disabled == true then
        return true
    end
    return false
end

-- ============================================
-- 체크박스 - 모던 스타일 (16x16)
-- ============================================
local function CreateElvCheckbox(parent)
    local checkbox = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    checkbox:SetSize(14, 14)

    -- 배경 (UF 통일: 14x14, UF 체크박스 배경색)
    checkbox:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
    })
    checkbox:SetBackdropColor(0.115, 0.115, 0.115, 0.9)
    checkbox:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.8)

    -- 체크 마크 (UF 통일: 전체 채우기 그라데이션)
    local check = checkbox:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", 1, -1)
    check:SetPoint("BOTTOMRIGHT", -1, 1)
    check:SetColorTexture(1, 1, 1, 1)
    check:SetGradient("HORIZONTAL",
        CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),
        CreateColor(THEME.accentBlue[1], THEME.accentBlue[2], THEME.accentBlue[3], 1)
    )
    check:Hide()
    checkbox.check = check

    -- 하이라이트 (UF 통일)
    local highlightTex = checkbox:CreateTexture(nil, "ARTWORK")
    highlightTex:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.1)
    highlightTex:SetPoint("TOPLEFT", 1, -1)
    highlightTex:SetPoint("BOTTOMRIGHT", -1, 1)
    checkbox:SetHighlightTexture(highlightTex, "ADD")

    -- UF 통일: 간소화된 상태 관리
    checkbox.isChecked = false
    checkbox.SetChecked = function(self, checked)
        self.isChecked = checked
        if checked then
            self.check:Show()
            self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        else
            self.check:Hide()
            self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.8)
        end
    end

    checkbox.GetChecked = function(self)
        return self.isChecked
    end

    checkbox:SetScript("OnClick", function(self)
        self.isChecked = not self.isChecked
        self:SetChecked(self.isChecked)
    end)

    return checkbox
end

function Widgets.CreateToggle(parent, option, yOffset, optionsTable)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(28)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(label)
    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    local name = option.name or ""
    if type(name) == "function" then
        name = name()
    end
    label:SetText(name)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)

    local checkbox = CreateElvCheckbox(frame)
    checkbox:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    if option.get then
        local value = ResolveGetSet(option.get, optionsTable, option)
        checkbox.isChecked = value or false
        checkbox:SetChecked(checkbox.isChecked)
    end

    local originalOnClick = checkbox:GetScript("OnClick")
    checkbox:SetScript("OnClick", function(self)
        if originalOnClick then originalOnClick(self) end
        if option.set then
            ResolveGetSet(option.set, optionsTable, option, self:GetChecked())
        end
    end)

    -- Handle disabled state
    if option.disabled then
        local function UpdateDisabled()
            local disabled = ResolveDisabled(option.disabled, optionsTable, option)
            checkbox:SetEnabled(not disabled)
            if disabled then
                label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
                checkbox:SetAlpha(0.5)
            else
                label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)
                checkbox:SetAlpha(1)
            end
        end
        UpdateDisabled()
        frame.UpdateDisabled = UpdateDisabled
    end

    frame.Refresh = function(self)
        if option.get then
            local value = ResolveGetSet(option.get, optionsTable, option)
            checkbox.isChecked = value or false
            checkbox:SetChecked(checkbox.isChecked)
        end
        if self.UpdateDisabled then
            self.UpdateDisabled()
        end
    end

    frame.checkbox = checkbox
    frame.label = label

    return frame
end

-- ============================================
-- 슬라이더 스타일 - 얇은 트랙 + 둥근 핸들
-- ============================================
local function StyleSlider(slider)
    if not slider then return end

    -- 기본 텍스처 숨기기 및 Low/High 텍스트를 슬라이더 양쪽에 배치
    pcall(function()
        if slider.NineSlice then slider.NineSlice:Hide() end
        local sliderName = slider:GetName()
        local lowText = sliderName and _G[sliderName.."Low"] or slider.Low
        local highText = sliderName and _G[sliderName.."High"] or slider.High
        local titleText = sliderName and _G[sliderName.."Text"] or slider.Text

        -- 낮음: 슬라이더 왼쪽에 배치
        if lowText then
            lowText:ClearAllPoints()
            lowText:SetPoint("RIGHT", slider, "LEFT", -6, 0)
            lowText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            StyleFontString(lowText)
        end
        -- 높음: 슬라이더 오른쪽에 배치
        if highText then
            highText:ClearAllPoints()
            highText:SetPoint("LEFT", slider, "RIGHT", 6, 0)
            highText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            StyleFontString(highText)
        end
        if titleText then
            titleText:Hide()  -- 타이틀 텍스트는 숨김 (별도 라벨 사용)
        end
    end)

    -- 트랙 배경 (4px 높이 - UF/스펙 통일)
    if not slider.bgTexture then
        local bg = slider:CreateTexture(nil, "BACKGROUND")
        bg:SetHeight(4)
        bg:SetPoint("LEFT", 0, 0)
        bg:SetPoint("RIGHT", 0, 0)
        bg:SetColorTexture(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 1)
        slider.bgTexture = bg

        -- 진행률 바 (악센트 그라데이션) - ARTWORK 레이어, sublevel 1로 설정
        local fill = slider:CreateTexture(nil, "ARTWORK", nil, 1)
        fill:SetHeight(4)
        fill:SetPoint("LEFT", bg, "LEFT", 0, 0)
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetGradient("HORIZONTAL",
            CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),      -- 보라 (좌)
            CreateColor(THEME.accentBlue[1], THEME.accentBlue[2], THEME.accentBlue[3], 1)  -- 파랑 (우)
        )
        fill:SetWidth(1)
        fill:Show()
        slider.fillTexture = fill
    end

    -- 핸들 (8x8 사각형 - UF/스펙 통일)
    pcall(function()
        local thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetTexture(FLAT)
            thumb:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            thumb:SetSize(8, 8)
        end
    end)

    -- 진행률 바 업데이트 함수 (슬라이더에 저장하여 언제든 호출 가능)
    slider.UpdateFillBar = function(self)
        if self.fillTexture then
            local min, max = self:GetMinMaxValues()
            local value = self:GetValue()
            local range = max - min
            if range > 0 then
                local percent = (value - min) / range
                local sliderWidth = self:GetWidth()
                if sliderWidth and sliderWidth > 0 then
                    local fillWidth = math.max(1, sliderWidth * percent)
                    self.fillTexture:SetWidth(fillWidth)
                    self.fillTexture:Show()
                end
            else
                self.fillTexture:SetWidth(1)
            end
        end
    end

    -- 진행률 바 업데이트 (HookScript는 한 번만)
    if not slider._modernStyled then
        slider._modernStyled = true
        slider:HookScript("OnValueChanged", function(self)
            if self.UpdateFillBar then
                self:UpdateFillBar()
            end
        end)
        -- 크기 변경 시에도 업데이트
        slider:HookScript("OnSizeChanged", function(self)
            if self.UpdateFillBar then
                self:UpdateFillBar()
            end
        end)
    end

    -- 항상 초기화 (스타일링 때마다 fill bar 업데이트)
    C_Timer.After(0.01, function()
        if slider and slider:IsShown() and slider.UpdateFillBar then
            slider:UpdateFillBar()
        end
    end)
end

function Widgets.CreateRange(parent, option, yOffset, optionsTable)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(32)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(label)
    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    label:SetWidth(180)  -- 라벨 너비 증가 (긴 한글 텍스트 대응)
    label:SetJustifyH("LEFT")
    local name = option.name or ""
    if type(name) == "function" then
        name = name()
    end
    label:SetText(name)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)

    local valueEditBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    valueEditBox:SetHeight(18)
    valueEditBox:SetWidth(50)
    valueEditBox:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    StyleEditBox(valueEditBox, "GameFontHighlight")
    valueEditBox:SetTextColor(1, 1, 1, 1)
    valueEditBox:SetAutoFocus(false)
    valueEditBox:SetJustifyH("CENTER")
    CreateBackdrop(valueEditBox, THEME.input, {0, 0, 0, 1})  -- UF 통일

    -- Allow decimal input (don't use SetNumeric which blocks ".")
    valueEditBox:SetNumeric(false)
    valueEditBox:EnableKeyboard(false)

    -- Filter to only allow valid numeric input (numbers, decimal point, minus sign)
    valueEditBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()
        -- Remove any characters that aren't numbers, decimal point, or minus sign
        local filtered = text:gsub("[^%d%.%-]", "")
        -- Ensure only one decimal point
        local first, rest = filtered:match("^([^%.]*%.?)(.*)")
        if rest then
            filtered = first .. rest:gsub("%.", "")
        end
        if filtered ~= text then
            self:SetText(filtered)
            self:SetCursorPosition(#filtered)
        end
    end)

    local slider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:SetPoint("LEFT", label, "RIGHT", 45, 0)  -- 낮음 텍스트 공간 확보
    slider:SetPoint("RIGHT", valueEditBox, "LEFT", -45, 0)  -- 높음 텍스트 공간 확보
    slider:EnableMouse(true)

    -- Apply ElvUI-style to slider
    StyleSlider(slider)
    
    local min = option.min or 0
    local max = option.max or 100
    local step = option.step or 0.1

    -- 동적 포맷 문자열 (step에 따라 소수점 자릿수 결정)
    local formatStr = (step >= 1) and "%.0f" or (step >= 0.1 and "%.1f" or "%.2f")

    if option.get then
        local value = ResolveGetSet(option.get, optionsTable, option) or min
        value = math.max(min, math.min(max, value))
        value = math.floor((value + 0.5 * step) / step) * step
        
        slider:SetMinMaxValues(min, max)
        slider:SetValueStep(step)
        slider:SetValue(value)
        valueEditBox:SetText(string.format(formatStr, value))
    end

    local function UpdateValueFromEditBox()
        local text = valueEditBox:GetText()
        local numValue = tonumber(text)
        if numValue then
            numValue = math.max(min, math.min(max, numValue))
            numValue = math.floor((numValue + 0.5 * step) / step) * step
            slider:SetValue(numValue)
            valueEditBox:SetText(string.format(formatStr, numValue))
            if option.set then
                ResolveGetSet(option.set, optionsTable, option, numValue)
            end
        else
            local currentValue = slider:GetValue()
            valueEditBox:SetText(string.format(formatStr, currentValue))
        end
    end

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor((value + 0.5 * step) / step) * step
        value = math.max(min, math.min(max, value))
        valueEditBox:SetText(string.format(formatStr, value))
        if option.set then
            ResolveGetSet(option.set, optionsTable, option, value)
        end
        -- Fill bar 업데이트
        if self.UpdateFillBar then
            self:UpdateFillBar()
        end
    end)
    
    valueEditBox:SetScript("OnEditFocusGained", function(self)
        self:EnableKeyboard(true)
        self:HighlightText()
    end)
    
    valueEditBox:SetScript("OnEditFocusLost", function(self)
        self:EnableKeyboard(false)
        self:ClearFocus()
        UpdateValueFromEditBox()
    end)
    
    valueEditBox:SetScript("OnEnterPressed", function(self)
        self:EnableKeyboard(false)
        self:ClearFocus()
        UpdateValueFromEditBox()
    end)
    
    valueEditBox:SetScript("OnEscapePressed", function(self)
        local currentValue = slider:GetValue()
        self:SetText(tostring(currentValue))
        self:EnableKeyboard(false)
        self:ClearFocus()
    end)
    
    if option.disabled then
        local function UpdateDisabled()
            local disabled = ResolveDisabled(option.disabled, optionsTable, option)
            slider:SetEnabled(not disabled)
            valueEditBox:SetEnabled(not disabled)
            if disabled then
                label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
                valueEditBox:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            else
                label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)
                valueEditBox:SetTextColor(1, 1, 1, 1)
            end
        end
        UpdateDisabled()
        frame.UpdateDisabled = UpdateDisabled
    end
    
    frame.Refresh = function(self)
        if option.get then
            local min = option.min or 0
            local max = option.max or 100
            local step = option.step or 0.1
            local fmt = (not step or step >= 1) and "%.0f" or (step >= 0.1 and "%.1f" or "%.2f")
            local value = ResolveGetSet(option.get, optionsTable, option) or min
            value = math.max(min, math.min(max, value))
            value = math.floor((value + 0.5 * step) / step) * step
            slider:SetMinMaxValues(min, max)
            slider:SetValueStep(step)
            slider:SetValue(value)
            valueEditBox:SetText(string.format(fmt, value))
        end
        if self.UpdateDisabled then
            self.UpdateDisabled()
        end
    end
    
    frame.slider = slider
    frame.label = label
    frame.valueEditBox = valueEditBox
    
    return frame
end

function Widgets.CreateSelect(parent, option, yOffset, optionsTable, optionKey, path)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(36)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(label)
    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    -- Build info structure with path - needs to be accessible to name resolution
    local function BuildInfo()
        local info = {
            handler = optionsTable and optionsTable.handler,
            option = option,
            arg = option.arg,
            options = optionsTable,
        }
        if path then
            for i = 1, #path do
                info[i] = path[i]
            end
        end
        if optionKey then
            info[#info + 1] = optionKey
        end
        return info
    end
    
    local name = option.name or ""
    if type(name) == "function" then
        -- Create info structure for the name function (similar to AceConfig)
        local info = BuildInfo()
        -- Try calling with info structure
        local success, result = pcall(function()
            return name(info)
        end)
        if success and result then
            name = result
        else
            -- Fallback: try without info, or use a default
            success, result = pcall(function()
                return name()
            end)
            if success and result then
                name = result
            else
                name = optionKey or option.name or ""
            end
        end
    end
    label:SetText(name)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)

    -- 커스텀 드롭다운 사용
    local dropdown = CreateCustomDropdown(frame, 200)
    dropdown:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    local function ResolveMethod(method, useInfo)
        if not method then
            return nil
        end
        -- Use provided info or build new one
        local info = useInfo or BuildInfo()
        if type(method) == "function" then
            return method(info)
        elseif type(method) == "string" then
            local handler = optionsTable and optionsTable.handler
            if handler and handler[method] then
                return handler[method](handler, info)
            end
        end
        return nil
    end

    local function CallSetMethod(value)
        if not option.set then return end
        local info = BuildInfo()
        if type(option.set) == "function" then
            option.set(info, value)
        elseif type(option.set) == "string" then
            local handler = optionsTable and optionsTable.handler
            if handler and handler[option.set] then
                handler[option.set](handler, info, value)
            end
        end
        -- SpecProfiles 스냅샷 갱신
        local SP = DDingUI and DDingUI.SpecProfiles
        if SP and SP.MarkDirty then
            SP:MarkDirty()
        end
    end


    local values = {}
    if option.values then
        local info = BuildInfo()
        if type(option.values) == "function" then
            values = option.values(info) or {}
        elseif type(option.values) == "string" then
            local handler = optionsTable and optionsTable.handler
            if handler and handler[option.values] then
                values = handler[option.values](handler, info) or {}
            end
        else
            values = option.values or {}
        end
    end

    local info = BuildInfo()
    local currentValue = ResolveMethod(option.get, info)

    -- 커스텀 드롭다운에 옵션 설정
    dropdown:SetOptions(values, currentValue)

    -- 값 변경 콜백 설정
    dropdown.onValueChanged = function(key)
        CallSetMethod(key)
    end

    frame.dropdown = dropdown
    frame.label = label

    return frame
end

function Widgets.CreateColor(parent, option, yOffset, optionsTable)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(28)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(label)
    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    local name = option.name or ""
    if type(name) == "function" then
        name = name()
    end
    label:SetText(name)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)

    -- ElvUI style color swatch
    local colorButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
    colorButton:SetSize(50, 18)
    colorButton:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    colorButton:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    colorButton:SetBackdropColor(0, 0, 0, 1)
    colorButton:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일

    local colorSwatch = colorButton:CreateTexture(nil, "ARTWORK")
    colorSwatch:SetPoint("TOPLEFT", colorButton, "TOPLEFT", 2, -2)
    colorSwatch:SetPoint("BOTTOMRIGHT", colorButton, "BOTTOMRIGHT", -2, 2)

    -- Hover effect
    colorButton:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    end)
    colorButton:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
    end)
    
    local r, g, b, a = 1, 1, 1, 1
    if option.get then
        local info = {
            handler = optionsTable and optionsTable.handler,
            option = option,
            arg = option.arg,
        }
        local success
        if type(option.get) == "function" then
            success, r, g, b, a = pcall(option.get, info)
            if not success then r, g, b, a = 1, 1, 1, 1 end
        elseif type(option.get) == "string" then
            local handler = optionsTable and optionsTable.handler
            if handler and handler[option.get] then
                success, r, g, b, a = pcall(handler[option.get], handler, info)
                if not success then r, g, b, a = 1, 1, 1, 1 end
            end
        end
        r, g, b, a = r or 1, g or 1, b or 1, a or 1
    end
    colorSwatch:SetColorTexture(r, g, b, a or 1)
    
    colorButton:SetScript("OnClick", function(self)
        ColorPickerFrame:Hide()
        local previousValues = {r, g, b, a}
        
        if ColorPickerFrame.SetupColorPickerAndShow then
            local r2, g2, b2, a2 = r, g, b, (a or 1)
            local INVERTED_ALPHA = (WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE)
            if INVERTED_ALPHA then
                a2 = 1 - a2
            end
            
            local info = {
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = ColorPickerFrame:GetColorAlpha()
                    if INVERTED_ALPHA then
                        a = 1 - a
                    end
                    colorSwatch:SetColorTexture(r, g, b, a or 1)
                    if option.set then
                        ResolveGetSet(option.set, optionsTable, option, r, g, b, a)
                    end
                end,
                hasOpacity = option.hasAlpha or false,
                opacityFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = ColorPickerFrame:GetColorAlpha()
                    if INVERTED_ALPHA then
                        a = 1 - a
                    end
                    colorSwatch:SetColorTexture(r, g, b, a or 1)
                    if option.set then
                        ResolveGetSet(option.set, optionsTable, option, r, g, b, a)
                    end
                end,
                opacity = a2,
                cancelFunc = function()
                    r, g, b, a = unpack(previousValues)
                    colorSwatch:SetColorTexture(r, g, b, a or 1)
                end,
                r = r2,
                g = g2,
                b = b2,
            }
            
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            local colorPicker = ColorPickerFrame
            colorPicker.previousValues = previousValues
            
            colorPicker.func = function()
                if ColorPickerFrame.GetColorRGB then
                    r, g, b = ColorPickerFrame:GetColorRGB()
                else
                    r = ColorPickerFrame.r or r
                    g = ColorPickerFrame.g or g
                    b = ColorPickerFrame.b or b
                end
                if option.hasAlpha then
                    if OpacitySliderFrame and OpacitySliderFrame.GetValue then
                        a = OpacitySliderFrame:GetValue()
                    else
                        a = ColorPickerFrame.opacity or a
                    end
                end
                colorSwatch:SetColorTexture(r, g, b, a or 1)
                if option.set then
                    ResolveGetSet(option.set, optionsTable, option, r, g, b, a)
                end
            end
            
            colorPicker.hasOpacity = option.hasAlpha or false
            if option.hasAlpha then
                colorPicker.opacityFunc = function()
                    if ColorPickerFrame.GetColorRGB then
                        r, g, b = ColorPickerFrame:GetColorRGB()
                    else
                        r = ColorPickerFrame.r or r
                        g = ColorPickerFrame.g or g
                        b = ColorPickerFrame.b or b
                    end
                    if OpacitySliderFrame and OpacitySliderFrame.GetValue then
                        a = OpacitySliderFrame:GetValue()
                    else
                        a = ColorPickerFrame.opacity or a
                    end
                    colorSwatch:SetColorTexture(r, g, b, a or 1)
                    if option.set then
                        ResolveGetSet(option.set, optionsTable, option, r, g, b, a)
                    end
                end
                colorPicker.opacity = 1 - (a or 1)
            end
            
            if colorPicker.SetColorRGB then
                colorPicker:SetColorRGB(r, g, b)
            else
                colorPicker.r = r
                colorPicker.g = g
                colorPicker.b = b
            end
            
            colorPicker.cancelFunc = function()
                r, g, b, a = unpack(previousValues)
                colorSwatch:SetColorTexture(r, g, b, a or 1)
            end
            
            ColorPickerFrame:Show()
        end
    end)
    
    frame.colorButton = colorButton
    frame.colorSwatch = colorSwatch
    frame.label = label
    
    return frame
end

function Widgets.CreateExecute(parent, option, yOffset, optionsTable)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    -- image 속성 확인 (아이콘 버튼)
    local imageTexture = option.image
    if type(imageTexture) == "function" then
        imageTexture = imageTexture()
    end

    local imageWidth = option.imageWidth or 28
    local imageHeight = option.imageHeight or 28

    -- 아이콘만 표시하는 모드인지 확인 (image 있고 name이 비어있거나 없음)
    local name = option.name or ""
    if type(name) == "function" then
        name = name()
    end

    local isIconOnly = imageTexture and (name == "" or name == nil)

    if isIconOnly then
        -- 아이콘 전용 버튼 (배경 없음)
        frame:SetHeight(imageHeight + 4)

        local button = CreateFrame("Button", nil, frame)
        button:SetSize(imageWidth, imageHeight)
        button:SetPoint("LEFT", frame, "LEFT", 0, 0)

        -- 아이콘 텍스처
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(imageTexture)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- 하이라이트 효과 (마우스오버 시)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.3)

        -- 툴팁
        local desc = option.desc or ""
        if type(desc) == "function" then
            desc = desc()
        end

        button:SetScript("OnEnter", function(self)
            if desc and desc ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(desc, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)

        button:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        button:SetScript("OnClick", function(self)
            if option.func then
                local info = {
                    handler = optionsTable and optionsTable.handler,
                    option = option,
                    arg = option.arg,
                }
                if type(option.func) == "function" then
                    option.func(info)
                elseif type(option.func) == "string" then
                    local handler = optionsTable and optionsTable.handler
                    if handler and handler[option.func] then
                        handler[option.func](handler, info)
                    end
                end
            end
        end)

        frame.button = button
        frame.icon = icon
    else
        -- 기존 스타일 (텍스트 버튼 또는 아이콘+텍스트)
        frame:SetHeight(28)

        local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
        button:SetHeight(22)
        button:SetWidth(180)
        button:SetPoint("LEFT", frame, "LEFT", 0, 0)

        button:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            tile = false,
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        button:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 1)
        button:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        StyleFontString(label)
        label:SetPoint("CENTER")
        label:SetText(name)
        label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)

        button:SetScript("OnEnter", function(self)
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.8)
            self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            label:SetTextColor(1, 1, 1, 1)
        end)

        button:SetScript("OnLeave", function(self)
            self:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 1)
            self:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
            label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)
        end)

        button:SetScript("OnClick", function(self)
            if option.func then
                local info = {
                    handler = optionsTable and optionsTable.handler,
                    option = option,
                    arg = option.arg,
                }
                if type(option.func) == "function" then
                    option.func(info)
                elseif type(option.func) == "string" then
                    local handler = optionsTable and optionsTable.handler
                    if handler and handler[option.func] then
                        handler[option.func](handler, info)
                    end
                end
            end
        end)

        frame.button = button
        frame.label = label
    end

    return frame
end

-- 가로 배치용 아이콘 전용 execute 버튼 (xOffset 지원)
function Widgets.CreateExecuteIconOnly(parent, option, yOffset, xOffset)
    local imageTexture = option.image
    if type(imageTexture) == "function" then
        imageTexture = imageTexture()
    end

    local imageWidth = option.imageWidth or 32
    local imageHeight = option.imageHeight or 32

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(imageWidth, imageHeight)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, -yOffset)

    local button = CreateFrame("Button", nil, frame)
    button:SetAllPoints()

    -- 아이콘 텍스처
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if imageTexture then
        icon:SetTexture(imageTexture)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    else
        icon:SetColorTexture(0.3, 0.3, 0.3, 1)
    end

    -- 하이라이트 효과 (마우스오버 시)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.3)

    -- 툴팁
    local desc = option.desc or ""
    if type(desc) == "function" then
        desc = desc()
    end

    button:SetScript("OnEnter", function(self)
        -- desc를 동적으로 다시 가져옴
        local currentDesc = option.desc or ""
        if type(currentDesc) == "function" then
            currentDesc = currentDesc()
        end
        if currentDesc and currentDesc ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(currentDesc, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        if option.func then
            local info = {
                option = option,
                arg = option.arg,
            }
            if type(option.func) == "function" then
                option.func(info)
            end
        end
    end)

    frame.button = button
    frame.icon = icon

    return frame
end

function Widgets.CreateInput(parent, option, yOffset, optionsTable)
    local isMultiline = option.multiline or false
    local frame = CreateFrame("Frame", nil, parent)
    
    if isMultiline then
        frame:SetHeight(150)
    else
        frame:SetHeight(30)
    end
    
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(label)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    local name = option.name or ""
    if type(name) == "function" then
        name = name()
    end
    label:SetText(name)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)

        if isMultiline then
        -- Create container frame with backdrop (the black box background)
        local scrollContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        scrollContainer:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
        scrollContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 0)
        scrollContainer:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
        })
        scrollContainer:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], THEME.input[4])
        scrollContainer:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
        
        local scrollFrame = CreateFrame("ScrollFrame", nil, scrollContainer, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 4, -4)
        scrollFrame:SetPoint("BOTTOMRIGHT", -22, 4)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
        editBox:SetWidth(scrollFrame:GetWidth() - 20)
        editBox:SetHeight(120)
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        scrollFrame:SetScrollChild(editBox)
        
        -- Make the container and scroll frame clickable to focus and highlight the EditBox
        local function FocusAndHighlight()
            editBox:SetFocus()
            editBox:HighlightText()
        end
        
        scrollContainer:EnableMouse(true)
        scrollContainer:SetScript("OnMouseDown", FocusAndHighlight)
        scrollFrame:EnableMouse(true)
        scrollFrame:SetScript("OnMouseDown", FocusAndHighlight)
        
        -- Also highlight when EditBox gains focus (for direct clicks on the EditBox)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
            -- Add visual feedback - accent border
            scrollContainer:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        end)

        editBox:SetScript("OnEditFocusLost", function(self)
            -- Remove visual feedback
            scrollContainer:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
        end)

        if option.get then
            local text = ResolveGetSet(option.get, optionsTable, option) or ""
            editBox:SetText(text)
            editBox:SetCursorPosition(0)
            editBox:ClearFocus()
        end
        
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput and option.set then
                ResolveGetSet(option.set, optionsTable, option, self:GetText())
            end
            local text = self:GetText()
            local lines = select(2, text:gsub("\n", "\n"))
            local height = math.max(120, (lines + 1) * 14)
            self:SetHeight(height)
        end)
        
        editBox:ClearFocus()
        
        frame.editBox = editBox
        frame.scrollFrame = scrollFrame
        frame.scrollContainer = scrollContainer
    else
        local editBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
        editBox:SetHeight(24)
        editBox:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        editBox:SetWidth(200)
        StyleEditBox(editBox, "GameFontNormal")
        editBox:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
        CreateBackdrop(editBox, THEME.input, {0, 0, 0, 1})  -- UF 통일
        
        editBox:EnableKeyboard(false)
        
        if option.get then
            local text = ResolveGetSet(option.get, optionsTable, option) or ""
            editBox:SetText(text)
            editBox:ClearFocus()
        end
        
        editBox:SetScript("OnEditFocusGained", function(self)
            self:EnableKeyboard(true)
            self:SetCursorPosition(string.len(self:GetText()))
            -- Add visual feedback for focus
            CreateBackdrop(self, THEME.input, THEME.accent)
        end)

        editBox:SetScript("OnEditFocusLost", function(self)
            self:EnableKeyboard(false)
            self:ClearFocus()
            -- Remove visual feedback for focus
            CreateBackdrop(self, THEME.input, {0, 0, 0, 1})  -- UF 통일
        end)

        editBox:SetScript("OnEnter", function(self)
        end)

        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput and option.set then
                ResolveGetSet(option.set, optionsTable, option, self:GetText())
            end
        end)
        
        editBox:SetScript("OnEnterPressed", function(self)
            self:EnableKeyboard(false)
            self:ClearFocus()
        end)
        
        editBox:ClearFocus()
        
        frame.editBox = editBox
    end
    
    frame.label = label
    
    if option.desc then
        local desc = option.desc
        if type(desc) == "function" then
            desc = desc()
        end
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(desc, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    return frame
end

-- 프레임 선택 피커 (입력 필드 + 선택 버튼)
function Widgets.CreateFramePicker(parent, option, yOffset, optionsTable)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(32)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(label)
    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    label:SetWidth(150)
    label:SetJustifyH("LEFT")
    local name = option.name or ""
    if type(name) == "function" then name = name() end
    label:SetText(name)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)

    -- 선택 버튼
    local pickButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
    pickButton:SetSize(60, 22)
    pickButton:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    CreateBackdrop(pickButton, THEME.accent, THEME.borderAccent)
    local pickText = pickButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(pickText)
    pickText:SetPoint("CENTER")
    pickText:SetText(L["Select"] or "선택")
    pickText:SetTextColor(1, 1, 1, 1)
    AddHoverHighlight(pickButton)

    -- 입력 필드
    local editBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    editBox:SetHeight(22)
    editBox:SetPoint("LEFT", label, "RIGHT", 10, 0)
    editBox:SetPoint("RIGHT", pickButton, "LEFT", -8, 0)
    StyleEditBox(editBox, "GameFontHighlight")
    editBox:SetAutoFocus(false)
    CreateBackdrop(editBox, THEME.input, {0, 0, 0, 1})  -- UF 통일

    -- 초기값 설정
    if option.get then
        local value = ResolveGetSet(option.get, optionsTable, option) or ""
        editBox:SetText(value)
    end

    -- 입력 완료 시
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if option.set then
            ResolveGetSet(option.set, optionsTable, option, self:GetText())
        end
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if option.get then
            local value = ResolveGetSet(option.get, optionsTable, option) or ""
            self:SetText(value)
        end
    end)

    -- 프레임 선택 기능
    local pickerFrame = nil
    pickButton:SetScript("OnClick", function()
        if pickerFrame then return end

        -- 풀스크린 투명 프레임 생성
        pickerFrame = CreateFrame("Frame", nil, UIParent)
        pickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        pickerFrame:SetAllPoints(UIParent)
        pickerFrame:EnableMouse(true)

        -- 안내 텍스트
        local hint = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        hint:SetPoint("TOP", pickerFrame, "TOP", 0, -100)
        hint:SetText(L["Click on a frame to select it (ESC to cancel)"] or "프레임을 클릭하세요 (ESC로 취소)")
        hint:SetTextColor(1, 1, 0, 1)

        -- 하이라이트 프레임
        local highlight = CreateFrame("Frame", nil, pickerFrame, "BackdropTemplate")
        highlight:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2})
        highlight:SetBackdropBorderColor(0, 1, 0, 0.8)
        highlight:Hide()

        -- 프레임 이름 표시
        local nameLabel = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("BOTTOM", highlight, "TOP", 0, 5)
        nameLabel:SetTextColor(0, 1, 0, 1)

        -- 마우스 이동 시 하이라이트
        pickerFrame:SetScript("OnUpdate", function()
            local focusFrame = (GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus())
            if focusFrame and focusFrame ~= pickerFrame and focusFrame ~= WorldFrame then
                local frameName = focusFrame:GetName()
                if frameName then
                    highlight:ClearAllPoints()
                    highlight:SetPoint("TOPLEFT", focusFrame, "TOPLEFT", -2, 2)
                    highlight:SetPoint("BOTTOMRIGHT", focusFrame, "BOTTOMRIGHT", 2, -2)
                    highlight:Show()
                    nameLabel:SetText(frameName)
                else
                    highlight:Hide()
                    nameLabel:SetText("")
                end
            else
                highlight:Hide()
                nameLabel:SetText("")
            end
        end)

        -- 클릭 시 선택
        pickerFrame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                local focusFrame = (GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus())
                if focusFrame and focusFrame ~= pickerFrame then
                    local frameName = focusFrame:GetName()
                    if frameName then
                        editBox:SetText(frameName)
                        if option.set then
                            ResolveGetSet(option.set, optionsTable, option, frameName)
                        end
                    end
                end
            end
            pickerFrame:Hide()
            pickerFrame = nil
        end)

        -- ESC로 취소
        pickerFrame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                pickerFrame:Hide()
                pickerFrame = nil
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        pickerFrame:EnableKeyboard(true)
    end)

    frame.Refresh = function(self)
        if option.get then
            local value = ResolveGetSet(option.get, optionsTable, option) or ""
            editBox:SetText(value)
        end
    end

    frame.editBox = editBox
    frame.pickButton = pickButton
    frame.label = label

    return frame
end

function Widgets.CreateHeader(parent, option, yOffset, sectionKey)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(28)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    -- Get header name
    local name = option.name or ""
    if type(name) == "function" then
        name = name()
    end

    -- Check collapsed state
    local isCollapsed = sectionKey and (CollapsedGroups[sectionKey] ~= false) or false

    -- Collapse/Expand arrow button
    local collapseBtn = CreateFrame("Button", nil, frame)
    collapseBtn:SetSize(18, 18)
    collapseBtn:SetPoint("LEFT", frame, "LEFT", 0, 2)

    local collapseArrow = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(collapseArrow)
    collapseArrow:SetPoint("CENTER", collapseBtn, "CENTER", 0, 0)
    collapseArrow:SetText(isCollapsed and "▶" or "▼")
    collapseArrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    collapseBtn.arrow = collapseArrow
    frame.collapseBtn = collapseBtn
    frame._sectionKey = sectionKey
    frame._isCollapsed = isCollapsed

    collapseBtn:SetScript("OnEnter", function(self)
        self.arrow:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    end)
    collapseBtn:SetScript("OnLeave", function(self)
        self.arrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    end)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    StyleFontString(label)
    -- Ensure we use global font with custom size for headers (UF 통일: no outline)
    local globalFontPath = DDingUI:GetGlobalFont()
    local currentFont = label:GetFont()
    if globalFontPath then
        label:SetFont(globalFontPath, 14, "")
    elseif currentFont then
        label:SetFont(currentFont, 14, "")
    end
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetPoint("LEFT", collapseBtn, "RIGHT", 4, 0)
    label:SetJustifyH("LEFT")
    label:SetText(name)
    -- ElvUI style - gold/yellow header text
    label:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)

    -- Make label clickable too
    local labelBtn = CreateFrame("Button", nil, frame)
    labelBtn:SetPoint("TOPLEFT", label, "TOPLEFT", -2, 2)
    labelBtn:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 2, -2)
    labelBtn:SetScript("OnEnter", function()
        collapseArrow:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    end)
    labelBtn:SetScript("OnLeave", function()
        collapseArrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    end)
    labelBtn:SetScript("OnClick", function()
        collapseBtn:Click()
    end)

    -- UF 통일: 페이드 그라디언트 언더라인 + 검은 그림자
    local underline = frame:CreateTexture(nil, "ARTWORK")
    underline:SetColorTexture(1, 1, 1, 1)
    underline:SetHeight(1)
    underline:SetPoint("LEFT", frame, "BOTTOMLEFT", 0, 2)
    underline:SetPoint("RIGHT", frame, "BOTTOMRIGHT", 0, 2)
    underline:SetGradient("HORIZONTAL",
        CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6),
        CreateColor(0.25, 0.25, 0.25, 0.15)
    )

    -- UF 통일: 검은 그림자 라인 (1px 아래 오프셋)
    local shadow = frame:CreateTexture(nil, "ARTWORK", nil, -1)
    shadow:SetHeight(1)
    shadow:SetPoint("LEFT", frame, "BOTTOMLEFT", 1, 1)
    shadow:SetPoint("RIGHT", frame, "BOTTOMRIGHT", 0, 1)
    shadow:SetColorTexture(0, 0, 0, 1)

    frame.label = label
    frame._sectionWidgets = {}  -- Will hold widgets in this section

    return frame
end

function Widgets.CreateDescription(parent, option, yOffset, optionsTable)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(label)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    
    local name = option.name or ""
    if type(name) == "function" then
        local info = {
            handler = optionsTable and optionsTable.handler,
            option = option,
            arg = option.arg,
        }
            local success, result = pcall(name, info)
            if success then
                name = result or ""
            else
                success, result = pcall(name)
                if success then
                    name = result or ""
                else
                    name = ""
                end
            end
        end
    label:SetText(name)
    label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    
    frame:SetHeight(label:GetStringHeight() + 10)
    frame.label = label
    
    return frame
end

local function RenderOptions(contentFrame, options, path, parentFrame)
    path = path or {}
    parentFrame = parentFrame or contentFrame:GetParent():GetParent()

    if contentFrame.subScrollChild then
        if contentFrame.subScrollChild.widgets then
            for i = #contentFrame.subScrollChild.widgets, 1, -1 do
                local widget = contentFrame.subScrollChild.widgets[i]
                if widget then
                    widget:Hide()
                    widget:SetParent(nil)
                end
            end
            contentFrame.subScrollChild.widgets = {}
        end
        contentFrame.subScrollChild = nil
    end
    if contentFrame.subTabContainer then
        contentFrame.subTabContainer:Hide()
        contentFrame.subTabContainer:SetParent(nil)
        contentFrame.subTabContainer = nil
    end
    if contentFrame.subContentArea then
        contentFrame.subContentArea:Hide()
        contentFrame.subContentArea:SetParent(nil)
        contentFrame.subContentArea = nil
    end
    if contentFrame.subTabButtons then
        for _, btn in ipairs(contentFrame.subTabButtons) do
            if btn then
                btn:Hide()
                btn:SetParent(nil)
            end
        end
        contentFrame.subTabButtons = nil
    end

    if contentFrame.widgets then
        for i = #contentFrame.widgets, 1, -1 do
            local widget = contentFrame.widgets[i]
            if widget then
                widget:Hide()
                widget:SetParent(nil)
            end
        end
    end
    contentFrame.widgets = {}
    
    if options.childGroups == "tab" then
        -- Get the parent frame's content area and scroll frame to make tabs sticky
        local parentContentArea = parentFrame and parentFrame.contentArea
        local parentScrollFrame = parentFrame and parentFrame.scrollFrame
        
        -- Check if we're in a nested tab situation (sub-sub tabs)
        -- Look for parent sub tab containers to calculate offset
        local cumulativeTabHeight = 0
        local parentSubTabContainer = nil
        
        -- When nested, contentFrame is a subScrollChild, whose parent is subContentArea,
        -- whose parent is the parent contentFrame that has the subTabContainer
        local parentContainer = contentFrame:GetParent()
        if parentContainer then
            local grandParentFrame = parentContainer:GetParent()
            if grandParentFrame and grandParentFrame.subTabContainer then
                -- Found parent sub tab container
                parentSubTabContainer = grandParentFrame.subTabContainer
                cumulativeTabHeight = cumulativeTabHeight + (grandParentFrame._subTabContainerHeight or 35)
            elseif parentContainer.subTabContainer then
                -- Parent frame itself has sub tab container
                parentSubTabContainer = parentContainer.subTabContainer
                cumulativeTabHeight = cumulativeTabHeight + (parentContainer._subTabContainerHeight or 35)
            end
        end

        -- Create sub tab container as child of contentArea (not scrollChild) so it stays fixed
        local subTabContainer = CreateFrame("Frame", nil, parentContentArea or contentFrame, "BackdropTemplate")
        subTabContainer:SetHeight(35)
        subTabContainer:SetFrameStrata("HIGH")
        subTabContainer:SetFrameLevel((parentScrollFrame and parentScrollFrame:GetFrameLevel() or 1) + 10)
        
        -- Add background to make it look good when sticky
        local bgMediumTransparent = {THEME.bgMedium[1], THEME.bgMedium[2], THEME.bgMedium[3], 0.95}
        CreateBackdrop(subTabContainer, bgMediumTransparent, {0, 0, 0, 1})  -- UF 통일
        
        if parentContentArea and parentScrollFrame then
            if parentSubTabContainer then
                -- Nested tabs: position below parent sub tab container
                subTabContainer:SetPoint("TOPLEFT", parentSubTabContainer, "BOTTOMLEFT", 0, 0)
                subTabContainer:SetPoint("TOPRIGHT", parentSubTabContainer, "BOTTOMRIGHT", 0, 0)
            else
                -- Top-level sub tabs: position relative to scroll frame's viewport (sticky at top)
                subTabContainer:SetPoint("TOPLEFT", parentScrollFrame, "TOPLEFT", 0, 0)
                subTabContainer:SetPoint("TOPRIGHT", parentScrollFrame, "TOPRIGHT", 0, 0)
            end
        else
            -- Fallback to original positioning if parent info not available
            if parentSubTabContainer then
                subTabContainer:SetPoint("TOPLEFT", parentSubTabContainer, "BOTTOMLEFT", 0, 0)
                subTabContainer:SetPoint("TOPRIGHT", parentSubTabContainer, "BOTTOMRIGHT", 0, 0)
            else
                subTabContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
                subTabContainer:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
            end
        end

        local subContentArea = CreateFrame("Frame", nil, contentFrame)
        -- Position normally - content starts at top, tab container overlays it
        local tabContainerHeight = 35
        subContentArea:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -1)
        subContentArea:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
        
        -- Store tab container height for height calculations
        contentFrame._subTabContainerHeight = tabContainerHeight
        -- Store cumulative height for nested tabs
        contentFrame._cumulativeTabHeight = cumulativeTabHeight + tabContainerHeight
        
        local subScrollChild = CreateFrame("Frame", nil, subContentArea)
        -- Position normally - content will start below tab container via yOffset
        subScrollChild:SetPoint("TOPLEFT", subContentArea, "TOPLEFT", 10, -10)
        subScrollChild:SetPoint("RIGHT", subContentArea, "RIGHT", -10, 0)
        subScrollChild.widgets = {}
        -- Store tab container height so RenderOptions can account for it
        subScrollChild._tabContainerHeight = contentFrame._cumulativeTabHeight or (contentFrame._subTabContainerHeight or 35)
        
        local sortedTabs = {}
        for key, option in pairs(options.args or {}) do
            if option.type == "group" or (option.type ~= "group" and option.type ~= "header" and option.type ~= "description") then
                -- hidden 체크 추가
                local isHidden = false
                if option.hidden then
                    if type(option.hidden) == "function" then
                        isHidden = option.hidden()
                    else
                        isHidden = option.hidden
                    end
                end
                if not isHidden then
                    table.insert(sortedTabs, {key = key, option = option, order = option.order or 999})
                end
            end
        end
        table.sort(sortedTabs, function(a, b) return a.order < b.order end)
        
        local subTabButtons = {}
        local tabX = 5
        
        for i, item in ipairs(sortedTabs) do
            local displayName = item.option.name or item.key
            if type(displayName) == "function" then
                displayName = displayName()
            end
            
            local subTabBtn = CreateTabButton(subTabContainer, displayName, function(btn)
                for _, t in ipairs(subTabButtons) do
                    t:SetActive(false)
                end
                btn:SetActive(true)

                RenderOptions(subScrollChild, item.option, path, parentFrame)

                -- Update content frame height after rendering sub-tab content
                -- Use multiple delays to ensure content has finished rendering
                if contentFrame._updateSubTabHeight then
                    C_Timer.After(0.02, contentFrame._updateSubTabHeight)
                    C_Timer.After(0.1, contentFrame._updateSubTabHeight)
                end
            end)
            subTabBtn:SetPoint("LEFT", subTabContainer, "LEFT", tabX, 0)

            local textWidth = subTabBtn.label:GetStringWidth()
            local buttonWidth = textWidth + 20
            subTabBtn:SetWidth(buttonWidth)
            tabX = tabX + buttonWidth + 5
            
            table.insert(subTabButtons, subTabBtn)
        end
        
        contentFrame.subTabContainer = subTabContainer
        contentFrame.subContentArea = subContentArea
        contentFrame.subTabButtons = subTabButtons
        contentFrame.subScrollChild = subScrollChild

        -- Update scroll child height to account for tab container
        -- This will be called after sub-tab content is rendered
        -- NOTE: 이 함수는 첫 번째 서브탭 렌더링 전에 정의되어야 함
        contentFrame._updateSubTabHeight = function()
            if subScrollChild then
                local subContentHeight = subScrollChild:GetHeight() or 100
                local tabContainerHeight = contentFrame._subTabContainerHeight or 35
                -- Content frame needs to be tall enough for tab container + content + padding
                -- Add extra bottom padding (50px) to ensure all content is scrollable
                local bottomPadding = 50
                local totalHeight = subContentHeight + tabContainerHeight + bottomPadding

                if contentFrame.scrollFrame then
                    contentFrame:SetHeight(totalHeight)
                    -- Force scroll bar update after height change
                    if contentFrame.scrollFrame.ScrollBar and contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition then
                        C_Timer.After(0.02, contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition)
                    end
                elseif contentFrame:GetParent() and contentFrame:GetParent():GetObjectType() == "ScrollFrame" then
                    contentFrame:SetHeight(totalHeight)
                else
                    contentFrame:SetHeight(totalHeight)
                end
            end
        end

        if #subTabButtons > 0 then
            subTabButtons[1]:SetActive(true)
            RenderOptions(subScrollChild, sortedTabs[1].option, path, parentFrame)

            -- Update content frame height after initial render
            -- Use multiple delays to ensure content has finished rendering
            C_Timer.After(0.02, contentFrame._updateSubTabHeight)
            C_Timer.After(0.1, contentFrame._updateSubTabHeight)
            C_Timer.After(0.3, contentFrame._updateSubTabHeight)
        end

        return
    end
    
    local sortedOptions = {}
    for key, option in pairs(options.args or {}) do
        table.insert(sortedOptions, {key = key, option = option, order = option.order or 999})
    end
    table.sort(sortedOptions, function(a, b) return a.order < b.order end)
    
    -- Start yOffset accounting for sticky tab container if present
    local yOffset = 15
    if contentFrame._tabContainerHeight then
        yOffset = yOffset + contentFrame._tabContainerHeight
    end
    local widgetHeight = 0

    -- 가로 배치용 변수 (아이콘 전용 execute 버튼)
    local xOffset = 10
    local iconRowHeight = 0
    local ICON_SPACING = 4
    local MAX_ROW_WIDTH = (contentFrame:GetWidth() or 500) - 30

    -- Section tracking for collapsible headers
    local currentHeaderWidget = nil
    local currentSectionKey = nil
    local currentSectionCollapsed = false
    local sectionWidgets = {}
    local headerWidgets = {}

    -- 아이콘 전용 버튼인지 확인하는 헬퍼 함수
    local function IsIconOnlyExecute(opt)
        if opt.type ~= "execute" then return false end
        local img = opt.image
        if type(img) == "function" then img = img() end
        local nm = opt.name or ""
        if type(nm) == "function" then nm = nm() end
        return img and (nm == "" or nm == " " or nm == nil)
    end

    -- 아이콘 행 종료 처리
    local function EndIconRow()
        if iconRowHeight > 0 then
            yOffset = yOffset + iconRowHeight + ICON_SPACING + 5
            xOffset = 10
            iconRowHeight = 0
        end
    end

    for _, item in ipairs(sortedOptions) do
        local key = item.key
        local option = item.option

        -- hidden 체크 (숨김 처리)
        local isHidden = false
        if option.hidden then
            if type(option.hidden) == "function" then
                isHidden = option.hidden()
            else
                isHidden = option.hidden
            end
        end

        if not isHidden then
            local widget = nil

            -- 아이콘 전용이 아닌 다른 타입이 나오면 아이콘 행 종료
            local isIconOnly = IsIconOnlyExecute(option)
            if not isIconOnly and iconRowHeight > 0 then
                EndIconRow()
            end

            if option.type == "toggle" then
                widget = Widgets.CreateToggle(contentFrame, option, yOffset, options)
                widgetHeight = 28
            elseif option.type == "range" then
                widget = Widgets.CreateRange(contentFrame, option, yOffset, options)
                widgetHeight = 32
            elseif option.type == "select" then
                -- Build path for info structure
                local currentPath = {}
                if path then
                    for i = 1, #path do
                        currentPath[i] = path[i]
                    end
                end
                currentPath[#currentPath + 1] = key
                widget = Widgets.CreateSelect(contentFrame, option, yOffset, options, key, currentPath)
                widgetHeight = 36
            elseif option.type == "color" then
                widget = Widgets.CreateColor(contentFrame, option, yOffset, options)
                widgetHeight = 28
            elseif option.type == "execute" then
                -- 아이콘 전용 버튼인지 확인
                if IsIconOnlyExecute(option) then
                    local imgW = option.imageWidth or 32
                    local imgH = option.imageHeight or 32

                    -- 현재 행에 공간이 없으면 다음 행으로
                    if xOffset + imgW > MAX_ROW_WIDTH then
                        EndIconRow()
                    end

                    -- 아이콘 버튼 생성 (가로 배치용)
                    widget = Widgets.CreateExecuteIconOnly(contentFrame, option, yOffset, xOffset)

                    -- xOffset 업데이트
                    xOffset = xOffset + imgW + ICON_SPACING
                    if imgH > iconRowHeight then
                        iconRowHeight = imgH
                    end

                    -- 아이콘은 yOffset을 증가시키지 않음 (같은 행)
                    widgetHeight = 0
                else
                    -- 일반 버튼이면 아이콘 행 종료
                    EndIconRow()
                    widget = Widgets.CreateExecute(contentFrame, option, yOffset)
                    widgetHeight = 28
                end
            elseif option.type == "dynamicIcons" then
                if DDingUI and DDingUI.CustomIcons and DDingUI.CustomIcons.BuildDynamicIconsUI then
                    local dynFrame = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
                    dynFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                    dynFrame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                    -- Set initial width and height for proper layout (CustomIcons uses BOTTOM anchors)
                    dynFrame:SetWidth(contentFrame:GetWidth() or 900)
                    dynFrame:SetHeight(750)  -- 충분한 초기 높이 설정
                    DDingUI.CustomIcons:BuildDynamicIconsUI(dynFrame)
                    widget = dynFrame
                    widgetHeight = 750  -- 고정 높이 사용
                end
            elseif option.type == "iconCustomization" then
                if DDingUI and DDingUI.IconCustomization and DDingUI.IconCustomization.BuildIconCustomizationUI then
                    local iconFrame = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
                    iconFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                    iconFrame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                    -- Set initial width for proper layout calculation
                    iconFrame:SetWidth(contentFrame:GetWidth() or 900)
                    DDingUI.IconCustomization:BuildIconCustomizationUI(iconFrame)
                    widget = iconFrame
                    -- Get height after BuildIconCustomizationUI sets it
                    widgetHeight = iconFrame:GetHeight() or 400
                end
            elseif option.type == "partyRaidFramesPage" then
                local embed = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
                embed:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                embed:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                embed:SetWidth(contentFrame:GetWidth() or 600)
                embed:SetHeight(contentFrame:GetHeight() or 600)

                local mode = option.mode or "party"
                if DDingUI and DDingUI.PartyFrames and DDingUI.PartyFrames.RenderOptionsPage then
                    DDingUI.PartyFrames:RenderOptionsPage(embed, mode, option.builder)
                end

                widget = embed
                widgetHeight = embed:GetHeight() or 600
            elseif option.type == "clickCastingPage" then
                local embed = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
                embed:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                embed:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                embed:SetWidth(contentFrame:GetWidth() or 600)
                embed:SetHeight(600)

                if DDingUI and DDingUI.PartyFrames and DDingUI.PartyFrames.ClickCast and DDingUI.PartyFrames.ClickCast.CreateClickCastUI then
                    local defaultTab = option.defaultTab or "spells"
                    DDingUI.PartyFrames.ClickCast:CreateClickCastUI(embed, defaultTab)
                end

                widget = embed
                widgetHeight = embed:GetHeight() or 600
            elseif option.type == "embedCDMIconGrid" then
                -- CDM Icon Grid for BuffTracker (custom embed widget)
                local container = CreateFrame("Frame", nil, contentFrame)
                container:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -yOffset)
                container:SetPoint("RIGHT", contentFrame, "RIGHT", -10, 0)

                local gridHeight = 120  -- Default height
                if DDingUI and DDingUI.GetCDMIconGridHeight then
                    gridHeight = DDingUI.GetCDMIconGridHeight()
                end
                container:SetHeight(gridHeight)

                if DDingUI and DDingUI.CreateCDMIconGridWidget then
                    local grid = DDingUI.CreateCDMIconGridWidget(container)
                    if grid then
                        grid:ClearAllPoints()
                        grid:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
                    end
                end

                widget = container
                widgetHeight = gridHeight
            elseif option.type == "input" then
                widget = Widgets.CreateInput(contentFrame, option, yOffset, options)
                widgetHeight = option.multiline and 150 or 32
            elseif option.type == "framepicker" then
                widget = Widgets.CreateFramePicker(contentFrame, option, yOffset, options)
                widgetHeight = 32
            elseif option.type == "header" then
                -- Generate section key for this header
                local headerName = option.name or ""
                if type(headerName) == "function" then
                    headerName = headerName()
                end
                local sectionKey = table.concat(path or {}, ".") .. ".header." .. (key or headerName)

                -- Finalize previous section
                if currentHeaderWidget and currentSectionKey then
                    headerWidgets[currentSectionKey] = currentHeaderWidget
                end

                -- Create collapsible header
                widget = Widgets.CreateHeader(contentFrame, option, yOffset, sectionKey)
                widgetHeight = 28

                -- Track this as current section
                currentHeaderWidget = widget
                currentSectionKey = sectionKey
                currentSectionCollapsed = CollapsedGroups[sectionKey] ~= false
                sectionWidgets[sectionKey] = {}

                -- Set up collapse button click handler
                if widget.collapseBtn then
                    widget.collapseBtn:SetScript("OnClick", function(self)
                        local sk = widget._sectionKey
                        local collapsed = CollapsedGroups[sk] ~= false  -- nil or true = collapsed

                        if collapsed then
                            -- Expand
                            CollapsedGroups[sk] = false
                            self.arrow:SetText("▼")
                        else
                            -- Collapse
                            CollapsedGroups[sk] = true
                            self.arrow:SetText("▶")
                        end

                        -- Refresh the content
                        local configFrame = ConfigFrame
                        if configFrame and configFrame.SoftRefresh then
                            configFrame:SoftRefresh()
                        end
                    end)
                end
            elseif option.type == "description" then
                widget = Widgets.CreateDescription(contentFrame, option, yOffset, options)
                widgetHeight = widget:GetHeight()
            elseif option.type == "group" and option.inline then
                local groupName = option.name or ""
                if type(groupName) == "function" then
                    groupName = groupName()
                end

                -- Generate unique key for collapse state
                local groupKey = table.concat(path or {}, ".") .. "." .. key
                local isCollapsed = CollapsedGroups[groupKey] ~= false

                -- ElvUI style group frame
                local groupFrame = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
                groupFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 5, -yOffset)
                groupFrame:SetPoint("RIGHT", contentFrame, "RIGHT", -5, 0)
                groupFrame:SetBackdrop({
                    bgFile = FLAT,
                    edgeFile = FLAT,
                    edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 }
                })
                groupFrame:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 1)
                groupFrame:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
                groupFrame._groupKey = groupKey

                -- Collapse/Expand arrow button
                local collapseBtn = CreateFrame("Button", nil, groupFrame)
                collapseBtn:SetSize(20, 20)
                collapseBtn:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", 4, -4)

                local collapseArrow = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                StyleFontString(collapseArrow)
                collapseArrow:SetPoint("CENTER", collapseBtn, "CENTER", 0, 0)
                collapseArrow:SetText(isCollapsed and "+" or "-")
                collapseArrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
                collapseBtn.arrow = collapseArrow

                collapseBtn:SetScript("OnEnter", function(self)
                    self.arrow:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                end)
                collapseBtn:SetScript("OnLeave", function(self)
                    self.arrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
                end)

                local groupTitle = groupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                StyleFontString(groupTitle)
                groupTitle:SetPoint("TOPLEFT", collapseBtn, "TOPRIGHT", 2, -3)
                groupTitle:SetText(groupName)
                -- Gold title for groups like ElvUI
                groupTitle:SetTextColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)

                -- Create content container for collapsible content
                local contentContainer = CreateFrame("Frame", nil, groupFrame)
                contentContainer:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", 0, -28)
                contentContainer:SetPoint("RIGHT", groupFrame, "RIGHT", 0, 0)
                groupFrame._contentContainer = contentContainer
                groupFrame._contentWidgets = {}

                local inlineYOffset = 0  -- Now relative to contentContainer
                local inlineSorted = {}
                for k, v in pairs(option.args or {}) do
                    table.insert(inlineSorted, {key = k, option = v, order = v.order or 999})
                end
                table.sort(inlineSorted, function(a, b) return a.order < b.order end)

                for _, inlineItem in ipairs(inlineSorted) do
                    -- Skip if hidden (not disabled - disabled shows but greyed out)
                    local inlineHidden = false
                    if inlineItem.option.hidden then
                        if type(inlineItem.option.hidden) == "function" then
                            inlineHidden = inlineItem.option.hidden()
                        else
                            inlineHidden = inlineItem.option.hidden
                        end
                    end
                    if not inlineHidden then
                        local inlineWidget = nil
                        local inlineHeight = 0

                        if inlineItem.option.type == "toggle" then
                            inlineWidget = Widgets.CreateToggle(contentContainer, inlineItem.option, inlineYOffset, options)
                            inlineHeight = 28
                        elseif inlineItem.option.type == "range" then
                            inlineWidget = Widgets.CreateRange(contentContainer, inlineItem.option, inlineYOffset, options)
                            inlineHeight = 32
                        elseif inlineItem.option.type == "select" then
                            -- Build path for info structure (for inline groups, path is just the key)
                            local inlinePath = {inlineItem.key}
                            inlineWidget = Widgets.CreateSelect(contentContainer, inlineItem.option, inlineYOffset, options, inlineItem.key, inlinePath)
                            inlineHeight = 36
                        elseif inlineItem.option.type == "color" then
                            inlineWidget = Widgets.CreateColor(contentContainer, inlineItem.option, inlineYOffset, options)
                            inlineHeight = 28
                        elseif inlineItem.option.type == "execute" then
                            inlineWidget = Widgets.CreateExecute(contentContainer, inlineItem.option, inlineYOffset)
                            inlineHeight = 28
                        elseif inlineItem.option.type == "input" then
                            inlineWidget = Widgets.CreateInput(contentContainer, inlineItem.option, inlineYOffset, options)
                            inlineHeight = inlineItem.option.multiline and 150 or 32
                        elseif inlineItem.option.type == "framepicker" then
                            inlineWidget = Widgets.CreateFramePicker(contentContainer, inlineItem.option, inlineYOffset, options)
                            inlineHeight = 32
                        elseif inlineItem.option.type == "header" then
                            inlineWidget = Widgets.CreateHeader(contentContainer, inlineItem.option, inlineYOffset)
                            inlineHeight = 32
                        elseif inlineItem.option.type == "description" then
                            inlineWidget = Widgets.CreateDescription(contentContainer, inlineItem.option, inlineYOffset, options)
                            inlineHeight = inlineWidget:GetHeight() + 5  -- Add extra spacing
                        elseif inlineItem.option.type == "group" and inlineItem.option.inline then
                            -- Nested inline group - render recursively
                            local nestedGroupName = inlineItem.option.name or ""
                            if type(nestedGroupName) == "function" then
                                nestedGroupName = nestedGroupName()
                            end

                            -- Create nested container frame
                            local nestedGroupFrame = CreateFrame("Frame", nil, contentContainer, "BackdropTemplate")
                            nestedGroupFrame:SetPoint("TOPLEFT", contentContainer, "TOPLEFT", 10, -inlineYOffset)
                            nestedGroupFrame:SetPoint("RIGHT", contentContainer, "RIGHT", -10, 0)
                            nestedGroupFrame:SetBackdrop({
                                bgFile = FLAT,
                                edgeFile = FLAT,
                                edgeSize = 1,
                                insets = { left = 1, right = 1, top = 1, bottom = 1 }
                            })
                            nestedGroupFrame:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 1)
                            nestedGroupFrame:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
                            
                            -- Nested group title
                            local nestedGroupTitle = nestedGroupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            StyleFontString(nestedGroupTitle)
                            nestedGroupTitle:SetPoint("TOPLEFT", nestedGroupFrame, "TOPLEFT", 10, -8)
                            nestedGroupTitle:SetText(nestedGroupName)
                            nestedGroupTitle:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                            
                            -- Render nested inline group options
                            local nestedYOffset = 35
                            local nestedSorted = {}
                            for k, v in pairs(inlineItem.option.args or {}) do
                                table.insert(nestedSorted, {key = k, option = v, order = v.order or 999})
                            end
                            table.sort(nestedSorted, function(a, b) return a.order < b.order end)
                            
                            for _, nestedItem in ipairs(nestedSorted) do
                                -- Skip if hidden
                                local nestedHidden = false
                                if nestedItem.option.hidden then
                                    if type(nestedItem.option.hidden) == "function" then
                                        nestedHidden = nestedItem.option.hidden()
                                    else
                                        nestedHidden = nestedItem.option.hidden
                                    end
                                end
                                if not nestedHidden then
                                    local nestedWidget = nil
                                    local nestedHeight = 0
                                    
                                    if nestedItem.option.type == "toggle" then
                                        nestedWidget = Widgets.CreateToggle(nestedGroupFrame, nestedItem.option, nestedYOffset, options)
                                        nestedHeight = 35
                                    elseif nestedItem.option.type == "range" then
                                        nestedWidget = Widgets.CreateRange(nestedGroupFrame, nestedItem.option, nestedYOffset, options)
                                        nestedHeight = 35
                                    elseif nestedItem.option.type == "select" then
                                        -- Build path for info structure (for nested groups, path is just the key)
                                        local nestedPath = {nestedItem.key}
                                        nestedWidget = Widgets.CreateSelect(nestedGroupFrame, nestedItem.option, nestedYOffset, options, nestedItem.key, nestedPath)
                                        nestedHeight = 40
                                    elseif nestedItem.option.type == "color" then
                                        nestedWidget = Widgets.CreateColor(nestedGroupFrame, nestedItem.option, nestedYOffset, options)
                                        nestedHeight = 35
                                    elseif nestedItem.option.type == "execute" then
                                        nestedWidget = Widgets.CreateExecute(nestedGroupFrame, nestedItem.option, nestedYOffset)
                                        nestedHeight = 32
                                    elseif nestedItem.option.type == "input" then
                                        nestedWidget = Widgets.CreateInput(nestedGroupFrame, nestedItem.option, nestedYOffset, options)
                                        nestedHeight = nestedItem.option.multiline and 150 or 35
                                    elseif nestedItem.option.type == "framepicker" then
                                        nestedWidget = Widgets.CreateFramePicker(nestedGroupFrame, nestedItem.option, nestedYOffset, options)
                                        nestedHeight = 32
                                    elseif nestedItem.option.type == "header" then
                                        nestedWidget = Widgets.CreateHeader(nestedGroupFrame, nestedItem.option, nestedYOffset)
                                        nestedHeight = 32
                                    elseif nestedItem.option.type == "description" then
                                        nestedWidget = Widgets.CreateDescription(nestedGroupFrame, nestedItem.option, nestedYOffset, options)
                                        nestedHeight = nestedWidget:GetHeight() + 5
                                    end
                                    
                                    if nestedWidget then
                                        nestedWidget:SetParent(nestedGroupFrame)
                                        nestedWidget:Show()
                                        table.insert(contentFrame.widgets, nestedWidget)
                                        nestedYOffset = nestedYOffset + nestedHeight + 15
                                    end
                                end
                            end
                            
                            nestedGroupFrame:SetHeight(nestedYOffset + 10)
                            nestedGroupFrame:Show()
                            table.insert(contentFrame.widgets, nestedGroupFrame)
                            inlineWidget = nestedGroupFrame
                            inlineHeight = nestedYOffset + 10
                        end
                        
                        if inlineWidget then
                            inlineWidget:SetParent(contentContainer)
                            inlineWidget:Show()
                            table.insert(groupFrame._contentWidgets, inlineWidget)
                            table.insert(contentFrame.widgets, inlineWidget)
                            inlineYOffset = inlineYOffset + inlineHeight + 18  -- Increased spacing from 12 to 18 for better separation
                        end
                    end
                end

                -- Store content height and set container size
                local contentHeight = inlineYOffset
                contentContainer:SetHeight(contentHeight)
                groupFrame._contentHeight = contentHeight
                groupFrame._collapsedHeight = 28  -- Header only

                -- Apply initial collapsed state
                if isCollapsed then
                    contentContainer:Hide()
                    groupFrame:SetHeight(groupFrame._collapsedHeight)
                else
                    contentContainer:Show()
                    groupFrame:SetHeight(contentHeight + 28 + 10)
                end

                -- Toggle collapse on button click
                collapseBtn:SetScript("OnClick", function(self)
                    local gf = self:GetParent()
                    local gKey = gf._groupKey
                    local cc = gf._contentContainer
                    local collapsed = CollapsedGroups[gKey] ~= false  -- nil or true = collapsed

                    if collapsed then
                        -- Expand
                        CollapsedGroups[gKey] = false
                        cc:Show()
                        gf:SetHeight(gf._contentHeight + 28 + 10)
                        self.arrow:SetText("-")
                    else
                        -- Collapse
                        CollapsedGroups[gKey] = true
                        cc:Hide()
                        gf:SetHeight(gf._collapsedHeight)
                        self.arrow:SetText("+")
                    end

                    -- Request parent to re-layout (refresh the whole content frame)
                    local configFrame = ConfigFrame
                    if configFrame and configFrame.SoftRefresh then
                        configFrame:SoftRefresh()
                    end
                end)

                -- Also make title clickable for toggle
                local titleBtn = CreateFrame("Button", nil, groupFrame)
                titleBtn:SetPoint("TOPLEFT", groupTitle, "TOPLEFT", -2, 2)
                titleBtn:SetPoint("BOTTOMRIGHT", groupTitle, "BOTTOMRIGHT", 2, -2)
                titleBtn:SetScript("OnClick", function()
                    collapseBtn:Click()
                end)
                titleBtn:SetScript("OnEnter", function()
                    collapseArrow:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                end)
                titleBtn:SetScript("OnLeave", function()
                    collapseArrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
                end)

                groupFrame:Show()
                table.insert(contentFrame.widgets, groupFrame)
                widgetHeight = isCollapsed and groupFrame._collapsedHeight or (contentHeight + 28 + 10)
            end
            
            if widget then
                widget:SetParent(contentFrame)

                -- If current section is collapsed and this is not a header, hide widget and skip height
                local isHeader = option.type == "header"
                if currentSectionCollapsed and not isHeader then
                    widget:Hide()
                    -- Add to section widgets for later show/hide
                    if currentSectionKey and sectionWidgets[currentSectionKey] then
                        table.insert(sectionWidgets[currentSectionKey], widget)
                    end
                    table.insert(contentFrame.widgets, widget)
                    -- Don't add to yOffset when collapsed
                else
                    widget:Show()
                    -- Add to section widgets for later show/hide
                    if currentSectionKey and sectionWidgets[currentSectionKey] and not isHeader then
                        table.insert(sectionWidgets[currentSectionKey], widget)
                    end
                    table.insert(contentFrame.widgets, widget)
                    yOffset = yOffset + widgetHeight + 15  -- Increased spacing from 10 to 15
                end
            end
        end
    end

    -- 루프 종료 후 남은 아이콘 행 처리
    EndIconRow()

    -- Update scroll frame
    -- Add extra bottom padding to ensure all content is accessible via scroll
    local bottomPadding = 50
    local totalHeight = yOffset + bottomPadding

    if contentFrame.scrollFrame then
        contentFrame.scrollFrame:SetScrollChild(contentFrame)
        contentFrame:SetHeight(totalHeight)
        -- Force scroll bar update
        if contentFrame.scrollFrame.ScrollBar and contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition then
            C_Timer.After(0.02, contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition)
        end
    elseif contentFrame:GetParent() and contentFrame:GetParent():GetObjectType() == "ScrollFrame" then
        -- If parent is a scroll frame, update height
        contentFrame:SetHeight(totalHeight)
    elseif yOffset > 0 then
        -- Fallback: always set height if we have content (for subScrollChild, etc.)
        contentFrame:SetHeight(totalHeight)
    end
end

-- ============================================
-- DanderS-style Search System
-- ============================================

-- Searchable control types
local SEARCHABLE_TYPES = {
    toggle = true, range = true, select = true, color = true,
    execute = true, input = true, framepicker = true,
}

-- Safely resolve option name/desc (can be string or function)
local function ResolveOptionText(val)
    if type(val) == "string" then return val end
    if type(val) == "function" then
        local ok, result = pcall(val)
        if ok and type(result) == "string" then return result end
    end
    return nil
end

-- Check if option is hidden
local function IsOptionHidden(opt)
    if not opt.hidden then return false end
    if type(opt.hidden) == "function" then
        local ok, result = pcall(opt.hidden)
        return ok and result
    end
    return opt.hidden == true
end

-- Build flat search index from entire options tree
local function BuildSearchIndex(options)
    local index = {}

    local function IndexGroup(group, breadcrumbParts, optionsTable, treeKey)
        if not group or not group.args then return end

        local sorted = {}
        for k, v in pairs(group.args) do
            table.insert(sorted, { key = k, option = v, order = v.order or 999 })
        end
        table.sort(sorted, function(a, b) return a.order < b.order end)

        for _, item in ipairs(sorted) do
            local opt = item.option
            if not IsOptionHidden(opt) then
                if opt.type == "group" then
                    local groupName = ResolveOptionText(opt.name) or item.key
                    if opt.inline then
                        -- Inline group: flatten into parent, keep same breadcrumb and optionsTable
                        IndexGroup(opt, breadcrumbParts, optionsTable, treeKey)
                    elseif opt.childGroups == "tab" then
                        -- Tab group: each child tab is a separate breadcrumb level
                        local newParts = {}
                        for _, p in ipairs(breadcrumbParts) do newParts[#newParts + 1] = p end
                        newParts[#newParts + 1] = groupName
                        for childKey, childOpt in pairs(opt.args or {}) do
                            if not IsOptionHidden(childOpt) and childOpt.type == "group" then
                                local childName = ResolveOptionText(childOpt.name) or childKey
                                local childParts = {}
                                for _, p in ipairs(newParts) do childParts[#childParts + 1] = p end
                                childParts[#childParts + 1] = childName
                                local childTreeKey = treeKey and (treeKey .. "." .. childKey) or childKey
                                IndexGroup(childOpt, childParts, childOpt, childTreeKey)
                            end
                        end
                    else
                        -- Regular sub-group: extend breadcrumb
                        local newParts = {}
                        for _, p in ipairs(breadcrumbParts) do newParts[#newParts + 1] = p end
                        newParts[#newParts + 1] = groupName
                        IndexGroup(opt, newParts, opt, treeKey)
                    end
                elseif SEARCHABLE_TYPES[opt.type] then
                    local name = ResolveOptionText(opt.name)
                    if name and name ~= "" then
                        local desc = ResolveOptionText(opt.desc)
                        local breadcrumb = table.concat(breadcrumbParts, "  >  ")
                        local pathKey = table.concat(breadcrumbParts, ".")
                        index[#index + 1] = {
                            name = name,
                            nameLower = name:lower(),
                            desc = desc,
                            descLower = desc and desc:lower() or nil,
                            type = opt.type,
                            option = opt,
                            optionsTable = optionsTable,
                            key = item.key,
                            breadcrumb = breadcrumb,
                            pathKey = pathKey,
                            treeKey = treeKey,
                        }
                    end
                end
            end
        end
    end

    -- Start from top-level groups
    local topSorted = {}
    for k, v in pairs(options.args or {}) do
        if v.type == "group" and not IsOptionHidden(v) then
            table.insert(topSorted, { key = k, option = v, order = v.order or 999 })
        end
    end
    table.sort(topSorted, function(a, b) return a.order < b.order end)

    for _, item in ipairs(topSorted) do
        local groupName = ResolveOptionText(item.option.name) or item.key
        if item.option.childGroups == "tab" then
            -- Tab parent: iterate children as separate tree entries
            local childSorted = {}
            for ck, cv in pairs(item.option.args or {}) do
                if not IsOptionHidden(cv) then
                    table.insert(childSorted, { key = ck, option = cv, order = cv.order or 999 })
                end
            end
            table.sort(childSorted, function(a, b) return a.order < b.order end)

            for _, child in ipairs(childSorted) do
                local childName = ResolveOptionText(child.option.name) or child.key
                local treeKey = item.key .. "." .. child.key
                if child.option.type == "group" then
                    IndexGroup(child.option, { groupName, childName }, child.option, treeKey)
                end
            end
        else
            -- Simple group
            IndexGroup(item.option, { groupName }, item.option, item.key)
        end
    end

    return index
end

-- Create breadcrumb badge widget
local function CreateBreadcrumbBadge(parent, breadcrumbText, yOffset, onClick)
    local badge = CreateFrame("Button", nil, parent, "BackdropTemplate")
    badge:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    badge:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
    badge:SetBackdropBorderColor(0, 0, 0, 1)

    local text = badge:CreateFontString(nil, "OVERLAY")
    text:SetFont(globalFontPath or "Fonts\\2002.TTF", 10, "")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetText(breadcrumbText)
    text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    text:SetPoint("LEFT", badge, "LEFT", 8, 0)
    badge.text = text

    -- Auto-size to text
    local textWidth = text:GetStringWidth() or 80
    badge:SetSize(textWidth + 16, 20)
    badge:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)

    -- Hover effect
    badge:SetScript("OnEnter", function(self)
        self.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.5)
    end)
    badge:SetScript("OnLeave", function(self)
        self.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)

    if onClick then
        badge:SetScript("OnClick", onClick)
    end

    return badge
end

-- Render search results in DanderS style
local function RenderSearchResults(contentFrame, results, parentFrame)
    -- Clean up existing widgets (same pattern as RenderOptions)
    if contentFrame.subScrollChild then
        if contentFrame.subScrollChild.widgets then
            for i = #contentFrame.subScrollChild.widgets, 1, -1 do
                local w = contentFrame.subScrollChild.widgets[i]
                if w then w:Hide(); w:SetParent(nil) end
            end
            contentFrame.subScrollChild.widgets = {}
        end
        contentFrame.subScrollChild = nil
    end
    if contentFrame.subTabContainer then
        contentFrame.subTabContainer:Hide()
        contentFrame.subTabContainer:SetParent(nil)
        contentFrame.subTabContainer = nil
    end
    if contentFrame.subContentArea then
        contentFrame.subContentArea:Hide()
        contentFrame.subContentArea:SetParent(nil)
        contentFrame.subContentArea = nil
    end
    if contentFrame.subTabButtons then
        for _, btn in ipairs(contentFrame.subTabButtons) do
            if btn then btn:Hide(); btn:SetParent(nil) end
        end
        contentFrame.subTabButtons = nil
    end
    if contentFrame.widgets then
        for i = #contentFrame.widgets, 1, -1 do
            local w = contentFrame.widgets[i]
            if w then w:Hide(); w:SetParent(nil) end
        end
    end
    contentFrame.widgets = {}

    local yOffset = 15

    -- Header: "검색 결과 (N개 발견)"
    local headerFrame = CreateFrame("Frame", nil, contentFrame)
    headerFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -yOffset)
    headerFrame:SetPoint("RIGHT", contentFrame, "RIGHT", -10, 0)
    headerFrame:SetHeight(28)
    table.insert(contentFrame.widgets, headerFrame)

    local headerText = headerFrame:CreateFontString(nil, "OVERLAY")
    headerText:SetFont(globalFontPath or "Fonts\\2002.TTF", 14, "")
    headerText:SetShadowOffset(1, -1)
    headerText:SetShadowColor(0, 0, 0, 1)
    headerText:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 0, 0)

    if #results > 0 then
        -- Apply gradient text for "검색 결과"
        local titlePart = CreateGradientText and CreateGradientText(L["Search Results"] or "검색 결과") or (L["Search Results"] or "검색 결과")
        headerText:SetText(titlePart .. "  |cff999999(" .. #results .. "개 발견)|r")
    else
        headerText:SetText("|cff999999" .. (L["No search results"] or "검색 결과 없음") .. "|r")
    end

    -- Underline (gradient fade like UF header style)
    local underline = headerFrame:CreateTexture(nil, "ARTWORK")
    underline:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -4)
    underline:SetPoint("RIGHT", headerFrame, "RIGHT", 0, 0)
    underline:SetHeight(1)
    underline:SetColorTexture(1, 1, 1, 1)
    underline:SetGradient("HORIZONTAL",
        CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6),
        CreateColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.15)
    )

    -- Shadow line below
    local shadowLine = headerFrame:CreateTexture(nil, "ARTWORK", nil, -1)
    shadowLine:SetPoint("TOPLEFT", underline, "BOTTOMLEFT", 0, -1)
    shadowLine:SetPoint("RIGHT", underline, "RIGHT", 0, 0)
    shadowLine:SetHeight(1)
    shadowLine:SetColorTexture(0, 0, 0, 0.4)

    yOffset = yOffset + 36

    if #results == 0 then
        contentFrame:SetHeight(yOffset + 50)
        return
    end

    -- Group results by pathKey (preserving order)
    local groups = {}
    local groupOrder = {}
    for _, entry in ipairs(results) do
        if not groups[entry.pathKey] then
            groups[entry.pathKey] = {
                breadcrumb = entry.breadcrumb,
                treeKey = entry.treeKey,
                items = {},
            }
            groupOrder[#groupOrder + 1] = entry.pathKey
        end
        table.insert(groups[entry.pathKey].items, entry)
    end

    -- Render each group
    for _, pathKey in ipairs(groupOrder) do
        local group = groups[pathKey]

        -- Breadcrumb badge
        local badge = CreateBreadcrumbBadge(contentFrame, group.breadcrumb, yOffset, function()
            if not parentFrame then return end

            -- 1) 검색 모드 플래그 먼저 해제 (ClearSearch가 이전 탭으로 돌아가는 것 방지)
            parentFrame._searchMode = false
            parentFrame._preSearchTab = nil
            parentFrame._preSearchPath = nil

            -- 2) 검색 박스 비우기 (OnTextChanged → FilterTree("") 실행 → 트리 메뉴 복원)
            if parentFrame.searchEditBox then
                parentFrame.searchEditBox:SetText("")
                parentFrame.searchEditBox:ClearFocus()
            end

            -- 3) 해당 트리 메뉴 항목으로 직접 이동
            if group.treeKey and parentFrame._optionLookup then
                local lookup = parentFrame._optionLookup[group.treeKey]
                if lookup then
                    if parentFrame.treeMenu then
                        parentFrame.treeMenu:SetSelected(group.treeKey)
                    end
                    parentFrame:SetContent(lookup.option, lookup.path)
                    parentFrame.currentTab = group.treeKey
                    parentFrame.currentPath = lookup.path
                end
            end
        end)
        table.insert(contentFrame.widgets, badge)
        yOffset = yOffset + 24

        -- Render each control in this group
        for _, entry in ipairs(group.items) do
            local widget = nil
            local widgetHeight = 0

            if entry.type == "toggle" then
                widget = Widgets.CreateToggle(contentFrame, entry.option, yOffset, entry.optionsTable)
                widgetHeight = 28
            elseif entry.type == "range" then
                widget = Widgets.CreateRange(contentFrame, entry.option, yOffset, entry.optionsTable)
                widgetHeight = 32
            elseif entry.type == "select" then
                widget = Widgets.CreateSelect(contentFrame, entry.option, yOffset, entry.optionsTable, entry.key, {})
                widgetHeight = 36
            elseif entry.type == "color" then
                widget = Widgets.CreateColor(contentFrame, entry.option, yOffset, entry.optionsTable)
                widgetHeight = 28
            elseif entry.type == "execute" then
                widget = Widgets.CreateExecute(contentFrame, entry.option, yOffset)
                widgetHeight = 28
            elseif entry.type == "input" then
                widget = Widgets.CreateInput(contentFrame, entry.option, yOffset, entry.optionsTable)
                widgetHeight = entry.option.multiline and 150 or 32
            elseif entry.type == "framepicker" then
                widget = Widgets.CreateFramePicker(contentFrame, entry.option, yOffset, entry.optionsTable)
                widgetHeight = 32
            end

            if widget then
                table.insert(contentFrame.widgets, widget)
                yOffset = yOffset + widgetHeight + 12
            end
        end

        -- Extra spacing between groups
        yOffset = yOffset + 8
    end

    -- Update scroll height
    local totalHeight = yOffset + 50
    contentFrame:SetHeight(totalHeight)

    if contentFrame.scrollFrame then
        contentFrame.scrollFrame:SetScrollChild(contentFrame)
        if contentFrame.scrollFrame.ScrollBar and contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition then
            C_Timer.After(0.02, contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition)
        end
    end
end

-- Create main config frame (StyleLib tree-menu layout)
function DDingUI:CreateConfigFrame()
    -- Always destroy and recreate the frame to ensure we have latest version
    if ConfigFrame then
        ConfigFrame:Hide()
        ConfigFrame:ClearAllPoints()
        local children = {ConfigFrame:GetChildren()}
        for _, child in ipairs(children) do
            child:SetParent(nil)
            child:Hide()
        end
        ConfigFrame:SetParent(nil)
        ConfigFrame = nil
    end

    -- Also clear global references
    for _, gName in ipairs({"DDingUI_ConfigFrame", "DDingUI_CDM_Panel"}) do
        local gf = _G[gName]
        if gf then
            gf:Hide()
            gf:ClearAllPoints()
            local children = {gf:GetChildren()}
            for _, child in ipairs(children) do
                child:SetParent(nil)
                child:Hide()
            end
            gf:SetParent(nil)
            _G[gName] = nil
        end
    end

    -- ============================================
    -- StyleLib 패널 뼈대 생성
    -- ============================================
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "1.0"

    local panel = SL.CreateSettingsPanel("CDM", "DDingUI CDM", version, {
        width = 920,
        height = 620,
        minWidth = 600,
        minHeight = 400,
        menuWidth = 200,
    })

    local frame = panel.frame
    local titleBar = panel.titleBar
    local treeFrame = panel.treeFrame
    local contentScroll = panel.contentScroll
    local contentChild = panel.contentChild

    -- Backward-compat global reference
    _G["DDingUI_ConfigFrame"] = frame

    frame:SetFrameLevel(100)

    -- UF 통일: 프레임 테두리를 솔리드 블랙으로 오버라이드
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- GUI 스케일 적용 (저장된 값)
    local savedScale = (DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.general and DDingUI.db.profile.general.guiScale) or 1.0
    frame:SetScale(savedScale)

    -- 프레임 닫힐 때 버프 트래커 미리보기 모드 종료 + CooldownViewerSettings 닫기
    frame:SetScript("OnHide", function()
        if DDingUI.DisableBuffTrackerPreview then
            DDingUI:DisableBuffTrackerPreview()
        end
        -- [12.0.1] cooldownViewerEnabled CVar는 복원하지 않음
        -- DDingUI CDM 기능 사용 시 CDM이 항상 활성화되어야 스캔/추적이 정상 작동
        -- CVar를 "0"으로 되돌리면 viewer 자식 프레임이 소멸 → 재열기 시 스캔 0개 반환
        DDingUI._cdmPrevCooldownViewerEnabled = nil
        -- [12.0.1] 고급 재사용 대기시간 관리자(CooldownViewerSettings) 같이 닫기
        local cdmSettings = _G["CooldownViewerSettings"]
        if cdmSettings and cdmSettings:IsShown() then
            cdmSettings:Hide()
        end
    end)

    -- UF 통일: 수직 그라데이션 제거 → 플랫 배경 (StyleLib ApplyBackdrop이 이미 적용)

    -- ============================================
    -- 타이틀바 커스터마이징 (UF 통일 레이아웃)
    -- Title + Version + Profile dropdown + Search + Close
    -- ============================================
    globalFontPath = DDingUI:GetGlobalFont() or SL.Font.path

    -- 타이틀 텍스트 (UF 통일: 글자별 그라디언트)
    if titleBar.titleText then
        titleBar.titleText:SetText(CreateGradientText("DDingUI CDM"))
    end

    local closeBtn = titleBar.closeBtn

    -- ============================================
    -- 프로필 드롭다운 (UF 통일: 타이틀바에 배치)
    -- ============================================
    local profileDropdown = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    profileDropdown:SetSize(140, 20)
    profileDropdown:SetPoint("LEFT", titleBar.verText or titleBar.titleText, "RIGHT", 14, 0)
    CreateBackdrop(profileDropdown, THEME.bgWidget, {0, 0, 0, 1})  -- UF 통일: 솔리드 블랙

    local profileText = profileDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileText:SetFont(globalFontPath, 11, "")
    profileText:SetShadowColor(0, 0, 0, 1)
    profileText:SetShadowOffset(1, -1)
    profileText:SetPoint("LEFT", 6, 0)
    profileText:SetPoint("RIGHT", -20, 0)
    profileText:SetJustifyH("LEFT")
    profileText:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)

    local profileArrow = profileDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileArrow:SetFont(globalFontPath, 10, "")
    profileArrow:SetPoint("RIGHT", -4, 0)
    profileArrow:SetText("▼")
    profileArrow:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)

    -- 현재 프로필 이름 표시
    local function UpdateProfileText()
        local currentProfile = DDingUI.db:GetCurrentProfile()
        profileText:SetText(currentProfile or "Default")
    end
    UpdateProfileText()

    -- 프로필 드롭다운 호버
    profileDropdown:EnableMouse(true)
    profileDropdown:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    end)
    profileDropdown:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
    end)

    -- 프로필 드롭다운 클릭 → 프로필 목록 팝업
    profileDropdown:SetScript("OnMouseDown", function(self)
        -- 기존 리스트 닫기
        if self._listFrame and self._listFrame:IsShown() then
            self._listFrame:Hide()
            return
        end

        local profiles = DDingUI.db:GetProfiles()
        local currentProfile = DDingUI.db:GetCurrentProfile()

        local listFrame = self._listFrame
        if not listFrame then
            listFrame = CreateFrame("Frame", nil, self, "BackdropTemplate")
            listFrame:SetFrameStrata("TOOLTIP")
            CreateBackdrop(listFrame, THEME.bgDark, {0, 0, 0, 1})  -- UF 통일
            self._listFrame = listFrame
        end

        -- 기존 아이템 제거
        if listFrame._items then
            for _, item in ipairs(listFrame._items) do
                item:Hide()
                item:SetParent(nil)
            end
        end
        listFrame._items = {}

        local itemHeight = 20
        local y = -2
        for _, name in ipairs(profiles) do
            local item = CreateFrame("Button", nil, listFrame, "BackdropTemplate")
            item:SetHeight(itemHeight)
            item:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, y)
            item:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, y)
            item:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "",
                edgeSize = 0,
            })
            item:SetBackdropColor(0, 0, 0, 0)

            local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemText:SetFont(globalFontPath, 11, "")
            itemText:SetShadowColor(0, 0, 0, 1)
            itemText:SetShadowOffset(1, -1)
            itemText:SetPoint("LEFT", 6, 0)
            itemText:SetText(name)
            if name == currentProfile then
                itemText:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            else
                itemText:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
            end

            item:SetScript("OnEnter", function(self)
                self:SetBackdropColor(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], THEME.bgHover[4])
            end)
            item:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0, 0, 0, 0)
            end)
            item:SetScript("OnClick", function()
                DDingUI.db:SetProfile(name)
                UpdateProfileText()
                listFrame:Hide()
                -- soft refresh 현재 콘텐츠
                if frame.SoftRefresh then
                    C_Timer.After(0.05, function() frame:SoftRefresh() end)
                end
            end)

            table.insert(listFrame._items, item)
            y = y - itemHeight
        end

        listFrame:SetSize(140, math.abs(y) + 4)
        listFrame:ClearAllPoints()
        listFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        listFrame:Show()

        -- 외부 클릭 시 닫기
        listFrame:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() and not profileDropdown:IsMouseOver() then
                if IsMouseButtonDown("LeftButton") then
                    self:Hide()
                end
            end
        end)
    end)

    frame.profileDropdown = profileDropdown

    -- ============================================
    -- GUI 크기 슬라이더 (타이틀바 내 검색 왼쪽)
    -- ============================================
    local scaleContainer = CreateFrame("Frame", nil, titleBar)
    scaleContainer:SetSize(140, 24)

    local scaleLabel = scaleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleLabel:SetFont(globalFontPath, 11, "")
    scaleLabel:SetShadowColor(0, 0, 0, 1)
    scaleLabel:SetShadowOffset(1, -1)
    scaleLabel:SetPoint("LEFT", scaleContainer, "LEFT", 0, 0)
    scaleLabel:SetText(L["Scale"] or "Scale")
    scaleLabel:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)

    local currentScale = (DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.general and DDingUI.db.profile.general.guiScale) or 1.0
    local scaleValue = scaleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleValue:SetFont(globalFontPath, 11, "")
    scaleValue:SetShadowColor(0, 0, 0, 1)
    scaleValue:SetShadowOffset(1, -1)
    scaleValue:SetPoint("RIGHT", scaleContainer, "RIGHT", 0, 0)
    scaleValue:SetText(string.format("%.0f%%", currentScale * 100))
    scaleValue:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)

    local scaleSlider = CreateFrame("Slider", nil, scaleContainer, "BackdropTemplate")
    scaleSlider:SetSize(70, 12)
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", 6, 0)
    scaleSlider:SetPoint("RIGHT", scaleValue, "LEFT", -6, 0)
    scaleSlider:SetOrientation("HORIZONTAL")
    scaleSlider:SetMinMaxValues(0.5, 1.5)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetValue(currentScale)

    scaleSlider:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
    })
    scaleSlider:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 1)
    scaleSlider:SetBackdropBorderColor(0, 0, 0, 1)

    local scaleThumb = scaleSlider:CreateTexture(nil, "OVERLAY")
    scaleThumb:SetSize(10, 16)
    scaleThumb:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    scaleSlider:SetThumbTexture(scaleThumb)

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20
        scaleValue:SetText(string.format("%.0f%%", value * 100))
        self._pendingValue = value
    end)

    scaleSlider:SetScript("OnMouseUp", function(self)
        local value = self._pendingValue or self:GetValue()
        value = math.floor(value * 20 + 0.5) / 20
        if DDingUI.db and DDingUI.db.profile then
            if not DDingUI.db.profile.general then DDingUI.db.profile.general = {} end
            DDingUI.db.profile.general.guiScale = value
        end
        frame:SetScale(value)
    end)

    scaleSlider:EnableMouseWheel(true)
    scaleSlider:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetValue()
        local step = 0.05
        local newValue
        if delta > 0 then
            newValue = math.min(1.5, current + step)
        else
            newValue = math.max(0.5, current - step)
        end
        self:SetValue(newValue)
        newValue = math.floor(newValue * 20 + 0.5) / 20
        if DDingUI.db and DDingUI.db.profile then
            if not DDingUI.db.profile.general then DDingUI.db.profile.general = {} end
            DDingUI.db.profile.general.guiScale = newValue
        end
        frame:SetScale(newValue)
    end)

    scaleSlider:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
        GameTooltip:SetText(L["GUI Scale"] or "GUI Scale", 1, 1, 1)
        GameTooltip:AddLine(L["Adjust the size of this settings window"] or "Adjust the size of this settings window", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    scaleSlider:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        GameTooltip:Hide()
    end)

    -- ============================================
    -- 검색 입력칸 (UF 통일: 200px, 닫기 버튼 왼쪽)
    -- ============================================
    local searchBox = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    searchBox:SetSize(200, 24)
    searchBox:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)

    -- 크기 슬라이더를 검색 왼쪽에 배치
    scaleContainer:SetPoint("RIGHT", searchBox, "LEFT", -12, 0)
    CreateBackdrop(searchBox, THEME.bgWidget, {0, 0, 0, 1})  -- UF 통일

    -- 돋보기 아이콘
    local searchIcon = searchBox:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 6, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.6, 0.6, 0.6)

    -- 검색 EditBox
    local searchEditBox = CreateFrame("EditBox", nil, searchBox)
    searchEditBox:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
    searchEditBox:SetPoint("RIGHT", -24, 0)
    searchEditBox:SetHeight(20)
    searchEditBox:SetFont(globalFontPath, 11, "")
    searchEditBox:SetAutoFocus(false)
    searchEditBox:SetJustifyH("LEFT")
    searchEditBox:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)

    -- 플레이스홀더
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchPlaceholder:SetFont(globalFontPath, 11, "")
    searchPlaceholder:SetText(L["Search..."] or "검색...")
    searchPlaceholder:SetTextColor(0.5, 0.5, 0.5)
    searchPlaceholder:SetPoint("LEFT", searchEditBox, "LEFT", 0, 0)
    searchPlaceholder:SetJustifyH("LEFT")

    -- 클리어 버튼
    local searchClearBtn = CreateFrame("Button", nil, searchBox)
    searchClearBtn:SetSize(16, 16)
    searchClearBtn:SetPoint("RIGHT", -4, 0)
    searchClearBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    searchClearBtn:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
    searchClearBtn:Hide()

    searchClearBtn:SetScript("OnEnter", function(self)
        self:GetNormalTexture():SetVertexColor(1, 0.2, 0.2)
    end)
    searchClearBtn:SetScript("OnLeave", function(self)
        self:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
    end)
    searchClearBtn:SetScript("OnClick", function()
        searchEditBox:SetText("")
        searchEditBox:ClearFocus()
    end)

    local searchDebounceTimer = nil
    searchEditBox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        searchPlaceholder:SetShown(text == "")
        searchClearBtn:SetShown(text ~= "")
        -- 트리 메뉴 필터링 (즉시)
        if frame.FilterTree then
            frame:FilterTree(text)
        end
        -- 디바운스 타이머 취소
        if searchDebounceTimer then
            searchDebounceTimer:Cancel()
            searchDebounceTimer = nil
        end
        if text == "" then
            -- 검색 해제 (즉시)
            if frame.ClearSearch then
                frame:ClearSearch()
            end
        else
            -- 검색 결과 렌더링 (0.2초 디바운스)
            searchDebounceTimer = C_Timer.NewTimer(0.2, function()
                if frame.PerformSearch then
                    frame:PerformSearch(text)
                end
            end)
        end
    end)
    searchEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    frame.searchBox = searchBox
    frame.searchEditBox = searchEditBox

    -- ============================================
    -- Center line for anchor mode
    -- ============================================
    local centerLine = CreateFrame("Frame", "DDingUI_CenterLine", UIParent, "BackdropTemplate")
    centerLine:SetWidth(2)
    centerLine:SetPoint("TOP", UIParent, "TOP", 0, 0)
    centerLine:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    centerLine:SetFrameStrata("HIGH")
    centerLine:SetFrameLevel(1000)
    centerLine:Hide()
    centerLine:SetBackdrop({
        bgFile = FLAT,
        tile = false,
    })
    centerLine:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)

    function DDingUI.UpdateCenterLine()
        local cl = _G["DDingUI_CenterLine"]
        if not cl then return end
        local unitFramesAnchorsEnabled = DDingUI.db.profile.unitFrames and
                                         DDingUI.db.profile.unitFrames.General and
                                         DDingUI.db.profile.unitFrames.General.ShowEditModeAnchors
        if unitFramesAnchorsEnabled then
            cl:Show()
            cl:ClearAllPoints()
            cl:SetPoint("TOP", UIParent, "TOP", 0, 0)
            cl:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
        else
            cl:Hide()
        end
    end

    -- ============================================
    -- 콘텐츠 영역: 커스텀 스크롤바 추가
    -- ============================================
    local contentFrame = contentScroll:GetParent()

    -- contentScroll 위치 조정 (스크롤바 공간 확보)
    contentScroll:ClearAllPoints()
    contentScroll:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    contentScroll:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -14, 4)

    -- 커스텀 스크롤바
    local scrollBar = CreateCustomScrollBar(contentFrame, contentScroll)
    scrollBar:SetPoint("TOPLEFT", contentScroll, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", contentScroll, "BOTTOMRIGHT", 4, 0)
    contentScroll.ScrollBar = scrollBar

    -- scrollChild 설정
    contentChild.widgets = {}
    contentChild.scrollFrame = contentScroll

    -- scrollChild 높이 변경 시 스크롤바 업데이트
    contentChild:SetScript("OnSizeChanged", function(self)
        local function updateScrollState()
            local currentScroll = contentScroll:GetVerticalScroll()
            local maxScroll = GetSafeScrollRange(contentScroll)
            if currentScroll > maxScroll then
                contentScroll:SetVerticalScroll(math.max(0, maxScroll))
            end
            if scrollBar.UpdateThumbPosition then
                scrollBar.UpdateThumbPosition()
            end
        end
        C_Timer.After(0.01, updateScrollState)
        C_Timer.After(0.05, updateScrollState)
        C_Timer.After(0.1, updateScrollState)
    end)

    -- ============================================
    -- Store references
    -- ============================================
    frame.titleBar = titleBar
    frame.treeFrame = treeFrame
    frame.contentArea = contentFrame
    frame.scrollFrame = contentScroll
    frame.scrollChild = contentChild
    frame.scrollBar = scrollBar
    frame.currentTab = nil      -- 현재 선택된 트리 키
    frame.currentPath = {}
    frame._optionLookup = {}    -- key → {option, path}

    -- ============================================
    -- Methods
    -- ============================================
    frame.SetContent = function(self, options, path)
        -- Clear scroll position
        self.scrollFrame:SetVerticalScroll(0)

        -- scrollChild 높이 초기화 및 너비 동기화
        if self.scrollChild then
            self.scrollChild:SetHeight(1)
            local sfWidth = self.scrollFrame:GetWidth()
            if sfWidth and sfWidth > 0 then
                self.scrollChild:SetWidth(sfWidth - 1)
            end
        end

        RenderOptions(self.scrollChild, options, path, self)

        -- 비동기 렌더링 대응: 지연된 스크롤바 업데이트
        local function DelayedUpdate()
            if self.scrollFrame then
                self.scrollFrame:SetVerticalScroll(0)
            end
            if self.scrollFrame and self.scrollFrame.ScrollBar and self.scrollFrame.ScrollBar.UpdateThumbPosition then
                self.scrollFrame.ScrollBar.UpdateThumbPosition()
            end
        end
        DelayedUpdate()
        C_Timer.After(0.02, DelayedUpdate)
        C_Timer.After(0.05, DelayedUpdate)
        C_Timer.After(0.1, DelayedUpdate)
        C_Timer.After(0.3, DelayedUpdate)
    end

    -- Refresh method
    frame.Refresh = function(self)
        if self.scrollChild and self.scrollChild.widgets then
            for _, widget in ipairs(self.scrollChild.widgets) do
                if widget.Refresh then
                    widget:Refresh()
                end
            end
        end
    end

    -- Soft refresh (preserves scroll position, restores sub-tab)
    frame.SoftRefresh = function(self)
        -- 검색 모드이면 검색 결과 다시 렌더링
        if self._searchMode and self.searchEditBox then
            local text = self.searchEditBox:GetText() or ""
            if text ~= "" then
                self:PerformSearch(text)
                return
            end
        end

        if not self.currentTab then return end

        local scrollPos = self.scrollFrame:GetVerticalScroll()

        if DDingUI and DDingUI.configOptions then
            self.configOptions = DDingUI.configOptions
        end
        if not self.configOptions then return end

        -- Get option data for current tree selection
        local lookup = self._optionLookup[self.currentTab]
        if not lookup then return end

        local currentOption = lookup.option
        local currentPath = lookup.path

        -- Store active sub-tab
        local activeSubTabKey = nil
        if self.scrollChild and self.scrollChild.subTabButtons then
            if currentOption and currentOption.args then
                local sortedTabs = {}
                for key, option in pairs(currentOption.args) do
                    if option.type == "group" or (option.type ~= "group" and option.type ~= "header" and option.type ~= "description") then
                        table.insert(sortedTabs, {key = key, option = option, order = option.order or 999})
                    end
                end
                table.sort(sortedTabs, function(a, b) return a.order < b.order end)
                for i, btn in ipairs(self.scrollChild.subTabButtons) do
                    if btn.active and sortedTabs[i] then
                        activeSubTabKey = sortedTabs[i].key
                        break
                    end
                end
            end
        end

        -- Re-render
        RenderOptions(self.scrollChild, currentOption, currentPath, self)

        -- Restore sub-tab
        if activeSubTabKey and self.scrollChild.subTabButtons then
            if currentOption and currentOption.args then
                local sortedTabs = {}
                for key, option in pairs(currentOption.args) do
                    if option.type == "group" or (option.type ~= "group" and option.type ~= "header" and option.type ~= "description") then
                        table.insert(sortedTabs, {key = key, option = option, order = option.order or 999})
                    end
                end
                table.sort(sortedTabs, function(a, b) return a.order < b.order end)
                for i, item in ipairs(sortedTabs) do
                    if item.key == activeSubTabKey and self.scrollChild.subTabButtons[i] then
                        self.scrollChild.subTabButtons[i]:Click()
                        break
                    end
                end
            end
        end

        -- Restore scroll position
        local function updateScrollState()
            if self.scrollFrame then
                local contentHeight = self.scrollChild and self.scrollChild:GetHeight() or 0
                local frameHeight = self.scrollFrame:GetHeight() or 0
                local maxScroll = math.max(0, contentHeight - frameHeight)
                local clampedPos = math.max(0, math.min(scrollPos, maxScroll))
                self.scrollFrame:SetVerticalScroll(clampedPos)
                if self.scrollFrame.ScrollBar and self.scrollFrame.ScrollBar.UpdateThumbPosition then
                    self.scrollFrame.ScrollBar.UpdateThumbPosition()
                end
            end
        end
        C_Timer.After(0.01, updateScrollState)
        C_Timer.After(0.05, updateScrollState)
        C_Timer.After(0.1, updateScrollState)
    end

    -- Full refresh (resets scroll, restores sub-tab)
    frame.FullRefresh = function(self)
        if not self.currentTab then return end

        if DDingUI and DDingUI.configOptions then
            self.configOptions = DDingUI.configOptions
        end
        if not self.configOptions then return end

        local lookup = self._optionLookup[self.currentTab]
        if not lookup then return end

        -- Store active sub-tab
        local activeSubTabKey = nil
        if self.scrollChild and self.scrollChild.subTabButtons then
            local currentOption = lookup.option
            if currentOption and currentOption.args then
                local sortedTabs = {}
                for key, option in pairs(currentOption.args) do
                    if option.type == "group" or (option.type ~= "group" and option.type ~= "header" and option.type ~= "description") then
                        table.insert(sortedTabs, {key = key, option = option, order = option.order or 999})
                    end
                end
                table.sort(sortedTabs, function(a, b) return a.order < b.order end)
                for i, btn in ipairs(self.scrollChild.subTabButtons) do
                    if btn.active and sortedTabs[i] then
                        activeSubTabKey = sortedTabs[i].key
                        break
                    end
                end
            end
        end

        self:SetContent(lookup.option, lookup.path)

        -- Restore sub-tab
        if activeSubTabKey then
            C_Timer.After(0.01, function()
                if not self.scrollChild or not self.scrollChild.subTabButtons then return end
                local currentOption = lookup.option
                if not currentOption or not currentOption.args then return end

                local sortedTabs = {}
                for key, option in pairs(currentOption.args) do
                    if option.type == "group" or (option.type ~= "group" and option.type ~= "header" and option.type ~= "description") then
                        table.insert(sortedTabs, {key = key, option = option, order = option.order or 999})
                    end
                end
                table.sort(sortedTabs, function(a, b) return a.order < b.order end)

                for i, item in ipairs(sortedTabs) do
                    if item.key == activeSubTabKey and self.scrollChild.subTabButtons[i] then
                        for _, btn in ipairs(self.scrollChild.subTabButtons) do
                            btn:SetActive(false)
                        end
                        self.scrollChild.subTabButtons[i]:SetActive(true)
                        local subScrollChild = self.scrollChild.subScrollChild
                        if subScrollChild then
                            if subScrollChild.widgets then
                                for j = #subScrollChild.widgets, 1, -1 do
                                    local widget = subScrollChild.widgets[j]
                                    if widget then widget:Hide(); widget:SetParent(nil) end
                                end
                            end
                            subScrollChild.widgets = {}
                            RenderOptions(subScrollChild, item.option, {unpack(lookup.path), item.key}, self)
                        end
                        break
                    end
                end
            end)
        end
    end

    ConfigFrame = frame
    return frame
end

-- ============================================
-- Open config with tree-menu navigation
-- ============================================
function DDingUI:OpenConfigGUI(options, tabKey)
    local frame = self:CreateConfigFrame()

    if not options then
        if self.configOptions then
            options = self.configOptions
        elseif DDingUI and DDingUI.configOptions then
            options = DDingUI.configOptions
        end
    end

    if not options then
        frame:Show()
        frame:Raise()
        return
    end

    -- ============================================
    -- Build tree menu data from AceConfig options
    -- ============================================
    local menuData = {}
    frame._optionLookup = {}

    local sortedGroups = {}
    for key, option in pairs(options.args or {}) do
        if option.type == "group" then
            local isHidden = false
            if option.hidden then
                isHidden = type(option.hidden) == "function" and option.hidden() or option.hidden
            end
            if not isHidden then
                table.insert(sortedGroups, {key = key, option = option, order = option.order or 999})
            end
        end
    end
    table.sort(sortedGroups, function(a, b) return a.order < b.order end)

    for _, item in ipairs(sortedGroups) do
        local displayName = item.option.name or item.key
        if type(displayName) == "function" then displayName = displayName() end

        if item.option.childGroups == "tab" then
            -- 이 그룹의 하위 항목들을 트리 자식으로 변환
            local children = {}
            local sortedChildren = {}
            for childKey, childOption in pairs(item.option.args or {}) do
                local childHidden = false
                if childOption.hidden then
                    childHidden = type(childOption.hidden) == "function" and childOption.hidden() or childOption.hidden
                end
                if not childHidden then
                    table.insert(sortedChildren, {key = childKey, option = childOption, order = childOption.order or 999})
                end
            end
            table.sort(sortedChildren, function(a, b) return a.order < b.order end)

            for _, child in ipairs(sortedChildren) do
                local childName = child.option.name or child.key
                if type(childName) == "function" then childName = childName() end
                local childTreeKey = item.key .. "." .. child.key

                table.insert(children, {
                    text = childName,
                    key = childTreeKey,
                })
                frame._optionLookup[childTreeKey] = {
                    option = child.option,
                    path = {item.key, child.key},
                }
            end

            -- 부모 키 → 첫 번째 자식으로 매핑
            if #children > 0 then
                frame._optionLookup[item.key] = frame._optionLookup[children[1].key]
            end

            table.insert(menuData, {
                text = displayName,
                key = item.key,
                children = children,
            })
        else
            -- 단순 그룹 → 리프 노드
            table.insert(menuData, {
                text = displayName,
                key = item.key,
            })
            frame._optionLookup[item.key] = {
                option = item.option,
                path = {item.key},
            }
        end
    end

    -- ============================================
    -- 기본 선택 키 결정
    -- ============================================
    local defaultKey = nil
    if tabKey then
        -- 정확히 일치하는 키 확인
        if frame._optionLookup[tabKey] then
            defaultKey = tabKey
        end
        -- 부모 키이면 첫 번째 자식 선택
        for _, item in ipairs(menuData) do
            if item.key == tabKey and item.children and #item.children > 0 then
                defaultKey = item.children[1].key
                break
            end
        end
    end
    if not defaultKey and #menuData > 0 then
        if menuData[1].children and #menuData[1].children > 0 then
            defaultKey = menuData[1].children[1].key
        else
            defaultKey = menuData[1].key
        end
    end

    -- ============================================
    -- 트리 메뉴 생성
    -- ============================================
    local tree = SL.CreateTreeMenu(frame.treeFrame, "CDM", menuData, {
        defaultKey = defaultKey,
        onSelect = function(key)
            -- 검색 모드에서 트리 메뉴 클릭 시 → 검색 해제 후 해당 페이지 이동
            if frame._searchMode then
                frame._searchMode = false
                frame._preSearchTab = nil
                frame._preSearchPath = nil
                if frame.searchEditBox then
                    frame.searchEditBox:SetText("")
                    frame.searchEditBox:ClearFocus()
                end
            end

            -- 버프 트래커 미리보기 정리
            if frame.currentTab and frame.currentTab:match("^buffTracker") and not key:match("^buffTracker") then
                if DDingUI.DisableBuffTrackerPreview then
                    DDingUI:DisableBuffTrackerPreview()
                end
            end

            local lookup = frame._optionLookup[key]
            if not lookup then
                -- 부모 노드 클릭 → 첫 번째 자식 선택
                for _, item in ipairs(menuData) do
                    if item.key == key and item.children and #item.children > 0 then
                        tree:SetSelected(item.children[1].key)
                        return
                    end
                end
                return
            end

            frame:SetContent(lookup.option, lookup.path)
            frame.currentTab = key
            frame.currentPath = lookup.path
            frame.configOptions = options
        end,
    })
    frame.treeMenu = tree
    frame._fullMenuData = menuData

    -- ============================================
    -- 트리 메뉴 검색 필터 (애드온 내장)
    -- ============================================
    local function OptionContainsText(key, query)
        local lookup = frame._optionLookup[key]
        if not lookup or not lookup.option or not lookup.option.args then return false end
        for _, arg in pairs(lookup.option.args) do
            local name = arg.name
            if type(name) == "function" then
                local ok, val = pcall(name)
                name = ok and val or nil
            end
            if type(name) == "string" and name:lower():find(query, 1, true) then
                return true
            end
        end
        return false
    end

    function frame:FilterTree(searchText)
        if not searchText or searchText == "" then
            tree:SetMenuData(self._fullMenuData)
            return
        end
        local query = searchText:lower()
        local filtered = {}
        for _, item in ipairs(self._fullMenuData) do
            local parentText = (item.text or ""):lower()
            local parentMatch = parentText:find(query, 1, true)

            if item.children and #item.children > 0 then
                local matchedChildren = {}
                for _, ch in ipairs(item.children) do
                    local childText = (ch.text or ""):lower()
                    local childMatch = childText:find(query, 1, true)
                    local contentMatch = OptionContainsText(ch.key, query)
                    if childMatch or contentMatch then
                        matchedChildren[#matchedChildren + 1] = { text = ch.text, key = ch.key }
                    end
                end
                if parentMatch then
                    filtered[#filtered + 1] = { text = item.text, key = item.key, children = item.children }
                elseif #matchedChildren > 0 then
                    filtered[#filtered + 1] = { text = item.text, key = item.key, children = matchedChildren }
                end
            else
                if parentMatch or OptionContainsText(item.key, query) then
                    filtered[#filtered + 1] = { text = item.text, key = item.key }
                end
            end
        end
        tree:SetMenuData(filtered, true)
    end

    -- ============================================
    -- 검색 인덱스 빌드
    -- ============================================
    frame._searchIndex = BuildSearchIndex(options)
    frame._searchMode = false

    -- ============================================
    -- DanderS 검색: PerformSearch / ClearSearch
    -- ============================================
    function frame:PerformSearch(query)
        if not self._searchIndex then return end

        local queryLower = query:lower()
        local results = {}

        for _, entry in ipairs(self._searchIndex) do
            if (entry.nameLower and entry.nameLower:find(queryLower, 1, true))
                or (entry.descLower and entry.descLower:find(queryLower, 1, true)) then
                results[#results + 1] = entry
            end
        end

        -- 검색 모드 진입 (첫 진입 시 현재 상태 저장)
        if not self._searchMode then
            self._preSearchTab = self.currentTab
            self._preSearchPath = self.currentPath
            self._searchMode = true
        end

        -- 스크롤 초기화
        self.scrollFrame:SetVerticalScroll(0)

        -- scrollChild 참조 전달
        self.scrollChild.scrollFrame = self.scrollFrame

        -- 검색 결과 렌더링
        RenderSearchResults(self.scrollChild, results, self)

        -- 스크롤바 업데이트
        local function DelayedUpdate()
            if self.scrollFrame and self.scrollFrame.ScrollBar and self.scrollFrame.ScrollBar.UpdateThumbPosition then
                self.scrollFrame.ScrollBar.UpdateThumbPosition()
            end
        end
        C_Timer.After(0.02, DelayedUpdate)
        C_Timer.After(0.1, DelayedUpdate)
    end

    function frame:ClearSearch()
        if not self._searchMode then return end
        self._searchMode = false

        -- 트리 메뉴 복원
        self:FilterTree("")

        -- 이전 뷰 복원
        local tabKey = self._preSearchTab
        if tabKey and self._optionLookup[tabKey] then
            local lookup = self._optionLookup[tabKey]
            if self.treeMenu then
                self.treeMenu:SetSelected(tabKey)
            end
            self:SetContent(lookup.option, lookup.path)
            self.currentTab = tabKey
            self.currentPath = lookup.path
        end

        self._preSearchTab = nil
        self._preSearchPath = nil
    end

    -- ============================================
    -- 초기 콘텐츠 렌더링
    -- ============================================
    if defaultKey and frame._optionLookup[defaultKey] then
        local lookup = frame._optionLookup[defaultKey]
        frame:SetContent(lookup.option, lookup.path)
        frame.currentTab = defaultKey
        frame.currentPath = lookup.path
        frame.configOptions = options
    end

    -- [12.0.1] BetterCooldownManager(고급 재사용 대기시간 관리자) 자동 활성화
    do
        local prevVal = C_CVar.GetCVar("cooldownViewerEnabled")
        DDingUI._cdmPrevCooldownViewerEnabled = prevVal
        C_CVar.SetCVar("cooldownViewerEnabled", "1")
        -- Blizzard_CooldownViewer 미로드 시 로드 시도
        if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then
            pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
        end
    end

    frame:Show()
    frame:Raise()

    -- 프레임 표시 후 레이아웃 확정 → scrollChild 너비 동기화
    C_Timer.After(0.05, function()
        if frame and frame:IsShown() then
            if frame.scrollFrame and frame.scrollChild then
                local sfWidth = frame.scrollFrame:GetWidth()
                if sfWidth and sfWidth > 0 then
                    frame.scrollChild:SetWidth(sfWidth - 1)
                end
            end
            if frame.SoftRefresh then
                frame:SoftRefresh()
            end
        end
    end)

    -- [12.0.1] 고급 재사용 대기시간 관리자(CooldownViewerSettings) 자동 열기
    C_Timer.After(0.15, function()
        if frame and frame:IsShown() then
            local cdmSettings = _G["CooldownViewerSettings"]
            if cdmSettings and cdmSettings.Show then
                cdmSettings:Show()
                cdmSettings:Raise()
            end
        end
    end)

    -- [12.0.1] CDM 활성화 후 카탈로그 자동 스캔 (viewer 프레임 재생성 대기 후)
    C_Timer.After(0.5, function()
        if frame and frame:IsShown() and DDingUI.CDMScanner then
            DDingUI.CDMScanner.ScanAll()
            if DDingUI.UpdateCDMIconGrid then
                DDingUI.UpdateCDMIconGrid()
            end
        end
    end)
end

-- ============================================
-- Export Public API
-- ============================================
DDingUI.GUI = {
    -- Core Functions
    CreateConfigFrame = DDingUI.CreateConfigFrame,
    OpenConfigGUI = DDingUI.OpenConfigGUI,

    -- Refresh the config frame (for external modules to trigger UI update)
    SoftRefresh = function()
        if ConfigFrame and ConfigFrame.SoftRefresh then
            ConfigFrame:SoftRefresh()
        end
    end,

    -- Widgets
    Widgets = Widgets,

    -- Theme Colors & Settings
    THEME = THEME,

    -- Styling Helpers (for other modules)
    CreateBackdrop = CreateBackdrop,
    CreateShadow = CreateShadow,
    FadeIn = FadeIn,
    FadeOut = FadeOut,
    AddHoverHighlight = AddHoverHighlight,
    StyleFontString = StyleFontString,

    -- Scroll Helpers (for modules that need themed scrollbars)
    CreateCustomScrollBar = CreateCustomScrollBar,
    GetSafeScrollRange = GetSafeScrollRange,
    PropagateMouseWheelToScroll = PropagateMouseWheelToScroll,
    PropagateMouseWheelRecursive = PropagateMouseWheelRecursive,
}
