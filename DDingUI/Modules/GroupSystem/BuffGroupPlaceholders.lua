local _, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Placeholders = {}
DDingUI.BuffGroupPlaceholders = Placeholders

local groups = {}

local function GetSpellNameFromToken(token)
    if type(token) ~= "string" then return nil end
    local name = token:match("^cdm:(.+)$")
    if not name then return nil end
    return name:gsub("^buff_", "")
end

local function ResolveSpellID(token, spellName)
    local controller = DDingUI.CDMHookEngine or DDingUI.FrameController
    local spellIDs = controller and controller.GetTrackedBuffSpellIDs
        and controller:GetTrackedBuffSpellIDs()
    local key = type(token) == "string" and token:match("^cdm:(.+)$")
    local trackedID = key and type(spellIDs) == "table" and spellIDs[key]
    if not (issecretvalue and issecretvalue(trackedID)) then
        trackedID = tonumber(trackedID)
        if trackedID and trackedID > 0 then return trackedID end
    end

    if not spellName or spellName == "" or not C_Spell or not C_Spell.GetSpellInfo then
        return nil
    end
    local info = C_Spell.GetSpellInfo(spellName)
    local spellID = info and info.spellID
    if issecretvalue and issecretvalue(spellID) then return nil end
    spellID = tonumber(spellID)
    return spellID and spellID > 0 and spellID or nil
end

local function ResolveInactiveDisplay(token)
    local visible = false
    local desaturated = true
    local customizer = DDingUI.IconCustomization
    if customizer and customizer.GetSpellSettings then
        local spellID = ResolveSpellID(token, GetSpellNameFromToken(token))
        local custom = spellID and customizer:GetSpellSettings(spellID, "Buff")
        if custom then
            if custom.alwaysShow == "on" then
                visible = true
            elseif custom.alwaysShow == "off" then
                visible = false
            end
            if custom.desatInactive == "off" then
                desaturated = false
            elseif custom.desatInactive == "on" then
                desaturated = true
            end
        end
    end
    return visible, desaturated
end

local function HasForcedInactiveBuff()
    local profile = DDingUI.db and DDingUI.db.profile
    local iconCustomization = profile and profile.iconCustomization
    local spells = iconCustomization and iconCustomization.spells
    for key, settings in pairs(spells or {}) do
        if type(key) == "string" and key:match("_Buff$")
            and type(settings) == "table" and settings.alwaysShow == "on"
        then
            return true
        end
    end
    return false
end

local function ResolveSpellTexture(token, spellName)
    local controller = DDingUI.CDMHookEngine or DDingUI.FrameController
    local textures = controller and controller.GetTrackedBuffSpellTextures
        and controller:GetTrackedBuffSpellTextures()
    local key = type(token) == "string" and token:match("^cdm:(.+)$")
    if key and type(textures) == "table" and textures[key] then
        return textures[key]
    end
    if not spellName or spellName == "" or not C_Spell then return nil end
    if C_Spell.GetSpellTexture then
        local texture = C_Spell.GetSpellTexture(spellName)
        if texture then return texture end
    end
    if C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellName)
        return info and info.iconID
    end
    return nil
end

local function CreatePlaceholder(groupName, token, texture)
    local frame = CreateFrame("Frame", nil, UIParent)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(texture)
    icon:SetDesaturation(0)
    icon:SetAlpha(1)

    frame.Icon = icon
    frame.icon = icon
    frame._ddIsPlaceholder = true
    frame._ddPlaceholderGroup = groupName
    frame._ddOrderToken = token
    frame._ddLayoutVisible = true
    frame:Hide()
    return frame
end

local function IsCurrentlyTracked(token)
    local controller = DDingUI.CDMHookEngine or DDingUI.FrameController
    local tracked = controller and controller.GetTrackedBuffSpellNames
        and controller:GetTrackedBuffSpellNames()
    if type(tracked) ~= "table" or not next(tracked) then return true end
    local key = token:match("^cdm:(.+)$")
    return key and tracked[key] == true or false
end

