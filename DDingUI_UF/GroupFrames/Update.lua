--[[
	ddingUI UnitFrames
	GroupFrames/Update.lua — 프레임 업데이트 함수

	DandersFrames UpdateUnitFrame/UpdateHealthFast/UpdatePower 패턴
	Secret-safe: 체력/자원은 StatusBar API로 직접 설정 (값 비교 회피)
]]

local _, ns = ...
local GF = ns.GroupFrames

local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitName = UnitName
local UnitClass = UnitClass
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsGroupLeader = UnitIsGroupLeader
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local UnitIsAFK = UnitIsAFK
local GetReadyCheckStatus = GetReadyCheckStatus
local UnitReaction = UnitReaction
local UnitThreatSituation = UnitThreatSituation
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor

local issecretvalue = issecretvalue
local SafeVal = ns.SafeVal   -- [REFACTOR] 통합 유틸리티 참조
local SafeNum = ns.SafeNum   -- [REFACTOR]
local C = ns.Constants       -- [REFACTOR] 아이콘 세트 등 상수 참조
local unpack = unpack
local UnitHealthPercent = UnitHealthPercent   -- [12.0.1] secret-safe 백분율 API
local UnitHealthMissing = UnitHealthMissing   -- [12.0.1] deficit API
local AbbreviateNumbers = function(v) return ns.Abbreviate(v) end

-----------------------------------------------
-- Shared Media Helper
-----------------------------------------------

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local function ResolveLSM(mediaType, val, fallback)
	if not val then return fallback end
	if type(val) == "string" and val:find("[/\\]") then return val end
	if LSM then
		local resolved = LSM:Fetch(mediaType, val)
		if resolved then return resolved end
	end
	return fallback
end


-----------------------------------------------
-- GetSafeHealthPercent (DF 패턴: secret-safe)
-- UnitHealthPercent + CurveConstants.ScaleTo100 → 0-100 직접 반환
-----------------------------------------------

-- [PERF] pcall 제거 (DandersFrames 패턴: UnitHealthPercent는 직접 호출 안전)
local function GetSafeHealthPercent(unit)
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
		if pct then
			if issecretvalue and issecretvalue(pct) then return 100 end
			return pct
		end
	end
	-- Fallback: 직접 계산
	local cur = UnitHealth(unit)
	local max = UnitHealthMax(unit)
	if not cur or not max then return 100 end
	if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then return 100 end
	if max == 0 then return 100 end
	return cur / max * 100
end

-----------------------------------------------
-- UpdateHealthFast (고빈도 — UNIT_HEALTH)
-----------------------------------------------

function GF:UpdateHealthFast(frame)
	if not frame or not frame.unit then return end
	local unit = frame.unit
	if not UnitExists(unit) then return end

	local healthBar = frame.healthBar
	if not healthBar then return end

	-- [12.0.1] Secret-safe: StatusBar API로 직접 설정 (UpdatePower 패턴)
	-- UnitHealth/UnitHealthMax → StatusBar가 C++ 레벨에서 secret number 처리
	healthBar:SetMinMaxValues(0, UnitHealthMax(unit))
	healthBar:SetValue(UnitHealth(unit))

	-- 체력 색상
	self:ApplyHealthColor(frame)

	-- 체력 텍스트
	self:UpdateHealthText(frame)
	self:UpdateCustomTexts(frame)
	
	-- 상태 아이콘/텍스트 (부활 시 Dead 상태 즉시 해제) -- [FIX]
	if self.UpdateStatusIcons then
		self:UpdateStatusIcons(frame)
	end
end

-----------------------------------------------
-- ApplyHealthColor — 직업색/반응색/커스텀
-----------------------------------------------

function GF:ApplyHealthColor(frame)
	if not frame or not frame.unit then return end
	local db = self:GetFrameDB(frame)
	local colorType = db.healthBarColorType or "class"
	local unit = frame.unit

	local r, g, b = 0.2, 0.8, 0.2 -- 기본 녹색

	-- [12.0.1] 색상 우선순위 (깜빡임 방지):
	-- 죽음/오프라인 > HoT healthColor > 일반 class/reaction
	-- [FIX] 디버프 하이라이트는 overlay/gradient/border로 표현되므로
	-- 체력바 색상(healthColor)과는 독립적 — 동시 표시 가능
	if frame.hotHealthColorActive and frame.hotHealthColorData then
		local hc = frame.hotHealthColorData
		r, g, b = hc[1], hc[2], hc[3]
	elseif colorType == "class" then
		local _, className = UnitClass(unit)
		if className then
			local cc = RAID_CLASS_COLORS[className]
			if cc then
				r, g, b = cc.r, cc.g, cc.b
			end
		end
	elseif colorType == "custom" then
		local c = db.healthBarColor or { 0.2, 0.8, 0.2, 1 }
		r, g, b = c[1], c[2], c[3]
	elseif colorType == "reaction" then
		-- [REFACTOR] 진영 색상 (적/중립/우호) — secret number 방어
		if UnitReaction then
			local reaction = UnitReaction("player", unit)
			if reaction and not (issecretvalue and issecretvalue(reaction)) then
				if reaction <= 3 then
					r, g, b = 0.8, 0.2, 0.2 -- 적대
				elseif reaction == 4 then
					r, g, b = 0.9, 0.7, 0.0 -- 중립
				else
					r, g, b = 0.2, 0.8, 0.2 -- 우호
				end
			end
		end
	elseif colorType == "smooth" then
		-- [12.0.1] 그라디언트 (체력% 기반 빨강→노랑→초록) — secret-safe
		local pct = GetSafeHealthPercent(unit) / 100 -- 0-1 범위로 변환
		if pct then
			if pct > 0.5 then
				local t = (pct - 0.5) * 2
				r = 1 - t
				g = 0.8 + 0.2 * t
				b = 0
			else
				local t = pct * 2
				r = 1
				g = t * 0.8
				b = 0
			end
		end
	end

	-- [12.0.1] 죽음/오프라인/유령 상태 → 색상 오버라이드
	-- [FIX] DandersFrames 패턴: UnitIsDeadOrGhost 사용 (secret boolean 대응)
	-- SafeVal은 secret boolean → nil 변환이라 사망 판정 실패 가능
	-- UnitIsDeadOrGhost는 단일 API로 Dead+Ghost 모두 감지, secret boolean도 안전하게 처리
	local ufColors = ns.Colors and ns.Colors.unitFrames

	-- [AUDIT-FIX] S2: pcall 제거 → SafeBool 사용 (API 자체는 에러 미발생)
	local isDeadOrGhost = ns.SafeBool(UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))

	local isConn = UnitIsConnected(unit)
	local isOffline = false
	if isConn ~= nil then
		if issecretvalue and issecretvalue(isConn) then
			isOffline = false
		else
			isOffline = not isConn
		end
	end

	if isDeadOrGhost then
		local dc = ufColors and ufColors.deathColor or { 0.47, 0.47, 0.47, 1 }
		-- [FIX] DandersFrames 패턴: 사망 시 배경색(frame.background) 변경
		-- frame.healthBar.bg는 그룹 프레임에 존재하지 않음!
		if frame.background then
			frame.background:SetVertexColor(dc[1], dc[2], dc[3], dc[4] or 1)
		end
		frame.healthBar:SetStatusBarColor(dc[1], dc[2], dc[3], 1)
	elseif isOffline then
		local oc = ufColors and ufColors.offlineColor or { 0.5, 0.5, 0.5, 1 }
		if frame.background then
			frame.background:SetVertexColor(oc[1], oc[2], oc[3], oc[4] or 1)
		end
		frame.healthBar:SetStatusBarColor(oc[1], oc[2], oc[3], 1)
	else
		-- 정상 상태: 배경색 복원
		if frame.background then
			local db = self:GetFrameDB(frame)
			local bgColor = db.background and db.background.color or { 0.08, 0.08, 0.08, 0.85 }
			frame.background:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.85)
		end
		frame.healthBar:SetStatusBarColor(r, g, b, 1)
	end
