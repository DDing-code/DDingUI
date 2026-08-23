local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Container = DDingUI.TrackedAuraContainer
if not Container then return end

local Sounds = {}
DDingUI.TrackedAuraSounds = Sounds

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local registrations = {}
local nativeDisplayByTracker = setmetatable({}, { __mode = "k" })
local nativeAlertActions = setmetatable({}, { __mode = "k" })
local pendingPlan
local pendingSignature
local sourceSignature
local registrationSignature
local diagnostics = {
    syncs = 0,
    plans = 0,
    registrations = 0,
    removals = 0,
    failures = 0,
    deferred = 0,
}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function IsValidSoundPath(path)
    if type(path) ~= "string" or path == "" then return false end
    local extension = path:lower():match("%.(%w+)$")
    return extension == "mp3" or extension == "ogg" or extension == "wav"
end

local function ResolveSound(source)
    source = source or {}
    local customPath = source.soundCustomPath
    if IsValidSoundPath(customPath) then return customPath, nil end

    local soundKey = source.soundFile
    if not soundKey or soundKey == "" or soundKey == "None" or not LSM then return nil, nil end
    local value = LSM:Fetch("sound", soundKey, true)
    if type(value) == "number" and value > 0 then return nil, value end
    if type(value) == "string" and value ~= "" then return value, nil end
    return nil, nil
end

local function TriggerEnum(name)
    local triggers = Enum and Enum.UnitAuraSoundTrigger
    return triggers and triggers[name] or nil
end

local function DisplayTrigger(tracker)
    local triggerName = tracker and tracker.settings and tracker.settings.soundTrigger or "start"
    if triggerName == "start" then return TriggerEnum("Added") end
    if triggerName == "end" then return TriggerEnum("Removed") end
    return nil
end

local function IsAutomaticAuraTracker(tracker)
    if type(tracker) ~= "table" or tracker.isGroup or tracker.enabled == false then return false end
    if tracker.isAura == false then return false end
    if tracker.trackingMode == "manual" or tracker.trackingMode == "spell" then return false end
    if tracker.trigger and tracker.trigger.type == "spell" then return false end
    return true
end

local function PassesActivation(tracker)
    local settings = tracker and tracker.settings
    local activationType = settings and settings.activationType
    if not activationType or activationType == "none" then return true end

    if activationType == "spell" then
        local spellID = tonumber(settings.activationSpellID)
            or tonumber(tracker.cooldownID) or tonumber(tracker.spellID)
        return not spellID or spellID <= 0 or not IsPlayerSpell or IsPlayerSpell(spellID)
    elseif activationType == "talent" then
        local nodeID = tonumber(settings.activationTalentID)
        if not nodeID or nodeID <= 0 then return true end
        local evaluated = false
        local learned = false
        local ok = pcall(function()
            local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID()
            local nodeInfo = configID and C_Traits and C_Traits.GetNodeInfo(configID, nodeID)
            if type(nodeInfo) ~= "table" or IsSecret(nodeInfo) then return end
            local activeRank = nodeInfo.activeRank
            if type(activeRank) ~= "number" or IsSecret(activeRank) then return end
            evaluated = true
            learned = activeRank > 0
        end)
        return not ok or not evaluated or learned
    end
    return true
end

local function BuildGroupOwners(trackers)
    local owners = {}
    for groupIndex, group in ipairs(trackers or {}) do
        if type(group) == "table" and group.isGroup then
            for _, childIndex in ipairs(group.controlledChildren or {}) do
                if type(childIndex) == "number" then
                    owners[childIndex] = groupIndex
                end
            end
        end
    end
    return owners
end

