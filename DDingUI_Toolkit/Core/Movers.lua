-- DDingUI Toolkit - Edit mode
-- [STYLE] Series edit mode (C5·C12): the remote, mover surface, HUD, grid, guides and snap
-- maths come from StyleLib 1.4 EditMode.lua. Toolkit keeps the frame registry, the
-- CENTER-based save model, undo/redo and the combat/non-combat preview switch.

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib
local Lib = LibStub and LibStub("DDingUI-StyleLib-1.0", true) or SL
local CHAT_PREFIX = ns.CHAT_PREFIX -- [STYLE] Core/Core.lua 공통 접두사
local ADDON_KEY = "MJToolkit"
local SPEC = Lib and Lib.EditModeSpec or {
    gridSpacing = 32, gridChoices = { 16, 32, 64 }, snapThreshold = 8, nudge = 1, nudgeShift = 10,
}

local Movers = {}
ns.ToolkitMovers = Movers

local function Locale(key, fallback)
    local value = L and rawget(L, key)
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

local function EnableRightClickMouselook(frame)
    if ns.EnableRightClickMouselook then
        ns:EnableRightClickMouselook(frame)
    end
end

local function HasEditModeLib()
    return Lib and Lib.CreateEditRemote and Lib.StyleMover and Lib.CreateMoverHUD
        and Lib.CreateEditGrid and Lib.CreateEditGuides and Lib.SnapToGrid and true or false
end

-- ============================================================
-- MoverRegistry
-- ============================================================
local REG = {
    {
        name = "CombatTimer",
        frameName = "DDingToolKit_CombatTimerFrame",
        dbPath = "CombatTimer.position",
        posType = "standard",
        module = "CombatTimer",
        previewState = "combat",
        defaultW = 120, defaultH = 40,
    },
    {
        name = "CombatStateAlert",
        getFrame = function()
            local mod = ns.CombatStateAlert or (DDingToolKit.modules and DDingToolKit.modules.CombatStateAlert)
            if mod and mod.CreateFrame then mod:CreateFrame() end
            return _G.DDingToolKit_CombatStateAlertFrame
        end,
        dbPath = "CombatStateAlert.position",
        posType = "standard",
        module = "CombatStateAlert",
        previewState = "always",
        defaultW = 480, defaultH = 96,
    },
    {
        name = "RaidBreakTimer",
        getFrame = function()
            local mod = ns.RaidBreakTimer or (DDingToolKit.modules and DDingToolKit.modules.RaidBreakTimer)
            if mod and mod.CreateFrame then mod:CreateFrame() end
            return _G.DDingToolKit_RaidBreakTimerFrame
        end,
        dbPath = "RaidBreakTimer.position",
        posType = "standard",
        module = "RaidBreakTimer",
        previewState = "noncombat",
        defaultW = 360, defaultH = 160,
    },
    {
        name = "CharacterPositionMarker",
        getFrame = function()
            local mod = ns.CharacterPositionMarker or (DDingToolKit.modules and DDingToolKit.modules.CharacterPositionMarker)
            if mod and mod.CreateFrame then mod:CreateFrame() end
            return _G.DDingToolKit_CharacterPositionMarkerFrame
        end,
        dbPath = "CharacterPositionMarker.position",
        posType = "standard",
        module = "CharacterPositionMarker",
        previewState = "combat",
        defaultW = 80, defaultH = 80,
    },
    {
        name = "RangeDisplay_Target",
        getFrame = function()
            local mod = ns.RangeDisplay or (DDingToolKit.modules and DDingToolKit.modules.RangeDisplay)
            if mod and mod.CreateFrames then mod:CreateFrames() end
            return _G.DDingToolKit_RangeDisplayTargetFrame
        end,
        dbPath = "RangeDisplay.targetPosition",
        posType = "standard",
        module = "RangeDisplay",
        previewState = function()
            local db = ns.db and ns.db.profile and ns.db.profile.RangeDisplay
            return (db and db.combatOnly) and "combat" or "always"
        end,
        defaultW = 140, defaultH = 32,
    },
    {
        name = "RangeDisplay_Focus",
        getFrame = function()
            local mod = ns.RangeDisplay or (DDingToolKit.modules and DDingToolKit.modules.RangeDisplay)
            if mod and mod.CreateFrames then mod:CreateFrames() end
            return _G.DDingToolKit_RangeDisplayFocusFrame
        end,
        dbPath = "RangeDisplay.focusPosition",
        posType = "standard",
        module = "RangeDisplay",
        previewState = function()
            local db = ns.db and ns.db.profile and ns.db.profile.RangeDisplay
            return (db and db.combatOnly) and "combat" or "always"
        end,
        defaultW = 140, defaultH = 32,
    },
    {
        name = "TargetSpell",
        getFrame = function()
            local mod = ns.CastingAlert or (DDingToolKit.modules and DDingToolKit.modules.CastingAlert)
            if mod and mod.CreateMainFrame then mod:CreateMainFrame() end
            return ns.CastingAlertIconFrame or _G.DDingToolKit_CastingAlertIconFrame
        end,
        dbPath = "CastingAlert.iconPosition",
        posType = "standard",
        module = "CastingAlert",
        previewState = function()
            local db = ns.db and ns.db.profile and ns.db.profile.CastingAlert
            return (not db or db.combatOnly ~= false) and "combat" or "always"
        end,
        defaultW = 80, defaultH = 80,
    },
    {
        name = "FocusInterrupt_T",
        getFrame = function() return ns.targetcastbar end,
        dbPath = "FocusInterrupt.targetPosition",
        posType = "standard",
        module = "FocusInterrupt",
        previewState = "combat",
        defaultW = 300, defaultH = 30,
    },
    {
        name = "FocusInterrupt_F",
        getFrame = function() return ns.focuscastbar end,
        dbPath = "FocusInterrupt.focusPosition",
        posType = "standard",
        module = "FocusInterrupt",
        previewState = "combat",
        defaultW = 300, defaultH = 30,
    },
    {
        name = "StasisTracker",
        getFrame = function()
            local mod = ns.StasisTracker or (DDingToolKit.modules and DDingToolKit.modules.StasisTracker)
            if mod and mod.CreateFrame then mod:CreateFrame() end
            return _G.DDingToolKit_StasisTrackerFrame
        end,
        dbPath = "StasisTracker.position",
        posType = "standard",
        module = "StasisTracker",
        previewState = "combat",
        defaultW = 140, defaultH = 63,
    },
    {
        name = "BloodlustTimer",
        getFrame = function()
            local mod = ns.BloodlustTimer or (DDingToolKit.modules and DDingToolKit.modules.BloodlustTimer)
            if mod and mod.CreateFrame then mod:CreateFrame() end
            return _G.DDingToolKit_BloodlustTimerFrame
        end,
        dbPath = "BloodlustTimer.position",
        posType = "standard",
        module = "BloodlustTimer",
        previewState = "combat",
        defaultW = 266, defaultH = 44,
    },
    {
        name = "RaidDefensiveTracker",
        getFrame = function()
            local mod = ns.RaidDefensiveTracker or (DDingToolKit.modules and DDingToolKit.modules.RaidDefensiveTracker)
            if mod and mod.CreateFrame then mod:CreateFrame() end
            return _G.DDingToolKit_RaidDefensiveTrackerFrame
        end,
        dbPath = "RaidDefensiveTracker.position",
        posType = "standard",
        module = "RaidDefensiveTracker",
        previewState = "combat",
        defaultW = 44, defaultH = 44,
        onPositionChanged = function()
            local mod = ns.RaidDefensiveTracker
                or (DDingToolKit.modules and DDingToolKit.modules.RaidDefensiveTracker)
            if mod and mod.OnMoverPositionChanged then
                mod:OnMoverPositionChanged()
            end
        end,
    },
    {
        name = "BloodlustStartMotion",
        getFrame = function()
            local mod = ns.BloodlustTimer or (DDingToolKit.modules and DDingToolKit.modules.BloodlustTimer)
            if mod and mod.CreateStartMotionFrame then mod:CreateStartMotionFrame() end
            return _G.DDingToolKit_BloodlustStartMotionFrame
        end,
        dbPath = "BloodlustTimer.startMotionPosition",
        posType = "standard",
        module = "BloodlustTimer",
        previewState = "combat",
        defaultW = 620, defaultH = 130,
    },
    {
        name = "DeathAlert",
        frameName = "DDingToolKit_DeathAlertFrame",
        dbPath = "DeathAlert.position",
        posType = "standard",
        module = "DeathAlert",
        previewState = "combat",
        defaultW = 400, defaultH = 50,
    },
    {
        name = "SkyridingTracker",
        frameName = "DDingUI_SkyridingTracker",
        posType = "skyriding",
        module = "SkyridingTracker",
        previewState = "noncombat",
        defaultW = 160, defaultH = 160,
    },
    {
        name = "DurabilityCheck",
        frameName = "DDingToolKit_DurabilityFrame",
        dbPath = "DurabilityCheck.position",
        posType = "standard",
        module = "DurabilityCheck",
        previewState = "noncombat",
        defaultW = 460, defaultH = 120,
    },
    {
        name = "GoldSplit",
        frameName = "DDingToolKit_GoldSplitFrame",
        dbPath = "GoldSplit.position",
        posType = "standard",
        module = "GoldSplit",
        previewState = "noncombat",
        defaultW = 280, defaultH = 160,
    },
    {
        name = "LFGAlert",
        frameName = "DDingToolKit_LFGAlertFrame",
        posType = "none",
        module = "LFGAlert",
        previewState = "noncombat",
        defaultW = 500, defaultH = 112,
    },
    {
        name = "PartyFullAlert",
        getFrame = function()
            local mod = ns.PartyFullAlert or (DDingToolKit.modules and DDingToolKit.modules.PartyFullAlert)
            if mod and mod.CreateAlertFrame then mod:CreateAlertFrame() end
            return _G.DDingToolKit_PartyFullAlertFrame
        end,
        dbPath = "PartyFullAlert.position",
        posType = "standard",
        module = "PartyFullAlert",
        previewState = "noncombat",
        defaultW = 500, defaultH = 112,
    },
    {
        name = "CalendarInviteAlert",
        getFrame = function()
            local mod = ns.CalendarInviteAlert
            if mod then mod:CreateAlertFrame() end
            return _G.DDingToolKit_CalendarInviteAlertFrame
        end,
        dbPath = "CalendarInviteAlert.position",
        posType = "standard",
        module = "CalendarInviteAlert",
        previewState = "noncombat",
        defaultW = 500, defaultH = 112,
    },
}

