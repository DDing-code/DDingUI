local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Engine = {}
DDingUI.TrackedAuraContainer = Engine

local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local RETRY_DELAY = 2

local desiredByTracker = setmetatable({}, { __mode = "k" })
local bindingByTracker = setmetatable({}, { __mode = "k" })
local failureByTracker = setmetatable({}, { __mode = "k" })
local formatterCache = {}
local suspended = false
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
    return CleanID(tracker and (tracker.cooldownID or (tracker.trigger and tracker.trigger.cooldownID))) or 0
end

local function TrackerSpellID(tracker)
    return CleanID(tracker and (tracker.spellID or (tracker.trigger and tracker.trigger.spellID))) or 0
end

local function IsAuraBar(tracker)
    if type(tracker) ~= "table" or tracker.isGroup or tracker.enabled == false then return false end
    if (tracker.displayType or "bar") ~= "bar" then return false end
    if ((tracker.settings or {}).barStyle or "bar") ~= "bar" then return false end
    if tracker.trackingMode == "manual" or tracker.trackingMode == "spell" then return false end
    if tracker.trigger and tracker.trigger.type == "spell" then return false end
    if tracker.isAura == false then return false end
    return TrackerCooldownID(tracker) > 0 or TrackerSpellID(tracker) > 0
end

local function AddCooldownInfo(include, cooldownID)
    if cooldownID <= 0 then return end

    local scanner = DDingUI.CDMScanner
    local info = scanner and scanner.GetEntry and scanner.GetEntry(cooldownID)
    if not info then
        local compat = DDingUI.CDMCompat
        info = compat and compat.GetCooldownInfo and compat:GetCooldownInfo(cooldownID)
    end
    if type(info) ~= "table" or IsSecret(info) then return end

    AddSpellVariants(include, info.spellID)
    AddSpellVariants(include, info.displaySpellID)
    AddSpellVariants(include, info.overrideSpellID)
    AddSpellVariants(include, info.overrideTooltipSpellID)
    AddSpellVariants(include, info.linkedSpellID)

    local linked = info.linkedSpellIDs
    if type(linked) == "table" and not IsSecret(linked) then
        for index = 1, #linked do
            AddSpellVariants(include, linked[index])
        end
    end
end

