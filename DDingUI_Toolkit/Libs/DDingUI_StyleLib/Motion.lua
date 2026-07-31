------------------------------------------------------
-- DDingUI_StyleLib :: Motion
-- Small shared motion helpers for UI feedback.
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local M = {}
Lib.Motion = M

local abs, max, min, sin = math.abs, math.max, math.min, math.sin
local tinsert, tremove = table.insert, table.remove
local FLAT = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------
-- Easing
------------------------------------------------------
local function Clamp01(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return t
end

function M.Clamp01(t)
    return Clamp01(tonumber(t) or 0)
end

function M.Lerp(a, b, t)
    return a + (b - a) * Clamp01(t)
end

function M.EaseLinear(t)
    return Clamp01(t)
end

function M.EaseOutQuad(t)
    t = Clamp01(t)
    return 1 - (1 - t) * (1 - t)
end

function M.EaseInOutQuad(t)
    t = Clamp01(t)
    if t < 0.5 then return 2 * t * t end
    return 1 - ((-2 * t + 2) ^ 2) / 2
end

function M.EaseOutCubic(t)
    t = 1 - Clamp01(t)
    return 1 - t * t * t
end

function M.EaseInOutCubic(t)
    t = Clamp01(t)
    if t < 0.5 then return 4 * t * t * t end
    return 1 - ((-2 * t + 2) ^ 3) / 2
end

function M.EaseOutQuint(t)
    t = 1 - Clamp01(t)
    return 1 - t * t * t * t * t
end

function M.EaseOutExpo(t)
    t = Clamp01(t)
    if t >= 1 then return 1 end
    return 1 - (2 ^ (-10 * t))
end

function M.EaseOutBack(t, overshoot)
    t = Clamp01(t) - 1
    local c1 = overshoot or 1.18
    local c3 = c1 + 1
    return 1 + c3 * t * t * t + c1 * t * t
end

function M.EasePulse(t)
    t = Clamp01(t)
    return sin(t * 3.14159265)
end

local EASES = {
    linear = M.EaseLinear,
    outQuad = M.EaseOutQuad,
    inOutQuad = M.EaseInOutQuad,
    outCubic = M.EaseOutCubic,
    inOutCubic = M.EaseInOutCubic,
    outQuint = M.EaseOutQuint,
    outExpo = M.EaseOutExpo,
    outBack = M.EaseOutBack,
    pulse = M.EasePulse,
    smooth = M.EaseInOutCubic,
}

function M.GetEase(ease)
    if type(ease) == "function" then return ease end
    return EASES[ease or "outCubic"] or M.EaseOutCubic
end

------------------------------------------------------
-- Tween driver
------------------------------------------------------
local driver = CreateFrame("Frame")
driver:Hide()

local jobs = {}

local function SafeCall(fn, ...)
    if fn then pcall(fn, ...) end
end

local function GetJobStore(target)
    if not target then return nil end
    target._ddslMotionJobs = target._ddslMotionJobs or {}
    return target._ddslMotionJobs
end

local function RemoveJob(index)
    local job = jobs[index]
    if job and job.target and job.target._ddslMotionJobs then
        if job.target._ddslMotionJobs[job.key] == job then
            job.target._ddslMotionJobs[job.key] = nil
        end
    end
    tremove(jobs, index)
end

driver:SetScript("OnUpdate", function(self, elapsed)
    for i = #jobs, 1, -1 do
        local job = jobs[i]
        if job.cancelled or not job.target then
            RemoveJob(i)
        else
            job.elapsed = job.elapsed + elapsed
            if job.elapsed < job.delay then
                -- wait
            else
                local t = (job.elapsed - job.delay) / job.duration
                if t >= 1 then
                    SafeCall(job.onUpdate, job.target, job.toValue, 1, 1)
                    SafeCall(job.onFinish, job.target)
                    RemoveJob(i)
                else
                    local eased = job.ease(t, job.overshoot)
                    local value = M.Lerp(job.fromValue, job.toValue, eased)
                    SafeCall(job.onUpdate, job.target, value, eased, t)
                end
            end
        end
    end

    if #jobs == 0 then self:Hide() end
end)

--- Start a numeric tween.
--- opts: { key, delay, ease, overshoot, onUpdate(target, value, eased, rawT), onFinish(target) }
function M.Tween(target, fromValue, toValue, duration, opts)
    if not target then return nil end
    opts = opts or {}
    local key = opts.key or "default"
    M.Stop(target, key)

    local store = GetJobStore(target)
    if not store then return nil end

    local job = {
        target = target,
        key = key,
        fromValue = tonumber(fromValue) or 0,
        toValue = tonumber(toValue) or 1,
        duration = max(0.001, tonumber(duration) or 0.18),
        delay = max(0, tonumber(opts.delay) or 0),
        elapsed = 0,
        ease = M.GetEase(opts.ease),
        overshoot = opts.overshoot,
        onUpdate = opts.onUpdate,
        onFinish = opts.onFinish,
    }

    store[key] = job
    tinsert(jobs, job)
    driver:Show()
    return job
end

function M.Stop(target, key, finish)
    if not target then return end
    key = key or "default"
    local store = target._ddslMotionJobs
    local job = store and store[key]
    if not job then return end
    if finish then
        SafeCall(job.onUpdate, job.target, job.toValue, 1, 1)
        SafeCall(job.onFinish, job.target)
    end
    job.cancelled = true
    store[key] = nil
end

function M.StopAll(target)
    if not target or not target._ddslMotionJobs then return end
    for key in pairs(target._ddslMotionJobs) do
        M.Stop(target, key)
    end
end

------------------------------------------------------
-- Colour and motion presets
------------------------------------------------------
local function ReadRGBA(color, fallback)
    fallback = fallback or { 1, 1, 1, 1 }
    if type(color) == "table" then
        return tonumber(color[1]) or fallback[1] or 1,
               tonumber(color[2]) or fallback[2] or 1,
               tonumber(color[3]) or fallback[3] or 1,
               tonumber(color[4]) or fallback[4] or 1
    end
    return fallback[1] or 1, fallback[2] or 1, fallback[3] or 1, fallback[4] or 1
end

local function LerpRGBA(fromColor, toColor, t)
    local fr, fg, fb, fa = ReadRGBA(fromColor)
    local tr, tg, tb, ta = ReadRGBA(toColor, { fr, fg, fb, fa })
    return M.Lerp(fr, tr, t), M.Lerp(fg, tg, t), M.Lerp(fb, tb, t), M.Lerp(fa, ta, t)
end

--- Tween any RGBA value. opts: { key, ease, apply(target, r,g,b,a,t,rawT), onFinish(target) }
function M.Color(target, fromColor, toColor, duration, opts)
    if not target then return nil end
    opts = opts or {}
    local key = opts.key or "color"
    local apply = opts.apply or opts.onUpdate

    return M.Tween(target, 0, 1, duration or 0.16, {
        key = key,
        delay = opts.delay,
        ease = opts.ease or "smooth",
        onUpdate = function(obj, value, eased, rawT)
            local r, g, b, a = LerpRGBA(fromColor, toColor, value)
            SafeCall(apply, obj, r, g, b, a, value, rawT)
        end,
        onFinish = opts.onFinish,
    })
end

function M.BackdropColor(frame, fromColor, toColor, duration, opts)
    if not frame or not frame.SetBackdropColor then return nil end
    opts = opts or {}
    opts.key = opts.key or "backdropColor"
    opts.apply = function(target, r, g, b, a)
        target:SetBackdropColor(r, g, b, a)
        SafeCall(opts.onColor, target, r, g, b, a)
    end
    return M.Color(frame, fromColor, toColor, duration, opts)
end

function M.BackdropBorderColor(frame, fromColor, toColor, duration, opts)
    if not frame or not frame.SetBackdropBorderColor then return nil end
    opts = opts or {}
    opts.key = opts.key or "backdropBorderColor"
    opts.apply = function(target, r, g, b, a)
        target:SetBackdropBorderColor(r, g, b, a)
        SafeCall(opts.onColor, target, r, g, b, a)
    end
    return M.Color(frame, fromColor, toColor, duration, opts)
end

function M.TextColor(fontString, fromColor, toColor, duration, opts)
    if not fontString or not fontString.SetTextColor then return nil end
    opts = opts or {}
    opts.key = opts.key or "textColor"
    opts.apply = function(target, r, g, b, a)
        target:SetTextColor(r, g, b, a)
        SafeCall(opts.onColor, target, r, g, b, a)
    end
    return M.Color(fontString, fromColor, toColor, duration, opts)
end

function M.TextureColor(texture, fromColor, toColor, duration, opts)
    if not texture or not texture.SetColorTexture then return nil end
    opts = opts or {}
    opts.key = opts.key or "textureColor"
    opts.apply = function(target, r, g, b, a)
        target:SetColorTexture(r, g, b, a)
        SafeCall(opts.onColor, target, r, g, b, a)
    end
    return M.Color(texture, fromColor, toColor, duration, opts)
end

function M.VertexColor(region, fromColor, toColor, duration, opts)
    if not region or not region.SetVertexColor then return nil end
    opts = opts or {}
    opts.key = opts.key or "vertexColor"
    opts.apply = function(target, r, g, b, a)
        target:SetVertexColor(r, g, b, a)
        SafeCall(opts.onColor, target, r, g, b, a)
    end
    return M.Color(region, fromColor, toColor, duration, opts)
end

--- Attach a smooth 0->1 hover progress tween.
--- opts: { key, duration, ease, bind, hook, initial, apply(frame,t,eased,rawT), onEnter, onLeave }
function M.Hover(frame, opts)
    if not frame then return nil end
    opts = opts or {}

    local key = opts.key or "hover"
    local duration = opts.duration or 0.10
    local ease = opts.ease or "smooth"
    local state = frame._ddslHoverMotion or {}
    frame._ddslHoverProgress = Clamp01(opts.initial or frame._ddslHoverProgress or 0)

    function state:SetTarget(target)
        target = Clamp01(target)
        local from = Clamp01(frame._ddslHoverProgress or 0)
        return M.Tween(frame, from, target, duration, {
            key = key,
            ease = ease,
            onUpdate = function(obj, value, eased, rawT)
                obj._ddslHoverProgress = value
                SafeCall(opts.apply, obj, value, eased, rawT)
            end,
            onFinish = function(obj)
                obj._ddslHoverProgress = target
                SafeCall(opts.apply, obj, target, target, 1)
            end,
        })
    end

    function state:Enter()
        SafeCall(opts.onEnter, frame)
        return self:SetTarget(1)
    end

    function state:Leave()
        SafeCall(opts.onLeave, frame)
        return self:SetTarget(0)
    end

    frame._ddslHoverMotion = state
    SafeCall(opts.apply, frame, frame._ddslHoverProgress, frame._ddslHoverProgress, 1)

    if opts.bind ~= false and not state.bound then
        if opts.hook then
            if frame.HookScript then
                frame:HookScript("OnEnter", function() state:Enter() end)
                frame:HookScript("OnLeave", function() state:Leave() end)
            end
        else
            frame:SetScript("OnEnter", function() state:Enter() end)
            frame:SetScript("OnLeave", function() state:Leave() end)
        end
        state.bound = true
    end

    return state
end

--- Smooth button hover: short in/out colour interpolation for bg, border, and label.
function M.ButtonHover(frame, opts)
    if not frame then return nil end
    opts = opts or {}

    local normalBg = opts.normalBg or { 0.06, 0.06, 0.06, 0.80 }
    local hoverBg = opts.hoverBg or { 0.20, 0.20, 0.20, 0.60 }
    local normalBorder = opts.normalBorder or { 0.25, 0.25, 0.25, 0.50 }
    local hoverBorder = opts.hoverBorder or normalBorder
    local text = opts.text or frame.label
    local normalText = opts.normalText or { 0.85, 0.85, 0.85, 1.0 }
    local hoverText = opts.hoverText or { 1.00, 1.00, 1.00, 1.0 }

    return M.Hover(frame, {
        key = opts.key or "buttonHover",
        duration = opts.duration or 0.10,
        ease = opts.ease or "smooth",
        bind = opts.bind,
        hook = opts.hook,
        initial = opts.initial,
        onEnter = opts.onEnter,
        onLeave = opts.onLeave,
        apply = function(target, t, eased, rawT)
            local r, g, b, a = LerpRGBA(normalBg, hoverBg, t)
            if target.SetBackdropColor then target:SetBackdropColor(r, g, b, a) end
            r, g, b, a = LerpRGBA(normalBorder, hoverBorder, t)
            if target.SetBackdropBorderColor then target:SetBackdropBorderColor(r, g, b, a) end
            if text and text.SetTextColor then
                r, g, b, a = LerpRGBA(normalText, hoverText, t)
                text:SetTextColor(r, g, b, a)
            end
            SafeCall(opts.apply, target, t, eased, rawT)
        end,
    })
end

--- Red-to-normal validation flash for popup input feedback.
function M.ValidationFlash(frame, opts)
    if not frame then return nil end
    opts = opts or {}
    local alert = opts.alert or { 0.90, 0.15, 0.15, 0.70 }
    local normal = opts.normal or { 1.00, 1.00, 1.00, 0.20 }
    local duration = opts.duration or 0.70
    local apply = opts.apply

    if not apply then
        if frame.SetBackdropBorderColor then
            apply = function(target, r, g, b, a) target:SetBackdropBorderColor(r, g, b, a) end
        elseif frame.SetColorTexture then
            apply = function(target, r, g, b, a) target:SetColorTexture(r, g, b, a) end
        elseif frame.SetVertexColor then
            apply = function(target, r, g, b, a) target:SetVertexColor(r, g, b, a) end
        end
    end

    if not apply then return nil end
    return M.Color(frame, alert, normal, duration, {
        key = opts.key or "validationFlash",
        ease = opts.ease or "outCubic",
        apply = apply,
        onFinish = opts.onFinish,
    })
end

--- Panel entrance: quick fade + scale settle for options and popups.
function M.PanelOpen(frame, opts)
    if not frame or not frame.SetAlpha then return nil end
    opts = opts or {}
    M.Stop(frame, opts.closeKey or "panelClose")
    local base = opts.baseScale or (frame.GetScale and frame:GetScale()) or 1
    local fromScale = opts.fromScale or (base * 0.965)
    local toScale = opts.toScale or base
    local fromAlpha = opts.fromAlpha or 0
    local toAlpha = opts.toAlpha or 1

    if frame.Show then frame:Show() end
    frame:SetAlpha(fromAlpha)
    if frame.SetScale then frame:SetScale(fromScale) end

    return M.Tween(frame, 0, 1, opts.duration or 0.18, {
        key = opts.key or "panelOpen",
        ease = opts.ease or "outQuint",
        onUpdate = function(target, t)
            target:SetAlpha(M.Lerp(fromAlpha, toAlpha, t))
            if target.SetScale then
                target:SetScale(M.Lerp(fromScale, toScale, t))
            end
            SafeCall(opts.onUpdate, target, t)
        end,
        onFinish = function(target)
            target:SetAlpha(toAlpha)
            if target.SetScale then target:SetScale(toScale) end
            SafeCall(opts.onFinish, target)
        end,
    })
end

--- Panel exit: fade + slight shrink, restoring scale after hide by default.
function M.PanelClose(frame, opts)
    if not frame or not frame.SetAlpha then return nil end
    opts = opts or {}
    M.Stop(frame, opts.openKey or "panelOpen")
    local base = opts.baseScale or (frame.GetScale and frame:GetScale()) or 1
    local fromScale = opts.fromScale or base
    local toScale = opts.toScale or (base * 0.965)
    local fromAlpha = opts.fromAlpha or (frame.GetAlpha and frame:GetAlpha()) or 1
    local toAlpha = opts.toAlpha or 0
    local hideOnFinish = opts.hideOnFinish
    if hideOnFinish == nil then hideOnFinish = true end
    local restoreScale = opts.restoreScale
    if restoreScale == nil then restoreScale = hideOnFinish end
    local restoreAlpha = opts.restoreAlpha
    if restoreAlpha == nil then restoreAlpha = hideOnFinish end

    return M.Tween(frame, 0, 1, opts.duration or 0.14, {
        key = opts.key or "panelClose",
        ease = opts.ease or "inOutQuad",
        onUpdate = function(target, t)
            target:SetAlpha(M.Lerp(fromAlpha, toAlpha, t))
            if target.SetScale then
                target:SetScale(M.Lerp(fromScale, toScale, t))
            end
            SafeCall(opts.onUpdate, target, t)
        end,
        onFinish = function(target)
            target:SetAlpha(toAlpha)
            if hideOnFinish and target.Hide then target:Hide() end
            if restoreScale and target.SetScale then target:SetScale(base) end
            if restoreAlpha then target:SetAlpha(fromAlpha) end
            SafeCall(opts.onFinish, target)
        end,
    })
end

------------------------------------------------------
-- Common motions
------------------------------------------------------
function M.Alpha(region, fromAlpha, toAlpha, duration, opts)
    if not region or not region.SetAlpha then return nil end
    opts = opts or {}
    opts.key = opts.key or "alpha"
    local oldUpdate = opts.onUpdate
    opts.onUpdate = function(target, value, eased, rawT)
        target:SetAlpha(value)
        SafeCall(oldUpdate, target, value, eased, rawT)
    end
    return M.Tween(region, fromAlpha, toAlpha, duration, opts)
end

function M.FadeIn(frame, duration, opts)
    if not frame then return nil end
    opts = opts or {}
    if frame.Show then frame:Show() end
    return M.Alpha(frame, opts.fromAlpha or frame:GetAlpha() or 0, opts.toAlpha or 1, duration or 0.16, opts)
end

function M.FadeOut(frame, duration, opts)
    if not frame then return nil end
    opts = opts or {}
    local hideOnFinish = opts.hideOnFinish
    local oldFinish = opts.onFinish
    opts.onFinish = function(target)
        if hideOnFinish and target.Hide then target:Hide() end
        SafeCall(oldFinish, target)
    end
    return M.Alpha(frame, opts.fromAlpha or frame:GetAlpha() or 1, opts.toAlpha or 0, duration or 0.16, opts)
end

function M.Scale(frame, fromScale, toScale, duration, opts)
    if not frame or not frame.SetScale then return nil end
    opts = opts or {}
    opts.key = opts.key or "scale"
    local oldUpdate = opts.onUpdate
    opts.onUpdate = function(target, value, eased, rawT)
        target:SetScale(value)
        SafeCall(oldUpdate, target, value, eased, rawT)
    end
    return M.Tween(frame, fromScale, toScale, duration, opts)
end

--- Cute impact-pop motion: shrink/appear -> overshoot -> settle.
--- opts: { baseScale, from, peak, to, duration, split, alpha, key, overshoot }
function M.ImpactPop(frame, opts)
    if not frame or not frame.SetScale then return nil end
    opts = opts or {}
    local base = opts.baseScale or frame:GetScale() or 1
    local from = opts.from or 0.92
    local peak = opts.peak or 1.08
    local to = opts.to or 1.0
    local split = opts.split or 0.56
    local duration = opts.duration or 0.22
    local startAlpha = opts.fromAlpha
    local endAlpha = opts.toAlpha or 1
    local alpha = opts.alpha
    local initialAlpha = startAlpha or (frame.GetAlpha and frame:GetAlpha()) or 0

    if frame.Show then frame:Show() end

    return M.Tween(frame, 0, 1, duration, {
        key = opts.key or "impactPop",
        ease = "linear",
        onUpdate = function(target, t)
            local scale
            if t < split then
                local p = M.EaseOutBack(t / split, opts.overshoot or 1.05)
                scale = M.Lerp(from, peak, p)
            else
                local p = M.EaseOutCubic((t - split) / (1 - split))
                scale = M.Lerp(peak, to, p)
            end
            target:SetScale(base * scale)
            if alpha and target.SetAlpha then
                target:SetAlpha(M.Lerp(initialAlpha, endAlpha, M.EaseOutQuad(t)))
            end
        end,
        onFinish = function(target)
            target:SetScale(base * to)
            if alpha and target.SetAlpha then target:SetAlpha(endAlpha) end
            SafeCall(opts.onFinish, target)
        end,
    })
end
M.Pop = M.ImpactPop

--- Small press feedback for buttons.
function M.Press(frame, opts)
    if not frame or not frame.SetScale then return nil end
    opts = opts or {}
    local base = opts.baseScale or frame:GetScale() or 1
    local down = opts.down or 0.96
    local duration = opts.duration or 0.07
    return M.Scale(frame, base, base * down, duration, {
        key = opts.key or "press",
        ease = opts.ease or "outQuad",
        onFinish = opts.onFinish,
    })
end

function M.Release(frame, opts)
    if not frame or not frame.SetScale then return nil end
    opts = opts or {}
    local base = opts.baseScale or 1
    return M.ImpactPop(frame, {
        key = opts.key or "press",
        baseScale = base,
        from = opts.from or 0.96,
        peak = opts.peak or 1.03,
        to = 1,
        duration = opts.duration or 0.13,
        overshoot = opts.overshoot or 0.75,
        onFinish = opts.onFinish,
    })
end

------------------------------------------------------
-- Edge flash
------------------------------------------------------
local function EnsureFlash(frame, key, thickness, layer, subLevel)
    local storeKey = "_ddslEdgeFlash_" .. key
    local flash = frame[storeKey]
    if flash then return flash end

    flash = CreateFrame("Frame", nil, frame)
    flash:SetAllPoints(frame)
    flash:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 0) + 8)
    flash:Hide()

    local top = flash:CreateTexture(nil, layer or "OVERLAY", nil, subLevel or 7)
    local bottom = flash:CreateTexture(nil, layer or "OVERLAY", nil, subLevel or 7)
    local left = flash:CreateTexture(nil, layer or "OVERLAY", nil, subLevel or 7)
    local right = flash:CreateTexture(nil, layer or "OVERLAY", nil, subLevel or 7)

    flash._edges = { top, bottom, left, right }
    flash._thickness = thickness or 2
    frame[storeKey] = flash
    return flash
