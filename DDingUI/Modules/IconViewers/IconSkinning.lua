local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- Get IconViewers module
local IconViewers = DDingUI.IconViewers
if not IconViewers then
    error("DDingUI: IconViewers module not initialized! Load IconViewers.lua first.")
end

-- Reference shared weak tables (avoids tainting Blizzard frames)
local iconData = IconViewers._iconData
local cdData = IconViewers._cdData
local texData = IconViewers._texData

local function GetIconData(frame)
    local d = iconData[frame]
    if not d then d = {}; iconData[frame] = d end
    return d
end

local function GetCdData(frame)
    local d = cdData[frame]
    if not d then d = {}; cdData[frame] = d end
    return d
end

-- Helper Functions

local function IsCooldownIconFrame(frame)
    return frame and (frame.icon or frame.Icon) and frame.Cooldown
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

local function GetIconCountFont(icon)
    if not icon then return nil end

    -- 1. ChargeCount (charges)
    local charge = icon.ChargeCount
    if charge then
        local fs = charge.Current or charge.Text or charge.Count or nil

        if not fs and charge.GetRegions then
            for _, region in ipairs({ charge:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    fs = region
                    break
                end
            end
        end

        if fs then
            return fs
        end
    end

    -- 2. Applications (Buff stacks)
    local apps = icon.Applications
    if apps and apps.GetRegions then
        for _, region in ipairs({ apps:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                return region
            end
        end
    end

    -- 3. Fallback: look for named stack text
    for _, region in ipairs({ icon:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            local name = region:GetName()
            if name and (name:find("Stack") or name:find("Applications")) then
                return region
            end
        end
    end

    return nil
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

local function NeutralizeAtlasTexture(texture)
    if not texture then return end

    if texture.SetAtlas then
        texture:SetAtlas(nil)
        local td = texData[texture]
        if not (td and td.atlasNeutralized) then
            local tdd = GetIconData(texture) -- reuse GetIconData pattern for texData
            -- Actually use texData directly
            if not texData[texture] then texData[texture] = {} end
            texData[texture].atlasNeutralized = true
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

local function HideDebuffBorder(icon)
    if not icon then return end

    if icon.DebuffBorder then
        NeutralizeAtlasTexture(icon.DebuffBorder)
    end

    local name = icon.GetName and icon:GetName()
    if name and _G[name .. "DebuffBorder"] then
        NeutralizeAtlasTexture(_G[name .. "DebuffBorder"])
    end

    if icon.GetRegions then
        for _, region in ipairs({ icon:GetRegions() }) do
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                local regionName = region.GetName and region:GetName()
                if regionName and regionName:find("DebuffBorder", 1, true) then
                    NeutralizeAtlasTexture(region)
                end
            end
        end
    end
end

-- Icon Skinning

function IconViewers:SkinIcon(icon, settings)
    -- Skip skinning during EditMode to avoid triggering Blizzard secret value errors
    -- Check both IsShown() and editModeActive for complete protection
    if EditModeManagerFrame then
        local inEditMode = false
        pcall(function()
            inEditMode = EditModeManagerFrame:IsShown() or EditModeManagerFrame.editModeActive
        end)
        if inEditMode then return end
    end

    -- Get the icon texture frame (handle both .icon and .Icon for compatibility)
    local iconTexture = icon.icon or icon.Icon
    if not icon or not iconTexture then return end

    -- Skip if frame is forbidden (protected)
    if icon.IsForbidden and icon:IsForbidden() then return end

    -- Skip if icon is being released/reset by Blizzard's pool system
    -- Use pcall to safely check cooldownID without triggering taint
    local success, wasReset = pcall(function()
        -- [FIX] DynBridge 프레임(_ddIconKey)은 cooldownID 없어도 리셋이 아님
        if icon._ddIconKey then return false end
        local id = iconData[icon]
        return icon.cooldownID == nil and (id and id.skinned)
    end)
    if success and wasReset then
        -- Frame was reset by CDM pool system - hide our borders and reset skinned flag
        local id = iconData[icon]
        if id then
            if id.borders then
                for _, borderTex in ipairs(id.borders) do
                    borderTex:SetShown(false)
                end
            end
            id.skinned = nil  -- Reset so frame gets re-skinned when CDM reuses it
        end
        return
    end

    -- Skip placeholder icons (empty CDM slot) -- [FIX: 복합 체크로 전투 중 재사용 프레임 오판 방지]
    -- [FIX] DynBridge 프레임(_ddIconKey)은 CDM 슬롯이 아니므로 placeholder 아님
    local isPlaceholder = true
    if icon._ddIconKey then
        isPlaceholder = false
    else
        pcall(function()
            if icon.layoutIndex ~= nil then isPlaceholder = false; return end
            if icon.cooldownInfo then isPlaceholder = false; return end
            if icon.cooldownID ~= nil then isPlaceholder = false; return end
        end)
    end
    if isPlaceholder and icon.IsActive and type(icon.IsActive) == "function" then
        local okA, activeVal = pcall(icon.IsActive, icon)
        if okA and not (issecretvalue and issecretvalue(activeVal)) and activeVal then isPlaceholder = false end
    end
    if isPlaceholder then
        local id = iconData[icon]
        if id and id.borders then
            for _, borderTex in ipairs(id.borders) do
                borderTex:SetShown(false)
            end
            id.skinned = nil
        end
        return
    end

    -- Calculate icon dimensions from iconSize and aspectRatio (crop slider)
    local iconSize = settings.iconSize or 40
    iconSize = iconSize + 0.01
    local aspectRatioValue = 1.0 -- Default to square

    -- Get aspect ratio from crop slider or convert from string format
    if settings.aspectRatioCrop then
        aspectRatioValue = settings.aspectRatioCrop
    elseif settings.aspectRatio then
        -- Convert "16:9" format to numeric ratio
        local aspectW, aspectH = settings.aspectRatio:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        if aspectW and aspectH then
            aspectRatioValue = tonumber(aspectW) / tonumber(aspectH)
        end
    end

    local iconWidth = iconSize
    local iconHeight = iconSize

    -- Calculate width/height based on aspect ratio value
    -- aspectRatioValue is width:height ratio (e.g., 1.78 for 16:9, 0.56 for 9:16)
    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            -- Wider - width is longest, so width = iconSize
            iconWidth = iconSize
            iconHeight = iconSize / aspectRatioValue
        elseif aspectRatioValue < 1.0 then
            -- Taller - height is longest, so height = iconSize
            iconWidth = iconSize * aspectRatioValue
            iconHeight = iconSize
        end
    end

    -- Padding is no longer applied; Blizzard masks are stripped instead
    local padding   = 0
    local zoom      = settings.zoom or 0
    local border    = icon.__CDM_Border

    -- This prevents stretching by cropping the texture to match the container aspect ratio
    iconTexture:ClearAllPoints()

    -- Fill the container completely
    iconTexture:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    iconTexture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)

    -- Remove Blizzard mask textures so the icon fills fully
    StripTextureMasks(iconTexture)

    -- Calculate texture coordinates based on aspect ratio to prevent stretching
    -- Use the same aspectRatioValue calculated above
    local left, right, top, bottom = 0, 1, 0, 1

    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            -- Wider than tall (e.g., 1.78 for 16:9) - crop top/bottom
            local cropAmount = 1.0 - (1.0 / aspectRatioValue)
            local offset = cropAmount / 2.0
            top = offset
            bottom = 1.0 - offset
        elseif aspectRatioValue < 1.0 then
            -- Taller than wide (e.g., 0.56 for 9:16) - crop left/right
            local cropAmount = 1.0 - aspectRatioValue
            local offset = cropAmount / 2.0
            left = offset
            right = 1.0 - offset
        end
    end

    -- Apply zoom on top of aspect ratio crop
    if zoom > 0 then
        local currentWidth = right - left
        local currentHeight = bottom - top
        local visibleSize = 1.0 - (zoom * 2)

        local zoomedWidth = currentWidth * visibleSize
        local zoomedHeight = currentHeight * visibleSize

        local centerX = (left + right) / 2.0
        local centerY = (top + bottom) / 2.0

        left = centerX - (zoomedWidth / 2.0)
        right = centerX + (zoomedWidth / 2.0)
        top = centerY - (zoomedHeight / 2.0)
        bottom = centerY + (zoomedHeight / 2.0)
    end

    -- Apply texture coordinates - this zooms/crops instead of stretching
    iconTexture:SetTexCoord(left, right, top, bottom)

    -- [REPARENT] 관리 아이콘도 동일하게 크기 적용 — snap-back 훅 우회 + 타겟 갱신
    if icon._ddIsManaged then
        icon._ddTargetWidth = iconWidth
        icon._ddTargetHeight = iconHeight
        icon._ddSettingSize = true
        icon:SetWidth(iconWidth)
        icon:SetHeight(iconHeight)
        icon:SetSize(iconWidth, iconHeight)
        icon._ddSettingSize = false
    else
        icon:SetWidth(iconWidth)
        icon:SetHeight(iconHeight)
        icon:SetSize(iconWidth, iconHeight)
    end

    -- Cooldown glow
    if icon.CooldownFlash then
        icon.CooldownFlash:ClearAllPoints()
        icon.CooldownFlash:SetAllPoints(iconTexture)
    end

    -- Cooldown swipe - use SetAllPoints to match texture exactly for pixel-perfect alignment
    if icon.Cooldown then
        icon.Cooldown:ClearAllPoints()
        icon.Cooldown:SetAllPoints(iconTexture)

        -- Store settings reference in weak table for hooks to access
        local cdd = GetCdData(icon.Cooldown)
        cdd.settings = settings
        cdd.parentIcon = icon

        -- Hook SetSwipeColor to detect aura swipe (yellow color) and customize it
        -- CDM uses yellow/gold color for aura duration display
        if not cdd.swipeColorHooked then
            cdd.swipeColorHooked = true
            hooksecurefunc(icon.Cooldown, "SetSwipeColor", function(self, r, g, b, a)
                local cd = cdData[self]
                if cd and cd.bypassColorHook then return end
                if not cd then return end
                local s = cd.settings
                local parentIcon = cd.parentIcon
                if not parentIcon then return end

                -- Detect yellow/gold aura swipe color
                -- CDM uses (1.0, 0.95, 0.57) for aura duration, (0, 0, 0) for regular cooldown
                local isAuraSwipe = r and g and b and r > 0.9 and g > 0.9 and b > 0.4
                GetIconData(parentIcon).isAuraSwipe = isAuraSwipe

                -- [12.0.1] Hide Duration Text logic (dynamically toggle text display based on swipe type)
                if s.hideDurationText then
                    if isAuraSwipe then
                        if self.SetHideCountdownNumbers then self:SetHideCountdownNumbers(true) end
                        self.noCooldownCount = true
                        for _, region in ipairs({ self:GetRegions() }) do
                            if region:GetObjectType() == "FontString" and not region.hookedHideText then
                                region:Hide()
                            end
                        end
                    else
                        if self.SetHideCountdownNumbers then self:SetHideCountdownNumbers(false) end
                        self.noCooldownCount = nil
                        for _, region in ipairs({ self:GetRegions() }) do
                            if region:GetObjectType() == "FontString" and not region.hookedHideText then
                                region:Show()
                            end
                        end
                    end
                end

                if isAuraSwipe and s then
                    -- Option 1: Replace aura swipe with glow
                    if s.auraGlow then
                        -- Hide swipe (make transparent)
                        cd.bypassColorHook = true
                        self:SetSwipeColor(0, 0, 0, 0)
                        cd.bypassColorHook = nil

                        -- Show glow
                        local SL = _G.DDingUI_StyleLib
                        if SL then
                                local glowType = s.auraGlowType or "Pixel Glow"
                                local glowColor = s.auraGlowColor or {0.95, 0.95, 0.32, 1}
                                local glowKey = "_DDingUIAuraGlow"
                                local glowTarget = parentIcon

                                local glowSuccess, err = pcall(function()
                                    if glowType == "Pixel Glow" then
                                        local pixelLines = s.auraGlowPixelLines or 8
                                        local pixelFrequency = s.auraGlowPixelFrequency or 0.25
                                        local pixelLength = s.auraGlowPixelLength  -- nil or 0 = auto
                                        if pixelLength == 0 then pixelLength = nil end
                                        local pixelThickness = s.auraGlowPixelThickness or 2
                                        SL.ShowPixelGlow(glowTarget, glowColor, pixelLines, pixelFrequency, pixelLength, pixelThickness, 0, 0, false, glowKey)
                                    elseif glowType == "Autocast Shine" then
                                        local particles = s.auraGlowAutocastParticles or 8
                                        local freq = s.auraGlowAutocastFrequency or 0.25
                                        local scale = s.auraGlowAutocastScale or 1.0
                                        SL.ShowAutocastGlow(glowTarget, glowColor, particles, freq, scale, 0, 0, glowKey)
                                    elseif glowType == "Action Button Glow" then
                                        local freq = s.auraGlowButtonFrequency or 0.25
                                        SL.ShowButtonGlow(glowTarget, glowColor, freq)
                                    elseif glowType == "Proc Glow" then
                                        local LCG = LibStub("LibCustomGlow-1.0", true)
                                        if LCG and LCG.ProcGlow_Start then
                                            LCG.ProcGlow_Start(glowTarget, {
                                                color = glowColor, startAnim = false,
                                                xOffset = 0, yOffset = 0, key = glowKey
                                            })
                                        end
                                    elseif glowType == "Blizzard Glow" then
                                        if ActionButton_ShowOverlayGlow then
                                            ActionButton_ShowOverlayGlow(glowTarget)
                                        end
                                    end
                                end)

                            if glowSuccess then
                                local pid = GetIconData(parentIcon)
                                pid.auraGlowActive = true
                                pid.auraGlowType = glowType
                            end
                        end

                    -- Option 2: Change aura swipe color
                    elseif s.auraSwipeColor then
                        local c = s.auraSwipeColor
                        cd.bypassColorHook = true
                        self:SetSwipeColor(c[1], c[2], c[3], c[4] or 0.8)
                        cd.bypassColorHook = nil
                    end
                else
                    -- Not aura swipe (regular cooldown) - stop any active glow
                    -- But check if aura is still active (auraInstanceID > 0) to survive CDM cooldown updates
                    local pid = iconData[parentIcon]
                    if pid and pid.auraGlowActive then
                        -- Check if the icon still has an active aura
                        local auraStillActive = false
                        pcall(function()
                            local auraID = parentIcon.auraInstanceID
                            if auraID ~= nil then
                                -- [FIX] secret value = 오라 활성 상태 (secret은 활성 오라에만 존재)
                                if issecretvalue and issecretvalue(auraID) then
                                    auraStillActive = true
                                elseif type(auraID) == "number" and auraID > 0 then
                                    auraStillActive = true
                                end
                            end
                        end)

                        if auraStillActive and s and s.auraGlow then
                            -- Aura is still active but CDM switched to cooldown display
                            -- Keep the glow and suppress the non-aura swipe color
                            cd.bypassColorHook = true
                            self:SetSwipeColor(0, 0, 0, 0)
                            cd.bypassColorHook = nil
                        else
                            -- Aura actually ended - stop the glow
                            local activeGlowType = pid.auraGlowType
                            pid.auraGlowActive = nil
                            pid.auraGlowType = nil
                            local SL2 = _G.DDingUI_StyleLib
                            if SL2 then
                                local glowKey = "_DDingUIAuraGlow"
                                local glowTarget = parentIcon
                                pcall(function()
                                    if activeGlowType == "Pixel Glow" then
                                        SL2.HidePixelGlow(glowTarget, glowKey)
                                    elseif activeGlowType == "Autocast Shine" then
                                        SL2.HideAutocastGlow(glowTarget, glowKey)
                                    elseif activeGlowType == "Action Button Glow" then
                                        SL2.HideButtonGlow(glowTarget)
                                    elseif activeGlowType == "Proc Glow" then
                                        local LCG = LibStub("LibCustomGlow-1.0", true)
                                        if LCG and LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(glowTarget, glowKey) end
                                    elseif activeGlowType == "Blizzard Glow" then
                                        if ActionButton_HideOverlayGlow then
                                            ActionButton_HideOverlayGlow(glowTarget)
                                        end
                                    end
                                end)
                            end
                        end
                    end
                end
            end)
        end

        -- Hook SetDrawSwipe to enforce disableSwipeAnimation setting
        -- BUT only for regular cooldowns, not for aura/buff swipes (yellow)
        if not cdd.drawSwipeHooked then
            cdd.drawSwipeHooked = true
            hooksecurefunc(icon.Cooldown, "SetDrawSwipe", function(self, draw)
                local cd = cdData[self]
                if cd and cd.bypassSwipeHook then return end
                if not cd then return end
                local s = cd.settings
                local parentIcon = cd.parentIcon
                if not s or not parentIcon then return end

                -- If auraGlow is active, keep swipe hidden
                local pid = iconData[parentIcon]
                if pid and pid.auraGlowActive and draw then
                    cd.bypassSwipeHook = true
                    self:SetDrawSwipe(false)
                    cd.bypassSwipeHook = nil
                    return
                end

                -- Only disable swipe if:
                -- 1. disableSwipeAnimation is enabled
                -- 2. This is NOT an aura swipe (yellow) - we want to keep aura swipes visible
                if s.disableSwipeAnimation and draw and not (pid and pid.isAuraSwipe) then
                    cd.bypassSwipeHook = true
                    self:SetDrawSwipe(false)
                    cd.bypassSwipeHook = nil
                end
            end)
        end

        -- Hook SetDrawEdge to enforce disableEdgeGlow setting
        if not cdd.drawEdgeHooked then
            cdd.drawEdgeHooked = true
            hooksecurefunc(icon.Cooldown, "SetDrawEdge", function(self, draw)
                local cd = cdData[self]
                if cd and cd.bypassEdgeHook then return end
                if not cd then return end
                local s = cd.settings

                if s.disableEdgeGlow and draw then
                    cd.bypassEdgeHook = true
                    self:SetDrawEdge(false)
                    cd.bypassEdgeHook = nil
                end
            end)
        end

        -- Hook SetDrawBling to enforce disableBlingAnimation setting
        if icon.Cooldown.SetDrawBling and not cdd.drawBlingHooked then
            cdd.drawBlingHooked = true
            hooksecurefunc(icon.Cooldown, "SetDrawBling", function(self, draw)
                local cd = cdData[self]
                if cd and cd.bypassBlingHook then return end
                if not cd then return end
                local s = cd.settings

                if s.disableBlingAnimation and draw then
                    cd.bypassBlingHook = true
                    self:SetDrawBling(false)
                    cd.bypassBlingHook = nil
                end
            end)
        end

        -- Apply initial settings
        if settings.disableSwipeAnimation then
            icon.Cooldown:SetDrawSwipe(false)
        end

        if settings.disableEdgeGlow then
            icon.Cooldown:SetDrawEdge(false)
        end

        if settings.disableBlingAnimation and icon.Cooldown.SetDrawBling then
            icon.Cooldown:SetDrawBling(false)
        end

        -- Always use square swipe texture for consistent appearance across all viewers
        if not settings.disableSwipeAnimation then
            icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        end

        -- Apply custom swipe color if set (for non-aura display)
        if settings.swipeColor and not settings.disableSwipeAnimation then
            local swipeColor = settings.swipeColor
            icon.Cooldown:SetSwipeColor(swipeColor[1], swipeColor[2], swipeColor[3], swipeColor[4])
        end

        -- Apply swipe reverse setting
        local swipeReverse = settings.swipeReverse
        if swipeReverse == nil then swipeReverse = false end
        icon.Cooldown:SetReverse(swipeReverse)

        -- Check current swipe color to detect if aura is active and apply auraSwipeColor immediately
        -- This handles the case where settings are changed while an aura swipe is already visible
        -- (auraGlow feature temporarily disabled)
        if settings.auraSwipeColor then
            -- Get current swipe color using pcall to avoid errors
            local ok, r, g, b, a2 = pcall(function()
                return icon.Cooldown:GetSwipeColor()
            end)

            if ok and r and g and b then
                -- Check if it's a yellow/gold aura swipe
                local isAuraSwipe = r > 0.9 and g > 0.9 and b > 0.4
                GetIconData(icon).isAuraSwipe = isAuraSwipe

                if isAuraSwipe then
                    -- Show swipe with custom color
                    icon.Cooldown:SetDrawSwipe(true)
                    local c = settings.auraSwipeColor
                    cdd.bypassColorHook = true
                    icon.Cooldown:SetSwipeColor(c[1], c[2], c[3], c[4] or 0.8)
                    cdd.bypassColorHook = nil
                end
            end
        end

        -- Position cooldown text (countdown timer) -- [12.0.1] cooldownTextAnchor/Offset 추가
        local cdAnchor = settings.durationTextAnchor or settings.cooldownTextAnchor

        -- Hide Duration Text initial state
        local pid = GetIconData(icon)
        if settings.hideDurationText and pid.isAuraSwipe then
            if icon.Cooldown.SetHideCountdownNumbers then
                icon.Cooldown:SetHideCountdownNumbers(true)
            end
            icon.Cooldown.noCooldownCount = true
        else
            if icon.Cooldown.SetHideCountdownNumbers then
                icon.Cooldown:SetHideCountdownNumbers(false)
            end
            icon.Cooldown.noCooldownCount = nil
        end

        if cdAnchor then
            if cdAnchor == "MIDDLE" then cdAnchor = "CENTER" end
            local cdOffsetX = settings.durationTextOffsetX or settings.cooldownTextOffsetX or 0
            local cdOffsetY = settings.durationTextOffsetY or settings.cooldownTextOffsetY or 0

            for _, region in ipairs({ icon.Cooldown:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    if settings.hideDurationText and pid.isAuraSwipe then
                        region:Hide()
                        -- Prevent region from showing
                        if not region.hookedHideText then
                            region.hookedHideText = true
                            hooksecurefunc(region, "Show", function(self)
                                local cd = self:GetParent()
                                if cd and cd.noCooldownCount then
                                    self:Hide()
                                end
                            end)
                        end
                    else
                        region:Show()
                        region:ClearAllPoints()
                        region:SetPoint(cdAnchor, icon.Cooldown, cdAnchor, cdOffsetX, cdOffsetY)
                        -- [12.0.1] Duration text font/size/color for BuffIconCooldownViewer
                        if settings.durationTextFont or settings.durationTextSize or settings.durationTextColor then
                            local dtSize = settings.durationTextSize or 14
                            local dtFont = DDingUI:GetFont(settings.durationTextFont)
                            region:SetFont(dtFont, dtSize, "OUTLINE")
                            local dtColor = settings.durationTextColor
                            if dtColor then
                                region:SetTextColor(dtColor[1], dtColor[2], dtColor[3], dtColor[4] or 1)
                            end
                        end
                    end
                    break
                end
            end
        end
    end

    -- Pandemic icon
    local picon = icon.PandemicIcon or icon.pandemicIcon or icon.Pandemic or icon.pandemic
    if not picon then
        for _, region in ipairs({ icon:GetChildren() }) do
            if region:GetName() and region:GetName():find("Pandemic") then
                picon = region
                break
            end
        end
    end

    if picon and picon.ClearAllPoints then
        picon:ClearAllPoints()
        picon:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        picon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    end

    -- Out of range highlight
    local oor = icon.OutOfRange or icon.outOfRange or icon.oor
    if oor and oor.ClearAllPoints then
        oor:ClearAllPoints()
        oor:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        oor:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    end

    -- Charge/stack text
    local fs = GetIconCountFont(icon)
    if fs and fs.ClearAllPoints then
        fs:ClearAllPoints()

        -- Keep charge/stack text above proc glows
        local parentFrame = fs.GetParent and fs:GetParent()
        if parentFrame and parentFrame.SetFrameLevel and icon.GetFrameLevel then
            local iconLevel = (icon.GetFrameLevel and icon:GetFrameLevel()) or 0
            local getParentLevel = parentFrame.GetFrameLevel
            local currentLevel = (getParentLevel and getParentLevel(parentFrame)) or 0
            parentFrame:SetFrameLevel(math.max(currentLevel, iconLevel + 10))
        end
        if fs.SetDrawLayer then
            fs:SetDrawLayer("OVERLAY", 7)
        end

        local point   = settings.chargeTextAnchor or "BOTTOMRIGHT"
        if point == "MIDDLE" then point = "CENTER" end

        local offsetX = settings.countTextOffsetX or 0
        local offsetY = settings.countTextOffsetY or 0

        fs:SetPoint(point, iconTexture, point, offsetX, offsetY)

        local desiredSize = settings.countTextSize
        if desiredSize and desiredSize > 0 then
            local font = DDingUI:GetFont(settings.countTextFont)
            fs:SetFont(font, desiredSize, "OUTLINE")
        end

        -- [12.0.1] Stack/charge text color
        local ctc = settings.countTextColor
        if ctc then
            fs:SetTextColor(ctc[1], ctc[2], ctc[3], ctc[4] or 1)
        end

    end

    -- Strip Blizzard overlay
    StripBlizzardOverlay(icon)

    -- Hide Blizzard debuff border (BuffIconCooldownViewer uses DebuffBorder as well)
    HideDebuffBorder(icon)

    -- Border - use texture-based borders like BetterCooldownManager (no SetBackdrop = no taint)
    if icon.IsForbidden and icon:IsForbidden() then
        GetIconData(icon).skinned = true
        return
    end

    local edgeSize = tonumber(settings.borderSize) or 1
    if DDingUI and DDingUI.ScaleBorder then
        edgeSize = DDingUI:ScaleBorder(edgeSize)
    elseif DDingUI and DDingUI.Scale then
        edgeSize = DDingUI:Scale(edgeSize)
        edgeSize = math.floor(edgeSize + 0.5)
    else
        edgeSize = math.floor(edgeSize + 0.5)
    end

    -- Create texture-based borders (like BetterCooldownManager) instead of BackdropTemplate
    local id = GetIconData(icon)
    id.borders = id.borders or {}
    local borders = id.borders

    if #borders == 0 then
        local function CreateBorderLine()
            return icon:CreateTexture(nil, "OVERLAY")
        end
        local topBorder = CreateBorderLine()
        topBorder:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 0, 0)
        topBorder:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 0, 0)

        local bottomBorder = CreateBorderLine()
        bottomBorder:SetPoint("BOTTOMLEFT", iconTexture, "BOTTOMLEFT", 0, 0)
        bottomBorder:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 0, 0)

        local leftBorder = CreateBorderLine()
        leftBorder:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 0, 0)
        leftBorder:SetPoint("BOTTOMLEFT", iconTexture, "BOTTOMLEFT", 0, 0)

        local rightBorder = CreateBorderLine()
        rightBorder:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 0, 0)
        rightBorder:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 0, 0)

        id.borders = { topBorder, bottomBorder, leftBorder, rightBorder }
        borders = id.borders
    end

    local topB, bottomB, leftB, rightB = unpack(borders)
    if topB and bottomB and leftB and rightB then
        local r, g, b, a = unpack(settings.borderColor or { 0, 0, 0, 1 })
        local shouldShow = edgeSize > 0

        topB:SetHeight(edgeSize)
        bottomB:SetHeight(edgeSize)
        leftB:SetWidth(edgeSize)
        rightB:SetWidth(edgeSize)

        for _, borderTex in ipairs(borders) do
            borderTex:SetColorTexture(r, g, b, a or 1)
            borderTex:SetShown(shouldShow)
        end
    end

    id.skinned = true
    id.skinPending = nil  -- Clear pending flag on successful skin
end

function IconViewers:SkinAllIconsInViewer(viewer)
    if not viewer or not viewer.GetName then return end

    local name     = viewer:GetName()
    local settings = DDingUI.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    local container = viewer.viewerFrame or viewer
    local children  = { container:GetChildren() }
    local isBuffViewer = (name == "BuffIconCooldownViewer") -- [FIX: placeholder black box]

    for _, icon in ipairs(children) do
        if IsCooldownIconFrame(icon) and (icon.icon or icon.Icon) then
            -- BuffIconCooldownViewer: skip placeholder icons -- [FIX: 복합 체크로 전투 중 재사용 프레임 오판 방지]
            local skipIcon = false
            if isBuffViewer then
                local isPlaceholder = true
                pcall(function()
                    if icon.layoutIndex ~= nil then isPlaceholder = false; return end
                    if icon.cooldownInfo then isPlaceholder = false; return end
                    if icon.cooldownID ~= nil then isPlaceholder = false; return end
                end)
                if isPlaceholder and icon.IsActive and type(icon.IsActive) == "function" then
                    local okA, activeVal = pcall(icon.IsActive, icon)
                    if okA and not (issecretvalue and issecretvalue(activeVal)) and activeVal then isPlaceholder = false end
                end
                if isPlaceholder then
                    local id = iconData[icon]
                    if id and id.borders then
                        for _, borderTex in ipairs(id.borders) do
                            borderTex:SetShown(false)
                        end
                        id.skinned = nil
                    end
                    skipIcon = true
                end
            end

            if not skipIcon then
                local ok, err = pcall(self.SkinIcon, self, icon, settings)
                if not ok then
                    GetIconData(icon).skinError = true
                    print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: |cffff4444SkinIcon error for", name, "icon:", err, "|r") -- [STYLE]
                end
            end
        end
    end
end

-- Expose to main addon for backwards compatibility
DDingUI.SkinIcon = function(self, icon, settings) return IconViewers:SkinIcon(icon, settings) end
DDingUI.SkinAllIconsInViewer = function(self, viewer) return IconViewers:SkinAllIconsInViewer(viewer) end

-- Note: ProcGlow SkinIcon hook is installed in ProcGlow:Initialize() via hooksecurefunc
