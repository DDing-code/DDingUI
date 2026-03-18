--[[
	ddingUI UnitFrames
	Units/TextFormats.lua — oUF Tag 시스템 대체
	Tags.lua의 포맷 함수를 oUF 의존 없이 직접 호출
	12.0.1 Secret Value v4 유지 -- [SECRET-V4]
]]

local _, ns = ...

local TextFormats = {}
ns.TextFormats = TextFormats

-----------------------------------------------
-- API Upvalue Caching -- [SECRET-V4]
-----------------------------------------------

local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsAFK = UnitIsAFK
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitReaction = UnitReaction
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitClassification = UnitClassification
local issecretvalue = issecretvalue
local SafeVal = ns.SafeVal

local format = format
local math_floor = math.floor
local type = type
local pcall = pcall
local AbbreviateNumbers = function(v) return ns.Abbreviate(v) end
local FormatPercentage = FormatPercentage
local UnitHealthPercent = UnitHealthPercent
local UnitHealthMissing = UnitHealthMissing
local UnitPowerPercent = UnitPowerPercent
local UnitPowerMissing = UnitPowerMissing

local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100

-----------------------------------------------
-- Secret-Safe Helpers (Tags.lua에서 이동)
-----------------------------------------------

-- [PERF] pcall 제거: string.format은 C함수라 secret number도 직접 포맷 가능
local function FormatPct100(secretPct100)
	if not secretPct100 then return nil end
	return string.format("%.0f", secretPct100) .. "%"
end

-- [PERF] pcall 제거: issecretvalue 분기 → 직접 호출
local function SafeFormatHealthPercent(unit)
	if not UnitHealthPercent then return nil end
	if ScaleTo100 then
		local result = FormatPct100(UnitHealthPercent(unit, true, ScaleTo100))
		if result then return result end
	end
	local val = UnitHealthPercent(unit)
	if not val then return nil end
	if issecretvalue and issecretvalue(val) then return nil end
	if FormatPercentage then return FormatPercentage(val, true) end
	return tostring(val)
end

-- [PERF] pcall 제거: issecretvalue 분기 → 직접 호출
local function SafeFormatPowerPercent(unit)
	if not UnitPowerPercent then return nil end
	if ScaleTo100 then
		local result = FormatPct100(UnitPowerPercent(unit, nil, true, ScaleTo100))
		if result then return result end
	end
	local val = UnitPowerPercent(unit)
	if not val then return nil end
	if issecretvalue and issecretvalue(val) then return nil end
	if FormatPercentage then return FormatPercentage(val, true) end
	return tostring(val)
end

local function NotSecretValue(value)
	if value == nil then return true end
	if issecretvalue then return not issecretvalue(value) end
	return true -- issecretvalue 없으면 안전하다고 가정
end

-----------------------------------------------
-- Status / Name Helpers (Tags.lua에서 이동)
-----------------------------------------------

local function GetStatus(unit)
	if SafeVal(UnitIsDead(unit)) then return "|cffcc3333Dead|r" end -- [12.0.1] secret boolean
	if SafeVal(UnitIsGhost(unit)) then return "|cffcc3333Dead|r" end -- [12.0.1]
	if SafeVal(UnitIsConnected(unit)) == false then return "|cff999999Offline|r" end -- [12.0.1] nil(secret)이면 skip
	return nil
end

local function SafeUnitName(unit)
	local name = UnitName(unit)
	if name == nil then return UNKNOWN or "???" end
	return name
end

local function IsSecretName(name)
	return name ~= nil and not SafeVal(name)
end

-----------------------------------------------
-- UTF-8 Helpers (Tags.lua에서 이동)
-----------------------------------------------

local function UTF8Len(s)
	if not s then return 0 end
	local len = 0
	for i = 1, #s do
		local byte = s:byte(i)
		if byte < 128 or byte >= 192 then
			len = len + 1
		end
	end
	return len
end

local function TruncateUTF8(name, maxChars)
	if not name then return "" end
	if UTF8Len(name) <= maxChars then return name end
	local bytes = 0
	local chars = 0
	for i = 1, #name do
		local byte = name:byte(i)
		if byte < 128 or byte >= 192 then
			chars = chars + 1
			if chars > maxChars then
				return name:sub(1, bytes)
			end
		end
		bytes = i
	end
	return name
end

-----------------------------------------------
-- Color Wrapping (Tags.lua WrapHealthColor/WrapPowerColor)
-----------------------------------------------

local function WrapHealthColor(text, unit, htDB)
	if not text then return text end
	local colorType = htDB and htDB.color and htDB.color.type or "white"
	if colorType == "class_color" then
		local _, class = UnitClass(unit)
		if class then
			local c = RAID_CLASS_COLORS[class]
			if c then
				return format("|cff%02x%02x%02x", math_floor(c.r * 255 + 0.5), math_floor(c.g * 255 + 0.5), math_floor(c.b * 255 + 0.5)) .. text .. "|r"
			end
		end
	elseif colorType == "reaction_color" then
		local reaction = UnitReaction(unit, "player")
		if reaction and NotSecretValue(reaction) then
			if reaction >= 5 then return "|cff4ab34a" .. text .. "|r"
			elseif reaction == 4 then return "|cffcccc33" .. text .. "|r"
			else return "|cffcc3333" .. text .. "|r" end
		end
	end
	return text
end

