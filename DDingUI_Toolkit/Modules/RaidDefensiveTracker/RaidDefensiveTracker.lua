-- DDingUI Toolkit - received support/raid buff tracker (12.1 AuraContainer)

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib

local DEFAULT_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local DEFAULT_ICON = 134400
local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local GROUP_KEY = "raidDefensives"
local DORMANT_SPELL_ID = 599999
local MAX_FRAMES = 16
local PREVIEW_COUNT = 4
local AddAuraSound = C_UnitAuras and C_UnitAuras.AddAuraSound
local RemoveAuraSound = C_UnitAuras and C_UnitAuras.RemoveAuraSound
local IsAddOnRestrictionActive = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
local AURA_SOUND_TRIGGER_ADDED = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
local ADDON_RESTRICTION = Enum.AddOnRestrictionType

local EFFECTS = {
    { key = "innervate", ids = { 29166 }, previewSpellID = 29166 },
    -- Time Spiral uses one class-specific recipient aura, not cast spell 374968.
    { key = "timeSpiral", ids = {
        375226, 375229, 375230, 375234, 375238, 375240, 375252,
        375253, 375254, 375255, 375256, 375257, 375258,
    }, previewSpellID = 375234 },
    { key = "spatialParadox", ids = { 406732, 406789 }, previewSpellID = 406789, maxFrames = 2 },
    { key = "powerInfusion", ids = { 10060 }, previewSpellID = 10060 },
    { key = "stampedingRoar", ids = { 77764 }, previewSpellID = 106898 },
    { key = "windRush", ids = { 192082 }, previewSpellID = 192077 },
    { key = "piercingHowl", ids = { 12323 }, previewSpellID = 12323 },
    { key = "antiMagicZone", ids = { 145629 }, previewSpellID = 145629 },
    { key = "darkness", ids = { 209426 }, previewSpellID = 209426 },
    { key = "zephyr", ids = { 374227 }, previewSpellID = 374227 },
    { key = "auraMastery", ids = { 31821, 317929 }, previewSpellID = 31821 },
    { key = "massBarrier", ids = { 414661, 414662, 414663 }, previewSpellID = 414661 },
    { key = "powerWordBarrier", ids = { 81782 }, previewSpellID = 81782 },
    { key = "spiritLink", ids = { 325174 }, previewSpellID = 325174 },
    { key = "rallyingCry", ids = { 97463 }, previewSpellID = 97463 },
}

local COLOR_DEFAULTS = {
    border = { 0.18, 0.76, 0.92, 0.95 },
    duration = { 1, 1, 1, 1 },
}

local DEFAULT_POSITION = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -250,
}

local RaidDefensiveTracker = {}
ns.RaidDefensiveTracker = RaidDefensiveTracker

local anchorFrame
local container
local previewFrame
local dragSurface
local buttonRegions = setmetatable({}, { __mode = "k" })
local enteredWorld = false
local applyPending = false
local editPreview = false
local configPreview = false
local manualPreview = false
local directDragging = false
local auraSoundRegistrations = {}
local auraSoundsPending = false

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function GetColor(value, fallback)
    value = type(value) == "table" and value or fallback
    return tonumber(value[1]) or fallback[1],
        tonumber(value[2]) or fallback[2],
        tonumber(value[3]) or fallback[3],
        tonumber(value[4]) or fallback[4] or 1
end

local function GetIconGeometry(db)
    local size = Clamp(db and db.iconSize, 20, 96, 44)
    local cropX = Clamp(db and db.iconCropX, 0, 45, 7) / 100
    local cropY = Clamp(db and db.iconCropY, 0, 45, 7) / 100
    local width = math.max(1, size * (1 - (cropX * 2)))
    local height = math.max(1, size * (1 - (cropY * 2)))
    return size, width, height, cropX, cropY
end

local function GetIconTexCoords(db)
    local _, _, _, cropX, cropY = GetIconGeometry(db)
    local zoom = Clamp(db and db.iconZoom, 0, 40, 0) / 100
    local visibleX = 1 - (cropX * 2)
    local visibleY = 1 - (cropY * 2)
    local zoomX = visibleX * zoom
    local zoomY = visibleY * zoom
    return cropX + zoomX, 1 - cropX - zoomX,
        cropY + zoomY, 1 - cropY - zoomY
end

local function CopyDefaultPosition()
    return {
        point = DEFAULT_POSITION.point,
        relativePoint = DEFAULT_POSITION.relativePoint,
        x = DEFAULT_POSITION.x,
        y = DEFAULT_POSITION.y,
    }
end

