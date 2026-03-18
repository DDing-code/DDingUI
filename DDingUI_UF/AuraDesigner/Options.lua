local addonName, ns = ...

-- ============================================================
-- AURA DESIGNER - OPTIONS GUI
-- Separate file: called from Options.lua via ns.BuildAuraDesignerPage()
-- ============================================================

local pairs, ipairs, type = pairs, ipairs, type
local format = string.format
local wipe = wipe
local tinsert = table.insert
local tremove = table.remove
local max, min = math.max, math.min
local sort = table.sort

local Widgets = ns.Widgets
local AD, Adapter, Engine

-- ============================================================
-- CONSTANTS
-- ============================================================

local INDICATOR_TYPES = {
    { key = "icon",       label = "아이콘",         placed = true  },
    { key = "square",     label = "사각형",         placed = true  },
    { key = "bar",        label = "바",             placed = true  },
    { key = "border",     label = "테두리",         placed = false },
    { key = "healthbar",  label = "체력바 색상",    placed = false },
    { key = "nametext",   label = "이름 색상",      placed = false },
    { key = "healthtext", label = "체력 텍스트 색상", placed = false },
    { key = "framealpha", label = "프레임 투명도",  placed = false },
}

local ANCHOR_OPTIONS = {
    { value = "TOPLEFT",     text = "좌상" },
    { value = "TOP",         text = "상" },
    { value = "TOPRIGHT",    text = "우상" },
    { value = "LEFT",        text = "좌" },
    { value = "CENTER",      text = "중앙" },
    { value = "RIGHT",       text = "우" },
    { value = "BOTTOMLEFT",  text = "좌하" },
    { value = "BOTTOM",      text = "하" },
    { value = "BOTTOMRIGHT", text = "우하" },
}

local ANCHOR_LABELS = {}
for _, opt in ipairs(ANCHOR_OPTIONS) do ANCHOR_LABELS[opt.value] = opt.text end

local GROWTH_OPTIONS = {
    { value = "RIGHT", text = "오른쪽" },
    { value = "LEFT",  text = "왼쪽" },
    { value = "UP",    text = "위" },
    { value = "DOWN",  text = "아래" },
}

local BORDER_STYLE_OPTIONS = {
    { value = "SOLID",    text = "실선" },
    { value = "ANIMATED", text = "애니메이션" },
    { value = "DASHED",   text = "점선" },
    { value = "GLOW",     text = "글로우" },
    { value = "CORNERS",  text = "모서리만" },
}

local BAR_ORIENT_OPTIONS = {
    { value = "HORIZONTAL", text = "가로" },
    { value = "VERTICAL",   text = "세로" },
}

local OUTLINE_OPTIONS = {
    { value = "NONE",         text = "없음" },
    { value = "OUTLINE",      text = "외곽선" },
    { value = "THICKOUTLINE", text = "굵은 외곽선" },
    { value = "SHADOW",       text = "그림자" },
}

local HEALTHBAR_MODE_OPTIONS = {
    { value = "Replace", text = "교체" },
    { value = "Tint",    text = "틴트" },
}

local FRAME_STRATA_OPTIONS = {
    { value = "INHERIT",    text = "상속 (프레임)" },
    { value = "BACKGROUND", text = "배경" },
    { value = "LOW",        text = "낮음" },
    { value = "MEDIUM",     text = "보통" },
    { value = "HIGH",       text = "높음" },
}

local EXPIRING_MODE_OPTIONS = {
    { value = "PERCENT", text = "퍼센트" },
    { value = "SECONDS", text = "초" },
}

local BADGE_COLORS = {
    icon       = { 0.36, 0.72, 0.94 },
    square     = { 0.51, 0.86, 0.51 },
    bar        = { 0.94, 0.71, 0.24 },
    border     = { 0.80, 0.50, 0.80 },
    healthbar  = { 0.94, 0.31, 0.31 },
    nametext   = { 0.72, 0.72, 0.94 },
    healthtext = { 0.72, 0.72, 0.94 },
    framealpha = { 0.60, 0.60, 0.60 },
}

