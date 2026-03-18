local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

-- 핫패스 글로벌 → 로컬 캐싱 (성능 최적화)
local GetTime = GetTime
local C_UnitAuras = C_UnitAuras
local C_Timer = C_Timer
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local string_format = string.format

-- Debug flag (파일 상단에 정의하여 전체에서 사용 가능)
local BUFF_TRACKER_DEBUG = false

-- Get ResourceBars module
local ResourceBars = DDingUI.ResourceBars
if not ResourceBars then
    error("DDingUI: ResourceBars module not initialized! Load ResourceDetection.lua first.")
end

local buildVersion = ResourceBars.buildVersion

-- ========================================
-- Texture-based border helper (no SetBackdrop = no taint)
-- ========================================
local function CreateTextureBorder(parent, borderSize, r, g, b, a)
    parent.__dduiBorders = parent.__dduiBorders or {}
    local borders = parent.__dduiBorders

    if #borders == 0 then
        local function CreateBorderTex()
            local tex = parent:CreateTexture(nil, "OVERLAY")
            tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
            return tex
        end
        borders[1] = CreateBorderTex()  -- top
        borders[2] = CreateBorderTex()  -- bottom
        borders[3] = CreateBorderTex()  -- left
        borders[4] = CreateBorderTex()  -- right
        parent.__dduiBorders = borders
    end

    local top, bottom, left, right = borders[1], borders[2], borders[3], borders[4]

    -- Top border
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", -borderSize, borderSize)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", borderSize, borderSize)
    top:SetHeight(borderSize)

    -- Bottom border
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -borderSize, -borderSize)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", borderSize, -borderSize)
    bottom:SetHeight(borderSize)

    -- Left border
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", -borderSize, borderSize)
    left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -borderSize, -borderSize)
    left:SetWidth(borderSize)

    -- Right border
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", borderSize, borderSize)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", borderSize, -borderSize)
    right:SetWidth(borderSize)

    return borders
end

local function UpdateTextureBorderColor(parent, r, g, b, a)
    local borders = parent.__dduiBorders
    if not borders then return end
    for _, tex in ipairs(borders) do
        tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end
end

local function UpdateTextureBorderSize(parent, borderSize)
    local borders = parent.__dduiBorders
    if not borders or #borders < 4 then return end

    local top, bottom, left, right = borders[1], borders[2], borders[3], borders[4]

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", -borderSize, borderSize)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", borderSize, borderSize)
    top:SetHeight(borderSize)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -borderSize, -borderSize)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", borderSize, -borderSize)
    bottom:SetHeight(borderSize)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", -borderSize, borderSize)
    left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -borderSize, -borderSize)
    left:SetWidth(borderSize)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", borderSize, borderSize)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", borderSize, -borderSize)
    right:SetWidth(borderSize)
end

local function ShowTextureBorder(parent, show)
    local borders = parent.__dduiBorders
    if not borders then return end
    for _, tex in ipairs(borders) do
        tex:SetShown(show)
    end
end

-- Mover mode flag (forces all bars to show regardless of hideWhenZero)
local isInMoverMode = false
local moverPositionSynced = false  -- true after initial position sync in mover mode

-- Preview mode flag (shows bars in options panel for configuration)
local isInPreviewMode = false

-- Preview animation state (per bar index)
local previewState = {}  -- { [barIndex] = { stacks = N, duration = N, lastUpdate = time } }
local previewTicker = nil
local PREVIEW_STACK_INTERVAL = 1.5  -- Change stacks every 1.5 seconds
local PREVIEW_DURATION_TICK = 0.1   -- Update duration every 0.1 seconds

-- Get preview values for a bar
local function GetPreviewValues(barIndex, maxStacks, maxDuration, barFillMode)
    if not previewState[barIndex] then
        previewState[barIndex] = {
            stacks = math.random(1, maxStacks),
            duration = maxDuration,
            lastStackUpdate = GetTime(),
        }
    end

    local state = previewState[barIndex]
    local now = GetTime()

    -- Update stacks randomly every interval
    if now - state.lastStackUpdate >= PREVIEW_STACK_INTERVAL then
        state.stacks = math.random(0, maxStacks)
        state.lastStackUpdate = now
    end

    -- Countdown duration
    state.duration = state.duration - PREVIEW_DURATION_TICK
    if state.duration <= 0 then
        state.duration = maxDuration  -- Reset to max
    end

    if barFillMode == "duration" then
        return state.duration, state.duration
    else
        return state.stacks, state.stacks
    end
end

-- Start preview ticker (only for preview mode, not mover mode)
local function StartPreviewTicker()
    if previewTicker then return end
    if not isInPreviewMode then return end  -- Only start for preview mode
    previewTicker = C_Timer.NewTicker(PREVIEW_DURATION_TICK, function()
        if not isInPreviewMode then
            if previewTicker then
                previewTicker:Cancel()
                previewTicker = nil
            end
            return
        end
        -- Trigger update
        ResourceBars:UpdateBuffTrackerBar()
    end)
end

-- Stop preview ticker
local function StopPreviewTicker()
    if previewTicker then
        previewTicker:Cancel()
        previewTicker = nil
    end
    previewState = {}  -- Reset state
end

-- Use shared PixelSnap from Toolkit
local PixelSnap = DDingUI.PixelSnapLocal or function(value)
    return math.max(0, math.floor((value or 0) + 0.5))
end

-- ============================================================
-- ADVANCED ANIMATION SYSTEM (using LibCustomGlow)
-- ============================================================
local LCG = LibStub("LibCustomGlow-1.0", true)

-- Glow type functions with customizable parameters
-- glowSettings = { color = {r,g,b,a}, lines = 8, frequency = 0.25, thickness = 2, xOffset = 0, yOffset = 0 }
local function StartPixelGlow(frame, glowSettings)
    if not frame or not LCG then return end
    local settings = glowSettings or {}
    local color = settings.color or {1, 1, 0.3, 1}
    local lines = math.floor(settings.lines or 8)  -- must be integer
    local frequency = settings.frequency or 0.25
    local thickness = settings.thickness or 2
    local xOffset = settings.xOffset or 0
    local yOffset = settings.yOffset or 0
    LCG.PixelGlow_Start(frame, color, lines, frequency, nil, thickness, xOffset, yOffset)
end

local function StartAutoCastGlow(frame, glowSettings)
    if not frame or not LCG then return end
    local settings = glowSettings or {}
    local color = settings.color or {1, 1, 0.3, 1}
    local particles = math.floor(settings.lines or 8)  -- particles count (must be integer)
    local frequency = settings.frequency or 0.25
    local scale = settings.thickness or 1  -- scale
    local xOffset = settings.xOffset or 0
    local yOffset = settings.yOffset or 0
    LCG.AutoCastGlow_Start(frame, color, particles, frequency, scale, xOffset, yOffset)
end

local function StartButtonGlow(frame, glowSettings)
    if not frame or not LCG then return end
    local settings = glowSettings or {}
    local color = settings.color or {1, 0.9, 0.5, 1}
    local frequency = settings.frequency or 0.125
    LCG.ButtonGlow_Start(frame, color, frequency)
end

local function StartProcGlow(frame, glowSettings)
    if not frame or not LCG then return end
    local settings = glowSettings or {}
    local color = settings.color or {0.95, 0.95, 0.32, 1}
    local duration = settings.frequency or 1  -- proc duration
    LCG.ProcGlow_Start(frame, {color = color, duration = duration, startAnim = true})
end

local function StopAllGlows(frame)
    if not frame or not LCG then return end
    LCG.PixelGlow_Stop(frame)
    LCG.AutoCastGlow_Stop(frame)
    LCG.ButtonGlow_Stop(frame)
    LCG.ProcGlow_Stop(frame)
end

-- Start glow based on type
local function StartGlow(frame, glowType, glowSettings)
    if not frame then return end
    StopAllGlows(frame)  -- Stop any existing glow first

    if glowType == "pixel" then
        StartPixelGlow(frame, glowSettings)
    elseif glowType == "autocast" then
        StartAutoCastGlow(frame, glowSettings)
    elseif glowType == "button" then
        StartButtonGlow(frame, glowSettings)
    elseif glowType == "proc" then
        StartProcGlow(frame, glowSettings)
    end
end

-- Hover (bounce) animation (reuses AnimationGroup to prevent memory leak)
local function StartHoverAnimation(frame)
    if not frame then return end

    -- Reuse existing AnimationGroup
    if frame._hoverAnimation then
        if not frame._hoverAnimation:IsPlaying() then
            frame._hoverAnimation:Play()
        end
        return
    end

    local ag = frame:CreateAnimationGroup()

    -- Move up
    local moveUp = ag:CreateAnimation("Translation")
    moveUp:SetOffset(0, 5)
    moveUp:SetDuration(0.3)
    moveUp:SetOrder(1)
    moveUp:SetSmoothing("OUT")

    -- Move down
    local moveDown = ag:CreateAnimation("Translation")
    moveDown:SetOffset(0, -5)
    moveDown:SetDuration(0.3)
    moveDown:SetOrder(2)
    moveDown:SetSmoothing("IN")

    ag:SetLooping("REPEAT")
    frame._hoverAnimation = ag
    ag:Play()
end

local function StopHoverAnimation(frame)
    if not frame then return end
    if frame._hoverAnimation and frame._hoverAnimation:IsPlaying() then
        frame._hoverAnimation:Stop()
    end
end

-- Pulse animation (scale) (reuses AnimationGroup to prevent memory leak)
local function StartPulseAnimation(frame)
    if not frame then return end

    -- Reuse existing AnimationGroup
    if frame._pulseAnimation then
        if not frame._pulseAnimation:IsPlaying() then
            frame._pulseAnimation:Play()
        end
        return
    end

    local ag = frame:CreateAnimationGroup()

    local scaleUp = ag:CreateAnimation("Scale")
    scaleUp:SetScale(1.15, 1.15)
    scaleUp:SetDuration(0.4)
    scaleUp:SetOrder(1)
    scaleUp:SetSmoothing("OUT")

    local scaleDown = ag:CreateAnimation("Scale")
    scaleDown:SetScale(1/1.15, 1/1.15)
    scaleDown:SetDuration(0.4)
    scaleDown:SetOrder(2)
    scaleDown:SetSmoothing("IN")

    ag:SetLooping("REPEAT")
    frame._pulseAnimation = ag
    ag:Play()
end

local function StopPulseAnimation(frame)
    if not frame then return end
    if frame._pulseAnimation and frame._pulseAnimation:IsPlaying() then
        frame._pulseAnimation:Stop()
        frame:SetScale(1)
    end
end

-- Flash animation (alpha) (reuses AnimationGroup to prevent memory leak)
local function StartFlashAnimation(frame)
    if not frame then return end

    -- Reuse existing AnimationGroup
    if frame._flashAnimation then
        if not frame._flashAnimation:IsPlaying() then
            frame._flashAnimation:Play()
        end
        return
    end

    local ag = frame:CreateAnimationGroup()

    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.3)
    fadeOut:SetDuration(0.4)
    fadeOut:SetOrder(1)

    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.3)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.4)
    fadeIn:SetOrder(2)

    ag:SetLooping("REPEAT")
    frame._flashAnimation = ag
    ag:Play()
end

local function StopFlashAnimation(frame)
    if not frame then return end
    if frame._flashAnimation and frame._flashAnimation:IsPlaying() then
        frame._flashAnimation:Stop()
        frame:SetAlpha(1)
    end
end

-- Spin animation (rotation) (reuses AnimationGroup to prevent memory leak)
local function StartSpinAnimation(frame)
    if not frame then return end

    -- Reuse existing AnimationGroup
    if frame._spinAnimation then
        if not frame._spinAnimation:IsPlaying() then
            frame._spinAnimation:Play()
        end
        return
    end

    local ag = frame:CreateAnimationGroup()

    local spin = ag:CreateAnimation("Rotation")
    spin:SetDegrees(360)
    spin:SetDuration(2)
    spin:SetOrder(1)

    ag:SetLooping("REPEAT")
    frame._spinAnimation = ag
    ag:Play()
end

local function StopSpinAnimation(frame)
    if not frame then return end
    if frame._spinAnimation and frame._spinAnimation:IsPlaying() then
        frame._spinAnimation:Stop()
    end
end

-- Stop all animations on a frame
local function StopAllAnimations(frame)
    if not frame then return end
    StopAllGlows(frame)
    StopHoverAnimation(frame)
    StopPulseAnimation(frame)
    StopFlashAnimation(frame)
    StopSpinAnimation(frame)
    frame._glowAnimation = false
end

-- Apply animation based on type with settings
local function ApplyIconAnimation(frame, animationType, glowSettings)
    if not frame then return end

    -- Stop all first
    StopAllAnimations(frame)

    if animationType == "none" then
        return
    elseif animationType == "hover" then
        StartHoverAnimation(frame)
    elseif animationType == "pulse" then
        StartPulseAnimation(frame)
    elseif animationType == "flash" then
        StartFlashAnimation(frame)
    elseif animationType == "spin" then
        StartSpinAnimation(frame)
    elseif animationType == "pixel" or animationType == "autocast" or animationType == "button" or animationType == "proc" then
        StartGlow(frame, animationType, glowSettings)
        frame._glowAnimation = true
    elseif animationType == "glow" then
        -- Legacy "glow" option - use button glow
        StartGlow(frame, "button", glowSettings)
        frame._glowAnimation = true
    elseif animationType == "shine" then
        -- Legacy "shine" option - use pixel glow
        StartGlow(frame, "pixel", glowSettings)
        frame._glowAnimation = true
    end
end

-- Legacy wrapper for backward compatibility
local function ShowOverlayGlow(frame)
    if not frame then return end
    StartGlow(frame, "button", nil)
end

local function HideOverlayGlow(frame)
    if not frame then return end
    StopAllGlows(frame)
end

-- Get current specialization ID (unique across all classes, e.g., 64 = Frost Mage, 253 = BM Hunter)
local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

-- Format duration with decimal places -- Secret value는 직접 반환, 숫자는 포맷팅
local function FormatDuration(value, decimals)
    -- Secret value는 비교 연산 불가 - pcall로 안전하게 처리
    local isNil = false
    pcall(function()
        if value == nil then isNil = true end
    end)
    if isNil then return "" end

    decimals = decimals or 1

    local ok, formatted = pcall(function()
        local num = tonumber(value)
        if num then
            return string.format("%." .. decimals .. "f", num)
        end
        return value
    end)

    if ok and formatted then
        return formatted
    end
    return value  -- Secret value는 그대로 반환 (SetText에서 처리)
end

-- ============================================================
-- AUTO-DETECT AURA VALUES -- CDM에서 현재 활성화된 버프의 실제 값을 읽어옵니다.
-- ============================================================

