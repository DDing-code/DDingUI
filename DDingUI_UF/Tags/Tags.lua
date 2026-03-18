--[[
	ddingUI UnitFrames
	Tags/Tags.lua — 헬퍼 함수, 포맷 매핑, 태그 프리셋, 디버그 명령
	oUF.Tags 등록은 TextFormats.lua에서 수행
	12.0.1 Secret Value v4 유지 -- [SECRET-V4]
]]

local _, ns = ...

local F = ns.Functions

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
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local issecretvalue = issecretvalue
local SafeVal = ns.SafeVal

local format = format
local math_floor = math.floor
local pcall = pcall
local AbbreviateNumbers = AbbreviateNumbers
local UnitHealthPercent = UnitHealthPercent
local UnitPowerPercent = UnitPowerPercent
local FormatPercentage = FormatPercentage

local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100

-----------------------------------------------
-- NotSecretValue (pcall 기반 안전 검사) -- [SECRET-V4]
-----------------------------------------------

local function NotSecretValue(value)
	if value == nil then return true end
	if issecretvalue then return not issecretvalue(value) end
	return true -- issecretvalue 없으면 안전하다고 가정 (closure 제거)
end

ns.NotSecretValue = NotSecretValue

-----------------------------------------------
-- GetHealthSafe: StatusBar용 -- [SECRET-V4] closure 제거
-----------------------------------------------

local function GetHealthSafe(unit)
	local max = UnitHealthMax(unit)
	if not max or max == 0 then return 0, 0, 0 end
	local cur = UnitHealth(unit)
	if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then
		return cur, max, nil
	end
	return cur, max, math_floor(cur / max * 100 + 0.5)
end

ns.GetHealthSafe = GetHealthSafe

-----------------------------------------------
-- GetPowerSafe: StatusBar용 -- [SECRET-V4] closure 제거
-----------------------------------------------

local function GetPowerSafe(unit)
	local powerType = UnitPowerType(unit)
	local max = UnitPowerMax(unit, powerType)
	if not max or max == 0 then return 0, 0, 0 end
	local cur = UnitPower(unit, powerType)
	if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then
		return cur, max, nil
	end
	return cur, max, math_floor(cur / max * 100 + 0.5)
end

ns.GetPowerSafe = GetPowerSafe

-----------------------------------------------
-- FORMAT_TO_TAG 매핑 (Layout.lua, Update.lua 호환)
-- DB format 키 → oUF tag 문자열 변환
-----------------------------------------------

ns.NAME_FORMAT_TO_TAG = {
	["name"]        = "[ddingui:classcolor][ddingui:name]|r",
	["name:abbrev"] = "[ddingui:classcolor][ddingui:name:abbrev]|r",
	["name:short"]  = "[ddingui:classcolor][ddingui:name:short]|r",
}

ns.HEALTH_FORMAT_TO_TAG = {
	["percentage"]         = "[ddingui:ht:pct]",
	["current"]            = "[ddingui:ht:cur]",
	["current-max"]        = "[ddingui:ht:curmax]",
	["deficit"]            = "[ddingui:ht:deficit]",
	["current-percentage"] = "[ddingui:ht:curpct]",
	["percent-current"]    = "[ddingui:ht:pctcur]",
	["current-percent"]    = "[ddingui:ht:curp]",
	["smart"]              = "[ddingui:ht:smart]",
	["raid"]               = "[ddingui:ht:raid]",
	["healer"]             = "[ddingui:ht:healer]",
	["percent-full"]       = "[ddingui:ht:pctfull]",
}

ns.POWER_FORMAT_TO_TAG = {
	["percentage"]         = "[ddingui:pt:pct]",
	["current"]            = "[ddingui:pt:cur]",
	["current-max"]        = "[ddingui:pt:curmax]",
	["deficit"]            = "[ddingui:pt:deficit]",
	["current-percentage"] = "[ddingui:pt:curpct]",
	["percent-current"]    = "[ddingui:pt:pctcur]",
	["current-percent"]    = "[ddingui:pt:curp]",
	["smart"]              = "[ddingui:pt:smart]",
}

