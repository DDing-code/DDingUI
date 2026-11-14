local _, ns = ...
local Data = ns.CooldownTraceData

-- [12.0.1] Hidden party uses, after the KiraUI 1.26 PartyCDs principle (new code, no KiraUI source).
-- Party casts are secret in 12.1, so a use is the rising edge of the caster's buff. Each watched
-- buff has an off-screen aura group whose one element is wider than the screen: while the buff is
-- up the container grows under the cursor and IsMouseOver answers (secret in combat).
-- Secret answers never reach Lua branches: C_CurveUtil picks numbers with them, and those numbers
-- only move status bars (CooldownTrace.lua draws them), including public uses.
local Sensor = {wants={}, engines={}, timers={}, sensors={}, pending={}, quick={}, guids={}, present={}, faults=0}
ns.CooldownTraceSensor = Sensor

local Eval = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
local UNITS = {"player", "party1", "party2", "party3", "party4"}
local CODES = 254          -- whole steps a stamp can hold; values travel as 0..1 in 1/255 steps
local STRIDE = 50000       -- one lit element is wider than any screen
local READ_EVERY, READS, SETTLE = .2, 2, .5
Sensor.CODES = CODES

local function Secret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function PublicNumber(value)
    return not Secret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

-- Whole seconds keep stamps, strip lines and the grey cover on the same clock.
function Sensor.Now() return math.floor(GetTime() + .5) end

-- Base seconds shared with the public ledger; talent reductions are not known.
function Sensor.Seconds(id)
    if Data.noEstimate[id] then return nil end
    return Data.baseCooldowns[id]
end

-- Stamps are whole 1/255 steps; a client that rounds them would drift, so it stays public-only.
local function SelfTest()
    if type(Eval) ~= "function" then return false end
    for _, step in ipairs({0, 1, 48, 85, 127, 200, 254, 255}) do
        local want = step / 255
        local value = want
        for pass = 1, 16 do
            local yes = pass % 2 == 1
            local ok, answer = pcall(Eval, yes, yes and value or 0, yes and 0 or value)
            if not ok then return false end
            if Secret(answer) then return true end
            if not PublicNumber(answer) or math.abs(answer - want) > 1e-6 then return false end
            value = answer
        end
    end
    return true
end
Sensor.available = SelfTest()

local host
local function Quiet(button)
    pcall(button.SetSize, button, 1, 1)
    pcall(button.EnableMouse, button, false)
end

-- Containers are built outside combat; a refused step stays pending for the next sync.
local function Build(entry, unit, id, short, filter)
    if Sensor.broken then return false end
    if InCombatLockdown() and not (entry.container and entry.grouped and entry.bound) then return false end
    local container = entry.container
    if not container then
        if not host then
            host = CreateFrame("Frame", nil, UIParent)
            host:SetSize(1, 1)
            host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        end
        local ok, made = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
        if not ok or not made then Sensor.broken = true; return false end
        container = made
        container:SetSize(1, 1)
        -- Just left of the screen: only a lit group reaches the cursor.
        container:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -11, 0)
        pcall(container.EnableMouse, container, false)
        entry.container = container
    end
    if not entry.grouped then
        local include = {}
        for _, auraID in ipairs((filter and Data.ccDebuffs[id]) or Data.auraIDs[id] or {id}) do include[auraID] = true end
        local config = {
            maxFrameCount = 1,
            candidateFilters = {includeSpellIDs = include, maxDuration = short},
            initializeFrame = Quiet,
            layout = {elementWidth = STRIDE, elementHeight = 1, elementSpacing = 0, lineSpacing = 0},
        }
        entry.grouped = pcall(container.AddAuraGroup, container, "use", filter or "HELPFUL", config)
        if not entry.grouped and filter == "HARMFUL|!PLAYER" then
            entry.grouped = pcall(container.AddAuraGroup, container, "use", "HARMFUL", config)
        end
        if not entry.grouped then return false end
    end
    if not entry.bound then
        entry.bound = not unit or pcall(container.SetUnit, container, unit)
        if not entry.bound then return false end
    end
    return true
end

local function Switch(entry, on)
    if entry.on == on or (on and not entry.bound) then return end
    local container = entry.container
    if container.SetEnabled and not pcall(container.SetEnabled, container, on) then return end
    entry.on = on
    if on then pcall(container.UpdateAllAuras, container) end
