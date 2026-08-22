--[[
    DDingToolKit - CharacterPositionMarker
    Code-drawn player position marker for combat visibility.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local SL = _G.DDingUI_StyleLib
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local SYSTEM_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\FRIZQT__.TTF"
local EMPTY_DIAMOND_TEXTURE = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\CharacterPositionMarker\\empty_diamond.tga"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC")
    or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: "

local CharacterPositionMarker = {}
CharacterPositionMarker.name = "CharacterPositionMarker"
ns.CharacterPositionMarker = CharacterPositionMarker

local markerFrame
local eventFrame
local editPreview = false
local testMode = false
local testToken = 0
local rangeThrottle = 0
local displayState = "hidden"
local visibilityAnim

local EFFECT_LINE_COUNT = 8
local SYSTEM_TICK_COUNT = 12
local SYSTEM_GLYPHS = { "SYS", "01", "R", ">>", "II", "//", "A", "07" }
local DEFAULT_EFFECT_COLOR = { 0.18, 0.78, 1.00, 0.85 }
local DEFAULT_EFFECT_SECONDARY_COLOR = { 0.62, 0.24, 1.00, 0.70 }

local MELEE_DPS_SPEC_IDS = {
    [70] = true,  -- Retribution Paladin
    [71] = true,  -- Arms Warrior
    [72] = true,  -- Fury Warrior
    [103] = true, -- Feral Druid
    [251] = true, -- Frost Death Knight
    [252] = true, -- Unholy Death Knight
    [255] = true, -- Survival Hunter
    [259] = true, -- Assassination Rogue
    [260] = true, -- Outlaw Rogue
    [261] = true, -- Subtlety Rogue
    [263] = true, -- Enhancement Shaman
    [269] = true, -- Windwalker Monk
    [577] = true, -- Havoc Demon Hunter
}

local RANGE_SPELL_BY_SPEC = {
    [62] = 30451,
    [63] = 133,
    [64] = 30455,
    [65] = 275773,
    [66] = 96231,
    [70] = 383328,
    [71] = 12294,
    [72] = 23881,
    [73] = 23922,
    [102] = 8921,
    [103] = 22568,
    [104] = 33917,
    [105] = 8921,
    [250] = 49998,
    [251] = 49998,
    [252] = 49998,
    [253] = 187707,
    [254] = 147362,
    [255] = 147362,
    [256] = 585,
    [257] = 585,
    [258] = 8902,
    [259] = 1766,
    [260] = 1766,
    [261] = 1766,
    [262] = 188196,
    [263] = 60103,
    [264] = 188196,
    [265] = 686,
    [266] = 105174,
    [267] = 116858,
    [268] = 100780,
    [269] = 100780,
    [270] = 100780,
    [577] = 162794,
    [581] = 263642,
    [1467] = 362969,
    [1468] = 362969,
    [1473] = 395160,
    [1480] = 473662,
}

local DEFAULT_POSITION = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
}

local function CopyDefaultPosition()
    return {
        point = DEFAULT_POSITION.point,
        relativePoint = DEFAULT_POSITION.relativePoint,
        x = DEFAULT_POSITION.x,
        y = DEFAULT_POSITION.y,
    }
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function EaseOutCubic(value)
    value = Clamp01(value)
    local inverse = 1 - value
    return 1 - inverse * inverse * inverse
end

local function SmoothStep(value)
    value = Clamp01(value)
    return value * value * (3 - 2 * value)
end

local function IsSystemVisualMode(db)
    return (db and db.visualMode or "SYSTEM") == "SYSTEM"
end

local function EnsurePosition(db)
    if type(db.position) ~= "table" then
        db.position = CopyDefaultPosition()
    end
    db.position.point = db.position.point or DEFAULT_POSITION.point
    db.position.relativePoint = db.position.relativePoint or db.position.point
    db.position.x = db.position.x or DEFAULT_POSITION.x
    db.position.y = db.position.y or DEFAULT_POSITION.y
end

local function EnsureDB()
    if not (ns.db and ns.db.profile) then return nil end

    if type(ns.db.profile.CharacterPositionMarker) ~= "table" then
        ns.db.profile.CharacterPositionMarker = {}
    end

    local db = ns.db.profile.CharacterPositionMarker
    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.CharacterPositionMarker
    if defaults and ns.MergeDefaults then
        ns:MergeDefaults(db, defaults)
    end

    if db.rangeModeVersion == nil then
        db.meleeDpsOnly = false
        db.rangeModeVersion = 2
    end
    if db.animationStyleVersion == nil then
        db.enterAnimationDuration = 0.58
        db.exitAnimationDuration = 0.42
        db.animationStyleVersion = 2
    end
    if db.visualMode == nil then
        db.visualMode = "SYSTEM"
    end

    EnsurePosition(db)
    return db
