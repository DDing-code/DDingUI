-- DDingUI Toolkit - shared calm party alert visual

local addonName, ns = ...
local SL = _G.DDingUI_StyleLib
local FLAT_TEXTURE = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local DEFAULT_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"

local DEFAULT_COLORS = {
    titleColor = { 0.78, 0.94, 1.00, 1.00 },
    subtitleColor = { 0.68, 0.80, 0.86, 1.00 },
    lineColor = { 0.26, 0.76, 0.90, 0.82 },
    accentColor = { 0.50, 0.68, 1.00, 0.82 },
    panelColor = { 0.025, 0.075, 0.10, 0.78 },
    glowColor = { 0.38, 0.82, 1.00, 0.20 },
}

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
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

local function ColorComponent(color, index, fallback)
    local value = type(color) == "table" and tonumber(color[index])
    return value ~= nil and value or fallback
end

local function CreateFlatTexture(parent, layer, subLevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, subLevel)
    texture:SetTexture(FLAT_TEXTURE)
    texture:SetColorTexture(1, 1, 1, 1)
    return texture
end

local function SetAnchoredRect(texture, width, height, point, relativeTo, relativePoint, x, y, rotation)
    texture:ClearAllPoints()
    texture:SetSize(math.max(1, width), math.max(1, height))
    texture:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
    if texture.SetRotation then texture:SetRotation(rotation or 0) end
end

local function SetCenteredRect(texture, width, height, relativeTo, x, y, rotation)
    SetAnchoredRect(texture, width, height, "CENTER", relativeTo, "CENTER", x, y, rotation)
end

local function SetSolidColor(texture, color, alpha)
    local r = ColorComponent(color, 1, 1)
    local g = ColorComponent(color, 2, 1)
    local b = ColorComponent(color, 3, 1)
    local a = ColorComponent(color, 4, 1)
    local cache = texture._calmSolidColor

    if not cache then
        cache = {}
        texture._calmSolidColor = cache
    end
    if cache[1] ~= r or cache[2] ~= g or cache[3] ~= b or cache[4] ~= a then
        cache[1], cache[2], cache[3], cache[4] = r, g, b, a
        texture:SetColorTexture(r, g, b, a)
    end
    texture:SetAlpha(Clamp01(alpha or 1))
end

local function SetGradientColor(texture, fromColor, fromAlpha, toColor, toAlpha, alpha)
    local fromR = ColorComponent(fromColor, 1, 1)
    local fromG = ColorComponent(fromColor, 2, 1)
    local fromB = ColorComponent(fromColor, 3, 1)
    local fromA = ColorComponent(fromColor, 4, 1) * Clamp01(fromAlpha or 1)
    local toR = ColorComponent(toColor, 1, 1)
    local toG = ColorComponent(toColor, 2, 1)
    local toB = ColorComponent(toColor, 3, 1)
    local toA = ColorComponent(toColor, 4, 1) * Clamp01(toAlpha or 1)
    local cache = texture._calmGradient

    if not cache then
        cache = {}
        texture._calmGradient = cache
    end

    if cache[1] ~= fromR or cache[2] ~= fromG or cache[3] ~= fromB or cache[4] ~= fromA
        or cache[5] ~= toR or cache[6] ~= toG or cache[7] ~= toB or cache[8] ~= toA then
        cache[1], cache[2], cache[3], cache[4] = fromR, fromG, fromB, fromA
        cache[5], cache[6], cache[7], cache[8] = toR, toG, toB, toA

        local applied = false
        if type(CreateColor) == "function" and type(texture.SetGradient) == "function" then
            applied = pcall(
                texture.SetGradient,
                texture,
                "HORIZONTAL",
                CreateColor(fromR, fromG, fromB, fromA),
                CreateColor(toR, toG, toB, toA)
            )
        end
        if not applied then
            texture:SetColorTexture(toR, toG, toB, math.max(fromA, toA))
        end
    end

    texture:SetAlpha(Clamp01(alpha or 1))
end

local CalmVisual = {}
CalmVisual.__index = CalmVisual

ns.CalmAlertStyle = {
    Clamp = Clamp,
    Clamp01 = Clamp01,
    SmoothStep = SmoothStep,
    EaseOutCubic = EaseOutCubic,
    ColorComponent = ColorComponent,
    CreateFlatTexture = CreateFlatTexture,
    SetAnchoredRect = SetAnchoredRect,
    SetCenteredRect = SetCenteredRect,
    SetSolidColor = SetSolidColor,
    SetGradientColor = SetGradientColor,
}

function CalmVisual:GetColor(key)
    local settings = self.settings or {}
    local color = settings[key]
    return type(color) == "table" and color or DEFAULT_COLORS[key]
end