local function EnsureDB()
    local profile = ns.db and ns.db.profile
    if not profile then return nil end

    if type(profile.RaidDefensiveTracker) ~= "table" then
        local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.RaidDefensiveTracker
        profile.RaidDefensiveTracker = defaults and ns:DeepCopy(defaults) or {}
    end

    local db = profile.RaidDefensiveTracker
    if type(db.spells) ~= "table" then db.spells = {} end
    if type(db.sounds) ~= "table" then db.sounds = {} end
    if db.iconZoom == nil then db.iconZoom = 0 end
    if db.iconCropX == nil then db.iconCropX = 7 end
    if db.iconCropY == nil then db.iconCropY = 7 end
    if db.soundFile == nil then db.soundFile = "" end
    if type(db.soundCustomPath) ~= "string" then db.soundCustomPath = "" end
    if type(db.soundChannel) ~= "string" then db.soundChannel = "Master" end
    if db.locked == nil then db.locked = true end
    if type(db.position) ~= "table" then db.position = CopyDefaultPosition() end

    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.RaidDefensiveTracker
    local defaultSpells = defaults and defaults.spells
    local defaultSounds = defaults and defaults.sounds
    for _, effect in ipairs(EFFECTS) do
        if db.spells[effect.key] == nil then
            db.spells[effect.key] = not defaultSpells or defaultSpells[effect.key] ~= false
        end
        if type(db.sounds[effect.key]) ~= "table" then
            local fallback = defaultSounds and defaultSounds[effect.key]
            db.sounds[effect.key] = fallback and ns:DeepCopy(fallback) or {
                soundFile = "",
                soundCustomPath = "",
                soundChannel = "Master",
            }
        end
    end
    return db
end

local function IsRestricted()
    if InCombatLockdown and InCombatLockdown() then return true end

    if UnitAffectingCombat then
        local ok, inCombat = pcall(UnitAffectingCombat, "player")
        if not ok or IsSecret(inCombat) then return true end
        if inCombat then return true end
    end

    if enteredWorld and C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or IsSecret(secret) then return true end
        if secret then return true end
    end

    return false
end

local function IsMovementRestricted()
    return InCombatLockdown and InCombatLockdown() or false
end

local function IsPreviewing()
    return editPreview or configPreview or manualPreview
end

local function IsDirectDragPreview()
    return configPreview or manualPreview
end

local function BuildSpellIDMap()
    local db = RaidDefensiveTracker.db or EnsureDB()
    local enabled = db and db.spells or {}
    local map = {}
    local frameCount = 0

    for _, effect in ipairs(EFFECTS) do
        if enabled[effect.key] ~= false then
            frameCount = frameCount + (effect.maxFrames or 1)
            for _, spellID in ipairs(effect.ids) do
                map[spellID] = true
            end
        end
    end

    if frameCount == 0 then
        map[DORMANT_SPELL_ID] = true
    end
    return map, frameCount
end

local function IsAuraSoundRestricted()
    if InCombatLockdown and InCombatLockdown() then return true end
    if not (IsAddOnRestrictionActive and ADDON_RESTRICTION) then return false end

    local function IsActive(restrictionType)
        if restrictionType == nil then return false end
        local ok, active = pcall(IsAddOnRestrictionActive, restrictionType)
        if not ok or IsSecret(active) then return true end
        return active == true
    end

    if IsActive(ADDON_RESTRICTION.Encounter) then return true end
    return IsActive(ADDON_RESTRICTION.ChallengeMode)
        and IsActive(ADDON_RESTRICTION.Combat)
end

local function ResolveAuraSound(settings)
    if type(settings) ~= "table" then return nil end

    local customPath = settings.soundCustomPath
    if type(customPath) == "string" and customPath ~= "" then
        if ns.IsValidSoundPath and ns:IsValidSoundPath(customPath) then
            return customPath
        end
        return nil
    end

    local soundFile = settings.soundFile
    if type(soundFile) == "number" and soundFile > 0 then return soundFile end
    if type(soundFile) == "string" and soundFile ~= "" then return soundFile end
    return nil
end

local function HasConfiguredAuraSound(settings)
    if type(settings) ~= "table" then return false end

    local customPath = settings.soundCustomPath
    if type(customPath) == "string" and customPath ~= "" then return true end

    local soundFile = settings.soundFile
    if type(soundFile) == "number" then return soundFile > 0 end
    return type(soundFile) == "string" and soundFile ~= ""
end

local VALID_SOUND_CHANNELS = {
    Master = true,
    SFX = true,
    Music = true,
    Ambience = true,
    Dialog = true,
}

