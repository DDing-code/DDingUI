--[[
	ddingUI UnitFrames
	Core/Config.lua - Cell_UnitFrames 수준의 상세 설정 시스템
]]

local _, ns = ...

local Config = {}
ns.Config = Config

-----------------------------------------------
-- Default Option Templates
-----------------------------------------------

-- Position template
local function CreatePositionOpt(point, relativePoint, offsetX, offsetY)
	return {
		point = point or "CENTER",
		relativePoint = relativePoint or "CENTER",
		offsetX = offsetX or 0,
		offsetY = offsetY or 0,
	}
end

-- Font template
local function CreateFontOpt(size, outline, shadow, style, justify)
	return {
		size = size or 12,
		outline = outline or "OUTLINE", -- "NONE", "OUTLINE", "THICKOUTLINE"
		shadow = shadow or false,
		style = style or STANDARD_TEXT_FONT,
		justify = justify or "CENTER", -- "LEFT", "CENTER", "RIGHT"
	}
end

-- Color template
local function CreateColorOpt(r, g, b, colorType)
	return {
		rgb = { r or 1, g or 1, b or 1 },
		type = colorType or "custom", -- "custom", "class_color", "power_color", "reaction_color"
	}
end

-- Size template
local function CreateSizeOpt(width, height)
	return {
		width = width or 20,
		height = height or 20,
	}
end

-- Glow template
local function CreateGlowOpt()
	return {
		type = "none", -- "none", "pixel", "shine", "button", "proc"
		color = { 1, 1, 1, 1 },
		lines = 9,
		frequency = 0.25,
		length = 8,
		thickness = 2,
	}
end

-----------------------------------------------
-- Aura Filter Defaults
-----------------------------------------------

ns.AuraFilters = {
	buffs = {
		blacklist = {},
		whitelist = {
			-- Bloodlust effects
			[2825] = true,   -- Bloodlust
			[32182] = true,  -- Heroism
			[80353] = true,  -- Time Warp
			[90355] = true,  -- Ancient Hysteria
			[390386] = true, -- Fury of the Aspects
			-- External defensives
			[1022] = true,   -- Blessing of Protection
			[1044] = true,   -- Blessing of Freedom
			[6940] = true,   -- Blessing of Sacrifice
			[33206] = true,  -- Pain Suppression
			[47788] = true,  -- Guardian Spirit
			[62618] = true,  -- Power Word: Barrier
			[116849] = true, -- Life Cocoon
			[102342] = true, -- Ironbark
		},
	},
	debuffs = {
		blacklist = {
			[8326] = true,   -- Ghost
			[15007] = true,  -- Ress Sickness
			[25771] = true,  -- Forbearance
			[26013] = true,  -- Deserter
			[57723] = true,  -- Exhaustion
			[57724] = true,  -- Sated
			[80354] = true,  -- Temporal Displacement
			[390435] = true, -- Exhaustion (Evoker)
		},
		whitelist = {},
	}
}

-----------------------------------------------
-- Raid Synergy Buff Spell IDs (레이드 시너지 버프)
-- "레이드 버프 숨기기" 옵션에서 사용
-- Source: DandersFrames RaidBuffs table (12.0.1 verified)
-----------------------------------------------

ns.RaidSynergyBuffs = {
	[1459] = true,    -- Arcane Intellect (신비한 지능)
	[21562] = true,   -- Power Word: Fortitude (신의 권능: 인내)
	[6673] = true,    -- Battle Shout (전투 외침)
	[1126] = true,    -- Mark of the Wild (야생의 징표)
	[462854] = true,  -- Skyfury (하늘의 분노)
	[381748] = true,  -- Blessing of the Bronze (청동의 축복) - buff
	[364342] = true,  -- Blessing of the Bronze (청동의 축복) - ability
}

-- 아이콘 텍스처 기반 캐시 (spellId가 secret일 때 fallback)
-- [FIX] 빈 캐시 재시도: C_Spell.GetSpellTexture가 아직 nil이면 다음 호출에서 재빌드
ns.RaidSynergyBuffIcons = nil -- lazy init

function ns.GetRaidSynergyBuffIcons()
	if ns.RaidSynergyBuffIcons then return ns.RaidSynergyBuffIcons end
	local cache = {}
	for spellId in pairs(ns.RaidSynergyBuffs) do
		local icon
		if C_Spell and C_Spell.GetSpellTexture then
			icon = C_Spell.GetSpellTexture(spellId)
		elseif GetSpellTexture then
			icon = GetSpellTexture(spellId)
		end
		if icon then
			cache[icon] = true
		end
	end
	-- [FIX] 빈 캐시는 저장하지 않음 → 다음 호출에서 재시도
	if next(cache) then
		ns.RaidSynergyBuffIcons = cache
	end
	return cache
end

-- [12.0.1] 생존기 판별: CenterDefensiveBuff API 100% 의존 (DandersFrames 패턴)
-- spellID 화이트리스트 제거 — Blizzard CompactUnitFrame_UpdateAuras가 결정한 생존기만 표시
-- 패치마다 수동 유지보수 불필요

-----------------------------------------------
-- [HOT-TRACKER] HoT Spec Data — HARF 필터 패턴 기반
-- spellID 없이 4-filter + points 조합으로 HoT 식별
-- raid: PLAYER|HELPFUL|RAID 통과
-- ric: PLAYER|HELPFUL|RAID_IN_COMBAT 통과
-- ext: PLAYER|HELPFUL|EXTERNAL_DEFENSIVE 통과
-- disp: PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE 통과
-- points: #aura.points 개수
-----------------------------------------------

local HotSpecData = { -- [12.0.1] HARF Specs.lua 검증 데이터 기반
	RestorationDruid = {
		auras = {
			Rejuvenation = { points = 1, raid = true,  ric = true,  ext = false, disp = true  }, -- 774
			Regrowth     = { points = 3, raid = true,  ric = true,  ext = false, disp = true  }, -- 8936
			Germination  = { points = 1, raid = false, ric = true,  ext = false, disp = true  }, -- 155777
			WildGrowth   = { points = 2, raid = true,  ric = true,  ext = false, disp = true  }, -- 48438
			IronBark     = { points = 2, raid = true,  ric = true,  ext = true,  disp = false }, -- 102342
			-- Lifebloom: points 1~2 가변 → Rejuvenation/WildGrowth과 충돌, cast tracking 필요 (미구현)
		},
	},
	PreservationEvoker = {
		auras = {
			Echo            = { points = 2, raid = true,  ric = true,  ext = false, disp = false }, -- 364343
			Reversion       = { points = 3, raid = true,  ric = true,  ext = false, disp = true  }, -- 366155
			EchoReversion   = { points = 3, raid = false, ric = true,  ext = false, disp = true  }, -- 367364
			DreamBreath     = { points = 3, raid = false, ric = true,  ext = false, disp = false }, -- 355941
			EchoDreamBreath = { points = 4, raid = false, ric = true,  ext = false, disp = false }, -- 376788 (3~4 가변, 4로 고정)
			TimeDilation    = { points = 2, raid = true,  ric = true,  ext = true,  disp = false }, -- 357170
			Rewind          = { points = 4, raid = true,  ric = true,  ext = false, disp = false }, -- 363534
			DreamFlight     = { points = 2, raid = false, ric = true,  ext = false, disp = false }, -- 359816
			VerdantEmbrace  = { points = 1, raid = false, ric = true,  ext = false, disp = false }, -- 360995
			-- Lifebind: points 1~2 가변 → VerdantEmbrace/DreamFlight과 충돌 (미구현)
		},
	},
	HolyPaladin = {
		auras = {
			BeaconOfFaith       = { points = 7, raid = true,  ric = true,  ext = false, disp = false }, -- 156910
			EternalFlame        = { points = 3, raid = true,  ric = true,  ext = false, disp = true  }, -- 156322
			BeaconOfLight       = { points = 6, raid = true,  ric = true,  ext = false, disp = false }, -- 53563
			BlessingOfProtection = { points = 0, raid = true, ric = true,  ext = true,  disp = true  }, -- 1022
			HolyBulwark         = { points = 6, raid = false, ric = true,  ext = false, disp = false }, -- 5~6 가변, 6으로 고정
			SacredWeapon        = { points = 5, raid = false, ric = true,  ext = false, disp = false },
			BlessingOfSacrifice = { points = 9, raid = true,  ric = true,  ext = true,  disp = false }, -- 6940
			BeaconOfVirtue      = { points = 4, raid = true,  ric = false, ext = false, disp = false }, -- 200025
			BeaconOfTheSavior   = { points = 7, raid = false, ric = true,  ext = false, disp = false },
		},
	},
	HolyPriest = {
		auras = {
			Renew           = { points = 2, raid = false, ric = true,  ext = false, disp = true  },
			EchoOfLight     = { points = 1, raid = false, ric = true,  ext = false, disp = false }, -- 77489
			GuardianSpirit  = { points = 3, raid = true,  ric = true,  ext = true,  disp = false }, -- 47788
			PrayerOfMending = { points = 1, raid = false, ric = true,  ext = false, disp = true  },
			PowerInfusion   = { points = 2, raid = true,  ric = false, ext = false, disp = true  }, -- 10060
		},
	},
	DisciplinePriest = {
		auras = {
			PowerWordShield = { points = 2, raid = true,  ric = true,  ext = false, disp = true  },
			Atonement       = { points = 0, raid = false, ric = true,  ext = false, disp = false }, -- 194384
			PainSuppression = { points = 0, raid = true,  ric = true,  ext = true,  disp = false }, -- 33206
			VoidShield      = { points = 3, raid = false, ric = true,  ext = false, disp = true  },
			PrayerOfMending = { points = 1, raid = false, ric = true,  ext = false, disp = true  },
			PowerInfusion   = { points = 2, raid = true,  ric = false, ext = false, disp = true  },
		},
	},
	MistweaverMonk = {
		auras = {
			RenewingMist         = { points = 2, raid = false, ric = true,  ext = false, disp = true  },
			EnvelopingMist       = { points = 3, raid = true,  ric = true,  ext = false, disp = true  },
			SoothingMist         = { points = 3, raid = true,  ric = true,  ext = false, disp = false },
			LifeCocoon           = { points = 3, raid = true,  ric = true,  ext = true,  disp = false },
			AspectOfHarmony      = { points = 2, raid = false, ric = true,  ext = false, disp = false },
			StrengthOfTheBlackOx = { points = 3, raid = false, ric = true,  ext = false, disp = true  },
		},
	},
	RestorationShaman = {
		auras = {
			Riptide     = { points = 2, raid = true,  ric = true,  ext = false, disp = true  },
			EarthShield = { points = 3, raid = false, ric = true,  ext = false, disp = true  },
		},
	},
}
ns.HotSpecData = HotSpecData

