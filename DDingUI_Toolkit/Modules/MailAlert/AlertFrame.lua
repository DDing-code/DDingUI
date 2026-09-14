-- Mail seal art, using the shared alert's frame pool and playback lifecycle.
local _, ns = ...
local MailAlert = ns.MailAlert
local Style = ns.CalmAlertStyle
local ICONS = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\MailAlertIcons.tga"
local LINE = {0.573, 0.784, 0.722, 1}
local DETAIL = {0.835, 0.765, 0.604, 1}
local TITLE = {0.933, 0.961, 0.933, 1}
local SUBTITLE = {0.710, 0.780, 0.749, 1}
local PANEL = {0.063, 0.098, 0.082, 1}
local SEAL_BG = {0.090, 0.122, 0.106, 1}
local WIDTH, HEIGHT = 560, 166

local function Tint(texture, color, alpha)
    texture:SetVertexColor(color[1], color[2], color[3], color[4])
    texture:SetAlpha(alpha)
end

local function RenderSeal(self, reveal, exitProgress, visibility, elapsed)
    local frame = self.frame
    local animated = self.motionEnabled ~= false
    -- Keep the approved 0.68s entrance / 0.75s exit, also at short display durations.
    if self.state and not self.state.closing and animated then
        local enter = math.min(0.68, self.state.duration * 0.4)
        local leave = math.min(0.75, self.state.duration * 0.4)
        reveal = Style.EaseOutCubic(elapsed / enter)
        exitProgress = Style.SmoothStep((elapsed - self.state.duration + leave) / leave)
        visibility = Style.SmoothStep(elapsed / math.min(0.22, enter)) * (1 - exitProgress)
    elseif self.state and self.state.closing then
        elapsed = 1.2
    end
    frame.art:SetAlpha(visibility)
    frame.art:SetScale(1)
    local rect, solid, gradient = Style.SetCenteredRect, Style.SetSolidColor, Style.SetGradientColor
    local panelWidth = WIDTH * (0.25 + 0.75 * reveal)
    rect(frame.panelLeft, panelWidth * 0.22, 107, frame.art, -panelWidth * 0.37, -9.5)
    rect(frame.panelRight, panelWidth * 0.22, 107, frame.art, panelWidth * 0.37, -9.5)
    rect(frame.haloLeft, panelWidth * 0.52, 107, frame.art, 0, -9.5)
    gradient(frame.panelLeft, PANEL, 0, PANEL, 1, 1)
    gradient(frame.panelRight, PANEL, 1, PANEL, 0, 1)
    solid(frame.haloLeft, PANEL, 1)

    local railWidth = (WIDTH * 0.45 - 26) * reveal * (1 - exitProgress * 0.2)
    rect(frame.topLeft, railWidth, 1, frame.art, -32 - railWidth / 2, 51)
    rect(frame.topRight, railWidth, 1, frame.art, 32 + railWidth / 2, 51)
    gradient(frame.topLeft, LINE, 0, LINE, 1, 1)
    gradient(frame.topRight, LINE, 1, LINE, 0, 1)
    rect(frame.glowLeft, WIDTH * 0.43, 1, frame.art, -WIDTH * 0.215, 40)
    rect(frame.glowRight, WIDTH * 0.43, 1, frame.art, WIDTH * 0.215, 40)
    gradient(frame.glowLeft, LINE, 0, LINE, 1, 0.28)
    gradient(frame.glowRight, LINE, 1, LINE, 0, 0.28)

    local sealAlpha = animated and Style.SmoothStep((elapsed - 0.03) / 0.36) * (1 - exitProgress) or 1
    local sealY = 51 - (animated and (1 - reveal) * 7 or 0)
    rect(frame.haloRight, 38, 38, frame.art, 0, sealY, math.rad(45))
    solid(frame.haloRight, SEAL_BG, sealAlpha)
    rect(frame.mailSeal, 80, 80, frame.art, 0, sealY)
    rect(frame.mailIcon, 26, 26, frame.art, 0, sealY)
    Tint(frame.mailSeal, LINE, sealAlpha)
    Tint(frame.mailIcon, TITLE, sealAlpha)

    local copyAlpha = animated and Style.SmoothStep((elapsed - 0.18) / 0.45) * (1 - exitProgress) or 1
    local offset = animated and -(1 - reveal) * 5 + exitProgress * 3 or 0
    frame.title:ClearAllPoints()
    frame.title:SetPoint("CENTER", frame.art, "CENTER", 0, -6.5 + offset)
    frame.subtitle:ClearAllPoints()
    frame.subtitle:SetPoint("CENTER", frame.art, "CENTER", 0, -45.5 + offset)
    frame.title:SetTextColor(TITLE[1], TITLE[2], TITLE[3], copyAlpha)
    frame.subtitle:SetTextColor(SUBTITLE[1], SUBTITLE[2], SUBTITLE[3], copyAlpha)

    local bottomAlpha = 0.5 * (animated and Style.SmoothStep((elapsed - 0.4) / 0.4) or 1) * (1 - exitProgress)
    rect(frame.bottomLeft, WIDTH * 0.33, 1, frame.art, -WIDTH * 0.165, -69)
    rect(frame.bottomRight, WIDTH * 0.33, 1, frame.art, WIDTH * 0.165, -69)
    gradient(frame.bottomLeft, DETAIL, 0, DETAIL, 1, bottomAlpha)
    gradient(frame.bottomRight, DETAIL, 1, DETAIL, 0, bottomAlpha)
    rect(frame.nodes[3], 5, 5, frame.art, 0, -69, math.rad(45))
    solid(frame.nodes[3], DETAIL, bottomAlpha)
    local endAlpha = 0.7 * (animated and Style.SmoothStep((elapsed - 0.3) / 0.4) or 1) * (1 - exitProgress)
    for index = 1, 2 do
        rect(frame.nodes[index], 9, 9, frame.art, (index == 1 and -1 or 1) * (WIDTH * 0.45 - 3), 51)
        Tint(frame.nodes[index], DETAIL, endAlpha)
    end
    local phase = Style.Clamp01((elapsed - 0.3) / 0.9)
    rect(frame.shimmer, 22.5, 2, frame.art, WIDTH * (-0.4 + 0.78 * phase) + 11.25, 51)
    rect(frame.shimmerRight, 22.5, 2, frame.art, WIDTH * (-0.4 + 0.78 * phase) + 33.75, 51)
    local sweepAlpha = animated and math.sin(phase * math.pi) * 0.55 or 0
    gradient(frame.shimmer, TITLE, 0, TITLE, 1, sweepAlpha)
    gradient(frame.shimmerRight, TITLE, 1, TITLE, 0, sweepAlpha)
