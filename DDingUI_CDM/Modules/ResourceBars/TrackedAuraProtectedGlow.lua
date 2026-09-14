local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local ResourceBars = DDingUI.ResourceBars
local Engine = DDingUI.TrackedAuraContainer
if not ResourceBars or not Engine then return end

-- Protected automatic auras cannot expose their active/stacks/duration state to
-- ordinary addon Lua. Visual actions that mean exactly "this aura is present"
-- can still be attached to the AuraContainer button itself. Its visibility owns
-- self color, desaturation, and glow without reading aura values back into Lua.
--
-- The shared alert policy rejects unsupported actions without rewriting saves.

local diagnostics = {
    eligibleEvaluations = 0,
    appliedOverrides = 0,
}


local function ColorSignature(color)
    color = type(color) == "table" and color or {}
    return table.concat({
        tostring(color[1] or 1),
        tostring(color[2] or 0.82),
        tostring(color[3] or 0.1),
        tostring(color[4] or 1),
    }, ",")
end

local function ResolveProtectedTriggerPresentation(tracker)
    if not Engine:IsAutomaticAuraTracker(tracker) or tracker.displayType ~= "trigger" then return nil end

    local alerts = tracker.settings and tracker.settings.alerts
    if type(alerts) ~= "table" or alerts.enabled ~= true then return nil end

    local actions = alerts.actions or {}
    if #actions == 0 then return nil end

    local targetKey
    local signatures = {}
    local visualActions = {}
    for _, action in ipairs(actions) do
        if action.type == "glow" and not Engine:GetAlertActionIssue(tracker, action) then
            targetKey = action.visualTarget
            visualActions[#visualActions + 1] = action
            signatures[#signatures + 1] = table.concat({
                targetKey,
                tostring(action.glowType or "pixel"),
                ColorSignature(action.glowColor),
                tostring(action.glowLines or 8),
                tostring(action.glowFrequency or 0.25),
                tostring(action.glowThickness or 2),
                tostring(action.glowXOffset or 0),
                tostring(action.glowYOffset or 0),
            }, ":")
        end
    end
    if not targetKey then return nil end

    return {
        actions = visualActions,
        targetKey = targetKey,
        signature = table.concat(signatures, ";"),
    }
end

function Engine:GetProtectedTriggerPresentation(tracker)
    return ResolveProtectedTriggerPresentation(tracker)
end

function Engine:InitializeProtectedTriggerButton(button, tracker)
    local presentation = ResolveProtectedTriggerPresentation(tracker)
    local visuals = DDingUI.RestrictedAuraVisuals
    if not presentation or not visuals or not visuals.ApplyGlow then return false end

    for _, action in ipairs(presentation.actions) do
        visuals:ApplyGlow(button, {
            iconAnimation = action.glowType or "pixel",
            glowColor = action.glowColor or { 1, 0.82, 0.1, 1 },
            glowLines = action.glowLines or 8,
            glowFrequency = action.glowFrequency or 0.25,
            glowThickness = action.glowThickness or 2,
            glowXOffset = action.glowXOffset or 0,
            glowYOffset = action.glowYOffset or 0,
            glowEnabled = true,
            glowWhenInactive = false,
        })
    end
    return true
end

local function ResolveProtectedPresentation(tracker)
    local settings = tracker and tracker.settings
    local alerts = settings and settings.alerts
    if type(alerts) ~= "table" or alerts.enabled ~= true then return nil end

    local presentation = {}
    for _, action in ipairs(alerts.actions or {}) do
        if type(action) == "table" and not Engine:GetAlertActionIssue(tracker, action)
            and Engine:GetAlertConditionKind(tracker, action.condition) == "present" then
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
            end
        end
    end
    if presentation.glow or presentation.selfColor or presentation.iconColor
        or presentation.borderColor or presentation.desaturate
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
