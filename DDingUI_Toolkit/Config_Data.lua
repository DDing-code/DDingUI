--[[
    DDingToolKit - Config_Data.lua
    선언적 설정 트리 정의 + DB 헬퍼 함수
    -- [REFACTOR] StyleLib 리팩토링 Phase 1
]]
local addonName, ns = ...
local L = ns.L

------------------------------------------------------
-- DB Helper Functions
------------------------------------------------------

--- 점(.) 표기법으로 DB 값 읽기
--- @param path string  e.g. "profile.LFGAlert.soundEnabled"
--- @return any
function ns:GetDBValue(path)
    local current = self.db
    for segment in path:gmatch("[^%.]+") do
        if current == nil then return nil end
        local num = tonumber(segment)
        if num then
            current = current[num]
        else
            current = current[segment]
        end
    end
    return current
end

--- 점(.) 표기법으로 DB 값 쓰기
--- @param path string  e.g. "profile.LFGAlert.soundEnabled"
--- @param value any
function ns:SetDBValue(path, value)
    local segments = {}
    for segment in path:gmatch("[^%.]+") do
        segments[#segments + 1] = segment
    end

    local current = self.db
    for i = 1, #segments - 1 do
        local seg = segments[i]
        local num = tonumber(seg)
        if num then
            if current[num] == nil then current[num] = {} end
            current = current[num]
        else
            if current[seg] == nil then current[seg] = {} end
            current = current[seg]
        end
    end

    local lastSeg = segments[#segments]
    local num = tonumber(lastSeg)
    if num then
        current[num] = value
    else
        current[lastSeg] = value
    end
end

------------------------------------------------------
-- Common Option Generators
------------------------------------------------------

--- 사운드 채널 옵션
function ns:GetSoundChannelOptions()
    return {
        { text = L["CHANNEL_MASTER"],   value = "Master" },
        { text = L["CHANNEL_SFX"],      value = "SFX" },
        { text = L["CHANNEL_MUSIC"],    value = "Music" },
        { text = L["CHANNEL_AMBIENCE"], value = "Ambience" },
        { text = L["CHANNEL_DIALOG"],   value = "Dialog" },
    }
end

--- 알림 위치 옵션 (3종: TOP/CENTER/BOTTOM)
function ns:GetAlertPositionOptions()
    return {
        { text = L["POS_TOP"],    value = "TOP" },
        { text = L["POS_CENTER"], value = "CENTER" },
        { text = L["POS_BOTTOM"], value = "BOTTOM" },
    }
end

--- 텍스트 정렬 옵션
function ns:GetAlignOptions()
    return {
        { text = L["ALIGN_LEFT"],   value = "LEFT" },
        { text = L["ALIGN_CENTER"], value = "CENTER" },
        { text = L["ALIGN_RIGHT"],  value = "RIGHT" },
    }
end

--- 채팅 채널 옵션
function ns:GetChatTypeOptions()
    return {
        { text = L["GOLDSPLIT_SAY"],   value = "SAY" },
        { text = L["GOLDSPLIT_PARTY"], value = "PARTY" },
        { text = L["GOLDSPLIT_RAID"],  value = "RAID" },
    }
end

------------------------------------------------------
-- Module Key ↔ Name 매핑
------------------------------------------------------

ns.ConfigModuleMap = {
    -- 전투
    combattimer     = "CombatTimer",
    raidbreaktimer  = "RaidBreakTimer",
    characterpositionmarker = "CharacterPositionMarker",
    rangedisplay    = "RangeDisplay",
    castingalert    = "CastingAlert",
    focusinterrupt  = "FocusInterrupt",
    partytracker    = "PartyTracker",
    deathalert      = "DeathAlert",
    deathreleaseguard = "DeathReleaseGuard",
    mythicplus      = "MythicPlusHelper",

    -- 유틸리티
    talentbg        = "TalentBG",
    lfgalert        = "LFGAlert",
    partyfullalert  = "PartyFullAlert",
    mailalert       = "MailAlert",
    cursortrail     = "CursorTrail",
    itemlevel       = "ItemLevel",
    notepad         = "Notepad",
    goldsplit       = "GoldSplit",
    durability      = "DurabilityCheck",
    skyridingtracker = "SkyridingTracker",
    autorepair      = "AutoRepair",
    raidlootpass    = "RaidLootPass",
}

------------------------------------------------------
-- ConfigTree 정의
------------------------------------------------------

-- 초기화 함수 (DB 로드 후 호출)
function ns:InitConfigTree()
    local tree = {}

    -----------------------------------------------
    -- 메뉴 구조 (트리 메뉴용)
    -----------------------------------------------
    tree.menu = {
        { text = L["TAB_GENERAL"],          key = "general" },
        -- [REFACTOR] 전투/비전투 카테고리 분리
        { text = L["TAB_CATEGORY_COMBAT"] or "|TInterface\\ICONS\\Ability_DualWield:14:14|t |cffff6b6b전투|r",  key = "cat_combat", children = {
            { text = L["TAB_COMBATTIMER"],      key = "combattimer" },
            { text = L["TAB_CHARACTERPOSITIONMARKER"], key = "characterpositionmarker" },
            { text = L["TAB_RANGEDISPLAY"],     key = "rangedisplay" },
            { text = L["TAB_CASTINGALERT"],     key = "castingalert" },
            { text = L["TAB_FOCUSINTERRUPT"],   key = "focusinterrupt" },
            { text = L["TAB_PARTYTRACKER"],     key = "partytracker" },
            { text = L["DEATHALERT_TITLE"] or "DeathAlert", key = "deathalert" },
            { text = L["DEATH_RELEASE_GUARD_TITLE"], key = "deathreleaseguard" },
        }},
        { text = L["TAB_CATEGORY_UTILITY"] or "|TInterface\\ICONS\\Trade_Engineering:14:14|t |cff6baaff유틸리티|r", key = "cat_utility", children = {
            { text = L["TAB_TALENTBG"],         key = "talentbg" },
            { text = L["TAB_LFGALERT"],         key = "lfgalert" },
            { text = L["TAB_PARTYFULLALERT"],   key = "partyfullalert" },
            { text = L["TAB_RAIDBREAKTIMER"],   key = "raidbreaktimer" },
            { text = L["TAB_MAILALERT"],        key = "mailalert" },
            { text = L["TAB_CURSORTRAIL"],      key = "cursortrail" },
            { text = L["TAB_ITEMLEVEL"],        key = "itemlevel" },
            { text = L["TAB_NOTEPAD"],          key = "notepad" },
            { text = L["TAB_GOLDSPLIT"],        key = "goldsplit" },
            { text = L["TAB_DURABILITY"],       key = "durability" },
            { text = L["TAB_SKYRIDINGTRACKER"], key = "skyridingtracker" },
            { text = L["TAB_AUTOREPAIR"],       key = "autorepair" },
            { text = L["TAB_RAIDLOOTPASS"],     key = "raidlootpass" },
        }},
    }

    -----------------------------------------------
    -- 패널 정의
    -----------------------------------------------
    tree.panels = {}

    -----------------------------------------------
    -- Dashboard
    -----------------------------------------------
    tree.panels["overview"] = {
        title = L["WORKSPACE_DASHBOARD"],
        desc = L["WORKSPACE_OVERVIEW_DESC"],
        customRender = true,
        render = function(container)
            ns.ToolkitHomePanels:RenderDashboard(container)
        end,
    }

    -----------------------------------------------
    -- Category: 전투 (Overview)
    -----------------------------------------------
    tree.panels["cat_combat"] = {
        title = L["TAB_CATEGORY_COMBAT"] or "|TInterface\\ICONS\\Ability_DualWield:14:14|t 전투",
        settings = {
            { type = "header", label = L["TAB_CATEGORY_COMBAT"] or "전투 모듈", isFirst = true },
            { type = "text", label = L["CATEGORY_COMBAT_DESC"] or "전투 중 사용되는 유틸리티 모듈입니다.\n좌측 메뉴에서 개별 모듈을 선택하세요." },
        },
    }

    -----------------------------------------------
    -- Category: 유틸리티 (Overview)
    -----------------------------------------------
    tree.panels["cat_utility"] = {
        title = L["TAB_CATEGORY_UTILITY"] or "|TInterface\\ICONS\\Trade_Engineering:14:14|t 유틸리티",
        settings = {
            { type = "header", label = L["TAB_CATEGORY_UTILITY"] or "유틸리티 모듈", isFirst = true },
            { type = "text", label = L["CATEGORY_UTILITY_DESC"] or "비전투 편의 기능 모듈입니다.\n좌측 메뉴에서 개별 모듈을 선택하세요." },
        },
    }

    -----------------------------------------------
    -- General
    -----------------------------------------------
    tree.panels["general"] = {
        title = L["TAB_GENERAL"],
        settings = {
            { type = "header", label = L["GLOBAL_SETTINGS"], isFirst = true },
            { type = "toggle", key = "profile.minimap.hide", label = L["SHOW_MINIMAP_BUTTON"], invert = true },
            { type = "toggle", key = "profile.welcomeMessage", label = L["SHOW_WELCOME_MESSAGE"] },

            { type = "header", label = L["INFO"] },
            { type = "text", label = L["VERSION"] .. ": " .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?") }, -- [12.0.1] GetAddOnMetadata 폴백 제거
            { type = "text", label = L["AUTHOR"] .. ": DDing" },
        },
    }

    tree.panels["profile"] = {
        title = L["WORKSPACE_PROFILE"],
        desc = L["PROFILE_PANEL_DESC"],
        customRender = true,
        render = function(container)
            ns.ToolkitHomePanels:RenderProfile(container)
        end,
    }

    -----------------------------------------------
    -- TalentBG (커스텀 렌더 - 텍스처 그리드 + 프리뷰)
    -----------------------------------------------
    tree.panels["talentbg"] = {
        title = L["TALENTBG_TITLE"],
        desc  = L["TALENTBG_DESC"],
        customRender = true,
        moduleEnableKey = "profile.modules.TalentBG",
    }

    -----------------------------------------------
    -- LFGAlert
    -----------------------------------------------
    tree.panels["lfgalert"] = {
        title = L["LFGALERT_TITLE"],
        desc  = L["LFGALERT_DESC"],
        moduleEnableKey = "profile.modules.LFGAlert",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.LFGAlert", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            -- 알림 방식
            { type = "header", label = L["ALERT_METHOD"] },
            { type = "toggle", key = "profile.LFGAlert.soundEnabled",       label = L["LFGALERT_SOUND_ENABLED"] },
            { type = "toggle", key = "profile.LFGAlert.flashEnabled",       label = L["LFGALERT_FLASH_DESC"] },
            { type = "toggle", key = "profile.LFGAlert.screenAlertEnabled", label = L["LFGALERT_SCREEN_DESC"] },
            { type = "toggle", key = "profile.LFGAlert.chatAlert",          label = L["LFGALERT_CHAT_DESC"] },
            { type = "toggle", key = "profile.LFGAlert.autoOpenLFG",        label = L["LFGALERT_AUTO_OPEN_DESC"] },

            -- 사운드 설정
            { type = "header", label = L["SOUND_SETTINGS"] },
            { type = "sound",    key = "profile.LFGAlert.soundFile",    label = L["LFGALERT_SOUND_FILE"],    defaultLabel = L["LFGALERT_DEFAULT_SOUND"], customPathKey = "profile.LFGAlert.soundCustomPath" },
            { type = "dropdown", key = "profile.LFGAlert.soundChannel", label = L["LFGALERT_SOUND_CHANNEL"], options = "soundChannels" },

            -- 화면 알림 설정
            { type = "header", label = L["SCREEN_ALERT_SETTINGS"] },
            { type = "dropdown", key = "profile.LFGAlert.alertPosition",  label = L["LFGALERT_POSITION"],  options = "alertPositions" },
            { type = "dropdown", key = "profile.LFGAlert.alertAnimation", label = L["LFGALERT_ANIMATION"], options = {
                { text = L["ANIM_BOUNCE"], value = "bounce" },
                { text = L["ANIM_FADE"],   value = "fade" },
                { text = L["ANIM_NONE"],   value = "none" },
            }},
            { type = "slider", key = "profile.LFGAlert.alertScale",    label = L["ALERT_SIZE"],          min = 0.5, max = 2.0, step = 0.1 },
            { type = "slider", key = "profile.LFGAlert.alertDuration", label = L["DISPLAY_DURATION"],    min = 1,   max = 15,  step = 1 },

            -- 조건
            { type = "header", label = L["CONDITIONS"] },
            { type = "toggle", key = "profile.LFGAlert.leaderOnly", label = L["LFGALERT_LEADER_ONLY_DESC"] },
            { type = "slider", key = "profile.LFGAlert.cooldown",   label = L["ALERT_COOLDOWN"], min = 0, max = 10, step = 1 },

            -- 테스트
            { type = "separator" },
            { type = "button", label = L["TEST_ALERT"], onClick = function()
                local mod = ns.modules and ns.modules["LFGAlert"]
                if mod and mod.TriggerAlert then mod:TriggerAlert(1, true) end
            end },
        },
    }

    -----------------------------------------------
    -- PartyFullAlert
    -----------------------------------------------
    local function RefreshPartyFullAlert()
        local mod = ns.modules and ns.modules["PartyFullAlert"]
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function RefreshPartyFullAlertPosition()
        local mod = ns.modules and ns.modules["PartyFullAlert"]
        if mod and mod.ApplyPosition then mod:ApplyPosition() end
    end

    tree.panels["partyfullalert"] = {
        title = L["PARTYFULLALERT_TITLE"],
        desc = L["PARTYFULLALERT_DESC"],
        moduleEnableKey = "profile.modules.PartyFullAlert",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.PartyFullAlert", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            { type = "header", label = L["ALERT_METHOD"] },
            { type = "toggle", key = "profile.PartyFullAlert.soundEnabled", label = L["PARTYFULLALERT_SOUND_ENABLED"] },
            { type = "toggle", key = "profile.PartyFullAlert.flashEnabled", label = L["PARTYFULLALERT_FLASH_ENABLED"] },
            { type = "toggle", key = "profile.PartyFullAlert.screenAlertEnabled", label = L["PARTYFULLALERT_SCREEN_ENABLED"] },
            { type = "toggle", key = "profile.PartyFullAlert.chatAlert", label = L["PARTYFULLALERT_CHAT_ENABLED"] },

            { type = "header", label = L["CONDITIONS"] },
            { type = "slider", key = "profile.PartyFullAlert.targetSize", label = L["PARTYFULLALERT_TARGET_SIZE"], min = 2, max = 5, step = 1 },
            { type = "slider", key = "profile.PartyFullAlert.cooldown", label = L["ALERT_COOLDOWN"], min = 0, max = 30, step = 1 },
            { type = "text", label = L["PARTYFULLALERT_FIVE_PLAYER_ONLY"] },

            { type = "header", label = L["SOUND_SETTINGS"] },
            { type = "sound", key = "profile.PartyFullAlert.soundFile", label = L["LFGALERT_SOUND_FILE"], defaultLabel = L["PARTYFULLALERT_DEFAULT_SOUND"], customPathKey = "profile.PartyFullAlert.soundCustomPath" },
            { type = "dropdown", key = "profile.PartyFullAlert.soundChannel", label = L["LFGALERT_SOUND_CHANNEL"], options = "soundChannels" },

            { type = "header", label = L["SCREEN_ALERT_SETTINGS"] },
            { type = "slider", key = "profile.PartyFullAlert.alertScale", label = L["ALERT_SIZE"], min = 0.5, max = 2.0, step = 0.1, onChange = RefreshPartyFullAlert },
            { type = "slider", key = "profile.PartyFullAlert.alertDuration", label = L["DISPLAY_DURATION"], min = 1, max = 15, step = 1 },

            { type = "header", label = L["CASTINGALERT_POSITION_SETTINGS"] },
            { type = "slider", key = "profile.PartyFullAlert.position.x", label = L["CASTINGALERT_POS_X"], min = -800, max = 800, step = 1, onChange = RefreshPartyFullAlertPosition },
            { type = "slider", key = "profile.PartyFullAlert.position.y", label = L["CASTINGALERT_POS_Y"], min = -600, max = 600, step = 1, onChange = RefreshPartyFullAlertPosition },

            { type = "separator" },
            { type = "button", label = L["TEST_ALERT"], onClick = function()
                local mod = ns.modules and ns.modules["PartyFullAlert"]
                if mod and mod.TriggerAlert then
                    mod:TriggerAlert(true, ns:GetDBValue("profile.PartyFullAlert.targetSize") or 5)
                end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["PartyFullAlert"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
        },
    }

    -----------------------------------------------
    -- MailAlert
    -----------------------------------------------
    tree.panels["mailalert"] = {
        title = L["MAILALERT_TITLE"],
        desc  = L["MAILALERT_DESC"],
        moduleEnableKey = "profile.modules.MailAlert",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.MailAlert", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            -- 알림 방식
            { type = "header", label = L["ALERT_METHOD"] },
            { type = "toggle", key = "profile.MailAlert.soundEnabled",       label = L["MAILALERT_SOUND_ENABLED"] },
            { type = "toggle", key = "profile.MailAlert.flashEnabled",       label = L["MAILALERT_FLASH_ENABLED"] },
            { type = "toggle", key = "profile.MailAlert.screenAlertEnabled", label = L["MAILALERT_SCREEN_ALERT"] },
            { type = "toggle", key = "profile.MailAlert.chatAlert",          label = L["MAILALERT_CHAT_ALERT"] },

            -- 조건 설정
            { type = "header", label = L["MAILALERT_CONDITION_SETTINGS"] },
            { type = "toggle", key = "profile.MailAlert.hideInCombat",   label = L["MAILALERT_HIDE_IN_COMBAT_DESC"] },
            { type = "toggle", key = "profile.MailAlert.hideInInstance", label = L["MAILALERT_HIDE_IN_INSTANCE_DESC"] },
            { type = "slider", key = "profile.MailAlert.cooldown",       label = L["ALERT_COOLDOWN"], min = 10, max = 300, step = 10 },

            -- 사운드 설정
            { type = "header", label = L["SOUND_SETTINGS"] },
            { type = "sound",    key = "profile.MailAlert.soundFile",    label = L["LFGALERT_SOUND_FILE"],    defaultLabel = L["MAILALERT_TEST_MSG"], customPathKey = "profile.MailAlert.soundCustomPath" },
            { type = "dropdown", key = "profile.MailAlert.soundChannel", label = L["LFGALERT_SOUND_CHANNEL"], options = "soundChannels" },

            -- 화면 알림 설정
            { type = "header", label = L["SCREEN_ALERT_SETTINGS"] },
            { type = "dropdown", key = "profile.MailAlert.alertPosition",  label = L["ALERT_POSITION"], options = "alertPositions" },
            { type = "dropdown", key = "profile.MailAlert.alertAnimation", label = L["ANIMATION"], options = {
                { text = L["ANIM_PULSE"], value = "pulse" },
                { text = L["ANIM_FADE"],  value = "fade" },
                { text = L["ANIM_NONE"],  value = "none" },
            }},
            { type = "slider", key = "profile.MailAlert.alertScale",    label = L["ALERT_SIZE"],       min = 0.5, max = 2.0, step = 0.1 },
            { type = "slider", key = "profile.MailAlert.alertDuration", label = L["DISPLAY_DURATION"], min = 1,   max = 15,  step = 1 },

            -- 테스트
            { type = "separator" },
            { type = "button", label = L["TEST_ALERT"], onClick = function()
                local mod = ns.modules and ns.modules["MailAlert"]
                if mod and mod.TriggerAlert then mod:TriggerAlert(true) end
            end },
        },
    }

    -----------------------------------------------
    -- CursorTrail
    -----------------------------------------------
    tree.panels["cursortrail"] = {
        title = L["CURSORTRAIL_TITLE"],
        desc  = L["CURSORTRAIL_DESC"],
        moduleEnableKey = "profile.modules.CursorTrail",
        settings = {
            -- 기본 설정
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.CursorTrail", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            -- 프리셋 (onChange 는 Phase 5에서 구현)
            { type = "header", label = L["CURSORTRAIL_PRESETS"] },
            { type = "custom", customType = "cursortrail_presets" },

            -- 색상 설정 (동적 색상 피커 - 커스텀 렌더)
            { type = "header", label = L["CURSORTRAIL_COLOR_SETTINGS"] },
            { type = "slider", key = "profile.CursorTrail.colorCount", label = L["CURSORTRAIL_COLOR_NUM"], min = 1, max = 10, step = 1 },
            { type = "custom", customType = "colorArray",
              countKey  = "profile.CursorTrail.colorCount",
              colorsKey = "profile.CursorTrail.colors",
              maxColors = 10,
            },
            { type = "toggle", key = "profile.CursorTrail.colorFlow",      label = L["CURSORTRAIL_COLOR_FLOW_DESC"] },
            { type = "slider", key = "profile.CursorTrail.colorFlowSpeed", label = L["CURSORTRAIL_FLOW_SPEED"], min = 0.1, max = 5.0, step = 0.1 },

            -- 외형
            { type = "header", label = L["CURSORTRAIL_APPEARANCE"] },
            { type = "slider",   key = "profile.CursorTrail.width",  label = L["WIDTH"],  min = 10, max = 200, step = 5 },
            { type = "slider",   key = "profile.CursorTrail.height", label = L["HEIGHT"], min = 10, max = 200, step = 5 },
            { type = "slider",   key = "profile.CursorTrail.alpha",  label = L["TRANSPARENCY"], min = 0.1, max = 1.0, step = 0.05 },
            { type = "dropdown", key = "profile.CursorTrail.texture", label = L["TEXTURE"], options = "cursorTrailTextures",
              onChange = function()
                local mod = ns.modules and ns.modules["CursorTrail"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "dropdown", key = "profile.CursorTrail.blendMode", label = L["CURSORTRAIL_BLEND_MODE"], options = {
                { text = L["CURSORTRAIL_BLEND_ADD"],   value = "ADD" },
                { text = L["CURSORTRAIL_BLEND_BLEND"], value = "BLEND" },
            },
              onChange = function()
                local mod = ns.modules and ns.modules["CursorTrail"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },

            -- 성능
            { type = "header", label = L["CURSORTRAIL_PERFORMANCE"] },
            { type = "text",   label = L["CURSORTRAIL_PERFORMANCE_WARNING"] },
            { type = "slider", key = "profile.CursorTrail.lifetime",    label = L["CURSORTRAIL_DOT_LIFETIME"], min = 0.1, max = 1.0, step = 0.05 },
            { type = "slider", key = "profile.CursorTrail.maxDots",     label = L["CURSORTRAIL_MAX_DOTS"],     min = 100, max = 2000, step = 100,
              onChange = function()
                local mod = ns.modules and ns.modules["CursorTrail"]
                if mod and mod.CreateElementPool then mod:CreateElementPool() end
              end,
            },
            { type = "slider", key = "profile.CursorTrail.dotDistance",  label = L["CURSORTRAIL_DOT_SPACING"],  min = 1,   max = 50,   step = 1 },

            -- 표시 조건
            { type = "header", label = L["CURSORTRAIL_DISPLAY_CONDITIONS"] },
            { type = "toggle",   key = "profile.CursorTrail.onlyInCombat",  label = L["CURSORTRAIL_COMBAT_ONLY"] },
            { type = "toggle",   key = "profile.CursorTrail.hideInInstance", label = L["CURSORTRAIL_HIDE_INSTANCE"] },
            { type = "dropdown", key = "profile.CursorTrail.layer", label = L["CURSORTRAIL_DISPLAY_LAYER"], options = {
                { text = L["CURSORTRAIL_LAYER_TOP"], value = "TOOLTIP" },
                { text = L["CURSORTRAIL_LAYER_BG"],  value = "BACKGROUND" },
            },
              onChange = function()
                local mod = ns.modules and ns.modules["CursorTrail"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
        },
    }

    -----------------------------------------------
    -- ItemLevel
    -----------------------------------------------
    local function RefreshItemLevel()
        local mod = ns.modules and ns.modules["ItemLevel"]
        if mod and mod.Refresh then mod:Refresh() end
    end

    tree.panels["itemlevel"] = {
        title = L["ITEMLEVEL_TITLE"],
        desc  = L["ITEMLEVEL_DESC"],
        moduleEnableKey = "profile.modules.ItemLevel",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.ItemLevel", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            -- 표시 설정
            { type = "header", label = L["ITEMLEVEL_DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.ItemLevel.showItemLevel",    label = L["ITEMLEVEL_SHOW_ILVL"], onChange = RefreshItemLevel },
            { type = "toggle", key = "profile.ItemLevel.showEnchant",      label = L["ITEMLEVEL_SHOW_ENCHANT"], onChange = RefreshItemLevel },
            { type = "toggle", key = "profile.ItemLevel.showGems",         label = L["ITEMLEVEL_SHOW_GEMS"], onChange = RefreshItemLevel },
            { type = "toggle", key = "profile.ItemLevel.showAverageIlvl",  label = L["ITEMLEVEL_SHOW_AVG"], onChange = RefreshItemLevel },
            { type = "toggle", key = "profile.ItemLevel.showEnhancedStats",label = L["ITEMLEVEL_SHOW_ENHANCED"], onChange = RefreshItemLevel },

            -- 본인 캐릭터
            { type = "header", label = L["ITEMLEVEL_SELF_SETTINGS"] },
            { type = "slider", key = "profile.ItemLevel.selfIlvlSize",    label = L["ITEMLEVEL_SELF_ILVL_SIZE"],    min = 8, max = 20, step = 1, onChange = RefreshItemLevel },
            { type = "dropdown", key = "profile.ItemLevel.selfIlvlFlags", label = L["ITEMLEVEL_ILVL_OUTLINE"], options = {
                { text = L["FONT_OUTLINE_NONE"], value = "" },
                { text = L["FONT_OUTLINE_NORMAL"], value = "OUTLINE" },
                { text = L["FONT_OUTLINE_THICK"], value = "THICKOUTLINE" },
              }, onChange = RefreshItemLevel },
            { type = "slider", key = "profile.ItemLevel.selfEnchantSize", label = L["ITEMLEVEL_SELF_ENCHANT_SIZE"], min = 8, max = 16, step = 1, onChange = RefreshItemLevel },
            { type = "dropdown", key = "profile.ItemLevel.selfEnchantFlags", label = L["ITEMLEVEL_ENCHANT_OUTLINE"], options = {
                { text = L["FONT_OUTLINE_NONE"], value = "" },
                { text = L["FONT_OUTLINE_NORMAL"], value = "OUTLINE" },
                { text = L["FONT_OUTLINE_THICK"], value = "THICKOUTLINE" },
              }, onChange = RefreshItemLevel },
            { type = "slider", key = "profile.ItemLevel.selfGemSize",     label = L["ITEMLEVEL_SELF_GEM_SIZE"],     min = 10, max = 24, step = 1, onChange = RefreshItemLevel },
            { type = "slider", key = "profile.ItemLevel.selfGemSpacing",  label = L["ITEMLEVEL_GEM_SPACING"],       min = -8, max = 12, step = 1, onChange = RefreshItemLevel },
            { type = "slider", key = "profile.ItemLevel.selfAvgSize",     label = L["ITEMLEVEL_SELF_AVG_SIZE"],     min = 12, max = 24, step = 1, onChange = RefreshItemLevel },

            -- 살펴보기
            { type = "header", label = L["ITEMLEVEL_INSPECT_SETTINGS"] },
            { type = "slider", key = "profile.ItemLevel.inspIlvlSize",    label = L["ITEMLEVEL_INSPECT_ILVL_SIZE"],    min = 8, max = 20, step = 1, onChange = RefreshItemLevel },
            { type = "dropdown", key = "profile.ItemLevel.inspIlvlFlags", label = L["ITEMLEVEL_ILVL_OUTLINE"], options = {
                { text = L["FONT_OUTLINE_NONE"], value = "" },
                { text = L["FONT_OUTLINE_NORMAL"], value = "OUTLINE" },
                { text = L["FONT_OUTLINE_THICK"], value = "THICKOUTLINE" },
              }, onChange = RefreshItemLevel },
            { type = "slider", key = "profile.ItemLevel.inspEnchantSize", label = L["ITEMLEVEL_INSPECT_ENCHANT_SIZE"], min = 8, max = 16, step = 1, onChange = RefreshItemLevel },
            { type = "dropdown", key = "profile.ItemLevel.inspEnchantFlags", label = L["ITEMLEVEL_ENCHANT_OUTLINE"], options = {
                { text = L["FONT_OUTLINE_NONE"], value = "" },
                { text = L["FONT_OUTLINE_NORMAL"], value = "OUTLINE" },
                { text = L["FONT_OUTLINE_THICK"], value = "THICKOUTLINE" },
              }, onChange = RefreshItemLevel },
            { type = "slider", key = "profile.ItemLevel.inspGemSize",     label = L["ITEMLEVEL_INSPECT_GEM_SIZE"],     min = 10, max = 24, step = 1, onChange = RefreshItemLevel },
            { type = "slider", key = "profile.ItemLevel.inspGemSpacing",  label = L["ITEMLEVEL_GEM_SPACING"],           min = -8, max = 12, step = 1, onChange = RefreshItemLevel },
            { type = "slider", key = "profile.ItemLevel.inspAvgSize",     label = L["ITEMLEVEL_INSPECT_AVG_SIZE"],      min = 12, max = 24, step = 1, onChange = RefreshItemLevel },

            -- 리셋
            { type = "separator" },
            { type = "button", label = L["RESET_TO_DEFAULT"], onClick = function()
                local mod = ns.modules and ns.modules["ItemLevel"]
                if mod and mod.ResetSettings then mod:ResetSettings() end
            end },
        },
    }

    -----------------------------------------------
    -- Notepad
    -----------------------------------------------
    tree.panels["notepad"] = {
        title = L["NOTEPAD_TITLE"],
        desc  = L["NOTEPAD_DESC"],
        moduleEnableKey = "profile.modules.Notepad",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.Notepad", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            { type = "header", label = L["NOTEPAD_BASIC_SETTINGS"] },
            { type = "toggle", key = "profile.Notepad.showPVEButton", label = L["NOTEPAD_SHOW_PVE_BUTTON"] },

            { type = "header", label = L["NOTEPAD_USAGE_TITLE"] },
            { type = "text",   label = L["NOTEPAD_USAGE_TEXT"] },

            { type = "header", label = L["QUICK_ACCESS"] },
            { type = "button", label = L["NOTEPAD_OPEN"], onClick = function()
                local mod = ns.modules and ns.modules["Notepad"]
                if mod and mod.ToggleMainFrame then mod:ToggleMainFrame() end
            end },
        },
    }

    -----------------------------------------------
    -- CombatTimer
    -----------------------------------------------
    tree.panels["combattimer"] = {
        title = L["COMBATTIMER_TITLE"],
        desc  = L["COMBATTIMER_DESC"],
        moduleEnableKey = "profile.modules.CombatTimer",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.CombatTimer", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            -- 표시 설정
            { type = "header", label = L["COMBATTIMER_DISPLAY_SETTINGS"] },
            { type = "toggle",   key = "profile.CombatTimer.showMilliseconds", label = L["COMBATTIMER_SHOW_MS"] },
            { type = "toggle",   key = "profile.CombatTimer.showBackground",   label = L["COMBATTIMER_SHOW_BG"] },
            { type = "toggle",   key = "profile.CombatTimer.colorByTime",      label = L["COMBATTIMER_COLOR_BY_TIME"] },
            { type = "toggle",   key = "profile.CombatTimer.locked",           label = L["POSITION_LOCKED"] },
            { type = "dropdown", key = "profile.CombatTimer.textAlign",        label = L["TEXT_ALIGN"], options = "alignOptions" },

            -- 폰트 설정
            { type = "header", label = L["COMBATTIMER_FONT_SETTINGS"] },
            { type = "font",   key = "profile.CombatTimer.font",     label = L["FONT"] },
            { type = "slider", key = "profile.CombatTimer.fontSize",  label = L["FONT_SIZE"],       min = 12, max = 48, step = 1 },
            { type = "color",  key = "profile.CombatTimer.textColor", label = L["TEXT_COLOR"],       hasAlpha = true },
            { type = "slider", key = "profile.CombatTimer.scale",     label = L["SCALE"],           min = 0.5, max = 2.0, step = 0.1 },
            { type = "slider", key = "profile.CombatTimer.bgAlpha",   label = L["BACKGROUND_ALPHA"],min = 0, max = 1, step = 0.05 },

            -- 알림 설정
            { type = "header", label = L["COMBATTIMER_ALERT_SETTINGS"] },
            { type = "toggle", key = "profile.CombatTimer.soundOnStart", label = L["COMBATTIMER_SOUND_ON_START"] },
            { type = "sound",  key = "profile.CombatTimer.soundFile",    label = L["LFGALERT_SOUND_FILE"], defaultLabel = L["COMBATTIMER_DEFAULT_SOUND"] or "기본 (카운트다운)", customPathKey = "profile.CombatTimer.soundCustomPath" },
            { type = "dropdown", key = "profile.CombatTimer.soundChannel", label = L["LFGALERT_SOUND_CHANNEL"], options = "soundChannels" },
            { type = "toggle", key = "profile.CombatTimer.printToChat",  label = L["COMBATTIMER_PRINT_TO_CHAT"] },

            -- 타이밍
            { type = "header", label = L["COMBATTIMER_TIMING_SETTINGS"] },
            { type = "slider", key = "profile.CombatTimer.hideDelay", label = L["COMBATTIMER_HIDE_DELAY"], min = 0, max = 10, step = 1 },

            -- 버튼
            { type = "separator" },
            { type = "button", label = L["TEST_ON_OFF"], onClick = function()
                local mod = ns.modules and ns.modules["CombatTimer"]
                if mod and mod.TestTimer then mod:TestTimer() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["CombatTimer"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
        },
    }

    -----------------------------------------------
    -- RaidBreakTimer
    -----------------------------------------------
    local function RefreshRaidBreakTimer()
        local mod = ns.modules and ns.modules["RaidBreakTimer"]
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function RefreshRaidBreakTimerPosition()
        local mod = ns.modules and ns.modules["RaidBreakTimer"]
        if mod and mod.ApplyPosition then mod:ApplyPosition() end
    end

    tree.panels["raidbreaktimer"] = {
        title = L["RAIDBREAKTIMER_TITLE"],
        desc = L["RAIDBREAKTIMER_DESC"],
        moduleEnableKey = "profile.modules.RaidBreakTimer",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.RaidBreakTimer", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            { type = "text", label = L["RAIDBREAKTIMER_BIGWIGS_NOTE"] },

            { type = "header", label = L["RAIDBREAKTIMER_TEXT_SETTINGS"] },
            { type = "input", key = "profile.RaidBreakTimer.customText", label = L["RAIDBREAKTIMER_CUSTOM_TEXT"], inputWidth = 300, onChange = RefreshRaidBreakTimer },
            { type = "dropdown", key = "profile.RaidBreakTimer.textOrder", label = L["RAIDBREAKTIMER_TEXT_ORDER"], options = {
                { text = L["RAIDBREAKTIMER_TIME_ONLY"], value = "TIME_ONLY" },
                { text = L["RAIDBREAKTIMER_TEXT_TIME"], value = "TEXT_TIME" },
                { text = L["RAIDBREAKTIMER_TIME_TEXT"], value = "TIME_TEXT" },
              }, onChange = RefreshRaidBreakTimer },
            { type = "dropdown", key = "profile.RaidBreakTimer.textLayer", label = L["RAIDBREAKTIMER_TEXT_LAYER"], options = {
                { text = L["RAIDBREAKTIMER_TEXT_LAYER_FRONT"], value = "FRONT" },
                { text = L["RAIDBREAKTIMER_TEXT_LAYER_BEHIND"], value = "BEHIND" },
              }, onChange = RefreshRaidBreakTimer },
            { type = "font", key = "profile.RaidBreakTimer.font", label = L["FONT"], onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.fontSize", label = L["FONT_SIZE"], min = 24, max = 160, step = 1, onChange = RefreshRaidBreakTimer },
            { type = "dropdown", key = "profile.RaidBreakTimer.fontOutline", label = L["FONT_OUTLINE"], options = {
                { text = L["FONT_OUTLINE_NONE"], value = "" },
                { text = L["FONT_OUTLINE_NORMAL"], value = "OUTLINE" },
                { text = L["FONT_OUTLINE_THICK"], value = "THICKOUTLINE" },
              }, onChange = RefreshRaidBreakTimer },
            { type = "color", key = "profile.RaidBreakTimer.textColor", label = L["TEXT_COLOR"], hasAlpha = true, onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.textOffsetX", label = L["RAIDBREAKTIMER_TEXT_OFFSET_X"], min = -600, max = 600, step = 1, onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.textOffsetY", label = L["RAIDBREAKTIMER_TEXT_OFFSET_Y"], min = -600, max = 600, step = 1, onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.scale", label = L["SCALE"], min = 0.5, max = 2.0, step = 0.05, onChange = RefreshRaidBreakTimer },

            { type = "header", label = L["RAIDBREAKTIMER_IMAGE_SETTINGS"] },
            { type = "toggle", key = "profile.RaidBreakTimer.showImage", label = L["RAIDBREAKTIMER_SHOW_IMAGE"], onChange = RefreshRaidBreakTimer },
            { type = "input", key = "profile.RaidBreakTimer.imageFolder", label = L["RAIDBREAKTIMER_IMAGE_FOLDER"], inputWidth = 300, onChange = RefreshRaidBreakTimer },
            { type = "input", key = "profile.RaidBreakTimer.imageFile", label = L["RAIDBREAKTIMER_IMAGE_FILE"], inputWidth = 300, onChange = RefreshRaidBreakTimer },
            { type = "text", label = L["RAIDBREAKTIMER_IMAGE_PATH_NOTE"] },
            { type = "dropdown", key = "profile.RaidBreakTimer.imageAnchor", label = L["RAIDBREAKTIMER_IMAGE_ANCHOR"], options = {
                { text = L["POS_TOPLEFT"], value = "TOPLEFT" },
                { text = L["POS_TOP"], value = "TOP" },
                { text = L["POS_TOPRIGHT"], value = "TOPRIGHT" },
                { text = L["POS_LEFT"], value = "LEFT" },
                { text = L["POS_CENTER"], value = "CENTER" },
                { text = L["POS_RIGHT"], value = "RIGHT" },
                { text = L["POS_BOTTOMLEFT"], value = "BOTTOMLEFT" },
                { text = L["POS_BOTTOM"], value = "BOTTOM" },
                { text = L["POS_BOTTOMRIGHT"], value = "BOTTOMRIGHT" },
              }, onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.imageWidth", label = L["RAIDBREAKTIMER_IMAGE_WIDTH"], min = 32, max = 1200, step = 1, onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.imageHeight", label = L["RAIDBREAKTIMER_IMAGE_HEIGHT"], min = 32, max = 1200, step = 1, onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.imageAlpha", label = L["RAIDBREAKTIMER_IMAGE_ALPHA"], min = 0, max = 1, step = 0.05, onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.imageOffsetX", label = L["RAIDBREAKTIMER_IMAGE_OFFSET_X"], min = -600, max = 600, step = 1, onChange = RefreshRaidBreakTimer },
            { type = "slider", key = "profile.RaidBreakTimer.imageOffsetY", label = L["RAIDBREAKTIMER_IMAGE_OFFSET_Y"], min = -600, max = 600, step = 1, onChange = RefreshRaidBreakTimer },

            { type = "header", label = L["CASTINGALERT_POSITION_SETTINGS"] },
            { type = "slider", key = "profile.RaidBreakTimer.position.x", label = L["CASTINGALERT_POS_X"], min = -800, max = 800, step = 1, onChange = RefreshRaidBreakTimerPosition },
            { type = "slider", key = "profile.RaidBreakTimer.position.y", label = L["CASTINGALERT_POS_Y"], min = -600, max = 600, step = 1, onChange = RefreshRaidBreakTimerPosition },

            { type = "separator" },
            { type = "button", label = L["TEST_ON_OFF"], onClick = function()
                local mod = ns.modules and ns.modules["RaidBreakTimer"]
                if mod and mod.TestMode then mod:TestMode() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["RaidBreakTimer"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
        },
    }

    -----------------------------------------------
    -- CharacterPositionMarker
    -----------------------------------------------
    tree.panels["characterpositionmarker"] = {
        title = L["CHARPOSMARKER_TITLE"],
        desc  = L["CHARPOSMARKER_DESC"],
        moduleEnableKey = "profile.modules.CharacterPositionMarker",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.CharacterPositionMarker", label = L["MODULE_ENABLED"], isModuleToggle = true,
              onChange = function(checked)
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if not mod then return end
                if checked then
                    if mod.OnInitialize and not mod.initialized then mod:OnInitialize() end
                    if mod.OnEnable then mod:OnEnable() end
                    mod.enabled = true
                else
                    if mod.OnDisable then mod:OnDisable() end
                    mod.enabled = false
                end
              end,
            },

            { type = "header", label = L["CHARPOSMARKER_DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.CharacterPositionMarker.enabled", label = L["CHARPOSMARKER_ENABLED"],
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "dropdown", key = "profile.CharacterPositionMarker.visualMode", label = L["CHARPOSMARKER_VISUAL_MODE"], options = {
                { text = L["CHARPOSMARKER_VISUAL_SIMPLE"], value = "SIMPLE" },
                { text = L["CHARPOSMARKER_VISUAL_FANCY"], value = "SYSTEM" },
              },
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "toggle", key = "profile.CharacterPositionMarker.combatOnly", label = L["CHARPOSMARKER_COMBAT_ONLY"],
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "toggle", key = "profile.CharacterPositionMarker.instanceOnly", label = L["CHARPOSMARKER_INSTANCE_ONLY"],
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "toggle", key = "profile.CharacterPositionMarker.rangeCheck", label = L["CHARPOSMARKER_RANGE_CHECK"],
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "toggle", key = "profile.CharacterPositionMarker.meleeDpsOnly", label = L["CHARPOSMARKER_MELEE_ONLY"],
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "input", key = "profile.CharacterPositionMarker.rangeSpell", label = L["CHARPOSMARKER_RANGE_SPELL"], numeric = true, inputWidth = 100,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "dropdown", key = "profile.CharacterPositionMarker.shape", label = L["CHARPOSMARKER_SHAPE"], options = {
                { text = L["CHARPOSMARKER_SHAPE_RETICLE"], value = "RETICLE" },
                { text = L["CHARPOSMARKER_SHAPE_CROSS"],   value = "CROSS" },
                { text = L["CHARPOSMARKER_SHAPE_SQUARE"],  value = "SQUARE" },
                { text = L["CHARPOSMARKER_SHAPE_DIAMOND"], value = "DIAMOND" },
                { text = L["CHARPOSMARKER_SHAPE_EMPTY_DIAMOND"], value = "EMPTY_DIAMOND" },
              },
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.CharacterPositionMarker.size", label = L["CHARPOSMARKER_SIZE"], min = 16, max = 180, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.CharacterPositionMarker.thickness", label = L["CHARPOSMARKER_THICKNESS"], min = 1, max = 24, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.CharacterPositionMarker.centerGap", label = L["CHARPOSMARKER_CENTER_GAP"], min = 0, max = 80, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.CharacterPositionMarker.scale", label = L["SCALE"], min = 0.3, max = 2.0, step = 0.05,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "dropdown", key = "profile.CharacterPositionMarker.frameStrata", label = L["CHARPOSMARKER_FRAME_STRATA"], options = {
                { text = L["CHARPOSMARKER_STRATA_LOW"],    value = "LOW" },
                { text = L["CHARPOSMARKER_STRATA_MEDIUM"], value = "MEDIUM" },
                { text = L["CHARPOSMARKER_STRATA_HIGH"],   value = "HIGH" },
              },
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "header", label = L["CHARPOSMARKER_ANIMATION_SETTINGS"] },
            { type = "toggle", key = "profile.CharacterPositionMarker.animationEnabled", label = L["CHARPOSMARKER_ANIMATION_ENABLED"],
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.CharacterPositionMarker.enterAnimationDuration", label = L["CHARPOSMARKER_ENTER_DURATION"], min = 0.1, max = 1.0, step = 0.05,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.CharacterPositionMarker.exitAnimationDuration", label = L["CHARPOSMARKER_EXIT_DURATION"], min = 0.1, max = 1.0, step = 0.05,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },

            { type = "header", label = L["COLOR"] },
            { type = "color", key = "profile.CharacterPositionMarker.color", label = L["CHARPOSMARKER_COLOR"], hasAlpha = true,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "color", key = "profile.CharacterPositionMarker.outOfRangeColor", label = L["CHARPOSMARKER_OUT_OF_RANGE_COLOR"], hasAlpha = true,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "color", key = "profile.CharacterPositionMarker.effectColor", label = L["CHARPOSMARKER_EFFECT_COLOR"], hasAlpha = true,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "color", key = "profile.CharacterPositionMarker.effectSecondaryColor", label = L["CHARPOSMARKER_EFFECT_SECONDARY_COLOR"], hasAlpha = true,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },

            { type = "header", label = L["CASTINGALERT_POSITION_SETTINGS"] },
            { type = "slider", key = "profile.CharacterPositionMarker.position.x", label = L["CASTINGALERT_POS_X"], min = -800, max = 800, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplyPosition then mod:ApplyPosition() end
              end,
            },
            { type = "slider", key = "profile.CharacterPositionMarker.position.y", label = L["CASTINGALERT_POS_Y"], min = -600, max = 600, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ApplyPosition then mod:ApplyPosition() end
              end,
            },

            { type = "separator" },
            { type = "button", label = L["TEST_ON_OFF"], onClick = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.TestMode then mod:TestMode() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["CharacterPositionMarker"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
        },
    }

    -----------------------------------------------
    -- RangeDisplay
    -----------------------------------------------
    local function RefreshRangeDisplay()
        local mod = ns.modules and ns.modules["RangeDisplay"]
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function RefreshRangeDisplayPosition()
        local mod = ns.modules and ns.modules["RangeDisplay"]
        if mod and mod.ApplyPosition then mod:ApplyPosition() end
    end

    tree.panels["rangedisplay"] = {
        title = L["RANGEDISPLAY_TITLE"],
        desc = L["RANGEDISPLAY_DESC"],
        moduleEnableKey = "profile.modules.RangeDisplay",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.RangeDisplay", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            { type = "header", label = L["RANGEDISPLAY_DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.RangeDisplay.showTarget", label = L["RANGEDISPLAY_SHOW_TARGET"], onChange = RefreshRangeDisplay },
            { type = "toggle", key = "profile.RangeDisplay.showFocus", label = L["RANGEDISPLAY_SHOW_FOCUS"], onChange = RefreshRangeDisplay },
            { type = "toggle", key = "profile.RangeDisplay.combatOnly", label = L["RANGEDISPLAY_COMBAT_ONLY"], onChange = RefreshRangeDisplay },
            { type = "toggle", key = "profile.RangeDisplay.showUnitLabel", label = L["RANGEDISPLAY_SHOW_LABEL"], onChange = RefreshRangeDisplay },
            { type = "toggle", key = "profile.RangeDisplay.showUnknown", label = L["RANGEDISPLAY_SHOW_UNKNOWN"], onChange = RefreshRangeDisplay },
            { type = "toggle", key = "profile.RangeDisplay.locked", label = L["POSITION_LOCKED"], onChange = RefreshRangeDisplay },

            { type = "header", label = L["RANGEDISPLAY_STYLE_SETTINGS"] },
            { type = "toggle", key = "profile.RangeDisplay.showAccentLine", label = L["RANGEDISPLAY_SHOW_ACCENT_LINE"], onChange = RefreshRangeDisplay },
            { type = "slider", key = "profile.RangeDisplay.width", label = L["RANGEDISPLAY_WIDTH"], min = 80, max = 260, step = 1, onChange = RefreshRangeDisplay },
            { type = "slider", key = "profile.RangeDisplay.height", label = L["RANGEDISPLAY_HEIGHT"], min = 20, max = 64, step = 1, onChange = RefreshRangeDisplay },
            { type = "slider", key = "profile.RangeDisplay.fontSize", label = L["FONT_SIZE"], min = 8, max = 42, step = 1, onChange = RefreshRangeDisplay },
            { type = "slider", key = "profile.RangeDisplay.scale", label = L["SCALE"], min = 0.5, max = 2.0, step = 0.05, onChange = RefreshRangeDisplay },
            { type = "slider", key = "profile.RangeDisplay.bgAlpha", label = L["BACKGROUND_ALPHA"], min = 0, max = 1, step = 0.05, onChange = RefreshRangeDisplay },
            { type = "slider", key = "profile.RangeDisplay.updateRate", label = L["RANGEDISPLAY_UPDATE_RATE"], min = 0.05, max = 1.0, step = 0.05 },
            { type = "dropdown", key = "profile.RangeDisplay.frameStrata", label = L["CHARPOSMARKER_FRAME_STRATA"], options = {
                { text = L["CHARPOSMARKER_STRATA_LOW"], value = "LOW" },
                { text = L["CHARPOSMARKER_STRATA_MEDIUM"], value = "MEDIUM" },
                { text = L["CHARPOSMARKER_STRATA_HIGH"], value = "HIGH" },
              },
              onChange = RefreshRangeDisplay,
            },

            { type = "header", label = L["RANGEDISPLAY_RANGE_COLORS"] },
            { type = "slider", key = "profile.RangeDisplay.nearThreshold", label = L["RANGEDISPLAY_NEAR_THRESHOLD"], min = 5, max = 20, step = 1, onChange = RefreshRangeDisplay },
            { type = "slider", key = "profile.RangeDisplay.farThreshold", label = L["RANGEDISPLAY_FAR_THRESHOLD"], min = 20, max = 100, step = 1, onChange = RefreshRangeDisplay },
            { type = "color", key = "profile.RangeDisplay.nearColor", label = L["RANGEDISPLAY_NEAR_COLOR"], hasAlpha = true, onChange = RefreshRangeDisplay },
            { type = "color", key = "profile.RangeDisplay.mediumColor", label = L["RANGEDISPLAY_MEDIUM_COLOR"], hasAlpha = true, onChange = RefreshRangeDisplay },
            { type = "color", key = "profile.RangeDisplay.farColor", label = L["RANGEDISPLAY_FAR_COLOR"], hasAlpha = true, onChange = RefreshRangeDisplay },
            { type = "color", key = "profile.RangeDisplay.unknownColor", label = L["RANGEDISPLAY_UNKNOWN_COLOR"], hasAlpha = true, onChange = RefreshRangeDisplay },

            { type = "header", label = L["CASTINGALERT_POSITION_SETTINGS"] },
            { type = "slider", key = "profile.RangeDisplay.targetPosition.x", label = L["RANGEDISPLAY_TARGET_POS_X"], min = -800, max = 800, step = 1, onChange = RefreshRangeDisplayPosition },
            { type = "slider", key = "profile.RangeDisplay.targetPosition.y", label = L["RANGEDISPLAY_TARGET_POS_Y"], min = -600, max = 600, step = 1, onChange = RefreshRangeDisplayPosition },
            { type = "slider", key = "profile.RangeDisplay.focusPosition.x", label = L["RANGEDISPLAY_FOCUS_POS_X"], min = -800, max = 800, step = 1, onChange = RefreshRangeDisplayPosition },
            { type = "slider", key = "profile.RangeDisplay.focusPosition.y", label = L["RANGEDISPLAY_FOCUS_POS_Y"], min = -600, max = 600, step = 1, onChange = RefreshRangeDisplayPosition },

            { type = "separator" },
            { type = "button", label = L["TEST_ON_OFF"], onClick = function()
                local mod = ns.modules and ns.modules["RangeDisplay"]
                if mod and mod.TestMode then mod:TestMode() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["RangeDisplay"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
        },
    }

    -----------------------------------------------
    -- PartyTracker
    -----------------------------------------------
    tree.panels["partytracker"] = {
        title = L["PARTYTRACKER_TITLE"],
        desc  = L["PARTYTRACKER_DESC"],
        moduleEnableKey = "profile.modules.PartyTracker",
        settings = {
            -- 모듈 활성화
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.PartyTracker", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            -- 표시 설정
            { type = "header", label = L["PARTYTRACKER_DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.PartyTracker.showInParty", label = L["PARTYTRACKER_SHOW_PARTY"] },
            { type = "toggle", key = "profile.PartyTracker.showInRaid",  label = L["PARTYTRACKER_SHOW_RAID"] },
            { type = "toggle", key = "profile.PartyTracker.showLust",    label = L["PARTYTRACKER_SHOW_LUST"], onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateVisibility then mod:UpdateVisibility() end
            end },
            { type = "toggle", key = "profile.PartyTracker.showManaBar", label = L["PARTYTRACKER_SHOW_MANA_BAR"] },
            { type = "toggle", key = "profile.PartyTracker.showManaText",label = L["PARTYTRACKER_SHOW_MANA_TEXT"] },
            { type = "toggle", key = "profile.PartyTracker.locked",      label = L["POSITION_LOCKED"], onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateLockState then mod:UpdateLockState() end
            end },

            -- 마나 프레임 분리
            { type = "header", label = L["PARTYTRACKER_SEPARATE_MANA"] },
            { type = "toggle", key = "profile.PartyTracker.separateManaFrame", label = L["PARTYTRACKER_SEPARATE_MANA_DESC"] },
            { type = "toggle", key = "profile.PartyTracker.manaLocked",        label = L["PARTYTRACKER_MANA_LOCKED"], onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateLockState then mod:UpdateLockState() end
            end },
            { type = "slider", key = "profile.PartyTracker.manaScale",         label = L["PARTYTRACKER_MANA_SCALE"], min = 0.5, max = 2.0, step = 0.1, onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateManaScale then mod:UpdateManaScale() end
            end },
            { type = "button", label = L["PARTYTRACKER_MANA_POSITION_RESET"], onClick = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.ResetManaPosition then mod:ResetManaPosition() end
            end },

            -- 크기 설정
            { type = "header", label = L["PARTYTRACKER_SIZE_SETTINGS"] },
            { type = "slider", key = "profile.PartyTracker.iconSize", label = L["ICON_SIZE"], min = 20, max = 60, step = 1, onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateIconSize then mod:UpdateIconSize() end
            end },
            { type = "slider", key = "profile.PartyTracker.scale",    label = L["SCALE"],     min = 0.5, max = 2.0, step = 0.1, onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateScale then mod:UpdateScale() end
            end },

            -- 폰트 설정
            { type = "header", label = L["PARTYTRACKER_FONT_SETTINGS"] },
            { type = "font",   key = "profile.PartyTracker.font",     label = L["FONT"], onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateFonts then mod:UpdateFonts() end
            end },
            { type = "slider", key = "profile.PartyTracker.fontSize",  label = L["FONT_SIZE"], min = 8, max = 24, step = 1, onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateFonts then mod:UpdateFonts() end
            end },

            -- 마나바 설정
            { type = "header",    label = L["PARTYTRACKER_MANA_BAR_SETTINGS"] },
            { type = "slider",    key = "profile.PartyTracker.manaBarWidth",   label = L["PARTYTRACKER_MANA_BAR_WIDTH"],   min = 30,  max = 120, step = 5, onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateManaBarSize then mod:UpdateManaBarSize() end
            end },
            { type = "slider",    key = "profile.PartyTracker.manaBarHeight",  label = L["PARTYTRACKER_MANA_BAR_HEIGHT"],  min = 4,   max = 20,  step = 1, onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateManaBarSize then mod:UpdateManaBarSize() end
            end },
            { type = "slider",    key = "profile.PartyTracker.manaBarOffsetX", label = L["PARTYTRACKER_MANA_BAR_OFFSET_X"],min = -50, max = 100, step = 1, onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateManaBarPosition then mod:UpdateManaBarPosition() end
            end },
            { type = "slider",    key = "profile.PartyTracker.manaBarOffsetY", label = L["PARTYTRACKER_MANA_BAR_OFFSET_Y"],min = -30, max = 30,  step = 1, onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateManaBarPosition then mod:UpdateManaBarPosition() end
            end },
            { type = "statusbar", key = "profile.PartyTracker.manaBarTexture", label = L["PARTYTRACKER_MANA_BAR_TEXTURE"], onChange = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.UpdateManaBarTexture then mod:UpdateManaBarTexture() end
            end },

            -- 버튼
            { type = "separator" },
            { type = "button", label = L["TEST_ON_OFF"], onClick = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.TestMode then mod:TestMode() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["PartyTracker"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },

            -- 정보 텍스트
            { type = "header", label = L["PARTYTRACKER_INFO_TITLE"] },
            { type = "text",   label = L["PARTYTRACKER_INFO_TEXT"] },
        },
    }

    -----------------------------------------------
    -- DeathAlert
    -----------------------------------------------
    tree.panels["deathalert"] = {
        title = L["DEATHALERT_TITLE"] or "DeathAlert",
        desc  = L["DEATHALERT_DESC_FULL"] or "사망 알림 설정",
        moduleEnableKey = "profile.modules.DeathAlert",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.DeathAlert", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            { type = "header", label = L["DEATHALERT_DISPLAY_SETTINGS"] or "표시 설정" },
            { type = "toggle", key = "profile.DeathAlert.onlyInstance", label = L["DEATHALERT_ONLY_INSTANCE"] or "인스턴스만" },
            { type = "toggle", key = "profile.DeathAlert.enableRoleIcon", label = L["DEATHALERT_ENABLE_ROLE_ICON"] or "역할 아이콘 표시" },
            { type = "toggle", key = "profile.DeathAlert.enableWipeDetection", label = L["DEATHALERT_WIPE_DETECTION"] or "전멸 방지" },
            { type = "toggle", key = "profile.DeathAlert.enableChatAlert", label = "채팅창 알림 출력" },

            { type = "header", label = L["DEATHALERT_TEXT_SETTINGS"] or "텍스트 설정" },
            { type = "font",   key = "profile.DeathAlert.font", label = L["FONT"] },
            { type = "slider", key = "profile.DeathAlert.fontSize", label = L["FONT_SIZE"], min = 12, max = 40, step = 1 },
            { type = "slider", key = "profile.DeathAlert.messageDuration", label = L["DISPLAY_DURATION"], min = 1, max = 10, step = 1 },
            { type = "toggle", key = "profile.DeathAlert.locked", label = L["POSITION_LOCKED"], onChange = function()
                local mod = ns.modules and ns.modules["DeathAlert"]
                if mod and mod.UpdateVisuals then mod:UpdateVisuals() end
            end },

            { type = "header", label = L["DEATHALERT_SOUND_SETTINGS"] or "사운드 설정" },
            { type = "toggle", key = "profile.DeathAlert.enableSound", label = L["MAILALERT_SOUND_ENABLED"] or "사운드 사용" },
            { type = "sound",  key = "profile.DeathAlert.soundFile", label = L["DEATHALERT_SOUND_MASTER"] or "기본 사운드" },
            { type = "sound",  key = "profile.DeathAlert.tankSound", label = L["DEATHALERT_SOUND_TANK"] or "탱커 전용" },
            { type = "sound",  key = "profile.DeathAlert.healerSound", label = L["DEATHALERT_SOUND_HEALER"] or "힐러 전용" },
            { type = "toggle", key = "profile.DeathAlert.enablePlayerSound", label = L["DEATHALERT_ENABLE_PLAYER_SOUND"] or "본인 전용 사운드 사용" },
            { type = "sound",  key = "profile.DeathAlert.playerSound", label = L["DEATHALERT_SOUND_PLAYER"] or "본인 사망 사운드" },
            { type = "dropdown", key = "profile.DeathAlert.soundChannel", label = L["LFGALERT_SOUND_CHANNEL"], options = "soundChannels" },

            { type = "separator" },
            { type = "button", label = L["TEST_ALERT"] or "알림 테스트", onClick = function()
                local mod = ns.modules and ns.modules["DeathAlert"]
                if mod and mod.TestMode then mod:TestMode() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                ns:SetDBValue("profile.DeathAlert.position", nil)
                local mod = ns.modules and ns.modules["DeathAlert"]
                if mod and mod.UpdateVisuals then mod:UpdateVisuals() end
            end },
        },
    }

    -----------------------------------------------
    -- DeathReleaseGuard
    -----------------------------------------------
    tree.panels["deathreleaseguard"] = {
        title = L["DEATH_RELEASE_GUARD_TITLE"],
        desc = L["DEATH_RELEASE_GUARD_DESC"],
        moduleEnableKey = "profile.modules.DeathReleaseGuard",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            {
                type = "toggle",
                key = "profile.modules.DeathReleaseGuard",
                label = L["MODULE_ENABLED"],
                reloadRequired = true,
                isModuleToggle = true,
            },
            { type = "header", label = L["DEATH_RELEASE_GUARD_SETTINGS"] },
            {
                type = "toggle",
                key = "profile.DeathReleaseGuard.enabled",
                label = L["DEATH_RELEASE_GUARD_ENABLE"],
                onChange = function()
                    local mod = ns.modules and ns.modules["DeathReleaseGuard"]
                    if mod and mod.RefreshSettings then
                        mod:RefreshSettings()
                    end
                end,
            },
            {
                type = "slider",
                key = "profile.DeathReleaseGuard.holdDuration",
                label = L["DEATH_RELEASE_GUARD_HOLD_DURATION"],
                min = 0.5,
                max = 5,
                step = 0.1,
                onChange = function()
                    local mod = ns.modules and ns.modules["DeathReleaseGuard"]
                    if mod and mod.RefreshSettings then
                        mod:RefreshSettings()
                    end
                end,
            },
            { type = "text", label = L["DEATH_RELEASE_GUARD_RAID_ONLY"] },
        },
    }

    -----------------------------------------------
    -- MythicPlusHelper
    -----------------------------------------------
    tree.panels["mythicplus"] = {
        title = L["MYTHICPLUS_TITLE"],
        desc  = L["MYTHICPLUS_DESC_FULL"],
        moduleEnableKey = "profile.modules.MythicPlusHelper",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.MythicPlusHelper", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            { type = "header", label = L["DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.MythicPlusHelper.enabled",       label = L["MYTHICPLUS_ENABLE_OVERLAY"] },
            { type = "toggle", key = "profile.MythicPlusHelper.showTeleports", label = L["MYTHICPLUS_SHOW_TELEPORTS"] },
            { type = "toggle", key = "profile.MythicPlusHelper.showScore",     label = L["MYTHICPLUS_SHOW_SCORE"] },
            { type = "slider", key = "profile.MythicPlusHelper.scale",         label = L["SCALE"], min = 0.5, max = 2.0, step = 0.1 },

            { type = "separator" },
            { type = "button", label = L["MYTHICPLUS_OPEN_TAB"], onClick = function()
                local mod = ns.modules and ns.modules["MythicPlusHelper"]
                if mod and mod.Toggle then mod:Toggle() end
            end },

            { type = "header", label = L["MYTHICPLUS_USAGE_TITLE"] },
            { type = "text",   label = L["MYTHICPLUS_USAGE_TEXT"] },
        },
    }

    -----------------------------------------------
    -- GoldSplit
    -----------------------------------------------
    tree.panels["goldsplit"] = {
        title = L["GOLDSPLIT_TITLE"],
        desc  = L["GOLDSPLIT_DESC_FULL"],
        moduleEnableKey = "profile.modules.GoldSplit",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.GoldSplit", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            -- 채팅 설정
            { type = "header",   label = L["CHAT_SETTINGS"] },
            { type = "dropdown", key = "profile.GoldSplit.chatType", label = L["GOLDSPLIT_DEFAULT_CHANNEL"], options = "chatTypes" },
            { type = "text",     label = L["GOLDSPLIT_NOTE"] },

            -- 위치 설정
            { type = "header", label = L["GOLDSPLIT_POSITION_SETTINGS"] },
            { type = "toggle", key = "profile.GoldSplit.locked", label = L["POSITION_LOCKED"] },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                ns:SetDBValue("profile.GoldSplit.position", nil)
                local mod = ns.modules and ns.modules["GoldSplit"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
            { type = "text", label = L["GOLDSPLIT_DRAG_TIP"] },

            -- 열기
            { type = "separator" },
            { type = "button", label = L["GOLDSPLIT_OPEN_WINDOW"], onClick = function()
                local mod = ns.modules and ns.modules["GoldSplit"]
                if mod and mod.Show then mod:Show() end
            end },
        },
    }

    -----------------------------------------------
    -- DurabilityCheck
    -----------------------------------------------
    tree.panels["durability"] = {
        title = L["DURABILITY_TITLE"],
        desc  = L["DURABILITY_DESC_FULL"],
        moduleEnableKey = "profile.modules.DurabilityCheck",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.DurabilityCheck", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            -- 표시 조건
            { type = "header", label = L["DURABILITY_DISPLAY_CONDITIONS"] },
            { type = "slider", key = "profile.DurabilityCheck.threshold", label = L["DURABILITY_THRESHOLD_DESC"], min = 5, max = 100, step = 5 },
            { type = "text",   label = L["DURABILITY_THRESHOLD_NOTE"] },

            -- 알림 설정
            { type = "header", label = L["DURABILITY_ALERT_SETTINGS"] },
            { type = "toggle", key = "profile.DurabilityCheck.soundEnabled", label = L["DURABILITY_SOUND_DESC"] },
            { type = "sound",  key = "profile.DurabilityCheck.soundFile",    label = L["LFGALERT_SOUND_FILE"], customPathKey = "profile.DurabilityCheck.soundCustomPath" },
            { type = "dropdown", key = "profile.DurabilityCheck.soundChannel", label = L["LFGALERT_SOUND_CHANNEL"], options = "soundChannels" },
            { type = "toggle", key = "profile.DurabilityCheck.locked",       label = L["POSITION_LOCKED"] },

            -- 화면 설정
            { type = "header", label = L["DURABILITY_SCREEN_SETTINGS"] },
            { type = "slider", key = "profile.DurabilityCheck.scale",       label = L["SCALE"],        min = 0.5, max = 2.0, step = 0.1 },
            { type = "font", key = "profile.DurabilityCheck.font",          label = L["FONT"] },
            { type = "slider", key = "profile.DurabilityCheck.titleSize",   label = L["TITLE_SIZE"],   min = 14, max = 48, step = 2 },
            { type = "slider", key = "profile.DurabilityCheck.percentSize", label = L["PERCENT_SIZE"], min = 20, max = 72, step = 2 },

            -- 버튼
            { type = "separator" },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["DurabilityCheck"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
            { type = "button", label = L["TEST_ALERT"], onClick = function()
                local mod = ns.modules and ns.modules["DurabilityCheck"]
                if mod and mod.TestAlert then mod:TestAlert() end
            end },
        },
    }

    -----------------------------------------------
    -- CastingAlert
    -----------------------------------------------
    tree.panels["castingalert"] = {
        title = L["CASTINGALERT_TITLE"],
        desc  = L["CASTINGALERT_DESC"],
        moduleEnableKey = "profile.modules.CastingAlert",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.CastingAlert", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            { type = "toggle", key = "profile.CastingAlert.enabled", label = L["CASTINGALERT_ENABLED"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },

            -- 표시 설정
            { type = "header", label = L["CASTINGALERT_DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.CastingAlert.disableForTank", label = L["CASTINGALERT_DISABLE_FOR_TANK"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "toggle", key = "profile.CastingAlert.ensureOffscreenNameplates", label = L["CASTINGALERT_ENSURE_OFFSCREEN"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.scale",          label = L["SCALE"],                   min = 0.5, max = 2.0, step = 0.1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.updateRate",     label = L["CASTINGALERT_UPDATE_RATE"],min = 0.03, max = 0.5, step = 0.01,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.RestartUpdate then mod:RestartUpdate() end
              end,
            },
            { type = "header", label = L["CASTINGALERT_ICON_SETTINGS"] },
            { type = "toggle", key = "profile.CastingAlert.showSwipe",       label = L["CASTINGALERT_SHOW_SWIPE"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "toggle", key = "profile.CastingAlert.showImportantGlow", label = L["CASTINGALERT_IMPORTANT_GLOW"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "toggle", key = "profile.CastingAlert.indicateInterrupts", label = L["CASTINGALERT_INDICATE_INTERRUPTS"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.maxShow",        label = L["CASTINGALERT_MAX_SHOW"],   min = 1,   max = 15,  step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.iconSize",       label = L["ICON_SIZE"],               min = 20,  max = 80,  step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.iconFontSize",   label = L["CASTINGALERT_ICON_FONT_SIZE"], min = 10, max = 36, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.dimAlpha",       label = L["CASTINGALERT_DIM_ALPHA"],  min = 0,   max = 1,   step = 0.1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.spacing",        label = L["CASTINGALERT_SPACING"],    min = 0,   max = 30,  step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "dropdown", key = "profile.CastingAlert.stackDirection", label = L["CASTINGALERT_STACK_DIRECTION"], options = {
                { text = L["CASTINGALERT_STACK_UP"],      value = "UP" },
                { text = L["CASTINGALERT_STACK_DOWN"],    value = "DOWN" },
                { text = L["CASTINGALERT_STACK_LEFT"],    value = "LEFT" },
                { text = L["CASTINGALERT_STACK_RIGHT"],   value = "RIGHT" },
                { text = L["CASTINGALERT_STACK_OVERLAP"], value = "OVERLAP" },
              },
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },

            -- Filter settings
            { type = "header", label = L["CASTINGALERT_FILTER_SETTINGS"] },
            { type = "toggle", key = "profile.CastingAlert.onlyTargetingMe", label = L["CASTINGALERT_ONLY_TARGETING_ME"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "toggle", key = "profile.CastingAlert.showTarget",      label = L["CASTINGALERT_SHOW_TARGET"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "toggle", key = "profile.CastingAlert.hideUntargeted",  label = L["CASTINGALERT_HIDE_UNTARGETED"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "toggle", key = "profile.CastingAlert.onlyImportant",   label = L["CASTINGALERT_ONLY_IMPORTANT"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },

            -- 텍스트 설정
            { type = "header", label = L["CASTINGALERT_TEXT_SETTINGS"] },
            { type = "font", key = "profile.CastingAlert.font", label = L["FONT"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "toggle", key = "profile.CastingAlert.showDuration", label = L["CASTINGALERT_SHOW_DURATION"],
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },
            { type = "color", key = "profile.CastingAlert.durationTextColor", label = L["CASTINGALERT_DURATION_TEXT_COLOR"], hasAlpha = true,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateStyle then mod:UpdateStyle() end
              end,
            },

            -- 바 설정

            -- 위치 설정
            { type = "header", label = L["CASTINGALERT_POSITION_SETTINGS"] },
            { type = "slider", key = "profile.CastingAlert.iconPosition.x", label = L["CASTINGALERT_ICON_POS_X"], min = -800, max = 800, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateIconPosition then mod:UpdateIconPosition() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.iconPosition.y", label = L["CASTINGALERT_ICON_POS_Y"], min = -600, max = 600, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdateIconPosition then mod:UpdateIconPosition() end
              end,
            },
            -- 사운드 설정
            { type = "header", label = L["CASTINGALERT_SOUND_SETTINGS"] },
            { type = "toggle", key = "profile.CastingAlert.soundEnabled",   label = L["CASTINGALERT_SOUND_ENABLED"] },
            { type = "slider", key = "profile.CastingAlert.soundThreshold", label = L["CASTINGALERT_SOUND_THRESHOLD"], min = 1, max = 5, step = 1 },
            { type = "slider", key = "profile.CastingAlert.soundCooldown",  label = L["CASTINGALERT_SOUND_COOLDOWN"], min = 0, max = 10, step = 0.5 },
            { type = "sound",  key = "profile.CastingAlert.soundFile",      label = L["LFGALERT_SOUND_FILE"], defaultLabel = L["CASTINGALERT_DEFAULT_SOUND"], customPathKey = "profile.CastingAlert.soundCustomPath" },
            { type = "dropdown", key = "profile.CastingAlert.soundChannel", label = L["LFGALERT_SOUND_CHANNEL"], options = "soundChannels" },

            -- 버튼
            { type = "separator" },
            { type = "button", label = L["TEST_ON_OFF"], onClick = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.TestMode then mod:TestMode() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
        },
    }

    local function RefreshFocusInterrupt()
        local mod = (ns.modules and ns.modules["FocusInterrupt"]) or ns.FocusInterrupt
        if mod and mod.QueueStyleRefresh then
            mod:QueueStyleRefresh()
        elseif mod and mod.UpdateStyle then
            mod:UpdateStyle()
        end
    end

    local focusTextPositions = {
        { text = L["ALIGN_LEFT"], value = "LEFT" },
        { text = L["ALIGN_CENTER"], value = "CENTER" },
        { text = L["ALIGN_RIGHT"], value = "RIGHT" },
        { text = L["FOCUSINTERRUPT_POSITION_ABOVE_LEFT"], value = "ABOVE_LEFT" },
        { text = L["FOCUSINTERRUPT_POSITION_ABOVE_CENTER"], value = "ABOVE_CENTER" },
        { text = L["FOCUSINTERRUPT_POSITION_ABOVE_RIGHT"], value = "ABOVE_RIGHT" },
        { text = L["FOCUSINTERRUPT_POSITION_BELOW_LEFT"], value = "BELOW_LEFT" },
        { text = L["FOCUSINTERRUPT_POSITION_BELOW_CENTER"], value = "BELOW_CENTER" },
        { text = L["FOCUSINTERRUPT_POSITION_BELOW_RIGHT"], value = "BELOW_RIGHT" },
    }
    local focusSidePositions = {
        { text = L["ALIGN_LEFT"], value = "LEFT" },
        { text = L["ALIGN_RIGHT"], value = "RIGHT" },
        { text = L["POS_TOP"], value = "TOP" },
        { text = L["POS_BOTTOM"], value = "BOTTOM" },
    }
    local focusFontOutlines = {
        { text = L["FOCUSINTERRUPT_OUTLINE_NONE"], value = "" },
        { text = L["FOCUSINTERRUPT_OUTLINE_NORMAL"], value = "OUTLINE" },
        { text = L["FOCUSINTERRUPT_OUTLINE_THICK"], value = "THICKOUTLINE" },
        { text = L["FOCUSINTERRUPT_OUTLINE_MONOCHROME"], value = "MONOCHROME" },
        { text = L["FOCUSINTERRUPT_OUTLINE_MONOCHROME_OUTLINE"], value = "MONOCHROME,OUTLINE" },
    }
    local focusFrameStrata = {
        { text = L["FOCUSINTERRUPT_STRATA_LOW"], value = "LOW" },
        { text = L["FOCUSINTERRUPT_STRATA_MEDIUM"], value = "MEDIUM" },
        { text = L["FOCUSINTERRUPT_STRATA_HIGH"], value = "HIGH" },
        { text = L["FOCUSINTERRUPT_STRATA_DIALOG"], value = "DIALOG" },
    }
    local focusTimeFormats = {
        { text = L["FOCUSINTERRUPT_TIME_REMAINING_TOTAL"], value = "REMAINING_TOTAL" },
        { text = L["FOCUSINTERRUPT_TIME_REMAINING"], value = "REMAINING" },
        { text = L["FOCUSINTERRUPT_TIME_TOTAL"], value = "TOTAL" },
    }

    -----------------------------------------------
    -- FocusInterrupt
    -----------------------------------------------
    tree.panels["focusinterrupt"] = {
        title = L["FOCUSINTERRUPT_TITLE"],
        desc  = L["FOCUSINTERRUPT_DESC"],
        moduleEnableKey = "profile.modules.FocusInterrupt",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.FocusInterrupt", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            { type = "header", label = L["DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.FocusInterrupt.showTarget", label = L["FOCUSINTERRUPT_SHOW_TARGET_BAR"], onChange = RefreshFocusInterrupt },
            { type = "toggle", key = "profile.FocusInterrupt.showFocus", label = L["FOCUSINTERRUPT_SHOW_FOCUS_BAR"], onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.interruptedHoldTime", label = L["FOCUSINTERRUPT_INTERRUPTED_HOLD_TIME"], min = 0, max = 5, step = 0.1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.updateRate", label = L["CASTINGALERT_UPDATE_RATE"], min = 0.02, max = 0.5, step = 0.01, onChange = RefreshFocusInterrupt },

            { type = "header", label = L["FOCUSINTERRUPT_BAR_SETTINGS"] },
            { type = "slider", key = "profile.FocusInterrupt.barWidth", label = L["FOCUSINTERRUPT_BAR_WIDTH"], min = 80, max = 600, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.barHeight", label = L["FOCUSINTERRUPT_BAR_HEIGHT"], min = 8, max = 80, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.targetScale", label = L["FOCUSINTERRUPT_TARGET_SCALE"], min = 0.5, max = 3, step = 0.05, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.focusScale", label = L["FOCUSINTERRUPT_FOCUS_SCALE"], min = 0.5, max = 3, step = 0.05, onChange = RefreshFocusInterrupt },
            { type = "statusbar", key = "profile.FocusInterrupt.texture", label = L["FOCUSINTERRUPT_TEXTURE"], onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.barAlpha", label = L["FOCUSINTERRUPT_BAR_ALPHA"], min = 0, max = 1, step = 0.05, onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.backgroundColor", label = L["FOCUSINTERRUPT_BACKGROUND_COLOR"], hasAlpha = false, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.bgAlpha", label = L["BACKGROUND_ALPHA"], min = 0, max = 1, step = 0.05, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.barBorderSize", label = L["FOCUSINTERRUPT_BAR_BORDER_SIZE"], min = 0, max = 12, step = 1, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.frameStrata", label = L["FOCUSINTERRUPT_FRAME_STRATA"], options = focusFrameStrata, onChange = RefreshFocusInterrupt },

            { type = "header", label = L["FOCUSINTERRUPT_SPELL_TEXT_SETTINGS"] },
            { type = "toggle", key = "profile.FocusInterrupt.showSpellName", label = L["FOCUSINTERRUPT_SHOW_SPELL_TEXT"], onChange = RefreshFocusInterrupt },
            { type = "font", key = "profile.FocusInterrupt.spellNameFont", label = L["FONT"], onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.spellNameFontSize", label = L["FONT_SIZE"], min = 6, max = 48, step = 1, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.spellNameOutline", label = L["FOCUSINTERRUPT_FONT_OUTLINE"], options = focusFontOutlines, onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.spellNameColor", label = L["TEXT_COLOR"], hasAlpha = true, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.spellNamePosition", label = L["FOCUSINTERRUPT_TEXT_POSITION"], options = focusTextPositions, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.spellNameOffsetX", label = L["X_OFFSET"], min = -200, max = 200, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.spellNameOffsetY", label = L["Y_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },

            { type = "header", label = L["FOCUSINTERRUPT_TIME_TEXT_SETTINGS"] },
            { type = "toggle", key = "profile.FocusInterrupt.showTimeText", label = L["FOCUSINTERRUPT_SHOW_TIME_TEXT"], onChange = RefreshFocusInterrupt },
            { type = "font", key = "profile.FocusInterrupt.timeTextFont", label = L["FONT"], onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.timeTextFontSize", label = L["FONT_SIZE"], min = 6, max = 48, step = 1, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.timeTextOutline", label = L["FOCUSINTERRUPT_FONT_OUTLINE"], options = focusFontOutlines, onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.timeTextColor", label = L["TEXT_COLOR"], hasAlpha = true, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.timeTextPosition", label = L["FOCUSINTERRUPT_TEXT_POSITION"], options = focusTextPositions, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.timeTextOffsetX", label = L["X_OFFSET"], min = -200, max = 200, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.timeTextOffsetY", label = L["Y_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.timeTextFormat", label = L["FOCUSINTERRUPT_TIME_FORMAT"], options = focusTimeFormats, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.timeTextDecimals", label = L["FOCUSINTERRUPT_TIME_DECIMALS"], min = 0, max = 2, step = 1, onChange = RefreshFocusInterrupt },

            { type = "header", label = L["FOCUSINTERRUPT_TARGET_TEXT_SETTINGS"] },
            { type = "toggle", key = "profile.FocusInterrupt.showTargetText", label = L["FOCUSINTERRUPT_SHOW_TARGET_TEXT"], onChange = RefreshFocusInterrupt },
            { type = "font", key = "profile.FocusInterrupt.targetTextFont", label = L["FONT"], onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.targetTextFontSize", label = L["FONT_SIZE"], min = 6, max = 48, step = 1, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.targetTextOutline", label = L["FOCUSINTERRUPT_FONT_OUTLINE"], options = focusFontOutlines, onChange = RefreshFocusInterrupt },
            { type = "toggle", key = "profile.FocusInterrupt.targetTextUseClassColor", label = L["FOCUSINTERRUPT_TARGET_CLASS_COLOR"], onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.targetTextColor", label = L["TEXT_COLOR"], hasAlpha = true, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.targetTextPosition", label = L["FOCUSINTERRUPT_TARGET_TEXT_POSITION"], options = focusTextPositions, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.targetTextOffsetX", label = L["X_OFFSET"], min = -200, max = 200, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.targetTextOffsetY", label = L["Y_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },

            { type = "header", label = L["FOCUSINTERRUPT_ICON_SETTINGS"] },
            { type = "toggle", key = "profile.FocusInterrupt.showIcon", label = L["SHOW_ICON"], onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.iconWidth", label = L["WIDTH"], min = 8, max = 100, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.iconHeight", label = L["HEIGHT"], min = 8, max = 100, step = 1, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.iconPosition", label = L["FOCUSINTERRUPT_ICON_POSITION"], options = focusSidePositions, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.iconOffsetX", label = L["X_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.iconOffsetY", label = L["Y_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.iconZoom", label = L["FOCUSINTERRUPT_ICON_ZOOM"], min = 0, max = 0.45, step = 0.01, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.iconBorderSize", label = L["FOCUSINTERRUPT_ICON_BORDER_SIZE"], min = 0, max = 12, step = 1, onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.iconBorderColor", label = L["FOCUSINTERRUPT_ICON_BORDER_COLOR"], hasAlpha = true, onChange = RefreshFocusInterrupt },

            { type = "header", label = L["FOCUSINTERRUPT_INDICATOR_SETTINGS"] },
            { type = "toggle", key = "profile.FocusInterrupt.showRaidMarker", label = L["FOCUSINTERRUPT_SHOW_RAID_MARKER"], onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.raidMarkerSize", label = L["FOCUSINTERRUPT_RAID_MARKER_SIZE"], min = 6, max = 64, step = 1, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.raidMarkerPosition", label = L["FOCUSINTERRUPT_RAID_MARKER_POSITION"], options = focusSidePositions, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.raidMarkerOffsetX", label = L["X_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.raidMarkerOffsetY", label = L["Y_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },
            { type = "toggle", key = "profile.FocusInterrupt.showTargetIndicator", label = L["FOCUSINTERRUPT_SHOW_TARGET_INDICATOR"], onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.targetIndicatorSize", label = L["FOCUSINTERRUPT_TARGET_INDICATOR_SIZE"], min = 8, max = 64, step = 1, onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.targetIndicatorColor", label = L["FOCUSINTERRUPT_TARGET_INDICATOR_COLOR"], hasAlpha = true, onChange = RefreshFocusInterrupt },
            { type = "dropdown", key = "profile.FocusInterrupt.targetIndicatorPosition", label = L["FOCUSINTERRUPT_TARGET_INDICATOR_POSITION"], options = focusSidePositions, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.targetIndicatorOffsetX", label = L["X_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.targetIndicatorOffsetY", label = L["Y_OFFSET"], min = -100, max = 100, step = 1, onChange = RefreshFocusInterrupt },

            { type = "header", label = L["FOCUSINTERRUPT_COLOR_SETTINGS"] },
            { type = "color", key = "profile.FocusInterrupt.interruptibleColor", label = L["FOCUSINTERRUPT_INTERRUPTIBLE_COLOR"], hasAlpha = false, onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.notInterruptibleColor", label = L["FOCUSINTERRUPT_NOTINT_COLOR"], hasAlpha = false, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.notInterruptibleAlpha", label = L["FOCUSINTERRUPT_NOTINT_ALPHA"], min = 0, max = 1, step = 0.05, onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.interruptedColor", label = L["FOCUSINTERRUPT_INTERRUPTED_COLOR"], hasAlpha = false, onChange = RefreshFocusInterrupt },
            { type = "toggle", key = "profile.FocusInterrupt.showImportantAlert", label = L["FOCUSINTERRUPT_SHOW_IMPORTANT_ALERT"], onChange = RefreshFocusInterrupt },
            { type = "color", key = "profile.FocusInterrupt.importantAlertColor", label = L["FOCUSINTERRUPT_IMPORTANT_ALERT_COLOR"], hasAlpha = true, onChange = RefreshFocusInterrupt },
            { type = "slider", key = "profile.FocusInterrupt.importantAlertAlpha", label = L["FOCUSINTERRUPT_IMPORTANT_ALERT_ALPHA"], min = 0, max = 1, step = 0.05, onChange = RefreshFocusInterrupt },

            { type = "header", label = L["FOCUSINTERRUPT_SOUND_SETTINGS"] },
            { type = "toggle", key = "profile.FocusInterrupt.focusSoundEnabled", label = L["FOCUSINTERRUPT_FOCUS_SOUND_ENABLED"] },
            { type = "slider", key = "profile.FocusInterrupt.focusSoundCooldown", label = L["FOCUSINTERRUPT_SOUND_COOLDOWN"], min = 0, max = 10, step = 0.5 },
            { type = "sound", key = "profile.FocusInterrupt.focusSoundFile", label = L["LFGALERT_SOUND_FILE"], defaultLabel = L["FOCUSINTERRUPT_DEFAULT_SOUND"], customPathKey = "profile.FocusInterrupt.focusSoundCustomPath" },
            { type = "dropdown", key = "profile.FocusInterrupt.focusSoundChannel", label = L["LFGALERT_SOUND_CHANNEL"], options = "soundChannels" },

            -- 버튼
            { type = "separator" },
            { type = "button", label = L["TEST_ON_OFF"], onClick = function()
                local mod = ns.modules and ns.modules["FocusInterrupt"]
                if mod and mod.TestMode then mod:TestMode() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["FocusInterrupt"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
        },
    }

    -----------------------------------------------
    -- SkyridingTracker
    -----------------------------------------------
    tree.panels["skyridingtracker"] = {
        title = L["SKYRIDINGTRACKER_TITLE"],
        desc  = L["SKYRIDINGTRACKER_DESC"],
        moduleEnableKey = "profile.modules.SkyridingTracker",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.SkyridingTracker", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            { type = "header", label = L["DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.SkyridingTracker.hideWhenFull", label = L["SKYRIDINGTRACKER_HIDE_WHEN_FULL"] },
            { type = "slider", key = "profile.SkyridingTracker.scale", label = L["SCALE"], min = 0.5, max = 2.0, step = 0.05,
              onChange = function()
                local mod = ns.modules and ns.modules["SkyridingTracker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.SkyridingTracker.posX", label = L["SKYRIDINGTRACKER_POS_X"], min = -500, max = 500, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["SkyridingTracker"]
                if mod and mod.ApplyPosition then mod:ApplyPosition() end
              end,
            },
            { type = "slider", key = "profile.SkyridingTracker.posY", label = L["SKYRIDINGTRACKER_POS_Y"], min = -500, max = 500, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["SkyridingTracker"]
                if mod and mod.ApplyPosition then mod:ApplyPosition() end
              end,
            },
            { type = "slider", key = "profile.SkyridingTracker.fadeOutDuration", label = L["SKYRIDINGTRACKER_FADEOUT"], min = 0, max = 3.0, step = 0.1,
              onChange = function()
                local mod = ns.modules and ns.modules["SkyridingTracker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "dropdown", key = "profile.SkyridingTracker.surgePosition", label = L["SKYRIDINGTRACKER_SURGE_POS"],
              options = {
                  { value = "bottom", text = L["SKYRIDINGTRACKER_SURGE_BOTTOM"] },
                  { value = "top",    text = L["SKYRIDINGTRACKER_SURGE_TOP"] },
              },
              onChange = function()
                local mod = ns.modules and ns.modules["SkyridingTracker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },

            -- 텍스처
            { type = "header", label = L["TEXTURE"] },
            { type = "statusbar", key = "profile.SkyridingTracker.barTexture", label = L["TEXTURE"],
              onChange = function()
                local mod = ns.modules and ns.modules["SkyridingTracker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "slider", key = "profile.SkyridingTracker.borderSize", label = L["SKYRIDINGTRACKER_BORDER"], min = 0, max = 8, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["SkyridingTracker"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },

            -- 색상: 기력
            { type = "header", label = L["SKYRIDINGTRACKER_COLOR_VIGOR"] },
            { type = "color", key = "profile.SkyridingTracker.vigorColor", label = L["SKYRIDINGTRACKER_COLOR_VIGOR_ACTIVE"], hasAlpha = false,
              onChange = function() local m = ns.modules and ns.modules["SkyridingTracker"]; if m and m.ApplyColors then m:ApplyColors() end end,
            },
            { type = "color", key = "profile.SkyridingTracker.vigorDimColor", label = L["SKYRIDINGTRACKER_COLOR_VIGOR_DIM"], hasAlpha = false,
              onChange = function() local m = ns.modules and ns.modules["SkyridingTracker"]; if m and m.ApplyColors then m:ApplyColors() end end,
            },

            -- 색상: 재기의 바람
            { type = "header", label = L["SKYRIDINGTRACKER_COLOR_WIND"] },
            { type = "color", key = "profile.SkyridingTracker.windColor", label = L["SKYRIDINGTRACKER_COLOR_WIND_ACTIVE"], hasAlpha = false,
              onChange = function() local m = ns.modules and ns.modules["SkyridingTracker"]; if m and m.ApplyColors then m:ApplyColors() end end,
            },
            { type = "color", key = "profile.SkyridingTracker.windDimColor", label = L["SKYRIDINGTRACKER_COLOR_WIND_DIM"], hasAlpha = false,
              onChange = function() local m = ns.modules and ns.modules["SkyridingTracker"]; if m and m.ApplyColors then m:ApplyColors() end end,
            },

            -- 색상: 소용돌이 쇄도
            { type = "header", label = L["SKYRIDINGTRACKER_COLOR_SURGE"] },
            { type = "color", key = "profile.SkyridingTracker.surgeColor", label = L["SKYRIDINGTRACKER_COLOR_SURGE_ACTIVE"], hasAlpha = false,
              onChange = function() local m = ns.modules and ns.modules["SkyridingTracker"]; if m and m.ApplyColors then m:ApplyColors() end end,
            },
            { type = "color", key = "profile.SkyridingTracker.surgeDimColor", label = L["SKYRIDINGTRACKER_COLOR_SURGE_DIM"], hasAlpha = false,
              onChange = function() local m = ns.modules and ns.modules["SkyridingTracker"]; if m and m.ApplyColors then m:ApplyColors() end end,
            },

            { type = "separator" },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["SkyridingTracker"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },

            { type = "header", label = L["SKYRIDINGTRACKER_INFO_TITLE"] },
            { type = "text",   label = L["SKYRIDINGTRACKER_INFO_TEXT"] },
        },
    }

    -----------------------------------------------
    -- AutoRepair
    -----------------------------------------------
    tree.panels["autorepair"] = {
        title = L["AUTOREPAIR_TITLE"],
        desc  = L["AUTOREPAIR_DESC"],
        moduleEnableKey = "profile.modules.AutoRepair",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.AutoRepair", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            { type = "header", label = L["AUTOREPAIR_TITLE"] },
            { type = "toggle", key = "profile.AutoRepair.useGuildBank", label = L["AUTOREPAIR_USE_GUILD_BANK"] },
            { type = "text",   label = L["AUTOREPAIR_GUILD_BANK_NOTE"] },
            { type = "toggle", key = "profile.AutoRepair.chatOutput",   label = L["AUTOREPAIR_CHAT_OUTPUT"] },
        },
    }

    -----------------------------------------------
    -- RaidLootPass
    -----------------------------------------------
    tree.panels["raidlootpass"] = {
        title = L["RAIDLOOTPASS_TITLE"],
        desc  = L["RAIDLOOTPASS_DESC"],
        moduleEnableKey = "profile.modules.RaidLootPass",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.RaidLootPass", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            { type = "header", label = L["RAIDLOOTPASS_TITLE"] },
            { type = "toggle", key = "profile.RaidLootPass.enabled", label = L["RAIDLOOTPASS_ENABLED"],
              onChange = function()
                local mod = ns.modules and ns.modules["RaidLootPass"]
                if mod and mod.ApplySettings then mod:ApplySettings() end
              end,
            },
            { type = "toggle", key = "profile.RaidLootPass.chatOutput", label = L["RAIDLOOTPASS_CHAT_OUTPUT"] },
            { type = "text", label = L["RAIDLOOTPASS_INFO_TEXT"] },
        },
    }


    self.ConfigTree = tree
    return tree
end
