local ns = select(2, ...)
local DDingUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0", true)

local IconStyle = {}
DDingUI.CustomIconStyle = IconStyle

local _CreateTextureBorder = DDingUI.CreateTextureBorder
local UpdateTextureBorderColor = DDingUI.UpdateTextureBorderColor
local _UpdateTextureBorderSize = DDingUI.UpdateTextureBorderSize
local ShowTextureBorder = DDingUI.ShowTextureBorder

local function CreateTextureBorder(parent, borderSize, r, g, b, a)
    return _CreateTextureBorder(parent, borderSize, r, g, b, a, true)
end

local function UpdateTextureBorderSize(parent, borderSize)
    return _UpdateTextureBorderSize(parent, borderSize, true)
end

local DEFAULT_ICON_SETTINGS = {
    iconSize = 44,
    aspectRatio = 1.0,
    borderSize = 1,
    borderColor = { 0, 0, 0, 1 },
    showCharges = true,
    showCooldown = true,
    showGCDSwipe = false,
    desaturateWhenUnusable = true,
    desaturateOnCooldown = true,
    countSettings = {
        size = 16,
        anchor = "BOTTOMRIGHT",
        offsetX = -2,
        offsetY = 2,
        color = { 1, 1, 1, 1 },
    },
    cooldownSettings = {
        size = 12,
        color = { 1, 1, 1, 1 },
    },
}

local function CopyColor(color)
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], color[4] }
end

-- Infer icon type if missing (for migration from older versions)
local function EnsureIconType(iconData)
    if not iconData then return end
    if iconData.type then return end  -- Already has type

    -- Infer type from data structure
    if iconData.slotID then
        iconData.type = "slot"
    elseif iconData.id then
        -- Try to detect if it's an item or spell
        -- C_Item.GetItemInfo is more reliable for checking if ID is an item
        local itemInfo = C_Item.GetItemInfo(iconData.id)
        if itemInfo then
            iconData.type = "item"
        else
            -- Also try legacy GetItemInfo as fallback
            local itemName = GetItemInfo(iconData.id)
            if itemName then
                iconData.type = "item"
            else
                -- Check if it's a valid spell
                local spellInfo = C_Spell.GetSpellInfo(iconData.id)
                if spellInfo then
                    iconData.type = "spell"
                else
                    -- Default to spell if we can't determine
                    iconData.type = "spell"
                end
            end
        end
    end
end

local function EnsureIconSettings(iconData)
    if not iconData then return end
    EnsureIconType(iconData)  -- Ensure type is set
    iconData.settings = iconData.settings or {}
    local settings = iconData.settings

    -- NOTE: iconSize is intentionally NOT set here to allow group iconSize to be used as fallback
    -- if settings.iconSize == nil then settings.iconSize = DEFAULT_ICON_SETTINGS.iconSize end
    if settings.aspectRatio == nil then settings.aspectRatio = DEFAULT_ICON_SETTINGS.aspectRatio end
    if settings.borderSize == nil then settings.borderSize = DEFAULT_ICON_SETTINGS.borderSize end
    if settings.borderColor == nil then settings.borderColor = CopyColor(DEFAULT_ICON_SETTINGS.borderColor) end
    if settings.showCharges == nil then settings.showCharges = DEFAULT_ICON_SETTINGS.showCharges end
    if settings.showCooldown == nil then settings.showCooldown = DEFAULT_ICON_SETTINGS.showCooldown end
    if settings.showGCDSwipe == nil then settings.showGCDSwipe = DEFAULT_ICON_SETTINGS.showGCDSwipe end
    if settings.desaturateWhenUnusable == nil then settings.desaturateWhenUnusable = DEFAULT_ICON_SETTINGS.desaturateWhenUnusable end
    if settings.desaturateOnCooldown == nil then settings.desaturateOnCooldown = DEFAULT_ICON_SETTINGS.desaturateOnCooldown end

    settings.countSettings = settings.countSettings or {}
    if settings.countSettings.size == nil then settings.countSettings.size = DEFAULT_ICON_SETTINGS.countSettings.size end
    if settings.countSettings.anchor == nil then settings.countSettings.anchor = DEFAULT_ICON_SETTINGS.countSettings.anchor end
    if settings.countSettings.offsetX == nil then settings.countSettings.offsetX = DEFAULT_ICON_SETTINGS.countSettings.offsetX end
    if settings.countSettings.offsetY == nil then settings.countSettings.offsetY = DEFAULT_ICON_SETTINGS.countSettings.offsetY end
    if settings.countSettings.color == nil then settings.countSettings.color = CopyColor(DEFAULT_ICON_SETTINGS.countSettings.color) end

    settings.cooldownSettings = settings.cooldownSettings or {}
    if settings.cooldownSettings.size == nil then settings.cooldownSettings.size = DEFAULT_ICON_SETTINGS.cooldownSettings.size end
    if settings.cooldownSettings.color == nil then settings.cooldownSettings.color = CopyColor(DEFAULT_ICON_SETTINGS.cooldownSettings.color) end

    -- TrinketProc-specific defaults
    if iconData.type == "trinketProc" then
        if settings.procSpellID == nil then settings.procSpellID = 0 end
        if settings.showProcDuration == nil then settings.showProcDuration = true end
        if settings.showItemCooldown == nil then settings.showItemCooldown = true end
        if settings.showProcStacks == nil then settings.showProcStacks = true end
    end
