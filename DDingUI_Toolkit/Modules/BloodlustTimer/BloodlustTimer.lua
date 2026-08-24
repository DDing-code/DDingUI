-- DDingUI Toolkit - Bloodlust and exhaustion timer

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local SL = _G.DDingUI_StyleLib
local AlertStyle = ns.CalmAlertStyle

local BloodlustTimer = {}
ns.BloodlustTimer = BloodlustTimer

local ACTIVE_DURATION = 40
local EXHAUSTION_DURATION = 600
local UPDATE_INTERVAL = 0.05
local DEFAULT_ICON = 136012
local DEFAULT_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local DEFAULT_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local DEFAULT_ANIMATION_FOLDER = "DDingUI_Media\\Bloodlust"
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local ICON_GLOW_KEY = "DDingUI_BloodlustIcon"
local BAR_GLOW_KEY = "DDingUI_BloodlustBar"
local START_MOTION_STYLE_VERSION = 4
local SYSTEM_TEXTURE_ROOT = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\BloodlustSystem\\"
local SYSTEM_RING_OUTER = SYSTEM_TEXTURE_ROOT .. "RingOuter.tga"
local SYSTEM_RING_INNER = SYSTEM_TEXTURE_ROOT .. "RingInner.tga"
local SYSTEM_CREST = SYSTEM_TEXTURE_ROOT .. "Crest.tga"
local SYSTEM_CREST_CORE = SYSTEM_TEXTURE_ROOT .. "CrestCore.tga"

-- Detect the player-side lockout instead of individual drums or cast spells.
-- This covers every current 12.1 Bloodlust source and future sources that use
-- one of the standard exhaustion effects.
local EXHAUSTION_SPELLS = {
    [57723] = 32182,   -- Exhaustion -> Heroism
    [57724] = 2825,    -- Sated -> Bloodlust
    [80354] = 80353,   -- Temporal Displacement -> Time Warp
    [95809] = 90355,   -- Insanity -> Ancient Hysteria
    [160455] = 264667, -- Fatigued -> Primal Rage
    [264689] = 264667, -- Fatigued -> Primal Rage
    [390435] = 390386, -- Exhaustion -> Fury of the Aspects
}

local DEFAULT_POSITION = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -170,
}

local DEFAULT_START_MOTION_POSITION = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 40,
}

local START_MOTION_COLORS = {
    title = { 1.00, 0.76, 0.30, 1.00 },
    line = { 0.70, 0.40, 0.10, 0.96 },
    accent = { 0.72, 0.015, 0.025, 0.98 },
    pulse = { 1.00, 0.07, 0.025, 0.90 },
    panel = { 0.018, 0.002, 0.006, 0.90 },
    glow = { 0.88, 0.010, 0.015, 0.34 },
}

local START_MOTION_V3_COLORS = {
    title = { 1.00, 0.88, 0.58, 1.00 },
    line = { 0.84, 0.61, 0.28, 0.94 },
    accent = { 0.76, 0.055, 0.035, 0.92 },
    pulse = { 1.00, 0.20, 0.07, 0.82 },
    panel = { 0.055, 0.006, 0.012, 0.78 },
    glow = { 0.72, 0.025, 0.018, 0.28 },
}

local START_MOTION_V2_COLORS = {
    title = { 1.00, 0.84, 0.34, 1.00 },
    line = { 1.00, 0.56, 0.10, 0.96 },
    accent = { 0.20, 0.82, 1.00, 0.88 },
    pulse = { 1.00, 0.12, 0.06, 0.82 },
    panel = { 0.035, 0.025, 0.018, 0.82 },
    glow = { 1.00, 0.38, 0.08, 0.28 },
}

local SYSTEM_MOTION_COLORS = {
    title = { 1.00, 0.91, 0.82, 1.00 },
    ring = { 0.90, 0.92, 0.90, 0.94 },
    accent = { 0.98, 0.025, 0.56, 0.94 },
    pulse = { 0.90, 0.025, 0.075, 0.94 },
    panel = { 0.115, 0.002, 0.052, 0.82 },
    glow = { 0.98, 0.025, 0.56, 0.34 },
    crest = { 1.00, 0.82, 0.62, 1.00 },
    crestCore = { 0.90, 0.025, 0.075, 1.00 },
}

local START_MOTION_DIAMOND_EDGES = {
    { -0.5, 0.5, 45 },
    { 0.5, 0.5, -45 },
    { -0.5, -0.5, -45 },
    { 0.5, -0.5, 45 },
}

local START_MOTION_FILIGREE_SEGMENTS = {
    { 0.000, 0.010, 0.022, 0.070 },
    { 0.022, 0.070, 0.046, 0.025 },
    { 0.046, 0.025, 0.070, 0.065 },
    { 0.070, 0.065, 0.096, 0.015 },
    { 0.000, -0.018, 0.032, -0.058 },
    { 0.032, -0.058, 0.070, -0.014 },
}

local START_MOTION_EMBER_LAYOUT = {
    { -1, 0.12, -0.22, 0.045, 0.15, 4.0 },
    { -1, 0.25, 0.08, 0.060, 0.11, 3.0 },
    { -1, 0.36, -0.12, 0.035, 0.18, 2.5 },
    { 1, 0.14, -0.18, 0.050, 0.14, 3.5 },
    { 1, 0.27, 0.12, 0.055, 0.12, 2.5 },
    { 1, 0.38, -0.08, 0.030, 0.17, 3.0 },
}

local frame
local eventFrame = CreateFrame("Frame")
local activeModule = false
local editPreview = false
local testMode = false
local testStartedAt = 0
local testPhase = "ACTIVE"
local testSerial = 0
local animationPreview = false
local animationPreviewEndsAt = 0
local animationPreviewSerial = 0
local updateElapsed = 0
local animationElapsed = 0
local animationFrameIndex = 0
local animationPlaying = false
local startMotionFrame
local startMotionState
local musicHandle
local nextMusicAt
local suppressFreshUntil = 0

local state = {
    hasDebuff = false,
    phase = "READY",
    debuffSpellID = nil,
    buffSpellID = 2825,
    appliedAt = nil,
    activeEndsAt = nil,
    debuffEndsAt = nil,
    durationObject = nil,
    waitingForRemoval = false,
    serial = 0,
}

local function IsSecret(value)
    return (ns.IsSecretValue and ns.IsSecretValue(value))
        or (issecretvalue and issecretvalue(value))
        or false
end

local function SafeNumber(value)
    if IsSecret(value) or value == nil then return nil end
    local ok, number = pcall(tonumber, value)
    if not ok or IsSecret(number) then return nil end
    return number
end

local function StartMotionColorMatches(color, expected)
    if type(color) ~= "table" then return false end
    for index = 1, 4 do
        local value = SafeNumber(color[index])
        if value == nil or math.abs(value - expected[index]) > 0.001 then
            return false
        end
    end
    return true
end

local function CopyStartMotionColor(color)
    return { color[1], color[2], color[3], color[4] }
end

local function Clamp(value, minimum, maximum, fallback)
    value = SafeNumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

local function SafeBooleanCall(func, ...)
    if not func then return false end
    local ok, value = pcall(func, ...)
    if not ok or IsSecret(value) then return false end
    return value and true or false
end

local function CopyDefaultPosition()
    return {
        point = DEFAULT_POSITION.point,
        relativePoint = DEFAULT_POSITION.relativePoint,
        x = DEFAULT_POSITION.x,
        y = DEFAULT_POSITION.y,
    }
end

local function CopyDefaultStartMotionPosition()
    return {
        point = DEFAULT_START_MOTION_POSITION.point,
        relativePoint = DEFAULT_START_MOTION_POSITION.relativePoint,
        x = DEFAULT_START_MOTION_POSITION.x,
        y = DEFAULT_START_MOTION_POSITION.y,
    }
end

local function EnsureDB()
    local profile = ns.db and ns.db.profile
    if not profile then return nil end
    if type(profile.BloodlustTimer) ~= "table" then
        local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.BloodlustTimer
        profile.BloodlustTimer = defaults and ns:DeepCopy(defaults) or {}
    end
    local db = profile.BloodlustTimer
    if type(db.position) ~= "table" then
        db.position = CopyDefaultPosition()
    end
    if type(db.startMotionPosition) ~= "table" then
        db.startMotionPosition = CopyDefaultStartMotionPosition()
    end
    if db.startMotionStyle ~= "SYSTEM" and db.startMotionStyle ~= "RITUAL" then
        db.startMotionStyle = "RITUAL"
    end
    local styleVersion = SafeNumber(db.startMotionStyleVersion) or 1
    if styleVersion < 2 then
        if db.startMotionFontOutline == "THICKOUTLINE" then
            db.startMotionFontOutline = "OUTLINE"
        end
    end
    if styleVersion < 3 then
        local colorKeys = { "title", "line", "accent", "pulse", "panel", "glow" }
        for _, colorKey in ipairs(colorKeys) do
            local dbKey = "startMotion" .. colorKey:sub(1, 1):upper() .. colorKey:sub(2) .. "Color"
            if StartMotionColorMatches(db[dbKey], START_MOTION_V2_COLORS[colorKey]) then
                db[dbKey] = CopyStartMotionColor(START_MOTION_COLORS[colorKey])
            end
        end
    end
    if styleVersion < 4 then
        local colorKeys = { "title", "line", "accent", "pulse", "panel", "glow" }
        for _, colorKey in ipairs(colorKeys) do
            local dbKey = "startMotion" .. colorKey:sub(1, 1):upper() .. colorKey:sub(2) .. "Color"
            if StartMotionColorMatches(db[dbKey], START_MOTION_V3_COLORS[colorKey]) then
                db[dbKey] = CopyStartMotionColor(START_MOTION_COLORS[colorKey])
            end
        end
    end
    if styleVersion < START_MOTION_STYLE_VERSION then
        db.startMotionStyleVersion = START_MOTION_STYLE_VERSION
    end
    return db
end

local function NormalizeFolderName(folderName)
    folderName = tostring(folderName or "")
    folderName = folderName:gsub("/", "\\")
    folderName = folderName:gsub("^%s+", ""):gsub("%s+$", "")
    folderName = folderName:gsub("^Interface\\+", "")
    folderName = folderName:gsub("^\\+", ""):gsub("\\+$", "")
    folderName = folderName:gsub("\\+", "\\")
    folderName = folderName:gsub("[<>:\"|%?%*]", "")
    if folderName == "" or folderName:find("..", 1, true) then
        return DEFAULT_ANIMATION_FOLDER
    end
    return folderName
end

local function NormalizeTGAFileName(fileName)
    fileName = tostring(fileName or "")
    fileName = fileName:gsub("/", "\\")
    fileName = fileName:match("([^\\]+)$") or fileName
    fileName = fileName:gsub("^%s+", ""):gsub("%s+$", "")
    fileName = fileName:gsub("%.[Tt][Gg][Aa]$", "")
    return fileName:gsub("[<>:\"|%?%*]", "")
end

local function ResolveAnimationPath(db)
    if not db then return nil end
    local fileName = NormalizeTGAFileName(db.animationFile)
    if fileName == "" then return nil end
    return "Interface\\" .. NormalizeFolderName(db.animationFolder) .. "\\" .. fileName
end

local function ResolveSpellTexture(spellID)
    local texture
    if C_Spell and C_Spell.GetSpellTexture then
        texture = C_Spell.GetSpellTexture(spellID)
    elseif _G.GetSpellTexture then
        texture = _G.GetSpellTexture(spellID)
    end
    if IsSecret(texture) or texture == nil then return DEFAULT_ICON end
    return texture
