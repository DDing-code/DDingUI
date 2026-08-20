-- ============================================================
-- CDMScanner.lua
-- Scans Cooldown Manager (CDM) frames to build an aura catalog
--
-- Key features:
-- 1. Public category metadata plus active pool frames
-- 2. Stable cooldown and spell identity through the compatibility cache
-- 3. C_Spell API for name and icon retrieval
-- ============================================================
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local CDMCompat = DDingUI.CDMCompat

-- Module initialization
DDingUI.CDMScanner = DDingUI.CDMScanner or {}
local CDMScanner = DDingUI.CDMScanner

-- Global API Cache (Performance Optimization)
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local next = next
local tonumber = tonumber
local tostring = tostring
local wipe = wipe
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local string_format = string.format
local math_floor = math.floor

-- ============================================================
-- SAFE VALUE UTILITIES (CDM CDM pattern)
-- ============================================================

-- [FIX] secret value / NaN / 음수 / 소수점 방어
local function IsSafeNumber(val)
    if CDMCompat then return CDMCompat:IsPublicNumber(val) end
    if issecretvalue and issecretvalue(val) then return false end
    return type(val) == "number" and val == val -- NaN 체크: NaN ~= NaN
end

local function IsUsableID(id)
    if CDMCompat then return CDMCompat:IsUsableID(id) end
    if not IsSafeNumber(id) then return false end
    return id > 0 and id == math_floor(id)
end

local function IsSafeTexture(value)
    if CDMCompat and not CDMCompat:IsPublicValue(value) then return false end
    if not CDMCompat and issecretvalue and issecretvalue(value) then return false end
    local valueType = type(value)
    return (valueType == "number" and value > 0)
        or (valueType == "string" and value ~= "")
end

-- [FIX] DDingUI HasAuraInstanceID 패턴: secret value 안전 체크
local function HasAuraInstanceID(value)
    if issecretvalue and issecretvalue(value) then return true end
    return type(value) == "number" and value ~= 0
end

-- Master catalog: { cooldownID = { name, icon, spellID, category, frame, ... } }
local masterCatalog = {}
local lastScanTime = 0
local isInCombat = false

-- ============================================================
-- LAYOUTINDEX-BASED CACHING
-- ============================================================
-- Cache frame -> cooldownID mappings to avoid runtime cooldownID access
-- Only populate during ScanAll() (outside combat), use cached values everywhere else

-- Weak table: frame -> cooldownID (auto-clears when frame is garbage collected)
local frameToCooldownID = setmetatable({}, { __mode = "k" })

-- [FIX] Nested table: viewerName → { layoutIndex → frame } (문자열 연결 제거)
local frameByLayoutKey = {}

-- Helper: Get cached cooldownID for a frame (SAFE - no taint)
local function GetCachedCooldownID(frame)
    if not frame then return nil end
    return frameToCooldownID[frame]
end

-- Helper: Cache cooldownID for a frame (only call outside combat)
local function CacheCooldownID(frame, cooldownID)
    if frame and cooldownID then
        frameToCooldownID[frame] = cooldownID
    end
end

-- [FIX] 문자열 연결 없이 nested table로 O(1) 접근
local function GetFrameByLayoutKey(viewerName, layoutIndex)
    if not viewerName or not layoutIndex then return nil end
    local viewerTable = frameByLayoutKey[viewerName]
    return viewerTable and viewerTable[layoutIndex]
end

local function CacheFrameByLayoutKey(viewerName, layoutIndex, frame)
    if viewerName and layoutIndex and frame then
        if not frameByLayoutKey[viewerName] then
            frameByLayoutKey[viewerName] = {}
        end
        frameByLayoutKey[viewerName][layoutIndex] = frame
    end
end

-- Viewer configuration
local CDM_VIEWERS = {
    { name = "EssentialCooldownViewer", category = "Essential", viewerType = "cooldown", isAura = false },
    { name = "UtilityCooldownViewer", category = "Utility", viewerType = "cooldown", isAura = false },
    { name = "BuffIconCooldownViewer", category = "TrackedBuff", viewerType = "aura", isAura = true },
    { name = "BuffBarCooldownViewer", category = "TrackedBar", viewerType = "aura", isAura = true },
}

-- Category display names
local CATEGORY_NAMES = {
    Essential = "핵심 능력 (Essential)",
    Utility = "보조 능력 (Utility)",
    TrackedBuff = "강화 (Tracked Buffs)",
    TrackedBar = "강화 (Tracked Bars)",
    ["TrackedBuff+Bar"] = "강화 (Buffs + Bars)",
}

local function NormalizeCategoryName(category)
    if category == "Utility" then return "Utility" end
    if category == "TrackedBar" then return "TrackedBar" end
    if category == "TrackedBuff" or category == "GroupBuff"
        or category == "SpecAgnosticTracked" or category == "EquipSlotTracked"
    then
        return "TrackedBuff"
    end
    return "Essential"
