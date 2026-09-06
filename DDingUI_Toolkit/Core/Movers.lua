-- DDingUI Toolkit - Edit mode

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit")
    or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: "

local Movers = {}
ns.ToolkitMovers = Movers

local function Locale(key, fallback)
    local value = L and rawget(L, key)
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

local function GetAccent()
    if SL and SL.GetAccent then
        local color = SL.GetAccent("MJToolkit")
        if color then return color[1] or 0.2, color[2] or 0.75, color[3] or 1 end
    end
    return 0.2, 0.75, 1
end

local function EnableRightClickMouselook(frame)
    if ns.EnableRightClickMouselook then
        ns:EnableRightClickMouselook(frame)
    end
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
        name = "PartyTracker",
        frameName = "DDingToolKit_PartyTrackerFrame",
        dbPath = "PartyTracker.position",
        posType = "standard",
        module = "PartyTracker",
        previewState = "combat",
        defaultW = 150, defaultH = 200,
    },
    {
        name = "PartyTracker_Mana",
        frameName = "DDingToolKit_PartyTrackerManaFrame",
        dbPath = "PartyTracker.manaPosition",
        posType = "standard",
        module = "PartyTracker",
        previewState = "combat",
        defaultW = 150, defaultH = 150,
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
    PartyTracker = { x = -500, y = -110 },
    PartyTracker_Mana = { x = 0, y = -150 },
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
        PartyTracker = Locale("TAB_PARTYTRACKER", "Party Tracker"),
        PartyTracker_Mana = Locale("PARTYTRACKER_HEALER_MANA", "Healer Mana"),
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
local editorSettings = {
    gridEnabled = false,
    gridSize = 20,
    snapEnabled = true,
    snapToGrid = true,
    snapToFrames = true,
    snapToCenter = true,
    snapThreshold = 10,
}
local editPreviewCombat = false
local nudgeFrame  = nil
local eventFrame  = nil
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

local function GetFrameRelativeScale(frame)
    if not frame then return 1 end
    local uiScale = UIParent:GetEffectiveScale() or 1
    local frameScale = frame:GetEffectiveScale() or uiScale
    if uiScale <= 0 or frameScale <= 0 then return 1 end
    return frameScale / uiScale
end

local function UpdateMoverReadout(overlay, x, y)
    if not overlay or not overlay.coord then return end
    local width, height = overlay:GetSize()
    overlay.coord:SetText(string.format(
        "X %d  Y %d  ·  %d×%d",
        math.floor((x or 0) + 0.5),
        math.floor((y or 0) + 0.5),
        math.floor((width or 0) + 0.5),
        math.floor((height or 0) + 0.5)
    ))
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
    local guideX, guideY
    if CalculateSnapPosition then
        nx, ny, guideX, guideY = CalculateSnapPosition(_dragMover, nx, ny)
    end
    UpdateSnapGuides(guideX, guideY)
    _dragMover:ClearAllPoints()
    _dragMover:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
    moverPos[_dragMover._regName] = { x = nx, y = ny }
    local target = GetTargetFrame and GetTargetFrame(_dragMover._reg)
    if target then
        local targetScale = GetFrameRelativeScale(target)
        target:ClearAllPoints()
        target:SetPoint("CENTER", UIParent, "CENTER", nx / targetScale, ny / targetScale)
    end
    UpdateMoverReadout(_dragMover, nx, ny)
    if nudgeFrame then
        nudgeFrame.coordLabel:SetText(
            (_dragMover.label and _dragMover.label:GetText()) or _dragMover._regName
        )
        if nudgeFrame.inputX then
            nudgeFrame.inputX._lastVal = tostring(math.floor(nx+0.5))
            nudgeFrame.inputX:SetText(nudgeFrame.inputX._lastVal)
            nudgeFrame.inputY._lastVal = tostring(math.floor(ny+0.5))
            nudgeFrame.inputY:SetText(nudgeFrame.inputY._lastVal)
        end
    end
end)

-- Snap guide lines (shown during drag)
local _snapGuideV, _snapGuideH
local function _EnsureSnapGuides()
    if _snapGuideV then return end
    _snapGuideV = UIParent:CreateTexture(nil, "OVERLAY")
    _snapGuideV:SetColorTexture(1, 0.2, 0.2, 0.75)
    _snapGuideV:SetSize(2, UIParent:GetHeight())
    _snapGuideV:Hide()
    _snapGuideH = UIParent:CreateTexture(nil, "OVERLAY")
    _snapGuideH:SetColorTexture(1, 0.2, 0.2, 0.75)
    _snapGuideH:SetSize(UIParent:GetWidth(), 2)
    _snapGuideH:Hide()
end

