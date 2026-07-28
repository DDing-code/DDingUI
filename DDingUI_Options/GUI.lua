local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local Base = DDingUI.GUIBase
local L = Base.L
local CollapsedGroups = Base.CollapsedGroups
local DragState = Base.DragState
local SL = Base.SL
local FLAT = Base.FLAT
local THEME = Base.THEME
local DDingUI_GetPopupEditBox = Base.GetPopupEditBox
local GetSafeScrollRange = Base.GetSafeScrollRange
local StyleFontString = Base.StyleFontString
local AddHoverHighlight = Base.AddHoverHighlight
local FadeIn = Base.FadeIn
local FadeOut = Base.FadeOut
local CreateBackdrop = Base.CreateBackdrop
local CreateShadow = Base.CreateShadow
local CreateGradientText = Base.CreateGradientText
local CreateCustomScrollBar = Base.CreateCustomScrollBar
local PropagateMouseWheelToScroll = Base.PropagateMouseWheelToScroll
local PropagateMouseWheelRecursive = Base.PropagateMouseWheelRecursive
local CreateTabButton = Base.CreateTabButton
local Widgets = Base.Widgets
local globalFontPath = "Fonts\\2002.TTF"
local ConfigFrame
local BuildSearchIndex = DDingUI.GUISearch.BuildSearchIndex
local RenderSearchResults = DDingUI.GUISearch.RenderSearchResults

local RenderOptions

local function MaterializeLazyOption(option)
    if type(option) ~= "table" then return option end

    local builder = rawget(option, "_lazyBuilder")
    if type(builder) ~= "function" then return option end

    local built = builder()
    if type(built) ~= "table" then return option end

    option._lazyBuilder = nil
    for key in pairs(option) do
        option[key] = nil
    end
    for key, value in pairs(built) do
        option[key] = value
    end
    return option
end

local SECTION_MENU_DEFS = {
    { key = "general",      label = "General Settings", icon = "Interface\\AddOns\\DDingUI_Options\\Media\\Navigation\\General.tga" },
    { key = "groupSystem",  label = "CDM Bars",         icon = "Interface\\AddOns\\DDingUI_Options\\Media\\Navigation\\CooldownBars.tga" },
    { key = "buffTracker",  label = "Buff Tracker",     icon = "Interface\\AddOns\\DDingUI_Options\\Media\\Navigation\\CustomAura.tga" },
    { key = "resourceBars", label = "Resource Bars",    icon = "Interface\\AddOns\\DDingUI_Options\\Media\\Navigation\\ResourceBars.tga" },
    { key = "castBars",     label = "Cast Bars",        icon = "Interface\\AddOns\\DDingUI_Options\\Media\\Navigation\\CastBars.tga" },
    { key = "buffBar",      label = "Tracked Bars",     icon = "Interface\\AddOns\\DDingUI_Options\\Media\\Navigation\\TrackedBars.tga" },
}

local function IsOptionVisible(option)
    if not option then return false end
    if type(option.hidden) == "function" then
        local ok, hidden = pcall(option.hidden)
        return not (ok and hidden)
    end
    return option.hidden ~= true
end

