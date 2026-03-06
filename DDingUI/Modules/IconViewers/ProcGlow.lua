local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

DDingUI.ProcGlow = DDingUI.ProcGlow or {}
local ProcGlow = DDingUI.ProcGlow

-- StyleLib v2 GlowEffects
local SL = _G.DDingUI_StyleLib

-- Track which icons currently have active glows
local activeGlowingIcons = {}  -- [icon] = true

-- Track by spellID to survive frame recycling/rescan
local activeOverlaySpells = {}  -- [spellID] = true

-- [REFACTOR] Weak tables to avoid tainting Blizzard CooldownViewer icon frames
-- Writing custom fields directly onto secure frames causes taint propagation →
-- secret boolean errors (allowAvailableAlert) when entering EditMode.
local viewerNameCache = setmetatable({}, { __mode = "k" })   -- replaces iconFrame._DDingUIViewerName
local glowActiveCache = setmetatable({}, { __mode = "k" })   -- replaces iconFrame._DDingUICustomGlowActive
local procActiveCache = setmetatable({}, { __mode = "k" })   -- replaces button._DDingUIProcActive

-- Glow key for LibCustomGlow
local GLOW_KEY = "_DDingUICustomGlow"

-- Glow persistence timers: re-apply glow if removed externally
local glowPersistenceTimers = {}  -- [icon] = ticker

-- LibCustomGlow glow types
ProcGlow.LibCustomGlowTypes = {
    "Pixel Glow",
    "Autocast Shine",
    "Action Button Glow",
    "Proc Glow",
    "Blizzard Glow",
}

-- Get spellID from a CDM button frame
local function GetButtonSpellID(button)
    if not button then return nil end
    if button.spellID then return button.spellID end
    if button.cooldownID then return button.cooldownID end
    if button.GetSpellID and type(button.GetSpellID) == "function" then
        local ok, sid = pcall(button.GetSpellID, button)
        if ok and sid and sid > 0 then return sid end
    end
    return nil
end

