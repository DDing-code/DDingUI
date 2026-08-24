--[[
    DDingToolKit - FocusInterrupt Module
    ──────────────────────────────────────────────────────
    • 타겟 + 포커스 듀얼 castbar
    • C_Spell.IsSpellImportant → important 배경 깜빡임
    • 레이드 마커 아이콘
    • 타겟 지시자 (QuestLegendary 느낌표 깜빡임)
    • 대상 이름 직업 색상
    • EMPOWER 이벤트 지원
    • INTERRUPTIBLE / NOT_INTERRUPTIBLE 실시간 이벤트
    • Tooltip hover
    • 개별 Scale (target / focus)
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L  = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC")
    or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: "

local FocusInterrupt = {}
FocusInterrupt.name = "FocusInterrupt"
ns.FocusInterrupt = FocusInterrupt

------------------------------------------------------
-- State
------------------------------------------------------
local mainFrame      = nil
local eventFrame     = nil
local isEnabled      = false
local isTestMode     = false
local updateTicker   = nil
local lastFocusSoundTime = 0

-- Targeted indicator atlases
local targetedTexts = {}

local TEXT_POSITIONS = {
    LEFT = { "LEFT", "LEFT" },
    CENTER = { "CENTER", "CENTER" },
    RIGHT = { "RIGHT", "RIGHT" },
    ABOVE_LEFT = { "BOTTOMLEFT", "TOPLEFT" },
    ABOVE_CENTER = { "BOTTOM", "TOP" },
    ABOVE_RIGHT = { "BOTTOMRIGHT", "TOPRIGHT" },
    BELOW_LEFT = { "TOPLEFT", "BOTTOMLEFT" },
    BELOW_CENTER = { "TOP", "BOTTOM" },
    BELOW_RIGHT = { "TOPRIGHT", "BOTTOMRIGHT" },
}

local ATTACH_POSITIONS = {
    LEFT = { "RIGHT", "LEFT" },
    RIGHT = { "LEFT", "RIGHT" },
    TOP = { "BOTTOM", "TOP" },
    BOTTOM = { "TOP", "BOTTOM" },
}

local function NumberOr(value, fallback, minimum, maximum)
    local number = tonumber(value) or fallback
    if minimum and number < minimum then number = minimum end
    if maximum and number > maximum then number = maximum end
    return number
end

local function ColorValues(color, fallback)
    color = type(color) == "table" and color or fallback
    fallback = fallback or { 1, 1, 1, 1 }
    return color[1] or fallback[1], color[2] or fallback[2],
        color[3] or fallback[3], color[4] or fallback[4] or 1
end

local function SetRegionPosition(region, parent, position, offsetX, offsetY)
    local points = TEXT_POSITIONS[position] or TEXT_POSITIONS.CENTER
    region:ClearAllPoints()
    region:SetPoint(points[1], parent, points[2], offsetX or 0, offsetY or 0)
end

local function SetAttachedPosition(region, parent, position, offsetX, offsetY)
    local points = ATTACH_POSITIONS[position] or ATTACH_POSITIONS.LEFT
    region:ClearAllPoints()
    region:SetPoint(points[1], parent, points[2], offsetX or 0, offsetY or 0)
end

local function ApplyFontStyle(fontString, font, size, outline, color)
    size = NumberOr(size, 12, 1, 96)
    outline = type(outline) == "string" and outline or ""
    if not fontString:SetFont(font or SL_FONT, size, outline) then
        fontString:SetFont(SL_FONT, size, outline)
    end
    fontString:SetTextColor(ColorValues(color, { 1, 1, 1, 1 }))
end

local function UpdateTargetedTexts(size)
    if not CreateAtlasMarkup then return end
    size = NumberOr(size, 16, 8, 64)
    targetedTexts[1] = CreateAtlasMarkup("QuestLegendary", size, size, 0, 0, 255, 0, 0)
    targetedTexts[2] = CreateAtlasMarkup("QuestLegendary", size, size, 0, 0)
end

local function ApplyCastbarStyle(bar, db)
    if not bar or not db then return end

    local barHeight = NumberOr(db.barHeight, 17, 8, 100)
    local iconWidth = NumberOr(db.iconWidth, 23, 8, 100)
    local iconHeight = NumberOr(db.iconHeight, 19, 8, 100)
    local showIcon = db.showIcon ~= false
    local iconPosition = db.iconPosition or "LEFT"
    local iconConsumesWidth = showIcon and (iconPosition == "LEFT" or iconPosition == "RIGHT")
    local barWidth = NumberOr(db.barWidth, 180, 60, 1000)
    if iconConsumesWidth then
        barWidth = math.max(40, barWidth - iconWidth)
    end

    bar:SetSize(barWidth, barHeight)
    bar:SetFrameStrata(db.frameStrata or "LOW")
    bar:SetAlpha(NumberOr(db.barAlpha, 1, 0, 1))
    bar:SetStatusBarTexture(db.texture or "RaidFrame-Hp-Fill")

    local statusTexture = bar:GetStatusBarTexture()
    if statusTexture then statusTexture:SetHorizTile(false) end

    local borderSize = NumberOr(db.barBorderSize, 1, 0, 12)
    local bgR, bgG, bgB = ColorValues(db.backgroundColor, { 0, 0, 0, 1 })
    bar.bg:ClearAllPoints()
    bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -borderSize, borderSize)
    bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", borderSize, -borderSize)
    bar.bg:SetColorTexture(bgR, bgG, bgB, NumberOr(db.bgAlpha, 0.8, 0, 1))

    bar.notinterruptable:ClearAllPoints()
    if statusTexture then
        bar.notinterruptable:SetPoint("TOPLEFT", statusTexture, "TOPLEFT")
        bar.notinterruptable:SetPoint("BOTTOMRIGHT", statusTexture, "BOTTOMRIGHT")
    else
        bar.notinterruptable:SetAllPoints(bar)
    end
    if db.texture == "RaidFrame-Hp-Fill" and bar.notinterruptable.SetAtlas then
        bar.notinterruptable:SetAtlas("RaidFrame-Hp-Fill")
    else
        bar.notinterruptable:SetTexture(db.texture or SL_FLAT)
    end
    local notR, notG, notB = ColorValues(db.notInterruptibleColor, { 0.9, 0.9, 0.9, 1 })
    local notAlpha = NumberOr(db.notInterruptibleAlpha, 1, 0, 1)
    local notColorSpec = { notR, notG, notB, notAlpha }
    if SL and SL.CopyBarColorMetadata then
        SL.CopyBarColorMetadata(notColorSpec, db.notInterruptibleColor)
        if type(notColorSpec.gradientColor) == "table" then
            notColorSpec.gradientColor[4] = notAlpha
        end
    end
    if SL and SL.ApplyBarColorToTexture then
        SL.ApplyBarColorToTexture(bar.notinterruptable, notColorSpec)
    else
        bar.notinterruptable:SetVertexColor(notR, notG, notB, notAlpha)
    end

    bar.important:ClearAllPoints()
    bar.important:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
    bar.important:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
    local impR, impG, impB, impA = ColorValues(db.importantAlertColor, { 1, 0, 0, 1 })
    if db.showImportantAlert == false then impA = 0 end
    bar.important:SetColorTexture(
        impR, impG, impB,
        NumberOr(db.importantAlertAlpha, impA, 0, 1) * impA
    )

    ApplyFontStyle(
        bar.name,
        db.spellNameFont or db.font,
        db.spellNameFontSize or barHeight * 0.7,
        db.spellNameOutline,
        db.spellNameColor
    )
    SetRegionPosition(
        bar.name, bar, db.spellNamePosition or "LEFT",
        NumberOr(db.spellNameOffsetX, 3),
        NumberOr(db.spellNameOffsetY, 0)
    )
    bar.name:SetShown(db.showSpellName ~= false)

    ApplyFontStyle(
        bar.time,
        db.timeTextFont or db.font,
        db.timeTextFontSize or barHeight * 0.5,
        db.timeTextOutline,
        db.timeTextColor
    )
    SetRegionPosition(
        bar.time, bar, db.timeTextPosition or "RIGHT",
        NumberOr(db.timeTextOffsetX, -3),
        NumberOr(db.timeTextOffsetY, 0)
    )
    bar.time:SetShown(db.showTimeText ~= false)

    ApplyFontStyle(
        bar.targetname,
        db.targetTextFont or db.font,
        db.targetTextFontSize or barHeight * 0.7,
        db.targetTextOutline,
        db.targetTextColor
    )
    SetRegionPosition(
        bar.targetname, bar, db.targetTextPosition or "BELOW_RIGHT",
        NumberOr(db.targetTextOffsetX, 0),
        NumberOr(db.targetTextOffsetY, -2)
    )
    bar.targetname:SetShown(db.showTargetText ~= false)

    bar.button:SetSize(iconWidth, iconHeight)
    SetAttachedPosition(
        bar.button, bar, iconPosition,
        NumberOr(db.iconOffsetX, -1),
        NumberOr(db.iconOffsetY, 0)
    )
    local iconBorderSize = NumberOr(db.iconBorderSize, 1, 0, math.min(iconWidth, iconHeight) / 2)
    local borderR, borderG, borderB, borderA = ColorValues(db.iconBorderColor, { 0, 0, 0, 1 })
    bar.button.border:SetVertexColor(borderR, borderG, borderB, borderA)
    bar.button.icon:ClearAllPoints()
    bar.button.icon:SetPoint("TOPLEFT", bar.button, "TOPLEFT", iconBorderSize, -iconBorderSize)
    bar.button.icon:SetPoint("BOTTOMRIGHT", bar.button, "BOTTOMRIGHT", -iconBorderSize, iconBorderSize)
    local iconZoom = NumberOr(db.iconZoom, 0.08, 0, 0.45)
    bar.button.icon:SetTexCoord(iconZoom, 1 - iconZoom, iconZoom, 1 - iconZoom)
    bar.button:SetShown(showIcon)

    local markerSize = NumberOr(db.raidMarkerSize, 15, 6, 64)
    bar.mark:SetSize(markerSize, markerSize)
    local markerPosition = db.raidMarkerPosition or "LEFT"
    local markerParent = showIcon and markerPosition == iconPosition and bar.button or bar
    SetAttachedPosition(
        bar.mark, markerParent, markerPosition,
        NumberOr(db.raidMarkerOffsetX, -1),
        NumberOr(db.raidMarkerOffsetY, 0)
    )
    bar.mark._enabled = db.showRaidMarker ~= false
    if not bar.mark._enabled then bar.mark:Hide() end

    local indicatorSize = NumberOr(db.targetIndicatorSize, 16, 8, 64)
    ApplyFontStyle(bar.targetedindi, db.font, indicatorSize, "OUTLINE", db.targetIndicatorColor)
    SetAttachedPosition(
        bar.targetedindi, bar, db.targetIndicatorPosition or "RIGHT",
        NumberOr(db.targetIndicatorOffsetX, 0),
        NumberOr(db.targetIndicatorOffsetY, 1)
    )
    bar.targetedindi._enabled = db.showTargetIndicator ~= false
    if not bar.targetedindi._enabled then bar.targetedindi:SetAlpha(0) end
    UpdateTargetedTexts(indicatorSize)

    bar._interruptColor = db.interruptibleColor or { 204/255, 1, 153/255 }
    bar._failedColor = db.interruptedColor or { 1, 0, 0 }
    bar._db = db
end

local function IsInterruptibleForSound(notInterruptible)
    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local notInterruptibleValue = C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 1, 0)
        if issecretvalue and issecretvalue(notInterruptibleValue) then return false end
        return (tonumber(notInterruptibleValue) or 0) < 0.5
    end

    if issecretvalue and issecretvalue(notInterruptible) then return false end
    return not notInterruptible
