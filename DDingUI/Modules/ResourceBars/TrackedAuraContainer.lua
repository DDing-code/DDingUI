local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Engine = {}
DDingUI.TrackedAuraContainer = Engine

local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local RETRY_DELAY = 2

local trackerBindings = setmetatable({}, { __mode = "k" })
local liveBindings = {}
local liveContainer
local buildingContainer
local liveSignature
local host
local suspended = false
local failedSignature
local failedAt = 0
local formatterCache = {}

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
        local overrideID = C_Spell.GetOverrideSpell(spellID)
        overrideID = CleanID(overrideID)
        if overrideID then include[overrideID] = true end
    end
    if C_Spell.GetBaseSpell then
        local baseID = C_Spell.GetBaseSpell(spellID)
        baseID = CleanID(baseID)
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

local function CollectDesired(trackers)
    local desired = {}
    local signatureParts = {}

    for _, tracker in ipairs(trackers or {}) do
        if IsAuraBar(tracker) then
            local include = {}
            local cooldownID = TrackerCooldownID(tracker)
            AddSpellVariants(include, TrackerSpellID(tracker))
            AddCooldownInfo(include, cooldownID)
            if not next(include) then
                AddSpellVariants(include, cooldownID)
            end

            local ids = SortedIDs(include)
            if #ids > 0 then
                local settings = tracker.settings or {}
                local maxApplications = ClampInteger(settings.maxStacks, 1, 1000, 1)
                local durationDecimals = ClampInteger(settings.durationDecimals, 0, 2, 1)
                desired[#desired + 1] = {
                    tracker = tracker,
                    include = include,
                    ids = ids,
                    maxApplications = maxApplications,
                    durationDecimals = durationDecimals,
                }
                signatureParts[#signatureParts + 1] = table.concat(ids, ",")
                    .. ":" .. maxApplications
                    .. ":" .. durationDecimals
            end
        end
    end

    return desired, table.concat(signatureParts, ";")
end

local function GetDurationFormatter(decimals)
    local cached = formatterCache[decimals]
    if cached ~= nil then return cached or nil end
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum and Enum.NumericRuleFormatRounding)
    then
        formatterCache[decimals] = false
        return nil
    end

    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local format = decimals > 0 and ("%." .. decimals .. "f") or "%d"
    local rounding = decimals > 0
        and Enum.NumericRuleFormatRounding.Nearest
        or Enum.NumericRuleFormatRounding.Up
    local options = { threshold = 0, format = format, rounding = rounding }
    if decimals == 0 then options.step = 1 end

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

local function EnsureHost()
    if host then return host end

    host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(1, 1)
    host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    host:SetFrameStrata("BACKGROUND")
    host:SetAlpha(0)
    host:EnableMouse(false)
    host:Show()
    return host
end

local function CreateInitializer(binding, desired)
    return function(button)
        button:SetSize(1, 1)
        if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
        if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end

        local carrier = CreateFrame("Frame", nil, button)
        carrier:SetAllPoints(button)
        carrier:EnableMouse(false)

        local applicationBar = CreateFrame("StatusBar", nil, carrier)
        applicationBar:SetAllPoints(carrier)
        applicationBar:SetStatusBarTexture(SOLID_TEXTURE)

        local durationBar = CreateFrame("StatusBar", nil, carrier)
        durationBar:SetAllPoints(carrier)
        durationBar:SetStatusBarTexture(SOLID_TEXTURE)

        local applicationText = carrier:CreateFontString(nil, "OVERLAY")
        applicationText:SetFont(DEFAULT_FONT, 12, "")
        applicationText:SetPoint("CENTER", carrier, "CENTER")

        local durationText = carrier:CreateFontString(nil, "OVERLAY")
        durationText:SetFont(DEFAULT_FONT, 12, "")
        durationText:SetPoint("CENTER", carrier, "CENTER")

        local immediate = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
        local remaining = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
        button:SetApplicationBar(applicationBar, {
            maxApplications = desired.maxApplications,
            interpolation = immediate,
        })
        local applicationFormatter = GetDurationFormatter(0)
        button:SetApplicationCount(
            applicationText,
            applicationFormatter and { formatter = applicationFormatter } or {}
        )
        button:SetDurationBar(durationBar, {
            interpolation = immediate,
            direction = remaining,
        })

        local formatter = GetDurationFormatter(desired.durationDecimals)
        button:SetDurationText(durationText, formatter and { textFormatter = formatter } or {})

        binding.button = button
        binding.applicationBar = applicationBar
        binding.applicationText = applicationText
        binding.durationBar = durationBar
        binding.durationText = durationText
    end