local DEFAULT_POSITIONS = {
    CombatTimer = { x = 0, y = -100 },
    RaidBreakTimer = { x = 0, y = 100 },
    CharacterPositionMarker = { x = 0, y = 0 },
    RangeDisplay_Target = { x = 0, y = -180 },
    RangeDisplay_Focus = { x = 0, y = -140 },
    TargetSpell = { x = 0, y = -30 },
    FocusInterrupt_T = { x = 0, y = -100 },
    FocusInterrupt_F = { x = 0, y = 50 },
    StasisTracker = { x = 0, y = -220 },
    BloodlustTimer = { x = 0, y = -170 },
    RaidDefensiveTracker = { x = 0, y = -250 },
    BloodlustStartMotion = { x = 0, y = 40 },
    DeathAlert = { x = 0, y = 0 },
    SkyridingTracker = { x = 0, y = 0 },
    DurabilityCheck = { x = 0, y = 0 },
    GoldSplit = { x = 0, y = 0 },
    LFGAlert = { x = 0, y = -100 },
    PartyFullAlert = { x = 0, y = 0 },
    CalendarInviteAlert = { x = 0, y = -260 },
}

local function GetDisplayName(reg)
    local labels = {
        CombatTimer = Locale("TAB_COMBATTIMER", "Combat Timer"),
        RaidBreakTimer = Locale("TAB_RAIDBREAKTIMER", "Raid Break Timer"),
        CharacterPositionMarker = Locale("TAB_CHARACTERPOSITIONMARKER", "Character Position"),
        RangeDisplay_Target = Locale("TAB_RANGEDISPLAY", "Range Display") .. " - " .. (TARGET or "Target"),
        RangeDisplay_Focus = Locale("TAB_RANGEDISPLAY", "Range Display") .. " - " .. (FOCUS or "Focus"),
        TargetSpell = Locale("TAB_CASTINGALERT", "Target Spell"),
        FocusInterrupt_T = Locale("TAB_FOCUSINTERRUPT", "Interrupt Bar") .. " - " .. (TARGET or "Target"),
        FocusInterrupt_F = Locale("TAB_FOCUSINTERRUPT", "Interrupt Bar") .. " - " .. (FOCUS or "Focus"),
        StasisTracker = Locale("TAB_STASISTRACKER", "Stasis Tracker"),
        BloodlustTimer = Locale("TAB_BLOODLUSTTIMER", "Bloodlust Timer"),
        RaidDefensiveTracker = Locale("TAB_RAIDDEFENSIVETRACKER", "Raid Defensive Tracker"),
        BloodlustStartMotion = Locale("BLT_START_MOTION_ANCHOR", "Bloodlust Start HUD"),
        DeathAlert = Locale("TAB_DEATHALERT", "Death Alert"),
        SkyridingTracker = Locale("TAB_SKYRIDINGTRACKER", "Skyriding Tracker"),
        DurabilityCheck = Locale("TAB_DURABILITY", "Durability"),
        GoldSplit = Locale("TAB_GOLDSPLIT", "Calculator"),
        LFGAlert = Locale("TAB_LFGALERT", "Party Alert"),
        PartyFullAlert = Locale("TAB_PARTYFULLALERT", "Party Full Alert"),
        CalendarInviteAlert = Locale("TAB_CALENDARINVITEALERT", "Calendar Invite Alert"),
    }
    return labels[reg.name] or reg.name
