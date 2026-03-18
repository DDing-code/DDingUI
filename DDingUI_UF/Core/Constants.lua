--[[
	ddingUI UnitFrames
	Core/Constants.lua - Constants and static data
]]

local _, ns = ...

local C = {}
ns.Constants = C

-----------------------------------------------
-- Frame Limits
-----------------------------------------------

C.MAX_BOSS_FRAMES = 8
C.MAX_ARENA_FRAMES = 5
C.MAX_PARTY_FRAMES = 4
C.MAX_RAID_GROUPS = 8

-----------------------------------------------
-- Power Types
-----------------------------------------------

C.POWER_TYPES = {
	[Enum.PowerType.Mana] = "MANA",
	[Enum.PowerType.Rage] = "RAGE",
	[Enum.PowerType.Focus] = "FOCUS",
	[Enum.PowerType.Energy] = "ENERGY",
	[Enum.PowerType.ComboPoints] = "COMBO_POINTS",
	[Enum.PowerType.Runes] = "RUNES",
	[Enum.PowerType.RunicPower] = "RUNIC_POWER",
	[Enum.PowerType.SoulShards] = "SOUL_SHARDS",
	[Enum.PowerType.LunarPower] = "LUNAR_POWER",
	[Enum.PowerType.HolyPower] = "HOLY_POWER",
	[Enum.PowerType.Maelstrom] = "MAELSTROM",
	[Enum.PowerType.Chi] = "CHI",
	[Enum.PowerType.Insanity] = "INSANITY",
	[Enum.PowerType.ArcaneCharges] = "ARCANE_CHARGES",
	[Enum.PowerType.Fury] = "FURY",
	[Enum.PowerType.Pain] = "PAIN",
	[Enum.PowerType.Essence] = "ESSENCE",
}

-----------------------------------------------
-- Dispel Colors
-----------------------------------------------

C.DISPEL_COLORS = {
	Magic   = { 0.20, 0.60, 1.00 },
	Curse   = { 0.60, 0.00, 1.00 },
	Disease = { 0.60, 0.40, 0.00 },
	Poison  = { 0.00, 0.60, 0.00 },
	Bleed   = { 1.00, 0.00, 0.00 },  -- Enrage(9)도 이 색상 공유 (DandersFrames 동일)
	none    = { 0.80, 0.00, 0.00 },
}

-----------------------------------------------
-- Class Colors (with alpha)
-----------------------------------------------

C.CLASS_COLORS = {}
for class, color in pairs(RAID_CLASS_COLORS) do
	C.CLASS_COLORS[class] = { color.r, color.g, color.b, 1 }
end

-----------------------------------------------
-- Reaction Colors
-----------------------------------------------

C.REACTION_COLORS = {
	[1] = { 0.87, 0.36, 0.20 },
	[2] = { 0.87, 0.36, 0.20 },
	[3] = { 0.87, 0.36, 0.20 },
	[4] = { 0.85, 0.77, 0.36 },
	[5] = { 0.29, 0.67, 0.30 },
	[6] = { 0.29, 0.67, 0.30 },
	[7] = { 0.29, 0.67, 0.30 },
	[8] = { 0.29, 0.67, 0.30 },
}

-----------------------------------------------
-- Power Colors
-----------------------------------------------

C.POWER_COLORS = {
	MANA           = { 0.31, 0.45, 0.63 },
	RAGE           = { 0.78, 0.25, 0.25 },
	FOCUS          = { 0.71, 0.43, 0.27 },
	ENERGY         = { 0.65, 0.63, 0.35 },
	RUNIC_POWER    = { 0.00, 0.82, 1.00 },
	LUNAR_POWER    = { 0.30, 0.52, 0.90 },
	MAELSTROM      = { 0.00, 0.50, 1.00 },
	INSANITY       = { 0.40, 0.00, 0.80 },
	FURY           = { 0.79, 0.26, 0.99 },
	PAIN           = { 1.00, 0.61, 0.00 },
	CHI            = { 0.71, 1.00, 0.92 },
	ARCANE_CHARGES = { 0.10, 0.10, 0.98 },
	HOLY_POWER     = { 0.95, 0.90, 0.60 },
	SOUL_SHARDS    = { 0.58, 0.51, 0.79 },
	ESSENCE        = { 0.22, 0.58, 0.58 },
	COMBO_POINTS   = { 1.00, 0.96, 0.41 },
	RUNES          = { 0.50, 0.50, 0.50 },
}