end

local function BuildContainer(desired)
    if not EnsureContainerAPI() then error("AuraContainer API unavailable") end

    local container = CreateFrame("AuraContainer", nil, EnsureHost(), "CustomAuraContainerTemplate")
    buildingContainer = container
    container:SetSize(1, 1)
    container:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)

    local bindings = {}
    for index, entry in ipairs(desired) do
        local binding = {}
        bindings[index] = binding
        container:AddAuraSlot("tracked" .. index, "HELPFUL", {
            candidateFilters = { includeSpellIDs = entry.include },
            initializeFrame = CreateInitializer(binding, entry),
        })
    end

    container:SetUnit("player")
    container:UpdateAllAuras()
    buildingContainer = nil
    return container, bindings
end

local function SetContainerActive(container, active)
    if not container then return end
    if container._ddingTrackedAuraActive == active then return end

    container._ddingTrackedAuraActive = active
    if container.SetEnabled then container:SetEnabled(active) end
    container:SetShown(active)
end

local function BindTrackers(desired)
    wipe(trackerBindings)
    for index, entry in ipairs(desired) do
        trackerBindings[entry.tracker] = liveBindings[index]
    end
end

function Engine:Sync(trackers)
    local desired, signature = CollectDesired(trackers)
    if #desired == 0 then
        wipe(trackerBindings)
        SetContainerActive(liveContainer, false)
        suspended = true
        return
    end

    if liveContainer and signature == liveSignature then
        BindTrackers(desired)
        suspended = false
        EnsureHost():Show()
        SetContainerActive(liveContainer, true)
        return
    end

    local now = GetTime()
    if failedSignature == signature and now - failedAt < RETRY_DELAY then
        wipe(trackerBindings)
        return
    end

    local ok, container, bindings = pcall(BuildContainer, desired)
    if not ok then
        SetContainerActive(buildingContainer, false)
        buildingContainer = nil
        failedSignature = signature
        failedAt = now
        wipe(trackerBindings)
        return
    end

    SetContainerActive(liveContainer, false)
    liveContainer = container
    liveBindings = bindings
    liveSignature = signature
    liveContainer._ddingTrackedAuraActive = true
    failedSignature = nil
    suspended = false
    BindTrackers(desired)
end

function Engine:Suspend()
    wipe(trackerBindings)
    suspended = true
    SetContainerActive(liveContainer, false)
end

local function CopyStatusBar(source, target)
    if not source or not target then return false end
    target:SetMinMaxValues(source:GetMinMaxValues())
    target:SetValue(source:GetValue())
    return true
end

local function CopyText(source, target)
    if not source or not target then return false end
    local text = source:GetText()
    if type(text) == "nil" then text = "" end
    target:SetText(text)
    return true
end

function Engine:Mirror(tracker, targetStatusBar, targetApplicationText, targetDurationText, mode, showDurationText)
    if suspended then return false, false, false end
    local binding = tracker and trackerBindings[tracker]
    if not binding then return false, false, false end

    local progressCopied
    if mode == "duration" then
        progressCopied = CopyStatusBar(binding.durationBar, targetStatusBar)
    else
        progressCopied = CopyStatusBar(binding.applicationBar, targetStatusBar)
    end

    local applicationCopied = CopyText(binding.applicationText, targetApplicationText)
    local durationCopied = not showDurationText
    if showDurationText then
        durationCopied = CopyText(binding.durationText, targetDurationText)
    end
    return progressCopied, applicationCopied, durationCopied
end
