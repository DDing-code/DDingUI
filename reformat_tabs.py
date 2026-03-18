file_path = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Config\BuffTrackerOptions.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

import re

old_tab_alloc = '''    local tabOptions = {
        triggerTab = { type = "group", name = L["Trigger"] or "트리거", order = 1, args = {} },
        displayTab = { type = "group", name = L["Display"] or "디스플레이", order = 2, args = {} },
        conditionsTab = { type = "group", name = L["Conditions"] or "조건 및 동작", order = 3, args = {} },
    }
    
    for k, v in pairs(flatOptions) do
        -- order-based distribution heuristic
        -- base header elements and very generic settings go to trigger
        local relativeOrder = v.order - orderBase
        
        if relativeOrder < 1 then
            -- Headers and delete buttons
            tabOptions.triggerTab.args[k] = v
        elseif k:find("alert") or relativeOrder >= 8 then
            -- Alerts and Conditions
            tabOptions.conditionsTab.args[k] = v
        elseif k:find("cooldownID") or k:find("spellID") or k:find("trackingMode") or k:find("dynamic") or k:find("maxStacks") or k:find("stackDuration") or k:find("hideWhenZero") or k:find("resetOnCombatEnd") then
            -- Trigger logics
            tabOptions.triggerTab.args[k] = v
        else
            -- Visual settings (displayType, widths, heights, colors, fonts, offsets, etc)
            tabOptions.displayTab.args[k] = v
        end
        
        -- Override order to avoid huge gaps inside individual tabs
        v.order = relativeOrder
    end'''

new_tab_alloc = '''    local tabOptions = {
        displayTab = { type = "group", name = "🎨 디스플레이", order = 1, desc = "|cff00ffff어떻게 보일 것인가?|r", args = {} },
        triggerTab = { type = "group", name = "⚙️ 트리거", order = 2, desc = "|cff00ffff언제 켜질 것인가?|r", args = {} },
        conditionsTab = { type = "group", name = "🔮 조건 및 동작", order = 3, desc = "|cff00ffff상황에 따라 어떻게 변할 것인가?|r", args = {} },
        loadTab = { type = "group", name = "💾 불러오기", order = 4, desc = "|cff00ffff이 트래커를 언제 작동할 것인가?|r", args = {} },
    }
    
    for k, v in pairs(flatOptions) do
        local relativeOrder = v.order - orderBase
        
        if relativeOrder < 1 then
            tabOptions.displayTab.args[k] = v
        elseif k:find("alert") or relativeOrder >= 8 then
            tabOptions.conditionsTab.args[k] = v
        elseif k:find("onlyInCombat") or k:find("hideWhenZero") or k:find("resetOnCombatEnd") or k:find("hideFromCDM") then
            tabOptions.loadTab.args[k] = v
        elseif k:find("cooldownID") or k:find("spellID") or k:find("trackingMode") or k:find("dynamic") or k:find("maxStacks") or k:find("stackDuration") then
            tabOptions.triggerTab.args[k] = v
        else
            tabOptions.displayTab.args[k] = v
        end
        
        v.order = relativeOrder
    end'''

if old_tab_alloc in text:
    text = text.replace(old_tab_alloc, new_tab_alloc)
    print("Tab layout updated.")
else:
    print("Tab layout pattern not found. Proceeding with text replacements.")

text = text.replace('["AND"] = "AND (모두 만족)"', '["AND"] = "AND (모든 조건 달성시)"')
text = text.replace('["OR"] = "OR (하나라도)"', '["OR"] = "OR (하나라도 충족시)"')

text = text.replace('["time"] = L["Time Left"] or "남은 시간",', '["time"] = "⏳ 남은 시간 기준",')
text = text.replace('["stacks"] = L["Stacks"] or "중첩 수",', '["stacks"] = "🔢 중첩 개수 기준",')
text = text.replace('["active"] = L["Active"] or "활성 상태",', '["active"] = "💡 켜짐/꺼짐 상태",')

text = text.replace('return { ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=", ["=="] = "==" }', 'return { ["<"] = "< (미만)", ["<="] = "<= (이하)", [">"] = "> (초과)", [">="] = ">= (이상)", ["=="] = "== (같음)" }')
text = text.replace('return { ["=="] = "==", ["~="] = "~=" }', 'return { ["=="] = "== (켜졌을 때)", ["~="] = "~= (꺼졌을 때)" }')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)
print("Option labels updated for human-friendly UX.")