-- Helper: Check if value is secret (WoW 12.0+ secret value handling)
local function IsSecretValue(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

-- Helper: Get spellID from cooldownID using C_CooldownViewer API (CDM API)
local function GetSpellIDFromCooldownID(cooldownID)
    if not cooldownID or not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return nil
    end

    local info
    pcall(function()
        info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    end)

    if not info then return nil end

    -- Priority: linkedSpellIDs[1] > overrideSpellID > spellID (CDM API)
    local spellID = nil
    pcall(function()
        if info.linkedSpellIDs and info.linkedSpellIDs[1] then
            spellID = info.linkedSpellIDs[1]
        elseif info.overrideSpellID and info.overrideSpellID > 0 then
            spellID = info.overrideSpellID
        elseif info.spellID and info.spellID > 0 then
            spellID = info.spellID
        end
    end)

    return spellID
end

-- Helper: Get max charges from spell (CDM API with secret value handling)
local function GetSpellMaxCharges(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellCharges then
        return nil
    end

    local chargeInfo
    pcall(function()
        chargeInfo = C_Spell.GetSpellCharges(spellID)
    end)

    if not chargeInfo then return nil end

    -- Check if maxCharges exists and is not secret
    if chargeInfo.maxCharges then
        if IsSecretValue(chargeInfo.maxCharges) then
            -- Secret value - return default for charge spells (default for charge spells)
            return 2
        end
        return chargeInfo.maxCharges
    end

    return nil
end

-- 버프에서 최대 중첩과 지속시간 자동 감지
-- Returns: maxStacks, duration, detected (boolean)
-- CDM API 방식: 실시간으로 CDM Viewer를 스캔하여 최신 auraInstanceID 가져오기
-- fallbackSpellID: 전투 중 Secret Value 우회용 (이미 알고 있는 spellID 전달)
function ResourceBars.AutoDetectAuraValues(cooldownID, fallbackSpellID)
    if (not cooldownID or cooldownID == 0) and not fallbackSpellID then
        return nil, nil, false
    end

    local detectedMaxStacks = nil
    local detectedDuration = nil

    -- 1. Get spellID from cooldownID (CDM API) or use fallback
    local spellID = GetSpellIDFromCooldownID(cooldownID) or fallbackSpellID

    -- 2. Try to get maxCharges from spell charges API
    if spellID then
        local maxCharges = GetSpellMaxCharges(spellID)
        if maxCharges and maxCharges > 0 then
            detectedMaxStacks = maxCharges
        end
    end

    -- 3. [NeverSecret API] spellID로 직접 조회 - 전투 중에도 작동!
    local autoDetectDebug = BUFF_TRACKER_DEBUG or IsShiftKeyDown()  -- Shift 누르면 항상 디버그
    if spellID then
        local ok, err = pcall(function()
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if autoDetectDebug then
                print("|cff00ccff[BT Debug]|r spellID:", spellID)
                print("|cff00ccff[BT Debug]|r GetPlayerAuraBySpellID:", auraData and "found" or "nil")
                if auraData then
                    print("|cff00ccff[BT Debug]|r   applications:", auraData.applications)
                    print("|cff00ccff[BT Debug]|r   duration:", auraData.duration)
                    print("|cff00ccff[BT Debug]|r   name:", auraData.name)
                end
            end
            if auraData then
                -- applications (현재 스택) - 0이면 비스택 버프 (1로 처리)
                local apps = auraData.applications
                if apps and apps > 0 then
                    if not detectedMaxStacks or apps > detectedMaxStacks then
                        detectedMaxStacks = apps
                    end
                elseif not detectedMaxStacks then
                    -- 비스택 버프: 활성화됨 = 1스택으로 취급
                    detectedMaxStacks = 1
                end
                -- duration (총 지속시간)
                if auraData.duration and auraData.duration > 0 then
                    detectedDuration = auraData.duration
                end
            end
        end)
        if not ok and BUFF_TRACKER_DEBUG then
            print("|cff00ccff[BT Debug]|r GetPlayerAuraBySpellID error:", err)
        end
    end

    -- 이미 감지됐으면 여기서 반환 (전투 중 Secret Value 우회 성공)
    if detectedMaxStacks and detectedDuration then
        return detectedMaxStacks, detectedDuration, true
    end

    -- 4. 실시간으로 CDM Viewer 스캔하여 프레임 찾기
    -- CDM 바 프레임의 GetMinMaxValues()에서 duration 읽기
    local frame = nil
    local viewers = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer then
            local children = { viewer:GetChildren() }
            for _, child in ipairs(children) do
                -- cooldownID 소스 다중 확인 (pcall로 감싸기)
                local cdID
                pcall(function()
                    cdID = child.cooldownID
                    if not cdID and child.cooldownInfo then
                        cdID = child.cooldownInfo.cooldownID
                    end
                    if not cdID and child.Icon and child.Icon.cooldownID then
                        cdID = child.Icon.cooldownID
                    end
                end)
                if cdID == cooldownID then
                    frame = child
                    break
                end
            end
        end
        if frame then break end
    end

    -- 4-1. CDM 바 프레임에서 maxDuration 읽기
    if frame and not detectedDuration then
        pcall(function()
            -- BuffBarCooldownViewer의 바 프레임에서 GetMinMaxValues
            if frame.Bar and frame.Bar.GetMinMaxValues then
                local _, maxVal = frame.Bar:GetMinMaxValues()
                if autoDetectDebug then
                    print("|cff00ccff[BT Debug]|r frame.Bar:GetMinMaxValues() maxVal:", maxVal)
                end
                if maxVal and maxVal > 0 then
                    detectedDuration = maxVal
                end
            end
            -- 또는 frame 자체가 StatusBar일 경우
            if not detectedDuration and frame.GetMinMaxValues then
                local _, maxVal = frame:GetMinMaxValues()
                if autoDetectDebug then
                    print("|cff00ccff[BT Debug]|r frame:GetMinMaxValues() maxVal:", maxVal)
                end
                if maxVal and maxVal > 0 then
                    detectedDuration = maxVal
                end
            end
        end)
    end

    -- 4-2. 실시간 auraInstanceID 가져오기
    local auraInstanceID
    if frame then
        pcall(function()
            auraInstanceID = frame.auraInstanceID
        end)
    end

    -- 5. C_CooldownViewer API에서 추가 정보 가져오기
    if not detectedMaxStacks then
        pcall(function()
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if info then
                    -- charges는 최대 충전/스택 수를 나타낼 수 있음
                    if info.charges and not IsSecretValue(info.charges) and info.charges > 0 then
                        detectedMaxStacks = info.charges
                    end
                end
            end
        end)
    end

    -- 6. AuraData에서 정보 가져오기 (GetAuraDataAutoUnit 방식)
    if auraInstanceID then
        -- player 먼저 시도, 없으면 target 시도 (CDM 방식)
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
        local unit = "player"
        if not auraData then
            auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("target", auraInstanceID)
            unit = "target"
        end

        if auraData then
            -- applications은 현재 스택 수
            local ok, apps = pcall(function()
                local a = auraData.applications
                if IsSecretValue(a) then return nil end
                return a
            end)
            if ok and apps and type(apps) == "number" then
                -- 현재 스택이 최대 스택보다 크면 업데이트
                if not detectedMaxStacks or apps > detectedMaxStacks then
                    detectedMaxStacks = apps
                end
            end

            -- duration은 총 지속시간
            local ok2, dur = pcall(function()
                local d = auraData.duration
                if IsSecretValue(d) then return nil end
                return d
            end)
            if ok2 and dur and type(dur) == "number" and dur > 0 then
                detectedDuration = dur
            end
        end
    end

    local detected = detectedMaxStacks ~= nil or detectedDuration ~= nil

    if BUFF_TRACKER_DEBUG then
        print("|cff00ccff[BT Debug]|r Final: maxStacks=" .. tostring(detectedMaxStacks) .. ", duration=" .. tostring(detectedDuration) .. ", detected=" .. tostring(detected))
    end

    return detectedMaxStacks, detectedDuration, detected
end

-- 외부에서 호출할 수 있도록 DDingUI에 노출
-- fallbackSpellID: 전투 중 Secret Value 우회용
DDingUI.AutoDetectAuraValues = function(cooldownID, fallbackSpellID)
    return ResourceBars.AutoDetectAuraValues(cooldownID, fallbackSpellID)
end

-- ============================================================
-- SCAN AVAILABLE BUFFS - CDM에서 추적 가능한 버프 목록 스캔 (CDM API 방식)
-- ============================================================
function ResourceBars.ScanAvailableBuffs()
    local availableBuffs = {}
    local seenCooldownIDs = {}

    -- Helper: Add buff to list
    local function AddBuff(cooldownID, source)
        if not cooldownID or seenCooldownIDs[cooldownID] then return end

        -- Get spell info from CDM API
        local spellID, spellName, iconTexture
        pcall(function()
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if info then
                    -- Priority: linkedSpellIDs[1] > overrideSpellID > spellID
                    spellID = (info.linkedSpellIDs and info.linkedSpellIDs[1]) or info.overrideSpellID or info.spellID
                    if spellID and spellID > 0 then
                        spellName = C_Spell.GetSpellName(spellID)
                        iconTexture = C_Spell.GetSpellTexture(spellID)
                    end
                end
            end
        end)

        if not spellName then return end

        seenCooldownIDs[cooldownID] = true

        -- Check for charges (CDM API)
        local hasCharges = false
        local maxCharges = 0
        pcall(function()
            if spellID then
                local chargeInfo = C_Spell.GetSpellCharges(spellID)
                if chargeInfo then
                    hasCharges = true
                    if chargeInfo.maxCharges and not IsSecretValue(chargeInfo.maxCharges) then
                        maxCharges = chargeInfo.maxCharges
                    else
                        maxCharges = 2  -- Default for charge spells
                    end
                end
            end
        end)

        table.insert(availableBuffs, {
            cooldownID = cooldownID,
            spellID = spellID,
            spellName = spellName,
            iconTexture = iconTexture or 134400,
            source = source,
            hasCharges = hasCharges,
            maxCharges = maxCharges,
        })
    end

    -- SOURCE 1: BuffIconCooldownViewer (CDM Buff Icons)
    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer then
        local children = { buffViewer:GetChildren() }
        for _, child in ipairs(children) do
            local cdID
            pcall(function()
                cdID = child.cooldownID or (child.cooldownInfo and child.cooldownInfo.cooldownID)
            end)
            if cdID then
                AddBuff(cdID, "BuffIcon")
            end
        end
    end

    -- SOURCE 2: BuffBarCooldownViewer (CDM Buff Bars)
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    if buffBarViewer then
        local children = { buffBarViewer:GetChildren() }
        for _, child in ipairs(children) do
            local cdID
            pcall(function()
                cdID = child.cooldownID or (child.cooldownInfo and child.cooldownInfo.cooldownID)
            end)
            if cdID then
                AddBuff(cdID, "BuffBar")
            end
        end
    end

    -- SOURCE 3: CDM Category Sets (Essential=0, Utility=1)
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        for category = 0, 1 do
            local cooldownIDs
            pcall(function()
                cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category, false)
            end)
            if cooldownIDs then
                local categoryName = category == 0 and "Essential" or "Utility"
                for _, cdID in ipairs(cooldownIDs) do
                    AddBuff(cdID, categoryName)
                end
            end
        end
    end

    -- Sort by name
    table.sort(availableBuffs, function(a, b)
        return (a.spellName or "") < (b.spellName or "")
    end)

    return availableBuffs
end

-- 외부에서 호출할 수 있도록 DDingUI에 노출
DDingUI.ScanAvailableBuffs = function()
    return ResourceBars.ScanAvailableBuffs()
end

-- (defaultSpecConfig 제거됨 - 미사용 변수)

-- Get the full config (per-spec now handled by SpecProfiles system)
-- Returns: specConfig (the config to read/write), rootConfig (same as specConfig)
local function GetFullSpecConfig()
    local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    if not rootCfg then return nil, nil end
    return rootCfg, rootCfg
end

-- Legacy function: Get generators/spenders
local function GetSpecConfig(cfg)
    if not cfg then return nil, nil end

    -- Fallback to shared/legacy config
    return cfg.generators, cfg.spenders
end

-- MANUAL STACK TRACKING (like IWT)
-- Per-buff manual stacks storage: { [barIndex] = { stacks = 0, expiresAt = nil } }
local manualStacksPerBuff = {}
-- Legacy global (for backwards compatibility)
local manualStacks = 0
local manualExpiresAt = nil
local manualTrackingEnabled = false

-- Get/set manual stacks for a specific buff index
local function GetManualStacks(barIndex)
    local data = manualStacksPerBuff[barIndex]
    return data and data.stacks or 0, data and data.expiresAt
end

local function SetManualStacks(barIndex, stacks, expiresAt)
    if not manualStacksPerBuff[barIndex] then
        manualStacksPerBuff[barIndex] = {}
    end
    manualStacksPerBuff[barIndex].stacks = stacks
    manualStacksPerBuff[barIndex].expiresAt = expiresAt
end

local function ResetManualStacks(barIndex)
    if barIndex then
        manualStacksPerBuff[barIndex] = nil
    else
        wipe(manualStacksPerBuff)
    end
end

-- Parse generators from trackedBuff settings
-- Returns: { [spellID] = { stacks = N, duration = N or nil } }
-- Format: spellID → 1 stack, refresh duration
--         spellID:2 → 2 stacks, refresh duration
--         spellID:1:5 → 1 stack, add 5 seconds
--         spellID:0:10 → no stacks, add 10 seconds only
--         spellID:2:0 → 2 stacks, no duration change
local function ParseBuffGenerators(settings)
    local result = {}
    local generators = settings and settings.generators
    if generators and type(generators) == "table" then
        for _, gen in ipairs(generators) do
            local spellID = tonumber(gen.spellID)  -- 숫자로 강제 변환
            if spellID and spellID > 0 then
                result[spellID] = {
                    stacks = gen.stacks or 1,
                    duration = gen.duration,  -- nil means refresh to default
                }
            end
        end
    end
    return result
end

-- Parse spenders from trackedBuff settings
local function ParseBuffSpenders(settings)
    local result = {}
    local spenders = settings and settings.spenders
    if spenders and type(spenders) == "table" then
        for _, spend in ipairs(spenders) do
            local spellID = tonumber(spend.spellID)  -- 숫자로 강제 변환
            if spellID and spellID > 0 then
                result[spellID] = spend.consume or 1
            end
        end
    end
    return result
end

-- Forward declarations (함수가 정의되기 전에 사용되는 경우)
local HideAllTrackedBuffBars
local HideAllTrackedBuffIcons
local HideAllTrackedBuffTexts
local ResetAllSoundTrackers
local soundTrackers = {}  -- forward-declared; 실제 사용은 line 2138+
local barFrames = {}      -- forward-declared; 실제 사용은 line 1921+
local iconFrames = {}     -- forward-declared; 실제 사용은 line 2064+
local GetTrackedBuffs  -- Used in expiration check before definition

-- GetDecimalFmt: 소수점 자릿수에 맞는 포맷 문자열 반환
local function GetDecimalFmt(decimals)
    return "%." .. (decimals or 1) .. "f"
end

-- ============================================================
-- CDM STACKS TRACKING
-- ============================================================

-- GetBuffStacks 함수 (원래 코드 복원) -- secret number는 그대로 전달 (표시용)
local function GetBuffStacks(frame, unit)
    if not frame then return 0 end
    local ok, result = pcall(function()
        if not frame.auraInstanceID then return 0 end
        unit = unit or "player"
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, frame.auraInstanceID)
        if not auraData then return 0 end
        return auraData.applications or 1
    end)
    if ok then return result or 0 end
    return 0
end

-- [12.0.1] 원래 스택 읽기 코드 복원
-- secret number여도 화면 표시(SetText)는 정상 작동함
-- 알림 비교만 EvaluateAlerts에서 별도 처리
-- Returns: trackedStacks, auraInstanceID, unit
local function ResolveTrackedStacks(cooldownID, frame, isManualMode, manualStackCount)
    if isManualMode then
        return manualStackCount or 0, nil, "player"
    end

    local unit = frame and frame.auraDataUnit or "player"
    local auraInstanceID = frame and frame.auraInstanceID
    local trackedStacks = tonumber(GetBuffStacks(frame, unit)) or 0

    if cooldownID and cooldownID > 0 then
        local directAura = nil
        pcall(function()
            directAura = C_UnitAuras.GetPlayerAuraBySpellID(cooldownID)
        end)
        if directAura then
            trackedStacks = tonumber(directAura.applications) or 1
            auraInstanceID = directAura.auraInstanceID
            unit = "player"
        end
    end

    return trackedStacks, auraInstanceID, unit
end

-- Parse comma-separated spell IDs into a lookup table (legacy support)
local function ParseSpellIDs(str)
    local result = {}
    if not str or str == "" then return result end
    for id in string.gmatch(str, "(%d+)") do
        local num = tonumber(id)
        if num and num > 0 then
            result[num] = true
        end
    end
    return result
end

-- Parse new generators/spenders array format into lookup tables
-- Returns: { [spellID] = stackAmount, ... }
local function ParseGenerators(cfg)
    local result = {}
    -- Get spec-specific or shared generators
    local generators, _ = GetSpecConfig(cfg)
    generators = generators or cfg.generators

    -- New format: array of { spellID, stacks }
    if generators and type(generators) == "table" then
        for _, gen in ipairs(generators) do
            if gen.spellID and gen.spellID > 0 then
                result[gen.spellID] = gen.stacks or cfg.maxStacks or 4
            end
        end
    end
    -- Legacy format: comma-separated string
    if next(result) == nil and cfg.generatorSpellIDs and cfg.generatorSpellIDs ~= "" then
        local legacyIDs = ParseSpellIDs(cfg.generatorSpellIDs)
        local defaultStacks = (cfg.generatorBehavior == "addOne") and 1 or (cfg.maxStacks or 4)
        for spellID in pairs(legacyIDs) do
            result[spellID] = defaultStacks
        end
    end
    return result
end

-- Returns: { [spellID] = consumeAmount, ... }
local function ParseSpenders(cfg)
    local result = {}
    -- Get spec-specific or shared spenders
    local _, spenders = GetSpecConfig(cfg)
    spenders = spenders or cfg.spenders

    -- New format: array of { spellID, consume }
    if spenders and type(spenders) == "table" then
        for _, spend in ipairs(spenders) do
            if spend.spellID and spend.spellID > 0 then
                result[spend.spellID] = spend.consume or 1
            end
        end
    end
    -- Legacy format: comma-separated string
    if next(result) == nil and cfg.spenderSpellIDs and cfg.spenderSpellIDs ~= "" then
        local legacyIDs = ParseSpellIDs(cfg.spenderSpellIDs)
        for spellID in pairs(legacyIDs) do
            result[spellID] = 1
        end
    end
    return result
end

-- Event frame for combat log tracking
local buffTrackerEventFrame = CreateFrame("Frame")
buffTrackerEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
buffTrackerEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
buffTrackerEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
buffTrackerEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
buffTrackerEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
buffTrackerEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
buffTrackerEventFrame:RegisterUnitEvent("UNIT_AURA", "player")  -- 플레이어 오라만 (레이드 성능 최적화)

local playerInCombat = false