local function GroupAllowsTracker(trackers, tracker, trackerIndex, groupOwners)
    local groupIndex = groupOwners and groupOwners[trackerIndex]
        or tonumber(tracker and tracker.parentGroup)
    local group = groupIndex and trackers and trackers[groupIndex]
    if not group or not group.isGroup then return true end
    if group.disabled or group.enabled == false or not PassesActivation(group) then return false end

    local settings = group.groupSettings or {}
    local loadSpec = settings.loadSpec
    if type(loadSpec) == "table" and next(loadSpec) then
        local specIndex = GetSpecialization and GetSpecialization()
        local specID = specIndex and GetSpecializationInfo(specIndex)
        local matched = loadSpec[specIndex] or (specID and loadSpec[specID])
        if not matched then
            for _, value in pairs(loadSpec) do
                if value == specIndex or value == specID then
                    matched = true
                    break
                end
            end
        end
        if not matched then return false end
    end

    local requestedType = settings.loadInstanceType or "all"
    if requestedType ~= "all" then
        local inInstance, instanceType = IsInInstance()
        if requestedType == "world" and inInstance then return false end
        if requestedType == "dungeon"
            and instanceType ~= "party" and instanceType ~= "scenario"
        then
            return false
        end
        if requestedType == "raid" and instanceType ~= "raid" then return false end
        if requestedType == "arena"
            and instanceType ~= "arena" and instanceType ~= "pvp"
        then
            return false
        end
    end
    return true
end

local function BoolValue(value)
    if value == true or value == "true" then return true end
    if value == false or value == "false" then return false end
    return nil
end

local function ActiveTriggerEdge(trigger)
    if type(trigger) ~= "table" or trigger.type ~= "active" then return nil end
    local expected = BoolValue(trigger.value)
    if expected == nil then return nil end

    local op = trigger.op or "=="
    if op == "!=" then expected = not expected
    elseif op ~= "==" then return nil end
    return expected and TriggerEnum("Added") or TriggerEnum("Removed")
end

