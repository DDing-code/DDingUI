local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local NativeTrinketOverlay = {}
DDingUI.NativeTrinketOverlay = NativeTrinketOverlay

local CDMCompat = DDingUI.CDMCompat
local pairsBySlot = {}
local pairByProcFrame = setmetatable({}, { __mode = "k" })
local pairByBaseFrame = setmetatable({}, { __mode = "k" })
local pairByNativeCooldownFrame = setmetatable({}, { __mode = "k" })
local hiddenCatalogCooldownIDs = {}
local nativeEffectSlots = {}
local pairMissingScans = {}
local effectMissingScans = {}
local stateRefreshQueued = false
local legacyPairSignature
local eventFrame = CreateFrame("Frame")
local SCAN_MISS_GRACE = 2

local function IsSecret(value)
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then
        return true
    end
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

local function IsPublicNumber(value)
    return not IsSecret(value) and type(value) == "number" and value == value
end

local function IsTrackedSlot(slotID)
    return slotID == 13 or slotID == 14
end

local function GetCooldown(frame)
    return frame and (frame.Cooldown or frame.cooldown) or nil
end

local function GetApplications(frame)
    return frame and (frame.Applications or frame.count) or nil
end

local function GetSafeAlpha(region, fallback)
    if not region or type(region.GetAlpha) ~= "function" then return fallback end
    local ok, alpha = pcall(region.GetAlpha, region)
    if ok and IsPublicNumber(alpha) then return alpha end
    return fallback
end

local function SetRegionAlpha(region, alpha, guardKey)
    if not region or type(region.SetAlpha) ~= "function" then return end
    local current = GetSafeAlpha(region, nil)
    if current and math.abs(current - alpha) < 0.001 then return end
    region[guardKey] = true
    region:SetAlpha(alpha)
    region[guardKey] = nil
end

local function IsIntegrationEnabled()
    local profile = DDingUI.db and DDingUI.db.profile
    local groupSystem = profile and profile.groupSystem
    return not groupSystem or groupSystem.integrateNativeTrinketEffects ~= false
end

local function ReadProcActive(frame)
    if not frame then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end

    local active
    if CDMCompat and type(CDMCompat.GetFrameActiveState) == "function" then
        active = CDMCompat:GetFrameActiveState(frame)
    elseif type(frame.IsActive) == "function" then
        local ok, value = pcall(frame.IsActive, frame)
        if ok and not IsSecret(value) and type(value) == "boolean" then
            active = value
        end
    end
    if active == true then return true end

    local auraInstanceID = frame.auraInstanceID
    if IsSecret(auraInstanceID) then
        return true
    end
    if type(auraInstanceID) == "number" and auraInstanceID ~= 0 then return true end

    local wasSetFromAura = frame.wasSetFromAura
    if not IsSecret(wasSetFromAura) and wasSetFromAura == true then return true end

    if type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and not IsSecret(shown) and shown == true then return true end
    end
    return false
end

local function RestoreSuppressedRegion(pair, regionKey, alphaKey, suppressedKey, guardKey)
    if not pair[suppressedKey] then return end
    local region = pair[regionKey]
    SetRegionAlpha(region, pair[alphaKey] or 1, guardKey)
    pair[alphaKey] = nil
    pair[suppressedKey] = nil
end

local function SetBaseVisualSuppressed(pair, active)
    local cooldown = pair.baseCooldown
    local applications = pair.baseApplications

    if active then
        if cooldown and not pair.baseCooldownSuppressed then
            pair.baseCooldownRestoreAlpha = GetSafeAlpha(cooldown, 1)
            pair.baseCooldownSuppressed = true
        end
        if applications and not pair.baseApplicationsSuppressed then
            pair.baseApplicationsRestoreAlpha = GetSafeAlpha(applications, 1)
            pair.baseApplicationsSuppressed = true
        end
        SetRegionAlpha(cooldown, 0, "_ddNativeTrinketAlphaGuard")
        SetRegionAlpha(applications, 0, "_ddNativeTrinketAlphaGuard")
        return
    end

    RestoreSuppressedRegion(
        pair,
        "baseCooldown",
        "baseCooldownRestoreAlpha",
        "baseCooldownSuppressed",
        "_ddNativeTrinketAlphaGuard"
    )
    RestoreSuppressedRegion(
        pair,
        "baseApplications",
        "baseApplicationsRestoreAlpha",
        "baseApplicationsSuppressed",
        "_ddNativeTrinketAlphaGuard"
    )
end