-- specID → specKey 매핑
local HotSpecMap = {
	[105]  = "RestorationDruid",
	[1468] = "PreservationEvoker",
	[65]   = "HolyPaladin",
	[257]  = "HolyPriest",
	[256]  = "DisciplinePriest",
	[270]  = "MistweaverMonk",
	[264]  = "RestorationShaman",
}
ns.HotSpecMap = HotSpecMap

-----------------------------------------------
-- Widget Defaults
-----------------------------------------------

local WidgetDefaults = {}
ns.WidgetDefaults = WidgetDefaults

-- Name Text Widget
WidgetDefaults.nameText = {
	enabled = true,
	frameLevel = 10,
	font = CreateFontOpt(12, "OUTLINE", false, nil, "LEFT"),
	color = CreateColorOpt(1, 1, 1, "class_color"),
	width = {
		value = 0,
		type = "unlimited", -- "percentage", "length", "unlimited"
		auxValue = 0,
	},
	position = CreatePositionOpt("TOPLEFT", "CENTER", 2, 8),
	format = "name", -- "name", "name:abbrev", "name:short"
	showLevel = false, -- [FIX] 이름 앞에 레벨 표시 여부
	tag = "", -- [12.0.1] oUF 태그 문자열 (빈 값이면 유닛별 기본값 사용)
}

-- Health Text Widget
WidgetDefaults.healthText = {
	enabled = true,
	frameLevel = 10,
	font = CreateFontOpt(11, "OUTLINE", false, nil, "RIGHT"),
	color = CreateColorOpt(1, 1, 1, "custom"),
	format = "percentage", -- "percentage", "current", "current-max", "deficit", "current-percentage", "custom"
	separator = "/", -- [UF-OPTIONS] 복합 포맷 구분자: "/", "|", "-", "·"
	textFormat = "", -- Custom format string
	tag = "", -- [12.0.1] oUF 태그 문자열 (빈 값이면 유닛별 기본값 사용)
	hideIfFull = false,
	hideIfEmpty = false,
	showDeadStatus = true,
	position = CreatePositionOpt("RIGHT", "CENTER", 0, 0),
}

-- Power Text Widget
WidgetDefaults.powerText = {
	enabled = false,
	frameLevel = 10,
	font = CreateFontOpt(10, "OUTLINE", false, nil, "RIGHT"),
	color = CreateColorOpt(1, 1, 1, "power_color"),
	format = "percentage", -- "percentage", "current", "current-max", "deficit", "smart", "current-percentage", "percent-current", "current-percent"
	textFormat = "",
	hideIfEmptyOrFull = false,
	anchorToPowerBar = false,
	powerFilter = false,
	position = CreatePositionOpt("BOTTOMRIGHT", "CENTER", 0, 0),
}

-- Status Text Widget (Dead/Offline/AFK — party/raid)
WidgetDefaults.statusText = {
	enabled = true,
	frameLevel = 11,
	font = CreateFontOpt(11, "OUTLINE", true, nil, "CENTER"),
	color = CreateColorOpt(0.8, 0.8, 0.8, "custom"),
	position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
	shadow = true,
	tag = "[ddingui:status]",
}

-- Level Text Widget
WidgetDefaults.levelText = {
	enabled = false,
	frameLevel = 10,
	font = CreateFontOpt(10, "OUTLINE", false, nil, "CENTER"),
	color = CreateColorOpt(1, 1, 1, "custom"),
	position = CreatePositionOpt("TOPLEFT", "CENTER", 0, 8),
}

-- Custom Text Widgets (5 slots)
WidgetDefaults.customText = {
	enabled = false,
	frameLevel = 11,
	texts = {
		text1 = {
			enabled = false,
			textFormat = "",
			color = CreateColorOpt(1, 1, 1, "custom"),
			font = CreateFontOpt(12, "OUTLINE", false, nil, "CENTER"),
			position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
		},
		text2 = {
			enabled = false,
			textFormat = "",
			color = CreateColorOpt(1, 1, 1, "custom"),
			font = CreateFontOpt(12, "OUTLINE", false, nil, "CENTER"),
			position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
		},
		text3 = {
			enabled = false,
			textFormat = "",
			color = CreateColorOpt(1, 1, 1, "custom"),
			font = CreateFontOpt(12, "OUTLINE", false, nil, "CENTER"),
			position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
		},
	},
}

-- Buff Widget
-- [AURA-FILTER] Buff Widget — secret-safe 필터 (12.0.1)
-- non-secret 필드만 사용: isFromPlayerOrPlayerPet, isBossAura, isRaid, dispelName
WidgetDefaults.buffs = {
	enabled = true,
	frameLevel = 10,
	scale = 1.0, -- [12.0.1] 확대 비율 (0.5~2.0)
	orientation = "LEFT_TO_RIGHT", -- [하위호환]
	growDirection = "RIGHT",
	columnGrowDirection = "UP",
	showStack = true,
	showDuration = true,
	showAnimation = true,
	showTooltip = true,
	hideInCombat = false,
	clickThrough = false,
	numPerLine = 5,
	maxIcons = 10,
	spacing = {
		horizontal = 2,
		vertical = 2,
	},
	font = {
		stacks = {
			size = 10,
			outline = "OUTLINE",
			shadow = false,
			style = STANDARD_TEXT_FONT,
			point = "BOTTOMRIGHT",
			relativePoint = "BOTTOMRIGHT",
			offsetX = 2,
			offsetY = -1,
			rgb = { 1, 1, 1 },
		},
		duration = {
			size = 10,
			outline = "OUTLINE",
			shadow = false,
			style = STANDARD_TEXT_FONT,
			point = "CENTER",
			relativePoint = "CENTER",
			offsetX = 0,
			offsetY = 0,
			rgb = { 1, 1, 1 },
			colorMode = "fixed", -- [12.0.1] "fixed" | "gradient" | "threshold"
		},
	},
	durationColors = { -- [12.0.1] gradient 모드 색상 (remaining/total 비율 기반)
		high = { 1, 1, 1 },       -- >50% 남음
		medium = { 1, 1, 0 },     -- 25-50% 남음
		low = { 1, 0.5, 0 },      -- 10-25% 남음
		expiring = { 1, 0, 0 },   -- <10% 남음
		-- [FIX] threshold 모드: 절대 시간(초) 기준 색상 (낮은 값부터 매칭)
		thresholds = {
			{ time = 3, rgb = { 1, 0, 0 } },      -- 3초 미만: 빨강
			{ time = 5, rgb = { 1, 0.5, 0 } },    -- 5초 미만: 주황
			{ time = 10, rgb = { 1, 1, 0 } },     -- 10초 미만: 노랑
		},
	},
	size = CreateSizeOpt(24, 24),
	filter = {
		-- [AURA-FILTER] secret-safe 필터 (non-secret 필드만)
		onlyMine = false,        -- 내가 건 버프만 (isFromPlayerOrPlayerPet)
		showBossAura = true,     -- 보스 버프 항상 표시 (isBossAura)
		showRaid = false,        -- 블리자드 지정 레이드 버프 (isRaid)
		useBlizzardFilter = true, -- 블리자드 파티프레임 필터 (SpellGetVisibilityInfo) [DandersFrames 동일]
		maxDuration = 0,         -- 최대 지속시간 필터 (0=무제한, secret guard 필요)
		hideNoDuration = false,  -- 지속시간 없는 것 숨기기
		hideRaidBuffs = false,   -- [FIX] 레이드 시너지 버프 숨기기 (인내, 전투 외침 등)
		-- [12.0.1] HoT 목록 기반 화이트리스트 (패턴 매칭 결과 재활용)
		useHotWhitelist = false,
	},
	position = CreatePositionOpt("BOTTOMLEFT", "TOPLEFT", 0, 2),
}

