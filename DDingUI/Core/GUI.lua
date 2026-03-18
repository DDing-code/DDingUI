local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

-- [FIX] WoW 12.0: EasyMenu 제거됨 → MenuUtil 기반 polyfill
if not EasyMenu and MenuUtil and MenuUtil.CreateContextMenu then
    EasyMenu = function(menuList, _, anchorFrame, x, y, displayMode)
        MenuUtil.CreateContextMenu(anchorFrame, function(ownerRegion, rootDescription)
            for _, item in ipairs(menuList) do
                if item.isTitle then
                    rootDescription:CreateTitle(item.text or "")
                elseif item.isSeparator then
                    rootDescription:CreateDivider()
                elseif item.hasArrow and item.menuList then
                    local sub = rootDescription:CreateButton(item.text or "")
                    for _, subItem in ipairs(item.menuList) do
                        if subItem.isTitle then
                            sub:CreateTitle(subItem.text or "")
                        else
                            sub:CreateButton(subItem.text or "", function()
                                if subItem.func then subItem.func() end
                            end)
                        end
                    end
                else
                    rootDescription:CreateButton(item.text or "", function()
                        if item.func then item.func() end
                    end)
                end
            end
        end)
    end
end
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

-- [FIX] 드래그&드롭 순서 변경 상태
local DragState = {
    active = false,
    sourceData = nil,   -- { groupKey, iconKey, iconIdx }
    sourceBtn = nil,
    ghostFrame = nil,
}

local SL = _G.DDingUI_StyleLib -- [12.0.1]
assert(SL, "DDingUI_StyleLib must be loaded before GUI.lua") -- [12.0.1]
local SLC = SL.Colors
local FLAT = SL.Textures.flat or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local acFrom, acTo, acLight, acDark = SL.GetAccent("CDM")

-- [FIX] WoW 12.0+: StaticPopup editBox 접근 헬퍼 (editBox 필드가 nil인 버전 대응)
local function DDingUI_GetPopupEditBox(dlg)
    if not dlg then return nil end
    if dlg.editBox then return dlg.editBox end
    if dlg.EditBox then return dlg.EditBox end
    local name = dlg.GetName and dlg:GetName()
    if name and _G[name.."EditBox"] then return _G[name.."EditBox"] end
    -- 최종 fallback: 자식 프레임 중 EditBox 타입 검색
    for i = 1, dlg:GetNumChildren() do
        local child = select(i, dlg:GetChildren())
        if child and child.IsObjectType and child:IsObjectType("EditBox") then
            return child
        end
    end
    return nil
end

-- [ELLESMERE] StyleLib v2 모듈 참조
local Tokens = SL.Tokens               -- 60+ 디자인 토큰
local WR     = SL.WidgetRefresh         -- 인플레이스 갱신
local PG     = SL.ProceduralGlow        -- 수학적 글로우 엔진

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
-- [REFACTOR] MoverUtils.EaseInOut 이징 적용
-- ============================================
local function FadeIn(frame, duration)
    if not frame then return end
    local MU_fade = DDingUI.MoverUtils
    if MU_fade and MU_fade.FadeIn then
        MU_fade.FadeIn(frame, duration or 0.2)
    else
        -- fallback: StyleLib
        SL.FadeIn(frame, duration or 0.2, frame:GetAlpha(), 1)
    end
end

