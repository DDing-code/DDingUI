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
        -- 기존 프로필에 없는 모듈은 InitDB에서 비활성화한 뒤 기본값을 병합한다.
        modules = {
            TalentBG = true,
            LFGAlert = true,
            PremadeGroupFilter = false,
            PartyFullAlert = true,
            MailAlert = true,
            CalendarInviteAlert = false,
            CursorTrail = true,
            ItemLevel = true,
            Notepad = true,
            CombatTimer = true,
            CombatStateAlert = false,
            RaidBreakTimer = false,
            CharacterPositionMarker = true,
            RangeDisplay = true,
            PartyTracker = true,
            DeathAlert = true,
            DeathReleaseGuard = true,
            MythicPlusHelper = true,
            GoldSplit = true,
            DurabilityCheck = true,

            CastingAlert = true,
            FocusInterrupt = true,
            StasisTracker = false,
            BloodlustTimer = false,
            RaidDefensiveTracker = false,
            ReadyCheckAssistant = false,
            RaidGroups = false,
            RaidPreparation = false,
            RaidPartyTooltip = false,
            AutoRepair = true,
            RaidLootPass = true,
            VoidcoreHelper = false,
            SkyridingTracker = true,
        },

        -- 전역 설정
        minimap = { hide = false, minimapPos = 225 },
        welcomeMessage = false,
        SoundManager = {
            enabled = true,
            mode = "PRIORITY",
            decisionWindow = 0.12,
            defaultDuration = 1.2,
            queueExpiry = 1.5,
            fadeOut = 0.08,
            pauseBackground = true,
            priorityOffsets = {
                FocusInterrupt = 0,
                CastingAlert = 0,
                DeathAlert = 0,
                BloodlustTimer = 0,
                CombatTimer = 0,
                CombatStateAlert = 0,
                PartyFullAlert = 0,
                LFGAlert = 0,
                DurabilityCheck = 0,
                MailAlert = 0,
                CalendarInviteAlert = 0,
            },
        },

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
            animationEnabled = true,
            designVersion = 2,
            width = 500,
            height = 112,
            frameStrata = "FULLSCREEN_DIALOG",
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontSize = 24,
            fontOutline = "OUTLINE",
            titleColor = { 0.78, 0.94, 1.00, 1.00 },
            subtitleColor = { 0.68, 0.80, 0.86, 1.00 },
            lineColor = { 0.26, 0.76, 0.90, 0.82 },
            accentColor = { 0.50, 0.68, 1.00, 0.82 },
            panelColor = { 0.025, 0.075, 0.10, 0.78 },
            glowColor = { 0.38, 0.82, 1.00, 0.20 },
            leaderOnly = false,
            cooldown = 2,
        },

        -- PremadeGroupFilter settings
        PremadeGroupFilter = {
            uiRevision = 5,
            showPanel = true,
            showSpecIcons = true,
            showLeaderScore = true,
            specIconClassBorder = true,
            specIconLeaderMarker = true,
            selectedDungeons = {},
            needMyRole = false,
            bloodlustFit = false,
            requireTank = false,
            requireHealer = false,
            minLeaderRating = 0,
            minMapBest = 0,
            sortMode = "DEFAULT",
        },

        -- PartyFullAlert 설정
        PartyFullAlert = {
            targetSize = 5,
            soundEnabled = true,
            flashEnabled = true,
            screenAlertEnabled = true,
            chatAlert = true,
            soundFile = "",
            soundCustomPath = "",
            soundChannel = "Master",
            alertScale = 1.0,
            alertDuration = 5,
            animationEnabled = true,
            designVersion = 2,
            width = 500,
            height = 112,
            frameStrata = "FULLSCREEN_DIALOG",
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontSize = 24,
            fontOutline = "OUTLINE",
            titleColor = { 0.80, 1.00, 0.88, 1.00 },
            subtitleColor = { 0.72, 0.86, 0.79, 1.00 },
            lineColor = { 0.25, 0.88, 0.68, 0.84 },
            accentColor = { 0.90, 0.72, 0.38, 0.88 },
            panelColor = { 0.025, 0.09, 0.07, 0.80 },
            glowColor = { 0.35, 0.95, 0.72, 0.20 },
            cooldown = 5,
            pollInterval = 0.4,
            position = {
                point = "TOP",
                relativePoint = "TOP",
                x = 0,
                y = -180,
            },
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

        -- CalendarInviteAlert
        CalendarInviteAlert = {
            notifyOnLogin = true,
            notifyToday = true,
            hideInCombat = true,
            soundEnabled = true,
            flashEnabled = false,
            screenAlertEnabled = true,
            chatAlert = true,
            soundFile = "",
            soundCustomPath = "",
            soundChannel = "Master",
            animationEnabled = true,
            alertDuration = 6,
            alertScale = 1,
            width = 500,
            height = 112,
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontSize = 24,
            fontOutline = "OUTLINE",
            frameStrata = "HIGH",
            titleColor = { 0.91, 0.96, 0.92, 1.00 },
            subtitleColor = { 0.70, 0.83, 0.79, 1.00 },
            lineColor = { 0.38, 0.72, 0.64, 0.82 },
            accentColor = { 0.83, 0.76, 0.54, 0.90 },
            panelColor = { 0.03, 0.065, 0.055, 0.78 },
            glowColor = { 0.42, 0.74, 0.65, 0.20 },
            position = { point = "TOP", relativePoint = "TOP", x = 0, y = -260 },
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
            selfEnabled = true,
            inspectEnabled = true,
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

        -- CombatStateAlert settings
        CombatStateAlert = {
            showStart = true,
            showEnd = true,
            instanceOnly = false,
            excludeDelves = false,
            visualMode = "SIMPLE",
            animationEnabled = true,
            duration = 1.8,
            designVersion = 3,
            width = 480,
            height = 96,
            scale = 1.0,
            frameStrata = "HIGH",
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontSize = 28,
            fontOutline = "OUTLINE",
            startText = "",
            endText = "",
            startColor = { 0.18, 0.82, 1.00, 1 },
            endColor = { 1.00, 0.72, 0.24, 1 },
            colorVersion = 2,
            startTextColor = { 0.70, 0.94, 1.00, 1.00 },
            startLineColor = { 0.12, 0.78, 0.92, 0.88 },
            startAccentColor = { 0.38, 0.55, 1.00, 0.72 },
            startDiamondColor = { 0.54, 0.36, 1.00, 0.90 },
            startWingColor = { 0.23, 0.72, 0.88, 0.70 },
            startPanelColor = { 0.03, 0.08, 0.12, 0.82 },
            startFlashColor = { 0.18, 0.82, 1.00, 0.14 },
            endTextColor = { 1.00, 0.85, 0.55, 1.00 },
            endLineColor = { 1.00, 0.63, 0.18, 0.88 },
            endAccentColor = { 1.00, 0.38, 0.18, 0.72 },
            endDiamondColor = { 1.00, 0.70, 0.28, 0.90 },
            endWingColor = { 1.00, 0.54, 0.18, 0.70 },
            endPanelColor = { 0.12, 0.055, 0.02, 0.82 },
            endFlashColor = { 1.00, 0.55, 0.16, 0.14 },
            startSoundEnabled = false,
            startSoundFile = "Sound\\Interface\\RaidWarning.ogg",
            startSoundCustomPath = "",
            startSoundChannel = "Master",
            endSoundEnabled = false,
            endSoundFile = "Sound\\Interface\\LevelUp2.ogg",
            endSoundCustomPath = "",
            endSoundChannel = "Master",
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 140,
            },
        },

        -- RaidBreakTimer settings
        RaidBreakTimer = {
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontSize = 72,
            fontOutline = "THICKOUTLINE",
            textColor = { 1, 1, 1, 1 },
            customText = "",
            textOrder = "TIME_ONLY",
            textLayer = "FRONT",
            textOffsetX = 0,
            textOffsetY = 0,
            scale = 1.0,
            showImage = false,
            imageFolder = "DDingUI_Backgrounds",
            imageFile = "",
            imageAnchor = "CENTER",
            imageWidth = 360,
            imageHeight = 180,
            imageAlpha = 0.85,
            imageOffsetX = 0,
            imageOffsetY = 0,
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 100,
            },
        },

        -- CharacterPositionMarker (캐릭터 위치 마커) 설정
        CharacterPositionMarker = {
            enabled = true,
            showMelee = true,
            showRanged = true,
            showTank = true,
            showHealer = true,
            combatOnly = true,
            instanceOnly = false,
            rangeCheck = true,
            meleeDpsOnly = false,
            rangeSpell = "",
            rangeModeVersion = 2,
            shape = "CROSS",
            size = 64,
            thickness = 5,
            centerGap = 18,
            scale = 0.8,
            frameStrata = "MEDIUM",
            visualMode = "SYSTEM",
            animationEnabled = true,
            enterAnimationDuration = 0.58,
            exitAnimationDuration = 0.42,
            animationStyleVersion = 2,
            color = { 0.15, 1.00, 0.25, 0.9 },
            outOfRangeColor = { 1.00, 0.05, 0.05, 0.95 },
            effectColor = { 0.18, 0.78, 1.00, 0.85 },
            effectSecondaryColor = { 0.62, 0.24, 1.00, 0.70 },
            rangeUpdateRate = 0.1,
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            },
        },

        -- RangeDisplay (대상/주시 사거리 표시) 설정
        RangeDisplay = {
            showTarget = true,
            showFocus = false,
            combatOnly = false,
            showUnitLabel = false,
            showUnknown = false,
            showAccentLine = true,
            locked = true,
            width = 140,
            height = 32,
            scale = 1.0,
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontSize = 20,
            fontOutline = "OUTLINE",
            frameStrata = "MEDIUM",
            bgAlpha = 0.25,
            updateRate = 0.2,
            nearThreshold = 8,
            farThreshold = 40,
            nearColor = { 0.25, 1.00, 0.45, 1 },
            mediumColor = { 1.00, 0.82, 0.20, 1 },
            farColor = { 1.00, 0.25, 0.20, 1 },
            unknownColor = { 0.70, 0.75, 0.82, 1 },
            targetPosition = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -180,
            },
            focusPosition = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -140,
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
            designVersion = 2,
            blinkEnabled = true,
            blinkPeriod = 1.4,
            width = 460,
            height = 120,
            frameStrata = "HIGH",
            titleSize = 24,
            percentSize = 36,
            font = SL and SL.Font.path or "Fonts\\2002.TTF", -- [12.0.1]
            fontOutline = "OUTLINE",
            titleColor = { 1.00, 0.82, 0.58, 1.00 },
            lineColor = { 1.00, 0.54, 0.22, 0.88 },
            panelColor = { 0.12, 0.045, 0.015, 0.82 },
            glowColor = { 1.00, 0.30, 0.12, 0.20 },
            position = nil,  -- 저장된 위치
        },

        -- CastingAlert (타겟 스펠 알림) 설정
        CastingAlert = {
            enabled = false,
            disableForTank = false, -- 탱커 전문화일 때 비활성화
            showTarget = true,
            onlyTargetingMe = true,
            hideUntargeted = false,
            onlyImportant = false,
            combatOnly = true,
            ignoreMinor = true,
            showDuration = true,
            showSwipe = true,
            showImportantGlow = true,
            indicateInterrupts = true,
            displayMode = "ICON",
            maxShow = 10,
            iconSize = 35,
            fontSize = 18,
            font = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF",
            iconFontSize = 18,
            durationTextColor = { 0.35, 1.00, 0.35, 1 },
            dimAlpha = 0.4,
            spacing = 4,
            stackDirection = "UP",
            scale = 1.0,
            updateRate = 0.05,
            scanDelay = 0.2,
            barWidth = 300,
            barHeight = 30,
            barTexture = "Interface\\Buttons\\WHITE8x8",
            barFontSize = 14,
            barColor = { 0.16, 0.58, 0.42, 1 },
            barBackgroundColor = { 0.04, 0.05, 0.06, 0.92 },
            barBorderColor = { 0.24, 0.29, 0.33, 1 },
            barTextColor = { 1, 1, 1, 1 },
            barTargetTextColor = { 0.25, 0.82, 1, 1 },
            dualIconSize = 32,
            dualFontSize = 20,
            dualGap = 4,
            soundEnabled = true,
            soundThreshold = 2,
            soundCooldown = 2,
            soundFile = "",
            soundCustomPath = "",  -- [12.0.1] 커스텀 사운드 경로
            soundChannel = "Master",
            iconPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -30 },
        },

        -- FocusInterrupt (타겟/포커스 시전바) 설정
        FocusInterrupt = {
            enabled = false,
            showTarget = true,
            showFocus  = true,
            barWidth  = 180,
            barHeight = 17,
            bgAlpha   = 0.8,
            barAlpha = 1,
            frameStrata = "LOW",
            backgroundColor = { 0, 0, 0, 1 },
            barBorderSize = 1,
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            texture = "RaidFrame-Hp-Fill",
            targetScale = 1.0,
            focusScale  = 1.2,
            updateRate  = 0.1,
            interruptedHoldTime = 1,

            showSpellName = true,
            spellNameFont = SL and SL.Font.path or "Fonts\\2002.TTF",
            spellNameFontSize = 12,
            spellNameOutline = "",
            spellNameColor = { 1, 1, 1, 1 },
            spellNamePosition = "LEFT",
            spellNameOffsetX = 3,
            spellNameOffsetY = 0,

            showTimeText = true,
            timeTextFont = SL and SL.Font.path or "Fonts\\2002.TTF",
            timeTextFontSize = 9,
            timeTextOutline = "",
            timeTextColor = { 1, 1, 1, 1 },
            timeTextPosition = "RIGHT",
            timeTextOffsetX = -3,
            timeTextOffsetY = 0,
            timeTextFormat = "REMAINING_TOTAL",
            timeTextDecimals = 1,

            showTargetText = true,
            targetTextFont = SL and SL.Font.path or "Fonts\\2002.TTF",
            targetTextFontSize = 12,
            targetTextOutline = "",
            targetTextColor = { 1, 1, 1, 1 },
            targetTextUseClassColor = true,
            targetTextPosition = "BELOW_RIGHT",
            targetTextOffsetX = 0,
            targetTextOffsetY = -2,

            showIcon = true,
            iconWidth = 23,
            iconHeight = 19,
            iconPosition = "LEFT",
            iconOffsetX = -1,
            iconOffsetY = 0,
            iconZoom = 0.08,
            iconBorderSize = 1,
            iconBorderColor = { 0, 0, 0, 1 },

            showRaidMarker = true,
            raidMarkerSize = 15,
            raidMarkerPosition = "LEFT",
            raidMarkerOffsetX = -1,
            raidMarkerOffsetY = 0,

            showTargetIndicator = true,
            targetIndicatorSize = 16,
            targetIndicatorColor = { 1, 1, 1, 1 },
            targetIndicatorPosition = "RIGHT",
            targetIndicatorOffsetX = 0,
            targetIndicatorOffsetY = 1,

            showImportantAlert = true,
            importantAlertColor = { 1, 0, 0, 1 },
            importantAlertAlpha = 1,
            notInterruptibleAlpha = 1,
            focusSoundEnabled = false,
            focusSoundCooldown = 1,
            focusSoundFile = "",
            focusSoundCustomPath = "",
            focusSoundChannel = "Master",
            interruptibleColor    = { 204/255, 1, 153/255 },
            notInterruptibleColor = { 0.9, 0.9, 0.9 },
            interruptedColor      = { 1, 0, 0 },
            targetPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -100 },
            focusPosition  = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 50 },
        },

        -- StasisTracker (Preservation Evoker Stasis) settings
        StasisTracker = {
            iconSize = 44,
            spacing = 4,
            scale = 1.0,
            showTimer = true,
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontSize = 15,
            orderFontSize = 10,
            timerFontSize = 12,
            warningThreshold = 5,
            storedBorderColor = { 0.20, 0.78, 1.00, 0.95 },
            emptyBorderColor = { 0.22, 0.28, 0.36, 0.90 },
            slotBackgroundColor = { 0.025, 0.035, 0.05, 0.90 },
            emptyIconColor = { 1.00, 1.00, 1.00, 1.00 },
            emptyShadeColor = { 0.00, 0.00, 0.00, 0.35 },
            orderTextColor = { 1.00, 1.00, 1.00, 0.95 },
            timerBarColor = { 0.20, 0.78, 1.00, 0.95 },
            timerBackgroundColor = { 0.025, 0.035, 0.05, 0.90 },
            timerTextColor = { 1.00, 1.00, 1.00, 1.00 },
            warningColor = { 1.00, 0.22, 0.18, 0.95 },
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -220,
            },
        },

        -- BloodlustTimer (Bloodlust and exhaustion timeline) settings
        BloodlustTimer = {
            showActive = true,
            showExhaustion = true,
            groupOnly = false,
            instanceOnly = false,
            showIcon = true,
            iconSize = 40,
            iconSpacing = 4,
            showCooldownSwipe = true,
            showCooldownNumbers = true,
            iconGlowEnabled = false,
            barGlowEnabled = false,
            iconGlowColor = { 1.00, 0.28, 0.10, 1.00 },
            barGlowColor = { 1.00, 0.28, 0.10, 0.95 },
            glowLines = 8,
            glowFrequency = 0.25,
            glowLength = 10,
            glowThickness = 2,
            scale = 1.0,
            frameStrata = "HIGH",

            showBar = true,
            barWidth = 220,
            barHeight = 20,
            barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
            barDirection = "LEFT",
            smoothBar = true,
            activeBarColor = { 1.00, 0.24, 0.12, 1 },
            exhaustionBarColor = { 0.38, 0.44, 0.54, 1 },
            barBackgroundColor = { 0.02, 0.025, 0.035, 0.90 },
            barBorderColor = { 0, 0, 0, 1 },
            barBorderSize = 1,

            showText = true,
            textFormat = "REMAINING",
            textDecimals = 1,
            decimalsThreshold = 3,
            activeText = "BL",
            exhaustionText = "",
            textOrder = "LABEL_TIME",
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontSize = 14,
            fontOutline = "OUTLINE",
            activeTextColor = { 1, 1, 1, 1 },
            exhaustionTextColor = { 0.85, 0.88, 0.92, 1 },
            textPosition = "INSIDE",
            textOffsetX = 0,
            textOffsetY = 0,

            startMotionEnabled = true,
            startMotionStyle = "SYSTEM",
            startMotionText = "BLOODLUST",
            startMotionDuration = 1.2,
            startMotionWidth = 620,
            startMotionHeight = 130,
            startMotionScale = 1.0,
            startMotionFrameStrata = "DIALOG",
            startMotionStyleVersion = 4,
            startMotionFont = SL and SL.Font.path or "Fonts\\2002.TTF",
            startMotionFontSize = 38,
            startMotionFontOutline = "OUTLINE",
            startMotionTitleColor = { 1.00, 0.76, 0.30, 1.00 },
            startMotionLineColor = { 0.70, 0.40, 0.10, 0.96 },
            startMotionAccentColor = { 0.72, 0.015, 0.025, 0.98 },
            startMotionPulseColor = { 1.00, 0.07, 0.025, 0.90 },
            startMotionPanelColor = { 0.018, 0.002, 0.006, 0.90 },
            startMotionGlowColor = { 0.88, 0.010, 0.015, 0.34 },
            startMotionSystemTitleColor = { 1.00, 0.91, 0.82, 1.00 },
            startMotionSystemRingColor = { 0.90, 0.92, 0.90, 0.94 },
            startMotionSystemAccentColor = { 0.98, 0.025, 0.56, 0.94 },
            startMotionSystemPulseColor = { 0.90, 0.025, 0.075, 0.94 },
            startMotionSystemPanelColor = { 0.115, 0.002, 0.052, 0.82 },
            startMotionSystemGlowColor = { 0.98, 0.025, 0.56, 0.34 },
            startMotionSystemCrestColor = { 1.00, 0.82, 0.62, 1.00 },
            startMotionSystemCrestCoreColor = { 0.90, 0.025, 0.075, 1.00 },
            startMotionPosition = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 40,
            },

            animationEnabled = false,
            animationFolder = "DDingUI_Media\\Bloodlust",
            animationFile = "",
            animationColumns = 4,
            animationRows = 4,
            animationFrameCount = 16,
            animationFPS = 20,
            animationPlayback = "LOOP",
            animationWidth = 220,
            animationHeight = 220,
            animationAlpha = 1,
            animationBlendMode = "ADD",
            animationLayer = "BACKGROUND",
            animationOffsetX = 0,
            animationOffsetY = 0,

            startSoundEnabled = false,
            startSoundFile = "",
            startSoundCustomPath = "",
            startSoundChannel = "Master",
            musicSoundEnabled = false,
            musicSoundFile = "",
            musicSoundCustomPath = "",
            musicSoundChannel = "Music",
            musicLoop = false,
            musicRepeatInterval = 10,
            endSoundEnabled = false,
            endSoundFile = "",
            endSoundCustomPath = "",
            endSoundChannel = "Master",
            readySoundEnabled = false,
            readySoundFile = "",
            readySoundCustomPath = "",
            readySoundChannel = "Master",

            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -170,
            },
        },

        -- RaidDefensiveTracker (received group defensive auras)
        RaidDefensiveTracker = {
            iconSize = 44,
            iconZoom = 0,
            iconCropX = 7,
            iconCropY = 7,
            spacing = 4,
            scale = 1.0,
            growDirection = "RIGHT",
            frameStrata = "HIGH",
            locked = true,
            showSwipe = true,
            showDuration = true,
            font = SL and SL.Font.path or "Fonts\\2002.TTF",
            fontOutline = "OUTLINE",
            durationFontSize = 16,
            durationTextColor = { 1.00, 1.00, 1.00, 1.00 },
            borderSize = 1,
            borderColor = { 0.18, 0.76, 0.92, 0.95 },
            soundFile = "",
            soundCustomPath = "",
            soundChannel = "Master",
            spells = {
                innervate = true,
                timeSpiral = true,
                spatialParadox = true,
                powerInfusion = true,
                stampedingRoar = true,
                windRush = true,
                piercingHowl = true,
                antiMagicZone = true,
                darkness = true,
                zephyr = true,
                auraMastery = true,
                massBarrier = true,
                powerWordBarrier = true,
                spiritLink = true,
                rallyingCry = true,
            },
            sounds = {
                innervate = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                timeSpiral = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                spatialParadox = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                powerInfusion = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                stampedingRoar = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                windRush = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                piercingHowl = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                antiMagicZone = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                darkness = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                zephyr = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                auraMastery = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                massBarrier = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                powerWordBarrier = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                spiritLink = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
                rallyingCry = { soundFile = "", soundCustomPath = "", soundChannel = "Master" },
            },
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -250,
            },
        },

        -- ReadyCheckAssistant (spec, loadout, and durability check)
        ReadyCheckAssistant = {
            minDurabilityPercent = 25,
            showLowSlots = true,
            mplusLoadouts = "",
            raidLoadouts = "",
            autoReport = false,
            reportOnlyProblems = true,
            showOpenTalentsButton = true,
            showReportButton = true,
            hideInCombat = true,
            width = 440,
            scale = 1.0,
            anchorSide = "BELOW",
            offsetX = 0,
            offsetY = -8,
        },

        -- RaidGroups (editable 8 x 5 raid group layouts)
        RaidGroups = {
            showRoleIcons = true,
            colorNames = true,
            balancePattern = "ODD_EVEN",
            autoCloseAfterApply = false,
            showLauncher = true,
            launcherRaidOnly = true,
            scale = 1.0,
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 20,
            },
            launcherPosition = {
                point = "LEFT",
                relativePoint = "LEFT",
                x = 12,
                y = 80,
            },
            currentLayout = {},
            savedLayouts = {},
            selectedLayoutName = "",
        },

        -- RaidPreparation (raid-wide ready and consumable overview)
        RaidPreparation = {
            autoOpen = true,
            raidOnly = true,
            leaderOnly = true,
            hideComplete = false,
            autoReport = false,
            reportUnknown = false,
            checkFood = true,
            checkFlask = true,
            checkRune = true,
            checkRaidBuffs = true,
            raidBuffAttackPower = true,
            raidBuffStamina = true,
            raidBuffIntellect = true,
            raidBuffVersatility = true,
            raidBuffMastery = true,
            raidBuffMovement = true,
            checkWeaponEnchant = false,
            checkDurability = true,
            durabilityThreshold = 30,
            minimumBuffMinutes = 10,
            closeAfterReadyCheck = false,
            closeDelay = 5,
            customFoodSpellIDs = "",
            customFlaskSpellIDs = "",
            customRuneSpellIDs = "",
            scale = 1.0,
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 10,
            },
        },

        -- RaidPartyTooltip (subgroup class and armor counts)
        RaidPartyTooltip = {
            showOnPremadeRaid = true,
            showOnMembers = true,
            showOnEmptySlots = true,
            showClassCounts = true,
            showClassIcons = true,
            showArmorCounts = true,
            showZeroArmor = true,
        },

        -- DeathAlert (party/raid death alert)
        DeathAlert = {
            onlyInstance = false,
            enableRoleIcon = true,
            enableWipeDetection = true,
            enableChatAlert = false,
            enableSound = true,
            soundFile = "",
            tankSound = "",
            healerSound = "",
            playerSound = "",
            enablePlayerSound = false,
            soundChannel = "Master",
            messageDuration = 4,
            fontSize = 24,
            font = "2002",
            locked = true,
            position = nil,
        },

        -- Raid release protection
        DeathReleaseGuard = {
            enabled = true,
            holdDuration = 1.5,
        },

        -- AutoRepair (자동수리) 설정
        AutoRepair = {
            useGuildBank = true,
            chatOutput = true,
        },

        -- RaidLootPass (레이드 루팅 자동 포기) 설정
        RaidLootPass = {
            enabled = true,
            chatOutput = true,
            excludeSelectedItems = false,
            protectRecipes = true,
            protectToys = true,
            protectMounts = true,
            protectPets = true,
            protectAppearanceUnlocks = true,
            protectHousingDecor = true,
            protectQuestItems = true,
        },

        -- Nebulous Voidcore bonus-roll advisor
        VoidcoreHelper = {
            entryPrompt = true,
            guardNonTargets = true,
            showAdvisor = true,
            showLootTable = true,
            bisBySpec = {},
            bisSourcesBySpec = {},
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
            customFolder = "DDingUI_Backgrounds",
        },
        newModuleNotices = {
            seen = {},
        },
    },
}

