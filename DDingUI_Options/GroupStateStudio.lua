local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local Base = DDingUI.GUIBase
local THEME = Base.THEME

local FLAT = "Interface\\Buttons\\WHITE8x8"
local FALLBACK_ICON = 134400
local EMPTY = {}

local STATE_ORDER = {
    { key = "ready", label = "Ready" },
    { key = "cooldown", label = "Cooldown" },
    { key = "active", label = "Active" },
    { key = "inactive", label = "Inactive" },
    { key = "maxCharges", label = "Max Charges" },
    { key = "unusable", label = "Unusable" },
}

local LAYOUT_KEYS = {
    alwaysShow = true,
    desatInactive = true,
    inactiveAlpha = true,
    hideWhenEmpty = true,
}

local GLOW_STYLE_KEYS = {
    "glowType",
    "glowColorMode",
    "glowColor",
    "glowSpeed",
    "glowLines",
    "glowThickness",
}

local RESET_KEYS = {
    ready = {
        { "glow", "cooldownReadyGlow" },
    },
    cooldown = {
        { "visual", "showCooldown" },
        { "visual", "desaturateOnCooldown" },
        { "visual", "cooldownSwipeMode" },
        { "visual", "nonActiveMode" },
        { "visual", "cooldownStateEffect" },
    },
    active = {
        { "glow", "activeGlow" },
        { "glow", "procGlowMode" },
        { "visual", "activeEffectDisplayMode" },
        { "visual", "activeSwipeMode" },
        { "visual", "activeBorderEnabled" },
        { "visual", "activeDurationMode" },
        { "visual", "showProcDuration" },
        { "visual", "showProcStacks" },
    },
    inactive = {
        { "visual", "alwaysShow" },
        { "visual", "desatInactive" },
    },
    maxCharges = {
        { "glow", "maxChargesGlow" },
        { "visual", "showCharges" },
        { "visual", "chargeCountMode" },
    },
    unusable = {
        { "visual", "desaturateWhenUnusable" },
        { "visual", "nonActiveMode" },
    },
}

local function T(key, fallback)
    return rawget(L, key) or fallback or key
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function SafePositiveNumber(value)
    if value == nil or IsSecret(value) then return nil end
    local number = tonumber(value)
    if not number or number <= 0 then return nil end
    return number
end

