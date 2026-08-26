local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end
local SL = _G.DDingUI_StyleLib

local Engine = {}
DDingUI.TrackedAuraContainer = Engine

local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local EMPTY_COLOR = {}
local RETRY_DELAY = 2
local SPELL_LIST_FIELDS = { "linkedSpellIDs", "trackingSpellIDs", "spellIDs" }

local desiredByTracker = setmetatable({}, { __mode = "k" })
local bindingByTracker = setmetatable({}, { __mode = "k" })
local failureByTracker = setmetatable({}, { __mode = "k" })
local deferredByTracker = setmetatable({}, { __mode = "k" })
local activePresentationByTracker = setmetatable({}, { __mode = "k" })
local deferredDisables = {}
local formatterCache = {}
local suspended = false
local loadWindow = false
local deferredBuildRequested = false
local diagnostics = {
    syncs = 0,
    desiredTrackers = 0,
    buildAttempts = 0,
    buildSuccess = 0,
    buildFailures = 0,
    rebuilds = 0,
    reuses = 0,
    retrySuppressed = 0,
    parked = 0,
    fallbackRequests = 0,
    deferredDisables = 0,
    deferredBuilds = 0,
    totalBuildMs = 0,
    maxBuildMs = 0,
    lastBuildMs = 0,
    lastError = nil,
}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function CleanID(value)
    if IsSecret(value) then return nil end
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return value
end

local function FirstCleanID(primary, fallback)
    return CleanID(primary) or CleanID(fallback)
end

local function AddSpellVariants(include, value)
    local spellID = CleanID(value)
    if not spellID then return end

    include[spellID] = true
    if not C_Spell then return end

    if C_Spell.GetOverrideSpell then
        local overrideID = CleanID(C_Spell.GetOverrideSpell(spellID))
        if overrideID then include[overrideID] = true end
    end
    if C_Spell.GetBaseSpell then
        local baseID = CleanID(C_Spell.GetBaseSpell(spellID))
        if baseID then include[baseID] = true end
    end
end

local function TrackerCooldownID(tracker)
    return tracker and FirstCleanID(
        tracker.cooldownID,
        tracker.trigger and tracker.trigger.cooldownID
    ) or 0
end

local function TrackerSpellID(tracker)
    return tracker and FirstCleanID(
        tracker.spellID,
        tracker.trigger and tracker.trigger.spellID
    ) or 0
end

local function IsSupportedAuraTracker(tracker)
    if type(tracker) ~= "table" or tracker.isGroup or tracker.enabled == false then return false end
    local displayType = tracker.displayType or "bar"
    if displayType ~= "bar" and displayType ~= "ring"
        and displayType ~= "icon" and displayType ~= "text" and displayType ~= "trigger"
    then
        return false
    end
    if displayType == "bar" and ((tracker.settings or {}).barStyle or "bar") ~= "bar" then
        return false
    end
    if displayType == "icon" and (tracker.settings or {}).showOnlyWhenInactive then
        return false
    end
    if tracker.trackingMode == "manual" or tracker.trackingMode == "spell" then return false end
    if tracker.trigger and tracker.trigger.type == "spell" then return false end
    if tracker.isAura == false then return false end
    if displayType == "trigger" then
        return Engine.GetProtectedTriggerPresentation
            and Engine:GetProtectedTriggerPresentation(tracker) ~= nil
            and (TrackerCooldownID(tracker) > 0 or TrackerSpellID(tracker) > 0)
    end
    return TrackerCooldownID(tracker) > 0 or TrackerSpellID(tracker) > 0
end

function Engine:IsSupportedAuraTracker(tracker)
    return IsSupportedAuraTracker(tracker)
end

local function RequiresLegacyObservation(tracker)
    local alerts = tracker and tracker.settings and tracker.settings.alerts
    if not alerts or alerts.enabled ~= true then return false end

    for _, trigger in ipairs(alerts.triggers or {}) do
        local triggerType = type(trigger) == "table" and trigger.type
        if triggerType == "duration" or triggerType == "duration_percent"
            or triggerType == "stacks"
        then
            return true
        end
    end
    return false
end

local function AddInfoSpellIDs(include, info)
    if type(info) ~= "table" or IsSecret(info) then return end

    AddSpellVariants(include, info.spellID)
    AddSpellVariants(include, info.displaySpellID)
    AddSpellVariants(include, info.overrideSpellID)
    AddSpellVariants(include, info.overrideTooltipSpellID)
    AddSpellVariants(include, info.linkedSpellID)

    for _, key in ipairs(SPELL_LIST_FIELDS) do
        local linked = info[key]
        if type(linked) == "table" and not IsSecret(linked) then
            for index = 1, #linked do
                AddSpellVariants(include, linked[index])
            end
        end
    end
end

local function AddCooldownInfo(include, cooldownID, preferredSpellID)
    if cooldownID <= 0 then return end

    local scanner = DDingUI.CDMScanner
    local catalogInfo = scanner and scanner.GetEntry and scanner.GetEntry(cooldownID)
    AddInfoSpellIDs(include, catalogInfo)

    local compat = DDingUI.CDMCompat
    local apiInfo = compat and compat.GetCooldownInfo and compat:GetCooldownInfo(cooldownID)
    AddInfoSpellIDs(include, apiInfo)

    local identity = compat and compat.GetCooldownSpellIdentity
        and compat:GetCooldownSpellIdentity(cooldownID, catalogInfo or apiInfo, preferredSpellID)
    AddInfoSpellIDs(include, identity)
end

