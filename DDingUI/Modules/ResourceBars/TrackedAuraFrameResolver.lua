local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Resolver = {}
DDingUI.TrackedAuraFrameResolver = Resolver

local VIEWER_NAMES = {
    "BuffBarCooldownViewer",
    "BuffIconCooldownViewer",
}

local assignments = setmetatable({}, { __mode = "k" })
local stickyFrames = {}
local stickyCooldownIDs = {}
local stickyGenerations = {}
local frameGenerations = setmetatable({}, { __mode = "k" })
local hookedPools = setmetatable({}, { __mode = "k" })
local hookedViewers = setmetatable({}, { __mode = "k" })

local activeFrames = {}
local activeFrameSet = setmetatable({}, { __mode = "k" })
local frameCooldownIDs = setmetatable({}, { __mode = "k" })
local frameSpellIDs = setmetatable({}, { __mode = "k" })
local consumedFrames = setmetatable({}, { __mode = "k" })
local durationFontStrings = setmetatable({}, { __mode = "k" })
local currentTokens = {}

local function FindDurationFontString(statusBar)
    if not statusBar then return nil end

    local cached = durationFontStrings[statusBar]
    if cached ~= nil then return cached or nil end

    local duration = statusBar.Duration
    if duration and type(duration.GetText) == "function" then
        durationFontStrings[statusBar] = duration
        return duration
    end

    local fontStringIndex = 0
    local regions = { statusBar:GetRegions() }
    for index = 1, #regions do
        local region = regions[index]
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            fontStringIndex = fontStringIndex + 1
            if fontStringIndex == 2 then
                durationFontStrings[statusBar] = region
                return region
            end
        end
    end

    durationFontStrings[statusBar] = false
    return nil
end

local function TrackerCooldownID(tracker)
    local value = tracker and (tracker.cooldownID or (tracker.trigger and tracker.trigger.cooldownID))
    value = tonumber(value)
    return value and value > 0 and value or 0
end

local function TrackerSpellID(tracker)
    local value = tracker and (tracker.spellID or (tracker.trigger and tracker.trigger.spellID))
    value = tonumber(value)
    return value and value > 0 and value or 0
end

local function IsAuraTracker(tracker)
    if type(tracker) ~= "table" or tracker.isGroup or tracker.enabled == false then return false end
    if tracker.trackingMode == "manual" or tracker.trackingMode == "spell" then return false end
    if tracker.trigger and tracker.trigger.type == "spell" then return false end
    if tracker.isAura == false then return false end
    return TrackerCooldownID(tracker) > 0 or TrackerSpellID(tracker) > 0
end

local function TrackerToken(tracker)
    return tostring(TrackerCooldownID(tracker)) .. ":" .. tostring(TrackerSpellID(tracker))
end

local function RequestRuntimeRefresh()
    local resourceBars = DDingUI.ResourceBars
    if resourceBars and resourceBars.RequestBuffTrackerUpdate then
        resourceBars:RequestBuffTrackerUpdate("tracked-frame", 0)
    end
end

local function ReleaseStickyFrame(frame)
    for token, boundFrame in pairs(stickyFrames) do
        if boundFrame == frame then
            stickyFrames[token] = nil
            stickyCooldownIDs[token] = nil
            stickyGenerations[token] = nil
        end
    end
end

local function HookViewer(viewer)
    if not viewer then return end

    local compat = DDingUI.CDMCompat
    if compat and compat.TrackViewerPool then
        compat:TrackViewerPool(viewer)
    end

    local pool = viewer.itemFramePool
    if pool and not hookedPools[pool] and type(pool.Release) == "function" then
        hookedPools[pool] = true
        hooksecurefunc(pool, "Release", function(_, frame)
            frameGenerations[frame] = (frameGenerations[frame] or 0) + 1
            ReleaseStickyFrame(frame)
            RequestRuntimeRefresh()
        end)
    end

    if not hookedViewers[viewer] then
        hookedViewers[viewer] = true
        if type(viewer.OnAcquireItemFrame) == "function" then
            hooksecurefunc(viewer, "OnAcquireItemFrame", function()
                RequestRuntimeRefresh()
            end)
        end
        if type(viewer.RefreshLayout) == "function" then
            hooksecurefunc(viewer, "RefreshLayout", function()
                RequestRuntimeRefresh()
            end)
        end
    end