buffTrackerEventFrame:SetScript("OnEvent", function(self, event, ...)
    local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    if not rootCfg or not rootCfg.enabled then return end

    -- UNIT_SPELLCAST_SUCCEEDED: 스킬 시전 성공 시 갱신 플래그
    -- NOTE: return 제거 - 수동 트래킹 로직(line 1164+)도 실행되어야 함
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and spellID then
            -- 시전된 spellID별로 시간 기록
            ResourceBars._spellCastRefresh = ResourceBars._spellCastRefresh or {}
            ResourceBars._spellCastRefresh[spellID] = GetTime()
        end
        -- return 제거: 아래 수동 트래킹 로직 실행 필요
    end

    -- UNIT_AURA: 순정 CDM과 동일하게 버프 변경 시 즉시 업데이트
    if event == "UNIT_AURA" then
        local unit, unitAuraUpdateInfo = ...
        if unit == "player" then
            -- 버프 갱신 감지: updatedAuraInstanceIDs를 저장해서 UpdateSingleTrackedBuffRing에서 처리
            if unitAuraUpdateInfo and unitAuraUpdateInfo.updatedAuraInstanceIDs then
                -- 글로벌 변수에 저장 (UpdateSingleTrackedBuffRing에서 확인)
                ResourceBars._pendingAuraUpdates = ResourceBars._pendingAuraUpdates or {}
                for _, updatedAuraID in ipairs(unitAuraUpdateInfo.updatedAuraInstanceIDs) do
                    ResourceBars._pendingAuraUpdates[updatedAuraID] = GetTime()
                end
            end
            ResourceBars:UpdateBuffTrackerBar()
        end
        return
    end

    -- Get config (per-spec handled by SpecProfiles system)
    local specCfg, _ = GetFullSpecConfig()
    if not specCfg then specCfg = rootCfg end

    -- Handle talent change events (always check, regardless of tracking mode)
    if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" then
        -- Talent changed - update bar to reflect new talent conditions
        C_Timer.After(0.1, function()
            ResourceBars:UpdateBuffTrackerBar()
        end)
        return
    end

    -- Handle specialization change (always, regardless of tracking mode)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Reset stacks when changing spec (different spells tracked)
        manualStacks = 0
        manualExpiresAt = nil

        -- 전문화 변경 시 프레임 초기화
        HideAllTrackedBuffBars()
        HideAllTrackedBuffIcons()
        HideAllTrackedBuffTexts()
        ResetAllSoundTrackers()
        wipe(soundTrackers)
        ResetManualStacks()  -- 전문화별 수동 스택 정리

        -- 새 전문화의 trackedBuffs를 로드할 시간 확보
        C_Timer.After(0.3, function()
            ResourceBars:UpdateBuffTrackerBar()
        end)
        return
    end

    -- Check if any manual tracking is enabled (global or per-buff)
    local hasAnyManualTracking = specCfg.trackingMode == "manual"
    if not hasAnyManualTracking then
        local trackedBuffs = GetTrackedBuffs()
        for _, buff in ipairs(trackedBuffs) do
            if buff.trackingMode == "manual" then
                hasAnyManualTracking = true
                break
            end
        end
    end
    if not hasAnyManualTracking then return end

    if event == "PLAYER_REGEN_DISABLED" then
        playerInCombat = true
        ResourceBars:UpdateBuffTrackerBar()
    elseif event == "PLAYER_REGEN_ENABLED" then
        playerInCombat = false

        -- ============================================================
        -- NEW: Per-buff manual tracking reset on combat end
        -- ============================================================
        local trackedBuffs = GetTrackedBuffs()
        for barIndex, buff in ipairs(trackedBuffs) do
            if buff.trackingMode == "manual" and buff.settings then
                if buff.settings.resetOnCombatEnd then
                    ResetManualStacks(barIndex)
                end
            end
        end

        -- LEGACY: Reset stacks when leaving combat (optional)
        if specCfg.resetOnCombatEnd then
            manualStacks = 0
            manualExpiresAt = nil
        end

        ResourceBars:UpdateBuffTrackerBar()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        if unit ~= "player" then return end

        -- ============================================================
        -- NEW: Per-buff manual tracking for trackedBuffsPerSpec
        -- ============================================================
        local trackedBuffs = GetTrackedBuffs()
        local inCombat = playerInCombat or UnitAffectingCombat("player")

        if BUFF_TRACKER_DEBUG then
            print(string.format("[ManualTrack] SPELLCAST spellID=%d, trackedBuffs=%d, inCombat=%s",
                spellID, #trackedBuffs, tostring(inCombat)))
        end

        for barIndex, buff in ipairs(trackedBuffs) do
            if BUFF_TRACKER_DEBUG then
                print(string.format("[ManualTrack] Bar %d: trackingMode=%s, hasSettings=%s",
                    barIndex, tostring(buff.trackingMode), tostring(buff.settings ~= nil)))
            end

            if buff.trackingMode == "manual" and buff.settings then
                local buffGens = ParseBuffGenerators(buff.settings)
                local buffSpends = ParseBuffSpenders(buff.settings)
                local maxStacks = buff.settings.maxStacks or 1
                local stackDuration = buff.settings.stackDuration or 30

                if BUFF_TRACKER_DEBUG then
                    local genCount = 0
                    for _ in pairs(buffGens) do genCount = genCount + 1 end
                    print(string.format("[ManualTrack] Bar %d: generators=%d, spellID=%d, inCombat=%s",
                        barIndex, genCount, spellID, tostring(inCombat)))
                end

                local currentStacks, currentExpires = GetManualStacks(barIndex)
                local now = GetTime()

                -- Generator spell cast (spellID를 숫자로 확실히 변환)
                local numSpellID = tonumber(spellID)
                local genData = numSpellID and buffGens[numSpellID]
                if genData then
                    if BUFF_TRACKER_DEBUG then
                        print(string.format("[ManualTrack] Bar %d: GENERATOR FOUND! stacks=%s, duration=%s",
                            barIndex, tostring(genData.stacks), tostring(genData.duration)))
                    end
                    if inCombat then
                        -- Flexible format: spellID:stacks:duration
                        -- genData.stacks: stacks to add (default 1, 0 = no change)
                        -- genData.duration: seconds to add (nil = refresh to default, 0 = no change)
                        local addStacks = genData.stacks or 1
                        local addDuration = genData.duration  -- nil, 0, or positive number

                        local newStacks = currentStacks or 0
                        local newExpires = currentExpires

                        -- Apply stacks change
                        if addStacks > 0 then
                            newStacks = math.min(newStacks + addStacks, maxStacks)
                        end

                        -- Apply duration change
                        if addDuration == nil then
                            -- nil = refresh duration to default (stackDuration)
                            if stackDuration > 0 then
                                newExpires = now + stackDuration
                            else
                                newExpires = nil  -- Unlimited
                            end
                        elseif addDuration > 0 then
                            -- Positive = add seconds to current remaining
                            local currentRemaining = newExpires and math.max(0, newExpires - now) or 0
                            local totalDuration = currentRemaining + addDuration
                            local maxDuration = stackDuration > 0 and stackDuration or 9999
                            totalDuration = math.min(totalDuration, maxDuration)
                            newExpires = now + totalDuration
                        end
                        -- addDuration == 0 → no duration change (keep current)

                        -- Ensure at least 1 stack if duration-only mode (stacks=0, duration>0)
                        if addStacks == 0 and (addDuration and addDuration > 0) and newStacks == 0 then
                            newStacks = 1
                        end

                        SetManualStacks(barIndex, newStacks, newExpires)
                        ResourceBars:UpdateBuffTrackerBar()
                    end
                else
                    -- Spender spell cast - always consumes stacks
                    local consumeValue = numSpellID and buffSpends[numSpellID]
                    if consumeValue then
                        if currentStacks and currentStacks > 0 then
                            local newStacks = math.max(0, currentStacks - consumeValue)
                            -- Keep duration if stacks remain, clear if all consumed
                            local newExpires = newStacks > 0 and currentExpires or nil
                            SetManualStacks(barIndex, newStacks, newExpires)
                            ResourceBars:UpdateBuffTrackerBar()
                        end
                    end
                end
            end
        end

        -- ============================================================
        -- LEGACY: Global manual tracking (for backwards compatibility)
        -- ============================================================
        local generators = ParseGenerators(rootCfg)
        local spenders = ParseSpenders(rootCfg)
        local maxStacks = specCfg.maxStacks or 4
        local duration = specCfg.stackDuration or 20

        -- Generator spell cast
        local genStacks = generators[spellID]
        if genStacks then
            -- Only gain stacks if in combat (like IWT)
            if inCombat then
                if genStacks == 1 then
                    -- Add 1 stack (capped at max) - for buffs like Frenzy
                    manualStacks = math.min(manualStacks + 1, maxStacks)
                elseif genStacks > 0 then
                    -- Set/add specific amount (capped at max)
                    manualStacks = math.min(manualStacks + genStacks, maxStacks)
                    -- If genStacks >= maxStacks, treat as "set to max"
                    if genStacks >= maxStacks then
                        manualStacks = maxStacks
                    end
                end
                -- Only set expiration if duration > 0 (0 = unlimited)
                if duration > 0 then
                    manualExpiresAt = GetTime() + duration
                else
                    manualExpiresAt = nil  -- No expiration for unlimited duration
                end
                ResourceBars:UpdateBuffTrackerBar()
            end
        -- Spender spell cast - consume specified amount
        else
            local consumeAmount = spenders[spellID]
            if consumeAmount and manualStacks > 0 then
                manualStacks = math.max(0, manualStacks - consumeAmount)
                if manualStacks == 0 then
                    manualExpiresAt = nil
                end
                ResourceBars:UpdateBuffTrackerBar()
            end
        end
    end
end)

-- Check expiration in OnUpdate
local expirationCheckFrame = CreateFrame("Frame")
local expirationCheckElapsed = 0
expirationCheckFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Throttle to every 0.1 seconds
    expirationCheckElapsed = expirationCheckElapsed + elapsed
    if expirationCheckElapsed < 0.1 then return end
    expirationCheckElapsed = 0

    local now = GetTime()
    local needsUpdate = false

    -- ============================================================
    -- NEW: Per-buff manual expiration check
    -- ============================================================
    local trackedBuffs = GetTrackedBuffs()
    for barIndex, buff in ipairs(trackedBuffs) do
        if buff.trackingMode == "manual" and buff.settings then
            local stacks, expiresAt = GetManualStacks(barIndex)
            if expiresAt and now >= expiresAt then
                local duration = buff.settings.stackDuration or 30
                if duration > 0 then
                    ResetManualStacks(barIndex)
                    needsUpdate = true
                end
            end
        end
    end

    -- ============================================================
    -- LEGACY: Global manual expiration check
    -- ============================================================
    if manualExpiresAt and now >= manualExpiresAt then
        local specCfg, _ = GetFullSpecConfig()
        local duration = specCfg and specCfg.stackDuration or 20
        -- Double-check duration is not unlimited
        if duration > 0 then
            manualStacks = 0
            manualExpiresAt = nil
            needsUpdate = true
        end
    end

    if needsUpdate then
        ResourceBars:UpdateBuffTrackerBar()
    end
end)

-- BUFF TRACKER BAR

function ResourceBars:GetBuffTrackerBar()
    if DDingUI.buffTrackerBar then return DDingUI.buffTrackerBar end

    local cfg, _ = GetFullSpecConfig()
    if not cfg then cfg = DDingUI.db.profile.buffTrackerBar end
    local anchor = _G[cfg.attachTo]
    if not anchor then
        anchor = UIParent
    end
    local anchorPoint = cfg.anchorPoint or "CENTER"

    -- Always parent to UIParent so visibility is independent from anchor
    local bar = CreateFrame("Frame", ADDON_NAME .. "BuffTrackerBar", UIParent)
    bar:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    bar:EnableMouse(false)
    bar:EnableMouseWheel(false)
    if bar.SetMouseMotionEnabled then
        bar:SetMouseMotionEnabled(false)
    end
    bar:SetHeight(DDingUI:Scale(cfg.height or 4))
    bar:SetPoint("CENTER", anchor, anchorPoint, DDingUI:Scale(cfg.offsetX or 0), DDingUI:Scale(cfg.offsetY or 18))

    local width = cfg.width or 0
    if width <= 0 then
        width = PixelSnap(DDingUI:GetEffectiveAnchorWidth(anchor))
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
    local tex = DDingUI:GetTexture(cfg.texture)
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel() + 1)
    -- Initialize min/max values to prevent texture distortion
    bar.StatusBar:SetMinMaxValues(0, 1)
    bar.StatusBar:SetValue(1)

    -- Hide the StatusBar's internal background texture so it doesn't interfere with our custom solid color background
    for i = 1, select("#", bar.StatusBar:GetRegions()) do
        local region = select(i, bar.StatusBar:GetRegions())
        if region:GetObjectType() == "Texture" and region ~= bar.StatusBar:GetStatusBarTexture() then
            region:Hide()
        end
    end

    -- BORDER (texture-based, no SetBackdrop = no taint)
    bar.Border = CreateFrame("Frame", nil, bar)
    bar.Border:SetFrameLevel(bar:GetFrameLevel() + 4)
    bar.Border:SetAllPoints(bar)
    local borderSize = DDingUI:ScaleBorder(cfg.borderSize or 1)
    bar._scaledBorder = borderSize
    local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
    CreateTextureBorder(bar.Border, borderSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

    -- TEXT FRAME
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    bar.TextFrame:SetFrameLevel(100)

    -- Stacks text (primary)
    local textAlign = cfg.textAlign or "CENTER"
    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint(textAlign, bar.TextFrame, textAlign, DDingUI:Scale(cfg.textX or 0), DDingUI:Scale(cfg.textY or 0))
    bar.TextValue:SetJustifyH(textAlign)
    bar.TextValue:SetFont(DDingUI:GetFont(cfg.textFont), cfg.textSize or 12, "OUTLINE")
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")

    -- Duration text (secondary)
    local durationAlign = cfg.durationTextAlign or "CENTER"
    bar.DurationText = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.DurationText:SetPoint(durationAlign, bar.TextFrame, durationAlign, DDingUI:Scale(cfg.durationTextX or 0), DDingUI:Scale(cfg.durationTextY or 0))
    bar.DurationText:SetJustifyH(durationAlign)
    bar.DurationText:SetFont(DDingUI:GetFont(cfg.durationTextFont or cfg.textFont), cfg.durationTextSize or 10, "OUTLINE")
    bar.DurationText:SetShadowOffset(0, 0)
    bar.DurationText:SetText("")
    bar.DurationText:Hide()

    -- TICK FRAME (above StatusBar so ticks are visible)
    bar.TickFrame = CreateFrame("Frame", nil, bar)
    bar.TickFrame:SetAllPoints(bar)
    bar.TickFrame:SetFrameLevel(bar:GetFrameLevel() + 2)

    -- TICKS
    bar.ticks = {}

    bar:Hide()

    DDingUI.buffTrackerBar = bar
    return bar
end

-- Get buff data by spell ID (uses GetPlayerAuraBySpellID to avoid secret value errors)
local function GetBuffData(spellID)
    if not spellID or spellID == 0 then return nil end

    -- Use GetPlayerAuraBySpellID directly (no secret value comparison)
    local auraData = nil
    pcall(function()
        auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end)
    return auraData
end

-- barFillMode: "stacks" (기본) or "duration"
-- durationTickPositions: {0.3, 0.5} 같은 비율 배열 (duration 모드용)
-- showTicks: 구분선 표시 여부 (개별 버프 설정)
-- cfgTickWidth: 구분선 두께 (개별 버프 설정)
-- barOrientation: "HORIZONTAL" or "VERTICAL" (바 방향)
function ResourceBars:UpdateBuffTrackerBarTicks(bar, current, max, barFillMode, durationTickPositions, showTicks, cfgTickWidth, barOrientation)
    -- Hide all ticks first
    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    cfgTickWidth = cfgTickWidth or 2
    local tickWidth = math.max(1, DDingUI:Scale(cfgTickWidth))
    local isVertical = (barOrientation == "VERTICAL")

    -- ============================================================
    -- DURATION MODE: 비율 기반 tick (팬데믹 등)
    -- ============================================================
    if barFillMode == "duration" then
        -- Duration 모드: durationTickPositions 사용
        if not durationTickPositions or #durationTickPositions == 0 then
            return  -- 설정된 tick이 없으면 표시 안 함
        end

        for i, position in ipairs(durationTickPositions) do
            local tick = bar.ticks[i]
            if not tick then
                tick = bar.TickFrame:CreateTexture(nil, "OVERLAY")
                tick:SetColorTexture(0, 0, 0, 1)
                bar.ticks[i] = tick
            end

            tick:ClearAllPoints()
            if isVertical then
                -- Vertical: position along Y axis (bottom to top)
                local y = position * height
                tick:SetPoint("BOTTOM", bar.TickFrame, "BOTTOM", 0, y)
                tick:SetSize(width, tickWidth)
            else
                -- Horizontal: position along X axis (left to right)
                local x = position * width
                tick:SetPoint("LEFT", bar.TickFrame, "LEFT", x, 0)
                tick:SetSize(tickWidth, height)
            end
            tick:Show()
        end
        return
    end

    -- ============================================================
    -- STACKS MODE: 스택 기반 tick (기본)
    -- ============================================================
    if showTicks == false or not max or max <= 1 then
        return
    end

    local needed = max - 1
    for i = 1, needed do
        local tick = bar.ticks[i]
        if not tick then
            -- Create tick on TickFrame (above StatusBar) so it's visible
            tick = bar.TickFrame:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(0, 0, 0, 1)
            bar.ticks[i] = tick
        end

        tick:ClearAllPoints()
        if isVertical then
            -- Vertical: position along Y axis (bottom to top)
            local y = (i / max) * height
            tick:SetPoint("BOTTOM", bar.TickFrame, "BOTTOM", 0, y)
            tick:SetSize(width, tickWidth)
        else
            -- Horizontal: position along X axis (left to right)
            local x = (i / max) * width
            tick:SetPoint("LEFT", bar.TickFrame, "LEFT", x, 0)
            tick:SetSize(tickWidth, height)
        end
        tick:Show()
    end
end

-- Ticker for buff updates
local buffTrackerTicker = nil

local function StopBuffTrackerTicker()
    if buffTrackerTicker then
        buffTrackerTicker:Cancel()
        buffTrackerTicker = nil
    end
end

local function StartBuffTrackerTicker()
    if buffTrackerTicker then return end

    -- 0.1초 간격 (10fps) - StatusBar/CooldownFrame은 자체 렌더링하므로 충분
    buffTrackerTicker = C_Timer.NewTicker(0.1, function()
        local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
        if not rootCfg or not rootCfg.enabled then
            StopBuffTrackerTicker()
            return
        end

        ResourceBars:UpdateBuffTrackerBar()
    end)
end

-- Slash command to toggle debug (BUFF_TRACKER_DEBUG는 파일 상단에 정의됨)
SLASH_BTDEBUG1 = "/btdebug"
SlashCmdList["BTDEBUG"] = function()
    BUFF_TRACKER_DEBUG = not BUFF_TRACKER_DEBUG
    print("|cff00ff00[DDingUI] Buff Tracker Debug:|r " .. (BUFF_TRACKER_DEBUG and "ON" or "OFF"))

    -- Print current state
    local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    local specCfg, _ = GetFullSpecConfig()
    if not specCfg then specCfg = rootCfg end

    print("|cffffcc00=== Root Config ===|r")
    print("  - enabled: " .. tostring(rootCfg and rootCfg.enabled))

    -- Show trackedBuffs info (per-spec using specID)
    local specID = GetCurrentSpecID()
    print("|cffffcc00=== Tracked Buffs (SpecID: " .. tostring(specID) .. ") ===|r")
    local trackedBuffs = GetTrackedBuffs()
    print("  - Count: " .. tostring(#trackedBuffs))
    for i, buff in ipairs(trackedBuffs) do
        local name = buff.name or "Unknown"
        local cdID = buff.cooldownID or 0
        local displayType = buff.displayType or "bar"
        local trackingMode = buff.trackingMode or "auto"
        print(string.format("  [%d] %s (cdID: %d, type: %s, mode: %s)", i, name, cdID, displayType, trackingMode))
        if buff.settings then
            local s = buff.settings
            print(string.format("      maxStacks=%d, hideWhenZero=%s, stackDuration=%d",
                s.maxStacks or 1, tostring(s.hideWhenZero), s.stackDuration or 30))
            -- Show generators
            if s.generators and #s.generators > 0 then
                print("      generators:")
                for _, gen in ipairs(s.generators) do
                    local genName = C_Spell.GetSpellName(gen.spellID) or "?"
                    print(string.format("        - %d (%s): stacks=%s, duration=%s",
                        gen.spellID, genName, tostring(gen.stacks), tostring(gen.duration)))
                end
            else
                print("      generators: (none)")
            end
            -- Show spenders
            if s.spenders and #s.spenders > 0 then
                print("      spenders:")
                for _, spend in ipairs(s.spenders) do
                    local spendName = C_Spell.GetSpellName(spend.spellID) or "?"
                    print(string.format("        - %d (%s): consume=%s",
                        spend.spellID, spendName, tostring(spend.consume)))
                end
            end
            -- Show manual stacks for this buff
            local stacks, expiresAt = GetManualStacks(i)
            print(string.format("      manualStacks=%d, expiresAt=%s", stacks, tostring(expiresAt)))
        else
            print("      settings: (nil)")
        end
    end
    if #trackedBuffs == 0 then
        print("  (none - using legacy config)")
    end

    print("|cffffcc00=== Spec Config (Legacy) ===|r")
    print("  - trackingMode: " .. tostring(specCfg and specCfg.trackingMode))
    print("  - cooldownID (cdm mode): " .. tostring(specCfg and specCfg.cooldownID))
    print("  - spellID (buff mode): " .. tostring(specCfg and specCfg.spellID))
    print("  - maxStacks: " .. tostring(specCfg and specCfg.maxStacks))
    print("  - stackDuration: " .. tostring(specCfg and specCfg.stackDuration))
    print("  - hideWhenZero: " .. tostring(specCfg and specCfg.hideWhenZero))
    print("  - requireTalentID: " .. tostring(specCfg and specCfg.requireTalentID))

    -- Manual mode info
    print("|cffffcc00=== Manual Tracking ===|r")
    print("  - manualStacks: " .. tostring(manualStacks))
    print("  - manualExpiresAt: " .. tostring(manualExpiresAt))
    print("  - playerInCombat: " .. tostring(playerInCombat))

    -- Show generators
    print("|cffffcc00=== Generators ===|r")
    local generators = rootCfg and ParseGenerators(rootCfg) or {}
    local genCount = 0
    for spellID, stacks in pairs(generators) do
        local name = C_Spell.GetSpellName(spellID) or "?"
        print(string.format("  [%d] %s -> +%d stacks", spellID, name, stacks))
        genCount = genCount + 1
    end
    if genCount == 0 then
        print("  (none configured)")
    end

    -- Show spenders
    print("|cffffcc00=== Spenders ===|r")
    local spenders = rootCfg and ParseSpenders(rootCfg) or {}
    local spendCount = 0
    for spellID, consume in pairs(spenders) do
        local name = C_Spell.GetSpellName(spellID) or "?"
        print(string.format("  [%d] %s -> -%d stacks", spellID, name, consume))
        spendCount = spendCount + 1
    end
    if spendCount == 0 then
        print("  (none configured)")
    end

    -- Bar state
    print("|cffffcc00=== Bar State ===|r")
    print("  - Ticker running: " .. tostring(buffTrackerTicker ~= nil))
    print("  - Legacy bar exists: " .. tostring(DDingUI.buffTrackerBar ~= nil))
    if DDingUI.buffTrackerBar then
        print("  - Legacy bar shown: " .. tostring(DDingUI.buffTrackerBar:IsShown()))
    end

    -- Multi-bar state
    print("|cffffcc00=== Multi-Bar State (NEW) ===|r")
    local barCount = 0
    for barIndex, bar in pairs(barFrames) do
        barCount = barCount + 1
        local buffInfo = trackedBuffs[barIndex]
        local buffName = buffInfo and buffInfo.name or "Unknown"
        local displayType = buffInfo and buffInfo.displayType or "bar"
        print(string.format("  [Bar %d] %s (type: %s)", barIndex, buffName, displayType))
        print(string.format("    - shown: %s, visible: %s", tostring(bar:IsShown()), tostring(bar:IsVisible())))
        print(string.format("    - size: %.1f x %.1f", bar:GetWidth(), bar:GetHeight()))
        local point, _, _, x, y = bar:GetPoint(1)
        print(string.format("    - position: %s offset %.1f, %.1f", tostring(point), x or 0, y or 0))
    end
    if barCount == 0 then
        print("  (no multi-bars created)")
    end

    -- Multi-icon state
    print("|cffffcc00=== Multi-Icon State (NEW) ===|r")
    local iconCount = 0
    for barIndex, icon in pairs(iconFrames) do
        iconCount = iconCount + 1
        local buffInfo = trackedBuffs[barIndex]
        local buffName = buffInfo and buffInfo.name or "Unknown"
        print(string.format("  [Icon %d] %s", barIndex, buffName))
        print(string.format("    - shown: %s, visible: %s", tostring(icon:IsShown()), tostring(icon:IsVisible())))
        print(string.format("    - size: %.1f x %.1f", icon:GetWidth(), icon:GetHeight()))
        print(string.format("    - glow: %s, pulse: %s", tostring(icon._glowAnimation), tostring(icon._pulseAnimation)))
        local point, _, _, x, y = icon:GetPoint(1)
        print(string.format("    - position: %s offset %.1f, %.1f", tostring(point), x or 0, y or 0))
    end
    if iconCount == 0 then
        print("  (no multi-icons created)")
    end

    -- Check required talent
    if specCfg and specCfg.requireTalentID and specCfg.requireTalentID > 0 then
        local talentKnown = IsPlayerSpell(specCfg.requireTalentID)
        local talentName = C_Spell.GetSpellName(specCfg.requireTalentID) or "?"
        print("|cffffcc00=== Required Talent ===|r")
        print(string.format("  [%d] %s - %s", specCfg.requireTalentID, talentName, talentKnown and "|cff00ff00KNOWN|r" or "|cffff0000NOT KNOWN|r"))
    end

    -- Check CDM mode
    if specCfg and specCfg.trackingMode == "cdm" then
        print("|cffffcc00=== CDM Tracking ===|r")
        local cooldownID = specCfg.cooldownID or 0
        print("  - cooldownID: " .. cooldownID)
        local CDMScanner = DDingUI.CDMScanner
        if CDMScanner and cooldownID > 0 then
            local entry = CDMScanner.GetEntry(cooldownID)
            print("  - Entry found: " .. tostring(entry ~= nil))
            if entry then
                print("  - Entry name: " .. tostring(entry.name))
                print("  - Entry spellID: " .. tostring(entry.spellID))
                print("  - Has auraInstanceID: " .. tostring(entry.hasAura))
            end
            local stacks, auraData = CDMScanner.GetStacksByCooldownID(cooldownID)
            print("  - Current stacks: " .. tostring(stacks))
            if auraData then
                print("  - Aura applications: " .. tostring(auraData.applications))
                print("  - Aura duration: " .. tostring(auraData.duration))
            end
        else
            print("  - CDMScanner: " .. (CDMScanner and "available" or "NOT AVAILABLE"))
        end
    end

    -- Check buff (for buff mode)
    if specCfg and specCfg.spellID and specCfg.spellID > 0 then
        print("|cffffcc00=== Buff Check (buff mode) ===|r")
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(specCfg.spellID)
        print("  - Aura found: " .. tostring(auraData ~= nil))
        if auraData then
            print("  - Aura name: " .. tostring(auraData.name))
            print("  - Aura applications: " .. tostring(auraData.applications))
            print("  - Aura duration: " .. tostring(auraData.duration))
        end
    end

    -- Also scan all player buffs to help find correct spell ID
    print("|cffffcc00=== Current Player Buffs ===|r")
    local foundAny = false
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        -- aura.applications 값은 비교하지 않고 그대로 출력
        print(string.format("  [%d] %s - stacks: %s", aura.spellId or 0, aura.name or "?", tostring(aura.applications)))
        foundAny = true
    end
    if not foundAny then
        print("  (no buffs)")
    end
end

-- Force show test
local testMode = false
SLASH_BTTEST1 = "/bttest"
SlashCmdList["BTTEST"] = function()
    testMode = not testMode

    if testMode then
        print("|cff00ff00[DDingUI] Buff Tracker Test Mode: ON|r (ticker paused)")
        StopBuffTrackerTicker()

        local bar = ResourceBars:GetBuffTrackerBar()
        bar:SetParent(UIParent)
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        bar:SetSize(200, 10)
        bar:SetFrameStrata("TOOLTIP")
        bar:SetAlpha(1)

        bar.StatusBar:SetMinMaxValues(0, 10)
        bar.StatusBar:SetValue(5)
        bar.StatusBar:SetStatusBarColor(1, 0.8, 0, 1)

        bar.Background:SetColorTexture(0.2, 0.2, 0.2, 1)
        bar.TextValue:SetText("TEST")
        bar.TextFrame:Show()

        bar:Show()
        print("  - Bar at CENTER, 200x10, value 5/10")
    else
        print("|cff00ff00[DDingUI] Buff Tracker Test Mode: OFF|r (ticker resumed)")
        StartBuffTrackerTicker()
        ResourceBars:UpdateBuffTrackerBar()
    end
end

-- Helper function to get effective max stacks (base + talent bonus)
local function GetEffectiveMaxStacks(cfg)
    local baseStacks = cfg.maxStacks or 4
    local bonusStacks = 0

    -- Check if bonus talent is learned
    if cfg.bonusTalentID and cfg.bonusTalentID > 0 then
        if IsPlayerSpell(cfg.bonusTalentID) then
            bonusStacks = cfg.bonusTalentStacks or 1
        end
    end

    return baseStacks + bonusStacks
end

-- Get tracked buffs from config (전문화별 설정 - specID 사용)
-- db.global에 저장하여 같은 전문화 캐릭터 간 설정 공유
GetTrackedBuffs = function()
    if not DDingUI.db then return {} end

    local specID = GetCurrentSpecID()
    if not specID then return {} end

    local rootCfg = DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    if not rootCfg then return {} end

    -- trackedBuffsPerSpec 초기화 (profile 스코프)
    if not rootCfg.trackedBuffsPerSpec then
        rootCfg.trackedBuffsPerSpec = {}
    end
    local profileStore = rootCfg.trackedBuffsPerSpec

    -- Reverse Migration: global → profile (기존 글로벌 데이터를 프로필로 복원)
    local globalStore = DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec
    if globalStore then
        for gSpecID, gData in pairs(globalStore) do
            if type(gData) == "table" and #gData > 0 then
                if not profileStore[gSpecID] or #profileStore[gSpecID] == 0 then
                    -- 프로필에 데이터가 없을 때만 마이그레이션 (기존 데이터 보호)
                    profileStore[gSpecID] = gData
                end
            end
        end
        -- 마이그레이션 완료 후 글로벌에서 제거
        DDingUI.db.global.trackedBuffsPerSpec = nil
    end

    -- Legacy migration: 레거시 trackedBuffs → profile
    if not rootCfg._legacyMigrationComplete
       and rootCfg.trackedBuffs and #rootCfg.trackedBuffs > 0 then
        if not profileStore[specID] or #profileStore[specID] == 0 then
            profileStore[specID] = {}
            for i, buff in ipairs(rootCfg.trackedBuffs) do
                local copy = {}
                for k, v in pairs(buff) do
                    if type(v) == "table" then
                        copy[k] = {}
                        for k2, v2 in pairs(v) do
                            copy[k][k2] = v2
                        end
                    else
                        copy[k] = v
                    end
                end
                profileStore[specID][i] = copy
            end
        end
        rootCfg._legacyMigrationComplete = true
        rootCfg.trackedBuffs = {}
    end

    -- [NEW] Phase 1 Tracker Groups (v2) Migration
    if not rootCfg._v2GroupMigrationComplete then
        if not rootCfg.trackerGroups then
            rootCfg.trackerGroups = {}
        end
        -- Ensure "Group1" exists as a fallback default
        if not rootCfg.trackerGroups["Group1"] then
            rootCfg.trackerGroups["Group1"] = {
                name = "기본 추적 그룹",
                point = "CENTER", x = 0, y = -100,
                sortMethod = "TIME_LEFT",
                sortDirection = "ASC",
                growthDir = "RIGHT",
                spacing = 5,
            }
        end

        -- Migrate all known specs
        if profileStore then
            for oldSpecID, buffs in pairs(profileStore) do
                for _, buff in ipairs(buffs) do
                    if not buff.group then
                        buff.group = "Group1"
                    end
                end
            end
        end

        rootCfg._v2GroupMigrationComplete = true
    end

    -- 현재 specID 슬롯이 없으면 빈 테이블 생성
    if not profileStore[specID] then
        profileStore[specID] = {}
    end

    return profileStore[specID]
end

-- ============================================================
-- MULTI-BAR SYSTEM -- 각 tracked buff마다 독립적인 바 프레임 생성
-- ============================================================
-- barFrames: forward-declared at top (line 976)

-- Create a bar frame for a specific tracked buff index
local function CreateTrackedBuffBar(barIndex)
    local cfg, _ = GetFullSpecConfig()
    if not cfg then cfg = DDingUI.db.profile.buffTrackerBar end

    local bar = CreateFrame("Frame", ADDON_NAME .. "BuffTrackerBar" .. barIndex, UIParent)
    bar:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    bar:EnableMouse(false)
    bar:EnableMouseWheel(false)
    if bar.SetMouseMotionEnabled then
        bar:SetMouseMotionEnabled(false)
    end
    bar:SetHeight(DDingUI:Scale(cfg.height or 4))
    bar:SetWidth(200)
    bar.barIndex = barIndex  -- Store for debugging

    -- BACKGROUND
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()
    bar.Background:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- STATUS BAR (for bar style)
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    local tex = DDingUI:GetTexture(cfg.texture)
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel() + 1)
    -- Initialize min/max values to prevent texture distortion
    bar.StatusBar:SetMinMaxValues(0, 1)
    bar.StatusBar:SetValue(1)

    -- COOLDOWN FRAME (for circular/square/donut style)
    bar.Cooldown = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    bar.Cooldown:SetAllPoints()
    bar.Cooldown:SetDrawEdge(false)
    bar.Cooldown:SetDrawSwipe(true)
    bar.Cooldown:SetSwipeColor(0, 0, 0, 0.7)
    bar.Cooldown:SetReverse(true)  -- Fill up as time passes
    bar.Cooldown:SetHideCountdownNumbers(true)  -- We use our own duration text
    bar.Cooldown:Hide()  -- Hidden by default (bar style)

    -- Cooldown icon texture (for circular/square/donut style background)
    bar.CooldownTexture = bar:CreateTexture(nil, "ARTWORK")
    bar.CooldownTexture:SetAllPoints()
    bar.CooldownTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.CooldownTexture:Hide()

    -- Donut center cutout (for donut style) - solid color to cover center
    bar.DonutCenter = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    bar.DonutCenter:SetPoint("CENTER")
    bar.DonutCenter:SetColorTexture(0, 0, 0, 1)  -- 단색 검정 텍스처
    bar.DonutCenter:Hide()

    -- RING STYLE TEXTURES
    -- Ring background (solid circle for progress fill)
    bar.RingBackground = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar.RingBackground:SetAllPoints()
    bar.RingBackground:SetTexture("Interface\\AddOns\\DDingUI\\Media\\Textures\\Ring_20px.tga")
    bar.RingBackground:SetVertexColor(0.15, 0.15, 0.15, 1)
    bar.RingBackground:Hide()

    -- Ring progress (shows current value with color)
    bar.RingProgress = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.RingProgress:SetAllPoints()
    bar.RingProgress:SetTexture("Interface\\AddOns\\DDingUI\\Media\\Textures\\Ring_20px.tga")
    bar.RingProgress:SetVertexColor(1, 0.8, 0, 1)
    bar.RingProgress:Hide()

    -- Ring border (outer ring texture - behind the ring for border effect)
    bar.RingBorder = bar:CreateTexture(nil, "BACKGROUND", nil, 0)  -- sublevel 0, behind RingBackground (sublevel 1)
    bar.RingBorder:SetPoint("CENTER")
    bar.RingBorder:SetTexture("Interface\\AddOns\\DDingUI\\Media\\Textures\\Ring_20px.tga")  -- Same texture, larger size for border
    bar.RingBorder:SetVertexColor(0, 0, 0, 1)
    bar.RingBorder:Hide()

    -- CIRCULAR PROGRESS (WeakAuras-style ring progress)
    -- Create container frame for circular progress
    bar.CircularProgressFrame = CreateFrame("Frame", nil, bar)
    bar.CircularProgressFrame:SetAllPoints(bar)
    bar.CircularProgressFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    bar.CircularProgressFrame:Hide()

    -- Initialize CircularProgress widget (will be set up in UpdateSingleTrackedBuffRing)
    bar._circularProgressInitialized = false

    -- BORDER (texture-based, no SetBackdrop = no taint)
    bar.Border = CreateFrame("Frame", nil, bar)
    bar.Border:SetFrameLevel(bar:GetFrameLevel() + 4)
    bar.Border:SetAllPoints(bar)
    local borderSize = DDingUI:ScaleBorder(cfg.borderSize or 1)
    bar._scaledBorder = borderSize
    CreateTextureBorder(bar.Border, borderSize, 0, 0, 0, 1)

    -- TEXT FRAME
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    bar.TextFrame:SetFrameLevel(100)

    -- Stacks text (primary)
    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", 0, 0)
    bar.TextValue:SetJustifyH("CENTER")
    bar.TextValue:SetFont(DDingUI:GetFont(cfg.textFont), cfg.textSize or 12, "OUTLINE")
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")

    -- Duration text (secondary)
    bar.DurationText = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.DurationText:SetPoint("CENTER", bar.TextFrame, "CENTER", 0, -10)
    bar.DurationText:SetJustifyH("CENTER")
    bar.DurationText:SetFont(DDingUI:GetFont(cfg.textFont), cfg.durationTextSize or 10, "OUTLINE")
    bar.DurationText:SetShadowOffset(0, 0)
    bar.DurationText:SetText("")
    bar.DurationText:Hide()

    -- TICK FRAME
    bar.TickFrame = CreateFrame("Frame", nil, bar)
    bar.TickFrame:SetAllPoints(bar)
    bar.TickFrame:SetFrameLevel(bar:GetFrameLevel() + 2)

    -- TICKS
    bar.ticks = {}

    bar:Hide()

    return bar
end

-- Get or create bar frame for a specific tracked buff index
local function GetTrackedBuffBar(barIndex)
    if not barFrames[barIndex] then
        barFrames[barIndex] = CreateTrackedBuffBar(barIndex)
    end
    return barFrames[barIndex]
end

-- ============================================================
-- ICON FRAME SYSTEM
-- 아이콘 모드용 프레임 (애니메이션, 쿨다운 스윕 지원)
-- ============================================================
-- iconFrames: forward-declared at top (line 977)

-- Create an icon frame for a specific tracked buff index
local function CreateTrackedBuffIcon(barIndex)
    local cfg, _ = GetFullSpecConfig()
    if not cfg then cfg = DDingUI.db.profile.buffTrackerBar end

    local size = 32
    local icon = CreateFrame("Frame", ADDON_NAME .. "BuffTrackerIcon" .. barIndex, UIParent)
    icon:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    icon:SetSize(size, size)
    icon:EnableMouse(false)
    icon.barIndex = barIndex

    -- Icon texture
    icon.Texture = icon:CreateTexture(nil, "ARTWORK")
    icon.Texture:SetAllPoints()
    icon.Texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Slight zoom

    -- Cooldown frame (for duration swipe)
    icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints()
    icon.Cooldown:SetDrawEdge(false)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetSwipeColor(0, 0, 0, 0.7)
    icon.Cooldown:SetReverse(true)  -- Reverse for buff duration (fill up as time passes)
    icon.Cooldown:SetHideCountdownNumbers(false)  -- Show countdown text

    -- Border (texture-based, no SetBackdrop = no taint)
    icon.Border = CreateFrame("Frame", nil, icon)
    icon.Border:SetFrameLevel(icon:GetFrameLevel() + 2)
    icon.Border:SetAllPoints(icon)
    CreateTextureBorder(icon.Border, 1, 0, 0, 0, 1)

    -- Glow frame for animation
    icon.Glow = CreateFrame("Frame", nil, icon)
    icon.Glow:SetAllPoints()
    icon.Glow:SetFrameLevel(icon:GetFrameLevel() + 3)

    -- Stack text
    icon.StackText = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.StackText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    icon.StackText:SetJustifyH("RIGHT")
    icon.StackText:SetText("")

    icon:Hide()

    return icon
end

-- Get or create icon frame for a specific tracked buff index
local function GetTrackedBuffIcon(barIndex)
    if not iconFrames[barIndex] then
        iconFrames[barIndex] = CreateTrackedBuffIcon(barIndex)
    end
    return iconFrames[barIndex]
end

-- Hide all icon frames (forward declared at top)
HideAllTrackedBuffIcons = function()
    for _, icon in pairs(iconFrames) do
        if icon then
            icon:Hide()
            -- Stop all animations
            StopAllAnimations(icon)
            icon._currentAnimation = nil
        end
    end
end

-- ============================================================
-- SOUND TRACKER SYSTEM
-- 사운드 모드용 트래커 (버프 시작/종료 시 소리 재생)
-- ============================================================
-- soundTrackers: forward-declared at top (line 975)

-- Get or create sound tracker for a specific tracked buff index
local function GetSoundTracker(barIndex)
    if not soundTrackers[barIndex] then
        soundTrackers[barIndex] = {
            lastPlayTime = 0,
            wasActive = false,
            lastIntervalPlay = 0,
        }
    end
    return soundTrackers[barIndex]
end

-- Play sound using LibSharedMedia
local function PlayTrackerSound(soundKey, channel)
    if not soundKey or soundKey == "None" or soundKey == "" then return end

    local soundFile = LSM:Fetch("sound", soundKey)
    if soundFile then
        PlaySoundFile(soundFile, channel or "Master")
    end
end

-- Reset all sound trackers (forward declared at top)
ResetAllSoundTrackers = function()
    for _, tracker in pairs(soundTrackers) do
        if tracker then
            tracker.wasActive = false
            tracker.lastPlayTime = 0
            tracker.lastIntervalPlay = 0
        end
    end
end

-- ============================================================
-- ALERT SYSTEM (Trigger-Action)
-- 트리거-액션 기반 유연한 알림 시스템
-- ============================================================

local function EvaluateComparison(current, op, target)
    if current == nil or target == nil then return false end
    -- [FIX] WoW taint protection: CDM/aura API values may be secret numbers
    -- tainted by DDingUI execution context during UNIT_AURA handler.
    -- pcall prevents "attempt to compare secret number value" errors.
    local ok, result = pcall(function()
        if op == "<=" then return current <= target
        elseif op == ">=" then return current >= target
        elseif op == "==" then return current == target
        elseif op == "!=" then return current ~= target
        elseif op == "<"  then return current < target
        elseif op == ">"  then return current > target
        end
        return false
    end)
    return ok and result or false
end

-- Evaluate all triggers for a tracked buff, return per-trigger results + combined result
-- [12.0.1] stacks 트리거 제거: 전투 중 applications가 secret number라 비교 불가 (WoW 12.0+)
local function EvaluateAlerts(trackedBuff, trackedStacks, hasData, auraInstanceID, unit)
    local settings = trackedBuff and trackedBuff.settings
    if not settings or not settings.alerts or not settings.alerts.enabled then
        return nil
    end

    local alerts = settings.alerts
    local triggers = alerts.triggers or {}
    if #triggers == 0 then return nil end

    local triggerResults = {}

    for i, trigger in ipairs(triggers) do
        local result = false

        if trigger.type == "active" then
            result = EvaluateComparison(hasData, trigger.op, trigger.value)

        elseif trigger.type == "duration" then
            if hasData and auraInstanceID then
                pcall(function()
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if auraData and auraData.expirationTime then
                        local remaining = auraData.expirationTime - GetTime()
                        if remaining > 0 then
                            result = EvaluateComparison(remaining, trigger.op, trigger.value)
                        end
                    end
                end)
            end
        end

        triggerResults[i] = result
    end

    -- Combine results based on triggerLogic
    local combined
    if alerts.triggerLogic == "and" then
        combined = true
        for _, r in ipairs(triggerResults) do
            if not r then combined = false; break end
        end
    else  -- "or" (default)
        combined = false
        for _, r in ipairs(triggerResults) do
            if r then combined = true; break end
        end
    end

    return {
        combined = combined,
        triggers = triggerResults,
    }
end

-- Apply alert actions (color override, sound) based on evaluation result
local function ApplyAlertActions(alertResult, trackedBuff, frame)
    if not alertResult then return end

    local alerts = trackedBuff.settings.alerts
    local actions = alerts.actions or {}
    if #actions == 0 then return end

    -- Reset color override
    frame._alertColorOverride = nil

    -- Initialize tracking tables
    if not frame._alertSoundLastPlay then
        frame._alertSoundLastPlay = {}
    end
    if not frame._alertPrevState then
        frame._alertPrevState = {}
    end

    local now = GetTime()

    for actionIdx, action in ipairs(actions) do
        -- Determine if this action's condition is met
        local shouldFire = false
        if action.condition == "any" then
            shouldFire = alertResult.combined
        else
            local triggerNum = tonumber((action.condition or ""):match("trigger(%d+)"))
            if triggerNum and alertResult.triggers[triggerNum] then
                shouldFire = true
            end
        end

        if action.type == "color" then
            -- Color override: apply while condition is true (last color wins)
            if shouldFire and action.color then
                frame._alertColorOverride = action.color
            end

        elseif action.type == "sound" then
            local stateKey = actionIdx
            local wasActive = frame._alertPrevState[stateKey]

            if action.soundMode == "repeat" then
                -- Repeat mode: play at cooldown intervals
                if shouldFire then
                    local cooldown = action.soundCooldown or 3
                    local lastPlay = frame._alertSoundLastPlay[stateKey] or 0
                    if now - lastPlay >= cooldown then
                        PlayTrackerSound(action.soundFile, action.soundChannel or "Master")
                        frame._alertSoundLastPlay[stateKey] = now
                    end
                end
            else
                -- Once mode (default): rising edge only
                if shouldFire and not wasActive then
                    PlayTrackerSound(action.soundFile, action.soundChannel or "Master")
                    frame._alertSoundLastPlay[stateKey] = now
                end
            end

            frame._alertPrevState[stateKey] = shouldFire
        end
    end
end

-- ============================================================
-- TEXT FRAME SYSTEM
-- 텍스트 모드용 프레임 (스택/지속시간/이름 텍스트 표시)
-- ============================================================
local textFrames = {}  -- [barIndex] = textFrame

-- Text animation uses the shared animation system defined above
-- ApplyTextAnimation wraps ApplyIconAnimation for text frames with glow settings
local function ApplyTextAnimation(frame, animationType, glowSettings)
    ApplyIconAnimation(frame, animationType, glowSettings)
end

-- Alias for stopping all text animations
local function StopTextAnimations(frame)
    StopAllAnimations(frame)
end

-- Create a text frame for a specific tracked buff index
local function CreateTrackedBuffText(barIndex)
    local globalCfg = DDingUI.db.profile.buffTrackerBar
    local frame = CreateFrame("Frame", ADDON_NAME .. "BuffTrackerText" .. barIndex, UIParent)
    frame:SetFrameStrata(globalCfg.frameStrata or "MEDIUM")
    frame:SetSize(200, 50)
    frame:EnableMouse(false)
    frame.barIndex = barIndex

    -- Optional icon next to text
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetSize(24, 24)
    frame.Icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Main text
    frame.Text = frame:CreateFontString(nil, "OVERLAY")
    frame.Text:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")
    frame.Text:SetPoint("LEFT", frame.Icon, "RIGHT", 4, 0)
    frame.Text:SetJustifyH("LEFT")
    frame.Text:SetText("")

    frame:Hide()

    return frame
end

-- Get or create text frame for a specific tracked buff index
local function GetTrackedBuffText(barIndex)
    if not textFrames[barIndex] then
        textFrames[barIndex] = CreateTrackedBuffText(barIndex)
    end
    return textFrames[barIndex]
end

-- Hide all text frames (forward declared at top)
HideAllTrackedBuffTexts = function()
    for _, frame in pairs(textFrames) do
        if frame then
            frame:Hide()
            StopTextAnimations(frame)
            frame._currentAnimation = nil
        end
    end
end

-- Hide all bar frames (forward declared at top)
HideAllTrackedBuffBars = function()
    for _, bar in pairs(barFrames) do
        if bar then
            bar:Hide()
        end
    end
end

-- Get the first tracked buff (for legacy single bar mode)
local function GetFirstTrackedBuff()
    local trackedBuffs = GetTrackedBuffs()
    return trackedBuffs[1]
end

function ResourceBars:UpdateBuffTrackerBar()
    local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    local cfg, _ = GetFullSpecConfig()

    -- Debug: Check if function is being called at all
    if BUFF_TRACKER_DEBUG then
        print("[BuffTracker] Update called, enabled=" .. tostring(rootCfg and rootCfg.enabled))
    end

    -- Use rootCfg for enabled flag (global setting)
    if not rootCfg or not rootCfg.enabled then
        HideAllTrackedBuffBars()
        HideAllTrackedBuffIcons()
        if DDingUI.buffTrackerBar then
            DDingUI.buffTrackerBar:Hide()
        end
        StopBuffTrackerTicker()
        return
    end

    -- cfg (per-spec handled by SpecProfiles system)
    if not cfg then cfg = rootCfg end

    -- ============================================================
    -- NEW: Multi-bar system - iterate all tracked buffs
    -- ============================================================
    local trackedBuffs = GetTrackedBuffs()
    local useTrackedBuffSystem = (#trackedBuffs > 0)

    if BUFF_TRACKER_DEBUG then
        print("[BuffTracker] useTrackedBuffSystem=" .. tostring(useTrackedBuffSystem) .. ", count=" .. #trackedBuffs)
    end

    -- Start ticker if not running
    if not buffTrackerTicker then
        StartBuffTrackerTicker()
    end

    -- Use new multi-bar system if we have tracked buffs
    if useTrackedBuffSystem then
        -- Update each tracked buff based on its display type
        for barIndex, trackedBuff in ipairs(trackedBuffs) do
            -- Skip disabled buffs
            if trackedBuff.enabled == false then
                local bar = barFrames[barIndex]
                DDingUI:SafeHide(bar)
                local icon = iconFrames[barIndex]
                if icon then
                    DDingUI:SafeHide(icon)
                    StopAllAnimations(icon)
                    icon._currentAnimation = nil
                end
                local textFrame = textFrames[barIndex]
                DDingUI:SafeHide(textFrame)
            else
                local displayType = trackedBuff.displayType or "bar"

                -- Helper to hide all display elements for this index (SafeHide for performance)
                local function HideOtherDisplays(exceptType)
                    -- Hide bar if not bar mode
                    if exceptType ~= "bar" then
                        DDingUI:SafeHide(barFrames[barIndex])
                    end
                    -- Hide icon if not icon mode
                    if exceptType ~= "icon" then
                        local icon = iconFrames[barIndex]
                        if icon then
                            DDingUI:SafeHide(icon)
                            StopAllAnimations(icon)
                            icon._currentAnimation = nil
                        end
                    end
                    -- Hide text if not text mode
                    if exceptType ~= "text" then
                        DDingUI:SafeHide(textFrames[barIndex])
                    end
                end

                if displayType == "bar" then
                    -- Bar mode: update bar, hide others
                    self:UpdateSingleTrackedBuffBar(barIndex, trackedBuff, cfg)
                    HideOtherDisplays("bar")
                elseif displayType == "ring" then
                    -- Ring mode: update ring (reuses bar frame with ring style)
                    self:UpdateSingleTrackedBuffRing(barIndex, trackedBuff, cfg)
                    HideOtherDisplays("bar")  -- Ring uses bar frame
                elseif displayType == "icon" then
                    -- Icon mode: update icon, hide others
                    self:UpdateSingleTrackedBuffIcon(barIndex, trackedBuff, cfg)
                    HideOtherDisplays("icon")
                elseif displayType == "sound" then
                    -- Sound mode: only play sound, no visual display
                    self:UpdateSingleTrackedBuffSound(barIndex, trackedBuff, cfg)
                    HideOtherDisplays("sound")  -- Hide all visuals
                elseif displayType == "text" then
                    -- Text mode: update text, hide others
                    self:UpdateSingleTrackedBuffText(barIndex, trackedBuff, cfg)
                    HideOtherDisplays("text")
                else
                    -- Fallback to bar mode
                    self:UpdateSingleTrackedBuffBar(barIndex, trackedBuff, cfg)
                    HideOtherDisplays("bar")
                end
            end
        end

        -- Hide excess frames (if buffs were removed, SafeHide for performance)
        for barIndex, bar in pairs(barFrames) do
            if barIndex > #trackedBuffs then
                DDingUI:SafeHide(bar)
            end
        end
        for barIndex, icon in pairs(iconFrames) do
            if barIndex > #trackedBuffs then
                DDingUI:SafeHide(icon)
                StopAllAnimations(icon)
                icon._currentAnimation = nil
            end
        end
        for barIndex, textFrame in pairs(textFrames) do
            if barIndex > #trackedBuffs then
                DDingUI:SafeHide(textFrame)
                StopTextAnimations(textFrame)
                textFrame._currentAnimation = nil
            end
        end

        -- Hide legacy single bar if it exists
        if DDingUI.buffTrackerBar then
            DDingUI.buffTrackerBar:Hide()
        end
        return
    end

    -- Legacy single bar mode removed - use trackedBuffs system instead
    -- Hide legacy bar if no tracked buffs configured
    if DDingUI.buffTrackerBar then
        DDingUI.buffTrackerBar:Hide()
    end
end

-- (CreateDurationOnUpdate 제거됨 - 미사용 데드코드. 실제 OnUpdate는 인라인 핸들러 사용)

-- ============================================================
-- Update a single tracked buff bar
-- ============================================================
function ResourceBars:UpdateSingleTrackedBuffBar(barIndex, trackedBuff, globalCfg)
    local bar = GetTrackedBuffBar(barIndex)
    local settings = trackedBuff.settings or {}

    -- DDingUI:Scale 사용 (픽셀퍼펙트 스케일, v1.1.5.5와 일관성 유지)

    -- Get settings from trackedBuff (with fallbacks to global config)
    local cooldownID = trackedBuff.cooldownID or 0
    local maxStacks = settings.maxStacks or 1
    local hideWhenZero = settings.hideWhenZero
    if hideWhenZero == nil then hideWhenZero = true end
    local showInCombat = settings.showInCombat or false
    local barColor = settings.barColor or { 1, 0.8, 0, 1 }
    local bgColor = settings.bgColor or globalCfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    local showStacksText = settings.showStacksText
    if showStacksText == nil then showStacksText = true end
    local showDurationText = settings.showDurationText or false
    -- Stacks text settings
    local textSize = settings.textSize or 12
    local textAlign = settings.textAlign or "CENTER"
    local textX = settings.textX or 0
    local textY = settings.textY or 0
    local textColor = settings.textColor or { 1, 1, 1, 1 }
    -- Duration text settings
    local durationTextSize = settings.durationTextSize or 10
    local durationTextAlign = settings.durationTextAlign or "CENTER"
    local durationTextX = settings.durationTextX or 0
    local durationTextY = settings.durationTextY or -10
    local durationTextColor = settings.durationTextColor or { 1, 1, 1, 1 }
    local durationDecimals = settings.durationDecimals or 1  -- 소수점 자릿수 (0-2)
    -- Duration warning settings
    local durationWarningEnabled = settings.durationWarningEnabled or false
    local durationWarningThreshold = settings.durationWarningThreshold or 5
    local durationWarningColor = settings.durationWarningColor or { 1, 0.2, 0.2, 1 }
    local barFillMode = settings.barFillMode or "stacks"  -- "stacks" or "duration"
    local dynamicDuration = settings.dynamicDuration or false  -- Auto mode: read duration from CDM
    local stackDuration = settings.stackDuration or 30  -- max duration for duration mode
    local barStyle = settings.barStyle or "bar"  -- "bar", "circular", "square", "donut"
    local donutThickness = settings.donutThickness or 0.3  -- 도넛 두께 비율 (0.1~0.5)
    local durationTickPositions = settings.durationTickPositions or {}  -- 비율 배열 (예: {0.3} = 30% 위치)
    local showTicks = settings.showTicks
    if showTicks == nil then showTicks = true end
    local tickWidth = settings.tickWidth or 2
    local hideFromCDM = settings.hideFromCDM or false  -- CDM에서 숨기기

    -- Per-bar position settings (with stacking fallback)
    local attachTo = settings.attachTo or globalCfg.attachTo or "EssentialCooldownViewer"
    local anchorPoint = settings.anchorPoint or globalCfg.anchorPoint or "BOTTOM"
    local baseOffsetX = settings.offsetX or globalCfg.offsetX or 0
    local baseOffsetY = settings.offsetY
    local growthDirection = settings.growthDirection or globalCfg.growthDirection or "DOWN"
    local growthSpacing = settings.growthSpacing or globalCfg.growthSpacing or 20

    -- Calculate offset based on growth direction (only when per-bar offset not set)
    local offsetX, offsetY
    if settings.offsetX ~= nil and settings.offsetY ~= nil then
        -- Per-bar custom position: use exact values
        offsetX = settings.offsetX
        offsetY = settings.offsetY
    else
        -- Auto-stack based on growth direction
        local stackIndex = barIndex - 1
        local baseX = globalCfg.offsetX or 0
        local baseY = globalCfg.offsetY or 18

        if growthDirection == "DOWN" then
            offsetX = baseX
            offsetY = baseY - (stackIndex * growthSpacing)
        elseif growthDirection == "UP" then
            offsetX = baseX
            offsetY = baseY + (stackIndex * growthSpacing)
        elseif growthDirection == "LEFT" then
            offsetX = baseX - (stackIndex * growthSpacing)
            offsetY = baseY
        elseif growthDirection == "RIGHT" then
            offsetX = baseX + (stackIndex * growthSpacing)
            offsetY = baseY
        else
            -- Default: DOWN
            offsetX = baseX
            offsetY = baseY - (stackIndex * growthSpacing)
        end
    end
    local width = settings.width or globalCfg.width or 0
    local height = settings.height or globalCfg.height or 4
    local barOrientation = settings.barOrientation or globalCfg.barOrientation or "HORIZONTAL"
    local barReverseFill = settings.barReverseFill or false
    local ringReverse = settings.ringReverse or false
    local borderSize = settings.borderSize or globalCfg.borderSize or 1
    local borderColor = settings.borderColor or globalCfg.borderColor or { 0, 0, 0, 1 }

    -- Per-buff frame strata (개별 설정 > 전체 설정 > 기본값)
    local strata = settings.frameStrata or globalCfg.frameStrata or "MEDIUM"
    bar:SetFrameStrata(strata)
    if bar.TextFrame then
        bar.TextFrame:SetFrameStrata(strata)
    end

    -- CDM tracking
    if cooldownID == 0 then
        bar:Hide()
        return
    end

    -- CDM 프레임 찾기
    local CDMScanner = DDingUI.CDMScanner
    local frame = CDMScanner and CDMScanner.FindFrameByCooldownID(cooldownID)

    -- CDM에서 숨기기 (추적 중인 버프를 CDM에서 숨김 - 중복 방지)
    -- pcall로 감싸서 전투 중 taint/invalid frame 에러 방지 -- [12.0.1]
    if hideFromCDM and frame then
        pcall(function()
            local entry = CDMScanner and CDMScanner.GetEntry(cooldownID)
            if entry then
                if entry.iconFrame and entry.iconFrame.SetAlpha then
                    entry.iconFrame:SetAlpha(0)
                    entry.iconFrame._ddingHidden = true
                end
                if entry.barFrame and entry.barFrame.SetAlpha then
                    entry.barFrame:SetAlpha(0)
                    entry.barFrame._ddingHidden = true
                end
                if entry.frame and entry.frame.SetAlpha and not entry.iconFrame and not entry.barFrame then
                    entry.frame:SetAlpha(0)
                    entry.frame._ddingHidden = true
                end
            elseif frame.SetAlpha then
                frame:SetAlpha(0)
                frame._ddingHidden = true
            end
        end)
    elseif frame then
        pcall(function()
            local entry = CDMScanner and CDMScanner.GetEntry(cooldownID)
            if entry then
                if entry.iconFrame and entry.iconFrame._ddingHidden and entry.iconFrame.SetAlpha then
                    entry.iconFrame:SetAlpha(1)
                    entry.iconFrame._ddingHidden = nil
                end
                if entry.barFrame and entry.barFrame._ddingHidden and entry.barFrame.SetAlpha then
                    entry.barFrame:SetAlpha(1)
                    entry.barFrame._ddingHidden = nil
                end
                if entry.frame and entry.frame._ddingHidden and entry.frame.SetAlpha then
                    entry.frame:SetAlpha(1)
                    entry.frame._ddingHidden = nil
                end
            elseif frame._ddingHidden and frame.SetAlpha then
                frame:SetAlpha(1)
                frame._ddingHidden = nil
            end
        end)
    end

    -- ============================================================
    -- MANUAL TRACKING MODE: Use spell-cast-based stacks instead of aura
    -- ============================================================
    local isManualMode = trackedBuff.trackingMode == "manual"
    local manualStackCount, manualExpiresAt = nil, nil
    if isManualMode then
        manualStackCount, manualExpiresAt = GetManualStacks(barIndex)
    end

    -- [12.0.1] Taint-safe stacks resolution (CDMScanner FontString > API > fallback)
    local trackedStacks, auraInstanceID, unit = ResolveTrackedStacks(cooldownID, frame, isManualMode, manualStackCount)

    -- hasData: frame과 auraInstanceID 존재 여부 (for auto mode)
    -- For manual mode, hasData is true if we have stacks > 0
    local hasData
    if isManualMode then
        hasData = (manualStackCount or 0) > 0
    else
        hasData = auraInstanceID ~= nil
    end

    -- ============================================================
    -- ALERT SYSTEM: 트리거 평가 + 액션 실행
    -- ============================================================
    -- [12.0.1] 알림 평가 (plain 캐싱 → secret 시 캐시 사용)
    local alertResult = EvaluateAlerts(trackedBuff, trackedStacks, hasData, auraInstanceID, unit)
    if alertResult then
        ApplyAlertActions(alertResult, trackedBuff, bar)
        if bar._alertColorOverride then
            barColor = bar._alertColorOverride
        end
    else
        bar._alertColorOverride = nil
    end

    -- ============================================================
    -- DYNAMIC DURATION: CDM에서 실시간으로 duration 읽기
    -- ============================================================
    if dynamicDuration and hasData and not isManualMode then
        local detectedDuration = nil

        -- 1. CDM 바 프레임에서 GetMinMaxValues()로 읽기
        if frame then
            pcall(function()
                -- BuffBarCooldownViewer의 바 프레임
                if frame.Bar and frame.Bar.GetMinMaxValues then
                    local _, maxVal = frame.Bar:GetMinMaxValues()
                    if maxVal and maxVal > 0 then
                        detectedDuration = maxVal
                    end
                end
                -- 또는 frame 자체가 StatusBar일 경우
                if not detectedDuration and frame.GetMinMaxValues then
                    local _, maxVal = frame:GetMinMaxValues()
                    if maxVal and maxVal > 0 then
                        detectedDuration = maxVal
                    end
                end
            end)
        end

        -- 2. CDM 바에서 못 찾으면 aura 데이터에서 duration 읽기
        if not detectedDuration and auraInstanceID then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                if auraData and auraData.duration and auraData.duration > 0 then
                    detectedDuration = auraData.duration
                end
            end)
        end

        -- 3. 감지된 duration 사용 (없으면 기본값 유지)
        if detectedDuration and detectedDuration > 0 then
            stackDuration = detectedDuration
            -- 설정에 저장하여 다음 업데이트에서도 사용
            if settings then
                settings._detectedDuration = detectedDuration
            end
        elseif settings and settings._detectedDuration then
            -- 이전에 감지된 값 사용
            stackDuration = settings._detectedDuration
        end
    elseif dynamicDuration and settings and settings._detectedDuration then
        -- 버프 비활성화 상태에서도 이전 감지 값 유지
        stackDuration = settings._detectedDuration
    end

    local current, max

    -- ============================================================
    -- DURATION MODE     -- ============================================================
    if barFillMode == "duration" then
        max = stackDuration

        if hasData then
            -- Duration 모드: C_UnitAuras.GetAuraDuration 사용
            -- OnUpdate로 지속시간 폴링
            bar._durationData = {
                unit = unit,
                auraID = auraInstanceID,
                maxDuration = stackDuration,
                showDurationText = showDurationText,
                stacksMode = false,  -- Duration 모드: 바 값 업데이트 함
                durationDecimals = durationDecimals,  -- 소수점 자릿수
                barStyle = barStyle,  -- 바 스타일 (bar/circular/square)
                -- Duration warning
                warningEnabled = durationWarningEnabled,
                warningThreshold = durationWarningThreshold,
                warningColor = durationWarningColor,
                normalColor = durationTextColor,
                -- Manual mode data
                isManualMode = isManualMode,
                manualExpiresAt = manualExpiresAt,
                barIndex = barIndex,
            }

            -- Circular/Square/Donut/Ring 스타일: Cooldown 프레임 초기화
            if barStyle == "circular" or barStyle == "square" or barStyle == "donut" or barStyle == "ring" then
                -- [12.0.1] 버프 갱신 시 Clear 후 재설정
                if bar._lastCooldownAuraID ~= auraInstanceID then
                    bar.Cooldown:Clear()
                end
                bar._lastCooldownAuraID = auraInstanceID
                pcall(function()
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if auraData and auraData.expirationTime and auraData.duration then
                        local startTime = auraData.expirationTime - auraData.duration
                        bar.Cooldown:SetCooldown(startTime, auraData.duration)
                    end
                end)
            end

            bar.StatusBar:SetMinMaxValues(0, max)

            -- OnUpdate 핸들러 설정 (매 프레임 폴링)
            if not bar._hasDurationUpdate then
                bar.StatusBar:SetScript("OnUpdate", function(self, elapsed)
                    local data = bar._durationData
                    if not data then return end

                    -- Manual 모드: manualExpiresAt 기반 duration 계산
                    if data.isManualMode then
                        local _, expiresAt = GetManualStacks(data.barIndex)
                        if expiresAt then
                            local remaining = math.max(0, expiresAt - GetTime())
                            if not data.stacksMode then
                                self:SetValue(remaining)
                            end
                            if bar.DurationText and data.showDurationText then
                                bar.DurationText:SetText(FormatDuration(remaining, data.durationDecimals))
                                if data.warningEnabled then
                                    if remaining <= data.warningThreshold then
                                        local wc = data.warningColor
                                        bar.DurationText:SetTextColor(wc[1] or 1, wc[2] or 0.2, wc[3] or 0.2, wc[4] or 1)
                                    else
                                        local nc = data.normalColor
                                        bar.DurationText:SetTextColor(nc[1] or 1, nc[2] or 1, nc[3] or 1, nc[4] or 1)
                                    end
                                end
                            end
                        else
                            self:SetValue(0)
                        end
                        return
                    end

                    -- Auto 모드: auraID 기반 duration 계산
                    if not data.auraID then return end

                    pcall(function()
                        local durObj = C_UnitAuras.GetAuraDuration(data.unit, data.auraID)
                        if durObj then
                            local remaining = durObj:GetRemainingDuration()

                            if not data.stacksMode then
                                self:SetValue(remaining)
                            end

                            if bar.DurationText and data.showDurationText then
                                -- SetFormattedText로 secret value도 소수점 설정 적용
                                local fmt = GetDecimalFmt(data.durationDecimals or 1)
                                bar.DurationText:SetFormattedText(fmt, remaining)

                                -- 경고 색상 적용 (pcall로 secret value 비교 보호)
                                if data.warningEnabled and remaining then
                                    pcall(function()
                                        if remaining <= data.warningThreshold then
                                            local wc = data.warningColor
                                            bar.DurationText:SetTextColor(wc[1] or 1, wc[2] or 0.2, wc[3] or 0.2, wc[4] or 1)
                                        else
                                            local nc = data.normalColor
                                            bar.DurationText:SetTextColor(nc[1] or 1, nc[2] or 1, nc[3] or 1, nc[4] or 1)
                                        end
                                    end)
                                end
                            end
                        end
                    end)
                end)
                bar._hasDurationUpdate = true
            end

            -- 초기값 설정 (Manual 모드)
            if isManualMode and manualExpiresAt then
                local remaining = math.max(0, manualExpiresAt - GetTime())
                bar.StatusBar:SetValue(remaining)
            -- 초기값 설정 (Auto 모드)
            elseif auraInstanceID then
                pcall(function()
                    local durObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
                    if durObj then
                        local remaining = durObj:GetRemainingDuration()
                        bar.StatusBar:SetValue(remaining)
                    end
                end)
            end
        else
            -- Duration 모드지만 버프 없음: OnUpdate 제거하고 0으로 설정
            if bar._hasDurationUpdate then
                bar.StatusBar:SetScript("OnUpdate", nil)
                bar._hasDurationUpdate = false
            end
            bar._durationData = nil
            bar.StatusBar:SetMinMaxValues(0, max)
            bar.StatusBar:SetValue(0)
            -- Cooldown 클리어 (원형/사각형 스타일)
            if bar.Cooldown then
                bar.Cooldown:Clear()
            end
        end

        current = 0  -- 텍스트 표시용 (실제 값은 OnUpdate에서)
    else
        -- ============================================================
        -- STACKS MODE (기본)
        -- ============================================================
        current = trackedStacks
        max = maxStacks

        -- 스택 모드에서도 지속시간 텍스트 표시 가능
        if showDurationText and hasData then
            -- Duration 텍스트 업데이트용 OnUpdate 설정
            bar._durationData = {
                unit = unit,
                auraID = auraInstanceID,
                maxDuration = stackDuration,
                showDurationText = showDurationText,
                stacksMode = true,  -- 스택 모드 플래그 (바 값 업데이트 안 함)
                durationDecimals = durationDecimals,  -- 소수점 자릿수
                barStyle = barStyle,  -- 바 스타일 (bar/circular/square)
                -- Duration warning
                warningEnabled = durationWarningEnabled,
                warningThreshold = durationWarningThreshold,
                warningColor = durationWarningColor,
                normalColor = durationTextColor,
            }

            -- Circular/Square/Donut/Ring 스타일: Cooldown 프레임 초기화 (스택 모드에서도)
            if barStyle == "circular" or barStyle == "square" or barStyle == "donut" or barStyle == "ring" then
                -- [12.0.1] 버프 갱신 시 Clear 후 재설정
                if bar._lastCooldownAuraID ~= auraInstanceID then
                    bar.Cooldown:Clear()
                end
                bar._lastCooldownAuraID = auraInstanceID
                pcall(function()
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if auraData and auraData.expirationTime and auraData.duration then
                        local startTime = auraData.expirationTime - auraData.duration
                        bar.Cooldown:SetCooldown(startTime, auraData.duration)
                    end
                end)
            end

            if not bar._hasDurationUpdate then
                bar.StatusBar:SetScript("OnUpdate", function(self, elapsed)
                    local data = bar._durationData
                    if not data or not data.auraID then return end

                    pcall(function()
                        local durObj = C_UnitAuras.GetAuraDuration(data.unit, data.auraID)
                        if durObj then
                            local remaining = durObj:GetRemainingDuration()

                            -- 스택 모드가 아닐 때만 바 값 업데이트 (Secret value OK)
                            if not data.stacksMode then
                                self:SetValue(remaining)
                            end

                            -- Duration 텍스트 업데이트
                            if bar.DurationText and data.showDurationText then
                                -- SetFormattedText로 secret value도 소수점 설정 적용
                                local fmt = GetDecimalFmt(data.durationDecimals or 1)
                                bar.DurationText:SetFormattedText(fmt, remaining)

                                -- 경고 색상 적용 (pcall로 secret value 비교 보호)
                                if data.warningEnabled and remaining then
                                    pcall(function()
                                        if remaining <= data.warningThreshold then
                                            local wc = data.warningColor
                                            bar.DurationText:SetTextColor(wc[1] or 1, wc[2] or 0.2, wc[3] or 0.2, wc[4] or 1)
                                        else
                                            local nc = data.normalColor
                                            bar.DurationText:SetTextColor(nc[1] or 1, nc[2] or 1, nc[3] or 1, nc[4] or 1)
                                        end
                                    end)
                                end
                            end
                        end
                    end)
                end)
                bar._hasDurationUpdate = true
            end
        else
            -- Duration OnUpdate 제거
            if bar._hasDurationUpdate then
                bar.StatusBar:SetScript("OnUpdate", nil)
                bar._hasDurationUpdate = false
            end
            bar._durationData = nil
        end
    end

    -- onlyInCombat: 전투 중에만 표시 (비전투 시 숨기기)
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    local onlyInCombat = settings.onlyInCombat or false
    if onlyInCombat and not inCombat and not isInMoverMode and not isInPreviewMode then
        bar:Hide()
        return
    end

    -- hideWhenZero (skip in mover/preview mode to show all bars)
    -- Also skip hiding if showInCombat is enabled and we're in combat
    if hideWhenZero and not hasData and not isInMoverMode and not isInPreviewMode then
        if not (showInCombat and inCombat) then
            bar:Hide()
            return
        end
    end

    -- Get anchor (개별 버프 설정 사용)
    local anchor = _G[attachTo]
    -- 앵커가 없으면 UIParent로 폴백
    if not anchor then
        anchor = UIParent
    end

    -- Calculate width
    local barWidth = width
    if barWidth <= 0 then
        barWidth = PixelSnap(DDingUI:GetEffectiveAnchorWidth(anchor))
    else
        barWidth = DDingUI:Scale(barWidth)
    end
    if barWidth <= 0 then
        barWidth = 200
    end

    -- Update position (DDingUI:Scale 사용 - v1.1.5.5와 일관성)
    local desiredX = DDingUI:Scale(offsetX)
    local desiredY = DDingUI:Scale(offsetY)
    local desiredHeight = DDingUI:Scale(height)

    -- Mover 모드일 때는 위치 설정 건너뛰기 (사용자가 드래그로 조절 중)
    -- 단, 초기 진입 시(moverPositionSynced=false)에는 최신 설정으로 위치 동기화
    if not isInMoverMode or not moverPositionSynced then
        if bar._lastAnchor ~= anchor or bar._lastAnchorPoint ~= anchorPoint or bar._lastOffsetX ~= desiredX or bar._lastOffsetY ~= desiredY then
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", anchor, anchorPoint, desiredX, desiredY)
            bar._lastAnchor = anchor
            bar._lastAnchorPoint = anchorPoint
            bar._lastOffsetX = desiredX
            bar._lastOffsetY = desiredY
        end
    end

    -- Circular/Square/Donut/Ring style: width = height (정사각형)
    local isCircularStyle = (barStyle == "circular" or barStyle == "square" or barStyle == "donut")
    local isRingStyle = (barStyle == "ring")
    local isDonutStyle = (barStyle == "donut")
    local isVertical = (barOrientation == "VERTICAL")
    if isCircularStyle or isRingStyle then
        barWidth = desiredHeight  -- 정사각형으로 만들기
    end

    -- Vertical orientation: swap width and height for the frame
    local frameWidth, frameHeight
    if isVertical and not isCircularStyle then
        frameWidth = desiredHeight  -- height becomes width
        frameHeight = barWidth      -- width becomes height
    else
        frameWidth = barWidth
        frameHeight = desiredHeight
    end

    if bar._lastHeight ~= frameHeight then
        bar:SetHeight(frameHeight)
        bar._lastHeight = frameHeight
    end

    if bar._lastWidth ~= frameWidth then
        bar:SetWidth(frameWidth)
        bar._lastWidth = frameWidth
    end

    -- Update background color
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
        bar.Background:SetShown(not isCircularStyle and not isRingStyle)  -- 원형/링 스타일에서는 배경 숨김
    end

    -- Bar style switching: StatusBar vs Cooldown vs Ring (always apply visibility)
    if isRingStyle then
        -- Ring style: use Ring textures with Cooldown swipe
        bar.StatusBar:Hide()
        if bar.CooldownTexture then
            bar.CooldownTexture:Hide()
        end
        if bar.DonutCenter then
            bar.DonutCenter:Hide()
        end

        -- Show Ring textures
        if bar.RingBackground then
            bar.RingBackground:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
            bar.RingBackground:Show()
        end
        if bar.RingProgress then
            bar.RingProgress:SetVertexColor(barColor[1], barColor[2], barColor[3], barColor[4] or 1)
            bar.RingProgress:Show()
        end
        if bar.RingBorder then
            local bc = borderColor
            bar.RingBorder:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
            bar.RingBorder:SetSize(frameWidth + 4, frameHeight + 4)
            bar.RingBorder:Show()
        end

        -- Use Cooldown for swipe effect over the ring
        if bar.Cooldown then
            bar.Cooldown:SetDrawSwipe(true)
            bar.Cooldown:SetSwipeColor(0, 0, 0, 0.6)
            -- ringReverse: true = 반시계 방향 (채움), false = 시계 방향 (비움)
            bar.Cooldown:SetReverse(not ringReverse)
            bar.Cooldown:Show()
        end
    elseif isCircularStyle then
        -- Circular/Square/Donut: use Cooldown frame
        bar.StatusBar:Hide()
        -- Hide Ring textures
        if bar.RingBackground then bar.RingBackground:Hide() end
        if bar.RingProgress then bar.RingProgress:Hide() end
        if bar.RingBorder then bar.RingBorder:Hide() end

        if bar.Cooldown then
            bar.Cooldown:Show()
        end
        if bar.CooldownTexture then
            bar.CooldownTexture:Show()
            -- 기본 아이콘 또는 버프 아이콘 설정
            local icon = trackedBuff.icon or 134400
            bar.CooldownTexture:SetTexture(icon)
        end
    else
        -- Bar: use StatusBar
        bar.StatusBar:Show()
        -- Apply bar orientation (HORIZONTAL or VERTICAL)
        if bar._lastOrientation ~= barOrientation then
            bar.StatusBar:SetOrientation(barOrientation)
            bar._lastOrientation = barOrientation
        end
        -- Apply reverse fill (right-to-left or top-to-bottom)
        if bar._lastReverseFill ~= barReverseFill then
            bar.StatusBar:SetReverseFill(barReverseFill)
            bar._lastReverseFill = barReverseFill
        end
        -- Hide Ring textures
        if bar.RingBackground then bar.RingBackground:Hide() end
        if bar.RingProgress then bar.RingProgress:Hide() end
        if bar.RingBorder then bar.RingBorder:Hide() end

        if bar.Cooldown then
            bar.Cooldown:Hide()
        end
        if bar.CooldownTexture then
            bar.CooldownTexture:Hide()
        end
        if bar.DonutCenter then
            bar.DonutCenter:Hide()
        end
    end
    bar._lastBarStyle = barStyle

    -- Donut style: update center cutout size based on donutThickness
    if isDonutStyle and bar.DonutCenter then
        local thickness = settings.donutThickness or 0.3
        local centerSize = desiredHeight * (1 - thickness * 2)
        if centerSize < 4 then centerSize = 4 end
        bar.DonutCenter:SetSize(centerSize, centerSize)
        bar.DonutCenter:Show()
    elseif bar.DonutCenter then
        bar.DonutCenter:Hide()
    end

    -- Update Cooldown texture icon if changed
    if isCircularStyle and bar.CooldownTexture then
        local icon = trackedBuff.icon or 134400
        if bar._lastCooldownIcon ~= icon then
            bar.CooldownTexture:SetTexture(icon)
            bar._lastCooldownIcon = icon
        end
    end

    -- Update texture (per-buff settings override global) - only for bar style (not circular/ring)
    local tex = DDingUI:GetTexture(settings.texture or globalCfg.texture)
    if bar._lastTexture ~= tex and not isCircularStyle and not isRingStyle then
        bar.StatusBar:SetStatusBarTexture(tex)
        bar._lastTexture = tex
    end

    -- Update border (texture-based) - hide for ring style (uses RingBorder instead)
    if bar.Border then
        if isRingStyle then
            ShowTextureBorder(bar.Border, false)
        else
            local scaledBorder = DDingUI:ScaleBorder(borderSize)
            bar._scaledBorder = scaledBorder
            UpdateTextureBorderSize(bar.Border, scaledBorder)
            UpdateTextureBorderColor(bar.Border, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
            ShowTextureBorder(bar.Border, scaledBorder > 0)
        end
    end

    -- Preview/Mover mode: use sample values when no actual data
    local displayCurrent = current
    local displayStacks = trackedStacks
    if not hasData then
        if isInPreviewMode then
            -- Animated preview values
            displayCurrent, displayStacks = GetPreviewValues(barIndex, max, stackDuration, barFillMode)
        elseif isInMoverMode then
            -- Static mover values (60% filled)
            displayCurrent = math.ceil(max * 0.6)
            displayStacks = displayCurrent
        end
    end

    -- Set bar values (secret value를 직접 전달)
    -- Duration mode는 OnUpdate에서 처리하므로 여기서 skip
    -- (isCircularStyle already defined above, no need to redefine)

    if barFillMode ~= "duration" then
        local smoothEnabled = settings.smoothProgress
        if smoothEnabled == nil then smoothEnabled = globalCfg.smoothProgress end
        local interpolation = smoothEnabled and buildVersion >= 120000 and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
        bar.StatusBar:SetMinMaxValues(0, max, interpolation)
        bar.StatusBar:SetValue(displayCurrent, interpolation)
    elseif (isInPreviewMode or isInMoverMode) and not hasData then
        -- Duration mode preview: show 60% filled
        bar.StatusBar:SetMinMaxValues(0, stackDuration)
        bar.StatusBar:SetValue(stackDuration * 0.6)
    end

    -- Circular/Square 스타일: 미리보기/이동 모드에서 Cooldown 설정
    if isCircularStyle and bar.Cooldown then
        if (isInPreviewMode or isInMoverMode) and not hasData then
            -- 미리보기/이동 모드: 가짜 쿨다운 표시 (60% 진행)
            local fakeDuration = stackDuration or 30
            local fakeStart = GetTime() - (fakeDuration * 0.4)  -- 40% 남음 (60% 진행)
            bar.Cooldown:SetCooldown(fakeStart, fakeDuration)
        elseif not hasData then
            -- 데이터 없음: 쿨다운 클리어
            bar.Cooldown:Clear()
        end
    end

    -- Set bar color
    bar.StatusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] or 1)

    -- Text display (개별 버프 설정 사용)
    -- 중첩 텍스트 설정 (barFillMode와 무관하게 표시 가능)
    bar.TextValue:SetText(displayStacks)  -- Use display value (sample in preview mode)
    local stacksFont = settings.textFont or globalCfg.textFont
    bar.TextValue:SetFont(DDingUI:GetFont(stacksFont), textSize, "OUTLINE")
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetJustifyH(textAlign)
    bar.TextValue:ClearAllPoints()
    bar.TextValue:SetPoint(textAlign, bar.TextFrame, textAlign, DDingUI:Scale(textX), DDingUI:Scale(textY))
    bar.TextValue:SetTextColor(textColor[1] or 1, textColor[2] or 1, textColor[3] or 1, textColor[4] or 1)
    bar.TextValue:SetShown(showStacksText)

    -- 지속시간 텍스트 설정 (barFillMode와 무관하게 표시 가능)
    if showDurationText then
        local durationFont = settings.durationTextFont or settings.textFont or globalCfg.textFont
        bar.DurationText:SetFont(DDingUI:GetFont(durationFont), durationTextSize, "OUTLINE")
        bar.DurationText:SetShadowOffset(0, 0)
        bar.DurationText:SetJustifyH(durationTextAlign)
        bar.DurationText:ClearAllPoints()
        bar.DurationText:SetPoint(durationTextAlign, bar.TextFrame, durationTextAlign, DDingUI:Scale(durationTextX), DDingUI:Scale(durationTextY))

        -- 초기 색상 설정: 경고 임계값 이하면 경고 색상, 아니면 일반 색상
        local initialColor = durationTextColor
        if durationWarningEnabled and hasData then
            local initialRemaining = nil
            pcall(function()
                if auraInstanceID then
                    local durObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
                    if durObj then
                        initialRemaining = durObj:GetRemainingDuration()
                    end
                elseif isManualMode and manualExpiresAt then
                    initialRemaining = manualExpiresAt - GetTime()
                end
            end)
            if initialRemaining and initialRemaining <= durationWarningThreshold then
                initialColor = durationWarningColor
            end
        end
        bar.DurationText:SetTextColor(initialColor[1] or 1, initialColor[2] or 1, initialColor[3] or 1, initialColor[4] or 1)

        -- Preview/Mover mode: show duration text
        if not hasData then
            if isInPreviewMode then
                local _, previewDuration = GetPreviewValues(barIndex, max, stackDuration, "duration")
                bar.DurationText:SetText(string.format("%." .. durationDecimals .. "f", previewDuration))
            elseif isInMoverMode then
                bar.DurationText:SetText(string.format("%." .. durationDecimals .. "f", stackDuration * 0.6))
            else
                bar.DurationText:SetText("")
            end
        else
            bar.DurationText:SetText("")  -- OnUpdate에서 업데이트
        end
        bar.DurationText:Show()
    else
        bar.DurationText:Hide()
    end

    -- TextFrame은 둘 중 하나라도 표시되면 보이게
    bar.TextFrame:SetShown(showStacksText or showDurationText)

    -- Update ticks (barFillMode, durationTickPositions, showTicks, tickWidth, barOrientation 전달)
    -- Ring/Circular 스타일에서는 tick 표시 안 함
    if not isRingStyle and not isCircularStyle then
        self:UpdateBuffTrackerBarTicks(bar, displayCurrent, max, barFillMode, durationTickPositions, showTicks, tickWidth, barOrientation)
    else
        -- Hide all ticks for ring/circular styles
        for _, tick in ipairs(bar.ticks or {}) do
            tick:Hide()
        end
    end

    bar:Show()

    if BUFF_TRACKER_DEBUG then
        print(string.format("[BuffTracker] Bar %d (%s): stacks=%s, hasData=%s, visible=%s, fillMode=%s, trackingMode=%s, isManual=%s",
            barIndex, trackedBuff.name or "?",
            tostring(current), tostring(hasData), tostring(bar:IsVisible()), barFillMode,
            tostring(trackedBuff.trackingMode), tostring(isManualMode)))
    end
end

-- ============================================================
-- RING MODE UPDATE
-- 링 표시 모드 업데이트 함수
-- ============================================================
function ResourceBars:UpdateSingleTrackedBuffRing(barIndex, trackedBuff, globalCfg)
    local bar = GetTrackedBuffBar(barIndex)
    if not bar then return end

    local settings = trackedBuff.settings or {}
    local cooldownID = trackedBuff.cooldownID or 0

    -- DDingUI:Scale 사용 (픽셀퍼펙트 스케일, v1.1.5.5와 일관성 유지)

    -- Ring-specific settings
    local ringSize = settings.ringSize or 32
    local ringFillMode = settings.ringFillMode or "stacks"
    local ringReverse = settings.ringReverse or false
    local ringColor = settings.ringColor or { 1, 0.8, 0, 1 }
    local ringBgColor = settings.ringBgColor or { 0.15, 0.15, 0.15, 1 }
    local ringBorderSize = settings.ringBorderSize or 2
    local ringBorderColor = settings.ringBorderColor or { 0, 0, 0, 1 }
    local ringShowText = settings.ringShowText ~= false
    local ringTextSize = settings.ringTextSize or 12
    local ringOffsetX = settings.ringOffsetX or 0
    local ringOffsetY = settings.ringOffsetY or 0
    local maxStacks = settings.maxStacks or 1
    local stackDuration = settings.stackDuration or 30
    local dynamicDuration = settings.dynamicDuration or false
    local hideWhenZero = settings.hideWhenZero
    if hideWhenZero == nil then hideWhenZero = true end
    local alwaysShowInCombat = settings.alwaysShowInCombat or false

    -- Attach frame settings
    local attachTo = settings.attachTo or globalCfg.attachTo or "EssentialCooldownViewer"
    local anchorPoint = settings.ringAnchorPoint or "CENTER"

    -- Per-buff frame strata (개별 설정 > 전체 설정 > 기본값)
    local strata = settings.frameStrata or globalCfg.frameStrata or "MEDIUM"
    bar:SetFrameStrata(strata)
    if bar.TextFrame then
        bar.TextFrame:SetFrameStrata(strata)
    end

    -- Growth direction settings (same as bar mode)
    local growthDirection = settings.growthDirection or globalCfg.growthDirection or "DOWN"
    local growthSpacing = settings.growthSpacing or globalCfg.growthSpacing or 4

    -- Get buff data (same as bar mode)
    local isManualMode = trackedBuff.trackingMode == "manual"
    local current, total, hasData, actualDuration, remainingDuration = 0, maxStacks, false, stackDuration, 0

    -- CDM 프레임 찾기
    local CDMScanner = DDingUI.CDMScanner
    local frame = CDMScanner and CDMScanner.FindFrameByCooldownID(cooldownID)

    -- Manual mode
    local manualStackCount, manualExpiresAt = nil, nil
    if isManualMode then
        manualStackCount, manualExpiresAt = GetManualStacks(barIndex)
    end

    -- [12.0.1] Taint-safe stacks resolution (CDMScanner FontString > API > fallback)
    local trackedStacks, auraInstanceID, unit = ResolveTrackedStacks(cooldownID, frame, isManualMode, manualStackCount)
    local auraData = nil

    if isManualMode then
        current = trackedStacks
        if manualExpiresAt and manualExpiresAt > 0 then
            remainingDuration = math.max(0, manualExpiresAt - GetTime())
        end
        hasData = trackedStacks > 0
    else
        current = trackedStacks or 0
        hasData = auraInstanceID ~= nil

        -- Duration 데이터 가져오기
        if hasData and auraInstanceID then
            pcall(function()
                local aData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                if aData then
                    if aData.duration and aData.duration > 0 then
                        actualDuration = aData.duration
                    end
                    if aData.expirationTime and aData.expirationTime > 0 then
                        remainingDuration = math.max(0, aData.expirationTime - GetTime())
                    end
                end
            end)
        end
    end

    -- ============================================================
    -- DYNAMIC DURATION: CDM에서 실시간으로 duration 읽기 (바와 동일)
    -- ============================================================
    if dynamicDuration and hasData and not isManualMode then
        local detectedDuration = nil

        -- 1. CDM 바 프레임에서 GetMinMaxValues()로 읽기
        if frame then
            pcall(function()
                if frame.Bar and frame.Bar.GetMinMaxValues then
                    local _, maxVal = frame.Bar:GetMinMaxValues()
                    if maxVal and maxVal > 0 then
                        detectedDuration = maxVal
                    end
                end
                if not detectedDuration and frame.GetMinMaxValues then
                    local _, maxVal = frame:GetMinMaxValues()
                    if maxVal and maxVal > 0 then
                        detectedDuration = maxVal
                    end
                end
            end)
        end

        -- 2. CDM 바에서 못 찾으면 aura 데이터에서 duration 읽기
        if not detectedDuration and auraInstanceID then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                if auraData and auraData.duration and auraData.duration > 0 then
                    detectedDuration = auraData.duration
                end
            end)
        end

        -- 3. 감지된 duration 사용
        if detectedDuration and detectedDuration > 0 then
            stackDuration = detectedDuration
            if settings then
                settings._detectedDuration = detectedDuration
            end
        elseif settings and settings._detectedDuration then
            stackDuration = settings._detectedDuration
        end
    elseif dynamicDuration and settings and settings._detectedDuration then
        stackDuration = settings._detectedDuration
    end

    -- Visibility check (include preview/mover mode - uses file-local isInPreviewMode, isInMoverMode)
    local inCombat = UnitAffectingCombat("player")
    local shouldShow = hasData or isInPreviewMode or isInMoverMode

    if not shouldShow and hideWhenZero then
        if not (alwaysShowInCombat and inCombat) then
            bar:Hide()
            return
        end
    end

    -- Preview/Mover mode: generate sample values
    if not hasData then
        if isInPreviewMode then
            current, remainingDuration = GetPreviewValues(barIndex, maxStacks, stackDuration, ringFillMode)
            total = maxStacks
            actualDuration = stackDuration
            hasData = true
        elseif isInMoverMode then
            current = math.ceil(maxStacks * 0.6)
            total = maxStacks
            remainingDuration = stackDuration * 0.6
            actualDuration = stackDuration
            hasData = true
        end
    end

    if not hasData then
        bar:Hide()
        return
    end

    -- Position and size (same pattern as bar mode)
    local anchor = _G[attachTo]
    -- 앵커가 없거나 숨겨져 있으면 UIParent로 폴백
    if not anchor then
        anchor = UIParent
    end

    -- Set ring size (square)
    bar:SetSize(ringSize, ringSize)

    -- Position - growthDirection에 따른 링 스태킹
    -- DDingUI:Scale 사용 (픽셀퍼펙트 스케일, v1.1.5.5와 일관성)
    local desiredX, desiredY

    -- 바 모드와 동일: 개별 오프셋이 설정되면 정확한 값 사용 (스태킹 무시)
    if settings.ringOffsetX ~= nil and settings.ringOffsetY ~= nil then
        -- Per-ring custom position: use exact values (DDingUI:Scale - v1.1.5.5와 일관성)
        desiredX = DDingUI:Scale(ringOffsetX)
        desiredY = DDingUI:Scale(ringOffsetY)
    else
        -- Auto-stack based on growth direction (DDingUI:Scale - v1.1.5.5와 일관성)
        local scaledOffsetX = DDingUI:Scale(ringOffsetX)
        local scaledOffsetY = DDingUI:Scale(ringOffsetY)
        local spacing = DDingUI:Scale(ringSize + growthSpacing)
        local stackIndex = barIndex - 1

        if growthDirection == "DOWN" then
            desiredX = scaledOffsetX
            desiredY = scaledOffsetY - (stackIndex * spacing)
        elseif growthDirection == "UP" then
            desiredX = scaledOffsetX
            desiredY = scaledOffsetY + (stackIndex * spacing)
        elseif growthDirection == "LEFT" then
            desiredX = scaledOffsetX - (stackIndex * spacing)
            desiredY = scaledOffsetY
        elseif growthDirection == "RIGHT" then
            desiredX = scaledOffsetX + (stackIndex * spacing)
            desiredY = scaledOffsetY
        else
            -- Default to DOWN
            desiredX = scaledOffsetX
            desiredY = scaledOffsetY - (stackIndex * spacing)
        end
    end

    -- Mover 모드일 때는 위치 설정 건너뛰기 (사용자가 드래그로 조절 중)
    -- 단, 초기 진입 시(moverPositionSynced=false)에는 최신 설정으로 위치 동기화
    if not isInMoverMode or not moverPositionSynced then
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", anchor, anchorPoint, desiredX, desiredY)
    end

    -- Hide bar-specific elements
    bar.StatusBar:Hide()
    bar.Background:Hide()
    if bar.Border then
        for _, tex in pairs(bar.Border.__dduiBorders or {}) do
            tex:Hide()
        end
    end
    if bar.DonutCenter then bar.DonutCenter:Hide() end

    -- ringThickness에 따라 텍스처 선택 (10, 20, 30, 40px)
    local ringThickness = settings.ringThickness or 20
    local ringTexture = string.format("Interface\\AddOns\\DDingUI\\Media\\Textures\\Ring_%dpx.tga", ringThickness)

    -- Show ring textures (explicitly set size and position)
    -- Border (outermost, behind everything)
    if bar.RingBorder then
        bar.RingBorder:ClearAllPoints()
        bar.RingBorder:SetPoint("CENTER", bar, "CENTER", 0, 0)
        bar.RingBorder:SetSize(ringSize + ringBorderSize * 2, ringSize + ringBorderSize * 2)
        bar.RingBorder:SetTexture(ringTexture)
        bar.RingBorder:SetVertexColor(ringBorderColor[1], ringBorderColor[2], ringBorderColor[3], ringBorderColor[4] or 1)
        bar.RingBorder:Show()
    end

    -- Hide old textures (CircularProgress 대신 CooldownFrame 사용)
    if bar.RingBackground then bar.RingBackground:Hide() end
    if bar.RingProgress then bar.RingProgress:Hide() end
    if bar.CooldownTexture then bar.CooldownTexture:Hide() end
    if bar.DonutCenter then bar.DonutCenter:Hide() end

    -- ============================================================
    -- RING PROGRESS (CDM Cooldown 훅 방식)
    -- CDM의 SetCooldown을 훅해서 우리 링과 동기화
    -- ============================================================

    if ringFillMode == "duration" and frame and frame.Cooldown then
        -- Duration 모드: CDM Cooldown 훅으로 동기화

        -- 1. 배경 링 텍스처 (맨 뒤 - BACKGROUND) - 항상 보임
        if not bar._ringColorBg then
            bar._ringColorBg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
            bar._ringColorBg:SetAllPoints(bar)
        end
        bar._ringColorBg:SetTexture(ringTexture)
        bar._ringColorBg:SetVertexColor(ringBgColor[1], ringBgColor[2], ringBgColor[3], ringBgColor[4] or 1)
        bar._ringColorBg:Show()

        -- 2. 스와이프를 색깔 링으로 설정 (시간 지나면서 사라짐 = 색깔이 줄어듦)
        bar.Cooldown:SetSwipeTexture(ringTexture)
        bar.Cooldown:SetSwipeColor(ringColor[1], ringColor[2], ringColor[3], ringColor[4] or 1)
        bar.Cooldown:SetDrawSwipe(true)
        bar.Cooldown:SetDrawEdge(false)
        bar.Cooldown:SetDrawBling(false)
        bar.Cooldown:SetHideCountdownNumbers(true)
        bar.Cooldown:SetReverse(not ringReverse)  -- ringReverse: true = 반시계 방향, false = 시계 방향
        bar.Cooldown:SetAllPoints(bar)
        bar.Cooldown:Show()

        -- 3. CDM의 SetCooldown 훅 (한 번만)
        if not frame._ddingCooldownHooked then
            local ourCooldown = bar.Cooldown
            hooksecurefunc(frame.Cooldown, "SetCooldown", function(self, start, duration)
                if ourCooldown and ourCooldown:IsShown() then
                    ourCooldown:SetCooldown(start, duration)
                end
            end)
            frame._ddingCooldownHooked = true
        end

        -- 4. 초기 동기화
        pcall(function()
            local cdmStart, cdmDuration = frame.Cooldown:GetCooldownTimes()
            if cdmStart and cdmDuration then
                bar.Cooldown:SetCooldown(cdmStart / 1000, cdmDuration / 1000)
            end
        end)

        -- 옛날 CircularProgress 숨기기
        if bar._ringBg then bar._ringBg:Hide() end
        if bar._ringFg then bar._ringFg:Hide() end
        if bar.CircularProgressFrame then bar.CircularProgressFrame:Hide() end

    else
        -- Stacks 모드: 기존 CircularProgress 사용
        local cropValue = settings.ringCrop or 1.41

        if bar.CircularProgressFrame and not bar._circularProgressInitialized then
            local CircularProgress = DDingUI.CircularProgress
            if CircularProgress then
                bar._ringBg = CircularProgress:Create(bar.CircularProgressFrame, "BACKGROUND", 1)
                CircularProgress:Modify(bar._ringBg, {
                    texture = ringTexture,
                    width = ringSize,
                    height = ringSize,
                    crop_x = cropValue,
                    crop_y = cropValue,
                    blendMode = "BLEND",
                })

                bar._ringFg = CircularProgress:Create(bar.CircularProgressFrame, "ARTWORK", 2)
                CircularProgress:Modify(bar._ringFg, {
                    texture = ringTexture,
                    width = ringSize,
                    height = ringSize,
                    crop_x = cropValue,
                    crop_y = cropValue,
                    blendMode = "BLEND",
                })

                bar._circularProgressInitialized = true
            end
        end

        if bar.CircularProgressFrame then
            bar.CircularProgressFrame:ClearAllPoints()
            bar.CircularProgressFrame:SetPoint("CENTER", bar, "CENTER", 0, 0)
            bar.CircularProgressFrame:SetSize(ringSize, ringSize)
            bar.CircularProgressFrame:Show()
        end

        if bar._ringBg then
            bar._ringBg.width = ringSize
            bar._ringBg.height = ringSize
            bar._ringBg:SetColor(ringBgColor[1], ringBgColor[2], ringBgColor[3], ringBgColor[4] or 0.8)
            bar._ringBg:SetProgress(0, 360)
            bar._ringBg:Show()
        end

        if bar._ringFg then
            bar._ringFg.width = ringSize
            bar._ringFg.height = ringSize
            bar._ringFg:SetColor(ringColor[1], ringColor[2], ringColor[3], ringColor[4] or 1)
            bar._ringFg:Show()

            local progress = 0
            if total > 0 then
                progress = current / total
            end

            if ringReverse then
                bar._ringFg:SetValue(progress, 0, 360)
            else
                bar._ringFg:SetValueReverse(progress, 0, 360)
            end
        end

        -- CDM 훅 방식 링 숨기기
        if bar._ringColorBg then bar._ringColorBg:Hide() end
        bar.Cooldown:Hide()
    end

    -- ============================================================
    -- DURATION MODE: 텍스트 표시용 데이터 설정
    -- CooldownFrame이 progress 애니메이션을 자동 처리하므로
    -- OnUpdate는 텍스트 업데이트만 담당
    -- ============================================================
    if ringFillMode == "duration" and hasData then
        bar._durationData = {
            unit = unit,
            auraID = auraInstanceID,
            maxDuration = stackDuration,
            showDurationText = ringShowText,
            durationDecimals = settings.ringDurationDecimals or 1,
            ringReverse = ringReverse,
            isManualMode = isManualMode,
            manualExpiresAt = manualExpiresAt,
            barIndex = barIndex,
        }
        -- 텍스트 업데이트용 OnUpdate (progress는 CooldownFrame이 처리)
        if ringShowText and not bar._hasRingTextUpdate then
            bar:SetScript("OnUpdate", function(self, elapsed)
                -- 0.05초 쓰로틀 (텍스트 업데이트는 20fps면 충분)
                self._textElapsed = (self._textElapsed or 0) + elapsed
                if self._textElapsed < 0.05 then return end
                self._textElapsed = 0

                local data = bar._durationData
                if not data or not data.auraID then return end

                -- 텍스트 표시: secret value로 직접 설정
                if bar.TextValue then
                    pcall(function()
                        local durObj = C_UnitAuras.GetAuraDuration(data.unit, data.auraID)
                        if durObj then
                            local secretRemaining = durObj:GetRemainingDuration()
                            bar.TextValue:SetFormattedText("%." .. (data.durationDecimals or 1) .. "f", secretRemaining)
                        end
                    end)
                end
            end)
            bar._hasRingTextUpdate = true
        elseif not ringShowText and bar._hasRingTextUpdate then
            bar:SetScript("OnUpdate", nil)
            bar._hasRingTextUpdate = false
        end
    elseif bar._hasRingTextUpdate then
        bar:SetScript("OnUpdate", nil)
        bar._hasRingTextUpdate = false
        bar._durationData = nil
    end

    -- Update text
    if bar.TextValue then
        bar.TextValue:ClearAllPoints()
        bar.TextValue:SetPoint("CENTER", bar, "CENTER", 0, 0)
        if ringShowText then
            bar.TextValue:SetFont(DDingUI:GetFont(globalCfg.textFont), ringTextSize, "OUTLINE")
            if ringFillMode == "duration" then
                -- Duration 모드: 초기값 설정 (OnUpdate에서 실시간 업데이트)
                local decimals = settings.ringDurationDecimals or 1
                if decimals == 0 then
                    bar.TextValue:SetText(string.format("%.0f", remainingDuration))
                else
                    bar.TextValue:SetText(string.format("%." .. decimals .. "f", remainingDuration))
                end
            else
                bar.TextValue:SetText(tostring(current))
            end
            bar.TextValue:Show()
        else
            bar.TextValue:Hide()
        end
    end

    -- Hide ticks for ring mode
    if bar.ticks then
        for _, tick in pairs(bar.ticks) do
            tick:Hide()
        end
    end

    bar:Show()
end

-- ============================================================
-- ICON MODE UPDATE
-- 아이콘 표시 모드 업데이트 함수
-- ============================================================
function ResourceBars:UpdateSingleTrackedBuffIcon(barIndex, trackedBuff, globalCfg)
    local icon = GetTrackedBuffIcon(barIndex)
    if not icon then return end

    local settings = trackedBuff.settings or {}
    local cooldownID = trackedBuff.cooldownID or 0

    -- DDingUI:Scale 사용 (픽셀퍼펙트 스케일, v1.1.5.5와 일관성 유지)

    -- Icon settings
    local iconSize = settings.iconSize or 32
    local iconAttachTo = settings.iconAttachTo or globalCfg.attachTo or "EssentialCooldownViewer"
    local iconAnchorPoint = settings.iconAnchorPoint or globalCfg.anchorPoint or "CENTER"
    local iconOffsetX = settings.iconOffsetX
    local iconOffsetY = settings.iconOffsetY
    -- Default stacking: place icons side by side horizontally
    if iconOffsetX == nil then
        iconOffsetX = (barIndex - 1) * (iconSize + 4)  -- 4px gap between icons
    end
    if iconOffsetY == nil then
        iconOffsetY = globalCfg.offsetY or 18
    end
    local iconAnimation = settings.iconAnimation or "glow"
    local iconSource = settings.iconSource or "buff"
    local customIconID = settings.customIconID or 0
    local showIconBorder = settings.showIconBorder ~= false
    local iconBorderSize = settings.iconBorderSize or 1
    local iconBorderColor = settings.iconBorderColor or { 0, 0, 0, 1 }
    local iconZoom = settings.iconZoom or 0.08
    local iconAspectRatio = settings.iconAspectRatio or 1.0
    local iconDesaturate = settings.iconDesaturate or false
    -- Icon stack text settings
    local iconShowStackText = settings.iconShowStackText ~= false
    local iconStackTextFont = settings.iconStackTextFont
    local iconStackTextSize = settings.iconStackTextSize or 12
    local iconStackTextColor = settings.iconStackTextColor or { 1, 1, 1, 1 }
    local iconStackTextAnchor = settings.iconStackTextAnchor or "BOTTOMRIGHT"
    local iconStackTextOffsetX = settings.iconStackTextOffsetX or -2
    local iconStackTextOffsetY = settings.iconStackTextOffsetY or 2
    local iconStackTextOutline = settings.iconStackTextOutline or "OUTLINE"
    local hideWhenZero = settings.hideWhenZero
    if hideWhenZero == nil then hideWhenZero = true end
    local showInCombat = settings.showInCombat or false
    local hideFromCDM = settings.hideFromCDM or false

    -- Per-buff frame strata (개별 설정 > 전체 설정 > 기본값)
    icon:SetFrameStrata(settings.frameStrata or globalCfg.frameStrata or "MEDIUM")

    -- ============================================================
    -- MANUAL TRACKING MODE: Use spell-cast-based stacks instead of aura
    -- ============================================================
    local isManualMode = trackedBuff.trackingMode == "manual"
    local manualStackCount, manualExpiresAtIcon = nil, nil
    if isManualMode then
        manualStackCount, manualExpiresAtIcon = GetManualStacks(barIndex)
    end

    -- Get tracking data
    local CDMScanner = DDingUI.CDMScanner
    local frame = CDMScanner and CDMScanner.FindFrameByCooldownID(cooldownID)

    -- [12.0.1] Taint-safe stacks resolution (CDMScanner FontString > API > fallback)
    local trackedStacks, auraInstanceID, unit = ResolveTrackedStacks(cooldownID, frame, isManualMode, manualStackCount)

    -- hasData for auto mode is based on auraInstanceID, for manual mode on stacks > 0
    local hasData
    if isManualMode then
        hasData = (manualStackCount or 0) > 0
    else
        hasData = auraInstanceID ~= nil
    end

    -- ============================================================
    -- ALERT SYSTEM: 트리거 평가 + 액션 실행
    -- ============================================================
    -- [12.0.1] alert 비교 전에 StackText에 stacks를 미리 기록
    -- [12.0.1] 알림 평가 (plain 캐싱 → secret 시 캐시 사용)
    local alertResult = EvaluateAlerts(trackedBuff, trackedStacks, hasData, auraInstanceID, unit)
    if alertResult then
        ApplyAlertActions(alertResult, trackedBuff, icon)
        if icon._alertColorOverride then
            iconBorderColor = icon._alertColorOverride
        end
    else
        icon._alertColorOverride = nil
    end

    -- CDM에서 숨기기 (추적 중인 버프를 CDM에서 숨김 - 중복 방지)
    if hideFromCDM and frame then
        local entry = CDMScanner and CDMScanner.GetEntry(cooldownID)
        if entry then
            if entry.iconFrame then
                entry.iconFrame:SetAlpha(0)
                entry.iconFrame._ddingHidden = true
            end
            if entry.barFrame then
                entry.barFrame:SetAlpha(0)
                entry.barFrame._ddingHidden = true
            end
            if entry.frame and not entry.iconFrame and not entry.barFrame then
                entry.frame:SetAlpha(0)
                entry.frame._ddingHidden = true
            end
        else
            frame:SetAlpha(0)
            frame._ddingHidden = true
        end
    elseif frame then
        local entry = CDMScanner and CDMScanner.GetEntry(cooldownID)
        if entry then
            if entry.iconFrame and entry.iconFrame._ddingHidden then
                entry.iconFrame:SetAlpha(1)
                entry.iconFrame._ddingHidden = nil
            end
            if entry.barFrame and entry.barFrame._ddingHidden then
                entry.barFrame:SetAlpha(1)
                entry.barFrame._ddingHidden = nil
            end
            if entry.frame and entry.frame._ddingHidden then
                entry.frame:SetAlpha(1)
                entry.frame._ddingHidden = nil
            end
        elseif frame._ddingHidden then
            frame:SetAlpha(1)
            frame._ddingHidden = nil
        end
    end

    -- Hide/show logic (skip in mover/preview mode)
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")

    -- onlyInCombat: 전투 중에만 표시
    local onlyInCombat = settings.onlyInCombat or false
    if onlyInCombat and not inCombat and not isInMoverMode and not isInPreviewMode then
        icon:Hide()
        StopAllAnimations(icon)
        icon._currentAnimation = nil
        return
    end

    local showOnlyWhenInactive = settings.showOnlyWhenInactive or false

    -- 비활성화 시에만 표시 모드
    if showOnlyWhenInactive then
        if hasData and not isInMoverMode and not isInPreviewMode then
            icon:Hide()
            StopAllAnimations(icon)
            icon._currentAnimation = nil
            return
        end
    else
        -- 기존 로직: hideWhenZero + showInCombat
        if hideWhenZero and not hasData and not isInMoverMode and not isInPreviewMode then
            if not (showInCombat and inCombat) then
                icon:Hide()
                StopAllAnimations(icon)
                icon._currentAnimation = nil
                return
            end
        end
    end

    -- Set size (with aspect ratio support) - 스케일 미적용 (핵심능력과 동일)
    local iconWidth = iconSize * iconAspectRatio
    local iconHeight = iconSize
    icon:SetSize(iconWidth, iconHeight)

    -- Set position (개별 아이콘 설정 사용, DDingUI:Scale - v1.1.5.5와 일관성)
    local anchor = _G[iconAttachTo]
    if not anchor then
        anchor = UIParent
    end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", anchor, iconAnchorPoint, DDingUI:Scale(iconOffsetX), DDingUI:Scale(iconOffsetY))

    -- Set icon texture
    local iconTexture
    if iconSource == "custom" and customIconID > 0 then
        -- Custom icon: try spell texture first, then raw texture ID
        iconTexture = C_Spell.GetSpellTexture(customIconID) or customIconID
    else
        -- Use buff icon from tracked buff
        iconTexture = trackedBuff.icon or 134400
    end
    icon.Texture:SetTexture(iconTexture)

    -- Apply zoom (texture crop)
    local zoomVal = iconZoom or 0
    icon.Texture:SetTexCoord(zoomVal, 1 - zoomVal, zoomVal, 1 - zoomVal)

    -- Apply desaturation based on buff status (skip in preview/mover mode)
    if iconDesaturate and not hasData and not isInPreviewMode and not isInMoverMode then
        icon.Texture:SetDesaturated(true)
    else
        icon.Texture:SetDesaturated(false)
    end

    -- Set border with size and color (texture-based)
    if showIconBorder and iconBorderSize > 0 then
        local scaledBorder = DDingUI:ScaleBorder(iconBorderSize)
        UpdateTextureBorderSize(icon.Border, scaledBorder)
        UpdateTextureBorderColor(icon.Border, iconBorderColor[1] or 0, iconBorderColor[2] or 0, iconBorderColor[3] or 0, iconBorderColor[4] or 1)
        ShowTextureBorder(icon.Border, true)
    else
        ShowTextureBorder(icon.Border, false)
    end

    -- Set cooldown swipe (duration display)
    if hasData and auraInstanceID then
        -- [12.0.1] 버프 갱신 시 auraInstanceID 변경 → Clear 후 재설정
        if icon._lastAuraInstanceID ~= auraInstanceID then
            icon.Cooldown:Clear()
        end
        icon._lastAuraInstanceID = auraInstanceID

        -- [12.0.1] pcall 보호: secret value 비교(> 0) 제거, nil 체크만 사용
        pcall(function()
            local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
            if auraData and auraData.duration and auraData.expirationTime then
                icon.Cooldown:SetCooldown(auraData.expirationTime - auraData.duration, auraData.duration)
            else
                icon.Cooldown:Clear()
            end
        end)
    else
        icon.Cooldown:Clear()
        icon._lastAuraInstanceID = nil
    end

    -- Set stack text
    if iconShowStackText and trackedStacks and hasData then
        -- Apply font settings
        local fontPath = iconStackTextFont and LSM:Fetch("font", iconStackTextFont) or STANDARD_TEXT_FONT
        local scaledSize = DDingUI:Scale(iconStackTextSize)
        icon.StackText:SetFont(fontPath, scaledSize, iconStackTextOutline or "OUTLINE")

        -- Apply color
        icon.StackText:SetTextColor(
            iconStackTextColor[1] or 1,
            iconStackTextColor[2] or 1,
            iconStackTextColor[3] or 1,
            iconStackTextColor[4] or 1
        )

        -- Apply position and text alignment based on anchor
        icon.StackText:ClearAllPoints()
        icon.StackText:SetPoint(iconStackTextAnchor, icon, iconStackTextAnchor,
            DDingUI:Scale(iconStackTextOffsetX), DDingUI:Scale(iconStackTextOffsetY))

        -- Set text alignment based on anchor
        if iconStackTextAnchor == "LEFT" or iconStackTextAnchor == "TOPLEFT" or iconStackTextAnchor == "BOTTOMLEFT" then
            icon.StackText:SetJustifyH("LEFT")
        elseif iconStackTextAnchor == "RIGHT" or iconStackTextAnchor == "TOPRIGHT" or iconStackTextAnchor == "BOTTOMRIGHT" then
            icon.StackText:SetJustifyH("RIGHT")
        else
            icon.StackText:SetJustifyH("CENTER")
        end

        -- Preview/Mover mode: show sample stack count
        local displayStacks = trackedStacks
        if not hasData then
            if isInPreviewMode then
                local previewStacks = GetPreviewValues(barIndex, 10, 30, "stacks")
                displayStacks = previewStacks
            elseif isInMoverMode then
                displayStacks = 3  -- Static value for mover
            end
        end
        icon.StackText:SetText(displayStacks)
        icon.StackText:Show()
    else
        icon.StackText:SetText("")
        icon.StackText:Hide()
    end

    -- Handle animation using advanced animation system
    local glowWhenInactive = settings.glowWhenInactive or false

    -- 글로우 조건 결정
    local shouldGlow
    if glowWhenInactive then
        -- 비활성화 시 글로우 (조건 반전)
        shouldGlow = not hasData or (isInPreviewMode or isInMoverMode)
    else
        -- 기존: 활성화 시 글로우
        shouldGlow = hasData or ((isInPreviewMode or isInMoverMode) and not hasData)
    end

    if shouldGlow then
        -- Build glow settings from per-buff settings
        local glowSettings = {
            color = settings.glowColor or {1, 0.9, 0.5, 1},
            lines = settings.glowLines or 8,
            frequency = settings.glowFrequency or 0.25,
            thickness = settings.glowThickness or 2,
            xOffset = settings.glowXOffset or 0,
            yOffset = settings.glowYOffset or 0,
        }

        -- Track previous animation to avoid redundant calls
        if icon._currentAnimation ~= iconAnimation then
            ApplyIconAnimation(icon, iconAnimation, glowSettings)
            icon._currentAnimation = iconAnimation
        end
    else
        -- Stop all animations
        if icon._currentAnimation and icon._currentAnimation ~= "none" then
            StopAllAnimations(icon)
            icon._currentAnimation = nil
        end
    end

    icon:Show()

    if BUFF_TRACKER_DEBUG then
        print(string.format("[BuffTracker] Icon %d (%s): hasData=%s, animation=%s",
            barIndex, trackedBuff.name or "?", tostring(hasData), iconAnimation))
    end
end

-- ============================================================
-- SOUND MODE UPDATE
-- 사운드 모드: 버프 시작/종료/간격에 따라 소리만 재생, 시각적 요소 없음
-- ============================================================
function ResourceBars:UpdateSingleTrackedBuffSound(barIndex, trackedBuff, globalCfg)
    local tracker = GetSoundTracker(barIndex)
    if not tracker then return end

    local settings = trackedBuff.settings or {}
    local cooldownID = trackedBuff.cooldownID or 0

    -- Sound settings
    local soundFile = settings.soundFile or "None"
    local soundChannel = settings.soundChannel or "Master"
    local soundTrigger = settings.soundTrigger or "start"
    local soundStartDelay = settings.soundStartDelay or 0
    local soundEndBefore = settings.soundEndBefore or 3
    local soundInterval = settings.soundInterval or 5

    -- ============================================================
    -- MANUAL TRACKING MODE: Use spell-cast-based stacks instead of aura
    -- ============================================================
    local isManualMode = trackedBuff.trackingMode == "manual"
    local manualStackCount = nil
    if isManualMode then
        manualStackCount = GetManualStacks(barIndex)
    end

    -- Get tracking data
    local CDMScanner = DDingUI.CDMScanner
    local frame = CDMScanner and CDMScanner.FindFrameByCooldownID(cooldownID)

    -- [12.0.1] Taint-safe stacks resolution
    local _, auraInstanceID, unit = ResolveTrackedStacks(cooldownID, frame, isManualMode, manualStackCount)

    -- hasData for auto mode is based on auraInstanceID, for manual mode on stacks > 0
    local hasData
    if isManualMode then
        hasData = (manualStackCount or 0) > 0
    else
        hasData = auraInstanceID ~= nil
    end

    local now = GetTime()

    -- Handle sound triggers
    if soundTrigger == "start" then
        -- Play when buff starts
        if hasData and not tracker.wasActive then
            PlayTrackerSound(soundFile, soundChannel)
            tracker.lastPlayTime = now
        end
    elseif soundTrigger == "startDelay" then
        -- Play X seconds after buff starts
        if hasData and not tracker.wasActive then
            tracker.buffStartTime = now
        end
        if hasData and tracker.buffStartTime then
            local elapsed = now - tracker.buffStartTime
            if elapsed >= soundStartDelay and tracker.lastPlayTime < tracker.buffStartTime + soundStartDelay then
                PlayTrackerSound(soundFile, soundChannel)
                tracker.lastPlayTime = now
            end
        end
    elseif soundTrigger == "end" then
        -- Play when buff ends
        if not hasData and tracker.wasActive then
            PlayTrackerSound(soundFile, soundChannel)
            tracker.lastPlayTime = now
        end
    elseif soundTrigger == "endBefore" then
        -- Play X seconds before buff ends (requires duration tracking)
        if hasData and auraInstanceID then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                if auraData and auraData.expirationTime then
                    local timeLeft = auraData.expirationTime - now
                    if timeLeft > 0 and timeLeft <= soundEndBefore then
                        if now - tracker.lastPlayTime > 1 then  -- Prevent spam
                            PlayTrackerSound(soundFile, soundChannel)
                            tracker.lastPlayTime = now
                        end
                    end
                end
            end)
        end
    elseif soundTrigger == "interval" then
        -- Play every X seconds while buff is active
        if hasData then
            if now - tracker.lastIntervalPlay >= soundInterval then
                PlayTrackerSound(soundFile, soundChannel)
                tracker.lastIntervalPlay = now
            end
        else
            tracker.lastIntervalPlay = 0  -- Reset when buff drops
        end
    end

    tracker.wasActive = hasData

    if BUFF_TRACKER_DEBUG then
        print(string.format("[BuffTracker] Sound %d (%s): hasData=%s, trigger=%s",
            barIndex, trackedBuff.name or "?", tostring(hasData), soundTrigger))
    end