UpdateSnapGuides = function(guideX, guideY)
    _EnsureSnapGuides()
    if guideX then
        _snapGuideV:ClearAllPoints()
        _snapGuideV:SetPoint("CENTER", UIParent, "BOTTOMLEFT", guideX, UIParent:GetHeight()/2)
        _snapGuideV:Show()
    else
        _snapGuideV:Hide()
    end
    if guideY then
        _snapGuideH:ClearAllPoints()
        _snapGuideH:SetPoint("CENTER", UIParent, "BOTTOMLEFT", UIParent:GetWidth()/2, guideY)
        _snapGuideH:Show()
    else
        _snapGuideH:Hide()
    end
end

-- Fade helpers
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

local gridLines = {}
local visualGridFrame

local function DrawVisualGrid()
    if not visualGridFrame then
        visualGridFrame = CreateFrame("Frame", "DDingToolKitVisualGrid", UIParent)
        visualGridFrame:SetAllPoints(UIParent)
        visualGridFrame:SetFrameStrata("BACKGROUND")
        visualGridFrame:SetFrameLevel(0)
    end

    for _, t in ipairs(gridLines) do t:Hide() end
    local lineIdx = 1

    local function MakeLine(w, h, p1, p2, x, y, r, g, b, a)
        local t = gridLines[lineIdx]
        if not t then
            t = visualGridFrame:CreateTexture(nil, "BACKGROUND")
            gridLines[lineIdx] = t
        end
        t:SetColorTexture(r, g, b, a)
        t:SetWidth(w)
        t:SetHeight(h)
        t:ClearAllPoints()
        t:SetPoint(p1, visualGridFrame, p1, x, y)
        t:SetPoint(p2, visualGridFrame, p2, x, y)
        t:Show()
        lineIdx = lineIdx + 1
    end

    local sw, sh = UIParent:GetSize()
    MakeLine(1, sh, "TOP", "BOTTOM", 0, 0, 1, 0, 0, 0.6)
    MakeLine(sw, 1, "LEFT", "RIGHT", 0, 0, 1, 0, 0, 0.6)

    local halfW = math.floor(sw / 2)
    local halfH = math.floor(sh / 2)
    local gridSize = editorSettings.gridSize
    for x = gridSize, halfW, gridSize do
        MakeLine(1, sh, "TOP", "BOTTOM", x, 0, 0.8, 0.8, 0.8, 0.15)
        MakeLine(1, sh, "TOP", "BOTTOM", -x, 0, 0.8, 0.8, 0.8, 0.15)
    end
    for y = gridSize, halfH, gridSize do
        MakeLine(sw, 1, "LEFT", "RIGHT", 0, y, 0.8, 0.8, 0.8, 0.15)
        MakeLine(sw, 1, "LEFT", "RIGHT", 0, -y, 0.8, 0.8, 0.8, 0.15)
    end
end

local function ToggleVisualGrid()
    if editorSettings.gridEnabled then
        DrawVisualGrid()
        visualGridFrame:Show()
    else
        if visualGridFrame then visualGridFrame:Hide() end
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

local function LoadEditorSettings()
    local saved = GetEditorDB()
    if not saved then return end
    for key, default in pairs(editorSettings) do
        if saved[key] ~= nil and type(saved[key]) == type(default) then
            editorSettings[key] = saved[key]
        end
    end
    editorSettings.gridSize = math.max(10, math.min(80, tonumber(editorSettings.gridSize) or 20))
    editorSettings.snapThreshold = math.max(4, math.min(30, tonumber(editorSettings.snapThreshold) or 10))
end

local function SaveEditorSettings()
    local saved = GetEditorDB()
    if not saved then return end
    for key, value in pairs(editorSettings) do
        saved[key] = value
    end
end

local function SavePanelPosition(frame)
    local saved = GetEditorDB()
    if not saved or not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    saved.panelPosition = {
        point = point or "BOTTOM",
        relativePoint = relativePoint or point or "BOTTOM",
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 80) + 0.5),
    }
end

local function LoadPanelPosition(frame)
    local saved = GetEditorDB()
    local position = saved and saved.panelPosition
    frame:ClearAllPoints()
    if type(position) == "table" and position.point then
        frame:SetPoint(
            position.point,
            UIParent,
            position.relativePoint or position.point,
            position.x or 0,
            position.y or 80
        )
    else
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 80)
    end
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

