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

local AURA_GLOW_KEY = "_DDingUIAuraGlow"
local AURA_SWIPE_GRACE = 0.25

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

local function IsAuraSwipeColor(r, g, b)
    return r and g and b and r > 0.9 and g > 0.9 and b > 0.4
end

local function SafeBool(value)
    local ok, result = pcall(function()
        return value == true
    end)
    return ok and result or false
end

local function FrameFlagIsTrue(frame, key)
    if not frame or not key then return false end
    local ok, value = pcall(function()
        return frame[key]
    end)
    return ok and SafeBool(value) or false
end

local function FrameTimeIsFuture(frame, key)
    if not frame or not key then return false end
    local now = GetTime and GetTime() or 0
    local ok, active = pcall(function()
        local value = frame[key]
        return type(value) == "number" and value > now
    end)
    return ok and active or false
end

local function IsManagedDynamicIcon(frame)
    if not frame then return false end
    local ok, result = pcall(function()
        return frame._ddIsManaged == true or frame._ddIconKey ~= nil or frame._iconKey ~= nil
    end)
    return ok and result == true or false
end

local function IconHasAuraState(icon, cooldown)
    if not icon then return false end

    local ok, active = pcall(function()
        return icon.wasSetFromAura == true or icon.auraInstanceID ~= nil
    end)
    if ok and active then return true end

    if IsManagedDynamicIcon(icon) then
        if FrameFlagIsTrue(icon, "_auraWasActive")
            or FrameFlagIsTrue(icon, "_trinketProcWasActive")
            or FrameTimeIsFuture(icon, "_ddTimedAuraActiveUntil")
            or FrameTimeIsFuture(icon, "_ddAuraActiveUntil")
            or FrameTimeIsFuture(icon, "_ddProcActiveUntil")
        then
            return true
        end
    end

    if cooldown and cooldown.GetSwipeColor then
        local colorOk, r, g, b = pcall(function()
            return cooldown:GetSwipeColor()
        end)
        if colorOk and IsAuraSwipeColor(r, g, b) then
            return true
        end
    end

    return false
end

local function ColorComponent(color, index, key, fallback)
    if type(color) ~= "table" then return fallback end
    local value = color[index]
    if value == nil then value = color[key] end
    if value == nil then return fallback end
    return value
end

local function ColorsMatch(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return ColorComponent(a, 1, "r", 1) == ColorComponent(b, 1, "r", 1)
        and ColorComponent(a, 2, "g", 1) == ColorComponent(b, 2, "g", 1)
        and ColorComponent(a, 3, "b", 1) == ColorComponent(b, 3, "b", 1)
        and ColorComponent(a, 4, "a", 1) == ColorComponent(b, 4, "a", 1)
end

local function CopyColor(color)
    if type(color) ~= "table" then return nil end
    return {
        ColorComponent(color, 1, "r", 1),
        ColorComponent(color, 2, "g", 1),
        ColorComponent(color, 3, "b", 1),
        ColorComponent(color, 4, "a", 1),
    }
end

local function SetHideActiveStateGray(icon, active)
    if not icon then return end
    local pid = GetIconData(icon)
    local texture = icon.icon or icon.Icon

    if active then
        pid.hideActiveStateGray = true
    elseif not pid.hideActiveStateGray then
        return
    else
        pid.hideActiveStateGray = nil
    end

    if not texture then return end
    if texture.SetDesaturated then
        pcall(texture.SetDesaturated, texture, active and true or false)
    end
    if texture.SetDesaturation then
        pcall(texture.SetDesaturation, texture, active and 1 or 0)
    end
    if texture.SetVertexColor then
        if active then
            pcall(texture.SetVertexColor, texture, 0.58, 0.58, 0.58, 1)
        else
            pcall(texture.SetVertexColor, texture, 1, 1, 1, 1)
        end
    end
end

local function SyncAuraGlowHost(icon, pid)
    if not icon or not pid then return nil end

    local host = pid.auraGlowHost
    if not host then
        host = CreateFrame("Frame", nil, icon)
        host:SetClampedToScreen(false)
        pid.auraGlowHost = host
    end

    if host:GetParent() ~= icon then
        host:SetParent(icon)
    end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)

    if host.SetFrameStrata and icon.GetFrameStrata then
        local strata = icon:GetFrameStrata()
        if strata then host:SetFrameStrata(strata) end
    end
    if host.SetFrameLevel and icon.GetFrameLevel then
        host:SetFrameLevel((icon:GetFrameLevel() or 0) + 5)
    end

    return host
