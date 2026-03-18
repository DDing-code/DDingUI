--[[
	ddingUI UnitFrames
	Core/Functions.lua - Utility functions
]]

local _, ns = ...

local F = {}
ns.Functions = F

local C = ns.Constants

-----------------------------------------------
-- API Upvalue Caching
-----------------------------------------------

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_modf = math.modf
local table_insert = table.insert
local table_remove = table.remove
local wipe = wipe
local type = type
local pcall = pcall
local format = format
local select = select
local tostring = tostring
local pairs = pairs

local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitReaction = UnitReaction
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local UIParent = UIParent
local CreateFrame = CreateFrame

-----------------------------------------------
-- Secret Value Handling (WoW 12.0+)
-- Legacy F: 메서드 — 기존 호출 호환 유지
-----------------------------------------------

-- [12.0.1] secret number/boolean 판별 (closure 제거)
function F:IsSecretValue(value)
	if value == nil then return true end
	if issecretvalue then return issecretvalue(value) end
	return false -- issecretvalue 없으면 안전하다고 가정
end

function F:GetSafeNumber(value, default)
	if self:IsSecretValue(value) then return default or 0 end
	return value or default or 0
end

-- [12.0.1] Secret-safe 나눗셈
function F:SafeDivide(a, b, default)
	default = default or 0
	if self:IsSecretValue(a) or self:IsSecretValue(b) then return default end
	if not b or b == 0 then return default end
	return a / b
end

-- [12.0.1] Secret-safe 퍼센트 (0~1 범위)
function F:SafePercent(current, max)
	if self:IsSecretValue(current) or self:IsSecretValue(max) then return 0 end
	if not max or max == 0 then return 0 end
	return current / max
end

-----------------------------------------------
-- 통합 Secret Value 유틸리티 (ns 레벨) -- [REFACTOR]
-- 모든 파일에서 ns.SafeVal / ns.SafeNum / ns.SafeBool 로 접근
-- issecretvalue 기반 (pcall보다 빠름)
-----------------------------------------------

local issecretvalue = issecretvalue

--- secret value → nil 변환 (boolean/string/number 모두)
--- @param val any
--- @return any|nil  secret이면 nil
function ns.SafeVal(val)
	if val == nil then return nil end
	if issecretvalue and issecretvalue(val) then return nil end
	return val
end

--- secret number → default 변환
--- @param val any
--- @param default number?  기본값 (default: 0)
--- @return number
function ns.SafeNum(val, default)
	default = default or 0
	if val == nil then return default end
	if issecretvalue and issecretvalue(val) then return default end
	return tonumber(val) or default
end

--- secret boolean → false 변환
--- @param val any
--- @return boolean
function ns.SafeBool(val)
	if val == nil then return false end
	if issecretvalue and issecretvalue(val) then return false end
	return val and true or false
end

-----------------------------------------------
-- 보호막 유틸리티 (GetSafeHealthPercent 동일 패턴) -- [12.0.1]
-- UnitGetTotalAbsorbs는 secret number 반환 가능
-- issecretvalue 체크 → non-secret이면 직접 연산, secret이면 nil 반환
-----------------------------------------------

--- 보호막 퍼센트 (0-100) — secret이면 nil
--- @param unit string
--- @return number|nil  secret이면 nil
function ns.GetSafeAbsorbPercent(unit)
	if not unit then return nil end
	local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
	if not absorbs then return nil end
	if issecretvalue and issecretvalue(absorbs) then return nil end
	local maxHP = UnitHealthMax(unit)
	if not maxHP then return nil end
	if issecretvalue and issecretvalue(maxHP) then return nil end
	if maxHP == 0 then return 0 end
	return absorbs / maxHP * 100
end

--- 보호막 정수값 — secret이면 nil, non-secret이면 number
--- @param unit string
--- @return number|nil
function ns.GetSafeAbsorbValue(unit)
	if not unit then return nil end
	local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
	if not absorbs then return nil end
	if issecretvalue and issecretvalue(absorbs) then return nil end
	return absorbs
end

--- 보호막 축약 문자열 — secret이면 AbbreviateNumbers(C++ 처리), non-secret이면 ns.Abbreviate
--- @param unit string
--- @return string
function ns.GetAbsorbText(unit)
	if not unit then return "" end
	local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
	if not absorbs then return "" end
	return ns.Abbreviate(absorbs) -- C++ AbbreviateNumbers가 secret 처리