local function DisableNewModulesForExistingProfile(profile, defaultModules)
    if type(profile) ~= "table" or type(profile.modules) ~= "table" then return end

    for moduleName in pairs(defaultModules) do
        if profile.modules[moduleName] == nil then
            profile.modules[moduleName] = false
        end
    end
end

local function RemoveRetiredModuleData(profile)
    if type(profile) ~= "table" then return end

    local retiredModules = {
        "BuffChecker",
        "BuffReminder",
        "KeystoneTracker",
    }

    for _, moduleName in ipairs(retiredModules) do
        if type(profile.modules) == "table" then
            profile.modules[moduleName] = nil
        end
        profile[moduleName] = nil
    end
end

local function CopyAlertColor(color, fallback, alphaMultiplier)
    color = type(color) == "table" and color or fallback
    fallback = fallback or { 1, 1, 1, 1 }
    local alpha = tonumber(color and color[4]) or tonumber(fallback[4]) or 1
    return {
        tonumber(color and color[1]) or fallback[1] or 1,
        tonumber(color and color[2]) or fallback[2] or 1,
        tonumber(color and color[3]) or fallback[3] or 1,
        alpha * (alphaMultiplier or 1),
    }
end

local function MigrateCombatStateAlertColors(profile)
    local db = type(profile) == "table" and profile.CombatStateAlert
    if type(db) ~= "table" or (tonumber(db.colorVersion) or 0) >= 2 then return end

    local startColor = CopyAlertColor(db.startColor, { 0.18, 0.82, 1.00, 1.00 })
    local endColor = CopyAlertColor(db.endColor, { 1.00, 0.72, 0.24, 1.00 })

    db.startTextColor = db.startTextColor or CopyAlertColor(startColor)
    db.startLineColor = db.startLineColor or CopyAlertColor(startColor, nil, 0.95)
    db.startAccentColor = db.startAccentColor or { 0.62, 0.34, 1.00, 0.65 }
    db.startDiamondColor = db.startDiamondColor or { 0.62, 0.34, 1.00, 0.95 }
    db.startWingColor = db.startWingColor or CopyAlertColor(startColor, nil, 0.82)
    db.startPanelColor = db.startPanelColor or { 0.62, 0.34, 1.00, 0.24 }
    db.startFlashColor = db.startFlashColor or CopyAlertColor(startColor, nil, 0.24)

    db.endTextColor = db.endTextColor or CopyAlertColor(endColor)
    db.endLineColor = db.endLineColor or CopyAlertColor(endColor, nil, 0.95)
    db.endAccentColor = db.endAccentColor or { 1.00, 0.40, 0.22, 0.65 }
    db.endDiamondColor = db.endDiamondColor or { 1.00, 0.40, 0.22, 0.95 }
    db.endWingColor = db.endWingColor or CopyAlertColor(endColor, nil, 0.82)
    db.endPanelColor = db.endPanelColor or { 1.00, 0.40, 0.22, 0.24 }
    db.endFlashColor = db.endFlashColor or CopyAlertColor(endColor, nil, 0.24)
    db.colorVersion = 2
