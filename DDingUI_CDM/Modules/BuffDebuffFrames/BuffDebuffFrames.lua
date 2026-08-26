local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

DDingUI.BuffDebuffFrames = DDingUI.BuffDebuffFrames or {}
local BDF = DDingUI.BuffDebuffFrames

local LSM = LibStub("LibSharedMedia-3.0")

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

-- Cache for styled auras to avoid re-styling
local styledAuras = {}
local function NeutralizeAtlasTexture(texture)
    if not texture then return end

    -- Clear existing atlas assignment and keep future atlas calls invisible
    if texture.SetAtlas then
        texture:SetAtlas(nil)
        if not IsHooked(texture, "atlasNeutralized") then
            SetHooked(texture, "atlasNeutralized")
            hooksecurefunc(texture, "SetAtlas", function(self)
                if self.SetTexture then
                    self:SetTexture(nil)
                end
                if self.SetAlpha then
                    self:SetAlpha(0)
                end
            end)
        end
    end

    if texture.SetTexture then
        texture:SetTexture(nil)
    end

    if texture.SetAlpha then
        texture:SetAlpha(0)
    end
end

local function IsEditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame.editModeActive
end

-- Re-entrancy guard to prevent recursive processing loops
BDF._processing = false

-- Create custom border overlay using textures instead of backdrop
local function CreateAuraBorderOverlay(auraFrame)
    local auraData = GetFrameData(auraFrame)
    if auraData.borderOverlay then return end

    local overlay = CreateFrame("Frame", nil, auraFrame)
    overlay:SetAllPoints(auraFrame.Icon or auraFrame)
    overlay:SetFrameLevel((auraFrame:GetFrameLevel() or 0) + 15)

    -- Create border textures for all four edges
    local edges = {"Top", "Bottom", "Left", "Right"}
    overlay.textures = {}

    for _, edge in ipairs(edges) do
        local tex = overlay:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(0, 0, 0, 1)
        overlay.textures[edge] = tex

        if edge == "Top" then
            tex:SetPoint("TOPLEFT", overlay, "TOPLEFT", -1, 1)
            tex:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 1, 1)
            tex:SetHeight(1)
        elseif edge == "Bottom" then
            tex:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -1, -1)
            tex:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 1, -1)
            tex:SetHeight(1)
        elseif edge == "Left" then
            tex:SetPoint("TOPLEFT", overlay, "TOPLEFT", -1, 1)
            tex:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -1, -1)
            tex:SetWidth(1)
        elseif edge == "Right" then
            tex:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 1, 1)
            tex:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 1, -1)
            tex:SetWidth(1)
        end
    end

    auraData.borderOverlay = overlay
end

local function EnsureAuraTextOverlay(auraFrame)
    local auraData = GetFrameData(auraFrame)
    if auraData.textOverlay then return auraData.textOverlay end

    local overlayParent = auraData.borderOverlay or auraFrame
    local textOverlay = CreateFrame("Frame", nil, auraFrame)
    textOverlay:SetAllPoints(overlayParent or auraFrame)

    local baseLevel = (overlayParent and overlayParent:GetFrameLevel()) or (auraFrame:GetFrameLevel() or 0)
    textOverlay:SetFrameLevel(baseLevel + 1)
    auraData.textOverlay = textOverlay

    return textOverlay
end

