--[[
    DDingToolKit - BuffReminder: BR Glow
    4-type glow system (Pixel, AutoCast, Border, Proc) using LibCustomGlow.
    Ported from BuffReminders/UI/Glow.lua by zerbi.
]]

local _, ns = ...

local LCG = LibStub("LibCustomGlow-1.0", true)
if not LCG then return end

ns.BR_Glow = {}

ns.BR_Glow.Type = {
    Pixel = 1,
    AutoCast = 2,
    Border = 3,
    Proc = 4,
}

local GlowType = ns.BR_Glow.Type
ns.BR_Glow.DEFAULT_COLOR = { 0.95, 0.95, 0.32, 1 }

-- ============================================================================
-- PULSING BORDER
-- ============================================================================

function ns.BR_Glow.PulsingBorderStart(frame, key, color, thickness, xOffset, yOffset, animDuration)
    color = color or ns.BR_Glow.DEFAULT_COLOR
    local cr, cg, cb, ca = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    local stateKey = "_pulsingBorder_" .. key
    local state = frame[stateKey]
    thickness = thickness or 2
    xOffset = xOffset or 0
    yOffset = yOffset or 0
    animDuration = animDuration or 0.6

    if not state then
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetPoint("TOPLEFT", -xOffset, yOffset)
        holder:SetPoint("BOTTOMRIGHT", xOffset, -yOffset)
        holder:SetFrameLevel(frame:GetFrameLevel() + 5)
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(thickness)
        t:SetColorTexture(cr, cg, cb, ca)
        local b = holder:CreateTexture(nil, "OVERLAY")
        b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(thickness)
        b:SetColorTexture(cr, cg, cb, ca)
        local l = holder:CreateTexture(nil, "OVERLAY")
        l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(thickness)
        l:SetColorTexture(cr, cg, cb, ca)
        local r = holder:CreateTexture(nil, "OVERLAY")
        r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(thickness)
        r:SetColorTexture(cr, cg, cb, ca)
        local ag = holder:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(1); fade:SetToAlpha(0.3)
        fade:SetDuration(animDuration); fade:SetSmoothing("IN_OUT")
        state = {
            holder = holder, anim = ag, fade = fade,
            edges = { t, b, l, r },
            color = { cr, cg, cb, ca },
            thickness = thickness, xOffset = xOffset, yOffset = yOffset,
            animDuration = animDuration,
        }
        frame[stateKey] = state
    else
        local prev = state.color
        if prev[1] ~= cr or prev[2] ~= cg or prev[3] ~= cb or prev[4] ~= ca then
            for _, edge in ipairs(state.edges) do edge:SetColorTexture(cr, cg, cb, ca) end
            state.color = { cr, cg, cb, ca }
        end
        if state.thickness ~= thickness or state.xOffset ~= xOffset or state.yOffset ~= yOffset then
            state.holder:SetPoint("TOPLEFT", -xOffset, yOffset)
            state.holder:SetPoint("BOTTOMRIGHT", xOffset, -yOffset)
            state.edges[1]:SetHeight(thickness); state.edges[2]:SetHeight(thickness)
            state.edges[3]:SetWidth(thickness); state.edges[4]:SetWidth(thickness)
            state.thickness = thickness; state.xOffset = xOffset; state.yOffset = yOffset
        end
        if state.animDuration ~= animDuration then
            state.fade:SetDuration(animDuration); state.animDuration = animDuration
            state.anim:Stop(); state.anim:Play()
        end
    end
    state.holder:Show()
    if not state.anim:IsPlaying() then state.anim:Play() end
end

function ns.BR_Glow.PulsingBorderStop(frame, key)
    local state = frame["_pulsingBorder_" .. key]
    if state then state.anim:Stop(); state.holder:Hide() end
end

-- ============================================================================
-- GLOW TYPE DISPATCHERS
-- ============================================================================

ns.BR_Glow.Types = {
    { name = "픽셀" },
    { name = "자동시전" },
    { name = "테두리" },
    { name = "프로세스" },
}

local GLOW_START = {
    function(f, color, key, size, xOff, yOff, params)
        local p = params or {}
        LCG.PixelGlow_Start(f, color, p.lines, p.frequency, p.length or 10, size, xOff, yOff, false, key)
    end,
    function(f, color, key, size, xOff, yOff, params)
        local p = params or {}
        LCG.AutoCastGlow_Start(f, color, p.particles, p.frequency, p.scale or (size / 2), xOff, yOff, key)
    end,
    function(f, color, key, size, xOff, yOff, params)
        local p = params or {}
        ns.BR_Glow.PulsingBorderStart(f, key, color, size, xOff, yOff, p.frequency)
    end,
    function(f, color, key, _, xOff, yOff, params)
        local p = params or {}
        LCG.ProcGlow_Start(f, {
            color = color, key = key,
            duration = p.duration or 1, startAnim = p.startAnim or false,
            xOffset = xOff, yOffset = yOff,
        })
    end,
}

local LCG_FRAME_KEYS = { [1] = "_PixelGlow", [2] = "_AutoCastGlow", [4] = "_ProcGlow" }