local function BuildDesiredAuraSounds()
    local desired = {}
    local db = RaidDefensiveTracker.db or EnsureDB()
    if not (RaidDefensiveTracker.active and db) then return desired end

    for _, effect in ipairs(EFFECTS) do
        if db.spells[effect.key] ~= false then
            local individualSettings = db.sounds[effect.key]
            local settings = HasConfiguredAuraSound(individualSettings) and individualSettings or db
            local sound = ResolveAuraSound(settings)
            if sound then
                local channel = settings.soundChannel
                if not VALID_SOUND_CHANNELS[channel] then channel = "Master" end
                desired[effect.key] = {
                    sound = sound,
                    channel = channel,
                    signature = type(sound) .. ":" .. tostring(sound) .. ":" .. channel,
                }
            end
        end
    end
    return desired
end

local function RemoveAuraSoundRegistration(key)
    local registration = auraSoundRegistrations[key]
    if not registration then return end

    if RemoveAuraSound then
        for index = #registration.handles, 1, -1 do
            pcall(RemoveAuraSound, registration.handles[index])
        end
    end
    auraSoundRegistrations[key] = nil
end

local function RegisterAuraSound(effect, wanted)
    local handles = {}
    local info = {
        unitToken = "player",
        soundFileName = type(wanted.sound) == "string" and wanted.sound or nil,
        soundFileID = type(wanted.sound) == "number" and wanted.sound or nil,
        outputChannel = wanted.channel,
    }

    for _, spellID in ipairs(effect.ids) do
        info.spellID = spellID
        local ok, handle = pcall(AddAuraSound, AURA_SOUND_TRIGGER_ADDED, info)
        if not ok or IsSecret(handle) or handle == nil then
            for index = #handles, 1, -1 do
                if RemoveAuraSound then pcall(RemoveAuraSound, handles[index]) end
            end
            auraSoundsPending = true
            return false
        end
        handles[#handles + 1] = handle
    end

    auraSoundRegistrations[effect.key] = {
        signature = wanted.signature,
        handles = handles,
    }
    return true
end

local function ReconcileAuraSounds()
    if not AddAuraSound then return end

    local desired = BuildDesiredAuraSounds()
    for key, registration in pairs(auraSoundRegistrations) do
        local wanted = desired[key]
        if not wanted or wanted.signature ~= registration.signature then
            RemoveAuraSoundRegistration(key)
        end
    end

    auraSoundsPending = false
    if not enteredWorld then
        auraSoundsPending = next(desired) ~= nil
        return
    end

    local restricted = IsAuraSoundRestricted()
    for _, effect in ipairs(EFFECTS) do
        local wanted = desired[effect.key]
        if wanted and not auraSoundRegistrations[effect.key] then
            if restricted then
                auraSoundsPending = true
            else
                RegisterAuraSound(effect, wanted)
            end
        end
    end
end

local function ResolveSpellTexture(spellID)
    local texture
    if C_Spell and C_Spell.GetSpellTexture then
        texture = C_Spell.GetSpellTexture(spellID)
    elseif GetSpellTexture then
        texture = GetSpellTexture(spellID)
    end
    if IsSecret(texture) or texture == nil then return DEFAULT_ICON end
    return texture
end

local function SetBorderColor(regions, r, g, b, a)
    regions.borderTop:SetColorTexture(r, g, b, a)
    regions.borderBottom:SetColorTexture(r, g, b, a)
    regions.borderLeft:SetColorTexture(r, g, b, a)
    regions.borderRight:SetColorTexture(r, g, b, a)
end

local function ApplyBorder(regions, size, color)
    local r, g, b, a = GetColor(color, COLOR_DEFAULTS.border)
    SetBorderColor(regions, r, g, b, a)

    if regions.innerBorder then
        if size <= 0 then
            regions.borderTop:Hide()
            regions.borderBottom:Hide()
            regions.borderLeft:Hide()
            regions.borderRight:Hide()
            return
        end

        local width = regions.iconWidth or 44
        local height = regions.iconHeight or 44
        local anchor = regions.borderLayer or regions.button

        regions.borderTop:ClearAllPoints()
        regions.borderTop:SetSize(width, size)
        regions.borderTop:SetPoint("TOP", anchor, "TOP", 0, 0)

        regions.borderBottom:ClearAllPoints()
        regions.borderBottom:SetSize(width, size)
        regions.borderBottom:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)

        regions.borderLeft:ClearAllPoints()
        regions.borderLeft:SetSize(size, height)
        regions.borderLeft:SetPoint("LEFT", anchor, "LEFT", 0, 0)

        regions.borderRight:ClearAllPoints()
        regions.borderRight:SetSize(size, height)
        regions.borderRight:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)

        regions.borderTop:Show()
        regions.borderBottom:Show()
        regions.borderLeft:Show()
        regions.borderRight:Show()
        return
    end

    if size <= 0 then
        regions.borderFrame:Hide()
        return
    end

    regions.borderFrame:Show()
    regions.borderFrame:ClearAllPoints()
    regions.borderFrame:SetPoint("TOPLEFT", regions.button, "TOPLEFT", -size, size)
    regions.borderFrame:SetPoint("BOTTOMRIGHT", regions.button, "BOTTOMRIGHT", size, -size)

    regions.borderTop:SetHeight(size)
    regions.borderBottom:SetHeight(size)
    regions.borderLeft:SetWidth(size)
    regions.borderRight:SetWidth(size)
