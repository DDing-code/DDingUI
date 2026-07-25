-- AssistHighlight Module - Assisted Combat Rotation Highlight
--
-- Highlights cooldown icons that match the assisted combat rotation suggestion.
-- Shows a highlight on icons suggested by C_AssistedCombat.GetNextCastSpell()

local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

DDingUI.AssistHighlight = DDingUI.AssistHighlight or {}
local AssistHighlight = DDingUI.AssistHighlight

-- StyleLib v2 GlowEffects
local SL = _G.DDingUI_StyleLib

local GLOW_KEY = "_DDingUIAssistGlow"

-- Viewer name list
local viewerNames = DDingUI.viewers or {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

local VIEWER_TO_GROUP = {
    EssentialCooldownViewer = "Cooldowns",
    UtilityCooldownViewer = "Utility",
    BuffIconCooldownViewer = "Buffs",
}

-- State
local rotationSpellsCache = {}
local rotationSpellsCacheValid = false
local currentSuggestedSpellID = nil
local isEnabled = false
local hooksInitialized = false
local pollingScript

local function GetGroupSystemGroups()
    local db = DDingUI.db and DDingUI.db.profile
    local gs = db and db.groupSystem
    return gs and gs.groups
end

local function ForEachGroupName(callback)
    local groups = GetGroupSystemGroups()
    if not groups then return end
    for groupName in pairs(groups) do
        callback(groupName)
    end
end

local function IsCallable(obj, method)
    return obj and type(obj[method]) == "function"
end

local function ForEachViewerIcon(viewerFrame, callback)
    if not viewerFrame or not callback then return end

    if viewerFrame.itemFramePool and IsCallable(viewerFrame.itemFramePool, "EnumerateActive") then
        for icon in viewerFrame.itemFramePool:EnumerateActive() do
            callback(icon)
        end
    elseif IsCallable(viewerFrame, "GetChildren") then
        local children = { viewerFrame:GetChildren() }
        for _, child in ipairs(children) do
            callback(child)
        end
    end
end

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
    if icon._spellID then
        return icon._spellID, nil
    end
    if icon._iconKey then
        local db = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
        local iconData = db and db.iconData and db.iconData[icon._iconKey]
        if iconData and iconData.id then
            return iconData.id, nil
        end
    end
    local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
    if fc and fc.GetSpellIDForIcon then
        local ok, spellID = pcall(fc.GetSpellIDForIcon, fc, icon)
        if ok and spellID then
            return spellID, nil
        end
    end
    local cooldownInfo = nil
    pcall(function()
        cooldownInfo = icon.GetCooldownInfo and icon:GetCooldownInfo() or icon.cooldownInfo
    end)
    if cooldownInfo then
        return cooldownInfo.spellID or cooldownInfo.overrideSpellID or cooldownInfo.linkedSpellID,
            cooldownInfo.overrideSpellID or cooldownInfo.linkedSpellID,
            cooldownInfo.linkedSpellIDs
    end
    if icon.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, icon.cooldownID)
        if ok and info then
            return info.spellID or info.overrideSpellID or info.linkedSpellID,
                info.overrideSpellID or info.linkedSpellID,
                info.linkedSpellIDs
        end
    end
    -- [ADD] CustomIcons (GroupSystem) 지원
    if icon._iconData then
        return icon._iconData.id, nil
    end
    -- fallback for some viewers that store spellID directly
    if icon.spellID then
        return icon.spellID, nil
    end
    return nil
end

-- Get assist highlight settings for a specific viewer or dynamic group
local function GetAssistSettings(viewerName)
    local db = DDingUI.db and DDingUI.db.profile
    if not db then return nil end

    -- 1. Check legacy viewers
    local viewers = db.viewers
    if viewers and viewers[viewerName] then
        local vs = viewers[viewerName]
        if vs.assistHighlight and vs.assistHighlight.enabled then
            return vs.assistHighlight
        end
    end

    -- 2. Check dynamic groups (CustomIcons/CDM)
    local groups = GetGroupSystemGroups()
    local groupName = viewerName
    if groups and not groups[groupName] and VIEWER_TO_GROUP[viewerName] then
        groupName = VIEWER_TO_GROUP[viewerName]
    end
    if groups and groups[groupName] then
        local gs = groups[groupName]
        if gs.assistHighlightEnabled then
            -- Map dynamic group settings to the expected format
            return {
                enabled = gs.assistHighlightEnabled,
                highlightType = gs.assistHighlightType or "flipbook",
                flipbookScale = gs.assistFlipbookScale or 1.5,
                glowType = gs.assistGlowType or "Pixel Glow",
                color = gs.assistGlowColor or {0.3, 0.7, 1.0, 1},
                lcgLines = gs.assistGlowLines or 10,
                lcgFrequency = gs.assistGlowFrequency or 0.25,
                lcgThickness = gs.assistGlowThickness or 1,
                lcgLength = gs.assistHighlightPixelLength or 8,
            }
        end
    end

    return nil
