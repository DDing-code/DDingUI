import sys
import re

file_path = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Modules\ResourceBars\BuffTrackerBar.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace local settings = trackedBuff.settings or {}
content = content.replace('local settings = trackedBuff.settings or {}', 
    'local display = trackedBuff.display or {}\n    local trigger = trackedBuff.trigger or {}')

# Update reference to EvaluateAlerts to EvaluateConditions
content = content.replace('EvaluateAlerts(', 'EvaluateConditions(')
content = content.replace('ApplyAlertActions(', 'ApplyConditionActions(')
content = content.replace('EvaluateAlerts ', 'EvaluateConditions ')
content = content.replace('ApplyAlertActions ', 'ApplyConditionActions ')

# Field mappings
trigger_fields = ['var', 'maxStacks', 'stackDuration', 'dynamicDuration', 'hideWhenZero', 'resetOnCombatEnd', 'showInCombat']
for f in trigger_fields:
    # Need to properly replace settings.f with trigger.f, and we don't want to mess up substring matches
    content = re.sub(r'\bsettings\.' + f + r'\b', 'trigger.' + f, content)

# Remaining settings. -> display.
content = re.sub(r'\bsettings\.', 'display.', content)

# Also trackedBuff.trackingMode -> trigger.type
content = content.replace('trackedBuff.trackingMode', 'trigger.type')
content = content.replace('trackedBuff.cooldownID', 'trigger.cooldownID')
content = content.replace('trackedBuff.spellID', 'trigger.spellID')

# Now let's inject EvaluateConditions and ApplyConditionActions implementation
# We will do this by replacing the original function definitions.
start_str = "local function EvaluateAlerts"
end_str = "-- ============================================================\n-- TEXT FRAME SYSTEM"

idx_start = content.find(start_str)
idx_end = content.find(end_str)

if idx_start != -1 and idx_end != -1:
    new_funcs = """local function EvaluateConditions(trackedBuff, trackedStacks, hasData, auraInstanceID, unit)
    local conditions = trackedBuff and trackedBuff.conditions or {}
    if #conditions == 0 then return nil end

    -- Return a list of active changes
    local activeChanges = {}

    for cIdx, cond in ipairs(conditions) do
        local checks = cond.checks or {}
        local changes = cond.changes or {}
        local matchType = cond.matchType or "AND"
        
        local conditionPassed = false
        if #checks > 0 then
            conditionPassed = (matchType == "AND")
            
            for _, chk in ipairs(checks) do
                local checkPassed = false
                
                if chk.variable == "active" then
                    checkPassed = EvaluateComparison(hasData, chk.op, chk.value == "true")
                elseif chk.variable == "time" then
                    if hasData and auraInstanceID then
                        pcall(function()
                            local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                            if auraData and auraData.expirationTime then
                                local remaining = auraData.expirationTime - GetTime()
                                if remaining > 0 then
                                    checkPassed = EvaluateComparison(remaining, chk.op, tonumber(chk.value) or 0)
                                end
                            end
                        end)
                    end
                elseif chk.variable == "stacks" then
                    if hasData then
                        checkPassed = EvaluateComparison(trackedStacks, chk.op, tonumber(chk.value) or 0)
                    end
                end
                
                if matchType == "AND" then
                    if not checkPassed then conditionPassed = false; break end
                else -- OR
                    if checkPassed then conditionPassed = true; break end
                end
            end
        end
        
        if conditionPassed then
            for _, chg in ipairs(changes) do
                table.insert(activeChanges, chg)
            end
        end
    end

    if #activeChanges == 0 then return nil end
    return activeChanges
end

-- Apply condition actions based on evaluation result
local function ApplyConditionActions(activeChanges, trackedBuff, frame)
    -- Reset overrides
    frame._alertColorOverride = nil
    frame._alertGlowOverride = false

    if not frame._alertPrevState then
        frame._alertPrevState = {}
    end
    if not frame._alertSoundLastPlay then
        frame._alertSoundLastPlay = {}
    end

    -- Process active changes
    -- For sounds, if it wasn't active in the previous frame, play it now.
    -- We can use the change index as the state key.
    
    local now = GetTime()
    local currentStates = {}

    if activeChanges then
        for i, chg in ipairs(activeChanges) do
            local stateKey = chg.property .. "_" .. tostring(chg.value)
            currentStates[stateKey] = true
            
            if chg.property == "color" then
                frame._alertColorOverride = chg.value
            elseif chg.property == "glow" then
                frame._alertGlowOverride = true
            elseif chg.property == "sound" then
                -- Play sound only once when transitioning into this state
                local wasActive = frame._alertPrevState[stateKey]
                if not wasActive then
                    local soundPath = nil
                    if IsValidSoundPath(chg.value) then soundPath = chg.value end
                    PlayTrackerSound(chg.value, "Master", soundPath)
                    frame._alertSoundLastPlay[stateKey] = now
                end
            end
        end
    end
    
    frame._alertPrevState = currentStates
end

"""
    content = content[:idx_start] + new_funcs + content[idx_end:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print('BuffTrackerBar successfully rewritten for Phase 3!')