end

local COMBAT_ALERT_V2_COLORS = {
    startTextColor = { 0.18, 0.82, 1.00, 1.00 },
    startLineColor = { 0.18, 0.82, 1.00, 0.95 },
    startAccentColor = { 0.62, 0.34, 1.00, 0.65 },
    startDiamondColor = { 0.62, 0.34, 1.00, 0.95 },
    startWingColor = { 0.18, 0.82, 1.00, 0.82 },
    startPanelColor = { 0.62, 0.34, 1.00, 0.24 },
    startFlashColor = { 0.18, 0.82, 1.00, 0.24 },
    endTextColor = { 1.00, 0.72, 0.24, 1.00 },
    endLineColor = { 1.00, 0.72, 0.24, 0.95 },
    endAccentColor = { 1.00, 0.40, 0.22, 0.65 },
    endDiamondColor = { 1.00, 0.40, 0.22, 0.95 },
    endWingColor = { 1.00, 0.72, 0.24, 0.82 },
    endPanelColor = { 1.00, 0.40, 0.22, 0.24 },
    endFlashColor = { 1.00, 0.72, 0.24, 0.24 },
}

local COMBAT_ALERT_V3_COLORS = {
    startTextColor = { 0.70, 0.94, 1.00, 1.00 },
    startLineColor = { 0.12, 0.78, 0.92, 0.88 },
    startAccentColor = { 0.38, 0.55, 1.00, 0.72 },
    startDiamondColor = { 0.54, 0.36, 1.00, 0.90 },
    startWingColor = { 0.23, 0.72, 0.88, 0.70 },
    startPanelColor = { 0.03, 0.08, 0.12, 0.82 },
    startFlashColor = { 0.18, 0.82, 1.00, 0.14 },
    endTextColor = { 1.00, 0.85, 0.55, 1.00 },
    endLineColor = { 1.00, 0.63, 0.18, 0.88 },
    endAccentColor = { 1.00, 0.38, 0.18, 0.72 },
    endDiamondColor = { 1.00, 0.70, 0.28, 0.90 },
    endWingColor = { 1.00, 0.54, 0.18, 0.70 },
    endPanelColor = { 0.12, 0.055, 0.02, 0.82 },
    endFlashColor = { 1.00, 0.55, 0.16, 0.14 },
}