-- [AURA-FILTER] Debuff Widget — secret-safe 필터 (12.0.1)
WidgetDefaults.debuffs = {
	enabled = true,
	frameLevel = 10,
	scale = 1.0, -- [12.0.1] 확대 비율 (0.5~2.0)
	orientation = "RIGHT_TO_LEFT", -- [하위호환]
	growDirection = "LEFT",
	columnGrowDirection = "UP",
	showStack = true,
	showDuration = true,
	showAnimation = true,
	showTooltip = true,
	hideInCombat = false,
	clickThrough = false,
	numPerLine = 4,
	maxIcons = 8,
	spacing = {
		horizontal = 2,
		vertical = 2,
	},
	font = {
		stacks = {
			size = 10,
			outline = "OUTLINE",
			shadow = false,
			style = STANDARD_TEXT_FONT,
			point = "BOTTOMRIGHT",
			relativePoint = "BOTTOMRIGHT",
			offsetX = 2,
			offsetY = -1,
			rgb = { 1, 1, 1 },
		},
		duration = {
			size = 10,
			outline = "OUTLINE",
			shadow = false,
			style = STANDARD_TEXT_FONT,
			point = "CENTER",
			relativePoint = "CENTER",
			offsetX = 0,
			offsetY = 0,
			rgb = { 1, 1, 1 },
			colorMode = "fixed", -- [12.0.1] "fixed" | "gradient" | "threshold"
		},
	},
	durationColors = { -- [12.0.1] gradient 모드 색상
		high = { 1, 1, 1 },
		medium = { 1, 1, 0 },
		low = { 1, 0.5, 0 },
		expiring = { 1, 0, 0 },
		thresholds = {
			{ time = 3, rgb = { 1, 0, 0 } },
			{ time = 5, rgb = { 1, 0.5, 0 } },
			{ time = 10, rgb = { 1, 1, 0 } },
		},
	},
	size = CreateSizeOpt(28, 28),
	border = {
		colorByType = true,
		colors = {
			none = { 0, 0, 0, 1 },
			magic = { 0.2, 0.6, 1, 1 },
			curse = { 0.6, 0, 1, 1 },
			disease = { 0.6, 0.4, 0, 1 },
			poison = { 0, 0.6, 0, 1 },
			bleed = { 1, 0, 0, 1 },
		},
	},
	filter = {
		-- [AURA-FILTER] secret-safe 필터 (non-secret 필드만)
		onlyDispellable = false, -- 해제 가능한 것만 (dispelName)
		showBossAura = true,     -- 보스 디버프 항상 표시 (isBossAura)
		showRaid = true,         -- 블리자드 지정 레이드 디버프 (isRaid)
		onlyMine = false,        -- 내 디버프만 (isFromPlayerOrPlayerPet)
		showAll = false,         -- 전부 표시 (다른 필터 무시)
		maxDuration = 0,         -- 최대 지속시간 (0=무제한)
		hideNoDuration = false,  -- 지속시간 없는 것 숨기기
		-- [AURA-FILTER] per-unit 화이트/블랙리스트 (spellId 기반, secret guard)
	},
	position = CreatePositionOpt("BOTTOMRIGHT", "TOPRIGHT", 0, 2),
}

-- [AURA-FILTER] Defensives Widget — 생존기/외생기 전용 카테고리
-- spellId 비교 필요 → issecretvalue 가드 포함
WidgetDefaults.defensives = {
	enabled = true,          -- [FIX] 기본 활성 (DandersFrames 동일)
	frameLevel = 10,
	scale = 1.0, -- [12.0.1] 확대 비율 (0.5~2.0)
	showAnimation = false, -- [12.0.1] 버프 팝업 애니메이션
	hideInCombat = false, -- [12.0.1] 전투 중 숨기기
	growDirection = "RIGHT",
	columnGrowDirection = "UP",
	showStack = false,
	showDuration = true,
	showTooltip = true,
	clickThrough = false,
	numPerLine = 4,
	maxIcons = 4,
	spacing = {
		horizontal = 2,
		vertical = 2,
	},
	font = { -- [12.0.1] 생존기 아이콘 폰트 설정
		duration = {
			size = 9,
			outline = "OUTLINE",
			shadow = false,
			style = STANDARD_TEXT_FONT,
			point = "CENTER",
			relativePoint = "CENTER",
			offsetX = 0,
			offsetY = 0,
			rgb = { 1, 1, 1 },
			colorMode = "fixed", -- "fixed" | "gradient"
		},
		stacks = {
			size = 9,
			outline = "OUTLINE",
			shadow = false,
			style = STANDARD_TEXT_FONT,
			point = "BOTTOMRIGHT",
			relativePoint = "BOTTOMRIGHT",
			offsetX = 2,
			offsetY = -1,
			rgb = { 1, 1, 1 },
		},
	},
	durationColors = { -- [12.0.1] gradient 모드 색상
		high = { 1, 1, 1 },
		medium = { 1, 1, 0 },
		low = { 1, 0.5, 0 },
		expiring = { 1, 0, 0 },
	},
	size = CreateSizeOpt(20, 20),
	showDefensives = true,   -- 개인 생존기 표시
	showExternals = true,    -- 외부 생존기 표시
	onlyMine = false,        -- 내가 건 것만 (isFromPlayerOrPlayerPet)
	position = CreatePositionOpt("CENTER", "CENTER", 0, 0), -- [12.0.1] 프레임 중앙 (DandersFrames 패턴)
}

-- [REFACTOR] PrivateAuras Widget — per-unit 설정 (글로벌 ns.db.privateAuras에서 이전)
-- [12.0.1] 구조 통일: iconSize → size, spacing 숫자 → 테이블, scale/position/numPerLine 추가
WidgetDefaults.privateAuras = {
	enabled = true,
	scale = 1.0, -- [12.0.1] 확대 비율 (0.5~2.0)
	maxAuras = 2,
	growDirection = "RIGHT",
	columnGrowDirection = "DOWN",
	numPerLine = 5,
	size = CreateSizeOpt(24, 24),
	spacing = {
		horizontal = 2,
		vertical = 2,
	},
	position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
}

-- [HOT-TRACKER] per-aura 표시 유형 기본값
-- auraSettings에 미설정된 aura는 이 기본값을 사용
local AURA_DISPLAY_DEFAULTS = {
	enabled = true,
	bar      = { enabled = false, thickness = 3, color = { 0.3, 0.85, 0.45, 0.8 } },
	gradient = { enabled = false, color = { 0.3, 0.85, 0.45 }, alpha = 0.4 },
	healthColor = { enabled = false, color = { 0.2, 0.8, 0.3, 1 } },
	outline  = { enabled = false, size = 2, color = { 0.3, 0.85, 0.45, 1 } },
}
ns.AURA_DISPLAY_DEFAULTS = AURA_DISPLAY_DEFAULTS

-- [HOT-TRACKER] HoT Tracker Widget — 힐러 HoT 추적 인디케이터
-- per-aura 설정: auraSettings["SpecKey.AuraName"] = { bar={...}, text={...}, ... }
WidgetDefaults.hotTracker = {
	enabled = false, -- 기본 비활성 (힐러만 사용)
	maxIndicators = 5,
	size = CreateSizeOpt(14, 14),
	spacing = 2,
	position = CreatePositionOpt("BOTTOM", "BOTTOM", 0, 2),
	growDirection = "RIGHT", -- RIGHT/LEFT/UP/DOWN
	auraSettings = {}, -- ["RestorationDruid.Rejuvenation"] = { enabled=true, bar={...}, ... }
}

-- Dispels Widget -- [12.0.1] 5종 하이라이트 + 아이콘 + 글로우 + 미리보기
WidgetDefaults.dispels = {
	enabled = true,
	frameLevel = 10,
	highlightType = "entire", -- "entire", "current", "current+", "gradient", "gradient-half" -- [12.0.1]
	onlyShowDispellable = true,
	curse = true,
	disease = true,
	magic = true,
	poison = true,
	bleed = false,
	enrage = false,
	iconStyle = "none", -- "none", "icon" -- [12.0.1]
	iconSize = 14,                        -- [12.0.1]
	iconPosition = CreatePositionOpt("BOTTOMRIGHT", "BOTTOMRIGHT", -4, 4), -- [12.0.1]
	size = 12,
	position = CreatePositionOpt("BOTTOMRIGHT", "BOTTOMRIGHT", -4, 4),
	glow = CreateGlowOpt(),               -- [12.0.1] pixel/shine/proc/normal
}

-- Raid Icon Widget
WidgetDefaults.raidIcon = {
	enabled = true,
	frameLevel = 10,
	size = CreateSizeOpt(16, 16),
	position = CreatePositionOpt("TOP", "CENTER", 0, 12),
}

-- Role Icon Widget
WidgetDefaults.roleIcon = {
	enabled = true,
	showTank = true,
	showHealer = true,
	showDPS = true,
	frameLevel = 10,
	size = CreateSizeOpt(14, 14),
	position = CreatePositionOpt("TOPRIGHT", "CENTER", 0, 0),
}

-- Leader Icon Widget
WidgetDefaults.leaderIcon = {
	enabled = true,
	frameLevel = 10,
	size = CreateSizeOpt(14, 14),
	position = CreatePositionOpt("TOPLEFT", "CENTER", 0, 12),
}

-- Combat Icon Widget
WidgetDefaults.combatIcon = {
	enabled = false,
	frameLevel = 10,
	size = CreateSizeOpt(20, 20),
	position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
}

-- Ready Check Icon Widget
WidgetDefaults.readyCheckIcon = {
	enabled = true,
	frameLevel = 10,
	size = CreateSizeOpt(20, 20),
	position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
}

-- Resting Icon Widget
WidgetDefaults.restingIcon = {
	enabled = false,
	frameLevel = 10,
	hideAtMaxLevel = true,
	size = CreateSizeOpt(18, 18),
	position = CreatePositionOpt("TOPLEFT", "CENTER", -15, 10),
}

-- Resurrect Icon Widget
WidgetDefaults.resurrectIcon = {
	enabled = true,
	frameLevel = 10,
	size = CreateSizeOpt(20, 20),
	position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
}

-- Summon Icon Widget
WidgetDefaults.summonIcon = {
	enabled = true,
	frameLevel = 10,
	size = CreateSizeOpt(20, 20),
	position = CreatePositionOpt("CENTER", "CENTER", 0, 0),
}

