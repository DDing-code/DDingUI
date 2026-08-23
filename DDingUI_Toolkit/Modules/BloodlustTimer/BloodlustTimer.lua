-- DDingUI Toolkit - Bloodlust and exhaustion timer

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local SL = _G.DDingUI_StyleLib

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

local function PlayConfiguredSound(db, prefix)
    local path = GetSoundPath(db, prefix)
    if not path then return nil end
    local channel = db[prefix .. "SoundChannel"] or "Master"
    local ok, played, handle = pcall(PlaySoundFile, path, channel)
    if not ok or IsSecret(played) or not played or IsSecret(handle) then return nil end
    return handle
end

function BloodlustTimer:StopMusic(fadeMilliseconds)
    nextMusicAt = nil
    if not IsSecret(musicHandle) and musicHandle ~= nil and StopSound then
        pcall(StopSound, musicHandle, fadeMilliseconds or 150)
    end
    musicHandle = nil
end

function BloodlustTimer:PlayMusicTrack()
    local db = self.db
    if not db or db.musicSoundEnabled ~= true then return end
    self:StopMusic(0)
    musicHandle = PlayConfiguredSound(db, "music")
    if db.musicLoop == true and musicHandle then
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

    self:ApplyPosition()
    if db.musicSoundEnabled ~= true then self:StopMusic(100) end
    if state.phase == "ACTIVE" and not self:IsPreviewing() and db.musicSoundEnabled == true and musicHandle == nil then
        self:StartMusic()
    end
    self:UpdateDisplay(true)
end

function BloodlustTimer:IsPreviewing()
    return editPreview or testMode or animationPreview
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
        if self.db.startSoundEnabled == true then PlayConfiguredSound(self.db, "start") end
        self:StartMusic()
        self:StartAnimation(false)
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
        PlayConfiguredSound(self.db, "end")
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
        PlayConfiguredSound(self.db, "ready")
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
        if self.db.endSoundEnabled == true then PlayConfiguredSound(self.db, "end") end
    end
    if elapsed >= 20 then
        testMode = false
        self:StopMusic(100)
        self:StopAnimation()
        if self.db.readySoundEnabled == true then PlayConfiguredSound(self.db, "ready") end
    end
end

function BloodlustTimer:OnUpdate(elapsed)
    if not activeModule and not self:IsPreviewing() then return end
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
    activeModule = false
    editPreview = false
    testMode = false
    animationPreview = false
    self:StopMusic(100)
    self:StopAnimation()
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
        self:UpdateDisplay(true)
        return
    end
    testMode = true
    testStartedAt = GetTime()
    testPhase = "ACTIVE"
    testSerial = testSerial + 1
    if self.db.startSoundEnabled == true then PlayConfiguredSound(self.db, "start") end
    self:StartMusic()
    self:StartAnimation(false)
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
end

function BloodlustTimer:RefreshEditPreview()
    if not editPreview then return end
    self:ApplySettings()
    if self.db.animationEnabled == true and not animationPlaying then
        self:StartAnimation(false)
    end
end

function BloodlustTimer:ExitEditPreview()
    editPreview = false
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