end

local function GetTexture(frame, index)
    if not frame.textures[index] then
        frame.textures[index] = frame:CreateTexture(nil, "ARTWORK")
        frame.textures[index]:SetTexture(SL_FLAT)
    end

    local texture = frame.textures[index]
    texture:ClearAllPoints()
    texture:SetTexture(SL_FLAT)
    texture:SetTexCoord(0, 1, 0, 1)
    if texture.SetRotation then
        texture:SetRotation(0)
    end
    texture:Show()
    return texture
end

local function HideTextures(frame)
    for _, texture in ipairs(frame.textures) do
        texture:Hide()
        texture:ClearAllPoints()
        if texture.SetRotation then
            texture:SetRotation(0)
        end
    end
end

local function AddLine(frame, index, width, height, x, y, rotation)
    local texture = GetTexture(frame, index)
    width = math.max(1, width)
    height = math.max(1, height)
    x = x or 0
    y = y or 0

    texture:SetSize(width, height)
    texture:SetPoint("CENTER", frame, "CENTER", x, y)
    texture:SetColorTexture(1, 1, 1, 1)
    texture:SetAlpha(1)
    if rotation and texture.SetRotation then
        texture:SetRotation(rotation)
    end
    if frame.layout then
        frame.layout[index] = {
            width = width,
            height = height,
            x = x,
            y = y,
            rotation = rotation or 0,
        }
    end
    return texture
end

local function ApplyVertexColor(frame, color)
    color = color or { 0.15, 1.00, 0.25, 0.9 }
    local r = color[1] or 1
    local g = color[2] or 1
    local b = color[3] or 1
    local a = color[4] or 1

    for _, texture in ipairs(frame.textures) do
        if texture:IsShown() then
            texture:SetVertexColor(r, g, b, a)
        end
    end
end

local function DrawMarker(frame, db)
    HideTextures(frame)
    frame.layout = {}

    local size = Clamp(db.size, 16, 180)
    local thickness = Clamp(db.thickness, 1, math.max(1, size))
    local gap = Clamp(db.centerGap, 0, math.floor(size * 0.8))
    local shape = db.shape or "CROSS"

    frame:SetSize(size, size)

    if shape == "CROSS" then
        AddLine(frame, 1, thickness, size, 0, 0)
        AddLine(frame, 2, size, thickness, 0, 0)
    elseif shape == "SQUARE" then
        local half = size * 0.5
        AddLine(frame, 1, size, thickness, 0, half - thickness * 0.5)
        AddLine(frame, 2, size, thickness, 0, -half + thickness * 0.5)
        AddLine(frame, 3, thickness, size, -half + thickness * 0.5, 0)
        AddLine(frame, 4, thickness, size, half - thickness * 0.5, 0)
    elseif shape == "DIAMOND" then
        local diamondSize = size * 0.68
        AddLine(frame, 1, diamondSize, diamondSize, 0, 0, math.rad(45))
    elseif shape == "EMPTY_DIAMOND" then
        local diamondSize = size * 0.92
        local texture = GetTexture(frame, 1)
        texture:SetTexture(EMPTY_DIAMOND_TEXTURE)
        texture:SetSize(diamondSize, diamondSize)
        texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetAlpha(1)
        frame.layout[1] = {
            width = diamondSize,
            height = diamondSize,
            x = 0,
            y = 0,
            rotation = 0,
        }
    else
        local arm = math.max(thickness, (size - gap) * 0.5)
        local offset = gap * 0.5 + arm * 0.5
        AddLine(frame, 1, thickness, arm, 0, offset)
        AddLine(frame, 2, thickness, arm, 0, -offset)
        AddLine(frame, 3, arm, thickness, -offset, 0)
        AddLine(frame, 4, arm, thickness, offset, 0)
    end

end

local function GetSegmentTravelOffset(index, segment, distance)
    local xSign = segment.x < 0 and -1 or 1
    local ySign = segment.y < 0 and -1 or 1

    if math.abs(segment.height or 0) > math.abs(segment.width or 0) then
        return 0, ySign * distance
    end
    if math.abs(segment.width or 0) > math.abs(segment.height or 0) then
        return xSign * distance, 0
    end

    if index % 2 == 0 then
        xSign = -xSign
    end
    return xSign * distance * 0.72, ySign * distance * 0.72
end