local function ApplyPairState(pair)
    if not pair or pairByBaseFrame[pair.baseFrame] ~= pair then return end

    local previousActive = pair.active
    local activeEffect
    for _, effect in ipairs(pair.effects or {}) do
        local procFrame = effect.frame
        local active = pairByProcFrame[procFrame] == pair and ReadProcActive(procFrame)
        effect.active = active
        procFrame._ddNativeTrinketActive = active and true or nil
        if active and not effect.visualActive and procFrame._ddTexSnapHooked then
            local icon = procFrame.icon or procFrame.Icon
            if icon then
                if icon.SetDesaturated then pcall(icon.SetDesaturated, icon, false) end
                if icon.SetDesaturation then pcall(icon.SetDesaturation, icon, 0) end
            end
            local visualApplied = false
            local cooldown = effect.cooldown or GetCooldown(procFrame)
            if cooldown and cooldown.GetSwipeColor and cooldown.SetSwipeColor then
                local ok, r, g, b, a = pcall(cooldown.GetSwipeColor, cooldown)
                if ok then
                    visualApplied = pcall(cooldown.SetSwipeColor, cooldown, r, g, b, a)
                end
            end
            effect.visualActive = visualApplied and true or nil
        elseif not active then
            effect.visualActive = nil
        end
        if active and not activeEffect then
            activeEffect = effect
        end
    end

    pair.active = activeEffect ~= nil
    pair.activeProcFrame = activeEffect and activeEffect.frame or nil
    SetBaseVisualSuppressed(pair, pair.active)

    local baseShown = pair.baseFrame.IsShown and pair.baseFrame:IsShown()
    local baseAlpha = baseShown and GetSafeAlpha(pair.baseFrame, 1) or 0
    for _, effect in ipairs(pair.effects or {}) do
        local procFrame = effect.frame
        if not (procFrame.IsForbidden and procFrame:IsForbidden()) then
            local procAlpha = effect == activeEffect and baseAlpha or 0
            SetRegionAlpha(procFrame, procAlpha, "_ddNativeTrinketAlphaGuard")
        end
    end

    if pair.visibilityDependsOnEffect and previousActive ~= pair.active
        and (previousActive ~= nil or pair.active)
    then
        local bridge = DDingUI.DynamicIconBridge
        if bridge and bridge.NotifyIconsChanged then
            bridge:NotifyIconsChanged(true)
        end
    end
end

local function RefreshAllStates()
    stateRefreshQueued = false
    for _, pair in pairs(pairsBySlot) do
        ApplyPairState(pair)
    end
end

local function QueueStateRefresh()
    if stateRefreshQueued then return end
    stateRefreshQueued = true
    C_Timer.After(0, RefreshAllStates)
end

local function HookProcFrame(procFrame, procCooldown)
    if not procFrame then return end

    if not procFrame._ddNativeTrinketOverlayHooked then
        procFrame:HookScript("OnShow", QueueStateRefresh)
        procFrame:HookScript("OnHide", QueueStateRefresh)
        hooksecurefunc(procFrame, "SetAlpha", function(self)
            if self._ddNativeTrinketAlphaGuard then return end
            if pairByProcFrame[self] then QueueStateRefresh() end
        end)
        if type(procFrame.OnActiveStateChanged) == "function" then
            pcall(hooksecurefunc, procFrame, "OnActiveStateChanged", QueueStateRefresh)
        end
        if type(procFrame.TriggerAuraAppliedAlert) == "function" then
            pcall(hooksecurefunc, procFrame, "TriggerAuraAppliedAlert", QueueStateRefresh)
        end
        procFrame._ddNativeTrinketOverlayHooked = true
    end

    if procCooldown and not procCooldown._ddNativeTrinketOverlayHooked then
        procCooldown:HookScript("OnShow", QueueStateRefresh)
        procCooldown:HookScript("OnHide", QueueStateRefresh)
        procCooldown._ddNativeTrinketOverlayHooked = true
    end
end

local function HookNativeCooldownShadow(frame)
    if not frame or frame._ddNativeTrinketShadowHooked then return end
    frame:HookScript("OnShow", function(self)
        if pairByNativeCooldownFrame[self] then
            SetRegionAlpha(self, 0, "_ddNativeTrinketAlphaGuard")
        end
    end)
    hooksecurefunc(frame, "SetAlpha", function(self)
        if self._ddNativeTrinketAlphaGuard then return end
        if pairByNativeCooldownFrame[self] then
            SetRegionAlpha(self, 0, "_ddNativeTrinketAlphaGuard")
        end
    end)
    frame._ddNativeTrinketShadowHooked = true
end