end

-- ============================================================
-- TEXT MODE UPDATE
-- 텍스트 모드: 스택/지속시간/이름을 텍스트로 표시
-- ============================================================
function ResourceBars:UpdateSingleTrackedBuffText(barIndex, trackedBuff, globalCfg)
    local textFrame = GetTrackedBuffText(barIndex)
    if not textFrame then return end

    local settings = trackedBuff.settings or {}
    local cooldownID = trackedBuff.cooldownID or 0

    -- DDingUI:Scale 사용 (픽셀퍼펙트 스케일, v1.1.5.5와 일관성 유지)

    -- Text settings
    local textDisplayMode = settings.textDisplayMode or "stacks"
    local customText = settings.customText or ""
    local textAnchor = settings.textAnchor or "CENTER"
    local textAnchorTo = settings.textAnchorTo or globalCfg.attachTo or "EssentialCooldownViewer"
    local textAnchorPoint = settings.textAnchorPoint or "CENTER"
    local textOffsetX = settings.textModeOffsetX or 0
    local textOffsetY = settings.textModeOffsetY or 50
    local textSize = settings.textModeSize or 24
    local textFont = settings.textModeFont
    local textColor = settings.textModeColor or { 1, 1, 1, 1 }
    local textOutline = settings.textModeOutline or "OUTLINE"
    local showIcon = settings.textShowIcon ~= false
    local iconSize = settings.textIconSize or 24
    local hideWhenZero = settings.hideWhenZero
    if hideWhenZero == nil then hideWhenZero = true end
    local showInCombat = settings.showInCombat or false
    local hideFromCDM = settings.hideFromCDM or false
    local durationDecimals = settings.durationDecimals or 1  -- 소수점 자릿수

    -- Per-buff frame strata (개별 설정 > 전체 설정 > 기본값)
    textFrame:SetFrameStrata(settings.frameStrata or globalCfg.frameStrata or "MEDIUM")

    -- ============================================================
    -- MANUAL TRACKING MODE: Use spell-cast-based stacks instead of aura
    -- ============================================================
    local isManualMode = trackedBuff.trackingMode == "manual"
    local manualStackCount = nil
    if isManualMode then
        manualStackCount = GetManualStacks(barIndex)
    end

    -- Get tracking data
    local CDMScanner = DDingUI.CDMScanner
    local frame = CDMScanner and CDMScanner.FindFrameByCooldownID(cooldownID)

    -- [12.0.1] Taint-safe stacks resolution (CDMScanner FontString > API > fallback)
    local trackedStacks, auraInstanceID, unit = ResolveTrackedStacks(cooldownID, frame, isManualMode, manualStackCount)

    -- hasData for auto mode is based on auraInstanceID, for manual mode on stacks > 0
    local hasData
    if isManualMode then
        hasData = (manualStackCount or 0) > 0
    else
        hasData = auraInstanceID ~= nil
    end

    -- ============================================================
    -- ALERT SYSTEM: 트리거 평가 + 액션 실행
    -- ============================================================
    -- [12.0.1] alert 비교 전에 Text에 stacks를 미리 기록
    -- [12.0.1] 알림 평가 (plain 캐싱 → secret 시 캐시 사용)
    local alertResult = EvaluateAlerts(trackedBuff, trackedStacks, hasData, auraInstanceID, unit)
    if alertResult then
        ApplyAlertActions(alertResult, trackedBuff, textFrame)
        if textFrame._alertColorOverride then
            textColor = textFrame._alertColorOverride
        end
    else
        textFrame._alertColorOverride = nil
    end

    -- CDM에서 숨기기 (추적 중인 버프를 CDM에서 숨김 - 중복 방지)
    if hideFromCDM and frame then
        local entry = CDMScanner and CDMScanner.GetEntry(cooldownID)
        if entry then
            if entry.iconFrame then
                entry.iconFrame:SetAlpha(0)
                entry.iconFrame._ddingHidden = true
            end
            if entry.barFrame then
                entry.barFrame:SetAlpha(0)
                entry.barFrame._ddingHidden = true
            end
            if entry.frame and not entry.iconFrame and not entry.barFrame then
                entry.frame:SetAlpha(0)
                entry.frame._ddingHidden = true
            end
        else
            frame:SetAlpha(0)
            frame._ddingHidden = true
        end
    elseif frame then
        local entry = CDMScanner and CDMScanner.GetEntry(cooldownID)
        if entry then
            if entry.iconFrame and entry.iconFrame._ddingHidden then
                entry.iconFrame:SetAlpha(1)
                entry.iconFrame._ddingHidden = nil
            end
            if entry.barFrame and entry.barFrame._ddingHidden then
                entry.barFrame:SetAlpha(1)
                entry.barFrame._ddingHidden = nil
            end
            if entry.frame and entry.frame._ddingHidden then
                entry.frame:SetAlpha(1)
                entry.frame._ddingHidden = nil
            end
        elseif frame._ddingHidden then
            frame:SetAlpha(1)
            frame._ddingHidden = nil
        end
    end

    -- onlyInCombat: 전투 중에만 표시
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    local onlyInCombat = settings.onlyInCombat or false
    if onlyInCombat and not inCombat and not isInMoverMode and not isInPreviewMode then
        textFrame:Hide()
        return
    end

    -- Hide if no data and hideWhenZero (skip in mover/preview mode)
    -- Also skip hiding if showInCombat is enabled and we're in combat
    if hideWhenZero and not hasData and not isInMoverMode and not isInPreviewMode then
        if not (showInCombat and inCombat) then
            textFrame:Hide()
            return
        end
    end

    -- Set position (DDingUI:Scale - v1.1.5.5와 일관성)
    local anchor = _G[textAnchorTo]
    if not anchor then
        anchor = UIParent
    end
    textFrame:ClearAllPoints()
    textFrame:SetPoint(textAnchor, anchor, textAnchorPoint, DDingUI:Scale(textOffsetX), DDingUI:Scale(textOffsetY))

    -- Set font
    local fontPath = textFont and LSM:Fetch("font", textFont) or STANDARD_TEXT_FONT
    textFrame.Text:SetFont(fontPath, DDingUI:Scale(textSize), textOutline)
    textFrame.Text:SetTextColor(textColor[1] or 1, textColor[2] or 1, textColor[3] or 1, textColor[4] or 1)

    -- Set icon
    if showIcon then
        local scaledIconSize = DDingUI:Scale(iconSize)
        textFrame.Icon:SetSize(scaledIconSize, scaledIconSize)
        textFrame.Icon:SetTexture(trackedBuff.icon or 134400)
        textFrame.Icon:Show()
        textFrame.Text:SetPoint("LEFT", textFrame.Icon, "RIGHT", 4, 0)
    else
        textFrame.Icon:Hide()
        textFrame.Text:SetPoint("LEFT", textFrame, "LEFT", 0, 0)
    end

    -- Set text based on display mode
    local displayText = ""
    if textDisplayMode == "stacks" then
        if hasData then
            displayText = trackedStacks  -- Secret value 직접 전달
        elseif isInPreviewMode then
            local previewStacks = GetPreviewValues(barIndex, 10, 30, "stacks")
            displayText = tostring(previewStacks)
        elseif isInMoverMode then
            displayText = "3"  -- Static value for mover
        else
            displayText = "0"
        end
    elseif textDisplayMode == "duration" then
        if hasData and auraInstanceID then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                if auraData and auraData.expirationTime then
                    local timeLeft = auraData.expirationTime - GetTime()
                    if timeLeft > 0 then
                        displayText = string.format("%." .. durationDecimals .. "f", timeLeft)
                    else
                        displayText = "0"
                    end
                end
            end)
        elseif isInPreviewMode then
            local _, previewDuration = GetPreviewValues(barIndex, 10, 30, "duration")
            displayText = string.format("%." .. durationDecimals .. "f", previewDuration)
        elseif isInMoverMode then
            displayText = string.format("%." .. durationDecimals .. "f", 18.0)
        end
    elseif textDisplayMode == "name" then
        displayText = trackedBuff.name or "Unknown"
    elseif textDisplayMode == "custom" then
        displayText = customText
    end

    textFrame.Text:SetText(displayText)
    textFrame:Show()

    -- Apply animation if enabled and buff is active
    local textAnimation = settings.textAnimation or "none"
    if hasData and textAnimation ~= "none" then
        -- Build glow settings from per-buff settings
        local glowSettings = {
            color = settings.textGlowColor or {1, 1, 0.3, 1},
            lines = settings.textGlowLines or 8,
            frequency = settings.textGlowFrequency or 0.25,
            thickness = settings.textGlowThickness or 2,
            xOffset = settings.textGlowXOffset or 0,
            yOffset = settings.textGlowYOffset or 0,
        }

        -- Track previous animation to avoid redundant calls
        if textFrame._currentAnimation ~= textAnimation then
            ApplyTextAnimation(textFrame, textAnimation, glowSettings)
            textFrame._currentAnimation = textAnimation
        end
    else
        -- Stop animations when buff is not active
        if textFrame._currentAnimation and textFrame._currentAnimation ~= "none" then
            StopTextAnimations(textFrame)
            textFrame._currentAnimation = nil
        end
    end

    if BUFF_TRACKER_DEBUG then
        print(string.format("[BuffTracker] Text %d (%s): hasData=%s, mode=%s",
            barIndex, trackedBuff.name or "?", tostring(hasData), textDisplayMode))
    end
