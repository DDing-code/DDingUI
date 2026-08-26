local _, ns = ...
local DDingUI = ns and ns.Addon
if not DDingUI then return end

local IconDiagnostics = {
    historyByKey = {},
    historyKeyOrder = {},
    maxHistoryPerIcon = 8,
    maxHistoryKeys = 256,
}
DDingUI.IconDiagnostics = IconDiagnostics

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function SafeNumber(value)
    if IsSecret(value) then return nil end
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

local function SafeText(value)
    if IsSecret(value) then return nil end
    local valueType = type(value)
    if valueType == "string" then return value end
    if valueType == "number" or valueType == "boolean" then return tostring(value) end
    return nil
end

local function SafeBoolean(value)
    if IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function SafeFrameCall(frame, methodName)
    if not frame then return nil end
    local method = frame[methodName]
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, frame)
    if not ok or IsSecret(value) then return nil end
    return value
end

local function CountEntries(value)
    if type(value) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function ContainsValue(list, target)
    if type(list) ~= "table" or target == nil then return false end
    for _, value in ipairs(list) do
        if value == target then return true end
    end
    return false
end

local function GetFrameGroupName(frame)
    if not frame then return nil end
    local groupName = SafeText(frame._ddGroupName)
    if groupName then return groupName end
    local container = frame._ddContainerRef
    return container and SafeText(container._groupName) or nil
end

local function GetFrameHistoryKey(frame)
    if not frame then return nil end
    local iconKey = SafeText(frame._ddIconKey)
    if iconKey then return "dynamic:" .. iconKey end

    local cooldownID = SafeNumber(frame._ddLayoutCooldownID)
        or SafeNumber(frame._ddLastCooldownID)
        or SafeNumber(frame.cooldownID)
    if cooldownID then return "cdm:" .. tostring(cooldownID) end
    return nil
end

local function GetQueryHistoryKey(query, resolvedCooldownID)
    if not query then return nil end
    if query.kind == "dynamic" then
        local iconKey = SafeText(query.iconKey)
        return iconKey and ("dynamic:" .. iconKey) or nil
    end
    local cooldownID = SafeNumber(resolvedCooldownID) or SafeNumber(query.cooldownID)
    return cooldownID and ("cdm:" .. tostring(cooldownID)) or nil
end

local function ResolveTransitionReason(frame, visible)
    if visible then
        if SafeBoolean(frame._ddInactiveGray) == true then return "inactive_gray" end
        if SafeBoolean(frame._ddInactivePlaceholder) == true then return "inactive_placeholder" end
        if SafeBoolean(frame._ddCombatKeepAlive) == true then return "combat_keep_alive" end
        return "layout_included"
    end
    if SafeBoolean(frame._ddingHidden) == true then return "hidden_by_tracker" end
    if SafeBoolean(frame._ddSuppressed) == true then return "suppressed" end
    if SafeBoolean(frame._ddStateFiltered) == true then return "state_filter" end
    if SafeBoolean(frame._ddOverflowFiltered) == true then return "overflow_filter" end
    if SafeBoolean(frame._ddManagedAuraExpired) == true then return "aura_expired" end
    if SafeBoolean(frame._ddCombatVisible) == false then return "combat_inactive" end
    if frame._ddSourceViewer == "BuffIconCooldownViewer"
        and SafeBoolean(frame._ddCDMViewerShown) == false
    then
        return "source_hidden"
    end
    return "layout_excluded"
end