-- Apply styling to a single aura frame
local function EnhanceAuraFrame(auraFrame, config)
    if not auraFrame or not config then return end
    if styledAuras[auraFrame] then return end

    local icon = auraFrame.Icon
    if not icon then return end

    -- Skip anchor frames
    if auraFrame.isAuraAnchor then return end

    -- Apply icon modifications
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local iconSize = config.iconSize or 36
    icon:SetSize(iconSize, iconSize)

    -- Hide default borders
    NeutralizeAtlasTexture(auraFrame.DebuffBorder)
    NeutralizeAtlasTexture(auraFrame.BuffBorder)
    NeutralizeAtlasTexture(auraFrame.TempEnchantBorder)

    -- Create our custom border overlay
    CreateAuraBorderOverlay(auraFrame)
    local textOverlay = EnsureAuraTextOverlay(auraFrame)

    -- Style duration text
    if auraFrame.Duration and config.duration then
        local durConfig = config.duration

        -- Check if duration text is enabled
            if durConfig.enabled ~= false then
                local font = DDingUI:GetFont(durConfig.font)

                auraFrame.Duration:ClearAllPoints()
                if textOverlay then
                    auraFrame.Duration:SetParent(textOverlay)
                end
                auraFrame.Duration:SetDrawLayer("OVERLAY", 2)

                local anchorPoint = durConfig.anchorPoint or "CENTER"
                local offsetX = durConfig.offsetX or 0
                local offsetY = durConfig.offsetY or 0

            auraFrame.Duration:SetPoint(anchorPoint, icon, anchorPoint, offsetX, offsetY)
            auraFrame.Duration:SetFont(font, durConfig.fontSize or 12, durConfig.fontFlag or "OUTLINE")
            auraFrame.Duration:SetShadowOffset(0, 0)

            local textColor = durConfig.textColor or {1, 1, 1, 1}
            auraFrame.Duration:SetTextColor(
                textColor[1] or 1,
                textColor[2] or 1,
                textColor[3] or 1,
                textColor[4] or 1
            )

            auraFrame.Duration:Show()
        else
            auraFrame.Duration:Hide()
        end
    end

    -- Style count text
    if auraFrame.Count and config.count then
        local countConfig = config.count

        -- Check if count text is enabled
        if countConfig.enabled ~= false then
            local font = DDingUI:GetFont(countConfig.font)

            auraFrame.Count:ClearAllPoints()
            if textOverlay then
                auraFrame.Count:SetParent(textOverlay)
            end
            auraFrame.Count:SetDrawLayer("OVERLAY", 2)

            local anchorPoint = countConfig.anchorPoint or "TOPRIGHT"
            local offsetX = countConfig.offsetX or 0
            local offsetY = countConfig.offsetY or 0

            auraFrame.Count:SetPoint(anchorPoint, icon, anchorPoint, offsetX, offsetY)
            auraFrame.Count:SetFont(font, countConfig.fontSize or 12, countConfig.fontFlag or "OUTLINE")

            local textColor = countConfig.textColor or {1, 1, 1, 1}
            auraFrame.Count:SetTextColor(
                textColor[1] or 1,
                textColor[2] or 1,
                textColor[3] or 1,
                textColor[4] or 1
            )

            auraFrame.Count:Show()
        else
            auraFrame.Count:Hide()
        end
    end

    styledAuras[auraFrame] = true
end

-- Adjust spacing on Blizzard containers without overriding their layout logic
local function ApplySpacingOnly(container, config)
    if not container or not config then return end

    -- Accept either layout table or direct config fields
    local spacingX = (config.layout and (config.layout.iconSpacing or config.layout.spacing))
        or config.iconSpacing
        or config.spacing
    local spacingY = (config.layout and config.layout.rowSpacing) or config.rowSpacing or spacingX

    if not spacingX then return end
    -- Avoid fighting Blizzard's edit mode refresh loop
    if IsEditModeActive() then return end

    -- Retail AuraContainerMixin exposes SetSpacing; guard for older clients
    if container.SetSpacing then
        container:SetSpacing(spacingX, spacingY or spacingX)
        -- Force immediate reflow so slider changes are visible without waiting
        if container.UpdateGridLayout then
            container:UpdateGridLayout()
        elseif container.MarkDirty then
            container:MarkDirty()
            if container:Layout() then container:Layout() end
        end
    end
end

-- Process all buff frames
local function ProcessBuffFrames()
    if BDF._processing then return end
    BDF._processing = true

    local db = DDingUI.db.profile.buffDebuffFrames
    if not db or not db.enabled then
        BDF._processing = false
        return
    end

    local buffConfig = db.buffs or {}
    if buffConfig.enabled == false then
        BDF._processing = false
        return
    end

    if not BuffFrame or not BuffFrame.auraFrames then
        BDF._processing = false
        return
    end

    -- Hide collapse button
    if BuffFrame.CollapseAndExpandButton then
        BuffFrame.CollapseAndExpandButton:SetAlpha(0)
        BuffFrame.CollapseAndExpandButton:EnableMouse(false)
    end

    -- Style each buff frame
    for _, auraFrame in pairs(BuffFrame.auraFrames) do
        EnhanceAuraFrame(auraFrame, buffConfig)
    end

    -- Let Blizzard handle layout; only adjust spacing if API is available
    ApplySpacingOnly(BuffFrame.auraContainer or BuffFrame.AuraContainer, buffConfig)
    BDF._processing = false