local function ResolveSectionTarget(targetKey, frame)
    if type(targetKey) ~= "string" or targetKey == "" then return nil, nil end

    local parts = {}
    for part in targetKey:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end
    local rootKey = parts[1]

    if rootKey == "uiScale" or rootKey == "display" or rootKey == "profiles" then
        table.insert(parts, 1, "general")
        rootKey = "general"
    elseif rootKey == "viewers" or rootKey == "customIcons" or rootKey == "iconCustomization" then
        rootKey = "groupSystem"
        parts = { rootKey }
    end

    if rootKey == "groupSystem" and frame and frame._optionLookup then
        local groupSystem = frame._optionLookup.groupSystem
        local groupArgs = groupSystem and groupSystem.option and groupSystem.option.args
        local remainder = targetKey:match("^groupSystem%.(.+)$")
        local bestMatch
        if remainder and groupArgs then
            for key in pairs(groupArgs) do
                if remainder == key or remainder:sub(1, #key + 1) == key .. "." then
                    if not bestMatch or #key > #bestMatch then
                        bestMatch = key
                    end
                end
            end
        end
        if bestMatch then
            parts = { "groupSystem", bestMatch }
            local suffix = remainder:sub(#bestMatch + 2)
            for part in suffix:gmatch("[^.]+") do
                parts[#parts + 1] = part
            end
        end
    end

    local subPath = {}
    for i = 2, #parts do
        subPath[#subPath + 1] = parts[i]
    end
    return rootKey, (#subPath > 0) and subPath or nil
end

local function BuildSectionMenuData(options, frame)
    local args = options and options.args or {}
    local generalArgs = {}
    for _, key in ipairs({ "uiScale", "display", "profiles" }) do
        if IsOptionVisible(args[key]) then
            generalArgs[key] = args[key]
        end
    end

    local sectionOptions = {
        general = {
            type = "group",
            name = L["General Settings"] or "General Settings",
            childGroups = "tab",
            args = generalArgs,
        },
        groupSystem = args.groupSystem,
        buffTracker = args.buffTracker,
        resourceBars = args.resourceBars,
        castBars = args.castBars,
        buffBar = args.buffBar,
    }

    frame._optionLookup = {}
    local menuData = {}
    for _, definition in ipairs(SECTION_MENU_DEFS) do
        local option = sectionOptions[definition.key]
        if IsOptionVisible(option) then
            local text = L[definition.label] or definition.label
            menuData[#menuData + 1] = {
                key = definition.key,
                text = text,
                icon = definition.icon,
            }
            frame._optionLookup[definition.key] = {
                option = option,
                path = { definition.key },
            }
        end
    end
    return menuData
end

local function CreateSectionMenu(parent, menuData, opts)
    opts = opts or {}
    local menu = CreateFrame("Frame", nil, parent)
    menu:SetAllPoints()
    menu.rows = {}
    menu.rowsByKey = {}
    menu.selectedKey = nil
    menu.onSelect = opts.onSelect

    local function ApplyRowState(row)
        local active = row._key == menu.selectedKey
        row._active = active
        row.activeBar:SetShown(active)
        if active then
            row.background:SetColorTexture(0.105, 0.105, 0.115, 0.96)
            row.icon:SetVertexColor(1, 0.43, 0.08, 1)
            row.label:SetTextColor(1, 1, 1, 1)
        else
            row.background:SetColorTexture(0, 0, 0, 0)
            row.icon:SetVertexColor(0.72, 0.72, 0.75, 1)
            row.label:SetTextColor(0.84, 0.84, 0.87, 1)
        end
    end

    local function AcquireRow(index)
        local row = menu.rows[index]
        if row then return row end

        row = CreateFrame("Button", nil, menu)
        row:SetHeight(54)
        row:RegisterForClicks("LeftButtonUp")

        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints()

        row.activeBar = row:CreateTexture(nil, "ARTWORK")
        row.activeBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.activeBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.activeBar:SetWidth(3)
        row.activeBar:SetColorTexture(1, 0.36, 0.06, 1)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", row, "LEFT", 24, 0)
        row.icon:SetTexCoord(0, 1, 0, 1)

        row.label = row:CreateFontString(nil, "OVERLAY")
        row.label:SetFont(globalFontPath, 13, "")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 20, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row.label:SetJustifyH("LEFT")

        row.divider = row:CreateTexture(nil, "BORDER")
        row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.divider:SetHeight(1)
        row.divider:SetColorTexture(0.24, 0.24, 0.27, 0.5)

        row:SetScript("OnEnter", function(self)
            if not self._active then
                self.background:SetColorTexture(0.12, 0.12, 0.14, 0.72)
                self.label:SetTextColor(0.88, 0.88, 0.9, 1)
            end
        end)
        row:SetScript("OnLeave", function(self)
            ApplyRowState(self)
        end)
        row:SetScript("OnClick", function(self)
            menu:SetSelected(self._key)
            if menu.onSelect then
                menu.onSelect(self._key, true)
            end
        end)

        menu.rows[index] = row
        return row
    end

    function menu:SetMenuData(data)
        self.rowsByKey = {}
        for index, item in ipairs(data or {}) do
            local row = AcquireRow(index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -((index - 1) * 54))
            row:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            row._key = item.key
            row.icon:SetTexture(item.icon)
            row.label:SetText(item.text or item.key)
            row:Show()
            self.rowsByKey[item.key] = row
        end
        for index = #(data or {}) + 1, #self.rows do
            self.rows[index]:Hide()
        end
        if self.selectedKey and not self.rowsByKey[self.selectedKey] then
            self.selectedKey = nil
        end
        for _, row in ipairs(self.rows) do
            if row:IsShown() then ApplyRowState(row) end
        end
    end

    function menu:SetSelected(key)
        if not self.rowsByKey[key] then return false end
        self.selectedKey = key
        for _, row in ipairs(self.rows) do
            if row:IsShown() then ApplyRowState(row) end
        end
        return true
    end

    function menu:GetSelected()
        return self.selectedKey
    end

    menu:SetMenuData(menuData)
    return menu
end

local CDM_BUILTIN_GROUPS = {
    Cooldowns = true,
    Buffs = true,
    Utility = true,
}

local function ShowCDMGroupContextMenu(configFrame, groupName, displayName, owner)
    if not groupName or CDM_BUILTIN_GROUPS[groupName] then return false end
    if not SL or not SL.ShowCascadingMenu then return false end

    local menuItems = {
        {
            text = L["Rename"] or "이름 변경",
            func = function()
                StaticPopup_Show("DDINGUI_RENAME_GROUP", nil, nil, {
                    oldName = groupName,
                    onAccept = function(newName)
                        if newName == groupName then return end
                        if DDingUI.GroupManager and DDingUI.GroupManager:RenameGroup(groupName, newName) then
                            if configFrame and configFrame.RebuildTreeMenu then
                                configFrame:RebuildTreeMenu("groupSystem.group_" .. newName)
                            end
                            if DDingUI.GroupSystem and DDingUI.GroupSystem.Refresh then
                                DDingUI.GroupSystem:Refresh()
                            end
                        end
                    end,
                })
            end,
        },
        { isSeparator = true },
        {
            text = "|cffff4444" .. (L["Delete Group"] or "그룹 삭제") .. "|r",
            func = function()
                if DDingUI.RequestDeleteIconGroup then
                    DDingUI:RequestDeleteIconGroup(groupName, displayName or groupName)
                end
            end,
        },
    }
    SL.ShowCascadingMenu(owner, menuItems, "TOPLEFT", "BOTTOMLEFT", 0, -2)
    return true
end

local function CleanupNestedOptionFrames(contentFrame, parentFrame)
    if not contentFrame then return end

    if contentFrame.subScrollChild then
        CleanupNestedOptionFrames(contentFrame.subScrollChild, parentFrame)
    end

    if contentFrame._stickyPreview then
        local stickyPreview = contentFrame._stickyPreview
        stickyPreview:Hide()
        stickyPreview:SetParent(nil)
        if parentFrame and parentFrame.contentArea
            and parentFrame.contentArea._groupStickyPreview == stickyPreview
        then
            parentFrame.contentArea._groupStickyPreview = nil
        end
        contentFrame._stickyPreview = nil
    end

    if contentFrame.subTabButtons then
        for _, button in ipairs(contentFrame.subTabButtons) do
            if button then
                button:Hide()
                button:SetParent(nil)
            end
        end
        contentFrame.subTabButtons = nil
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

    if contentFrame.widgets then
        for index = #contentFrame.widgets, 1, -1 do
            local widget = contentFrame.widgets[index]
            if widget then
                widget:Hide()
                widget:SetParent(nil)
            end
        end
    end
    contentFrame.widgets = {}
    contentFrame.subScrollChild = nil
    contentFrame._updateSubTabHeight = nil
end

-- ============================================================
-- [REFACTOR] WeakAuras-style Buff Tracker Panel
-- contentArea 안에 좌측 리스트 + 우측 탭 split-view를 임베딩
-- ============================================================
RenderOptions = function(contentFrame, options, path, parentFrame)
    options = MaterializeLazyOption(options)
    path = path or {}
    parentFrame = parentFrame or contentFrame:GetParent():GetParent()

    CleanupNestedOptionFrames(contentFrame, parentFrame)

    if parentFrame and parentFrame.contentArea and not contentFrame._preserveGroupStickyPreview then
        local stickyPreview = parentFrame.contentArea._groupStickyPreview
        if stickyPreview then
            stickyPreview:Hide()
            stickyPreview:SetParent(nil)
            parentFrame.contentArea._groupStickyPreview = nil
        end
    end

    -- Buff Tracker 커스텀 패널 숨기기 (다른 탭으로 이동 시)
    -- NOTE: btPanel 내부의 tabChild에서 RenderOptions를 호출할 때는 숨기지 않음
    if parentFrame and parentFrame.contentArea and parentFrame.contentArea._btPanel then
        local btPanel = parentFrame.contentArea._btPanel
        local isInsideBtPanel = btPanel.tabChild
            and (contentFrame == btPanel.tabChild or contentFrame._insideBuffTrackerPanel)
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

    -- [REFACTOR] 커스텀 렌더러 분기
    if options.customRenderer == "buffTracker" then
        DDingUI.GUI.CreateBuffTrackerPanel(contentFrame, parentFrame)
        return
    end

    if options.childGroups == "tab" then
        -- Get the parent frame's content area and scroll frame to make tabs sticky
        local parentContentArea = contentFrame._nestedTabContentArea
            or (parentFrame and parentFrame.contentArea)
        local parentScrollFrame = contentFrame.scrollFrame
            or (parentFrame and parentFrame.scrollFrame)
        local stickyPreview
        local stickyPreviewHeight = 0
        local cumulativeTabHeight = 0
        local parentSubTabContainer

        local parentContainer = contentFrame:GetParent()
        if parentContainer then
            local grandParentFrame = parentContainer:GetParent()
            if grandParentFrame and grandParentFrame.subTabContainer then
                parentSubTabContainer = grandParentFrame.subTabContainer
                cumulativeTabHeight = grandParentFrame._cumulativeTabHeight
                    or grandParentFrame._subTabContainerHeight
                    or 35
            elseif parentContainer.subTabContainer then
                parentSubTabContainer = parentContainer.subTabContainer
                cumulativeTabHeight = parentContainer._cumulativeTabHeight
                    or parentContainer._subTabContainerHeight
                    or 35
            end
        end

        if options.stickyGroupPreview and parentContentArea and parentScrollFrame
            and DDingUI.BuildGroupAssignedIconGridUI
        then
            stickyPreview = CreateFrame("Frame", nil, parentContentArea, "BackdropTemplate")
            stickyPreview:SetFrameStrata("DIALOG")
            stickyPreview:SetFrameLevel((parentScrollFrame:GetFrameLevel() or 1) + 9)
            if parentSubTabContainer then
                stickyPreview:SetPoint("TOPLEFT", parentSubTabContainer, "BOTTOMLEFT", 0, 0)
                stickyPreview:SetPoint("TOPRIGHT", parentSubTabContainer, "BOTTOMRIGHT", 0, 0)
            else
                stickyPreview:SetPoint("TOPLEFT", parentScrollFrame, "TOPLEFT", 0, 0)
                stickyPreview:SetPoint("TOPRIGHT", parentScrollFrame, "TOPRIGHT", 0, 0)
            end
            CreateBackdrop(stickyPreview, {THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.98}, {0, 0, 0, 1})

            local previewWidth = math.max(240, (parentScrollFrame:GetWidth() or contentFrame:GetWidth() or 760) - 20)
            local previewHolder = CreateFrame("Frame", nil, stickyPreview)
            previewHolder:SetPoint("TOPLEFT", stickyPreview, "TOPLEFT", 10, -6)
            previewHolder:SetWidth(previewWidth)
            DDingUI:BuildGroupAssignedIconGridUI(previewHolder, options.stickyGroupPreview)

            stickyPreviewHeight = math.max(48, (previewHolder:GetHeight() or 36) + 12)
            stickyPreview:SetHeight(stickyPreviewHeight)
            stickyPreview._previewHolder = previewHolder
            parentContentArea._groupStickyPreview = stickyPreview
            contentFrame._stickyPreview = stickyPreview
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
            if stickyPreview then
                subTabContainer:SetPoint("TOPLEFT", stickyPreview, "BOTTOMLEFT", 0, 0)
                subTabContainer:SetPoint("TOPRIGHT", stickyPreview, "BOTTOMRIGHT", 0, 0)
            elseif parentSubTabContainer then
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
        local fixedHeaderHeight = tabContainerHeight + stickyPreviewHeight
        subContentArea:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -1)
        subContentArea:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

        -- Store tab container height for height calculations
        contentFrame._subTabContainerHeight = fixedHeaderHeight
        -- Store cumulative height for nested tabs
        contentFrame._cumulativeTabHeight = cumulativeTabHeight + fixedHeaderHeight

        local subScrollChild = CreateFrame("Frame", nil, subContentArea)
        -- Position normally - content will start below tab container via yOffset
        subScrollChild:SetPoint("TOPLEFT", subContentArea, "TOPLEFT", 10, -10)
        subScrollChild:SetPoint("RIGHT", subContentArea, "RIGHT", -10, 0)
        subScrollChild.widgets = {}
        subScrollChild._insideBuffTrackerPanel = contentFrame._insideBuffTrackerPanel
        subScrollChild._preserveGroupStickyPreview = stickyPreview ~= nil
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
                if parentFrame then
                    parentFrame._requestedSubTabPath = nil
                end
                contentFrame._activeSubTabKey = item.key
                for _, t in ipairs(subTabButtons) do
                    t:SetActive(false)
                end
                btn:SetActive(true)

                RenderOptions(subScrollChild, item.option, {unpack(path), item.key}, parentFrame)

                -- Update content frame height after rendering sub-tab content
                -- Use multiple delays to ensure content has finished rendering
                if contentFrame._updateSubTabHeight then
                    C_Timer.After(0.02, contentFrame._updateSubTabHeight)
                    C_Timer.After(0.1, contentFrame._updateSubTabHeight)
                end
            end)
            local groupName = #path == 1
                and path[1] == "groupSystem"
                and item.key:match("^group_(.+)$")
                or nil
            if groupName and not CDM_BUILTIN_GROUPS[groupName] then
                local capturedGroupName = groupName
                local capturedDisplayName = displayName
                local leftClick = subTabBtn:GetScript("OnClick")
                subTabBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                subTabBtn:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        ShowCDMGroupContextMenu(
                            parentFrame,
                            capturedGroupName,
                            capturedDisplayName,
                            self
                        )
                        return
                    end
                    if leftClick then leftClick(self, button) end
                end)
            end
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
            local initialTabIndex = 1
            local requestedPath = parentFrame and parentFrame._requestedSubTabPath
            local requestedKey = requestedPath and requestedPath[1]
            local requestedKeyMatched = false
            if requestedKey then
                for index, item in ipairs(sortedTabs) do
                    if item.key == requestedKey then
                        initialTabIndex = index
                        requestedKeyMatched = true
                        table.remove(requestedPath, 1)
                        if #requestedPath == 0 then
                            parentFrame._requestedSubTabPath = nil
                        end
                        break
                    end
                end
                if not requestedKeyMatched then
                    parentFrame._requestedSubTabPath = nil
                end
            end

            local initialTab = sortedTabs[initialTabIndex]
            contentFrame._activeSubTabKey = initialTab.key
            subTabButtons[initialTabIndex]:SetActive(true)
            RenderOptions(subScrollChild, initialTab.option, {unpack(path), initialTab.key}, parentFrame)

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
            elseif option.type == "groupAssignedIconGrid" then
                local groupName = option.groupName
                if groupName and DDingUI.BuildGroupAssignedIconGridUI then
                    local gridFrame = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
                    gridFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                    gridFrame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                    gridFrame:SetWidth(contentFrame:GetWidth() or 760)
                    DDingUI:BuildGroupAssignedIconGridUI(gridFrame, groupName)
                    widget = gridFrame
                    widgetHeight = gridFrame:GetHeight() or 80
                end
            elseif option.type == "groupUnassignedIconGrid" then
                local groupName = option.groupName
                if groupName and DDingUI.BuildGroupUnassignedIconGridUI then
                    local gridFrame = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
                    gridFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOffset)
                    gridFrame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
                    gridFrame:SetWidth(contentFrame:GetWidth() or 760)
                    DDingUI:BuildGroupUnassignedIconGridUI(gridFrame, groupName)
                    widget = gridFrame
                    widgetHeight = gridFrame:GetHeight() or 60
                end
            elseif option.type == "spellSearch" then
                -- [REFACTOR] 실시간 Spell ID 검증 위젯 (CDM 패턴 이식)
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
                local searchMode = option.searchMode or "spell" -- "spell" | "item"
                inputContainer.editBox:HookScript("OnTextChanged", function(self)
                    local text = self:GetText()
                    local inputID = tonumber(text)
                    if inputID and inputID > 0 then
                        if searchMode == "item" then
                            -- 아이템 ID 검증
                            C_Item.RequestLoadItemDataByID(inputID)
                            local itemName, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(inputID)
                            if itemName then
                                statusText:SetText(itemName)
                                statusText:SetTextColor(THEME.success[1], THEME.success[2], THEME.success[3], 1)
                                if itemTexture then
                                    iconPreview:SetTexture(itemTexture)
                                    iconPreview:Show()
                                else
                                    iconPreview:Hide()
                                end
                            else
                                -- 캐시 미스 — 지연 재시도
                                statusText:SetText("Loading...")
                                statusText:SetTextColor(THEME.warning and THEME.warning[1] or 1, THEME.warning and THEME.warning[2] or 0.8, THEME.warning and THEME.warning[3] or 0, 1)
                                iconPreview:Hide()
                                C_Timer.After(0.5, function()
                                    if self:GetText() == text then -- 아직 같은 입력이면
                                        local name2, _, _, _, _, _, _, _, _, tex2 = C_Item.GetItemInfo(inputID)
                                        if name2 then
                                            statusText:SetText(name2)
                                            statusText:SetTextColor(THEME.success[1], THEME.success[2], THEME.success[3], 1)
                                            if tex2 then iconPreview:SetTexture(tex2); iconPreview:Show() end
                                        else
                                            statusText:SetText("Invalid item ID")
                                            statusText:SetTextColor(THEME.error[1], THEME.error[2], THEME.error[3], 1)
                                        end
                                    end
                                end)
                            end
                        else
                            -- 스펠 ID 검증
                            local ok, spellInfo = pcall(function()
                                if C_Spell and C_Spell.GetSpellInfo then
                                    return C_Spell.GetSpellInfo(inputID)
                                end
                            end)
                            if ok and spellInfo and spellInfo.name then
                                statusText:SetText(spellInfo.name)
                                statusText:SetTextColor(THEME.success[1], THEME.success[2], THEME.success[3], 1)
                                local tex = C_Spell.GetSpellTexture(inputID)
                                if tex then
                                    iconPreview:SetTexture(tex)
                                    iconPreview:Show()
                                end
                            else
                                statusText:SetText("Invalid spell ID")
                                statusText:SetTextColor(THEME.error[1], THEME.error[2], THEME.error[3], 1)
                                iconPreview:Hide()
                            end
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
-- Create main config frame (StyleLib tree-menu layout)
function DDingUI:CreateConfigFrame()
    local searchDebounceTimer

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
    local version = C_AddOns.GetAddOnMetadata("DDingUI", "Version") or "1.0"

    local panel = SL.CreateSettingsPanel("CDM", "DDingUI CDM", version, {
        width = 980,
        height = 640,
        minWidth = 600,
        minHeight = 400,
        menuWidth = 240,
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
        if DDingUI.CleanupGroupSystemOptionsRuntime then
            DDingUI:CleanupGroupSystemOptionsRuntime()
        end
        if DDingUI.CleanupResourceBarOptionsRuntime then
            DDingUI:CleanupResourceBarOptionsRuntime()
        end
        if searchDebounceTimer then
            searchDebounceTimer:Cancel()
            searchDebounceTimer = nil
        end
        if DragState.ghostFrame then
            DragState.ghostFrame:Hide()
        end
        local framePicker = DDingUI._optionsFramePicker
        if framePicker then
            framePicker:SetScript("OnUpdate", nil)
            framePicker:Hide()
            DDingUI._optionsFramePicker = nil
        end
        local buffContextMenu = _G["DDingUI_BT_ContextMenu"]
        if buffContextMenu then
            buffContextMenu:Hide()
        end
        local profileConfirm = _G["DDingUI_ProfileConfirmPopup"]
        if profileConfirm then
            profileConfirm:Hide()
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
                searchDebounceTimer = nil
                if frame:IsShown() and frame.PerformSearch then
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
        local hasRequestedSubTabPath = self._requestedSubTabPath and #self._requestedSubTabPath > 0
        local activeSubTabKey = self._requestedSubTabKey
        self._requestedSubTabKey = nil
        if not activeSubTabKey and self.scrollChild and self.scrollChild.subTabButtons then
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

        if not hasRequestedSubTabPath and activeSubTabKey then
            local restorePath = { activeSubTabKey }
            local activeOption = currentOption and currentOption.args and currentOption.args[activeSubTabKey]
            local nestedFrame = self.scrollChild and self.scrollChild.subScrollChild
            if activeOption and activeOption.args and nestedFrame and nestedFrame.subTabButtons then
                local nestedTabs = {}
                for key, option in pairs(activeOption.args) do
                    if option.type == "group" or (option.type ~= "group" and option.type ~= "header" and option.type ~= "description") then
                        nestedTabs[#nestedTabs + 1] = {
                            key = key,
                            order = option.order or 999,
                        }
                    end
                end
                table.sort(nestedTabs, function(a, b) return a.order < b.order end)
                for index, button in ipairs(nestedFrame.subTabButtons) do
                    if button.active and nestedTabs[index] then
                        restorePath[#restorePath + 1] = nestedTabs[index].key
                        break
                    end
                end
            end
            self._requestedSubTabPath = restorePath
            hasRequestedSubTabPath = true
        end

        -- Re-render
        RenderOptions(self.scrollChild, currentOption, currentPath, self)

        -- Restore sub-tab
        if activeSubTabKey and self.scrollChild.subTabButtons and not hasRequestedSubTabPath then
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
        if activeSubTabKey and lookup.option and lookup.option.childGroups == "tab" then
            local restorePath = { activeSubTabKey }
            local activeOption = lookup.option.args and lookup.option.args[activeSubTabKey]
            local nestedFrame = self.scrollChild and self.scrollChild.subScrollChild
            if activeOption and activeOption.args and nestedFrame and nestedFrame.subTabButtons then
                local nestedTabs = {}
                for key, option in pairs(activeOption.args) do
                    if option.type == "group" or (option.type ~= "group" and option.type ~= "header" and option.type ~= "description") then
                        nestedTabs[#nestedTabs + 1] = {
                            key = key,
                            order = option.order or 999,
                        }
                    end
                end
                table.sort(nestedTabs, function(a, b) return a.order < b.order end)
                for index, button in ipairs(nestedFrame.subTabButtons) do
                    if button.active and nestedTabs[index] then
                        restorePath[#restorePath + 1] = nestedTabs[index].key
                        break
                    end
                end
            end
            self._requestedSubTabPath = restorePath
            self:SetContent(lookup.option, lookup.path)
            return
        end

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

    -- [FIX] groupSystem 옵션 테이블을 매번 재생성 (현재 spec/프로필 데이터 반영)
    -- SetupOptions()에서 1회 빌드된 configOptions.args.groupSystem은
    -- 빌드 시점의 gs.groups를 캐시하므로, spec/캐릭 변경 후 열면 이전 데이터가 잔존
    if options and options.args and ns.CreateGroupSystemOptions then
        options.args.groupSystem = ns.CreateGroupSystemOptions(1)
        self.configOptions = options
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
    menuData = BuildSectionMenuData(options, frame)
    local resolvedDefaultKey, requestedSubTabPath = ResolveSectionTarget(tabKey, frame)
    if not resolvedDefaultKey or not frame._optionLookup[resolvedDefaultKey] then
        resolvedDefaultKey = menuData[1] and menuData[1].key or nil
        requestedSubTabPath = nil
    end
    frame._requestedSubTabPath = requestedSubTabPath

    local defaultKey = resolvedDefaultKey
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
    local tree = CreateSectionMenu(frame.treeFrame, menuData, {
        defaultKey = defaultKey,
        onSelect = function(key, fromUser)
            if fromUser then
                frame._requestedSubTabPath = nil
            end
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
            local leavingTracker = frame.currentTab and frame.currentTab:match("^buffTracker")
            local enteringTracker = key:match("^buffTracker")
            if leavingTracker and not enteringTracker then
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
        -- 그룹 및 추적 항목 우클릭 메뉴
        onRightClick = function(key, text, btn)
            local groupName = key:match("^groupSystem%.group_(.+)$")
            if groupName then
                ShowCDMGroupContextMenu(frame, groupName, text, btn)
                return
            end

            -- 추적 항목 우클릭 메뉴
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
    if defaultKey then
        tree:SetSelected(defaultKey)
    end
    frame._fullMenuData = menuData

    function frame:NavigateToSection(targetKey)
        local rootKey, subTabPath = ResolveSectionTarget(targetKey, self)
        if not rootKey or not self._optionLookup[rootKey] then return false end
        self._requestedSubTabPath = subTabPath
        tree:SetSelected(rootKey)
        if tree.onSelect then
            tree.onSelect(rootKey, false)
        end
        return true
    end

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

        newMenuData = BuildSectionMenuData(options, self)
        menuData = newMenuData
        self._fullMenuData = newMenuData
        tree:SetMenuData(newMenuData)

        -- 선택 복원
        local targetKey = selectKey or self.currentTab
        local rootKey, subTabPath = ResolveSectionTarget(targetKey, self)
        if not rootKey or not self._optionLookup[rootKey] then
            rootKey = newMenuData[1] and newMenuData[1].key or nil
            subTabPath = nil
        end
        if rootKey then
            self._requestedSubTabPath = subTabPath
            tree:SetSelected(rootKey)
            if tree.onSelect then tree.onSelect(rootKey, false) end
        end
    end

    -- ============================================
    -- 트리 메뉴 검색 필터 (애드온 내장)
    -- ============================================
    local function OptionContainsText(key, query)
        local lookup = frame._optionLookup[key]
        if not lookup or not lookup.option then return false end

        local function Contains(option)
            if not option then return false end
            local name = option.name
            if type(name) == "function" then
                local ok, value = pcall(name)
                name = ok and value or nil
            end
            if type(name) == "string" and name:lower():find(query, 1, true) then
                return true
            end
            for _, child in pairs(option.args or {}) do
                if Contains(child) then return true end
            end
            return false
        end

        return Contains(lookup.option)
    end

    function frame:FilterTree(searchText)
        if not searchText or searchText == "" then
            tree:SetMenuData(self._fullMenuData)
            if self.currentTab then
                tree:SetSelected(self.currentTab)
            end
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
    frame._searchIndex = nil
    frame._searchMode = false

    -- ============================================
    -- Search actions
    -- ============================================
    function frame:PerformSearch(query)
        if not self._searchIndex then
            for _, option in pairs(options.args or {}) do
                MaterializeLazyOption(option)
            end
            self._searchIndex = BuildSearchIndex(options)
        end

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
-- Shared Styled Widget Helpers -- [REFACTOR] CDM 패턴 이식용 공용 위젯
-- ============================================

DDingUI.GUI = {
    -- Core Functions
    CreateConfigFrame = DDingUI.CreateConfigFrame,
    OpenConfigGUI = DDingUI.OpenConfigGUI,
    RenderOptions = RenderOptions,
    GetPopupEditBox = DDingUI_GetPopupEditBox,

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