-- Shield Bar Widget (Absorb)
WidgetDefaults.shieldBar = {
	enabled = true,
	frameLevel = 9,
	point = "RIGHT",
	reverseFill = false,
	overShield = true,
	texture = [[Interface\Buttons\WHITE8x8]],
	color = { 1, 1, 0, 0.4 },
	overshieldColor = { 1, 1, 1, 0.8 },
}

-- Cast Bar Widget
WidgetDefaults.castBar = {
	enabled = true,
	frameLevel = 10,
	useClassColor = false,
	onlyShowInterrupt = false,
	anchorToParent = true,
	timeToHold = 0.5,
	interruptedLabel = "중단됨",
	showInterruptedSpell = true,
	orientation = "LEFT_TO_RIGHT",
	fadeInTimer = 0.1,
	fadeOutTimer = 0.3,
	texture = [[Interface\Buttons\WHITE8x8]],
	position = CreatePositionOpt("TOPLEFT", "BOTTOMLEFT", 0, -5),
	detachedPosition = CreatePositionOpt("CENTER", "CENTER", 0, 0),
	size = CreateSizeOpt(200, 20),
	timer = {
		enabled = true,
		format = "remaining", -- "remaining", "remaining/total", "total"
		size = 11,
		outline = "OUTLINE",
		shadow = true,
		style = STANDARD_TEXT_FONT,
		point = "RIGHT",
		relativePoint = "RIGHT",
		offsetY = 0,
		offsetX = -3,
		rgb = { 1, 1, 1 },
	},
	spell = {
		enabled = true,
		size = 11,
		outline = "OUTLINE",
		shadow = true,
		style = STANDARD_TEXT_FONT,
		point = "LEFT",
		relativePoint = "LEFT",
		offsetY = 0,
		offsetX = 3,
		rgb = { 1, 1, 1 },
	},
	showSpell = true,
	showTarget = false,
	targetSeparator = "->",
	spark = {
		enabled = true,
		width = 2,
		color = { 1, 1, 1, 1 },
	},
	border = {
		showBorder = true,
		size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
		color = { 0, 0, 0, 1 },
	},
	icon = {
		enabled = true,
		position = "inside-left", -- "left", "right", "inside-left", "inside-right", "none"
		zoom = 0,
	},
	colors = {
		interruptible = { 0.2, 0.57, 0.5, 1 },
		nonInterruptible = { 0.43, 0.43, 0.43, 1 },
		background = { 0, 0, 0, 0.8 },
		backgroundTexture = [[Interface\Buttons\WHITE8x8]],
	},
}

-- Class Bar Widget (Class Power)
WidgetDefaults.classBar = {
	enabled = true,
	frameLevel = 10,
	spacing = 2,
	verticalFill = false,
	sameSizeAsHealthBar = true,
	hideOutOfCombat = false,
	size = CreateSizeOpt(200, 6),
	position = CreatePositionOpt("BOTTOMLEFT", "TOPLEFT", 0, 2),
	texture = [[Interface\Buttons\WHITE8x8]],
	border = { enabled = true, size = 1, color = { 0, 0, 0, 1 } },
	background = { enabled = true, color = { 0.05, 0.05, 0.05, 0.8 }, texture = [[Interface\Buttons\WHITE8x8]] },
}

-- Alt Power Bar Widget
WidgetDefaults.altPowerBar = {
	enabled = false,
	frameLevel = 10,
	sameSizeAsHealthBar = true,
	hideIfEmpty = true,
	hideIfFull = false,
	hideOutOfCombat = false,
	size = CreateSizeOpt(200, 4),
	position = CreatePositionOpt("TOPLEFT", "TOPLEFT", 0, 0),
	texture = [[Interface\Buttons\WHITE8x8]],
	background = { color = { 0.08, 0.08, 0.08, 0.85 }, texture = [[Interface\Buttons\WHITE8x8]] },
}

-- Power Bar Widget
WidgetDefaults.powerBar = {
	enabled = true,
	frameLevel = 15,
	powerFilter = false,
	hideIfEmpty = false,
	hideIfFull = false,
	hideOutOfCombat = false,
	colorPower = true,
	orientation = "LEFT_TO_RIGHT",
	size = CreateSizeOpt(200, 4),
	sameWidthAsHealthBar = true,
	sameHeightAsHealthBar = false,
	position = CreatePositionOpt("BOTTOMLEFT", "BOTTOMLEFT", 0, 0),
	anchorToParent = true,
	detachedPosition = CreatePositionOpt("BOTTOMLEFT", "BOTTOMLEFT", 0, 0),
	texture = [[Interface\Buttons\WHITE8x8]],
	background = { color = { 0, 0, 0, 0.7 }, texture = [[Interface\Buttons\WHITE8x8]] },
}

-- Heal Prediction Widget
WidgetDefaults.healPrediction = {
	enabled = true,
	frameLevel = 9,
	point = "healthBar",
	reverseFill = false,
	overHeal = false,
	texture = [[Interface\Buttons\WHITE8x8]],
	color = { 0, 1, 0.5, 0.4 },
	overHealColor = { 1, 1, 1, 0.3 },
}

-- Heal Absorb Widget
WidgetDefaults.healAbsorb = {
	enabled = true,
	frameLevel = 10,
	texture = [[Interface\Buttons\WHITE8x8]],
	color = { 1, 0.1, 0.1, 0.5 },
	anchorPoint = "LEFT",
}

-- Fader Widget
WidgetDefaults.fader = {
	enabled = false,
	range = true,
	combat = false,
	hover = false,
	target = false,
	unitTarget = false,
	fadeDuration = 0.25,
	maxAlpha = 1,
	minAlpha = 0.35,
}

-- Highlight Widget -- [12.0.1] Target/Focus/Hover 보더
WidgetDefaults.highlight = {
	enabled = true,
	hover = true,
	target = true,
	focus = true,                    -- [12.0.1]
	size = 1,
	targetColor = { 1, 0.3, 0.3, 1 },
	focusColor = { 0.3, 0.6, 1, 1 }, -- [12.0.1]
	hoverColor = { 1, 1, 1, 0.3 },
}

-- Debuff Highlight Widget (그룹 프레임용)
WidgetDefaults.debuffHighlight = {
	enabled = true,
	borderSize = 0,
	overlayAlpha = 0.25,
	showNonDispellable = true, -- 해제 불가 디버프(출혈/격노)도 표시할지
	-- [FIX] 그라디언트 오버레이 옵션 (DandersFrames 패턴)
	overlayMode = "gradient",      -- "solid" (기존 단색 오버레이) | "gradient" (가장자리→중앙 페이드)
	gradientStyle = "TOP",         -- "EDGE" (4면) | "TOP" | "BOTTOM" | "TOP_BOTTOM" (위아래) | "FULL"
	gradientSize = 0.35,        -- 그라디언트 크기 (프레임 대비 비율, 0.1~1.0)
	gradientBlendMode = "ADD",  -- "ADD" (발광) | "BLEND" (반투명)
}

-- Threat Widget
WidgetDefaults.threat = {
	enabled = true,
	frameLevel = 5,
	style = "border", -- "border", "glow"
	borderSize = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
	colors = {
		[0] = { 0.5, 0.5, 0.5, 0 },    -- 없음
		[1] = { 1, 1, 0.47, 1 },        -- 높은 위협
		[2] = { 1, 0.6, 0, 1 },         -- 최고 위협
		[3] = { 1, 0, 0, 1 },           -- 탱킹 중
	},
}

-----------------------------------------------
-- Global Colors
-----------------------------------------------