end

-- Initialize buff tracker
function ResourceBars:InitializeBuffTracker()
    local rootCfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
    if rootCfg and rootCfg.enabled then
        StartBuffTrackerTicker()
    end

    -- Initial update (여러 번)
    local initDelays = { 0.1, 0.5, 1.0, 2.0 }
    for _, delay in ipairs(initDelays) do
        C_Timer.After(delay, function()
            ResourceBars:UpdateBuffTrackerBar()
        end)
    end

    -- PLAYER_ENTERING_WORLD 이벤트 등록 (리로드/존 이동 후 버프 트래커 갱신)
    local buffTrackerInitFrame = CreateFrame("Frame")
    local pendingInitTimers = {}
    buffTrackerInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    buffTrackerInitFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    buffTrackerInitFrame:SetScript("OnEvent", function(self, event, ...)
        -- 이전 타이머 취소 (이벤트 연속 발생 시 중복 방지)
        for i = 1, #pendingInitTimers do
            if pendingInitTimers[i] then
                pendingInitTimers[i]:Cancel()
            end
        end
        wipe(pendingInitTimers)

        -- CDM 초기화 대기: 0.5초 후 1회 + 2초 후 1회 (5개 → 2개로 축소)
        local delays = { 0.5, 2.0 }
        for _, delay in ipairs(delays) do
            pendingInitTimers[#pendingInitTimers + 1] = C_Timer.NewTimer(delay, function()
                local cfg = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar
                if cfg and cfg.enabled then
                    if not buffTrackerTicker then
                        StartBuffTrackerTicker()
                    end
                    ResourceBars:UpdateBuffTrackerBar()
                end
            end)
        end
    end)
