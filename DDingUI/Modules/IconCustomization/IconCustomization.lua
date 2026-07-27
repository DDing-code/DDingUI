local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local LSM = LibStub("LibSharedMedia-3.0", true)
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]

DDingUI.IconCustomization = DDingUI.IconCustomization or {}
local IconCustomization = DDingUI.IconCustomization

-- IMPORTANT: Use weak table to store DDingUI data instead of adding fields to Blizzard frames
-- This prevents taint propagation that causes secret value errors in WoW 12.0+
local FrameData = setmetatable({}, { __mode = "k" })  -- weak keys

local function GetFrameData(frame)
    if not frame then return nil end
    if not FrameData[frame] then
        FrameData[frame] = {}
    end
    return FrameData[frame]
end

local function IsHooked(frame, hookName)
    local data = FrameData[frame]
    return data and data[hookName]
end

local function SetHooked(frame, hookName)
    GetFrameData(frame)[hookName] = true
end

-- Lazy-loaded GUI components (DDingUI.GUI is exported after this file loads)
local Widgets, THEME
local function EnsureGUILoaded()
    if not Widgets and DDingUI.GUI then
        Widgets = DDingUI.GUI.Widgets
        THEME = DDingUI.GUI.THEME
    end
    return Widgets and THEME
end

-- GlowEffects are provided by SL (DDingUI_StyleLib) already loaded at line 4

-- Cached GetChildren helper to avoid repeated O(n) traversal
-- Uses FrameData to avoid tainting Blizzard frames
local function GetCachedChildren(container, ttl)
    if not container or not container.GetChildren then return {} end
    ttl = ttl or 0.1
    local now = GetTime()
    local data = GetFrameData(container)
    if data.cachedChildren and data.cachedChildrenTime and
       (now - data.cachedChildrenTime) < ttl then
        return data.cachedChildren
    end
    data.cachedChildren = { container:GetChildren() }
    data.cachedChildrenTime = now
    return data.cachedChildren
end

-- Helper to refresh the DDingUI custom GUI (soft refresh to avoid flash)
local function RefreshGUI()
    local configFrame = _G["DDingUI_ConfigFrame"]
    if configFrame and configFrame.SoftRefresh then
        configFrame:SoftRefresh()
    elseif configFrame and configFrame.FullRefresh then
        configFrame:FullRefresh()
    end
end

-- Style font string helper (matches GUI.lua style - no outline)
local function StyleFontString(fontString)
    if not fontString then return end
    local globalFontPath = DDingUI:GetGlobalFont()
    local currentFont, size, flags = fontString:GetFont()
    size = size or 12
    -- 그림자 없이 깔끔하게 (ElvUI 스타일)
    flags = ""
    if globalFontPath then
        fontString:SetFont(globalFontPath, size, flags)
    elseif currentFont and size then
        fontString:SetFont(currentFont, size, flags)
    end
    -- 그림자 완전 제거
    fontString:SetShadowOffset(0, 0)
    fontString:SetShadowColor(0, 0, 0, 0)
end