local function CloneTable(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and CloneTable(value) or value
    end
    return copy
end

local function IsEmpty(value)
    return type(value) ~= "table" or next(value) == nil
end

local function GetDynamicCapabilities(iconData, settings)
    local iconType = iconData and iconData.type
    local overlay = DDingUI.CustomIconActiveEffectOverlay
    local itemID = iconData and SafePositiveNumber(iconData.id)
    local itemActive = iconType == "item" and overlay and overlay.SupportsActiveEffect
        and overlay:SupportsActiveEffect(itemID, settings) == true
    local procActive = iconType == "racial"
        or iconType == "trinketProc"
        or iconType == "slot"
        or (iconType == "item" and overlay and overlay.SupportsProcGlow
            and overlay:SupportsProcGlow(itemID, settings) == true)
    local buffLike = iconType == "aura" or iconType == "trinketProc" or iconType == "totem"
    local hasCooldown = iconType ~= "aura" and iconType ~= "totem"
    return {
        ready = hasCooldown,
        cooldown = hasCooldown,
        active = buffLike or itemActive or procActive,
        inactive = buffLike or itemActive,
        maxCharges = iconType == "spell" or iconType == "racial",
        unusable = hasCooldown,
        buffLike = buffLike,
        itemActive = itemActive,
        procActive = procActive,
    }
end

local function GetCDMCapabilities(viewerType)
    local hasCooldown = viewerType ~= "Buff"
    return {
        ready = hasCooldown,
        cooldown = hasCooldown,
        active = true,
        inactive = viewerType == "Buff",
        maxCharges = hasCooldown,
        unusable = hasCooldown,
        buffLike = viewerType == "Buff",
        itemActive = false,
        procActive = false,
    }
end

local function GetContext(groupName, create)
    local opt = DDingUI:GetGroupIconDetailSelection(groupName)
    local profile = DDingUI.db and DDingUI.db.profile
    if not opt or not profile then return nil end

    if opt._gridKind == "dynamic" then
        local dynamicIcons = profile.dynamicIcons
        local iconData = dynamicIcons and dynamicIcons.iconData
            and dynamicIcons.iconData[opt._gridDynamicIconKey]
        if not iconData then return nil end
        if create then iconData.settings = iconData.settings or {} end
        local settings = iconData.settings or EMPTY
        return {
            kind = "dynamic",
            groupName = groupName,
            opt = opt,
            iconKey = opt._gridDynamicIconKey,
            iconData = iconData,
            iconType = iconData.type or opt._gridDynamicIconType,
            settings = settings,
            glowSettings = settings.customStateGlow or EMPTY,
            capabilities = GetDynamicCapabilities(iconData, settings),
        }
    end

    if opt._gridKind ~= "cdm" then return nil end
    local spellID = SafePositiveNumber(opt._gridSpellID)
    local viewerType = opt._gridViewerType
    if not spellID or not viewerType then return nil end

    local iconCustomization = profile.iconCustomization
    local spells = iconCustomization and iconCustomization.spells
    if create then
        profile.iconCustomization = profile.iconCustomization or {}
        profile.iconCustomization.spells = profile.iconCustomization.spells or {}
        spells = profile.iconCustomization.spells
    end
    spells = spells or EMPTY

    local spellKey = tostring(spellID) .. "_" .. tostring(viewerType)
    local genericKey = tostring(spellID)
    local exact = spells[spellKey]
    local generic = spells[genericKey]
    if create and not exact then
        exact = type(generic) == "table" and CloneTable(generic) or {}
        spells[spellKey] = exact
    end
    local settings = exact or generic or EMPTY
    return {
        kind = "cdm",
        groupName = groupName,
        opt = opt,
        spellID = spellID,
        viewerType = viewerType,
        spells = spells,
        spellKey = spellKey,
        settings = settings,
        glowSettings = settings,
        capabilities = GetCDMCapabilities(viewerType),
    }
end

local function ReadSetting(context, scope, key, defaultValue)
    local settings = scope == "glow" and context.glowSettings or context.settings
    local value = settings and settings[key]
    if value == nil then return defaultValue end
    return value
end

local function MarkDirty()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

local function RefreshStateStudioOptions(groupName, delay)
    if DDingUI.SoftRefreshGroupSystemOptions then
        DDingUI:SoftRefreshGroupSystemOptions(delay or 0)
    end
end

local function RefreshRuntime(context, changes)
    local layoutChanged = false
    local glowChanged = false
    for _, change in ipairs(changes) do
        layoutChanged = layoutChanged or LAYOUT_KEYS[change.key] == true
        glowChanged = glowChanged or change.scope == "glow"
    end

    if context.kind == "dynamic" then
        if DDingUI.CustomIcons and DDingUI.CustomIcons.RefreshDynamicIcon then
            DDingUI.CustomIcons:RefreshDynamicIcon(context.iconKey)
        end
        if glowChanged and DDingUI.NativeTrinketOverlay
            and DDingUI.NativeTrinketOverlay.ApplyAll
        then
            C_Timer.After(0, function()
                DDingUI.NativeTrinketOverlay:ApplyAll()
            end)
        end
        if layoutChanged and DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge.NotifyIconsChanged then
            DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
        end
    elseif glowChanged and DDingUI.IconCustomization and DDingUI.IconCustomization.RefreshAllGlows then
        DDingUI.IconCustomization:RefreshAllGlows()
    elseif DDingUI.GroupSystem and DDingUI.GroupSystem.RequestFullUpdate then
        DDingUI.GroupSystem:RequestFullUpdate()
    end

    RefreshStateStudioOptions(context.groupName, 0.03)
end

local function WriteChanges(groupName, changes)
    local context = GetContext(groupName, true)
    if not context then return false end

    local glowStyleChanged = false

    for _, change in ipairs(changes) do
        local target
        if change.scope == "glow" and context.kind == "dynamic" then
            context.settings.customStateGlow = context.settings.customStateGlow or {}
            target = context.settings.customStateGlow
        else
            target = context.settings
        end
        target[change.key] = change.value
        glowStyleChanged = glowStyleChanged or change.glowStyle == true
    end

    if context.kind == "dynamic" and IsEmpty(context.settings.customStateGlow) then
        context.settings.customStateGlow = nil
        context.glowSettings = EMPTY
    elseif context.kind == "cdm" and IsEmpty(context.settings) then
        context.spells[context.spellKey] = nil
    end

    if context.kind == "cdm" and context.viewerType == "Buff" then
        for _, change in ipairs(changes) do
            if change.key == "alwaysShow" and change.value == "on"
                and DDingUI.EnsureGroupBuffIconOrder
            then
                DDingUI:EnsureGroupBuffIconOrder(groupName, context.opt)
                break
            end
        end
    end

    MarkDirty()
    RefreshRuntime(context, changes)
    if glowStyleChanged and DDingUI.ApplyAssignedIconGlowStyleScope then
        local current = GetContext(groupName, false)
        DDingUI:ApplyAssignedIconGlowStyleScope(
            groupName,
            current and current.glowSettings or EMPTY
        )
    end
    return true
end

local function GetSelectionKey(groupName, context)
    local detailKey = DDingUI:GetGroupIconDetailKey(context.opt)
    return tostring(groupName) .. "|" .. tostring(detailKey or "")
end

local function GetSelectedState(groupName, context)
    DDingUI._groupStateStudioSelection = DDingUI._groupStateStudioSelection or {}
    local selectionKey = GetSelectionKey(groupName, context)
    local selected = DDingUI._groupStateStudioSelection[selectionKey]
    if selected and context.capabilities[selected] then return selected end
    selected = context.capabilities.active and "active" or "ready"
    DDingUI._groupStateStudioSelection[selectionKey] = selected
    return selected
end

local function SetSelectedState(groupName, context, state)
    if not context.capabilities[state] then return end
    DDingUI._groupStateStudioSelection = DDingUI._groupStateStudioSelection or {}
    DDingUI._groupStateStudioSelection[GetSelectionKey(groupName, context)] = state
    RefreshStateStudioOptions(groupName, 0)
end

local function MakeToggle(groupName, label, scope, key, order, defaultValue)
    return {
        type = "toggle",
        name = label,
        order = order,
        width = "full",
        get = function()
            local context = GetContext(groupName, false)
            return context and ReadSetting(context, scope, key, defaultValue) == true or false
        end,
        set = function(_, value)
            local stored = value == defaultValue and nil or value == true
            WriteChanges(groupName, { { scope = scope, key = key, value = stored } })
        end,
    }
end

local function MakeSelect(groupName, label, scope, key, order, values, defaultValue, glowStyle)
    return {
        type = "select",
        name = label,
        order = order,
        width = "full",
        values = values,
        get = function()
            local context = GetContext(groupName, false)
            return context and ReadSetting(context, scope, key, defaultValue) or defaultValue
        end,
        set = function(_, value)
            local stored = value == defaultValue and nil or value
            WriteChanges(groupName, {
                { scope = scope, key = key, value = stored, glowStyle = glowStyle },
            })
        end,
    }
end

local function MakeRange(groupName, label, scope, key, order, defaultValue, minimum, maximum, step, glowStyle)
    return {
        type = "range",
        name = label,
        order = order,
        width = "full",
        min = minimum,
        max = maximum,
        step = step,
        isPercent = maximum <= 1,
        get = function()
            local context = GetContext(groupName, false)
            return tonumber(context and ReadSetting(context, scope, key, defaultValue)) or defaultValue
        end,
        set = function(_, value)
            local number = tonumber(value) or defaultValue
            local stored = math.abs(number - defaultValue) < 0.0001 and nil or number
            WriteChanges(groupName, {
                { scope = scope, key = key, value = stored, glowStyle = glowStyle },
            })
        end,
    }
end

local function MakeColor(groupName, label, scope, key, order, defaultColor, glowStyle)
    return {
        type = "color",
        name = label,
        order = order,
        width = "full",
        hasAlpha = true,
        get = function()
            local context = GetContext(groupName, false)
            local color = context and ReadSetting(context, scope, key, defaultColor) or defaultColor
            return color.r or color[1] or defaultColor[1],
                color.g or color[2] or defaultColor[2],
                color.b or color[3] or defaultColor[3],
                color.a or color[4] or defaultColor[4] or 1
        end,
        set = function(_, r, g, b, a)
            WriteChanges(groupName, {
                {
                    scope = scope,
                    key = key,
                    value = { r = r, g = g, b = b, a = a or 1 },
                    glowStyle = glowStyle,
                },
            })
        end,
    }
end

local function AddGlowActivationControl(args, groupName, context, state, order)
    local glowKey = state == "ready" and "cooldownReadyGlow"
        or state == "maxCharges" and "maxChargesGlow"
        or "activeGlow"
    local procGlow = state == "active" and context.kind == "dynamic"
        and context.capabilities.procActive
    if procGlow then
        args.glowEnabled = MakeSelect(groupName, T("Activation Glow", "Activation Glow"), "glow", "procGlowMode", order, {
            inherit = T("Default", "Default"),
            on = T("On", "On"),
            off = T("Off", "Off"),
        }, "inherit")
    else
        local label = state == "ready" and T("Ready Glow", "Ready Glow")
            or state == "maxCharges" and T("Max Charges Glow", "Max Charges Glow")
            or T("Activation Glow", "Activation Glow")
        args.glowEnabled = MakeToggle(groupName, label, "glow", glowKey, order, false)
    end
end

local function AddCooldownControls(args, groupName, context)
    if context.kind == "dynamic" then
        args.cooldownSwipe = MakeToggle(groupName, T("Show Cooldown Swipe", "Show Cooldown Swipe"), "visual", "showCooldown", 20, true)
        args.cooldownDesaturate = MakeToggle(groupName, T("Desaturate on Cooldown", "Desaturate on Cooldown"), "visual", "desaturateOnCooldown", 21, true)
    else
        args.cooldownSwipe = MakeSelect(groupName, T("Cooldown Swipe", "Cooldown Swipe"), "visual", "cooldownSwipeMode", 20, {
            inherit = T("Default", "Default"),
            normal = T("Normal", "Normal"),
            reverse = T("Reverse", "Reverse"),
            hidden = T("Hidden", "Hidden"),
        }, "inherit")
    end

    if context.kind == "cdm" or not context.capabilities.inactive then
        args.nonActiveMode = MakeSelect(groupName, T("Non-active Color", "Non-active Color"), "visual", "nonActiveMode", 22, {
            inherit = T("Default", "Default"),
            desaturate = T("Desaturate", "Desaturate"),
            fullColor = T("Full Color", "Full Color"),
        }, "inherit")
        args.cooldownEffect = MakeSelect(groupName, T("Cooldown State Effect", "Cooldown State Effect"), "visual", "cooldownStateEffect", 23, {
            inherit = T("Default", "Default"),
            lowerAlphaOnCD = T("Lower Opacity", "Lower Opacity"),
            hiddenOnCD = T("Hide on Cooldown", "Hide on Cooldown"),
            hiddenReady = T("Hide when Ready", "Hide when Ready"),
        }, "inherit")
    end
end

local function AddActiveControls(args, groupName, context)
    AddGlowActivationControl(args, groupName, context, "active", 20)
    if context.kind == "dynamic" and context.capabilities.itemActive then
        args.activeEffectDisplay = MakeSelect(groupName, T("Active Effect Display", "Active Effect Display"), "visual", "activeEffectDisplayMode", 24, {
            inherit = T("Default", "Default"),
            both = T("Swipe and Glow", "Swipe and Glow"),
            swipe = T("Swipe Only", "Swipe Only"),
            glow = T("Glow Only", "Glow Only"),
            glow_duration = T("Glow and Duration", "Glow and Duration"),
            hidden = T("Hidden", "Hidden"),
        }, "inherit")
    end
    args.activeSwipe = MakeSelect(groupName, T("Active Swipe", "Active Swipe"), "visual", "activeSwipeMode", 25, {
        inherit = T("Default", "Default"),
        custom = T("Custom Color", "Custom Color"),
        class = T("Class Color", "Class Color"),
        hidden = T("Hide Active State", "Hide Active State"),
    }, "inherit")
    args.activeBorder = MakeToggle(groupName, T("Active Border", "Active Border"), "visual", "activeBorderEnabled", 27, false)

    if context.kind == "dynamic" and context.iconType == "trinketProc" then
        args.activeDuration = MakeToggle(groupName, T("Show Proc Duration", "Show Proc Duration"), "visual", "showProcDuration", 29, true)
        args.activeStacks = MakeToggle(groupName, T("Show Proc Stacks", "Show Proc Stacks"), "visual", "showProcStacks", 30, true)
    elseif context.kind == "cdm" or context.capabilities.itemActive then
        args.activeDuration = MakeSelect(groupName, T("Active Duration Text", "Active Duration Text"), "visual", "activeDurationMode", 29, {
            inherit = T("Default", "Default"),
            show = T("Show", "Show"),
            hide = T("Hide", "Hide"),
        }, "inherit")
    end
end

local function AddInactiveControls(args, groupName)
    args.alwaysShow = MakeSelect(groupName, T("Always Show Buff", "Always Show Buff"), "visual", "alwaysShow", 20, {
        inherit = T("Default", "Default"),
        on = T("Show", "Show"),
        off = T("Hide", "Hide"),
    }, "inherit")
    args.desaturateInactive = MakeSelect(groupName, T("Desaturate Inactive", "Desaturate Inactive"), "visual", "desatInactive", 21, {
        inherit = T("Default", "Default"),
        on = T("Desaturate", "Desaturate"),
        off = T("Full Color", "Full Color"),
    }, "inherit")
end

local function AddMaxChargeControls(args, groupName, context)
    AddGlowActivationControl(args, groupName, context, "maxCharges", 20)
    if context.kind == "dynamic" then
        args.showCharges = MakeToggle(groupName, T("Show Charges", "Show Charges"), "visual", "showCharges", 24, true)
    else
        args.showCharges = MakeSelect(groupName, T("Charge Display", "Charge Display"), "visual", "chargeCountMode", 24, {
            inherit = T("Default", "Default"),
            show = T("Show", "Show"),
            hide = T("Hide", "Hide"),
        }, "inherit")
    end
end

local function AddUnusableControls(args, groupName, context)
    if context.kind == "dynamic" then
        args.unusableDesaturate = MakeToggle(groupName, T("Desaturate When Unusable", "Desaturate When Unusable"), "visual", "desaturateWhenUnusable", 20, true)
    end
    args.unusableColor = MakeSelect(groupName, T("Non-active Color", "Non-active Color"), "visual", "nonActiveMode", 21, {
        inherit = T("Default", "Default"),
        desaturate = T("Desaturate", "Desaturate"),
        fullColor = T("Full Color", "Full Color"),
    }, "inherit")
end

local function ResetState(groupName, state)
    local changes = {}
    for _, entry in ipairs(RESET_KEYS[state] or EMPTY) do
        changes[#changes + 1] = { scope = entry[1], key = entry[2], value = nil }
    end
    if #changes > 0 then WriteChanges(groupName, changes) end
end

local function StateLabel(state)
    for _, definition in ipairs(STATE_ORDER) do
        if definition.key == state then return T(definition.label, definition.label) end
    end
    return state
end

function DDingUI:BuildGroupStateStudioArgs(groupName)
    local context = GetContext(groupName, false)
    if not context then
        return {
            empty = {
                type = "description",
                name = T(
                    "Select an icon from the preview to edit its states.",
                    "Select an icon from the preview to edit its states."
                ),
                order = 1,
            },
        }
    end

    local state = GetSelectedState(groupName, context)
    local args = {
        studio = {
            type = "groupStateStudio",
            name = "",
            order = 1,
            groupName = groupName,
        },
        stateHeader = {
            type = "header",
            name = StateLabel(state),
            order = 10,
        },
    }

    if state == "ready" then
        AddGlowActivationControl(args, groupName, context, state, 20)
    elseif state == "cooldown" then
        AddCooldownControls(args, groupName, context)
    elseif state == "active" then
        AddActiveControls(args, groupName, context)
    elseif state == "inactive" then
        AddInactiveControls(args, groupName)
    elseif state == "maxCharges" then
        AddMaxChargeControls(args, groupName, context)
    elseif state == "unusable" then
        AddUnusableControls(args, groupName, context)
    end

    args.resetState = {
        type = "execute",
        name = T("Reset This State", "Reset This State"),
        order = 90,
        width = "normal",
        func = function() ResetState(groupName, state) end,
    }
    return args
end

local function GetResolvedGlowType(context)
    local glowType = ReadSetting(context, "glow", "glowType", "button")
    return glowType == "blizzard" and "proc" or glowType
end

local function GetResolvedGlowColorMode(context)
    if ReadSetting(context, "glow", "glowType") == "blizzard" then
        return "blizzard"
    end
    local mode = ReadSetting(context, "glow", "glowColorMode")
    if mode then return mode end
    return ReadSetting(context, "glow", "glowColor") and "custom" or "default"
end

local function ScopeDescription(scope)
    if scope == "all" then
        return T(
            "Glow style changes are copied to every icon in every specialization. State activation settings are not changed.",
            "글로우 스타일 변경을 모든 전문화의 모든 아이콘에 복사합니다. 상태 활성화 설정은 변경하지 않습니다."
        )
    elseif scope == "group" then
        return T(
            "Glow style changes are copied to every icon in this group. State activation settings are not changed.",
            "글로우 스타일 변경을 이 그룹의 모든 아이콘에 복사합니다. 상태 활성화 설정은 변경하지 않습니다."
        )
    end
    return T(
        "Glow style changes affect only the selected icon.",
        "글로우 스타일 변경은 선택한 아이콘에만 적용됩니다."
    )
end

function DDingUI:BuildGroupEffectStyleArgs(groupName)
    local context = GetContext(groupName, false)
    if not context then
        return {
            empty = {
                type = "description",
                name = T(
                    "Select an icon from the preview to edit its effect style.",
                    "미리보기에서 아이콘을 선택하면 효과 스타일을 편집할 수 있습니다."
                ),
                order = 1,
            },
        }
    end

    local scope = self._groupIconApplyScope or "icon"
    local args = {
        scopeHeader = {
            type = "header",
            name = T("Glow Apply Scope", "글로우 적용 범위"),
            order = 1,
        },
        applyScope = {
            type = "select",
            name = T("Glow Apply Scope", "글로우 적용 범위"),
            order = 2,
            width = "full",
            values = {
                icon = T("This Icon", "이 아이콘"),
                group = T("This Group", "이 그룹"),
                all = T("All Groups and Specs", "모든 그룹·전문화"),
            },
            get = function()
                return DDingUI._groupIconApplyScope or "icon"
            end,
            set = function(_, value)
                DDingUI._groupIconApplyScope = value
                RefreshStateStudioOptions(groupName, 0)
            end,
        },
        scopeDescription = {
            type = "description",
            name = ScopeDescription(scope),
            order = 3,
        },
        styleHeader = {
            type = "header",
            name = T("Glow Style", "글로우 스타일"),
            order = 10,
        },
    }

    args.glowType = {
        type = "select",
        name = T("Glow Type", "글로우 유형"),
        order = 11,
        width = "full",
        values = {
            button = T("Action Button Glow", "액션 버튼 글로우"),
            pixel = T("Pixel Glow", "픽셀 글로우"),
            autocast = T("Autocast Shine", "자동시전 광택"),
            proc = T("Proc Effect", "발동 효과"),
        },
        get = function()
            local current = GetContext(groupName, false)
            return current and GetResolvedGlowType(current) or "button"
        end,
        set = function(_, value)
            local current = GetContext(groupName, false)
            local changes = {
                {
                    scope = "glow",
                    key = "glowType",
                    value = value == "button" and nil or value,
                    glowStyle = true,
                },
            }
            if current and ReadSetting(current, "glow", "glowType") == "blizzard" then
                changes[#changes + 1] = {
                    scope = "glow",
                    key = "glowColorMode",
                    value = "blizzard",
                    glowStyle = true,
                }
            end
            WriteChanges(groupName, changes)
        end,
    }

    args.glowColorMode = {
        type = "select",
        name = T("Glow Color Mode", "글로우 색상 방식"),
        order = 12,
        width = "full",
        values = {
            default = T("Default", "기본값"),
            blizzard = T("Keep Blizzard Default Glow Color", "블리자드 기본 글로우 색상 유지"),
            class = T("Class Color", "직업 색상"),
            custom = T("Custom", "사용자 지정"),
        },
        get = function()
            local current = GetContext(groupName, false)
            return current and GetResolvedGlowColorMode(current) or "default"
        end,
        set = function(_, value)
            local current = GetContext(groupName, false)
            local changes = {
                {
                    scope = "glow",
                    key = "glowColorMode",
                    value = value == "default" and nil or value,
                    glowStyle = true,
                },
            }
            if current and ReadSetting(current, "glow", "glowType") == "blizzard" then
                changes[#changes + 1] = {
                    scope = "glow",
                    key = "glowType",
                    value = "proc",
                    glowStyle = true,
                }
            end
            WriteChanges(groupName, changes)
        end,
    }

    args.glowColor = MakeColor(
        groupName,
        T("Custom Glow Color", "사용자 글로우 색상"),
        "glow",
        "glowColor",
        13,
        { 1, 0.85, 0.1, 1 },
        true
    )
    args.glowColor.hidden = function()
        local current = GetContext(groupName, false)
        return not current or GetResolvedGlowColorMode(current) ~= "custom"
    end

    args.motionHeader = {
        type = "header",
        name = T("Glow Motion", "글로우 움직임"),
        order = 20,
    }
    args.glowSpeed = MakeRange(
        groupName,
        T("Glow Frequency", "글로우 속도"),
        "glow",
        "glowSpeed",
        21,
        0.25,
        0.05,
        1,
        0.05,
        true
    )
    args.glowSpeed.isPercent = false
    args.glowLines = MakeRange(
        groupName,
        T("Line Amount", "라인 수"),
        "glow",
        "glowLines",
        22,
        8,
        1,
        30,
        1,
        true
    )
    args.glowThickness = MakeRange(
        groupName,
        T("Line Thickness", "라인 두께"),
        "glow",
        "glowThickness",
        23,
        2,
        0.5,
        6,
        0.5,
        true
    )
    local function HidePixelOptions()
        local current = GetContext(groupName, false)
        return not current or GetResolvedGlowType(current) ~= "pixel"
    end
    args.glowLines.hidden = HidePixelOptions
    args.glowThickness.hidden = HidePixelOptions

    args.resetGlowStyle = {
        type = "execute",
        name = T("Reset Glow Style", "글로우 스타일 초기화"),
        order = 29,
        width = "normal",
        func = function()
            local changes = {}
            for _, key in ipairs(GLOW_STYLE_KEYS) do
                changes[#changes + 1] = {
                    scope = "glow",
                    key = key,
                    value = nil,
                    glowStyle = true,
                }
            end
            WriteChanges(groupName, changes)
        end,
    }

    args.stateAppearanceHeader = {
        type = "header",
        name = T("State Appearance", "상태 외형"),
        order = 40,
    }
    args.stateAppearanceDescription = {
        type = "description",
        name = T(
            "These appearance values always apply only to the selected icon.",
            "이 외형 값은 항상 선택한 아이콘에만 적용됩니다."
        ),
        order = 41,
    }

    if context.capabilities.active then
        args.activeSwipeColor = MakeColor(
            groupName,
            T("Active Swipe Color", "활성 스와이프 색상"),
            "visual",
            "activeSwipeColor",
            42,
            { 1, 0.776, 0.376, 0.8 }
        )
        args.activeSwipeColor.hidden = function()
            local current = GetContext(groupName, false)
            return not current or ReadSetting(current, "visual", "activeSwipeMode", "inherit") ~= "custom"
        end
        args.activeBorderColor = MakeColor(
            groupName,
            T("Active Border Color", "활성 테두리 색상"),
            "visual",
            "activeBorderColor",
            43,
            { 1, 0.776, 0.376, 1 }
        )
        args.activeBorderColor.hidden = function()
            local current = GetContext(groupName, false)
            return not current or ReadSetting(current, "visual", "activeBorderEnabled", false) ~= true
        end
    end

    if context.capabilities.cooldown then
        args.cooldownAlpha = MakeRange(
            groupName,
            T("Cooldown Opacity", "재사용 대기 중 투명도"),
            "visual",
            "cooldownStateAlpha",
            44,
            0.35,
            0.05,
            1,
            0.05
        )
        args.cooldownAlpha.hidden = function()
            local current = GetContext(groupName, false)
            return not current or ReadSetting(current, "visual", "cooldownStateEffect") ~= "lowerAlphaOnCD"
        end
    end

    if context.capabilities.inactive then
        args.inactiveAlpha = MakeRange(
            groupName,
            T("Inactive Opacity", "비활성 투명도"),
            "visual",
            "inactiveAlpha",
            45,
            0.5,
            0.05,
            1,
            0.05
        )
    end

    args.resetStateAppearance = {
        type = "execute",
        name = T("Reset State Appearance", "상태 외형 초기화"),
        order = 90,
        width = "normal",
        func = function()
            WriteChanges(groupName, {
                { scope = "visual", key = "activeSwipeColor", value = nil },
                { scope = "visual", key = "activeBorderColor", value = nil },
                { scope = "visual", key = "cooldownStateAlpha", value = nil },
                { scope = "visual", key = "inactiveAlpha", value = nil },
            })
        end,
    }
    return args
end

local function CreateEdges(frame, layer, subLevel)
    subLevel = math.max(-8, math.min(7, tonumber(subLevel) or 0))
    local edges = {}
    for index = 1, 4 do
        edges[index] = frame:CreateTexture(nil, layer, nil, subLevel)
        edges[index]:SetColorTexture(1, 1, 1, 1)
    end
    edges[1]:SetPoint("TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT")
    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT")
    edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT")
    edges[3]:SetPoint("BOTTOMLEFT")
    edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT")
    edges[4]:SetWidth(1)
    return edges
end

local function SetEdges(edges, r, g, b, a, thickness)
    for index, edge in ipairs(edges) do
        edge:SetColorTexture(r, g, b, a)
        if index <= 2 then edge:SetHeight(thickness) else edge:SetWidth(thickness) end
    end
end

local function GetGlowColor(context)
    local mode = ReadSetting(context, "glow", "glowColorMode", "default")
    local color
    if mode == "custom" then
        color = ReadSetting(context, "glow", "glowColor", { r = 1, g = 0.78, b = 0.2, a = 1 })
    elseif mode == "class" then
        local _, class = UnitClass("player")
        color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    elseif mode == "blizzard" then
        color = { r = 1, g = 0.82, b = 0.28, a = 1 }
    end
    color = color or { r = 1, g = 0.42, b = 0.08, a = 1 }
    return color.r or color[1] or 1,
        color.g or color[2] or 0.42,
        color.b or color[3] or 0.08,
        color.a or color[4] or 1
end

local function IsGlowEnabled(context, state)
    if state == "active" and context.kind == "dynamic" and context.capabilities.procActive then
        local mode = ReadSetting(context, "glow", "procGlowMode")
        if mode == "on" then return true end
        if mode == "off" then return false end
        local profile = DDingUI.db and DDingUI.db.profile
        local groups = profile and profile.groupSystem and profile.groupSystem.groups
        local group = groups and groups[context.groupName]
        return not group or group.procGlowEnabled ~= false
    end
    local key = state == "ready" and "cooldownReadyGlow"
        or state == "maxCharges" and "maxChargesGlow"
        or "activeGlow"
    return ReadSetting(context, "glow", key, false) == true
end

local function GetStateSummary(context, state)
    if state == "ready" or state == "active" or state == "maxCharges" then
        return IsGlowEnabled(context, state) and T("Glow On", "Glow On") or T("Glow Off", "Glow Off")
    elseif state == "cooldown" then
        if context.kind == "dynamic" then
            return ReadSetting(context, "visual", "showCooldown", true)
                and T("Swipe Shown", "Swipe Shown") or T("Swipe Hidden", "Swipe Hidden")
        end
        local mode = ReadSetting(context, "visual", "cooldownSwipeMode", "inherit")
        return T("Swipe", "Swipe") .. ": " .. T(mode == "inherit" and "Default" or mode:gsub("^%l", string.upper), mode)
    elseif state == "inactive" then
        local alpha = tonumber(ReadSetting(context, "visual", "inactiveAlpha", 0.5)) or 0.5
        return T("Opacity", "Opacity") .. ": " .. tostring(math.floor(alpha * 100 + 0.5)) .. "%"
    elseif state == "unusable" then
        return ReadSetting(context, "visual", "desaturateWhenUnusable", true)
            and T("Desaturated", "Desaturated") or T("Full Color", "Full Color")
    end
    return ""
end

local function AddStatePreview(iconFrame, context, state, font)
    local icon = iconFrame.icon
    local alpha = 1
    local desaturated = false
    if state == "inactive" then
        alpha = tonumber(ReadSetting(context, "visual", "inactiveAlpha", 0.5)) or 0.5
        desaturated = ReadSetting(context, "visual", "desatInactive", "inherit") ~= "off"
    elseif state == "cooldown" then
        desaturated = context.kind == "dynamic"
            and ReadSetting(context, "visual", "desaturateOnCooldown", true) ~= false
            or ReadSetting(context, "visual", "nonActiveMode") == "desaturate"
        if ReadSetting(context, "visual", "cooldownStateEffect") == "lowerAlphaOnCD" then
            alpha = tonumber(ReadSetting(context, "visual", "cooldownStateAlpha", 0.35)) or 0.35
        end
    elseif state == "unusable" then
        desaturated = ReadSetting(context, "visual", "desaturateWhenUnusable", true) ~= false
    end
    icon:SetDesaturated(desaturated)
    iconFrame:SetAlpha(math.max(0.05, math.min(1, alpha)))

    if state == "cooldown" or state == "active" then
        local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawBling(false)
        cooldown:SetHideCountdownNumbers(true)
        if state == "active" then
            local color = ReadSetting(context, "visual", "activeSwipeColor", { r = 1, g = 0.776, b = 0.376, a = 0.65 })
            cooldown:SetSwipeColor(
                color.r or color[1] or 1,
                color.g or color[2] or 0.776,
                color.b or color[3] or 0.376,
                color.a or color[4] or 0.65
            )
        else
            cooldown:SetSwipeColor(0, 0, 0, 0.72)
        end
        cooldown:SetCooldown(GetTime() - 4, 10)
    end

    if state == "active" then
        local duration = iconFrame:CreateFontString(nil, "OVERLAY", nil, 7)
        duration:SetFont(font, 11, "OUTLINE")
        duration:SetPoint("TOP", iconFrame, "TOP", 0, -2)
        duration:SetText("8.4")
        duration:SetTextColor(1, 1, 1, 1)
        local stacks = iconFrame:CreateFontString(nil, "OVERLAY", nil, 7)
        stacks:SetFont(font, 11, "OUTLINE")
        stacks:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
        stacks:SetText("3")
    elseif state == "maxCharges" then
        local charges = iconFrame:CreateFontString(nil, "OVERLAY", nil, 7)
        charges:SetFont(font, 13, "OUTLINE")
        charges:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
        charges:SetText("2")
        charges:SetTextColor(1, 0.84, 0.16, 1)
    elseif state == "unusable" then
        local tint = iconFrame:CreateTexture(nil, "OVERLAY", nil, 4)
        tint:SetAllPoints()
        tint:SetColorTexture(0.35, 0.02, 0.02, 0.2)
    end

    if state == "active" and ReadSetting(context, "visual", "activeBorderEnabled", false) then
        local border = CreateEdges(iconFrame, "OVERLAY", 6)
        local color = ReadSetting(context, "visual", "activeBorderColor", { r = 1, g = 0.776, b = 0.376, a = 1 })
        SetEdges(
            border,
            color.r or color[1] or 1,
            color.g or color[2] or 0.776,
            color.b or color[3] or 0.376,
            color.a or color[4] or 1,
            2
        )
    end

    if IsGlowEnabled(context, state) then
        local glow = CreateEdges(iconFrame, "OVERLAY", 7)
        local r, g, b, a = GetGlowColor(context)
        SetEdges(glow, r, g, b, a, 3)
    end
end

function DDingUI:BuildGroupStateStudioUI(parent, groupName)
    local context = GetContext(groupName, false)
    if not context then
        parent:SetHeight(1)
        return
    end

    local selectedState = GetSelectedState(groupName, context)
    local font = self.GetGlobalFont and self:GetGlobalFont() or "Fonts\\2002.TTF"
    local width = math.max(280, parent:GetWidth() or 760)
    local margin, gap, cardHeight = 6, 8, 94
    local columns = width >= 620 and 3 or width >= 390 and 2 or 1
    local cardWidth = math.floor((width - margin * 2 - gap * (columns - 1)) / columns)

    for index, definition in ipairs(STATE_ORDER) do
        local row = math.floor((index - 1) / columns)
        local column = (index - 1) % columns
        local supported = context.capabilities[definition.key] == true
        local card = CreateFrame("Button", nil, parent)
        card:SetSize(cardWidth, cardHeight)
        card:SetPoint(
            "TOPLEFT",
            parent,
            "TOPLEFT",
            margin + column * (cardWidth + gap),
            -(margin + row * (cardHeight + gap))
        )
        card:RegisterForClicks("LeftButtonUp")

        local background = card:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(
            THEME.panelRaised[1], THEME.panelRaised[2], THEME.panelRaised[3],
            supported and 1 or 0.5)
        local edges = CreateEdges(card, "BORDER", 1)
        if selectedState == definition.key then
            SetEdges(edges, THEME.accent[1], THEME.accent[2], THEME.accent[3], 1, 2)
        else
            SetEdges(edges, THEME.border[1], THEME.border[2], THEME.border[3], supported and 1 or 0.45, 1)
        end

        local iconFrame = CreateFrame("Frame", nil, card)
        iconFrame:SetSize(54, 54)
        iconFrame:SetPoint("LEFT", card, "LEFT", 12, 0)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(context.opt._gridIconTex or FALLBACK_ICON)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconFrame.icon = icon
        AddStatePreview(iconFrame, context, definition.key, font)

        local label = card:CreateFontString(nil, "OVERLAY")
        label:SetFont(font, 12, "")
        label:SetPoint("TOPLEFT", card, "TOPLEFT", 76, -18)
        label:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetText(T(definition.label, definition.label))
        label:SetTextColor(supported and 0.95 or 0.48, supported and 0.95 or 0.48, supported and 0.95 or 0.48, 1)

        local summary = card:CreateFontString(nil, "OVERLAY")
        summary:SetFont(font, 10, "")
        summary:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
        summary:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        summary:SetJustifyH("LEFT")
        summary:SetText(supported
            and GetStateSummary(context, definition.key)
            or T("Not supported", "Not supported"))
        summary:SetTextColor(0.62, 0.65, 0.72, supported and 1 or 0.55)

        if supported then
            card:SetScript("OnEnter", function()
                background:SetColorTexture(THEME.bgHover[1], THEME.bgHover[2], THEME.bgHover[3], 1)
            end)
            card:SetScript("OnLeave", function()
                background:SetColorTexture(THEME.panelRaised[1], THEME.panelRaised[2], THEME.panelRaised[3], 1)
            end)
            card:SetScript("OnClick", function()
                SetSelectedState(groupName, context, definition.key)
            end)
        else
            card:EnableMouse(false)
        end
    end

    local rows = math.ceil(#STATE_ORDER / columns)
    parent:SetHeight(margin * 2 + cardHeight * rows + gap * math.max(0, rows - 1))
end

DDingUI.GroupStateStudio = {
    GetContext = GetContext,
    ReadSetting = ReadSetting,
    WriteChanges = WriteChanges,
}
