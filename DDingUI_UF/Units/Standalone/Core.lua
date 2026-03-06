--[[
	ddingUI UnitFrames
	Units/Standalone/Core.lua — 독자 UF 중앙 이벤트 디스패처
	
	oUF의 이벤트 라우팅을 대체:
	- UNIT_HEALTH → UpdateHealth
	- UNIT_POWER_UPDATE → UpdatePower
	- UNIT_SPELLCAST_* → UpdateCastbar
	- UNIT_AURA → UpdateAuras
	- UNIT_HEAL_PREDICTION 등 → UpdateHealthPrediction
	- PLAYER_TARGET_CHANGED 등 → 대상 프레임 전체 갱신
	- 인디케이터/하이라이트 이벤트
	
	Layout.lua의 StyleUnit을 그대로 호출하여 모든 위젯 생성
	→ 모든 파라미터 100% 보존
]]

local _, ns = ...

local SUF = {}
ns.SUF = SUF

local Drivers = ns.ElementDrivers
local TagEngine = ns.TagEngine

SUF.frames = {}       -- unit → frame
SUF.allFrames = {}    -- 모든 standalone frame 리스트

-----------------------------------------------
-- Frame Creation: oUF:Spawn() 대체
-- SecureUnitButtonTemplate + Layout:StyleUnit
-----------------------------------------------

function SUF:SpawnUnit(unit, frameName)
	local frame = CreateFrame("Button", frameName, UIParent, "SecureUnitButtonTemplate")
	frame.unit = unit
	frame._unitKey = unit:gsub("%d+$", "")

	-- Secure attributes
	frame:RegisterForClicks("AnyUp")
	frame:SetAttribute("unit", unit)
	frame:SetAttribute("type1", "target")
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("type2", "togglemenu")
	frame:SetAttribute("*type2", "togglemenu")

	-- Tag 메서드 제공 (Layout.lua의 self:Tag(fs, tagStr)를 위해)
	frame.Tag = function(self, fontString, tagStr)
		if TagEngine then
			TagEngine:Register(self, fontString, tagStr)
		end
	end

	-- Layout.lua의 StyleUnit 호출 → 모든 위젯 생성
	if ns.Layout and ns.Layout.StyleUnit then
		ns.Layout:StyleUnit(frame, unit)
	end

	-- Castbar OnUpdate 등록
	if frame.Castbar then
		frame:SetScript("OnUpdate", function(self, elapsed)
			if Drivers then
				Drivers:CastbarOnUpdate(self, elapsed)
			end
		end)
	end

	-- 등록
	self.frames[unit] = frame
	self.allFrames[#self.allFrames + 1] = frame

	return frame
end

-----------------------------------------------
-- 중앙 이벤트 디스패처
-----------------------------------------------

local eventFrame = CreateFrame("Frame")

-- 유닛별 이벤트 (고빈도)
local UNIT_EVENTS = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH",
	"UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
	"UNIT_NAME_UPDATE", "UNIT_CONNECTION",
	"UNIT_AURA",
	"UNIT_HEAL_PREDICTION",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
	"UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
	"UNIT_THREAT_SITUATION_UPDATE",
	"UNIT_FLAGS",
}

-- 시전바 이벤트
local CASTBAR_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
	"UNIT_SPELLCAST_EMPOWER_UPDATE",
}

-- 글로벌 이벤트
local GLOBAL_EVENTS = {
	"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
	"RAID_TARGET_UPDATE",
	"PLAYER_ROLES_ASSIGNED",
	"READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
	"PARTY_LEADER_CHANGED",
	"INCOMING_RESURRECT_CHANGED", "INCOMING_SUMMON_CHANGED",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
	"PLAYER_UPDATE_RESTING",
	"UPDATE_SHAPESHIFT_FORM",
}

-- 이벤트 등록
for _, ev in ipairs(UNIT_EVENTS) do
	eventFrame:RegisterEvent(ev)
end
for _, ev in ipairs(CASTBAR_EVENTS) do
	eventFrame:RegisterEvent(ev)
end
for _, ev in ipairs(GLOBAL_EVENTS) do
	eventFrame:RegisterEvent(ev)
end