end

local function PlayFocusCastSound(unit, notInterruptible)
    local db = FocusInterrupt.db or (ns.db and ns.db.profile and ns.db.profile.FocusInterrupt)
    if not db or not db.focusSoundEnabled then return end
    if isTestMode then return end
    if not unit or not UnitExists(unit) or not UnitCanAttack or not UnitCanAttack("player", unit) then return end
    if not IsInterruptibleForSound(notInterruptible) then return end

    local now = GetTime()
    local cooldown = tonumber(db.focusSoundCooldown) or 0
    if cooldown > 0 and (now - lastFocusSoundTime) < cooldown then
        return
    end
    lastFocusSoundTime = now

    local channel = db.focusSoundChannel or "Master"
    local soundFile = db.focusSoundFile
    local customPath = db.focusSoundCustomPath
    local raidWarningSound = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    if ns.RequestSound then
        ns:RequestSound({
            source = "FocusInterrupt",
            key = "interruptible-cast",
            soundFile = soundFile,
            customPath = customPath,
            soundKit = raidWarningSound,
            channel = channel,
            priority = 110,
        })
    elseif (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
        if ns.PlaySound then
            ns:PlaySound(soundFile, channel, customPath)
        elseif customPath and customPath ~= "" then
            PlaySoundFile(customPath, channel)
        elseif soundFile and soundFile ~= "" then
            PlaySoundFile(soundFile, channel)
        end
    else
        PlaySound(raidWarningSound, channel)
    end
end

------------------------------------------------------
-- Castbar factory
------------------------------------------------------
local function CreateCastbar(db)
    -- StatusBar
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetStatusBarTexture("RaidFrame-Hp-Fill")
    local stex = bar:GetStatusBarTexture()
    if stex then stex:SetHorizTile(false) end
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)
    bar:SetStatusBarColor(1, 0.9, 0.9)

    -- notInterruptible overlay
    bar.notinterruptable = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.notinterruptable:SetPoint("TOPLEFT", stex, "TOPLEFT")
    bar.notinterruptable:SetPoint("BOTTOMRIGHT", stex, "BOTTOMRIGHT")
    bar.notinterruptable:SetAtlas("RaidFrame-Hp-Fill")
    bar.notinterruptable:SetVertexColor(0.9, 0.9, 0.9)
    bar.notinterruptable:SetAlpha(0)
    bar.notinterruptable:Show()

    -- important blink bg
    bar.important = bar:CreateTexture(nil, "BACKGROUND")
    bar.important:SetDrawLayer("BACKGROUND", -6)
    bar.important:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
    bar.important:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
    bar.important:SetColorTexture(1, 0, 0, 1)
    bar.important:SetAlpha(0)
    bar.important:Show()

    -- bg
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    bar.bg:SetColorTexture(0, 0, 0, 0.8)
    bar.bg:Show()

    -- spell name
    bar.name = bar:CreateFontString(nil, "OVERLAY")
    bar.name:SetFont(SL_FONT, 12)
    bar.name:SetPoint("LEFT", bar, "LEFT", 3, 0)

    -- time
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetFont(SL_FONT, 9)
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -3, 0)

    -- tooltip
    bar:EnableMouse(false)
    bar:SetMouseMotionEnabled(true)
    bar:SetScript("OnEnter", function(self)
        if self.castspellid then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetSpellByID(self.castspellid)
        end
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar.isAlert = false
    bar:Hide()

    -- spell icon (left side)
    bar.button = CreateFrame("Button", nil, bar)
    bar.button:SetPoint("RIGHT", bar, "LEFT", -1, 0)
    bar.button:SetSize(23, 19)
    bar.button:EnableMouse(false)

    bar.button.border = bar.button:CreateTexture(nil, "BACKGROUND")
    bar.button.border:SetAllPoints()
    bar.button.border:SetTexture(SL_FLAT)
    bar.button.border:SetVertexColor(0, 0, 0)
    bar.button.border:Show()

    bar.button.icon = bar.button:CreateTexture(nil, "ARTWORK")
    bar.button.icon:SetPoint("TOPLEFT", bar.button, "TOPLEFT", 1, -1)
    bar.button.icon:SetPoint("BOTTOMRIGHT", bar.button, "BOTTOMRIGHT", -1, 1)
    bar.button.icon:SetTexCoord(0.08, 0.92, 0.16, 0.84)
    bar.button:Show()

    -- target name (below bar, class-colored)
    bar.targetname = bar:CreateFontString(nil, "ARTWORK")
    bar.targetname:SetFont(SL_FONT, 12)
    bar.targetname:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)

    -- raid marker
    bar.mark = bar:CreateTexture(nil, "ARTWORK")
    bar.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    bar.mark:SetSize(15, 15)
    bar.mark:SetPoint("RIGHT", bar.button, "LEFT", -1, 0)

    -- Targeted indicator
    bar.targetedindi = bar:CreateFontString(nil, "ARTWORK")
    bar.targetedindi:SetFont(SL_FONT, 16, "OUTLINE")
    bar.targetedindi:SetPoint("LEFT", bar, "RIGHT", 0, 1)
    bar.targetedindi:Show()

    -- internal state
    bar.start = 0
    bar.duration = 0
    bar.duration_obj = nil
    bar.failstart = nil
    bar.targetedinditype = 1
    -- draggable
    bar:SetMovable(true)

    ApplyCastbarStyle(bar, db)
    return bar
