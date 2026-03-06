----------------------------------------------------------------------
-- DDingUI Nameplate - HealthBar.lua
-- Health bar creation, update, color logic, smooth animation
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FLAT = ns.FLAT
local floor = math.floor
local SMOOTH_SPEED = 5  -- units/sec interpolation speed multiplier

----------------------------------------------------------------------
-- Create health bar elements -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.CreateHealthBar(data)
    local parent = data.frame
    local db = ns.db.healthBar
    local sizeDB = db.enemy  -- default to enemy; resized in UpdateHealthBar

    -- Background -- [NAMEPLATE]
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(FLAT)
    local bgColor = ns.GetSLColor("bg.input")
    bg:SetVertexColor(ns.UnpackColor(bgColor))

    -- StatusBar -- [NAMEPLATE]
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(FLAT)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    -- Border -- [NAMEPLATE]
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetBackdrop({
        edgeFile = FLAT,
        edgeSize = 1,
    })
    local borderColor = ns.GetSLColor("border.default")
    border:SetBackdropBorderColor(ns.UnpackColor(borderColor))

    data.healthBar = {
        bar    = bar,
        bg     = bg,
        border = border,
        smooth = {
            current = 1,
            target  = 1,
            active  = false,
        },
    }

    -- Smooth animation OnUpdate -- [NAMEPLATE]
    bar:SetScript("OnUpdate", function(self, elapsed)
        local s = data.healthBar.smooth
        if not s.active then return end

        local diff = s.target - s.current
        if math.abs(diff) < 0.001 then
            s.current = s.target
            s.active  = false
            self:SetValue(s.target)
            return
        end

        local step = diff * math.min(elapsed * SMOOTH_SPEED, 1)
        s.current = s.current + step
        self:SetValue(s.current)
    end)

    -- Initial layout
    ns.LayoutHealthBar(data)
end

----------------------------------------------------------------------
-- Layout health bar (position/size) -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.LayoutHealthBar(data)
    local db = ns.db.healthBar
    local sizeDB = (data.isFriendly and db.friendly) or db.enemy
    local w = sizeDB.width or 120
    local h = sizeDB.height or 12

    local parent = data.frame
    local hb = data.healthBar
    if not hb then return end

    -- Position: centered horizontally, slightly above center
    hb.bar:ClearAllPoints()
    hb.bar:SetPoint("CENTER", parent, "CENTER", 0, 0)
    hb.bar:SetSize(w, h)

    hb.bg:ClearAllPoints()
    hb.bg:SetPoint("TOPLEFT", hb.bar, "TOPLEFT", 0, 0)
    hb.bg:SetPoint("BOTTOMRIGHT", hb.bar, "BOTTOMRIGHT", 0, 0)

    hb.border:ClearAllPoints()
    hb.border:SetPoint("TOPLEFT", hb.bar, "TOPLEFT", -1, 1)
    hb.border:SetPoint("BOTTOMRIGHT", hb.bar, "BOTTOMRIGHT", 1, -1)
    hb.border:SetFrameLevel(hb.bar:GetFrameLevel() + 1)
end

----------------------------------------------------------------------
-- Update health value -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateHealthBar(data, unitID)
    local hb = data.healthBar
    if not hb or not unitID then return end

    local health    = UnitHealth(unitID)
    local healthMax = UnitHealthMax(unitID)

    -- Secret number protection -- [NAMEPLATE]
    if issecretvalue and (issecretvalue(health) or issecretvalue(healthMax)) then
        return
    end

    health    = tonumber(health) or 0
    healthMax = tonumber(healthMax) or 1
    if healthMax == 0 then healthMax = 1 end

    local pct = health / healthMax

    -- [PERF] 타입이 실제로 변경됐을 때만 Re-layout (매 UNIT_HEALTH마다 ClearAllPoints 방지)
    local isFriendly = UnitIsFriend("player", unitID) and true or false
    if data._lastFriendly ~= isFriendly then
        data._lastFriendly = isFriendly
        ns.LayoutHealthBar(data)
    end

    if ns.db.healthBar.smoothing and hb.smooth.current ~= pct then
        hb.smooth.target = pct
        hb.smooth.active = true
    else
        hb.bar:SetValue(pct)
        hb.smooth.current = pct
        hb.smooth.target  = pct
        hb.smooth.active  = false
    end
end

----------------------------------------------------------------------
-- Health color logic -- [NAMEPLATE]
-- Priority: threat > tapped > class (player) > reaction
----------------------------------------------------------------------
function ns.UpdateHealthColor(data, unitID)
    local hb = data.healthBar
    if not hb or not unitID then return end

    local db = ns.db.healthBar
    local r, g, b = 0.85, 0.20, 0.20  -- default hostile red

    -- 1. Tapped (someone else tagged this mob) -- [NAMEPLATE]
    if data.isTapped then
        r, g, b = ns.UnpackColor(db.tappedColor)
        hb.bar:SetStatusBarColor(r, g, b)
        return
    end

    -- 2. Threat color (if threat module active and overrides reaction)
    if db.colorByThreat and ns.db.threat.enabled and ns.GetThreatColor then
        local tr, tg, tb = ns.GetThreatColor(unitID)
        if tr then
            hb.bar:SetStatusBarColor(tr, tg, tb)
            return
        end
    end

    -- 3. Class color (player units) -- [NAMEPLATE]
    if db.colorByClass and data.isPlayer then
        local _, class = UnitClass(unitID)
        if class then
            local cc = RAID_CLASS_COLORS[class]
            if cc then
                hb.bar:SetStatusBarColor(cc.r, cc.g, cc.b)
                return
            end
        end
    end

    -- 4. Reaction color -- [NAMEPLATE]
    if db.colorByReaction then
        local reaction = UnitReaction(unitID, "player")
        if reaction then
            if reaction <= 2 then
                -- Hostile
                r, g, b = ns.UnpackColor(db.reactionColors.hostile)
            elseif reaction <= 4 then
                -- Neutral
                r, g, b = ns.UnpackColor(db.reactionColors.neutral)
            else
                -- Friendly
                r, g, b = ns.UnpackColor(db.reactionColors.friendly)
            end
        end
    end

    hb.bar:SetStatusBarColor(r, g, b)
end