ns.Colors = {
	-- Cast Bar Colors
	castBar = {
		texture = [[Interface\Buttons\WHITE8x8]],
		interruptible = { 0.2, 0.57, 0.5, 1 },
		nonInterruptible = { 0.43, 0.43, 0.43, 1 },
		background = { 0, 0, 0, 0.8 },
	},
	-- Reaction Colors
	reaction = {
		friendly = { 0.29, 0.69, 0.3, 1 },
		hostile = { 0.78, 0.25, 0.25, 1 },
		neutral = { 0.85, 0.77, 0.36, 1 },
		pet = { 0.29, 0.69, 0.3, 1 },
		useClassColorForPet = false,
		tapped = { 0.5, 0.5, 0.5, 1 },
	},
	-- Class Resources
	classResources = {
		holyPower = { 0.9, 0.89, 0.04, 1 },
		arcaneCharges = { 0, 0.62, 1, 1 },
		soulShards = { 0.58, 0.51, 0.8, 1 },
	},
	-- Combo Points
	comboPoints = {
		[1] = { 0.76, 0.3, 0.3, 1 },
		[2] = { 0.79, 0.56, 0.3, 1 },
		[3] = { 0.82, 0.82, 0.3, 1 },
		[4] = { 0.56, 0.79, 0.3, 1 },
		[5] = { 0.43, 0.77, 0.3, 1 },
		[6] = { 0.3, 0.76, 0.3, 1 },
		[7] = { 0.36, 0.82, 0.54, 1 },
		charged = { 0.15, 0.64, 1, 1 },
	},
	-- Chi
	chi = {
		[1] = { 0.72, 0.77, 0.31, 1 },
		[2] = { 0.58, 0.74, 0.36, 1 },
		[3] = { 0.49, 0.72, 0.38, 1 },
		[4] = { 0.38, 0.7, 0.42, 1 },
		[5] = { 0.26, 0.67, 0.46, 1 },
		[6] = { 0.13, 0.64, 0.5, 1 },
	},
	-- Runes
	runes = {
		blood = { 1.0, 0.24, 0.24, 1 },
		frost = { 0.24, 1.0, 1.0, 1 },
		unholy = { 0.24, 1.0, 0.24, 1 },
	},
	-- Essence (Evoker)
	essence = {
		[1] = { 0.2, 0.57, 0.5, 1 },
		[2] = { 0.2, 0.57, 0.5, 1 },
		[3] = { 0.2, 0.57, 0.5, 1 },
		[4] = { 0.2, 0.57, 0.5, 1 },
		[5] = { 0.2, 0.57, 0.5, 1 },
		[6] = { 0.2, 0.57, 0.5, 1 },
	},
	-- Shield Bar
	shieldBar = {
		texture = [[Interface\Buttons\WHITE8x8]],
		shieldColor = { 1, 1, 0, 0.4 },
		overshieldColor = { 1, 1, 1, 0.8 },
	},
	-- Heal Prediction
	healPrediction = {
		texture = [[Interface\Buttons\WHITE8x8]],
		color = { 0, 1, 0.5, 0.4 },
		overHealColor = { 1, 1, 1, 0.3 },
	},
	-- Heal Absorb
	healAbsorb = {
		texture = [[Interface\Buttons\WHITE8x8]],
		color = { 1, 0.1, 0.1, 0.5 },
	},
	-- Unit Frames
	unitFrames = {
		barColor = { 0.06, 0.07, 0.07, 1 },
		lossColor = { 0.52, 0.21, 0.19, 1 },
		fullColor = { 0.2, 0.2, 1, 1 },
		deathColor = { 0.47, 0.47, 0.47, 1 },
		offlineColor = { 0.5, 0.5, 0.5, 1 }, -- [UF-OPTIONS] 오프라인 색상
		useFullColor = false,
		useDeathColor = true,
		barAlpha = 1,
		lossAlpha = 1,
		backgroundAlpha = 0.85,
		powerBarAlpha = 1,
		powerLossAlpha = 1,
	},
	-- Highlight -- [12.0.1] Focus 색상 추가
	highlight = {
		target = { 1, 0.3, 0.3, 1 },
		focus = { 0.3, 0.6, 1, 1 },
		hover = { 1, 1, 1, 0.3 },
	},
}

-----------------------------------------------
-- Default Settings
-----------------------------------------------

-- [PERF] 키는 항상 string/number이므로 재귀 불필요
-- 리프 값 fast path: type 체크만으로 함수 호출 절감
local function CopyDeep(src)
	if type(src) ~= "table" then return src end
	local dst = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDeep(v)
		else
			dst[k] = v
		end
	end
	return dst
end

