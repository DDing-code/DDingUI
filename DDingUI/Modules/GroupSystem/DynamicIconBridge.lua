-- [GROUP SYSTEM] DynamicIconBridge: CustomIcons ↔ GroupSystem 통합 어댑터
-- [DYNAMIC] CustomIcons(생석치물물약) 프레임을 GroupSystem 컨테이너에서 관리
-- FrameController 패턴 기반 — reparent to UIParent, container 앵커 참조
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local DynamicIconBridge = {}
DDingUI.DynamicIconBridge = DynamicIconBridge

-- ============================================================
-- Locals
-- ============================================================

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local tostring = tostring
local table_concat = table.concat
local table_sort = table.sort
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local C_UnitAuras = C_UnitAuras
local pcall = pcall

local GROUP_VIEWER_MAP = {
    ["Cooldowns"] = "EssentialCooldownViewer",
    ["Buffs"] = "BuffIconCooldownViewer",
    ["Utility"] = "UtilityCooldownViewer",
}

local BLOODLUST_ALIAS_SPELL_IDS = { 2825, 32182, 80353, 90355, 160452, 264667, 390386 }
local CUSTOM_AURA_PRESET_SPELL_IDS = {
    [1236616] = true,
    [1236994] = true,
    [1239479] = true,
    [374968] = true,
}
for _, spellID in ipairs(BLOODLUST_ALIAS_SPELL_IDS) do
    CUSTOM_AURA_PRESET_SPELL_IDS[spellID] = true
end

local CUSTOM_AURA_PRESET_FALLBACK_NAMES = {
    ["Light's Potential"] = true,
    ["Potion of Recklessness"] = true,
    ["Devoured Dreams"] = true,
    ["Potion of Devoured Dreams"] = true,
    ["Time Spiral"] = true,
    ["Bloodlust"] = true,
    ["Bloodlust / Heroism"] = true,
    ["Heroism"] = true,
    ["Time Warp"] = true,
    ["Ancient Hysteria"] = true,
    ["Fury of the Aspects"] = true,
    ["빛의 잠재력"] = true,
    ["무모함의 물약"] = true,
    ["잠식된 꿈"] = true,
    ["시간의 와류"] = true,
    ["피의 욕망"] = true,
    ["영웅심"] = true,
    ["시간 왜곡"] = true,
}

-- ============================================================
-- State
-- ============================================================

local managedFrames = {}    -- [iconKey] = true
local initialized = false
local layoutSuppressed = false
local COMBAT_ICON_GRACE_SECONDS = 1.5
local hiddenCDMFrames = {}  -- [frame] = cooldownID (CDM 숨김 추적)
local SUPPRESSED_SPELL_CACHE_TTL = 0.15
local suppressedSpellCache = nil
local suppressedSpellCacheAt = 0

local function ResolveInactiveBuffDisplay(iconData)
    local settings = iconData and iconData.settings or {}
    local visible = false
    if settings.alwaysShow == "on" then
        visible = true
    elseif settings.alwaysShow == "off" then
        visible = false
    end

    local desaturated = settings.desatInactive ~= "off"
    if settings.desatInactive == "on" then
        desaturated = true
    end
    return visible, desaturated
end

local function ResetGroupIconLayoutState(frame, resetTarget)
    if not frame then return end
    local gr = DDingUI.GroupRenderer
    if gr and gr.ResetIconLayoutState then
        gr:ResetIconLayoutState(frame, resetTarget)
        return
    end
    frame._ddLastGroupLayoutHash = nil
    frame._ddCurrentContainer = nil
    frame._ddCurrentX = nil
    frame._ddCurrentY = nil
    frame._ddPositionMotion = nil
    if resetTarget then
        frame._ddTargetPoint = nil
        frame._ddTargetRelPoint = nil
        frame._ddTargetX = nil
        frame._ddTargetY = nil
    end
end

local function InvalidateGroupLayoutCaches()
    local gr = DDingUI.GroupRenderer
    if gr and gr.InvalidateLayoutCaches then
        gr:InvalidateLayoutCaches()
    end
end

local function InvalidateSuppressedSpellCache()
    suppressedSpellCache = nil
    suppressedSpellCacheAt = 0
end

local function IsFlightHideAlphaLocked()
    local fh = DDingUI.FlightHide
    return fh and (fh.isActive or fh._hiding)
end

local function SafeNumber(value)
    if value == nil then return nil end
    if issecretvalue then
        local okSecret, secret = pcall(issecretvalue, value)
        if okSecret and secret then return nil end
    end
    local valueType = type(value)
    if valueType == "number" then
        if canaccessvalue and not canaccessvalue(value) then return nil end
        return value
    end
    if valueType == "string" then
        local okNumber, numberValue = pcall(tonumber, value)
        if okNumber then return numberValue end
    end
    return nil
end

local function SafeTableField(tbl, key)
    if not tbl or not key then return nil end
    local ok, value = pcall(function()
        return tbl[key]
    end)
    if ok then return value end
    return nil
end

local function IsCustomAuraPresetUnassignedEntry(spellName, entry)
    local spellID = type(entry) == "table" and SafeNumber(entry.spellID)
    if spellID and CUSTOM_AURA_PRESET_SPELL_IDS[spellID] then return true end

    local rawName = type(spellName) == "string" and spellName:gsub("^buff_", "") or nil
    if rawName and CUSTOM_AURA_PRESET_FALLBACK_NAMES[rawName] then return true end
    if type(spellName) == "string" and CUSTOM_AURA_PRESET_FALLBACK_NAMES[spellName] then return true end

    if rawName and C_Spell and C_Spell.GetSpellInfo then
        for presetID in pairs(CUSTOM_AURA_PRESET_SPELL_IDS) do
            local ok, info = pcall(C_Spell.GetSpellInfo, presetID)
            if ok and info and info.name and info.name == rawName then
                return true
            end
        end
    end
    return false
end

local function MaxActiveUntil(...)
    local best
    for i = 1, select("#", ...) do
        local rawValue = select(i, ...)
        local value = SafeNumber(rawValue)
        if value and value > 0 and (not best or value > best) then
            best = value
        end
    end
    return best
end

local function FrameHasLiveEffect(frame, now)
    local activeUntil = frame and MaxActiveUntil(frame._ddTimedAuraActiveUntil, frame._ddAuraActiveUntil, frame._ddProcActiveUntil)
    return activeUntil and activeUntil > (now or (GetTime and GetTime()) or 0)
end

local function FrameHadRecentEffect(frame, now)
    if not frame then return false end
    now = now or (GetTime and GetTime()) or 0
    local lastActive = MaxActiveUntil(frame._ddLastDynamicActiveAt, frame._ddLastAuraActiveAt, frame._ddLastProcActiveAt)
    return lastActive and (now - lastActive) <= COMBAT_ICON_GRACE_SECONDS
end

-- ============================================================
-- CustomIcons 접근 헬퍼
-- ============================================================

local function GetCustomIcons()
    return DDingUI.CustomIcons
end

