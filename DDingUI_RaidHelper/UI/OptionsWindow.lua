-- [STYLE] Toolkit-grade three-column settings window for RaidHelper.
-- The state and combat-safety rules remain in Options.lua; this file only
-- replaces the presentation layer when the embedded StyleLib is available.

local _, ns = ...

local Options = ns.Options
if not Options then return end

local ADDON_KEY = "RaidHelper"
local BRAND_ICON = "Interface\\AddOns\\DDingUI_RaidHelper\\Media\\RaidHelper_Icon.tga"
local ICON_ROOT = "Interface\\AddOns\\DDingUI_RaidHelper\\Media\\Navigation\\"
local SOLID = "Interface\\Buttons\\WHITE8x8"

-- [STYLE] 시안 7: rounded window with three rounded cards (182 / 232 / rest),
-- 8px from the window's left/right/bottom edges and 8px apart.
local PRIMARY_WIDTH = 182
local MODULE_WIDTH = 232
local CARD_INSET = 8
local NAV_PAD = 4
local TITLE_HEIGHT = 44
local DETAIL_HEADER_HEIGHT = 92
local PRIMARY_ROW_HEIGHT = 48
local PRIMARY_ROW_STEP = 52
local MODULE_ROW_HEIGHT = 52
local MODULE_ROW_STEP = 54
local MODULE_LIST_TOP = 80
local PILL_ALPHA = 0.18
local RESIZE_GRIP_SIZE = 30
local DEFAULT_RADIUS = { window = 14, card = 10, row = 8, control = 6, check = 4, track = 2 }
local PAGE_ROW_GAP = 16
local SMALL_TEXT = 12 -- [STYLE] series minimum readable size (StyleLib 1.2 F.small)
local SPELL_ROW_HEIGHT = 46
local SPELL_ROW_STEP = 52

local CATEGORY_DEFS = {
    {
        key = "display",
        label = "전투 화면",
        desc = "파형과 화면 배치",
        icon = ICON_ROOT .. "RaidTimeline.tga",
        pages = { "timeline", "alert" },
    },
    {
        key = "planning",
        label = "전투 계획",
        desc = "쿨기와 상위 빌드",
        icon = ICON_ROOT .. "HealerPlan.tga",
        pages = { "cooldowns", "profile" },
    },
    {
        key = "data",
        label = "데이터",
        desc = "로그 팩과 갱신 상태",
        icon = ICON_ROOT .. "LogData.tga",
        pages = { "data" },
    },
}

local PAGE_META = {
    timeline = {
        label = "타임라인",
        short = "크기·아이콘·표시 요소",
        desc = "전투 중 표시되는 피해 파형과 기믹·전문화 쿨기 아이콘의 크기, 표시 구간, 요소별 표시 여부를 설정합니다.",
        category = "display",
    },
    alert = {
        label = "리마인더",
        short = "아이콘·글자·정렬·방향",
        desc = "곧 사용할 쿨기를 알리는 리마인더의 아이콘·글자 크기, 정렬, 성장 방향, 줄 수와 음성 카운트를 설정합니다.",
        category = "display",
    },
    cooldowns = {
        label = "쿨기 표시",
        short = "주요·세미·외생기 선택",
        desc = "현재 전문화에서 타임라인에 표시할 주요·보조·외생기·개인 기술을 선택합니다.",
        category = "planning",
    },
    profile = {
        label = "상위 전문화 프로필",
        short = "스탯과 대표 특성",
        desc = "현재 보스·난이도·전문화와 일치하는 상위 기록의 2차 스탯과 대표 특성을 확인합니다.",
        category = "planning",
    },
    data = {
        label = "데이터 팩",
        short = "설치 모델과 갱신 상태",
        desc = "Warcraft Logs 공개 로그에서 생성한 로컬 데이터 팩의 설치 및 갱신 상태를 확인합니다.",
        category = "data",
    },
}

local CATEGORY_BY_KEY = {}
local PAGE_CATEGORY = {}
for _, category in ipairs(CATEGORY_DEFS) do
    CATEGORY_BY_KEY[category.key] = category
    for _, pageKey in ipairs(category.pages) do
        PAGE_CATEGORY[pageKey] = category.key
    end
end

local LegacyInitialize = Options.Initialize
local LegacySelectPage = Options.SelectPage
local LegacyRefreshCooldownControls = Options.RefreshCooldownControls

local function UnpackColor(color, alpha)
    return color[1], color[2], color[3], alpha or color[4] or 1
end

local function WithAlpha(color, alpha)
    return { color[1], color[2], color[3], alpha or color[4] or 1 }
end

-- [STYLE] Embedded StyleLib 1.3 rounded helpers; set in Options:Initialize.
local RoundLib

local function CanRound()
    return RoundLib ~= nil and RoundLib.Rounded ~= false
        and RoundLib.MakeRounded ~= nil and RoundLib.RoundTexture ~= nil
end

local function GetRadius(key)
    local radius = RoundLib and RoundLib.Radius
    return radius and radius[key] or DEFAULT_RADIUS[key]
end

-- Rounded 9-slice texture (StyleLib marks it with _ddslRoundTex).
local function RoundFill(texture, radius)
    if texture and CanRound() then
        RoundLib.RoundTexture(texture, radius)
    end
    return texture
end

-- Same rule as StyleLib RowHover: a rounded texture is tinted, a plain one is filled.
local function Paint(texture, color, alpha)
    if texture._ddslRoundTex then
        texture:SetVertexColor(UnpackColor(color, alpha))
    else
        texture:SetColorTexture(UnpackColor(color, alpha))
    end
end

local function ApplyBackdrop(frame, background, border, backgroundAlpha, borderAlpha, radius)
    if radius and CanRound() then -- [STYLE]
        RoundLib.MakeRounded(
            frame,
            radius,
            WithAlpha(background, backgroundAlpha),
            WithAlpha(border, borderAlpha)
        )
        return
    end
    frame:SetBackdrop({
        bgFile = SOLID,
        edgeFile = SOLID,
        edgeSize = 1,
    })
    frame:SetBackdropColor(UnpackColor(background, backgroundAlpha))
    frame:SetBackdropBorderColor(UnpackColor(border, borderAlpha))
end

local function MakeFont(parent, fontPath, size, color, text)
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    fontString:SetFont(fontPath, size, "")
    fontString:SetTextColor(UnpackColor(color))
    fontString:SetText(text or "")
    return fontString
end

local function CreateDivider(parent, color)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(UnpackColor(color))
    return divider
end

local function CreateCard(parent, colors, height, accent, background)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height)
    ApplyBackdrop(
        card,
        background or colors.bg.sidebar,
        colors.border.separator,
        (background or colors.bg.sidebar)[4],
        colors.border.separator[4],
        GetRadius("card")
    )

    if accent then
        -- [STYLE] Keep the stripe on the straight edge so it never pokes out of a rounded corner.
        local inset = CanRound() and (GetRadius("card") + 2) or 0
        local stripe = card:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -inset)
        stripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, inset)
        stripe:SetWidth(3)
        stripe:SetColorTexture(UnpackColor(accent))
        card.accentStripe = stripe
    end
    return card
end

local function AddCardHeader(card, fontPath, colors, titleSize, normalSize, title, description, accent, rightInset)
    rightInset = rightInset or 20
    local titleText = MakeFont(card, fontPath, titleSize, colors.text.highlight, title)
    titleText:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -17)
    titleText:SetPoint("RIGHT", card, "RIGHT", -rightInset, 0)
    titleText:SetJustifyH("LEFT")

    if accent then
        titleText:SetTextColor(UnpackColor(accent))
    end

    local descriptionText
    if description and description ~= "" then
        descriptionText = MakeFont(card, fontPath, normalSize, colors.text.dim, description)
        descriptionText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -6)
        descriptionText:SetPoint("RIGHT", card, "RIGHT", -rightInset, 0)
        descriptionText:SetJustifyH("LEFT")
        descriptionText:SetWordWrap(true)
    end
    return titleText, descriptionText
end

local function CreateSwitch(parent, styleLib, colors, onChanged)
    local accent = styleLib.GetAccent(ADDON_KEY)
    local switch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    switch:SetSize(38, 20)
    ApplyBackdrop(switch, colors.bg.widget, colors.border.default, nil, nil, GetRadius("control"))

    local fill = RoundFill(switch:CreateTexture(nil, "ARTWORK"), GetRadius("check"))
    fill:SetPoint("TOPLEFT", switch, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", switch, "BOTTOMRIGHT", -2, 2)
    Paint(fill, accent)

    local knob = RoundFill(switch:CreateTexture(nil, "OVERLAY"), GetRadius("check"))
    knob:SetSize(14, 14)
    Paint(knob, colors.text.highlight)

    local function Refresh()
        fill:SetShown(switch.checked == true)
        knob:ClearAllPoints()
        if switch.checked then
            knob:SetPoint("RIGHT", switch, "RIGHT", -3, 0)
            switch:SetBackdropBorderColor(UnpackColor(accent))
        else
            knob:SetPoint("LEFT", switch, "LEFT", 3, 0)
            Paint(knob, colors.text.dim)
            switch:SetBackdropBorderColor(UnpackColor(colors.border.default))
        end
        if switch.checked then
            Paint(knob, colors.text.highlight)
        end
    end

    function switch:SetChecked(value, silent)
        self.checked = value == true
        Refresh()
        if not silent and onChanged then onChanged(self.checked) end
    end

    function switch:GetChecked()
        return self.checked == true
    end

    function switch:SetDisabledState(disabled)
        self.disabled = disabled == true
        self:SetEnabled(not self.disabled)
        self:SetAlpha(self.disabled and 0.45 or 1)
    end

    switch:SetScript("OnClick", function(self)
        if self.disabled then return end
        self:SetChecked(not self.checked)
    end)
    switch:SetScript("OnEnter", function(self)
        if self.disabled then return end
        self:SetBackdropBorderColor(UnpackColor(accent))
    end)
    switch:SetScript("OnLeave", Refresh)
    switch:SetChecked(false, true)
    return switch
end

local function CreateScrollArea(parent, colors)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(5)
    track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -5)
    track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, RESIZE_GRIP_SIZE + 8)

    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(4)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:SetColorTexture(UnpackColor(colors.text.dim))

    local function UpdateThumb()
        local viewHeight = math.max(1, scroll:GetHeight() or 1)
        local contentHeight = math.max(viewHeight, child:GetHeight() or 1)
        local trackHeight = math.max(1, track:GetHeight() or 1)
        local thumbHeight = math.max(28, trackHeight * (viewHeight / contentHeight))
        thumbHeight = math.min(trackHeight, thumbHeight)
        thumb:SetHeight(thumbHeight)

        local range = math.max(0, contentHeight - viewHeight)
        if range <= 0 or trackHeight <= thumbHeight then
            thumb:Hide()
            return
        end

        thumb:Show()
        local progress = math.max(0, math.min(1, scroll:GetVerticalScroll() / range))
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -((trackHeight - thumbHeight) * progress))
    end

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
        local nextValue = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48))
        self:SetVerticalScroll(nextValue)
        UpdateThumb()
    end)
    scroll:SetScript("OnVerticalScroll", UpdateThumb)
    scroll:SetScript("OnScrollRangeChanged", UpdateThumb)
    scroll:SetScript("OnSizeChanged", function(_, width)
        child:SetWidth(math.max(1, width - 12))
        UpdateThumb()
    end)
    child:SetScript("OnSizeChanged", UpdateThumb)

    scroll._updateThumb = UpdateThumb
    scroll._track = track
    scroll._thumb = thumb
    return scroll, child
