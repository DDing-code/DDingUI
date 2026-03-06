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

-- Get LibCustomGlow
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

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
-- Uses reference comparison for reliability (viewerFrame may not have a name)
local function GetViewerType(iconFrame)
    if not iconFrame then return nil end

    -- Known viewer frames to check
    local viewerTypes = {
        { viewerName = "BuffIconCooldownViewer", type = "Buff" },
        { viewerName = "EssentialCooldownViewer", type = "Essential" },
        { viewerName = "UtilityCooldownViewer", type = "Utility" },
    }

    local parent = iconFrame:GetParent()
    for i = 1, 10 do  -- Increased depth for safety
        if not parent then break end

        -- Method 1: Check by name (works when viewer is direct parent)
        local name = parent:GetName()
        if name then
            for _, v in ipairs(viewerTypes) do
                if name == v.viewerName then
                    return v.type
                end
            end
        end

        -- Method 2: Check by reference (works for viewerFrame container)
        for _, v in ipairs(viewerTypes) do
            local viewer = _G[v.viewerName]
            if viewer then
                -- Check if parent is the viewer or its viewerFrame
                if parent == viewer or parent == viewer.viewerFrame then
                    return v.type
                end
            end
        end

        parent = parent:GetParent()
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
    
    local container = viewer.viewerFrame or viewer
    local icons = {}
    local spellMap = {} -- Track unique spells by ID
    
    for _, child in ipairs(GetCachedChildren(container)) do
        if child and (child.icon or child.Icon) and child.Cooldown then
            local spellID = GetSpellIDFromIcon(child)
            if spellID and not spellMap[spellID] then
                spellMap[spellID] = true

                local spellInfo = C_Spell.GetSpellInfo(spellID)
                if spellInfo then
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
local function GetSpellCustomization(spellID)
    local db = DDingUI.db.profile.iconCustomization or {}
    db.spells = db.spells or {}
    return db.spells[tostring(spellID)] or {}
end

-- Check if a spell is customized
local function IsSpellCustomized(spellID)
    local custom = GetSpellCustomization(spellID)
    return custom.readyGlow ~= nil
end

-- UI state
local uiState = {
    selectedSpellID = nil,
    scannedIcons = {},
}

-- Track hooked frames for event-driven updates
local hookedFrames = {} -- [iconFrame] = true


-- READY STATE GLOW FUNCTIONS

-- Stop all glow effects on a frame
local function StopAllGlows(frame, key)
    if not frame or not LCG then return end
    local glowKey = key or "DDingUI_ReadyGlow"
    pcall(LCG.PixelGlow_Stop, frame, glowKey)
    pcall(LCG.AutoCastGlow_Stop, frame, glowKey)
    pcall(LCG.ButtonGlow_Stop, frame)
    pcall(LCG.ProcGlow_Stop, frame, glowKey)
end

-- Check if glow should be shown for a spell
local function ShouldShowReadyGlow(spellID)
    if not spellID then return false end
    
    local custom = GetSpellCustomization(spellID)
    -- STRICT CHECK: readyGlow must be explicitly boolean true
    if not custom or custom.readyGlow ~= true then
        return false
    end
    
    return true
end