-- CustomIcons.lua의 runtime.iconFrames에 접근
-- CustomIcons:GetAllIconFrames() API를 통해 접근 (Phase 5에서 추가)
local function GetIconFrames()
    local ci = GetCustomIcons()
    if ci and ci.GetAllIconFrames then
        return ci:GetAllIconFrames()
    end
    return {}
end

-- CustomIcons DB 접근
local function GetDynamicDB()
    local ci = GetCustomIcons()
    if ci and ci.GetDynamicDB then
        local db = ci.GetDynamicDB()
        if db then return db end
    end

    local profile = DDingUI.db and DDingUI.db.profile
    if not profile then return nil end
    profile.dynamicIcons = profile.dynamicIcons or {}
    local db = profile.dynamicIcons
    db.iconData = db.iconData or {}
    db.ungrouped = db.ungrouped or {}
    db.groups = db.groups or {}
    return db
end

local function GetDynamicIconData(iconKey)
    local db = GetDynamicDB()
    return db and db.iconData and db.iconData[iconKey] or nil
end

local function GetEquippedSlotItemID(iconFrame, slotID)
    if not slotID or not GetInventoryItemID then return nil end

    local ok, rawItemID = pcall(GetInventoryItemID, "player", slotID)
    local itemID = ok and SafeNumber(rawItemID)
    if itemID then
        if iconFrame then
            iconFrame._lastInventoryItemID = itemID
            iconFrame._lastInventoryItemAt = GetTime and GetTime() or 0
        end
        return itemID
    end

    return iconFrame and iconFrame._lastInventoryItemID or nil
end

local function ShouldTrackSlot(iconFrame, slotID)
    if not slotID then return false end
    if GetEquippedSlotItemID(iconFrame, slotID) then return true end
    return slotID == 13 or slotID == 14
end

-- ============================================================
-- 활성 아이콘 수집
-- ============================================================

-- ShouldIconSpawn 간이 버전 (CustomIcons의 로직 참조)
local function IsBuffSourceGroup(sourceGroupKey, db)
    if not sourceGroupKey then return false end

    local sourceGroup = db and db.groups and db.groups[sourceGroupKey]
    if sourceGroup and sourceGroup.linkedCDMGroup == "Buffs" then
        return true
    end

    local profile = DDingUI.db and DDingUI.db.profile
    local gsGroups = profile and profile.groupSystem and profile.groupSystem.groups
    if type(gsGroups) ~= "table" then return false end

    for groupName, groupSettings in pairs(gsGroups) do
        if groupSettings and groupSettings.sourceGroupKey == sourceGroupKey then
            if groupName == "Buffs" then return true end
            if groupSettings.groupCategory == "buff" then return true end
            if GROUP_VIEWER_MAP[groupName] == "BuffIconCooldownViewer" then return true end
        end
    end

    return false
end

local function IsBuffGroup(groupName, groupSettings)
    if groupName == "Buffs" then return true end
    if groupSettings and groupSettings.groupCategory == "buff" then return true end
    return GROUP_VIEWER_MAP[groupName] == "BuffIconCooldownViewer"
end

local function AddSuppressedSpellName(suppressed, spellName)
    if type(spellName) ~= "string" then return end
    local rawName = spellName:gsub("^buff_", "")
    if rawName == "" then return end

    local ok, info = pcall(function()
        return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(rawName)
    end)
    local spellID = ok and info and tonumber(info.spellID)
    if spellID and spellID > 0 then
        suppressed[spellID] = true
    end
end

local function AddSuppressedID(suppressed, value)
    local id = SafeNumber(value)
    if id and id > 0 then
        suppressed[id] = true
    end
end

local function AddSuppressedCooldownInfo(suppressed, cooldownID)
    local id = SafeNumber(cooldownID)
    if not id or id <= 0 then return end
    AddSuppressedID(suppressed, id)

    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return end
    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
    if not ok or type(info) ~= "table" then return end

    AddSuppressedID(suppressed, SafeTableField(info, "spellID"))
    AddSuppressedID(suppressed, SafeTableField(info, "overrideSpellID"))
    AddSuppressedID(suppressed, SafeTableField(info, "overrideTooltipSpellID"))

    local linkedIDs = SafeTableField(info, "linkedSpellIDs")
    if type(linkedIDs) == "table" then
        pcall(function()
            for _, linkedID in pairs(linkedIDs) do
                AddSuppressedID(suppressed, linkedID)
            end
        end)
    end
end

local function AddTrackedBuffSuppression(suppressed, buff)
    if type(buff) ~= "table" or buff.enabled == false or buff.disabled == true or buff.isGroup then return end
    local settings = buff.settings
    if not (type(settings) == "table" and settings.hideFromCDM) then return end

    AddSuppressedCooldownInfo(suppressed, buff.cooldownID)
    AddSuppressedID(suppressed, buff.spellID)
    AddSuppressedID(suppressed, settings.spellID)
    AddSuppressedID(suppressed, settings.customSpellID)
    AddSuppressedID(suppressed, settings.customAuraSpellID)
    AddSuppressedSpellName(suppressed, buff.name)
end

local function AddTrackedBuffSuppressions(suppressed)
    local db = DDingUI.db
    if not db then return end
    local rootCfg = db.profile and db.profile.buffTrackerBar
    if type(rootCfg) ~= "table" or rootCfg.enabled == false then return end

    local specID
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        specID = specIndex and GetSpecializationInfo(specIndex)
    end

    local globalStore = db.global and db.global.trackedBuffsPerSpec
    local tracked = specID and globalStore and globalStore[specID]
    if type(tracked) == "table" then
        for _, buff in ipairs(tracked) do
            AddTrackedBuffSuppression(suppressed, buff)
        end
    end

    if type(rootCfg.trackedBuffs) == "table" then
        for _, buff in ipairs(rootCfg.trackedBuffs) do
            AddTrackedBuffSuppression(suppressed, buff)
        end
    end
end