local function CollectConfiguredTokens(groupName, settings)
    local tokens, seen = {}, {}
    local function Add(token)
        local forcedVisible = type(token) == "string"
            and token:match("^cdm:")
            and ResolveInactiveDisplay(token)
        if type(token) == "string" and token:match("^cdm:")
            and (IsCurrentlyTracked(token) or forcedVisible) and not seen[token]
        then
            seen[token] = true
            tokens[#tokens + 1] = token
        end
    end

    for _, token in ipairs(settings.iconOrder or {}) do
        Add(token)
    end

    local profile = DDingUI.db and DDingUI.db.profile
    local groupSystem = profile and profile.groupSystem
    for spellName, assignedGroup in pairs(groupSystem and groupSystem.spellAssignments or {}) do
        if assignedGroup == groupName then
            Add("cdm:" .. tostring(spellName))
        end
    end
    if groupName == "Buffs" then
        local controller = DDingUI.CDMHookEngine or DDingUI.FrameController
        local tracked = controller and controller.GetTrackedBuffSpellNames
            and controller:GetTrackedBuffSpellNames() or {}
        local trackedOrder = controller and controller.GetTrackedBuffSpellOrder
            and controller:GetTrackedBuffSpellOrder() or {}
        local assignments = groupSystem and groupSystem.spellAssignments or {}
        local unassigned = groupSystem and groupSystem.unassignedBuffSpells or {}
        local defaultTokens = {}
        for spellName in pairs(tracked) do
            if not assignments[spellName] and not unassigned[spellName] then
                defaultTokens[#defaultTokens + 1] = "cdm:" .. spellName
            end
        end
        table.sort(defaultTokens, function(a, b)
            local aName, bName = a:match("^cdm:(.+)$"), b:match("^cdm:(.+)$")
            local aOrder, bOrder = trackedOrder[aName], trackedOrder[bName]
            if aOrder ~= bOrder then
                return (aOrder or math.huge) < (bOrder or math.huge)
            end
            return a < b
        end)
        for _, token in ipairs(defaultTokens) do Add(token) end
    end
    return tokens, seen
end

local function EnableDynamicInactiveIcons(settings)
    local profile = DDingUI.db and DDingUI.db.profile
    local dynamicIcons = profile and profile.dynamicIcons
    local sourceGroup = settings and settings.sourceGroupKey
        and dynamicIcons and dynamicIcons.groups and dynamicIcons.groups[settings.sourceGroupKey]
    local iconDataDB = dynamicIcons and dynamicIcons.iconData
    if not sourceGroup or type(sourceGroup.icons) ~= "table" or type(iconDataDB) ~= "table" then
        return false
    end

    local changed = false
    for _, iconKey in ipairs(sourceGroup.icons) do
        local iconData = iconDataDB[iconKey]
        local iconSettings = iconData and iconData.settings
        local isEffect = iconData and (iconData.type == "aura"
            or (iconData.type == "trinketProc"
                and iconSettings and iconSettings.showItemCooldown == false))
        if isEffect then
            iconData.settings = iconSettings or {}
            if iconData.settings.alwaysShow == nil then
                iconData.settings.alwaysShow = "on"
                changed = true
            end
        end
    end
    return changed
end

local function EnableNativeInactiveIcons(groupName, settings)
    local profile = DDingUI.db and DDingUI.db.profile
    if not profile then return false end
    profile.iconCustomization = profile.iconCustomization or {}
    profile.iconCustomization.spells = profile.iconCustomization.spells or {}

    local spells = profile.iconCustomization.spells
    local tokens = CollectConfiguredTokens(groupName, settings)
    local changed = false
    for _, token in ipairs(tokens) do
        local spellID = ResolveSpellID(token, GetSpellNameFromToken(token))
        if spellID then
            local baseKey = tostring(spellID)
            local spellKey = baseKey .. "_Buff"
            local custom = spells[spellKey]
            if type(custom) ~= "table" then
                custom = {}
                local fallback = spells[baseKey]
                if type(fallback) == "table" then
                    for key, value in pairs(fallback) do
                        custom[key] = value
                    end
                end
                spells[spellKey] = custom
            end
            if custom.alwaysShow == nil then
                custom.alwaysShow = "on"
                changed = true
            end
        end
    end
    return changed
end

function Placeholders:MigrateLegacyGroupSettings(groupSystem)
    local changed = false
    for groupName, settings in pairs(groupSystem and groupSystem.groups or {}) do
        if type(settings) == "table" and rawget(settings, "showInactiveIcons") == true
            and settings._inactiveIconSettingsMigV1 ~= true
        then
            changed = EnableDynamicInactiveIcons(settings) or changed
            changed = EnableNativeInactiveIcons(groupName, settings) or changed
            settings.showInactiveIcons = nil
            settings._inactiveIconSettingsMigV1 = true
            changed = true
        end
    end

    if changed and DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
    return changed
end

function Placeholders:BuildPlacements(groupName, settings, activeTokens)
    local state = groups[groupName]
    if not settings or not HasForcedInactiveBuff() then
        if state then
            for _, frame in pairs(state) do
                frame._ddLayoutVisible = false
                frame:Hide()
            end
        end
        return nil
    end

    state = state or {}
    groups[groupName] = state
    local tokens, configured = CollectConfiguredTokens(groupName, settings)
    local placements = {}

    for token, frame in pairs(state) do
        if not configured[token] or (activeTokens and activeTokens[token]) then
            frame._ddLayoutVisible = false
            frame:Hide()
        end
    end

    for _, token in ipairs(tokens) do
        if not (activeTokens and activeTokens[token]) then
            local visible, desaturated = ResolveInactiveDisplay(token)
            local frame = state[token]
            if visible and not frame then
                local texture = ResolveSpellTexture(token, GetSpellNameFromToken(token))
                if texture then
                    frame = CreatePlaceholder(groupName, token, texture)
                    state[token] = frame
                end
            end
            if visible and frame then
                frame._ddLayoutVisible = true
                placements[#placements + 1] = {
                    isPlaceholder = true,
                    inactiveGray = desaturated,
                    icon = frame,
                    sourceVisible = true,
                    _ddOrderToken = token,
                }
            elseif frame then
                frame._ddLayoutVisible = false
                frame:Hide()
            end
        end
    end
    return placements
end

function Placeholders:ApplyStyle(frame, settings)
    if not (frame and frame._ddIsPlaceholder and settings) then return end
    local icon = frame.Icon
    local borders = frame._ddBorders
    if not borders then
        borders = {}
        for index = 1, 4 do
            borders[index] = frame:CreateTexture(nil, "OVERLAY")
        end
        borders[1]:SetPoint("TOPLEFT", icon, "TOPLEFT")
        borders[1]:SetPoint("TOPRIGHT", icon, "TOPRIGHT")
        borders[2]:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT")
        borders[2]:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
        borders[3]:SetPoint("TOPLEFT", icon, "TOPLEFT")
        borders[3]:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT")
        borders[4]:SetPoint("TOPRIGHT", icon, "TOPRIGHT")
        borders[4]:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
        frame._ddBorders = borders
    end

    local size = tonumber(settings.borderSize) or 1
    if DDingUI.ScaleBorder then
        size = DDingUI:ScaleBorder(size)
    end
    local color = settings.borderColor or { 0, 0, 0, 1 }
    local r, g, b, a = color[1] or color.r or 0, color[2] or color.g or 0,
        color[3] or color.b or 0, color[4] or color.a or 1
    borders[1]:SetHeight(size)
    borders[2]:SetHeight(size)
    borders[3]:SetWidth(size)
    borders[4]:SetWidth(size)
    for _, border in ipairs(borders) do
        border:SetColorTexture(r, g, b, a)
        border:SetShown(size > 0)
    end
end

function Placeholders:DeactivateFrame(frame)
    if not (frame and frame._ddIsPlaceholder) then return end
    frame._ddLayoutVisible = false
    frame._ddContainerRef = nil
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
end

function Placeholders:ReleaseGroup(groupName)
    local state = groups[groupName]
    if not state then return end
    for _, frame in pairs(state) do
        self:DeactivateFrame(frame)
    end
    groups[groupName] = nil
end

function Placeholders:ReleaseAll()
    local names = {}
    for groupName in pairs(groups) do
        names[#names + 1] = groupName
    end
    for _, groupName in ipairs(names) do
        self:ReleaseGroup(groupName)
    end
end
