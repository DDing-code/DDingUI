-- ============================================================
-- CDMScanner.lua
-- Scans Cooldown Manager (CDM) frames to build an aura catalog
--
-- Key features:
-- 1. Multiple cooldownID sources (frame.cooldownID, cooldownInfo, Icon)
-- 2. C_CooldownViewer.GetCooldownViewerCooldownInfo for verification
-- 3. C_Spell API for name and icon retrieval
-- ============================================================
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- Module initialization
DDingUI.CDMScanner = DDingUI.CDMScanner or {}
local CDMScanner = DDingUI.CDMScanner

-- Master catalog: { cooldownID = { name, icon, spellID, category, frame, ... } }
local masterCatalog = {}
local lastScanTime = 0
local isInCombat = false

-- ============================================================
-- LAYOUTINDEX-BASED CACHING (BetterCooldownManager pattern)
-- ============================================================
-- Cache frame -> cooldownID mappings to avoid runtime cooldownID access
-- Only populate during ScanAll() (outside combat), use cached values everywhere else

-- Weak table: frame -> cooldownID (auto-clears when frame is garbage collected)
local frameToCooldownID = setmetatable({}, { __mode = "k" })

-- Reverse lookup: viewerName_layoutIndex -> frame (weak values to prevent memory leak)
local frameByLayoutKey = setmetatable({}, { __mode = "v" })

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

-- Helper: Get frame by layout key (SAFE - no taint)
local function GetFrameByLayoutKey(viewerName, layoutIndex)
    if not viewerName or not layoutIndex then return nil end
    return frameByLayoutKey[viewerName .. "_" .. layoutIndex]
end

-- Helper: Cache frame by layout key
local function CacheFrameByLayoutKey(viewerName, layoutIndex, frame)
    if viewerName and layoutIndex and frame then
        frameByLayoutKey[viewerName .. "_" .. layoutIndex] = frame
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

-- ============================================================
-- CDM AVAILABILITY CHECK
-- ============================================================

function CDMScanner.IsCDManagerAvailable()
    return _G["BuffIconCooldownViewer"] ~= nil or _G["BuffBarCooldownViewer"] ~= nil
end

-- ============================================================
-- MASTER CDM SCANNER
-- ============================================================

