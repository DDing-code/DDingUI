-- DDingUI Toolkit - runtime sound collision manager

local addonName, ns = ...

local SoundManager = {}
ns.SoundManager = SoundManager

local FALLBACK_SETTINGS = {
    enabled = true,
    mode = "PRIORITY",
    decisionWindow = 0.12,
    defaultDuration = 1.2,
    queueExpiry = 1.5,
    fadeOut = 0.08,
    pauseBackground = true,
    priorityOffsets = {},
}

local MAX_QUEUE_SIZE = 6

local pending = {}
local queued = {}
local recent = {}
local currentAlert
local background
local decisionTimer
local sequence = 0

local function Now()
    if GetTimePreciseSec then return GetTimePreciseSec() end
    return GetTime()
end

local function IsSecret(value)
    local checker = ns.IsSecretValue or issecretvalue
    if type(checker) ~= "function" then return false end
    local ok, result = pcall(checker, value)
    return ok and result == true
end

local function SafeNumber(value, fallback, minimum, maximum)
    if IsSecret(value) then return fallback end
    local ok, number = pcall(tonumber, value)
    if not ok or IsSecret(number) or number == nil or number ~= number then
        number = fallback
    end
    if minimum and number < minimum then number = minimum end
    if maximum and number > maximum then number = maximum end
    return number
end

local function GetSettings()
    local profile = ns.db and ns.db.profile
    local settings = profile and profile.SoundManager
    return type(settings) == "table" and settings or FALLBACK_SETTINGS
end

local function GetSetting(key)
    local settings = GetSettings()
    local value = settings[key]
    if value == nil then value = FALLBACK_SETTINGS[key] end
    return value
end

local function GetMode()
    if GetSetting("enabled") == false then return "OVERLAP" end
    local mode = GetSetting("mode")
    if mode ~= "QUEUE" and mode ~= "OVERLAP" then return "PRIORITY" end
    return mode
end

local function CancelTimer(timer)
    if timer and type(timer.Cancel) == "function" then
        pcall(timer.Cancel, timer)
    end
end

local function NewTimer(delay, callback)
    delay = SafeNumber(delay, 0, 0, 10)
    if delay <= 0 or not C_Timer or not C_Timer.NewTimer then
        callback()
        return nil
    end
    return C_Timer.NewTimer(delay, callback)
end

local function Notify(request, callbackName, ...)
    local callback = request and request[callbackName]
    if type(callback) == "function" then
        pcall(callback, ...)
    end
end

local function ResolvePath(request)
    local customPath = request.customPath
    if type(customPath) == "string" and customPath ~= "" then
        if not ns.IsValidSoundPath or ns:IsValidSoundPath(customPath) then
            return customPath
        end
    end

    local soundFile = request.soundFile or request.path
    if type(soundFile) == "string" and soundFile ~= "" then
        return soundFile
    end
    return nil
end

local function HasPayload(request)
    return ResolvePath(request) ~= nil
        or (not IsSecret(request.soundKit) and type(request.soundKit) == "number")
end

local function PlayRaw(request)
    local channel = request.channel or "Master"
    local path = ResolvePath(request)
    local ok, played, handle

    if path then
        ok, played, handle = pcall(PlaySoundFile, path, channel)
    elseif not IsSecret(request.soundKit) and type(request.soundKit) == "number" then
        ok, played, handle = pcall(PlaySound, request.soundKit, channel)
    else
        return false, nil
    end

    if not ok then return false, nil end
    if not IsSecret(played) and played == false then return false, nil end
    if IsSecret(handle) then handle = nil end
    return true, handle
end

local function StopHandle(entry, fadeSeconds)
    if not entry or not StopSound or IsSecret(entry.handle) or entry.handle == nil then return end
    local fadeMilliseconds = math.floor(SafeNumber(fadeSeconds, 0, 0, 1) * 1000 + 0.5)
    pcall(StopSound, entry.handle, fadeMilliseconds)
end

local function RequestIsValid(request, ignoreExpiry)
    if not request then return false end
    if not ignoreExpiry and request.expireAt <= Now() then return false end
    if type(request.isValid) == "function" then
        local ok, valid = pcall(request.isValid)
        if not ok or IsSecret(valid) or valid ~= true then return false end
    end
    return true