end

local function SetBorderColor(target, r, g, b, a)
    target.borderTop:SetColorTexture(r, g, b, a)
    target.borderBottom:SetColorTexture(r, g, b, a)
    target.borderLeft:SetColorTexture(r, g, b, a)
    target.borderRight:SetColorTexture(r, g, b, a)
end

local function AddBorder(target)
    target.borderTop = target:CreateTexture(nil, "OVERLAY")
    target.borderTop:SetPoint("TOPLEFT")
    target.borderTop:SetPoint("TOPRIGHT")
    target.borderTop:SetHeight(1)
    target.borderBottom = target:CreateTexture(nil, "OVERLAY")
    target.borderBottom:SetPoint("BOTTOMLEFT")
    target.borderBottom:SetPoint("BOTTOMRIGHT")
    target.borderBottom:SetHeight(1)
    target.borderLeft = target:CreateTexture(nil, "OVERLAY")
    target.borderLeft:SetPoint("TOPLEFT")
    target.borderLeft:SetPoint("BOTTOMLEFT")
    target.borderLeft:SetWidth(1)
    target.borderRight = target:CreateTexture(nil, "OVERLAY")
    target.borderRight:SetPoint("TOPRIGHT")
    target.borderRight:SetPoint("BOTTOMRIGHT")
    target.borderRight:SetWidth(1)
    SetBorderColor(target, 0, 0, 0, 1)
end

local function SetBorderSize(target, size)
    size = math.max(0, size or 0)
    local shown = size > 0
    target.borderTop:SetShown(shown)
    target.borderBottom:SetShown(shown)
    target.borderLeft:SetShown(shown)
    target.borderRight:SetShown(shown)
    if not shown then return end
    target.borderTop:SetHeight(size)
    target.borderBottom:SetHeight(size)
    target.borderLeft:SetWidth(size)
    target.borderRight:SetWidth(size)
end

local function GetColor(color, fallback)
    if type(color) ~= "table" then color = fallback end
    return color[1] or fallback[1], color[2] or fallback[2], color[3] or fallback[3], color[4] or fallback[4] or 1
end

local function StopPixelGlow(target, key)
    if not target or not target._bltPixelGlowActive then return end
    if LCG then LCG.PixelGlow_Stop(target, key) end
    target._bltPixelGlowActive = nil
end

local function ApplyPixelGlow(target, key, enabled, color, fallback, db)
    if not LCG or not target or not enabled then
        StopPixelGlow(target, key)
        return
    end

    local r, g, b, a = GetColor(color, fallback)
    local lines = math.floor(Clamp(db.glowLines, 1, 20, 8))
    local frequency = Clamp(db.glowFrequency, 0.05, 2, 0.25)
    local length = Clamp(db.glowLength, 2, 40, 10)
    local thickness = Clamp(db.glowThickness, 1, 8, 2)
    local current = target._bltPixelGlowActive

    if current
        and current.r == r and current.g == g and current.b == b and current.a == a
        and current.lines == lines and current.frequency == frequency
        and current.length == length and current.thickness == thickness then
        return
    end

    StopPixelGlow(target, key)
    LCG.PixelGlow_Start(target, { r, g, b, a }, lines, frequency, length, thickness, 0, 0, false, key)
    target._bltPixelGlowActive = {
        r = r,
        g = g,
        b = b,
        a = a,
        lines = lines,
        frequency = frequency,
        length = length,
        thickness = thickness,
    }
end

local function BuildDurationObject(aura)
    if not aura then return nil end
    local auraInstanceID = aura.auraInstanceID
    if C_UnitAuras and C_UnitAuras.GetAuraDuration and not IsSecret(auraInstanceID) and auraInstanceID ~= nil then
        local ok, durationObject = pcall(C_UnitAuras.GetAuraDuration, "player", auraInstanceID)
        if ok and not IsSecret(durationObject) and durationObject then return durationObject end
    end
    if not C_DurationUtil or not C_DurationUtil.CreateDuration then return nil end
    local expirationTime = aura.expirationTime
    local duration = aura.duration
    local hasExpiration = IsSecret(expirationTime) or expirationTime ~= nil
    local hasDuration = IsSecret(duration) or duration ~= nil
    if not hasExpiration or not hasDuration then return nil end

    local durationObject = C_DurationUtil.CreateDuration()
    if not durationObject or not durationObject.SetTimeFromEnd then return nil end
    local ok = pcall(durationObject.SetTimeFromEnd, durationObject, expirationTime, duration)
    if not ok then return nil end
    return durationObject
end

local function FindExhaustionAura()
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end
    for debuffSpellID, buffSpellID in pairs(EXHAUSTION_SPELLS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, debuffSpellID)
        if ok and not IsSecret(aura) and type(aura) == "table" then
            return aura, debuffSpellID, buffSpellID
        end
    end
    return nil
end

local function GetAuraTimes(aura)
    if not aura then return nil, nil, nil end
    local expirationTime = SafeNumber(aura.expirationTime)
    local duration = SafeNumber(aura.duration)
    if not expirationTime or not duration or duration <= 0 then return nil, nil, nil end
    return expirationTime - duration, expirationTime, duration
end

local function GetSoundPath(db, prefix)
    if not db then return nil end
    local customPath = db[prefix .. "SoundCustomPath"]
    if type(customPath) == "string" and customPath ~= "" and ns:IsValidSoundPath(customPath) then
        return customPath
    end
    local soundFile = db[prefix .. "SoundFile"]
    if type(soundFile) == "string" and soundFile ~= "" then return soundFile end
    return nil
end

local function PlayConfiguredSound(db, prefix, request)
    local path = GetSoundPath(db, prefix)
    if not path then return nil end
    local channel = db[prefix .. "SoundChannel"] or "Master"

    if ns.RequestSound and type(request) == "table" then
        request.soundFile = path
        request.channel = channel
        return ns:RequestSound(request)
    end

    local ok, played, handle = pcall(PlaySoundFile, path, channel)
    if not ok or IsSecret(played) or not played or IsSecret(handle) then return nil end
    return handle
end

function BloodlustTimer:StopMusic(fadeMilliseconds)
    nextMusicAt = nil
    if ns.CancelManagedSound then
        ns:CancelManagedSound("BloodlustTimer:music", (fadeMilliseconds or 150) / 1000)
    elseif not IsSecret(musicHandle) and musicHandle ~= nil and StopSound then
        pcall(StopSound, musicHandle, fadeMilliseconds or 150)
    end
    musicHandle = nil
end

function BloodlustTimer:PlayMusicTrack()
    local db = self.db
    if not db or db.musicSoundEnabled ~= true then return end
    self:StopMusic(0)
    local requested = PlayConfiguredSound(db, "music", {
        source = "BloodlustTimer",
        key = "music",
        lane = "BACKGROUND",
        priority = 10,
        duration = ACTIVE_DURATION,
        expiresIn = ACTIVE_DURATION,
        persistent = true,
        isValid = function()
            return activeModule and (state.phase == "ACTIVE" or testMode)
        end,
        onStarted = function(handle)
            musicHandle = handle
        end,
        onStopped = function()
            musicHandle = nil
        end,
    })
    if db.musicLoop == true and requested then
        nextMusicAt = GetTime() + Clamp(db.musicRepeatInterval, 1, ACTIVE_DURATION, 10)
    end
end

function BloodlustTimer:StartMusic()
    if self.db and self.db.musicSoundEnabled == true then
        self:PlayMusicTrack()
    end
end

function BloodlustTimer:UpdateMusic(now, phase)
    if phase ~= "ACTIVE" or not nextMusicAt or now < nextMusicAt then return end
    self:PlayMusicTrack()
end

function BloodlustTimer:GetAnimationSettings()
    local db = self.db or {}
    local columns = math.floor(Clamp(db.animationColumns, 1, 32, 4))
    local rows = math.floor(Clamp(db.animationRows, 1, 32, 4))
    local maximum = columns * rows
    local count = math.floor(Clamp(db.animationFrameCount, 1, maximum, maximum))
    local fps = Clamp(db.animationFPS, 1, 60, 20)
    return columns, rows, count, fps
end

function BloodlustTimer:SetAnimationFrame(index)
    if not frame then return end
    local columns, rows, count = self:GetAnimationSettings()
    index = math.max(0, math.min(count - 1, index or 0))
    local column = index % columns
    local row = math.floor(index / columns)
    frame.animation:SetTexCoord(column / columns, (column + 1) / columns, row / rows, (row + 1) / rows)
end

function BloodlustTimer:StartAnimation(force)
    local db = self.db
    if not db or (db.animationEnabled ~= true and not force) then return end
    local path = ResolveAnimationPath(db)
    if not path then return end
    local display = self:CreateFrame()
    display.animation:SetTexture(path)
    display.animation:Show()
    animationFrameIndex = 0
    animationElapsed = 0
    animationPlaying = true
    self:SetAnimationFrame(0)
end

function BloodlustTimer:StopAnimation()
    animationPlaying = false
    animationElapsed = 0
    animationFrameIndex = 0
    if frame then frame.animation:Hide() end
end

function BloodlustTimer:UpdateAnimation(elapsed)
    if not animationPlaying or not frame then return end
    local _, _, count, fps = self:GetAnimationSettings()
    animationElapsed = animationElapsed + elapsed
    local interval = 1 / fps
    if animationElapsed < interval then return end

    local steps = math.max(1, math.floor(animationElapsed / interval))
    animationElapsed = animationElapsed - (steps * interval)
    animationFrameIndex = animationFrameIndex + steps
    if animationFrameIndex >= count then
        if (self.db and self.db.animationPlayback) == "ONCE" then
            self:StopAnimation()
            return
        end
        animationFrameIndex = animationFrameIndex % count
    end
    self:SetAnimationFrame(animationFrameIndex)
end

function BloodlustTimer:CreateFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "DDingToolKit_BloodlustTimerFrame", UIParent)
    frame:SetSize(266, 44)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)

    frame.animation = frame:CreateTexture(nil, "BACKGROUND")
    frame.animation:SetPoint("CENTER")
    frame.animation:Hide()

    frame.iconFrame = CreateFrame("Frame", nil, frame)
    frame.iconFrame:EnableMouse(false)
    frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.iconFrame.background = frame.iconFrame:CreateTexture(nil, "BACKGROUND")
    frame.iconFrame.background:SetAllPoints()
    frame.iconFrame.background:SetColorTexture(0.02, 0.025, 0.035, 0.94)
    AddBorder(frame.iconFrame)

    frame.cooldown = CreateFrame("Cooldown", nil, frame.iconFrame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetDrawSwipe(true)
    frame.cooldown:SetReverse(true)

    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetStatusBarTexture(DEFAULT_BAR)
    frame.bar:SetMinMaxValues(0, ACTIVE_DURATION)
    frame.bar:SetValue(ACTIVE_DURATION)
    frame.barBackground = frame.bar:CreateTexture(nil, "BACKGROUND")
    frame.barBackground:SetAllPoints()
    frame.barBackground:SetColorTexture(0.02, 0.025, 0.035, 0.9)
    AddBorder(frame.bar)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(DEFAULT_FONT, 14, "OUTLINE")
    frame.text:SetJustifyH("CENTER")
    frame.text:SetWordWrap(false)

    frame:Hide()
    self.frame = frame
    return frame
end

function BloodlustTimer:StopGlows()
    if not frame then return end
    StopPixelGlow(frame.iconFrame, ICON_GLOW_KEY)
    StopPixelGlow(frame.bar, BAR_GLOW_KEY)
end

function BloodlustTimer:UpdateGlows(snapshot, phaseEnabled)
    if not (frame and self.db) then return end
    local active = phaseEnabled and snapshot and snapshot.phase == "ACTIVE"
    local db = self.db

    ApplyPixelGlow(
        frame.iconFrame,
        ICON_GLOW_KEY,
        active and db.showIcon ~= false and db.iconGlowEnabled == true,
        db.iconGlowColor,
        { 1.00, 0.28, 0.10, 1.00 },
        db
    )
    ApplyPixelGlow(
        frame.bar,
        BAR_GLOW_KEY,
        active and db.showBar ~= false and db.barGlowEnabled == true,
        db.barGlowColor,
        { 1.00, 0.28, 0.10, 0.95 },
        db
    )
end

function BloodlustTimer:ApplyPosition()
    local db = self.db or EnsureDB()
    if not db then return end
    local display = self:CreateFrame()
    local position = db.position or DEFAULT_POSITION
    display:ClearAllPoints()
    display:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or position.point or "CENTER",
        SafeNumber(position.x) or 0,
        SafeNumber(position.y) or -170
    )