end

--- 보호막 퍼센트 문자열 — secret이면 "?%", non-secret이면 "XX%"
--- @param unit string
--- @return string
function ns.GetAbsorbPercentText(unit)
	local pct = ns.GetSafeAbsorbPercent(unit)
	if pct == nil then return "?%" end
	if pct <= 0 then return "" end
	return string.format("%.0f%%", pct)
end

-----------------------------------------------
-- Number Abbreviation (CreateAbbreviateConfig + Lua fallback)
-- ns.db.numberFormat ("KOREAN"/"WESTERN") + ns.db.decimalLength (0~3)
-----------------------------------------------

local _RawAbbreviate = AbbreviateNumbers
local CreateAbbreviateConfig = CreateAbbreviateConfig
local issecretvalue = issecretvalue

local KOREAN_UNITS = {
	{ 1e4,  "만" },
	{ 1e8,  "억" },
	{ 1e12, "조" },
}
local WESTERN_UNITS = {
	{ 1e3,  "K" },
	{ 1e6,  "M" },
	{ 1e9,  "B" },
	{ 1e12, "T" },
}

-- Lua fallback: CreateAbbreviateConfig 없을 때 사용
-- secret value는 처리 불가 → _RawAbbreviate(value) fallback
local function LuaAbbreviate(value)
	local fmt = ns.db and ns.db.numberFormat or "KOREAN"
	local decimals = ns.db and ns.db.decimalLength or 1
	if decimals < 0 then decimals = 0 end
	if decimals > 3 then decimals = 3 end

	local units = (fmt == "KOREAN") and KOREAN_UNITS or WESTERN_UNITS
	for i = #units, 1, -1 do
		local u = units[i]
		if value >= u[1] then
			local divided = value / u[1]
			return string.format("%." .. decimals .. "f", divided) .. u[2]
		end
	end
	return tostring(math.floor(value + 0.5))
end

-- [REFACTOR] ElvUI/Platynator 검증 패턴:
-- AbbreviateNumbers(value, data) 에서 data = { config = CreateAbbreviateConfig(bp) }
-- raw config 직접 전달 시 Blizzard C-API가 무시함
-- significandDivisor = breakpoint / (10^decimals), fractionDivisor = 10^decimals

--- 숫자 축약 config 생성 (설정 변경 시 재호출)
function ns.BuildAbbreviateConfig()
	local decimals = ns.db and ns.db.decimalLength or 1
	if decimals < 0 then decimals = 0 end
	if decimals > 3 then decimals = 3 end

	local factor = 10 ^ decimals
	local fmt = ns.db and ns.db.numberFormat or "KOREAN"
	local units = (fmt == "KOREAN") and KOREAN_UNITS or WESTERN_UNITS

	-- Blizzard C-API 경로 (secret value 지원)
	if CreateAbbreviateConfig then
		local breakpoints = {}
		for i, u in ipairs(units) do
			breakpoints[i] = {
				breakpoint = u[1],
				abbreviation = u[2],
				significandDivisor = u[1] / factor,
				fractionDivisor = factor,
				abbreviationIsGlobal = false,
			}
		end
		-- {config = ...} 래퍼 테이블로 저장 (ElvUI/Platynator 검증 패턴)
		ns._abbreviateData = { config = CreateAbbreviateConfig(breakpoints) }
	else
		-- Lua fallback 모드
		ns._abbreviateData = nil
	end

	-- 설정 캐시 (LuaAbbreviate + 갱신 버전 추적)
	ns._abbrVersion = (ns._abbrVersion or 0) + 1
end

--- AbbreviateNumbers 래퍼: config 적용 + secret value 안전
--- @param value number|secret
--- @return string
function ns.Abbreviate(value)
	if not value then return "0" end
	-- C-API: {config=...} 래퍼 테이블 전달 (secret value도 처리)
	if ns._abbreviateData then
		return _RawAbbreviate(value, ns._abbreviateData)
	end
	-- Secret value → C-API 기본 축약 (설정 반영 불가, 안전성 우선)
	if issecretvalue and issecretvalue(value) then
		return _RawAbbreviate(value)
	end
	-- Lua fallback (설정 반영, secret 불가)
	return LuaAbbreviate(value)
end

-----------------------------------------------
-- Table Pooling
-----------------------------------------------

local tablePool = {}
local POOL_MAX = 128

function F:AcquireTable()
	return table_remove(tablePool) or {}