-- Show ready glow with settings
local function ShowReadyGlow(frame, spellID)
    if not frame or not LCG then return end

    -- Stop any existing glow first
    StopAllGlows(frame, "DDingUI_ReadyGlow")

    local frameData = GetFrameData(frame)

    if not spellID then
        frameData.readyGlowActive = false
        return
    end

    -- Get customization settings
    local custom = GetSpellCustomization(spellID)
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
        pcall(LCG.PixelGlow_Start, frame, color, glowLines, glowSpeed, nil, glowThickness, 0, 0, true, "DDingUI_ReadyGlow")
    elseif glowType == "autocast" then
        pcall(LCG.AutoCastGlow_Start, frame, color, 4, glowSpeed, 1.0, 0, 0, "DDingUI_ReadyGlow")
    elseif glowType == "proc" then
        pcall(LCG.ProcGlow_Start, frame, {
            color = color,
            startAnim = false,
            xOffset = 0,
            yOffset = 0,
            key = "DDingUI_ReadyGlow"
        })
    else -- button (default)
        pcall(LCG.ButtonGlow_Start, frame, color, glowSpeed)
    end

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

    if not ShouldShowReadyGlow(spellID) then
        if iconData.readyGlowActive then
            HideReadyGlow(iconFrame)
        end
        return
    end

    -- Get customization to check glowTrigger setting
    local custom = GetSpellCustomization(spellID)

    -- Determine glowTrigger: use saved value, or default based on viewer type
    local glowTrigger = custom and custom.glowTrigger
    if not glowTrigger then
        -- Cache viewer type for performance
        if iconData.viewerType == nil then
            iconData.viewerType = GetViewerType(iconFrame) or false
        end
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
            ShowReadyGlow(iconFrame, spellID)
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
local function FindAndHookIconForSpell(targetSpellID)
    if not targetSpellID then return end

    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
    }

    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer then
            local container = viewer.viewerFrame or viewer
            for _, child in ipairs(GetCachedChildren(container)) do
                if child and (child.icon or child.Icon) and child.Cooldown then
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
local function RefreshAllReadyGlows(forceRefresh, targetSpellID)
    -- Loop through tracked frames
    for frame, _ in pairs(hookedFrames) do
        if frame and not frame:IsForbidden() then
            local frameData = GetFrameData(frame)
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

                -- targetSpellID가 지정되면 해당 스펠만 처리
                if targetSpellID and freshID ~= targetSpellID then
                    -- skip
                else
                    -- Check if glow should be shown
                    if ShouldShowReadyGlow(freshID) then
                        -- forceRefresh면 기존 글로우 숨기고 재적용
                        if forceRefresh and frameData.readyGlowActive then
                            HideReadyGlow(frame)
                            -- 바로 재적용
                            ShowReadyGlow(frame, freshID)
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
                
                -- Show blue border if customized
                if IsSpellCustomized(iconData.spellID) then
                    border:SetBackdropBorderColor(0.2, 0.6, 1, 1) -- Blue
                    border:Show()
                end
                
                -- Highlight border for selected
                if uiState.selectedSpellID == iconData.spellID then
                    border:SetBackdropBorderColor(1, 1, 0, 1) -- Yellow for selected
                    border:Show()
                end
                
                -- Click handler
                iconButton:SetScript("OnClick", function(self)
                    uiState.selectedSpellID = iconData.spellID
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
        for _, category in ipairs(categories) do
            for _, iconData in ipairs(uiState.scannedIcons[category.key] or {}) do
                if iconData.spellID == uiState.selectedSpellID then
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
            
            -- Get current customization settings
            local custom = GetSpellCustomization(uiState.selectedSpellID)
            local db = DDingUI.db.profile.iconCustomization
            db.spells = db.spells or {}
            local spellKey = tostring(uiState.selectedSpellID)
            
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
                -- Save the spell ID before clearing
                local resetSpellID = uiState.selectedSpellID

                -- Hide glow on any frames with this spell before deleting customization
                if resetSpellID then
                    for frame, _ in pairs(hookedFrames) do
                        if frame and not frame:IsForbidden() then
                            local frameSpellID = GetFrameData(frame).cachedSpellID or GetSpellIDFromIcon(frame)
                            if frameSpellID == resetSpellID then
                                HideReadyGlow(frame)
                            end
                        end
                    end
                end

                db.spells[spellKey] = nil
                uiState.selectedSpellID = nil
                -- Refresh all icons with this spell to remove glow
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
                            -- Clean up if false - hide glow and remove customization
                            -- First hide glow on any frames with this spell
                            for frame, _ in pairs(hookedFrames) do
                                if frame and not frame:IsForbidden() then
                                    local frameSpellID = GetFrameData(frame).cachedSpellID or GetSpellIDFromIcon(frame)
                                    if frameSpellID == uiState.selectedSpellID then
                                        HideReadyGlow(frame)
                                    end
                                end
                            end
                            db.spells[spellKey] = nil
                        end
                        -- Refresh all icons with this spell
                        RefreshAllReadyGlows()
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
                        RefreshAllReadyGlows(true, uiState.selectedSpellID)
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
                        RefreshAllReadyGlows(true, uiState.selectedSpellID)
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
                        RefreshAllReadyGlows(true, uiState.selectedSpellID)
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
                        RefreshAllReadyGlows(true, uiState.selectedSpellID)
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
                        RefreshAllReadyGlows(true, uiState.selectedSpellID)
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
                        RefreshAllReadyGlows(true, uiState.selectedSpellID)
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
    
    local custom = GetSpellCustomization(spellID)
    if not custom or not IsSpellCustomized(spellID) then return end
    
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
    
    local custom = GetSpellCustomization(spellID)
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
            if viewer then
                local container = viewer.viewerFrame or viewer
                for _, child in ipairs(GetCachedChildren(container)) do
                    if child and (child.icon or child.Icon) and child.Cooldown then
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
                -- Re-hook after CDM rebuilds icons (talent changes may add/remove spells)
                C_Timer.After(0.5, function()
                    local viewers = DDingUI.viewers or {
                        "EssentialCooldownViewer",
                        "UtilityCooldownViewer",
                        "BuffIconCooldownViewer",
                    }
                    for _, viewerName in ipairs(viewers) do
                        local viewer = _G[viewerName]
                        if viewer then
                            local container = viewer.viewerFrame or viewer
                            for _, child in ipairs({container:GetChildren()}) do
                                if child and (child.icon or child.Icon) and child.Cooldown then
                                    -- Re-read spellID from frame
                                    local fd = FrameData[child]
                                    if fd then fd.cachedSpellID = nil end
                                    IconCustomization:HookIconFrame(child)
                                end
                            end
                        end
                    end
                    RefreshAllReadyGlows()
                end)
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
    print("|cff00ff00[DDingUI Debug]|r Scanning buff icons...")

    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then
        print("  |cffff0000BuffIconCooldownViewer not found|r")
        return
    end

    print("  BuffIconCooldownViewer: found, shown=" .. tostring(viewer:IsShown()))
    print("  viewerFrame: " .. (viewer.viewerFrame and "exists" or "nil"))

    local container = viewer.viewerFrame or viewer
    local children = { container:GetChildren() }
    print("  Children count: " .. #children)

    for i, child in ipairs(children) do
        if child and (child.icon or child.Icon) and child.Cooldown then
            local spellID = GetSpellIDFromIcon(child)
            local viewerType = GetViewerType(child)
            local buffActive = IsBuffActiveForIcon(child)  -- Uses IsShown(), SECRET-SAFE
            local custom = spellID and GetSpellCustomization(spellID) or {}
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

    print("|cff00ff00[DDingUI Debug]|r Done.")
end
