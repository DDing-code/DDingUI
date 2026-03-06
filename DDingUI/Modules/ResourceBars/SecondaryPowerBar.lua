local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

-- Local API caching for hot paths
local string_format = string.format
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local GetTime = GetTime
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local wipe = wipe

-- Reusable tables for Essence/Rune update functions (avoid per-frame allocation)
local _displayOrder = {}
local _stateList = {}
local _readyList = {}
local _cdList = {}
local _readyLookup = {}
local _cdLookup = {}

-- Marker color overlay helper: clip frame + overlay StatusBar (secret value safe)
-- Also handles max color overlay (no numeric comparison needed)
local _defaultMarkerColors = {
    {1, 0.3, 0.3, 1}, {1, 1, 0.3, 1}, {0.3, 1, 0.3, 1},
    {0.3, 0.7, 1, 1}, {1, 0.5, 1, 1},
}

local function UpdateMarkerColorOverlays(bar, cfg, current, max, interpolation)
    local mainTex = bar.StatusBar:GetStatusBarTexture()
    local texPath = mainTex and mainTex:GetTexture()

    -- Marker color overlays
    if cfg.markerColorChange and cfg.markers and #cfg.markers > 0 then
        local barWidth = bar.StatusBar:GetWidth()
        if barWidth > 0 and max and max > 0 then
            bar._markerOverlays = bar._markerOverlays or {}
            local mbc = cfg.markerBarColors or {}

            for i, rawVal in ipairs(cfg.markers) do
                local mVal = type(rawVal) == "table" and rawVal.value or rawVal
                local mc = mbc[i] or _defaultMarkerColors[i] or _defaultMarkerColors[1]
                if mVal and type(mVal) == "number" and mVal > 0 and mVal < max and mc then
                    local markerPx = (mVal / max) * barWidth

                    if not bar._markerOverlays[i] then
                        local clip = CreateFrame("Frame", nil, bar)
                        clip:SetClipsChildren(true)
                        local ov = CreateFrame("StatusBar", nil, clip)
                        bar._markerOverlays[i] = { clip = clip, bar = ov }
                    end

                    local mo = bar._markerOverlays[i]
                    mo.clip:ClearAllPoints()
                    mo.clip:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT", markerPx, 0)
                    mo.clip:SetPoint("BOTTOMRIGHT", bar.StatusBar, "BOTTOMRIGHT", 0, 0)
                    mo.clip:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 1 + i)

                    mo.bar:ClearAllPoints()
                    mo.bar:SetAllPoints(bar.StatusBar)
                    mo.bar:SetMinMaxValues(0, max, interpolation)
                    mo.bar:SetValue(current, interpolation)
                    if texPath then mo.bar:SetStatusBarTexture(texPath) end
                    mo.bar:SetStatusBarColor(mc[1], mc[2], mc[3], mc[4] or 1)

                    mo.clip:Show()
                    mo.bar:Show()
                elseif bar._markerOverlays[i] then
                    bar._markerOverlays[i].clip:Hide()
                end
            end

            for i = #cfg.markers + 1, #bar._markerOverlays do
                bar._markerOverlays[i].clip:Hide()
            end
        end
    else
        if bar._markerOverlays then
            for _, mo in ipairs(bar._markerOverlays) do mo.clip:Hide() end
        end
    end

    -- Max color overlay: shows only when current = max (secret value safe)
    -- Uses min=max-0.5 so only integer max triggers 100% fill
    if cfg.enableMaxColor and max and max > 0 then
        if not bar._maxColorOverlay then
            bar._maxColorOverlay = CreateFrame("StatusBar", nil, bar)
        end
        local maxOv = bar._maxColorOverlay
        maxOv:ClearAllPoints()
        maxOv:SetAllPoints(bar.StatusBar)
        maxOv:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 10)
        maxOv:SetMinMaxValues(max - 0.5, max)
        maxOv:SetValue(current)
        if texPath then maxOv:SetStatusBarTexture(texPath) end
        local mc = cfg.maxColor or { 1.0, 0.3, 0.3, 1.0 }
        maxOv:SetStatusBarColor(mc[1], mc[2], mc[3], mc[4] or 1)
        maxOv:Show()
    else
        if bar._maxColorOverlay then bar._maxColorOverlay:Hide() end
    end
end

-- Get ResourceBars module
local ResourceBars = DDingUI.ResourceBars
if not ResourceBars then
    error("DDingUI: ResourceBars module not initialized! Load ResourceDetection.lua first.")
end

-- Get functions from ResourceDetection
local GetSecondaryResource = ResourceBars.GetSecondaryResource
local GetPrimaryResource = ResourceBars.GetPrimaryResource
local GetResourceColor = ResourceBars.GetResourceColor
local GetSecondaryResourceValue = ResourceBars.GetSecondaryResourceValue
local GetChargedPowerPoints = ResourceBars.GetChargedPowerPoints
local tickedPowerTypes = ResourceBars.tickedPowerTypes
local fragmentedPowerTypes = ResourceBars.fragmentedPowerTypes
local buildVersion = ResourceBars.buildVersion

-- Use shared PixelSnap from Toolkit
local PixelSnap = DDingUI.PixelSnapLocal or function(value)
    return math_max(0, math_floor((value or 0) + 0.5))
end

-- [REFACTOR] 공통 TextureBorder 유틸리티는 Toolkit.lua DDingUI.CreateTextureBorder 등에서 제공
local CreateTextureBorder = DDingUI.CreateTextureBorder
local UpdateTextureBorderColor = DDingUI.UpdateTextureBorderColor
local UpdateTextureBorderSize = DDingUI.UpdateTextureBorderSize
local ShowTextureBorder = DDingUI.ShowTextureBorder

-- ===================================================================
-- COLORCURVE THRESHOLD SYSTEM -- Uses UnitPowerPercent with ColorCurve for secret-value safe threshold colors
-- Hardcoded thresholds: 0-35% red, 35-70% yellow, 70-100% base color
-- ===================================================================
local secondaryPowerBarColorCurve = nil  -- Cached curve
local secondaryPowerBarColorCurveHash = nil  -- Cache key based on base color

-- Create or get cached ColorCurve for secondary power bar
local function GetSecondaryPowerBarColorCurve(cfg, baseColor, maxValue)
    if not cfg.thresholdEnabled then return nil end

    -- Check if ColorCurve API exists (WoW 12.0+)
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
        return nil
    end

    -- Create hash based on base color only (thresholds are hardcoded)
    local bc = baseColor or {1, 1, 1, 1}
    local currentHash = string.format("%.2f,%.2f,%.2f", bc[1] or bc.r or 1, bc[2] or bc.g or 1, bc[3] or bc.b or 1)

    -- Return cached curve if base color hasn't changed
    if secondaryPowerBarColorCurve and secondaryPowerBarColorCurveHash == currentHash then
        return secondaryPowerBarColorCurve
    end

    -- Hardcoded threshold colors
    local RED = CreateColor(1.0, 0.3, 0.3, 1)     -- 0-35%
    local YELLOW = CreateColor(1.0, 0.8, 0.0, 1)  -- 35-70%
    local baseColorObj
    if bc[1] then
        baseColorObj = CreateColor(bc[1], bc[2], bc[3], bc[4] or 1)
    else
        baseColorObj = CreateColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
    end

    -- Create the ColorCurve with hardcoded thresholds
    local curve = C_CurveUtil.CreateColorCurve()
    local EPSILON = 0.0001

    -- 0% - Red
    curve:AddPoint(0.0, RED)
    -- Just before 35% - still Red
    curve:AddPoint(0.35 - EPSILON, RED)
    -- At 35% - Yellow begins
    curve:AddPoint(0.35, YELLOW)
    -- Just before 70% - still Yellow
    curve:AddPoint(0.70 - EPSILON, YELLOW)
    -- At 70% - Base color begins
    curve:AddPoint(0.70, baseColorObj)
    -- 100% - Base color
    curve:AddPoint(1.0, baseColorObj)

    -- Cache
    secondaryPowerBarColorCurve = curve
    secondaryPowerBarColorCurveHash = currentHash
    return curve