end

local function StyleButton(button)
    local regions = buttonRegions[button]
    local db = RaidDefensiveTracker.db
    if not regions or not db then return end

    local _, width, height = GetIconGeometry(db)
    local fontSize = Clamp(db.durationFontSize, 8, 36, 16)
    local borderSize = Clamp(db.borderSize, 0, 6, 1)
    local font = type(db.font) == "string" and db.font ~= "" and db.font or DEFAULT_FONT
    local outline = db.fontOutline or "OUTLINE"
    local left, right, top, bottom = GetIconTexCoords(db)

    button:SetSize(width, height)
    regions.iconWidth = width
    regions.iconHeight = height
    regions.icon:ClearAllPoints()
    regions.icon:SetSize(width, height)
    regions.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    regions.icon:SetTexCoord(left, right, top, bottom)
    if regions.borderLayer then
        regions.borderLayer:ClearAllPoints()
        regions.borderLayer:SetSize(width, height)
        regions.borderLayer:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
    -- Border styling must finish before Blizzard's secret duration regions are
    -- touched; a rejected duration write would otherwise skip the border.
    ApplyBorder(regions, borderSize, db.borderColor)
    regions.cooldown:SetDrawSwipe(db.showSwipe ~= false)
    regions.cooldown:SetReverse(true)
    regions.duration:SetFont(font, fontSize, outline)
end

local function CreateBorderRegions(parent, button)
    local regions = {
        button = button,
        borderFrame = parent,
    }

    regions.borderTop = parent:CreateTexture(nil, "OVERLAY")
    regions.borderTop:SetPoint("TOPLEFT")
    regions.borderTop:SetPoint("TOPRIGHT")

    regions.borderBottom = parent:CreateTexture(nil, "OVERLAY")
    regions.borderBottom:SetPoint("BOTTOMLEFT")
    regions.borderBottom:SetPoint("BOTTOMRIGHT")

    regions.borderLeft = parent:CreateTexture(nil, "OVERLAY")
    regions.borderLeft:SetPoint("TOPLEFT")
    regions.borderLeft:SetPoint("BOTTOMLEFT")

    regions.borderRight = parent:CreateTexture(nil, "OVERLAY")
    regions.borderRight:SetPoint("TOPRIGHT")
    regions.borderRight:SetPoint("BOTTOMRIGHT")
    return regions
end

local function InitializeAuraButton(button)
    local db = RaidDefensiveTracker.db or EnsureDB() or {}
    local _, width, height = GetIconGeometry(db)
    local fontSize = Clamp(db.durationFontSize, 8, 36, 16)
    local font = type(db.font) == "string" and db.font ~= "" and db.font or DEFAULT_FONT

    button:EnableMouse(false)
    button:SetSize(width, height)

    local regions = {}
    buttonRegions[button] = regions

    regions.icon = button:CreateTexture(nil, "ARTWORK")
    button:SetIcon(regions.icon)

    regions.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    regions.cooldown:SetAllPoints(button)
    regions.cooldown:SetDrawEdge(false)
    regions.cooldown:SetHideCountdownNumbers(true)
    if button.SetDurationCooldown then
        button:SetDurationCooldown(regions.cooldown)
    end

    -- Filled backing textures can be expanded to the screen by the 12.1 aura
    -- provider. Keep four explicitly sized inner lines on an isolated frame.
    regions.borderLayer = CreateFrame("Frame", nil, button)
    regions.borderLayer:SetSize(width, height)
    regions.borderLayer:SetPoint("CENTER", button, "CENTER", 0, 0)
    regions.borderLayer:SetFrameLevel(regions.cooldown:GetFrameLevel() + 1)
    regions.innerBorder = true
    regions.borderTop = regions.borderLayer:CreateTexture(nil, "OVERLAY")
    regions.borderBottom = regions.borderLayer:CreateTexture(nil, "OVERLAY")
    regions.borderLeft = regions.borderLayer:CreateTexture(nil, "OVERLAY")
    regions.borderRight = regions.borderLayer:CreateTexture(nil, "OVERLAY")

    regions.textLayer = CreateFrame("Frame", nil, button)
    regions.textLayer:SetAllPoints(button)
    regions.textLayer:SetFrameLevel(regions.cooldown:GetFrameLevel() + 2)

    regions.duration = regions.textLayer:CreateFontString(nil, "OVERLAY")
    regions.duration:SetPoint("CENTER", button, "CENTER", 0, 0)
    regions.duration:SetJustifyH("CENTER")
    regions.duration:SetFont(font, fontSize, db.fontOutline or "OUTLINE")
    regions.duration:SetTextColor(GetColor(db.durationTextColor, COLOR_DEFAULTS.duration))
    regions.duration:SetShown(db.showDuration ~= false)
    if button.SetDurationText then
        -- SetDurationText marks text, alpha, and vertex color as secret. Configure
        -- those properties first; only font changes remain safe afterward.
        button:SetDurationText(regions.duration)
    end

    StyleButton(button)
