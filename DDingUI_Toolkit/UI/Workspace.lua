--[[
    DDingUI Toolkit - Three-column settings workspace
    Keeps the existing declarative settings renderer while replacing the
    legacy collapsible tree with category, module, and detail columns.
]]

local addonName, ns = ...
local Lib = LibStub("DDingUI-StyleLib-1.0")
local Controls = ns.ToolkitControls or Lib
local L = ns.L
local C = Lib.Colors
local F = Lib.Font
local SOLID = Lib.Textures and Lib.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local ADDON_KEY = "MJToolkit"

local Workspace = {}
ns.ToolkitWorkspace = Workspace

local PRIMARY_WIDTH = 190
local MODULE_WIDTH = 240
local TOP_HEIGHT = 42
local DETAIL_HEADER_HEIGHT = 86
local PRIMARY_ROW_HEIGHT = 56
local MODULE_ROW_HEIGHT = 48
local RESIZE_GRIP_SIZE = 32
local RESIZE_GRIP_MARGIN = 4
local RESIZE_GRIP_CLEARANCE = RESIZE_GRIP_SIZE + (RESIZE_GRIP_MARGIN * 2)

local ICON_ROOT = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\Navigation\\"

local CATEGORY_DEFS = {
    {
        key = "dashboard",
        label = L["WORKSPACE_DASHBOARD"],
        icon = ICON_ROOT .. "Dashboard.tga",
        panels = { "overview" },
    },
    {
        key = "combat",
        label = L["WORKSPACE_COMBAT"],
        icon = ICON_ROOT .. "Combat.tga",
        panels = {
            "combattimer",
            "castingalert",
            "focusinterrupt",
            "rangedisplay",
            "characterpositionmarker",
        },
    },
    {
        key = "party",
        label = L["WORKSPACE_PARTY_RAID"],
        icon = ICON_ROOT .. "PartyRaid.tga",
        panels = {
            "partytracker",
            "mythicplus",
            "goldsplit",
            "raidlootpass",
        },
    },
    {
        key = "alerts",
        label = L["WORKSPACE_ALERTS"],
        icon = ICON_ROOT .. "Alerts.tga",
        panels = {
            "lfgalert",
            "partyfullalert",
            "mailalert",
            "deathalert",
            "durability",
        },
    },
    {
        key = "display",
        label = L["WORKSPACE_DISPLAY"],
        icon = ICON_ROOT .. "Display.tga",
        panels = {
            "talentbg",
            "cursortrail",
            "itemlevel",
            "skyridingtracker",
        },
    },
    {
        key = "utility",
        label = L["WORKSPACE_UTILITY"],
        icon = ICON_ROOT .. "Utility.tga",
        panels = {
            "notepad",
            "autorepair",
        },
    },
    {
        key = "profile",
        label = L["WORKSPACE_PROFILE"],
        icon = ICON_ROOT .. "Profile.tga",
        panels = { "profile" },
        bottom = true,
    },
}

local CATEGORY_BY_KEY = {}
local PANEL_CATEGORY = {}
for _, category in ipairs(CATEGORY_DEFS) do
    CATEGORY_BY_KEY[category.key] = category
    for _, panelKey in ipairs(category.panels) do
        PANEL_CATEGORY[panelKey] = category.key
    end
end

local function UnpackColor(color, fallbackAlpha)
    return color[1], color[2], color[3], color[4] or fallbackAlpha or 1
end

local function SetBackdrop(frame, background, border)
    frame:SetBackdrop({
        bgFile = SOLID,
        edgeFile = SOLID,
        edgeSize = 1,
    })
    frame:SetBackdropColor(UnpackColor(background))
    frame:SetBackdropBorderColor(UnpackColor(border))
end

local function MakeFont(parent, size, color, text)
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    fontString:SetFont(F.path, size, "")
    fontString:SetTextColor(UnpackColor(color))
    fontString:SetText(text or "")
    return fontString
end