end

-- Check if any viewer or dynamic group has assist highlight enabled
local function IsEnabledForAnyViewer()
    local db = DDingUI.db and DDingUI.db.profile
    if not db then return false end

    local viewers = db.viewers
    if viewers then
        for _, vName in ipairs(viewerNames) do
            local vs = viewers[vName]
            if vs and vs.assistHighlight and vs.assistHighlight.enabled then
                return true
            end
        end
    end

    local groups = GetGroupSystemGroups()
    if groups then
        for _, gs in pairs(groups) do
            if gs and gs.assistHighlightEnabled then
                return true
            end
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

local function GetCurrentSuggestedSpellID()
    if AssistedCombatManager and AssistedCombatManager.lastNextCastSpellID then
        return AssistedCombatManager.lastNextCastSpellID
    end
    if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
        return C_AssistedCombat.GetNextCastSpell()
    end
    return nil
end

local function SpellMatchesSuggested(rawSpellID, overrideSpellID, linkedSpellIDs)
    if not currentSuggestedSpellID then return false end
    if rawSpellID == currentSuggestedSpellID or overrideSpellID == currentSuggestedSpellID then
        return true
    end
    if type(linkedSpellIDs) == "table" then
        for _, spellID in ipairs(linkedSpellIDs) do
            if spellID == currentSuggestedSpellID then
                return true
            end
        end
    end
    return false
end

-- Get viewer name for an icon frame (walk parent chain)
local function GetViewerNameForIcon(button)
    if not button then return nil end

    if button._DDingUIAssistViewerName then
        return button._DDingUIAssistViewerName
    end
    if button._ddGroupName then
        return button._ddGroupName
    end

    -- [ADD] Check if it's a dynamic group icon
    if button._iconData and button._iconData.settings and button._groupSettings then
        -- Find the group name that matches these settings (not trivial, but we usually set `_DDingUIAssistViewerName` explicitly)
        if button._DDingUIAssistViewerName then
            return button._DDingUIAssistViewerName
        end
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

-- ============================================================
-- Flipbook highlight (Blizzard style ants animation)
-- ============================================================

local function ResizeFlipbookHighlight(frame, icon)
    if not frame or not icon then return end
    local w, h = icon:GetSize()
    if not w or w <= 0 then w = 36 end
    if not h or h <= 0 then h = 36 end
    local settings = GetAssistSettings(icon._DDingUIAssistViewerName or GetViewerNameForIcon(icon))
    local scale = (settings and settings.flipbookScale) or 1.5

    if frame.Flipbook then
        local ox = w * math.max((scale - 1) * 0.5, 0)
        local oy = h * math.max((scale - 1) * 0.5, 0)
        frame.Flipbook:ClearAllPoints()
        frame.Flipbook:SetPoint("TOPLEFT", icon, "TOPLEFT", -ox, oy)
        frame.Flipbook:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", ox, -oy)
    elseif frame.Texture then
        frame.Texture:SetSize(w * scale, h * scale)
    end
end