end

local function Entry(unit, id, short)
    local list = Sensor.sensors[unit]
    local pair = list and list[id]
    return pair and pair[short and "short" or "main"]
end

-- true/false in public, a secret boolean in combat; never branched on here.
local function Lit(entry)
    local container = entry and entry.on and entry.container
    if not container then return false end
    local ok, lit = pcall(container.IsMouseOver, container, 1e5, -1e5, 0, 0)
    if not ok then return false end
    if Secret(lit) then return lit end
    return lit == true
end

-- One reading of a timer's inputs: the caster's buff (minus short proc copies) and, for
-- external buffs, the same buff on any other party member.
local function Read(timer, signal)
    local unit, id = timer.unit, timer.id
    if Data.ccDebuffs[id] then
        Sensor.stops:Read(id, signal)
        return
    end
    signal.hasMain = not Data.others[id]
    signal.hasShort = signal.hasMain and Data.short[id] ~= nil
    if signal.hasMain then signal.main = Lit(Entry(unit, id)) end
    if signal.hasShort then signal.short = Lit(Entry(unit, id, true)) end
    local count = 0
    if Data.zone[id] then
        for _, other in ipairs(UNITS) do
            if other ~= unit and Sensor.present[other] then
                count = count + 1
                signal[count] = Lit(Entry(other, id))
            end
        end
    end
    for index = count + 1, signal.n do signal[index] = nil end
    signal.n = count
end

-- Public state only: known=false as soon as one input is secret.
local function Known(signal)
    local up = false
    if signal.hasMain then
        if Secret(signal.main) or (signal.hasShort and Secret(signal.short)) then return false end
        up = signal.main == true and not (signal.hasShort and signal.short == true)
    end
    for index = 1, signal.n do
        if Secret(signal[index]) then return false end
        if signal[index] == true then up = true end
    end
    return true, up
end

-- a while the buff is up, b otherwise; works the same for public and secret inputs.
local function Choose(signal, a, b)
    local result = b
    if signal.hasMain then
        if signal.hasShort then
            result = Eval(signal.main, Eval(signal.short, b, a), b)
        else
            result = Eval(signal.main, a, b)
        end
    end
    for index = 1, signal.n do result = Eval(signal[index], a, result) end
    return result
end

-- Two slots: a stamp keeps its own epoch while new uses go to a fresh 254-step window.
local function Clear(timer, n)
    for k = 1, 2 do
        local slot = timer.slots[k]
        slot.c, slot.v, slot.epoch = 1, 0, n
    end
    timer.cur, timer.pub, timer.primed = 1, 1, false
    timer.readyAt = GetTime() + SETTLE
    timer.version = (timer.version or 0) + 1
end

local function Roll(timer, n)
    if n - timer.slots[timer.cur].epoch < timer.period then return end
    timer.cur = 3 - timer.cur
    local slot = timer.slots[timer.cur]
    slot.c, slot.v, slot.epoch = 1, 0, n
    timer.version = timer.version + 1
end

-- Use time as a step count from the slot epoch, stored as (255 - code) / 255.
local function Stamp(timer, n)
    local code = math.floor((n - timer.slots[timer.cur].epoch) / timer.u)
    code = math.max(0, math.min(CODES, code))
    return (255 - code) / 255
end

local function NewTimer(unit, id)
    local seconds = Sensor.Seconds(id)
    if not seconds then return nil end
    seconds = math.max(1, math.floor(seconds + .5))
    local u = math.max(1, math.ceil(seconds / CODES))
    local timer = {unit=unit, id=id, seconds=seconds, u=u, period=CODES * u, slots={{}, {}},
        signal={n=0}, previous={n=0}}
    Clear(timer, Sensor.Now())
    return timer
end

function Sensor:Public(unit, id, started)
    local timer = self.timers[unit] and self.timers[unit][id]
    if not timer then return end
    timer.slots[1].v, timer.slots[2].v = 0, 0
    local n = math.floor(started + .5)
    Roll(timer, n)
    local slot = timer.slots[timer.cur]
    slot.c, slot.v, timer.pub = Stamp(timer, n), 1, 0
    timer.version = timer.version + 1
end

