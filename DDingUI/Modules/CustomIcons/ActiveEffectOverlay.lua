local _, ns = ...
local DDingUI = ns and (ns.Addon or ns.DDingUI)
if not DDingUI then return end

local ActiveEffectOverlay = {}
DDingUI.CustomIconActiveEffectOverlay = ActiveEffectOverlay

local GOLD = { 1, 0.776, 0.376, 0.7 }
local LIGHTS_POTENTIAL_SPELLS = { [1236616] = true }
local RECKLESSNESS_SPELLS = { [1236994] = true }
local DEVOURED_DREAMS_SPELLS = { [1239479] = true }
local INVISIBILITY_SPELLS = {
    [371125] = true,
    [431424] = true,
    [371133] = true,
    [371134] = true,
    [1236551] = true,
}
local KNOWN_ITEMS = {
    [241308] = { duration = 30, spells = LIGHTS_POTENTIAL_SPELLS, procGlow = true },
    [241309] = { duration = 30, spells = LIGHTS_POTENTIAL_SPELLS, procGlow = true },
    [245897] = { duration = 30, spells = LIGHTS_POTENTIAL_SPELLS, procGlow = true },
    [245898] = { duration = 30, spells = LIGHTS_POTENTIAL_SPELLS, procGlow = true },
    [241288] = { duration = 30, spells = RECKLESSNESS_SPELLS, procGlow = true },
    [241289] = { duration = 30, spells = RECKLESSNESS_SPELLS, procGlow = true },
    [245902] = { duration = 30, spells = RECKLESSNESS_SPELLS, procGlow = true },
    [245903] = { duration = 30, spells = RECKLESSNESS_SPELLS, procGlow = true },
    [241294] = { duration = 10, spells = DEVOURED_DREAMS_SPELLS, procGlow = true },
    [241302] = { duration = 18, spells = INVISIBILITY_SPELLS },
    [241303] = { duration = 18, spells = INVISIBILITY_SPELLS },
}

local states = {}
local triggerMap = {}
local unresolvedIcons = {}
local itemSpellCache = {}
local triggerMapDirty = true
local nextToken = 0

local function IsPublicNumber(value)
    if type(value) ~= "number" then return false end
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

local function NormalizeNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    local numberValue = tonumber(value)
    if not numberValue or numberValue <= 0 then return nil end
    return numberValue
end

local function NormalizeItemID(value)
    local itemID = NormalizeNumber(value)
    return itemID and math.floor(itemID) or nil
end

local function GetDynamicDB()
    local profile = DDingUI.db and DDingUI.db.profile
    return profile and profile.dynamicIcons
end

local function GetIconData(iconKey)
    local db = GetDynamicDB()
    return db and db.iconData and db.iconData[iconKey]
end

local function GetConfiguredDuration(iconData)
    if type(iconData) ~= "table" or iconData.type ~= "item" then return nil end
    local settings = iconData.settings
    return type(settings) == "table" and NormalizeNumber(settings.activeEffectDuration) or nil
end

local function ForEachItemID(iconData, callback)
    if type(iconData) ~= "table" or type(callback) ~= "function" then return end
    local seen = {}
    local function Visit(value)
        local itemID = NormalizeItemID(value)
        if not itemID or seen[itemID] then return end
        seen[itemID] = true
        callback(itemID)
    end

    Visit(iconData.id)
    local settings = iconData.settings
    local fallbacks = type(settings) == "table" and settings.fallbackItems
    if type(fallbacks) == "string" then
        for value in string.gmatch(fallbacks, "(%d+)") do
            Visit(value)
        end
    elseif type(fallbacks) == "table" then
        for key, value in pairs(fallbacks) do
            if type(key) == "number" and value == true then
                Visit(key)
            else
                Visit(value)
            end
        end
    end
end

local function GetKnownEffect(iconData)
    local effect
    ForEachItemID(iconData, function(itemID)
        effect = effect or KNOWN_ITEMS[itemID]
    end)
    return effect
end

local function GetProcDuration(iconData)
    local effect = GetKnownEffect(iconData)
    return effect and effect.procGlow == true and effect.duration or nil
