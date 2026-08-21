local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

-- Reactive frame registry shared by GroupSystem runtime.
--
-- FrameController used to rebuild its maps by enumerating every active Blizzard
-- Cooldown Viewer pool on each Reconcile. This registry keeps active frame
-- identity incrementally from CDM acquire/id/release hooks and uses the cached
-- CDMScanner catalog for bootstrap/repair. A bounded live-pool reconciliation
-- closes hook timing gaps without repeating the full catalog/API scan.

local Registry = {}
DDingUI.GroupCDMFrameRegistry = Registry

local CDMCompat = DDingUI.CDMCompat
local CDMScanner = DDingUI.CDMScanner
local EMPTY = {}

local KNOWN_VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local framesByViewer = {}
local viewerRefs = {}
local viewerNameByRef = setmetatable({}, { __mode = "k" })
local frameMeta = setmetatable({}, { __mode = "k" })
local viewerNeedsBootstrap = {}

local scannerSyncInitialized = false
local lastScannerSyncToken = nil

local diagnostics = {
    acquires = 0,
    tracks = 0,
    releases = 0,
    scannerRefreshes = 0,
    scannerFrames = 0,
    scannerUnchangedSkips = 0,
    scannerConflictSkips = 0,
    bootstrapPoolScans = 0,
    bootstrapFrames = 0,
    viewerResets = 0,
    viewerBootstrapScans = 0,
    idReplacements = 0,
    livePoolScans = 0,
    livePoolFrames = 0,
    livePoolPrunes = 0,
}

local function IsUsableID(value)
    if CDMCompat and CDMCompat.IsUsableID then
        return CDMCompat:IsUsableID(value)
    end
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function EnsureViewerTable(viewerName)
    if not viewerName then return EMPTY end
    local frames = framesByViewer[viewerName]
    if not frames then
        frames = {}
        framesByViewer[viewerName] = frames
    end
    return frames
end

local function RemoveFrameMapping(frame, meta)
    meta = meta or frameMeta[frame]
    if not meta then return end
    local frames = meta.viewerName and framesByViewer[meta.viewerName]
    if frames and meta.cooldownID and frames[meta.cooldownID] == frame then
        frames[meta.cooldownID] = nil
    end
end

local function GetScannerToken(scanner)
    if scanner and type(scanner.GetLastScanTime) == "function" then
        local ok, token = pcall(scanner.GetLastScanTime)
        if ok then return token end
    end
    return nil
end

function Registry:RegisterViewer(viewerName, viewer)
    if type(viewerName) ~= "string" or not viewer then return false end

    local previous = viewerRefs[viewerName]
    if previous and previous ~= viewer then
        local frames = framesByViewer[viewerName]
        if frames then
            for _, frame in pairs(frames) do
                local meta = frameMeta[frame]
                if meta and meta.viewerName == viewerName then
                    frameMeta[frame] = nil
                end
            end
        end
        framesByViewer[viewerName] = {}
        viewerNameByRef[previous] = nil
        viewerNeedsBootstrap[viewerName] = true
        diagnostics.viewerResets = diagnostics.viewerResets + 1
    end

    viewerRefs[viewerName] = viewer
    viewerNameByRef[viewer] = viewerName
    EnsureViewerTable(viewerName)
    return true
end

function Registry:ResolveViewerName(viewer, frame)
    if viewer then
        local known = viewerNameByRef[viewer]
        if known then return known end

        if viewer.GetName then
            local ok, name = pcall(viewer.GetName, viewer)
            if ok and type(name) == "string" then
                for _, viewerName in ipairs(KNOWN_VIEWERS) do
                    if name == viewerName then
                        self:RegisterViewer(viewerName, viewer)
                        return viewerName
                    end
                end
            end
        end

        for _, viewerName in ipairs(KNOWN_VIEWERS) do
            if _G[viewerName] == viewer then
                self:RegisterViewer(viewerName, viewer)
                return viewerName
            end
        end
    end

    local meta = frame and frameMeta[frame]
    if meta and meta.viewerName then return meta.viewerName end
    if frame and frame._ddSourceViewer then return frame._ddSourceViewer end

    local parent = frame and frame.GetParent and frame:GetParent()
    if parent then
        local known = viewerNameByRef[parent]
        if known then return known end
        for _, viewerName in ipairs(KNOWN_VIEWERS) do
            if _G[viewerName] == parent then
                self:RegisterViewer(viewerName, parent)
                return viewerName
            end
        end
    end

    return nil