end

------------------------------------------------------
-- Hide / Show raidicon
------------------------------------------------------
local function HideCastbar(bar)
    bar:SetValue(0)
    bar:Hide()
    bar.isAlert = false
    bar.targetname:SetText("")
    bar.targetname:Hide()
    bar.failstart = nil
    bar.duration_obj = nil
    bar.important:SetAlpha(0)
    bar.targetedindi:SetAlpha(0)
    bar.notinterruptable:SetAlpha(0)
end

local function ShowRaidIcon(unit, markTex)
    if not markTex._enabled then
        markTex:Hide()
        return
    end
    local idx = GetRaidTargetIndex(unit)
    if idx then
        SetRaidTargetIconTexture(markTex, idx)
        markTex:Show()
    else
        markTex:Hide()
    end
end

local function GetInterruptText(guid)
    if guid then
        local name = UnitNameFromGUID(guid)
        if issecretvalue and issecretvalue(name) then
            return L["FOCUSINTERRUPT_INTERRUPTED"] or INTERRUPTED or "Interrupted"
        end
        if name and SPELL_INTERRUPTED_BY then
            return SPELL_INTERRUPTED_BY:format(name)
        end
    end
    return L["FOCUSINTERRUPT_INTERRUPTED"] or INTERRUPTED or "Interrupted"