end

-- Enter mover mode for tracked buff bars (shows all bars regardless of hideWhenZero)
function ResourceBars:EnterMoverMode()
    isInMoverMode = true
    moverPositionSynced = false  -- 초기 진입 시 최신 설정으로 위치 동기화 허용
    -- Force update to show all bars with proper layout + position sync
    self:UpdateBuffTrackerBar()
    moverPositionSynced = true  -- 이후 드래그 중 위치 업데이트 건너뛰기
end

-- Exit mover mode for tracked buff bars
function ResourceBars:ExitMoverMode()
    isInMoverMode = false
    moverPositionSynced = false
    -- Force update to apply normal hideWhenZero behavior
    self:UpdateBuffTrackerBar()
end

-- Legacy function name for compatibility
function ResourceBars:InitializeTrackedBuffBarsForMover()
    self:EnterMoverMode()
end

-- Preview mode for options panel (shows all bars/icons/text with sample values)
function ResourceBars:EnablePreviewMode()
    isInPreviewMode = true
    -- Start preview animation ticker
    StartPreviewTicker()
    -- Force update to show all bars with proper layout
    self:UpdateBuffTrackerBar()
end

function ResourceBars:DisablePreviewMode()
    isInPreviewMode = false
    -- Stop preview animation ticker
    StopPreviewTicker()
    -- 프리뷰 상태 정리 (메모리 해제)
    wipe(previewState)
    -- Force update to apply normal hideWhenZero behavior
    self:UpdateBuffTrackerBar()
