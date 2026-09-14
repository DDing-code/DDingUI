local ADDON_NAME, ns = ...
local Engine = ns.Addon and ns.Addon.TrackedAuraContainer
if not Engine then return end

-- Shared by options and runtime. Native sound events and AuraContainer visuals
-- do not expose protected aura state to addon Lua.
local function TriggerKind(trigger)
    if type(trigger) ~= "table" then return nil end
    if trigger.type == "combat" then return "combat" end
    if trigger.type == "applications" then return "applications" end
    if trigger.type ~= "active" then return nil end
    local value = trigger.value
    if value == "true" then value = true elseif value == "false" then value = false end
    if type(value) ~= "boolean" then return nil end
    local op = trigger.op or "=="
    if op == "!=" then value = not value elseif op ~= "==" then return nil end
    return value and "present" or "absent"
end

function Engine:GetAlertConditionKind(tracker, condition)
    if not self:IsAutomaticAuraTracker(tracker) then return "legacy" end
    local alerts = tracker.settings and tracker.settings.alerts
    local triggers = alerts and alerts.triggers or {}
    condition = condition or "any"
    local index = type(condition) == "string" and tonumber(condition:match("^trigger(%d+)$"))
    if index then return TriggerKind(triggers[index]) end
    if condition ~= "any" or #triggers == 0 then return nil end
    local shared
    for _, trigger in ipairs(triggers) do
        local kind = TriggerKind(trigger)
        if not kind or (shared and shared ~= kind) then return nil end
        shared = kind
    end
    return shared
end

function Engine:GetAlertActionIssue(tracker, action)
    if not self:IsAutomaticAuraTracker(tracker) then return nil end
    local kind = self:GetAlertConditionKind(tracker, action.condition)
    if not kind then return "Aura Alert Unsupported Condition" end
    if action.type == "sound" then
        if kind ~= "combat" and (action.soundMode or "once") ~= "once" then
            return "Aura Alert Event Sound Only"
        end
        return nil
    end
    if kind ~= "present" then return "Aura Alert Present Visual Only" end
    local target = action.visualTarget or "self"
    if tracker.displayType == "trigger" then
        if action.type ~= "glow" or type(target) ~= "string"
            or (not target:match("^cdm:%d+$") and not target:match("^custom:.+$"))
        then
            return "Aura Alert External Glow Only"
        end
        for _, other in ipairs(tracker.settings.alerts.actions or {}) do
            if other.type == "glow" and other.visualTarget ~= target
                and self:GetAlertConditionKind(tracker, other.condition) == "present"
            then
                return "Aura Alert Single Glow Target"
            end
        end
    elseif not self:IsSupportedAuraTracker(tracker) or target ~= "self"
        or (action.type ~= "glow" and action.type ~= "color" and action.type ~= "desaturate")
    then
        return "Aura Alert Self Visual Only"
    elseif action.type == "color" and action.colorTarget
        and action.colorTarget ~= "self" and action.colorTarget ~= "icon" and action.colorTarget ~= "border"
    then
        return "Aura Alert Self Visual Only"
    end
    return nil
end