end

------------------------------------------------------
-- Cast state update
------------------------------------------------------
local function CheckCasting(bar, event, interruptedBy)
    if not bar then return end
    local unit = bar.unit
    local db = bar._db or FocusInterrupt.db or {}
    if (unit == "target" and db.showTarget == false)
        or (unit == "focus" and db.showFocus == false) then
        HideCastbar(bar)
        return
    end
    if not UnitExists(unit) then HideCastbar(bar); return end

    local currtime = GetTime()

    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(100)
        if db.showTimeText ~= false then
            bar.time:SetText(L["FOCUSINTERRUPT_INTERRUPTED"] or INTERRUPTED)
        end
        local c = bar._failedColor
        if SL and SL.ApplyBarColor then
            SL.ApplyBarColor(bar, c)
        else
            bar:SetStatusBarColor(c[1], c[2], c[3])
        end
        bar.failstart = currtime
        bar:SetStatusBarDesaturated(false)
        bar.duration_obj = nil
        if interruptedBy and db.showTargetText ~= false then
            bar.targetname:SetText(GetInterruptText(interruptedBy))
            bar.targetname:SetTextColor(ColorValues(db.targetTextColor, { 1, 1, 1, 1 }))
            bar.targetname:Show()
        else
            bar.targetname:SetText("")
            bar.targetname:Hide()
        end
        bar.important:SetAlpha(0)
        bar.targetedindi:SetAlpha(0)
        bar.notinterruptable:SetAlpha(0)
        bar:Show()
        return
    end

    -- casting / channeling / empowering
    local bchannel = false
    local name, _, texture, start, endTime, _, _, notInterruptible, spellid = UnitCastingInfo(unit)
    if not name then
        name, _, texture, start, endTime, _, notInterruptible, spellid = UnitChannelInfo(unit)
        bchannel = true
    end

    if name then
        local wasShown = bar:IsShown()

        -- duration object
        local duration
        if bchannel then
            duration = UnitChannelDuration and UnitChannelDuration(unit)
        else
            duration = UnitCastingDuration and UnitCastingDuration(unit)
        end
        bar.duration_obj = duration

        bar.button.icon:SetTexture(texture)
        bar:SetReverseFill(bchannel)
        bar:SetMinMaxValues(start, endTime)
        bar.failstart = nil
        bar.castspellid = spellid

        local c = bar._interruptColor
        if SL and SL.ApplyBarColor then
            SL.ApplyBarColor(bar, c)
        else
            bar:SetStatusBarColor(c[1], c[2], c[3])
        end
        bar.name:SetText(name)
        ShowRaidIcon(unit, bar.mark)
        bar.button.icon:SetShown(db.showIcon ~= false)
        bar:Show()
        if unit == "focus" and not wasShown then
            PlayFocusCastSound(unit, notInterruptible)
        end

        -- important (C_CurveUtil secret-safe)
        if db.showImportantAlert ~= false
            and C_Spell.IsSpellImportant
            and C_CurveUtil
            and C_CurveUtil.EvaluateColorValueFromBoolean then
            local imp = C_Spell.IsSpellImportant(spellid)
            bar.important:Show()
            bar.important:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(imp, 1, 0))
        else
            bar.important:SetAlpha(0)
        end

        -- targeted indicator
        if bar.targetedindi._enabled
            and C_CurveUtil
            and C_CurveUtil.EvaluateColorValueFromBoolean then
            local tgt = UnitIsUnit(unit .. "target", "player")
            bar.targetedindi:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(tgt, 1, 0))
        else
            bar.targetedindi:SetAlpha(0)
        end

        -- Secret-safe non-interruptible overlay
        local alpha = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean and C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 1, 0) or 0
        bar.notinterruptable:SetAlpha(alpha)

        -- target name (class-colored)
        local tt = unit .. "target"
        if db.showTargetText ~= false and UnitExists(tt) then
            local _, cls = UnitClass(tt)
            local usedClassColor = false
            local classIsSecret = issecretvalue and issecretvalue(cls)
            if db.targetTextUseClassColor ~= false
                and not classIsSecret
                and cls then
                local cc = RAID_CLASS_COLORS[cls]
                if cc then
                    bar.targetname:SetTextColor(cc.r, cc.g, cc.b)
                    usedClassColor = true
                end
            end
            if not usedClassColor then
                bar.targetname:SetTextColor(ColorValues(db.targetTextColor, { 1, 1, 1, 1 }))
            end
            bar.targetname:SetText(UnitName(tt))
            bar.targetname:Show()
        else
            bar.targetname:SetText("")
            bar.targetname:Hide()
        end
    else
        if not bar.failstart then HideCastbar(bar) end
    end
