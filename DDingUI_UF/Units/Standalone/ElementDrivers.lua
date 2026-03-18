--[[
	ddingUI UnitFrames
	Units/Standalone/ElementDrivers.lua — oUF element 시스템 대체
	
	oUF가 self.Health/self.Power/self.Castbar 등을 감지하여 자동으로
	이벤트를 등록하고 SetValue/SetMinMaxValues를 호출했던 역할을 대체.
	
	Layout.lua의 StyleUnit이 self.Health = bar 등을 설정하면,
	이 드라이버가 해당 요소에 적합한 이벤트 핸들링을 수행한다.
	
	Secret-safe: StatusBar API로 직접 설정 (값 비교 회피)
]]

local _, ns = ...

local Drivers = {}
ns.ElementDrivers = Drivers

local SafeVal = ns.SafeVal
local SafeNum = ns.SafeNum
local issecretvalue = issecretvalue
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitReaction = UnitReaction
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local FACTION_BAR_COLORS = FACTION_BAR_COLORS
local PowerBarColor = PowerBarColor
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local CreateUnitHealPredictionCalculator = CreateUnitHealPredictionCalculator
local GetTime = GetTime
local unpack = unpack
local pcall = pcall
local C = ns.Constants

-----------------------------------------------
-- Health Driver
-----------------------------------------------