local function ApplySegmentAnimation(frame, progress, mode)
    local layout = frame.layout
    if not layout then return end

    local size = frame:GetWidth() or 64
    local distance = size * 0.42
    local move = mode == "exit" and progress * distance or (1 - progress) * distance
    local alpha = mode == "exit" and (1 - progress) or progress

    for index, segment in ipairs(layout) do
        local texture = frame.textures and frame.textures[index]
        if texture then
            local xOffset, yOffset = GetSegmentTravelOffset(index, segment, move)
            texture:ClearAllPoints()
            texture:SetPoint("CENTER", frame, "CENTER", segment.x + xOffset, segment.y + yOffset)
            texture:SetSize(segment.width, segment.height)
            if texture.SetRotation then
                texture:SetRotation(segment.rotation or 0)
            end
            texture:SetAlpha(alpha)
            texture:Show()
        end
    end
end

local function ResetSegmentAnimation(frame)
    ApplySegmentAnimation(frame, 1, "enter")
end

local function SetEffectColor(texture, color)
    color = color or DEFAULT_EFFECT_COLOR
    texture:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, 1)
end

local function CreateFxTexture(frame, layer, blendMode)
    local texture = frame:CreateTexture(nil, layer or "OVERLAY")
    texture:SetTexture(SL_FLAT)
    texture:SetBlendMode(blendMode or "ADD")
    texture:Hide()
    return texture
end

local function PositionFxTexture(texture, frame, width, height, x, y, rotation, color, alpha)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", frame, "CENTER", x or 0, y or 0)
    texture:SetSize(math.max(1, width or 1), math.max(1, height or 1))
    SetEffectColor(texture, color)
    texture:SetAlpha(alpha or 1)
    if texture.SetRotation then
        texture:SetRotation(rotation or 0)
    end
    texture:Show()
end

local function PositionFxText(text, frame, value, x, y, color, alpha, size)
    text:ClearAllPoints()
    text:SetPoint("CENTER", frame, "CENTER", x or 0, y or 0)
    text:SetFont(SYSTEM_FONT, size or 8, "OUTLINE")
    color = color or DEFAULT_EFFECT_COLOR
    text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha or color[4] or 1)
    text:SetText(value or "")
    text:Show()
end

local function EnsureEffectTextures(frame)
    if not frame.fxTextures then
        frame.fxTextures = {}
        for index = 1, EFFECT_LINE_COUNT do
            frame.fxTextures[index] = CreateFxTexture(frame, "OVERLAY", "ADD")
        end
    end

    if frame.systemFx then return end

    local fx = {
        panels = {},
        corners = {},
        diamond = {},
        ticks = {},
        glyphs = {},
    }
    frame.systemFx = fx

    fx.panelBack = CreateFxTexture(frame, "ARTWORK", "BLEND")
    fx.scanLine = CreateFxTexture(frame, "OVERLAY", "ADD")
    fx.scanGlow = CreateFxTexture(frame, "OVERLAY", "ADD")

    for index = 1, 4 do
        fx.panels[index] = CreateFxTexture(frame, "OVERLAY", "ADD")
    end
    for index = 1, 8 do
        fx.corners[index] = CreateFxTexture(frame, "OVERLAY", "ADD")
    end
    for index = 1, 4 do
        fx.diamond[index] = CreateFxTexture(frame, "OVERLAY", "ADD")
    end
    for index = 1, SYSTEM_TICK_COUNT do
        fx.ticks[index] = CreateFxTexture(frame, "OVERLAY", "ADD")
    end
    for index = 1, #SYSTEM_GLYPHS do
        local text = frame:CreateFontString(nil, "OVERLAY")
        text:SetFont(SYSTEM_FONT, 7, "OUTLINE")
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        text:Hide()
        fx.glyphs[index] = text
    end

    fx.statusText = frame:CreateFontString(nil, "OVERLAY")
    fx.statusText:SetFont(SYSTEM_FONT, 8, "OUTLINE")
    fx.statusText:SetJustifyH("CENTER")
    fx.statusText:SetJustifyV("MIDDLE")
    fx.statusText:Hide()

    fx.subText = frame:CreateFontString(nil, "OVERLAY")
    fx.subText:SetFont(SYSTEM_FONT, 6, "OUTLINE")
    fx.subText:SetJustifyH("CENTER")
    fx.subText:SetJustifyV("MIDDLE")
    fx.subText:Hide()
end

local function HideSystemFX(frame)
    local fx = frame.systemFx
    if not fx then return end

    if fx.panelBack then fx.panelBack:Hide() end
    if fx.scanLine then fx.scanLine:Hide() end
    if fx.scanGlow then fx.scanGlow:Hide() end
    if fx.statusText then fx.statusText:Hide() end
    if fx.subText then fx.subText:Hide() end

    for _, list in pairs({ fx.panels, fx.corners, fx.diamond, fx.ticks, fx.glyphs }) do
        for _, object in ipairs(list) do
            object:Hide()
            if object.SetAlpha then object:SetAlpha(0) end
        end
    end
