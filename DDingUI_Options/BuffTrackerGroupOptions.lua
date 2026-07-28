local _, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local context = ns.BuffTrackerGroupOptionsContext
if not context then return end

local GetTrackedBuffs = context.GetTrackedBuffs
local RefreshOptions = context.RefreshOptions

-- Create group settings options (for right panel when group is selected)
function DDingUI.CreateGroupOptions(groupIdx)
    local trackedBuffs = GetTrackedBuffs()
    local group = trackedBuffs[groupIdx]
    if not group or not group.isGroup then return {} end

    local gs = group.groupSettings or {}
    local options = {}

    -- ─── Group Name ───
    options["groupName"] = {
        type = "input",
        name = L["Group Name"] or "Group Name",
        order = 0.1,
        width = "double",
        get = function() return group.name or "" end,
        set = function(_, val)
            group.name = val
            RefreshOptions()
        end,
    }
    options["groupEnabled"] = {
        type = "toggle",
        name = L["Enabled"] or "Enabled",
        order = 0.2,
        width = "full",
        get = function() return not group.disabled end,
        set = function(_, val)
            group.disabled = not val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ─── Growth / Layout ───
    options["layoutHeader"] = {
        type = "header",
        name = L["Layout"] or "Layout",
        order = 1,
    }
    options["growthDirection"] = {
        type = "select",
        name = L["Growth Direction"] or "Growth Direction",
        order = 1.1, width = "normal",
        values = {
            DOWN = L["Down"] or "Down", UP = L["Up"] or "Up",
            LEFT = L["Left"] or "Left", RIGHT = L["Right"] or "Right",
        },
        get = function() return gs.growthDirection or "DOWN" end,
        set = function(_, val)
            group.groupSettings.growthDirection = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["growthSpacing"] = {
        type = "range",
        name = L["Spacing"] or "Spacing",
        order = 1.2, width = "normal",
        min = 0, max = 50, step = 1,
        get = function() return gs.growthSpacing or 2 end,
        set = function(_, val)
            group.groupSettings.growthSpacing = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["sortMode"] = {
        type = "select",
        name = L["Sort Mode"] or "Sort Mode",
        desc = L["How children are sorted at runtime"] or "How children are sorted at runtime",
        order = 1.3, width = "normal",
        values = {
            none = L["Manual (drag order)"] or "Manual",
            priority = L["Priority"] or "Priority",
            duration = L["Remaining Duration"] or "Duration",
            name = L["Name"] or "Name",
        },
        get = function() return gs.sortMode or "none" end,
        set = function(_, val)
            group.groupSettings.sortMode = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ─── Position & Anchor ───
    options["positionHeader"] = {
        type = "header",
        name = L["Position & Anchor"] or "Position & Anchor",
        order = 2,
    }
    options["attachTo"] = {
        type = "select",
        name = L["Attach To"] or "Attach To",
        order = 2.1, width = "double",
        values = function()
            local opts = {}
            opts["UIParent"] = L["Screen (UIParent)"] or "Screen (UIParent)"
            if DDingUI.db.profile.unitFrames and DDingUI.db.profile.unitFrames.enabled then
                opts["DDingUI_Player"] = L["Player Frame (Custom)"] or "Player Frame (Custom)"
            end
            opts["PlayerFrame"] = L["Default Player Frame"] or "Default Player Frame"

            if DDingUI.GetViewerOptions then
                local viewerOptions = DDingUI:GetViewerOptions()
                for key, label in pairs(viewerOptions or {}) do
                    opts[key] = label
                end
            end

            local current = group.groupSettings and group.groupSettings.attachTo
            if current and current ~= "" and not opts[current] then
                local knownLabels = {
                    DDingUI_Group_Cooldowns = L["Essential Cooldowns"] or "Essential Cooldowns",
                    DDingUI_Group_Buffs = L["Buff Icons"] or "Buff Icons",
                    DDingUI_Group_Utility = L["Utility Cooldowns"] or "Utility Cooldowns",
                }
                opts[current] = knownLabels[current] or current
            end
            return opts
        end,
        get = function()
            return (group.groupSettings and group.groupSettings.attachTo) or "UIParent"
        end,
        set = function(_, val)
            group.groupSettings.attachTo = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["anchorPoint"] = {
        type = "select",
        name = L["Anchor Point"] or "Anchor Point",
        order = 2.2, width = "normal",
        values = {
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOP"] = L["Top"] or "Top",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["LEFT"] = L["Left"] or "Left",
            ["CENTER"] = L["Center"] or "Center",
            ["RIGHT"] = L["Right"] or "Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function() return gs.anchorPoint or "CENTER" end,
        set = function(_, val)
            group.groupSettings.anchorPoint = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["selfPoint"] = {
        type = "select",
        name = L["Self Point"] or "Self Point",
        order = 2.3, width = "normal",
        values = {
            ["TOPLEFT"] = L["Top Left"] or "Top Left",
            ["TOP"] = L["Top"] or "Top",
            ["TOPRIGHT"] = L["Top Right"] or "Top Right",
            ["LEFT"] = L["Left"] or "Left",
            ["CENTER"] = L["Center"] or "Center",
            ["RIGHT"] = L["Right"] or "Right",
            ["BOTTOMLEFT"] = L["Bottom Left"] or "Bottom Left",
            ["BOTTOM"] = L["Bottom"] or "Bottom",
            ["BOTTOMRIGHT"] = L["Bottom Right"] or "Bottom Right",
        },
        get = function() return gs.selfPoint or "CENTER" end,
        set = function(_, val)
            group.groupSettings.selfPoint = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["offsetX"] = {
        type = "range",
        name = L["X Offset"] or "X Offset",
        order = 2.4, width = "normal",
        min = -500, max = 500, step = 1,
        get = function() return gs.offsetX or 0 end,
        set = function(_, val)
            group.groupSettings.offsetX = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["offsetY"] = {
        type = "range",
        name = L["Y Offset"] or "Y Offset",
        order = 2.5, width = "normal",
        min = -500, max = 500, step = 1,
        get = function() return gs.offsetY or 0 end,
        set = function(_, val)
            group.groupSettings.offsetY = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["frameStrata"] = {
        type = "select",
        name = L["Frame Strata"] or "Frame Strata",
        order = 2.6, width = "normal",
        values = {
            BACKGROUND = "BACKGROUND", LOW = "LOW", MEDIUM = "MEDIUM", HIGH = "HIGH", DIALOG = "DIALOG",
        },
        get = function() return gs.frameStrata or "MEDIUM" end,
        set = function(_, val)
            group.groupSettings.frameStrata = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ─── Load Conditions ───
    options["loadHeader"] = {
        type = "header",
        name = L["Load Conditions"] or "Load Conditions",
        order = 3,
    }
    options["loadCombatOnly"] = {
        type = "toggle",
        name = L["Combat Only"] or "Combat Only",
        desc = L["Only show this group during combat"] or "Only show this group during combat",
        order = 3.1, width = "full",
        get = function() return gs.loadCombatOnly or false end,
        set = function(_, val)
            group.groupSettings.loadCombatOnly = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["loadInstanceType"] = {
        type = "select",
        name = L["Instance Type"] or "Instance Type",
        order = 3.2, width = "normal",
        values = {
            all = L["All"] or "All",
            dungeon = L["Dungeon"] or "Dungeon",
            raid = L["Raid"] or "Raid",
            arena = L["Arena/BG"] or "Arena/BG",
            world = L["Open World"] or "Open World",
        },
        get = function() return gs.loadInstanceType or "all" end,
        set = function(_, val)
            group.groupSettings.loadInstanceType = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    -- ─── Children Management ───
    options["childrenHeader"] = {
        type = "header",
        name = L["Children"] or "Children",
        order = 4,
    }
    local children = group.controlledChildren or {}
    local allTrackedBuffs = GetTrackedBuffs()
    if #children == 0 then
        options["noChildren"] = {
            type = "description",
            name = "|cff888888" .. (L["No children in this group. Right-click a tracker and select 'Move to Group' to add."] or "No children. Right-click a tracker → Move to Group.") .. "|r",
            order = 4.1,
        }
    else
        for ci, childIdx in ipairs(children) do
            local child = allTrackedBuffs[childIdx]
            if child then
                local childName = child.name or "?"
                if child.spellID and child.spellID > 0 then
                    local sn = C_Spell.GetSpellName(child.spellID)
                    if sn then childName = sn end
                end
                options["child" .. ci .. "_name"] = {
                    type = "description",
                    name = "  " .. ci .. ". " .. childName .. "  |cff888888[" .. (child.displayType or "bar"):upper() .. "]|r",
                    order = 4 + ci * 0.1,
                    fontSize = "medium",
                }
            end
        end
    end
    -- ─── Conditional Actions (Action Set 구조) ───
    -- DB 기본값 보장
    if not group.groupSettings.conditionalActions then
        group.groupSettings.conditionalActions = {
            enabled = false,
            sets = {},
        }
    end
    local ca = group.groupSettings.conditionalActions

    -- 마이그레이션: 기존 flat 구조 → sets 구조
    if ca.triggers and not ca.sets then
        ca.sets = {{
            logic = ca.logic or "and",
            triggers = ca.triggers,
            actions = ca.actions or {},
        }}
        ca.triggers = nil
        ca.actions = nil
        ca.logic = nil
    end
    if not ca.sets then ca.sets = {} end

    -- 공용 드롭다운 데이터
    local childValues = {}
    for ci, childIdx in ipairs(children) do
        local child = allTrackedBuffs[childIdx]
        if child then
            local n = child.name or "?"
            if child.spellID and child.spellID > 0 then
                local sn = C_Spell.GetSpellName(child.spellID)
                if sn then n = sn end
            end
            childValues[ci] = ci .. ". " .. n
        end
    end

    local conditionValues = {}
    local CA_MODULE = DDingUI.ConditionalActions
    if CA_MODULE and CA_MODULE.CONDITIONS then
        for _, cond in ipairs(CA_MODULE.CONDITIONS) do
            conditionValues[cond.id] = cond.name
        end
    end

    local actionTypeValues = {}
    local actionTypeNames = {}
    if CA_MODULE and CA_MODULE.ACTION_TYPES then
        for _, at in ipairs(CA_MODULE.ACTION_TYPES) do
            actionTypeValues[at.id] = at.name
            actionTypeNames[at.id] = at.name
        end
    end

    local barTargetValues = {}
    -- 기본 바 대상 (자원바/시전바)
    if CA_MODULE and CA_MODULE.BAR_TARGETS then
        for _, bt in ipairs(CA_MODULE.BAR_TARGETS) do
            barTargetValues[bt.id] = bt.name
        end
    end
    -- BuffTracker 바 대상 추가: 자식 바들
    for ci, childIdx in ipairs(children) do
        local child = allTrackedBuffs[childIdx]
        if child then
            local n = child.name or "?"
            if child.spellID and child.spellID > 0 then
                local sn = C_Spell.GetSpellName(child.spellID)
                if sn then n = sn end
            end
            barTargetValues["bt_child_" .. ci] = "TrackerBar: " .. n
        end
    end

    -- 헤더
    options["actionsHeader"] = {
        type = "description",
        name = "|cffffa300" .. (L["Conditional Actions"] or "Conditional Actions") .. "|r",
        order = 5,
        fontSize = "large",
        width = "full",
    }
    options["actionsEnabled"] = {
        type = "toggle",
        name = L["Enable Actions"] or "Enable Actions",
        order = 5.1, width = "full",
        get = function() return ca.enabled end,
        set = function(_, val) ca.enabled = val; RefreshOptions() end,
    }

    -- ─── 각 Action Set 렌더링 ───
    for si, set in ipairs(ca.sets) do
        local setOrder = 5.2 + si * 0.5
        local setArgs = {}

        -- ── 세트 내 Triggers 섹션 ──
        setArgs["triggersLabel"] = {
            type = "description",
            name = "|cff88ccff" .. (L["Triggers"] or "Triggers") .. "|r",
            order = 1,
            fontSize = "medium",
            width = "full",
        }
        setArgs["triggerLogic"] = {
            type = "select",
            name = L["Trigger Logic"] or "Logic",
            order = 1.1, width = "half",
            values = { ["and"] = "AND", ["or"] = "OR" },
            get = function() return set.logic or "and" end,
            set = function(_, val) set.logic = val end,
        }

        -- 트리거 목록
        for ti, trigger in ipairs(set.triggers or {}) do
            local tOrder = 1.2 + ti * 0.05

            setArgs["t" .. ti .. "_source"] = {
                type = "select",
                name = "#" .. ti .. " " .. (L["Source"] or "Source"),
                order = tOrder, width = "half",
                values = childValues,
                get = function() return trigger.childIndex or 1 end,
                set = function(_, val) trigger.childIndex = val; trigger.source = "child" end,
            }
            setArgs["t" .. ti .. "_cond"] = {
                type = "select",
                name = L["Condition"] or "Condition",
                order = tOrder + 0.01, width = "normal",
                values = conditionValues,
                get = function() return trigger.condition or "active" end,
                set = function(_, val)
                    trigger.condition = val
                    -- [FIX] duration 조건 선택 시 maxDuration 자동 채우기 (툴팁에서 추출)
                    if (val == "duration_gte" or val == "duration_lte") and not trigger.maxDuration then
                        local targetSpellID = nil
                        -- 트리거 대상 버프의 spellID 찾기
                        local childIdx = children[trigger.childIndex or 1]
                        local buff = childIdx and allTrackedBuffs[childIdx]
                        if buff then
                            targetSpellID = buff.spellID
                            if (not targetSpellID or targetSpellID == 0) and buff.cooldownID and buff.cooldownID > 0 then
                                targetSpellID = buff.cooldownID
                            end
                        end
                        if targetSpellID and targetSpellID > 0 then
                            local autoD = DDingUI.ExtractDurationFromTooltip and DDingUI.ExtractDurationFromTooltip(targetSpellID)
                            if autoD and autoD > 0 then
                                trigger.maxDuration = autoD
                            end
                        end
                    end
                    RefreshOptions()
                end,
            }
            setArgs["t" .. ti .. "_value"] = {
                type = "range",
                name = L["Value"] or "Value",
                order = tOrder + 0.02, width = "half",
                min = 0,
                -- [FIX] 커스텀 렌더러(CreateRange)가 함수형 max/step을 지원하지 않음
                -- math.min(함수, 숫자) → 에러 → 이후 위젯(maxDuration) 렌더링 중단
                -- duration 조건에서만 이 위젯이 표시되므로 duration 기준 값 사용
                max = 120,
                step = 0.5,
                get = function() return trigger.value or 0 end,
                set = function(_, val) trigger.value = val end,
                hidden = function()
                    local c = trigger.condition or "active"
                    return c ~= "duration_gte" and c ~= "duration_lte"
                end,
            }
            -- 전체 버프 지속시간 (duration 조건에서만 표시 - 수동 카운트다운용)
            -- 이 값을 설정하면 API 대신 수동으로 지속시간을 추적 (전투 중 secret value 우회)
            -- duration 조건 선택 시 툴팁에서 자동 추출하여 채움 (수동 수정 가능)
            setArgs["t" .. ti .. "_maxDuration"] = {
                type = "input",
                name = L["Buff Total Duration (sec)"] or "전체 버프 지속시간 (초)",
                desc = "수동 카운트다운용 전체 지속시간 (초). 전투 중 시크릿밸류 우회. 0 또는 빈칸 = API 사용.",
                order = tOrder + 0.025, width = "half",
                get = function() return tostring(trigger.maxDuration or "") end,
                set = function(_, val)
                    local num = tonumber(val)
                    trigger.maxDuration = (num and num > 0) and num or nil
                end,
                hidden = function()
                    local c = trigger.condition or "active"
                    return c ~= "duration_gte" and c ~= "duration_lte"
                end,
            }
            local tiCapture = ti
            setArgs["t" .. ti .. "_delete"] = {
                type = "execute",
                name = "|cffff4444X|r",
                order = tOrder + 0.03, width = "half",
                hidden = function() return not set.triggers or #set.triggers <= 1 end,
                func = function()
                    table.remove(set.triggers, tiCapture)
                    RefreshOptions()
                end,
            }
        end

        -- 트리거 추가 버튼
        setArgs["trigger_add"] = {
            type = "execute",
            name = "+ " .. (L["Add Trigger"] or "Add Trigger"),
            order = 1.99, width = "normal",
            func = function()
                if not set.triggers then set.triggers = {} end
                table.insert(set.triggers, {
                    source = "child",
                    childIndex = 1,
                    condition = "active",
                    value = 0,
                })
                RefreshOptions()
            end,
        }

        -- ── 세트 내 Actions 섹션 ──
        setArgs["actionsLabel"] = {
            type = "description",
            name = "\n|cff88ccff" .. (L["Actions"] or "Actions") .. "|r",
            order = 3,
            fontSize = "medium",
            width = "full",
        }

        -- 동작 목록 (flat 위젯, prefix로 구분)
        for ai, action in ipairs(set.actions or {}) do
            local aOrder = 3.1 + ai * 0.1
            local typeName = actionTypeNames[action.type] or action.type or "?"
            local p = "a" .. ai .. "_"  -- prefix

            -- 동작 라벨 (구분선)
            setArgs[p .. "label"] = {
                type = "description",
                name = "|cffcccccc" .. (L["Action"] or "Action") .. " " .. ai .. " (" .. typeName .. ")|r",
                order = aOrder,
                fontSize = "medium",
                width = "full",
            }

            setArgs[p .. "type"] = {
                type = "select",
                name = L["Type"] or "Type",
                order = aOrder + 0.01, width = "normal",
                values = actionTypeValues,
                get = function() return action.type or "bar_color" end,
                set = function(_, val)
                    action.type = val
                    RefreshOptions()
                end,
            }
            setArgs[p .. "target"] = {
                type = "select",
                name = L["Target Bar"] or "Target Bar",
                order = aOrder + 0.02, width = "normal",
                values = barTargetValues,
                get = function() return action.target or "PrimaryPowerBar" end,
                set = function(_, val) action.target = val end,
                hidden = function()
                    return action.type ~= "bar_color" and action.type ~= "bar_glow"
                end,
            }
            setArgs[p .. "color"] = {
                type = "color",
                name = L["Color"] or "Color",
                order = aOrder + 0.03, width = "half",
                hasAlpha = true,
                get = function()
                    local c = action.color or {1, 0.2, 0.2, 1}
                    return c[1], c[2], c[3], c[4] or 1
                end,
                set = function(_, r, g, b, a) action.color = {r, g, b, a} end,
                hidden = function()
                    return action.type ~= "bar_color" and action.type ~= "bar_glow"
                        and action.type ~= "icon_glow" and action.type ~= "show_text"
                end,
            }
            setArgs[p .. "childIndex"] = {
                type = "select",
                name = L["Target Child"] or "Target Child",
                order = aOrder + 0.04, width = "normal",
                values = childValues,
                get = function() return action.childIndex or 1 end,
                set = function(_, val) action.childIndex = val end,
                hidden = function()
                    return action.type ~= "icon_glow" and action.type ~= "icon_change"
                end,
            }
            setArgs[p .. "intensity"] = {
                type = "range",
                name = L["Intensity"] or "Intensity",
                order = aOrder + 0.05, width = "half",
                min = 0.1, max = 2.0, step = 0.1,
                get = function() return action.intensity or 0.6 end,
                set = function(_, val) action.intensity = val end,
                hidden = function() return action.type ~= "bar_glow" end,
            }
            setArgs[p .. "newIcon"] = {
                type = "input",
                name = L["New Icon ID"] or "New Icon ID",
                order = aOrder + 0.051, width = "normal",
                get = function() return tostring(action.newIconID or "") end,
                set = function(_, val) action.newIconID = tonumber(val) or val end,
                hidden = function() return action.type ~= "icon_change" end,
            }
            setArgs[p .. "sound"] = {
                type = "input",
                name = L["Sound File"] or "Sound File",
                order = aOrder + 0.052, width = "double",
                get = function() return action.soundFile or "" end,
                set = function(_, val) action.soundFile = val end,
                hidden = function() return action.type ~= "play_sound" end,
            }
            setArgs[p .. "soundChannel"] = {
                type = "select",
                name = L["Channel"] or "Channel",
                order = aOrder + 0.053, width = "half",
                values = { Master = "Master", SFX = "SFX", Music = "Music", Dialog = "Dialog" },
                get = function() return action.channel or "Master" end,
                set = function(_, val) action.channel = val end,
                hidden = function() return action.type ~= "play_sound" end,
            }
            setArgs[p .. "soundCooldown"] = {
                type = "range",
                name = L["Cooldown"] or "Cooldown (sec)",
                order = aOrder + 0.054, width = "half",
                min = 0, max = 60, step = 1,
                get = function() return action.cooldown or 3 end,
                set = function(_, val) action.cooldown = val end,
                hidden = function() return action.type ~= "play_sound" end,
            }
            setArgs[p .. "text"] = {
                type = "input",
                name = L["Text"] or "Text",
                order = aOrder + 0.055, width = "double",
                get = function() return action.text or "" end,
                set = function(_, val) action.text = val end,
                hidden = function() return action.type ~= "show_text" end,
            }
            setArgs[p .. "textSize"] = {
                type = "range",
                name = L["Size"] or "Size",
                order = aOrder + 0.056, width = "half",
                min = 10, max = 60, step = 1,
                get = function() return action.size or 28 end,
                set = function(_, val) action.size = val end,
                hidden = function() return action.type ~= "show_text" end,
            }
            setArgs[p .. "textDuration"] = {
                type = "range",
                name = L["Duration"] or "Duration (sec)",
                order = aOrder + 0.057, width = "half",
                min = 0.5, max = 10, step = 0.5,
                get = function() return action.duration or 2 end,
                set = function(_, val) action.duration = val end,
                hidden = function() return action.type ~= "show_text" end,
            }
            setArgs[p .. "textPos"] = {
                type = "select",
                name = L["Position"] or "Position",
                order = aOrder + 0.058, width = "half",
                values = { CENTER = "Center", TOP = "Top", BOTTOM = "Bottom" },
                get = function() return action.position or "CENTER" end,
                set = function(_, val) action.position = val end,
                hidden = function() return action.type ~= "show_text" end,
            }

            local aiCapture = ai
            setArgs[p .. "delete"] = {
                type = "execute",
                name = "|cffff4444" .. (L["Delete Action"] or "Delete") .. "|r",
                order = aOrder + 0.09, width = "half",
                hidden = function() return not set.actions or #set.actions <= 1 end,
                func = function()
                    table.remove(set.actions, aiCapture)
                    RefreshOptions()
                end,
            }
        end

        -- 동작 추가 버튼
        setArgs["action_add"] = {
            type = "execute",
            name = "+ " .. (L["Add Action"] or "Add Action"),
            order = 3.99, width = "normal",
            func = function()
                if not set.actions then set.actions = {} end
                table.insert(set.actions, {
                    type = "bar_color",
                    target = "PrimaryPowerBar",
                    color = {1, 0.2, 0.2, 1},
                })
                RefreshOptions()
            end,
        }

        -- 세트 삭제 버튼
        local siCapture = si
        setArgs["deleteSet"] = {
            type = "execute",
            name = "|cffff4444" .. (L["Delete Set"] or "Delete Set") .. "|r",
            order = 99, width = "normal",
            func = function()
                table.remove(ca.sets, siCapture)
                RefreshOptions()
            end,
        }

        -- 세트 제목 (트리거/동작 수 표시)
        local trigCount = set.triggers and #set.triggers or 0
        local actCount = set.actions and #set.actions or 0
        local setName = (L["Action Set"] or "Action Set") .. " " .. si
            .. "  |cff888888(" .. trigCount .. " " .. (L["triggers"] or "triggers")
            .. ", " .. actCount .. " " .. (L["actions"] or "actions") .. ")|r"

        -- 세트를 폴더블 inline group으로 등록
        options["set_" .. si] = {
            type = "group",
            name = setName,
            order = setOrder,
            inline = true,
            args = setArgs,
        }
    end

    -- ─── 동작 세트 추가 버튼 ───
    options["set_add_spacer"] = {
        type = "description",
        name = " ",
        order = 9.98,
        width = "full",
    }
    options["set_add"] = {
        type = "execute",
        name = "|cff44ff44+ " .. (L["Add Action Set"] or "Add Action Set") .. "|r",
        order = 9.99, width = "full",
        func = function()
            table.insert(ca.sets, {
                logic = "and",
                triggers = {
                    { source = "child", childIndex = 1, condition = "active", value = 0 },
                },
                actions = {
                    { type = "bar_color", target = "PrimaryPowerBar", color = {1, 0.2, 0.2, 1} },
                },
            })
            RefreshOptions()
        end,
    }

    return options
end

-- Export group functions
ns.CreateGroupOptions = DDingUI.CreateGroupOptions
