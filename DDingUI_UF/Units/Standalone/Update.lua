local _, ns = ...
local SUF = ns.Standalone
local F = ns.Functions
local SafeVal = ns.SafeVal
local SafeNum = ns.SafeNum

function SUF:UpdateHealth(frame)
	local unit = frame.unit
	if not UnitExists(unit) then return end
	
	local health = frame.Health
	if not health then return end

	local current = UnitHealth(unit)
	local max = UnitHealthMax(unit)

	current = SafeNum(current, 0)
	max = SafeNum(max, 1)
	if max == 0 then max = 1 end

	health:SetMinMaxValues(0, max)
	health:SetValue(current)

	-- Health Color (Class basic)
	local _, className = UnitClass(unit)
	if className and RAID_CLASS_COLORS[className] then
		local c = RAID_CLASS_COLORS[className]
		health:SetStatusBarColor(c.r, c.g, c.b)
	else
		health:SetStatusBarColor(0.2, 0.8, 0.2)
	end
	
	-- Health Text (Current / Percent)
	if frame.HealthText then
		if current == 0 then
			frame.HealthText:SetText("Dead")
		else
			local pct = (max > 0) and (current / max * 100) or 0
			if pct < 100 then
				frame.HealthText:SetText(("%s | %.1f%%"):format(F:Abbreviate(current), pct))
			else
				frame.HealthText:SetText(F:Abbreviate(current))
			end
		end
	end
end

function SUF:UpdatePower(frame)
	local unit = frame.unit
	if not UnitExists(unit) then return end
	
	local power = frame.Power
	if not power then return end

	local current = UnitPower(unit)
	local max = UnitPowerMax(unit)

	current = SafeNum(current, 0)
	max = SafeNum(max, 1)
	if max == 0 then max = 1 end

	power:SetMinMaxValues(0, max)
	power:SetValue(current)

	-- Power Color
	local typeName, typeToken = UnitPowerType(unit)
	local cList = ns.Constants.POWER_COLORS
	local c
	if typeToken and cList[typeToken] then
		c = cList[typeToken]
	elseif typeName and cList[typeName] then
		c = cList[typeName]
	else
		c = { 0.31, 0.45, 0.63 }
	end
	power:SetStatusBarColor(c[1], c[2], c[3])
end

function SUF:UpdateName(frame)
	local unit = frame.unit
	if not UnitExists(unit) then return end
	
	if frame.NameText then
		local name = UnitName(unit)
		if name then
			frame.NameText:SetText(name)
		end
	end
end

function SUF:UpdateAuras(frame)
	if not frame.Auras or not _G.TargetFrame_UpdateAuras then return end
	if not UnitExists(frame.unit) then return end
	-- Minimal bridge to native TargetFrame Aura logic
	_G.TargetFrame_UpdateAuras(frame)
end