CalculateSnapPosition = function(mover, x, y)
    if not editorSettings.snapEnabled then return x, y, nil, nil end

    local threshold = editorSettings.snapThreshold
    local screenW, screenH = UIParent:GetSize()
    local bestX, bestY = x, y
    local bestXDistance, bestYDistance = threshold + 0.001, threshold + 0.001
    local guideX, guideY

    local function ConsiderX(candidate, guide)
        local distance = math.abs(candidate - x)
        if distance < bestXDistance then
            bestXDistance = distance
            bestX = candidate
            guideX = guide + (screenW / 2)
        end
    end

    local function ConsiderY(candidate, guide)
        local distance = math.abs(candidate - y)
        if distance < bestYDistance then
            bestYDistance = distance
            bestY = candidate
            guideY = guide + (screenH / 2)
        end
    end

    if editorSettings.snapToCenter then
        ConsiderX(0, 0)
        ConsiderY(0, 0)
    end

    if editorSettings.gridEnabled and editorSettings.snapToGrid then
        local gridSize = editorSettings.gridSize
        local gridX = math.floor(x / gridSize + 0.5) * gridSize
        local gridY = math.floor(y / gridSize + 0.5) * gridSize
        ConsiderX(gridX, gridX)
        ConsiderY(gridY, gridY)
    end

    if editorSettings.snapToFrames then
        local width, height = mover:GetSize()
        width = math.max(1, width or 1)
        height = math.max(1, height or 1)

        for name, target in pairs(movers) do
            if target ~= mover and target:IsShown() and target:GetAlpha() > 0.05 then
                local targetPosition = moverPos[name]
                if targetPosition then
                    local targetW, targetH = target:GetSize()
                    targetW = math.max(1, targetW or 1)
                    targetH = math.max(1, targetH or 1)
                    local targetX, targetY = targetPosition.x, targetPosition.y
                    local verticalOverlap = math.abs(y - targetY) <= ((height + targetH) / 2 + threshold)
                    local horizontalOverlap = math.abs(x - targetX) <= ((width + targetW) / 2 + threshold)

                    if verticalOverlap then
                        ConsiderX(targetX, targetX)
                        ConsiderX(targetX - targetW / 2 + width / 2, targetX - targetW / 2)
                        ConsiderX(targetX + targetW / 2 - width / 2, targetX + targetW / 2)
                        ConsiderX(targetX - targetW / 2 - width / 2, targetX - targetW / 2)
                        ConsiderX(targetX + targetW / 2 + width / 2, targetX + targetW / 2)
                    end

                    if horizontalOverlap then
                        ConsiderY(targetY, targetY)
                        ConsiderY(targetY - targetH / 2 + height / 2, targetY - targetH / 2)
                        ConsiderY(targetY + targetH / 2 - height / 2, targetY + targetH / 2)
                        ConsiderY(targetY - targetH / 2 - height / 2, targetY - targetH / 2)
                        ConsiderY(targetY + targetH / 2 + height / 2, targetY + targetH / 2)
                    end
                end
            end
        end
    end

    return bestX, bestY, guideX, guideY
end