end

------------------------------------------------------
-- Unit event handler
------------------------------------------------------
local function OnUnitEvent(bar, event, ...)
    local interruptedBy = nil

    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        interruptedBy = select(4, ...)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        interruptedBy = select(4, ...)
        if interruptedBy ~= nil then
            event = "UNIT_SPELLCAST_INTERRUPTED"
        end
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        local _, _, _, complete, interrupted = ...
        interruptedBy = interrupted
        if not (issecretvalue and issecretvalue(complete)) and not complete then
            event = "UNIT_SPELLCAST_INTERRUPTED"
        end
    end
    CheckCasting(bar, event, interruptedBy)
end

------------------------------------------------------
-- Register unit events
------------------------------------------------------
local function RegisterUnit(bar, unit)
    bar.unit = unit
    bar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    bar:RegisterUnitEvent("UNIT_TARGET", unit)
end

local function CheckUnit(bar, unit)
    if not bar then return end
    if not UnitExists(unit) then HideCastbar(bar); return end
    bar.failstart = nil
    CheckCasting(bar, "NOTHING")
end

------------------------------------------------------
-- Tick update
------------------------------------------------------
local updateCount = 1

local function UpdateCastbar(bar)
    if not bar:IsShown() then return end

    local current = GetTime()
    if bar.failstart then
        local holdTime = NumberOr(bar._db and bar._db.interruptedHoldTime, 1, 0, 10)
        if current - bar.failstart > holdTime then HideCastbar(bar) end
    else
        local db = bar._db or {}
        if bar.duration_obj and db.showTimeText ~= false then
            local decimals = math.floor(NumberOr(db.timeTextDecimals, 1, 0, 2))
            local formatString = "%." .. decimals .. "f"
            local remaining = bar.duration_obj:GetRemainingDuration(0)
            local total = bar.duration_obj:GetTotalDuration(0)
            if db.timeTextFormat == "REMAINING" then
                bar.time:SetText(string.format(formatString, remaining))
            elseif db.timeTextFormat == "TOTAL" then
                bar.time:SetText(string.format(formatString, total))
            else
                bar.time:SetText(string.format(formatString .. "/" .. formatString, remaining, total))
            end
        end
        bar:SetValue(current * 1000, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil)
    end
