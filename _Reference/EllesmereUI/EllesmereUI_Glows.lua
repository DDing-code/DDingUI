-------------------------------------------------------------------------------
--  EllesmereUI_Glows.lua
--  Shared glow rendering engine for the EllesmereUI addon suite.
--  Provides: Pixel Glow (procedural ants), Action Button Glow, Auto-Cast
--  Shine, Shape Glow, and FlipBook-based glows (GCD, Modern WoW, Classic WoW).
--  Each addon attaches to EllesmereUI.Glows.* instead of duplicating engines.
-------------------------------------------------------------------------------
if not EllesmereUI then return end
if EllesmereUI.Glows then return end  -- already loaded by another addon

local floor = math.floor
local min   = math.min
local ceil  = math.ceil
local sin   = math.sin

-------------------------------------------------------------------------------
--  Style Definitions (superset of all addons)
--  Each addon picks from this table by index or iterates for its dropdown.
--  Fields: name, procedural, buttonGlow, autocast, shapeGlow, atlas, texture,
--          rows, columns, frames, duration, frameW, frameH, scale, previewScale
-------------------------------------------------------------------------------
local GLOW_STYLES = {
    { name = "Pixel Glow",         procedural = true },
    { name = "Action Button Glow", buttonGlow = true, scale = 1.36, previewScale = 1.28 },
    { name = "Auto-Cast Shine",    autocast   = true },
    { name = "Shape Glow",         shapeGlow  = true, scale = 1.20, previewScale = 1.20 },
    { name = "GCD",
      atlas = "RotationHelper_Ants_Flipbook", scale = 1.12, previewScale = 1.47 },
    { name = "Modern WoW Glow",
      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", scale = 1.02, previewScale = 1.34 },
    { name = "Classic WoW Glow",
      texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3,
      frameW = 48, frameH = 48, scale = 1.09, previewScale = 1.47 },
}

-------------------------------------------------------------------------------
--  Texture constants
-------------------------------------------------------------------------------
local ANTS_TEX      = [[Interface\SpellActivationOverlay\IconAlertAnts]]
local ICON_ALERT_TEX = [[Interface\SpellActivationOverlay\IconAlert]]
local BG_GLOW_L, BG_GLOW_R = 0.00781250, 0.50781250
local BG_GLOW_T, BG_GLOW_B = 0.27734375, 0.52734375
local SHINE_TEX    = [[Interface\Artifacts\Artifacts]]
local SHINE_COORDS = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }
local SHINE_SIZES  = { 7, 6, 5, 4 }

-------------------------------------------------------------------------------
--  Procedural Ants Engine
--  N small rectangles orbit the perimeter of a frame each OnUpdate.
--  Each ant uses 2 textures: primary + overflow for corner wrapping.
-------------------------------------------------------------------------------
local function _EdgeAndOffset(dist, w, h)
    if dist < w then return 0, dist end
    dist = dist - w
    if dist < h then return 1, dist end
    dist = dist - h
    if dist < w then return 2, dist end
    return 3, dist - w
end

local function _PlaceOnEdge(tex, parent, edge, startOff, endOff, w, h, th)
    local len = endOff - startOff
    if len < 0.5 then tex:Hide(); return end
    len = floor(len + 0.5)
    tex:ClearAllPoints()
    if edge == 0 then
        tex:SetSize(len, th); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", floor(startOff + 0.5), 0)
    elseif edge == 1 then
        tex:SetSize(th, len); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", w - th, -floor(startOff + 0.5))
    elseif edge == 2 then
        tex:SetSize(len, th); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", floor(w - endOff + 0.5), -(h - th))
    else
        tex:SetSize(th, len); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -floor(h - endOff + 0.5))
    end
    tex:Show()
end

local function _EdgeLen(edge, w, h)
    return (edge == 0 or edge == 2) and w or h
end