local PLACED_TYPE_LABELS = { icon = "아이콘", square = "사각형", bar = "바" }
local FRAME_LEVEL_TYPE_KEYS = { "border", "healthbar", "nametext", "healthtext", "framealpha" }
local FRAME_LEVEL_LABELS = {
    border = "테두리", healthbar = "체력바", nametext = "이름",
    healthtext = "체력 텍스트", framealpha = "투명도",
}

local TYPE_DEFAULTS = {
    icon = {
        anchor = "TOPLEFT", offsetX = 0, offsetY = 0,
        size = 24, scale = 1.0, alpha = 1.0,
        frameLevel = 0, frameStrata = "INHERIT",
        borderEnabled = true, borderThickness = 1, borderInset = 1,
        hideSwipe = false, hideIcon = false,
        showDuration = true, durationFont = "Fonts\\FRIZQT__.TTF",
        durationScale = 1.0, durationOutline = "OUTLINE",
        durationAnchor = "CENTER", durationX = 0, durationY = 0,
        durationColorByTime = true,
        durationColor = {r = 1, g = 1, b = 1, a = 1},
        durationHideAboveEnabled = false, durationHideAboveThreshold = 10,
        showStacks = true, stackMinimum = 2,
        stackFont = "Fonts\\FRIZQT__.TTF", stackScale = 1.0,
        stackOutline = "OUTLINE", stackAnchor = "BOTTOMRIGHT",
        stackX = 0, stackY = 0,
        stackColor = {r = 1, g = 1, b = 1, a = 1},
        expiringEnabled = false, expiringThreshold = 30, expiringThresholdMode = "PERCENT",
        expiringColor = {r = 1, g = 0.2, b = 0.2, a = 1},
        expiringPulsate = false,
        expiringWholeAlphaPulse = false, expiringBounce = false,
    },
    square = {
        anchor = "TOPLEFT", offsetX = 0, offsetY = 0,
        size = 24, scale = 1.0, alpha = 1.0,
        frameLevel = 0, frameStrata = "INHERIT",
        color = {r = 1, g = 1, b = 1, a = 1},
        showBorder = true, borderThickness = 1, borderInset = 1,
        hideSwipe = false, hideIcon = false,
        showDuration = true, durationFont = "Fonts\\FRIZQT__.TTF",
        durationScale = 1.0, durationOutline = "OUTLINE",
        durationAnchor = "CENTER", durationX = 0, durationY = 0,
        durationColorByTime = true,
        durationColor = {r = 1, g = 1, b = 1, a = 1},
        durationHideAboveEnabled = false, durationHideAboveThreshold = 10,
        showStacks = true, stackMinimum = 2,
        stackFont = "Fonts\\FRIZQT__.TTF", stackScale = 1.0,
        stackOutline = "OUTLINE", stackAnchor = "BOTTOMRIGHT",
        stackX = 0, stackY = 0,
        stackColor = {r = 1, g = 1, b = 1, a = 1},
        expiringEnabled = false, expiringThreshold = 30, expiringThresholdMode = "PERCENT",
        expiringColor = {r = 1, g = 0.2, b = 0.2, a = 1},
        expiringPulsate = false,
        expiringWholeAlphaPulse = false, expiringBounce = false,
    },
    bar = {
        anchor = "BOTTOM", offsetX = 0, offsetY = 0,
        orientation = "HORIZONTAL", width = 60, height = 6,
        matchFrameWidth = true, matchFrameHeight = false,
        texture = "Interface\\TargetingFrame\\UI-StatusBar",
        fillColor = {r = 1, g = 1, b = 1, a = 1},
        bgColor = {r = 0, g = 0, b = 0, a = 0.5},
        showBorder = true, borderThickness = 1,
        borderColor = {r = 0, g = 0, b = 0, a = 1},
        alpha = 1.0, frameLevel = 0, frameStrata = "INHERIT",
        barColorByTime = false,
        expiringEnabled = false, expiringThreshold = 5,
        expiringThresholdMode = "SECONDS",
        expiringColor = {r = 1, g = 0.2, b = 0.2, a = 1},
        showDuration = true, durationFont = "Fonts\\FRIZQT__.TTF",
        durationScale = 1.0, durationOutline = "OUTLINE",
        durationAnchor = "CENTER", durationX = 0, durationY = 0,
        durationColorByTime = true,
        durationHideAboveEnabled = false, durationHideAboveThreshold = 10,
    },
}