function CDMScanner.ScanAll()
    -- Combat protection
    if InCombatLockdown() then
        return false, "Combat lockdown"
    end

    wipe(masterCatalog)
    wipe(frameToCooldownID)
    wipe(frameByLayoutKey)
    local totalCount = 0

    for _, viewerInfo in ipairs(CDM_VIEWERS) do
        local viewer = _G[viewerInfo.name]
        if viewer then
            local children = { viewer:GetChildren() }

            -- Sort by X position for consistent slot indexing
            table.sort(children, function(a, b)
                local ax = a:GetLeft() or 0
                local bx = b:GetLeft() or 0
                return ax < bx
            end)

            local slotIndex = 0
            for _, frame in ipairs(children) do
                -- Try multiple sources for cooldownID (use pcall to avoid secret value errors)
                local cdID
                pcall(function()
                    cdID = frame.cooldownID
                    -- Fallback 1: Check cooldownInfo table
                    if not cdID and frame.cooldownInfo then
                        cdID = frame.cooldownInfo.cooldownID
                    end
                    -- Fallback 2: For bar frames, check nested Icon frame
                    if not cdID and frame.Icon and frame.Icon.cooldownID then
                        cdID = frame.Icon.cooldownID
                    end
                end)

                -- Process if we found a cooldownID
                if cdID and type(cdID) == "number" then
                    -- Verify with CDM API that this cooldown actually exists (use pcall for safety)
                    local info
                    pcall(function()
                        if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                            info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                        end
                    end)

                    -- Skip frames with no CDM info
                    if info then
                        slotIndex = slotIndex + 1

                        -- Get spell info from API
                        local spellID, name, icon
                        local baseSpellID = info.spellID or 0
                        local overrideSpellID = info.overrideSpellID
                        local overrideTooltipSpellID = info.overrideTooltipSpellID
                        local linkedSpellIDs = info.linkedSpellIDs
                        local firstLinkedSpellID = linkedSpellIDs and linkedSpellIDs[1]

                        -- Priority: first linkedSpellID > overrideSpellID > baseSpellID
                        local displaySpellID = firstLinkedSpellID or overrideSpellID or baseSpellID

                        spellID = baseSpellID
                        name = displaySpellID and C_Spell.GetSpellName(displaySpellID)

                        -- ICON PRIORITY: Read from frame first (shows actual CDM texture)
                        -- Icon viewers: frame.Icon:GetTexture() or frame.Icon:GetTextureFileID()
                        -- Bar viewers: frame.Icon.Icon:GetTexture()
                        if frame.Icon then
                            -- Try GetTexture first (returns path or ID)
                            if frame.Icon.GetTexture then
                                local tex = frame.Icon:GetTexture()
                                -- Validate texture is actually set (not nil, not 0, not empty, not secret)
                                if tex and not issecretvalue(tex) and tex ~= 0 and tex ~= "" then
                                    icon = tex
                                end
                            end
                            -- Try GetTextureFileID as fallback (returns numeric ID)
                            if not icon and frame.Icon.GetTextureFileID then
                                local texID = frame.Icon:GetTextureFileID()
                                if texID and not issecretvalue(texID) and texID > 0 then
                                    icon = texID
                                end
                            end
                            -- Bar viewer structure: frame.Icon.Icon
                            if not icon and frame.Icon.Icon then
                                if frame.Icon.Icon.GetTexture then
                                    local tex = frame.Icon.Icon:GetTexture()
                                    if tex and not issecretvalue(tex) and tex ~= 0 and tex ~= "" then
                                        icon = tex
                                    end
                                end
                                if not icon and frame.Icon.Icon.GetTextureFileID then
                                    local texID = frame.Icon.Icon:GetTextureFileID()
                                    if texID and not issecretvalue(texID) and texID > 0 then
                                        icon = texID
                                    end
                                end
                            end
                        end

                        -- Fallback to API for icon
                        if not icon then
                            if viewerInfo.isAura then
                                -- Auras: try overrideTooltipSpellID first (this is what CDM uses for display)
                                if overrideTooltipSpellID and overrideTooltipSpellID > 0 then
                                    icon = C_Spell.GetSpellTexture(overrideTooltipSpellID)
                                end
                                -- Then try base spellID
                                if not icon and baseSpellID > 0 then
                                    icon = C_Spell.GetSpellTexture(baseSpellID)
                                end
                                if not icon and overrideSpellID then
                                    icon = C_Spell.GetSpellTexture(overrideSpellID)
                                end
                                if not icon and displaySpellID then
                                    icon = C_Spell.GetSpellTexture(displaySpellID)
                                end
                            else
                                -- Cooldowns: use override/linked chain
                                icon = displaySpellID and C_Spell.GetSpellTexture(displaySpellID)
                                if not icon and overrideSpellID then
                                    icon = C_Spell.GetSpellTexture(overrideSpellID)
                                end
                                if not icon and baseSpellID > 0 then
                                    icon = C_Spell.GetSpellTexture(baseSpellID)
                                end
                            end
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
                            -- Update category to show it's in both buff viewers
                            if existing.category == "TrackedBuff" and viewerInfo.category == "TrackedBar" then
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
                        else
                            -- Create new entry
                            masterCatalog[cdID] = {
                                cooldownID = cdID,
                                spellID = spellID or 0,
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
                                auraInstanceID = frame.auraInstanceID,
                                auraDataUnit = frame.auraDataUnit or "player",
                            }
                            totalCount = totalCount + 1
                        end

                        -- Store slot index on frame
                        frame._ddingSlotIndex = slotIndex - 1

                        -- Cache frame -> cooldownID mapping (BetterCooldownManager pattern)
                        -- This allows safe lookups without accessing frame.cooldownID at runtime
                        CacheCooldownID(frame, cdID)

                        -- Cache layout key -> frame mapping for reverse lookup
                        local layoutKey = frame.layoutIndex or slotIndex
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
        if entry.isTrackedBuff then trackedBuffs = trackedBuffs + 1 end
        if entry.isTrackedBar then trackedBars = trackedBars + 1 end
    end

    return true, totalCount, trackedBuffs, trackedBars