local function HookPairFrames(pair)
    local baseFrame = pair.baseFrame
    for _, effect in ipairs(pair.effects or {}) do
        HookProcFrame(effect.frame, effect.cooldown)
    end

    if not baseFrame._ddNativeTrinketOverlayHooked then
        baseFrame:HookScript("OnShow", QueueStateRefresh)
        baseFrame:HookScript("OnHide", QueueStateRefresh)
        hooksecurefunc(baseFrame, "SetAlpha", function(self)
            if self._ddNativeTrinketAlphaGuard then return end
            if pairByBaseFrame[self] then QueueStateRefresh() end
        end)
        baseFrame._ddNativeTrinketOverlayHooked = true
    end

    local baseCooldown = pair.baseCooldown
    if baseCooldown and not baseCooldown._ddNativeTrinketOverlayHooked then
        hooksecurefunc(baseCooldown, "SetAlpha", function(self, alpha)
            if self._ddNativeTrinketAlphaGuard then return end
            local currentPair = pairByBaseFrame[baseFrame]
            if not currentPair or not currentPair.active then return end
            if IsPublicNumber(alpha) and alpha > 0 then
                currentPair.baseCooldownRestoreAlpha = alpha
            end
            SetRegionAlpha(self, 0, "_ddNativeTrinketAlphaGuard")
        end)
        baseCooldown._ddNativeTrinketOverlayHooked = true
    end
end

local function GetEquipmentIdentity(frame, expectedCategory, categoryLookup)
    if not frame or not CDMCompat then return nil end
    local cooldownID = CDMCompat:GetFrameCooldownID(frame)
    if not IsPublicNumber(cooldownID) then return nil end
    if type(categoryLookup) == "table" and not categoryLookup[cooldownID] then
        return nil
    end

    local info
    if type(categoryLookup) == "table" then
        info = CDMCompat:GetCooldownInfo(cooldownID, true)
    else
        info = CDMCompat:GetFrameCooldownInfo(frame)
        local frameSlot = type(info) == "table" and info.equipSlot
        if IsPublicNumber(frameSlot) and IsTrackedSlot(frameSlot) then
            info = CDMCompat:GetCooldownInfo(cooldownID, true) or info
        end
    end
    if type(info) ~= "table" then return nil end

    local category = info.category
    local equipSlot = info.equipSlot
    if not IsPublicNumber(category) or not IsPublicNumber(equipSlot)
        or category ~= expectedCategory or not IsTrackedSlot(equipSlot)
    then
        return nil
    end

    return equipSlot, cooldownID, info
end

local function CandidateWins(candidate, candidateID, current, currentID)
    if not current then return true end
    local candidateShown = candidate.IsShown and candidate:IsShown() or false
    local currentShown = current.IsShown and current:IsShown() or false
    if candidateShown ~= currentShown then return candidateShown end
    if IsPublicNumber(candidateID) and IsPublicNumber(currentID) then
        return candidateID < currentID
    end
    return false
end

local function DynamicBaseWins(candidate, current)
    if not current then return true end
    if candidate.priority ~= current.priority then
        return candidate.priority > current.priority
    end
    local candidateManaged = candidate.frame._ddIsManaged == true
    local currentManaged = current.frame._ddIsManaged == true
    if candidateManaged ~= currentManaged then return candidateManaged end
    local candidateShown = candidate.frame.IsShown and candidate.frame:IsShown() or false
    local currentShown = current.frame.IsShown and current.frame:IsShown() or false
    if candidateShown ~= currentShown then return candidateShown end
    return tostring(candidate.iconKey) < tostring(current.iconKey)
end

local function BuildAssignedDynamicIconLookup(db)
    local assigned = {}
    local linkedGroupCount = 0
    local profile = DDingUI.db and DDingUI.db.profile
    local groupSystem = profile and profile.groupSystem

    for _, groupSettings in pairs((groupSystem and groupSystem.groups) or {}) do
        local sourceGroupKey = type(groupSettings) == "table" and groupSettings.sourceGroupKey
        if groupSettings.enabled ~= false and type(sourceGroupKey) == "string" then
            linkedGroupCount = linkedGroupCount + 1
            local sourceGroup = db.groups and db.groups[sourceGroupKey]
            for _, iconKey in ipairs((sourceGroup and sourceGroup.icons) or {}) do
                assigned[iconKey] = true
            end
        end
    end

    return assigned, linkedGroupCount > 0
end