local function Feed(timer, n)
    Roll(timer, n)
    local signal, previous = timer.signal, timer.previous
    Read(timer, signal)
    if timer.primed then
        local known, up = Known(signal)
        local knewBefore, was = Known(previous)
        -- Only a rising edge is a use; a buff already up when watching starts is a baseline.
        if not ((known and not up) or (knewBefore and was)) then
            if known and knewBefore then
                local started = GetTime() - (Data.ccLag[timer.id] or 0)
                for engine in pairs(Sensor.engines) do engine:SensedUse(timer.unit, timer.id, started) end
                Sensor:Public(timer.unit, timer.id, started)
            else
                local slot, other = timer.slots[timer.cur], timer.slots[3 - timer.cur]
                local stamp = Stamp(timer, n)
                slot.c = Choose(signal, Choose(previous, slot.c, stamp), slot.c)
                slot.v = Choose(signal, Choose(previous, slot.v, 1), slot.v)
                other.v = Choose(signal, Choose(previous, other.v, 0), other.v)
                -- A newer hidden use fades an older public timer of the same spell.
                timer.pub = Choose(signal, Choose(previous, timer.pub, 0), timer.pub)
                timer.version = timer.version + 1
            end
        end
    end
    timer.primed = true
    timer.signal, timer.previous = previous, signal
end

local ticker = CreateFrame("Frame")
ticker:Hide()
local elapsed = 0
ticker:SetScript("OnUpdate", function(self, delta)
    local now = GetTime()
    local quickBusy = false
    for unit, count in pairs(Sensor.quick) do
        if count > 0 then
            Sensor.quick[unit], quickBusy = count - 1, count > 1 or quickBusy
            for id, timer in pairs(Sensor.timers[unit] or {}) do
                if timer.active and Data.fast[id] and now >= timer.readyAt then
                    if not pcall(Feed, timer, Sensor.Now()) then Sensor.faults = Sensor.faults + 1 end
                end
            end
        end
    end
    elapsed = elapsed + delta
    if elapsed < READ_EVERY then return end
    elapsed = 0
    local n, busy, any = Sensor.Now(), quickBusy, false
    for _, unit in ipairs(UNITS) do
        if (Sensor.pending[unit] or 0) > 0 then any = true end
    end
    for unit, list in pairs(Sensor.timers) do
        local pending = (Sensor.pending[unit] or 0) > 0
        for id, timer in pairs(list) do
            if timer.active and not Data.ccDebuffs[id] then
                local due = timer.primed and (pending or (any and Data.zone[id]))
                if not timer.primed and now < timer.readyAt then busy = true
                elseif due or not timer.primed then
                    local ok = pcall(Feed, timer, n)
                    if not ok then Sensor.faults = Sensor.faults + 1 end
                end
            end
        end
    end
    for unit, count in pairs(Sensor.pending) do
        if count > 0 then
            Sensor.pending[unit] = count - 1
            if count > 1 then busy = true end
        end
    end
    if not busy then self:Hide() end
end)

-- [12.0.1] Updated-only aura payloads cannot create an edge; secret payloads are conservatively read.
local function Churns(info)
    if Secret(info) or info == nil or (issecrettable and issecrettable(info)) then return true end
    return Secret(info.isFullUpdate) or Secret(info.addedAuras) or Secret(info.removedAuraInstanceIDs)
        or info.isFullUpdate or info.addedAuras ~= nil or info.removedAuraInstanceIDs ~= nil
end

local watchers = {}
for _, unit in ipairs(UNITS) do
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function(_, _, _, info)
        local ok, churn = pcall(Churns, info)
        if ok and not churn then return end
        for id, timer in pairs(Sensor.timers[unit] or {}) do
            if timer.active and Data.fast[id] then Sensor.quick[unit] = 3; break end
        end
        Sensor.pending[unit] = READS
        if not ticker:IsShown() then elapsed = 0 end
        ticker:Show()
    end)
    watchers[unit] = watcher
end

local function Need(need, unit, id, short)
    need[unit] = need[unit] or {}
    local pair = need[unit][id] or {}
    need[unit][id] = pair
    pair[short and "short" or "main"] = short or true
end

-- Engines report the party spells they list; raid rows and the player's own spells never ask.
function Sensor:Track(engine, wants)
    self.wants[engine] = wants
    self:Sync()
end