-- ============================================================
-- Undo / Redo
-- ============================================================
local function RefreshUndoButtons()
    if not nudgeFrame then return end
    nudgeFrame.undoBtn:SetEnabled(#undoStack > 0)
    nudgeFrame.redoBtn:SetEnabled(#redoStack > 0)
    if nudgeFrame.undoBtn.RefreshStyle then nudgeFrame.undoBtn:RefreshStyle() end
    if nudgeFrame.redoBtn.RefreshStyle then nudgeFrame.redoBtn:RefreshStyle() end
end

local function PushUndo(name, x, y)
    table.insert(undoStack, { name = name, x = x, y = y })
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
    wipe(redoStack)
    RefreshUndoButtons()
end

local function UpdateCoordUI(name, x, y)
    if not nudgeFrame then return end
    if not name then
        nudgeFrame.coordLabel:SetText(Locale("EDIT_MODE_SELECT_PROMPT", "Select a frame to edit"))
        if nudgeFrame.metaLabel then
            nudgeFrame.metaLabel:SetText("UIParent")
        end
        if nudgeFrame.frameSelect and nudgeFrame.frameSelect.SetValue then
            nudgeFrame.frameSelect:SetValue(nil, true)
        end
        if nudgeFrame.inputX then
            nudgeFrame.inputX:SetText("")
            nudgeFrame.inputX:ClearFocus()
            nudgeFrame.inputY:SetText("")
            nudgeFrame.inputY:ClearFocus()
        end
        if nudgeFrame.RefreshSettings then nudgeFrame:RefreshSettings() end
        return
    end
    local reg = GetReg(name)
    nudgeFrame.coordLabel:SetText(reg and GetDisplayName(reg) or name)
    if nudgeFrame.frameSelect and nudgeFrame.frameSelect.SetValue then
        nudgeFrame.frameSelect:SetValue(name, true)
    end
    if nudgeFrame.inputX then
        nudgeFrame.inputX._lastVal = tostring(math.floor(x + 0.5))
        nudgeFrame.inputX:SetText(nudgeFrame.inputX._lastVal)
        nudgeFrame.inputY._lastVal = tostring(math.floor(y + 0.5))
        nudgeFrame.inputY:SetText(nudgeFrame.inputY._lastVal)
    end
    local overlay = movers[name]
    UpdateMoverReadout(overlay, x, y)
    if nudgeFrame.metaLabel then
        local width, height = overlay and overlay:GetSize()
        nudgeFrame.metaLabel:SetText(string.format(
            "UIParent  ·  CENTER  ·  %d × %d",
            math.floor((width or 0) + 0.5),
            math.floor((height or 0) + 0.5)
        ))
    end
    if nudgeFrame.RefreshSettings then nudgeFrame:RefreshSettings() end
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

function Movers:Nudge(dx, dy)
    if not selected then return end
    local pos = moverPos[selected] or { x = 0, y = 0 }
    PushUndo(selected, pos.x, pos.y)
    ApplyOvPos(selected, pos.x + dx, pos.y + dy)
end

-- ============================================================
-- Overlay creation
-- ============================================================
local function RefreshMoverStyle(ov)
    if not ov then return end
    local reg = ov._reg
    local enabled = IsModuleEnabled(reg)
    local accentR, accentG, accentB = GetAccent()
    if ov._selected then
        ov:SetBackdropBorderColor(accentR, accentG, accentB, 1)
        ov:SetBackdropColor(accentR * 0.20, accentG * 0.20, accentB * 0.20, 0.82)
        if ov.label then ov.label:SetTextColor(1, 1, 1, 1) end
    elseif ov._hover then
        ov:SetBackdropBorderColor(1, 0.67, 0.18, 1)
        ov:SetBackdropColor(0.18, 0.14, 0.07, 0.72)
        if ov.label then ov.label:SetTextColor(1, 0.88, 0.65, 1) end
    else
        local r = enabled and accentR or 0.42
        local g = enabled and accentG or 0.42
        local b = enabled and accentB or 0.42
        ov:SetBackdropBorderColor(r, g, b, enabled and 0.88 or 0.65)
        ov:SetBackdropColor(r * 0.12, g * 0.12, b * 0.12, enabled and 0.58 or 0.48)
        if ov.label then ov.label:SetTextColor(enabled and 0.92 or 0.62, enabled and 0.94 or 0.62, enabled and 0.96 or 0.62, 1) end
    end
    if ov.centerV then
        ov.centerV:SetColorTexture(accentR, accentG, accentB, 0.78)
        ov.centerH:SetColorTexture(accentR, accentG, accentB, 0.78)
        ov.centerV:SetShown(ov._selected)
        ov.centerH:SetShown(ov._selected)
    end
    if ov.selectionHUD then
        ov.selectionHUD.accent:SetColorTexture(accentR, accentG, accentB, 1)
        ov.selectionHUD:SetShown(ov._selected)
    end
    if ov.disabledLabel then ov.disabledLabel:SetShown(not enabled) end
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
    local enabled = IsModuleEnabled(reg)
    local r = enabled and 0.20 or 0.45
    local g = enabled and 0.75 or 0.45
    local b = enabled and 0.30 or 0.45

    local ov = CreateFrame("Button", "DDingToolKitMover_" .. reg.name, UIParent, "BackdropTemplate")
    ov:SetSize(reg.defaultW or 120, reg.defaultH or 40)
    ov:SetFrameStrata("DIALOG")
    ov:SetFrameLevel(200)
    ov:SetClampedToScreen(true)
    ov:EnableMouse(true)
    ov:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 2 })
    ov:SetBackdropColor(r, g, b, 0.35)
    ov:SetBackdropBorderColor(r, g, b, 0.85)
    ov._reg = reg
    ov._regName = reg.name

    local centerV = ov:CreateTexture(nil, "ARTWORK")
    centerV:SetPoint("CENTER")
    centerV:SetSize(1, 12)
    centerV:SetColorTexture(r, g, b, 0.78)
    centerV:Hide()
    ov.centerV = centerV

    local centerH = ov:CreateTexture(nil, "ARTWORK")
    centerH:SetPoint("CENTER")
    centerH:SetSize(12, 1)
    centerH:SetColorTexture(r, g, b, 0.78)
    centerH:Hide()
    ov.centerH = centerH

    local lbl = ov:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(SL_FONT, 11, "OUTLINE")
    lbl:SetPoint("LEFT", ov, "LEFT", 4, 4)
    lbl:SetPoint("RIGHT", ov, "RIGHT", -4, 4)
    lbl:SetJustifyH("CENTER")
    lbl:SetWordWrap(false)
    lbl:SetText(GetDisplayName(reg))
    lbl:SetTextColor(1, 1, 1, 1)
    ov.label = lbl

    local selectionHUD = CreateFrame("Frame", nil, ov)
    selectionHUD:SetSize(178, 18)
    selectionHUD:SetPoint("TOPRIGHT", ov, "BOTTOMRIGHT", 0, -4)
    selectionHUD:SetFrameLevel(ov:GetFrameLevel() + 2)
    selectionHUD:SetClampedToScreen(true)
    selectionHUD:Hide()

    local hudBg = selectionHUD:CreateTexture(nil, "BACKGROUND")
    hudBg:SetAllPoints()
    local hudColor = SL and SL.Colors and SL.Colors.bg and SL.Colors.bg.input or { 0.025, 0.035, 0.05 }
    hudBg:SetColorTexture(hudColor[1], hudColor[2], hudColor[3], 0.94)

    local hudAccent = selectionHUD:CreateTexture(nil, "BORDER")
    hudAccent:SetPoint("TOPLEFT")
    hudAccent:SetPoint("BOTTOMLEFT")
    hudAccent:SetWidth(2)
    hudAccent:SetColorTexture(r, g, b, 1)
    selectionHUD.accent = hudAccent

    local coord = selectionHUD:CreateFontString(nil, "OVERLAY")
    coord:SetFont(SL_FONT, 9, "OUTLINE")
    coord:SetPoint("LEFT", 7, 0)
    coord:SetTextColor(0.88, 0.91, 0.96, 1)
    ov.coord = coord
    ov.selectionHUD = selectionHUD

    local disabledLabel = ov:CreateFontString(nil, "OVERLAY")
    disabledLabel:SetFont(SL_FONT, 8, "OUTLINE")
    disabledLabel:SetPoint("TOPRIGHT", -3, -2)
    disabledLabel:SetText(Locale("DISABLED", "Disabled"))
    disabledLabel:SetTextColor(0.72, 0.72, 0.74, 1)
    disabledLabel:SetShown(not enabled)
    ov.disabledLabel = disabledLabel

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