local function CollectDynamicBases(result)
    local customIcons = DDingUI.CustomIcons
    if not customIcons or not customIcons.GetAllIconFrames or not customIcons.GetDynamicDB then return end
    local iconFrames = customIcons:GetAllIconFrames()
    local db = customIcons.GetDynamicDB()
    if type(iconFrames) ~= "table" or type(db) ~= "table" or type(db.iconData) ~= "table" then return end
    local assignedIconKeys, hasLinkedGroups = BuildAssignedDynamicIconLookup(db)

    for iconKey, iconData in pairs(db.iconData) do
        local slotID = iconData and iconData.slotID
        local iconType = iconData and iconData.type
        local settings = iconData and iconData.settings
        if iconType == "item" and settings and settings.trackTrinketEffect == true then
            local itemID = tonumber(iconData.id)
            for _, equippedSlot in ipairs({ 13, 14 }) do
                local equippedItemID = GetInventoryItemID
                    and GetInventoryItemID("player", equippedSlot)
                if IsPublicNumber(itemID) and IsPublicNumber(equippedItemID)
                    and itemID == equippedItemID
                then
                    slotID = equippedSlot
                    break
                end
            end
        end
        local tracksEffect = iconType == "trinketProc"
            or ((iconType == "slot" or iconType == "item") and settings
                and settings.trackTrinketEffect == true)
        local frame = tracksEffect and IsTrackedSlot(slotID) and iconFrames[iconKey]
        local isAssigned = frame and (frame._ddIsManaged == true or assignedIconKeys[iconKey] == true)
        local isVisibleFallback = frame and not hasLinkedGroups
            and frame.IsShown and frame:IsShown()
        if frame and (isAssigned or isVisibleFallback) then
            local candidate = {
                frame = frame,
                iconKey = iconKey,
                iconData = iconData,
                iconSettings = settings,
                slotID = slotID,
                priority = iconType == "trinketProc" and 3
                    or iconType == "slot" and 2 or 1,
                usesDynamicBase = true,
                visibilityDependsOnEffect = iconType == "trinketProc" and settings
                    and settings.showItemCooldown == false,
            }
            if DynamicBaseWins(candidate, result[slotID]) then
                result[slotID] = candidate
            end
        end
    end
end