end

local function OnTick()
    if not isTestMode then
        if ns.targetcastbar then UpdateCastbar(ns.targetcastbar) end
        if ns.focuscastbar  then UpdateCastbar(ns.focuscastbar) end
    end

    updateCount = updateCount + 1
    if updateCount > 3 then
        -- targeted indicator blink
        for _, bar in ipairs({ ns.targetcastbar, ns.focuscastbar }) do
            if bar and bar:IsShown() then
                if #targetedTexts > 0 then
                    if bar.targetedindi._enabled then
                        bar.targetedindi:SetText(targetedTexts[bar.targetedinditype] or "")
                    end
                    bar.targetedinditype = bar.targetedinditype + 1
                    if bar.targetedinditype > #targetedTexts then bar.targetedinditype = 1 end
                end
                if bar._db and bar._db.showImportantAlert ~= false then
                    if bar.important:IsShown() then bar.important:Hide() else bar.important:Show() end
                else
                    bar.important:Hide()
                end
            end
        end
        updateCount = 1
    end
end

------------------------------------------------------
-- Module lifecycle
------------------------------------------------------
function FocusInterrupt:OnInitialize()
    self.db = ns.db.profile.FocusInterrupt
end

function FocusInterrupt:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.FocusInterrupt then
            self.db = ns.db.profile.FocusInterrupt
        else return end
    end
    isEnabled = true
    self:Init()
end

function FocusInterrupt:OnDisable()
    if ns.CancelManagedSoundsBySource then ns:CancelManagedSoundsBySource("FocusInterrupt") end
    isEnabled = false
    isTestMode = false
    if ns.targetcastbar then
        HideCastbar(ns.targetcastbar)
        ns.targetcastbar:UnregisterAllEvents()
        ns.targetcastbar:EnableMouse(false)
        ns.targetcastbar:SetMouseMotionEnabled(false)
    end
    if ns.focuscastbar then
        HideCastbar(ns.focuscastbar)
        ns.focuscastbar:UnregisterAllEvents()
        ns.focuscastbar:EnableMouse(false)
        ns.focuscastbar:SetMouseMotionEnabled(false)
    end
    if eventFrame then eventFrame:UnregisterAllEvents() end
    if updateTicker then updateTicker:Cancel(); updateTicker = nil end
end

