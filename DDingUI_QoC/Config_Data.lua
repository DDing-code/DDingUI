--[[
    DDingQoC - Config_Data.lua
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
    combattimer     = "CombatTimer",
    buffchecker     = "BuffChecker",
    castingalert    = "CastingAlert",
    focusinterrupt  = "FocusInterrupt",
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
        { text = L["TAB_COMBATTIMER"],      key = "combattimer" },
        { text = L["TAB_BUFFCHECKER"],      key = "buffchecker" },
        { text = L["TAB_CASTINGALERT"],     key = "castingalert" },
        { text = L["TAB_FOCUSINTERRUPT"],   key = "focusinterrupt" },
    }

    -----------------------------------------------
    -- 패널 정의
    -----------------------------------------------
    tree.panels = {}

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
    tree.panels["itemlevel"] = {
        title = L["ITEMLEVEL_TITLE"],
        desc  = L["ITEMLEVEL_DESC"],
        moduleEnableKey = "profile.modules.ItemLevel",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.ItemLevel", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            -- 표시 설정
            { type = "header", label = L["ITEMLEVEL_DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.ItemLevel.showItemLevel",    label = L["ITEMLEVEL_SHOW_ILVL"] },
            { type = "toggle", key = "profile.ItemLevel.showEnchant",      label = L["ITEMLEVEL_SHOW_ENCHANT"] },
            { type = "toggle", key = "profile.ItemLevel.showGems",         label = L["ITEMLEVEL_SHOW_GEMS"] },
            { type = "toggle", key = "profile.ItemLevel.showAverageIlvl",  label = L["ITEMLEVEL_SHOW_AVG"] },
            { type = "toggle", key = "profile.ItemLevel.showEnhancedStats",label = L["ITEMLEVEL_SHOW_ENHANCED"] },

            -- 본인 캐릭터
            { type = "header", label = L["ITEMLEVEL_SELF_SETTINGS"] },
            { type = "slider", key = "profile.ItemLevel.selfIlvlSize",    label = L["ITEMLEVEL_SELF_ILVL_SIZE"],    min = 8, max = 20, step = 1 },
            { type = "slider", key = "profile.ItemLevel.selfEnchantSize", label = L["ITEMLEVEL_SELF_ENCHANT_SIZE"], min = 8, max = 16, step = 1 },
            { type = "slider", key = "profile.ItemLevel.selfGemSize",     label = L["ITEMLEVEL_SELF_GEM_SIZE"],     min = 10, max = 24, step = 1 },
            { type = "slider", key = "profile.ItemLevel.selfAvgSize",     label = L["ITEMLEVEL_SELF_AVG_SIZE"],     min = 12, max = 24, step = 1 },

            -- 살펴보기
            { type = "header", label = L["ITEMLEVEL_INSPECT_SETTINGS"] },
            { type = "slider", key = "profile.ItemLevel.inspIlvlSize",    label = L["ITEMLEVEL_INSPECT_ILVL_SIZE"],    min = 8, max = 20, step = 1 },
            { type = "slider", key = "profile.ItemLevel.inspEnchantSize", label = L["ITEMLEVEL_INSPECT_ENCHANT_SIZE"], min = 8, max = 16, step = 1 },
            { type = "slider", key = "profile.ItemLevel.inspGemSize",     label = L["ITEMLEVEL_INSPECT_GEM_SIZE"],     min = 10, max = 24, step = 1 },

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
            { type = "toggle", key = "profile.PartyTracker.showManaBar", label = L["PARTYTRACKER_SHOW_MANA_BAR"] },
            { type = "toggle", key = "profile.PartyTracker.showManaText",label = L["PARTYTRACKER_SHOW_MANA_TEXT"] },
            { type = "toggle", key = "profile.PartyTracker.locked",      label = L["POSITION_LOCKED"] },

            -- 마나 프레임 분리
            { type = "header", label = L["PARTYTRACKER_SEPARATE_MANA"] },
            { type = "toggle", key = "profile.PartyTracker.separateManaFrame", label = L["PARTYTRACKER_SEPARATE_MANA_DESC"] },
            { type = "toggle", key = "profile.PartyTracker.manaLocked",        label = L["PARTYTRACKER_MANA_LOCKED"] },
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
            { type = "toggle", key = "profile.DurabilityCheck.locked",       label = L["POSITION_LOCKED"] },

            -- 화면 설정
            { type = "header", label = L["DURABILITY_SCREEN_SETTINGS"] },
            { type = "slider", key = "profile.DurabilityCheck.scale",       label = L["SCALE"],        min = 0.5, max = 2.0, step = 0.1 },
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
    -- BuffChecker
    -----------------------------------------------
    tree.panels["buffchecker"] = {
        title = L["BUFFCHECKER_TITLE"],
        desc  = L["BUFFCHECKER_DESC"],
        moduleEnableKey = "profile.modules.BuffChecker",
        settings = {
            -- 기본
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.BuffChecker", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            -- 체크 항목
            { type = "header", label = L["BUFFCHECKER_CHECK_ITEMS"] },
            { type = "toggle", key = "profile.BuffChecker.showFood",   label = L["BUFFCHECKER_CHECK_FOOD"] },
            { type = "toggle", key = "profile.BuffChecker.showFlask",  label = L["BUFFCHECKER_CHECK_FLASK"] },
            { type = "toggle", key = "profile.BuffChecker.showWeapon", label = L["BUFFCHECKER_CHECK_WEAPON"] },
            { type = "toggle", key = "profile.BuffChecker.showRune",   label = L["BUFFCHECKER_CHECK_RUNE"] },

            -- 표시 조건
            { type = "header", label = L["BUFFCHECKER_DISPLAY_CONDITIONS"] },
            { type = "toggle", key = "profile.BuffChecker.instanceOnly", label = L["BUFFCHECKER_INSTANCE_ONLY"] },
            { type = "button", label = L["ALL_CHECK_ON"], onClick = function()
                ns:SetDBValue("profile.BuffChecker.showFood", true)
                ns:SetDBValue("profile.BuffChecker.showFlask", true)
                ns:SetDBValue("profile.BuffChecker.showWeapon", true)
                ns:SetDBValue("profile.BuffChecker.showRune", true)
            end },
            { type = "button", label = L["ALL_CHECK_OFF"], onClick = function()
                ns:SetDBValue("profile.BuffChecker.showFood", false)
                ns:SetDBValue("profile.BuffChecker.showFlask", false)
                ns:SetDBValue("profile.BuffChecker.showWeapon", false)
                ns:SetDBValue("profile.BuffChecker.showRune", false)
            end },

            -- 표시 설정
            { type = "header",   label = L["BUFFCHECKER_DISPLAY_SETTINGS"] },
            { type = "slider",   key = "profile.BuffChecker.iconSize",   label = L["ICON_SIZE"], min = 20, max = 80, step = 5 },
            { type = "slider",   key = "profile.BuffChecker.scale",      label = L["SCALE"],     min = 0.5, max = 2.0, step = 0.1 },
            { type = "dropdown", key = "profile.BuffChecker.alignment",  label = L["TEXT_ALIGN"], options = "alignOptions" },
            { type = "toggle",   key = "profile.BuffChecker.locked",     label = L["POSITION_LOCKED"] },

            -- 텍스트 설정
            { type = "header", label = L["BUFFCHECKER_TEXT_SETTINGS"] },
            { type = "toggle", key = "profile.BuffChecker.showText",  label = L["SHOW_TEXT"] },
            { type = "slider", key = "profile.BuffChecker.textSize",  label = L["FONT_SIZE"], min = 8, max = 20, step = 1 },
            { type = "font",   key = "profile.BuffChecker.textFont",  label = L["BUFFCHECKER_TEXT_FONT"] },
            { type = "color",  key = "profile.BuffChecker.textColor", label = L["TEXT_COLOR"], hasAlpha = false, colorFormat = "rgb_object" },

            -- 버튼
            { type = "separator" },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["BuffChecker"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },
            { type = "button", label = L["TEST_ON_OFF"], onClick = function()
                local mod = ns.modules and ns.modules["BuffChecker"]
                if mod and mod.TestMode then mod:TestMode() end
            end },
        },
    }

    -----------------------------------------------
    -- KeystoneTracker
    -----------------------------------------------
    tree.panels["keystonetracker"] = {
        title = L["KEYSTONETRACKER_TITLE"],
        desc  = L["KEYSTONETRACKER_DESC"],
        moduleEnableKey = "profile.modules.KeystoneTracker",
        settings = {
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.KeystoneTracker", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },
            { type = "header", label = L["DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.KeystoneTracker.showInParty", label = L["KEYSTONETRACKER_SHOW_IN_PARTY"] },
            { type = "toggle", key = "profile.KeystoneTracker.showInRaid",  label = L["KEYSTONETRACKER_SHOW_IN_RAID"] },
            { type = "toggle", key = "profile.KeystoneTracker.locked",      label = L["POSITION_LOCKED"] },
            { type = "slider", key = "profile.KeystoneTracker.scale",       label = L["SCALE"],     min = 0.5, max = 2.0, step = 0.1 },
            { type = "slider", key = "profile.KeystoneTracker.fontSize",    label = L["FONT_SIZE"], min = 8,   max = 20,  step = 1 },

            { type = "separator" },
            { type = "button", label = L["KEYSTONETRACKER_TOGGLE_WINDOW"], onClick = function()
                local mod = ns.modules and ns.modules["KeystoneTracker"]
                if mod and mod.Toggle then mod:Toggle() end
            end },
            { type = "button", label = L["RESET_POSITION"], onClick = function()
                local mod = ns.modules and ns.modules["KeystoneTracker"]
                if mod and mod.ResetPosition then mod:ResetPosition() end
            end },

            { type = "header", label = L["KEYSTONETRACKER_USAGE_TITLE"] },
            { type = "text",   label = L["KEYSTONETRACKER_USAGE_TEXT"] },
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
            -- 표시 설정
            { type = "header", label = L["CASTINGALERT_DISPLAY_SETTINGS"] },
            { type = "toggle", key = "profile.CastingAlert.disableForTank", label = L["CASTINGALERT_DISABLE_FOR_TANK"] },
            { type = "toggle", key = "profile.CastingAlert.onlyTargetingMe",label = L["CASTINGALERT_ONLY_TARGETING_ME"] },
            { type = "toggle", key = "profile.CastingAlert.showTarget",     label = L["CASTINGALERT_SHOW_TARGET"] },
            { type = "slider", key = "profile.CastingAlert.maxShow",        label = L["CASTINGALERT_MAX_SHOW"],   min = 1,   max = 15,  step = 1 },
            { type = "slider", key = "profile.CastingAlert.iconSize",       label = L["ICON_SIZE"],               min = 20,  max = 80,  step = 1 },
            { type = "slider", key = "profile.CastingAlert.fontSize",       label = L["FONT_SIZE"],               min = 10,  max = 30,  step = 1 },
            { type = "slider", key = "profile.CastingAlert.dimAlpha",       label = L["CASTINGALERT_DIM_ALPHA"],  min = 0,   max = 1,   step = 0.1 },
            { type = "slider", key = "profile.CastingAlert.scale",          label = L["SCALE"],                   min = 0.5, max = 2.0, step = 0.1 },
            { type = "slider", key = "profile.CastingAlert.updateRate",     label = L["CASTINGALERT_UPDATE_RATE"],min = 0.1, max = 0.5, step = 0.05 },

            -- 위치 설정
            { type = "header", label = L["CASTINGALERT_POSITION_SETTINGS"] },
            { type = "slider", key = "profile.CastingAlert.position.x", label = L["CASTINGALERT_POS_X"], min = -600, max = 600, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdatePosition then mod:UpdatePosition() end
              end,
            },
            { type = "slider", key = "profile.CastingAlert.position.y", label = L["CASTINGALERT_POS_Y"], min = -400, max = 400, step = 1,
              onChange = function()
                local mod = ns.modules and ns.modules["CastingAlert"]
                if mod and mod.UpdatePosition then mod:UpdatePosition() end
              end,
            },

            -- 사운드 설정
            { type = "header", label = L["CASTINGALERT_SOUND_SETTINGS"] },
            { type = "toggle", key = "profile.CastingAlert.soundEnabled",   label = L["CASTINGALERT_SOUND_ENABLED"] },
            { type = "slider", key = "profile.CastingAlert.soundThreshold", label = L["CASTINGALERT_SOUND_THRESHOLD"], min = 1, max = 5, step = 1 },
            { type = "sound",  key = "profile.CastingAlert.soundFile",      label = L["LFGALERT_SOUND_FILE"], defaultLabel = L["CASTINGALERT_DEFAULT_SOUND"], customPathKey = "profile.CastingAlert.soundCustomPath" },

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
            -- 활성화
            { type = "header", label = L["DISPLAY_SETTINGS"] },

            -- 시전바 설정
            { type = "header", label = L["FOCUSINTERRUPT_BAR_SETTINGS"] },
            { type = "slider",    key = "profile.FocusInterrupt.barWidth",  label = L["FOCUSINTERRUPT_BAR_WIDTH"],  min = 100, max = 500, step = 5 },
            { type = "slider",    key = "profile.FocusInterrupt.barHeight", label = L["FOCUSINTERRUPT_BAR_HEIGHT"], min = 15,  max = 60,  step = 1 },
            { type = "slider",    key = "profile.FocusInterrupt.bgAlpha",   label = L["BACKGROUND_ALPHA"],          min = 0,   max = 1,   step = 0.1 },
            { type = "slider",    key = "profile.FocusInterrupt.fontSize",  label = L["FONT_SIZE"],                 min = 8,   max = 24,  step = 1 },
            { type = "slider",    key = "profile.FocusInterrupt.scale",     label = L["SCALE"],                     min = 0.5, max = 2.0, step = 0.1 },
            { type = "statusbar", key = "profile.FocusInterrupt.texture",   label = L["FOCUSINTERRUPT_TEXTURE"] },

            -- 차단 설정
            { type = "header", label = L["FOCUSINTERRUPT_INT_SETTINGS"] },
            { type = "toggle", key = "profile.FocusInterrupt.notInterruptibleHide", label = L["FOCUSINTERRUPT_NOTINT_HIDE"] },
            { type = "toggle", key = "profile.FocusInterrupt.cooldownHide",         label = L["FOCUSINTERRUPT_CD_HIDE"] },
            { type = "toggle", key = "profile.FocusInterrupt.showKickIcon",         label = L["FOCUSINTERRUPT_SHOW_KICK_ICON"] },
            { type = "toggle", key = "profile.FocusInterrupt.showInterrupter",      label = L["FOCUSINTERRUPT_SHOW_INTERRUPTER"] },
            { type = "toggle", key = "profile.FocusInterrupt.showTarget",           label = L["FOCUSINTERRUPT_SHOW_TARGET"] },
            { type = "toggle", key = "profile.FocusInterrupt.showTime",             label = L["FOCUSINTERRUPT_SHOW_TIME"] },
            { type = "toggle", key = "profile.FocusInterrupt.mute",                 label = L["FOCUSINTERRUPT_MUTE"] },
            { type = "sound",  key = "profile.FocusInterrupt.soundFile",            label = L["LFGALERT_SOUND_FILE"], defaultLabel = L["FOCUSINTERRUPT_DEFAULT_SOUND"], customPathKey = "profile.FocusInterrupt.soundCustomPath" },
            { type = "slider", key = "profile.FocusInterrupt.interruptedFadeTime",  label = L["FOCUSINTERRUPT_FADE_TIME"],     min = 0,  max = 2,  step = 0.25 },
            { type = "slider", key = "profile.FocusInterrupt.kickIconSize",         label = L["FOCUSINTERRUPT_KICK_ICON_SIZE"],min = 15, max = 60, step = 1 },

            -- 색상 설정
            { type = "header", label = L["FOCUSINTERRUPT_COLOR_SETTINGS"] },
            { type = "color", key = "profile.FocusInterrupt.interruptibleColor",    label = L["FOCUSINTERRUPT_INTERRUPTIBLE_COLOR"], hasAlpha = false },
            { type = "color", key = "profile.FocusInterrupt.notInterruptibleColor", label = L["FOCUSINTERRUPT_NOTINT_COLOR"],       hasAlpha = false },
            { type = "color", key = "profile.FocusInterrupt.cooldownColor",         label = L["FOCUSINTERRUPT_CD_COLOR"],           hasAlpha = false },
            { type = "color", key = "profile.FocusInterrupt.interruptedColor",      label = L["FOCUSINTERRUPT_INTERRUPTED_COLOR"],  hasAlpha = false },

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

    self.ConfigTree = tree
    return tree
end