end

local function GetSpellDisplay(spellID)
    if not IsUsableID(spellID) or not C_Spell then return nil, nil end
    local name
    local icon
    if C_Spell.GetSpellName then
        local ok, value = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(value) == "string" then name = value end
    end
    if C_Spell.GetSpellTexture then
        local ok, value = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and not (issecretvalue and issecretvalue(value)) then
            local valueType = type(value)
            if (valueType == "number" and value > 0) or (valueType == "string" and value ~= "") then
                icon = value
            end
        end
    end
    return name, icon
end

local function AddStaticCatalogEntry(cooldownID, info, categoryDef)
    if not IsUsableID(cooldownID) or type(info) ~= "table" then return end
    local category = NormalizeCategoryName(categoryDef and categoryDef.name or "Essential")
    local displaySpellID = CDMCompat and CDMCompat:ResolveInfoSpellID(info) or info.overrideSpellID or info.spellID
    local name, icon = GetSpellDisplay(displaySpellID)
    local existing = masterCatalog[cooldownID]
    if existing then
        if existing.category == "TrackedBuff" and category == "TrackedBar" then
            existing.category = "TrackedBuff+Bar"
            existing.categoryName = CATEGORY_NAMES["TrackedBuff+Bar"]
            existing.isTrackedBar = true
        elseif existing.category == "TrackedBar" and category == "TrackedBuff" then
            existing.category = "TrackedBuff+Bar"
            existing.categoryName = CATEGORY_NAMES["TrackedBuff+Bar"]
            existing.isTrackedBuff = true
        end
        return
    end

    masterCatalog[cooldownID] = {
        cooldownID = cooldownID,
        spellID = IsUsableID(info.spellID) and info.spellID or displaySpellID or 0,
        displaySpellID = displaySpellID or 0,
        overrideSpellID = info.overrideSpellID,
        overrideTooltipSpellID = info.overrideTooltipSpellID,
        linkedSpellIDs = info.linkedSpellIDs,
        name = name or "Unknown",
        icon = icon or 134400,
        category = category,
        categoryName = CATEGORY_NAMES[category] or category,
        viewerType = (category == "Essential" or category == "Utility") and "cooldown" or "aura",
        viewerName = categoryDef and categoryDef.viewerName,
        isAura = category == "TrackedBuff" or category == "TrackedBar",
        isTrackedBuff = category == "TrackedBuff",
        isTrackedBar = category == "TrackedBar",
        hasAura = info.hasAura,
        selfAura = info.selfAura,
        charges = info.charges,
        flags = info.flags,
        isKnown = info.isKnown,
    }
end

-- ============================================================
-- CDM AVAILABILITY CHECK
-- ============================================================

function CDMScanner.IsCDManagerAvailable()
    return _G["BuffIconCooldownViewer"] ~= nil or _G["BuffBarCooldownViewer"] ~= nil
end

-- ============================================================
-- MASTER CDM SCANNER
-- ============================================================

-- [FIX] Forward declaration — GetAllEntries/GetEntriesByCategory 정렬 캐시에서 사용
local catalogVersion = 0

