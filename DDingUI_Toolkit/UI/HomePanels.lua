local addonName, ns = ...

local Lib = LibStub("DDingUI-StyleLib-1.0")
local Controls = ns.ToolkitControls or Lib
local L = ns.L
local C = Lib.Colors
local F = Lib.Font
local SOLID = Lib.Textures and Lib.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local ADDON_KEY = "MJToolkit"

local HomePanels = {}
ns.ToolkitHomePanels = HomePanels

local function LT(key, fallback)
    local value = L and rawget(L, key)
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

local function Color(color, alpha)
    color = color or { 1, 1, 1, alpha or 1 }
    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or alpha or 1
end

local function MakeText(parent, size, color, text)
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    fontString:SetFont(F.path, math.max(1, tonumber(size) or F.normal), "")
    fontString:SetTextColor(Color(color or C.text.normal))
    fontString:SetText(text or "")
    fontString:SetJustifyH("LEFT")
    return fontString
end

local function SetBackdrop(frame, background, border)
    frame:SetBackdrop({
        bgFile = SOLID,
        edgeFile = SOLID,
        edgeSize = 1,
    })
    frame:SetBackdropColor(Color(background or C.bg.input))
    frame:SetBackdropBorderColor(Color(border or C.border.default))
end

local function AddSection(parent, text, y)
    local section = Controls.CreateSectionHeader(parent, ADDON_KEY, text, {
        isFirst = y == -12,
    })
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    section:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y)
    return y - section:GetHeight()
end

local function AddStat(parent, x, width, label)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -58)
    frame:SetSize(width, 74)
    SetBackdrop(frame, { 0.07, 0.072, 0.082, 0.94 }, { 0.22, 0.23, 0.26, 0.85 })

    local value = MakeText(frame, 24, C.text.highlight, "0")
    value:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)

    local caption = MakeText(frame, F.small, C.text.dim, label)
    caption:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
    frame.value = value
    return frame
end

local function GetWorkspace()
    local frame = _G.DDingUI_MJToolkit_Panel
    local result = frame and frame._panelResult
    return result and result.workspace
end

local function GetModuleCounts(panelKeys)
    local seen = {}
    local enabled, total = 0, 0
    for _, panelKey in ipairs(panelKeys or {}) do
        local moduleName = ns.ConfigModuleMap and ns.ConfigModuleMap[panelKey]
        if moduleName and not seen[moduleName] then
            seen[moduleName] = true
            total = total + 1
            local modules = ns.db and ns.db.profile and ns.db.profile.modules
            if modules and modules[moduleName] == true then
                enabled = enabled + 1
            end
        end
    end
    return enabled, total
end

