import re

file_path = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Config\BuffTrackerOptions.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# Insert wizard state variables
wizard_vars = '''
local wizardState = { trackType = "buff", displayType = "icon", spellID = "", target = "player" }
local searchQuery = ""
'''

if 'local wizardState =' not in text:
    text = text.replace('local GetTrackedBuffs = function()', wizard_vars + '\nlocal GetTrackedBuffs = function()')

# Rewrite CreateTrackedBuffListOptions to include Wizard, Search, Import/Export
find_pattern = r'local function CreateTrackedBuffListOptions\(baseOrder\)\s*(.*?)\s*return options\s*end'

new_func = r'''    local options = {}

    local rootCfg = DDingUI.db.profile.buffTrackerBar
    if not rootCfg.trackerGroups then rootCfg.trackerGroups = { Group1 = { name = "Group1" } } end

    local trackedBuffs = GetTrackedBuffs()
    local buffsByGroup = {}
    
    for groupKey, _ in pairs(rootCfg.trackerGroups) do
        buffsByGroup[groupKey] = {}
    end
    
    for i, buff in ipairs(trackedBuffs) do
        local g = buff.group or "Group1"
        if not buffsByGroup[g] then
            buffsByGroup[g] = {}
        end
        table.insert(buffsByGroup[g], { index = i, buff = buff })
    end

    local currentOrder = 1
    
    -- 1. Toolbar Node (Overview + Search + Import/Export)
    options["overview"] = {
        type = "group",
        name = "🏠 " .. (L["Overview"] or "개요 및 도구"),
        order = currentOrder,
        args = {
            search = {
                type = "input",
                name = "🔍 검색바",
                desc = "트래커 이름을 검색하여 필터링합니다.",
                order = 1,
                width = "full",
                get = function() return searchQuery end,
                set = function(_, val) searchQuery = (val or ""):lower(); RefreshOptions() end,
            },
            desc = {
                type = "description",
                name = "\n|cffffcc00내 추적기 시작하기|r\n\n좌측의 트리에서 그룹 또는 개별 트래커를 찾아 상세 설정을 열어보세요.\n검색바를 이용해 트래커를 빠르게 찾을 수 있습니다.\n\n새로운 트래커를 만드려면 바로 아래의 [✨ 마법사를 통한 빠른 생성] 메뉴를 이용하세요!\n",
                order = 2,
                fontSize = "medium"
            },
            exportBtn = {
                type = "execute",
                name = "📦 프로필 내보내기",
                order = 3,
                width = "normal",
                func = function() print(CDM_PREFIX .. "문자열 내보내기/가져오기 기능은 플러그인 모듈에서 추후 지원됩니다.") end,
            },
            importBtn = {
                type = "execute",
                name = "📥 프로필 가져오기",
                order = 4,
                width = "normal",
                func = function() print(CDM_PREFIX .. "문자열 내보내기/가져오기 기능은 플러그인 모듈에서 추후 지원됩니다.") end,
            },
        }
    }
    currentOrder = currentOrder + 1

    -- 2. Wizard Node
    options["wizard"] = {
        type = "group",
        name = "|cff00ff00✨ 새 트래커 (마법사)|r",
        order = currentOrder,
        args = {
            header = { type = "header", name = "초보자를 위한 빠른 생성 마법사", order = 1 },
            desc = { type = "description", name = "복잡한 설정 없이 몇 번의 클릭만으로 나만의 커스텀 트래커를 손쉽게 생성해보세요!\n\n만약 주문 번호를 찾기 어렵다면 [스킬 카탈로그] 탭을 활용해 주문 번호를 복사하거나 자동으로 생성할 수 있습니다.\n", order = 2, fontSize = "medium" },
            
            step1Desc = { type = "description", name = "|cffffcc001단계. 어떤 것을 추적할까요?|r", order = 3 },
            trackType = {
                type = "select", name = "추적 타입", order = 4, width = "normal",
                values = { buff = "버프 (Buff)", debuff = "디버프 (Debuff)", cd = "쿨타임 (Cooldown)", manual = "수동 스택 바 (Manual)" },
                get = function() return wizardState.trackType end,
                set = function(_, val) wizardState.trackType = val; RefreshOptions() end,
            },
            targetType = {
                type = "select", name = "추적 대상", order = 5, width = "half",
                values = { player = "나 (Player)", target = "대상 (Target)", pet = "소환수 (Pet)" },
                get = function() return wizardState.target end,
                set = function(_, val) wizardState.target = val; RefreshOptions() end,
            },
            spellID = {
                type = "input", name = "주문 번호 (Spell ID)", desc = "추적할 주문 번호(숫자)를 입력하세요.", order = 6, width = "normal",
                get = function() return wizardState.spellID end,
                set = function(_, val) wizardState.spellID = val; RefreshOptions() end,
            },
            
            sep = { type = "description", name = "\n", order = 7, width = "full" },
            step2Desc = { type = "description", name = "|cffffcc002단계. 어떤 시각적 형태로 표시할까요?|r", order = 8 },
            displayType = {
                type = "select", name = "디자인", order = 9, width = "normal",
                values = { icon = "상자 아이콘 (Icon)", bar = "길다란 진행 바 (Bar)", ring = "원형 바 (Ring)", text = "텍스트 크게 (Text)" },
                get = function() return wizardState.displayType end,
                set = function(_, val) wizardState.displayType = val; RefreshOptions() end,
            },
            
            sep2 = { type = "description", name = "\n", order = 10, width = "full" },
            createBtn = {
                type = "execute", name = "✅ 마법사로 트래커 생성하기", order = 11, width = "full",
                func = function()
                    local spellIdNum = tonumber(wizardState.spellID)
                    if not spellIdNum or spellIdNum <= 0 then
                        print(CDM_PREFIX .. "마법사: 올바른 주문 번호(Spell ID)를 숫자로 입력해주세요!")
                        return
                    end
                    DDingUI.AddTrackedBuff(spellIdNum, nil, wizardState.displayType)
                    -- 마법사 초기화
                    wizardState.spellID = ""
                    RefreshOptions()
                    print(CDM_PREFIX .. "마법사: 성공적으로 트래커가 생성되었습니다!")
                end,
            }
        }
    }
    currentOrder = currentOrder + 1

    -- Create tree nodes for each Tracker Group
    for groupKey, groupConfig in pairs(rootCfg.trackerGroups) do
        local groupBuffs = buffsByGroup[groupKey] or {}
        local isDefault = (groupKey == "Group1")
        
        -- Search filtering
        local visibleBuffs = {}
        for _, bData in ipairs(groupBuffs) do
            local buffName = bData.buff.name or "Unknown"
            if bData.buff.spellID and bData.buff.spellID > 0 then
                local spellName = GetSpellInfo(bData.buff.spellID)
                if spellName then buffName = spellName end
            end
            bData.computedName = buffName
            if searchQuery == "" or buffName:lower():find(searchQuery) then
                table.insert(visibleBuffs, bData)
            end
        end

        local groupNode = {
            type = "group",
            name = (groupConfig.name or groupKey) .. (isDefault and " (기본)" or ""),
            order = currentOrder,
            hidden = function() return searchQuery ~= "" and #visibleBuffs == 0 end, -- 검색결과 없을경우 폴더 숨김
            args = {
                header = {
                    type = "description",
                    name = "|cffffaa00" .. (groupConfig.name or groupKey) .. "|r 그룹: |cff888888" .. #visibleBuffs .. " items|r\n\n그룹의 위치 및 정렬 설정은 우측 탭에서 진행하세요.",
                    order = 1,
                    width = "full"
                }
            }
        }

        if #visibleBuffs == 0 then
            groupNode.args["empty"] = {
                type = "description",
                name = "|cffaaaaaa(비어 있음)|r",
                order = 2,
                width = "full",
            }
        else
            -- Sub-nodes for each buff
            for i, bData in ipairs(visibleBuffs) do
                local buffId = tostring(bData.index)
                local buffName = bData.computedName
                
                local iconText = bData.buff.icon and string.format("|T%d:16:16:0:0|t ", bData.buff.icon) or ""
                local displayTypeMap = { bar="[오라 바] ", icon="[아이콘] ", ring="[원형 바] ", text="[텍스트] ", sound="[사운드] " }
                local prefix = displayTypeMap[bData.buff.displayType] or ""
                
                local buffNode = {
                    type = "group",
                    name = iconText .. prefix .. buffName,
                    desc = "ID: " .. (bData.buff.cooldownID or "-") .. "\n\n클릭하여 상세 설정을 엽니다.",
                    order = 2 + i,
                    childGroups = "tab", -- Here is where we make the trigger/display/conditions/load show as tabs
                    args = CreateTrackedBuffOptions(bData.index, 1) -- Inject the 4-tab layout
                }
                
                groupNode.args["buff_" .. buffId] = buffNode
            end
        end
        
        options["group_" .. groupKey] = groupNode
        currentOrder = currentOrder + 1
    end
'''

def repl(m):
    return new_func

text = re.sub(find_pattern, repl, text, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print('Wizard and layout refactor executed.')
