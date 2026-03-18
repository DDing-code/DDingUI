--[[
	ddingUI UnitFrames
	AuraDesigner/Presets.lua — 스펙별 기본 프리셋
	
	설치 직후 바로 동작. 유저가 수정하면 프리셋 덮어쓰지 않음.
	프리셋은 placed 인디케이터(icon/square/bar) + frame-level 효과를 포함.
	DandersFrames의 "즉시 동작" 철학 이식.
]]

local _, ns = ...

ns.AuraDesigner = ns.AuraDesigner or {}
local Presets = {}
ns.AuraDesigner.Presets = Presets

-- ============================================================
-- PRESET DEFINITIONS
-- 각 스펙의 오라별 기본 인디케이터 배치.
-- anchor: 프레임 기준 앵커 포인트
-- offsetX/Y: 앵커 기준 오프셋 (픽셀)
-- size: 아이콘/사각형 크기
-- ============================================================

local function Icon(id, anchor, ox, oy, size)
	return { id = id, type = "icon", anchor = anchor, offsetX = ox or 0, offsetY = oy or 0, size = size or 16, showDuration = true, showStacks = true }
end

local function Square(id, anchor, ox, oy, size, color)
	return { id = id, type = "square", anchor = anchor, offsetX = ox or 0, offsetY = oy or 0, size = size or 6, color = color }
end

local function Bar(id, anchor, ox, oy, height, matchWidth)
	return { id = id, type = "bar", anchor = anchor, offsetX = ox or 0, offsetY = oy or 0, height = height or 3, matchFrameWidth = matchWidth ~= false }
end

-- ============================================================
-- RESTORATION DRUID
-- ============================================================
Presets.RestorationDruid = {
	Rejuvenation = {
		priority = 7,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
	},
	Regrowth = {
		priority = 6,
		indicators = { Icon(1, "TOPLEFT", 16, -1, 14) },
	},
	Lifebloom = {
		priority = 8,
		indicators = { Icon(1, "TOPLEFT", 31, -1, 14) },
	},
	Germination = {
		priority = 6,
		indicators = { Square(1, "BOTTOMLEFT", 2, 2, 6, { r=0.77, g=0.89, b=0.42, a=1 }) },
	},
	WildGrowth = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 10, 2, 6, { r=0.81, g=0.58, b=0.93, a=1 }) },
	},
	SymbioticRelationship = {
		priority = 4,
		indicators = { Square(1, "BOTTOMLEFT", 18, 2, 6, { r=0.40, g=0.77, b=0.74, a=1 }) },
	},
	IronBark = {
		priority = 9,
		indicators = { Icon(1, "CENTER", 0, 0, 20) },
		border = { color = { r=0.65, g=0.47, b=0.33 }, thickness = 2 },
	},
}

-- ============================================================
-- PRESERVATION EVOKER
-- ============================================================
Presets.PreservationEvoker = {
	Echo = {
		priority = 7,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
	},
	Reversion = {
		priority = 6,
		indicators = { Icon(1, "TOPLEFT", 16, -1, 14) },
	},
	EchoReversion = {
		priority = 6,
		indicators = { Square(1, "BOTTOMLEFT", 2, 2, 6, { r=0.40, g=0.77, b=0.74, a=1 }) },
	},
	DreamBreath = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 10, 2, 6, { r=0.47, g=0.87, b=0.47, a=1 }) },
	},
	EchoDreamBreath = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 18, 2, 6, { r=0.36, g=0.82, b=0.60, a=1 }) },
	},
	DreamFlight = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 26, 2, 6, { r=0.81, g=0.58, b=0.93, a=1 }) },
	},
	Lifebind = {
		priority = 8,
		indicators = { Icon(1, "TOPLEFT", 31, -1, 14) },
	},
	TimeDilation = {
		priority = 9,
		indicators = { Icon(1, "CENTER", 0, 0, 20) },
		border = { color = { r=0.94, g=0.82, b=0.31 }, thickness = 2 },
	},
	Rewind = {
		priority = 9,
		indicators = {},
		border = { color = { r=0.74, g=0.85, b=0.40 }, thickness = 2 },
	},
	VerdantEmbrace = {
		priority = 7,
		indicators = { Square(1, "TOPRIGHT", -2, -2, 6, { r=0.47, g=0.87, b=0.47, a=1 }) },
	},
}