-- [PERF] ns.defaults 구축을 함수로 래핑
-- 파일 파싱 시점에 60+ CopyDeep 호출 제거 → Config:Initialize()에서 호출
local function BuildDefaults()
	local defaults = {
	debug = false,
	locked = true,
	hideBlizzard = true,
	minimapAngle = 225,
	minimap = { hide = false }, -- [12.0.1] LibDBIcon 미니맵 버튼
	testMode = false,
	iconSet = "default", -- [REFACTOR] 전역 아이콘 세트 ("default", "ddingui")

	-- Core Systems (Tier 1)
	smoothBars = true,
	pixelPerfect = true,

	-- Health Gradient
	healthGradient = {
		enabled = false,
		colors = { 1, 0, 0, 1, 1, 0, 0, 1, 0 },
	},

	-- Threat on health bar
	aggroOnHealthBar = false,

	-- Appearance
	appearance = {
		oorAlpha = 0.4,
		deadAlpha = 0.6,
		offlineAlpha = 0.5,
		deadDesaturate = true,
		offlineDesaturate = true,
	},

	-- Modules
	clickCasting = {
		enabled = false,
		bindings = {},
	},

	-- [12.0.1] Mover / Edit Mode
	mover = {
		gridEnabled = false,     -- 그리드 오버레이 기본 OFF
		gridSnap = false,        -- 그리드 스냅 기본 OFF
		gridSize = 10,
		frameSnap = true,        -- 프레임간 스냅 기본 ON
		snapThreshold = 15,      -- [MOVER-FIX] 스냅 감지 거리 (px), ElvUI 기본값 15
		nudgeStep = 1,           -- 넛지 이동 단위 (px)
		previewRaidCount = 20,   -- [EDITMODE] 레이드 미리보기 인원수 (10~40, step 5)
	},

	-- [MOVER] 무버 위치 저장 네임스페이스 (ElvUI 형식: "POINT,UIParent,POINT,x,y")
	movers = {},

	targetedSpells = {
		enabled = false,
		color = { 1, 0.2, 0.1, 0.3 },
		spellList = {}, -- empty = all enemy casts
	},

	myBuffIndicators = {
		enabled = false,
		maxIndicators = 3,
		barHeight = 3,
		spacing = 1,
		position = "BOTTOM", -- "BOTTOM" or "TOP"
		defaultColor = nil, -- nil = class color
		trackedSpells = {}, -- empty = all my buffs
	},

	privateAuras = {
		enabled = true,
		iconSize = 24,
		maxAuras = 2,
		spacing = 2,
		growDirection = "RIGHT",
	},

	dispelHighlight = {
		enabled = true,
		onlyShowDispellable = true,
		mode = "border",           -- [12.0.1] "border", "glow", "gradient", "icon"
		glowType = "pixel",        -- [12.0.1] "pixel", "shine", "proc" (LibCustomGlow 타입)
		glowThickness = 2,         -- [12.0.1] 글로우 두께
		gradientAlpha = 0.4,       -- [12.0.1] 그라데이션 투명도
		iconSize = 14,             -- [12.0.1] 아이콘 크기
		iconPosition = "TOPRIGHT", -- [12.0.1] 아이콘 위치
		-- colors = { Magic = {r,g,b}, Curse = {r,g,b}, ... }, -- [FIX] nil이면 기본 색상 사용
	},

	-- Global Fading (legacy, appearance로 이전 예정)
	outOfRangeAlpha = 0.4,
	deadAlpha = 0.6,
	offlineAlpha = 0.6,

	-- Global Colors
	colors = {
		border = { 0, 0, 0, 1 },
		background = { 0.08, 0.08, 0.08, 0.85 },
		healthBg = { 0.1, 0.1, 0.1, 0.8 },
	},

	-- Global Media
	media = {
		texture = [[Interface\Buttons\WHITE8x8]],
		textureName = "", -- LSM 표시이름 (임포트 시 저장)
		font = STANDARD_TEXT_FONT,
		fontName = "", -- LSM 표시이름 (임포트 시 저장)
		fontSize = 11,
		fontFlags = "OUTLINE",
	},

	-- 숫자 표시 형식 (ElvUI numberPrefixStyle 패턴)
	-- "WESTERN": K, M, B, T (서양식)
	-- "KOREAN": 만, 억, 조 (동양식)
	numberFormat = "KOREAN",
	decimalLength = 1, -- 소수점 자릿수 (0~2)

	-----------------------------------------------
	-- Player Frame
	-----------------------------------------------
	player = {
		enabled = true,
		size = { 220, 40 },
		position = { -260, 200 },
		anchorPoint = "BOTTOM",
		selfPoint = "BOTTOM",
		attachTo = "UIParent",
		clickCast = false,
		barOrientation = "horizontal",

		-- Appearance
		healthBarColorType = "class", -- "class", "reaction", "smooth", "custom"
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },
		reverseHealthFill = false,
		healthBarTexture = [[Interface\Buttons\WHITE8x8]],
		useHealthBarTexture = false,
		powerBarTexture = [[Interface\Buttons\WHITE8x8]],
		usePowerBarTexture = false,

		-- Border
		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		-- Background
		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		-- Widgets
		widgets = CopyDeep(WidgetDefaults),

		-- Widget Overrides for Player
		-- (이 유닛 특화 설정은 기본값을 덮어씀)
	},

	-----------------------------------------------
	-- Target Frame
	-----------------------------------------------
	target = {
		enabled = true,
		size = { 220, 40 },
		position = { 260, 200 },
		anchorPoint = "BOTTOM",
		selfPoint = "BOTTOM",
		attachTo = "UIParent",
		clickCast = false,
		barOrientation = "horizontal",
		sameSizeAsPlayer = false,
		mirrorPlayer = false,

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },
		reverseHealthFill = false,
		healthBarTexture = [[Interface\Buttons\WHITE8x8]],
		useHealthBarTexture = false,
		powerBarTexture = [[Interface\Buttons\WHITE8x8]],
		usePowerBarTexture = false,

		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = CopyDeep(WidgetDefaults),
	},

	-----------------------------------------------
	-- Target of Target Frame
	-----------------------------------------------
	targettarget = {
		enabled = true,
		size = { 100, 22 },
		position = { 0, 0 }, -- anchored to target

		anchorToParent = true,
		parent = "target",
		anchorPosition = CreatePositionOpt("BOTTOMLEFT", "BOTTOMRIGHT", 5, 0),

		clickCast = false,
		barOrientation = "horizontal",
		sameSizeAsPlayer = false,

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },
		reverseHealthFill = false,

		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = {
			nameText = CopyDeep(WidgetDefaults.nameText),
			healthText = CopyDeep(WidgetDefaults.healthText),
			powerText = CopyDeep(WidgetDefaults.powerText),
			powerBar = CopyDeep(WidgetDefaults.powerBar),
			buffs = CopyDeep(WidgetDefaults.buffs), -- [FIX] 버프 defaults 추가
			debuffs = CopyDeep(WidgetDefaults.debuffs),
			defensives = CopyDeep(WidgetDefaults.defensives), -- [REFACTOR] per-unit 생존기
			privateAuras = CopyDeep(WidgetDefaults.privateAuras), -- [REFACTOR] per-unit 프라이빗 오라
			raidIcon = CopyDeep(WidgetDefaults.raidIcon),
			fader = CopyDeep(WidgetDefaults.fader),
			highlight = CopyDeep(WidgetDefaults.highlight),
			customText = CopyDeep(WidgetDefaults.customText), -- [FIX] 커스텀 태그 지원
		},
	},

	-----------------------------------------------
	-- Focus Frame
	-----------------------------------------------
	focus = {
		enabled = true,
		size = { 180, 32 },
		position = { -300, -100 },
		anchorPoint = "LEFT",
		selfPoint = "LEFT",
		attachTo = "UIParent",

		anchorToParent = false,
		parent = nil,
		anchorPosition = nil,

		clickCast = false,
		barOrientation = "horizontal",
		sameSizeAsPlayer = false,

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },
		reverseHealthFill = false,

		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = CopyDeep(WidgetDefaults),
	},

	-----------------------------------------------
	-- Focus Target Frame
	-----------------------------------------------
	focustarget = {
		enabled = true,
		size = { 80, 22 },
		position = { 0, 0 },

		anchorToParent = true,
		parent = "focus",
		anchorPosition = CreatePositionOpt("TOPLEFT", "TOPRIGHT", 5, 0),

		clickCast = false,
		barOrientation = "horizontal",
		sameSizeAsPlayer = false,

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },

		border = {
			enabled = true,
			size = 1,
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = {
			nameText = CopyDeep(WidgetDefaults.nameText),
			healthText = CopyDeep(WidgetDefaults.healthText),
			powerText = CopyDeep(WidgetDefaults.powerText),
			powerBar = CopyDeep(WidgetDefaults.powerBar),
			buffs = CopyDeep(WidgetDefaults.buffs), -- [FIX] 버프 defaults 추가
			debuffs = CopyDeep(WidgetDefaults.debuffs),
			defensives = CopyDeep(WidgetDefaults.defensives), -- [REFACTOR] per-unit 생존기
			privateAuras = CopyDeep(WidgetDefaults.privateAuras), -- [REFACTOR] per-unit 프라이빗 오라
			raidIcon = CopyDeep(WidgetDefaults.raidIcon),
			fader = CopyDeep(WidgetDefaults.fader),
			highlight = CopyDeep(WidgetDefaults.highlight),
			customText = CopyDeep(WidgetDefaults.customText), -- [FIX] 커스텀 태그 지원
		},
	},

	-----------------------------------------------
	-- Pet Frame
	-----------------------------------------------
	pet = {
		enabled = true,
		size = { 100, 22 },
		position = { 0, 0 },

		anchorToParent = true,
		parent = "player",
		anchorPosition = CreatePositionOpt("TOPLEFT", "BOTTOMLEFT", 0, -5),

		clickCast = false,
		barOrientation = "horizontal",
		sameSizeAsPlayer = false,

		healthBarColorType = "reaction",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },

		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = {
			nameText = CopyDeep(WidgetDefaults.nameText),
			healthText = CopyDeep(WidgetDefaults.healthText),
			defensives = CopyDeep(WidgetDefaults.defensives), -- [REFACTOR] per-unit 생존기
			privateAuras = CopyDeep(WidgetDefaults.privateAuras), -- [REFACTOR] per-unit 프라이빗 오라
			powerBar = CopyDeep(WidgetDefaults.powerBar),
			castBar = CopyDeep(WidgetDefaults.castBar),
			buffs = CopyDeep(WidgetDefaults.buffs),
			debuffs = CopyDeep(WidgetDefaults.debuffs),
			raidIcon = CopyDeep(WidgetDefaults.raidIcon),
			fader = CopyDeep(WidgetDefaults.fader),
			highlight = CopyDeep(WidgetDefaults.highlight),
			customText = CopyDeep(WidgetDefaults.customText), -- [FIX] 커스텀 태그 지원
		},
	},

	-----------------------------------------------
	-- Boss Frames
	-----------------------------------------------
	boss = {
		enabled = true,
		size = { 180, 35 },
		position = { -60, 100 },
		anchorPoint = "RIGHT",
		selfPoint = "RIGHT",
		attachTo = "UIParent",
		spacing = 48,
		growDirection = "DOWN",

		clickCast = false,
		barOrientation = "horizontal",

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },
		reverseHealthFill = false,

		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = CopyDeep(WidgetDefaults),
	},

	-----------------------------------------------
	-- Arena Frames
	-----------------------------------------------
	arena = {
		enabled = true,
		size = { 180, 35 },
		position = { -60, 100 },
		anchorPoint = "RIGHT",
		selfPoint = "RIGHT",
		attachTo = "UIParent",
		spacing = 48,
		growDirection = "DOWN",

		clickCast = false,
		barOrientation = "horizontal",

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },

		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = CopyDeep(WidgetDefaults),
	},

	-----------------------------------------------
	-- Party Frames
	-----------------------------------------------
	party = {
		enabled = true,
		size = { 120, 36 },
		position = { 20, -40 },
		anchorPoint = "TOPLEFT",
		spacing = 4,
		spacingX = 0, -- [IMPORT-REWRITE] 가로 간격
		spacingY = 4, -- [IMPORT-REWRITE] 세로 간격
		maxColumns = 1, -- [IMPORT-REWRITE]
		unitsPerColumn = 5, -- [IMPORT-REWRITE]
		growDirection = "DOWN", -- "DOWN", "UP", "RIGHT", "LEFT", "H_CENTER", "V_CENTER"
		columnGrowDirection = "RIGHT", -- "RIGHT", "LEFT", "DOWN", "UP" (2차 정렬 방향)
		groupBy = "GROUP", -- "GROUP", "ROLE", "CLASS"
		sortBy = "INDEX", -- "INDEX", "NAME"
		sortDir = "ASC", -- "ASC", "DESC"
		showPlayer = false,
		showInRaid = false,

		clickCast = true,
		barOrientation = "horizontal",

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },
		reverseHealthFill = false,

		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = CopyDeep(WidgetDefaults),
		-- NOTE: CopyDeep(WidgetDefaults)에 debuffHighlight 이미 포함
	},

	-----------------------------------------------
	-- Raid Frames
	-----------------------------------------------
	raid = {
		enabled = true,
		size = { 66, 46 },
		position = { 20, -100 },
		anchorPoint = "TOPLEFT",
		spacingX = 3,
		spacingY = 3,
		groupSpacing = 5,
		unitsPerColumn = 5,
		maxColumns = 8,
		maxGroups = 8,
		growDirection = "DOWN", -- "DOWN", "UP", "RIGHT", "LEFT", "H_CENTER", "V_CENTER"
		columnGrowDirection = "RIGHT", -- "RIGHT", "LEFT", "DOWN", "UP" (2차 정렬 방향)
		groupBy = "GROUP", -- "GROUP", "ROLE", "CLASS"
		sortBy = "INDEX", -- "INDEX", "NAME"
		sortDir = "ASC", -- "ASC", "DESC"
		sortByRole = false,
		visibility = "[group:raid] show; hide",

		clickCast = true,
		barOrientation = "horizontal",

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },
		reverseHealthFill = false,

		border = {
			enabled = true,
			size = 1, -- [UF-OPTIONS] 슬라이더 1~5, 기본 1px
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = {
			nameText = CopyDeep(WidgetDefaults.nameText),
			healthText = CopyDeep(WidgetDefaults.healthText),
			powerText = CopyDeep(WidgetDefaults.powerText), -- [FIX] 자원 텍스트 위젯 추가
			statusText = CopyDeep(WidgetDefaults.statusText), -- [FIX] 상태 텍스트 위젯 추가
			powerBar = CopyDeep(WidgetDefaults.powerBar),
			buffs = CopyDeep(WidgetDefaults.buffs), -- [AURA-FILTER] raid에도 버프 위젯 추가
			debuffs = CopyDeep(WidgetDefaults.debuffs),
			defensives = CopyDeep(WidgetDefaults.defensives), -- [AURA-FILTER] 생존기 위젯
			privateAuras = CopyDeep(WidgetDefaults.privateAuras), -- [REFACTOR] per-unit 프라이빗 오라
			hotTracker = CopyDeep(WidgetDefaults.hotTracker), -- [HOT-TRACKER] HoT 추적
			dispels = CopyDeep(WidgetDefaults.dispels),
			raidIcon = CopyDeep(WidgetDefaults.raidIcon),
			roleIcon = CopyDeep(WidgetDefaults.roleIcon),
			leaderIcon = CopyDeep(WidgetDefaults.leaderIcon),
			readyCheckIcon = CopyDeep(WidgetDefaults.readyCheckIcon),
			resurrectIcon = CopyDeep(WidgetDefaults.resurrectIcon),
			summonIcon = CopyDeep(WidgetDefaults.summonIcon),
			shieldBar = CopyDeep(WidgetDefaults.shieldBar),
			healPrediction = CopyDeep(WidgetDefaults.healPrediction),
			healAbsorb = CopyDeep(WidgetDefaults.healAbsorb),
			threat = CopyDeep(WidgetDefaults.threat),
			fader = CopyDeep(WidgetDefaults.fader),
			highlight = CopyDeep(WidgetDefaults.highlight),
			debuffHighlight = CopyDeep(WidgetDefaults.debuffHighlight), -- [FIX] 디버프 하이라이트
			customText = CopyDeep(WidgetDefaults.customText), -- [FIX] 커스텀 텍스트 위젯 추가
		},
	},

	-----------------------------------------------
	-- Mythic Raid Frames (신화 레이드 20인 고정)
	-----------------------------------------------
	mythicRaid = {
		enabled = true,
		size = { 56, 38 },         -- 더 작은 프레임 (raid: 66x46)
		position = { 20, -100 },   -- 같은 위치 (전환 시 자연스럽게)
		anchorPoint = "TOPLEFT",
		spacingX = 2,              -- 더 촘촘 (raid: 3)
		spacingY = 2,
		groupSpacing = 3,          -- (raid: 5)
		unitsPerColumn = 5,
		maxColumns = 8,
		maxGroups = 4,             -- 20인 = 4그룹 (raid: 8)
		growDirection = "DOWN",
		columnGrowDirection = "RIGHT",
		groupBy = "GROUP",
		sortBy = "INDEX",
		sortDir = "ASC",
		sortByRole = false,
		-- visibility는 사용하지 않음 (raid 헤더의 visibility를 공유)

		clickCast = true,
		barOrientation = "horizontal",

		healthBarColorType = "class",
		healthLossColorType = "custom",
		healthBarColor = { 0.2, 0.2, 0.2, 1 },
		healthLossColor = { 0.5, 0.1, 0.1, 1 },
		reverseHealthFill = false,

		border = {
			enabled = true,
			size = 1,
			color = { 0, 0, 0, 1 },
		},

		background = {
			color = { 0.08, 0.08, 0.08, 0.85 },
		},

		widgets = {
			nameText = CopyDeep(WidgetDefaults.nameText),
			healthText = CopyDeep(WidgetDefaults.healthText),
			powerText = CopyDeep(WidgetDefaults.powerText), -- [FIX] 자원 텍스트 위젯 추가
			statusText = CopyDeep(WidgetDefaults.statusText), -- [FIX] 상태 텍스트 위젯 추가
			powerBar = CopyDeep(WidgetDefaults.powerBar),
			buffs = CopyDeep(WidgetDefaults.buffs),
			debuffs = CopyDeep(WidgetDefaults.debuffs),
			defensives = CopyDeep(WidgetDefaults.defensives),
			privateAuras = CopyDeep(WidgetDefaults.privateAuras),
			hotTracker = CopyDeep(WidgetDefaults.hotTracker),
			dispels = CopyDeep(WidgetDefaults.dispels),
			raidIcon = CopyDeep(WidgetDefaults.raidIcon),
			roleIcon = CopyDeep(WidgetDefaults.roleIcon),
			leaderIcon = CopyDeep(WidgetDefaults.leaderIcon),
			readyCheckIcon = CopyDeep(WidgetDefaults.readyCheckIcon),
			resurrectIcon = CopyDeep(WidgetDefaults.resurrectIcon),
			summonIcon = CopyDeep(WidgetDefaults.summonIcon),
			shieldBar = CopyDeep(WidgetDefaults.shieldBar),
			healPrediction = CopyDeep(WidgetDefaults.healPrediction),
			healAbsorb = CopyDeep(WidgetDefaults.healAbsorb),
			threat = CopyDeep(WidgetDefaults.threat),
			fader = CopyDeep(WidgetDefaults.fader),
			highlight = CopyDeep(WidgetDefaults.highlight),
			debuffHighlight = CopyDeep(WidgetDefaults.debuffHighlight),
			customText = CopyDeep(WidgetDefaults.customText), -- [FIX] 커스텀 텍스트 위젯 추가
		},
	},
	}

	-- Apply Unit-specific widget overrides
	-- Player: nameText 왼쪽 정렬
	defaults.player.widgets.nameText.position = CreatePositionOpt("LEFT", "LEFT", 3, 0)
	defaults.player.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r"
	defaults.player.widgets.healthText.position = CreatePositionOpt("RIGHT", "RIGHT", -3, 0)
	defaults.player.widgets.healthText.tag = "[ddingui:health]" -- [12.0.1]
	defaults.player.widgets.powerText.enabled = true -- [FIX] 플레이어 자원 텍스트 기본 활성화
	defaults.player.widgets.powerText.position = CreatePositionOpt("RIGHT", "CENTER", -4, 0)
	defaults.player.widgets.castBar.size = CreateSizeOpt(250, 20)
	defaults.player.widgets.castBar.anchorToParent = false
	defaults.player.widgets.castBar.detachedPosition = CreatePositionOpt("BOTTOM", "BOTTOM", 0, 260)

	-- Target: nameText 왼쪽 정렬
	defaults.target.widgets.nameText.position = CreatePositionOpt("LEFT", "LEFT", 3, 0)
	defaults.target.widgets.nameText.showLevel = true -- [FIX] 대상 이름에 레벨 표시
	defaults.target.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r"
	defaults.target.widgets.healthText.position = CreatePositionOpt("RIGHT", "RIGHT", -3, 0)
	defaults.target.widgets.healthText.tag = "[ddingui:health:current-percent]" -- [12.0.1]
	defaults.target.widgets.powerText.enabled = true -- [FIX] 대상 자원 텍스트 기본 활성화
	defaults.target.widgets.powerText.position = CreatePositionOpt("RIGHT", "CENTER", -4, 0)

	-- TargetTarget: 간소화
	defaults.targettarget.widgets.nameText.position = CreatePositionOpt("CENTER", "CENTER", 0, 0)
	defaults.targettarget.widgets.nameText.font.size = 10
	defaults.targettarget.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r"
	defaults.targettarget.widgets.powerBar.size = CreateSizeOpt(100, 2)
	defaults.targettarget.widgets.buffs.enabled = false -- [FIX] 대상의 대상 버프 기본 OFF

	-- FocusTarget: 간소화
	defaults.focustarget.widgets.buffs.enabled = false -- [FIX] 주시 대상 버프 기본 OFF

	-- Focus
	defaults.focus.widgets.nameText.position = CreatePositionOpt("LEFT", "LEFT", 3, 0)
	defaults.focus.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r"
	defaults.focus.widgets.healthText.tag = "[ddingui:health]" -- [12.0.1]
	defaults.focus.widgets.powerText.enabled = true -- [FIX] 초점 자원 텍스트 기본 활성화
	defaults.focus.widgets.powerText.position = CreatePositionOpt("RIGHT", "CENTER", -4, 0)
	defaults.focus.widgets.castBar.size = CreateSizeOpt(180, 15)

	-- Pet
	defaults.pet.widgets.nameText.position = CreatePositionOpt("CENTER", "CENTER", 0, 0)
	defaults.pet.widgets.nameText.font.size = 10
	defaults.pet.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r"
	defaults.pet.widgets.powerBar.size = CreateSizeOpt(100, 2)

	-- Boss: 레벨 + 이름 + 분류
	defaults.boss.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r [ddingui:classification]"
	defaults.boss.widgets.healthText.tag = "[ddingui:health:current-percent]" -- [12.0.1]

	-- Arena: 직업색 + 이름
	defaults.arena.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r"
	defaults.arena.widgets.healthText.tag = "[ddingui:health:current-percent]" -- [12.0.1]

	-- Party: 직업색 + 이름 (RIGHT 앵커 없음, 태그가 8글자 제한)
	defaults.party.widgets.nameText.position = CreatePositionOpt("LEFT", "LEFT", 4, 0)
	defaults.party.widgets.nameText.width = { type = "unlimited" }     -- [FIX] 태그로 길이 제한, WoW "..." 방지
	defaults.party.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r" -- [FIX] RIGHT 앵커 없으므로 풀네임
	defaults.party.widgets.healthText.tag = "[ddingui:health:percent]" -- [12.0.1]

	-- Raid 특화 설정 (2개 앵커로 텍스트 범위 제한)
	defaults.raid.widgets.nameText.position = CreatePositionOpt("CENTER", "CENTER", 0, 0)
	defaults.raid.widgets.nameText.position.rightPoint = "RIGHT"       -- [FIX] 2nd anchor
	defaults.raid.widgets.nameText.position.rightRelPoint = "RIGHT"
	defaults.raid.widgets.nameText.position.rightOffsetX = -2
	defaults.raid.widgets.nameText.position.leftPoint = "LEFT"         -- [FIX] 3rd anchor (raid 3점 앵커)
	defaults.raid.widgets.nameText.position.leftRelPoint = "LEFT"
	defaults.raid.widgets.nameText.position.leftOffsetX = 2
	defaults.raid.widgets.nameText.width = { type = "anchor" }         -- [FIX] 앵커로 너비 결정
	defaults.raid.widgets.nameText.font.size = 10
	defaults.raid.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r"
	defaults.raid.widgets.healthText.enabled = false
	defaults.raid.widgets.healthText.tag = "[ddingui:health:raid]" -- [12.0.1]
	defaults.raid.widgets.powerBar.size = CreateSizeOpt(66, 3)
	defaults.raid.widgets.debuffs.maxIcons = 3
	defaults.raid.widgets.debuffs.size = CreateSizeOpt(16, 16)
	defaults.raid.widgets.debuffs.filter.onlyDispellable = true -- [AURA-FILTER] 구 키 수정
	defaults.raid.widgets.debuffs.filter.showBossAura = true -- [AURA-FILTER] 구 키 수정
	defaults.raid.widgets.dispels.onlyShowDispellable = true

	-- MythicRaid 특화 설정 (raid와 동일 구조, 크기만 다름)
	defaults.mythicRaid.widgets.nameText.position = CreatePositionOpt("CENTER", "CENTER", 0, 0)
	defaults.mythicRaid.widgets.nameText.position.rightPoint = "RIGHT"
	defaults.mythicRaid.widgets.nameText.position.rightRelPoint = "RIGHT"
	defaults.mythicRaid.widgets.nameText.position.rightOffsetX = -2
	defaults.mythicRaid.widgets.nameText.position.leftPoint = "LEFT"
	defaults.mythicRaid.widgets.nameText.position.leftRelPoint = "LEFT"
	defaults.mythicRaid.widgets.nameText.position.leftOffsetX = 2
	defaults.mythicRaid.widgets.nameText.width = { type = "anchor" }
	defaults.mythicRaid.widgets.nameText.font.size = 9 -- raid(10)보다 약간 작게
	defaults.mythicRaid.widgets.nameText.tag = "[ddingui:classcolor][ddingui:name]|r"
	defaults.mythicRaid.widgets.healthText.enabled = false
	defaults.mythicRaid.widgets.healthText.tag = "[ddingui:health:raid]"
	defaults.mythicRaid.widgets.powerBar.size = CreateSizeOpt(56, 2) -- raid(66x3)보다 작게
	defaults.mythicRaid.widgets.debuffs.maxIcons = 3
	defaults.mythicRaid.widgets.debuffs.size = CreateSizeOpt(14, 14) -- raid(16x16)보다 작게
	defaults.mythicRaid.widgets.debuffs.filter.onlyDispellable = true
	defaults.mythicRaid.widgets.debuffs.filter.showBossAura = true
	defaults.mythicRaid.widgets.dispels.onlyShowDispellable = true

	return defaults