end

-----------------------------------------------
-- UpdateHealthText (secret-safe: DF 패턴)
-- [12.0.1] UnitHealthPercent + SetFormattedText 사용
-- secret value로 직접 연산(+, -, *, /, 비교) 금지
-----------------------------------------------

-- [PERF] Blizzard AbbreviateNumbers 없으면 fallback
local function SafeAbbreviate(val)
	if AbbreviateNumbers then return AbbreviateNumbers(val) end
	-- fallback: SetFormattedText가 secret을 내부 처리
	return val
end

function GF:UpdateHealthText(frame)
	if not frame or not frame.healthText then return end
	local db = self:GetFrameDB(frame)
	local widgets = db.widgets or {}
	local htDB = widgets.healthText or {}

	if htDB.enabled == false then
		frame.healthText:Hide()
		return
	end

	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		frame.healthText:SetText("")
		return
	end

	-- [FIX] secret boolean 방어 — DandersFrames 패턴: UnitIsDeadOrGhost 사용
	local rawDeadOrGhost2 = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
	if rawDeadOrGhost2 ~= nil then
		local isActuallyDead = false
		if issecretvalue and issecretvalue(rawDeadOrGhost2) then
			-- secret → 개별 체크
			local rawD = UnitIsDead(unit)
			local rawG = UnitIsGhost(unit)
			if rawD and not (issecretvalue and issecretvalue(rawD)) then
				isActuallyDead = true
			elseif rawG and not (issecretvalue and issecretvalue(rawG)) then
				isActuallyDead = true
			else
				local curHP = UnitHealth(unit)
				if curHP and not (issecretvalue and issecretvalue(curHP)) and curHP == 0 then
					isActuallyDead = true
				end
			end
		else
			isActuallyDead = rawDeadOrGhost2 and true or false
		end
		if isActuallyDead then
			frame.healthText:SetText("")
			return
		end
	end
	local isConn = UnitIsConnected(unit)
	if isConn ~= nil and not (issecretvalue and issecretvalue(isConn)) and not isConn then
		frame.healthText:SetText("")
		return
	end

	local fmt = htDB.format or "percentage"
	local hideIfFull = htDB.hideIfFull
	local separator = htDB.separator or "/"
	local text = ""

	-- [12.0.1] Secret-safe: UnitHealthPercent (DF 패턴)
	-- UnitHealth/UnitHealthMax가 secret number를 반환하면 직접 연산 불가
	-- → UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) 사용
	-- → SetFormattedText/AbbreviateNumbers는 Blizzard가 내부 처리

	local textAlreadySet = false -- [12.0.1] SetFormattedText 사용 시 true

	if fmt == "percentage" then
		-- [PERF] pcall 제거: UnitHealthPercent 직접 호출 + SetFormattedText가 secret 내부 처리
		if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
			local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
			if pct then
				if hideIfFull and not (issecretvalue and issecretvalue(pct)) and pct >= 99.9 then
					text = ""
				else
					frame.healthText:SetFormattedText("%.0f%%", pct)
					textAlreadySet = true
				end
			else
				local safePct = GetSafeHealthPercent(unit)
				if hideIfFull and safePct >= 99.9 then text = "" else text = string.format("%.0f%%", safePct) end
			end
		else
			local safePct = GetSafeHealthPercent(unit)
			if hideIfFull and safePct >= 99.9 then text = "" else text = string.format("%.0f%%", safePct) end
		end

	elseif fmt == "current" then
		-- [12.0.1] AbbreviateNumbers가 secret 내부 처리 (closure 제거)
		local cur = UnitHealth(unit)
		text = (cur and SafeAbbreviate(cur)) or ""

	elseif fmt == "deficit" then
		-- [12.0.1] UnitHealthMissing → deficit 직접 반환 (closure 제거)
		if UnitHealthMissing then
			local deficit = UnitHealthMissing(unit, true)
			if deficit and not (issecretvalue and issecretvalue(deficit)) then
				if C_StringUtil and C_StringUtil.TruncateWhenZero and C_StringUtil.WrapString then
					local truncated = C_StringUtil.TruncateWhenZero(deficit)
					text = C_StringUtil.WrapString(truncated, "-")
				else
					text = string.format("-%s", SafeAbbreviate(deficit) or deficit)
				end
			end
		end

	elseif fmt == "current-max" then
		-- [12.0.1] 각 값을 개별 AbbreviateNumbers로 처리 (closure 제거)
		local cur = UnitHealth(unit)
		local max = UnitHealthMax(unit)
		local curStr = (cur and SafeAbbreviate(cur)) or ""
		local maxStr = (max and SafeAbbreviate(max)) or ""
		text = curStr .. separator .. maxStr

	elseif fmt == "current-percentage" then
		-- [PERF] pcall 제거: UnitHealthPercent 직접 호출
		local cur = UnitHealth(unit)
		if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
			local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
			if pct then
				local curStr = (cur and SafeAbbreviate(cur)) or ""
				frame.healthText:SetFormattedText("%s %.0f%%", curStr, pct)
				textAlreadySet = true
			else
				local safePct = GetSafeHealthPercent(unit)
				local curStr = (cur and SafeAbbreviate(cur)) or ""
				text = curStr .. " " .. string.format("%.0f%%", safePct)
			end
		else
			local safePct = GetSafeHealthPercent(unit)
			local curStr = (cur and SafeAbbreviate(cur)) or ""
			text = curStr .. " " .. string.format("%.0f%%", safePct)
		end

	else
		-- fallback: percentage
		local pct = GetSafeHealthPercent(unit)
		text = string.format("%.0f%%", pct)
	end

	-- 체력 텍스트 색상 적용
	local colorOpt = htDB.color or {}
	local colorType = colorOpt.type or "custom"
	if colorType == "class_color" then
		local _, className = UnitClass(unit)
		if className then
			local cc = RAID_CLASS_COLORS[className]
			if cc then
				frame.healthText:SetTextColor(cc.r, cc.g, cc.b, 1)
			else
				frame.healthText:SetTextColor(1, 1, 1, 1)
			end
		else
			frame.healthText:SetTextColor(1, 1, 1, 1)
		end
	elseif colorType == "reaction_color" then
		-- [AUDIT-FIX] C2: secret number로 테이블 인덱싱 방지
		local reaction = UnitReaction(unit, "player")
		if reaction and not (issecretvalue and issecretvalue(reaction)) then
			local rc = FACTION_BAR_COLORS[reaction]
			if rc then
				frame.healthText:SetTextColor(rc.r, rc.g, rc.b, 1)
			else
				frame.healthText:SetTextColor(1, 1, 1, 1)
			end
		else
			frame.healthText:SetTextColor(1, 1, 1, 1)
		end
	elseif colorType == "power_color" then
		-- [AUDIT-FIX] 기력 색상: pToken(string)으로 조회 (secret 방지)
		local _, pToken = UnitPowerType(unit)
		if pToken and not (issecretvalue and issecretvalue(pToken)) then
			local pc = PowerBarColor[pToken]
			if pc then
				frame.healthText:SetTextColor(pc.r or 0.5, pc.g or 0.5, pc.b or 0.5, 1)
			else
				frame.healthText:SetTextColor(1, 1, 1, 1)
			end
		else
			frame.healthText:SetTextColor(1, 1, 1, 1)
		end
	elseif colorType == "health_gradient" then
		-- [FIX] 체력 그라데이션: HP%에 따라 빨강→노랑→초록
		local pct = GetSafeHealthPercent(unit) / 100
		local r, g
		if pct > 0.5 then
			r = (1.0 - pct) * 2
			g = 1.0
		else
			r = 1.0
			g = pct * 2
		end
		frame.healthText:SetTextColor(r, g, 0, 1)
	elseif colorType == "custom" then
		local rgb = colorOpt.rgb or { 1, 1, 1 }
		frame.healthText:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
	else
		frame.healthText:SetTextColor(1, 1, 1, 1)
	end

	if not textAlreadySet then
		frame.healthText:SetText(text)
	end
	frame.healthText:Show()
