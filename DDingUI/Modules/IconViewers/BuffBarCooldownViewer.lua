local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

DDingUI.IconViewers = DDingUI.IconViewers or {}
local IconViewers = DDingUI.IconViewers

IconViewers.BuffBarCooldownViewer = IconViewers.BuffBarCooldownViewer or {}
local BuffBar = IconViewers.BuffBarCooldownViewer

local C_Timer = _G.C_Timer
local UIParent = _G.UIParent
local WHITE8 = "Interface\\Buttons\\WHITE8X8"

-- Use shared PixelSnap from Toolkit
local PixelSnap = DDingUI.PixelSnapLocal or function(value)
    return math.max(0, math.floor((value or 0) + 0.5))
end

local frameState = setmetatable({}, { __mode = "k" })
local function GetFrameState(frame)
    if not frame then return nil end
    local state = frameState[frame]
    if not state then
        state = {}
        frameState[frame] = state
    end
    return state
end

local function StripTextureMasks(texture)
    if not texture or not texture.GetMaskTexture then return end

    local i = 1
    local mask = texture:GetMaskTexture(i)
    while mask do
        texture:RemoveMaskTexture(mask)
        i = i + 1
        mask = texture:GetMaskTexture(i)
    end
end

local function StripBlizzardOverlay(icon)
    for _, region in ipairs({ icon:GetRegions() }) do
        if region:IsObjectType("Texture") and region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
            region:SetTexture("")
            region:Hide()
            region.Show = function() end
        end
    end
end

local function GetSettings()
    if not DDingUI.db or not DDingUI.db.profile then
        return nil
    end

    DDingUI.db.profile.buffBarViewer = DDingUI.db.profile.buffBarViewer or {}
    DDingUI.db.profile.buffBarViewer.barColors = DDingUI.db.profile.buffBarViewer.barColors or {}
    DDingUI.db.profile.buffBarViewer.barColorsBySpec = DDingUI.db.profile.buffBarViewer.barColorsBySpec or {}
    return DDingUI.db.profile.buffBarViewer
end

local function GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local id = GetSpecializationInfo(specIndex)
        return id
    end
    return nil
end

local function GetBarColor(settings, barIndex)
    if not settings then return nil end
    local specID = GetCurrentSpecID()
    if specID and settings.barColorsBySpec and settings.barColorsBySpec[specID] then
        return settings.barColorsBySpec[specID][barIndex]
    end
    if settings.barColors then
        return settings.barColors[barIndex]
    end
    return nil
end

local function SetBarColor(settings, barIndex, color)
    if not settings then return end
    local specID = GetCurrentSpecID()
    settings.barColorsBySpec = settings.barColorsBySpec or {}
    if specID then
        settings.barColorsBySpec[specID] = settings.barColorsBySpec[specID] or {}
        settings.barColorsBySpec[specID][barIndex] = color
    else
        settings.barColors = settings.barColors or {}
        settings.barColors[barIndex] = color
    end
end

local function GetBarIndex(child)
    local idx = 0
    pcall(function()
        if child.layoutIndex and type(child.layoutIndex) == "number" then idx = child.layoutIndex end
    end)
    if idx == 0 then idx = child.orderIndex or (child.GetID and child:GetID()) or 1 end
    return idx
end

