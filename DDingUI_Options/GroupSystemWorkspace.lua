local _, ns = ...
local DDingUI = ns.Addon
local GUI = DDingUI.GUI
local Base = DDingUI.GUIBase
local L = Base.L
local FLAT = Base.FLAT
local THEME = Base.THEME

local GROUP_LABEL_KEYS = {
    Cooldowns = "Essential Cooldowns",
    Buffs = "Buff Icons",
    Utility = "Utility Cooldowns",
}

local function T(key, fallback)
    return rawget(L, key) or fallback or key
end

local function FontPath()
    return DDingUI.GetGlobalFont and DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
end

local function SetSurface(frame, background, border)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function CreateText(parent, size, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(FontPath(), size, "")
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetJustifyH(justify or "LEFT")
    return text
end

local function CreateDivider(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
    line:SetHeight(1)
    line:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.82)
    return line
end

local function CreateButton(parent, label, accent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(26)
    local border = accent and THEME.accent or THEME.focus
    SetSurface(button, THEME.input, border)
    button.label = CreateText(button, 10, { 0.83, 0.85, 0.89, 1 }, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(label)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(border[1], border[2], border[3], 0.16)
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], 1)
        self.label:SetTextColor(0.83, 0.85, 0.89, 1)
    end)
    return button
end

local WORKSPACE_CATEGORIES = {
    {
        key = "layout",
        glyph = "↔",
        label = "Layout & Size",
        fallback = "배치와 크기",
        sections = {
            { key = "appearance", label = "Appearance", fallback = "외관" },
            { key = "position", label = "Position", fallback = "위치" },
        },
    },
    {
        key = "state",
        glyph = "◇",
        label = "Icon State",
        fallback = "아이콘 상태",
        requiresIcon = true,
        sections = {
            { key = "states", label = "State Display", fallback = "상태 표시" },
            { key = "advanced", label = "Advanced Display", fallback = "고급 표시" },
        },
    },
    {
        key = "text",
        glyph = "T",
        label = "Text",
        fallback = "텍스트",
        sections = {
            { key = "stack", label = "Stack Text", fallback = "중첩 텍스트" },
            { key = "cooldown", label = "Cooldown Text", fallback = "재사용 대기시간" },
            { key = "duration", label = "Duration Text", fallback = "지속시간" },
        },
    },
    {
        key = "effects",
        glyph = "✦",
        label = "Glow & Effects",
        fallback = "글로우와 효과",
        sections = {
            { key = "icon", label = "Icon Glow", fallback = "아이콘 글로우", requiresIcon = true },
            { key = "group", label = "Group Default Glow", fallback = "그룹 기본 글로우" },
            { key = "swipe", label = "Swipe", fallback = "스와이프" },
        },
    },
    {
        key = "animation",
        glyph = "▶",
        label = "Animation",
        fallback = "애니메이션",
    },
}

local CATEGORY_BY_KEY = {}
for _, definition in ipairs(WORKSPACE_CATEGORIES) do
    CATEGORY_BY_KEY[definition.key] = definition
end