end

-- SECONDARY POWER BAR

function ResourceBars:GetSecondaryPowerBar()
    if DDingUI.secondaryPowerBar then return DDingUI.secondaryPowerBar end

    local cfg = DDingUI.db.profile.secondaryPowerBar
    local anchor = DDingUI:ResolveAnchorFrame(cfg.attachTo)
    local anchorPoint = cfg.anchorPoint or "CENTER"

    local bar = CreateFrame("Frame", ADDON_NAME .. "SecondaryPowerBar", UIParent)  -- [FIX] 항상 UIParent 자식 (엘레베이터 방지)
    bar:SetIgnoreParentAlpha(true)
    bar:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    -- Keep the bar click-through so it never blocks PlayerFrame interactions
    bar:EnableMouse(false)
    bar:EnableMouseWheel(false)
    if bar.SetMouseMotionEnabled then
        bar:SetMouseMotionEnabled(false)
    end


    bar:SetHeight(DDingUI:Scale(cfg.height or 4))
    local initSelfPoint = cfg.selfPoint or "CENTER" -- [FIX: selfPoint support]
    bar:SetPoint(initSelfPoint, anchor, anchorPoint, DDingUI:Scale(cfg.offsetX or 0), DDingUI:Scale(cfg.offsetY or 12))

    local MAX_AUTO_WIDTH_INIT = 600
    local width = cfg.width or 0
    if width <= 0 then
        -- Auto width: get from viewer or anchor content width
        local effectiveWidth, needsBorderComp = DDingUI:GetEffectiveAnchorWidth(anchor)
        if effectiveWidth and effectiveWidth > 0 and effectiveWidth <= MAX_AUTO_WIDTH_INIT and anchor ~= UIParent then
            if needsBorderComp then
                local bComp = DDingUI:ScaleBorder(cfg.borderSize or 1)
                width = PixelSnap(effectiveWidth - 2 * bComp)
            else
                width = PixelSnap(effectiveWidth)
            end
        else
            width = 200
        end
        if not width or width <= 0 or width > MAX_AUTO_WIDTH_INIT then
            width = 200
        end
    else
        width = DDingUI:Scale(width)
    end

    bar:SetWidth(width)

    -- BACKGROUND (lowest frame level)
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    -- Use background texture if specified, otherwise use solid color
    if cfg.bgTexture then
        local bgTex = DDingUI:GetTexture(cfg.bgTexture)
        bar.Background:SetTexture(bgTex)
        bar.Background:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    else
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    -- STATUS BAR (for non-fragmented resources) - class/custom color fill
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    -- Use GetTexture helper: if cfg.texture is set, use it; otherwise use global texture
    local tex = DDingUI:GetTexture(cfg.texture)
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel() + 1)

    -- BORDER - above ticks (texture-based, no SetBackdrop = no taint)
    bar.Border = CreateFrame("Frame", nil, bar)
    bar.Border:SetFrameLevel(bar:GetFrameLevel() + 4)
    bar.Border:SetAllPoints(bar)
    local borderSize = DDingUI:ScaleBorder(cfg.borderSize or 1)
    bar._scaledBorder = borderSize
    local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
    CreateTextureBorder(bar.Border, borderSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

    -- TICKS FRAME - above all color overlays (maxColor=+11, markerOverlays=+12, markerLines=+16)
    bar.TicksFrame = CreateFrame("Frame", nil, bar)
    bar.TicksFrame:SetAllPoints(bar)
    bar.TicksFrame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 13)

    -- CHARGED POWER OVERLAY FRAME - sits above the status bar, below ticks/border
    bar.ChargedFrame = CreateFrame("Frame", nil, bar)
    bar.ChargedFrame:SetAllPoints(bar)
    bar.ChargedFrame:SetFrameLevel(bar:GetFrameLevel() + 2)

    -- RUNE TIMER TEXT FRAME - above border
    bar.RuneTimerTextFrame = CreateFrame("Frame", nil, bar)
    bar.RuneTimerTextFrame:SetAllPoints(bar)
    bar.RuneTimerTextFrame:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    bar.RuneTimerTextFrame:SetFrameLevel(99)

    -- TEXT FRAME - highest
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    bar.TextFrame:SetFrameLevel(100)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", DDingUI:Scale(cfg.textX or 0), DDingUI:Scale(cfg.textY or 0))
    bar.TextValue:SetJustifyH("CENTER")
    bar.TextValue:SetFont(DDingUI:GetFont(cfg.textFont), cfg.textSize or 12, "OUTLINE")
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")


    -- FRAGMENTED POWER BARS (for Runes)
    bar.FragmentedPowerBars = {}
    bar.FragmentedPowerBarTexts = {}

    -- TICKS
    bar.ticks = {}

    -- MARKERS (custom divider lines)
    bar.markers = {}

    -- CHARGED POWER SEGMENTS
    bar.ChargedSegments = {}

    bar:Hide()

    DDingUI.secondaryPowerBar = bar
    return bar
end

function ResourceBars:UpdateChargedPowerSegments(bar, resource, max)
    local cfg = DDingUI.db.profile.secondaryPowerBar

    -- Hide all overlays first
    for _, segment in pairs(bar.ChargedSegments) do
        segment:Hide()
    end

    -- Bail out if the bar itself is hidden or not applicable
    if cfg.hideBarShowText or not resource or not max then
        return
    end

    if fragmentedPowerTypes[resource] or not tickedPowerTypes[resource] then
        return
    end

    local chargedPoints = GetChargedPowerPoints and GetChargedPowerPoints(resource)
    if not chargedPoints or #chargedPoints == 0 then
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then
        return
    end

    if not max or max <= 0 then
        return
    end

    local segmentWidth = width / max
    local chargedColor = cfg.chargedColor or { 0.22, 0.62, 1.0, 0.8 }

    for _, index in ipairs(chargedPoints) do
        if index >= 1 and index <= max then
            local segment = bar.ChargedSegments[index]
            if not segment then
                segment = bar.ChargedFrame:CreateTexture(nil, "ARTWORK")
                bar.ChargedSegments[index] = segment
            end

            segment:ClearAllPoints()
            segment:SetPoint("LEFT", bar, "LEFT", (index - 1) * segmentWidth, 0)
            segment:SetSize(segmentWidth, height)
            -- Use charged color exclusively; avoid additive blend so class/custom bar colors do not tint these overlays.
            segment:SetColorTexture(chargedColor[1], chargedColor[2], chargedColor[3], chargedColor[4] or 0.8)
            segment:SetBlendMode("BLEND")
            segment:Show()
        end
    end