local function CollectBarFrames(viewer)
    local children = {}
    if not viewer then return children end

    if viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
        for frame in viewer.itemFramePool:EnumerateActive() do
            if frame and frame.Bar then
                children[#children + 1] = frame
            end
        end
        return children
    end

    if viewer.GetChildren then
        for _, child in ipairs({ viewer:GetChildren() }) do
            if child and child.Bar then
                children[#children + 1] = child
            end
        end
    end

    return children
end

local function GetAnchorFrame(settings)
    -- Custom anchor: return custom target if set
    if settings then
        local frameName = settings.anchorFrame
        if frameName and frameName ~= "" then
            local target = _G[frameName]
            if target then return target end
        end
    end
    -- Default: EssentialCooldownViewer
    local anchor = _G["EssentialCooldownViewer"]
    if anchor then
        return anchor
    end
    return nil
end

local function ResolvePositionAnchor(settings)
    if not settings then return nil end
    if not settings._moverSaved and not settings.attachTo then
        return nil
    end

    local frameName = settings.attachTo
    if not frameName or frameName == "" then
        frameName = "UIParent"
    end

    if DDingUI.ResolveAnchorFrame then
        return DDingUI:ResolveAnchorFrame(frameName)
    end
    return _G[frameName] or UIParent
end

local function ApplyViewerPosition(viewer, settings)
    if not viewer or not settings then return end
    if DDingUI.Movers and DDingUI.Movers.ConfigMode then return end

    local anchor = ResolvePositionAnchor(settings)
    if not anchor then return end
    if InCombatLockdown() and viewer.IsProtected and viewer:IsProtected() then return end

    local selfPoint = settings.selfPoint or "CENTER"
    local anchorPoint = settings.anchorPoint or "CENTER"
    if anchor == UIParent then
        selfPoint = "CENTER"
        anchorPoint = "CENTER"
    end

    local offsetX = DDingUI:Scale(settings.offsetX or settings.anchorOffsetX or 0)
    local offsetY = DDingUI:Scale(settings.offsetY or settings.anchorOffsetY or 0)
    local state = GetFrameState(viewer)
    local layoutKey = tostring(selfPoint) .. ":" .. tostring(anchor:GetName() or "UIParent")
        .. ":" .. tostring(anchorPoint) .. ":" .. tostring(offsetX) .. ":" .. tostring(offsetY)

    if state.lastViewerPositionKey == layoutKey then
        return
    end
    state.lastViewerPositionKey = layoutKey

    viewer:ClearAllPoints()
    viewer:SetPoint(selfPoint, anchor, anchorPoint, offsetX, offsetY)
end

local function ComputeBarWidth(settings, viewer, iconTotal, spacing, barBorder)
    local width = settings.width or 0
    local anchor = GetAnchorFrame(settings) or viewer
    spacing = spacing or 0
    iconTotal = iconTotal or 0
    barBorder = barBorder or 0

    if width <= 0 then
        local anchorWidth
        if anchor and anchor.GetWidth then
            local ok, w = pcall(anchor.GetWidth, anchor)
            if ok then
                local avd = IconViewers._viewerData and IconViewers._viewerData[anchor]
                anchorWidth = (avd and avd.iconWidth) or w
            end
        end
        width = PixelSnap(anchorWidth or (viewer and viewer:GetWidth()) or 200)
        width = math.max(1, width - iconTotal - spacing)
    else
        width = PixelSnap(DDingUI:Scale(width))
    end

    return width
end

local function ComputeBarHeight(settings, bar)
    local desired = settings.height or 16
    local scaled = DDingUI:Scale(desired)
    if scaled <= 0 and bar and bar.GetHeight then
        local ok, h = pcall(bar.GetHeight, bar)
        if ok and h and h > 0 then
            return h
        end
    end
    return scaled
end

local function ApplyIconMaskSettings(iconFrame, settings)
    if not iconFrame or settings.hideIconMask == false then
        return
    end

    local iconTexture = iconFrame.icon or iconFrame.Icon or iconFrame.IconTexture
    if iconTexture then
        StripTextureMasks(iconTexture)
    end

    if iconFrame.GetRegions then
        for _, region in ipairs({ iconFrame:GetRegions() }) do
            if region and region:IsObjectType("Texture") then
                StripTextureMasks(region)
            end
        end
    end

    StripBlizzardOverlay(iconFrame)

    if iconFrame.DebuffBorder then
        if iconFrame.DebuffBorder.SetTexture then
            iconFrame.DebuffBorder:SetTexture(nil)
        end
        if iconFrame.DebuffBorder.Hide then
            iconFrame.DebuffBorder:Hide()
        end
    end
end

local function ApplyIconZoom(iconFrame, settings)
    if not iconFrame then return end
    local iconTexture = iconFrame.icon or iconFrame.Icon or iconFrame.IconTexture
    if not iconTexture then return end

    local zoom = settings.iconZoom or 0
    zoom = math.max(0, math.min(zoom, 0.45)) -- clamp for safety

    iconTexture:ClearAllPoints()
    iconTexture:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
    iconTexture:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)

    local left = zoom
    local right = 1 - zoom
    local top = zoom
    local bottom = 1 - zoom
    iconTexture:SetTexCoord(left, right, top, bottom)
end

local function ApplyIconBorder(iconFrame, settings)
    if not iconFrame then return end

    local size = settings.iconBorderSize or 0
    local borderSize = DDingUI:ScaleBorder(size)

    -- Use texture-based borders like BetterCooldownManager (no SetBackdrop = no taint)
    local state = GetFrameState(iconFrame)
    state.iconBorders = state.iconBorders or {}
    local borders = state.iconBorders

    if #borders == 0 then
        local function CreateBorderLine()
            return iconFrame:CreateTexture(nil, "OVERLAY")
        end
        local topBorder = CreateBorderLine()
        topBorder:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
        topBorder:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 0, 0)

        local bottomBorder = CreateBorderLine()
        bottomBorder:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", 0, 0)
        bottomBorder:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)

        local leftBorder = CreateBorderLine()
        leftBorder:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
        leftBorder:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", 0, 0)

        local rightBorder = CreateBorderLine()
        rightBorder:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 0, 0)
        rightBorder:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)

        state.iconBorders = { topBorder, bottomBorder, leftBorder, rightBorder }
        borders = state.iconBorders
    end

    local top, bottom, left, right = unpack(borders)
    if top and bottom and left and right then
        local c = settings.iconBorderColor or {0, 0, 0, 1}
        local shouldShow = borderSize > 0

        top:SetHeight(borderSize)
        bottom:SetHeight(borderSize)
        left:SetWidth(borderSize)
        right:SetWidth(borderSize)

        for _, borderTex in ipairs(borders) do
            borderTex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            borderTex:SetShown(shouldShow)
        end
    end
end