end

local function StopAuraGlowOnTarget(target, glowType)
    if not target or not glowType then return end

    local SL = _G.DDingUI_StyleLib
    pcall(function()
        if glowType == "Pixel Glow" then
            if SL and SL.HidePixelGlow then SL.HidePixelGlow(target, AURA_GLOW_KEY) end
        elseif glowType == "Autocast Shine" then
            if SL and SL.HideAutocastGlow then SL.HideAutocastGlow(target, AURA_GLOW_KEY) end
        elseif glowType == "Action Button Glow" then
            if SL and SL.HideButtonGlow then SL.HideButtonGlow(target) end
        elseif glowType == "Proc Glow" then
            local LCG = LibStub("LibCustomGlow-1.0", true)
            if LCG and LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(target, AURA_GLOW_KEY) end
        elseif glowType == "Blizzard Glow" then
            if ActionButton_HideOverlayGlow then ActionButton_HideOverlayGlow(target) end
        end
    end)
end

local function StopAuraGlow(parentIcon, pid, clearWanted)
    if not pid then return end

    local glowType = pid.auraGlowType
    local target = pid.auraGlowTarget or pid.auraGlowHost or parentIcon
    StopAuraGlowOnTarget(target, glowType)
    if target ~= parentIcon then
        StopAuraGlowOnTarget(parentIcon, glowType)
    end
    if pid.auraGlowHost then
        pid.auraGlowHost:Hide()
    end

    pid.auraGlowActive = nil
    pid.auraGlowType = nil
    pid.auraGlowColor = nil
    pid.auraGlowTarget = nil
    pid.auraGlowLastSeen = nil
    pid._glowRemoveTimer = nil
    if clearWanted ~= false then
        pid.auraGlowWanted = nil
        pid.auraGlowSettings = nil
    end
end

local ShowAuraGlow

local function EnsureAuraGlowHooks(icon, pid)
    if not icon or not pid or pid.auraGlowHooks then return end
    if not icon.HookScript then return end

    pid.auraGlowHooks = true
    icon:HookScript("OnShow", function(self)
        local data = iconData[self]
        if data and data.auraGlowWanted and data.auraGlowSettings and ShowAuraGlow then
            ShowAuraGlow(self, data, data.auraGlowSettings)
        end
    end)
    icon:HookScript("OnHide", function(self)
        local data = iconData[self]
        if data and data.auraGlowHost then
            data.auraGlowHost:Hide()
        end
    end)
end