-- ============================================================
-- DB MIGRATION (flat → spec-scoped)
-- ============================================================

local function MigrateToSpecScoped(adDB)
    if not adDB then return end
    -- V1: flat auras → spec-keyed
    if not adDB._specScopedV1 then
        if adDB.auras then
            local isFlat = false
            for _, val in pairs(adDB.auras) do
                if type(val) == "table" and (val.priority ~= nil or val.indicators ~= nil) then
                    isFlat = true; break
                end
            end
            if isFlat then
                local oldAuras = adDB.auras
                local newAuras = {}
                local auraToSpecs = {}
                local trackable = ns.AuraDesigner and ns.AuraDesigner.TrackableAuras
                if trackable then
                    for specKey, auraList in pairs(trackable) do
                        for _, info in ipairs(auraList) do
                            if not auraToSpecs[info.name] then auraToSpecs[info.name] = {} end
                            tinsert(auraToSpecs[info.name], specKey)
                        end
                    end
                end
                for auraName, auraCfg in pairs(oldAuras) do
                    local specs = auraToSpecs[auraName]
                    if specs then
                        for _, specKey in ipairs(specs) do
                            if not newAuras[specKey] then newAuras[specKey] = {} end
                            newAuras[specKey][auraName] = DeepCopyValue(auraCfg)
                        end
                    end
                end
                adDB.auras = newAuras
            end
        end
        adDB._specScopedV1 = true
    end
    -- V2: flat layoutGroups → spec-keyed
    if not adDB._specScopedV2 then
        if adDB.layoutGroups then
            local isFlat = false
            for k, v in pairs(adDB.layoutGroups) do
                if type(k) == "number" and type(v) == "table" and v.id ~= nil then
                    isFlat = true; break
                end
            end
            if isFlat then
                local oldGroups = adDB.layoutGroups
                local newGroups = {}
                local auraToSpecs = {}
                if adDB.auras then
                    for specKey, specAuras in pairs(adDB.auras) do
                        if type(specAuras) == "table" then
                            for auraName in pairs(specAuras) do
                                if not auraToSpecs[auraName] then auraToSpecs[auraName] = {} end
                                auraToSpecs[auraName][specKey] = true
                            end
                        end
                    end
                end
                for _, group in ipairs(oldGroups) do
                    local targetSpecs = {}
                    if group.members then
                        for _, member in ipairs(group.members) do
                            local specs = auraToSpecs[member.auraName]
                            if specs then for specKey in pairs(specs) do targetSpecs[specKey] = true end end
                        end
                    end
                    for specKey in pairs(targetSpecs) do
                        if not newGroups[specKey] then newGroups[specKey] = {} end
                        tinsert(newGroups[specKey], DeepCopyValue(group))
                    end
                end
                adDB.layoutGroups = newGroups
            end
        end
        adDB._specScopedV2 = true
    end
end

-- ============================================================
-- DB HELPERS
-- ============================================================

local function GetAuraDesignerDB()
    local adDB = ns.db and ns.db.auraDesigner
    if adDB and (not adDB._specScopedV1 or not adDB._specScopedV2) then
        MigrateToSpecScoped(adDB)
    end
    return adDB
end

local function ResolveSpec()
    local adDB = GetAuraDesignerDB()
    if not adDB then return nil end
    if adDB.spec == "auto" then
        return Engine and Engine:ResolveSpec() or nil
    end
    return adDB.spec
end

local function GetSpecAuras(spec)
    local adDB = GetAuraDesignerDB()
    if not adDB then return {} end
    if not adDB.auras then adDB.auras = {} end
    spec = spec or ResolveSpec()
    if not spec then return {} end
    if not adDB.auras[spec] then adDB.auras[spec] = {} end
    return adDB.auras[spec]
end

local function GetSpecLayoutGroups(spec)
    local adDB = GetAuraDesignerDB()
    if not adDB then return {} end
    if not adDB.layoutGroups then adDB.layoutGroups = {} end
    spec = spec or ResolveSpec()
    if not spec then return {} end
    if not adDB.layoutGroups[spec] then adDB.layoutGroups[spec] = {} end
    return adDB.layoutGroups[spec]
end

local function EnsureAuraConfig(auraName)
    local specAuras = GetSpecAuras()
    if not specAuras[auraName] then
        specAuras[auraName] = { priority = 5 }
    end
    return specAuras[auraName]