local function GetBarBackground(bar)
    if not bar then return nil end
    if bar.BarBG then
        return bar.BarBG
    end
    local state = GetFrameState(bar)
    if state.barBG and state.barBG.GetObjectType and state.barBG:GetObjectType() == "Texture" then
        return state.barBG
    end

    for _, region in ipairs({ bar:GetRegions() }) do
        if region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas == "UI-HUD-CoolDownManager-Bar-BG" or atlas == "UI-HUD-CooldownManager-Bar-BG" then
                state.barBG = region
                return region
            end
        end
    end

    return nil
end

local function GetApplicationsFont(iconFrame)
    if not iconFrame then return nil end

    if iconFrame.Applications then
        if iconFrame.Applications.GetObjectType and iconFrame.Applications:GetObjectType() == "FontString" then
            return iconFrame.Applications
        elseif iconFrame.Applications.GetRegions then
            for _, region in ipairs({ iconFrame.Applications:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    return region
                end
            end
        end
    end

    for _, region in ipairs({ iconFrame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            local name = region:GetName()
            if name and (name:find("Applications") or name:find("Stack")) then
                return region
            end
        end
    end

    return nil
end

local function InstallBuffBarVisibilityShowHook(ownerFrame, hookKey, textElement, settingKey)
    if not ownerFrame or not textElement or not hooksecurefunc then return end

    local state = GetFrameState(ownerFrame)
    if not state or state[hookKey] then return end

    local ok = pcall(hooksecurefunc, textElement, "Show", function(self)
        local current = GetFrameState(ownerFrame)
        local currentSettings = current and current.lastSettings
        if currentSettings and currentSettings[settingKey] == false then
            self:Hide()
            self:SetAlpha(0)
        end
    end)
    if ok then
        state[hookKey] = true
    end
end

local function HideStoredBorders(ownerFrame, stateKey)
    local state = GetFrameState(ownerFrame)
    local borders = state and state[stateKey]
    if not borders then return end

    for _, borderTex in ipairs(borders) do
        borderTex:Hide()
    end
end

local function ResetViewerLayoutState(viewer)
    local state = GetFrameState(viewer)
    if state then
        state.lastBarLayoutKey = nil
    end
end

local function EnsureBuffBarRefreshDispatchFrame()
    if BuffBar.__barContentRefreshDispatchFrame then return end
    local frame = CreateFrame("Frame")
    frame:Hide()
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not BuffBar.__barContentRefreshQueued then
            self:Hide()
            return
        end

        BuffBar.__barContentRefreshDelayRemaining = (BuffBar.__barContentRefreshDelayRemaining or 0) - (elapsed or 0)
        if BuffBar.__barContentRefreshDelayRemaining > 0 then
            return
        end

        self:Hide()
        BuffBar.__barContentRefreshQueued = nil
        BuffBar.__barContentRefreshDelayRemaining = 0
        local resetLayout = BuffBar.__barContentRefreshResetLayout
        local safeCall = BuffBar.__barContentRefreshSafeCall
        BuffBar.__barContentRefreshResetLayout = nil
        BuffBar.__barContentRefreshSafeCall = nil

        if resetLayout then
            ResetViewerLayoutState(_G["BuffBarCooldownViewer"])
        end
        if safeCall then
            pcall(function()
                BuffBar:Refresh()
            end)
        else
            BuffBar:Refresh()
        end
    end)
    BuffBar.__barContentRefreshDispatchFrame = frame
end

local function QueueBuffBarRefresh(delay, resetLayout, safeCall)
    BuffBar.__barContentRefreshResetLayout = BuffBar.__barContentRefreshResetLayout or resetLayout
    BuffBar.__barContentRefreshSafeCall = BuffBar.__barContentRefreshSafeCall or safeCall
    delay = delay or 0.01
    if BuffBar.__barContentRefreshQueued then
        BuffBar.__barContentRefreshDelayRemaining = math.min(BuffBar.__barContentRefreshDelayRemaining or delay, delay)
        return
    end

    BuffBar.__barContentRefreshQueued = true
    BuffBar.__barContentRefreshDelayRemaining = delay
    EnsureBuffBarRefreshDispatchFrame()
    BuffBar.__barContentRefreshDispatchFrame:Show()
end

local function GetIconPosition(settings)
    if settings.hideIcon then
        return "HIDDEN"
    end

    local iconPosition = settings.iconPosition or "LEFT"
    if iconPosition ~= "RIGHT" and iconPosition ~= "HIDDEN" then
        iconPosition = "LEFT"
    end
    return iconPosition
end

local function EnsureOverlayContainer(parent, state, stateKey, levelOffset)
    if not parent or not state then return nil end

    local container = state[stateKey]
    if not container then
        container = CreateFrame("Frame", nil, parent)
        state[stateKey] = container
    end

    if container:GetParent() ~= parent then
        container:SetParent(parent)
    end
    container:ClearAllPoints()
    container:SetAllPoints(parent)
    container:SetFrameLevel((parent:GetFrameLevel() or 0) + (levelOffset or 6))
    container:Show()
    return container
end

local function InstallBarContentHook(child, childState)
    if not child or not childState or childState.barContentHooked or not child.SetBarContent or not hooksecurefunc then
        return
    end

    local ok = pcall(hooksecurefunc, child, "SetBarContent", function(self)
        local state = GetFrameState(self)
        if state then
            state.lastStyleKey = nil
        end
        ResetViewerLayoutState(_G["BuffBarCooldownViewer"])
        QueueBuffBarRefresh(0.01)
    end)
    if ok then
        childState.barContentHooked = true
    end
end

local function StyleBarChild(child, settings, viewer)
    if not child or not child.Bar then return end

    -- Wrap entire styling in pcall to prevent Blizzard taint errors
    local success, err = pcall(function()

    local bar = child.Bar
    local childState = GetFrameState(child)
    if childState then
        childState.lastSettings = settings
    end
    InstallBarContentHook(child, childState)
    local barState = GetFrameState(bar)
    local iconFrame = child.Icon or child.IconFrame or child.IconButton
    local applicationsFS = GetApplicationsFont(iconFrame)
    local barHeight = PixelSnap(ComputeBarHeight(settings, bar))
    local iconSize = barHeight
    local iconBorderSize = settings.iconBorderSize or 0
    local iconBorderScaled = DDingUI:ScaleBorder(iconBorderSize)
    local barIndex = GetBarIndex(child)
    local iconPosition = GetIconPosition(settings)
    local iconHidden = iconPosition == "HIDDEN"
    local iconGap = iconHidden and 0 or PixelSnap(DDingUI:Scale(settings.iconGap or 0))
    local iconVisible = not iconHidden and iconFrame ~= nil

    if iconHidden then
        iconSize = 0
        if applicationsFS and bar then
            if applicationsFS:GetParent() ~= bar then
                applicationsFS:SetParent(bar)
            end
        end
        if iconFrame then
            iconFrame:Hide()
            iconFrame:SetAlpha(0)
            -- Collapse icon frame so bar anchors flush left
            iconFrame:ClearAllPoints()
            iconFrame:SetSize(0.001, 0.001)
            iconFrame:SetPoint("LEFT", child, "LEFT", 0, 0)
            HideStoredBorders(iconFrame, "iconBorders")
        end
    else
        if settings.hideIconMask ~= false then
            ApplyIconMaskSettings(iconFrame, settings)
        end
        ApplyIconZoom(iconFrame, settings)
        ApplyIconBorder(iconFrame, settings)

        if iconFrame then
            iconFrame:Show()
            iconFrame:SetAlpha(1)
            -- Restore icon size when showing
            local iconFrameSize = PixelSnap(barHeight + (iconBorderScaled * 2))
            iconFrame:ClearAllPoints()
            iconFrame:SetSize(iconFrameSize, iconFrameSize)
            if iconPosition == "RIGHT" then
                iconFrame:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            else
                iconFrame:SetPoint("LEFT", child, "LEFT", 0, 0)
            end
        end
        if applicationsFS then
            applicationsFS:Show()
            if applicationsFS:GetParent() ~= iconFrame then
                applicationsFS:SetParent(iconFrame)
            end
        end
    end
    local iconTotalWidth = iconVisible and PixelSnap(iconSize + (iconBorderScaled * 2)) or 0
    local iconTotalHeight = iconVisible and PixelSnap(iconSize + (iconBorderScaled * 2)) or 0
    local barWidth = ComputeBarWidth(settings, viewer, iconTotalWidth, iconGap, 0)
    -- Bar visuals
    local tex = DDingUI.GetTexture and DDingUI:GetTexture(settings.texture) or WHITE8
    bar:SetStatusBarTexture(tex)
    local color = GetBarColor(settings, barIndex) or settings.barColor or { 0.9, 0.9, 0.9, 1 }
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    if barState then
        barState.barIndex = barIndex
    end
    local barBG = GetBarBackground(bar)
    if barBG then
        barBG:SetTexture(WHITE8)
        local bg = settings.bgColor or { 0.1, 0.1, 0.1, 0.7 }
        barBG:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
        barBG:ClearAllPoints()
        barBG:SetPoint("TOPLEFT", bar, "TOPLEFT")
        barBG:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
        barBG:SetDrawLayer("BACKGROUND", 0)
    end

    if bar.Pip then
        -- Hide Blizzard's end-cap "spark" so it doesn't overhang the bar
        bar.Pip:Hide()
        if bar.Pip.SetTexture then
            bar.Pip:SetTexture(nil)
        end
        if childState and not childState.pipShowHooked and hooksecurefunc then
            local ok = pcall(hooksecurefunc, bar.Pip, "Show", function(self)
                self:Hide()
                self:SetAlpha(0)
                if self.SetTexture then
                    self:SetTexture(nil)
                end
            end)
            if ok then
                childState.pipShowHooked = true
            end
        end
    end

    -- Use texture-based borders like BetterCooldownManager (no SetBackdrop = no taint)
    local borderSize = DDingUI:ScaleBorder(settings.borderSize or 1)

    if not barState then return end
    barState.barBorders = barState.barBorders or {}
    local borders = barState.barBorders

    if #borders == 0 then
        local function CreateBorderLine()
            return bar:CreateTexture(nil, "OVERLAY")
        end
        local topBorder = CreateBorderLine()
        topBorder:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        topBorder:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)

        local bottomBorder = CreateBorderLine()
        bottomBorder:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        bottomBorder:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

        local leftBorder = CreateBorderLine()
        leftBorder:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        leftBorder:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)

        local rightBorder = CreateBorderLine()
        rightBorder:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        rightBorder:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

        barState.barBorders = { topBorder, bottomBorder, leftBorder, rightBorder }
        borders = barState.barBorders
    end

    local top, bottom, left, right = unpack(borders)
    if top and bottom and left and right then
        local bc = settings.borderColor or { 0, 0, 0, 1 }
        local shouldShow = borderSize > 0

        top:SetHeight(borderSize)
        bottom:SetHeight(borderSize)
        left:SetWidth(borderSize)
        right:SetWidth(borderSize)

        for _, borderTex in ipairs(borders) do
            borderTex:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 1)
            borderTex:SetShown(shouldShow)
            borderTex:SetDrawLayer("OVERLAY", 7)
        end
    end

    bar:SetHeight(barHeight)
    if barWidth then
        local effectiveBarWidth = PixelSnap(math.max(1, barWidth))
        local effectiveFrameWidth = effectiveBarWidth + iconTotalWidth + iconGap
        bar:SetWidth(effectiveBarWidth)
        child:SetWidth(effectiveFrameWidth)

        bar:ClearAllPoints()
        if iconHidden then
            bar:SetPoint("LEFT", child, "LEFT", 0, 0)
            bar:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        elseif iconPosition == "RIGHT" then
            bar:SetPoint("LEFT", child, "LEFT", 0, 0)
            bar:SetPoint("RIGHT", iconFrame or child, iconFrame and "LEFT" or "RIGHT", iconFrame and -iconGap or 0, 0)
        else
            bar:SetPoint("LEFT", iconFrame or child, iconFrame and "RIGHT" or "LEFT", iconFrame and iconGap or 0, 0)
            bar:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        end
    end

    -- Sync child frame height to match bar height (prevents gaps between bars)
    local childHeight = barHeight
    if iconVisible then
        childHeight = math.max(barHeight, iconTotalHeight)
    end
    child:SetHeight(childHeight)

    -- Text styling
    local nameFS = bar.Name
    local durFS = bar.Duration
    local textContainer
    if barState then
        if (nameFS and settings.showName ~= false) or (durFS and settings.showDuration ~= false) then
            textContainer = EnsureOverlayContainer(bar, barState, "barTextContainer", 6)
        elseif barState.barTextContainer then
            barState.barTextContainer:Hide()
        end
    end

    if nameFS then
        InstallBuffBarVisibilityShowHook(child, "nameShowHooked", nameFS, "showName")
        if settings.showName == false then
            nameFS:Hide()
            nameFS:SetAlpha(0)
        else
            if textContainer and nameFS:GetParent() ~= textContainer then
                nameFS:SetParent(textContainer)
            end
            nameFS:Show()
            nameFS:SetAlpha(1)
            if nameFS.SetIgnoreParentScale then nameFS:SetIgnoreParentScale(true) end
            local nameFont = DDingUI:GetFont(settings.nameFont)
            if nameFont then
                nameFS:SetFont(nameFont, settings.nameSize or 14, "OUTLINE")
            else
                nameFS:SetFont(nameFS:GetFont(), settings.nameSize or 14, "OUTLINE")
            end
            local nc = settings.nameColor or {1, 1, 1, 1}
            nameFS:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
            if nameFS.SetShadowOffset then nameFS:SetShadowOffset(0, 0) end
            if nameFS.SetDrawLayer then nameFS:SetDrawLayer("OVERLAY", 7) end
            if nameFS.SetWordWrap then nameFS:SetWordWrap(false) end
            if nameFS.SetNonSpaceWrap then nameFS:SetNonSpaceWrap(false) end
            nameFS:ClearAllPoints()
            local anchor = settings.nameAnchor or "LEFT"
            if anchor == "MIDDLE" then anchor = "CENTER" end
            local ax = settings.nameOffsetX or 0
            local ay = settings.nameOffsetY or 0
            nameFS:SetPoint(anchor, bar, anchor, ax, ay)
        end
    end

    if applicationsFS and (iconFrame or bar) then
        InstallBuffBarVisibilityShowHook(child, "applicationsShowHooked", applicationsFS, "showApplications")
        if settings.showApplications == false then
            applicationsFS:Hide()
            applicationsFS:SetAlpha(0)
            if barState and barState.barAppTextContainer then
                barState.barAppTextContainer:Hide()
            end
        else
            local appContainer = EnsureOverlayContainer(bar, barState, "barAppTextContainer", 6)
            if appContainer and applicationsFS:GetParent() ~= appContainer then
                applicationsFS:SetParent(appContainer)
            end
            applicationsFS:SetAlpha(1)
            if settings.applicationsSize then
                local appFont = DDingUI:GetFont(settings.applicationsFont)
                if appFont then
                    applicationsFS:SetFont(appFont, settings.applicationsSize, "OUTLINE")
                else
                    applicationsFS:SetFont(applicationsFS:GetFont(), settings.applicationsSize, "OUTLINE")
                end
            end
            local ac = settings.applicationsColor or {1, 1, 1, 1}
            applicationsFS:SetTextColor(ac[1], ac[2], ac[3], ac[4] or 1)
            if applicationsFS.SetIgnoreParentScale then applicationsFS:SetIgnoreParentScale(true) end
            if applicationsFS.SetShadowOffset then applicationsFS:SetShadowOffset(0, 0) end
            if applicationsFS.SetDrawLayer then applicationsFS:SetDrawLayer("OVERLAY", 7) end
            if applicationsFS.SetJustifyH then applicationsFS:SetJustifyH("CENTER") end

            applicationsFS:ClearAllPoints()
            local anchor = settings.applicationsAnchor or "BOTTOMRIGHT"
            if anchor == "MIDDLE" then
                anchor = "CENTER"
            end
            local ax = settings.applicationsOffsetX or 0
            local ay = settings.applicationsOffsetY or 0
            local target = iconVisible and iconFrame or bar
            applicationsFS:SetPoint(anchor, target, anchor, ax, ay)
            applicationsFS:Show()
        end
    end

    if durFS then
        InstallBuffBarVisibilityShowHook(child, "durationShowHooked", durFS, "showDuration")
        if settings.showDuration == false then
            durFS:Hide()
            durFS:SetAlpha(0)
        else
            if textContainer and durFS:GetParent() ~= textContainer then
                durFS:SetParent(textContainer)
            end
            durFS:Show()
            durFS:SetAlpha(1)
            if durFS.SetIgnoreParentScale then durFS:SetIgnoreParentScale(true) end
            local durFont = DDingUI:GetFont(settings.durationFont)
            if durFont then
                durFS:SetFont(durFont, settings.durationSize or 12, "OUTLINE")
            else
                durFS:SetFont(durFS:GetFont(), settings.durationSize or 12, "OUTLINE")
            end
            local dc = settings.durationColor or {1, 1, 1, 1}
            durFS:SetTextColor(dc[1], dc[2], dc[3], dc[4] or 1)
            if durFS.SetShadowOffset then durFS:SetShadowOffset(0, 0) end
            if durFS.SetDrawLayer then durFS:SetDrawLayer("OVERLAY", 7) end
            durFS:ClearAllPoints()
            local anchor = settings.durationAnchor or "RIGHT"
            if anchor == "MIDDLE" then anchor = "CENTER" end
            local ax = settings.durationOffsetX or 0
            local ay = settings.durationOffsetY or 0
            durFS:SetPoint(anchor, bar, anchor, ax, ay)
        end
    end

    -- Hide Blizzard debuff border if present
    if child.DebuffBorder then
        child.DebuffBorder:Hide()
    end

    end) -- end pcall

    if not success and err then
        -- Silently ignore Blizzard taint errors
    end
