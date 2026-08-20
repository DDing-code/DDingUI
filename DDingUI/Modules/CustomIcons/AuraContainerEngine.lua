local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Engine = {
    records = {},
    pendingAnchors = {},
    buildQueue = {},
    buildHead = 1,
    buildTail = 0,
    ownedIconCounts = {},
}
DDingUI.CustomIconAuraEngine = Engine

local RuntimeValues = DDingUI.CustomIconRuntimeValues
local SafeNumber = RuntimeValues and RuntimeValues.SafeNumber

local VALID_POINTS = {
    TOP = true, TOPLEFT = true, TOPRIGHT = true,
    BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
    LEFT = true, RIGHT = true, CENTER = true,
}

local function PublicNumber(value)
    if SafeNumber then
        return SafeNumber(value)
    elseif type(value) == "number" then
        return value
    elseif type(value) == "string" then
        return tonumber(value)
    end
    return nil
end

local function PositiveNumber(value)
    local number = PublicNumber(value)
    if number and number > 0 then return number end
    return nil
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function PixelSnap(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function NormalizePoint(point, fallback)
    point = type(point) == "string" and point:upper() or fallback
    if point == "MIDDLE" then point = "CENTER" end
    return VALID_POINTS[point] and point or fallback
end

local function ResolveColor(color, fallback)
    fallback = fallback or { 1, 1, 1, 1 }
    if type(color) ~= "table" then
        return fallback[1], fallback[2], fallback[3], fallback[4]
    end
    return color[1] or color.r or fallback[1],
        color[2] or color.g or fallback[2],
        color[3] or color.b or fallback[3],
        color[4] or color.a or fallback[4]
end

local function ColorSignature(color)
    local r, g, b, a = ResolveColor(color)
    return table.concat({ r, g, b, a }, ",")
end

local function ResolveFont(fontName)
    local font = DDingUI.GetFont and DDingUI:GetFont(fontName)
    if type(font) == "string" and font ~= "" then return font end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function ComputeIconDimensions(settings)
    local size = math.max(1, tonumber(settings.iconSize) or 32) + 0.1
    local aspect = tonumber(settings.aspectRatioCrop) or 1
    if aspect <= 0 then aspect = 1 end
    local width, height = size, size
    if aspect > 1 then
        height = size / aspect
    elseif aspect < 1 then
        width = size * aspect
    end
    return math.max(1, PixelSnap(width)), math.max(1, PixelSnap(height))
end

local function ApplyTextureCrop(texture, zoom, aspect)
    if not texture then return end
    zoom = Clamp(zoom or 0.08, 0, 0.49)
    aspect = tonumber(aspect) or 1
    if aspect <= 0 then aspect = 1 end

    local left, right, top, bottom = zoom, 1 - zoom, zoom, 1 - zoom
    local regionWidth, regionHeight = right - left, bottom - top
    if aspect > 1 then
        local desiredHeight = regionWidth / aspect
        local crop = (regionHeight - desiredHeight) / 2
        top, bottom = top + crop, bottom - crop
    elseif aspect < 1 then
        local desiredWidth = regionHeight * aspect
        local crop = (regionWidth - desiredWidth) / 2
        left, right = left + crop, right - crop
    end
    texture:SetTexCoord(left, right, top, bottom)
end

local function IsEditPreviewActive()
    if DDingUI.Movers and DDingUI.Movers.ConfigMode then return true end
    return EditModeManagerFrame
        and EditModeManagerFrame.IsEditModeActive
        and EditModeManagerFrame:IsEditModeActive()
        or false
end

local function CurrentSpecID()
    local index = GetSpecialization and GetSpecialization()
    return index and GetSpecializationInfo and GetSpecializationInfo(index) or nil
end

local function MatchesStaticLoadConditions(iconData)
    local conditions = iconData.settings
        and iconData.settings.loadConditions
    if not (conditions and conditions.enabled) then return true end

    if conditions.inCombat or conditions.outOfCombat then
        return false
    end
    if type(conditions.specs) ~= "table" then return true end

    local hasRestriction = false
    for _, enabled in pairs(conditions.specs) do
        if enabled then
            hasRestriction = true
            break
        end
    end
    if not hasRestriction then return true end
    local specID = CurrentSpecID()
    return specID and conditions.specs[specID] == true or false
end

local function IsEngineAura(iconData)
    if type(iconData) ~= "table" or iconData.type ~= "aura" then return false end
    if not PositiveNumber(iconData.id) then return false end
    local settings = iconData.settings or {}
    if settings.alwaysShow == "on" then return false end
    if not MatchesStaticLoadConditions(iconData) then return false end

    local customIcons = DDingUI.CustomIcons
    if customIcons and customIcons.IsCustomTimedAuraIcon
        and customIcons:IsCustomTimedAuraIcon(iconData)
    then
        return false
    end
    return true
end

local function AddSpellID(target, order, value)
    local spellID = PositiveNumber(value)
    if not spellID or target[spellID] then return end
    target[spellID] = true
    order[#order + 1] = spellID
end

local function AddSpellIDs(target, order, value)
    if type(value) == "table" then
        for key, entry in pairs(value) do
            if entry == true then
                AddSpellID(target, order, key)
            else
                AddSpellIDs(target, order, entry)
            end
        end
    elseif type(value) == "string" then
        for entry in value:gmatch("%d+") do
            AddSpellID(target, order, entry)
        end
    else
        AddSpellID(target, order, value)
    end
end

local function AddSpellVariants(target, order, spellID)
    AddSpellID(target, order, spellID)
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        AddSpellID(target, order, C_SpellBook.FindSpellOverrideByID(spellID))
    end
    if C_Spell and C_Spell.GetBaseSpell then
        AddSpellID(target, order, C_Spell.GetBaseSpell(spellID))
    end
end

local function OrderedSourceKeys(db, sourceGroupKey)
    local result = {}
    if sourceGroupKey == "ungrouped" then
        for iconKey in pairs(db.ungrouped or {}) do
            if type(iconKey) == "string" then result[#result + 1] = iconKey end
        end
        table.sort(result)
        return result
    end

    local group = db.groups and db.groups[sourceGroupKey]
    local icons = group and group.icons
    if type(icons) ~= "table" then return result end
    local maximum = 0
    for index in pairs(icons) do
        if type(index) == "number" and index >= 1 and index % 1 == 0 then
            maximum = math.max(maximum, index)
        end
    end
    local seen = {}
    for index = 1, maximum do
        local iconKey = icons[index]
        if type(iconKey) == "string" and not seen[iconKey] then
            seen[iconKey] = true
            result[#result + 1] = iconKey
        end
    end
    return result
end

local function BuildNativeSpellSet(iconList)
    local result, ignoredOrder = {}, {}
    local compat = DDingUI.CDMCompat
    for _, entry in ipairs(iconList or {}) do
        if compat and compat.ResolveFrameSpellID and entry and entry.icon then
            AddSpellID(result, ignoredOrder, compat:ResolveFrameSpellID(entry.icon))
        end
    end
    return result
end

local function BuildSourceSpec(groupName, settings, iconList)
    local profile = DDingUI.db and DDingUI.db.profile
    local db = profile and profile.dynamicIcons
    local sourceGroupKey = settings and settings.sourceGroupKey
    if type(db) ~= "table" or not sourceGroupKey then return nil end

    local ownedKeys, iconKeys = {}, {}
    local includeMap, includeOrder = {}, {}
    local nativeSpellIDs = BuildNativeSpellSet(iconList)
    for _, iconKey in ipairs(OrderedSourceKeys(db, sourceGroupKey)) do
        local iconData = db.iconData and db.iconData[iconKey]
        if IsEngineAura(iconData) then
            local primaryIDs, primaryOrder = {}, {}
            AddSpellIDs(primaryIDs, primaryOrder, iconData.id)
            local iconSettings = iconData.settings or {}
            AddSpellIDs(primaryIDs, primaryOrder, iconSettings.auraAliases)
            AddSpellIDs(primaryIDs, primaryOrder, iconSettings.fallbackItems)
            local candidateMap, candidateOrder = {}, {}
            for _, spellID in ipairs(primaryOrder) do
                AddSpellVariants(candidateMap, candidateOrder, spellID)
            end
            local duplicateNative = false
            for spellID in pairs(candidateMap) do
                if nativeSpellIDs[spellID] then
                    duplicateNative = true
                    break
                end
            end
            if not duplicateNative then
                ownedKeys[iconKey] = true
                iconKeys[#iconKeys + 1] = iconKey
                for _, spellID in ipairs(candidateOrder) do
                    AddSpellID(includeMap, includeOrder, spellID)
                end
            end
        end
    end
    if #iconKeys == 0 or #includeOrder == 0 then return nil end

    table.sort(includeOrder)
    local width, height = ComputeIconDimensions(settings)
    local direction = type(settings.direction) == "string" and settings.direction:upper() or "RIGHT"
    local secondaryDirection = type(settings.growDirection) == "string"
        and settings.growDirection:upper() or "DOWN"
    local spacing = PixelSnap(settings.spacing or 2)
    local rowLimit = math.max(0, PixelSnap(settings.rowLimit or 0))
    local signature = table.concat({
        groupName, sourceGroupKey, table.concat(iconKeys, ":"),
        table.concat(includeOrder, ":"), width, height,
        direction, secondaryDirection, spacing, rowLimit,
    }, "|")

    return {
        signature = signature,
        ownedKeys = ownedKeys,
        iconKeys = iconKeys,
        includeMap = includeMap,
        width = width,
        height = height,
        spacing = spacing,
        rowLimit = rowLimit,
        direction = direction,
        secondaryDirection = secondaryDirection,
        maxFrames = #iconKeys,
    }
end

local function BuildStyle(settings, spec)
    local hideActiveState = settings.hideActiveState == true
    local glowType = settings.auraGlowType or "Pixel Glow"
    local style = {
        width = spec.width,
        height = spec.height,
        zoom = settings.zoom or 0.08,
        aspect = settings.aspectRatioCrop or 1,
        borderSize = math.max(0, PixelSnap(settings.borderSize or 1)),
        borderColor = settings.borderColor or { 0, 0, 0, 1 },
        durationFont = ResolveFont(settings.durationTextFont or settings.cooldownFont),
        durationSize = math.max(1, tonumber(settings.durationTextSize or settings.cooldownFontSize) or 12),
        durationColor = settings.durationTextColor or settings.cooldownTextColor or { 1, 1, 1, 1 },
        durationPoint = NormalizePoint(settings.durationTextAnchor or settings.cooldownTextAnchor, "CENTER"),
        durationX = tonumber(settings.durationTextOffsetX or settings.cooldownTextOffsetX) or 0,
        durationY = tonumber(settings.durationTextOffsetY or settings.cooldownTextOffsetY) or 0,
        hideDuration = settings.hideDurationText == true,
        countFont = ResolveFont(settings.countTextFont),
        countSize = math.max(1, tonumber(settings.countTextSize) or 14),
        countColor = settings.countTextColor or { 1, 1, 1, 1 },
        countPoint = NormalizePoint(settings.chargeTextAnchor, "BOTTOMRIGHT"),
        countX = tonumber(settings.countTextOffsetX) or 0,
        countY = tonumber(settings.countTextOffsetY) or 0,
        hideSwipe = settings.disableSwipeAnimation == true or hideActiveState,
        swipeReverse = settings.swipeReverse == true,
        swipeColor = settings.auraSwipeColor or settings.swipeColor or { 0, 0, 0, 0.8 },
        desaturateIcon = hideActiveState,
        drawEdge = settings.disableEdgeGlow ~= true,
        drawBling = settings.disableBlingAnimation ~= true,
        glowEnabled = settings.auraGlow == true and not hideActiveState,
        glowType = glowType,
        glowBlizzard = settings.auraGlowColorMode == "blizzard" or glowType == "Blizzard Glow",
        glowColor = settings.auraGlowColor or { 0.95, 0.95, 0.32, 1 },
        glowLines = math.max(1, PixelSnap(settings.auraGlowPixelLines or 8)),
        glowFrequency = math.max(0.01, tonumber(settings.auraGlowPixelFrequency) or 0.25),
        glowLength = tonumber(settings.auraGlowPixelLength),
        glowThickness = math.max(0.1, tonumber(settings.auraGlowPixelThickness) or 2),
        glowParticles = math.max(1, PixelSnap(settings.auraGlowAutocastParticles or 8)),
        glowAutocastFrequency = math.max(0.01, tonumber(settings.auraGlowAutocastFrequency) or 0.25),
        glowScale = math.max(0.1, tonumber(settings.auraGlowAutocastScale) or 1),
        glowButtonFrequency = math.max(0.01, tonumber(settings.auraGlowButtonFrequency) or 0.25),
    }
    style.signature = table.concat({
        style.zoom, style.aspect, style.borderSize, ColorSignature(style.borderColor),
        style.durationFont, style.durationSize, ColorSignature(style.durationColor),
        style.durationPoint, style.durationX, style.durationY, style.hideDuration and 1 or 0,
        style.countFont, style.countSize, ColorSignature(style.countColor),
        style.countPoint, style.countX, style.countY,
        style.hideSwipe and 1 or 0, style.swipeReverse and 1 or 0,
        ColorSignature(style.swipeColor), style.desaturateIcon and 1 or 0,
        style.drawEdge and 1 or 0,
        style.drawBling and 1 or 0,
        style.glowEnabled and 1 or 0, style.glowType,
        style.glowBlizzard and 1 or 0, ColorSignature(style.glowColor),
        style.glowLines, style.glowFrequency, style.glowLength or "",
        style.glowThickness, style.glowParticles, style.glowAutocastFrequency,
        style.glowScale, style.glowButtonFrequency,
    }, "|")
    return style
end

local function ApplyBorder(regions, style)
    local r, g, b, a = ResolveColor(style.borderColor, { 0, 0, 0, 1 })
    local size = style.borderSize
    local borders = regions.borders
    borders[1]:SetHeight(math.max(size, 1))
    borders[2]:SetHeight(math.max(size, 1))
    borders[3]:SetWidth(math.max(size, 1))
    borders[4]:SetWidth(math.max(size, 1))
    for _, border in ipairs(borders) do
        border:SetColorTexture(r, g, b, a)
        border:SetShown(size > 0)
    end
end

local function ApplyText(fontString, font, size, color, point, x, y, alpha)
    fontString:SetFont(font, size, "OUTLINE")
    fontString:ClearAllPoints()
    fontString:SetPoint(point, fontString:GetParent(), point, x, y)
    fontString:SetTextColor(ResolveColor(color))
    fontString:SetAlpha(alpha or 1)
end

local function ApplyRegionStyle(regions, style)
    ApplyTextureCrop(regions.icon, style.zoom, style.aspect)
    regions.icon:SetDesaturated(style.desaturateIcon)
    local swipeR, swipeG, swipeB, swipeA = ResolveColor(style.swipeColor, { 0, 0, 0, 0.8 })
    regions.cooldown:SetDrawSwipe(not style.hideSwipe)
    regions.cooldown:SetReverse(style.swipeReverse)
    regions.cooldown:SetSwipeColor(swipeR, swipeG, swipeB, swipeA)
    regions.cooldown:SetDrawEdge(style.drawEdge)
    regions.cooldown:SetDrawBling(style.drawBling)
    regions.cooldown:SetHideCountdownNumbers(true)
    ApplyBorder(regions, style)
    ApplyText(
        regions.duration, style.durationFont, style.durationSize,
        style.durationColor, style.durationPoint, style.durationX, style.durationY,
        style.hideDuration and 0 or 1
    )
    ApplyText(
        regions.count, style.countFont, style.countSize,
        style.countColor, style.countPoint, style.countX, style.countY, 1
    )
end

local function ApplyActiveGlow(button, style)
    if not style.glowEnabled then return end
    local visuals = DDingUI.RestrictedAuraVisuals
    if visuals and visuals.ApplyGlow then
        visuals:ApplyGlow(button, style)
    end
end

local function DurationFormatter()
    if Engine.durationFormatterTried then return Engine.durationFormatter end
    Engine.durationFormatterTried = true
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum and Enum.NumericRuleFormatRounding)
    then
        return nil
    end

    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local up = Enum.NumericRuleFormatRounding.Up
    local down = Enum.NumericRuleFormatRounding.Down
    local ok = pcall(formatter.SetBreakpoints, formatter, {
        { threshold = 0, format = "%d", step = 1, rounding = up },
        { threshold = 60, format = "%dm", step = 1, rounding = up, components = { { div = 60 } } },
        { threshold = 61, format = "%dm", step = 1, rounding = down, components = { { div = 60 } } },
        { threshold = 3600, format = "%dh", step = 1, rounding = down, components = { { div = 3600 } } },
        { threshold = 86400, format = "%dd", step = 1, rounding = down, components = { { div = 86400 } } },
    })
    if ok then Engine.durationFormatter = formatter end
    return Engine.durationFormatter
end

local function RegisterDurationText(button, fontString)
    local formatter = DurationFormatter()
    local options = formatter and { textFormatter = formatter } or {}
    if pcall(button.SetDurationText, button, fontString, options) then return true end
    return pcall(button.SetDurationText, button, fontString, {})
end

local function CreateInitializer(buttons, style)
    return function(button)
        button:SetSize(style.width, style.height)
        if button.SetMouseClickEnabled then
            pcall(button.SetMouseClickEnabled, button, false)
        end
        if button.SetMouseMotionEnabled then
            pcall(button.SetMouseMotionEnabled, button, false)
        end

        local regions = {}
        regions.icon = button:CreateTexture(nil, "ARTWORK")
        regions.icon:SetAllPoints(button)
        regions.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        regions.cooldown:SetAllPoints(button)

        regions.borderHost = CreateFrame("Frame", nil, button)
        regions.borderHost:SetAllPoints(button)
        regions.borderHost:SetFrameLevel(regions.cooldown:GetFrameLevel() + 1)
        regions.borderHost:EnableMouse(false)
        local top = regions.borderHost:CreateTexture(nil, "OVERLAY")
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
        local bottom = regions.borderHost:CreateTexture(nil, "OVERLAY")
        bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
        local left = regions.borderHost:CreateTexture(nil, "OVERLAY")
        left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
        local right = regions.borderHost:CreateTexture(nil, "OVERLAY")
        right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
        regions.borders = { top, bottom, left, right }

        regions.textHost = CreateFrame("Frame", nil, button)
        regions.textHost:SetAllPoints(button)
        regions.textHost:SetFrameLevel(regions.borderHost:GetFrameLevel() + 1)
        regions.textHost:EnableMouse(false)
        regions.duration = regions.textHost:CreateFontString(nil, "OVERLAY")
        regions.count = regions.textHost:CreateFontString(nil, "OVERLAY")
        ApplyRegionStyle(regions, style)
        pcall(ApplyActiveGlow, button, style)

        button:SetIcon(regions.icon)
        button:SetDurationCooldown(regions.cooldown)
        button:SetApplicationCount(regions.count, {})
        RegisterDurationText(button, regions.duration)
        buttons[button] = regions
    end
end

local function SetContainerAxis(container, vertical)
    local axes = AnchorUtil and AnchorUtil.FlowLayoutAxis
    if axes and container.SetFlowLayoutAxis then
        container:SetFlowLayoutAxis(vertical and axes.Vertical or axes.Horizontal)
    end
end

local function SetContainerMaximumLine(container, size)
    local setter = container.SetFlowLayoutMaximumLineSize or container.SetAuraLayoutRowWidth
    if setter then setter(container, size) end
end

local function ResolveContainerPoint(spec)
    if spec.direction == "UP" then return "BOTTOM", true end
    if spec.direction == "DOWN" then return "TOP", true end
    if spec.direction == "LEFT" then return "RIGHT", false end
    if spec.direction == "CENTERED_HORIZONTAL" then
        return spec.secondaryDirection == "UP" and "BOTTOM" or "TOP", false
    end
    return "LEFT", false
end

local function EnsureContainerAPI()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn) then return false end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    return C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") == true
end

local function BuildContainer(record, request)
    if not EnsureContainerAPI() then error("Blizzard_AuraContainer unavailable") end
    local spec, style = request.spec, request.style
    local point, vertical = ResolveContainerPoint(spec)
    local container = CreateFrame("AuraContainer", nil, record.holder, "CustomAuraContainerTemplate")
    record.buildingContainer = container
    container:SetPoint(point, record.holder, point)
    container:SetSize(1, 1)
    SetContainerAxis(container, vertical)

    if spec.rowLimit > 0 then
        local primarySize = vertical and spec.height or spec.width
        SetContainerMaximumLine(container, spec.rowLimit * primarySize + (spec.rowLimit - 1) * spec.spacing)
    end

    local buttons = setmetatable({}, { __mode = "k" })
    container:AddAuraGroup("tracked", "HELPFUL", {
        maxFrameCount = spec.maxFrames,
        candidateFilters = { includeSpellIDs = spec.includeMap },
        initializeFrame = CreateInitializer(buttons, style),
        layout = {
            elementWidth = spec.width,
            elementHeight = spec.height,
            elementSpacing = spec.spacing,
            lineSpacing = spec.spacing,
            groupSpacing = spec.spacing,
            groupLineSpacing = spec.spacing,
        },
    })
    if container.SetAuraGroupLayout then
        container:SetAuraGroupLayout("tracked", {
            elementWidth = spec.width,
            elementHeight = spec.height,
            elementSpacing = spec.spacing,
            lineSpacing = spec.spacing,
            groupSpacing = spec.spacing,
            groupLineSpacing = spec.spacing,
        })
    end
    container:SetUnit("player")
    container:UpdateAllAuras()
    record.buildingContainer = nil
    return container, point, buttons
end

local function SetRecordOwnership(record, ownedKeys)
    for iconKey in pairs(record.ownedKeys or {}) do
        local count = (Engine.ownedIconCounts[iconKey] or 1) - 1
        Engine.ownedIconCounts[iconKey] = count > 0 and count or nil
    end
    record.ownedKeys = ownedKeys
    for iconKey in pairs(ownedKeys or {}) do
        Engine.ownedIconCounts[iconKey] = (Engine.ownedIconCounts[iconKey] or 0) + 1
    end
end

local function DeactivateRecord(record, clearPending)
    record.active = false
    SetRecordOwnership(record, nil)
    if record.container then record.container:Hide() end
    if record.holder then record.holder:Hide() end
    if clearPending then
        record.pendingBuild = nil
        record.pendingSignature = nil
    end
end

local function EnsureHolder(record)
    if record.holder then return record.holder end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:EnableMouse(false)
    holder:Hide()
    record.holder = holder
    return holder
end

local function SyncHolderVisual(record)
    local holder, frame = record.holder, record.frame
    if not (holder and frame and record.active) then return end
    local alpha = PublicNumber(frame:GetAlpha())
    if alpha then holder:SetAlpha(alpha) end
    holder:SetFrameStrata(frame:GetFrameStrata())
    holder:SetShown(frame:IsShown())
end

local function HideOwnedLegacyFrames(record)
    local frame = record.frame
    if not (frame and frame._managedIcons and record.ownedKeys) then return end
    for index = 1, (frame._iconCount or 0) do
        local icon = frame._managedIcons[index]
        if icon and icon._ddIconKey and record.ownedKeys[icon._ddIconKey] then
            icon._ddLayoutVisible = false
            icon:Hide()
        end
    end
end

local function HookGroupFrame(record, frame)
    if record.hookedFrame == frame then return end
    record.hookedFrame = frame
    local groupName = record.groupName
    hooksecurefunc(frame, "SetPoint", function()
        Engine:MarkAnchor(groupName)
    end)
    hooksecurefunc(frame, "SetAlpha", function()
        local current = Engine.records[groupName]
        if current then SyncHolderVisual(current) end
    end)
    frame:HookScript("OnSizeChanged", function()
        Engine:MarkAnchor(groupName)
    end)
    frame:HookScript("OnShow", function()
        local current = Engine.records[groupName]
        if current then
            SyncHolderVisual(current)
            Engine:MarkAnchor(groupName)
        end
    end)
    frame:HookScript("OnHide", function()
        local current = Engine.records[groupName]
        if current and current.holder then current.holder:Hide() end
    end)
end

local function SetContainerPoint(record, point)
    if not (record.container and point) or record.currentPoint == point then return end
    record.container:ClearAllPoints()
    record.container:SetPoint(point, record.holder, point)
    record.currentPoint = point
end

local function GetManagedBounds(frame)
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    left, bottom = PublicNumber(left), PublicNumber(bottom)
    width, height = PublicNumber(width), PublicNumber(height)
    if not ok or not left or not bottom or not width or not height then
        return nil
    end
    local centerX, centerY = left + width / 2, bottom + height / 2
    local minX, maxX, minY, maxY
    for index = 1, (frame._iconCount or 0) do
        local icon = frame._managedIcons and frame._managedIcons[index]
        local x = icon and PublicNumber(icon._ddTargetX)
        local y = icon and PublicNumber(icon._ddTargetY)
        local iconWidth = icon and PublicNumber(icon._ddTargetWidth)
        local iconHeight = icon and PublicNumber(icon._ddTargetHeight)
        if icon and icon._ddLayoutVisible ~= false
            and x and y and iconWidth and iconHeight
        then
            local iconLeft, iconRight = centerX + x - iconWidth / 2, centerX + x + iconWidth / 2
            local iconBottom, iconTop = centerY + y - iconHeight / 2, centerY + y + iconHeight / 2
            minX = minX and math.min(minX, iconLeft) or iconLeft
            maxX = maxX and math.max(maxX, iconRight) or iconRight
            minY = minY and math.min(minY, iconBottom) or iconBottom
            maxY = maxY and math.max(maxY, iconTop) or iconTop
        end
    end
    return minX, maxX, minY, maxY, centerX, centerY
end

function Engine:AnchorGroup(groupName)
    local record = self.records[groupName]
    local holder, frame = record and record.holder, record and record.frame
    if not (record and record.active and holder and frame) then return end
    SyncHolderVisual(record)
    if not frame:IsShown() then return end

    local minX, maxX, minY, maxY, centerX, centerY = GetManagedBounds(frame)
    holder:ClearAllPoints()
    if not minX then
        SetContainerPoint(record, "CENTER")
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX or -10000, centerY or -10000)
        return
    end

    local spec, gap = record.spec, record.spec.spacing
    SetContainerPoint(record, record.basePoint)
    if spec.direction == "LEFT" then
        holder:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", minX - gap, (minY + maxY) / 2)
    elseif spec.direction == "UP" then
        holder:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", (minX + maxX) / 2, maxY + gap)
    elseif spec.direction == "DOWN" then
        holder:SetPoint("TOP", UIParent, "BOTTOMLEFT", (minX + maxX) / 2, minY - gap)
    elseif spec.direction == "CENTERED_HORIZONTAL" then
        if spec.secondaryDirection == "UP" then
            holder:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", (minX + maxX) / 2, maxY + gap)
        else
            holder:SetPoint("TOP", UIParent, "BOTTOMLEFT", (minX + maxX) / 2, minY - gap)
        end
    else
        holder:SetPoint("LEFT", UIParent, "BOTTOMLEFT", maxX + gap, (minY + maxY) / 2)
    end
end

function Engine:MarkAnchor(groupName)
    if not groupName or self.pendingAnchors[groupName] then return end
    self.pendingAnchors[groupName] = true
    self.worker:Show()
end

function Engine:QueueBuild(record, request)
    record.pendingBuild = request
    record.pendingSignature = request.signature
    record.buildNotBefore = (GetTime and GetTime() or 0) + 0.08
    if record.buildQueued then return end
    record.buildQueued = true
    self.buildTail = self.buildTail + 1
    self.buildQueue[self.buildTail] = record.groupName
    self.worker:Show()
end

function Engine:RunNextBuild()
    while self.buildHead <= self.buildTail do
        local groupName = self.buildQueue[self.buildHead]
        self.buildQueue[self.buildHead] = nil
        self.buildHead = self.buildHead + 1
        local record = self.records[groupName]
        if record then
            record.buildQueued = nil
            local request = record.pendingBuild
            if request then
                local now = GetTime and GetTime() or 0
                if record.buildNotBefore and now < record.buildNotBefore then
                    self.buildTail = self.buildTail + 1
                    self.buildQueue[self.buildTail] = groupName
                    record.buildQueued = true
                    return false
                end
                record.pendingBuild = nil
                record.pendingSignature = nil
                record.buildNotBefore = nil
                local ok, container, point, buttons = pcall(BuildContainer, record, request)
                if ok and container then
                    if record.container and record.container ~= container then
                        record.container:Hide()
                    end
                    record.container = container
                    record.buttons = buttons
                    record.basePoint = point
                    record.currentPoint = point
                    record.spec = request.spec
                    record.style = request.style
                    record.signature = request.spec.signature
                    record.styleSignature = request.style.signature
                    SetRecordOwnership(record, request.spec.ownedKeys)
                    record.active = true
                    record.failedSignature = nil
                    record.failedAt = nil
                    record.holder:Show()
                    HideOwnedLegacyFrames(record)
                    self:MarkAnchor(groupName)
                else
                    if record.buildingContainer then record.buildingContainer:Hide() end
                    record.buildingContainer = nil
                    record.failedSignature = request.signature
                    record.failedAt = GetTime and GetTime() or 0
                    record.lastError = tostring(container)
                    DeactivateRecord(record, false)
                end
                local bridge = DDingUI.DynamicIconBridge
                if bridge and bridge.NotifyIconsChanged then
                    bridge:NotifyIconsChanged(true)
                end
                return true
            end
        end
    end
    self.buildQueue = {}
    self.buildHead, self.buildTail = 1, 0
    return false
end

function Engine:SyncGroup(groupName, groupFrame, settings, iconList)
    if not groupName or not groupFrame or not settings or settings.enabled == false
        or IsEditPreviewActive()
    then
        self:ReleaseGroup(groupName)
        return false
    end

    local spec = BuildSourceSpec(groupName, settings, iconList)
    if not spec then
        self:ReleaseGroup(groupName)
        return false
    end

    local record = self.records[groupName]
    if not record then
        record = { groupName = groupName }
        self.records[groupName] = record
    end
    record.frame = groupFrame
    EnsureHolder(record)
    HookGroupFrame(record, groupFrame)

    local style = BuildStyle(settings, spec)
    local requestSignature = spec.signature .. "#" .. style.signature
    if record.active and record.signature == spec.signature
        and record.styleSignature == style.signature
    then
        record.spec = spec
        SetRecordOwnership(record, spec.ownedKeys)
        SyncHolderVisual(record)
        self:MarkAnchor(groupName)
        return true
    end

    if record.pendingSignature == requestSignature then
        return record.active == true
    end
    local now = GetTime and GetTime() or 0
    if record.failedSignature == requestSignature
        and record.failedAt and now - record.failedAt < 5
    then
        return record.active == true
    end

    if not record.active or record.signature ~= spec.signature then
        DeactivateRecord(record, false)
    end
    self:QueueBuild(record, {
        spec = spec,
        style = style,
        signature = requestSignature,
    })
    return record.active == true
end

function Engine:IsOwnedIcon(groupName, iconKey)
    local record = groupName and self.records[groupName]
    return record and record.active and record.ownedKeys and record.ownedKeys[iconKey] == true or false
end

function Engine:IsIconOwnedAnywhere(iconKey)
    return iconKey and (self.ownedIconCounts[iconKey] or 0) > 0 or false
end

function Engine:ReleaseGroup(groupName)
    local record = groupName and self.records[groupName]
    if not record then return end
    DeactivateRecord(record, true)
end

function Engine:DestroyGroup(groupName)
    self:ReleaseGroup(groupName)
    self.records[groupName] = nil
    self.pendingAnchors[groupName] = nil
end

function Engine:DestroyAll()
    for groupName in pairs(self.records) do
        self:DestroyGroup(groupName)
    end
    self.ownedIconCounts = {}
    self.buildQueue = {}
    self.buildHead, self.buildTail = 1, 0
end

Engine.worker = CreateFrame("Frame")
Engine.worker:Hide()
Engine.worker:SetScript("OnUpdate", function(self)
    local built = Engine:RunNextBuild()
    for groupName in pairs(Engine.pendingAnchors) do
        Engine.pendingAnchors[groupName] = nil
        Engine:AnchorGroup(groupName)
    end
    if not built and Engine.buildHead > Engine.buildTail and not next(Engine.pendingAnchors) then
        self:Hide()
    end
end)