end

-- Default per-point colors (fallback for existing profiles with empty perPointColors)
local _defaultPerPointColors = {
    {0.2, 1, 0.2, 1},     -- 1
    {0.4, 1, 0.2, 1},     -- 2
    {0.6, 1, 0.2, 1},     -- 3
    {0.8, 1, 0.2, 1},     -- 4
    {1, 0.8, 0.2, 1},     -- 5
    {1, 0.5, 0.2, 1},     -- 6
    {1, 0.3, 0.2, 1},     -- 7
    {1, 0.2, 0.2, 1},     -- 8
    {1, 0.1, 0.1, 1},     -- 9
    {1, 0, 0, 1},         -- 10
}

function ResourceBars:UpdatePerPointColorSegments(bar, resource, visualMax, current)
    local cfg = DDingUI.db.profile.secondaryPowerBar

    bar.PerPointSegments = bar.PerPointSegments or {}

    -- Hide all overlays first
    for _, segment in pairs(bar.PerPointSegments) do
        segment:Hide()
    end

    if not cfg.enablePerPointColors or cfg.hideBarShowText then return end
    if not resource or fragmentedPowerTypes[resource] or not tickedPowerTypes[resource] then return end
    if not visualMax or visualMax <= 0 or not current or current <= 0 then return end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    -- For SoulShards, convert to display values
    local displayMax = visualMax
    local displayCurrent = current
    if resource == Enum.PowerType.SoulShards then
        displayMax = math_floor(visualMax / 10)
        displayCurrent = math_floor(current / 10)
    end
    if displayMax <= 0 then return end

    -- Cap to visual max (overflow mode: only show colors within threshold)
    displayCurrent = math_min(displayCurrent, displayMax)

    local segmentWidth = width / displayMax
    local ppColors = cfg.perPointColors or {}

    for i = 1, displayCurrent do
        local ppColor = ppColors[i] or _defaultPerPointColors[i] or _defaultPerPointColors[1]
        local segment = bar.PerPointSegments[i]
        if not segment then
            segment = bar.ChargedFrame:CreateTexture(nil, "BORDER")
            bar.PerPointSegments[i] = segment
        end

        segment:ClearAllPoints()
        segment:SetPoint("LEFT", bar, "LEFT", (i - 1) * segmentWidth, 0)
        segment:SetSize(segmentWidth, height)
        segment:SetColorTexture(ppColor[1], ppColor[2], ppColor[3], ppColor[4] or 1)
        segment:SetBlendMode("BLEND")
        segment:Show()
    end
end

function ResourceBars:UpdateOverflowColorSegments(bar, resource, visualMax, current)
    local cfg = DDingUI.db.profile.secondaryPowerBar

    bar.OverflowSegments = bar.OverflowSegments or {}

    -- Hide all overlays first
    for _, segment in pairs(bar.OverflowSegments) do
        segment:Hide()
    end

    if not cfg.enableOverflowColor or cfg.hideBarShowText then return end
    if not resource or fragmentedPowerTypes[resource] or not tickedPowerTypes[resource] then return end
    if not visualMax or visualMax <= 0 or not current then return end

    local threshold = cfg.overflowThreshold or 5

    -- For SoulShards, convert fractional current to display value
    local displayCurrent = current
    if resource == Enum.PowerType.SoulShards then
        displayCurrent = math.floor(current / 10)
    end

    if displayCurrent <= threshold then return end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    -- Segment width based on threshold (the visual number of segments)
    local segmentWidth = width / threshold
    local overflowCount = displayCurrent - threshold
    local overflowColor = cfg.overflowColor or {1.0, 0.3, 0.3, 1.0}

    for i = 1, overflowCount do
        local segment = bar.OverflowSegments[i]
        if not segment then
            -- ARTWORK sublevel 1: above per-point (BORDER) but below charged (ARTWORK default)
            segment = bar.ChargedFrame:CreateTexture(nil, "ARTWORK", nil, 1)
            bar.OverflowSegments[i] = segment
        end

        segment:ClearAllPoints()
        segment:SetPoint("LEFT", bar, "LEFT", (i - 1) * segmentWidth, 0)
        segment:SetSize(segmentWidth, height)
        segment:SetColorTexture(overflowColor[1], overflowColor[2], overflowColor[3], overflowColor[4] or 1)
        segment:SetBlendMode("BLEND")
        segment:Show()
    end
end

function ResourceBars:CreateFragmentedPowerBars(bar, resource)
    local cfg = DDingUI.db.profile.secondaryPowerBar
    local maxPower = (resource == "MAELSTROM_WEAPON" and 5) or UnitPowerMax("player", resource) or 0
    
    for i = 1, maxPower do
        if not bar.FragmentedPowerBars[i] then
            local fragmentBar = CreateFrame("StatusBar", nil, bar)
            -- Use GetTexture helper: if cfg.texture is set, use it; otherwise use global texture
            local tex = DDingUI:GetTexture(cfg.texture)
            fragmentBar:SetStatusBarTexture(tex)
            fragmentBar:SetOrientation("HORIZONTAL")
            fragmentBar:SetFrameLevel(bar.StatusBar:GetFrameLevel())
            bar.FragmentedPowerBars[i] = fragmentBar
            
            -- Create text for reload time display (centered on fragment bar)
            local text = fragmentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("CENTER", fragmentBar, "CENTER", 0, 0)
            text:SetJustifyH("CENTER")
            text:SetText("")
            bar.FragmentedPowerBarTexts[i] = text
        end
    end
end