local function SortedIDs(include)
    local ids = {}
    for spellID in pairs(include) do
        ids[#ids + 1] = spellID
    end
    table.sort(ids)
    return ids
end

local function BuildSavedSpellSet(tracker)
    if type(tracker) ~= "table" then return nil end

    local include = {}
    local spellID = TrackerSpellID(tracker)
    AddSpellVariants(include, spellID)
    AddInfoSpellIDs(include, tracker)
    if next(include) == nil then return nil end
    return include
end

local function AddResolvedAuraIdentity(include, spellID, cooldownID)
    if cooldownID > 0 then
        AddCooldownInfo(include, cooldownID, spellID)
        return
    end

    local scanner = DDingUI.CDMScanner
    local catalogInfo = scanner and scanner.FindUniqueAuraEntryBySpellID
        and scanner.FindUniqueAuraEntryBySpellID(spellID)
    if not catalogInfo then return end

    AddInfoSpellIDs(include, catalogInfo)
    local resolvedCooldownID = CleanID(catalogInfo.cooldownID) or 0
    AddCooldownInfo(include, resolvedCooldownID, spellID)
end

local function BuildSpellSet(tracker, claimedBySpellID, saved)
    saved = saved or BuildSavedSpellSet(tracker)
    if not saved then return nil end

    local include = {}
    for spellID in pairs(saved) do
        include[spellID] = true
    end

    local extra = {}
    local cooldownID = TrackerCooldownID(tracker)
    local spellID = TrackerSpellID(tracker)
    AddResolvedAuraIdentity(extra, spellID, cooldownID)
    for extraSpellID in pairs(extra) do
        local owner = claimedBySpellID and claimedBySpellID[extraSpellID]
        if owner == nil or owner == tracker then
            include[extraSpellID] = true
        end
    end
    return include
end

local function ClampInteger(value, minimum, maximum, fallback)
    value = tonumber(value) or fallback
    value = math.floor(value + 0.5)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function BuildDesired(tracker, claimedBySpellID, saved)
    if not IsSupportedAuraTracker(tracker) then return nil end

    local include = BuildSpellSet(tracker, claimedBySpellID, saved)
    if not include then return nil end

    local ids = SortedIDs(include)
    if #ids == 0 then return nil end

    local settings = tracker.settings or {}
    local maxApplications = ClampInteger(settings.maxStacks, 1, 1000, 1)
    local durationDecimals = ClampInteger(settings.durationDecimals, 0, 2, 1)
    local protectedTrigger = tracker.displayType == "trigger"
        and Engine.GetProtectedTriggerPresentation
        and Engine:GetProtectedTriggerPresentation(tracker) or nil
    return {
        include = include,
        maxApplications = maxApplications,
        durationDecimals = durationDecimals,
        triggerTargetKey = protectedTrigger and protectedTrigger.targetKey or nil,
        signature = table.concat(ids, ",") .. ":" .. maxApplications .. ":" .. durationDecimals
            .. ":" .. (tracker.displayType or "bar")
            .. ":" .. (protectedTrigger and protectedTrigger.signature or ""),
    }
end

function Engine:GetTrackedSpellIDs(tracker)
    local include = BuildSpellSet(tracker)
    return include and SortedIDs(include) or nil
end

local function GetFormatter(decimals)
    local cached = formatterCache[decimals]
    if cached ~= nil then return cached or nil end
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum and Enum.NumericRuleFormatRounding)
    then
        formatterCache[decimals] = false
        return nil
    end

    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local scale = 10 ^ decimals
    local options = {
        threshold = 0,
        format = decimals > 0 and ("%." .. decimals .. "f") or "%d",
        step = 1 / scale,
        rounding = Enum.NumericRuleFormatRounding.Nearest,
    }
    local ok = pcall(formatter.SetBreakpoints, formatter, { options })
    formatterCache[decimals] = ok and formatter or false
    return ok and formatter or nil
end

local function EnsureContainerAPI()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn) then return false end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        local ok = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        if not ok then return false end
    end
    return C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") == true
end

local function CanMutateBindings()
    if loadWindow then return true end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or IsSecret(restricted) or restricted == true then return false end
    end
    return true
end

local function ColorPart(color)
    color = color or {}
    local gradient = color.gradientColor or EMPTY_COLOR
    return table.concat({
        tostring(color[1] or 1),
        tostring(color[2] or 1),
        tostring(color[3] or 1),
        tostring(color[4] or 1),
        tostring(color.gradientMode or "SOLID"),
        tostring(color.gradientOrientation or "HORIZONTAL"),
        tostring(gradient[1] or 1),
        tostring(gradient[2] or 1),
        tostring(gradient[3] or 1),
        tostring(gradient[4] or 1),
    }, ",")
end

local function StyleSignature(style)
    return table.concat({
        tostring(style.displayType),
        tostring(style.mode),
        tostring(style.texture),
        ColorPart(style.barColor),
        ColorPart(style.bgColor),
        ColorPart(style.borderColor),
        tostring(style.borderSize or 0),
        tostring(style.geometryWidth),
        tostring(style.geometryHeight),
        tostring(style.orientation),
        tostring(style.reverseFill),
        tostring(style.showTicks),
        tostring(style.tickWidth),
        type(style.tickPositions) == "table" and table.concat(style.tickPositions, ",") or "",
        tostring(style.showStacksText),
        tostring(style.showDurationText),
        tostring(style.stacksFont),
        tostring(style.stacksFontSize),
        tostring(style.stacksOutline),
        tostring(style.stacksAlign),
        tostring(style.stacksJustify),
        tostring(style.stacksX),
        tostring(style.stacksY),
        ColorPart(style.stacksColor),
        tostring(style.durationFont),
        tostring(style.durationFontSize),
        tostring(style.durationOutline),
        tostring(style.durationAlign),
        tostring(style.durationX),
        tostring(style.durationY),
        ColorPart(style.durationColor),
        tostring(style.frameStrata),
        tostring(style.frameLevel),
        tostring(style.iconZoom),
        tostring(style.iconTexture),
        tostring(style.useAuraIcon),
        tostring(style.iconDesaturate),
        ColorPart(style.iconTint),
        tostring(style.iconAnimation),
        ColorPart(style.glowColor),
        tostring(style.glowLines),
        tostring(style.glowFrequency),
        tostring(style.glowThickness),
        tostring(style.glowXOffset),
        tostring(style.glowYOffset),
        tostring(style.glowWhenInactive),
        tostring(style.swipeTexture),
        tostring(style.ringMaskTexture),
        ColorPart(style.ringBgColor),
        ColorPart(style.swipeColor),
        tostring(style.swipeReverse),
        tostring(style.textDisplayMode),
        tostring(style.staticText),
        tostring(style.showIcon),
        tostring(style.iconSize),
        tostring(style.preserveInactive),
        tostring(style.protectedTriggerSignature),
    }, "|")