ns.ABSORB_FORMAT_TO_TAG = {
	["absorb"]          = "[ddingui:absorb]",
	["absorb-percent"]  = "[ddingui:absorb:percent]",
	["health-absorb"]   = "[ddingui:health:absorb]",
	["healabsorb"]      = "[ddingui:healabsorb]",
}

-----------------------------------------------
-- Tag Preset Table (Options UI 연동)
-----------------------------------------------

ns.TagPresets = {
	name = {
		{ label = "이름 (전체)",       tag = "[ddingui:name]",                             format = "name" },
		{ label = "이름 (긴)",         tag = "[ddingui:name:long]",                        format = "name:long" },
		{ label = "이름 (중간)",       tag = "[ddingui:name:medium]",                      format = "name:medium" },
		{ label = "이름 (짧은)",       tag = "[ddingui:name:short]",                       format = "name:short" },
		{ label = "이름 (매우짧은)",   tag = "[ddingui:name:veryshort]",                   format = "name:veryshort" },
		{ label = "이름 (약칭)",       tag = "[ddingui:name:abbrev]",                      format = "name:abbrev" },
		{ label = "이름 (레이드)",     tag = "[ddingui:name:raid]",                        format = "name:raid" },
		{ label = "직업색 + 이름",     tag = "[ddingui:classcolor][ddingui:name:medium]|r", format = "name:medium" },
		{ label = "직업색 + 이름(짧은)", tag = "[ddingui:classcolor][ddingui:name:short]|r", format = "name:short" },
		{ label = "직업색 + 이름(레이드)", tag = "[ddingui:classcolor][ddingui:name:raid]|r", format = "name:raid" },
		{ label = "역할 + 이름",       tag = "[ddingui:name:role]",                        format = "name:role" },
		{ label = "레벨 + 이름",       tag = "[ddingui:level:smart] [ddingui:name:medium]", format = "name:medium" },
		{ label = "직업색 + 레벨 + 이름", tag = "[ddingui:classcolor][ddingui:level:smart] [ddingui:name:medium]|r", format = "name:medium" },
	},
	health = {
		{ label = "스마트 (기본)",     tag = "[ddingui:health]",                           format = "smart" },
		{ label = "퍼센트",            tag = "[ddingui:health:percent]",                   format = "percentage" },
		{ label = "퍼센트 (항상)",     tag = "[ddingui:health:percent-full]",              format = "percent-full" },
		{ label = "현재값",            tag = "[ddingui:health:current]",                   format = "current" },
		{ label = "현재 / 최대",       tag = "[ddingui:health:current-max]",               format = "current-max" },
		{ label = "현재 | 퍼센트",     tag = "[ddingui:health:current-percent]",           format = "current-percentage" },
		{ label = "감소량",            tag = "[ddingui:health:deficit]",                   format = "deficit" },
		{ label = "레이드 (100% 숨김)", tag = "[ddingui:health:raid]",                     format = "raid" },
		{ label = "힐러전용 감소량",   tag = "[ddingui:health:healeronly]",                format = "healer" },
	},
	power = {
		{ label = "퍼센트",            tag = "[ddingui:pt:pct]",                           format = "percentage" },
		{ label = "현재값",            tag = "[ddingui:pt:cur]",                           format = "current" },
		{ label = "현재 / 최대",       tag = "[ddingui:pt:curmax]",                        format = "current-max" },
		{ label = "감소량",            tag = "[ddingui:pt:deficit]",                       format = "deficit" },
		{ label = "현재 | 퍼센트",     tag = "[ddingui:pt:curpct]",                        format = "current-percentage" },
		{ label = "스마트",            tag = "[ddingui:pt:smart]",                         format = "smart" },
	},
	absorb = {
		{ label = "보호막 (축약)",       tag = "[ddingui:absorb]",                           format = "absorb" },
		{ label = "보호막 퍼센트",       tag = "[ddingui:absorb:percent]",                   format = "absorb-percent" },
		{ label = "체력 + 보호막",       tag = "[ddingui:health:absorb]",                    format = "health-absorb" },
		{ label = "힐 흡수량",           tag = "[ddingui:healabsorb]",                       format = "healabsorb" },
	},
}

-----------------------------------------------
-- [DEBUG] /tagtest 진단 커맨드 -- [SECRET-V4]
-----------------------------------------------