end

-----------------------------------------------
-- UpdatePower
-----------------------------------------------

function GF:UpdatePower(frame)
	if not frame or not frame.unit then return end
	local unit = frame.unit
	if not UnitExists(unit) then return end

	local powerBar = frame.powerBar
	if not powerBar or not powerBar:IsShown() then return end

	-- [AUDIT-FIX] C1: powerType을 인자로 전달하지 않음 (secret number taint 방지)
	-- UnitPower(unit), UnitPowerMax(unit)는 기본 자원 타입을 C++에서 자동 결정
	powerBar:SetMinMaxValues(0, UnitPowerMax(unit))
	powerBar:SetValue(UnitPower(unit))

	-- [AUDIT-FIX] 색상: pToken(string)으로만 조회 (number powerType 미사용)
	local _, pToken = UnitPowerType(unit)
	if pToken and not (issecretvalue and issecretvalue(pToken)) then
		local pColor = PowerBarColor[pToken]
		if pColor then
			powerBar:SetStatusBarColor(pColor.r or 0.5, pColor.g or 0.5, pColor.b or 0.5, 1)
		end
	else
		powerBar:SetStatusBarColor(0.24, 0.49, 1.0, 1) -- 기본 마나 색상 fallback
	end
end

-----------------------------------------------
-- UpdateName
-----------------------------------------------

function GF:UpdateName(frame)
	if not frame or not frame.nameText or not frame.unit then return end
	local unit = frame.unit
	if not UnitExists(unit) then return end

	local name = UnitName(unit) or unit
	local db = self:GetFrameDB(frame)
	local widgets = db.widgets or {}
	local nameDB = widgets.nameText or {}

	-- [REFACTOR] 이름 형식 적용
	local nameFormat = nameDB.format or "name"
	if nameFormat == "name:abbrev" then
		-- 3자로 줄임 (한글: 2자)
		if name and #name > 6 then
			name = name:sub(1, 6) .. "."
		end
	elseif nameFormat == "name:short" then
		-- 첫 단어만
		name = name:match("^(%S+)") or name
	end

	-- [REFACTOR] 색상 모드 적용
	local colorOpt = nameDB.color or {}
	local colorType = colorOpt.type or "class_color"

	if colorType == "class_color" then
		local _, className = UnitClass(unit)
		if className then
			local cc = RAID_CLASS_COLORS[className]
			if cc then
				frame.nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
			else
				frame.nameText:SetTextColor(1, 1, 1, 1)
			end
		else
			frame.nameText:SetTextColor(1, 1, 1, 1)
		end
	elseif colorType == "reaction_color" then
		-- [AUDIT-FIX] C2: secret number로 테이블 인덱싱 방지
		local reaction = UnitReaction(unit, "player")
		if reaction and not (issecretvalue and issecretvalue(reaction)) then
			local rc = FACTION_BAR_COLORS[reaction]
			if rc then
				frame.nameText:SetTextColor(rc.r, rc.g, rc.b, 1)
			else
				frame.nameText:SetTextColor(1, 1, 1, 1)
			end
		else
			frame.nameText:SetTextColor(1, 1, 1, 1)
		end
	elseif colorType == "power_color" then
		-- [AUDIT-FIX] 기력 색상: pToken(string)으로 조회 (secret 방지)
		local _, pToken = UnitPowerType(unit)
		if pToken and not (issecretvalue and issecretvalue(pToken)) then
			local pc = PowerBarColor[pToken]
			if pc then
				frame.nameText:SetTextColor(pc.r or 0.5, pc.g or 0.5, pc.b or 0.5, 1)
			else
				frame.nameText:SetTextColor(1, 1, 1, 1)
			end
		else
			frame.nameText:SetTextColor(1, 1, 1, 1)
		end
	elseif colorType == "health_gradient" then
		-- [FIX] 체력 그라데이션
		local pct = GetSafeHealthPercent(unit) / 100
		local r, g
		if pct > 0.5 then
			r = (1.0 - pct) * 2
			g = 1.0
		else
			r = 1.0
			g = pct * 2
		end
		frame.nameText:SetTextColor(r, g, 0, 1)
	elseif colorType == "custom" then
		local rgb = colorOpt.rgb or { 1, 1, 1 }
		frame.nameText:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
	else
		frame.nameText:SetTextColor(1, 1, 1, 1)
	end

	frame.nameText:SetText(name)