-- ============================================================
-- AUGMENTATION EVOKER
-- ============================================================
Presets.AugmentationEvoker = {
	Prescience = {
		priority = 8,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
	},
	ShiftingSands = {
		priority = 6,
		indicators = { Square(1, "BOTTOMLEFT", 2, 2, 6, { r=1.0, g=0.84, b=0.28, a=1 }) },
	},
	BlisteringScales = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 10, 2, 6, { r=0.94, g=0.50, b=0.50, a=1 }) },
	},
	InfernosBlessing = {
		priority = 7,
		indicators = { Square(1, "BOTTOMLEFT", 18, 2, 6, { r=1.0, g=0.60, b=0.28, a=1 }) },
	},
	SymbioticBloom = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 26, 2, 6, { r=0.51, g=0.78, b=0.52, a=1 }) },
	},
	EbonMight = {
		priority = 9,
		indicators = { Icon(1, "CENTER", 0, 0, 18) },
		border = { color = { r=0.62, g=0.47, b=0.85 }, thickness = 2 },
	},
	SourceOfMagic = {
		priority = 6,
		indicators = { Icon(1, "TOPLEFT", 16, -1, 14) },
	},
	SensePower = {
		priority = 4,
		indicators = { Square(1, "TOPRIGHT", -2, -2, 6, { r=0.94, g=0.82, b=0.31, a=1 }) },
	},
}

-- ============================================================
-- DISCIPLINE PRIEST
-- ============================================================
Presets.DisciplinePriest = {
	Atonement = {
		priority = 8,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
	},
	PowerWordShield = {
		priority = 7,
		indicators = { Icon(1, "TOPLEFT", 16, -1, 14) },
	},
	VoidShield = {
		priority = 7,
		indicators = { Square(1, "BOTTOMLEFT", 2, 2, 6, { r=0.62, g=0.47, b=0.85, a=1 }) },
	},
	PrayerOfMending = {
		priority = 6,
		indicators = { Square(1, "BOTTOMLEFT", 10, 2, 6, { r=0.56, g=0.93, b=0.56, a=1 }) },
	},
	PainSuppression = {
		priority = 10,
		indicators = { Icon(1, "CENTER", 0, 0, 20) },
		border = { color = { r=0.81, g=0.58, b=0.93 }, thickness = 2 },
	},
	PowerInfusion = {
		priority = 9,
		indicators = {},
		border = { color = { r=0.94, g=0.82, b=0.31 }, thickness = 2 },
	},
}

-- ============================================================
-- HOLY PRIEST
-- ============================================================
Presets.HolyPriest = {
	Renew = {
		priority = 7,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
	},
	EchoOfLight = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 2, 2, 6, { r=1.0, g=0.84, b=0.28, a=1 }) },
	},
	PrayerOfMending = {
		priority = 6,
		indicators = { Icon(1, "TOPLEFT", 16, -1, 14) },
	},
	GuardianSpirit = {
		priority = 10,
		indicators = { Icon(1, "CENTER", 0, 0, 20) },
		border = { color = { r=0.94, g=0.50, b=0.50 }, thickness = 2 },
	},
	PowerInfusion = {
		priority = 9,
		indicators = {},
		border = { color = { r=0.94, g=0.82, b=0.31 }, thickness = 2 },
	},
}

-- ============================================================
-- MISTWEAVER MONK
-- ============================================================
Presets.MistweaverMonk = {
	RenewingMist = {
		priority = 7,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
	},
	EnvelopingMist = {
		priority = 8,
		indicators = { Icon(1, "TOPLEFT", 16, -1, 14) },
	},
	SoothingMist = {
		priority = 6,
		indicators = { Square(1, "BOTTOMLEFT", 2, 2, 6, { r=0.47, g=0.87, b=0.47, a=1 }) },
	},
	AspectOfHarmony = {
		priority = 7,
		indicators = { Square(1, "BOTTOMLEFT", 10, 2, 6, { r=0.81, g=0.58, b=0.93, a=1 }) },
	},
	LifeCocoon = {
		priority = 10,
		indicators = { Icon(1, "CENTER", 0, 0, 20) },
		border = { color = { r=0.31, g=0.76, b=0.97 }, thickness = 2 },
	},
	StrengthOfTheBlackOx = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 18, 2, 6, { r=0.40, g=0.77, b=0.74, a=1 }) },
	},
}

-- ============================================================
-- RESTORATION SHAMAN
-- ============================================================
Presets.RestorationShaman = {
	Riptide = {
		priority = 7,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
	},
	EarthShield = {
		priority = 8,
		indicators = { Icon(1, "TOPLEFT", 16, -1, 14) },
	},
	AncestralVigor = {
		priority = 5,
		indicators = { Square(1, "BOTTOMLEFT", 2, 2, 6, { r=0.56, g=0.93, b=0.56, a=1 }) },
	},
	EarthlivingWeapon = {
		priority = 4,
		indicators = { Square(1, "BOTTOMLEFT", 10, 2, 6, { r=0.47, g=0.87, b=0.47, a=1 }) },
	},
	Hydrobubble = {
		priority = 9,
		indicators = { Icon(1, "CENTER", 0, 0, 20) },
		border = { color = { r=0.31, g=0.76, b=0.97 }, thickness = 2 },
	},
}