end

local function HideEffectTextures(frame)
    if frame.fxTextures then
        for _, texture in ipairs(frame.fxTextures) do
            texture:Hide()
            texture:SetAlpha(0)
        end
    end
    HideSystemFX(frame)
end

local function GetWarningEffectColor(db)
    local c = db and db.outOfRangeColor or { 1, 0.05, 0.05, 0.95 }
    return { c[1] or 1, c[2] or 0.05, c[3] or 0.05, c[4] or 0.95 }
end

local function DrawSystemShell(frame, db, alpha, spread, warning, statusText, subText, scanProgress)
    EnsureEffectTextures(frame)

    local fx = frame.systemFx
    local size = frame:GetWidth() or 64
    local thickness = math.max(1, (db.thickness or 5) * 0.42)
    local primary = warning and GetWarningEffectColor(db) or (db.effectColor or DEFAULT_EFFECT_COLOR)
    local secondary = warning and { 1.00, 0.18, 0.10, 0.80 } or (db.effectSecondaryColor or DEFAULT_EFFECT_SECONDARY_COLOR)
    local a = Clamp01(alpha or 1)
    local shellSpread = spread or 1

    local diamondRadius = size * 0.70 * shellSpread
    local diamondSide = diamondRadius * 1.4142
    local diamondOffset = diamondRadius * 0.5
    PositionFxTexture(fx.diamond[1], frame, diamondSide, thickness, diamondOffset, diamondOffset, math.rad(-45), primary, a * 0.50)
    PositionFxTexture(fx.diamond[2], frame, diamondSide, thickness, diamondOffset, -diamondOffset, math.rad(45), primary, a * 0.50)
    PositionFxTexture(fx.diamond[3], frame, diamondSide, thickness, -diamondOffset, -diamondOffset, math.rad(-45), primary, a * 0.50)
    PositionFxTexture(fx.diamond[4], frame, diamondSide, thickness, -diamondOffset, diamondOffset, math.rad(45), primary, a * 0.50)

    local cornerX = size * 0.84 * shellSpread
    local cornerY = size * 0.78 * shellSpread
    local cornerLen = size * 0.30
    local cornerAlpha = warning and a * 0.85 or a * 0.58
    PositionFxTexture(fx.corners[1], frame, cornerLen, thickness, -cornerX + cornerLen * 0.5, cornerY, 0, primary, cornerAlpha)
    PositionFxTexture(fx.corners[2], frame, thickness, cornerLen, -cornerX, cornerY - cornerLen * 0.5, 0, primary, cornerAlpha)
    PositionFxTexture(fx.corners[3], frame, cornerLen, thickness, cornerX - cornerLen * 0.5, cornerY, 0, primary, cornerAlpha)
    PositionFxTexture(fx.corners[4], frame, thickness, cornerLen, cornerX, cornerY - cornerLen * 0.5, 0, primary, cornerAlpha)
    PositionFxTexture(fx.corners[5], frame, cornerLen, thickness, -cornerX + cornerLen * 0.5, -cornerY, 0, primary, cornerAlpha)
    PositionFxTexture(fx.corners[6], frame, thickness, cornerLen, -cornerX, -cornerY + cornerLen * 0.5, 0, primary, cornerAlpha)
    PositionFxTexture(fx.corners[7], frame, cornerLen, thickness, cornerX - cornerLen * 0.5, -cornerY, 0, primary, cornerAlpha)
    PositionFxTexture(fx.corners[8], frame, thickness, cornerLen, cornerX, -cornerY + cornerLen * 0.5, 0, primary, cornerAlpha)

    local tickRadius = size * 1.04 * shellSpread
    for index, texture in ipairs(fx.ticks) do
        local angle = (index - 1) * math.pi * 2 / SYSTEM_TICK_COUNT
        local x = math.cos(angle) * tickRadius
        local y = math.sin(angle) * tickRadius
        local tickLen = size * (index % 3 == 0 and 0.16 or 0.10)
        local tickColor = index % 2 == 0 and secondary or primary
        PositionFxTexture(texture, frame, tickLen, thickness, x, y, angle + math.pi * 0.5, tickColor, a * 0.45)
    end

    if statusText and statusText ~= "" then
        local panelY = size * 1.05 * shellSpread
        local panelW = size * 1.82
        local panelH = size * 0.28
        fx.panelBack:ClearAllPoints()
        fx.panelBack:SetPoint("CENTER", frame, "CENTER", 0, panelY)
        fx.panelBack:SetSize(panelW, panelH)
        fx.panelBack:SetColorTexture(0.015, 0.025, 0.05, a * 0.62)
        fx.panelBack:SetAlpha(1)
        fx.panelBack:Show()

        PositionFxTexture(fx.panels[1], frame, panelW * 0.78, thickness, 0, panelY + panelH * 0.5, 0, primary, a * 0.80)
        PositionFxTexture(fx.panels[2], frame, panelW * 0.78, thickness, 0, panelY - panelH * 0.5, 0, primary, a * 0.55)
        PositionFxTexture(fx.panels[3], frame, thickness, panelH * 0.70, -panelW * 0.45, panelY, 0, secondary, a * 0.65)
        PositionFxTexture(fx.panels[4], frame, thickness, panelH * 0.70, panelW * 0.45, panelY, 0, secondary, a * 0.65)

        PositionFxText(fx.statusText, frame, statusText, 0, panelY + 1, primary, a, 8)
        if subText and subText ~= "" then
            PositionFxText(fx.subText, frame, subText, 0, -size * 0.98 * shellSpread, secondary, a * 0.62, 6)
        else
            fx.subText:Hide()
        end
    else
        fx.panelBack:Hide()
        fx.statusText:Hide()
        fx.subText:Hide()
        for _, texture in ipairs(fx.panels) do texture:Hide() end
    end

    if scanProgress then
        local scanY = -size * 0.56 + size * 1.12 * Clamp01(scanProgress)
        local scanAlpha = warning and a * 0.75 or a * 0.45
        PositionFxTexture(fx.scanGlow, frame, size * 1.82, thickness * 3.2, 0, scanY, 0, secondary, scanAlpha * 0.38)
        PositionFxTexture(fx.scanLine, frame, size * 1.65, thickness, 0, scanY, 0, primary, scanAlpha)
    else
        fx.scanGlow:Hide()
        fx.scanLine:Hide()
    end

    local glyphRadius = size * 1.18 * shellSpread
    for index, text in ipairs(fx.glyphs) do
        if statusText and statusText ~= "" then
            local angle = (index - 1) * math.pi * 2 / #fx.glyphs + math.rad(22)
            local x = math.cos(angle) * glyphRadius
            local y = math.sin(angle) * glyphRadius
            PositionFxText(text, frame, SYSTEM_GLYPHS[index], x, y, index % 2 == 0 and secondary or primary, a * 0.44, 6)
        else
            text:Hide()
        end
    end