local function AppendResolvedSoundSignature(parts, source)
    local fileName, fileID = ResolveSound(source)
    parts[#parts + 1] = tostring(fileName or "")
    parts[#parts + 1] = tostring(fileID or "")
end

local function ActionTrigger(alerts, action)
    if type(action) ~= "table" or action.type ~= "sound"
        or action.soundMode == "repeat"
    then
        return nil
    end

    local triggers = alerts and alerts.triggers or {}
    local condition = action.condition or "any"
    local triggerIndex = type(condition) == "string"
        and tonumber(condition:match("^trigger(%d+)$")) or nil
    if triggerIndex then return ActiveTriggerEdge(triggers[triggerIndex]) end
    if condition ~= "any" or #triggers == 0 then return nil end

    local shared
    for _, trigger in ipairs(triggers) do
        local edge = ActiveTriggerEdge(trigger)
        if edge == nil or (shared ~= nil and edge ~= shared) then return nil end
        shared = edge
    end
    return shared
end

local function AppendAlertSignature(parts, alerts)
    if type(alerts) ~= "table" then return end
    parts[#parts + 1] = tostring(alerts.enabled == true)
    parts[#parts + 1] = tostring(alerts.triggerLogic or "or")
    for index, trigger in ipairs(alerts.triggers or {}) do
        parts[#parts + 1] = table.concat({
            "t", index, tostring(trigger.type), tostring(trigger.op), tostring(trigger.value),
        }, ":")
    end
    for index, action in ipairs(alerts.actions or {}) do
        parts[#parts + 1] = table.concat({
            "a", index, tostring(action), tostring(action.type), tostring(action.condition),
            tostring(action.soundMode), tostring(action.soundFile),
            tostring(action.soundCustomPath), tostring(action.soundChannel),
        }, ":")
        AppendResolvedSoundSignature(parts, action)
    end
end

local function BuildSourceSignature(trackers)
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    local inInstance, instanceType = IsInInstance()
    local parts = {
        tostring(specIndex or 0), tostring(specID or 0),
        tostring(inInstance == true), tostring(instanceType or "none"),
    }
    for index, tracker in ipairs(trackers or {}) do
        if type(tracker) == "table" then
            local settings = tracker.settings or {}
            parts[#parts + 1] = table.concat({
                tostring(index), tostring(tracker), tostring(tracker.uid or ""),
                tostring(tracker.isGroup == true),
                tostring(tracker.enabled ~= false), tostring(tracker.disabled == true),
                tostring(tracker.parentGroup or 0), tostring(tracker.displayType or "bar"),
                tostring(tracker.trackingMode or ""), tostring(tracker.isAura ~= false),
                tostring(tracker.spellID or 0), tostring(tracker.cooldownID or 0),
                tostring(tracker.trigger and tracker.trigger.type or ""),
                tostring(tracker.trigger and tracker.trigger.spellID or 0),
                tostring(settings.activationType or "none"),
                tostring(settings.activationSpellID or 0),
                tostring(settings.activationTalentID or 0),
                tostring(settings.soundTrigger or "start"), tostring(settings.soundFile or ""),
                tostring(settings.soundCustomPath or ""), tostring(settings.soundChannel or "Master"),
            }, ":")
            AppendResolvedSoundSignature(parts, settings)
            AppendAlertSignature(parts, settings.alerts)

            if tracker.isGroup then
                local groupSettings = tracker.groupSettings or {}
                parts[#parts + 1] = tostring(groupSettings.loadInstanceType or "all")
                local childParts = {}
                for _, childIndex in ipairs(tracker.controlledChildren or {}) do
                    childParts[#childParts + 1] = tostring(childIndex)
                end
                parts[#parts + 1] = table.concat(childParts, ",")
                local specParts = {}
                for key, value in pairs(groupSettings.loadSpec or {}) do
                    specParts[#specParts + 1] = tostring(key) .. "=" .. tostring(value)
                end
                table.sort(specParts)
                parts[#parts + 1] = table.concat(specParts, ",")
            end
        end
    end
    return table.concat(parts, "|")
end

local function AddPlanEntry(byKey, keys, trigger, spellID, fileName, fileID, channel, tracker, action)
    if trigger == nil or not spellID or spellID <= 0 or not (fileName or fileID) then return end
    local key = table.concat({
        tostring(trigger), tostring(spellID), tostring(fileName or ""),
        tostring(fileID or ""), tostring(channel),
    }, "\31")
    local entry = byKey[key]
    if not entry then
        entry = {
            key = key,
            trigger = trigger,
            spellID = spellID,
            fileName = fileName,
            fileID = fileID,
            channel = channel,
            displayTrackers = setmetatable({}, { __mode = "k" }),
            alertActions = setmetatable({}, { __mode = "k" }),
        }
        byKey[key] = entry
        keys[#keys + 1] = key
    end
    if tracker then entry.displayTrackers[tracker] = true end
    if action then entry.alertActions[action] = true end
end

local function BuildPlan(trackers)
    diagnostics.plans = diagnostics.plans + 1
    local byKey = {}
    local keys = {}
    local groupOwners = BuildGroupOwners(trackers)

    for trackerIndex, tracker in ipairs(trackers or {}) do
        if IsAutomaticAuraTracker(tracker)
            and PassesActivation(tracker)
            and GroupAllowsTracker(trackers, tracker, trackerIndex, groupOwners)
        then
            local spellIDs = Container:GetTrackedSpellIDs(tracker)
            if spellIDs then
                local settings = tracker.settings or {}
                if tracker.displayType == "sound" then
                    local trigger = DisplayTrigger(tracker)
                    local fileName, fileID = ResolveSound(settings)
                    for _, spellID in ipairs(spellIDs) do
                        AddPlanEntry(
                            byKey, keys, trigger, spellID, fileName, fileID,
                            settings.soundChannel or "Master", tracker, nil
                        )
                    end
                end

                local alerts = settings.alerts
                if alerts and alerts.enabled == true then
                    for _, action in ipairs(alerts.actions or {}) do
                        local trigger = ActionTrigger(alerts, action)
                        local fileName, fileID = ResolveSound(action)
                        for _, spellID in ipairs(spellIDs) do
                            AddPlanEntry(
                                byKey, keys, trigger, spellID, fileName, fileID,
                                action.soundChannel or "Master", nil, action
                            )
                        end
                    end
                end
            end
        end
    end

    table.sort(keys)
    local plan = {}
    for _, key in ipairs(keys) do plan[#plan + 1] = byKey[key] end
    return plan, table.concat(keys, "\30")
end

local function CanChangeRegistrations()
    if (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
    then
        return false
    end

    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or IsSecret(restricted) or restricted == true then
            return false
        end
    end

    local restrictionAPI = C_RestrictedActions
        and C_RestrictedActions.IsAddOnRestrictionActive
    if restrictionAPI then
        local okEncounter, encounter = pcall(restrictionAPI, 1)
        local okCombat, combat = pcall(restrictionAPI, 0)
        local okChallenge, challenge = pcall(restrictionAPI, 2)
        if not okEncounter or not okCombat or not okChallenge
            or IsSecret(encounter) or IsSecret(combat) or IsSecret(challenge)
            or encounter == true or (combat == true and challenge == true)
        then
            return false
        end
    end
    return true
end

local retryFrame = CreateFrame("Frame")
local retryTicker
local RetryPendingPlan

local function RequestRetry()
    retryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    retryFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    retryFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    retryFrame:RegisterEvent("ENCOUNTER_END")
    retryFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    if not retryTicker and C_Timer and C_Timer.NewTicker then
        retryTicker = C_Timer.NewTicker(1, function()
            RetryPendingPlan()
        end)
    end
end

local function StopRetry()
    retryFrame:UnregisterAllEvents()
    if retryTicker then
        retryTicker:Cancel()
        retryTicker = nil
    end
end

local function ClearRegistrations()
    if not (C_UnitAuras and C_UnitAuras.RemoveAuraSound) then return false end
    local failed = false
    for index = #registrations, 1, -1 do
        local registrationID = registrations[index]
        local ok = pcall(C_UnitAuras.RemoveAuraSound, registrationID)
        if ok then
            table.remove(registrations, index)
            diagnostics.removals = diagnostics.removals + 1
        else
            failed = true
        end
    end
    return not failed
end

local function MarkPlanOwners(plan)
    wipe(nativeDisplayByTracker)
    wipe(nativeAlertActions)
    for _, entry in ipairs(plan or {}) do
        for tracker in pairs(entry.displayTrackers) do
            nativeDisplayByTracker[tracker] = true
        end
        for action in pairs(entry.alertActions) do
            nativeAlertActions[action] = true
        end
    end
end

local function ApplyPlan(plan, signature)
    if signature == registrationSignature then
        MarkPlanOwners(plan)
        pendingPlan = nil
        pendingSignature = nil
        StopRetry()
        return true
    end
    if not CanChangeRegistrations() then
        pendingPlan = plan
        pendingSignature = signature
        diagnostics.deferred = diagnostics.deferred + 1
        RequestRetry()
        return false
    end
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound) then
        return false
    end
    if not ClearRegistrations() then
        registrationSignature = nil
        wipe(nativeDisplayByTracker)
        wipe(nativeAlertActions)
        pendingPlan = plan
        pendingSignature = signature
        diagnostics.deferred = diagnostics.deferred + 1
        RequestRetry()
        return false
    end

    registrationSignature = nil
    wipe(nativeDisplayByTracker)
    wipe(nativeAlertActions)
    local displayExpected = setmetatable({}, { __mode = "k" })
    local displaySucceeded = setmetatable({}, { __mode = "k" })
    local actionExpected = setmetatable({}, { __mode = "k" })
    local actionSucceeded = setmetatable({}, { __mode = "k" })
    for _, entry in ipairs(plan) do
        for tracker in pairs(entry.displayTrackers) do
            displayExpected[tracker] = (displayExpected[tracker] or 0) + 1
        end
        for action in pairs(entry.alertActions) do
            actionExpected[action] = (actionExpected[action] or 0) + 1
        end
    end

    local failed = false
    for _, entry in ipairs(plan) do
        local info = {
            unitToken = "player",
            spellID = entry.spellID,
            outputChannel = entry.channel,
        }
        if entry.fileName then info.soundFileName = entry.fileName
        else info.soundFileID = entry.fileID end

        local ok, registrationID = pcall(C_UnitAuras.AddAuraSound, entry.trigger, info)
        if ok and registrationID then
            registrations[#registrations + 1] = registrationID
            diagnostics.registrations = diagnostics.registrations + 1
            for tracker in pairs(entry.displayTrackers) do
                displaySucceeded[tracker] = (displaySucceeded[tracker] or 0) + 1
            end
            for action in pairs(entry.alertActions) do
                actionSucceeded[action] = (actionSucceeded[action] or 0) + 1
            end
        else
            diagnostics.failures = diagnostics.failures + 1
            failed = true
        end
    end

    for tracker, expected in pairs(displayExpected) do
        nativeDisplayByTracker[tracker] = displaySucceeded[tracker] == expected
    end
    for action, expected in pairs(actionExpected) do
        nativeAlertActions[action] = actionSucceeded[action] == expected
    end

    if failed then
        ClearRegistrations()
        registrationSignature = nil
        wipe(nativeDisplayByTracker)
        wipe(nativeAlertActions)
        pendingPlan = plan
        pendingSignature = signature
        RequestRetry()
        return false
    end

    pendingPlan = nil
    pendingSignature = nil
    registrationSignature = signature
    StopRetry()
    return true
end

function Sounds:Sync(trackers)
    diagnostics.syncs = diagnostics.syncs + 1
    local nextSourceSignature = BuildSourceSignature(trackers)
    if nextSourceSignature == sourceSignature then return end
    sourceSignature = nextSourceSignature

    local plan, signature = BuildPlan(trackers)
    ApplyPlan(plan, signature)
end

function Sounds:Suspend()
    sourceSignature = nil
    ApplyPlan({}, "")
end

function Sounds:Invalidate()
    sourceSignature = nil
end

function Sounds:IsNative(tracker)
    return tracker ~= nil and nativeDisplayByTracker[tracker] == true
end

function Sounds:IsNativeAlertAction(action)
    local source = action and (action._nativeSourceAction or action)
    return source ~= nil and nativeAlertActions[source] == true
end

function Sounds:GetDiagnostics()
    local result = {}
    for key, value in pairs(diagnostics) do result[key] = value end
    local nativeActions = 0
    for _ in pairs(nativeAlertActions) do nativeActions = nativeActions + 1 end
    result.activeRegistrations = #registrations
    result.nativeAlertActions = nativeActions
    result.pending = pendingPlan ~= nil
    return result
end

function Sounds:ResetDiagnostics()
    for key in pairs(diagnostics) do diagnostics[key] = 0 end
end

RetryPendingPlan = function()
    if not pendingPlan or not CanChangeRegistrations() then return end
    ApplyPlan(pendingPlan, pendingSignature or "")
end

retryFrame:SetScript("OnEvent", RetryPendingPlan)

function Sounds:OnSharedMediaRegistered(_, mediaType)
    if mediaType ~= "sound" then return end
    self:Invalidate()
    local resourceBars = DDingUI.ResourceBars
    if resourceBars and resourceBars.RequestBuffTrackerUpdate then
        resourceBars:RequestBuffTrackerUpdate("aura-sound-media", 0.05)
    end
end

if LSM and LSM.RegisterCallback then
    LSM.RegisterCallback(Sounds, "LibSharedMedia_Registered", "OnSharedMediaRegistered")
end
