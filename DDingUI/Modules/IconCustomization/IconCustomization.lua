local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local SL = _G.DDingUI_StyleLib -- [12.0.1]
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
    local db = DDingUI.db.profile.iconCustomization or {}
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

-- Check if a spell is customized
local function IsSpellCustomized(spellID, viewerType)
    local custom = GetSpellCustomization(spellID, viewerType)
    return custom.readyGlow ~= nil
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
    pcall(SL.HideButtonGlow, frame)
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then pcall(LCG.ProcGlow_Stop, frame, glowKey) end
end

-- Check if glow should be shown for a spell
-- viewerType: "Essential"/"Utility"/"Buff" — 뷰어별 독립 체크
local function ShouldShowReadyGlow(spellID, viewerType)
    if not spellID then return false end

    local custom = GetSpellCustomization(spellID, viewerType)
    -- STRICT CHECK: readyGlow must be explicitly boolean true
    if not custom or custom.readyGlow ~= true then
        return false
    end

    return true
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
    if not custom or custom.readyGlow ~= true then
        frameData.readyGlowActive = false
        return
    end

    -- Get glow settings with defaults
    local glowType = custom.glowType or "button"
    local glowColor = custom.glowColor or {r = 1, g = 0.85, b = 0.1}
    local glowSpeed = custom.glowSpeed or 0.25
    local glowLines = math.floor(custom.glowLines or 8)  -- must be integer
    local glowThickness = custom.glowThickness or 2

    -- Convert color to table format
    local color = {glowColor.r or 1, glowColor.g or 0.85, glowColor.b or 0.1, 1}

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
        pcall(SL.ShowButtonGlow, frame, color, glowSpeed)
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
    if cooldownVisible and cooldownInfo and not cooldownInfo.isOnGCD then
        return true
    end
    
    -- If cooldown is NOT visible, or if it's just GCD, treat as ready (not on cooldown)
    return false
end

-- Update glow state for an icon frame
local function UpdateReadyGlow(iconFrame)
    if not iconFrame then return end

    local iconData = GetFrameData(iconFrame)

    -- Always read fresh spellID from frame (CDM may reuse frames for different spells)
    local spellID = GetSpellIDFromIcon(iconFrame)
    if not spellID then
        -- Spell gone from this frame — clear cache and hide glow
        if iconData.readyGlowActive then
            HideReadyGlow(iconFrame)
        end
        iconData.cachedSpellID = nil
        return
    end
    if spellID ~= iconData.cachedSpellID then
        -- Spell changed on this frame - hide old glow and reset state
        if iconData.readyGlowActive then
            HideReadyGlow(iconFrame)
        end
        iconData.cachedSpellID = spellID
    end

    -- [PER-VIEWER] 뷰어 타입 캐시 (한 번만 조회)
    if iconData.viewerType == nil then
        iconData.viewerType = GetViewerType(iconFrame) or false
    end
    local viewerType = iconData.viewerType or nil -- false → nil

    if not ShouldShowReadyGlow(spellID, viewerType) then
        if iconData.readyGlowActive then
            HideReadyGlow(iconFrame)
        end
        return
    end

    -- Get customization to check glowTrigger setting (뷰어별)
    local custom = GetSpellCustomization(spellID, viewerType)

    -- Determine glowTrigger: use saved value, or default based on viewer type
    local glowTrigger = custom and custom.glowTrigger
    if not glowTrigger then
        -- Default: Buff viewer → "active", others → "ready"
        glowTrigger = (iconData.viewerType == "Buff") and "active" or "ready"
    end

    local shouldGlow = false

    if glowTrigger == "active" then
        -- For "active" trigger: Show glow when buff IS active
        -- Uses IsShown() instead of spellID lookup - SECRET-SAFE during combat!
        shouldGlow = IsBuffActiveForIcon(iconFrame)
    else
        -- For "ready" trigger (default): Show glow when NOT on cooldown
        shouldGlow = not IsSpellOnCooldown(iconFrame)
    end

    -- Only update if state actually changed (prevent flashing)
    if shouldGlow then
        if not iconData.readyGlowActive then
            ShowReadyGlow(iconFrame, spellID, viewerType)
        end
    else
        if iconData.readyGlowActive then
            HideReadyGlow(iconFrame)
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
                HideReadyGlow(iconFrame)
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
                if child and child.cooldownID and child.Cooldown then
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

-- Refresh all icons with ready glow customizations
-- forceRefresh: true면 활성화된 글로우도 강제로 재적용 (설정 변경 시)
-- targetSpellID: 특정 스펠만 새로고침 (nil이면 전체)
-- targetViewerType: 특정 뷰어만 새로고침 (nil이면 전체)
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

            -- Always read fresh spellID (CDM may reuse frames for different spells)
            local freshID = GetSpellIDFromIcon(frame)
            if not freshID then
                -- Spell gone from this frame — clear cache and hide glow
                if frameData.readyGlowActive then
                    HideReadyGlow(frame)
                end
                frameData.cachedSpellID = nil
            else
                if freshID ~= frameData.cachedSpellID then
                    -- Spell changed on this frame - hide old glow
                    if frameData.readyGlowActive then
                        HideReadyGlow(frame)
                    end
                    frameData.cachedSpellID = freshID
                end

                -- targetSpellID/targetViewerType 필터
                if targetSpellID and freshID ~= targetSpellID then
                    -- skip: 다른 스펠
                elseif targetViewerType and viewerType ~= targetViewerType then
                    -- skip: 다른 뷰어
                else
                    -- Check if glow should be shown (뷰어별)
                    if ShouldShowReadyGlow(freshID, viewerType) then
                        -- forceRefresh면 기존 글로우 숨기고 재적용
                        if forceRefresh and frameData.readyGlowActive then
                            HideReadyGlow(frame)
                            -- 바로 재적용
                            ShowReadyGlow(frame, freshID, viewerType)
                        else
                            UpdateReadyGlow(frame)
                        end
                    else
                        -- Hide glow if customization was removed
                        if frameData.readyGlowActive then
                            HideReadyGlow(frame)
                        end
                    end
                end
            end
        end
    end
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

    -- Hook cooldown frame for ready glow
    if custom.readyGlow == true then
        HookCooldownFrame(iconFrame)
    end
end

-- Hook an icon frame for ready glow
function IconCustomization:HookIconFrame(iconFrame)
    if not iconFrame then return end
    local spellID = GetSpellIDFromIcon(iconFrame)
    if not spellID then return end

    local viewerType = GetViewerType(iconFrame)
    local custom = GetSpellCustomization(spellID, viewerType)
    if custom.readyGlow == true then
        HookCooldownFrame(iconFrame)
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
            local result = originalSkinIcon(self, icon, settings)
            
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
                    if child and child.cooldownID and child.Cooldown then
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
                        if fd then
                            fd.cachedSpellID = nil
                            fd.viewerType = nil
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
                                if child and child.cooldownID and child.Cooldown then
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
        if child and child.cooldownID and child.Cooldown then
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