local function GetOrCreateFlipbookHighlight(icon)
    if icon._DDingUIAssistFlipbook then
        -- Update size on re-access
        ResizeFlipbookHighlight(icon._DDingUIAssistFlipbook, icon)
        return icon._DDingUIAssistFlipbook
    end

    local ok, nativeFrame = pcall(CreateFrame, "Frame", nil, icon, "ActionBarButtonAssistedCombatHighlightTemplate")
    if ok and nativeFrame then
        nativeFrame:SetFrameLevel(icon:GetFrameLevel() + 15)
        nativeFrame:SetAllPoints(icon)
        nativeFrame:Hide()
        if nativeFrame.Flipbook and nativeFrame.Flipbook.Anim then
            nativeFrame.Flipbook.Anim:Play()
            nativeFrame.Flipbook.Anim:Stop()
        end
        icon._DDingUIAssistFlipbook = nativeFrame
        ResizeFlipbookHighlight(nativeFrame, icon)
        return nativeFrame
    end

    local frame = CreateFrame("Frame", nil, icon)
    frame:SetFrameLevel(icon:GetFrameLevel() + 10)
    frame:SetAllPoints(icon)

    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAtlas(flipbookConfig.atlas)
    tex:SetBlendMode("ADD")
    tex:SetPoint("CENTER", icon, "CENTER", 0, 0)
    frame.Texture = tex
    ResizeFlipbookHighlight(frame, icon)

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
    ResizeFlipbookHighlight(flipbook, icon)
    flipbook:SetAlpha(1)
    flipbook:Show()
    if flipbook.Anim and not flipbook.Anim:IsPlaying() then
        flipbook.Anim:Play()
    elseif flipbook.Flipbook and flipbook.Flipbook.Anim and not flipbook.Flipbook.Anim:IsPlaying() then
        flipbook.Flipbook.Anim:Play()
    end
end

local function HideFlipbook(icon)
    if icon._DDingUIAssistFlipbook then
        icon._DDingUIAssistFlipbook:SetAlpha(0)
        icon._DDingUIAssistFlipbook:Hide()
        if icon._DDingUIAssistFlipbook.Anim and icon._DDingUIAssistFlipbook.Anim:IsPlaying() then
            icon._DDingUIAssistFlipbook.Anim:Stop()
        end
        if icon._DDingUIAssistFlipbook.Flipbook and icon._DDingUIAssistFlipbook.Flipbook.Anim and icon._DDingUIAssistFlipbook.Flipbook.Anim:IsPlaying() then
            icon._DDingUIAssistFlipbook.Flipbook.Anim:Stop()
        end
    end
end

-- ============================================================
-- LCG glow highlight (LibCustomGlow style)
-- ============================================================

local function ApplyLCGGlow(icon, settings)
    -- Stop existing assist glows
    SL.HidePixelGlow(icon, GLOW_KEY)
    SL.HideAutocastGlow(icon, GLOW_KEY)
    SL.HideButtonGlow(icon)
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(icon, GLOW_KEY) end

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
        SL.ShowPixelGlow(icon, color,
            lines, frequency, length, thickness,
            xOffset, yOffset, false, GLOW_KEY)
    elseif glowType == "Autocast Shine" then
        local particles = math.floor(settings.lcgLines or 10)
        local frequency = settings.lcgFrequency or 0.25
        local scale = settings.lcgScale or 1
        local xOffset = settings.xOffset or 0
        local yOffset = settings.yOffset or 0
        SL.ShowAutocastGlow(icon, color,
            particles, frequency, scale,
            xOffset, yOffset, GLOW_KEY)
    elseif glowType == "Action Button Glow" then
        SL.ShowButtonGlow(icon, color, settings.lcgFrequency or 0.25)
    elseif glowType == "Proc Glow" then
        local LCG2 = LibStub("LibCustomGlow-1.0", true)
        if LCG2 and LCG2.ProcGlow_Start then
            LCG2.ProcGlow_Start(icon, {
                color = color, startAnim = false,
                xOffset = settings.xOffset or 0,
                yOffset = settings.yOffset or 0,
                key = GLOW_KEY
            })
        end
    elseif glowType == "Blizzard Glow" then
        if ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(icon)
        end
    end

    icon._DDingUIAssistGlowActive = true
end

