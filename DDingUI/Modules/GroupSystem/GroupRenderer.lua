-- [GROUP SYSTEM] GroupRenderer: CDM 프레임 SetParent 방식 렌더링
-- [REPARENT] ViewerLayout 동일 레이아웃 엔진 — 뷰어 설정값 100% 반영
-- FrameController.SetupFrameInContainer 통합, Blizzard CDM 프레임 직접 관리
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupRenderer = {}
DDingUI.GroupRenderer = GroupRenderer

local ResetPostCombatDynamicIconState

-- [DEBUG] FrameController DLog 접근
local function GRLog(...)
    local fc = DDingUI.FrameController
    if fc and fc._isDebugLog and fc._isDebugLog() then
        print("|cffcccc88[GR]|r", ...)
    end
end

-- [CDM PATTERN] 전투 종료 후 deferred 컨테이너 조작 재실행
-- CDM의 combatDirtyViewers 패턴: 전투 중 명명된 프레임 조작 skip → 전투 종료 후 전체 Reconcile
local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function()
    if ResetPostCombatDynamicIconState then
        ResetPostCombatDynamicIconState()
        C_Timer.After(0.05, ResetPostCombatDynamicIconState)
        C_Timer.After(0.25, ResetPostCombatDynamicIconState)
    end
    -- [FIX] pending Show/Hide 처리 (전투 중 named 프레임 Show/Hide 불가 → 전투 종료 시 실행)
    if GroupRenderer.groupFrames then
        for _, frame in pairs(GroupRenderer.groupFrames) do
            if frame._pendingCombatShow then
                frame._pendingCombatShow = nil
                frame:Show()
            elseif frame._pendingCombatHide then
                frame._pendingCombatHide = nil
                frame:Hide()
            end
        end
    end
    -- 전투 종료 → FrameController에 Reconcile 요청 (pending Show/Hide/SetSize 해결)
    local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
    if fc and fc.ScheduleReconcile then
        fc:ScheduleReconcile(0.1)
    elseif fc and fc.ForceReconcile then
        C_Timer.After(0.1, function()
            fc:ForceReconcile()
        end)
    end
    local gs = DDingUI.GroupSystem
    if gs and gs.enabled and gs.Refresh then
        C_Timer.After(0.05, function()
            if gs.enabled then
                pcall(gs.Refresh, gs)
            end
        end)
    end
end)

-- Locals
local CreateFrame = CreateFrame
local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_floor = math.floor
local math_abs = math.abs
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local table_concat = table.concat
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local C_Timer = C_Timer
local COMBAT_DYNAMIC_MISSING_GRACE = 1.5
local ALPHA_EPSILON = 0.01
local ICON_MOTION_DEFAULT_DURATION = 0.18
local ICON_MOTION_MIN_DELTA = 0.5

local iconMotionDriver = CreateFrame("Frame")
iconMotionDriver:Hide()
local activeIconMotions = {}
local activeIconMotionCount = 0

local function EaseOutCubic(t)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

local function ApplyIconPositionNow(icon, container, x, y)
    icon._ddSettingPosition = true
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", container, "CENTER", x, y)
    icon._ddSettingPosition = false
    icon._ddContainerRef = container
    icon._ddCurrentContainer = container
    icon._ddCurrentX = x
    icon._ddCurrentY = y
end

local function IconAnchorMatches(icon, container, x, y)
    if not icon or not icon.GetNumPoints or icon:GetNumPoints() ~= 1 then
        return false
    end

    local point, relativeTo, relativePoint, currentX, currentY = icon:GetPoint(1)
    if point ~= "CENTER" or relativeTo ~= container or relativePoint ~= "CENTER" then
        return false
    end
    if issecretvalue and (issecretvalue(currentX) or issecretvalue(currentY)) then
        return false
    end
    if type(currentX) ~= "number" or type(currentY) ~= "number" then
        return false
    end

    return math_abs(currentX - x) <= ICON_MOTION_MIN_DELTA
        and math_abs(currentY - y) <= ICON_MOTION_MIN_DELTA
end

local function StopIconMotion(icon)
    if not icon or not icon._ddPositionMotion then return end
    activeIconMotions[icon] = nil
    icon._ddPositionMotion = nil
    activeIconMotionCount = math_max(activeIconMotionCount - 1, 0)
    if activeIconMotionCount == 0 then
        iconMotionDriver:Hide()
    end
end

local function ResetIconLayoutState(icon, resetTarget)
    if not icon then return end
    StopIconMotion(icon)
    icon._ddLastGroupLayoutHash = nil
    icon._ddCurrentContainer = nil
    icon._ddCurrentX = nil
    icon._ddCurrentY = nil
    if resetTarget then
        icon._ddTargetPoint = nil
        icon._ddTargetRelPoint = nil
        icon._ddTargetX = nil
        icon._ddTargetY = nil
    end
end

iconMotionDriver:SetScript("OnUpdate", function(_, elapsed)
    if activeIconMotionCount <= 0 then
        iconMotionDriver:Hide()
        return
    end

    for icon, motion in pairs(activeIconMotions) do
        if not icon:IsShown() or icon._ddingHidden then
            activeIconMotions[icon] = nil
            icon._ddPositionMotion = nil
            icon._ddLastGroupLayoutHash = nil
            icon._ddCurrentContainer = nil
            icon._ddCurrentX = nil
            icon._ddCurrentY = nil
            activeIconMotionCount = math_max(activeIconMotionCount - 1, 0)
        else
            motion.elapsed = motion.elapsed + elapsed
            local t = motion.elapsed / motion.duration
            if t >= 1 then
                ApplyIconPositionNow(icon, motion.container, motion.toX, motion.toY)
                activeIconMotions[icon] = nil
                icon._ddPositionMotion = nil
                activeIconMotionCount = math_max(activeIconMotionCount - 1, 0)
            else
                local eased = EaseOutCubic(t)
                local x = motion.fromX + (motion.toX - motion.fromX) * eased
                local y = motion.fromY + (motion.toY - motion.fromY) * eased
                ApplyIconPositionNow(icon, motion.container, x, y)
            end
        end
    end

    if activeIconMotionCount <= 0 then
        iconMotionDriver:Hide()
    end
end)

-- FrameController 참조 (런타임에 resolve)
local FC -- FrameController lazy reference

local function GetFC()
    if not FC then
        FC = DDingUI.FrameController or DDingUI.CDMHookEngine
    end
    return FC
end