end

local function CreateResizeGrip(frame, styleLib, colors)
    local accent = styleLib.GetAccent(ADDON_KEY)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(RESIZE_GRIP_SIZE, RESIZE_GRIP_SIZE)
    -- [STYLE] Marks sit inside the detail card's corner, clear of the rounded window corner.
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CARD_INSET, CARD_INSET)
    grip:SetFrameLevel(frame:GetFrameLevel() + 50)
    grip:RegisterForDrag("LeftButton")

    local vertical = grip:CreateTexture(nil, "OVERLAY")
    vertical:SetSize(3, 14)
    vertical:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -6, 6)
    vertical:SetColorTexture(UnpackColor(colors.text.dim))

    local horizontal = grip:CreateTexture(nil, "OVERLAY")
    horizontal:SetSize(14, 3)
    horizontal:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -6, 6)
    horizontal:SetColorTexture(UnpackColor(colors.text.dim))

    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    grip:SetScript("OnEnter", function()
        vertical:SetColorTexture(UnpackColor(accent))
        horizontal:SetColorTexture(UnpackColor(accent))
    end)
    grip:SetScript("OnLeave", function()
        vertical:SetColorTexture(UnpackColor(colors.text.dim))
        horizontal:SetColorTexture(UnpackColor(colors.text.dim))
    end)
    return grip
end

local function RegisterEscapeFrame(frame)
    if not UISpecialFrames then return end
    local frameName = frame:GetName()
    for _, registeredName in ipairs(UISpecialFrames) do
        if registeredName == frameName then return end
    end
    table.insert(UISpecialFrames, frameName)
end

