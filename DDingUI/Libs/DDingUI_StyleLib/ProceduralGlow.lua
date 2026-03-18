------------------------------------------------------
-- DDingUI_StyleLib :: ProceduralGlow
-- Mathematical glow engine (EllesmereUI Procedural Ants + Shape Glow)
-- Taint-free: uses OnUpdate + trigonometry instead of AnimationGroup
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local sin, cos, abs, floor, max, min = math.sin, math.cos, math.abs, math.floor, math.max, math.min
local PI2 = 6.2831853  -- 2π

-- ============================================
-- ProceduralGlow Module
-- ============================================
local PG = {}
Lib.ProceduralGlow = PG

-- Flat white texture for all solid colors
local FLAT = [[Interface\Buttons\WHITE8x8]]

-- Reusable glow data pool (prevent frame creation spam)
local _glowPool = {}

------------------------------------------------------
-- 1. SHAPE GLOW — 부드러운 펄스 글로우
------------------------------------------------------
-- Creates a pulsing glow effect around a frame using sine wave alpha modulation.
-- Taint-free: pure OnUpdate + math.sin

--- Start a pulsing shape glow on a frame.
--- @param frame Frame  target frame to glow
--- @param r number  red 0-1
--- @param g number  green 0-1
--- @param b number  blue 0-1
--- @param opts table|nil  { size=4, speed=3, minAlpha=0.2, maxAlpha=0.6, key="default" }
function PG.StartShapeGlow(frame, r, g, b, opts)
    opts = opts or {}
    local key = opts.key or "default"
    local glowKey = "_pgShapeGlow_" .. key

    -- Stop existing glow with same key
    PG.StopShapeGlow(frame, key)

    local size   = opts.size or 4
    local speed  = opts.speed or 3.0
    local minA   = opts.minAlpha or 0.15
    local maxA   = opts.maxAlpha or 0.55

    -- Create glow frame
    local glow = CreateFrame("Frame", nil, frame)
    glow:SetFrameLevel(max(1, frame:GetFrameLevel() - 1))
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -size, size)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size, -size)

    -- Glow texture
    local tex = glow:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(r, g, b, minA)
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end

    -- Animation state
    local d = { timer = 0, speed = speed, minA = minA, maxA = maxA, tex = tex }

    -- OnUpdate: sine wave alpha modulation (~30fps limited)
    local accum = 0
    glow:SetScript("OnUpdate", function(self, elapsed)
        accum = accum + elapsed
        if accum < 0.033 then return end  -- ~30fps
        d.timer = (d.timer + accum * d.speed) % PI2
        local alpha = d.minA + (d.maxA - d.minA) * (0.5 + 0.5 * sin(d.timer))
        d.tex:SetAlpha(alpha)
        accum = 0
    end)

    frame[glowKey] = glow
end

--- Stop a pulsing shape glow.
--- @param frame Frame
--- @param key string|nil  glow key (default: "default")
function PG.StopShapeGlow(frame, key)
    key = key or "default"
    local glowKey = "_pgShapeGlow_" .. key
    if frame[glowKey] then
        frame[glowKey]:SetScript("OnUpdate", nil)
        frame[glowKey]:Hide()
        frame[glowKey]:SetParent(nil)
        frame[glowKey] = nil
    end
end

------------------------------------------------------
-- 2. PULSE STRIPE — 선택 항목 좌측 스트라이프 펄스
------------------------------------------------------
-- Adds a gentle pulsing effect to a selection stripe (left accent bar).

--- Start pulse on a stripe texture.
--- @param stripe Texture  the stripe texture (2px left bar)
--- @param speed number|nil  pulse speed (default: 2.5)
--- @param minAlpha number|nil  (default: 0.5)
--- @param maxAlpha number|nil  (default: 1.0)
function PG.StartStripePulse(stripe, speed, minAlpha, maxAlpha)
    if not stripe then return end
    PG.StopStripePulse(stripe)

    speed = speed or 2.5
    minAlpha = minAlpha or 0.5
    maxAlpha = maxAlpha or 1.0

    local d = { timer = 0 }
    local parent = stripe:GetParent()
    if not parent then return end

    -- Use parent's OnUpdate to drive the pulse
    local origOnUpdate = parent:GetScript("OnUpdate")
    parent._pgStripePulse = true

    parent:SetScript("OnUpdate", function(self, elapsed)
        if origOnUpdate then origOnUpdate(self, elapsed) end
        if not parent._pgStripePulse then return end
        d.timer = (d.timer + elapsed * speed) % PI2
        local alpha = minAlpha + (maxAlpha - minAlpha) * (0.5 + 0.5 * sin(d.timer))
        stripe:SetAlpha(alpha)
    end)