end

local function NormalizeTextPosition(position)
    if position == "ABOVE" or position == "BELOW" then return position end
    return "INSIDE"
end

local function NormalizeFrameStrata(strata)
    if strata == "MEDIUM" or strata == "DIALOG" then return strata end
    return "HIGH"
end

local function NormalizeStartMotionStyle(style)
    return style == "SYSTEM" and "SYSTEM" or "RITUAL"
end

local function ApplyStartMotionFont(fontString, font, size, flags)
    local ok, result = pcall(fontString.SetFont, fontString, font, size, flags)
    if not ok or result == false then
        fontString:SetFont(DEFAULT_FONT, size, flags)
    end
end

local function StartMotionColor(value, fallback)
    return type(value) == "table" and value or fallback
end

local function SetBrightenedStartMotionColor(target, color, fallback, amount)
    local r, g, b, a = GetColor(color, fallback)
    target[1] = r + (1 - r) * amount
    target[2] = g + (1 - g) * amount
    target[3] = b + (1 - b) * amount
    target[4] = a
    return target
end

local function CreateStartMotionTexture(parent, layer, subLevel, blendMode)
    local texture = AlertStyle.CreateFlatTexture(parent, layer, subLevel)
    if blendMode and texture.SetBlendMode then
        texture:SetBlendMode(blendMode)
    end
    return texture
end

local function CreateSystemAssetTexture(parent, texturePath, layer, subLevel, blendMode)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, subLevel)
    texture:SetTexture(texturePath)
    if blendMode and texture.SetBlendMode then
        texture:SetBlendMode(blendMode)
    end
    return texture
end

local function SetSystemAssetColor(texture, color, fallback, alpha)
    local red, green, blue, colorAlpha = GetColor(color, fallback)
    texture:SetVertexColor(red, green, blue, 1)
    texture:SetAlpha(AlertStyle.Clamp01((alpha or 1) * colorAlpha))
end

local function SetStartMotionSegment(texture, relativeTo, x1, y1, x2, y2, thickness)
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    local rotation = dx == 0 and (math.pi * 0.5) or math.atan(dy / dx)
    AlertStyle.SetCenteredRect(
        texture,
        math.max(1, length),
        math.max(1, thickness),
        relativeTo,
        (x1 + x2) * 0.5,
        (y1 + y2) * 0.5,
        rotation
    )
end

local function PlaceStartMotionDiamond(edges, glows, relativeTo, centerX, centerY, halfSize, lineThickness, glowThickness)
    local edgeLength = math.sqrt(2) * halfSize
    for index, geometry in ipairs(START_MOTION_DIAMOND_EDGES) do
        local edgeX = centerX + halfSize * geometry[1]
        local edgeY = centerY + halfSize * geometry[2]
        local rotation = math.rad(geometry[3])
        if glows then
            AlertStyle.SetCenteredRect(glows[index], edgeLength, glowThickness, relativeTo, edgeX, edgeY, rotation)
        end
        AlertStyle.SetCenteredRect(edges[index], edgeLength, lineThickness, relativeTo, edgeX, edgeY, rotation)
    end
end

function BloodlustTimer:CreateStartMotionFrame()
    if startMotionFrame then return startMotionFrame end
    if not AlertStyle then return nil end

    local display = CreateFrame("Frame", "DDingToolKit_BloodlustStartMotionFrame", UIParent)
    display:SetSize(620, 130)
    display:SetFrameStrata("DIALOG")
    display:SetClampedToScreen(true)
    display:EnableMouse(false)
    display:Hide()

    display.art = CreateFrame("Frame", nil, display)
    display.art:SetAllPoints(display)
    display.glowLeft = CreateStartMotionTexture(display.art, "BACKGROUND", -7, "ADD")
    display.glowRight = CreateStartMotionTexture(display.art, "BACKGROUND", -7, "ADD")
    display.panelLeft = CreateStartMotionTexture(display.art, "BACKGROUND", -5)
    display.panelRight = CreateStartMotionTexture(display.art, "BACKGROUND", -5)
    display.panelCoreLeft = CreateStartMotionTexture(display.art, "BACKGROUND", -4)
    display.panelCoreRight = CreateStartMotionTexture(display.art, "BACKGROUND", -4)

    display.topRuleGlowLeft = CreateStartMotionTexture(display.art, "ARTWORK", -3, "ADD")
    display.topRuleGlowRight = CreateStartMotionTexture(display.art, "ARTWORK", -3, "ADD")
    display.topRuleLeft = CreateStartMotionTexture(display.art, "ARTWORK", 0)
    display.topRuleRight = CreateStartMotionTexture(display.art, "ARTWORK", 0)
    display.bottomRuleGlowLeft = CreateStartMotionTexture(display.art, "ARTWORK", -3, "ADD")
    display.bottomRuleGlowRight = CreateStartMotionTexture(display.art, "ARTWORK", -3, "ADD")
    display.bottomRuleLeft = CreateStartMotionTexture(display.art, "ARTWORK", 0)
    display.bottomRuleRight = CreateStartMotionTexture(display.art, "ARTWORK", 0)

    display.filigreeLeft = {}
    display.filigreeRight = {}
    for index = 1, #START_MOTION_FILIGREE_SEGMENTS do
        display.filigreeLeft[index] = CreateStartMotionTexture(display.art, "ARTWORK", 1)
        display.filigreeRight[index] = CreateStartMotionTexture(display.art, "ARTWORK", 1)
    end

    display.sealBloom = CreateStartMotionTexture(display.art, "ARTWORK", -2, "ADD")
    display.sealFill = CreateStartMotionTexture(display.art, "ARTWORK", -1)
    display.sealOuterEdges = {}
    display.sealOuterGlows = {}
    display.sealInnerEdges = {}
    display.sealFinials = {}
    for index = 1, 4 do
        display.sealOuterGlows[index] = CreateStartMotionTexture(display.art, "ARTWORK", 0, "ADD")
        display.sealOuterEdges[index] = CreateStartMotionTexture(display.art, "ARTWORK", 2)
        display.sealInnerEdges[index] = CreateStartMotionTexture(display.art, "ARTWORK", 2)
        display.sealFinials[index] = CreateStartMotionTexture(display.art, "ARTWORK", 1)
    end
    display.gemGlow = CreateStartMotionTexture(display.art, "ARTWORK", 2, "ADD")
    display.gemFill = CreateStartMotionTexture(display.art, "ARTWORK", 3)
    display.gemCore = CreateStartMotionTexture(display.art, "ARTWORK", 4)

    display.endMedallionLeft = {}
    display.endMedallionRight = {}
    display.endMedallionCores = {}
    for index = 1, 4 do
        display.endMedallionLeft[index] = CreateStartMotionTexture(display.art, "ARTWORK", 1)
        display.endMedallionRight[index] = CreateStartMotionTexture(display.art, "ARTWORK", 1)
    end
    for index = 1, 2 do
        display.endMedallionCores[index] = CreateStartMotionTexture(display.art, "ARTWORK", 2, "ADD")
    end

    display.bottomJewelGlows = {}
    display.bottomJewels = {}
    for index = 1, 3 do
        display.bottomJewelGlows[index] = CreateStartMotionTexture(display.art, "ARTWORK", 1, "ADD")
        display.bottomJewels[index] = CreateStartMotionTexture(display.art, "ARTWORK", 2)
    end

    display.embers = {}
    for index = 1, #START_MOTION_EMBER_LAYOUT do
        display.embers[index] = CreateStartMotionTexture(display.art, "ARTWORK", 3, "ADD")
    end

    display.hotLineColor = {}
    display.hotAccentColor = {}

    display.titleGlow = display.art:CreateFontString(nil, "ARTWORK")
    display.titleGlow:SetJustifyH("CENTER")
    display.titleGlow:SetJustifyV("MIDDLE")
    display.titleGlow:SetWordWrap(false)
    display.title = display.art:CreateFontString(nil, "OVERLAY")
    display.title:SetJustifyH("CENTER")
    display.title:SetJustifyV("MIDDLE")
    display.title:SetWordWrap(false)
    display.title:SetShadowOffset(1, -1)
    display.title:SetShadowColor(0, 0, 0, 0.72)

    display.systemArt = CreateFrame("Frame", nil, display)
    display.systemArt:SetAllPoints(display)
    display.systemArt:Hide()
    display.systemPanelLeft = CreateStartMotionTexture(display.systemArt, "BACKGROUND", -6)
    display.systemPanelRight = CreateStartMotionTexture(display.systemArt, "BACKGROUND", -6)
    display.systemGlowLeft = CreateStartMotionTexture(display.systemArt, "BACKGROUND", -5, "ADD")
    display.systemGlowRight = CreateStartMotionTexture(display.systemArt, "BACKGROUND", -5, "ADD")

    display.systemTopLeft = CreateStartMotionTexture(display.systemArt, "ARTWORK", -2)
    display.systemTopRight = CreateStartMotionTexture(display.systemArt, "ARTWORK", -2)
    display.systemBottomLeft = CreateStartMotionTexture(display.systemArt, "ARTWORK", -2)
    display.systemBottomRight = CreateStartMotionTexture(display.systemArt, "ARTWORK", -2)
    display.systemScanLeft = CreateStartMotionTexture(display.systemArt, "ARTWORK", -1, "ADD")
    display.systemScanRight = CreateStartMotionTexture(display.systemArt, "ARTWORK", -1, "ADD")

    display.systemSideNodes = {}
    display.systemSideCores = {}
    for index = 1, 2 do
        display.systemSideNodes[index] = CreateStartMotionTexture(display.systemArt, "ARTWORK", 0)
        display.systemSideCores[index] = CreateStartMotionTexture(display.systemArt, "ARTWORK", 1, "ADD")
    end

    display.systemOuterRingGlow = CreateSystemAssetTexture(display.systemArt, SYSTEM_RING_OUTER, "ARTWORK", 0, "ADD")
    display.systemOuterRing = CreateSystemAssetTexture(display.systemArt, SYSTEM_RING_OUTER, "ARTWORK", 1, "ADD")
    display.systemAccentRing = CreateSystemAssetTexture(display.systemArt, SYSTEM_RING_OUTER, "ARTWORK", 2, "ADD")
    display.systemInnerRing = CreateSystemAssetTexture(display.systemArt, SYSTEM_RING_INNER, "ARTWORK", 3, "ADD")
    display.systemCrestGlow = CreateSystemAssetTexture(display.systemArt, SYSTEM_CREST, "ARTWORK", 3, "ADD")
    display.systemCrestCore = CreateSystemAssetTexture(display.systemArt, SYSTEM_CREST_CORE, "ARTWORK", 4, "ADD")
    display.systemCrest = CreateSystemAssetTexture(display.systemArt, SYSTEM_CREST, "ARTWORK", 5, "ADD")

    display.systemStatusNodes = {}
    for index = 1, 3 do
        display.systemStatusNodes[index] = CreateStartMotionTexture(display.systemArt, "ARTWORK", 6, index == 2 and "ADD" or nil)
    end

    display.systemTitleGlow = display.systemArt:CreateFontString(nil, "ARTWORK")
    display.systemTitleGlow:SetJustifyH("CENTER")
    display.systemTitleGlow:SetJustifyV("MIDDLE")
    display.systemTitleGlow:SetWordWrap(false)
    display.systemTitle = display.systemArt:CreateFontString(nil, "OVERLAY")
    display.systemTitle:SetJustifyH("CENTER")
    display.systemTitle:SetJustifyV("MIDDLE")
    display.systemTitle:SetWordWrap(false)
    display.systemTitle:SetShadowOffset(1, -1)
    display.systemTitle:SetShadowColor(0, 0, 0, 0.90)

    startMotionFrame = display
    self.startMotionFrame = display
    return display
