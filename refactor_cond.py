# refactor_conditions.py
import re

file_path = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Config\BuffTrackerOptions.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

old_start_str = "for cIdx, cond in ipairs(conditions) do"
old_end_str = "options[\"tracked\" .. index .. \"_spacer\"] ="

start_idx = content.find(old_start_str)
end_idx = content.find(old_end_str)

if start_idx == -1 or end_idx == -1:
    print("Could not find start or end index.")
    exit(1)

new_block = """    for cIdx, cond in ipairs(conditions) do
        local cBase = condOrderBase + (cIdx * 0.1)
        
        local cArgs = {}
        options["tracked" .. index .. "_c" .. cIdx .. "_group"] = {
            type = "group",
            name = "|cffffaa00▼ " .. (L["Condition"] or "조건") .. " " .. cIdx .. "|r",
            inline = true,
            order = cBase,
            args = cArgs,
        }
        
        -- Move Up Condition
        cArgs["moveup"] = {
            type = "execute",
            name = "▲ " .. (L["Move Up"] or "위"),
            order = 1,
            width = "half",
            hidden = function() return cIdx == 1 end,
            func = function()
                local c = EnsureConditions(index)
                if c and cIdx > 1 then
                    -- Swap with previous
                    c[cIdx], c[cIdx - 1] = c[cIdx - 1], c[cIdx]
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }
        
        -- Move Down Condition
        cArgs["movedown"] = {
            type = "execute",
            name = "▼ " .. (L["Move Down"] or "아래"),
            order = 2,
            width = "half",
            hidden = function() return cIdx == #conditions end,
            func = function()
                local c = EnsureConditions(index)
                if c and cIdx < #conditions then
                    -- Swap with next
                    c[cIdx], c[cIdx + 1] = c[cIdx + 1], c[cIdx]
                    DDingUI:UpdateBuffTrackerBar()
                    RefreshOptions()
                end
            end,
        }
        
        -- MatchType
        cArgs["matchType"] = {
            type = "select",
            name = L["Trigger Logic"] or "트리거 조건",
            order = 3,
            width = "half",
            values = { ["AND"] = "AND (모두 만족)", ["OR"] = "OR (하나라도)" },
            get = function() return conditions[cIdx].matchType or "AND" end,
            set = function(_, val)
                if conditions[cIdx] then
                    conditions[cIdx].matchType = val
                    DDingUI:UpdateBuffTrackerBar()
                end
            end,
        }
        
        -- Remove Condition
        cArgs["remove"] = {
            type = "execute",
            name = "|cffff4444[ X UI_삭제 ]|r",
            order = 4,
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
        
        -- Separator
        cArgs["sep1"] = { type = "description", name = "", order = 5, width = "full" }
        
        -------------------------------------------
        -- CHECKS
        -------------------------------------------
        local checks = cond.checks or {}
        
        for kIdx, chk in ipairs(checks) do
            local chkBase = 10 + (kIdx * 0.1)
            
            cArgs["k" .. kIdx .. "_variable"] = {
                type = "select",
                name = "|cff00ff00[ IF ] 검사 " .. kIdx .. "|r",
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
            
            cArgs["k" .. kIdx .. "_op"] = {
                type = "select",
                name = "연산자",
                order = chkBase + 0.01,
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
            
            cArgs["k" .. kIdx .. "_val"] = {
                type = "input",
                name = "값",
                order = chkBase + 0.02,
                width = "half",
                get = function() return tostring(checks[kIdx].value or "") end,
                set = function(_, val)
                    if checks[kIdx] then
                        checks[kIdx].value = val
                        DDingUI:UpdateBuffTrackerBar()
                    end
                end,
            }
            
            cArgs["k" .. kIdx .. "_remove"] = {
                type = "execute",
                name = "X",
                order = chkBase + 0.03,
                width = 0.25,
                func = function()
                    if conditions[cIdx] and conditions[cIdx].checks then
                        table.remove(conditions[cIdx].checks, kIdx)
                        DDingUI:UpdateBuffTrackerBar()
                        RefreshOptions()
                    end
                end,
            }
        end
        
        cArgs["kAdd"] = {
            type = "execute",
            name = "|cff00ff00+ " .. (L["Add Check"] or "단일 조건 추가") .. "|r",
            order = 19.9,
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
        
        -- Separator
        cArgs["sep2"] = { type = "description", name = " ", order = 20, width = "full" }
        
        -------------------------------------------
        -- CHANGES
        -------------------------------------------
        local changes = cond.changes or {}
        
        for chgIdx, chg in ipairs(changes) do
            local chgBase = 30 + (chgIdx * 0.1)
            
            cArgs["chg" .. chgIdx .. "_prop"] = {
                type = "select",
                name = "|cffffaa00[ THEN ] 동작 " .. chgIdx .. "|r",
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
                cArgs["chg" .. chgIdx .. "_color"] = {
                    type = "color",
                    name = "색상 설정",
                    order = chgBase + 0.01,
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
                cArgs["chg" .. chgIdx .. "_sound"] = {
                    type = "select",
                    name = "효과음 선택",
                    order = chgBase + 0.01,
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
                 cArgs["chg" .. chgIdx .. "_glow"] = {
                    type = "toggle",
                    name = "반짝임 On/Off",
                    order = chgBase + 0.01,
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
            
            cArgs["chg" .. chgIdx .. "_remove"] = {
                type = "execute",
                name = "X",
                order = chgBase + 0.02,
                width = 0.25,
                func = function()
                    if conditions[cIdx] and conditions[cIdx].changes then
                        table.remove(conditions[cIdx].changes, chgIdx)
                        DDingUI:UpdateBuffTrackerBar()
                        RefreshOptions()
                    end
                end,
            }
        end
        
        cArgs["chgAdd"] = {
            type = "execute",
            name = "|cffffaa00+ " .. (L["Add Action"] or "단일 동작 추가") .. "|r",
            order = 39.9,
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
    -- Separator line (only show when buff exists AND is expanded)
    """

full_new_content = content[:start_idx] + new_block + content[end_idx:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(full_new_content)

print('Conditions refactored successfully to inline groups!')