end

-----------------------------------------------
-- UpdateCustomTexts (커스텀 텍스트 업데이트) -- [FIX] 그룹프레임 커스텀텍스트
-----------------------------------------------

function GF:UpdateCustomTexts(frame)
	if not frame or not frame.customTexts or not frame.unit then return end
	local unit = frame.unit
	if not UnitExists(unit) then return end

	local TF = ns.TextFormats
	if not TF or not TF.CreateCompoundUpdater then return end

	for key, fs in pairs(frame.customTexts) do
		if fs._tagString and fs._tagString ~= "" then
			-- updater 캐시 (매 프레임 생성 방지)
			if not fs._updater then
				fs._updater = TF:CreateCompoundUpdater(fs._tagString)
			end
			if fs._updater then
				local ok, text = pcall(fs._updater, unit)
				if ok and text then
					fs:SetText(text)
					fs:Show()
				else
					fs:SetText("")
				end
			else
				fs:SetText("")
			end
		else
			fs:SetText("")
		end
	end
end

-----------------------------------------------
-- UpdateRoleIcon
-----------------------------------------------

function GF:UpdateRoleIcon(frame)
	if not frame or not frame.roleIcon or not frame.unit then return end
	local db = self:GetFrameDB(frame)
	local widgets = db.widgets or {}
	local roleDB = widgets.roleIcon or {}

	if roleDB.enabled == false then
		frame.roleIcon:Hide()
		return
	end

	-- [REFACTOR] 아이콘 세트 기반 역할 아이콘 (개별 텍스처 모드 지원)
	local iconSet = C.ICON_SETS[ns.db.iconSet or "default"] or C.ICON_SETS["default"]
	local role = UnitGroupRolesAssigned(frame.unit)

	-- [FIX] 역할별 필터: 탱커/힐러/딜러 개별 표시 설정
	if role == "TANK" and roleDB.showTank == false then
		frame.roleIcon:Hide()
		return
	elseif role == "HEALER" and roleDB.showHealer == false then
		frame.roleIcon:Hide()
		return
	elseif role == "DAMAGER" and roleDB.showDPS == false then
		frame.roleIcon:Hide()
		return
	end

	if iconSet.role.textures and iconSet.role.textures[role] then
		frame.roleIcon:SetTexture(iconSet.role.textures[role])
		frame.roleIcon:SetTexCoord(0, 1, 0, 1)
		frame.roleIcon:Show()
	elseif iconSet.role.coords and iconSet.role.coords[role] then
		frame.roleIcon:SetTexture(iconSet.role.texture)
		frame.roleIcon:SetTexCoord(unpack(iconSet.role.coords[role]))
		frame.roleIcon:Show()
	else
		frame.roleIcon:Hide()
	end
end

-----------------------------------------------
-- UpdateLeaderIcon
-----------------------------------------------

function GF:UpdateLeaderIcon(frame)
	if not frame or not frame.leaderIcon or not frame.unit then return end
	-- [12.0.1] secret boolean 방어 + 아이콘 세트 텍스처 갱신
	if SafeVal(UnitIsGroupLeader(frame.unit)) then
		local iconSet = C.ICON_SETS[ns.db.iconSet or "default"] or C.ICON_SETS["default"]
		frame.leaderIcon:SetTexture(iconSet.leader)
		frame.leaderIcon:Show()
	else
		frame.leaderIcon:Hide()
	end
end

-----------------------------------------------
-- UpdateRaidTargetIcon
-----------------------------------------------

function GF:UpdateRaidTargetIcon(frame)
	if not frame or not frame.raidTargetIcon or not frame.unit then return end
	local index = GetRaidTargetIndex(frame.unit)
	if index then
		SetRaidTargetIconTexture(frame.raidTargetIcon, index)
		frame.raidTargetIcon:Show()
	else
		frame.raidTargetIcon:Hide()
	end
end

-----------------------------------------------
-- UpdateReadyCheck
-----------------------------------------------

function GF:UpdateReadyCheck(frame, event)
	if not frame or not frame.readyCheckIcon or not frame.unit then return end

	if event == "READY_CHECK_FINISHED" then
		frame.readyCheckIcon:Hide()
		return
	end

	local status = GetReadyCheckStatus(frame.unit)
	if status == "ready" then
		frame.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
		frame.readyCheckIcon:Show()
	elseif status == "notready" then
		frame.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
		frame.readyCheckIcon:Show()
	elseif status == "waiting" then
		frame.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
		frame.readyCheckIcon:Show()
	else
		frame.readyCheckIcon:Hide()
	end
end

-----------------------------------------------
-- UpdateStatusIcons (AFK, 부활, 소환)
-----------------------------------------------