local function FindCooldownFontString(...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            return region
        end
    end
    return nil
end

local function GetCooldownTextFontString(cooldown)
    if not cooldown then return nil end
    local cached = cooldown._ddCooldownTextFS
    if cached and cached.GetObjectType and cached:GetObjectType() == "FontString" then
        return cached
    end
    cached = cooldown.Text or cooldown.text
    if cached and cached.GetObjectType and cached:GetObjectType() == "FontString" then
        cooldown._ddCooldownTextFS = cached
        return cached
    end
    local ok, found = pcall(function()
        return FindCooldownFontString(cooldown:GetRegions())
    end)
    cached = ok and found or nil
    cooldown._ddCooldownTextFS = cached
    return cached
end

local function GetIconCooldownFrame(icon)
    if not icon then return nil end
    return icon.cooldown or icon.Cooldown
end

local function GetIconCountText(icon)
    if not icon then return nil end
    if icon.count then return icon.count end
    local applications = icon.Applications
    return applications and applications.Applications or nil
end

local function ForEachCooldownTextFontString(cooldown, callback)
    if not (cooldown and callback) then return false end
    local seen = {}
    local found = false

    local function Visit(region)
        if region and not seen[region] and region.GetObjectType and region:GetObjectType() == "FontString" then
            seen[region] = true
            found = true
            callback(region)
        end
    end

    Visit(cooldown.Text)
    Visit(cooldown.text)

    local ok, regions = pcall(function()
        return { cooldown:GetRegions() }
    end)
    if ok and type(regions) == "table" then
        for _, region in ipairs(regions) do
            Visit(region)
        end
    end

    local cached = GetCooldownTextFontString(cooldown)
    Visit(cached)
    return found
end

-- 그룹 프레임 저장소
GroupRenderer.groupFrames = {} -- [groupName] = containerFrame
GroupRenderer._forceFullSetup = false -- [FIX] Refresh 시 강제 재설정 플래그

-- ============================================================
-- [REPARENT] 그룹 이름 → 소속 뷰어 매핑
-- ============================================================

function GroupRenderer:ResetIconLayoutState(icon, resetTarget)
    ResetIconLayoutState(icon, resetTarget)
end

function GroupRenderer:InvalidateLayoutCaches(resetTargets)
    for _, frame in pairs(self.groupFrames or {}) do
        if frame then
            frame._lastCombinedLayoutHash = nil
            frame._lastDynHash = nil
            for _, icon in pairs(frame._managedIcons or {}) do
                ResetIconLayoutState(icon, resetTargets == true)
            end
        end
    end
end

local GROUP_VIEWER_MAP = {
    ["Cooldowns"] = "EssentialCooldownViewer",
    ["Buffs"]     = "BuffIconCooldownViewer",
    ["Utility"]   = "UtilityCooldownViewer",
}

local function GroupUsesDurationText(groupName, groupSettings)
    return groupName == "Buffs" or (groupSettings and groupSettings.groupCategory == "buff")
end

local function ResolveGroupTextSetting(groupName, groupSettings, primaryKey, fallbackKey)
    if groupSettings then
        if primaryKey and groupSettings[primaryKey] ~= nil then
            return groupSettings[primaryKey]
        end
        if fallbackKey and groupSettings[fallbackKey] ~= nil then
            return groupSettings[fallbackKey]
        end
    end

    local viewerName = GROUP_VIEWER_MAP[groupName]
    local profile = DDingUI.db and DDingUI.db.profile
    local viewerSettings = viewerName and profile and profile.viewers and profile.viewers[viewerName]
    if viewerSettings then
        if primaryKey and viewerSettings[primaryKey] ~= nil then
            return viewerSettings[primaryKey]
        end
        if fallbackKey and viewerSettings[fallbackKey] ~= nil then
            return viewerSettings[fallbackKey]
        end
    end

    return nil
end

local function ResolveCooldownTextStyle(groupName, groupSettings)
    if not groupSettings then
        return ResolveGroupTextSetting(groupName, nil, "cooldownTextAnchor"),
            ResolveGroupTextSetting(groupName, nil, "cooldownTextOffsetX"),
            ResolveGroupTextSetting(groupName, nil, "cooldownTextOffsetY"),
            ResolveGroupTextSetting(groupName, nil, "cooldownFontSize"),
            ResolveGroupTextSetting(groupName, nil, "cooldownFont"),
            ResolveGroupTextSetting(groupName, nil, "cooldownTextColor")
    end

    if GroupUsesDurationText(groupName, groupSettings) then
        return ResolveGroupTextSetting(groupName, groupSettings, "durationTextAnchor", "cooldownTextAnchor"),
            ResolveGroupTextSetting(groupName, groupSettings, "durationTextOffsetX", "cooldownTextOffsetX"),
            ResolveGroupTextSetting(groupName, groupSettings, "durationTextOffsetY", "cooldownTextOffsetY"),
            ResolveGroupTextSetting(groupName, groupSettings, "durationTextSize", "cooldownFontSize"),
            ResolveGroupTextSetting(groupName, groupSettings, "durationTextFont", "cooldownFont"),
            ResolveGroupTextSetting(groupName, groupSettings, "durationTextColor", "cooldownTextColor")
    end

    return ResolveGroupTextSetting(groupName, groupSettings, "cooldownTextAnchor"),
        ResolveGroupTextSetting(groupName, groupSettings, "cooldownTextOffsetX"),
        ResolveGroupTextSetting(groupName, groupSettings, "cooldownTextOffsetY"),
        ResolveGroupTextSetting(groupName, groupSettings, "cooldownFontSize"),
        ResolveGroupTextSetting(groupName, groupSettings, "cooldownFont"),
        ResolveGroupTextSetting(groupName, groupSettings, "cooldownTextColor")
end

local function ResolveRGBA(color)
    if type(color) ~= "table" then return 1, 1, 1, 1 end
    if color.GetRGBA then
        local ok, r, g, b, a = pcall(color.GetRGBA, color)
        if ok then return r or 1, g or 1, b or 1, a or 1 end
    end
    if color[1] then
        return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    end
    if color.r then
        return color.r or 1, color.g or 1, color.b or 1, color.a or 1
    end
    return 1, 1, 1, 1
end

local function ApplyDynamicIconTextOptions(icon, groupName, groupSettings)
    if not icon or not groupSettings then return end
    local iconTexture = icon.icon or icon.Icon
    local textAnchorFrame = iconTexture or icon

    local function ScheduleTextRetry()
        if icon._ddDynamicTextRetryPending then return end
        local retryCount = tonumber(icon._ddDynamicTextRetryCount) or 0
        if retryCount >= 3 then return end
        icon._ddDynamicTextRetryCount = retryCount + 1
        icon._ddDynamicTextRetryPending = true
        C_Timer.After(0, function()
            icon._ddDynamicTextRetryPending = nil
            if icon._ddIsManaged and not icon._ddingHidden then
                local container = icon._ddContainerRef
                ApplyDynamicIconTextOptions(
                    icon,
                    icon._ddGroupName or groupName or (container and container._groupName),
                    icon._groupSettings or groupSettings or (container and container._groupSettings)
                )
            end
        end)
    end

    local countText = GetIconCountText(icon)
    if countText then
        local countAnchor = ResolveGroupTextSetting(groupName, groupSettings, "chargeTextAnchor") or "BOTTOMRIGHT"
        if countAnchor == "MIDDLE" then countAnchor = "CENTER" end
        local cox = tonumber(ResolveGroupTextSetting(groupName, groupSettings, "countTextOffsetX")) or 0
        local coy = tonumber(ResolveGroupTextSetting(groupName, groupSettings, "countTextOffsetY")) or 0
        countText:ClearAllPoints()
        countText:SetPoint(countAnchor, textAnchorFrame, countAnchor, cox, coy)

        local cSize = tonumber(ResolveGroupTextSetting(groupName, groupSettings, "countTextSize"))
        if cSize and cSize > 0 then
            local cFont = DDingUI:GetFont(ResolveGroupTextSetting(groupName, groupSettings, "countTextFont"))
            countText:SetFont(cFont, cSize, "OUTLINE")
        end

        local countColor = ResolveGroupTextSetting(groupName, groupSettings, "countTextColor")
        if type(countColor) == "table" then
            countText:SetTextColor(ResolveRGBA(countColor))
        end
    end

    local cooldown = GetIconCooldownFrame(icon)
    if cooldown then
        local cdAnchor, oxRaw, oyRaw, textSizeRaw, textFont, textColor = ResolveCooldownTextStyle(groupName, groupSettings)
        local ox = tonumber(oxRaw) or 0
        local oy = tonumber(oyRaw) or 0
        if cdAnchor == "MIDDLE" then cdAnchor = "CENTER" end

        local textSize = tonumber(textSizeRaw)
        if textSize and textSize > 0 and cooldown.SetCountdownFont then
            local font = DDingUI:GetFont(textFont)
            if font then
                pcall(cooldown.SetCountdownFont, cooldown, font, textSize, "OUTLINE")
            end
        end

        if groupSettings.hideDurationText then
            if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
            cooldown.noCooldownCount = true
        else
            if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
            cooldown.noCooldownCount = nil
        end

        local foundCooldownText = ForEachCooldownTextFontString(cooldown, function(cdText)
            icon._ddDynamicTextRetryCount = nil
            if groupSettings.hideDurationText then
                cdText:Hide()
                if not cdText.hookedHideText then
                    cdText.hookedHideText = true
                    hooksecurefunc(cdText, "Show", function(self)
                        local cd = self:GetParent()
                        if cd and cd.noCooldownCount then self:Hide() end
                    end)
                end
            else
                cdText:Show()
                if cdAnchor then
                    cdText:ClearAllPoints()
                    cdText:SetPoint(cdAnchor, textAnchorFrame, cdAnchor, ox, oy)
                end
                if textSize and textSize > 0 then
                    local font = DDingUI:GetFont(textFont)
                    cdText:SetFont(font, textSize, "OUTLINE")
                end
                if type(textColor) == "table" then
                    cdText:SetTextColor(ResolveRGBA(textColor))
                end
            end
        end)
        if not foundCooldownText then
            ScheduleTextRetry()
        end
    end
end

function GroupRenderer:ApplyDynamicIconTextOptions(icon, groupName, groupSettings)
    return ApplyDynamicIconTextOptions(icon, groupName, groupSettings)
end

local function GetObjectAlpha(obj)
    if not (obj and obj.GetAlpha) then return nil end
    local ok, alpha = pcall(obj.GetAlpha, obj)
    if ok and type(alpha) == "number" then return alpha end
    return nil
end

local function SetAlphaIfNeeded(obj, alpha, cacheField)
    if not (obj and obj.SetAlpha) then return end
    alpha = tonumber(alpha) or 1
    local fh = DDingUI.FlightHide
    if alpha > 0 and fh and (fh.isActive or fh._hiding) then
        return
    end
    local actual = GetObjectAlpha(obj)
    local cached = cacheField and obj[cacheField]
    if cached ~= alpha or not actual or math_abs(actual - alpha) > ALPHA_EPSILON then
        if cacheField then
            obj[cacheField] = alpha
        end
        obj:SetAlpha(alpha)
    end
end

local function RestoreIconTextureOpacity(icon)
    if not icon or icon._ddingHidden then return end
    local texture = icon.icon or icon.Icon
    if not texture then return end

    if texture.Show then
        pcall(texture.Show, texture)
    end
    local fh = DDingUI.FlightHide
    if fh and (fh.isActive or fh._hiding) then
        return
    end
    SetAlphaIfNeeded(texture, 1, "_ddLastTextureAlpha")

    if texture.GetVertexColor and texture.SetVertexColor then
        local ok, r, g, b, a = pcall(texture.GetVertexColor, texture)
        if ok and type(a) == "number" and a < (1 - ALPHA_EPSILON) then
            pcall(texture.SetVertexColor, texture, r or 1, g or 1, b or 1, 1)
        end
    end
end

local function SetDynamicIconInactiveGray(icon, inactiveGray)
    if not icon then return end
    local wasForcedGray = icon._ddForcedInactiveGray == true
    icon._ddInactiveGray = inactiveGray and true or nil

    local texture = icon.icon or icon.Icon
    if texture then
        if texture.Show then pcall(texture.Show, texture) end
        if inactiveGray then
            icon._ddForcedInactiveGray = true
            if texture.SetDesaturated then pcall(texture.SetDesaturated, texture, true) end
            if texture.SetDesaturation then pcall(texture.SetDesaturation, texture, 1) end
            SetAlphaIfNeeded(texture, 0.48, "_ddLastTextureAlpha")
        elseif wasForcedGray then
            icon._ddForcedInactiveGray = nil
            if texture.SetDesaturated then pcall(texture.SetDesaturated, texture, false) end
            if texture.SetDesaturation then pcall(texture.SetDesaturation, texture, 0) end
            SetAlphaIfNeeded(texture, 1, "_ddLastTextureAlpha")
        else
            icon._ddForcedInactiveGray = nil
        end
    end

    local function ClearCooldown(cooldown)
        if not cooldown then return end
        if cooldown.Clear then pcall(cooldown.Clear, cooldown) end
        if cooldown.SetHideCountdownNumbers then pcall(cooldown.SetHideCountdownNumbers, cooldown, true) end
        cooldown.noCooldownCount = true
        if cooldown.Hide then pcall(cooldown.Hide, cooldown) end
    end

    local function RestoreCooldown(cooldown)
        if not cooldown then return end
        cooldown.noCooldownCount = nil
        if cooldown.Show then pcall(cooldown.Show, cooldown) end
    end

    if not inactiveGray then
        if wasForcedGray then
            RestoreCooldown(icon.cooldown)
            if icon.Cooldown and icon.Cooldown ~= icon.cooldown then
                RestoreCooldown(icon.Cooldown)
            end
            local countText = GetIconCountText(icon)
            if countText and countText.Show then pcall(countText.Show, countText) end
        end
        return
    end

    ClearCooldown(icon.cooldown)
    if icon.Cooldown and icon.Cooldown ~= icon.cooldown then
        ClearCooldown(icon.Cooldown)
    end
    ClearCooldown(icon.cooldownProbe)
    ClearCooldown(icon.cooldownChargeProbe)

    local countText = GetIconCountText(icon)
    if countText then
        if countText.SetText then pcall(countText.SetText, countText, "") end
        if countText.Hide then pcall(countText.Hide, countText) end
    end

    local SL = _G.DDingUI_StyleLib
    if SL then
        if SL.HidePixelGlow then
            pcall(SL.HidePixelGlow, icon, "_DDingUIAssistGlow")
            pcall(SL.HidePixelGlow, icon, "_DDingUICustomGlow")
        end
        if SL.HideAutocastGlow then
            pcall(SL.HideAutocastGlow, icon, "_DDingUIAssistGlow")
            pcall(SL.HideAutocastGlow, icon, "_DDingUICustomGlow")
        end
        if SL.HideButtonGlow then
            pcall(SL.HideButtonGlow, icon)
        end
    end

    local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then
        pcall(LCG.ProcGlow_Stop, icon, "_DDingUIAssistGlow")
        pcall(LCG.ProcGlow_Stop, icon, "_DDingUICustomGlow")
    end
end

local function HideDynamicIconBorderLayers(icon)
    if not icon then return end
    if icon.border then
        if icon.border.SetAlpha then pcall(icon.border.SetAlpha, icon.border, 0) end
        if icon.border.Hide then pcall(icon.border.Hide, icon.border) end
    end
    local borders = icon._ddBorders
    if type(borders) == "table" then
        for _, borderTex in ipairs(borders) do
            if borderTex then
                if borderTex.SetAlpha then pcall(borderTex.SetAlpha, borderTex, 0) end
                if borderTex.SetShown then pcall(borderTex.SetShown, borderTex, false) end
                if borderTex.Hide then pcall(borderTex.Hide, borderTex) end
            end
        end
    end
end

local function TagDynamicIconForGroup(icon, groupName, groupSettings)
    if not icon then return end
    icon._groupSettings = groupSettings
    icon._ddGroupName = groupName
    icon._ddSourceViewer = GROUP_VIEWER_MAP[groupName]
    if icon.cooldown then
        icon.cooldown._ddGroupName = groupName
        icon.cooldown._ddSourceViewer = icon._ddSourceViewer
    end
end

local function SafeTokenValue(value)
    if value == nil then return nil end
    local ok, result = pcall(function()
        if issecretvalue and issecretvalue(value) then return nil end
        return tostring(value)
    end)
    if ok and result and result ~= "" then return result end
    return nil
end

local function BuildCDMOrderToken(entry)
    if not entry then return nil end

    local spellName = entry.spellName
    if not spellName and entry.cooldownID then
        local fc = GetFC()
        if fc and fc.GetSpellNameForID then
            spellName = fc:GetSpellNameForID(entry.cooldownID)
        end
    end

    if spellName and spellName ~= "" then
        return "cdm:" .. spellName
    end

    local fallbackID = SafeTokenValue(entry.cooldownID)
    if fallbackID then
        return "cdm_id:" .. fallbackID
    end
    return nil
end

local function BuildDynamicOrderToken(iconKey)
    if not iconKey then return nil end
    return "dyn:" .. tostring(iconKey)
end

function GroupRenderer:IsHiddenSourceBuffIcon(icon)
    return icon
        and icon._ddSourceViewer == "BuffIconCooldownViewer"
        and icon._ddCDMViewerShown == false
end

function GroupRenderer:CanShowManagedIcon(icon)
    return icon and not icon._ddingHidden and not self:IsHiddenSourceBuffIcon(icon)
end

function GroupRenderer:HideHiddenSourceBuffIcon(icon)
    if not self:IsHiddenSourceBuffIcon(icon) then return end
    if icon.SetAlpha then
        pcall(icon.SetAlpha, icon, 0)
        icon._ddLastGroupAlpha = 0
    end
    if icon.Hide then
        pcall(icon.Hide, icon)
    end
end

local function SetManagedIconLayoutVisible(icon, visible)
    if icon then
        icon._ddLayoutVisible = visible and true or false
    end
end

local function ShouldLayoutManagedIcon(icon)
    if not icon or icon._ddingHidden or icon._ddSuppressed then return false end
    if icon._ddLayoutVisible ~= nil then
        return icon._ddLayoutVisible == true
    end
    if icon._ddIconKey then
        if icon._ddManagedAuraExpired then return false end
        if icon._ddCombatKeepAlive and icon._ddCombatVisible == false then return false end
    end
    if GroupRenderer:IsHiddenSourceBuffIcon(icon) then return false end
    return icon:IsShown()
end

local function BuildCDMPlacement(entry)
    if not entry or not entry.icon then return nil end
    entry.isCDM = true
    entry.isDynamic = nil
    entry.inactiveGray = false
    entry.icon._ddInactiveGray = nil
    entry.sourceVisible = not GroupRenderer:IsHiddenSourceBuffIcon(entry.icon)
    entry._ddOrderToken = BuildCDMOrderToken(entry)
    return entry
end

local function BuildDynamicPlacement(entry)
    if not entry or not entry.frame then return nil end
    return {
        isDynamic = true,
        icon = entry.frame,
        iconKey = entry.iconKey,
        entry = entry,
        cooldownID = entry.iconKey,
        active = entry.active ~= false,
        combatKeepAlive = entry.combatKeepAlive and true or false,
        combatVisible = entry.combatVisible ~= false,
        inactiveGray = entry.inactiveGray and true or false,
        _ddOrderToken = BuildDynamicOrderToken(entry.iconKey),
    }
end

local function GetDynamicIconData(iconKey)
    local ci = DDingUI.CustomIcons
    local db = ci and ci.GetDynamicDB and ci.GetDynamicDB()
    return db and db.iconData and db.iconData[iconKey]
end

ResetPostCombatDynamicIconState = function()
    local frames = GroupRenderer.groupFrames
    if not frames then return end

    local bridge = DDingUI.DynamicIconBridge
    local fh = DDingUI.FlightHide

    local function IsDynamicAuraActive(icon, iconData)
        if not (iconData and iconData.type == "aura") then return false end
        local ci = DDingUI.CustomIcons
        if not ci then return false end

        if ci.ResolvePlayerAuraForIcon then
            local okAura, auraData = pcall(ci.ResolvePlayerAuraForIcon, ci, icon, iconData)
            if okAura then return auraData ~= nil end
        end

        if ci.IsCustomTimedAuraIcon then
            local okTimed, isTimed = pcall(ci.IsCustomTimedAuraIcon, ci, iconData)
            if okTimed and isTimed then
                if not ci.GetActiveCustomTimedAuraForIcon then return false end
                local okActive, auraState = pcall(ci.GetActiveCustomTimedAuraForIcon, ci, iconData)
                return okActive and auraState ~= nil
            end
        end

        return false
    end

    local function RestoreDynamicIconAfterCombat(icon, frame, groupAlpha, visualBlocked)
        if not icon then return end
        local now = GetTime and GetTime() or 0
        icon._ddManagedAuraExpired = nil
        icon._ddCombatKeepAlive = nil
        icon._ddCombatVisible = nil
        icon._ddCombatMissingSince = nil
        icon._ddLastDynamicActiveAt = now
        icon._ddLastAuraActiveAt = now
        icon._wasVisibleInGroup = true
        icon._auraWasActive = true
        if visualBlocked then return end
        if icon.Show and (not frame or frame:IsShown()) then pcall(icon.Show, icon) end
        SetAlphaIfNeeded(icon, groupAlpha or 1, "_ddLastGroupAlpha")
        SetDynamicIconInactiveGray(icon, false)
        RestoreIconTextureOpacity(icon)
    end

    local function HideInactiveDynamicAura(icon)
        if not icon then return end
        icon._ddCombatKeepAlive = nil
        icon._ddCombatVisible = false
        icon._ddManagedAuraExpired = true
        icon._wasVisibleInGroup = nil
        icon._auraWasActive = false
        icon._ddTimedAuraActiveUntil = nil
        icon._ddAuraActiveUntil = nil
        icon._ddLastDynamicActiveAt = nil
        icon._ddLastAuraActiveAt = nil
        if icon.cooldown then
            if icon.cooldown.Clear then pcall(icon.cooldown.Clear, icon.cooldown) end
            if icon.cooldown.Hide then pcall(icon.cooldown.Hide, icon.cooldown) end
        end
        if icon.Cooldown and icon.Cooldown ~= icon.cooldown then
            if icon.Cooldown.Clear then pcall(icon.Cooldown.Clear, icon.Cooldown) end
            if icon.Cooldown.Hide then pcall(icon.Cooldown.Hide, icon.Cooldown) end
        end
        if icon.count and icon.count.Hide then pcall(icon.count.Hide, icon.count) end
        HideDynamicIconBorderLayers(icon)
        SetAlphaIfNeeded(icon, 0, "_ddLastGroupAlpha")
        if icon.Hide then pcall(icon.Hide, icon) end
    end

    for _, frame in pairs(frames) do
        local groupAlpha = frame and frame._groupSettings and frame._groupSettings.groupAlpha or 1
        if frame and frame._ddDeferredReleaseIcons then
            for iconKey, icon in pairs(frame._ddDeferredReleaseIcons) do
                if icon then
                    local iconData = GetDynamicIconData(iconKey)
                    if iconData and iconData.type == "aura" then
                        if IsDynamicAuraActive(icon, iconData) then
                            RestoreDynamicIconAfterCombat(icon, frame, groupAlpha, fh and fh.isActive)
                        else
                            HideInactiveDynamicAura(icon)
                        end
                    elseif bridge and bridge.ReleaseFrame then
                        bridge:ReleaseFrame(icon, iconKey)
                    else
                        icon._ddCombatKeepAlive = nil
                        icon._ddCombatVisible = nil
                        icon._ddCombatMissingSince = nil
                    end
                end
                frame._ddDeferredReleaseIcons[iconKey] = nil
            end
        end

        if frame and frame._managedIcons then
            for _, icon in pairs(frame._managedIcons) do
                if icon and icon._ddIconKey then
                    icon._ddCombatKeepAlive = nil
                    icon._ddCombatVisible = nil
                    icon._ddCombatMissingSince = nil

                    local iconData = GetDynamicIconData(icon._ddIconKey)
                    if iconData and iconData.type == "aura" and icon._ddManagedAuraExpired then
                        if IsDynamicAuraActive(icon, iconData) then
                            RestoreDynamicIconAfterCombat(icon, frame, groupAlpha, fh and fh.isActive)
                        else
                            HideInactiveDynamicAura(icon)
                        end
                    elseif not (fh and fh.isActive) then
                        if icon.Show and frame:IsShown() then pcall(icon.Show, icon) end
                        SetAlphaIfNeeded(icon, groupAlpha, "_ddLastGroupAlpha")
                        RestoreIconTextureOpacity(icon)
                    end
                end
            end
        end
    end
end

local function SafeNumber(value)
    if value == nil then return nil end
    if issecretvalue then
        local okSecret, secret = pcall(issecretvalue, value)
        if okSecret and secret then return nil end
    end
    local valueType = type(value)
    if valueType == "number" then
        local okText, text = pcall(tostring, value)
        if not okText then return nil end
        return tonumber(text)
    end
    if valueType == "string" then
        local okNumber, numberValue = pcall(tonumber, value)
        if okNumber then return numberValue end
    end
    return nil
end

local function SafeTableField(tbl, key)
    if not tbl or not key then return nil end
    local ok, value = pcall(function()
        return tbl[key]
    end)
    if ok then return value end
    return nil
end

local BLOODLUST_GROUP_IDS = {
    [2825] = true, [32182] = true, [80353] = true, [90355] = true,
    [160452] = true, [264667] = true, [390386] = true,
    [146555] = true, [178207] = true, [230935] = true, [256740] = true,
    [292686] = true, [309658] = true, [381301] = true, [444257] = true,
}

local ITEM_EFFECT_IDS = {
    [5512] = 6262,
    [224464] = 452930,
    [241304] = 1234768,
    [241305] = 1234768,
    [241308] = 1236616,
    [241309] = 1236616,
    [245898] = 1236616,
    [245897] = 1236616,
    [241288] = 1236994,
    [241289] = 1236994,
    [245902] = 1236994,
    [245903] = 1236994,
    [241300] = 1234770,
    [241301] = 1234770,
    [245917] = 1234770,
    [245916] = 1234770,
    [211878] = 431416,
    [211879] = 431416,
    [211880] = 431416,
}

local function AddNormalizedID(set, value)
    local id = SafeNumber(value)
    if not id or id <= 0 then return end

    set[id] = true
    local effectID = ITEM_EFFECT_IDS[id]
    if effectID then
        set[effectID] = true
    end
    if BLOODLUST_GROUP_IDS[id] then
        set[2825] = true
        for aliasID in pairs(BLOODLUST_GROUP_IDS) do
            set[aliasID] = true
        end
    end
end

local function AddIDsFromValue(set, value)
    local valueType = type(value)
    if valueType == "table" then
        pcall(function()
            for _, id in pairs(value) do
                AddIDsFromValue(set, id)
            end
        end)
    elseif valueType == "string" then
        local matched = false
        for id in string.gmatch(value, "(%d+)") do
            matched = true
            AddNormalizedID(set, id)
        end
        if not matched then
            AddNormalizedID(set, value)
        end
    else
        AddNormalizedID(set, value)
    end
end

local function GetTableField(tbl, key)
    if type(tbl) ~= "table" then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    if ok then return value end
    return nil
end

local function AddCooldownInfoIDs(set, info)
    if type(info) ~= "table" then return end
    AddNormalizedID(set, GetTableField(info, "overrideTooltipSpellID"))
    AddNormalizedID(set, GetTableField(info, "overrideSpellID"))
    AddNormalizedID(set, GetTableField(info, "spellID"))
    AddIDsFromValue(set, GetTableField(info, "linkedSpellIDs"))
end

local function AddCDMEntryIDs(set, entry)
    if not entry then return end
    AddNormalizedID(set, entry.cooldownID)

    local icon = entry.icon
    if icon then
        local okAura, auraSpellID = pcall(function() return icon.auraSpellID end)
        if okAura then AddNormalizedID(set, auraSpellID) end

        local okGetAura, getAuraSpellID = pcall(function()
            return icon.GetAuraSpellID and icon:GetAuraSpellID()
        end)
        if okGetAura then AddNormalizedID(set, getAuraSpellID) end

        local okInfo, cooldownInfo = pcall(function() return icon.cooldownInfo end)
        if okInfo then AddCooldownInfoIDs(set, cooldownInfo) end

        local okGetInfo, getInfo = pcall(function()
            return icon.GetCooldownInfo and icon:GetCooldownInfo()
        end)
        if okGetInfo then AddCooldownInfoIDs(set, getInfo) end
    end

    if entry.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, entry.cooldownID)
        if ok then AddCooldownInfoIDs(set, info) end
    end
end

local function AddDynamicEntryIDs(set, entry)
    local iconData = entry and entry.iconData
    if iconData then
        AddNormalizedID(set, iconData.id)
        local settings = iconData.settings
        if settings then
            AddIDsFromValue(set, settings.auraAliases)
            AddIDsFromValue(set, settings.fallbackItems)
            AddIDsFromValue(set, settings.customAuraSpellID)
            AddIDsFromValue(set, settings.customTimedAuraSpellID)
        end
    end

    local frame = entry and entry.frame
    if frame then
        AddNormalizedID(set, frame._cachedAuraSpellID)
        AddNormalizedID(set, frame._ddAuraSpellID)
        AddNormalizedID(set, frame._ddTimedAuraSpellID)
    end
end

local function IDSetsIntersect(a, b)
    for id in pairs(a or {}) do
        if b and b[id] then return true end
    end
    return false
end

local function MarkIDs(target, source)
    for id in pairs(source or {}) do
        target[id] = true
    end
end