end

--- Stop stripe pulse.
--- @param stripe Texture
function PG.StopStripePulse(stripe)
    if not stripe then return end
    stripe:SetAlpha(1.0)
    local parent = stripe:GetParent()
    if parent then
        parent._pgStripePulse = nil
    end
end

------------------------------------------------------
-- 3. PROCEDURAL ANTS — 둘레를 따라 이동하는 개미 효과
------------------------------------------------------
-- N rectangles move clockwise around a frame's perimeter.
-- Each ant uses 2 textures for corner wrapping.

local function _EdgeAndOffset(dist, w, h)
    if dist < w then return 0, dist end        -- top edge (→)
    dist = dist - w
    if dist < h then return 1, dist end        -- right edge (↓)
    dist = dist - h
    if dist < w then return 2, dist end        -- bottom edge (←)
    return 3, dist - w                          -- left edge (↑)
end

local function _EdgeLen(edge, w, h)
    return (edge == 0 or edge == 2) and w or h
end

local function _PlaceOnEdge(tex, parent, edge, startOff, endOff, w, h, thickness)
    tex:ClearAllPoints()
    tex:Show()

    if edge == 0 then       -- top (left→right)
        tex:SetPoint("TOPLEFT", parent, "TOPLEFT", startOff, 0)
        tex:SetSize(max(1, endOff - startOff), thickness)
    elseif edge == 1 then   -- right (top→bottom)
        tex:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -startOff)
        tex:SetSize(thickness, max(1, endOff - startOff))
    elseif edge == 2 then   -- bottom (right→left)
        tex:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(startOff), 0)
        tex:SetSize(max(1, endOff - startOff), thickness)
    elseif edge == 3 then   -- left (bottom→top)
        tex:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, startOff)
        tex:SetSize(thickness, max(1, endOff - startOff))
    end
end

--- Start procedural ants animation around a frame.
--- @param frame Frame  target frame
--- @param r number  red 0-1
--- @param g number  green 0-1
--- @param b number  blue 0-1
--- @param opts table|nil  { N=4, thickness=2, lineLen=8, period=2.0, key="default" }
function PG.StartAnts(frame, r, g, b, opts)
    opts = opts or {}
    local key = opts.key or "default"
    local antsKey = "_pgAnts_" .. key

    PG.StopAnts(frame, key)

    local N         = opts.N or 4
    local thickness = opts.thickness or 2
    local lineLen   = opts.lineLen or 8
    local period    = opts.period or 2.0

    -- Container
    local container = CreateFrame("Frame", nil, frame)
    container:SetAllPoints(frame)
    container:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Create ant textures (2 per ant: primary + overflow for corner wrapping)
    local ants = {}
    for i = 1, N do
        local primary = container:CreateTexture(nil, "OVERLAY", nil, 7)
        primary:SetColorTexture(r, g, b, 0.85)
        if primary.SetSnapToPixelGrid then
            primary:SetSnapToPixelGrid(false)
            primary:SetTexelSnappingBias(0)
        end

        local overflow = container:CreateTexture(nil, "OVERLAY", nil, 7)
        overflow:SetColorTexture(r, g, b, 0.85)
        if overflow.SetSnapToPixelGrid then
            overflow:SetSnapToPixelGrid(false)
            overflow:SetTexelSnappingBias(0)
        end
        overflow:Hide()

        ants[i] = { primary = primary, overflow = overflow }
    end

    -- Animation data
    local d = {
        timer = 0,
        period = period,
        N = N,
        lineLen = lineLen,
        thickness = thickness,
        ants = ants,
    }

    -- OnUpdate (~30fps limited)
    local accum = 0
    container:SetScript("OnUpdate", function(self, elapsed)
        accum = accum + elapsed
        if accum < 0.033 then return end

        d.timer = d.timer + accum
        if d.timer > d.period then d.timer = d.timer - d.period end
        accum = 0

        local w = self:GetWidth()
        local h = self:GetHeight()
        if w < 2 or h < 2 then return end

        local perim = 2 * (w + h)
        local progress = d.timer / d.period

        for i = 1, d.N do
            local headDist = ((progress + (i - 1) / d.N) % 1) * perim
            local tailDist = headDist - d.lineLen
            if tailDist < 0 then tailDist = tailDist + perim end

            local headEdge, headOff = _EdgeAndOffset(headDist, w, h)
            local tailEdge, tailOff = _EdgeAndOffset(tailDist, w, h)

            local ant = d.ants[i]

            if headEdge == tailEdge and headOff >= tailOff then
                -- Same edge, no wrapping
                _PlaceOnEdge(ant.primary, self, headEdge, tailOff, headOff, w, h, d.thickness)
                ant.overflow:Hide()
            else
                -- Corner wrapping: split into 2 segments
                local headLen = _EdgeLen(headEdge, w, h)
                _PlaceOnEdge(ant.primary, self, headEdge, 0, headOff, w, h, d.thickness)
                local tailLen = _EdgeLen(tailEdge, w, h)
                _PlaceOnEdge(ant.overflow, self, tailEdge, tailOff, tailLen, w, h, d.thickness)
                ant.overflow:Show()
            end
        end
    end)

    frame[antsKey] = container
