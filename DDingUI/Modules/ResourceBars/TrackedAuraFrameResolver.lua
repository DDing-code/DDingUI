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
local hookedPools = setmetatable({}, { __mode = "k" })
local hookedViewers = setmetatable({}, { __mode = "k" })
local durationFontStrings = setmetatable({}, { __mode = "k" })

local diagnostics = {
    passes = 0,
    emptyPasses = 0,
    snapshots = 0,
    framesVisited = 0,
    records = 0,
    stickyHits = 0,
    spellMatches = 0,
    cooldownMatches = 0,
    infoMatches = 0,
    refreshRequests = 0,
    catalogLookups = 0,
    catalogSearches = 0,
    catalogEntriesVisited = 0,
    catalogMisses = 0,
    poolFallbackSnapshots = 0,
}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function CleanID(value)
    if IsSecret(value) then return 0 end
    value = tonumber(value)
    return value and value > 0 and value or 0
end

local function SafeEquals(value, expected)
    return expected > 0 and not IsSecret(value) and value == expected
end

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
    return CleanID(tracker and (tracker.cooldownID or (tracker.trigger and tracker.trigger.cooldownID)))
end

local function TrackerSpellID(tracker)
    return CleanID(tracker and (tracker.spellID or (tracker.trigger and tracker.trigger.spellID)))
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
    diagnostics.refreshRequests = diagnostics.refreshRequests + 1
    local resourceBars = DDingUI.ResourceBars
    if resourceBars and resourceBars.RequestBuffTrackerUpdate then
        resourceBars:RequestBuffTrackerUpdate("tracked-frame", 0)
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
        hooksecurefunc(pool, "Release", function()
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

local function HookKnownViewers()
    for _, viewerName in ipairs(VIEWER_NAMES) do
        HookViewer(_G[viewerName])
    end
end

local function ReadCurrentCooldownID(frame)
    local compat = DDingUI.CDMCompat
    if not compat or not frame then return nil end

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
    if not compat or not compat.ResolveFrameSpellID or not frame then return nil end
    local value = compat:ResolveFrameSpellID(frame)
    return compat:IsUsableID(value) and value or nil
end

local function InfoMatchesSpell(frame, spellID)
    if spellID <= 0 or not frame then return false end
    local compat = DDingUI.CDMCompat
    if not compat or not compat.GetFrameCooldownInfo then return false end

    local info = compat:GetFrameCooldownInfo(frame)
    if type(info) ~= "table" or IsSecret(info) then return false end
    if SafeEquals(info.overrideSpellID, spellID)
        or SafeEquals(info.overrideTooltipSpellID, spellID)
        or SafeEquals(info.spellID, spellID)
        or SafeEquals(info.displaySpellID, spellID)
        or SafeEquals(info.linkedSpellID, spellID)
    then
        return true
    end

    local linked = info.linkedSpellIDs
    if type(linked) == "table" and not IsSecret(linked) then
        for _, linkedID in ipairs(linked) do
            if SafeEquals(linkedID, spellID) then return true end
        end
    end
    return false
end

local function EntryMatchesSpell(entry, spellID)
    if type(entry) ~= "table" or spellID <= 0 or IsSecret(entry) then return false end

    if SafeEquals(entry.spellID, spellID)
        or SafeEquals(entry.displaySpellID, spellID)
        or SafeEquals(entry.overrideSpellID, spellID)
        or SafeEquals(entry.overrideTooltipSpellID, spellID)
        or SafeEquals(entry.linkedSpellID, spellID)
    then
        return true
    end

    local linked = entry.linkedSpellIDs
    if type(linked) == "table" and not IsSecret(linked) then
        for _, linkedID in ipairs(linked) do
            if SafeEquals(linkedID, spellID) then return true end
        end
    end
    return false
end

local function EntryFrame(entry)
    if type(entry) ~= "table" then return nil end
    return entry.barFrame or entry.frame or entry.iconFrame
end

local function IsTrackedAuraEntry(entry)
    return type(entry) == "table"
        and (entry.isTrackedBuff == true
            or entry.isTrackedBar == true
            or entry.category == "TrackedBuff+Bar")
end

local function FrameMatchesRecord(frame, cooldownID, spellID)
    if not frame then return false end

    if spellID > 0 then
        local resolvedSpellID = ReadResolvedSpellID(frame)
        if resolvedSpellID and resolvedSpellID == spellID then
            return true
        end
        return InfoMatchesSpell(frame, spellID)
    end

    if cooldownID > 0 then
        local resolvedCooldownID = ReadResolvedCooldownID(frame)
        return resolvedCooldownID == cooldownID
    end

    return false
end

local function FindByCatalog(cooldownID, spellID)
    local scanner = DDingUI.CDMScanner
    if not scanner then return nil, false end

    diagnostics.catalogLookups = diagnostics.catalogLookups + 1

    if cooldownID > 0 and scanner.GetEntry then
        local entry = scanner.GetEntry(cooldownID)
        local frame = IsTrackedAuraEntry(entry) and EntryFrame(entry) or nil
        if frame then
            if spellID <= 0
                or EntryMatchesSpell(entry, spellID)
                or FrameMatchesRecord(frame, cooldownID, spellID)
            then
                diagnostics.cooldownMatches = diagnostics.cooldownMatches + 1
                return frame, true
            end
        end
    end

    if spellID <= 0 or not scanner.GetAllEntries then
        diagnostics.catalogMisses = diagnostics.catalogMisses + 1
        return nil, scanner.IsPopulated and scanner.IsPopulated() or false
    end

    local entries = scanner.GetAllEntries()
    if type(entries) ~= "table" then
        diagnostics.catalogMisses = diagnostics.catalogMisses + 1
        return nil, false
    end

    diagnostics.snapshots = diagnostics.snapshots + 1
    diagnostics.catalogSearches = diagnostics.catalogSearches + 1

    local candidate
    local matchCount = 0
    local seenFrames = setmetatable({}, { __mode = "k" })

    for _, entry in ipairs(entries) do
        if IsTrackedAuraEntry(entry) then
            diagnostics.catalogEntriesVisited = diagnostics.catalogEntriesVisited + 1
            local frame = EntryFrame(entry)
            if frame and not seenFrames[frame] then
                seenFrames[frame] = true
                diagnostics.framesVisited = diagnostics.framesVisited + 1
                if EntryMatchesSpell(entry, spellID) or FrameMatchesRecord(frame, cooldownID, spellID) then
                    candidate = frame
                    matchCount = matchCount + 1
                    if matchCount > 1 then break end
                end
            end
        end
    end

    if matchCount == 1 then
        diagnostics.spellMatches = diagnostics.spellMatches + 1
        return candidate, true
    end

    diagnostics.catalogMisses = diagnostics.catalogMisses + 1
    return nil, scanner.IsPopulated and scanner.IsPopulated() or #entries > 0
end

local function FindByPoolFallback(cooldownID, spellID)
    diagnostics.poolFallbackSnapshots = diagnostics.poolFallbackSnapshots + 1

    local candidate
    local matchCount = 0

    for _, viewerName in ipairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        HookViewer(viewer)
        local pool = viewer and viewer.itemFramePool
        if pool then
            for frame in pool:EnumerateActive() do
                diagnostics.framesVisited = diagnostics.framesVisited + 1
                if FrameMatchesRecord(frame, cooldownID, spellID) then
                    candidate = frame
                    matchCount = matchCount + 1
                    if spellID > 0 and ReadResolvedSpellID(frame) == spellID then
                        diagnostics.spellMatches = diagnostics.spellMatches + 1
                        return frame
                    end
                    if matchCount > 1 then
                        candidate = nil
                    end
                end
            end
        end
    end

    if matchCount == 1 and candidate then
        diagnostics.infoMatches = diagnostics.infoMatches + 1
        return candidate
    end
    return nil
end

local function ResolveRecord(record)
    local frame, catalogReady = FindByCatalog(record.cooldownID, record.spellID)
    if frame then return frame end

    -- Compatibility fallback only while the shared CDM catalog is not ready.
    -- Once populated, an inactive/missing aura must not trigger direct pool scans.
    if not catalogReady then
        return FindByPoolFallback(record.cooldownID, record.spellID)
    end
    return nil
end

function Resolver:BeginPass(trackers)
    diagnostics.passes = diagnostics.passes + 1
    local auraContainer = DDingUI.TrackedAuraContainer
    if auraContainer and auraContainer.Sync then
        auraContainer:Sync(trackers)
    end
    local auraSounds = DDingUI.TrackedAuraSounds
    if auraSounds and auraSounds.Sync then
        auraSounds:Sync(trackers)
    end

    wipe(assignments)
    HookKnownViewers()

    local records = {}
    local recordsByToken = {}

    for _, tracker in ipairs(trackers or {}) do
        local shouldReadLegacy = not auraContainer or not auraContainer.ShouldReadLegacy
            or auraContainer:ShouldReadLegacy(tracker)
        if IsAuraTracker(tracker) and shouldReadLegacy then
            local token = TrackerToken(tracker)
            local record = recordsByToken[token]
            if not record then
                record = {
                    cooldownID = TrackerCooldownID(tracker),
                    spellID = TrackerSpellID(tracker),
                    trackers = {},
                }
                recordsByToken[token] = record
                records[#records + 1] = record
            end
            record.trackers[#record.trackers + 1] = tracker
        end
    end

    if #records == 0 then
        diagnostics.emptyPasses = diagnostics.emptyPasses + 1
        return
    end

    diagnostics.records = diagnostics.records + #records

    for _, record in ipairs(records) do
        local frame = ResolveRecord(record)
        if frame then
            for _, tracker in ipairs(record.trackers) do
                assignments[tracker] = frame
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

function Resolver:ShouldReadLegacy(tracker)
    local auraContainer = DDingUI.TrackedAuraContainer
    if not auraContainer or not auraContainer.ShouldReadLegacy then return true end
    return auraContainer:ShouldReadLegacy(tracker)
end

function Resolver:Suspend()
    wipe(assignments)
    local auraContainer = DDingUI.TrackedAuraContainer
    if auraContainer and auraContainer.Suspend then
        auraContainer:Suspend()
    end
    local auraSounds = DDingUI.TrackedAuraSounds
    if auraSounds and auraSounds.Suspend then
        auraSounds:Suspend()
    end
end

function Resolver:Invalidate()
    wipe(assignments)
    local auraSounds = DDingUI.TrackedAuraSounds
    if auraSounds and auraSounds.Invalidate then
        auraSounds:Invalidate()
    end
end

function Resolver:GetDiagnostics()
    local result = {}
    for key, value in pairs(diagnostics) do
        result[key] = value
    end
    result.averageFramesPerSnapshot = diagnostics.snapshots > 0
        and diagnostics.framesVisited / diagnostics.snapshots or 0
    result.averageRecordsPerPass = diagnostics.passes > 0
        and diagnostics.records / diagnostics.passes or 0
    result.averageCatalogEntriesPerSearch = diagnostics.catalogSearches > 0
        and diagnostics.catalogEntriesVisited / diagnostics.catalogSearches or 0
    return result
end

function Resolver:ResetDiagnostics()
    for key in pairs(diagnostics) do
        diagnostics[key] = 0
    end
end