end

function BloodlustTimer:RenderSystemStartMotion(progress)
    if not startMotionFrame or not self.db or not AlertStyle then return end

    local display = startMotionFrame
    local db = self.db
    local width = Clamp(db.startMotionWidth, 360, 900, 620)
    local height = Clamp(db.startMotionHeight, 90, 220, 130)
    local titleColor = StartMotionColor(db.startMotionSystemTitleColor, SYSTEM_MOTION_COLORS.title)
    local ringColor = StartMotionColor(db.startMotionSystemRingColor, SYSTEM_MOTION_COLORS.ring)
    local accentColor = StartMotionColor(db.startMotionSystemAccentColor, SYSTEM_MOTION_COLORS.accent)
    local pulseColor = StartMotionColor(db.startMotionSystemPulseColor, SYSTEM_MOTION_COLORS.pulse)
    local panelColor = StartMotionColor(db.startMotionSystemPanelColor, SYSTEM_MOTION_COLORS.panel)
    local glowColor = StartMotionColor(db.startMotionSystemGlowColor, SYSTEM_MOTION_COLORS.glow)
    local crestColor = StartMotionColor(db.startMotionSystemCrestColor, SYSTEM_MOTION_COLORS.crest)
    local crestCoreColor = StartMotionColor(db.startMotionSystemCrestCoreColor, SYSTEM_MOTION_COLORS.crestCore)

    progress = AlertStyle.Clamp01(progress)
    local panelReveal = AlertStyle.EaseOutCubic(progress / 0.26)
    local ringReveal = AlertStyle.EaseOutCubic((progress - 0.08) / 0.34)
    local crestReveal = AlertStyle.SmoothStep((progress - 0.20) / 0.24)
    local titleReveal = AlertStyle.SmoothStep((progress - 0.30) / 0.22)
    local exitProgress = AlertStyle.SmoothStep((progress - 0.84) / 0.16)
    local visibility = 1 - exitProgress
    local pulse = math.sin(math.pi * AlertStyle.Clamp01((progress - 0.10) / 0.72))

    display.art:Hide()
    display.systemArt:Show()
    display.systemArt:SetAlpha(visibility)
    display.systemArt:SetScale(0.985 + 0.015 * ringReveal + 0.012 * pulse - 0.008 * exitProgress)

    local panelHalfWidth = width * 0.448 * panelReveal
    local panelHeight = height * 0.68
    AlertStyle.SetAnchoredRect(display.systemPanelLeft, panelHalfWidth, panelHeight, "RIGHT", display.systemArt, "CENTER", 0, 0)
    AlertStyle.SetAnchoredRect(display.systemPanelRight, panelHalfWidth, panelHeight, "LEFT", display.systemArt, "CENTER", 0, 0)
    AlertStyle.SetGradientColor(display.systemPanelLeft, panelColor, 0, panelColor, 1, panelReveal)
    AlertStyle.SetGradientColor(display.systemPanelRight, panelColor, 1, panelColor, 0, panelReveal)

    local glowHalfWidth = width * 0.30 * panelReveal
    AlertStyle.SetAnchoredRect(display.systemGlowLeft, glowHalfWidth, height * 0.82, "RIGHT", display.systemArt, "CENTER", 0, 0)
    AlertStyle.SetAnchoredRect(display.systemGlowRight, glowHalfWidth, height * 0.82, "LEFT", display.systemArt, "CENTER", 0, 0)
    AlertStyle.SetGradientColor(display.systemGlowLeft, glowColor, 0, glowColor, 0.88, ringReveal * (0.18 + pulse * 0.38))
    AlertStyle.SetGradientColor(display.systemGlowRight, glowColor, 0.88, glowColor, 0, ringReveal * (0.18 + pulse * 0.38))

    local ringSize = math.min(height * 0.94, width * 0.22)
    local frameGap = ringSize * 0.38
    local frameOuterX = width * 0.458
    local frameLineLength = math.max(1, (frameOuterX - frameGap) * panelReveal)
    local topY = height * 0.338
    local bottomY = -height * 0.338

    AlertStyle.SetAnchoredRect(display.systemTopLeft, frameLineLength, 1.25, "RIGHT", display.systemArt, "CENTER", -frameGap, topY)
    AlertStyle.SetAnchoredRect(display.systemTopRight, frameLineLength, 1.25, "LEFT", display.systemArt, "CENTER", frameGap, topY)
    AlertStyle.SetAnchoredRect(display.systemBottomLeft, frameLineLength * 1.03, 1, "RIGHT", display.systemArt, "CENTER", -frameGap, bottomY)
    AlertStyle.SetAnchoredRect(display.systemBottomRight, frameLineLength * 1.03, 1, "LEFT", display.systemArt, "CENTER", frameGap, bottomY)
    AlertStyle.SetSolidColor(display.systemTopLeft, ringColor, panelReveal * 0.82)
    AlertStyle.SetSolidColor(display.systemTopRight, ringColor, panelReveal * 0.82)
    AlertStyle.SetSolidColor(display.systemBottomLeft, ringColor, panelReveal * 0.48)
    AlertStyle.SetSolidColor(display.systemBottomRight, ringColor, panelReveal * 0.48)

    local sideX = width * 0.465
    local sideSize = math.max(2, height * 0.077 * panelReveal)
    local sideCoreSize = math.max(1, height * 0.038 * panelReveal)
    AlertStyle.SetCenteredRect(display.systemSideNodes[1], sideSize, sideSize, display.systemArt, -sideX, 0, math.rad(45))
    AlertStyle.SetCenteredRect(display.systemSideNodes[2], sideSize, sideSize, display.systemArt, sideX, 0, math.rad(45))
    AlertStyle.SetCenteredRect(display.systemSideCores[1], sideCoreSize, sideCoreSize, display.systemArt, -sideX, 0, math.rad(45))
    AlertStyle.SetCenteredRect(display.systemSideCores[2], sideCoreSize, sideCoreSize, display.systemArt, sideX, 0, math.rad(45))
    AlertStyle.SetSolidColor(display.systemSideNodes[1], ringColor, panelReveal * 0.78)
    AlertStyle.SetSolidColor(display.systemSideNodes[2], ringColor, panelReveal * 0.78)
    AlertStyle.SetSolidColor(display.systemSideCores[1], accentColor, panelReveal)
    AlertStyle.SetSolidColor(display.systemSideCores[2], accentColor, panelReveal)

    local scanLength = math.max(1, width * 0.239 * ringReveal)
    local scanGap = ringSize * 0.48
    AlertStyle.SetAnchoredRect(display.systemScanLeft, scanLength, 1.25, "RIGHT", display.systemArt, "CENTER", -scanGap, -height * 0.008)
    AlertStyle.SetAnchoredRect(display.systemScanRight, scanLength, 1.25, "LEFT", display.systemArt, "CENTER", scanGap, -height * 0.008)
    AlertStyle.SetSolidColor(display.systemScanLeft, pulseColor, ringReveal * 0.62)
    AlertStyle.SetSolidColor(display.systemScanRight, pulseColor, ringReveal * 0.62)

    local ringY = height * 0.03
    local outerRotation = math.rad(-22 * (1 - ringReveal) + exitProgress * 5)
    local accentRotation = math.rad(32 * (1 - ringReveal) - exitProgress * 8)
    local innerRotation = math.rad(-44 * (1 - ringReveal) + exitProgress * 10)
    AlertStyle.SetCenteredRect(display.systemOuterRingGlow, ringSize * 1.08, ringSize * 1.08, display.systemArt, 0, ringY, outerRotation)
    AlertStyle.SetCenteredRect(display.systemOuterRing, ringSize, ringSize, display.systemArt, 0, ringY, outerRotation)
    AlertStyle.SetCenteredRect(display.systemAccentRing, ringSize * 0.92, ringSize * 0.92, display.systemArt, 0, ringY, accentRotation)
    AlertStyle.SetCenteredRect(display.systemInnerRing, ringSize * 0.72, ringSize * 0.72, display.systemArt, 0, ringY, innerRotation)
    AlertStyle.SetCenteredRect(display.systemCrestGlow, ringSize * 0.58, ringSize * 0.58, display.systemArt, 0, ringY, 0)
    AlertStyle.SetCenteredRect(display.systemCrestCore, ringSize * 0.54, ringSize * 0.54, display.systemArt, 0, ringY, 0)
    AlertStyle.SetCenteredRect(display.systemCrest, ringSize * 0.54, ringSize * 0.54, display.systemArt, 0, ringY, 0)
    SetSystemAssetColor(display.systemOuterRingGlow, glowColor, SYSTEM_MOTION_COLORS.glow, ringReveal * (0.18 + pulse * 0.34))
    SetSystemAssetColor(display.systemOuterRing, ringColor, SYSTEM_MOTION_COLORS.ring, ringReveal)
    SetSystemAssetColor(display.systemAccentRing, accentColor, SYSTEM_MOTION_COLORS.accent, ringReveal * 0.82)
    SetSystemAssetColor(display.systemInnerRing, pulseColor, SYSTEM_MOTION_COLORS.pulse, ringReveal * 0.90)
    SetSystemAssetColor(display.systemCrestGlow, accentColor, SYSTEM_MOTION_COLORS.accent, crestReveal * (0.10 + pulse * 0.24))
    SetSystemAssetColor(display.systemCrestCore, crestCoreColor, SYSTEM_MOTION_COLORS.crestCore, crestReveal * (0.78 + pulse * 0.22))
    SetSystemAssetColor(display.systemCrest, crestColor, SYSTEM_MOTION_COLORS.crest, crestReveal)

    for index = 1, 3 do
        local nodeSize = height * (index == 2 and 0.054 or 0.038) * crestReveal
        local nodeX = (index - 2) * height * 0.092
        AlertStyle.SetCenteredRect(display.systemStatusNodes[index], math.max(1, nodeSize), math.max(1, nodeSize), display.systemArt, nodeX, bottomY, math.rad(45))
        AlertStyle.SetSolidColor(display.systemStatusNodes[index], index == 2 and accentColor or ringColor, crestReveal * (index == 2 and 0.92 or 0.72))
    end

    local titleRed, titleGreen, titleBlue, titleAlpha = GetColor(titleColor, SYSTEM_MOTION_COLORS.title)
    local accentRed, accentGreen, accentBlue = GetColor(accentColor, SYSTEM_MOTION_COLORS.accent)
    local titleScale = 0.92 + 0.08 * titleReveal + 0.01 * pulse
    display.systemTitle:ClearAllPoints()
    display.systemTitle:SetPoint("CENTER", display.systemArt, "CENTER", 0, -height * 0.015 + (1 - titleReveal) * 4)
    display.systemTitle:SetScale(titleScale)
    display.systemTitle:SetTextColor(titleRed, titleGreen, titleBlue, titleAlpha * titleReveal)
    display.systemTitleGlow:ClearAllPoints()
    display.systemTitleGlow:SetPoint("CENTER", display.systemTitle, "CENTER", 0, 0)
    display.systemTitleGlow:SetScale(titleScale)
    display.systemTitleGlow:SetTextColor(accentRed, accentGreen, accentBlue, titleReveal * (0.14 + pulse * 0.24))