end

function F:ReleaseTable(t)
	if type(t) ~= "table" then return end
	wipe(t)
	if #tablePool < POOL_MAX then
		table_insert(tablePool, t)
	end
end

-----------------------------------------------
-- PixelPerfect System
-----------------------------------------------

local pixelMult = 1

function F:UpdatePixelScale()
	local scale = UIParent:GetEffectiveScale()
	pixelMult = (scale > 0) and (1 / scale) or 1
end

function F:PixelPerfect(value)
	if not value then return 0 end
	if ns.db and ns.db.pixelPerfect == false then return value end
	return pixelMult * math_floor(value / pixelMult + 0.5)
end

function F:PixelPerfectThickness(value)
	if ns.db and ns.db.pixelPerfect == false then return math_max(1, value or 1) end
	return math_max(pixelMult, self:PixelPerfect(value or 1))
end

-- Cell 방식: PixelUtil.GetNearestPixelSize 사용 (정확한 1물리픽셀)
function F:ScalePixel(desiredPixels)
	if ns.db and ns.db.pixelPerfect == false then return desiredPixels or 1 end
	if PixelUtil and PixelUtil.GetNearestPixelSize then
		local scale = UIParent:GetEffectiveScale()
		return PixelUtil.GetNearestPixelSize(desiredPixels or 1, scale)
	end
	return pixelMult * (desiredPixels or 1)
end

function F:SetPixelPerfectSize(frame, w, h)
	if not frame then return end
	frame:SetSize(self:PixelPerfect(w), self:PixelPerfect(h or w))
end

function F:GetPixelMult()
	return pixelMult
end

-----------------------------------------------
-- Number Formatting
-----------------------------------------------

function F:FormatNumber(value)
	if not value then return "0" end
	if self:IsSecretValue(value) then return "?" end
	-- closure 제거: issecretvalue 체크 후 직접 연산
	if value >= 1000000000 then
		return format("%.1fB", value / 1000000000)
	elseif value >= 1000000 then
		return format("%.1fM", value / 1000000)
	elseif value >= 1000 then
		return format("%.1fK", value / 1000)
	else
		return tostring(math_floor(value))
	end
end

function F:FormatPercent(current, max)
	if not current or not max then return "0%" end
	if self:IsSecretValue(current) or self:IsSecretValue(max) then return "?%" end
	-- closure 제거: issecretvalue 체크 후 직접 연산
	if max == 0 then return "0%" end
	return format("%d%%", math_floor(current / max * 100 + 0.5))
end

function F:FormatTime(seconds)
	if not seconds or seconds <= 0 then return "" end

	if seconds >= 3600 then
		return format("%dh", math_floor(seconds / 3600))
	elseif seconds >= 60 then
		return format("%dm", math_floor(seconds / 60))
	elseif seconds >= 10 then
		return format("%d", math_floor(seconds))
	else
		return format("%.1f", seconds)
	end
end

-----------------------------------------------
-- String Functions
-----------------------------------------------

function F:ShortenName(name, length)
	if not name then return "" end
	length = length or 12

	if #name <= length then return name end

	-- UTF-8 aware truncation
	local bytes = 0
	local chars = 0
	for i = 1, #name do
		local byte = name:byte(i)
		if byte < 128 or byte >= 192 then
			chars = chars + 1
			if chars > length then
				return name:sub(1, bytes) .. ".."
			end
		end
		bytes = i
	end

	return name
end

-----------------------------------------------
-- Color Functions
-----------------------------------------------

function F:GetClassColor(class)
	if not class then return 1, 1, 1 end
	local color = RAID_CLASS_COLORS[class]
	if color then return color.r, color.g, color.b end
	return 1, 1, 1
end

function F:GetReactionColor(unit)
	if not unit or not UnitExists(unit) then return 1, 1, 1 end
	-- [AUDIT-FIX] UnitReaction secret number 방어
	local reaction = UnitReaction(unit, "player")
	if reaction and not (issecretvalue and issecretvalue(reaction)) then
		-- [FIX] ns.Colors.reaction 글로벌 색상 우선 적용
		local rc = ns.Colors and ns.Colors.reaction
		if rc then
			local c
			if reaction >= 5 then c = rc.friendly
			elseif reaction == 4 then c = rc.neutral
			elseif reaction <= 3 then c = rc.hostile end
			if c then return c[1], c[2], c[3] end
		end
		local color = C.REACTION_COLORS[reaction]
		if color then return color[1], color[2], color[3] end
	end
	return 1, 1, 1