function HomePanels:RenderDashboard(container)
    local title = MakeText(container, 16, C.text.highlight, LT("DASHBOARD_STATUS", "Module status"))
    title:SetPoint("TOPLEFT", container, "TOPLEFT", 18, -18)

    local statWidth = 146
    local totalStat = AddStat(container, 18, statWidth, LT("DASHBOARD_TOTAL_MODULES", "Total modules"))
    local enabledStat = AddStat(container, 18 + statWidth + 10, statWidth, LT("DASHBOARD_ENABLED_MODULES", "Enabled"))
    local disabledStat = AddStat(container, 18 + ((statWidth + 10) * 2), statWidth, LT("DASHBOARD_DISABLED_MODULES", "Disabled"))

    local y = AddSection(container, LT("DASHBOARD_WORKSPACES", "Workspaces"), -148)
    local categoryRows = {}
    local workspace = GetWorkspace()
    for _, category in ipairs(workspace and workspace.categories or {}) do
        if category.key ~= "dashboard" and category.key ~= "profile" then
            local row = CreateFrame("Frame", nil, container, "BackdropTemplate")
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 6)
            row:SetPoint("TOPRIGHT", container, "TOPRIGHT", -18, y - 6)
            row:SetHeight(46)
            SetBackdrop(row, { 0.065, 0.067, 0.075, 0.88 }, { 0.18, 0.19, 0.22, 0.8 })

            local label = MakeText(row, F.normal, C.text.highlight, category.label)
            label:SetPoint("LEFT", row, "LEFT", 14, 6)
            local status = MakeText(row, F.small, C.text.dim, "")
            status:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)

            local open = Controls.CreateButton(row, ADDON_KEY, LT("DASHBOARD_OPEN", "Open"), function()
                local activeWorkspace = GetWorkspace()
                if activeWorkspace then
                    activeWorkspace:SelectCategory(category.key, true)
                end
            end, { width = 92, height = 26 })
            open:SetPoint("RIGHT", row, "RIGHT", -10, 0)

            categoryRows[#categoryRows + 1] = {
                status = status,
                panels = category.panels,
            }
            y = y - 52
        end
    end

    y = AddSection(container, LT("DASHBOARD_QUICK_ACTIONS", "Quick actions"), y - 6)
    local editMode = Controls.CreateButton(container, ADDON_KEY, LT("EDIT_MODE", "Edit Mode"), function()
        local panel = _G.DDingUI_MJToolkit_Panel
        if panel then panel:Hide() end
        C_Timer.After(0, function()
            if ns.ToolkitMovers and ns.ToolkitMovers.ToggleConfigMode then
                ns.ToolkitMovers:ToggleConfigMode()
            end
        end)
    end, { width = 150 })
    editMode:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 8)

    local profiles = Controls.CreateButton(container, ADDON_KEY, LT("WORKSPACE_PROFILE", "Profile"), function()
        if ns.ConfigUI and ns.ConfigUI.SelectPanel then
            ns.ConfigUI:SelectPanel("profile")
        end
    end, { width = 150 })
    profiles:SetPoint("LEFT", editMode, "RIGHT", 10, 0)
    y = y - 48

    function container:_refresh()
        local allPanels = {}
        local activeWorkspace = GetWorkspace()
        for _, category in ipairs(activeWorkspace and activeWorkspace.categories or {}) do
            if category.key ~= "dashboard" and category.key ~= "profile" then
                for _, panelKey in ipairs(category.panels or {}) do
                    allPanels[#allPanels + 1] = panelKey
                end
            end
        end

        local enabled, total = GetModuleCounts(allPanels)
        totalStat.value:SetText(total)
        enabledStat.value:SetText(enabled)
        disabledStat.value:SetText(math.max(0, total - enabled))
        for _, row in ipairs(categoryRows) do
            local rowEnabled, rowTotal = GetModuleCounts(row.panels)
            row.status:SetFormattedText(
                LT("DASHBOARD_MODULE_COUNT", "%d of %d enabled"),
                rowEnabled,
                rowTotal
            )
        end
    end

    container._contentHeight = math.max(520, math.abs(y) + 24)
    container:SetHeight(container._contentHeight)
    container:_refresh()
end

local PROFILE_ACTION_POPUP = "DDINGTOOLKIT_PROFILE_ACTION"
local PROFILE_IMPORT_POPUP = "DDINGTOOLKIT_PROFILE_IMPORT"
local profileCodeDialog

StaticPopupDialogs[PROFILE_ACTION_POPUP] = {
    text = "%s",
    button1 = ACCEPT or "OK",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, data)
        if not data then return end
        local ok
        if data.action == "reset" then
            ok = ns:ResetToolkitProfile()
        elseif data.action == "delete" then
            ok = ns:DeleteToolkitProfile(data.profileName)
        end
        if ok then ReloadUI() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ProfileErrorText(reason)
    local messages = {
        empty = LT("PROFILE_ERROR_EMPTY", "Enter a profile name."),
        long = LT("PROFILE_ERROR_LONG", "Profile names can contain up to 48 characters."),
        exists = LT("PROFILE_ERROR_EXISTS", "A profile with that name already exists."),
        last = LT("PROFILE_ERROR_LAST", "The last profile cannot be deleted."),
        missing = LT("PROFILE_ERROR_MISSING", "The selected profile no longer exists."),
        storage = LT("PROFILE_ERROR_STORAGE", "Profile storage is not available."),
        profile_missing = LT("PROFILE_CODE_ERROR_PROFILE", "The profile data is missing."),
        library = LT("PROFILE_CODE_ERROR_LIBRARY", "The profile-code libraries are unavailable."),
        empty_code = LT("PROFILE_CODE_ERROR_EMPTY", "Paste a profile code first."),
        code_size = LT("PROFILE_CODE_ERROR_SIZE", "The profile code is too large."),
        data_size = LT("PROFILE_CODE_ERROR_SIZE", "The profile code is too large."),
        data_depth = LT("PROFILE_CODE_ERROR_DATA", "The profile contains unsupported data."),
        data_type = LT("PROFILE_CODE_ERROR_DATA", "The profile contains unsupported data."),
        data_cycle = LT("PROFILE_CODE_ERROR_DATA", "The profile contains unsupported data."),
        format = LT("PROFILE_CODE_ERROR_FORMAT", "This is not a Toolkit profile code."),
        decode = LT("PROFILE_CODE_ERROR_CORRUPT", "The profile code is damaged or incomplete."),
        checksum = LT("PROFILE_CODE_ERROR_CORRUPT", "The profile code is damaged or incomplete."),
        decompress = LT("PROFILE_CODE_ERROR_CORRUPT", "The profile code is damaged or incomplete."),
        deserialize = LT("PROFILE_CODE_ERROR_CORRUPT", "The profile code is damaged or incomplete."),
        wrong_addon = LT("PROFILE_CODE_ERROR_ADDON", "This code belongs to a different addon."),
        schema = LT("PROFILE_CODE_ERROR_VERSION", "This profile-code version is not supported."),
        serialize = LT("PROFILE_CODE_ERROR_EXPORT", "The profile could not be exported."),
        compress = LT("PROFILE_CODE_ERROR_EXPORT", "The profile could not be exported."),
        encode = LT("PROFILE_CODE_ERROR_EXPORT", "The profile could not be exported."),
        name_unavailable = LT("PROFILE_CODE_ERROR_NAME", "A name for the imported profile could not be created."),
    }
    return messages[reason] or LT("PROFILE_ERROR_UNKNOWN", "The profile operation failed.")
end

local function ShowProfileError(status, reason)
    status:SetText(ProfileErrorText(reason))
    status:SetTextColor(1, 0.32, 0.28, 1)
end

local function CreateProfileCodeDialog()
    if profileCodeDialog then return profileCodeDialog end

    local overlay = CreateFrame("Frame", "DDingUIToolkitProfileCodeOverlay", UIParent, "BackdropTemplate")
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel(180)
    overlay:EnableMouse(true)
    overlay:SetBackdrop({ bgFile = SOLID })
    overlay:SetBackdropColor(0, 0, 0, 0.58)
    overlay:Hide()
    UISpecialFrames[#UISpecialFrames + 1] = overlay:GetName()

    local dialog = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:SetSize(630, 430)
    dialog:SetFrameLevel(overlay:GetFrameLevel() + 1)
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    SetBackdrop(dialog, { 0.035, 0.038, 0.047, 0.98 }, { 0.15, 0.75, 0.92, 0.95 })

    local title = MakeText(dialog, 17, C.text.highlight, "")
    title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -18)

    local closeIcon = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeIcon:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -2, -2)
    closeIcon:SetScript("OnClick", function() overlay:Hide() end)

    local description = MakeText(dialog, F.small, C.text.dim, "")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    description:SetPoint("RIGHT", dialog, "RIGHT", -42, 0)
    description:SetJustifyV("TOP")
    description:SetWordWrap(true)

    local nameRow = CreateFrame("Frame", nil, dialog)
    nameRow:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -82)
    nameRow:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -20, -82)
    nameRow:SetHeight(28)

    local nameLabel = MakeText(nameRow, F.normal, C.text.normal, LT("PROFILE_CODE_IMPORT_NAME", "New profile name (optional)"))
    nameLabel:SetPoint("LEFT", nameRow, "LEFT", 0, 0)

    local nameEdit = CreateFrame("EditBox", nil, nameRow, "BackdropTemplate")
    nameEdit:SetPoint("RIGHT", nameRow, "RIGHT", 0, 0)
    nameEdit:SetSize(310, 25)
    nameEdit:SetAutoFocus(false)
    nameEdit:SetMaxLetters(48)
    nameEdit:SetFont(F.path, math.max(1, F.normal), "")
    nameEdit:SetTextColor(Color(C.text.highlight))
    nameEdit:SetTextInsets(7, 7, 0, 0)
    SetBackdrop(nameEdit, C.bg.input, C.border.default)
    nameEdit:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.15, 0.75, 0.92, 1)
        self:HighlightText()
    end)
    nameEdit:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(Color(C.border.default))
        self:HighlightText(0, 0)
    end)
    nameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local codeBox = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    codeBox:SetPoint("LEFT", dialog, "LEFT", 20, 0)
    codeBox:SetPoint("RIGHT", dialog, "RIGHT", -20, 0)
    codeBox:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 68)
    SetBackdrop(codeBox, { 0.018, 0.020, 0.026, 1 }, C.border.default)

    local scroll = CreateFrame("ScrollFrame", nil, codeBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", codeBox, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", codeBox, "BOTTOMRIGHT", -28, 8)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(F.path, math.max(1, F.small), "")
    editBox:SetTextColor(Color(C.text.highlight))
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:SetMaxLetters(ns.PROFILE_CODE_MAX_BYTES or 524288)
    scroll:SetScrollChild(editBox)

    local function ResizeEditBox()
        local width = math.max(1, (scroll:GetWidth() or 1) - 4)
        editBox:SetWidth(width)
        local textHeight = tonumber(editBox:GetStringHeight()) or 0
        editBox:SetHeight(math.max(scroll:GetHeight() or 1, textHeight + 14))
    end
    scroll:SetScript("OnSizeChanged", ResizeEditBox)
    scroll:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    codeBox:EnableMouse(true)
    codeBox:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    editBox:SetScript("OnTextChanged", function()
        ResizeEditBox()
        if dialog._clearStatusOnEdit then
            dialog.status:SetText("")
        end
    end)
    editBox:SetScript("OnCursorChanged", function(_, _, y, _, cursorHeight)
        y = -y
        local offset = scroll:GetVerticalScroll()
        if y < offset then
            scroll:SetVerticalScroll(y)
            return
        end

        local cursorBottom = y + cursorHeight - scroll:GetHeight()
        if cursorBottom > offset then
            scroll:SetVerticalScroll(cursorBottom)
        end
    end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local status = MakeText(dialog, F.small, C.text.dim, "")
    status:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 24)
    status:SetPoint("RIGHT", dialog, "RIGHT", -255, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    dialog.status = status
    nameEdit:SetScript("OnTextChanged", function()
        if dialog._clearStatusOnEdit then
            status:SetText("")
        end
    end)

    local close = Controls.CreateButton(dialog, ADDON_KEY, LT("PROFILE_CODE_CLOSE", "Close"), function()
        overlay:Hide()
    end, { width = 90 })
    close:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 18)

    local primary = Controls.CreateButton(dialog, ADDON_KEY, "", function()
        if dialog.mode == "export" then
            editBox:SetFocus()
            editBox:HighlightText()
            status:SetText(LT("PROFILE_CODE_COPY_READY", "Press Ctrl+C to copy the selected code."))
            status:SetTextColor(Color(C.text.dim))
            return
        end

        local decoded, reason = ns:DecodeToolkitProfileCode(editBox:GetText())
        if not decoded then
            ShowProfileError(status, reason)
            return
        end

        local targetName, nameError = ns:GetToolkitImportProfileName(decoded, nameEdit:GetText())
        if not targetName then
            ShowProfileError(status, nameError)
            return
        end

        local sourceName = decoded.profileName ~= "" and decoded.profileName
            or LT("PROFILE_CODE_UNKNOWN_PROFILE", "Unnamed profile")
        local popup = StaticPopup_Show(
            PROFILE_IMPORT_POPUP,
            string.format(
                LT("PROFILE_CODE_IMPORT_CONFIRM", "Import '%s' as the new profile '%s' and apply it?"),
                sourceName,
                targetName
            ),
            nil,
            {
                decoded = decoded,
                profileName = targetName,
                dialog = dialog,
            }
        )
        if popup then
            popup:SetFrameLevel(overlay:GetFrameLevel() + 20)
        end
    end, { width = 130 })
    primary:SetPoint("RIGHT", close, "LEFT", -10, 0)

    function dialog:SetStatus(text, isError)
        status:SetText(text or "")
        if isError then
            status:SetTextColor(1, 0.32, 0.28, 1)
        else
            status:SetTextColor(Color(C.text.dim))
        end
    end

    function dialog:Open(mode, code)
        self.mode = mode
        self._clearStatusOnEdit = false
        status:SetText("")
        nameEdit:SetText("")
        editBox:SetText(code or "")

        codeBox:ClearAllPoints()
        codeBox:SetPoint("LEFT", dialog, "LEFT", 20, 0)
        codeBox:SetPoint("RIGHT", dialog, "RIGHT", -20, 0)
        codeBox:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 68)

        if mode == "export" then
            title:SetText(LT("PROFILE_CODE_EXPORT_TITLE", "Export profile code"))
            description:SetText(LT("PROFILE_CODE_EXPORT_DESC", "Copy this code to save or share the current profile. Saved memo text is excluded."))
            nameRow:Hide()
            codeBox:SetPoint("TOP", dialog, "TOP", 0, -82)
            primary.label:SetText(LT("PROFILE_CODE_SELECT_ALL", "Select all"))
        else
            title:SetText(LT("PROFILE_CODE_IMPORT_TITLE", "Import profile code"))
            description:SetText(LT("PROFILE_CODE_IMPORT_DESC", "Paste a Toolkit code below. It will be added as a new profile; leave the name empty to use the code's profile name."))
            nameRow:Show()
            codeBox:SetPoint("TOP", dialog, "TOP", 0, -122)
            primary.label:SetText(LT("PROFILE_CODE_IMPORT_ACTION", "Import"))
        end

        overlay:Show()
        self._clearStatusOnEdit = true
        C_Timer.After(0, function()
            if not overlay:IsShown() then return end
            editBox:SetFocus()
            if mode == "export" then
                editBox:HighlightText()
            end
            ResizeEditBox()
        end)
    end

    overlay:SetScript("OnHide", function()
        editBox:ClearFocus()
        nameEdit:ClearFocus()
    end)

    profileCodeDialog = dialog
    return dialog
