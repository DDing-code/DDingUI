-- DDingUI Toolkit - searchable overlay dropdown

local addonName, ns = ...
local Lib = LibStub("DDingUI-StyleLib-1.0")
local LSM = LibStub("LibSharedMedia-3.0", true)
local L = ns.L
local Controls = ns.ToolkitControls
if not Controls then return end

local C = Lib.Colors
local F = Lib.Font
local SOLID = Lib.Textures and Lib.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local ADDON_KEY = "MJToolkit"

local activeDropdown

local function Accent()
    local color = Lib.GetAccent(ADDON_KEY)
    return color[1], color[2], color[3]
end

local function IsMediaPath(value)
    if type(value) ~= "string" then return false end
    local lower = value:lower()
    return lower:find("\\", 1, true) ~= nil
        or lower:match("%.ttf$")
        or lower:match("%.otf$")
        or lower:match("%.tga$")
        or lower:match("%.blp$")
        or lower:match("%.ogg$")
        or lower:match("%.mp3$")
        or lower:match("%.wav$")
end

local function IsTextureMedia(mediaType)
    return mediaType == "statusbar"
        or mediaType == "background"
        or mediaType == "border"
        or mediaType == "texture"
end

local function ResolveMediaPath(mediaType, item)
    if not mediaType or not item then return nil end
    if LSM and item.text and mediaType ~= "texture" then
        local path = LSM:Fetch(mediaType, item.text, true)
        if path then return path end
    end
    if IsMediaPath(item.value) then return item.value end
    if IsMediaPath(item.path) then return item.path end
    return nil
end

local function NormalizeOptions(options)
    local items = {}
    options = type(options) == "table" and options or {}

    if #options > 0 then
        for index, option in ipairs(options) do
            if type(option) == "table" then
                local text = option.text or option.label or option.name or option[1]
                local value
                if option.value ~= nil then
                    value = option.value
                elseif option[2] ~= nil then
                    value = option[2]
                else
                    value = option[1] or text
                end
                items[#items + 1] = {
                    text = tostring(text or value or ""),
                    value = value,
                    path = option.path,
                    order = option.order or index,
                    disabled = option.disabled == true,
                    tooltip = option.tooltip,
                }
            else
                items[#items + 1] = {
                    text = tostring(option),
                    value = option,
                    order = index,
                }
            end
        end
    else
        for value, text in pairs(options) do
            items[#items + 1] = {
                text = tostring(text or value),
                value = value,
            }
        end
        table.sort(items, function(a, b)
            return a.text:upper() < b.text:upper()
        end)
    end

    for _, item in ipairs(items) do
        item.searchText = (item.text .. " " .. tostring(item.value or "")):lower()
    end
    return items
end

local function PlayPreview(path)
    if path and path ~= "" then
        PlaySoundFile(path, "Master")
    end
end

local function StyleSoundButton(button)
    if button.SetNormalAtlas then
        button:SetNormalAtlas("common-icon-sound")
        button:SetPushedAtlas("common-icon-sound-pressed")
    else
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
        button.icon = icon
    end
end

local function CloseActiveDropdown()
    if activeDropdown and activeDropdown.Close then
        activeDropdown:Close()
    end
end

function Controls.CloseDropdowns()
    CloseActiveDropdown()
end