end

function Registry:Acquire(viewer, frame)
    if not frame then return false end
    diagnostics.acquires = diagnostics.acquires + 1

    local oldMeta = frameMeta[frame]
    if oldMeta then
        RemoveFrameMapping(frame, oldMeta)
    end

    local viewerName = self:ResolveViewerName(viewer, frame)
    frameMeta[frame] = viewerName and { viewerName = viewerName, hookObserved = true } or nil
    if viewerName then
        frame._ddSourceViewer = viewerName
        EnsureViewerTable(viewerName)
        viewerNeedsBootstrap[viewerName] = nil
        return true
    end
    return false
end

function Registry:TrackFrame(frame, cooldownID, viewerName)
    if not frame then return false end

    local previous = frameMeta[frame]
    local hookObserved = (previous and previous.hookObserved) or viewerName == nil
    viewerName = viewerName or self:ResolveViewerName(nil, frame)
        or (previous and previous.viewerName)
    if not viewerName then return false end

    if not IsUsableID(cooldownID) and CDMCompat and CDMCompat.GetFrameCooldownID then
        cooldownID = CDMCompat:GetFrameCooldownID(frame)
    end

    if previous and (previous.viewerName ~= viewerName or previous.cooldownID ~= cooldownID) then
        RemoveFrameMapping(frame, previous)
    end

    frame._ddSourceViewer = viewerName
    local meta = previous or {}
    meta.viewerName = viewerName
    meta.cooldownID = IsUsableID(cooldownID) and cooldownID or nil
    meta.hookObserved = hookObserved and true or nil
    frameMeta[frame] = meta

    if not meta.cooldownID then
        EnsureViewerTable(viewerName)
        return false
    end

    local frames = EnsureViewerTable(viewerName)
    local replaced = frames[meta.cooldownID]
    if replaced and replaced ~= frame then
        diagnostics.idReplacements = diagnostics.idReplacements + 1
    end
    frames[meta.cooldownID] = frame
    viewerNeedsBootstrap[viewerName] = nil
    diagnostics.tracks = diagnostics.tracks + 1
    return true
end

function Registry:ReleaseFrame(frame, viewerName)
    if not frame then return false end
    local meta = frameMeta[frame]
    if not meta and viewerName then
        meta = { viewerName = viewerName }
    end
    if not meta then return false end

    RemoveFrameMapping(frame, meta)
    frameMeta[frame] = nil
    frame._ddSourceViewer = nil
    diagnostics.releases = diagnostics.releases + 1
    return true
end

local function TrackScannerFrame(self, viewerName, frame, cooldownID)
    if not frame or not IsUsableID(cooldownID) then return 0 end
    local viewer = _G[viewerName]
    if viewer then self:RegisterViewer(viewerName, viewer) end

    -- Hook-observed identity wins over the scanner snapshot. The scanner is
    -- deliberately delayed outside combat and can still point at a frame that
    -- has already been released/reused by Blizzard.
    local meta = frameMeta[frame]
    if meta and meta.hookObserved
        and (meta.viewerName ~= viewerName
            or (meta.cooldownID and meta.cooldownID ~= cooldownID))
    then
        diagnostics.scannerConflictSkips = diagnostics.scannerConflictSkips + 1
        return 0
    end
    local existing = EnsureViewerTable(viewerName)[cooldownID]
    if existing and existing ~= frame then
        return 0
    end
    return self:TrackFrame(frame, cooldownID, viewerName) and 1 or 0
