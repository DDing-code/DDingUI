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

-- Get ResourceBars module
local ResourceBars = DDingUI.ResourceBars
if not ResourceBars then
    error("DDingUI: ResourceBars module not initialized! Load ResourceDetection.lua first.")
end

-- Get functions from ResourceDetection
local GetPrimaryResource = ResourceBars.GetPrimaryResource
local GetSecondaryResource = ResourceBars.GetSecondaryResource
local GetResourceColor = ResourceBars.GetResourceColor
local GetPrimaryResourceValue = ResourceBars.GetPrimaryResourceValue
local tickedPowerTypes = ResourceBars.tickedPowerTypes
local buildVersion = ResourceBars.buildVersion

-- ========================================
-- Texture-based border helper (no SetBackdrop = no taint)
-- ========================================
-- [REFACTOR] 공통 TextureBorder 유틸리티는 Toolkit.lua DDingUI.CreateTextureBorder 등에서 제공
local CreateTextureBorder = DDingUI.CreateTextureBorder
local UpdateTextureBorderColor = DDingUI.UpdateTextureBorderColor
local UpdateTextureBorderSize = DDingUI.UpdateTextureBorderSize
local ShowTextureBorder = DDingUI.ShowTextureBorder

-- Check if player has secondary resource (실제 값이 있는지도 확인)
local function HasSecondaryResource()
    local secondaryResource = GetSecondaryResource and GetSecondaryResource()
    if not secondaryResource then return false end

    -- SOUL/STAGGER/MAELSTROM_WEAPON은 항상 있음 (폴백 메서드 지원)
    if secondaryResource == "SOUL" or secondaryResource == "STAGGER" or secondaryResource == "MAELSTROM_WEAPON" then
        return true
    end

    -- PowerType인 경우 max가 0보다 큰지 확인
    if type(secondaryResource) == "number" then
        local max = UnitPowerMax("player", secondaryResource)
        return type(max) == "number" and max > 0
    end

    return true
end

-- Use shared PixelSnap from Toolkit
local PixelSnap = DDingUI.PixelSnapLocal or function(value)
    return math_max(0, math_floor((value or 0) + 0.5))
end

-- ===================================================================
-- COLORCURVE THRESHOLD SYSTEM -- Uses UnitPowerPercent with ColorCurve for secret-value safe threshold colors
-- Hardcoded thresholds: 0-35% red, 35-70% yellow, 70-100% base color
-- ===================================================================
local powerBarColorCurve = nil  -- Cached curve
local powerBarColorCurveHash = nil  -- Cache key based on base color

-- Create or get cached ColorCurve for power bar
local function GetPowerBarColorCurve(cfg, baseColor)
    if not cfg.thresholdEnabled then return nil end

    -- Check if ColorCurve API exists (WoW 12.0+)
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
        return nil
    end

    -- Create hash based on base color only (thresholds are hardcoded)
    local bc = baseColor or {1, 1, 1, 1}
    local currentHash = string.format("%.2f,%.2f,%.2f", bc[1] or bc.r or 1, bc[2] or bc.g or 1, bc[3] or bc.b or 1)

    -- Return cached curve if base color hasn't changed
    if powerBarColorCurve and powerBarColorCurveHash == currentHash then
        return powerBarColorCurve
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
    powerBarColorCurve = curve
    powerBarColorCurveHash = currentHash
    return curve
end

-- PRIMARY POWER BAR

