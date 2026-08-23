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

local function CreateModeButton(parent, label)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(32)
    button.label = CreateText(button, 11, { 0.64, 0.66, 0.72, 1 }, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(label)
    button.underline = button:CreateTexture(nil, "ARTWORK")
    button.underline:SetPoint("BOTTOMLEFT", 8, 0)
    button.underline:SetPoint("BOTTOMRIGHT", -8, 0)
    button.underline:SetHeight(2)
    button.underline:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)

    function button:SetActive(active)
        self._active = active == true
        self.underline:SetShown(self._active)
        if self._active then
            self.label:SetTextColor(1, 0.48, 0.12, 1)
        else
            self.label:SetTextColor(0.64, 0.66, 0.72, 1)
        end
    end
    button:SetScript("OnEnter", function(self)
        if not self._active then self.label:SetTextColor(0.9, 0.91, 0.94, 1) end
    end)
    button:SetScript("OnLeave", function(self) self:SetActive(self._active) end)
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
    workspace.inspectorMode = DDingUI._groupWorkspaceInspectorMode
        or (DDingUI:GetGroupIconDetailSelection(workspace.selectedGroup) and "icon" or "group")
    DDingUI._groupWorkspaceInspectorMode = nil

    local inspector = CreateFrame("Frame", nil, workspace, "BackdropTemplate")
    inspector:SetPoint("TOPRIGHT", workspace, "TOPRIGHT", 0, 0)
    inspector:SetPoint("BOTTOMRIGHT", workspace, "BOTTOMRIGHT", 0, 0)
    inspector:SetWidth(330)
    SetSurface(inspector, THEME.panelRaised, THEME.border)

    local inspectorHeader = CreateFrame("Frame", nil, inspector)
    inspectorHeader:SetPoint("TOPLEFT", inspector, "TOPLEFT", 0, 0)
    inspectorHeader:SetPoint("TOPRIGHT", inspector, "TOPRIGHT", 0, 0)
    inspectorHeader:SetHeight(66)
    inspectorHeader.iconFrame = CreateFrame("Frame", nil, inspectorHeader, "BackdropTemplate")
    inspectorHeader.iconFrame:SetSize(40, 40)
    inspectorHeader.iconFrame:SetPoint("LEFT", inspectorHeader, "LEFT", 12, 0)
    SetSurface(inspectorHeader.iconFrame, THEME.input, THEME.borderLight)
    inspectorHeader.icon = inspectorHeader.iconFrame:CreateTexture(nil, "ARTWORK")
    inspectorHeader.icon:SetPoint("TOPLEFT", 2, -2)
    inspectorHeader.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    inspectorHeader.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    inspectorHeader.title = CreateText(inspectorHeader, 12, { 0.96, 0.97, 0.99, 1 })
    inspectorHeader.title:SetPoint("TOPLEFT", inspectorHeader.iconFrame, "TOPRIGHT", 10, -3)
    inspectorHeader.title:SetPoint("RIGHT", inspectorHeader, "RIGHT", -10, 0)
    inspectorHeader.subtitle = CreateText(inspectorHeader, 10, { 0.48, 0.52, 0.59, 1 })
    inspectorHeader.subtitle:SetPoint("TOPLEFT", inspectorHeader.title, "BOTTOMLEFT", 0, -6)
    inspectorHeader.subtitle:SetPoint("RIGHT", inspectorHeader, "RIGHT", -10, 0)
    CreateDivider(inspectorHeader, -65)

    local modeBar = CreateFrame("Frame", nil, inspector, "BackdropTemplate")
    modeBar:SetPoint("TOPLEFT", inspectorHeader, "BOTTOMLEFT", 0, 0)
    modeBar:SetPoint("TOPRIGHT", inspectorHeader, "BOTTOMRIGHT", 0, 0)
    modeBar:SetHeight(34)
    SetSurface(modeBar, THEME.panelStrong, THEME.border)
    local iconMode = CreateModeButton(modeBar, T("Icon", "아이콘"))
    iconMode:SetPoint("TOPLEFT", modeBar, "TOPLEFT", 8, -1)
    iconMode:SetWidth(78)
    local groupMode = CreateModeButton(modeBar, T("Group", "그룹"))
    groupMode:SetPoint("LEFT", iconMode, "RIGHT", 2, 0)
    groupMode:SetWidth(78)
    local systemMode = CreateModeButton(modeBar, T("General", "공통"))
    systemMode:SetPoint("LEFT", groupMode, "RIGHT", 2, 0)
    systemMode:SetWidth(78)

    local inspectorScroll = CreateFrame("ScrollFrame", nil, inspector)
    inspectorScroll:SetPoint("TOPLEFT", modeBar, "BOTTOMLEFT", 4, -4)
    inspectorScroll:SetPoint("BOTTOMRIGHT", inspector, "BOTTOMRIGHT", -14, 4)
    inspectorScroll:EnableMouseWheel(true)
    local inspectorChild = CreateFrame("Frame", nil, inspectorScroll)
    inspectorChild:SetWidth(311)
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
    center:SetPoint("BOTTOMRIGHT", inspector, "BOTTOMLEFT", -10, 10)

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
    workspace.iconMode = iconMode
    workspace.groupMode = groupMode
    workspace.systemMode = systemMode
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

    function workspace:QueueRefresh(mode)
        if mode then self.inspectorMode = mode end
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
        holder._onGroupIconSelected = function() self:QueueRefresh("icon") end
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

    function workspace:RefreshInspectorHeader()
        local selected = DDingUI:GetGroupIconDetailSelection(self.selectedGroup)
        if self.inspectorMode == "system" then
            self.inspectorHeader.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
            self.inspectorHeader.title:SetText(T("CDM Settings", "CDM 전체 설정"))
            self.inspectorHeader.subtitle:SetText(T("Viewer behavior", "뷰어 동작 설정"))
        elseif self.inspectorMode == "icon" and selected then
            self.inspectorHeader.icon:SetTexture(selected._gridIconTex or 134400)
            self.inspectorHeader.title:SetText(selected._gridDisplayName or selected._gridSpellName or T("Selected Icon", "선택한 아이콘"))
            local kind = selected._gridKind == "dynamic" and T("Custom Icon", "커스텀 아이콘") or T("CDM Icon", "CDM 아이콘")
            self.inspectorHeader.subtitle:SetText(kind .. "  ·  " .. GetGroupLabel(self.selectedGroup))
        else
            self.inspectorHeader.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
            self.inspectorHeader.title:SetText(GetGroupLabel(self.selectedGroup))
            self.inspectorHeader.subtitle:SetText(T("Group settings", "그룹 설정"))
        end
    end

    function workspace:RefreshInspector()
        if not self.selectedGroup then return end
        local selected = DDingUI:GetGroupIconDetailSelection(self.selectedGroup)
        if self.inspectorMode == "icon" and not selected then self.inspectorMode = "group" end
        self:RefreshInspectorHeader()
        self.iconMode:SetActive(self.inspectorMode == "icon")
        self.groupMode:SetActive(self.inspectorMode == "group")
        self.systemMode:SetActive(self.inspectorMode == "system")
        self.iconMode:SetAlpha(selected and 1 or 0.42)
        self.inspectorScroll:SetVerticalScroll(0)
        local page = self.inspectorMode == "system"
            and DDingUI:BuildGroupWorkspaceSystemPage()
            or DDingUI:BuildGroupWorkspaceOptionPage(self.selectedGroup, self.inspectorMode)
        if page then
            GUI.RenderOptions(self.inspectorChild, page, {
                "groupSystem",
                "group_" .. tostring(self.selectedGroup),
                self.inspectorMode,
            }, self._parentFrame)
        end
        if self.inspectorScrollBar.UpdateThumbPosition then C_Timer.After(0, self.inspectorScrollBar.UpdateThumbPosition) end
    end

    function workspace:SelectGroup(groupName)
        if not groupName or not GroupExists(groupName) then groupName = GetDefaultGroup() end
        if not groupName then return end
        self.selectedGroup = groupName
        DDingUI._groupWorkspaceSelectedGroup = groupName
        if not DDingUI:GetGroupIconDetailSelection(groupName) then self.inspectorMode = "group" end
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

    iconMode:SetScript("OnClick", function()
        if not DDingUI:GetGroupIconDetailSelection(workspace.selectedGroup) then return end
        workspace.inspectorMode = "icon"
        workspace:RefreshInspector()
    end)
    groupMode:SetScript("OnClick", function()
        workspace.inspectorMode = "group"
        workspace:RefreshInspector()
    end)
    systemMode:SetScript("OnClick", function()
        workspace.inspectorMode = "system"
        workspace:RefreshInspector()
    end)
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
