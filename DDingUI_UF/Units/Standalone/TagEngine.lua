--[[
	ddingUI UnitFrames
	Units/Standalone/TagEngine.lua — oUF Tag 시스템 대체
	self:Tag(fontString, tagStr) 메서드를 독자적으로 제공
	TextFormats.lua의 Methods 테이블과 CreateCompoundUpdater를 직접 사용
]]

local _, ns = ...

local TagEngine = {}
ns.TagEngine = TagEngine

-- 등록된 태그 바인딩: { frame → { { fontString=fs, updater=fn, events={...} } } }
local bindings = {}
TagEngine._bindings = bindings

-- 이벤트 → 태그이름 매핑 (TextFormats.lua 하단과 동일)
local TAG_EVENTS = {
	-- Health tags
	["ddingui:ht:pct"]     = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:cur"]     = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:curmax"]  = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:deficit"] = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:curpct"]  = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:pctcur"]  = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:curp"]    = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:smart"]   = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:raid"]    = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:healer"]  = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	["ddingui:ht:pctfull"] = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS",
	-- Power tags
	["ddingui:pt:pct"]     = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	["ddingui:pt:cur"]     = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	["ddingui:pt:curmax"]  = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	["ddingui:pt:deficit"] = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	["ddingui:pt:curpct"]  = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	["ddingui:pt:pctcur"]  = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	["ddingui:pt:curp"]    = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	["ddingui:pt:smart"]   = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	-- Name tags
	["ddingui:name"]           = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:name:short"]     = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:name:medium"]    = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:name:long"]      = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:name:veryshort"] = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:name:abbrev"]    = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:name:raid"]      = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:name:role"]      = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	-- Color prefix tags
	["ddingui:classcolor"]     = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:reactioncolor"]  = "UNIT_NAME_UPDATE UNIT_CONNECTION",
	["ddingui:powercolor"]     = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_CONNECTION",
	["ddingui:healthcolor"]    = "UNIT_HEALTH UNIT_MAXHEALTH",
	-- Absorb tags
	["ddingui:absorb"]             = "UNIT_ABSORB_AMOUNT_CHANGED UNIT_HEALTH UNIT_MAXHEALTH",
	["ddingui:absorb:percent"]     = "UNIT_ABSORB_AMOUNT_CHANGED UNIT_HEALTH UNIT_MAXHEALTH",
	["ddingui:healabsorb"]         = "UNIT_HEAL_ABSORB_AMOUNT_CHANGED UNIT_HEALTH UNIT_MAXHEALTH",
	["ddingui:incheal"]            = "UNIT_HEAL_PREDICTION UNIT_HEALTH UNIT_MAXHEALTH",
	["ddingui:health:absorb"]      = "UNIT_ABSORB_AMOUNT_CHANGED UNIT_HEALTH UNIT_MAXHEALTH",
	-- Status
	["ddingui:status"]             = "UNIT_HEALTH UNIT_CONNECTION UNIT_FLAGS",
	-- Static (no events)
	["ddingui:level:smart"]        = "",
	["ddingui:level"]              = "",
	["ddingui:classification"]     = "",

	-- oUF 내장 태그 이벤트 (커스텀 텍스트 호환)
	["name"]                = "UNIT_NAME_UPDATE",
	["dead"]                = "UNIT_HEALTH",
	["offline"]             = "UNIT_HEALTH UNIT_CONNECTION",
	["status"]              = "UNIT_HEALTH UNIT_CONNECTION UNIT_FLAGS",
	["curhp"]               = "UNIT_HEALTH UNIT_MAXHEALTH",
	["maxhp"]               = "UNIT_MAXHEALTH",
	["missinghp"]           = "UNIT_HEALTH UNIT_MAXHEALTH",
	["perhp"]               = "UNIT_HEALTH UNIT_MAXHEALTH",
	["curpp"]               = "UNIT_POWER_UPDATE UNIT_MAXPOWER",
	["maxpp"]               = "UNIT_MAXPOWER",
	["missingpp"]           = "UNIT_MAXPOWER UNIT_POWER_UPDATE",
	["perpp"]               = "UNIT_MAXPOWER UNIT_POWER_UPDATE",
	["level"]               = "",
	["classification"]      = "",
	["shortclassification"] = "",
	["smartlevel"]          = "",
	["raidcolor"]           = "UNIT_NAME_UPDATE",
	["powercolor"]          = "UNIT_DISPLAYPOWER",
	["threatcolor"]         = "UNIT_THREAT_SITUATION_UPDATE",
	["threat"]              = "UNIT_THREAT_SITUATION_UPDATE",
	["difficulty"]          = "UNIT_FACTION",
	["class"]               = "",
	["creature"]            = "",
	["smartclass"]          = "",
	["race"]                = "",
	["faction"]             = "",
	["sex"]                 = "",
	["resting"]             = "",
	["pvp"]                 = "UNIT_FACTION",
	["leader"]              = "",
	["leaderlong"]          = "",
	["plus"]                = "",
	["rare"]                = "",
	["affix"]               = "",
	["group"]               = "",
	["curmana"]             = "UNIT_POWER_UPDATE UNIT_MAXPOWER",
	["maxmana"]             = "UNIT_POWER_UPDATE UNIT_MAXPOWER",
	["arenaspec"]           = "",
}