end

function Registry:SyncFromScanner(force)
    local scanner = DDingUI.CDMScanner or CDMScanner
    if not scanner or not scanner.GetAllEntries or not scanner.IsPopulated
        or not scanner.IsPopulated()
    then
        return 0
    end

    local token = GetScannerToken(scanner)
    if not force and scannerSyncInitialized then
        -- If CDMScanner exposes a scan timestamp, only consume a newly completed
        -- scan. When no token API exists, consume the scanner once for bootstrap
        -- and let reactive acquire/id/release hooks own runtime identity after it.
        if token == nil or token == lastScannerSyncToken then
            diagnostics.scannerUnchangedSkips = diagnostics.scannerUnchangedSkips + 1
            return 0
        end
    end

    scannerSyncInitialized = true
    lastScannerSyncToken = token
    diagnostics.scannerRefreshes = diagnostics.scannerRefreshes + 1

    local tracked = 0
    for _, entry in ipairs(scanner.GetAllEntries() or EMPTY) do
        local cooldownID = entry and entry.cooldownID
        if IsUsableID(cooldownID) then
            if entry.category == "Essential" then
                tracked = tracked + TrackScannerFrame(self, "EssentialCooldownViewer", entry.frame, cooldownID)
            elseif entry.category == "Utility" then
                tracked = tracked + TrackScannerFrame(self, "UtilityCooldownViewer", entry.frame, cooldownID)
            else
                if entry.isTrackedBuff or entry.category == "TrackedBuff" or entry.category == "TrackedBuff+Bar" then
                    tracked = tracked + TrackScannerFrame(
                        self, "BuffIconCooldownViewer", entry.iconFrame or (entry.category == "TrackedBuff" and entry.frame), cooldownID
                    )
                end
                if entry.isTrackedBar or entry.category == "TrackedBar" or entry.category == "TrackedBuff+Bar" then
                    tracked = tracked + TrackScannerFrame(
                        self, "BuffBarCooldownViewer", entry.barFrame or (entry.category == "TrackedBar" and entry.frame), cooldownID
                    )
                end
            end
        end
    end
    diagnostics.scannerFrames = diagnostics.scannerFrames + tracked
    return tracked
end

local function BootstrapViewerPool(self, viewerName)
    local viewer = viewerRefs[viewerName] or _G[viewerName]
    local pool = viewer and viewer.itemFramePool
    if not (pool and pool.EnumerateActive) then return 0 end
    if InCombatLockdown and InCombatLockdown() then return 0 end
    if CDMCompat and CDMCompat.IsSettingsOpen and CDMCompat:IsSettingsOpen() then return 0 end

    diagnostics.bootstrapPoolScans = diagnostics.bootstrapPoolScans + 1
    local tracked = 0
    for frame in pool:EnumerateActive() do
        local cooldownID = CDMCompat and CDMCompat:GetFrameCooldownID(frame) or frame.cooldownID
        if self:TrackFrame(frame, cooldownID, viewerName) then
            tracked = tracked + 1
        end
    end
    diagnostics.bootstrapFrames = diagnostics.bootstrapFrames + tracked
    return tracked
end

local function SyncViewerPool(self, viewerName)
    local viewer = viewerRefs[viewerName] or _G[viewerName]
    local pool = viewer and viewer.itemFramePool
    if not (pool and pool.EnumerateActive) then return 0, false end

    viewerNeedsBootstrap[viewerName] = nil
    diagnostics.livePoolScans = diagnostics.livePoolScans + 1
    local seen = {}
    local tracked = 0
    for frame in pool:EnumerateActive() do
        seen[frame] = true
        local cooldownID = CDMCompat and CDMCompat:GetFrameCooldownID(frame) or frame.cooldownID
        if self:TrackFrame(frame, cooldownID, viewerName) then
            tracked = tracked + 1
        end
    end

    local frames = EnsureViewerTable(viewerName)
    for cooldownID, frame in pairs(frames) do
        if not seen[frame] then
            frames[cooldownID] = nil
            local meta = frameMeta[frame]
            if meta and meta.viewerName == viewerName and meta.cooldownID == cooldownID then
                frameMeta[frame] = nil
                if frame._ddSourceViewer == viewerName then
                    frame._ddSourceViewer = nil
                end
            end
            diagnostics.livePoolPrunes = diagnostics.livePoolPrunes + 1
        end
    end

    diagnostics.livePoolFrames = diagnostics.livePoolFrames + tracked
    return tracked, true
