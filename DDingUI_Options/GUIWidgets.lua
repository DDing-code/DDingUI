local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local LSM = LibStub("LibSharedMedia-3.0")

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
}

-- [FIX] 드래그&드롭 순서 변경 상태
local DragState = {
    active = false,
    sourceData = nil,   -- { groupKey, iconKey, iconIdx }
    sourceBtn = nil,
    ghostFrame = nil,
}

local function IsDropAfterTarget(button)
    if not button or not button.GetTop or not button.GetBottom then return false end
    local top = button:GetTop()
    local bottom = button:GetBottom()
    if not top or not bottom then return false end

    local _, cursorY = GetCursorPosition()
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not scale or scale == 0 then scale = 1 end
    local cursorUIY = cursorY / scale
    return cursorUIY < ((top + bottom) * 0.5)
end

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

-- [DDINGUI] StyleLib v2 모듈 참조
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

    -- Template-less FontStrings can report an invalid transient height.
    if type(size) ~= "number" or size <= 0 or size > 96 then
        size = 12
    end

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

local function IsMediaFilePath(value)
    if type(value) ~= "string" then return false end
    local lower = value:lower()
    return lower:match("^interface\\")
        or lower:match("^fonts\\")
        or lower:match("%.ogg$")
        or lower:match("%.mp3$")
        or lower:match("%.wav$")
        or lower:match("%.ttf$")
        or lower:match("%.otf$")
        or lower:match("%.tga$")
        or lower:match("%.blp$")
end

local function ResolveOptionMediaType(option, values)
    local dialogControl = type(option.dialogControl) == "string"
        and option.dialogControl:lower()
        or ""
    if dialogControl:find("font", 1, true) then
        return "font"
    elseif dialogControl:find("statusbar", 1, true) then
        return "statusbar"
    elseif dialogControl:find("background", 1, true) then
        return "background"
    elseif dialogControl:find("border", 1, true) then
        return "border"
    elseif dialogControl:find("sound", 1, true) then
        return "sound"
    end

    local mediaLists = _G.AceGUIWidgetLSMlists
    if mediaLists then
        for _, mediaType in ipairs({ "font", "statusbar", "background", "border", "sound" }) do
            if values == mediaLists[mediaType] then
                return mediaType
            end
        end
    end
    return option.mediaType
end

local function ResolveMediaPath(mediaType, key, value)
    if not mediaType or key == nil or key == "" or key == "None" or key == "none" then
        return nil
    end
    local path = LSM and LSM:Fetch(mediaType, key, true)
    if path then
        return path
    end
    if IsMediaFilePath(value) then
        return value
    end
    return nil
end

local function IsTextureMedia(mediaType)
    return mediaType == "statusbar" or mediaType == "background" or mediaType == "border"
end

local function PlayMediaPreview(path)
    if not path then return end
    PlaySoundFile(path, "Master")
end

local function StyleSoundPreviewButton(button)
    if not button then return end
    button:SetNormalAtlas("common-icon-sound")
    button:SetPushedAtlas("common-icon-sound-pressed")