local function _AntsOnUpdate(self, elapsed)
    local d = self._euiAntsData
    if not d then return end
    d.timer = d.timer + elapsed
    if d.timer >= d.period then d.timer = d.timer - d.period end
    d._accum = (d._accum or 0) + elapsed
    if d._accum < 0.033 then return end
    d._accum = 0
    local w, h = d.w, d.h
    if w * h == 0 then
        w, h = self:GetSize()
        if w * h == 0 then return end
        d.w = w; d.h = h
    end
    local perim = 2 * (w + h)
    if perim <= 0 then return end
    local progress = d.timer / d.period
    local step = 1 / d.N
    for i = 1, d.N do
        local headDist = ((progress + (i - 1) * step) % 1) * perim
        local tailDist = headDist - d.lineLen
        if tailDist < 0 then tailDist = tailDist + perim end
        local headEdge, headOff = _EdgeAndOffset(headDist, w, h)
        local tailEdge, tailOff = _EdgeAndOffset(tailDist, w, h)
        local primary  = d.lines[i]
        local overflow = d.lines[i + d.N]
        if headEdge == tailEdge then
            _PlaceOnEdge(primary, self, headEdge, tailOff, headOff, w, h, d.th)
            overflow:Hide()
        else
            _PlaceOnEdge(primary,  self, headEdge, 0,       headOff,                      w, h, d.th)
            _PlaceOnEdge(overflow, self, tailEdge, tailOff, _EdgeLen(tailEdge, w, h), w, h, d.th)
        end
    end
end

local function StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, sz)
    if not wrapper._euiAntsData then
        wrapper._euiAntsData = { lines = {}, N = 0, timer = 0, w = 0, h = 0 }
    end
    local d = wrapper._euiAntsData
    d.N = N; d.th = th; d.period = period; d.lineLen = lineLen
    d.w = sz or 0; d.h = sz or 0
    local totalTex = N * 2
    for i = 1, totalTex do
        if not d.lines[i] then
            local tex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(1, 1, 1, 1)
            d.lines[i] = tex
        end
        d.lines[i]:SetVertexColor(cr, cg, cb, 1)
        d.lines[i]:Show()
    end
    for i = totalTex + 1, #d.lines do d.lines[i]:Hide() end
    wrapper:SetScript("OnUpdate", _AntsOnUpdate)
end

local function StopProceduralAnts(wrapper)
    wrapper:SetScript("OnUpdate", nil)
    if wrapper._euiAntsData then
        for _, tex in ipairs(wrapper._euiAntsData.lines) do tex:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Action Button Glow Engine
--  Outer glow (soft border from IconAlert) + animated marching ants.
-------------------------------------------------------------------------------
local function _ButtonGlowOnUpdate(self, elapsed)
    local d = self._euiBgData
    if not d then return end
    AnimateTexCoords(d.ants, 256, 256, 48, 48, 22, elapsed, 0.01)
end

local function StartButtonGlow(wrapper, sz, cr, cg, cb, scale)
    scale = scale or 1.0
    if not wrapper._euiBgData then
        local glow = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        glow:SetTexture(ICON_ALERT_TEX)
        glow:SetTexCoord(BG_GLOW_L, BG_GLOW_R, BG_GLOW_T, BG_GLOW_B)
        glow:SetBlendMode("ADD")
        glow:SetPoint("CENTER")
        local ants = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        ants:SetTexture(ANTS_TEX)
        ants:SetBlendMode("ADD")
        ants:SetPoint("CENTER")
        wrapper._euiBgData = { glow = glow, ants = ants }
    end
    local d = wrapper._euiBgData
    local frameSz = sz * scale
    local glowSz  = frameSz * 1.3
    local antsSz   = frameSz * 1.0
    d.glow:SetSize(glowSz, glowSz)
    d.glow:SetDesaturated(true); d.glow:SetVertexColor(cr, cg, cb, 1)
    d.glow:SetAlpha(1); d.glow:Show()
    d.ants:SetSize(antsSz, antsSz)
    d.ants:SetDesaturated(true); d.ants:SetVertexColor(cr, cg, cb, 1)
    d.ants:SetAlpha(1); d.ants:Show()
    wrapper:SetScript("OnUpdate", _ButtonGlowOnUpdate)
end

local function StopButtonGlow(wrapper)
    wrapper:SetScript("OnUpdate", nil)
    if wrapper._euiBgData then
        wrapper._euiBgData.ants:Hide()
        wrapper._euiBgData.glow:Hide()
    end
end