end

function ResourceBars:TogglePreviewMode()
    if isInPreviewMode then
        self:DisablePreviewMode()
    else
        self:EnablePreviewMode()
    end
    return isInPreviewMode
end

function ResourceBars:IsPreviewModeEnabled()
    return isInPreviewMode
end

-- Expose to main addon
DDingUI.GetBuffTrackerBar = function(self) return ResourceBars:GetBuffTrackerBar() end
DDingUI.UpdateBuffTrackerBar = function(self) return ResourceBars:UpdateBuffTrackerBar() end
DDingUI.GetTrackedBuffBars = function(self) return barFrames end  -- Multi-bar access for debugging
DDingUI.GetTrackedBuffIcons = function(self) return iconFrames end  -- Multi-icon access for debugging
DDingUI.GetTrackedBuffTexts = function(self) return textFrames end  -- Multi-text access for debugging
DDingUI.GetSoundTrackers = function(self) return soundTrackers end  -- Sound tracker access for debugging
DDingUI.InitializeTrackedBuffBarsForMover = function(self) return ResourceBars:InitializeTrackedBuffBarsForMover() end
DDingUI.ExitBuffTrackerMoverMode = function(self) return ResourceBars:ExitMoverMode() end
DDingUI.EnableBuffTrackerPreview = function(self) return ResourceBars:EnablePreviewMode() end
DDingUI.DisableBuffTrackerPreview = function(self) return ResourceBars:DisablePreviewMode() end
DDingUI.ToggleBuffTrackerPreview = function(self) return ResourceBars:TogglePreviewMode() end
DDingUI.IsBuffTrackerPreviewEnabled = function(self) return ResourceBars:IsPreviewModeEnabled() end