end

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
    local selectedFontPath, selectedFontSize, selectedFontFlags = selectedText:GetFont()

    local selectedMediaPreview

    -- 화살표 아이콘
    local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(arrow)
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
    arrow:SetText("▼")
    arrow:SetTextColor(SL.GetColor("dim"))
    dropdown.arrow = arrow

    local soundPreviewButton

    -- 드롭다운 리스트 프레임
    local listFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    listFrame:SetWidth(width)
    listFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    listFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    listFrame:SetFrameLevel(300)
    listFrame:SetClampedToScreen(true)
    listFrame:SetToplevel(true)
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
    dropdown.mediaType = nil
    dropdown.values = nil
    dropdown.searchable = false
    local searchEdit
    local searchPlaceholder
    local noSearchResults

    local function EnsureSelectedMediaPreview()
        if selectedMediaPreview then return selectedMediaPreview end
        selectedMediaPreview = dropdown:CreateTexture(nil, "ARTWORK")
        selectedMediaPreview:SetSize(58, 12)
        selectedMediaPreview:SetPoint("LEFT", dropdown, "LEFT", 7, 0)
        dropdown.selectedMediaPreview = selectedMediaPreview
        return selectedMediaPreview
    end

    local function EnsureSoundPreviewButton()
        if soundPreviewButton then return soundPreviewButton end
        soundPreviewButton = CreateFrame("Button", nil, dropdown)
        soundPreviewButton:SetSize(18, 18)
        soundPreviewButton:SetPoint("RIGHT", dropdown, "RIGHT", -18, 0)
        StyleSoundPreviewButton(soundPreviewButton)
        soundPreviewButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(rawget(L, "Preview Sound") or "Preview sound")
            GameTooltip:Show()
        end)
        soundPreviewButton:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        soundPreviewButton:SetScript("OnClick", function()
            local values = dropdown.values
            local value = values and values[dropdown.currentValue]
            PlayMediaPreview(ResolveMediaPath("sound", dropdown.currentValue, value))
        end)
        dropdown.soundPreviewButton = soundPreviewButton
        return soundPreviewButton
    end

    local function ResetSelectedTextFont()
        if selectedFontPath then
            selectedText:SetFont(selectedFontPath, selectedFontSize or 11, selectedFontFlags or "")
        end
    end

    local function UpdateSelectedMedia(key, value)
        if selectedMediaPreview then selectedMediaPreview:Hide() end
        if soundPreviewButton then soundPreviewButton:Hide() end
        selectedText:ClearAllPoints()
        selectedText:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
        selectedText:SetPoint("RIGHT", dropdown, "RIGHT", -20, 0)
        ResetSelectedTextFont()

        local mediaType = dropdown.mediaType
        local path = ResolveMediaPath(mediaType, key, value)
        if IsTextureMedia(mediaType) and path then
            selectedMediaPreview = EnsureSelectedMediaPreview()
            selectedMediaPreview:SetTexture(path)
            selectedMediaPreview:Show()
            selectedText:ClearAllPoints()
            selectedText:SetPoint("LEFT", selectedMediaPreview, "RIGHT", 7, 0)
            selectedText:SetPoint("RIGHT", dropdown, "RIGHT", -20, 0)
        elseif mediaType == "sound" and path then
            soundPreviewButton = EnsureSoundPreviewButton()
            soundPreviewButton:Show()
            selectedText:ClearAllPoints()
            selectedText:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
            selectedText:SetPoint("RIGHT", dropdown, "RIGHT", -40, 0)
        end
    end

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

    local SEARCH_HEIGHT = 24
    local SEARCH_INSET = SEARCH_HEIGHT + 8

    local function EnsureSearchBox()
        if searchEdit then return searchEdit end

        searchEdit = CreateFrame("EditBox", nil, listFrame, "BackdropTemplate")
        searchEdit:SetHeight(SEARCH_HEIGHT)
        searchEdit:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 4, -4)
        searchEdit:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -4, -4)
        searchEdit:SetFrameLevel(listFrame:GetFrameLevel() + 5)
        searchEdit:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        searchEdit:SetBackdropColor(0, 0, 0, 0.45)
        searchEdit:SetBackdropBorderColor(SL.GetColor("border"))
        searchEdit:SetAutoFocus(false)
        searchEdit:SetMaxLetters(60)
        searchEdit:SetTextInsets(7, 24, 0, 0)
        searchEdit:SetTextColor(SL.GetColor("text"))
        searchEdit:SetJustifyH("LEFT")
        local searchFont = DDingUI:GetGlobalFont() or globalFontPath
        searchEdit:SetFont(searchFont, 11, "")

        searchPlaceholder = searchEdit:CreateFontString(nil, "OVERLAY")
        searchPlaceholder:SetFont(searchFont, 11, "")
        searchPlaceholder:SetPoint("LEFT", searchEdit, "LEFT", 7, 0)
        searchPlaceholder:SetText(rawget(L, "Search...") or "Search...")
        searchPlaceholder:SetTextColor(SL.GetColor("dim"))

        local searchIcon = searchEdit:CreateTexture(nil, "OVERLAY")
        searchIcon:SetSize(13, 13)
        searchIcon:SetPoint("RIGHT", searchEdit, "RIGHT", -7, 0)
        searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
        searchIcon:SetVertexColor(SL.GetColor("dim"))

        noSearchResults = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        StyleFontString(noSearchResults)
        noSearchResults:SetPoint("TOP", searchEdit, "BOTTOM", 0, -11)
        noSearchResults:SetText(rawget(L, "No search results") or "No search results")
        noSearchResults:SetTextColor(SL.GetColor("dim"))
        noSearchResults:Hide()

        searchEdit:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(SL.GetColor("accent"))
        end)
        searchEdit:SetScript("OnLeave", function(self)
            if not self:HasFocus() then
                self:SetBackdropBorderColor(SL.GetColor("border"))
            end
        end)
        searchEdit:SetScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(SL.GetColor("accent"))
        end)
        searchEdit:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(SL.GetColor("border"))
        end)
        searchEdit:SetScript("OnEscapePressed", function(self)
            if self:GetText() ~= "" then
                self:SetText("")
            else
                self:ClearFocus()
            end
        end)
        searchEdit:SetScript("OnEnterPressed", function()
            for _, item in ipairs(dropdown.items) do
                if item:IsShown() then
                    item:Click()
                    return
                end
            end
        end)
        searchEdit:SetScript("OnTextChanged", function(self)
            if searchPlaceholder then
                searchPlaceholder:SetShown(self:GetText() == "")
            end
            if dropdown.ApplyFilter then
                dropdown:ApplyFilter(self:GetText())
            end
        end)
        dropdown.searchEdit = searchEdit
        return searchEdit
    end

    local function ConfigureSearch(enabled)
        dropdown.searchable = enabled == true

        scrollFrame:ClearAllPoints()
        scrollbarTrack:ClearAllPoints()
        if dropdown.searchable then
            EnsureSearchBox():Show()
            scrollFrame:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, -SEARCH_INSET)
            scrollbarTrack:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, -SEARCH_INSET)
        else
            if searchEdit then
                searchEdit:ClearFocus()
                searchEdit:Hide()
            end
            if noSearchResults then noSearchResults:Hide() end
            scrollFrame:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, -2)
            scrollbarTrack:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, -2)
        end
        scrollFrame:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -2 - scrollbarWidth - 2, 2)
        scrollbarTrack:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -2, 2)
    end

    function dropdown:ApplyFilter(rawQuery)
        local query = tostring(rawQuery or ""):lower()
        query = query:match("^%s*(.-)%s*$") or ""
        local yOffset = 2
        local visibleCount = 0

        for _, item in ipairs(self.items) do
            local matches = query == ""
                or (item.searchText and item.searchText:find(query, 1, true) ~= nil)
            item:ClearAllPoints()
            if matches then
                item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, -yOffset)
                item:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -2, -yOffset)
                item:Show()
                yOffset = yOffset + item:GetHeight()
                visibleCount = visibleCount + 1
            else
                item:Hide()
            end
        end

        scrollChild:SetHeight(math.max(1, yOffset + 2))
        local visibleRows = math.min(visibleCount, maxVisibleItems)
        local rowHeight = self.mediaType and 24 or itemHeight
        local emptyRows = self.searchable and visibleCount == 0 and 1 or 0
        local listHeight = (self.searchable and SEARCH_INSET or 0)
            + math.max(visibleRows, emptyRows) * rowHeight
            + 6
        listFrame:SetHeight(math.max(6, listHeight))
        if noSearchResults then
            noSearchResults:SetShown(self.searchable and visibleCount == 0)
        end

        scrollFrame:SetVerticalScroll(0)
        UpdateScrollbarThumb()
    end

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
            if self._itemsDirty then
                self:SetOptions(self.values, self.currentValue, self.mediaType, self.searchable, true)
            end
            activeDropdown = self
            listFrame:Show()
        end
    end)

    -- 리스트 프레임 닫기 처리
    listFrame:SetScript("OnHide", function()
        dropdown:SetBackdropBorderColor(0, 0, 0, 1)  -- UF 통일
        arrow:SetTextColor(SL.GetColor("dim"))
        if searchEdit then searchEdit:ClearFocus() end
    end)
    dropdown:HookScript("OnHide", function()
        listFrame:Hide()
        if activeDropdown == dropdown then
            activeDropdown = nil
        end
    end)

    -- 외부 클릭 시 닫기
    listFrame:SetScript("OnShow", function(self)
        if dropdown._itemsDirty then
            dropdown:SetOptions(
                dropdown.values,
                dropdown.currentValue,
                dropdown.mediaType,
                dropdown.searchable,
                true
            )
        end
        local uiScale = UIParent:GetEffectiveScale()
        local dropdownScale = dropdown:GetEffectiveScale()
        if uiScale and uiScale > 0 and dropdownScale and dropdownScale > 0 then
            self:SetScale(dropdownScale / uiScale)
        end
        scrollFrame:SetVerticalScroll(0)
        if dropdown.searchable and searchEdit then
            if searchEdit:GetText() ~= "" then
                searchEdit:SetText("")
            elseif dropdown.ApplyFilter then
                dropdown:ApplyFilter("")
            end
            C_Timer.After(0, function()
                if self:IsShown() and searchEdit:IsShown() then
                    searchEdit:SetFocus()
                end
            end)
        end
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
    function dropdown:SetOptions(values, currentKey, mediaType, searchable, buildItems)
        values = type(values) == "table" and values or {}
        self.values = values
        self.mediaType = mediaType
        self.currentValue = currentKey
        self.searchable = mediaType ~= nil or searchable == true
        if buildItems then
            ConfigureSearch(self.searchable)
        end
        -- 기존 아이템을 풀에 보관 (메모리 누수 방지)
        if not self._itemPool then self._itemPool = {} end
        for _, item in ipairs(self.items) do
            item:Hide()
            item:ClearAllPoints()
            tinsert(self._itemPool, item)
        end
        wipe(self.items)

        if not buildItems then
            self._itemsDirty = true
            if currentKey ~= nil and values[currentKey] ~= nil then
                local displayText = IsMediaFilePath(values[currentKey]) and tostring(currentKey) or values[currentKey]
                selectedText:SetText(displayText)
                UpdateSelectedMedia(currentKey, values[currentKey])
            else
                UpdateSelectedMedia(nil, nil)
            end
            return
        end
        self._itemsDirty = false

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
            local displayText = IsMediaFilePath(value) and tostring(key) or value
            displayText = tostring(displayText or key)
            local item = self._itemPool and tremove(self._itemPool) or CreateFrame("Button", nil, scrollChild)
            item:SetParent(scrollChild)
            local rowHeight = mediaType and 24 or itemHeight
            item:SetHeight(rowHeight)

            local itemBackground = item.background
            if not itemBackground then
                itemBackground = item:CreateTexture(nil, "BACKGROUND")
                itemBackground:SetAllPoints()
                itemBackground:SetColorTexture(0, 0, 0, 0)
                item.background = itemBackground
            end

            -- 왼쪽 액센트 바 (선택 표시용) - 보라→파랑 그라데이션
            local accentBar = item.accentBar
            if not accentBar then
                accentBar = item:CreateTexture(nil, "ARTWORK")
                accentBar:SetWidth(2)
                accentBar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
                accentBar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
                accentBar:SetColorTexture(1, 1, 1, 1)
                local _acR, _acG, _acB = SL.GetColor("accent")
                local _abR, _abG, _abB = SL.GetColor("accentGradEnd")
                accentBar:SetGradient("VERTICAL",
                    CreateColor(_abR, _abG, _abB, 1),
                    CreateColor(_acR, _acG, _acB, 1)
                )
                item.accentBar = accentBar
            end

            local isSelected = (key == currentKey)
            if isSelected then
                itemBackground:SetColorTexture(SL.GetColor("selected"))
                accentBar:Show()
            else
                itemBackground:SetColorTexture(0, 0, 0, 0)
                accentBar:Hide()
            end

            local itemText = item.text
            if not itemText then
                itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                StyleFontString(itemText)
                item._defaultFontPath, item._defaultFontSize, item._defaultFontFlags = itemText:GetFont()
                item.text = itemText
            end
            itemText:ClearAllPoints()
            itemText:SetPoint("LEFT", item, "LEFT", 10, 0)
            itemText:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(displayText)
            if item._defaultFontPath then
                itemText:SetFont(item._defaultFontPath, item._defaultFontSize or 11, item._defaultFontFlags or "")
            end

            local mediaPreview = item.mediaPreview
            if mediaPreview then mediaPreview:Hide() end

            local fontPreview = item.fontPreview
            if fontPreview then fontPreview:Hide() end

            local previewButton = item.previewButton
            if previewButton then previewButton:Hide() end

            local mediaPath = ResolveMediaPath(mediaType, key, value)
            item.mediaPath = mediaPath
            if IsTextureMedia(mediaType) and mediaPath then
                if not mediaPreview then
                    mediaPreview = item:CreateTexture(nil, "ARTWORK")
                    mediaPreview:SetSize(64, 12)
                    item.mediaPreview = mediaPreview
                end
                mediaPreview:ClearAllPoints()
                mediaPreview:SetPoint("LEFT", item, "LEFT", 10, 0)
                mediaPreview:SetTexture(mediaPath)
                mediaPreview:Show()
                itemText:ClearAllPoints()
                itemText:SetPoint("LEFT", mediaPreview, "RIGHT", 8, 0)
                itemText:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            elseif mediaType == "font" then
                if not fontPreview then
                    fontPreview = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    StyleFontString(fontPreview)
                    fontPreview:SetJustifyH("RIGHT")
                    fontPreview:SetWordWrap(false)
                    fontPreview:SetWidth(68)
                    item.fontPreview = fontPreview
                    item._fontPreviewFallbackPath, item._fontPreviewFallbackSize,
                        item._fontPreviewFallbackFlags = fontPreview:GetFont()
                end
                fontPreview:ClearAllPoints()
                fontPreview:SetPoint("RIGHT", item, "RIGHT", -6, 0)
                local fontApplied = mediaPath and fontPreview:SetFont(mediaPath, 13, "")
                if fontApplied then
                    fontPreview:SetText("Ag 123")
                    fontPreview:SetTextColor(SL.GetColor("text"))
                else
                    local fallbackPath = item._fontPreviewFallbackPath
                    if fallbackPath then
                        fontPreview:SetFont(
                            fallbackPath,
                            item._fontPreviewFallbackSize or 11,
                            item._fontPreviewFallbackFlags or ""
                        )
                    end
                    fontPreview:SetText("--")
                    fontPreview:SetTextColor(SL.GetColor("dim"))
                end
                fontPreview:Show()
                itemText:ClearAllPoints()
                itemText:SetPoint("LEFT", item, "LEFT", 10, 0)
                itemText:SetPoint("RIGHT", fontPreview, "LEFT", -8, 0)
            elseif mediaType == "sound" and mediaPath then
                if not previewButton then
                    previewButton = CreateFrame("Button", nil, item)
                    previewButton:SetSize(20, 20)
                    previewButton:SetPoint("RIGHT", item, "RIGHT", -2, 0)
                    previewButton:SetFrameLevel(item:GetFrameLevel() + 2)
                    StyleSoundPreviewButton(previewButton)
                    previewButton:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(rawget(L, "Preview Sound") or "Preview sound")
                        GameTooltip:Show()
                    end)
                    previewButton:SetScript("OnLeave", function(self)
                        GameTooltip:Hide()
                    end)
                    previewButton:SetScript("OnClick", function(self)
                        PlayMediaPreview(self:GetParent().mediaPath)
                    end)
                    item.previewButton = previewButton
                end
                previewButton:Show()
                itemText:ClearAllPoints()
                itemText:SetPoint("LEFT", item, "LEFT", 10, 0)
                itemText:SetPoint("RIGHT", item, "RIGHT", -28, 0)
            end

            if isSelected then
                itemText:SetTextColor(SL.GetColor("text"))
            else
                itemText:SetTextColor(SL.GetColor("dim"))
            end

            item.key = key
            item.displayText = displayText
            item.searchText = (displayText .. " " .. tostring(key)):lower()

            -- 호버 효과 - 배경만 살짝 밝게
            item:SetScript("OnEnter", function(self)
                if self.key ~= dropdown.currentValue then
                    self.background:SetColorTexture(SL.GetColor("hover"))
                    self.text:SetTextColor(SL.GetColor("text"))
                end
            end)
            item:SetScript("OnLeave", function(self)
                if self.key == dropdown.currentValue then
                    self.background:SetColorTexture(SL.GetColor("selected"))
                    self.text:SetTextColor(SL.GetColor("text"))
                else
                    self.background:SetColorTexture(0, 0, 0, 0)
                    self.text:SetTextColor(SL.GetColor("dim"))
                end
            end)

            -- 클릭 시 선택
            item:SetScript("OnClick", function(self)
                dropdown.currentValue = self.key
                selectedText:SetText(self.displayText)
                UpdateSelectedMedia(self.key, values[self.key])
                listFrame:Hide()
                if activeDropdown == dropdown then
                    activeDropdown = nil
                end

                if dropdown.onValueChanged then
                    dropdown.onValueChanged(self.key)
                end

                for _, itm in ipairs(dropdown.items) do
                    if itm.key == self.key then
                        itm.background:SetColorTexture(SL.GetColor("selected"))
                        itm.text:SetTextColor(SL.GetColor("text"))
                        itm.accentBar:Show()
                    else
                        itm.background:SetColorTexture(0, 0, 0, 0)
                        itm.text:SetTextColor(SL.GetColor("dim"))
                        itm.accentBar:Hide()
                    end
                end
            end)

            table.insert(self.items, item)
        end

        self:ApplyFilter(self.searchable and searchEdit and searchEdit:GetText() or "")

        -- 현재 값 설정
        if currentKey ~= nil and values[currentKey] ~= nil then
            self.currentValue = currentKey
            -- LSM HashTable의 경우 경로가 아닌 이름(key)을 표시
            local displayText = IsMediaFilePath(values[currentKey]) and tostring(currentKey) or values[currentKey]
            selectedText:SetText(displayText)
            UpdateSelectedMedia(currentKey, values[currentKey])
        else
            UpdateSelectedMedia(nil, nil)
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
        UpdateSelectedMedia(key, self.values and self.values[key])
    end

    return dropdown