local function CleanText(text)
    text = tostring(text or "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

local function CreateWorkspace(styleLib, fontPath, colors, version)
    local existing = _G.DDingUI_RaidHelper_Panel
    if existing and existing._panelResult then
        return existing._panelResult
    end

    local accent = styleLib.GetAccent(ADDON_KEY)
    local frame = CreateFrame("Frame", "DDingUI_RaidHelper_Panel", UIParent, "BackdropTemplate")
    frame:SetSize(1080, 680)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(920, 580)
    if styleLib.AllowOffscreen then styleLib.AllowOffscreen(frame) else frame:SetClampedToScreen(true) end -- [STYLE] 화면 밖으로 걸쳐 두기
    -- [STYLE] 시안 7: round the window before the title bar is built so the shared
    -- title bar drops its rectangular background and accent line.
    ApplyBackdrop(frame, colors.bg.main, colors.border.default, nil, nil, GetRadius("window"))
    frame._ddslMotionBaseScale = frame:GetScale() or 1

    -- [STYLE] Shared title bar as-is (no font/version override) + series "GUI 크기" control.
    local titleBar = styleLib.CreateTitleBar(frame, ADDON_KEY, "DDingUI RaidHelper", version, {
        scale = {
            get = function() return Options:GetOptionsScale() end,
            set = function(value) Options:SetOptionsScale(value) end,
            target = frame,
        },
        -- [STYLE] C12: shared "편집 모드"/"편집 중" title-bar button only toggles positioning.
        editMode = {
            onClick = function()
                if ns.TimelineUI and ns.TimelineUI.ToggleEditMode then
                    ns.TimelineUI:ToggleEditMode()
                end
                Options:RefreshPreviewButton()
            end,
            isActive = function()
                return ns.TimelineUI and ns.TimelineUI.IsEditSessionActive
                    and ns.TimelineUI:IsEditSessionActive() or false
            end,
        },
    })
    titleBar:SetHeight(TITLE_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    -- [STYLE] Give the scale label breathing room before its slider track.
    if titleBar.scaleControl then titleBar.scaleControl:SetWidth(176) end

    local globalSearch = styleLib.CreateSearchBox(titleBar, 184, { placeholder = "검색" })
    globalSearch:SetPoint("RIGHT", titleBar.scaleControl or titleBar.closeBtn, "LEFT", -12, 0)

    -- [STYLE] Three rounded cards below the title bar; nothing rectangular reaches the
    -- window's rounded corners (WoW clips to rectangles, not to the rounded outline).
    local primaryFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    primaryFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_INSET, -TITLE_HEIGHT)
    primaryFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CARD_INSET, CARD_INSET)
    primaryFrame:SetWidth(PRIMARY_WIDTH)
    ApplyBackdrop(primaryFrame, colors.bg.sidebar, colors.border.separator, nil, nil, GetRadius("card"))

    local moduleFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    moduleFrame:SetPoint("TOPLEFT", primaryFrame, "TOPRIGHT", CARD_INSET, 0)
    moduleFrame:SetPoint("BOTTOMLEFT", primaryFrame, "BOTTOMRIGHT", CARD_INSET, 0)
    moduleFrame:SetWidth(MODULE_WIDTH)
    ApplyBackdrop(moduleFrame, colors.bg.sidebar, colors.border.separator, nil, nil, GetRadius("card"))

    local detailCard = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detailCard:SetPoint("TOPLEFT", moduleFrame, "TOPRIGHT", CARD_INSET, 0)
    detailCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CARD_INSET, CARD_INSET)
    ApplyBackdrop(detailCard, colors.bg.titlebar, colors.border.separator, nil, nil, GetRadius("card"))

    -- Header and content are transparent regions of the detail card (no own surface).
    local contentHeader = CreateFrame("Frame", nil, detailCard)
    contentHeader:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 0, 0)
    contentHeader:SetPoint("TOPRIGHT", detailCard, "TOPRIGHT", 0, 0)
    contentHeader:SetHeight(DETAIL_HEADER_HEIGHT)

    local contentFrame = CreateFrame("Frame", nil, detailCard)
    contentFrame:SetPoint("TOPLEFT", contentHeader, "BOTTOMLEFT", 0, 0)
    contentFrame:SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", 0, 0)

    local headerDivider = CreateDivider(contentHeader, colors.border.separator)
    headerDivider:SetPoint("BOTTOMLEFT", contentHeader, "BOTTOMLEFT", 1, 0)
    headerDivider:SetPoint("BOTTOMRIGHT", contentHeader, "BOTTOMRIGHT", -1, 0)
    headerDivider:SetHeight(1)

    local contentScroll, contentChild = CreateScrollArea(contentFrame, colors)
    contentScroll:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 8, -8)
    contentScroll:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -9, 8)

    -- [STYLE] Faint series-rings watermark in the detail card's lower right. It sits on a
    -- mouse-transparent layer above the page cards so it stays visible (alpha 0.05).
    local watermark
    if styleLib.AddWatermark then
        local watermarkLayer = CreateFrame("Frame", nil, detailCard)
        watermarkLayer:SetAllPoints(detailCard)
        watermarkLayer:SetFrameLevel(detailCard:GetFrameLevel() + 30)
        watermark = styleLib.AddWatermark(watermarkLayer, ADDON_KEY, { height = 144 })
    end

    local detailKicker = MakeFont(contentHeader, fontPath, SMALL_TEXT, accent, "")
    detailKicker:SetPoint("TOPLEFT", contentHeader, "TOPLEFT", 24, -15)
    detailKicker:SetJustifyH("LEFT")

    local detailTitle = MakeFont(contentHeader, fontPath, 19, colors.text.highlight, "")
    detailTitle:SetPoint("TOPLEFT", detailKicker, "BOTTOMLEFT", 0, -5)
    detailTitle:SetPoint("RIGHT", contentHeader, "RIGHT", -24, 0)
    detailTitle:SetJustifyH("LEFT")

    local detailDescription = MakeFont(contentHeader, fontPath, 12, colors.text.dim, "")
    detailDescription:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -7)
    detailDescription:SetPoint("RIGHT", contentHeader, "RIGHT", -24, 0)
    detailDescription:SetJustifyH("LEFT")
    detailDescription:SetWordWrap(true)

    local moduleTitle = MakeFont(moduleFrame, fontPath, 18, colors.text.highlight, "")
    moduleTitle:SetPoint("TOPLEFT", moduleFrame, "TOPLEFT", 16, -16)
    moduleTitle:SetPoint("RIGHT", moduleFrame, "RIGHT", -16, 0)
    moduleTitle:SetJustifyH("LEFT")

    local moduleSearch = styleLib.CreateSearchBox(moduleFrame, MODULE_WIDTH - 24, {
        placeholder = "필터 검색...",
    })
    moduleSearch:SetPoint("TOPLEFT", moduleFrame, "TOPLEFT", 12, -46)

    local moduleList = CreateFrame("Frame", nil, moduleFrame)
    moduleList:SetPoint("TOPLEFT", moduleFrame, "TOPLEFT", 0, -MODULE_LIST_TOP)
    moduleList:SetPoint("BOTTOMRIGHT", moduleFrame, "BOTTOMRIGHT", 0, 0)

    -- [STYLE] 시안 7: one rounded pill per column (accent α0.18) that slides between rows.
    -- It is a texture of the card itself, so every row (child frame) draws above it.
    local function CreateColumnIndicator(column, width, height)
        if not styleLib.CreateIndicator then return nil end
        return styleLib.CreateIndicator(column, width, height, WithAlpha(accent, PILL_ALPHA), {
            radius = GetRadius("row"),
            x = NAV_PAD,
            layer = "BACKGROUND",
            subLevel = 2,
        })
    end

    local workspace = {
        selectedCategory = "display",
        selectedPage = "timeline",
        primaryRows = {},
        moduleRows = {},
        primaryIndicator = CreateColumnIndicator(primaryFrame, PRIMARY_WIDTH - NAV_PAD * 2, PRIMARY_ROW_HEIGHT),
        moduleIndicator = CreateColumnIndicator(moduleFrame, MODULE_WIDTH - NAV_PAD * 2, MODULE_ROW_HEIGHT),
    }

    local PRIMARY_IDLE = { colors.bg.sidebar[1], colors.bg.sidebar[2], colors.bg.sidebar[3], 0 }
    local MODULE_IDLE = PRIMARY_IDLE

    -- Inactive row background. On leave RowHover owns the fade back, so it is not snapped here.
    local function PaintIdle(row, idle, fromLeave)
        if fromLeave and row.rowHoverAttached then return end
        Paint(row.background, idle)
    end

    local function AttachRowHover(row, idle)
        if not styleLib.RowHover then return end
        row.rowHoverAttached = true
        styleLib.RowHover(row, {
            bg = row.background,
            label = row.hoverLabel or row.label,
            normal = idle,
            hover = colors.bg.hover,
            isActive = function(target) return target.active == true end,
        })
    end

    local function MoveIndicator(indicator, rows, isActive)
        if not indicator then return end
        for _, row in ipairs(rows) do
            if row:IsShown() and isActive(row) then
                indicator:MoveTo(row, frame:IsShown())
                return
            end
        end
        indicator:HideIndicator()
    end

    -- [STYLE] 시안 7: the pill marks the selection; the active row keeps a clear background.
    local function ApplyPrimaryState(row, fromLeave)
        local active = row.categoryKey == workspace.selectedCategory
        row.active = active
        if active then
            Paint(row.background, PRIMARY_IDLE)
            row.icon:SetVertexColor(UnpackColor(accent))
            row.label:SetTextColor(UnpackColor(colors.text.highlight))
        else
            PaintIdle(row, PRIMARY_IDLE, fromLeave)
            row.icon:SetVertexColor(UnpackColor(colors.text.dim))
            row.label:SetTextColor(UnpackColor(colors.text.normal))
        end
    end

    local function AcquirePrimaryRow(index)
        local row = workspace.primaryRows[index]
        if row then return row end

        row = CreateFrame("Button", nil, primaryFrame)
        row:SetHeight(PRIMARY_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")

        -- [STYLE] Rounded hover background (radius 8, same as the pill).
        row.background = RoundFill(row:CreateTexture(nil, "BACKGROUND"), GetRadius("row"))
        row.background:SetAllPoints()

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", row, "LEFT", 12, 0)
        row.icon:SetTexCoord(0, 1, 0, 1)

        -- [STYLE] Single anchor + fixed width so RowHover can nudge the label.
        row.label = MakeFont(row, fontPath, 14, colors.text.normal, "")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 12, 0)
        row.label:SetWidth(PRIMARY_WIDTH - NAV_PAD * 2 - 12 - 28 - 12 - 8)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        row:SetScript("OnEnter", function(self)
            if not self.active then
                if not self.rowHoverAttached then
                    Paint(self.background, colors.bg.hover)
                end
                self.label:SetTextColor(UnpackColor(colors.text.highlight))
            end
        end)
        row:SetScript("OnLeave", function(self) ApplyPrimaryState(self, true) end)
        row:SetScript("OnClick", function(self)
            workspace:SelectCategory(self.categoryKey, true)
        end)
        AttachRowHover(row, PRIMARY_IDLE)

        workspace.primaryRows[index] = row
        return row
    end

    local function RefreshPrimaryRows()
        for index, category in ipairs(CATEGORY_DEFS) do
            local row = AcquirePrimaryRow(index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", primaryFrame, "TOPLEFT", NAV_PAD, -(NAV_PAD + (index - 1) * PRIMARY_ROW_STEP))
            row:SetPoint("RIGHT", primaryFrame, "RIGHT", -NAV_PAD, 0)
            row.categoryKey = category.key
            row.icon:SetTexture(category.icon)
            row.label:SetText(category.label)
            row:Show()
            ApplyPrimaryState(row)
        end
        MoveIndicator(workspace.primaryIndicator, workspace.primaryRows, function(row)
            return row.active == true
        end)
    end

    local function ApplyModuleState(row, fromLeave)
        local active = row.pageKey == workspace.selectedPage
        row.active = active
        if active then
            Paint(row.background, MODULE_IDLE)
            row.status:SetVertexColor(UnpackColor(accent))
            row.label:SetTextColor(UnpackColor(accent))
            row.description:SetTextColor(UnpackColor(colors.text.normal))
        else
            PaintIdle(row, MODULE_IDLE, fromLeave)
            row.status:SetVertexColor(UnpackColor(colors.text.dim))
            row.label:SetTextColor(UnpackColor(colors.text.normal))
            row.description:SetTextColor(UnpackColor(colors.text.dim))
        end
    end

    local function AcquireModuleRow(index)
        local row = workspace.moduleRows[index]
        if row then return row end

        row = CreateFrame("Button", nil, moduleList)
        row:SetHeight(MODULE_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")

        row.background = RoundFill(row:CreateTexture(nil, "BACKGROUND"), GetRadius("row"))
        row.background:SetAllPoints()

        -- [STYLE] Status mark = open ring from the series logo, aligned to the title line.
        if styleLib.CreateStatusRing then
            row.status = styleLib.CreateStatusRing(row, 11, colors.text.dim)
        else
            row.status = row:CreateTexture(nil, "ARTWORK")
            row.status:SetTexture(SOLID)
            row.status:SetSize(7, 7)
        end
        row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -12)

        -- [STYLE] Title + description share one single-anchor block (integer offsets),
        -- so the RowHover nudge moves both lines together.
        row.textBlock = CreateFrame("Frame", nil, row)
        row.textBlock:SetPoint("TOPLEFT", row, "TOPLEFT", 32, 0)
        row.textBlock:SetSize(MODULE_WIDTH - NAV_PAD * 2 - 32 - 10, MODULE_ROW_HEIGHT)
        row.hoverLabel = row.textBlock

        row.label = MakeFont(row.textBlock, fontPath, 13, colors.text.normal, "")
        row.label:SetPoint("TOPLEFT", row.textBlock, "TOPLEFT", 0, -9)
        row.label:SetPoint("RIGHT", row.textBlock, "RIGHT", 0, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        row.description = MakeFont(row.textBlock, fontPath, SMALL_TEXT, colors.text.dim, "")
        row.description:SetPoint("TOPLEFT", row.textBlock, "TOPLEFT", 0, -28)
        row.description:SetPoint("RIGHT", row.textBlock, "RIGHT", 0, 0)
        row.description:SetJustifyH("LEFT")
        row.description:SetWordWrap(false)

        row:SetScript("OnEnter", function(self)
            if not self.active then
                if not self.rowHoverAttached then
                    Paint(self.background, colors.bg.hover)
                end
                self.label:SetTextColor(UnpackColor(colors.text.highlight))
            end
        end)
        row:SetScript("OnLeave", function(self) ApplyModuleState(self, true) end)
        row:SetScript("OnClick", function(self)
            workspace:SelectPage(self.pageKey, true)
        end)
        AttachRowHover(row, MODULE_IDLE)

        workspace.moduleRows[index] = row
        return row
    end

    local function PageMatches(pageKey, query)
        if not query or query == "" then return true end
        query = query:lower()
        local meta = PAGE_META[pageKey]
        return meta and (
            CleanText(meta.label):lower():find(query, 1, true)
            or CleanText(meta.desc):lower():find(query, 1, true)
        )
    end

    function workspace:RefreshModuleRows(query, acrossAll)
        local pageKeys = {}
        if acrossAll and query and query ~= "" then
            moduleTitle:SetText("검색 결과")
            for _, category in ipairs(CATEGORY_DEFS) do
                for _, pageKey in ipairs(category.pages) do
                    if PageMatches(pageKey, query) then
                        pageKeys[#pageKeys + 1] = pageKey
                    end
                end
            end
        else
            local category = CATEGORY_BY_KEY[self.selectedCategory]
            moduleTitle:SetText(category and category.label or "")
            for _, pageKey in ipairs(category and category.pages or {}) do
                if PageMatches(pageKey, query) then
                    pageKeys[#pageKeys + 1] = pageKey
                end
            end
        end

        for index, pageKey in ipairs(pageKeys) do
            local row = AcquireModuleRow(index)
            local meta = PAGE_META[pageKey]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", moduleList, "TOPLEFT", NAV_PAD, -((index - 1) * MODULE_ROW_STEP))
            row:SetPoint("RIGHT", moduleList, "RIGHT", -NAV_PAD, 0)
            row.pageKey = pageKey
            row.label:SetText(meta.label)
            row.description:SetText(meta.short or meta.desc)
            row:Show()
            ApplyModuleState(row)
        end
        for index = #pageKeys + 1, #self.moduleRows do
            self.moduleRows[index]:Hide()
        end
        MoveIndicator(workspace.moduleIndicator, self.moduleRows, function(row)
            return row.active == true
        end)
    end

    function workspace:SetPageMeta(pageKey)
        local meta = PAGE_META[pageKey]
        if not meta then return end
        local category = CATEGORY_BY_KEY[meta.category]
        detailKicker:SetText(category and category.label or "RAID HELPER")
        detailTitle:SetText(meta.label)
        detailDescription:SetText(meta.desc)
    end

    function workspace:SelectCategory(categoryKey, notify)
        local category = CATEGORY_BY_KEY[categoryKey]
        if not category then return false end
        self.selectedCategory = categoryKey
        globalSearch:SetText("")
        moduleSearch:SetText("")
        RefreshPrimaryRows()
        self:RefreshModuleRows()
        if category.pages[1] then
            self:SelectPage(category.pages[1], notify)
        end
        return true
    end

    function workspace:SelectPage(pageKey, notify)
        local meta = PAGE_META[pageKey]
        if not meta then return false end
        local categoryChanged = meta.category ~= self.selectedCategory
        self.selectedCategory = meta.category
        self.selectedPage = pageKey
        if notify and globalSearch:GetText() ~= "" then
            globalSearch:SetText("")
        end
        if categoryChanged then
            moduleSearch:SetText("")
        end
        RefreshPrimaryRows()
        self:RefreshModuleRows()
        self:SetPageMeta(pageKey)
        if notify and Options.SelectPage then
            Options:SelectPage(pageKey)
        end
        return true
    end

    function workspace:FilterModules(query, acrossAll)
        self:RefreshModuleRows(query, acrossAll)
    end

    moduleSearch:SetOnTextChanged(function(text)
        workspace:FilterModules(text, false)
    end)
    globalSearch:SetOnTextChanged(function(text)
        workspace:FilterModules(text, text ~= "")
    end)

    local treeAdapter = {}
    function treeAdapter:SetSelected(pageKey)
        return workspace:SelectPage(pageKey, false)
    end
    function treeAdapter:GetSelected()
        return workspace.selectedPage
    end
    function treeAdapter:SetMenuData()
        workspace:RefreshModuleRows()
    end

    RefreshPrimaryRows()
    workspace:RefreshModuleRows()
    workspace:SetPageMeta("timeline")
    CreateResizeGrip(frame, styleLib, colors)
    RegisterEscapeFrame(frame)

    if styleLib.EnableRightClickMouselook then
        styleLib.EnableRightClickMouselook(frame)
        styleLib.EnableRightClickMouselook(titleBar)
        styleLib.EnableRightClickMouselook(primaryFrame)
        styleLib.EnableRightClickMouselook(moduleFrame)
        styleLib.EnableRightClickMouselook(detailCard)
        styleLib.EnableRightClickMouselook(contentFrame)
        styleLib.EnableRightClickMouselook(contentScroll)
    end

    frame:Hide()
    if styleLib.Motion then styleLib.Motion.BindPanel(frame) end
    -- [STYLE] Restore the saved "GUI 크기" through the motion-safe base scale.
    local optionsScale = Options:GetOptionsScale()
    if frame.SetBaseScale then
        frame:SetBaseScale(optionsScale)
    else
        frame:SetScale(optionsScale)
    end
    local result = {
        frame = frame,
        titleBar = titleBar,
        treeFrame = primaryFrame,
        moduleFrame = moduleFrame,
        detailCard = detailCard,
        watermark = watermark,
        contentHeader = contentHeader,
        contentFrame = contentFrame,
        contentScroll = contentScroll,
        contentChild = contentChild,
        workspace = workspace,
        treeMenu = treeAdapter,
        globalSearch = globalSearch,
        moduleSearch = moduleSearch,
    }
    frame._panelResult = result
    return result
end

local function CreateModernPage(parent, height)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -18)
    page:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -22, -18)
    page:SetHeight(height)
    page.contentHeight = height
    page.rows = {}
    page.rowCursor = 0
    -- [STYLE] Top-level rows keep a single anchor so StaggerIn can nudge them;
    -- their width follows the page instead of a second anchor.
    page:SetScript("OnSizeChanged", function(self, width)
        width = math.max(1, width or self:GetWidth() or 1)
        for _, row in ipairs(self.rows) do
            row:SetWidth(width)
        end
    end)
    page:Hide()
    return page
end

-- Hidden pages may miss OnSizeChanged; re-sync row widths whenever a page is shown.
local function SyncPageRows(page)
    local handler = page and page.rows and page:GetScript("OnSizeChanged")
    if handler then handler(page, page:GetWidth()) end
end

local function AddPageRow(page, height)
    local row = CreateFrame("Frame", nil, page)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -page.rowCursor)
    row:SetSize(math.max(1, page:GetWidth() or 1), height)
    page.rowCursor = page.rowCursor + height + PAGE_ROW_GAP
    page.rows[#page.rows + 1] = row
    return row
end

local function CreateRowCard(page, colors, height, accent, background)
    local row = AddPageRow(page, height)
    local card = CreateCard(row, colors, height, accent, background)
    card:SetAllPoints(row)
    return card, row
end

local function CreateInfoRow(card, fontPath, colors, title, description, y)
    local titleText = MakeFont(card, fontPath, 13, colors.text.highlight, title)
    titleText:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y)
    titleText:SetPoint("RIGHT", card, "RIGHT", -76, 0)
    titleText:SetJustifyH("LEFT")

    local descriptionText = MakeFont(card, fontPath, SMALL_TEXT, colors.text.dim, description)
    descriptionText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -6)
    descriptionText:SetPoint("RIGHT", card, "RIGHT", -76, 0)
    descriptionText:SetJustifyH("LEFT")
    return titleText, descriptionText
