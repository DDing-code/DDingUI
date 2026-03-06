local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

DDingUI.viewers = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

local defaults = {
    char = {},  -- per-character data (e.g., _specAutoSetup flag)
    global = {},
    profile = {
        general = {
            globalTexture = "Meli",
            globalFont = "Naowh",
            applyGlobalFontToBlizzard = false,
            eyefinity = false,
            ultrawide = false,
            uiScale = nil,
            guiScale = 1.0,  -- Config GUI scale (0.5 ~ 1.5)
            hideWhileFlying = false,
            hideWhileMounted = false,
            hideInVehicle = true,
        },
        minimap = {
            hide = false,
        },
        -- Unit Frames anchor settings (default disabled)
        unitFrames = {
            enabled = false,
            General = {
                ShowEditModeAnchors = false,
            },
        },
        viewers = {
            general = {
                cooldownFontSize = 18,
                cooldownTextColor = {1, 1, 1, 1},
                cooldownShadowOffsetX = 0,
                cooldownShadowOffsetY = 0,
                cooldownTextFormat = "auto", -- auto, seconds, mmss, decimal
                procGlow = {
                    enabled = true,
                    glowType = "Pixel Glow",
                    loopColor = {0.95, 0.95, 0.32, 1},
                    -- Pixel Glow
                    lcgLines = 5,
                    lcgFrequency = 0.25,
                    lcgLength = 8,
                    lcgThickness = 1,
                    -- Autocast Shine
                    autocastParticles = 8,
                    autocastFrequency = 0.25,
                    autocastScale = 1.0,
                    -- Action Button Glow
                    buttonGlowFrequency = 0.25,
                },
                assistHighlight = {
                    enabled = false,
                    highlightType = "flipbook", -- "flipbook" or "lcg"
                    flipbookScale = 1.5,
                    -- LCG settings (when highlightType = "lcg")
                    glowType = "Pixel Glow",
                    color = {0.3, 0.7, 1.0, 1},
                    lcgLines = 5,
                    lcgFrequency = 0.25,
                    lcgLength = 8,
                    lcgThickness = 1,
                },
            },
            EssentialCooldownViewer = {
                enabled          = true,
                iconSize         = 48,
                aspectRatioCrop  = 1.0,
                spacing          = 1,
                zoom             = 0.08,
                borderSize       = 1,
                borderColor      = { 0, 0, 0, 1 },
                chargeTextAnchor = "BOTTOMRIGHT",
                countTextSize    = 16,
                countTextOffsetX = 0,
                countTextOffsetY = 0,
                rowLimit         = 0,
                rowIconSizes     = {},
                primaryDirection = "CENTERED_HORIZONTAL",
                secondaryDirection = nil,
                cooldownFontSize = 18,
                cooldownTextColor = {1, 1, 1, 1},
                cooldownShadowOffsetX = 0,
                cooldownShadowOffsetY = 0,
                -- Animation options
                disableSwipeAnimation = false,
                swipeColor = nil,  -- nil = use Blizzard default
                swipeReverse = false,
                disableEdgeGlow = false,
                disableBlingAnimation = false,
                -- Aura swipe customization (for buff/survival ability duration display)
                auraSwipeColor = nil,  -- nil = keep CDM default yellow
                auraGlow = false,  -- Replace aura swipe with glow
                auraGlowType = "Pixel Glow",
                auraGlowColor = {0.95, 0.95, 0.32, 1},
                -- Aura Glow: Autocast Shine
                auraGlowAutocastParticles = 8,
                auraGlowAutocastFrequency = 0.25,
                auraGlowAutocastScale = 1.0,
                -- Aura Glow: Action Button Glow
                auraGlowButtonFrequency = 0.25,
                -- Group state offsets (party/raid)
                groupOffsets = {
                    party = { x = 0, y = 0 },
                    raid  = { x = 0, y = 0 },
                },
            },
            UtilityCooldownViewer = {
                enabled          = true,
                iconSize         = 48,
                aspectRatioCrop  = 1.0,
                spacing          = 1,
                zoom             = 0.08,
                borderSize       = 1,
                borderColor      = { 0, 0, 0, 1 },
                chargeTextAnchor = "BOTTOMRIGHT",
                countTextSize    = 16,
                countTextOffsetX = 0,
                countTextOffsetY = 0,
                rowLimit         = 0,
                rowIconSizes     = {},
                primaryDirection = "CENTERED_HORIZONTAL",
                secondaryDirection = nil,
                cooldownFontSize = 18,
                cooldownTextColor = {1, 1, 1, 1},
                cooldownShadowOffsetX = 0,
                cooldownShadowOffsetY = 0,
                -- Custom anchor settings
                anchorFrame   = "",
                anchorPoint   = "CENTER",
                anchorOffsetX = 0,
                anchorOffsetY = 0,
                -- Animation options
                disableSwipeAnimation = false,
                swipeColor = nil,  -- nil = use Blizzard default
                swipeReverse = false,
                disableEdgeGlow = false,
                disableBlingAnimation = false,
                -- Aura swipe customization (for buff/survival ability duration display)
                auraSwipeColor = nil,  -- nil = keep CDM default yellow
                auraGlow = false,  -- Replace aura swipe with glow
                auraGlowType = "Pixel Glow",
                auraGlowColor = {0.95, 0.95, 0.32, 1},
                -- Aura Glow: Autocast Shine
                auraGlowAutocastParticles = 8,
                auraGlowAutocastFrequency = 0.25,
                auraGlowAutocastScale = 1.0,
                -- Aura Glow: Action Button Glow
                auraGlowButtonFrequency = 0.25,
                -- Group state offsets (party/raid)
                groupOffsets = {
                    party = { x = 0, y = 0 },
                    raid  = { x = 0, y = 0 },
                },
            },
            BuffIconCooldownViewer = {
                enabled          = true,
                iconSize         = 38,
                aspectRatioCrop  = 1.0,
                spacing          = 1,
                zoom             = 0.08,
                borderSize       = 1,
                borderColor      = { 0, 0, 0, 1 },
                chargeTextAnchor = "BOTTOMRIGHT",
                countTextSize    = 14,
                countTextOffsetX = 0,
                countTextOffsetY = 0,
                rowLimit         = 0,
                rowIconSizes     = {},
                primaryDirection = "CENTERED_HORIZONTAL",
                secondaryDirection = nil,
                cooldownFontSize = 18,
                cooldownTextColor = {1, 1, 1, 1},
                cooldownShadowOffsetX = 0,
                cooldownShadowOffsetY = 0,
                -- Custom anchor settings
                anchorFrame   = "",
                anchorPoint   = "CENTER",
                anchorOffsetX = 0,
                anchorOffsetY = 0,
                -- BuffIconCooldownViewer specific options
                durationTextAnchor = "TOP",
                durationTextOffsetX = 0,
                durationTextOffsetY = 0,
                disableSwipeAnimation = false,
                swipeColor = {0, 0, 0, 0.8},
                swipeReverse = true,
                disableEdgeGlow = false,
                disableBlingAnimation = false,
            },
        },
        -- Keybinds Display
        cooldownManager_keybindFontName = "Friz Quadrata TT",
        cooldownManager_keybindFontFlags = { OUTLINE = true },
        cooldownManager_keybindFontColor = {1, 1, 1, 1},
        cooldownManager_showKeybinds_Essential = false,
        cooldownManager_keybindAnchor_Essential = "TOPRIGHT",
        cooldownManager_keybindFontSize_Essential = 14,
        cooldownManager_keybindOffsetX_Essential = -3,
        cooldownManager_keybindOffsetY_Essential = -3,
        cooldownManager_keybindFontName_Essential = nil,
        cooldownManager_keybindFontColor_Essential = nil,
        cooldownManager_showKeybinds_Utility = false,
        cooldownManager_keybindAnchor_Utility = "TOPRIGHT",
        cooldownManager_keybindFontSize_Utility = 10,
        cooldownManager_keybindOffsetX_Utility = -3,
        cooldownManager_keybindOffsetY_Utility = -3,
        cooldownManager_keybindFontName_Utility = nil,
        cooldownManager_keybindFontColor_Utility = nil,
        buffBarViewer = {
            enabled = true,
            width = 0,
            height = 16,
            hideIconMask = true,
            hideIcon = false,
            borderSize = 1,
            borderColor = { 0, 0, 0, 1 },
            texture = nil,
            barColor = { 0.9, 0.9, 0.9, 1 },
            bgColor = { 0.15, 0.15, 0.15, 1 },
            iconZoom = 0.08,
            iconBorderSize = 1,
            iconBorderColor = { 0, 0, 0, 1 },
            showName = true,
            nameSize = 14,
            nameColor = { 1, 1, 1, 1 },
            nameAnchor = "LEFT",
            nameOffsetX = 0,
            nameOffsetY = 0,
            showDuration = true,
            durationSize = 12,
            durationColor = { 1, 1, 1, 1 },
            durationAnchor = "RIGHT",
            durationOffsetX = 0,
            durationOffsetY = 0,
            showApplications = true,
            applicationsSize = 12,
            applicationsColor = { 1, 1, 1, 1 },
            applicationsAnchor = "BOTTOMRIGHT",
            applicationsOffsetX = 0,
            applicationsOffsetY = 0,
            growDirection = "BOTTOM",  -- BOTTOM: bars grow upward, TOP: bars grow downward
            disableDynamicLayout = true,
            barColors = {},
            barColorsBySpec = {},
            -- Custom anchor settings
            anchorFrame   = "",
            anchorPoint   = "CENTER",
            anchorOffsetX = 0,
            anchorOffsetY = 0,
        },
        powerBar = {
            enabled           = true,
            attachTo          = "EssentialCooldownViewer",
            anchorPoint       = "TOP",
            frameStrata       = "MEDIUM",
            height            = 14,
            offsetX           = 0,
            offsetY           = 10,
            width             = 0,
            texture           = nil,
            textFont          = nil,
            textFormat        = nil,
            useClassColor     = true,
            showManaAsPercent = true,
            textPrecision     = 0,
            showPercentSign   = true,
            showText          = true,
            showTicks         = true,
            tickWidth         = 2,
            smoothProgress    = true,
            fasterUpdates     = true,
            updateFrequency   = 0.1,
            textSize          = 20,
            textX             = 1,
            textY             = 2,
            bgColor           = { 0.15, 0.15, 0.15, 1 },
            borderSize        = 1,
            borderColor       = { 0, 0, 0, 1 },
            -- No secondary resource size settings
            useNoSecondarySize = false,
            noSecondaryHeight  = 14,
            noSecondaryWidth   = 0,
            noSecondaryOffsetY = 27, -- 보조 자원 바 위치에 맞춤 (BOTTOM 앵커 사용)
            hideWhenMana      = false,
            hideBarShowText   = false,
            -- Threshold colors (hardcoded: 0-35% red, 35-70% yellow, 70-100% base)
            thresholdEnabled = false,
            -- Custom markers (divider lines at specific resource values)
            markers = {},          -- { 30, 70, 100 } plain value array
            markerColor = { 1, 1, 1, 0.8 },
            markerWidth = 2,
            markerColorChange = false,
            markerBarColors = {},  -- { {1,0,0,1}, {1,1,0,1} } parallel to markers
        },
        secondaryPowerBar = {
            enabled       = true,
            attachTo      = "EssentialCooldownViewer",
            anchorPoint   = "TOP",
            frameStrata   = "MEDIUM",
            height        = 14,
            offsetX       = 0,
            offsetY       = 27,
            width         = 0,
            texture       = nil,
            textFont      = nil,
            textFormat    = nil,
            bgTexture     = nil,
            useClassColor = false,
            showManaAsPercent = true,
            hideWhenMana  = false,
            showText      = true,
            showTicks     = true,
            tickWidth     = 2,
            hideBarShowText = false,
            showFragmentedPowerBarText  = false,
            fragmentedPowerBarTextPrecision = nil,
            runeTimerFont = nil,
            smoothProgress = true,
            fasterUpdates = true,
            updateFrequency = 0.1,
            textSize      = 16,
            textX         = 1,
            textY         = 2,
            textPrecision = 0,  -- 백분율 소수점 자릿수 (0, 1, 2)
            showPercentSign = false,  -- 백분율에 % 기호 표시
            runeTimerTextSize = 10,
            runeTimerTextX    = 0,
            runeTimerTextY    = 0,
            -- No primary resource size (주자원 마나 숨김 시 보조자원 승격)
            useNoPrimarySize  = false,
            noPrimaryHeight   = 14,
            noPrimaryWidth    = 0,
            noPrimaryOffsetY  = 10,
            chargedColor  = { 0.22, 0.62, 1.0, 0.8 },
            bgColor       = { 0.15, 0.15, 0.15, 1 },
            borderSize    = 1,
            borderColor   = { 0, 0, 0, 1 },
            -- Threshold colors (hardcoded: 0-35% red, 35-70% yellow, 70-100% base)
            thresholdEnabled = false,
            -- Custom markers (divider lines at specific resource values)
            markers = {},          -- { 30, 70, 100 } plain value array
            markerColor = { 1, 1, 1, 0.8 },
            markerWidth = 2,
            markerColorChange = false,
            markerBarColors = {},  -- { {1,0,0,1}, {1,1,0,1} } parallel to markers
            -- Max resource color (바 꽉 찼을 때 색상 변경)
            enableMaxColor = false,
            maxColor       = { 1.0, 0.3, 0.3, 1.0 },
            -- Recharge color (룬/에센스 재충전 색상)
            useRechargeColor = false,
            rechargeColor  = { 0.4, 0.4, 0.4, 1.0 },
            -- Per-point colors (콤보포인트 등 포인트별 색상)
            enablePerPointColors = false,
            perPointColors = {
                {0.2, 1, 0.2, 1},     -- 1
                {0.4, 1, 0.2, 1},     -- 2
                {0.6, 1, 0.2, 1},     -- 3
                {0.8, 1, 0.2, 1},     -- 4
                {1, 0.8, 0.2, 1},     -- 5
                {1, 0.5, 0.2, 1},     -- 6
                {1, 0.3, 0.2, 1},     -- 7
                {1, 0.2, 0.2, 1},     -- 8
                {1, 0.1, 0.1, 1},     -- 9
                {1, 0, 0, 1},         -- 10
            },
            -- Overflow color (기준점 초과시 첫 칸부터 오버레이)
            enableOverflowColor = false,
            overflowThreshold = 5,
            overflowColor = { 1.0, 0.3, 0.3, 1.0 },
        },
        buffTrackerBar = {
            enabled       = false,
            attachTo      = "EssentialCooldownViewer",
            anchorPoint   = "TOP",
            frameStrata   = "MEDIUM",
            height        = 4,
            offsetX       = 0,
            offsetY       = 18,
            width         = 0,
            growthDirection = "DOWN",  -- "UP", "DOWN", "LEFT", "RIGHT"
            growthSpacing = 20,        -- spacing between stacked bars
            texture       = nil,
            borderSize    = 1,
            borderColor   = { 0, 0, 0, 1 },
            bgColor       = { 0.15, 0.15, 0.15, 1 },
            barColor      = { 1, 0.8, 0, 1 },
            barOrientation = "HORIZONTAL", -- "HORIZONTAL" or "VERTICAL"
            barReverseFill = false,  -- 바: 역방향 채움 (우→좌, 상→하)
            ringReverse = true,      -- 링: 역방향 (시계→반시계 느낌, 채움 vs 비움)
            showText      = true,
            textFont      = nil,
            textSize      = 12,
            textX         = 0,
            textY         = 0,
            textColor     = { 1, 1, 1, 1 },
            textAlign     = "CENTER",
            -- Duration text settings
            durationTextFont  = nil,
            durationTextSize  = 10,
            durationTextX     = 0,
            durationTextY     = -10,
            durationTextColor = { 1, 1, 1, 1 },
            durationTextAlign = "CENTER",
            showTicks     = true,
            smoothProgress = true,
            hideWhenZero  = true,
            showInCombat  = false,  -- Always show during combat even if hideWhenZero is enabled
            spellID       = 0,
            cooldownID    = 0,        -- CDM cooldown ID for CDM tracking mode
            maxStacks     = 1,
            -- Tracking mode: "cdm" (recommended), "manual", or "buff"
            trackingMode  = "cdm",    -- "cdm" uses CDM integration (most accurate)
            generatorSpellIDs = "",  -- e.g., "190411,6343,435222" for Whirlwind/Thunder Clap/Thunder Blast
            spenderSpellIDs   = "",  -- e.g., "23881,85288,280735" for Bloodthirst/Raging Blow/Execute
            generatorBehavior = "setMax", -- "setMax" or "addOne"
            stackDuration = 20,      -- seconds before stacks expire
            resetOnCombatEnd = true, -- reset stacks when leaving combat
            barFillMode   = "stacks", -- "stacks" or "duration" for bar fill
            showStacksText = false,   -- show stacks text
            showDurationText = false, -- show duration text
            -- Talent conditions
            requireTalentID = 0,      -- talent spell ID required to enable tracker (0 = always enabled)
            bonusTalentID   = 0,      -- talent spell ID that grants bonus stacks
            bonusTalentStacks = 1,    -- bonus max stacks when talent is learned
            -- Per-spec handled by SpecProfiles system now
            usePerSpec    = false,    -- deprecated, kept for migration
            specs         = {},       -- deprecated, kept for migration
            -- Tracked buffs list (new foldable UI system)
            trackedBuffs  = {},       -- array of tracked buffs with settings (legacy/migration)
            -- Per-spec tracked buffs (uses specID as key for cross-class uniqueness)
            trackedBuffsPerSpec = {}, -- [specID] = { tracked buffs array }
            -- trackedBuffs structure:
            -- [1] = {
            --     cooldownID = 12345,
            --     name = "Buff Name",
            --     icon = 134400,
            --     displayType = "bar",  -- "bar" | "icon"
            --     expanded = false,     -- foldable state
            --     hideFromCDM = false,  -- hide from Cooldown Manager when tracked
            --     settings = {
            --         maxStacks = 10,
            --         stackDuration = 30,
            --         dynamicDuration = true,  -- Auto mode: read duration from CDM at runtime (default ON)
            --         hideWhenZero = true,
            --         showInCombat = false,
            --         barColor = {1, 0.8, 0, 1},
            --         showStacksText = true,
            --         showDurationText = false,
            --         durationDecimals = 1,  -- decimal places for duration (0-2)
            --         ...
            --     }
            -- }
        },
        powerTypeColors = {
            useClassColor = true,
            colors = {
                -- Primary Power Types
                [Enum.PowerType.Mana] = { 0.00, 0.00, 1.00, 1.0 },
                [Enum.PowerType.Rage] = { 1.00, 0.00, 0.00, 1.0 },
                [Enum.PowerType.Focus] = { 1.00, 0.50, 0.25, 1.0 },
                [Enum.PowerType.Energy] = { 1.00, 1.00, 0.00, 1.0 },
                [Enum.PowerType.RunicPower] = { 0.00, 0.82, 1.00, 1.0 },
                [Enum.PowerType.LunarPower] = { 0.30, 0.52, 0.90, 1.0 },
                [Enum.PowerType.Fury] = { 0.79, 0.26, 0.99, 1.0 },
                [Enum.PowerType.Maelstrom] = { 0.00, 0.50, 1.00, 1.0 },
                -- Secondary Power Types
                [Enum.PowerType.Runes] = { 0.77, 0.12, 0.23, 1.0 },
                ["SOUL"] = { 0.64, 0.19, 0.79, 1.0 },
                [Enum.PowerType.ComboPoints] = { 1.00, 0.96, 0.41, 1.0 },
                [Enum.PowerType.Essence] = { 0.20, 0.58, 0.50, 1.0 },
                [Enum.PowerType.ArcaneCharges] = { 0.20, 0.60, 1.00, 1.0 },
                ["STAGGER"] = { 1.00, 0.42, 0.42, 1.0 },
                [Enum.PowerType.Chi] = { 0.00, 1.00, 0.59, 1.0 },
                [Enum.PowerType.HolyPower] = { 0.95, 0.90, 0.60, 1.0 },
                [Enum.PowerType.SoulShards] = { 0.58, 0.51, 0.79, 1.0 },
                ["MAELSTROM_WEAPON"] = { 0.00, 0.50, 1.00, 1.0 },
                -- DK Rune Spec Colors
                ["RUNE_BLOOD"]  = { 1.00, 0.25, 0.25, 1.0 },
                ["RUNE_FROST"]  = { 0.25, 1.00, 1.00, 1.0 },
                ["RUNE_UNHOLY"] = { 0.25, 1.00, 0.25, 1.0 },
                -- Stagger threshold colors
                ["STAGGER_LIGHT"]  = { 0.52, 1.00, 0.52, 1.0 },
                ["STAGGER_MEDIUM"] = { 1.00, 0.98, 0.72, 1.0 },
                ["STAGGER_HEAVY"]  = { 1.00, 0.42, 0.42, 1.0 },
            },
        },
        castBar = {
            showEmpoweredTicks = true,
            showEmpoweredStageColors = true,
            enabled       = true,
            attachTo      = "EssentialCooldownViewer",
            frameStrata   = "MEDIUM",
            height        = 24,
            offsetY       = -83,
            showIcon      = true,
            texture       = nil,
            color         = { 1.0, 0.7, 0.0, 1.0 },
            useClassColor = false,
            textSize      = 16,
            width         = 0,
            bgColor       = { 0.1, 0.1, 0.1, 1 },
            showTimeText  = true,
            interruptedColor      = { 0.9, 0.2, 0.2, 1.0 },
            interruptedFadeEnabled = true,
            interruptedFadeDuration = 0.3,
            empoweredStageColors = {
                [1] = {0.3, 0.75, 1, 1},
                [2] = {0.4, 1, 0.4, 1},
                [3] = {1, 0.85, 0, 1},
                [4] = {1, 0.5, 0, 1},
                [5] = {1, 0.2, 0.2, 1},
            },
        },
        customIcons = {
            enabled = true,
            countTextSize = 16,
            countTextX = -2,
            countTextY = 2,
            countTextAnchor = "BOTTOMRIGHT",
            trackedItems = {},
            consumables = {
                iconSize = 44,
                aspectRatioCrop = 1.0,
                spacing = 1,
                rowLimit = 0,
                growthDirection = "Right",
                anchorPoint = "BOTTOMLEFT",
                borderSize = 1,
                borderColor = { 0, 0, 0, 1 },
                anchorFrame = "DDingUI_Player",
                offsetX = 1,
                offsetY = -2,
                hideUnusableItems = false,
                countTextSize = 16,
                countTextX = -2,
                countTextY = 2,
                countTextAnchor = "BOTTOMRIGHT",
                item_241304 = true,
                item_241300 = true,
                item_241308 = true,
                item_241288 = true,
                item_241292 = true,
                item_241296 = true,
                item_241294 = true,
                item_241286 = true,
                item_241302 = true,
            },
            items = {
                iconSize = 44,
                aspectRatioCrop = 1.0,
                spacing = 1,
                rowLimit = 0,
                growthDirection = "Right",
                anchorPoint = "BOTTOMLEFT",
                borderSize = 1,
                borderColor = { 0, 0, 0, 1 },
                anchorFrame = "DDingUI_Player",
                offsetX = 1,
                offsetY = -2,
                hideUnusableItems = false,
            },
            trinkets = {
                trinket1 = true,
                trinket2 = true,
                weapon1 = true,
                weapon2 = true,
                iconSize = 44,
                aspectRatioCrop = 1.0,
                spacing = 1,
                rowLimit = 0,
                growthDirection = "LEFT",
                anchorPoint = "TOPRIGHT",
                borderSize = 1,
                borderColor = { 0, 0, 0, 1 },
                anchorFrame = "DDingUI_Player",
                offsetX = -1,
                offsetY = 49,
                hideUnusableItems = true,
                countTextSize = 16,
                countTextX = -2,
                countTextY = 2,
                countTextAnchor = "BOTTOMRIGHT",
            },
            defensives = {
                enabled = true,
                iconSize = 44,
                aspectRatioCrop = 1.0,
                spacing = 1,
                rowLimit = 0,
                growthDirection = "LEFT",
                anchorPoint = "TOPRIGHT",
                borderSize = 1,
                borderColor = { 0, 0, 0, 1 },
                anchorFrame = "DDingUI_Player",
                offsetX = -1,
                offsetY = 2,
                hideUnusableSpells = true,
                countTextSize = 16,
                countTextX = -2,
                countTextY = 2,
                countTextAnchor = "BOTTOMRIGHT",
            },
            racials = {
                iconSize = 44,
                aspectRatioCrop = 1.0,
                spacing = 1,
                rowLimit = 0,
                growthDirection = "LEFT",
                anchorPoint = "TOPRIGHT",
                borderSize = 1,
                borderColor = { 0, 0, 0, 1 },
                anchorFrame = "DDingUI_Player",
                offsetX = 0,
                offsetY = -45,
                hideUnusableSpells = true,
                spell_274738 = true,
                spell_202719 = true,
                spell_26297 = true,
                spell_20572 = true,
                spell_255654 = true,
                spell_20577 = true,
                spell_68992 = true,
                spell_20589 = true,
                spell_265221 = true,
                spell_28880 = true,
                spell_287712 = true,
                spell_312924 = true,
                spell_255647 = true,
                spell_107079 = true,
                spell_69070 = true,
                spell_58984 = true,
                spell_256948 = true,
                spell_20594 = true,
                spell_20549 = true,
                spell_7744 = true,
                spell_59752 = true,
                spell_357214 = true,
            },
        },
        dynamicIcons = {
            enabled = true,
            iconData = {},
            ungrouped = {},
            groups = {},
        },
        iconCustomization = {
            spells = {},
        },
        movers = {
            showGrid = false,
        },
        buffDebuffFrames = {
            enabled = false,  -- 모듈 비활성화 상태
            layout = {
                iconsPerRow = 12,
                iconSpacing = 5,
                rowSpacing = 5,
                anchorSide = "TOPRIGHT",
                growthHorizontal = "LEFT",
                growthVertical = "DOWN",
            },
            buffs = {
                enabled = true,
                iconSize = 38,
                layout = {
                    iconsPerRow = 12,
                    iconSpacing = 11,
                    rowSpacing = 1,
                    anchorSide = "TOPRIGHT",
                },
                duration = {
                    enabled = true,
                    anchorPoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                    fontSize = 12,
                    fontFlag = "OUTLINE",
                    textColor = {1, 1, 1, 1},
                },
                count = {
                    enabled = true,
                    anchorPoint = "BOTTOMRIGHT",
                    offsetX = 0,
                    offsetY = 0,
                    fontSize = 12,
                    fontFlag = "OUTLINE",
                    textColor = {1, 1, 1, 1},
                },
            },
            debuffs = {
                enabled = true,
                iconSize = 38,
                layout = {
                    iconsPerRow = 12,
                    iconSpacing = 11,
                    rowSpacing = 1,
                    anchorSide = "TOPRIGHT",
                },
                duration = {
                    enabled = true,
                    anchorPoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                    fontSize = 12,
                    fontFlag = "OUTLINE",
                    textColor = {1, 1, 1, 1},
                },
                count = {
                    enabled = true,
                    anchorPoint = "BOTTOMRIGHT",
                    offsetX = 0,
                    offsetY = 0,
                    fontSize = 12,
                    fontFlag = "OUTLINE",
                    textColor = {1, 1, 1, 1},
                },
            },
        },
        -- Missing Alerts (Pet Missing, Class Buff Missing)
        missingAlerts = {
            enabled = true,
            -- Pet Missing Alert
            petMissingEnabled = true,
            petText = "PET IS MISSING",
            petOffsetX = 0,
            petOffsetY = 150,
            petFontSize = 48,
            petTextColor = { 0.42, 1, 0, 1 },  -- Green
            petBorderSize = 0,  -- 0 = no border
            petBorderColor = { 0, 0, 0, 1 },
            petInstanceOnly = false,
            petAnchorPoint = "CENTER",
            -- Class Buff Missing Alert (DISABLED - 모듈 비활성화됨)
            buffMissingEnabled = false,
            buffOffsetX = 0,
            buffOffsetY = 230,
            buffIconSize = 64,
            buffDesaturate = false,
        },
    },
}

DDingUI.defaults = defaults