function FocusInterrupt:Init()
    local db = self.db

    if not mainFrame then
        mainFrame = CreateFrame("Frame", nil, UIParent)
        mainFrame:SetSize(1, 1)
        mainFrame:SetPoint("BOTTOM", UIParent, "BOTTOM")
        mainFrame:Show()
    end

    -- target castbar
    if not ns.targetcastbar then
        ns.targetcastbar = CreateCastbar(db)
        local tpos = db.targetPosition or {}
        ns.targetcastbar:SetPoint(tpos.point or "CENTER", UIParent, tpos.relativePoint or "CENTER",
            tpos.x or 0, tpos.y or -100)
        ns.targetcastbar:SetScript("OnEvent", OnUnitEvent)
    end
    ApplyCastbarStyle(ns.targetcastbar, db)
    ns.targetcastbar:SetScale(db.targetScale or 1.0)
    ns.targetcastbar:SetMouseMotionEnabled(true)
    RegisterUnit(ns.targetcastbar, "target")

    -- focus castbar
    if not ns.focuscastbar then
        ns.focuscastbar = CreateCastbar(db)
        local fpos = db.focusPosition or {}
        ns.focuscastbar:SetPoint(fpos.point or "CENTER", UIParent, fpos.relativePoint or "CENTER",
            fpos.x or 0, fpos.y or 50)
        ns.focuscastbar:SetScript("OnEvent", OnUnitEvent)
    end
    ApplyCastbarStyle(ns.focuscastbar, db)
    ns.focuscastbar:SetScale(db.focusScale or 1.2)
    ns.focuscastbar:SetMouseMotionEnabled(true)
    RegisterUnit(ns.focuscastbar, "focus")

    -- global events
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_TARGET_CHANGED" then
                CheckUnit(ns.targetcastbar, "target")
            elseif event == "PLAYER_FOCUS_CHANGED" then
                CheckUnit(ns.focuscastbar, "focus")
            elseif event == "PLAYER_ENTERING_WORLD" then
                CheckUnit(ns.targetcastbar, "target")
                CheckUnit(ns.focuscastbar, "focus")
            end
        end)
    end
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    CheckUnit(ns.targetcastbar, "target")
    CheckUnit(ns.focuscastbar, "focus")

    -- tick update
    if updateTicker then updateTicker:Cancel() end
    updateTicker = C_Timer.NewTicker(db.updateRate or 0.1, OnTick)
end

------------------------------------------------------
-- Style / Position
------------------------------------------------------
function FocusInterrupt:UpdateStyle()
    self.db = ns.db and ns.db.profile and ns.db.profile.FocusInterrupt or self.db
    local db = self.db
    if not db then return end

    if not mainFrame then
        if isEnabled or isTestMode then self:Init() end
        return
    end

    if ns.targetcastbar then
        ApplyCastbarStyle(ns.targetcastbar, db)
        ns.targetcastbar:SetScale(db.targetScale or 1)
    end
    if ns.focuscastbar then
        ApplyCastbarStyle(ns.focuscastbar, db)
        ns.focuscastbar:SetScale(db.focusScale or 1.2)
    end

    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
    if isEnabled or isTestMode then
        updateTicker = C_Timer.NewTicker(db.updateRate or 0.1, OnTick)
    end

    if isEnabled and not isTestMode then
        CheckUnit(ns.targetcastbar, "target")
        CheckUnit(ns.focuscastbar, "focus")
    elseif not isTestMode then
        if ns.targetcastbar then HideCastbar(ns.targetcastbar) end
        if ns.focuscastbar then HideCastbar(ns.focuscastbar) end
    end
end

local styleRefreshSerial = 0

function FocusInterrupt:QueueStyleRefresh()
    styleRefreshSerial = styleRefreshSerial + 1
    local serial = styleRefreshSerial
    C_Timer.After(0.04, function()
        if serial ~= styleRefreshSerial then return end
        FocusInterrupt:UpdateStyle()
        if isTestMode then FocusInterrupt:RefreshEditPreview() end
    end)
end

function FocusInterrupt:ResetPosition()
    local db = self.db
    if ns.targetcastbar then
        ns.targetcastbar:ClearAllPoints()
        ns.targetcastbar:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
        db.targetPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -100 }
    end
    if ns.focuscastbar then
        ns.focuscastbar:ClearAllPoints()
        ns.focuscastbar:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
        db.focusPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 50 }
    end
end