end

function Options:RefreshPreviewButton()
    -- [STYLE] C12: keep the title-bar edit button ("편집 모드"/"편집 중") in step with positioning.
    local editButton = self.panel and self.panel.titleBar and self.panel.titleBar.editButton
    if editButton and editButton.Refresh then editButton:Refresh() end

    local button = self.previewButton
    if not button then return end

    local active = ns.TimelineUI
        and ns.TimelineUI.IsPreviewMode
        and ns.TimelineUI:IsPreviewMode()
        and not ns.TimelineUI:IsEditSessionActive()
    local text = active and "미리보기 종료" or "미리보기"
    if button.label and button.label.SetText then
        button.label:SetText(text)
    elseif button.SetText then
        button:SetText(text)
    end
end

-- [STYLE] Timeline "표시 요소" switches (2026-10-11 사용자 요청), two per row: mechanic-side
-- elements on the left, cooldown-side and bar-wide elements on the right.
local ELEMENT_GRID_TOP = 72
local ELEMENT_ROW_HEIGHT = 46
local ELEMENT_ROW_STEP = 52
local TIMELINE_ELEMENTS = {
    { key = "showMechanics", label = "기믹 아이콘", desc = "바 위의 보스 기믹" },
    { key = "showCooldowns", label = "쿨기 아이콘", desc = "바 아래 힐러 쿨기" },
    { key = "showCountdown", label = "기믹 남은 초", desc = "아이콘 아래 숫자" },
    { key = "showCooldownDetail", label = "쿨기 이름", desc = "가까운 쿨기 하나" },
    { key = "showMechanicDetail", label = "기믹 상세", desc = "이름·피해·피격 인원" },
    { key = "showSpread", label = "쿨기 오차 범위", desc = "사용 시점 오차 띠" },
    { key = "highlightNear", label = "가까운 기믹 강조", desc = "5초 안이면 키움" },
    { key = "showDamage", label = "피해 파형", desc = "평균 피해 능선" },
    { key = "showPhases", label = "페이즈 표시", desc = "구간 띠·경계선·이름" },
    { key = "showGrid", label = "시간 눈금", desc = "5초·10초 눈금" },
    { key = "showTimeReadout", label = "전투 시간", desc = "경과 시간·페이즈" },
}

function Options:RefreshTimelineStyleControls()
    local controls = self.timelineStyleControls
    if not controls then return end
    local style = self:GetRequestedTimelineStyle()
    local kinds = self.timelineStyleControlKinds or {}
    self.syncingTimelineStyleControls = true
    for key, control in pairs(controls) do
        if kinds[key] == "slider" then
            control.slider:SetValue(style[key])
        else
            control:SetChecked(style[key] == true, true)
        end
    end
    self.syncingTimelineStyleControls = false
end

local function ChangeTimelineStyle(key, value)
    if Options.syncingTimelineStyleControls then return end
    Options:SetTimelineStyleValue(key, value)
end

