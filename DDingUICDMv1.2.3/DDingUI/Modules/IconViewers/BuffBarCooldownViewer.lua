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
    return child.layoutIndex or child.orderIndex or (child.GetID and child:GetID()) or 1
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
    iconFrame.__dduiIconBorders = iconFrame.__dduiIconBorders or {}
    local borders = iconFrame.__dduiIconBorders

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

        iconFrame.__dduiIconBorders = { topBorder, bottomBorder, leftBorder, rightBorder }
        borders = iconFrame.__dduiIconBorders
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
    if bar.__dduiBarBG and bar.__dduiBarBG.GetObjectType and bar.__dduiBarBG:GetObjectType() == "Texture" then
        return bar.__dduiBarBG
    end

    for _, region in ipairs({ bar:GetRegions() }) do
        if region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas == "UI-HUD-CoolDownManager-Bar-BG" or atlas == "UI-HUD-CooldownManager-Bar-BG" then
                bar.__dduiBarBG = region
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

local function RaiseTextLayer(fs, owner)
    -- No-op; frame level adjustments removed
end

local function StyleBarChild(child, settings, viewer)
    if not child or not child.Bar then return end

    -- Wrap entire styling in pcall to prevent Blizzard taint errors
    local success, err = pcall(function()

    local bar = child.Bar
    local iconFrame = child.Icon or child.IconFrame or child.IconButton
    local applicationsFS = GetApplicationsFont(iconFrame)
    local barHeight = PixelSnap(ComputeBarHeight(settings, bar))
    local iconSize = barHeight
    local font = (DDingUI.GetFont and DDingUI:GetFont(nil)) or (DDingUI.GetGlobalFont and DDingUI:GetGlobalFont()) or nil
    local iconBorderSize = settings.iconBorderSize or 0
    local iconBorderScaled = DDingUI:ScaleBorder(iconBorderSize)
    local barIndex = GetBarIndex(child)

    if settings.hideIcon then
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
            if iconFrame.__dduiIconBorder then
                iconFrame.__dduiIconBorder:Hide()
            end
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
            iconFrame:SetPoint("LEFT", child, "LEFT", 0, 0)
        end
        if applicationsFS then
            applicationsFS:Show()
            if applicationsFS:GetParent() ~= iconFrame then
                applicationsFS:SetParent(iconFrame)
            end
        end
    end
    local iconTotalWidth = settings.hideIcon and 0 or PixelSnap(iconSize + (iconBorderScaled * 2))
    local iconTotalHeight = settings.hideIcon and 0 or PixelSnap(iconSize + (iconBorderScaled * 2))
    local barBorderSize = DDingUI:ScaleBorder(settings.borderSize or 1)

    local barWidth = ComputeBarWidth(settings, viewer, iconTotalWidth, 0, 0)
    -- Bar visuals
    local tex = DDingUI.GetTexture and DDingUI:GetTexture(settings.texture) or WHITE8
    bar:SetStatusBarTexture(tex)
    local color = GetBarColor(settings, barIndex) or settings.barColor or { 0.9, 0.9, 0.9, 1 }
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    bar.__dduiBarIndex = barIndex
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
        bar.Pip:SetTexture(nil)
    end

    -- Use texture-based borders like BetterCooldownManager (no SetBackdrop = no taint)
    local borderSize = DDingUI:ScaleBorder(settings.borderSize or 1)

    bar.__dduiBarBorders = bar.__dduiBarBorders or {}
    local borders = bar.__dduiBarBorders

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

        bar.__dduiBarBorders = { topBorder, bottomBorder, leftBorder, rightBorder }
        borders = bar.__dduiBarBorders
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
        bar:SetWidth(effectiveBarWidth)
        child:SetWidth(effectiveBarWidth + iconTotalWidth)
        -- Re-anchor bar so it starts flush after icon (or at child left when icon hidden)
        bar:ClearAllPoints()
        if settings.hideIcon then
            bar:SetPoint("LEFT", child, "LEFT", 0, 0)
        else
            bar:SetPoint("LEFT", iconFrame or child, "RIGHT", 0, 0)
        end
    end

    -- Sync child frame height to match bar height (prevents gaps between bars)
    local childHeight = barHeight
    if not settings.hideIcon then
        childHeight = math.max(barHeight, iconTotalHeight)
    end
    child:SetHeight(childHeight)

    -- Text styling
    local nameFS = bar.Name
    if nameFS then
        if settings.showName == false then
            nameFS:Hide()
        else
            nameFS:Show()
            local nameFont = DDingUI:GetFont(settings.nameFont)
            if nameFont then
                nameFS:SetFont(nameFont, settings.nameSize or 14, "OUTLINE")
            else
                nameFS:SetFont(nameFS:GetFont(), settings.nameSize or 14, "OUTLINE")
            end
            local nc = settings.nameColor or {1, 1, 1, 1}
            nameFS:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
            nameFS:ClearAllPoints()
            local anchor = settings.nameAnchor or "LEFT"
            if anchor == "MIDDLE" then anchor = "CENTER" end
            local ax = settings.nameOffsetX or 0
            local ay = settings.nameOffsetY or 0
            nameFS:SetPoint(anchor, bar, anchor, ax, ay)
        end
    end

    if applicationsFS and (iconFrame or bar) then
        if settings.showApplications == false then
            applicationsFS:Hide()
        else
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

            applicationsFS:ClearAllPoints()
            local anchor = settings.applicationsAnchor or "BOTTOMRIGHT"
            if anchor == "MIDDLE" then
                anchor = "CENTER"
            end
            local ax = settings.applicationsOffsetX or 0
            local ay = settings.applicationsOffsetY or 0
            local target = settings.hideIcon and bar or iconFrame
            if settings.hideIcon then
                if applicationsFS:GetParent() ~= bar then
                    applicationsFS:SetParent(bar)
                end
            else
                if applicationsFS:GetParent() ~= iconFrame then
                    applicationsFS:SetParent(iconFrame)
                end
            end
            applicationsFS:SetPoint(anchor, target, anchor, ax, ay)
            applicationsFS:Show()
        end
    end

    local durFS = bar.Duration
    if durFS then
        if settings.showDuration == false then
            durFS:Hide()
        else
            durFS:Show()
            local durFont = DDingUI:GetFont(settings.durationFont)
            if durFont then
                durFS:SetFont(durFont, settings.durationSize or 12, "OUTLINE")
            else
                durFS:SetFont(durFS:GetFont(), settings.durationSize or 12, "OUTLINE")
            end
            local dc = settings.durationColor or {1, 1, 1, 1}
            durFS:SetTextColor(dc[1], dc[2], dc[3], dc[4] or 1)
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

    -- Apply grow direction (BOTTOM = bars grow upward, TOP = bars grow downward)
    local growDirection = settings.growDirection or "BOTTOM"

    if viewer.GetChildren then
        local children = {}
        local visibleChildren = {}
        for _, child in ipairs({ viewer:GetChildren() }) do
            if child.Bar then
                table.insert(children, child)
                if child:IsShown() then
                    table.insert(visibleChildren, child)
                end
            end
        end

        table.sort(children, function(a, b)
            local la = a.layoutIndex or a:GetID() or 0
            local lb = b.layoutIndex or b:GetID() or 0
            return la < lb
        end)

        table.sort(visibleChildren, function(a, b)
            local la = a.layoutIndex or a:GetID() or 0
            local lb = b.layoutIndex or b:GetID() or 0
            return la < lb
        end)

        -- Apply individual bar styles (all bars including hidden)
        for _, child in ipairs(children) do
            StyleBarChild(child, settings, viewer)
        end

        -- Reposition only VISIBLE bars based on grow direction
        local layoutKey = growDirection .. "_" .. #visibleChildren
        for _, child in ipairs(visibleChildren) do
            layoutKey = layoutKey .. "_" .. tostring(child.layoutIndex or child:GetID() or 0)
        end

        if viewer.__dduiLastBarLayoutKey == layoutKey then
            return -- Layout unchanged, skip repositioning to avoid ping-pong
        end
        viewer.__dduiLastBarLayoutKey = layoutKey

        if #visibleChildren > 0 then
            local barHeight = PixelSnap(ComputeBarHeight(settings, visibleChildren[1].Bar))
            local spacing = 2  -- spacing between bars

            -- When icon hidden, shift bars right by half icon width to keep bar centered
            local xOffset = 0
            if settings.hideIcon then
                local iconBorderScaled = DDingUI:ScaleBorder(settings.iconBorderSize or 0)
                xOffset = PixelSnap(barHeight + (iconBorderScaled * 2)) / 2
            end

            -- Suppress OnSizeChanged feedback during repositioning
            viewer.__dduiBarLayoutInProgress = true

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

            viewer.__dduiBarLayoutInProgress = nil
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

    -- Position is managed by Blizzard EditMode (no custom anchor override)
    -- anchorFrame setting is used only for width auto-calculation in ComputeBarWidth

    self:ApplyViewerStyle(viewer, settings)
    BuffBar.__refreshInProgress = nil
end

local function TryHookViewer()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or viewer.__dduiBuffBarHooked then
        return viewer ~= nil
    end

    viewer.__dduiBuffBarHooked = true

    viewer:HookScript("OnShow", function()
        BuffBar:Refresh()
    end)
    viewer:HookScript("OnSizeChanged", function()
        if viewer.__dduiBarLayoutInProgress then return end
        if viewer.__dduiSizeChangedTimer then
            viewer.__dduiSizeChangedTimer:Cancel()
        end
        viewer.__dduiSizeChangedTimer = C_Timer.NewTimer(0.05, function()
            viewer.__dduiSizeChangedTimer = nil
            viewer.__dduiLastBarLayoutKey = nil
            BuffBar:Refresh()
        end)
    end)

    if viewer.Bar and viewer.Bar.HookScript then
        viewer.Bar:HookScript("OnSizeChanged", function()
            if viewer.__dduiBarSizeChangedTimer then
                viewer.__dduiBarSizeChangedTimer:Cancel()
            end
            viewer.__dduiBarSizeChangedTimer = C_Timer.NewTimer(0.05, function()
                viewer.__dduiBarSizeChangedTimer = nil
                viewer.__dduiLastBarLayoutKey = nil
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
        local throttle = 0
        f:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_REGEN_ENABLED" then
                if BuffBar.__refreshQueued then
                    BuffBar.__refreshQueued = nil
                    C_Timer.After(0.1, function()
                        pcall(function()
                            BuffBar:Refresh()
                        end)
                    end)
                end
                return
            end

            if unit and unit ~= "player" then return end
            throttle = throttle + 1
            if throttle > 1 then
                return
            end
            C_Timer.After(0.05, function()
                throttle = 0
                local viewer = _G["BuffBarCooldownViewer"]
                if viewer then
                    viewer.__dduiLastBarLayoutKey = nil
                end
                pcall(function()
                    BuffBar:Refresh()
                end)
            end)
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

            if not item.__dduiColorSwatch then
                local swatch = CreateFrame("Button", nil, item, "ColorSwatchTemplate")
                swatch:SetPoint("LEFT", item, "RIGHT", 4, 0)
                swatch:SetSize(18, 18)
                swatch:Show()
                item.__dduiColorSwatch = swatch
            end

            local swatch = item.__dduiColorSwatch
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
            specFrame:SetScript("OnEvent", function()
                if CooldownViewerSettingsBar and CooldownViewerSettingsBar.RefreshLayout then
                    CooldownViewerSettingsBar:RefreshLayout()
                end
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
        print("|cffff0000[DDingUI BuffBar]|r BuffBarCooldownViewer not found")
        return
    end

    local allChildren = { viewer:GetChildren() }
    print("|cff00ccff[DDingUI BuffBar Debug]|r Total children: " .. #allChildren)
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

        local layoutIdx = child.layoutIndex or "<nil>"
        local frameID = (child.GetID and child:GetID()) or "<nil>"

        local cdID = "<nil>"
        pcall(function()
            if child.cooldownID then cdID = tostring(child.cooldownID)
            elseif child.cooldownInfo and child.cooldownInfo.cooldownID then cdID = tostring(child.cooldownInfo.cooldownID)
            end
        end)

        local auraID = child.auraInstanceID and tostring(child.auraInstanceID) or "<nil>"

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
