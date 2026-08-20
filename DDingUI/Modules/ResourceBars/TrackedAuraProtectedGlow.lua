local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local ResourceBars = DDingUI.ResourceBars
local Engine = DDingUI.TrackedAuraContainer
if not ResourceBars or not Engine then return end

-- Protected automatic auras cannot expose their active/stacks/duration state to
-- ordinary addon Lua. Actions that mean exactly "this aura is present" can
-- still be attached to the AuraContainer button itself. Its visibility owns
-- self color, desaturation, glow, and sound transitions without reading aura
-- values back into addon code.
--
-- This bridge runs outside TrackedAuraProtectedAlerts so it can inspect the
-- SavedVariables-backed alert definition before that module temporarily removes
-- protected triggers/actions from legacy Lua evaluation.

local diagnostics = {
    eligibleEvaluations = 0,
    appliedOverrides = 0,
}

local function ActiveTriggerMeansAuraPresent(trigger)
    if type(trigger) ~= "table" or trigger.type ~= "active" then
        return false
    end

    local op = trigger.op or "=="
    if op == "==" then
        return trigger.value == true
    elseif op == "!=" then
        return trigger.value == false
    end
    return false
end

local function AllTriggersMeanAuraPresent(alerts)
    local triggers = alerts and alerts.triggers or {}
    if #triggers == 0 then return false end

    for _, trigger in ipairs(triggers) do
        if not ActiveTriggerMeansAuraPresent(trigger) then
            return false
        end
    end
    return true
end

local function ConditionMeansAuraPresent(alerts, condition)
    if condition == "any" then
        -- With only aura-present predicates, both AND and OR collapse to the
        -- same condition: the tracked aura is present. The default single
        -- active trigger + `any` action therefore remains supported.
        return AllTriggersMeanAuraPresent(alerts)
    end

    local triggerIndex = type(condition) == "string"
        and tonumber(condition:match("^trigger(%d+)$")) or nil
    if not triggerIndex then return false end

    local trigger = alerts and alerts.triggers and alerts.triggers[triggerIndex]
    return ActiveTriggerMeansAuraPresent(trigger)
end

local function SoundSignaturePart(actionIndex, action)
    return table.concat({
        tostring(actionIndex),
        tostring(action.soundFile),
        tostring(action.soundCustomPath),
        tostring(action.soundChannel),
        tostring(action.soundMode),
        tostring(action.soundCooldown),
    }, ":")
end

local function ResolveProtectedPresentation(tracker)
    local settings = tracker and tracker.settings
    local alerts = settings and settings.alerts
    if type(alerts) ~= "table" or alerts.enabled ~= true then return nil end

    local presentation = {}
    local soundParts = {}
    for actionIndex, action in ipairs(alerts.actions or {}) do
        if type(action) == "table" and ConditionMeansAuraPresent(alerts, action.condition) then
            local selfTarget = action.visualTarget == nil or action.visualTarget == "self"
            if action.type == "glow" and selfTarget then
                presentation.glow = action
            elseif action.type == "color" and selfTarget and type(action.color) == "table" then
                local colorTarget = action.colorTarget or "self"
                if colorTarget == "self" then
                    presentation.selfColor = action.color
                elseif colorTarget == "icon" then
                    presentation.iconColor = action.color
                elseif colorTarget == "border" then
                    presentation.borderColor = action.color
                end
            elseif action.type == "desaturate" and selfTarget then
                presentation.desaturate = true
            elseif action.type == "sound" then
                presentation.sounds = presentation.sounds or {}
                presentation.sounds[#presentation.sounds + 1] = action
                soundParts[#soundParts + 1] = SoundSignaturePart(actionIndex, action)
            end
        end
    end
    if presentation.sounds then
        presentation.soundSignature = table.concat(soundParts, "|")
    end
    if presentation.glow or presentation.selfColor or presentation.iconColor
        or presentation.borderColor or presentation.desaturate or presentation.sounds
    then
        return presentation
    end
    return nil
end

local function IsProtectedVisualPath(tracker)
    if not tracker then return false end
    local displayType = tracker.displayType or "bar"
    if displayType ~= "bar" and displayType ~= "ring"
        and displayType ~= "icon" and displayType ~= "text"
    then
        return false
    end
    if Engine.IsProtectedDisplayPath then
        return Engine:IsProtectedDisplayPath(tracker)
    end
    return Engine.IsBound and Engine:IsBound(tracker) or false
end

local function CallWithProtectedPresentation(original, self, barIndex, tracker, globalCfg)
    if not IsProtectedVisualPath(tracker) then
        return original(self, barIndex, tracker, globalCfg)
    end

    diagnostics.eligibleEvaluations = diagnostics.eligibleEvaluations + 1

    local presentation = ResolveProtectedPresentation(tracker)
    if not presentation then
        return original(self, barIndex, tracker, globalCfg)
    end

    Engine:SetActivePresentationOverride(tracker, presentation)
    local ok, result1, result2, result3 = pcall(original, self, barIndex, tracker, globalCfg)
    Engine:ClearActivePresentationOverride(tracker)

    if not ok then
        error(result1, 0)
    end

    diagnostics.appliedOverrides = diagnostics.appliedOverrides + 1
    return result1, result2, result3
end

local function Wrap(methodName)
    local original = ResourceBars[methodName]
    if type(original) == "function" then
        ResourceBars[methodName] = function(self, barIndex, tracker, globalCfg)
            return CallWithProtectedPresentation(original, self, barIndex, tracker, globalCfg)
        end
    end
end

Wrap("UpdateSingleTrackedBuffBar")
Wrap("UpdateSingleTrackedBuffRing")
Wrap("UpdateSingleTrackedBuffIcon")
Wrap("UpdateSingleTrackedBuffText")

function Engine:GetProtectedGlowDiagnostics()
    return {
        eligibleEvaluations = diagnostics.eligibleEvaluations,
        appliedOverrides = diagnostics.appliedOverrides,
    }
end