end

function BloodlustTimer:RenderStartMotion(progress)
    if not startMotionFrame or not self.db or not AlertStyle then return end

    if NormalizeStartMotionStyle(self.db.startMotionStyle) == "SYSTEM" then
        self:RenderSystemStartMotion(progress)
        return
    end

    startMotionFrame.systemArt:Hide()
    startMotionFrame.art:Show()

    progress = AlertStyle.Clamp01(progress)
    local db = self.db
    local width = Clamp(db.startMotionWidth, 360, 900, 620)
    local height = Clamp(db.startMotionHeight, 90, 220, 130)
    local titleColor = StartMotionColor(db.startMotionTitleColor, START_MOTION_COLORS.title)
    local lineColor = StartMotionColor(db.startMotionLineColor, START_MOTION_COLORS.line)
    local accentColor = StartMotionColor(db.startMotionAccentColor, START_MOTION_COLORS.accent)
    local pulseColor = StartMotionColor(db.startMotionPulseColor, START_MOTION_COLORS.pulse)
    local panelColor = StartMotionColor(db.startMotionPanelColor, START_MOTION_COLORS.panel)
    local glowColor = StartMotionColor(db.startMotionGlowColor, START_MOTION_COLORS.glow)
    local hotLineColor = SetBrightenedStartMotionColor(startMotionFrame.hotLineColor, lineColor, START_MOTION_COLORS.line, 0.24)
    local hotAccentColor = SetBrightenedStartMotionColor(startMotionFrame.hotAccentColor, accentColor, START_MOTION_COLORS.accent, 0.18)

    local sealReveal = AlertStyle.EaseOutCubic(progress / 0.22)
    local panelReveal = AlertStyle.EaseOutCubic((progress - 0.02) / 0.28)
    local ornamentReveal = AlertStyle.EaseOutCubic((progress - 0.08) / 0.36)
    local titleReveal = AlertStyle.SmoothStep((progress - 0.15) / 0.22)
    local exitProgress = AlertStyle.SmoothStep((progress - 0.82) / 0.18)
    local visibility = 1 - exitProgress
    local sealPulse = math.sin(math.pi * AlertStyle.Clamp01((progress - 0.015) / 0.44))
    local emberBurst = math.sin(math.pi * AlertStyle.Clamp01((progress - 0.08) / 0.68))
    local emberDrift = AlertStyle.SmoothStep((progress - 0.08) / 0.70)
    local shapeAlpha = panelReveal * visibility
    local ornamentAlpha = ornamentReveal * visibility

    startMotionFrame.art:SetAlpha(visibility)
    startMotionFrame.art:SetScale(0.965 + 0.035 * sealReveal + 0.012 * sealPulse - 0.012 * exitProgress)

    local panelHalfWidth = width * 0.46 * panelReveal
    local panelHeight = height * (0.78 + 0.02 * sealPulse)
    local panelCoreHalfWidth = width * 0.27 * panelReveal
    AlertStyle.SetAnchoredRect(startMotionFrame.panelLeft, panelHalfWidth, panelHeight, "RIGHT", startMotionFrame.art, "CENTER", 0, 0)
    AlertStyle.SetAnchoredRect(startMotionFrame.panelRight, panelHalfWidth, panelHeight, "LEFT", startMotionFrame.art, "CENTER", 0, 0)
    AlertStyle.SetGradientColor(startMotionFrame.panelLeft, panelColor, 0, panelColor, 1, shapeAlpha)
    AlertStyle.SetGradientColor(startMotionFrame.panelRight, panelColor, 1, panelColor, 0, shapeAlpha)
    AlertStyle.SetAnchoredRect(startMotionFrame.panelCoreLeft, panelCoreHalfWidth, panelHeight, "RIGHT", startMotionFrame.art, "CENTER", 0, 0)
    AlertStyle.SetAnchoredRect(startMotionFrame.panelCoreRight, panelCoreHalfWidth, panelHeight, "LEFT", startMotionFrame.art, "CENTER", 0, 0)
    AlertStyle.SetGradientColor(startMotionFrame.panelCoreLeft, panelColor, 0, panelColor, 1, shapeAlpha * 0.96)
    AlertStyle.SetGradientColor(startMotionFrame.panelCoreRight, panelColor, 1, panelColor, 0, shapeAlpha * 0.96)

    local glowHalfWidth = width * (0.16 + 0.29 * panelReveal)
    local glowAlpha = visibility * (0.16 * panelReveal + 0.48 * sealPulse)
    AlertStyle.SetAnchoredRect(startMotionFrame.glowLeft, glowHalfWidth, height * 0.90, "RIGHT", startMotionFrame.art, "CENTER", 0, 0)
    AlertStyle.SetAnchoredRect(startMotionFrame.glowRight, glowHalfWidth, height * 0.90, "LEFT", startMotionFrame.art, "CENTER", 0, 0)
    AlertStyle.SetGradientColor(startMotionFrame.glowLeft, glowColor, 0, glowColor, 1, glowAlpha)
    AlertStyle.SetGradientColor(startMotionFrame.glowRight, glowColor, 1, glowColor, 0, glowAlpha)

    local topY = height * 0.29
    local bottomY = -height * 0.33
    local sealHalf = math.max(1, height * 0.19 * sealReveal)
    local sealGap = sealHalf + 7
    local outerRuleX = width * 0.43
    local endMedallionHalf = math.max(1, height * 0.055 * ornamentReveal)
    local ruleEnd = math.max(sealGap + 1, outerRuleX - endMedallionHalf - 3)
    local topRuleLength = math.max(1, (ruleEnd - sealGap) * ornamentReveal)

    AlertStyle.SetAnchoredRect(startMotionFrame.topRuleGlowLeft, topRuleLength, 5, "RIGHT", startMotionFrame.art, "CENTER", -sealGap, topY)
    AlertStyle.SetAnchoredRect(startMotionFrame.topRuleGlowRight, topRuleLength, 5, "LEFT", startMotionFrame.art, "CENTER", sealGap, topY)
    AlertStyle.SetAnchoredRect(startMotionFrame.topRuleLeft, topRuleLength, 1.5, "RIGHT", startMotionFrame.art, "CENTER", -sealGap, topY)
    AlertStyle.SetAnchoredRect(startMotionFrame.topRuleRight, topRuleLength, 1.5, "LEFT", startMotionFrame.art, "CENTER", sealGap, topY)
    AlertStyle.SetGradientColor(startMotionFrame.topRuleGlowLeft, lineColor, 0.05, lineColor, 0.80, ornamentAlpha * 0.18)
    AlertStyle.SetGradientColor(startMotionFrame.topRuleGlowRight, lineColor, 0.80, lineColor, 0.05, ornamentAlpha * 0.18)
    AlertStyle.SetGradientColor(startMotionFrame.topRuleLeft, hotLineColor, 0.20, hotLineColor, 1, ornamentAlpha * 0.92)
    AlertStyle.SetGradientColor(startMotionFrame.topRuleRight, hotLineColor, 1, hotLineColor, 0.20, ornamentAlpha * 0.92)

    local endX = sealGap + (outerRuleX - sealGap) * ornamentReveal
    PlaceStartMotionDiamond(startMotionFrame.endMedallionLeft, nil, startMotionFrame.art, -endX, topY, endMedallionHalf, 1.35, 1)
    PlaceStartMotionDiamond(startMotionFrame.endMedallionRight, nil, startMotionFrame.art, endX, topY, endMedallionHalf, 1.35, 1)
    for index = 1, 4 do
        AlertStyle.SetSolidColor(startMotionFrame.endMedallionLeft[index], hotLineColor, ornamentAlpha * 0.84)
        AlertStyle.SetSolidColor(startMotionFrame.endMedallionRight[index], hotLineColor, ornamentAlpha * 0.84)
    end
    local medallionCoreSize = math.max(1, endMedallionHalf * 0.62)
    AlertStyle.SetCenteredRect(startMotionFrame.endMedallionCores[1], medallionCoreSize, medallionCoreSize, startMotionFrame.art, -endX, topY, math.rad(45))
    AlertStyle.SetCenteredRect(startMotionFrame.endMedallionCores[2], medallionCoreSize, medallionCoreSize, startMotionFrame.art, endX, topY, math.rad(45))
    AlertStyle.SetSolidColor(startMotionFrame.endMedallionCores[1], lineColor, ornamentAlpha * 0.45)
    AlertStyle.SetSolidColor(startMotionFrame.endMedallionCores[2], lineColor, ornamentAlpha * 0.45)

    for index, segment in ipairs(START_MOTION_FILIGREE_SEGMENTS) do
        local x1 = sealGap + width * segment[1] * ornamentReveal
        local y1 = topY + height * segment[2] * ornamentReveal
        local x2 = sealGap + width * segment[3] * ornamentReveal
        local y2 = topY + height * segment[4] * ornamentReveal
        SetStartMotionSegment(startMotionFrame.filigreeLeft[index], startMotionFrame.art, -x1, y1, -x2, y2, 1.45)
        SetStartMotionSegment(startMotionFrame.filigreeRight[index], startMotionFrame.art, x1, y1, x2, y2, 1.45)
        AlertStyle.SetSolidColor(startMotionFrame.filigreeLeft[index], hotLineColor, ornamentAlpha * 0.78)
        AlertStyle.SetSolidColor(startMotionFrame.filigreeRight[index], hotLineColor, ornamentAlpha * 0.78)
    end

    AlertStyle.SetCenteredRect(startMotionFrame.sealBloom, sealHalf * 1.80, sealHalf * 1.80, startMotionFrame.art, 0, topY, math.rad(45))
    AlertStyle.SetCenteredRect(startMotionFrame.sealFill, sealHalf * 1.28, sealHalf * 1.28, startMotionFrame.art, 0, topY, math.rad(45))
    AlertStyle.SetSolidColor(startMotionFrame.sealBloom, glowColor, visibility * sealReveal * (0.14 + sealPulse * 0.38))
    AlertStyle.SetSolidColor(startMotionFrame.sealFill, panelColor, visibility * sealReveal)
    PlaceStartMotionDiamond(startMotionFrame.sealOuterEdges, startMotionFrame.sealOuterGlows, startMotionFrame.art, 0, topY, sealHalf, 2.2, 7)
    PlaceStartMotionDiamond(startMotionFrame.sealInnerEdges, nil, startMotionFrame.art, 0, topY, sealHalf * 0.66, 1.15, 1)
    for index = 1, 4 do
        AlertStyle.SetSolidColor(startMotionFrame.sealOuterGlows[index], lineColor, visibility * sealReveal * (0.12 + sealPulse * 0.24))
        AlertStyle.SetSolidColor(startMotionFrame.sealOuterEdges[index], hotLineColor, visibility * sealReveal)
        AlertStyle.SetSolidColor(startMotionFrame.sealInnerEdges[index], lineColor, visibility * sealReveal * 0.74)
    end

    SetStartMotionSegment(startMotionFrame.sealFinials[1], startMotionFrame.art, -sealHalf * 0.48, topY + sealHalf * 0.54, 0, topY + sealHalf * 1.24, 1.35)
    SetStartMotionSegment(startMotionFrame.sealFinials[2], startMotionFrame.art, sealHalf * 0.48, topY + sealHalf * 0.54, 0, topY + sealHalf * 1.24, 1.35)
    SetStartMotionSegment(startMotionFrame.sealFinials[3], startMotionFrame.art, -sealHalf * 0.38, topY - sealHalf * 0.62, 0, topY - sealHalf * 1.18, 1.2)
    SetStartMotionSegment(startMotionFrame.sealFinials[4], startMotionFrame.art, sealHalf * 0.38, topY - sealHalf * 0.62, 0, topY - sealHalf * 1.18, 1.2)
    for _, texture in ipairs(startMotionFrame.sealFinials) do
        AlertStyle.SetSolidColor(texture, hotLineColor, visibility * sealReveal * 0.82)
    end

    local gemHalf = math.max(1, sealHalf * 0.34)
    local gemSize = math.sqrt(2) * gemHalf
    AlertStyle.SetCenteredRect(startMotionFrame.gemGlow, gemSize * 1.72, gemSize * 1.72, startMotionFrame.art, 0, topY, math.rad(45))
    AlertStyle.SetCenteredRect(startMotionFrame.gemFill, gemSize, gemSize, startMotionFrame.art, 0, topY, math.rad(45))
    AlertStyle.SetCenteredRect(startMotionFrame.gemCore, gemSize * 0.42, gemSize * 0.42, startMotionFrame.art, 0, topY, math.rad(45))
    AlertStyle.SetSolidColor(startMotionFrame.gemGlow, glowColor, visibility * sealReveal * (0.28 + sealPulse * 0.58))
    AlertStyle.SetSolidColor(startMotionFrame.gemFill, accentColor, visibility * sealReveal)
    AlertStyle.SetSolidColor(startMotionFrame.gemCore, hotAccentColor, visibility * sealReveal * (0.72 + sealPulse * 0.28))

    local bottomGap = width * 0.060
    local bottomOuterX = width * 0.42
    local bottomRuleLength = math.max(1, (bottomOuterX - bottomGap) * ornamentReveal)
    AlertStyle.SetAnchoredRect(startMotionFrame.bottomRuleGlowLeft, bottomRuleLength, 4, "RIGHT", startMotionFrame.art, "CENTER", -bottomGap, bottomY)
    AlertStyle.SetAnchoredRect(startMotionFrame.bottomRuleGlowRight, bottomRuleLength, 4, "LEFT", startMotionFrame.art, "CENTER", bottomGap, bottomY)
    AlertStyle.SetAnchoredRect(startMotionFrame.bottomRuleLeft, bottomRuleLength, 1.25, "RIGHT", startMotionFrame.art, "CENTER", -bottomGap, bottomY)
    AlertStyle.SetAnchoredRect(startMotionFrame.bottomRuleRight, bottomRuleLength, 1.25, "LEFT", startMotionFrame.art, "CENTER", bottomGap, bottomY)
    AlertStyle.SetGradientColor(startMotionFrame.bottomRuleGlowLeft, lineColor, 0.03, lineColor, 0.72, ornamentAlpha * 0.12)
    AlertStyle.SetGradientColor(startMotionFrame.bottomRuleGlowRight, lineColor, 0.72, lineColor, 0.03, ornamentAlpha * 0.12)
    AlertStyle.SetGradientColor(startMotionFrame.bottomRuleLeft, hotLineColor, 0.08, hotLineColor, 0.80, ornamentAlpha * 0.78)
    AlertStyle.SetGradientColor(startMotionFrame.bottomRuleRight, hotLineColor, 0.80, hotLineColor, 0.08, ornamentAlpha * 0.78)

    for index = 1, 3 do
        local x = (index - 2) * height * 0.145
        local size = height * (index == 2 and 0.068 or 0.045) * ornamentReveal
        local jewelColor = index == 2 and accentColor or lineColor
        local jewelCoreColor = index == 2 and hotAccentColor or hotLineColor
        AlertStyle.SetCenteredRect(startMotionFrame.bottomJewelGlows[index], math.max(1, size * 1.85), math.max(1, size * 1.85), startMotionFrame.art, x, bottomY, math.rad(45))
        AlertStyle.SetCenteredRect(startMotionFrame.bottomJewels[index], math.max(1, size), math.max(1, size), startMotionFrame.art, x, bottomY, math.rad(45))
        AlertStyle.SetSolidColor(startMotionFrame.bottomJewelGlows[index], jewelColor, ornamentAlpha * (0.12 + sealPulse * 0.18))
        AlertStyle.SetSolidColor(startMotionFrame.bottomJewels[index], jewelCoreColor, ornamentAlpha * 0.88)
    end

    for index, ember in ipairs(START_MOTION_EMBER_LAYOUT) do
        local side, xFactor, yFactor, driftX, driftY, baseSize = ember[1], ember[2], ember[3], ember[4], ember[5], ember[6]
        local x = side * width * (xFactor + driftX * emberDrift)
        local y = height * (yFactor + driftY * emberDrift)
        local emberSize = math.max(1, baseSize * (0.86 + 0.24 * sealPulse))
        local emberColor = index % 2 == 0 and pulseColor or hotAccentColor
        AlertStyle.SetCenteredRect(startMotionFrame.embers[index], emberSize, emberSize, startMotionFrame.art, x, y, math.rad(45))
        AlertStyle.SetSolidColor(startMotionFrame.embers[index], emberColor, emberBurst * visibility * (index % 2 == 0 and 0.46 or 0.62))
    end

    local tr, tg, tb, ta = GetColor(titleColor, START_MOTION_COLORS.title)
    local ar, ag, ab = GetColor(accentColor, START_MOTION_COLORS.accent)
    local titleScale = 0.88 + 0.12 * titleReveal + 0.028 * sealPulse
    startMotionFrame.title:ClearAllPoints()
    startMotionFrame.title:SetPoint("CENTER", startMotionFrame.art, "CENTER", 0, -4 + (1 - titleReveal) * 8 - exitProgress * 4)
    startMotionFrame.title:SetScale(titleScale)
    startMotionFrame.title:SetTextColor(tr, tg, tb, ta * titleReveal * visibility)
    startMotionFrame.titleGlow:ClearAllPoints()
    startMotionFrame.titleGlow:SetPoint("CENTER", startMotionFrame.title, "CENTER", 0, 0)
    startMotionFrame.titleGlow:SetScale(titleScale)
    startMotionFrame.titleGlow:SetTextColor(ar, ag, ab, titleReveal * visibility * (0.08 + 0.18 * sealPulse))