SLASH_DDINGUI_TAGTEST1 = "/tagtest"
SlashCmdList["DDINGUI_TAGTEST"] = function()
	local p = print
	local oUF = ns.oUF
	p("|cff00ff00[ddingUI Tags] 진단 시작 (oUF + TextFormats)|r")

	-- 1. API 존재 확인
	p("  --- API 존재 확인 ---")
	p("  oUF: " .. (oUF and "|cff00ff00OK|r" or "|cffff0000없음|r"))
	p("  oUF.Tags: " .. (oUF and oUF.Tags and "|cff00ff00OK|r" or "|cffff0000없음|r"))
	p("  issecretvalue: " .. (issecretvalue and "|cff00ff00OK|r" or "|cffff8800없음|r"))
	p("  AbbreviateNumbers: " .. (AbbreviateNumbers and "|cff00ff00OK|r" or "|cffff0000없음|r"))
	p("  FormatPercentage: " .. (FormatPercentage and "|cff00ff00OK|r" or "|cffff8800없음|r"))
	p("  UnitHealthPercent: " .. (UnitHealthPercent and "|cff00ff00OK|r" or "|cffff0000없음|r"))
	p("  ScaleTo100: " .. (ScaleTo100 and "|cff00ff00OK|r" or "|cffff8800없음|r"))

	-- 2. Secret value 상태
	p("  --- Secret Value 상태 (player) ---")
	local rawH = UnitHealth("player")
	local rawHM = UnitHealthMax("player")
	p("  UnitHealth: secret=" .. tostring(issecretvalue and issecretvalue(rawH) or "N/A"))
	p("  UnitHealthMax: secret=" .. tostring(issecretvalue and issecretvalue(rawHM) or "N/A"))

	-- 3. oUF.Tags.Methods 테스트
	p("  --- oUF.Tags.Methods 테스트 (unit=player) ---")
	if not oUF or not oUF.Tags then
		p("  |cffff0000oUF.Tags 없음|r")
		return
	end

	local testTags = {
		"ddingui:ht:pct", "ddingui:ht:cur", "ddingui:ht:curmax",
		"ddingui:ht:deficit", "ddingui:ht:smart", "ddingui:ht:raid",
		"ddingui:pt:pct", "ddingui:pt:cur", "ddingui:pt:curmax",
		"ddingui:name", "ddingui:name:short", "ddingui:name:medium",
		"ddingui:classcolor", "ddingui:level:smart", "ddingui:status",
	}

	local registered = 0
	for _, tag in ipairs(testTags) do
		local fn = oUF.Tags.Methods[tag]
		if fn then
			registered = registered + 1
			local ok, result = pcall(fn, "player")
			if ok then
				local cleanP = pcall(function()
					p("  [" .. tag .. "] = \"" .. (result or "nil") .. "\"")
				end)
				if not cleanP then
					p("  [" .. tag .. "] |cff00ff00OK|r type=" .. type(result))
				end
			else
				p("  [" .. tag .. "] |cffff0000ERROR:|r " .. tostring(result))
			end
		else
			p("  [" .. tag .. "] |cffff0000미등록|r")
		end
	end
	p("  등록된 태그: " .. registered .. "/" .. #testTags)

	-- 4. 프레임 상태 확인
	local playerFrame = ns.frames and ns.frames.player
	if playerFrame then
		p("  --- PlayerFrame 상태 ---")
		p("  PlayerFrame: |cff00ff00존재|r")
		p("  unit: " .. tostring(playerFrame.unit))
		p("  Health: " .. (playerFrame.Health and "|cff00ff00OK|r" or "|cffff0000nil|r"))
		p("  Power: " .. (playerFrame.Power and "|cff00ff00OK|r" or "|cffff8800nil|r"))
		if playerFrame.HealthText then
			p("  HealthText: visible=" .. tostring(playerFrame.HealthText:IsVisible()))
		end
		if playerFrame.PowerText then
			p("  PowerText: visible=" .. tostring(playerFrame.PowerText:IsVisible()))
		end
	end

	p("|cff00ff00[ddingUI Tags] 진단 완료|r")
end

-----------------------------------------------
-- [DEBUG] /pinkbar - 대상 프레임 1px 바 추적
-----------------------------------------------

SLASH_DDINGUI_PINKBAR1 = "/pinkbar"
SlashCmdList["DDINGUI_PINKBAR"] = function()
	local p = print
	p("|cffff00ff[pinkbar] 대상 프레임 전체 스캔|r")

	local targetFrame = ns.frames and ns.frames.target
	if not targetFrame then
		p("  |cffff0000target 프레임 없음|r")
		return
	end

	p("  target frame: " .. format("%.0fx%.0f", targetFrame:GetWidth(), targetFrame:GetHeight()))
	p("  unit=" .. tostring(targetFrame.unit or targetFrame._unit))

	local function SafeNum(val)
		local ok, n = pcall(function() return val + 0 end)
		return ok and n or 0
	end

	local function ScanRegions(frame, depth, parentName)
		if depth > 4 then return end
		local prefix = string.rep("  ", depth + 1)

		for i = 1, frame:GetNumRegions() do
			local region = select(i, frame:GetRegions())
			if region and region:IsVisible() then
				local rType = region:GetObjectType()
				local rw, rh = SafeNum(region:GetWidth()), SafeNum(region:GetHeight())
				if rh <= 2 and rw > 5 then
					if rType == "Texture" then
						local r, g, b, a = region:GetVertexColor()
						local tex = region:GetTexture()
						p(prefix .. "|cffff8800SUSPECT|r " .. parentName .. " region" .. i .. " (" .. rType .. ")")
						p(prefix .. "  size=" .. format("%.1fx%.1f", rw, rh))
						p(prefix .. "  color=" .. format("%.2f,%.2f,%.2f,%.2f", r, g, b, a))
						p(prefix .. "  texture=" .. tostring(tex))
						p(prefix .. "  drawLayer=" .. tostring(region:GetDrawLayer()))
						for pt = 1, region:GetNumPoints() do
							local point, relativeTo, relPoint, xOfs, yOfs = region:GetPoint(pt)
							local relName = relativeTo and relativeTo:GetName() or tostring(relativeTo)
							p(prefix .. "  point" .. pt .. ": " .. tostring(point) .. " -> " .. relName .. ":" .. tostring(relPoint) .. " " .. format("%.1f,%.1f", xOfs or 0, yOfs or 0))
						end
					end
				end
			end
		end

		for i = 1, frame:GetNumChildren() do
			local child = select(i, frame:GetChildren())
			if child and child:IsVisible() then
				local cw, ch = SafeNum(child:GetWidth()), SafeNum(child:GetHeight())
				local cName = child:GetName() or (parentName .. ".child" .. i)
				if ch <= 2 and cw > 5 then
					p(prefix .. "|cffff0000SUSPECT|r " .. cName .. " (" .. child:GetObjectType() .. ")")
					p(prefix .. "  size=" .. format("%.1fx%.1f", cw, ch))
					if child.GetStatusBarTexture then
						local sr, sg, sb, sa = child:GetStatusBarColor()
						p(prefix .. "  StatusBarColor=" .. format("%.2f,%.2f,%.2f,%.2f", sr or 0, sg or 0, sb or 0, sa or 0))
					end
					ScanRegions(child, depth + 1, cName)
				end
				ScanRegions(child, depth + 1, cName)
			end
		end
	end

	local health = targetFrame.Health
	if health then
		local hr, hg, hb, ha = health:GetStatusBarColor()
		p("  Health: " .. format("%.0fx%.0f", health:GetWidth(), health:GetHeight())
		  .. " color=" .. format("%.2f,%.2f,%.2f,%.2f", hr or 0, hg or 0, hb or 0, ha or 0))
	end

	local power = targetFrame.Power
	if power then
		local pr, pg, pb, pa = power:GetStatusBarColor()
		p("  Power: " .. format("%.0fx%.0f", power:GetWidth(), power:GetHeight())
		  .. " visible=" .. tostring(power:IsVisible())
		  .. " color=" .. format("%.2f,%.2f,%.2f,%.2f", pr or 0, pg or 0, pb or 0, pa or 0))
	else
		p("  Power: nil")
	end

	ScanRegions(targetFrame, 1, "TargetFrame")

	p("|cffff00ff[pinkbar] 스캔 완료|r")
end

-- Tags.lua 로드 확인
ns.Debug("Tags.lua loaded")
