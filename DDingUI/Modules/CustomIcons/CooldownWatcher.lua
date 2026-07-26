local ns = select(2, ...)
local DDingUI = ns.Addon

local CooldownWatcher = {}
DDingUI.CustomIconCooldownWatcher = CooldownWatcher

function CooldownWatcher.Attach(
    runtime,
    ScheduleCustomIconWork,
    UpdateAllIcons,
    SafeNumber,
    GetDynamicDB
)
    function runtime.ClearCustomCooldownTable(tbl)
        if not tbl then return end
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end

    function runtime.NormalizeCustomCooldownState(startTime, duration, enable)
        return startTime or 0, duration or 0, enable or 0
    end

    function runtime.PopulateCustomCooldownState(state, startTime, duration, enable)
        if not state then return end
        startTime, duration, enable = runtime.NormalizeCustomCooldownState(startTime, duration, enable)
        state.startTime = startTime
        state.duration = duration
        state.enable = enable
        local isActive = false
        pcall(function()
            isActive = enable == 1 and startTime > 0 and duration > 0
        end)
        state.isActive = isActive
        local readyTime = nil
        if isActive then
            pcall(function()
                readyTime = startTime + duration
            end)
        end
        state.readyTime = readyTime
    end

    function runtime.UpdateCustomCooldownStateIfChanged(state, startTime, duration, enable)
        if not state then return false end
        startTime, duration, enable = runtime.NormalizeCustomCooldownState(startTime, duration, enable)
        local same = false
        pcall(function()
            same = state.startTime == startTime and state.duration == duration and state.enable == enable
        end)
        if same then return false end
        runtime.PopulateCustomCooldownState(state, startTime, duration, enable)
        return true
    end

    function runtime.ReadCustomItemCooldown(itemID)
        local startTime, duration, enable
        if C_Container and C_Container.GetItemCooldown then
            pcall(function()
                startTime, duration, enable = C_Container.GetItemCooldown(itemID)
            end)
        end
        return startTime, duration, enable
    end

    function runtime.ReadCustomSlotCooldown(slotID)
        local startTime, duration, enable
        if GetInventoryItemCooldown then
            pcall(function()
                startTime, duration, enable = GetInventoryItemCooldown("player", slotID)
            end)
        end
        return startTime, duration, enable
    end

    function runtime.EvaluateCustomCooldownWatches()
        local watcher = runtime.cooldownWatcher
        if not watcher or (watcher.activeTargetCount or 0) <= 0 then return end
        local changed = {}

        for itemID, iconKeys in pairs(watcher.itemTargets) do
            local state = watcher.itemStates[itemID]
            if not state then
                state = {}
                watcher.itemStates[itemID] = state
            end
            if runtime.UpdateCustomCooldownStateIfChanged(state, runtime.ReadCustomItemCooldown(itemID)) then
                for iconKey in pairs(iconKeys) do
                    changed[iconKey] = true
                end
            end
        end

        for slotID, iconKeys in pairs(watcher.slotTargets) do
            local state = watcher.slotStates[slotID]
            if not state then
                state = {}
                watcher.slotStates[slotID] = state
            end
            if runtime.UpdateCustomCooldownStateIfChanged(state, runtime.ReadCustomSlotCooldown(slotID)) then
                for iconKey in pairs(iconKeys) do
                    changed[iconKey] = true
                end
            end
        end

        if next(changed) then
            runtime.QueueCustomCooldownIconRefresh(nil, changed)
        end
    end

    function runtime.FlushCustomCooldownIconRefresh()
        local watcher = runtime.cooldownWatcher
        if not watcher then return end
        local keys = watcher.pendingIconKeys
        local refreshAll = watcher.refreshAll
        local notify = watcher.layoutNotify

        watcher.refreshPending = false
        watcher.refreshAll = false
        watcher.layoutNotify = nil

        if refreshAll then
            runtime.ClearCustomCooldownTable(keys)
            for _, targetMap in ipairs({ watcher.itemTargets, watcher.slotTargets }) do
                for _, iconKeys in pairs(targetMap) do
                    for iconKey in pairs(iconKeys) do
                        keys[iconKey] = true
                    end
                end
            end
        end

        for iconKey in pairs(keys) do
            if runtime.UpdateDynamicIcon then
                pcall(runtime.UpdateDynamicIcon, iconKey)
            end
            keys[iconKey] = nil
        end

        if notify and DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
            DDingUI.DynamicIconBridge:NotifyIconsChanged(notify == true or notify == "force")
        end
    end

    function runtime.EnsureCustomCooldownWatcher()
        local watcher = runtime.cooldownWatcher
        if not watcher then return nil end
        return watcher
    end

    function runtime.QueueEvaluateCustomCooldownWatches()
        local watcher = runtime.EnsureCustomCooldownWatcher()
        if not watcher or (watcher.activeTargetCount or 0) <= 0 or watcher.evaluatePending then return end
        watcher.evaluatePending = true
        ScheduleCustomIconWork()
    end

    function runtime.QueueCustomCooldownIconRefresh(needsLayoutNotify, iconKeys)
        local watcher = runtime.EnsureCustomCooldownWatcher()
        if not watcher then
            UpdateAllIcons(needsLayoutNotify, "item")
            return
        end
        if iconKeys then
            for iconKey in pairs(iconKeys) do
                watcher.pendingIconKeys[iconKey] = true
            end
        else
            watcher.refreshAll = true
        end
        if needsLayoutNotify == true or needsLayoutNotify == "force" then
            watcher.layoutNotify = "force"
        elseif needsLayoutNotify and watcher.layoutNotify ~= "force" then
            watcher.layoutNotify = needsLayoutNotify
        end
        watcher.refreshPending = true
        ScheduleCustomIconWork()
    end

    function runtime.AddCustomCooldownTarget(targets, id, iconKey)
        local safeID = SafeNumber(id)
        if not safeID or not iconKey then return end
        targets[safeID] = targets[safeID] or {}
        targets[safeID][iconKey] = true
    end

    function runtime.AddCustomFallbackItemTargets(settings, iconKey)
        if type(settings) ~= "table" or type(settings.fallbackItems) ~= "string" then return end
        for itemText in string.gmatch(settings.fallbackItems, "(%d+)") do
            runtime.AddCustomCooldownTarget(runtime.cooldownWatcher.itemTargets, itemText, iconKey)
        end
    end

    function runtime.PrimeCustomCooldownWatcherStates()
        local watcher = runtime.cooldownWatcher
        runtime.ClearCustomCooldownTable(watcher.itemStates)
        runtime.ClearCustomCooldownTable(watcher.slotStates)
        for itemID in pairs(watcher.itemTargets) do
            watcher.itemStates[itemID] = {}
            runtime.PopulateCustomCooldownState(watcher.itemStates[itemID], runtime.ReadCustomItemCooldown(itemID))
        end
        for slotID in pairs(watcher.slotTargets) do
            watcher.slotStates[slotID] = {}
            runtime.PopulateCustomCooldownState(watcher.slotStates[slotID], runtime.ReadCustomSlotCooldown(slotID))
        end
    end

    function runtime.RegisterCustomCooldownWatches()
        local watcher = runtime.EnsureCustomCooldownWatcher()
        if not watcher then return end
        local db = GetDynamicDB()
        runtime.ClearCustomCooldownTable(watcher.itemTargets)
        runtime.ClearCustomCooldownTable(watcher.slotTargets)
        watcher.activeTargetCount = 0
        watcher.hasSpellTarget = false

        for iconKey, frame in pairs(runtime.iconFrames) do
            local iconData = frame and db.iconData and db.iconData[iconKey]
            if iconData then
                if iconData.type == "item" then
                    runtime.AddCustomCooldownTarget(watcher.itemTargets, iconData.id, iconKey)
                    runtime.AddCustomFallbackItemTargets(iconData.settings, iconKey)
                elseif iconData.type == "slot" then
                    runtime.AddCustomCooldownTarget(watcher.slotTargets, iconData.slotID, iconKey)
                elseif iconData.type == "trinketProc" and (not iconData.settings or iconData.settings.showItemCooldown ~= false) then
                    runtime.AddCustomCooldownTarget(watcher.slotTargets, iconData.slotID, iconKey)
                elseif iconData.type == "spell" or iconData.type == "racial" then
                    watcher.hasSpellTarget = true
                end
            end
        end

        for _ in pairs(watcher.itemTargets) do
            watcher.activeTargetCount = watcher.activeTargetCount + 1
        end
        for _ in pairs(watcher.slotTargets) do
            watcher.activeTargetCount = watcher.activeTargetCount + 1
        end

        runtime.PrimeCustomCooldownWatcherStates()
        watcher.kindsInitialized = true
    end

    function runtime.RequestCustomCooldownWatchRegistration()
        local watcher = runtime.cooldownWatcher
        if InCombatLockdown and InCombatLockdown() then
            watcher.registrationPending = true
            return
        end
        watcher.registrationPending = false
        runtime.RegisterCustomCooldownWatches()
    end

end