-- Viewer name list
local viewerNames = DDingUI.viewers or {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

-- Get viewer name for an icon frame (walk parent chain)
local function GetViewerNameForIcon(button)
    if not button then return nil end
    -- [FIX] GroupSystem reparent 후 부모 체인 끊김 대응
    -- GroupRenderer가 태그한 원본 뷰어 이름 우선 사용
    if button._ddSourceViewer then
        return button._ddSourceViewer
    end
    local currentParent = button
    for _ = 1, 6 do
        currentParent = currentParent:GetParent()
        if not currentParent then return nil end
        local parentName = currentParent:GetName()
        if parentName then
            for _, vName in ipairs(viewerNames) do
                if parentName == vName then
                    return vName
                end
            end
        end
    end
    return nil
end

-- Check if a button belongs to one of our cooldown viewer frames
local function IsCooldownViewerIcon(button)
    return GetViewerNameForIcon(button) ~= nil
end

-- Check if a frame is a cooldown icon (same logic as IconViewers)
local function IsCooldownIconFrame(frame)
    return frame and (frame.icon or frame.Icon) and frame.Cooldown
end

-- Get proc glow settings for a specific icon (reads from its viewer's settings)
local function GetProcGlowSettings(iconFrame)
    local viewers = DDingUI.db.profile.viewers
    if not viewers then return nil end

    -- If icon provided, get its specific viewer's settings
    if iconFrame then
        local vName = viewerNameCache[iconFrame] or GetViewerNameForIcon(iconFrame)
        if vName then
            viewerNameCache[iconFrame] = vName  -- cache for performance
            local vs = viewers[vName]
            if vs and vs.procGlow and vs.procGlow.enabled then
                return vs.procGlow
            end
            return nil
        end
    end

    -- No icon: check if ANY viewer has proc glow enabled (for RefreshAll etc.)
    for _, vName in ipairs(viewerNames) do
        local vs = viewers[vName]
        if vs and vs.procGlow and vs.procGlow.enabled then
            return vs.procGlow
        end
    end
    return nil
end

-- Hide Blizzard's glow effects (simple Hide)
local function HideBlizzardGlow(iconFrame)
    if iconFrame.SpellActivationAlert then
        iconFrame.SpellActivationAlert:Hide()
        if iconFrame.SpellActivationAlert.ProcLoopFlipbook then
            iconFrame.SpellActivationAlert.ProcLoopFlipbook:Hide()
        end
        if iconFrame.SpellActivationAlert.ProcStartFlipbook then
            iconFrame.SpellActivationAlert.ProcStartFlipbook:Hide()
        end
    end
    if iconFrame.overlay then iconFrame.overlay:Hide() end
    if iconFrame.Overlay then iconFrame.Overlay:Hide() end
    if iconFrame.Glow then iconFrame.Glow:Hide() end
end

-- Check if LCG glow frame actually exists AND is visible on the icon
local function IsGlowFramePresent(iconFrame, glowType)
    local glowFrame
    if glowType == "Pixel Glow" then
        glowFrame = iconFrame["_PixelGlow" .. GLOW_KEY]
    elseif glowType == "Autocast Shine" then
        glowFrame = iconFrame["_AutoCastGlow" .. GLOW_KEY]
    elseif glowType == "Action Button Glow" then
        glowFrame = iconFrame._ButtonGlow
    elseif glowType == "Proc Glow" then
        glowFrame = iconFrame["_ProcGlow" .. GLOW_KEY]
    elseif glowType == "Blizzard Glow" then
        -- Check Blizzard's native overlay glow
        if iconFrame.overlay and iconFrame.overlay.IsShown and iconFrame.overlay:IsShown() then
            return true
        end
        if iconFrame.SpellActivationAlert and iconFrame.SpellActivationAlert.IsShown and iconFrame.SpellActivationAlert:IsShown() then
            return true
        end
        return false
    end
    if not glowFrame then return false end
    return glowFrame.IsShown and glowFrame:IsShown() or false
end

-- Apply glow effect to an icon (LCG call only, no timer management)
local function ApplyGlowEffect(iconFrame, forceRestart)
    local glowSettings = GetProcGlowSettings(iconFrame)
    if not glowSettings then return end

    local glowType = glowSettings.glowType or "Pixel Glow"
    local color = glowSettings.loopColor or {0.95, 0.95, 0.32, 1}
    if not color[4] then color[4] = 1 end

    -- Skip if glow is already active and correct type (prevents flickering from repeated calls)
    if not forceRestart and glowActiveCache[iconFrame] and IsGlowFramePresent(iconFrame, glowType) then
        return
    end

    -- Stop any existing glows first
    SL.HidePixelGlow(iconFrame, GLOW_KEY)
    SL.HideAutocastGlow(iconFrame, GLOW_KEY)
    SL.HideButtonGlow(iconFrame)
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(iconFrame, GLOW_KEY) end
    if ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(iconFrame)
    end

    if glowType == "Blizzard Glow" then
        -- Use WoW's native overlay glow
        if ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(iconFrame)
        end
    else
        if glowType == "Pixel Glow" then
            local lines = math.floor(glowSettings.lcgLines or 5)
            local frequency = glowSettings.lcgFrequency or 0.25
            local length = glowSettings.lcgLength or 8
            local thickness = glowSettings.lcgThickness or 1
            SL.ShowPixelGlow(iconFrame, color, lines, frequency, length, thickness, -1, -1, false, GLOW_KEY)
        elseif glowType == "Autocast Shine" then
            local particles = math.floor(glowSettings.autocastParticles or 8)
            local frequency = glowSettings.autocastFrequency or 0.25
            local scale = glowSettings.autocastScale or 1.0
            SL.ShowAutocastGlow(iconFrame, color, particles, frequency, scale, 0, 0, GLOW_KEY)
        elseif glowType == "Action Button Glow" then
            local frequency = glowSettings.buttonGlowFrequency or 0.25
            SL.ShowButtonGlow(iconFrame, color, frequency, GLOW_KEY)
        elseif glowType == "Proc Glow" then
            local LCG = LibStub("LibCustomGlow-1.0", true)
            if LCG and LCG.ProcGlow_Start then
                LCG.ProcGlow_Start(iconFrame, {
                    color = color, startAnim = false,
                    xOffset = 0, yOffset = 0, key = GLOW_KEY
                })
            end
        end
    end

    glowActiveCache[iconFrame] = true
    activeGlowingIcons[iconFrame] = true
end

-- Start glow on an icon with persistence timer
local function StartGlow(iconFrame)
    local glowSettings = GetProcGlowSettings(iconFrame)
    if not glowSettings then return end

    local glowType = glowSettings.glowType or "Pixel Glow"

    -- If flag says active, verify the LCG glow frame actually exists
    if glowActiveCache[iconFrame] then
        if IsGlowFramePresent(iconFrame, glowType) then return end
        glowActiveCache[iconFrame] = nil
        activeGlowingIcons[iconFrame] = nil
    end

    -- Apply the glow
    ApplyGlowEffect(iconFrame)

    -- Cancel existing persistence timer
    if glowPersistenceTimers[iconFrame] then
        glowPersistenceTimers[iconFrame]:Cancel()
        glowPersistenceTimers[iconFrame] = nil
    end

    -- Start persistence timer: checks every 0.3s if glow was removed externally
    glowPersistenceTimers[iconFrame] = C_Timer.NewTicker(0.3, function()
        if not activeGlowingIcons[iconFrame] then
            if glowPersistenceTimers[iconFrame] then
                glowPersistenceTimers[iconFrame]:Cancel()
                glowPersistenceTimers[iconFrame] = nil
            end
            return
        end

        if not iconFrame:IsShown() then return end

        local gs = GetProcGlowSettings(iconFrame)
        if not gs then return end
        local gt = gs.glowType or "Pixel Glow"
        if not IsGlowFramePresent(iconFrame, gt) then
            ApplyGlowEffect(iconFrame)
            if gt ~= "Blizzard Glow" then
                HideBlizzardGlow(iconFrame)
            end
        end
    end)
end

-- Stop glow on an icon
local function StopGlow(iconFrame)
    if not glowActiveCache[iconFrame] then return end

    -- Cancel persistence timer first
    if glowPersistenceTimers[iconFrame] then
        glowPersistenceTimers[iconFrame]:Cancel()
        glowPersistenceTimers[iconFrame] = nil
    end

    SL.HidePixelGlow(iconFrame, GLOW_KEY)
    SL.HideAutocastGlow(iconFrame, GLOW_KEY)
    SL.HideButtonGlow(iconFrame)
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(iconFrame, GLOW_KEY) end
    if ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(iconFrame)
    end

    glowActiveCache[iconFrame] = nil
    activeGlowingIcons[iconFrame] = nil
end

-- Re-apply glows after RescanViewer completes (survives frame recycling/re-skinning)
local function ReapplyGlowsAfterRescan(viewer)
    if not next(activeOverlaySpells) then return end

    local container = viewer and (viewer.viewerFrame or viewer)
    if not container or not container.GetChildren then return end

    for _, child in ipairs({ container:GetChildren() }) do
        if child and child:IsShown() and IsCooldownIconFrame(child) then
            local glowSettings = GetProcGlowSettings(child)
            if not glowSettings or not glowSettings.enabled then
                -- Settings disabled for this viewer, stop any active glow
                if glowActiveCache[child] then
                    StopGlow(child)
                end
            else
                local spellID = GetButtonSpellID(child)
                if spellID and activeOverlaySpells[spellID] then
                    local gt = glowSettings.glowType or "Pixel Glow"
                    if not glowActiveCache[child] then
                        if gt ~= "Blizzard Glow" then
                            HideBlizzardGlow(child)
                        end
                        StartGlow(child)
                    else
                        if not IsGlowFramePresent(child, gt) then
                            ApplyGlowEffect(child)
                            if gt ~= "Blizzard Glow" then
                                HideBlizzardGlow(child)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Scan all viewers for icons that already have active SpellActivationAlert
local function ScanExistingOverlays()
    for _, name in ipairs(viewerNames) do
        local viewer = _G[name]
        if viewer and viewer:IsShown() then
            local container = viewer.viewerFrame or viewer
            if container and container.GetChildren then
                for _, child in ipairs({ container:GetChildren() }) do
                    if child and child:IsShown() and IsCooldownIconFrame(child) then
                        local glowSettings = GetProcGlowSettings(child)
                        if glowSettings and glowSettings.enabled then
                            if child.SpellActivationAlert and child.SpellActivationAlert:IsShown() then
                                local spellID = GetButtonSpellID(child)
                                HideBlizzardGlow(child)
                                StartGlow(child)
                                if spellID then
                                    activeOverlaySpells[spellID] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Setup glow hooks
local function SetupGlowHooks()
    if ActionButtonSpellAlertManager then
        if ActionButtonSpellAlertManager.ShowAlert then
            hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, button)
                if not IsCooldownViewerIcon(button) then return end
                local spellID = GetButtonSpellID(button)
                local glowSettings = GetProcGlowSettings(button)
                if glowSettings and glowSettings.enabled then
                    -- BCM pattern: flag immediately, apply glow after Blizzard finishes
                    procActiveCache[button] = true
                    if glowSettings.glowType == "Blizzard Glow" then
                        -- Let Blizzard's native glow show, just track it
                        glowActiveCache[button] = true
                        activeGlowingIcons[button] = true
                    else
                        HideBlizzardGlow(button)
                        C_Timer.After(0, function()
                            if procActiveCache[button] then
                                StartGlow(button)
                                HideBlizzardGlow(button)
                            end
                        end)
                    end
                    -- Track by spellID for rescan survival
                    if spellID then
                        activeOverlaySpells[spellID] = true
                    end
                end
            end)
        end

        if ActionButtonSpellAlertManager.HideAlert then
            hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, button)
                if not IsCooldownViewerIcon(button) then return end
                local spellID = GetButtonSpellID(button)
                procActiveCache[button] = nil
                StopGlow(button)
                -- Untrack by spellID
                if spellID then
                    activeOverlaySpells[spellID] = nil
                end
            end)
        end
    end

    -- Hook RescanViewer to re-apply glows after viewer rescan completes
    local IconViewers = DDingUI.IconViewers
    if IconViewers and IconViewers.RescanViewer then
        hooksecurefunc(IconViewers, "RescanViewer", function(_, viewer)
            -- Delay slightly to let SkinIcon and layout changes settle
            C_Timer.After(0.15, function()
                if viewer and viewer.IsShown and viewer:IsShown() then
                    ReapplyGlowsAfterRescan(viewer)
                end
            end)
        end)
    end

    -- Hook SkinIcon to re-apply glow after reskinning
    if IconViewers and IconViewers.SkinIcon then
        hooksecurefunc(IconViewers, "SkinIcon", function(_, icon)
            if icon and procActiveCache[icon] then
                C_Timer.After(0.02, function()
                    if procActiveCache[icon] and icon:IsShown() then
                        ApplyGlowEffect(icon)
                        HideBlizzardGlow(icon)
                    end
                end)
            end
        end)
    end

    -- Scan for already-active overlays
    ScanExistingOverlays()