end

-- ============================================================
-- State
-- ============================================================
local configMode  = false
local movers      = {}      -- name -> overlay Button frame
local moverPos    = {}      -- name -> {x, y}  CENTER offset from UIParent CENTER
local selected    = nil     -- currently selected mover name
local undoStack   = {}
local redoStack   = {}
local MAX_UNDO    = 50
-- Saved under profile.moverSettings (same keys as before; values follow the series spec).
local editorSettings = {
    gridEnabled = true,
    gridSize = SPEC.gridSpacing,
    snapEnabled = true,
    snapToGrid = true,
    snapToFrames = true,
    snapToCenter = true,
    snapThreshold = SPEC.snapThreshold,
}
local editPreviewCombat = false
local remote      = nil     -- Lib.CreateEditRemote
local grid        = nil     -- Lib.CreateEditGrid
local guides      = nil     -- Lib.CreateEditGuides
local eventFrame  = nil
local reopenConfig = false  -- settings window was open when edit mode started
local modulePreviewActive = {}
local modulePreviewInitialized = {}
local forcedPreviewTargets = {}
local stateCallbacks = {}

local function NotifyStateCallbacks()
    for callback in pairs(stateCallbacks) do
        callback(configMode)
    end
end

local CalculateSnapPosition
local GetTargetFrame
local FinishDrag
local UpdateSnapGuides
local UpdateCoordUI

local function GetFrameRelativeScale(frame)
    if not frame then return 1 end
    local uiScale = UIParent:GetEffectiveScale() or 1
    local frameScale = frame:GetEffectiveScale() or uiScale
    if uiScale <= 0 or frameScale <= 0 then return 1 end
    return frameScale / uiScale
end

-- C5: one readout, anchor-relative (CENTER of UIParent) offsets, same while and after dragging.
local function UpdateMoverReadout(overlay, x, y)
    if not overlay or not overlay.selectionHUD then return end
    local width, height = overlay:GetSize()
    overlay.selectionHUD:Update(x or 0, y or 0, width or 0, height or 0)
end

-- OnUpdate drag state
local _isDragging  = false
local _dragMover   = nil
local _dragOffX    = 0
local _dragOffY    = 0
local _dragUpdate  = CreateFrame("Frame")
_dragUpdate:Hide()
_dragUpdate:SetScript("OnUpdate", function()
    if not _isDragging or not _dragMover then return end
    if not IsMouseButtonDown("LeftButton") then
        if FinishDrag then FinishDrag(_dragMover) end
        return
    end
    local cx, cy = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    cx, cy = cx / uiScale, cy / uiScale
    local sw, sh = UIParent:GetSize()
    local nx = cx - sw/2 - _dragOffX
    local ny = cy - sh/2 - _dragOffY
    local snappedX, snappedY
    if CalculateSnapPosition then
        nx, ny, snappedX, snappedY = CalculateSnapPosition(_dragMover, nx, ny)
    end
    UpdateSnapGuides(snappedX, snappedY, nx + sw / 2, ny + sh / 2)
    _dragMover:ClearAllPoints()
    _dragMover:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
    moverPos[_dragMover._regName] = { x = nx, y = ny }
    local target = GetTargetFrame and GetTargetFrame(_dragMover._reg)
    if target then
        local targetScale = GetFrameRelativeScale(target)
        target:ClearAllPoints()
        target:SetPoint("CENTER", UIParent, "CENTER", nx / targetScale, ny / targetScale)
    end
    UpdateCoordUI(_dragMover._regName, nx, ny)
end)

-- Alignment guides: accent lines through the mover centre, per snapped axis (StyleLib). -- [STYLE]
UpdateSnapGuides = function(snappedX, snappedY, cx, cy)
    if not (snappedX or snappedY) then
        if guides then guides:Hide() end
        return
    end
    if not guides then guides = Lib.CreateEditGuides(ADDON_KEY) end
    guides:ShowAt(cx, cy)
    guides.v:SetShown(snappedX and true or false)
    guides.h:SetShown(snappedY and true or false)
end

-- Fade helpers (mover overlays; the remote uses the StyleLib panel motion)
local FADE_DUR = 0.18
local function FadeIn(frame)
    if not frame then return end
    if frame._fadeOutAG then frame._fadeOutAG:Stop() end
    frame:Show()
    local ag = frame._fadeAG
    if not ag then
        ag = frame:CreateAnimationGroup()
        frame._fadeAG = ag
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1)
        a:SetDuration(FADE_DUR); a:SetSmoothing("OUT")
        ag:SetScript("OnFinished", function() frame:SetAlpha(1) end)
    end
    ag:Stop(); frame:SetAlpha(0); ag:Play()