function Drivers:UpdateHealth(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local health = frame.Health
	if not health then return end

	-- Secret-safe: StatusBar API가 C++에서 secret number 처리
	health:SetMinMaxValues(0, UnitHealthMax(unit))
	-- [FIX] smoothing 인자 전달: ns.db.smoothBars 동적 참조 (런타임 토글 지원)
	local interpMode = (ns.db and ns.db.smoothBars ~= false)
		and Enum.StatusBarInterpolation.Linear
		or Enum.StatusBarInterpolation.Immediate
	health:SetValue(UnitHealth(unit), interpMode)

	-- 색상
	local owner = frame  -- Layout.lua에서 health.__owner 대신
	local unitKey = frame._unitKey or unit:gsub("%d+$", "")
	local udb = ns.db and ns.db[unitKey]
	local colorType = udb and udb.healthBarColorType or "class"

	local r, g, b
	if colorType == "custom" and udb and udb.healthBarColor then
		r, g, b = unpack(udb.healthBarColor)
	elseif colorType == "smooth" then
		-- smooth gradient (UnitHealthPercent 기반)
		local pct = 1
		if UnitHealthPercent then
			local raw = UnitHealthPercent(unit)
			if raw and not (issecretvalue and issecretvalue(raw)) then
				pct = raw / 100
			end
		end
		if pct > 0.5 then
			r = (1 - pct) * 2
			g = 1
		else
			r = 1
			g = pct * 2
		end
		b = 0
	else
		-- class / reaction (oUF 동작 재현)
		-- oUF 로직: colorClass가 true이면 UnitIsPlayer인 유닛에 직업 색상 적용
		-- colorReaction이 true이면 NPC에 반응도 색상 적용
		-- 둘 다 true이면 플레이어=직업색상, NPC=반응도색상
		if health.colorClass and UnitIsPlayer(unit) then
			local _, class = UnitClass(unit)
			local cc = class and RAID_CLASS_COLORS[class]
			if cc then
				r, g, b = cc.r, cc.g, cc.b
			end
		end

		-- 직업 색상으로 못 잡았으면 (NPC거나 colorClass가 false) → reaction 시도
		if not r and health.colorReaction then
			local reaction = UnitReaction(unit, "player")
			if reaction and not (issecretvalue and issecretvalue(reaction)) then
				-- ns.Constants.REACTION_COLORS는 커스텀 색상 (글로벌 색상 시스템)
				local rc = C.REACTION_COLORS and C.REACTION_COLORS[reaction]
				if rc then
					r, g, b = rc[1], rc[2], rc[3]
				else
					local fc = FACTION_BAR_COLORS[reaction]
					if fc then r, g, b = fc.r, fc.g, fc.b end
				end
			end
		end

		-- 그래도 못 잡았으면 최종 폴백
		if not r then
			r, g, b = 49/255, 207/255, 37/255
		end
	end

	health:SetStatusBarColor(r, g, b)

	-- Background
	if health.bg and not health.bg._customColor then
		local mu = health.bg.multiplier or C.HEALTH_BG_MULTIPLIER or 0.3
		health.bg:SetVertexColor(r * mu, g * mu, b * mu)
	end

	-- PostUpdateColor 콜백 (Layout.lua에서 설정됨)
	if health.PostUpdateColor then
		health:PostUpdateColor(unit, nil)
	end

	-- PostUpdate 콜백
	if health.PostUpdate then
		health:PostUpdate(unit)
	end
end

-----------------------------------------------
-- Power Driver
-----------------------------------------------

function Drivers:UpdatePower(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local power = frame.Power
	if not power then return end

	local max = UnitPowerMax(unit)
	local cur = UnitPower(unit)

	power:SetMinMaxValues(0, max)
	-- [FIX] smoothing 인자 전달
	local interpMode = (ns.db and ns.db.smoothBars ~= false)
		and Enum.StatusBarInterpolation.Linear
		or Enum.StatusBarInterpolation.Immediate
	power:SetValue(cur, interpMode)

	-- 색상 (colorPower)
	if power.colorPower ~= false then
		local pType, pToken = UnitPowerType(unit)
		local r, g, b = 0.2, 0.2, 0.6
		-- pToken 우선
		if pToken and not (issecretvalue and issecretvalue(pToken)) then
			local customC = ns.Colors and ns.Colors.power and ns.Colors.power[pToken]
			if not customC then
				customC = C.POWER_COLORS and C.POWER_COLORS[pToken]
			end
			if customC then
				r, g, b = customC[1], customC[2], customC[3]
			else
				local c = PowerBarColor[pToken]
				if c and c.r then r, g, b = c.r, c.g, c.b end
			end
		elseif pType and not (issecretvalue and issecretvalue(pType)) then
			local c = PowerBarColor[pType]
			if c and c.r then r, g, b = c.r, c.g, c.b end
		end
		power:SetStatusBarColor(r, g, b)
		if power.bg then
			local mu = power.bg.multiplier or 0.3
			power.bg:SetVertexColor(r * mu, g * mu, b * mu)
		end
	end

	-- PostUpdateColor 콜백
	if power.PostUpdateColor then
		power:PostUpdateColor(unit)
	end

	-- PostUpdate 콜백 (show/hide + health 높이 조정)
	if power.PostUpdate then
		power:PostUpdate(unit, cur, nil, max)
	end
end

-----------------------------------------------
-- Castbar Driver
-----------------------------------------------

function Drivers:UpdateCastbar(frame, event)
	local unit = frame.unit
	if not unit then return end
	local castbar = frame.Castbar
	if not castbar then return end

	if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED"
		or event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
		local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(unit)
		if not name then
			castbar:Hide()
			if castbar.backdrop then castbar.backdrop:Hide() end
			return
		end
		if castbar.hideTradeSkills and isTradeSkill then
			castbar:Hide()
			if castbar.backdrop then castbar.backdrop:Hide() end
			return
		end

		castbar.notInterruptible = notInterruptible
		castbar.castID = castID
		castbar._channeling = false

		if castbar.Icon then castbar.Icon:SetTexture(texture) end
		if castbar.Text then castbar.Text:SetText(text or name) end

		-- [FIX] startTimeMS/endTimeMS가 secret number일 수 있음 → pcall로 보호
		local duration, elapsed
		local timeOk = pcall(function()
			duration = (endTimeMS - startTimeMS) / 1000
			elapsed = (GetTime() - startTimeMS / 1000)
		end)
		if not timeOk or not duration then
			castbar:Hide()
			if castbar.backdrop then castbar.backdrop:Hide() end
			return
		end
		castbar:SetMinMaxValues(0, duration)
		castbar:SetValue(elapsed)
		castbar._totalDuration = duration

		if castbar.Spark then castbar.Spark:Show() end

		-- 차단 가능 여부 색상
		local isNotInt = false
		if notInterruptible ~= nil then
			if issecretvalue and issecretvalue(notInterruptible) then
				isNotInt = true
			elseif notInterruptible then
				isNotInt = true
			end
		end
		if isNotInt then
			castbar:SetStatusBarColor(unpack(castbar._nonIntColor or C.CASTBAR_NOINTERRUPT_COLOR))
		else
			castbar:SetStatusBarColor(unpack(castbar._intColor or C.CASTBAR_COLOR))
		end
		-- niOverlay
		if castbar.niOverlay and castbar.niOverlay.SetAlphaFromBoolean then
			castbar.niOverlay:SetAlphaFromBoolean(notInterruptible, 0.25, 0)
		end
		-- Shield
		if castbar.Shield and castbar.Shield.SetAlphaFromBoolean then
			castbar.Shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
		end

		-- PostCastStart 콜백
		if castbar.PostCastStart then
			castbar:PostCastStart(unit)
		end

		castbar:Show()
		if castbar.backdrop then castbar.backdrop:Show() end

	elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID, _, numStages = UnitChannelInfo(unit)
		if not name then
			castbar:Hide()
			if castbar.backdrop then castbar.backdrop:Hide() end
			return
		end

		castbar.notInterruptible = notInterruptible
		castbar._channeling = true

		if castbar.Icon then castbar.Icon:SetTexture(texture) end
		if castbar.Text then castbar.Text:SetText(text or name) end

		-- [FIX] startTimeMS/endTimeMS가 secret number일 수 있음 → pcall로 보호
		local duration, remaining
		local timeOk = pcall(function()
			duration = (endTimeMS - startTimeMS) / 1000
			remaining = (endTimeMS / 1000) - GetTime()
		end)
		if not timeOk or not duration then
			castbar:Hide()
			if castbar.backdrop then castbar.backdrop:Hide() end
			return
		end
		castbar:SetMinMaxValues(0, duration)
		castbar:SetValue(remaining)
		castbar._totalDuration = duration

		if castbar.Spark then castbar.Spark:Show() end

		-- 차단 가능 여부
		local isNotInt = false
		if notInterruptible ~= nil then
			if issecretvalue and issecretvalue(notInterruptible) then
				isNotInt = true
			elseif notInterruptible then
				isNotInt = true
			end
		end
		if isNotInt then
			castbar:SetStatusBarColor(unpack(castbar._nonIntColor or C.CASTBAR_NOINTERRUPT_COLOR))
		else
			castbar:SetStatusBarColor(unpack(castbar._intColor or C.CASTBAR_COLOR))
		end
		if castbar.niOverlay and castbar.niOverlay.SetAlphaFromBoolean then
			castbar.niOverlay:SetAlphaFromBoolean(notInterruptible, 0.25, 0)
		end
		if castbar.Shield and castbar.Shield.SetAlphaFromBoolean then
			castbar.Shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
		end

		if castbar.PostChannelStart then
			castbar:PostChannelStart(unit)
		end

		castbar:Show()
		if castbar.backdrop then castbar.backdrop:Show() end

	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_INTERRUPTED"
		or event == "UNIT_SPELLCAST_CHANNEL_STOP"
		or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
		if castbar.Spark then castbar.Spark:Hide() end
		-- timeToHold 처리
		local holdTime = castbar.timeToHold or 0.5
		if holdTime > 0 then
			C_Timer.After(holdTime, function()
				if castbar._channeling and event == "UNIT_SPELLCAST_CHANNEL_STOP" then
					castbar:Hide()
					if castbar.backdrop then castbar.backdrop:Hide() end
				elseif not castbar._channeling then
					castbar:Hide()
					if castbar.backdrop then castbar.backdrop:Hide() end
				end
			end)
		else
			castbar:Hide()
			if castbar.backdrop then castbar.backdrop:Hide() end
		end

	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		if castbar.PostCastInterruptible then
			castbar:PostCastInterruptible(unit)
		end
	end
end

-- OnUpdate: 시전바 값 갱신 (매 프레임)
function Drivers:CastbarOnUpdate(frame, elapsed)
	local castbar = frame.Castbar
	if not castbar or not castbar:IsShown() then return end

	local unit = frame.unit
	if not unit then return end

	if castbar._channeling then
		local _, _, _, _, endTimeMS = UnitChannelInfo(unit)
		if not endTimeMS then
			castbar:Hide()
			if castbar.backdrop then castbar.backdrop:Hide() end
			return
		end
		-- [FIX] endTimeMS가 secret일 수 있음
		local remaining
		local ok = pcall(function()
			remaining = (endTimeMS / 1000) - GetTime()
			if remaining < 0 then remaining = 0 end
		end)
		if not ok or not remaining then return end
		castbar:SetValue(remaining)

		-- Spark 위치
		if castbar.Spark then
			local _, maxVal = castbar:GetMinMaxValues()
			if maxVal and maxVal > 0 then
				local ratio = remaining / maxVal
				local sparkPos = castbar:GetWidth() * ratio
				castbar.Spark:SetPoint("CENTER", castbar, "LEFT", sparkPos, 0)
			end
		end

		-- CustomTimeText
		if castbar.CustomTimeText and castbar._totalDuration then
			-- DurationObject 호환 테이블
			local durationObj = {
				GetRemainingDuration = function() return remaining end,
				GetDuration = function() return castbar._totalDuration end,
				GetElapsedDuration = function() return castbar._totalDuration - remaining end,
			}
			castbar:CustomTimeText(durationObj)
		elseif castbar.Time then
			castbar.Time:SetFormattedText("%.1f", remaining)
		end
	else
		local _, _, _, startTimeMS, endTimeMS = UnitCastingInfo(unit)
		if not startTimeMS or not endTimeMS then
			castbar:Hide()
			if castbar.backdrop then castbar.backdrop:Hide() end
			return
		end
		-- [FIX] startTimeMS/endTimeMS가 secret일 수 있음
		local duration, elapsed_time
		local ok = pcall(function()
			duration = (endTimeMS - startTimeMS) / 1000
			elapsed_time = GetTime() - (startTimeMS / 1000)
			if elapsed_time > duration then elapsed_time = duration end
		end)
		if not ok or not duration then return end
		castbar:SetValue(elapsed_time)

		-- Spark 위치
		if castbar.Spark then
			if duration > 0 then
				local ratio = elapsed_time / duration
				local sparkPos = castbar:GetWidth() * ratio
				castbar.Spark:SetPoint("CENTER", castbar, "LEFT", sparkPos, 0)
			end
		end

		-- CustomTimeText
		local remaining = duration - elapsed_time
		if castbar.CustomTimeText and castbar._totalDuration then
			local durationObj = {
				GetRemainingDuration = function() return remaining end,
				GetDuration = function() return castbar._totalDuration end,
				GetElapsedDuration = function() return elapsed_time end,
			}
			castbar:CustomTimeText(durationObj)
		elseif castbar.Time then
			castbar.Time:SetFormattedText("%.1f", remaining)
		end
	end
end

-----------------------------------------------
-- Health Prediction Driver
-----------------------------------------------
-- [PERF] 그룹프레임과 동일한 state-based pcall 패턴 (closure 생성 방지)
local HealPredState_UF = { unit = nil, calc = nil, result = 0 }
local function GetHealPredSafe_UF()
	UnitGetDetailedHealPrediction(HealPredState_UF.unit, nil, HealPredState_UF.calc)
	HealPredState_UF.result = HealPredState_UF.calc:GetIncomingHeals()
end
local AbsorbPredState_UF = { calc = nil, amt = 0, clamped = false }
local function GetAbsorbSafe_UF()
	AbsorbPredState_UF.amt, AbsorbPredState_UF.clamped = AbsorbPredState_UF.calc:GetDamageAbsorbs()
end
local HealAbsorbState_UF = { calc = nil, amt = 0 }
local function GetHealAbsorbSafe_UF()
	HealAbsorbState_UF.amt = HealAbsorbState_UF.calc:GetHealAbsorbs()
end

function Drivers:UpdateHealthPrediction(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local hp = frame.HealthPrediction
	if not hp then return end
	local health = frame.Health
	if not health then return end

	local maxHP = UnitHealthMax(unit)

	-- 1. HEAL PREDICTION (힐 예측)
	-- [FIX] 그룹 프레임과 동일: parent를 frame으로, 단일 앵커 + 명시적 크기
	if hp.healingAll then
		local incomingHeals = 0
		if UnitGetIncomingHeals then
			local heals = UnitGetIncomingHeals(unit)
			if heals and not (issecretvalue and issecretvalue(heals)) then
				incomingHeals = heals
			end
		end
		local healthFill = health:GetStatusBarTexture()
		if healthFill then
			if hp.healingAll:GetParent() ~= frame then hp.healingAll:SetParent(frame) end
			hp.healingAll:SetFrameLevel(health:GetFrameLevel() + 1)
			hp.healingAll:ClearAllPoints()
			hp.healingAll:SetPoint("LEFT", healthFill, "RIGHT", 0, 0)
			hp.healingAll:SetWidth(health:GetWidth())
			hp.healingAll:SetHeight(health:GetHeight())
		end
		hp.healingAll:SetMinMaxValues(0, maxHP)
		hp.healingAll:SetValue(incomingHeals)
		hp.healingAll:Show()
	end

	-- ========================================
	-- 2. ABSORB (보호막) + OVERSHIELD (초과 보호막)
	-- GroupFrames/Update.lua line 878-998 과 100% 동일 로직
	-- ========================================
	local absBar = hp.damageAbsorb
	local overBar = hp.overShieldBar
	local overGlow = hp.overDamageAbsorbIndicator
	local healthFill = health:GetStatusBarTexture()
	local barWidth = health:GetWidth()
	local barHeight = health:GetHeight()

	if absBar then
		local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0

		-- Calculator (secret-safe)
		local attachedAbsorbs = absorbs
		local isClamped = false
		if CreateUnitHealPredictionCalculator and unit then
			if not frame._absCalc then
				frame._absCalc = CreateUnitHealPredictionCalculator()
				pcall(function() frame._absCalc:SetDamageAbsorbClampMode(1) end)
			end
			local calc = frame._absCalc
			UnitGetDetailedHealPrediction(unit, nil, calc)
			local ok, amt, clamped = pcall(function() return calc:GetDamageAbsorbs() end)
			if ok and amt then
				attachedAbsorbs = amt
				isClamped = clamped
			end
		end

		local hasAnyAbsorb = true
		if not (issecretvalue and issecretvalue(attachedAbsorbs)) then
			hasAnyAbsorb = (attachedAbsorbs and attachedAbsorbs > 0)
		end

		if not hasAnyAbsorb then
			absBar:Hide()
			if overBar then overBar:Hide() end
			if overGlow then overGlow:Hide() end
		else
			local anchor = healthFill
			if hp.healingAll and hp.healingAll:IsShown() then
				local hpFill = hp.healingAll:GetStatusBarTexture()
				if hpFill then anchor = hpFill end
			end

			-- parent를 frame으로 (health의 child이면 클리핑됨)
			if absBar:GetParent() ~= frame then absBar:SetParent(frame) end
			absBar:SetFrameLevel(health:GetFrameLevel() + 1)
			absBar:ClearAllPoints()
			absBar:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
			absBar:SetWidth(barWidth)
			absBar:SetHeight(barHeight)
			absBar:SetMinMaxValues(0, maxHP)
			absBar:SetValue(attachedAbsorbs)
			absBar:Show()

			if absBar.SetAlphaFromBoolean then
				absBar:SetAlphaFromBoolean(isClamped, 0, 1)
			end

			-- OverShield Bar (OVERFLOW)
			if overBar then
				if overBar:GetParent() ~= frame then overBar:SetParent(frame) end
				overBar:SetFrameLevel(health:GetFrameLevel() + 2)
				overBar:ClearAllPoints()
				overBar:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
				overBar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
				overBar:SetReverseFill(true)
				overBar:SetMinMaxValues(0, maxHP)
				overBar:SetValue(absorbs)
				overBar:Show()

				if overBar.SetAlphaFromBoolean then
					overBar:SetAlphaFromBoolean(isClamped, 1, 0)
				else
					local clampedVal = false
					if not (issecretvalue and issecretvalue(isClamped)) then
						clampedVal = isClamped
					end
					if clampedVal then overBar:SetAlpha(1) else overBar:SetAlpha(0) end
				end
			end

			-- OverShield Glow
			if overGlow and overBar then
				local overBarTex = overBar:GetStatusBarTexture()
				if overBarTex then
					overGlow:ClearAllPoints()
					overGlow:SetPoint("TOP", overBarTex, "TOPLEFT", 0, 0)
					overGlow:SetPoint("BOTTOM", overBarTex, "BOTTOMLEFT", 0, 0)
					overGlow:SetWidth(3)
				end
				overGlow:Show()

				if overGlow.SetAlphaFromBoolean then
					overGlow:SetAlphaFromBoolean(isClamped, 1, 0)
				else
					local clampedVal = false
					if not (issecretvalue and issecretvalue(isClamped)) then
						clampedVal = isClamped
					end
					if clampedVal then overGlow:SetAlpha(1) else overGlow:SetAlpha(0) end
				end
			end
		end
	end

	-- 3. HEAL ABSORB (힐 흡수) — 그룹 프레임과 동일
	if hp.healAbsorb then
		local healAbsorbAmt = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0

		local hasHealAbsorb = true
		if not (issecretvalue and issecretvalue(healAbsorbAmt)) then
			hasHealAbsorb = (healAbsorbAmt and healAbsorbAmt > 0)
		end

		if not hasHealAbsorb then
			hp.healAbsorb:Hide()
		else
			if hp.healAbsorb:GetParent() ~= frame then hp.healAbsorb:SetParent(frame) end
			hp.healAbsorb:SetFrameLevel(health:GetFrameLevel() + 1)
			if healthFill then
				hp.healAbsorb:ClearAllPoints()
				hp.healAbsorb:SetPoint("RIGHT", healthFill, "RIGHT", 0, 0)
				hp.healAbsorb:SetWidth(barWidth)
				hp.healAbsorb:SetHeight(barHeight)
				hp.healAbsorb:SetReverseFill(true)
			end
			hp.healAbsorb:SetMinMaxValues(0, maxHP)
			hp.healAbsorb:SetValue(healAbsorbAmt)
			hp.healAbsorb:Show()
		end
	end

	-- PostUpdate 콜백 (오버힐 글로우)
	if hp.PostUpdate then
		hp:PostUpdate(unit)
	end
end

-----------------------------------------------
-- ClassPower Driver
-----------------------------------------------

function Drivers:UpdateClassPower(frame)
	local unit = frame.unit
	if not unit or unit ~= "player" then return end
	local cp = frame.ClassPower
	if not cp then return end

	-- 직업 자원 타입 결정
	local playerClass = select(2, UnitClass("player"))
	local powerType, powerToken
	if playerClass == "ROGUE" or playerClass == "DRUID" then
		powerType = Enum.PowerType.ComboPoints
		powerToken = "COMBO_POINTS"
	elseif playerClass == "PALADIN" then
		powerType = Enum.PowerType.HolyPower
		powerToken = "HOLY_POWER"
	elseif playerClass == "WARLOCK" then
		powerType = Enum.PowerType.SoulShards
		powerToken = "SOUL_SHARDS"
	elseif playerClass == "MAGE" then
		powerType = Enum.PowerType.ArcaneCharges
		powerToken = "ARCANE_CHARGES"
	elseif playerClass == "MONK" then
		powerType = Enum.PowerType.Chi
		powerToken = "CHI"
	elseif playerClass == "EVOKER" then
		powerType = Enum.PowerType.Essence
		powerToken = "ESSENCE"
	else
		-- 직업 자원 없음
		for i = 1, #cp do cp[i]:Hide() end
		return
	end

	local cur = UnitPower("player", powerType) or 0
	local max = UnitPowerMax("player", powerType) or 0

	if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then
		for i = 1, #cp do cp[i]:Hide() end
		return
	end

	for i = 1, max do
		cp[i]:SetMinMaxValues(0, 1)
		if i <= cur then
			cp[i]:SetValue(1)
		else
			cp[i]:SetValue(0)
		end
		cp[i]:Show()
	end
	for i = max + 1, #cp do
		cp[i]:Hide()
	end

	-- PostUpdate 콜백
	if cp.PostUpdate then
		cp:PostUpdate(cur, max, max ~= (cp._lastMax or 0), powerToken)
		cp._lastMax = max
	end
end

-----------------------------------------------
-- Indicator Drivers
-----------------------------------------------

function Drivers:UpdateRaidTargetIndicator(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local raidIcon = frame.RaidTargetIndicator
	if not raidIcon then return end

	local index = GetRaidTargetIndex(unit)
	if index then
		SetRaidTargetIconTexture(raidIcon, index)
		raidIcon:Show()
	else
		raidIcon:Hide()
	end
end

function Drivers:UpdateGroupRoleIndicator(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local roleIcon = frame.GroupRoleIndicator
	if not roleIcon then return end

	-- UpdateRole 오버라이드가 있으면 사용 (Layout.lua에서 설정)
	if roleIcon.UpdateRole then
		roleIcon:UpdateRole("PLAYER_ROLES_ASSIGNED")
		return
	end

	local role = UnitGroupRolesAssigned(unit)
	if role and role ~= "NONE" then
		roleIcon:Show()
	else
		roleIcon:Hide()
	end
end

function Drivers:UpdateReadyCheckIndicator(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local rc = frame.ReadyCheckIndicator
	if not rc then return end

	local status = GetReadyCheckStatus(unit)
	if status == "ready" then
		rc:SetTexture([[Interface\RaidFrame\ReadyCheck-Ready]])
		rc:Show()
	elseif status == "notready" then
		rc:SetTexture([[Interface\RaidFrame\ReadyCheck-NotReady]])
		rc:Show()
	elseif status == "waiting" then
		rc:SetTexture([[Interface\RaidFrame\ReadyCheck-Waiting]])
		rc:Show()
	else
		rc:Hide()
	end
end

function Drivers:UpdateResurrectIndicator(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local res = frame.ResurrectIndicator
	if not res then return end

	local hasIncoming = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)
	if hasIncoming then
		res:SetTexture([[Interface\RaidFrame\Raid-Icon-Rez]])
		res:Show()
	else
		res:Hide()
	end
end

function Drivers:UpdateLeaderIndicator(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local leader = frame.LeaderIndicator
	if not leader then return end

	if UnitIsGroupLeader(unit) then
		if leader._iconSetTexture then
			leader:SetTexture(leader._iconSetTexture)
		end
		leader:Show()
	else
		leader:Hide()
	end
end

function Drivers:UpdateCombatIndicator(frame)
	if frame.unit ~= "player" then return end
	local combat = frame.CombatIndicator
	if not combat then return end

	if UnitAffectingCombat("player") then
		combat:Show()
	else
		combat:Hide()
	end
end

function Drivers:UpdateRestingIndicator(frame)
	if frame.unit ~= "player" then return end
	local resting = frame.RestingIndicator
	if not resting then return end

	if IsResting() then
		if resting._iconSetTexture then
			resting:SetTexture(resting._iconSetTexture)
			if resting._iconSetCoords then
				resting:SetTexCoord(unpack(resting._iconSetCoords))
			end
		end
		-- hideAtMaxLevel 처리 (PostUpdate 콜백에서)
		if resting.PostUpdate then
			resting:PostUpdate(true)
		end
		resting:Show()
	else
		resting:Hide()
	end
end

function Drivers:UpdateThreatIndicator(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local threat = frame.ThreatIndicator
	if not threat then return end

	local status = UnitThreatSituation(unit)
	if threat.PostUpdate then
		local color = nil
		if status and status > 0 then
			color = GetThreatStatusColor(status)
		end
		threat:PostUpdate(unit, status, color)
	elseif status and status > 0 then
		local r, g, b = GetThreatStatusColor(status)
		threat:SetBackdropBorderColor(r, g, b, 0.8)
		threat:Show()
	else
		threat:Hide()
	end
end

-----------------------------------------------
-- Highlight Driver
-----------------------------------------------

function Drivers:UpdateHighlight(frame)
	-- Elements/Highlight.lua의 Update 함수가 존재하면 위임
	if ns.HighlightUpdate then
		ns.HighlightUpdate(frame)
		return
	end

	local unit = frame.unit
	if not unit then return end
	local hl = frame.Highlight
	if not hl then return end

	-- Target border
	if hl.target then
		if UnitIsUnit(unit, "target") then
			local color = (ns.Colors and ns.Colors.highlight and ns.Colors.highlight.target) or hl._db and hl._db.targetColor or { 1, 1, 1, 1 }
			hl.target:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
			hl.target:Show()
		else
			hl.target:Hide()
		end
	end

	-- Focus border
	if hl.focus then
		if UnitIsUnit(unit, "focus") then
			local color = (ns.Colors and ns.Colors.highlight and ns.Colors.highlight.focus) or hl._db and hl._db.focusColor or { 0.6, 0.2, 1, 1 }
			hl.focus:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
			hl.focus:Show()
		else
			hl.focus:Hide()
		end
	end
end

-----------------------------------------------
-- Range Driver (0.5초 틱)
-----------------------------------------------

function Drivers:UpdateRange(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local range = frame.Range
	if not range then return end

	local inRange = UnitInRange(unit)
	if inRange then
		frame:SetAlpha(range.insideAlpha or 1)
	else
		frame:SetAlpha(range.outsideAlpha or 0.35)
	end
end

-----------------------------------------------
-- DispelHighlight Driver
-----------------------------------------------

function Drivers:UpdateDispelHighlight(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	local dh = frame.DispelHighlight
	if not dh then return end

	-- Elements/DispelHighlight.lua의 Update 함수가 존재하면 위임
	if ns.DispelHighlightUpdate then
		ns.DispelHighlightUpdate(frame)
		return
	end

	-- 기본 fallback: 숨기기
	dh:Hide()
end

-----------------------------------------------
-- Auras Driver (UNIT_AURA)
-- Layout.lua의 oUF Buffs/Debuffs element 로직을 독자적으로 구동
-----------------------------------------------

function Drivers:UpdateAuras(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end

	-- Buffs element
	if frame.Buffs then
		self:_UpdateAuraElement(frame, frame.Buffs, unit, "HELPFUL")
	end

	-- Debuffs element
	if frame.Debuffs then
		self:_UpdateAuraElement(frame, frame.Debuffs, unit, "HARMFUL")
	end

	-- [AD] AuraDesigner 인디케이터 업데이트 (party/raid 유닛만)
	local adEngine = ns.AuraDesigner and ns.AuraDesigner.Engine
	if adEngine then
		local ok, err = pcall(adEngine.UpdateStandaloneFrame, adEngine, frame)
		if not ok and ns.db and ns.db.debug then
			ns.Debug("AuraDesigner error:", err)
		end
	end
end

function Drivers:_UpdateAuraElement(frame, element, unit, filter)
	if not element then return end

	local maxButtons = element.num or 32
	local buttonSize = element.size or 24
	local createdButtons = element.createdButtons or 0

	-- 기존 버튼 숨기기
	for i = 1, createdButtons do
		if element[i] then
			element[i]:Hide()
			-- [DandersFrames 패턴] 아이콘 정리: 타이머 추적 방지
			element[i]._expirationTime = nil
			element[i]._totalDuration = nil
			element[i]._hasExpiration = nil
		end
	end

	-- ================================================================
	-- [FIX] Phase 1: 필터 통과 오라를 전부 수집 (maxButtons 제한없이)
	-- 전투 중 secret value로 인해 모든 디버프가 필터를 통과할 수 있으므로
	-- 먼저 전부 수집 → 정렬(SortAuras) → maxButtons만큼만 표시
	-- ================================================================
	local customFilter = element.filter or filter
	local passedAuras = {}  -- { auraData, auraData, ... }

	for i = 1, 40 do
		local auraData = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex(unit, i, customFilter)
		if not auraData then break end

		-- 커스텀 필터 적용
		local show = true
		if element.FilterAura then
			show = element.FilterAura(element, unit, auraData)
		end

		if show then
			passedAuras[#passedAuras + 1] = auraData
		end
	end

	-- ================================================================
	-- [FIX] Phase 2: 정렬 (SortAuras 구현)
	-- Layout.lua의 SortAuras 콜백: Boss > Raid > Dispellable > Mine > Others
	-- 정렬 후 상위 maxButtons개만 표시 → 내 디버프 우선 보장
	-- ================================================================
	if element.SortAuras and #passedAuras > 1 then
		-- SortAuras는 button 기반이므로 auraData 기반 래퍼 사용
		table.sort(passedAuras, function(a, b)
			-- SortAuras expects buttons with _data, create temp wrappers
			local wa = { _data = a }
			local wb = { _data = b }
			return element.SortAuras(element, wa, wb)
		end)
	end

	-- ================================================================
	-- [FIX] Phase 3: 상위 maxButtons개만 버튼에 표시
	-- ================================================================
	local displayCount = math.min(#passedAuras, maxButtons)

	for idx = 1, displayCount do
		local auraData = passedAuras[idx]

		-- 버튼 생성 또는 재사용
		local button = element[idx]
		if not button then
			button = CreateFrame("Button", nil, element)
			button:SetSize(buttonSize, buttonSize)

			button.Icon = button:CreateTexture(nil, "ARTWORK")
			button.Icon:SetAllPoints()

			button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
			button.Cooldown:SetAllPoints()
			button.Cooldown:SetReverse(true)
			-- [DandersFrames 패턴] SetHideCountdownNumbers: 1회 설정
			button.Cooldown:SetHideCountdownNumbers(false) -- 네이티브 카운트다운 표시
			-- 네이티브 cooldown text 탐색 + 폰트 설정 (큰 기본 폰트 방지)
			local regions = {button.Cooldown:GetRegions()}
			for _, region in ipairs(regions) do
				if region and region.GetObjectType and region:GetObjectType() == "FontString" then
					button._nativeCooldownText = region
					region:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
					break
				end
			end

			button.Count = button:CreateFontString(nil, "OVERLAY")
			button.Count:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
			button.Count:SetPoint("BOTTOMRIGHT", 2, -1)

			button.Overlay = button:CreateTexture(nil, "OVERLAY")
			button.Overlay:SetAllPoints()

			element[idx] = button
			element.createdButtons = math.max(element.createdButtons or 0, idx)

			-- PostCreateButton 콜백
			if element.PostCreateButton then
				element:PostCreateButton(button)
			end
		end

		-- 아이콘 설정
		local icon = auraData.icon
		if icon then
			button.Icon:SetTexture(icon)
		end

		-- 쿨다운 (DandersFrames 패턴: SetCooldownFromExpirationTime)
		-- [FIX] DoesAuraHaveExpirationTime은 secret boolean 반환 가능
		-- → Lua if 비교 불가, C++ API (SetShownFromBoolean)로만 사용
		if button.Cooldown then
			local auraInstanceID = auraData.auraInstanceID

			-- 쿨다운 설정: raw secret 값 직접 전달
			if button.Cooldown.SetCooldownFromExpirationTime and auraData.expirationTime and auraData.duration then
				button.Cooldown:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
			elseif auraData.duration and auraData.expirationTime then
				local dur = SafeNum(auraData.duration, 0)
				local exp = SafeNum(auraData.expirationTime, 0)
				if dur > 0 and exp > 0 then
					button.Cooldown:SetCooldown(exp - dur, dur)
				end
			end

			-- 쿨다운 표시/숨김: secret boolean도 C++에서 처리
			if auraInstanceID and C_UnitAuras and C_UnitAuras.DoesAuraHaveExpirationTime then
				local hasExp = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
				if button.Cooldown.SetShownFromBoolean then
					button.Cooldown:SetShownFromBoolean(hasExp)
				else
					-- fallback: secret이 아닌 경우만 비교
					if not (issecretvalue and issecretvalue(hasExp)) then
						if hasExp then button.Cooldown:Show() else button.Cooldown:Hide() end
					else
						button.Cooldown:Show() -- secret이면 표시
					end
				end
			else
				-- API 없으면 duration으로 판단
				local dur = SafeNum(auraData.duration, 0)
				if dur > 0 then button.Cooldown:Show() else button.Cooldown:Hide() end
			end
		end

		-- 스택 (DandersFrames 패턴: GetAuraApplicationDisplayCount)
		button.Count:SetText("")
		local auraInstanceID = auraData.auraInstanceID
		if auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
			local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
			if stackText then
				button.Count:SetText(stackText)
				button.Count:Show()
			else
				button.Count:Hide()
			end
		else
			local count = SafeNum(auraData.applications, 0)
			if count > 1 then
				button.Count:SetText(count)
				button.Count:Show()
			else
				button.Count:Hide()
			end
		end

		-- PostUpdateButton 콜백
		if element.PostUpdateButton then
			element:PostUpdateButton(button, unit, auraData, idx)
		end

		button:Show()
	end

	-- 위치 배치
	if element.SetPosition and displayCount > 0 then
		element:SetPosition(1, displayCount)
	else
		-- 기본 배치: oUF 기본 패턴
		local anchor = element.initialAnchor or "BOTTOMLEFT"
		local growX = element.growthX or "RIGHT"
		local growY = element.growthY or "UP"
		local maxCols = element.maxCols or element.num or displayCount
		local spacingX = element.spacingX or element.spacing or 2
		local spacingY = element.spacingY or element.spacing or 2

		for i = 1, displayCount do
			local button = element[i]
			if button then
				local col = (i - 1) % maxCols
				local row = math.floor((i - 1) / maxCols)

				local xMul = (growX == "LEFT") and -1 or 1
				local yMul = (growY == "DOWN") and -1 or 1

				button:ClearAllPoints()
				button:SetPoint(anchor, element, anchor,
					col * (buttonSize + spacingX) * xMul,
					row * (buttonSize + spacingY) * yMul)
			end
		end
	end
end

-----------------------------------------------
-- All Indicators Update
-----------------------------------------------

function Drivers:UpdateAllIndicators(frame)
	self:UpdateRaidTargetIndicator(frame)
	self:UpdateGroupRoleIndicator(frame)
	self:UpdateReadyCheckIndicator(frame)
	self:UpdateResurrectIndicator(frame)
	self:UpdateLeaderIndicator(frame)
	self:UpdateCombatIndicator(frame)
	self:UpdateRestingIndicator(frame)
	self:UpdateThreatIndicator(frame)
	self:UpdateHighlight(frame)
end

-----------------------------------------------
-- Full Update
-----------------------------------------------

function Drivers:UpdateAll(frame)
	self:UpdateHealth(frame)
	self:UpdatePower(frame)
	self:UpdateHealthPrediction(frame)
	self:UpdateClassPower(frame)
	self:UpdateAuras(frame)
	self:UpdateAllIndicators(frame)
	self:UpdateRange(frame)
	self:UpdateDispelHighlight(frame)

	-- Tag 갱신
	if ns.TagEngine then
		ns.TagEngine:UpdateAll(frame)
	end
end

ns.Debug("ElementDrivers.lua loaded")
