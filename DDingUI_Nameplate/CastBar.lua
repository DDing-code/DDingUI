----------------------------------------------------------------------
-- DDingUI Nameplate - CastBar.lua
-- Cast bar creation, spell events, progress OnUpdate
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FLAT = ns.FLAT
local FONT = ns.FONT
local GetTime = GetTime

----------------------------------------------------------------------
-- Create cast bar -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.CreateCastBar(data)
    local parent = data.frame
    local db = ns.db.castBar

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetFrameLevel((parent:GetFrameLevel() or 0) + 3)
    frame:Hide()

    -- Background -- [NAMEPLATE]
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(FLAT)
    bg:SetAllPoints(frame)
    local bgColor = ns.GetSLColor("bg.input")
    bg:SetVertexColor(ns.UnpackColor(bgColor))

    -- StatusBar -- [NAMEPLATE]
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture(FLAT)
    bar:SetAllPoints(frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    -- Accent color for normal cast
    local accentColor
    if ns.SL and ns.SL.GetAccent then
        local from = ns.SL.GetAccent("Nameplate")
        if from then
            accentColor = from
        end
    end
    accentColor = accentColor or { 0.65, 0.35, 0.85, 1 }
    bar:SetStatusBarColor(accentColor[1], accentColor[2], accentColor[3])

    -- Border -- [NAMEPLATE]
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    local borderColor = ns.GetSLColor("border.default")
    border:SetBackdropBorderColor(ns.UnpackColor(borderColor))
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(frame:GetFrameLevel() + 1)

    -- Spell icon -- [NAMEPLATE]
    local icon = frame:CreateTexture(nil, "OVERLAY")
    local iconSize = db.iconSize or 14
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("RIGHT", frame, "LEFT", -2, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Icon border
    local iconBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    iconBorder:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    iconBorder:SetBackdropBorderColor(ns.UnpackColor(borderColor))
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    iconBorder:SetFrameLevel(frame:GetFrameLevel() + 1)

    -- Spell name text -- [NAMEPLATE]
    local spellName = bar:CreateFontString(nil, "OVERLAY")
    spellName:SetFont(FONT, 8, "OUTLINE")
    spellName:SetPoint("LEFT", bar, "LEFT", 2, 0)
    spellName:SetJustifyH("LEFT")
    local textColor = ns.GetSLColor("text.normal")
    spellName:SetTextColor(ns.UnpackColor(textColor))

    -- Timer text -- [NAMEPLATE]
    local timer = bar:CreateFontString(nil, "OVERLAY")
    timer:SetFont(FONT, 8, "OUTLINE")
    timer:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    timer:SetJustifyH("RIGHT")
    timer:SetTextColor(ns.UnpackColor(textColor))

    -- Shield texture (for uninterruptible casts) -- [NAMEPLATE]
    local shield = frame:CreateTexture(nil, "OVERLAY")
    shield:SetTexture("Interface\\CastingBar\\interrupt-bronze")
    shield:SetSize(iconSize + 6, iconSize + 6)
    shield:SetPoint("CENTER", icon, "CENTER", 0, 0)
    shield:Hide()

    data.castBar = {
        frame      = frame,
        bg         = bg,
        bar        = bar,
        border     = border,
        icon       = icon,
        iconBorder = iconBorder,
        spellName  = spellName,
        timer      = timer,
        shield     = shield,
        -- State
        casting    = false,
        channeling = false,
        startTime  = 0,
        endTime    = 0,
        notInterruptible = false,
        accentColor = accentColor,
    }

    -- Layout
    ns.LayoutCastBar(data)
end

----------------------------------------------------------------------
-- Layout cast bar -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.LayoutCastBar(data)
    local cb = data.castBar
    if not cb then return end

    local db = ns.db.castBar
    local hb = data.healthBar

    -- Position below health bar
    cb.frame:ClearAllPoints()
    if hb and hb.bar then
        cb.frame:SetPoint("TOPLEFT", hb.bar, "BOTTOMLEFT", 0, -2)
        cb.frame:SetPoint("TOPRIGHT", hb.bar, "BOTTOMRIGHT", 0, -2)
    else
        cb.frame:SetPoint("CENTER", data.frame, "CENTER", 0, -10)
        cb.frame:SetWidth(120)
    end
    cb.frame:SetHeight(db.height or 10)
end

----------------------------------------------------------------------
-- Cast event handler -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.OnCastEvent(data, unitID, event, ...)
    local cb = data.castBar
    if not cb or not ns.db.castBar.enabled then return end

    if event == "UNIT_SPELLCAST_START" then
        ns.StartCast(data, unitID, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        ns.StartCast(data, unitID, true)
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        ns.StopCast(data)
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        ns.UpdateCastDelay(data, unitID, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        ns.UpdateCastDelay(data, unitID, true)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        cb.notInterruptible = false
        ns.UpdateCastShield(data)
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        cb.notInterruptible = true
        ns.UpdateCastShield(data)
    end
end

----------------------------------------------------------------------
-- Start cast -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.StartCast(data, unitID, isChannel)
    local cb = data.castBar
    if not cb then return end

    local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID
    if isChannel then
        name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(unitID)
    else
        name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(unitID)
    end

    if not name then
        ns.StopCast(data)
        return
    end

    -- Secret value protection -- [NAMEPLATE]
    if spellID and issecretvalue and issecretvalue(spellID) then
        spellID = nil
    end

    local startTime = startTimeMS / 1000
    local endTime   = endTimeMS / 1000

    cb.casting    = not isChannel
    cb.channeling = isChannel
    cb.startTime  = startTime
    cb.endTime    = endTime
    cb.notInterruptible = notInterruptible or false

    -- Visuals
    if ns.db.castBar.showSpellName then
        cb.spellName:SetText(name)
        cb.spellName:Show()
    else
        cb.spellName:Hide()
    end

    if texture then
        cb.icon:SetTexture(texture)
        cb.icon:Show()
        cb.iconBorder:Show()
    else
        cb.icon:Hide()
        cb.iconBorder:Hide()
    end

    -- Shield
    ns.UpdateCastShield(data)

    -- Color: normal = accent, shielded = shielded color
    ns.UpdateCastBarColor(data)

    -- Layout
    ns.LayoutCastBar(data)

    -- Show and start OnUpdate -- [NAMEPLATE]
    cb.frame:Show()
    cb.frame:SetScript("OnUpdate", function(self, elapsed)
        ns.OnCastUpdate(data, elapsed)
    end)
end

----------------------------------------------------------------------
-- OnUpdate for cast progress -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.OnCastUpdate(data, elapsed)
    local cb = data.castBar
    if not cb then return end

    local now = GetTime()
    local startTime = cb.startTime
    local endTime   = cb.endTime

    if endTime <= startTime then
        ns.StopCast(data)
        return
    end

    local duration = endTime - startTime
    local progress

    if cb.channeling then
        progress = (endTime - now) / duration
    else
        progress = (now - startTime) / duration
    end

    if progress >= 1 or (not cb.channeling and now >= endTime) then
        ns.StopCast(data)
        return
    end

    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end

    cb.bar:SetValue(progress)

    -- Timer text -- [PERF] 0.1초 단위가 바뀔 때만 SetText
    if ns.db.castBar.showTimer then
        local remaining = endTime - now
        if remaining < 0 then remaining = 0 end
        local newTimerText = string.format("%.1f", remaining)
        if cb._lastTimerText ~= newTimerText then
            cb._lastTimerText = newTimerText
            cb.timer:SetText(newTimerText)
        end
        cb.timer:Show()
    else
        cb.timer:Hide()
    end
end

----------------------------------------------------------------------
-- Stop cast -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.StopCast(data)
    local cb = data.castBar
    if not cb then return end

    cb.casting    = false
    cb.channeling = false
    cb.frame:SetScript("OnUpdate", nil)
    cb.frame:Hide()
end

----------------------------------------------------------------------
-- Update cast when delayed -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateCastDelay(data, unitID, isChannel)
    local cb = data.castBar
    if not cb then return end

    local name, text, texture, startTimeMS, endTimeMS
    if isChannel then
        name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo(unitID)
    else
        name, text, texture, startTimeMS, endTimeMS = UnitCastingInfo(unitID)
    end

    if not name then
        ns.StopCast(data)
        return
    end

    cb.startTime = startTimeMS / 1000
    cb.endTime   = endTimeMS / 1000
end

----------------------------------------------------------------------
-- Update shield (interruptible indicator) -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateCastShield(data)
    local cb = data.castBar
    if not cb then return end

    if cb.notInterruptible and ns.db.castBar.showShield then
        cb.shield:Show()
    else
        cb.shield:Hide()
    end

    ns.UpdateCastBarColor(data)
end

----------------------------------------------------------------------
-- Cast bar color -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateCastBarColor(data)
    local cb = data.castBar
    if not cb then return end

    if cb.notInterruptible then
        local c = ns.db.castBar.shieldedColor
        cb.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        local c = cb.accentColor
        cb.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end
end

----------------------------------------------------------------------
-- Update cast bar on initial plate creation -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateCastBar(data, unitID)
    if not unitID or not ns.db.castBar.enabled then return end

    -- Check if unit is currently casting
    local name = UnitCastingInfo(unitID)
    if name then
        ns.StartCast(data, unitID, false)
        return
    end

    -- Check if unit is currently channeling
    name = UnitChannelInfo(unitID)
    if name then
        ns.StartCast(data, unitID, true)
        return
    end

    -- No active cast
    ns.StopCast(data)
end