-- 시전바 이벤트 세트 (빠른 조회용)
local CASTBAR_EVENT_SET = {}
for _, ev in ipairs(CASTBAR_EVENTS) do CASTBAR_EVENT_SET[ev] = true end

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if not Drivers then return end

	-- 글로벌 이벤트: 모든 프레임 갱신
	if event == "PLAYER_TARGET_CHANGED" then
		-- target 프레임 전체 갱신
		local tf = SUF.frames["target"]
		if tf and tf:IsVisible() then Drivers:UpdateAll(tf) end
		-- targettarget도
		local ttf = SUF.frames["targettarget"]
		if ttf and ttf:IsVisible() then Drivers:UpdateAll(ttf) end
		-- 모든 프레임의 highlight 갱신
		for _, frame in ipairs(SUF.allFrames) do
			if frame:IsVisible() then Drivers:UpdateHighlight(frame) end
		end
		return
	elseif event == "PLAYER_FOCUS_CHANGED" then
		local ff = SUF.frames["focus"]
		if ff and ff:IsVisible() then Drivers:UpdateAll(ff) end
		local ftf = SUF.frames["focustarget"]
		if ftf and ftf:IsVisible() then Drivers:UpdateAll(ftf) end
		for _, frame in ipairs(SUF.allFrames) do
			if frame:IsVisible() then Drivers:UpdateHighlight(frame) end
		end
		return
	elseif event == "RAID_TARGET_UPDATE" then
		for _, frame in ipairs(SUF.allFrames) do
			if frame:IsVisible() then Drivers:UpdateRaidTargetIndicator(frame) end
		end
		return
	elseif event == "PLAYER_ROLES_ASSIGNED" then
		for _, frame in ipairs(SUF.allFrames) do
			if frame:IsVisible() then Drivers:UpdateGroupRoleIndicator(frame) end
		end
		return
	elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" or event == "READY_CHECK_FINISHED" then
		for _, frame in ipairs(SUF.allFrames) do
			if frame:IsVisible() then Drivers:UpdateReadyCheckIndicator(frame) end
		end
		return
	elseif event == "PARTY_LEADER_CHANGED" then
		for _, frame in ipairs(SUF.allFrames) do
			if frame:IsVisible() then Drivers:UpdateLeaderIndicator(frame) end
		end
		return
	elseif event == "INCOMING_RESURRECT_CHANGED" or event == "INCOMING_SUMMON_CHANGED" then
		local unit = ...
		if unit then
			local f = SUF.frames[unit]
			if f and f:IsVisible() then Drivers:UpdateResurrectIndicator(f) end
		end
		return
	elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		local pf = SUF.frames["player"]
		if pf and pf:IsVisible() then Drivers:UpdateCombatIndicator(pf) end
		return
	elseif event == "PLAYER_UPDATE_RESTING" then
		local pf = SUF.frames["player"]
		if pf and pf:IsVisible() then Drivers:UpdateRestingIndicator(pf) end
		return
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		local pf = SUF.frames["player"]
		if pf and pf:IsVisible() then
			Drivers:UpdatePower(pf)
			Drivers:UpdateClassPower(pf)
		end
		return
	end

	-- 유닛별 이벤트
	local unit = ...
	if not unit then return end

	local frame = SUF.frames[unit]
	if not frame or not frame:IsVisible() then return end

	-- 시전바 이벤트
	if CASTBAR_EVENT_SET[event] then
		Drivers:UpdateCastbar(frame, event)
		return
	end

	-- 요소별 분기
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
		Drivers:UpdateHealth(frame)
		Drivers:UpdateHealthPrediction(frame)  -- 보호막 바는 체력 위치에 앵커되므로 같이 갱신
		if TagEngine then TagEngine:UpdateForEvent(frame, event) end
	elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
		Drivers:UpdatePower(frame)
		Drivers:UpdateClassPower(frame)
		if TagEngine then TagEngine:UpdateForEvent(frame, event) end
	elseif event == "UNIT_NAME_UPDATE" then
		if TagEngine then TagEngine:UpdateForEvent(frame, event) end
	elseif event == "UNIT_CONNECTION" then
		Drivers:UpdateAll(frame)
	elseif event == "UNIT_AURA" then
		Drivers:UpdateAuras(frame)
		Drivers:UpdateDispelHighlight(frame)
	elseif event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED"
		or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
		Drivers:UpdateHealthPrediction(frame)
		if TagEngine then TagEngine:UpdateForEvent(frame, event) end
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
		Drivers:UpdateThreatIndicator(frame)
	elseif event == "UNIT_FLAGS" then
		if TagEngine then TagEngine:UpdateForEvent(frame, event) end
	end
end)

-----------------------------------------------
-- Range ticker (0.5초 간격)
-----------------------------------------------

local rangeTicker = CreateFrame("Frame")
local rangeElapsed = 0
rangeTicker:SetScript("OnUpdate", function(self, elapsed)
	rangeElapsed = rangeElapsed + elapsed
	if rangeElapsed < 0.5 then return end
	rangeElapsed = 0

	for _, frame in ipairs(SUF.allFrames) do
		if frame:IsVisible() and frame.Range then
			Drivers:UpdateRange(frame)
		end
	end
end)

-----------------------------------------------
-- OnShow 후크: 프레임이 보여질 때 전체 갱신
-----------------------------------------------

function SUF:HookOnShow(frame)
	frame:HookScript("OnShow", function(self)
		if Drivers then
			C_Timer.After(0, function()
				if self:IsVisible() and self.unit then
					Drivers:UpdateAll(self)
				end
			end)
		end
	end)
end

ns.Debug("Standalone Core.lua loaded")