local function AlertColorsMatch(color, expected)
    if type(color) ~= "table" then return false end
    for index = 1, 4 do
        local value = tonumber(color[index])
        if not value or math.abs(value - expected[index]) > 0.001 then
            return false
        end
    end
    return true
end

local function MigrateCombatStateAlertDesign(profile)
    local db = type(profile) == "table" and profile.CombatStateAlert
    if type(db) ~= "table" or (tonumber(db.designVersion) or 0) >= 3 then return end

    local width = tonumber(db.width)
    local height = tonumber(db.height)
    if width == 420 or width == 520 then db.width = 480 end
    if height == 84 or height == 112 then db.height = 96 end

    for key, oldColor in pairs(COMBAT_ALERT_V2_COLORS) do
        if AlertColorsMatch(db[key], oldColor) then
            db[key] = CopyAlertColor(COMBAT_ALERT_V3_COLORS[key])
        end
    end
    db.designVersion = 3
end

local function MigratePartyAlertDesign(profile)
    if type(profile) ~= "table" then return end

    for _, moduleName in ipairs({ "LFGAlert", "PartyFullAlert" }) do
        local db = profile[moduleName]
        if type(db) == "table" and (tonumber(db.designVersion) or 0) < 2 then
            if db.animationEnabled == nil then
                db.animationEnabled = moduleName ~= "LFGAlert" or db.alertAnimation ~= "none"
            end
            db.designVersion = 2
        end
    end