local function PopulatePreviewBar(bar, label)
    if not bar then return end
    local db = FocusInterrupt.db or {}
    ApplyCastbarStyle(bar, db)
    bar.button.icon:SetTexture(134400)
    bar.name:SetText(label == "focus" and "Focus Spell" or "Target Spell")
    bar.time:SetText("1.8/2.5")
    bar.targetname:SetText(label == "focus" and "Focus Target" or "Target")
    bar.targetname:SetTextColor(ColorValues(db.targetTextColor, { 1, 1, 1, 1 }))
    bar.targetname:SetShown(db.showTargetText ~= false)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(50)
    if SL and SL.ApplyBarColor then
        SL.ApplyBarColor(bar, bar._interruptColor)
    else
        bar:SetStatusBarColor(bar._interruptColor[1], bar._interruptColor[2], bar._interruptColor[3])
    end
    bar.notinterruptable:SetAlpha(0)
    bar.important:SetAlpha(db.showImportantAlert ~= false and 0.65 or 0)
    if bar.mark._enabled then
        SetRaidTargetIconTexture(bar.mark, label == "focus" and 4 or 8)
        bar.mark:Show()
    else
        bar.mark:Hide()
    end
    if bar.targetedindi._enabled then
        bar.targetedindi:SetText(targetedTexts[1] or "!")
        bar.targetedindi:SetAlpha(1)
    else
        bar.targetedindi:SetAlpha(0)
    end
    bar.failstart = nil
    bar.duration_obj = nil
    bar:SetAlpha(NumberOr(db.barAlpha, 1, 0, 1))
    bar:Show()
end

local function RestoreRuntimeAfterPreview()
    if isEnabled then
        CheckUnit(ns.targetcastbar, "target")
        CheckUnit(ns.focuscastbar, "focus")
        return
    end
    if ns.targetcastbar then ns.targetcastbar:UnregisterAllEvents() end
    if ns.focuscastbar then ns.focuscastbar:UnregisterAllEvents() end
    if eventFrame then eventFrame:UnregisterAllEvents() end
    if updateTicker then updateTicker:Cancel(); updateTicker = nil end
end

------------------------------------------------------
-- Test Mode
------------------------------------------------------
function FocusInterrupt:TestMode()
    if not self.db then
        self.db = ns.db and ns.db.profile and ns.db.profile.FocusInterrupt
    end
    if not mainFrame then
        self:Init()
    end

    isTestMode = not isTestMode

    if isTestMode then
        for label, bar in pairs({ target = ns.targetcastbar, focus = ns.focuscastbar }) do
            if bar then
                bar:EnableMouse(true)
                bar:RegisterForDrag("LeftButton")
                bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
                bar:SetScript("OnDragStop", function(self)
                    self:StopMovingOrSizing()
                    local p, _, rp, x, y = self:GetPoint()
                    local key = (label == "target") and "targetPosition" or "focusPosition"
                    FocusInterrupt.db[key] = { point = p, relativePoint = rp, x = x, y = y }
                end)
                if ns.EnableRightClickMouselook then
                    ns:EnableRightClickMouselook(bar)
                end
                bar:SetScript("OnUpdate", nil)
                PopulatePreviewBar(bar, label)
            end
        end
        print(CHAT_PREFIX .. "FocusInterrupt " .. L["TEST_MODE"] .. " ON")
    else
        for _, bar in pairs({ ns.targetcastbar, ns.focuscastbar }) do
            if bar then
                bar:EnableMouse(false)
                bar:SetScript("OnDragStart", nil)
                bar:SetScript("OnDragStop", nil)
                HideCastbar(bar)
            end
        end
        RestoreRuntimeAfterPreview()
        print(CHAT_PREFIX .. "FocusInterrupt " .. L["TEST_MODE"] .. " OFF")
    end
end

function FocusInterrupt:IsTestMode() return isTestMode end

------------------------------------------------------
-- Edit mode (Movers)
------------------------------------------------------
function FocusInterrupt:EnterEditPreview()
    if isTestMode then return end
    if not self.db then
        self.db = ns.db and ns.db.profile and ns.db.profile.FocusInterrupt
    end
    if not mainFrame then
        self:Init()
    end
    isTestMode = true
    for label, bar in pairs({ target = ns.targetcastbar, focus = ns.focuscastbar }) do
        if bar then
            bar:SetScript("OnUpdate", nil)
            PopulatePreviewBar(bar, label)
        end
    end
end

function FocusInterrupt:RefreshEditPreview()
    if not isTestMode then return end
    for label, bar in pairs({ target = ns.targetcastbar, focus = ns.focuscastbar }) do
        PopulatePreviewBar(bar, label)
    end
end

function FocusInterrupt:ExitEditPreview()
    if not isTestMode then return end
    isTestMode = false
    for _, bar in pairs({ ns.targetcastbar, ns.focuscastbar }) do
        if bar then HideCastbar(bar) end
    end
    RestoreRuntimeAfterPreview()
end

-- 모듈 등록
DDingToolKit:RegisterModule("FocusInterrupt", FocusInterrupt)