end

local function GetActiveEffectDuration(iconData)
    return GetConfiguredDuration(iconData) or GetProcDuration(iconData)
end

local function GetDisplayMode(iconData)
    local settings = type(iconData) == "table" and iconData.settings
    local mode = type(settings) == "table" and settings.activeEffectDisplayMode
    if mode == "swipe" or mode == "glow" or mode == "hidden" then
        return mode
    end
    return "both"
end

local function AddTrigger(spellID, iconKey)
    if not IsPublicNumber(spellID) or not iconKey then return false end
    local icons = triggerMap[spellID]
    if not icons then
        icons = {}
        triggerMap[spellID] = icons
    end
    icons[iconKey] = true
    return true
end

local function ResolveItemSpell(itemID)
    local cached = itemSpellCache[itemID]
    if cached then return cached end
    if not (C_Item and C_Item.GetItemSpell) then return nil end

    local _, spellID = C_Item.GetItemSpell(itemID)
    if IsPublicNumber(spellID) then
        itemSpellCache[itemID] = spellID
        return spellID
    end
    return nil
end

local function AddItemTriggers(iconKey, itemID)
    local added = false
    local known = KNOWN_ITEMS[itemID]
    if known then
        for spellID in pairs(known.spells) do
            added = AddTrigger(spellID, iconKey) or added
        end
    end
    local itemSpellID = ResolveItemSpell(itemID)
    if itemSpellID then
        added = AddTrigger(itemSpellID, iconKey) or added
    end
    return added
end

local function BuildTriggerMap()
    triggerMap = {}
    unresolvedIcons = {}
    triggerMapDirty = false

    local db = GetDynamicDB()
    local iconDataByKey = db and db.iconData
    if type(iconDataByKey) ~= "table" then
        states = {}
        return
    end

    for iconKey, iconData in pairs(iconDataByKey) do
        if GetActiveEffectDuration(iconData) then
            local added = false
            ForEachItemID(iconData, function(itemID)
                added = AddItemTriggers(iconKey, itemID) or added
            end)
            if not added then
                unresolvedIcons[iconKey] = true
            end
        else
            states[iconKey] = nil
        end
    end
end

local function ResolvePendingItemSpells()
    for iconKey in pairs(unresolvedIcons) do
        local iconData = GetIconData(iconKey)
        local added = false
        if GetActiveEffectDuration(iconData) then
            ForEachItemID(iconData, function(itemID)
                added = AddItemTriggers(iconKey, itemID) or added
            end)
        end
        if added or not GetActiveEffectDuration(iconData) then
            unresolvedIcons[iconKey] = nil
        end
    end
end

local function FindCooldownText(cooldown)
    if not (cooldown and cooldown.GetRegions) then return nil end
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            return region
        end
    end
    return nil
end

local function ResolveColor(settings)
    local mode = settings and settings.activeSwipeMode
    if mode == "hidden" or (settings and settings.activeStateMode == "hide") then
        return nil
    end
    if mode == "class" then
        local _, classFile = UnitClass("player")
        local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if color then
            return color.r, color.g, color.b, color.a or 0.7
        end
    elseif mode == "custom" and type(settings.activeSwipeColor) == "table" then
        local color = settings.activeSwipeColor
        return color.r or color[1] or GOLD[1],
            color.g or color[2] or GOLD[2],
            color.b or color[3] or GOLD[3],
            color.a or color[4] or GOLD[4]
    end
    return GOLD[1], GOLD[2], GOLD[3], GOLD[4]
end

local function SyncFrameLevels(frame, overlay)
    local baseLevel = frame:GetFrameLevel() or 0
    overlay.frame:SetFrameLevel(baseLevel + 20)
    overlay.cooldown:SetFrameLevel(baseLevel + 21)
    overlay.borderFrame:SetFrameLevel(baseLevel + 22)
    if frame.border then frame.border:SetFrameLevel(baseLevel + 22) end
    if frame.Applications then frame.Applications:SetFrameLevel(baseLevel + 23) end
end