end

local function MigrateBloodlustStartMotionStyle(profile)
    local db = type(profile) == "table" and profile.BloodlustTimer
    if type(db) == "table" and db.startMotionStyle == nil then
        db.startMotionStyle = "RITUAL"
    end
end

-- 데이터베이스 초기화
function ns:InitDB()
    ns.isFreshInstall = not (
        type(DDingUIToolkitDB) == "table"
        and type(DDingUIToolkitDB.profile) == "table"
    )

    if not DDingUIToolkitDB then
        DDingUIToolkitDB = {}
    end

    MigrateCombatStateAlertColors(DDingUIToolkitDB.profile)
    MigrateCombatStateAlertDesign(DDingUIToolkitDB.profile)
    MigratePartyAlertDesign(DDingUIToolkitDB.profile)
    MigrateBloodlustStartMotionStyle(DDingUIToolkitDB.profile)
    if type(DDingUIToolkitDB.profiles) == "table" then
        for _, storedProfile in pairs(DDingUIToolkitDB.profiles) do
            MigrateCombatStateAlertColors(storedProfile)
            MigrateCombatStateAlertDesign(storedProfile)
            MigratePartyAlertDesign(storedProfile)
            MigrateBloodlustStartMotionStyle(storedProfile)
        end
    end

    -- 프로필 초기화
    if not DDingUIToolkitDB.profile then
        DDingUIToolkitDB.profile = self:DeepCopy(self.defaults.profile)
    else
        DisableNewModulesForExistingProfile(DDingUIToolkitDB.profile, self.defaults.profile.modules)
        self:MergeDefaults(DDingUIToolkitDB.profile, self.defaults.profile)
    end
    RemoveRetiredModuleData(DDingUIToolkitDB.profile)
    if type(DDingUIToolkitDB.profiles) == "table" then
        for _, storedProfile in pairs(DDingUIToolkitDB.profiles) do
            RemoveRetiredModuleData(storedProfile)
        end
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