end

-- Track if hooks have been set up
local hooksInitialized = false

-- Initialize the module
function ProcGlow:Initialize()
    if hooksInitialized then return end
    hooksInitialized = true

    if ActionButtonSpellAlertManager then
        SetupGlowHooks()
    else
        C_Timer.After(0.3, function()
            SetupGlowHooks()
        end)
    end
end

-- Refresh all proc glows (viewers only)
function ProcGlow:RefreshAll()
    -- Stop all current glows first
    local iconsWithProcs = {}
    for icon, _ in pairs(activeGlowingIcons) do
        if icon then
            local spellID = GetButtonSpellID(icon)
            if spellID then
                iconsWithProcs[icon] = spellID
            end
            StopGlow(icon)
        end
    end
    wipe(activeGlowingIcons)

    -- Re-apply glows for icons whose viewer still has proc glow enabled
    for icon, spellID in pairs(iconsWithProcs) do
        if icon and icon:IsShown() then
            local glowSettings = GetProcGlowSettings(icon)
            if glowSettings and glowSettings.enabled then
                StartGlow(icon)
            end
        end
    end
end

-- Re-apply glow after SkinIcon changes (aspect ratio, etc.)
function ProcGlow:UpdateButtonGlow(icon)
    if not icon then return end
    if procActiveCache[icon] or activeGlowingIcons[icon] then
        ApplyGlowEffect(icon)
        HideBlizzardGlow(icon)
    end
end

-- Public API for starting/stopping glows (for compatibility)
function ProcGlow:StartGlow(icon)
    if not icon or not IsCooldownViewerIcon(icon) then return end
    StartGlow(icon)
end

function ProcGlow:StopGlow(icon)
    if not icon or not IsCooldownViewerIcon(icon) then return end
    StopGlow(icon)
end
