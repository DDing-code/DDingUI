-- AssistHighlight Module - Assisted Combat Rotation Highlight
--
-- Highlights cooldown icons that match the assisted combat rotation suggestion.
-- Shows a highlight on icons suggested by C_AssistedCombat.GetNextCastSpell()

local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

DDingUI.AssistHighlight = DDingUI.AssistHighlight or {}
local AssistHighlight = DDingUI.AssistHighlight

-- Get LibCustomGlow for glow effects
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local GLOW_KEY = "_DDingUIAssistGlow"

-- Viewer name list
local viewerNames = DDingUI.viewers or {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

-- State
local rotationSpellsCache = {}
local rotationSpellsCacheValid = false
local currentSuggestedSpellID = nil
local isEnabled = false
local hooksInitialized = false

-- Flipbook config
local flipbookConfig = {
    atlas = "RotationHelper_Ants_Flipbook_2x",
    rows = 6,
    columns = 5,
    frames = 30,
    duration = 1.0,
}

-- Extract spellID from CDM icon (NOT secret value)
local function ExtractSpellIDFromIcon(icon)
    if icon.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, icon.cooldownID)
        if ok and info then
            return info.spellID, info.overrideSpellID
        end
    end
    return nil
end

-- Get assist highlight settings for a specific viewer
local function GetAssistSettings(viewerName)
    local viewers = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.viewers
    if not viewers then return nil end
    local vs = viewers[viewerName]
    if vs and vs.assistHighlight and vs.assistHighlight.enabled then
        return vs.assistHighlight
    end
    return nil
end

-- Check if any viewer has assist highlight enabled
local function IsEnabledForAnyViewer()
    local viewers = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.viewers
    if not viewers then return false end
    for _, vName in ipairs(viewerNames) do
        local vs = viewers[vName]
        if vs and vs.assistHighlight and vs.assistHighlight.enabled then
            return true
        end
    end
    return false
end

-- Update rotation spells cache
local function UpdateRotationSpellsCache()
    wipe(rotationSpellsCache)
    if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
        local rotationSpells = C_AssistedCombat.GetRotationSpells()
        if rotationSpells then
            for _, spellID in ipairs(rotationSpells) do
                rotationSpellsCache[spellID] = true
            end
        end
    end
    rotationSpellsCacheValid = true
end

-- Check if spell is in rotation
local function IsSpellInRotation(spellID)
    if not spellID then return false end
    if not rotationSpellsCacheValid then
        UpdateRotationSpellsCache()
    end
    return rotationSpellsCache[spellID] == true
end

-- Get viewer name for an icon frame (walk parent chain)
local function GetViewerNameForIcon(button)
    if not button then return nil end
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

-- ============================================================
-- Flipbook highlight (Blizzard style ants animation)
-- ============================================================

local function GetOrCreateFlipbookHighlight(icon)
    if icon._DDingUIAssistFlipbook then
        -- Update size on re-access
        if icon._DDingUIAssistFlipbook.Texture then
            local w, h = icon:GetSize()
            local settings = GetAssistSettings(icon._DDingUIAssistViewerName or GetViewerNameForIcon(icon))
            local scale = (settings and settings.flipbookScale) or 1.5
            icon._DDingUIAssistFlipbook.Texture:SetSize(w * scale, h * scale)
        end
        return icon._DDingUIAssistFlipbook
    end

    local frame = CreateFrame("Frame", nil, icon)
    frame:SetFrameLevel(icon:GetFrameLevel() + 10)
    frame:SetAllPoints(icon)

    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAtlas(flipbookConfig.atlas)
    tex:SetBlendMode("ADD")
    tex:SetPoint("CENTER", icon, "CENTER", 0, 0)
    local w, h = icon:GetSize()
    local settings = GetAssistSettings(icon._DDingUIAssistViewerName or GetViewerNameForIcon(icon))
    local scale = (settings and settings.flipbookScale) or 1.5
    tex:SetSize(w * scale, h * scale)
    frame.Texture = tex

    local animGroup = frame:CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    animGroup:SetToFinalAlpha(true)
    frame.Anim = animGroup

    local alphaAnim = animGroup:CreateAnimation("Alpha")
    alphaAnim:SetChildKey("Texture")
    alphaAnim:SetFromAlpha(1)
    alphaAnim:SetToAlpha(1)
    alphaAnim:SetDuration(0.001)
    alphaAnim:SetOrder(0)

    local flipAnim = animGroup:CreateAnimation("FlipBook")
    flipAnim:SetChildKey("Texture")
    flipAnim:SetDuration(flipbookConfig.duration)
    flipAnim:SetOrder(0)
    flipAnim:SetFlipBookRows(flipbookConfig.rows)
    flipAnim:SetFlipBookColumns(flipbookConfig.columns)
    flipAnim:SetFlipBookFrames(flipbookConfig.frames)
    flipAnim:SetFlipBookFrameWidth(0)
    flipAnim:SetFlipBookFrameHeight(0)
    frame.FlipAnim = flipAnim

    frame:SetAlpha(0)
    frame:Show()

    icon._DDingUIAssistFlipbook = frame
    return frame