function ResourceBars:GetPowerBar()
    if DDingUI.powerBar then return DDingUI.powerBar end

    local cfg = DDingUI.db.profile.powerBar
    local anchor = DDingUI:ResolveAnchorFrame(cfg.attachTo)
    local anchorPoint = cfg.anchorPoint or "CENTER"



    local bar = CreateFrame("Frame", ADDON_NAME .. "PowerBar", UIParent)  -- [FIX] 항상 UIParent 자식 (엘레베이터 방지)
    bar:SetIgnoreParentAlpha(true)
    bar:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    bar:SetHeight(DDingUI:Scale(cfg.height or 6))
    local initSelfPoint = cfg.selfPoint or "CENTER" -- [FIX: selfPoint support]
    bar:SetPoint(initSelfPoint, anchor, anchorPoint, DDingUI:Scale(cfg.offsetX or 0), DDingUI:Scale(cfg.offsetY or 6))

    local MAX_AUTO_WIDTH_INIT = 600
    local width = cfg.width or 0
    if width <= 0 then
        -- Auto width: get from viewer or anchor content width
        local effectiveWidth, needsBorderComp = DDingUI:GetEffectiveAnchorWidth(anchor)
        if effectiveWidth and effectiveWidth > 0 and effectiveWidth <= MAX_AUTO_WIDTH_INIT and anchor ~= UIParent then
            if needsBorderComp then
                -- [FIX] CDM 아이콘 컨테이너: 보더가 프레임 바깥으로 확장되므로 양쪽 보더 두께만큼 차감
                local bComp = DDingUI:ScaleBorder(cfg.borderSize or 1)
                width = PixelSnap(effectiveWidth - 2 * bComp)
            else
                -- 일반 프레임 (다른 바 등): 이미 보더가 반영된 너비이므로 그대로 사용
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

    -- BACKGROUND
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    -- STATUS BAR
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    -- Use GetTexture helper: if cfg.texture is set, use it; otherwise use global texture
    local tex = DDingUI:GetTexture(cfg.texture)
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel())

    -- Hide the StatusBar's internal background texture so it doesn't interfere with our custom solid color background
    for i = 1, select("#", bar.StatusBar:GetRegions()) do
        local region = select(i, bar.StatusBar:GetRegions())
        if region:GetObjectType() == "Texture" and region ~= bar.StatusBar:GetStatusBarTexture() then
            region:Hide()
        end
    end

    -- BORDER (texture-based, no SetBackdrop = no taint)
    bar.Border = CreateFrame("Frame", nil, bar)
    bar.Border:SetAllPoints(bar)
    local borderSize = DDingUI:ScaleBorder(cfg.borderSize or 1)
    local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
    CreateTextureBorder(bar.Border, borderSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

    -- TEXT FRAME (설정된 strata 사용 - GUI보다 아래에 표시)
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

    -- TICKS
    bar.ticks = {}

    -- MARKERS (custom divider lines)
    bar.markers = {}

    bar:Hide()

    DDingUI.powerBar = bar
    return bar
end

function ResourceBars:UpdatePowerBar()
    local cfg = DDingUI.db.profile.powerBar
    if not cfg.enabled then
        if DDingUI.powerBar then
            DDingUI.powerBar:Hide()
            DDingUI.powerBar:SetScript("OnUpdate", nil)
        end
        return
    end

    local bar = self:GetPowerBar()

    local anchor = DDingUI:ResolveAnchorFrame(cfg.attachTo)
    -- 자기 자신을 앵커로 설정하면 UIParent로 폴백
    if anchor == bar or cfg.attachTo == "DDingUIPowerBar" then
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
            -- 앵커 복구 시 자동 재시도
            if not bar._anchorRetryScheduled then
                bar._anchorRetryScheduled = true
                C_Timer.After(0.2, function() ResourceBars:UpdatePowerBar() end)
                C_Timer.After(0.5, function() ResourceBars:UpdatePowerBar() end)
                C_Timer.After(1.0, function()
                    bar._anchorRetryScheduled = nil
                    ResourceBars:UpdatePowerBar()
                end)
                C_Timer.After(2.0, function() ResourceBars:UpdatePowerBar() end)
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
            C_Timer.After(0.2, function() ResourceBars:UpdatePowerBar() end)
            C_Timer.After(0.5, function() ResourceBars:UpdatePowerBar() end)
            C_Timer.After(1.0, function()
                bar._anchorRetryScheduled = nil
                local originalAnchor = DDingUI:ResolveAnchorFrame(cfg.attachTo)
                if originalAnchor and originalAnchor:IsShown() then
                    bar._anchorRetryCount = 0
                end
                ResourceBars:UpdatePowerBar()
            end)
            C_Timer.After(2.0, function()
                local originalAnchor = DDingUI:ResolveAnchorFrame(cfg.attachTo)
                if originalAnchor and originalAnchor:IsShown() then
                    bar._anchorRetryCount = 0
                    ResourceBars:UpdatePowerBar()
                end
            end)
        end
    else
        -- 앵커 찾으면 카운터 리셋
        bar._anchorRetryCount = 0
        bar._anchorRetryScheduled = nil

        -- [FIX] SetParent(anchor) 제거 — 엘레베이터 현상 근본 원인
        -- 스펙 변경 시 그룹 프레임이 재생성되면 부모가 바뀌면서 오프셋이 누적됨
        -- SetIgnoreParentAlpha(true)로 이미 alpha 상속을 차단하므로 SetParent 불필요
        if bar:GetParent() ~= UIParent then
            bar:SetParent(UIParent)
            bar:SetIgnoreParentAlpha(true)
        end
    end

    -- Setup/teardown OnUpdate ticker for faster updates
    if cfg.fasterUpdates then
        local updateFrequency = cfg.updateFrequency or 0.1
        -- 주파수 변경 시에만 함수 재생성 (매 호출마다 새 함수 객체 생성 방지)
        if not bar._onUpdateFunc or bar._onUpdateFreq ~= updateFrequency then
            bar._onUpdateFreq = updateFrequency
            bar._onUpdateFunc = function(frame, elapsed)
                frame._updateElapsed = (frame._updateElapsed or 0) + elapsed
                if frame._updateElapsed >= (frame._onUpdateFreq or 0.1) then
                    frame._updateElapsed = 0
                    ResourceBars:UpdatePowerBar()
                end
            end
            bar:SetScript("OnUpdate", bar._onUpdateFunc)
        end
    else
        if bar._onUpdateFunc then
            bar:SetScript("OnUpdate", nil)
            bar._onUpdateFunc = nil
        end
    end

    local resource = GetPrimaryResource()

    if not resource then
        -- Grace Period 중에는 바를 숨기지 않음 (전문화 변경 시 잠시 nil일 수 있음)
        if not inGracePeriod then
            bar:Hide()
        end
        return
    end

    -- Check if we should hide the bar when power is mana (DPS spec only)
    if cfg.hideWhenMana and resource == Enum.PowerType.Mana then
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if role == "DAMAGER" then
            -- Grace Period 중에는 숨기지 않음 (전문화 변경 시 일시적으로 Mana로 감지될 수 있음)
            if not inGracePeriod then
                bar:Hide()
            end
            return
        end
    end

    -- Check if we should use "no secondary" size
    -- Use when: no secondary resource OR secondary power bar is disabled OR secondary is mana and hideWhenMana is enabled (DPS only)
    local hasSecondary = HasSecondaryResource()
    local secondaryCfg = DDingUI.db.profile.secondaryPowerBar
    local secondaryDisabled = secondaryCfg and not secondaryCfg.enabled
    local secondaryResource = GetSecondaryResource and GetSecondaryResource()
    local secondaryHiddenDueToMana = false
    if secondaryCfg and secondaryCfg.hideWhenMana and secondaryResource == Enum.PowerType.Mana then
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if role == "DAMAGER" then
            secondaryHiddenDueToMana = true
        end
    end
    local useNoSecondarySize = cfg.useNoSecondarySize and (not hasSecondary or secondaryDisabled or secondaryHiddenDueToMana)



    -- Update layout
    local desiredHeight
    if useNoSecondarySize then
        desiredHeight = DDingUI:Scale(cfg.noSecondaryHeight or cfg.height or 6)
    else
        desiredHeight = DDingUI:Scale(cfg.height or 6)
    end

    do -- positioning block
        local anchorPoint
        local desiredX, desiredY
        if anchorFallback then
            -- [FIX] 앵커 비활성 → 현재 화면 위치 유지 (CENTER fallback 완전 제거)
            -- 바가 이미 화면에 있으면 그 위치를 UIParent 기준 상대좌표로 변환
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
                desiredY = DDingUI:Scale(cfg.offsetY or 0)
            end
        else
            anchorPoint = cfg.anchorPoint or "CENTER"
            desiredX = DDingUI:Scale(cfg.offsetX or 0)
            desiredY = DDingUI:Scale(cfg.offsetY or 0)
        end

        -- 기준점 (selfPoint): 명시적 설정이 있으면 사용, 없으면 앵커 기반 자동 변환 -- [FIX: selfPoint support]
        local barAnchorPoint
        if cfg.selfPoint then
            barAnchorPoint = cfg.selfPoint
        else
            -- 레거시: 앵커 포인트에 따른 barAnchorPoint 변환
            -- TOP 앵커: 바를 anchor 위에 배치, 위로 확장 → barAnchorPoint = BOTTOM
            -- BOTTOM 앵커: 바를 anchor 아래에 배치, 아래로 확장 → barAnchorPoint = TOP
            -- CENTER 앵커: 바를 anchor 중앙에 배치, 양쪽으로 확장 → barAnchorPoint = CENTER
            if anchorPoint == "TOP" then
                barAnchorPoint = "BOTTOM"
            elseif anchorPoint == "BOTTOM" then
                barAnchorPoint = "TOP"
            else
                barAnchorPoint = anchorPoint
            end
        end

        local width
        local cfgWidth
        if useNoSecondarySize then
            cfgWidth = cfg.noSecondaryWidth or cfg.width or 0
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
        -- Only reposition / resize when something actually changed to avoid texture flicker
        local needsReposition = bar._lastAnchor ~= anchor or bar._lastAnchorPoint ~= anchorPoint
            or bar._lastOffsetX ~= desiredX or bar._lastOffsetY ~= desiredY
            or bar._lastBarAnchorPoint ~= barAnchorPoint
        if needsReposition and not isInMoverMode then
            bar:ClearAllPoints()
            bar:SetPoint(barAnchorPoint, anchor, anchorPoint, desiredX, desiredY)
            bar._lastAnchor = anchor
            bar._lastAnchorPoint = anchorPoint
            bar._lastOffsetX = desiredX
            bar._lastOffsetY = desiredY
            bar._lastBarAnchorPoint = barAnchorPoint
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
        bar._lastTexture = tex

        -- Re-hide the StatusBar's internal background texture after texture change
        for i = 1, select("#", bar.StatusBar:GetRegions()) do
            local region = select(i, bar.StatusBar:GetRegions())
            if region:GetObjectType() == "Texture" and region ~= bar.StatusBar:GetStatusBarTexture() then
                region:Hide()
            end
        end
    end

    -- Update border size and color (texture-based)
    local borderSize = cfg.borderSize or 1
    if bar.Border then
        local scaledBorder = DDingUI:ScaleBorder(borderSize)
        UpdateTextureBorderSize(bar.Border, scaledBorder)
        local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
        UpdateTextureBorderColor(bar.Border, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        ShowTextureBorder(bar.Border, scaledBorder > 0)
    end

    -- Get resource values
    local max, _, current, displayValue, valueType = GetPrimaryResourceValue(resource, cfg)
    if not max then
        -- Grace Period 중에는 바를 숨기지 않음
        if not inGracePeriod then
            bar:Hide()
        end
        return
    end

    -- Set bar values
    local interpolation = cfg.smoothProgress and buildVersion >= 120000 and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
    bar.StatusBar:SetMinMaxValues(0, max, interpolation)
    bar.StatusBar:SetValue(current, interpolation)

    -- Set bar color
    local powerTypeColors = DDingUI.db.profile.powerTypeColors
    local baseR, baseG, baseB, baseA = 1, 1, 1, 1

    if powerTypeColors.useClassColor then
        -- Class color
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            baseR, baseG, baseB = classColor.r, classColor.g, classColor.b
        else
            -- Fallback to resource color
            local color = GetResourceColor(resource)
            baseR, baseG, baseB = color.r, color.g, color.b
        end
    elseif powerTypeColors.colors[resource] then
        -- Power type specific color
        local color = powerTypeColors.colors[resource]
        baseR, baseG, baseB, baseA = color[1], color[2], color[3], color[4] or 1
    else
        -- Default resource color
        local color = GetResourceColor(resource)
        baseR, baseG, baseB = color.r, color.g, color.b
    end

    -- Apply threshold colors if enabled (ColorCurve + UnitPowerPercent)
    local thresholdApplied = false
    if cfg.thresholdEnabled then
        local baseColor = {baseR, baseG, baseB, baseA}
        local colorCurve = GetPowerBarColorCurve(cfg, baseColor)

        if colorCurve and resource and resource >= 0 then
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

    -- Only use base colors if threshold wasn't applied
    if not thresholdApplied then
        bar.StatusBar:SetStatusBarColor(baseR, baseG, baseB, baseA)
    end

    -- Marker color overlay: clip frame + overlay StatusBar (secret value safe)
    -- No numeric comparison needed - StatusBar handles secret values internally
    local _defaultMarkerColors = {
        {1, 0.3, 0.3, 1}, {1, 1, 0.3, 1}, {0.3, 1, 0.3, 1},
        {0.3, 0.7, 1, 1}, {1, 0.5, 1, 1},
    }
    if cfg.markerColorChange and cfg.markers and #cfg.markers > 0 then
        local barWidth = bar.StatusBar:GetWidth()
        if barWidth > 0 and max > 0 then
            bar._markerOverlays = bar._markerOverlays or {}
            local mainTex = bar.StatusBar:GetStatusBarTexture()
            local texPath = mainTex and mainTex:GetTexture()
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

    -- Update text
    if valueType == "percent" then
        local precision = cfg.textPrecision or 0
        local percentSign = cfg.showPercentSign ~= false and "%%" or ""
        bar.TextValue:SetText(string.format("%." .. precision .. "f" .. percentSign, displayValue))
    else
        bar.TextValue:SetText(tostring(displayValue))
    end

    bar.TextValue:SetFont(DDingUI:GetFont(cfg.textFont), cfg.textSize or 12, "OUTLINE")
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:ClearAllPoints()
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", DDingUI:Scale(cfg.textX or 0), DDingUI:Scale(cfg.textY or 0))

    -- Show text based on config
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
    else
        -- Show the bar visuals
        if bar.StatusBar then
            bar.StatusBar:Show()
        end
        if bar.Background then
            bar.Background:Show()
        end
        -- Show border if size > 0
        if bar.Border and (cfg.borderSize or 1) > 0 then
            bar.Border:Show()
        end
        -- Update ticks if this is a ticked power type
        self:UpdatePowerBarTicks(bar, resource, max)
        -- Update custom markers
        self:UpdatePowerBarMarkers(bar, max)
    end

    bar:Show()
end

function ResourceBars:UpdatePowerBarTicks(bar, resource, max)
    local cfg = DDingUI.db.profile.powerBar
    
    -- Hide all ticks first
    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    if not cfg.showTicks or not tickedPowerTypes[resource] then
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    local needed = max - 1
    for i = 1, needed do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(0, 0, 0, 1)
            bar.ticks[i] = tick
        end
        
        local x = math_floor((i / max) * width)
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

function ResourceBars:UpdatePowerBarMarkers(bar, max)
    local cfg = DDingUI.db.profile.powerBar
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
    local mWidth = math_max(1, DDingUI:Scale(cfg.markerWidth or 2))

    -- Marker line frame: above all color overlays (frame level +15)
    if not bar._markerLineFrame then
        bar._markerLineFrame = CreateFrame("Frame", nil, bar)
        bar._markerLineFrame:SetAllPoints(bar.StatusBar)
        bar._markerLineFrame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 15)
        -- Force recreate markers as children of the new frame
        bar.markers = {}
    end

    for i, rawVal in ipairs(markers) do
        -- Backward compat: old format {value=30, color=...} → new format plain number
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
DDingUI.GetPowerBar = function(self) return ResourceBars:GetPowerBar() end
DDingUI.UpdatePowerBar = function(self) return ResourceBars:UpdatePowerBar() end
DDingUI.UpdatePowerBarTicks = function(self, bar, resource, max) return ResourceBars:UpdatePowerBarTicks(bar, resource, max) end

-- Debug command for threshold