end
local function FadeOut(frame, cb)
    if not frame then return end
    if frame._fadeAG then frame._fadeAG:Stop() end
    local ag = frame._fadeOutAG
    if not ag then
        ag = frame:CreateAnimationGroup()
        frame._fadeOutAG = ag
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0)
        a:SetDuration(FADE_DUR); a:SetSmoothing("IN")
        ag:SetScript("OnFinished", function() frame:Hide(); if cb then cb() end end)
    end
    ag.cb = cb
    ag:Stop(); frame:SetAlpha(1); ag:Play()
end

-- Grid (StyleLib): centred on the screen, same spacing/origin as the snap grid. -- [STYLE]
local function GetGrid()
    if not grid then
        grid = Lib.CreateEditGrid(ADDON_KEY, { spacing = editorSettings.gridSize })
    end
    return grid
end

local function RefreshGrid()
    if not configMode then return end
    local g = GetGrid()
    g:SetSpacing(editorSettings.gridSize)
    if editorSettings.gridEnabled then
        if not g:IsShown() or (g:GetAlpha() or 1) < 1 then g:ShowAnimated() end
    elseif g:IsShown() then
        g:HideAnimated()
    end
    if remote and remote.SetGridState then
        remote:SetGridState(editorSettings.gridEnabled, editorSettings.gridSize)
    end
end

-- ============================================================
-- DB helpers
-- ============================================================
local function GetEditorDB()
    local profile = ns.db and ns.db.profile
    if not profile then return nil end
    if type(profile.moverSettings) ~= "table" then
        profile.moverSettings = {}
    end
    return profile.moverSettings
end

-- Only the series choices (16/32/64) are kept; anything else (old 10/20/40/80) becomes the default 32.
local function NearestGridChoice(value)
    value = tonumber(value)
    for _, choice in ipairs(SPEC.gridChoices or { 16, 32, 64 }) do
        if choice == value then return choice end
    end
    return SPEC.gridSpacing
end

local function LoadEditorSettings()
    local saved = GetEditorDB()
    if saved then
        for key, default in pairs(editorSettings) do
            if saved[key] ~= nil and type(saved[key]) == type(default) then
                editorSettings[key] = saved[key]
            end
        end
    end
    -- Series spec: the grid is on whenever edit mode starts, spacing is one of 16/32/64, snap distance 8.
    editorSettings.gridEnabled = true
    editorSettings.gridSize = NearestGridChoice(editorSettings.gridSize)
    editorSettings.snapThreshold = SPEC.snapThreshold
end

local function SaveEditorSettings()
    local saved = GetEditorDB()
    if not saved then return end
    for key, value in pairs(editorSettings) do
        saved[key] = value
    end
end

-- Remote position: profile.moverSettings.panelPosition (same table shape as before).
local function LoadRemotePosition()
    local saved = GetEditorDB()
    local position = saved and saved.panelPosition
    if type(position) == "table" and position.point then
        return position.point, position.x or 0, position.y or 0
    end
    return nil
end