local function CreateCategoryButton(parent, definition)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(50)
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()
    button.background:SetColorTexture(THEME.panelStrong[1], THEME.panelStrong[2], THEME.panelStrong[3], 0)
    button.accent = button:CreateTexture(nil, "ARTWORK")
    button.accent:SetPoint("TOPLEFT")
    button.accent:SetPoint("BOTTOMLEFT")
    button.accent:SetWidth(3)
    button.accent:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    button.glyph = CreateText(button, 18, { 0.58, 0.61, 0.67, 1 }, "CENTER")
    button.glyph:SetSize(34, 30)
    button.glyph:SetPoint("LEFT", button, "LEFT", 10, 0)
    button.glyph:SetText(definition.glyph)
    button.label = CreateText(button, 11, { 0.72, 0.74, 0.79, 1 })
    button.label:SetPoint("LEFT", button.glyph, "RIGHT", 8, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.label:SetText(T(definition.label, definition.fallback))

    function button:SetAvailable(available)
        self._available = available ~= false
        self:EnableMouse(self._available)
        self:SetAlpha(self._available and 1 or 0.36)
    end

    function button:SetActive(active)
        self._active = active == true
        self.accent:SetShown(self._active)
        self.background:SetAlpha(self._active and 0.9 or 0)
        if self._active then
            self.glyph:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            self.label:SetTextColor(0.97, 0.98, 1, 1)
        else
            self.glyph:SetTextColor(0.58, 0.61, 0.67, 1)
            self.label:SetTextColor(0.72, 0.74, 0.79, 1)
        end
    end

    button:SetScript("OnEnter", function(self)
        if self._available and not self._active then
            self.background:SetAlpha(0.45)
            self.label:SetTextColor(0.94, 0.95, 0.98, 1)
        end
    end)
    button:SetScript("OnLeave", function(self) self:SetActive(self._active) end)
    button:SetAvailable(true)
    button:SetActive(false)
    return button
end

local function CreateSubsectionButton(parent, definition)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(34)
    button.label = CreateText(button, 10, { 0.58, 0.61, 0.67, 1 }, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(T(definition.label, definition.fallback))
    button.underline = button:CreateTexture(nil, "ARTWORK")
    button.underline:SetPoint("BOTTOMLEFT", 6, 0)
    button.underline:SetPoint("BOTTOMRIGHT", -6, 0)
    button.underline:SetHeight(2)
    button.underline:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)

    function button:SetActive(active)
        self._active = active == true
        self.underline:SetShown(self._active)
        self.label:SetTextColor(
            self._active and THEME.accent[1] or 0.58,
            self._active and THEME.accent[2] or 0.61,
            self._active and THEME.accent[3] or 0.67,
            1
        )
    end
    button:SetScript("OnEnter", function(self)
        if not self._active then self.label:SetTextColor(0.93, 0.94, 0.97, 1) end
    end)
    button:SetScript("OnLeave", function(self) self:SetActive(self._active) end)
    button:SetActive(false)
    return button
end

local function GetGroupStore()
    local profile = DDingUI.db and DDingUI.db.profile
    return profile and profile.groupSystem
end

local function GroupExists(groupName)
    local store = GetGroupStore()
    return store and store.groups and store.groups[groupName] ~= nil
end

local function GetDefaultGroup()
    local remembered = DDingUI._groupWorkspaceSelectedGroup
    if remembered and GroupExists(remembered) then return remembered end
    if GroupExists("Cooldowns") then return "Cooldowns" end
    local store = GetGroupStore()
    local bestName, bestOrder
    for name, settings in pairs((store and store.groups) or {}) do
        local order = tonumber(settings.order) or 999
        if not bestOrder or order < bestOrder then
            bestName, bestOrder = name, order
        end
    end
    return bestName
end

local function GetGroupLabel(groupName)
    local store = GetGroupStore()
    local settings = store and store.groups and store.groups[groupName]
    local localeKey = GROUP_LABEL_KEYS[groupName]
    return (localeKey and T(localeKey, nil))
        or (settings and settings.name)
        or groupName
        or T("CDM Bars", "CDM 바")
end

local function SequenceSignature(values)
    if type(values) ~= "table" then return "" end
    local parts = {}
    for index, value in ipairs(values) do
        parts[index] = tostring(value)
    end
    return table.concat(parts, "\31")
end

local function GetGroupSignature(groupName)
    local store = GetGroupStore()
    local settings = store and store.groups and store.groups[groupName]
    if not settings then return "missing" end
    local order = settings.iconOrder
    local orderSignature = SequenceSignature(order)
    local profile = DDingUI.db and DDingUI.db.profile
    local sourceGroup = settings.sourceGroupKey
        and profile
        and profile.dynamicIcons
        and profile.dynamicIcons.groups
        and profile.dynamicIcons.groups[settings.sourceGroupKey]
    local sourceIcons = sourceGroup and sourceGroup.icons
    local sourceSignature = SequenceSignature(sourceIcons)
    return table.concat({
        tostring(settings.enabled ~= false),
        tostring(settings.iconSize or ""),
        tostring(settings.spacing or ""),
        tostring(settings.borderSize or ""),
        tostring(settings.zoom or ""),
        tostring(settings.aspectRatioCrop or ""),
        tostring(settings.direction or ""),
        tostring(settings.growDirection or ""),
        tostring(settings.rowLimit or ""),
        tostring(settings.groupAlpha or ""),
        orderSignature,
        sourceSignature,
        tostring(DDingUI._groupIconDetailSelection and DDingUI._groupIconDetailSelection.key or ""),
    }, ":")
end

if not StaticPopupDialogs["DDINGUI_CREATE_CDM_GROUP"] then
    StaticPopupDialogs["DDINGUI_CREATE_CDM_GROUP"] = {
        text = T("New Group Name", "새 그룹 이름"),
        button1 = T("Create", "생성"),
        button2 = _G.CANCEL or "취소",
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self)
            local editBox = self.editBox or self.EditBox
            if not editBox then return end
            editBox:SetText("")
            editBox:SetFocus()
        end,
        OnAccept = function(self, data)
            local editBox = self.editBox or self.EditBox
            local name = editBox and editBox:GetText()
            name = name and name:match("^%s*(.-)%s*$") or ""
            if name ~= "" and data and data.onAccept then data.onAccept(name) end
        end,
        EditBoxOnEnterPressed = function(self)
            local dialog = self:GetParent()
            if dialog and dialog.button1 then dialog.button1:Click() end
        end,
    }
