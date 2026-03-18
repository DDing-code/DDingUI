--[[
	ddingUI UnitFrames
	AuraDesigner/Config.lua — Spec-specific aura display definitions
	
	DandersFrames AuraDesigner/Config.lua 패턴 기반.
	스펙별 추적 가능한 오라, 스펠 ID, Secret 시그니처 정의.
]]

local _, ns = ...

-- Initialize namespace
ns.AuraDesigner = ns.AuraDesigner or {}
local AD = ns.AuraDesigner

-- ============================================================
-- SPEC MAP
-- Maps CLASS_SPECNUM to internal spec key (DandersFrames 동일)
-- ============================================================
AD.SpecMap = {
	DRUID_4     = "RestorationDruid",
	SHAMAN_3    = "RestorationShaman",
	PRIEST_1    = "DisciplinePriest",
	PRIEST_2    = "HolyPriest",
	PALADIN_1   = "HolyPaladin",
	EVOKER_2    = "PreservationEvoker",
	EVOKER_3    = "AugmentationEvoker",
	MONK_2      = "MistweaverMonk",
}

-- ============================================================
-- SPEC INFO
-- Display names and class tokens for each supported spec
-- ============================================================
AD.SpecInfo = {
	PreservationEvoker  = { display = "보존 소환사",     class = "EVOKER"  },
	AugmentationEvoker  = { display = "증강 소환사",     class = "EVOKER"  },
	RestorationDruid    = { display = "회복 드루이드",   class = "DRUID"   },
	DisciplinePriest    = { display = "수양 사제",       class = "PRIEST"  },
	HolyPriest          = { display = "신성 사제",       class = "PRIEST"  },
	MistweaverMonk      = { display = "운무 수도사",     class = "MONK"    },
	RestorationShaman   = { display = "회복 주술사",     class = "SHAMAN"  },
	HolyPaladin         = { display = "신성 기사",       class = "PALADIN" },
}

-- ============================================================
-- STATIC ICON TEXTURES
-- Hardcoded texture IDs: C_Spell.GetSpellTexture() dynamically
-- swaps icons when a talent replaces a spell, causing both tiles
-- to show the same icon. Static IDs avoid this entirely.
-- ============================================================
AD.IconTextures = {
	-- Preservation Evoker
	Echo                = 4622456,
	Reversion           = 4630467,
	EchoReversion       = 4630469,
	DreamBreath         = 4622454,
	EchoDreamBreath     = 7439198,
	DreamFlight         = 4622455,
	Lifebind            = 4630453,
	TimeDilation        = 4622478,
	Rewind              = 4622474,
	VerdantEmbrace      = 4622471,
	-- Augmentation Evoker
	Prescience          = 5199639,
	ShiftingSands       = 5199633,
	BlisteringScales    = 5199621,
	InfernosBlessing    = 5199632,
	SymbioticBloom      = 4554354,
	EbonMight           = 5061347,
	SourceOfMagic       = 4630412,
	SensePower          = 132160,
	-- Restoration Druid
	Rejuvenation        = 136081,
	Regrowth            = 136085,
	Lifebloom           = 134206,
	Germination         = 1033478,
	WildGrowth          = 236153,
	SymbioticRelationship = 1408837,
	IronBark            = 572025,
	-- Discipline Priest
	PowerWordShield     = 135940,
	Atonement           = 458720,
	VoidShield          = 7514191,
	PrayerOfMending     = 135944,
	PainSuppression     = 135936,
	PowerInfusion       = 135939,
	-- Holy Priest
	Renew               = 135953,
	EchoOfLight         = 237537,
	GuardianSpirit      = 237542,
	-- Mistweaver Monk
	RenewingMist        = 627487,
	EnvelopingMist      = 775461,
	SoothingMist        = 606550,
	AspectOfHarmony     = 5927638,
	LifeCocoon          = 627485,
	StrengthOfTheBlackOx = 615340,
	-- Restoration Shaman
	Riptide             = 252995,
	EarthShield         = 136089,
	AncestralVigor      = 237574,
	EarthlivingWeapon   = 237578,
	Hydrobubble         = 1320371,
	-- Holy Paladin
	BeaconOfFaith       = 1030095,
	EternalFlame        = 135433,
	BeaconOfLight       = 236247,
	BeaconOfVirtue      = 1030094,
	BeaconOfTheSavior   = 7514188,
	BlessingOfProtection = 135964,
	HolyArmaments       = 5927636,
	BlessingOfSacrifice = 135966,
	BlessingOfFreedom   = 135968,
	Dawnlight           = 5927633,
}