-------------------------------------------------------------------------------
--  Auto-Cast Shine Engine
--  4 layers of N sparkle dots orbit the perimeter at different speeds.
-------------------------------------------------------------------------------
local function _AutoCastOnUpdate(self, elapsed)
    local d = self._euiAcData
    if not d then return end
    for k = 1, 4 do
        d.timers[k] = d.timers[k] + elapsed / (d.period * k)
        if d.timers[k] > 1 then d.timers[k] = d.timers[k] - 1 end
    end
    d._accum = (d._accum or 0) + elapsed
    if d._accum < 0.033 then return end
    d._accum = 0
    local w, h = d.w, d.h
    if w * h == 0 then
        w, h = self:GetSize()
        if w * h == 0 then return end
        d.w = w; d.h = h
        d.perim = 2 * (w + h)
        d.rightLim = h + w
        d.bottomLim = h * 2 + w
        d.space = d.perim / d.N
    end
    local texIdx = 0
    for k = 1, 4 do
        for i = 1, d.N do
            texIdx = texIdx + 1
            local pos = (d.space * i + d.perim * d.timers[k]) % d.perim
            local dot = d.dots[texIdx]
            dot:ClearAllPoints()
            if pos > d.bottomLim then
                dot:SetPoint("CENTER", self, "BOTTOMRIGHT", -(pos - d.bottomLim), 0)
            elseif pos > d.rightLim then
                dot:SetPoint("CENTER", self, "TOPRIGHT", 0, -(pos - d.rightLim))
            elseif pos > h then
                dot:SetPoint("CENTER", self, "TOPLEFT", pos - h, 0)
            else
                dot:SetPoint("CENTER", self, "BOTTOMLEFT", 0, pos)
            end
        end
    end
end

local function StartAutoCastShine(wrapper, sz, cr, cg, cb, scale)
    scale = scale or 1.0
    local N = 4
    local totalDots = N * 4
    if not wrapper._euiAcData then
        wrapper._euiAcData = { dots = {}, timers = { 0, 0.25, 0.5, 0.75 }, N = N, period = 2, w = 0, h = 0 }
    end
    local d = wrapper._euiAcData
    d.N = N
    d.timers[1] = 0; d.timers[2] = 0.25; d.timers[3] = 0.5; d.timers[4] = 0.75
    for idx = 1, totalDots do
        if not d.dots[idx] then
            local dot = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            dot:SetTexture(SHINE_TEX)
            dot:SetTexCoord(SHINE_COORDS[1], SHINE_COORDS[2], SHINE_COORDS[3], SHINE_COORDS[4])
            dot:SetDesaturated(true); dot:SetBlendMode("ADD")
            d.dots[idx] = dot
        end
        local layer = ceil(idx / N)
        local baseSz = (SHINE_SIZES[layer] or 4) * scale
        d.dots[idx]:SetSize(baseSz, baseSz)
        d.dots[idx]:SetVertexColor(cr, cg, cb, 1)
        d.dots[idx]:Show()
    end
    for idx = totalDots + 1, #d.dots do d.dots[idx]:Hide() end
    d.w = 0; d.h = 0
    wrapper:SetScript("OnUpdate", _AutoCastOnUpdate)
end

local function StopAutoCastShine(wrapper)
    wrapper:SetScript("OnUpdate", nil)
    if wrapper._euiAcData then
        for _, dot in ipairs(wrapper._euiAcData.dots) do dot:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Shape Glow Engine
--  Pulsing additive glow using the icon's shape mask texture.
--  Used by ActionBars (custom shapes) and CDM (custom icon shapes).
--  opts.maskPath   — path to the shape mask texture
--  opts.borderPath — path to the shape border texture
--  opts.shapeMask  — MaskTexture object for AddMaskTexture
-------------------------------------------------------------------------------
local function _ShapeGlowOnUpdate(self, elapsed)
    local d = self._euiSgData
    if not d then return end
    d.timer = d.timer + elapsed * d.speed
    if d.timer > 6.2832 then d.timer = d.timer - 6.2832 end
    local alpha = 0.25 + 0.25 * (0.5 + 0.5 * sin(d.timer))
    d.glow:SetAlpha(alpha)
    if d.bright then
        d.bTimer = (d.bTimer or 0) + elapsed * d.speed * 0.50
        if d.bTimer > 6.2832 then d.bTimer = d.bTimer - 6.2832 end
        local bAlpha = 0.35 + 0.10 * (0.5 + 0.5 * sin(d.bTimer))
        d.bright:SetAlpha(bAlpha)
    end
