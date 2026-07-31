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
            if not modules or modules[moduleName] ~= false then
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

local function ShowProfileError(status, reason)
    local messages = {
        empty = LT("PROFILE_ERROR_EMPTY", "Enter a profile name."),
        long = LT("PROFILE_ERROR_LONG", "Profile names can contain up to 48 characters."),
        exists = LT("PROFILE_ERROR_EXISTS", "A profile with that name already exists."),
        last = LT("PROFILE_ERROR_LAST", "The last profile cannot be deleted."),
        missing = LT("PROFILE_ERROR_MISSING", "The selected profile no longer exists."),
        storage = LT("PROFILE_ERROR_STORAGE", "Profile storage is not available."),
    }
    status:SetText(messages[reason] or LT("PROFILE_ERROR_UNKNOWN", "The profile operation failed."))
    status:SetTextColor(1, 0.32, 0.28, 1)
end

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