end

function BuffBar:ApplyViewerStyle(viewer, settings)
    if not viewer or not settings then return end

    local viewerState = GetFrameState(viewer)

    -- Apply grow direction (BOTTOM = bars grow upward, TOP = bars grow downward)
    local growDirection = settings.growDirection or "BOTTOM"

    local children = CollectBarFrames(viewer)
    if #children > 0 then
        local visibleChildren = {}
        for _, child in ipairs(children) do
            if child:IsShown() then
                table.insert(visibleChildren, child)
            end
        end

        table.sort(children, function(a, b)
            return GetBarIndex(a) < GetBarIndex(b)
        end)

        table.sort(visibleChildren, function(a, b)
            return GetBarIndex(a) < GetBarIndex(b)
        end)

        -- Apply individual bar styles (all bars including hidden)
        for _, child in ipairs(children) do
            StyleBarChild(child, settings, viewer)
        end

        local spacing = PixelSnap(DDingUI:Scale(settings.barSpacing ~= nil and settings.barSpacing or 2))
        local iconPosition = GetIconPosition(settings)
        local iconGap = settings.iconGap or 0

        -- Reposition only VISIBLE bars based on grow direction
        local layoutKey = growDirection .. "_" .. #visibleChildren
            .. "_h" .. tostring(settings.height or 16)
            .. "_s" .. tostring(spacing)
            .. "_i" .. tostring(iconPosition)
            .. "_g" .. tostring(iconGap)
        for _, child in ipairs(visibleChildren) do
            layoutKey = layoutKey .. "_" .. tostring(GetBarIndex(child))
        end

        if viewerState.lastBarLayoutKey == layoutKey then
            return -- Layout unchanged, skip repositioning to avoid ping-pong
        end
        viewerState.lastBarLayoutKey = layoutKey

        if #visibleChildren > 0 then
            local xOffset = 0

            -- Suppress OnSizeChanged feedback during repositioning
            viewerState.barLayoutInProgress = true

            for i, child in ipairs(visibleChildren) do
                pcall(function()
                    child:ClearAllPoints()
                    if growDirection == "TOP" then
                        if i == 1 then
                            child:SetPoint("TOP", viewer, "TOP", xOffset, 0)
                        else
                            child:SetPoint("TOP", visibleChildren[i-1], "BOTTOM", 0, -spacing)
                        end
                    else
                        if i == 1 then
                            child:SetPoint("BOTTOM", viewer, "BOTTOM", xOffset, 0)
                        else
                            child:SetPoint("BOTTOM", visibleChildren[i-1], "TOP", 0, spacing)
                        end
                    end
                end)
            end

            viewerState.barLayoutInProgress = nil
        end
    end