end

local function LayoutFlash(flash)
    local t = flash._thickness or 2
    local top, bottom, left, right = flash._edges[1], flash._edges[2], flash._edges[3], flash._edges[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", flash, "TOPLEFT", -t, t)
    top:SetPoint("TOPRIGHT", flash, "TOPRIGHT", t, t)
    top:SetHeight(t)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", flash, "BOTTOMLEFT", -t, -t)
    bottom:SetPoint("BOTTOMRIGHT", flash, "BOTTOMRIGHT", t, -t)
    bottom:SetHeight(t)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", flash, "TOPLEFT", -t, t)
    left:SetPoint("BOTTOMLEFT", flash, "BOTTOMLEFT", -t, -t)
    left:SetWidth(t)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", flash, "TOPRIGHT", t, t)
    right:SetPoint("BOTTOMRIGHT", flash, "BOTTOMRIGHT", t, -t)
    right:SetWidth(t)
end

--- Accent/white edge flash. opts: { key, thickness, alpha, duration, layer, subLevel }
function M.EdgeFlash(frame, r, g, b, opts)
    if not frame or not frame.CreateTexture then return nil end
    opts = opts or {}
    local key = opts.key or "default"
    local alpha = opts.alpha or 0.90
    local flash = EnsureFlash(frame, key, opts.thickness or 2, opts.layer, opts.subLevel)
    flash._thickness = opts.thickness or flash._thickness or 2
    LayoutFlash(flash)

    for _, edge in ipairs(flash._edges) do
        edge:SetTexture(FLAT)
        edge:SetColorTexture(r or 1, g or 1, b or 1, alpha)
        if edge.SetSnapToPixelGrid then
            edge:SetSnapToPixelGrid(false)
            edge:SetTexelSnappingBias(0)
        end
        edge:Show()
    end
    flash:SetAlpha(1)
    flash:Show()

    return M.Alpha(flash, 1, 0, opts.duration or 0.32, {
        key = "edgeFlash",
        ease = opts.ease or "outCubic",
        onFinish = function(target)
            if target and target.Hide then target:Hide() end
            SafeCall(opts.onFinish, target)
        end,
    })
end

------------------------------------------------------
-- Convenience aliases on the main lib
------------------------------------------------------
Lib.Tween = M.Tween
Lib.StopMotion = M.Stop
Lib.ColorTween = M.Color
Lib.FadeIn = M.FadeIn
Lib.FadeOut = M.FadeOut
Lib.ImpactPop = M.ImpactPop
Lib.EdgeFlash = M.EdgeFlash
Lib.AttachHoverMotion = M.Hover
Lib.ButtonHoverMotion = M.ButtonHover
-- Compatibility for controls created before the shared preset was renamed.
M.InterfaceButton = M.ButtonHover
Lib.InterfaceButtonMotion = M.ButtonHover
Lib.PanelOpen = M.PanelOpen
Lib.PanelClose = M.PanelClose
Lib.ValidationFlash = M.ValidationFlash