end

local function UpdateEffectTextures(frame, progress, mode, db)
    if not IsSystemVisualMode(db) then
        HideEffectTextures(frame)
        return
    end

    EnsureEffectTextures(frame)

    local size = frame:GetWidth() or 64
    local p = mode == "exit" and SmoothStep(progress) or EaseOutCubic(progress)
    local radius = mode == "exit"
        and (size * (0.28 + p * 0.72))
        or (size * (0.86 - p * 0.50))
    local pulse = math.sin(progress * math.pi)
    local thickness = math.max(1, (db.thickness or 5) * 0.55)
    local primary = db.effectColor or DEFAULT_EFFECT_COLOR
    local secondary = db.effectSecondaryColor or DEFAULT_EFFECT_SECONDARY_COLOR

    for index, texture in ipairs(frame.fxTextures) do
        local angle = (index - 1) * math.pi * 2 / EFFECT_LINE_COUNT
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        local length = size * (index % 2 == 0 and 0.30 or 0.20)
        local color = index % 2 == 0 and secondary or primary
        local alpha = (color[4] or 1) * pulse

        texture:ClearAllPoints()
        texture:SetPoint("CENTER", frame, "CENTER", x, y)
        texture:SetSize(length, thickness)
        SetEffectColor(texture, color)
        texture:SetAlpha(alpha)
        if texture.SetRotation then
            texture:SetRotation(angle)
        end
        texture:Show()
    end

    local shellProgress = mode == "exit" and progress or (1 - progress)
    local spread = 1 + shellProgress * 0.42
    local statusText = mode == "exit" and "SYSTEM CLOSING" or "SYSTEM ONLINE"
    local subText = mode == "exit" and "COMBAT DATA SEALED" or "PLAYER POSITION LOCKED"
    DrawSystemShell(frame, db, math.max(pulse, 0.18), spread, false, statusText, subText, mode == "exit" and (1 - progress) or progress)
end