local function SaveRemotePosition(point, x, y)
    local saved = GetEditorDB()
    if not saved or not point then return end
    saved.panelPosition = {
        point = point,
        relativePoint = point,
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
end

local function GetPosTable(reg)
    if not reg.dbPath then return nil, nil end
    local parts = { strsplit(".", reg.dbPath) }
    local t = ns.db.profile
    for i = 1, #parts - 1 do
        if type(t) ~= "table" then return nil, nil end
        if not t[parts[i]] then t[parts[i]] = {} end
        t = t[parts[i]]
    end
    return t, parts[#parts]
end

local function GetDefaultPos(reg)
    if reg.posType == "skyriding" then
        local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.SkyridingTracker
        return "CENTER", (defaults and defaults.posX) or 0, (defaults and defaults.posY) or 0
    end

    if reg.dbPath and ns.defaults and ns.defaults.profile then
        local value = ns.defaults.profile
        for part in reg.dbPath:gmatch("[^.]+") do
            value = type(value) == "table" and value[part] or nil
            if value == nil then break end
        end
        if type(value) == "table" then
            return value.point or "CENTER", value.x or 0, value.y or 0, value.relativePoint
        end
    end

    local fallback = DEFAULT_POSITIONS[reg.name] or { x = 0, y = 0 }
    return "CENTER", fallback.x, fallback.y, "CENTER"
end

local function SavePos(reg, point, x, y)
    if reg.posType == "none" then return end

    if reg.posType == "skyriding" then
        local db = ns.db.profile.SkyridingTracker
        if db then
            db.posX = x
            db.posY = y
            local mod = ns.SkyridingTracker
            if mod and mod.ApplyPosition then mod:ApplyPosition() end
        end
        return
    end

    -- standard
    local tbl, key = GetPosTable(reg)
    if tbl and key then
        tbl[key] = { point = point, relativePoint = point, x = x, y = y }
    end
end

local function NotifyPositionChanged(reg)
    if reg and reg.onPositionChanged then
        pcall(reg.onPositionChanged, reg)
    end
end

local function GetSavedPos(reg)
    if reg.posType == "skyriding" then
        local db = ns.db.profile.SkyridingTracker
        if db then return "CENTER", db.posX or 0, db.posY or 0 end
        return "CENTER", 0, 0
    end
    if reg.posType == "none" then
        return "TOP", 0, -100
    end
    -- standard
    local tbl, key = GetPosTable(reg)
    if tbl and key and tbl[key] and tbl[key].point then
        return tbl[key].point, tbl[key].x or 0, tbl[key].y or 0
    end
    return "CENTER", 0, 0
end

-- ============================================================
-- Frame / Module resolution
-- ============================================================
GetTargetFrame = function(reg)
    if reg.getFrame then return reg.getFrame() end
    if reg.frameName then return _G[reg.frameName] end
    return nil
end

local function ShowPreviewTarget(reg)
    local tf = GetTargetFrame(reg)
    if not tf then return end
    if tf.IsShown and not tf:IsShown() then
        forcedPreviewTargets[reg.name] = tf
    end
    if tf.Show then tf:Show() end
end

local function RestorePreviewTarget(reg)
    local tf = forcedPreviewTargets[reg.name]
    if tf and tf.Hide then
        tf:Hide()
    end
    forcedPreviewTargets[reg.name] = nil
end

local function RestorePreviewTargets()
    for name, frame in pairs(forcedPreviewTargets) do
        if frame and frame.Hide then
            frame:Hide()
        end
        forcedPreviewTargets[name] = nil
    end
end

local function GetReg(name)
    for _, r in ipairs(REG) do
        if r.name == name then return r end
    end
    return nil
end

local function GetModule(name)
    if ns[name] then return ns[name] end
    if DDingToolKit.modules then return DDingToolKit.modules[name] end
    return nil
end

local function IsRegistryAvailable(reg)
    return GetModule(reg.module) ~= nil or GetTargetFrame(reg) ~= nil
end

local function IsModuleEnabled(reg)
    if not (ns.db and ns.db.profile and ns.db.profile.modules) then return true end
    local v = ns.db.profile.modules[reg.module]
    return v == true
end

local function ShouldShowInPreview(reg)
    local previewState = reg.previewState
    if type(previewState) == "function" then
        previewState = previewState(reg)
    end
    if previewState == "combat" then
        return editPreviewCombat
    end
    if previewState == "noncombat" then
        return not editPreviewCombat
    end
    return true
end

local function ModuleShouldPreview(moduleName)
    for _, reg in ipairs(REG) do
        if reg.module == moduleName and ShouldShowInPreview(reg) then
            return true
        end
    end
    return false
end

local function GetPreviewContext()
    return {
        combat = editPreviewCombat,
        mode = editPreviewCombat and "combat" or "noncombat",
    }
end

local function SetModulePreview(moduleName, active)
    local mod = GetModule(moduleName)
    if not mod then return end

    if active then
        if not mod.enabled and not modulePreviewInitialized[moduleName] then
            if mod.OnInitialize then
                mod:OnInitialize()
            end
            modulePreviewInitialized[moduleName] = true
        end
        if modulePreviewActive[moduleName] then
            if mod.RefreshEditPreview then
                mod:RefreshEditPreview(GetPreviewContext())
            end
            return
        end
        if mod.EnterEditPreview then
            mod:EnterEditPreview(GetPreviewContext())
        end
        modulePreviewActive[moduleName] = true
    else
        if modulePreviewActive[moduleName] and mod.ExitEditPreview then
            mod:ExitEditPreview(GetPreviewContext())
        end
        modulePreviewActive[moduleName] = nil
    end
end

local function RefreshModulePreviews()
    local seen = {}
    for _, reg in ipairs(REG) do
        if not seen[reg.module] then
            seen[reg.module] = true
            SetModulePreview(reg.module, ModuleShouldPreview(reg.module))
        end
    end
end

-- Snap (StyleLib maths): centre, the visible grid, other movers. Returns x, y, snappedX, snappedY.
-- Grid snapping follows the "격자" snap checkbox, not whether the grid is drawn.
CalculateSnapPosition = function(mover, x, y)
    if not editorSettings.snapEnabled then return x, y, nil, nil end
    local threshold = editorSettings.snapThreshold or SPEC.snapThreshold
    local bestDx, bestDy = nil, nil

    local function Consider(dx, dy)
        if dx and dx ~= 0 and (not bestDx or math.abs(dx) < math.abs(bestDx)) then bestDx = dx end
        if dy and dy ~= 0 and (not bestDy or math.abs(dy) < math.abs(bestDy)) then bestDy = dy end
    end

    if editorSettings.snapToCenter then
        local sx, hitX = Lib.SnapToCenter(x, threshold)
        local sy, hitY = Lib.SnapToCenter(y, threshold)
        Consider(hitX and (sx - x) or nil, hitY and (sy - y) or nil)
    end

    if editorSettings.snapToGrid then
        local spacing = editorSettings.gridSize or SPEC.gridSpacing
        local sx, hitX = Lib.SnapToGrid(x, spacing, threshold)
        local sy, hitY = Lib.SnapToGrid(y, spacing, threshold)
        Consider(hitX and (sx - x) or nil, hitY and (sy - y) or nil)
    end

    if editorSettings.snapToFrames then
        local width, height = mover:GetSize()
        width = math.max(1, width or 1)
        height = math.max(1, height or 1)
        local rect = { x - width / 2, y - height / 2, width, height }
        local others = {}
        for name, target in pairs(movers) do
            if target ~= mover and target:IsShown() and target:GetAlpha() > 0.05 and moverPos[name] then
                local targetW, targetH = target:GetSize()
                targetW = math.max(1, targetW or 1)
                targetH = math.max(1, targetH or 1)
                others[#others + 1] = {
                    moverPos[name].x - targetW / 2, moverPos[name].y - targetH / 2, targetW, targetH,
                }
            end
        end
        if #others > 0 then
            local dx, dy = Lib.SnapToRects(rect, others, threshold)
            Consider(dx, dy)
        end
    end

    -- A candidate that already sits on the line counts as snapped (guide shown, no movement).
    local snappedX = bestDx ~= nil
    local snappedY = bestDy ~= nil
    if not snappedX and editorSettings.snapToCenter and math.abs(x) < 0.5 then snappedX = true end
    if not snappedY and editorSettings.snapToCenter and math.abs(y) < 0.5 then snappedY = true end
    return x + (bestDx or 0), y + (bestDy or 0), snappedX or nil, snappedY or nil
end

-- ============================================================
-- Undo / Redo
-- ============================================================
local function RefreshUndoButtons()
    if remote and remote.SetUndoState then
        remote:SetUndoState(#undoStack > 0, #redoStack > 0)
    end
end

local function PushUndo(name, x, y)
    table.insert(undoStack, { name = name, x = x, y = y })
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
    wipe(redoStack)
    RefreshUndoButtons()
end

local function RefreshResetButton()
    local btn = remote and remote.buttons and remote.buttons["초기화"]
    if btn and btn.SetDisabledState then btn:SetDisabledState(selected == nil) end
end

UpdateCoordUI = function(name, x, y)
    if name then
        UpdateMoverReadout(movers[name], x, y)
    end
    if not remote then return end
    if not name then
        remote:SetSelection(nil)
        RefreshResetButton()
        return
    end
    local reg = GetReg(name)
    local overlay = movers[name]
    local width, height = overlay and overlay:GetSize()
    remote:SetSelection({
        name = reg and GetDisplayName(reg) or name,
        anchor = "UIParent  ·  CENTER",
        x = x, y = y, w = width or 0, h = height or 0,
    })
    if remote.frameDropdown and remote.frameDropdown.SetValue then
        remote.frameDropdown:SetValue(name)
    end
    RefreshResetButton()
end

local function ApplyOvPos(name, x, y)
    x = math.floor(x + 0.5)
    y = math.floor(y + 0.5)
    moverPos[name] = { x = x, y = y }
    local ov = movers[name]
    if ov then
        ov:ClearAllPoints()
        ov:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    for _, reg in ipairs(REG) do
        if reg.name == name then
            local tf = GetTargetFrame(reg)
            local s = GetFrameRelativeScale(tf)
            SavePos(reg, "CENTER", x / s, y / s)
            if tf then
                tf:ClearAllPoints()
                tf:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
            end
            NotifyPositionChanged(reg)
            break
        end
    end
    UpdateCoordUI(name, x, y)
end

function Movers:Undo()
    if #undoStack == 0 then return end
    local entry = table.remove(undoStack)
    -- 현재 위치 -> redo에 저장
    local cur = moverPos[entry.name] or { x = 0, y = 0 }
    table.insert(redoStack, { name = entry.name, x = cur.x, y = cur.y })
    ApplyOvPos(entry.name, entry.x, entry.y)
    RefreshUndoButtons()
end

function Movers:Redo()
    if #redoStack == 0 then return end
    local entry = table.remove(redoStack)
    -- 현재 위치 -> undo에 저장
    local cur = moverPos[entry.name] or { x = 0, y = 0 }
    table.insert(undoStack, { name = entry.name, x = cur.x, y = cur.y })
    ApplyOvPos(entry.name, entry.x, entry.y)
    RefreshUndoButtons()
end

--- dx/dy already include the Shift ×10 step (the remote applies it).
function Movers:Nudge(dx, dy)
    if not selected then return end
    local pos = moverPos[selected] or { x = 0, y = 0 }
    PushUndo(selected, pos.x, pos.y)
    ApplyOvPos(selected, pos.x + dx, pos.y + dy)
end

function Movers:SetSelectedPosition(x, y)
    if not selected then return end
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then return end
    local pos = moverPos[selected] or { x = 0, y = 0 }
    if math.abs(pos.x - x) < 0.5 and math.abs(pos.y - y) < 0.5 then return end
    PushUndo(selected, pos.x, pos.y)
    ApplyOvPos(selected, x, y)
end

-- ============================================================
-- Overlay creation
-- ============================================================
local function RefreshMoverStyle(ov)
    if not ov or not ov.surface then return end
    local enabled = IsModuleEnabled(ov._reg)
    ov.surface:SetDisabled(not enabled, Locale("DISABLED", "Disabled"))
    ov.surface:SetHover(ov._hover)
    ov.surface:SetSelected(ov._selected)
    if ov.selectionHUD then
        ov.selectionHUD:SetShown(ov._selected)
    end
end

local function SetMoverSelected(ov, isSelected)
    if not ov then return end
    ov._selected = isSelected and true or false
    RefreshMoverStyle(ov)
end

local function SelectMover(name)
    local overlay = name and movers[name]
    if not overlay or not overlay:IsShown() then return false end
    if selected and movers[selected] and selected ~= name then
        SetMoverSelected(movers[selected], false)
    end
    selected = name
    SetMoverSelected(overlay, true)
    local position = moverPos[name] or { x = 0, y = 0 }
    UpdateCoordUI(name, position.x, position.y)
    return true
end

FinishDrag = function(overlay)
    if not overlay or not _isDragging then return end
    local reg = overlay._reg
    _isDragging = false
    _dragMover = nil
    _dragUpdate:Hide()
    UpdateSnapGuides(nil, nil)

    local position = moverPos[reg.name] or { x = 0, y = 0 }
    local x, y = position.x, position.y
    if CalculateSnapPosition then
        x, y = CalculateSnapPosition(overlay, x, y)
    end
    if overlay._dragStartX
        and (math.abs(x - overlay._dragStartX) > 0.5 or math.abs(y - overlay._dragStartY) > 0.5)
    then
        PushUndo(reg.name, overlay._dragStartX, overlay._dragStartY)
    end
    overlay._dragStartX = nil
    overlay._dragStartY = nil
    ApplyOvPos(reg.name, x, y)
end

local function CreateMoverOverlay(reg)
    local ov = CreateFrame("Button", "DDingToolKitMover_" .. reg.name, UIParent)
    ov:SetSize(reg.defaultW or 120, reg.defaultH or 40)
    ov:SetFrameStrata("DIALOG")
    ov:SetFrameLevel(200)
    ov:SetClampedToScreen(true)
    ov:EnableMouse(true)
    ov._reg = reg
    ov._regName = reg.name

    -- [STYLE] series mover surface + selection HUD (StyleLib 1.4)
    ov.surface = Lib.StyleMover(ov, ADDON_KEY, { label = GetDisplayName(reg) })
    ov.label = ov.surface.label
    ov.selectionHUD = Lib.CreateMoverHUD(ov, ADDON_KEY)

    local pt, px, py = GetSavedPos(reg)
    moverPos[reg.name] = { x = px, y = py }
    ov:SetPoint("CENTER", UIParent, pt, px, py)
    UpdateMoverReadout(ov, px, py)
    RefreshMoverStyle(ov)

    -- Cursor-driven drag keeps scaling and snapping deterministic.
    ov:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local pos = moverPos[reg.name] or { x = 0, y = 0 }
        self._dragStartX = pos.x
        self._dragStartY = pos.y
        SelectMover(reg.name)
        -- 드래그 오프셋: 마우스와 프레임 센터 간 거리
        local cx2, cy2 = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        cx2, cy2 = cx2 / uiScale, cy2 / uiScale
        local sw, sh = UIParent:GetSize()
        _dragOffX = cx2 - sw/2 - pos.x
        _dragOffY = cy2 - sh/2 - pos.y
        _isDragging = true
        _dragMover = self
        _dragUpdate:Show()
    end)

    ov:SetScript("OnMouseUp", function(self, btn)
        if btn ~= "LeftButton" or not _isDragging then return end
        FinishDrag(self)
    end)

    ov:SetScript("OnClick", function(self, btn)
        if btn and btn ~= "LeftButton" then return end
        SelectMover(reg.name)
    end)
    ov:SetScript("OnEnter", function(self)
        self._hover = true
        RefreshMoverStyle(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(GetDisplayName(reg), 1, 1, 1)
        GameTooltip:AddLine(Locale("EDIT_MODE_DRAG_HINT", "Drag to move"), 0.72, 0.75, 0.80)
        GameTooltip:AddLine(Locale("EDIT_MODE_KEY_HINT", "Arrow keys: fine adjustment"), 0.72, 0.75, 0.80)
        GameTooltip:Show()
    end)
    ov:SetScript("OnLeave", function(self)
        self._hover = false
        RefreshMoverStyle(self)
        GameTooltip:Hide()
    end)
    EnableRightClickMouselook(ov)

    return ov
end

local function SyncMoverToTarget(reg, targetFrame)
    local ov = movers[reg.name]
    if not ov then return end

    local tf = targetFrame or GetTargetFrame(reg)
    if not tf then return end

    local w, h = tf:GetSize()
    local s = GetFrameRelativeScale(tf)
    if w and h and w > 1 and h > 1 then
        ov:SetSize(w * s, h * s)
    end

    local cx, cy = tf:GetCenter()
    if cx and cy then
        local uiScale = UIParent:GetEffectiveScale()
        local fScale = tf:GetEffectiveScale()
        local sw, sh = UIParent:GetSize()
        local fx = (cx * fScale / uiScale) - (sw / 2)
        local fy = (cy * fScale / uiScale) - (sh / 2)
        ov:ClearAllPoints()
        ov:SetPoint("CENTER", UIParent, "CENTER", fx, fy)
        moverPos[reg.name] = { x = math.floor(fx + 0.5), y = math.floor(fy + 0.5) }
        UpdateMoverReadout(ov, moverPos[reg.name].x, moverPos[reg.name].y)
    end
end

function Movers:SyncFromTarget(name, targetFrame)
    local reg = GetReg(name)
    if not reg then return false end

    SyncMoverToTarget(reg, targetFrame)
    if selected == name then
        local position = moverPos[name]
        if position then UpdateCoordUI(name, position.x, position.y) end
    end
    return true
end

local function GetFrameOptions()
    local options = {}
    for _, reg in ipairs(REG) do
        local overlay = movers[reg.name]
        if overlay and overlay:IsShown() then
            local label = GetDisplayName(reg)
            if not IsModuleEnabled(reg) then
                label = label .. "  |cff777777(" .. Locale("DISABLED", "Disabled") .. ")|r"
            end
            options[#options + 1] = { text = label, value = reg.name }
        end
    end
    table.sort(options, function(a, b) return a.text < b.text end)
    return options
end

local function RefreshFrameSelector()
    if remote and remote.RefreshFrames then
        remote:RefreshFrames(selected)
    end
end

function Movers:ResetSelected()
    if not selected then return end
    local reg = GetReg(selected)
    if not reg then return end
    local current = moverPos[selected] or { x = 0, y = 0 }
    PushUndo(selected, current.x, current.y)
    local target = GetTargetFrame(reg)
    local point, x, y, relativePoint = GetDefaultPos(reg)

    if reg.posType == "skyriding" then
        local db = ns.db and ns.db.profile and ns.db.profile.SkyridingTracker
        if db then
            db.posX, db.posY = x, y
        end
    elseif reg.posType == "standard" then
        local tbl, key = GetPosTable(reg)
        if tbl and key then
            tbl[key] = {
                point = point,
                relativePoint = relativePoint or point,
                x = x,
                y = y,
            }
        end
    end

    if target then
        target:ClearAllPoints()
        target:SetPoint(point, UIParent, relativePoint or point, x, y)
        SyncMoverToTarget(reg)
        local position = moverPos[selected] or { x = 0, y = 0 }
        UpdateCoordUI(selected, position.x, position.y)
        NotifyPositionChanged(reg)
    else
        ApplyOvPos(selected, x, y)
    end
end

local function UpdatePreviewButtons()
    if remote and remote.previewControl and remote.previewControl.SetValue then
        remote.previewControl:SetValue(editPreviewCombat, true)
    end
end

local function RefreshPreviewVisibility(useFade)
    for _, reg in ipairs(REG) do
        local ov = movers[reg.name]
        if ov then
            local visible = ShouldShowInPreview(reg)
            if visible then
                ShowPreviewTarget(reg)
                SyncMoverToTarget(reg)
                if useFade then FadeIn(ov) else ov:SetAlpha(1); ov:Show() end
            else
                if selected == reg.name then
                    SetMoverSelected(ov, false)
                    selected = nil
                    UpdateCoordUI(nil)
                end
                RestorePreviewTarget(reg)
                if useFade then FadeOut(ov) else ov:Hide() end
            end
        end
    end

    if selected then
        local reg = GetReg(selected)
        if not reg or not ShouldShowInPreview(reg) then
            selected = nil
            UpdateCoordUI(nil)
        end
    end
end

local function RefreshEditPreviewMode(useFade)
    RefreshModulePreviews()
    for _, reg in ipairs(REG) do
        if IsRegistryAvailable(reg) and not movers[reg.name] then
            movers[reg.name] = CreateMoverOverlay(reg)
        end
    end
    RefreshPreviewVisibility(useFade)
    RefreshFrameSelector()
    UpdatePreviewButtons()
end

local function SetPreviewCombat(combat)
    combat = not not combat
    if editPreviewCombat == combat then
        if configMode then
            RefreshEditPreviewMode(true)
        end
        UpdatePreviewButtons()
        return
    end
    editPreviewCombat = combat
    if configMode then
        RefreshEditPreviewMode(true)
    else
        UpdatePreviewButtons()
    end
end

-- ============================================================
-- Remote (StyleLib CreateEditRemote) -- [STYLE]
-- ============================================================
local function BuildRemote()
    local r
    r = Lib.CreateEditRemote(ADDON_KEY, {
        title = "DDingUI Toolkit",
        version = DDingToolKit.version,
        frames = GetFrameOptions,
        onSelectFrame = function(value) SelectMover(value) end,
        onNudge = function(dx, dy) Movers:Nudge(dx, dy) end,
        onApplyXY = function(x, y) Movers:SetSelectedPosition(x, y) end,
        onReset = function() Movers:ResetSelected() end,
        onUndo = function() Movers:Undo() end,
        onRedo = function() Movers:Redo() end,
        onDone = function() if configMode then Movers:ToggleConfigMode() end end,
        onEscape = function() if configMode then Movers:ToggleConfigMode() end end,
        grid = {
            enabled = editorSettings.gridEnabled,
            spacing = editorSettings.gridSize,
            -- SetGridState re-enters these through the checkbox; return when nothing changed.
            onToggle = function(on)
                on = on and true or false
                if editorSettings.gridEnabled == on then return end
                editorSettings.gridEnabled = on
                SaveEditorSettings()
                RefreshGrid()
            end,
            onSpacing = function(n)
                n = NearestGridChoice(n)
                if editorSettings.gridSize == n then return end
                editorSettings.gridSize = n
                SaveEditorSettings()
                RefreshGrid()
            end,
        },
        snap = {
            enabled = editorSettings.snapEnabled,
            center = editorSettings.snapToCenter,
            grid = editorSettings.snapToGrid,
            frames = editorSettings.snapToFrames,
            onChange = function(key, on)
                on = on and true or false
                if key == "enabled" then editorSettings.snapEnabled = on
                elseif key == "center" then editorSettings.snapToCenter = on
                elseif key == "grid" then editorSettings.snapToGrid = on
                elseif key == "frames" then editorSettings.snapToFrames = on
                end
                SaveEditorSettings()
            end,
        },
        -- Toolkit-only: combat / non-combat preview switch.
        extra = function(parent, y)
            local controls = ns.ToolkitControls
            if not (controls and controls.CreateSegmentedControl) then return 0 end
            local width = (parent:GetWidth() or 300) - 28
            local control = controls.CreateSegmentedControl(parent, ADDON_KEY,
                Locale("EDIT_MODE_PREVIEW", "Preview"), {
                    { text = Locale("EDIT_MODE_NONCOMBAT", "Non-combat"), value = false },
                    { text = Locale("EDIT_MODE_COMBAT", "Combat"), value = true },
                }, editPreviewCombat, {
                    width = width,
                    onChange = function(value) SetPreviewCombat(value == true) end,
                })
            control:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
            parent.previewControl = control
            return (control:GetHeight() or 64) + 6
        end,
        loadPosition = LoadRemotePosition,
        savePosition = SaveRemotePosition,
    })
    EnableRightClickMouselook(r)
    return r
end

-- ============================================================
-- ShowMovers / HideMovers
-- ============================================================
function Movers:ShowMovers()
    LoadEditorSettings()
    if not remote then
        remote = BuildRemote()
    end
    RefreshEditPreviewMode(true)
    RefreshFrameSelector()
    UpdatePreviewButtons()
    UpdateCoordUI(nil)
    if remote.ShowAnimated then remote:ShowAnimated() else remote:Show() end
    RefreshGrid()
    wipe(undoStack)
    wipe(redoStack)
    RefreshUndoButtons()
end

function Movers:HideMovers()
    -- 드래그 중이면 정리
    _isDragging = false; _dragMover = nil; _dragUpdate:Hide()
    UpdateSnapGuides(nil, nil)
    for _, ov in pairs(movers) do
        SetMoverSelected(ov, false)
        FadeOut(ov)
    end
    if remote and remote:IsShown() then
        -- [STYLE] StyleLib 1.4: HideAnimated really closes (BindPanel shrink, pairs with the open
        -- motion; immediate in combat). Only the title-bar X calls onDone.
        if remote.HideAnimated then remote:HideAnimated() else remote:Hide() end
    end
    if grid and grid:IsShown() then grid:HideAnimated() end
    SaveEditorSettings()
    selected = nil
    RestorePreviewTargets()

    local calledExit = {}
    for _, reg in ipairs(REG) do
        if not calledExit[reg.module] then
            calledExit[reg.module] = true
            local mod = GetModule(reg.module)
            if mod and mod.ExitEditPreview then
                mod:ExitEditPreview()
            end
        end
    end
    wipe(modulePreviewActive)

    wipe(undoStack)
    wipe(redoStack)
    print(CHAT_PREFIX .. Locale("EDIT_MODE_SAVED", "Positions saved."))
end

-- ============================================================
-- Public toggle
-- ============================================================
--- opts.reopenConfig = false: do not bring the settings window back on exit
--- (used by ConfigUI:Show, which is already opening it).
function Movers:ToggleConfigMode(opts)
    if InCombatLockdown() then
        print(CHAT_PREFIX .. Locale("EDIT_MODE_COMBAT_BLOCKED", "Edit mode is unavailable during combat."))
        return
    end
    if not configMode and not HasEditModeLib() then
        ns.PrintError("Edit mode needs the embedded DDingUI StyleLib 1.4 (EditMode.lua).")
        return
    end
    configMode = not configMode
    if configMode then
        local config = ns.ConfigUI
        reopenConfig = (config and config.IsShown and config:IsShown()) and true or false
        if reopenConfig then config:Hide() end
        self:ShowMovers()
        print(CHAT_PREFIX .. Locale("EDIT_MODE_ENABLED_CHAT", "|cff33bfe6Edit mode enabled|r. Drag a frame to move it."))
    else
        self:HideMovers()
        local reopen = reopenConfig and not (type(opts) == "table" and opts.reopenConfig == false)
        reopenConfig = false
        if reopen and ns.ConfigUI and ns.ConfigUI.Show then
            ns.ConfigUI:Show()
        end
    end
    NotifyStateCallbacks()
end

function Movers:IsActive() return configMode end

function Movers:GetEditorSettings() return editorSettings end

function Movers:RegisterStateCallback(callback)
    if type(callback) ~= "function" then return end
    stateCallbacks[callback] = true
end

function Movers:UnregisterStateCallback(callback)
    stateCallbacks[callback] = nil
end

-- ============================================================
-- Combat auto-exit + init
-- ============================================================
local _initFrame = CreateFrame("Frame")
_initFrame:RegisterEvent("PLAYER_LOGIN")
_initFrame:SetScript("OnEvent", function()
    _initFrame:UnregisterAllEvents()
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and configMode then
            configMode = false
            reopenConfig = false -- combat: leave the settings window closed
            Movers:HideMovers()
            NotifyStateCallbacks()
            print(CHAT_PREFIX .. Locale("EDIT_MODE_COMBAT_EXIT", "Edit mode closed because combat started."))
        end
    end)
end)