end

local function StartShapeGlow(wrapper, sz, cr, cg, cb, scale, opts)
    scale = scale or 1.20
    opts = opts or {}
    local btn = wrapper:GetParent()
    if not btn then return end
    if not wrapper._euiSgData then
        local glow   = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        glow:SetBlendMode("ADD")
        local edge   = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        edge:SetBlendMode("ADD")
        local bright = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        bright:SetBlendMode("ADD")
        wrapper._euiSgData = { glow = glow, edge = edge, bright = bright, timer = 0, speed = 10.0 }
    end
    local d = wrapper._euiSgData
    d.timer = 0

    local glowSz = sz * scale
    local offset  = (glowSz - sz) / 2
    d.glow:ClearAllPoints()
    d.glow:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -offset,  offset)
    d.glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  offset, -offset)
    local maskPath   = opts.maskPath
    local borderPath = opts.borderPath
    if maskPath then
        d.glow:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    else
        d.glow:SetColorTexture(1, 1, 1, 1)
    end
    d.glow:SetVertexColor(cr, cg, cb, 1)
    d.glow:SetAlpha(1); d.glow:Show()

    -- Edge glow
    d.edge:ClearAllPoints()
    local inset = 4
    d.edge:SetPoint("TOPLEFT",     btn, "TOPLEFT",      inset, -inset)
    d.edge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  -inset,  inset)
    if borderPath then
        d.edge:SetTexture(borderPath)
    elseif maskPath then
        d.edge:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    else
        d.edge:SetColorTexture(1, 1, 1, 1)
    end
    d.edge:SetBlendMode("ADD")
    d.edge:SetVertexColor(cr, cg, cb, 1)
    d.edge:SetAlpha(0.85); d.edge:Show()

    -- Bright border overlay
    d.bright:ClearAllPoints(); d.bright:SetAllPoints(btn)
    if borderPath then
        d.bright:SetTexture(borderPath)
    else
        d.bright:SetColorTexture(0, 0, 0, 0)
    end
    d.bright:SetVertexColor(cr, cg, cb, 1)
    d.bright:SetAlpha(0.5); d.bright:Show()

    -- Mask the pulsing glow with the shape mask texture
    local shapeMask = opts.shapeMask
    if shapeMask then
        pcall(d.glow.RemoveMaskTexture, d.glow, shapeMask)
        pcall(d.glow.AddMaskTexture, d.glow, shapeMask)
    end
    wrapper:SetScript("OnUpdate", _ShapeGlowOnUpdate)
end

local function StopShapeGlow(wrapper)
    wrapper:SetScript("OnUpdate", nil)
    if wrapper._euiSgData then
        wrapper._euiSgData.glow:Hide()
        wrapper._euiSgData.edge:Hide()
        wrapper._euiSgData.bright:Hide()
    end
end

-------------------------------------------------------------------------------
--  FlipBook Glow Engine
--  Handles atlas-based and raw-texture FlipBook animations (GCD, Modern WoW
--  Glow, Classic WoW Glow, and any future FlipBook styles).
-------------------------------------------------------------------------------
local function StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb)
    local glowScale = entry.scale or 1
    local texSz = sz * glowScale

    if not wrapper._euiFlipData then
        local tex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetPoint("CENTER")
        local ag = tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local anim = ag:CreateAnimation("FlipBook")
        wrapper._euiFlipData = { tex = tex, ag = ag, anim = anim }
    end
    local d = wrapper._euiFlipData
    d.tex:SetSize(texSz, texSz)
    if entry.atlas then
        d.tex:SetAtlas(entry.atlas)
    elseif entry.texture then
        d.tex:SetTexture(entry.texture)
    end
    d.tex:SetDesaturated(true)
    d.tex:SetVertexColor(cr, cg, cb)
    d.tex:Show()
    d.anim:SetFlipBookRows(entry.rows or 6)
    d.anim:SetFlipBookColumns(entry.columns or 5)
    d.anim:SetFlipBookFrames(entry.frames or 30)
    d.anim:SetDuration(entry.duration or 1.0)
    d.anim:SetFlipBookFrameWidth(entry.frameW or 0)
    d.anim:SetFlipBookFrameHeight(entry.frameH or 0)
    if d.ag:IsPlaying() then d.ag:Stop() end
    d.ag:Play()
    wrapper:SetScript("OnUpdate", nil)