end

function MailAlert:CreateSealVisual()
    if self.sealVisual then return self.sealVisual end
    local visual = ns.CreateCalmPartyAlert("DDingToolKit_MailSealFrame")
    local frame = visual.frame
    for _, key in ipairs({"diamondTopLeft", "diamondTopRight", "diamondBottomLeft", "diamondBottomRight"}) do
        frame[key]:Hide()
    end
    frame.nodes[4]:Hide()
    frame.nodes[5]:Hide()
    frame.mailSeal = frame.art:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.mailIcon = frame.art:CreateTexture(nil, "ARTWORK", nil, 2)
    for _, texture in ipairs({frame.mailSeal, frame.nodes[1], frame.nodes[2], frame.mailIcon}) do
        texture:SetTexture(ICONS)
        texture:SetTexCoord(texture == frame.mailIcon and 0.5 or 0, texture == frame.mailIcon and 1 or 0.5, 0, 1)
    end
    frame.title:SetShadowOffset(0, -1)
    frame.title:SetShadowColor(0, 0, 0, 1)
    frame.subtitle:SetShadowOffset(0, -1)
    frame.subtitle:SetShadowColor(0, 0, 0, 1)
    visual.Render = RenderSeal
    visual:Apply({width = WIDTH, height = HEIGHT, fontSize = 29, fontOutline = "NONE", frameStrata = "HIGH"})
    local font = frame.subtitle:GetFont()
    frame.subtitle:SetFont(font, 14, "")
    self.sealVisual = visual
    return visual
end