function Sensor:Sync()
    if not self.available then return end
    local n, changed = self.Now(), false
    for _, unit in ipairs(UNITS) do
        local guid = UnitGUID(unit)
        if Secret(guid) or type(guid) ~= "string" then guid = nil end
        self.present[unit] = guid ~= nil
        if self.guids[unit] ~= guid then self.guids[unit], changed = guid, true end
    end
    local wanted = {}
    for _, wants in pairs(self.wants) do
        for unit, ids in pairs(wants) do
            wanted[unit] = wanted[unit] or {}
            for id in pairs(ids) do wanted[unit][id] = true end
        end
    end
    for unit, ids in pairs(wanted) do
        local list = self.timers[unit] or {}
        self.timers[unit] = list
        for id in pairs(ids) do list[id] = list[id] or NewTimer(unit, id) end
    end
    local need, cc, armed = {}, {}, false
    for unit, list in pairs(self.timers) do
        for id, timer in pairs(list) do
            local active = wanted[unit] and wanted[unit][id] and self.present[unit] or false
            if timer.guid ~= self.guids[unit] then
                timer.guid = self.guids[unit]
                Clear(timer, n)
            elseif changed or (active and not timer.active) then
                -- A joining member's running buff is a baseline, not a use.
                timer.primed, timer.readyAt = false, GetTime() + SETTLE
            end
            timer.active = active
            if active and Data.ccDebuffs[id] then
                cc[id] = cc[id] or {}
                cc[id][#cc[id]+1] = timer
            elseif active then
                if not timer.primed then armed = true end
                if not Data.others[id] then
                    Need(need, unit, id)
                    if Data.short[id] then Need(need, unit, id, Data.short[id]) end
                end
                if Data.zone[id] then
                    for _, other in ipairs(UNITS) do
                        if other ~= unit and self.present[other] then Need(need, other, id) end
                    end
                end
            end
        end
    end
    for _, unit in ipairs(UNITS) do
        local list = self.sensors[unit] or {}
        self.sensors[unit] = list
        for id, pair in pairs(need[unit] or {}) do
            list[id] = list[id] or {}
            for kind, value in pairs(pair) do
                local entry = list[id][kind] or {}
                list[id][kind] = entry
                if Build(entry, unit, id, kind == "short" and value or nil) then
                    local wasOn = entry.on
                    Switch(entry, true)
                    if not wasOn then
                        Sensor.pending[unit], armed = READS, true
                        -- [12.0.1] A probe first built after combat must sample a baseline again.
                        for owner, timers in pairs(self.timers) do
                            local timer = timers[id]
                            if timer and (owner == unit or Data.zone[id]) then
                                timer.primed = false
                                timer.readyAt = math.max(timer.readyAt, GetTime() + SETTLE)
                            end
                        end
                    end
                end
                if changed and entry.on then pcall(entry.container.UpdateAllAuras, entry.container) end
            end
        end
        for id, pair in pairs(list) do
            for kind, entry in pairs(pair) do
                if entry.container and not (need[unit] and need[unit][id] and need[unit][id][kind]) then Switch(entry, false) end
            end
        end
        local watcher = watchers[unit]
        if need[unit] and not watcher.watching then
            watcher:RegisterUnitEvent("UNIT_AURA", unit)
            watcher.watching = true
        elseif not need[unit] and watcher.watching then
            watcher:UnregisterAllEvents()
            watcher.watching = false
        end
    end
    if self.stops then self.stops:Sync(cc) end
    if armed then ticker:Show() end
end

function Sensor:Timer(unit, guid, id)
    local timer = self.timers[unit] and self.timers[unit][id]
    if timer and timer.active and guid ~= nil and timer.guid == guid then return timer end
end

-- Encounter and key resets: every hidden stamp is dropped and watching starts from a baseline.
function Sensor:Reset(hold)
    local n = self.Now()
    for _, list in pairs(self.timers) do
        for _, timer in pairs(list) do
            Clear(timer, n)
            if hold then timer.readyAt = GetTime() + hold end
        end
    end
    for unit in pairs(self.pending) do self.pending[unit] = READS end
    if self.stops then self.stops:Reset() end
    if self.available then ticker:Show() end
end

Sensor.Build, Sensor.Switch, Sensor.Lit, Sensor.Feed = Build, Switch, Lit, Feed