-- ============================================================
-- HOLY PALADIN
-- ============================================================
Presets.HolyPaladin = {
	BeaconOfLight = {
		priority = 9,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
		nametext = { color = { r=1.0, g=0.93, b=0.47 } },
	},
	BeaconOfFaith = {
		priority = 9,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
		nametext = { color = { r=1.0, g=0.84, b=0.28 } },
	},
	BeaconOfVirtue = {
		priority = 8,
		indicators = { Square(1, "BOTTOMLEFT", 2, 2, 6, { r=1.0, g=0.88, b=0.37, a=1 }) },
	},
	BeaconOfTheSavior = {
		priority = 9,
		indicators = { Icon(1, "TOPLEFT", 1, -1, 14) },
		nametext = { color = { r=0.93, g=0.80, b=0.47 } },
	},
	EternalFlame = {
		priority = 7,
		indicators = { Icon(1, "TOPLEFT", 16, -1, 14) },
	},
	Dawnlight = {
		priority = 6,
		indicators = { Square(1, "BOTTOMLEFT", 10, 2, 6, { r=1.0, g=0.84, b=0.28, a=1 }) },
	},
	BlessingOfProtection = {
		priority = 10,
		indicators = { Icon(1, "CENTER", 0, 0, 20) },
		border = { color = { r=0.94, g=0.82, b=0.31 }, thickness = 2 },
	},
	HolyArmaments = {
		priority = 7,
		indicators = { Square(1, "BOTTOMLEFT", 18, 2, 6, { r=0.81, g=0.58, b=0.93, a=1 }) },
	},
	BlessingOfSacrifice = {
		priority = 9,
		indicators = {},
		border = { color = { r=0.94, g=0.50, b=0.50 }, thickness = 2 },
	},
	BlessingOfFreedom = {
		priority = 7,
		indicators = { Square(1, "TOPRIGHT", -2, -2, 6, { r=0.56, g=0.93, b=0.56, a=1 }) },
	},
}

-- ============================================================
-- PUBLIC API
-- ============================================================

-- Get preset for a spec
function Presets:Get(specKey)
	return self[specKey]
end

-- Apply preset to ns.db.auraDesigner if no user data exists for the spec
function Presets:ApplyIfEmpty(specKey)
	local preset = self[specKey]
	if not preset then return false end

	local adDB = ns.db and ns.db.auraDesigner
	if not adDB then return false end
	if not adDB.auras then adDB.auras = {} end

	-- 이미 유저 데이터가 있으면 덮어쓰지 않음
	if adDB.auras[specKey] and next(adDB.auras[specKey]) then
		return false
	end

	adDB.auras[specKey] = {}
	for auraName, auraCfg in pairs(preset) do
		-- Deep copy
		local copy = {}
		copy.priority = auraCfg.priority or 5
		copy.indicators = {}
		if auraCfg.indicators then
			for _, inst in ipairs(auraCfg.indicators) do
				local icopy = {}
				for k, v in pairs(inst) do
					if type(v) == "table" then
						icopy[k] = {}
						for k2, v2 in pairs(v) do icopy[k][k2] = v2 end
					else
						icopy[k] = v
					end
				end
				copy.indicators[#copy.indicators + 1] = icopy
			end
		end
		if auraCfg.border then
			copy.border = {}
			for k, v in pairs(auraCfg.border) do
				if type(v) == "table" then
					copy.border[k] = {}
					for k2, v2 in pairs(v) do copy.border[k][k2] = v2 end
				else
					copy.border[k] = v
				end
			end
		end
		if auraCfg.nametext then
			copy.nametext = {}
			for k, v in pairs(auraCfg.nametext) do
				if type(v) == "table" then
					copy.nametext[k] = {}
					for k2, v2 in pairs(v) do copy.nametext[k][k2] = v2 end
				else
					copy.nametext[k] = v
				end
			end
		end
		if auraCfg.healthbar then
			copy.healthbar = {}
			for k, v in pairs(auraCfg.healthbar) do
				if type(v) == "table" then
					copy.healthbar[k] = {}
					for k2, v2 in pairs(v) do copy.healthbar[k][k2] = v2 end
				else
					copy.healthbar[k] = v
				end
			end
		end
		adDB.auras[specKey][auraName] = copy
	end

	return true
end

-- Apply all presets (for fresh install)
function Presets:ApplyAllDefaults()
	local AD = ns.AuraDesigner
	if not AD or not AD.SpecMap then return end
	for _, specKey in pairs(AD.SpecMap) do
		self:ApplyIfEmpty(specKey)
	end
end

-- Reset spec to preset
function Presets:ResetToPreset(specKey)
	local adDB = ns.db and ns.db.auraDesigner
	if adDB and adDB.auras then
		adDB.auras[specKey] = nil
	end
	return self:ApplyIfEmpty(specKey)
end