local function UpdateSystemActiveState(frame, db, warning)
    if visibilityAnim then return end
    if not IsSystemVisualMode(db) then
        HideEffectTextures(frame)
        return
    end
    if not frame:IsShown() then
        HideEffectTextures(frame)
        return
    end

    local now = GetTime and GetTime() or 0
    local pulse = warning and (0.65 + math.sin(now * 9) * 0.20) or 0.28
    local spread = warning and (1.06 + math.sin(now * 7) * 0.025) or 1
    local statusText = warning and "TARGET OUT OF RANGE" or nil
    local subText = warning and "REPOSITION REQUIRED" or nil
    local scanProgress = warning and ((math.sin(now * 4.5) + 1) * 0.5) or nil

    DrawSystemShell(frame, db or {}, pulse, spread, warning, statusText, subText, scanProgress)
end

local function FinishVisibilityAnimation(frame)
    local mode = visibilityAnim and visibilityAnim.mode
    local db = visibilityAnim and visibilityAnim.db or CharacterPositionMarker.db or EnsureDB()
    visibilityAnim = nil
    HideEffectTextures(frame)

    if mode == "exit" then
        displayState = "hidden"
        frame:SetAlpha(1)
        frame:SetScale((db and db.scale) or 1)
        frame:Hide()
        ResetSegmentAnimation(frame)
    else
        displayState = "shown"
        frame:SetAlpha(1)
        frame:SetScale((db and db.scale) or 1)
        ResetSegmentAnimation(frame)
        CharacterPositionMarker:UpdateColor()
    end
end

local function UpdateVisibilityAnimation(frame, elapsed)
    if not visibilityAnim then return end

    local db = visibilityAnim.db or CharacterPositionMarker.db or EnsureDB()
    local duration = math.max(0.01, visibilityAnim.duration or 0.35)
    visibilityAnim.elapsed = visibilityAnim.elapsed + elapsed

    local rawProgress = Clamp01(visibilityAnim.elapsed / duration)
    local progress = visibilityAnim.mode == "exit" and SmoothStep(rawProgress) or EaseOutCubic(rawProgress)
    local baseScale = (db and db.scale) or 1

    if visibilityAnim.mode == "exit" then
        frame:SetAlpha(1 - progress)
        frame:SetScale(baseScale * (1 + progress * 0.08))
        ApplySegmentAnimation(frame, progress, "exit")
        UpdateEffectTextures(frame, rawProgress, "exit", db or {})
    else
        frame:SetAlpha(progress)
        frame:SetScale(baseScale * (0.68 + progress * 0.32))
        ApplySegmentAnimation(frame, progress, "enter")
        UpdateEffectTextures(frame, rawProgress, "enter", db or {})
    end

    if rawProgress >= 1 then
        FinishVisibilityAnimation(frame)
    end
end

local function ShowFrameDirect(frame, db)
    visibilityAnim = nil
    displayState = "shown"
    HideEffectTextures(frame)
    frame:SetAlpha(1)
    frame:SetScale((db and db.scale) or 1)
    ResetSegmentAnimation(frame)
    frame:Show()
end

local function HideFrameDirect(frame, db)
    visibilityAnim = nil
    displayState = "hidden"
    HideEffectTextures(frame)
    frame:SetAlpha(1)
    frame:SetScale((db and db.scale) or 1)
    ResetSegmentAnimation(frame)
    frame:Hide()
end

local function StartVisibilityAnimation(frame, mode, db)
    db = db or {}
    local duration = mode == "exit" and (db.exitAnimationDuration or 0.28) or (db.enterAnimationDuration or 0.38)
    visibilityAnim = {
        mode = mode,
        elapsed = 0,
        duration = duration,
        db = db,
    }

    if mode == "exit" then
        displayState = "hiding"
        frame:Show()
        frame:SetAlpha(1)
        ResetSegmentAnimation(frame)
    else
        displayState = "showing"
        frame:Show()
        frame:SetAlpha(0)
        ApplySegmentAnimation(frame, 0, "enter")
    end
end

local function GetCurrentSpecID()
    if not GetSpecialization or not GetSpecializationInfo then return nil end
    local specIndex = GetSpecialization()
    if not specIndex or IsSecret(specIndex) then return nil end

    local specID = GetSpecializationInfo(specIndex)
    if not specID or IsSecret(specID) then return nil end
    return specID
end

local function IsMeleeDpsSpec()
    local specID = GetCurrentSpecID()
    return specID and MELEE_DPS_SPEC_IDS[specID] == true
end

local function GetCurrentRoleCategory()
    if not GetSpecialization then return nil end
    local specIndex = GetSpecialization()
    if not specIndex or IsSecret(specIndex) then return nil end

    local role
    if GetSpecializationRole then
        role = GetSpecializationRole(specIndex)
    end
    if IsSecret(role) then return nil end
    if (not role or role == "NONE") and GetSpecializationInfo then
        role = select(5, GetSpecializationInfo(specIndex))
    end
    if not role or IsSecret(role) then return nil end

    if role == "TANK" then return "TANK" end
    if role == "HEALER" then return "HEALER" end
    if role ~= "DAMAGER" then return nil end
    return IsMeleeDpsSpec() and "MELEE" or "RANGED"