end

local function EnsureTypeConfig(auraName, typeKey)
    local auraCfg = EnsureAuraConfig(auraName)
    if not auraCfg[typeKey] then
        local defaults = TYPE_DEFAULTS[typeKey]
        if defaults then
            auraCfg[typeKey] = {}
            for k, v in pairs(defaults) do
                if type(v) == "table" then
                    auraCfg[typeKey][k] = {}
                    for kk, vv in pairs(v) do auraCfg[typeKey][k][kk] = vv end
                else
                    auraCfg[typeKey][k] = v
                end
            end
        else
            -- Frame-level defaults
            if typeKey == "border" then
                auraCfg[typeKey] = { style = "SOLID", color = {r=1,g=1,b=1,a=1}, thickness = 2, inset = 0 }
            elseif typeKey == "healthbar" then
                auraCfg[typeKey] = { mode = "Replace", color = {r=1,g=1,b=1,a=1}, blend = 0.5 }
            elseif typeKey == "nametext" or typeKey == "healthtext" then
                auraCfg[typeKey] = { color = {r=1,g=1,b=1,a=1} }
            elseif typeKey == "framealpha" then
                auraCfg[typeKey] = { alpha = 0.5 }
            end
        end
    end
    return auraCfg[typeKey]
end

-- ============================================================
-- INSTANCE MANAGEMENT
-- ============================================================

local function CreateIndicatorInstance(auraName, typeKey)
    local auraCfg = EnsureAuraConfig(auraName)
    if not auraCfg.indicators then auraCfg.indicators = {} end
    if not auraCfg.nextIndicatorID then auraCfg.nextIndicatorID = 1 end
    local defaults = TYPE_DEFAULTS[typeKey]
    local instance = {
        id = auraCfg.nextIndicatorID,
        type = typeKey,
        anchor = defaults and defaults.anchor or "TOPLEFT",
        offsetX = 0, offsetY = 0,
    }
    auraCfg.nextIndicatorID = auraCfg.nextIndicatorID + 1
    tinsert(auraCfg.indicators, instance)
    return instance
end

local function GetIndicatorByID(auraName, indicatorID)
    local auraCfg = GetSpecAuras()[auraName]
    if not auraCfg or not auraCfg.indicators then return nil end
    for _, inst in ipairs(auraCfg.indicators) do
        if inst.id == indicatorID then return inst end
    end
    return nil
end

local function RemoveIndicatorInstance(auraName, indicatorID)
    local auraCfg = GetSpecAuras()[auraName]
    if not auraCfg or not auraCfg.indicators then return end
    for i, inst in ipairs(auraCfg.indicators) do
        if inst.id == indicatorID then
            tremove(auraCfg.indicators, i)
            return
        end
    end
end

-- ============================================================
-- PROXY SYSTEM (instance → global defaults → TYPE_DEFAULTS)
-- ============================================================

local GLOBAL_DEFAULT_MAP = {
    icon   = { size = "iconSize", scale = "iconScale", showDuration = "showDuration", showStacks = "showStacks" },
    square = { size = "iconSize", scale = "iconScale", showDuration = "showDuration", showStacks = "showStacks" },
    bar    = {},
}


local function CreateInstanceProxy(auraName, indicatorID)
    return setmetatable({}, {
        __index = function(_, k)
            local inst = GetIndicatorByID(auraName, indicatorID)
            if inst then
                local val = inst[k]
                if val ~= nil then return val end
            end
            -- Global defaults
            if inst and inst.type then
                local gdMap = GLOBAL_DEFAULT_MAP[inst.type]
                if gdMap then
                    local gdKey = gdMap[k]
                    if gdKey then
                        local adDB = GetAuraDesignerDB()
                        local gd = adDB and adDB.defaults
                        if gd and gd[gdKey] ~= nil then return gd[gdKey] end
                    end
                end
                -- TYPE_DEFAULTS
                local defaults = TYPE_DEFAULTS[inst.type]
                if defaults then
                    local fallback = defaults[k]
                    if type(fallback) == "table" and inst then
                        local copy = {}
                        for fk, fv in pairs(fallback) do copy[fk] = fv end
                        inst[k] = copy
                        return copy
                    end
                    return fallback
                end
            end
            return nil
        end,
        __newindex = function(_, k, v)
            local inst = GetIndicatorByID(auraName, indicatorID)
            if not inst then return end
            inst[k] = v
            if ns.AuraDesignerOptions_RefreshPreviewLightweight then ns.AuraDesignerOptions_RefreshPreviewLightweight() end
        end,
    })