-- ============================================================
-- TOOLTIP SPELL ID OVERRIDES
-- Some aura spell IDs are internal/secret and produce wrong tooltips.
-- Map aura name → castable spell ID for correct tooltip display.
-- ============================================================
AD.TooltipSpellIDs = {
	VerdantEmbrace = 360995,
	EbonMight = 395296,
}

-- ============================================================
-- SPELL IDS PER SPEC
-- Used for runtime aura matching via reverse spell ID lookup
-- ============================================================
AD.SpellIDs = {
	PreservationEvoker = {
		Echo = 364343, Reversion = 366155, EchoReversion = 367364,
		DreamBreath = 355941, EchoDreamBreath = 376788,
		DreamFlight = 363502, Lifebind = 373267,
		TimeDilation = 357170, Rewind = 363534, VerdantEmbrace = 409895,
	},
	AugmentationEvoker = {
		Prescience = 410089, ShiftingSands = 413984, BlisteringScales = 360827,
		InfernosBlessing = 410263, SymbioticBloom = 410686, EbonMight = 395152,
		SourceOfMagic = 369459,
		SensePower = 361022,
	},
	RestorationDruid = {
		Rejuvenation = 774, Regrowth = 8936, Lifebloom = 33763,
		Germination = 155777, WildGrowth = 48438, SymbioticRelationship = 474754,
		IronBark = 102342,
	},
	DisciplinePriest = {
		PowerWordShield = 17, Atonement = 194384,
		VoidShield = 1253593, PrayerOfMending = 41635,
		PainSuppression = 33206, PowerInfusion = 10060,
	},
	HolyPriest = {
		Renew = 139, EchoOfLight = 77489,
		PrayerOfMending = 41635,
		GuardianSpirit = 47788, PowerInfusion = 10060,
	},
	MistweaverMonk = {
		RenewingMist = 119611, EnvelopingMist = 124682, SoothingMist = 115175,
		AspectOfHarmony = 450769,
		LifeCocoon = 116849, StrengthOfTheBlackOx = 443113,
	},
	RestorationShaman = {
		Riptide = 61295, EarthShield = 383648,
		AncestralVigor = 207400,
		EarthlivingWeapon = 382024,
		Hydrobubble = 444490,
	},
	HolyPaladin = {
		BeaconOfFaith = 156910, EternalFlame = 156322, BeaconOfLight = 53563,
		BeaconOfTheSavior = 1244893, BeaconOfVirtue = 200025,
		BlessingOfProtection = 1022, HolyArmaments = 432502,
		BlessingOfSacrifice = 6940, BlessingOfFreedom = 1044,
		Dawnlight = 431381,
	},
}

-- ============================================================
-- SELF-ONLY SPELL IDS
-- Auras that only appear on the caster (player unit) but are
-- sourced by another unit (e.g. Symbiotic Relationship buff).
-- ============================================================
AD.SelfOnlySpellIDs = {
	RestorationDruid = {
		[474754] = "SymbioticRelationship",
	},
	AugmentationEvoker = {
		[395296] = "EbonMight",
	},
}

-- ============================================================
-- ALTERNATE SPELL IDS
-- Some spells have multiple IDs. Merged into reverse lookup.
-- ============================================================
AD.AlternateSpellIDs = {
	RestorationShaman = {
		[974]    = "EarthShield",
		[382021] = "EarthlivingWeapon",
		[382022] = "EarthlivingWeapon",
	},
}