end

local function ApplyColor(region, color)
    region:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local function ConfigureRingCooldown(cooldown, owner, maskTexture)
    if not cooldown or not owner or not maskTexture then return end

    if cooldown._ddingRingSwipeTexture ~= maskTexture then
        cooldown:SetSwipeTexture(maskTexture, 1, 1, 1, 1)
        cooldown._ddingRingSwipeTexture = maskTexture
    end
    if cooldown.SetUseCircularEdge then
        cooldown:SetUseCircularEdge(true)
    end
end

function Engine:ConfigureRingCooldown(cooldown, owner, maskTexture)
    ConfigureRingCooldown(cooldown, owner, maskTexture)
end

function Engine:ClearRingCooldownMask(cooldown)
    if not cooldown then return end
    if cooldown._ddingRingSwipeTexture then
        cooldown:SetSwipeTexture(SOLID_TEXTURE, 1, 1, 1, 1)
        cooldown._ddingRingSwipeTexture = nil
    end
    if cooldown.SetUseCircularEdge then
        cooldown:SetUseCircularEdge(false)
    end
end

local function CreateBorder(button, size, color)
    size = tonumber(size) or 0
    if size <= 0 then return end

    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:SetFrameLevel(button:GetFrameLevel() + 3)
    host:EnableMouse(false)

    local top = host:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    top:SetPoint("TOPLEFT", host, "TOPLEFT", -size, size)
    top:SetPoint("TOPRIGHT", host, "TOPRIGHT", size, size)
    top:SetHeight(size)

    local bottom = host:CreateTexture(nil, "OVERLAY")
    bottom:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -size, -size)
    bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", size, -size)
    bottom:SetHeight(size)

    local left = host:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    left:SetPoint("TOPLEFT", host, "TOPLEFT", -size, 0)
    left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -size, 0)
    left:SetWidth(size)

    local right = host:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    right:SetPoint("TOPRIGHT", host, "TOPRIGHT", size, 0)
    right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", size, 0)
    right:SetWidth(size)
end

local function CreateBoundText(button, style, prefix)
    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:SetFrameLevel(button:GetFrameLevel() + 4)
    host:EnableMouse(false)

    local fontString = host:CreateFontString(nil, "OVERLAY")
    local font = style[prefix .. "Font"] or DEFAULT_FONT
    local size = math.max(1, tonumber(style[prefix .. "FontSize"]) or 12)
    local align = style[prefix .. "Align"] or "CENTER"
    local justify = style[prefix .. "Justify"] or align
    local outline = style[prefix .. "Outline"]
    if outline == nil then outline = "OUTLINE" end
    local color = style[prefix .. "Color"] or { 1, 1, 1, 1 }
    fontString:SetFont(font, size, outline)
    fontString:SetShadowOffset(0, 0)
    fontString:SetJustifyH(justify)
    fontString:SetPoint(
        align,
        button,
        align,
        tonumber(style[prefix .. "X"]) or 0,
        tonumber(style[prefix .. "Y"]) or 0
    )
    fontString:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    return fontString
end

local function RegisterDurationText(button, fontString, decimals)
    local formatter = GetFormatter(decimals)
    local options = formatter and { textFormatter = formatter } or {}
    if pcall(button.SetDurationText, button, fontString, options) then return true end
    return pcall(button.SetDurationText, button, fontString, {})
end

local function InitializeButton(button, proxy, style)
    button:SetAllPoints(proxy)
    button:SetFrameLevel((style.frameLevel or 1) + 1)
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
end

local StartContainerGlow

local function CreateBarTicks(button, desired, style)
    local positions = style.tickPositions
    local maximum = tonumber(desired.maxApplications) or 1
    local count
    if style.mode == "duration" then
        count = type(positions) == "table" and #positions or 0
    elseif style.showTicks ~= false and maximum > 1 then
        count = maximum - 1
    else
        return
    end
    if count <= 0 then return end

    local width = tonumber(style.geometryWidth) or 0
    local height = tonumber(style.geometryHeight) or 0
    if width <= 0 or height <= 0 then return end

    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:SetFrameLevel(button:GetFrameLevel() + 2)
    host:EnableMouse(false)

    local tickWidth = math.max(1, tonumber(style.tickWidth) or 1)
    local vertical = style.orientation == "VERTICAL"
    for index = 1, count do
        local position = style.mode == "duration" and tonumber(positions[index]) or (index / maximum)
        if position and position > 0 and position < 1 then
            local tick = host:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(0, 0, 0, 1)
            if vertical then
                tick:SetPoint("BOTTOM", host, "BOTTOM", 0, position * height)
                tick:SetSize(width, tickWidth)
            else
                tick:SetPoint("LEFT", host, "LEFT", position * width, 0)
                tick:SetSize(tickWidth, height)
            end
        end
    end