end

local function ReadCurrentCooldownID(frame)
    local compat = DDingUI.CDMCompat
    if not compat then return nil end

    if type(frame.GetCooldownID) == "function" then
        local ok, value = pcall(frame.GetCooldownID, frame)
        if ok and compat:IsUsableID(value) then return value end
    end

    local value = frame.cooldownID
    if compat:IsUsableID(value) then return value end
    return nil
end

local function ReadResolvedCooldownID(frame)
    local current = ReadCurrentCooldownID(frame)
    if current then return current end

    local compat = DDingUI.CDMCompat
    if compat and compat.GetFrameCooldownID then
        local cached = compat:GetFrameCooldownID(frame)
        if compat:IsUsableID(cached) then return cached end
    end
    return nil
end

local function ReadResolvedSpellID(frame)
    local compat = DDingUI.CDMCompat
    if not compat or not compat.ResolveFrameSpellID then return nil end
    local value = compat:ResolveFrameSpellID(frame)
    return compat:IsUsableID(value) and value or nil
end

local function InfoMatchesSpell(frame, spellID)
    if spellID <= 0 then return false end
    local compat = DDingUI.CDMCompat
    if not compat or not compat.GetFrameCooldownInfo then return false end

    local info = compat:GetFrameCooldownInfo(frame)
    if type(info) ~= "table" then return false end
    if info.overrideSpellID == spellID
        or info.overrideTooltipSpellID == spellID
        or info.spellID == spellID
        or info.linkedSpellID == spellID
    then
        return true
    end

    for _, linkedID in ipairs(info.linkedSpellIDs or {}) do
        if linkedID == spellID then return true end
    end
    return false
end