local function SortedIDs(include)
    local ids = {}
    for spellID in pairs(include) do
        ids[#ids + 1] = spellID
    end
    table.sort(ids)
    return ids
end

local function ClampInteger(value, minimum, maximum, fallback)
    value = tonumber(value) or fallback
    value = math.floor(value + 0.5)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function BuildDesired(tracker)
    if not IsAuraBar(tracker) then return nil end

    local include = {}
    local cooldownID = TrackerCooldownID(tracker)
    AddSpellVariants(include, TrackerSpellID(tracker))
    AddCooldownInfo(include, cooldownID)

    local ids = SortedIDs(include)
    if #ids == 0 then return nil end

    local settings = tracker.settings or {}
    local maxApplications = ClampInteger(settings.maxStacks, 1, 1000, 1)
    local durationDecimals = ClampInteger(settings.durationDecimals, 0, 2, 1)
    return {
        include = include,
        maxApplications = maxApplications,
        durationDecimals = durationDecimals,
        signature = table.concat(ids, ",") .. ":" .. maxApplications .. ":" .. durationDecimals,
    }
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

local function ColorPart(color)
    color = color or {}
    return table.concat({
        tostring(color[1] or 1),
        tostring(color[2] or 1),
        tostring(color[3] or 1),
        tostring(color[4] or 1),
    }, ",")
end

local function StyleSignature(style)
    return table.concat({
        tostring(style.mode),
        tostring(style.texture),
        ColorPart(style.barColor),
        ColorPart(style.bgColor),
        ColorPart(style.borderColor),
        tostring(style.borderSize or 0),
        tostring(style.orientation),
        tostring(style.reverseFill),
        tostring(style.showStacksText),
        tostring(style.showDurationText),
        tostring(style.stacksFont),
        tostring(style.stacksFontSize),
        tostring(style.stacksAlign),
        tostring(style.stacksX),
        tostring(style.stacksY),
        ColorPart(style.stacksColor),
        tostring(style.durationFont),
        tostring(style.durationFontSize),
        tostring(style.durationAlign),
        tostring(style.durationX),
        tostring(style.durationY),
        ColorPart(style.durationColor),
        tostring(style.frameStrata),
        tostring(style.frameLevel),
    }, "|")
end

local function ApplyColor(region, color)
    region:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
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
    top:SetPoint("TOPLEFT", host, "TOPLEFT")
    top:SetPoint("TOPRIGHT", host, "TOPRIGHT")
    top:SetHeight(size)

    local bottom = host:CreateTexture(nil, "OVERLAY")
    bottom:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
    bottom:SetHeight(size)

    local left = host:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    left:SetPoint("TOPLEFT", host, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT")
    left:SetWidth(size)

    local right = host:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    right:SetPoint("TOPRIGHT", host, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
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
    local color = style[prefix .. "Color"] or { 1, 1, 1, 1 }
    fontString:SetFont(font, size, "OUTLINE")
    fontString:SetShadowOffset(0, 0)
    fontString:SetJustifyH(align)
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

local function CreateInitializer(proxy, desired, style)
    return function(button)
        button:SetAllPoints(proxy)
        button:SetFrameLevel((style.frameLevel or 1) + 1)
        if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
        if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end

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
        ApplyColor(progress:GetStatusBarTexture(), style.barColor or { 1, 0.8, 0, 1 })

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

        if style.showStacksText then
            local applications = CreateBoundText(button, style, "stacks")
            local formatter = GetFormatter(0)
            pcall(button.SetApplicationCount, button, applications, formatter and { formatter = formatter } or {})
        end
        if style.showDurationText then
            RegisterDurationText(button, CreateBoundText(button, style, "duration"), desired.durationDecimals)
        end

        CreateBorder(button, style.borderSize, style.borderColor or { 0, 0, 0, 1 })
    end
end

local function BuildBinding(bar, desired, style, styleSignature)
    if not EnsureContainerAPI() then error("AuraContainer API unavailable") end

    local proxy = CreateFrame("Frame", nil, UIParent)
    proxy:SetFrameStrata(style.frameStrata or "MEDIUM")
    proxy:SetFrameLevel(style.frameLevel or 1)
    proxy:SetAllPoints(bar)
    proxy:EnableMouse(false)
    proxy:Show()

    local container = CreateFrame("AuraContainer", nil, proxy, "CustomAuraContainerTemplate")
    container:SetPoint("CENTER", proxy, "CENTER")
    container:SetSize(1, 1)
    container:AddAuraSlot("tracked", "HELPFUL", {
        candidateFilters = { includeSpellIDs = desired.include },
        initializeFrame = CreateInitializer(proxy, desired, style),
    })
    container:SetUnit("player")
    container:UpdateAllAuras()

    return {
        proxy = proxy,
        container = container,
        bar = bar,
        desiredSignature = desired.signature,
        styleSignature = styleSignature,
    }
end

local function RestoreLegacyDisplay(bar)
    if not bar then return end
    bar._auraContainerOwnsDisplay = nil
    bar._auraContainerBinding = nil
    if bar.StatusBar then bar.StatusBar:SetAlpha(1) end
    if bar.Background then bar.Background:SetAlpha(1) end
    if bar.Border then bar.Border:SetAlpha(1) end
    if bar.TextValue then bar.TextValue:SetAlpha(1) end
    if bar.DurationText then bar.DurationText:SetAlpha(1) end
end

local function HideLegacyDisplay(bar)
    if not bar then return end
    bar._auraContainerOwnsDisplay = true
    if bar.StatusBar then bar.StatusBar:SetAlpha(0) end
    if bar.Background then bar.Background:SetAlpha(0) end
    if bar.Border then bar.Border:SetAlpha(0) end
    if bar.TextValue then bar.TextValue:SetAlpha(0) end
    if bar.DurationText then bar.DurationText:SetAlpha(0) end
end

local function ParkBinding(binding)
    if not binding then return end
    if binding.proxy then binding.proxy:Hide() end
    RestoreLegacyDisplay(binding.bar)
    diagnostics.parked = diagnostics.parked + 1
end

function Engine:Sync(trackers)
    diagnostics.syncs = diagnostics.syncs + 1
    local retained = {}
    local desiredCount = 0
    for _, tracker in ipairs(trackers or {}) do
        local desired = BuildDesired(tracker)
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
        end
    end
    suspended = false
end

function Engine:Attach(tracker, bar, style)
    local desired = tracker and desiredByTracker[tracker]
    if suspended or not desired or not bar or type(style) ~= "table" or style.barStyle ~= "bar" then
        self:Detach(tracker, bar)
        return false
    end

    local signature = StyleSignature(style)
    local binding = bindingByTracker[tracker]
    if binding and binding.desiredSignature == desired.signature and binding.styleSignature == signature then
        diagnostics.reuses = diagnostics.reuses + 1
        if binding.bar ~= bar then
            RestoreLegacyDisplay(binding.bar)
            binding.bar = bar
            binding.proxy:ClearAllPoints()
            binding.proxy:SetAllPoints(bar)
        end
        binding.proxy:SetFrameStrata(style.frameStrata or "MEDIUM")
        binding.proxy:SetFrameLevel(style.frameLevel or 1)
        binding.proxy:Show()
        HideLegacyDisplay(bar)
        bar._auraContainerBinding = binding
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

    diagnostics.buildAttempts = diagnostics.buildAttempts + 1
    if binding then diagnostics.rebuilds = diagnostics.rebuilds + 1 end
    local started = debugprofilestop and debugprofilestop() or nil
    local ok, replacement = pcall(BuildBinding, bar, desired, style, signature)
    local elapsed = started and (debugprofilestop() - started) or 0
    diagnostics.lastBuildMs = elapsed
    diagnostics.totalBuildMs = diagnostics.totalBuildMs + elapsed
    diagnostics.maxBuildMs = math.max(diagnostics.maxBuildMs, elapsed)
    if not ok then
        diagnostics.buildFailures = diagnostics.buildFailures + 1
        diagnostics.lastError = tostring(replacement)
        failureByTracker[tracker] = { signature = buildSignature, time = now }
        ParkBinding(binding)
        RestoreLegacyDisplay(bar)
        local resourceBars = DDingUI.ResourceBars
        if resourceBars and resourceBars.RequestBuffTrackerUpdate then
            diagnostics.fallbackRequests = diagnostics.fallbackRequests + 1
            resourceBars:RequestBuffTrackerUpdate("aura-container-fallback", 0)
        end
        return false
    end

    diagnostics.buildSuccess = diagnostics.buildSuccess + 1
    diagnostics.lastError = nil
    ParkBinding(binding)
    bindingByTracker[tracker] = replacement
    failureByTracker[tracker] = nil
    HideLegacyDisplay(bar)
    bar._auraContainerBinding = replacement
    return true
end

function Engine:ShouldReadLegacy(tracker)
    if suspended or not tracker or not desiredByTracker[tracker] then
        return true
    end

    if bindingByTracker[tracker] then
        return false
    end

    local failure = failureByTracker[tracker]
    return failure ~= nil and GetTime() - failure.time < RETRY_DELAY
end

function Engine:Detach(tracker, bar)
    local binding = tracker and bindingByTracker[tracker]
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