local function CopyIconTexture(frame, overlay)
    local source = frame.icon or frame.Icon
    if not (source and source.GetTexture) then return end
    local texture = source:GetTexture()
    if texture then
        overlay.icon:SetTexture(texture)
        overlay.icon:SetTexCoord(source:GetTexCoord())
        overlay.icon:SetDesaturated(false)
    end
end

local function SyncManagedBorder(frame, iconData, overlay)
    local source = frame._ddBorders
    if not frame._ddIsManaged or type(source) ~= "table" or #source < 4 then
        overlay.borderFrame:SetAlpha(0)
        return
    end

    local settings = iconData.settings or {}
    local groupSettings = frame._groupSettings
        or (frame._ddContainerRef and frame._ddContainerRef._groupSettings)
        or {}
    local color = settings.activeBorderEnabled == true and settings.activeBorderColor
        or groupSettings.borderColor
        or { 0, 0, 0, 1 }
    local r = color.r or color[1] or 0
    local g = color.g or color[2] or 0
    local b = color.b or color[3] or 0
    local a = color.a or color[4] or 1
    local visible = false
    for index = 1, 4 do
        local sourceLine = source[index]
        local targetLine = overlay.borders[index]
        if sourceLine and targetLine then
            targetLine:SetColorTexture(r, g, b, a)
            if index <= 2 then
                targetLine:SetHeight(sourceLine:GetHeight())
            else
                targetLine:SetWidth(sourceLine:GetWidth())
            end
            visible = visible or sourceLine:IsShown()
        end
    end
    overlay.borderFrame:SetAlpha(visible and 1 or 0)
end

local function SyncTextStyle(frame, iconData, overlay)
    local settings = iconData.settings or {}
    local groupSettings = frame._groupSettings
        or (frame._ddContainerRef and frame._ddContainerRef._groupSettings)
        or {}
    local hideText = groupSettings.hideDurationText == true
    if settings.activeDurationMode == "show" then
        hideText = false
    elseif settings.activeDurationMode == "hide" then
        hideText = true
    end

    overlay.cooldown:SetHideCountdownNumbers(hideText)
    overlay.cooldown.noCooldownCount = hideText and true or nil
    local overlayText = FindCooldownText(overlay.cooldown)
    if not overlayText then return false end
    if hideText then
        overlayText:Hide()
        return true
    end

    local sourceText = FindCooldownText(frame.cooldown or frame.Cooldown)
    if sourceText then
        local font, size, flags = sourceText:GetFont()
        if font and size then overlayText:SetFont(font, size, flags) end
        overlayText:SetTextColor(sourceText:GetTextColor())
        overlayText:SetShadowColor(sourceText:GetShadowColor())
        overlayText:SetShadowOffset(sourceText:GetShadowOffset())
        local point, _, relativePoint, offsetX, offsetY = sourceText:GetPoint(1)
        if point then
            overlayText:ClearAllPoints()
            overlayText:SetPoint(point, overlay.icon, relativePoint or point, offsetX or 0, offsetY or 0)
        end
    end
    overlayText:Show()
    return true
end

local function RefreshIcon(iconKey)
    local customIcons = DDingUI.CustomIcons
    if customIcons and customIcons.RefreshDynamicIcon then
        customIcons:RefreshDynamicIcon(iconKey)
    end
end

local function StartWindow(iconKey)
    local iconData = GetIconData(iconKey)
    local duration = GetActiveEffectDuration(iconData)
    if not duration then return false end

    nextToken = nextToken + 1
    local token = nextToken
    local startTime = GetTime()
    states[iconKey] = {
        token = token,
        startTime = startTime,
        duration = duration,
        expirationTime = startTime + duration,
    }
    C_Timer.After(duration + 0.05, function()
        local state = states[iconKey]
        if state and state.token == token and state.expirationTime <= GetTime() then
            states[iconKey] = nil
            RefreshIcon(iconKey)
        end
    end)
    return true
end

function ActiveEffectOverlay:MarkDirty()
    triggerMapDirty = true
end