function CDMScanner.ScanAll()
    -- Combat protection
    if InCombatLockdown() then
        return false, "Combat lockdown"
    end
    if CDMCompat and CDMCompat:IsSettingsOpen() then
        return false, "Cooldown viewer settings open"
    end

    local previousCatalog = masterCatalog
    local previousFrameToCooldownID = frameToCooldownID
    local previousFrameByLayoutKey = frameByLayoutKey
    masterCatalog = {}
    frameToCooldownID = setmetatable({}, { __mode = "k" })
    frameByLayoutKey = {}
    local totalCount = 0

    if CDMCompat then
        for _, categoryDef in ipairs(CDMCompat:GetCategoryDefinitions()) do
            local cooldownIDs = CDMCompat:GetCategorySet(categoryDef.category, true)
            if type(cooldownIDs) == "table" then
                for _, cooldownID in ipairs(cooldownIDs) do
                    local info = CDMCompat:GetCooldownInfo(cooldownID)
                    AddStaticCatalogEntry(cooldownID, info, categoryDef)
                end
            end
        end
    end

    for _, viewerInfo in ipairs(CDM_VIEWERS) do
        local viewer = _G[viewerInfo.name]
        if viewer then
            if CDMCompat then CDMCompat:TrackViewerPool(viewer) end
            local children = {}
            if viewer.itemFramePool then
                for frame in viewer.itemFramePool:EnumerateActive() do
                    table.insert(children, frame)
                end
            end

            -- Stable viewer order without reading protected screen coordinates.
            table.sort(children, function(a, b)
                local ai = IsSafeNumber(a.layoutIndex) and a.layoutIndex or 999999
                local bi = IsSafeNumber(b.layoutIndex) and b.layoutIndex or 999999
                return ai < bi
            end)

            local slotIndex = 0
            for _, frame in ipairs(children) do
                local cdID = CDMCompat and CDMCompat:GetFrameCooldownID(frame)
                    or GetCachedCooldownID(frame)

                -- Process if we found a cooldownID
                if IsUsableID(cdID) then
                    local info = CDMCompat and CDMCompat:GetFrameCooldownInfo(frame)
                    if not info and CDMCompat then
                        info = CDMCompat:GetCooldownInfo(cdID)
                    end

                    -- Skip frames with no CDM info
                    if info then
                        slotIndex = slotIndex + 1

                        -- Get spell info from API
                        local spellID, name, icon
                        local baseSpellID = IsUsableID(info.spellID) and info.spellID or 0
                        local overrideSpellID = info.overrideSpellID
                        local overrideTooltipSpellID = info.overrideTooltipSpellID
                        local linkedSpellIDs = info.linkedSpellIDs
                        local firstLinkedSpellID = linkedSpellIDs and linkedSpellIDs[1]

                        local displaySpellID = CDMCompat and CDMCompat:ResolveFrameSpellID(frame)
                            or overrideSpellID or firstLinkedSpellID or baseSpellID

                        spellID = baseSpellID
                        pcall(function() name = displaySpellID and C_Spell.GetSpellName(displaySpellID) end)

                        -- [FIX] pcall-safe texture resolver
                        local function SafeGetSpellTexture(sid)
                            if not sid or sid == 0 then return nil end
                            local ok, tex = pcall(C_Spell.GetSpellTexture, sid)
                            if ok and IsSafeTexture(tex) then return tex end
                            return nil
                        end

                        -- ICON PRIORITY: Read from frame first (shows actual CDM texture)
                        if frame.Icon then
                            pcall(function()
                                -- Try GetTexture first
                                if frame.Icon.GetTexture then
                                    local tex = frame.Icon:GetTexture()
                                    if IsSafeTexture(tex) then
                                        icon = tex
                                    end
                                end
                                -- Try GetTextureFileID
                                if not icon and frame.Icon.GetTextureFileID then
                                    local texID = frame.Icon:GetTextureFileID()
                                    if IsSafeTexture(texID) then
                                        icon = texID
                                    end
                                end
                                -- Bar viewer structure: frame.Icon.Icon
                                if not icon and frame.Icon.Icon then
                                    if frame.Icon.Icon.GetTexture then
                                        local tex = frame.Icon.Icon:GetTexture()
                                        if IsSafeTexture(tex) then
                                            icon = tex
                                        end
                                    end
                                    if not icon and frame.Icon.Icon.GetTextureFileID then
                                        local texID = frame.Icon.Icon:GetTextureFileID()
                                        if IsSafeTexture(texID) then
                                            icon = texID
                                        end
                                    end
                                end
                            end)
                        end

                        -- [FIX] cooldownInfo fallback (CDM stores texture data here)
                        if not icon then
                            pcall(function()
                                if frame.cooldownInfo then
                                    local ci = frame.cooldownInfo
                                    if ci.texture and ci.texture ~= 0 then icon = ci.texture end
                                    if not icon and ci.iconFileID and ci.iconFileID > 0 then icon = ci.iconFileID end
                                end
                                -- CDM API info fallback
                                if not icon and info.iconFileID and info.iconFileID > 0 then icon = info.iconFileID end
                            end)
                        end

                        -- Fallback to spell API (pcall-safe)
                        if not icon then
                            icon = SafeGetSpellTexture(overrideTooltipSpellID)
                                or SafeGetSpellTexture(displaySpellID)
                                or SafeGetSpellTexture(overrideSpellID)
                                or SafeGetSpellTexture(baseSpellID)
                        end

                        -- Fallbacks for name
                        if not name and overrideSpellID then
                            name = C_Spell.GetSpellName(overrideSpellID)
                        end
                        if not name and baseSpellID > 0 then
                            name = C_Spell.GetSpellName(baseSpellID)
                        end

                        -- Check if already exists (for TrackedBuff+Bar case)
                        local existing = masterCatalog[cdID]
                        if existing then
                            -- Static category membership can differ from the viewer that
                            -- currently owns the frame. The live viewer is authoritative
                            -- for cooldown/utility routing and per-spec layout changes.
                            if viewerInfo.category == "Essential" or viewerInfo.category == "Utility" then
                                existing.category = viewerInfo.category
                                existing.categoryName = CATEGORY_NAMES[viewerInfo.category] or viewerInfo.category
                                existing.viewerType = viewerInfo.viewerType
                                existing.viewerName = viewerInfo.name
                                existing.isAura = false
                                existing.isTrackedBuff = false
                                existing.isTrackedBar = false
                                existing.frame = frame
                            -- Update category to show it's in both buff viewers
                            elseif existing.category == "TrackedBuff" and viewerInfo.category == "TrackedBar" then
                                existing.category = "TrackedBuff+Bar"
                                existing.categoryName = CATEGORY_NAMES["TrackedBuff+Bar"]
                                existing.isTrackedBar = true
                                existing.barFrame = frame
                            elseif existing.category == "TrackedBar" and viewerInfo.category == "TrackedBuff" then
                                existing.category = "TrackedBuff+Bar"
                                existing.categoryName = CATEGORY_NAMES["TrackedBuff+Bar"]
                                existing.isTrackedBuff = true
                                existing.iconFrame = frame
                            end
                            existing.frame = existing.frame or frame
                            if viewerInfo.category == "TrackedBuff" then existing.iconFrame = frame end
                            if viewerInfo.category == "TrackedBar" then existing.barFrame = frame end
                            existing.slotIndex = slotIndex
                            existing.viewerName = existing.viewerName or viewerInfo.name
                            existing.hasAuraInstance = HasAuraInstanceID(frame.auraInstanceID)
                            existing.auraDataUnit = frame.auraDataUnit or "player"
                            if existing.name == "Unknown" and name then existing.name = name end
                            if (not existing.icon or existing.icon == 134400) and icon then existing.icon = icon end
                            if displaySpellID and displaySpellID > 0 then
                                existing.displaySpellID = displaySpellID
                            end
                        else
                            -- Create new entry
                            masterCatalog[cdID] = {
                                cooldownID = cdID,
                                spellID = spellID or 0,
                                displaySpellID = displaySpellID or 0,  -- override/linked 포함
                                overrideSpellID = overrideSpellID,
                                overrideTooltipSpellID = overrideTooltipSpellID,
                                linkedSpellIDs = linkedSpellIDs,
                                name = name or "Unknown",
                                icon = icon or 134400,
                                category = viewerInfo.category,
                                categoryName = CATEGORY_NAMES[viewerInfo.category] or viewerInfo.category,
                                viewerType = viewerInfo.viewerType,
                                viewerName = viewerInfo.name,
                                isAura = viewerInfo.isAura,
                                isTrackedBuff = viewerInfo.category == "TrackedBuff",
                                isTrackedBar = viewerInfo.category == "TrackedBar",
                                frame = frame,
                                iconFrame = viewerInfo.category == "TrackedBuff" and frame or nil,
                                barFrame = viewerInfo.category == "TrackedBar" and frame or nil,
                                slotIndex = slotIndex,
                                -- API info
                                hasAura = info.hasAura,
                                selfAura = info.selfAura,
                                charges = info.charges,
                                flags = info.flags,
                                -- Aura tracking data
                                -- [FIX] secret value 방어: auraInstanceID 존재 여부만 기록
                                hasAuraInstance = HasAuraInstanceID(frame.auraInstanceID),
                                auraDataUnit = frame.auraDataUnit or "player",
                            }
                        end

                        -- Store slot index on frame
                        frame._ddingSlotIndex = slotIndex - 1

                        -- Cache frame -> cooldownID mapping.
                        -- This allows safe lookups without accessing frame.cooldownID at runtime
                        CacheCooldownID(frame, cdID)

                        -- Cache layout key -> frame mapping for reverse lookup
                        local layoutKey = IsSafeNumber(frame.layoutIndex) and frame.layoutIndex or slotIndex
                        CacheFrameByLayoutKey(viewerInfo.name, layoutKey, frame)
                    end -- end if info
                end -- end if cdID
            end -- end for frame
        end -- end if viewer
    end -- end for viewerInfo

    lastScanTime = GetTime()

    -- Count by type
    local trackedBuffs = 0
    local trackedBars = 0
    for _, entry in pairs(masterCatalog) do
        totalCount = totalCount + 1
        if entry.isTrackedBuff then trackedBuffs = trackedBuffs + 1 end
        if entry.isTrackedBar then trackedBars = trackedBars + 1 end
    end

    if totalCount == 0 then
        masterCatalog = previousCatalog
        frameToCooldownID = previousFrameToCooldownID
        frameByLayoutKey = previousFrameByLayoutKey
        return false, "Cooldown viewer data not ready"
    end

    catalogVersion = catalogVersion + 1

    return true, totalCount, trackedBuffs, trackedBars