function Options:CreateModernTimelinePage(parent, styleLib, fontPath, colors)
    local accent = styleLib.GetAccent(ADDON_KEY)
    local page = CreateModernPage(parent, 640)

    local previewCard = CreateRowCard(page, colors, 100, accent)
    AddCardHeader(
        previewCard,
        fontPath,
        colors,
        14,
        SMALL_TEXT,
        "미리보기",
        "견본 전투로 타임라인과 리마인더를 재생합니다. 위치 조정은 제목줄의 편집 모드를 사용합니다.",
        nil,
        302
    )

    local previewButton = styleLib.CreateButton(previewCard, ADDON_KEY, "미리보기", function()
        if ns.TimelineUI and ns.TimelineUI.TogglePreviewMode then
            ns.TimelineUI:TogglePreviewMode()
            Options:RefreshPreviewButton()
        end
    end, { width = 132, height = 28 })
    previewButton:SetPoint("RIGHT", previewCard, "RIGHT", -20, 0)

    local resetButton
    resetButton = styleLib.CreateButton(previewCard, ADDON_KEY, "위치 초기화", function()
        if ns.TimelineUI then ns.TimelineUI:ResetPosition() end
        ns:Print("프레임 위치를 초기화했습니다.")
        if styleLib.AppliedFeedback then -- [STYLE]
            styleLib.AppliedFeedback(resetButton, resetButton.label, { text = "초기화됨" })
        end
    end, { width = 112, height = 28 })
    resetButton:SetPoint("RIGHT", previewButton, "LEFT", -8, 0)

    local displayCard = CreateRowCard(page, colors, 232)
    AddCardHeader(
        displayCard,
        fontPath,
        colors,
        14,
        SMALL_TEXT,
        "화면 표시",
        "전체 배율과 바 너비·높이를 조절합니다. 배경 불투명도는 바 배경에만 적용되며 0%면 파형과 아이콘만 화면에 뜹니다."
    )

    local timelineScaleSlider = styleLib.CreateSlider(
        displayCard,
        ADDON_KEY,
        "전체 크기 (%)",
        60,
        160,
        5,
        self:GetRequestedTimelineScale() * 100,
        {
            width = 240,
            onChange = function(value)
                if Options.syncingDisplayControls then return end
                Options:SetTimelineScale(value / 100)
            end,
        }
    )
    timelineScaleSlider:SetPoint("TOPLEFT", displayCard, "TOPLEFT", 20, -72)
    timelineScaleSlider:SetPoint("RIGHT", displayCard, "CENTER", -16, 0)

    local backgroundAlphaSlider = styleLib.CreateSlider(
        displayCard,
        ADDON_KEY,
        "배경 불투명도 (%)",
        0,
        100,
        5,
        self:GetRequestedBackgroundAlpha() * 100,
        {
            width = 240,
            onChange = function(value)
                if Options.syncingDisplayControls then return end
                Options:SetBackgroundAlpha(value / 100)
            end,
        }
    )
    backgroundAlphaSlider:SetPoint("TOPLEFT", displayCard, "TOP", 16, -72)
    backgroundAlphaSlider:SetPoint("RIGHT", displayCard, "RIGHT", -20, 0)

    local timelineWidthSlider = styleLib.CreateSlider(
        displayCard,
        ADDON_KEY,
        "너비 (px)",
        200,
        1200,
        20,
        self:GetRequestedTimelineWidth(),
        {
            width = 240,
            onChange = function(value)
                if Options.syncingDisplayControls then return end
                Options:SetTimelineWidth(value)
            end,
        }
    )
    timelineWidthSlider:SetPoint("TOPLEFT", displayCard, "TOPLEFT", 20, -150)
    timelineWidthSlider:SetPoint("RIGHT", displayCard, "CENTER", -16, 0)

    local timelineHeightSlider = styleLib.CreateSlider(
        displayCard,
        ADDON_KEY,
        "높이 (px)",
        80,
        160,
        2,
        self:GetRequestedTimelineHeight(),
        {
            width = 240,
            onChange = function(value)
                if Options.syncingDisplayControls then return end
                Options:SetTimelineHeight(value)
            end,
        }
    )
    timelineHeightSlider:SetPoint("TOPLEFT", displayCard, "TOP", 16, -150)
    timelineHeightSlider:SetPoint("RIGHT", displayCard, "RIGHT", -20, 0)

    -- [STYLE] Timeline detail options (2026-10-11 사용자 요청): icon sizes, shown range and one
    -- switch per bar element. The page's "미리보기" plays the real bar, so it is the live sample.
    local spec = ns.TimelineUI and ns.TimelineUI.TIMELINE_STYLE_SPEC or {}
    local style = self:GetRequestedTimelineStyle()
    local controls, kinds = {}, {}

    local function AddStyleSlider(card, key, label, y, leftColumn)
        local range = spec[key] or {}
        local slider = styleLib.CreateSlider(card, ADDON_KEY, label, range.min or 0, range.max or 100,
            1, style[key] or range.default or 0, {
                width = 240,
                onChange = function(value) ChangeTimelineStyle(key, value) end,
            })
        if leftColumn then
            slider:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y)
            slider:SetPoint("RIGHT", card, "CENTER", -16, 0)
        else
            slider:SetPoint("TOPLEFT", card, "TOP", 16, y)
            slider:SetPoint("RIGHT", card, "RIGHT", -20, 0)
        end
        controls[key] = slider
        kinds[key] = "slider"
        return slider
    end

    local iconCard = CreateRowCard(page, colors, 154)
    AddCardHeader(
        iconCard,
        fontPath,
        colors,
        14,
        SMALL_TEXT,
        "아이콘",
        "기믹·쿨기 아이콘 크기입니다. 기믹 아이콘은 바 높이 안에서만 커집니다.",
        nil,
        150
    )
    local styleResetButton
    styleResetButton = styleLib.CreateButton(iconCard, ADDON_KEY, "기본값으로", function()
        if Options:ResetTimelineStyle() and styleLib.AppliedFeedback then -- [STYLE]
            styleLib.AppliedFeedback(styleResetButton, styleResetButton.label, { text = "되돌림" })
        end
    end, { width = 112, height = 28 })
    styleResetButton:SetPoint("TOPRIGHT", iconCard, "TOPRIGHT", -20, -20)
    AddStyleSlider(iconCard, "mechanicSize", "기믹 아이콘 크기 (px)", -72, true)
    AddStyleSlider(iconCard, "cooldownSize", "쿨기 아이콘 크기 (px)", -72, false)

    local rangeCard = CreateRowCard(page, colors, 232)
    AddCardHeader(
        rangeCard,
        fontPath,
        colors,
        14,
        SMALL_TEXT,
        "표시 구간",
        "지금을 기준으로 바에 담을 시간과 지나간 아이콘의 진하기를 정합니다. 0%면 지나간 아이콘을 숨깁니다."
    )
    AddStyleSlider(rangeCard, "windowPast", "지난 시간 (초)", -72, true)
    AddStyleSlider(rangeCard, "windowFuture", "앞으로 표시할 시간 (초)", -72, false)
    AddStyleSlider(rangeCard, "pastAlpha", "지난 아이콘 불투명도 (%)", -150, true)

    local elementRows = math.ceil(#TIMELINE_ELEMENTS / 2)
    local elementCard = CreateRowCard(page, colors, ELEMENT_GRID_TOP + elementRows * ELEMENT_ROW_STEP + 10)
    AddCardHeader(
        elementCard,
        fontPath,
        colors,
        14,
        SMALL_TEXT,
        "표시 요소",
        "타임라인에 그릴 요소를 하나씩 켜고 끕니다. 아이콘을 꺼도 리마인더는 그대로 알려 줍니다."
    )
    for index, element in ipairs(TIMELINE_ELEMENTS) do
        local key = element.key
        local row = CreateFrame("Frame", nil, elementCard, "BackdropTemplate")
        row:SetHeight(ELEMENT_ROW_HEIGHT)
        ApplyBackdrop(row, colors.bg.widget, colors.border.separator, nil, nil, GetRadius("row"))
        local top = -(ELEMENT_GRID_TOP + math.floor((index - 1) / 2) * ELEMENT_ROW_STEP)
        if index % 2 == 1 then
            row:SetPoint("TOPLEFT", elementCard, "TOPLEFT", 16, top)
            row:SetPoint("RIGHT", elementCard, "CENTER", -8, 0)
        else
            row:SetPoint("TOPLEFT", elementCard, "TOP", 8, top)
            row:SetPoint("RIGHT", elementCard, "RIGHT", -16, 0)
        end

        local label = MakeFont(row, fontPath, 13, colors.text.highlight, element.label)
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8)
        label:SetPoint("RIGHT", row, "RIGHT", -58, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        local description = MakeFont(row, fontPath, SMALL_TEXT, colors.text.dim, element.desc)
        description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
        description:SetPoint("RIGHT", row, "RIGHT", -58, 0)
        description:SetJustifyH("LEFT")
        description:SetWordWrap(false)

        local switch = CreateSwitch(row, styleLib, colors, function(value)
            ChangeTimelineStyle(key, value == true)
        end)
        switch:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        switch:SetChecked(style[key] == true, true)
        controls[key] = switch
        kinds[key] = "switch"
    end

    local behaviorCard = CreateRowCard(page, colors, 92)
    CreateInfoRow(
        behaviorCard,
        fontPath,
        colors,
        "마커 툴팁",
        "기믹과 전문화 쿨기 마커에 마우스를 올렸을 때 상세 정보를 표시합니다.",
        -23
    )

    local tooltipSwitch = CreateSwitch(behaviorCard, styleLib, colors, function(value)
        if Options.syncingCheckbox then return end
        Options:SetTooltipsEnabled(value)
    end)
    tooltipSwitch:SetPoint("TOPRIGHT", behaviorCard, "TOPRIGHT", -22, -23)
    tooltipSwitch:SetChecked(self:ShouldShowTooltips(), true)

    local safetyCard = CreateRowCard(page, colors, 72, accent, colors.bg.widget)
    local safetyTitle = MakeFont(safetyCard, fontPath, 12, accent, "전투 안전 적용")
    safetyTitle:SetPoint("TOPLEFT", safetyCard, "TOPLEFT", 20, -17)
    local safetyText = MakeFont(
        safetyCard,
        fontPath,
        SMALL_TEXT,
        colors.text.dim,
        "이 페이지의 표시 설정은 전투 중에 바꾸면 전투 종료 후 자동으로 반영합니다."
    )
    safetyText:SetPoint("TOPLEFT", safetyTitle, "BOTTOMLEFT", 0, -7)
    safetyText:SetPoint("RIGHT", safetyCard, "RIGHT", -20, 0)
    safetyText:SetJustifyH("LEFT")

    self.tooltipCheckbox = tooltipSwitch
    self.timelineScaleSlider = timelineScaleSlider
    self.backgroundAlphaSlider = backgroundAlphaSlider
    self.timelineWidthSlider = timelineWidthSlider
    self.timelineHeightSlider = timelineHeightSlider
    self.previewButton = previewButton
    self.timelineStyleControls = controls
    self.timelineStyleControlKinds = kinds
    self.timelineStyleResetButton = styleResetButton
    -- [STYLE] Scroll through every card, including the element switches and the notes below.
    page.contentHeight = page.rowCursor - PAGE_ROW_GAP
    page:SetHeight(page.contentHeight)
    return page
end

local function GetSpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    if type(_G.GetSpellTexture) == "function" then
        return _G.GetSpellTexture(spellID)
    end
    return nil
end

local function CreateSpellRow(parent, styleLib, fontPath, colors, specID, spell, column, rowIndex)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(SPELL_ROW_HEIGHT)
    ApplyBackdrop(row, colors.bg.widget, colors.border.separator, nil, nil, GetRadius("row")) -- [STYLE]

    if column == 0 then
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -(58 + rowIndex * SPELL_ROW_STEP))
        row:SetPoint("RIGHT", parent, "CENTER", -8, 0)
    else
        row:SetPoint("TOPLEFT", parent, "TOP", 8, -(58 + rowIndex * SPELL_ROW_STEP))
        row:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    end

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexture(GetSpellTexture(spell.spellID) or BRAND_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local name = ns.CooldownCatalog:GetSpellName(specID, spell.spellID)
    local label = MakeFont(row, fontPath, 12, colors.text.highlight, name)
    label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, -3)
    label:SetPoint("RIGHT", row, "RIGHT", -58, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    local spellIDText = MakeFont(row, fontPath, SMALL_TEXT, colors.text.dim, "주문 ID  " .. spell.spellID)
    spellIDText:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    spellIDText:SetPoint("RIGHT", row, "RIGHT", -58, 0)
    spellIDText:SetJustifyH("LEFT")

    local switch = CreateSwitch(row, styleLib, colors, function(value)
        if Options.syncingCooldownControls then return end
        Options:SetCooldownVisible(specID, spell.spellID, value)
    end)
    switch:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    switch:SetChecked(spell.defaultShown ~= false, true)
    return row, switch
end

-- [STYLE] "곧 사용 알림" page (2026-10-10 사용자 요청): every alert detail in one place,
-- with a live sample drawn by the same layout code as the in-combat alert.
local ALERT_ALIGN_ITEMS = {
    { text = "왼쪽", value = "LEFT" },
    { text = "가운데", value = "CENTER" },
    { text = "오른쪽", value = "RIGHT" },
}
local ALERT_GROW_ITEMS = {
    { text = "아래로", value = "DOWN" },
    { text = "위로", value = "UP" },
}

--- Keeps the settings sample inside its card: horizontally on the aligned side, vertically on
--- the side it grows from (top when lines stack down, bottom when they stack up).
function Options:PositionAlertSample()
    local area, sample = self.alertSampleArea, self.alertSample
    if not (area and sample) then return end
    local style = self:GetAlertStyle()
    local vertical = style.grow == "UP" and "BOTTOM" or "TOP"
    local horizontal = style.align == "RIGHT" and "RIGHT" or style.align == "CENTER" and "" or "LEFT"
    local point = vertical .. horizontal
    sample:SetScale(math.min(1, math.max(1, area:GetWidth()) / style.width))
    sample:ClearAllPoints()
    sample:SetPoint(point, area, point, 0, 0)
end

function Options:RefreshAlertControls()
    local controls = self.alertControls
    if not controls then return end
    local style = self:GetAlertStyle()
    self.syncingAlertControls = true
    local kinds = self.alertControlKinds or {}
    for key, control in pairs(controls) do
        local value = style[key]
        if kinds[key] == "slider" then
            control.slider:SetValue(value)
        elseif kinds[key] == "switch" then
            control:SetChecked(value == true, true)
        else
            control:SetValue(value)
        end
    end
    self.syncingAlertControls = false
    self:PositionAlertSample()
end

local function ChangeAlertStyle(key, value)
    if Options.syncingAlertControls then return end
    Options:SetAlertStyleValue(key, value)
    Options:PositionAlertSample()
end

function Options:CreateModernAlertPage(parent, styleLib, fontPath, colors)
    local accent = styleLib.GetAccent(ADDON_KEY)
    local spec = ns.TimelineUI and ns.TimelineUI.ALERT_STYLE_SPEC or {}
    local style = self:GetAlertStyle()
    local page = CreateModernPage(parent, 640)
    local controls, kinds = {}, {}

    -- Show / voice ----------------------------------------------------------------------
    local showCard = CreateRowCard(page, colors, 226)
    CreateInfoRow(
        showCard,
        fontPath,
        colors,
        "리마인더",
        "표시 시작 시간 안에 예정된 선택 쿨기를 아이콘·스킬 이름·남은 초로 표시합니다.",
        -23
    )
    local upcomingCooldownSwitch = CreateSwitch(showCard, styleLib, colors, function(value)
        if Options.syncingCheckbox then return end
        Options:SetUpcomingCooldownsEnabled(value)
    end)
    upcomingCooldownSwitch:SetPoint("TOPRIGHT", showCard, "TOPRIGHT", -22, -23)
    upcomingCooldownSwitch:SetChecked(self:ShouldShowUpcomingCooldowns(), true)

    local voiceDivider = CreateDivider(showCard, colors.border.separator)
    voiceDivider:SetPoint("TOPLEFT", showCard, "TOPLEFT", 20, -87)
    voiceDivider:SetPoint("TOPRIGHT", showCard, "TOPRIGHT", -20, -87)
    voiceDivider:SetHeight(1)

    local _, voiceDescription = CreateInfoRow(
        showCard,
        fontPath,
        colors,
        "카운트 소리",
        "3초 전부터 선택한 소리로 셉니다. 전투 중에도 바로 적용됩니다.",
        -105
    )
    voiceDescription:SetPoint("RIGHT", showCard, "RIGHT", -176, 0)
    local countdownVoiceSwitch = CreateSwitch(showCard, styleLib, colors, function(value)
        if Options.syncingCheckbox then return end
        Options:SetCountdownVoiceEnabled(value)
    end)
    countdownVoiceSwitch:SetPoint("TOPRIGHT", showCard, "TOPRIGHT", -22, -105)
    countdownVoiceSwitch:SetChecked(self:ShouldPlayCountdownVoice(), true)
    local voicePreviewButton = styleLib.CreateButton(showCard, ADDON_KEY, "미리 듣기", function()
        if ns.TimelineUI and ns.TimelineUI.PreviewCountdownVoice then
            ns.TimelineUI:PreviewCountdownVoice()
        end
    end, { width = 84, height = 24 })
    voicePreviewButton:SetPoint("RIGHT", countdownVoiceSwitch, "LEFT", -12, 0)
    local countdownVoiceDropdown = styleLib.CreateDropdown(showCard, ADDON_KEY, "카운트 종류", {
        { text = "일본어 카운트", value = "ja" },
        { text = "한국어 카운트", value = "ko" },
        { text = "영어 카운트", value = "en" },
        { text = "경보 카운트", value = "alarm" },
    }, ns.TimelineUI:GetCountdownVoicePack(), {
        width = 172,
        onChange = function(value)
            if Options.syncingCheckbox then return end
            Options:SetCountdownVoicePack(value)
        end,
    })
    countdownVoiceDropdown:SetPoint("TOPLEFT", showCard, "TOPLEFT", 20, -177)

    -- Live sample: tall enough for three lines at the largest sizes (3 x 52 + 2 x 16 = 188).
    local sampleCard = CreateRowCard(page, colors, 280, accent)
    AddCardHeader(
        sampleCard,
        fontPath,
        colors,
        14,
        SMALL_TEXT,
        "견본",
        "아래 설정을 바꾸면 바로 반영됩니다. 화면 위치는 편집 모드에서 따로 옮깁니다.",
        nil,
        150
    )
    local resetButton
    resetButton = styleLib.CreateButton(sampleCard, ADDON_KEY, "기본값으로", function()
        Options:ResetAlertStyle()
        if styleLib.AppliedFeedback then -- [STYLE]
            styleLib.AppliedFeedback(resetButton, resetButton.label, { text = "되돌림" })
        end
    end, { width = 112, height = 28 })
    resetButton:SetPoint("TOPRIGHT", sampleCard, "TOPRIGHT", -20, -20)

    local sampleArea = CreateFrame("Frame", nil, sampleCard)
    sampleArea:SetPoint("TOPLEFT", sampleCard, "TOPLEFT", 20, -70)
    sampleArea:SetPoint("BOTTOMRIGHT", sampleCard, "BOTTOMRIGHT", -20, 14)
    if sampleArea.SetClipsChildren then sampleArea:SetClipsChildren(true) end
    self.alertSampleArea = sampleArea
    sampleArea:SetScript("OnSizeChanged", function() Options:PositionAlertSample() end)
    if ns.TimelineUI and ns.TimelineUI.CreateAlertSample then
        self.alertSample = ns.TimelineUI:CreateAlertSample(sampleArea)
    end

    -- Sizes ------------------------------------------------------------------------------
    local function AddSlider(card, key, label, step, y, leftColumn)
        local range = spec[key] or {}
        local slider = styleLib.CreateSlider(card, ADDON_KEY, label, range.min or 0, range.max or 100,
            step or 1, style[key] or range.default or 0, {
                width = 240,
                onChange = function(value) ChangeAlertStyle(key, value) end,
            })
        if leftColumn then
            slider:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y)
            slider:SetPoint("RIGHT", card, "CENTER", -16, 0)
        else
            slider:SetPoint("TOPLEFT", card, "TOP", 16, y)
            slider:SetPoint("RIGHT", card, "RIGHT", -20, 0)
        end
        controls[key] = slider
        kinds[key] = "slider"
        return slider
    end

    local sizeCard = CreateRowCard(page, colors, 232)
    AddCardHeader(sizeCard, fontPath, colors, 14, SMALL_TEXT, "크기",
        "아이콘과 글자 크기, 알림 줄의 너비를 정합니다. 줄 높이는 가장 큰 요소에 맞춰집니다.")
    AddSlider(sizeCard, "iconSize", "아이콘 크기 (px)", 1, -72, true)
    AddSlider(sizeCard, "nameSize", "이름 글자 크기", 1, -72, false)
    AddSlider(sizeCard, "countSize", "숫자 글자 크기", 1, -150, true)
    AddSlider(sizeCard, "width", "알림 너비 (px)", 10, -150, false)

    -- Layout -----------------------------------------------------------------------------
    local layoutCard = CreateRowCard(page, colors, 300)
    AddCardHeader(layoutCard, fontPath, colors, 14, SMALL_TEXT, "배치",
        "줄 정렬과 쌓이는 방향, 간격과 줄 수, 몇 초 전부터 보여줄지 정합니다.")
    local alignDropdown = styleLib.CreateDropdown(layoutCard, ADDON_KEY, "정렬", ALERT_ALIGN_ITEMS, style.align, {
        width = 140,
        onChange = function(value) ChangeAlertStyle("align", value) end,
    })
    alignDropdown:SetPoint("TOPLEFT", layoutCard, "TOPLEFT", 20, -76)
    controls.align = alignDropdown
    kinds.align = "dropdown"
    local growDropdown = styleLib.CreateDropdown(layoutCard, ADDON_KEY, "성장 방향", ALERT_GROW_ITEMS, style.grow, {
        width = 120,
        onChange = function(value) ChangeAlertStyle("grow", value) end,
    })
    growDropdown:SetPoint("TOPLEFT", layoutCard, "TOP", 16, -76)
    controls.grow = growDropdown
    kinds.grow = "dropdown"
    AddSlider(layoutCard, "spacing", "줄 간격 (px)", 1, -128, true)
    AddSlider(layoutCard, "maxRows", "최대 줄 수", 1, -128, false)
    AddSlider(layoutCard, "window", "표시 시작 (초 전)", 1, -206, true)

    -- Elements ---------------------------------------------------------------------------
    local elementCard = CreateRowCard(page, colors, 256)
    local function AddToggle(key, title, description, y)
        CreateInfoRow(elementCard, fontPath, colors, title, description, y)
        local switch = CreateSwitch(elementCard, styleLib, colors, function(value)
            ChangeAlertStyle(key, value == true)
        end)
        switch:SetPoint("TOPRIGHT", elementCard, "TOPRIGHT", -22, y)
        switch:SetChecked(style[key] == true, true)
        controls[key] = switch
        kinds[key] = "switch"
        return switch
    end
    AddToggle("showIcon", "아이콘 표시", "줄 앞에 스킬 아이콘을 보여줍니다.", -23)
    local elementDivider = CreateDivider(elementCard, colors.border.separator)
    elementDivider:SetPoint("TOPLEFT", elementCard, "TOPLEFT", 20, -87)
    elementDivider:SetPoint("TOPRIGHT", elementCard, "TOPRIGHT", -20, -87)
    elementDivider:SetHeight(1)
    AddToggle("showName", "스킬 이름 표시", "끄면 아이콘과 남은 초만 보여줍니다.", -105)
    local popDivider = CreateDivider(elementCard, colors.border.separator)
    popDivider:SetPoint("TOPLEFT", elementCard, "TOPLEFT", 20, -169)
    popDivider:SetPoint("TOPRIGHT", elementCard, "TOPRIGHT", -20, -169)
    popDivider:SetHeight(1)
    AddToggle("pop", "모션", "등장·퇴장·줄 이동과 3초 강조·숫자 팝·지금 반짝임을 켭니다.", -187)

    local noteCard = CreateRowCard(page, colors, 72, accent, colors.bg.widget)
    local noteTitle = MakeFont(noteCard, fontPath, 12, accent, "바로 적용")
    noteTitle:SetPoint("TOPLEFT", noteCard, "TOPLEFT", 20, -17)
    local noteText = MakeFont(
        noteCard,
        fontPath,
        SMALL_TEXT,
        colors.text.dim,
        "알림 모양은 전투 중에도 바로 바뀝니다. 크기는 타임라인의 '전체 크기'를 함께 따릅니다."
    )
    noteText:SetPoint("TOPLEFT", noteTitle, "BOTTOMLEFT", 0, -7)
    noteText:SetPoint("RIGHT", noteCard, "RIGHT", -20, 0)
    noteText:SetJustifyH("LEFT")

    self.upcomingCooldownCheckbox = upcomingCooldownSwitch
    self.countdownVoiceCheckbox = countdownVoiceSwitch
    self.countdownVoiceDropdown = countdownVoiceDropdown
    self.voicePreviewButton = voicePreviewButton
    self.alertResetButton = resetButton
    self.alertControls = controls
    self.alertControlKinds = kinds
    -- [STYLE] Scroll through every card, including layout and element switches below the sample.
    page.contentHeight = page.rowCursor - PAGE_ROW_GAP
    page:SetHeight(page.contentHeight)
    self:PositionAlertSample()
    return page
