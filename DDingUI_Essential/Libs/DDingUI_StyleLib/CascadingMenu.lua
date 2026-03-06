------------------------------------------------------
-- DDingUI_StyleLib :: CascadingMenu
-- 우클릭 컨텍스트 메뉴 (inspired by AbstractFramework)
-- 계단식 서브메뉴 지원
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetCursorPosition = GetCursorPosition

---------------------------------------------------------------------
-- Menu Pool
---------------------------------------------------------------------
local menuPool = {}
local activeMenus = {}

local ITEM_HEIGHT = 22
local MENU_PADDING = 4
local SEPARATOR_HEIGHT = 9
local MIN_WIDTH = 120
local MAX_WIDTH = 250
local SUB_OFFSET_X = -2

---------------------------------------------------------------------
-- Menu Item
---------------------------------------------------------------------
local function CreateMenuItem(parent)
    local item = CreateFrame("Button", nil, parent, "BackdropTemplate")
    item:SetHeight(ITEM_HEIGHT)
    item:EnableMouse(true)

    -- 배경 hover
    item.bg = item:CreateTexture(nil, "BACKGROUND")
    item.bg:SetAllPoints()
    item.bg:SetColorTexture(Lib.GetColor("hover"))
    item.bg:Hide()

    -- 텍스트
    item.text = item:CreateFontString(nil, "OVERLAY")
    item.text:SetFont(Lib:GetFont("primary"), Lib:GetFontSize("normal"), "")
    item.text:SetPoint("LEFT", 8, 0)
    item.text:SetPoint("RIGHT", -20, 0)
    item.text:SetJustifyH("LEFT")
    item.text:SetWordWrap(false)

    -- 서브메뉴 화살표
    item.arrow = item:CreateFontString(nil, "OVERLAY")
    item.arrow:SetFont(Lib:GetFont("primary"), Lib:GetFontSize("small"), "")
    item.arrow:SetPoint("RIGHT", -6, 0)
    item.arrow:SetText("▸")
    item.arrow:SetTextColor(Lib.GetColor("dim"))
    item.arrow:Hide()

    -- 체크마크
    item.check = item:CreateFontString(nil, "OVERLAY")
    item.check:SetFont(Lib:GetFont("primary"), Lib:GetFontSize("normal"), "")
    item.check:SetPoint("LEFT", 8, 0)
    item.check:SetText("✓")
    item.check:Hide()

    -- 아이콘
    item.icon = item:CreateTexture(nil, "ARTWORK")
    item.icon:SetSize(16, 16)
    item.icon:SetPoint("LEFT", 6, 0)
    item.icon:Hide()

    -- Hover 효과
    item:SetScript("OnEnter", function(self)
        if self._disabled then return end
        self.bg:Show()
        self.text:SetTextColor(Lib.GetColor("highlight"))

        -- 다른 열린 서브메뉴 닫기
        Lib._CloseSubMenus(self:GetParent():GetFrameLevel())

        -- 서브메뉴 열기
        if self._menuList then
            Lib._ShowSubMenu(self, self._menuList)
        end
    end)

    item:SetScript("OnLeave", function(self)
        self.bg:Hide()
        if not self._disabled then
            local color = self._color or "text"
            self.text:SetTextColor(Lib.GetColor(color))
        end
    end)

    item:SetScript("OnClick", function(self)
        if self._disabled then return end
        if self._menuList then return end -- 서브메뉴는 클릭으로 닫지 않음

        if self._func then
            self._func(self._value)
        end
        Lib.HideCascadingMenu()
    end)

    return item
end

local function CreateSeparator(parent)
    local sep = CreateFrame("Frame", nil, parent)
    sep:SetHeight(SEPARATOR_HEIGHT)

    local line = sep:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", 8, 0)
    line:SetPoint("RIGHT", -8, 0)
    line:SetColorTexture(Lib.GetColor("separator"))
    sep._line = line

    return sep
end

---------------------------------------------------------------------
-- Menu Frame
---------------------------------------------------------------------
local function GetMenuFrame()
    for _, menu in ipairs(menuPool) do
        if not menu._inUse then
            menu._inUse = true
            menu:Show()
            return menu
        end
    end

    -- 새로 생성
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)

    Lib.ApplyPixelBackdrop(menu, 1)
    menu:SetBackdropColor(Lib.GetColor("background"))
    menu:SetBackdropBorderColor(Lib.GetColor("border"))

    menu._items = {}
    menu._separators = {}
    menu._inUse = true

    tinsert(menuPool, menu)
    return menu
end

local function ResetMenuFrame(menu)
    menu._inUse = false
    menu:Hide()
    for _, item in ipairs(menu._items) do
        item:Hide()
        item._func = nil
        item._menuList = nil
        item._value = nil
        item._disabled = false
        item._color = nil
        item.arrow:Hide()
        item.check:Hide()
        item.icon:Hide()
    end
    for _, sep in ipairs(menu._separators) do
        sep:Hide()
    end
end