end

local function GetFlowSettings(direction)
    if direction == "LEFT" then
        return "RIGHT", "Horizontal", "Left", "Down"
    elseif direction == "UP" then
        return "BOTTOM", "Vertical", "Right", "Up"
    elseif direction == "DOWN" then
        return "TOP", "Vertical", "Right", "Down"
    end
    return "LEFT", "Horizontal", "Right", "Down"
end

local function ApplyGrowth()
    if not container or not anchorFrame then return end

    local db = RaidDefensiveTracker.db or {}
    local point, axis, horizontal, vertical = GetFlowSettings(db.growDirection)
    container:ClearAllPoints()
    container:SetPoint(point, anchorFrame, point)

    local axisValues = AnchorUtil and AnchorUtil.FlowLayoutAxis
    local directionValues = AnchorUtil and AnchorUtil.FlowDirection
    local setAxis = container.SetFlowLayoutAxis or container.SetAuraLayoutAxis
    local setAnchor = container.SetFlowLayoutAnchorPoint or container.SetAuraLayoutAnchorPoint
    local setGrowth = container.SetFlowLayoutGrowthDirection or container.SetAuraLayoutGrowthDirection

    if setAxis and axisValues and axisValues[axis] then
        setAxis(container, axisValues[axis])
    end
    if setAnchor then
        setAnchor(container, point)
    end
    if setGrowth and directionValues and directionValues[horizontal] and directionValues[vertical] then
        setGrowth(container, directionValues[horizontal], directionValues[vertical])
    end
end

local function ApplyContainerConfig()
    if not container then return false end
    if IsRestricted() then
        applyPending = true
        return false
    end

    local db = RaidDefensiveTracker.db or EnsureDB()
    if not db then return false end

    local map, count = BuildSpellIDMap()
    local _, width, height = GetIconGeometry(db)
    local spacing = Clamp(db.spacing, 0, 24, 4)

    local ok = pcall(function()
        -- Aura groups keep their parsed candidate set while live. Re-showing the
        -- container asks Blizzard's mixin to parse the updated include set now.
        container:Hide()
        container:SetAuraGroupCandidateFilters(GROUP_KEY, { includeSpellIDs = map })
        container:SetAuraGroupMaxFrameCount(GROUP_KEY, count)
        container:SetAuraGroupLayout(GROUP_KEY, {
            elementWidth = width,
            elementHeight = height,
            elementSpacing = spacing,
        })
        ApplyGrowth()
    end)

    -- A partial failure must not leave the display hidden for the session.
    if not pcall(container.Show, container) then
        ok = false
    end

    for button in pairs(buttonRegions) do
        if not pcall(StyleButton, button) then
            ok = false
        end
    end

    if not pcall(container.SetAlpha, container, IsPreviewing() and 0 or 1) then
        ok = false
    end

    applyPending = not ok
    return ok
end

local function EnsureContainer()
    if container then return true end
    if not anchorFrame or IsRestricted() then
        applyPending = true
        return false
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn
        and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
    then
        local ok, loaded = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        if not ok or not loaded then
            applyPending = true
            return false
        end
    end

    local map = BuildSpellIDMap()
    local db = RaidDefensiveTracker.db or EnsureDB() or {}
    local _, width, height = GetIconGeometry(db)
    local spacing = Clamp(db.spacing, 0, 24, 4)

    local created
    local ok = pcall(function()
        created = CreateFrame("AuraContainer", nil, anchorFrame, "CustomAuraContainerTemplate")
        created:SetSize(1, 1)
        created:EnableMouse(false)
        container = created
        ApplyGrowth()
        created:AddAuraGroup(GROUP_KEY, "HELPFUL", {
            maxFrameCount = MAX_FRAMES,
            candidateFilters = { includeSpellIDs = map },
            initializeFrame = InitializeAuraButton,
            layout = {
                elementWidth = width,
                elementHeight = height,
                elementSpacing = spacing,
            },
        })
        created:SetUnit("player")
        created:UpdateAllAuras()
    end)

    if not ok then
        if created then created:Hide() end
        container = nil
        applyPending = true
        return false
    end

    applyPending = false
    return true