-- 별칭(aliases) 이벤트도 매핑
for alias, original in pairs({
	["ddingui:health"]                   = "ddingui:ht:smart",
	["ddingui:health:percent"]           = "ddingui:ht:pct",
	["ddingui:health:percent-full"]      = "ddingui:ht:pctfull",
	["ddingui:health:current"]           = "ddingui:ht:cur",
	["ddingui:health:current-max"]       = "ddingui:ht:curmax",
	["ddingui:health:current-percent"]   = "ddingui:ht:curpct",
	["ddingui:health:deficit"]           = "ddingui:ht:deficit",
	["ddingui:health:raid"]              = "ddingui:ht:raid",
	["ddingui:health:healeronly"]        = "ddingui:ht:healer",
	["ddingui:health:max"]               = "ddingui:ht:cur",
	["ddingui:health:db"]                = "ddingui:ht:pct",
	["ddingui:power"]                    = "ddingui:pt:cur",
	["ddingui:power:percent"]            = "ddingui:pt:pct",
	["ddingui:power:current-max"]        = "ddingui:pt:curmax",
	["ddingui:power:deficit"]            = "ddingui:pt:deficit",
	["ddingui:power:healeronly"]         = "ddingui:pt:smart",
}) do
	if TAG_EVENTS[original] then
		TAG_EVENTS[alias] = TAG_EVENTS[original]
	end
end

TagEngine.TAG_EVENTS = TAG_EVENTS

-----------------------------------------------
-- Parse tag string → list of events needed
-----------------------------------------------

local function CollectEventsFromTagString(tagStr)
	local eventSet = {}
	for tagName in tagStr:gmatch("%[([^%]]+)%]") do
		local events = TAG_EVENTS[tagName]
		if events then
			for ev in events:gmatch("%S+") do
				eventSet[ev] = true
			end
		end
	end
	return eventSet
end

-----------------------------------------------
-- Tag method: frame:Tag(fontString, tagStr)
-- TextFormats.CreateCompoundUpdater를 사용하여 복합 태그 파싱
-----------------------------------------------

function TagEngine:Register(frame, fontString, tagStr)
	if not frame or not fontString or not tagStr or tagStr == "" then return end

	local TF = ns.TextFormats
	if not TF then return end

	-- 복합 태그 파싱 → 단일 평가 함수 생성
	local updater = TF:CreateCompoundUpdater(tagStr)
	if not updater then return end

	-- 이벤트 수집
	local events = CollectEventsFromTagString(tagStr)

	-- 바인딩 저장
	if not bindings[frame] then bindings[frame] = {} end
	bindings[frame][#bindings[frame] + 1] = {
		fontString = fontString,
		updater = updater,
		events = events,
		tagStr = tagStr,
	}

	-- fontString에 UpdateTag 메서드 추가 (customText 등에서 사용)
	fontString.UpdateTag = function(self)
		local unit = frame.unit
		if not unit then return end
		local ok, text = pcall(updater, unit)
		if ok and text then
			self:SetText(text)
		else
			self:SetText("")
		end
	end

	-- 즉시 평가
	if frame.unit then
		local ok, text = pcall(updater, frame.unit)
		if ok and text then
			fontString:SetText(text)
		end
	end
end

-----------------------------------------------
-- Update: 특정 이벤트에 해당하는 모든 태그 갱신
-----------------------------------------------

function TagEngine:UpdateForEvent(frame, event)
	if not frame or not bindings[frame] then return end
	local unit = frame.unit
	if not unit then return end

	for _, binding in ipairs(bindings[frame]) do
		if binding.events[event] or event == "ALL" then
			local ok, text = pcall(binding.updater, unit)
			if ok and text then
				binding.fontString:SetText(text)
			else
				binding.fontString:SetText("")
			end
		end
	end
end

-----------------------------------------------
-- UpdateAll: 프레임의 모든 태그 갱신
-----------------------------------------------

function TagEngine:UpdateAll(frame)
	self:UpdateForEvent(frame, "ALL")
end

-----------------------------------------------
-- Unregister: 프레임의 모든 태그 해제
-----------------------------------------------

function TagEngine:UnregisterAll(frame)
	bindings[frame] = nil
end

ns.Debug("TagEngine.lua loaded")