end

function BuffBar:Refresh()
    -- CRITICAL: Skip refresh during combat to prevent taint propagation
    -- (Custom anchor is maintained by hooksecurefunc on SetPoint instead)
    if InCombatLockdown() then
        if not BuffBar.__refreshQueued then
            BuffBar.__refreshQueued = true
        end
        return
    end

    -- Prevent recursive refresh
    if BuffBar.__refreshInProgress then return end
    BuffBar.__refreshInProgress = true

    local settings = GetSettings()
    if not settings then
        BuffBar.__refreshInProgress = nil
        return
    end

    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        BuffBar.__refreshInProgress = nil
        return
    end

    if settings.enabled == false then
        viewer:Hide()
        BuffBar.__refreshInProgress = nil
        return
    end

    viewer:Show()

    -- Position is managed by DDingUI's own mover mode. anchorFrame is only
    -- used as the auto-width reference for ComputeBarWidth.
    ApplyViewerPosition(viewer, settings)

    self:ApplyViewerStyle(viewer, settings)
    BuffBar.__refreshInProgress = nil
end

local function TryHookViewer()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return false
    end

    local viewerState = GetFrameState(viewer)
    if viewerState.buffBarHooked then
        return viewer ~= nil
    end

    viewerState.buffBarHooked = true

    viewer:HookScript("OnShow", function()
        BuffBar:Refresh()
    end)
    viewer:HookScript("OnSizeChanged", function()
        local state = GetFrameState(viewer)
        if state.barLayoutInProgress then return end
        if state.sizeChangedTimer then
            state.sizeChangedTimer:Cancel()
        end
        state.sizeChangedTimer = C_Timer.NewTimer(0.05, function()
            state.sizeChangedTimer = nil
            ResetViewerLayoutState(viewer)
            BuffBar:Refresh()
        end)
    end)

    if viewer.Bar and viewer.Bar.HookScript then
        viewer.Bar:HookScript("OnSizeChanged", function()
            local state = GetFrameState(viewer)
            if state.barSizeChangedTimer then
                state.barSizeChangedTimer:Cancel()
            end
            state.barSizeChangedTimer = C_Timer.NewTimer(0.05, function()
                state.barSizeChangedTimer = nil
                ResetViewerLayoutState(viewer)
                BuffBar:Refresh()
            end)
        end)
    end

    BuffBar:Refresh()
    return true
