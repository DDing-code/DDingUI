--[[
    DDingToolKit - Database
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
            PartyTracker = true,
            MythicPlusHelper = true,
            GoldSplit = true,
            DurabilityCheck = true,

            KeystoneTracker = true,
            CastingAlert = true,
            FocusInterrupt = true,
            BuffChecker = true,
            AutoRepair = true,
            SkyridingTracker = true,
        },

        -- 전역 설정
        minimap = { hide = false, minimapPos = 225 },
        welcomeMessage = false,

        -- TalentBG 설정
        TalentBG = {
            mode = "spec",  -- "spec" | "class" | "global"
            globalBackground = "",
        },

        -- LFGAlert 설정
        LFGAlert = {
            soundEnabled = true,
            flashEnabled = true,
            screenAlertEnabled = true,
            autoOpenLFG = false,
            chatAlert = true,
            soundFile = "",  -- 빈 값 = SOUNDKIT.READY_CHECK 사용
            soundCustomPath = "",  -- [12.0.1] 커스텀 사운드 경로
            soundChannel = "Master",
            alertPosition = "TOP",
            alertScale = 1.0,
            alertDuration = 5,
            alertAnimation = "bounce",
            leaderOnly = false,
            cooldown = 2,
        },

        -- MailAlert 설정
        MailAlert = {
            soundEnabled = true,
            flashEnabled = true,
            screenAlertEnabled = true,
            chatAlert = true,
            soundFile = "",  -- 빈 값 = SOUNDKIT.TELL_MESSAGE 사용
            soundCustomPath = "",  -- [12.0.1] 커스텀 사운드 경로
            soundChannel = "Master",
            alertPosition = "CENTER",
            alertScale = 1.0,
            alertDuration = 5,
            alertAnimation = "pulse",
            hideInCombat = true,
            hideInInstance = false,
            cooldown = 60,
        },

        -- CursorTrail 설정
        CursorTrail = {
            enabled = true,

            -- 색상 설정
            colorCount = 8,
            colors = {
                [1] = { 0.00, 0.11, 1.00, 1 },   -- 파랑
                [2] = { 0.00, 0.33, 0.34, 1 },   -- 청록
                [3] = { 0.10, 0.00, 1.00, 1 },   -- 보라
                [4] = { 0.31, 0.20, 0.29, 1 },   -- 자주
                [5] = { 1.00, 0.61, 0.00, 1 },   -- 주황
                [6] = { 1.00, 0.16, 0.00, 1 },   -- 빨강
                [7] = { 1.00, 0.10, 0.00, 1 },   -- 진빨강
                [8] = { 1.00, 0.04, 0.00, 1 },   -- 불꽃
                [9] = { 0.00, 0.00, 0.00, 1 },   -- 검정
                [10] = { 0.00, 0.00, 0.00, 1 }, -- 검정
            },

            -- 색상 플로우 (무지개 효과)
            colorFlow = false,
            colorFlowSpeed = 0.6,

            -- 트레일 외형
            width = 60,
            height = 60,
            alpha = 1.0,
            texture = "Interface\\COMMON\\Indicator-Gray",
            blendMode = "ADD",

            -- 트레일 동작
            lifetime = 0.25,
            maxDots = 800,
            dotDistance = 2,

            -- 표시 조건
            onlyInCombat = false,
            hideInInstance = false,
            layer = "TOOLTIP",

            -- 프리셋
            preset = "custom",
        },

        -- ItemLevel 설정
        ItemLevel = {
            -- 표시 옵션
            showItemLevel = true,
            showEnchant = true,
            showGems = true,
            showAverageIlvl = true,
            showEnhancedStats = true,

            -- 본인 캐릭터 설정
            selfIlvlSize = 13,
            selfIlvlFlags = "OUTLINE",
            selfEnchantSize = 10,
            selfEnchantFlags = "OUTLINE",
            selfGemSize = 14,
            selfGemSpacing = 0,
            selfAvgSize = 18,

            -- 살펴보기 설정
            inspIlvlSize = 13,
            inspIlvlFlags = "OUTLINE",
            inspEnchantSize = 10,
            inspEnchantFlags = "OUTLINE",
            inspGemSize = 14,
            inspGemSpacing = 0,
            inspAvgSize = 17,
        },

        -- Notepad 설정
        Notepad = {
            showPVEButton = true,
            savedNotes = {},  -- { name, title, content }
        },

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
            enabled = false,           -- 모듈 활성화
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

        -- BuffChecker (버프 체크) 설정
        BuffChecker = {
            enabled = false,
            showFood = false,
            showFlask = false,
            showWeapon = false,
            showRune = false,
            instanceOnly = true,
            iconSize = 40,
            scale = 1.0,
            locked = false,
            showText = true,
            textSize = 10,
            textFont = SL and SL.Font.path or "Fonts\\2002.TTF", -- [12.0.1]
            textColor = { r = 1, g = 0.3, b = 0.3 },
            alignment = "CENTER",
            position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 },
        },
        
        -- SkyridingTracker (활공 트래커) 설정
        SkyridingTracker = {
            enabled = true,
            scale = 1.0,
            locked = false,
            posX = 0,
            posY = 0,
            fadeOutDuration = 0.7,
            -- 서지 위치 ("bottom" / "top")
            surgePosition = "bottom",
            -- 테두리
            borderSize = 2,
            -- 색상 (r, g, b)
            vigorColor     = { 0.20, 0.80, 1.00 },
            vigorDimColor  = { 0.06, 0.15, 0.22 },
            windColor      = { 0.40, 1.00, 0.55 },
            windDimColor   = { 0.08, 0.20, 0.12 },
            surgeColor     = { 1.00, 0.55, 0.10 },
            surgeDimColor  = { 0.20, 0.12, 0.03 },
            -- 텍스처
            barTexture     = "Interface\\TargetingFrame\\UI-StatusBar",
        },
    },

    char = {
        -- TalentBG 전문화별 설정
        TalentBG = {
            specSettings = {
                [1] = { background = "" },
                [2] = { background = "" },
                [3] = { background = "" },
                [4] = { background = "" },
            },
        },
    },

    global = {
        -- TalentBG 직업별 설정
        TalentBG = {
            classSettings = {},  -- [classID] = { background = "" }
            customPaths = {},    -- 사용자 추가 배경 파일명 목록
        },
    },
}

-- 데이터베이스 초기화
function ns:InitDB()
    if not DDingUIToolkitDB then
        DDingUIToolkitDB = {}
    end

    -- 프로필 초기화
    if not DDingUIToolkitDB.profile then
        DDingUIToolkitDB.profile = self:DeepCopy(self.defaults.profile)
    else
        self:MergeDefaults(DDingUIToolkitDB.profile, self.defaults.profile)
    end

    -- 캐릭터별 데이터 초기화
    if not DDingUIToolkitDB.char then
        DDingUIToolkitDB.char = {}
    end

    local charKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
    if not DDingUIToolkitDB.char[charKey] then
        DDingUIToolkitDB.char[charKey] = self:DeepCopy(self.defaults.char)
    else
        self:MergeDefaults(DDingUIToolkitDB.char[charKey], self.defaults.char)
    end

    -- 전역 데이터 초기화
    if not DDingUIToolkitDB.global then
        DDingUIToolkitDB.global = self:DeepCopy(self.defaults.global)
    else
        self:MergeDefaults(DDingUIToolkitDB.global, self.defaults.global)
    end

    -- 데이터베이스 참조 설정
    self.db = {
        profile = DDingUIToolkitDB.profile,
        char = DDingUIToolkitDB.char[charKey],
        global = DDingUIToolkitDB.global,
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
