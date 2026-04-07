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
    partytracker    = "PartyTracker",
    durability      = "DurabilityCheck",
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
        { text = L["TAB_PARTYTRACKER"],     key = "partytracker" },
        { text = L["TAB_DURABILITY"],       key = "durability" },
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
            { type = "button", label = L["EDIT_POSITION"] or "위치 편집", onClick = function()
                if ns.QoCMovers then ns.QoCMovers:ToggleConfigMode() end
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
            { type = "button", label = L["EDIT_POSITION"] or "위치 편집", onClick = function()
                if ns.QoCMovers then ns.QoCMovers:ToggleConfigMode() end
            end },

            -- 정보 텍스트
            { type = "header", label = L["PARTYTRACKER_INFO_TITLE"] },
            { type = "text",   label = L["PARTYTRACKER_INFO_TEXT"] },
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
    local function bcRecheck()
        local mod = ns.modules and ns.modules["BuffChecker"]
        if mod and mod.DoCheck then mod:DoCheck() end
    end

    local function bcVisuals()
        local mod = ns.modules and ns.modules["BuffChecker"]
        if mod and mod.UpdateVisuals then mod:UpdateVisuals() end
    end

    tree.panels["buffchecker"] = {
        title = L["BUFFCHECKER_TITLE"] or "버프 체커 (Buff Checker)",
        desc  = L["BUFFCHECKER_DESC"] or "개인, 직업 버프, 소모품 등 버프 누락 시 아이콘으로 알림",
        moduleEnableKey = "profile.modules.BuffChecker",
        settings = {
            -- 기본
            { type = "header", label = L["MODULE_ENABLED"], isFirst = true },
            { type = "toggle", key = "profile.modules.BuffChecker", label = L["MODULE_ENABLED"], reloadRequired = true, isModuleToggle = true },

            -- 표시/일반 설정
            { type = "header", label = L["BUFFCHECKER_DISPLAY_SETTINGS"] or "일반 및 표시 설정" },
            { type = "dropdown", key = "profile.BuffChecker.zoneCheck", label = L["BUFFCHECKER_ZONE_CHECK"] or "활성화 조건", onChange = bcRecheck, options = {
                { text = L["BUFFCHECKER_ZONE_ALWAYS"] or "항상",                      value = "always" },
                { text = L["BUFFCHECKER_ZONE_INSTANCE"] or "던전/레이드만",          value = "instance" },
                { text = L["BUFFCHECKER_ZONE_GROUP"] or "파티/레이드 구성 시",       value = "group" },
                { text = L["BUFFCHECKER_ZONE_BOTH"] or "인스턴스 또는 구성 시", value = "instanceOrGroup" },
            }},
            { type = "toggle", key = "profile.BuffChecker.hideInCombat",       label = L["BUFFCHECKER_HIDE_COMBAT"] or "전투 중 숨김", onChange = bcRecheck },
            { type = "toggle", key = "profile.BuffChecker.ignoreWhileMounted", label = L["BUFFCHECKER_IGNORE_MOUNTED"] or "탈것 탑승 시 숨김", onChange = bcRecheck },
            { type = "toggle", key = "profile.BuffChecker.ignoreWhileResting", label = L["BUFFCHECKER_IGNORE_RESTING"] or "휴식 상태 시 숨김", onChange = bcRecheck },
            { type = "slider", key = "profile.BuffChecker.threshold",          label = L["BUFFCHECKER_THRESHOLD"] or "남은 시간 경고 (분)", min = 1, max = 60, step = 1, onChange = bcRecheck },
            
            -- UI 레이아웃
            { type = "header", label = L["BUFFCHECKER_UI_SETTINGS"] or "프레임 및 레이아웃" },
            { type = "slider",   key = "profile.BuffChecker.iconSize",    label = L["ICON_SIZE"],       min = 20, max = 80, step = 5,      onChange = bcVisuals },
            { type = "slider",   key = "profile.BuffChecker.iconSpacing", label = L["ICON_SPACING"] or "간격", min = 0, max = 20, step = 1, onChange = bcVisuals },
            { type = "slider",   key = "profile.BuffChecker.scale",       label = L["SCALE"],           min = 0.5, max = 2.0, step = 0.1,  onChange = bcVisuals },
            { type = "slider",   key = "profile.BuffChecker.bgAlpha",     label = L["BACKGROUND_ALPHA"], min = 0, max = 1, step = 0.05,    onChange = bcVisuals },            
            { type = "toggle",   key = "profile.BuffChecker.showText",    label = L["SHOW_TEXT"],   onChange = bcVisuals },
            { type = "dropdown", key = "profile.BuffChecker.glowType",    label = L["BUFFCHECKER_GLOW_TYPE"] or "글로우 타입", onChange = bcVisuals, options = {
                { text = "Pixel",    value = "pixel" },
                { text = "Autocast", value = "autocast" },
                { text = "Button",   value = "button" },
                { text = "None",     value = "none" },
            }},
            { type = "color",  key = "profile.BuffChecker.glowColor",     label = L["BUFFCHECKER_GLOW_COLOR"] or "글로우 생상", hasAlpha = false, colorFormat = "rgb_object", onChange = bcVisuals },
            { type = "toggle",   key = "profile.BuffChecker.locked",      label = L["POSITION_LOCKED"] },

            -- 소모품 체크 항목
            { type = "header", label = L["BUFFCHECKER_CHECK_CONSUMABLES"] or "소모품 (음식/영약/오일/룬) 체크" },
            { type = "toggle", key = "profile.BuffChecker.showFood",   label = L["BUFFCHECKER_CHECK_FOOD"] or "음식 부족 시 알림", onChange = bcRecheck },
            { type = "toggle", key = "profile.BuffChecker.showFlask",  label = L["BUFFCHECKER_CHECK_FLASK"] or "영약 부족 시 알림", onChange = bcRecheck },
            { type = "toggle", key = "profile.BuffChecker.showWeapon", label = L["BUFFCHECKER_CHECK_WEAPON"] or "무기 오일/독 부족 시 알림", onChange = bcRecheck },
            { type = "toggle", key = "profile.BuffChecker.showRune",   label = L["BUFFCHECKER_CHECK_RUNE"] or "증강의 룬 부족 시 알림", onChange = bcRecheck },

            -- 직업별 버프 체크 항목
            { type = "header", label = L["BUFFCHECKER_CHECK_CLASS"] or "직업별 버프 및 펫/태세 체크" },
            { type = "toggle", key = "profile.BuffChecker.checkClassBuff", label = L["BUFFCHECKER_CHECK_CLASSBUFF"] or "주 시너지 체크 (사제 인내 등)", onChange = bcRecheck },
            { type = "toggle", key = "profile.BuffChecker.checkPet",       label = L["BUFFCHECKER_CHECK_PET"] or "소환수 부재 시 알림 (냥꾼, 흑마, 법사 등)", onChange = bcRecheck },
            { type = "toggle", key = "profile.BuffChecker.checkStance",    label = L["BUFFCHECKER_CHECK_STANCE"] or "전투 태세/오라 누락 알림", onChange = bcRecheck },
            { type = "toggle", key = "profile.BuffChecker.checkRoguePoisons", label = L["BUFFCHECKER_CHECK_POISONS"] or "로그 독 점검 (전투 단검 등)", onChange = bcRecheck },

            -- 버튼
            { type = "separator" },
            { type = "button", label = L["EDIT_POSITION"] or "위치 편집", onClick = function()
                if ns.QoCMovers then ns.QoCMovers:ToggleConfigMode() end
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
            { type = "button", label = L["EDIT_POSITION"] or "위치 편집", onClick = function()
                if ns.QoCMovers then ns.QoCMovers:ToggleConfigMode() end
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
            { type = "button", label = L["EDIT_POSITION"] or "위치 편집", onClick = function()
                if ns.QoCMovers then ns.QoCMovers:ToggleConfigMode() end
            end },
        },
    }



    self.ConfigTree = tree
    return tree
end