local function RefreshFrameSelector()
    if not nudgeFrame or not nudgeFrame.frameSelect or not nudgeFrame.frameSelect.SetOptions then return end
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
    nudgeFrame.frameSelect:SetOptions(options, selected)
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
    if not nudgeFrame then return end
    if nudgeFrame.nonCombatBtn and nudgeFrame.nonCombatBtn.SetActive then
        nudgeFrame.nonCombatBtn:SetActive(not editPreviewCombat)
    end
    if nudgeFrame.combatBtn and nudgeFrame.combatBtn.SetActive then
        nudgeFrame.combatBtn:SetActive(editPreviewCombat)
    end
    if nudgeFrame.previewLabel then
        nudgeFrame.previewLabel:SetText(Locale("EDIT_MODE_PREVIEW", "Preview"))
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
-- NudgeFrame
-- ============================================================
local function MakeBtn(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 30, h or 22)
    b:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1 })
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(SL_FONT, 11, "OUTLINE")
    fs:SetAllPoints()
    fs:SetText(text)
    b:SetScript("OnClick", onClick)
    b._fs = fs

    function b:RefreshStyle(hover)
        if self.IsEnabled and not self:IsEnabled() then
            self:SetBackdropColor(0.08, 0.08, 0.11, 0.9)
            self:SetBackdropBorderColor(0.18, 0.18, 0.24, 0.9)
            self._fs:SetTextColor(0.45, 0.45, 0.50, 1)
        elseif self._active then
            self:SetBackdropColor(0.08, 0.34, 0.48, 1)
            self:SetBackdropBorderColor(0.35, 0.80, 1.0, 1)
            self._fs:SetTextColor(1, 1, 1, 1)
        elseif hover then
            self:SetBackdropColor(0.22, 0.22, 0.30, 1)
            self:SetBackdropBorderColor(0.35, 0.35, 0.45, 1)
            self._fs:SetTextColor(1, 1, 1, 1)
        else
            self:SetBackdropColor(0.12, 0.12, 0.18, 1)
            self:SetBackdropBorderColor(0.25, 0.25, 0.35, 1)
            self._fs:SetTextColor(0.92, 0.92, 0.92, 1)
        end
    end

    function b:SetActive(active)
        self._active = active and true or false
        self:RefreshStyle(self._hover)
    end

    function b:SetText(value)
        self._fs:SetText(value or "")
    end

    b:SetScript("OnEnter", function(s) s._hover = true; s:RefreshStyle(true) end)
    b:SetScript("OnLeave", function(s) s._hover = false; s:RefreshStyle(false) end)
    b:RefreshStyle(false)
    return b
end

local function SetControlTooltip(frame, title, description)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        if description and description ~= "" then
            GameTooltip:AddLine(description, 0.72, 0.75, 0.80, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function MakeInputBox(parent, text, w, h, onEnter)
    local wrap = CreateFrame("Frame", nil, parent)
    wrap:SetSize(w, h)
    local lbl = wrap:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(SL_FONT, 10, "OUTLINE")
    lbl:SetPoint("LEFT", wrap, "LEFT", 0, 0)
    lbl:SetText(text)
    local edit = CreateFrame("EditBox", nil, wrap, "BackdropTemplate")
    edit:SetSize(w - 15, h)
    edit:SetPoint("RIGHT", wrap, "RIGHT", 0, 0)
    edit:SetFont(SL_FONT, 10, "OUTLINE")
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1 })
    edit:SetBackdropColor(0.12, 0.12, 0.18, 1)
    edit:SetBackdropBorderColor(0.25, 0.25, 0.35, 1)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onEnter then onEnter(tonumber(self:GetText())) end
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(self._lastVal or "0")
    end)
    edit._wrapper = wrap
    return edit