end

function Options:CreateModernCooldownPage(parent, styleLib, fontPath, colors)
    local accent = styleLib.GetAccent(ADDON_KEY)
    local page = CreateModernPage(parent, 760)

    local presetCard = CreateRowCard(page, colors, 120, accent)

    local specLabel = MakeFont(presetCard, fontPath, SMALL_TEXT, colors.text.dim, "현재 전문화")
    specLabel:SetPoint("TOPLEFT", presetCard, "TOPLEFT", 20, -17)
    local specText = MakeFont(presetCard, fontPath, 15, colors.text.highlight, "")
    specText:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -6)

    local presets = {
        { text = "주요만", mode = "major", width = 76 },
        { text = "주요 + 세미", mode = "healing", width = 96 },
        { text = "전체", mode = "all", width = 58 },
        { text = "전체 해제", mode = "none", width = 76 },
        { text = "기본값", mode = "default", width = 68 },
    }
    local previous
    local presetButtons = {}
    for _, preset in ipairs(presets) do
        local button
        button = styleLib.CreateButton(presetCard, ADDON_KEY, preset.text, function()
            local applied = Options:SetCooldownPreset(preset.mode)
            if applied and styleLib.AppliedFeedback then -- [STYLE]
                -- Presets are exclusive: only the latest one keeps the feedback label.
                if styleLib.CancelAppliedFeedback then
                    for _, other in ipairs(presetButtons) do
                        if other ~= button then styleLib.CancelAppliedFeedback(other.label) end
                    end
                end
                local deferred = type(InCombatLockdown) == "function" and InCombatLockdown()
                styleLib.AppliedFeedback(button, button.label, {
                    text = deferred and "전투 후" or "적용됨",
                })
            end
        end, { width = preset.width, height = 26 })
        presetButtons[#presetButtons + 1] = button
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 7, 0)
        else
            button:SetPoint("BOTTOMLEFT", presetCard, "BOTTOMLEFT", 20, 17)
        end
        previous = button
    end

    local listRoot = AddPageRow(page, 1)

    local noSpecCard = CreateCard(listRoot, colors, 92, accent)
    noSpecCard:SetPoint("TOPLEFT", listRoot, "TOPLEFT", 0, 0)
    noSpecCard:SetPoint("TOPRIGHT", listRoot, "TOPRIGHT", 0, 0)
    local noSpecText = MakeFont(
        noSpecCard,
        fontPath,
        12,
        colors.text.dim,
        "지원하는 전문화로 변경하면 해당 주문 선택 항목이 자동으로 표시됩니다."
    )
    noSpecText:SetPoint("LEFT", noSpecCard, "LEFT", 20, 0)
    noSpecText:SetPoint("RIGHT", noSpecCard, "RIGHT", -20, 0)
    noSpecText:SetJustifyH("LEFT")

    self.cooldownSpecFrames = {}
    self.cooldownCheckboxes = {}
    for _, specID in ipairs(ns.CooldownCatalog:GetSpecIDs()) do
        local currentSpecID = specID
        local spec = ns.CooldownCatalog and ns.CooldownCatalog:GetSpec(currentSpecID)
        if spec then
            local specFrame = CreateFrame("Frame", nil, listRoot)
            specFrame:SetPoint("TOPLEFT", listRoot, "TOPLEFT", 0, 0)
            specFrame:SetPoint("TOPRIGHT", listRoot, "TOPRIGHT", 0, 0)
            specFrame:Hide()
            self.cooldownSpecFrames[currentSpecID] = specFrame
            self.cooldownCheckboxes[currentSpecID] = {}

            local cursorY = 0
            for _, group in ipairs(ns.CooldownCatalog:GetGroups()) do
                local groupSpells = {}
                for _, spell in ipairs(spec.spells) do
                    if spell.category == group.key then
                        groupSpells[#groupSpells + 1] = spell
                    end
                end

                if #groupSpells > 0 then
                    local rowCount = math.ceil(#groupSpells / 2)
                    local cardHeight = 66 + rowCount * SPELL_ROW_STEP
                    local groupCard = CreateCard(specFrame, colors, cardHeight)
                    groupCard:SetPoint("TOPLEFT", specFrame, "TOPLEFT", 0, -cursorY)
                    groupCard:SetPoint("TOPRIGHT", specFrame, "TOPRIGHT", 0, -cursorY)
                    AddCardHeader(
                        groupCard,
                        fontPath,
                        colors,
                        14,
                        SMALL_TEXT,
                        group.label,
                        group.description,
                        accent
                    )

                    for index, spell in ipairs(groupSpells) do
                        local column = (index - 1) % 2
                        local rowIndex = math.floor((index - 1) / 2)
                        local _, switch = CreateSpellRow(
                            groupCard,
                            styleLib,
                            fontPath,
                            colors,
                            currentSpecID,
                            spell,
                            column,
                            rowIndex
                        )
                        self.cooldownCheckboxes[currentSpecID][#self.cooldownCheckboxes[currentSpecID] + 1] = {
                            checkbox = switch,
                            spellID = spell.spellID,
                        }
                    end
                    cursorY = cursorY + cardHeight + 14
                end
            end

            local sourceCard = CreateCard(specFrame, colors, 68, accent, colors.bg.widget)
            sourceCard:SetPoint("TOPLEFT", specFrame, "TOPLEFT", 0, -cursorY)
            sourceCard:SetPoint("TOPRIGHT", specFrame, "TOPRIGHT", 0, -cursorY)
            local sourceTitle = MakeFont(sourceCard, fontPath, SMALL_TEXT, accent, "LORRGS 방식의 선택 분류")
            sourceTitle:SetPoint("TOPLEFT", sourceCard, "TOPLEFT", 20, -15)
            local sourceText = MakeFont(
                sourceCard,
                fontPath,
                SMALL_TEXT,
                colors.text.dim,
                "주요·보조·외생기·개인/유틸로 구분하며 실제 시전이 확인된 기술만 타임라인에 표시합니다."
            )
            sourceText:SetPoint("TOPLEFT", sourceTitle, "BOTTOMLEFT", 0, -7)
            sourceText:SetPoint("RIGHT", sourceCard, "RIGHT", -20, 0)
            sourceText:SetJustifyH("LEFT")
            cursorY = cursorY + 68

            specFrame:SetHeight(cursorY)
            specFrame.contentHeight = cursorY
        end
    end

    self.cooldownSpecText = specText
    self.cooldownNoSpecText = noSpecCard
    page.listRoot = listRoot
    page.baseHeight = 156
    return page
end

function Options:CreateModernProfilePage(parent, styleLib, fontPath, colors)
    local accent = styleLib.GetAccent(ADDON_KEY)
    local page = CreateModernPage(parent, 416)

    local summaryCard = CreateRowCard(page, colors, 174, accent)
    AddCardHeader(summaryCard, fontPath, colors, 14, SMALL_TEXT, "현재 선택", "자동으로 감지한 보스·난이도·전문화 기준입니다.")

    local profileSummary = MakeFont(summaryCard, fontPath, 13, colors.text.highlight, "")
    profileSummary:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 20, -72)
    profileSummary:SetPoint("RIGHT", summaryCard, "RIGHT", -230, 0)
    profileSummary:SetHeight(76)
    profileSummary:SetJustifyH("LEFT")
    profileSummary:SetJustifyV("TOP")

    local profileButton = styleLib.CreateButton(summaryCard, ADDON_KEY, "2차 스탯 · 특성 코드", function()
        if ns.HealerProfileUI then ns.HealerProfileUI:Show() end
    end, { width = 184, height = 30 })
    profileButton:SetPoint("RIGHT", summaryCard, "RIGHT", -20, -18)

    local cardsRow = AddPageRow(page, 124)
    local statsCard = CreateCard(cardsRow, colors, 124)
    statsCard:SetPoint("TOPLEFT", cardsRow, "TOPLEFT", 0, 0)
    statsCard:SetPoint("BOTTOMRIGHT", cardsRow, "BOTTOM", -8, 0)
    AddCardHeader(
        statsCard,
        fontPath,
        colors,
        14,
        SMALL_TEXT,
        "평균 2차 스탯",
        "치명타·가속·특화·유연성의 상위 표본 평균을 표시합니다.",
        accent
    )

    local talentCard = CreateCard(cardsRow, colors, 124)
    talentCard:SetPoint("TOPLEFT", cardsRow, "TOP", 8, 0)
    talentCard:SetPoint("BOTTOMRIGHT", cardsRow, "BOTTOMRIGHT", 0, 0)
    AddCardHeader(
        talentCard,
        fontPath,
        colors,
        14,
        SMALL_TEXT,
        "대표 특성",
        "가장 자주 사용된 빌드와 사용률, 복사 가능한 가져오기 코드를 제공합니다.",
        accent
    )

    local noteCard = CreateRowCard(page, colors, 72, nil, colors.bg.widget)
    local note = MakeFont(
        noteCard,
        fontPath,
        SMALL_TEXT,
        colors.text.dim,
        "대표 특성 코드는 저장한 노드와 현재 게임의 특성 트리 해시를 조합해 런타임에 생성합니다."
    )
    note:SetPoint("LEFT", noteCard, "LEFT", 20, 0)
    note:SetPoint("RIGHT", noteCard, "RIGHT", -20, 0)
    note:SetJustifyH("LEFT")

    self.profileSummary = profileSummary
    self.profileButton = profileButton
    return page
end

function Options:CreateModernDataPage(parent, styleLib, fontPath, colors)
    local accent = styleLib.GetAccent(ADDON_KEY)
    local page = CreateModernPage(parent, 274)

    local statusCard = CreateRowCard(page, colors, 174, accent)
    AddCardHeader(statusCard, fontPath, colors, 14, SMALL_TEXT, "설치 상태", "현재 게임에 로드된 영웅·신화 데이터 모델입니다.")

    local dataSummary = MakeFont(statusCard, fontPath, 13, colors.text.highlight, "")
    dataSummary:SetPoint("TOPLEFT", statusCard, "TOPLEFT", 20, -72)
    dataSummary:SetPoint("RIGHT", statusCard, "RIGHT", -220, 0)
    dataSummary:SetHeight(82)
    dataSummary:SetJustifyH("LEFT")
    dataSummary:SetJustifyV("TOP")

    local reloadButton = styleLib.CreateButton(statusCard, ADDON_KEY, "데이터 다시 불러오기", function()
        Options:ReloadData()
    end, { width = 174, height = 30 })
    reloadButton:SetPoint("RIGHT", statusCard, "RIGHT", -20, -18)

    local privacyCard = CreateRowCard(page, colors, 76, accent, colors.bg.widget)
    local privacyTitle = MakeFont(privacyCard, fontPath, SMALL_TEXT, accent, "공개 로그만 사용")
    privacyTitle:SetPoint("TOPLEFT", privacyCard, "TOPLEFT", 20, -16)
    local privacyText = MakeFont(
        privacyCard,
        fontPath,
        SMALL_TEXT,
        colors.text.dim,
        "데이터 팩에는 캐릭터 이름·서버·보고서 코드·API 자격 정보를 저장하지 않습니다."
    )
    privacyText:SetPoint("TOPLEFT", privacyTitle, "BOTTOMLEFT", 0, -7)
    privacyText:SetPoint("RIGHT", privacyCard, "RIGHT", -20, 0)
    privacyText:SetJustifyH("LEFT")

    self.dataSummary = dataSummary
    self.reloadButton = reloadButton
    return page
end

function Options:UpdateModernContentHeight(page)
    if not self.modernWorkspace or not page or not self.contentChild then return end
    local height = page.contentHeight or page:GetHeight() or 500
    self.contentChild:SetHeight(math.max(1, height + 38))
    if self.contentScroll and self.contentScroll._updateThumb then
        self.contentScroll._updateThumb()
    end
end

function Options:SelectPage(key)
    if not self.modernWorkspace then
        return LegacySelectPage(self, key)
    end

    key = self.pages and self.pages[key] and key or "timeline"
    local previousPage = self.activePage
    for pageKey, page in pairs(self.pages) do
        page:SetShown(pageKey == key)
    end
    self.activePage = key
    if self.contentScroll and self.contentScroll.SetVerticalScroll then
        self.contentScroll:SetVerticalScroll(0)
    end
    if self.workspace and self.workspace.selectedPage ~= key then
        self.workspace:SelectPage(key, false)
    else
        self.workspace:SetPageMeta(key)
    end
    SyncPageRows(self.pages[key])
    self:UpdateModernContentHeight(self.pages[key])
    self:RefreshAll()

    -- [STYLE] Page switch: top-level detail rows fade/nudge in one after another.
    local styleLib = self.styleLib
    local rows = self.pages[key].rows
    if previousPage and previousPage ~= key and rows
        and styleLib and styleLib.StaggerIn
        and self.frame and self.frame:IsShown() then
        styleLib.StaggerIn(rows, { step = 0.03, offset = 4 })
    end
end

function Options:RefreshCooldownControls()
    LegacyRefreshCooldownControls(self)
    if not self.modernWorkspace or not self.pages or not self.pages.cooldowns then return end

    local specID = ns.Engine and ns.Engine.playerSpecID or nil
    local specFrame = self.cooldownSpecFrames and self.cooldownSpecFrames[specID]
    local contentHeight = specFrame and specFrame.contentHeight or 92
    local page = self.pages.cooldowns
    page.contentHeight = page.baseHeight + contentHeight
    page:SetHeight(page.contentHeight)
    if self.activePage == "cooldowns" then
        self:UpdateModernContentHeight(page)
    end
end

function Options:Initialize()
    if self.initialized then return end

    local styleLib = ns.GetStyleLib and ns:GetStyleLib()
        or _G.DDingUI_RaidHelperStyleLib -- [REFACTOR] private embedded copy only
    if not styleLib
        or not styleLib.CreateTitleBar
        or not styleLib.CreateSearchBox
        or not styleLib.CreateButton
        or not styleLib.CreateSlider
        or not styleLib.GetAccent
        or not styleLib.Colors then
        return LegacyInitialize(self)
    end

    local colors = styleLib.Colors
    RoundLib = styleLib -- [STYLE] rounded helpers for the workspace and page cards
    local fontPath = styleLib.GetFont and styleLib:GetFont("primary") or styleLib.Font.path
    local version = "2.1.1"
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata(ns.addonName, "Version") or version
    elseif type(GetAddOnMetadata) == "function" then
        version = GetAddOnMetadata(ns.addonName, "Version") or version
    end

    local panel = CreateWorkspace(styleLib, fontPath, colors, version)
    if not panel or not panel.frame or not panel.contentChild then
        return LegacyInitialize(self)
    end

    self.modernWorkspace = true
    self.styleLib = styleLib
    self.panel = panel
    self.frame = panel.frame
    self.tree = panel.treeMenu
    self.workspace = panel.workspace
    self.contentScroll = panel.contentScroll
    self.contentChild = panel.contentChild
    self.independentWindow = true

    self.pages = {
        timeline = self:CreateModernTimelinePage(panel.contentChild, styleLib, fontPath, colors),
        alert = self:CreateModernAlertPage(panel.contentChild, styleLib, fontPath, colors),
        cooldowns = self:CreateModernCooldownPage(panel.contentChild, styleLib, fontPath, colors),
        profile = self:CreateModernProfilePage(panel.contentChild, styleLib, fontPath, colors),
        data = self:CreateModernDataPage(panel.contentChild, styleLib, fontPath, colors),
    }

    panel.frame:HookScript("OnHide", function()
        local ui = ns.TimelineUI
        if ui and ui:IsPreviewMode() and not ui:IsEditSessionActive() then
            ui:SetPreviewMode(false, { noReopen = true })
        end
    end)
    panel.frame:SetScript("OnShow", function()
        Options:RefreshAll()
        SyncPageRows(Options.pages[Options.activePage or "timeline"])
        Options:UpdateModernContentHeight(Options.pages[Options.activePage or "timeline"])
    end)

    self.initialized = true
    self:SelectPage("timeline")
end