-- ============================================================
-- SECRET AURA FINGERPRINTS
-- Filter fingerprinting technique from Harrek's Advanced Raid Frames.
-- 4-filter signature = which WoW filter strings the aura passes.
-- ============================================================
AD.SecretAuraInfo = {
	PreservationEvoker = {
		auras = {
			TimeDilation   = { signature = "1:1:1:0" },
			Rewind         = { signature = "1:1:0:0" },
			VerdantEmbrace = { signature = "0:1:0:0" },
		},
		casts = {
			[357170] = { "TimeDilation" },
			[363534] = { "Rewind" },
			[360995] = { "Lifebind", "VerdantEmbrace" },
		},
	},
	RestorationDruid = {
		auras = {
			IronBark = { signature = "1:1:1:0" },
		},
		casts = {
			[102342] = { "IronBark" },
		},
	},
	DisciplinePriest = {
		auras = {
			PainSuppression = { signature = "1:1:1:0" },
			PowerInfusion   = { signature = "1:0:0:1" },
		},
		casts = {
			[33206] = { "PainSuppression" },
			[10060] = { "PowerInfusion" },
		},
	},
	HolyPriest = {
		auras = {
			GuardianSpirit = { signature = "1:1:1:0" },
			PowerInfusion  = { signature = "1:0:0:1" },
		},
		casts = {
			[47788] = { "GuardianSpirit" },
			[10060] = { "PowerInfusion" },
		},
	},
	MistweaverMonk = {
		auras = {
			LifeCocoon           = { signature = "1:1:1:0" },
			StrengthOfTheBlackOx = { signature = "0:1:0:1" },
		},
		casts = {},
	},
	HolyPaladin = {
		auras = {
			BlessingOfProtection = { signature = "1:1:1:1" },
			HolyArmaments        = { signature = "0:1:0:0" },
			BlessingOfSacrifice  = { signature = "1:1:1:0" },
			BlessingOfFreedom    = { signature = "1:0:0:1" },
			Dawnlight            = { signature = "0:1:0:0" },
		},
		casts = {
			[1022]   = { "BlessingOfProtection" },
			[432472] = { "HolyArmaments" },
			[6940]   = { "BlessingOfSacrifice" },
		},
	},
	AugmentationEvoker = {
		auras = {
			SensePower = { signature = "0:1:0:0" },
		},
		casts = {},
	},
}