ShowAuraGlow = function(parentIcon, pid, settings)
    if not parentIcon or not pid or not settings then return end

    local glowType = settings.auraGlowType or "Pixel Glow"
    local glowColor = settings.auraGlowColor or {0.95, 0.95, 0.32, 1}
    local glowTarget = parentIcon
    if glowType ~= "Blizzard Glow" then
        glowTarget = SyncAuraGlowHost(parentIcon, pid)
        if not glowTarget then return end
    end

    pid.auraGlowWanted = true
    pid.auraGlowSettings = settings
    pid.auraGlowLastSeen = GetTime and GetTime() or 0
    EnsureAuraGlowHooks(parentIcon, pid)

    if glowTarget.Show then
        glowTarget:Show()
    end

    if pid.auraGlowActive
        and pid.auraGlowType == glowType
        and pid.auraGlowTarget == glowTarget
        and ColorsMatch(pid.auraGlowColor, glowColor) then
        return
    end

    if pid.auraGlowActive then
        StopAuraGlow(parentIcon, pid, false)
    end

    local SL = _G.DDingUI_StyleLib
    local glowStarted = false
    local glowSuccess = pcall(function()
        if glowType == "Pixel Glow" then
            if not (SL and SL.ShowPixelGlow) then return end
            local pixelLines = settings.auraGlowPixelLines or 8
            local pixelFrequency = settings.auraGlowPixelFrequency or 0.25
            local pixelLength = settings.auraGlowPixelLength
            if pixelLength == 0 then pixelLength = nil end
            local pixelThickness = settings.auraGlowPixelThickness or 2
            SL.ShowPixelGlow(glowTarget, glowColor, pixelLines, pixelFrequency, pixelLength, pixelThickness, 0, 0, false, AURA_GLOW_KEY)
            glowStarted = true
        elseif glowType == "Autocast Shine" then
            if not (SL and SL.ShowAutocastGlow) then return end
            local particles = settings.auraGlowAutocastParticles or 8
            local freq = settings.auraGlowAutocastFrequency or 0.25
            local scale = settings.auraGlowAutocastScale or 1.0
            SL.ShowAutocastGlow(glowTarget, glowColor, particles, freq, scale, 0, 0, AURA_GLOW_KEY)
            glowStarted = true
        elseif glowType == "Action Button Glow" then
            if not (SL and SL.ShowButtonGlow) then return end
            local freq = settings.auraGlowButtonFrequency or 0.25
            SL.ShowButtonGlow(glowTarget, glowColor, freq)
            glowStarted = true
        elseif glowType == "Proc Glow" then
            local LCG = LibStub("LibCustomGlow-1.0", true)
            if LCG and LCG.ProcGlow_Start then
                LCG.ProcGlow_Start(glowTarget, {
                    color = glowColor,
                    startAnim = false,
                    xOffset = 0,
                    yOffset = 0,
                    key = AURA_GLOW_KEY,
                })
                glowStarted = true
            end
        elseif glowType == "Blizzard Glow" then
            if ActionButton_ShowOverlayGlow then
                ActionButton_ShowOverlayGlow(glowTarget)
                glowStarted = true
            end
        end
    end)

    if glowSuccess and glowStarted then
        pid.auraGlowActive = true
        pid.auraGlowType = glowType
        pid.auraGlowColor = CopyColor(glowColor)
        pid.auraGlowTarget = glowTarget
    end
end

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

-- [CDM 통합] Color 값 안전 추출 — viewer 마이그레이션된 값이 Color 객체/테이블/nil일 수 있음
local function SafeColor(c, fallbackR, fallbackG, fallbackB, fallbackA)
    if not c then return fallbackR or 0, fallbackG or 0, fallbackB or 0, fallbackA or 1 end
    -- {r, g, b, a} 테이블
    if type(c) == "table" and c[1] then return c[1], c[2], c[3], c[4] or 1 end
    -- CreateColor() 객체 (GetRGBA 메서드)
    if type(c) == "table" and c.GetRGBA then return c:GetRGBA() end
    -- {r=, g=, b=, a=} 테이블
    if type(c) == "table" and c.r then return c.r, c.g, c.b, c.a or 1 end
    return fallbackR or 0, fallbackG or 0, fallbackB or 0, fallbackA or 1