end

local function CreatePreviewIcon(parent, spellID, seconds)
    local iconFrame = CreateFrame("Frame", nil, parent)
    iconFrame.button = iconFrame

    iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.icon:SetAllPoints()
    iconFrame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    iconFrame.icon:SetTexture(ResolveSpellTexture(spellID))

    iconFrame.shade = iconFrame:CreateTexture(nil, "OVERLAY")
    iconFrame.shade:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
    iconFrame.shade:SetPoint("BOTTOMRIGHT", iconFrame, "CENTER", 0, 0)
    iconFrame.shade:SetColorTexture(0, 0, 0, 0.42)

    iconFrame.duration = iconFrame:CreateFontString(nil, "OVERLAY")
    iconFrame.duration:SetPoint("CENTER")
    iconFrame.duration:SetFont(DEFAULT_FONT, 16, "OUTLINE")
    iconFrame.duration:SetText(tostring(seconds))

    iconFrame.borderFrame = CreateFrame("Frame", nil, iconFrame)
    iconFrame.borderFrame:SetAllPoints(iconFrame)
    local borders = CreateBorderRegions(iconFrame.borderFrame, iconFrame)
    iconFrame.borderTop = borders.borderTop
    iconFrame.borderBottom = borders.borderBottom
    iconFrame.borderLeft = borders.borderLeft
    iconFrame.borderRight = borders.borderRight
    return iconFrame
end

local function RefreshConfigPosition()
    local function Refresh()
        local config = ns.ConfigUI
        if config and config.IsShown and config:IsShown() and config.RefreshCurrentPanel then
            config:RefreshCurrentPanel()
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Refresh)
    else
        Refresh()
    end
end

local function SyncEditModeMover()
    local movers = ns.ToolkitMovers
    if movers and movers.SyncFromTarget then
        movers:SyncFromTarget("RaidDefensiveTracker", anchorFrame)
    end
end

local function SaveDirectPosition()
    local db = RaidDefensiveTracker.db or EnsureDB()
    if not (db and anchorFrame) then return end

    local centerX, centerY = anchorFrame:GetCenter()
    local uiScale = UIParent:GetEffectiveScale()
    local frameScale = anchorFrame:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetSize()
    if not (centerX and centerY and uiScale and uiScale > 0 and frameScale and frameScale > 0) then
        return
    end

    local relativeScale = frameScale / uiScale
    local screenX = (centerX * relativeScale) - (screenWidth / 2)
    local screenY = (centerY * relativeScale) - (screenHeight / 2)
    local x = math.floor((screenX / relativeScale) + 0.5)
    local y = math.floor((screenY / relativeScale) + 0.5)

    db.position = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = x,
        y = y,
    }
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    SyncEditModeMover()
    RefreshConfigPosition()
end

local function UpdateDragSurfaceGeometry()
    if not (dragSurface and previewFrame and previewFrame.icons) then return end

    local db = RaidDefensiveTracker.db or {}
    local _, width, height = GetIconGeometry(db)
    local spacing = Clamp(db.spacing, 0, 24, 4)
    local horizontalTotal = (PREVIEW_COUNT * width) + ((PREVIEW_COUNT - 1) * spacing) + 8
    local verticalTotal = (PREVIEW_COUNT * height) + ((PREVIEW_COUNT - 1) * spacing) + 8
    local direction = db.growDirection or "RIGHT"

    dragSurface:ClearAllPoints()
    if direction == "LEFT" then
        dragSurface:SetSize(horizontalTotal, height + 8)
        dragSurface:SetPoint("RIGHT", anchorFrame, "CENTER", (width / 2) + 4, 0)
    elseif direction == "UP" then
        dragSurface:SetSize(width + 8, verticalTotal)
        dragSurface:SetPoint("BOTTOM", anchorFrame, "CENTER", 0, -(height / 2) - 4)
    elseif direction == "DOWN" then
        dragSurface:SetSize(width + 8, verticalTotal)
        dragSurface:SetPoint("TOP", anchorFrame, "CENTER", 0, (height / 2) + 4)
    else
        dragSurface:SetSize(horizontalTotal, height + 8)
        dragSurface:SetPoint("LEFT", anchorFrame, "CENTER", -(width / 2) - 4, 0)
    end