end

local function NormalizeRequest(request)
    if type(request) ~= "table" then return nil end

    local source = type(request.source) == "string" and request.source or "Toolkit"
    local eventKey = type(request.key) == "string" and request.key or "alert"
    local createdAt = Now()
    local expiresIn = SafeNumber(request.expiresIn, GetSetting("queueExpiry"), 0.1, 10)
    local priority = SafeNumber(request.priority, 50, 0, 1000)
    local priorityOffsets = GetSetting("priorityOffsets")
    if type(priorityOffsets) == "table" then
        priority = priority + SafeNumber(priorityOffsets[source], 0, -100, 100)
    end

    sequence = sequence + 1
    return {
        source = source,
        key = source .. ":" .. eventKey,
        soundFile = request.soundFile,
        customPath = request.customPath,
        path = request.path,
        soundKit = request.soundKit,
        channel = request.channel or "Master",
        lane = request.lane == "BACKGROUND" and "BACKGROUND" or "ALERT",
        priority = math.max(0, math.min(1000, priority)),
        duration = SafeNumber(request.duration, GetSetting("defaultDuration"), 0.1, 30),
        dedupeWindow = SafeNumber(request.dedupeWindow, 0.25, 0, 30),
        createdAt = createdAt,
        expiresIn = expiresIn,
        expireAt = createdAt + expiresIn,
        serial = sequence,
        canQueue = request.canQueue == true,
        interruptible = request.interruptible ~= false,
        immediate = request.immediate == true,
        persistent = request.persistent == true,
        isValid = request.isValid,
        onStarted = request.onStarted,
        onStopped = request.onStopped,
        onDropped = request.onDropped,
    }
end

local function DropRequest(request, reason)
    Notify(request, "onDropped", reason or "dropped")
end

local function IsDuplicate(request)
    if request.dedupeWindow <= 0 then return false end

    local lastPlayed = recent[request.key]
    if lastPlayed and request.createdAt - lastPlayed < request.dedupeWindow then
        return true
    end
    if currentAlert and currentAlert.request.key == request.key then
        return true
    end
    return false
end

local function StopBackground(reason, keepRequest, fadeSeconds)
    local entry = background
    if not entry then return end

    if entry.playing then
        StopHandle(entry, fadeSeconds)
        entry.playing = false
        entry.handle = nil
        Notify(entry.request, "onStopped", reason or "stopped")
    end

    if not keepRequest then background = nil end
end