end

local function BuildNudgeFrame()
    local f = CreateFrame("Frame", "DDingToolKitNudgeFrame", UIParent, "BackdropTemplate")
    f:SetSize(620, 284)
    LoadPanelPosition(f)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(250)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    EnableRightClickMouselook(f)
    f:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 2 })
    f:SetBackdropColor(0.035, 0.035, 0.045, 0.98)
    f:SetBackdropBorderColor(0.12, 0.12, 0.15, 1)

    local accentR, accentG, accentB = GetAccent()
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    header:SetHeight(34)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePanelPosition(f)
    end)

    local headerBG = header:CreateTexture(nil, "BACKGROUND")
    headerBG:SetAllPoints()
    headerBG:SetColorTexture(0.085, 0.085, 0.105, 1)
    local headerAccent = header:CreateTexture(nil, "ARTWORK")
    headerAccent:SetPoint("BOTTOMLEFT")
    headerAccent:SetPoint("BOTTOMRIGHT")
    headerAccent:SetHeight(2)
    headerAccent:SetColorTexture(accentR, accentG, accentB, 1)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont(SL_FONT, 13, "OUTLINE")
    title:SetPoint("LEFT", 12, 0)
    title:SetText(Locale("EDIT_MODE_TITLE", "DDingUI Toolkit Edit Mode"))

    local closeBtn = MakeBtn(header, "×", 26, 24, function() Movers:ToggleConfigMode() end)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -5, 0)
    SetControlTooltip(closeBtn, Locale("CLOSE", "Close"), Locale("EDIT_MODE_CLOSE_DESC", "Save positions and leave edit mode."))

    local controls = ns.ToolkitControls
    if controls and controls.CreateDropdown then
        local frameSelect = controls.CreateDropdown(
            f,
            "MJToolkit",
            Locale("EDIT_MODE_FRAME", "Frame"),
            {},
            nil,
            {
                width = 360,
                searchable = true,
                placeholder = Locale("EDIT_MODE_SELECT_PROMPT", "Select a frame to edit"),
                emptyText = Locale("EDIT_MODE_NO_FRAMES", "No frames are available in this preview."),
                onChange = function(value)
                    SelectMover(value)
                end,
            }
        )
        frameSelect:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -43)
        frameSelect:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -43)
        f.frameSelect = frameSelect
    end

    local coordLabel = f:CreateFontString(nil, "OVERLAY")
    coordLabel:SetFont(SL_FONT, 12, "OUTLINE")
    coordLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -78)
    coordLabel:SetText(Locale("EDIT_MODE_SELECT_PROMPT", "Select a frame to edit"))
    coordLabel:SetTextColor(0.95, 0.95, 0.97, 1)
    f.coordLabel = coordLabel

    local metaLabel = f:CreateFontString(nil, "OVERLAY")
    metaLabel:SetFont(SL_FONT, 10, "OUTLINE")
    metaLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -80)
    metaLabel:SetText("UIParent")
    metaLabel:SetTextColor(0.54, 0.56, 0.62, 1)
    f.metaLabel = metaLabel

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -99)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -99)
    divider:SetHeight(1)
    divider:SetColorTexture(0.20, 0.20, 0.23, 0.85)

    local function SectionLabel(text, x)
        local label = f:CreateFontString(nil, "OVERLAY")
        label:SetFont(SL_FONT, 10, "OUTLINE")
        label:SetPoint("TOPLEFT", f, "TOPLEFT", x, -110)
        label:SetText(text)
        label:SetTextColor(0.58, 0.60, 0.66, 1)
        return label
    end

    SectionLabel(Locale("EDIT_MODE_NUDGE", "Fine position"), 20)
    SectionLabel(Locale("EDIT_MODE_COORDINATES", "Coordinates"), 178)
    local previewLabel = SectionLabel(Locale("EDIT_MODE_PREVIEW", "Preview"), 410)
    f.previewLabel = previewLabel

    local inputX = MakeInputBox(f, "X", 90, 24, function(val)
        if selected and val then
            local curY = tonumber(f.inputY._lastVal) or 0
            PushUndo(selected, tonumber(f.inputX._lastVal) or 0, curY)
            ApplyOvPos(selected, val, curY)
        end
    end)
    inputX._wrapper:SetPoint("TOPLEFT", f, "TOPLEFT", 178, -137)
    f.inputX = inputX

    local inputY = MakeInputBox(f, "Y", 90, 24, function(val)
        if selected and val then
            local curX = tonumber(f.inputX._lastVal) or 0
            PushUndo(selected, curX, tonumber(f.inputY._lastVal) or 0)
            ApplyOvPos(selected, curX, val)
        end
    end)
    inputY._wrapper:SetPoint("LEFT", inputX._wrapper, "RIGHT", 12, 0)
    f.inputY = inputY

    local up = MakeBtn(f, "▲", 32, 24, function() Movers:Nudge(0, 1) end)
    local down = MakeBtn(f, "▼", 32, 24, function() Movers:Nudge(0, -1) end)
    local left = MakeBtn(f, "◀", 32, 24, function() Movers:Nudge(-1, 0) end)
    local right = MakeBtn(f, "▶", 32, 24, function() Movers:Nudge(1, 0) end)
    up:SetPoint("TOPLEFT", f, "TOPLEFT", 72, -128)
    down:SetPoint("TOP", up, "BOTTOM", 0, 4)
    left:SetPoint("RIGHT", down, "LEFT", -4, 0)
    right:SetPoint("LEFT", down, "RIGHT", 4, 0)
    SetControlTooltip(up, Locale("EDIT_MODE_NUDGE", "Fine position"), Locale("EDIT_MODE_SHIFT_HINT", "Hold Shift for 10-pixel steps."))

    local nonCombatBtn = MakeBtn(f, Locale("EDIT_MODE_NONCOMBAT", "Non-combat"), 82, 26, function() SetPreviewCombat(false) end)
    nonCombatBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 410, -136)
    f.nonCombatBtn = nonCombatBtn

    local combatBtn = MakeBtn(f, Locale("EDIT_MODE_COMBAT", "Combat"), 82, 26, function() SetPreviewCombat(true) end)
    combatBtn:SetPoint("LEFT", nonCombatBtn, "RIGHT", 6, 0)
    f.combatBtn = combatBtn

    local snapBtn = MakeBtn(f, "", 96, 24, function()
        editorSettings.snapEnabled = not editorSettings.snapEnabled
        SaveEditorSettings()
        f:RefreshSettings()
    end)
    snapBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -190)
    f.snapBtn = snapBtn

    local gridBtn = MakeBtn(f, "", 96, 24, function()
        editorSettings.gridEnabled = not editorSettings.gridEnabled
        SaveEditorSettings()
        ToggleVisualGrid()
        f:RefreshSettings()
    end)
    gridBtn:SetPoint("LEFT", snapBtn, "RIGHT", 8, 0)
    f.gridBtn = gridBtn

    local frameSnapBtn = MakeBtn(f, "", 108, 24, function()
        editorSettings.snapToFrames = not editorSettings.snapToFrames
        SaveEditorSettings()
        f:RefreshSettings()
    end)
    frameSnapBtn:SetPoint("LEFT", gridBtn, "RIGHT", 8, 0)
    f.frameSnapBtn = frameSnapBtn

    local centerSnapBtn = MakeBtn(f, "", 108, 24, function()
        editorSettings.snapToCenter = not editorSettings.snapToCenter
        SaveEditorSettings()
        f:RefreshSettings()
    end)
    centerSnapBtn:SetPoint("LEFT", frameSnapBtn, "RIGHT", 8, 0)
    f.centerSnapBtn = centerSnapBtn

    local gridSizeBtn = MakeBtn(f, "", 92, 24, function()
        local sizes = { 10, 20, 40, 80 }
        local nextSize = sizes[1]
        for index, size in ipairs(sizes) do
            if size == editorSettings.gridSize then
                nextSize = sizes[(index % #sizes) + 1]
                break
            end
        end
        editorSettings.gridSize = nextSize
        SaveEditorSettings()
        if editorSettings.gridEnabled then ToggleVisualGrid() end
        f:RefreshSettings()
    end)
    gridSizeBtn:SetPoint("LEFT", centerSnapBtn, "RIGHT", 8, 0)
    f.gridSizeBtn = gridSizeBtn

    local resetBtn = MakeBtn(f, Locale("RESET_POSITION", "Reset"), 76, 24, function() Movers:ResetSelected() end)
    resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 14)
    f.resetBtn = resetBtn

    local undoBtn = MakeBtn(f, Locale("EDIT_MODE_UNDO", "Undo"), 68, 24, function() Movers:Undo() end)
    undoBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
    undoBtn:SetEnabled(false)
    undoBtn:RefreshStyle()
    f.undoBtn = undoBtn

    local redoBtn = MakeBtn(f, Locale("EDIT_MODE_REDO", "Redo"), 68, 24, function() Movers:Redo() end)
    redoBtn:SetPoint("LEFT", undoBtn, "RIGHT", 8, 0)
    redoBtn:SetEnabled(false)
    redoBtn:RefreshStyle()
    f.redoBtn = redoBtn

    local doneBtn = MakeBtn(f, Locale("EDIT_MODE_DONE", "Done"), 88, 26, function() Movers:ToggleConfigMode() end)
    doneBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 13)
    doneBtn:SetActive(true)
    f.doneBtn = doneBtn

    SetControlTooltip(resetBtn, Locale("RESET_POSITION", "Reset"), Locale("EDIT_MODE_RESET_DESC", "Restore the selected frame to its default position."))
    SetControlTooltip(snapBtn, Locale("EDIT_MODE_SNAP", "Snap"), Locale("EDIT_MODE_SNAP_DESC", "Enable or disable all position snapping."))
    SetControlTooltip(gridBtn, Locale("EDIT_MODE_GRID", "Grid"), Locale("EDIT_MODE_GRID_DESC", "Show the alignment grid and snap to it."))
    SetControlTooltip(frameSnapBtn, Locale("EDIT_MODE_FRAME_SNAP", "Frame snap"), Locale("EDIT_MODE_FRAME_SNAP_DESC", "Align edges and centers with other visible frames."))
    SetControlTooltip(centerSnapBtn, Locale("EDIT_MODE_CENTER_SNAP", "Center snap"), Locale("EDIT_MODE_CENTER_SNAP_DESC", "Align with the horizontal and vertical screen center."))

    function f:RefreshSettings()
        snapBtn:SetText(Locale("EDIT_MODE_SNAP", "Snap") .. (editorSettings.snapEnabled and "  ON" or "  OFF"))
        snapBtn:SetActive(editorSettings.snapEnabled)
        gridBtn:SetText(Locale("EDIT_MODE_GRID", "Grid") .. (editorSettings.gridEnabled and "  ON" or "  OFF"))
        gridBtn:SetActive(editorSettings.gridEnabled)
        frameSnapBtn:SetText(Locale("EDIT_MODE_FRAME_SNAP", "Frame snap"))
        frameSnapBtn:SetActive(editorSettings.snapEnabled and editorSettings.snapToFrames)
        centerSnapBtn:SetText(Locale("EDIT_MODE_CENTER_SNAP", "Center snap"))
        centerSnapBtn:SetActive(editorSettings.snapEnabled and editorSettings.snapToCenter)
        gridSizeBtn:SetText(string.format("%s  %d", Locale("EDIT_MODE_GRID_SIZE", "Grid"), editorSettings.gridSize))
        gridSizeBtn:SetActive(editorSettings.gridEnabled)
        resetBtn:SetEnabled(selected ~= nil)
        resetBtn:RefreshStyle()
    end

    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(self, key)
        if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then
            self:SetPropagateKeyboardInput(true)
            return
        end
        local handled = false
        local step = IsShiftKeyDown() and 10 or 1
        if key == "UP" then Movers:Nudge(0, step); handled = true
        elseif key == "DOWN" then Movers:Nudge(0, -step); handled = true
        elseif key == "LEFT" then Movers:Nudge(-step, 0); handled = true
        elseif key == "RIGHT" then Movers:Nudge(step, 0); handled = true
        elseif key == "ESCAPE" then Movers:ToggleConfigMode(); handled = true
        elseif IsControlKeyDown() and key == "Z" then Movers:Undo(); handled = true
        elseif IsControlKeyDown() and key == "Y" then Movers:Redo(); handled = true
        end
        self:SetPropagateKeyboardInput(not handled)
    end)
    f:SetScript("OnKeyUp", function(self)
        self:SetPropagateKeyboardInput(true)
    end)

    f:RefreshSettings()
    UpdatePreviewButtons()
    f:Hide()
    return f