end

local function UpdateDragState()
    if not dragSurface then return end
    local db = RaidDefensiveTracker.db or EnsureDB()
    local canDrag = IsDirectDragPreview() and db and db.locked == false
        and not IsMovementRestricted()

    if directDragging and not canDrag then
        anchorFrame:StopMovingOrSizing()
        directDragging = false
        SaveDirectPosition()
    end
    dragSurface:EnableMouse(canDrag == true)
    dragSurface:SetShown(canDrag == true)
end

local function LayoutPreview()
    if not previewFrame or not anchorFrame then return end
    local db = RaidDefensiveTracker.db or {}
    local _, width, height = GetIconGeometry(db)
    local spacing = Clamp(db.spacing, 0, 24, 4)
    local direction = db.growDirection or "RIGHT"
    local left, right, top, bottom = GetIconTexCoords(db)

    for index, iconFrame in ipairs(previewFrame.icons) do
        iconFrame:SetSize(width, height)
        iconFrame.icon:SetTexCoord(left, right, top, bottom)
        iconFrame:ClearAllPoints()
        if index == 1 then
            iconFrame:SetPoint("CENTER", anchorFrame, "CENTER")
        else
            local previous = previewFrame.icons[index - 1]
            if direction == "LEFT" then
                iconFrame:SetPoint("RIGHT", previous, "LEFT", -spacing, 0)
            elseif direction == "UP" then
                iconFrame:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
            elseif direction == "DOWN" then
                iconFrame:SetPoint("TOP", previous, "BOTTOM", 0, -spacing)
            else
                iconFrame:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
            end
        end

        iconFrame.duration:SetFont(
            type(db.font) == "string" and db.font ~= "" and db.font or DEFAULT_FONT,
            Clamp(db.durationFontSize, 8, 36, 16),
            db.fontOutline or "OUTLINE"
        )
        iconFrame.duration:SetTextColor(GetColor(db.durationTextColor, COLOR_DEFAULTS.duration))
        iconFrame.duration:SetShown(db.showDuration ~= false)
        ApplyBorder(iconFrame, Clamp(db.borderSize, 0, 6, 1), db.borderColor)
    end
    UpdateDragSurfaceGeometry()
end

local function RefreshVisibility()
    if not anchorFrame then return end
    local preview = IsPreviewing()

    if previewFrame then previewFrame:SetShown(preview) end
    if container then pcall(container.SetAlpha, container, preview and 0 or 1) end
    UpdateDragState()

    if RaidDefensiveTracker.active or preview then
        anchorFrame:Show()
    else
        anchorFrame:Hide()
    end
end

function RaidDefensiveTracker:CreateFrame()
    self.db = self.db or EnsureDB()
    if not self.db then return nil end

    local frameCreated = false
    if not anchorFrame then
        frameCreated = true
        anchorFrame = CreateFrame("Frame", "DDingToolKit_RaidDefensiveTrackerFrame", UIParent)
        anchorFrame:SetSize(44, 44)
        anchorFrame:EnableMouse(false)
        anchorFrame:SetMovable(true)
        anchorFrame:SetClampedToScreen(true)

        previewFrame = CreateFrame("Frame", nil, anchorFrame)
        previewFrame:SetAllPoints(anchorFrame)
        previewFrame.icons = {}
        local previewSpells = { 29166, 375234, 406789, 10060 }
        local previewTimes = { 8, 9, 7, 12 }
        for index = 1, PREVIEW_COUNT do
            previewFrame.icons[index] = CreatePreviewIcon(
                previewFrame,
                previewSpells[index],
                previewTimes[index]
            )
        end
        previewFrame:Hide()

        dragSurface = CreateFrame("Frame", nil, anchorFrame, "BackdropTemplate")
        dragSurface:SetFrameLevel(anchorFrame:GetFrameLevel() + 20)
        dragSurface:SetBackdrop({
            bgFile = FLAT_TEXTURE,
            edgeFile = FLAT_TEXTURE,
            edgeSize = 1,
        })
        dragSurface:SetBackdropColor(0.04, 0.12, 0.16, 0.14)
        dragSurface:SetBackdropBorderColor(0.18, 0.76, 0.92, 0.72)
        dragSurface:RegisterForDrag("LeftButton")
        dragSurface:SetScript("OnDragStart", function()
            local db = RaidDefensiveTracker.db or EnsureDB()
            if not (IsDirectDragPreview() and db and db.locked == false) then return end
            if IsMovementRestricted() then return end
            directDragging = true
            anchorFrame:StartMoving()
        end)
        dragSurface:SetScript("OnDragStop", function()
            if not directDragging then return end
            anchorFrame:StopMovingOrSizing()
            directDragging = false
            SaveDirectPosition()
        end)
        dragSurface:Hide()
    end

    if frameCreated then
        self:ApplyPosition()
    end
    local _, width, height = GetIconGeometry(self.db)
    anchorFrame:SetSize(width, height)
    anchorFrame:SetScale(Clamp(self.db.scale, 0.5, 2, 1))
    anchorFrame:SetFrameStrata(self.db.frameStrata or "HIGH")
    LayoutPreview()

    if not container then EnsureContainer() end
    RefreshVisibility()
    return anchorFrame