local function StartBackground()
    if not background or background.playing then return end
    if currentAlert and GetSetting("pauseBackground") ~= false and GetMode() ~= "OVERLAP" then return end
    if (#pending > 0 or #queued > 0) and GetSetting("pauseBackground") ~= false and GetMode() ~= "OVERLAP" then return end
    if not RequestIsValid(background.request, background.request.persistent) then
        local request = background.request
        background = nil
        DropRequest(request, "expired")
        return
    end

    local played, handle = PlayRaw(background.request)
    if not played then
        local request = background.request
        background = nil
        DropRequest(request, "play-failed")
        return
    end

    background.handle = handle
    background.playing = true
    Notify(background.request, "onStarted", handle)
end

local ContinueQueue

local function FinishCurrent(reason, stopSound, continueQueue)
    local entry = currentAlert
    if not entry then return end

    currentAlert = nil
    CancelTimer(entry.releaseTimer)
    entry.releaseTimer = nil
    if stopSound then StopHandle(entry, GetSetting("fadeOut")) end
    Notify(entry.request, "onStopped", reason or "finished")

    if continueQueue and ContinueQueue then ContinueQueue() end
end

local function StartAlert(request)
    if not RequestIsValid(request) then
        DropRequest(request, "expired")
        return false
    end

    if background and background.playing and GetSetting("pauseBackground") ~= false and GetMode() ~= "OVERLAP" then
        StopBackground("suspended", true, GetSetting("fadeOut"))
    end

    local played, handle = PlayRaw(request)
    if not played then
        DropRequest(request, "play-failed")
        return false
    end

    local startedAt = Now()
    local entry = {
        request = request,
        handle = handle,
        startedAt = startedAt,
        releaseAt = startedAt + request.duration,
    }
    currentAlert = entry
    recent[request.key] = startedAt
    Notify(request, "onStarted", handle)

    entry.releaseTimer = NewTimer(request.duration, function()
        if currentAlert == entry then
            FinishCurrent("finished", true, true)
        end
    end)
    return true
end

local function RemoveQueueIndex(index, reason)
    local request = table.remove(queued, index)
    if request and reason then DropRequest(request, reason) end
    return request
end

local function RefreshSequentialExpiry()
    if GetMode() ~= "QUEUE" then return end

    local now = Now()
    local scheduledAt = now
    if currentAlert then
        scheduledAt = math.max(now, SafeNumber(currentAlert.releaseAt, now))
    end

    for _, request in ipairs(queued) do
        local grace = SafeNumber(request.expiresIn, GetSetting("queueExpiry"), 0.1, 10)
        request.expireAt = math.max(request.expireAt, scheduledAt + grace)
        scheduledAt = scheduledAt + request.duration
    end
end

local function AddToQueue(request)
    if not RequestIsValid(request) then
        DropRequest(request, "expired")
        return false
    end

    if request.dedupeWindow > 0 then
        for index = #queued, 1, -1 do
            if queued[index].key == request.key then
                DropRequest(queued[index], "replaced")
                queued[index] = request
                RefreshSequentialExpiry()
                return true
            end
        end
    end

    queued[#queued + 1] = request
    if #queued > MAX_QUEUE_SIZE then
        local removeIndex = 1
        if GetMode() == "PRIORITY" then
            for index = 2, #queued do
                local candidate = queued[index]
                local selected = queued[removeIndex]
                if candidate.priority < selected.priority
                    or (candidate.priority == selected.priority and candidate.serial > selected.serial) then
                    removeIndex = index
                end
            end
        end
        RemoveQueueIndex(removeIndex, "queue-full")
    end

    RefreshSequentialExpiry()
    return true
end

local function TakeNextQueued()
    for index = #queued, 1, -1 do
        if not RequestIsValid(queued[index]) then
            RemoveQueueIndex(index, "expired")
        end
    end
    if #queued == 0 then return nil end

    local selectedIndex = 1
    if GetMode() == "PRIORITY" then
        for index = 2, #queued do
            local candidate = queued[index]
            local selected = queued[selectedIndex]
            if candidate.priority > selected.priority
                or (candidate.priority == selected.priority and candidate.serial < selected.serial) then
                selectedIndex = index
            end
        end
    end
    return RemoveQueueIndex(selectedIndex)
end

ContinueQueue = function()
    if currentAlert then return end

    local request = TakeNextQueued()
    while request do
        if StartAlert(request) then return end
        request = TakeNextQueued()
    end
    StartBackground()
end

local function Dispatch(request)
    if not RequestIsValid(request) then
        DropRequest(request, "expired")
        return
    end

    if not currentAlert then
        if not StartAlert(request) then ContinueQueue() end
        return
    end

    local current = currentAlert.request
    if request.priority > current.priority and current.interruptible then
        FinishCurrent("preempted", true, false)
        if not StartAlert(request) then ContinueQueue() end
    elseif request.canQueue then
        AddToQueue(request)
    else
        DropRequest(request, "lower-priority")
    end
end

local function SelectHighestPriority(requests)
    local selectedIndex = 1
    for index = 2, #requests do
        local candidate = requests[index]
        local selected = requests[selectedIndex]
        if candidate.priority > selected.priority
            or (candidate.priority == selected.priority and candidate.serial < selected.serial) then
            selectedIndex = index
        end
    end
    return selectedIndex
end

local function FlushPending()
    decisionTimer = nil
    if #pending == 0 then return end

    local requests = pending
    pending = {}
    local valid = {}
    for _, request in ipairs(requests) do
        if RequestIsValid(request) then
            valid[#valid + 1] = request
        else
            DropRequest(request, "expired")
        end
    end
    if #valid == 0 then
        StartBackground()
        return
    end

    local selectedIndex = SelectHighestPriority(valid)
    local selected = valid[selectedIndex]
    for index, request in ipairs(valid) do
        if index ~= selectedIndex then
            if request.canQueue then
                AddToQueue(request)
            else
                DropRequest(request, "collision")
            end
        end
    end
    Dispatch(selected)
end

local function AddPending(request)
    if request.dedupeWindow > 0 then
        for index = #pending, 1, -1 do
            if pending[index].key == request.key then
                DropRequest(pending[index], "replaced")
                pending[index] = request
                return
            end
        end
    end

    pending[#pending + 1] = request
    if not decisionTimer then
        decisionTimer = NewTimer(GetSetting("decisionWindow"), FlushPending)
    end
end

function SoundManager:Request(request)
    request = NormalizeRequest(request)
    if not request or not HasPayload(request) then return false end

    if request.immediate then
        local played, handle = PlayRaw(request)
        if played then
            Notify(request, "onStarted", handle)
        else
            DropRequest(request, "play-failed")
        end
        return played
    end

    if request.lane == "BACKGROUND" then
        StopBackground("replaced", false, GetSetting("fadeOut"))
        background = { request = request, playing = false }
        StartBackground()
        return true
    end

    local mode = GetMode()
    if mode == "OVERLAP" then
        local played, handle = PlayRaw(request)
        if played then
            Notify(request, "onStarted", handle)
        else
            DropRequest(request, "play-failed")
        end
        return played
    end

    if IsDuplicate(request) then
        DropRequest(request, "duplicate")
        return false
    end

    if mode == "QUEUE" then
        AddToQueue(request)
        ContinueQueue()
    else
        AddPending(request)
    end
    return true
end

function SoundManager:CancelKey(key, fadeSeconds)
    if type(key) ~= "string" or key == "" then return end

    for index = #pending, 1, -1 do
        if pending[index].key == key then
            DropRequest(table.remove(pending, index), "cancelled")
        end
    end
    for index = #queued, 1, -1 do
        if queued[index].key == key then
            RemoveQueueIndex(index, "cancelled")
        end
    end

    if currentAlert and currentAlert.request.key == key then
        FinishCurrent("cancelled", true, true)
    end
    if background and background.request.key == key then
        StopBackground("cancelled", false, fadeSeconds or GetSetting("fadeOut"))
    end
    if not currentAlert and #pending == 0 and #queued == 0 then StartBackground() end
end

function SoundManager:CancelSource(source, fadeSeconds)
    if type(source) ~= "string" or source == "" then return end

    for index = #pending, 1, -1 do
        if pending[index].source == source then
            DropRequest(table.remove(pending, index), "cancelled")
        end
    end
    for index = #queued, 1, -1 do
        if queued[index].source == source then
            RemoveQueueIndex(index, "cancelled")
        end
    end

    if currentAlert and currentAlert.request.source == source then
        FinishCurrent("cancelled", true, true)
    end
    if background and background.request.source == source then
        StopBackground("cancelled", false, fadeSeconds or GetSetting("fadeOut"))
    end
    if not currentAlert and #pending == 0 and #queued == 0 then StartBackground() end
end

function SoundManager:RefreshSettings()
    if GetMode() == "OVERLAP" then
        CancelTimer(decisionTimer)
        decisionTimer = nil
        for _, request in ipairs(pending) do DropRequest(request, "settings-changed") end
        for _, request in ipairs(queued) do DropRequest(request, "settings-changed") end
        pending = {}
        queued = {}
        StartBackground()
    elseif GetMode() == "QUEUE" then
        RefreshSequentialExpiry()
        if not currentAlert then ContinueQueue() end
        if currentAlert and background and background.playing and GetSetting("pauseBackground") ~= false then
            StopBackground("suspended", true, GetSetting("fadeOut"))
        end
    elseif currentAlert and background and background.playing and GetSetting("pauseBackground") ~= false then
        StopBackground("suspended", true, GetSetting("fadeOut"))
    else
        StartBackground()
    end
end

function SoundManager:GetState()
    return {
        current = currentAlert and currentAlert.request.key or nil,
        pending = #pending,
        queued = #queued,
        background = background and background.request.key or nil,
        backgroundPlaying = background and background.playing == true or false,
    }
end

function ns:RequestSound(request)
    return SoundManager:Request(request)
end

function ns:CancelManagedSound(key, fadeSeconds)
    SoundManager:CancelKey(key, fadeSeconds)
end

function ns:CancelManagedSoundsBySource(source, fadeSeconds)
    SoundManager:CancelSource(source, fadeSeconds)
end
