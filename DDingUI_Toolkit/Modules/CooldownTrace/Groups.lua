local _, ns = ...
local L, Data = ns.L, ns.CooldownTraceData
local Groups = {}
ns.SkillTracker = Groups
-- [REFACTOR] OmniCD group system: frame 0 is the party-frame layout (saved "common" group),
-- frames 1-8 are extra bars. Spell types stay DDingUI's defensives/cooldowns/cc categories.
local BAR_COUNT = 8
Groups.BAR_COUNT = BAR_COUNT
local LEGACY_MODULES = {defensives="DefensiveTracker", cooldowns="CooldownTracker", cc="SkillTrace_cc"}
local LEGACY_NAMES = {common="CT_COMMON", defensives="CT_CATEGORY_DEFENSIVES", cooldowns="CT_CATEGORY_COOLDOWNS", cc="CT_CATEGORY_CC"}
local LEGACY_ORDER = {"common", "defensives", "cooldowns", "cc"}
local SIDE_POINTS = {RIGHT={"TOPLEFT", "TOPRIGHT"}, LEFT={"TOPRIGHT", "TOPLEFT"},
    TOP={"BOTTOMLEFT", "TOPLEFT"}, BOTTOM={"TOPLEFT", "BOTTOMLEFT"}}
-- [REFACTOR] Effect and context options each bar now owns (they used to follow frame 0).
local FX_FIELDS = {"showInParty", "showInRaid", "showInDelve",
    "activeGlow", "glowType", "glowColor", "glowPulse", "glowSpeed", "glowThickness",
    "useGlow", "useGlowType", "useGlowColor", "useGlowDuration",
    "showSwipe", "showNumbers", "showCharges", "unknownAlpha",
    "showBorder", "borderThickness", "borderColor"}
Groups.FX_FIELDS = FX_FIELDS
local categoryOf = {}
for _, category in ipairs(Data.categories) do
    for _, catalog in pairs(Data[category]) do
        for _, id in ipairs(catalog) do categoryOf[id] = categoryOf[id] or category end
    end
end
local cache = {}
local specCache, inspectRequests, nextInspect = {}, {}, 0

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

-- [12.0.1] Snapshot inspect data by GUID; the client's inspect result is transient.
function Groups:UnitSpec(unit, guid, class, player)
    local api = C_SpecializationInfo or {}
    local getter = api.GetInspectSpecialization or GetInspectSpecialization
    if not getter then return nil, false end
    local ok, spec
    if player then
        local indexGetter, infoGetter = api.GetSpecialization or GetSpecialization, api.GetSpecializationInfo or GetSpecializationInfo
        if indexGetter and infoGetter then
            local valid, index = pcall(indexGetter)
            if valid and Public(index) and type(index) == "number" and index > 0 then ok, spec = pcall(infoGetter, index) end
        end
    else ok, spec = pcall(getter, unit) end
    if ok and Public(spec) and type(spec) == "number" then
        for _, id in ipairs(Data.classSpecs[class] or {}) do
            if spec == id then
                specCache[guid] = spec
                return spec, true
            end
        end
    end
    if specCache[guid] then return specCache[guid], true end
    local now = GetTime()
    if not player and not InCombatLockdown() and NotifyInspect and CanInspect
        and not (InspectFrame and InspectFrame:IsShown()) and now >= nextInspect
        and now - (inspectRequests[guid] or -math.huge) >= 10 then
        local canRead, canInspect = pcall(CanInspect, unit)
        if canRead and Public(canInspect) and canInspect == true then
            nextInspect, inspectRequests[guid] = now + 4, now
            pcall(NotifyInspect, unit)
        end
    end
    return nil, true
end

function Groups:InvalidateSpec(unit)
    if not Public(unit) or type(unit) ~= "string" then return end
    local guid = UnitGUID(unit)
    if Public(guid) and type(guid) == "string" then specCache[guid], inspectRequests[guid] = nil, nil end
end

local function Clamp(value, default, low, high)
    if type(value) ~= "number" or value ~= value then return default end
    return math.max(low, math.min(high, value))
end

local function Editable()
    if InCombatLockdown() then return false end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, value = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or (issecretvalue and issecretvalue(value)) or value then return false end
    end
    return true
end