end

local function IsCurrentRoleEnabled(db)
    local category = GetCurrentRoleCategory()
    if category == "MELEE" then return db.showMelee ~= false end
    if category == "RANGED" then return db.showRanged ~= false end
    if category == "TANK" then return db.showTank ~= false end
    if category == "HEALER" then return db.showHealer ~= false end
    return false
end

local function HasAttackableTarget()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")
end

local function IsCombatActive()
    return InCombatLockdown()
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
        or (UnitExists("pet") and UnitAffectingCombat and UnitAffectingCombat("pet"))
end

local function NormalizeRangeResult(result)
    local spellRangeResult = Enum and Enum.SpellRangeCheckResult
    if spellRangeResult then
        if result == spellRangeResult.InRange then return true end
        if result == spellRangeResult.OutOfRange then return false end
    end

    if result == true or result == 1 then return true end
    if result == false or result == 0 then return false end
    return nil
end

local function GetRangeSpell(db)
    if db then
        local userSpell = db.rangeSpell
        if userSpell and userSpell ~= "" then
            return tonumber(userSpell) or userSpell
        end
    end

    local specID = GetCurrentSpecID()
    return specID and RANGE_SPELL_BY_SPEC[specID] or nil
end

local function GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            return info.name
        end
        if type(info) == "string" then
            return info
        end
    end

    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end
    return nil
end

local function CheckSpellRange(spellID)
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, result = pcall(C_Spell.IsSpellInRange, spellID, "target")
        if ok then
            local normalized = NormalizeRangeResult(result)
            if normalized ~= nil then return normalized end
        end

        local spellName = GetSpellName(spellID)
        if spellName then
            local okByName, resultByName = pcall(C_Spell.IsSpellInRange, spellName, "target")
            if okByName then
                local normalized = NormalizeRangeResult(resultByName)
                if normalized ~= nil then return normalized end
            end
        end
    end

    if IsSpellInRange then
        local spellName = GetSpellName(spellID)
        if spellName then
            local ok, result = pcall(IsSpellInRange, spellName, "target")
            if ok then
                local normalized = NormalizeRangeResult(result)
                if normalized ~= nil then return normalized end
            end
        end
    end

    return nil
end

local function IsTargetOutOfRange(db)
    local spell = GetRangeSpell(db)
    if not spell or not UnitExists("target") then return false end

    local inRange = CheckSpellRange(spell)
    return inRange == false
end

function CharacterPositionMarker:OnInitialize()
    self.db = EnsureDB()
    self.initialized = true
end

function CharacterPositionMarker:CreateFrame()
    if markerFrame then return markerFrame end

    markerFrame = CreateFrame("Frame", "DDingToolKit_CharacterPositionMarkerFrame", UIParent)
    markerFrame:SetFrameStrata("MEDIUM")
    markerFrame:SetClampedToScreen(true)
    markerFrame:SetIgnoreParentAlpha(true)
    markerFrame:EnableMouse(false)
    markerFrame:SetMovable(true)
    markerFrame.textures = {}
    EnsureEffectTextures(markerFrame)
    markerFrame:SetScript("OnUpdate", function(_, elapsed)
        UpdateVisibilityAnimation(markerFrame, elapsed)

        rangeThrottle = rangeThrottle + elapsed
        local db = CharacterPositionMarker.db or (ns.db and ns.db.profile and ns.db.profile.CharacterPositionMarker)
        if rangeThrottle < ((db and db.rangeUpdateRate) or 0.1) then return end
        rangeThrottle = 0
        CharacterPositionMarker:UpdateVisibility()
        CharacterPositionMarker:UpdateColor()
    end)
    markerFrame:Hide()

    return markerFrame
end

function CharacterPositionMarker:IsOutOfMeleeRange()
    local db = self.db or EnsureDB()
    if not db then return false end
    if not db.rangeCheck then return false end
    if db.meleeDpsOnly == true and not IsMeleeDpsSpec() then return false end
    if not HasAttackableTarget() then return false end

    return IsTargetOutOfRange(db)
end

function CharacterPositionMarker:GetActiveColor()
    local db = self.db or EnsureDB()
    if not db then return { 0.15, 1.00, 0.25, 0.9 } end
    if self:IsOutOfMeleeRange() then
        return db.outOfRangeColor or { 1, 0, 0, 0.95 }
    end
    return db.color or { 0.15, 1.00, 0.25, 0.9 }
end