local function WrapPowerColor(text, unit, ptDB)
	if not text then return text end
	local colorType = ptDB and ptDB.color and ptDB.color.type or "power_color"
	if colorType == "power_color" then
		local pType, pToken = UnitPowerType(unit)
		-- [12.0.1] secret value 방어
		if pToken and issecretvalue and issecretvalue(pToken) then pToken = nil end
		if pType and issecretvalue and issecretvalue(pType) then pType = nil end
		-- 1) pToken 문자열로 조회
		if pToken then
			local customC = ns.Colors and ns.Colors.power and ns.Colors.power[pToken]
			if not customC then
				local C = ns.Constants
				customC = C and C.POWER_COLORS and C.POWER_COLORS[pToken]
			end
			if customC then
				return format("|cff%02x%02x%02x", math_floor((customC[1] or 1) * 255 + 0.5), math_floor((customC[2] or 1) * 255 + 0.5), math_floor((customC[3] or 1) * 255 + 0.5)) .. text .. "|r"
			end
			local c = PowerBarColor[pToken]
			if c and c.r then
				return format("|cff%02x%02x%02x", math_floor((c.r or 1) * 255 + 0.5), math_floor((c.g or 1) * 255 + 0.5), math_floor((c.b or 1) * 255 + 0.5)) .. text .. "|r"
			end
		end
		-- 2) pType 숫자로 폴백
		if pType then
			local c = PowerBarColor[pType]
			if c and c.r then
				return format("|cff%02x%02x%02x", math_floor((c.r or 1) * 255 + 0.5), math_floor((c.g or 1) * 255 + 0.5), math_floor((c.b or 1) * 255 + 0.5)) .. text .. "|r"
			end
		end
		return "|cff3e7eff" .. text .. "|r"
	elseif colorType == "class_color" then
		local _, class = UnitClass(unit)
		if class then
			local c = RAID_CLASS_COLORS[class]
			if c then
				return format("|cff%02x%02x%02x", math_floor(c.r * 255 + 0.5), math_floor(c.g * 255 + 0.5), math_floor(c.b * 255 + 0.5)) .. text .. "|r"
			end
		end
		return text
	elseif colorType == "reaction_color" then
		local reaction = UnitReaction(unit, "player")
		if reaction and NotSecretValue(reaction) then
			if reaction >= 5 then return "|cff4ab34a" .. text .. "|r"
			elseif reaction == 4 then return "|cffcccc33" .. text .. "|r"
			else return "|cffcc3333" .. text .. "|r" end
		end
		return text
	end
	return text
end

-----------------------------------------------
-- Class Color Helper (이름 태그용)
-----------------------------------------------

local function GetClassColorPrefix(unit, unitKey)
	local rawName = UnitName(unit)
	if rawName and not SafeVal(rawName) then return "" end

	-- DB에서 커스텀 색상 확인
	local unitDB = ns.db and ns.db[unitKey]
	if unitDB then
		local nameColor = unitDB.widgets and unitDB.widgets.nameText and unitDB.widgets.nameText.color
		if nameColor and nameColor.type == "custom" and nameColor.rgb then
			local c = nameColor.rgb
			return format("|cff%02x%02x%02x",
				math_floor(c[1] * 255 + 0.5),
				math_floor(c[2] * 255 + 0.5),
				math_floor(c[3] * 255 + 0.5))
		end
	end
	if SafeVal(UnitIsConnected(unit)) == false then return "|cff999999" end -- [12.0.1] secret boolean
	local _, class = UnitClass(unit)
	if class then
		local color = RAID_CLASS_COLORS[class]
		if color then
			return format("|cff%02x%02x%02x", math_floor(color.r * 255 + 0.5), math_floor(color.g * 255 + 0.5), math_floor(color.b * 255 + 0.5))
		end
	end
	local reaction = UnitReaction(unit, "player")
	if reaction and NotSecretValue(reaction) then
		if reaction >= 5 then return "|cff4ab34a"
		elseif reaction == 4 then return "|cffcccc33"
		else return "|cffcc3333" end
	end
	return "|cff999999"
end

-----------------------------------------------
-- Health Format Functions
-- 키: ns.HEALTH_FORMAT_TO_TAG의 키와 1:1 대응
-----------------------------------------------

TextFormats.health = {}

TextFormats.health["percentage"] = function(unit, sep, htDB) -- [SECRET-V4]
	local pctStr = SafeFormatHealthPercent(unit)
	if pctStr then return pctStr end
	return AbbreviateNumbers(UnitHealth(unit))
end

TextFormats.health["current"] = function(unit, sep, htDB) -- [SECRET-V4]
	return AbbreviateNumbers(UnitHealth(unit))
end

TextFormats.health["current-max"] = function(unit, sep, htDB) -- [SECRET-V4]
	return AbbreviateNumbers(UnitHealth(unit)) .. sep .. AbbreviateNumbers(UnitHealthMax(unit))
end

-- [REMOVED] health deficit: ⚠️ secret 환경에서 빈 문자열

TextFormats.health["current-percentage"] = function(unit, sep, htDB) -- [SECRET-V4]
	local curStr = AbbreviateNumbers(UnitHealth(unit))
	local pctStr = SafeFormatHealthPercent(unit)
	if pctStr then return curStr .. " (" .. pctStr .. ")" end
	return curStr
end

TextFormats.health["percent-current"] = function(unit, sep, htDB) -- [SECRET-V4]
	local pctStr = SafeFormatHealthPercent(unit)
	local curStr = AbbreviateNumbers(UnitHealth(unit))
	if pctStr then return pctStr .. sep .. curStr end
	return curStr
end

TextFormats.health["current-percent"] = function(unit, sep, htDB) -- [SECRET-V4]
	local curStr = AbbreviateNumbers(UnitHealth(unit))
	local pctStr = SafeFormatHealthPercent(unit)
	if pctStr then return curStr .. sep .. pctStr end
	return curStr
end

TextFormats.health["smart"] = function(unit, sep, htDB) -- [SECRET-V4]
	local curStr = AbbreviateNumbers(UnitHealth(unit))
	local pctStr = SafeFormatHealthPercent(unit)
	if pctStr then return curStr .. sep .. pctStr end
	return curStr
end