local function CleanLabel(text)
    text = tostring(text or "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function CreateDivider(parent, point, relativeTo, relativePoint, x, y, vertical)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(UnpackColor(C.border.separator))
    divider:SetPoint(point, relativeTo, relativePoint, x, y)
    if vertical then
        divider:SetWidth(1)
    else
        divider:SetHeight(1)
    end
    return divider
end

local function CreateToggle(parent, onChanged)
    local from = Lib.GetAccent(ADDON_KEY)
    local toggle = CreateFrame("Button", nil, parent, "BackdropTemplate")
    toggle:SetSize(18, 18)
    SetBackdrop(toggle, C.bg.widget, C.border.default)

    local fill = toggle:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(from[1], from[2], from[3], 1)

    function toggle:SetValue(value, silent)
        self.value = value ~= false
        fill:SetShown(self.value)
        if self.value then
            self:SetBackdropBorderColor(from[1], from[2], from[3], 0.9)
        else
            self:SetBackdropBorderColor(UnpackColor(C.border.default))
        end
        if not silent and onChanged then
            onChanged(self.value)
        end
    end

    toggle:SetScript("OnClick", function(self)
        self:SetValue(not self.value)
    end)
    toggle:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(from[1], from[2], from[3], 0.8)
    end)
    toggle:SetScript("OnLeave", function(self)
        self:SetValue(self.value, true)
    end)
    toggle:SetValue(false, true)
    return toggle
end

local function CreateSmoothScroll(scrollFrame, options)
    options = options or {}
    local speed = options.speed or 12
    local step = options.step or 60
    local target = 0
    local smoothing = false

    local driver = CreateFrame("Frame")
    driver:Hide()

    local function GetRange()
        local child = scrollFrame:GetScrollChild()
        if not child then return 0 end
        return math.max(0, (child:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
    end

    driver:SetScript("OnUpdate", function(self, elapsed)
        local current = scrollFrame:GetVerticalScroll()
        local range = GetRange()
        target = math.max(0, math.min(range, target))
        local difference = target - current
        if math.abs(difference) < 0.5 then
            scrollFrame:SetVerticalScroll(target)
            smoothing = false
            self:Hide()
            return
        end
        local nextValue = current + difference * math.min(1, speed * elapsed)
        scrollFrame:SetVerticalScroll(math.max(0, math.min(range, nextValue)))
    end)

    local controller = {}

    function controller:ScrollTo(value)
        target = math.max(0, math.min(GetRange(), tonumber(value) or 0))
        if not smoothing then
            smoothing = true
            driver:Show()
        end
    end

    function controller:OnMouseWheel(delta)
        local range = GetRange()
        if range <= 0 then return end
        local base = smoothing and target or scrollFrame:GetVerticalScroll()
        self:ScrollTo(base - delta * step)
    end

    function controller:Stop()
        smoothing = false
        target = scrollFrame:GetVerticalScroll()
        driver:Hide()
    end

    function controller:Reset(value)
        self:Stop()
        target = tonumber(value) or 0
        scrollFrame:SetVerticalScroll(target)
    end

    return controller
end

local function CreateScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local smooth = CreateSmoothScroll(scroll, { speed = 12, step = 60 })

    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(5)
    track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -4)
    track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, RESIZE_GRIP_CLEARANCE)

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAllPoints()
    thumbTexture:SetColorTexture(0.48, 0.49, 0.52, 0.8)

    local function UpdateThumb()
        local range = scroll:GetVerticalScrollRange() or 0
        local viewHeight = scroll:GetHeight() or 1
        local contentHeight = math.max(child:GetHeight() or 1, viewHeight)
        local trackHeight = track:GetHeight() or 1
        local thumbHeight = math.max(28, trackHeight * (viewHeight / contentHeight))
        thumb:SetHeight(math.min(trackHeight, thumbHeight))

        if range <= 0 or trackHeight <= thumbHeight then
            thumb:Hide()
            return
        end

        thumb:Show()
        local progress = math.max(0, math.min(1, scroll:GetVerticalScroll() / range))
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -((trackHeight - thumbHeight) * progress))
    end

    local function SetFromCursor()
        smooth:Stop()
        local _, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cursorY = cursorY / scale
        local top = track:GetTop() or cursorY
        local trackHeight = track:GetHeight() or 1
        local thumbHeight = thumb:GetHeight() or 28
        local progress = (top - cursorY - thumbHeight * 0.5) / math.max(1, trackHeight - thumbHeight)
        progress = math.max(0, math.min(1, progress))
        scroll:SetVerticalScroll((scroll:GetVerticalScrollRange() or 0) * progress)
        UpdateThumb()
    end

    scroll:SetScript("OnMouseWheel", function(self, delta)
        smooth:OnMouseWheel(delta)
    end)
    scroll:SetScript("OnVerticalScroll", UpdateThumb)
    scroll:SetScript("OnScrollRangeChanged", UpdateThumb)
    scroll:SetScript("OnSizeChanged", function(_, width)
        child:SetWidth(math.max(1, width - 12))
        UpdateThumb()
    end)
    child:SetScript("OnSizeChanged", UpdateThumb)

    track:EnableMouse(true)
    track:SetScript("OnMouseDown", SetFromCursor)
    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function(self)
        smooth:Stop()
        self:SetScript("OnUpdate", SetFromCursor)
    end)
    thumb:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    thumb:SetScript("OnEnter", function()
        thumbTexture:SetColorTexture(0.72, 0.73, 0.76, 1)
    end)
    thumb:SetScript("OnLeave", function()
        thumbTexture:SetColorTexture(0.48, 0.49, 0.52, 0.8)
    end)

    scroll._updateThumb = UpdateThumb
    scroll._track = track
    scroll._thumb = thumb
    scroll._smoothController = smooth
    return scroll, child