end

-----------------------------------------------
-- Config Functions
-----------------------------------------------

function Config:Initialize()
	-- [PERF] ns.defaults를 여기서 구축 (파일 파싱 시점이 아닌 ADDON_LOADED 시점)
	ns.defaults = BuildDefaults()
	self:MergeDefaults()

	-- [AD] AuraDesigner DB 기본값 초기화
	if not ns.db.auraDesigner then
		ns.db.auraDesigner = {
			enabled = true, -- 프리셋 포함 → 기본 활성화
			spec = "auto",
			auras = {},
			layoutGroups = {},
			defaults = {
				iconSize = 20, iconScale = 1.0,
				showDuration = true, showStacks = true,
				durationScale = 1.0, durationOutline = "OUTLINE",
			},
		}
	end
end

-- [AUDIT-FIX] merge 함수를 모듈 레벨로 이동 (매 호출 클로저 생성 방지)
local function MergeDeep(source, target)
	for key, value in pairs(source) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = CopyDeep(value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			MergeDeep(value, target[key])
		end
	end
end

function Config:MergeDefaults()
	MergeDeep(ns.defaults, ns.db)
end

-- [FIX] 마이그레이션: 옛 축약 태그 + width 제약 제거
-- IMPORTANT: Profiles:Initialize() 이후에 호출해야 함 (ns.db가 실제 SavedVars를 가리킬 때)
function Config:RunMigrations()
	local OLD_TAGS = { "ddingui:name:medium", "ddingui:name:short", "ddingui:name:raid" }
	local allUnits = { "player", "target", "targettarget", "focus", "focustarget", "pet", "party", "raid", "mythicRaid", "boss", "arena" }
	for _, unitKey in ipairs(allUnits) do
		local unitDB = ns.db[unitKey]
		local nameDB = unitDB and unitDB.widgets and unitDB.widgets.nameText
		if nameDB then
			-- 태그 마이그레이션: 옛 축약 태그 → 풀네임
			if nameDB.tag and nameDB.tag ~= "" then
				for _, old in ipairs(OLD_TAGS) do
					if nameDB.tag:find(old, 1, true) then
						nameDB.tag = nameDB.tag:gsub(old, "ddingui:name")
						break
					end
				end
			end
			-- width: percentage → unlimited (이름 잘림 방지)
			-- anchor는 raid 등에서 의도적 사용이므로 유지
			if nameDB.width and nameDB.width.type == "percentage" then
				nameDB.width.type = "unlimited"
				nameDB.width.value = 0
			end
			-- position: rightPoint 제거 (RIGHT 앵커 제약 방지)
			if nameDB.position and nameDB.position.rightPoint then
				nameDB.position.rightPoint = nil
				nameDB.position.rightRelPoint = nil
				nameDB.position.rightOffsetX = nil
				nameDB.position.rightOffsetY = nil
			end
		end
	end

	-- iconSet 마이그레이션: "minimal"/"custom" → "ddingui" -- [REFACTOR]
	if ns.db.iconSet == "minimal" or ns.db.iconSet == "custom" then
		ns.db.iconSet = "ddingui"
	end

	-- numberFormat 마이그레이션: 기존 "WESTERN" → 한국어 클라이언트면 "KOREAN"
	if ns.db.numberFormat == "WESTERN" and GetLocale() == "koKR" then
		ns.db.numberFormat = "KOREAN"
	end

	-- [HOT-TRACKER] displayTypes(전역) → auraSettings(per-aura) 마이그레이션
	local hotUnits = { "party", "raid", "mythicRaid" }
	for _, unitKey in ipairs(hotUnits) do
		local unitDB = ns.db[unitKey]
		local hotDB = unitDB and unitDB.widgets and unitDB.widgets.hotTracker
		if hotDB and hotDB.displayTypes then
			if not hotDB.auraSettings then hotDB.auraSettings = {} end
			local dt = hotDB.displayTypes
			local overrides = hotDB.specOverrides or {}
			for specKey, specData in pairs(HotSpecData) do
				for auraName in pairs(specData.auras) do
					local key = specKey .. "." .. auraName
					if not hotDB.auraSettings[key] then
						local isEnabled = true
						if overrides[specKey] and overrides[specKey][auraName] == false then
							isEnabled = false
						end
						hotDB.auraSettings[key] = {
							enabled = isEnabled,
							bar = dt.bar and { enabled = dt.bar.enabled, thickness = dt.bar.thickness, color = dt.bar.color } or { enabled = false },
							gradient = dt.gradient and {
								enabled = dt.gradient.enabled,
								intensity = dt.gradient.intensity,
								colors = dt.gradient.colors,
							} or { enabled = false },
							healthColor = dt.healthColor and { enabled = dt.healthColor.enabled, color = dt.healthColor.color } or { enabled = false },
							outline = dt.outline and { enabled = dt.outline.enabled, size = dt.outline.size, color = dt.outline.color } or { enabled = false },
							text = {
								enabled = dt.text and dt.text.enabled or true,
								fontSize = dt.text and dt.text.font and dt.text.font.size or 9,
							},
						}
					end
				end
			end
			hotDB.displayTypes = nil
			hotDB.specOverrides = nil
		end
	end

	-- [FIX] debuffHighlight 마이그레이션: 테두리 제거 + 위아래 그라데이션
	local dhUnits = { "player", "target", "focus", "party", "raid", "mythicRaid", "boss", "arena" }
	for _, unitKey in ipairs(dhUnits) do
		local unitDB = ns.db[unitKey]
		local dhDB = unitDB and unitDB.widgets and unitDB.widgets.debuffHighlight
		if dhDB then
			-- borderSize: 2(구 기본값) → 0 (테두리 제거)
			if dhDB.borderSize == 2 then
				dhDB.borderSize = 0
			end
			-- overlayMode: solid(구 기본값) → gradient
			if dhDB.overlayMode == "solid" then
				dhDB.overlayMode = "gradient"
			end
			-- gradientStyle: EDGE/TOP_BOTTOM(구 기본값) → TOP (위만)
			if dhDB.gradientStyle == "EDGE" or dhDB.gradientStyle == "TOP_BOTTOM" then
				dhDB.gradientStyle = "TOP"
			end
		end
	end
end

function Config:Get(path)
	local parts = { strsplit(".", path) }
	local value = ns.db
	for _, part in ipairs(parts) do
		if type(value) ~= "table" then return nil end
		value = value[part]
	end
	return value
end

function Config:Set(path, newValue)
	local parts = { strsplit(".", path) }
	local target = ns.db
	for i = 1, #parts - 1 do
		if type(target[parts[i]]) ~= "table" then
			target[parts[i]] = {}
		end
		target = target[parts[i]]
	end
	target[parts[#parts]] = newValue
end

function Config:GetUnitSettings(unit)
	return ns.db[unit] or ns.defaults[unit] or {}
end

function Config:GetWidgetSettings(unit, widgetName)
	local unitSettings = self:GetUnitSettings(unit)
	if unitSettings.widgets and unitSettings.widgets[widgetName] then
		return unitSettings.widgets[widgetName]
	end
	return WidgetDefaults[widgetName] or {}
end

function Config:SetWidgetOption(unit, widgetName, optionPath, value)
	local path = unit .. ".widgets." .. widgetName .. "." .. optionPath
	self:Set(path, value)
end

function Config:GetWidgetOption(unit, widgetName, optionPath)
	local path = unit .. ".widgets." .. widgetName .. "." .. optionPath
	local value = self:Get(path)
	if value ~= nil then return value end

	-- Fallback to default
	local parts = { strsplit(".", optionPath) }
	local defaultWidget = WidgetDefaults[widgetName]
	if not defaultWidget then return nil end

	for _, part in ipairs(parts) do
		if type(defaultWidget) ~= "table" then return nil end
		defaultWidget = defaultWidget[part]
	end
	return defaultWidget
end

-- Export helper functions
Config.CreatePositionOpt = CreatePositionOpt
Config.CreateFontOpt = CreateFontOpt
Config.CreateColorOpt = CreateColorOpt
Config.CreateSizeOpt = CreateSizeOpt
Config.CreateGlowOpt = CreateGlowOpt
Config.CopyDeep = CopyDeep