end

function F:GetPowerColor(powerType, powerToken)
	local colors = C.POWER_COLORS
	-- [AUDIT-FIX] pToken(string) 우선 조회 (secret 안전)
	if powerToken and not (issecretvalue and issecretvalue(powerToken)) and colors[powerToken] then
		local c = colors[powerToken]
		return c[1], c[2], c[3]
	end
	-- [AUDIT-FIX] powerType(number) secret 방어
	if powerType and not (issecretvalue and issecretvalue(powerType)) then
		local typeName = C.POWER_TYPES[powerType]
		if typeName and colors[typeName] then
			local c = colors[typeName]
			return c[1], c[2], c[3]
		end
	end
	return 0.31, 0.45, 0.63
end

function F:ColorGradient(perc, ...)
	if perc >= 1 then
		local r, g, b = select(select('#', ...) - 2, ...)
		return r, g, b
	elseif perc <= 0 then
		local r, g, b = ...
		return r, g, b
	end

	local num = select('#', ...) / 3
	local segment, relperc = math_modf(perc * (num - 1))
	local r1, g1, b1, r2, g2, b2 = select((segment * 3) + 1, ...)

	return r1 + (r2 - r1) * relperc,
		   g1 + (g2 - g1) * relperc,
		   b1 + (b2 - b1) * relperc
end

-----------------------------------------------
-- Frame Functions
-----------------------------------------------

function F:CreateBackdrop(frame, bgColor, borderColor, explicitW, explicitH)
	if not frame then return end

	bgColor = bgColor or C.FRAME_BG
	borderColor = borderColor or C.BORDER_COLOR

	local borderSize = self:ScalePixel(C.BORDER_SIZE)

	local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	-- [12.0.1] explicit size 모드: tainted context에서 GetSize() secret value 방지
	if explicitW and explicitH then
		backdrop:SetSize(explicitW + 2 * borderSize, explicitH + 2 * borderSize)
		backdrop:SetPoint("CENTER", frame, "CENTER", 0, 0)
	else
		backdrop:SetPoint("TOPLEFT", -borderSize, borderSize)
		backdrop:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
	end
	backdrop:SetFrameLevel(math_max(0, frame:GetFrameLevel() - 1))
	backdrop:SetBackdrop({
		bgFile = C.FLAT_TEXTURE,
		edgeFile = C.FLAT_TEXTURE,
		edgeSize = borderSize,
		insets = { left = borderSize, right = borderSize, top = borderSize, bottom = borderSize },
	})
	backdrop:SetBackdropColor(unpack(bgColor))
	backdrop:SetBackdropBorderColor(unpack(borderColor))

	frame.backdrop = backdrop
	return backdrop
end

function F:CreateFontString(parent, fontSize, fontFlags, justifyH)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(
		C.DEFAULT_FONT,
		fontSize or C.DEFAULT_FONT_SIZE,
		fontFlags or C.DEFAULT_FONT_FLAGS
	)
	fs:SetJustifyH(justifyH or "CENTER")
	fs:SetWordWrap(false)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
end

-----------------------------------------------
-- Unit Functions
-----------------------------------------------

-- [AUDIT-FIX] 모듈 레벨 상수로 이동 (매 호출 테이블 생성 방지 — 레이드 시 매초 100회+ 호출)
local DISPEL_BY_CLASS = {
	PRIEST  = { Magic = true, Disease = true },
	PALADIN = { Magic = true, Poison = true, Disease = true },
	DRUID   = { Magic = true, Curse = true, Poison = true },
	SHAMAN  = { Magic = true, Curse = true },
	MONK    = { Magic = true, Poison = true, Disease = true },
	MAGE    = { Curse = true },
	EVOKER  = { Magic = true, Poison = true },
}

function F:CanDispel(debuffType)
	if not debuffType then return false end
	local _, class = UnitClass("player")
	local classDispels = DISPEL_BY_CLASS[class]
	return classDispels and classDispels[debuffType] or false
end

function F:ShouldDisplayAura(unit, auraData, isRaidFrame)
	if not auraData then return false end
	if auraData.isBossAura then return true end

	if isRaidFrame then
		if auraData.isHarmful and auraData.dispelName then
			return true
		end
		if auraData.isFromPlayerOrPlayerPet then
			return true
		end
		return false
	end

	return true
end