-- Create backdrop helper
local function CreateBackdrop(frame, bgColor, borderColor)
    if not frame.SetBackdrop then
        if Mixin and BackdropTemplateMixin then
            Mixin(frame, BackdropTemplateMixin)
        else
            return
        end
    end
    local backdrop = {
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
    frame:SetBackdrop(backdrop)
    if bgColor then
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end
    if borderColor then
        frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    end
end

-- Helper function to get spell ID from an icon frame
local function GetSpellIDFromIcon(iconFrame)
    if not iconFrame then return nil end
    
    local spellID = nil
    pcall(function()
        -- Try cooldownInfo first (Blizzard's cooldown manager format)
        if iconFrame.cooldownInfo then
            spellID = iconFrame.cooldownInfo.overrideSpellID or iconFrame.cooldownInfo.spellID
        end
        -- Fallback to other common properties
        if not spellID then
            spellID = iconFrame.spellID or iconFrame.SpellID
        end
        if not spellID and iconFrame.GetSpellID then
            spellID = iconFrame:GetSpellID()
        end
        if not spellID and iconFrame.GetSpellId then
            spellID = iconFrame:GetSpellId()
        end
    end)
    if issecretvalue and issecretvalue(spellID) then
        return nil
    end
    return spellID
end

-- Detect viewer type for an icon frame (returns "Buff", "Essential", "Utility", or nil)
-- [REPARENT] UIParent reparent 후 GetParent() 체인 워킹 불가 → 다중 fallback 전략
local function GetViewerType(iconFrame)
    if not iconFrame then return nil end

    local VIEWER_TYPE_MAP = {
        ["EssentialCooldownViewer"] = "Essential",
        ["UtilityCooldownViewer"]   = "Utility",
        ["BuffIconCooldownViewer"]  = "Buff",
    }

    -- 방법 1: FrameController iconSourceMap (가장 신뢰 — reparent 무관)
    local cooldownID = iconFrame.cooldownID
    if issecretvalue and issecretvalue(cooldownID) then
        cooldownID = nil
    end
    if cooldownID then
        local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
        if fc and fc.GetIconSource then
            local sourceName = fc:GetIconSource(cooldownID)
            if sourceName and VIEWER_TYPE_MAP[sourceName] then
                return VIEWER_TYPE_MAP[sourceName]
            end
        end
    end

    -- 방법 2: _ddContainerRef → 그룹 이름 → 뷰어 타입 역추적
    local containerRef = iconFrame._ddContainerRef
    if containerRef and containerRef._groupName then
        local GROUP_VIEWER = {
            ["Cooldowns"] = "EssentialCooldownViewer",
            ["Buffs"]     = "BuffIconCooldownViewer",
            ["Utility"]   = "UtilityCooldownViewer",
        }
        local viewerName = GROUP_VIEWER[containerRef._groupName]
        if viewerName and VIEWER_TYPE_MAP[viewerName] then
            return VIEWER_TYPE_MAP[viewerName]
        end
    end

    -- 방법 3: _ddSourceViewer 태그 (GroupRenderer가 설정)
    if iconFrame._ddSourceViewer and VIEWER_TYPE_MAP[iconFrame._ddSourceViewer] then
        return VIEWER_TYPE_MAP[iconFrame._ddSourceViewer]
    end

    -- 방법 4: 직접 parent 비교 (reparent 전 or 미관리 아이콘)
    local parent = iconFrame:GetParent()
    if parent then
        for viewerName, viewerType in pairs(VIEWER_TYPE_MAP) do
            local viewer = _G[viewerName]
            if viewer and (parent == viewer or parent == (viewer.viewerFrame or viewer)) then
                return viewerType
            end
        end
    end

    return nil
end

-- Check if buff is active (SECRET-SAFE - no spellID needed!)
-- For BuffIconCooldownViewer: icon is shown = buff is active
-- This avoids secret value issues during combat
local function IsBuffActiveForIcon(iconFrame)
    if not iconFrame then return false end
    -- BuffIconCooldownViewer only shows icons when buff is active
    -- So IsShown() directly tells us the buff state!
    local ok, shown = pcall(iconFrame.IsShown, iconFrame)
    return ok and shown == true
end

-- Scan viewers for icons and collect spell data
local function ScanViewerIcons(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return {} end

    local icons = {}
    local spellMap = {} -- Track unique spells by ID

    -- [REPARENT] itemFramePool:EnumerateActive()는 parent 무관하게 동작
    -- UIParent reparent 후 GetChildren()은 빈 결과 반환 → pool 방식으로 전환
    if viewer.itemFramePool then
        for child in viewer.itemFramePool:EnumerateActive() do
            if child and child.cooldownID then
                local spellID = GetSpellIDFromIcon(child)
                if spellID and not spellMap[spellID] then
                    spellMap[spellID] = true

                    local ok, spellInfo = pcall(C_Spell.GetSpellInfo, spellID)
                    if ok and spellInfo then
                        table.insert(icons, {
                            spellID = spellID,
                            spellName = spellInfo.name or "Unknown",
                            iconTexture = spellInfo.iconID or C_Spell.GetSpellTexture(spellID),
                            viewerName = viewerName,
                        })
                    end
                end
            end
        end
    end

    return icons
end

-- Get all icons from all viewers
local function ScanAllViewerIcons()
    local viewers = DDingUI.viewers or {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
    }
    
    local categorizedIcons = {
        Essential = {},
        Utility = {},
        Buff = {},
    }
    
    for _, viewerName in ipairs(viewers) do
        local icons = ScanViewerIcons(viewerName)
        if viewerName == "EssentialCooldownViewer" then
            categorizedIcons.Essential = icons
        elseif viewerName == "UtilityCooldownViewer" then
            categorizedIcons.Utility = icons
        elseif viewerName == "BuffIconCooldownViewer" then
            categorizedIcons.Buff = icons
        end
    end
    
    return categorizedIcons
end

-- Get customization settings for a spell
-- viewerType: "Essential"/"Utility"/"Buff" — 뷰어별 독립 커스터마이징
local function GetSpellCustomization(spellID, viewerType)
    local profile = DDingUI.db and DDingUI.db.profile
    local db = profile and profile.iconCustomization or {}
    db.spells = db.spells or {}
    if viewerType then
        local compositeKey = tostring(spellID) .. "_" .. viewerType
        if db.spells[compositeKey] then
            return db.spells[compositeKey]
        end
    end
    -- fallback: 범용 키 (기존 데이터 호환)
    return db.spells[tostring(spellID)] or {}
end

function IconCustomization:GetSpellSettings(spellID, viewerType)
    if issecretvalue and issecretvalue(spellID) then return nil end
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return nil end
    return GetSpellCustomization(spellID, viewerType)
end

-- Check if a spell is customized
local function IsSpellCustomized(spellID, viewerType)
    local custom = GetSpellCustomization(spellID, viewerType)
    return type(custom) == "table" and next(custom) ~= nil
end

local function ResolveIconCustomization(icon)
    local spellID = GetSpellIDFromIcon(icon)
    if issecretvalue and issecretvalue(spellID) then return nil end
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return nil end

    local viewerType
    local sourceViewer = icon and icon._ddSourceViewer
    if sourceViewer == "EssentialCooldownViewer" then
        viewerType = "Essential"
    elseif sourceViewer == "UtilityCooldownViewer" then
        viewerType = "Utility"
    elseif sourceViewer == "BuffIconCooldownViewer" then
        viewerType = "Buff"
    elseif not InCombatLockdown() then
        viewerType = GetViewerType(icon)
    end
    if not viewerType then return nil end
    return GetSpellCustomization(spellID, viewerType)
end

do
    local formatterCache = {}
    local formatterCount = 0
    local formatterUnavailable = false
    local attachedFormatters = setmetatable({}, { __mode = "k" })

    local function BuildThresholdFormatter(seconds, decimals, useColor, r, g, b)
        if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
            and Enum and Enum.NumericRuleFormatRounding and CreateColor)
        then
            return nil
        end

        local roundingUp = Enum.NumericRuleFormatRounding.Up
        local roundingNearest = Enum.NumericRuleFormatRounding.Nearest
        local function Colorize(format)
            if not useColor then return format end
            return CreateColor(r, g, b, 1):WrapTextInColorCode(format)
        end

        local breakpoints = {}
        if decimals then
            breakpoints[#breakpoints + 1] = {
                threshold = 0,
                format = Colorize("%.1f"),
                rounding = roundingNearest,
            }
        else
            breakpoints[#breakpoints + 1] = {
                threshold = 0,
                format = Colorize("%d"),
                rounding = roundingUp,
                step = 1,
            }
        end
        breakpoints[#breakpoints + 1] = {
            threshold = seconds,
            format = "%d",
            rounding = roundingUp,
            step = 1,
        }
        breakpoints[#breakpoints + 1] = {
            threshold = 59.0001,
            format = "%d:%02d",
            rounding = roundingUp,
            step = 1,
            components = { { div = 60 }, { mod = 60 } },
        }
        breakpoints[#breakpoints + 1] = {
            threshold = 3599.0001,
            format = "%dh",
            rounding = roundingUp,
            step = 1,
            components = { { div = 3600 } },
        }
        breakpoints[#breakpoints + 1] = {
            threshold = 86399.0001,
            format = "%dd",
            rounding = roundingUp,
            step = 1,
            components = { { div = 86400 } },
        }

        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        local ok = pcall(formatter.SetBreakpoints, formatter, breakpoints)
        return ok and formatter or nil
    end

    local function GetThresholdFormatter(settings)
        if not settings then return nil end
        local seconds = tonumber(settings.thresholdSeconds) or 0
        if seconds <= 0 then return nil end
        seconds = math.min(59, math.floor(seconds + 0.5))

        local decimals = settings.thresholdDecimals == true
        local useColor = settings.thresholdColorEnabled == true
        if not decimals and not useColor then return nil end

        local color = settings.thresholdColor or {}
        local r = color.r or color[1] or 1
        local g = color.g or color[2] or 0.2
        local b = color.b or color[3] or 0.2
        local signature = string.format(
            "%d|%d|%d|%.3f|%.3f|%.3f",
            seconds,
            decimals and 1 or 0,
            useColor and 1 or 0,
            r,
            g,
            b
        )

        local formatter = formatterCache[signature]
        if formatter == nil and not formatterUnavailable then
            if formatterCount >= 64 then
                formatterCache = {}
                formatterCount = 0
            end
            formatter = BuildThresholdFormatter(seconds, decimals, useColor, r, g, b)
            if formatter then
                formatterCache[signature] = formatter
                formatterCount = formatterCount + 1
            else
                formatterUnavailable = true
            end
        end
        return formatter
    end

    function IconCustomization:ApplyThresholdFormatter(cooldown, settings)
        if not (cooldown and cooldown.SetCountdownFormatter) then return end
        local formatter = GetThresholdFormatter(settings)
        if formatter then
            if attachedFormatters[cooldown] ~= formatter then
                attachedFormatters[cooldown] = formatter
                cooldown:SetCountdownFormatter(formatter)
            end
        elseif attachedFormatters[cooldown] then
            attachedFormatters[cooldown] = nil
            cooldown:SetCountdownFormatter(nil)
        end
    end
end

local function GetPlayerClassColor()
    local _, class = UnitClass("player")
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then
        return { color.r or 1, color.g or 1, color.b or 1, 0.8 }
    end
    return { 1, 0.776, 0.376, 0.8 }
end

local function NormalizeColor(color, fallback)
    fallback = fallback or { 1, 0.776, 0.376, 0.8 }
    if type(color) ~= "table" then
        return { fallback[1], fallback[2], fallback[3], fallback[4] }
    end
    return {
        color.r or color[1] or fallback[1],
        color.g or color[2] or fallback[2],
        color.b or color[3] or fallback[3],
        color.a or color[4] or fallback[4],
    }
end

local function ResolveActiveSwipeColor(custom)
    if custom.activeSwipeMode == "class" then
        return GetPlayerClassColor()
    end
    if custom.activeSwipeMode == "custom" then
        return NormalizeColor(custom.activeSwipeColor)
    end
    return nil
end

local function BuildEffectiveSkinSettings(icon, settings)
    local custom = ResolveIconCustomization(icon)
    if not custom then return settings end
    local activeStateMode = custom.activeStateMode
    local activeSwipeMode = custom.activeSwipeMode
    local cooldownSwipeMode = custom.cooldownSwipeMode
    local cooldownEdgeMode = custom.cooldownEdgeMode
    local cooldownFinishMode = custom.cooldownFinishMode
    local activeDurationMode = custom.activeDurationMode
    if activeStateMode == nil and activeSwipeMode == nil and cooldownSwipeMode == nil
        and cooldownEdgeMode == nil and cooldownFinishMode == nil
        and activeDurationMode == nil
    then
        return settings
    end

    local effective = {}
    for key, value in pairs(settings or {}) do
        effective[key] = value
    end

    if activeSwipeMode == "hidden" or activeStateMode == "hide" then
        effective.hideActiveState = true
    elseif activeSwipeMode == "class" or activeSwipeMode == "custom" then
        effective.hideActiveState = false
        effective.auraSwipeColor = ResolveActiveSwipeColor(custom)
    elseif activeStateMode == "show" then
        effective.hideActiveState = false
    end

    if cooldownSwipeMode == "normal" then
        effective.disableSwipeAnimation = false
        effective.swipeReverse = false
    elseif cooldownSwipeMode == "reverse" then
        effective.disableSwipeAnimation = false
        effective.swipeReverse = true
    elseif cooldownSwipeMode == "hidden" then
        effective.disableSwipeAnimation = true
    end

    if cooldownEdgeMode == "show" then
        effective.disableEdgeGlow = false
    elseif cooldownEdgeMode == "hide" then
        effective.disableEdgeGlow = true
    end

    if cooldownFinishMode == "show" then
        effective.disableBlingAnimation = false
    elseif cooldownFinishMode == "hide" then
        effective.disableBlingAnimation = true
    end

    if activeDurationMode == "show" then
        effective.hideDurationText = false
    elseif activeDurationMode == "hide" then
        effective.hideDurationText = true
    end

    effective._ddIconCooldownSwipeMode = cooldownSwipeMode
    effective._ddIconCooldownEdgeMode = cooldownEdgeMode
    effective._ddIconCooldownFinishMode = cooldownFinishMode
    return effective
end

local function ApplyExplicitSkinVisibility(icon, settings)
    local cooldown = icon and icon.Cooldown
    if not cooldown or not settings then return end

    local data = GetFrameData(icon)
    local swipeMode = settings._ddIconCooldownSwipeMode
    if cooldown.SetDrawSwipe
        and ((swipeMode == "normal" or swipeMode == "reverse")
            or (data.iconCooldownSwipeMode and not swipeMode and settings.disableSwipeAnimation ~= true))
    then
        cooldown:SetDrawSwipe(true)
    end
    local edgeMode = settings._ddIconCooldownEdgeMode
    if cooldown.SetDrawEdge
        and (edgeMode == "show"
            or (data.iconCooldownEdgeMode and not edgeMode and settings.disableEdgeGlow ~= true))
    then
        cooldown:SetDrawEdge(true)
    end
    local finishMode = settings._ddIconCooldownFinishMode
    if cooldown.SetDrawBling
        and (finishMode == "show"
            or (data.iconCooldownFinishMode and not finishMode and settings.disableBlingAnimation ~= true))
    then
        cooldown:SetDrawBling(true)
    end
    data.iconCooldownSwipeMode = swipeMode
    data.iconCooldownEdgeMode = edgeMode
    data.iconCooldownFinishMode = finishMode
end

-- UI state
local uiState = {
    selectedSpellID = nil,
    selectedKey = nil,         -- spellID_viewerType (뷰어 구분 하이라이트용)
    selectedViewerType = nil,  -- "Essential"/"Utility"/"Buff" (DB 복합키용)
    scannedIcons = {},
}

-- Track hooked frames for event-driven updates
local hookedFrames = {} -- [iconFrame] = true


-- READY STATE GLOW FUNCTIONS

-- Stop all glow effects on a frame
local function StopAllGlows(frame, key)
    if not frame then return end
    local glowKey = key or "DDingUI_ReadyGlow"
    pcall(SL.HidePixelGlow, frame, glowKey)
    pcall(SL.HideAutocastGlow, frame, glowKey)
    pcall(SL.HideButtonGlow, frame, glowKey)
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then pcall(LCG.ProcGlow_Stop, frame, glowKey) end
end

local function NeedsRuntimeHook(custom)
    if type(custom) ~= "table" then return false end
    return custom.readyGlow == true
        or custom.activeGlow == true
        or custom.maxChargesGlow == true
        or custom.cooldownReadyGlow == true
        or custom.nonActiveMode ~= nil
        or custom.cooldownStateEffect ~= nil
        or custom.chargeCountMode ~= nil
        or custom.chargeHideSwipe == true
        or custom.chargeHideEdge == true
        or custom.chargeHideDuration == true
        or custom.activeBorderEnabled == true
        or custom.buffGainSound ~= nil
        or custom.buffLossSound ~= nil
        or custom.cooldownReadySound ~= nil
end

-- [FIX] 글로우 적용 후 텍스트 프레임 레벨을 글로우 위로 올림
-- LCG가 생성한 글로우 프레임이 쿨다운/스택 텍스트를 가리는 문제 방지
local function RaiseTextAboveGlow(frame)
    if not frame then return end
    local baseLevel = frame:GetFrameLevel()
    local textLevel = baseLevel + 15 -- 글로우 프레임(보통 +3~+8) 위로

    -- Cooldown 프레임 (타이머 텍스트 포함)
    if frame.Cooldown then
        pcall(frame.Cooldown.SetFrameLevel, frame.Cooldown, textLevel)
    end

    -- CDM 아이콘의 텍스트 자식 프레임들을 올림
    local ok, children = pcall(function() return { frame:GetChildren() } end)
    if ok and children then
        for _, child in ipairs(children) do
            if child and child ~= frame.Cooldown then
                -- 텍스트가 있는 프레임만 올림 (글로우 프레임은 건드리지 않음)
                local hasText = false
                local okR, regions = pcall(function() return { child:GetRegions() } end)
                if okR and regions then
                    for _, region in ipairs(regions) do
                        if region and pcall(function() return region:GetObjectType() end)
                           and region:GetObjectType() == "FontString" then
                            hasText = true
                            break
                        end
                    end
                end
                if hasText then
                    pcall(child.SetFrameLevel, child, textLevel)
                end
            end
        end
    end
end

-- Show ready glow with settings
-- viewerType: "Essential"/"Utility"/"Buff" — 뷰어별 독립 글로우
local function ShowReadyGlow(frame, spellID, viewerType)
    if not frame then return end

    -- Stop any existing glow first
    StopAllGlows(frame, "DDingUI_ReadyGlow")

    local frameData = GetFrameData(frame)

    if not spellID then
        frameData.readyGlowActive = false
        return
    end

    -- Get customization settings (뷰어별)
    local custom = GetSpellCustomization(spellID, viewerType)
    if not custom or not (
        custom.readyGlow == true
        or custom.activeGlow == true
        or custom.maxChargesGlow == true
        or custom.cooldownReadyGlow == true
    ) then
        frameData.readyGlowActive = false
        return
    end

    -- Get glow settings with defaults
    local glowType = custom.glowType or "button"
    local glowColor
    if custom.glowColorMode == "class" then
        glowColor = GetPlayerClassColor()
    elseif custom.glowColorMode == "custom"
        or (custom.glowColorMode == nil and custom.glowColor)
    then
        glowColor = custom.glowColor
    end
    glowColor = glowColor or {r = 1, g = 0.85, b = 0.1}
    local glowSpeed = custom.glowSpeed or 0.25
    local glowLines = math.floor(custom.glowLines or 8)  -- must be integer
    local glowThickness = custom.glowThickness or 2

    -- Convert color to table format
    local color = {
        glowColor.r or glowColor[1] or 1,
        glowColor.g or glowColor[2] or 0.85,
        glowColor.b or glowColor[3] or 0.1,
        1,
    }

    -- Start appropriate glow type
    if glowType == "pixel" then
        pcall(SL.ShowPixelGlow, frame, color, glowLines, glowSpeed, nil, glowThickness, 0, 0, true, "DDingUI_ReadyGlow")
    elseif glowType == "autocast" then
        pcall(SL.ShowAutocastGlow, frame, color, 4, glowSpeed, 1.0, 0, 0, "DDingUI_ReadyGlow")
    elseif glowType == "proc" then
        local LCG = LibStub("LibCustomGlow-1.0", true)
        if LCG and LCG.ProcGlow_Start then
            pcall(LCG.ProcGlow_Start, frame, {
                color = color, startAnim = false,
                xOffset = 0, yOffset = 0, key = "DDingUI_ReadyGlow"
            })
        end
    else -- button (default)
        pcall(SL.ShowButtonGlow, frame, color, glowSpeed, "DDingUI_ReadyGlow")
    end

    -- [FIX] 텍스트가 글로우 뒤로 가지 않도록 프레임 레벨 조정
    RaiseTextAboveGlow(frame)

    frameData.readyGlowActive = true
end

-- Hide ready glow
local function HideReadyGlow(frame)
    if not frame then return end

    -- Stop all glow types
    StopAllGlows(frame, "DDingUI_ReadyGlow")

    -- Explicitly hide ButtonGlow frame
    if frame._ButtonGlow then
        frame._ButtonGlow:SetAlpha(0)
        frame._ButtonGlow:Hide()
    end

    GetFrameData(frame).readyGlowActive = false
end

-- Check if spell is on cooldown (ignores GCD) - SECRET-SAFE for combat
local function IsSpellOnCooldown(iconFrame)
    if not iconFrame then return false end
    
    local spellID = GetSpellIDFromIcon(iconFrame)
    if not spellID then return false end
    
    -- SECRET-SAFE: Use IsVisible() instead of GetCooldownTimes() arithmetic
    -- Check if cooldown frame is visible (indicates active cooldown)
    local cooldownVisible = false
    if iconFrame.Cooldown then
        local ok, visible = pcall(iconFrame.Cooldown.IsVisible, iconFrame.Cooldown)
        if ok and visible == true then
            cooldownVisible = true
        end
    end
    
    -- Get cooldown info to check isOnGCD (NeverSecret!)
    local cooldownInfo
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and info then
        cooldownInfo = info
    end
    
    -- Logic: If cooldown is visible AND it's NOT just GCD, then it's on cooldown
    -- If isOnGCD is true, treat as ready (not on cooldown)
    if cooldownVisible and cooldownInfo then
        local isOnGCD = cooldownInfo.isOnGCD
        if issecretvalue and issecretvalue(isOnGCD) then
            return false
        end
        return isOnGCD ~= true
    end
    
    -- If cooldown is NOT visible, or if it's just GCD, treat as ready (not on cooldown)
    return false
end

local function ReadCleanBoolean(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "boolean" then return value end
    return nil
end

local function ReadCleanNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "number" then return value end
    return nil
end

local function IsIconActiveState(iconFrame, viewerType)
    if not iconFrame then return false end
    local active = ReadCleanBoolean(iconFrame.isActive)
    if active ~= nil then return active end
    if iconFrame.wasSetFromAura == true or iconFrame.auraInstanceID ~= nil then
        return true
    end
    if viewerType == "Buff" then
        return IsBuffActiveForIcon(iconFrame)
    end
    return false
end

local function GetChargeState(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellCharges then
        return false, false
    end
    local chargeInfo = C_Spell.GetSpellCharges(spellID)
    if not chargeInfo then return false, false end
    local maxCharges = ReadCleanNumber(chargeInfo.maxCharges)
    if not maxCharges or maxCharges <= 1 then return false, false end
    local recharging = ReadCleanBoolean(chargeInfo.isActive)
    return true, recharging == false
end

local function SetVisualAlpha(iconFrame, alpha)
    local regions = {
        iconFrame and (iconFrame.Icon or iconFrame.icon),
        iconFrame and iconFrame.Cooldown,
        iconFrame and iconFrame.ChargeCount,
        iconFrame and iconFrame.Applications,
    }
    for _, region in ipairs(regions) do
        if region and region.SetAlpha then
            region:SetAlpha(alpha)
        end
    end
end

local function SetIconDesaturated(iconFrame, enabled)
    local texture = iconFrame and (iconFrame.Icon or iconFrame.icon)
    if not texture then return end
    if texture.SetDesaturated then
        texture:SetDesaturated(enabled and true or false)
    elseif texture.SetDesaturation then
        texture:SetDesaturation(enabled and 1 or 0)
    end
end

local function GetIconBorderTextures(iconFrame)
    if not iconFrame then return nil end
    if type(iconFrame._ddBorders) == "table" then
        return iconFrame._ddBorders
    end
    local border = iconFrame.border
    if border and type(border.__dduiBorders) == "table" then
        return border.__dduiBorders
    end
    local viewerData = DDingUI.IconViewers and DDingUI.IconViewers._iconData
    local data = viewerData and viewerData[iconFrame]
    return data and data.borders or nil
end

local function GetDefaultBorderColor(iconFrame)
    local settings = iconFrame and iconFrame._groupSettings
    if not settings and iconFrame and iconFrame._ddContainerRef then
        settings = iconFrame._ddContainerRef._groupSettings
    end
    if not settings and iconFrame then
        local viewerName = iconFrame._ddSourceViewer
        local profile = DDingUI.db and DDingUI.db.profile
        settings = viewerName and profile and profile.viewers and profile.viewers[viewerName]
    end
    return NormalizeColor(settings and settings.borderColor, { 0, 0, 0, 1 })
end

local function ApplyActiveBorder(iconFrame, custom, active)
    local data = GetFrameData(iconFrame)
    local enabled = custom and custom.activeBorderEnabled == true
    if not enabled and not data.activeBorderApplied then return end

    local borders = GetIconBorderTextures(iconFrame)
    if type(borders) ~= "table" then return end
    local color = enabled and active
        and NormalizeColor(custom.activeBorderColor, { 1, 0.776, 0.376, 1 })
        or GetDefaultBorderColor(iconFrame)
    for _, border in ipairs(borders) do
        if border and border.SetColorTexture then
            border:SetColorTexture(color[1], color[2], color[3], color[4])
        end
    end
    data.activeBorderApplied = enabled and active or nil
end

local function ApplyNativeStateAppearance(iconFrame, custom, active, onCooldown, isCharge)
    if not iconFrame then return end
    local data = GetFrameData(iconFrame)

    local nonActiveMode = custom and custom.nonActiveMode
    local texture = iconFrame.Icon or iconFrame.icon
    if nonActiveMode == "desaturate" then
        if texture and texture.GetDesaturation
            and (not data.nonActiveModeApplied or data.dynamicIcon == true)
        then
            data.nonActiveBaseDesaturation = texture:GetDesaturation()
        end
        SetIconDesaturated(iconFrame, not active)
        data.nonActiveModeApplied = true
    elseif nonActiveMode == "fullColor" then
        if texture and texture.GetDesaturation
            and (not data.nonActiveModeApplied or data.dynamicIcon == true)
        then
            data.nonActiveBaseDesaturation = texture:GetDesaturation()
        end
        SetIconDesaturated(iconFrame, false)
        data.nonActiveModeApplied = true
    elseif data.nonActiveModeApplied then
        if texture and texture.SetDesaturation then
            texture:SetDesaturation(data.nonActiveBaseDesaturation or 0)
        else
            SetIconDesaturated(iconFrame, false)
        end
        data.nonActiveBaseDesaturation = nil
        data.nonActiveModeApplied = nil
    end

    local effect = custom and custom.cooldownStateEffect
    local visualAlpha = 1
    if effect == "lowerAlphaOnCD" and onCooldown then
        visualAlpha = tonumber(custom.cooldownStateAlpha) or 0.5
    elseif effect == "hiddenOnCD" and onCooldown then
        visualAlpha = 0
    elseif effect == "hiddenReady" and not onCooldown then
        visualAlpha = 0
    end
    if effect or data.cooldownStateAlphaApplied then
        SetVisualAlpha(iconFrame, visualAlpha)
        data.cooldownStateAlphaApplied = effect and true or nil
    end

    ApplyActiveBorder(iconFrame, custom, active)

    local cooldown = iconFrame.Cooldown
    if cooldown and (
        isCharge
        or data.chargeHideSwipeApplied
        or data.chargeHideEdgeApplied
        or data.chargeHideDurationApplied
    ) then
        local base = iconFrame._groupSettings
            or (iconFrame._ddContainerRef and iconFrame._ddContainerRef._groupSettings)
            or {}
        if cooldown.SetDrawSwipe
            and ((custom and custom.chargeHideSwipe == true) or data.chargeHideSwipeApplied)
        then
            local hidden = custom and custom.chargeHideSwipe == true
            cooldown:SetDrawSwipe(not hidden and base.disableSwipeAnimation ~= true)
            data.chargeHideSwipeApplied = hidden or nil
        end
        if cooldown.SetDrawEdge
            and ((custom and custom.chargeHideEdge == true) or data.chargeHideEdgeApplied)
        then
            local hidden = custom and custom.chargeHideEdge == true
            cooldown:SetDrawEdge(not hidden and base.disableEdgeGlow ~= true)
            data.chargeHideEdgeApplied = hidden or nil
        end
        if cooldown.SetHideCountdownNumbers
            and ((custom and custom.chargeHideDuration == true) or data.chargeHideDurationApplied)
        then
            local hidden = custom and custom.chargeHideDuration == true
            cooldown:SetHideCountdownNumbers(hidden or base.hideDurationText == true)
            data.chargeHideDurationApplied = hidden or nil
        end
    end
    local chargeCount = iconFrame.ChargeCount
    if chargeCount then
        local chargeCountMode = custom and custom.chargeCountMode
        if chargeCountMode == "hide" then
            chargeCount:Hide()
            data.chargeCountModeApplied = true
        elseif chargeCountMode == "show" then
            chargeCount:Show()
            data.chargeCountModeApplied = true
        elseif data.chargeCountModeApplied then
            chargeCount:Show()
            data.chargeCountModeApplied = nil
        end
    end
end

local function PlayConfiguredSound(soundKey)
    if not soundKey or soundKey == "none" or not LSM then return end
    local path = LSM:Fetch("sound", soundKey, true)
    if path then
        PlaySoundFile(path, "Master")
    end
end

local function UpdateNativeStateSounds(iconFrame, custom, active, onCooldown)
    local data = GetFrameData(iconFrame)
    if data.lastSoundActive ~= nil and active ~= data.lastSoundActive then
        local soundKey
        if custom then
            soundKey = active and custom.buffGainSound or custom.buffLossSound
        end
        PlayConfiguredSound(soundKey)
    end
    if data.lastSoundOnCooldown == true and onCooldown == false then
        PlayConfiguredSound(custom and custom.cooldownReadySound)
    end
    data.lastSoundActive = active
    data.lastSoundOnCooldown = onCooldown
end

-- Update glow state for an icon frame
local function UpdateReadyGlow(iconFrame, isTimerFiring)
    if not iconFrame then return end

    local iconData = GetFrameData(iconFrame)

    -- Always read fresh spellID from frame (CDM may reuse frames for different spells)
    local spellID = GetSpellIDFromIcon(iconFrame)
    if not spellID then
        -- Spell gone from this frame — delay hiding to avoid flicker during pool reallocation
        if iconData.readyGlowActive then
            if isTimerFiring then
                HideReadyGlow(iconFrame)
                iconData.cachedSpellID = nil
            elseif not iconData._readyGlowHideTimer then
                iconData._readyGlowHideTimer = C_Timer.NewTimer(0.1, function()
                    iconData._readyGlowHideTimer = nil
                    if iconFrame and not iconFrame:IsForbidden() then
                        UpdateReadyGlow(iconFrame, true)
                    end
                end)
            end
        else
            iconData.cachedSpellID = nil
        end
        return
    end

    if spellID ~= iconData.cachedSpellID then
        -- Spell changed on this frame
        if iconData.readyGlowActive then
            HideReadyGlow(iconFrame)
        end
        ApplyNativeStateAppearance(iconFrame, nil, false, false, true)
        iconData.lastSoundActive = nil
        iconData.lastSoundOnCooldown = nil
        iconData.cachedSpellID = spellID
    end

    -- [PER-VIEWER] 뷰어 타입 캐시 (한 번만 조회)
    if iconData.viewerType == nil then
        iconData.viewerType = GetViewerType(iconFrame) or false
    end
    local viewerType = iconData.viewerType or nil -- false → nil

    -- Get customization and evaluate all event-driven visual states.
    local custom = GetSpellCustomization(spellID, viewerType)
    local active = IsIconActiveState(iconFrame, viewerType)
    local onCooldown = IsSpellOnCooldown(iconFrame)
    local isCharge, atMaxCharges = false, false
    if custom and (
        custom.maxChargesGlow == true
        or custom.chargeCountMode ~= nil
        or custom.chargeHideSwipe == true
        or custom.chargeHideEdge == true
        or custom.chargeHideDuration == true
    ) then
        isCharge, atMaxCharges = GetChargeState(spellID)
    end
    ApplyNativeStateAppearance(iconFrame, custom, active, onCooldown, isCharge)
    UpdateNativeStateSounds(iconFrame, custom, active, onCooldown)

    local shouldGlow = false
    if custom then
        if custom.activeGlow == true and active then
            shouldGlow = true
        elseif custom.maxChargesGlow == true and atMaxCharges then
            shouldGlow = true
        elseif custom.cooldownReadyGlow == true and not onCooldown then
            shouldGlow = true
        elseif custom.readyGlow == true then
            local legacyTrigger = custom.glowTrigger
                or (iconData.viewerType == "Buff" and "active" or "ready")
            if legacyTrigger == "active" then
                shouldGlow = active
            else
                shouldGlow = not onCooldown
            end
        end
    end

    -- Only update if state actually changed (prevent flashing)
    if shouldGlow then
        if iconData._readyGlowHideTimer then
            iconData._readyGlowHideTimer:Cancel()
            iconData._readyGlowHideTimer = nil
        end
        if not iconData.readyGlowActive then
            ShowReadyGlow(iconFrame, spellID, viewerType)
        end
    else
        if iconData.readyGlowActive then
            if isTimerFiring then
                HideReadyGlow(iconFrame)
            elseif not iconData._readyGlowHideTimer then
                iconData._readyGlowHideTimer = C_Timer.NewTimer(0.1, function()
                    iconData._readyGlowHideTimer = nil
                    if iconFrame and not iconFrame:IsForbidden() then
                        UpdateReadyGlow(iconFrame, true)
                    end
                end)
            end
        end
    end
end

-- Hook cooldown frame
local function HookCooldownFrame(iconFrame)
    if not iconFrame or not iconFrame.Cooldown then return end
    if IsHooked(iconFrame, "readyGlowHooked") then return end

    SetHooked(iconFrame, "readyGlowHooked")

    local iconData = GetFrameData(iconFrame)

    -- Cache spellID on frame for event-driven updates
    if not InCombatLockdown() then
        local cooldownInfo = iconFrame.cooldownInfo
        if cooldownInfo then
            local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
            if spellID then
                iconData.cachedSpellID = spellID
            end
        end
    end

    -- If we couldn't cache from cooldownInfo, try GetSpellIDFromIcon
    if not iconData.cachedSpellID then
        local spellID = GetSpellIDFromIcon(iconFrame)
        if spellID then
            iconData.cachedSpellID = spellID
        end
    end

    -- Track frame for event-driven updates
    hookedFrames[iconFrame] = true

    -- Hook OnHide for instant glow when cooldown completes (for "ready" trigger)
    if not IsHooked(iconFrame.Cooldown, "readyGlowOnHideHooked") then
        SetHooked(iconFrame.Cooldown, "readyGlowOnHideHooked")
        iconFrame.Cooldown:HookScript("OnHide", function(self)
            -- Cooldown finished - immediately update glow
            C_Timer.After(0, function()
                if iconFrame and not iconFrame:IsForbidden() then
                    UpdateReadyGlow(iconFrame)
                end
            end)
        end)
    end

    -- Hook OnShow/OnHide for buff icons (for "active" trigger)
    -- BuffIconCooldownViewer shows/hides icons when buff activates/deactivates
    if not IsHooked(iconFrame, "buffGlowHooked") then
        SetHooked(iconFrame, "buffGlowHooked")

        -- OnShow: Buff activated - show glow if "active" trigger
        iconFrame:HookScript("OnShow", function(self)
            C_Timer.After(0, function()
                if iconFrame and not iconFrame:IsForbidden() then
                    UpdateReadyGlow(iconFrame)
                end
            end)
        end)

        -- OnHide: Buff deactivated - hide glow
        iconFrame:HookScript("OnHide", function(self)
            if GetFrameData(iconFrame).readyGlowActive then
                UpdateReadyGlow(iconFrame)
            end
        end)
    end

    -- Initial update
    UpdateReadyGlow(iconFrame)
end

-- Find and hook icon frames for a specific spell ID
-- [REPARENT] itemFramePool:EnumerateActive()로 전환 (GetChildren은 reparent 후 빈 결과)
local function FindAndHookIconForSpell(targetSpellID)
    if not targetSpellID then return end

    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
    }

    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for child in viewer.itemFramePool:EnumerateActive() do
                if child and child.Cooldown then
                    local spellID = GetSpellIDFromIcon(child)
                    if spellID and spellID == targetSpellID then
                        -- Hook this frame if not already hooked
                        HookCooldownFrame(child)
                        -- Update glow immediately
                        UpdateReadyGlow(child)
                    end
                end
            end
        end
    end
end

local function RefreshAllReadyGlows(forceRefresh, targetSpellID, targetViewerType)
    -- Loop through tracked frames
    for frame, _ in pairs(hookedFrames) do
        if frame and not frame:IsForbidden() then
            local frameData = GetFrameData(frame)

            -- [PER-VIEWER] 프레임별 뷰어 타입
            if frameData.viewerType == nil then
                frameData.viewerType = GetViewerType(frame) or false
            end
            local viewerType = frameData.viewerType or nil

            local freshID = GetSpellIDFromIcon(frame)

            -- targetSpellID/targetViewerType 필터
            if targetSpellID and freshID ~= targetSpellID then
                -- skip: 다른 스펠
            elseif targetViewerType and viewerType ~= targetViewerType then
                -- skip: 다른 뷰어
            else
                if forceRefresh and frameData.readyGlowActive then
                    HideReadyGlow(frame)
                    UpdateReadyGlow(frame)
                else
                    -- UpdateReadyGlow 내부에 디바운스 및 spellID 캐싱 로직이 완성되어 있으므로 위임
                    UpdateReadyGlow(frame)
                end
            end
        end
    end
end

function IconCustomization:GetIconContext(iconFrame)
    local spellID = GetSpellIDFromIcon(iconFrame)
    if issecretvalue and issecretvalue(spellID) then
        return nil, nil
    end
    if spellID == nil then
        return nil, nil
    end

    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
        return nil, nil
    end

    return spellID, GetViewerType(iconFrame)
end

function IconCustomization:OpenSpellEditor(spellID, viewerType)
    if issecretvalue and issecretvalue(spellID) then return end
    if spellID == nil then return end
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 or not viewerType then return end

    uiState.selectedSpellID = spellID
    uiState.selectedViewerType = viewerType
    uiState.selectedKey = tostring(spellID) .. "_" .. viewerType
    uiState.scannedIcons = ScanAllViewerIcons()

    if not DDingUI._optionsLoaded and DDingUI.OpenConfig then
        DDingUI:OpenConfig()
    end
    if DDingUI.OpenConfigGUI then
        DDingUI:OpenConfigGUI(nil, "iconCustomization")
    end
end

local function BuildGlowContextMenuItems(Current, Apply, SetGlowState, ResetGlow, defaultTrigger, resetLabel, includeReset, capabilities)
    local function ChoiceMenu(key, values, fallback)
        local items = {}
        local selected = Current()[key] or fallback
        for _, value in ipairs(values) do
            local capturedValue = value[1]
            items[#items + 1] = {
                text = value[2],
                checked = selected == capturedValue,
                func = function() Apply(key, capturedValue) end,
            }
        end
        return items
    end

    capabilities = capabilities or {}
    local custom = Current()
    local glowType = custom.glowType or "button"
    local glowTypeLabels = {
        button = L["Action Button Glow"] or "Action Button Glow",
        pixel = L["Pixel Glow"] or "Pixel Glow",
        autocast = L["Autocast Shine"] or "Autocast Shine",
        proc = L["Proc Effect"] or "Proc Effect",
    }
    local glowColorMode = custom.glowColorMode
        or (custom.glowColor and "custom" or "default")
    local glowColorModeLabels = {
        default = L["Default"] or "Default",
        class = L["Class Color"] or "Class Color",
        custom = L["Custom"] or "Custom",
    }
    local legacyTrigger = custom.readyGlow == true and (custom.glowTrigger or defaultTrigger) or nil
    local items = {}
    if capabilities.proc then
        local procMode = custom.procGlowMode or "inherit"
        items[#items + 1] = {
            text = L["Proc Glow"] or "Proc Glow",
            rightText = procMode == "on" and (L["On"] or "On")
                or procMode == "off" and (L["Off"] or "Off")
                or (L["Default"] or "Default"),
            menuList = {
                {
                    text = L["Default"] or "Default",
                    checked = procMode == "inherit",
                    func = function() SetGlowState("proc", nil) end,
                },
                {
                    text = L["On"] or "On",
                    checked = procMode == "on",
                    func = function() SetGlowState("proc", "on") end,
                },
                {
                    text = L["Off"] or "Off",
                    checked = procMode == "off",
                    func = function() SetGlowState("proc", "off") end,
                },
            },
        }
    end
    if capabilities.active then
        local enabled = custom.activeGlow == true or legacyTrigger == "active"
        items[#items + 1] = {
            text = L["Active State Glow"] or "Active State Glow",
            checked = enabled,
            func = function() SetGlowState("active", not enabled) end,
        }
    end
    if capabilities.maxCharges then
        local enabled = custom.maxChargesGlow == true
        items[#items + 1] = {
            text = L["Max Charges Glow"] or "Max Charges Glow",
            checked = enabled,
            func = function() SetGlowState("maxCharges", not enabled) end,
        }
    end
    if capabilities.ready then
        local enabled = custom.cooldownReadyGlow == true or legacyTrigger == "ready"
        items[#items + 1] = {
            text = L["Cooldown Ready Glow"] or "Cooldown Ready Glow",
            checked = enabled,
            func = function() SetGlowState("ready", not enabled) end,
        }
    end
    if #items > 0 then
        items[#items + 1] = { isSeparator = true }
    end
    items[#items + 1] = {
            text = L["Glow Type"] or "Glow Type",
            rightText = glowTypeLabels[glowType],
            menuList = ChoiceMenu("glowType", {
                {"button", L["Action Button Glow"] or "Action Button Glow"},
                {"pixel", L["Pixel Glow"] or "Pixel Glow"},
                {"autocast", L["Autocast Shine"] or "Autocast Shine"},
                {"proc", L["Proc Effect"] or "Proc Effect"},
            }, "button"),
        }
    items[#items + 1] = {
            text = L["Glow Color Mode"] or "Glow Color Mode",
            rightText = glowColorModeLabels[glowColorMode],
            menuList = ChoiceMenu("glowColorMode", {
                { "default", L["Default"] or "Default" },
                { "class", L["Class Color"] or "Class Color" },
                { "custom", L["Custom"] or "Custom" },
            }, glowColorMode),
        }
    items[#items + 1] = {
            text = L["Custom Glow Color"] or "Custom Glow Color",
            swatch = custom.glowColor or {r = 1, g = 0.85, b = 0.1},
            setColor = function(r, g, b)
                Apply("glowColorMode", "custom")
                Apply("glowColor", {r = r, g = g, b = b})
            end,
            func = function()
                local old = Current().glowColor
                local previous = old and {r = old.r, g = old.g, b = old.b} or nil
                local color = old or {r = 1, g = 0.85, b = 0.1}
                if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then return end
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = color.r or 1,
                    g = color.g or 0.85,
                    b = color.b or 0.1,
                    hasOpacity = false,
                    swatchFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        Apply("glowColorMode", "custom")
                        Apply("glowColor", {r = r, g = g, b = b})
                    end,
                    cancelFunc = function()
                        Apply("glowColor", previous)
                    end,
                })
            end,
        }
    items[#items + 1] = {
            text = L["Pixel Glow Settings"] or "Pixel Glow Settings",
            rightText = glowType == "pixel" and string.format("%d / %d", custom.glowLines or 8, custom.glowThickness or 2) or nil,
            menuList = {
                {
                    text = L["Glow Frequency"] or "Glow Frequency",
                    rightText = string.format("%.2f", custom.glowSpeed or 0.25),
                    menuList = ChoiceMenu("glowSpeed", {
                        {0.10, "0.10"}, {0.20, "0.20"}, {0.25, "0.25"},
                        {0.50, "0.50"}, {1.00, "1.00"},
                    }, 0.25),
                },
                {
                    text = L["Line Amount"] or "Line Amount",
                    rightText = tostring(custom.glowLines or 8),
                    menuList = ChoiceMenu("glowLines", {
                        {4, "4"}, {8, "8"}, {12, "12"}, {16, "16"},
                    }, 8),
                },
                {
                    text = L["Line Thickness"] or "Line Thickness",
                    rightText = tostring(custom.glowThickness or 2),
                    menuList = ChoiceMenu("glowThickness", {
                        {1, "1"}, {2, "2"}, {3, "3"}, {4, "4"}, {6, "6"},
                    }, 2),
                },
            },
        }
    if includeReset ~= false then
        items[#items + 1] = { isSeparator = true }
        items[#items + 1] = {
            text = resetLabel,
            color = "dim",
            func = ResetGlow,
        }
    end
    return items
end

local function BuildThresholdContextMenuItem(Current, ApplySetting)
    local settings = Current()
    local seconds = tonumber(settings.thresholdSeconds) or 0
    local color = settings.thresholdColor or { r = 1, g = 0.2, b = 0.2 }
    local secondChoices = {
        { 0, L["Off"] or "Off" },
        { 3, "3s" },
        { 5, "5s" },
        { 10, "10s" },
        { 15, "15s" },
        { 20, "20s" },
        { 30, "30s" },
        { 45, "45s" },
        { 59, "59s" },
    }
    local secondItems = {}
    for _, choice in ipairs(secondChoices) do
        local value = choice[1]
        secondItems[#secondItems + 1] = {
            text = choice[2],
            checked = seconds == value,
            func = function()
                ApplySetting("thresholdSeconds", value > 0 and value or nil)
            end,
        }
    end

    return {
        text = L["Threshold Text"] or "Threshold Text",
        rightText = seconds > 0 and string.format("%ds", seconds) or (L["Off"] or "Off"),
        menuList = {
            {
                text = L["Threshold Seconds"] or "Threshold Seconds",
                rightText = seconds > 0 and string.format("%ds", seconds) or (L["Off"] or "Off"),
                menuList = secondItems,
            },
            {
                text = L["Threshold Decimals"] or "Threshold Decimals",
                checked = settings.thresholdDecimals == true,
                func = function()
                    ApplySetting("thresholdDecimals", settings.thresholdDecimals ~= true and true or nil)
                end,
            },
            {
                text = L["Threshold Color"] or "Threshold Color",
                checked = settings.thresholdColorEnabled == true,
                func = function()
                    ApplySetting("thresholdColorEnabled", settings.thresholdColorEnabled ~= true and true or nil)
                end,
            },
            {
                text = L["Threshold Text Color"] or "Threshold Text Color",
                swatch = color,
                func = function()
                    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then return end
                    local current = Current().thresholdColor or { r = 1, g = 0.2, b = 0.2 }
                    local previous = {
                        r = current.r or current[1] or 1,
                        g = current.g or current[2] or 0.2,
                        b = current.b or current[3] or 0.2,
                    }
                    ColorPickerFrame:SetupColorPickerAndShow({
                        r = previous.r,
                        g = previous.g,
                        b = previous.b,
                        hasOpacity = false,
                        swatchFunc = function()
                            local r, g, b = ColorPickerFrame:GetColorRGB()
                            ApplySetting("thresholdColor", { r = r, g = g, b = b })
                        end,
                        cancelFunc = function()
                            ApplySetting("thresholdColor", previous)
                        end,
                    })
                end,
            },
        },
    }
end

local function OpenMenuColorPicker(Current, ApplySetting, key, fallback)
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then return end
    local previous = NormalizeColor(Current()[key], fallback)
    ColorPickerFrame:SetupColorPickerAndShow({
        r = previous[1],
        g = previous[2],
        b = previous[3],
        hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ApplySetting(key, { r = r, g = g, b = b, a = previous[4] })
        end,
        cancelFunc = function()
            ApplySetting(key, {
                r = previous[1],
                g = previous[2],
                b = previous[3],
                a = previous[4],
            })
        end,
    })
end

local function BuildSoundContextMenuItem(label, key, Current, ApplySetting)
    local selected = Current()[key] or "none"
    local soundNames = {}
    if LSM and LSM.HashTable then
        for name in pairs(LSM:HashTable("sound") or {}) do
            soundNames[#soundNames + 1] = name
        end
        table.sort(soundNames)
    end

    local choices = {
        {
            text = L["None"] or "None",
            checked = selected == "none",
            func = function() ApplySetting(key, nil) end,
        },
    }
    local pageSize = 16
    for first = 1, #soundNames, pageSize do
        local last = math.min(first + pageSize - 1, #soundNames)
        local page = {}
        for index = first, last do
            local soundName = soundNames[index]
            page[#page + 1] = {
                text = soundName,
                checked = selected == soundName,
                func = function()
                    ApplySetting(key, soundName)
                    PlayConfiguredSound(soundName)
                end,
            }
        end
        choices[#choices + 1] = {
            text = string.format("%d-%d", first, last),
            menuList = page,
        }
    end

    return {
        text = label,
        rightText = selected ~= "none" and selected or (L["None"] or "None"),
        menuList = choices,
    }
end

local function BuildStateEffectMenuItems(Current, ApplySetting, includeCharges)
    local settings = Current()
    local items = {
        {
            text = L["Non Active State"] or "Non Active State",
            rightText = settings.nonActiveMode == "desaturate" and (L["Desaturate"] or "Desaturate")
                or settings.nonActiveMode == "fullColor" and (L["Full Color"] or "Full Color")
                or (L["Default"] or "Default"),
            menuList = {
                {
                    text = L["Default"] or "Default",
                    checked = settings.nonActiveMode == nil,
                    func = function() ApplySetting("nonActiveMode", nil) end,
                },
                {
                    text = L["Desaturate When Not Active"] or "Desaturate When Not Active",
                    checked = settings.nonActiveMode == "desaturate",
                    func = function() ApplySetting("nonActiveMode", "desaturate") end,
                },
                {
                    text = L["Full Color"] or "Full Color",
                    checked = settings.nonActiveMode == "fullColor",
                    func = function() ApplySetting("nonActiveMode", "fullColor") end,
                },
            },
        },
        {
            text = L["Cooldown State Effect"] or "Cooldown State Effect",
            rightText = settings.cooldownStateEffect == "lowerAlphaOnCD"
                    and (L["Lower Alpha on Cooldown"] or "Lower Alpha on Cooldown")
                or settings.cooldownStateEffect == "hiddenOnCD"
                    and (L["Hidden on Cooldown"] or "Hidden on Cooldown")
                or settings.cooldownStateEffect == "hiddenReady"
                    and (L["Hidden When Ready"] or "Hidden When Ready")
                or (L["None"] or "None"),
            menuList = {
                {
                    text = L["None"] or "None",
                    checked = settings.cooldownStateEffect == nil,
                    func = function() ApplySetting("cooldownStateEffect", nil) end,
                },
                {
                    text = L["Lower Alpha on Cooldown"] or "Lower Alpha on Cooldown",
                    checked = settings.cooldownStateEffect == "lowerAlphaOnCD",
                    func = function() ApplySetting("cooldownStateEffect", "lowerAlphaOnCD") end,
                },
                {
                    text = L["Hidden on Cooldown"] or "Hidden on Cooldown",
                    checked = settings.cooldownStateEffect == "hiddenOnCD",
                    func = function() ApplySetting("cooldownStateEffect", "hiddenOnCD") end,
                },
                {
                    text = L["Hidden When Ready"] or "Hidden When Ready",
                    checked = settings.cooldownStateEffect == "hiddenReady",
                    func = function() ApplySetting("cooldownStateEffect", "hiddenReady") end,
                },
            },
        },
        {
            text = L["Cooldown State Opacity"] or "Cooldown State Opacity",
            rightText = string.format("%d%%", math.floor((tonumber(settings.cooldownStateAlpha) or 0.5) * 100 + 0.5)),
            menuList = {},
        },
    }
    for _, alpha in ipairs({ 0.25, 0.4, 0.5, 0.6, 0.75 }) do
        local capturedAlpha = alpha
        items[3].menuList[#items[3].menuList + 1] = {
            text = string.format("%d%%", math.floor(capturedAlpha * 100 + 0.5)),
            checked = (tonumber(settings.cooldownStateAlpha) or 0.5) == capturedAlpha,
            func = function() ApplySetting("cooldownStateAlpha", capturedAlpha) end,
        }
    end

    if includeCharges then
        local chargeMenu = {
            {
                text = L["Charge Count"] or "Charge Count",
                rightText = settings.chargeCountMode == "show" and (L["Show"] or "Show")
                    or settings.chargeCountMode == "hide" and (L["Hide"] or "Hide")
                    or (L["Default"] or "Default"),
                menuList = {
                    {
                        text = L["Default"] or "Default",
                        checked = settings.chargeCountMode == nil,
                        func = function() ApplySetting("chargeCountMode", nil) end,
                    },
                    {
                        text = L["Show"] or "Show",
                        checked = settings.chargeCountMode == "show",
                        func = function() ApplySetting("chargeCountMode", "show") end,
                    },
                    {
                        text = L["Hide"] or "Hide",
                        checked = settings.chargeCountMode == "hide",
                        func = function() ApplySetting("chargeCountMode", "hide") end,
                    },
                },
            },
        }
        for _, option in ipairs({
            { "chargeHideSwipe", L["Hide Recharge Swipe"] or "Hide Recharge Swipe" },
            { "chargeHideEdge", L["Hide Recharge Edge"] or "Hide Recharge Edge" },
            { "chargeHideDuration", L["Hide Duration With Charges"] or "Hide Duration With Charges" },
        }) do
            local capturedKey = option[1]
            local label = option[2]
            chargeMenu[#chargeMenu + 1] = {
                text = label,
                checked = settings[capturedKey] == true,
                func = function()
                    ApplySetting(
                        capturedKey,
                        settings[capturedKey] ~= true and true or nil
                    )
                end,
            }
        end
        items[#items + 1] = {
            text = L["Charge Display"] or "Charge Display",
            menuList = chargeMenu,
        }
    end
    return items
end

function IconCustomization:BuildContextMenuItems(spellID, viewerType, onSettingsChanged, glowOnly)
    if issecretvalue and issecretvalue(spellID) then return nil end
    if spellID == nil then return nil end
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 or not viewerType then return nil end

    local profile = DDingUI.db and DDingUI.db.profile
    if not profile then return nil end
    profile.iconCustomization = profile.iconCustomization or {}
    profile.iconCustomization.spells = profile.iconCustomization.spells or {}

    local spells = profile.iconCustomization.spells
    local spellKey = tostring(spellID) .. "_" .. viewerType
    local defaultTrigger = viewerType == "Buff" and "active" or "ready"

    local function Current()
        return spells[spellKey] or {}
    end

    local function RefreshGlow()
        RefreshAllReadyGlows(true, spellID, viewerType)
        RefreshGUI()
    end

    local function NotifyChanged()
        if onSettingsChanged then onSettingsChanged(spells[spellKey]) end
    end

    local function Compact()
        if spells[spellKey] and next(spells[spellKey]) == nil then
            spells[spellKey] = nil
        end
    end

    local function Apply(key, value)
        spells[spellKey] = spells[spellKey] or {}
        spells[spellKey][key] = value
        Compact()
        NotifyChanged()
        RefreshGlow()
    end

    local function SetGlowState(state, value)
        spells[spellKey] = spells[spellKey] or {}
        local custom = spells[spellKey]
        if state == "proc" then
            custom.procGlowMode = value
        else
            local key = state == "active" and "activeGlow"
                or state == "maxCharges" and "maxChargesGlow"
                or "cooldownReadyGlow"
            custom[key] = value == true and true or nil
            custom.readyGlow = nil
            custom.glowTrigger = nil
        end
        Compact()
        NotifyChanged()
        FindAndHookIconForSpell(spellID)
        if DDingUI.ProcGlow and DDingUI.ProcGlow.RefreshAll then
            DDingUI.ProcGlow:RefreshAll()
        end
        RefreshGlow()
    end

    local function ResetGlow()
        local custom = spells[spellKey]
        if custom then
            custom.readyGlow = nil
            custom.glowTrigger = nil
            custom.glowType = nil
            custom.glowColorMode = nil
            custom.glowColor = nil
            custom.glowSpeed = nil
            custom.glowLines = nil
            custom.glowThickness = nil
            custom.procGlowMode = nil
            custom.activeGlow = nil
            custom.maxChargesGlow = nil
            custom.cooldownReadyGlow = nil
        end
        Compact()
        NotifyChanged()
        if DDingUI.ProcGlow and DDingUI.ProcGlow.RefreshAll then
            DDingUI.ProcGlow:RefreshAll()
        end
        RefreshGlow()
    end

    local function RefreshVisual()
        if DDingUI.GroupSystem and DDingUI.GroupSystem.RequestFullUpdate then
            DDingUI.GroupSystem:RequestFullUpdate()
        end
        RefreshGUI()
    end

    local function ApplyVisual(key, value)
        spells[spellKey] = spells[spellKey] or {}
        spells[spellKey][key] = value
        Compact()
        NotifyChanged()
        FindAndHookIconForSpell(spellID)
        RefreshVisual()
    end

    local function ResetIcon()
        spells[spellKey] = nil
        NotifyChanged()
        RefreshAllReadyGlows(true, spellID, viewerType)
        RefreshVisual()
    end

    if glowOnly then
        return BuildGlowContextMenuItems(
            Current,
            Apply,
            SetGlowState,
            ResetGlow,
            defaultTrigger,
            L["Reset Glow"] or "Reset Glow",
            true,
            {
                proc = viewerType ~= "Buff",
                active = true,
                maxCharges = viewerType ~= "Buff",
                ready = viewerType ~= "Buff",
            }
        )
    end
    local menuItems = {}

    local function VisualChoice(label, key, choices)
        local selected = Current()[key] or "inherit"
        local labels = {}
        local items = {}
        for _, choice in ipairs(choices) do
            local value = choice[1]
            labels[value] = choice[2]
            items[#items + 1] = {
                text = choice[2],
                checked = selected == value,
                func = function()
                    ApplyVisual(key, value == "inherit" and nil or value)
                end,
            }
        end
        return {
            text = label,
            rightText = labels[selected],
            menuList = items,
        }
    end

    local inheritShowHide = {
        { "inherit", L["Default"] or "Default" },
        { "show", L["Show"] or "Show" },
        { "hide", L["Hide"] or "Hide" },
    }
    menuItems[#menuItems + 1] = { isSeparator = true }
    menuItems[#menuItems + 1] = VisualChoice(
        L["Active State"] or "Active State",
        "activeSwipeMode",
        {
            { "inherit", L["Default"] or "Default" },
            { "custom", L["Swipe Color"] or "Swipe Color" },
            { "class", L["Class Color"] or "Class Color" },
            { "hidden", L["Hide Active State"] or "Hide Active State" },
        }
    )
    menuItems[#menuItems + 1] = {
        text = L["Active Swipe Color"] or "Active Swipe Color",
        swatch = Current().activeSwipeColor or { r = 1, g = 0.776, b = 0.376, a = 0.8 },
        func = function()
            ApplyVisual("activeSwipeMode", "custom")
            OpenMenuColorPicker(
                Current,
                ApplyVisual,
                "activeSwipeColor",
                { 1, 0.776, 0.376, 0.8 }
            )
        end,
    }
    menuItems[#menuItems + 1] = {
        text = L["Active Border"] or "Active Border",
        checked = Current().activeBorderEnabled == true,
        func = function()
            ApplyVisual(
                "activeBorderEnabled",
                Current().activeBorderEnabled ~= true and true or nil
            )
        end,
    }
    menuItems[#menuItems + 1] = {
        text = L["Active Border Color"] or "Active Border Color",
        swatch = Current().activeBorderColor or { r = 1, g = 0.776, b = 0.376, a = 1 },
        func = function()
            ApplyVisual("activeBorderEnabled", true)
            OpenMenuColorPicker(
                Current,
                ApplyVisual,
                "activeBorderColor",
                { 1, 0.776, 0.376, 1 }
            )
        end,
    }
    if viewerType == "Buff" then
        menuItems[#menuItems + 1] = VisualChoice(
            L["Always Show Buff"] or "Always Show Buff",
            "alwaysShow",
            {
                { "inherit", L["Default"] or "Default" },
                { "on", L["Show"] or "Show" },
                { "off", L["Hide"] or "Hide" },
            }
        )
        menuItems[#menuItems + 1] = VisualChoice(
            L["Desaturate Inactive"] or "Desaturate Inactive",
            "desatInactive",
            {
                { "inherit", L["Default"] or "Default" },
                { "on", L["Desaturate"] or "Desaturate" },
                { "off", L["Full Color"] or "Full Color" },
            }
        )
    end
    if viewerType ~= "Buff" then
        for _, item in ipairs(BuildStateEffectMenuItems(Current, ApplyVisual, true)) do
            menuItems[#menuItems + 1] = item
        end
    end
    menuItems[#menuItems + 1] = VisualChoice(
        L["Cooldown Swipe"] or "Cooldown Swipe",
        "cooldownSwipeMode",
        {
            { "inherit", L["Default"] or "Default" },
            { "normal", L["Normal"] or "Normal" },
            { "reverse", L["Reverse"] or "Reverse" },
            { "hidden", L["Hidden"] or "Hidden" },
        }
    )
    menuItems[#menuItems + 1] = VisualChoice(
        L["Cooldown Edge"] or "Cooldown Edge",
        "cooldownEdgeMode",
        inheritShowHide
    )
    menuItems[#menuItems + 1] = VisualChoice(
        L["Cooldown Finish Flash"] or "Cooldown Finish Flash",
        "cooldownFinishMode",
        inheritShowHide
    )
    menuItems[#menuItems + 1] = VisualChoice(
        L["Active Duration Text"] or "Active Duration Text",
        "activeDurationMode",
        inheritShowHide
    )
    menuItems[#menuItems + 1] = BuildThresholdContextMenuItem(Current, ApplyVisual)
    if viewerType == "Buff" then
        menuItems[#menuItems + 1] = BuildSoundContextMenuItem(
            L["Audio on Buff Gain"] or "Audio on Buff Gain",
            "buffGainSound",
            Current,
            ApplyVisual
        )
        menuItems[#menuItems + 1] = BuildSoundContextMenuItem(
            L["Audio on Buff Loss"] or "Audio on Buff Loss",
            "buffLossSound",
            Current,
            ApplyVisual
        )
    else
        menuItems[#menuItems + 1] = BuildSoundContextMenuItem(
            L["Audio Effect on Cooldown Ready"] or "Audio Effect on Cooldown Ready",
            "cooldownReadySound",
            Current,
            ApplyVisual
        )
    end
    menuItems[#menuItems + 1] = { isSeparator = true }
    menuItems[#menuItems + 1] = {
        text = L["Reset Icon"] or "Reset Icon",
        color = "dim",
        func = ResetIcon,
    }
    return menuItems
end

function IconCustomization:BuildDynamicContextMenuItems(iconKey, refreshFunc, onSettingsChanged, glowOnly)
    local profile = DDingUI.db and DDingUI.db.profile
    local dynamicIcons = profile and profile.dynamicIcons
    local iconData = iconKey and dynamicIcons and dynamicIcons.iconData and dynamicIcons.iconData[iconKey]
    if not iconData then return nil end
    iconData.settings = iconData.settings or {}

    local supportsActiveState = iconData.type == "aura"
        or iconData.type == "trinketProc"
        or (iconData.type == "item" and tonumber(iconData.settings.activeEffectDuration) ~= nil)
    local defaultTrigger = supportsActiveState and "active" or "ready"
    local function Current()
        return iconData.settings.customStateGlow or {}
    end

    local function Refresh()
        if DDingUI.CustomIcons and DDingUI.CustomIcons.RefreshDynamicIcon then
            DDingUI.CustomIcons:RefreshDynamicIcon(iconKey)
        end
        if refreshFunc then refreshFunc() end
        RefreshGUI()
    end

    local function Apply(key, value)
        iconData.settings.customStateGlow = iconData.settings.customStateGlow or {}
        iconData.settings.customStateGlow[key] = value
        if onSettingsChanged then onSettingsChanged(iconData.settings.customStateGlow) end
        Refresh()
    end

    local function SetGlowState(state, value)
        iconData.settings.customStateGlow = iconData.settings.customStateGlow or {}
        local custom = iconData.settings.customStateGlow
        local key = state == "active" and "activeGlow"
            or state == "maxCharges" and "maxChargesGlow"
            or "cooldownReadyGlow"
        custom[key] = value == true and true or nil
        custom.readyGlow = nil
        custom.glowTrigger = nil
        if next(custom) == nil then
            iconData.settings.customStateGlow = nil
        end
        if onSettingsChanged then onSettingsChanged(iconData.settings.customStateGlow) end
        Refresh()
    end

    local function ResetGlow()
        iconData.settings.customStateGlow = nil
        if onSettingsChanged then onSettingsChanged(nil) end
        Refresh()
    end

    if glowOnly then
        return BuildGlowContextMenuItems(
            Current,
            Apply,
            SetGlowState,
            ResetGlow,
            defaultTrigger,
            L["Reset Glow"] or "Reset Glow",
            true,
            {
                active = supportsActiveState,
                maxCharges = iconData.type == "spell",
                ready = iconData.type ~= "aura",
            }
        )
    end
    local menuItems = {}

    local function ToggleSetting(key, defaultValue)
        local current = iconData.settings[key]
        if current == nil then current = defaultValue end
        iconData.settings[key] = not current
        Refresh()
    end

    local function ApplyStateSetting(key, value)
        iconData.settings[key] = value
        Refresh()
        if (key == "alwaysShow" or key == "desatInactive")
            and DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge.NotifyIconsChanged
        then
            DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
        end
    end

    local function StateChoice(label, key, choices)
        local selected = iconData.settings[key] or "inherit"
        local labels = {}
        local items = {}
        for _, choice in ipairs(choices) do
            local value = choice[1]
            labels[value] = choice[2]
            items[#items + 1] = {
                text = choice[2],
                checked = selected == value,
                func = function()
                    ApplyStateSetting(key, value == "inherit" and nil or value)
                end,
            }
        end
        return {
            text = label,
            rightText = labels[selected],
            menuList = items,
        }
    end

    local stateItems = {
        {
            text = L["Show Cooldown Swipe"] or "Show Cooldown Swipe",
            checked = iconData.settings.showCooldown ~= false,
            func = function() ToggleSetting("showCooldown", true) end,
        },
    }
    if iconData.type == "spell" or iconData.type == "racial" then
        stateItems[#stateItems + 1] = {
            text = L["Show Charges"] or "Show Charges",
            checked = iconData.settings.showCharges ~= false,
            func = function() ToggleSetting("showCharges", true) end,
        }
    end
    if iconData.type ~= "aura" then
        stateItems[#stateItems + 1] = {
            text = L["Desaturate on Cooldown"] or "Desaturate on Cooldown",
            checked = iconData.settings.desaturateOnCooldown ~= false,
            func = function() ToggleSetting("desaturateOnCooldown", true) end,
        }
        stateItems[#stateItems + 1] = {
            text = L["Desaturate When Unusable"] or "Desaturate When Unusable",
            checked = iconData.settings.desaturateWhenUnusable ~= false,
            func = function() ToggleSetting("desaturateWhenUnusable", true) end,
        }
    end
    if iconData.type == "trinketProc" then
        stateItems[#stateItems + 1] = { isSeparator = true }
        stateItems[#stateItems + 1] = {
            text = L["Show Proc Duration"] or "Show Proc Duration",
            checked = iconData.settings.showProcDuration ~= false,
            func = function() ToggleSetting("showProcDuration", true) end,
        }
        stateItems[#stateItems + 1] = {
            text = L["Show Proc Stacks"] or "Show Proc Stacks",
            checked = iconData.settings.showProcStacks ~= false,
            func = function() ToggleSetting("showProcStacks", true) end,
        }
        stateItems[#stateItems + 1] = {
            text = L["Show Item Cooldown"] or "Show Item Cooldown",
            checked = iconData.settings.showItemCooldown ~= false,
            func = function() ToggleSetting("showItemCooldown", true) end,
        }
    end
    if supportsActiveState then
        stateItems[#stateItems + 1] = { isSeparator = true }
        stateItems[#stateItems + 1] = StateChoice(
            L["Active State"] or "Active State",
            "activeSwipeMode",
            {
                { "inherit", L["Default"] or "Default" },
                { "custom", L["Swipe Color"] or "Swipe Color" },
                { "class", L["Class Color"] or "Class Color" },
                { "hidden", L["Hide Active State"] or "Hide Active State" },
            }
        )
        stateItems[#stateItems + 1] = {
            text = L["Active Swipe Color"] or "Active Swipe Color",
            swatch = iconData.settings.activeSwipeColor
                or { r = 1, g = 0.776, b = 0.376, a = 0.8 },
            func = function()
                ApplyStateSetting("activeSwipeMode", "custom")
                OpenMenuColorPicker(
                    function() return iconData.settings end,
                    ApplyStateSetting,
                    "activeSwipeColor",
                    { 1, 0.776, 0.376, 0.8 }
                )
            end,
        }
        stateItems[#stateItems + 1] = {
            text = L["Active Border"] or "Active Border",
            checked = iconData.settings.activeBorderEnabled == true,
            func = function()
                ApplyStateSetting(
                    "activeBorderEnabled",
                    iconData.settings.activeBorderEnabled ~= true and true or nil
                )
            end,
        }
        stateItems[#stateItems + 1] = {
            text = L["Active Border Color"] or "Active Border Color",
            swatch = iconData.settings.activeBorderColor
                or { r = 1, g = 0.776, b = 0.376, a = 1 },
            func = function()
                ApplyStateSetting("activeBorderEnabled", true)
                OpenMenuColorPicker(
                    function() return iconData.settings end,
                    ApplyStateSetting,
                    "activeBorderColor",
                    { 1, 0.776, 0.376, 1 }
                )
            end,
        }
        stateItems[#stateItems + 1] = StateChoice(
            L["Always Show Buff"] or "Always Show Buff",
            "alwaysShow",
            {
                { "inherit", L["Default"] or "Default" },
                { "on", L["Show"] or "Show" },
                { "off", L["Hide"] or "Hide" },
            }
        )
        stateItems[#stateItems + 1] = StateChoice(
            L["Desaturate Inactive"] or "Desaturate Inactive",
            "desatInactive",
            {
                { "inherit", L["Default"] or "Default" },
                { "on", L["Desaturate"] or "Desaturate" },
                { "off", L["Full Color"] or "Full Color" },
            }
        )
    else
        for _, item in ipairs(BuildStateEffectMenuItems(
            function() return iconData.settings end,
            ApplyStateSetting,
            false
        )) do
            stateItems[#stateItems + 1] = item
        end
    end

    for _, item in ipairs(stateItems) do
        menuItems[#menuItems + 1] = item
    end
    menuItems[#menuItems + 1] = BuildThresholdContextMenuItem(
        function() return iconData.settings end,
        ApplyStateSetting
    )
    if iconData.type == "aura" or iconData.type == "trinketProc" then
        menuItems[#menuItems + 1] = BuildSoundContextMenuItem(
            L["Audio on Buff Gain"] or "Audio on Buff Gain",
            "buffGainSound",
            function() return iconData.settings end,
            ApplyStateSetting
        )
        menuItems[#menuItems + 1] = BuildSoundContextMenuItem(
            L["Audio on Buff Loss"] or "Audio on Buff Loss",
            "buffLossSound",
            function() return iconData.settings end,
            ApplyStateSetting
        )
    else
        menuItems[#menuItems + 1] = BuildSoundContextMenuItem(
            L["Audio Effect on Cooldown Ready"] or "Audio Effect on Cooldown Ready",
            "cooldownReadySound",
            function() return iconData.settings end,
            ApplyStateSetting
        )
    end
    return menuItems
end

function IconCustomization:RefreshAllGlows()
    RefreshAllReadyGlows(true)
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge.NotifyIconsChanged then
        DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
    elseif DDingUI.GroupSystem and DDingUI.GroupSystem.RequestFullUpdate then
        DDingUI.GroupSystem:RequestFullUpdate()
    end
end

function IconCustomization:UpdateDynamicIconGlow(frame, settings, shouldGlow)
    if not frame then return end
    local frameData = GetFrameData(frame)
    local key = "DDingUI_DynamicStateGlow"
    local configured = settings and (
        settings.readyGlow == true
        or settings.activeGlow == true
        or settings.maxChargesGlow == true
        or settings.cooldownReadyGlow == true
    )
    if not configured or shouldGlow ~= true then
        if frameData.dynamicGlowActive then
            StopAllGlows(frame, key)
            frameData.dynamicGlowActive = nil
            frameData.dynamicGlowSignature = nil
        end
        return
    end

    local glowType = settings.glowType or "button"
    local glowColor
    if settings.glowColorMode == "class" then
        glowColor = GetPlayerClassColor()
    elseif settings.glowColorMode == "custom"
        or (settings.glowColorMode == nil and settings.glowColor)
    then
        glowColor = settings.glowColor
    end
    glowColor = glowColor or { r = 1, g = 0.85, b = 0.1 }
    local signature = table.concat({
        glowType,
        tostring(glowColor.r or glowColor[1] or 1),
        tostring(glowColor.g or glowColor[2] or 0.85),
        tostring(glowColor.b or glowColor[3] or 0.1),
        tostring(settings.glowSpeed or 0.25),
        tostring(settings.glowLines or 8),
        tostring(settings.glowThickness or 2),
    }, ":")
    if frameData.dynamicGlowActive and frameData.dynamicGlowSignature == signature then return end

    StopAllGlows(frame, key)
    local color = {
        glowColor.r or glowColor[1] or 1,
        glowColor.g or glowColor[2] or 0.85,
        glowColor.b or glowColor[3] or 0.1,
        1,
    }
    if glowType == "pixel" then
        pcall(SL.ShowPixelGlow, frame, color, math.floor(settings.glowLines or 8), settings.glowSpeed or 0.25, nil, settings.glowThickness or 2, 0, 0, true, key)
    elseif glowType == "autocast" then
        pcall(SL.ShowAutocastGlow, frame, color, 4, settings.glowSpeed or 0.25, 1, 0, 0, key)
    elseif glowType == "proc" then
        local glow = LibStub("LibCustomGlow-1.0", true)
        if glow and glow.ProcGlow_Start then
            pcall(glow.ProcGlow_Start, frame, {
                color = color,
                startAnim = false,
                xOffset = 0,
                yOffset = 0,
                key = key,
            })
        end
    else
        pcall(SL.ShowButtonGlow, frame, color, settings.glowSpeed or 0.25, key)
    end
    RaiseTextAboveGlow(frame)
    frameData.dynamicGlowActive = true
    frameData.dynamicGlowSignature = signature
end

function IconCustomization:ClearDynamicIconGlow(frame)
    if not frame then return end
    local frameData = GetFrameData(frame)
    if frameData.dynamicGlowActive then
        StopAllGlows(frame, "DDingUI_DynamicStateGlow")
    end
    frameData.dynamicGlowActive = nil
    frameData.dynamicGlowSignature = nil
end

-- Build the Icon Customization UI
function IconCustomization:BuildIconCustomizationUI(parentFrame)
    if not parentFrame then return end

    -- Ensure GUI components are loaded
    if not EnsureGUILoaded() then
        -- Fallback THEME if GUI not loaded yet
        THEME = THEME or {
            accent = {0.90, 0.45, 0.12},
            accentLight = {1.00, 0.60, 0.25},
            accentDark = {0.50, 0.15, 0.04},
            bgDark = {0.08, 0.08, 0.08, 0.95},
            bgMedium = {0.18, 0.18, 0.22, 0.80},
            bgLight = {0.20, 0.20, 0.20, 0.60},
            bgWidget = {0.06, 0.06, 0.06, 0.80},
            border = {0.25, 0.25, 0.25, 0.50},
            borderLight = {0.40, 0.40, 0.40, 0.70},
            text = {0.85, 0.85, 0.85, 1},
            textDim = {0.60, 0.60, 0.60, 1},
        }
    end

    -- Clear existing widgets
    if parentFrame.widgets then
        for _, widget in ipairs(parentFrame.widgets) do
            if widget and widget.ClearAllPoints then
                widget:Hide()
                widget:ClearAllPoints()
                widget:SetParent(nil)
            end
        end
    end
    parentFrame.widgets = {}
    
    local yOffset = 10
    
    -- Scan Icons button
    local scanButtonFrame = CreateFrame("Frame", nil, parentFrame)
    scanButtonFrame:SetHeight(32)
    scanButtonFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 10, -yOffset)
    scanButtonFrame:SetPoint("RIGHT", parentFrame, "RIGHT", -10, 0)
    
    local scanButton = CreateFrame("Button", nil, scanButtonFrame, "BackdropTemplate")
    scanButton:SetHeight(28)
    scanButton:SetWidth(150)
    scanButton:SetPoint("LEFT", scanButtonFrame, "LEFT", 0, 0)
    
    scanButton:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    scanButton:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    scanButton:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 1)
    
    local scanLabel = scanButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(scanLabel)
    scanLabel:SetPoint("CENTER")
    scanLabel:SetText(L["Scan Icons"] or "Scan Icons")
    scanLabel:SetTextColor(1, 1, 1, 1)
    
    scanButton:SetScript("OnClick", function(self)
        uiState.scannedIcons = ScanAllViewerIcons()
        RefreshGUI()
    end)
    
    table.insert(parentFrame.widgets, scanButtonFrame)
    yOffset = yOffset + 42
    
    -- Help text
    local helpText = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleFontString(helpText)
    helpText:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 10, -yOffset)
    helpText:SetPoint("RIGHT", parentFrame, "RIGHT", -10, 0)
    helpText:SetJustifyH("LEFT")
    helpText:SetText(L["Click to select • Blue border = Customized"] or "Click to select • Blue border = Customized")
    helpText:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.85)
    table.insert(parentFrame.widgets, helpText)
    yOffset = yOffset + 25
    
    -- Display icons by category
    local categories = {
        { name = L["Essential Cooldowns"] or "Essential Cooldowns", key = "Essential", color = {1, 0.5, 0.2} },
        { name = L["Utility Cooldowns"] or "Utility Cooldowns", key = "Utility", color = {0.2, 0.6, 1} },
        { name = L["Buff Icons"] or "Buff Icons", key = "Buff", color = {0.2, 1, 0.2} },
    }
    
    for _, category in ipairs(categories) do
        local icons = uiState.scannedIcons[category.key] or {}
        if #icons > 0 then
            -- Category header
            local headerFrame = CreateFrame("Frame", nil, parentFrame)
            headerFrame:SetHeight(24)
            headerFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 10, -yOffset)
            headerFrame:SetPoint("RIGHT", parentFrame, "RIGHT", -10, 0)
            
            local headerText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            StyleFontString(headerText)
            local globalFontPath = DDingUI:GetGlobalFont()
            if globalFontPath then
                headerText:SetFont(globalFontPath, 16, "OUTLINE")
            end
            headerText:SetPoint("LEFT", headerFrame, "LEFT", 0, 0)
            headerText:SetText(string.format("%s (%d)", category.name, #icons))
            headerText:SetTextColor(category.color[1], category.color[2], category.color[3], 1)
            
            table.insert(parentFrame.widgets, headerFrame)
            yOffset = yOffset + 30
            
            -- Icon grid
            local gridFrame = CreateFrame("Frame", nil, parentFrame)
            gridFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 10, -yOffset)
            gridFrame:SetPoint("RIGHT", parentFrame, "RIGHT", -10, 0)
            
            local iconSize = 44
            local spacing = 5
            local parentWidth = parentFrame:GetWidth() or 900
            local iconsPerRow = math.floor((parentWidth - 20) / (iconSize + spacing))
            if iconsPerRow < 1 then iconsPerRow = 1 end
            
            local currentRow = 0
            local currentCol = 0
            
            for i, iconData in ipairs(icons) do
                local iconButton = CreateFrame("Button", nil, gridFrame, "BackdropTemplate")
                iconButton:SetSize(iconSize, iconSize)
                iconButton:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 
                    currentCol * (iconSize + spacing), -currentRow * (iconSize + spacing))
                
                -- Icon texture
                local iconTexture = iconButton:CreateTexture(nil, "ARTWORK")
                iconTexture:SetAllPoints(iconButton)
                iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if iconData.iconTexture then
                    iconTexture:SetTexture(iconData.iconTexture)
                else
                    iconTexture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                
                iconButton.iconTexture = iconTexture
                
                -- Border for customization indicator
                local border = CreateFrame("Frame", nil, iconButton, "BackdropTemplate")
                border:SetAllPoints(iconButton)
                border:SetBackdrop({
                    edgeFile = FLAT,
                    edgeSize = 2,
                })
                border:SetBackdropBorderColor(0, 0, 0, 0) -- Hidden by default
                border:Hide()
                iconButton.customBorder = border
                
                -- [PER-VIEWER] 뷰어별 고유 키: DB 복합키와 동일 형식
                local iconKey = tostring(iconData.spellID) .. "_" .. category.key

                -- Show blue border if customized (뷰어별 독립 체크)
                if IsSpellCustomized(iconData.spellID, category.key) then
                    border:SetBackdropBorderColor(0.2, 0.6, 1, 1) -- Blue
                    border:Show()
                end

                -- Highlight border for selected (뷰어별 고유 키로 비교)
                if uiState.selectedKey == iconKey then
                    border:SetBackdropBorderColor(1, 1, 0, 1) -- Yellow for selected
                    border:Show()
                end

                -- Click handler
                iconButton:SetScript("OnClick", function(self)
                    uiState.selectedSpellID = iconData.spellID
                    uiState.selectedKey = iconKey
                    uiState.selectedViewerType = category.key -- [PER-VIEWER]
                    RefreshGUI()
                end)
                
                -- Tooltip
                iconButton:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(iconData.spellID)
                    GameTooltip:Show()
                end)
                iconButton:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                end)
                
                iconButton.spellData = iconData
                
                currentCol = currentCol + 1
                if currentCol >= iconsPerRow then
                    currentCol = 0
                    currentRow = currentRow + 1
                end
            end
            
            local gridHeight = (math.ceil(#icons / iconsPerRow)) * (iconSize + spacing)
            gridFrame:SetHeight(gridHeight)
            
            table.insert(parentFrame.widgets, gridFrame)
            yOffset = yOffset + gridHeight + 20
        end
    end
    
    -- Configuration panel for selected spell
    if uiState.selectedSpellID then
        local selectedSpellData = nil
        local selectedCategory = nil
        -- [PER-VIEWER] selectedKey(복합키)로 정확한 뷰어 매칭
        for _, category in ipairs(categories) do
            for _, iconData in ipairs(uiState.scannedIcons[category.key] or {}) do
                local iconKey = tostring(iconData.spellID) .. "_" .. category.key
                if iconKey == uiState.selectedKey then
                    selectedSpellData = iconData
                    selectedCategory = category.key
                    break
                end
            end
            if selectedSpellData then break end
        end
        
        if selectedSpellData then
            yOffset = yOffset + 20
            
            -- Preview icon
            local previewIcon = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
            previewIcon:SetSize(48, 48)
            previewIcon:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 10, -yOffset)
            CreateBackdrop(previewIcon, THEME.bgDark, THEME.border)
            
            local previewTexture = previewIcon:CreateTexture(nil, "ARTWORK")
            previewTexture:SetAllPoints(previewIcon)
            previewTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if selectedSpellData.iconTexture then
                previewTexture:SetTexture(selectedSpellData.iconTexture)
            end
            table.insert(parentFrame.widgets, previewIcon)
            
            -- Editing header
            local editingHeader = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            StyleFontString(editingHeader)
            local globalFontPath = DDingUI:GetGlobalFont()
            if globalFontPath then
                editingHeader:SetFont(globalFontPath, 14, "OUTLINE")
            end
            editingHeader:SetPoint("LEFT", previewIcon, "RIGHT", 10, 0)
            editingHeader:SetPoint("TOP", previewIcon, "TOP", 0, 0)
            editingHeader:SetText(string.format(L["Editing: %s"] or "Editing: %s", selectedSpellData.spellName))
            editingHeader:SetTextColor(1, 1, 0.2, 1)
            table.insert(parentFrame.widgets, editingHeader)
            
            yOffset = yOffset + 60
            
            -- Get current customization settings (뷰어별 독립)
            local custom = GetSpellCustomization(uiState.selectedSpellID, uiState.selectedViewerType)
            local db = DDingUI.db.profile.iconCustomization
            db.spells = db.spells or {}
            -- [PER-VIEWER] 복합키: spellID_viewerType
            local spellKey = tostring(uiState.selectedSpellID) .. "_" .. (uiState.selectedViewerType or selectedCategory)
            
            -- Deselect button
            local deselectButton = CreateFrame("Button", nil, parentFrame, "BackdropTemplate")
            deselectButton:SetHeight(28)
            deselectButton:SetWidth(120)
            deselectButton:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 10, -yOffset)
            CreateBackdrop(deselectButton, THEME.accent, THEME.border)
            
            local deselectLabel = deselectButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            StyleFontString(deselectLabel)
            deselectLabel:SetPoint("CENTER")
            deselectLabel:SetText(L["Deselect"] or "Deselect")
            deselectLabel:SetTextColor(1, 1, 1, 1)
            
            deselectButton:SetScript("OnClick", function(self)
                uiState.selectedSpellID = nil
                uiState.selectedKey = nil
                uiState.selectedViewerType = nil
                RefreshGUI()
            end)
            table.insert(parentFrame.widgets, deselectButton)
            
            -- Reset Icon button
            local resetButton = CreateFrame("Button", nil, parentFrame, "BackdropTemplate")
            resetButton:SetHeight(28)
            resetButton:SetWidth(120)
            resetButton:SetPoint("LEFT", deselectButton, "RIGHT", 10, 0)
            CreateBackdrop(resetButton, THEME.accent, THEME.border)
            
            local resetLabel = resetButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            StyleFontString(resetLabel)
            resetLabel:SetPoint("CENTER")
            resetLabel:SetText(L["Reset Icon"] or "Reset Icon")
            resetLabel:SetTextColor(1, 1, 1, 1)
            
            resetButton:SetScript("OnClick", function(self)
                -- Save before clearing
                local resetSpellID = uiState.selectedSpellID
                local resetViewerType = uiState.selectedViewerType

                -- [PER-VIEWER] 해당 뷰어의 프레임만 글로우 제거
                if resetSpellID then
                    for frame, _ in pairs(hookedFrames) do
                        if frame and not frame:IsForbidden() then
                            local fd = GetFrameData(frame)
                            local frameSpellID = fd.cachedSpellID or GetSpellIDFromIcon(frame)
                            local frameVT = fd.viewerType or nil
                            if frameSpellID == resetSpellID and frameVT == resetViewerType then
                                HideReadyGlow(frame)
                            end
                        end
                    end
                end

                db.spells[spellKey] = nil
                uiState.selectedSpellID = nil
                uiState.selectedKey = nil
                uiState.selectedViewerType = nil
                RefreshAllReadyGlows()
                RefreshGUI()
            end)
            table.insert(parentFrame.widgets, resetButton)
            
            yOffset = yOffset + 40
            
            -- Ready State Glow toggle
            if Widgets and Widgets.CreateToggle then
                local glowToggle = Widgets.CreateToggle(parentFrame, {
                    name = L["Ready State Glow"] or "Ready State Glow",
                    get = function() return custom.readyGlow == true end,
                    set = function(_, val)
                        db.spells[spellKey] = db.spells[spellKey] or {}
                        db.spells[spellKey].readyGlow = val or nil
                        if val then
                            -- Find and hook the icon frame for this spell
                            FindAndHookIconForSpell(uiState.selectedSpellID)
                        else
                            -- [PER-VIEWER] 해당 뷰어의 프레임만 글로우 제거
                            for frame, _ in pairs(hookedFrames) do
                                if frame and not frame:IsForbidden() then
                                    local fd = GetFrameData(frame)
                                    local frameSpellID = fd.cachedSpellID or GetSpellIDFromIcon(frame)
                                    local frameVT = fd.viewerType or nil
                                    if frameSpellID == uiState.selectedSpellID and frameVT == uiState.selectedViewerType then
                                        HideReadyGlow(frame)
                                    end
                                end
                            end
                            db.spells[spellKey] = nil
                        end
                        -- Refresh (뷰어별)
                        RefreshAllReadyGlows(false, uiState.selectedSpellID, uiState.selectedViewerType)
                    end,
                }, yOffset, {})
                table.insert(parentFrame.widgets, glowToggle)
                yOffset = yOffset + 35
            end

            -- Glow Trigger select (ready vs active)
            -- Default based on category: Buff → "active", Essential/Utility → "ready"
            local defaultTrigger = (selectedCategory == "Buff") and "active" or "ready"
            if Widgets and Widgets.CreateSelect then
                local glowTriggerSelect = Widgets.CreateSelect(parentFrame, {
                    name = L["Glow Trigger"] or "Glow Trigger",
                    values = {
                        ["ready"] = L["When Ready (Cooldown)"] or "When Ready (Cooldown)",
                        ["active"] = L["When Active (Buff)"] or "When Active (Buff)",
                    },
                    get = function() return custom.glowTrigger or defaultTrigger end,
                    set = function(_, val)
                        db.spells[spellKey] = db.spells[spellKey] or {}
                        db.spells[spellKey].glowTrigger = val
                        RefreshAllReadyGlows(true, uiState.selectedSpellID, uiState.selectedViewerType)
                        RefreshGUI()
                    end,
                }, yOffset, nil, nil, nil)
                table.insert(parentFrame.widgets, glowTriggerSelect)
                yOffset = yOffset + 40
            end

            -- Glow Type select (always visible)
            if Widgets and Widgets.CreateSelect then
                local glowTypeSelect = Widgets.CreateSelect(parentFrame, {
                    name = L["Glow Type"] or "Glow Type",
                    values = {
                        ["button"] = L["Action Button Glow"] or "Action Button Glow",
                        ["pixel"] = L["Pixel Glow"] or "Pixel Glow",
                        ["autocast"] = L["Autocast Shine"] or "Autocast Shine",
                        ["proc"] = L["Proc Effect"] or "Proc Effect",
                    },
                    get = function() return custom.glowType or "button" end,
                    set = function(_, val)
                        db.spells[spellKey] = db.spells[spellKey] or {}
                        db.spells[spellKey].glowType = val
                        -- 강제 새로고침으로 글로우 타입 변경 즉시 반영
                        RefreshAllReadyGlows(true, uiState.selectedSpellID, uiState.selectedViewerType)
                        RefreshGUI()
                    end,
                }, yOffset, nil, nil, nil)
                table.insert(parentFrame.widgets, glowTypeSelect)
                yOffset = yOffset + 40
            end
            
            -- Glow Color (always visible)
            if Widgets and Widgets.CreateColor then
                local glowColor = Widgets.CreateColor(parentFrame, {
                    name = L["Glow Color"] or "Glow Color",
                    get = function()
                        local color = custom.glowColor or {r = 1, g = 0.85, b = 0.1}
                        return color.r or 1, color.g or 0.85, color.b or 0.1
                    end,
                    set = function(_, r, g, b)
                        db.spells[spellKey] = db.spells[spellKey] or {}
                        db.spells[spellKey].glowColor = {r = r, g = g, b = b}
                        -- 강제 새로고침으로 색상 변경 즉시 반영
                        RefreshAllReadyGlows(true, uiState.selectedSpellID, uiState.selectedViewerType)
                    end,
                }, yOffset, {})
                table.insert(parentFrame.widgets, glowColor)
                yOffset = yOffset + 35
            end
            
            -- Glow Frequency/Speed (always visible - proc glow just won't use it)
            if Widgets and Widgets.CreateRange then
                local glowSpeedRange = Widgets.CreateRange(parentFrame, {
                    name = L["Glow Frequency"] or "Glow Frequency",
                    get = function() return custom.glowSpeed or 0.25 end,
                    set = function(_, val)
                        db.spells[spellKey] = db.spells[spellKey] or {}
                        db.spells[spellKey].glowSpeed = val
                        -- 강제 새로고침으로 속도 변경 즉시 반영
                        RefreshAllReadyGlows(true, uiState.selectedSpellID, uiState.selectedViewerType)
                    end,
                    min = 0.05,
                    max = 1.0,
                    step = 0.05,
                }, yOffset, {})
                table.insert(parentFrame.widgets, glowSpeedRange)
                yOffset = yOffset + 35
            end
            
            -- Glow Lines (always visible - pixel glow only, but show for all)
            if Widgets and Widgets.CreateRange then
                local glowLinesRange = Widgets.CreateRange(parentFrame, {
                    name = L["Line Amount"] or "Line Amount",
                    get = function() return custom.glowLines or 8 end,
                    set = function(_, val)
                        db.spells[spellKey] = db.spells[spellKey] or {}
                        db.spells[spellKey].glowLines = val
                        -- 강제 새로고침으로 라인 수 변경 즉시 반영
                        RefreshAllReadyGlows(true, uiState.selectedSpellID, uiState.selectedViewerType)
                    end,
                    min = 1,
                    max = 16,
                    step = 1,
                }, yOffset, {})
                table.insert(parentFrame.widgets, glowLinesRange)
                yOffset = yOffset + 35
            end
            
            -- Glow Thickness (always visible - pixel glow only, but show for all)
            if Widgets and Widgets.CreateRange then
                local glowThicknessRange = Widgets.CreateRange(parentFrame, {
                    name = L["Line Thickness"] or "Line Thickness",
                    get = function() return custom.glowThickness or 2 end,
                    set = function(_, val)
                        db.spells[spellKey] = db.spells[spellKey] or {}
                        db.spells[spellKey].glowThickness = val
                        -- 강제 새로고침으로 두께 변경 즉시 반영
                        RefreshAllReadyGlows(true, uiState.selectedSpellID, uiState.selectedViewerType)
                    end,
                    min = 1,
                    max = 10,
                    step = 1,
                }, yOffset, {})
                table.insert(parentFrame.widgets, glowThicknessRange)
                yOffset = yOffset + 35
            end
        end
    end

    -- Add extra bottom padding for scroll accessibility
    local bottomPadding = 100
    parentFrame:SetHeight(math.max(yOffset + bottomPadding, 400))
end

-- Apply customizations to viewer icons
function IconCustomization:ApplySpellCustomization(iconFrame, spellID)
    if not iconFrame or not spellID then return end

    local viewerType = GetViewerType(iconFrame)
    local custom = GetSpellCustomization(spellID, viewerType)
    if not custom or not IsSpellCustomized(spellID, viewerType) then return end

    if NeedsRuntimeHook(custom) then
        HookCooldownFrame(iconFrame)
        UpdateReadyGlow(iconFrame)
    end
end

function IconCustomization:ApplyDynamicIconState(frame, settings, active, ready)
    if not frame or type(settings) ~= "table" then return end
    GetFrameData(frame).dynamicIcon = true
    local onCooldown = active ~= true and ready ~= true
    ApplyNativeStateAppearance(frame, settings, active == true, onCooldown, false)
    UpdateNativeStateSounds(frame, settings, active == true, onCooldown)

    local cooldown = frame.cooldown or frame.Cooldown
    local mode = settings.activeSwipeMode
    if cooldown and active == true then
        if mode == "hidden" then
            if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(false) end
        elseif mode == "class" or mode == "custom" then
            local color = mode == "class"
                and GetPlayerClassColor()
                or NormalizeColor(settings.activeSwipeColor)
            if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(true) end
            if cooldown.SetSwipeColor then
                cooldown:SetSwipeColor(color[1], color[2], color[3], color[4])
            end
        end
    end
end

-- Hook an icon frame for ready glow
function IconCustomization:HookIconFrame(iconFrame)
    if not iconFrame then return end
    local spellID = GetSpellIDFromIcon(iconFrame)
    if not spellID then return end

    local viewerType = GetViewerType(iconFrame)
    local custom = GetSpellCustomization(spellID, viewerType)
    if NeedsRuntimeHook(custom) then
        HookCooldownFrame(iconFrame)
        UpdateReadyGlow(iconFrame)
    end
end

-- Initialize hooks - hook into SkinIcon to hook new icons
function IconCustomization:Initialize()
    if self.__initialized then return end
    self.__initialized = true
    
    -- Hook into IconViewers.SkinIcon to hook new icons as they're created
    if DDingUI.IconViewers and DDingUI.IconViewers.SkinIcon then
        local originalSkinIcon = DDingUI.IconViewers.SkinIcon
        function DDingUI.IconViewers:SkinIcon(icon, settings)
            local effectiveSettings = BuildEffectiveSkinSettings(icon, settings)
            local result = originalSkinIcon(self, icon, effectiveSettings)
            ApplyExplicitSkinVisibility(icon, effectiveSettings)
            IconCustomization:ApplyThresholdFormatter(
                icon and (icon.Cooldown or icon.cooldown),
                ResolveIconCustomization(icon)
            )
            
            -- Hook the icon for ready glow if it has customization
            if icon and (icon.icon or icon.Icon) and icon.Cooldown then
                IconCustomization:HookIconFrame(icon)
            end
            
            return result
        end
    end
    
    -- Hook existing icons in viewers
    C_Timer.After(1.0, function()
        local viewers = DDingUI.viewers or {
            "EssentialCooldownViewer",
            "UtilityCooldownViewer",
            "BuffIconCooldownViewer",
        }
        
        for _, viewerName in ipairs(viewers) do
            local viewer = _G[viewerName]
            -- [REPARENT] itemFramePool:EnumerateActive()로 전환
            if viewer and viewer.itemFramePool then
                for child in viewer.itemFramePool:EnumerateActive() do
                    if child and child.Cooldown then
                        IconCustomization:HookIconFrame(child)
                    end
                end
            end
        end
    end)
    
    -- Register events to refresh glow when cooldowns/buffs update
    if not self.__eventFrame then
        self.__eventFrame = CreateFrame("Frame")
        self.__eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self.__eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        self.__eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        self.__eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        self.__eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        self.__eventFrame:SetScript("OnEvent", function(self, event, unit)
            if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
                -- Clear all cached spellIDs (frames are reused for different spells)
                for frame, _ in pairs(hookedFrames) do
                    if frame and not frame:IsForbidden() then
                        local fd = FrameData[frame]
                        ApplyNativeStateAppearance(frame, nil, false, false, true)
                        if fd then
                            fd.cachedSpellID = nil
                            fd.viewerType = nil
                            fd.lastSoundActive = nil
                            fd.lastSoundOnCooldown = nil
                        end
                        HideReadyGlow(frame)
                    end
                end
                -- [FIX] 다단계 재시도: CDM 뷰어 재생성 대기
                local function RehookAllViewers()
                    local viewers = DDingUI.viewers or {
                        "EssentialCooldownViewer",
                        "UtilityCooldownViewer",
                        "BuffIconCooldownViewer",
                    }
                    for _, viewerName in ipairs(viewers) do
                        local viewer = _G[viewerName]
                        -- [REPARENT] itemFramePool:EnumerateActive()로 전환
                        if viewer and viewer.itemFramePool then
                            for child in viewer.itemFramePool:EnumerateActive() do
                                if child and child.Cooldown then
                                    -- Re-read spellID from frame
                                    local fd = FrameData[child]
                                    if fd then fd.cachedSpellID = nil end
                                    IconCustomization:HookIconFrame(child)
                                end
                            end
                        end
                    end
                    RefreshAllReadyGlows()
                end
                C_Timer.After(0.5, RehookAllViewers)
                C_Timer.After(1.5, RehookAllViewers)
                C_Timer.After(3.0, RehookAllViewers)
                return
            end
            RefreshAllReadyGlows()
        end)
    end
end

-- Initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        IconCustomization:Initialize()
        initFrame:UnregisterAllEvents()
    end
end)

-- Debug slash command: /ddingdebug
SLASH_DDINGUIDEBUG1 = "/ddingdebug"
SlashCmdList["DDINGUIDEBUG"] = function(msg)
    print(((SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: ") .. "Scanning buff icons...") -- [STYLE]

    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then
        print("  |cffff0000BuffIconCooldownViewer not found|r")
        return
    end

    print("  BuffIconCooldownViewer: found, shown=" .. tostring(viewer:IsShown()))
    print("  viewerFrame: " .. (viewer.viewerFrame and "exists" or "nil"))
    print("  itemFramePool: " .. (viewer.itemFramePool and "exists" or "nil"))

    -- [REPARENT] itemFramePool:EnumerateActive()로 전환
    local children = {}
    if viewer.itemFramePool then
        for child in viewer.itemFramePool:EnumerateActive() do
            children[#children + 1] = child
        end
    end
    print("  Active icon count: " .. #children)

    for i, child in ipairs(children) do
        if child and child.Cooldown then
            local spellID = GetSpellIDFromIcon(child)
            local viewerType = GetViewerType(child)
            local buffActive = IsBuffActiveForIcon(child)  -- Uses IsShown(), SECRET-SAFE
            local custom = spellID and GetSpellCustomization(spellID, viewerType) or {}
            local glowEnabled = custom.readyGlow == true
            local glowTrigger = custom.glowTrigger or (viewerType == "Buff" and "active" or "ready")

            local spellName = spellID and C_Spell.GetSpellName(spellID) or "Unknown"
            print(string.format("  [%d] %s (ID:%s) viewerType=%s buffActive=%s glowEnabled=%s trigger=%s",
                i,
                tostring(spellName),
                tostring(spellID or "nil"),
                tostring(viewerType or "nil"),
                tostring(buffActive),
                tostring(glowEnabled),
                tostring(glowTrigger)
            ))
        end
    end

    print(((SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: ") .. "Done.") -- [STYLE]
end