end

-- ============================================================
-- CATALOG ACCESS
-- ============================================================

-- Get all entries as array (sorted by name)
function CDMScanner.GetAllEntries()
    local results = {}
    for _, entry in pairs(masterCatalog) do
        table.insert(results, entry)
    end

    table.sort(results, function(a, b)
        -- Use pcall since name might be a secret value
        local success, result = pcall(function()
            return (a.name or "") < (b.name or "")
        end)
        if success then
            return result
        end
        -- Fallback: sort by cooldownID if name comparison fails
        return (a.cooldownID or 0) < (b.cooldownID or 0)
    end)

    return results
end

-- Get entry by cooldownID
function CDMScanner.GetEntry(cooldownID)
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
    if not cooldownID or cooldownID == 0 then return nil end

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
            local children = { viewer:GetChildren() }
            for _, frame in ipairs(children) do
                local cdID
                pcall(function()
                    cdID = frame.cooldownID
                    if not cdID and frame.cooldownInfo then
                        cdID = frame.cooldownInfo.cooldownID
                    end
                    if not cdID and frame.Icon and frame.Icon.cooldownID then
                        cdID = frame.Icon.cooldownID
                    end
                end)
                if cdID == cooldownID then
                    -- Cache for future lookups
                    CacheCooldownID(frame, cdID)
                    return frame
                end
            end
        end
    end

    return nil
end

-- Find frame by layoutIndex (BetterCooldownManager pattern - TAINT-SAFE)
function CDMScanner.FindFrameByLayoutIndex(viewerName, layoutIndex)
    -- First try cached lookup (SAFE - no cooldownID access)
    local frame = GetFrameByLayoutKey(viewerName, layoutIndex)
    if frame then
        return frame, GetCachedCooldownID(frame)
    end

    -- Fallback: scan viewer children by layoutIndex (SAFE - layoutIndex is not protected)
    local viewer = _G[viewerName]
    if not viewer then return nil, nil end

    local children = { viewer:GetChildren() }
    for _, childFrame in ipairs(children) do
        if childFrame.layoutIndex == layoutIndex then
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

