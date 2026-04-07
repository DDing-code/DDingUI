--[[
    DDingQoC - Database
    통합 SavedVariables 및 기본값 정의
]]

local addonName, ns = ...
local SL = _G.DDingUI_StyleLib -- [12.0.1]

-- 기본값 정의
ns.defaults = {
    profile = {
        -- 모듈 활성화 상태
        modules = {
            TalentBG = true,
            LFGAlert = true,
            MailAlert = true,
            CursorTrail = true,
            ItemLevel = true,
            Notepad = true,
            CombatTimer = true,
            CastingAlert = true,
            FocusInterrupt = true,
            BuffChecker = true,
            PartyTracker = false,
        },

        -- 전역 설정
        minimap = { hide = false, minimapPos = 225 },
        welcomeMessage = false,

        -- CombatTimer 설정
        CombatTimer = {
            showMilliseconds = true,
            showBackground = false,
            colorByTime = false,
            locked = false,
            fontSize = 26,
            scale = 1.0,
            bgAlpha = 0.5,
            font = SL and SL.Font.path or "Fonts\\2002.TTF", -- [12.0.1]
            textColor = { 1, 1, 1, 1 },  -- r, g, b, a
            textAlign = "CENTER",  -- LEFT, CENTER, RIGHT
            soundOnStart = false,
            soundFile = "",  -- [12.0.1] 빈 값 = SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_GO
            soundCustomPath = "",  -- [12.0.1] 커스텀 사운드 경로
            soundChannel = "Master",  -- [12.0.1]
            printToChat = true,
            hideDelay = 3,
            position = {
                point = "TOP",
                relativePoint = "TOP",
                x = 0,
                y = -100,
            },
        },

        -- PartyTracker 설정 (기본값 비활성화 - SavedVariables 없으면 모두 꺼짐)
        PartyTracker = {
            showInParty = false,       -- 파티에서 표시
            showInRaid = false,        -- 레이드에서 표시
            showManaBar = false,       -- 마나바 표시
            showManaText = false,      -- 마나 퍼센트 텍스트 표시
            separateManaFrame = false, -- 힐러 마나 분리 표시
            locked = false,
            manaLocked = false,        -- 힐러 마나 프레임 잠금 (분리 시)
            iconSize = 33,
            scale = 1.0,
            manaScale = 1.0,           -- 힐러 마나 프레임 크기 (분리 시)
            font = SL and SL.Font.path or "Fonts\\2002.TTF", -- [12.0.1]
            fontSize = 14,
            -- 마나바 설정
            manaBarWidth = 60,
            manaBarHeight = 10,
            manaBarOffsetX = 4,
            manaBarOffsetY = 6,
            manaBarTexture = "Interface\\TargetingFrame\\UI-StatusBar",
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = -500,
                y = -110,
            },
            manaPosition = {           -- 힐러 마나 프레임 위치 (분리 시)
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -150,
            },
        },

        -- MythicPlusHelper 설정
        MythicPlusHelper = {
            enabled = true,
            showTeleports = true,
            showScore = true,
            scale = 1.0,
        },

        -- GoldSplit (쌀숭이) 설정
        GoldSplit = {
            chatType = "SAY",
            locked = false,
            position = nil,
        },

        -- DurabilityCheck (내구도 체크) 설정
        DurabilityCheck = {
            threshold = 50,  -- 50% 이하일 때 표시
            soundEnabled = false,
            soundFile = "",
            soundCustomPath = "",  -- [12.0.1] 커스텀 사운드 경로
            soundChannel = "Master",
            locked = false,
            scale = 1.0,
            titleSize = 24,
            percentSize = 36,
            font = SL and SL.Font.path or "Fonts\\2002.TTF", -- [12.0.1]
            position = nil,  -- 저장된 위치
        },

        -- KeystoneTracker (쐐기돌 추적) 설정
        KeystoneTracker = {
            locked = false,
            showInParty = true,
            showInRaid = false,
            scale = 1.0,
            font = SL and SL.Font.path or "Fonts\\2002.TTF", -- [12.0.1]
            fontSize = 12,
            position = {
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                x = 50,
                y = -200,
            },
        },

        -- CastingAlert (타겟 스펠 알림) 설정
        CastingAlert = {
            enabled = false,
            disableForTank = false, -- 탱커 전문화일 때 비활성화
            showTarget = true,
            onlyTargetingMe = true,
            maxShow = 10,
            iconSize = 35,
            fontSize = 18,
            dimAlpha = 0.4,
            scale = 1.0,
            updateRate = 0.2,
            soundEnabled = true,
            soundThreshold = 2,
            soundFile = "",
            soundCustomPath = "",  -- [12.0.1] 커스텀 사운드 경로
            position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -30 },
        },

        -- FocusInterrupt (포커스 차단 시전바) 설정
        FocusInterrupt = {
            enabled = false,
            barWidth = 280,
            barHeight = 30,
            bgAlpha = 0.3,
            fontSize = 12,
            font = SL and SL.Font.path or "Fonts\\2002.TTF", -- [12.0.1]
            texture = "Interface\\TargetingFrame\\UI-StatusBar",
            scale = 1.0,
            showTarget = true,
            showTime = true,
            showInterrupter = true,
            showKickIcon = false,
            kickIconSize = 30,
            cooldownHide = false,
            notInterruptibleHide = true,
            mute = true,
            soundFile = "",
            soundCustomPath = "",  -- [12.0.1] 커스텀 사운드 경로
            interruptedFadeTime = 0.75,
            interruptibleColor = { 0.25, 0.78, 0.92 },      -- 파랑
            notInterruptibleColor = { 1.0, 0.49, 0.04 },    -- 주황
            cooldownColor = { 0.77, 0.12, 0.23 },            -- 빨강
            interruptedColor = { 0.51, 0.51, 0.51 },         -- 회색
            position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 250 },
        },


        -- AutoRepair (자동수리) 설정
        AutoRepair = {
            useGuildBank = true,
            chatOutput = true,
        },

        -- BuffChecker (통합 버프 체커) 설정
        BuffChecker = {
            -- 소모품 토글 (Config 패널 key = showFood/showFlask/showWeapon/showRune)
            showFood = true,
            showFlask = true,
            showWeapon = true,
            showRune = true,
            -- 직업 버프/펫/태세 토글
            checkClassBuff = true,
            checkFlask = true,      -- 코드 내부용 (showFlask 미러)
            checkFood = true,       -- 코드 내부용 (showFood 미러)
            checkWeaponOil = true,  -- 코드 내부용 (showWeapon 미러)
            checkPet = true,
            checkStance = true,
            checkRoguePoisons = true,
            -- 조건
            zoneCheck = "instanceOrGroup",  -- always / instance / group / instanceOrGroup
            ignoreWhileMounted = true,
            ignoreWhileResting = true,
            hideInCombat = false,
            threshold = 5,  -- 분 단위
            -- 표시
            iconSize = 40,
            iconSpacing = 5,
            scale = 1.0,
            bgAlpha = 0.6,
            locked = false,
            showText = true,
            textColor = { r = 1, g = 0.3, b = 0.3 },
            -- 글로우
            glowType = "autocast",  -- pixel / autocast / button / none
            glowColor = { r = 1, g = 1, b = 0 },
            position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 },
        },
    },

    char = {},

    global = {},
}

