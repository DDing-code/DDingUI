local _, ns = ...
local Sensor, Data = ns.CooldownTraceSensor, ns.CooldownTraceData
local Stops = {feeds={}, alive={}, slots={}}
Sensor.stops = Stops

-- [12.0.1] PartyStops principle: anonymous hostile debuffs feed every party owner of a CC spell.
-- The default pool watches ten enemies, with four probes per area spell; no saved settings.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

local function Eligible(unit)
    return Ask(UnitExists, unit) == true and Ask(UnitCanAttack, "player", unit) ~= false
        and Ask(UnitCanAssist, "player", unit) == false and Ask(UnitIsDeadOrGhost, unit) ~= true
        and Ask(UnitIsBossMob, unit) ~= true
end

local function Bind(feed)
    local index = 0
    for _, unit in ipairs(Stops.slots) do
        local fighting = Ask(UnitAffectingCombat, unit) ~= false
        if fighting or Stops.relaxed or feed.id == 2094 then
            index = index + 1
            local entry = feed.probes[index]
            if not entry then break end
            if entry.unit ~= unit or not entry.on then
                if pcall(entry.container.SetUnit, entry.container, unit) then
                    entry.unit = unit
                    Sensor.Switch(entry, true)
                    if feed.id == 2094 then feed.settle = GetTime() + .4 end
                end
            end
        end
    end
    for k = index + 1, #feed.probes do Sensor.Switch(feed.probes[k], false) end
end

function Stops:Scan()
    local slots, relaxed = {}, InCombatLockdown()
    for unit in pairs(self.alive) do
        if Eligible(unit) and Ask(UnitAffectingCombat, unit) ~= false then relaxed = false; break end
    end
    -- Combatants take the pool first; Blind also needs out-of-combat enemies.
    for pass = 1, 2 do
        for index = 1, 40 do
            local unit = "nameplate" .. index
            if self.alive[unit] and Eligible(unit) then
                local fighting = Ask(UnitAffectingCombat, unit) ~= false
                if (pass == 1 and (fighting or relaxed)) or (pass == 2 and not fighting and not relaxed and self.loose) then
                    if #slots < 10 then slots[#slots+1] = unit end
                end
            end
        end
    end
    self.slots = slots
    self.relaxed = relaxed
    for _, feed in pairs(self.feeds) do if feed.on then Bind(feed) end end
end

function Stops:Read(id, signal)
    local feed = self.feeds[id]
    local count = 0
    signal.hasMain, signal.hasShort, signal.main = true, false, false
    for _, entry in ipairs(feed and feed.on and feed.probes or {}) do
        if entry.on then count = count + 1; signal[count] = Sensor.Lit(entry) end
    end
    for index = count + 1, signal.n do signal[index] = nil end
    signal.n = count
end

local driver = CreateFrame("Frame")
driver:Hide()
local elapsed, sinceScan = 0, 0
driver:SetScript("OnUpdate", function(_, delta)
    elapsed, sinceScan = elapsed + delta, sinceScan + delta
    if elapsed < .2 then return end
    elapsed = 0
    if sinceScan >= 2 then sinceScan = 0; Stops:Scan() end
    local now, n = GetTime(), Sensor.Now()
    for id, feed in pairs(Stops.feeds) do
        if feed.on and #feed.probes > 0 then
            for _, timer in ipairs(feed.timers) do
                if now >= timer.readyAt and (id ~= 2094 or now >= feed.settle) then
                    if not pcall(Sensor.Feed, timer, n - (Data.ccLag[id] or 0)) then
                        Sensor.faults = Sensor.faults + 1
                    end
                elseif id == 2094 then timer.primed = false end
            end
        end
    end
end)

local watch = CreateFrame("Frame")
watch:SetScript("OnEvent", function(_, event, unit)
    if issecretvalue and issecretvalue(unit) then return end
    if type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
    local number = tonumber(unit:match("%d+$"))
    if not number or number < 1 or number > 40 then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then Stops.alive[unit] = nil
    elseif event == "NAME_PLATE_UNIT_ADDED" then Stops.alive[unit] = true end
    Stops:Scan()
end)

function Stops:Sync(wanted)
    local any, loose = next(wanted) ~= nil, wanted[2094] ~= nil
    self.loose = loose
    for id, timers in pairs(wanted) do
        local feed = self.feeds[id]
        if not feed then feed = {id=id, probes={}, settle=0}; self.feeds[id] = feed end
        if not feed.on then feed.settle = GetTime() + .4 end
        feed.on, feed.timers = true, timers
        if not InCombatLockdown() then
            for index = #feed.probes + 1, Data.ccAOE[id] and 4 or 10 do
                local entry = {}
                if not Sensor.Build(entry, nil, id, nil, "HARMFUL|!PLAYER") then break end
                -- Unit bindings can change in combat; only construction is deferred.
                pcall(entry.container.SetEnabled, entry.container, false)
                entry.on = false
                feed.probes[index] = entry
            end
        end
    end
    for id, feed in pairs(self.feeds) do
        if not wanted[id] then
            feed.on, feed.timers = false, nil
            for _, entry in ipairs(feed.probes) do Sensor.Switch(entry, false) end
        end
    end
    if any and not self.running then
        for index = 1, 40 do
            local unit = "nameplate" .. index
            if Ask(UnitExists, unit) == true then self.alive[unit] = true end
        end
        for _, event in ipairs({"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FLAGS"}) do
            watch:RegisterEvent(event)
        end
    elseif not any then
        watch:UnregisterAllEvents()
        wipe(self.alive)
    end
    self.running = any
    self:Scan()
    driver:SetShown(any)
end

function Stops:Reset()
    for _, feed in pairs(self.feeds) do feed.settle = GetTime() + .4 end
end