end

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
    -- [FIX] _ddIsManaged 프레임은 건너뜀: 버프 갱신 중 cooldownID 일시 nil 가능
    if not icon._ddIsManaged then
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
    end

    -- Skip placeholder icons (empty CDM slot) -- [FIX: 복합 체크로 전투 중 재사용 프레임 오판 방지]
    -- [FIX] DynBridge 프레임(_ddIconKey)은 CDM 슬롯이 아니므로 placeholder 아님
    -- [FIX] _ddIsManaged 프레임은 건너뜀: 전투 중 cooldownID secret value 가능
    local isPlaceholder = true
    if icon._ddIsManaged or icon._ddIconKey then
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

    -- [FIX] texcoord 캐시 저장 + CDM snap-back 훅 설치
    icon._ddTexCoord = { left, right, top, bottom }

    if not icon._ddTexSnapHooked then
        -- [PERF] TLog: 인라인 boolean 체크로 교체 (함수 호출 비용 제거)
        -- 디버그가 필요하면 /run DDingUI._texDebug=true
        local _texDebug = DDingUI._texDebug

        -- AddMaskTexture 훅
        if iconTexture.AddMaskTexture then
            hooksecurefunc(iconTexture, "AddMaskTexture", function(self, mask)
                if icon._ddIsManaged and mask then
                    if _texDebug then print("|cffff8888[TEX]|r AddMask", tostring(icon.cooldownID)) end
                    self:RemoveMaskTexture(mask)
                end
            end)
        end

        -- SetTexCoord 훅
        hooksecurefunc(iconTexture, "SetTexCoord", function(self)
            if icon._ddIsManaged and icon._ddTexCoord and not icon._ddSettingTexCoord then
                local tc = icon._ddTexCoord
                icon._ddSettingTexCoord = true
                self:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                icon._ddSettingTexCoord = false
            end
        end)

        -- Hide 훅
        hooksecurefunc(iconTexture, "Hide", function(self)
            if icon._ddIsManaged then
                self:Show()
            end
        end)

        -- SetShown 훅
        if iconTexture.SetShown then
            hooksecurefunc(iconTexture, "SetShown", function(self, shown)
                if icon._ddIsManaged and not shown then
                    self:Show()
                end
            end)
        end

        -- SetAlpha 훅 (texture level)
        hooksecurefunc(iconTexture, "SetAlpha", function(self, a)
            if icon._ddIsManaged and a and a < 0.01 then
                self:SetAlpha(1)
            end
        end)

        -- SetVertexColor 훅 (alpha channel로 숨길 수 있음)
        hooksecurefunc(iconTexture, "SetVertexColor", function(self, r, g, b, a)
            if icon._ddIsManaged and a and a < 0.01 then
                self:SetVertexColor(r or 1, g or 1, b or 1, 1)
            end
        end)

        -- ClearAllPoints 훅 (앵커 제거 → 렌더링 안 됨)
        hooksecurefunc(iconTexture, "ClearAllPoints", function(self)
            if icon._ddIsManaged and not icon._ddSettingSkin then
                self:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
                self:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            end
        end)

        -- SetTexture 훅 (nil로 설정 시 빈 텍스쳐)
        -- [PERF] SetTexture 훅 제거: 로깅 전용이었으므로 성능에만 악영향
        -- (디버그 필요 시 DDingUI._texDebug = true + 필요한 훅에서 개별 로깅)

        icon._ddTexSnapHooked = true
    end

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
                if not cd or cd.bypassColorHook then return end
                local s = cd.settings
                local parentIcon = cd.parentIcon
                if not parentIcon then return end

                -- [PERF] 변경 감지: 이전 isAuraSwipe 상태와 동일하면 전체 로직 스킵
                local isAuraSwipe = IsAuraSwipeColor(r, g, b)
                local pid = iconData[parentIcon]
                if not pid then pid = {}; iconData[parentIcon] = pid end
                local now = GetTime and GetTime() or 0
                if not isAuraSwipe and IconHasAuraState(parentIcon, self) then
                    isAuraSwipe = true
                end
                if isAuraSwipe then
                    pid.auraSwipeLastSeen = now
                elseif pid.auraSwipeLastSeen and (now - pid.auraSwipeLastSeen) <= AURA_SWIPE_GRACE then
                    isAuraSwipe = true
                end
                local prevAura = pid.isAuraSwipe
                pid.isAuraSwipe = isAuraSwipe
                if s and s.hideActiveState then
                    SetHideActiveStateGray(parentIcon, isAuraSwipe)
                else
                    SetHideActiveStateGray(parentIcon, false)
                end
                if isAuraSwipe and s and s.auraGlow then
                    pid._glowRemoveTimer = nil
                    pid.auraGlowLastSeen = now
                end
                -- [PERF] 상태 변경 없으면 heavy 로직 전부 스킵 (매 프레임 → 전환 시에만)
                if isAuraSwipe == prevAura and not (isAuraSwipe and s and s.auraGlow and not pid.auraGlowActive) then return end

                -- [12.0.1] Hide Duration Text logic (상태 전환 시에만 실행)
                if s.hideDurationText then
                    -- [PERF] FontString 캐시: GetRegions() 임시 테이블 생성 방지
                    if not cd._cachedFontStrings then
                        cd._cachedFontStrings = {}
                        for _, region in ipairs({ self:GetRegions() }) do
                            if region:GetObjectType() == "FontString" and not region.hookedHideText then
                                cd._cachedFontStrings[#cd._cachedFontStrings + 1] = region
                            end
                        end
                    end
                    if isAuraSwipe then
                        if self.SetHideCountdownNumbers then self:SetHideCountdownNumbers(true) end
                        self.noCooldownCount = true
                        for i = 1, #cd._cachedFontStrings do cd._cachedFontStrings[i]:Hide() end
                    else
                        if self.SetHideCountdownNumbers then self:SetHideCountdownNumbers(false) end
                        self.noCooldownCount = nil
                        for i = 1, #cd._cachedFontStrings do cd._cachedFontStrings[i]:Show() end
                    end
                end


                if isAuraSwipe and s then
                    -- Option 0: hideActiveState — convert aura swipe to normal cooldown swipe
                    -- (CDM CDM "hideActive" port: SetReverse(false) + normal swipe color)
                    -- The icon shows its regular CD timer instead of the active-state yellow overlay
                    if s.hideActiveState then
                        SetHideActiveStateGray(parentIcon, true)
                        -- Switch from reversed (aura) to forward (cooldown) direction
                        if self.SetReverse then self:SetReverse(false) end
                        -- Override yellow aura color → normal cooldown swipe color
                        cd.bypassColorHook = true
                        local swipeAlpha = 0.7
                        if s.swipeColor then
                            local sc = s.swipeColor
                            local sr, sg, sb, sa = sc[1] or 0, sc[2] or 0, sc[3] or 0, sc[4] or 0.8
                            self:SetSwipeColor(sr, sg, sb, sa)
                        else
                            self:SetSwipeColor(0, 0, 0, swipeAlpha)
                        end
                        cd.bypassColorHook = nil
                    -- Option 1: Replace aura swipe with glow
                    elseif s.auraGlow then
                        pid._glowRemoveTimer = nil
                        ShowAuraGlow(parentIcon, pid, s)
                        -- Hide swipe (make transparent)
                        cd.bypassColorHook = true
                        self:SetSwipeColor(0, 0, 0, 0)
                        cd.bypassColorHook = nil

                    -- Option 2: Change aura swipe color
                    elseif s.auraSwipeColor then
                        local c = s.auraSwipeColor
                        cd.bypassColorHook = true
                        self:SetSwipeColor(c[1], c[2], c[3], c[4] or 0.8)
                        cd.bypassColorHook = nil
                    end
                else
                    -- Not aura swipe (regular cooldown) - debounce glow removal
                    -- CDM rapidly alternates between aura/cooldown swipe colors during updates
                    -- Immediate removal causes glow flickering
                    local pid = iconData[parentIcon]
                    if pid and pid.auraGlowActive and s and s.auraGlow then
                        -- [FIX] 즉시 제거 금지 — 0.3초 디바운스로 CDM 순간 전환 무시
                        -- swipe를 투명하게 유지하여 글로우가 보이는 상태 유지
                        cd.bypassColorHook = true
                        self:SetSwipeColor(0, 0, 0, 0)
                        cd.bypassColorHook = nil

                        -- 디바운스 타이머 설정: 0.3초 후에도 aura swipe가 없으면 글로우 제거
                        pid._glowRemoveTimer = GetTime()
                        if not pid._glowRemoveScheduled then
                            local cooldownFrame = self
                            pid._glowRemoveScheduled = true
                            C_Timer.After(0.35, function()
                                pid._glowRemoveScheduled = nil
                                -- 0.35초 시점에서 마지막 non-aura 이벤트가 아직 유효한지 확인
                                if not pid._glowRemoveTimer then return end
                                if (GetTime() - pid._glowRemoveTimer) < 0.3 then return end
                                if pid.auraGlowLastSeen and (GetTime() - pid.auraGlowLastSeen) < 0.75 then
                                    pid._glowRemoveTimer = nil
                                    return
                                end
                                if IconHasAuraState(parentIcon, cooldownFrame) then
                                    pid._glowRemoveTimer = nil
                                    return
                                end
                                -- 0.3초 동안 aura swipe가 없었으면 = 오라 종료 → 글로우 제거
                                if not pid.auraGlowActive then return end
                                StopAuraGlow(parentIcon, pid)
                            end)
                        end
                    end
                end
            end)
        end

        -- Hook SetCooldown for hideActiveState:
        -- When CDM pushes aura duration data, replace it with actual spell cooldown
        -- using C_Spell.GetSpellCooldownDuration + SetCooldownFromDurationObject.
        -- This makes the icon show the real cooldown timer instead of aura remaining time.
        if not cdd.setCooldownHooked then
            cdd.setCooldownHooked = true
            hooksecurefunc(icon.Cooldown, "SetCooldown", function(self)
                local cd = cdData[self]
                if not cd then return end
                if cd.bypassCDHook then return end  -- prevent recursion
                local s = cd.settings
                local parentIcon = cd.parentIcon
                if not s or not parentIcon or not s.hideActiveState then return end
                -- Check if frame is in aura state
                local isActive = false
                pcall(function()
                    isActive = parentIcon.wasSetFromAura == true
                        or parentIcon.auraInstanceID ~= nil
                end)
                if not isActive then
                    SetHideActiveStateGray(parentIcon, false)
                    return
                end
                SetHideActiveStateGray(parentIcon, true)
                -- Get spellID from CDM frame
                local spellID = nil
                pcall(function()
                    local ci = parentIcon.cooldownInfo
                    if ci then spellID = ci.overrideSpellID or ci.spellID end
                end)
                if not spellID then return end
                -- Visual: normal cooldown appearance
                self:SetReverse(false)
                cd.bypassColorHook = true
                if s.swipeColor then
                    local sc = s.swipeColor
                    self:SetSwipeColor(sc[1] or 0, sc[2] or 0, sc[3] or 0, sc[4] or 0.8)
                else
                    self:SetSwipeColor(0, 0, 0, 0.7)
                end
                cd.bypassColorHook = nil
                -- Data: replace aura duration with actual spell cooldown
                cd.bypassCDHook = true
                cd.bypassColorHook = true
                pcall(function()
                    local durObj
                    local charges = C_Spell.GetSpellCharges(spellID)
                    if charges and charges.maxCharges and charges.maxCharges > 1 then
                        durObj = C_Spell.GetSpellChargeDuration(spellID)
                    else
                        durObj = C_Spell.GetSpellCooldownDuration(spellID)
                    end
                    if durObj then
                        self:SetCooldownFromDurationObject(durObj)
                    end
                end)
                cd.bypassCDHook = nil
                cd.bypassColorHook = nil
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
            local pid = GetIconData(icon)
            local currentColorOk, cr, cg, cb = pcall(function() return icon.Cooldown:GetSwipeColor() end)
            local isPhysicallyYellow = currentColorOk and cr and cg and cb and cr > 0.9 and cg > 0.9 and cb > 0.4
            local currentlyIsAura = isPhysicallyYellow or pid.isAuraSwipe or pid.auraGlowActive

            if isPhysicallyYellow then
                pid.isAuraSwipe = true
            end

            local swipeColor = settings.swipeColor
            local sr, sg, sb, sa = SafeColor(swipeColor, 0, 0, 0, 0.8)

            if currentlyIsAura then
                if settings.hideActiveState then
                    icon.Cooldown:SetSwipeColor(sr, sg, sb, sa)
                elseif settings.auraGlow then
                    -- If auraGlow is active, keep the swipe native bypass transparent
                    -- Do not let SkinIcon break the transparency set by the hook
                    local cdd = GetCdData(icon.Cooldown)
                    if cdd then cdd.bypassColorHook = true end
                    icon.Cooldown:SetSwipeColor(0, 0, 0, 0)
                    if cdd then cdd.bypassColorHook = nil end
                end
                -- If it's a native aura swipe and no override features are on, we leave it alone (skip SetSwipeColor)
            else
                -- Normal non-aura state
                icon.Cooldown:SetSwipeColor(sr, sg, sb, sa)
            end
        end

        -- Apply swipe reverse setting
        local swipeReverse = settings.swipeReverse
        if swipeReverse == nil then swipeReverse = false end
        icon.Cooldown:SetReverse(swipeReverse)

        -- [hideActiveState] Immediate application for already-active icons
        -- When user toggles the option, icons already showing aura state get overridden now
        if settings.hideActiveState then
            local isActive = false
            pcall(function()
                isActive = icon.wasSetFromAura == true or icon.auraInstanceID ~= nil
            end)
            if not isActive then
                -- Fallback: check current swipe color
                local ok2, cr, cg, cb = pcall(function() return icon.Cooldown:GetSwipeColor() end)
                if ok2 and cr and cg and cb and cr > 0.9 and cg > 0.9 and cb > 0.4 then
                    isActive = true
                end
            end
            if isActive then
                SetHideActiveStateGray(icon, true)
                -- Visual: normal cooldown appearance
                icon.Cooldown:SetReverse(false)
                cdd.bypassColorHook = true
                if settings.swipeColor then
                    local sc = settings.swipeColor
                    icon.Cooldown:SetSwipeColor(sc[1] or 0, sc[2] or 0, sc[3] or 0, sc[4] or 0.8)
                else
                    icon.Cooldown:SetSwipeColor(0, 0, 0, 0.7)
                end
                cdd.bypassColorHook = nil
                GetIconData(icon).isAuraSwipe = true
                -- Data: replace aura duration with actual spell cooldown
                pcall(function()
                    local ci = icon.cooldownInfo
                    local spellID = ci and (ci.overrideSpellID or ci.spellID)
                    if spellID then
                        cdd.bypassCDHook = true
                        cdd.bypassColorHook = true
                        local durObj
                        local charges = C_Spell.GetSpellCharges(spellID)
                        if charges and charges.maxCharges and charges.maxCharges > 1 then
                            durObj = C_Spell.GetSpellChargeDuration(spellID)
                        else
                            durObj = C_Spell.GetSpellCooldownDuration(spellID)
                        end
                        if durObj then
                            icon.Cooldown:SetCooldownFromDurationObject(durObj)
                        end
                        cdd.bypassCDHook = nil
                        cdd.bypassColorHook = nil
                    end
                end)
            else
                SetHideActiveStateGray(icon, false)
            end
        else
            SetHideActiveStateGray(icon, false)
        end

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
                                local dr, dg, db, da = SafeColor(dtColor, 1, 1, 1, 1)
                                region:SetTextColor(dr, dg, db, da)
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

        -- [12.0.1] Stack/charge text color — nil이면 흰색 기본값 적용 (CDM 노란색 폴백 방지)
        local ctc = settings.countTextColor or {1, 1, 1, 1}
        local cr, cg, cb, ca = SafeColor(ctc, 1, 1, 1, 1)
        fs:SetTextColor(cr, cg, cb, ca)

    end

    -- Strip Blizzard overlay
    StripBlizzardOverlay(icon)

    -- Hide Blizzard debuff border (BuffIconCooldownViewer uses DebuffBorder as well)
    HideDebuffBorder(icon)

    -- Border - use texture-based borders instead of SetBackdrop to avoid taint.
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

    -- Create texture-based borders instead of BackdropTemplate.
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
        local r, g, b, a = SafeColor(settings.borderColor, 0, 0, 0, 1)
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