function IconDiagnostics:RecordFrameEvent(frame, eventType, visible, reason)
    local key = GetFrameHistoryKey(frame)
    if not key then return end

    local list = self.historyByKey[key]
    if not list then
        list = {}
        self.historyByKey[key] = list
        self.historyKeyOrder[#self.historyKeyOrder + 1] = key
        if #self.historyKeyOrder > self.maxHistoryKeys then
            local expiredKey = table.remove(self.historyKeyOrder, 1)
            self.historyByKey[expiredKey] = nil
        end
    end

    local safeVisible = SafeBoolean(visible)
    local safeReason = SafeText(reason) or "state_changed"
    local groupName = GetFrameGroupName(frame)
    local signature = table.concat({
        SafeText(eventType) or "state",
        safeVisible == nil and "unknown" or (safeVisible and "1" or "0"),
        safeReason,
        groupName or "",
    }, ":")
    local previous = list[#list]
    if previous and previous.signature == signature then return end

    list[#list + 1] = {
        time = SafeNumber(GetTime and GetTime()) or 0,
        eventType = SafeText(eventType) or "state",
        visible = safeVisible,
        reason = safeReason,
        groupName = groupName,
        signature = signature,
    }
    if #list > self.maxHistoryPerIcon then
        table.remove(list, 1)
    end
end

function IconDiagnostics:RecordLayoutTransition(frame, visible)
    self:RecordFrameEvent(frame, "layout", visible, ResolveTransitionReason(frame, visible))
end

local function ResolveDynamicFrame(iconKey)
    local customIcons = DDingUI.CustomIcons
    local frames = customIcons and customIcons.GetAllIconFrames and customIcons:GetAllIconFrames()
    return type(frames) == "table" and frames[iconKey] or nil
end

local function NormalizeSpellName(value)
    local name = SafeText(value)
    return name and name:gsub("^buff_", "") or nil
end

local function ResolveCDMFrame(query)
    local controller = DDingUI.FrameController or DDingUI.CDMHookEngine
    if not controller then return nil, SafeNumber(query and query.cooldownID) end

    local cooldownID = SafeNumber(query and query.cooldownID)
    if cooldownID and controller.GetIconFrame then
        local frame = controller:GetIconFrame(cooldownID)
        if frame then return frame, cooldownID end
    end

    local spellID = SafeNumber(query and query.spellID)
    if spellID and controller.GetIconFrame then
        local frame = controller:GetIconFrame(spellID)
        if frame then return frame, spellID end
    end

    local targetName = NormalizeSpellName(query and query.spellName)
    local iconMap = controller.GetIconMap and controller:GetIconMap()
    if not targetName or type(iconMap) ~= "table" then return nil, cooldownID end
    for rawCooldownID, frame in pairs(iconMap) do
        local candidateID = SafeNumber(rawCooldownID)
        if candidateID then
            local candidateName = controller.GetSpellNameForID
                and NormalizeSpellName(controller:GetSpellNameForID(candidateID))
            if candidateName == targetName then
                return frame, candidateID
            end
        end
    end
    return nil, cooldownID
end

local function ReadGlowVisible(frame)
    if not frame then return nil end
    if SafeBoolean(frame._ddTrinketEffectGlowActive) == true then return true end
    for _, field in ipairs({
        "_PixelGlow_DDingUICustomGlow",
        "_AutoCastGlow_DDingUICustomGlow",
        "_ProcGlow_DDingUICustomGlow",
        "_ButtonGlow",
        "overlay",
        "SpellActivationAlert",
    }) do
        local glowFrame = frame[field]
        if SafeFrameCall(glowFrame, "IsShown") == true then return true end
    end
    return false
end

local function ReadActiveState(frame)
    if not frame then return nil, nil end
    for _, field in ipairs({
        "_ddCustomIconActive",
        "_auraWasActive",
        "_ddTotemActive",
        "_trinketProcWasActive",
        "_ddCDMActive",
        "isActive",
    }) do
        local value = SafeBoolean(frame[field])
        if value ~= nil then return value, field end
    end
    return nil, nil
end

local function BuildFrameState(frame)
    if not frame then return {} end
    local active, activeSource = ReadActiveState(frame)
    local container = frame._ddContainerRef
    return {
        frameShown = SafeBoolean(SafeFrameCall(frame, "IsShown")),
        containerShown = SafeBoolean(SafeFrameCall(container, "IsShown")),
        alpha = SafeNumber(SafeFrameCall(frame, "GetAlpha")),
        layoutVisible = SafeBoolean(frame._ddLayoutVisible),
        active = active,
        activeSource = activeSource,
        ready = SafeBoolean(frame._ddCustomIconReady),
        procActive = SafeBoolean(frame._ddCustomIconProcActive),
        glowVisible = ReadGlowVisible(frame),
        inactiveGray = SafeBoolean(frame._ddInactiveGray),
        inactivePlaceholder = SafeBoolean(frame._ddInactivePlaceholder),
        hidden = SafeBoolean(frame._ddingHidden),
        suppressed = SafeBoolean(frame._ddSuppressed),
        stateFiltered = SafeBoolean(frame._ddStateFiltered),
        overflowFiltered = SafeBoolean(frame._ddOverflowFiltered),
        managedAuraExpired = SafeBoolean(frame._ddManagedAuraExpired),
        combatVisible = SafeBoolean(frame._ddCombatVisible),
        combatKeepAlive = SafeBoolean(frame._ddCombatKeepAlive),
        sourceViewerShown = SafeBoolean(frame._ddCDMViewerShown),
        sourceViewer = SafeText(frame._ddSourceViewer),
        currentGroup = GetFrameGroupName(frame),
        lastDynamicActiveAt = SafeNumber(frame._ddLastDynamicActiveAt),
        lastAuraActiveAt = SafeNumber(frame._ddLastAuraActiveAt),
        lastProcActiveAt = SafeNumber(frame._ddLastProcActiveAt),
        activeUntil = SafeNumber(frame._ddTimedAuraActiveUntil)
            or SafeNumber(frame._ddAuraActiveUntil)
            or SafeNumber(frame._ddProcActiveUntil),
    }
end

local function ResolveDecision(frame, state, groupSettings)
    if groupSettings and groupSettings.enabled == false then return false, "group_disabled" end
    if not frame then return false, "frame_missing" end
    if state.hidden == true then return false, "hidden_by_tracker" end
    if state.suppressed == true then return false, "suppressed" end
    if state.stateFiltered == true then return false, "state_filter" end
    if state.overflowFiltered == true then return false, "overflow_filter" end
    if state.managedAuraExpired == true then return false, "aura_expired" end
    if state.combatVisible == false then return false, "combat_inactive" end
    if state.sourceViewer == "BuffIconCooldownViewer" and state.sourceViewerShown == false then
        return false, "source_hidden"
    end
    if state.layoutVisible == false then return false, "layout_excluded" end
    if state.containerShown == false then return false, "group_frame_hidden" end
    if state.alpha and state.alpha <= 0.001 then return false, "alpha_zero" end
    if state.frameShown == false then return false, "frame_hidden" end
    if state.inactiveGray == true then return true, "inactive_gray" end
    if state.inactivePlaceholder == true then return true, "inactive_placeholder" end
    return true, "eligible"
end

local function FindOrderIndex(order, tokens)
    if type(order) ~= "table" then return nil end
    for index, token in ipairs(order) do
        if ContainsValue(tokens, token) then return index end
    end
    return nil
end

local function GetCurrentSpecID()
    if not (GetSpecialization and GetSpecializationInfo) then return nil end
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    return SafeNumber(GetSpecializationInfo(specIndex))
end

local function CopyHistory(history)
    local copy = {}
    for index, entry in ipairs(history or {}) do
        copy[index] = {
            time = entry.time,
            eventType = entry.eventType,
            visible = entry.visible,
            reason = entry.reason,
            groupName = entry.groupName,
        }
    end
    return copy
end

function IconDiagnostics:Inspect(query)
    query = type(query) == "table" and query or {}
    local profile = DDingUI.db and DDingUI.db.profile
    local groupSystem = profile and profile.groupSystem
    local groupSettings = groupSystem and groupSystem.groups and groupSystem.groups[query.groupName]
    local dynamicDB = profile and profile.dynamicIcons
    local iconData
    local frame
    local resolvedCooldownID
    local individualSettings
    local identity = {}
    local membershipCount = 0
    local membershipNames = {}
    local duplicateIdentityCount = 0
    local orderTokens = {}

    if query.kind == "dynamic" then
        local iconKey = SafeText(query.iconKey)
        iconData = iconKey and dynamicDB and dynamicDB.iconData and dynamicDB.iconData[iconKey]
        frame = iconKey and ResolveDynamicFrame(iconKey) or nil
        individualSettings = type(iconData) == "table" and iconData.settings or nil
        identity.iconKey = iconKey
        identity.iconType = type(iconData) == "table" and SafeText(iconData.type)
            or SafeText(query.iconType)
        identity.spellOrItemID = type(iconData) == "table" and SafeNumber(iconData.id)
            or SafeNumber(query.itemID)
        identity.slotID = type(iconData) == "table" and SafeNumber(iconData.slotID)
            or SafeNumber(query.slotID)
        identity.totemSlot = type(iconData) == "table" and SafeNumber(iconData.totemSlot)
            or SafeNumber(query.totemSlot)

        local identityProvider = DDingUI.CustomIconIdentity
        identity.persistentID = identityProvider and identityProvider.GetPersistentID
            and identityProvider:GetPersistentID(iconData, iconKey)
            or (type(iconData) == "table" and SafeText(iconData.persistentID))
        if identity.persistentID then orderTokens[#orderTokens + 1] = "dynid:" .. identity.persistentID end
        if iconKey then orderTokens[#orderTokens + 1] = "dyn:" .. iconKey end

        for sourceKey, dynamicGroup in pairs((dynamicDB and dynamicDB.groups) or {}) do
            if type(dynamicGroup) == "table" and ContainsValue(dynamicGroup.icons, iconKey) then
                membershipCount = membershipCount + 1
                membershipNames[#membershipNames + 1] = SafeText(dynamicGroup.name) or SafeText(sourceKey) or "?"
            end
        end
        if identity.persistentID then
            for otherKey, otherData in pairs((dynamicDB and dynamicDB.iconData) or {}) do
                if otherKey ~= iconKey and type(otherData) == "table"
                    and SafeText(otherData.persistentID) == identity.persistentID
                then
                    duplicateIdentityCount = duplicateIdentityCount + 1
                end
            end
        end
    else
        frame, resolvedCooldownID = ResolveCDMFrame(query)
        identity.cooldownID = resolvedCooldownID
        identity.spellOrItemID = SafeNumber(query.spellID)
        identity.viewerType = SafeText(query.viewerType)
        local customizationDB = profile and profile.iconCustomization
        local spellSettings = customizationDB and customizationDB.spells
        if type(spellSettings) == "table" and identity.spellOrItemID then
            local baseKey = tostring(identity.spellOrItemID)
            local viewerKey = identity.viewerType and (baseKey .. "_" .. identity.viewerType)
            individualSettings = (viewerKey and spellSettings[viewerKey]) or spellSettings[baseKey]
        end
        local spellName = SafeText(query.spellName)
        if spellName then orderTokens[#orderTokens + 1] = "cdm:" .. spellName end
    end

    local state = BuildFrameState(frame)
    local visible, decisionReason = ResolveDecision(frame, state, groupSettings)
    local assignment = query.spellName and groupSystem and groupSystem.spellAssignments
        and groupSystem.spellAssignments[query.spellName]
    local sourceGroupKey = groupSettings and SafeText(groupSettings.sourceGroupKey)
    local groupOrder = groupSettings and groupSettings.iconOrder
    local historyKey = GetQueryHistoryKey(query, resolvedCooldownID)

    return {
        now = SafeNumber(GetTime and GetTime()) or 0,
        kind = query.kind == "dynamic" and "dynamic" or "cdm",
        displayName = SafeText(query.displayName) or SafeText(query.spellName) or identity.iconKey or "Unknown",
        groupName = SafeText(query.groupName),
        specID = GetCurrentSpecID(),
        frameFound = frame ~= nil,
        groupFound = groupSettings ~= nil,
        groupEnabled = groupSettings and groupSettings.enabled ~= false or false,
        sourceGroupKey = sourceGroupKey,
        assignedGroup = SafeText(assignment),
        identity = identity,
        state = state,
        decision = {
            visible = visible,
            reason = decisionReason,
        },
        settings = {
            individualOverrideCount = CountEntries(individualSettings),
            orderIndex = FindOrderIndex(groupOrder, orderTokens),
            membershipCount = membershipCount,
            membershipNames = membershipNames,
        },
        conflicts = {
            duplicateIdentityCount = duplicateIdentityCount,
            multipleMemberships = membershipCount > 1,
        },
        history = CopyHistory(historyKey and self.historyByKey[historyKey]),
    }
end