local function IsIconActive(iconKey, iconData, iconFrame, isBuffContext)
    if not iconData then return false end
    if not iconFrame then return false end
    local now = GetTime and GetTime() or 0
    local inCombat = InCombatLockdown and InCombatLockdown()

    if iconData.type == "item" then
        if iconData.settings and iconData.settings.hideWhenEmpty == true
            and iconFrame._ddItemCountEmpty == true
        then
            return false
        end
        return true
    end

    -- racial 타입: 등록 후 항상 활성 (쿨다운 상태만 변함)
    if iconData.type == "racial" then
        return true
    end

    if iconData.type == "slot" then
        local slotID = iconData.slotID
        return ShouldTrackSlot(iconFrame, slotID)
    end

    if iconData.type == "spell" then
        local ci = GetCustomIcons()
        if ci and ci.IsCurrentRacialSpellIcon and ci:IsCurrentRacialSpellIcon(iconData) then
            return true
        end
    end

    if iconData.type == "trinketProc" then
        local settings = iconData.settings or {}
        if settings.showItemCooldown ~= false then
            local slotID = iconData.slotID
            if ShouldTrackSlot(iconFrame, slotID) then return true end
        end

        if not isBuffContext then
            local slotID = iconData.slotID
            return ShouldTrackSlot(iconFrame, slotID)
        end

        local ci = GetCustomIcons()
        if ci and ci.ResolveTrinketProcAuraForIcon then
            local auraData = ci:ResolveTrinketProcAuraForIcon(iconFrame, iconData)
            local isActive = auraData ~= nil
            if iconFrame then
                iconFrame._trinketProcWasActive = isActive
                if auraData then
                    iconFrame._ddLastProcActiveAt = now
                    local duration = SafeNumber(SafeTableField(auraData, "duration"))
                    iconFrame._ddProcActiveUntil = SafeNumber(SafeTableField(auraData, "expirationTime"))
                        or (duration and (now + duration))
                        or (now + COMBAT_ICON_GRACE_SECONDS)
                elseif inCombat and FrameHasLiveEffect(iconFrame, now) then
                    iconFrame._trinketProcWasActive = true
                    return true
                elseif inCombat and iconFrame._ddLastProcActiveAt and (now - iconFrame._ddLastProcActiveAt) <= COMBAT_ICON_GRACE_SECONDS then
                    iconFrame._trinketProcWasActive = false
                    return false
                else
                    iconFrame._ddProcActiveUntil = nil
                end
            end
            return isActive
        end
        return iconFrame and iconFrame._trinketProcWasActive == true
    end

    -- spellbook 체크: spell 타입이면 배운 주문만
    if iconData.type == "spell" and iconData.id then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo(iconData.id)
        if not spellInfo then
            -- [FIX] 전투 중 GetSpellInfo가 일시적 nil 반환 — 폴백 체크
            -- IsSpellKnownOrOverridesKnown은 더 안정적 (캐시 기반)
            local isKnown = false
            pcall(function()
                isKnown = IsSpellKnownOrOverridesKnown(iconData.id)
                    or IsPlayerSpell(iconData.id)
            end)
            if not isKnown then
                -- 최종 폴백: 이전 프레임에서 보였으면 유지 (hysteresis)
                if iconFrame._wasVisibleInGroup then
                    return true
                end
                return false
            end
        end
    end

    -- [FIX] aura 타입: CustomIcons의 UpdateAuraIcon 내부 스캔 결과 활용
    -- C_UnitAuras.GetPlayerAuraBySpellID 단일 체크는 오라 ID와 주문 ID가 다를 때 실패함
    -- CustomIcons가 _cachedAuraSpellID와 AuraUtil 폴백으로 계산한 최종 상태 사용
    if iconData.type == "aura" and iconData.id then
        local ci = GetCustomIcons()
        if ci and ci.GetActiveCustomTimedAuraForIcon then
            local timedAura = ci:GetActiveCustomTimedAuraForIcon(iconData)
            if timedAura then
                if iconFrame then
                    iconFrame._auraWasActive = true
                    iconFrame._ddTimedAuraActiveUntil = SafeNumber(SafeTableField(timedAura, "expirationTime"))
                    iconFrame._ddLastAuraActiveAt = now
                    iconFrame._ddManagedAuraExpired = nil
                    iconFrame._ddCombatKeepAlive = nil
                    iconFrame._ddCombatVisible = nil
                    iconFrame._ddCombatMissingSince = nil
                end
                return true
            elseif iconFrame then
                iconFrame._ddTimedAuraActiveUntil = nil
            end
        end
        if ci and ci.ResolvePlayerAuraForIcon then
            local auraData = ci:ResolvePlayerAuraForIcon(iconFrame, iconData)
            local isActive = (auraData ~= nil)
            if iconFrame then
                iconFrame._auraWasActive = isActive
                if auraData then
                    iconFrame._ddLastAuraActiveAt = now
                    iconFrame._ddManagedAuraExpired = nil
                    iconFrame._ddCombatKeepAlive = nil
                    iconFrame._ddCombatVisible = nil
                    iconFrame._ddCombatMissingSince = nil
                    local expirationTime = SafeNumber(SafeTableField(auraData, "expirationTime"))
                    if expirationTime and expirationTime > 0 then
                        iconFrame._ddAuraActiveUntil = expirationTime
                    end
                    if SafeTableField(auraData, "__ddinguiTimedAura") then
                        iconFrame._ddTimedAuraActiveUntil = expirationTime
                    end
                elseif not isActive then
                    iconFrame._ddTimedAuraActiveUntil = nil
                    iconFrame._ddAuraActiveUntil = nil
                end
            end
            return isActive
        end
        -- [FIX] _auraWasActive 캐시에만 의존하지 않고 항상 직접 확인
        -- 전투 중 UpdateAuraIcon이 지연되면 캐시가 stale → 그룹에서 누락
        local auraData = nil
        pcall(function()
            if iconFrame and iconFrame._cachedAuraSpellID then
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconFrame._cachedAuraSpellID)
            else
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconData.id)
            end
        end)
        local isActive = (auraData ~= nil)
        -- 캐시도 동기화 (UpdateAuraIcon과 일관성 유지)
        if iconFrame then
            iconFrame._auraWasActive = isActive
            local expirationTime = auraData and SafeNumber(SafeTableField(auraData, "expirationTime"))
            if expirationTime and expirationTime > 0 then
                iconFrame._ddAuraActiveUntil = expirationTime
                iconFrame._ddLastAuraActiveAt = now
            elseif not isActive then
                iconFrame._ddAuraActiveUntil = nil
            end
        end
        return isActive
    end

    -- loadConditions 체크
    local settings = iconData.settings
    if settings and settings.loadConditions and settings.loadConditions.enabled then
        local lc = settings.loadConditions
        -- Spec 조건
        if lc.specs then
            local anySpecSet = false
            for _, v in pairs(lc.specs) do
                if v then anySpecSet = true; break end
            end
            if anySpecSet then
                local currentSpec = GetSpecialization and GetSpecialization() or 0
                local specID = currentSpec and GetSpecializationInfo and GetSpecializationInfo(currentSpec) or 0
                if not lc.specs[specID] then return false end
            end
        end
        -- Combat 조건
        if lc.inCombat and not InCombatLockdown() then return false end
        if lc.outOfCombat and InCombatLockdown() then return false end
    end

    return true
end