end

local function ShowFlipbook(icon)
    local flipbook = GetOrCreateFlipbookHighlight(icon)
    flipbook:SetAlpha(1)
    if not flipbook.Anim:IsPlaying() then
        flipbook.Anim:Play()
    end
end

local function HideFlipbook(icon)
    if icon._DDingUIAssistFlipbook then
        icon._DDingUIAssistFlipbook:SetAlpha(0)
        if icon._DDingUIAssistFlipbook.Anim:IsPlaying() then
            icon._DDingUIAssistFlipbook.Anim:Stop()
        end
    end
end

-- ============================================================
-- LCG glow highlight (LibCustomGlow style)
-- ============================================================

local function ApplyLCGGlow(icon, settings)
    if not LCG then return end

    -- Stop existing assist glows
    LCG.PixelGlow_Stop(icon, GLOW_KEY)
    LCG.AutoCastGlow_Stop(icon, GLOW_KEY)
    LCG.ProcGlow_Stop(icon, GLOW_KEY)
    LCG.ButtonGlow_Stop(icon)

    local glowType = settings.glowType or "Pixel Glow"
    local color = settings.color or {0.3, 0.7, 1.0, 1}
    if not color[4] then color[4] = 1 end

    if glowType == "Pixel Glow" then
        local lines = math.floor(settings.lcgLines or 5)
        local frequency = settings.lcgFrequency or 0.25
        local length = settings.lcgLength or 8
        local thickness = settings.lcgThickness or 1
        local xOffset = settings.xOffset or -1
        local yOffset = settings.yOffset or -1
        LCG.PixelGlow_Start(icon, color,
            lines, frequency, length, thickness,
            xOffset, yOffset, false, GLOW_KEY)
    elseif glowType == "Autocast Shine" then
        local particles = math.floor(settings.lcgLines or 10)
        local frequency = settings.lcgFrequency or 0.25
        local scale = settings.lcgScale or 1
        local xOffset = settings.xOffset or 0
        local yOffset = settings.yOffset or 0
        LCG.AutoCastGlow_Start(icon, color,
            particles, frequency, scale,
            xOffset, yOffset, GLOW_KEY)
    elseif glowType == "Action Button Glow" then
        LCG.ButtonGlow_Start(icon, color, settings.lcgFrequency or 0.25)
    elseif glowType == "Proc Glow" then
        LCG.ProcGlow_Start(icon, {
            color = color,
            startAnim = false,
            xOffset = settings.xOffset or 0,
            yOffset = settings.yOffset or 0,
            key = GLOW_KEY
        })
    elseif glowType == "Blizzard Glow" then
        if ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(icon)
        end
    end

    icon._DDingUIAssistGlowActive = true
end

local function StopLCGGlow(icon)
    if not icon._DDingUIAssistGlowActive then return end
    if LCG then
        LCG.PixelGlow_Stop(icon, GLOW_KEY)
        LCG.AutoCastGlow_Stop(icon, GLOW_KEY)
        LCG.ProcGlow_Stop(icon, GLOW_KEY)
        LCG.ButtonGlow_Stop(icon)
    end
    if ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(icon)
    end
    icon._DDingUIAssistGlowActive = nil
end

-- ============================================================
-- Unified highlight management
-- ============================================================

local function HideHighlight(icon)
    HideFlipbook(icon)
    StopLCGGlow(icon)
end

local function UpdateIconHighlight(icon, viewerName)
    if not icon or not icon.Icon then return end

    local settings = GetAssistSettings(viewerName)
    if not settings then
        HideHighlight(icon)
        return
    end

    -- Cache viewer name on icon
    icon._DDingUIAssistViewerName = viewerName

    local rawSpellID, overrideSpellID = ExtractSpellIDFromIcon(icon)
    if not rawSpellID then
        HideHighlight(icon)
        return
    end

    -- Check if in rotation
    local inRotation = IsSpellInRotation(rawSpellID)
    if not inRotation and overrideSpellID then
        inRotation = IsSpellInRotation(overrideSpellID)
    end

    if not inRotation then
        HideHighlight(icon)
        return
    end

    -- Check if this is the suggested spell
    local isSuggested = currentSuggestedSpellID
        and (rawSpellID == currentSuggestedSpellID
             or (overrideSpellID and overrideSpellID == currentSuggestedSpellID))

    local highlightType = settings.highlightType or "flipbook"

    if isSuggested then
        if highlightType == "flipbook" then
            StopLCGGlow(icon)
            ShowFlipbook(icon)
        else
            HideFlipbook(icon)
            ApplyLCGGlow(icon, settings)
        end
    else
        HideHighlight(icon)
    end