end

local function CreateBarInitializer(proxy, desired, style)
    return function(button)
        InitializeButton(button, proxy, style)

        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(button)
        local bgColor = style.bgColor or { 0.15, 0.15, 0.15, 1 }
        background:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] or 1)

        local progress = CreateFrame("StatusBar", nil, button)
        progress:SetAllPoints(button)
        progress:SetFrameLevel(button:GetFrameLevel() + 1)
        progress:SetStatusBarTexture(style.texture or SOLID_TEXTURE)
        progress:SetOrientation(style.orientation or "HORIZONTAL")
        progress:SetReverseFill(style.reverseFill == true)
        if SL and SL.ApplyBarColor then
            SL.ApplyBarColor(progress, style.barColor or { 1, 0.8, 0, 1 })
        else
            ApplyColor(progress:GetStatusBarTexture(), style.barColor or { 1, 0.8, 0, 1 })
        end

        local immediate = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
        if style.mode == "stacks" then
            button:SetApplicationBar(progress, {
                maxApplications = desired.maxApplications,
                interpolation = immediate,
            })
        else
            local remaining = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
            button:SetDurationBar(progress, {
                interpolation = immediate,
                direction = remaining,
            })
        end
        CreateBarTicks(button, desired, style)

        if style.showStacksText then
            local applications = CreateBoundText(button, style, "stacks")
            local formatter = GetFormatter(0)
            pcall(button.SetApplicationCount, button, applications, formatter and { formatter = formatter } or {})
        end
        if style.showDurationText then
            RegisterDurationText(button, CreateBoundText(button, style, "duration"), desired.durationDecimals)
        end

        CreateBorder(button, style.borderSize, style.borderColor or { 0, 0, 0, 1 })
        StartContainerGlow(button, style)
    end
end

StartContainerGlow = function(button, style)
    local visuals = DDingUI.RestrictedAuraVisuals
    if visuals and visuals.ApplyGlow then
        visuals:ApplyGlow(button, style)
    end
end

local function CreateIconInitializer(proxy, desired, style)
    return function(button)
        InitializeButton(button, proxy, style)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        local zoom = tonumber(style.iconZoom) or 0
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        if style.useAuraIcon == false and style.iconTexture then
            icon:SetTexture(style.iconTexture)
        else
            button:SetIcon(icon)
        end
        icon:SetDesaturated(style.iconDesaturate == true)
        ApplyColor(icon, style.iconTint or { 1, 1, 1, 1 })

        local swipe = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        swipe:SetAllPoints(button)
        swipe:SetDrawEdge(false)
        swipe:SetDrawBling(false)
        swipe:SetDrawSwipe(true)
        swipe:SetReverse(style.swipeReverse ~= false)
        local swipeColor = style.swipeColor or { 0, 0, 0, 0.7 }
        swipe:SetSwipeTexture(style.swipeTexture or SOLID_TEXTURE, 1, 1, 1, 1)
        swipe:SetSwipeColor(swipeColor[1] or 0, swipeColor[2] or 0, swipeColor[3] or 0, swipeColor[4] or 0.7)
        swipe:SetHideCountdownNumbers(style.showDurationText == true)
        swipe:Show()
        button:SetDurationCooldown(swipe)

        if style.showStacksText then
            local applications = CreateBoundText(button, style, "stacks")
            local formatter = GetFormatter(0)
            button:SetApplicationCount(applications, formatter and { formatter = formatter } or {})
        end
        if style.showDurationText then
            RegisterDurationText(button, CreateBoundText(button, style, "duration"), desired.durationDecimals)
        end
        CreateBorder(button, style.borderSize, style.borderColor or { 0, 0, 0, 1 })
        StartContainerGlow(button, style)
    end
end

local function CreateRingInitializer(proxy, desired, style)
    return function(button)
        InitializeButton(button, proxy, style)

        if style.ringMaskTexture then
            local background = button:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints(button)
            background:SetTexture(style.ringMaskTexture)
            ApplyColor(background, style.ringBgColor or { 0.15, 0.15, 0.15, 1 })

            local borderSize = tonumber(style.borderSize) or 0
            if borderSize > 0 then
                local border = button:CreateTexture(nil, "BACKGROUND", nil, -1)
                border:SetPoint("TOPLEFT", button, "TOPLEFT", -borderSize, borderSize)
                border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", borderSize, -borderSize)
                border:SetTexture(style.ringMaskTexture)
                ApplyColor(border, style.borderColor or { 0, 0, 0, 1 })
            end
        end

        local swipe = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        swipe:SetAllPoints(button)
        swipe:SetDrawEdge(false)
        swipe:SetDrawBling(false)
        swipe:SetDrawSwipe(true)
        swipe:SetReverse(style.swipeReverse ~= false)
        local swipeColor = style.swipeColor or { 1, 0.8, 0, 1 }
        if style.ringMaskTexture then
            ConfigureRingCooldown(swipe, button, style.ringMaskTexture)
        else
            swipe:SetSwipeTexture(SOLID_TEXTURE, 1, 1, 1, 1)
        end
        swipe:SetSwipeColor(swipeColor[1] or 1, swipeColor[2] or 0.8, swipeColor[3] or 0, swipeColor[4] or 1)
        swipe:SetHideCountdownNumbers(true)
        swipe:Show()
        button:SetDurationCooldown(swipe)

        if style.showDurationText then
            RegisterDurationText(button, CreateBoundText(button, style, "duration"), desired.durationDecimals)
        end
        StartContainerGlow(button, style)
    end
end