end

-- Process all debuff frames
local function ProcessDebuffFrames()
    if BDF._processing then return end
    BDF._processing = true

    local db = DDingUI.db.profile.buffDebuffFrames
    if not db or not db.enabled then
        BDF._processing = false
        return
    end

    local debuffConfig = db.debuffs or {}
    if debuffConfig.enabled == false then
        BDF._processing = false
        return
    end

    if not DebuffFrame or not DebuffFrame.auraFrames then
        BDF._processing = false
        return
    end

    -- Style each debuff frame
    for _, auraFrame in pairs(DebuffFrame.auraFrames) do
        EnhanceAuraFrame(auraFrame, debuffConfig)
    end

    -- Let Blizzard handle layout; only adjust spacing if API is available
    ApplySpacingOnly(DebuffFrame.auraContainer or DebuffFrame.AuraContainer, debuffConfig)
    BDF._processing = false
end

-- Pending flags to prevent duplicate timer creation
local pendingBuffUpdate = false
local pendingDebuffUpdate = false
local pendingEditModeRefresh = false

-- Hook into aura update functions
local function HookAuraUpdates()
    -- Hook buff frame updates once
    if BuffFrame and BuffFrame.UpdateAuraButtons and not BDF._buffHooked then
        hooksecurefunc(BuffFrame, "UpdateAuraButtons", function()
            if not pendingBuffUpdate then
                pendingBuffUpdate = true
                C_Timer.After(0.1, function()
                    pendingBuffUpdate = false
                    ProcessBuffFrames()
                end)
            end
        end)
        BDF._buffHooked = true
    end

    -- Hook debuff frame updates once
    if DebuffFrame and DebuffFrame.UpdateAuraButtons and not BDF._debuffHooked then
        hooksecurefunc(DebuffFrame, "UpdateAuraButtons", function()
            if not pendingDebuffUpdate then
                pendingDebuffUpdate = true
                C_Timer.After(0.1, function()
                    pendingDebuffUpdate = false
                    ProcessDebuffFrames()
                end)
            end
        end)
        BDF._debuffHooked = true
    end
end

-- Hook edit mode
local function HookEditMode()
    if BDF._editModeHooked then return end

    if EditModeManagerFrame then
        local function RefreshOnEditMode()
            if not pendingEditModeRefresh then
                pendingEditModeRefresh = true
                C_Timer.After(0.5, function()
                    pendingEditModeRefresh = false
                    styledAuras = {} -- Clear cache so frames get re-styled after edit mode
                    ProcessBuffFrames()
                    ProcessDebuffFrames()
                end)
            end
        end

        -- Use RegisterCallback if available, otherwise use hooksecurefunc (not both)
        if EditModeManagerFrame.RegisterCallback then
            EditModeManagerFrame:RegisterCallback("EditModeEnter", RefreshOnEditMode)
            EditModeManagerFrame:RegisterCallback("EditModeExit", RefreshOnEditMode)
        else
            -- Fallback hooks only if RegisterCallback not available
            hooksecurefunc(EditModeManagerFrame, "EnterEditMode", RefreshOnEditMode)
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", RefreshOnEditMode)
        end
        BDF._editModeHooked = true
    end
end

-- Initialize the module
function BDF:Initialize()
    local db = DDingUI.db.profile.buffDebuffFrames
    if not db or not db.enabled then return end

    -- Wait for frames to be ready
    C_Timer.After(1.0, function()
        ProcessBuffFrames()
        ProcessDebuffFrames()
        HookAuraUpdates()
        HookEditMode()
    end)
end

-- Refresh all frames
function BDF:RefreshAll()
    styledAuras = {} -- Clear cache

    -- Clean up ticker if it exists (legacy cleanup)
    if BDF._updateTicker then
        BDF._updateTicker:Cancel()
        BDF._updateTicker = nil
    end

    if DDingUI.db.profile.buffDebuffFrames and DDingUI.db.profile.buffDebuffFrames.enabled then
        ProcessBuffFrames()
        ProcessDebuffFrames()
        HookAuraUpdates()
    end
end