end

function GUI.PromptCreateCDMGroup(onCreated)
    StaticPopup_Show("DDINGUI_CREATE_CDM_GROUP", nil, nil, {
        onAccept = function(name)
            if not DDingUI.GroupManager or not DDingUI.GroupManager:CreateGroup(name) then return end
            if DDingUI.GroupSystem and DDingUI.GroupSystem.OnGroupAdded then
                DDingUI.GroupSystem:OnGroupAdded(name)
            end
            DDingUI._groupWorkspaceSelectedGroup = name
            if onCreated then onCreated(name) end
        end,
    })
end

function GUI.CreateGroupSystemWorkspace(contentFrame, parentFrame)
    local contentArea = parentFrame.contentArea
    parentFrame.scrollFrame:Hide()
    if parentFrame.scrollBar then parentFrame.scrollBar:Hide() end

    local old = contentArea._groupWorkspace
    if old then
        if old.Release then old:Release() end
        old:Hide()
        old:SetParent(nil)
    end

    local workspace = CreateFrame("Frame", nil, contentArea, "BackdropTemplate")
    workspace:SetAllPoints(contentArea)
    workspace:SetFrameStrata("DIALOG")
    workspace:SetFrameLevel(contentArea:GetFrameLevel() + 5)
    SetSurface(workspace, THEME.shell, THEME.border)
    contentArea._groupWorkspace = workspace
    workspace._parentFrame = parentFrame
    workspace.selectedGroup = GetDefaultGroup()
    local requestedMode = DDingUI._groupWorkspaceInspectorMode
    local hasSelectedIcon = DDingUI:GetGroupIconDetailSelection(workspace.selectedGroup) ~= nil
    workspace.category = requestedMode == "icon" and hasSelectedIcon and "state"
        or DDingUI._groupWorkspaceCategory
        or "layout"
    workspace.sectionByCategory = DDingUI._groupWorkspaceSections or {}
    DDingUI._groupWorkspaceInspectorMode = nil

    local inspector = CreateFrame("Frame", nil, workspace, "BackdropTemplate")
    SetSurface(inspector, THEME.panelRaised, THEME.border)

    local inspectorHeader = CreateFrame("Frame", nil, inspector)
    inspectorHeader:SetPoint("TOPLEFT", inspector, "TOPLEFT", 0, 0)
    inspectorHeader:SetPoint("TOPRIGHT", inspector, "TOPRIGHT", 0, 0)
    inspectorHeader:SetHeight(54)
    inspectorHeader.iconFrame = CreateFrame("Frame", nil, inspectorHeader, "BackdropTemplate")
    inspectorHeader.iconFrame:SetSize(34, 34)
    inspectorHeader.iconFrame:SetPoint("LEFT", inspectorHeader, "LEFT", 12, 0)
    SetSurface(inspectorHeader.iconFrame, THEME.input, THEME.borderLight)
    inspectorHeader.icon = inspectorHeader.iconFrame:CreateTexture(nil, "ARTWORK")
    inspectorHeader.icon:SetPoint("TOPLEFT", 2, -2)
    inspectorHeader.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    inspectorHeader.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    inspectorHeader.title = CreateText(inspectorHeader, 12, { 0.96, 0.97, 0.99, 1 })
    inspectorHeader.title:SetPoint("TOPLEFT", inspectorHeader.iconFrame, "TOPRIGHT", 10, -1)
    inspectorHeader.title:SetPoint("RIGHT", inspectorHeader, "RIGHT", -10, 0)
    inspectorHeader.subtitle = CreateText(inspectorHeader, 10, { 0.48, 0.52, 0.59, 1 })
    inspectorHeader.subtitle:SetPoint("TOPLEFT", inspectorHeader.title, "BOTTOMLEFT", 0, -6)
    inspectorHeader.subtitle:SetPoint("RIGHT", inspectorHeader, "RIGHT", -10, 0)
    CreateDivider(inspectorHeader, -53)

    local categoryRail = CreateFrame("Frame", nil, inspector, "BackdropTemplate")
    categoryRail:SetPoint("TOPLEFT", inspectorHeader, "BOTTOMLEFT", 0, 0)
    categoryRail:SetPoint("BOTTOMLEFT", inspector, "BOTTOMLEFT", 0, 0)
    categoryRail:SetWidth(168)
    SetSurface(categoryRail, THEME.panelStrong, THEME.border)
    local categoryTitle = CreateText(categoryRail, 9, { 0.46, 0.49, 0.55, 1 })
    categoryTitle:SetPoint("TOPLEFT", categoryRail, "TOPLEFT", 14, -12)
    categoryTitle:SetText(T("What do you want to configure?", "무엇을 설정할까요?"))

    local categoryButtons = {}
    local previousCategoryButton
    for _, definition in ipairs(WORKSPACE_CATEGORIES) do
        local button = CreateCategoryButton(categoryRail, definition)
        button:SetPoint("LEFT", categoryRail, "LEFT", 1, 0)
        button:SetPoint("RIGHT", categoryRail, "RIGHT", -1, 0)
        if previousCategoryButton then
            button:SetPoint("TOP", previousCategoryButton, "BOTTOM", 0, -1)
        else
            button:SetPoint("TOP", categoryRail, "TOP", 0, -36)
        end
        categoryButtons[definition.key] = button
        previousCategoryButton = button
    end

    local subsectionBar = CreateFrame("Frame", nil, inspector, "BackdropTemplate")
    subsectionBar:SetPoint("TOPLEFT", inspectorHeader, "BOTTOMLEFT", 168, 0)
    subsectionBar:SetPoint("TOPRIGHT", inspectorHeader, "BOTTOMRIGHT", 0, 0)
    subsectionBar:SetHeight(38)
    SetSurface(subsectionBar, THEME.panelStrong, THEME.border)
    subsectionBar.buttons = {}

    local inspectorScroll = CreateFrame("ScrollFrame", nil, inspector)
    inspectorScroll:SetPoint("TOPLEFT", subsectionBar, "BOTTOMLEFT", 4, -4)
    inspectorScroll:SetPoint("BOTTOMRIGHT", inspector, "BOTTOMRIGHT", -14, 4)
    inspectorScroll:EnableMouseWheel(true)
    local inspectorChild = CreateFrame("Frame", nil, inspectorScroll)
    inspectorChild:SetWidth(640)
    inspectorChild:SetHeight(1)
    inspectorChild.widgets = {}
    inspectorChild.scrollFrame = inspectorScroll
    inspectorChild._insideGroupSystemWorkspace = true
    inspectorChild._compactOptionsLayout = true
    inspectorScroll:SetScrollChild(inspectorChild)
    local inspectorScrollBar = GUI.CreateCustomScrollBar(inspector, inspectorScroll)
    inspectorScrollBar:SetPoint("TOPLEFT", inspectorScroll, "TOPRIGHT", 3, 0)
    inspectorScrollBar:SetPoint("BOTTOMLEFT", inspectorScroll, "BOTTOMRIGHT", 3, 0)
    inspectorScroll.ScrollBar = inspectorScrollBar
    inspectorScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, inspectorChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 30)))
        if inspectorScrollBar.UpdateThumbPosition then inspectorScrollBar.UpdateThumbPosition() end
    end)
    inspectorScroll:SetScript("OnSizeChanged", function(self)
        local width = self:GetWidth()
        if width and width > 40 then inspectorChild:SetWidth(width - 1) end
    end)
    inspectorChild:SetScript("OnSizeChanged", function()
        if inspectorScrollBar.UpdateThumbPosition then C_Timer.After(0, inspectorScrollBar.UpdateThumbPosition) end
    end)

    local center = CreateFrame("Frame", nil, workspace)
    center:SetPoint("TOPLEFT", workspace, "TOPLEFT", 10, -10)
    center:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", -10, -10)
    center:SetHeight(250)
    inspector:SetPoint("TOPLEFT", center, "BOTTOMLEFT", 0, -8)
    inspector:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", -10, 10)

    local centerHeader = CreateFrame("Frame", nil, center, "BackdropTemplate")
    centerHeader:SetPoint("TOPLEFT", center, "TOPLEFT", 0, 0)
    centerHeader:SetPoint("TOPRIGHT", center, "TOPRIGHT", 0, 0)
    centerHeader:SetHeight(52)
    SetSurface(centerHeader, THEME.panelRaised, THEME.border)
    centerHeader.title = CreateText(centerHeader, 14, { 0.96, 0.97, 0.99, 1 })
    centerHeader.title:SetPoint("TOPLEFT", centerHeader, "TOPLEFT", 14, -10)
    centerHeader.subtitle = CreateText(centerHeader, 10, { 0.49, 0.52, 0.59, 1 })
    centerHeader.subtitle:SetPoint("TOPLEFT", centerHeader.title, "BOTTOMLEFT", 0, -5)
    centerHeader.state = CreateText(centerHeader, 10, { 0.35, 0.92, 0.48, 1 }, "RIGHT")
    centerHeader.state:SetPoint("RIGHT", centerHeader, "RIGHT", -108, 0)
    local restoreButton = CreateButton(centerHeader, T("Restore Order", "기본 순서 복원"), true)
    restoreButton:SetWidth(92)
    restoreButton:SetPoint("RIGHT", centerHeader, "RIGHT", -8, 0)

    local canvas = CreateFrame("Frame", nil, center, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", centerHeader, "BOTTOMLEFT", 0, -8)
    canvas:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", 0, 32)
    SetSurface(canvas, THEME.panel, THEME.border)
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    local canvasTitle = CreateText(canvas, 10, { 0.5, 0.53, 0.6, 1 })
    canvasTitle:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, -10)
    canvasTitle:SetText(T("Live Preview", "실시간 미리보기"))
    local selectionStrip = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    selectionStrip:SetPoint("TOP", canvas, "TOP", 0, -30)
    selectionStrip:SetSize(250, 25)
    selectionStrip:SetFrameLevel(canvas:GetFrameLevel() + 20)
    SetSurface(selectionStrip, THEME.bgMedium, THEME.focus)
    selectionStrip.text = CreateText(selectionStrip, 10, { 0.74, 0.88, 0.93, 1 }, "CENTER")
    selectionStrip.text:SetPoint("CENTER")
    selectionStrip:Hide()

    local statusBar = CreateFrame("Frame", nil, center)
    statusBar:SetPoint("BOTTOMLEFT", center, "BOTTOMLEFT", 0, 0)
    statusBar:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", 0, 0)
    statusBar:SetHeight(24)
    local statusText = CreateText(statusBar, 9, { 0.42, 0.45, 0.51, 1 })
    statusText:SetPoint("LEFT", statusBar, "LEFT", 4, 0)

    workspace.centerHeader = centerHeader
    workspace.canvas = canvas
    workspace.selectionStrip = selectionStrip
    workspace.inspectorHeader = inspectorHeader
    workspace.inspectorScroll = inspectorScroll
    workspace.inspectorChild = inspectorChild
    workspace.inspectorScrollBar = inspectorScrollBar
    workspace.categoryRail = categoryRail
    workspace.categoryButtons = categoryButtons
    workspace.subsectionBar = subsectionBar
    workspace.restoreButton = restoreButton
    workspace.statusText = statusText

    function workspace:RefreshHeader()
        local store = GetGroupStore()
        local settings = store and store.groups and store.groups[self.selectedGroup]
        self.centerHeader.title:SetText(GetGroupLabel(self.selectedGroup))
        self.centerHeader.subtitle:SetText(GROUP_LABEL_KEYS[self.selectedGroup]
            and T("Blizzard CDM group", "블리자드 CDM 그룹")
            or T("Custom icon group", "커스텀 아이콘 그룹"))
        local enabled = settings and settings.enabled ~= false
        self.centerHeader.state:SetText(enabled and T("Synced", "동기화됨") or T("Disabled", "비활성"))
        self.centerHeader.state:SetTextColor(enabled and 0.35 or 0.55, enabled and 0.92 or 0.57, enabled and 0.48 or 0.62, 1)
        self.restoreButton:SetShown(self.selectedGroup == "Cooldowns" or self.selectedGroup == "Buffs" or self.selectedGroup == "Utility")
        self.statusText:SetText(GetGroupLabel(self.selectedGroup))
    end

    function workspace:RefreshPreviewSelection()
        local selected = DDingUI:GetGroupIconDetailSelection(self.selectedGroup)
        if selected then
            local name = selected._gridDisplayName or selected._gridSpellName or selected._gridDynamicIconKey or T("Selected Icon", "선택한 아이콘")
            self.selectionStrip.text:SetText(name .. "  ·  " .. T("editing", "편집 중"))
            self.selectionStrip:Show()
        else
            self.selectionStrip:Hide()
        end
    end

    function workspace:ResolveNavigation()
        local selected = DDingUI:GetGroupIconDetailSelection(self.selectedGroup)
        local definition = CATEGORY_BY_KEY[self.category]
        if not definition or (definition.requiresIcon and not selected) then
            self.category = "layout"
            definition = CATEGORY_BY_KEY.layout
        end

        local sections = {}
        for _, section in ipairs(definition.sections or {}) do
            if not section.requiresIcon or selected then
                sections[#sections + 1] = section
            end
        end

        local currentSection = self.sectionByCategory[self.category]
        local sectionIsAvailable = false
        for _, section in ipairs(sections) do
            if section.key == currentSection then
                sectionIsAvailable = true
                break
            end
        end
        if not sectionIsAvailable then
            currentSection = sections[1] and sections[1].key or nil
            self.sectionByCategory[self.category] = currentSection
        end

        DDingUI._groupWorkspaceCategory = self.category
        DDingUI._groupWorkspaceSections = self.sectionByCategory
        return definition, sections, currentSection, selected
    end

    function workspace:RefreshCategoryNavigation()
        local definition, sections, currentSection, selected = self:ResolveNavigation()
        for _, category in ipairs(WORKSPACE_CATEGORIES) do
            local button = self.categoryButtons[category.key]
            if button then
                button:SetAvailable(not category.requiresIcon or selected ~= nil)
                button:SetActive(category.key == self.category)
            end
        end

        for _, button in ipairs(self.subsectionBar.buttons) do
            button:Hide()
            button:SetParent(nil)
        end
        wipe(self.subsectionBar.buttons)

        self.inspectorScroll:ClearAllPoints()
        if #sections > 0 then
            self.subsectionBar:Show()
            self.inspectorScroll:SetPoint("TOPLEFT", self.subsectionBar, "BOTTOMLEFT", 4, -4)
            local availableWidth = math.max(420, (self.subsectionBar:GetWidth() or 600) - 16)
            local buttonWidth = math.max(96, math.min(168,
                math.floor((availableWidth - math.max(0, #sections - 1) * 2) / #sections)))
            local previous
            for _, section in ipairs(sections) do
                local button = CreateSubsectionButton(self.subsectionBar, section)
                button:SetWidth(buttonWidth)
                if previous then
                    button:SetPoint("TOPLEFT", previous, "TOPRIGHT", 2, 0)
                else
                    button:SetPoint("TOPLEFT", self.subsectionBar, "TOPLEFT", 8, -2)
                end
                button:SetActive(section.key == currentSection)
                local sectionKey = section.key
                button:SetScript("OnClick", function() self:SelectSection(sectionKey) end)
                self.subsectionBar.buttons[#self.subsectionBar.buttons + 1] = button
                previous = button
            end
        else
            self.subsectionBar:Hide()
            self.inspectorScroll:SetPoint("TOPLEFT", self.inspectorHeader, "BOTTOMLEFT", 172, -4)
        end
        self.inspectorScroll:SetPoint("BOTTOMRIGHT", inspector, "BOTTOMRIGHT", -14, 4)
        return definition, currentSection, selected
    end

    function workspace:SelectCategory(categoryKey)
        local definition = CATEGORY_BY_KEY[categoryKey]
        local selected = DDingUI:GetGroupIconDetailSelection(self.selectedGroup)
        if not definition or (definition.requiresIcon and not selected) then return end
        self.category = categoryKey
        if categoryKey == "effects"
            and self.sectionByCategory.effects == "icon"
            and not selected
        then
            self.sectionByCategory.effects = "group"
        end
        self:RefreshInspector()
    end

    function workspace:SelectSection(sectionKey)
        if not sectionKey then return end
        self.sectionByCategory[self.category] = sectionKey
        self:RefreshInspector()
    end

    function workspace:QueueRefresh(mode)
        if mode then
            self.category = mode == "icon" and "state"
                or (mode == "group" or mode == "system") and "layout"
                or mode
        end
        if self._interactionTimer then self._interactionTimer:Cancel() end
        self._interactionTimer = C_Timer.NewTimer(0, function()
            self._interactionTimer = nil
            if self:IsShown() then self:RefreshAll(true) end
        end)
    end

    function workspace:RefreshPreview()
        if not self.selectedGroup or not GroupExists(self.selectedGroup) then return end
        if self.previewHolder then
            self.previewHolder:Hide()
            self.previewHolder:SetParent(nil)
        end
        local holder = CreateFrame("Frame", nil, self.canvas)
        holder:SetWidth(math.max(280, (self.canvas:GetWidth() or 560) - 28))
        holder._onGroupIconSelected = function() self:QueueRefresh("state") end
        holder._onAssignedGridCommit = function() self:QueueRefresh(nil) end
        DDingUI:BuildGroupAssignedIconGridUI(holder, self.selectedGroup)
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", self.canvas, "CENTER", 0, -6)
        self.previewHolder = holder
        self._previewSignature = GetGroupSignature(self.selectedGroup)
        self._observedSignature = self._previewSignature
        self._signatureStableFor = 0
        self:RefreshPreviewSelection()
    end

    function workspace:RefreshInspectorHeader(definition, currentSection, selected)
        local categoryLabel = definition and T(definition.label, definition.fallback) or ""
        local showSelectedIcon = selected and (
            self.category == "state"
            or (self.category == "effects" and currentSection == "icon")
        )
        if showSelectedIcon then
            self.inspectorHeader.icon:SetTexture(selected._gridIconTex or 134400)
            self.inspectorHeader.title:SetText(selected._gridDisplayName or selected._gridSpellName or T("Selected Icon", "선택한 아이콘"))
            local kind = selected._gridKind == "dynamic" and T("Custom Icon", "커스텀 아이콘") or T("CDM Icon", "CDM 아이콘")
            self.inspectorHeader.subtitle:SetText(categoryLabel .. "  ·  " .. kind .. "  ·  " .. GetGroupLabel(self.selectedGroup))
        else
            self.inspectorHeader.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
            self.inspectorHeader.title:SetText(GetGroupLabel(self.selectedGroup))
            self.inspectorHeader.subtitle:SetText(categoryLabel)
        end
    end

    function workspace:RefreshInspector()
        if not self.selectedGroup then return end
        local definition, currentSection, selected = self:RefreshCategoryNavigation()
        self:RefreshInspectorHeader(definition, currentSection, selected)
        self.inspectorScroll:SetVerticalScroll(0)
        local page = DDingUI:BuildGroupWorkspaceOptionPage(
            self.selectedGroup,
            self.category,
            currentSection
        )
        if page then
            GUI.RenderOptions(self.inspectorChild, page, {
                "groupSystem",
                "group_" .. tostring(self.selectedGroup),
                self.category,
                currentSection or "main",
            }, self._parentFrame)
        end
        if self.inspectorScrollBar.UpdateThumbPosition then C_Timer.After(0, self.inspectorScrollBar.UpdateThumbPosition) end
    end

    function workspace:SelectGroup(groupName)
        if not groupName or not GroupExists(groupName) then groupName = GetDefaultGroup() end
        if not groupName then return end
        self.selectedGroup = groupName
        DDingUI._groupWorkspaceSelectedGroup = groupName
        if not DDingUI:GetGroupIconDetailSelection(groupName) and self.category == "state" then
            self.category = "layout"
        end
        self:RefreshAll(true)
    end

    function workspace:RefreshAll(forcePreview)
        if not GroupExists(self.selectedGroup) then self.selectedGroup = GetDefaultGroup() end
        self:RefreshHeader()
        if forcePreview or self._previewSignature ~= GetGroupSignature(self.selectedGroup) then self:RefreshPreview() end
        self:RefreshInspector()
    end

    function workspace:Release()
        self:SetScript("OnUpdate", nil)
        self.canvas:SetScript("OnSizeChanged", nil)
        if self._resizeTimer then self._resizeTimer:Cancel(); self._resizeTimer = nil end
        if self._interactionTimer then self._interactionTimer:Cancel(); self._interactionTimer = nil end
        if self.previewHolder then
            self.previewHolder:Hide()
            self.previewHolder:SetParent(nil)
            self.previewHolder = nil
        end
    end

    for _, definition in ipairs(WORKSPACE_CATEGORIES) do
        local categoryKey = definition.key
        categoryButtons[categoryKey]:SetScript("OnClick", function()
            workspace:SelectCategory(categoryKey)
        end)
    end
    restoreButton:SetScript("OnClick", function()
        if DDingUI.ResetGroupSystemIconOrder and DDingUI:ResetGroupSystemIconOrder(workspace.selectedGroup) then
            workspace:RefreshAll(true)
        end
    end)

    canvas:SetScript("OnSizeChanged", function()
        if workspace._resizeTimer then workspace._resizeTimer:Cancel() end
        workspace._resizeTimer = C_Timer.NewTimer(0.05, function()
            workspace._resizeTimer = nil
            if workspace:IsShown() then workspace:RefreshPreview() end
        end)
    end)
    workspace:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < 0.08 then return end
        local interval = self._elapsed
        self._elapsed = 0
        local signature = GetGroupSignature(self.selectedGroup)
        if signature ~= self._observedSignature then
            self._observedSignature = signature
            self._signatureStableFor = 0
            return
        end
        if signature ~= self._previewSignature then
            self._signatureStableFor = (self._signatureStableFor or 0) + interval
        else
            self._signatureStableFor = 0
        end
        if self._signatureStableFor >= 0.16 then
            self:RefreshHeader()
            self:RefreshPreview()
        end
    end)
    workspace:SetScript("OnHide", function(self) self:Release() end)

    workspace:RefreshHeader()
    workspace:RefreshInspector()
    C_Timer.After(0, function()
        if workspace:IsShown() then workspace:RefreshPreview() end
    end)
end