-- GroupSystem에서 호출: 특정 CustomIcons 그룹의 활성 아이콘 목록 반환
-- sourceGroupKey: CustomIcons의 그룹 키 ("group_xxx" 또는 "ungrouped")
-- 반환: { {iconKey=string, frame=Frame, iconData=table}, ... }
function DynamicIconBridge:GetActiveIconsForGroup(sourceGroupKey, groupSettings)
    -- [FIX] 미초기화 시 자동 초기화 시도
    if not initialized then
        self:Initialize()
        if not initialized then return {} end
    end

    local ci = GetCustomIcons()
    if not ci then return {} end

    local db = GetDynamicDB()
    if not db then return {} end

    local iconFrames = GetIconFrames()



    -- 대상 아이콘 키 수집
    local targetKeys = {}
    local targetOrder = {}
    local function AddTargetIconKey(iconKey)
        if type(iconKey) ~= "string" or iconKey == "" or targetKeys[iconKey] then return end
        targetKeys[iconKey] = true
        targetOrder[#targetOrder + 1] = iconKey
    end
    if sourceGroupKey == "ungrouped" then
        for iconKey in pairs(db.ungrouped or {}) do
            AddTargetIconKey(iconKey)
        end
        table_sort(targetOrder, function(a, b) return tostring(a) < tostring(b) end)
    else
        local group = db.groups and db.groups[sourceGroupKey]
        if group and group.icons then
            for _, iconKey in ipairs(group.icons) do
                AddTargetIconKey(iconKey)
            end
        end
    end



    -- [FIX] 편집모드에서는 모든 아이콘 반환 (비활성 강화효과도 표시)
    local isEditMode = (DDingUI.Movers and DDingUI.Movers.ConfigMode)
        or (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive())

    -- 활성 아이콘 필터링
    local result = {}
    local activeSet = {}
    local inCombat = InCombatLockdown and InCombatLockdown()
    local now = GetTime and GetTime() or 0
    local isBuffContext = IsBuffSourceGroup(sourceGroupKey, db)
    for sourceIndex, iconKey in ipairs(targetOrder) do
        local frame = iconFrames[iconKey]
        local iconData = db.iconData[iconKey]
        if not frame then
            -- skip: no frame exists
        elseif not iconData then
            -- skip: no icon data
        else
            local isActive = isEditMode
            if not isActive then
                local okActive, activeResult = pcall(IsIconActive, iconKey, iconData, frame, isBuffContext)
                if okActive then
                    isActive = activeResult == true
                    frame._ddLastDynamicError = nil
                else
                    isActive = false
                    frame._ddLastDynamicError = tostring(activeResult)
                end
            end
            local keepVisible = false
            local keepManaged = false
            local hideEmptyItem = not isEditMode
                and iconData.type == "item"
                and iconData.settings
                and iconData.settings.hideWhenEmpty == true
                and frame._ddItemCountEmpty == true

            if isActive then
                frame._ddLastDynamicActiveAt = now
                frame._wasVisibleInGroup = true
                keepVisible = true
            elseif inCombat and not hideEmptyItem then
                local isCooldownTrinket = iconData.type == "trinketProc"
                    and (not iconData.settings or iconData.settings.showItemCooldown ~= false)
                local isAuraIcon = iconData.type == "aura"
                local isEffectIcon = isAuraIcon or (iconData.type == "trinketProc" and isBuffContext and not isCooldownTrinket)
                local liveEffect = isEffectIcon and not isAuraIcon and FrameHasLiveEffect(frame, now)
                local expiredManagedAura = isEffectIcon and iconData.type == "aura" and frame._ddManagedAuraExpired
                local recentEffect = isEffectIcon and not isAuraIcon and not expiredManagedAura and FrameHadRecentEffect(frame, now)
                keepManaged = (not isEffectIcon) and (frame._ddIsManaged and frame._ddContainerRef) and true or false
                local keepHistorical = (not isEffectIcon) and frame._wasVisibleInGroup == true
                local lastActive = frame._ddLastDynamicActiveAt
                local graceVisible = lastActive and (now - lastActive) <= COMBAT_ICON_GRACE_SECONDS
                keepVisible = (not expiredManagedAura and (liveEffect or recentEffect)) or keepManaged or keepHistorical or ((not isEffectIcon) and graceVisible)
                if liveEffect then
                    frame._ddLastDynamicActiveAt = now
                end
                if keepVisible and not (keepManaged or keepHistorical) and not frame._ddGraceNotifyPending then
                    frame._ddGraceNotifyPending = true
                    C_Timer.After(COMBAT_ICON_GRACE_SECONDS + 0.05, function()
                        frame._ddGraceNotifyPending = nil
                        if initialized and layoutSuppressed then
                            DynamicIconBridge:NotifyIconsChanged()
                        end
                    end)
                end
            end

            local isCooldownTrinket = iconData.type == "trinketProc"
                and (not iconData.settings or iconData.settings.showItemCooldown ~= false)
            local isAuraIcon = iconData.type == "aura"
            local isEffectIcon = isAuraIcon or (iconData.type == "trinketProc" and isBuffContext and not isCooldownTrinket)
            local showInactive, desaturateInactive = ResolveInactiveBuffDisplay(iconData)
            local includeActiveStateGray = groupSettings
                and groupSettings.hideActiveState == true
                and isBuffContext
                and isActive
                and isEffectIcon
            local includeInactive = showInactive and isEffectIcon and not (isActive or keepVisible or keepManaged)
            local forceGray = (includeInactive and desaturateInactive) or includeActiveStateGray
            if not (isActive or keepVisible or keepManaged or includeInactive or includeActiveStateGray) then
            -- [FIX] 비활성 전환: hysteresis 플래그 해제
                if not inCombat then
                    frame._wasVisibleInGroup = nil
                    frame._ddLastDynamicActiveAt = nil
                end
        else
            if forceGray then
                frame._ddCombatKeepAlive = nil
                frame._ddCombatVisible = true
            end
            result[#result + 1] = {
                iconKey = iconKey,
                frame = frame,
                iconData = iconData,
                isDynamic = true,
                sourceIndex = sourceIndex,
                active = isActive,
                combatKeepAlive = keepVisible and not isActive,
                combatVisible = includeInactive or includeActiveStateGray or keepVisible,
                inactiveGray = forceGray,
                inactivePlaceholder = includeInactive,
            }
            -- [FIX] 활성 상태 기록: 다음 틱에서 일시적 nil 반환 시 유지
            if isActive or keepVisible then
                frame._wasVisibleInGroup = true
            end
            activeSet[iconKey] = true
        end
    end
    end



    -- 정렬: 그룹 내 순서 유지
    if sourceGroupKey ~= "ungrouped" then
        local group = db.groups and db.groups[sourceGroupKey]
        if group and group.icons then
            local orderMap = {}
            for i, k in ipairs(group.icons) do
                if type(k) == "string" and not orderMap[k] then
                    orderMap[k] = i
                end
            end
            table_sort(result, function(a, b)
                local aOrder = orderMap[a.iconKey] or a.sourceIndex or 999999
                local bOrder = orderMap[b.iconKey] or b.sourceIndex or 999999
                if aOrder ~= bOrder then return aOrder < bOrder end
                return tostring(a.iconKey or "") < tostring(b.iconKey or "")
            end)
        end
    else
        table_sort(result, function(a, b)
            return tostring(a.iconKey or "") < tostring(b.iconKey or "")
        end)
    end

    -- 같은 CustomIcons 그룹 안에서 같은 spell/aura가 중복 생성되어도 하나만 렌더링
    local seenIdentity = {}
    local deduped = {}
    for _, entry in ipairs(result) do
        local iconData = entry.iconData
        local identity = nil
        if iconData and (iconData.type == "spell" or iconData.type == "aura") and iconData.id then
            identity = iconData.type .. ":" .. tostring(tonumber(iconData.id) or iconData.id)
        end
        if not identity or not seenIdentity[identity] then
            if identity then seenIdentity[identity] = true end
            deduped[#deduped + 1] = entry
        end
    end
    result = deduped

    return result
end

-- 커스텀 그룹에서 추적 중인 모든 아이콘의 spell ID 세트 반환
-- CDM 그룹에서 中복 아이콘을 숨기는 데 사용
-- 반환: { [spellID] = true, ... }
function DynamicIconBridge:GetSuppressedSpellIDs()
    if not initialized then
        self:Initialize()
        if not initialized then return {} end
    end

    local now = GetTime and GetTime() or 0
    if suppressedSpellCache and (now - suppressedSpellCacheAt) <= SUPPRESSED_SPELL_CACHE_TTL then
        return suppressedSpellCache
    end

    local db = GetDynamicDB()
    if not db then return {} end

    local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    if not gs or not gs.groups then return {} end

    local suppressed = {}

    if type(gs.unassignedBuffSpells) == "table" then
        for spellName, enabled in pairs(gs.unassignedBuffSpells) do
            if enabled and not IsCustomAuraPresetUnassignedEntry(spellName, enabled) then
                local spellID = type(enabled) == "table" and tonumber(enabled.spellID)
                if spellID and spellID > 0 then
                    suppressed[spellID] = true
                else
                    AddSuppressedSpellName(suppressed, spellName)
                end
            end
        end
    end

    -- 모든 dynamic 그룹의 아이콘 spell ID 수집
    AddTrackedBuffSuppressions(suppressed)

    for groupName, groupSettings in pairs(gs.groups) do
        local shouldSuppressDuplicates = groupSettings.enabled
            and groupSettings.sourceGroupKey
            and (IsBuffGroup(groupName, groupSettings)
                or (groupSettings.groupType ~= "dynamic" and groupSettings.suppressCDMDuplicates == true))

        if shouldSuppressDuplicates then
            local srcKey = groupSettings.sourceGroupKey
            local group = db.groups and db.groups[srcKey]
            if group and group.icons then
                for _, iconKey in ipairs(group.icons) do
                    local iconData = db.iconData[iconKey]
                    if iconData then
                        if iconData.id and (iconData.type == "spell" or iconData.type == "aura") then
                            if not (IsBuffGroup(groupName, groupSettings) and iconData.type == "aura") then
                                suppressed[iconData.id] = true
                            end
                        elseif iconData.type == "trinketProc" and iconData.settings then
                            local procSpellID = tonumber(iconData.settings.procSpellID)
                            if procSpellID and procSpellID > 0 then
                                suppressed[procSpellID] = true
                            end
                        end
                    end
                end
            end
        end
    end

    suppressedSpellCache = suppressed
    suppressedSpellCacheAt = now
    return suppressed
end

function DynamicIconBridge:InvalidateSuppressedSpellCache()
    InvalidateSuppressedSpellCache()
end

-- CustomIcons 그룹 목록 반환 (GroupSystem 동기화용)
-- 반환: { [sourceGroupKey] = {name=string, enabled=boolean, iconCount=number}, ... }
function DynamicIconBridge:GetDynamicGroups()
    local db = GetDynamicDB()
    if not db then return {} end

    local result = {}

    -- 사용자 정의 그룹
    for groupKey, group in pairs(db.groups or {}) do
        result[groupKey] = {
            name = group.name or groupKey,
            enabled = group.enabled ~= false,
            iconCount = group.icons and #group.icons or 0,
            linkedCDMGroup = group.linkedCDMGroup,
        }
    end

    -- ungrouped 아이콘이 있으면 포함
    local ungroupedCount = 0
    for _ in pairs(db.ungrouped or {}) do
        ungroupedCount = ungroupedCount + 1
    end
    if ungroupedCount > 0 then
        result["ungrouped"] = {
            name = "Ungrouped",
            enabled = true,
            iconCount = ungroupedCount,
        }
    end

    return result
end

-- [FIX] zoom + 종횡비 크롭을 결합한 TexCoord 적용
-- CustomIcons의 ApplyAspectRatioCrop과 동일한 로직
local function BuildDynamicLayoutStateHash()
    local db = GetDynamicDB()
    if not db then return "", {} end
    local inCombat = InCombatLockdown and InCombatLockdown()
    local iconFrames = GetIconFrames()
    local now = GetTime and GetTime() or 0

    local sourceKeys = {}
    local sourceSeen = {}
    local gs = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    local groups = gs and gs.groups
    if type(groups) == "table" then
        for _, groupSettings in pairs(groups) do
            local sourceKey = groupSettings and groupSettings.enabled and groupSettings.sourceGroupKey
            if sourceKey and not sourceSeen[sourceKey] then
                sourceSeen[sourceKey] = true
                sourceKeys[#sourceKeys + 1] = sourceKey
            end
        end
    end

    table_sort(sourceKeys, function(a, b) return tostring(a) < tostring(b) end)

    local parts = {}
    local sourceParts = {}
    for _, sourceKey in ipairs(sourceKeys) do
        local keys = {}
        if sourceKey == "ungrouped" then
            for iconKey in pairs(db.ungrouped or {}) do
                keys[#keys + 1] = iconKey
            end
            table_sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        else
            local sourceGroup = db.groups and db.groups[sourceKey]
            if sourceGroup and sourceGroup.icons then
                for _, iconKey in ipairs(sourceGroup.icons) do
                    keys[#keys + 1] = iconKey
                end
            end
        end

        local isBuffContext = IsBuffSourceGroup(sourceKey, db)
        for _, iconKey in ipairs(keys) do
            local iconData = db.iconData and db.iconData[iconKey]
            local frame = iconFrames and iconFrames[iconKey]
            if iconData and frame then
                local token = "1"
                local isCooldownTrinket = iconData.type == "trinketProc"
                    and (not iconData.settings or iconData.settings.showItemCooldown ~= false)
                local isEffectIcon = iconData.type == "aura" or (iconData.type == "trinketProc" and isBuffContext and not isCooldownTrinket)

                if isEffectIcon then
                    local expiredManagedAura = iconData.type == "aura" and frame._ddManagedAuraExpired
                    local active = false
                    if iconData.type == "aura" then
                        local ci = GetCustomIcons()
                        if ci and ci.IsCustomTimedAuraIcon and ci:IsCustomTimedAuraIcon(iconData) then
                            active = ci.GetActiveCustomTimedAuraForIcon and ci:GetActiveCustomTimedAuraForIcon(iconData) ~= nil
                        else
                            active = not expiredManagedAura and frame._auraWasActive == true
                        end
                    else
                        active = frame._trinketProcWasActive == true
                            or FrameHasLiveEffect(frame, now)
                            or (inCombat and not expiredManagedAura and FrameHadRecentEffect(frame, now))
                    end
                    token = active and "1" or nil
                elseif iconData.type == "slot" or iconData.type == "trinketProc" then
                    local slotID = iconData.slotID
                    token = (ShouldTrackSlot(frame, slotID) or (inCombat and frame._wasVisibleInGroup)) and "1" or nil
                end

                if not token and isEffectIcon then
                    local showInactive, desaturateInactive = ResolveInactiveBuffDisplay(iconData)
                    if showInactive then
                        token = desaturateInactive and "g" or "i"
                    end
                end
                if token then
                    local part = tostring(sourceKey) .. ":" .. tostring(iconKey) .. ":" .. (inCombat and "c" or token)
                    parts[#parts + 1] = part
                    local sourcePartList = sourceParts[sourceKey]
                    if not sourcePartList then
                        sourcePartList = {}
                        sourceParts[sourceKey] = sourcePartList
                    end
                    sourcePartList[#sourcePartList + 1] = part
                end
            end
        end
    end

    table_sort(parts)
    local sourceHashes = {}
    for sourceKey, sourcePartList in pairs(sourceParts) do
        table_sort(sourcePartList)
        sourceHashes[sourceKey] = table_concat(sourcePartList, ";")
    end
    return table_concat(parts, ";"), sourceHashes
end

local function BuildDirtySourceKeys(previousHashes, nextHashes)
    if type(previousHashes) ~= "table" or type(nextHashes) ~= "table" then
        return nil
    end

    local dirty
    for sourceKey, hash in pairs(nextHashes) do
        if previousHashes[sourceKey] ~= hash then
            dirty = dirty or {}
            dirty[sourceKey] = true
        end
    end
    for sourceKey in pairs(previousHashes) do
        if nextHashes[sourceKey] == nil then
            dirty = dirty or {}
            dirty[sourceKey] = true
        end
    end
    return dirty
end

function DynamicIconBridge.ApplyTexCoordCrop(texture, zoom, aspectRatio)
    if not texture or not texture.SetTexCoord then return end
    zoom = zoom or 0.08
    aspectRatio = aspectRatio or 1.0
    if aspectRatio <= 0 then aspectRatio = 1.0 end

    local left, right, top, bottom = zoom, 1 - zoom, zoom, 1 - zoom
    local regionW = right - left
    local regionH = bottom - top

    if regionW > 0 and regionH > 0 and aspectRatio ~= 1.0 then
        local currentRatio = regionW / regionH
        if aspectRatio > currentRatio then
            local desiredH = regionW / aspectRatio
            local cropH = (regionH - desiredH) / 2
            top = top + cropH
            bottom = bottom - cropH
        elseif aspectRatio < currentRatio then
            local desiredW = regionH * aspectRatio
            local cropW = (regionW - desiredW) / 2
            left = left + cropW
            right = right - cropW
        end
    end

    texture:SetTexCoord(left, right, top, bottom)
end

-- ============================================================
-- 프레임 컨테이너 관리 (FrameController 패턴)
-- ============================================================

function DynamicIconBridge:SetupFrameInContainer(frame, container, targetW, targetH, iconKey, zoom, aspectRatioCrop)
    if not frame or not container then return end
    local needsLayoutReset = frame._ddContainerRef ~= container or frame._ddIconKey ~= iconKey
    if needsLayoutReset then
        ResetGroupIconLayoutState(frame, true)
    end
    targetW = tonumber(targetW) or 40
    targetH = tonumber(targetH) or targetW
    if targetW < 1 then targetW = 40 end
    if targetH < 1 then targetH = targetW end

    -- 1. 원래 상태 저장 (최초 1회)
    if not frame._ddOrigState then
        frame._ddOrigState = {
            parent = frame:GetParent(),
            width = frame:GetWidth(),
            height = frame:GetHeight(),
            scale = frame:GetScale(),
            points = {},
        }
        local numPoints = frame:GetNumPoints()
        for i = 1, numPoints do
            local point, relTo, relPoint, x, y = frame:GetPoint(i)
            frame._ddOrigState.points[i] = { point, relTo, relPoint, x, y }
        end
    end

    -- 2. SetParent(UIParent) + 컨테이너 참조 -- [DYNAMIC]
    frame:SetParent(UIParent)
    frame._ddContainerRef = container
    frame._ddGroupName = container._groupName
    frame._ddSourceViewer = GROUP_VIEWER_MAP[frame._ddGroupName]
    frame._groupSettings = container._groupSettings or frame._groupSettings
    local iconData = GetDynamicIconData(iconKey)
    local expiredManagedAura = iconData and iconData.type == "aura" and frame._ddManagedAuraExpired
    if not (iconData and iconData.type == "aura") then
        frame._ddManagedAuraExpired = nil
        if frame.icon and frame.icon.SetAlpha and not IsFlightHideAlphaLocked() then
            frame.icon:SetAlpha(1)
        end
    end
    if frame.cooldown then
        frame.cooldown._ddGroupName = frame._ddGroupName
        frame.cooldown._ddSourceViewer = frame._ddSourceViewer
    end
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(container:GetFrameLevel() + 10)

    -- 3. 스케일 강제 1
    frame:SetScale(1)

    -- 4. 타겟 크기 설정
    frame._ddTargetWidth = targetW
    frame._ddTargetHeight = targetH
    frame._ddSettingSize = true
    frame:SetSize(targetW, targetH)
    frame._ddSettingSize = false

    -- 아이콘 텍스처: zoom + 종횡비 크롭을 TexCoord에 결합
    if frame.icon then
        zoom = zoom or 0.08
        frame.icon:SetAllPoints(frame)
        DynamicIconBridge.ApplyTexCoordCrop(frame.icon, zoom, aspectRatioCrop or 1.0)
    end

    -- 5. 관리 태그
    frame._ddIsManaged = true
    frame._ddIconKey = iconKey

    -- [FIX] reparent 후 명시적 Show (이전 부모가 숨겨졌으면 프레임도 숨겨진 상태)
    if expiredManagedAura then
        frame:SetAlpha(0)
        frame:Hide()
    else
        frame:Show()
    end

    -- [FIX] SetSize, ClearAllPoints, SetPoint table overrides (Not hooksecurefunc)
    -- hooksecurefunc runs AFTER the original, causing 1-frame flickering (0x0 or wrong position).
    -- By overriding the table method, we completely block CustomIcons from changing size/position
    -- while the icon is managed by DDingUI GroupSystem.
    if not frame._ddBridgeHooksInstalled then
        frame._SetSize_orig = frame.SetSize
        frame.SetSize = function(self, w, h)
            if self._ddSettingSize or not self._ddIsManaged then
                return self:_SetSize_orig(w, h)
            end
            -- Ignore unauthorized SetSize while managed
        end

        frame._ClearAllPoints_orig = frame.ClearAllPoints
        frame.ClearAllPoints = function(self)
            if self._ddSettingPosition or not self._ddIsManaged then
                return self:_ClearAllPoints_orig()
            end
            -- Ignore unauthorized ClearAllPoints
        end

        frame._SetPoint_orig = frame.SetPoint
        frame.SetPoint = function(self, pt, relTo, relPt, x, y)
            if self._ddSettingPosition or not self._ddIsManaged then
                return self:_SetPoint_orig(pt, relTo, relPt, x, y)
            end
            -- Ignore unauthorized SetPoint
        end

        frame._ddBridgeHooksInstalled = true
    end

    -- 6. 초기 위치 (CENTER, GroupRenderer의 LayoutGroup이 최종 위치 설정)
    if not frame._ddTargetPoint then
        frame._ddTargetPoint = "CENTER"
        frame._ddTargetRelPoint = "CENTER"
        frame._ddTargetX = 0
        frame._ddTargetY = 0
    end

    frame._ddSettingPosition = true
    frame:ClearAllPoints()
    frame:SetPoint(
        frame._ddTargetPoint,
        container,
        frame._ddTargetRelPoint or "CENTER",
        frame._ddTargetX or 0,
        frame._ddTargetY or 0
    )
    frame._ddSettingPosition = false

    -- 7. Show
    if expiredManagedAura then
        frame:SetAlpha(0)
        frame:Hide()
    elseif container:IsShown() then
        frame:Show()
    else
        frame:Hide()
    end

    -- [FIX] FlightHide 활성 중이면 새 아이콘도 알파 0 적용
    local fh = DDingUI.FlightHide
    if fh and fh.isActive then
        frame:SetAlpha(0)
    end

    managedFrames[iconKey] = true
end

function DynamicIconBridge:ReleaseFrame(frame, iconKey)
    if not frame then return end

    local orig = frame._ddOrigState
    frame._ddIsManaged = nil
    ResetGroupIconLayoutState(frame, true)
    if orig then
        -- [FIX] 이미 부모가 nil (RemoveGroup에서 정리됨)이면 복원하지 않음 (고스트 프레임 방지)
        if orig.parent and frame:GetParent() ~= nil then
            frame:SetParent(orig.parent)
        end
        if frame:GetParent() ~= nil then
            frame:SetSize(orig.width or 40, orig.height or orig.width or 40)
            frame:SetScale(orig.scale)
        end
    end

    -- 관리 태그 정리
    frame._ddTargetPoint = nil
    frame._ddTargetRelPoint = nil
    frame._ddTargetX = nil
    frame._ddTargetY = nil
    frame._ddTargetWidth = nil
    frame._ddTargetHeight = nil
    frame._ddContainerRef = nil
    frame._ddIconKey = nil
    frame._ddGroupName = nil
    frame._ddSourceViewer = nil
    frame._groupSettings = nil
    frame._ddCombatKeepAlive = nil
    frame._ddCombatVisible = nil
    frame._ddLastDynamicActiveAt = nil
    frame._ddTimedAuraActiveUntil = nil
    frame._ddAuraActiveUntil = nil
    frame._ddProcActiveUntil = nil
    frame._ddManagedAuraExpired = nil
    if frame.cooldown then
        frame.cooldown._ddGroupName = nil
        frame.cooldown._ddSourceViewer = nil
    end
    frame._ddOrigState = nil

    if iconKey then
        managedFrames[iconKey] = nil
    end

    -- [FIX] 해제된 프레임 명시적 숨기기 (원래 부모로 복원 후에도 화면에 남는 고스트 방지)
    if frame.Hide then
        frame:Hide()
    end
end

function DynamicIconBridge:ReleaseAllFrames()
    local iconFrames = GetIconFrames()
    for iconKey in pairs(managedFrames) do
        local frame = iconFrames[iconKey]
        if frame then
            self:ReleaseFrame(frame, iconKey)
        end
    end
    wipe(managedFrames)
end

function DynamicIconBridge:IsFrameManaged(iconKey)
    return managedFrames[iconKey] == true
end

-- ============================================================
-- CustomIcons 레이아웃 억제
-- ============================================================

function DynamicIconBridge:IsActive()
    return initialized and layoutSuppressed
end

function DynamicIconBridge:SuppressCustomIconsLayout()
    layoutSuppressed = true
end

function DynamicIconBridge:RestoreCustomIconsLayout()
    if not layoutSuppressed then return end
    layoutSuppressed = false

    -- 복원 후 CustomIcons가 자체 레이아웃을 재실행하도록 트리거
    local ci = GetCustomIcons()
    if ci and ci.LoadDynamicIcons then
        C_Timer.After(0.1, function()
            ci:LoadDynamicIcons()
        end)
    end
end

-- ============================================================
-- [FIX] CDM 프레임 숨기기 (BuffTrackerBar.hideFromCDM 패턴)
-- SetAlpha(0) + Show/SetShown 훅 — 전투 중에도 안전
-- Hide()는 보호 프레임에서 taint를 유발할 수 있으므로 SetAlpha(0) 사용
-- ============================================================

local function HideCDMFrame(frame, cooldownID)
    if not frame then return end
    if frame._ddDynBridgeHidden then return end  -- 이미 숨김

    frame._ddDynBridgeHidden = true
    frame._ddDynBridgeHiddenCdID = cooldownID
    -- [PHASE3] SetAlpha(0) — 전투 중에도 taint 없이 작동
    frame._ddAlphaGuard = true
    frame:SetAlpha(0)
    frame._ddAlphaGuard = nil
    -- EnableMouse(false) — 투명 상태에서 클릭 방지
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
    hiddenCDMFrames[frame] = cooldownID

    -- Show hook: CDM이 Show() 호출하면 즉시 다시 SetAlpha(0)
    if not frame._ddDynBridgeShowHooked then
        hooksecurefunc(frame, "Show", function(self)
            if self._ddDynBridgeHidden then
                -- 프레임 재활용 감지: cooldownID 변경 시 새 ID가 억제 대상인지 확인
                if self._ddDynBridgeHiddenCdID then
                    local currentID = self.cooldownID
                    if currentID and currentID ~= self._ddDynBridgeHiddenCdID then
                        if not DynamicIconBridge:ShouldSuppressCooldownID(currentID) then
                            self._ddDynBridgeHidden = nil
                            self._ddDynBridgeHiddenCdID = nil
                            hiddenCDMFrames[self] = nil
                            if not IsFlightHideAlphaLocked() then
                                self._ddAlphaGuard = true
                                self:SetAlpha(1)
                                self._ddAlphaGuard = nil
                            end
                            if self.EnableMouse then pcall(self.EnableMouse, self, true) end
                            return
                        else
                            self._ddDynBridgeHiddenCdID = currentID
                            hiddenCDMFrames[self] = currentID
                        end
                    end
                end
                self._ddAlphaGuard = true
                self:SetAlpha(0)
                self._ddAlphaGuard = nil
                if self.EnableMouse then pcall(self.EnableMouse, self, false) end
            end
        end)
        frame._ddDynBridgeShowHooked = true
    end

    -- SetShown hook
    if not frame._ddDynBridgeSetShownHooked then
        hooksecurefunc(frame, "SetShown", function(self, shown)
            -- [FIX] secret value 방어: shown 값이 테이블(secret)일 경우 평가 시 에러 발생
            if type(shown) == "table" or (issecretvalue and issecretvalue(shown)) then return end
            if shown and self._ddDynBridgeHidden then
                self._ddAlphaGuard = true
                self:SetAlpha(0)
                self._ddAlphaGuard = nil
                if self.EnableMouse then pcall(self.EnableMouse, self, false) end
            end
        end)
        frame._ddDynBridgeSetShownHooked = true
    end

    -- [PHASE3] SetAlpha hook — CDM이 SetAlpha(1) 호출해도 즉시 재숨김
    if not frame._ddDynBridgeAlphaHooked then
        hooksecurefunc(frame, "SetAlpha", function(self, alpha)
            if self._ddAlphaGuard then return end  -- 재귀 방지
            -- [FIX] secret value 방어: alpha가 숫자가 아니면(secret table) 대조 불가
            if type(alpha) ~= "number" or (issecretvalue and issecretvalue(alpha)) then return end
            if self._ddDynBridgeHidden and alpha > 0 then
                self._ddAlphaGuard = true
                self:SetAlpha(0)
                self._ddAlphaGuard = nil
            end
        end)
        frame._ddDynBridgeAlphaHooked = true
    end
end

local function UnhideCDMFrame(frame)
    if not frame then return end
    frame._ddDynBridgeHidden = nil
    frame._ddDynBridgeHiddenCdID = nil
    hiddenCDMFrames[frame] = nil
    -- [PHASE3] 알파/마우스 복원 (guard로 SetAlpha hook 우회)
    if not IsFlightHideAlphaLocked() then
        frame._ddAlphaGuard = true
        frame:SetAlpha(1)
        frame._ddAlphaGuard = nil
    end
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, true) end
end

local function ScanAndHideCDMBuffs()
    local suppressed = DynamicIconBridge:GetSuppressedSpellIDs()
    if not next(suppressed) then
        for frame in pairs(hiddenCDMFrames) do
            UnhideCDMFrame(frame)
        end
        return
    end

    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer.itemFramePool then return end

    for frame in viewer.itemFramePool:EnumerateActive() do
        if frame and frame.cooldownID then
            local shouldSuppress = false
            pcall(function()
                if frame.auraSpellID and suppressed[frame.auraSpellID] then
                    shouldSuppress = true
                end
            end)
            if not shouldSuppress then
                pcall(function()
                    if frame.cooldownID and suppressed[frame.cooldownID] then
                        shouldSuppress = true
                    end
                end)
            end
            if shouldSuppress then
                HideCDMFrame(frame, frame.cooldownID)
            end
        end
    end
end

-- cooldownID가 억제 대상인지 확인 (HideCDMFrame 재활용 체크용)
function DynamicIconBridge:ShouldSuppressCooldownID(cooldownID)
    local suppressed = self:GetSuppressedSpellIDs()
    local result = false
    pcall(function()
        if suppressed[cooldownID] then result = true end
    end)
    return result
end

-- ============================================================
-- 초기화 / 종료
-- ============================================================

function DynamicIconBridge:Initialize()
    if initialized then return end

    -- CustomIcons가 로드되지 않았으면 재시도
    local ci = GetCustomIcons()
    if not ci then
        -- [FIX] 최대 10회 재시도 (1초 간격) — 이전에는 1회만 시도 후 포기
        self._initRetries = (self._initRetries or 0) + 1
        if self._initRetries <= 10 then
            C_Timer.After(1, function()
                self:Initialize()
            end)
        end
        return
    end

    initialized = true
    self._initRetries = nil
    self._lastAppliedLayoutStateHash = nil
    self._lastAppliedSourceHashes = nil

    -- 레이아웃 억제 시작
    self:SuppressCustomIconsLayout()

    -- [FIX] CDM BuffViewer Layout 훅 — CDM이 아이콘을 Show하면 즉시 숨김
    -- BuffFrameManager.Initialize 패턴: Layout/UpdateLayout 훅으로 타이밍 갭 제거
    local viewer = _G["BuffIconCooldownViewer"]
    if viewer and not self._viewerLayoutHooked then
        self._viewerLayoutHooked = true
        if viewer.Layout then
            hooksecurefunc(viewer, "Layout", function()
                if initialized then ScanAndHideCDMBuffs() end
            end)
        end
        if viewer.UpdateLayout then
            hooksecurefunc(viewer, "UpdateLayout", function()
                if initialized then ScanAndHideCDMBuffs() end
            end)
        end
    end

    if not self._auraEventFrame then
        self._auraEventFrame = CreateFrame("Frame")
        self._auraEventFrame:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_AURA" and unit ~= "player" then return end
            if not initialized then return end
            ScanAndHideCDMBuffs()
            self:NotifyIconsChanged(false)
        end)
    end
    self._auraEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    self._auraEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- 즉시 초기 스캔
    ScanAndHideCDMBuffs()

    -- CDM 뷰어가 아직 준비 안 됐을 수 있으므로 폴백
    C_Timer.After(0.5, function()
        if initialized then ScanAndHideCDMBuffs() end
    end)
    C_Timer.After(2.0, function()
        if initialized then ScanAndHideCDMBuffs() end
    end)
end

function DynamicIconBridge:Shutdown()
    if not initialized then return end
    initialized = false
    if self._auraEventFrame then
        self._auraEventFrame:UnregisterAllEvents()
    end

    -- CDM 프레임 숨김 해제
    for frame in pairs(hiddenCDMFrames) do
        UnhideCDMFrame(frame)
    end
    wipe(hiddenCDMFrames)

    -- 모든 managed 프레임 복원
    self:ReleaseAllFrames()

    -- CustomIcons 레이아웃 복원
    self:RestoreCustomIconsLayout()
end

-- ============================================================
-- GroupSystem 업데이트 트리거 (CustomIcons 이벤트 → GroupSystem 재레이아웃)
-- ============================================================

-- CustomIcons changes only mark the shared GroupSystem queue dirty.
-- State hashing and source selection run once when the queue consumes the mark.
function DynamicIconBridge:NotifyIconsChanged(forceLayout)
    if not initialized then return end
    if not layoutSuppressed then return end

    if forceLayout then
        InvalidateGroupLayoutCaches()
    end
    local gs = DDingUI.GroupSystem
    if gs and gs.RequestDynamicUpdate then
        local delay = (InCombatLockdown and InCombatLockdown()) and 0.3 or 0.16
        gs:RequestDynamicUpdate(forceLayout and true or nil, delay, true)
    elseif gs and gs.RequestFullUpdate then
        gs:RequestFullUpdate()
    elseif gs and gs.DoFullUpdate then
        gs:DoFullUpdate()
    end
end

function DynamicIconBridge:CollectDirtySourceKeys()
    if not initialized or not layoutSuppressed then return false end
    ScanAndHideCDMBuffs()

    local stateHash, sourceHashes = BuildDynamicLayoutStateHash()
    if stateHash == self._lastAppliedLayoutStateHash then
        return false
    end

    local sourceKeys = BuildDirtySourceKeys(self._lastAppliedSourceHashes, sourceHashes)
    self._lastAppliedLayoutStateHash = stateHash
    self._lastAppliedSourceHashes = sourceHashes
    return sourceKeys or true
end