function GF:UpdateStatusIcons(frame)
	if not frame or not frame.unit then return end
	local unit = frame.unit
	if not UnitExists(unit) then return end

	-- 부활 아이콘 -- [12.0.1] secret boolean 방어
	if frame.resurrectIcon then
		local hasRes = SafeVal(UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit))
		if hasRes then
			frame.resurrectIcon:Show()
		else
			frame.resurrectIcon:Hide()
		end
	end

	-- 상태 텍스트 (AFK+시간/Offline/Dead/Ghost/소환) -- [FIX] AFK 시간 + 소환 상태 추가
	if frame.statusText then
		-- AFK 체크
		local isAFK = SafeVal(UnitIsAFK(unit))
		-- 연결 체크
		local connVal = SafeVal(UnitIsConnected(unit))
		local isDisconnected = (connVal ~= nil) and (not connVal)
		-- [FIX] 사망/유령 체크
		local isDeadOrGhostSI = SafeVal(UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
		if isDeadOrGhostSI == nil then
			-- secret → 개별 체크 + HP 폴백
			local isDead = SafeVal(UnitIsDead(unit))
			local isGhost = SafeVal(UnitIsGhost(unit))
			if isDead or isGhost then
				isDeadOrGhostSI = true
			else
				local curHP = UnitHealth(unit)
				if curHP and not (issecretvalue and issecretvalue(curHP)) and curHP == 0 then
					isDeadOrGhostSI = true
				end
			end
		end
		-- 유령 여부 (Dead vs Ghost 텍스트 구분용)
		local isGhostSI = isDeadOrGhostSI and SafeVal(UnitIsGhost(unit))

		-- 소환 상태 체크
		local summonStatus = 0
		if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
			local ok, status = pcall(C_IncomingSummon.IncomingSummonStatus, unit)
			if ok and status then summonStatus = status end
		end

		-- 우선순위: Dead/Ghost > Offline > 소환 > AFK
		if isDeadOrGhostSI then
			if isGhostSI then
				frame.statusText:SetText("|cff999999|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:16:16:0:-1|tGhost|r")
			else
				frame.statusText:SetText("|cffcc3333|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:16:16:0:-1|tDead|r")
			end
			frame.statusText:Show()
			frame._afkStartTime = nil
			frame._offlineStartTime = nil
		elseif isDisconnected then
			-- Offline 경과 시간 추적
			if not frame._offlineStartTime then
				frame._offlineStartTime = GetTime()
			end
			local elapsed = GetTime() - frame._offlineStartTime
			local offText
			if elapsed >= 3600 then
				offText = string.format("|cff999999|TInterface\\FriendsFrame\\StatusIcon-Offline:16:16:0:-1|tOffline %dh%dm|r", elapsed / 3600, (elapsed % 3600) / 60)
			elseif elapsed >= 60 then
				offText = string.format("|cff999999|TInterface\\FriendsFrame\\StatusIcon-Offline:16:16:0:-1|tOffline %dm%ds|r", elapsed / 60, elapsed % 60)
			else
				offText = "|cff999999|TInterface\\FriendsFrame\\StatusIcon-Offline:16:16:0:-1|tOffline|r"
			end
			frame.statusText:SetText(offText)
			frame.statusText:Show()
			frame._afkStartTime = nil
		elseif summonStatus == 1 then -- Pending
			frame.statusText:SetText("|cff00ccff|TInterface\\Icons\\Spell_Magic_SummonFast:16:16:0:-1|t소환 대기중|r")
			frame.statusText:Show()
			frame._offlineStartTime = nil
		elseif summonStatus == 2 then -- Accepted
			frame.statusText:SetText("|cff00ff00|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16:0:-1|t소환 수락|r")
			frame.statusText:Show()
			frame._offlineStartTime = nil
		elseif summonStatus == 3 then -- Declined
			frame.statusText:SetText("|cffff3333|TInterface\\RaidFrame\\ReadyCheck-NotReady:16:16:0:-1|t소환 거절|r")
			frame.statusText:Show()
			frame._offlineStartTime = nil
		elseif isAFK then
			-- AFK 경과 시간 추적
			if not frame._afkStartTime then
				frame._afkStartTime = GetTime()
			end
			local elapsed = GetTime() - frame._afkStartTime
			local afkText
			if elapsed >= 3600 then
				afkText = string.format("|cffcccc00|TInterface\\FriendsFrame\\StatusIcon-Away:16:16:0:-1|tAFK %dh%dm|r", elapsed / 3600, (elapsed % 3600) / 60)
			elseif elapsed >= 60 then
				afkText = string.format("|cffcccc00|TInterface\\FriendsFrame\\StatusIcon-Away:16:16:0:-1|tAFK %dm%ds|r", elapsed / 60, elapsed % 60)
			else
				afkText = "|cffcccc00|TInterface\\FriendsFrame\\StatusIcon-Away:16:16:0:-1|tAFK|r"
			end
			frame.statusText:SetText(afkText)
			frame.statusText:Show()
			frame._offlineStartTime = nil
		else
			frame.statusText:Hide()
			frame._afkStartTime = nil
			frame._offlineStartTime = nil
		end
	end
end

-----------------------------------------------
-- UpdateHealPrediction — 힐 예측 + 보호막 + 힐 흡수 -- [12.0.1]
-- DandersFrames OVERLAY 패턴: healthFillTexture 기준 앵커
-- Secret-safe: StatusBar가 내부에서 secret value 연산 처리
-----------------------------------------------

local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitGetIncomingHeals = UnitGetIncomingHeals
local CreateUnitHealPredictionCalculator = CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction

-- [PERF] 힐 예측 state-based pcall: 매 호출 closure 생성 방지 (UNIT_HEALTH 고빈도)
local HealPredState = { unit = nil, calc = nil, result = 0 }
local function GetHealPredictionSafe()
	UnitGetDetailedHealPrediction(HealPredState.unit, nil, HealPredState.calc)
	HealPredState.result = HealPredState.calc:GetIncomingHeals()
end

function GF:UpdateHealPrediction(frame)
	if not frame or not frame.unit then return end
	local unit = frame.unit
	if not UnitExists(unit) then return end

	-- [FIX] DandersFrames 패턴: 매 업데이트마다 parent 보장
	-- /reload 시 이전 C++ 프레임이 healthBar 자식으로 남아있을 수 있음
	if frame.healPredictionBar and frame.healPredictionBar:GetParent() ~= frame then
		frame.healPredictionBar:SetParent(frame)
	end
	if frame.absorbBar and frame.absorbBar:GetParent() ~= frame then
		frame.absorbBar:SetParent(frame)
	end
	if frame.overShieldBar and frame.overShieldBar:GetParent() ~= frame then
		frame.overShieldBar:SetParent(frame)
	end
	if frame.healAbsorbBar and frame.healAbsorbBar:GetParent() ~= frame then
		frame.healAbsorbBar:SetParent(frame)
	end



	local healthBar = frame.healthBar
	if not healthBar then return end
	local healthFill = healthBar:GetStatusBarTexture()
	if not healthFill then return end

	local db = self:GetFrameDB(frame)
	local widgets = db.widgets or {}

	-- [DandersFrames 패턴] border inset 적용 — 보호막/힐예측 바가 보더와 겹치지 않도록
	local borderDB = db and db.border
	local borderInset = 0
	if borderDB and borderDB.enabled ~= false then
		borderInset = borderDB.size or 1
	end
	local barWidth = healthBar:GetWidth() - (borderInset * 2)
	local barHeight = healthBar:GetHeight() - (borderInset * 2)
	if barWidth <= 0 or barHeight <= 0 then return end
	local maxHealth = UnitHealthMax(unit)

	-- ========================================
	-- 1. HEAL PREDICTION (힐 예측)
	-- ========================================
	local healBar = frame.healPredictionBar
	if healBar then
		local hpDB = widgets.healPrediction or {}
		if hpDB.enabled == false then
			healBar:Hide()
		else
			-- [12.0.1] CreateUnitHealPredictionCalculator 우선 (secret-safe)
			-- [PERF] state-based pcall: closure 생성 0회 (UNIT_HEALTH 고빈도 최적화)
			local incomingHeals = 0
			if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
				if not frame._healCalc then
					frame._healCalc = CreateUnitHealPredictionCalculator()
					pcall(function()
						frame._healCalc:SetIncomingHealClampMode(0)
						frame._healCalc:SetIncomingHealOverflowPercent(1.0)
					end)
				end
				HealPredState.unit = unit
				HealPredState.calc = frame._healCalc
				HealPredState.result = 0
				if pcall(GetHealPredictionSafe) then
					incomingHeals = HealPredState.result
				end
			elseif UnitGetIncomingHeals then
				-- [PERF] pcall 제거: issecretvalue 체크로 충분 (ElvUI 패턴)
				local heals = UnitGetIncomingHeals(unit)
				if heals and not (issecretvalue and issecretvalue(heals)) then
					incomingHeals = heals
				end
			end

			-- [DandersFrames 패턴] 단일 앵커 + 명시적 Size (border inset 이미 반영됨)
			healBar:ClearAllPoints()
			healBar:SetPoint("LEFT", healthFill, "RIGHT", 0, 0)
			healBar:SetWidth(barWidth)
			healBar:SetHeight(barHeight)
			healBar:SetMinMaxValues(0, maxHealth)
			healBar:SetValue(incomingHeals)

			-- [FIX] 텍스쳐 적용: 위젯별(기본 WHITE8x8 제외) → 글로벌 미디어 텍스처 fallback (LSM 변환 적용)
			local hpTexRaw = hpDB.texture
			local hpTexture = (hpTexRaw and hpTexRaw ~= [[Interface\Buttons\WHITE8x8]] and hpTexRaw) or (ns.db and ns.db.media and ns.db.media.texture)
			local resolvedTex = ResolveLSM("statusbar", hpTexture)
			if resolvedTex and resolvedTex ~= [[Interface\Buttons\WHITE8x8]] then
				healBar:SetStatusBarTexture(resolvedTex)
			end

			-- [FIX] DandersFrames 패턴: 타일링 비활성화 및 텍스처 좌표 고정으로 1px edge bleeding 방지
			local hpBarTex = healBar:GetStatusBarTexture()
			if hpBarTex then
				hpBarTex:SetHorizTile(false)
				hpBarTex:SetVertTile(false)
				hpBarTex:SetTexCoord(0, 1, 0, 1)
			end

			-- [FIX] ns.Colors 글로벌 색상 우선 적용
			local color = (ns.Colors and ns.Colors.healPrediction and ns.Colors.healPrediction.color) or hpDB.color or { 0, 1, 0.5, 0.4 }
			healBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.4)
			healBar:Show()
		end
	end

	-- ========================================
	-- 2. ABSORB (보호막) + OVERSHIELD (초과 보호막) -- [12.0.1]
	-- DandersFrames ATTACHED_OVERFLOW 패턴:
	-- 풀피 → absorbBar 클리핑됨 → overShieldBar(ReverseFill)로 표시
	-- 비풀피 → absorbBar 정상 + 초과분은 overShieldBar로 추가
	-- ========================================
	local absBar = frame.absorbBar
	local overBar = frame.overShieldBar
	local overGlow = frame.overShieldGlow
	if absBar then
		local sbDB = widgets.shieldBar or {}
		if sbDB.enabled == false then
			absBar:Hide()
			if overBar then overBar:Hide() end
			if overGlow then overGlow:Hide() end
		else
			local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0

			-- [FIX] ns.Colors 글로벌 색상 우선 적용
			local color = (ns.Colors and ns.Colors.shieldBar and ns.Colors.shieldBar.shieldColor) or sbDB.color or { 1, 1, 0, 0.4 }

			-- [FIX] 텍스쳐 적용: 위젯별(기본 WHITE8x8 제외) → 글로벌 미디어 텍스처 fallback (LSM 변환 적용)
			local sbTexRaw = sbDB.texture
			local sbTexture = (sbTexRaw and sbTexRaw ~= [[Interface\Buttons\WHITE8x8]] and sbTexRaw) or (ns.db and ns.db.media and ns.db.media.texture)
			local resolvedTex = ResolveLSM("statusbar", sbTexture)
			if resolvedTex and resolvedTex ~= [[Interface\Buttons\WHITE8x8]] then
				absBar:SetStatusBarTexture(resolvedTex)
				if overBar then overBar:SetStatusBarTexture(resolvedTex) end
			end

			-- [12.0.1] 11.1 Secret-Safe Calculator
			local attachedAbsorbs = absorbs
			local isClamped = false
			if CreateUnitHealPredictionCalculator and unit then
				if not frame._absCalc then
					frame._absCalc = CreateUnitHealPredictionCalculator()
					pcall(function() frame._absCalc:SetDamageAbsorbClampMode(1) end) -- [FIX] 1 = Missing Health 기준 클램핑 (DandersFrames ATTACHED_OVERFLOW 패턴)
				end
				local calc = frame._absCalc
				UnitGetDetailedHealPrediction(unit, nil, calc)
				local ok, amt, clamped = pcall(function() return calc:GetDamageAbsorbs() end)
				if ok and amt then
					attachedAbsorbs = amt
					isClamped = clamped -- secret bool in M+
				end
			end

			local hasAnyAbsorb = true
			if not (issecretvalue and issecretvalue(attachedAbsorbs)) then
				hasAnyAbsorb = (attachedAbsorbs and attachedAbsorbs > 0)
			end

			local osColor = (ns.Colors and ns.Colors.shieldBar and ns.Colors.shieldBar.overshieldColor) or sbDB.overshieldColor or color

			if not hasAnyAbsorb then
				absBar:Hide()
				if overBar then overBar:Hide() end
				if overGlow then overGlow:Hide() end
			else
				local anchor = healthFill
				if healBar and healBar:IsShown() then
					local hpFill = healBar:GetStatusBarTexture()
					if hpFill then anchor = hpFill end
				end

				-- [DandersFrames 패턴] 단일 앵커 + 명시적 Size (border inset 이미 반영됨)
				absBar:ClearAllPoints()
				absBar:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
				absBar:SetWidth(barWidth)
				absBar:SetHeight(barHeight)
				absBar:SetMinMaxValues(0, maxHealth)
				absBar:SetValue(attachedAbsorbs)
				absBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.4)
				absBar:Show()

				-- [FIX] Secret Alpha visibility helper (DandersFrames 패턴)
				if absBar.SetAlphaFromBoolean then
					absBar:SetAlphaFromBoolean(isClamped, 0, 1) -- Inverse: 0 when clamped
				end

				-- OverShield Bar (OVERFLOW) — DandersFrames ATTACHED_OVERFLOW 패턴
				-- clamped → ATTACHED 숨기고 OVERLAY로 전체 보호막 표시
				if overBar then
					overBar:ClearAllPoints()
					overBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
					overBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
					overBar:SetReverseFill(true)
					overBar:SetMinMaxValues(0, maxHealth)
					overBar:SetValue(absorbs) -- [FIX] 원본 전체 보호막량 (클램핑 안 된 값)
					overBar:SetStatusBarColor(osColor[1], osColor[2], osColor[3], (osColor[4] or 0.4) * 0.7)
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

				-- OverShield Glow — 개별 프레임과 동일: 보호막 끝(ReverseFill LEFT)에 위치
				if overGlow and overBar then
					local overBarTex = overBar:GetStatusBarTexture()
					if overBarTex then
						overGlow:ClearAllPoints()
						overGlow:SetPoint("TOP", overBarTex, "TOPLEFT", 0, 0)
						overGlow:SetPoint("BOTTOM", overBarTex, "BOTTOMLEFT", 0, 0)
						overGlow:SetWidth(3)
					end
					overGlow:SetVertexColor(osColor[1], osColor[2], osColor[3], 0.8)
					overGlow:Show()

					if overGlow.SetAlphaFromBoolean then
						overGlow:SetAlphaFromBoolean(isClamped, 1, 0)
					else
						-- Fallback
						local clampedVal = false
						if not (issecretvalue and issecretvalue(isClamped)) then
							clampedVal = isClamped
						end
						if clampedVal then overGlow:SetAlpha(1) else overGlow:SetAlpha(0) end
					end
				end
			end
		end
	end

	-- ========================================
	-- 3. HEAL ABSORB (힐 흡수) — ReverseFill
	-- ========================================
	local haBar = frame.healAbsorbBar
	if haBar then
		local haDB = widgets.healAbsorb or {}
		if haDB.enabled == false then
			haBar:Hide()
		else
			-- [PERF] pcall 제거: StatusBar:SetValue()가 secret value 내부 처리
			local healAbsorb = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0

			-- [FIX] 치유 흡수 바 정렬 방향 (좌측/우측)
			local haPos = haDB.anchorPoint or "LEFT"
			haBar:ClearAllPoints()
			if haPos == "LEFT" then
				haBar:SetPoint("LEFT", healthFill, "LEFT", 0, 0)
				haBar:SetReverseFill(false)
			else
				haBar:SetPoint("RIGHT", healthFill, "RIGHT", 0, 0)
				haBar:SetReverseFill(true)
			end
			haBar:SetWidth(barWidth)
			haBar:SetHeight(barHeight)
			haBar:SetMinMaxValues(0, maxHealth)
			haBar:SetValue(healAbsorb)

			-- [FIX] 텍스쳐 적용: 위젯별 → 글로벌 미디어 텍스처 fallback (LSM 변환 적용)
			local haTexRaw = haDB.texture
			local haTexture = haTexRaw or (ns.db and ns.db.media and ns.db.media.texture)
			local resolvedTex = ResolveLSM("statusbar", haTexture)
			if resolvedTex then
				haBar:SetStatusBarTexture(resolvedTex)
			end

			-- [FIX] pixel bleeding 방지: 타일링 비활성화 + 텍스처 좌표 고정
			local haBarTex = haBar:GetStatusBarTexture()
			if haBarTex then
				haBarTex:SetHorizTile(false)
				haBarTex:SetVertTile(false)
				haBarTex:SetTexCoord(0, 1, 0, 1)
			end

			-- [FIX] ns.Colors 글로벌 색상 우선 적용
			local color = (ns.Colors and ns.Colors.healAbsorb and ns.Colors.healAbsorb.color) or haDB.color or { 1, 0.1, 0.1, 0.5 }
			haBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.5)
			haBar:Show()
		end
	end