function ActiveEffectOverlay:IsConsumableItem(itemID)
    itemID = NormalizeItemID(itemID)
    if not itemID then return false end
    if KNOWN_ITEMS[itemID] then return true end
    if not (C_Item and C_Item.GetItemInfoInstant) then return false end

    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    if not IsPublicNumber(classID) then return false end
    local consumableClass = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
    return classID == consumableClass
end

function ActiveEffectOverlay:SupportsProcGlow(itemID, settings)
    return GetProcDuration({ id = itemID, settings = settings }) ~= nil
end

function ActiveEffectOverlay:SupportsActiveEffect(itemID, settings)
    return GetActiveEffectDuration({ type = "item", id = itemID, settings = settings }) ~= nil
end

function ActiveEffectOverlay:ShouldShowSwipe(iconData)
    local mode = GetDisplayMode(iconData)
    return mode == "both" or mode == "swipe"
end

function ActiveEffectOverlay:ShouldShowGlow(iconData)
    local mode = GetDisplayMode(iconData)
    return mode == "both" or mode == "glow"
end

function ActiveEffectOverlay:IsProcActive(iconData)
    if type(iconData) ~= "table" then return false end
    local state = states[iconData.key]
    return state ~= nil and state.expirationTime > GetTime()
end

function ActiveEffectOverlay:GetDefaultDuration(itemID, settings)
    local duration
    ForEachItemID({ id = itemID, settings = settings }, function(candidateID)
        if not duration and KNOWN_ITEMS[candidateID] then
            duration = KNOWN_ITEMS[candidateID].duration
        end
    end)
    return duration or 30
end

function ActiveEffectOverlay:GetDuration(iconKey)
    return GetConfiguredDuration(GetIconData(iconKey))
end

function ActiveEffectOverlay:SetDuration(iconKey, duration)
    local iconData = GetIconData(iconKey)
    if type(iconData) ~= "table" or iconData.type ~= "item" then return false end
    if not self:IsConsumableItem(iconData.id) then return false end

    iconData.settings = iconData.settings or {}
    local normalized = duration and NormalizeNumber(duration) or nil
    if duration ~= nil and not normalized then return false end
    if iconData.settings.activeEffectDuration == normalized then return false end

    iconData.settings.activeEffectDuration = normalized
    states[iconKey] = nil
    self:MarkDirty()
    RefreshIcon(iconKey)
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    return true
end

function ActiveEffectOverlay:ClearIcon(iconKey)
    if not iconKey then return end
    states[iconKey] = nil
    self:MarkDirty()
end

function ActiveEffectOverlay:PrepareFrame(frame)
    if not frame or frame._ddActiveEffectOverlay then return end
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:SetAlpha(0)
    holder:EnableMouse(false)

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(holder)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    cooldown:SetAllPoints(holder)
    cooldown:SetDrawEdge(false)
    if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
    cooldown:SetDrawSwipe(true)
    cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    cooldown:SetSwipeColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetReverse(false)

    local borderFrame = CreateFrame("Frame", nil, holder)
    borderFrame:SetAllPoints(holder)
    borderFrame:EnableMouse(false)
    borderFrame:SetAlpha(0)
    local top = borderFrame:CreateTexture(nil, "OVERLAY")
    top:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    local bottom = borderFrame:CreateTexture(nil, "OVERLAY")
    bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    local left = borderFrame:CreateTexture(nil, "OVERLAY")
    left:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    local right = borderFrame:CreateTexture(nil, "OVERLAY")
    right:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)

    frame._ddActiveEffectOverlay = {
        frame = holder,
        icon = icon,
        cooldown = cooldown,
        borderFrame = borderFrame,
        borders = { top, bottom, left, right },
    }
    SyncFrameLevels(frame, frame._ddActiveEffectOverlay)
end

function ActiveEffectOverlay:ResetFrame(frame)
    if not frame then return end
    local wasItem = frame._type == "item"
    local overlay = frame._ddActiveEffectOverlay
    if overlay then
        overlay.token = nil
        overlay.styleRetryPending = nil
        overlay.cooldown:Clear()
        overlay.frame:SetAlpha(0)
    end
    frame._ddActiveEffectSignature = nil
    if wasItem then self:MarkDirty() end