end

function BuffBar:Initialize()
    if self.__initialized then return end
    self.__initialized = true

    local hooked = TryHookViewer()
    if not hooked then
        C_Timer.After(0.25, TryHookViewer)
        C_Timer.After(0.75, TryHookViewer)
        C_Timer.After(1.5, TryHookViewer)
    end

    -- Refresh layout when player auras change (bars can hide/show)
    if not self.__eventFrame then
        local f = CreateFrame("Frame")
        f:RegisterUnitEvent("UNIT_AURA", "player")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_REGEN_ENABLED" then
                if BuffBar.__refreshQueued then
                    BuffBar.__refreshQueued = nil
                    QueueBuffBarRefresh(0.1, false, true)
                end
                return
            end

            if unit and unit ~= "player" then return end
            QueueBuffBarRefresh(0.05, true, true)
        end)
        self.__eventFrame = f
    end

    -- Hook Blizzard CooldownViewerSettings bar list to add per-bar color picker
    if not self.__settingsHooked then
        self.__settingsHooked = true
        local function ApplyBarColorsToItem(item, index)
            if not item or not item.Bar then return end

            local settings = GetSettings()
            if not settings then return end

            local savedColor = (settings.barColors and settings.barColors[index]) or settings.barColor or {1, 1, 1, 1}
            local fill = item.Bar.FillTexture or (item.Bar.GetStatusBarTexture and item.Bar:GetStatusBarTexture())
            if fill then
                fill:SetVertexColor(savedColor[1], savedColor[2], savedColor[3], savedColor[4] or 1)
            end

            local itemState = GetFrameState(item)
            if not itemState.colorSwatch then
                local swatch = CreateFrame("Button", nil, item, "ColorSwatchTemplate")
                swatch:SetPoint("LEFT", item, "RIGHT", 4, 0)
                swatch:SetSize(18, 18)
                swatch:Show()
                itemState.colorSwatch = swatch
            end

            local swatch = itemState.colorSwatch
            swatch:SetColorRGB(savedColor[1], savedColor[2], savedColor[3])
            swatch:Show()

            swatch:SetScript("OnClick", function()
                local info = {}
                info.r, info.g, info.b, info.opacity = savedColor[1], savedColor[2], savedColor[3], savedColor[4] or 1
                info.hasOpacity = true
                info.swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = ColorPickerFrame:GetColorAlpha()
                    SetBarColor(settings, index, { r, g, b, a })
                    if fill then
                        fill:SetVertexColor(r, g, b, a)
                    end
                    swatch:SetColorRGB(r, g, b)
                end
                info.cancelFunc = function()
                    local r, g, b, a = ColorPickerFrame:GetPreviousValues()
                    SetBarColor(settings, index, { r, g, b, a })
                    if fill then
                        fill:SetVertexColor(r, g, b, a)
                    end
                    swatch:SetColorRGB(r, g, b)
                end
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
        end

        local function HookSettingsBar(self)
            if not self or not self.itemPool then return end
            local activeItems = {}
            for item in self.itemPool:EnumerateActive() do
                table.insert(activeItems, item)
            end
            table.sort(activeItems, function(a, b)
                local aIdx = a.orderIndex or 0
                local bIdx = b.orderIndex or 0
                return aIdx < bIdx
            end)

            local visibleIndex = 0
            for _, item in ipairs(activeItems) do
                if item.Bar and item.Bar.Name and not item.Icon:IsDesaturated() then
                    visibleIndex = visibleIndex + 1
                    ApplyBarColorsToItem(item, visibleIndex)
                end
            end
        end

        if CooldownViewerSettingsBarCategoryMixin then
            hooksecurefunc(CooldownViewerSettingsBarCategoryMixin, "RefreshLayout", HookSettingsBar)
            local specFrame = CreateFrame("Frame")
            specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            specFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
            specFrame:SetScript("OnEvent", function(_, event)
                -- [FIX] 설정바 리프레시 (기존 로직)
                if CooldownViewerSettingsBar and CooldownViewerSettingsBar.RefreshLayout then
                    CooldownViewerSettingsBar:RefreshLayout()
                end
                -- [FIX] 스펙 변경 시 뷰어 재생성 대응: 훅 리셋 + 재훅
                C_Timer.After(0.5, function()
                    local viewer = _G["BuffBarCooldownViewer"]
                    if viewer then
                        ResetViewerLayoutState(viewer)
                    end
                    TryHookViewer()
                end)
                C_Timer.After(2.0, function()
                    TryHookViewer()
                    BuffBar:Refresh()
                end)
            end)
        end
    end
end

-- Convenience export for external calls
DDingUI.RefreshBuffBarCooldownViewer = function(self)
    return BuffBar:Refresh()
end

-- Debug command: /ddingbar
SLASH_DDINGBAR1 = "/ddingbar"
SlashCmdList["DDINGBAR"] = function()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: |cffff0000BuffBarCooldownViewer not found|r") -- [STYLE]
        return
    end

    local allChildren = { viewer:GetChildren() }
    print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: BuffBar Debug - Total children: " .. #allChildren) -- [STYLE]
    print("  Viewer size: " .. string.format("%.1f x %.1f", viewer:GetWidth(), viewer:GetHeight()))
    print("  Viewer shown: " .. tostring(viewer:IsShown()))

    for i, child in ipairs(allChildren) do
        local hasBar = child.Bar ~= nil
        local shown = child:IsShown()
        local w, h = child:GetWidth(), child:GetHeight()
        local nameText = ""
        local barH, barW = 0, 0

        if hasBar then
            pcall(function()
                if child.Bar.Name then
                    nameText = child.Bar.Name:GetText() or "<nil>"
                end
                barH = child.Bar:GetHeight()
                barW = child.Bar:GetWidth()
            end)
        end

        local layoutIdx = "<nil>"
        pcall(function() if child.layoutIndex ~= nil then layoutIdx = tostring(child.layoutIndex) end end)
        local frameID = (child.GetID and child:GetID()) or "<nil>"

        local cdID = "<nil>"
        pcall(function()
            if child.cooldownID then cdID = tostring(child.cooldownID)
            elseif child.cooldownInfo and child.cooldownInfo.cooldownID then cdID = tostring(child.cooldownInfo.cooldownID)
            end
        end)

        local auraID = "<nil>"
        pcall(function() auraID = tostring(child.auraInstanceID) end)

        local color = shown and "|cff00ff00" or "|cffff0000"
        local barColor = hasBar and "|cff00ff00Bar|r" or "|cffff0000NoBar|r"

        print(string.format("  %s#%d|r %s shown=%s layout=%s id=%s",
            color, i, barColor, tostring(shown), tostring(layoutIdx), tostring(frameID)))
        if hasBar then
            print(string.format("    Name: \"%s\"  cdID: %s  auraID: %s",
                nameText, cdID, auraID))
            print(string.format("    child: %.0fx%.0f  bar: %.0fx%.0f  delta: %.0f",
                w, h, barW, barH, h - barH))
        end
    end

    local barCount, shownCount, emptyCount = 0, 0, 0
    for _, child in ipairs(allChildren) do
        if child.Bar then
            barCount = barCount + 1
            if child:IsShown() then
                shownCount = shownCount + 1
                pcall(function()
                    if child.Bar.Name then
                        local t = child.Bar.Name:GetText()
                        if not t or t == "" then
                            emptyCount = emptyCount + 1
                        end
                    end
                end)
            end
        end
    end
    print(string.format("  |cff00ccff[Summary]|r bars=%d shown=%d empty_shown=%d",
        barCount, shownCount, emptyCount))
end