-- [REMOVED] health raid: ⚠️ secret 시 빈 문자열 (percent-full 사용 권장)

-- [REMOVED] health healer: ⚠️ secret 환경에서 빈 문자열

TextFormats.health["percent-full"] = function(unit, sep, htDB) -- [SECRET-V4]
	local pctStr = SafeFormatHealthPercent(unit)
	if pctStr then return pctStr end
	return AbbreviateNumbers(UnitHealth(unit))
end

-----------------------------------------------
-- Power Format Functions
-----------------------------------------------

TextFormats.power = {}

TextFormats.power["percentage"] = function(unit, sep, ptDB) -- [SECRET-V4]
	local pctStr = SafeFormatPowerPercent(unit)
	if pctStr then return pctStr end
	return AbbreviateNumbers(UnitPower(unit))
end

TextFormats.power["current"] = function(unit, sep, ptDB) -- [SECRET-V4]
	return AbbreviateNumbers(UnitPower(unit))
end

TextFormats.power["current-max"] = function(unit, sep, ptDB) -- [SECRET-V4]
	return AbbreviateNumbers(UnitPower(unit)) .. " " .. sep .. " " .. AbbreviateNumbers(UnitPowerMax(unit))
end

-- [REMOVED] power deficit: ⚠️ secret 환경에서 빈 문자열

TextFormats.power["current-percentage"] = function(unit, sep, ptDB) -- [SECRET-V4]
	local curStr = AbbreviateNumbers(UnitPower(unit))
	local pctStr = SafeFormatPowerPercent(unit)
	if pctStr then return curStr .. " (" .. pctStr .. ")" end
	return curStr
end

TextFormats.power["percent-current"] = function(unit, sep, ptDB) -- [SECRET-V4]
	local pctStr = SafeFormatPowerPercent(unit)
	local curStr = AbbreviateNumbers(UnitPower(unit))
	if pctStr then return pctStr .. sep .. curStr end
	return curStr
end

TextFormats.power["current-percent"] = function(unit, sep, ptDB) -- [SECRET-V4]
	local curStr = AbbreviateNumbers(UnitPower(unit))
	local pctStr = SafeFormatPowerPercent(unit)
	if pctStr then return curStr .. sep .. pctStr end
	return curStr
end

TextFormats.power["smart"] = function(unit, sep, ptDB) -- [SECRET-V4]
	local curStr = AbbreviateNumbers(UnitPower(unit))
	local pctStr = SafeFormatPowerPercent(unit)
	if pctStr then return curStr .. sep .. pctStr end
	return curStr
end

-----------------------------------------------
-- Name Format Functions
-----------------------------------------------

TextFormats.name = {}

TextFormats.name["name"] = function(unit, unitKey)
	local name = SafeUnitName(unit)
	local prefix = GetClassColorPrefix(unit, unitKey)
	if IsSecretName(name) then return prefix .. name .. "|r" end
	return prefix .. name .. "|r"
end

TextFormats.name["name:short"] = function(unit, unitKey)
	local name = SafeUnitName(unit)
	local prefix = GetClassColorPrefix(unit, unitKey)
	if IsSecretName(name) then return prefix .. name .. "|r" end
	return prefix .. TruncateUTF8(name, 8) .. "|r"
end

TextFormats.name["name:medium"] = function(unit, unitKey)
	local name = SafeUnitName(unit)
	local prefix = GetClassColorPrefix(unit, unitKey)
	if IsSecretName(name) then return prefix .. name .. "|r" end
	if UTF8Len(name) > 14 then
		return prefix .. TruncateUTF8(name, 14) .. ".." .. "|r"
	end
	return prefix .. name .. "|r"
end

TextFormats.name["name:raid"] = function(unit, unitKey)
	local name = SafeUnitName(unit)
	local prefix = GetClassColorPrefix(unit, unitKey)
	if IsSecretName(name) then return prefix .. name .. "|r" end
	return prefix .. TruncateUTF8(name, 6) .. "|r"
end

TextFormats.name["name:veryshort"] = function(unit, unitKey)
	local name = SafeUnitName(unit)
	local prefix = GetClassColorPrefix(unit, unitKey)
	if IsSecretName(name) then return prefix .. name .. "|r" end
	return prefix .. TruncateUTF8(name, 4) .. "|r"
end

TextFormats.name["name:long"] = function(unit, unitKey)
	local name = SafeUnitName(unit)
	local prefix = GetClassColorPrefix(unit, unitKey)
	if IsSecretName(name) then return prefix .. name .. "|r" end
	return prefix .. TruncateUTF8(name, 20) .. "|r"
end

TextFormats.name["name:abbrev"] = function(unit, unitKey)
	local name = SafeUnitName(unit)
	local prefix = GetClassColorPrefix(unit, unitKey)
	if IsSecretName(name) then return prefix .. name .. "|r" end
	local byte = name:byte(1)
	if byte and byte >= 0xEA then
		return prefix .. TruncateUTF8(name, 3) .. "|r"
	end
	local abbrev = name:gsub("(%S+) ", function(word)
		return word:sub(1, 1) .. ". "
	end)
	return prefix .. abbrev .. "|r"
end

TextFormats.name["name:role"] = function(unit, unitKey)
	local name = SafeUnitName(unit)
	local prefix = GetClassColorPrefix(unit, unitKey)
	if not IsSecretName(name) then
		name = TruncateUTF8(name, 8)
	end
	local role = UnitGroupRolesAssigned(unit)
	local ROLE_ICONS = {
		TANK    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:0:0:0:0:64:64:0:19:22:41|t",
		HEALER  = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:0:0:0:0:64:64:20:39:1:20|t",
		DAMAGER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:0:0:0:0:64:64:20:39:22:41|t",
	}
	local icon = ROLE_ICONS[role]
	if icon then
		if IsSecretName(name) then return prefix .. name .. "|r" end
		return prefix .. icon .. " " .. name .. "|r"
	end
	return prefix .. name .. "|r"