end

function BloodlustTimer:ApplyStartMotionPosition()
    self.db = self.db or EnsureDB()
    if not self.db then return end
    local display = self:CreateStartMotionFrame()
    if not display then return end
    local position = type(self.db.startMotionPosition) == "table" and self.db.startMotionPosition or DEFAULT_START_MOTION_POSITION
    display:ClearAllPoints()
    display:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or position.point or "CENTER",
        SafeNumber(position.x) or 0,
        SafeNumber(position.y) or 40
    )
end

function BloodlustTimer:ApplyStartMotionSettings()
    self.db = self.db or EnsureDB()
    if not self.db then return end
    local db = self.db
    local display = self:CreateStartMotionFrame()
    if not display then return end

    local width = Clamp(db.startMotionWidth, 360, 900, 620)
    local height = Clamp(db.startMotionHeight, 90, 220, 130)
    local fontSize = Clamp(db.startMotionFontSize, 18, 72, 38)
    local outline = db.startMotionFontOutline or "OUTLINE"
    if outline == "NONE" then outline = "" end
    local text = tostring(db.startMotionText or "BLOODLUST")
    text = text:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then text = "BLOODLUST" end

    display:SetSize(width, height)
    display:SetScale(Clamp(db.startMotionScale, 0.5, 2, 1))
    display:SetFrameStrata(NormalizeFrameStrata(db.startMotionFrameStrata))
    display.title:SetWidth(math.max(1, width - 120))
    display.title:SetHeight(math.max(1, height * 0.42))
    display.titleGlow:SetWidth(math.max(1, width - 120))
    display.titleGlow:SetHeight(math.max(1, height * 0.42))
    display.systemTitle:SetWidth(math.max(1, width - 190))
    display.systemTitle:SetHeight(math.max(1, height * 0.36))
    display.systemTitleGlow:SetWidth(math.max(1, width - 190))
    display.systemTitleGlow:SetHeight(math.max(1, height * 0.36))
    ApplyStartMotionFont(display.title, db.startMotionFont or DEFAULT_FONT, fontSize, outline)
    ApplyStartMotionFont(display.titleGlow, db.startMotionFont or DEFAULT_FONT, math.min(74, fontSize + 2), "")
    ApplyStartMotionFont(display.systemTitle, db.startMotionFont or DEFAULT_FONT, math.min(fontSize, height * 0.32), outline)
    ApplyStartMotionFont(display.systemTitleGlow, db.startMotionFont or DEFAULT_FONT, math.min(74, fontSize + 2, height * 0.34), "")
    display.title:SetText(text)
    display.titleGlow:SetText(text)
    display.systemTitle:SetText(text)
    display.systemTitleGlow:SetText(text)
    self:ApplyStartMotionPosition()

    if startMotionState then
        self:UpdateStartMotion(0)
    end
end

function BloodlustTimer:StopStartMotion()
    startMotionState = nil
    if startMotionFrame then
        startMotionFrame:Hide()
        startMotionFrame.art:SetAlpha(1)
        startMotionFrame.art:SetScale(1)
        startMotionFrame.systemArt:SetAlpha(1)
        startMotionFrame.systemArt:SetScale(1)
    end
end

function BloodlustTimer:PlayStartMotion(force, looping)
    self.db = self.db or EnsureDB()
    if not self.db then return end
    if self.db.startMotionEnabled ~= true and not force then return end
    if not force and not self:ShouldShowInEnvironment() then return end

    self:StopStartMotion()
    self:ApplyStartMotionSettings()
    local display = self:CreateStartMotionFrame()
    if not display then return end

    startMotionState = {
        elapsed = 0,
        duration = Clamp(self.db.startMotionDuration, 0.7, 2.5, 1.2),
        looping = looping == true,
        forcedPreview = force == true,
    }
    display:Show()
    self:RenderStartMotion(0)
end