-- 데이터베이스 초기화
function ns:InitDB()
    if not DDingUIQoCDB then
        DDingUIQoCDB = {}
    end

    -- 프로필 초기화
    if not DDingUIQoCDB.profile then
        DDingUIQoCDB.profile = self:DeepCopy(self.defaults.profile)
    else
        self:MergeDefaults(DDingUIQoCDB.profile, self.defaults.profile)
    end

    -- 캐릭터별 데이터 초기화
    if not DDingUIQoCDB.char then
        DDingUIQoCDB.char = {}
    end

    local charKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
    if not DDingUIQoCDB.char[charKey] then
        DDingUIQoCDB.char[charKey] = self:DeepCopy(self.defaults.char)
    else
        self:MergeDefaults(DDingUIQoCDB.char[charKey], self.defaults.char)
    end

    -- 전역 데이터 초기화
    if not DDingUIQoCDB.global then
        DDingUIQoCDB.global = self:DeepCopy(self.defaults.global)
    else
        self:MergeDefaults(DDingUIQoCDB.global, self.defaults.global)
    end

    -- =========================================
    -- Toolkit → QoC 마이그레이션 (공통 모듈 전체)
    -- DDingUIToolkitDB가 존재하고, 아직 마이그레이션 안 했으면 실행
    -- =========================================
    if not DDingUIQoCDB._migratedToolkit then
        local toolkitDB = _G.DDingUIToolkitDB
        if toolkitDB and toolkitDB.profile then
            local SL = _G.DDingUI_StyleLib
            local prefix = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: "

            -- QoC에 존재하는 모듈 중 Toolkit DB에도 설정이 있는 것들
            local sharedModules = {
                "TalentBG", "LFGAlert", "MailAlert", "CursorTrail",
                "ItemLevel", "Notepad", "CombatTimer", "PartyTracker",
                "CastingAlert", "FocusInterrupt", "BuffChecker",
            }

            local migrated = {}
            for _, modName in ipairs(sharedModules) do
                local src = toolkitDB.profile[modName]
                if src and type(src) == "table" then
                    local dst = DDingUIQoCDB.profile[modName]
                    if dst and type(dst) == "table" then
                        for k, v in pairs(src) do
                            if k ~= "enabled" then  -- enabled는 modules.X가 관리
                                if type(v) == "table" then
                                    dst[k] = self:DeepCopy(v)
                                else
                                    dst[k] = v
                                end
                            end
                        end

                        -- Toolkit에서 enabled=true였으면 QoC modules도 활성화
                        if src.enabled and DDingUIQoCDB.profile.modules[modName] ~= nil then
                            DDingUIQoCDB.profile.modules[modName] = true
                        end

                        migrated[#migrated + 1] = modName
                    end
                end

                -- modules 토글 마이그레이션 (Toolkit에서 꺼둔 것도 반영)
                if toolkitDB.profile.modules and toolkitDB.profile.modules[modName] ~= nil then
                    if DDingUIQoCDB.profile.modules[modName] ~= nil then
                        DDingUIQoCDB.profile.modules[modName] = toolkitDB.profile.modules[modName]
                    end
                end
            end

            -- minimap 설정도 가져오기 (위치 등)
            if toolkitDB.profile.minimap then
                for k, v in pairs(toolkitDB.profile.minimap) do
                    DDingUIQoCDB.profile.minimap[k] = v
                end
            end

            if #migrated > 0 then
                print(prefix .. "|cff00ff00Toolkit에서 " .. #migrated .. "개 모듈 설정 마이그레이션 완료:|r " .. table.concat(migrated, ", "))
            end
        end
        DDingUIQoCDB._migratedToolkit = true
    end

    -- 데이터베이스 참조 설정
    self.db = {
        profile = DDingUIQoCDB.profile,
        char = DDingUIQoCDB.char[charKey],
        global = DDingUIQoCDB.global,
    }

    return self.db
end

-- 딥 카피
function ns:DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for key, value in pairs(orig) do
            copy[self:DeepCopy(key)] = self:DeepCopy(value)
        end
        setmetatable(copy, self:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- 기본값 병합 (없는 키만 추가)
function ns:MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = self:DeepCopy(value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            self:MergeDefaults(target[key], value)
        end
    end
end