end

-- Main Config Frame

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
    dropdown:SetOptions(
        values,
        currentValue,
        ResolveOptionMediaType(option, values),
        option.searchable == true
    )

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
                    if srcData and dstData and srcData.groupKey == dstData.groupKey and srcData.iconKey ~= dstData.iconKey then
                        local insertAfter = IsDropAfterTarget(targetBtn)
                        local handled = false
                        if DDingUI.ReorderGroupSystemIcon then
                            handled = DDingUI:ReorderGroupSystemIcon(srcData.groupKey, srcData.iconKey, dstData.iconKey, insertAfter) == true
                        end
                        -- ReorderIconInGroup 사용: src를 dst 위치로 이동
                        if not handled and DDingUI.CustomIcons and DDingUI.CustomIcons.ReorderIconInGroup then
                            DDingUI.CustomIcons:ReorderIconInGroup(srcData.groupKey, srcData.iconKey, dstData.iconKey, insertAfter)
                            handled = true
                        end
                        if handled then
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
        if pickerFrame and pickerFrame:IsShown() then return end
        pickerFrame = nil

        -- 풀스크린 투명 프레임 생성
        pickerFrame = CreateFrame("Frame", nil, UIParent)
        DDingUI._optionsFramePicker = pickerFrame
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
            DDingUI._optionsFramePicker = nil
            pickerFrame = nil
        end)

        -- ESC로 취소
        pickerFrame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                pickerFrame:Hide()
                DDingUI._optionsFramePicker = nil
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

DDingUI.GUIBase = {
    L = L,
    CollapsedGroups = CollapsedGroups,
    DragState = DragState,
    SL = SL,
    FLAT = FLAT,
    THEME = THEME,
    GetPopupEditBox = DDingUI_GetPopupEditBox,
    GetSafeScrollRange = GetSafeScrollRange,
    StyleFontString = StyleFontString,
    AddHoverHighlight = AddHoverHighlight,
    FadeIn = FadeIn,
    FadeOut = FadeOut,
    CreateBackdrop = CreateBackdrop,
    CreateShadow = CreateShadow,
    CreateGradientText = CreateGradientText,
    CreateCustomScrollBar = CreateCustomScrollBar,
    PropagateMouseWheelToScroll = PropagateMouseWheelToScroll,
    PropagateMouseWheelRecursive = PropagateMouseWheelRecursive,
    CreateTabButton = CreateTabButton,
    Widgets = Widgets,
}