local function CreateTextInitializer(proxy, desired, style)
    return function(button)
        InitializeButton(button, proxy, style)

        if style.showIcon then
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("LEFT", button, "LEFT", 0, 0)
            icon:SetSize(style.iconSize or 20, style.iconSize or 20)
            button:SetIcon(icon)
        end

        local text = CreateBoundText(button, style, "stacks")
        if style.textDisplayMode == "duration" then
            RegisterDurationText(button, text, desired.durationDecimals)
        elseif style.textDisplayMode == "stacks" then
            local formatter = GetFormatter(0)
            button:SetApplicationCount(text, formatter and { formatter = formatter } or {})
        else
            text:SetText(style.staticText or "")
        end
        if style.showDurationText and style.textDisplayMode ~= "duration" then
            RegisterDurationText(button, CreateBoundText(button, style, "duration"), desired.durationDecimals)
        end
        local visuals = DDingUI.RestrictedAuraVisuals
        if visuals and visuals.ApplyTextMotion then
            visuals:ApplyTextMotion(button, style.iconAnimation)
        end
        StartContainerGlow(button, style)
    end
end

local function CreateTriggerInitializer(proxy, tracker, style)
    return function(button)
        InitializeButton(button, proxy, style)
        button:SetFrameLevel(proxy:GetFrameLevel() + 1)
        if not Engine.InitializeProtectedTriggerButton
            or not Engine:InitializeProtectedTriggerButton(button, tracker)
        then
            error("protected trigger initialization failed")
        end
    end
end

local function CreateInitializer(proxy, desired, style, tracker)
    if style.displayType == "icon" then
        return CreateIconInitializer(proxy, desired, style)
    elseif style.displayType == "ring" then
        return CreateRingInitializer(proxy, desired, style)
    elseif style.displayType == "text" then
        return CreateTextInitializer(proxy, desired, style)
    elseif style.displayType == "trigger" then
        return CreateTriggerInitializer(proxy, tracker, style)
    end
    return CreateBarInitializer(proxy, desired, style)
end

local function PositionProxy(proxy, container, bar, style, targetFrame, reparent)
    if not proxy then return end

    local parent = targetFrame or UIParent
    if reparent and proxy:GetParent() ~= parent then
        proxy:SetParent(parent)
    end

    proxy:ClearAllPoints()
    if targetFrame then
        proxy:SetFrameStrata(targetFrame:GetFrameStrata() or style.frameStrata or "MEDIUM")
        proxy:SetFrameLevel((targetFrame:GetFrameLevel() or 1) + 10)
        proxy:SetAllPoints(targetFrame)
        if container then
            container:SetFrameLevel(proxy:GetFrameLevel() + 1)
        end
    else
        proxy:SetFrameStrata(style.frameStrata or "MEDIUM")
        proxy:SetFrameLevel(style.frameLevel or 1)
        local width = tonumber(style.geometryWidth)
        local height = tonumber(style.geometryHeight)
        if (not width or width <= 0) and bar and bar.GetWidth then
            width = bar:GetWidth()
        end
        if (not height or height <= 0) and bar and bar.GetHeight then
            height = bar:GetHeight()
        end
        if width and width > 0 and height and height > 0 then
            proxy:SetPoint("CENTER", bar, "CENTER")
            proxy:SetSize(width, height)
        else
            proxy:SetAllPoints(bar)
        end
    end
end

local function BuildBinding(bar, desired, style, styleSignature, tracker)
    if not EnsureContainerAPI() then error("AuraContainer API unavailable") end

    local targetFrame
    if style.displayType == "trigger" then
        local visuals = DDingUI.BuffTrackerConditionalVisuals
        targetFrame = visuals and visuals.ResolveTargetFrame
            and visuals:ResolveTargetFrame(desired.triggerTargetKey)
        if not targetFrame then error("protected trigger target unavailable") end
    end

    -- Build the engine-owned subtree under UIParent first. Once the slot is
    -- registered, the addon-owned proxy can safely follow its target icon.
    local proxy = CreateFrame("Frame", nil, UIParent)
    PositionProxy(proxy, nil, bar, style, targetFrame, false)
    proxy:EnableMouse(false)
    proxy:Hide()

    local container = CreateFrame("AuraContainer", nil, proxy, "CustomAuraContainerTemplate")
    if targetFrame then container:SetFrameLevel(proxy:GetFrameLevel() + 1) end
    container:Hide()
    container:SetPoint("CENTER", proxy, "CENTER")
    container:SetSize(1, 1)
    container:AddAuraSlot("tracked", "HELPFUL", {
        candidateFilters = { includeSpellIDs = desired.include },
        initializeFrame = CreateInitializer(proxy, desired, style, tracker),
    })
    container:SetUnit("player")
    if container.SetEnabled then container:SetEnabled(true) end
    container:Show()
    container:UpdateAllAuras()
    PositionProxy(proxy, container, bar, style, targetFrame, true)
    proxy:SetShown(style.presentationVisible ~= false)

    return {
        proxy = proxy,
        container = container,
        bar = bar,
        desiredSignature = desired.signature,
        styleSignature = styleSignature,
        displayType = style.displayType,
        tracker = tracker,
        targetFrame = targetFrame,
        active = true,
        presentationVisible = style.presentationVisible ~= false,
    }
end