function CalmVisual:Render(reveal, exitProgress, visibility, elapsed)
    local frame = self.frame
    if not frame then return end

    reveal = Clamp01(reveal)
    exitProgress = Clamp01(exitProgress)
    visibility = Clamp01(visibility)
    elapsed = tonumber(elapsed) or 0

    local settings = self.settings or {}
    local width = Clamp(settings.width, 320, 760)
    local height = Clamp(settings.height, 80, 170)
    local titleColor = self:GetColor("titleColor")
    local subtitleColor = self:GetColor("subtitleColor")
    local lineColor = self:GetColor("lineColor")
    local accentColor = self:GetColor("accentColor")
    local panelColor = self:GetColor("panelColor")
    local glowColor = self:GetColor("glowColor")
    local shapeReveal = SmoothStep(reveal) * (1 - 0.12 * exitProgress)

    frame.art:SetAlpha(visibility)
    frame.art:SetScale(0.975 + 0.025 * EaseOutCubic(reveal) - 0.01 * exitProgress)

    -- Matching colors at the center keep the two halves visually continuous.
    local panelReveal = 0.18 + 0.82 * EaseOutCubic(reveal)
    local panelHalfWidth = width * 0.43 * panelReveal
    local panelHeight = height * 0.58 * (0.92 + 0.08 * reveal)
    local panelAlpha = SmoothStep(reveal) * (1 - exitProgress)
    SetAnchoredRect(frame.panelLeft, panelHalfWidth, panelHeight, "RIGHT", frame.art, "CENTER", 0, 0)
    SetAnchoredRect(frame.panelRight, panelHalfWidth, panelHeight, "LEFT", frame.art, "CENTER", 0, 0)
    SetGradientColor(frame.panelLeft, panelColor, 0, panelColor, 1, panelAlpha)
    SetGradientColor(frame.panelRight, panelColor, 1, panelColor, 0, panelAlpha)

    local glowHalfWidth = width * 0.47 * panelReveal
    local glowHeight = height * 0.82
    local glowAlpha = SmoothStep(reveal) * (1 - exitProgress) * 0.72
    SetAnchoredRect(frame.glowLeft, glowHalfWidth, glowHeight, "RIGHT", frame.art, "CENTER", 0, 0)
    SetAnchoredRect(frame.glowRight, glowHalfWidth, glowHeight, "LEFT", frame.art, "CENTER", 0, 0)
    SetGradientColor(frame.glowLeft, glowColor, 0, glowColor, 0.58, glowAlpha)
    SetGradientColor(frame.glowRight, glowColor, 0.58, glowColor, 0, glowAlpha)

    local railGap = 10
    local railHalfWidth = width * 0.38 * shapeReveal
    local topY = height * 0.31
    local bottomY = -height * 0.31
    SetAnchoredRect(frame.topLeft, railHalfWidth, 2, "RIGHT", frame.art, "CENTER", -railGap, topY)
    SetAnchoredRect(frame.topRight, railHalfWidth, 2, "LEFT", frame.art, "CENTER", railGap, topY)
    SetAnchoredRect(frame.bottomLeft, railHalfWidth * 0.72, 1, "RIGHT", frame.art, "CENTER", -railGap, bottomY)
    SetAnchoredRect(frame.bottomRight, railHalfWidth * 0.72, 1, "LEFT", frame.art, "CENTER", railGap, bottomY)
    SetGradientColor(frame.topLeft, accentColor, 0.18, lineColor, 1, shapeReveal)
    SetGradientColor(frame.topRight, lineColor, 1, accentColor, 0.18, shapeReveal)
    SetGradientColor(frame.bottomLeft, accentColor, 0.08, lineColor, 0.62, shapeReveal * 0.72)
    SetGradientColor(frame.bottomRight, lineColor, 0.62, accentColor, 0.08, shapeReveal * 0.72)

    local diamondHalf = 6 * shapeReveal
    local diamondEdge = math.sqrt(2) * diamondHalf
    local diamondMid = diamondHalf * 0.5
    SetCenteredRect(frame.diamondTopLeft, diamondEdge, 1.5, frame.art, -diamondMid, topY + diamondMid, math.rad(45))
    SetCenteredRect(frame.diamondTopRight, diamondEdge, 1.5, frame.art, diamondMid, topY + diamondMid, math.rad(-45))
    SetCenteredRect(frame.diamondBottomLeft, diamondEdge, 1.5, frame.art, -diamondMid, topY - diamondMid, math.rad(-45))
    SetCenteredRect(frame.diamondBottomRight, diamondEdge, 1.5, frame.art, diamondMid, topY - diamondMid, math.rad(45))
    SetSolidColor(frame.diamondTopLeft, accentColor, shapeReveal)
    SetSolidColor(frame.diamondTopRight, accentColor, shapeReveal)
    SetSolidColor(frame.diamondBottomLeft, accentColor, shapeReveal)
    SetSolidColor(frame.diamondBottomRight, accentColor, shapeReveal)

    local titleReveal = SmoothStep((reveal - 0.14) / 0.50) * (1 - exitProgress)
    local subtitleReveal = SmoothStep((reveal - 0.24) / 0.48) * (1 - exitProgress)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("CENTER", frame.art, "CENTER", 0, 9 + (1 - titleReveal) * 5 - exitProgress * 4)
    frame.title:SetTextColor(
        ColorComponent(titleColor, 1, 1),
        ColorComponent(titleColor, 2, 1),
        ColorComponent(titleColor, 3, 1),
        ColorComponent(titleColor, 4, 1) * titleReveal
    )
    frame.subtitle:ClearAllPoints()
    frame.subtitle:SetPoint("CENTER", frame.art, "CENTER", 0, -17 + (1 - subtitleReveal) * 4 - exitProgress * 3)
    frame.subtitle:SetTextColor(
        ColorComponent(subtitleColor, 1, 1),
        ColorComponent(subtitleColor, 2, 1),
        ColorComponent(subtitleColor, 3, 1),
        ColorComponent(subtitleColor, 4, 1) * subtitleReveal
    )

    local nodeCount = math.max(1, math.min(5, math.floor(tonumber(self.nodeCount) or 1)))
    local nodeSpacing = math.min(22, width * 0.045)
    for index, node in ipairs(frame.nodes) do
        if index <= nodeCount then
            local delay = 0.25 + (index - 1) * 0.055
            local nodeReveal = SmoothStep((reveal - delay) / 0.34)
            local pulse = 0.88 + 0.12 * math.sin(elapsed * 1.8 + index * 0.72)
            local nodeAlpha = nodeReveal * (1 - exitProgress) * pulse
            local targetX = (index - (nodeCount + 1) * 0.5) * nodeSpacing
            local x = targetX * (0.72 + 0.28 * nodeReveal)
            local y = bottomY + (1 - nodeReveal) * 7 - exitProgress * 3
            local size = 6 + nodeReveal * 2
            SetCenteredRect(node, size, size, frame.art, x, y, math.rad(45))
            SetSolidColor(node, index % 2 == 0 and lineColor or accentColor, nodeAlpha)
            node:Show()
        else
            node:Hide()
        end
    end

    local shimmerCycle = (elapsed * 0.24) % 1
    local shimmerAlpha = math.sin(math.pi * shimmerCycle) * shapeReveal * (1 - exitProgress) * 0.34
    local shimmerX = -width * 0.32 + width * 0.64 * shimmerCycle
    SetCenteredRect(frame.shimmer, math.max(24, width * 0.09), 2, frame.art, shimmerX, topY)
    SetGradientColor(frame.shimmer, glowColor, 0, glowColor, 1, shimmerAlpha)