end

local function CreateProxy(auraName, typeKey)
    local defaults = TYPE_DEFAULTS[typeKey]
    return setmetatable({}, {
        __index = function(_, k)
            local auraCfg = GetSpecAuras()[auraName]
            if auraCfg and auraCfg[typeKey] then
                local val = auraCfg[typeKey][k]
                if val ~= nil then return val end
            end
            if defaults then
                local fallback = defaults[k]
                if type(fallback) == "table" then
                    local typeCfg = EnsureTypeConfig(auraName, typeKey)
                    local copy = {}
                    for fk, fv in pairs(fallback) do copy[fk] = fv end
                    typeCfg[k] = copy
                    return copy
                end
                return fallback
            end
            return nil
        end,
        __newindex = function(_, k, v)
            local typeCfg = EnsureTypeConfig(auraName, typeKey)
            typeCfg[k] = v
            if ns.AuraDesignerOptions_RefreshPreviewLightweight then ns.AuraDesignerOptions_RefreshPreviewLightweight() end
        end,
    })
end

-- ============================================================
-- AURA ICON HELPER
-- ============================================================

local function GetAuraIcon(specKey, auraName)
    local icons = AD and AD.IconTextures
    if icons and icons[auraName] then return icons[auraName] end
    local spellIDs = AD and AD.SpellIDs
    if not spellIDs or not specKey then return nil end
    local specIDs = spellIDs[specKey]
    if not specIDs then return nil end
    local spellID = specIDs[auraName]
    if not spellID or spellID == 0 then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return nil
end

-- ============================================================
-- LAYOUT GROUP HELPERS
-- ============================================================

local function GetIndicatorLayoutGroup(auraName, indicatorID)
    local groups = GetSpecLayoutGroups()
    for _, group in ipairs(groups) do
        if group.members then
            for _, member in ipairs(group.members) do
                if member.auraName == auraName and member.indicatorID == indicatorID then
                    return group
                end
            end
        end
    end
    return nil
end

local function CreateLayoutGroup(name)
    local adDB = GetAuraDesignerDB()
    if not adDB then return nil end
    local groups = GetSpecLayoutGroups()
    if not adDB.nextLayoutGroupID then adDB.nextLayoutGroupID = 1 end
    local id = adDB.nextLayoutGroupID
    adDB.nextLayoutGroupID = id + 1
    local group = {
        id = id, name = name or ("그룹 " .. id),
        anchor = "TOPLEFT", offsetX = 0, offsetY = 0,
        growDirection = "RIGHT", spacing = 2, members = {},
    }
    tinsert(groups, group)
    return group
end

local function DeleteLayoutGroup(groupID)
    local groups = GetSpecLayoutGroups()
    for i, group in ipairs(groups) do
        if group.id == groupID then
            if group.members then
                for _, member in ipairs(group.members) do
                    RemoveIndicatorInstance(member.auraName, member.indicatorID)
                end
            end
            tremove(groups, i)
            break
        end
    end
end

local function GetLayoutGroupByID(groupID)
    local groups = GetSpecLayoutGroups()
    for _, group in ipairs(groups) do
        if group.id == groupID then return group end
    end
    return nil
end

local function AddGroupMember(groupID, auraName, indicatorID)
    local group = GetLayoutGroupByID(groupID)
    if not group then return end
    if not group.members then group.members = {} end
    for _, m in ipairs(group.members) do
        if m.auraName == auraName and m.indicatorID == indicatorID then return end
    end
    tinsert(group.members, { auraName = auraName, indicatorID = indicatorID })
end

local function RemoveGroupMember(groupID, auraName, indicatorID)
    local group = GetLayoutGroupByID(groupID)
    if not group or not group.members then return end
    for i, m in ipairs(group.members) do
        if m.auraName == auraName and m.indicatorID == indicatorID then
            tremove(group.members, i)
            break
        end
    end
end