end

-----------------------------------------------
-- Format Name Lookup (ns.NAME_FORMAT_TO_TAG 키와 호환)
-- Tags.lua의 NAME_FORMAT_TO_TAG 매핑:
--   "name" → "[ddingui:classcolor][ddingui:name]|r" = name:name
--   "name:abbrev" → classcolor + abbrev = name:abbrev
--   "name:short" → classcolor + short = name:short
-----------------------------------------------

-- NAME_FORMAT_TO_TAG 키 → TextFormats.name 키 변환
local NAME_FORMAT_MAP = {
	["name"]        = "name",
	["name:abbrev"] = "name:abbrev",
	["name:short"]  = "name:short",
}

-----------------------------------------------
-- Updater Factory: DB 설정을 live-lookup하여 텍스트 생성
-----------------------------------------------

-- Health updater: GetStatus + format + WrapColor
function TextFormats:CreateHealthUpdater(unitKey)
	return function(unit)
		if not unit or not UnitExists(unit) then return "" end
		local status = GetStatus(unit)
		if status then return status end

		-- Live-lookup: 설정은 런타임에 변경될 수 있음
		local htDB = ns.db and ns.db[unitKey] and ns.db[unitKey].widgets and ns.db[unitKey].widgets.healthText
		local fmt = htDB and htDB.format or "percentage"
		local sep = htDB and htDB.separator or "/"
		local formatFunc = TextFormats.health[fmt] or TextFormats.health["percentage"]

		local text = formatFunc(unit, sep, htDB)
		if not text then return "" end
		return WrapHealthColor(text, unit, htDB)
	end
end

-- Power updater: connected + max check + format + WrapColor
function TextFormats:CreatePowerUpdater(unitKey)
	return function(unit)
		if not unit or not UnitExists(unit) then return "" end
		if SafeVal(UnitIsConnected(unit)) == false then return "" end -- [12.0.1] secret boolean
		local max = UnitPowerMax(unit)
		if not max or max == 0 then return "" end

		local ptDB = ns.db and ns.db[unitKey] and ns.db[unitKey].widgets and ns.db[unitKey].widgets.powerText
		local fmt = ptDB and ptDB.format or "percentage"
		local sep = ptDB and ptDB.separator or "/"
		local formatFunc = TextFormats.power[fmt] or TextFormats.power["percentage"]

		local text = formatFunc(unit, sep, ptDB)
		if not text then return "" end
		return WrapPowerColor(text, unit, ptDB)
	end
end

-- Name updater: classcolor + name format
function TextFormats:CreateNameUpdater(unitKey)
	return function(unit)
		if not unit or not UnitExists(unit) then return "" end

		local nameDB = ns.db and ns.db[unitKey] and ns.db[unitKey].widgets and ns.db[unitKey].widgets.nameText
		local nameFmt = nameDB and nameDB.format
		local nameKey = NAME_FORMAT_MAP[nameFmt] or "name"

		-- showLevel 처리
		local showLevel = nameDB and nameDB.showLevel
		local nameFunc = TextFormats.name[nameKey] or TextFormats.name["name"]
		local result = nameFunc(unit, unitKey)

		if showLevel then
			local level = UnitEffectiveLevel and UnitEffectiveLevel(unit)
			if level and level > 0 then
				-- classcolor prefix는 이미 nameFunc 안에 포함
				-- level을 이름 앞에 삽입: "|cff...|r" 구조에서 prefix 뒤에 넣기
				local prefix, rest = result:match("^(|cff%x%x%x%x%x%x)(.+)$")
				if prefix and rest then
					local c = UnitClassification and UnitClassification(unit)
					local levelStr = tostring(level)
					if c == "rareelite" then levelStr = levelStr .. "R+"
					elseif c == "elite" then levelStr = levelStr .. "+"
					elseif c == "rare" then levelStr = levelStr .. "R"
					end
					return prefix .. levelStr .. " " .. rest
				end
			end
		end

		return result
	end
end

-----------------------------------------------
-- BindToFrame: 프레임에 텍스트 업데이터 연결
-- (레거시 유틸리티 — oUF Tags 모드에서는 사용 안 함)
-----------------------------------------------

function TextFormats:BindToFrame(frame, unitKey)
	if not unitKey then
		unitKey = frame._unitKey or (frame._unit and frame._unit:gsub("%d+$", "")) or "player"
	end

	-- Health text updater
	frame._healthTextUpdater = self:CreateHealthUpdater(unitKey)

	-- Power text updater
	frame._powerTextUpdater = self:CreatePowerUpdater(unitKey)

	-- Name text updater
	frame._nameTextUpdater = self:CreateNameUpdater(unitKey)
end

-- 개별 재바인딩 (설정 변경 시 특정 텍스트만)
function TextFormats:RebindHealth(frame, unitKey)
	unitKey = unitKey or frame._unitKey or "player"
	frame._healthTextUpdater = self:CreateHealthUpdater(unitKey)
end

function TextFormats:RebindPower(frame, unitKey)
	unitKey = unitKey or frame._unitKey or "player"
	frame._powerTextUpdater = self:CreatePowerUpdater(unitKey)
end

function TextFormats:RebindName(frame, unitKey)
	unitKey = unitKey or frame._unitKey or "player"
	frame._nameTextUpdater = self:CreateNameUpdater(unitKey)
end

-----------------------------------------------
-- FORMAT_TO_TAG 호환 테이블 (Options UI 연동)
-- Tags.lua의 ns.HEALTH_FORMAT_TO_TAG 등을 대체하지 않음
-- 기존 UI는 태그 문자열 사용 → 프리셋 포맷명 사용으로 전환
-----------------------------------------------