end

function CalmVisual:OnUpdate(elapsed)
    local state = self.state
    if not state then return end

    elapsed = tonumber(elapsed) or 0
    state.elapsed = state.elapsed + math.max(0, elapsed)

    if state.closing then
        local progress = Clamp01(state.elapsed / state.duration)
        local exitProgress = SmoothStep(progress)
        self:Render(1, exitProgress, 1 - exitProgress, state.elapsed)
        if progress >= 1 then
            self.state = nil
            self.frame:Hide()
        end
        return
    end

    local duration = state.duration
    if not state.animated then
        self:Render(1, 0, 1, 0)
        if state.elapsed >= duration then
            self.state = nil
            self.frame:Hide()
        end
        return
    end

    local exitDuration = math.min(0.65, math.max(0.32, duration * 0.14))
    local reveal = 1
    local exitProgress = 0
    local visibility = 1

    local enterDuration = math.min(0.78, math.max(0.42, duration * 0.18))
    if state.elapsed < enterDuration then
        reveal = EaseOutCubic(state.elapsed / enterDuration)
        visibility = SmoothStep(state.elapsed / math.min(0.24, enterDuration))
    elseif state.elapsed > duration - exitDuration then
        exitProgress = SmoothStep((state.elapsed - (duration - exitDuration)) / exitDuration)
        visibility = 1 - exitProgress
    end

    self:Render(reveal, exitProgress, visibility, state.elapsed)
    if state.elapsed >= duration then
        self.state = nil
        self.frame:Hide()
    end
end