end

-----------------------------------------------
-- [FIX] 오버레이 보더 우선순위 관리 — 겹침으로 인한 두께 누적 방지
-- 우선순위: threat > debuff > highlight > base
-- 활성 우선순위가 높은 보더만 표시, 나머지는 숨김
-----------------------------------------------
local function UpdateAllBorderVisibility(frame)
	if not frame then return end

	-- 우선순위 평가: 가장 높은 활성 보더 결정
	local activeBorder = nil -- "threat", "debuff", "highlight", "base"
	if frame._threatBorderActive then
		activeBorder = "threat"
	elseif frame.debuffHighlightActive then
		activeBorder = "debuff"
	elseif frame._highlightBorderActive then
		activeBorder = "highlight"
	else
		activeBorder = "base"
	end

	-- 각 보더의 가시성 설정 (활성 보더만 Show)
	if frame.threatBorder then
		if activeBorder == "threat" then
			frame.threatBorder:Show()
		else
			frame.threatBorder:Hide()
		end
	end
	if frame.debuffHighlight and frame.debuffHighlight.border then
		if activeBorder == "debuff" then
			frame.debuffHighlight.border:Show()
		else
			frame.debuffHighlight.border:Hide()
		end
	end
	if frame.highlightBorder then
		if activeBorder == "highlight" then
			frame.highlightBorder:Show()
		else
			frame.highlightBorder:Hide()
		end
	end
	if frame.border then
		if activeBorder == "base" then
			local GF = ns.GroupFrames
			if GF then
				local db = GF:GetFrameDB(frame)
				local borderDB = db and db.border
				if not borderDB or borderDB.enabled ~= false then
					frame.border:Show()
				end
			end
		else
			frame.border:Hide()
		end
	end
