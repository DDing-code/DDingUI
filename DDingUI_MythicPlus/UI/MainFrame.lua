local addonName, ns = ...

local Addon = ns.Addon
local UI = ns.UI
local L = ns.L

local TABS = {
    { key = "general", label = "General" },
    { key = "groups", label = "Groups" },
    { key = "style", label = "Style" },
    { key = "spells", label = "Spells" },
    { key = "profile", label = "Profile" },
    { key = "dungeon", label = "Dungeon" },
    { key = "info", label = "Info" },
    { key = "routes", label = "Routes" },
    { key = "runs", label = "Runs" },
    { key = "debug", label = "Debug" },
}

local STYLE_FIELDS = {
    { field = "width", label = "Width", step = 10, min = 60, max = 900 },
    { field = "height", label = "Height", step = 1, min = 10, max = 80 },
    { field = "icon", label = "Icon", step = 1, min = 0, max = 90 },
    { field = "right", label = "Right", step = 2, min = 0, max = 160 },
    { field = "target", label = "Target", step = 1, min = 0, max = 48 },
    { field = "marker", label = "Marker", step = 1, min = 1, max = 8 },
    { field = "font", label = "Font", step = 1, min = 8, max = 32 },
    { field = "spacing", label = "Gap", step = 1, min = 0, max = 30 },
    { field = "max", label = "Rows", step = 1, min = 1, max = 20 },
    { field = "alpha", label = "Fill", step = 0.05, min = 0.10, max = 1 },
    { field = "bg", label = "Back", step = 0.05, min = 0, max = 1 },
}

local FIELD_MAP = {
    width = "width",
    height = "height",
    icon = "iconSize",
    right = "rightWidth",
    target = "targetIndicatorSize",
    marker = "interruptMarkerWidth",
    font = "fontSize",
    spacing = "spacing",
    max = "maxRows",
    alpha = "barAlpha",
    bg = "bgAlpha",
    texture = "barTexture",
}

local COLOR_PRESETS = {
    { 0.14, 0.78, 0.36, 0.95 },
    { 0.00, 0.58, 0.78, 0.95 },
    { 0.73, 0.43, 0.18, 0.95 },
    { 0.78, 0.50, 0.00, 0.95 },
    { 0.72, 0.10, 0.20, 0.95 },
    { 0.58, 0.56, 0.36, 0.95 },
    { 0.45, 0.85, 0.32, 0.95 },
}

local GROW_DIRECTIONS = { "DOWN", "UP", "RIGHT", "LEFT" }
local TIME_FORMATS = { "remaining", "duration" }
local FONT_OUTLINES = { "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE", "NONE" }
local TARGET_SEPARATORS = { " > ", " >> ", " - ", " : ", " " }

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if minValue and value < minValue then return minValue end
    if maxValue and value > maxValue then return maxValue end
    return value
end

local function Round(value, step)
    if not step or step >= 1 then
        return math.floor((tonumber(value) or 0) + 0.5)
    end
    return math.floor(((tonumber(value) or 0) / step) + 0.5) * step
end

local function FormatValue(value)
    if value == nil then return "n/a" end
    if type(value) == "number" then
        if math.floor(value) == value then return tostring(value) end
        return string.format("%.2f", value)
    end
    return tostring(value)
end

local function CreateValueControl(parent, x, y, label, onMinus, onPlus, width)
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(width or 168, 44)
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    control.label = control:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    control.label:SetPoint("TOPLEFT", 0, 0)
    control.label:SetText(label)
    control.label:SetTextColor(UI:Color("textDim"))

    control.minus = UI:CreateButton(control, 24, 22, "-")
    control.minus:SetPoint("BOTTOMLEFT", 0, 0)
    control.minus:SetScript("OnClick", onMinus)

    control.value = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    control.value:SetPoint("LEFT", control.minus, "RIGHT", 8, 0)
    control.value:SetPoint("RIGHT", control, "RIGHT", -34, 0)
    control.value:SetJustifyH("CENTER")
    control.value:SetTextColor(UI:Color("text"))

    control.plus = UI:CreateButton(control, 24, 22, "+")
    control.plus:SetPoint("BOTTOMRIGHT", 0, 0)
    control.plus:SetScript("OnClick", onPlus)
    return control
end

local function GetGroupDB(groupKey)
    return ns.db and ns.db.profile and ns.db.profile.groups and ns.db.profile.groups[groupKey]
end

local function ApplyConfig(reason)
    if ns.Config and ns.Config.ApplyOrQueue then
        ns.Config:ApplyOrQueue(reason)
    elseif ns.Display and ns.Display.ApplyConfig then
        ns.Display:ApplyConfig(reason)
    end
end

local function SetButtonState(button, active)
    button:SetBackdropColor(active and 0.00 or 0.15, active and 0.42 or 0.17, active and 0.55 or 0.20, 0.98)
end

local function CreateLine(parent, text, x, y, width)
    local line = UI:CreateBodyText(parent, text)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    line:SetWidth(width or 660)
    return line
end

local function CreateToggle(parent, x, y, width, label, getter, setter)
    local button = UI:CreateButton(parent, width or 190, 26, "")
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetScript("OnClick", function()
        setter(not getter())
        if button.Refresh then
            button:Refresh()
        end
    end)
    function button:Refresh()
        local enabled = getter()
        self.text:SetText((enabled and "|cff88ff88ON|r " or "|cffff6666OFF|r ") .. label)
    end
    button:Refresh()
    return button
end