end

-- ============================================================
-- CATALOG ACCESS
-- ============================================================

-- [FIX] 정렬 캐시: ScanAll 후 한 번만 정렬, 이후 캐시 반환
local sortedAllCache = nil
local sortedAllVersion = -1
local sortedCategoryCache = nil
local sortedCategoryVersion = -1

-- [FIX] pcall 제거: entry.name은 ScanAll에서 "name or 'Unknown'"으로 안전하게 설정됨
local function sortByName(a, b)
    if a == b then return false end
    if not a then return false end
    if not b then return true end
    local nameA = a.name or ""
    local nameB = b.name or ""
    if nameA ~= nameB then return nameA < nameB end
    return (a.cooldownID or 0) < (b.cooldownID or 0)
end

-- Get all entries as array (sorted by name, cached)
function CDMScanner.GetAllEntries()
    if sortedAllVersion == catalogVersion and sortedAllCache then
        return sortedAllCache
    end

    local results = {}
    for _, entry in pairs(masterCatalog) do
        results[#results + 1] = entry
    end
    table.sort(results, sortByName)

    sortedAllCache = results
    sortedAllVersion = catalogVersion
    return results
end

-- Get entries grouped by category: { Essential = {...}, Utility = {...}, Buff = {...} }
function CDMScanner.GetEntriesByCategory()
    if sortedCategoryVersion == catalogVersion and sortedCategoryCache then
        return sortedCategoryCache
    end

    local grouped = {
        Essential = {},
        Utility = {},
        Buff = {},
    }

    for _, entry in pairs(masterCatalog) do
        local cat = entry.category
        if cat == "Essential" then
            grouped.Essential[#grouped.Essential + 1] = entry
        elseif cat == "Utility" then
            grouped.Utility[#grouped.Utility + 1] = entry
        else
            grouped.Buff[#grouped.Buff + 1] = entry
        end
    end

    table.sort(grouped.Essential, sortByName)
    table.sort(grouped.Utility, sortByName)
    table.sort(grouped.Buff, sortByName)

    sortedCategoryCache = grouped
    sortedCategoryVersion = catalogVersion
    return grouped
end

-- Get entry by cooldownID
function CDMScanner.GetEntry(cooldownID)
    if not IsUsableID(cooldownID) then return nil end
    return masterCatalog[cooldownID]
end

-- Get entry count
function CDMScanner.GetCount()
    local count = 0
    for _ in pairs(masterCatalog) do
        count = count + 1
    end
    return count
end

-- Check if catalog is populated
function CDMScanner.IsPopulated()
    return next(masterCatalog) ~= nil
end

-- Get last scan time
function CDMScanner.GetLastScanTime()
    return lastScanTime
end

-- ============================================================
-- CDM FRAME FINDER
-- ============================================================

-- Find CDM frame by cooldownID
function CDMScanner.FindFrameByCooldownID(cooldownID)
    if not IsUsableID(cooldownID) then return nil end

    -- Primary: Check masterCatalog (populated during scan)
    local entry = masterCatalog[cooldownID]
    if entry and entry.frame then
        return entry.frame
    end

    -- Secondary: Check cached frame -> cooldownID mappings (reverse lookup)
    -- This is SAFE - no direct cooldownID access
    for frame, cachedID in pairs(frameToCooldownID) do
        if cachedID == cooldownID then
            return frame
        end
    end

    -- Fallback: scan frames directly (ONLY outside combat)
    -- IMPORTANT: Skip fallback during combat to prevent taint propagation
    -- cooldownID access can cause Blizzard_CooldownViewer spellID secret value errors
    if InCombatLockdown() then
        return nil  -- Use cached data only during combat
    end

    -- Last resort: direct frame scan with cooldownID access
    -- This path should rarely be taken since we cache everything in ScanAll()
    for _, viewerInfo in ipairs(CDM_VIEWERS) do
        local viewer = _G[viewerInfo.name]
        if viewer then
            local children = {}
            if viewer.itemFramePool then
                for f in viewer.itemFramePool:EnumerateActive() do
                    table.insert(children, f)
                end
            end

            for _, frame in ipairs(children) do
                local cdID = CDMCompat and CDMCompat:GetFrameCooldownID(frame)
                    or GetCachedCooldownID(frame)
                if IsUsableID(cdID) and cdID == cooldownID then
                    -- Cache for future lookups
                    CacheCooldownID(frame, cdID)
                    return frame
                end
            end
        end
    end

    return nil
end

-- Find a frame by layoutIndex without touching protected runtime values.
function CDMScanner.FindFrameByLayoutIndex(viewerName, layoutIndex)
    if type(viewerName) ~= "string" or not IsSafeNumber(layoutIndex) then return nil, nil end
    -- First try cached lookup (SAFE - no cooldownID access)
    local frame = GetFrameByLayoutKey(viewerName, layoutIndex)
    if frame then
        return frame, GetCachedCooldownID(frame)
    end

    -- Fallback: scan viewer children by layoutIndex (SAFE - layoutIndex is not protected)
    local viewer = _G[viewerName]
    if not viewer then return nil, nil end

    local children = {}
    if viewer.itemFramePool then
        for f in viewer.itemFramePool:EnumerateActive() do
            table.insert(children, f)
        end
    end

    for _, childFrame in ipairs(children) do
        local childLayoutIndex = childFrame.layoutIndex
        if IsSafeNumber(childLayoutIndex) and childLayoutIndex == layoutIndex then
            -- Cache for future lookups
            CacheFrameByLayoutKey(viewerName, layoutIndex, childFrame)
            local cooldownID = GetCachedCooldownID(childFrame)
            return childFrame, cooldownID
        end
    end

    return nil, nil
end

-- Get all cached cooldownIDs (for debugging)
function CDMScanner.GetCachedFrameCount()
    local count = 0
    for _ in pairs(frameToCooldownID) do
        count = count + 1
    end
    return count
end

-- ============================================================
-- AURA DATA ACCESS
-- ============================================================

-- Get aura data from CDM frame's auraInstanceID (secret value safe)
function CDMScanner.GetAuraDataFromFrame(frame, unit)
    if not frame or not HasAuraInstanceID(frame.auraInstanceID) then return nil end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID then return nil end -- [12.0.1]

    unit = unit or frame.auraDataUnit or "player"

    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, frame.auraInstanceID) -- [12.0.1]
    return ok and auraData or nil
end

-- Get aura data by cooldownID
function CDMScanner.GetAuraDataByCooldownID(cooldownID)
    local frame = CDMScanner.FindFrameByCooldownID(cooldownID)
    if not frame then return nil, nil end

    local unit = frame.auraDataUnit or "player"
    local auraData = CDMScanner.GetAuraDataFromFrame(frame, unit)

    return auraData, frame
end

-- Get stacks from CDM frame (reads from displayed Count text to avoid secret values)
-- [FIX] 무차별 FontString 스캔 제거 — frame.Count / frame.Icon.Count만 사용
function CDMScanner.GetStacksFromFrame(frame)
    if not frame then return 0, false end

    -- Use CACHED cooldownID instead of accessing frame.cooldownID directly
    local cooldownID = GetCachedCooldownID(frame)
        or (CDMCompat and CDMCompat:GetFrameCooldownID(frame))
    local hasAura = false

    -- If no cached cooldownID and outside combat, try to get and cache it
    if not cooldownID and not InCombatLockdown() and CDMCompat then
        cooldownID = CDMCompat:GetFrameCooldownID(frame)
        if IsUsableID(cooldownID) then
            CacheCooldownID(frame, cooldownID)
        else
            cooldownID = nil
        end
    end

    -- Try C_CooldownViewer API for hasAura (uses cached cooldownID - SAFE)
    if cooldownID then
        local info = CDMCompat and CDMCompat:GetCooldownInfo(cooldownID)
        if info and info.hasAura then
            hasAura = true
        end
    end

    -- [FIX] HasAuraInstanceID 래퍼: secret value 안전하게 존재만 확인
    if not hasAura then
        hasAura = HasAuraInstanceID(frame.auraInstanceID)
    end

    -- [FIX] 스택 읽기: frame.Count 또는 frame.Icon.Count만 사용 (FontString 무차별 스캔 제거)
    -- 타이머 텍스트, 라벨 등을 스택으로 오인하는 문제 방지
    local stacks = 0

    -- CDM bar frames: frame.Count
    if frame.Count then
        pcall(function()
            local countText = frame.Count:GetText()
            if not (issecretvalue and issecretvalue(countText))
                and type(countText) == "string" and countText ~= ""
            then
                stacks = tonumber(countText) or 0
            end
        end)
    end

    -- CDM icon frames: frame.Icon.Count
    if stacks == 0 and frame.Icon and frame.Icon.Count then
        pcall(function()
            local countText = frame.Icon.Count:GetText()
            if not (issecretvalue and issecretvalue(countText))
                and type(countText) == "string" and countText ~= ""
            then
                stacks = tonumber(countText) or 0
            end
        end)
    end

    -- If aura is active but no stacks displayed, treat as 1
    if hasAura and stacks == 0 then
        stacks = 1
    end

    return stacks, hasAura
end

-- Get stacks by cooldownID (safe, no secret values)
function CDMScanner.GetStacksByCooldownID(cooldownID)
    local frame = CDMScanner.FindFrameByCooldownID(cooldownID)
    if not frame then return 0, false end

    local stacks, hasAura = CDMScanner.GetStacksFromFrame(frame)
    return stacks, hasAura
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "COOLDOWN_VIEWER_DATA_LOADED")
pcall(eventFrame.RegisterEvent, eventFrame, "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
pcall(eventFrame.RegisterEvent, eventFrame, "COOLDOWN_VIEWER_TABLE_HOTFIXED")

-- [FIX] CDM 패턴: OnUpdate 기반 dirty flag — C_Timer 객체 생성 없이 배치 처리
local scanDirty = false
local scanDelayElapsed = 0
local SCAN_DELAY_THRESHOLD = 0.1

local function OnUpdateScanProcessor(self, elapsed)
    scanDelayElapsed = scanDelayElapsed + elapsed
    if scanDelayElapsed < SCAN_DELAY_THRESHOLD then return end

    -- 다음 프레임까지 대기 완료 → 스캔 실행
    scanDirty = false
    scanDelayElapsed = 0
    self:SetScript("OnUpdate", nil)

    if not InCombatLockdown() then
        CDMScanner.ScanAll()
    end
end

local function MarkScanDirty(delay)
    scanDelayElapsed = 0
    SCAN_DELAY_THRESHOLD = delay or 0.1
    if not scanDirty then
        scanDirty = true
        eventFrame:SetScript("OnUpdate", OnUpdateScanProcessor)
    end
end

-- 초기화/스펙 변경용: 점진적 재시도 (특정 딜레이 필요 → C_Timer 유지)
local retryTimers = {}
local function ScheduleRetryScans(delays)
    for i = 1, #retryTimers do
        if retryTimers[i] then
            retryTimers[i]:Cancel()
        end
    end
    wipe(retryTimers)
    for _, delay in ipairs(delays) do
        retryTimers[#retryTimers + 1] = C_Timer.NewTimer(delay, function()
            CDMScanner.ScanAll()
        end)
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        isInCombat = true
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        isInCombat = false
        MarkScanDirty(0.5) -- 전투 종료 후 0.5초 대기
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScheduleRetryScans({ 0.5, 1.5, 3.0 })
        return
    elseif event == "COOLDOWN_VIEWER_DATA_LOADED"
        or event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"
        or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED"
    then
        if CDMCompat then CDMCompat:Invalidate() end
        MarkScanDirty(0)
        return
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if CDMCompat then CDMCompat:Invalidate() end
        MarkScanDirty(0.2)
        return
    end

    -- Rescan after spec/talent change
    if CDMCompat then CDMCompat:Invalidate() end
    ScheduleRetryScans({ 0.5, 1.5, 3.0, 5.0 })
end)

-- ============================================================
-- INITIALIZATION
-- ============================================================

-- BCDM pattern: 단일 초기화 타이머, 플래그로 중복 방지
local cdmInitialized = false
local cdmInitTimer = nil

local function InitializeCDMScanner()
    -- 이미 초기화 완료되었으면 스킵
    if cdmInitialized then return end

    if not CDMScanner.IsCDManagerAvailable() then
        -- Retry after delay (단일 타이머만 사용)
        if cdmInitTimer then
            cdmInitTimer:Cancel()
        end
        cdmInitTimer = C_Timer.NewTimer(2.0, function()
            cdmInitTimer = nil
            InitializeCDMScanner()
        end)
        return
    end

    -- 초기화 완료 플래그 설정
    cdmInitialized = true

    -- Initial scan
    C_Timer.After(0.5, function()
        local success, totalCount, buffCount, barCount = CDMScanner.ScanAll()
        -- Silent initialization (no chat output)
    end)
end

-- Start initialization after addon loads (BCDM pattern: 단일 타이머)
C_Timer.After(0.5, InitializeCDMScanner)

-- ============================================================
-- API EXPORTS
-- ============================================================

DDingUI.ScanCDM = function() return CDMScanner.ScanAll() end
DDingUI.GetCDMEntries = function() return CDMScanner.GetAllEntries() end
DDingUI.GetCDMEntry = function(cooldownID) return CDMScanner.GetEntry(cooldownID) end
DDingUI.GetCDMStacksByCooldownID = function(cooldownID) return CDMScanner.GetStacksByCooldownID(cooldownID) end
DDingUI.FindCDMFrame = function(cooldownID) return CDMScanner.FindFrameByCooldownID(cooldownID) end
DDingUI.FindCDMFrameByLayout = function(viewerName, layoutIndex) return CDMScanner.FindFrameByLayoutIndex(viewerName, layoutIndex) end
DDingUI.GetCDMCacheCount = function() return CDMScanner.GetCachedFrameCount() end

-- Debug command
SLASH_DDINGCDM1 = "/ddingcdm"
SlashCmdList["DDINGCDM"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    local cmd = args[1] or ""

    if cmd == "scan" then
        local success, total, buffs, bars = CDMScanner.ScanAll()
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Scan " .. (success and "complete" or "failed"))
        print("  Total: " .. (total or 0) .. " (Buffs: " .. (buffs or 0) .. ", Bars: " .. (bars or 0) .. ")")
        print("  Cached frames: " .. CDMScanner.GetCachedFrameCount())
    elseif cmd == "list" then
        local entries = CDMScanner.GetAllEntries()
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. #entries .. " entries:")
        for i, entry in ipairs(entries) do
            local stacks, hasAura = CDMScanner.GetStacksByCooldownID(entry.cooldownID)
            print(string_format("  [%d] %s (cdID:%d, stacks:%d, hasAura:%s)",
                i, entry.name or "?", entry.cooldownID or 0, stacks, tostring(hasAura)))
        end
    elseif cmd == "detail" then
        local entries = CDMScanner.GetAllEntries()
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Detailed info:")
        for i, entry in ipairs(entries) do
            print(string_format("  [%d] %s", i, entry.name or "?"))
            print(string_format("      cooldownID: %d, spellID: %d", entry.cooldownID or 0, entry.spellID or 0))
            print(string_format("      icon: %s, category: %s", tostring(entry.icon), entry.category or "?"))
            if entry.frame then
                print("      frame: exists")
            end
        end
    elseif cmd == "inspect" then
        -- Inspect frame structure for a specific cooldownID
        local cdID = tonumber(args[2])
        if not cdID then
            print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Usage: /ddingcdm inspect <cooldownID>")
            return
        end
        local frame = CDMScanner.FindFrameByCooldownID(cdID)
        if not frame then
            print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Frame not found for cooldownID: " .. cdID)
            return
        end
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Frame inspection for cdID: " .. cdID)
        print("  auraInstanceID: " .. tostring(frame.auraInstanceID))
        print("  cooldownID: " .. tostring(frame.cooldownID))
        print("  frame.Count exists: " .. tostring(frame.Count ~= nil))
        if frame.Count then
            print("    Count:GetText() = " .. tostring(frame.Count:GetText()))
        end
        print("  frame.Icon exists: " .. tostring(frame.Icon ~= nil))
        if frame.Icon then
            print("    Icon.Count exists: " .. tostring(frame.Icon.Count ~= nil))
            if frame.Icon.Count then
                print("    Icon.Count:GetText() = " .. tostring(frame.Icon.Count:GetText()))
            end
        end
        -- Check for other possible stack locations
        print("  Looking for other FontStrings...")
        local regions = {frame:GetRegions()}
        for i, region in ipairs(regions) do
            if region:GetObjectType() == "FontString" then
                local text = region:GetText()
                print(string_format("    Region[%d] FontString: %s", i, tostring(text)))
            end
        end
        -- Check children
        local children = {frame:GetChildren()}
        for i, child in ipairs(children) do
            print(string_format("    Child[%d]: %s", i, child:GetObjectType()))
            local childRegions = {child:GetRegions()}
            for j, region in ipairs(childRegions) do
                if region:GetObjectType() == "FontString" then
                    local text = region:GetText()
                    print(string_format("      ChildRegion[%d] FontString: %s", j, tostring(text)))
                end
            end
        end
    elseif cmd == "test" then
        -- Test tracking for a specific cooldownID
        local cdID = tonumber(args[2])
        if not cdID then
            print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Usage: /ddingcdm test <cooldownID>")
            return
        end
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Testing cooldownID: " .. cdID)
        local frame = CDMScanner.FindFrameByCooldownID(cdID)
        print("  Frame found: " .. tostring(frame ~= nil))
        if frame then
            local stacks, hasAura = CDMScanner.GetStacksFromFrame(frame)
            print("  GetStacksFromFrame: stacks=" .. stacks .. ", hasAura=" .. tostring(hasAura))
        end
        local info = CDMCompat and CDMCompat:GetCooldownInfo(cdID, true)
        if info then
            print("  C_CooldownViewer info:")
            pcall(function()
                print("    hasAura: " .. tostring(info.hasAura))
                print("    spellID: " .. tostring(info.spellID))
            end)
        else
            print("  C_CooldownViewer: no info returned")
        end
    elseif cmd == "cache" then
        -- Show cache statistics
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Cache Statistics:")
        print("  Cached frames: " .. CDMScanner.GetCachedFrameCount())
        print("  Catalog entries: " .. CDMScanner.GetCount())
        print("  Last scan: " .. (lastScanTime > 0 and string_format("%.1fs ago", GetTime() - lastScanTime) or "never"))
        print("  In combat: " .. tostring(isInCombat))

        -- Show layout key cache
        local layoutKeyCount = 0
        for _ in pairs(frameByLayoutKey) do
            layoutKeyCount = layoutKeyCount + 1
        end
        print("  Layout key cache: " .. layoutKeyCount)
    else
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: Commands:")
        print("  /ddingcdm scan - Rescan CDM frames")
        print("  /ddingcdm list - List all CDM entries with stacks")
        print("  /ddingcdm detail - Detailed CDM info")
        print("  /ddingcdm cache - Show cache statistics")
        print("  /ddingcdm inspect <cdID> - Inspect frame structure")
        print("  /ddingcdm test <cdID> - Test tracking for specific cooldownID")
    end
end