end

--- Stop procedural ants animation.
--- @param frame Frame
--- @param key string|nil  (default: "default")
function PG.StopAnts(frame, key)
    key = key or "default"
    local antsKey = "_pgAnts_" .. key
    if frame[antsKey] then
        frame[antsKey]:SetScript("OnUpdate", nil)
        frame[antsKey]:Hide()
        frame[antsKey]:SetParent(nil)
        frame[antsKey] = nil
    end
end

------------------------------------------------------
-- 4. EASING FUNCTIONS
------------------------------------------------------

--- CSS ease-in-out equivalent (quadratic)
--- @param t number  0-1 progress
--- @return number  eased value 0-1
function PG.EaseInOut(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return 1 - (-2 * t + 2) ^ 2 / 2
    end
end

--- Linear interpolation
--- @param a number  start value
--- @param b number  end value
--- @param t number  0-1 progress
--- @return number
function PG.Lerp(a, b, t)
    return a + (b - a) * t
end

------------------------------------------------------
-- 5. TAINT-FREE FADE
------------------------------------------------------
-- Manual OnUpdate fade for frames that may be protected.

local _fadeQueue = {}
local _fadeFrame = CreateFrame("Frame")
_fadeFrame:Hide()

_fadeFrame:SetScript("OnUpdate", function(self, elapsed)
    local hasAny = false
    for frame, d in pairs(_fadeQueue) do
        d.elapsed = d.elapsed + elapsed
        if d.elapsed >= d.duration then
            frame:SetAlpha(d.toAlpha)
            if d.toAlpha <= 0 and d.hideOnFinish then
                frame:Hide()
            end
            if d.onFinish then pcall(d.onFinish) end
            _fadeQueue[frame] = nil
        else
            local t = d.elapsed / d.duration
            local eased = PG.EaseInOut(t)
            frame:SetAlpha(PG.Lerp(d.fromAlpha, d.toAlpha, eased))
            hasAny = true
        end
    end
    if not hasAny then self:Hide() end
end)

--- Taint-free fade for any frame (uses OnUpdate, not AnimationGroup).
--- @param frame Frame
--- @param fromAlpha number  starting alpha
--- @param toAlpha number  ending alpha
--- @param duration number  seconds
--- @param opts table|nil  { hideOnFinish=false, onFinish=function }
function PG.Fade(frame, fromAlpha, toAlpha, duration, opts)
    opts = opts or {}
    frame:SetAlpha(fromAlpha)
    if not frame:IsShown() and toAlpha > 0 then
        frame:Show()
    end
    _fadeQueue[frame] = {
        fromAlpha = fromAlpha,
        toAlpha = toAlpha,
        duration = max(0.01, duration),
        elapsed = 0,
        hideOnFinish = opts.hideOnFinish,
        onFinish = opts.onFinish,
    }
    _fadeFrame:Show()
end

--- Cancel any pending fade on a frame.
--- @param frame Frame
function PG.CancelFade(frame)
    _fadeQueue[frame] = nil
end

------------------------------------------------------
-- 6. UNIFIED API
------------------------------------------------------

--- Start glow on a frame (dispatches to the appropriate glow type).
--- @param frame Frame
--- @param style string  "shape" | "ants" | "pulse"
--- @param r number  red
--- @param g number  green
--- @param b number  blue
--- @param opts table|nil
function PG.StartGlow(frame, style, r, g, b, opts)
    if style == "ants" then
        PG.StartAnts(frame, r, g, b, opts)
    elseif style == "pulse" or style == "shape" then
        PG.StartShapeGlow(frame, r, g, b, opts)
    end
end

--- Stop all glows on a frame.
--- @param frame Frame
--- @param key string|nil
function PG.StopGlow(frame, key)
    PG.StopShapeGlow(frame, key)
    PG.StopAnts(frame, key)
end