function BloodlustTimer:UpdateStartMotion(elapsed)
    if not startMotionState or not startMotionFrame then return end
    elapsed = SafeNumber(elapsed) or 0
    startMotionState.elapsed = startMotionState.elapsed + math.max(0, elapsed)

    local duration = startMotionState.duration
    if startMotionState.looping then
        local cycleDuration = duration + 0.65
        local cycleElapsed = startMotionState.elapsed % cycleDuration
        if cycleElapsed >= duration then
            self:RenderStartMotion(1)
        else
            self:RenderStartMotion(cycleElapsed / duration)
        end
        return
    end

    local progress = math.min(1, startMotionState.elapsed / duration)
    self:RenderStartMotion(progress)
    if progress >= 1 then
        self:StopStartMotion()
    end
end

function BloodlustTimer:PreviewStartMotion()
    self:PlayStartMotion(true, false)
end

function BloodlustTimer:ResetStartMotionPosition()
    self.db = self.db or EnsureDB()
    if not self.db then return end
    self.db.startMotionPosition = CopyDefaultStartMotionPosition()
    self:ApplyStartMotionPosition()
end

function BloodlustTimer:ApplySettings()
    self.db = EnsureDB()
    if not self.db then return end
    local db = self.db
    local display = self:CreateFrame()
    local showIcon = db.showIcon ~= false
    local showBar = db.showBar ~= false
    local iconSize = Clamp(db.iconSize, 20, 100, 40)
    local barWidth = Clamp(db.barWidth, 80, 600, 220)
    local barHeight = Clamp(db.barHeight, 6, 80, 20)
    local spacing = Clamp(db.iconSpacing, 0, 30, 4)
    local fontSize = Clamp(db.fontSize, 8, 40, 14)
    local textPosition = NormalizeTextPosition(db.textPosition)
    local textExtra = db.showText ~= false and textPosition ~= "INSIDE" and (fontSize + 6) or 0
    local coreWidth = (showIcon and iconSize or 0) + (showIcon and showBar and spacing or 0) + (showBar and barWidth or 0)
    local coreHeight = math.max(showIcon and iconSize or 1, showBar and barHeight or 1)

    display:SetSize(math.max(1, coreWidth), math.max(1, coreHeight + textExtra))
    display:SetScale(Clamp(db.scale, 0.5, 2.5, 1))
    display:SetFrameStrata(NormalizeFrameStrata(db.frameStrata))

    local coreOffsetY = textPosition == "ABOVE" and -textExtra or 0
    display.iconFrame:ClearAllPoints()
    display.iconFrame:SetPoint("TOPLEFT", display, "TOPLEFT", 0, coreOffsetY)
    display.iconFrame:SetSize(iconSize, iconSize)
    display.iconFrame:SetShown(showIcon)

    display.bar:ClearAllPoints()
    if showIcon then
        display.bar:SetPoint("LEFT", display.iconFrame, "RIGHT", spacing, 0)
    else
        display.bar:SetPoint("TOPLEFT", display, "TOPLEFT", 0, coreOffsetY - ((coreHeight - barHeight) / 2))
    end
    display.bar:SetSize(barWidth, barHeight)
    display.bar:SetShown(showBar)
    display.bar:SetStatusBarTexture(db.barTexture or DEFAULT_BAR)
    if display.bar.SetReverseFill then
        display.bar:SetReverseFill(db.barDirection == "RIGHT")
    end

    local bgR, bgG, bgB, bgA = GetColor(db.barBackgroundColor, { 0.02, 0.025, 0.035, 0.9 })
    display.barBackground:SetColorTexture(bgR, bgG, bgB, bgA)
    local borderR, borderG, borderB, borderA = GetColor(db.barBorderColor, { 0, 0, 0, 1 })
    SetBorderColor(display.bar, borderR, borderG, borderB, borderA)
    SetBorderColor(display.iconFrame, borderR, borderG, borderB, borderA)
    local borderSize = Clamp(db.barBorderSize, 0, 8, 1)
    SetBorderSize(display.bar, borderSize)
    SetBorderSize(display.iconFrame, borderSize)

    display.text:ClearAllPoints()
    local textAnchor = showBar and display.bar or (showIcon and display.iconFrame or display)
    local offsetX = Clamp(db.textOffsetX, -400, 400, 0)
    local offsetY = Clamp(db.textOffsetY, -200, 200, 0)
    if textPosition == "ABOVE" then
        display.text:SetPoint("BOTTOM", textAnchor, "TOP", offsetX, 4 + offsetY)
    elseif textPosition == "BELOW" then
        display.text:SetPoint("TOP", textAnchor, "BOTTOM", offsetX, -4 + offsetY)
    else
        display.text:SetPoint("CENTER", textAnchor, "CENTER", offsetX, offsetY)
    end
    display.text:SetFont(db.font or DEFAULT_FONT, fontSize, db.fontOutline or "OUTLINE")
    display.text:SetShown(db.showText ~= false)

    display.cooldown:SetDrawSwipe(db.showCooldownSwipe ~= false)
    display.cooldown:SetHideCountdownNumbers(db.showCooldownNumbers == false)

    display.animation:ClearAllPoints()
    display.animation:SetPoint("CENTER", display, "CENTER", Clamp(db.animationOffsetX, -800, 800, 0), Clamp(db.animationOffsetY, -600, 600, 0))
    display.animation:SetSize(Clamp(db.animationWidth, 16, 1000, 220), Clamp(db.animationHeight, 16, 1000, 220))
    display.animation:SetAlpha(Clamp(db.animationAlpha, 0, 1, 1))
    display.animation:SetBlendMode(db.animationBlendMode == "BLEND" and "BLEND" or "ADD")
    local drawLayer = db.animationLayer
    if drawLayer ~= "BACKGROUND" and drawLayer ~= "BORDER" and drawLayer ~= "ARTWORK" and drawLayer ~= "OVERLAY" then
        drawLayer = "BACKGROUND"
    end
    display.animation:SetDrawLayer(drawLayer, drawLayer == "BACKGROUND" and 0 or -1)
    local animationPath = ResolveAnimationPath(db)
    display.animation:SetTexture(animationPath)
    if db.animationEnabled ~= true and not animationPreview then
        self:StopAnimation()
    end

    self:ApplyStartMotionSettings()
    self:ApplyPosition()
    if db.musicSoundEnabled ~= true then self:StopMusic(100) end
    if state.phase == "ACTIVE" and not self:IsPreviewing() and db.musicSoundEnabled == true and musicHandle == nil then
        self:StartMusic()
    end
    self:UpdateDisplay(true)
end

function BloodlustTimer:IsPreviewing()
    return editPreview or testMode or animationPreview
        or (startMotionState and startMotionState.forcedPreview == true)
end

function BloodlustTimer:ShouldShowInEnvironment()
    if self:IsPreviewing() then return true end
    local db = self.db
    if not db then return false end
    if db.groupOnly == true and not SafeBooleanCall(IsInGroup) then return false end
    if db.instanceOnly == true then
        local inInstance = SafeBooleanCall(IsInInstance)
        if not inInstance then return false end
    end
    return true
end

function BloodlustTimer:GetSnapshot(now)
    if editPreview then
        return {
            phase = "ACTIVE",
            remaining = 23,
            duration = ACTIVE_DURATION,
            startTime = now - (ACTIVE_DURATION - 23),
            buffSpellID = state.buffSpellID or 2825,
            serial = -1,
        }
    end

    if animationPreview then
        local remaining = math.max(0, animationPreviewEndsAt - now)
        return {
            phase = "ACTIVE",
            remaining = remaining,
            duration = 5,
            startTime = animationPreviewEndsAt - 5,
            buffSpellID = state.buffSpellID or 2825,
            serial = animationPreviewSerial,
        }
    end

    if testMode then
        local elapsed = now - testStartedAt
        if testPhase == "ACTIVE" then
            return {
                phase = "ACTIVE",
                remaining = math.max(0, 8 - elapsed),
                duration = 8,
                startTime = testStartedAt,
                buffSpellID = 2825,
                serial = testSerial,
            }
        end
        return {
            phase = "EXHAUSTION",
            remaining = math.max(0, 20 - elapsed),
            duration = 12,
            startTime = testStartedAt + 8,
            buffSpellID = 2825,
            serial = testSerial,
        }
    end

    if not state.hasDebuff or state.phase == "READY" then return nil end
    local remaining
    local duration
    local startTime
    if state.phase == "ACTIVE" then
        duration = ACTIVE_DURATION
        startTime = state.appliedAt
        if state.activeEndsAt then remaining = math.max(0, state.activeEndsAt - now) end
    else
        duration = state.debuffEndsAt and EXHAUSTION_DURATION or nil
        startTime = state.appliedAt
        if state.debuffEndsAt then remaining = math.max(0, state.debuffEndsAt - now) end
    end
    return {
        phase = state.phase,
        remaining = remaining,
        duration = duration,
        startTime = startTime,
        durationObject = state.durationObject,
        buffSpellID = state.buffSpellID or 2825,
        serial = state.serial,
    }
end

local function FormatClock(seconds, decimals, decimalsThreshold)
    if seconds == nil then return "--:--" end
    seconds = math.max(0, seconds)
    if seconds >= 60 then
        local rounded = math.ceil(seconds)
        return string.format("%d:%02d", math.floor(rounded / 60), rounded % 60)
    end
    if decimals > 0 and seconds <= decimalsThreshold then
        return string.format("%." .. decimals .. "f", seconds)
    end
    return tostring(math.ceil(seconds))
end

function BloodlustTimer:FormatText(snapshot)
    local db = self.db or {}
    local decimals = math.floor(Clamp(db.textDecimals, 0, 2, 1))
    local threshold = Clamp(db.decimalsThreshold, 0, 30, 3)
    local format = db.textFormat or "REMAINING"
    local timeText
    if format == "SECONDS" then
        timeText = snapshot.remaining and tostring(math.ceil(snapshot.remaining)) or "--"
    else
        timeText = FormatClock(snapshot.remaining, decimals, threshold)
        if format == "REMAINING_TOTAL" then
            timeText = timeText .. " / " .. FormatClock(snapshot.duration, 0, 0)
        end
    end

    local label = snapshot.phase == "ACTIVE" and tostring(db.activeText or "BL") or tostring(db.exhaustionText or "")
    label = label:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" or db.textOrder == "TIME_ONLY" then return timeText end
    if db.textOrder == "TIME_LABEL" then return timeText .. " " .. label end
    return label .. " " .. timeText
end

function BloodlustTimer:ApplyCooldown(snapshot)
    if not frame then return end
    if frame._cooldownSerial == snapshot.serial and frame._cooldownPhase == snapshot.phase then return end
    frame._cooldownSerial = snapshot.serial
    frame._cooldownPhase = snapshot.phase
    if frame.cooldown.Clear then frame.cooldown:Clear() end

    if snapshot.phase == "EXHAUSTION" and snapshot.durationObject and frame.cooldown.SetCooldownFromDurationObject then
        local ok = pcall(frame.cooldown.SetCooldownFromDurationObject, frame.cooldown, snapshot.durationObject)
        if ok then return end
    end
    if snapshot.startTime and snapshot.duration then
        frame.cooldown:SetCooldown(snapshot.startTime, snapshot.duration)
    end
end

