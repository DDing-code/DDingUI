import sys

file_path = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Config\BuffTrackerOptions.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1
for i, line in enumerate(lines):
    if '-- Alerts Enabled toggle' in line:
        start_idx = i
    if '-- Separator line (only show when buff exists AND is expanded)' in line:
        end_idx = i
        break

if start_idx != -1 and end_idx != -1:
    new_code = '''
    -- ============================================================
    -- CONDITIONS (Phase 2 WA-style)
    -- ============================================================
    local function EnsureConditions(idx)
        local trackedBuffs = GetTrackedBuffs()
        local b = trackedBuffs[idx]
        if not b then return nil end
        if not b.conditions then b.conditions = {} end
        return b.conditions
    end

    local condOrderBase = orderBase + 8.0

    options["tracked" .. index .. "_condAddBtn"] = {
        type = "execute",
        name = "+ " .. (L["Add Condition"] or "조건 추가"),
        order = condOrderBase,
        width = "full",
        func = function()
            local conds = EnsureConditions(index)
            if conds then
                table.insert(conds, { matchType = "AND", checks = {}, changes = {} })
                DDingUI:UpdateBuffTrackerBar()
                RefreshOptions()
            end
        end,
    }

    local buff = GetTrackedBuff(index)
    local conditions = buff and buff.conditions or {}

    for cIdx, cond in ipairs(conditions) do
        local cBase = condOrderBase + (cIdx * 0.1)
        
        -- Condition Header
        options["tracked" .. index .. "_c" .. cIdx .. "_header"] = {
            type = "description",
            name = "\\n|cffffaa00▼ 조건 " .. cIdx .. "|r",
            order = cBase + 0.01,
            width = "normal",
            fontSize = "medium",
        }
        
        -- Remove Condition
        options["tracked" .. index .. "_c" .. cIdx .. "_remove"] = {
            type = "execute",
            name = "|cffff4444X " .. (L["Remove Condition"] or "조건 삭제") .. "|r",
            order = cBase + 0.02,
            width = "half",
            func = function()
                local c = EnsureConditions(index)
                if c then
                    table.remove(c, cIdx)
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }
        
        -- MatchType
        options["tracked" .. index .. "_c" .. cIdx .. "_matchType"] = {
            type = "select",
            name = L["Trigger Logic"] or "트리거 조건",
            order = cBase + 0.03,
            width = "half",
            values = { ["AND"] = "AND", ["OR"] = "OR" },
            get = function() return conditions[cIdx].matchType or "AND" end,
            set = function(_, val)
                if conditions[cIdx] then
                    conditions[cIdx].matchType = val
                    DDingUI:UpdateBuffTrackerBar()
                end
            end,
        }
        
        -------------------------------------------
        -- CHECKS
        -------------------------------------------
        local checks = cond.checks or {}
        
        for kIdx, chk in ipairs(checks) do
            local chkBase = cBase + 0.04 + (kIdx * 0.001)
            
            options["tracked" .. index .. "_c" .. cIdx .. "_k" .. kIdx .. "_variable"] = {
                type = "select",
                name = "IF",
                order = chkBase,
                width = "half",
                values = {
                    ["time"] = L["Time Left"] or "남은 시간",
                    ["stacks"] = L["Stacks"] or "중첩 수",
                    ["active"] = L["Active"] or "활성 상태",
                },
                get = function() return checks[kIdx].variable or "active" end,
                set = function(_, val)
                    if checks[kIdx] then
                        checks[kIdx].variable = val
                        if val == "active" then
                            checks[kIdx].op = "=="
                            checks[kIdx].value = "true"
                        else
                            checks[kIdx].op = "<="
                            checks[kIdx].value = "5"
                        end
                        DDingUI:UpdateBuffTrackerBar()
                        RefreshOptions()
                    end
                end,
            }
            
            options["tracked" .. index .. "_c" .. cIdx .. "_k" .. kIdx .. "_op"] = {
                type = "select",
                name = "",
                order = chkBase + 0.0001,
                width = "half",
                values = function()
                    local v = checks[kIdx] and checks[kIdx].variable or "active"
                    if v == "active" then return { ["=="] = "==", ["~="] = "~=" } end
                    return { ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=", ["=="] = "==" }
                end,
                get = function() return checks[kIdx].op or "==" end,
                set = function(_, val)
                    if checks[kIdx] then
                        checks[kIdx].op = val
                        DDingUI:UpdateBuffTrackerBar()
                    end
                end,
            }
            
            options["tracked" .. index .. "_c" .. cIdx .. "_k" .. kIdx .. "_val"] = {
                type = "input",
                name = "",
                order = chkBase + 0.0002,
                width = "half",
                get = function() return tostring(checks[kIdx].value or "") end,
                set = function(_, val)
                    if checks[kIdx] then
                        checks[kIdx].value = val
                        DDingUI:UpdateBuffTrackerBar()
                    end
                end,
            }
            
            options["tracked" .. index .. "_c" .. cIdx .. "_k" .. kIdx .. "_remove"] = {
                type = "execute",
                name = "X",
                order = chkBase + 0.0003,
                width = 0.2,
                func = function()
                    if conditions[cIdx] and conditions[cIdx].checks then
                        table.remove(conditions[cIdx].checks, kIdx)
                        DDingUI:UpdateBuffTrackerBar()
                        RefreshOptions()
                    end
                end,
            }
        end
        
        options["tracked" .. index .. "_c" .. cIdx .. "_kAdd"] = {
            type = "execute",
            name = "+ " .. (L["Add Check"] or "조건(If) 추가"),
            order = cBase + 0.049,
            width = "normal",
            func = function()
                if conditions[cIdx] then
                    if not conditions[cIdx].checks then conditions[cIdx].checks = {} end
                    table.insert(conditions[cIdx].checks, { variable = "active", op = "==", value = "true" })
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }
        
        -------------------------------------------
        -- CHANGES
        -------------------------------------------
        local changes = cond.changes or {}
        
        for chgIdx, chg in ipairs(changes) do
            local chgBase = cBase + 0.05 + (chgIdx * 0.001)
            
            options["tracked" .. index .. "_c" .. cIdx .. "_chg" .. chgIdx .. "_prop"] = {
                type = "select",
                name = "THEN",
                order = chgBase,
                width = "normal",
                values = {
                    ["color"] = L["Color Override"] or "색상 변경",
                    ["sound"] = L["Play Sound"] or "사운드 재생",
                    ["glow"] = L["Show Glow"] or "반짝임 효과",
                },
                get = function() return changes[chgIdx].property or "color" end,
                set = function(_, val)
                    if changes[chgIdx] then
                        changes[chgIdx].property = val
                        if val == "color" then changes[chgIdx].value = {1,0,0,1} end
                        if val == "sound" then changes[chgIdx].value = "None" end
                        if val == "glow" then changes[chgIdx].value = true end
                        DDingUI:UpdateBuffTrackerBar()
                        RefreshOptions()
                    end
                end,
            }
            
            if chg.property == "color" then
                options["tracked" .. index .. "_c" .. cIdx .. "_chg" .. chgIdx .. "_color"] = {
                    type = "color",
                    name = "",
                    order = chgBase + 0.0001,
                    width = "half",
                    hasAlpha = true,
                    get = function()
                        local c = changes[chgIdx].value or {1,1,1,1}
                        if type(c) == "table" then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
                        return 1, 1, 1, 1
                    end,
                    set = function(_, r,g,b,a)
                        if changes[chgIdx] then
                            changes[chgIdx].value = {r,g,b,a}
                            DDingUI:UpdateBuffTrackerBar()
                        end
                    end,
                }
            elseif chg.property == "sound" then
                options["tracked" .. index .. "_c" .. cIdx .. "_chg" .. chgIdx .. "_sound"] = {
                    type = "select",
                    name = "",
                    order = chgBase + 0.0001,
                    width = "half",
                    values = function()
                        local vals = {}
                        for _, name in ipairs(LSM:List("sound")) do vals[name] = name end
                        return vals
                    end,
                    sorting = function() return LSM:List("sound") end,
                    get = function() return changes[chgIdx].value or "None" end,
                    set = function(_, val)
                        if changes[chgIdx] then
                            changes[chgIdx].value = val
                            if val and val ~= "None" then
                                local p = LSM:Fetch("sound", val)
                                if p then PlaySoundFile(p, "Master") end
                            end
                            DDingUI:UpdateBuffTrackerBar()
                        end
                    end,
                }
            elseif chg.property == "glow" then
                 options["tracked" .. index .. "_c" .. cIdx .. "_chg" .. chgIdx .. "_glow"] = {
                    type = "toggle",
                    name = "",
                    order = chgBase + 0.0001,
                    width = "half",
                    get = function() return changes[chgIdx].value == true end,
                    set = function(_, val)
                        if changes[chgIdx] then
                            changes[chgIdx].value = val
                            DDingUI:UpdateBuffTrackerBar()
                        end
                    end,
                }
            end
            
            options["tracked" .. index .. "_c" .. cIdx .. "_chg" .. chgIdx .. "_remove"] = {
                type = "execute",
                name = "X",
                order = chgBase + 0.0002,
                width = 0.2,
                func = function()
                    if conditions[cIdx] and conditions[cIdx].changes then
                        table.remove(conditions[cIdx].changes, chgIdx)
                        DDingUI:UpdateBuffTrackerBar()
                        RefreshOptions()
                    end
                end,
            }
        end
        
        options["tracked" .. index .. "_c" .. cIdx .. "_chgAdd"] = {
            type = "execute",
            name = "+ " .. (L["Add Change"] or "동작(Then) 추가"),
            order = cBase + 0.059,
            width = "normal",
            func = function()
                if conditions[cIdx] then
                    if not conditions[cIdx].changes then conditions[cIdx].changes = {} end
                    table.insert(conditions[cIdx].changes, { property = "color", value = {1,0,0,1} })
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }
        
    end
'''
    
    updated_lines = lines[:start_idx] + [new_code] + lines[end_idx:]
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(updated_lines)
    print('Conditions block successfully rewritten!')
else:
    print('Boundaries not found!')