end

-- ============================================================
-- Public API
-- ============================================================

function AssistHighlight:UpdateViewerHighlights(viewerName)
    local viewerFrame = _G[viewerName]
    if not viewerFrame then return end

    local children = { viewerFrame:GetChildren() }
    for _, child in ipairs(children) do
        if child.Icon then
            UpdateIconHighlight(child, viewerName)
        end
    end
end

function AssistHighlight:UpdateAllHighlights()
    if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
        currentSuggestedSpellID = C_AssistedCombat.GetNextCastSpell()
    end
    for _, vName in ipairs(viewerNames) do
        self:UpdateViewerHighlights(vName)
    end
end

function AssistHighlight:RefreshAll()
    -- Hide all current highlights
    for _, vName in ipairs(viewerNames) do
        local viewerFrame = _G[vName]
        if viewerFrame then
            local children = { viewerFrame:GetChildren() }
            for _, child in ipairs(children) do
                HideHighlight(child)
            end
        end
    end

    -- Re-apply if still enabled
    if IsEnabledForAnyViewer() then
        rotationSpellsCacheValid = false
        UpdateRotationSpellsCache()
        self:UpdateAllHighlights()
    end
end

-- ============================================================
-- Event handling & hooks
-- ============================================================

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not isEnabled then return end

    if event == "PLAYER_ENTERING_WORLD" then
        rotationSpellsCacheValid = false
        UpdateRotationSpellsCache()
        AssistHighlight:UpdateAllHighlights()
    elseif event == "PLAYER_TALENT_UPDATE"
        or event == "SPELLS_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "TRAIT_CONFIG_UPDATED"
    then
        rotationSpellsCacheValid = false
        UpdateRotationSpellsCache()
        AssistHighlight:UpdateAllHighlights()
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        AssistHighlight:UpdateAllHighlights()
    end
end)

local function SetupHooks()
    if hooksInitialized then return end
    hooksInitialized = true

    -- Hook AssistedCombatManager for suggestion updates
    if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
        hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function()
            if not isEnabled then return end
            if not IsEnabledForAnyViewer() then return end
            AssistHighlight:UpdateAllHighlights()
        end)
    end

    -- Hook viewer RefreshLayout for icon changes
    for _, vName in ipairs(viewerNames) do
        local viewerFrame = _G[vName]
        if viewerFrame and viewerFrame.RefreshLayout then
            hooksecurefunc(viewerFrame, "RefreshLayout", function()
                if not isEnabled then return end
                local settings = GetAssistSettings(vName)
                if not settings then return end
                C_Timer.After(0.05, function()
                    AssistHighlight:UpdateViewerHighlights(vName)
                end)
            end)
        end
    end

    -- Hook RescanViewer to update after rescan
    local IconViewers = DDingUI.IconViewers
    if IconViewers and IconViewers.RescanViewer then
        hooksecurefunc(IconViewers, "RescanViewer", function(_, viewer)
            if not isEnabled then return end
            C_Timer.After(0.15, function()
                if viewer and viewer.IsShown and viewer:IsShown() then
                    local vName = viewer:GetName()
                    if vName then
                        AssistHighlight:UpdateViewerHighlights(vName)
                    end
                end
            end)
        end)
    end
end

function AssistHighlight:Enable()
    if isEnabled then return end
    isEnabled = true

    -- Enable the CVar so AssistedCombatManager fires events
    if C_CVar and C_CVar.GetCVar then
        if C_CVar.GetCVar("assistedCombatHighlight") ~= "1" then
            C_CVar.SetCVar("assistedCombatHighlight", "1")
        end
    end

    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")

    SetupHooks()

    rotationSpellsCacheValid = false
    UpdateRotationSpellsCache()
    self:UpdateAllHighlights()
end

function AssistHighlight:Disable()
    if not isEnabled then return end
    isEnabled = false

    eventFrame:UnregisterAllEvents()

    wipe(rotationSpellsCache)
    rotationSpellsCacheValid = false

    -- Hide all highlights
    for _, vName in ipairs(viewerNames) do
        local viewerFrame = _G[vName]
        if viewerFrame then
            local children = { viewerFrame:GetChildren() }
            for _, child in ipairs(children) do
                HideHighlight(child)
            end
        end
    end
end

function AssistHighlight:Initialize()
    -- Check if C_AssistedCombat API exists
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
        return
    end

    if IsEnabledForAnyViewer() then
        self:Enable()
    end
end

function AssistHighlight:OnSettingChanged()
    local shouldBeEnabled = IsEnabledForAnyViewer()
    if shouldBeEnabled and not isEnabled then
        self:Enable()
    elseif not shouldBeEnabled and isEnabled then
        self:Disable()
    elseif isEnabled then
        self:RefreshAll()
    end
end