-- ============================================================
-- TRACKABLE AURAS PER SPEC
-- Each aura: { name, display, color, secret }
-- Colors used for UI tile accents in Options.
-- ============================================================
AD.TrackableAuras = {
	PreservationEvoker = {
		{ name = "Echo",             display = "메아리",             color = {0.31, 0.76, 0.97} },
		{ name = "Reversion",        display = "되돌림",             color = {0.51, 0.78, 0.52} },
		{ name = "EchoReversion",    display = "메아리 되돌림",       color = {0.40, 0.77, 0.74} },
		{ name = "DreamBreath",      display = "꿈의 숨결",          color = {0.47, 0.87, 0.47} },
		{ name = "EchoDreamBreath",  display = "메아리 꿈의 숨결",    color = {0.36, 0.82, 0.60} },
		{ name = "DreamFlight",      display = "꿈의 비행",          color = {0.81, 0.58, 0.93} },
		{ name = "Lifebind",         display = "생명 결속",          color = {0.94, 0.50, 0.50} },
		{ name = "TimeDilation",     display = "시간 팽창",          color = {0.94, 0.82, 0.31}, secret = true },
		{ name = "Rewind",           display = "되감기",             color = {0.74, 0.85, 0.40}, secret = true },
		{ name = "VerdantEmbrace",   display = "푸른 포옹",          color = {0.47, 0.87, 0.47}, secret = true },
	},
	AugmentationEvoker = {
		{ name = "Prescience",       display = "예지력",             color = {0.81, 0.58, 0.85} },
		{ name = "ShiftingSands",    display = "변화하는 모래",       color = {1.00, 0.84, 0.28} },
		{ name = "BlisteringScales", display = "타오르는 비늘",       color = {0.94, 0.50, 0.50} },
		{ name = "InfernosBlessing", display = "지옥불의 축복",       color = {1.00, 0.60, 0.28} },
		{ name = "SymbioticBloom",   display = "공생의 꽃",          color = {0.51, 0.78, 0.52} },
		{ name = "EbonMight",        display = "칠흑의 힘",          color = {0.62, 0.47, 0.85} },
		{ name = "SourceOfMagic",    display = "마력의 원천",         color = {0.31, 0.76, 0.97} },
		{ name = "SensePower",       display = "힘 감지",            color = {0.94, 0.82, 0.31}, secret = true },
	},
	RestorationDruid = {
		{ name = "Rejuvenation",           display = "회복",               color = {0.51, 0.78, 0.52} },
		{ name = "Regrowth",               display = "재성장",             color = {0.31, 0.76, 0.97} },
		{ name = "Lifebloom",              display = "생명꽃",             color = {0.56, 0.93, 0.56} },
		{ name = "Germination",            display = "발아",               color = {0.77, 0.89, 0.42} },
		{ name = "WildGrowth",             display = "급속 성장",          color = {0.81, 0.58, 0.93} },
		{ name = "SymbioticRelationship",  display = "공생",               color = {0.40, 0.77, 0.74} },
		{ name = "IronBark",               display = "나무 껍질",          color = {0.65, 0.47, 0.33}, secret = true },
	},
	DisciplinePriest = {
		{ name = "PowerWordShield", display = "신성한 보호막",   color = {1.00, 0.84, 0.28} },
		{ name = "Atonement",       display = "속죄",            color = {0.94, 0.50, 0.50} },
		{ name = "VoidShield",      display = "공허의 방패",      color = {0.62, 0.47, 0.85} },
		{ name = "PrayerOfMending", display = "치유의 기원",      color = {0.56, 0.93, 0.56} },
		{ name = "PainSuppression", display = "고통 억제",       color = {0.81, 0.58, 0.93}, secret = true },
		{ name = "PowerInfusion",   display = "신의 권능: 주입",  color = {0.94, 0.82, 0.31}, secret = true },
	},
	HolyPriest = {
		{ name = "Renew",           display = "갱생",               color = {0.56, 0.93, 0.56} },
		{ name = "EchoOfLight",     display = "빛의 메아리",         color = {1.00, 0.84, 0.28} },
		{ name = "PrayerOfMending", display = "치유의 기원",         color = {0.81, 0.58, 0.93} },
		{ name = "GuardianSpirit",  display = "수호 영혼",           color = {0.94, 0.50, 0.50}, secret = true },
		{ name = "PowerInfusion",   display = "신의 권능: 주입",     color = {0.94, 0.82, 0.31}, secret = true },
	},
	MistweaverMonk = {
		{ name = "RenewingMist",     display = "되살림의 안개",       color = {0.56, 0.93, 0.56} },
		{ name = "EnvelopingMist",   display = "감싸는 안개",         color = {0.31, 0.76, 0.97} },
		{ name = "SoothingMist",     display = "진정의 안개",         color = {0.47, 0.87, 0.47} },
		{ name = "AspectOfHarmony",  display = "조화의 면모",         color = {0.81, 0.58, 0.93} },
		{ name = "LifeCocoon",       display = "생명의 고치",         color = {0.31, 0.76, 0.97}, secret = true },
		{ name = "StrengthOfTheBlackOx", display = "검은 소의 힘",    color = {0.40, 0.77, 0.74}, secret = true },
	},
	RestorationShaman = {
		{ name = "Riptide",           display = "성난 파도",          color = {0.31, 0.76, 0.97} },
		{ name = "EarthShield",       display = "대지의 방패",        color = {0.65, 0.47, 0.33} },
		{ name = "AncestralVigor",    display = "조상의 기백",        color = {0.56, 0.93, 0.56} },
		{ name = "EarthlivingWeapon", display = "대지살이 무기",      color = {0.47, 0.87, 0.47} },
		{ name = "Hydrobubble",       display = "수중 방울",          color = {0.31, 0.76, 0.97} },
	},
	HolyPaladin = {
		{ name = "BeaconOfFaith",       display = "신앙의 봉화",        color = {1.00, 0.84, 0.28} },
		{ name = "EternalFlame",        display = "영원한 불꽃",        color = {1.00, 0.60, 0.28} },
		{ name = "BeaconOfLight",       display = "빛의 봉화",          color = {1.00, 0.93, 0.47} },
		{ name = "BeaconOfVirtue",      display = "미덕의 봉화",        color = {1.00, 0.88, 0.37} },
		{ name = "BeaconOfTheSavior",   display = "구원자의 봉화",      color = {0.93, 0.80, 0.47} },
		{ name = "BlessingOfProtection", display = "보호의 축복",       color = {0.94, 0.82, 0.31}, secret = true },
		{ name = "HolyArmaments",        display = "신성한 무장",       color = {0.81, 0.58, 0.93}, secret = true },
		{ name = "BlessingOfSacrifice",  display = "희생의 축복",       color = {0.94, 0.50, 0.50}, secret = true },
		{ name = "BlessingOfFreedom",    display = "자유의 축복",       color = {0.56, 0.93, 0.56}, secret = true },
		{ name = "Dawnlight",            display = "여명의 빛",         color = {1.00, 0.84, 0.28}, secret = true },
	},
}