function CharacterPositionMarker:UpdateColor()
    if not markerFrame or not markerFrame:IsShown() then return end

    local db = self.db or EnsureDB()
    local outOfRange = self:IsOutOfMeleeRange()
    local color
    if outOfRange then
        color = db and db.outOfRangeColor or { 1, 0, 0, 0.95 }
    else
        color = db and db.color or { 0.15, 1.00, 0.25, 0.9 }
    end

    ApplyVertexColor(markerFrame, color)
    UpdateSystemActiveState(markerFrame, db, outOfRange)
end

function CharacterPositionMarker:ApplyPosition()
    local db = self.db or EnsureDB()
    if not db then return end

    local frame = self:CreateFrame()
    frame:ClearAllPoints()
    frame:SetPoint(
        db.position.point or "CENTER",
        UIParent,
        db.position.relativePoint or db.position.point or "CENTER",
        db.position.x or 0,
        db.position.y or 0
    )
end

function CharacterPositionMarker:ApplySettings()
    self.db = EnsureDB()
    if not self.db then return end

    local frame = self:CreateFrame()
    frame:SetFrameStrata(self.db.frameStrata or "MEDIUM")
    frame:SetScale(self.db.scale or 1)
    DrawMarker(frame, self.db)
    if not IsSystemVisualMode(self.db) then
        visibilityAnim = nil
        HideEffectTextures(frame)
        frame:SetAlpha(1)
        frame:SetScale(self.db.scale or 1)
        ResetSegmentAnimation(frame)
        if self:ShouldShow() then
            displayState = "shown"
            frame:Show()
        else
            displayState = "hidden"
            frame:Hide()
        end
    end
    self:UpdateColor()
    self:ApplyPosition()
    self:UpdateVisibility()
end

function CharacterPositionMarker:ShouldShow()
    local db = self.db or EnsureDB()
    if not db then return false end
    if editPreview or testMode then return true end
    if not db.enabled then return false end
    if not IsCurrentRoleEnabled(db) then return false end

    if db.combatOnly ~= false and not IsCombatActive() then
        return false
    end

    if db.instanceOnly then
        local inInstance = IsInInstance()
        if not inInstance then return false end
    end

    return true
end

function CharacterPositionMarker:UpdateVisibility()
    local frame = self:CreateFrame()
    frame:EnableMouse(editPreview)

    local db = self.db or EnsureDB()
    local shouldShow = self:ShouldShow()
    local useAnimation = db and IsSystemVisualMode(db) and db.animationEnabled ~= false and not editPreview

    if shouldShow then
        if displayState == "hidden" or displayState == "hiding" then
            if useAnimation then
                StartVisibilityAnimation(frame, "enter", db)
            else
                ShowFrameDirect(frame, db)
            end
        end
        self:UpdateColor()
    else
        if displayState == "shown" or displayState == "showing" then
            if useAnimation then
                StartVisibilityAnimation(frame, "exit", db)
            else
                HideFrameDirect(frame, db)
            end
        elseif displayState == "hidden" then
            frame:Hide()
        end
    end
end

function CharacterPositionMarker:RegisterEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function()
            CharacterPositionMarker:UpdateVisibility()
            CharacterPositionMarker:UpdateColor()
        end)
    end

    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
end

function CharacterPositionMarker:OnEnable()
    self.db = EnsureDB()
    self.initialized = true
    self:RegisterEvents()
    self:ApplySettings()
end

function CharacterPositionMarker:OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    editPreview = false
    testMode = false
    visibilityAnim = nil
    displayState = "hidden"
    if markerFrame then
        HideEffectTextures(markerFrame)
        markerFrame:Hide()
        markerFrame:SetAlpha(1)
        markerFrame:EnableMouse(false)
    end
end

function CharacterPositionMarker:ResetPosition()
    self.db = self.db or EnsureDB()
    if not self.db then return end
    self.db.position = CopyDefaultPosition()
    self:ApplySettings()
end

function CharacterPositionMarker:TestMode()
    testMode = not testMode
    testToken = testToken + 1
    local token = testToken
    self:ApplySettings()

    if testMode then
        C_Timer.After(8, function()
            if token ~= testToken then return end
            testMode = false
            CharacterPositionMarker:UpdateVisibility()
        end)
    end
end

function CharacterPositionMarker:EnterEditPreview()
    editPreview = true
    self:ApplySettings()
end

function CharacterPositionMarker:RefreshEditPreview()
    if editPreview then
        self:ApplySettings()
    end
end

function CharacterPositionMarker:ExitEditPreview()
    editPreview = false
    self:UpdateVisibility()
end

DDingToolKit:RegisterModule("CharacterPositionMarker", CharacterPositionMarker)