---------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------
local function LayoutMenu(menu, menuList)
    -- 텍스트 폭 측정용 임시 FontString
    local tempFS = menu:CreateFontString(nil, "OVERLAY")
    tempFS:SetFont(Lib:GetFont("primary"), Lib:GetFontSize("normal"), "")

    local itemIndex = 0
    local sepIndex = 0
    local yOffset = -MENU_PADDING
    local maxWidth = MIN_WIDTH
    local hasIcon = false

    -- 아이콘 존재 여부 사전 확인
    for _, entry in ipairs(menuList) do
        if entry.icon then hasIcon = true; break end
    end

    local textLeftOffset = hasIcon and 28 or 8

    for _, entry in ipairs(menuList) do
        if entry.isSeparator then
            sepIndex = sepIndex + 1
            local sep = menu._separators[sepIndex]
            if not sep then
                sep = CreateSeparator(menu)
                menu._separators[sepIndex] = sep
            end
            sep:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, yOffset)
            sep:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
            sep:Show()
            yOffset = yOffset - SEPARATOR_HEIGHT
        else
            itemIndex = itemIndex + 1
            local item = menu._items[itemIndex]
            if not item then
                item = CreateMenuItem(menu)
                menu._items[itemIndex] = item
            end

            -- 텍스트
            item.text:SetText(entry.text or "")
            item.text:SetPoint("LEFT", textLeftOffset, 0)
            tempFS:SetText(entry.text or "")
            local textWidth = tempFS:GetStringWidth() + textLeftOffset + 24
            if textWidth > maxWidth then maxWidth = textWidth end

            -- 색상
            local color = entry.color or "text"
            item._color = color
            if entry.disabled then
                item.text:SetTextColor(Lib.GetColor("disabled"))
                item._disabled = true
            else
                item.text:SetTextColor(Lib.GetColor(color))
                item._disabled = false
            end

            -- 콜백
            item._func = entry.func
            item._value = entry.value
            item._menuList = entry.menuList

            -- 서브메뉴 화살표
            if entry.menuList then
                item.arrow:Show()
            end

            -- 체크마크
            if entry.checked then
                item.check:Show()
                item.text:SetPoint("LEFT", textLeftOffset + 14, 0)
            end

            -- 아이콘
            if entry.icon then
                item.icon:SetTexture(entry.icon)
                if entry.iconCoords then
                    item.icon:SetTexCoord(unpack(entry.iconCoords))
                else
                    item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                item.icon:Show()
            end

            item:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PADDING, yOffset)
            item:SetPoint("RIGHT", menu, "RIGHT", -MENU_PADDING, 0)
            item:Show()
            yOffset = yOffset - ITEM_HEIGHT
        end
    end

    tempFS:Hide()

    maxWidth = math.min(maxWidth, MAX_WIDTH)
    local totalHeight = -yOffset + MENU_PADDING

    Lib.SetPxSize(menu, maxWidth, totalHeight)

    return maxWidth, totalHeight
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

--- 커서 위치 또는 anchor 프레임에 계단식 메뉴 표시
--- @param anchor Frame|nil  nil이면 커서 위치
--- @param menuList table  메뉴 항목 배열
--- @param anchorPoint string|nil  기본 "TOPLEFT"
--- @param relativePoint string|nil  기본 "BOTTOMLEFT"
--- @param offsetX number|nil
--- @param offsetY number|nil
function Lib.ShowCascadingMenu(anchor, menuList, anchorPoint, relativePoint, offsetX, offsetY)
    if not menuList or #menuList == 0 then return end

    Lib.HideCascadingMenu() -- 기존 메뉴 닫기

    local menu = GetMenuFrame()
    menu:SetFrameLevel(100)
    tinsert(activeMenus, menu)

    LayoutMenu(menu, menuList)

    if anchor then
        menu:ClearAllPoints()
        menu:SetPoint(
            anchorPoint or "TOPLEFT",
            anchor,
            relativePoint or "BOTTOMLEFT",
            offsetX or 0,
            offsetY or -2
        )
    else
        -- 커서 위치에 표시
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    -- 클릭 밖 닫기
    if not Lib._cascadeCloser then
        local closer = CreateFrame("Button", nil, UIParent)
        closer:SetAllPoints(UIParent)
        closer:SetFrameStrata("TOOLTIP")
        closer:SetFrameLevel(99) -- 메뉴보다 1 낮게
        closer:EnableMouse(true)
        closer:RegisterForClicks("AnyUp")
        closer:SetScript("OnClick", function()
            Lib.HideCascadingMenu()
        end)
        Lib._cascadeCloser = closer
    end
    Lib._cascadeCloser:Show()
end

--- 서브메뉴 표시 (내부)
function Lib._ShowSubMenu(parentItem, menuList)
    local menu = GetMenuFrame()
    local parentMenu = parentItem:GetParent()
    menu:SetFrameLevel(parentMenu:GetFrameLevel() + 2)
    tinsert(activeMenus, menu)

    local w, _ = LayoutMenu(menu, menuList)

    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", parentItem, "TOPRIGHT", SUB_OFFSET_X, MENU_PADDING)
end

--- 특정 레벨 이상 서브메뉴 닫기 (내부)
function Lib._CloseSubMenus(level)
    for i = #activeMenus, 1, -1 do
        local m = activeMenus[i]
        if m:GetFrameLevel() > level + 1 then
            ResetMenuFrame(m)
            tremove(activeMenus, i)
        end
    end
end

--- 모든 메뉴 닫기
function Lib.HideCascadingMenu()
    for i = #activeMenus, 1, -1 do
        ResetMenuFrame(activeMenus[i])
        tremove(activeMenus, i)
    end
    if Lib._cascadeCloser then
        Lib._cascadeCloser:Hide()
    end
end