end

local function StopFlipBookGlow(wrapper)
    if wrapper._euiFlipData then
        wrapper._euiFlipData.tex:Hide()
        if wrapper._euiFlipData.ag then wrapper._euiFlipData.ag:Stop() end
    end
end

-------------------------------------------------------------------------------
--  StopAllGlows — clears any active glow engine on a wrapper frame
-------------------------------------------------------------------------------
local function StopAllGlows(wrapper)
    if not wrapper then return end
    StopProceduralAnts(wrapper)
    StopButtonGlow(wrapper)
    StopAutoCastShine(wrapper)
    StopShapeGlow(wrapper)
    StopFlipBookGlow(wrapper)
    wrapper:SetScript("OnUpdate", nil)
end

-------------------------------------------------------------------------------
--  StartGlow — unified entry point
--  wrapper  : Frame to render the glow on
--  styleIdx : index into GLOW_STYLES (1-based)
--  sz       : icon/frame size in pixels
--  cr,cg,cb : glow color (0-1)
--  opts     : optional table with overrides:
--    .scale       — override entry.scale
--    .N, .th, .period — pixel glow tuning
--    .maskPath, .borderPath, .shapeMask — shape glow textures
-------------------------------------------------------------------------------
local function StartGlow(wrapper, styleIdx, sz, cr, cg, cb, opts)
    if not wrapper then return end
    styleIdx = tonumber(styleIdx) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then styleIdx = 1 end
    local entry = GLOW_STYLES[styleIdx]
    opts = opts or {}
    sz = sz or 36
    cr = cr or 1; cg = cg or 1; cb = cb or 1

    -- Stop any previous glow
    StopAllGlows(wrapper)

    if entry.procedural then
        local N       = opts.N or 8
        local th      = opts.th or 2
        local period  = opts.period or 4
        local lineLen = floor((sz + sz) * (2 / N - 0.1))
        lineLen = min(lineLen, sz)
        if lineLen < 1 then lineLen = 1 end
        StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, sz)

    elseif entry.buttonGlow then
        local scale = opts.scale or entry.scale or 1.36
        StartButtonGlow(wrapper, sz, cr, cg, cb, scale)

    elseif entry.autocast then
        StartAutoCastShine(wrapper, sz, cr, cg, cb, opts.scale or 1.0)

    elseif entry.shapeGlow then
        local scale = opts.scale or entry.scale or 1.20
        StartShapeGlow(wrapper, sz, cr, cg, cb, scale, opts)

    else
        -- FlipBook mode (GCD, Modern WoW Glow, Classic WoW Glow, etc.)
        StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb)
    end

    wrapper._euiGlowActive = true
    wrapper:SetAlpha(1)
    wrapper:Show()
end

local function StopGlow(wrapper)
    if not wrapper then return end
    StopAllGlows(wrapper)
    wrapper._euiGlowActive = false
    wrapper:SetAlpha(0)
end

-------------------------------------------------------------------------------
--  Public API — attached to EllesmereUI.Glows
-------------------------------------------------------------------------------
EllesmereUI.Glows = {
    STYLES              = GLOW_STYLES,

    -- High-level API (recommended)
    StartGlow           = StartGlow,
    StopGlow            = StopGlow,

    -- Low-level engines (for addons that need direct control)
    StartProceduralAnts = StartProceduralAnts,
    StopProceduralAnts  = StopProceduralAnts,
    StartButtonGlow     = StartButtonGlow,
    StopButtonGlow      = StopButtonGlow,
    StartAutoCastShine  = StartAutoCastShine,
    StopAutoCastShine   = StopAutoCastShine,
    StartShapeGlow      = StartShapeGlow,
    StopShapeGlow       = StopShapeGlow,
    StartFlipBookGlow   = StartFlipBookGlow,
    StopFlipBookGlow    = StopFlipBookGlow,
    StopAllGlows        = StopAllGlows,
}