local function FadeOut(frame, duration)
    if not frame then return end
    local MU_fade = DDingUI.MoverUtils
    if MU_fade and MU_fade.FadeOut then
        MU_fade.FadeOut(frame, duration or 0.2)
    else
        -- fallback: StyleLib
        SL.FadeOut(frame, duration or 0.2, frame:GetAlpha(), 0, false)
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
    topColor = topColor or {SL.GetColor("gradTop")}
    bottomColor = bottomColor or {SL.GetColor("gradBottom")}

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
    startColor = startColor or {SL.GetColor("accent")}
    endColor = endColor or {SL.GetColor("accentGradEnd")}  -- accentBlue → SL
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

    local acR, acG, acB = SL.GetColor("accent")
    local abR, abG, abB = SL.GetColor("accentGradEnd")
    if direction == "HORIZONTAL" then
        gradient:SetGradient("HORIZONTAL",
            CreateColor(acR, acG, acB, 1),      -- 보라 (좌)
            CreateColor(abR, abG, abB, 1)  -- 파랑 (우)
        )
    else
        gradient:SetGradient("VERTICAL",
            CreateColor(abR, abG, abB, 1),  -- 파랑 (하)
            CreateColor(acR, acG, acB, 1)       -- 보라 (상)
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
    scrollBar:SetBackdropColor(SL.GetColor("widget"))

    -- 스크롤바 썸 (드래그 가능한 부분)
    local thumb = CreateFrame("Button", nil, scrollBar, "BackdropTemplate")
    thumb:SetWidth(8)
    thumb:SetHeight(40)
    thumb:SetBackdrop({
        bgFile = FLAT,
        edgeFile = nil,
    })
    thumb:SetBackdropColor(SL.GetColor("border"))
    thumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)
    scrollBar.thumb = thumb

    -- 썸 호버 효과
    thumb:SetScript("OnEnter", function(self)
        self:SetBackdropColor(SL.GetColor("accent"))
    end)
    thumb:SetScript("OnLeave", function(self)
        if not self.isDragging then
            self:SetBackdropColor(SL.GetColor("border"))
        end
    end)

    -- 드래그 기능 (OnMouseDown/OnMouseUp 방식)
    thumb:EnableMouse(true)
    thumb.isDragging = false

    thumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.isDragging = true
            self:SetBackdropColor(SL.GetColor("accent"))
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
                self:SetBackdropColor(SL.GetColor("border"))
            end
        end
    end)

    thumb:SetScript("OnUpdate", function(self)
        if self.isDragging then
            -- 마우스 버튼이 놓였는지 확인 (thumb 바깥에서 놓았을 때도 감지)
            if not IsMouseButtonDown("LeftButton") then
                self.isDragging = false
                if not self:IsMouseOver() then
                    self:SetBackdropColor(SL.GetColor("border"))
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

    -- [REFACTOR] 스무스 스크롤 적용 (MoverUtils.CreateSmoothScroll)
    scrollFrame:EnableMouseWheel(true)
    local MU = DDingUI.MoverUtils
    local smoothCtrl = MU and MU.CreateSmoothScroll and MU.CreateSmoothScroll(scrollFrame, { speed = 12, step = 60 })

    if smoothCtrl then
        -- 스무스 스크롤 활성: OnMouseWheel → 보간 스크롤
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            smoothCtrl:OnMouseWheel(delta)
        end)
        scrollBar._smoothCtrl = smoothCtrl -- 외부 접근용 (SmoothScrollTo 호출)
    else
        -- 폴백: MoverUtils 미로드 시 기존 방식 유지
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
    end

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
    dropdown:SetBackdropColor(SL.GetColor("widget"))
    dropdown:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일: 솔리드 블랙

    -- 선택된 텍스트
    local selectedText = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(selectedText)
    selectedText:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    selectedText:SetPoint("RIGHT", dropdown, "RIGHT", -20, 0)
    selectedText:SetJustifyH("LEFT")
    selectedText:SetTextColor(SL.GetColor("text"))
    selectedText:SetText("Select...")
    dropdown.selectedText = selectedText

    -- 화살표 아이콘
    local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(arrow)
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
    arrow:SetText("▼")
    arrow:SetTextColor(SL.GetColor("dim"))
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
    listFrame:SetBackdropColor(SL.GetColor("selected"))
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
    local ar, ag, ab = SL.GetColor("accent")
    scrollbarThumb:SetBackdropColor(ar, ag, ab, 0.6)
    scrollbarThumb:EnableMouse(true)
    scrollbarThumb.isDragging = false
    dropdown.scrollbarThumb = scrollbarThumb

    -- 썸 호버 효과
    scrollbarThumb:SetScript("OnEnter", function(self)
        if not self.isDragging then
            self:SetBackdropColor(SL.GetColor("accent"))
        end
    end)
    scrollbarThumb:SetScript("OnLeave", function(self)
        if not self.isDragging then
            local r, g, b = SL.GetColor("accent")
            self:SetBackdropColor(r, g, b, 0.6)
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
            self:SetBackdropColor(SL.GetColor("accent"))
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
                local r, g, b = SL.GetColor("accent")
                self:SetBackdropColor(r, g, b, 0.9)
            else
                local r, g, b = SL.GetColor("accent")
                self:SetBackdropColor(r, g, b, 0.6)
            end
        end
    end)

    scrollbarThumb:SetScript("OnUpdate", function(self)
        if self.isDragging then
            -- 마우스 버튼이 놓였는지 확인 (thumb 바깥에서 놓았을 때도 감지)
            if not IsMouseButtonDown("LeftButton") then
                self.isDragging = false
                if self:IsMouseOver() then
                    local r, g, b = SL.GetColor("accent")
                    self:SetBackdropColor(r, g, b, 0.9)
                else
                    local r, g, b = SL.GetColor("accent")
                    self:SetBackdropColor(r, g, b, 0.6)
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
        self:SetBackdropBorderColor(SL.GetColor("accent"))
        arrow:SetTextColor(SL.GetColor("accent"))
    end)
    dropdown:SetScript("OnLeave", function(self)
        if not listFrame:IsShown() then
            self:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
            arrow:SetTextColor(SL.GetColor("dim"))
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
        arrow:SetTextColor(SL.GetColor("dim"))
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
            local _acR, _acG, _acB = SL.GetColor("accent")
            local _abR, _abG, _abB = SL.GetColor("accentGradEnd")
            accentBar:SetGradient("VERTICAL",
                CreateColor(_abR, _abG, _abB, 1),  -- 파랑 (하)
                CreateColor(_acR, _acG, _acB, 1)    -- 보라 (상)
            )
            item.accentBar = accentBar

            local isSelected = (key == currentKey)
            if isSelected then
                item:SetBackdropColor(SL.GetColor("selected"))
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
                itemText:SetTextColor(SL.GetColor("text"))
            else
                itemText:SetTextColor(SL.GetColor("dim"))
            end

            item.key = key
            item.displayText = displayText
            item.text = itemText

            -- 호버 효과 - 배경만 살짝 밝게
            item:SetScript("OnEnter", function(self)
                if self.key ~= dropdown.currentValue then
                    self:SetBackdropColor(SL.GetColor("hover"))
                    self.text:SetTextColor(SL.GetColor("text"))
                end
            end)
            item:SetScript("OnLeave", function(self)
                if self.key == dropdown.currentValue then
                    self:SetBackdropColor(SL.GetColor("selected"))
                    self.text:SetTextColor(SL.GetColor("text"))
                else
                    self:SetBackdropColor(0, 0, 0, 0)
                    self.text:SetTextColor(SL.GetColor("dim"))
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
                        itm:SetBackdropColor(SL.GetColor("selected"))
                        itm.text:SetTextColor(SL.GetColor("text"))
                        itm.accentBar:Show()
                    else
                        itm:SetBackdropColor(0, 0, 0, 0)
                        itm.text:SetTextColor(SL.GetColor("dim"))
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
    label:SetTextColor(SL.GetColor("text"))  -- 미선택: 흰색

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
    local _tAcR, _tAcG, _tAcB = SL.GetColor("accent")
    local _tAbR, _tAbG, _tAbB = SL.GetColor("accentGradEnd")
    accentLine:SetGradient("HORIZONTAL",
        CreateColor(_tAcR, _tAcG, _tAcB, 1),      -- 보라 (좌)
        CreateColor(_tAbR, _tAbG, _tAbB, 1)  -- 파랑 (우)
    )
    accentLine:Hide()

    -- 호버 효과
    btn:SetScript("OnEnter", function(self)
        if not self.active then
            self:SetBackdropColor(SL.GetColor("hover"))
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
            self.label:SetTextColor(SL.GetColor("accent"))  -- 선택: 보라색
        else
            self.accentLine:Hide()
            self:SetBackdropColor(0, 0, 0, 0)
            self.label:SetTextColor(SL.GetColor("text"))  -- 미선택: 흰색
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
    checkbox:SetBackdropBorderColor(SL.GetColor("border"))

    -- 체크 마크 (UF 통일: 전체 채우기 그라데이션)
    local check = checkbox:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", 1, -1)
    check:SetPoint("BOTTOMRIGHT", -1, 1)
    check:SetColorTexture(1, 1, 1, 1)
    local _cAcR, _cAcG, _cAcB = SL.GetColor("accent")
    local _cAbR, _cAbG, _cAbB = SL.GetColor("accentGradEnd")
    check:SetGradient("HORIZONTAL",
        CreateColor(_cAcR, _cAcG, _cAcB, 1),
        CreateColor(_cAbR, _cAbG, _cAbB, 1)
    )
    check:Hide()
    checkbox.check = check

    -- 하이라이트 (UF 통일)
    local highlightTex = checkbox:CreateTexture(nil, "ARTWORK")
    highlightTex:SetColorTexture(_cAcR, _cAcG, _cAcB, 0.1)
    highlightTex:SetPoint("TOPLEFT", 1, -1)
    highlightTex:SetPoint("BOTTOMRIGHT", -1, 1)
    checkbox:SetHighlightTexture(highlightTex, "ADD")

    -- UF 통일: 간소화된 상태 관리
    checkbox.isChecked = false
    checkbox.SetChecked = function(self, checked)
        self.isChecked = checked
        if checked then
            self.check:Show()
            self:SetBackdropBorderColor(SL.GetColor("accent"))
        else
            self.check:Hide()
            self:SetBackdropBorderColor(SL.GetColor("border"))
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
    label:SetTextColor(SL.GetColor("text"))

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
                label:SetTextColor(SL.GetColor("dim"))
                checkbox:SetAlpha(0.5)
            else
                label:SetTextColor(SL.GetColor("text"))
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

    -- 기본 텍스쳐 숨기기 및 Low/High 텍스트를 슬라이더 양쪽에 배치
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
            lowText:SetTextColor(SL.GetColor("dim"))
            StyleFontString(lowText)
        end
        -- 높음: 슬라이더 오른쪽에 배치
        if highText then
            highText:ClearAllPoints()
            highText:SetPoint("LEFT", slider, "RIGHT", 6, 0)
            highText:SetTextColor(SL.GetColor("dim"))
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
    label:SetTextColor(SL.GetColor("text"))

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
                label:SetTextColor(SL.GetColor("dim"))
                valueEditBox:SetTextColor(SL.GetColor("dim"))
            else
                label:SetTextColor(SL.GetColor("text"))
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
    label:SetTextColor(SL.GetColor("text"))

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
    label:SetTextColor(SL.GetColor("text"))

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
        self:SetBackdropBorderColor(SL.GetColor("accent"))
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

        -- 아이콘 텍스쳐
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
        button:SetBackdropColor(SL.GetColor("widget"))
        button:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        StyleFontString(label)
        label:SetPoint("CENTER")
        label:SetText(name)
        label:SetTextColor(SL.GetColor("text"))

        -- [FIX] 드래그&드롭 지원 (_dragData가 있는 execute 전용)
        local dragData = option._dragData
        if dragData then
            button:SetMovable(true)
            button:RegisterForDrag("LeftButton")
            button._dragData = dragData

            -- 드래그 커서 아이콘
            local dragIcon = "|TInterface\\CURSOR\\UI-Cursor-Move:14:14|t "

            button:SetScript("OnDragStart", function(self)
                DragState.active = true
                DragState.sourceData = self._dragData
                DragState.sourceBtn = self
                -- 고스트 프레임 생성
                if not DragState.ghostFrame then
                    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                    ghost:SetFrameStrata("TOOLTIP")
                    ghost:SetSize(180, 22)
                    ghost:SetBackdrop({
                        bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
                        insets = { left = 0, right = 0, top = 0, bottom = 0 }
                    })
                    ghost:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
                    ghost:SetBackdropBorderColor(SL.GetColor("accent"))
                    ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    StyleFontString(ghost.text)
                    ghost.text:SetPoint("CENTER")
                    ghost:SetScript("OnUpdate", function(g)
                        local cx, cy = GetCursorPosition()
                        local s = UIParent:GetEffectiveScale()
                        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / s, cy / s)
                    end)
                    DragState.ghostFrame = ghost
                end
                DragState.ghostFrame.text:SetText(dragIcon .. (name or ""))
                DragState.ghostFrame:ClearAllPoints()
                DragState.ghostFrame:Show()
                -- 원래 버튼 반투명
                self:SetAlpha(0.3)
            end)

            button:SetScript("OnDragStop", function(self)
                if not DragState.active then return end
                self:SetAlpha(1)
                if DragState.ghostFrame then DragState.ghostFrame:Hide() end

                -- 드롭 대상 찾기: 마우스 아래 프레임 검색
                local frames = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
                local targetBtn = nil
                for _, f in ipairs(frames) do
                    if f and f._dragData and f ~= self then
                        targetBtn = f
                        break
                    end
                    -- 부모가 Button이고 _dragData 있으면
                    if f and f:GetParent() and f:GetParent()._dragData and f:GetParent() ~= self then
                        targetBtn = f:GetParent()
                        break
                    end
                end

                if targetBtn and targetBtn._dragData then
                    local srcData = DragState.sourceData
                    local dstData = targetBtn._dragData
                    if srcData.groupKey == dstData.groupKey and srcData.iconKey ~= dstData.iconKey then
                        -- ReorderIconInGroup 사용: src를 dst 위치로 이동
                        if DDingUI.CustomIcons and DDingUI.CustomIcons.ReorderIconInGroup then
                            DDingUI.CustomIcons:ReorderIconInGroup(srcData.groupKey, srcData.iconKey, dstData.iconKey)
                            -- [FIX] RefreshLayout + SoftRefresh (FullRefresh는 서브탭 없으면 창 닫힘)
                            if DDingUI.GroupSystem and DDingUI.GroupSystem.RefreshLayout then
                                DDingUI.GroupSystem:RefreshLayout()
                            end
                            C_Timer.After(0.1, function()
                                local cf = _G["DDingUI_ConfigFrame"]
                                if not cf or not cf:IsShown() then return end
                                local ct = cf.currentTab or ""
                                if ct:match("^groupSystem") and cf.configOptions then
                                    local fn = DDingUI._CreateGroupSystemOptions
                                    if fn then
                                        cf.configOptions.args.groupSystem = fn(1)
                                        DDingUI.configOptions = cf.configOptions
                                        if cf._optionLookup and cf._optionLookup[ct] then
                                            local path = cf._optionLookup[ct].path
                                            if path then
                                                local opt = cf.configOptions
                                                for _, k in ipairs(path) do
                                                    opt = opt and opt.args and opt.args[k]
                                                end
                                                if opt then cf._optionLookup[ct].option = opt end
                                            end
                                        end
                                    end
                                end
                                if cf.SoftRefresh then cf:SoftRefresh() end
                            end)
                        end
                    end
                end

                DragState.active = false
                DragState.sourceData = nil
                DragState.sourceBtn = nil
            end)

            -- 드래그 중 다른 버튼 위에 올리면 하이라이트
            local origOnEnter = button:GetScript("OnEnter")
            button:SetScript("OnEnter", function(self)
                if DragState.active and DragState.sourceBtn ~= self and self._dragData then
                    self:SetBackdropColor(0.2, 0.8, 0.2, 0.5)
                    self:SetBackdropBorderColor(0.2, 1, 0.2, 1)
                else
                    self:SetBackdropColor(SL.GetColor("accent"))
                    self:SetBackdropBorderColor(SL.GetColor("accent"))
                end
                label:SetTextColor(1, 1, 1, 1)
            end)

            button:SetScript("OnLeave", function(self)
                self:SetBackdropColor(SL.GetColor("widget"))
                self:SetBackdropBorderColor(0, 0, 0, 1)
                label:SetTextColor(SL.GetColor("text"))
            end)

            -- 메인 버튼 클릭은 아무 동작 없음 (드래그 전용)
            button:SetScript("OnClick", function(self) end)

            -- [FIX] X 삭제 버튼 (오른쪽)
            local closeBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
            closeBtn:SetSize(22, 22)
            closeBtn:SetPoint("LEFT", button, "RIGHT", 4, 0)
            closeBtn:SetBackdrop({
                bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            closeBtn:SetBackdropColor(0.3, 0.1, 0.1, 0.8)
            closeBtn:SetBackdropBorderColor(0, 0, 0, 1)

            local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            StyleFontString(closeText)
            closeText:SetPoint("CENTER")
            closeText:SetText("X")
            closeText:SetTextColor(0.6, 0.3, 0.3, 1)

            closeBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.8, 0.15, 0.15, 1)
                self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
                closeText:SetTextColor(1, 1, 1, 1)
            end)
            closeBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.3, 0.1, 0.1, 0.8)
                self:SetBackdropBorderColor(0, 0, 0, 1)
                closeText:SetTextColor(0.6, 0.3, 0.3, 1)
            end)
            closeBtn:SetScript("OnClick", function()
                if option.func then
                    if type(option.func) == "function" then
                        option.func()
                    end
                end
            end)
            frame.closeBtn = closeBtn
        else
            -- 드래그 미지원 일반 버튼
            button:SetScript("OnEnter", function(self)
                self:SetBackdropColor(SL.GetColor("accent"))
                self:SetBackdropBorderColor(SL.GetColor("accent"))
                label:SetTextColor(1, 1, 1, 1)
            end)

            button:SetScript("OnLeave", function(self)
                self:SetBackdropColor(SL.GetColor("widget"))
                self:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
                label:SetTextColor(SL.GetColor("text"))
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
        end

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

    -- 아이콘 텍스쳐
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
    label:SetTextColor(SL.GetColor("text"))

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
        editBox:SetTextColor(SL.GetColor("text"))
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
            scrollContainer:SetBackdropBorderColor(SL.GetColor("accent"))
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
        editBox:SetTextColor(SL.GetColor("text"))
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
            if option.set then
                ResolveGetSet(option.set, optionsTable, option, self:GetText())
            end
            self:EnableKeyboard(false)
            self:ClearFocus()
            -- Remove visual feedback for focus
            CreateBackdrop(self, THEME.input, {0, 0, 0, 1})  -- UF 통일
        end)

        editBox:SetScript("OnEnter", function(self)
        end)

        editBox:SetScript("OnTextChanged", function(self, userInput)
            -- 입력 중에는 set 호출하지 않음 (Enter 또는 포커스 해제 시에만)
        end)
        
        editBox:SetScript("OnEnterPressed", function(self)
            if option.set then
                ResolveGetSet(option.set, optionsTable, option, self:GetText())
            end
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
    label:SetTextColor(SL.GetColor("text"))

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
    local isCollapsed = sectionKey and (CollapsedGroups[sectionKey] == true) or false  -- nil = 펼침 (기본)

    -- Collapse/Expand arrow button
    local collapseBtn = CreateFrame("Button", nil, frame)
    collapseBtn:SetSize(18, 18)
    collapseBtn:SetPoint("LEFT", frame, "LEFT", 0, 2)

    local collapseArrow = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(collapseArrow)
    collapseArrow:SetPoint("CENTER", collapseBtn, "CENTER", 0, 0)
    collapseArrow:SetText(isCollapsed and "▶" or "▼")
    collapseArrow:SetTextColor(SL.GetColor("dim"))
    collapseBtn.arrow = collapseArrow
    frame.collapseBtn = collapseBtn
    frame._sectionKey = sectionKey
    frame._isCollapsed = isCollapsed

    collapseBtn:SetScript("OnEnter", function(self)
        self.arrow:SetTextColor(SL.GetColor("accent"))
    end)
    collapseBtn:SetScript("OnLeave", function(self)
        self.arrow:SetTextColor(SL.GetColor("dim"))
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
        collapseArrow:SetTextColor(SL.GetColor("accent"))
    end)
    labelBtn:SetScript("OnLeave", function()
        collapseArrow:SetTextColor(SL.GetColor("dim"))
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
    label:SetTextColor(SL.GetColor("dim"))
    
    frame:SetHeight(label:GetStringHeight() + 10)
    frame.label = label
    
    return frame
end
-- [REFACTOR] Forward declaration: RenderOptions는 이 함수 뒤에 정의되지만,
-- CreateBuffTrackerPanel 내부 클로저에서 참조됨
local RenderOptions

-- ============================================================
-- [REFACTOR] WeakAuras-style Buff Tracker Panel
-- contentArea 안에 좌측 리스트 + 우측 탭 split-view를 임베딩
-- ============================================================
local function CreateBuffTrackerPanel(contentFrame, parentFrame)
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

    local SIDE_W = Tokens and Tokens.SIDEBAR_W or 180
    local ITEM_H = Tokens and Tokens.ROW_H or 22
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

    -- [ELLESMERE] WidgetRefresh 컨텍스트 생성
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

    -- 검색 바
    local searchFrame = CreateFrame("Frame", nil, leftPanel)
    searchFrame:SetPoint("TOPLEFT", 5, -5)
    searchFrame:SetPoint("TOPRIGHT", -5, -5)
    searchFrame:SetHeight(22)

    -- Preview 토글 버튼 (검색바 오른쪽)
    local PREVIEW_BTN_W = 22
    local previewBtn = CreateFrame("Button", nil, searchFrame, "BackdropTemplate")
    previewBtn:SetSize(PREVIEW_BTN_W, 22)
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
    local searchInputFrame = CreateFrame("Frame", nil, searchFrame)
    searchInputFrame:SetPoint("TOPLEFT", 0, 0)
    searchInputFrame:SetPoint("BOTTOMRIGHT", previewBtn, "BOTTOMLEFT", -3, 0)

    local searchBg = searchInputFrame:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetColorTexture(THEME.input[1], THEME.input[2], THEME.input[3], THEME.input[4] or 0.8)

    local searchBox = CreateFrame("EditBox", nil, searchInputFrame)
    searchBox:SetAllPoints()
    searchBox:SetFontObject(GameFontNormalSmall)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(6, 6, 0, 0)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        if btPanel.RefreshList then btPanel:RefreshList(self:GetText()) end
    end)

    -- placeholder
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 6, 0)
    searchPlaceholder:SetText("Search...")
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
    -- [ELLESMERE] PP: disable pixel snap for crisp 1px
    if divider.SetSnapToPixelGrid then
        divider:SetSnapToPixelGrid(false)
        divider:SetTexelSnappingBias(0)
    end
    divider:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 0, 0)

    -- ─── 우측 패널: 탭 + 설정 ───
    local rightPanel = CreateFrame("Frame", nil, btPanel)
    rightPanel:SetPoint("TOPLEFT", divider, "TOPRIGHT", 0, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", btPanel, "BOTTOMRIGHT", 0, 0)

    -- 탭 바
    local tabBar = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
    tabBar:SetPoint("TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", 0, 0)
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
            tabChild.subScrollChild = nil
        end
        if tabChild.subTabContainer then
            tabChild.subTabContainer:Hide()
            tabChild.subTabContainer = nil
        end
        tabChild:SetHeight(1)
        tabScrollFrame:SetVerticalScroll(0)
    end

    -- ─── 트래커 리스트 렌더링 ───
    function btPanel:RefreshList(searchQueryRaw)
        local searchQ = (searchQueryRaw or searchBox:GetText() or ""):lower()
        local rootCfg = DDingUI.db.profile.buffTrackerBar
        local trackedBuffs = GetTrackedBuffsForGUI()  -- [FIX] global per-spec 소스

        -- 기존 버튼 숨기기
        for _, btn in ipairs(self.listButtons) do btn:Hide() end

        local yOff = 0
        local btnIdx = 0

        -- ─── 상단 고정 항목 (WeakAuras 스타일) ───
        local staticItems = {
            { key = "wizard",    name = "|cff44ee44+ " .. (L["New Tracker"] or "New Tracker") .. "|r",  colorR = 0.27, colorG = 0.93, colorB = 0.27 },
            { key = "catalog",   name = L["CDM Aura Catalog"] or "CDM Catalog",                          colorR = THEME.text[1], colorG = THEME.text[2], colorB = THEME.text[3] },
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
            -- [ELLESMERE] PP
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
                -- [ELLESMERE] PP + accent 등록
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
                btn._icon:SetSize(16, 16)
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

            -- [ELLESMERE] 얼룩말 줄무늬 + 선택 하이라이트
            local rowAlpha = Tokens and Tokens.RowBgAlpha(btnIdx) or 0
            if self.selectedIndex == i then
                -- 선택됨: accent 배경 + stripe 표시 + 펄스
                btn._bg:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.18)
                if not entry.isGroup then
                    btn._text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
                end
                btn._stripe:Show()
                -- [ELLESMERE] 스트라이프 펄스 애니메이션
                if PG then PG.StartStripePulse(btn._stripe, 2.5, 0.5, 1.0) end
            else
                -- 비선택: 얼룩말 배경
                btn._bg:SetColorTexture(1, 1, 1, rowAlpha)
                btn._stripe:Hide()
                -- [ELLESMERE] 이전 펄스 중지
                if PG then PG.StopStripePulse(btn._stripe) end
            end

            -- [ELLESMERE] 3단계 호버 (bg + text 동시 변환)
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
                    -- [ELLESMERE] 3단계 복원: 얼룩말 배경 + 원래 텍스트 + stripe 숨김
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
        self:RenderTrackerTabs(index)
    end

    function btPanel:SelectStatic(key)
        self.selectedIndex = key
        self:RefreshList()
        self:RenderStaticPage(key)
    end

    -- ─── 그룹 선택 → 그룹 설정 렌더링 ───
    function btPanel:RenderGroupSettings(groupIdx)
        ClearTabContent()

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
                -- [ELLESMERE] PP
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

    -- ─── 우측 탭 렌더링 (WeakAuras 스타일) ───
    -- flat options를 order 범위 + key prefix로 탭으로 자동 분류
    function btPanel:RenderTrackerTabs(index)
        ClearTabContent()

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

        -- 1. 기본 설정 (모든 displayType에 공통)
        tabDefs[#tabDefs + 1] = {
            name = L["General"] or "General",
            filter = function(key, order)
                -- order 0~1.09 범위 (enabled, displayType, frameStrata, trackingMode, manual 관련)
                -- Spell bar/color/text 키는 Bar/Text 탭으로 이동되었으므로 제외
                if key:find("_spellFillDirection", 1, true) or key:find("_spellRechargeColor", 1, true)
                   or key:find("_spellFullChargeColor", 1, true) or key:find("_spellReadyStyle", 1, true)
                   or key:find("_spellReadyColor", 1, true) or key:find("_spellColorCurve", 1, true)
                   or key:find("_spellShowReadyText", 1, true) or key:find("_spellHeader", 1, true) then
                    return false
                end
                return order >= 0 and order < 1.1
            end,
        }

        -- 2. displayType별 전용 탭
        if dType == "icon" then
            tabDefs[#tabDefs + 1] = {
                name = L["Icon"] or "Icon",
                filter = function(key, order)
                    return order >= 1.1 and order < 1.81
                end,
            }
        elseif dType == "sound" then
            tabDefs[#tabDefs + 1] = {
                name = L["Sound"] or "Sound",
                filter = function(key, order)
                    return order >= 1.81 and order < 1.9
                end,
            }
        elseif dType == "text" then
            tabDefs[#tabDefs + 1] = {
                name = L["Text"] or "Text",
                filter = function(key, order)
                    return order >= 1.9 and order < 2
                end,
            }
        elseif dType == "ring" then
            tabDefs[#tabDefs + 1] = {
                name = L["Ring"] or "Ring",
                filter = function(key, order)
                    -- 링 설정: ring prefix (Pos, Offset 포함)
                    return key:find("_ring") ~= nil
                end,
            }
        elseif dType == "bar" then
            -- 바 관련 스펠 옵션 키 (General에서 Bar로 이동)
            local spellBarKeys = {
                _spellFillDirection = true,
                _spellRechargeColor = true,
                _spellFullChargeColor = true,
                _spellReadyStyle = true,
                _spellReadyColor = true,
                _spellColorCurve = true,
            }
            -- 텍스트 관련 스펠 옵션 키 (General에서 Text로 이동)
            local spellTextKeys = {
                _spellShowReadyText = true,
            }
            -- 스펠 헤더 키
            local spellHeaderKey = "_spellHeader"

            -- 스펠 키 매칭 함수 (key suffix 기반)
            local function isSpellBarKey(key)
                for suffix in pairs(spellBarKeys) do
                    if key:find(suffix, 1, true) then return true end
                end
                return false
            end
            local function isSpellTextKey(key)
                for suffix in pairs(spellTextKeys) do
                    if key:find(suffix, 1, true) then return true end
                end
                return false
            end
            local function isSpellHeaderKey(key)
                return key:find(spellHeaderKey, 1, true) ~= nil
            end

            -- 외관 탭 (바 색상/채움/텍스쳐/테두리 + 스펠 색상/외관 옵션)
            tabDefs[#tabDefs + 1] = {
                name = L["Appearance"] or "Appearance",
                filter = function(key, order)
                    -- order 2~4.99 (기존 bar settings) + spell bar/color 키
                    if isSpellBarKey(key) or isSpellHeaderKey(key) then return true end
                    if order >= 2 and order < 5 then return true end
                    -- order 5.65~5.94: barOrientation, reverseFill, border, texture
                    if order >= 5.65 and order < 5.95 then return true end
                    return false
                end,
            }
            -- 위치/크기 탭
            tabDefs[#tabDefs + 1] = {
                name = L["Position"] or "Position",
                filter = function(key, order)
                    -- order 5.0~5.64: attachTo, anchorPoint, selfPoint, offset, width, height
                    return order >= 5 and order < 5.65
                end,
            }
            -- 텍스트 탭 (기존 Appearance → Text 이름 변경 + spell text 옵션 포함)
            tabDefs[#tabDefs + 1] = {
                name = L["Text"] or "Text",
                filter = function(key, order)
                    -- order 5.95~7.99: tick, stacks text, duration text, border, texture + spell text keys
                    if isSpellTextKey(key) then return true end
                    return order >= 5.95 and order < 8
                end,
            }
        end

        -- 마지막: 알림 탭 (모든 displayType 공통, order 8+)
        tabDefs[#tabDefs + 1] = {
            name = L["Actions"] or "Actions",
            filter = function(key, order)
                return key:find("_alert") ~= nil or order >= 8
            end,
        }

        -- ─── 각 탭의 옵션 분류 ───
        local tabGroups = {}
        for i, def in ipairs(tabDefs) do
            local args = {}
            local hasVisible = false
            for key, opt in pairs(allOpts) do
                local oOrder = opt.order or 999
                if def.filter(key, oOrder) then
                    args[key] = opt
                    -- hidden 체크 (함수이면 호출)
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
            tabGroups[i] = { name = def.name, args = args, hasVisible = hasVisible }
        end

        -- ─── 탭 버튼 생성 ───
        local tabX = 5
        local visibleTabIdx = 0
        local firstVisibleTab = nil

        for i, tg in ipairs(tabGroups) do
            -- 빈 탭은 건너뛰기
            if tg.hasVisible or next(tg.args) then
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
                if tg.hasVisible or next(tg.args) then
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
        local pageOpts = { type = "group", name = tabGroup.name, args = tabGroup.args }
        RenderOptions(tabChild, pageOpts, {}, parentFrame)

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
        -- 탭 바 숨기기 (정적 페이지는 탭 없음)
        tabBar:Hide()
        for _, tb in ipairs(self.tabButtons) do tb:Hide() end

        -- 컨텐츠 영역 재배치 (탭바 숨김이므로 상단부터)
        tabScrollFrame:ClearAllPoints()
        tabScrollFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 5, -5)
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
                            btPanel:SelectStatic("catalog")
                        end,
                    },
                },
            }
        elseif key == "catalog" then
            -- CDM 카탈로그 (기존 작동 유지)
            local catalogOpts = ns.CreateAuraIconOptions(1)
            pageOpts = {type = "group", name = "CDM Catalog", args = catalogOpts}
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
        if btPanel and btPanel.RenderStaticPage then
            btPanel:RenderStaticPage("catalog")
        end
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

