local ns = select(2, ...)
local DDingUI = ns.Addon

local TotemTracker = {}
DDingUI.CustomIconTotems = TotemTracker

local PLACEHOLDER_ICON = 310731
local framesBySlot = {}
local trackedCount = 0
local eventFrame = CreateFrame("Frame")

local function GetSlot(iconData, frame)
    return tonumber((iconData and iconData.totemSlot) or (frame and frame._totemSlot))
end

local function GetSlotFrames(slot, create)
    local frames = framesBySlot[slot]
    if not frames and create then
        frames = setmetatable({}, { __mode = "k" })
        framesBySlot[slot] = frames
    end
    return frames
end

local function SetEventsEnabled(enabled)
    eventFrame:UnregisterAllEvents()
    if not enabled then return end
    eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

local function FeedDurationObject(cooldown, durationObject)
    if not cooldown then return end
    cooldown:SetReverse(true)
    if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
    if durationObject then
        cooldown:Show()
        cooldown:SetCooldownFromDurationObject(durationObject, true)
    else
        cooldown:Clear()
        cooldown:Hide()
    end
end

local function FeedLegacyDuration(frame, slot)
    local haveTotem, _, startTime, duration, icon = GetTotemInfo(slot)
    if haveTotem and duration and duration > 0 then
        frame.cooldownProbe:SetReverse(true)
        if frame.cooldownProbe.SetDrawBling then frame.cooldownProbe:SetDrawBling(false) end
        frame.cooldownProbe:SetCooldown(startTime, duration)
        if frame.icon then frame.icon:SetTexture(icon) end
        return true
    end
    frame.cooldownProbe:Clear()
    frame.cooldownProbe:Hide()
    return false
end

local function NotifyStateChanged()
    local bridge = DDingUI.DynamicIconBridge
    if bridge and bridge.NotifyIconsChanged then
        bridge:NotifyIconsChanged()
    end
end

function TotemTracker:GetNumSlots()
    return (GetNumTotemSlots and GetNumTotemSlots()) or 0
end

function TotemTracker:GetPlaceholderIcon()
    return PLACEHOLDER_ICON
end

function TotemTracker:UpdateFrame(frame, iconData, suppressLayoutRefresh, authoritativeState)
    local slot = GetSlot(iconData, frame)
    if not frame or not slot or slot < 1 then return false end

    local previousActive = frame._ddTotemActive == true
    local stateInitialized = frame._ddTotemStateInitialized == true
    local observedActive = false
    local durationObject

    if GetTotemDuration then
        durationObject = GetTotemDuration(slot)
        FeedDurationObject(frame.cooldownProbe, durationObject)
        observedActive = frame.cooldownProbe and frame.cooldownProbe:IsShown() and true or false
    elseif GetTotemInfo and frame.cooldownProbe then
        observedActive = FeedLegacyDuration(frame, slot)
    end

    local active = observedActive
    if stateInitialized and not authoritativeState then
        active = previousActive
    end

    if frame.cooldown then
        if GetTotemDuration then
            FeedDurationObject(frame.cooldown, durationObject)
        elseif observedActive then
            local _, _, startTime, duration = GetTotemInfo(slot)
            frame.cooldown:SetReverse(true)
            if frame.cooldown.SetDrawBling then frame.cooldown:SetDrawBling(false) end
            frame.cooldown:SetCooldown(startTime, duration)
        else
            frame.cooldown:Clear()
            frame.cooldown:Hide()
        end
        if iconData and iconData.settings and iconData.settings.showCooldown == false then
            frame.cooldown:Hide()
        end
    end

    if frame.icon then
        if observedActive and GetTotemInfo then
            local _, _, _, _, icon = GetTotemInfo(slot)
            frame.icon:SetTexture(icon)
            frame.icon:SetDesaturation(0)
        elseif not stateInitialized then
            frame.icon:SetTexture(PLACEHOLDER_ICON)
        end
    end

    frame._ddTotemActive = active
    frame._ddTotemStateInitialized = true
    frame._ddCustomIconActive = active
    frame._ddCustomIconReady = not active
    frame._ddCustomIconProcActive = false
    frame._ddManagedAuraExpired = nil

    if frame.count then
        frame.count:SetText("")
        frame.count:Hide()
    end

    if DDingUI.CustomIcons and DDingUI.CustomIcons.UpdateDynamicIconStateGlow then
        DDingUI.CustomIcons:UpdateDynamicIconStateGlow(frame, iconData)
    end
    if frame._ddIsManaged and DDingUI.CustomIcons and DDingUI.CustomIcons.ApplyManagedGroupTextOptions then
        DDingUI.CustomIcons.ApplyManagedGroupTextOptions(frame)
    end

    if not suppressLayoutRefresh and previousActive ~= active then
        NotifyStateChanged()
    end
    return active
end

function TotemTracker:RegisterFrame(frame, iconData)
    local slot = GetSlot(iconData, frame)
    if not frame or not slot or slot < 1 then return end

    self:UnregisterFrame(frame)
    frame._totemSlot = slot
    local frames = GetSlotFrames(slot, true)
    frames[frame] = iconData
    trackedCount = trackedCount + 1
    if trackedCount == 1 then
        SetEventsEnabled(true)
    end
    self:UpdateFrame(frame, iconData, true, true)
end

function TotemTracker:UnregisterFrame(frame)
    if not frame then return end
    local slot = frame._totemSlot
    local frames = slot and framesBySlot[slot]
    if frames and frames[frame] then
        frames[frame] = nil
        trackedCount = math.max(0, trackedCount - 1)
        if not next(frames) then
            framesBySlot[slot] = nil
        end
    end
    frame._totemSlot = nil
    frame._ddTotemActive = nil
    frame._ddTotemStateInitialized = nil
    if trackedCount == 0 then
        SetEventsEnabled(false)
    end
end

function TotemTracker:RefreshSlot(slot)
    slot = tonumber(slot)
    local frames = slot and framesBySlot[slot]
    if not frames then return end

    local stateChanged = false
    for frame, iconData in pairs(frames) do
        local previousActive = frame._ddTotemActive == true
        self:UpdateFrame(frame, iconData, true, true)
        if previousActive ~= (frame._ddTotemActive == true) then
            stateChanged = true
        end
    end
    if stateChanged then
        NotifyStateChanged()
    end
end

function TotemTracker:RefreshAll()
    local stateChanged = false
    for _, frames in pairs(framesBySlot) do
        for frame, iconData in pairs(frames) do
            local previousActive = frame._ddTotemActive == true
            self:UpdateFrame(frame, iconData, true, true)
            if previousActive ~= (frame._ddTotemActive == true) then
                stateChanged = true
            end
        end
    end
    if stateChanged then
        NotifyStateChanged()
    end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_TOTEM_UPDATE" then
        local slot = tonumber(arg1)
        if slot then
            TotemTracker:RefreshSlot(slot)
        else
            TotemTracker:RefreshAll()
        end
    else
        TotemTracker:RefreshAll()
    end
end)