end

function Registry:SyncLivePools()
    local tracked = 0
    local scanned = 0
    for _, viewerName in ipairs(KNOWN_VIEWERS) do
        local viewerTracked, didScan = SyncViewerPool(self, viewerName)
        tracked = tracked + viewerTracked
        if didScan then scanned = scanned + 1 end
    end
    return tracked, scanned
end

function Registry:Bootstrap(externalViewerRefs)
    for _, viewerName in ipairs(KNOWN_VIEWERS) do
        local viewer = (externalViewerRefs and externalViewerRefs[viewerName]) or _G[viewerName]
        if viewer then self:RegisterViewer(viewerName, viewer) end
    end

    local scannerFrames = self:SyncFromScanner(false)
    if scannerFrames > 0 or self:GetCount() > 0 then
        self._bootstrapped = true
        return scannerFrames
    end

    local tracked = 0
    for _, viewerName in ipairs(KNOWN_VIEWERS) do
        tracked = tracked + BootstrapViewerPool(self, viewerName)
    end

    -- Bootstrap pool walking is a one-shot fallback. Even an empty snapshot is
    -- considered attempted; subsequent frames arrive through acquire/id hooks.
    self._bootstrapped = true
    return tracked
end

function Registry:Refresh(externalViewerRefs)
    for _, viewerName in ipairs(KNOWN_VIEWERS) do
        local viewer = (externalViewerRefs and externalViewerRefs[viewerName]) or _G[viewerName]
        if viewer then self:RegisterViewer(viewerName, viewer) end
    end

    local tracked = self:SyncFromScanner(false)
    if not self._bootstrapped then
        tracked = tracked + self:Bootstrap(externalViewerRefs)
    end

    -- The live pools are authoritative. CDM can finish or recycle frames after
    -- the initial scanner/bootstrap pass without emitting every hook we observe.
    -- Reconcile is already debounced, so one bounded pass keeps membership exact
    -- without restoring the old repeated API/catalog scans.
    local liveTracked = self:SyncLivePools()
    tracked = tracked + liveTracked

    -- A Blizzard viewer object can be replaced without a fresh CDMScanner scan.
    -- In that case the cached scanner frames belong to the old viewer, so make
    -- one bounded out-of-combat pool pass for only the replaced viewer.
    for viewerName in pairs(viewerNeedsBootstrap) do
        viewerNeedsBootstrap[viewerName] = nil
        diagnostics.viewerBootstrapScans = diagnostics.viewerBootstrapScans + 1
        tracked = tracked + BootstrapViewerPool(self, viewerName)
    end

    return tracked
end

function Registry:GetFrames(viewerName)
    return framesByViewer[viewerName] or EMPTY
end

function Registry:GetMeta(frame)
    return frameMeta[frame]
end

function Registry:GetCount(viewerName)
    local count = 0
    if viewerName then
        for _ in pairs(framesByViewer[viewerName] or EMPTY) do count = count + 1 end
        return count
    end
    for _, frames in pairs(framesByViewer) do
        for _ in pairs(frames) do count = count + 1 end
    end
    return count
end

function Registry:GetDiagnostics()
    local result = {
        totalFrames = self:GetCount(),
        bootstrapped = self._bootstrapped == true,
        scannerSyncInitialized = scannerSyncInitialized,
        lastScannerSyncToken = lastScannerSyncToken,
    }
    for key, value in pairs(diagnostics) do result[key] = value end
    return result
end