RenderOptions = function(contentFrame, options, path, parentFrame)
    path = path or {}
    parentFrame = parentFrame or contentFrame:GetParent():GetParent()

    -- [REFACTOR] 커스텀 렌더러 분기
    if options.customRenderer == "buffTracker" then
        CreateBuffTrackerPanel(contentFrame, parentFrame)
        return
    end

    -- Buff Tracker 커스텀 패널 숨기기 (다른 탭으로 이동 시)
    -- NOTE: btPanel 내부의 tabChild에서 RenderOptions를 호출할 때는 숨기지 않음
    if parentFrame and parentFrame.contentArea and parentFrame.contentArea._btPanel then
        local btPanel = parentFrame.contentArea._btPanel
        local isInsideBtPanel = btPanel.tabChild and (contentFrame == btPanel.tabChild)
        if not isInsideBtPanel then
            btPanel:Hide()
            -- 스크롤 UI 복원
            parentFrame.scrollFrame:Show()
            if parentFrame.scrollBar then parentFrame.scrollBar:Show() end
        end
    end

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
        -- [FIX] 메인 프레임이 strata "DIALOG"이므로 탭도 "DIALOG"이어야 배경 위에 표시됨
        -- 기존 "HIGH"는 DIALOG보다 낮아서 탭이 콘텐츠 배경에 가려짐
        subTabContainer:SetFrameStrata("DIALOG")
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
            elseif option.type == "groupAssignGrid" then
                -- [REFACTOR] 인라인 그룹 아이콘 할당 그리드
                local groupName = option.groupName
                if groupName and DDingUI.BuildGroupAssignGridUI then
                    local gridFrame = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
                    gridFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                    gridFrame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                    gridFrame:SetWidth(contentFrame:GetWidth() or 900)
                    DDingUI:BuildGroupAssignGridUI(gridFrame, groupName)
                    widget = gridFrame
                    widgetHeight = gridFrame:GetHeight() or 200
                end
            elseif option.type == "spellSearch" then
                -- [REFACTOR] 실시간 Spell ID 검증 위젯 (Ayije 패턴 이식)
                local _GUI = DDingUI.GUI -- 런타임 참조 (local 정의가 파일 후반부)
                local searchFrame = CreateFrame("Frame", nil, contentFrame)
                searchFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                searchFrame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                searchFrame:SetHeight(60)

                local gf = DDingUI:GetGlobalFont() or globalFontPath

                -- 입력 필드
                local inputContainer = _GUI.CreateStyledInput(searchFrame, 200, 28, false)
                inputContainer:SetPoint("TOPLEFT", searchFrame, "TOPLEFT", 0, 0)

                -- Placeholder 텍스트
                local placeholder = inputContainer:CreateFontString(nil, "OVERLAY")
                placeholder:SetFont(gf, 11, "")
                placeholder:SetPoint("LEFT", inputContainer.editBox, "LEFT", 0, 0)
                placeholder:SetText(option.placeholder or "Spell ID...")
                placeholder:SetTextColor(0.55, 0.55, 0.55, 1)
                inputContainer.editBox:HookScript("OnEditFocusGained", function() placeholder:Hide() end)
                inputContainer.editBox:HookScript("OnEditFocusLost", function(self)
                    if self:GetText() == "" then placeholder:Show() end
                end)

                -- 아이콘 프리뷰
                local iconPreview = searchFrame:CreateTexture(nil, "ARTWORK")
                iconPreview:SetSize(28, 28)
                iconPreview:SetPoint("LEFT", inputContainer, "RIGHT", 8, 0)
                iconPreview:Hide()

                -- 상태 텍스트 (스펠 이름 or 에러)
                local statusText = searchFrame:CreateFontString(nil, "OVERLAY")
                statusText:SetFont(gf, 11, "")
                statusText:SetShadowOffset(1, -1)
                statusText:SetShadowColor(0, 0, 0, 1)
                statusText:SetPoint("LEFT", iconPreview, "RIGHT", 8, 0)
                statusText:SetPoint("RIGHT", searchFrame, "RIGHT", -80, 0)
                statusText:SetJustifyH("LEFT")

                -- Add 버튼
                local addBtn = _GUI.CreateStyledButton(searchFrame, option.buttonText or "Add", 70, 28)
                addBtn:SetPoint("RIGHT", searchFrame, "RIGHT", 0, -15)

                -- 실시간 유효성 검사 (OnTextChanged)
                inputContainer.editBox:HookScript("OnTextChanged", function(self)
                    local text = self:GetText()
                    local spellID = tonumber(text)
                    if spellID and spellID > 0 then
                        local ok, spellInfo = pcall(function()
                            if C_Spell and C_Spell.GetSpellInfo then
                                return C_Spell.GetSpellInfo(spellID)
                            end
                        end)
                        if ok and spellInfo and spellInfo.name then
                            statusText:SetText(spellInfo.name)
                            statusText:SetTextColor(THEME.success[1], THEME.success[2], THEME.success[3], 1)
                            local tex = C_Spell.GetSpellTexture(spellID)
                            if tex then
                                iconPreview:SetTexture(tex)
                                iconPreview:Show()
                            end
                        else
                            statusText:SetText("Invalid spell ID")
                            statusText:SetTextColor(THEME.error[1], THEME.error[2], THEME.error[3], 1)
                            iconPreview:Hide()
                        end
                    else
                        statusText:SetText("")
                        iconPreview:Hide()
                    end
                end)

                -- Add 버튼 콜백
                addBtn:SetScript("OnClick", function()
                    if option.onAdd then
                        local text = inputContainer:GetText()
                        local success = option.onAdd(text)
                        if success then
                            inputContainer:SetText("")
                            statusText:SetText("Added!")
                            statusText:SetTextColor(THEME.success[1], THEME.success[2], THEME.success[3], 1)
                            iconPreview:Hide()
                            placeholder:Show()
                        end
                    end
                end)

                -- Enter 키로도 추가
                inputContainer.editBox:HookScript("OnEnterPressed", function()
                    if option.onAdd then
                        local text = inputContainer:GetText()
                        local success = option.onAdd(text)
                        if success then
                            inputContainer:SetText("")
                            statusText:SetText("Added!")
                            statusText:SetTextColor(THEME.success[1], THEME.success[2], THEME.success[3], 1)
                            iconPreview:Hide()
                            placeholder:Show()
                        end
                    end
                end)

                searchFrame.inputContainer = inputContainer
                searchFrame.statusText = statusText
                searchFrame.iconPreview = iconPreview
                searchFrame.addBtn = addBtn

                widget = searchFrame
                widgetHeight = 60
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
                currentSectionCollapsed = CollapsedGroups[sectionKey] == true  -- nil = 펼침 (기본)
                sectionWidgets[sectionKey] = {}

                -- Set up collapse button click handler
                if widget.collapseBtn then
                    widget.collapseBtn:SetScript("OnClick", function(self)
                        local sk = widget._sectionKey
                        local collapsed = CollapsedGroups[sk] == true  -- nil = 펼침 (기본)

                        if collapsed then
                            -- Expand
                            CollapsedGroups[sk] = false
                            self.arrow:SetText("▼")
                        else
                            -- Collapse
                            CollapsedGroups[sk] = true
                            self.arrow:SetText("▶")
                        end

                        -- 섹션 위젯 show/hide (전체 재렌더 없이 즉시 반영)
                        local secWidgets = sectionWidgets[sk]
                        if secWidgets then
                            for _, sw in ipairs(secWidgets) do
                                if collapsed then
                                    sw:Show()
                                else
                                    sw:Hide()
                                end
                            end
                        end

                        -- 보이는 위젯의 Y 위치 재배치 + contentFrame 높이 재계산
                        C_Timer.After(0, function()
                            -- 범용: contentFrame의 보이는 위젯 위치 재배치
                            if contentFrame and contentFrame.widgets then
                                local newY = 0
                                local spacing = 15
                                for _, w in ipairs(contentFrame.widgets) do
                                    if w:IsShown() then
                                        w:ClearAllPoints()
                                        w:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -newY)
                                        w:SetPoint("RIGHT", contentFrame, "RIGHT", -10, 0)
                                        local h = w:GetHeight() or 28
                                        newY = newY + h + spacing
                                    end
                                end
                                local totalH = newY + 50
                                contentFrame:SetHeight(totalH)
                                -- 스크롤바 업데이트
                                if contentFrame.scrollFrame and contentFrame.scrollFrame.ScrollBar
                                   and contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition then
                                    pcall(contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition)
                                end
                            end

                            -- 커스텀 오라 패널 폴백
                            local cf = _G["DDingUI_ConfigFrame"]
                            local btp = cf and cf.contentArea and cf.contentArea._btPanel
                            if btp and btp.selectedIndex and btp:IsShown() then
                                pcall(function()
                                    local idx = btp.selectedIndex
                                    if type(idx) == "string" then
                                        if btp.RenderStaticPage then
                                            btp:RenderStaticPage(idx)
                                        end
                                    else
                                        local specIdx = GetSpecialization and GetSpecialization() or 1
                                        local specID = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx) or 0
                                        local globalStore = DDingUI.db and DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec
                                        local tb = (globalStore and globalStore[specID]) or (DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.trackedBuffs) or {}
                                        local sel = tb[idx]
                                        if sel and sel.isGroup and btp.RenderGroupSettings then
                                            btp:RenderGroupSettings(idx)
                                        elseif btp.RenderTrackerTabs then
                                            btp:RenderTrackerTabs(idx)
                                        end
                                    end
                                end)
                            end
                        end)
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
                local isCollapsed = CollapsedGroups[groupKey] == true  -- nil = 펼침 (기본)

                -- Foldable group frame (no background)
                local groupFrame = CreateFrame("Frame", nil, contentFrame)
                groupFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                groupFrame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                groupFrame._groupKey = groupKey

                -- 상단 구분선
                local topLine = groupFrame:CreateTexture(nil, "ARTWORK")
                topLine:SetHeight(1)
                topLine:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", 5, 0)
                topLine:SetPoint("TOPRIGHT", groupFrame, "TOPRIGHT", -5, 0)
                topLine:SetColorTexture(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.3)

                -- Collapse/Expand arrow button
                local collapseBtn = CreateFrame("Button", nil, groupFrame)
                collapseBtn:SetSize(20, 20)
                collapseBtn:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", 4, -4)

                local collapseArrow = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                StyleFontString(collapseArrow)
                collapseArrow:SetPoint("CENTER", collapseBtn, "CENTER", 0, 0)
                collapseArrow:SetText(isCollapsed and "+" or "-")
                collapseArrow:SetTextColor(SL.GetColor("dim"))
                collapseBtn.arrow = collapseArrow

                collapseBtn:SetScript("OnEnter", function(self)
                    self.arrow:SetTextColor(SL.GetColor("accent"))
                end)
                collapseBtn:SetScript("OnLeave", function(self)
                    self.arrow:SetTextColor(SL.GetColor("dim"))
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

                            -- Create nested container frame (no background)
                            local nestedGroupFrame = CreateFrame("Frame", nil, contentContainer)
                            nestedGroupFrame:SetPoint("TOPLEFT", contentContainer, "TOPLEFT", 10, -inlineYOffset)
                            nestedGroupFrame:SetPoint("RIGHT", contentContainer, "RIGHT", -10, 0)
                            
                            -- Nested group title
                            local nestedGroupTitle = nestedGroupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            StyleFontString(nestedGroupTitle)
                            nestedGroupTitle:SetPoint("TOPLEFT", nestedGroupFrame, "TOPLEFT", 10, -8)
                            nestedGroupTitle:SetText(nestedGroupName)
                            nestedGroupTitle:SetTextColor(SL.GetColor("accent"))
                            
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
                                        nestedYOffset = nestedYOffset + nestedHeight + 4
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
                            inlineYOffset = inlineYOffset + inlineHeight + 4
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
                    local collapsed = CollapsedGroups[gKey] == true  -- nil = 펼침 (기본)

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

                    -- 부모 레이아웃 재계산 (다음 프레임)
                    C_Timer.After(0, function()
                        -- 범용: contentFrame의 보이는 위젯 위치 재배치
                        if contentFrame and contentFrame.widgets then
                            local newY = 0
                            local spacing = 15
                            for _, w in ipairs(contentFrame.widgets) do
                                if w:IsShown() then
                                    w:ClearAllPoints()
                                    w:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -newY)
                                    w:SetPoint("RIGHT", contentFrame, "RIGHT", -10, 0)
                                    local h = w:GetHeight() or 28
                                    newY = newY + h + spacing
                                end
                            end
                            local totalH = newY + 50
                            contentFrame:SetHeight(totalH)
                            if contentFrame.scrollFrame and contentFrame.scrollFrame.ScrollBar
                               and contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition then
                                pcall(contentFrame.scrollFrame.ScrollBar.UpdateThumbPosition)
                            end
                        end

                        -- 커스텀 오라 패널 폴백
                        local cf = _G["DDingUI_ConfigFrame"]
                        local btp = cf and cf.contentArea and cf.contentArea._btPanel
                        if btp and btp.selectedIndex and btp:IsShown() then
                            pcall(function()
                                if btp.RenderGroupSettings or btp.RenderTrackerTabs then
                                    local specIdx = GetSpecialization and GetSpecialization() or 1
                                    local specID = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx) or 0
                                    local globalStore = DDingUI.db and DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec
                                    local tb = (globalStore and globalStore[specID]) or (DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.trackedBuffs) or {}
                                    local sel = tb[btp.selectedIndex]
                                    if sel and sel.isGroup and btp.RenderGroupSettings then
                                        btp:RenderGroupSettings(btp.selectedIndex)
                                    elseif btp.RenderTrackerTabs then
                                        btp:RenderTrackerTabs(btp.selectedIndex)
                                    end
                                end
                            end)
                        end
                    end)
                end)

                -- Also make title clickable for toggle
                local titleBtn = CreateFrame("Button", nil, groupFrame)
                titleBtn:SetPoint("TOPLEFT", groupTitle, "TOPLEFT", -2, 2)
                titleBtn:SetPoint("BOTTOMRIGHT", groupTitle, "BOTTOMRIGHT", 2, -2)
                titleBtn:SetScript("OnClick", function()
                    collapseBtn:Click()
                end)
                titleBtn:SetScript("OnEnter", function()
                    collapseArrow:SetTextColor(SL.GetColor("accent"))
                end)
                titleBtn:SetScript("OnLeave", function()
                    collapseArrow:SetTextColor(SL.GetColor("dim"))
                end)

                groupFrame:Show()
                table.insert(contentFrame.widgets, groupFrame)
                widget = groupFrame  -- yOffset 증가를 위해 widget에 할당
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
    text:SetTextColor(SL.GetColor("dim"))
    text:SetPoint("LEFT", badge, "LEFT", 8, 0)
    badge.text = text

    -- Auto-size to text
    local textWidth = text:GetStringWidth() or 80
    badge:SetSize(textWidth + 16, 20)
    badge:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset)

    -- Hover effect
    badge:SetScript("OnEnter", function(self)
        self.text:SetTextColor(SL.GetColor("accent"))
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.5)
    end)
    badge:SetScript("OnLeave", function(self)
        self.text:SetTextColor(SL.GetColor("dim"))
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
        titleBar.titleText:SetText(SL.CreateAddonTitle("CDM", "CDM")) -- [STYLE]
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
    profileText:SetTextColor(SL.GetColor("text"))

    local profileArrow = profileDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileArrow:SetFont(globalFontPath, 10, "")
    profileArrow:SetPoint("RIGHT", -4, 0)
    profileArrow:SetText("▼")
    profileArrow:SetTextColor(SL.GetColor("dim"))

    -- 현재 프로필 이름 표시
    local function UpdateProfileText()
        local currentProfile = DDingUI.db:GetCurrentProfile()
        profileText:SetText(currentProfile or "Default")
    end
    UpdateProfileText()

    -- 프로필 드롭다운 호버
    profileDropdown:EnableMouse(true)
    profileDropdown:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(SL.GetColor("accent"))
    end)
    profileDropdown:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
    end)

    -- ============================================
    -- 커스텀 확인 팝업 (FULLSCREEN_DIALOG 스트라타 — config 위에 표시)
    -- ============================================
    local confirmPopup = CreateFrame("Frame", "DDingUI_ProfileConfirmPopup", UIParent, "BackdropTemplate")
    confirmPopup:SetSize(300, 120)
    confirmPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    confirmPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    confirmPopup:SetFrameLevel(500)
    confirmPopup:EnableMouse(true)
    confirmPopup:SetMovable(true)
    confirmPopup:RegisterForDrag("LeftButton")
    confirmPopup:SetScript("OnDragStart", confirmPopup.StartMoving)
    confirmPopup:SetScript("OnDragStop", confirmPopup.StopMovingOrSizing)
    confirmPopup:Hide()

    confirmPopup:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    confirmPopup:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    confirmPopup:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.9)

    local confirmText = confirmPopup:CreateFontString(nil, "OVERLAY")
    confirmText:SetFont(globalFontPath, 12, "")
    confirmText:SetShadowColor(0, 0, 0, 1)
    confirmText:SetShadowOffset(1, -1)
    confirmText:SetPoint("TOP", 0, -18)
    confirmText:SetWidth(260)
    confirmText:SetJustifyH("CENTER")
    confirmText:SetTextColor(1, 0.85, 0.85)
    confirmPopup._text = confirmText

    -- 확인 버튼
    local confirmAcceptBtn = CreateFrame("Button", nil, confirmPopup, "BackdropTemplate")
    confirmAcceptBtn:SetSize(100, 26)
    confirmAcceptBtn:SetPoint("BOTTOMRIGHT", confirmPopup, "BOTTOM", -8, 14)
    CreateBackdrop(confirmAcceptBtn, {0.6, 0.15, 0.15, 0.9}, {0.8, 0.2, 0.2, 0.9})

    local acceptText = confirmAcceptBtn:CreateFontString(nil, "OVERLAY")
    acceptText:SetFont(globalFontPath, 11, "")
    acceptText:SetShadowColor(0, 0, 0, 1)
    acceptText:SetShadowOffset(1, -1)
    acceptText:SetPoint("CENTER", 0, 0)
    acceptText:SetText(ACCEPT or "삭제")
    acceptText:SetTextColor(1, 1, 1)

    confirmAcceptBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.8, 0.2, 0.2, 1)
    end)
    confirmAcceptBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.6, 0.15, 0.15, 0.9)
    end)
    confirmAcceptBtn:SetScript("OnClick", function()
        if confirmPopup._onAccept then
            confirmPopup._onAccept()
        end
        confirmPopup:Hide()
    end)

    -- 취소 버튼
    local confirmCancelBtn = CreateFrame("Button", nil, confirmPopup, "BackdropTemplate")
    confirmCancelBtn:SetSize(100, 26)
    confirmCancelBtn:SetPoint("BOTTOMLEFT", confirmPopup, "BOTTOM", 8, 14)
    CreateBackdrop(confirmCancelBtn, THEME.bgWidget, {0.3, 0.3, 0.3, 0.7})

    local cancelText = confirmCancelBtn:CreateFontString(nil, "OVERLAY")
    cancelText:SetFont(globalFontPath, 11, "")
    cancelText:SetShadowColor(0, 0, 0, 1)
    cancelText:SetShadowOffset(1, -1)
    cancelText:SetPoint("CENTER", 0, 0)
    cancelText:SetText(CANCEL or "취소")
    cancelText:SetTextColor(0.7, 0.7, 0.7)

    confirmCancelBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    end)
    confirmCancelBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.7)
    end)
    confirmCancelBtn:SetScript("OnClick", function()
        confirmPopup:Hide()
    end)

    -- ESC로 닫기
    confirmPopup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    local function ShowConfirmPopup(message, onAccept)
        confirmPopup._text:SetText(message)
        confirmPopup._onAccept = onAccept
        confirmPopup:Show()
    end

    -- 드롭다운 리스트 빌드 함수 (삭제 후 재사용)
    local function BuildProfileList(dropdown)
        local profiles = DDingUI.db:GetProfiles()
        local currentProfile = DDingUI.db:GetCurrentProfile()

        local listFrame = dropdown._listFrame
        if not listFrame then
            listFrame = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
            listFrame:SetFrameStrata("TOOLTIP")
            CreateBackdrop(listFrame, THEME.bgDark, {0, 0, 0, 1})
            dropdown._listFrame = listFrame
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
            local isCurrent = (name == currentProfile)

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
            itemText:SetPoint("RIGHT", -22, 0)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(name)
            if isCurrent then
                itemText:SetTextColor(SL.GetColor("accent"))
            else
                itemText:SetTextColor(SL.GetColor("text"))
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
                if frame.SoftRefresh then
                    C_Timer.After(0.05, function() frame:SoftRefresh() end)
                end
            end)

            -- 삭제 버튼 (현재 프로필이 아닌 경우에만, listFrame 직접 자식)
            if not isCurrent then
                local delBtn = CreateFrame("Button", nil, listFrame)
                delBtn:SetSize(16, 16)
                delBtn:SetPoint("RIGHT", item, "RIGHT", -2, 0)
                delBtn:SetFrameLevel(listFrame:GetFrameLevel() + 10)
                delBtn:RegisterForClicks("AnyUp")

                local delText = delBtn:CreateFontString(nil, "OVERLAY")
                delText:SetFont(globalFontPath, 12, "OUTLINE")
                delText:SetPoint("CENTER", 0, 0)
                delText:SetText("|cff666666✕|r")

                delBtn:SetScript("OnEnter", function(self)
                    delText:SetText("|cffff4444✕|r")
                    item:SetBackdropColor(0.3, 0.08, 0.08, 0.6)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 0)
                    GameTooltip:SetText((L["Delete Profile"] or "프로필 삭제") .. ": " .. name, 1, 0.3, 0.3)
                    GameTooltip:Show()
                end)
                delBtn:SetScript("OnLeave", function(self)
                    delText:SetText("|cff666666✕|r")
                    item:SetBackdropColor(0, 0, 0, 0)
                    GameTooltip:Hide()
                end)
                delBtn:SetScript("OnClick", function()
                    local msg = string.format(
                        (L["Delete profile '%s'?\nThis cannot be undone."] or "프로필 '%s'을(를) 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다."),
                        name
                    )
                    ShowConfirmPopup(msg, function()
                        DDingUI.db:DeleteProfile(name, true)
                        UpdateProfileText()
                        BuildProfileList(dropdown)
                        if frame.SoftRefresh then
                            C_Timer.After(0.05, function() frame:SoftRefresh() end)
                        end
                    end)
                end)

                table.insert(listFrame._items, delBtn)
            end

            table.insert(listFrame._items, item)
            y = y - itemHeight
        end

        listFrame:SetSize(160, math.abs(y) + 4)
        listFrame:ClearAllPoints()
        listFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        listFrame:Show()

        -- 외부 클릭 시 닫기 (확인 팝업이 떠있으면 닫지 않음)
        listFrame:SetScript("OnUpdate", function(self)
            if confirmPopup:IsShown() then return end
            if not self:IsMouseOver() and not profileDropdown:IsMouseOver() then
                if IsMouseButtonDown("LeftButton") then
                    self:Hide()
                end
            end
        end)
    end

    -- 프로필 드롭다운 클릭 → 프로필 목록 팝업
    profileDropdown:SetScript("OnMouseDown", function(self)
        if self._listFrame and self._listFrame:IsShown() then
            self._listFrame:Hide()
            return
        end
        BuildProfileList(self)
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
    scaleLabel:SetTextColor(SL.GetColor("dim"))

    local currentScale = (DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.general and DDingUI.db.profile.general.guiScale) or 1.0
    local scaleValue = scaleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleValue:SetFont(globalFontPath, 11, "")
    scaleValue:SetShadowColor(0, 0, 0, 1)
    scaleValue:SetShadowOffset(1, -1)
    scaleValue:SetPoint("RIGHT", scaleContainer, "RIGHT", 0, 0)
    scaleValue:SetText(string.format("%.0f%%", currentScale * 100))
    scaleValue:SetTextColor(SL.GetColor("text"))

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
    scaleSlider:SetBackdropColor(SL.GetColor("widget"))
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
        self:SetBackdropBorderColor(SL.GetColor("accent"))
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

    -- ============================================
    -- 편집 모드(이동모드) 토글 버튼 (검색 왼쪽) -- [12.0.1]
    -- ============================================
    local editModeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate") -- [12.0.1]
    editModeBtn:SetSize(62, 20)
    editModeBtn:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    CreateBackdrop(editModeBtn, THEME.bgWidget, {0, 0, 0, 1})

    local editModeText = editModeBtn:CreateFontString(nil, "OVERLAY") -- [12.0.1]
    editModeText:SetFont(globalFontPath, 11, "")
    editModeText:SetShadowColor(0, 0, 0, 1)
    editModeText:SetShadowOffset(1, -1)
    editModeText:SetPoint("CENTER", 0, 0)
    editModeText:SetText(L["Edit Mode"] or "Edit Mode")
    editModeText:SetTextColor(SL.GetColor("dim"))

    editModeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(SL.GetColor("accent"))
        editModeText:SetTextColor(SL.GetColor("accent"))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
        GameTooltip:SetText(L["Edit Mode"] or "Edit Mode", 1, 1, 1)
        GameTooltip:AddLine(L["Toggle draggable movers for all CDM frames"] or "Toggle draggable movers for all CDM frames", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    editModeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        editModeText:SetTextColor(SL.GetColor("dim"))
        GameTooltip:Hide()
    end)
    editModeBtn:SetScript("OnClick", function()
        -- 설정 창 닫기
        frame:Hide()
        -- 이동모드 토글
        if DDingUI.Movers and DDingUI.Movers.ToggleConfigMode then
            DDingUI.Movers:ToggleConfigMode()
        end
    end)

    -- 크기 슬라이더를 편집 버튼 왼쪽에 배치 -- [12.0.1]
    scaleContainer:SetPoint("RIGHT", editModeBtn, "LEFT", -10, 0)
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
    searchEditBox:SetTextColor(SL.GetColor("text"))

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
        local activeSubTabIndex = nil
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
                        activeSubTabIndex = i
                        break
                    end
                end
            end
        end

        -- [FIX] 서브탭이 활성 상태이면 서브탭 콘텐츠만 다시 그림 (깜빡임 방지)
        if activeSubTabKey and self.scrollChild and self.scrollChild.subScrollChild then
            local currentOption = lookup.option
            local subOption = currentOption and currentOption.args and currentOption.args[activeSubTabKey]
            if subOption then
                local subScrollChild = self.scrollChild.subScrollChild
                if subScrollChild.widgets then
                    for j = #subScrollChild.widgets, 1, -1 do
                        local widget = subScrollChild.widgets[j]
                        if widget then widget:Hide(); widget:SetParent(nil) end
                    end
                end
                subScrollChild.widgets = {}
                RenderOptions(subScrollChild, subOption, {unpack(lookup.path), activeSubTabKey}, self)
                return
            end
        end

        self:SetContent(lookup.option, lookup.path)

        -- Restore sub-tab (SetContent 호출 시 폴백)
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

    -- 재귀 트리 빌더: childGroups가 "tab" 또는 "select"이면 하위 그룹을 트리 자식으로 변환
    local function BuildTreeChildren(parentOption, parentPath)
        local children = {}
        local sortedChildren = {}
        for childKey, childOption in pairs(parentOption.args or {}) do
            if childOption.type == "group" then
                local childHidden = false
                if childOption.hidden then
                    if type(childOption.hidden) == "function" then
                        childHidden = childOption.hidden()
                    else
                        childHidden = childOption.hidden
                    end
                end
                if not childHidden then
                    table.insert(sortedChildren, {key = childKey, option = childOption, order = childOption.order or 999})
                end
            end
        end
        table.sort(sortedChildren, function(a, b) return a.order < b.order end)

        for _, child in ipairs(sortedChildren) do
            local childName = child.option.name or child.key
            if type(childName) == "function" then childName = childName() end
            local childPath = {}
            for _, p in ipairs(parentPath) do childPath[#childPath + 1] = p end
            childPath[#childPath + 1] = child.key
            local childTreeKey = table.concat(childPath, ".")

            local childCG = child.option.childGroups
            local grandChildren = nil
            if childCG == "select" and child.option.args then
                grandChildren = BuildTreeChildren(child.option, childPath)
            end

            table.insert(children, {
                text = childName,
                key = childTreeKey,
                icon = child.option.icon,
                iconCoords = child.option.iconCoords,
                desc = child.option.desc,
                disabled = child.option.disabled,
                children = (grandChildren and #grandChildren > 0) and grandChildren or nil,
            })
            frame._optionLookup[childTreeKey] = {
                option = child.option,
                path = childPath,
            }

            -- 부모-자식 포워딩: 이 자식이 grandChildren을 가지면, 클릭 시 첫 손자로 이동하도록 매핑
            if grandChildren and #grandChildren > 0 then
                frame._optionLookup[childTreeKey] = frame._optionLookup[grandChildren[1].key]
            end
        end
        return children
    end

    local sortedGroups = {}
    for key, option in pairs(options.args or {}) do
        if option.type == "group" then
            local isHidden = false
            if option.hidden then
                if type(option.hidden) == "function" then
                    isHidden = option.hidden()
                else
                    isHidden = option.hidden
                end
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

        local cg = item.option.childGroups
        if cg == "tab" or cg == "select" then
            -- 이 그룹의 하위 항목들을 트리 자식으로 재귀 변환
            local children = BuildTreeChildren(item.option, {item.key})

            -- 부모 키 → 첫 번째 자식으로 매핑
            if #children > 0 then
                frame._optionLookup[item.key] = frame._optionLookup[children[1].key]
            end

            table.insert(menuData, {
                text = displayName,
                key = item.key,
                icon = item.option.icon,            -- Phase 2: 스펠 아이콘
                iconCoords = item.option.iconCoords,
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
    -- [12.0.1] 기본 CDM 그룹 (이름 변경 불가)
    local CDM_BUILTIN_GROUPS = { ["Cooldowns"] = true, ["Buffs"] = true, ["Utility"] = true }

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
                -- 부모 노드 클릭 → 첫 번째 자식 선택 (재귀 검색)
                local function FindAndSelectFirstChild(items)
                    for _, item in ipairs(items) do
                        if item.key == key and item.children and #item.children > 0 then
                            tree:SetSelected(item.children[1].key)
                            return true
                        end
                        if item.children then
                            if FindAndSelectFirstChild(item.children) then return true end
                        end
                    end
                    return false
                end
                FindAndSelectFirstChild(menuData)
                return
            end

            frame:SetContent(lookup.option, lookup.path)
            frame.currentTab = key
            frame.currentPath = lookup.path
            frame.configOptions = options
        end,
        -- [12.0.1+WA] 우클릭 → 컨텍스트 메뉴 (CDM 그룹 이름 변경 + BT 트래커 조작)
        onRightClick = function(key, text, btn)
            -- ── CDM 그룹 이름 변경 ──
            local groupName = key:match("^groupSystem%.group_(.+)$")
            if groupName then
                if CDM_BUILTIN_GROUPS[groupName] then return end
                StaticPopup_Show("DDINGUI_RENAME_GROUP", nil, nil, {
                    oldName = groupName,
                    onAccept = function(newName)
                        if newName == groupName then return end
                        if DDingUI.GroupManager and DDingUI.GroupManager:RenameGroup(groupName, newName) then
                            if frame.RebuildTreeMenu then
                                frame:RebuildTreeMenu("groupSystem.group_" .. newName)
                            end
                            if DDingUI.GroupSystem and DDingUI.GroupSystem.Refresh then
                                DDingUI.GroupSystem:Refresh()
                            end
                        end
                    end,
                })
                return
            end

            -- ── BT 트래커 우클릭: WeakAuras-equivalent context menu ──
            -- 키 = "group_X.buff_N" 또는 "group_X.buff_N.displayTab" 등
            local buffIndex = key:match("%.buff_(%d+)")
            if not buffIndex then return end
            buffIndex = tonumber(buffIndex)
            if not buffIndex then return end

            -- 컨텍스트 메뉴 프레임 (재사용)
            if not frame._contextMenu then
                local ctx = CreateFrame("Frame", "DDingUI_BT_ContextMenu", UIParent, "BackdropTemplate")
                ctx:SetFrameStrata("FULLSCREEN_DIALOG")
                ctx:SetFrameLevel(100)
                ctx:SetSize(200, 10)
                ctx:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1,
                })
                ctx:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
                ctx:SetBackdropBorderColor(0, 0, 0, 1)
                ctx:Hide()
                ctx._buttonPool = {}
                ctx._sepPool = {}

                -- Click-away catcher
                local catcher = CreateFrame("Button", nil, ctx)
                catcher:SetFrameStrata("FULLSCREEN_DIALOG")
                catcher:SetFrameLevel(99)
                catcher:SetAllPoints(UIParent)
                catcher:SetScript("OnClick", function() ctx:Hide() end)
                catcher:EnableMouseWheel(true)
                catcher:SetScript("OnMouseWheel", function() ctx:Hide() end)
                catcher:Hide()
                ctx._catcher = catcher

                ctx.Show_ = ctx.Show
                ctx.Show = function(self)
                    self._catcher:Show()
                    self:Show_()
                end
                ctx.Hide_ = ctx.Hide
                ctx.Hide = function(self)
                    self._catcher:Hide()
                    self:Hide_()
                end

                frame._contextMenu = ctx
            end

            local ctx = frame._contextMenu
            ctx:Hide()

            -- Build menu items
            local menuItems = {}

            -- 1. 복제
            menuItems[#menuItems + 1] = {
                text = "|cff88ff88▣|r 복제",
                func = function()
                    DDingUI.DuplicateTrackedBuff(buffIndex)
                    ctx:Hide()
                end,
            }
            -- 2. 이름 변경
            menuItems[#menuItems + 1] = {
                text = "|cff88ccff✎|r 이름 변경",
                func = function()
                    ctx:Hide()
                    StaticPopup_Show("DDINGUI_RENAME_TRACKER", nil, nil, {
                        buffIndex = buffIndex,
                        currentName = text,
                    })
                end,
            }
            -- 3. 위로 이동
            menuItems[#menuItems + 1] = {
                text = "|cffcccccc▲|r 위로 이동",
                func = function()
                    DDingUI.MoveTrackedBuffUp(buffIndex)
                    ctx:Hide()
                end,
            }
            -- 4. 아래로 이동
            menuItems[#menuItems + 1] = {
                text = "|cffcccccc▼|r 아래로 이동",
                func = function()
                    DDingUI.MoveTrackedBuffDown(buffIndex)
                    ctx:Hide()
                end,
            }
            -- 5. separator
            menuItems[#menuItems + 1] = { separator = true }
            -- 6. 복사 서브메뉴
            menuItems[#menuItems + 1] = {
                text = "|cffffcc44⧉|r 전체 설정 복사",
                func = function()
                    DDingUI.CopyTrackedBuffSettings(buffIndex, "all")
                    ctx:Hide()
                end,
            }
            menuItems[#menuItems + 1] = {
                text = "    디스플레이 복사",
                func = function()
                    DDingUI.CopyTrackedBuffSettings(buffIndex, "display")
                    ctx:Hide()
                end,
            }
            menuItems[#menuItems + 1] = {
                text = "    활성 조건 복사",
                func = function()
                    DDingUI.CopyTrackedBuffSettings(buffIndex, "trigger")
                    ctx:Hide()
                end,
            }
            menuItems[#menuItems + 1] = {
                text = "    조건 복사",
                func = function()
                    DDingUI.CopyTrackedBuffSettings(buffIndex, "conditions")
                    ctx:Hide()
                end,
            }
            menuItems[#menuItems + 1] = {
                text = "    불러오기 복사",
                func = function()
                    DDingUI.CopyTrackedBuffSettings(buffIndex, "load")
                    ctx:Hide()
                end,
            }
            -- 7. 붙여넣기 (클립보드에 데이터 있을 때만)
            if DDingUI.HasTrackedBuffClipboard and DDingUI.HasTrackedBuffClipboard() then
                menuItems[#menuItems + 1] = {
                    text = "|cff44ff44✓|r " .. DDingUI.GetTrackedBuffPasteLabel(),
                    func = function()
                        DDingUI.PasteTrackedBuffSettings(buffIndex)
                        ctx:Hide()
                    end,
                }
            end
            -- 8. separator
            menuItems[#menuItems + 1] = { separator = true }
            -- 9. 내보내기
            menuItems[#menuItems + 1] = {
                text = "|cff88aaff↗|r 내보내기",
                func = function()
                    ctx:Hide()
                    local exportStr = DDingUI.ExportTrackedBuff(buffIndex)
                    if exportStr then
                        StaticPopup_Show("DDINGUI_EXPORT_TRACKER", nil, nil, {
                            exportString = exportStr,
                        })
                    end
                end,
            }
            -- 9.5 가져오기
            menuItems[#menuItems + 1] = {
                text = "|cff88aaff↙|r 가져오기",
                func = function()
                    ctx:Hide()
                    StaticPopup_Show("DDINGUI_IMPORT_TRACKER")
                end,
            }
            -- 10. 활성/비활성 토글
            menuItems[#menuItems + 1] = { separator = true }
            local isDisabled = DDingUI.IsTrackedBuffDisabled and DDingUI.IsTrackedBuffDisabled(buffIndex) or false
            menuItems[#menuItems + 1] = {
                text = isDisabled and "|cff44ff44●|r 활성화" or "|cff888888●|r 비활성화",
                func = function()
                    DDingUI.ToggleTrackedBuffEnabled(buffIndex)
                    ctx:Hide()
                end,
            }
            -- 11. 삭제 (맨 마지막, 빨간색)
            menuItems[#menuItems + 1] = { separator = true }
            menuItems[#menuItems + 1] = {
                text = "|cffff4444✕|r 삭제",
                func = function()
                    DDingUI.RemoveTrackedBuff(buffIndex)
                    ctx:Hide()
                end,
            }

            -- Create/reuse rows from separate pools
            local ROW_H = 22
            local SEP_H = 8
            local yOff = -4
            local btnIdx, sepIdx = 0, 0
            if not ctx._buttonPool then ctx._buttonPool = {} end
            if not ctx._sepPool then ctx._sepPool = {} end
            -- hide all pooled
            for _, b in ipairs(ctx._buttonPool) do b:Hide() end
            for _, s in ipairs(ctx._sepPool) do s:Hide() end

            for i, item in ipairs(menuItems) do
                if item.separator then
                    sepIdx = sepIdx + 1
                    local sep = ctx._sepPool[sepIdx]
                    if not sep then
                        sep = ctx:CreateTexture(nil, "ARTWORK")
                        ctx._sepPool[sepIdx] = sep
                    end
                    sep:SetHeight(1)
                    sep:ClearAllPoints()
                    sep:SetPoint("TOPLEFT", ctx, "TOPLEFT", 8, yOff - 3)
                    sep:SetPoint("TOPRIGHT", ctx, "TOPRIGHT", -8, yOff - 3)
                    sep:SetColorTexture(0.3, 0.3, 0.35, 0.6)
                    sep:Show()
                    yOff = yOff - SEP_H
                else
                    btnIdx = btnIdx + 1
                    local row = ctx._buttonPool[btnIdx]
                    if not row then
                        row = CreateFrame("Button", nil, ctx)
                        row:SetHeight(ROW_H)
                        row._bg = row:CreateTexture(nil, "BACKGROUND")
                        row._bg:SetAllPoints()
                        row._bg:SetColorTexture(0, 0, 0, 0)
                        row._text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        row._text:SetPoint("LEFT", 10, 0)
                        row._text:SetPoint("RIGHT", -10, 0)
                        row._text:SetJustifyH("LEFT")
                        ctx._buttonPool[btnIdx] = row
                    end
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", ctx, "TOPLEFT", 2, yOff)
                    row:SetPoint("TOPRIGHT", ctx, "TOPRIGHT", -2, yOff)
                    row._text:SetText(item.text)
                    row:SetScript("OnClick", item.func)
                    row:SetScript("OnEnter", function(self) self._bg:SetColorTexture(0.2, 0.3, 0.5, 0.4) end)
                    row:SetScript("OnLeave", function(self) self._bg:SetColorTexture(0, 0, 0, 0) end)
                    row:Show()
                    yOff = yOff - ROW_H
                end
            end

            ctx:SetHeight(math.abs(yOff) + 8)

            -- Position near the clicked button
            ctx:ClearAllPoints()
            ctx:SetPoint("TOPLEFT", btn, "TOPRIGHT", 2, 0)
            ctx:Show()
        end,
    })
    frame.treeMenu = tree
    frame._fullMenuData = menuData

    -- [12.0.1] 트리 메뉴 재빌드 (그룹 생성/삭제/이름변경 후 호출)
    frame.RebuildTreeMenu = function(self, selectKey)
        -- 옵션 테이블 재생성
        if ns.CreateGroupSystemOptions then
            options.args.groupSystem = ns.CreateGroupSystemOptions(1)
        end
        DDingUI.configOptions = options

        -- menuData + _optionLookup 재빌드
        local newMenuData = {}
        self._optionLookup = {}

        local sorted = {}
        for k, opt in pairs(options.args or {}) do
            if opt.type == "group" then
                local isHidden = false
                if opt.hidden then
                    if type(opt.hidden) == "function" then
                        isHidden = opt.hidden()
                    else
                        isHidden = opt.hidden
                    end
                end
                if not isHidden then
                    table.insert(sorted, {key = k, option = opt, order = opt.order or 999})
                end
            end
        end
        table.sort(sorted, function(a, b) return a.order < b.order end)

        -- RebuildTreeChildren: childGroups="select" 재귀 지원 (BuffTracker 그룹 포함)
        local function RebuildTreeChildren(parentOption, parentPath)
            local children = {}
            local sortedCh = {}
            for childKey, childOption in pairs(parentOption.args or {}) do
                if childOption.type == "group" then
                    local childHidden = false
                    if childOption.hidden then
                        if type(childOption.hidden) == "function" then
                            childHidden = childOption.hidden()
                        else
                            childHidden = childOption.hidden
                        end
                    end
                    if not childHidden then
                        table.insert(sortedCh, {key = childKey, option = childOption, order = childOption.order or 999})
                    end
                end
            end
            table.sort(sortedCh, function(a, b) return a.order < b.order end)

            for _, ch in ipairs(sortedCh) do
                local childName = ch.option.name or ch.key
                if type(childName) == "function" then childName = childName() end
                local childPath = {}
                for _, p in ipairs(parentPath) do childPath[#childPath + 1] = p end
                childPath[#childPath + 1] = ch.key
                local childTreeKey = table.concat(childPath, ".")

                -- 재귀: childGroups="select"인 경우 손자 노드도 변환
                local grandChildren = nil
                if ch.option.childGroups == "select" and ch.option.args then
                    grandChildren = RebuildTreeChildren(ch.option, childPath)
                end

                table.insert(children, {
                    text = childName,
                    key = childTreeKey,
                    icon = ch.option.icon,
                    iconCoords = ch.option.iconCoords,
                    desc = ch.option.desc,
                    disabled = ch.option.disabled,
                    children = (grandChildren and #grandChildren > 0) and grandChildren or nil,
                })
                self._optionLookup[childTreeKey] = { option = ch.option, path = childPath }

                if grandChildren and #grandChildren > 0 then
                    self._optionLookup[childTreeKey] = self._optionLookup[grandChildren[1].key]
                end
            end
            return children
        end

        for _, item in ipairs(sorted) do
            local displayName = item.option.name or item.key
            if type(displayName) == "function" then displayName = displayName() end

            local cg = item.option.childGroups
            if cg == "tab" or cg == "select" then
                local children = RebuildTreeChildren(item.option, {item.key})
                if #children > 0 then
                    self._optionLookup[item.key] = self._optionLookup[children[1].key]
                end
                table.insert(newMenuData, {
                    text = displayName,
                    key = item.key,
                    icon = item.option.icon,
                    iconCoords = item.option.iconCoords,
                    children = children,
                })
            else
                table.insert(newMenuData, { text = displayName, key = item.key })
                self._optionLookup[item.key] = { option = item.option, path = {item.key} }
            end
        end

        menuData = newMenuData
        self._fullMenuData = newMenuData
        tree:SetMenuData(newMenuData, false)

        -- 선택 복원
        local targetKey = selectKey or self.currentTab
        if targetKey and self._optionLookup[targetKey] then
            tree:SetSelected(targetKey)
            if tree.onSelect then tree.onSelect(targetKey) end
        elseif #newMenuData > 0 then
            local firstKey
            if newMenuData[1].children and #newMenuData[1].children > 0 then
                firstKey = newMenuData[1].children[1].key
            else
                firstKey = newMenuData[1].key
            end
            tree:SetSelected(firstKey)
            if tree.onSelect then tree.onSelect(firstKey) end
        end
    end

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
                        matchedChildren[#matchedChildren + 1] = {
                            text = ch.text, key = ch.key,
                            icon = ch.icon, iconCoords = ch.iconCoords,
                            children = ch.children,
                        }
                    end
                end
                if parentMatch then
                    filtered[#filtered + 1] = {
                        text = item.text, key = item.key,
                        icon = item.icon, iconCoords = item.iconCoords,
                        children = item.children,
                    }
                elseif #matchedChildren > 0 then
                    filtered[#filtered + 1] = {
                        text = item.text, key = item.key,
                        icon = item.icon, iconCoords = item.iconCoords,
                        children = matchedChildren,
                    }
                end
            else
                if parentMatch or OptionContainsText(item.key, query) then
                    filtered[#filtered + 1] = {
                        text = item.text, key = item.key,
                        icon = item.icon, iconCoords = item.iconCoords,
                    }
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
-- Shared Styled Widget Helpers -- [REFACTOR] Ayije 패턴 이식용 공용 위젯
-- ============================================

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
-- Modal Overlay Utility -- [REFACTOR] Ayije 패턴 이식
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
-- Expand/Collapse Row Utility -- [REFACTOR] Ayije 아코디언 패턴 이식
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

    -- Styled Widget Helpers -- [REFACTOR] Ayije 패턴 이식용
    CreateStyledButton = CreateStyledButton,
    CreateStyledToggle = CreateStyledToggle,
    CreateStyledInput = CreateStyledInput,
    CreateStyledDropdown = CreateStyledDropdown,
    CreateModalOverlay = CreateModalOverlay,

    -- Expand/Collapse Row -- [REFACTOR] Ayije 아코디언 패턴
    CreateExpandableRow = CreateExpandableRow,
    RepositionExpandableRows = RepositionExpandableRows,
    ROW_HEIGHT_COLLAPSED = ROW_HEIGHT_COLLAPSED,
    ROW_HEIGHT_EXPANDED = ROW_HEIGHT_EXPANDED,
    ROW_SPACING = ROW_SPACING,
}