-- Debug command
SLASH_DDINGBUFF1 = "/ddingbuff"
SlashCmdList["DDINGBUFF"] = function(msg)
    local cdID = tonumber(msg)
    if cdID then
        -- Test specific cooldownID
        print("|cff00ccff[DDingUI BuffTracker]|r Testing cdID: " .. cdID)

        -- 1. CDMScanner에서 frame 찾기
        local CDMScanner = DDingUI.CDMScanner
        local frame = CDMScanner and CDMScanner.FindFrameByCooldownID(cdID)
        if frame then
            print("  auraInstanceID=" .. tostring(frame.auraInstanceID))
            print("  auraDataUnit=" .. tostring(frame.auraDataUnit))
            print("  auraData 있음 (applications는 secret value라 출력 불가)")
        else
            print("  frame 없음 - /ddingcdm scan 필요")
        end
    else
        BUFF_TRACKER_DEBUG = not BUFF_TRACKER_DEBUG
        print("|cff00ccff[DDingUI BuffTracker]|r Debug: " .. (BUFF_TRACKER_DEBUG and "ON" or "OFF"))
    end
end

-- Scan available buffs command (CDM API)
SLASH_BTSCAN1 = "/btscan"
SlashCmdList["BTSCAN"] = function(msg)
    print("|cff00ccff[DDingUI BuffTracker]|r Scanning available buffs...")

    local buffs = DDingUI.ScanAvailableBuffs()
    if not buffs or #buffs == 0 then
        print("|cffff9900  No buffs found. Make sure CDM Buff Viewer is visible.|r")
        return
    end

    print("|cff00ff00  Found " .. #buffs .. " available buffs:|r")
    for i, buff in ipairs(buffs) do
        local chargeStr = buff.hasCharges and (" [Charges: " .. buff.maxCharges .. "]") or ""
        print(string.format("    %d. |cffffffff%s|r (cdID:%d, spellID:%d)%s [%s]",
            i, buff.spellName or "Unknown", buff.cooldownID, buff.spellID or 0, chargeStr, buff.source))
    end
    print("|cff00ccff  Use cooldownID to add buffs to Buff Tracker.|r")
end

-- Reset tracked buffs command
SLASH_BTRESET1 = "/btreset"
SlashCmdList["BTRESET"] = function(msg)
    if not DDingUI.db then
        print("|cffff0000[DDingUI]|r BuffTracker config not found!")
        return
    end

    -- db.profile.buffTrackerBar.trackedBuffsPerSpec 사용 (프로필별)
    local rootCfg = DDingUI.db.profile and DDingUI.db.profile.buffTrackerBar

    if msg == "all" then
        -- Reset all tracked buffs (profile + legacy)
        if rootCfg then
            rootCfg.trackedBuffsPerSpec = {}
            rootCfg.trackedBuffs = {}
            rootCfg._migratedSpecs = {}
            if rootCfg.specs then
                for specID, specCfg in pairs(rootCfg.specs) do
                    if type(specCfg) == "table" then
                        specCfg.trackedBuffs = {}
                    end
                end
            end
        end
        -- Also clean up any remaining global data
        if DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec then
            DDingUI.db.global.trackedBuffsPerSpec = nil
        end
        print("|cff00ff00[DDingUI]|r All tracked buffs cleared!")
    elseif msg == "spec" or msg == "" then
        -- Reset current spec's tracked buffs only
        local specID = GetCurrentSpecID()
        if specID and rootCfg and rootCfg.trackedBuffsPerSpec then
            rootCfg.trackedBuffsPerSpec[specID] = {}
            print("|cff00ff00[DDingUI]|r Current spec (ID: " .. specID .. ") tracked buffs cleared!")
        else
            print("|cffff0000[DDingUI]|r Could not determine current spec!")
        end
    elseif msg == "legacy" then
        -- Clean up old per-spec data (now using SpecProfiles system)
        local cleaned = 0
        if rootCfg.specs then
            for specID, _ in pairs(rootCfg.specs) do
                rootCfg.specs[specID] = nil
                cleaned = cleaned + 1
            end
        end
        rootCfg.usePerSpec = false
        print("|cff00ff00[DDingUI]|r Cleaned " .. cleaned .. " legacy spec entries! (Now using SpecProfiles system)")
    elseif msg == "help" then
        print("|cffffcc00[DDingUI BuffTracker Reset]|r")
        print("  /btreset         - Clear current spec's tracked buffs")
        print("  /btreset spec    - Clear current spec's tracked buffs")
        print("  /btreset all     - Clear ALL specs' tracked buffs")
        print("  /btreset legacy  - Clean up old per-spec data")
    else
        print("|cffffcc00[DDingUI BuffTracker Reset]|r")
        print("  /btreset         - Clear current spec's tracked buffs")
        print("  /btreset spec    - Clear current spec's tracked buffs")
        print("  /btreset all     - Clear ALL specs' tracked buffs")
        print("  /btreset legacy  - Clean up old per-spec data")
    end

    -- Hide all bars and icons
    HideAllTrackedBuffBars()
    HideAllTrackedBuffIcons()

    -- Refresh
    ResourceBars:UpdateBuffTrackerBar()

    -- Notify AceConfig
    local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange(ADDON_NAME)
    end
end