local function RestoreLegacyDisplay(host)
    if not host then return end
    host._auraContainerOwnsDisplay = nil
    host._auraContainerBinding = nil
    if host.StatusBar then host.StatusBar:SetAlpha(1) end
    if host.Background then host.Background:SetAlpha(1) end
    if host.Border then host.Border:SetAlpha(1) end
    if host.TickFrame then host.TickFrame:SetAlpha(1) end
    if host.TextValue then host.TextValue:SetAlpha(1) end
    if host.DurationText then host.DurationText:SetAlpha(1) end
    if host.Cooldown then host.Cooldown:SetAlpha(1) end
    if host.StackText then host.StackText:SetAlpha(1) end
    if host.Glow then host.Glow:SetAlpha(1) end
    if host.Text then host.Text:SetAlpha(1) end
    if host.Texture then host.Texture:SetAlpha(1) end
    if host.Icon then host.Icon:SetAlpha(1) end
    if host._ringColorBg then host._ringColorBg:SetAlpha(1) end
    if host.RingBackground then host.RingBackground:SetAlpha(1) end
    if host.RingProgress then host.RingProgress:SetAlpha(1) end
    if host.RingBorder then host.RingBorder:SetAlpha(1) end
end

local function HideLegacyDisplay(host, style)
    if not host then return end
    local displayType = type(style) == "table" and style.displayType or style
    host._auraContainerOwnsDisplay = true
    if displayType == "bar" or displayType == nil then
        if host.StatusBar then host.StatusBar:SetAlpha(0) end
        if host.Background then host.Background:SetAlpha(0) end
        if host.Border then host.Border:SetAlpha(0) end
        if host.TickFrame then host.TickFrame:SetAlpha(0) end
        if host.TextValue then host.TextValue:SetAlpha(0) end
        if host.DurationText then host.DurationText:SetAlpha(0) end
    elseif displayType == "ring" then
        if host.Cooldown then host.Cooldown:SetAlpha(0) end
        if host.TextValue then host.TextValue:SetAlpha(0) end
        if host.DurationText then host.DurationText:SetAlpha(0) end
        if type(style) == "table" and not style.preserveInactive then
            if host._ringColorBg then host._ringColorBg:SetAlpha(0) end
            if host.RingBackground then host.RingBackground:SetAlpha(0) end
            if host.RingProgress then host.RingProgress:SetAlpha(0) end
            if host.RingBorder then host.RingBorder:SetAlpha(0) end
        end
    elseif displayType == "icon" then
        if host.Cooldown then host.Cooldown:SetAlpha(0) end
        if host.StackText then host.StackText:SetAlpha(0) end
        if host.DurationText then host.DurationText:SetAlpha(0) end
        if type(style) == "table" and not style.preserveInactive then
            if host.Texture then host.Texture:SetAlpha(0) end
            if host.Border then host.Border:SetAlpha(0) end
            if host.Glow then host.Glow:SetAlpha(0) end
        end
    elseif displayType == "text" then
        if host.Text then host.Text:SetAlpha(0) end
        if host.DurationText then host.DurationText:SetAlpha(0) end
        if type(style) == "table" and not style.preserveInactive and host.Icon then
            host.Icon:SetAlpha(0)
        end
    end
end

local lifecycleFrame = CreateFrame("Frame")
local lifecycleTicker
local FlushDeferredBindings

local function RegisterLifecycleRetry()
    lifecycleFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    lifecycleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    lifecycleFrame:RegisterEvent("ENCOUNTER_END")
    lifecycleFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    if not lifecycleTicker and C_Timer and C_Timer.NewTicker then
        lifecycleTicker = C_Timer.NewTicker(1, function()
            FlushDeferredBindings()
        end)
    end
end

local function SetBindingEnabled(binding, enabled)
    local container = binding and binding.container
    if not container or not CanMutateBindings() then return false end

    local ok = true
    if type(container.SetEnabled) == "function" then
        ok = pcall(container.SetEnabled, container, enabled)
    end
    if ok then
        local visibilityMethod = enabled and container.Show or container.Hide
        if type(visibilityMethod) == "function" then
            ok = pcall(visibilityMethod, container)
        end
    end
    return ok
end

FlushDeferredBindings = function()
    if not CanMutateBindings() then return end
    for binding in pairs(deferredDisables) do
        if binding.active ~= true then
            if SetBindingEnabled(binding, false) then
                deferredDisables[binding] = nil
            end
        else
            deferredDisables[binding] = nil
        end
    end
    if deferredBuildRequested then
        deferredBuildRequested = false
        local resourceBars = DDingUI.ResourceBars
        if resourceBars and resourceBars.RequestBuffTrackerUpdate then
            resourceBars:RequestBuffTrackerUpdate("aura-container-ready", 0)
        end
    end
    if not deferredBuildRequested and next(deferredDisables) == nil then
        lifecycleFrame:UnregisterAllEvents()
        if lifecycleTicker then
            lifecycleTicker:Cancel()
            lifecycleTicker = nil
        end
    end
end

lifecycleFrame:SetScript("OnEvent", FlushDeferredBindings)

local function ActivateBinding(binding)
    if not binding then return false end
    if binding.active == true then
        deferredDisables[binding] = nil
        if binding.proxy then binding.proxy:SetShown(binding.presentationVisible ~= false) end
        return true
    end
    if deferredDisables[binding] then
        deferredDisables[binding] = nil
        binding.active = true
        if binding.proxy then binding.proxy:SetShown(binding.presentationVisible ~= false) end
        return true
    end

    local enabled = SetBindingEnabled(binding, true)
    if not enabled then
        RegisterLifecycleRetry()
        return false
    end
    binding.active = true
    if binding.proxy then binding.proxy:SetShown(binding.presentationVisible ~= false) end
    if enabled and binding.container and binding.container.UpdateAllAuras then
        pcall(binding.container.UpdateAllAuras, binding.container)
    end
    return enabled
end