-- ============================================================
-- LINKED AURA RULES (추론 규칙)
-- ============================================================
AD.LinkedAuraRules = {
	RestorationDruid = {
		SymbioticRelationship = {
			type = "caster_to_target",
			sourceSpellID = 474754,
			targetSpellIDs = { 474750, 474760 },
		},
	},
}

-- ============================================================
-- INDICATOR TYPE DEFINITIONS
-- ============================================================
AD.INDICATOR_TYPES = {
	{ key = "icon",       label = "아이콘",       placed = true  },
	{ key = "square",     label = "사각형",       placed = true  },
	{ key = "bar",        label = "바",           placed = true  },
	{ key = "border",     label = "테두리",       placed = false },
	{ key = "healthbar",  label = "체력바 색상",  placed = false },
	{ key = "nametext",   label = "이름 색상",    placed = false },
	{ key = "healthtext", label = "HP 색상",      placed = false },
	{ key = "framealpha", label = "프레임 투명도", placed = false },
}

-- Frame-level types only (placed types excluded)
AD.FRAME_LEVEL_TYPES = {}
for _, typeDef in ipairs(AD.INDICATOR_TYPES) do
	if not typeDef.placed then
		AD.FRAME_LEVEL_TYPES[#AD.FRAME_LEVEL_TYPES + 1] = typeDef
	end
end

-- ============================================================
-- DEFAULT VALUES PER INDICATOR TYPE
-- ============================================================
AD.TYPE_DEFAULTS = {
	icon = {
		anchor = "TOPLEFT", offsetX = 0, offsetY = 0,
		size = 20, scale = 1.0, alpha = 1.0,
		borderEnabled = true, borderThickness = 1, borderInset = 1,
		hideSwipe = false, hideIcon = false,
		showDuration = true,
		durationScale = 1.0, durationOutline = "OUTLINE",
		durationAnchor = "CENTER", durationX = 0, durationY = 0,
		durationColorByTime = true,
		showStacks = true, stackMinimum = 2,
		stackScale = 1.0, stackOutline = "OUTLINE",
		stackAnchor = "BOTTOMRIGHT", stackX = 0, stackY = 0,
		expiringEnabled = false, expiringThreshold = 30,
		expiringThresholdMode = "PERCENT",
		expiringColor = { r = 1, g = 0.2, b = 0.2 },
		expiringPulsate = false,
		expiringWholeAlphaPulse = false, expiringBounce = false,
	},
	square = {
		anchor = "TOPLEFT", offsetX = 0, offsetY = 0,
		size = 8, scale = 1.0, alpha = 1.0,
		color = { r = 1, g = 1, b = 1, a = 1 },
		showBorder = true, borderThickness = 1, borderInset = 1,
		hideSwipe = false,
		showDuration = false,
		showStacks = true, stackMinimum = 2,
		expiringEnabled = false, expiringThreshold = 30,
		expiringThresholdMode = "PERCENT",
		expiringColor = { r = 1, g = 0.2, b = 0.2 },
	},
	bar = {
		anchor = "BOTTOM", offsetX = 0, offsetY = 0,
		orientation = "HORIZONTAL", width = 60, height = 4,
		matchFrameWidth = true, matchFrameHeight = false,
		fillColor = { r = 1, g = 1, b = 1, a = 1 },
		bgColor = { r = 0, g = 0, b = 0, a = 0.5 },
		showBorder = true, borderThickness = 1,
		borderColor = { r = 0, g = 0, b = 0, a = 1 },
		alpha = 1.0,
		barColorByTime = false,
		expiringEnabled = false, expiringThreshold = 5,
		expiringColor = { r = 1, g = 0.2, b = 0.2 },
		showDuration = false,
	},
}