-- 포맷명 목록 (Options UI 드롭다운용)
TextFormats.HEALTH_FORMATS = {
	"percentage", "current", "current-max",
	"current-percentage", "percent-current", "current-percent",
	"smart", "percent-full",
}

TextFormats.POWER_FORMATS = {
	"percentage", "current", "current-max",
	"current-percentage", "percent-current", "current-percent",
	"smart",
}

TextFormats.NAME_FORMATS = {
	"name", "name:abbrev", "name:short",
}

-----------------------------------------------
-- Expose helpers for external use
-----------------------------------------------

TextFormats.SafeFormatHealthPercent = SafeFormatHealthPercent
TextFormats.SafeFormatPowerPercent = SafeFormatPowerPercent
TextFormats.NotSecretValue = NotSecretValue
TextFormats.GetStatus = GetStatus
TextFormats.SafeUnitName = SafeUnitName
TextFormats.TruncateUTF8 = TruncateUTF8
TextFormats.UTF8Len = UTF8Len
TextFormats.GetClassColorPrefix = GetClassColorPrefix

-- ns에도 expose (기존 코드 호환)
ns.NotSecretValue = ns.NotSecretValue or NotSecretValue

-----------------------------------------------
-- Methods Table (oUF.Tags.Methods 대체)
-- Update.lua의 UpdateCustomText 유효성 검증 + debugtag 진단용
-- 키: 태그 이름 (e.g. "ddingui:ht:pct"), 값: function(unit) → string
-----------------------------------------------

TextFormats.Methods = {}

-- unit → DB unitKey 변환 (party1→party, boss2→boss 등)
local function GetUnitKey(unit)
	if not unit then return nil end
	return unit:gsub("%d+$", "")
end

-- unit → healthText separator 읽기 (설정값 실시간 반영)
local function GetHealthSep(unit)
	local key = GetUnitKey(unit)
	if not key or not ns.db or not ns.db[key] then return "/" end
	local htDB = ns.db[key].widgets and ns.db[key].widgets.healthText
	return htDB and htDB.separator or "/"
end

-- unit → powerText separator 읽기 (설정값 실시간 반영)
local function GetPowerSep(unit)
	local key = GetUnitKey(unit)
	if not key or not ns.db or not ns.db[key] then return "/" end
	local ptDB = ns.db[key].widgets and ns.db[key].widgets.powerText
	return ptDB and ptDB.separator or "/"
end

-- Health tag methods (HEALTH_FORMAT_TO_TAG 키와 1:1 대응)
TextFormats.Methods["ddingui:ht:pct"]     = function(unit) return (TextFormats.health["percentage"] or TextFormats.health["smart"])(unit, GetHealthSep(unit)) end
TextFormats.Methods["ddingui:ht:cur"]     = function(unit) return (TextFormats.health["current"])(unit, GetHealthSep(unit)) end
TextFormats.Methods["ddingui:ht:curmax"]  = function(unit) return (TextFormats.health["current-max"])(unit, GetHealthSep(unit)) end
TextFormats.Methods["ddingui:ht:deficit"] = function(unit) return (TextFormats.health["deficit"])(unit, GetHealthSep(unit)) end
TextFormats.Methods["ddingui:ht:curpct"]  = function(unit) return (TextFormats.health["current-percentage"])(unit, GetHealthSep(unit)) end
TextFormats.Methods["ddingui:ht:pctcur"]  = function(unit) return (TextFormats.health["percent-current"])(unit, GetHealthSep(unit)) end
TextFormats.Methods["ddingui:ht:curp"]    = function(unit) return (TextFormats.health["current-percent"])(unit, GetHealthSep(unit)) end
TextFormats.Methods["ddingui:ht:smart"]   = function(unit) return (TextFormats.health["smart"])(unit, GetHealthSep(unit)) end
-- [REMOVED] ddingui:ht:raid, ddingui:ht:healer
TextFormats.Methods["ddingui:ht:pctfull"] = function(unit) return (TextFormats.health["percent-full"])(unit, GetHealthSep(unit)) end

-- Health alternate names (TagPresets에서 사용)
TextFormats.Methods["ddingui:health"]              = TextFormats.Methods["ddingui:ht:smart"]
TextFormats.Methods["ddingui:health:percent"]       = TextFormats.Methods["ddingui:ht:pct"]
TextFormats.Methods["ddingui:health:percent-full"]  = TextFormats.Methods["ddingui:ht:pctfull"]
TextFormats.Methods["ddingui:health:current"]       = TextFormats.Methods["ddingui:ht:cur"]
TextFormats.Methods["ddingui:health:current-max"]   = TextFormats.Methods["ddingui:ht:curmax"]
TextFormats.Methods["ddingui:health:current-percent"] = TextFormats.Methods["ddingui:ht:curpct"]
-- [REMOVED] ddingui:health:healeronly

-- Power tag methods (POWER_FORMAT_TO_TAG 키와 1:1 대응)
TextFormats.Methods["ddingui:pt:pct"]     = function(unit) return (TextFormats.power["percentage"])(unit, GetPowerSep(unit)) end
TextFormats.Methods["ddingui:pt:cur"]     = function(unit) return (TextFormats.power["current"])(unit, GetPowerSep(unit)) end
TextFormats.Methods["ddingui:pt:curmax"]  = function(unit) return (TextFormats.power["current-max"])(unit, GetPowerSep(unit)) end
-- [REMOVED] ddingui:pt:deficit
TextFormats.Methods["ddingui:pt:curpct"]  = function(unit) return (TextFormats.power["current-percentage"])(unit, GetPowerSep(unit)) end
TextFormats.Methods["ddingui:pt:pctcur"]  = function(unit) return (TextFormats.power["percent-current"])(unit, GetPowerSep(unit)) end
TextFormats.Methods["ddingui:pt:curp"]    = function(unit) return (TextFormats.power["current-percent"])(unit, GetPowerSep(unit)) end
TextFormats.Methods["ddingui:pt:smart"]   = function(unit) return (TextFormats.power["smart"])(unit, GetPowerSep(unit)) end