local function ParkBinding(binding)
    if not binding then return end
    if binding.active == false then
        if binding.proxy then binding.proxy:Hide() end
        RestoreLegacyDisplay(binding.bar)
        return
    end
    binding.active = false
    if binding.proxy then binding.proxy:Hide() end
    if not SetBindingEnabled(binding, false) then
        deferredDisables[binding] = true
        diagnostics.deferredDisables = diagnostics.deferredDisables + 1
        RegisterLifecycleRetry()
    end
    RestoreLegacyDisplay(binding.bar)
    diagnostics.parked = diagnostics.parked + 1
end

function Engine:Sync(trackers)
    diagnostics.syncs = diagnostics.syncs + 1
    suspended = false
    local retained = {}
    local desiredCount = 0
    local savedByTracker = {}
    local claimedBySpellID = {}

    for _, tracker in ipairs(trackers or {}) do
        if IsSupportedAuraTracker(tracker) then
            local saved = BuildSavedSpellSet(tracker)
            savedByTracker[tracker] = saved
            for spellID in pairs(saved or {}) do
                if claimedBySpellID[spellID] == nil then
                    claimedBySpellID[spellID] = tracker
                end
            end
        end
    end

    for _, tracker in ipairs(trackers or {}) do
        local desired = BuildDesired(tracker, claimedBySpellID, savedByTracker[tracker])
        desiredByTracker[tracker] = desired
        if desired then
            retained[tracker] = true
            desiredCount = desiredCount + 1
        end
    end
    diagnostics.desiredTrackers = desiredCount

    for tracker, binding in pairs(bindingByTracker) do
        if not retained[tracker] then
            ParkBinding(binding)
            bindingByTracker[tracker] = nil
            desiredByTracker[tracker] = nil
            failureByTracker[tracker] = nil
            deferredByTracker[tracker] = nil
        end
    end
end

function Engine:BeginLoadWindow()
    loadWindow = true
    deferredBuildRequested = false
end

function Engine:EndLoadWindow()
    loadWindow = false
end

function Engine:IsLoadWindow()
    return loadWindow
end

local function ApplyGlowStyle(style, source, animationKey, colorKey, prefix)
    prefix = prefix or "glow"
    style.iconAnimation = source[animationKey] or source.glowType or "none"
    style.glowColor = source[colorKey] or source.glowColor or { 1, 0.9, 0.5, 1 }
    style.glowLines = source[prefix .. "Lines"] or source.glowLines or 8
    style.glowFrequency = source[prefix .. "Frequency"] or source.glowFrequency or 0.25
    style.glowThickness = source[prefix .. "Thickness"] or source.glowThickness or 2
    style.glowXOffset = source[prefix .. "XOffset"] or source.glowXOffset or 0
    style.glowYOffset = source[prefix .. "YOffset"] or source.glowYOffset or 0
end

function Engine:SetActivePresentationOverride(tracker, presentation)
    if tracker then activePresentationByTracker[tracker] = presentation end
end

function Engine:ClearActivePresentationOverride(tracker)
    if tracker then activePresentationByTracker[tracker] = nil end
end