end

local function SafeSetBackdrop(frame, backdropInfo, borderColor)
    if not frame or not frame.SetBackdrop then return end
    if InCombatLockdown() then
        DDingUI.__cdmPendingBackdrops = DDingUI.__cdmPendingBackdrops or {}
        DDingUI.__cdmPendingBackdrops[frame] = {
            backdropInfo = backdropInfo,
            borderColor = borderColor,
        }
        if not DDingUI.__cdmBackdropEventFrame then
            local eventFrame = CreateFrame("Frame")
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:SetScript("OnEvent", function()
                for pending, settings in pairs(DDingUI.__cdmPendingBackdrops) do
                    if pending and pending.SetBackdrop then
                        pcall(pending.SetBackdrop, pending, settings.backdropInfo)
                        if settings.borderColor then
                            pcall(pending.SetBackdropBorderColor, pending, unpack(settings.borderColor))
                        end
                    end
                end
                DDingUI.__cdmPendingBackdrops = {}
            end)
            DDingUI.__cdmBackdropEventFrame = eventFrame
        end
        return
    end

    pcall(frame.SetBackdrop, frame, backdropInfo)
    if borderColor then
        pcall(frame.SetBackdropBorderColor, frame, unpack(borderColor))
    end
end

local function ApplyIconBorder(iconFrame, settings)
    if not iconFrame or not iconFrame.border then return end
    local edgeSize = settings.borderSize or 0
    if edgeSize <= 0 then
        ShowTextureBorder(iconFrame.border, false)
        iconFrame.border:Hide()
        return
    end

    -- Use texture-based borders (no SetBackdrop = no taint)
    local borderColor = settings.borderColor or {0, 0, 0, 1}
    if not iconFrame.border.__dduiBorders then
        CreateTextureBorder(iconFrame.border, edgeSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    else
        UpdateTextureBorderSize(iconFrame.border, edgeSize)
        UpdateTextureBorderColor(iconFrame.border, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    end
    ShowTextureBorder(iconFrame.border, true)
    iconFrame.border:Show()
end

local function BuildCountSettings(iconSettings)
    local cs = iconSettings.countSettings or {}
    return {
        size = cs.size or 16,
        anchor = cs.anchor or "BOTTOMRIGHT",
        offsetX = cs.offsetX or -2,
        offsetY = cs.offsetY or 2,
        color = cs.color or {1, 1, 1, 1},
        font = cs.font,  -- Font name from LSM, nil means use global font
    }
end

local function ApplyCooldownTextStyle(cooldown, iconData)
    if not cooldown or not cooldown.GetRegions then return end

    local fontString
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            fontString = region
            break
        end
    end
    if not fontString then return end

    local cds = (iconData.settings and iconData.settings.cooldownSettings) or {}
    local fontPath = DDingUI:GetGlobalFont()
    local size = cds.size or 12
    local color = cds.color or { 1, 1, 1, 1 }

    -- Reuse general viewer shadow offsets for consistency
    local shadowOffsetX = 1
    local shadowOffsetY = -1
    if DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.viewers and DDingUI.db.profile.viewers.general then
        shadowOffsetX = DDingUI.db.profile.viewers.general.cooldownShadowOffsetX or shadowOffsetX
        shadowOffsetY = DDingUI.db.profile.viewers.general.cooldownShadowOffsetY or shadowOffsetY
    end

    local _, _, flags = fontString:GetFont()
    fontString:SetFont(fontPath, size, flags)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fontString:SetShadowOffset(shadowOffsetX, shadowOffsetY)
end

local function ApplyAspectRatioCrop(texture, aspect, baseZoom)
    if not texture or not texture.SetTexCoord then return end

    aspect = tonumber(aspect) or 1.0
    if aspect <= 0 then aspect = 1.0 end

    baseZoom = tonumber(baseZoom) or 0
    if baseZoom < 0 then baseZoom = 0 end
    if baseZoom > 0.499 then baseZoom = 0.499 end

    local left, right, top, bottom = baseZoom, 1 - baseZoom, baseZoom, 1 - baseZoom
    local regionW = right - left
    local regionH = bottom - top

    if regionW > 0 and regionH > 0 and aspect ~= 1.0 then
        local currentRatio = regionW / regionH
        if aspect > currentRatio then
            local desiredH = regionW / aspect
            local cropH = (regionH - desiredH) / 2
            top = top + cropH
            bottom = bottom - cropH
        elseif aspect < currentRatio then
            local desiredW = regionH * aspect
            local cropW = (regionW - desiredW) / 2
            left = left + cropW
            right = right - cropW
        end
    end

    texture:SetTexCoord(left, right, top, bottom)
end

local function ApplyIconSettings(iconFrame, iconData, groupSettings)
    EnsureIconSettings(iconData)
    local settings = iconData.settings or {}
    -- Use icon's own size if useOwnSize is true, otherwise fall back to group size, then default
    local size
    if settings.useOwnSize then
        size = settings.iconSize or DEFAULT_ICON_SETTINGS.iconSize
    else
        size = settings.iconSize or (groupSettings and groupSettings.iconSize) or DEFAULT_ICON_SETTINGS.iconSize
    end
    local aspect = settings.aspectRatio or 1.0
    local width = size
    local height = size
    if aspect > 1.0 then
        height = size / aspect
    elseif aspect < 1.0 then
        width = size * aspect
    end
    -- [FIX] DynamicIconBridge 관리 아이콘은 GroupSystem이 크기를 관리하므로 건너뜀
    -- CustomIcons의 aspectRatio와 GroupSystem의 aspectRatioCrop이 다르면
    -- SetSize → snap-back 훅 → 1프레임 깜빡임 발생 방지
    if not iconFrame._ddIsManaged then
        iconFrame:SetSize(width, height)
    end

    if iconFrame.icon and not iconFrame._ddIsManaged then
        iconFrame.icon:ClearAllPoints()
        iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
        iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
        -- Mirror CooldownViewer behavior: crop instead of stretching when aspect ratio changes.
        ApplyAspectRatioCrop(iconFrame.icon, aspect, 0.08)
    end

    ApplyIconBorder(iconFrame, {
        borderSize = settings.borderSize or DEFAULT_ICON_SETTINGS.borderSize,
        borderColor = settings.borderColor or DEFAULT_ICON_SETTINGS.borderColor,
    })

    local managedGroupSettings = groupSettings
        or iconFrame._groupSettings
        or (iconFrame._ddContainerRef and iconFrame._ddContainerRef._groupSettings)
    local groupOwnsText = iconFrame._ddIsManaged and managedGroupSettings
    if not groupOwnsText then
        local cs = BuildCountSettings(settings)
        local fontPath = DDingUI:GetGlobalFont()
        if cs.font and LSM then
            local fetchedFont = LSM:Fetch("font", cs.font)
            if fetchedFont then
                fontPath = fetchedFont
            end
        end
        if fontPath and cs.size and tonumber(cs.size) > 0 then
            -- pcall to safely set font just in case path is invalid
            pcall(function() iconFrame.count:SetFont(fontPath, tonumber(cs.size), "OUTLINE") end)
        else
            pcall(function() iconFrame.count:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE") end)
        end
        if cs.color then
            iconFrame.count:SetTextColor(unpack(cs.color))
        end
        iconFrame.count:ClearAllPoints()
        iconFrame.count:SetPoint(cs.anchor, iconFrame, cs.anchor, cs.offsetX, cs.offsetY)

        -- Apply cooldown text settings
        local cooldownSettings = settings.cooldownSettings or {size = 12, color = {1, 1, 1, 1}}
        if iconFrame.cooldown.SetCountdownFont then
            local cdFontPath = DDingUI:GetGlobalFont()
            iconFrame.cooldown:SetCountdownFont(cdFontPath, cooldownSettings.size, "OUTLINE")
        end
        ApplyCooldownTextStyle(iconFrame.cooldown, iconData)
    end
    -- Note: Cooldown text color is not directly controllable with standard WoW cooldown frames.
    -- The color setting is saved but may not be applied depending on WoW API limitations.
end

-- ------------------------
IconStyle.defaultIconSettings = DEFAULT_ICON_SETTINGS
IconStyle.EnsureIconType = EnsureIconType
IconStyle.EnsureIconSettings = EnsureIconSettings
IconStyle.SafeSetBackdrop = SafeSetBackdrop
IconStyle.ApplyIconBorder = ApplyIconBorder
IconStyle.ApplyIconSettings = ApplyIconSettings