end

local function CreateResizeGrip(frame)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(RESIZE_GRIP_SIZE, RESIZE_GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -RESIZE_GRIP_MARGIN, RESIZE_GRIP_MARGIN)
    grip:SetFrameLevel(frame:GetFrameLevel() + 80)
    grip:EnableMouse(true)
    grip:SetHitRectInsets(-4, -4, -4, -4)

    local vertical = grip:CreateTexture(nil, "OVERLAY")
    vertical:SetSize(4, 20)
    vertical:SetPoint("BOTTOMRIGHT", -2, 2)
    vertical:SetColorTexture(0.65, 0.65, 0.67, 0.8)

    local horizontal = grip:CreateTexture(nil, "OVERLAY")
    horizontal:SetSize(20, 4)
    horizontal:SetPoint("BOTTOMRIGHT", -2, 2)
    horizontal:SetColorTexture(0.65, 0.65, 0.67, 0.8)

    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function(self)
        self._sizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnDragStop", function(self)
        self._sizing = false
        frame:StopMovingOrSizing()
    end)
    grip:SetScript("OnEnter", function()
        local accent = Lib.GetAccent(ADDON_KEY)
        vertical:SetColorTexture(accent[1], accent[2], accent[3], 1)
        horizontal:SetColorTexture(accent[1], accent[2], accent[3], 1)
    end)
    grip:SetScript("OnLeave", function()
        if grip._sizing then return end
        vertical:SetColorTexture(0.65, 0.65, 0.67, 0.8)
        horizontal:SetColorTexture(0.65, 0.65, 0.67, 0.8)
    end)
    frame._resizeGrip = grip
    return grip
end

local function RegisterEscapeFrame(frame)
    local name = frame:GetName()
    for _, registeredName in ipairs(UISpecialFrames) do
        if registeredName == name then return end
    end
    table.insert(UISpecialFrames, name)
end