function Engine:Attach(tracker, bar, style)
    local desired = tracker and desiredByTracker[tracker]
    if suspended or not desired or not bar or type(style) ~= "table" then
        self:Detach(tracker, bar)
        return false
    end

    local settings = tracker.settings or {}
    local protectedTrigger
    if style.displayType == "trigger" then
        protectedTrigger = self.GetProtectedTriggerPresentation
            and self:GetProtectedTriggerPresentation(tracker) or nil
        if not protectedTrigger then
            self:Detach(tracker, bar)
            return false
        end
        style.protectedTriggerSignature = protectedTrigger.signature
    end
    local presentation = activePresentationByTracker[tracker]
    if presentation and presentation.selfColor then
        if style.displayType == "bar" then
            style.barColor = presentation.selfColor
        elseif style.displayType == "ring" then
            style.swipeColor = presentation.selfColor
        elseif style.displayType == "icon" then
            style.borderColor = presentation.selfColor
        elseif style.displayType == "text" then
            style.stacksColor = presentation.selfColor
        end
    end
    if presentation and presentation.iconColor and style.displayType == "icon" then
        style.iconTint = presentation.iconColor
    end
    if presentation and presentation.borderColor then
        style.borderColor = presentation.borderColor
    end
    if presentation and presentation.desaturate and style.displayType == "icon" then
        style.iconDesaturate = true
    end
    if presentation and presentation.glow then
        ApplyGlowStyle(style, presentation.glow, "glowType", "glowColor")
        style.glowWhenInactive = false
    elseif style.displayType == "icon" then
        ApplyGlowStyle(style, settings, "iconAnimation", "glowColor")
        style.glowWhenInactive = settings.glowWhenInactive == true
    elseif style.displayType == "text" then
        ApplyGlowStyle(style, settings, "textAnimation", "textGlowColor", "textGlow")
        style.glowWhenInactive = false
    end
    local signature = StyleSignature(style)
    local binding = bindingByTracker[tracker]
    local triggerTargetFrame
    if protectedTrigger then
        local visuals = DDingUI.BuffTrackerConditionalVisuals
        triggerTargetFrame = visuals and visuals.ResolveTargetFrame
            and visuals:ResolveTargetFrame(protectedTrigger.targetKey)
    end
    local bindingMatches = binding
        and binding.desiredSignature == desired.signature
        and binding.styleSignature == signature
        and (not protectedTrigger or binding.targetFrame == triggerTargetFrame)
    if bindingMatches then
        diagnostics.reuses = diagnostics.reuses + 1
        if binding.bar ~= bar then
            RestoreLegacyDisplay(binding.bar)
            binding.bar = bar
        end
        PositionProxy(binding.proxy, binding.container, bar, style, binding.targetFrame, true)
        binding.presentationVisible = style.presentationVisible ~= false
        if not ActivateBinding(binding) then
            RestoreLegacyDisplay(bar)
            return false
        end
        HideLegacyDisplay(bar, style)
        bar._auraContainerBinding = binding
        deferredByTracker[tracker] = nil
        return true
    end

    local failure = failureByTracker[tracker]
    local buildSignature = desired.signature .. "|" .. signature
    local now = GetTime()
    if failure and failure.signature == buildSignature and now - failure.time < RETRY_DELAY then
        diagnostics.retrySuppressed = diagnostics.retrySuppressed + 1
        ParkBinding(binding)
        RestoreLegacyDisplay(bar)
        return false
    end

    if not CanMutateBindings() then
        deferredByTracker[tracker] = true
        if not deferredBuildRequested then
            deferredBuildRequested = true
            diagnostics.deferredBuilds = diagnostics.deferredBuilds + 1
        end
        RegisterLifecycleRetry()
        if bindingMatches then
            if binding.bar ~= bar then
                RestoreLegacyDisplay(binding.bar)
                binding.bar = bar
            end
            PositionProxy(binding.proxy, binding.container, bar, style, binding.targetFrame, true)
            binding.presentationVisible = style.presentationVisible ~= false
            if ActivateBinding(binding) then
                HideLegacyDisplay(bar, style)
                bar._auraContainerBinding = binding
                return true
            end
        end
        ParkBinding(binding)
        RestoreLegacyDisplay(bar)
        return false
    end
    diagnostics.buildAttempts = diagnostics.buildAttempts + 1
    if binding then diagnostics.rebuilds = diagnostics.rebuilds + 1 end
    local started = debugprofilestop and debugprofilestop() or nil
    local ok, replacement = pcall(BuildBinding, bar, desired, style, signature, tracker)
    local elapsed = started and (debugprofilestop() - started) or 0
    diagnostics.lastBuildMs = elapsed
    diagnostics.totalBuildMs = diagnostics.totalBuildMs + elapsed
    diagnostics.maxBuildMs = math.max(diagnostics.maxBuildMs, elapsed)
    if not ok then
        deferredByTracker[tracker] = nil
        diagnostics.buildFailures = diagnostics.buildFailures + 1
        diagnostics.lastError = tostring(replacement)
        local failureAttempts = failure and failure.signature == buildSignature
            and ((failure.attempts or 0) + 1) or 1
        failureByTracker[tracker] = {
            signature = buildSignature,
            time = now,
            attempts = failureAttempts,
        }
        ParkBinding(binding)
        RestoreLegacyDisplay(bar)
        local resourceBars = DDingUI.ResourceBars
        if resourceBars and resourceBars.RequestBuffTrackerUpdate then
            diagnostics.fallbackRequests = diagnostics.fallbackRequests + 1
            resourceBars:RequestBuffTrackerUpdate("aura-container-fallback", 0)
            if failureAttempts <= 3 and C_Timer and C_Timer.After then
                C_Timer.After(RETRY_DELAY, function()
                    local currentFailure = failureByTracker[tracker]
                    if currentFailure and currentFailure.signature == buildSignature
                        and currentFailure.time == now
                    then
                        resourceBars:RequestBuffTrackerUpdate("aura-container-retry", 0)
                    end
                end)
            end
        end
        return false
    end

    diagnostics.buildSuccess = diagnostics.buildSuccess + 1
    diagnostics.lastError = nil
    ParkBinding(binding)
    bindingByTracker[tracker] = replacement
    failureByTracker[tracker] = nil
    deferredByTracker[tracker] = nil
    HideLegacyDisplay(bar, style)
    bar._auraContainerBinding = replacement
    return true
end

function Engine:ShouldReadLegacy(tracker)
    if suspended or not tracker or not desiredByTracker[tracker] then
        return true
    end
    if RequiresLegacyObservation(tracker) then return true end

    if bindingByTracker[tracker] then
        return false
    end

    local failure = failureByTracker[tracker]
    return failure ~= nil and GetTime() - failure.time < RETRY_DELAY
end

function Engine:HasBinding(tracker)
    return tracker ~= nil and bindingByTracker[tracker] ~= nil
end

function Engine:SetPresentationVisible(tracker, visible)
    local binding = tracker and bindingByTracker[tracker]
    if not binding or not binding.proxy then return false end
    binding.presentationVisible = visible == true
    binding.proxy:SetShown(binding.active == true and binding.presentationVisible)
    return true
end

function Engine:IsBuildDeferred(tracker)
    return tracker ~= nil and deferredByTracker[tracker] == true
end

function Engine:Detach(tracker, bar)
    local binding = tracker and bindingByTracker[tracker]
    if tracker then deferredByTracker[tracker] = nil end
    if binding then ParkBinding(binding) end
    RestoreLegacyDisplay(bar)
end

function Engine:Suspend()
    suspended = true
    for _, binding in pairs(bindingByTracker) do
        ParkBinding(binding)
    end
end

function Engine:GetDiagnostics()
    local activeBindings = 0
    local failedTrackers = 0
    for _ in pairs(bindingByTracker) do
        activeBindings = activeBindings + 1
    end
    for _ in pairs(failureByTracker) do
        failedTrackers = failedTrackers + 1
    end

    local result = {}
    for key, value in pairs(diagnostics) do
        result[key] = value
    end
    result.activeBindings = activeBindings
    result.failedTrackers = failedTrackers
    result.averageBuildMs = diagnostics.buildAttempts > 0
        and diagnostics.totalBuildMs / diagnostics.buildAttempts or 0
    result.suspended = suspended
    return result
end

function Engine:ResetDiagnostics()
    for key, value in pairs(diagnostics) do
        if type(value) == "number" then
            diagnostics[key] = 0
        else
            diagnostics[key] = nil
        end
    end
end