function ns:CreateMainFrame()
    if self.MainFrame then
        return self.MainFrame
    end

    local frame = UI:CreateMainFrame(UIParent, 840, 840, "DDingUIMythicPlus_MainFrame")
    frame.titleBar = UI:CreateTitleBar(frame, "|cffffffffDDing|r|cffffa300UI|r |cff00b7ebMythic Plus|r v" .. Addon.version)
    frame.selectedTab = "general"
    frame.selectedGroup = "generalCast"

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -56)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\logo")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 16, -2)
    title:SetText(L["ADDON_TITLE"])
    title:SetTextColor(UI:Color("text"))

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Standalone timers, center alerts, voice cues, and party interrupt tracking.")
    subtitle:SetTextColor(UI:Color("textDim"))

    local tabButtons = {}
    for index, tab in ipairs(TABS) do
        local button = UI:CreateButton(frame, 76, 28, tab.label)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 26 + ((index - 1) * 78), -132)
        button.tabKey = tab.key
        button:SetScript("OnClick", function()
            frame.selectedTab = button.tabKey
            frame:RefreshTabs()
        end, width)
        tabButtons[#tabButtons + 1] = button
    end

    local content = UI:CreatePanel(frame, 788, 610)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -172)
    frame.content = content
    frame.panels = {}

    local function CreatePanel(key)
        local panel = CreateFrame("Frame", nil, content)
        panel:SetAllPoints(content)
        panel:Hide()
        frame.panels[key] = panel
        return panel
    end

    local general = CreatePanel("general")
    local generalHeader = UI:CreateSectionHeader(general, "Runtime")
    generalHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 18, -18)
    CreateLine(general, "Native events are registered once during startup. Settings changes update listeners and display state without calling Frame:RegisterEvent from UI clicks.", 18, -50, 730)

    local moduleButtons = {}
    local moduleRows = {
        { "AuraFingerprint", "Aura Fingerprint" },
        { "MythicRuntime", "Runtime" },
        { "CooldownCalibration", "CD Calibration" },
        { "Voice", "Voice" },
        { "AlertRuntime", "Alert API" },
        { "FlashTextMedium", "Medium Text" },
        { "GlobalSettings", "Global" },
        { "EncounterCVarGuard", "CVar Guard" },
        { "ProfileExchange", "Import / Export" },
        { "ConditionEngine", "Conditions" },
        { "TimerAlertDispatcher", "Timer Alerts" },
        { "CountdownDisplay", "Countdown Display" },
        { "RingProgress", "Ring Progress" },
        { "CastProgressBar", "Cast Progress" },
        { "BunBar", "Bun Bar" },
        { "PartyFrameGlow", "Frame Glow" },
        { "WidgetTracker", "UI Widgets" },
        { "BossMechanicBridge", "Boss Bridge" },
        { "AbsorbShieldTracker", "Absorb Shield" },
        { "DogJumpTracker", "Dog Jump" },
        { "TrashCustomEventTracker", "Trash Custom" },
        { "PartySpecSync", "Spec Sync" },
        { "InterruptTracker", "Interrupts" },
        { "NameplateMarker", "Nameplate Icons" },
        { "DebuffTracker", "Debuffs" },
        { "PrivateAuraTracker", "Private Auras" },
        { "AffixTracker", "Affixes" },
        { "HealthThresholdTracker", "HP Alerts" },
        { "KeystoneInfo", "Keystone" },
        { "AssignmentPlanner", "Assignments" },
        { "EncounterSplitTracker", "Splits" },
        { "SpellBrowser", "Spell Browser" },
        { "RouteNotes", "Route Notes" },
        { "PullPlanner", "Pull Preview" },
        { "RouteOverlay", "Route Overlay" },
        { "RunHistory", "Run History" },
        { "DeathTracker", "Deaths" },
    }
    local moduleCols = 9
    local moduleWidth = 84
    local moduleStep = 85
    for index, row in ipairs(moduleRows) do
        local col = (index - 1) % moduleCols
        local r = math.floor((index - 1) / moduleCols)
        local button = CreateToggle(general, 18 + (col * moduleStep), -98 - (r * 30), moduleWidth, row[2], function()
            return Addon:IsModuleEnabled(row[1])
        end, function(enabled)
            Addon:SetModuleEnabled(row[1], enabled)
        end)
        moduleButtons[#moduleButtons + 1] = button
    end

    local runtimeHeader = UI:CreateSectionHeader(general, "Runtime Options")
    runtimeHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 18, -222)
    local runtimeToggleButtons = {}
    local optionRows = {
        { label = "M+ Only", key = "hideNonMythicPlus" },
        { label = "Boss TL", key = "useBossTimeline" },
        { label = "Predict", key = "usePredictiveBossTimeline" },
        { label = "Poll", key = "useBossCastPolling" },
        { label = "Trash TL", key = "useTrashTimeline" },
        { label = "Passive", key = "usePassiveTimeline" },
        { label = "Countdown", key = "countdownAlerts" },
        { label = "Infer Spell", key = "inferUnknownSpellID" },
        { label = "Hide Long", key = "hideLongTimerBarEnabled" },
        { label = "Keep Ready", key = "keepTimerBarAfterReadyEnabled" },
        { label = "M+ Boss", moduleKey = "GlobalSettings", field = "bossAlertsEnabledMplus" },
        { label = "Raid Boss", moduleKey = "GlobalSettings", field = "bossAlertsEnabledRaid" },
        { label = "Tank DPS", moduleKey = "GlobalSettings", field = "hideTankBossAlertsForDps" },
        { label = "Tank Heal", moduleKey = "GlobalSettings", field = "hideTankBossAlertsForHeal", trueOnly = true },
        { label = "Warn Text", moduleKey = "EncounterCVarGuard", field = "encounterWarningsEnabled" },
        { label = "Warn Snd", moduleKey = "EncounterCVarGuard", field = "encounterWarningSoundsEnabled" },
    }
    local function GetRuntimeToggleValue(row)
        if row.moduleKey then
            local db = Addon:GetModuleDB(row.moduleKey)
            if row.trueOnly then
                return db and db[row.field] == true
            end
            return db and db[row.field] ~= false
        end
        return ns.db.profile.runtime[row.key] ~= false
    end
    local function SetRuntimeToggleValue(row, enabled)
        if row.moduleKey == "GlobalSettings" then
            local module = ns.GlobalSettings
            if module and module.SetSceneField then
                module:SetSceneField(row.field, enabled)
                return
            end
            local db = Addon:GetModuleDB(row.moduleKey)
            if db then
                db[row.field] = enabled and true or false
                ApplyConfig(row.moduleKey .. ":" .. row.field)
            end
            return
        end
        if row.moduleKey then
            local db = Addon:GetModuleDB(row.moduleKey)
            if db then
                db[row.field] = enabled and true or false
                ApplyConfig(row.moduleKey .. ":" .. row.field)
            end
            return
        end
        ns.db.profile.runtime[row.key] = enabled and true or false
        ApplyConfig("runtime:" .. row.key)
    end
    for index, row in ipairs(optionRows) do
        local col = (index - 1) % 8
        local r = math.floor((index - 1) / 8)
        local button = CreateToggle(general, 18 + (col * 94), -254 - (r * 32), 88, row.label, function()
            return GetRuntimeToggleValue(row)
        end, function(enabled)
            SetRuntimeToggleValue(row, enabled)
        end)
        runtimeToggleButtons[#runtimeToggleButtons + 1] = button
    end
    runtimeToggleButtons[#runtimeToggleButtons + 1] = CreateToggle(general, 18, -318, 100, "Timer Pre", function()
        local db = Addon:GetModuleDB("TimerAlertDispatcher")
        return db and db.preAlert ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("TimerAlertDispatcher")
        if db then
            db.preAlert = enabled and true or false
            ApplyConfig("timerAlertDispatcher:preAlert")
        end
    end)
    runtimeToggleButtons[#runtimeToggleButtons + 1] = CreateToggle(general, 126, -318, 100, "Timer CD", function()
        local db = Addon:GetModuleDB("TimerAlertDispatcher")
        return db and db.countdown ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("TimerAlertDispatcher")
        if db then
            db.countdown = enabled and true or false
            ApplyConfig("timerAlertDispatcher:countdown")
        end
    end)
    runtimeToggleButtons[#runtimeToggleButtons + 1] = CreateToggle(general, 234, -318, 100, "Timer Def", function()
        local db = Addon:GetModuleDB("TimerAlertDispatcher")
        return db and db.useRuntimeDefaults ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("TimerAlertDispatcher")
        if db then
            db.useRuntimeDefaults = enabled and true or false
            ApplyConfig("timerAlertDispatcher:runtimeDefaults")
        end
    end)
    local barModeButton = UI:CreateButton(general, 100, 28, "Bar Mode")
    barModeButton:SetPoint("TOPLEFT", general, "TOPLEFT", 342, -318)
    barModeButton:SetScript("OnClick", function()
        local module = ns.GlobalSettings
        local mode = module and module.GetBarMode and module:GetBarMode() or "both"
        local nextMode = mode == "both" and "timer"
            or mode == "timer" and "bun"
            or mode == "bun" and "none"
            or "both"
        if module and module.SetBarMode then
            module:SetBarMode(nextMode)
        end
        frame:RefreshRuntimeControls()
    end)
    local voiceChannelButton = UI:CreateButton(general, 100, 28, "Voice: Master")
    voiceChannelButton:SetPoint("TOPLEFT", general, "TOPLEFT", 450, -318)
    voiceChannelButton:SetScript("OnClick", function()
        local voice = ns.Voice
        if voice and voice.CycleChannel then
            voice:CycleChannel(1)
            ApplyConfig("voice:channel")
        end
        frame:RefreshRuntimeControls()
    end)
    local caaGuardButton = CreateToggle(general, 558, -318, 100, "CAA Guard", function()
        local db = Addon:GetModuleDB("EncounterCVarGuard")
        return db and db.autoMuteCombatAudioInFixedBoss == true
    end, function(enabled)
        local db = Addon:GetModuleDB("EncounterCVarGuard")
        if db then
            db.autoMuteCombatAudioInFixedBoss = enabled and true or false
            ApplyConfig("EncounterCVarGuard:autoMuteCombatAudioInFixedBoss")
        end
    end)
    runtimeToggleButtons[#runtimeToggleButtons + 1] = caaGuardButton

    local runtimeControls = {}
    local moduleValueControls = {}
    local function CreateRuntimeValueControl(x, y, label, key, step, minValue, maxValue, width)
        local control = CreateValueControl(general, x, y, label, function()
            local runtime = ns.db.profile.runtime
            runtime[key] = Clamp(Round((tonumber(runtime[key]) or 0) - step, step), minValue, maxValue)
            ApplyConfig("runtime:" .. key)
            frame:RefreshRuntimeControls()
        end, function()
            local runtime = ns.db.profile.runtime
            runtime[key] = Clamp(Round((tonumber(runtime[key]) or 0) + step, step), minValue, maxValue)
            ApplyConfig("runtime:" .. key)
            frame:RefreshRuntimeControls()
        end, width)
        control.runtimeKey = key
        runtimeControls[#runtimeControls + 1] = control
        return control
    end

    local function CreateModuleValueControl(moduleKey, x, y, label, key, step, minValue, maxValue, width)
        local control = CreateValueControl(general, x, y, label, function()
            local db = Addon:GetModuleDB(moduleKey)
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - step, step), minValue, maxValue)
                ApplyConfig(moduleKey .. ":" .. key)
                frame:RefreshRuntimeControls()
            end
        end, function()
            local db = Addon:GetModuleDB(moduleKey)
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + step, step), minValue, maxValue)
                ApplyConfig(moduleKey .. ":" .. key)
                frame:RefreshRuntimeControls()
            end
        end, width)
        control.moduleKey = moduleKey
        control.moduleField = key
        moduleValueControls[#moduleValueControls + 1] = control
        return control
    end

    local interruptHeader = UI:CreateSectionHeader(general, "Interrupt Options")
    interruptHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 18, -356)
    CreateLine(general, "Interrupt cooldowns are inferred from party cast success because combat log registration is intentionally avoided.", 18, -380, 730)
    CreateToggle(general, 18, -410, 176, "Count Casts", function()
        local db = Addon:GetModuleDB("InterruptTracker")
        return db and db.trackCastsAsUsed == true
    end, function(enabled)
        local db = Addon:GetModuleDB("InterruptTracker")
        if db then
            db.trackCastsAsUsed = enabled and true or false
            ApplyConfig("interrupt:trackCastsAsUsed")
        end
    end)

    CreateToggle(general, 208, -410, 176, "Player Names", function()
        local db = Addon:GetModuleDB("InterruptTracker")
        return db and db.showPlayerName ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("InterruptTracker")
        if db then
            db.showPlayerName = enabled and true or false
            ApplyConfig("interrupt:showPlayerName")
        end
    end)

    CreateToggle(general, 398, -410, 176, "Timer Text", function()
        local db = Addon:GetModuleDB("InterruptTracker")
        return db and db.showTimer ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("InterruptTracker")
        if db then
            db.showTimer = enabled and true or false
            ApplyConfig("interrupt:showTimer")
        end
    end)

    CreateToggle(general, 588, -410, 176, "Ready Text", function()
        local db = Addon:GetModuleDB("InterruptTracker")
        return db and db.showReadyText ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("InterruptTracker")
        if db then
            db.showReadyText = enabled and true or false
            ApplyConfig("interrupt:showReadyText")
        end
    end)

    local compactValueWidth = 140
    CreateRuntimeValueControl(18, -450, "Countdown Lead", "countdownSeconds", 1, 1, 10, compactValueWidth)
    CreateRuntimeValueControl(168, -450, "Countdown Min", "countdownMin", 1, 1, 5, compactValueWidth)
    CreateRuntimeValueControl(318, -450, "Default CD", "observedCooldown", 1, 1, 120, compactValueWidth)
    CreateRuntimeValueControl(468, -450, "Hide Above", "hideLongTimerBarSeconds", 1, 0, 300, compactValueWidth)
    local voiceVolumeControl = CreateModuleValueControl("Voice", 618, -450, "Voice Vol", "volume", 0.05, 0, 1, compactValueWidth)
    voiceVolumeControl.formatPercent = true

    local fingerprintHeader = UI:CreateSectionHeader(general, "Fingerprint Options")
    fingerprintHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 18, -500)
    CreateToggle(general, 18, -528, 228, "Fingerprint Runtime", function()
        local db = Addon:GetModuleDB("AuraFingerprint")
        return db and db.enabled ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("AuraFingerprint")
        if db then
            db.enabled = enabled and true or false
            ApplyConfig("fingerprint:enabled")
        end
    end)
    CreateToggle(general, 264, -528, 228, "Fallback Unknown", function()
        local db = Addon:GetModuleDB("AuraFingerprint")
        return db and db.fallbackOnUnknown ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("AuraFingerprint")
        if db then
            db.fallbackOnUnknown = enabled and true or false
            ApplyConfig("fingerprint:fallback")
        end
    end)
    CreateToggle(general, 510, -528, 228, "M+ Only", function()
        local db = Addon:GetModuleDB("AuraFingerprint")
        return db and db.onlyInChallenge ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("AuraFingerprint")
        if db then
            db.onlyInChallenge = enabled and true or false
            ApplyConfig("fingerprint:onlyInChallenge")
        end
    end)
    CreateModuleValueControl("AuraFingerprint", 18, -564, "Start Delay", "startDelay", 0.02, 0.02, 0.50)
    CreateModuleValueControl("AuraFingerprint", 208, -564, "Target Delay", "targetDelay", 0.02, 0.02, 0.50)
    CreateModuleValueControl("AuraFingerprint", 398, -564, "Aura Poll", "auraDeltaPoll", 0.02, 0.05, 1.00)

    local groups = CreatePanel("groups")
    local groupsHeader = UI:CreateSectionHeader(groups, "Groups")
    groupsHeader:SetPoint("TOPLEFT", groups, "TOPLEFT", 18, -18)
    CreateLine(groups, "Reference-backed display groups are exposed here. Positions are moved with Edit Mode.", 18, -48, 730)
    local groupButtons = {}
    local groupKeys = ns.Display and ns.Display:GetGroupKeys() or {}
    for index, key in ipairs(groupKeys) do
        local db = GetGroupDB(key)
        local col = (index - 1) % 3
        local r = math.floor((index - 1) / 3)
        local y = -92 - (r * 76)
        local x = 18 + (col * 246)
        local selectButton = UI:CreateButton(groups, 228, 26, db and db.label or key)
        selectButton:SetPoint("TOPLEFT", groups, "TOPLEFT", x, y)
        selectButton.groupKey = key
        selectButton:SetScript("OnClick", function()
            frame.selectedGroup = key
            frame.selectedTab = "style"
            frame:RefreshTabs()
        end)
        groupButtons[#groupButtons + 1] = selectButton
        CreateToggle(groups, x, y - 30, 108, "Use", function()
            return GetGroupDB(key).enabled ~= false
        end, function(enabled)
            GetGroupDB(key).enabled = enabled and true or false
            ApplyConfig("group:" .. key .. ":enabled")
        end)
        CreateToggle(groups, x + 120, y - 30, 108, "Prev", function()
            return GetGroupDB(key).preview == true
        end, function(enabled)
            GetGroupDB(key).preview = enabled and true or false
            ApplyConfig("group:" .. key .. ":preview")
        end)
    end

    local style = CreatePanel("style")
    local styleHeader = UI:CreateSectionHeader(style, "Style")
    styleHeader:SetPoint("TOPLEFT", style, "TOPLEFT", 18, -18)
    local styleTargetButtons = {}
    for index, key in ipairs(groupKeys) do
        local db = GetGroupDB(key)
        local button = UI:CreateButton(style, 146, 24, db and db.label or key)
        local col = (index - 1) % 5
        local r = math.floor((index - 1) / 5)
        button:SetPoint("TOPLEFT", style, "TOPLEFT", 18 + (col * 152), -50 - (r * 30))
        button.groupKey = key
        button:SetScript("OnClick", function()
            frame.selectedGroup = key
            frame:RefreshStyleControls()
        end)
        styleTargetButtons[#styleTargetButtons + 1] = button
    end

    local styleControls = {}
    for index, field in ipairs(STYLE_FIELDS) do
        local col = (index - 1) % 3
        local r = math.floor((index - 1) / 3)
        local control = CreateValueControl(style, 18 + (col * 190), -140 - (r * 52), field.label, function()
            local db = GetGroupDB(frame.selectedGroup)
            local key = FIELD_MAP[field.field]
            if db and key then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - field.step, field.step), field.min, field.max)
                ApplyConfig("style:" .. frame.selectedGroup .. ":" .. key)
                frame:RefreshStyleControls()
            end
        end, function()
            local db = GetGroupDB(frame.selectedGroup)
            local key = FIELD_MAP[field.field]
            if db and key then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + field.step, field.step), field.min, field.max)
                ApplyConfig("style:" .. frame.selectedGroup .. ":" .. key)
                frame:RefreshStyleControls()
            end
        end)
        control.field = field.field
        styleControls[#styleControls + 1] = control
    end

    local textureButton = UI:CreateButton(style, 180, 28, "Cycle Texture")
    textureButton:SetPoint("TOPLEFT", style, "TOPLEFT", 588, -140)
    textureButton:SetScript("OnClick", function()
        local db = GetGroupDB(frame.selectedGroup)
        if not db then return end
        local textures = { "DDingUI Flat", "Blizzard", "BantoBar", "Smooth" }
        local current = db.barTexture
        local index = 1
        for i, value in ipairs(textures) do
            if value == current then index = i break end
        end
        index = index + 1
        if index > #textures then index = 1 end
        db.barTexture = textures[index]
        ApplyConfig("style:" .. frame.selectedGroup .. ":texture")
        frame:RefreshStyleControls()
    end)

    local colorButton = UI:CreateButton(style, 180, 28, "Cycle Color")
    colorButton:SetPoint("TOPLEFT", style, "TOPLEFT", 588, -176)
    colorButton:SetScript("OnClick", function()
        local db = GetGroupDB(frame.selectedGroup)
        if not db then return end
        local current = db.color or {}
        local index = 0
        for i, color in ipairs(COLOR_PRESETS) do
            if math.abs((current[1] or 0) - color[1]) < 0.01
                and math.abs((current[2] or 0) - color[2]) < 0.01
                and math.abs((current[3] or 0) - color[3]) < 0.01 then
                index = i
                break
            end
        end
        index = index + 1
        if index > #COLOR_PRESETS then index = 1 end
        db.color = ns.DeepCopy(COLOR_PRESETS[index])
        ApplyConfig("style:" .. frame.selectedGroup .. ":color")
        frame:RefreshStyleControls()
    end)

    local growButton = UI:CreateButton(style, 180, 28, "Grow Direction")
    growButton:SetPoint("TOPLEFT", style, "TOPLEFT", 588, -212)
    growButton:SetScript("OnClick", function()
        local db = GetGroupDB(frame.selectedGroup)
        if not db then return end
        local index = 1
        for i, value in ipairs(GROW_DIRECTIONS) do
            if value == db.growDirection then index = i break end
        end
        index = index + 1
        if index > #GROW_DIRECTIONS then index = 1 end
        db.growDirection = GROW_DIRECTIONS[index]
        ApplyConfig("style:" .. frame.selectedGroup .. ":grow")
        frame:RefreshStyleControls()
    end)

    local tankOnlyButton = UI:CreateButton(style, 180, 28, "Tank Only")
    tankOnlyButton:SetPoint("TOPLEFT", style, "TOPLEFT", 588, -248)
    tankOnlyButton:SetScript("OnClick", function()
        local db = GetGroupDB(frame.selectedGroup)
        if not db then return end
        db.tankOnly = not db.tankOnly
        ApplyConfig("style:" .. frame.selectedGroup .. ":tankOnly")
        frame:RefreshStyleControls()
    end)

    local timeFormatButton = UI:CreateButton(style, 180, 28, "Time Format")
    timeFormatButton:SetPoint("TOPLEFT", style, "TOPLEFT", 588, -284)
    timeFormatButton:SetScript("OnClick", function()
        local db = GetGroupDB(frame.selectedGroup)
        if not db then return end
        local index = 1
        for i, value in ipairs(TIME_FORMATS) do
            if value == db.timeFormat then index = i break end
        end
        index = index + 1
        if index > #TIME_FORMATS then index = 1 end
        db.timeFormat = TIME_FORMATS[index]
        ApplyConfig("style:" .. frame.selectedGroup .. ":timeFormat")
        frame:RefreshStyleControls()
    end)

    local outlineButton = UI:CreateButton(style, 180, 28, "Font Outline")
    outlineButton:SetPoint("TOPLEFT", style, "TOPLEFT", 588, -320)
    outlineButton:SetScript("OnClick", function()
        local db = GetGroupDB(frame.selectedGroup)
        if not db then return end
        local current = tostring(db.fontOutline or "OUTLINE"):upper()
        local index = 1
        for i, value in ipairs(FONT_OUTLINES) do
            if value == current then index = i break end
        end
        index = index + 1
        if index > #FONT_OUTLINES then index = 1 end
        db.fontOutline = FONT_OUTLINES[index] == "NONE" and "" or FONT_OUTLINES[index]
        ApplyConfig("style:" .. frame.selectedGroup .. ":outline")
        frame:RefreshStyleControls()
    end)

    local separatorButton = UI:CreateButton(style, 180, 28, "Target Separator")
    separatorButton:SetPoint("TOPLEFT", style, "TOPLEFT", 588, -356)
    separatorButton:SetScript("OnClick", function()
        local db = GetGroupDB(frame.selectedGroup)
        if not db then return end
        local current = tostring(db.targetSeparator or " > ")
        local index = 1
        for i, value in ipairs(TARGET_SEPARATORS) do
            if value == current then index = i break end
        end
        index = index + 1
        if index > #TARGET_SEPARATORS then index = 1 end
        db.targetSeparator = TARGET_SEPARATORS[index]
        ApplyConfig("style:" .. frame.selectedGroup .. ":sep")
        frame:RefreshStyleControls()
    end)

    local selectedInfo = CreateLine(style, "", 588, -400, 180)

    local spells = CreatePanel("spells")
    local spellsHeader = UI:CreateSectionHeader(spells, "Spells")
    spellsHeader:SetPoint("TOPLEFT", spells, "TOPLEFT", 18, -18)
    CreateLine(spells, "Spell editing uses standalone rules plus local overrides. The browser covers trash spells, boss events, boss mechanics, health thresholds, and private auras.", 18, -50, 730)
    local openBrowser = UI:CreateButton(spells, 180, 30, "Open Spell Browser")
    openBrowser:SetPoint("TOPLEFT", spells, "TOPLEFT", 18, -100)
    openBrowser:SetScript("OnClick", function()
        local module = Addon:GetModule("SpellBrowser")
        if module and module.Open then
            module:Open()
        end
    end)
    local selectedTipButton = UI:CreateButton(spells, 180, 30, "Selected Tip")
    selectedTipButton:SetPoint("LEFT", openBrowser, "RIGHT", 10, 0)
    selectedTipButton:SetScript("OnClick", function()
        local browser = Addon:GetModule("SpellBrowser")
        local row = browser and browser.GetSelectedRow and browser:GetSelectedRow() or nil
        if row and ns.SpellTooltip and ns.SpellTooltip.ShowForRow then
            ns.SpellTooltip:ShowForRow(row)
        else
            Addon:Print("Select a spell row in the browser first.")
        end
        frame:RefreshSpells()
    end)
    local hideTipButton = UI:CreateButton(spells, 180, 30, "Hide Tip")
    hideTipButton:SetPoint("LEFT", selectedTipButton, "RIGHT", 10, 0)
    hideTipButton:SetScript("OnClick", function()
        if ns.SpellTooltip and ns.SpellTooltip.Hide then
            ns.SpellTooltip:Hide()
        end
        frame:RefreshSpells()
    end)

    spells.statusLines = {}
    for i = 1, 3 do
        spells.statusLines[i] = CreateLine(spells, "", 18, -150 - ((i - 1) * 24), 730)
    end

    local spellTooltipControls = {}
    local spellTooltipValues = {}
    local function CreateSpellTooltipToggle(field, label, x, y, defaultEnabled)
        local button = CreateToggle(spells, x, y, 176, label, function()
            local db = Addon:GetModuleDB("SpellTooltip")
            if not db then
                return defaultEnabled ~= false
            end
            if defaultEnabled == false then
                return db[field] == true
            end
            return db[field] ~= false
        end, function(enabled)
            local db = Addon:GetModuleDB("SpellTooltip")
            if db then
                db[field] = enabled and true or false
                ApplyConfig("spellTooltip:" .. tostring(field))
            end
        end)
        spellTooltipControls[#spellTooltipControls + 1] = button
        return button
    end
    local function CreateSpellTooltipValue(x, y, label, key, step, minValue, maxValue)
        local control = CreateValueControl(spells, x, y, label, function()
            local db = Addon:GetModuleDB("SpellTooltip")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - step, step), minValue, maxValue)
                ApplyConfig("spellTooltip:" .. tostring(key))
                frame:RefreshSpells()
            end
        end, function()
            local db = Addon:GetModuleDB("SpellTooltip")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + step, step), minValue, maxValue)
                ApplyConfig("spellTooltip:" .. tostring(key))
                frame:RefreshSpells()
            end
        end)
        control.tooltipField = key
        spellTooltipValues[#spellTooltipValues + 1] = control
        return control
    end
    CreateSpellTooltipToggle("enabled", "Tooltip", 18, -238, true)
    CreateSpellTooltipToggle("showSpellIDs", "Show IDs", 208, -238, true)
    CreateSpellTooltipToggle("includeRightText", "Right Text", 398, -238, true)
    CreateSpellTooltipValue(18, -280, "Tip Lines", "maxLines", 1, 1, 12)
    CreateSpellTooltipValue(208, -280, "Tip Width", "width", 20, 360, 900)
    CreateSpellTooltipValue(398, -280, "Tip Height", "height", 20, 240, 700)

    local profile = CreatePanel("profile")
    local profileHeader = UI:CreateSectionHeader(profile, "Profile Exchange")
    profileHeader:SetPoint("TOPLEFT", profile, "TOPLEFT", 18, -18)
    CreateLine(profile, "Profile sharing uses bundled LibSerialize and LibDeflate. No external addon is required for compressed exports/imports.", 18, -50, 730)

    local profileLines = {}
    local profileToggles = {}
    local function CreateProfileToggle(x, y, width, label, getter, setter)
        local button = CreateToggle(profile, x, y, width, label, getter, setter)
        profileToggles[#profileToggles + 1] = button
        return button
    end

    local function ExportProfile(scope)
        local exchange = ns.ProfileExchange
        if not exchange or not exchange.Export then
            Addon:Print("|cffff6666Profile exchange unavailable.|r")
            return
        end
        local encoded, err, payload, codec = exchange:Export(scope)
        if encoded and exchange.ShowExportPopup then
            exchange:ShowExportPopup(encoded, payload, codec)
        else
            Addon:Print("|cffff6666Export failed:|r " .. tostring(err))
        end
        if frame.RefreshProfile then
            frame:RefreshProfile()
        end
    end

    local function ResetProfile(scope)
        local exchange = ns.ProfileExchange
        if not exchange or not exchange.ResetProfile then
            Addon:Print("|cffff6666Profile reset unavailable.|r")
            return
        end
        local ok, err, actualScope, keys = exchange:ResetProfile(scope)
        if ok then
            Addon:Print("Profile reset: " .. tostring(actualScope) .. " (" .. tostring(keys or 0) .. " sections).")
        else
            Addon:Print("|cffff6666Profile reset failed:|r " .. tostring(err))
        end
        if frame.RefreshTabs then
            frame:RefreshTabs()
        end
    end

    local function ConfirmProfileReset(scope, label)
        if not StaticPopupDialogs or not StaticPopup_Show then
            ResetProfile(scope)
            return
        end
        StaticPopupDialogs["DDINGUI_MYTHICPLUS_PROFILE_RESET"] = {
            text = "Reset profile scope: " .. tostring(label or scope) .. "?",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                ResetProfile(scope)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("DDINGUI_MYTHICPLUS_PROFILE_RESET")
    end

    local exportAll = UI:CreateButton(profile, 112, 30, "Export All")
    exportAll:SetPoint("TOPLEFT", profile, "TOPLEFT", 18, -100)
    exportAll:SetScript("OnClick", function() ExportProfile("all") end)

    local exportStyle = UI:CreateButton(profile, 112, 30, "Export Style")
    exportStyle:SetPoint("LEFT", exportAll, "RIGHT", 8, 0)
    exportStyle:SetScript("OnClick", function() ExportProfile("style") end)

    local exportRules = UI:CreateButton(profile, 112, 30, "Export Rules")
    exportRules:SetPoint("LEFT", exportStyle, "RIGHT", 8, 0)
    exportRules:SetScript("OnClick", function() ExportProfile("rules") end)

    local exportRoutes = UI:CreateButton(profile, 112, 30, "Export Routes")
    exportRoutes:SetPoint("LEFT", exportRules, "RIGHT", 8, 0)
    exportRoutes:SetScript("OnClick", function() ExportProfile("routes") end)

    local exportRuns = UI:CreateButton(profile, 112, 30, "Export Runs")
    exportRuns:SetPoint("LEFT", exportRoutes, "RIGHT", 8, 0)
    exportRuns:SetScript("OnClick", function() ExportProfile("runs") end)

    local importButton = UI:CreateButton(profile, 112, 30, "Import")
    importButton:SetPoint("LEFT", exportRuns, "RIGHT", 8, 0)
    importButton:SetScript("OnClick", function()
        local exchange = ns.ProfileExchange
        if exchange and exchange.ShowImportPopup then
            exchange:ShowImportPopup()
        else
            Addon:Print("|cffff6666Profile import unavailable.|r")
        end
        if frame.RefreshProfile then
            frame:RefreshProfile()
        end
    end)

    local resetStyle = UI:CreateButton(profile, 102, 30, "Reset Style")
    resetStyle:SetPoint("TOPLEFT", profile, "TOPLEFT", 18, -190)
    resetStyle:SetScript("OnClick", function() ConfirmProfileReset("style", "style") end)

    local resetRules = UI:CreateButton(profile, 102, 30, "Reset Rules")
    resetRules:SetPoint("LEFT", resetStyle, "RIGHT", 8, 0)
    resetRules:SetScript("OnClick", function() ConfirmProfileReset("rules", "rules") end)

    local resetRoutes = UI:CreateButton(profile, 102, 30, "Reset Routes")
    resetRoutes:SetPoint("LEFT", resetRules, "RIGHT", 8, 0)
    resetRoutes:SetScript("OnClick", function() ConfirmProfileReset("routes", "routes") end)

    local resetRuns = UI:CreateButton(profile, 102, 30, "Reset Runs")
    resetRuns:SetPoint("LEFT", resetRoutes, "RIGHT", 8, 0)
    resetRuns:SetScript("OnClick", function() ConfirmProfileReset("runs", "runs/history") end)

    local resetTrash = UI:CreateButton(profile, 102, 30, "Reset Trash")
    resetTrash:SetPoint("LEFT", resetRuns, "RIGHT", 8, 0)
    resetTrash:SetScript("OnClick", function() ConfirmProfileReset("trash", "trash cooldowns") end)

    local resetConfig = UI:CreateButton(profile, 102, 30, "Reset Config")
    resetConfig:SetPoint("LEFT", resetTrash, "RIGHT", 8, 0)
    resetConfig:SetScript("OnClick", function() ConfirmProfileReset("config", "all except style") end)

    local resetAll = UI:CreateButton(profile, 102, 30, "Reset All")
    resetAll:SetPoint("LEFT", resetConfig, "RIGHT", 8, 0)
    resetAll:SetScript("OnClick", function() ConfirmProfileReset("all", "full profile") end)

    CreateProfileToggle(18, -150, 176, "Exchange Enabled", function()
        local db = Addon:GetModuleDB("ProfileExchange")
        return db and db.enabled ~= false
    end, function(enabled)
        local db = Addon:GetModuleDB("ProfileExchange")
        if db then
            db.enabled = enabled and true or false
            ApplyConfig("profileExchange:enabled")
        end
    end)

    CreateProfileToggle(208, -150, 176, "Include Caches", function()
        local db = Addon:GetModuleDB("ProfileExchange")
        return db and db.includeCaches == true
    end, function(enabled)
        local db = Addon:GetModuleDB("ProfileExchange")
        if db then
            db.includeCaches = enabled and true or false
            ApplyConfig("profileExchange:includeCaches")
        end
    end)

    for i = 1, 6 do
        profileLines[i] = CreateLine(profile, "", 18, -250 - ((i - 1) * 28), 730)
    end
    local dungeon = CreatePanel("dungeon")
    local dungeonHeader = UI:CreateSectionHeader(dungeon, "Dungeon Data")
    dungeonHeader:SetPoint("TOPLEFT", dungeon, "TOPLEFT", 18, -18)
    dungeon.statusLines = {}
    for i = 1, 7 do
        dungeon.statusLines[i] = CreateLine(dungeon, "", 18, -50 - ((i - 1) * 28), 730)
    end
    local presetButton = UI:CreateButton(dungeon, 220, 30, "Cycle Boss Preset")
    presetButton:SetPoint("TOPLEFT", dungeon, "TOPLEFT", 18, -262)
    presetButton:SetScript("OnClick", function()
        if ns.DungeonData and ns.DungeonData.CycleBossPresetAuthor then
            local author = ns.DungeonData:CycleBossPresetAuthor()
            if author and ns.Config and ns.Config.ApplyOrQueue then
                ns.Config:ApplyOrQueue("bossPreset:" .. tostring(author))
            end
        end
        frame:RefreshDungeon()
    end)

    local dungeonTrackingHeader = UI:CreateSectionHeader(dungeon, "Tracking Options")
    dungeonTrackingHeader:SetPoint("TOPLEFT", dungeon, "TOPLEFT", 18, -312)
    local dungeonTrackingButtons = {}
    local dungeonValueControls = {}

    local function CreateDungeonToggle(moduleKey, field, label, x, y, defaultEnabled)
        local button = CreateToggle(dungeon, x, y, 176, label, function()
            local db = Addon:GetModuleDB(moduleKey)
            if not db then
                return defaultEnabled == true
            end
            if defaultEnabled == false then
                return db[field] == true
            end
            return db[field] ~= false
        end, function(enabled)
            local db = Addon:GetModuleDB(moduleKey)
            if db then
                db[field] = enabled and true or false
                ApplyConfig(moduleKey .. ":" .. field)
            end
        end)
        dungeonTrackingButtons[#dungeonTrackingButtons + 1] = button
        return button
    end

    local function CreateDungeonValueControl(moduleKey, x, y, label, key, step, minValue, maxValue)
        local control = CreateValueControl(dungeon, x, y, label, function()
            local db = Addon:GetModuleDB(moduleKey)
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - step, step), minValue, maxValue)
                ApplyConfig(moduleKey .. ":" .. key)
                frame:RefreshDungeon()
            end
        end, function()
            local db = Addon:GetModuleDB(moduleKey)
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + step, step), minValue, maxValue)
                ApplyConfig(moduleKey .. ":" .. key)
                frame:RefreshDungeon()
            end
        end)
        control.moduleKey = moduleKey
        control.moduleField = key
        dungeonValueControls[#dungeonValueControls + 1] = control
        return control
    end

    CreateDungeonToggle("DebuffTracker", "includeParty", "Debuff Party", 18, -344, true)
    CreateDungeonToggle("DebuffTracker", "includeTarget", "Debuff Target", 208, -344, false)
    CreateDungeonToggle("DebuffTracker", "includeNameplates", "Debuff Plates", 398, -344, false)
    CreateDungeonToggle("DebuffTracker", "includeHelpful", "Helpful Auras", 588, -344, false)

    CreateDungeonToggle("PrivateAuraTracker", "includeRaid", "Private Raid", 18, -382, true)
    CreateDungeonToggle("PrivateAuraTracker", "requireRules", "Require Rules", 208, -382, true)
    CreateDungeonToggle("PrivateAuraTracker", "showCountdown", "Aura Countdown", 398, -382, true)
    CreateDungeonToggle("PrivateAuraTracker", "showCountdownText", "Aura Text", 588, -382, true)

    CreateDungeonValueControl("DebuffTracker", 18, -426, "Debuff Scan", "scanInterval", 0.05, 0.05, 2.00)
    CreateDungeonValueControl("PrivateAuraTracker", 208, -426, "Aura Slots", "maxIcons", 1, 1, 10)
    CreateDungeonValueControl("PartyFrameGlow", 398, -426, "Glow Prio", "priorityMin", 5, 0, 100)
    CreateDungeonValueControl("PartyFrameGlow", 588, -426, "Glow Sec", "duration", 1, 1, 20)
    CreateDungeonToggle("AffixTracker", "showWeekly", "Weekly Affix", 18, -470, true)
    CreateDungeonToggle("AffixTracker", "scanAuras", "Affix Auras", 208, -470, true)
    CreateDungeonToggle("AffixTracker", "includeNameplates", "Affix Plates", 398, -470, true)
    CreateDungeonValueControl("AffixTracker", 588, -470, "Affix Scan", "scanInterval", 0.05, 0.05, 2.00)
    CreateDungeonValueControl("PartyFrameGlow", 18, -514, "Glow Lines", "lines", 1, 1, 30)
    CreateDungeonValueControl("PartyFrameGlow", 208, -514, "Glow Freq", "frequency", 0.05, 0.10, 5.00)
    CreateDungeonValueControl("PartyFrameGlow", 398, -514, "Glow Scale", "scale", 0.10, 0.50, 4.00)
    CreateDungeonValueControl("PartyFrameGlow", 588, -514, "Glow Off", "offset", 1, -20, 20)
    CreateDungeonToggle("PrivateAuraTracker", "sounds", "Aura Sounds", 18, -558, false)
    local privateAuraChannelButton = UI:CreateButton(dungeon, 176, 26, "Aura Ch")
    privateAuraChannelButton:SetPoint("TOPLEFT", dungeon, "TOPLEFT", 208, -558)
    privateAuraChannelButton:SetScript("OnClick", function()
        local module = ns.PrivateAuraTracker
        if module and module.CycleChannel then
            module:CycleChannel(1)
            ApplyConfig("PrivateAuraTracker:channel")
        end
        frame:RefreshDungeon()
    end)

    local info = CreatePanel("info")
    local infoHeader = UI:CreateSectionHeader(info, "Keystone Overview")
    infoHeader:SetPoint("TOPLEFT", info, "TOPLEFT", 18, -18)
    info.lines = {}
    for i = 1, 12 do
        info.lines[i] = CreateLine(info, "", 18, -50 - ((i - 1) * 28), 730)
    end

    local infoControls = {}
    local infoModuleControls = {}
    local infoValueControls = {}
    local function CreateInfoToggle(field, label, x, y, defaultEnabled, width)
        local button = CreateToggle(info, x, y, width or 176, label, function()
            local db = Addon:GetModuleDB("KeystoneInfo")
            if not db then
                return defaultEnabled ~= false
            end
            if defaultEnabled == false then
                return db[field] == true
            end
            return db[field] ~= false
        end, function(enabled)
            local db = Addon:GetModuleDB("KeystoneInfo")
            if db then
                db[field] = enabled and true or false
                ApplyConfig("keystoneInfo:" .. field)
            end
        end)
        infoControls[#infoControls + 1] = button
        return button
    end

    local function CreateInfoModuleToggle(moduleName, field, label, x, y, defaultEnabled, width)
        local button = CreateToggle(info, x, y, width or 176, label, function()
            local db = Addon:GetModuleDB(moduleName)
            if not db then
                return defaultEnabled ~= false
            end
            if defaultEnabled == false then
                return db[field] == true
            end
            return db[field] ~= false
        end, function(enabled)
            local db = Addon:GetModuleDB(moduleName)
            if db then
                db[field] = enabled and true or false
                ApplyConfig(tostring(moduleName) .. ":" .. tostring(field))
            end
        end)
        infoModuleControls[#infoModuleControls + 1] = button
        return button
    end

    local function CreateInfoValueControl(moduleName, x, y, label, key, step, minValue, maxValue, width)
        local control = CreateValueControl(info, x, y, label, function()
            local db = Addon:GetModuleDB(moduleName)
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - step, step), minValue, maxValue)
                ApplyConfig(tostring(moduleName) .. ":" .. tostring(key))
                frame:RefreshInfo()
            end
        end, function()
            local db = Addon:GetModuleDB(moduleName)
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + step, step), minValue, maxValue)
                ApplyConfig(tostring(moduleName) .. ":" .. tostring(key))
                frame:RefreshInfo()
            end
        end, width)
        control.infoModule = moduleName
        control.infoField = key
        infoValueControls[#infoValueControls + 1] = control
        return control
    end

    local refreshInfoButton = UI:CreateButton(info, 82, 30, "Refresh")
    refreshInfoButton:SetPoint("TOPLEFT", info, "TOPLEFT", 18, -400)
    refreshInfoButton:SetScript("OnClick", function()
        if ns.KeystoneInfo and ns.KeystoneInfo.BuildSnapshot then
            ns.KeystoneInfo:BuildSnapshot()
        end
        frame:RefreshInfo()
    end)

    local printInfoButton = UI:CreateButton(info, 82, 30, "Print")
    printInfoButton:SetPoint("LEFT", refreshInfoButton, "RIGHT", 8, 0)
    printInfoButton:SetScript("OnClick", function()
        if ns.KeystoneInfo and ns.KeystoneInfo.Print then
            ns.KeystoneInfo:Print()
        end
    end)

    local guideInfoButton = UI:CreateButton(info, 82, 30, "Guide")
    guideInfoButton:SetPoint("LEFT", printInfoButton, "RIGHT", 8, 0)
    guideInfoButton:SetScript("OnClick", function()
        if ns.EncounterGuide and ns.EncounterGuide.Open then
            ns.EncounterGuide:Open()
        end
        frame:RefreshInfo()
    end)

    local briefInfoButton = UI:CreateButton(info, 82, 30, "Brief")
    briefInfoButton:SetPoint("LEFT", guideInfoButton, "RIGHT", 8, 0)
    briefInfoButton:SetScript("OnClick", function()
        if ns.KeystoneInfo and ns.KeystoneInfo.PrintBrief then
            ns.KeystoneInfo:PrintBrief(nil, 6)
        end
    end)

    local copyInfoButton = UI:CreateButton(info, 82, 30, "Copy")
    copyInfoButton:SetPoint("LEFT", briefInfoButton, "RIGHT", 8, 0)
    copyInfoButton:SetScript("OnClick", function()
        if ns.KeystoneInfo and ns.KeystoneInfo.ShowBriefPopup then
            ns.KeystoneInfo:ShowBriefPopup(nil, 6)
        end
    end)

    local riskInfoButton = UI:CreateButton(info, 82, 30, "Risks")
    riskInfoButton:SetPoint("LEFT", copyInfoButton, "RIGHT", 8, 0)
    riskInfoButton:SetScript("OnClick", function()
        if ns.KeystoneInfo and ns.KeystoneInfo.PrintRisks then
            ns.KeystoneInfo:PrintRisks(nil, 6)
        end
    end)

    local assignInfoButton = UI:CreateButton(info, 82, 30, "Assign")
    assignInfoButton:SetPoint("LEFT", riskInfoButton, "RIGHT", 8, 0)
    assignInfoButton:SetScript("OnClick", function()
        if ns.AssignmentPlanner and ns.AssignmentPlanner.ShowAddPopup then
            ns.AssignmentPlanner:ShowAddPopup()
        end
        frame:RefreshInfo()
    end)

    local splitInfoButton = UI:CreateButton(info, 82, 30, "Splits")
    splitInfoButton:SetPoint("LEFT", assignInfoButton, "RIGHT", 8, 0)
    splitInfoButton:SetScript("OnClick", function()
        if ns.EncounterSplitTracker and ns.EncounterSplitTracker.PrintSummary then
            ns.EncounterSplitTracker:PrintSummary(nil, 6)
        end
        frame:RefreshInfo()
    end)

    CreateInfoToggle("enabled", "Keystone", 18, -448, true, 138)
    CreateInfoToggle("includeAffixes", "Affixes", 164, -448, true, 138)
    CreateInfoToggle("includeDataCoverage", "Data", 310, -448, true, 138)
    CreateInfoToggle("includeRouteStatus", "Routes", 456, -448, true, 138)
    CreateInfoToggle("includeRunHistory", "Runs", 602, -448, true, 138)
    CreateInfoToggle("announceOnChallengeStart", "Start Print", 18, -486, false, 138)
    CreateInfoModuleToggle("EncounterGuide", "selectOnEncounterStart", "Auto Sel", 164, -486, true, 138)
    CreateInfoModuleToggle("EncounterGuide", "advanceOnEncounterEnd", "Auto Adv", 310, -486, true, 138)
    CreateInfoModuleToggle("EncounterGuide", "printOnEncounterStart", "Print Start", 456, -486, false, 138)
    CreateInfoModuleToggle("EncounterGuide", "showOnChallengeStart", "Start Guide", 602, -486, false, 138)
    CreateInfoModuleToggle("AssignmentPlanner", "showInGuide", "Assign Guide", 18, -524, true, 138)
    CreateInfoModuleToggle("AssignmentPlanner", "announceToChat", "Assign Chat", 164, -524, true, 138)
    CreateInfoModuleToggle("EncounterSplitTracker", "announceToChat", "Split Chat", 310, -524, false, 138)
    CreateInfoModuleToggle("EncounterSplitTracker", "showAlert", "Split Alert", 456, -524, false, 138)
    CreateInfoModuleToggle("EncounterSplitTracker", "recordFailed", "Record Fail", 602, -524, true, 138)
    CreateInfoValueControl("EncounterGuide", 18, -562, "Guide Events", "timelineRows", 1, 1, 12, 138)
    CreateInfoValueControl("EncounterGuide", 164, -562, "Live Rows", "liveRows", 1, 0, 6, 138)
    CreateInfoValueControl("AssignmentPlanner", 310, -562, "Assign Rows", "guideRows", 1, 1, 8, 138)
    CreateInfoValueControl("AssignmentPlanner", 456, -562, "Max Assigns", "maxAssignments", 1, 1, 200, 138)
    CreateInfoValueControl("EncounterSplitTracker", 602, -562, "Max Splits", "maxSplits", 1, 1, 100, 138)

    local routes = CreatePanel("routes")
    local routesHeader = UI:CreateSectionHeader(routes, "Route Notes")
    routesHeader:SetPoint("TOPLEFT", routes, "TOPLEFT", 18, -18)
    routes.lines = {}
    for i = 1, 8 do
        routes.lines[i] = CreateLine(routes, "", 18, -50 - ((i - 1) * 28), 730)
    end

    local routeControls = {}
    local routeValueControls = {}
    local function CreateRouteToggle(field, label, x, y, defaultEnabled)
        local button = CreateToggle(routes, x, y, 176, label, function()
            local db = Addon:GetModuleDB("RouteNotes")
            if not db then
                return defaultEnabled ~= false
            end
            if defaultEnabled == false then
                return db[field] == true
            end
            return db[field] ~= false
        end, function(enabled)
            local db = Addon:GetModuleDB("RouteNotes")
            if db then
                db[field] = enabled and true or false
                ApplyConfig("routeNotes:" .. field)
            end
        end)
        routeControls[#routeControls + 1] = button
        return button
    end

    local function CreateRouteValueControl(x, y, label, key, step, minValue, maxValue)
        local control = CreateValueControl(routes, x, y, label, function()
            local db = Addon:GetModuleDB("RouteNotes")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - step, step), minValue, maxValue)
                ApplyConfig("routeNotes:" .. key)
                frame:RefreshRoutes()
            end
        end, function()
            local db = Addon:GetModuleDB("RouteNotes")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + step, step), minValue, maxValue)
                ApplyConfig("routeNotes:" .. key)
                frame:RefreshRoutes()
            end
        end)
        control.routeField = key
        routeValueControls[#routeValueControls + 1] = control
        return control
    end

    local showRouteButton = UI:CreateButton(routes, 144, 30, "Show Current")
    showRouteButton:SetPoint("TOPLEFT", routes, "TOPLEFT", 18, -292)
    showRouteButton:SetScript("OnClick", function()
        if ns.RouteNotes and ns.RouteNotes.Show then
            ns.RouteNotes:Show()
        end
        frame:RefreshRoutes()
    end)

    local prevRouteButton = UI:CreateButton(routes, 108, 30, "Previous")
    prevRouteButton:SetPoint("LEFT", showRouteButton, "RIGHT", 10, 0)
    prevRouteButton:SetScript("OnClick", function()
        if ns.RouteNotes and ns.RouteNotes.Prev then
            ns.RouteNotes:Prev()
        end
        frame:RefreshRoutes()
    end)

    local nextRouteButton = UI:CreateButton(routes, 108, 30, "Next")
    nextRouteButton:SetPoint("LEFT", prevRouteButton, "RIGHT", 10, 0)
    nextRouteButton:SetScript("OnClick", function()
        if ns.RouteNotes and ns.RouteNotes.Next then
            ns.RouteNotes:Next()
        end
        frame:RefreshRoutes()
    end)

    local clearRouteButton = UI:CreateButton(routes, 132, 30, "Clear Notes")
    clearRouteButton:SetPoint("LEFT", nextRouteButton, "RIGHT", 10, 0)
    clearRouteButton:SetScript("OnClick", function()
        if ns.RouteNotes and ns.RouteNotes.ClearNotes then
            local count = ns.RouteNotes:ClearNotes()
            Addon:Print("Route notes cleared: " .. tostring(count))
        end
        frame:RefreshRoutes()
    end)

    local routeBrowserButton = UI:CreateButton(routes, 144, 30, "Open Spells")
    routeBrowserButton:SetPoint("LEFT", clearRouteButton, "RIGHT", 10, 0)
    routeBrowserButton:SetScript("OnClick", function()
        local module = Addon:GetModule("SpellBrowser")
        if module and module.Open then
            module:Open()
        end
    end)

    local routeMapButton = UI:CreateButton(routes, 78, 30, "Map")
    routeMapButton:SetPoint("LEFT", routeBrowserButton, "RIGHT", 8, 0)
    routeMapButton:SetScript("OnClick", function()
        if ns.RouteMap and ns.RouteMap.Toggle then
            ns.RouteMap:Toggle()
        end
        frame:RefreshRoutes()
    end)

    CreateRouteToggle("enabled", "Route Notes", 18, -344, true)
    CreateRouteToggle("showOnChallengeStart", "Start Alert", 208, -344, true)
    CreateRouteToggle("announceToChat", "Chat Print", 398, -344, true)
    CreateRouteToggle("showCenterAlert", "Center Alert", 588, -344, true)
    CreateRouteToggle("onlyInChallenge", "M+ Only", 18, -382, false)
    CreateRouteValueControl(208, -382, "Max Notes", "maxNotes", 1, 1, 120)
    CreateRouteValueControl(398, -382, "Alert Sec", "alertDuration", 0.25, 0.50, 10.00)
    local overlayButton = UI:CreateButton(routes, 132, 30, "Overlay")
    overlayButton:SetPoint("TOPLEFT", routes, "TOPLEFT", 588, -382)
    overlayButton:SetScript("OnClick", function()
        if ns.RouteOverlay and ns.RouteOverlay.Toggle then
            ns.RouteOverlay:Toggle()
        end
        frame:RefreshRoutes()
    end)

    local pullHeader = UI:CreateSectionHeader(routes, "Pull Preview")
    pullHeader:SetPoint("TOPLEFT", routes, "TOPLEFT", 18, -430)
    routes.pullLines = {}
    for i = 1, 3 do
        routes.pullLines[i] = CreateLine(routes, "", 18, -456 - ((i - 1) * 24), 730)
    end
    local pullControls = {}
    local pullValueControls = {}

    local function CreatePullToggle(field, label, x, y, defaultEnabled)
        local button = CreateToggle(routes, x, y, 176, label, function()
            local db = Addon:GetModuleDB("PullPlanner")
            if not db then
                return defaultEnabled ~= false
            end
            if defaultEnabled == false then
                return db[field] == true
            end
            return db[field] ~= false
        end, function(enabled)
            local db = Addon:GetModuleDB("PullPlanner")
            if db then
                db[field] = enabled and true or false
                ApplyConfig("pullPlanner:" .. field)
            end
        end)
        pullControls[#pullControls + 1] = button
        return button
    end

    local function CreatePullValueControl(x, y, label, key, step, minValue, maxValue)
        local control = CreateValueControl(routes, x, y, label, function()
            local db = Addon:GetModuleDB("PullPlanner")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - step, step), minValue, maxValue)
                ApplyConfig("pullPlanner:" .. key)
                frame:RefreshRoutes()
            end
        end, function()
            local db = Addon:GetModuleDB("PullPlanner")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + step, step), minValue, maxValue)
                ApplyConfig("pullPlanner:" .. key)
                frame:RefreshRoutes()
            end
        end)
        control.pullField = key
        pullValueControls[#pullValueControls + 1] = control
        return control
    end

    local pullShowButton = UI:CreateButton(routes, 118, 28, "Show Pull")
    pullShowButton:SetPoint("TOPLEFT", routes, "TOPLEFT", 18, -526)
    pullShowButton:SetScript("OnClick", function()
        if ns.PullPlanner and ns.PullPlanner.Show then
            ns.PullPlanner:Show()
        end
        frame:RefreshRoutes()
    end)
    local pullPrevButton = UI:CreateButton(routes, 92, 28, "Prev")
    pullPrevButton:SetPoint("LEFT", pullShowButton, "RIGHT", 8, 0)
    pullPrevButton:SetScript("OnClick", function()
        if ns.PullPlanner and ns.PullPlanner.Prev then
            ns.PullPlanner:Prev()
        end
        frame:RefreshRoutes()
    end)
    local pullNextButton = UI:CreateButton(routes, 92, 28, "Next")
    pullNextButton:SetPoint("LEFT", pullPrevButton, "RIGHT", 8, 0)
    pullNextButton:SetScript("OnClick", function()
        if ns.PullPlanner and ns.PullPlanner.Next then
            ns.PullPlanner:Next()
        end
        frame:RefreshRoutes()
    end)
    local pullClearButton = UI:CreateButton(routes, 112, 28, "Clear Pulls")
    pullClearButton:SetPoint("LEFT", pullNextButton, "RIGHT", 8, 0)
    pullClearButton:SetScript("OnClick", function()
        if ns.PullPlanner and ns.PullPlanner.ClearPulls then
            local count = ns.PullPlanner:ClearPulls()
            Addon:Print("Pull previews cleared: " .. tostring(count))
        end
        frame:RefreshRoutes()
    end)

    CreatePullToggle("enabled", "Pull Preview", 472, -526, true)
    CreatePullToggle("includeGeneralCasts", "All Casts", 18, -560, false)
    CreatePullValueControl(208, -560, "Min Prio", "minPriority", 5, 0, 100)
    CreatePullValueControl(398, -560, "Rows/Pull", "rowsPerPull", 1, 1, 12)
    CreatePullValueControl(588, -560, "Max Rows", "maxGeneratedRows", 5, 5, 120)

    local runs = CreatePanel("runs")
    local runsHeader = UI:CreateSectionHeader(runs, "Run History")
    runsHeader:SetPoint("TOPLEFT", runs, "TOPLEFT", 18, -18)
    runs.lines = {}
    for i = 1, 11 do
        runs.lines[i] = CreateLine(runs, "", 18, -50 - ((i - 1) * 28), 730)
    end

    local runControls = {}
    local runValueControls = {}
    local deathControls = {}
    local deathValueControls = {}
    local function CreateRunToggle(field, label, x, y, defaultEnabled)
        local button = CreateToggle(runs, x, y, 176, label, function()
            local db = Addon:GetModuleDB("RunHistory")
            if not db then
                return defaultEnabled ~= false
            end
            if defaultEnabled == false then
                return db[field] == true
            end
            return db[field] ~= false
        end, function(enabled)
            local db = Addon:GetModuleDB("RunHistory")
            if db then
                db[field] = enabled and true or false
                ApplyConfig("runHistory:" .. field)
            end
        end)
        runControls[#runControls + 1] = button
        return button
    end

    local function CreateRunValueControl(x, y, label, key, step, minValue, maxValue)
        local control = CreateValueControl(runs, x, y, label, function()
            local db = Addon:GetModuleDB("RunHistory")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - step, step), minValue, maxValue)
                ApplyConfig("runHistory:" .. key)
                frame:RefreshRuns()
            end
        end, function()
            local db = Addon:GetModuleDB("RunHistory")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + step, step), minValue, maxValue)
                ApplyConfig("runHistory:" .. key)
                frame:RefreshRuns()
            end
        end)
        control.runField = key
        runValueControls[#runValueControls + 1] = control
        return control
    end

    local function CreateDeathToggle(field, label, x, y, defaultEnabled)
        local button = CreateToggle(runs, x, y, 176, label, function()
            local db = Addon:GetModuleDB("DeathTracker")
            if not db then
                return defaultEnabled ~= false
            end
            if defaultEnabled == false then
                return db[field] == true
            end
            return db[field] ~= false
        end, function(enabled)
            local db = Addon:GetModuleDB("DeathTracker")
            if db then
                db[field] = enabled and true or false
                ApplyConfig("deathTracker:" .. field)
            end
        end)
        deathControls[#deathControls + 1] = button
        return button
    end

    local function CreateDeathValueControl(x, y, label, key, step, minValue, maxValue)
        local control = CreateValueControl(runs, x, y, label, function()
            local db = Addon:GetModuleDB("DeathTracker")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) - step, step), minValue, maxValue)
                ApplyConfig("deathTracker:" .. key)
                frame:RefreshRuns()
            end
        end, function()
            local db = Addon:GetModuleDB("DeathTracker")
            if db then
                db[key] = Clamp(Round((tonumber(db[key]) or 0) + step, step), minValue, maxValue)
                ApplyConfig("deathTracker:" .. key)
                frame:RefreshRuns()
            end
        end)
        control.deathField = key
        deathValueControls[#deathValueControls + 1] = control
        return control
    end

    local clearRunsButton = UI:CreateButton(runs, 144, 30, "Clear History")
    clearRunsButton:SetPoint("TOPLEFT", runs, "TOPLEFT", 18, -344)
    clearRunsButton:SetScript("OnClick", function()
        if ns.RunHistory and ns.RunHistory.ClearHistory then
            local count = ns.RunHistory:ClearHistory()
            Addon:Print("Run history cleared: " .. tostring(count))
        end
        frame:RefreshRuns()
    end)

    local printRunsButton = UI:CreateButton(runs, 144, 30, "Print Recent")
    printRunsButton:SetPoint("LEFT", clearRunsButton, "RIGHT", 10, 0)
    printRunsButton:SetScript("OnClick", function()
        local history = ns.RunHistory and ns.RunHistory.GetHistory and ns.RunHistory:GetHistory(5) or {}
        if #history == 0 then
            Addon:Print("Run history is empty.")
            return
        end
        for index, run in ipairs(history) do
            Addon:Print("Run #" .. tostring(index) .. ": " .. ns.RunHistory:FormatRun(run))
        end
    end)

    local copyRunButton = UI:CreateButton(runs, 144, 30, "Copy Report")
    copyRunButton:SetPoint("LEFT", printRunsButton, "RIGHT", 10, 0)
    copyRunButton:SetScript("OnClick", function()
        if ns.RunHistory and ns.RunHistory.ShowReportPopup then
            ns.RunHistory:ShowReportPopup("last", 8)
        end
    end)

    local summaryRunsButton = UI:CreateButton(runs, 144, 30, "Print Summary")
    summaryRunsButton:SetPoint("LEFT", copyRunButton, "RIGHT", 10, 0)
    summaryRunsButton:SetScript("OnClick", function()
        if ns.RunHistory and ns.RunHistory.PrintSummary then
            ns.RunHistory:PrintSummary("all", 6)
        end
        frame:RefreshRuns()
    end)

    local deathSummaryButton = UI:CreateButton(runs, 144, 30, "Death Summary")
    deathSummaryButton:SetPoint("LEFT", summaryRunsButton, "RIGHT", 10, 0)
    deathSummaryButton:SetScript("OnClick", function()
        if ns.RunHistory and ns.RunHistory.PrintDeathSummary then
            ns.RunHistory:PrintDeathSummary("all", 8)
        end
        frame:RefreshRuns()
    end)

    local encounterSummaryButton = UI:CreateButton(runs, 144, 30, "Boss Summary")
    encounterSummaryButton:SetPoint("TOPLEFT", runs, "TOPLEFT", 18, -382)
    encounterSummaryButton:SetScript("OnClick", function()
        if ns.RunHistory and ns.RunHistory.PrintEncounterSummary then
            ns.RunHistory:PrintEncounterSummary("all", 8)
        end
        frame:RefreshRuns()
    end)

    local compareRunsButton = UI:CreateButton(runs, 144, 30, "Compare Best")
    compareRunsButton:SetPoint("LEFT", encounterSummaryButton, "RIGHT", 10, 0)
    compareRunsButton:SetScript("OnClick", function()
        if ns.RunHistory and ns.RunHistory.PrintComparison then
            ns.RunHistory:PrintComparison("last")
        end
        frame:RefreshRuns()
    end)

    local openDeathsButton = UI:CreateButton(runs, 144, 30, "Open Deaths")
    openDeathsButton:SetPoint("LEFT", compareRunsButton, "RIGHT", 10, 0)
    openDeathsButton:SetScript("OnClick", function()
        if ns.DeathTracker and ns.DeathTracker.Open then
            ns.DeathTracker:Open()
        end
        frame:RefreshRuns()
    end)

    local printDeathsButton = UI:CreateButton(runs, 144, 30, "Print Deaths")
    printDeathsButton:SetPoint("LEFT", openDeathsButton, "RIGHT", 10, 0)
    printDeathsButton:SetScript("OnClick", function()
        if ns.DeathTracker and ns.DeathTracker.Print then
            ns.DeathTracker:Print(8)
        end
        frame:RefreshRuns()
    end)

    local clearDeathsButton = UI:CreateButton(runs, 144, 30, "Clear Deaths")
    clearDeathsButton:SetPoint("LEFT", printDeathsButton, "RIGHT", 10, 0)
    clearDeathsButton:SetScript("OnClick", function()
        if ns.DeathTracker and ns.DeathTracker.ClearRecent then
            local count = ns.DeathTracker:ClearRecent()
            Addon:Print("Recent deaths cleared: " .. tostring(count))
        end
        frame:RefreshRuns()
    end)

    CreateRunToggle("enabled", "Run History", 18, -424, true)
    CreateRunToggle("recordResets", "Record Resets", 208, -424, true)
    CreateRunToggle("announceToChat", "Chat Print", 398, -424, true)
    CreateRunToggle("showCompletionAlert", "Finish Alert", 588, -424, true)
    CreateRunValueControl(18, -462, "Max Runs", "maxRuns", 1, 1, 100)

    CreateDeathToggle("enabled", "Deaths", 18, -510, true)
    CreateDeathToggle("announceToChat", "Death Chat", 208, -510, true)
    CreateDeathToggle("showAlert", "Death Alert", 398, -510, true)
    CreateDeathToggle("detectWipes", "Wipe Detect", 588, -510, true)
    CreateDeathValueControl(18, -550, "Max Deaths", "maxRecent", 1, 1, 50)
    CreateDeathValueControl(208, -550, "Poll", "pollInterval", 0.1, 0.2, 5)
    CreateDeathValueControl(398, -550, "Wipe %", "wipeDeadPercent", 0.05, 0.2, 1)
    CreateDeathValueControl(588, -550, "Wipe CD", "wipeCooldown", 1, 3, 120)

    local debug = CreatePanel("debug")
    local debugHeader = UI:CreateSectionHeader(debug, "Debug")
    debugHeader:SetPoint("TOPLEFT", debug, "TOPLEFT", 18, -18)
    debug.lines = {}
    for i = 1, 20 do
        debug.lines[i] = CreateLine(debug, "", 18, -50 - ((i - 1) * 28), 740)
    end

    local edit = UI:CreateButton(frame, 126, 30, L["EDIT_MODE"])
    edit:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 26, 22)
    edit:SetScript("OnClick", function()
        ns.ToggleEditMode()
        frame:RefreshTabs()
    end)

    local test = UI:CreateButton(frame, 116, 30, L["TEST_ALERT"])
    test:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    test:SetScript("OnClick", function()
        if ns.Display then
            ns.Display:ShowCenterAlert({ name = "ADDS > 6", icon = 136116, duration = 1.6 })
            ns.Display:ApplyPreview("kickCC")
            ns.Display:ApplyPreview("generalCast")
            ns.Display:ApplyPreview("special")
            ns.Display:ApplyPreview("tankbusterCD")
            ns.Display:ApplyPreview("tankbusterIncoming")
            ns.Display:ApplyPreview("debuffIcons")
            ns.Display:ApplyPreview("misc")
            ns.Display:ApplyPreview("affix")
        end
        if ns.CountdownDisplay and ns.CountdownDisplay.Preview then
            ns.CountdownDisplay:Preview()
        end
        if ns.RingProgress and ns.RingProgress.Preview then
            ns.RingProgress:Preview()
        end
        if ns.CastProgressBar and ns.CastProgressBar.Preview then
            ns.CastProgressBar:Preview()
        end
        if ns.BunBar and ns.BunBar.Preview then
            ns.BunBar:Preview()
        end
    end)

    local close = UI:CreateButton(frame, 110, 30, L["CLOSE"])
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 22)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    function frame:RefreshStyleControls()
        for _, button in ipairs(styleTargetButtons) do
            SetButtonState(button, button.groupKey == self.selectedGroup)
        end
        local db = GetGroupDB(self.selectedGroup)
        for _, control in ipairs(styleControls) do
            local key = FIELD_MAP[control.field]
            control.value:SetText(FormatValue(db and db[key]))
        end
        growButton.text:SetText("Grow: " .. tostring(db and db.growDirection or "DOWN"))
        tankOnlyButton.text:SetText((db and db.tankOnly) and "|cff88ff88Tank Only|r" or "|cffaaaaaaAll Roles|r")
        timeFormatButton.text:SetText("Time: " .. tostring(db and db.timeFormat or "remaining"))
        local outline = db and tostring(db.fontOutline or "") or "OUTLINE"
        if outline == "" then
            outline = "NONE"
        end
        outlineButton.text:SetText("Outline: " .. outline)
        separatorButton.text:SetText("Sep: " .. tostring(db and db.targetSeparator or " > "))
        selectedInfo:SetText((db and db.label or self.selectedGroup)
            .. "\nTexture: " .. tostring(db and db.barTexture or "n/a")
            .. "\nTime: " .. tostring(db and db.timeFormat or "remaining")
            .. "\nOutline: " .. outline
            .. "\nSep: " .. tostring(db and db.targetSeparator or " > ")
            .. "\nColor: " .. FormatValue(db and db.color and db.color[1]) .. ", "
            .. FormatValue(db and db.color and db.color[2]) .. ", "
            .. FormatValue(db and db.color and db.color[3]))
    end

    function frame:RefreshRuntimeControls()
        local runtime = ns.db and ns.db.profile and ns.db.profile.runtime or {}
        for _, button in ipairs(runtimeToggleButtons) do
            if button.Refresh then
                button:Refresh()
            end
        end
        for _, control in ipairs(runtimeControls) do
            control.value:SetText(FormatValue(runtime[control.runtimeKey]))
        end
        for _, control in ipairs(moduleValueControls) do
            local db = Addon:GetModuleDB(control.moduleKey)
            if control.formatPercent then
                local value = tonumber(db and db[control.moduleField]) or 0
                control.value:SetText(string.format("%.0f%%", value * 100))
            else
                control.value:SetText(FormatValue(db and db[control.moduleField]))
            end
        end
        local globalMode = ns.GlobalSettings and ns.GlobalSettings.GetBarMode and ns.GlobalSettings:GetBarMode() or "both"
        barModeButton.text:SetText("Bars: " .. tostring(globalMode))
        local voiceChannel = ns.Voice and ns.Voice.GetChannel and ns.Voice:GetChannel()
            or (Addon:GetModuleDB("Voice") or {}).channel
            or "Master"
        voiceChannelButton.text:SetText("Voice: " .. tostring(voiceChannel))
    end

    function frame:RefreshDungeon()
        local status = ns.DataProvider and ns.DataProvider:GetStatus() or {}
        local dataLines = ns.DataProvider and ns.DataProvider.BuildStatusLines and ns.DataProvider:BuildStatusLines() or {}
        for index = 1, #dungeon.statusLines do
            dungeon.statusLines[index]:SetText(dataLines[index] or "")
        end
        presetButton.text:SetText("Boss Preset: "
            .. tostring(status.bossPresetAuthor or "none")
            .. " (" .. tostring(status.bossPresetSource or "n/a")
            .. ", " .. tostring(status.bossPresetAuthors or 0) .. ")")
        for _, button in ipairs(dungeonTrackingButtons) do
            if button.Refresh then
                button:Refresh()
            end
        end
        for _, control in ipairs(dungeonValueControls) do
            local db = Addon:GetModuleDB(control.moduleKey)
            control.value:SetText(FormatValue(db and db[control.moduleField]))
        end
        local privateAuraChannel = ns.PrivateAuraTracker and ns.PrivateAuraTracker.GetChannel and ns.PrivateAuraTracker:GetChannel()
            or (Addon:GetModuleDB("PrivateAuraTracker") or {}).channel
            or "Master"
        privateAuraChannelButton.text:SetText("Aura Ch: " .. tostring(privateAuraChannel))
    end

    function frame:RefreshSpells()
        local lines = {}
        local browserLines = ns.SpellBrowser and ns.SpellBrowser.BuildStatusLines and ns.SpellBrowser:BuildStatusLines() or {}
        local tooltipLines = ns.SpellTooltip and ns.SpellTooltip.BuildStatusLines and ns.SpellTooltip:BuildStatusLines() or {}
        lines[#lines + 1] = browserLines[1] or ""
        lines[#lines + 1] = browserLines[2] or ""
        lines[#lines + 1] = tooltipLines[1] or ""
        for index = 1, #spells.statusLines do
            spells.statusLines[index]:SetText(lines[index] or "")
            if index == 1 then
                spells.statusLines[index]:SetTextColor(UI:Color("text"))
            else
                spells.statusLines[index]:SetTextColor(UI:Color("textDim"))
            end
        end
        for _, button in ipairs(spellTooltipControls) do
            if button.Refresh then
                button:Refresh()
            end
        end
        local db = Addon:GetModuleDB("SpellTooltip") or {}
        for _, control in ipairs(spellTooltipValues) do
            control.value:SetText(FormatValue(db[control.tooltipField]))
        end
        openBrowser.text:SetText("Open Browser")
        selectedTipButton.text:SetText("Selected Tip")
        hideTipButton.text:SetText("Hide Tip")
    end

    function frame:RefreshInfo()
        local lines = ns.KeystoneInfo and ns.KeystoneInfo.GetLines and ns.KeystoneInfo:GetLines() or {}
        local db = Addon:GetModuleDB("KeystoneInfo") or {}
        for index = 1, #info.lines do
            info.lines[index]:SetText(lines[index] or "")
        end
        for _, button in ipairs(infoControls) do
            if button.Refresh then
                button:Refresh()
            end
        end
        for _, button in ipairs(infoModuleControls) do
            if button.Refresh then
                button:Refresh()
            end
        end
        for _, control in ipairs(infoValueControls) do
            local moduleDB = Addon:GetModuleDB(control.infoModule) or {}
            control.value:SetText(FormatValue(moduleDB[control.infoField]))
        end
        refreshInfoButton.text:SetText("Refresh")
        printInfoButton.text:SetText("Print")
        briefInfoButton.text:SetText("Brief")
        copyInfoButton.text:SetText("Copy")
        riskInfoButton.text:SetText("Risks")
        assignInfoButton.text:SetText("Assign")
        local splitStats = ns.EncounterSplitTracker and ns.EncounterSplitTracker.GetStats and ns.EncounterSplitTracker:GetStats() or {}
        splitInfoButton.text:SetText("Splits " .. tostring(splitStats.stored or 0))
        if ns.EncounterGuide and ns.EncounterGuide.BuildLines then
            ns.EncounterGuide:BuildLines()
        end
        local guideStats = ns.EncounterGuide and ns.EncounterGuide.GetStats and ns.EncounterGuide:GetStats() or {}
        guideInfoButton.text:SetText("Guide " .. tostring(guideStats.cursor or 0) .. "/" .. tostring(guideStats.bosses or 0))
        info.lines[12]:SetText("Slash: /dmp key status, brief, copy, risks; /dmp guide; /dmp assign; /dmp splits")
        info.lines[12]:SetTextColor(UI:Color("textDim"))
        if db.enabled == false then
            info.lines[1]:SetText("Keystone overview is disabled.")
        end
    end

    function frame:RefreshRoutes()
        local db = Addon:GetModuleDB("RouteNotes") or {}
        local stats = ns.RouteNotes and ns.RouteNotes.GetStats and ns.RouteNotes:GetStats() or {}
        local pullDB = Addon:GetModuleDB("PullPlanner") or {}
        local pullStats = ns.PullPlanner and ns.PullPlanner.GetStats and ns.PullPlanner:GetStats() or {}
        local routeStatusLines = ns.RouteNotes and ns.RouteNotes.BuildStatusLines and ns.RouteNotes:BuildStatusLines() or {}
        routes.lines[1]:SetText(routeStatusLines[1] or ("Current route mapID/source: "
            .. tostring(stats.mapID or "none")
            .. " / " .. tostring(stats.source or "none")))
        routes.lines[2]:SetText(routeStatusLines[2] or "")
        routes.lines[3]:SetText(routeStatusLines[3] or "")
        routes.lines[4]:SetText("Last note: " .. tostring(stats.lastText or ""))
        local routeBrief = ns.RouteNotes and ns.RouteNotes.BuildRouteLines
            and ns.RouteNotes:BuildRouteLines(stats.mapID, 2) or {}
        routes.lines[5]:SetText("Selected route: " .. tostring(routeBrief[1] or "none"))
        routes.lines[6]:SetText("Next route: " .. tostring(routeBrief[2] or "none"))
        routes.lines[7]:SetText("Options: enabled=" .. tostring(db.enabled ~= false)
            .. " start=" .. tostring(db.showOnChallengeStart ~= false)
            .. " chat=" .. tostring(db.announceToChat ~= false)
            .. " alert=" .. tostring(db.showCenterAlert ~= false)
            .. " mplusOnly=" .. tostring(db.onlyInChallenge == true))
        local mapStats = ns.RouteMap and ns.RouteMap.GetStats and ns.RouteMap:GetStats() or {}
        local mapStatusLines = ns.RouteMap and ns.RouteMap.BuildStatusLines and ns.RouteMap:BuildStatusLines() or {}
        routes.lines[8]:SetText(mapStatusLines[1] or ("Route map: markers=" .. tostring(mapStats.markers or 0)
            .. " selected=" .. tostring(mapStats.cursor or 0)
            .. " path=" .. tostring(mapStats.pathSegments or 0)
            .. " texture=" .. tostring(mapStats.textureSource or "none")
            .. " last=" .. tostring(mapStats.lastLabel or "")))
        for _, button in ipairs(routeControls) do
            if button.Refresh then
                button:Refresh()
            end
        end
        for _, control in ipairs(routeValueControls) do
            control.value:SetText(FormatValue(db and db[control.routeField]))
        end
        local pullStatusLines = ns.PullPlanner and ns.PullPlanner.BuildStatusLines and ns.PullPlanner:BuildStatusLines() or {}
        routes.pullLines[1]:SetText(pullStatusLines[1] or ("Pull preview map/source/cursor: "
            .. tostring(pullStats.mapID or "none")
            .. " / " .. tostring(pullStats.source or "none")
            .. " / " .. tostring(pullStats.cursor or 0)
            .. "/" .. tostring(pullStats.pulls or 0)
            .. " rules=" .. tostring(pullStats.rules or 0)))
        local pullBrief = ns.PullPlanner and ns.PullPlanner.BuildPullLines
            and ns.PullPlanner:BuildPullLines(pullStats.mapID, 2) or {}
        routes.pullLines[2]:SetText("Selected pull: " .. tostring(pullBrief[1] or "none"))
        routes.pullLines[3]:SetText("Next pull: " .. tostring(pullBrief[2] or "none"))
        for _, button in ipairs(pullControls) do
            if button.Refresh then
                button:Refresh()
            end
        end
        for _, control in ipairs(pullValueControls) do
            control.value:SetText(FormatValue(pullDB and pullDB[control.pullField]))
        end
        local overlayStats = ns.RouteOverlay and ns.RouteOverlay.GetStats and ns.RouteOverlay:GetStats() or {}
        local overlayStatusLines = ns.RouteOverlay and ns.RouteOverlay.BuildStatusLines and ns.RouteOverlay:BuildStatusLines() or {}
        overlayButton.text:SetText("Overlay "
            .. tostring(overlayStats.routeIndex or 0) .. "/" .. tostring(overlayStats.routeTotal or 0)
            .. " "
            .. tostring(overlayStats.pullIndex or 0) .. "/" .. tostring(overlayStats.pullTotal or 0)
            .. " M" .. tostring(overlayStats.markerIndex or 0))
        if overlayStatusLines[1] then
            routes.lines[7]:SetText(overlayStatusLines[1])
        end
        routeMapButton.text:SetText("Map " .. tostring(mapStats.cursor or 0) .. "/" .. tostring(mapStats.markers or 0))
    end

    function frame:RefreshRuns()
        local db = Addon:GetModuleDB("RunHistory") or {}
        local stats = ns.RunHistory and ns.RunHistory.GetStats and ns.RunHistory:GetStats() or {}
        local deathStats = ns.DeathTracker and ns.DeathTracker.GetStats and ns.DeathTracker:GetStats() or {}
        local history = ns.RunHistory and ns.RunHistory.GetHistory and ns.RunHistory:GetHistory(5) or {}
        local runLines = ns.RunHistory and ns.RunHistory.BuildStatusLines and ns.RunHistory:BuildStatusLines() or {}
        runs.lines[1]:SetText(runLines[1] or ("Active/stored/last status: "
            .. tostring(stats.active == true)
            .. " / " .. tostring(stats.stored or 0)
            .. " / " .. tostring(stats.lastStatus or "none")))
        runs.lines[2]:SetText(runLines[2] or "")
        runs.lines[3]:SetText(runLines[3] or "")
        runs.lines[4]:SetText("Options: enabled=" .. tostring(db.enabled ~= false)
            .. " resets=" .. tostring(db.recordResets ~= false)
            .. " chat=" .. tostring(db.announceToChat ~= false)
            .. " alert=" .. tostring(db.showCompletionAlert ~= false)
            .. " max=" .. tostring(db.maxRuns or 30)
            .. " / live deaths=" .. tostring(deathStats.recent or 0)
            .. " wipes=" .. tostring(deathStats.wipes or 0))
        for index = 1, 5 do
            local run = history[index]
            runs.lines[4 + index]:SetText(run and ("#" .. tostring(index) .. " "
                .. (ns.RunHistory and ns.RunHistory.FormatRun and ns.RunHistory:FormatRun(run) or tostring(run.status or ""))) or "")
        end
        local deathLines = ns.DeathTracker and ns.DeathTracker.BuildStatusLines and ns.DeathTracker:BuildStatusLines() or {}
        runs.lines[10]:SetText(deathLines[1] or "")
        runs.lines[11]:SetText(deathLines[2] or "Slash: /dmp runs status, summary, encounters, deaths, compare, list, current, details, copy, clear, max, enabled, resets, chat, alert")
        for _, button in ipairs(runControls) do
            if button.Refresh then
                button:Refresh()
            end
        end
        for _, control in ipairs(runValueControls) do
            control.value:SetText(FormatValue(db and db[control.runField]))
        end
        for _, button in ipairs(deathControls) do
            if button.Refresh then
                button:Refresh()
            end
        end
        local deathDB = Addon:GetModuleDB("DeathTracker") or {}
        for _, control in ipairs(deathValueControls) do
            control.value:SetText(FormatValue(deathDB and deathDB[control.deathField]))
        end
    end

    function frame:RefreshProfile()
        local exchange = ns.ProfileExchange
        local stats = exchange and exchange.GetStats and exchange:GetStats() or {}
        local codec = exchange and exchange.GetCodecStatus and exchange:GetCodecStatus() or {}
        local db = Addon:GetModuleDB("ProfileExchange") or {}
        for _, button in ipairs(profileToggles) do
            if button.Refresh then
                button:Refresh()
            end
        end
        local statusLines = exchange and exchange.BuildStatusLines and exchange:BuildStatusLines() or {}
        local resetLines = exchange and exchange.BuildResetLines and exchange:BuildResetLines() or {}
        if statusLines[1] then
            profileLines[1]:SetText(statusLines[1] or "")
            profileLines[2]:SetText(statusLines[2] or "")
            profileLines[3]:SetText(statusLines[3] or "")
            profileLines[4]:SetText(statusLines[4] or "")
            profileLines[5]:SetText(resetLines[1] or "")
            profileLines[6]:SetText(resetLines[2] or "Imports and resets queue config application during combat.")
        else
            profileLines[1]:SetText("Enabled: " .. tostring(db.enabled ~= false)
                .. " / include caches: " .. tostring(db.includeCaches == true)
                .. " / last mode: " .. tostring(db.lastMode or "merge"))
            profileLines[2]:SetText("Bundled codec: serialize=" .. tostring(codec.serialize == true)
                .. " deflate=" .. tostring(codec.deflate == true)
                .. " compressed=" .. tostring(codec.compressed == true))
            profileLines[3]:SetText("Exports/imports: " .. tostring(stats.exports or 0)
                .. " / " .. tostring(stats.imports or 0)
                .. " / resets: " .. tostring(stats.resets or 0)
                .. " / last scope: " .. tostring(stats.lastScope or ""))
            profileLines[4]:SetText("Last keys: " .. tostring(stats.lastKeys or 0)
                .. " / last reset: " .. tostring(stats.lastResetScope or db.lastResetScope or "")
                .. " (" .. tostring(stats.lastResetKeys or db.lastResetKeys or 0) .. ")")
            profileLines[5]:SetText("Scopes: all = full profile, style = UI/layout/visuals, rules = spell/dungeon overrides, routes = planning/assignments, runs = history/splits/deaths, trash = trash CD tuning.")
            profileLines[6]:SetText("Config reset restores every non-style section to defaults; imports and resets queue config application during combat.")
        end
    end
    function frame:RefreshDebug()
        local state = Addon.EventBusState or {}
        local audit = ns.NativeEvents and ns.NativeEvents.GetAuditStatus and ns.NativeEvents:GetAuditStatus() or {}
        local registered = state.registered or {}
        local events = {}
        for event in pairs(registered) do
            events[#events + 1] = event
        end
        table.sort(events)
        debug.lines[1]:SetText("Audit: standalone=" .. tostring(audit.standalone == true)
            .. " nativeLocked=" .. tostring(audit.registrationClosed == true)
            .. " nativeFailed=" .. tostring(audit.failedCount or 0)
            .. " blockedNative=" .. tostring(audit.blockedNative == true)
            .. " disabledSkips=" .. tostring(state.skippedDisabled or 0))
        debug.lines[2]:SetText("Last native register: " .. tostring(state.lastRegister) .. " via " .. tostring(state.lastRegisterFrame))
        debug.lines[3]:SetText("Registered events: " .. tostring(#events))
        debug.lines[4]:SetText(table.concat(events, ", "))
        debug.lines[5]:SetText("Pending config: " .. (ns.Config and ns.Config:GetPendingText() or "n/a"))
        local runtime = Addon:GetModule("MythicRuntime")
        local runtimeStats = runtime and runtime.GetStats and runtime:GetStats() or {}
        debug.lines[6]:SetText("Config apply count: " .. tostring(ns.Config and ns.Config.applyCount or 0)
            .. "; Runtime active/units/casts/cd/scans: "
            .. tostring(runtimeStats.activeCasts or 0) .. "/"
            .. tostring(runtimeStats.unitGUIDs or 0) .. "/"
            .. tostring(runtimeStats.castsTracked or 0) .. "-"
            .. tostring(runtimeStats.castRefreshes or 0) .. "/"
            .. tostring(runtimeStats.cooldownsScheduled or 0) .. "/"
            .. tostring(runtimeStats.nameplateScans or 0) .. "-"
            .. tostring(runtimeStats.bossScans or 0))
        local obsStats = ns.RuntimeObservation and ns.RuntimeObservation:GetStats() or {}
        local schedulerStats = ns.CooldownScheduler and ns.CooldownScheduler:GetStats() or {}
        local debuffStats = ns.DebuffTracker and ns.DebuffTracker:GetStats() or {}
        local privateAuraStats = ns.PrivateAuraTracker and ns.PrivateAuraTracker:GetStats() or {}
        local affixStats = ns.AffixTracker and ns.AffixTracker:GetStats() or {}
        local healthStats = ns.HealthThresholdTracker and ns.HealthThresholdTracker:GetStats() or {}
        local markerStats = ns.NameplateMarker and ns.NameplateMarker:GetStats() or {}
        local fingerprintStats = ns.AuraFingerprint and ns.AuraFingerprint:GetStats() or {}
        local interruptStats = ns.InterruptTracker and ns.InterruptTracker:GetStats() or {}
        local specSyncStats = ns.PartySpecSync and ns.PartySpecSync:GetStats() or {}
        local alertStats = ns.Alert and ns.Alert:GetStats() or {}
        local countdownStats = ns.CountdownDisplay and ns.CountdownDisplay:GetStats() or {}
        local ringStats = ns.RingProgress and ns.RingProgress:GetStats() or {}
        local castProgressStats = ns.CastProgressBar and ns.CastProgressBar:GetStats() or {}
        local bunStats = ns.BunBar and ns.BunBar:GetStats() or {}
        local glowStats = ns.PartyFrameGlow and ns.PartyFrameGlow:GetStats() or {}
        local voiceStats = ns.Voice and ns.Voice.GetStats and ns.Voice:GetStats() or {}
        local voiceSourceStats = ns.Voice and ns.Voice.GetVoiceSourceStats and ns.Voice:GetVoiceSourceStats() or {}
        local encounterGuard = ns.EncounterCVarGuard
        local encounterGuardStats = encounterGuard and encounterGuard.GetStats and encounterGuard:GetStats() or {}
        local encounterGuardDB = encounterGuard and encounterGuard.GetDB and encounterGuard:GetDB() or {}
        local obsLines = ns.RuntimeObservation and ns.RuntimeObservation.BuildStatusLines and ns.RuntimeObservation:BuildStatusLines() or nil
        local schedulerLines = ns.CooldownScheduler and ns.CooldownScheduler.BuildStatusLines and ns.CooldownScheduler:BuildStatusLines() or nil
        local trashCacheLines = ns.TrashCache and ns.TrashCache.BuildStatusLines and ns.TrashCache:BuildStatusLines() or nil
        debug.lines[7]:SetText(obsLines and table.concat(obsLines, "; ") or (
            "Observed units/casts-ch/successes/interrupts/spell-npc inferred/int-lock/pred/history: "
            .. tostring(obsStats.observed or 0) .. "/"
            .. tostring(obsStats.casts or 0) .. "/"
            .. tostring(obsStats.channels or 0) .. "/"
            .. tostring(obsStats.successes or 0) .. "/"
            .. tostring(obsStats.interrupts or 0) .. "/"
            .. tostring(obsStats.inferred or 0) .. "/"
            .. tostring(obsStats.npcInferred or 0) .. "/"
            .. tostring(obsStats.interruptible or 0) .. "-"
            .. tostring(obsStats.locked or 0) .. "/"
            .. tostring(obsStats.predictions or 0) .. "-"
            .. tostring(obsStats.predictionCleared or 0) .. "/"
            .. tostring(obsStats.history or 0)
        ))
        debug.lines[8]:SetText((schedulerLines and table.concat(schedulerLines, "; ") or (
            "Scheduled first/cooldown/hidden-exp/pending/skipped: "
            .. tostring(schedulerStats.first or 0) .. "/"
            .. tostring(schedulerStats.cooldown or 0) .. "/"
            .. tostring(schedulerStats.hidden or 0) .. "-"
            .. tostring(schedulerStats.hiddenExpired or 0) .. "/"
            .. tostring(schedulerStats.pending or 0) .. "/"
            .. tostring(schedulerStats.skipped or 0)
        )) .. "; fingerprints c/t/a/r/m/f/s: "
            .. tostring(fingerprintStats.captured or 0) .. "/"
            .. tostring(fingerprintStats.target or 0) .. "/"
            .. tostring(fingerprintStats.auraDelta or 0) .. "/"
            .. tostring(fingerprintStats.resolved or 0) .. "/"
            .. tostring(fingerprintStats.matched or 0) .. "/"
            .. tostring(fingerprintStats.fallback or 0) .. "/"
            .. tostring(fingerprintStats.skipped or 0))
        local timelineStats = ns.TimelineScheduler and ns.TimelineScheduler:GetStats() or {}
        local timelineLines = ns.TimelineScheduler and ns.TimelineScheduler.BuildStatusLines and ns.TimelineScheduler:BuildStatusLines() or nil
        debug.lines[9]:SetText(timelineLines and table.concat(timelineLines, "; ") or (
            "Boss timeline trigger/mode/events/rules/fixed/series/passive/windows/obs q-m-e-stop-active-trans-alias/sync/resume/state p-r-f-c/skipped: "
            .. tostring(timelineStats.trigger or "none") .. "/"
            .. tostring(timelineStats.mode or "auto") .. "-"
            .. tostring(timelineStats.fixedDriver or "time") .. "/"
            .. tostring(timelineStats.events or 0) .. "/"
            .. tostring(timelineStats.durationRules or 0) .. "/"
            .. tostring(timelineStats.fixed or 0) .. "/"
            .. tostring(timelineStats.series or 0) .. "/"
            .. tostring(timelineStats.passive or 0) .. "/"
            .. tostring(timelineStats.castWindows or 0) .. "/"
            .. tostring(timelineStats.observeQueued or 0) .. "-"
            .. tostring(timelineStats.observeMatched or 0) .. "-"
            .. tostring(timelineStats.observeExpired or 0) .. "-"
            .. tostring(timelineStats.observeStopped or 0) .. "-"
            .. tostring(timelineStats.observeActive or 0) .. "-"
            .. tostring(timelineStats.observeTransitions or 0) .. "-"
            .. tostring(timelineStats.observeAliases or 0) .. "/"
            .. tostring(timelineStats.syncSkips or 0) .. "/"
            .. tostring(timelineStats.resumeSnapshots or 0) .. "-"
            .. tostring(timelineStats.resumeMatches or 0) .. "/"
            .. tostring(timelineStats.passivePaused or 0) .. "-"
            .. tostring(timelineStats.passiveResumed or 0) .. "-"
            .. tostring(timelineStats.passiveFinished or 0) .. "-"
            .. tostring(timelineStats.passiveCanceled or 0) .. "/"
            .. tostring(timelineStats.skipped or 0)
        ))
        debug.lines[10]:SetText(
            "Debuff rules/map/units/auras; interrupts members/cd/attached/records/count; spec sync c/s/r/q: "
            .. tostring(debuffStats.rules or 0) .. "/"
            .. tostring(debuffStats.mapID or 0) .. "/"
            .. tostring(debuffStats.units or 0) .. "/"
            .. tostring(debuffStats.auras or 0) .. "; "
            .. tostring(interruptStats.members or 0) .. "/"
            .. tostring(interruptStats.cooldowns or 0) .. "/"
            .. tostring(interruptStats.attached or 0) .. "/"
            .. tostring(interruptStats.records or 0) .. "/"
            .. tostring(interruptStats.interrupts or 0) .. "; "
            .. tostring(specSyncStats.cache or 0) .. "/"
            .. tostring(specSyncStats.sent or 0) .. "/"
            .. tostring(specSyncStats.received or 0) .. "/"
            .. tostring(specSyncStats.queries or 0)
        )
        debug.lines[11]:SetText(
            "Nameplate icons active/cd/ready/total; affix weekly/rules/active/units/refreshes: "
            .. tostring(markerStats.active or 0) .. "/"
            .. tostring(markerStats.cooldown or 0) .. "/"
            .. tostring(markerStats.ready or 0) .. "/"
            .. tostring(markerStats.icons or 0) .. "; "
            .. tostring(affixStats.affixes or 0) .. "/"
            .. tostring(affixStats.rules or 0) .. "/"
            .. tostring(affixStats.active or 0) .. "/"
            .. tostring(affixStats.units or 0) .. "/"
            .. tostring(affixStats.refreshes or 0)
        )
        debug.lines[12]:SetText((trashCacheLines and table.concat(trashCacheLines, "; ") or "TrashCache status unavailable")
            .. "; Health threshold rules/active/trash/alerts: "
            .. tostring(healthStats.rules or 0) .. "/"
            .. tostring(healthStats.active or 0) .. "/"
            .. tostring(healthStats.trashUnits or 0) .. "/"
            .. tostring(healthStats.alerts or 0)
        )
        debug.lines[13]:SetText(
            "Private aura scope/enc/rules/anchors/sounds/pending: "
            .. tostring(privateAuraStats.scope or "none") .. "/"
            .. tostring(privateAuraStats.encounterID or 0) .. "/"
            .. tostring(privateAuraStats.rules or 0) .. "/"
            .. tostring(privateAuraStats.anchors or 0) .. "/"
            .. tostring(privateAuraStats.sounds or 0) .. "/"
            .. tostring(privateAuraStats.pending == true)
        )
        debug.lines[14]:SetText(
            "Alert active c/v/flash/stop; countdown ticks/shown/hidden; ring s/st/c/i; cast s/st/c/i; bun a/s/e/i; glow s/st/m/f/tg/tm: "
            .. tostring(alertStats.activeCountdowns or 0) .. "/"
            .. tostring(alertStats.activeVulnerability or 0) .. "/"
            .. tostring(alertStats.flashes or 0) .. "/"
            .. tostring(alertStats.stopped or 0) .. "; "
            .. tostring(countdownStats.ticks or 0) .. "/"
            .. tostring(countdownStats.shown or 0) .. "/"
            .. tostring(countdownStats.hidden or 0) .. "; "
            .. tostring(ringStats.shown or 0) .. "/"
            .. tostring(ringStats.stopped or 0) .. "/"
            .. tostring(ringStats.completed or 0) .. "/"
            .. tostring(ringStats.ignored or 0) .. "; "
            .. tostring(castProgressStats.shown or 0) .. "/"
            .. tostring(castProgressStats.stopped or 0) .. "/"
            .. tostring(castProgressStats.completed or 0) .. "/"
            .. tostring(castProgressStats.ignored or 0) .. "; "
            .. tostring(bunStats.accepted or 0) .. "/"
            .. tostring(bunStats.shown or 0) .. "/"
            .. tostring(bunStats.expired or 0) .. "/"
            .. tostring(bunStats.ignored or 0) .. "; "
            .. tostring(glowStats.started or 0) .. "/"
            .. tostring(glowStats.stopped or 0) .. "/"
            .. tostring(glowStats.missed or 0) .. "/"
            .. tostring(glowStats.fallback or 0) .. "/"
            .. tostring(glowStats.targetGlows or 0) .. "/"
            .. tostring(glowStats.timerGlows or 0)
        )
        debug.lines[15]:SetText(
            "Voice played/alerts/cd/file/sound/tts/fallback; skips failed/throttled/skipped; packs/cache/src ok-miss/channel/last: "
            .. tostring(voiceStats.played or 0) .. "/"
            .. tostring(voiceStats.alerts or 0) .. "/"
            .. tostring(voiceStats.countdowns or 0) .. "/"
            .. tostring(voiceStats.fileID or 0) .. "/"
            .. tostring(voiceStats.soundPath or 0) .. "/"
            .. tostring(voiceStats.tts or 0) .. "/"
            .. tostring(voiceStats.fallback or 0) .. "; "
            .. tostring(voiceStats.failed or 0) .. "/"
            .. tostring(voiceStats.throttled or 0) .. "/"
            .. tostring(voiceStats.skipped or 0) .. "; "
            .. tostring(voiceStats.packs or 0) .. "/"
            .. tostring(voiceStats.cache or 0) .. "/"
            .. tostring(voiceSourceStats.active or 0) .. "-"
            .. tostring(voiceSourceStats.resolved or 0) .. "-"
            .. tostring(voiceSourceStats.missing or 0) .. "/"
            .. tostring(voiceStats.channel or "") .. "/"
            .. tostring(voiceStats.lastSource or "")
        )
        debug.lines[16]:SetText(
            "Encounter guard repair/warn/warnsound/timeline/sound/CAA; boss/fixed/muted/forced; repairs/events/writes/failed: "
            .. tostring(encounterGuardDB.repairEncounterCVars ~= false) .. "/"
            .. tostring(encounterGuardDB.encounterWarningsEnabled ~= false) .. "/"
            .. tostring(encounterGuardDB.encounterWarningSoundsEnabled ~= false) .. "/"
            .. tostring(encounterGuardDB.encounterTimelineEnabled ~= false) .. "/"
            .. tostring(encounterGuardDB.forceSoundChannels == true) .. "-"
            .. tostring(encounterGuardDB.soundChannels or "") .. "/"
            .. tostring(encounterGuardDB.autoMuteCombatAudioInFixedBoss == true) .. "; "
            .. tostring(encounterGuardStats.inBoss == true) .. "/"
            .. tostring(encounterGuardStats.fixed == true) .. "/"
            .. tostring(encounterGuardStats.caaVolumeMuted == true) .. "/"
            .. tostring(encounterGuardStats.caaWasForced == true) .. "; "
            .. tostring(encounterGuardStats.repairs or 0) .. "/"
            .. tostring(encounterGuardStats.cvarEvents or 0) .. "/"
            .. tostring(encounterGuardStats.cvarWrites or 0) .. "/"
            .. tostring(encounterGuardStats.failedWrites or 0)
        )
        local errors = ns.Runtime and ns.Runtime.errorLog or {}
        for i = 1, 4 do
            local entry = errors[i]
            debug.lines[16 + i]:SetText(entry and (entry.time .. " " .. entry.source .. ": " .. entry.message) or "")
        end
    end

    function frame:RefreshTabs()
        if ns.RecordSmokeTab then
            ns.RecordSmokeTab(self.selectedTab)
        end
        for _, button in ipairs(tabButtons) do
            SetButtonState(button, button.tabKey == self.selectedTab)
        end
        for key, panel in pairs(self.panels) do
            if key == self.selectedTab then
                panel:Show()
            else
                panel:Hide()
            end
        end
        for _, button in ipairs(moduleButtons) do
            if button.Refresh then button:Refresh() end
        end
        for _, button in ipairs(groupButtons) do
            local db = GetGroupDB(button.groupKey)
            if db then
                button.text:SetText(db.label or button.groupKey)
            end
        end
        self:RefreshStyleControls()
        self:RefreshRuntimeControls()
        self:RefreshDungeon()
        self:RefreshSpells()
        self:RefreshInfo()
        self:RefreshRoutes()
        self:RefreshRuns()
        self:RefreshProfile()
        self:RefreshDebug()
    end

    function frame:SelectTab(tabKey)
        tabKey = tostring(tabKey or ""):lower()
        for _, tab in ipairs(TABS) do
            if tab.key == tabKey then
                self.selectedTab = tabKey
                self:Show()
                self:RefreshTabs()
                return true
            end
        end
        return false
    end

    tinsert(UISpecialFrames, "DDingUIMythicPlus_MainFrame")
    self.MainFrame = frame
    frame:RefreshTabs()
    return frame
end
