local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local Base = DDingUI.GUIBase
local L = Base.L
local SL = Base.SL
local FLAT = Base.FLAT
local THEME = Base.THEME
local CreateGradientText = Base.CreateGradientText
local Widgets = Base.Widgets

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
    text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 10, "")
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

-- Render compact search results.
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
    headerText:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
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
            if group.treeKey and parentFrame.NavigateToSection then
                parentFrame:NavigateToSection(group.treeKey)
            elseif group.treeKey and parentFrame._optionLookup then
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

DDingUI.GUISearch = {
    BuildSearchIndex = BuildSearchIndex,
    RenderSearchResults = RenderSearchResults,
}