local function SnapshotFrames()
    wipe(activeFrames)
    wipe(activeFrameSet)
    wipe(frameCooldownIDs)
    wipe(frameSpellIDs)

    for _, viewerName in ipairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        HookViewer(viewer)
        local pool = viewer and viewer.itemFramePool
        if pool then
            for frame in pool:EnumerateActive() do
                if not activeFrameSet[frame] then
                    activeFrameSet[frame] = true
                    activeFrames[#activeFrames + 1] = frame
                    frameCooldownIDs[frame] = ReadResolvedCooldownID(frame)
                    frameSpellIDs[frame] = ReadResolvedSpellID(frame)
                end
            end
        end
    end
end

local function Assign(record, frame, remember)
    record.frame = frame
    consumedFrames[frame] = true
    for _, tracker in ipairs(record.trackers) do
        assignments[tracker] = frame
    end

    if remember then
        stickyFrames[record.token] = frame
        stickyCooldownIDs[record.token] = ReadCurrentCooldownID(frame)
            or frameCooldownIDs[frame]
            or record.cooldownID
        stickyGenerations[record.token] = frameGenerations[frame] or 0
    end
end

local function StickyStillMatches(record, frame)
    if not activeFrameSet[frame] then return false end
    if (frameGenerations[frame] or 0) ~= (stickyGenerations[record.token] or 0) then return false end

    local currentCooldownID = ReadCurrentCooldownID(frame)
    local boundCooldownID = stickyCooldownIDs[record.token]
    if currentCooldownID and boundCooldownID and currentCooldownID ~= boundCooldownID then
        return false
    end

    local resolvedSpellID = frameSpellIDs[frame]
    if record.needsSpellDisambiguation and resolvedSpellID then
        return resolvedSpellID == record.spellID
    end
    return true
end

function Resolver:BeginPass(trackers)
    local auraContainer = DDingUI.TrackedAuraContainer
    if auraContainer and auraContainer.Sync then
        auraContainer:Sync(trackers)
    end

    wipe(assignments)
    wipe(consumedFrames)
    wipe(currentTokens)
    SnapshotFrames()

    local records = {}
    local recordsByToken = {}
    local cooldownUseCount = {}

    for _, tracker in ipairs(trackers or {}) do
        if IsAuraTracker(tracker) then
            local token = TrackerToken(tracker)
            local record = recordsByToken[token]
            if not record then
                record = {
                    token = token,
                    cooldownID = TrackerCooldownID(tracker),
                    spellID = TrackerSpellID(tracker),
                    trackers = {},
                }
                recordsByToken[token] = record
                records[#records + 1] = record
                cooldownUseCount[record.cooldownID] = (cooldownUseCount[record.cooldownID] or 0) + 1
            end
            record.trackers[#record.trackers + 1] = tracker
            currentTokens[token] = true
        end
    end

    for token in pairs(stickyFrames) do
        if not currentTokens[token] then
            stickyFrames[token] = nil
            stickyCooldownIDs[token] = nil
            stickyGenerations[token] = nil
        end
    end

    for _, record in ipairs(records) do
        record.needsSpellDisambiguation = record.cooldownID > 0
            and (cooldownUseCount[record.cooldownID] or 0) > 1
            and record.spellID > 0
        local frame = stickyFrames[record.token]
        if frame and not consumedFrames[frame] and StickyStillMatches(record, frame) then
            Assign(record, frame, false)
        else
            stickyFrames[record.token] = nil
            stickyCooldownIDs[record.token] = nil
            stickyGenerations[record.token] = nil
        end
    end

    for _, record in ipairs(records) do
        if not record.frame and record.spellID > 0 then
            for _, frame in ipairs(activeFrames) do
                if not consumedFrames[frame] and frameSpellIDs[frame] == record.spellID then
                    Assign(record, frame, true)
                    break
                end
            end
        end
    end

    for _, record in ipairs(records) do
        if not record.frame and record.cooldownID > 0 and not record.needsSpellDisambiguation then
            for _, frame in ipairs(activeFrames) do
                if not consumedFrames[frame] and frameCooldownIDs[frame] == record.cooldownID then
                    Assign(record, frame, true)
                    break
                end
            end
        end
    end

    for _, record in ipairs(records) do
        if not record.frame and record.spellID > 0 then
            local candidate
            local matchCount = 0
            for _, frame in ipairs(activeFrames) do
                if not consumedFrames[frame] and InfoMatchesSpell(frame, record.spellID) then
                    candidate = frame
                    matchCount = matchCount + 1
                end
            end
            if matchCount == 1 then
                local recordMatches = 0
                for _, other in ipairs(records) do
                    if not other.frame and InfoMatchesSpell(candidate, other.spellID) then
                        recordMatches = recordMatches + 1
                    end
                end
                if recordMatches == 1 then
                    Assign(record, candidate, false)
                end
            end
        end
    end
end

function Resolver:GetFrame(tracker)
    return tracker and assignments[tracker] or nil
end

function Resolver:MirrorProgress(frame, targetStatusBar, targetDurationText, showDurationText)
    local sourceStatusBar = frame and frame.Bar
    if not sourceStatusBar
        or type(sourceStatusBar.GetMinMaxValues) ~= "function"
        or type(sourceStatusBar.GetValue) ~= "function"
        or not targetStatusBar
    then
        return false, false
    end

    local valuesOK, minValue, maxValue, value = pcall(function()
        local minimum, maximum = sourceStatusBar:GetMinMaxValues()
        return minimum, maximum, sourceStatusBar:GetValue()
    end)
    if not valuesOK then return false, false end

    targetStatusBar:SetMinMaxValues(minValue, maxValue)
    targetStatusBar:SetValue(value)

    local textCopied = not showDurationText
    if showDurationText and targetDurationText then
        local sourceDurationText = FindDurationFontString(sourceStatusBar)
        if sourceDurationText then
            local ok, text = pcall(sourceDurationText.GetText, sourceDurationText)
            if ok and type(text) ~= "nil" then
                textCopied = pcall(targetDurationText.SetText, targetDurationText, text)
            end
        end
    end

    return true, textCopied
end

function Resolver:AttachAuraContainer(tracker, bar, style)
    local auraContainer = DDingUI.TrackedAuraContainer
    if not auraContainer or not auraContainer.Attach then return false end
    return auraContainer:Attach(tracker, bar, style)
end

function Resolver:Suspend()
    wipe(assignments)
    local auraContainer = DDingUI.TrackedAuraContainer
    if auraContainer and auraContainer.Suspend then
        auraContainer:Suspend()
    end
end

function Resolver:Invalidate(clearSticky)
    wipe(assignments)
    if clearSticky then
        wipe(stickyFrames)
        wipe(stickyCooldownIDs)
        wipe(stickyGenerations)
    end
end