local function SwapGroupMembers(groupID, idx1, idx2)
    local group = GetLayoutGroupByID(groupID)
    if not group or not group.members then return end
    if idx1 < 1 or idx1 > #group.members or idx2 < 1 or idx2 > #group.members then return end
    group.members[idx1], group.members[idx2] = group.members[idx2], group.members[idx1]
end

-- ============================================================
-- MULTI-TRIGGER HELPERS
-- ============================================================

local function GetFrameEffectTriggers(auraName, typeKey)
    local auraCfg = GetSpecAuras()[auraName]
    local typeCfg = auraCfg and auraCfg[typeKey]
    if typeCfg and typeCfg.triggers then return typeCfg.triggers end
    return { auraName }
end

local function AddFrameEffectTrigger(auraName, typeKey, triggerName)
    local typeCfg = EnsureTypeConfig(auraName, typeKey)
    if not typeCfg.triggers then typeCfg.triggers = { auraName } end
    for _, t in ipairs(typeCfg.triggers) do
        if t == triggerName then return end
    end
    tinsert(typeCfg.triggers, triggerName)
end

local function RemoveFrameEffectTrigger(auraName, typeKey, triggerName)
    local auraCfg = GetSpecAuras()[auraName]
    local typeCfg = auraCfg and auraCfg[typeKey]
    if not typeCfg or not typeCfg.triggers or #typeCfg.triggers <= 1 then return end
    for i, t in ipairs(typeCfg.triggers) do
        if t == triggerName then
            tremove(typeCfg.triggers, i)
            break
        end
    end
end

-- ============================================================
-- EFFECTS COLLECTION
-- ============================================================

local function CollectAllEffects()
    local effects = {}
    local spec = ResolveSpec()
    local trackable = spec and AD and AD.TrackableAuras and AD.TrackableAuras[spec]
    local displayNames = {}
    if trackable then
        for _, info in ipairs(trackable) do
            displayNames[info.name] = info.display
        end
    end

    for auraName, auraCfg in pairs(GetSpecAuras(spec)) do
        if type(auraCfg) == "table" and displayNames[auraName] then
            if auraCfg.indicators then
                for _, indicator in ipairs(auraCfg.indicators) do
                    tinsert(effects, {
                        source = "placed", auraName = auraName,
                        displayName = displayNames[auraName],
                        indicatorID = indicator.id, typeKey = indicator.type,
                        config = indicator, anchor = indicator.anchor or "CENTER",
                    })
                end
            end
            for _, typeKey in ipairs(FRAME_LEVEL_TYPE_KEYS) do
                if auraCfg[typeKey] then
                    tinsert(effects, {
                        source = "frame", auraName = auraName,
                        displayName = displayNames[auraName],
                        typeKey = typeKey, config = auraCfg[typeKey],
                    })
                end
            end
        end
    end

    sort(effects, function(a, b)
        if a.source ~= b.source then return a.source == "placed" end
        if a.source == "placed" then return (a.indicatorID or 0) > (b.indicatorID or 0) end
        return a.typeKey < b.typeKey
    end)
    return effects
end

-- ============================================================
-- REFRESH HELPER (forward-declared, set during build)
-- ============================================================

local ADRefreshAll
local RefreshPage

local function SetRefreshCallbacks(refreshAll, refreshPage)
    ADRefreshAll = refreshAll
    RefreshPage = refreshPage
end

-- ============================================================
-- COPY APPEARANCE
-- ============================================================

local COPY_SKIP_KEYS = { id = true, type = true, anchor = true, offsetX = true, offsetY = true }

local function DeepCopyValue(val)
    if type(val) == "table" then
        local copy = {}
        for k, v in pairs(val) do copy[k] = DeepCopyValue(v) end
        return copy
    end
    return val
end

local function CopyIndicatorAppearance(srcAuraName, srcIndicatorID, dstAuraName, dstIndicatorID)
    local src = GetIndicatorByID(srcAuraName, srcIndicatorID)
    local dst = GetIndicatorByID(dstAuraName, dstIndicatorID)
    if not src or not dst or src.type ~= dst.type then return end
    local allKeys = {}
    for k in pairs(src) do if not COPY_SKIP_KEYS[k] then allKeys[k] = true end end
    for k in pairs(dst) do if not COPY_SKIP_KEYS[k] then allKeys[k] = true end end
    for k in pairs(allKeys) do
        if src[k] ~= nil then dst[k] = DeepCopyValue(src[k]) else dst[k] = nil end
    end