local function FilterGroupedBuffDynamicEntries(dynamicIcons, iconList, groupName, groupSettings)
    if type(dynamicIcons) ~= "table" or #dynamicIcons == 0 then return dynamicIcons end

    local cdmIDs = {}
    if GroupUsesDurationText(groupName, groupSettings) then
        for _, entry in ipairs(iconList or {}) do
            AddCDMEntryIDs(cdmIDs, entry)
        end
    end

    local seenIDs = {}
    local seenKeys = {}
    local result = {}
    for _, entry in ipairs(dynamicIcons) do
        local entryIDs = {}
        AddDynamicEntryIDs(entryIDs, entry)

        local duplicateCDM = next(cdmIDs) and next(entryIDs) and IDSetsIntersect(entryIDs, cdmIDs)
        local duplicateDynamic = next(entryIDs) and IDSetsIntersect(entryIDs, seenIDs)
        local key = entry and entry.iconKey and tostring(entry.iconKey)
        if key and seenKeys[key] then
            duplicateDynamic = true
        end

        if not duplicateCDM and not duplicateDynamic then
            result[#result + 1] = entry
            MarkIDs(seenIDs, entryIDs)
            if key then seenKeys[key] = true end
        end
    end

    return result
end

local function ShouldKeepDynamicIconInCombat(icon)
    if not icon or not icon._ddIconKey then return false end

    local iconData = GetDynamicIconData(icon._ddIconKey)
    if not iconData then
        return true
    end

    local now = GetTime and GetTime() or 0
    local function IsStillWithinKnownDuration(...)
        for i = 1, select("#", ...) do
            local activeUntil = SafeNumber((select(i, ...)))
            if activeUntil and activeUntil > now then
                return true
            end
        end
        return false
    end

    -- CDM custom buffs hide and reanchor immediately when their timer ends.
    -- Do not resurrect expired aura/proc frames through combat layout fallback.
    if iconData.type == "aura" then
        if icon._ddManagedAuraExpired then
            return false
        end

        local ci = DDingUI.CustomIcons
        if ci and ci.GetActiveCustomTimedAuraForIcon then
            local timedAura = ci:GetActiveCustomTimedAuraForIcon(iconData)
            if timedAura then
                icon._ddTimedAuraActiveUntil = SafeNumber(SafeTableField(timedAura, "expirationTime"))
                return true
            end
        end
        if ci and ci.ResolvePlayerAuraForIcon then
            local auraData = ci:ResolvePlayerAuraForIcon(icon, iconData)
            if auraData then
                local expirationTime = SafeNumber(SafeTableField(auraData, "expirationTime"))
                if expirationTime and expirationTime > 0 then
                    icon._ddAuraActiveUntil = expirationTime
                end
                return true
            end
        end

        icon._ddTimedAuraActiveUntil = nil
        icon._ddAuraActiveUntil = nil
        return false
    end

    if iconData.type == "trinketProc" then
        local settings = iconData.settings or {}
        if settings.showItemCooldown ~= false and iconData.slotID and GetInventoryItemID("player", iconData.slotID) then
            return true
        end

        if IsStillWithinKnownDuration(icon._ddProcActiveUntil) then
            return true
        end

        local ci = DDingUI.CustomIcons
        if ci and ci.ResolveTrinketProcAuraForIcon then
            local auraData = ci:ResolveTrinketProcAuraForIcon(icon, iconData)
            if auraData then
                local duration = SafeNumber(SafeTableField(auraData, "duration"))
                icon._ddProcActiveUntil = SafeNumber(SafeTableField(auraData, "expirationTime"))
                    or (duration and (now + duration))
                    or (now + 0.75)
                return true
            end
        end
        return icon._trinketProcWasActive == true and IsStillWithinKnownDuration(icon._ddProcActiveUntil)
    end

    return true
end

local function RestoreDynamicIconVisibility(icon, groupName, groupSettings, groupAlpha, combatVisible, inactiveGray)
    if not icon then return end
    ApplyDynamicIconTextOptions(icon, groupName, groupSettings)
    if inactiveGray then
        SetManagedIconLayoutVisible(icon, true)
        icon._ddManagedAuraExpired = nil
        icon._ddCombatVisible = true
        icon._ddCombatKeepAlive = nil
        icon._ddCombatMissingSince = nil
        if icon.Show then
            icon:Show()
        end
        SetAlphaIfNeeded(icon, groupAlpha or 1, "_ddLastGroupAlpha")
        SetDynamicIconInactiveGray(icon, true)
        return
    end
    if icon._ddManagedAuraExpired then
        SetManagedIconLayoutVisible(icon, false)
        icon._ddCombatVisible = false
        icon._ddCombatKeepAlive = nil
        if icon.icon and icon.icon.SetAlpha then
            pcall(icon.icon.SetAlpha, icon.icon, 0)
        end
        if icon.cooldown and icon.cooldown.Hide then
            pcall(icon.cooldown.Hide, icon.cooldown)
        end
        if icon.Cooldown and icon.Cooldown.Hide and icon.Cooldown ~= icon.cooldown then
            pcall(icon.Cooldown.Hide, icon.Cooldown)
        end
        if icon.count and icon.count.Hide then
            pcall(icon.count.Hide, icon.count)
        end
        HideDynamicIconBorderLayers(icon)
        if icon.SetAlpha then
            pcall(icon.SetAlpha, icon, 0)
            icon._ddLastGroupAlpha = 0
        end
        if icon.Hide then
            pcall(icon.Hide, icon)
        end
        return
    end
    if icon.Show then
        icon:Show()
    end
    if combatVisible ~= false then
        icon._ddCombatKeepAlive = nil
        icon._ddCombatVisible = nil
        icon._ddCombatMissingSince = nil
    end
    SetManagedIconLayoutVisible(icon, combatVisible ~= false)
    local iconAlpha = combatVisible == false and 0 or (groupAlpha or 1)
    SetAlphaIfNeeded(icon, iconAlpha, "_ddLastGroupAlpha")
    SetDynamicIconInactiveGray(icon, false)
    if iconAlpha > 0 then
        RestoreIconTextureOpacity(icon)
    end
end

local function RestorePlacementVisibility(entry, groupName, groupSettings, groupAlpha)
    if not entry then return end
    local icon = entry.icon or entry.frame
    if not icon then return end
    if entry.isDynamic then
        RestoreDynamicIconVisibility(icon, groupName, groupSettings, groupAlpha, entry.combatVisible, entry.inactiveGray)
        return
    end
    if entry.sourceVisible == false or GroupRenderer:IsHiddenSourceBuffIcon(icon) then
        SetManagedIconLayoutVisible(icon, false)
        GroupRenderer:HideHiddenSourceBuffIcon(icon)
        return
    end
    SetDynamicIconInactiveGray(icon, entry.inactiveGray == true)
    SetManagedIconLayoutVisible(icon, not icon._ddingHidden and not icon._ddSuppressed)
    if icon.Show and not icon._ddingHidden then
        icon:Show()
    end
    if not icon._ddingHidden then
        SetAlphaIfNeeded(icon, groupAlpha or 1, "_ddLastGroupAlpha")
        if not entry.inactiveGray then
            RestoreIconTextureOpacity(icon)
        end
    end
end

local function RestoreActivePlacements(list, groupName, groupSettings, groupAlpha)
    for _, entry in ipairs(list or {}) do
        RestorePlacementVisibility(entry, groupName, groupSettings, groupAlpha)
    end
end

local function RestoreActiveDynamicEntries(list, groupName, groupSettings, groupAlpha)
    for _, entry in ipairs(list or {}) do
        if entry then
            RestoreDynamicIconVisibility(entry.frame, groupName, groupSettings, groupAlpha, entry.combatVisible, entry.inactiveGray)
        end
    end
end

local function EntryRequiresFreshLayout(entry, frame, layoutHash)
    if not entry or not frame then return false end
    local icon = entry.icon or entry.frame
    if not icon or icon._ddingHidden then return false end

    local isDynamicEntry = entry.isDynamic or entry.iconKey ~= nil
    if isDynamicEntry then
        if not entry.inactiveGray and (entry.combatVisible == false or icon._ddCombatVisible == false or icon._ddManagedAuraExpired) then
            return false
        end
    elseif entry.sourceVisible == false or GroupRenderer:IsHiddenSourceBuffIcon(icon) then
        return false
    end

    if icon._ddContainerRef ~= frame then return true end
    if icon._ddTargetPoint ~= "CENTER" or icon._ddTargetX == nil or icon._ddTargetY == nil then return true end
    local motion = icon._ddPositionMotion
    if motion then
        if motion.container ~= frame or motion.toX ~= icon._ddTargetX or motion.toY ~= icon._ddTargetY then
            return true
        end
    else
        if icon._ddCurrentContainer ~= frame or icon._ddCurrentX == nil or icon._ddCurrentY == nil then return true end
        if icon._ddCurrentX ~= icon._ddTargetX or icon._ddCurrentY ~= icon._ddTargetY then return true end
        if not IconAnchorMatches(icon, frame, icon._ddTargetX, icon._ddTargetY) then return true end
    end
    if icon._ddLastGroupLayoutHash ~= layoutHash then return true end
    return false
end

local function ListRequiresFreshLayout(list, frame, layoutHash)
    for _, entry in ipairs(list or {}) do
        if EntryRequiresFreshLayout(entry, frame, layoutHash) then
            return true
        end
    end
    return false
end

local function ApplyGroupIconOrder(groupSettings, combinedList)
    local iconOrder = groupSettings and groupSettings.iconOrder
    if type(iconOrder) ~= "table" or #iconOrder == 0 then return end

    local ORDER_STRIDE = 1000
    local orderMap = {}
    for i, token in ipairs(iconOrder) do
        if type(token) == "string" and token ~= "" and not orderMap[token] then
            orderMap[token] = i * ORDER_STRIDE
        end
    end

    for i, entry in ipairs(combinedList) do
        entry._ddDefaultOrder = i
        if not entry._ddOrderToken then
            if entry.isDynamic then
                entry._ddOrderToken = BuildDynamicOrderToken(entry.iconKey or entry.cooldownID)
            else
                entry._ddOrderToken = BuildCDMOrderToken(entry)
            end
        end
    end

    local cdmAnchors = {}
    for _, entry in ipairs(combinedList) do
        local token = entry._ddOrderToken
        local rank = token and orderMap[token]
        if rank and not entry.isDynamic then
            cdmAnchors[#cdmAnchors + 1] = {
                defaultOrder = entry._ddDefaultOrder or 0,
                rank = rank,
            }
        end
    end
    table.sort(cdmAnchors, function(a, b)
        return (a.defaultOrder or 0) < (b.defaultOrder or 0)
    end)

    local function GetImplicitCDMRank(entry)
        if not entry or entry.isDynamic then return nil end
        if entry._ddOrderToken and orderMap[entry._ddOrderToken] then return nil end
        local defaultOrder = entry._ddDefaultOrder or 0
        local prevAnchor, nextAnchor
        for _, anchor in ipairs(cdmAnchors) do
            if anchor.defaultOrder < defaultOrder then
                prevAnchor = anchor
            elseif anchor.defaultOrder > defaultOrder then
                nextAnchor = anchor
                break
            end
        end

        if prevAnchor and nextAnchor and nextAnchor.rank > prevAnchor.rank then
            local span = nextAnchor.defaultOrder - prevAnchor.defaultOrder
            if span > 0 then
                local ratio = (defaultOrder - prevAnchor.defaultOrder) / span
                return prevAnchor.rank + ((nextAnchor.rank - prevAnchor.rank) * ratio) + (defaultOrder * 0.001)
            end
        elseif prevAnchor then
            return prevAnchor.rank + (ORDER_STRIDE * 0.5) + (defaultOrder * 0.001)
        elseif nextAnchor then
            return nextAnchor.rank - (ORDER_STRIDE * 0.5) + (defaultOrder * 0.001)
        end

        return nil
    end

    table.sort(combinedList, function(a, b)
        local aOrder = a._ddOrderToken and orderMap[a._ddOrderToken]
        local bOrder = b._ddOrderToken and orderMap[b._ddOrderToken]
        local aRank = aOrder or GetImplicitCDMRank(a)
        local bRank = bOrder or GetImplicitCDMRank(b)
        if aRank or bRank then
            aRank = aRank or (100000000 + (a._ddDefaultOrder or 0))
            bRank = bRank or (100000000 + (b._ddDefaultOrder or 0))
            if aRank ~= bRank then return aRank < bRank end
        end
        return (a._ddDefaultOrder or 0) < (b._ddDefaultOrder or 0)
    end)
end

-- ============================================================
-- ViewerLayout 동일 헬퍼 함수들
-- [REPARENT] 뷰어 설정을 100% 반영하기 위해 ViewerLayout과 동일 로직 복제
-- ============================================================

local function AddHashValue(parts, key, value)
    if value == nil then return end
    parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
end

local function AddHashColor(parts, key, color)
    if type(color) ~= "table" then return end
    AddHashValue(parts, key .. "1", color[1] or color.r)
    AddHashValue(parts, key .. "2", color[2] or color.g)
    AddHashValue(parts, key .. "3", color[3] or color.b)
    AddHashValue(parts, key .. "4", color[4] or color.a)
end

local function BuildGroupRenderSettingsHash(groupSettings)
    if type(groupSettings) ~= "table" then return "" end
    local parts = {}
    AddHashValue(parts, "iconSize", groupSettings.iconSize)
    AddHashValue(parts, "aspectRatioCrop", groupSettings.aspectRatioCrop)
    AddHashValue(parts, "spacing", groupSettings.spacing)
    AddHashValue(parts, "direction", groupSettings.direction)
    AddHashValue(parts, "growDirection", groupSettings.growDirection)
    AddHashValue(parts, "rowLimit", groupSettings.rowLimit)
    AddHashValue(parts, "zoom", groupSettings.zoom)
    AddHashValue(parts, "borderSize", groupSettings.borderSize)
    AddHashColor(parts, "borderColor", groupSettings.borderColor)
    AddHashValue(parts, "groupAlpha", groupSettings.groupAlpha)
    AddHashValue(parts, "showInactiveIcons", groupSettings.showInactiveIcons)
    AddHashValue(parts, "cooldownShadowOffsetX", groupSettings.cooldownShadowOffsetX)
    AddHashValue(parts, "cooldownShadowOffsetY", groupSettings.cooldownShadowOffsetY)
    AddHashValue(parts, "groupCategory", groupSettings.groupCategory)
    AddHashValue(parts, "iconMotion", groupSettings.iconMotion)
    AddHashValue(parts, "iconMotionDuration", groupSettings.iconMotionDuration)
    AddHashValue(parts, "disableSwipeAnimation", groupSettings.disableSwipeAnimation)
    AddHashValue(parts, "swipeReverse", groupSettings.swipeReverse)
    AddHashColor(parts, "swipeColor", groupSettings.swipeColor)
    AddHashValue(parts, "hideActiveState", groupSettings.hideActiveState)
    AddHashValue(parts, "auraGlow", groupSettings.auraGlow)
    AddHashValue(parts, "auraGlowType", groupSettings.auraGlowType)
    AddHashValue(parts, "auraGlowPixelLines", groupSettings.auraGlowPixelLines)
    AddHashValue(parts, "auraGlowPixelFrequency", groupSettings.auraGlowPixelFrequency)
    AddHashValue(parts, "auraGlowPixelThickness", groupSettings.auraGlowPixelThickness)
    AddHashValue(parts, "auraGlowPixelLength", groupSettings.auraGlowPixelLength)
    AddHashValue(parts, "auraGlowAutocastParticles", groupSettings.auraGlowAutocastParticles)
    AddHashValue(parts, "auraGlowAutocastFrequency", groupSettings.auraGlowAutocastFrequency)
    AddHashValue(parts, "auraGlowAutocastScale", groupSettings.auraGlowAutocastScale)
    AddHashValue(parts, "auraGlowButtonFrequency", groupSettings.auraGlowButtonFrequency)
    AddHashColor(parts, "auraGlowColor", groupSettings.auraGlowColor)
    AddHashValue(parts, "procGlowEnabled", groupSettings.procGlowEnabled)
    AddHashValue(parts, "procGlowType", groupSettings.procGlowType)
    AddHashValue(parts, "procGlowPixelLines", groupSettings.procGlowPixelLines)
    AddHashValue(parts, "procGlowPixelFrequency", groupSettings.procGlowPixelFrequency)
    AddHashValue(parts, "procGlowPixelThickness", groupSettings.procGlowPixelThickness)
    AddHashValue(parts, "procGlowPixelLength", groupSettings.procGlowPixelLength)
    AddHashValue(parts, "procGlowAutocastParticles", groupSettings.procGlowAutocastParticles)
    AddHashValue(parts, "procGlowAutocastFrequency", groupSettings.procGlowAutocastFrequency)
    AddHashValue(parts, "procGlowAutocastScale", groupSettings.procGlowAutocastScale)
    AddHashValue(parts, "procGlowButtonFrequency", groupSettings.procGlowButtonFrequency)
    AddHashColor(parts, "procGlowColor", groupSettings.procGlowColor)
    AddHashValue(parts, "assistHighlightEnabled", groupSettings.assistHighlightEnabled)
    AddHashValue(parts, "assistHighlightType", groupSettings.assistHighlightType)
    AddHashValue(parts, "assistFlipbookScale", groupSettings.assistFlipbookScale)
    AddHashValue(parts, "assistGlowType", groupSettings.assistGlowType)
    AddHashValue(parts, "assistGlowLines", groupSettings.assistGlowLines)
    AddHashValue(parts, "assistGlowFrequency", groupSettings.assistGlowFrequency)
    AddHashValue(parts, "assistGlowThickness", groupSettings.assistGlowThickness)
    AddHashValue(parts, "assistHighlightPixelLength", groupSettings.assistHighlightPixelLength)
    AddHashColor(parts, "assistGlowColor", groupSettings.assistGlowColor)
    AddHashValue(parts, "disableEdgeGlow", groupSettings.disableEdgeGlow)
    AddHashValue(parts, "disableBlingAnimation", groupSettings.disableBlingAnimation)
    AddHashValue(parts, "countTextFont", groupSettings.countTextFont)
    AddHashValue(parts, "countTextSize", groupSettings.countTextSize)
    AddHashColor(parts, "countTextColor", groupSettings.countTextColor)
    AddHashValue(parts, "chargeTextAnchor", groupSettings.chargeTextAnchor)
    AddHashValue(parts, "countTextOffsetX", groupSettings.countTextOffsetX)
    AddHashValue(parts, "countTextOffsetY", groupSettings.countTextOffsetY)
    AddHashValue(parts, "cooldownFont", groupSettings.cooldownFont)
    AddHashValue(parts, "cooldownFontSize", groupSettings.cooldownFontSize)
    AddHashColor(parts, "cooldownTextColor", groupSettings.cooldownTextColor)
    AddHashValue(parts, "cooldownTextAnchor", groupSettings.cooldownTextAnchor)
    AddHashValue(parts, "cooldownTextOffsetX", groupSettings.cooldownTextOffsetX)
    AddHashValue(parts, "cooldownTextOffsetY", groupSettings.cooldownTextOffsetY)
    AddHashValue(parts, "cooldownTextFormat", groupSettings.cooldownTextFormat)
    AddHashValue(parts, "hideDurationText", groupSettings.hideDurationText)
    AddHashValue(parts, "durationTextFont", groupSettings.durationTextFont)
    AddHashValue(parts, "durationTextSize", groupSettings.durationTextSize)
    AddHashColor(parts, "durationTextColor", groupSettings.durationTextColor)
    AddHashValue(parts, "durationTextAnchor", groupSettings.durationTextAnchor)
    AddHashValue(parts, "durationTextOffsetX", groupSettings.durationTextOffsetX)
    AddHashValue(parts, "durationTextOffsetY", groupSettings.durationTextOffsetY)

    if type(groupSettings.rowIconSizes) == "table" then
        for i = 1, 8 do
            AddHashValue(parts, "rowIconSize" .. i, groupSettings.rowIconSizes[i])
        end
    end
    if type(groupSettings.groupOffsets) == "table" then
        local party = groupSettings.groupOffsets.party
        local raid = groupSettings.groupOffsets.raid
        if type(party) == "table" then
            AddHashValue(parts, "partyX", party.x)
            AddHashValue(parts, "partyY", party.y)
        end
        if type(raid) == "table" then
            AddHashValue(parts, "raidX", raid.x)
            AddHashValue(parts, "raidY", raid.y)
        end
    end

    return table_concat(parts, "|")
end

local function BuildPlacementHash(combinedList, groupSettings)
    local parts = {}
    local settingsHash = BuildGroupRenderSettingsHash(groupSettings)
    if settingsHash ~= "" then
        parts[#parts + 1] = "settings:" .. settingsHash
    end
    for i, entry in ipairs(combinedList or {}) do
        local icon = entry.icon or entry.frame
        local token = entry._ddOrderToken
            or (entry.isDynamic and BuildDynamicOrderToken(entry.iconKey or entry.cooldownID))
            or BuildCDMOrderToken(entry)
            or tostring(i)
        local visible = "1"
        if icon and (icon._ddingHidden or icon._ddSuppressed) then
            visible = "0"
        elseif entry.inactiveGray then
            visible = "g"
        elseif entry.isDynamic and entry.combatVisible == false then
            visible = "0"
        elseif entry.isCDM and (entry.sourceVisible == false or GroupRenderer:IsHiddenSourceBuffIcon(entry.icon)) then
            visible = "0"
        end
        parts[#parts + 1] = tostring(token) .. "@" .. tostring(icon or i) .. ":" .. visible
    end
    return table_concat(parts, ";")
end

local function PixelSnap(val)
    return math_floor(val + 0.5)
end

-- profile.viewers[viewerName] 참조
local function GetViewerSettings(viewerName)
    local profile = DDingUI.db and DDingUI.db.profile
    return viewerName and profile and profile.viewers and profile.viewers[viewerName]
end

-- ViewerLayout.ComputeIconDimensions 동일
local function ComputeIconDimensions(settings, sizeOverride)
    local baseSize = sizeOverride or settings.iconSize or 32
    local iconSize = baseSize + 0.1
    local aspectRatioValue = 1.0

    if settings.aspectRatioCrop then
        aspectRatioValue = settings.aspectRatioCrop
    elseif settings.aspectRatio then
        local aspectW, aspectH = settings.aspectRatio:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        if aspectW and aspectH then
            aspectRatioValue = tonumber(aspectW) / tonumber(aspectH)
        end
    end

    local iconWidth = iconSize
    local iconHeight = iconSize

    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            iconHeight = iconSize / aspectRatioValue
        elseif aspectRatioValue < 1.0 then
            iconWidth = iconSize * aspectRatioValue
        end
    end

    return PixelSnap(iconWidth), PixelSnap(iconHeight)
end

-- [FIX] spacing 값 그대로 사용 (ViewerLayout과 동일)
local function ComputeSpacing(settings)
    local spacing = settings.spacing or 2
    return PixelSnap(spacing)
end

-- ViewerLayout.GetRowIconSize 동일
local function GetRowIconSize(settings, rowIndex)
    if not settings or not settings.rowIconSizes then
        return nil
    end
    local value = settings.rowIconSizes[rowIndex]
    if type(value) == "string" then
        value = tonumber(value)
    end
    if type(value) == "number" and value > 0 then
        return value
    end
    return nil
end

-- ViewerLayout.DIRECTION_RULES 동일
local DIRECTION_RULES = {
    CENTERED_HORIZONTAL = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    LEFT                = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    RIGHT               = { type = "HORIZONTAL", defaultSecondary = "DOWN",  allowed = { UP = true, DOWN = true } },
    UP                  = { type = "VERTICAL",   defaultSecondary = "RIGHT", allowed = { LEFT = true, RIGHT = true } },
    DOWN                = { type = "VERTICAL",   defaultSecondary = "RIGHT", allowed = { LEFT = true, RIGHT = true } },
    STATIC              = { type = "STATIC" },
}

-- ViewerLayout.NormalizeDirectionToken 동일
local function NormalizeDirectionToken(token)
    if not token or token == "" then
        return nil
    end
    local aliases = {
        CENTEREDHORIZONTAL = "CENTERED_HORIZONTAL",
        CENTERHORIZONTAL   = "CENTERED_HORIZONTAL",
        CENTERED           = "CENTERED_HORIZONTAL",
        CENTER             = "CENTERED_HORIZONTAL",
        CENTRED            = "CENTERED_HORIZONTAL",
        CENTRE             = "CENTERED_HORIZONTAL",
    }
    local cleaned = token:gsub("[%s%-_]+", ""):upper()
    return aliases[cleaned] or cleaned
end

-- ViewerLayout.ResolveDirections 동일
local function ResolveDirections(viewerName, settings)
    local primary = NormalizeDirectionToken(settings.primaryDirection)
    local secondary = NormalizeDirectionToken(settings.secondaryDirection)

    -- Legacy growthDirection 호환
    local legacyDirection = settings.growthDirection
    if not primary and legacyDirection then
        if legacyDirection == "Static" or legacyDirection == "STATIC" then
            primary = "STATIC"
        elseif legacyDirection:match("^Centered Horizontal and") then
            primary = "CENTERED_HORIZONTAL"
            local token = legacyDirection:match("and%s+(.+)$")
            secondary = NormalizeDirectionToken(token)
        elseif legacyDirection == "Centered Horizontal" then
            primary = "CENTERED_HORIZONTAL"
        else
            local p = legacyDirection:match("^(%w+)")
            primary = NormalizeDirectionToken(p)
            local s = legacyDirection:match("and%s+(.+)$")
            secondary = NormalizeDirectionToken(s)
        end
    end

    -- BuffIconCooldownViewer rowGrowDirection 호환
    if not primary and viewerName == "BuffIconCooldownViewer" and settings.rowGrowDirection then
        primary = "CENTERED_HORIZONTAL"
        if type(settings.rowGrowDirection) == "string" and settings.rowGrowDirection:lower() == "up" then
            secondary = "UP"
        else
            secondary = "DOWN"
        end
    end

    primary = primary or "CENTERED_HORIZONTAL"
    local rule = DIRECTION_RULES[primary]
    if not rule then
        primary = "CENTERED_HORIZONTAL"
        rule = DIRECTION_RULES[primary]
    end

    local rowLimit = settings.rowLimit or 0
    if rowLimit < 0 then rowLimit = 0 end
    rowLimit = math_floor(rowLimit + 0.0001)

    if rule.type ~= "STATIC" and rowLimit > 0 then
        if not secondary or not rule.allowed[secondary] then
            secondary = rule.defaultSecondary
        end
    else
        secondary = nil
    end

    return primary, secondary, rowLimit, rule.type
end

-- ============================================================
-- snap-back 안전 아이콘 위치/크기 설정
-- FrameController 훅을 우회하면서 타겟 값도 동시 갱신
-- ============================================================

local function SetIconPosition(icon, container, x, y, motionSettings)
    -- 위치 동일하면 skip → ClearAllPoints 깜빡임 방지
    -- [REPARENT] GetParent() → _ddContainerRef (parent는 UIParent)
    if icon._ddTargetPoint == "CENTER"
       and icon._ddTargetX == x and icon._ddTargetY == y
       and icon._ddContainerRef == container
       and icon._ddCurrentContainer == container
       and icon._ddCurrentX == x and icon._ddCurrentY == y
       and IconAnchorMatches(icon, container, x, y) then
        return
    end

    local fromX = icon._ddCurrentX
    local fromY = icon._ddCurrentY
    local fromContainer = icon._ddCurrentContainer
    local hasCurrentPosition = fromContainer ~= nil and fromX ~= nil and fromY ~= nil
    local activeMotion = icon._ddPositionMotion
    if activeMotion then
        fromX = icon._ddCurrentX or activeMotion.fromX
        fromY = icon._ddCurrentY or activeMotion.fromY
        fromContainer = activeMotion.container
        hasCurrentPosition = fromContainer ~= nil and fromX ~= nil and fromY ~= nil
    end
    if fromContainer ~= container then
        if hasCurrentPosition then
            fromX = icon._ddTargetX
            fromY = icon._ddTargetY
            fromContainer = icon._ddContainerRef
            hasCurrentPosition = fromContainer ~= nil and fromX ~= nil and fromY ~= nil
        else
            fromX = nil
            fromY = nil
            fromContainer = nil
        end
    end

    icon._ddTargetPoint = "CENTER"
    icon._ddTargetRelPoint = "CENTER"
    icon._ddTargetX = x
    icon._ddTargetY = y

    local canAnimate = motionSettings and motionSettings.enabled
        and hasCurrentPosition
        and fromContainer == container
        and fromX ~= nil and fromY ~= nil
        and (math_abs(fromX - x) > ICON_MOTION_MIN_DELTA or math_abs(fromY - y) > ICON_MOTION_MIN_DELTA)

    if canAnimate then
        local duration = tonumber(motionSettings.duration) or ICON_MOTION_DEFAULT_DURATION
        if duration <= 0.01 then
            StopIconMotion(icon)
            ApplyIconPositionNow(icon, container, x, y)
            return
        end

        if not icon._ddPositionMotion then
            activeIconMotionCount = activeIconMotionCount + 1
        end
        icon._ddPositionMotion = {
            container = container,
            fromX = fromX,
            fromY = fromY,
            toX = x,
            toY = y,
            elapsed = 0,
            duration = duration,
        }
        activeIconMotions[icon] = icon._ddPositionMotion
        iconMotionDriver:Show()
    else
        StopIconMotion(icon)
        ApplyIconPositionNow(icon, container, x, y)
    end
end

local function SetIconSize(icon, w, h)
    w = math_max(tonumber(w) or 1, 1)
    h = math_max(tonumber(h) or w, 1)
    -- 크기 동일하면 skip
    if icon._ddTargetWidth == w and icon._ddTargetHeight == h then return end
    icon._ddTargetWidth = w
    icon._ddTargetHeight = h

    icon._ddSettingSize = true
    icon:SetSize(w, h)
    icon._ddSettingSize = false
end

-- ============================================================
-- ViewerLayout.LayoutHorizontal 동일 (snap-back 지원 버전)
-- CENTERED_HORIZONTAL, LEFT, RIGHT + 보조 방향 UP/DOWN
-- ============================================================

local function LayoutHorizontal(icons, container, primary, secondary, spacing, rowLimit, getDimensionsForRow, motionSettings)
    local count = #icons
    if count == 0 then return 0, 0 end

    local iconsPerRow = rowLimit > 0 and math_max(1, rowLimit) or count
    local numRows = math_ceil(count / iconsPerRow)
    local rowDirection = (secondary == "UP") and 1 or -1

    -- 행 메타데이터 계산
    local rowMeta = {}
    local maxRowWidth = 0
    local totalHeight = 0
    for row = 1, numRows do
        local iconWidth, iconHeight = getDimensionsForRow(row)
        local rowStart = (row - 1) * iconsPerRow + 1
        local rowEnd = math_min(row * iconsPerRow, count)
        local rowCount = rowEnd - rowStart + 1
        local rowWidth = rowCount * iconWidth + (rowCount - 1) * spacing
        if rowWidth < iconWidth then
            rowWidth = iconWidth
        end
        maxRowWidth = math_max(maxRowWidth, rowWidth)
        totalHeight = totalHeight + iconHeight

        rowMeta[row] = {
            startIndex = rowStart,
            count = rowCount,
            width = rowWidth,
            iconWidth = iconWidth,
            iconHeight = iconHeight,
        }
    end

    totalHeight = totalHeight + (numRows - 1) * spacing

    -- Row 1을 기준점으로 anchorY 계산 (DOWN이면 위에서, UP이면 아래에서 시작)
    local anchorY
    if motionSettings and motionSettings.pinWrappedRowsToAnchor then
        anchorY = 0
    elseif rowDirection == -1 then
        anchorY = (totalHeight / 2) - (rowMeta[1].iconHeight / 2)
    else
        anchorY = -(totalHeight / 2) + (rowMeta[1].iconHeight / 2)
    end

    local currentY = anchorY
    for row = 1, numRows do
        local meta = rowMeta[row]
        local baseX
        if primary == "CENTERED_HORIZONTAL" then
            -- 각 행이 독립적으로 가운데 정렬 (행별 아이콘 수에 맞춤)
            baseX = -meta.width / 2 + meta.iconWidth / 2
        elseif primary == "RIGHT" then
            baseX = -(maxRowWidth / 2) + (meta.iconWidth / 2)
        else -- LEFT
            baseX = (maxRowWidth / 2) - (meta.iconWidth / 2)
        end

        for position = 0, meta.count - 1 do
            local icon = icons[meta.startIndex + position]
            local x
            if primary == "LEFT" then
                x = baseX - position * (meta.iconWidth + spacing)
            else
                x = baseX + position * (meta.iconWidth + spacing)
            end

            SetIconSize(icon, meta.iconWidth, meta.iconHeight)
            SetIconPosition(icon, container, math_floor(x + 0.5), math_floor(currentY + 0.5), motionSettings)
        end

        local nextMeta = rowMeta[row + 1]
        if nextMeta then
            local step = (meta.iconHeight / 2) + (nextMeta.iconHeight / 2) + spacing
            currentY = currentY + step * rowDirection
        end
    end

    return maxRowWidth, totalHeight
end

-- ============================================================
-- ViewerLayout.LayoutVertical 동일 (snap-back 지원 버전)
-- UP, DOWN + 보조 방향 LEFT/RIGHT
-- ============================================================

local function LayoutVertical(icons, container, primary, secondary, spacing, rowLimit, getDimensionsForRow, motionSettings)
    local count = #icons
    if count == 0 then return 0, 0 end

    local iconsPerColumn = rowLimit > 0 and math_max(1, rowLimit) or count
    local numColumns = math_ceil(count / iconsPerColumn)
    local columnDirection = (secondary == "LEFT") and -1 or 1
    local verticalDirection = (primary == "UP") and 1 or -1

    -- 열 메타데이터 계산
    local columnMeta = {}
    local maxColumnHeight = 0
    local totalWidth = 0
    for column = 1, numColumns do
        local iconWidth, iconHeight = getDimensionsForRow(column)
        local columnStart = (column - 1) * iconsPerColumn + 1
        local columnEnd = math_min(column * iconsPerColumn, count)
        local columnCount = columnEnd - columnStart + 1
        local columnHeight = columnCount * iconHeight + (columnCount - 1) * spacing

        maxColumnHeight = math_max(maxColumnHeight, columnHeight)
        totalWidth = totalWidth + iconWidth
        if column > 1 then
            totalWidth = totalWidth + spacing
        end

        columnMeta[column] = {
            startIndex = columnStart,
            count = columnCount,
            height = columnHeight,
            iconWidth = iconWidth,
            iconHeight = iconHeight,
        }
    end

    local totalHeight = maxColumnHeight

    -- Column 1 기준 anchorX
    local anchorX
    if columnDirection == 1 then
        anchorX = -(totalWidth / 2) + (columnMeta[1].iconWidth / 2)
    else
        anchorX = (totalWidth / 2) - (columnMeta[1].iconWidth / 2)
    end

    -- 수직 기준 anchorY
    local anchorY
    if verticalDirection == -1 then
        anchorY = (totalHeight / 2) - (columnMeta[1].iconHeight / 2)
    else
        anchorY = -(totalHeight / 2) + (columnMeta[1].iconHeight / 2)
    end

    local currentX = anchorX
    for column = 1, numColumns do
        local meta = columnMeta[column]
        local startY = anchorY

        for position = 0, meta.count - 1 do
            local icon = icons[meta.startIndex + position]
            local y = startY + position * (meta.iconHeight + spacing) * verticalDirection

            SetIconSize(icon, meta.iconWidth, meta.iconHeight)
            SetIconPosition(icon, container, math_floor(currentX + 0.5), math_floor(y + 0.5), motionSettings)
        end

        local nextMeta = columnMeta[column + 1]
        if nextMeta then
            local step = (meta.iconWidth / 2) + (nextMeta.iconWidth / 2) + spacing
            currentX = currentX + step * columnDirection
        end
    end

    return totalWidth, totalHeight
end

-- ============================================================
-- 그룹 프레임 생성
-- [REPARENT] _isDDContainer 태그 추가
-- ============================================================

function GroupRenderer:CreateGroupFrame(groupName, groupSettings)
    if self.groupFrames[groupName] then
        return self.groupFrames[groupName]
    end

    local frame = CreateFrame("Frame", "DDingUI_Group_" .. groupName, UIParent)
    frame:SetSize(200, 50) -- 초기 크기, 레이아웃 후 조정

    -- [REPARENT] Mover 저장 위치가 없으면 소속 CDM 뷰어 위치를 마이그레이션
    -- [FIX] _moverSaved 플래그: 편집모드에서 위치 저장 시 설정됨
    -- → 뷰어 마이그레이션을 건너뛰고 저장된 groupSettings 위치 사용

    -- [FIX] 핵심 3대 그룹은 프록시 앵커가 마스터 → 프록시 위치에서 초기 좌표 설정
    -- SyncProxyAnchors OnUpdate에서 매 프레임 프록시→그룹 동기화하므로
    -- 여기서는 프록시가 있으면 프록시에 맞추고, 없으면 settings 폴백
    local CORE_PROXY = {
        ["Cooldowns"] = "DDingUI_Anchor_Cooldowns",
        ["Buffs"]     = "DDingUI_Anchor_Buffs",
        ["Utility"]   = "DDingUI_Anchor_Utility",
    }
    local proxyName = CORE_PROXY[groupName]
    local proxyFrame = proxyName and _G[proxyName]

    local moverId = proxyName or ("DDingUI_Group_" .. groupName)
    local hasMoverPos = DDingUI.Movers and DDingUI.Movers.CreatedMovers
        and DDingUI.Movers.CreatedMovers[moverId]
    local hasSavedPos = groupSettings._moverSaved  -- [FIX] 편집모드 저장 위치 존재 여부
    local hasBeenMigrated = groupSettings._viewerPosMigrated  -- [FIX] 이미 마이그레이션 완료된 프로필
    local usedViewerPos = false

    -- [FIX] 프록시 앵커가 있는 핵심 3대 그룹은 별도의 폴백이나 좌표계산 없이 프록시를 앵커로 종속됨.
    -- 프록시 자체의 위치는 Mover에서 groupSettings 정보를 읽어 완벽히 복원하므로,
    -- 0,0으로 맞추기만 하면 항상 정확히 일치하며 마우스 드래그도 실시간으로 반영됨.
    if proxyFrame then
        frame:SetPoint("CENTER", proxyFrame, "CENTER", 0, 0)
    else
        if not hasMoverPos and not hasSavedPos and not hasBeenMigrated then
            local viewerName = GROUP_VIEWER_MAP[groupName]
            local profile = DDingUI.db and DDingUI.db.profile
            local vs = viewerName and profile and profile.viewers and profile.viewers[viewerName]

            -- [FIX] 뷰어가 구 프로필에서 비활성이었으면 뷰어 위치 마이그레이션 스킵
            local viewerWasDisabled = vs and vs.enabled == false

            -- 1순위: 뷰어 프로필의 커스텀 앵커 프레임
            if not viewerWasDisabled and vs and vs.anchorFrame and vs.anchorFrame ~= "" then
                local target = _G[vs.anchorFrame]
                if target then
                    local pt = vs.anchorPoint or "CENTER"
                    local ox = vs.anchorOffsetX or 0
                    local oy = vs.anchorOffsetY or 0
                    frame:SetPoint(pt, target, pt, ox, oy)
                    groupSettings.attachTo = vs.anchorFrame
                    groupSettings.anchorPoint = pt
                    groupSettings.selfPoint = pt
                    groupSettings.offsetX = ox
                    groupSettings.offsetY = oy
                    groupSettings._moverSaved = true
                    usedViewerPos = true
                end
            end

            -- 2순위: 뷰어 프로필의 앵커 오프셋
            if not usedViewerPos and not viewerWasDisabled and vs then
                local ox = vs.anchorOffsetX or 0
                local oy = vs.anchorOffsetY or 0
                if ox ~= 0 or oy ~= 0 then
                    local pt = vs.anchorPoint or "CENTER"
                    frame:SetPoint(pt, UIParent, pt, ox, oy)
                    groupSettings.anchorPoint = pt
                    groupSettings.selfPoint = pt
                    groupSettings.offsetX = ox
                    groupSettings.offsetY = oy
                    groupSettings._moverSaved = true
                    usedViewerPos = true
                end
            end

            -- 2.5순위: movers 테이블에서 뷰어 이름으로 저장된 위치
            if not usedViewerPos and not viewerWasDisabled then
                local movers = profile and profile.movers
                local moverStr = viewerName and movers and movers[viewerName]
                if moverStr and type(moverStr) == "string" then
                    local pt, relFrame, relPt, sx, sy = strsplit(",", moverStr)
                    local mx, my = tonumber(sx), tonumber(sy)
                    if mx and my then
                        pt = pt or "CENTER"
                        relPt = relPt or "CENTER"
                        local anchor = (relFrame and relFrame ~= "" and _G[relFrame]) or UIParent
                        frame:SetPoint(pt, anchor, relPt, mx, my)
                        groupSettings.anchorPoint = relPt
                        groupSettings.selfPoint = pt
                        groupSettings.offsetX = mx
                        groupSettings.offsetY = my
                        if relFrame and relFrame ~= "" and relFrame ~= "UIParent" then
                            groupSettings.attachTo = relFrame
                        end
                        groupSettings._moverSaved = true
                        usedViewerPos = true
                    end
                end
            end

            -- 3순위: CDM 편집모드 DB 직접 읽기 (CDM.db.editModePositions)
            -- CDM이 뷰어 위치를 DB에 저장하므로, 프레임 위치 대신 DB에서 직접 읽으면 타이밍 문제 없음
            if not usedViewerPos and not viewerWasDisabled then
                local CDM_Addon = nil
                local cdmDB = CDM_Addon and CDM_Addon.db
                local editPos = cdmDB and cdmDB.editModePositions
                if editPos then
                    local viewerPos = editPos[viewerName]
                    local savedPos = viewerPos and viewerPos["Default"]
                    if savedPos and savedPos.x and savedPos.y then
                        local pt = savedPos.point or "CENTER"
                        local sx = savedPos.x
                        local sy = savedPos.y
                        -- Essential/Buffs: AnchorMainLayoutContainer는 TOP/BOTTOM 기준
                        -- Essential: SetPixelPerfectPoint(container, "TOP", UIParent, point, x, y)
                        -- Buffs: SetPixelPerfectPoint(container, "BOTTOM", UIParent, point, x, y + yOffset)
                        -- DDingUI 그룹 시스템은 CENTER 기준이므로 변환 필요 없이 그대로 사용
                        frame:SetPoint("CENTER", UIParent, pt, sx, sy)
                        groupSettings.anchorPoint = pt
                        groupSettings.selfPoint = "CENTER"
                        groupSettings.offsetX = sx
                        groupSettings.offsetY = sy
                        groupSettings._moverSaved = true
                        usedViewerPos = true
                    end
                end
            end

            -- [FALLBACK] CDM DB도 없으면 → 지연 재시도 (GetCenter 폴백)
            if not usedViewerPos and not viewerWasDisabled and viewerName then
                local capturedFrame = frame
                local capturedSettings = groupSettings
                local capturedViewerName = viewerName
                local retryDelays = { 2, 4 }
                for _, delay in ipairs(retryDelays) do
                    C_Timer.After(delay, function()
                        if capturedSettings._moverSaved then return end
                        local viewer = _G[capturedViewerName]
                        if not viewer then return end
                        local cx, cy = viewer:GetCenter()
                        local uiCX, uiCY = UIParent:GetCenter()
                        if cx and cy and uiCX and uiCY then
                            local ox = cx - uiCX
                            local oy = cy - uiCY
                            if math.abs(ox) > 50 or math.abs(oy) > 50 then
                                capturedSettings.anchorPoint = "CENTER"
                                capturedSettings.selfPoint = "CENTER"
                                capturedSettings.offsetX = ox
                                capturedSettings.offsetY = oy
                                capturedSettings._moverSaved = true
                                capturedFrame:ClearAllPoints()
                                capturedFrame:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                            end
                        end
                    end)
                end
            end
        end

        local goX, goY = 0, 0
        local vn = GROUP_VIEWER_MAP[groupName]
        if vn then
            local profile = DDingUI.db and DDingUI.db.profile
            local vs = profile and profile.viewers and profile.viewers[vn]
            local overrides = vs and vs.groupOffsets
            if overrides then
                if IsInRaid() then
                    goX = overrides.raid and overrides.raid.x or 0
                    goY = overrides.raid and overrides.raid.y or 0
                elseif IsInGroup() then
                    goX = overrides.party and overrides.party.x or 0
                    goY = overrides.party and overrides.party.y or 0
                end
            end
        end

        local attachTo = groupSettings.attachTo or "UIParent"
        local anchorFrame = _G[attachTo] or UIParent
        local selfPoint = groupSettings.selfPoint or "CENTER"

        local scaledGoX = DDingUI.Scale and DDingUI:Scale(goX) or goX
        local scaledGoY = DDingUI.Scale and DDingUI:Scale(goY) or goY

        frame:SetPoint(
            selfPoint,
            anchorFrame,
            groupSettings.anchorPoint or "CENTER",
            (groupSettings.offsetX or 0) + scaledGoX,
            (groupSettings.offsetY or 0) + scaledGoY
        )
    end

    frame:SetFrameStrata("MEDIUM")
    frame:Show()

    frame._groupName = groupName
    frame._isDDContainer = true  -- [REPARENT] FrameController snap-back 훅 식별 태그
    frame._managedIcons = {}     -- 현재 re-parent된 CDM 아이콘 목록
    frame._iconCount = 0

    -- [REPARENT] 컨테이너 OnHide/OnShow → 관리 아이콘 visibility 동기화
    -- UIParent 자식 아이콘은 컨테이너 숨김을 상속하지 않으므로 수동 전파 필요
    frame:HookScript("OnHide", function(self)
        for i = 1, (self._iconCount or 0) do
            local ic = self._managedIcons[i]
            if ic and ic._ddIsManaged then
                ic:Hide()
            end
        end
    end)
    frame:HookScript("OnShow", function(self)
        for i = 1, (self._iconCount or 0) do
            local ic = self._managedIcons[i]
            -- [FIX] _ddingHidden 아이콘은 Show하지 않음 (BuffTrackerBar 추적 중)
            if ic and ic._ddIsManaged and GroupRenderer:CanShowManagedIcon(ic) then
                ic:Show()
            end
        end
    end)

    self.groupFrames[groupName] = frame
    return frame
end

-- ============================================================
-- 그룹 업데이트 (CDM 아이콘 SetParent)
-- [REPARENT] 뷰어 설정 100% 반영 — iconSize, spacing, direction, border 등 전부
-- ============================================================

function GroupRenderer:UpdateGroup(groupName, iconList, groupSettings)
    local frame = self.groupFrames[groupName]
    if not frame then
        frame = self:CreateGroupFrame(groupName, groupSettings)
    end


    if not groupSettings.enabled then
        self:ReleaseGroupIcons(frame)
        -- [FIX] named 프레임 전투 중 Hide 보호
        if not frame:IsShown() then return end  -- 이미 숨김
        if InCombatLockdown() and frame:GetName() then
            frame._pendingCombatHide = true
        else
            frame:Hide()
        end
        return
    end

    -- [FIX] groupType에 상관없이 sourceGroupKey가 있으면 동적 아이콘을 병합하여 하이브리드(CDM+Dynamic) 지원
    local dynamicIcons = {}
    local bridge = DDingUI.DynamicIconBridge
    if bridge and groupSettings.sourceGroupKey then
        dynamicIcons = bridge:GetActiveIconsForGroup(groupSettings.sourceGroupKey, groupSettings) or {}
    end
    local ci = DDingUI.CustomIcons
    if ci and ci.GetActiveCustomTimedAuraEntriesForCDMGroup then
        local timedEntries = ci:GetActiveCustomTimedAuraEntriesForCDMGroup(groupName, groupSettings)
        if timedEntries then
            local seenDynamic = {}
            for _, entry in ipairs(dynamicIcons) do
                if entry and entry.iconKey then
                    seenDynamic[entry.iconKey] = true
                end
            end
            for _, entry in ipairs(timedEntries) do
                if entry and entry.iconKey and not seenDynamic[entry.iconKey] then
                    dynamicIcons[#dynamicIcons + 1] = entry
                    seenDynamic[entry.iconKey] = true
                end
            end
        end
    end
    dynamicIcons = FilterGroupedBuffDynamicEntries(dynamicIcons, iconList, groupName, groupSettings)
    local hasDynamicIcons = false

    -- 기존 managed 아이콘 중 이번 리스트에 없는 것만 release
    local newSet = {}
    local combinedList = {}
    local activeCDMTokens = {}

    -- CDM icons stay in their source group; dynamic icons are additions.
    -- 1. CDM icons
    for _, entry in ipairs(iconList) do
        local placement = BuildCDMPlacement(entry)
        if placement then
            newSet[placement.icon] = true
            combinedList[#combinedList + 1] = placement
            if placement._ddOrderToken then
                activeCDMTokens[placement._ddOrderToken] = true
            end
        end
    end

    local placeholders = DDingUI.BuffGroupPlaceholders
    if placeholders then
        local placeholderEntries = placeholders:BuildPlacements(groupName, groupSettings, activeCDMTokens)
        for _, placement in ipairs(placeholderEntries or {}) do
            newSet[placement.icon] = true
            combinedList[#combinedList + 1] = placement
        end
    end

    -- 2. Dynamic icons
    for _, entry in ipairs(dynamicIcons) do
        local placement = BuildDynamicPlacement(entry)
        if placement then
            hasDynamicIcons = true
            newSet[placement.icon] = true
            combinedList[#combinedList + 1] = placement
        end
    end

    local inCombat = InCombatLockdown and InCombatLockdown()
    local fc = GetFC()
    local scanHolding = fc and fc.IsScanHoldActive and fc:IsScanHoldActive()
    frame._ddDeferredReleaseIcons = frame._ddDeferredReleaseIcons or {}
    if inCombat and frame._managedIcons then
        for _, icon in pairs(frame._managedIcons) do
            if icon and icon._ddIconKey and not newSet[icon] and ShouldKeepDynamicIconInCombat(icon) then
                newSet[icon] = true
                combinedList[#combinedList + 1] = {
                    isDynamic = true,
                    icon = icon,
                    iconKey = icon._ddIconKey,
                    cooldownID = icon._ddIconKey,
                    active = false,
                    combatKeepAlive = true,
                    combatVisible = true,
                    _ddOrderToken = BuildDynamicOrderToken(icon._ddIconKey),
                }
                hasDynamicIcons = true
            end
        end
    end
    if scanHolding and frame._managedIcons then
        for _, icon in pairs(frame._managedIcons) do
            if icon and not icon._ddIconKey and icon._ddIsManaged and not newSet[icon] then
                local cooldownID = icon._ddLastCooldownID or icon.cooldownID
                local spellName
                if fc and fc.GetSpellNameForID and cooldownID then
                    pcall(function()
                        spellName = fc:GetSpellNameForID(cooldownID)
                    end)
                end
                local placement = {
                    isCDM = true,
                    icon = icon,
                    cooldownID = cooldownID,
                    spellName = spellName,
                    cdmKeepAlive = true,
                    sourceVisible = not GroupRenderer:IsHiddenSourceBuffIcon(icon),
                }
                placement._ddOrderToken = BuildCDMOrderToken(placement)
                newSet[icon] = true
                combinedList[#combinedList + 1] = placement
            end
        end
    end
    if not inCombat and frame._ddDeferredReleaseIcons then
        for iconKey, icon in pairs(frame._ddDeferredReleaseIcons) do
            if icon and not newSet[icon] then
                local releaseBridge = DDingUI.DynamicIconBridge
                if releaseBridge then
                    releaseBridge:ReleaseFrame(icon, iconKey)
                end
            end
            frame._ddDeferredReleaseIcons[iconKey] = nil
        end
    end

    ApplyGroupIconOrder(groupSettings, combinedList)
    local combinedHash = BuildPlacementHash(combinedList, groupSettings)
    local needsFreshLayout = ListRequiresFreshLayout(combinedList, frame, combinedHash)
    if inCombat and frame._lastCombinedLayoutHash == combinedHash and not GroupRenderer._forceFullSetup and not needsFreshLayout then
        RestoreActivePlacements(combinedList, groupName, groupSettings, groupSettings.groupAlpha or 1)
        if #combinedList > 0 and not frame:IsShown() then
            frame:Show()
        end
        return
    end
    frame._lastCombinedLayoutHash = combinedHash

    for _, icon in pairs(frame._managedIcons) do
        if icon and not newSet[icon] and icon._ddContainerRef == frame then
            SetManagedIconLayoutVisible(icon, false)
            SetDynamicIconInactiveGray(icon, false)
            GRLog("cleanup:", tostring(icon.cooldownID), "dyn=" .. tostring(icon._ddIconKey ~= nil), "shown=" .. tostring(icon:IsShown()), "alpha=" .. string.format("%.2f", icon:GetAlpha()))
            if icon._ddIsPlaceholder then
                if placeholders then placeholders:DeactivateFrame(icon) end
            elseif icon._ddIconKey then
                -- 동적 아이콘: DDingUI가 소유 → 직접 Hide + Release
                if inCombat then
                    frame._ddDeferredReleaseIcons[icon._ddIconKey] = icon
                    local iconData = GetDynamicIconData(icon._ddIconKey)
                    local isExpiredAura = iconData and iconData.type == "aura"
                    icon._ddCombatKeepAlive = isExpiredAura and nil or true
                    icon._ddCombatVisible = false
                    if isExpiredAura then
                        HideDynamicIconBorderLayers(icon)
                        if icon.SetAlpha then
                            pcall(icon.SetAlpha, icon, 0)
                            icon._ddLastGroupAlpha = 0
                        end
                        if icon.Hide then icon:Hide() end
                    elseif icon.Show then
                        icon:Show()
                    end
                    if not isExpiredAura then
                        SetAlphaIfNeeded(icon, 0, "_ddLastGroupAlpha")
                    end
                else
                    icon:Hide()
                    local bridge = DDingUI.DynamicIconBridge
                    if bridge then bridge:ReleaseFrame(icon, icon._ddIconKey) end
                end
            elseif inCombat then
                ResetIconLayoutState(icon, false)
                if icon.SetAlpha then
                    pcall(icon.SetAlpha, icon, 0)
                    icon._ddLastGroupAlpha = 0
                end
                if icon.Hide then
                    pcall(icon.Hide, icon)
                end
            elseif fc then
                icon._ddLayoutVisible = nil
                fc:ReleaseFrameFromContainer(icon)
            end
            -- CDM icons that leave this group are released outside combat.
        end
    end
    wipe(frame._managedIcons)

    -- [FIX] groupSettings가 단일 소스 — Config UI가 gs.groups[name]에 기록
    local viewerName = GROUP_VIEWER_MAP[groupName]

    -- 아이콘 크기: groupSettings에서 직접 계산 (viewer settings 무시)
    local baseIconW, baseIconH = ComputeIconDimensions(groupSettings)

    -- [FIX] groupSettings를 프레임에 캐시 (OnHide relayout에서 사용)
    frame._groupSettings = groupSettings

    -- [REPARENT] 스키닝용 프로필 참조 (미리 resolve)
    local IconViewers = DDingUI.IconViewers
    local profile = DDingUI.db and DDingUI.db.profile
    local viewers = profile and profile.viewers

    -- [REPARENT] 1단계: SetupFrameInContainer + SkinIcon (텍스처/테두리/글로우)
    -- SkinIcon이 LayoutGroup보다 먼저 실행 → LayoutGroup이 최종 크기 결정 (rowIconSizes 보존)
    -- [FIX] groupSettings 기반 SkinIcon 설정 — 텍스트/테두리/글로우 모두 groupSettings에서 읽음
    -- CDM 그룹: CopyVO가 viewer→gs.groups로 복사하므로 groupSettings에 텍스트 키 존재
    -- 커스텀 그룹: BuildCustomTextArgs/GS_Range가 gs.groups에 직접 기록
    local skinSettingsForGroup = groupSettings

    local idx = 0
    for i, entry in ipairs(combinedList) do
        local icon = entry.icon

        if icon then
            local sourceVisible = entry.sourceVisible ~= false and not GroupRenderer:IsHiddenSourceBuffIcon(icon)
            if entry.isPlaceholder then
                icon:SetParent(UIParent)
                icon._ddContainerRef = frame
                icon._ddIsManaged = true
                icon._ddLayoutVisible = true
                icon:SetScale(1)
                icon:SetSize(baseIconW, baseIconH)
                local placeholderBridge = DDingUI.DynamicIconBridge
                if placeholderBridge and placeholderBridge.ApplyTexCoordCrop then
                    placeholderBridge.ApplyTexCoordCrop(icon.icon, groupSettings.zoom or 0.08, groupSettings.aspectRatioCrop or 1.0)
                end
                if placeholders then
                    placeholders:ApplyStyle(icon, groupSettings)
                end
                SetDynamicIconInactiveGray(icon, true)
                SetAlphaIfNeeded(icon, groupSettings.groupAlpha or 1, "_ddLastGroupAlpha")
                idx = idx + 1
                frame._managedIcons[idx] = icon
                icon:Show()
            elseif entry.isDynamic then
                if frame._ddDeferredReleaseIcons then
                    frame._ddDeferredReleaseIcons[entry.iconKey or entry.cooldownID] = nil
                end
                -- [동적 아이콘 스키닝] — 그룹 통일 크기 사용 (baseIconW/baseIconH)
                local bridge = DDingUI.DynamicIconBridge
                if bridge then
                    TagDynamicIconForGroup(icon, groupName, groupSettings)
                    icon._ddCombatKeepAlive = entry.combatKeepAlive and true or nil
                    icon._ddCombatVisible = entry.combatVisible ~= false
                    icon._ddInactiveGray = entry.inactiveGray and true or nil
                    SetDynamicIconInactiveGray(icon, entry.inactiveGray == true)
                    if entry.inactiveGray then
                        icon._ddManagedAuraExpired = nil
                    end
                    SetManagedIconLayoutVisible(icon, entry.inactiveGray or (entry.combatVisible ~= false and not icon._ddManagedAuraExpired))
                    local alreadyManaged = icon._ddIsManaged and icon._ddContainerRef == frame and not GroupRenderer._forceFullSetup
                    if not alreadyManaged then
                        bridge:SetupFrameInContainer(icon, frame, baseIconW, baseIconH, entry.cooldownID, groupSettings.zoom, groupSettings.aspectRatioCrop)
                        -- [FIX] CustomIcons 자체 .border 프레임 숨기기 (GroupRenderer _ddBorders와 이중 표시 방지)
                        if icon.border then icon.border:Hide() end
                    elseif icon.icon then
                        -- [FIX] 이미 managed 아이콘도 zoom + 종횡비 크롭 갱신
                        bridge.ApplyTexCoordCrop(icon.icon, groupSettings.zoom or 0.08, groupSettings.aspectRatioCrop or 1.0)
                    end
                    -- [FIX] 동적 아이콘 테두리 적용 (SkinIcon은 CDM 전용이라 사용 불가 — 텍스처 파괴)
                    -- groupSettings에서 borderSize/borderColor만 적용
                    local edgeSize = tonumber(groupSettings.borderSize) or 1
                    if DDingUI and DDingUI.ScaleBorder then
                        edgeSize = DDingUI:ScaleBorder(edgeSize)
                    else
                        edgeSize = math.floor(edgeSize + 0.5)
                    end
                    local iconTexture = icon.icon or icon.Icon
                    if iconTexture then
                        icon._ddBorders = icon._ddBorders or {}
                        local borders = icon._ddBorders
                        if #borders == 0 then
                            local function CreateBorderLine()
                                return icon:CreateTexture(nil, "OVERLAY")
                            end
                            local top = CreateBorderLine()
                            top:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 0, 0)
                            top:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 0, 0)
                            local bottom = CreateBorderLine()
                            bottom:SetPoint("BOTTOMLEFT", iconTexture, "BOTTOMLEFT", 0, 0)
                            bottom:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 0, 0)
                            local left = CreateBorderLine()
                            left:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 0, 0)
                            left:SetPoint("BOTTOMLEFT", iconTexture, "BOTTOMLEFT", 0, 0)
                            local right = CreateBorderLine()
                            right:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 0, 0)
                            right:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 0, 0)
                            icon._ddBorders = { top, bottom, left, right }
                            borders = icon._ddBorders
                        end
                        if #borders >= 4 then
                            local bc = groupSettings.borderColor or { 0, 0, 0, 1 }
                            local br, bg, bb, ba = bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1
                            local shouldShow = edgeSize > 0 and (entry.inactiveGray or not icon._ddManagedAuraExpired) and entry.combatVisible ~= false
                            borders[1]:SetHeight(edgeSize); borders[2]:SetHeight(edgeSize)
                            borders[3]:SetWidth(edgeSize); borders[4]:SetWidth(edgeSize)
                            for _, borderTex in ipairs(borders) do
                                borderTex:SetColorTexture(br, bg, bb, ba)
                                borderTex:SetShown(shouldShow)
                            end
                        end
                    end

                    -- [FIX] 동적 아이콘 텍스트 파라미터 적용 (SkinIcon 우회)
                    -- count (스택/충전) 텍스트
                    if icon.count then
                        local countAnchor = groupSettings.chargeTextAnchor or "BOTTOMRIGHT"
                        if countAnchor == "MIDDLE" then countAnchor = "CENTER" end
                        local cox = tonumber(groupSettings.countTextOffsetX) or 0
                        local coy = tonumber(groupSettings.countTextOffsetY) or 0
                        icon.count:ClearAllPoints()
                        icon.count:SetPoint(countAnchor, iconTexture or icon, countAnchor, cox, coy)

                        local cSize = tonumber(groupSettings.countTextSize)
                        if cSize and cSize > 0 then
                            local cFont = DDingUI:GetFont(groupSettings.countTextFont)
                            icon.count:SetFont(cFont, cSize, "OUTLINE")
                        end

                        local ctc = groupSettings.countTextColor
                        if type(ctc) == "table" then
                            local cr, cg, cb, ca = 1, 1, 1, 1
                            if ctc.GetRGBA then cr, cg, cb, ca = ctc:GetRGBA()
                            elseif ctc[1] then cr, cg, cb, ca = ctc[1], ctc[2], ctc[3], ctc[4] or 1
                            elseif ctc.r then cr, cg, cb, ca = ctc.r, ctc.g, ctc.b, ctc.a or 1 end
                            icon.count:SetTextColor(cr, cg, cb, ca)
                        end
                    end

                    -- duration (지속시간) 텍스트
                    if icon.cooldown then
                        local cdAnchor, doxRaw, doyRaw, textSizeRaw, textFont, textColor = ResolveCooldownTextStyle(groupName, groupSettings)
                        local dox = tonumber(doxRaw) or 0
                        local doy = tonumber(doyRaw) or 0
                        if cdAnchor == "MIDDLE" then cdAnchor = "CENTER" end

                        if groupSettings.hideDurationText then
                            if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(true) end
                            icon.cooldown.noCooldownCount = true
                        else
                            if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(false) end
                            icon.cooldown.noCooldownCount = nil
                        end

                        local cdTextFS = GetCooldownTextFontString(icon.cooldown)

                        if cdTextFS then
                            if groupSettings.hideDurationText then
                                cdTextFS:Hide()
                                if not cdTextFS.hookedHideText then
                                    cdTextFS.hookedHideText = true
                                    hooksecurefunc(cdTextFS, "Show", function(self)
                                        local cd = self:GetParent()
                                        if cd and cd.noCooldownCount then self:Hide() end
                                    end)
                                end
                            else
                                cdTextFS:Show()
                                if cdAnchor then
                                    cdTextFS:ClearAllPoints()
                                    cdTextFS:SetPoint(cdAnchor, icon.cooldown, cdAnchor, dox, doy)
                                end
                                local dSize = tonumber(textSizeRaw)
                                if dSize and dSize > 0 then
                                    local dFont = DDingUI:GetFont(textFont)
                                    cdTextFS:SetFont(dFont, dSize, "OUTLINE")
                                end
                                local dtc = textColor
                                if type(dtc) == "table" then
                                    local dr, dg, db, da = 1, 1, 1, 1
                                    if dtc.GetRGBA then dr, dg, db, da = dtc:GetRGBA()
                                    elseif dtc[1] then dr, dg, db, da = dtc[1], dtc[2], dtc[3], dtc[4] or 1
                                    elseif dtc.r then dr, dg, db, da = dtc.r, dtc.g, dtc.b, dtc.a or 1 end
                                    cdTextFS:SetTextColor(dr, dg, db, da)
                                end
                            end
                        end
                    end

                    ApplyDynamicIconTextOptions(icon, groupName, groupSettings)

                    idx = idx + 1
                    frame._managedIcons[idx] = icon
                    -- CDM 기본 그룹이 아직 숨겨진 상태여도 동적 아이콘은 레이아웃 대상에 포함되어야 한다.
                    icon:Show()
                end
            elseif fc then
                -- [CDM 아이콘 스키닝]
                SetDynamicIconInactiveGray(icon, entry.inactiveGray == true)
                local alreadyManaged = icon._ddIsManaged and icon._ddContainerRef == frame
                    and icon._ddLayoutCooldownID == entry.cooldownID
                    and not GroupRenderer._forceFullSetup
                if not alreadyManaged then
                    GRLog("SetupFrame:", tostring(entry.cooldownID), "shown=" .. tostring(icon:IsShown()), "alpha=" .. string.format("%.2f", icon:GetAlpha()))
                    fc:SetupFrameInContainer(icon, frame, baseIconW, baseIconH, entry.cooldownID)

                    if IconViewers and IconViewers.SkinIcon and entry.cooldownID then
                        local srcViewer = fc:GetIconSource(entry.cooldownID)
                        if srcViewer then
                            icon._ddSourceViewer = srcViewer
                        end
                        pcall(IconViewers.SkinIcon, IconViewers, icon, skinSettingsForGroup)
                    end
                else
                    icon._ddLastCooldownID = entry.cooldownID
                    icon._ddLayoutCooldownID = entry.cooldownID
                end
                SetManagedIconLayoutVisible(icon, sourceVisible and not icon._ddSuppressed and not icon._ddingHidden)
                idx = idx + 1
                frame._managedIcons[idx] = icon
                if not sourceVisible then
                    GroupRenderer:HideHiddenSourceBuffIcon(icon)
                end
            end

            -- [FIX] 동적 그룹 아이콘 등 새로 할당된 아이콘 가시성 복구
            -- 컨테이너가 이미 보이는 상태에서 아이콘이 추가되면 OnShow가 안 타므로 직접 Show
            if frame:IsShown() and sourceVisible and not icon._ddSuppressed and not icon._ddingHidden then
                if not icon:IsShown() then
                    if not (scanHolding and not icon._ddIconKey) then
                        icon:Show()
                    end
                end
            end

            -- [FIX] OnHide 디바운스 재배치: 여러 아이콘 hide를 0.05초 내 한 번에 처리
            -- 즉시 호출 시 매 아이콘 hide마다 전체 ClearAllPoints → 깜빡임/겹침 유발
            if not icon._ddLayoutHooked then
                icon._ddLayoutHooked = true
                icon:HookScript("OnHide", function(self)
                    if not self._ddIsManaged then return end
                    -- [REPARENT] _ddContainerRef 사용 (parent는 UIParent)
                    local p = self._ddContainerRef
                    if not (p and p._isDDContainer and p._groupName) then return end
                    local gn = p._groupName
                    if not gn then return end

                    -- 디바운스: 0.03초 후 한 번만 레이아웃
                    if not p._ddLayoutPending then
                        p._ddLayoutPending = true
                        C_Timer.After(0.03, function()
                            p._ddLayoutPending = nil
                            if not (p and p._isDDContainer) then return end
                            if InCombatLockdown() then return end -- [FIX] 전투 중 SetSize 보호

                            -- [FIX] 캐시된 groupSettings 사용 (viewer settings 대신)
                            local cachedGS = p._groupSettings
                            if cachedGS then
                                local vn2 = GROUP_VIEWER_MAP[gn]
                                local ls = {
                                    iconSize = cachedGS.iconSize or 32,
                                    aspectRatioCrop = cachedGS.aspectRatioCrop or 1.0,
                                    spacing = cachedGS.spacing or 2,
                                    primaryDirection = cachedGS.direction or "RIGHT",
                                    secondaryDirection = cachedGS.growDirection,
                                    rowLimit = cachedGS.rowLimit or 0,
                                    rowIconSizes = cachedGS.rowIconSizes,
                                    groupCategory = cachedGS.groupCategory,
                                    iconMotion = cachedGS.iconMotion,
                                    iconMotionDuration = cachedGS.iconMotionDuration,
                                }
                                GroupRenderer:LayoutGroup(p, ls, vn2)
                            end
                            -- 모든 아이콘이 숨겨졌으면 그룹 프레임도 숨기기
                            local anyVis = false
                            for i = 1, (p._iconCount or 0) do
                                local ic = p._managedIcons[i]
                                if ic and ic:IsShown() then anyVis = true; break end
                            end
                            local holdHiddenCDM = false
                            local holdFC = GetFC()
                            if holdFC and holdFC.IsScanHoldActive and holdFC:IsScanHoldActive() then
                                holdHiddenCDM = true
                            end
                            if not anyVis and not holdHiddenCDM then
                                p:Hide()
                                if DDingUI.ContainerSync then
                                    DDingUI.ContainerSync:SyncAll()
                                end
                            end
                        end)
                    end
                end)
            end
        end
    end
    frame._iconCount = idx

    -- [FIX] groupSettings → LayoutGroup 형식 변환 (모든 그룹 통일)
    -- Config UI가 gs.groups[name]에 기록한 값을 직접 사용
    -- [FIX] groupOffsets: ViewerOptions SaveGroupOffset은 viewers[viewerKey]에 저장하므로
    -- 실시간 반영을 위해 viewers DB를 직접 읽음. 비-CDM 그룹은 groupSettings에서 읽음.
    local resolvedGroupOffsets = groupSettings.groupOffsets
    if viewerName then
        local profile = DDingUI.db and DDingUI.db.profile
        local vs = profile and profile.viewers and profile.viewers[viewerName]
        if vs and vs.groupOffsets then
            resolvedGroupOffsets = vs.groupOffsets
        end
    end
    local layoutSettings = {
        iconSize = groupSettings.iconSize or 32,
        aspectRatioCrop = groupSettings.aspectRatioCrop or 1.0,
        spacing = groupSettings.spacing or 2,
        primaryDirection = groupSettings.direction or "RIGHT",
        secondaryDirection = groupSettings.growDirection,
        rowLimit = groupSettings.rowLimit or 0,
        rowIconSizes = groupSettings.rowIconSizes,
        groupOffsets = resolvedGroupOffsets,
        groupCategory = groupSettings.groupCategory,
        iconMotion = groupSettings.iconMotion,
        iconMotionDuration = groupSettings.iconMotionDuration,
    }

    -- 2단계: LayoutGroup (최종 크기/위치 결정 — rowIconSizes 반영)
    self:LayoutGroup(frame, layoutSettings, viewerName)

    if idx > 0 then
        -- [FIX] CDM 뷰어의 IsShown() 반영 (전투 외 버프 숨김 등)
        -- ContainerSync는 alpha=0만 설정 → CDM의 Show/Hide는 그대로 유지
        -- 뷰어가 CDM에 의해 숨겨진 상태면 CDM 아이콘만 숨김.
        -- 물약/장신구 같은 동적 아이콘이 있으면 기본 CDM 그룹에서도 독립적으로 표시한다.
        local sourceViewer = viewerName and _G[viewerName]
        local sourceViewerHidden = sourceViewer and not sourceViewer:IsShown()
        local preserveCombatVisibility = sourceViewerHidden and InCombatLockdown()
        if sourceViewerHidden and not preserveCombatVisibility and not hasDynamicIcons then
            -- [FIX] 프레임 자체는 숨기지 않음 — 앵커 체인 보존
            for i = 1, idx do
                local ic = frame._managedIcons[i]
                if ic then ic:Hide() end
            end
        else
            if sourceViewerHidden and not preserveCombatVisibility and hasDynamicIcons then
                for i = 1, idx do
                    local ic = frame._managedIcons[i]
                    if ic then
                        if ic._ddIconKey then
                            ic:Show()
                        else
                            ic:Hide()
                        end
                    end
                end
            end
            -- [FIX] 이미 보이면 Skip (전투 중 불필요한 Show 방지)
            if not frame:IsShown() then
                if InCombatLockdown() and frame:GetName() then
                    frame._pendingCombatShow = true
                else
                    frame:Show()
                end
            end
        end
    else
        -- [FIX] 아이콘 0개여도 프레임을 숨기지 않음
        -- 숨기면 이 그룹에 앵커된 프레임들의 앵커가 끊어져 엘레베이터 현상 발생
        -- 프레임은 비어있지만 :IsShown()=true 유지 → 앵커 체인 보존
        -- [FIX] 이미 보이면 Skip
        if not frame:IsShown() then
            if InCombatLockdown() and frame:GetName() then
                frame._pendingCombatShow = true
            else
                frame:Show()
            end
        end
    end

    -- [12.0.1] 그룹 아이콘 투명도 적용
    -- [FIX] FlightHide 활성 또는 페이드 중이면 alpha=0 유지 (Reconcile이 덮어쓰는 것 방지)
    local fh = DDingUI.FlightHide
    local flightHiding = fh and (fh.isActive or fh._hiding)
    local groupAlpha = flightHiding and 0 or (groupSettings.groupAlpha or 1.0)

    -- [FIX CDM] 컨테이너 프레임 alpha: 변경 시에만 SetAlpha (매 틱 호출 방지)
    SetAlphaIfNeeded(frame, groupAlpha, "_ddLastFrameAlpha")

    for i = 1, idx do
        local ic = frame._managedIcons[i]
        if ic then
            -- [FIX] BuffTrackerBar가 _ddingHidden으로 숨긴 아이콘은 alpha 유지 (깜빡임 방지)
            -- [FIX CDM] alpha 실제 변경 시에만 SetAlpha → CooldownFrame 재렌더 방지
            -- 스와이프·아이콘색상 동시 깜빡임의 근본 원인 차단
            if not ic._ddingHidden then
                local iconAlpha = groupAlpha
                if ic._ddIconKey and ic._ddCombatKeepAlive and ic._ddCombatVisible == false then
                    iconAlpha = 0
                elseif GroupRenderer:IsHiddenSourceBuffIcon(ic) then
                    iconAlpha = 0
                end
                SetAlphaIfNeeded(ic, iconAlpha, "_ddLastGroupAlpha")
                if ic._ddInactiveGray and iconAlpha > 0 then
                    SetDynamicIconInactiveGray(ic, true)
                elseif iconAlpha > 0 then
                    SetDynamicIconInactiveGray(ic, false)
                    RestoreIconTextureOpacity(ic)
                end
            end
        end
    end
end

-- ============================================================
-- 레이아웃 엔진
-- [REPARENT] ViewerLayout과 동일 — 뷰어 설정의 direction, spacing,
-- rowLimit, rowIconSizes, iconSize, aspectRatioCrop 전부 반영
-- CENTER 앵커 기반 + snap-back 타겟 자동 설정
-- ============================================================

function GroupRenderer:LayoutGroup(frame, viewerSettings, viewerName)
    if not frame or not frame._managedIcons then return end
    local layoutHash = frame._lastCombinedLayoutHash or frame._lastDynHash

    -- 뷰어 전환 중 추가된 아이콘도 숨김 상태에서 슬롯과 목표 좌표를 계산한다.
    -- 표시 여부와 레이아웃 계산을 분리해야 새 아이콘이 초기 CENTER 좌표에 남지 않는다.
    if frame._viewerHidden then
        local actualViewer = viewerName and _G[viewerName]
        if actualViewer and actualViewer:IsShown() then
            -- 뷰어가 실제로 보이는데 플래그가 true → 고착 상태 → 해제
            frame._viewerHidden = false
        end
    end

    -- [REPARENT] 보이는 아이콘만 레이아웃에 포함 (belt-and-suspenders)
    -- CDM이 Hide()한 아이콘이 _managedIcons에 남아있으면 빈 공간("이 빠짐") 발생
    -- [FIX] _ddingHidden 아이콘도 제외: BuffTrackerBar가 추적 중인 버프를 CDM에서
    -- 완전히 빼서 정렬 공백 없이 나머지 아이콘이 올바르게 배치되도록 함
    local allIcons = frame._managedIcons
    local icons = {}
    local count = 0
    for i = 1, (frame._iconCount or 0) do
        local icon = allIcons[i]
        if ShouldLayoutManagedIcon(icon) then
            count = count + 1
            icons[count] = icon
        end
    end
    -- [FIX] 가상 최소 크기 계산 (핵심 3대 그룹만: Cooldowns, Buffs, Utility)
    -- 다이나믹 그룹은 다른 모듈이 앵커되지 않으므로 phantom 불필요
    local phantomW, phantomH = 1, 1
    local phantomPrimary, phantomSecondary, phantomLayoutType
    local isCoreGroup = (viewerName == "BuffIconCooldownViewer")  -- 강화효과만 phantom 적용
    if isCoreGroup and viewerSettings then
        local phantomIconW, phantomIconH = ComputeIconDimensions(viewerSettings)
        local phantomSpacing = ComputeSpacing(viewerSettings)
        local phantomRowLimit = viewerSettings.rowLimit or 0
        if phantomRowLimit <= 0 then phantomRowLimit = 9 end
        local phantomRows = (viewerName == "BuffIconCooldownViewer") and 1 or 2
        -- [FIX] ResolveDirections는 rowLimit=0이면 secondary를 nil로 버림
        -- phantom은 2줄 기준이므로, rowLimit을 강제로 2로 설정하여 유저의 secondary 설정을 보존
        local phantomResolveSettings = {}
        for k, v in pairs(viewerSettings) do phantomResolveSettings[k] = v end
        phantomResolveSettings.rowLimit = 2
        phantomPrimary, phantomSecondary, _, phantomLayoutType = ResolveDirections(viewerName, phantomResolveSettings)
        if phantomLayoutType == "VERTICAL" then
            phantomW = phantomRows * phantomIconW + (phantomRows - 1) * phantomSpacing
            phantomH = phantomRowLimit * phantomIconH + (phantomRowLimit - 1) * phantomSpacing
        else
            phantomW = phantomRowLimit * phantomIconW + (phantomRowLimit - 1) * phantomSpacing
            phantomH = phantomRows * phantomIconH + (phantomRows - 1) * phantomSpacing
        end
        phantomW = math_max(PixelSnap(phantomW), 1)
        phantomH = math_max(PixelSnap(phantomH), 1)
    end

    if count == 0 then
        if frame._lastLayoutW and frame._lastLayoutW > phantomW then
            phantomW = frame._lastLayoutW
        end
        if frame._lastLayoutH and frame._lastLayoutH > phantomH then
            phantomH = frame._lastLayoutH
        end
        if InCombatLockdown() and frame:GetName() then
            frame._pendingLayoutSize = { phantomW, phantomH }
        else
            frame:SetSize(phantomW, phantomH)
        end
        frame._lastLayoutW = phantomW
        frame._lastLayoutH = phantomH
        frame.__cdmIconWidth = phantomW
        return
    end

    -- 뷰어 설정이 없으면 최소 fallback (UpdateGroup에서 이미 처리하지만 안전)
    if not viewerSettings then
        viewerSettings = { iconSize = 32, spacing = 2, primaryDirection = "CENTERED_HORIZONTAL" }
    end

    local motionSettings
    local isBuffMotionGroup = (viewerName == "BuffIconCooldownViewer") or (viewerSettings.groupCategory == "buff")
    if isBuffMotionGroup then
        motionSettings = {
            pinWrappedRowsToAnchor = true,
        }
        if viewerSettings.iconMotion ~= false then
            motionSettings.enabled = true
            motionSettings.duration = tonumber(viewerSettings.iconMotionDuration) or ICON_MOTION_DEFAULT_DURATION
        end
    end

    -- ViewerLayout과 동일하게 방향/행제한 resolve
    local primary, secondary, rowLimit, layoutType = ResolveDirections(viewerName, viewerSettings)

    -- [12.0.1] rowLimit 오버라이드 제거: 뷰어 설정의 rowLimit을 그대로 사용
    -- 기본값 0(=단일행)이므로, 유저가 명시적으로 설정한 값(예: 9)이 존중됨

    local spacing = ComputeSpacing(viewerSettings)

    -- 행/열별 아이콘 크기 (rowIconSizes 지원)
    local rowDimensions = {}
    local function GetDimensionsForRow(rowIndex)
        if not rowDimensions[rowIndex] then
            local overrideSize = GetRowIconSize(viewerSettings, rowIndex)
            local w, h = ComputeIconDimensions(viewerSettings, overrideSize)
            rowDimensions[rowIndex] = { width = w, height = h }
        end
        return rowDimensions[rowIndex].width, rowDimensions[rowIndex].height
    end

    -- 레이아웃 실행
    local totalW, totalH = 0, 0
    if layoutType == "HORIZONTAL" then
        totalW, totalH = LayoutHorizontal(icons, frame, primary, secondary, spacing, rowLimit, GetDimensionsForRow, motionSettings)
    elseif layoutType == "VERTICAL" then
        totalW, totalH = LayoutVertical(icons, frame, primary, secondary, spacing, rowLimit, GetDimensionsForRow, motionSettings)
    else
        -- STATIC: 크기만 설정, 위치는 그대로
        local iconW, iconH = GetDimensionsForRow(1)
        for i, icon in ipairs(icons) do
            SetIconSize(icon, iconW, iconH)
        end
        totalW = iconW
        totalH = iconH
    end

    -- 컨테이너 크기 설정
    if layoutHash then
        for i = 1, count do
            local icon = icons[i]
            if icon then
                icon._ddLastGroupLayoutHash = layoutHash
            end
        end
    end

    local snappedW = math_max(PixelSnap(totalW), 1)
    local snappedH = math_max(PixelSnap(totalH), 1)

    -- [FIX] 가상 최소 크기 적용: 아이콘이 있어도 프레임이 phantom 미만으로 줄어들지 않음
    local finalW = math_max(snappedW, phantomW)
    local finalH = math_max(snappedH, phantomH)

    -- [FIX] 가상 크기가 실제보다 클 때, 아이콘을 방향 설정에 맞게 정렬 (세로 중앙 X)
    -- DOWN → 아이콘을 프레임 상단에 정렬, UP → 하단에 정렬
    if finalH > snappedH then
        local resolvedSecondary = secondary or phantomSecondary or "DOWN"
        local shiftY = 0
        if resolvedSecondary == "UP" then
            -- 아이콘을 프레임 하단에 정렬 (위로 성장)
            shiftY = -(finalH - snappedH) / 2
        else
            -- DOWN 또는 기본: 아이콘을 프레임 상단에 정렬 (아래로 성장)
            shiftY = (finalH - snappedH) / 2
        end
        if shiftY ~= 0 then
            for i = 1, count do
                local icon = icons[i]
                if icon and icon._ddTargetX and icon._ddTargetY then
                    SetIconPosition(icon, frame, icon._ddTargetX, icon._ddTargetY + math_floor(shiftY + 0.5), motionSettings)
                end
            end
        end
    end

    -- [FIX] attachTo 그룹 너비 동기화: 다른 그룹에 앵커된 경우 부모 그룹 너비에 맞춤
    -- 예: Utility가 Cooldowns에 앵커 → Utility 프레임 너비를 Cooldowns와 동일하게
    local groupName = frame._groupName
    if groupName then
        local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
        local groupSettings = gs and gs.groups and gs.groups[groupName]
        if groupSettings then
            local attachTo = groupSettings.attachTo
            if attachTo and attachTo ~= "UIParent" and attachTo ~= "" then
                local parentFrame = _G[attachTo]
                if parentFrame and parentFrame._isDDContainer then
                    local parentW = parentFrame:GetWidth()
                    if parentW and parentW > 1 and parentW > finalW then
                        finalW = parentW
                    end
                end
            end
        end
    end

    -- [FIX] 전투 중 SetSize 보호 함수 에러 방지
    -- 명명된 프레임(DDingUI_Group_*)은 전투 중 SetSize 불가 → defer
    if InCombatLockdown() and frame:GetName() then
        frame._pendingLayoutSize = { finalW, finalH }
        -- 전투 종료 후 재적용
        if not GroupRenderer._combatDeferFrame then
            GroupRenderer._combatDeferFrame = CreateFrame("Frame")
            GroupRenderer._combatDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            GroupRenderer._combatDeferFrame:SetScript("OnEvent", function()
                for _, gf in pairs(GroupRenderer.groupFrames or {}) do
                    if gf._pendingLayoutSize then
                        local pw, ph = gf._pendingLayoutSize[1], gf._pendingLayoutSize[2]
                        gf:SetSize(pw, ph)
                        gf._pendingLayoutSize = nil
                    end
                end
            end)
        end
    else
        frame:SetSize(finalW, finalH)
    end
    frame._lastLayoutW = finalW  -- [FIX] 엘레베이터 방지: count==0일 때 이 크기 유지
    frame._lastLayoutH = finalH

    -- [FIX] 프록시 앵커 크기 즉시 동기화 (OnUpdate 지연 없이)
    -- 아이콘 크기/간격 변경, 프로필 전환 등 모든 경우에 즉시 반영
    -- [FIX] groupName은 L990에서 이미 선언 — 재선언(shadowing) 제거
    local CORE_PROXY_NAMES = {
        ["Cooldowns"] = "DDingUI_Anchor_Cooldowns",
        ["Buffs"]     = "DDingUI_Anchor_Buffs",
        ["Utility"]   = "DDingUI_Anchor_Utility",
    }
    local proxyName = groupName and CORE_PROXY_NAMES[groupName]
    local proxy = proxyName and _G[proxyName]
    if proxy then
        -- [FIX] Reconcile → LayoutGroup 경로가 tainted 일 수 있음
        -- 전투 중 SetSize 호출 시 ADDON_ACTION_BLOCKED 방지
        if InCombatLockdown() then
            -- 전투 종료 후 지연 동기화
            C_Timer.After(0.5, function()
                if proxy and not InCombatLockdown() then
                    proxy:SetSize(finalW, finalH)
                    proxy.__cdmIconWidth = snappedW
                    proxy._lastSyncW = math.floor(finalW + 0.5)
                    proxy._lastSyncH = math.floor(finalH + 0.5)
                end
            end)
        else
            proxy:SetSize(finalW, finalH)
            proxy.__cdmIconWidth = snappedW
            proxy._lastSyncW = math.floor(finalW + 0.5)
            proxy._lastSyncH = math.floor(finalH + 0.5)
        end
    end

    -- [REPARENT] __cdmIconWidth 동기화 (BuffTrackerBar, ResourceBars 등이 참조)
    frame.__cdmIconWidth = snappedW
    -- [FIX] 원본 뷰어에도 미러링 — 리소스바가 뷰어에서 직접 읽으므로
    local viewerFrame = viewerName and _G[viewerName]
    if viewerFrame then
        viewerFrame.__cdmIconWidth = snappedW
    end

    -- [REPARENT] groupOffsets: 파티/레이드 상태별 아이콘 위치 보정
    -- ViewerLayout.GetGroupOffset 동일 로직
    if viewerSettings.groupOffsets then
        local groupOX, groupOY = 0, 0
        if IsInRaid() then
            local r = viewerSettings.groupOffsets.raid
            groupOX = r and r.x or 0
            groupOY = r and r.y or 0
        elseif IsInGroup() then
            local p = viewerSettings.groupOffsets.party
            groupOX = p and p.x or 0
            groupOY = p and p.y or 0
        end

        if groupOX ~= 0 or groupOY ~= 0 then
            if DDingUI.Scale then
                groupOX = DDingUI:Scale(groupOX)
                groupOY = DDingUI:Scale(groupOY)
            end
            for i = 1, count do
                local icon = icons[i]
                if icon and icon._ddTargetX and icon._ddTargetY then
                    SetIconPosition(icon, frame, icon._ddTargetX + groupOX, icon._ddTargetY + groupOY, motionSettings)
                end
            end
        end
    end
end

-- ============================================================
-- 아이콘 복원 (그룹/전체)
-- [REPARENT] FrameController.ReleaseFrameFromContainer 사용
-- ============================================================

function GroupRenderer:ReleaseGroupIcons(frame)
    if not frame or not frame._managedIcons then return end

    local fc = GetFC()
    local bridge = DDingUI.DynamicIconBridge

    local iconsToHide = {}

    for _, icon in pairs(frame._managedIcons) do
        if icon then
            icon._ddLayoutVisible = nil
            if icon._ddIsPlaceholder then
                local placeholders = DDingUI.BuffGroupPlaceholders
                if placeholders then placeholders:DeactivateFrame(icon) end
            elseif icon._ddIconKey then
                -- [FIX] 동적 아이콘: bridge로 해제 + 숨기기
                if icon.Hide then icon:Hide() end
                iconsToHide[#iconsToHide + 1] = icon
                if bridge then bridge:ReleaseFrame(icon, icon._ddIconKey) end
            else
                -- CDM 아이콘
                if fc then
                    fc:ReleaseFrameFromContainer(icon)
                end
            end
        end
    end

    -- 동적 아이콘은 Release 후 reparent로 Show될 수 있으므로 다시 Hide
    for _, icon in ipairs(iconsToHide) do
        if icon.Hide then icon:Hide() end
    end

    wipe(frame._managedIcons)
    frame._iconCount = 0
    frame._lastCombinedLayoutHash = nil
    frame._lastDynHash = nil
end

function GroupRenderer:RestoreAllIcons()
    for groupName, frame in pairs(self.groupFrames) do
        self:ReleaseGroupIcons(frame)
    end
end

-- ============================================================
-- 정리
-- ============================================================

function GroupRenderer:DestroyAllGroups()
    self:RestoreAllIcons()
    if DDingUI.BuffGroupPlaceholders then
        DDingUI.BuffGroupPlaceholders:ReleaseAll()
    end

    for groupName, frame in pairs(self.groupFrames) do
        frame:Hide()
    end
    wipe(self.groupFrames)

    -- [FIX] 프록시 앵커 크기 캐시 초기화
    -- groupFrame 파괴 후 SyncProxyAnchors가 else 분기에서 작은 크기로 오염되는 것 방지
    -- 새 groupFrame 생성 시 크기가 확실히 반영되도록 캐시 리셋
    if DDingUI.ProxyAnchors then
        for _, proxy in pairs(DDingUI.ProxyAnchors) do
            proxy._lastSyncW = nil
            proxy._lastSyncH = nil
        end
    end
end

function GroupRenderer:DestroyGroup(groupName)
    local frame = self.groupFrames[groupName]
    if not frame then return end
    if DDingUI.BuffGroupPlaceholders then
        DDingUI.BuffGroupPlaceholders:ReleaseGroup(groupName)
    end

    -- [FIX] 동적/CDM 아이콘을 개별적으로 확인하여 모두 안전하게 해제
    self:ReleaseGroupIcons(frame)

    -- [FIX] UnregisterMover로 Mover 프레임까지 완전 정리 (stale mover 방지)
    if DDingUI.Movers then
        local moverName = "DDingUI_Group_" .. groupName
        if DDingUI.Movers.UnregisterMover then
            DDingUI.Movers:UnregisterMover(moverName)
        elseif DDingUI.Movers.CreatedMovers and DDingUI.Movers.CreatedMovers[moverName] then
            DDingUI.Movers.CreatedMovers[moverName] = nil
        end
    end

    frame:Hide()
    self.groupFrames[groupName] = nil
end

-- ============================================================
-- [FIX] CDM 뷰어 Show/Hide → 그룹 프레임 표시 상태 동기화
-- ContainerSync에서 OnShow/OnHide 훅으로 호출됨
-- ============================================================

function GroupRenderer:SyncViewerVisibility(viewerName)
    -- 뷰어 → 그룹 이름 역매핑
    local targetGroup
    for groupName, mappedViewer in pairs(GROUP_VIEWER_MAP) do
        if mappedViewer == viewerName then
            targetGroup = groupName
            break
        end
    end
    if not targetGroup then return end

    local frame = self.groupFrames[targetGroup]
    if not frame then return end

    local viewer = _G[viewerName]
    if not viewer then return end

    if viewer:IsShown() then
        -- CDM이 뷰어를 보여줌 → 뷰어 숨김 플래그 해제 + 아이콘 표시
        local wasHidden = frame._viewerHidden
        frame._viewerHidden = false

        if frame._iconCount and frame._iconCount > 0 then
            frame:Show()
            for i = 1, (frame._iconCount or 0) do
                local ic = frame._managedIcons and frame._managedIcons[i]
                -- [FIX] _ddingHidden 아이콘은 Show하지 않음 (BuffTrackerBar 추적 중)
                if GroupRenderer:CanShowManagedIcon(ic) then ic:Show() end
            end
        end

        -- [FIX] 전문화 변경 후 뷰어가 다시 나타나면 전체 재스캔 + 레이아웃 필요
        -- 이전 전문화의 아이콘이 managed에 남아있으므로 새 아이콘을 다시 가져와야 함
        if wasHidden then
            local fc = DDingUI.FrameController or DDingUI.CDMHookEngine
            if fc and fc.ForceReconcile then
                C_Timer.After(0.1, function()
                    if fc.initialized then
                        fc:ForceReconcile()
                    end
                end)
            end
        end
    else
        -- [FIX] CDM 뷰어 숨김 → 아이콘만 숨기고 프레임 크기는 유지
        -- _viewerHidden 플래그로 LayoutGroup 실행을 차단
        -- → 프레임 크기 보존 → 앵커된 그룹 위치 유지 (엘레베이터 방지)
        frame._viewerHidden = true
        for i = 1, (frame._iconCount or 0) do
            local ic = frame._managedIcons and frame._managedIcons[i]
            if ic then ic:Hide() end
        end
    end
end

-- ============================================================
-- [DYNAMIC] UpdateDynamicGroup: CustomIcons 프레임을 그룹 컨테이너에 배치
-- DynamicIconBridge를 통해 활성 아이콘을 가져와 GroupRenderer 레이아웃 엔진으로 배치
-- ============================================================

function GroupRenderer:UpdateDynamicGroup(groupName, groupSettings, frame)
    if not frame then
        frame = self.groupFrames[groupName]
        if not frame then
            frame = self:CreateGroupFrame(groupName, groupSettings)
        end
    end
    if DDingUI.BuffGroupPlaceholders then
        DDingUI.BuffGroupPlaceholders:ReleaseGroup(groupName)
    end

    if not groupSettings or not groupSettings.enabled then
        self:ReleaseGroupIcons(frame)
        frame:Hide()
        return
    end

    local bridge = DDingUI.DynamicIconBridge
    if not bridge then
        frame:Hide()
        return
    end

    -- [DYNAMIC] sourceGroupKey로 해당 CustomIcons 그룹의 아이콘만 요청
    local sourceKey = groupSettings.sourceGroupKey
    if not sourceKey then
        frame:Hide()
        return
    end
    local activeIcons = bridge:GetActiveIconsForGroup(sourceKey, groupSettings)
    local inCombat = InCombatLockdown and InCombatLockdown()
    local now = GetTime and GetTime() or 0
    if inCombat and frame._managedIcons then
        local existingKeys = {}
        for _, entry in ipairs(activeIcons) do
            if entry.iconKey then
                existingKeys[entry.iconKey] = true
            end
            if entry.frame then
                entry.frame._ddCombatMissingSince = nil
            end
        end
        for _, icon in pairs(frame._managedIcons) do
            local iconKey = icon and icon._ddIconKey
            if iconKey and not existingKeys[iconKey] then
                local iconData = GetDynamicIconData(iconKey)
                local allowMissingGrace = not (iconData and iconData.type == "aura")
                local keepVisible = ShouldKeepDynamicIconInCombat(icon)
                if keepVisible then
                    icon._ddCombatMissingSince = nil
                elseif allowMissingGrace then
                    icon._ddCombatMissingSince = icon._ddCombatMissingSince or now
                    keepVisible = (now - icon._ddCombatMissingSince) <= COMBAT_DYNAMIC_MISSING_GRACE
                else
                    icon._ddCombatMissingSince = nil
                end
                if keepVisible then
                    existingKeys[iconKey] = true
                    activeIcons[#activeIcons + 1] = {
                        iconKey = iconKey,
                        frame = icon,
                        iconData = nil,
                        active = false,
                        combatKeepAlive = true,
                        combatVisible = true,
                    }
                end
            end
        end
    end

    -- [FIX] 아이콘 구성이 변경되지 않았으면 전체 레이아웃 스킵 (0x0 플래시 방지)
    -- 매 틱마다 wipe→재배치→LayoutGroup을 실행하면 중간에 크기가 0x0이 되었다가 복구됨
    -- → 아이콘 추가/제거/전문화 변경 시에만 재실행
    for index, entry in ipairs(activeIcons) do
        if entry then
            entry.isDynamic = true
            entry.sourceIndex = entry.sourceIndex or index
        end
    end
    ApplyGroupIconOrder(groupSettings, activeIcons)

    local newKeyHash = "settings:" .. BuildGroupRenderSettingsHash(groupSettings) .. ";"
    for _, entry in ipairs(activeIcons) do
        local visibleToken = entry.inactiveGray and ":g" or ((inCombat and ":c") or (entry.combatVisible == false and ":0" or ":1"))
        newKeyHash = newKeyHash .. (entry.iconKey or "") .. visibleToken .. ";"
    end
    local hasDeferredRelease = false
    if not inCombat and frame._ddDeferredReleaseIcons then
        for _ in pairs(frame._ddDeferredReleaseIcons) do
            hasDeferredRelease = true
            break
        end
    end
    if frame._lastDynHash and frame._lastDynHash == newKeyHash
       and not GroupRenderer._forceFullSetup
       and not hasDeferredRelease
       and not ListRequiresFreshLayout(activeIcons, frame, newKeyHash) then
        RestoreActiveDynamicEntries(activeIcons, groupName, groupSettings, groupSettings.groupAlpha or 1)
        if #activeIcons > 0 and not frame:IsShown() then
            frame:Show()
        end
        return  -- 아이콘 구성 동일 → 레이아웃 불필요
    end
    frame._lastDynHash = newKeyHash

    -- 기존 managed 아이콘 중 이번 리스트에 없는 것 release
    local newSet = {}
    for _, entry in ipairs(activeIcons) do
        newSet[entry.iconKey] = true
    end
    frame._ddDeferredReleaseIcons = frame._ddDeferredReleaseIcons or {}
    if not inCombat then
        for iconKey, icon in pairs(frame._ddDeferredReleaseIcons) do
            if icon and not newSet[iconKey] then
                bridge:ReleaseFrame(icon, iconKey)
            end
            frame._ddDeferredReleaseIcons[iconKey] = nil
        end
    end
    if frame._managedIcons then
        for _, icon in pairs(frame._managedIcons) do
            if icon and icon._ddIconKey and not newSet[icon._ddIconKey] then
                SetManagedIconLayoutVisible(icon, false)
                if inCombat then
                    frame._ddDeferredReleaseIcons[icon._ddIconKey] = icon
                    local iconData = GetDynamicIconData(icon._ddIconKey)
                    local isExpiredAura = iconData and iconData.type == "aura"
                    icon._ddCombatKeepAlive = isExpiredAura and nil or true
                    icon._ddCombatVisible = false
                    if isExpiredAura then
                        HideDynamicIconBorderLayers(icon)
                        if icon.SetAlpha then
                            pcall(icon.SetAlpha, icon, 0)
                            icon._ddLastGroupAlpha = 0
                        end
                        if icon.Hide then icon:Hide() end
                    elseif icon.Show then
                        icon:Show()
                    end
                    if not isExpiredAura then
                        SetAlphaIfNeeded(icon, 0, "_ddLastGroupAlpha")
                    end
                else
                    bridge:ReleaseFrame(icon, icon._ddIconKey)
                end
            end
        end
    end
    frame._managedIcons = frame._managedIcons or {}
    wipe(frame._managedIcons)

    -- 아이콘 크기 계산
    frame._groupSettings = groupSettings

    local baseIconW, baseIconH = ComputeIconDimensions({
        iconSize = groupSettings.iconSize or 32,
        aspectRatioCrop = groupSettings.aspectRatioCrop or 1.0,
    })

    -- 아이콘 설정 + 컨테이너 배치
    local idx = 0
    for _, entry in ipairs(activeIcons) do
        local icon = entry.frame
        if icon then
            if frame._ddDeferredReleaseIcons then
                frame._ddDeferredReleaseIcons[entry.iconKey] = nil
            end
            icon._ddCombatMissingSince = nil
            -- 개별 아이콘 크기 오버라이드 (아이콘 자체 settings.iconSize)
            TagDynamicIconForGroup(icon, groupName, groupSettings)
            icon._ddCombatKeepAlive = entry.combatKeepAlive and true or nil
            icon._ddCombatVisible = entry.combatVisible ~= false
            icon._ddInactiveGray = entry.inactiveGray and true or nil
            if entry.inactiveGray then
                icon._ddManagedAuraExpired = nil
            end
            SetManagedIconLayoutVisible(icon, entry.inactiveGray or (entry.combatVisible ~= false and not icon._ddManagedAuraExpired))

            local iw, ih = baseIconW, baseIconH
            local iconData = entry.iconData
            if iconData and iconData.settings and iconData.settings.iconSize then
                iw, ih = ComputeIconDimensions({
                    iconSize = iconData.settings.iconSize,
                    aspectRatioCrop = iconData.settings.aspectRatio or groupSettings.aspectRatioCrop or 1.0,
                })
            end

            -- SetupFrameInContainer (이미 managed면 위치만 갱신)
            local alreadyManaged = icon._ddIsManaged and icon._ddContainerRef == frame
                and not GroupRenderer._forceFullSetup
            if not alreadyManaged then
                bridge:SetupFrameInContainer(icon, frame, iw, ih, entry.iconKey, groupSettings.zoom, groupSettings.aspectRatioCrop)
            elseif icon.icon then
                -- [FIX] 이미 managed 아이콘도 zoom + 종횡비 크롭 갱신
                bridge.ApplyTexCoordCrop(icon.icon, groupSettings.zoom or 0.08, groupSettings.aspectRatioCrop or 1.0)
            end

            -- [FIX] 동적 그룹 테두리 적용
            local iconTexture = icon.icon or icon.Icon
            if iconTexture then
                local edgeSize = tonumber(groupSettings.borderSize) or 1
                if DDingUI and DDingUI.ScaleBorder then
                    edgeSize = DDingUI:ScaleBorder(edgeSize)
                else
                    edgeSize = math.floor(edgeSize + 0.5)
                end

                icon._ddBorders = icon._ddBorders or {}
                local borders = icon._ddBorders
                if #borders == 0 then
                    local function CreateBorderLine() return icon:CreateTexture(nil, "OVERLAY") end
                    borders[1] = CreateBorderLine(); borders[1]:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 0, 0); borders[1]:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 0, 0)
                    borders[2] = CreateBorderLine(); borders[2]:SetPoint("BOTTOMLEFT", iconTexture, "BOTTOMLEFT", 0, 0); borders[2]:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 0, 0)
                    borders[3] = CreateBorderLine(); borders[3]:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 0, 0); borders[3]:SetPoint("BOTTOMLEFT", iconTexture, "BOTTOMLEFT", 0, 0)
                    borders[4] = CreateBorderLine(); borders[4]:SetPoint("TOPRIGHT", iconTexture, "TOPRIGHT", 0, 0); borders[4]:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 0, 0)
                end
                if #borders >= 4 then
                    local bc = groupSettings.borderColor or { 0, 0, 0, 1 }
                    local br, bg, bb, ba = 0, 0, 0, 1
                    if type(bc) == "table" and bc.GetRGBA then br, bg, bb, ba = bc:GetRGBA()
                    elseif type(bc) == "table" and bc[1] then br, bg, bb, ba = bc[1], bc[2], bc[3], bc[4] or 1
                    elseif type(bc) == "table" and bc.r then br, bg, bb, ba = bc.r, bc.g, bc.b, bc.a or 1 end

                    borders[1]:SetHeight(edgeSize); borders[2]:SetHeight(edgeSize)
                    borders[3]:SetWidth(edgeSize); borders[4]:SetWidth(edgeSize)
                    for _, borderTex in ipairs(borders) do
                        borderTex:SetColorTexture(br, bg, bb, ba)
                        borderTex:SetShown(edgeSize > 0 and (entry.inactiveGray or not icon._ddManagedAuraExpired) and entry.combatVisible ~= false)
                    end
                end
            end

            -- [FIX] 동적 그룹 텍스트 파라미터 적용
            if icon.count then
                local anchor = groupSettings.chargeTextAnchor or "BOTTOMRIGHT"
                if anchor == "MIDDLE" then anchor = "CENTER" end
                local ox = tonumber(groupSettings.countTextOffsetX) or 0
                local oy = tonumber(groupSettings.countTextOffsetY) or 0
                icon.count:ClearAllPoints()
                icon.count:SetPoint(anchor, iconTexture or icon, anchor, ox, oy)

                local size = tonumber(groupSettings.countTextSize)
                if size and size > 0 then
                    local font = DDingUI:GetFont(groupSettings.countTextFont)
                    icon.count:SetFont(font, size, "OUTLINE")
                end

                local tc = groupSettings.countTextColor
                if type(tc) == "table" then
                    local r, g, b, a = 1, 1, 1, 1
                    if tc.GetRGBA then r, g, b, a = tc:GetRGBA()
                    elseif tc[1] then r, g, b, a = tc[1], tc[2], tc[3], tc[4] or 1
                    elseif tc.r then r, g, b, a = tc.r, tc.g, tc.b, tc.a or 1 end
                    icon.count:SetTextColor(r, g, b, a)
                end
            end

            if icon.cooldown then
                local cdAnchor, oxRaw, oyRaw, textSizeRaw, textFont, textColor = ResolveCooldownTextStyle(groupName, groupSettings)
                local ox = tonumber(oxRaw) or 0
                local oy = tonumber(oyRaw) or 0
                if cdAnchor == "MIDDLE" then cdAnchor = "CENTER" end

                if groupSettings.hideDurationText then
                    if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(true) end
                    icon.cooldown.noCooldownCount = true
                else
                    if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(false) end
                    icon.cooldown.noCooldownCount = nil
                end

                local cdText = GetCooldownTextFontString(icon.cooldown)

                if cdText then
                    if groupSettings.hideDurationText then
                        cdText:Hide()
                        if not cdText.hookedHideText then
                            cdText.hookedHideText = true
                            hooksecurefunc(cdText, "Show", function(self)
                                local cd = self:GetParent()
                                if cd and cd.noCooldownCount then self:Hide() end
                            end)
                        end
                    else
                        cdText:Show()
                        if cdAnchor then
                            cdText:ClearAllPoints()
                            cdText:SetPoint(cdAnchor, icon.cooldown, cdAnchor, ox, oy)
                        end
                        local size = tonumber(textSizeRaw)
                        if size and size > 0 then
                            local font = DDingUI:GetFont(textFont)
                            cdText:SetFont(font, size, "OUTLINE")
                        end
                        local tc = textColor
                        if type(tc) == "table" then
                            local r, g, b, a = 1, 1, 1, 1
                            if tc.GetRGBA then r, g, b, a = tc:GetRGBA()
                            elseif tc[1] then r, g, b, a = tc[1], tc[2], tc[3], tc[4] or 1
                            elseif tc.r then r, g, b, a = tc.r, tc.g, tc.b, tc.a or 1 end
                            cdText:SetTextColor(r, g, b, a)
                        end
                    end
                end
            end

            ApplyDynamicIconTextOptions(icon, groupName, groupSettings)

            idx = idx + 1
            frame._managedIcons[idx] = icon
            -- [FIX] 동적 아이콘 명시적 Show (LayoutGroup의 IsShown 필터 통과)
            icon:Show()
            local iconAlpha = groupSettings.groupAlpha or 1
            if icon._ddCombatKeepAlive and icon._ddCombatVisible == false then
                iconAlpha = 0
            end
            SetAlphaIfNeeded(icon, iconAlpha, "_ddLastGroupAlpha")
            if entry.inactiveGray and iconAlpha > 0 then
                SetDynamicIconInactiveGray(icon, true)
            elseif iconAlpha > 0 then
                SetDynamicIconInactiveGray(icon, false)
                RestoreIconTextureOpacity(icon)
            end
        end
    end
    frame._iconCount = idx

    -- [FIX] IsShown=false 누락 복구: 아이콘이 스캔되었다면 CDM이 실질적으로 활성 상태임
    -- LayoutGroup이 스킵되는 것을 방지하기 위해 여기서 미리 _viewerHidden 플래그를 점검/해제
    local sourceViewer = viewerName and _G[viewerName]
    if sourceViewer and sourceViewer:IsShown() and frame._viewerHidden then
        frame._viewerHidden = false
    end

    -- viewerSettings 구성 (groupSettings → viewerSettings 형식 변환)
    local vs = {
        iconSize = groupSettings.iconSize or 32,
        aspectRatioCrop = groupSettings.aspectRatioCrop or 1.0,
        spacing = groupSettings.spacing or 2,
        primaryDirection = groupSettings.direction or "RIGHT",
        secondaryDirection = groupSettings.growDirection or "DOWN",
        rowLimit = groupSettings.rowLimit or 0,
        rowIconSizes = groupSettings.rowIconSizes,
        groupOffsets = groupSettings.groupOffsets,
        groupCategory = groupSettings.groupCategory,
        iconMotion = groupSettings.iconMotion,
        iconMotionDuration = groupSettings.iconMotionDuration,
    }

    -- LayoutGroup (기존 레이아웃 엔진 재사용)
    self:LayoutGroup(frame, vs, nil)

    -- Show/Hide 결정
    if idx > 0 then
        frame:Show()
    elseif inCombat then
        frame._pendingCombatHide = true
    else
        frame:Hide()
    end
end
