--[[
    DDingToolKit - Combat State Alert
    Animated combat start/end notification.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"

local CombatStateAlert = {}
CombatStateAlert.name = "CombatStateAlert"
ns.CombatStateAlert = CombatStateAlert

local DEFAULT_POSITION = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 140,
}

local FALLBACK_DEFAULTS = {
    showStart = true,
    showEnd = true,
    instanceOnly = false,
    visualMode = "SIMPLE",
    animationEnabled = true,
    duration = 1.8,
    designVersion = 3,
    width = 480,
    height = 96,
    scale = 1,
    frameStrata = "HIGH",
    font = SL_FONT,
    fontSize = 28,
    fontOutline = "OUTLINE",
    startText = "",
    endText = "",
    startColor = { 0.18, 0.82, 1.00, 1 },
    endColor = { 1.00, 0.72, 0.24, 1 },
    colorVersion = 2,
    startTextColor = { 0.70, 0.94, 1.00, 1.00 },
    startLineColor = { 0.12, 0.78, 0.92, 0.88 },
    startAccentColor = { 0.38, 0.55, 1.00, 0.72 },
    startDiamondColor = { 0.54, 0.36, 1.00, 0.90 },
    startWingColor = { 0.23, 0.72, 0.88, 0.70 },
    startPanelColor = { 0.03, 0.08, 0.12, 0.82 },
    startFlashColor = { 0.18, 0.82, 1.00, 0.14 },
    endTextColor = { 1.00, 0.85, 0.55, 1.00 },
    endLineColor = { 1.00, 0.63, 0.18, 0.88 },
    endAccentColor = { 1.00, 0.38, 0.18, 0.72 },
    endDiamondColor = { 1.00, 0.70, 0.28, 0.90 },
    endWingColor = { 1.00, 0.54, 0.18, 0.70 },
    endPanelColor = { 0.12, 0.055, 0.02, 0.82 },
    endFlashColor = { 1.00, 0.55, 0.16, 0.14 },
    startSoundEnabled = false,
    startSoundFile = "Sound\\Interface\\RaidWarning.ogg",
    startSoundCustomPath = "",
    startSoundChannel = "Master",
    endSoundEnabled = false,
    endSoundFile = "Sound\\Interface\\LevelUp2.ogg",
    endSoundCustomPath = "",
    endSoundChannel = "Master",
    position = DEFAULT_POSITION,
}

local START_SECONDARY = { 0.38, 0.55, 1.00, 1 }
local END_SECONDARY = { 1.00, 0.38, 0.18, 1 }

local alertFrame
local activeModule = false
local editPreview = false
local animationState
local sequenceToken = 0
local displayToken = 0

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function Clamp01(value)
    return Clamp(value, 0, 1)
end

local function SmoothStep(value)
    value = Clamp01(value)
    return value * value * (3 - 2 * value)
end

local function EaseOutCubic(value)
    value = Clamp01(value)
    local inverse = 1 - value
    return 1 - inverse * inverse * inverse
end

local function CopyPosition(position)
    position = position or DEFAULT_POSITION
    return {
        point = position.point or DEFAULT_POSITION.point,
        relativePoint = position.relativePoint or position.point or DEFAULT_POSITION.relativePoint,
        x = tonumber(position.x) or DEFAULT_POSITION.x,
        y = tonumber(position.y) or DEFAULT_POSITION.y,
    }
end

local function MergeFallbacks(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                MergeFallbacks(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeFallbacks(target[key], value)
        end
    end
end

local function EnsureDB()
    if not (ns.db and ns.db.profile) then return nil end

    if type(ns.db.profile.CombatStateAlert) ~= "table" then
        ns.db.profile.CombatStateAlert = {}
    end

    local db = ns.db.profile.CombatStateAlert
    local previousDesignVersion = tonumber(db.designVersion) or 0
    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.CombatStateAlert
    if defaults and ns.MergeDefaults then
        ns:MergeDefaults(db, defaults)
    else
        MergeFallbacks(db, FALLBACK_DEFAULTS)
    end

    if previousDesignVersion < 3 then
        local width = tonumber(db.width)
        local height = tonumber(db.height)
        if width == 420 or width == 520 then db.width = 480 end
        if height == 84 or height == 112 then db.height = 96 end
        db.designVersion = 3
    end

    if type(db.position) ~= "table" then
        db.position = CopyPosition()
    else
        db.position = CopyPosition(db.position)
    end

    return db
end

local function SetTextureColor(texture, color, alpha)
    local colorAlpha = tonumber(color and color[4]) or 1
    texture:SetAlpha(1)
    texture:SetVertexColor(
        tonumber(color and color[1]) or 1,
        tonumber(color and color[2]) or 1,
        tonumber(color and color[3]) or 1,
        colorAlpha * Clamp01(alpha or 1)
    )
end

local function SetTextureGradient(texture, fromColor, fromAlpha, toColor, toAlpha, alpha)
    local fromR = tonumber(fromColor and fromColor[1]) or 1
    local fromG = tonumber(fromColor and fromColor[2]) or 1
    local fromB = tonumber(fromColor and fromColor[3]) or 1
    local fromA = (tonumber(fromColor and fromColor[4]) or 1) * Clamp01(fromAlpha or 1)
    local toR = tonumber(toColor and toColor[1]) or 1
    local toG = tonumber(toColor and toColor[2]) or 1
    local toB = tonumber(toColor and toColor[3]) or 1
    local toA = (tonumber(toColor and toColor[4]) or 1) * Clamp01(toAlpha or 1)
    local cache = texture._ddingGradient

    if not cache then
        cache = {}
        texture._ddingGradient = cache
    end

    if cache[1] ~= fromR or cache[2] ~= fromG or cache[3] ~= fromB or cache[4] ~= fromA
        or cache[5] ~= toR or cache[6] ~= toG or cache[7] ~= toB or cache[8] ~= toA then
        cache[1], cache[2], cache[3], cache[4] = fromR, fromG, fromB, fromA
        cache[5], cache[6], cache[7], cache[8] = toR, toG, toB, toA
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetGradient(
            "HORIZONTAL",
            CreateColor(fromR, fromG, fromB, fromA),
            CreateColor(toR, toG, toB, toA)
        )
    end

    texture:SetAlpha(Clamp01(alpha or 1))
end

local function SetSolidTextureColor(texture, color, alpha)
    local r = tonumber(color and color[1]) or 1
    local g = tonumber(color and color[2]) or 1
    local b = tonumber(color and color[3]) or 1
    local a = tonumber(color and color[4]) or 1
    local cache = texture._ddingSolidColor

    if not cache then
        cache = {}
        texture._ddingSolidColor = cache
    end
    if cache[1] ~= r or cache[2] ~= g or cache[3] ~= b or cache[4] ~= a then
        cache[1], cache[2], cache[3], cache[4] = r, g, b, a
        texture:SetColorTexture(r, g, b, a)
    end
    texture:SetAlpha(Clamp01(alpha or 1))
end

local function SetLine(texture, width, height, x, y, rotation)
    texture:ClearAllPoints()
    texture:SetSize(math.max(1, width), math.max(1, height))
    texture:SetPoint("CENTER", alertFrame.art, "CENTER", x or 0, y or 0)
    if texture.SetRotation then
        texture:SetRotation(rotation or 0)
    end
end

local function CreateFlatTexture(parent, layer, subLevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, subLevel)
    texture:SetTexture(SL_FLAT)
    texture:SetColorTexture(1, 1, 1, 1)
    return texture
end

local EFFECT_TEXTURES = {
    "flash",
    "topLine",
    "bottomLine",
    "leftLine",
    "rightLine",
    "diamondTopLeft",
    "diamondTopRight",
    "diamondBottomLeft",
    "diamondBottomRight",
    "leftDiamond",
    "rightDiamond",
    "leftWingTop",
    "leftWingBottom",
    "rightWingTop",
    "rightWingBottom",
    "leftPlate",
    "rightPlate",
    "leftCapTop",
    "leftCapBottom",
    "rightCapTop",
    "rightCapBottom",
}

local function SetEffectsShown(frame, shown)
    if frame._effectsShown == shown then return end
    frame._effectsShown = shown
    local method = shown and "Show" or "Hide"
    for _, key in ipairs(EFFECT_TEXTURES) do
        local texture = frame[key]
        texture[method](texture)
    end
end

local function GetAlertText(db, kind)
    if kind == "END" then
        if type(db.endText) == "string" and db.endText ~= "" then
            return db.endText
        end
        return L["CSA_END_DEFAULT"] or "COMBAT ENDED"
    end

    if type(db.startText) == "string" and db.startText ~= "" then
        return db.startText
    end
    return L["CSA_START_DEFAULT"] or "COMBAT ENGAGED"
end

local function GetEventPalette(db, kind)
    if kind == "END" then
        local legacy = db.endColor or FALLBACK_DEFAULTS.endColor
        return db.endTextColor or legacy,
            db.endLineColor or legacy,
            db.endAccentColor or END_SECONDARY,
            db.endDiamondColor or END_SECONDARY,
            db.endWingColor or legacy,
            db.endPanelColor or END_SECONDARY,
            db.endFlashColor or legacy
    end

    local legacy = db.startColor or FALLBACK_DEFAULTS.startColor
    return db.startTextColor or legacy,
        db.startLineColor or legacy,
        db.startAccentColor or START_SECONDARY,
        db.startDiamondColor or START_SECONDARY,
        db.startWingColor or legacy,
        db.startPanelColor or START_SECONDARY,
        db.startFlashColor or legacy
end

local function PlayAlertSound(db, kind)
    local enabled
    local soundFile
    local customPath
    local channel

    if kind == "END" then
        enabled = db.endSoundEnabled
        soundFile = db.endSoundFile
        customPath = db.endSoundCustomPath
        channel = db.endSoundChannel
    else
        enabled = db.startSoundEnabled
        soundFile = db.startSoundFile
        customPath = db.startSoundCustomPath
        channel = db.startSoundChannel
    end

    if not enabled then return end
    if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
        ns:PlaySound(soundFile, channel or "Master", customPath)
    end
end

local function ApplyStaticLayout(kind, reveal, exitProgress, visibility)
    if not alertFrame then return end

    local db = CombatStateAlert.db or EnsureDB()
    if not db then return end

    reveal = Clamp01(reveal)
    exitProgress = Clamp01(exitProgress)
    visibility = Clamp01(visibility)

    local width = Clamp(db.width, 260, 800)
    local height = Clamp(db.height, 64, 200)
    local textColor, lineColor, accentColor, diamondColor, wingColor, panelColor, flashColor = GetEventPalette(db, kind)
    local fancy = db.visualMode == "FANCY"

    alertFrame.art:SetAlpha(visibility)
    alertFrame.art:SetScale(fancy and (0.965 + 0.035 * reveal) or (0.98 + 0.02 * reveal))

    alertFrame.text:ClearAllPoints()
    local textX = fancy and ((1 - reveal) * 10 - exitProgress * 10) or 0
    local textY = fancy and 0 or (-8 * (1 - reveal) + 7 * exitProgress)
    alertFrame.text:SetPoint("CENTER", alertFrame.art, "CENTER", textX, textY)
    alertFrame.text:SetText(GetAlertText(db, kind))
    alertFrame.text:SetTextColor(
        textColor[1] or 1,
        textColor[2] or 1,
        textColor[3] or 1,
        textColor[4] or 1
    )

    if not fancy then
        SetEffectsShown(alertFrame, false)
        return
    end

    SetEffectsShown(alertFrame, true)

    local shapeReveal = reveal * (1 - exitProgress)
    local panelHalfWidth = math.min(width * 0.30, 144)
    local panelHeight = math.min(height * 0.38, 36)
    local panelAlpha = SmoothStep(reveal) * (1 - exitProgress)
    local panelReveal = 0.72 + 0.28 * SmoothStep(reveal)
    local panelWidth = panelHalfWidth * 2 * panelReveal * (1 - 0.12 * exitProgress)
    local panelX = (1 - reveal) * 8 - exitProgress * 8

    SetLine(alertFrame.leftPlate, panelWidth, panelHeight, panelX, 0, 0)
    SetLine(alertFrame.rightPlate, panelWidth, panelHeight, panelX, 0, 0)
    SetSolidTextureColor(alertFrame.leftPlate, panelColor, panelAlpha)
    SetTextureGradient(alertFrame.rightPlate, lineColor, 0.52, diamondColor, 0.58, panelAlpha)

    local panelLineWidth = panelHalfWidth * 2 * shapeReveal
    SetLine(alertFrame.topLine, panelLineWidth, 2, 0, panelHeight * 0.5, 0)
    SetLine(alertFrame.bottomLine, panelLineWidth * 0.64, 1, 0, -panelHeight * 0.5, 0)
    SetTextureGradient(alertFrame.topLine, lineColor, 0.88, accentColor, 0.88, shapeReveal)
    SetTextureGradient(alertFrame.bottomLine, accentColor, 0.45, lineColor, 0.45, shapeReveal * 0.72)

    local railY = -height * 0.34
    local diamondHalf = 7 * shapeReveal
    local diamondMid = diamondHalf * 0.5
    local diamondEdge = math.sqrt(2) * diamondHalf
    SetLine(alertFrame.diamondTopLeft, diamondEdge, 2, -diamondMid, railY + diamondMid, math.rad(45))
    SetLine(alertFrame.diamondTopRight, diamondEdge, 2, diamondMid, railY + diamondMid, math.rad(-45))
    SetLine(alertFrame.diamondBottomLeft, diamondEdge, 2, -diamondMid, railY - diamondMid, math.rad(-45))
    SetLine(alertFrame.diamondBottomRight, diamondEdge, 2, diamondMid, railY - diamondMid, math.rad(45))
    SetTextureColor(alertFrame.diamondTopLeft, diamondColor, shapeReveal)
    SetTextureColor(alertFrame.diamondTopRight, diamondColor, shapeReveal)
    SetTextureColor(alertFrame.diamondBottomLeft, diamondColor, shapeReveal)
    SetTextureColor(alertFrame.diamondBottomRight, diamondColor, shapeReveal)

    local railGap = 12
    local railWidth = math.max(1, (panelHalfWidth - railGap - 12) * shapeReveal)
    SetLine(alertFrame.leftLine, railWidth, 2, -(railGap + railWidth * 0.5), railY, 0)
    SetLine(alertFrame.rightLine, railWidth, 2, railGap + railWidth * 0.5, railY, 0)
    SetTextureGradient(alertFrame.leftLine, accentColor, 0.55, lineColor, 1, shapeReveal)
    SetTextureGradient(alertFrame.rightLine, lineColor, 1, accentColor, 0.55, shapeReveal)

    local sideDiamondX = panelHalfWidth + 8 + 18 * exitProgress
    local sideDiamondSize = 5 * shapeReveal
    SetLine(alertFrame.leftDiamond, sideDiamondSize, sideDiamondSize, -sideDiamondX, railY, math.rad(45))
    SetLine(alertFrame.rightDiamond, sideDiamondSize, sideDiamondSize, sideDiamondX, railY, math.rad(45))
    SetTextureColor(alertFrame.leftDiamond, accentColor, shapeReveal * 0.85)
    SetTextureColor(alertFrame.rightDiamond, accentColor, shapeReveal * 0.85)

    local bracketX = math.min(width * 0.39, 188) + (1 - reveal) * 26 + exitProgress * 24
    local bracketY = math.min(height * 0.25, 24)
    local bracketWidth = 24 * shapeReveal
    local bracketHeight = 13 * shapeReveal
    SetLine(alertFrame.leftWingTop, bracketWidth, 2, -bracketX + bracketWidth * 0.5, bracketY, 0)
    SetLine(alertFrame.leftWingBottom, bracketWidth, 2, -bracketX + bracketWidth * 0.5, -bracketY, 0)
    SetLine(alertFrame.rightWingTop, bracketWidth, 2, bracketX - bracketWidth * 0.5, bracketY, 0)
    SetLine(alertFrame.rightWingBottom, bracketWidth, 2, bracketX - bracketWidth * 0.5, -bracketY, 0)
    SetLine(alertFrame.leftCapTop, 2, bracketHeight, -bracketX, bracketY - bracketHeight * 0.5, 0)
    SetLine(alertFrame.leftCapBottom, 2, bracketHeight, -bracketX, -bracketY + bracketHeight * 0.5, 0)
    SetLine(alertFrame.rightCapTop, 2, bracketHeight, bracketX, bracketY - bracketHeight * 0.5, 0)
    SetLine(alertFrame.rightCapBottom, 2, bracketHeight, bracketX, -bracketY + bracketHeight * 0.5, 0)
    SetTextureColor(alertFrame.leftWingTop, wingColor, shapeReveal)
    SetTextureColor(alertFrame.leftWingBottom, wingColor, shapeReveal)
    SetTextureColor(alertFrame.rightWingTop, wingColor, shapeReveal)
    SetTextureColor(alertFrame.rightWingBottom, wingColor, shapeReveal)
    SetTextureColor(alertFrame.leftCapTop, wingColor, shapeReveal)
    SetTextureColor(alertFrame.leftCapBottom, wingColor, shapeReveal)
    SetTextureColor(alertFrame.rightCapTop, wingColor, shapeReveal)
    SetTextureColor(alertFrame.rightCapBottom, wingColor, shapeReveal)

    local scanAlpha = math.sin(math.pi * reveal) * (1 - exitProgress)
    local scanX = -panelHalfWidth + panelHalfWidth * 2 * reveal
    SetLine(alertFrame.flash, 52, 2, scanX, 0, 0)
    SetTextureColor(alertFrame.flash, flashColor, scanAlpha)
end

local function StopAnimation(hideFrame)
    animationState = nil
    if not alertFrame then return end

    alertFrame.art:SetScale(1)
    if hideFrame then
        alertFrame:Hide()
    end
end

local function UpdateAnimation()
    if not (alertFrame and animationState) then return end

    local elapsed = GetTime() - animationState.startedAt
    local duration = animationState.duration
    local progress = Clamp01(elapsed / duration)
    local reveal
    local exitProgress = 0
    local visibility

    if progress < 0.22 then
        reveal = EaseOutCubic(progress / 0.22)
        visibility = SmoothStep(progress / 0.10)
    elseif progress < 0.72 then
        reveal = 1
        visibility = 1
    else
        reveal = 1
        exitProgress = SmoothStep((progress - 0.72) / 0.28)
        visibility = 1 - exitProgress
    end

    ApplyStaticLayout(animationState.kind, reveal, exitProgress, visibility)

    if progress >= 1 then
        StopAnimation(true)
    end
end

function CombatStateAlert:CreateFrame()
    if alertFrame then return alertFrame end

    local db = self.db or EnsureDB()
    if not db then return nil end

    local frame = CreateFrame("Frame", "DDingToolKit_CombatStateAlertFrame", UIParent)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:Hide()

    frame.art = CreateFrame("Frame", nil, frame)
    frame.art:SetAllPoints(frame)

    frame.flash = CreateFlatTexture(frame.art, "ARTWORK", -1)
    frame.topLine = CreateFlatTexture(frame.art, "ARTWORK", -2)
    frame.bottomLine = CreateFlatTexture(frame.art, "ARTWORK", -2)
    frame.leftLine = CreateFlatTexture(frame.art, "ARTWORK", 0)
    frame.rightLine = CreateFlatTexture(frame.art, "ARTWORK", 0)
    frame.diamondTopLeft = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.diamondTopRight = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.diamondBottomLeft = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.diamondBottomRight = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.leftDiamond = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.rightDiamond = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.leftWingTop = CreateFlatTexture(frame.art, "ARTWORK", 0)
    frame.leftWingBottom = CreateFlatTexture(frame.art, "ARTWORK", 0)
    frame.rightWingTop = CreateFlatTexture(frame.art, "ARTWORK", 0)
    frame.rightWingBottom = CreateFlatTexture(frame.art, "ARTWORK", 0)
    frame.leftPlate = CreateFlatTexture(frame.art, "BACKGROUND", -2)
    frame.rightPlate = CreateFlatTexture(frame.art, "BACKGROUND", -2)
    frame.leftCapTop = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.leftCapBottom = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.rightCapTop = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.rightCapBottom = CreateFlatTexture(frame.art, "ARTWORK", 1)

    frame.text = frame.art:CreateFontString(nil, "OVERLAY")
    frame.text:SetJustifyH("CENTER")
    frame.text:SetJustifyV("MIDDLE")
    frame.text:SetWordWrap(false)

    frame:SetScript("OnUpdate", UpdateAnimation)

    alertFrame = frame
    self:ApplySettings()
    return frame
end

function CombatStateAlert:ApplyPosition()
    local db = self.db or EnsureDB()
    if not (db and alertFrame) then return end

    local position = CopyPosition(db.position)
    db.position = position
    alertFrame:ClearAllPoints()
    alertFrame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
end

function CombatStateAlert:ApplySettings()
    local db = EnsureDB()
    if not db then return end
    self.db = db

    if not alertFrame then return end

    local width = Clamp(db.width, 260, 800)
    local height = Clamp(db.height, 64, 200)
    local scale = Clamp(db.scale, 0.5, 2)
    local fontSize = Clamp(db.fontSize, 12, 64)
    local outline = db.fontOutline or "OUTLINE"

    alertFrame:SetSize(width, height)
    alertFrame:SetScale(scale)
    alertFrame:SetFrameStrata(db.frameStrata or "HIGH")
    alertFrame.text:SetFont(db.font or SL_FONT, fontSize, outline == "NONE" and "" or outline)
    alertFrame.text:SetWidth(math.max(1, width - 48))
    alertFrame.text:SetHeight(math.max(1, height * 0.55))
    self:ApplyPosition()

    if editPreview then
        ApplyStaticLayout("START", 1, 0, 1)
        alertFrame:Show()
    elseif animationState then
        UpdateAnimation()
    end
end

function CombatStateAlert:ShowAlert(kind, force)
    local db = self.db or EnsureDB()
    if not db then return end
    self.db = db

    kind = kind == "END" and "END" or "START"
    if not force then
        if not activeModule or editPreview then return end
        if kind == "START" and not db.showStart then return end
        if kind == "END" and not db.showEnd then return end
        if db.instanceOnly then
            local inInstance = IsInInstance()
            if not inInstance then return end
        end
    end

    PlayAlertSound(db, kind)

    self:CreateFrame()
    if not alertFrame then return end

    displayToken = displayToken + 1
    local currentDisplayToken = displayToken
    StopAnimation(false)
    self:ApplySettings()
    alertFrame:Show()

    if not db.animationEnabled then
        ApplyStaticLayout(kind, 1, 0, 1)
        C_Timer.After(Clamp(db.duration, 0.8, 4), function()
            if alertFrame and not editPreview and currentDisplayToken == displayToken and not animationState then
                alertFrame:Hide()
            end
        end)
        return
    end

    animationState = {
        kind = kind,
        startedAt = GetTime(),
        duration = Clamp(db.duration, 0.8, 4),
    }
    ApplyStaticLayout(kind, 0, 0, 0)
end

function CombatStateAlert:TestAlert(kind)
    sequenceToken = sequenceToken + 1
    self:ShowAlert(kind, true)
end

function CombatStateAlert:TestSequence()
    sequenceToken = sequenceToken + 1
    local token = sequenceToken
    local db = self.db or EnsureDB()
    if not db then return end

    self:ShowAlert("START", true)
    C_Timer.After(Clamp(db.duration, 0.8, 4) + 0.35, function()
        if token == sequenceToken and not editPreview then
            CombatStateAlert:ShowAlert("END", true)
        end
    end)
end

function CombatStateAlert:ResetPosition()
    local db = self.db or EnsureDB()
    if not db then return end

    db.position = CopyPosition()
    self:ApplyPosition()
end

function CombatStateAlert:EnterEditPreview()
    editPreview = true
    sequenceToken = sequenceToken + 1
    displayToken = displayToken + 1
    StopAnimation(false)
    self:CreateFrame()
    self:ApplySettings()
    if alertFrame then
        alertFrame:EnableMouse(false)
        ApplyStaticLayout("START", 1, 0, 1)
        alertFrame:Show()
    end
end

function CombatStateAlert:RefreshEditPreview()
    if not editPreview then return end
    self:ApplySettings()
end

function CombatStateAlert:ExitEditPreview()
    editPreview = false
    StopAnimation(true)
end

function CombatStateAlert:OnInitialize()
    self.db = EnsureDB()
end

function CombatStateAlert:OnEnable()
    self.db = EnsureDB()
    activeModule = true
    sequenceToken = sequenceToken + 1
    displayToken = displayToken + 1
    self:CreateFrame()
    self:ApplySettings()
    if alertFrame and not editPreview then
        alertFrame:Hide()
    end
end

function CombatStateAlert:OnDisable()
    activeModule = false
    editPreview = false
    sequenceToken = sequenceToken + 1
    displayToken = displayToken + 1
    StopAnimation(true)
end

function CombatStateAlert:OnMediaChanged()
    self:ApplySettings()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        sequenceToken = sequenceToken + 1
        displayToken = displayToken + 1
        if not editPreview then
            StopAnimation(true)
        end
        return
    end

    if not activeModule or editPreview then return end
    CombatStateAlert:ShowAlert(event == "PLAYER_REGEN_DISABLED" and "START" or "END")
end)

DDingToolKit:RegisterModule("CombatStateAlert", CombatStateAlert)