end
-- [FIX] ns에 공유 등록 → Auras.lua도 동일한 함수 사용 (중복 제거)
ns.UpdateBorderVisibility = UpdateAllBorderVisibility
-- backward compat alias
local UpdateBaseBorderVisibility = UpdateAllBorderVisibility

-----------------------------------------------
-- UpdateThreat — 위협 보더 표시 -- [12.0.1]
-----------------------------------------------

function GF:UpdateThreat(frame)
	if not frame or not frame.threatBorder or not frame.unit then return end
	local db = self:GetFrameDB(frame)
	local widgets = db.widgets or {}
	local threatDB = widgets.threat or {}

	if threatDB.enabled == false then
		frame.threatBorder:Hide()
		return
	end

	local unit = frame.unit
	if not UnitExists(unit) then
		frame.threatBorder:Hide()
		return
	end

	local status = UnitThreatSituation(unit)
	-- [12.0.1] secret value 방어
	if status and issecretvalue and issecretvalue(status) then
		status = nil
	end

	if status and status > 0 then
		local colors = threatDB.colors or {}
		local color = colors[status] or { 1, 0, 0, 1 }
		local borderSize = threatDB.borderSize or 1

		-- [FIX] 캐싱: 동일 값이면 SetHeight/SetWidth 스킵 (렌더링 캐시 무효화 방지)
		if frame.threatBorder._cachedSize ~= borderSize then
			frame.threatBorder.top:SetHeight(borderSize)
			frame.threatBorder.bottom:SetHeight(borderSize)
			frame.threatBorder.left:SetWidth(borderSize)
			frame.threatBorder.right:SetWidth(borderSize)
			frame.threatBorder._cachedSize = borderSize
		end
		frame.threatBorder:SetColor(color[1], color[2], color[3], color[4] or 1)
		frame._threatBorderActive = true
		UpdateAllBorderVisibility(frame) -- [FIX] 우선순위 기반 보더 관리
	else
		frame._threatBorderActive = false
		UpdateAllBorderVisibility(frame) -- [FIX] 우선순위 기반 보더 관리
	end
