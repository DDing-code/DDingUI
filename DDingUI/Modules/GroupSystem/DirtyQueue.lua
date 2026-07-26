local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local DirtyQueue = {}
DDingUI.GroupDirtyQueue = DirtyQueue

local dirty = {
    full = false,
    fullRefresh = false,
    cdm = false,
    cdmIDs = {},
    cdmForceLayout = false,
    dynamic = false,
    dynamicSources = nil,
    dynamicProbe = false,
}

local dispatchFrame
local flushHandler
local enabled = false
local lastFlushAt = 0

local function Now()
    return GetTime and GetTime() or 0
end

local function NormalizeDelay(delay)
    delay = tonumber(delay) or 0
    return delay > 0 and delay or 0
end

local function MergeSources(sourceKeys)
    if sourceKeys == true or dirty.dynamicSources == true then
        dirty.dynamicSources = true
        return
    end
    if type(sourceKeys) ~= "table" then return end

    dirty.dynamicSources = type(dirty.dynamicSources) == "table" and dirty.dynamicSources or {}
    for sourceKey in pairs(sourceKeys) do
        dirty.dynamicSources[sourceKey] = true
    end
end

local function HasDirtyWork()
    return dirty.full or dirty.cdm or dirty.dynamic
end

local function ResetDirtyState()
    dirty.full = false
    dirty.fullDueAt = nil
    dirty.fullRefresh = false
    dirty.cdm = false
    dirty.cdmDueAt = nil
    wipe(dirty.cdmIDs)
    dirty.cdmForceLayout = false
    dirty.dynamic = false
    dirty.dynamicDueAt = nil
    dirty.dynamicSources = nil
    dirty.dynamicProbe = false
end

local function EnsureDispatchFrame()
    if dispatchFrame then return end
    dispatchFrame = CreateFrame("Frame")
    dispatchFrame:Hide()
    dispatchFrame:SetScript("OnUpdate", function(self)
        if not enabled or not flushHandler or not HasDirtyWork() then
            self:Hide()
            return
        end

        local now = Now()
        local minInterval = (InCombatLockdown and InCombatLockdown()) and 0.08 or 0.05
        if lastFlushAt > 0 and (now - lastFlushAt) < minInterval then return end

        local batch
        if dirty.full and (dirty.fullDueAt or 0) <= now then
            batch = { full = true, fullRefresh = dirty.fullRefresh }
            ResetDirtyState()
        else
            local cdmReady = dirty.cdm and (dirty.cdmDueAt or 0) <= now
            local dynamicReady = dirty.dynamic and (dirty.dynamicDueAt or 0) <= now
            if not cdmReady and not dynamicReady then return end

            batch = {}
            if cdmReady then
                batch.cdmIDs = dirty.cdmIDs
                batch.cdmForceLayout = dirty.cdmForceLayout
                dirty.cdm = false
                dirty.cdmDueAt = nil
                dirty.cdmIDs = {}
                dirty.cdmForceLayout = false
            end
            if dynamicReady then
                batch.dynamicSources = dirty.dynamicSources
                batch.dynamicProbe = dirty.dynamicProbe
                dirty.dynamic = false
                dirty.dynamicDueAt = nil
                dirty.dynamicSources = nil
                dirty.dynamicProbe = false
            end
        end

        flushHandler(batch)
        lastFlushAt = Now()
        if not HasDirtyWork() then self:Hide() end
    end)
end

local function Wake()
    if not enabled then return end
    EnsureDispatchFrame()
    dispatchFrame:Show()
end

function DirtyQueue:SetHandler(handler)
    flushHandler = handler
end

function DirtyQueue:SetEnabled(value)
    enabled = value == true
    if not enabled then
        ResetDirtyState()
        lastFlushAt = 0
        if dispatchFrame then dispatchFrame:Hide() end
    elseif HasDirtyWork() then
        Wake()
    end
end

function DirtyQueue:MarkFull(delay, fullRefresh)
    if not enabled then return end
    if not dirty.full then
        dirty.full = true
        dirty.fullDueAt = Now() + NormalizeDelay(delay)
    end
    dirty.fullRefresh = dirty.fullRefresh or fullRefresh == true
    dirty.cdm = false
    dirty.cdmDueAt = nil
    wipe(dirty.cdmIDs)
    dirty.cdmForceLayout = false
    dirty.dynamic = false
    dirty.dynamicDueAt = nil
    dirty.dynamicSources = nil
    dirty.dynamicProbe = false
    Wake()
end

function DirtyQueue:MarkCDM(changes, delay)
    if not enabled or dirty.full then return end
    if not dirty.cdm then
        dirty.cdm = true
        dirty.cdmDueAt = Now() + NormalizeDelay(delay)
    end
    if type(changes) ~= "table" then
        dirty.cdmForceLayout = true
    else
        if changes.forceLayout then dirty.cdmForceLayout = true end
        if type(changes.ids) == "table" then
            for cooldownID in pairs(changes.ids) do
                dirty.cdmIDs[cooldownID] = true
            end
        end
    end
    Wake()
end

function DirtyQueue:MarkDynamic(sourceKeys, delay, probe)
    if not enabled or dirty.full then return end
    if not dirty.dynamic then
        dirty.dynamic = true
        dirty.dynamicDueAt = Now() + NormalizeDelay(delay)
    end
    if sourceKeys == true then
        dirty.dynamicSources = true
    elseif type(sourceKeys) == "table" then
        MergeSources(sourceKeys)
    elseif not probe then
        dirty.dynamicSources = true
    end
    dirty.dynamicProbe = dirty.dynamicProbe or probe == true
    Wake()
end

function DirtyQueue:Clear()
    ResetDirtyState()
    if dispatchFrame then dispatchFrame:Hide() end
end