end

function ActiveEffectOverlay:ApplyFrame(frame, iconData)
    if not frame then return end
    self:PrepareFrame(frame)
    local overlay = frame._ddActiveEffectOverlay
    local duration = GetActiveEffectDuration(iconData)
    if not duration then
        if overlay.token then
            overlay.token = nil
            overlay.cooldown:Clear()
        end
        overlay.frame:SetAlpha(0)
        return
    end

    local settings = iconData.settings or {}
    local signature = tostring(iconData.id) .. ":" .. tostring(settings.fallbackItems or "") .. ":" .. tostring(duration)
    if frame._ddActiveEffectSignature ~= signature then
        frame._ddActiveEffectSignature = signature
        self:MarkDirty()
    end

    local state = states[iconData.key or frame._iconKey]
    if state and state.expirationTime <= GetTime() then
        states[iconData.key or frame._iconKey] = nil
        state = nil
    end
    if not state then
        if overlay.token then
            overlay.token = nil
            overlay.cooldown:Clear()
        end
        overlay.frame:SetAlpha(0)
        return
    end

    frame._ddInactiveGray = nil
    frame._ddForcedInactiveGray = nil
    frame._ddInactiveAlpha = nil
    frame._ddInactivePlaceholder = nil
    frame._ddManagedAuraExpired = nil
    frame._ddCombatVisible = nil
    if DDingUI.CustomIcons and DDingUI.CustomIcons.RestoreActiveIconVisual then
        DDingUI.CustomIcons.RestoreActiveIconVisual(frame)
    end
    frame._ddCustomIconActive = true
    frame._ddCustomIconReady = false
    SyncFrameLevels(frame, overlay)
    CopyIconTexture(frame, overlay)
    local displayMode = GetDisplayMode(iconData)
    local r, g, b, a
    if self:ShouldShowSwipe(iconData) then
        r, g, b, a = ResolveColor(settings)
    end
    if r then
        overlay.cooldown:SetDrawSwipe(true)
        overlay.cooldown:SetSwipeColor(r, g, b, a)
    else
        overlay.cooldown:SetDrawSwipe(false)
    end
    overlay.icon:SetAlpha(r and 1 or 0)
    overlay.cooldown:SetAlpha(r and 1 or 0)
    if overlay.token ~= state.token then
        overlay.token = state.token
        overlay.cooldown:SetCooldown(state.startTime, state.duration)
        local customizer = DDingUI.IconCustomization
        if customizer and customizer.ApplyThresholdFormatter then
            customizer:ApplyThresholdFormatter(overlay.cooldown, settings)
        end
    end
    local styled = SyncTextStyle(frame, iconData, overlay)
    SyncManagedBorder(frame, iconData, overlay)
    if not styled and not overlay.styleRetryPending then
        overlay.styleRetryPending = true
        C_Timer.After(0, function()
            overlay.styleRetryPending = nil
            if overlay.token == state.token then
                SyncTextStyle(frame, iconData, overlay)
            end
        end)
    end
    overlay.frame:SetAlpha(displayMode == "hidden" and 0 or 1)
end

function ActiveEffectOverlay:SyncTextStyle(frame, iconData)
    local overlay = frame and frame._ddActiveEffectOverlay
    if overlay and overlay.token then
        iconData = iconData or GetIconData(frame._iconKey)
        if not iconData then return end
        SyncTextStyle(frame, iconData, overlay)
        SyncManagedBorder(frame, iconData, overlay)
    end
end

function ActiveEffectOverlay:HandleSpellcast(spellID)
    if not IsPublicNumber(spellID) then return false end
    if triggerMapDirty then BuildTriggerMap() end

    local icons = triggerMap[spellID]
    if not icons and next(unresolvedIcons) then
        ResolvePendingItemSpells()
        icons = triggerMap[spellID]
    end
    if not icons then return false end

    local changed = false
    for iconKey in pairs(icons) do
        changed = StartWindow(iconKey) or changed
    end
    return changed
end