local function BarIndex(id)
    local index = type(id) == "string" and tonumber(id:match("^bar(%d)$"))
    return index and index >= 1 and index <= BAR_COUNT and index or nil
end

function Groups:ModuleName(id)
    if id == "common" then return "SkillTrace_common" end
    local index = BarIndex(id)
    return index and "SkillTrace_bar" .. index or nil
end

function Groups:Keys(id)
    return "skilltracker", self:ModuleName(id)
end

function Groups:Category(id) return categoryOf[id] end

function Groups:Invalidate() wipe(cache) end

-- [REFACTOR] Old fixed-group selections become the per-spell enable lists; old group tables stay.
local function NormalizeSelections(db, modules)
    local oldGroups = type(db.groups) == "table" and db.groups
    local migrate = not (oldGroups and oldGroups[1] == "common")
    local selections, enabled = {}, {}
    if migrate then
        for _, id in ipairs(oldGroups or {"cooldowns", "defensives"}) do
            if type(id) == "string" and (id == "cooldowns" or id == "defensives" or id:match("^group%d+$")) then
                local group = db[id]
                if type(group) == "table" then
                    local source = type(group.spells) == "table" and group.spells or Data[id] or {}
                    for _, category in ipairs(Data.categories) do
                        selections[category] = selections[category] or {}
                        for class, catalog in pairs(Data[category]) do
                            local selected = type(source[class]) == "table" and source[class] or {}
                            local list = selections[category][class] or {}
                            selections[category][class] = list
                            for _, spellID in ipairs(catalog) do
                                for _, saved in ipairs(selected) do
                                    if saved == spellID then
                                        list[spellID] = true
                                        local moduleName = LEGACY_MODULES[id] or "SkillTrace_" .. id
                                        if modules[moduleName] then enabled[category] = true end
                                        break
                                    end
                                end
                            end
                        end
                    end
                    if not LEGACY_MODULES[id] then modules["SkillTrace_" .. id] = false end
                end
            end
        end
    end
    for _, id in ipairs(LEGACY_ORDER) do
        if type(db[id]) ~= "table" then db[id] = ns:DeepCopy(ns.defaults.profile.CooldownTrace[id]) end
        local group = db[id]
        ns:MergeDefaults(group, ns.defaults.profile.CooldownTrace[id] or ns.defaults.profile.CooldownTrace.cooldowns)
        group.name = L[LEGACY_NAMES[id]]
        if id ~= "common" then
            if type(group.separate) ~= "boolean" then group.separate = true end
            if migrate then
                group.spells = {}
                for class, catalog in pairs(Data[id]) do
                    local list = {}
                    group.spells[class] = list
                    for _, spellID in ipairs(catalog) do
                        if id == "cc" or (selections[id] and selections[id][class] and selections[id][class][spellID]) then
                            list[#list+1] = spellID
                        end
                    end
                end
                if enabled[id] then modules[LEGACY_MODULES[id]] = true end
            elseif type(group.spells) ~= "table" then group.spells = ns:DeepCopy(Data[id]) end
            for class, spells in pairs(group.spells) do
                if not Data[id][class] or type(spells) ~= "table" then group.spells[class] = nil
                else
                    local allowed, seen = {}, {}
                    for _, spellID in ipairs(Data[id][class]) do allowed[spellID] = true end
                    for index = #spells, 1, -1 do
                        local spellID = spells[index]
                        if type(spellID) ~= "number" or not allowed[spellID] or seen[spellID] then table.remove(spells, index)
                        else seen[spellID] = true end
                    end
                end
            end
        end
        if id == "common" and migrate then modules.SkillTrace_common = true end
        if id ~= "common" and modules[LEGACY_MODULES[id]] == nil then modules[LEGACY_MODULES[id]] = false end
    end
    db.groups = {unpack(LEGACY_ORDER)}
end

-- [REFACTOR] A shown fixed group becomes an enabled extra bar with its old placement.
local function BarFromGroup(group, bar, shown)
    local size = Clamp(group.iconSize, 36, 20, 48)
    local barsStyle = group.displayStyle == "bars"
    local side = SIDE_POINTS[group.attachSide] or SIDE_POINTS.RIGHT
    bar.name = group.name
    bar.redirect = shown
    bar.locked = true
    bar.unitBar = group.attachTo == "party" and group.memberLayout ~= "all"
    bar.anchor, bar.attach = side[1], side[2]
    bar.offsetX, bar.offsetY = Clamp(group.offsetX, 0, -500, 500), Clamp(group.offsetY, 0, -500, 500)
    local oldScale = Clamp(group.scale, 1, .5, 1.5)
    bar.layout = barsStyle and "vertical" or "horizontal"
    bar.progressBar = barsStyle
    bar.columns = barsStyle and 15 or math.floor(Clamp(group.columns, 8, 1, 30))
    bar.scale = math.max(.2, math.floor(size / 36 * oldScale * 100 + .5) / 100)
    if type(group.position) == "table" then
        -- Offsets are in the frame's scale; keep the same screen spot under the bar's new scale.
        bar.position = ns:DeepCopy(group.position)
        local factor = oldScale / bar.scale
        for _, axis in ipairs({"x", "y"}) do
            local value = bar.position[axis]
            if type(value) == "number" then bar.position[axis] = math.floor(value * factor * 10 + .5) / 10 end
        end
    end
    bar.paddingX, bar.paddingY = Clamp(group.gapX, 3, -1, 20), Clamp(group.gapY, 3, -1, 20)
    bar.growUpward = group.grow == "UP"
    bar.growLeft = group.align == "RIGHT"
    bar.sortBy = group.sortOrder == "spell" and "priority" or "remaining_priority"
    bar.statusBarWidth = Clamp(Clamp(group.barWidth, 220, 140, 400) - size, 205, 50, 300)
    bar.classColor = group.nameClassColor == true
end

local function MigrateFrames(db, modules)
    if db.frameVersion == 1 then return end
    local commonOn = modules.SkillTrace_common ~= false
    local plan, visible = {}, false
    for _, category in ipairs(Data.categories) do
        local group = db[category]
        local shown = modules[LEGACY_MODULES[category]] == true
        plan[category] = shown and (group.separate == false and (commonOn and "common" or "hidden") or "bar") or "hidden"
        if plan[category] ~= "hidden" then visible = true end
    end
    local nextBar = 2
    for _, category in ipairs(Data.categories) do
        -- A profile that showed nothing starts with OmniCD's default: every type on the party frame.
        if not visible or plan[category] == "common" then
            db.frames[category] = 0
        else
            local key = "bar" .. nextBar
            BarFromGroup(db[category], db.extraBars[key], plan[category] == "bar")
            modules["SkillTrace_" .. key] = plan[category] == "bar"
            db.frames[category] = nextBar
            nextBar = nextBar + 1
        end
    end
    modules.SkillTrace_common = true
    db.frameVersion = 1
end

local function AdoptEffects(bar, source)
    if type(source) ~= "table" then return end
    for _, field in ipairs(FX_FIELDS) do
        if bar[field] == nil and source[field] ~= nil then bar[field] = ns:DeepCopy(source[field]) end
    end
end

local function SanitizeFrames(db)
    for _, key in ipairs({"frames", "priority", "spellFrame", "spellPriority", "spellGlow", "extraBars"}) do
        if type(db[key]) ~= "table" then db[key] = ns:DeepCopy(ns.defaults.profile.CooldownTrace[key]) end
    end
    for _, category in ipairs(Data.categories) do
        db.frames[category] = math.floor(Clamp(db.frames[category], 0, 0, BAR_COUNT))
        db.priority[category] = math.floor(Clamp(db.priority[category], ns.defaults.profile.CooldownTrace.priority[category], 0, 100))
    end
    for _, key in ipairs({"spellFrame", "spellPriority", "spellGlow"}) do
        for id, value in pairs(db[key]) do
            local valid = categoryOf[id] and (key == "spellGlow" and value == false
                or key == "spellFrame" and type(value) == "number" and value >= 0 and value <= BAR_COUNT
                or key == "spellPriority" and type(value) == "number" and value >= 0 and value <= 100)
            if not valid then db[key][id] = nil end
        end
    end
    for index = 1, BAR_COUNT do
        local key = "bar" .. index
        if type(db.extraBars[key]) ~= "table" then db.extraBars[key] = ns:DeepCopy(ns.defaults.profile.CooldownTrace.extraBars[key]) end
        -- [REFACTOR] A bar without its own effect options adopts frame 0's current values once,
        -- so the screen looks the same; afterwards each bar is edited on its own.
        AdoptEffects(db.extraBars[key], db.common)
        ns:MergeDefaults(db.extraBars[key], ns.defaults.profile.CooldownTrace.extraBars[key])
    end
end

function Groups:Initialize()
    local db, modules = ns.db.profile.CooldownTrace, ns.db.profile.modules
    -- [REFACTOR] Only active legacy trackers opt in; the common frame default is not user consent.
    if modules.SkillTracker == nil then
        modules.SkillTracker = false
        for name, enabled in pairs(modules) do
            if enabled == true and type(name) == "string" and (name == "CooldownTracker"
                or name == "DefensiveTracker" or name == "SkillTrace_cc"
                or name:match("^SkillTrace_group%d+$") or name:match("^SkillTrace_bar[1-8]$")) then
                modules.SkillTracker = true
                break
            end
        end
    end
    NormalizeSelections(db, modules)
    SanitizeFrames(db)
    MigrateFrames(db, modules)
    -- [STYLE] Keep the old frame scale for placement/text; size changes now affect only icon pixels.
    if db.common.pixelSize == nil then
        db.common.pixelSize = Clamp(db.common.iconSize, 36, 20, 48) * Clamp(db.common.scale, .8, .5, 1.5)
    end
    -- Frame 0 always follows the master switch, like OmniCD's raid-frame icons.
    modules.SkillTrace_common = true
    for index = 1, BAR_COUNT do
        local bar = db.extraBars["bar" .. index]
        if bar.pixelSize == nil then bar.pixelSize = 36 * Clamp(bar.scale, .6, .2, 2) end
        if modules["SkillTrace_bar" .. index] == nil then modules["SkillTrace_bar" .. index] = false end
    end
    self:Invalidate()
    for _, id in ipairs(self:Ids()) do
        local moduleName = self:ModuleName(id)
        if not ns.modules[moduleName] then
            ns.DDingToolKit:RegisterModule(moduleName, ns.CooldownTraceEngine.New(moduleName, id))
        end
    end
end

function Groups:Ids()
    local ids = {"common"}
    for index = 1, BAR_COUNT do ids[#ids+1] = "bar" .. index end
    return ids
end

function Groups:Definitions()
    self:Initialize()
    local definitions = {}
    for _, id in ipairs(self:Ids()) do
        definitions[#definitions+1] = {"skilltracker", self:ModuleName(id), id}
    end
    return definitions
end

function Groups:Bar(index)
    return ns.db.profile.CooldownTrace.extraBars["bar" .. index]
end

-- OmniCD keeps "Interrupts" as bar 1's default name and the number for the others.
function Groups:BarName(index)
    local bar = self:Bar(index)
    local name = bar and bar.name
    if type(name) == "string" and name ~= "" then return name end
    return index == 1 and L["CT_BAR_INTERRUPTS"] or tostring(index)
end

function Groups:BarEnabled(index)
    return ns.db.profile.modules["SkillTrace_bar" .. index] == true
end

function Groups:Frame(id)
    local db = ns.db.profile.CooldownTrace
    local frame = db.spellFrame[id]
    if type(frame) ~= "number" then frame = db.frames[categoryOf[id]] end
    return math.floor(Clamp(frame, 0, 0, BAR_COUNT))
end

function Groups:TypeFrame(category) return ns.db.profile.CooldownTrace.frames[category] or 0 end

-- A disabled bar sends its spells to the party frame unless OmniCD's redirect is off.
function Groups:DisplayFrame(id)
    local frame = self:Frame(id)
    if frame > 0 and not self:BarEnabled(frame) then
        local bar = self:Bar(frame)
        if bar and bar.redirect == false then return nil end
        return 0
    end
    return frame
end

function Groups:Priority(id)
    local db = ns.db.profile.CooldownTrace
    local priority = db.spellPriority[id]
    if type(priority) ~= "number" then priority = db.priority[categoryOf[id]] end
    return priority or 0
end

function Groups:Glow(id)
    return ns.db.profile.CooldownTrace.spellGlow[id] ~= false
end

function Groups:IsSelected(id, class)
    local category = categoryOf[id]
    local group = category and ns.db.profile.CooldownTrace[category]
    for _, candidate in ipairs(group and (group.spells or Data[category])[class] or {}) do
        if candidate == id then return true end
    end
    return false
end

-- Enabled spells of one frame in catalog order (types in DDingUI order).
function Groups:Spells(frame, class)
    local key = tostring(frame) .. ":" .. tostring(class)
    local list = cache[key]
    if list then return list end
    list = {}
    local db = ns.db.profile.CooldownTrace
    for _, category in ipairs(Data.categories) do
        local selected = {}
        for _, id in ipairs((db[category].spells or Data[category])[class] or {}) do selected[id] = true end
        for _, id in ipairs(Data[category][class] or {}) do
            if selected[id] and self:DisplayFrame(id) == frame then list[#list+1] = id end
        end
    end
    cache[key] = list
    return list
end

-- [REFACTOR] Carry observed uses across layout changes before hidden rows discard their ledgers.
function Groups:Refresh(syncEnabled)
    self:Invalidate()
    local modules, uses = {}, {}
    for _, id in ipairs(self:Ids()) do
        local mod = ns.modules[self:ModuleName(id)]
        if mod then modules[#modules+1] = mod end
    end
    for _, mod in ipairs(modules) do
        for guid, spells in pairs(mod.ledger or {}) do
            uses[guid] = uses[guid] or {}
            for spellID, state in pairs(spells) do
                local previous = uses[guid][spellID]
                if not previous or state.started > previous.started then uses[guid][spellID] = state end
            end
        end
    end
    for _, mod in ipairs(modules) do
        if syncEnabled then
            local profile = ns.db.profile.modules
            local enabled = profile.SkillTracker ~= false and profile[mod.moduleName] == true
            if enabled and not mod.running then mod:OnEnable()
            elseif not enabled and (mod.running or mod.preview) then mod:OnDisable() end
            mod.enabled = enabled
        end
        if mod.running then mod.ledger = ns:DeepCopy(uses); mod:ApplySettings() end
    end
end

function Groups:SetEnabled(id, enabled)
    if type(enabled) ~= "boolean" then return end
    if id ~= nil and not BarIndex(id) then return end
    ns.db.profile.modules[id and self:ModuleName(id) or "SkillTracker"] = enabled
    self:Refresh(true)
end

local function SetOverride(store, id, value, typeValue)
    if value == typeValue then store[id] = nil else store[id] = value end
end

-- OmniCD Frame/Priority tabs: a type change drops spell overrides that now match it.
function Groups:SetTypeFrame(category, value)
    if not Editable() then return nil, "CT_GROUP_COMBAT" end
    if not LEGACY_MODULES[category] or type(value) ~= "number" then return end
    local db = ns.db.profile.CooldownTrace
    value = math.floor(Clamp(value, 0, 0, BAR_COUNT))
    db.frames[category] = value
    for id, frame in pairs(db.spellFrame) do
        if categoryOf[id] == category and frame == value then db.spellFrame[id] = nil end
    end
    self:Refresh()
    return true
end

function Groups:SetTypePriority(category, value)
    if not LEGACY_MODULES[category] or type(value) ~= "number" then return end
    local db = ns.db.profile.CooldownTrace
    value = math.floor(Clamp(value, 0, 0, 100))
    db.priority[category] = value
    for id, priority in pairs(db.spellPriority) do
        if categoryOf[id] == category and priority == value then db.spellPriority[id] = nil end
    end
    self:Refresh()
    return true
end

function Groups:SetSpellFrame(id, value)
    if not Editable() then return nil, "CT_GROUP_COMBAT" end
    if not categoryOf[id] or type(value) ~= "number" then return end
    local db = ns.db.profile.CooldownTrace
    SetOverride(db.spellFrame, id, math.floor(Clamp(value, 0, 0, BAR_COUNT)), db.frames[categoryOf[id]])
    self:Refresh()
    return true
end

function Groups:SetSpellPriority(id, value)
    if not categoryOf[id] or type(value) ~= "number" then return end
    local db = ns.db.profile.CooldownTrace
    SetOverride(db.spellPriority, id, math.floor(Clamp(value, 0, 0, 100)), db.priority[categoryOf[id]])
    self:Refresh()
    return true
end

function Groups:SetSpellGlow(id, enabled)
    if not categoryOf[id] or type(enabled) ~= "boolean" then return end
    -- Glow is on by default; only an explicit "off" is stored.
    if enabled then ns.db.profile.CooldownTrace.spellGlow[id] = nil else ns.db.profile.CooldownTrace.spellGlow[id] = false end
    self:Refresh()
    return true
end

function Groups:SetSpells(category, class, spellID, selected, frame)
    if not Editable() then return nil, "CT_GROUP_COMBAT" end
    if not LEGACY_MODULES[category] then return end
    local catalog = Data[category] and Data[category][class]
    local db = ns.db.profile.CooldownTrace[category]
    if not catalog or not db then return end
    if frame ~= nil and (type(frame) ~= "number" or frame < 0 or frame > BAR_COUNT or frame % 1 ~= 0) then return end
    local allowed = {}
    for _, candidate in ipairs(catalog) do allowed[candidate] = true end
    if spellID and not allowed[spellID] then return end
    local spells = db.spells[class] or {}
    db.spells[class] = spells
    for _, candidate in ipairs(spellID and {spellID} or catalog) do
        -- [REFACTOR] Selecting a spell in a group moves its existing assignment there.
        if selected and frame ~= nil then
            local trace = ns.db.profile.CooldownTrace
            SetOverride(trace.spellFrame, candidate, frame, trace.frames[category])
        end
        local found
        for index, existing in ipairs(spells) do
            if existing == candidate then
                found = true
                if not selected and (frame == nil or self:Frame(candidate) == frame) then table.remove(spells, index) end
                break
            end
        end
        if selected and not found then spells[#spells+1] = candidate end
    end
    self:Refresh()
    return true
end

-- OmniCD Spells tab: "Clear all" unchecks every spell, "Reset" restores defaults; both drop overrides.
function Groups:ResetSpells(restore, frame)
    if not Editable() then return nil, "CT_GROUP_COMBAT" end
    if frame ~= nil and (type(frame) ~= "number" or frame < 0 or frame > BAR_COUNT or frame % 1 ~= 0) then return end
    local db = ns.db.profile.CooldownTrace
    -- [REFACTOR] Group actions keep assignments and other groups' spell settings intact.
    if frame ~= nil then
        for _, category in ipairs(Data.categories) do
            for class, catalog in pairs(Data[category]) do
                local spells = db[category].spells[class] or {}
                for index = #spells, 1, -1 do
                    if self:Frame(spells[index]) == frame then table.remove(spells, index) end
                end
                for _, id in ipairs(catalog) do
                    if self:Frame(id) == frame then
                        if restore then spells[#spells+1] = id end
                        db.spellPriority[id], db.spellGlow[id] = nil, nil
                    end
                end
                db[category].spells[class] = spells
            end
        end
        self:Refresh()
        return true
    end
    wipe(db.spellFrame); wipe(db.spellPriority); wipe(db.spellGlow)
    for _, category in ipairs(Data.categories) do
        local spells = {}
        for class, catalog in pairs(Data[category]) do spells[class] = restore and {unpack(catalog)} or {} end
        db[category].spells = spells
    end
    self:Refresh()
    return true
end

function Groups:RenameBar(index, name)
    local bar = self:Bar(index)
    if not bar then return end
    if type(name) ~= "string" or name:match("^%s*$") then name = nil end
    bar.name = name
    self:Refresh()
end

function Groups:ResetBarPosition(index)
    local bar = self:Bar(index)
    if not bar then return end
    local default = ns.defaults.profile.CooldownTrace.extraBars["bar" .. index].position
    bar.position = ns:DeepCopy(default)
    self:Refresh()
end

function Groups:ResetBar(index)
    if not self:Bar(index) then return end
    ns.db.profile.CooldownTrace.extraBars["bar" .. index] = ns:DeepCopy(ns.defaults.profile.CooldownTrace.extraBars["bar" .. index])
    local bar = ns.db.profile.CooldownTrace.extraBars["bar" .. index]
    bar.pixelSize = 36 * bar.scale
    AdoptEffects(bar, ns.defaults.profile.CooldownTrace.common)
    self:Refresh()
end