end

-- ============================================================
-- ANCHOR POSITIONS (for frame preview)
-- ============================================================

local ANCHOR_POSITIONS = {
    TOPLEFT     = { x = 0,   y = 0   },
    TOP         = { x = 0.5, y = 0   },
    TOPRIGHT    = { x = 1,   y = 0   },
    LEFT        = { x = 0,   y = 0.5 },
    CENTER      = { x = 0.5, y = 0.5 },
    RIGHT       = { x = 1,   y = 0.5 },
    BOTTOMLEFT  = { x = 0,   y = 1   },
    BOTTOM      = { x = 0.5, y = 1   },
    BOTTOMRIGHT = { x = 1,   y = 1   },
}

-- ============================================================
-- MODULE TABLE (exposed to ns)
-- ============================================================

ns.AuraDesignerOptions = {
    -- Constants
    INDICATOR_TYPES = INDICATOR_TYPES,
    ANCHOR_OPTIONS = ANCHOR_OPTIONS,
    ANCHOR_LABELS = ANCHOR_LABELS,
    GROWTH_OPTIONS = GROWTH_OPTIONS,
    BORDER_STYLE_OPTIONS = BORDER_STYLE_OPTIONS,
    BAR_ORIENT_OPTIONS = BAR_ORIENT_OPTIONS,
    OUTLINE_OPTIONS = OUTLINE_OPTIONS,
    HEALTHBAR_MODE_OPTIONS = HEALTHBAR_MODE_OPTIONS,
    FRAME_STRATA_OPTIONS = FRAME_STRATA_OPTIONS,
    EXPIRING_MODE_OPTIONS = EXPIRING_MODE_OPTIONS,
    TYPE_DEFAULTS = TYPE_DEFAULTS,
    BADGE_COLORS = BADGE_COLORS,
    PLACED_TYPE_LABELS = PLACED_TYPE_LABELS,
    FRAME_LEVEL_TYPE_KEYS = FRAME_LEVEL_TYPE_KEYS,
    FRAME_LEVEL_LABELS = FRAME_LEVEL_LABELS,
    ANCHOR_POSITIONS = ANCHOR_POSITIONS,
    -- Helpers
    GetAuraDesignerDB = GetAuraDesignerDB,
    ResolveSpec = ResolveSpec,
    GetSpecAuras = GetSpecAuras,
    GetSpecLayoutGroups = GetSpecLayoutGroups,
    EnsureAuraConfig = EnsureAuraConfig,
    EnsureTypeConfig = EnsureTypeConfig,
    CreateIndicatorInstance = CreateIndicatorInstance,
    GetIndicatorByID = GetIndicatorByID,
    RemoveIndicatorInstance = RemoveIndicatorInstance,
    CreateInstanceProxy = CreateInstanceProxy,
    CreateProxy = CreateProxy,
    GetAuraIcon = GetAuraIcon,
    GetIndicatorLayoutGroup = GetIndicatorLayoutGroup,
    CreateLayoutGroup = CreateLayoutGroup,
    DeleteLayoutGroup = DeleteLayoutGroup,
    GetLayoutGroupByID = GetLayoutGroupByID,
    AddGroupMember = AddGroupMember,
    RemoveGroupMember = RemoveGroupMember,
    SwapGroupMembers = SwapGroupMembers,
    GetFrameEffectTriggers = GetFrameEffectTriggers,
    AddFrameEffectTrigger = AddFrameEffectTrigger,
    RemoveFrameEffectTrigger = RemoveFrameEffectTrigger,
    CollectAllEffects = CollectAllEffects,
    CopyIndicatorAppearance = CopyIndicatorAppearance,
    DeepCopyValue = DeepCopyValue,
    SetRefreshCallbacks = SetRefreshCallbacks,
    MigrateToSpecScoped = MigrateToSpecScoped,
}

-- Lazy-init AD/Adapter/Engine references
function ns.AuraDesignerOptions:Init()
    AD = ns.AuraDesigner
    Adapter = AD and AD.Adapter
    Engine = AD and AD.Engine
end