-----------------------------------------------
-- Threat Colors
-----------------------------------------------

C.THREAT_COLORS = {
	[0] = { 0.69, 0.69, 0.69 },
	[1] = { 1.00, 1.00, 0.47 },
	[2] = { 1.00, 0.60, 0.00 },
	[3] = { 1.00, 0.00, 0.00 },
}

-----------------------------------------------
-- ClassPower Colors
-----------------------------------------------

C.CLASSPOWER_COLORS = {
	COMBO_POINTS   = { 1.00, 0.96, 0.41 },
	HOLY_POWER     = { 0.95, 0.90, 0.60 },
	CHI            = { 0.71, 1.00, 0.92 },
	SOUL_SHARDS    = { 0.58, 0.51, 0.79 },
	ARCANE_CHARGES = { 0.43, 0.43, 0.93 },
	ESSENCE        = { 0.22, 0.58, 0.58 },
}

-----------------------------------------------
-- Media Defaults
-----------------------------------------------

local SL = _G.DDingUI_StyleLib -- [12.0.1]
C.FLAT_TEXTURE = (SL and SL.Textures and SL.Textures.flat) or [[Interface\Buttons\WHITE8x8]] -- [12.0.1]
C.DEFAULT_FONT = (SL and SL.Font and SL.Font.default) or "Fonts\\FRIZQT__.TTF" -- [12.0.1]
C.DEFAULT_FONT_SIZE = 11
C.DEFAULT_FONT_FLAGS = "OUTLINE"

-----------------------------------------------
-- Design Constants (Cell-inspired)
-----------------------------------------------

C.BORDER_SIZE = 1 -- [UF-OPTIONS] 기본 1px, 슬라이더 1~5
C.FRAME_BG     = (SL and SL.Colors and SL.Colors.bg and SL.Colors.bg.sidebar) or { 0.08, 0.08, 0.08, 0.85 } -- [12.0.1]
C.BORDER_COLOR = { 0, 0, 0, 1 }
C.HEALTH_BG_MULTIPLIER = 0.2
C.POWER_HEIGHT = 3
C.CASTBAR_COLOR = { 1.0, 0.7, 0.0 }
C.CASTBAR_NOINTERRUPT_COLOR = { 0.7, 0.7, 0.7 }
C.HEAL_PREDICTION_COLOR = { 0, 0.83, 0, 0.4 }
C.ABSORB_COLOR = { 0.7, 0.7, 1.0, 0.5 }
C.OUT_OF_RANGE_ALPHA = 0.4

-----------------------------------------------
-- Smooth Bar (WoW Retail Native)
-----------------------------------------------

C.SMOOTH_INTERPOLATION = Enum and Enum.StatusBarInterpolation
	and Enum.StatusBarInterpolation.ExponentialEaseOut or nil

-----------------------------------------------
-- Secret Value → Percentage (WoW 12.0+)
-----------------------------------------------

C.CURVE_SCALE = CurveConstants and CurveConstants.ScaleTo100 or nil

-----------------------------------------------
-- Health Gradient (Red → Yellow → Green)
-----------------------------------------------

C.HEALTH_GRADIENT = { 1, 0, 0, 1, 1, 0, 0, 1, 0 }

-----------------------------------------------
-- Appearance States
-----------------------------------------------

C.APPEARANCE = {
	NORMAL = 0,
	OUT_OF_RANGE = 1,
	DEAD = 2,
	OFFLINE = 3,
}
C.DEAD_ALPHA = 0.6
C.OFFLINE_ALPHA = 0.5

-----------------------------------------------
-- Castbar SafeZone
-----------------------------------------------

C.SAFEZONE_COLOR = { 0.85, 0.20, 0.20, 0.50 }

-----------------------------------------------
-- Heal Absorb Color
-----------------------------------------------