-- Get aura data from CDM frame's auraInstanceID
function CDMScanner.GetAuraDataFromFrame(frame, unit)
    if not frame or not frame.auraInstanceID then return nil end
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
function CDMScanner.GetStacksFromFrame(frame)
    if not frame then return 0, false end

    -- Use CACHED cooldownID instead of accessing frame.cooldownID directly
    -- This is the BetterCooldownManager pattern - avoids taint propagation
    local cooldownID = GetCachedCooldownID(frame)
    local hasAura = false

    -- If no cached cooldownID and outside combat, try to get and cache it
    if not cooldownID and not InCombatLockdown() then
        pcall(function()
            cooldownID = frame.cooldownID
            if not cooldownID and frame.cooldownInfo then
                cooldownID = frame.cooldownInfo.cooldownID
            end
        end)
        -- Cache it for future lookups
        if cooldownID then
            CacheCooldownID(frame, cooldownID)
        end
    end

    -- Try C_CooldownViewer API for hasAura (uses cached cooldownID - SAFE)
    if cooldownID then
        pcall(function()
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if info and info.hasAura then
                    hasAura = true
                end
            end
        end)
    end

    -- Fallback: Check auraInstanceID (safe to access - not a protected property)
    if not hasAura then
        pcall(function()
            hasAura = frame.auraInstanceID ~= nil
        end)
    end

    -- Read stacks from the frame's Count FontString (avoids secret value issues)
    -- [12.0.1] GetText()가 secret string 반환 가능 → 비교/tonumber 시 에러
    -- 각 블록을 pcall로 보호
    local stacks = 0

    -- Try Count FontString (bar frames)
    if frame.Count then
        pcall(function()
            local countText = frame.Count:GetText()
            if countText and countText ~= "" then
                stacks = tonumber(countText) or 0
            end
        end)
    end

    -- Try Icon.Count (icon frames)
    if stacks == 0 and frame.Icon and frame.Icon.Count then
        pcall(function()
            local countText = frame.Icon.Count:GetText()
            if countText and countText ~= "" then
                stacks = tonumber(countText) or 0
            end
        end)
    end

    -- Search all FontStrings in frame regions for stack count
    if stacks == 0 then
        pcall(function()
            local regions = {frame:GetRegions()}
            for _, region in ipairs(regions) do
                if region:GetObjectType() == "FontString" then
                    local text = region:GetText()
                    if text and text ~= "" then
                        local num = tonumber(text)
                        if num and num > 0 and num < 100 then
                            stacks = num
                            break
                        end
                    end
                end
            end
        end)
    end

    -- Search children's FontStrings
    if stacks == 0 then
        pcall(function()
            local children = {frame:GetChildren()}
            for _, child in ipairs(children) do
                local childRegions = {child:GetRegions()}
                for _, region in ipairs(childRegions) do
                    if region:GetObjectType() == "FontString" then
                        local text = region:GetText()
                        if text and text ~= "" then
                            local num = tonumber(text)
                            if num and num > 0 and num < 100 then
                                stacks = num
                                break
                            end
                        end
                    end
                end
                if stacks > 0 then break end
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
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")  -- 플레이어만

-- Debounced ScanAll: 여러 이벤트가 연속 발생해도 마지막 1회만 실행
local pendingScanTimer = nil
local function DebouncedScanAll(delay)
    if pendingScanTimer then
        pendingScanTimer:Cancel()
    end
    pendingScanTimer = C_Timer.NewTimer(delay, function()
        pendingScanTimer = nil
        CDMScanner.ScanAll()
    end)
end

-- 초기화/스펙 변경용: 점진적 재시도 (이전 타이머 취소 후 새로 생성)
local retryTimers = {}
local function ScheduleRetryScans(delays)
    -- 기존 재시도 타이머 전부 취소
    for i = 1, #retryTimers do
        if retryTimers[i] then
            retryTimers[i]:Cancel()
        end
    end
    -- 테이블 초기화 후 새 타이머 추가
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
        DebouncedScanAll(0.5)
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- 리로드/존 이동 후 CDM 스캔 (점진적 재시도, 이전 타이머 취소)
        ScheduleRetryScans({ 0.5, 1.5, 3.0 })
        return
    elseif event == "UNIT_AURA" then
        -- 플레이어 오라 변경 시 카탈로그 업데이트 (전투 중이 아닐 때만)
        if not isInCombat then
            DebouncedScanAll(0.1)
        end
        return
    end

    -- Rescan after spec/talent change (점진적 재시도, 이전 타이머 취소)
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
        if success then
            -- Silent initialization
            -- print("|cff00ccff[DDingUI CDM]|r Scanned " .. (totalCount or 0) .. " entries")
        end
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
        print("|cff00ccff[DDingUI CDM]|r Scan " .. (success and "complete" or "failed"))
        print("  Total: " .. (total or 0) .. " (Buffs: " .. (buffs or 0) .. ", Bars: " .. (bars or 0) .. ")")
        print("  Cached frames: " .. CDMScanner.GetCachedFrameCount())
    elseif cmd == "list" then
        local entries = CDMScanner.GetAllEntries()
        print("|cff00ccff[DDingUI CDM]|r " .. #entries .. " entries:")
        for i, entry in ipairs(entries) do
            local stacks, hasAura = CDMScanner.GetStacksByCooldownID(entry.cooldownID)
            print(string.format("  [%d] %s (cdID:%d, stacks:%d, hasAura:%s)",
                i, entry.name or "?", entry.cooldownID or 0, stacks, tostring(hasAura)))
        end
    elseif cmd == "detail" then
        local entries = CDMScanner.GetAllEntries()
        print("|cff00ccff[DDingUI CDM]|r Detailed info:")
        for i, entry in ipairs(entries) do
            print(string.format("  [%d] %s", i, entry.name or "?"))
            print(string.format("      cooldownID: %d, spellID: %d", entry.cooldownID or 0, entry.spellID or 0))
            print(string.format("      icon: %s, category: %s", tostring(entry.icon), entry.category or "?"))
            if entry.frame then
                print("      frame: exists")
            end
        end
    elseif cmd == "inspect" then
        -- Inspect frame structure for a specific cooldownID
        local cdID = tonumber(args[2])
        if not cdID then
            print("|cff00ccff[DDingUI CDM]|r Usage: /ddingcdm inspect <cooldownID>")
            return
        end
        local frame = CDMScanner.FindFrameByCooldownID(cdID)
        if not frame then
            print("|cff00ccff[DDingUI CDM]|r Frame not found for cooldownID: " .. cdID)
            return
        end
        print("|cff00ccff[DDingUI CDM]|r Frame inspection for cdID: " .. cdID)
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
                print(string.format("    Region[%d] FontString: %s", i, tostring(text)))
            end
        end
        -- Check children
        local children = {frame:GetChildren()}
        for i, child in ipairs(children) do
            print(string.format("    Child[%d]: %s", i, child:GetObjectType()))
            local childRegions = {child:GetRegions()}
            for j, region in ipairs(childRegions) do
                if region:GetObjectType() == "FontString" then
                    local text = region:GetText()
                    print(string.format("      ChildRegion[%d] FontString: %s", j, tostring(text)))
                end
            end
        end
    elseif cmd == "test" then
        -- Test tracking for a specific cooldownID
        local cdID = tonumber(args[2])
        if not cdID then
            print("|cff00ccff[DDingUI CDM]|r Usage: /ddingcdm test <cooldownID>")
            return
        end
        print("|cff00ccff[DDingUI CDM]|r Testing cooldownID: " .. cdID)
        local frame = CDMScanner.FindFrameByCooldownID(cdID)
        print("  Frame found: " .. tostring(frame ~= nil))
        if frame then
            local stacks, hasAura = CDMScanner.GetStacksFromFrame(frame)
            print("  GetStacksFromFrame: stacks=" .. stacks .. ", hasAura=" .. tostring(hasAura))
        end
        -- Also try C_CooldownViewer API (use pcall to avoid secret value errors)
        local info
        pcall(function()
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            end
        end)
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
        print("|cff00ccff[DDingUI CDM]|r Cache Statistics:")
        print("  Cached frames: " .. CDMScanner.GetCachedFrameCount())
        print("  Catalog entries: " .. CDMScanner.GetCount())
        print("  Last scan: " .. (lastScanTime > 0 and string.format("%.1fs ago", GetTime() - lastScanTime) or "never"))
        print("  In combat: " .. tostring(isInCombat))

        -- Show layout key cache
        local layoutKeyCount = 0
        for _ in pairs(frameByLayoutKey) do
            layoutKeyCount = layoutKeyCount + 1
        end
        print("  Layout key cache: " .. layoutKeyCount)
    else
        print("|cff00ccff[DDingUI CDM]|r Commands:")
        print("  /ddingcdm scan - Rescan CDM frames")
        print("  /ddingcdm list - List all CDM entries with stacks")
        print("  /ddingcdm detail - Detailed CDM info")
        print("  /ddingcdm cache - Show cache statistics")
        print("  /ddingcdm inspect <cdID> - Inspect frame structure")
        print("  /ddingcdm test <cdID> - Test tracking for specific cooldownID")
    end
end