function ResourceBars:UpdateFragmentedPowerDisplay(bar, resource)
    local cfg = DDingUI.db.profile.secondaryPowerBar
    local maxPower = (resource == "MAELSTROM_WEAPON" and 5) or UnitPowerMax("player", resource)
    if maxPower <= 0 then return end

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    local fragmentedBarWidth = barWidth / maxPower
    local fragmentedBarHeight = barHeight / maxPower

    local r, g, b, a = bar.StatusBar:GetStatusBarColor()
    local color = { r = r, g = g, b = b, a = a or 1 }

    if resource == Enum.PowerType.Essence then
        local current = UnitPower("player", resource)
        local maxEssence = UnitPowerMax("player", resource)
        local regenRate = (type(GetPowerRegenForPowerType) == "function" and GetPowerRegenForPowerType(resource)) or 0.2
        local tickDuration = 5 / (5 / (1 / regenRate))
        local now = GetTime()

        bar._NextEssenceTick = bar._NextEssenceTick or nil
        bar._LastEssence = bar._LastEssence or current

        -- If we gained an essence, reset timer
        if current > bar._LastEssence then
            if current < maxEssence then
                bar._NextEssenceTick = now + tickDuration
            else
                bar._NextEssenceTick = nil
            end
        end

        -- If missing essence and no timer, start it
        if current < maxEssence and not bar._NextEssenceTick then
            bar._NextEssenceTick = now + tickDuration
        end

        -- If full essence, hide timer
        if current >= maxEssence then
            bar._NextEssenceTick = nil
        end

        bar._LastEssence = current

        wipe(_displayOrder); local displayOrder = _displayOrder
        wipe(_stateList); local stateList = _stateList
        for i = 1, maxEssence do
            if i <= current then
                stateList[i] = "full"
            elseif i == current + 1 then
                stateList[i] = bar._NextEssenceTick and "partial" or "empty"
            else
                stateList[i] = "empty"
            end
            displayOrder[#displayOrder + 1] = i
        end

        bar.StatusBar:SetValue(current)

        local precision = (cfg.fragmentedPowerBarTextPrecision and math.max(0, string.len(cfg.fragmentedPowerBarTextPrecision) - 3)) or 0
        local interpolation = cfg.smoothProgress and buildVersion >= 120000 and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
        local essFont = DDingUI:GetFont(cfg.runeTimerFont)
        local essTextSize = cfg.runeTimerTextSize or 10
        for pos = 1, #displayOrder do
            local idx = displayOrder[pos]
            local essFrame = bar.FragmentedPowerBars[idx]
            local essText = bar.FragmentedPowerBarTexts[idx]
            local state = stateList[idx]

            -- Apply font settings to essence text
            if essText and essFont then
                essText:SetFont(essFont, essTextSize, "OUTLINE")
            end

            if essFrame then
                essFrame:ClearAllPoints()
                essFrame:SetSize(fragmentedBarWidth, barHeight)
                essFrame:SetPoint("LEFT", bar, "LEFT", (pos - 1) * fragmentedBarWidth, 0)

                essFrame:SetMinMaxValues(0, 1)

                if state == "full" then
                    essFrame:Hide()
                    essFrame:SetValue(1, interpolation)
                    essFrame:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
                    essText:SetText("")
                elseif state == "partial" then
                    essFrame:Show()
                    local remaining = math_max(0, bar._NextEssenceTick - now)
                    local value = 1 - (remaining / tickDuration)
                    essFrame:SetValue(value, interpolation)
                    if cfg.useRechargeColor and cfg.rechargeColor then
                        local rc = cfg.rechargeColor
                        essFrame:SetStatusBarColor(rc[1], rc[2], rc[3], rc[4] or 1)
                    else
                        essFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5, color.a or 1)
                    end
                    if cfg.showFragmentedPowerBarText then
                        essText:SetText(string.format("%." .. (precision or 1) .. "f", remaining))
                    else
                        essText:SetText("")
                    end
                else
                    essFrame:Show()
                    essFrame:SetValue(0, interpolation)
                    if cfg.useRechargeColor and cfg.rechargeColor then
                        local rc = cfg.rechargeColor
                        essFrame:SetStatusBarColor(rc[1], rc[2], rc[3], rc[4] or 1)
                    else
                        essFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5, color.a or 1)
                    end
                    essText:SetText("")
                end
            end
        end
    elseif resource == Enum.PowerType.Runes then
        -- Collect rune states: ready and recharging
        wipe(_readyList); local readyList = _readyList
        wipe(_cdList); local cdList = _cdList
        local now = GetTime()
        for i = 1, maxPower do
            local start, duration, runeReady = GetRuneCooldown(i)
            if runeReady then
                readyList[#readyList + 1] = { index = i }
            else
                if start and duration and duration > 0 then
                    local elapsed = now - start
                    local remaining = math_max(0, duration - elapsed)
                    local frac = math_max(0, math_min(1, elapsed / duration))
                    cdList[#cdList + 1] = { index = i, remaining = remaining, frac = frac }
                else
                    cdList[#cdList + 1] = { index = i, remaining = math.huge, frac = 0 }
                end
            end
        end

        -- Sort cdList by ascending remaining time (least remaining on the left of the CD group)
        table.sort(cdList, function(a, b)
            return a.remaining < b.remaining
        end)

        -- Build final display order: ready runes first (left), then CD runes sorted by remaining
        wipe(_displayOrder); local displayOrder = _displayOrder
        wipe(_readyLookup); local readyLookup = _readyLookup
        wipe(_cdLookup); local cdLookup = _cdLookup
        for _, v in ipairs(readyList) do
            displayOrder[#displayOrder + 1] = v.index
            readyLookup[v.index] = true
        end
        for _, v in ipairs(cdList) do
            displayOrder[#displayOrder + 1] = v.index
            cdLookup[v.index] = v
        end

        bar.StatusBar:SetValue(#readyList)

        local precision = (cfg.fragmentedPowerBarTextPrecision and math.max(0, string.len(cfg.fragmentedPowerBarTextPrecision) - 3)) or 0
        local interpolation = cfg.smoothProgress and buildVersion >= 120000 and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
        local runeFont = DDingUI:GetFont(cfg.runeTimerFont)
        local runeTextSize = cfg.runeTimerTextSize or 10
        for pos = 1, #displayOrder do
            local runeIndex = displayOrder[pos]
            local runeFrame = bar.FragmentedPowerBars[runeIndex]
            local runeText = bar.FragmentedPowerBarTexts[runeIndex]

            -- Apply font settings to rune text
            if runeText and runeFont then
                runeText:SetFont(runeFont, runeTextSize, "OUTLINE")
            end

            if runeFrame then
                runeFrame:ClearAllPoints()
                runeFrame:SetSize(fragmentedBarWidth, barHeight)
                runeFrame:SetPoint("LEFT", bar, "LEFT", (pos - 1) * fragmentedBarWidth, 0)

                runeFrame:SetMinMaxValues(0, 1)
                if readyLookup[runeIndex] then
                    runeFrame:Hide()
                    runeFrame:SetValue(1, interpolation)
                    runeFrame:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
                    runeText:SetText("")
                else
                    runeFrame:Show()
                    local cdInfo = cdLookup[runeIndex]
                    if cfg.useRechargeColor and cfg.rechargeColor then
                        local rc = cfg.rechargeColor
                        runeFrame:SetStatusBarColor(rc[1], rc[2], rc[3], rc[4] or 1)
                    else
                        runeFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5, color.a or 1)
                    end
                    if cdInfo then
                        runeFrame:SetValue(cdInfo.frac, interpolation)
                        if cfg.showFragmentedPowerBarText then
                            runeText:SetText(string.format("%." .. (precision or 1) .. "f", math_max(0, cdInfo.remaining)))
                        else
                            runeText:SetText("")
                        end
                    else
                        runeFrame:SetValue(0, interpolation)
                        runeText:SetText("")
                    end
                end
            end
        end
    end

    -- Hide extra fragmented power bars beyond current maxPower
    for i = maxPower + 1, #bar.FragmentedPowerBars do
        if bar.FragmentedPowerBars[i] then
            bar.FragmentedPowerBars[i]:Hide()
            if bar.FragmentedPowerBarTexts[i] then
                bar.FragmentedPowerBarTexts[i]:SetText("")
            end
        end
    end
end

function ResourceBars:UpdateSecondaryPowerBarTicks(bar, resource, max)
    local cfg = DDingUI.db.profile.secondaryPowerBar

    -- Hide all ticks first
    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    -- Don't show ticks if disabled or not a ticked power type
    if not cfg.showTicks or not tickedPowerTypes[resource] then
        return
    end

    local width  = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    -- For Soul Shards, use the display max (not the internal fractional max)
    local displayMax = max
    if resource == Enum.PowerType.SoulShards then
        displayMax = UnitPowerMax("player", resource) -- non-fractional max (usually 5)
    end
    if not displayMax or displayMax <= 0 then
        return
    end

    local needed = displayMax - 1
    for i = 1, needed do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar.TicksFrame:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(0, 0, 0, 1)
            bar.ticks[i] = tick
        end

        local x = (i / displayMax) * width
        tick:ClearAllPoints()
        -- x is already in pixels (calculated from bar width), no need to scale
        tick:SetPoint("LEFT", bar.StatusBar, "LEFT", x, 0)
        -- Ensure tick width is at least 1 pixel to prevent disappearing
        local cfgTickWidth = cfg.tickWidth or 2
        local tickWidth = math_max(1, DDingUI:Scale(cfgTickWidth))
        -- height is already in pixels (from bar:GetHeight()), no need to scale
        tick:SetSize(tickWidth, height)
        tick:Show()
    end
end

-- Ticker for faster updates (separate from bar frame so it runs even when bar is hidden)
local secondaryPowerTicker = nil
local secondaryPowerTickerFrame = nil

local function SetupSecondaryPowerTicker(cfg)
    -- Cancel existing ticker
    if secondaryPowerTicker then
        secondaryPowerTicker:Cancel()
        secondaryPowerTicker = nil
    end

    if cfg.fasterUpdates and cfg.enabled then
        local updateFrequency = cfg.updateFrequency or 0.1
        secondaryPowerTicker = C_Timer.NewTicker(updateFrequency, function()
            ResourceBars:UpdateSecondaryPowerBar()
        end)
    end
end

function ResourceBars:UpdateSecondaryPowerBar()
    local cfg = DDingUI.db.profile.secondaryPowerBar
    if not cfg.enabled then
        if DDingUI.secondaryPowerBar then
            DDingUI.secondaryPowerBar:Hide()
        end
        -- Stop ticker when disabled
        if secondaryPowerTicker then
            secondaryPowerTicker:Cancel()
            secondaryPowerTicker = nil
        end
        return
    end

    -- Setup ticker for faster updates (only if not already running)
    if cfg.fasterUpdates and not secondaryPowerTicker then
        SetupSecondaryPowerTicker(cfg)
    elseif not cfg.fasterUpdates and secondaryPowerTicker then
        secondaryPowerTicker:Cancel()
        secondaryPowerTicker = nil
    end

    local bar = self:GetSecondaryPowerBar()

    -- Track stagger percentage for dynamic color changes
    local resource = GetSecondaryResource()
    if resource == "STAGGER" then
        local stagger = UnitStagger("player") or 0
        local maxHealth = UnitHealthMax("player") or 1
        local staggerPercent = (stagger / maxHealth) * 100

        -- Initialize tracking variable if it doesn't exist
        bar._lastStaggerPercent = bar._lastStaggerPercent or staggerPercent

        -- Check if we crossed a threshold and need to update colors
        if (staggerPercent >= 30 and bar._lastStaggerPercent < 30)
            or (staggerPercent < 30 and bar._lastStaggerPercent >= 30)
            or (staggerPercent >= 60 and bar._lastStaggerPercent < 60)
            or (staggerPercent < 60 and bar._lastStaggerPercent >= 60) then
            -- Force color update by clearing cached color
            bar._lastColorResource = nil
        end

        bar._lastStaggerPercent = staggerPercent
    end

    local anchor = DDingUI:ResolveAnchorFrame(cfg.attachTo)
    -- 자기 자신을 앵커로 설정하면 UIParent로 폴백
    if anchor == bar or cfg.attachTo == "DDingUISecondaryPowerBar" then
        anchor = UIParent
    end

    -- Grace Period check - don't permanently hide bar during spec/level changes
    local inGracePeriod = ResourceBars.IsInGracePeriod and ResourceBars.IsInGracePeriod()

    local anchorFallback = false
    if not anchor then
        if inGracePeriod then
            -- 특성 변경 중: 위치 틀어짐 방지를 위해 바를 잠시 숨기고
            -- 앵커가 복구되면 정확한 위치에 다시 표시
            if bar:GetParent() ~= UIParent then
                bar:SetParent(UIParent)
            end
            bar:Hide()
            if not bar._anchorRetryScheduled then
                bar._anchorRetryScheduled = true
                C_Timer.After(0.2, function() ResourceBars:UpdateSecondaryPowerBar() end)
                C_Timer.After(0.5, function() ResourceBars:UpdateSecondaryPowerBar() end)
                C_Timer.After(1.0, function()
                    bar._anchorRetryScheduled = nil
                    ResourceBars:UpdateSecondaryPowerBar()
                end)
                C_Timer.After(2.0, function() ResourceBars:UpdateSecondaryPowerBar() end)
            end
            return
        end

        -- 비 grace period: 재시도 카운터 추적
        bar._anchorRetryCount = (bar._anchorRetryCount or 0) + 1
        anchor = UIParent
        anchorFallback = true

        if bar:GetParent() ~= UIParent then
            bar:SetParent(UIParent)
        end

        if not bar._anchorRetryScheduled then
            bar._anchorRetryScheduled = true
            C_Timer.After(0.2, function() ResourceBars:UpdateSecondaryPowerBar() end)
            C_Timer.After(0.5, function() ResourceBars:UpdateSecondaryPowerBar() end)
            C_Timer.After(1.0, function()
                bar._anchorRetryScheduled = nil
                local originalAnchor = DDingUI:ResolveAnchorFrame(cfg.attachTo)
                if originalAnchor and originalAnchor:IsShown() then
                    bar._anchorRetryCount = 0
                end
                ResourceBars:UpdateSecondaryPowerBar()
            end)
            C_Timer.After(2.0, function()
                local originalAnchor = DDingUI:ResolveAnchorFrame(cfg.attachTo)
                if originalAnchor and originalAnchor:IsShown() then
                    bar._anchorRetryCount = 0
                    ResourceBars:UpdateSecondaryPowerBar()
                end
            end)
        end
    else
        -- 앵커 찾으면 카운터 리셋
        bar._anchorRetryCount = 0
        bar._anchorRetryScheduled = nil

        -- [FIX] SetParent(anchor) 제거 — 엘레베이터 현상 근본 원인
        -- 스펙 변경 시 그룹 프레임이 재생성되면 부모가 바뀌면서 오프셋이 누적됨
        if bar:GetParent() ~= UIParent then
            bar:SetParent(UIParent)
            bar:SetIgnoreParentAlpha(true)
        end
    end
    local resource = GetSecondaryResource()

    if not resource then
        -- Grace Period 중에는 바를 숨기지 않음 (전문화 변경 시 잠시 nil일 수 있음)
        if not inGracePeriod then
            bar:Hide()
        end
        return
    end

    -- Optionally hide when the secondary resource is mana (DPS spec only)
    if cfg.hideWhenMana and resource == Enum.PowerType.Mana then
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if role == "DAMAGER" then
            if not inGracePeriod then
                bar:Hide()
            end
            return
        end
    end

    -- Check if primary bar is hidden due to mana (DPS only) → use "no primary" size
    local primaryCfg = DDingUI.db.profile.powerBar
    local primaryResource = GetPrimaryResource and GetPrimaryResource()
    local primaryDisabled = primaryCfg and not primaryCfg.enabled
    local primaryHiddenDueToMana = false
    if primaryCfg and primaryCfg.hideWhenMana and primaryResource == Enum.PowerType.Mana then
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if role == "DAMAGER" then
            primaryHiddenDueToMana = true
        end
    end
    local useNoPrimarySize = cfg.useNoPrimarySize and (primaryDisabled or primaryHiddenDueToMana)

    -- Update layout
    local desiredHeight
    if useNoPrimarySize then
        desiredHeight = DDingUI:Scale(cfg.noPrimaryHeight or cfg.height or 4)
    else
        desiredHeight = DDingUI:Scale(cfg.height or 4)
    end

    do -- positioning block
        local anchorPoint
        local desiredX, desiredY
        if anchorFallback then
            -- [FIX] 앵커 비활성 → 현재 화면 위치 유지 (CENTER fallback 완전 제거)
            local cx, cy = bar:GetCenter()
            if cx and cy then
                local parentCX, parentCY = UIParent:GetCenter()
                anchorPoint = "CENTER"
                desiredX = cx - (parentCX or 0)
                desiredY = cy - (parentCY or 0)
            else
                -- 바가 아직 위치 없음 (최초 로드) → 설정값 사용
                anchorPoint = cfg.anchorPoint or "CENTER"
                desiredX = DDingUI:Scale(cfg.offsetX or 0)
                desiredY = DDingUI:Scale(cfg.offsetY or 12)
            end
        else
            anchorPoint = cfg.anchorPoint or "CENTER"
            desiredX = DDingUI:Scale(cfg.offsetX or 0)
            if useNoPrimarySize and cfg.noPrimaryOffsetY then
                desiredY = DDingUI:Scale(cfg.noPrimaryOffsetY)
            else
                desiredY = DDingUI:Scale(cfg.offsetY or 12)
            end
        end

        local cfgWidth
        if useNoPrimarySize then
            cfgWidth = cfg.noPrimaryWidth or cfg.width or 0
        else
            cfgWidth = cfg.width or 0
        end

        -- Reset _lastWidth if cfg width setting changed (to force recalculation)
        if bar._lastCfgWidth ~= cfgWidth then
            bar._lastWidth = nil
            bar._lastCfgWidth = cfgWidth
        end

        -- Maximum auto width limit to prevent infinite/huge widths during frame transitions
        local MAX_AUTO_WIDTH = 600

        local width
        if cfgWidth <= 0 then
            -- Auto width: get from viewer or anchor content width
            local effectiveWidth, needsBorderComp = DDingUI:GetEffectiveAnchorWidth(anchor)
            if effectiveWidth and effectiveWidth > 0 and effectiveWidth <= MAX_AUTO_WIDTH and anchor ~= UIParent then
                if needsBorderComp then
                    local bComp = DDingUI:ScaleBorder(cfg.borderSize or 1)
                    width = PixelSnap(effectiveWidth - 2 * bComp)
                else
                    width = PixelSnap(effectiveWidth)
                end
            elseif DDingUI.powerBar and DDingUI.powerBar:IsShown() then
                local powerBarWidth = DDingUI.powerBar:GetWidth()
                if powerBarWidth and powerBarWidth > 0 and powerBarWidth <= MAX_AUTO_WIDTH then
                    width = PixelSnap(powerBarWidth)
                else
                    width = bar._graceFallbackWidth or 200
                end
            else
                width = bar._graceFallbackWidth or 200
            end
            -- Final safeguard against invalid widths
            if not width or width <= 0 or width > MAX_AUTO_WIDTH then
                width = bar._graceFallbackWidth or 200
            end
        else
            width = DDingUI:Scale(cfgWidth)
        end

        -- Mover 모드 중에는 위치/크기 재설정 건너뛰기 (드래그와 충돌 방지)
        local isInMoverMode = DDingUI.Movers and DDingUI.Movers.ConfigMode
        local selfPoint = cfg.selfPoint or "CENTER" -- [FIX: selfPoint support]
        -- Only reposition / resize when something actually changed to avoid texture flicker
        if (bar._lastAnchor ~= anchor or bar._lastAnchorPoint ~= anchorPoint or bar._lastOffsetX ~= desiredX or bar._lastOffsetY ~= desiredY or bar._lastSelfPoint ~= selfPoint) and not isInMoverMode then
            bar:ClearAllPoints()
            bar:SetPoint(selfPoint, anchor, anchorPoint, desiredX, desiredY)
            bar._lastAnchor = anchor
            bar._lastAnchorPoint = anchorPoint
            bar._lastOffsetX = desiredX
            bar._lastOffsetY = desiredY
            bar._lastSelfPoint = selfPoint
        end

        if bar._lastWidth ~= width and not isInMoverMode then
            bar:SetWidth(width)
            bar._lastWidth = width
        end
    end -- positioning block

    if bar._lastHeight ~= desiredHeight then
        bar:SetHeight(desiredHeight)
        bar._lastHeight = desiredHeight
    end

    -- Update background color
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    -- Update texture (use per-bar texture if set, otherwise use global)
    local tex = DDingUI:GetTexture(cfg.texture)
    if bar._lastTexture ~= tex then
        bar.StatusBar:SetStatusBarTexture(tex)
        -- [FIX] FragmentedPowerBars(룬/정수/소용돌이 등) 텍스쳐도 동기화
        if bar.FragmentedPowerBars then
            for _, fragmentBar in pairs(bar.FragmentedPowerBars) do
                if fragmentBar and fragmentBar.SetStatusBarTexture then
                    fragmentBar:SetStatusBarTexture(tex)
                end
            end
        end
        bar._lastTexture = tex
    end

    -- Update border size and color (texture-based)
    local borderSize = cfg.borderSize or 1
    if bar.Border then
        local scaledBorder = DDingUI:ScaleBorder(borderSize)
        bar._scaledBorder = scaledBorder
        UpdateTextureBorderSize(bar.Border, scaledBorder)
        local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
        UpdateTextureBorderColor(bar.Border, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        ShowTextureBorder(bar.Border, scaledBorder > 0)
    end

    -- Get resource values
    local max, maxDisplayValue, current, displayValue, valueType = GetSecondaryResourceValue(resource, cfg)
    if not max then
        -- Grace Period 중에는 바를 숨기지 않음
        if not inGracePeriod then
            bar:Hide()
        end
        return
    end

    -- SOUL_SECRET: DH 포식 Soul Fragments (secret value 처리)
    -- current는 secret value일 수 있으므로 비교/연산 금지, Blizzard 위젯에 직접 전달
    if valueType == "SOUL_SECRET" then
        local interpolation = cfg.smoothProgress and buildVersion >= 120000 and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
        bar.StatusBar:SetMinMaxValues(0, max, interpolation)
        bar.StatusBar:SetValue(current, interpolation)
        bar.StatusBar:SetAlpha(1)

        -- Color
        local powerTypeColors = DDingUI.db.profile.powerTypeColors
        local baseR, baseG, baseB, baseA = 1, 1, 1, 1
        if powerTypeColors.useClassColor then
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                baseR, baseG, baseB, baseA = classColor.r, classColor.g, classColor.b, 1
            else
                local color = GetResourceColor(resource)
                if color then
                    baseR, baseG, baseB, baseA = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, 1
                end
            end
        elseif powerTypeColors.colors and powerTypeColors.colors[resource] then
            local color = powerTypeColors.colors[resource]
            baseR, baseG, baseB, baseA = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
        else
            local color = GetResourceColor(resource)
            if color then
                baseR, baseG, baseB, baseA = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, 1
            end
        end
        bar.StatusBar:SetStatusBarColor(baseR, baseG, baseB, baseA)

        -- Marker color overlay for SOUL resources (secret value safe)
        UpdateMarkerColorOverlays(bar, cfg, current, max, interpolation)

        -- Text: tostring(secret value) → "?" in combat, number out of combat
        bar.TextValue:SetText(tostring(current))

        -- SOUL is not ticked/fragmented, just hide fragmented bars as safety
        for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
            fragmentBar:Hide()
        end

        bar.TextValue:SetFont(DDingUI:GetFont(cfg.textFont), cfg.textSize or 12, "OUTLINE")
        bar.TextValue:SetShadowOffset(0, 0)
        bar.TextValue:ClearAllPoints()
        bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", DDingUI:Scale(cfg.textX or 0), DDingUI:Scale(cfg.textY or 0))
        bar.TextFrame:SetShown(cfg.showText ~= false)

        if cfg.hideBarShowText then
            if bar.StatusBar then bar.StatusBar:Hide() end
            if bar.Background then bar.Background:Hide() end
            if bar.Border then bar.Border:Hide() end
            for _, tick in ipairs(bar.ticks) do tick:Hide() end
        else
            if bar.StatusBar then bar.StatusBar:Show() end
            if bar.Background then bar.Background:Show() end
            if bar.Border and (bar._scaledBorder or DDingUI:ScaleBorder(cfg.borderSize or 1)) > 0 then
                bar.Border:Show()
            end
        end

        bar:Show()
        return
    end

    -- Compute visual max for overflow mode (ticked resources only)
    local visualMax = max
    if cfg.enableOverflowColor and not fragmentedPowerTypes[resource] and tickedPowerTypes[resource] then
        local threshold = cfg.overflowThreshold or 5
        if resource == Enum.PowerType.SoulShards then
            visualMax = threshold * 10  -- SoulShards uses fractional (x10) values
        else
            visualMax = threshold
        end
    end

    -- Handle fragmented power types (Runes, Essence)
    if fragmentedPowerTypes[resource] then
        -- Set StatusBar color first so UpdateFragmentedPowerDisplay can read it
        local powerTypeColors = DDingUI.db.profile.powerTypeColors
        local fragR, fragG, fragB, fragA = 1, 1, 1, 1
        if powerTypeColors.useClassColor then
            -- Class color for all resources
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                fragR, fragG, fragB, fragA = classColor.r, classColor.g, classColor.b, 1
            else
                local color = GetResourceColor(resource)
                if color then
                    fragR, fragG, fragB, fragA = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, 1
                end
            end
        elseif powerTypeColors.colors and powerTypeColors.colors[resource] then
            -- For runes, check spec-specific color first
            if resource == Enum.PowerType.Runes then
                local specColor = nil
                local spec = GetSpecialization and GetSpecialization()
                local specID = spec and GetSpecializationInfo and GetSpecializationInfo(spec)
                if specID == 250 then
                    specColor = powerTypeColors.colors["RUNE_BLOOD"]
                elseif specID == 251 then
                    specColor = powerTypeColors.colors["RUNE_FROST"]
                elseif specID == 252 then
                    specColor = powerTypeColors.colors["RUNE_UNHOLY"]
                end
                if specColor then
                    fragR, fragG, fragB, fragA = specColor[1] or 1, specColor[2] or 1, specColor[3] or 1, specColor[4] or 1
                else
                    local color = powerTypeColors.colors[resource]
                    fragR, fragG, fragB, fragA = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
                end
            else
                -- Power type specific color
                local color = powerTypeColors.colors[resource]
                fragR, fragG, fragB, fragA = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
            end
        else
            -- Default resource color
            local color = GetResourceColor(resource)
            if color then
                fragR, fragG, fragB, fragA = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, 1
            end
        end

        -- Apply threshold colors if enabled (ColorCurve)
        local thresholdApplied = false
        if cfg.thresholdEnabled then
            local baseColor = {fragR, fragG, fragB, fragA}
            local colorCurve = GetSecondaryPowerBarColorCurve(cfg, baseColor, max)

            if colorCurve and resource and type(resource) == "number" and resource >= 0 then
                -- WoW 12.0+: Use barTexture:SetVertexColor
                local barTexture = bar.StatusBar:GetStatusBarTexture()
                pcall(function()
                    local colorResult = UnitPowerPercent("player", resource, false, colorCurve)
                    if colorResult and colorResult.GetRGB then
                        barTexture:SetVertexColor(colorResult:GetRGB())
                        thresholdApplied = true
                    end
                end)
            end
        end

        -- Base color (threshold takes precedence if applied; maxColor handled by overlay)
        if not thresholdApplied then
            bar.StatusBar:SetStatusBarColor(fragR, fragG, fragB, fragA)
        end

        -- Marker + max color overlays for fragmented resources (secret value safe)
        UpdateMarkerColorOverlays(bar, cfg, current, max, interpolation)

        -- Set StatusBar min/max and value first
        local interpolation = cfg.smoothProgress and buildVersion >= 120000 and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
        bar.StatusBar:SetMinMaxValues(0, max, interpolation)
        bar.StatusBar:SetValue(current, interpolation)

        self:CreateFragmentedPowerBars(bar, resource)
        self:UpdateFragmentedPowerDisplay(bar, resource)

        -- Update ticks for fragmented resources
        self:UpdateSecondaryPowerBarTicks(bar, resource, max)

        bar.TextValue:SetText(tostring(current))
    else
        -- Normal bar display
        bar.StatusBar:SetAlpha(1)
        local interpolation = cfg.smoothProgress and buildVersion >= 120000 and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
        bar.StatusBar:SetMinMaxValues(0, visualMax, interpolation)
        bar.StatusBar:SetValue(math_min(current, visualMax), interpolation)

        -- Set bar color
        local powerTypeColors = DDingUI.db.profile.powerTypeColors
        local baseR, baseG, baseB, baseA = 1, 1, 1, 1
        if powerTypeColors.useClassColor then
            -- Class color for all resources
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                baseR, baseG, baseB, baseA = classColor.r, classColor.g, classColor.b, 1
            else
                local color = GetResourceColor(resource)
                if color then
                    baseR, baseG, baseB, baseA = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, 1
                end
            end
        elseif powerTypeColors.colors and powerTypeColors.colors[resource] and resource ~= "STAGGER" then
            -- Power type specific color (skip for stagger as it uses dynamic colors)
            local color = powerTypeColors.colors[resource]
            baseR, baseG, baseB, baseA = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
        else
            -- Default resource color (includes dynamic stagger colors)
            local color = GetResourceColor(resource)
            if color then
                baseR, baseG, baseB, baseA = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, 1
            end
        end

        -- Apply threshold colors if enabled (ColorCurve)
        local thresholdApplied = false
        if cfg.thresholdEnabled then
            local baseColor = {baseR, baseG, baseB, baseA}
            local colorCurve = GetSecondaryPowerBarColorCurve(cfg, baseColor, max)

            if colorCurve and resource and type(resource) == "number" and resource >= 0 then
                -- WoW 12.0+: Use barTexture:SetVertexColor
                local barTexture = bar.StatusBar:GetStatusBarTexture()
                pcall(function()
                    local colorResult = UnitPowerPercent("player", resource, false, colorCurve)
                    if colorResult and colorResult.GetRGB then
                        barTexture:SetVertexColor(colorResult:GetRGB())
                        thresholdApplied = true
                    end
                end)
            end
        end

        -- Base color (threshold takes precedence if applied; maxColor handled by overlay)
        if not thresholdApplied then
            bar.StatusBar:SetStatusBarColor(baseR, baseG, baseB, baseA)
        end

        -- Marker + max color overlays for normal bar resources (secret value safe)
        UpdateMarkerColorOverlays(bar, cfg, current, max, interpolation)

        if cfg.textFormat == "Percent" or cfg.textFormat == "Percent%" or valueType == "percent" then
            local precision = cfg.textPrecision or 0
            local percentSign = cfg.showPercentSign and "%%" or ""
            if valueType == "custom" then
                bar.TextValue:SetText(displayValue)
            else
                bar.TextValue:SetText(string.format("%." .. precision .. "f" .. percentSign, displayValue))
            end
        elseif cfg.textFormat == "Current / Maximum" then
            if valueType == "custom" then
                bar.TextValue:SetText(displayValue .. ' / ' .. (maxDisplayValue or max))
            else
                bar.TextValue:SetText(AbbreviateNumbers(displayValue) .. ' / ' .. AbbreviateNumbers(maxDisplayValue or max))
            end
        else -- Default "Current" format
            if valueType == "custom" then
                bar.TextValue:SetText(displayValue)
            else
                bar.TextValue:SetText(AbbreviateNumbers(displayValue))
            end
        end
        
        -- Hide fragmented bars
        for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
            fragmentBar:Hide()
        end
    end

    bar.TextValue:SetFont(DDingUI:GetFont(cfg.textFont), cfg.textSize or 12, "OUTLINE")
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:ClearAllPoints()
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", DDingUI:Scale(cfg.textX or 0), DDingUI:Scale(cfg.textY or 0))


    -- Show text
    bar.TextFrame:SetShown(cfg.showText ~= false)

    -- Handle hide bar but show text option
    if cfg.hideBarShowText then
        -- Hide the bar visuals but keep text visible
        if bar.StatusBar then
            bar.StatusBar:Hide()
        end
        if bar.Background then
            bar.Background:Hide()
        end
        -- Hide border when bar is hidden
        if bar.Border then
            bar.Border:Hide()
        end
        -- Hide ticks when bar is hidden
        for _, tick in ipairs(bar.ticks) do
            tick:Hide()
        end
        -- Hide fragmented power bars (runes) when bar is hidden
        for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
            fragmentBar:Hide()
        end
        -- Hide rune timer texts when bar is hidden
        for _, runeText in ipairs(bar.FragmentedPowerBarTexts) do
            if runeText then
                runeText:Hide()
            end
        end
    else
        -- Show the bar visuals
        if bar.StatusBar then
            bar.StatusBar:Show()
        end
        if bar.Background then
            bar.Background:Show()
        end
        -- Show border if size > 0
        if bar.Border and (bar._scaledBorder or DDingUI:ScaleBorder(cfg.borderSize or 1)) > 0 then
            bar.Border:Show()
        end
        -- Update ticks if this is a ticked power type and not fragmented
        if not fragmentedPowerTypes[resource] then
            self:UpdateSecondaryPowerBarTicks(bar, resource, visualMax)
        end
    end

    -- Update per-point color overlays (below charged overlays)
    self:UpdatePerPointColorSegments(bar, resource, visualMax, current)

    -- Update overflow color overlays (above per-point, below charged)
    self:UpdateOverflowColorSegments(bar, resource, visualMax, current)

    -- Update charged power overlays (e.g., Charged Combo Points)
    self:UpdateChargedPowerSegments(bar, resource, visualMax)

    -- Update custom markers
    self:UpdateSecondaryPowerBarMarkers(bar, visualMax)

    bar:Show()
end

function ResourceBars:UpdateSecondaryPowerBarMarkers(bar, max)
    local cfg = DDingUI.db.profile.secondaryPowerBar
    local markers = cfg.markers

    -- Hide all existing marker textures first
    if bar.markers then
        for _, m in ipairs(bar.markers) do
            m:Hide()
        end
    end

    if not markers or #markers == 0 or not max or max <= 0 then
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    local c = cfg.markerColor or { 1, 1, 1, 0.8 }
    local mWidth = math.max(1, DDingUI:Scale(cfg.markerWidth or 2))

    -- Marker line frame: above all color overlays (frame level +15)
    if not bar._markerLineFrame then
        bar._markerLineFrame = CreateFrame("Frame", nil, bar)
        bar._markerLineFrame:SetAllPoints(bar.StatusBar)
        bar._markerLineFrame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 15)
        bar.markers = {}
    end

    for i, rawVal in ipairs(markers) do
        local val = type(rawVal) == "table" and rawVal.value or rawVal
        if not val or type(val) ~= "number" then val = 0 end

        local marker = bar.markers[i]
        if not marker then
            marker = bar._markerLineFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            bar.markers[i] = marker
        end

        if val > 0 and val < max then
            local x = math_floor((val / max) * width)
            marker:ClearAllPoints()
            marker:SetPoint("LEFT", bar.StatusBar, "LEFT", x, 0)
            marker:SetSize(mWidth, height)
            marker:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            marker:Show()
        else
            marker:Hide()
        end
    end
end

-- Expose to main addon for backwards compatibility
DDingUI.GetSecondaryPowerBar = function(self) return ResourceBars:GetSecondaryPowerBar() end
DDingUI.UpdateSecondaryPowerBar = function(self) return ResourceBars:UpdateSecondaryPowerBar() end
DDingUI.UpdateSecondaryPowerBarTicks = function(self, bar, resource, max) return ResourceBars:UpdateSecondaryPowerBarTicks(bar, resource, max) end
DDingUI.CreateFragmentedPowerBars = function(self, bar, resource) return ResourceBars:CreateFragmentedPowerBars(bar, resource) end
DDingUI.UpdateFragmentedPowerDisplay = function(self, bar, resource) return ResourceBars:UpdateFragmentedPowerDisplay(bar, resource) end
DDingUI.UpdateChargedPowerSegments = function(self, bar, resource, max) return ResourceBars:UpdateChargedPowerSegments(bar, resource, max) end
DDingUI.UpdatePerPointColorSegments = function(self, bar, resource, max, current) return ResourceBars:UpdatePerPointColorSegments(bar, resource, max, current) end
DDingUI.UpdateOverflowColorSegments = function(self, bar, resource, max, current) return ResourceBars:UpdateOverflowColorSegments(bar, resource, max, current) end