local function StopLCGGlow(icon)
    if not icon._DDingUIAssistGlowActive then return end
    SL.HidePixelGlow(icon, GLOW_KEY)
    SL.HideAutocastGlow(icon, GLOW_KEY)
    SL.HideButtonGlow(icon)
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(icon, GLOW_KEY) end
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

    local rawSpellID, overrideSpellID, linkedSpellIDs = ExtractSpellIDFromIcon(icon)
    if not rawSpellID then
        HideHighlight(icon)
        return
    end

    -- Check if this is the suggested spell. This is more reliable than
    -- requiring GetRotationSpells(), which can be empty during spec/load gaps.
    local isSuggested = SpellMatchesSuggested(rawSpellID, overrideSpellID, linkedSpellIDs)

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

    if viewerFrame then
        -- [FIX] GroupSystem 활성 시 아이콘이 UIParent로 reparent되어
        -- GetChildren()으로 찾을 수 없음 → itemFramePool 사용
        if viewerFrame.itemFramePool and IsCallable(viewerFrame.itemFramePool, "EnumerateActive") then
            for icon in viewerFrame.itemFramePool:EnumerateActive() do
                if icon.Icon and not icon.isEditing then
                    UpdateIconHighlight(icon, viewerName)
                end
            end
        elseif IsCallable(viewerFrame, "GetChildren") then
            -- Fallback: itemFramePool이 없는 경우 (비CDM 뷰어)
            local children = { viewerFrame:GetChildren() }
            for _, child in ipairs(children) do
                if child.Icon then
                    UpdateIconHighlight(child, viewerName)
                end
            end
        end
    end

    -- [ADD] Dynamic Groups (CustomIcons) 지원
    local db = DDingUI.db and DDingUI.db.profile
    local groups = GetGroupSystemGroups()
    if db and groups and groups[viewerName] and db.dynamicIcons and db.dynamicIcons.groups then
        local grpSettings = groups[viewerName]
        local sourceGroupKey = grpSettings.sourceGroupKey or viewerName
        local ciGroup = db.dynamicIcons.groups[sourceGroupKey]

        if ciGroup and ciGroup.icons and DDingUI.CustomIcons and DDingUI.CustomIcons.runtime and DDingUI.CustomIcons.runtime.iconFrames then
            for _, iconKey in ipairs(ciGroup.icons) do
                local iconFrame = DDingUI.CustomIcons.runtime.iconFrames[iconKey]
                if iconFrame and iconFrame.icon then
                    -- Create a unified "Icon" property for ApplyLCGGlow compatibility if missing
                    if not iconFrame.Icon then iconFrame.Icon = iconFrame.icon end
                    iconFrame._DDingUIAssistViewerName = viewerName
                    if not iconFrame.isEditing then
                        UpdateIconHighlight(iconFrame, viewerName)
                    end
                end
            end
        end
    end
end

function AssistHighlight:UpdateAllHighlights()
    currentSuggestedSpellID = GetCurrentSuggestedSpellID()
    for _, vName in ipairs(viewerNames) do
        self:UpdateViewerHighlights(vName)
    end
    
    ForEachGroupName(function(gName)
        self:UpdateViewerHighlights(gName)
    end)
end

function AssistHighlight:RefreshAll()
    -- Hide all current highlights
    for _, vName in ipairs(viewerNames) do
        local viewerFrame = _G[vName]
        if viewerFrame then
            if viewerFrame.itemFramePool and IsCallable(viewerFrame.itemFramePool, "EnumerateActive") then
                for icon in viewerFrame.itemFramePool:EnumerateActive() do
                    HideHighlight(icon)
                end
            elseif IsCallable(viewerFrame, "GetChildren") then
                local children = { viewerFrame:GetChildren() }
                for _, child in ipairs(children) do
                    HideHighlight(child)
                end
            end
        end
    end

    if DDingUI.CustomIcons and DDingUI.CustomIcons.runtime and DDingUI.CustomIcons.runtime.iconFrames then
        for _, iconFrame in pairs(DDingUI.CustomIcons.runtime.iconFrames) do
            HideHighlight(iconFrame)
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

    -- Hook AssistedCombatManager for suggestion updates (if available)
    if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
        hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function()
            if not isEnabled then return end
            if not IsEnabledForAnyViewer() then return end
            AssistHighlight:UpdateAllHighlights()
        end)
    end

    -- [FIX] OnUpdate 폴링: AssistedCombatManager 훅이 없거나 불안정할 때
    -- ~15fps 쓰로틀로 C_AssistedCombat.GetNextCastSpell() 변경을 실시간 추적
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
            if not isEnabled then return end
            if not IsEnabledForAnyViewer() then return end
            AssistHighlight:UpdateAllHighlights()
        end, "DDingUI_AssistHighlight")
        EventRegistry:RegisterCallback("AssistedCombatManager.OnSetUseAssistedHighlight", function()
            if not isEnabled then return end
            AssistHighlight:UpdateAllHighlights()
        end, "DDingUI_AssistHighlight_CVar")
    end

    local POLL_THROTTLE = 0.066  -- ~15fps
    local nextPollTime = 0
    pollingScript = function()
        if not isEnabled then return end
        if not ((C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) or AssistedCombatManager) then return end

        local now = GetTime()
        if now < nextPollTime then return end
        nextPollTime = now + POLL_THROTTLE

        local newSuggested = GetCurrentSuggestedSpellID()
        if newSuggested ~= currentSuggestedSpellID then
            currentSuggestedSpellID = newSuggested
            AssistHighlight:UpdateAllHighlights()
        end
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

    -- Hook GroupSystem RefreshLayout
    if DDingUI.GroupSystem and DDingUI.GroupSystem.RefreshLayout then
        hooksecurefunc(DDingUI.GroupSystem, "RefreshLayout", function()
            if not isEnabled then return end
            C_Timer.After(0.05, function()
                ForEachGroupName(function(gName)
                    AssistHighlight:UpdateViewerHighlights(gName)
                end)
            end)
        end)
    end

    -- Hook CustomIcons UpdateAllIcons (which triggers when dynamic icons are added/removed)
    if DDingUI.CustomIcons and DDingUI.CustomIcons.UpdateAllIcons then
        hooksecurefunc(DDingUI.CustomIcons, "UpdateAllIcons", function()
            if not isEnabled then return end
            C_Timer.After(0.15, function()
                ForEachGroupName(function(gName)
                    AssistHighlight:UpdateViewerHighlights(gName)
                end)
            end)
        end)
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
    eventFrame:SetScript("OnUpdate", pollingScript)

    rotationSpellsCacheValid = false
    UpdateRotationSpellsCache()
    self:UpdateAllHighlights()