function BloodlustTimer:UpdateDisplay(force)
    if not self.db then return end
    local display = self:CreateFrame()
    local now = GetTime()
    local snapshot = self:GetSnapshot(now)
    if not snapshot or not self:ShouldShowInEnvironment() then
        self:StopGlows()
        display:Hide()
        return
    end

    local phaseEnabled = snapshot.phase == "ACTIVE" and self.db.showActive ~= false
        or snapshot.phase == "EXHAUSTION" and self.db.showExhaustion ~= false
    local animationVisible = snapshot.phase == "ACTIVE" and animationPlaying
    if not phaseEnabled and not animationVisible then
        self:StopGlows()
        display:Hide()
        return
    end

    display:Show()
    display.iconFrame:SetShown(phaseEnabled and self.db.showIcon ~= false)
    display.bar:SetShown(phaseEnabled and self.db.showBar ~= false)
    display.text:SetShown(phaseEnabled and self.db.showText ~= false)

    display.icon:SetTexture(ResolveSpellTexture(snapshot.buffSpellID))
    display.icon:SetDesaturated(snapshot.phase == "EXHAUSTION")
    if force then
        display._cooldownSerial = nil
        display._cooldownPhase = nil
    end
    self:ApplyCooldown(snapshot)

    local activeColor = { 1.00, 0.24, 0.12, 1 }
    local exhaustionColor = { 0.38, 0.44, 0.54, 1 }
    local barColor = snapshot.phase == "ACTIVE" and self.db.activeBarColor or self.db.exhaustionBarColor
    local fallbackColor = snapshot.phase == "ACTIVE" and activeColor or exhaustionColor
    if SL and SL.ApplyBarColor then
        SL.ApplyBarColor(display.bar, barColor, fallbackColor)
    else
        display.bar:SetStatusBarColor(GetColor(barColor, fallbackColor))
    end
    display.bar:SetMinMaxValues(0, snapshot.duration or 1)
    local value = snapshot.remaining
    if value == nil then value = snapshot.duration or 1 end
    if self.db.smoothBar == false then value = math.ceil(value) end
    display.bar:SetValue(value)

    local textColor = snapshot.phase == "ACTIVE" and self.db.activeTextColor or self.db.exhaustionTextColor
    local tr, tg, tb, ta = GetColor(textColor, { 1, 1, 1, 1 })
    display.text:SetTextColor(tr, tg, tb, ta)
    display.text:SetText(self:FormatText(snapshot))
    self:UpdateGlows(snapshot, phaseEnabled)
end

function BloodlustTimer:StartFromAura(aura, debuffSpellID, buffSpellID, silent)
    local now = GetTime()
    local appliedAt, expirationTime, duration = GetAuraTimes(aura)
    state.hasDebuff = true
    state.debuffSpellID = debuffSpellID
    state.buffSpellID = buffSpellID or 2825
    state.durationObject = BuildDurationObject(aura)
    state.waitingForRemoval = false
    state.serial = state.serial + 1

    if silent then
        state.appliedAt = appliedAt
        state.debuffEndsAt = expirationTime
        if appliedAt and now - appliedAt >= 0 and now - appliedAt < ACTIVE_DURATION then
            state.phase = "ACTIVE"
            state.activeEndsAt = appliedAt + ACTIVE_DURATION
        else
            state.phase = "EXHAUSTION"
            state.activeEndsAt = nil
        end
    else
        state.phase = "ACTIVE"
        state.appliedAt = now
        state.activeEndsAt = now + ACTIVE_DURATION
        state.debuffEndsAt = expirationTime or (now + (duration or EXHAUSTION_DURATION))
        if self.db.startSoundEnabled == true then
            PlayConfiguredSound(self.db, "start", {
                source = "BloodlustTimer",
                key = "start",
                priority = 85,
            })
        end
        self:StartMusic()
        self:StartAnimation(false)
        self:PlayStartMotion(false, false)
    end
    if silent and state.phase == "ACTIVE" then
        self:StartMusic()
        self:StartAnimation(false)
    end
    self:UpdateDisplay(true)
end

function BloodlustTimer:FinishActive(playSound)
    if state.phase ~= "ACTIVE" then return end
    state.phase = "EXHAUSTION"
    state.activeEndsAt = nil
    state.serial = state.serial + 1
    self:StopMusic(200)
    self:StopAnimation()
    if playSound and self.db.endSoundEnabled == true then
        PlayConfiguredSound(self.db, "end", {
            source = "BloodlustTimer",
            key = "end",
            priority = 75,
        })
    end
    self:UpdateDisplay(true)
end

function BloodlustTimer:FinishExhaustion(playSound)
    local hadDebuff = state.hasDebuff
    state.hasDebuff = false
    state.phase = "READY"
    state.debuffSpellID = nil
    state.appliedAt = nil
    state.activeEndsAt = nil
    state.debuffEndsAt = nil
    state.durationObject = nil
    state.waitingForRemoval = false
    state.serial = state.serial + 1
    self:StopMusic(100)
    self:StopAnimation()
    if hadDebuff and playSound and self.db.readySoundEnabled == true then
        PlayConfiguredSound(self.db, "ready", {
            source = "BloodlustTimer",
            key = "ready",
            priority = 65,
            canQueue = true,
        })
    end
    self:UpdateDisplay(true)
end

function BloodlustTimer:ScanAuras(silent)
    if not activeModule then return end
    local aura, debuffSpellID, buffSpellID = FindExhaustionAura()
    if aura then
        if not state.hasDebuff then
            self:StartFromAura(aura, debuffSpellID, buffSpellID, silent)
        else
            state.durationObject = BuildDurationObject(aura) or state.durationObject
            local appliedAt, expirationTime = GetAuraTimes(aura)
            if appliedAt then state.appliedAt = state.appliedAt or appliedAt end
            if expirationTime then state.debuffEndsAt = expirationTime end
        end
    elseif state.hasDebuff then
        self:FinishExhaustion(not silent)
    end
end

function BloodlustTimer:UpdateTest(now)
    if not testMode then return end
    local elapsed = now - testStartedAt
    if elapsed >= 8 and testPhase == "ACTIVE" then
        testPhase = "EXHAUSTION"
        testSerial = testSerial + 1
        self:StopMusic(200)
        self:StopAnimation()
        if self.db.endSoundEnabled == true then
            PlayConfiguredSound(self.db, "end", {
                source = "BloodlustTimer",
                key = "end",
                priority = 75,
            })
        end
    end
    if elapsed >= 20 then
        testMode = false
        self:StopMusic(100)
        self:StopAnimation()
        if self.db.readySoundEnabled == true then
            PlayConfiguredSound(self.db, "ready", {
                source = "BloodlustTimer",
                key = "ready",
                priority = 65,
                canQueue = true,
            })
        end
    end
end

function BloodlustTimer:OnUpdate(elapsed)
    if not activeModule and not self:IsPreviewing() then return end
    self:UpdateStartMotion(elapsed)
    self:UpdateAnimation(elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed < UPDATE_INTERVAL then return end
    updateElapsed = 0
    local now = GetTime()

    if animationPreview and now >= animationPreviewEndsAt then
        animationPreview = false
        self:StopAnimation()
    end
    self:UpdateTest(now)

    if not self:IsPreviewing() and state.phase == "ACTIVE" and state.activeEndsAt and now >= state.activeEndsAt then
        self:FinishActive(true)
    elseif not self:IsPreviewing() and state.phase == "EXHAUSTION" and not state.waitingForRemoval
        and state.debuffEndsAt and now >= state.debuffEndsAt then
        state.waitingForRemoval = true
        self:ScanAuras(false)
    end

    local snapshot = self:GetSnapshot(now)
    self:UpdateMusic(now, snapshot and snapshot.phase)
    self:UpdateDisplay(false)
end

function BloodlustTimer:OnInitialize()
    self.db = EnsureDB()
    self.initialized = true
end

function BloodlustTimer:OnEnable()
    self.db = EnsureDB()
    activeModule = true
    suppressFreshUntil = GetTime() + 1.5
    self:CreateFrame()
    self:ApplySettings()
    C_Timer.After(0.2, function()
        if activeModule then BloodlustTimer:ScanAuras(true) end
    end)
end

function BloodlustTimer:OnDisable()
    if ns.CancelManagedSoundsBySource then ns:CancelManagedSoundsBySource("BloodlustTimer", 0.1) end
    activeModule = false
    editPreview = false
    testMode = false
    animationPreview = false
    self:StopMusic(100)
    self:StopAnimation()
    self:StopStartMotion()
    self:StopGlows()
    self:FinishExhaustion(false)
    if frame then frame:Hide() end
end

function BloodlustTimer:OnMediaChanged()
    self:ApplySettings()
end

function BloodlustTimer:ResetPosition()
    self.db = self.db or EnsureDB()
    if not self.db then return end
    self.db.position = CopyDefaultPosition()
    self:ApplyPosition()
end

function BloodlustTimer:TestMode()
    self.db = self.db or EnsureDB()
    self:CreateFrame()
    if state.phase == "ACTIVE" and not testMode then return end
    if testMode then
        testMode = false
        self:StopMusic(100)
        self:StopAnimation()
        self:StopStartMotion()
        self:UpdateDisplay(true)
        return
    end
    testMode = true
    testStartedAt = GetTime()
    testPhase = "ACTIVE"
    testSerial = testSerial + 1
    if self.db.startSoundEnabled == true then
        PlayConfiguredSound(self.db, "start", {
            source = "BloodlustTimer",
            key = "start",
            priority = 85,
        })
    end
    self:StartMusic()
    self:StartAnimation(false)
    self:PlayStartMotion(false, false)
    self:ApplySettings()
end

function BloodlustTimer:PreviewAnimation()
    self.db = self.db or EnsureDB()
    self:CreateFrame()
    animationPreview = true
    animationPreviewEndsAt = GetTime() + 5
    animationPreviewSerial = animationPreviewSerial + 1
    self:StartAnimation(true)
    self:ApplySettings()
end

function BloodlustTimer:EnterEditPreview()
    editPreview = true
    self.db = self.db or EnsureDB()
    self:CreateFrame()
    self:ApplySettings()
    self:StartAnimation(false)
    self:PlayStartMotion(true, true)
end

function BloodlustTimer:RefreshEditPreview()
    if not editPreview then return end
    self:ApplySettings()
    if self.db.animationEnabled == true and not animationPlaying then
        self:StartAnimation(false)
    end
    if not startMotionState then
        self:PlayStartMotion(true, true)
    end
end

function BloodlustTimer:ExitEditPreview()
    editPreview = false
    self:StopStartMotion()
    if state.phase ~= "ACTIVE" then self:StopAnimation() end
    self:UpdateDisplay(true)
end

eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:SetScript("OnEvent", function(_, event, unit, updateInfo)
    if not activeModule then return end
    if event == "UNIT_AURA" then
        local isFullUpdate = false
        if not IsSecret(updateInfo) and type(updateInfo) == "table" then
            local value = updateInfo.isFullUpdate
            if not IsSecret(value) and value == true then isFullUpdate = true end
        end
        BloodlustTimer:ScanAuras(isFullUpdate or GetTime() < suppressFreshUntil)
    elseif event == "PLAYER_DEAD" then
        BloodlustTimer:FinishActive(false)
    else
        if event == "PLAYER_ENTERING_WORLD" then
            suppressFreshUntil = GetTime() + 1.5
        end
        C_Timer.After(0.2, function()
            if activeModule then BloodlustTimer:ScanAuras(true) end
        end)
    end
end)
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    BloodlustTimer:OnUpdate(elapsed)
end)

DDingToolKit:RegisterModule("BloodlustTimer", BloodlustTimer)