end

function RaidDefensiveTracker:ApplyPosition()
    if not anchorFrame then return end
    local db = self.db or EnsureDB()
    local position = db and db.position or DEFAULT_POSITION
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or position.point or "CENTER",
        tonumber(position.x) or 0,
        tonumber(position.y) or -250
    )
    SyncEditModeMover()
end

function RaidDefensiveTracker:ApplySettings()
    self.db = EnsureDB()
    if not self.db then return end
    self:CreateFrame()
    if not anchorFrame then return end

    local _, width, height = GetIconGeometry(self.db)
    anchorFrame:SetSize(width, height)
    anchorFrame:SetScale(Clamp(self.db.scale, 0.5, 2, 1))
    anchorFrame:SetFrameStrata(self.db.frameStrata or "HIGH")
    self:ApplyPosition()
    LayoutPreview()

    if EnsureContainer() then
        ApplyContainerConfig()
    end
    ReconcileAuraSounds()
    RefreshVisibility()
end

function RaidDefensiveTracker:OnInitialize()
    self.db = EnsureDB()
    self.initialized = true
end

function RaidDefensiveTracker:OnEnable()
    self.db = EnsureDB()
    self.active = true
    self:CreateFrame()
    self:ApplySettings()
end

function RaidDefensiveTracker:OnDisable()
    self.active = false
    editPreview = false
    configPreview = false
    manualPreview = false
    if container and not IsRestricted() and container.SetEnabled then
        pcall(container.SetEnabled, container, false)
    end
    ReconcileAuraSounds()
    RefreshVisibility()
end

function RaidDefensiveTracker:OnMediaChanged()
    self:ApplySettings()
end

function RaidDefensiveTracker:ResetPosition()
    self.db = self.db or EnsureDB()
    if not self.db then return end
    self.db.position = CopyDefaultPosition()
    self:CreateFrame()
    self:ApplyPosition()
    RefreshConfigPosition()
end

function RaidDefensiveTracker:RefreshAuraSounds()
    self.db = EnsureDB()
    ReconcileAuraSounds()
end

function RaidDefensiveTracker:OnMoverPositionChanged()
    self.db = EnsureDB()
    RefreshConfigPosition()
end

function RaidDefensiveTracker:TestMode()
    self.db = self.db or EnsureDB()
    manualPreview = not manualPreview
    self:CreateFrame()
    self:ApplySettings()
end

function RaidDefensiveTracker:EnterEditPreview(context)
    self.db = self.db or EnsureDB()
    if type(context) == "table" and context.source == "config" then
        configPreview = true
    else
        editPreview = true
    end
    self:CreateFrame()
    self:ApplySettings()
end

function RaidDefensiveTracker:RefreshEditPreview()
    if not (editPreview or configPreview) then return end
    self:ApplySettings()
end

function RaidDefensiveTracker:ExitEditPreview(context)
    if type(context) == "table" and context.source == "config" then
        configPreview = false
    else
        editPreview = false
    end
    self:ApplySettings()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, _, restrictionState)
    if event == "PLAYER_ENTERING_WORLD" then
        enteredWorld = true
    end

    if event == "PLAYER_ENTERING_WORLD" then
        ReconcileAuraSounds()
    elseif event == "PLAYER_REGEN_ENABLED" and auraSoundsPending then
        ReconcileAuraSounds()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED"
        and not IsSecret(restrictionState)
        and restrictionState == 0
        and auraSoundsPending
    then
        ReconcileAuraSounds()
    end

    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        RefreshVisibility()
    end

    if not (RaidDefensiveTracker.active or IsPreviewing()) then return end
    if event == "PLAYER_ENTERING_WORLD" or applyPending then
        RaidDefensiveTracker:ApplySettings()
    elseif container then
        pcall(container.UpdateAllAuras, container)
    end
end)

DDingToolKit:RegisterModule("RaidDefensiveTracker", RaidDefensiveTracker)
