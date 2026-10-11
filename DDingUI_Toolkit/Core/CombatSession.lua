--[[
    DDingToolKit - Combat Session
    One shared combat-state judgement for CombatTimer and CombatStateAlert. -- [REFACTOR]

    A session starts on PLAYER_REGEN_DISABLED. PLAYER_REGEN_ENABLED only makes the end
    tentative: the session ends once the player is out of combat AND no group member is in
    combat, and that "all clear" state has held for END_GRACE seconds. Re-entering combat
    (or a group member still fighting) during that window continues the same session, so
    neither a combat-end nor a new combat-start is reported.

    Callbacks: fn(kind, info)
      kind "START": info = { startedAt, silent }   silent = resumed after /reload or login
      kind "END":   info = { startedAt, endedAt, silent }  endedAt = when the all-clear began,
                    silent = the combat ended across a loading screen (no alert wanted)
    No COMBAT_LOG events, no protected calls; UnitAffectingCombat values are secret-guarded.
]]

local addonName, ns = ...

local CombatSession = {}
ns.CombatSession = CombatSession

CombatSession.END_GRACE = 2.0 -- seconds the all-clear state must hold before combat ends
CombatSession.POLL_INTERVAL = 0.25 -- polling only runs while an end is pending

local active = false
local playerInCombat = false
local startedAt
local clearSince
local endAcrossLoading = false
local ticker
local listeners = {}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- true / false; secret or failed reads count as "not in combat" so a session can still end.
local function UnitInCombat(unit)
    if type(UnitAffectingCombat) ~= "function" then return false end
    local ok, value = pcall(UnitAffectingCombat, unit)
    if not ok or IsSecret(value) then return false end
    return value == true
end

local function PlayerInCombat()
    if playerInCombat then return true end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return true end
    return UnitInCombat("player")
end

function CombatSession:IsGroupFighting()
    if type(IsInRaid) ~= "function" then return false end
    if IsInRaid() then
        for index = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local unit = "raid" .. index
            if not (UnitIsUnit and UnitIsUnit(unit, "player")) and UnitInCombat(unit) then
                return true
            end
        end
    elseif IsInGroup and IsInGroup() then
        for index = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do
            if UnitInCombat("party" .. index) then return true end
        end
    end
    return false
end

local function Fire(kind, info)
    for _, fn in pairs(listeners) do
        local ok, err = pcall(fn, kind, info)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

local function StopPolling()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Finish()
    StopPolling()
    local info = { startedAt = startedAt, endedAt = clearSince or GetTime(), silent = endAcrossLoading }
    active, startedAt, clearSince, endAcrossLoading = false, nil, nil, false
    Fire("END", info)
end

-- One poll step while an end is pending.
function CombatSession:Evaluate()
    if not active then
        StopPolling()
        return
    end
    local now = GetTime()
    if PlayerInCombat() or self:IsGroupFighting() then
        clearSince = nil
        return
    end
    clearSince = clearSince or now
    if now - clearSince >= self.END_GRACE then
        Finish()
    end
end

local function StartPolling()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(CombatSession.POLL_INTERVAL, function()
        CombatSession:Evaluate()
    end)
end

local function Begin(silent)
    clearSince = nil
    endAcrossLoading = false
    StopPolling()
    if active then return end -- re-entry inside the grace window: same session
    active = true
    startedAt = GetTime()
    Fire("START", { startedAt = startedAt, silent = silent == true })
end

function CombatSession:OnEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        playerInCombat = true
        Begin(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        playerInCombat = false
        if active then
            self:Evaluate()
            if active then StartPolling() end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-sync after loading screens / reload (REGEN events may have been missed).
        playerInCombat = (type(InCombatLockdown) == "function" and InCombatLockdown()) or UnitInCombat("player")
        if playerInCombat then
            Begin(not active)
        elseif active then
            -- Out of combat across a loading screen: end quietly (the old alert was cancelled
            -- by the loading screen too), unless combat resumes first.
            endAcrossLoading = true
            self:Evaluate()
            if active then StartPolling() end
        end
    end
end

function CombatSession:IsActive()
    return active
end

function CombatSession:GetStartedAt()
    return startedAt
end

--- Time the current all-clear began (end pending), or nil while combat continues.
function CombatSession:GetClearSince()
    return active and clearSince or nil
end

function CombatSession:RegisterCallback(owner, fn)
    listeners[owner] = fn
end

function CombatSession:UnregisterCallback(owner)
    listeners[owner] = nil
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    CombatSession:OnEvent(event)
end)
CombatSession.eventFrame = eventFrame