C.HEAL_ABSORB_COLOR = { 0.68, 0.15, 0.15, 0.65 }

-----------------------------------------------
-- Not Interruptible Overlay
-----------------------------------------------

C.NI_OVERLAY_COLOR = { 0.78, 0.25, 0.25, 0.15 }

-----------------------------------------------
-- Highlight System (DandersFrames-inspired)
-- [12.0.1] Frame level offsets for Target/Focus/Hover borders
-----------------------------------------------

C.HIGHLIGHT_LEVELS = {
	FOCUS  = 8,   -- Focus 보더
	TARGET = 9,   -- Target 보더 (Selection)
	HOVER  = 10,  -- Mouseover 보더
}

-----------------------------------------------
-- Dispel Icons (WoW built-in textures) -- [12.0.1]
-----------------------------------------------

C.DISPEL_ICONS = {
	Magic   = [[Interface\Icons\Spell_Holy_DispelMagic]],
	Curse   = [[Interface\Icons\Spell_Holy_RemoveCurse]],
	Disease = [[Interface\Icons\Spell_Nature_RemoveDisease]],
	Poison  = [[Interface\Icons\Spell_Nature_NullifyPoison]],
}

-----------------------------------------------
-- Icon Sets (전투/역할/리더 아이콘 세트)
-----------------------------------------------
C.ICON_SETS = {
	["default"] = {
		label = "DDingUI",
		role = {
			textures = {
				TANK    = [[Interface\AddOns\DDingUI_UF\Media\Icons\tank_sololv]],
				HEALER  = [[Interface\AddOns\DDingUI_UF\Media\Icons\healer_sololv]],
				DAMAGER = [[Interface\AddOns\DDingUI_UF\Media\Icons\dps_sololv]],
			},
		},
		leader   = [[Interface\AddOns\DDingUI_UF\Media\Icons\leader_sololv]],
		assist   = [[Interface\AddOns\DDingUI_UF\Media\Icons\leader_sololv]],
		combat   = [[Interface\AddOns\DDingUI_UF\Media\Icons\combat_sololv]],
		resting  = [[Interface\AddOns\DDingUI_UF\Media\Icons\rest_sololv]],
	},
}

-----------------------------------------------
-- Layout Defaults (매직넘버 중앙 관리)
-- Layout.lua, Preview.lua 등에서 `or` fallback으로 사용되던 값들
-----------------------------------------------

C.SHADOW_OFFSET = { 1, -1 }
C.SHADOW_COLOR = { 0, 0, 0, 1 }
C.AURA_TEXCOORD = { 0.08, 0.92, 0.08, 0.92 }
C.AURA_BORDER_SIZE = 1

-- 글로우/보더
C.OVERHEAL_GLOW_WIDTH = 4
C.OVERSHIELD_GLOW_WIDTH = 8
C.OVERSHIELD_GLOW_OFFSET = { -4, 3, -4, -3 } -- topX, topY, bottomX, bottomY
C.HIGHLIGHT_BORDER_SIZE = 2
C.MOUSEOVER_ALPHA = 0.08

-- 캐스트바
C.CASTBAR_ATTACHED_GAP = 2
C.CASTBAR_SPELL_PADDING = 4
C.CASTBAR_TIMER_PADDING = -4
C.CASTBAR_TEXT_RIGHT_CLIP = -40
C.CASTBAR_ICON_GAP = 3

-- 인디케이터 기본 크기
C.INDICATOR_SIZE = {
	raidIcon = 14,
	roleIcon = 14,
	readyCheckIcon = 16,
	resurrectIcon = 20,
	leaderIcon = 14,
	combatIcon = 20,
	restingIcon = 18,
}

-- 텍스트 기본 오프셋
C.TEXT_OFFSET = {
	nameLeftPad = 4,
	healthRightPad = -4,
}

-- Additional Power
C.ADDITIONAL_POWER_HEIGHT = 4

-- ClassPower
C.CLASSPOWER_DEFAULT_HEIGHT = 4
C.CLASSPOWER_DEFAULT_GAP = 1
C.CLASSPOWER_MARGIN = 2