-- Name tag methods
TextFormats.Methods["ddingui:name"]           = function(unit) return (TextFormats.name["name"])(unit, "player") end
TextFormats.Methods["ddingui:name:short"]     = function(unit) return (TextFormats.name["name:short"])(unit, "player") end
TextFormats.Methods["ddingui:name:medium"]    = function(unit) return (TextFormats.name["name:medium"])(unit, "player") end
TextFormats.Methods["ddingui:name:long"]      = function(unit) return (TextFormats.name["name:long"])(unit, "player") end
TextFormats.Methods["ddingui:name:veryshort"] = function(unit) return (TextFormats.name["name:veryshort"])(unit, "player") end
TextFormats.Methods["ddingui:name:abbrev"]    = function(unit) return (TextFormats.name["name:abbrev"])(unit, "player") end
TextFormats.Methods["ddingui:name:raid"]      = function(unit) return (TextFormats.name["name:raid"])(unit, "player") end
TextFormats.Methods["ddingui:name:role"]      = function(unit) return (TextFormats.name["name:role"])(unit, "player") end

-- Class color prefix tag (compound tags에서 사용)
TextFormats.Methods["ddingui:classcolor"] = function(unit)
	return GetClassColorPrefix(unit, "player")
end

-- Absorb tags (보호막)
TextFormats.Methods["ddingui:absorb"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	if not UnitGetTotalAbsorbs then return "" end
	-- [PERF] pcall 제거: AbbreviateNumbers(C-API)가 secret 직접 처리
	local absorb = UnitGetTotalAbsorbs(unit)
	if not absorb then return "" end
	return AbbreviateNumbers(absorb)
end

-- [REMOVED] ddingui:absorb:percent: ❌ secret 시 퍼센트 아닌 축약값

-- Health + Absorb 합산 태그
TextFormats.Methods["ddingui:health:absorb"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	local status = GetStatus(unit)
	if status then return status end
	local curStr = AbbreviateNumbers(UnitHealth(unit))
	local absStr = ""
	if UnitGetTotalAbsorbs then
		-- [PERF] pcall 제거: AbbreviateNumbers(C-API)가 secret 직접 처리
		local absorb = UnitGetTotalAbsorbs(unit)
		if absorb then
			if issecretvalue and issecretvalue(absorb) then
				absStr = " +" .. AbbreviateNumbers(absorb)
			else
				absorb = tonumber(absorb) or 0
				if absorb > 0 then
					absStr = " +" .. AbbreviateNumbers(absorb)
				end
			end
		end
	end
	return curStr .. absStr
end

-- Health DB format auto (현재 설정에 맞는 포맷)
TextFormats.Methods["ddingui:health:db"] = TextFormats.Methods["ddingui:ht:pct"]

-- Health max
TextFormats.Methods["ddingui:health:max"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return AbbreviateNumbers(UnitHealthMax(unit))
end

-- Heal Absorb (괴사일격 등)
TextFormats.Methods["ddingui:healabsorb"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	if not UnitGetTotalHealAbsorbs then return "" end
	-- [PERF] pcall 제거: AbbreviateNumbers(C-API)가 secret 직접 처리
	local absorb = UnitGetTotalHealAbsorbs(unit)
	if not absorb then return "" end
	return AbbreviateNumbers(absorb)
end

-- Incoming Heal (수신 힐량)
TextFormats.Methods["ddingui:incheal"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	if not UnitGetIncomingHeals then return "" end
	-- [PERF] pcall 제거: AbbreviateNumbers(C-API)가 secret 직접 처리
	local heal = UnitGetIncomingHeals(unit)
	if not heal then return "" end
	return "+" .. AbbreviateNumbers(heal)
end

-- Power aliases (Options 태그 참조 패널과 일치)
TextFormats.Methods["ddingui:power"]             = TextFormats.Methods["ddingui:pt:cur"]
TextFormats.Methods["ddingui:power:percent"]     = TextFormats.Methods["ddingui:pt:pct"]
TextFormats.Methods["ddingui:power:current-max"] = TextFormats.Methods["ddingui:pt:curmax"]
-- [REMOVED] ddingui:power:deficit
TextFormats.Methods["ddingui:power:healeronly"]   = TextFormats.Methods["ddingui:pt:smart"]

-- Color prefix tags (compound tags에서 앞에 붙이고 |r로 종료)
-- [REMOVED] ddingui:powercolor: ⚠️ secret 시 기본 파란색 fallback

-- [REMOVED] ddingui:healthcolor: ⚠️ secret 시 기본 녹색 고정

-- [REMOVED] ddingui:reactioncolor: ⚠️ secret 시 기본 회색

-- Level (단순)
TextFormats.Methods["ddingui:level"] = function(unit)
	local level = UnitEffectiveLevel and UnitEffectiveLevel(unit)
	if not level or level <= 0 then return "" end
	return tostring(level)
end

-- Classification (+/R/B)
TextFormats.Methods["ddingui:classification"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	local c = UnitClassification and UnitClassification(unit)
	if c == "rareelite" then return "R+"
	elseif c == "elite" or c == "worldboss" then return "+"
	elseif c == "rare" then return "R"
	end
	return ""
end

-- Level tag (compound tags에서 사용)
TextFormats.Methods["ddingui:level:smart"] = function(unit)
	local level = UnitEffectiveLevel and UnitEffectiveLevel(unit)
	if not level or level <= 0 then return "" end
	local c = UnitClassification and UnitClassification(unit)
	local str = tostring(level)
	if c == "rareelite" then str = str .. "R+"
	elseif c == "elite" then str = str .. "+"
	elseif c == "rare" then str = str .. "R"
	end
	return str
end

-- [REMOVED] ddingui:status: ⚠️ secret boolean → Dead/Offline 감지 불가

-----------------------------------------------
-- oUF 내장 태그 호환 레이어
-- 커스텀 텍스트에서 [name], [dead], [curhp] 등 oUF 네이티브 태그를
-- 직접 사용하더라도 동작하도록 함
-----------------------------------------------

-- name (oUF built-in)
TextFormats.Methods["name"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return UnitName(unit) or ""
end

-- [REMOVED] dead, offline, status (oUF built-in): ⚠️ secret boolean

-- curhp (oUF built-in)
TextFormats.Methods["curhp"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return tostring(UnitHealth(unit))
end

-- maxhp (oUF built-in)
TextFormats.Methods["maxhp"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return tostring(UnitHealthMax(unit))
end

-- [REMOVED] missinghp, perhp (oUF built-in): ❌ secret 시 빈 문자열

-- curpp (oUF built-in)
TextFormats.Methods["curpp"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return tostring(UnitPower(unit))
end

-- maxpp (oUF built-in)
TextFormats.Methods["maxpp"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return tostring(UnitPowerMax(unit))
end

-- [REMOVED] missingpp, perpp (oUF built-in): ❌ secret 시 빈 문자열

-- level (oUF built-in)
TextFormats.Methods["level"] = TextFormats.Methods["ddingui:level"]

-- classification / shortclassification (oUF built-in)
TextFormats.Methods["classification"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	local c = UnitClassification and UnitClassification(unit)
	if c == "rare" then return "Rare"
	elseif c == "rareelite" then return "Rare Elite"
	elseif c == "elite" then return "Elite"
	elseif c == "worldboss" then return "Boss"
	elseif c == "minus" then return "Affix"
	end
	return ""
end

TextFormats.Methods["shortclassification"] = TextFormats.Methods["ddingui:classification"]

-- smartlevel (oUF built-in)
TextFormats.Methods["smartlevel"] = TextFormats.Methods["ddingui:level:smart"]

-- raidcolor (oUF built-in) — class color hex prefix
TextFormats.Methods["raidcolor"] = TextFormats.Methods["ddingui:classcolor"]

-- [REMOVED] powercolor (oUF built-in)

-- class (oUF built-in)
TextFormats.Methods["class"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return UnitClass(unit) or ""
end

-- creature (oUF built-in)
TextFormats.Methods["creature"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return UnitCreatureFamily(unit) or UnitCreatureType(unit) or ""
end

-- smartclass (oUF built-in)
TextFormats.Methods["smartclass"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	if UnitIsPlayer(unit) then
		return UnitClass(unit) or ""
	end
	return UnitCreatureFamily(unit) or UnitCreatureType(unit) or ""
end

-- race (oUF built-in)
TextFormats.Methods["race"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return UnitRace(unit) or ""
end

-- faction (oUF built-in)
TextFormats.Methods["faction"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return UnitFactionGroup(unit) or ""
end

-- [REMOVED] sex: ⚠️ UnitSex secret 가능

-- resting (oUF built-in)
TextFormats.Methods["resting"] = function(unit)
	if unit == "player" and IsResting() then return "zzz" end
	return ""
end

-- [REMOVED] pvp, leader, leaderlong: ⚠️ secret boolean

-- plus / rare / affix (oUF built-in)
TextFormats.Methods["plus"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	local c = UnitClassification and UnitClassification(unit)
	if c == "elite" or c == "rareelite" then return "+" end
	return ""
end

TextFormats.Methods["rare"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	local c = UnitClassification and UnitClassification(unit)
	if c == "rare" or c == "rareelite" then return "Rare" end
	return ""
end

TextFormats.Methods["affix"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	local c = UnitClassification and UnitClassification(unit)
	if c == "minus" then return "Affix" end
	return ""
end

-- threat / threatcolor (oUF built-in)
TextFormats.Methods["threat"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	local s = UnitThreatSituation(unit)
	if s == 1 then return "++"
	elseif s == 2 then return "--"
	elseif s == 3 then return "Aggro"
	end
	return ""
end

TextFormats.Methods["threatcolor"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	local s = UnitThreatSituation(unit) or 0
	local r, g, b = GetThreatStatusColor(s)
	return format("|cff%02x%02x%02x", math_floor((r or 1) * 255 + 0.5), math_floor((g or 1) * 255 + 0.5), math_floor((b or 1) * 255 + 0.5))
end

-- difficulty (oUF built-in)
TextFormats.Methods["difficulty"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	if UnitCanAttack("player", unit) then
		local l = UnitEffectiveLevel(unit)
		local color = GetCreatureDifficultyColor((l and l > 0) and l or 999)
		if color then
			return format("|cff%02x%02x%02x", math_floor((color.r or 1) * 255 + 0.5), math_floor((color.g or 1) * 255 + 0.5), math_floor((color.b or 1) * 255 + 0.5))
		end
	end
	return ""
end

-- [REMOVED] group: ⚠️ UnitIsUnit secret 가능

-- curmana / maxmana (oUF built-in)
TextFormats.Methods["curmana"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return tostring(UnitPower(unit, Enum.PowerType.Mana))
end

TextFormats.Methods["maxmana"] = function(unit)
	if not unit or not UnitExists(unit) then return "" end
	return tostring(UnitPowerMax(unit, Enum.PowerType.Mana))
end

-- arenaspec (oUF built-in)
TextFormats.Methods["arenaspec"] = function(unit)
	if not unit then return "" end
	local id = unit:match("arena(%d)$")
	if id and GetArenaOpponentSpec then
		local specID = GetArenaOpponentSpec(tonumber(id))
		if specID and specID > 0 and GetSpecializationInfoByID then
			local _, specName = GetSpecializationInfoByID(specID)
			return specName or ""
		end
	end
	return ""
end

-- [AUDIT-FIX] W6: 삭제된 태그 NOOP stub (기존 사용자 DB에 저장된 태그 참조 방어)
local function NOOP_TAG() return "" end
local DELETED_TAGS = {
	"ddingui:status", "ddingui:healthcolor", "ddingui:reactioncolor", "ddingui:powercolor",
	"ddingui:health:deficit", "ddingui:health:raid", "ddingui:health:healeronly",
	"ddingui:power:deficit", "ddingui:absorb:percent",
	"ddingui:ht:deficit", "ddingui:ht:raid", "ddingui:ht:healer",
	"ddingui:pt:deficit",
	"dead", "offline", "status", "powercolor",
	"missinghp", "missingpp", "perhp", "perpp",
	"pvp", "leader", "leaderlong", "sex", "group",
}
for _, tagName in ipairs(DELETED_TAGS) do
	if not TextFormats.Methods[tagName] then
		TextFormats.Methods[tagName] = NOOP_TAG
	end
end

-----------------------------------------------
-- CreateCompoundUpdater: 복합 태그 문자열 → 평가 함수
-- "[ddingui:classcolor][ddingui:name]|r" → function(unit) return colorPrefix..name.."|r" end
-----------------------------------------------

function TextFormats:CreateCompoundUpdater(tagString)
	if not tagString or tagString == "" then return nil end

	-- 태그 파트 파싱: [tag1] literal [tag2] literal ...
	local parts = {}
	local pos = 1
	local len = #tagString

	while pos <= len do
		local bracketStart = tagString:find("%[", pos)
		if bracketStart then
			-- 브래킷 전 리터럴 텍스트
			if bracketStart > pos then
				local literal = tagString:sub(pos, bracketStart - 1)
				parts[#parts + 1] = { type = "literal", value = literal }
			end
			-- 브래킷 안 태그 이름
			local bracketEnd = tagString:find("%]", bracketStart)
			if bracketEnd then
				local tagName = tagString:sub(bracketStart + 1, bracketEnd - 1)
				parts[#parts + 1] = { type = "tag", name = tagName }
				pos = bracketEnd + 1
			else
				-- 닫는 브래킷 없음 → 나머지를 리터럴로
				parts[#parts + 1] = { type = "literal", value = tagString:sub(pos) }
				break
			end
		else
			-- 남은 문자열은 리터럴
			parts[#parts + 1] = { type = "literal", value = tagString:sub(pos) }
			break
		end
	end

	if #parts == 0 then return nil end

	-- 단일 태그 → 직접 반환 (최적화)
	if #parts == 1 and parts[1].type == "tag" then
		return self.Methods[parts[1].name]
	end

	-- 복합 태그 → 결합 함수 생성
	return function(unit)
		local result = ""
		for _, part in ipairs(parts) do
			if part.type == "literal" then
				result = result .. part.value
			elseif part.type == "tag" then
				local fn = TextFormats.Methods[part.name]
				if fn then
					local ok, val = pcall(fn, unit)
					if ok and val then
						result = result .. val
					end
				end
			end
		end
		return result
	end
end

-----------------------------------------------
-- oUF.Tags.Methods / Events 등록 (롤백)
-- TextFormats.Methods → oUF.Tags.Methods로 1:1 등록
-- Layout.lua의 self:Tag()가 oUF 태그 엔진 사용
-----------------------------------------------

local oUF = ns.oUF
if oUF and oUF.Tags then
	-- Health tag events
	local HEALTH_EVENTS = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS"
	-- Power tag events
	local POWER_EVENTS = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION"
	-- Name tag events
	local NAME_EVENTS = "UNIT_NAME_UPDATE UNIT_CONNECTION"

	-- Register all Methods with oUF.Tags
	for tagName, tagFunc in pairs(TextFormats.Methods) do
		oUF.Tags.Methods[tagName] = tagFunc

		-- Assign events based on tag name prefix
		if tagName:find("^ddingui:ht:") or tagName:find("^ddingui:health") then
			oUF.Tags.Events[tagName] = HEALTH_EVENTS
		elseif tagName:find("^ddingui:pt:") or tagName:find("^ddingui:power") then
			oUF.Tags.Events[tagName] = POWER_EVENTS
		elseif tagName:find("^ddingui:name") then
			oUF.Tags.Events[tagName] = NAME_EVENTS
		elseif tagName == "ddingui:classcolor" then
			oUF.Tags.Events[tagName] = NAME_EVENTS
		elseif tagName:find("^ddingui:absorb") then
			oUF.Tags.Events[tagName] = "UNIT_ABSORB_AMOUNT_CHANGED UNIT_HEALTH UNIT_MAXHEALTH"
		elseif tagName == "ddingui:healabsorb" then
			oUF.Tags.Events[tagName] = "UNIT_HEAL_ABSORB_AMOUNT_CHANGED UNIT_HEALTH UNIT_MAXHEALTH"
		elseif tagName == "ddingui:incheal" then
			oUF.Tags.Events[tagName] = "UNIT_HEAL_PREDICTION UNIT_HEALTH UNIT_MAXHEALTH"
		elseif tagName == "ddingui:level:smart" or tagName == "ddingui:level" or tagName == "ddingui:classification" then
			oUF.Tags.Events[tagName] = "" -- no events (static)
		end
	end

-- [REMOVED] ddingui:status oUF fallback registration

	ns.Debug("TextFormats → oUF.Tags registered (" .. (function()
		local c = 0
		for _ in pairs(TextFormats.Methods) do c = c + 1 end
		return c
	end)() .. " tags)")
else
	ns.Debug("TextFormats.lua loaded (oUF not available, standalone mode)")
end