local GLOW_STOP = {
    LCG.PixelGlow_Stop,
    LCG.AutoCastGlow_Stop,
    ns.BR_Glow.PulsingBorderStop,
    LCG.ProcGlow_Stop,
}

function ns.BR_Glow.Start(frame, typeIndex, color, key, size, xOffset, yOffset, params)
    size = size or 2; xOffset = xOffset or 0; yOffset = yOffset or 0
    local fn = GLOW_START[typeIndex]
    if fn then fn(frame, color, key, size, xOffset, yOffset, params) end
end

function ns.BR_Glow.Stop(frame, typeIndex, key)
    local fn = GLOW_STOP[typeIndex]
    if fn then
        fn(frame, key)
        local lcgKey = LCG_FRAME_KEYS[typeIndex]
        if lcgKey then frame[lcgKey .. (key or "")] = nil end
    end
end

function ns.BR_Glow.StopAll(frame, key)
    for typeIndex = 1, 4 do ns.BR_Glow.Stop(frame, typeIndex, key) end
end

-- ============================================================================
-- HIGH-LEVEL GLOW FUNCTIONS
-- ============================================================================

local EXPIRATION_KEY = "BR_expiration"
local GLOW_STATE_KEY = "_brGlowState"

local function ColorsEqual(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

local function ShallowEqual(a, b)
    if a == b then return true end
    if not a or not b then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function ns.BR_Glow.BuildAdvancedParams(t, typeIndex, keyPrefix)
    keyPrefix = keyPrefix or "glow"
    if typeIndex == GlowType.Pixel then
        local lines = t.pixelLines or t[keyPrefix .. "PixelLines"]
        local freq = t.pixelFrequency or t[keyPrefix .. "PixelFrequency"]
        local len = t.pixelLength or t[keyPrefix .. "PixelLength"]
        if lines or freq or len then return { lines = lines, frequency = freq, length = len } end
    elseif typeIndex == GlowType.AutoCast then
        local particles = t.autocastParticles or t[keyPrefix .. "AutocastParticles"]
        local freq = t.autocastFrequency or t[keyPrefix .. "AutocastFrequency"]
        local scale = t.autocastScale or t[keyPrefix .. "AutocastScale"]
        if particles or freq or scale then return { particles = particles, frequency = freq, scale = scale } end
    elseif typeIndex == GlowType.Border then
        local freq = t.borderFrequency or t[keyPrefix .. "BorderFrequency"]
        if freq then return { frequency = freq } end
    elseif typeIndex == GlowType.Proc then
        local dur = t.procDuration or t[keyPrefix .. "ProcDuration"]
        local startAnim = t.procStartAnim
        if startAnim == nil then startAnim = t[keyPrefix .. "ProcStartAnim"] end
        if dur or startAnim then return { duration = dur, startAnim = startAnim } end
    end
    return nil
end

function ns.BR_Glow.SetExpiration(frame, show, category, cachedSettings)
    local state = frame[GLOW_STATE_KEY]
    if show then
        local typeIndex, color, size, borderOffset, params, glowXOff, glowYOff
        if cachedSettings then
            typeIndex = cachedSettings.typeIndex
            color = cachedSettings.color
            size = cachedSettings.size
            borderOffset = cachedSettings.borderSize or ns.BR_DEFAULT_BORDER_SIZE
            params = cachedSettings.params
            glowXOff = cachedSettings.glowXOffset or 0
            glowYOff = cachedSettings.glowYOffset or 0
        else
            local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
            local d = db and db.defaults or {}
            typeIndex = d.glowType or GlowType.AutoCast
            color = d.glowColor
            if typeIndex == GlowType.Proc and not d.glowProcUseCustomColor then color = nil end
            size = d.glowSize or 2
            borderOffset = (category and ns.BR_Config.GetCategorySetting(category, "borderSize"))
                or d.borderSize or ns.BR_DEFAULT_BORDER_SIZE
            params = ns.BR_Glow.BuildAdvancedParams(d, typeIndex)
            glowXOff = d.glowXOffset or 0
            glowYOff = d.glowYOffset or 0
        end
        local xOff = borderOffset + glowXOff
        local yOff = borderOffset + glowYOff
        if state and state.showing and state.typeIndex == typeIndex and state.size == size
            and state.xOff == xOff and state.yOff == yOff
            and ColorsEqual(state.color, color) and ShallowEqual(state.params, params) then
            return
        end
        if state and state.showing then
            ns.BR_Glow.Stop(frame, state.typeIndex, EXPIRATION_KEY)
        end
        ns.BR_Glow.Start(frame, typeIndex, color, EXPIRATION_KEY, size, xOff, yOff, params)
        frame[GLOW_STATE_KEY] = {
            showing = true, typeIndex = typeIndex, size = size,
            color = color, xOff = xOff, yOff = yOff, params = params,
        }
    else
        if state and state.showing then
            ns.BR_Glow.Stop(frame, state.typeIndex, EXPIRATION_KEY)
            state.showing = false
        end
    end
end