local function BuildPairSignature()
    local signature = {}
    for _, slotID in ipairs({ 13, 14 }) do
        if nativeEffectSlots[slotID] then
            signature[#signature + 1] = "native"
            signature[#signature + 1] = tostring(slotID)
        end
        local pair = pairsBySlot[slotID]
        if pair then
            signature[#signature + 1] = tostring(slotID)
            signature[#signature + 1] = tostring(pair.baseFrame)
            signature[#signature + 1] = tostring(pair.nativeCooldownFrame)
            for _, effect in ipairs(pair.effects or {}) do
                signature[#signature + 1] = tostring(effect.cooldownID)
                signature[#signature + 1] = tostring(effect.frame)
            end
        end
    end
    return table.concat(signature, ":")
end

local function RefreshLegacyRegistrationIfChanged()
    local signature = BuildPairSignature()
    if signature == legacyPairSignature then return end
    legacyPairSignature = signature

    if DDingUI.InvalidateGroupCDMIconEntryCache then
        DDingUI.InvalidateGroupCDMIconEntryCache()
    end
    local registryModule = DDingUI.TrinketEffects
    if registryModule and registryModule.RefreshEventRegistration then
        registryModule:RefreshEventRegistration()
    end
end

local function CollectCandidates(registry, viewerName, expectedKind, result)
    local categoryName = expectedKind == "cooldown" and "EquipSlotEssential" or "EquipSlotTracked"
    local expectedCategory = CDMCompat:GetCategory(categoryName)
    local categoryLookup = expectedCategory and CDMCompat:GetCategoryLookup(expectedCategory, true)
    if not IsPublicNumber(expectedCategory) then return end
    if type(categoryLookup) == "table" and next(categoryLookup) == nil then
        categoryLookup = nil
    end

    for cooldownID, frame in pairs(registry:GetFrames(viewerName) or {}) do
        local slotID, resolvedCooldownID, info = GetEquipmentIdentity(
            frame,
            expectedCategory,
            categoryLookup
        )
        if slotID then
            local resolvedID = resolvedCooldownID or cooldownID
            if expectedKind == "effect" then
                local effects = result[slotID]
                if not effects then
                    effects = {}
                    result[slotID] = effects
                end
                effects[#effects + 1] = {
                    frame = frame,
                    cooldownID = resolvedID,
                    info = info,
                    cooldown = GetCooldown(frame),
                }
            else
                local current = result[slotID]
                if CandidateWins(frame, resolvedID, current and current.frame, current and current.cooldownID) then
                    result[slotID] = {
                        frame = frame,
                        cooldownID = resolvedID,
                        info = info,
                    }
                end
            end
        end
    end

    if expectedKind == "effect" then
        for _, effects in pairs(result) do
            table.sort(effects, function(a, b)
                if IsPublicNumber(a.cooldownID) and IsPublicNumber(b.cooldownID) then
                    return a.cooldownID < b.cooldownID
                end
                return tostring(a.frame) < tostring(b.frame)
            end)
        end
    end
end

local function SameEffectFrames(previousEffects, nextEffects)
    if type(previousEffects) ~= "table" or type(nextEffects) ~= "table"
        or #previousEffects ~= #nextEffects
    then
        return false
    end
    for index, effect in ipairs(previousEffects) do
        if effect.frame ~= nextEffects[index].frame then return false end
    end
    return true
end

local function UpdatePairSources(pair, base, effects)
    local baseCooldown = GetCooldown(base.frame)
    local baseApplications = GetApplications(base.frame)
    if pair.baseCooldown ~= baseCooldown or pair.baseApplications ~= baseApplications then
        SetBaseVisualSuppressed(pair, false)
    end
    pair.baseCooldownID = base.cooldownID
    pair.baseInfo = base.info
    pair.baseCooldown = baseCooldown
    pair.baseApplications = baseApplications
    pair.nativeCooldownFrame = base.nativeCooldownFrame
    pair.nativeCooldownID = base.nativeCooldownID
    pair.iconKey = base.iconKey
    pair.iconData = base.iconData
    pair.iconSettings = base.iconSettings
    pair.usesDynamicBase = base.usesDynamicBase == true
    pair.visibilityDependsOnEffect = base.visibilityDependsOnEffect == true
    for index, source in ipairs(effects) do
        local effect = pair.effects[index]
        effect.cooldownID = source.cooldownID
        effect.info = source.info
        effect.cooldown = source.cooldown
    end
end

local function DetachPair(pair)
    if not pair then return end
    SetBaseVisualSuppressed(pair, false)
    pairByBaseFrame[pair.baseFrame] = nil

    local nativeCooldownFrame = pair.nativeCooldownFrame
    if nativeCooldownFrame and nativeCooldownFrame ~= pair.baseFrame then
        pairByNativeCooldownFrame[nativeCooldownFrame] = nil
        nativeCooldownFrame._ddNativeTrinketOverlay = nil
        nativeCooldownFrame._ddNativeTrinketBase = nil
        if not (nativeCooldownFrame.IsForbidden and nativeCooldownFrame:IsForbidden()) then
            SetRegionAlpha(nativeCooldownFrame, 1, "_ddNativeTrinketAlphaGuard")
        end
    end

    local controller = DDingUI.FrameController
    local inCombat = InCombatLockdown and InCombatLockdown()
    for _, effect in ipairs(pair.effects or {}) do
        local procFrame = effect.frame
        pairByProcFrame[procFrame] = nil
        procFrame._ddNativeTrinketOverlay = nil
        procFrame._ddNativeTrinketActive = nil
        procFrame._ddNativeTrinketBase = nil
        if inCombat then
            pair.pendingDetach = true
            if not (procFrame.IsForbidden and procFrame:IsForbidden()) then
                SetRegionAlpha(procFrame, 0, "_ddNativeTrinketAlphaGuard")
            end
        elseif effect.anchored and controller and controller.ReleaseFrameFromContainer then
            controller:ReleaseFrameFromContainer(procFrame)
        end
    end
end

local function UpdateEventRegistration(hasPairs)
    if hasPairs and not eventFrame._ddNativeTrinketRegistered then
        eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame._ddNativeTrinketRegistered = true
    elseif not hasPairs and eventFrame._ddNativeTrinketRegistered then
        eventFrame:UnregisterAllEvents()
        eventFrame._ddNativeTrinketRegistered = nil
    end
end

function NativeTrinketOverlay:RefreshPairs(registry)
    if not registry then
        local retained = 0
        for _ in pairs(pairsBySlot) do retained = retained + 1 end
        return retained
    end

    if not IsIntegrationEnabled() then
        if InCombatLockdown and InCombatLockdown() then
            local retained = 0
            for _ in pairs(pairsBySlot) do retained = retained + 1 end
            return retained
        end
        for slotID, pair in pairs(pairsBySlot) do
            DetachPair(pair)
            pairsBySlot[slotID] = nil
        end
        pairByProcFrame = setmetatable({}, { __mode = "k" })
        pairByBaseFrame = setmetatable({}, { __mode = "k" })
        pairByNativeCooldownFrame = setmetatable({}, { __mode = "k" })
        hiddenCatalogCooldownIDs = {}
        nativeEffectSlots = {}
        pairMissingScans = {}
        effectMissingScans = {}
        UpdateEventRegistration(false)
        RefreshLegacyRegistrationIfChanged()
        return 0
    end

    local cooldowns = {}
    local effects = {}
    local dynamicBases = {}
    local inCombat = InCombatLockdown and InCombatLockdown()
    CollectCandidates(registry, "EssentialCooldownViewer", "cooldown", cooldowns)
    CollectCandidates(registry, "BuffIconCooldownViewer", "effect", effects)
    CollectDynamicBases(dynamicBases)

    local nextNativeEffectSlots = {}
    for slotID, slotEffects in pairs(effects) do
        if #slotEffects > 0 then
            nextNativeEffectSlots[slotID] = true
        end
    end
    for _, slotID in ipairs({ 13, 14 }) do
        if nextNativeEffectSlots[slotID] then
            effectMissingScans[slotID] = 0
        elseif nativeEffectSlots[slotID] then
            local misses = (effectMissingScans[slotID] or 0) + 1
            effectMissingScans[slotID] = misses
            if inCombat or misses <= SCAN_MISS_GRACE then
                nextNativeEffectSlots[slotID] = true
            end
        else
            effectMissingScans[slotID] = 0
        end
    end
    nativeEffectSlots = nextNativeEffectSlots

    for slotID, dynamicBase in pairs(dynamicBases) do
        local nativeBase = cooldowns[slotID]
        if effects[slotID] and #effects[slotID] > 0 then
            if nativeBase then
                dynamicBase.nativeCooldownFrame = nativeBase.frame
                dynamicBase.nativeCooldownID = nativeBase.cooldownID
            end
            cooldowns[slotID] = dynamicBase
        end
    end

    local nextPairs = {}
    for slotID, base in pairs(cooldowns) do
        local slotEffects = effects[slotID]
        if slotEffects and #slotEffects > 0 then
            local previous = pairsBySlot[slotID]
            local pair = previous
            if not pair or pair.baseFrame ~= base.frame
                or pair.nativeCooldownFrame ~= base.nativeCooldownFrame
                or not SameEffectFrames(pair.effects, slotEffects)
            then
                pair = {
                    slotID = slotID,
                    baseFrame = base.frame,
                    baseCooldownID = base.cooldownID,
                    baseInfo = base.info,
                    baseCooldown = GetCooldown(base.frame),
                    baseApplications = GetApplications(base.frame),
                    nativeCooldownFrame = base.nativeCooldownFrame,
                    nativeCooldownID = base.nativeCooldownID,
                    iconKey = base.iconKey,
                    iconData = base.iconData,
                    iconSettings = base.iconSettings,
                    usesDynamicBase = base.usesDynamicBase == true,
                    visibilityDependsOnEffect = base.visibilityDependsOnEffect == true,
                    effects = slotEffects,
                }
            else
                UpdatePairSources(pair, base, slotEffects)
            end
            nextPairs[slotID] = pair
            pairMissingScans[slotID] = 0
        end
    end

    for slotID, pair in pairs(pairsBySlot) do
        local replacement = nextPairs[slotID]
        if replacement then
            pairMissingScans[slotID] = 0
            if inCombat and (replacement.baseFrame ~= pair.baseFrame
                or replacement.nativeCooldownFrame ~= pair.nativeCooldownFrame
                or not SameEffectFrames(replacement.effects, pair.effects))
            then
                nextPairs[slotID] = pair
            end
        else
            local misses = (pairMissingScans[slotID] or 0) + 1
            pairMissingScans[slotID] = misses
            if inCombat or misses <= SCAN_MISS_GRACE then
                nextPairs[slotID] = pair
            end
        end
    end

    for slotID, pair in pairs(pairsBySlot) do
        if nextPairs[slotID] ~= pair then
            DetachPair(pair)
        end
    end

    pairsBySlot = nextPairs
    pairByProcFrame = setmetatable({}, { __mode = "k" })
    pairByBaseFrame = setmetatable({}, { __mode = "k" })
    pairByNativeCooldownFrame = setmetatable({}, { __mode = "k" })
    hiddenCatalogCooldownIDs = {}

    local count = 0
    for _, pair in pairs(pairsBySlot) do
        count = count + 1
        pairByBaseFrame[pair.baseFrame] = pair
        if pair.nativeCooldownFrame and pair.nativeCooldownFrame ~= pair.baseFrame then
            pairByNativeCooldownFrame[pair.nativeCooldownFrame] = pair
            pair.nativeCooldownFrame._ddNativeTrinketOverlay = true
            pair.nativeCooldownFrame._ddNativeTrinketBase = pair.baseFrame
            HookNativeCooldownShadow(pair.nativeCooldownFrame)
            if IsPublicNumber(pair.nativeCooldownID) then
                hiddenCatalogCooldownIDs[pair.nativeCooldownID] = true
            end
        end
        for _, effect in ipairs(pair.effects or {}) do
            pairByProcFrame[effect.frame] = pair
            effect.frame._ddNativeTrinketOverlay = true
            effect.frame._ddNativeTrinketBase = pair.baseFrame
            if IsPublicNumber(effect.cooldownID) then
                hiddenCatalogCooldownIDs[effect.cooldownID] = true
            end
        end
        HookPairFrames(pair)
    end

    UpdateEventRegistration(count > 0)
    QueueStateRefresh()
    RefreshLegacyRegistrationIfChanged()
    return count
end

local GLOW_TYPE_MAP = {
    button = "Action Button Glow",
    pixel = "Pixel Glow",
    autocast = "Autocast Shine",
    proc = "Proc Glow",
    blizzard = "Blizzard Glow",
}

local function CopySettings(settings)
    local copy = {}
    for key, value in pairs(settings or {}) do
        copy[key] = value
    end
    return copy
end

local function ResolveIconGlowColor(custom, fallback)
    local mode = custom and custom.glowColorMode
    if mode == "custom" and type(custom.glowColor) == "table" then
        return custom.glowColor
    end
    if mode == "class" then
        local _, classFile = UnitClass("player")
        local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if classColor then
            return { classColor.r, classColor.g, classColor.b, classColor.a or 1 }
        end
    elseif mode == "blizzard" then
        return { 1, 0.82, 0.28, 1 }
    end
    return fallback or { 1, 0.85, 0.1, 1 }
end

local function BuildEffectSettings(pair, groupSettings)
    groupSettings = type(groupSettings) == "table" and groupSettings or {}
    local settings = CopySettings(groupSettings)
    settings.auraGlow = groupSettings.procGlowEnabled ~= false
    settings.auraGlowType = groupSettings.procGlowType
        or groupSettings.auraGlowType
        or "Pixel Glow"
    settings.auraGlowColor = groupSettings.procGlowColor
        or groupSettings.auraGlowColor
        or { 0.95, 0.95, 0.32, 1 }
    settings.auraGlowPixelLines = groupSettings.procGlowPixelLines
        or groupSettings.auraGlowPixelLines
    settings.auraGlowPixelFrequency = groupSettings.procGlowPixelFrequency
        or groupSettings.auraGlowPixelFrequency
    settings.auraGlowPixelThickness = groupSettings.procGlowPixelThickness
        or groupSettings.auraGlowPixelThickness
    settings.auraGlowAutocastFrequency = groupSettings.procGlowAutocastFrequency
        or groupSettings.auraGlowAutocastFrequency
    settings.auraGlowButtonFrequency = groupSettings.procGlowButtonFrequency
        or groupSettings.auraGlowButtonFrequency

    local iconSettings = pair and pair.iconSettings
    local custom = iconSettings and iconSettings.customStateGlow
    if type(custom) ~= "table" then return settings end

    local mode = custom.procGlowMode
    local hasStyle = custom.glowType ~= nil
        or custom.glowColorMode ~= nil
        or custom.glowColor ~= nil
        or custom.glowLines ~= nil
        or custom.glowSpeed ~= nil
        or custom.glowThickness ~= nil
    if mode ~= "on" and mode ~= "off" and not hasStyle then
        return settings
    end

    if mode == "on" then
        settings.auraGlow = true
        settings.auraGlowType = GLOW_TYPE_MAP[custom.glowType or "button"]
            or settings.auraGlowType
            or "Action Button Glow"
    elseif mode == "off" then
        settings.auraGlow = false
    elseif custom.glowType then
        settings.auraGlowType = GLOW_TYPE_MAP[custom.glowType] or settings.auraGlowType
    end

    if mode ~= "off" then
        settings.auraGlowColor = ResolveIconGlowColor(custom, settings.auraGlowColor)
        settings.auraGlowPixelLines = custom.glowLines or settings.auraGlowPixelLines
        settings.auraGlowPixelFrequency = custom.glowSpeed or settings.auraGlowPixelFrequency
        settings.auraGlowPixelThickness = custom.glowThickness or settings.auraGlowPixelThickness
        settings.auraGlowAutocastFrequency = custom.glowSpeed or settings.auraGlowAutocastFrequency
        settings.auraGlowButtonFrequency = custom.glowSpeed or settings.auraGlowButtonFrequency
    end
    return settings
end

local function ColorSignature(color)
    if type(color) ~= "table" then return "-" end
    return table.concat({
        tostring(color[1] or color.r),
        tostring(color[2] or color.g),
        tostring(color[3] or color.b),
        tostring(color[4] or color.a),
    }, ",")
end

local function BuildStyleKey(container, settings, width, height)
    settings = type(settings) == "table" and settings or {}
    return table.concat({
        tostring(container and container._lastCombinedLayoutHash or "-"),
        tostring(width),
        tostring(height),
        tostring(settings.zoom),
        tostring(settings.borderSize),
        tostring(settings.durationTextSize),
        tostring(settings.durationTextAnchor),
        tostring(settings.durationTextOffsetX),
        tostring(settings.durationTextOffsetY),
        tostring(settings.countTextSize),
        tostring(settings.countTextAnchor),
        tostring(settings.countTextOffsetX),
        tostring(settings.countTextOffsetY),
        tostring(settings.auraGlow),
        tostring(settings.auraGlowType),
        ColorSignature(settings.auraGlowColor),
        tostring(settings.auraGlowPixelLines),
        tostring(settings.auraGlowPixelFrequency),
        tostring(settings.auraGlowPixelThickness),
        tostring(settings.auraGlowAutocastFrequency),
        tostring(settings.auraGlowButtonFrequency),
    }, ":")
end

local function ApplyEffectPlacement(pair, effect, baseFrame, width, height)
    local procFrame = effect.frame
    if procFrame.IsForbidden and procFrame:IsForbidden() then
        return
    end

    local controller = DDingUI.FrameController
    local needsAnchor = not effect.anchored
        or procFrame._ddContainerRef ~= baseFrame
        or effect.width ~= width
        or effect.height ~= height

    if needsAnchor and not (InCombatLockdown and InCombatLockdown())
        and controller and controller.SetupFrameInContainer
    then
        controller:SetupFrameInContainer(procFrame, baseFrame, width, height, effect.cooldownID)
        if procFrame._ddContainerRef == baseFrame then
            procFrame._ddTargetPoint = "CENTER"
            procFrame._ddTargetRelPoint = "CENTER"
            procFrame._ddTargetX = 0
            procFrame._ddTargetY = 0
            procFrame._ddSettingPosition = true
            procFrame:ClearAllPoints()
            procFrame:SetPoint("CENTER", baseFrame, "CENTER", 0, 0)
            procFrame._ddSettingPosition = false
            procFrame._ddLayoutVisible = true
            effect.anchored = true
            effect.width = width
            effect.height = height
        end
    end

    if effect.anchored then
        local container = baseFrame._ddContainerRef
        local settings = BuildEffectSettings(pair, container and container._groupSettings)
        local styleKey = BuildStyleKey(container, settings, width, height)
        if effect.styleKey ~= styleKey and DDingUI.IconViewers and DDingUI.IconViewers.SkinIcon then
            DDingUI.IconViewers:SkinIcon(procFrame, settings or {})
            effect.styleKey = styleKey
        end
    end
end

local function ApplyNativeCooldownShadow(pair)
    local frame = pair.nativeCooldownFrame
    if not frame or frame == pair.baseFrame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    if not (InCombatLockdown and InCombatLockdown()) and frame._ddIsManaged then
        local controller = DDingUI.FrameController
        if controller and controller.ReleaseFrameFromContainer then
            controller:ReleaseFrameFromContainer(frame)
        end
    end
    SetRegionAlpha(frame, 0, "_ddNativeTrinketAlphaGuard")
end

local function ApplyPairPlacement(pair)
    local baseFrame = pair.baseFrame
    ApplyNativeCooldownShadow(pair)
    if not baseFrame._ddIsManaged or not baseFrame._ddContainerRef then
        ApplyPairState(pair)
        return
    end

    local width = baseFrame:GetWidth()
    local height = baseFrame:GetHeight()
    if not IsPublicNumber(width) or not IsPublicNumber(height) or width <= 0 or height <= 0 then
        return
    end

    for _, effect in ipairs(pair.effects or {}) do
        ApplyEffectPlacement(pair, effect, baseFrame, width, height)
    end

    ApplyPairState(pair)
end

function NativeTrinketOverlay:ApplyAll()
    for _, pair in pairs(pairsBySlot) do
        ApplyPairPlacement(pair)
    end
end

function NativeTrinketOverlay:IsOverlayFrame(frame)
    return pairByProcFrame[frame] ~= nil or pairByNativeCooldownFrame[frame] ~= nil
end

function NativeTrinketOverlay:GetPairForSlot(slotID)
    return pairsBySlot[slotID]
end

function NativeTrinketOverlay:OwnsBaseFrame(frame, slotID)
    local pair = pairsBySlot[slotID]
    return pair ~= nil and pair.baseFrame == frame
end

function NativeTrinketOverlay:IsSlotEffectActive(slotID)
    local pair = pairsBySlot[slotID]
    return pair ~= nil and pair.active == true
end

function NativeTrinketOverlay:ShouldHideCatalogCooldown(cooldownID)
    return IsPublicNumber(cooldownID) and hiddenCatalogCooldownIDs[cooldownID] == true
end

function NativeTrinketOverlay:HasNativeEffectForItem(itemID)
    if not IsPublicNumber(itemID) then return false end
    for slotID in pairs(nativeEffectSlots) do
        local equippedItemID = GetInventoryItemID and GetInventoryItemID("player", slotID)
        if IsPublicNumber(equippedItemID) and equippedItemID == itemID then
            return true
        end
    end
    return false
end

function NativeTrinketOverlay:HasNativeEffectForSlot(slotID)
    return IsTrackedSlot(slotID) and nativeEffectSlots[slotID] == true
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "UNIT_AURA" then
        QueueStateRefresh()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        NativeTrinketOverlay:ApplyAll()
    end
end)