end

function AssistHighlight:Disable()
    if not isEnabled then return end
    isEnabled = false

    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnUpdate", nil)  -- [FIX] OnUpdate 폴링 정리

    wipe(rotationSpellsCache)
    rotationSpellsCacheValid = false

    -- Hide all highlights
    for _, vName in ipairs(viewerNames) do
        local viewerFrame = _G[vName]
        if viewerFrame then
            if viewerFrame.itemFramePool then
                for icon in viewerFrame.itemFramePool:EnumerateActive() do
                    HideHighlight(icon)
                end
            else
                local children = { viewerFrame:GetChildren() }
                for _, child in ipairs(children) do
                    HideHighlight(child)
                end
            end
        end
    end

    if DDingUI.CustomIcons and DDingUI.CustomIcons.runtime and DDingUI.CustomIcons.runtime.iconFrames then
        for _, iconFrame in pairs(DDingUI.CustomIcons.runtime.iconFrames) do
            HideHighlight(iconFrame)
        end
    end
end

function AssistHighlight:Initialize()
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

function AssistHighlight:DebugStatus()
    currentSuggestedSpellID = GetCurrentSuggestedSpellID()
    local suggestedName = currentSuggestedSpellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(currentSuggestedSpellID) or "nil"
    local cvar = GetCVar and GetCVar("assistedCombatHighlight") or "?"
    print(string.format("|cff66ccffDDingUI Assist|r enabled=%s anySetting=%s cvar=%s suggested=%s (%s)",
        tostring(isEnabled), tostring(IsEnabledForAnyViewer()), tostring(cvar), tostring(currentSuggestedSpellID), tostring(suggestedName)))

    for _, vName in ipairs(viewerNames) do
        local settings = GetAssistSettings(vName)
        local viewer = _G[vName]
        local total, matched = 0, 0
        if viewer and viewer.itemFramePool then
            for icon in viewer.itemFramePool:EnumerateActive() do
                total = total + 1
                local rawSpellID, overrideSpellID, linkedSpellIDs = ExtractSpellIDFromIcon(icon)
                if SpellMatchesSuggested(rawSpellID, overrideSpellID, linkedSpellIDs) then
                    matched = matched + 1
                end
            end
        end
        print(string.format("  %s setting=%s icons=%d matched=%d", vName, tostring(settings and settings.enabled), total, matched))
    end

    ForEachGroupName(function(gName)
        local settings = GetAssistSettings(gName)
        if settings then
            print(string.format("  group:%s setting=%s type=%s", gName, tostring(settings.enabled), tostring(settings.highlightType)))
        end
    end)
end

SLASH_DDASSISTDEBUG1 = "/ddassistdebug"
SlashCmdList["DDASSISTDEBUG"] = function()
    if DDingUI.AssistHighlight and DDingUI.AssistHighlight.DebugStatus then
        DDingUI.AssistHighlight:DebugStatus()
    end
end