function Controls.CreateDropdown(parent, addonKey, labelText, options, default, opts)
    opts = opts or {}
    local r, g, b = Accent()
    local width = opts.width or 220
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, opts.height or 30)

    local label = Controls.MakeFont(row, F.normal, C.text.normal, labelText)
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetPoint("RIGHT", row, "CENTER", -22, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    local button = CreateFrame("Button", nil, row, "BackdropTemplate")
    button:SetSize(width, 24)
    button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    Controls.ApplyBackdrop(button, C.bg.input, C.border.default)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local selectedText = Controls.MakeFont(button, F.normal, C.text.normal, opts.placeholder or "Select...")
    selectedText:SetPoint("LEFT", button, "LEFT", 8, 0)
    selectedText:SetPoint("RIGHT", button, "RIGHT", -22, 0)
    selectedText:SetJustifyH("LEFT")
    selectedText:SetWordWrap(false)
    local defaultFontPath, defaultFontSize, defaultFontFlags = selectedText:GetFont()

    local arrow = Controls.MakeFont(button, F.normal, C.text.dim, "\226\150\188")
    arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)

    local selectedTexture
    local selectedSoundButton

    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(498)
    catcher:Hide()

    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetWidth(width)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(500)
    list:SetToplevel(true)
    list:SetClampedToScreen(true)
    Controls.ApplyBackdrop(list, { 0.055, 0.055, 0.06, 0.99 }, { 0, 0, 0, 1 })
    list:Hide()

    local search = Controls.CreateSearchBox(list, width - 8, {
        height = 26,
        placeholder = SEARCH or "Search",
    })
    search:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4)
    search:SetPoint("TOPRIGHT", list, "TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, list)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(math.max(1, width - 16), 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)

    local scrollbar = CreateFrame("Frame", nil, list)
    scrollbar:SetWidth(7)
    scrollbar:SetPoint("RIGHT", list, "RIGHT", -3, 0)
    local scrollbarBG = scrollbar:CreateTexture(nil, "BACKGROUND")
    scrollbarBG:SetAllPoints()
    scrollbarBG:SetColorTexture(0, 0, 0, 0.34)

    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(5)
    thumb:SetPoint("TOP", scrollbar, "TOP", 0, 0)
    local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAllPoints()
    thumbTexture:SetColorTexture(r, g, b, 0.7)

    local emptyText = Controls.MakeFont(
        list,
        F.small,
        C.text.dim,
        opts.emptyText or (L and L["DROPDOWN_NO_RESULTS"]) or "No results"
    )
    emptyText:SetPoint("TOP", search, "BOTTOM", 0, -14)
    emptyText:Hide()

    row.items = NormalizeOptions(options)
    row.rows = {}
    row.filtered = {}
    row.currentValue = nil
    row.keyboardIndex = 0
    row.mediaType = opts.mediaType
    row.searchable = opts.searchable
    if row.searchable == nil then
        row.searchable = row.mediaType ~= nil or #row.items > (opts.searchThreshold or 7)
    end

    local rowHeight = row.mediaType and 26 or 24
    local maxVisible = opts.maxVisible or 10

    local function ResetSelectedFont()
        if defaultFontPath then
            selectedText:SetFont(
                defaultFontPath,
                math.max(1, tonumber(defaultFontSize) or F.normal),
                defaultFontFlags or ""
            )
        end
    end

    local function EnsureSelectedTexture()
        if selectedTexture then return selectedTexture end
        selectedTexture = button:CreateTexture(nil, "ARTWORK")
        selectedTexture:SetSize(56, 12)
        selectedTexture:SetPoint("LEFT", button, "LEFT", 7, 0)
        return selectedTexture
    end

    local function EnsureSelectedSoundButton()
        if selectedSoundButton then return selectedSoundButton end
        selectedSoundButton = CreateFrame("Button", nil, button)
        selectedSoundButton:SetSize(18, 18)
        selectedSoundButton:SetPoint("RIGHT", button, "RIGHT", -20, 0)
        selectedSoundButton:SetFrameLevel(button:GetFrameLevel() + 3)
        StyleSoundButton(selectedSoundButton)
        selectedSoundButton:SetScript("OnClick", function()
            local item = row._selectedItem
            PlayPreview(ResolveMediaPath("sound", item))
        end)
        Controls.SetTooltip(
            selectedSoundButton,
            (L and L["DROPDOWN_PREVIEW"]) or PREVIEW or "Preview"
        )
        return selectedSoundButton
    end

    local function UpdateSelectedMedia(item)
        row._selectedItem = item
        if selectedTexture then selectedTexture:Hide() end
        if selectedSoundButton then selectedSoundButton:Hide() end
        ResetSelectedFont()
        selectedText:ClearAllPoints()
        selectedText:SetPoint("LEFT", button, "LEFT", 8, 0)
        selectedText:SetPoint("RIGHT", button, "RIGHT", -22, 0)

        if not item then return end
        local path = ResolveMediaPath(row.mediaType, item)
        if IsTextureMedia(row.mediaType) and path then
            local preview = EnsureSelectedTexture()
            preview:SetTexture(path)
            preview:Show()
            selectedText:ClearAllPoints()
            selectedText:SetPoint("LEFT", preview, "RIGHT", 7, 0)
            selectedText:SetPoint("RIGHT", button, "RIGHT", -22, 0)
        elseif row.mediaType == "font" and path then
            selectedText:SetFont(path, math.max(1, F.normal), "")
        elseif row.mediaType == "sound" and path then
            local soundButton = EnsureSelectedSoundButton()
            soundButton:Show()
            selectedText:SetPoint("RIGHT", button, "RIGHT", -42, 0)
        end
    end

    local function UpdateScrollbar()
        local range = scroll:GetVerticalScrollRange() or 0
        local trackHeight = scrollbar:GetHeight() or 1
        local viewHeight = scroll:GetHeight() or 1
        local contentHeight = math.max(child:GetHeight() or 1, viewHeight)
        local thumbHeight = math.max(24, trackHeight * (viewHeight / contentHeight))
        thumb:SetHeight(math.min(trackHeight, thumbHeight))

        if range <= 0 or trackHeight <= thumbHeight then
            scrollbar:Hide()
            return
        end

        scrollbar:Show()
        local progress = math.max(0, math.min(1, scroll:GetVerticalScroll() / range))
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollbar, "TOP", 0, -((trackHeight - thumbHeight) * progress))
    end

    local function ScrollToKeyboardRow()
        local target = row.filtered[row.keyboardIndex]
        if not target then return end
        local targetTop = (row.keyboardIndex - 1) * rowHeight
        local targetBottom = targetTop + rowHeight
        local current = scroll:GetVerticalScroll()
        local viewHeight = scroll:GetHeight()
        if targetTop < current then
            scroll:SetVerticalScroll(targetTop)
        elseif targetBottom > current + viewHeight then
            scroll:SetVerticalScroll(math.max(0, targetBottom - viewHeight))
        end
        UpdateScrollbar()
    end

    local function RefreshRowStates()
        for _, optionRow in ipairs(row.rows) do
            local item = optionRow.item
            local selected = item and item.value == row.currentValue
            local keyboard = item and row.filtered[row.keyboardIndex] == item
            optionRow.accent:SetShown(selected)
            if selected then
                optionRow.background:SetColorTexture(0.18, 0.18, 0.22, 0.95)
                optionRow.text:SetTextColor(1, 1, 1, 1)
            elseif keyboard then
                optionRow.background:SetColorTexture(0.20, 0.20, 0.22, 0.88)
                optionRow.text:SetTextColor(1, 1, 1, 1)
            else
                optionRow.background:SetColorTexture(0, 0, 0, 0)
                optionRow.text:SetTextColor(Controls.UnpackColor(
                    item and item.disabled and C.text.disabled or C.text.normal
                ))
            end
        end
    end

    local function SelectItem(item, silent)
        if not item or item.disabled then return false end
        local changed = row.currentValue ~= item.value
        row.currentValue = item.value
        selectedText:SetText(item.text)
        UpdateSelectedMedia(item)
        RefreshRowStates()
        if changed and not silent and opts.onChange then
            opts.onChange(item.value, item.text)
        end
        return true
    end

    local function AcquireOptionRow(index)
        local optionRow = row.rows[index]
        if optionRow then return optionRow end

        optionRow = CreateFrame("Button", nil, child)
        optionRow:SetHeight(rowHeight)
        optionRow:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        optionRow.background = optionRow:CreateTexture(nil, "BACKGROUND")
        optionRow.background:SetAllPoints()

        optionRow.accent = optionRow:CreateTexture(nil, "ARTWORK")
        optionRow.accent:SetPoint("TOPLEFT", optionRow, "TOPLEFT", 0, 0)
        optionRow.accent:SetPoint("BOTTOMLEFT", optionRow, "BOTTOMLEFT", 0, 0)
        optionRow.accent:SetWidth(2)
        optionRow.accent:SetColorTexture(r, g, b, 1)

        optionRow.text = Controls.MakeFont(optionRow, F.normal, C.text.normal, "")
        optionRow.text:SetPoint("LEFT", optionRow, "LEFT", 10, 0)
        optionRow.text:SetPoint("RIGHT", optionRow, "RIGHT", -8, 0)
        optionRow.text:SetJustifyH("LEFT")
        optionRow.text:SetWordWrap(false)
        optionRow.defaultFontPath, optionRow.defaultFontSize, optionRow.defaultFontFlags =
            optionRow.text:GetFont()

        optionRow:SetScript("OnEnter", function(self)
            if self.item and not self.item.disabled and self.item.value ~= row.currentValue then
                self.background:SetColorTexture(0.20, 0.20, 0.22, 0.82)
                self.text:SetTextColor(1, 1, 1, 1)
            end
            if self.item and self.item.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.item.tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        optionRow:SetScript("OnLeave", function()
            GameTooltip:Hide()
            RefreshRowStates()
        end)
        optionRow:SetScript("OnClick", function(self, mouseButton)
            if mouseButton ~= "LeftButton" or not SelectItem(self.item) then return end
            row:Close()
        end)

        row.rows[index] = optionRow
        return optionRow
    end

    local function ConfigureOptionRow(optionRow, item)
        optionRow.item = item
        optionRow.text:SetText(item.text)
        optionRow.text:ClearAllPoints()
        optionRow.text:SetPoint("LEFT", optionRow, "LEFT", 10, 0)
        optionRow.text:SetPoint("RIGHT", optionRow, "RIGHT", -8, 0)
        if optionRow.defaultFontPath then
            optionRow.text:SetFont(
                optionRow.defaultFontPath,
                math.max(1, tonumber(optionRow.defaultFontSize) or F.normal),
                optionRow.defaultFontFlags or ""
            )
        end

        if optionRow.mediaPreview then optionRow.mediaPreview:Hide() end
        if optionRow.fontPreview then optionRow.fontPreview:Hide() end
        if optionRow.soundButton then optionRow.soundButton:Hide() end

        local path = ResolveMediaPath(row.mediaType, item)
        if IsTextureMedia(row.mediaType) and path then
            if not optionRow.mediaPreview then
                optionRow.mediaPreview = optionRow:CreateTexture(nil, "ARTWORK")
                optionRow.mediaPreview:SetSize(64, 12)
            end
            optionRow.mediaPreview:ClearAllPoints()
            optionRow.mediaPreview:SetPoint("LEFT", optionRow, "LEFT", 10, 0)
            optionRow.mediaPreview:SetTexture(path)
            optionRow.mediaPreview:Show()
            optionRow.text:SetPoint("LEFT", optionRow.mediaPreview, "RIGHT", 8, 0)
        elseif row.mediaType == "font" then
            if not optionRow.fontPreview then
                optionRow.fontPreview = Controls.MakeFont(optionRow, 13, C.text.normal, "")
                optionRow.fontPreview:SetWidth(78)
                optionRow.fontPreview:SetJustifyH("RIGHT")
                optionRow.fontFallbackPath, optionRow.fontFallbackSize, optionRow.fontFallbackFlags =
                    optionRow.fontPreview:GetFont()
            end
            optionRow.fontPreview:ClearAllPoints()
            optionRow.fontPreview:SetPoint("RIGHT", optionRow, "RIGHT", -7, 0)
            local applied = path and optionRow.fontPreview:SetFont(path, 13, "")
            if applied then
                optionRow.fontPreview:SetText("Ag 123")
                optionRow.fontPreview:SetTextColor(Controls.UnpackColor(C.text.normal))
            else
                if optionRow.fontFallbackPath then
                    optionRow.fontPreview:SetFont(
                        optionRow.fontFallbackPath,
                        math.max(1, tonumber(optionRow.fontFallbackSize) or F.small),
                        optionRow.fontFallbackFlags or ""
                    )
                end
                optionRow.fontPreview:SetText("--")
                optionRow.fontPreview:SetTextColor(Controls.UnpackColor(C.text.disabled))
            end
            optionRow.fontPreview:Show()
            optionRow.text:SetPoint("RIGHT", optionRow.fontPreview, "LEFT", -8, 0)
        elseif row.mediaType == "sound" and path then
            if not optionRow.soundButton then
                optionRow.soundButton = CreateFrame("Button", nil, optionRow)
                optionRow.soundButton:SetSize(20, 20)
                optionRow.soundButton:SetPoint("RIGHT", optionRow, "RIGHT", -3, 0)
                optionRow.soundButton:SetFrameLevel(optionRow:GetFrameLevel() + 3)
                StyleSoundButton(optionRow.soundButton)
                optionRow.soundButton:SetScript("OnClick", function(self)
                    PlayPreview(ResolveMediaPath("sound", self:GetParent().item))
                end)
                Controls.SetTooltip(
                    optionRow.soundButton,
                    (L and L["DROPDOWN_PREVIEW"]) or PREVIEW or "Preview"
                )
            end
            optionRow.soundButton:Show()
            optionRow.text:SetPoint("RIGHT", optionRow, "RIGHT", -30, 0)
        end

        optionRow:SetAlpha(item.disabled and 0.55 or 1)
    end

    function row:ApplyFilter(query)
        query = tostring(query or ""):lower():match("^%s*(.-)%s*$") or ""
        wipe(self.filtered)
        for _, item in ipairs(self.items) do
            if query == "" or item.searchText:find(query, 1, true) then
                self.filtered[#self.filtered + 1] = item
            end
        end

        for index, item in ipairs(self.filtered) do
            local optionRow = AcquireOptionRow(index)
            ConfigureOptionRow(optionRow, item)
            optionRow:ClearAllPoints()
            optionRow:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -((index - 1) * rowHeight))
            optionRow:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -((index - 1) * rowHeight))
            optionRow:Show()
        end
        for index = #self.filtered + 1, #self.rows do
            self.rows[index]:Hide()
        end

        self.keyboardIndex = #self.filtered > 0 and 1 or 0
        child:SetHeight(math.max(1, #self.filtered * rowHeight))
        emptyText:SetShown(#self.filtered == 0)

        local searchHeight = self.searchable and 34 or 0
        local visibleRows = math.min(math.max(1, #self.filtered), maxVisible)
        local listHeight = 8 + searchHeight + visibleRows * rowHeight
        list:SetHeight(listHeight)

        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -(4 + searchHeight))
        scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -12, 4)
        scrollbar:ClearAllPoints()
        scrollbar:SetPoint("TOPRIGHT", list, "TOPRIGHT", -3, -(4 + searchHeight))
        scrollbar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -3, 4)
        search:SetShown(self.searchable)

        scroll:SetVerticalScroll(0)
        RefreshRowStates()
        C_Timer.After(0, UpdateScrollbar)
    end

    local function PositionList()
        list:ClearAllPoints()
        local uiScale = UIParent:GetEffectiveScale()
        local buttonScale = button:GetEffectiveScale()
        if uiScale and uiScale > 0 and buttonScale and buttonScale > 0 then
            list:SetScale(buttonScale / uiScale)
            catcher:SetScale(1)
        end

        local buttonBottom = (button:GetBottom() or 0) * (buttonScale or 1)
        local required = (list:GetHeight() or 0) * (buttonScale or 1) + 12
        if buttonBottom > required then
            list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        else
            list:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
        end
    end

    function row:Open()
        if self._disabled or #self.items == 0 then return end
        if activeDropdown and activeDropdown ~= self then
            activeDropdown:Close()
        end
        activeDropdown = self
        self:ApplyFilter("")
        PositionList()
        catcher:Show()
        list:Show()
        button:SetBackdropBorderColor(r, g, b, 1)
        arrow:SetTextColor(r, g, b, 1)
        if self.searchable then
            search:SetText("")
            C_Timer.After(0, function()
                if list:IsShown() then
                    search.editBox:SetFocus()
                end
            end)
        end
    end

    function row:Close()
        list:Hide()
        catcher:Hide()
        search.editBox:ClearFocus()
        button:SetBackdropBorderColor(Controls.UnpackColor(C.border.default))
        arrow:SetTextColor(Controls.UnpackColor(C.text.dim))
        if activeDropdown == self then activeDropdown = nil end
    end

    function row:SetValue(value, silent)
        for _, item in ipairs(self.items) do
            if item.value == value or item.text == value then
                return SelectItem(item, silent ~= false)
            end
        end
        self.currentValue = value
        selectedText:SetText(opts.placeholder or "Select...")
        UpdateSelectedMedia(nil)
        RefreshRowStates()
        return false
    end

    function row:GetValue()
        return self.currentValue
    end

    function row:GetText()
        return selectedText:GetText()
    end

    function row:SetOptions(nextOptions, currentValue)
        self.items = NormalizeOptions(nextOptions)
        if opts.searchable == nil then
            self.searchable = self.mediaType ~= nil or #self.items > (opts.searchThreshold or 7)
        end
        self:SetValue(currentValue, true)
    end

    function row:SetDisabledState(disabled)
        self._disabled = disabled == true
        button:SetEnabled(not self._disabled)
        self:SetAlpha(self._disabled and 0.48 or 1)
        if self._disabled then self:Close() end
    end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        if list:IsShown() then row:Close() else row:Open() end
    end)
    button:SetScript("OnEnter", function()
        button:SetBackdropBorderColor(r, g, b, 0.85)
        arrow:SetTextColor(r, g, b, 1)
    end)
    button:SetScript("OnLeave", function()
        if not list:IsShown() then
            button:SetBackdropBorderColor(Controls.UnpackColor(C.border.default))
            arrow:SetTextColor(Controls.UnpackColor(C.text.dim))
        end
    end)

    catcher:SetScript("OnClick", function()
        row:Close()
    end)
    catcher:EnableMouseWheel(true)
    catcher:SetScript("OnMouseWheel", function()
        row:Close()
    end)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local nextValue = self:GetVerticalScroll() - delta * rowHeight * 2
        nextValue = math.max(0, math.min(self:GetVerticalScrollRange() or 0, nextValue))
        self:SetVerticalScroll(nextValue)
        UpdateScrollbar()
    end)
    scroll:SetScript("OnVerticalScroll", UpdateScrollbar)
    scroll:SetScript("OnScrollRangeChanged", UpdateScrollbar)

    local draggingThumb = false
    local dragStartY
    local dragStartScroll
    thumb:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        draggingThumb = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / UIParent:GetEffectiveScale()
        dragStartScroll = scroll:GetVerticalScroll()
        thumbTexture:SetColorTexture(r, g, b, 1)
    end)
    thumb:SetScript("OnMouseUp", function()
        draggingThumb = false
        thumbTexture:SetColorTexture(r, g, b, 0.7)
    end)
    thumb:SetScript("OnUpdate", function()
        if not draggingThumb then return end
        if not IsMouseButtonDown("LeftButton") then
            draggingThumb = false
            thumbTexture:SetColorTexture(r, g, b, 0.7)
            return
        end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / UIParent:GetEffectiveScale()
        local delta = dragStartY - cursorY
        local trackRange = math.max(1, scrollbar:GetHeight() - thumb:GetHeight())
        local scrollRange = scroll:GetVerticalScrollRange() or 0
        scroll:SetVerticalScroll(math.max(0, math.min(
            scrollRange,
            dragStartScroll + (delta / trackRange) * scrollRange
        )))
        UpdateScrollbar()
    end)

    search:SetOnTextChanged(function(query)
        row:ApplyFilter(query)
    end)
    search.editBox:HookScript("OnKeyDown", function(self, key)
        if key == "DOWN" and #row.filtered > 0 then
            row.keyboardIndex = math.min(#row.filtered, math.max(1, row.keyboardIndex + 1))
            ScrollToKeyboardRow()
            RefreshRowStates()
        elseif key == "UP" and #row.filtered > 0 then
            row.keyboardIndex = math.max(1, row.keyboardIndex - 1)
            ScrollToKeyboardRow()
            RefreshRowStates()
        elseif key == "ENTER" or key == "NUMPADENTER" then
            local item = row.filtered[row.keyboardIndex]
            if SelectItem(item) then row:Close() end
        elseif key == "ESCAPE" then
            if self:GetText() ~= "" then
                self:SetText("")
            else
                row:Close()
            end
        end
    end)

    row:HookScript("OnHide", function()
        row:Close()
    end)
    Controls.SetTooltip(row, opts.tooltip)
    Controls.EnableRightClickMouselook(row)
    Controls.EnableRightClickMouselook(button)

    local selected
    for _, item in ipairs(row.items) do
        if item.value == default or item.text == default then
            selected = item
            break
        end
    end
    if not selected and #row.items > 0 and default == nil then
        selected = row.items[1]
    end
    if selected then
        SelectItem(selected, true)
    else
        row.currentValue = default
        selectedText:SetText(opts.placeholder or "Select...")
    end

    row.label = label
    row.button = button
    row.selectedText = selectedText
    row.listFrame = list
    row.searchBox = search
    row.scrollFrame = scroll
    row.scrollChild = child
    row.control = button
    return row
end