function Workspace:Create(title, version, opts)
    opts = opts or {}

    local existing = _G.DDingUI_MJToolkit_Panel
    if existing and existing._panelResult then
        return existing._panelResult
    end

    local from = Lib.GetAccent(ADDON_KEY)
    local frame = CreateFrame("Frame", "DDingUI_MJToolkit_Panel", UIParent, "BackdropTemplate")
    frame:SetSize(opts.width or 1180, opts.height or 720)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(opts.minWidth or 930, opts.minHeight or 580)
    frame:SetClampedToScreen(true)
    SetBackdrop(frame, C.bg.main, { 0, 0, 0, 1 })
    frame:Hide()

    local titleBar = Lib.CreateTitleBar(frame, ADDON_KEY, title, version)
    titleBar:SetHeight(TOP_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local primaryFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    primaryFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -TOP_HEIGHT)
    primaryFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    primaryFrame:SetWidth(PRIMARY_WIDTH)
    SetBackdrop(primaryFrame, C.bg.sidebar, { 0, 0, 0, 0 })

    local moduleFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    moduleFrame:SetPoint("TOPLEFT", primaryFrame, "TOPRIGHT", 0, 0)
    moduleFrame:SetPoint("BOTTOMLEFT", primaryFrame, "BOTTOMRIGHT", 0, 0)
    moduleFrame:SetWidth(MODULE_WIDTH)
    SetBackdrop(moduleFrame, { 0.075, 0.075, 0.08, 0.98 }, { 0, 0, 0, 0 })

    local contentHeader = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentHeader:SetPoint("TOPLEFT", moduleFrame, "TOPRIGHT", 1, 0)
    contentHeader:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -TOP_HEIGHT)
    contentHeader:SetHeight(DETAIL_HEADER_HEIGHT)
    SetBackdrop(contentHeader, { 0.095, 0.095, 0.105, 0.98 }, { 0, 0, 0, 0 })

    local contentFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentFrame:SetPoint("TOPLEFT", contentHeader, "BOTTOMLEFT", 0, -1)
    contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    SetBackdrop(contentFrame, C.bg.main, { 0, 0, 0, 0 })

    local primaryDivider = CreateDivider(frame, "TOPLEFT", primaryFrame, "TOPRIGHT", 0, 0, true)
    primaryDivider:SetPoint("BOTTOMLEFT", primaryFrame, "BOTTOMRIGHT", 0, 0)
    local moduleDivider = CreateDivider(frame, "TOPLEFT", moduleFrame, "TOPRIGHT", 0, 0, true)
    moduleDivider:SetPoint("BOTTOMLEFT", moduleFrame, "BOTTOMRIGHT", 0, 0)
    local headerDivider = CreateDivider(contentHeader, "BOTTOMLEFT", contentHeader, "BOTTOMLEFT", 0, 0, false)
    headerDivider:SetPoint("BOTTOMRIGHT", contentHeader, "BOTTOMRIGHT", 0, 0)

    local contentScroll, contentChild = CreateScrollArea(contentFrame)
    contentScroll:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -8)
    contentScroll:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -10, 8)

    local workspace = CreateFrame("Frame", nil, frame)
    workspace:SetAllPoints()
    workspace.categories = CATEGORY_DEFS
    workspace.categoryByKey = CATEGORY_BY_KEY
    workspace.panelCategory = PANEL_CATEGORY
    workspace.selectedCategory = "dashboard"
    workspace.selectedPanel = "overview"
    workspace.opts = opts
    workspace.primaryRows = {}
    workspace.moduleRows = {}

    local detailTitle = MakeFont(contentHeader, 18, C.text.highlight)
    detailTitle:SetPoint("TOPLEFT", contentHeader, "TOPLEFT", 24, -18)
    detailTitle:SetPoint("RIGHT", contentHeader, "RIGHT", -150, 0)
    detailTitle:SetJustifyH("LEFT")

    local detailDescription = MakeFont(contentHeader, F.normal, C.text.dim)
    detailDescription:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -8)
    detailDescription:SetPoint("RIGHT", contentHeader, "RIGHT", -150, 0)
    detailDescription:SetJustifyH("LEFT")
    detailDescription:SetWordWrap(true)

    local detailToggleLabel = MakeFont(contentHeader, F.small, C.text.dim, L["WORKSPACE_ACTIVE"])
    detailToggleLabel:SetPoint("TOPRIGHT", contentHeader, "TOPRIGHT", -66, -22)

    local detailToggle
    detailToggle = CreateToggle(contentHeader, function(value)
        if workspace.selectedPanel and workspace.opts.onModuleToggle then
            workspace.opts.onModuleToggle(workspace.selectedPanel, value)
        end
    end)
    detailToggle:SetPoint("LEFT", detailToggleLabel, "RIGHT", 10, 0)

    local moduleTitle = MakeFont(moduleFrame, 18, C.text.highlight)
    moduleTitle:SetPoint("TOPLEFT", moduleFrame, "TOPLEFT", 20, -17)
    moduleTitle:SetPoint("RIGHT", moduleFrame, "RIGHT", -18, 0)
    moduleTitle:SetJustifyH("LEFT")

    local moduleSearch = Controls.CreateSearchBox(moduleFrame, MODULE_WIDTH - 32, {
        placeholder = L["WORKSPACE_FILTER"],
    })
    moduleSearch:SetPoint("TOPLEFT", moduleFrame, "TOPLEFT", 16, -50)

    local moduleList = CreateFrame("Frame", nil, moduleFrame)
    moduleList:SetPoint("TOPLEFT", moduleFrame, "TOPLEFT", 0, -84)
    moduleList:SetPoint("BOTTOMRIGHT", moduleFrame, "BOTTOMRIGHT", 0, 0)

    local function GetPanelDef(panelKey)
        return ns.ConfigTree and ns.ConfigTree.panels and ns.ConfigTree.panels[panelKey]
    end

    local function GetPanelLabel(panelKey)
        local panelDef = GetPanelDef(panelKey)
        return CleanLabel(panelDef and panelDef.title or panelKey)
    end

    local function PanelMatches(panelKey, query)
        if not query or query == "" then return true end
        query = query:lower()
        local panelDef = GetPanelDef(panelKey)
        if GetPanelLabel(panelKey):lower():find(query, 1, true) then return true end
        if panelDef and panelDef.desc and CleanLabel(panelDef.desc):lower():find(query, 1, true) then
            return true
        end
        for _, setting in ipairs(panelDef and panelDef.settings or {}) do
            if setting.label and CleanLabel(setting.label):lower():find(query, 1, true) then
                return true
            end
        end
        return false
    end

    local function ApplyPrimaryState(row)
        local active = row.categoryKey == workspace.selectedCategory
        row.active = active
        row.activeBar:SetShown(active)
        if active then
            row.background:SetColorTexture(0.115, 0.115, 0.13, 0.96)
            row.icon:SetVertexColor(from[1], from[2], from[3], 1)
            row.label:SetTextColor(1, 1, 1, 1)
        else
            row.background:SetColorTexture(0, 0, 0, 0)
            row.icon:SetVertexColor(0.67, 0.68, 0.71, 1)
            row.label:SetTextColor(UnpackColor(C.text.normal))
        end
    end

    local function AcquirePrimaryRow(index)
        local row = workspace.primaryRows[index]
        if row then return row end

        row = CreateFrame("Button", nil, primaryFrame)
        row:SetHeight(PRIMARY_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")

        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints()

        row.activeBar = row:CreateTexture(nil, "ARTWORK")
        row.activeBar:SetPoint("TOPLEFT")
        row.activeBar:SetPoint("BOTTOMLEFT")
        row.activeBar:SetWidth(3)
        row.activeBar:SetColorTexture(from[1], from[2], from[3], 1)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 20, 0)
        row.icon:SetTexCoord(0, 1, 0, 1)

        row.label = MakeFont(row, F.normal, C.text.normal)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 16, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row.label:SetJustifyH("LEFT")

        row.divider = row:CreateTexture(nil, "BORDER")
        row.divider:SetPoint("BOTTOMLEFT")
        row.divider:SetPoint("BOTTOMRIGHT")
        row.divider:SetHeight(1)
        row.divider:SetColorTexture(0.20, 0.20, 0.22, 0.48)

        row:SetScript("OnEnter", function(self)
            if not self.active then
                self.background:SetColorTexture(0.12, 0.12, 0.14, 0.72)
                self.label:SetTextColor(0.92, 0.92, 0.94, 1)
            end
        end)
        row:SetScript("OnLeave", ApplyPrimaryState)
        row:SetScript("OnClick", function(self)
            workspace:SelectCategory(self.categoryKey, true)
        end)

        workspace.primaryRows[index] = row
        return row
    end

    local function RefreshPrimaryRows()
        local topIndex = 0
        for index, category in ipairs(CATEGORY_DEFS) do
            local row = AcquirePrimaryRow(index)
            row:ClearAllPoints()
            if category.bottom then
                row:SetPoint("BOTTOMLEFT", primaryFrame, "BOTTOMLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", primaryFrame, "TOPLEFT", 0, -(topIndex * PRIMARY_ROW_HEIGHT))
                topIndex = topIndex + 1
            end
            row:SetPoint("RIGHT", primaryFrame, "RIGHT", 0, 0)
            row.categoryKey = category.key
            row.icon:SetTexture(category.icon)
            row.label:SetText(category.label)
            row:Show()
            ApplyPrimaryState(row)
        end
    end

    local function ApplyModuleState(row)
        local active = row.panelKey == workspace.selectedPanel
        row.active = active
        row.activeBar:SetShown(active)
        if active then
            row.background:SetColorTexture(0.12, 0.12, 0.135, 0.98)
            row.label:SetTextColor(from[1], from[2], from[3], 1)
        else
            row.background:SetColorTexture(0, 0, 0, 0)
            row.label:SetTextColor(UnpackColor(C.text.normal))
        end

        local panelDef = GetPanelDef(row.panelKey)
        if panelDef and panelDef.moduleEnableKey then
            local enabled = ns:GetDBValue(panelDef.moduleEnableKey)
            row.toggle:SetValue(enabled ~= false, true)
            row.toggle:Show()
            row.status:SetColorTexture(
                enabled ~= false and 0.28 or 0.48,
                enabled ~= false and 0.82 or 0.48,
                enabled ~= false and 0.70 or 0.48,
                1
            )
        else
            row.toggle:Hide()
            row.status:SetColorTexture(from[1], from[2], from[3], 0.8)
        end
    end

    local function AcquireModuleRow(index)
        local row = workspace.moduleRows[index]
        if row then return row end

        row = CreateFrame("Button", nil, moduleList)
        row:SetHeight(MODULE_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")

        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints()

        row.activeBar = row:CreateTexture(nil, "ARTWORK")
        row.activeBar:SetPoint("TOPLEFT")
        row.activeBar:SetPoint("BOTTOMLEFT")
        row.activeBar:SetWidth(2)
        row.activeBar:SetColorTexture(from[1], from[2], from[3], 1)

        row.status = row:CreateTexture(nil, "ARTWORK")
        row.status:SetSize(7, 7)
        row.status:SetPoint("LEFT", 16, 0)

        row.label = MakeFont(row, F.normal, C.text.normal)
        row.label:SetPoint("LEFT", row.status, "RIGHT", 12, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        row.toggle = CreateToggle(row, function(value)
            if row.panelKey and workspace.opts.onModuleToggle then
                workspace.opts.onModuleToggle(row.panelKey, value)
            end
        end)
        row.toggle:SetSize(18, 18)
        row.toggle:SetPoint("RIGHT", row, "RIGHT", -14, 0)
        row.toggle:SetFrameLevel(row:GetFrameLevel() + 4)

        row.divider = row:CreateTexture(nil, "BORDER")
        row.divider:SetPoint("BOTTOMLEFT", 12, 0)
        row.divider:SetPoint("BOTTOMRIGHT", -12, 0)
        row.divider:SetHeight(1)
        row.divider:SetColorTexture(0.20, 0.20, 0.22, 0.40)

        row:SetScript("OnEnter", function(self)
            if not self.active then
                self.background:SetColorTexture(0.12, 0.12, 0.14, 0.68)
                self.label:SetTextColor(0.94, 0.94, 0.95, 1)
            end
        end)
        row:SetScript("OnLeave", ApplyModuleState)
        row:SetScript("OnClick", function(self)
            workspace:SelectPanel(self.panelKey, true)
        end)

        workspace.moduleRows[index] = row
        return row
    end

    function workspace:GetCategoryPanels(categoryKey)
        local category = CATEGORY_BY_KEY[categoryKey]
        return category and category.panels or {}
    end

    function workspace:RefreshModuleRows(query, acrossAll)
        local panelKeys = {}
        if acrossAll and query and query ~= "" then
            for _, category in ipairs(CATEGORY_DEFS) do
                for _, panelKey in ipairs(category.panels) do
                    if PanelMatches(panelKey, query) then
                        panelKeys[#panelKeys + 1] = panelKey
                    end
                end
            end
            moduleTitle:SetText(L["WORKSPACE_SEARCH_RESULTS"])
        else
            local category = CATEGORY_BY_KEY[self.selectedCategory]
            moduleTitle:SetText(category and category.label or "")
            for _, panelKey in ipairs(self:GetCategoryPanels(self.selectedCategory)) do
                if PanelMatches(panelKey, query) then
                    panelKeys[#panelKeys + 1] = panelKey
                end
            end
        end

        for index, panelKey in ipairs(panelKeys) do
            local row = AcquireModuleRow(index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", moduleList, "TOPLEFT", 0, -((index - 1) * MODULE_ROW_HEIGHT))
            row:SetPoint("RIGHT", moduleList, "RIGHT", 0, 0)
            row.panelKey = panelKey
            row.label:SetText(GetPanelLabel(panelKey))
            row:Show()
            ApplyModuleState(row)
        end
        for index = #panelKeys + 1, #self.moduleRows do
            self.moduleRows[index]:Hide()
        end
    end

    function workspace:SetPanelMeta(panelKey)
        local panelDef = GetPanelDef(panelKey)
        detailTitle:SetText(GetPanelLabel(panelKey))
        detailDescription:SetText(CleanLabel(panelDef and panelDef.desc or ""))
        detailDescription:SetShown(panelDef and panelDef.desc and panelDef.desc ~= "")

        if panelDef and panelDef.moduleEnableKey then
            detailToggleLabel:Show()
            detailToggle:Show()
            detailToggle:SetValue(ns:GetDBValue(panelDef.moduleEnableKey) ~= false, true)
        else
            detailToggleLabel:Hide()
            detailToggle:Hide()
        end
    end

    function workspace:SelectCategory(categoryKey, notify)
        local category = CATEGORY_BY_KEY[categoryKey]
        if not category then return false end
        if Controls.CloseDropdowns then Controls.CloseDropdowns() end
        self.selectedCategory = categoryKey
        moduleSearch:SetText("")
        RefreshPrimaryRows()
        self:RefreshModuleRows()

        local panelKey = category.panels[1]
        if panelKey then
            self:SelectPanel(panelKey, notify)
        end
        return true
    end

    function workspace:SelectPanel(panelKey, notify)
        if not GetPanelDef(panelKey) then return false end
        if Controls.CloseDropdowns then Controls.CloseDropdowns() end

        local categoryKey = PANEL_CATEGORY[panelKey]
        if categoryKey and categoryKey ~= self.selectedCategory then
            self.selectedCategory = categoryKey
            moduleSearch:SetText("")
            RefreshPrimaryRows()
            self:RefreshModuleRows()
        end

        self.selectedPanel = panelKey
        self:SetPanelMeta(panelKey)
        for _, row in ipairs(self.moduleRows) do
            if row:IsShown() then ApplyModuleState(row) end
        end

        if notify and self.opts.onSelect then
            self.opts.onSelect(panelKey)
        end
        return true
    end

    function workspace:FilterModules(query)
        self:RefreshModuleRows(query, query and query ~= "")
    end

    function workspace:RefreshModuleStates()
        self:SetPanelMeta(self.selectedPanel)
        for _, row in ipairs(self.moduleRows) do
            if row:IsShown() then ApplyModuleState(row) end
        end
    end

    moduleSearch:SetOnTextChanged(function(text)
        workspace:RefreshModuleRows(text, false)
    end)

    local treeAdapter = {}
    function treeAdapter:SetSelected(panelKey)
        return workspace:SelectPanel(panelKey, false)
    end
    function treeAdapter:GetSelected()
        return workspace.selectedPanel
    end
    function treeAdapter:SetMenuData()
        workspace:RefreshModuleRows()
    end

    RefreshPrimaryRows()
    workspace:RefreshModuleRows()
    workspace:SetPanelMeta("overview")

    CreateResizeGrip(frame)
    RegisterEscapeFrame(frame)

    local result = {
        frame = frame,
        titleBar = titleBar,
        treeFrame = primaryFrame,
        moduleFrame = moduleFrame,
        contentHeader = contentHeader,
        contentFrame = contentFrame,
        contentScroll = contentScroll,
        contentChild = contentChild,
        divider = moduleDivider,
        workspace = workspace,
        treeMenu = treeAdapter,
        moduleSearch = moduleSearch,
    }
    frame._panelResult = result
    return result
end