function CalmVisual:Apply(settings, position)
    self.settings = type(settings) == "table" and settings or {}
    local frame = self.frame
    local width = Clamp(self.settings.width, 320, 760)
    local height = Clamp(self.settings.height, 80, 170)
    local fontSize = Clamp(self.settings.fontSize, 14, 48)
    local outline = self.settings.fontOutline or "OUTLINE"
    local font = self.settings.font or DEFAULT_FONT

    frame:SetSize(width, height)
    frame:SetScale(Clamp(self.settings.alertScale or self.settings.scale, 0.5, 2))
    frame:SetFrameStrata(self.settings.frameStrata or "FULLSCREEN_DIALOG")
    frame.title:SetWidth(math.max(1, width - 48))
    frame.title:SetHeight(math.max(1, height * 0.32))
    frame.subtitle:SetWidth(math.max(1, width - 64))
    frame.subtitle:SetHeight(math.max(1, height * 0.24))

    local fontFlags = outline == "NONE" and "" or outline
    local titleOK, titleResult = pcall(frame.title.SetFont, frame.title, font, fontSize, fontFlags)
    local subtitleOK, subtitleResult = pcall(frame.subtitle.SetFont, frame.subtitle, font, math.max(11, math.floor(fontSize * 0.56 + 0.5)), fontFlags)
    if not titleOK or titleResult == false then
        frame.title:SetFont(DEFAULT_FONT, fontSize, fontFlags)
    end
    if not subtitleOK or subtitleResult == false then
        frame.subtitle:SetFont(DEFAULT_FONT, math.max(11, math.floor(fontSize * 0.56 + 0.5)), fontFlags)
    end

    position = type(position) == "table" and position or self.settings.position or {}
    frame:ClearAllPoints()
    frame:SetPoint(
        position.point or "TOP",
        UIParent,
        position.relativePoint or position.point or "TOP",
        tonumber(position.x) or 0,
        tonumber(position.y) or -100
    )

    if frame:IsShown() then
        if self.state then
            self:OnUpdate(0)
        else
            self:Render(1, 0, 1, 0)
        end
    end
end

function CalmVisual:Show(title, subtitle, options)
    options = type(options) == "table" and options or {}
    self.frame.title:SetText(type(title) == "string" and title or "")
    self.frame.subtitle:SetText(type(subtitle) == "string" and subtitle or "")
    self.nodeCount = math.max(1, math.min(5, math.floor(tonumber(options.nodeCount) or 1)))
    self.frame:Show()

    if options.persistent then
        self.state = nil
        self:Render(1, 0, 1, 0)
        return
    end

    self.state = {
        elapsed = 0,
        duration = Clamp(options.duration, 1, 15),
        animated = options.animated ~= false,
    }
    self:Render(self.state.animated and 0 or 1, 0, self.state.animated and 0 or 1, 0)
end

function CalmVisual:Hide(immediate)
    if not self.frame:IsShown() then return end
    if immediate then
        self.state = nil
        self.frame:Hide()
        self.frame.art:SetAlpha(1)
        self.frame.art:SetScale(1)
        return
    end

    self.state = {
        elapsed = 0,
        duration = 0.45,
        closing = true,
    }
end

function ns.CreateCalmPartyAlert(frameName)
    local visual = setmetatable({}, CalmVisual)
    local frame = CreateFrame("Frame", frameName, UIParent)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()

    frame.art = CreateFrame("Frame", nil, frame)
    frame.art:SetAllPoints(frame)
    frame.glowLeft = CreateFlatTexture(frame.art, "BACKGROUND", -3)
    frame.glowRight = CreateFlatTexture(frame.art, "BACKGROUND", -3)
    frame.panelLeft = CreateFlatTexture(frame.art, "BACKGROUND", -2)
    frame.panelRight = CreateFlatTexture(frame.art, "BACKGROUND", -2)
    frame.topLeft = CreateFlatTexture(frame.art, "ARTWORK", -1)
    frame.topRight = CreateFlatTexture(frame.art, "ARTWORK", -1)
    frame.bottomLeft = CreateFlatTexture(frame.art, "ARTWORK", -1)
    frame.bottomRight = CreateFlatTexture(frame.art, "ARTWORK", -1)
    frame.diamondTopLeft = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.diamondTopRight = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.diamondBottomLeft = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.diamondBottomRight = CreateFlatTexture(frame.art, "ARTWORK", 1)
    frame.shimmer = CreateFlatTexture(frame.art, "ARTWORK", 2)
    frame.nodes = {}
    for index = 1, 5 do
        frame.nodes[index] = CreateFlatTexture(frame.art, "ARTWORK", 1)
    end

    frame.title = frame.art:CreateFontString(nil, "OVERLAY")
    frame.title:SetJustifyH("CENTER")
    frame.title:SetJustifyV("MIDDLE")
    frame.title:SetWordWrap(false)
    frame.subtitle = frame.art:CreateFontString(nil, "OVERLAY")
    frame.subtitle:SetJustifyH("CENTER")
    frame.subtitle:SetJustifyV("MIDDLE")
    frame.subtitle:SetWordWrap(false)

    visual.frame = frame
    frame:SetScript("OnUpdate", function(_, elapsed)
        visual:OnUpdate(elapsed)
    end)
    return visual
end