end

StaticPopupDialogs[PROFILE_IMPORT_POPUP] = {
    text = "%s",
    button1 = ACCEPT or "OK",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, data)
        if not data then return end
        local ok, result = ns:ImportToolkitProfileCode(data.decoded, data.profileName)
        if ok then
            ReloadUI()
        elseif data.dialog then
            ShowProfileError(data.dialog.status, result)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function HomePanels:RenderProfile(container)
    local currentTitle = MakeText(container, F.small, C.text.dim, LT("PROFILE_CURRENT", "Current profile"))
    currentTitle:SetPoint("TOPLEFT", container, "TOPLEFT", 18, -18)
    local currentName = MakeText(container, 22, C.text.highlight, "")
    currentName:SetPoint("TOPLEFT", currentTitle, "BOTTOMLEFT", 0, -7)
    local usage = MakeText(container, F.small, C.text.dim, "")
    usage:SetPoint("TOPLEFT", currentName, "BOTTOMLEFT", 0, -6)

    local y = AddSection(container, LT("PROFILE_SWITCH", "Switch profile"), -92)
    local selectedProfile = ns:GetToolkitProfileName()
    local applyProfile
    local profileDropdown = Controls.CreateDropdown(
        container,
        ADDON_KEY,
        LT("PROFILE_AVAILABLE", "Available profiles"),
        ns:GetToolkitProfileOptions(),
        selectedProfile,
        {
            width = 240,
            searchable = true,
            onChange = function(value)
                selectedProfile = value
                if applyProfile then
                    applyProfile:SetDisabledState(value == ns:GetToolkitProfileName())
                end
            end,
        }
    )
    profileDropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 8)
    profileDropdown:SetPoint("TOPRIGHT", container, "TOPRIGHT", -18, y - 8)

    applyProfile = Controls.CreateButton(container, ADDON_KEY, LT("PROFILE_APPLY", "Apply profile"), function()
        if selectedProfile == ns:GetToolkitProfileName() then return end
        local ok, reason = ns:UseToolkitProfile(selectedProfile)
        if ok then
            ReloadUI()
        else
            ShowProfileError(container._status, reason)
        end
    end, { width = 150 })
    applyProfile:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 48)
    y = y - 88

    y = AddSection(container, LT("PROFILE_CREATE", "Create profile"), y)
    local newName = ""
    local nameInput = Controls.CreateInputField(
        container,
        ADDON_KEY,
        LT("PROFILE_NAME", "Profile name"),
        "",
        {
            inputWidth = 240,
            maxLetters = 48,
            onChange = function(value)
                newName = value or ""
            end,
        }
    )
    nameInput:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 8)
    nameInput:SetPoint("TOPRIGHT", container, "TOPRIGHT", -18, y - 8)

    local function CreateProfile(copyCurrent)
        newName = nameInput:GetValue()
        local ok, reason = ns:CreateToolkitProfile(newName, copyCurrent)
        if ok then
            ReloadUI()
        else
            ShowProfileError(container._status, reason)
        end
    end

    local createBlank = Controls.CreateButton(container, ADDON_KEY, LT("PROFILE_CREATE_DEFAULT", "Create from defaults"), function()
        CreateProfile(false)
    end, { width = 176 })
    createBlank:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 48)

    local duplicate = Controls.CreateButton(container, ADDON_KEY, LT("PROFILE_DUPLICATE", "Duplicate current"), function()
        CreateProfile(true)
    end, { width = 176 })
    duplicate:SetPoint("LEFT", createBlank, "RIGHT", 10, 0)
    y = y - 90

    y = AddSection(container, LT("PROFILE_CODE_SECTION", "Profile code"), y)
    local codeDescription = MakeText(
        container,
        F.small,
        C.text.dim,
        LT("PROFILE_CODE_SECTION_DESC", "Save the current settings as a shareable code or add a code as a new profile. Saved memo text is excluded.")
    )
    codeDescription:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 8)
    codeDescription:SetPoint("RIGHT", container, "RIGHT", -18, 0)
    codeDescription:SetJustifyV("TOP")
    codeDescription:SetWordWrap(true)

    local exportCode = Controls.CreateButton(container, ADDON_KEY, LT("PROFILE_CODE_EXPORT", "Export code"), function()
        local code, reason = ns:ExportToolkitProfileCode()
        if not code then
            ShowProfileError(container._status, reason)
            return
        end
        CreateProfileCodeDialog():Open("export", code)
    end, { width = 176 })
    exportCode:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 48)

    local importCode = Controls.CreateButton(container, ADDON_KEY, LT("PROFILE_CODE_IMPORT", "Import code"), function()
        CreateProfileCodeDialog():Open("import")
    end, { width = 176 })
    importCode:SetPoint("LEFT", exportCode, "RIGHT", 10, 0)
    y = y - 92

    y = AddSection(container, LT("PROFILE_GENERAL_SETTINGS", "Shared controls"), y)
    local minimap = Controls.CreateCheckbox(
        container,
        ADDON_KEY,
        L["SHOW_MINIMAP_BUTTON"] or "Show minimap button",
        not (ns.db and ns.db.profile and ns.db.profile.minimap and ns.db.profile.minimap.hide),
        {
            onChange = function(checked)
                ns.db.profile.minimap.hide = not checked
                local icon = LibStub("LibDBIcon-1.0", true)
                if icon then
                    if checked then
                        icon:Show(addonName)
                    else
                        icon:Hide(addonName)
                    end
                end
            end,
        }
    )
    minimap:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 8)
    minimap:SetPoint("TOPRIGHT", container, "TOPRIGHT", -18, y - 8)

    local welcome = Controls.CreateCheckbox(
        container,
        ADDON_KEY,
        L["SHOW_WELCOME_MESSAGE"] or "Show welcome message",
        ns.db and ns.db.profile and ns.db.profile.welcomeMessage == true,
        {
            onChange = function(checked)
                ns.db.profile.welcomeMessage = checked
            end,
        }
    )
    welcome:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 42)
    welcome:SetPoint("TOPRIGHT", container, "TOPRIGHT", -18, y - 42)
    y = y - 82

    y = AddSection(container, LT("PROFILE_MAINTENANCE", "Profile maintenance"), y)
    local reset = Controls.CreateButton(container, ADDON_KEY, LT("PROFILE_RESET", "Reset current"), function()
        StaticPopup_Show(
            PROFILE_ACTION_POPUP,
            LT("PROFILE_RESET_CONFIRM", "Reset the current profile to defaults?"),
            nil,
            { action = "reset" }
        )
    end, { width = 150 })
    reset:SetPoint("TOPLEFT", container, "TOPLEFT", 18, y - 8)

    local delete = Controls.CreateButton(container, ADDON_KEY, LT("PROFILE_DELETE", "Delete current"), function()
        if #ns:GetToolkitProfileNames() <= 1 then
            ShowProfileError(container._status, "last")
            return
        end
        StaticPopup_Show(
            PROFILE_ACTION_POPUP,
            string.format(
                LT("PROFILE_DELETE_CONFIRM", "Delete profile '%s'?"),
                ns:GetToolkitProfileName()
            ),
            nil,
            {
                action = "delete",
                profileName = ns:GetToolkitProfileName(),
            }
        )
    end, { width = 150 })
    delete:SetPoint("LEFT", reset, "RIGHT", 10, 0)

    local status = MakeText(container, F.small, C.text.dim, "")
    status:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -14)
    status:SetPoint("RIGHT", container, "RIGHT", -18, 0)
    container._status = status
    y = y - 62

    function container:_refresh()
        local profileName = ns:GetToolkitProfileName()
        local count = ns:GetToolkitProfileUsage(profileName)
        currentName:SetText(profileName)
        usage:SetFormattedText(LT("PROFILE_USAGE", "Used by %d character(s)"), count)
        profileDropdown:SetOptions(ns:GetToolkitProfileOptions(), profileName)
        selectedProfile = profileName
        applyProfile:SetDisabledState(true)
        profileDropdown:SetValue(profileName, true)
        minimap:SetChecked(not ns.db.profile.minimap.hide, true)
        welcome:SetChecked(ns.db.profile.welcomeMessage == true, true)
    end

    container._contentHeight = math.max(610, math.abs(y) + 24)
    container:SetHeight(container._contentHeight)
    container:_refresh()
end