end

-- ============================================================
-- ShowMovers / HideMovers
-- ============================================================
function Movers:ShowMovers()
    LoadEditorSettings()
    if not nudgeFrame then
        nudgeFrame = BuildNudgeFrame()
    end
    RefreshEditPreviewMode(true)
    RefreshFrameSelector()
    UpdatePreviewButtons()
    nudgeFrame:RefreshSettings()
    FadeIn(nudgeFrame)
    if editorSettings.gridEnabled then ToggleVisualGrid() end
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
    if nudgeFrame then FadeOut(nudgeFrame) end
    if visualGridFrame then visualGridFrame:Hide() end
    SaveEditorSettings()
    if nudgeFrame then SavePanelPosition(nudgeFrame) end
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
function Movers:ToggleConfigMode()
    if InCombatLockdown() then
        print(CHAT_PREFIX .. Locale("EDIT_MODE_COMBAT_BLOCKED", "Edit mode is unavailable during combat."))
        return
    end
    configMode = not configMode
    if configMode then
        if ns.ConfigUI and ns.ConfigUI.IsShown and ns.ConfigUI:IsShown() then
            ns.ConfigUI:Hide()
        end
        self:ShowMovers()
        print(CHAT_PREFIX .. Locale("EDIT_MODE_ENABLED_CHAT", "|cff33bfe6Edit mode enabled|r. Drag a frame to move it."))
    else
        self:HideMovers()
    end
    NotifyStateCallbacks()
end

function Movers:IsActive() return configMode end

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
            Movers:HideMovers()
            NotifyStateCallbacks()
            print(CHAT_PREFIX .. Locale("EDIT_MODE_COMBAT_EXIT", "Edit mode closed because combat started."))
        end
    end)
end)