end

-----------------------------------------------
-- UpdateHighlight — 타겟/포커스 보더 표시 -- [12.0.1]
-----------------------------------------------

function GF:UpdateHighlight(frame)
	if not frame or not frame.highlightBorder or not frame.unit then return end
	-- [12.0.1] hover 활성 중이면 hover 해제 후 재평가
	if frame._gfHoverActive then
		frame._gfHoverActive = nil
	end

	local db = self:GetFrameDB(frame)
	local widgets = db.widgets or {}
	local hlDB = widgets.highlight or {}

	if hlDB.enabled == false then
		frame.highlightBorder:Hide()
		return
	end

	local unit = frame.unit
	if not UnitExists(unit) then
		frame.highlightBorder:Hide()
		return
	end

	local borderSize = hlDB.size or 1

	-- 타겟 우선 (타겟 + 포커스 동시일 때 타겟 색상)
	if hlDB.target ~= false and UnitIsUnit(unit, "target") then
		local color = hlDB.targetColor or { 1, 0.3, 0.3, 1 }
		if frame.highlightBorder._cachedSize ~= borderSize then
			frame.highlightBorder.top:SetHeight(borderSize)
			frame.highlightBorder.bottom:SetHeight(borderSize)
			frame.highlightBorder.left:SetWidth(borderSize)
			frame.highlightBorder.right:SetWidth(borderSize)
			frame.highlightBorder._cachedSize = borderSize
		end
		frame.highlightBorder:SetColor(color[1], color[2], color[3], color[4] or 1)
		frame._highlightBorderActive = true
		UpdateAllBorderVisibility(frame)
	elseif hlDB.focus ~= false and UnitIsUnit(unit, "focus") then
		local color = hlDB.focusColor or { 0.3, 0.6, 1, 1 }
		if frame.highlightBorder._cachedSize ~= borderSize then
			frame.highlightBorder.top:SetHeight(borderSize)
			frame.highlightBorder.bottom:SetHeight(borderSize)
			frame.highlightBorder.left:SetWidth(borderSize)
			frame.highlightBorder.right:SetWidth(borderSize)
			frame.highlightBorder._cachedSize = borderSize
		end
		frame.highlightBorder:SetColor(color[1], color[2], color[3], color[4] or 1)
		frame._highlightBorderActive = true
		UpdateAllBorderVisibility(frame)
	else
		frame._highlightBorderActive = false
		UpdateAllBorderVisibility(frame)
	end
end

-----------------------------------------------
-- FullFrameRefresh — 전체 갱신 (유닛 변경, 초기화)
-----------------------------------------------

function GF:FullFrameRefresh(frame)
	if not frame or not frame.unit then return end

	-- 색상 캐시 초기화
	frame.gfCurrentBgKey = nil

	-- 코어 업데이트
	self:UpdateHealthFast(frame)
	self:UpdatePower(frame)
	self:UpdateName(frame)
	self:UpdateCustomTexts(frame)

	-- 힐 예측 + 보호막 -- [12.0.1]
	self:UpdateHealPrediction(frame)

	-- 상태 아이콘
	self:UpdateRoleIcon(frame)
	self:UpdateLeaderIcon(frame)
	self:UpdateRaidTargetIcon(frame)
	self:UpdateStatusIcons(frame)

	-- 위협 보더 -- [12.0.1]
	if self.UpdateThreat then
		self:UpdateThreat(frame)
	end

	-- 타겟/포커스 하이라이트 -- [12.0.1]
	if self.UpdateHighlight then
		self:UpdateHighlight(frame)
	end

	-- 아우라 (BlizzardAuraCache 기반) -- [REFACTOR] QueueAuraUpdate로 배치 처리
	if self.QueueAuraUpdate then
		self:QueueAuraUpdate(frame)
	end

	-- [FIX] 디버프 하이라이트
	if self.UpdateDebuffHighlight then
		self:UpdateDebuffHighlight(frame)
	end

	-- 생존기 아이콘: ProcessDirtyAuras Phase B에서 캐시 구축 후 자동 호출
	-- (여기서 직접 호출하면 캐시 구축 전이라 전투 중 표시 안 됨)

	-- 거리 체크
	if self.UpdateRange then
		self:UpdateRange(frame)
	end
end
