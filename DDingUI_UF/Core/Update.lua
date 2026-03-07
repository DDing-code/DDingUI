--[[
	ddingUI UnitFrames
	Core/Update.lua - Real-time frame update system

	Config.lua 데이터 구조 기준:
	- 체력: 유닛 레벨 flat (healthBarColorType, healthBarColor, etc.)
	- 크기: size = { width, height }
	- 위젯: widgets.powerBar, widgets.castBar, widgets.classBar, etc.
	- 위젯 크기: widgets.xxx.size = { width = n, height = n }
]]

local _, ns = ...

local Update = {}
ns.Update = Update

local C = ns.Constants
local F = ns.Functions

-----------------------------------------------
-- API Upvalue Caching
-----------------------------------------------

local pairs = pairs
local select = select
local type = type
local math_max = math.max
local math_floor = math.floor
local math_random = math.random
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local unpack = unpack
local wipe = wipe
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitHealthPercent = UnitHealthPercent -- WoW 12.x
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsAFK = UnitIsAFK
local format = string.format
local issecretvalue = issecretvalue -- WoW 12.x secret value API
local SafeVal = ns.SafeVal   -- [REFACTOR] 통합 유틸리티

-----------------------------------------------
-- [STANDALONE] oUF ForceUpdate 호환 래퍼
-- oUF 프레임: element:ForceUpdate() 호출
-- Standalone 프레임: ElementDrivers 호출
-----------------------------------------------

local function SafeForceUpdate(element, fallbackFunc)
	if element and type(element.ForceUpdate) == "function" then
		element:ForceUpdate()
	elseif fallbackFunc then
		fallbackFunc()
	end
end

-- 프레임 단위 갱신: Health/Power/Castbar 등 전체
local function StandaloneRefresh(frame, elementName)
	local D = ns.ElementDrivers
	if not D or not frame then return end
	if elementName == "Health" then
		D:UpdateHealth(frame)
	elseif elementName == "Power" then
		D:UpdatePower(frame)
	elseif elementName == "Castbar" then
		-- castbar는 이벤트 드리븐이므로 여기서 특별히 갱신할 것 없음
	elseif elementName == "HealthPrediction" then
		D:UpdateHealthPrediction(frame)
	elseif elementName == "ClassPower" then
		D:UpdateClassPower(frame)
	elseif elementName == "Buffs" or elementName == "Debuffs" then
		D:UpdateAuras(frame)
	elseif elementName == "Highlight" then
		D:UpdateHighlight(frame)
	elseif elementName == "DispelHighlight" then
		D:UpdateDispelHighlight(frame)
	elseif elementName == "RaidTargetIndicator" then
		D:UpdateRaidTargetIndicator(frame)
	elseif elementName == "ThreatIndicator" then
		D:UpdateThreatIndicator(frame)
	else
		-- 전체 갱신 폴백
		D:UpdateAll(frame)
	end
	-- 태그도 갱신
	if ns.TagEngine then
		ns.TagEngine:UpdateAll(frame)
	end
end

-- oUF UpdateAllElements 호환 래퍼
local function SafeUpdateAllElements(frame, reason)
	if not frame then return end
	if frame.UpdateAllElements then
		frame:UpdateAllElements(reason or "RefreshFrame")
	else
		StandaloneRefresh(frame, nil)
	end
end

-----------------------------------------------
-- [SECRET-V4] GetHealthSafe: StatusBar용
-- cur은 secret → StatusBar:SetValue()가 수용
-- max는 항상 clean
-----------------------------------------------

local AbbreviateNumbers = function(v) return ns.Abbreviate(v) end
local FormatPercentage = FormatPercentage        -- [SECRET-V4]
local UnitHealthPercent = UnitHealthPercent       -- 0-1 범위 (secret)
local UnitHealthMissing = UnitHealthMissing
local pcall = pcall
local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100 -- [SECRET-V4]

-- [PERF] pcall 제거: string.format은 C함수라 secret number도 직접 포맷 가능
local function FormatPct100(secretPct100)
	if not secretPct100 then return nil end
	return string.format("%.0f", secretPct100) .. "%"
end

-- [PERF] pcall 제거: issecretvalue 분기 → 직접 호출
local function SafeFormatHealthPercent(unit)
	if not UnitHealthPercent then return nil end
	-- ScaleTo100 경로 우선 (0-100 범위, FormatPct100이 secret 처리)
	if ScaleTo100 then
		local result = FormatPct100(UnitHealthPercent(unit, true, ScaleTo100))
		if result then return result end
	end
	-- FormatPercentage 경로: clean value만 직접 호출
	local val = UnitHealthPercent(unit)
	if not val then return nil end
	if issecretvalue and issecretvalue(val) then return nil end
	if FormatPercentage then return FormatPercentage(val, true) end
	return tostring(val)
end

local function GetHealthSafe(unit) -- [SECRET-V4] closure 제거
	local max = UnitHealthMax(unit)
	if not max or max == 0 then return 0, 0, 0 end
	local cur = UnitHealth(unit)     -- secret일 수 있음
	if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then
		return cur, max, nil
	end
	local pct = math_floor(cur / max * 100 + 0.5)
	return cur, max, pct
	-- StatusBar:SetValue(cur) 가 secret 수용하므로 cur 그대로 반환
end

-----------------------------------------------
-- [SECRET-V4] FormatHealthText: 직접 SetText용 체력 포맷 함수
-- AbbreviateNumbers + SafeFormatHealthPercent 사용
-- 산술/비교 일절 금지
-----------------------------------------------

-- unit: WoW unitID ("player", "target", "party1", etc.)
-- fmt: DB format key ("percentage", "current", "current-max", etc.)
-- sep: 구분자 (기본 "/")
-- Returns: formatted string
function Update:FormatHealthText(unit, fmt, sep) -- [SECRET-V4]
	if not unit or not UnitExists(unit) then return "" end

	-- 상태 체크 (Dead/Offline/AFK)
	if not UnitIsConnected(unit) then return "|cff999999Offline|r" end
	if UnitIsDeadOrGhost(unit) then return "|cffcc3333Dead|r" end

	local max = UnitHealthMax(unit)
	if not max or max == 0 then return "" end
	if not fmt then fmt = "percentage" end
	if not sep then sep = "/" end

	-- [SECRET-V4] AbbreviateNumbers: C-API, secret 수용
	local curStr = AbbreviateNumbers(UnitHealth(unit))
	local maxStr = AbbreviateNumbers(max) -- max는 항상 clean
	local pctStr = SafeFormatHealthPercent(unit)

	if fmt == "percentage" then
		return pctStr or curStr

	elseif fmt == "current" then
		return curStr

	elseif fmt == "current-max" then
		return curStr .. sep .. maxStr

	elseif fmt == "deficit" then
		if not UnitHealthMissing then return "" end
		local missing = UnitHealthMissing(unit)
		if not missing then return "" end
		-- [PERF] pcall 제거: AbbreviateNumbers(C-API)가 secret 직접 처리
		if issecretvalue and issecretvalue(missing) then
			local str = AbbreviateNumbers(missing)
			if not str or str == "0" then return "" end
			return "-" .. str
		end
		if missing <= 0 then return "" end
		return "-" .. AbbreviateNumbers(missing)

	elseif fmt == "current-percentage" then
		return curStr .. " (" .. (pctStr or "?") .. ")"

	elseif fmt == "percent-current" then
		return (pctStr or curStr) .. sep .. curStr

	elseif fmt == "current-percent" then
		return curStr .. sep .. (pctStr or "?")

	elseif fmt == "smart" then
		return curStr .. sep .. (pctStr or "?")

	elseif fmt == "raid" then
		return pctStr or curStr

	elseif fmt == "healer" then
		if UnitGroupRolesAssigned("player") ~= "HEALER" then return "" end
		if not UnitHealthMissing then return "" end
		local missing = UnitHealthMissing(unit)
		if not missing then return "" end
		-- [PERF] pcall 제거: AbbreviateNumbers(C-API)가 secret 직접 처리
		if issecretvalue and issecretvalue(missing) then
			local str = AbbreviateNumbers(missing)
			if not str or str == "0" then return "" end
			return str
		end
		if missing <= 0 then return "" end
		return AbbreviateNumbers(missing)

	elseif fmt == "percent-full" then
		return pctStr or curStr

	else
		return pctStr or curStr
	end
end

-- ns에도 등록하여 Layout.lua PostUpdate에서 접근 가능
ns.FormatHealthText = function(unit, fmt, sep)
	return Update:FormatHealthText(unit, fmt, sep)
end

-----------------------------------------------
-- Combat Safety Queue (oUF_LS dirtyObjects 패턴)
-----------------------------------------------

local combatQueue = {}     -- { [key] = {func, arg1, arg2, ...}, ... } -- [REFACTOR] key-based (중복 방지)
local isCombatQueued = false
local combatQueueOrder = {} -- 실행 순서 유지

local function ProcessCombatQueue()
	if InCombatLockdown() then return end
	for i = 1, #combatQueueOrder do
		local key = combatQueueOrder[i]
		local entry = combatQueue[key]
		if entry and entry[1] then
			local ok, err = pcall(entry[1], select(2, unpack(entry)))
			if not ok then
				ns.Debug("CombatQueue error:", err)
			end
		end
	end
	wipe(combatQueue)
	wipe(combatQueueOrder)
	isCombatQueued = false
end

local function QueueForCombat(keyOrFunc, funcOrArg1, ...)
	local key, func, args
	if type(keyOrFunc) == "string" then
		-- QueueForCombat("key", func, ...) — key-based (중복 시 덮어쓰기)
		key = keyOrFunc
		func = funcOrArg1
		args = {func, ...}
	else
		-- QueueForCombat(func, ...) — legacy 호환 (자동 key 생성)
		func = keyOrFunc
		key = tostring(func) .. "#" .. (#combatQueueOrder + 1)
		args = {func, funcOrArg1, ...}
	end
	if not combatQueue[key] then
		combatQueueOrder[#combatQueueOrder + 1] = key
	end
	combatQueue[key] = args
	if not isCombatQueued then
		isCombatQueued = true
		ns.RegisterEvent("PLAYER_REGEN_ENABLED", ProcessCombatQueue)
	end
end

-- Safe wrapper: executes immediately if not in combat, queues otherwise
local function CombatSafeCall(func, ...)
	if InCombatLockdown() then
		QueueForCombat(func, ...)
		return false  -- queued
	else
		func(...)
		return true   -- executed
	end
end

ns.CombatSafeCall = CombatSafeCall
ns.QueueForCombat = QueueForCombat

-----------------------------------------------
-- Helper Functions
-----------------------------------------------

-- [FIX] LSM 표시이름("기본 글꼴","Melli") → 파일 경로 변환
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local function ResolveLSM(mediaType, val, fallback)
	if not val then return fallback end
	if val:find("[/\\]") then return val end
	if LSM then
		local resolved = LSM:Fetch(mediaType, val)
		if resolved then return resolved end
	end
	return fallback
end

local function GetTexture()
	local raw = ns.db and ns.db.media and ns.db.media.texture or C.FLAT_TEXTURE
	return ResolveLSM("statusbar", raw, C.FLAT_TEXTURE)
end

local function GetFont()
	local db = ns.db and ns.db.media or {}
	local fontPath = ResolveLSM("font", db.font, C.DEFAULT_FONT)
	return fontPath,
		   db.fontSize or C.DEFAULT_FONT_SIZE,
		   db.fontFlags or C.DEFAULT_FONT_FLAGS
end

-- SetFont 안전 래퍼: 실패 시 WoW 기본 폰트 폴백 -- [12.0.1]
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local function SafeSetFont(fontString, font, size, flags)
	if not fontString then return false end
	size = size or 11
	flags = flags or "OUTLINE"
	local success = fontString:SetFont(font or FALLBACK_FONT, size, flags)
	if not success then
		fontString:SetFont(FALLBACK_FONT, size, flags)
	end
	return true
end

-- 위젯 설정 안전 접근
local function GetWidgetDB(unitDB, widgetName)
	return unitDB and unitDB.widgets and unitDB.widgets[widgetName]
end

-- oUF 태그 기반 텍스트 즉시 갱신
local function ForceRefreshText(frame)
	if not frame then return end
	if frame.UpdateTags then
		frame:UpdateTags()
	elseif ns.TagEngine then
		ns.TagEngine:UpdateAll(frame)
	end
end

-- frame/unitKey 양쪽 호출 규약 지원
local function ResolveFrameUnit(self, frameOrUnit, unitKey)
	if type(frameOrUnit) == "string" then
		local unit = frameOrUnit
		local frame = ns.frames[unit]
		if not frame then
			-- [12.0.1] 그룹 유닛은 전용 배치 리프레시로 라우팅
			if unit == "party" then self:RefreshPartyFrames() return nil, nil end
			if unit == "raid" then self:RefreshRaidFrames() return nil, nil end
			if unit == "boss" then self:RefreshBossFrames() return nil, nil end
			if unit == "arena" then self:RefreshArenaFrames() return nil, nil end
			return nil, nil
		end
		return frame, unit
	else
		return frameOrUnit, unitKey
	end
end

-----------------------------------------------
-- Update Enabled State
-----------------------------------------------

function Update:UpdateEnabled(unitKey)
	if InCombatLockdown() then
		QueueForCombat("UpdateEnabled:" .. unitKey, Update.UpdateEnabled, Update, unitKey) -- [REFACTOR] key-based
		ns.Debug("UpdateEnabled queued for after combat:", unitKey)
		return
	end

	local frame = ns.frames[unitKey]
	if not frame then return end

	local baseUnit = unitKey:gsub("%d+", "")
	local db = ns.db[unitKey] or ns.db[baseUnit]
	if not db then return end

	if db.enabled == false then
		UnregisterUnitWatch(frame)
		frame:Hide()
	else
		RegisterUnitWatch(frame)
		if frame.unit and UnitExists(frame.unit) then
			frame:Show()
		end
	end
end

function Update:UpdateEnabledGroup(unitKey)
	if InCombatLockdown() then
		QueueForCombat("UpdateEnabledGroup:" .. unitKey, Update.UpdateEnabledGroup, Update, unitKey) -- [REFACTOR] key-based
		ns.Debug("UpdateEnabledGroup queued for after combat:", unitKey)
		return
	end

	if unitKey == "party" then
		local header = ns.headers and ns.headers.party
		if header then
			if ns.db.party and ns.db.party.enabled == false then
				header:Hide()
			else
				header:Show()
			end
		end
	elseif unitKey == "raid" then
		for i = 1, 8 do
			local header = ns.headers and ns.headers["raid_group" .. i]
			if header then
				if ns.db.raid and ns.db.raid.enabled == false then
					header:Hide()
				else
					header:Show()
				end
			end
		end
	end
end

-----------------------------------------------
-- Update Frame Size
-- Config: db.size = { width, height }
-- Config: db.widgets.powerBar.size.height
-----------------------------------------------

-- [FIX] 테두리/배경 런타임 갱신 (Options에서 변경 시 반영)
function Update:UpdateBorder(frame, unitKey)
	if not frame or not frame.Backdrop then return end
	local db = ns.db[unitKey]
	if not db then return end

	local borderDB = db.border or {}
	local bgDB = db.background or {}

	-- 테두리 활성화/비활성화
	if borderDB.enabled == false then
		frame.Backdrop:Hide()
		return
	else
		frame.Backdrop:Show()
	end

	-- 테두리 두께: 슬라이더 값(0.1~3)이 곧 물리픽셀
	local rawSize = borderDB.size or C.BORDER_SIZE
	local borderSize = F:ScalePixel(rawSize)
	frame.Backdrop:ClearAllPoints()
	frame.Backdrop:SetPoint("TOPLEFT", -borderSize, borderSize)
	frame.Backdrop:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)

	-- 배경 업데이트 (수동 텍스처 방식)
	local bgColor = bgDB.color or C.FRAME_BG
	if type(bgColor) ~= "table" then bgColor = C.FRAME_BG end

	if frame.Backdrop.bg then
		-- 수동 텍스처 방식: bg + borderTextures
		frame.Backdrop.bg:ClearAllPoints()
		frame.Backdrop.bg:SetPoint("TOPLEFT", borderSize, -borderSize)
		frame.Backdrop.bg:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
		frame.Backdrop.bg:SetColorTexture(unpack(bgColor))

		-- 테두리 색상
		local borderColor = borderDB.color or C.BORDER_COLOR
		if type(borderColor) ~= "table" then borderColor = C.BORDER_COLOR end
		local r, g, b, a = unpack(borderColor)

		if frame.Backdrop.borderTextures then
			local top, bottom, left, right = unpack(frame.Backdrop.borderTextures)
			top:SetHeight(borderSize)
			top:SetColorTexture(r, g, b, a)
			bottom:SetHeight(borderSize)
			bottom:SetColorTexture(r, g, b, a)
			left:SetWidth(borderSize)
			left:SetColorTexture(r, g, b, a)
			right:SetWidth(borderSize)
			right:SetColorTexture(r, g, b, a)
		end
	else
		-- 레거시 BackdropTemplate 방식 (fallback)
		frame.Backdrop:SetBackdrop({
			bgFile = C.FLAT_TEXTURE,
			edgeFile = C.FLAT_TEXTURE,
			edgeSize = borderSize,
			insets = { left = borderSize, right = borderSize, top = borderSize, bottom = borderSize },
		})
		frame.Backdrop:SetBackdropColor(unpack(bgColor))
		local borderColor = borderDB.color or C.BORDER_COLOR
		if type(borderColor) == "table" then
			frame.Backdrop:SetBackdropBorderColor(unpack(borderColor))
		else
			frame.Backdrop:SetBackdropBorderColor(unpack(C.BORDER_COLOR))
		end
	end
end

function Update:UpdateFrameSize(frame, unitKey)
	if not frame then ns.Debug("UpdateFrameSize: frame nil for", unitKey) return end
	local db = ns.db[unitKey]
	if not db then ns.Debug("UpdateFrameSize: db nil for", unitKey) return end

	local width = (db.size and db.size[1]) or 200
	local height = (db.size and db.size[2]) or 40

	ns.Debug("UpdateFrameSize:", unitKey, width .. "x" .. height)
	-- [12.0.1] 전투 중 보호 프레임(pet 등) SetSize taint 방지
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
		ns.Debug("UpdateFrameSize: skipped (combat lockdown) for", unitKey)
		return
	end
	frame:SetSize(width, height)

	-- 기력바 높이 계산
	local powerDB = GetWidgetDB(db, "powerBar")
	local powerH = 0
	if powerDB and powerDB.enabled ~= false and frame.Power then
		powerH = (powerDB.size and powerDB.size.height) or C.POWER_HEIGHT
	end

	-- 체력바 크기 조정
	if frame.Health then
		frame.Health:ClearAllPoints()
		frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		frame.Health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, powerH > 0 and powerH or 0)
	end

	-- 기력바 높이/위치 조정
	if frame.Power and powerDB then
		local pH = (powerDB.size and powerDB.size.height) or C.POWER_HEIGHT
		frame.Power:SetHeight(pH)
	end

	-- 힐 예측 바 너비 -- [REFACTOR] Layout.lua 실제 키와 일치시킴
	if frame.HealthPrediction then
		if frame.HealthPrediction.healingAll then
			frame.HealthPrediction.healingAll:SetWidth(width)
		end
		if frame.HealthPrediction.damageAbsorb then
			frame.HealthPrediction.damageAbsorb:SetWidth(width)
		end
		if frame.HealthPrediction.healAbsorb then
			frame.HealthPrediction.healAbsorb:SetWidth(width)
		end
	end
end

-----------------------------------------------
-- Update Health
-- Config: flat at unit level (healthBarColorType, healthBarColor, etc.)
-----------------------------------------------

function Update:UpdateHealth(frameOrUnit, unitKey)
	local frame, unit = ResolveFrameUnit(self, frameOrUnit, unitKey)
	if not frame or not frame.Health then
		ns.Debug("UpdateHealth: frame/health nil for", tostring(frameOrUnit), tostring(unitKey))
		return
	end

	local db = ns.db[unit]
	if not db then ns.Debug("UpdateHealth: db nil for", unit) return end
	ns.Debug("UpdateHealth:", unit, "colorType=" .. (db.healthBarColorType or "class"))

	local health = frame.Health
	local colorType = db.healthBarColorType or "class"

	-- oUF 색상 플래그 런타임 전환 -- [12.0.1]
	if colorType == "custom" then
		health.colorClass = false
		health.colorReaction = false
		health.colorSmooth = false
		if db.healthBarColor then
			health:SetStatusBarColor(unpack(db.healthBarColor))
		end
	elseif colorType == "smooth" then
		health.colorSmooth = true
		health.colorClass = false
		health.colorReaction = false
		health.colorHealth = true
	else
		health.colorClass = (colorType == "class")
		health.colorReaction = (colorType == "reaction" or colorType == "class")
		health.colorHealth = true
		health.colorSmooth = false
	end

	-- [REFACTOR] smoothBars 런타임 토글
	if ns.db.smoothBars ~= false then
		health.smoothing = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Linear or nil
	else
		health.smoothing = nil
	end

	-- 역방향 채움
	if db.reverseHealthFill then
		health:SetReverseFill(true)
	else
		health:SetReverseFill(false)
	end

	-- 배경(손실 체력) 색상 -- [FIX-OPTION] healthLossColor 우선 적용
	if health.bg then
		local lossType = db.healthLossColorType or "custom"
		if lossType == "custom" and db.healthLossColor then
			local lc = db.healthLossColor
			health.bg:SetVertexColor(lc[1] or 0.5, lc[2] or 0.1, lc[3] or 0.1, lc[4] or 1)
			health.bg._customColor = true -- [FIX] PostUpdateColor에서 덮어쓰기 방지
		elseif lossType == "class_dark" then
			-- class_dark: PostUpdateColor에서 bg.multiplier 기반으로 자동 처리
			health.bg.multiplier = C.HEALTH_BG_MULTIPLIER or 0.3
			health.bg._customColor = false
		elseif db.background and db.background.color then
			local bgColor = db.background.color
			health.bg:SetVertexColor(bgColor[1] or 0.1, bgColor[2] or 0.1, bgColor[3] or 0.1, bgColor[4] or 0.8)
			health.bg._customColor = true -- [FIX] PostUpdateColor에서 덮어쓰기 방지
		else
			health.bg._customColor = false
		end
	end

	-- 텍스처 변경 -- [FIX] healthBarTexture가 있으면 바로 적용 (useHealthBarTexture 불필요)
	local hTex = db.healthBarTexture or GetTexture()
	hTex = ResolveLSM("statusbar", hTex, GetTexture())
	health:SetStatusBarTexture(hTex)

	-- 배경 텍스처: 별도 설정 우선, 없으면 바 텍스처 따라감
	if health.bg then
		local bgTex = db.healthBgTexture or hTex
		bgTex = ResolveLSM("statusbar", bgTex, hTex)
		health.bg:SetTexture(bgTex)
	end

	-- 강제 업데이트
	if frame.unit and UnitExists(frame.unit) then
		SafeForceUpdate(health, function() StandaloneRefresh(frame, "Health") end)
	end
end

-----------------------------------------------
-- Update Power
-- Config: db.widgets.powerBar
-----------------------------------------------

function Update:UpdatePower(frameOrUnit, unitKey)
	local frame, unit = ResolveFrameUnit(self, frameOrUnit, unitKey)
	if not frame then ns.Debug("UpdatePower: frame nil for", tostring(frameOrUnit)) return end
	ns.Debug("UpdatePower:", unit)

	local db = ns.db[unit]
	if not db then return end

	local pDB = GetWidgetDB(db, "powerBar")
	if not pDB then return end

	if pDB.enabled == false then
		if frame.Power then
			self:SetElementEnabled(frame, "Power", false)
			frame.Power:Hide()
			-- 체력바 확장
			if frame.Health then
				frame.Health:ClearAllPoints()
				frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
				frame.Health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
			end
		end
	else
		if frame.Power then
			self:SetElementEnabled(frame, "Power", true)
			frame.Power:Show()
			local powerH = (pDB.size and pDB.size.height) or C.POWER_HEIGHT

			-- [FIX] 자원바 위치 재설정 (분리/부착 모드) -- [REFACTOR]
			frame.Power:ClearAllPoints()
			if pDB.anchorToParent == false and pDB.detachedPosition then
				local pos = pDB.detachedPosition
				local w = (pDB.size and pDB.size.width) or frame:GetWidth()
				frame.Power:SetParent(UIParent)
				frame.Power:SetSize(w, powerH)
				frame.Power:SetPoint(
					pos.point or "BOTTOM",
					frame,  -- [FIX] 앵커는 주인 프레임 (UIParent가 아닌 유닛프레임 기준 배치)
					pos.relativePoint or "BOTTOM",
					pos.offsetX or 0,
					pos.offsetY or 0
				)
				if not frame.Power.backdrop then F:CreateBackdrop(frame.Power) end
			else
				frame.Power:SetParent(frame)
				frame.Power:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
				frame.Power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
				frame.Power:SetHeight(powerH)
			end

			-- 체력바 조정
			if frame.Health then
				frame.Health:ClearAllPoints()
				frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
				local bottomInset = (pDB.anchorToParent ~= false) and powerH or 0
				frame.Health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, bottomInset)
			end

			-- [REFACTOR] smoothBars 런타임 토글 (Power)
			if ns.db.smoothBars ~= false then
				frame.Power.smoothing = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Linear or nil
			else
				frame.Power.smoothing = nil
			end

			-- 색상 설정
			frame.Power.colorPower = pDB.colorPower ~= false
			frame.Power.colorClass = pDB.colorClass == true
			-- [FIX] colorPower/colorClass 둘 다 아닐 때 customColor 적용
			if not frame.Power.colorPower and not frame.Power.colorClass and pDB.customColor then
				frame.Power:SetStatusBarColor(unpack(pDB.customColor))
			end

			-- [FIX] 텍스처 적용: per-widget > per-unit > global
			local pTex = pDB.texture or db.powerBarTexture or GetTexture()
			pTex = ResolveLSM("statusbar", pTex, GetTexture())
			frame.Power:SetStatusBarTexture(pTex)

			-- 배경 텍스처/색상 -- [FIX] 배경 설정 추가
			if frame.Power.bg then
				local bgTex = (pDB.background and pDB.background.texture) or pTex
				bgTex = ResolveLSM("statusbar", bgTex, pTex)
				frame.Power.bg:SetTexture(bgTex)
				if pDB.background and pDB.background.color then
					local bgC = pDB.background.color
					frame.Power.bg:SetVertexColor(bgC[1] or 0, bgC[2] or 0, bgC[3] or 0, bgC[4] or 0.7)
					frame.Power.bg.multiplier = nil -- 커스텀 색상이면 multiplier 무시
				end
			end

			-- 강제 업데이트
			if frame.unit and UnitExists(frame.unit) then
				SafeForceUpdate(frame.Power, function() StandaloneRefresh(frame, "Power") end)
			else
				-- [FIX] 유닛 없음 (대상 없음 등) → 파워바+백드롭 숨기기 (흰 바 방지)
				frame.Power:Hide()
				if frame.Power.backdrop then frame.Power.backdrop:Hide() end
			end
		end
	end
end

-----------------------------------------------
-- Update Alt Power Bar (보조 자원바)
-- Config: db.widgets.altPowerBar
-----------------------------------------------

function Update:UpdateAltPower(frame, unitKey)
	if not frame then return end
	-- [FIX] Layout에서 enabled=false시 _altPowerBar에만 저장됨
	local altPower = frame.AlternativePower or frame._altPowerBar or frame._altPowerFrame
	local addPower = frame.AdditionalPower or frame._additionalPowerFrame
	if not altPower and not addPower then return end

	local db = ns.db[unitKey]
	if not db then return end

	local apDB = GetWidgetDB(db, "altPowerBar")
	if not apDB then return end

	if apDB.enabled == false then
		if frame.AlternativePower then
			self:SetElementEnabled(frame, "AlternativePower", false)
		end
		if altPower then altPower:Hide() end
		
		if frame.AdditionalPower then
			self:SetElementEnabled(frame, "AdditionalPower", false)
		end
		if addPower then addPower:Hide() end
	else
		-- [FIX] _altPowerBar → AlternativePower로 승격 (oUF 엘리먼트 등록)
		if not frame.AlternativePower and (frame._altPowerBar or frame._altPowerFrame) then
			frame.AlternativePower = frame._altPowerBar or frame._altPowerFrame
			frame._altPowerBar = nil
			frame._altPowerFrame = nil
		end
		if altPower then
			self:SetElementEnabled(frame, "AlternativePower", true)
			altPower:Show()
			local apH = (apDB.size and apDB.size.height) or 4
			local apW = (apDB.size and apDB.size.width) or frame:GetWidth()
			altPower:SetSize(apW, apH)
			-- 위치 업데이트
			altPower:ClearAllPoints()
			local pos = apDB.position
			altPower:SetPoint(
				pos and pos.point or "TOP",
				frame,
				pos and pos.relativePoint or "TOP",
				pos and pos.offsetX or 0,
				pos and pos.offsetY or 0
			)
			-- [FIX] 텍스처/배경 적용
			local apTex = apDB.texture or GetTexture()
			apTex = ResolveLSM("statusbar", apTex, GetTexture())
			altPower:SetStatusBarTexture(apTex)
			if altPower.bg then
				local bgTex = (apDB.background and apDB.background.texture) or apTex
				bgTex = ResolveLSM("statusbar", bgTex, apTex)
				altPower.bg:SetTexture(bgTex)
				if apDB.background and apDB.background.color then
					local bgC = apDB.background.color
					altPower.bg:SetVertexColor(bgC[1] or 0.08, bgC[2] or 0.08, bgC[3] or 0.08, bgC[4] or 0.85)
				end
			end
			if frame.unit and UnitExists(frame.unit) and type(altPower.ForceUpdate) == "function" then
				altPower:ForceUpdate()
			end
		end

		if not frame.AdditionalPower and frame._additionalPowerFrame then
			frame.AdditionalPower = frame._additionalPowerFrame
			frame._additionalPowerFrame = nil
		end
		if addPower then
			self:SetElementEnabled(frame, "AdditionalPower", true)
			addPower:Show()
			local apTex = apDB.texture or GetTexture()
			apTex = ResolveLSM("statusbar", apTex, GetTexture())
			addPower:SetStatusBarTexture(apTex)
			if addPower.bg then
				local bgTex = (apDB.background and apDB.background.texture) or apTex
				bgTex = ResolveLSM("statusbar", bgTex, apTex)
				addPower.bg:SetTexture(bgTex)
				if apDB.background and apDB.background.color then
					local bgC = apDB.background.color
					addPower.bg:SetVertexColor(bgC[1] or 0.08, bgC[2] or 0.08, bgC[3] or 0.08, bgC[4] or 0.85)
				end
			end
			if frame.unit and UnitExists(frame.unit) and type(addPower.ForceUpdate) == "function" then
				addPower:ForceUpdate()
			end
		end
	end
end

-----------------------------------------------
-- Update Castbar
-- Config: db.widgets.castBar
-----------------------------------------------

function Update:UpdateCastbar(frame, unitKey)
	if not frame then return end
	local db = ns.db[unitKey]
	if not db then return end

	local cbDB = GetWidgetDB(db, "castBar")
	if not cbDB then return end

	local castbar = frame.Castbar
	if not castbar then return end

	if cbDB.enabled == false then
		self:SetElementEnabled(frame, "Castbar", false)
		castbar:Hide()
	else
		self:SetElementEnabled(frame, "Castbar", true)
		castbar:Show()

		-- 크기 업데이트
		local cbWidth = cbDB.size and cbDB.size.width
		local cbHeight = cbDB.size and cbDB.size.height

		if cbWidth then
			-- [FIX] inside 아이콘 모드: 바 너비에서 아이콘 영역 제외
			local iPos = castbar._iconPos
			if iPos == "inside-left" or iPos == "inside-right" then
				local iconW = cbHeight or castbar:GetHeight()
				castbar:SetWidth(cbWidth - iconW)
			else
				castbar:SetWidth(cbWidth)
			end
		end
		if cbHeight then
			castbar:SetHeight(cbHeight)
		end

		-- [FIX-OPTION] 아이콘 설정
		if castbar.Icon then
			local iconDB = cbDB.icon
			if iconDB and iconDB.enabled == false then
				castbar.Icon:Hide()
			else
				castbar.Icon:Show()
				local iconH = cbHeight or castbar:GetHeight()
				castbar.Icon:SetSize(iconH, iconH)
				-- [REFACTOR] icon.position: inside 모드는 바 바깥에 배치
				if iconDB and iconDB.position then
					castbar.Icon:ClearAllPoints()
					local iPos = iconDB.position
					if iPos == "right" then
						castbar.Icon:SetPoint("LEFT", castbar, "RIGHT", 3, 0)
					elseif iPos == "inside-right" then
						castbar.Icon:SetPoint("LEFT", castbar, "RIGHT", 0, 0)
					elseif iPos == "inside-left" then
						castbar.Icon:SetPoint("RIGHT", castbar, "LEFT", 0, 0)
					elseif iPos == "none" then
						castbar.Icon:Hide()
					else -- "left" (외부 좌측)
						castbar.Icon:SetPoint("RIGHT", castbar, "LEFT", -3, 0)
					end
					castbar._iconPos = iPos
					-- Text/Time: 아이콘이 바 바깥이므로 항상 바 기준
					if castbar.Text then
						castbar.Text:ClearAllPoints()
						castbar.Text:SetPoint("LEFT", castbar, 4, 0)
						castbar.Text:SetPoint("RIGHT", castbar, -40, 0)
					end
					if castbar.Time then
						castbar.Time:ClearAllPoints()
						castbar.Time:SetPoint("RIGHT", castbar, -4, 0)
					end
				end
			end
		end

		-- [FIX-OPTION] 스파크 설정
		if castbar.Spark then
			local sparkDB = cbDB.spark
			if sparkDB and sparkDB.enabled == false then
				castbar.Spark:Hide()
			else
				castbar.Spark:Show()
				local sparkH = cbHeight or castbar:GetHeight()
				castbar.Spark:SetHeight(sparkH)
				if sparkDB and sparkDB.width then
					castbar.Spark:SetWidth(sparkDB.width)
				end
				-- [FIX] 미적용 옵션 연결: spark.color
				if sparkDB and sparkDB.color then
					castbar.Spark:SetVertexColor(unpack(sparkDB.color))
				end
			end
		end

		-- [FIX-OPTION] 캐스트바 텍스처 -- [FIX] 바 텍스처 + 배경 텍스처 분리
		if cbDB.texture then
			local cbTex = ResolveLSM("statusbar", cbDB.texture, GetTexture())
			castbar:SetStatusBarTexture(cbTex)
		end
		-- 배경 텍스처: 별도 설정 우선, 없으면 바 텍스처 따라감
		if castbar.bg then
			local cbBgTex = (cbDB.colors and cbDB.colors.backgroundTexture) or cbDB.texture or GetTexture()
			cbBgTex = ResolveLSM("statusbar", cbBgTex, GetTexture())
			castbar.bg:SetTexture(cbBgTex)
		end

		-- [FIX-OPTION] 텍스트 폰트 크기
		local font, fontSize, fontFlags = GetFont()
		if castbar.Text then
			local spellDB = cbDB.spell
			local spSize = (spellDB and spellDB.size) or (fontSize - 1)
			local spOutline = (spellDB and spellDB.outline) or fontFlags
			local spFont = (spellDB and spellDB.style) or font
			SafeSetFont(castbar.Text, spFont, spSize, spOutline)
			if cbDB.showSpell == false then
				castbar.Text:Hide()
			else
				castbar.Text:Show()
			end
			-- [FIX] 미적용 옵션 연결: spell position (아이콘은 바 바깥이므로 항상 castbar 기준)
			if spellDB and spellDB.point then
				castbar.Text:ClearAllPoints()
				local spOX = spellDB.offsetX or 3
				local spOY = spellDB.offsetY or 0
				castbar.Text:SetPoint(
					spellDB.point or "LEFT",
					castbar,
					spellDB.relativePoint or "LEFT",
					spOX,
					spOY
				)
			end
			-- [FIX] 미적용 옵션 연결: spell shadow
			if spellDB and spellDB.shadow then
				castbar.Text:SetShadowColor(0, 0, 0, 1)
				castbar.Text:SetShadowOffset(1, -1)
			elseif spellDB then
				castbar.Text:SetShadowOffset(0, 0)
			end
		end
		if castbar.Time then
			local timerDB = cbDB.timer
			if timerDB and timerDB.enabled == false then
				castbar.Time:Hide()
			else
				castbar.Time:Show()
				local tSize = (timerDB and timerDB.size) or (fontSize - 1)
				local tOutline = (timerDB and timerDB.outline) or fontFlags
				local tFont = (timerDB and timerDB.style) or font
				SafeSetFont(castbar.Time, tFont, tSize, tOutline)
				-- [FIX] 미적용 옵션 연결: timer position (아이콘은 바 바깥이므로 항상 castbar 기준)
				if timerDB.point then
					castbar.Time:ClearAllPoints()
					local tOX = timerDB.offsetX or -3
					local tOY = timerDB.offsetY or 0
					castbar.Time:SetPoint(
						timerDB.point or "RIGHT",
						castbar,
						timerDB.relativePoint or "RIGHT",
						tOX,
						tOY
					)
				end
				-- [FIX] 미적용 옵션 연결: timer shadow
				if timerDB.shadow then
					castbar.Time:SetShadowColor(0, 0, 0, 1)
					castbar.Time:SetShadowOffset(1, -1)
				else
					castbar.Time:SetShadowOffset(0, 0)
				end
				-- [REFACTOR] timer format 런타임 업데이트
				if timerDB.format then
					castbar._timerFormat = timerDB.format
				end
			end
		end

		-- [FIX-OPTION] 색상 설정 저장 (oUF Castbar PostCastStart/PostCastInterruptible에서 사용)
		-- [FIX] 글로벌 ns.Colors.castBar 우선, per-unit cbDB.colors fallback
		local colors = cbDB.colors
		if colors then
			castbar._intColor = (ns.Colors and ns.Colors.castBar and ns.Colors.castBar.interruptible) or colors.interruptible
			castbar._nonIntColor = (ns.Colors and ns.Colors.castBar and ns.Colors.castBar.nonInterruptible) or colors.nonInterruptible
			if colors.background and castbar.bg then
				local bgc = colors.background
				castbar.bg:SetVertexColor(bgc[1] or 0, bgc[2] or 0, bgc[3] or 0, bgc[4] or 0.8)
			end
		end
		castbar._useClassColor = cbDB.useClassColor
		castbar._onlyShowInterrupt = cbDB.onlyShowInterrupt
	end
end

function Update:UpdateCastbarPosition(frame, unitKey)
	if not frame or not frame.Castbar then return end
	local db = ns.db[unitKey]
	if not db then return end

	local cbDB = GetWidgetDB(db, "castBar")
	if not cbDB then return end

	local castbar = frame.Castbar
	castbar:ClearAllPoints()

	-- [REFACTOR] inside 아이콘 모드: 바 영역에서 아이콘 크기 제외
	local iPos = castbar._iconPos
	local h = (cbDB.size and cbDB.size.height) or 18
	local iconW = 0
	if iPos == "inside-left" or iPos == "inside-right" then
		iconW = h -- 정사각형 아이콘
	end

	if not cbDB.anchorToParent and cbDB.detachedPosition then
		-- 분리된 시전바: 주인 프레임 기준 독립 위치
		local pos = cbDB.detachedPosition
		local w = (cbDB.size and cbDB.size.width) or frame:GetWidth()
		castbar:SetSize(w - iconW, h)
		local adjOX = pos.offsetX or 0
		if iPos == "inside-left" then adjOX = adjOX + iconW / 2 end
		if iPos == "inside-right" then adjOX = adjOX - iconW / 2 end
		castbar:SetPoint(
			pos.point or "CENTER",
			frame,  -- [FIX] 앵커는 주인 프레임 (UIParent가 아닌 유닛프레임 기준 배치)
			pos.relativePoint or "CENTER",
			adjOX,
			pos.offsetY or 0
		)
	else
		-- 부착된 시전바: 프레임 아래
		local cbGap = F:PixelPerfectThickness(2)
		local leftOff = iPos == "inside-left" and iconW or 0
		local rightOff = iPos == "inside-right" and -iconW or 0
		castbar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", leftOff, -cbGap)
		castbar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", rightOff, -cbGap)
		castbar:SetHeight(h)
	end
end

-----------------------------------------------
-- Update Auras (Buffs/Debuffs)
-- Config: db.widgets.buffs, db.widgets.debuffs
-----------------------------------------------

-- [FIX] 아이콘 정렬: 1차/2차 방향 → oUF 속성 매핑 (Layout.lua ApplyAuraGrowth와 동일)
-- growDir: 1차 방향 (RIGHT/LEFT/DOWN/UP), colGrowDir: 2차 방향 (줄 바꿈 방향)
local function RuntimeApplyAuraGrowth(element, growDir, colGrowDir, maxPerLine, hSpacing, vSpacing, iconSize, num)
	local isVerticalPrimary = (growDir == "DOWN" or growDir == "UP")

	if isVerticalPrimary then
		-- 세로 1차: 커스텀 SetPosition 필요 (oUF는 가로 1차만 네이티브 지원)
		local maxRows = math_max(1, maxPerLine)
		local maxColCount = math_max(1, math.ceil(num / maxRows))
		element:SetSize(iconSize * maxColCount + hSpacing * (maxColCount - 1), iconSize * maxRows + vSpacing * (maxRows - 1))

		-- 앵커 결정: 1차(세로) + 2차(가로) 조합
		local ySign = (growDir == "DOWN") and -1 or 1
		local xSign = (colGrowDir == "LEFT") and -1 or 1
		if growDir == "DOWN" and colGrowDir == "LEFT" then
			element.initialAnchor = "TOPRIGHT"
		elseif growDir == "DOWN" then
			element.initialAnchor = "TOPLEFT"
		elseif growDir == "UP" and colGrowDir == "LEFT" then
			element.initialAnchor = "BOTTOMRIGHT"
		else
			element.initialAnchor = "BOTTOMLEFT"
		end

		element.growthX = (colGrowDir == "LEFT") and "LEFT" or "RIGHT"
		element.growthY = growDir
		element.maxCols = maxColCount

		-- 세로 1차 커스텀 SetPosition 오버라이드
		element.SetPosition = function(el, from, to)
			local w = el.width or el.size or 16
			local h = el.height or el.size or 16
			local sX = w + (el.spacingX or el.spacing or 0)
			local sY = h + (el.spacingY or el.spacing or 0)
			local anchor = el.initialAnchor or "BOTTOMLEFT"
			for i = from, to do
				local button = el[i]
				if not button then break end
				local row = (i - 1) % maxRows        -- 세로 인덱스 (1차)
				local col = math_floor((i - 1) / maxRows) -- 가로 인덱스 (2차)
				button:ClearAllPoints()
				button:SetPoint(anchor, el, anchor, col * sX * xSign, row * sY * ySign)
			end
		end
	else
		-- 가로 1차: oUF 기본 SetPosition 사용
		local maxCols = math_max(1, maxPerLine)
		local maxRowCount = math_max(1, math.ceil(num / maxCols))
		element:SetSize(iconSize * maxCols + hSpacing * (maxCols - 1), iconSize * maxRowCount + vSpacing * (maxRowCount - 1))

		element.growthX = (growDir == "LEFT") and "LEFT" or "RIGHT"
		element.growthY = (colGrowDir == "DOWN") and "DOWN" or "UP"
		element.maxCols = maxCols

		-- 앵커 결정: 1차(가로) + 2차(세로) 조합
		if growDir == "LEFT" and colGrowDir == "DOWN" then
			element.initialAnchor = "TOPRIGHT"
		elseif growDir == "LEFT" then
			element.initialAnchor = "BOTTOMRIGHT"
		elseif colGrowDir == "DOWN" then
			element.initialAnchor = "TOPLEFT"
		else
			element.initialAnchor = "BOTTOMLEFT"
		end

		element.SetPosition = nil -- oUF 기본 사용
	end
end

-- orientation → growDirection/columnGrowDirection 하위호환 변환
local function ResolveAuraGrowth(aDB, defaultGrow, defaultColGrow)
	local growDir = aDB.growDirection or defaultGrow
	local colGrowDir = aDB.columnGrowDirection or defaultColGrow
	-- 하위호환: 기존 orientation 값 변환
	if not aDB.growDirection and aDB.orientation then
		local orient = aDB.orientation
		if orient == "RIGHT_TO_LEFT" then growDir, colGrowDir = "LEFT", "UP"
		elseif orient == "LEFT_TO_RIGHT" then growDir, colGrowDir = "RIGHT", "UP"
		elseif orient == "TOP_TO_BOTTOM" then growDir, colGrowDir = "DOWN", "RIGHT"
		elseif orient == "BOTTOM_TO_TOP" then growDir, colGrowDir = "UP", "RIGHT"
		end
	end
	return growDir, colGrowDir
end

function Update:UpdateAuras(frameOrUnit, unitKey)
	local frame, unit = ResolveFrameUnit(self, frameOrUnit, unitKey)
	if not frame then return end

	local db = ns.db[unit]
	if not db then return end

	-- 버프 업데이트
	local bDB = GetWidgetDB(db, "buffs")
	local buffs = frame.Buffs or frame._buffsFrame
	if buffs and bDB then
		if bDB.enabled == false then
			if frame.Buffs then
				self:SetElementEnabled(frame, "Buffs", false)
			end
			buffs:Hide()
		else
			if not frame.Buffs and frame._buffsFrame then
				frame.Buffs = frame._buffsFrame
				frame._buffsFrame = nil
			end
			self:SetElementEnabled(frame, "Buffs", true)
			frame.Buffs:Show()
			local iconSize = (bDB.size and bDB.size.width) or 24
			local num = bDB.maxIcons or 10
			local hSpacing = (bDB.spacing and bDB.spacing.horizontal) or 2
			local numPerLine = bDB.numPerLine or num
			local vSpacing = (bDB.spacing and bDB.spacing.vertical) or 2

			frame.Buffs.size = iconSize
			frame.Buffs.num = num
			frame.Buffs.spacingX = hSpacing -- [FIX] oUF 속성명 수정
			frame.Buffs.spacingY = vSpacing -- [FIX] oUF 속성명 수정
			frame.Buffs.spacing = hSpacing  -- oUF fallback

			-- [FIX] 1차/2차 방향 지원 (growDirection + columnGrowDirection)
			local growDir, colGrowDir = ResolveAuraGrowth(bDB, "RIGHT", "UP")
			RuntimeApplyAuraGrowth(frame.Buffs, growDir, colGrowDir, numPerLine, hSpacing, vSpacing, iconSize, num)

			-- position
			if bDB.position then
				frame.Buffs:ClearAllPoints()
				local pos = bDB.position
				frame.Buffs:SetPoint(
					pos.point or "BOTTOMLEFT",
					frame,
					pos.relativePoint or "TOPLEFT",
					pos.offsetX or 0,
					pos.offsetY or 2
				)
			end

			-- clickThrough
			if bDB.clickThrough then
				frame.Buffs:EnableMouse(false)
			else
				frame.Buffs:EnableMouse(true)
			end

			-- [12.0.1] 폰트 DB + gradient 색상 런타임 갱신
			frame.Buffs._fontDB = bDB.font
			frame.Buffs._durationColors = bDB.durationColors
			frame.Buffs.showDuration = bDB.showDuration
			frame.Buffs.showStack = bDB.showStack
			frame.Buffs._borderDB = bDB.border

			if frame.unit and UnitExists(frame.unit) then
				SafeForceUpdate(frame.Buffs, function() StandaloneRefresh(frame, "Buffs") end)
			end
		end
	end

	-- 디버프 업데이트
	local dDB = GetWidgetDB(db, "debuffs")
	local debuffs = frame.Debuffs or frame._debuffsFrame
	if debuffs and dDB then
		if dDB.enabled == false then
			if frame.Debuffs then
				self:SetElementEnabled(frame, "Debuffs", false)
			end
			debuffs:Hide()
		else
			if not frame.Debuffs and frame._debuffsFrame then
				frame.Debuffs = frame._debuffsFrame
				frame._debuffsFrame = nil
			end
			self:SetElementEnabled(frame, "Debuffs", true)
			frame.Debuffs:Show()
			local iconSize = (dDB.size and dDB.size.width) or 28
			local num = dDB.maxIcons or 8
			local hSpacing = (dDB.spacing and dDB.spacing.horizontal) or 2
			local numPerLine = dDB.numPerLine or num
			local vSpacing = (dDB.spacing and dDB.spacing.vertical) or 2

			frame.Debuffs.size = iconSize
			frame.Debuffs.num = num
			frame.Debuffs.spacingX = hSpacing -- [FIX] oUF 속성명 수정
			frame.Debuffs.spacingY = vSpacing -- [FIX] oUF 속성명 수정
			frame.Debuffs.spacing = hSpacing  -- oUF fallback

			-- [FIX] 1차/2차 방향 지원 (growDirection + columnGrowDirection)
			local growDir, colGrowDir = ResolveAuraGrowth(dDB, "LEFT", "UP")
			RuntimeApplyAuraGrowth(frame.Debuffs, growDir, colGrowDir, numPerLine, hSpacing, vSpacing, iconSize, num)

			-- position
			if dDB.position then
				frame.Debuffs:ClearAllPoints()
				local pos = dDB.position
				frame.Debuffs:SetPoint(
					pos.point or "BOTTOMRIGHT",
					frame,
					pos.relativePoint or "TOPRIGHT",
					pos.offsetX or 0,
					pos.offsetY or 2
				)
			end

			-- clickThrough
			if dDB.clickThrough then
				frame.Debuffs:EnableMouse(false)
			else
				frame.Debuffs:EnableMouse(true)
			end

			-- [AURA-FILTER] CustomFilter는 Layout.lua에서 설정한 ConfigBasedAuraFilter 유지

			-- [12.0.1] 폰트 DB + gradient 색상 런타임 갱신
			frame.Debuffs._fontDB = dDB.font
			frame.Debuffs._durationColors = dDB.durationColors
			frame.Debuffs.showDuration = dDB.showDuration
			frame.Debuffs.showStack = dDB.showStack
			frame.Debuffs._borderDB = dDB.border

			if frame.unit and UnitExists(frame.unit) then
				SafeForceUpdate(frame.Debuffs, function() StandaloneRefresh(frame, "Debuffs") end)
			end
		end
	end

	-- [12.0.1] 개별 유닛 프레임 생존기 트래커 제거 — CenterDefensiveBuff API는 그룹 프레임에만 존재
end

-----------------------------------------------
-- Update Custom Text
-- Config: db.widgets.customText
-----------------------------------------------

function Update:UpdateCustomText(frame, unitKey)
	if not frame then return end
	local db = ns.db[unitKey]
	if not db then return end

	local ctDB = GetWidgetDB(db, "customText")
	if not ctDB then return end

	-- [FIX] on-demand fontstring 생성: Layout 시점에 _customTexts가 없으면 여기서 생성
	if not frame._customTexts then
		frame._customTexts = {}
	end

	for key, textDB in pairs(ctDB.texts or {}) do
		local fs = frame._customTexts[key]

		-- [FIX] fontstring이 없으면 on-demand 생성
		if not fs then
			local ctParent = frame.TextOverlay or frame.Health
			if not ctParent then break end -- Health도 없으면 포기
			fs = ctParent:CreateFontString(nil, "OVERLAY")
			frame._customTexts[key] = fs
		end

		local hasFormat = textDB.textFormat and textDB.textFormat ~= ""
		if not textDB.enabled or ctDB.enabled == false then
			fs:Hide()
		elseif not hasFormat then
			fs:Hide()
		else
			fs:Show()
			-- 폰트 업데이트
			local font, fontSize, fontFlags = GetFont()
			local tFont = textDB.font
			SafeSetFont(fs,
				(tFont and tFont.style) or font,
				(tFont and tFont.size) or fontSize,
				(tFont and tFont.outline) or fontFlags
			)
			-- 위치 업데이트
			fs:ClearAllPoints()
			if textDB.position then
				local pos = textDB.position
				fs:SetPoint(pos.point or "CENTER", frame.Health, pos.relativePoint or "CENTER", pos.offsetX or 0, pos.offsetY or 0)
			else
				fs:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
			end
			fs:SetJustifyH((tFont and tFont.justify) or "CENTER")
			-- 태그 업데이트: ns.MigrateTagString 사용 (Layout.lua와 동일 로직) -- [FIX]
			local tag = textDB.textFormat or ""
			local migrateFunc = ns.MigrateTagString
			if migrateFunc then
				local newTag = migrateFunc(tag)
				if newTag ~= tag then
					tag = newTag
					textDB.textFormat = tag -- DB도 업데이트
				end
			end

			-- 유효성 검증: ns.IsValidCustomTag 사용 -- [FIX]
			local valid = false
			local validateFunc = ns.IsValidCustomTag
			if validateFunc then
				valid = validateFunc(tag)
			else
				-- 폴백: 직접 검증
				valid = true
				local oUF = ns.oUF
				local tagMethods = oUF and oUF.Tags and oUF.Tags.Methods
				if tag ~= "" and tagMethods then
					for inner in tag:gmatch("%[([^%]]+)%]") do
						if not tagMethods[inner] then
							valid = false
							break
						end
					end
				elseif tag ~= "" then
					valid = false
				end
			end

			if tag ~= "" and valid then
				-- oUF re-tag: Untag old → Tag new
				if frame.Untag then frame:Untag(fs) end
				if frame.Tag then
					frame:Tag(fs, tag)
					-- [FIX] 즉시 태그 평가 → 텍스트 표시
					if fs.UpdateTag then fs:UpdateTag() end
				end
			else
				if frame.Untag then frame:Untag(fs) end
				fs:SetText("") -- 빈/잘못된 태그
			end
		end
	end
end

-----------------------------------------------
-- Update ClassPower
-- Config: db.widgets.classBar
-----------------------------------------------

function Update:UpdateClassPower(frame, unitKey)
	if not frame or not frame.ClassPower then return end
	local db = ns.db[unitKey]
	if not db then return end

	local cpDB = GetWidgetDB(db, "classBar")
	if not cpDB then return end

	if cpDB.enabled == false then
		self:SetElementEnabled(frame, "ClassPower", false) -- [FIX] 리로드 없이 비활성화
		for i = 1, #frame.ClassPower do
			frame.ClassPower[i]:Hide()
		end
	else
		self:SetElementEnabled(frame, "ClassPower", true) -- [FIX] 리로드 없이 활성화
		-- [FIX] 미적용 옵션 연결: hideOutOfCombat
		if cpDB.hideOutOfCombat and not InCombatLockdown() then
			for i = 1, #frame.ClassPower do
				frame.ClassPower[i]:Hide()
			end
			return
		end

		local cpHeight = (cpDB.size and cpDB.size.height) or 4
		local spacing = cpDB.spacing or 2 -- [FIX-OPTION]
		local numBars = #frame.ClassPower
		local totalWidth = frame:GetWidth() - 2 -- 인셋 보정

		-- [FIX-OPTION] sameSizeAsHealthBar 적용
		if cpDB.sameSizeAsHealthBar ~= false and frame.Health then
			totalWidth = frame.Health:GetWidth()
		end

		-- [FIX] 바 텍스처 + 배경 텍스처/색상 적용
		local cpTex = cpDB.texture and ResolveLSM("statusbar", cpDB.texture, GetTexture()) or GetTexture()
		local cpBgTex = (cpDB.background and cpDB.background.texture) and ResolveLSM("statusbar", cpDB.background.texture, cpTex) or cpTex
		local cpBgCol = cpDB.background and cpDB.background.color
		for i = 1, numBars do
			frame.ClassPower[i]:SetStatusBarTexture(cpTex)
			if frame.ClassPower[i].bg then
				frame.ClassPower[i].bg:SetTexture(cpBgTex)
				if cpBgCol then
					frame.ClassPower[i].bg:SetVertexColor(cpBgCol[1] or 0.05, cpBgCol[2] or 0.05, cpBgCol[3] or 0.05, cpBgCol[4] or 0.8)
				end
			end
		end

		local barWidth = (totalWidth - spacing * (numBars - 1)) / numBars
		for i = 1, numBars do
			local bar = frame.ClassPower[i]
			bar:SetHeight(cpHeight)
			bar:SetWidth(math_max(1, barWidth))
			-- 간격 재배치
			if i > 1 then
				bar:ClearAllPoints()
				bar:SetPoint("LEFT", frame.ClassPower[i - 1], "RIGHT", spacing, 0)
			end
		end

		-- [FIX-OPTION] 컨테이너 위치
		if cpDB.position then
			frame.ClassPower[1]:ClearAllPoints()
			local pos = cpDB.position
			frame.ClassPower[1]:SetPoint(
				pos.point or "BOTTOMLEFT",
				frame,
				pos.relativePoint or "TOPLEFT",
				pos.offsetX or 0,
				pos.offsetY or 2
			)
		end

		SafeForceUpdate(frame.ClassPower, function() StandaloneRefresh(frame, "ClassPower") end)
	end
end

-----------------------------------------------
-- Update Text
-- Config: db.widgets.nameText, db.widgets.healthText
-----------------------------------------------

function Update:UpdateText(frame, unitKey)
	if not frame then return end
	local db = ns.db[unitKey]
	if not db then return end

	local font, fontSize, fontFlags = GetFont()

	-- 이름 텍스트
	local nameDB = GetWidgetDB(db, "nameText")
	if frame.NameText and nameDB then
		if nameDB.enabled == false then
			frame.NameText:Hide()
		else
			frame.NameText:Show()

			-- 폰트 업데이트
			local nFont = nameDB.font
			if nFont then
				local fSize = nFont.size or fontSize
				local fOutline = nFont.outline or fontFlags
				local fStyle = nFont.style or font
				SafeSetFont(frame.NameText, fStyle, fSize, fOutline)
				-- [ESSENTIAL] 그림자 설정 적용
				if nFont.shadow then
					frame.NameText:SetShadowColor(0, 0, 0, 1)
					frame.NameText:SetShadowOffset(1, -1)
				else
					frame.NameText:SetShadowOffset(0, 0)
				end
			end

			-- [FIX] 미적용 옵션 연결: nameText.color
			if nameDB.color then
				local colorType = nameDB.color.type or "class_color"
				if colorType == "custom" and nameDB.color.rgb then
					frame.NameText:SetTextColor(unpack(nameDB.color.rgb))
					frame.NameText._customColor = true
				elseif colorType == "class_color" then
					-- [FIX] 클래스 색상: SetTextColor 폴백 (태그 |cff 없을 때 대비)
					frame.NameText._customColor = nil
					local unit = frame.unit
					if unit then
						local _, class = UnitClass(unit)
						if class and RAID_CLASS_COLORS[class] then
							local c = RAID_CLASS_COLORS[class]
							frame.NameText:SetTextColor(c.r, c.g, c.b)
						else
							frame.NameText:SetTextColor(1, 1, 1)
						end
					else
						frame.NameText:SetTextColor(1, 1, 1)
					end
				else
					-- reaction_color, power_color 등: 흰색 기본 (태그에서 처리)
					frame.NameText._customColor = nil
					frame.NameText:SetTextColor(1, 1, 1)
				end
			end

			-- [FIX] 미적용 옵션 연결: nameText.width
			if nameDB.width then
				local wType = nameDB.width.type or "unlimited"
				if wType == "percentage" and frame.Health then
					local healthW = frame.Health:GetWidth()
					-- [FIX] 초기 로드 시 Health 폭이 0이면 프레임 폭으로 폴백
					if healthW <= 0 then healthW = frame:GetWidth() end
					if healthW > 0 then
						local maxW = healthW * (nameDB.width.value or 0.75)
						frame.NameText:SetWidth(maxW)
					end
				elseif wType == "length" and nameDB.width.value then
					frame.NameText:SetWidth(nameDB.width.value)
				elseif wType == "anchor" then
					-- [FIX] 2개 앵커로 너비 결정: SetWidth 해제하여 앵커 기반 너비 사용
					frame.NameText:SetWidth(0)
				else
					-- unlimited 또는 기타: 제약 없음
					frame.NameText:SetWidth(0)
				end
			end

			-- 앵커 업데이트
			if nameDB.position then
				frame.NameText:ClearAllPoints()
				local pos = nameDB.position
				local point = pos.point or "LEFT"
				local relPoint = pos.relativePoint or point
				local oX = pos.offsetX or 0
				local oY = pos.offsetY or 0
				local anchor = frame.Health or frame

				frame.NameText:SetPoint(point, anchor, relPoint, oX, oY)

				-- [FIX] 2개 앵커 지원: rightPoint/leftPoint로 텍스트 범위 제한 (party/raid)
				if pos.leftPoint and frame.Health then
					frame.NameText:SetPoint(pos.leftPoint, frame.Health, pos.leftRelPoint or pos.leftPoint, pos.leftOffsetX or 0, pos.leftOffsetY or 0)
				end
				if pos.rightPoint and frame.Health then
					frame.NameText:SetPoint(pos.rightPoint, frame.Health, pos.rightRelPoint or pos.rightPoint, pos.rightOffsetX or 0, pos.rightOffsetY or 0)
				end

				-- 정렬
				local justify = (nFont and nFont.justify) or "LEFT"
				frame.NameText:SetJustifyH(justify)
			end

			-- 이름 포맷 변경 → oUF re-tag
			if frame.NameText and frame.Untag and frame.Tag then
				frame:Untag(frame.NameText)
				local nameFmt = nameDB.format or "name"
				local nameTagStr = (ns.NAME_FORMAT_TO_TAG and ns.NAME_FORMAT_TO_TAG[nameFmt])
					or "[ddingui:classcolor][ddingui:name]|r"
				-- [FIX] 색상 타입에 따라 프리픽스 교체 (NAME_FORMAT_TO_TAG에 classcolor 내장)
				local nameColorType = nameDB.color and nameDB.color.type or "class_color"
				if nameColorType == "reaction_color" then
					nameTagStr = nameTagStr:gsub("%[ddingui:classcolor%]", "[ddingui:reactioncolor]")
				elseif nameColorType == "power_color" then
					nameTagStr = nameTagStr:gsub("%[ddingui:classcolor%]", "[ddingui:powercolor]")
				elseif nameColorType == "custom" then
					nameTagStr = nameTagStr:gsub("%[ddingui:classcolor%]", "")
					nameTagStr = nameTagStr:gsub("|r$", "")
				end
				frame:Tag(frame.NameText, nameTagStr)
			end
			ForceRefreshText(frame)
		end
	end

	-- 체력 텍스트
	local healthDB = GetWidgetDB(db, "healthText")
	if frame.HealthText and healthDB then
		if healthDB.enabled == false then
			frame.HealthText:Hide()
		else
			frame.HealthText:Show()

			-- 폰트 업데이트
			local hFont = healthDB.font
			if hFont then
				local fSize = hFont.size or fontSize
				local fOutline = hFont.outline or fontFlags
				local fStyle = hFont.style or font
				frame.HealthText:SetFont(fStyle, fSize, fOutline)
				-- [ESSENTIAL] 그림자 설정 적용
				if hFont.shadow then
					frame.HealthText:SetShadowColor(0, 0, 0, 1)
					frame.HealthText:SetShadowOffset(1, -1)
				else
					frame.HealthText:SetShadowOffset(0, 0)
				end
			end

			-- 앵커 업데이트
			if healthDB.position then
				frame.HealthText:ClearAllPoints()
				local pos = healthDB.position
				local point = pos.point or "RIGHT"
				local relPoint = pos.relativePoint or point
				local oX = pos.offsetX or 0
				local oY = pos.offsetY or 0

				if frame.Health then
					frame.HealthText:SetPoint(point, frame.Health, relPoint, oX, oY)
				else
					frame.HealthText:SetPoint(point, frame, relPoint, oX, oY)
				end

				local justify = (hFont and hFont.justify) or "RIGHT"
				frame.HealthText:SetJustifyH(justify)
			end

			-- 포맷 변경 → oUF re-tag + 즉시 갱신
			if frame.HealthText and frame.Untag and frame.Tag then
				frame:Untag(frame.HealthText)
				local htFmt = healthDB.format or "percentage"
				local htTagStr = (ns.HEALTH_FORMAT_TO_TAG and ns.HEALTH_FORMAT_TO_TAG[htFmt])
					or "[ddingui:ht:pct]"
				-- [FIX] healthText 색상 타입에 따른 태그 프리픽스 추가
				local htColorType = healthDB.color and healthDB.color.type or "custom"
				if htColorType == "class_color" then
					htTagStr = "[ddingui:classcolor]" .. htTagStr .. "|r"
				elseif htColorType == "reaction_color" then
					htTagStr = "[ddingui:reactioncolor]" .. htTagStr .. "|r"
				elseif htColorType == "power_color" then
					htTagStr = "[ddingui:powercolor]" .. htTagStr .. "|r"
				end
				frame:Tag(frame.HealthText, htTagStr)
			end
			ForceRefreshText(frame)

			-- [FIX] 미적용 옵션 연결: healthText.color
			if healthDB.color then
				local colorType = healthDB.color.type or "custom"
				if colorType == "custom" and healthDB.color.rgb then
					frame.HealthText:SetTextColor(unpack(healthDB.color.rgb))
				else
					-- class_color/reaction_color/power_color는 태그 프리픽스가 처리
					frame.HealthText:SetTextColor(1, 1, 1)
				end
			end

			-- [FIX] 미적용 옵션 연결: hideIfFull/hideIfEmpty/showDeadStatus
			if frame.Health then
				frame.Health._healthTextHideIfFull = healthDB.hideIfFull
				frame.Health._healthTextHideIfEmpty = healthDB.hideIfEmpty
				frame.Health._healthTextShowDeadStatus = healthDB.showDeadStatus
			end
		end
	end

	-- [ElvUI 패턴] 자원 텍스트: 포맷별 태그 문자열 변경으로 즉시 반영
	local ptDB = GetWidgetDB(db, "powerText")
	-- [FIX] ptDB가 nil이면 defaults에서 생성 시도 (SavedVars 마이그레이션 누락 대응)
	if frame.PowerText and not ptDB then
		local defPT = ns.WidgetDefaults and ns.WidgetDefaults.powerText
		if defPT then
			if not db.widgets then db.widgets = {} end
			local function SimpleCopy(t)
				if type(t) ~= "table" then return t end
				local c = {}; for k,v in pairs(t) do c[k] = type(v) == "table" and SimpleCopy(v) or v end; return c
			end
			db.widgets.powerText = SimpleCopy(defPT)
			-- 유닛별 override 적용
			local baseUnit = unitKey:gsub("%d", "")
			if baseUnit == "player" or baseUnit == "target" or baseUnit == "focus" then
				db.widgets.powerText.enabled = true
			end
			ptDB = db.widgets.powerText
		end
	end
	if frame.PowerText and ptDB then
		if ptDB.enabled == false then
			frame.PowerText:Hide()
		else
			frame.PowerText:Show()

			-- 폰트 업데이트
			local pFont = ptDB.font
			if pFont then
				local fSize = pFont.size or (fontSize - 1)
				local fOutline = pFont.outline or fontFlags
				local fStyle = pFont.style or font
				SafeSetFont(frame.PowerText, fStyle, fSize, fOutline)
				if pFont.shadow then
					frame.PowerText:SetShadowColor(0, 0, 0, 1)
					frame.PowerText:SetShadowOffset(1, -1)
				else
					frame.PowerText:SetShadowOffset(0, 0)
				end
			end

			-- 앵커 업데이트
			frame.PowerText:ClearAllPoints()
			local anchor = (ptDB.anchorToPowerBar and frame.Power) or frame.Health
			if anchor then
				if ptDB.position then
					local pos = ptDB.position
					frame.PowerText:SetPoint(pos.point or "RIGHT", anchor, pos.relativePoint or "CENTER", pos.offsetX or -4, pos.offsetY or 0)
				else
					frame.PowerText:SetPoint("LEFT", anchor, "LEFT", 4, 0)
				end
			end

			local justify = (pFont and pFont.justify) or "RIGHT"
			frame.PowerText:SetJustifyH(justify)

			-- 포맷 변경 → oUF re-tag + 즉시 갱신
			if frame.PowerText and frame.Untag and frame.Tag then
				frame:Untag(frame.PowerText)
				local ptFmt = ptDB.format or "percentage"
				local ptTagStr = (ns.POWER_FORMAT_TO_TAG and ns.POWER_FORMAT_TO_TAG[ptFmt])
					or "[ddingui:pt:pct]"
				-- [FIX] 색상 타입에 따른 태그 프리픽스 추가 (Layout.lua와 동일)
				local ptColorType = ptDB.color and ptDB.color.type or "power_color"
				if ptColorType == "power_color" then
					ptTagStr = "[ddingui:powercolor]" .. ptTagStr .. "|r"
				elseif ptColorType == "class_color" then
					ptTagStr = "[ddingui:classcolor]" .. ptTagStr .. "|r"
				elseif ptColorType == "reaction_color" then
					ptTagStr = "[ddingui:reactioncolor]" .. ptTagStr .. "|r"
				end
				frame:Tag(frame.PowerText, ptTagStr)
			end
			ForceRefreshText(frame)

			-- 색상 (custom만 SetTextColor, 나머지는 태그 |cff에서 처리)
			if ptDB.color then
				local colorType = ptDB.color.type or "power_color"
				if colorType == "custom" and ptDB.color.rgb then
					frame.PowerText:SetTextColor(ptDB.color.rgb[1] or 1, ptDB.color.rgb[2] or 1, ptDB.color.rgb[3] or 1)
				else
					frame.PowerText:SetTextColor(1, 1, 1)
				end
			end
		end
	end
end

-----------------------------------------------
-- Update Indicators
-- Config: db.widgets.raidIcon, db.widgets.roleIcon, etc.
-----------------------------------------------

-- [FIX-OPTION] 인디케이터 위치 적용 헬퍼
local function ApplyIndicatorPosition(indicator, posDB, parent)
	if not indicator or not posDB then return end
	indicator:ClearAllPoints()
	local anchor = parent or indicator:GetParent()
	indicator:SetPoint(
		posDB.point or "CENTER",
		anchor,
		posDB.relativePoint or "CENTER",
		posDB.offsetX or 0,
		posDB.offsetY or 0
	)
end

function Update:UpdateIndicators(frameOrUnit, unitKey)
	local frame, unit = ResolveFrameUnit(self, frameOrUnit, unitKey)
	if not frame then return end

	local db = ns.db[unit]
	if not db then return end

	-- [FIX] 인디케이터 활성/비활성 - SetElementEnabled로 show/hide 처리
	local hasUnit = frame.unit and UnitExists(frame.unit)

	-- 공격대 아이콘
	local raidIconDB = GetWidgetDB(db, "raidIcon")
	if frame.RaidTargetIndicator and raidIconDB then
		if raidIconDB.enabled == false then
			self:SetElementEnabled(frame, "RaidTargetIndicator", false)
		else
			self:SetElementEnabled(frame, "RaidTargetIndicator", true)
			local size = (raidIconDB.size and raidIconDB.size.width) or 14
			frame.RaidTargetIndicator:SetSize(size, size)
			if raidIconDB.position then
				ApplyIndicatorPosition(frame.RaidTargetIndicator, raidIconDB.position, frame)
			end
			if hasUnit and frame.RaidTargetIndicator.ForceUpdate then frame.RaidTargetIndicator:ForceUpdate() end
		end
	end

	-- 준비 확인
	local readyDB = GetWidgetDB(db, "readyCheckIcon")
	if frame.ReadyCheckIndicator and readyDB then
		if readyDB.enabled == false then
			self:SetElementEnabled(frame, "ReadyCheckIndicator", false)
		else
			self:SetElementEnabled(frame, "ReadyCheckIndicator", true)
			local size = (readyDB.size and readyDB.size.width) or 16
			frame.ReadyCheckIndicator:SetSize(size, size)
			if readyDB.position then
				ApplyIndicatorPosition(frame.ReadyCheckIndicator, readyDB.position, frame)
			end
			if hasUnit and frame.ReadyCheckIndicator.ForceUpdate then frame.ReadyCheckIndicator:ForceUpdate() end
		end
	end

	-- 역할 아이콘
	local roleDB = GetWidgetDB(db, "roleIcon")
	if frame.GroupRoleIndicator and roleDB then
		if roleDB.enabled == false then
			self:SetElementEnabled(frame, "GroupRoleIndicator", false)
		else
			self:SetElementEnabled(frame, "GroupRoleIndicator", true)
			local size = (roleDB.size and roleDB.size.width) or 14
			frame.GroupRoleIndicator:SetSize(size, size)
			if roleDB.position then
				ApplyIndicatorPosition(frame.GroupRoleIndicator, roleDB.position, frame)
			end
			if hasUnit and frame.GroupRoleIndicator.ForceUpdate then frame.GroupRoleIndicator:ForceUpdate() end
		end
	end

	-- 부활 아이콘
	local resDB = GetWidgetDB(db, "resurrectIcon")
	if frame.ResurrectIndicator and resDB then
		if resDB.enabled == false then
			self:SetElementEnabled(frame, "ResurrectIndicator", false)
		else
			self:SetElementEnabled(frame, "ResurrectIndicator", true)
			local size = (resDB.size and resDB.size.width) or 20
			frame.ResurrectIndicator:SetSize(size, size)
			if resDB.position then
				ApplyIndicatorPosition(frame.ResurrectIndicator, resDB.position, frame)
			end
			if hasUnit and frame.ResurrectIndicator.ForceUpdate then frame.ResurrectIndicator:ForceUpdate() end
		end
	end

	-- 파티장 아이콘
	local leaderDB = GetWidgetDB(db, "leaderIcon")
	if frame.LeaderIndicator and leaderDB then
		if leaderDB.enabled == false then
			self:SetElementEnabled(frame, "LeaderIndicator", false)
		else
			self:SetElementEnabled(frame, "LeaderIndicator", true)
			local size = (leaderDB.size and leaderDB.size.width) or 14
			frame.LeaderIndicator:SetSize(size, size)
			-- [REFACTOR] 아이콘 세트 변경 시 텍스처 갱신
			local curIconSet = C.ICON_SETS[ns.db.iconSet or "default"] or C.ICON_SETS["default"]
			frame.LeaderIndicator._iconSetTexture = curIconSet.leader
			if leaderDB.position then
				ApplyIndicatorPosition(frame.LeaderIndicator, leaderDB.position, frame)
			end
			if hasUnit and frame.LeaderIndicator.ForceUpdate then frame.LeaderIndicator:ForceUpdate() end
		end
	end

	-- 전투 아이콘
	local combatDB = GetWidgetDB(db, "combatIcon")
	if frame.CombatIndicator and combatDB then
		if combatDB.enabled == false then
			self:SetElementEnabled(frame, "CombatIndicator", false)
		else
			self:SetElementEnabled(frame, "CombatIndicator", true)
			local size = (combatDB.size and combatDB.size.width) or 20
			frame.CombatIndicator:SetSize(size, size)
			if combatDB.position then
				ApplyIndicatorPosition(frame.CombatIndicator, combatDB.position, frame)
			end
			if hasUnit and frame.CombatIndicator.ForceUpdate then frame.CombatIndicator:ForceUpdate() end
		end
	end

	-- 휴식 아이콘
	local restDB = GetWidgetDB(db, "restingIcon")
	if frame.RestingIndicator and restDB then
		if restDB.enabled == false then
			self:SetElementEnabled(frame, "RestingIndicator", false)
		else
			self:SetElementEnabled(frame, "RestingIndicator", true)
			local size = (restDB.size and restDB.size.width) or 18
			frame.RestingIndicator:SetSize(size, size)
			-- [REFACTOR] 아이콘 세트 변경 시 텍스처 갱신
			local curIconSet = C.ICON_SETS[ns.db.iconSet or "default"] or C.ICON_SETS["default"]
			frame.RestingIndicator._iconSetTexture = curIconSet.resting
			frame.RestingIndicator._iconSetCoords = curIconSet.restingCoords or nil
			if curIconSet.resting then
				frame.RestingIndicator:SetTexture(curIconSet.resting)
				if curIconSet.restingCoords then
					frame.RestingIndicator:SetTexCoord(unpack(curIconSet.restingCoords))
				else
					frame.RestingIndicator:SetTexCoord(0, 1, 0, 1)
				end
			end
			if restDB.position then
				ApplyIndicatorPosition(frame.RestingIndicator, restDB.position, frame)
			end
			-- hideAtMaxLevel PostUpdate 갱신
			if restDB.hideAtMaxLevel then
				frame.RestingIndicator.PostUpdate = function(element, isResting)
					if isResting then
						local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or MAX_PLAYER_LEVEL or 80
						if UnitLevel("player") >= maxLevel then
							element:Hide()
						end
					end
				end
			else
				frame.RestingIndicator.PostUpdate = nil
			end
			if hasUnit and frame.RestingIndicator.ForceUpdate then frame.RestingIndicator:ForceUpdate() end
		end
	end

	-- 소환 아이콘
	local summonDB = GetWidgetDB(db, "summonIcon")
	if frame.SummonIndicator and summonDB then
		if summonDB.enabled == false then
			self:SetElementEnabled(frame, "SummonIndicator", false)
		else
			self:SetElementEnabled(frame, "SummonIndicator", true)
			local size = (summonDB.size and summonDB.size.width) or 20
			frame.SummonIndicator:SetSize(size, size)
			if summonDB.position then
				ApplyIndicatorPosition(frame.SummonIndicator, summonDB.position, frame)
			end
			if hasUnit and frame.SummonIndicator.ForceUpdate then frame.SummonIndicator:ForceUpdate() end
		end
	end

	-- 위협 표시
	local threatDB = GetWidgetDB(db, "threat")
	if frame.ThreatIndicator and threatDB then
		if threatDB.enabled == false then
			self:SetElementEnabled(frame, "ThreatIndicator", false)
		else
			self:SetElementEnabled(frame, "ThreatIndicator", true)
			-- [FIX] 미적용 옵션 연결: threat borderSize
			if threatDB.borderSize then
				local tBorder = F:ScalePixel(threatDB.borderSize)
				-- [FIX] edgeSize 0 또는 프레임 사이즈 0 → TexCoord out of range 방지
				if tBorder and tBorder > 0 and frame:GetWidth() > 0 and frame:GetHeight() > 0 then
					frame.ThreatIndicator:ClearAllPoints()
					frame.ThreatIndicator:SetPoint("TOPLEFT", frame, "TOPLEFT", -tBorder, tBorder)
					frame.ThreatIndicator:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", tBorder, -tBorder)
					local bd = frame.ThreatIndicator:GetBackdrop()
					if bd then
						bd.edgeSize = tBorder
						frame.ThreatIndicator:SetBackdrop(bd)
					end
				end
			end
			-- [FIX] 미적용 옵션 연결: threat colors (PostUpdate에서 사용)
			if threatDB.colors then
				frame.ThreatIndicator._colors = threatDB.colors
			end
			-- [FIX] 미적용 옵션 연결: threat style
			if threatDB.style then
				frame.ThreatIndicator._style = threatDB.style
			end
			if hasUnit and frame.ThreatIndicator.ForceUpdate then frame.ThreatIndicator:ForceUpdate() end
		end
	end

	-- 치유 예측
	local hpDB = GetWidgetDB(db, "healPrediction")
	if frame.HealthPrediction and hpDB then
		if hpDB.enabled == false then
			self:SetElementEnabled(frame, "HealthPrediction", false)
		else
			self:SetElementEnabled(frame, "HealthPrediction", true)

			-- [REFACTOR] 색상은 전역 ns.Colors에서 읽기
			local hpColor = (ns.Colors and ns.Colors.healPrediction and ns.Colors.healPrediction.color) or { 0, 1, 0.5, 0.4 }
			if frame.HealthPrediction.healingAll then
				frame.HealthPrediction.healingAll:GetStatusBarTexture():SetVertexColor(unpack(hpColor))
			end

			-- 텍스처는 per-unit 설정에서 읽기 (각 요소별 분리)
			local defaultTex = GetTexture()
			if hpDB.texture then
				local hpTex = ResolveLSM("statusbar", hpDB.texture, defaultTex)
				if frame.HealthPrediction.healingAll then frame.HealthPrediction.healingAll:SetStatusBarTexture(hpTex) end
			end

			local sbDB = GetWidgetDB(db, "shieldBar")
			local sbColor = (ns.Colors and ns.Colors.shieldBar and ns.Colors.shieldBar.shieldColor) or { 1, 1, 0, 0.4 }
			if frame.HealthPrediction.damageAbsorb then
				frame.HealthPrediction.damageAbsorb:GetStatusBarTexture():SetVertexColor(unpack(sbColor))
			end
			if sbDB and sbDB.texture then
				local sbTex = ResolveLSM("statusbar", sbDB.texture, defaultTex)
				if frame.HealthPrediction.damageAbsorb then frame.HealthPrediction.damageAbsorb:SetStatusBarTexture(sbTex) end
			end

			local haDB = GetWidgetDB(db, "healAbsorb")
			local haColor = (ns.Colors and ns.Colors.healAbsorb and ns.Colors.healAbsorb.color) or { 1, 0.1, 0.1, 0.5 }
			if frame.HealthPrediction.healAbsorb then
				frame.HealthPrediction.healAbsorb:GetStatusBarTexture():SetVertexColor(unpack(haColor))
			end
			if haDB and haDB.texture then
				local haTex = ResolveLSM("statusbar", haDB.texture, defaultTex)
				if frame.HealthPrediction.healAbsorb then frame.HealthPrediction.healAbsorb:SetStatusBarTexture(haTex) end
			end

			SafeForceUpdate(frame.HealthPrediction, function() StandaloneRefresh(frame, "HealthPrediction") end)
		end
	end
end

-----------------------------------------------
-- Update Highlight -- [FIX] 미적용 옵션 연결
-- Config: db.widgets.highlight
-----------------------------------------------

function Update:UpdateHighlight(frameOrUnit, unitKey)
	local frame, unit = ResolveFrameUnit(self, frameOrUnit, unitKey)
	if not frame or not frame.Highlight then return end

	local db = ns.db[unit]
	if not db then return end

	local hlDB = GetWidgetDB(db, "highlight")
	if not hlDB then return end

	-- [FIX] highlight.enabled 값에 따른 활성/비활성 처리
	if hlDB.enabled == false then
		self:SetElementEnabled(frame, "Highlight", false)
		return
	else
		self:SetElementEnabled(frame, "Highlight", true)
	end

	-- _db 참조 갱신 (Elements/Highlight.lua의 UpdateTarget/UpdateFocus에서 사용)
	frame.Highlight._db = hlDB

	-- [FIX] 미적용 옵션 연결: highlight.size (border thickness)
	if hlDB.size and frame.Highlight.target then
		local thickness = F:ScalePixel(hlDB.size)
		-- [FIX] edgeSize 0 또는 프레임 사이즈 0 → TexCoord out of range 방지
		if thickness and thickness > 0 and frame:GetWidth() > 0 and frame:GetHeight() > 0 then
			for _, key in pairs({"target", "focus", "hover"}) do
				local border = frame.Highlight[key]
				if border then
					border:ClearAllPoints()
					border:SetPoint("TOPLEFT", frame, "TOPLEFT", -thickness, thickness)
					border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, -thickness)
					local bd = border:GetBackdrop()
					if bd then
						bd.edgeSize = thickness
						border:SetBackdrop(bd)
					end
				end
			end
		end
	end

	-- 강제 업데이트 (색상은 Elements/Highlight.lua에서 _db 읽어서 적용)
	SafeForceUpdate(frame.Highlight, function() StandaloneRefresh(frame, "Highlight") end)
end

-----------------------------------------------
-- Refresh Fading
-----------------------------------------------

function Update:RefreshFading()
	local outOfRangeAlpha = ns.db.outOfRangeAlpha or 0.4

	-- 개인 유닛 프레임 범위 알파 갱신 (oUF Range element 처리)
	for unitKey, frame in pairs(ns.frames) do
		frame._outOfRangeAlpha = outOfRangeAlpha
		if frame.unit and UnitExists(frame.unit) then
			SafeUpdateAllElements(frame, "RefreshFrame")
		end
	end

	-- GroupFrames는 자체 Range 시스템 사용 (GroupFrames/Range.lua)
	local GF = ns.GroupFrames
	if GF and GF.allFrames then
		for _, frame in pairs(GF.allFrames) do
			if frame then
				frame._outOfRangeAlpha = outOfRangeAlpha
			end
		end
	end
end

-----------------------------------------------
-- Refresh Full Frame
-----------------------------------------------

function Update:RefreshFrame(unitKey)
	local frame = ns.frames[unitKey]
	if not frame then return end

	self:UpdateEnabled(unitKey) -- [REFACTOR] 프로필 전환 시 활성/비활성 재적용
	self:UpdateBorder(frame, unitKey) -- [FIX] 테두리/배경 런타임 갱신
	self:UpdateFrameSize(frame, unitKey)
	self:UpdateHealth(frame, unitKey)
	self:UpdatePower(frame, unitKey)
	self:UpdateAltPower(frame, unitKey) -- [REFACTOR] 보조 자원바
	self:UpdateCastbar(frame, unitKey)
	self:UpdateCastbarPosition(frame, unitKey)
	self:UpdateAuras(frame, unitKey)
	self:UpdateCustomText(frame, unitKey)
	self:UpdateText(frame, unitKey)
	self:UpdateIndicators(frame, unitKey)
	self:UpdateHighlight(frame, unitKey) -- [FIX] 미적용 옵션 연결

	-- [CDM 호환] 위치 재적용 (attachTo/selfPoint/anchorPoint 설정 변경 시 즉시 반영)
	-- 편집모드 중에는 Mover가 위치를 관리하므로 스킵
	local isEditMode = ns.Mover and ns.Mover.IsUnlocked and ns.Mover:IsUnlocked()
	if not isEditMode and not InCombatLockdown() then
		local cfg = ns.db[unitKey]
		if cfg and ns.ApplyUnitPosition then
			-- 종속 유닛 (targettarget, focustarget, pet)은 부모 앵커 사용
			if not cfg.anchorToParent then
				local FALLBACKS = {
					player = { "BOTTOMLEFT", UIParent, "BOTTOM", -260, 200 },
					target = { "BOTTOMRIGHT", UIParent, "BOTTOM", 260, 200 },
					focus = { "LEFT", UIParent, "LEFT", 80, -100 },
				}
				local fb = FALLBACKS[unitKey]
				frame:ClearAllPoints()
				if fb then
					ns.ApplyUnitPosition(frame, cfg, fb[1], fb[2], fb[3], fb[4], fb[5])
				else
					ns.ApplyUnitPosition(frame, cfg, "CENTER", UIParent, "CENTER", 0, 0)
				end
			end
		end
	end

	if unitKey == "player" then
		self:UpdateClassPower(frame, unitKey)
	end

	-- [FIX] PrivateAuras 런타임 enable/disable (설정 끄면 즉시 비활성)
	if frame.PrivateAuras then
		local paDB = ns.db[unitKey] and ns.db[unitKey].widgets and ns.db[unitKey].widgets.privateAuras
		if not paDB then
			paDB = ns.db.privateAuras -- 글로벌 fallback
		end
		if paDB and paDB.enabled == false then
			self:SetElementEnabled(frame, "PrivateAuras", false)
			frame.PrivateAuras:Hide()
		else
			self:SetElementEnabled(frame, "PrivateAuras", true)
			frame.PrivateAuras:Show()
		end
	end

	if frame.unit and UnitExists(frame.unit) then
		SafeUpdateAllElements(frame, "RefreshFrame")
	end
end

function Update:RefreshAllFrames()
	for unitKey, frame in pairs(ns.frames) do
		self:RefreshFrame(unitKey)
	end
end

-----------------------------------------------
-- Group Frame Refresh
-----------------------------------------------

function Update:RefreshPartyFrames()
	-- [REFACTOR] GroupFrames 경로 (oUF 폴백 제거)
	local GF = ns.GroupFrames
	if GF and GF.headersInitialized then
		for _, frame in pairs(GF.allFrames or {}) do
			if frame and not frame.isRaidFrame then
				if GF.ApplyLayout then GF:ApplyLayout(frame) end
				if GF.FullFrameRefresh then GF:FullFrameRefresh(frame) end
			end
		end
	end
	self:RefreshSimFrameSize("party")
end

function Update:RefreshRaidFrames()
	if not ns.db.raid then
		self:RefreshSimFrameSize("raid")
		return
	end

	-- [REFACTOR] GroupFrames 경로 (oUF 폴백 제거)
	local GF = ns.GroupFrames
	if GF and GF.headersInitialized then
		for _, frame in pairs(GF.allFrames or {}) do
			if frame and frame.isRaidFrame then
				if GF.ApplyLayout then GF:ApplyLayout(frame) end
				if GF.FullFrameRefresh then GF:FullFrameRefresh(frame) end
			end
		end
	end
	self:RefreshSimFrameSize("raid")
end

function Update:RefreshBossFrames()
	if not ns.db.boss then return end
	local settings = ns.db.boss
	local spacing = settings.spacing or 48
	local growDir = settings.growDirection or "DOWN"

	for i = 1, (C.MAX_BOSS_FRAMES or 8) do
		local frame = ns.frames["boss" .. i]
		if frame then
			self:UpdateBorder(frame, "boss")
			self:UpdateFrameSize(frame, "boss")
			self:UpdateHealth(frame, "boss")
			self:UpdatePower(frame, "boss")
			self:UpdateCastbar(frame, "boss")
			self:UpdateCastbarPosition(frame, "boss")
			self:UpdateAuras(frame, "boss")
			self:UpdateCustomText(frame, "boss")
			self:UpdateText(frame, "boss")

			-- [12.0.1] 간격/성장방향 실시간 갱신
			if i > 1 then
				local prev = ns.frames["boss" .. (i - 1)]
				if prev then
					frame:ClearAllPoints()
					if growDir == "UP" then
						frame:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
					else
						frame:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
					end
				end
			end

			if frame.unit and UnitExists(frame.unit) then
				SafeUpdateAllElements(frame, "RefreshFrame")
			end
		end
	end
end

function Update:RefreshArenaFrames()
	if not ns.db.arena then return end
	local settings = ns.db.arena
	local spacing = settings.spacing or 48
	local growDir = settings.growDirection or "DOWN"

	for i = 1, (C.MAX_ARENA_FRAMES or 5) do
		local frame = ns.frames["arena" .. i]
		if frame then
			self:UpdateBorder(frame, "arena")
			self:UpdateFrameSize(frame, "arena")
			self:UpdateHealth(frame, "arena")
			self:UpdatePower(frame, "arena")
			self:UpdateCastbar(frame, "arena")
			self:UpdateCastbarPosition(frame, "arena")
			self:UpdateText(frame, "arena")
			self:UpdateCustomText(frame, "arena") -- [FIX] 커스텀 태그 누락

			-- [12.0.1] 간격/성장방향 실시간 갱신
			if i > 1 then
				local prev = ns.frames["arena" .. (i - 1)]
				if prev then
					frame:ClearAllPoints()
					if growDir == "UP" then
						frame:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
					else
						frame:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
					end
				end
			end

			if frame.unit and UnitExists(frame.unit) then
				SafeUpdateAllElements(frame, "RefreshFrame")
			end
		end
	end
end

-----------------------------------------------
-- Refresh Media (Texture/Font)
-----------------------------------------------

function Update:RefreshMedia()
	local texture = GetTexture()
	local font, fontSize, fontFlags = GetFont()

	for unitKey, frame in pairs(ns.frames) do
		if frame.Health then
			frame.Health:SetStatusBarTexture(texture)
			if frame.Health.bg then
				frame.Health.bg:SetTexture(texture)
			end
		end

		if frame.Power then
			frame.Power:SetStatusBarTexture(texture)
			if frame.Power.bg then
				frame.Power.bg:SetTexture(texture)
			end
		end

		if frame.Castbar then
			frame.Castbar:SetStatusBarTexture(texture)
			if frame.Castbar.Text then
				frame.Castbar.Text:SetFont(font, fontSize - 1, fontFlags)
			end
			if frame.Castbar.Time then
				frame.Castbar.Time:SetFont(font, fontSize - 1, fontFlags)
			end
		end

		-- [FIX-OPTION] 텍스트 폰트: 위젯별 설정 우선, 없으면 전역 폰트
		local unitDB = ns.db[unitKey]
		local nameDB = unitDB and GetWidgetDB(unitDB, "nameText")
		if frame.NameText then
			if nameDB and nameDB.font and nameDB.font.size then
				local nf = nameDB.font
				frame.NameText:SetFont(nf.style or font, nf.size, nf.outline or fontFlags)
			else
				frame.NameText:SetFont(font, fontSize, fontFlags)
			end
		end
		local healthDB = unitDB and GetWidgetDB(unitDB, "healthText")
		if frame.HealthText then
			if healthDB and healthDB.font and healthDB.font.size then
				local hf = healthDB.font
				frame.HealthText:SetFont(hf.style or font, hf.size, hf.outline or fontFlags)
			else
				frame.HealthText:SetFont(font, fontSize, fontFlags)
			end
		end

		-- [FIX] 오라 아이콘 폰트 라이브 업데이트
		if ns._RefreshAuraFonts then
			local buffDB = unitDB and unitDB.widgets and unitDB.widgets.buffs
			if frame.Buffs and buffDB then
				frame.Buffs._fontDB = buffDB.font
				frame.Buffs._durationColors = buffDB.durationColors
				ns._RefreshAuraFonts(frame.Buffs)
			end
			local debuffDB = unitDB and unitDB.widgets and unitDB.widgets.debuffs
			if frame.Debuffs and debuffDB then
				frame.Debuffs._fontDB = debuffDB.font
				frame.Debuffs._durationColors = debuffDB.durationColors
				ns._RefreshAuraFonts(frame.Debuffs)
			end
		end
	end

	self:RefreshPartyFrames()
	self:RefreshRaidFrames()
end

-----------------------------------------------
-- Convenience Functions (Options Panel 호출용)
-----------------------------------------------

local function ApplyToUnit(self, unitKey, internalUpdateFunc)
	local frame = ns.frames[unitKey]
	if frame then
		if internalUpdateFunc then
			internalUpdateFunc(self, frame, unitKey)
		end
		if frame.unit and UnitExists(frame.unit) then
			SafeUpdateAllElements(frame, "RefreshFrame")
		end
	elseif unitKey == "party" then
		ns.Debug("ApplyToUnit: routing to RefreshPartyFrames")
		self:RefreshPartyFrames()
	elseif unitKey == "raid" then
		ns.Debug("ApplyToUnit: routing to RefreshRaidFrames")
		self:RefreshRaidFrames()
	elseif unitKey == "boss" then
		self:RefreshBossFrames()
	elseif unitKey == "arena" then
		self:RefreshArenaFrames()
	end
end

function Update:RefreshUnit(unitKey)
	if unitKey == "party" then
		self:RefreshPartyFrames()
	elseif unitKey == "raid" then
		self:RefreshRaidFrames()
	elseif unitKey == "boss" then
		self:RefreshBossFrames()
	elseif unitKey == "arena" then
		self:RefreshArenaFrames()
	else
		self:RefreshFrame(unitKey)
	end
end

function Update:UpdateSize(unitKey)
	ApplyToUnit(self, unitKey, Update.UpdateFrameSize)
	-- 편집모드 프레임도 실시간 갱신
	self:RefreshSimFrameSize(unitKey)
end

function Update:UpdateAnchor(unitKey)
	self:RefreshUnit(unitKey)
end

function Update:UpdateOrientation(unitKey)
	self:RefreshUnit(unitKey)
end

function Update:UpdateLayout(unitKey)
	-- [REFACTOR] GroupFrames (non-oUF) 헤더 속성 런타임 갱신
	local GF = ns.GroupFrames
	local gfHandled = false
	if GF and GF.headersInitialized and not InCombatLockdown() then
		if unitKey == "party" and GF.partyHeader then
			local db = ns.db.party
			if db then
				local growDir = db.growDirection or "DOWN"
				local colGrowDir = db.columnGrowDirection or "RIGHT"
				local point = (ns.GROW_TO_POINT or {})[growDir] or "TOP"
				local colAnchor = (ns.COLUMN_GROW_TO_ANCHOR or {})[colGrowDir] or "LEFT"
				local priKey, priVal, secKey, secVal = ns.GetGrowOffsets(growDir, db.spacing or 4)
				local colSpacing = (colGrowDir == "LEFT" or colGrowDir == "UP") and -(db.spacingX or 4) or (db.spacingX or 4)
				local size = db.size or { 120, 36 }
				local header = GF.partyHeader
				header:SetAttribute("point", point)
				header:SetAttribute(priKey, priVal)
				header:SetAttribute(secKey, secVal)
				header:SetAttribute("maxColumns", db.maxColumns or 1)
				header:SetAttribute("unitsPerColumn", db.unitsPerColumn or 5)
				header:SetAttribute("columnSpacing", colSpacing)
				header:SetAttribute("columnAnchorPoint", colAnchor)
				header:SetAttribute("sortDir", db.sortDir or "ASC")
				header:SetAttribute("sortMethod", db.sortBy or "INDEX")
				header:SetAttribute("showPlayer", db.showPlayer or false)
				header:SetAttribute("gf-width", size[1])
				header:SetAttribute("gf-height", size[2])
				local groupByAttr = db.groupBy or "GROUP"
				if groupByAttr == "ROLE" then
					header:SetAttribute("groupBy", "ASSIGNEDROLE")
					header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
				elseif groupByAttr == "CLASS" then
					header:SetAttribute("groupBy", "CLASS")
					header:SetAttribute("groupingOrder", "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,DEATHKNIGHT,SHAMAN,MAGE,WARLOCK,MONK,DRUID,DEMONHUNTER,EVOKER")
				else
					header:SetAttribute("groupBy", nil)
					header:SetAttribute("groupingOrder", nil)
				end
				header:Hide()
				header:Show()
				-- [REFACTOR] 자식 프레임 레이아웃도 갱신
				for _, frame in pairs(GF.allFrames or {}) do
					if frame and not frame.isRaidFrame then
						GF:ApplyLayout(frame)
					end
				end
				gfHandled = true
			end
		elseif (unitKey == "raid" or unitKey == "mythicRaid") and GF.raidHeaders then
			-- [MYTHIC-RAID] mythicRaid 설정 변경 시에도 레이드 헤더 갱신
			local db = ns.db[unitKey]
			if db then
				local growDir = db.growDirection or "DOWN"
				local point = (ns.GROW_TO_POINT or {})[growDir] or "TOP"
				local priKey, priVal, secKey, secVal = ns.GetGrowOffsets(growDir, db.spacingY or 3)
				local size = db.size or { 66, 46 }
				for i = 1, (db.maxGroups or 8) do
					local header = GF.raidHeaders[i]
					if header then
						header:SetAttribute("point", point)
						header:SetAttribute(priKey, priVal)
						header:SetAttribute(secKey, secVal)
						header:SetAttribute("sortDir", db.sortDir or "ASC")
						header:SetAttribute("sortMethod", db.sortBy or "INDEX")
						header:SetAttribute("gf-width", size[1])
						header:SetAttribute("gf-height", size[2])
						header:Hide()
						header:Show()
					end
				end
				-- [FIX] 그룹 간 배치 방향 갱신 (Headers.lua 생성 로직과 동일)
				local groupGrowDir = db.groupGrowDirection
				if not groupGrowDir then
					if growDir == "H_CENTER" or growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER" then
						groupGrowDir = "RIGHT"
					else
						groupGrowDir = "DOWN"
					end
				end
				local gSpacing = db.groupSpacing or 5
				for i = 2, (db.maxGroups or 8) do
					local header = GF.raidHeaders[i]
					local prev = GF.raidHeaders[i - 1]
					if header and prev then
						header:ClearAllPoints()
						if groupGrowDir == "RIGHT" then
							header:SetPoint("TOPLEFT", prev, "TOPRIGHT", gSpacing, 0)
						elseif groupGrowDir == "LEFT" then
							header:SetPoint("TOPRIGHT", prev, "TOPLEFT", -gSpacing, 0)
						elseif groupGrowDir == "DOWN" then
							header:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gSpacing)
						elseif groupGrowDir == "UP" then
							header:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, gSpacing)
						else
							header:SetPoint("TOPLEFT", prev, "TOPRIGHT", gSpacing, 0)
						end
					end
				end
				-- [REFACTOR] 자식 프레임 레이아웃도 갱신
				for _, frame in pairs(GF.allFrames or {}) do
					if frame and frame.isRaidFrame then
						GF:ApplyLayout(frame)
					end
				end
				gfHandled = true
			end
		end
	end

	-- [REFACTOR] GF가 처리했으면 oUF 경로 스킵
	if gfHandled then
		-- H_CENTER/V_CENTER 위치 갱신은 GF용으로도 필요하므로 아래 블록으로 이동
	else
	-- [FIX] 그룹 헤더 속성 런타임 갱신 (reload 불필요) — oUF 경로
	if not InCombatLockdown() then
		if unitKey == "party" then
			local header = ns.headers and ns.headers.party
			if header then
				local db = ns.db.party
				if db then
					-- [FIX] 1차/2차 성장 방향 계산
					local growDir = db.growDirection or "DOWN"
					local colGrowDir = db.columnGrowDirection or "RIGHT"
					local GROW_TO_POINT = ns.GROW_TO_POINT
					local COLUMN_GROW_TO_ANCHOR = ns.COLUMN_GROW_TO_ANCHOR
					local point = GROW_TO_POINT[growDir] or "TOP"
					local colAnchor = COLUMN_GROW_TO_ANCHOR[colGrowDir] or "LEFT"
					local priKey, priVal, secKey, secVal = ns.GetGrowOffsets(growDir, db.spacing or 4)
					local colSpacing = (colGrowDir == "LEFT" or colGrowDir == "UP") and -(db.spacingX or 4) or (db.spacingX or 4)

					header:SetAttribute("point", point)
					header:SetAttribute(priKey, priVal)
					header:SetAttribute(secKey, secVal)
					header:SetAttribute("maxColumns", db.maxColumns or 1)
					header:SetAttribute("unitsPerColumn", db.unitsPerColumn or 5)
					header:SetAttribute("columnSpacing", colSpacing)
					header:SetAttribute("columnAnchorPoint", colAnchor)
					header:SetAttribute("sortDir", db.sortDir or "ASC")
					header:SetAttribute("sortMethod", db.sortBy or "INDEX")
					header:SetAttribute("showPlayer", db.showPlayer or false)

					-- [FIX] groupBy 런타임 갱신
					local groupByAttr = db.groupBy or "GROUP"
					if groupByAttr == "ROLE" then
						header:SetAttribute("groupBy", "ASSIGNEDROLE")
						header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
					elseif groupByAttr == "CLASS" then
						header:SetAttribute("groupBy", "CLASS")
						header:SetAttribute("groupingOrder", "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,DEATHKNIGHT,SHAMAN,MAGE,WARLOCK,MONK,DRUID,DEMONHUNTER,EVOKER")
					else
						header:SetAttribute("groupBy", nil)
						header:SetAttribute("groupingOrder", nil)
					end
					-- [FIX] SecureGroupHeader가 정렬 속성 변경 후 자식 재배치하도록 강제
					header:Hide()
					header:Show()
				end
			end
		elseif unitKey == "raid" then
			local db = ns.db.raid
			if db and ns.headers then
				local growDir = db.growDirection or "DOWN"
				local colGrowDir = db.columnGrowDirection or "RIGHT"
				local GROW_TO_POINT = ns.GROW_TO_POINT
				local COLUMN_GROW_TO_ANCHOR = ns.COLUMN_GROW_TO_ANCHOR
				local point = GROW_TO_POINT[growDir] or "TOP"
				local colAnchor = COLUMN_GROW_TO_ANCHOR[colGrowDir] or "LEFT"
				local priKey, priVal, secKey, secVal = ns.GetGrowOffsets(growDir, db.spacingY or 3)
				local colSpacing = (colGrowDir == "LEFT" or colGrowDir == "UP") and -(db.spacingX or 3) or (db.spacingX or 3)

				for i = 1, (db.maxGroups or 8) do
					local header = ns.headers["raid_group" .. i]
					if header then
						header:SetAttribute("point", point)
						header:SetAttribute(priKey, priVal)
						header:SetAttribute(secKey, secVal)
						header:SetAttribute("columnSpacing", colSpacing)
						header:SetAttribute("columnAnchorPoint", colAnchor)
						header:SetAttribute("sortDir", db.sortDir or "ASC")
						header:SetAttribute("sortMethod", db.sortBy or "INDEX")
						-- [FIX] SecureGroupHeader가 정렬 속성 변경 후 자식 재배치하도록 강제
						header:Hide()
						header:Show()
					end
				end
			end
		end
	end
	end -- [REFACTOR] gfHandled else 블록 닫기
	-- [FIX] 성장 방향 변경 시 헤더 위치 갱신 (H_CENTER/V_CENTER 포함)
	if not InCombatLockdown() and (unitKey == "party" or unitKey == "raid") then
		local db = ns.db[unitKey]
		if db then
			local growDir = db.growDirection or "DOWN"
			local isHCenter = (growDir == "H_CENTER")
			local isVCenter = (growDir == "V_CENTER")
			local headers = {}
			local GF2 = ns.GroupFrames
			if unitKey == "party" then
				-- [REFACTOR] GF 헤더 우선, oUF 폴백
				local h = (GF2 and GF2.partyHeader) or (ns.headers and ns.headers.party)
				if h then headers[1] = h end
			elseif unitKey == "raid" then
				if GF2 and GF2.raidHeaders then
					for i = 1, (db.maxGroups or 8) do
						local h = GF2.raidHeaders[i]
						if h then headers[#headers + 1] = h end
					end
				elseif ns.headers then
					for i = 1, (db.maxGroups or 8) do
						local h = ns.headers["raid_group" .. i]
						if h then headers[#headers + 1] = h end
					end
				end
			end
			local pos = db.position
			-- [FIX] 위치 형식별 안전한 오프셋 추출 (레거시 문자열 형식 방어)
			local posX, posY
			if pos then
				if pos.point then
					posX = tonumber(pos.offsetX) or 0
					posY = tonumber(pos.offsetY) or 0
				elseif type(pos[1]) == "string" then
					posX = tonumber(pos[4]) or 0
					posY = tonumber(pos[5]) or 0
				elseif type(pos[1]) == "number" then
					posX = tonumber(pos[1]) or 0
					posY = tonumber(pos[2]) or 0
				else
					posX, posY = 0, 0
				end
			else
				posX, posY = 0, 0
			end
			for idx, header in ipairs(headers) do
				header:ClearAllPoints()
				if isHCenter then
					-- 가로 중앙: 프레임이 가로로 나열, 저장된 위치 기준으로 가로 중앙 정렬
					if unitKey == "raid" and idx > 1 then
						local prev = headers[idx - 1]
						header:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -(db.groupSpacing or 5))
					else
						-- 가시 자식 수 × 프레임 너비로 총 폭 계산 → 저장 위치 기준 중앙 오프셋
						-- [PERF] select(ci, GetChildren()) O(n²) → 캐시 O(n)
						local numVisible, frameW = 0, 0
						local hChildren = { header:GetChildren() }
						for _, child in ipairs(hChildren) do
							if child and child:IsShown() then
								numVisible = numVisible + 1
								if frameW == 0 then frameW = child:GetWidth() end
							end
						end
						local sp = db.spacing or db.spacingX or 4
						local totalW = numVisible * frameW + math_max(0, numVisible - 1) * sp
						local ap = pos and pos.point or "TOPLEFT"
						local rp = pos and pos.relativePoint or ap
						header:SetPoint(ap, UIParent, rp, posX - totalW / 2, posY)
					end
				elseif isVCenter then
					-- 세로 중앙: 프레임이 세로로 나열, 저장된 위치 기준으로 세로 중앙 정렬
					if unitKey == "raid" and idx > 1 then
						local prev = headers[idx - 1]
						header:SetPoint("TOPLEFT", prev, "TOPRIGHT", db.groupSpacing or 5, 0)
					else
						-- 가시 자식 수 × 프레임 높이로 총 높이 계산 → 저장 위치 기준 중앙 오프셋
						-- [PERF] select(ci, GetChildren()) O(n²) → 캐시 O(n)
						local numVisible, frameH = 0, 0
						local hChildren = { header:GetChildren() }
						for _, child in ipairs(hChildren) do
							if child and child:IsShown() then
								numVisible = numVisible + 1
								if frameH == 0 then frameH = child:GetHeight() end
							end
						end
						local sp = db.spacing or db.spacingY or 4
						local totalH = numVisible * frameH + math_max(0, numVisible - 1) * sp
						local ap = pos and pos.point or "TOPLEFT"
						local rp = pos and pos.relativePoint or ap
						header:SetPoint(ap, UIParent, rp, posX, posY + totalH / 2)
					end
				else
					-- 일반 방향: 저장된 위치로 복원
					if unitKey == "raid" and idx > 1 then
						local prev = headers[idx - 1]
						header:SetPoint("TOPLEFT", prev, "TOPRIGHT", db.groupSpacing or 5, 0)
					else
						local ap = pos and pos.point or "TOPLEFT"
						local rp = pos and pos.relativePoint or ap
						header:SetPoint(ap, UIParent, rp, posX, posY)
					end
				end
			end
		end
	end

	self:RefreshUnit(unitKey)
end

function Update:UpdateCastBar(unitKey)
	local frame = ns.frames[unitKey]
	if frame then
		self:UpdateCastbar(frame, unitKey)
		self:UpdateCastbarPosition(frame, unitKey)
	end
end

function Update:UpdateTexts(unitKey)
	local frame = ns.frames[unitKey]
	if frame then
		self:UpdateCustomText(frame, unitKey)
		self:UpdateText(frame, unitKey)

		if frame.unit and UnitExists(frame.unit) then
			SafeUpdateAllElements(frame, "RefreshFrame")
		end
	elseif unitKey == "party" then
		self:RefreshPartyFrames()
	elseif unitKey == "raid" then
		self:RefreshRaidFrames()
	elseif unitKey == "boss" then
		self:RefreshBossFrames()
	elseif unitKey == "arena" then
		self:RefreshArenaFrames()
	end
end

function Update:UpdateClassBar(unitKey)
	local frame = ns.frames[unitKey]
	if frame then
		self:UpdateClassPower(frame, unitKey)
	end
end

function Update:RefreshAll()
	self:RefreshAllFrames()
	self:RefreshPartyFrames()
	self:RefreshRaidFrames()
	self:RefreshBossFrames()
	self:RefreshArenaFrames()
end

-----------------------------------------------
-- RefreshNumberFormat — 숫자 표시 설정 변경 시 텍스트만 갱신
-- RefreshAll()보다 가볍고, 텍스트 갱신에 집중
-----------------------------------------------

function Update:RefreshNumberFormat()
	-- 1) oUF 개인 프레임: 태그 즉시 재평가
	for unitKey, frame in pairs(ns.frames) do
		if frame then
			ForceRefreshText(frame)
			-- UpdateAllElements는 태그 + 기타 요소 모두 갱신
			if frame.unit and UnitExists(frame.unit) then
				SafeUpdateAllElements(frame, "RefreshFrame")
			end
		end
	end

	-- 2) GroupFrames 파티/레이드: 체력 텍스트 직접 갱신
	local GF = ns.GroupFrames
	if GF and GF.headersInitialized then
		for _, frame in pairs(GF.allFrames or {}) do
			if frame and frame.unit and UnitExists(frame.unit) then
				if GF.UpdateHealthText then
					GF:UpdateHealthText(frame)
				end
			end
		end
	end

	-- 3) 보스/투기장 프레임
	for i = 1, (C.MAX_BOSS_FRAMES or 8) do
		local bFrame = ns.frames["boss" .. i]
		if bFrame then
			ForceRefreshText(bFrame)
			if bFrame.unit and UnitExists(bFrame.unit) then
				SafeUpdateAllElements(bFrame, "RefreshFrame")
			end
		end
	end
	for i = 1, (C.MAX_ARENA_FRAMES or 5) do
		local aFrame = ns.frames["arena" .. i]
		if aFrame then
			ForceRefreshText(aFrame)
			if aFrame.unit and UnitExists(aFrame.unit) then
				SafeUpdateAllElements(aFrame, "RefreshFrame")
			end
		end
	end
end

-----------------------------------------------
-- Lightweight Update Functions
-- Options 슬라이더 드래그 중 사용 (풀 리프레시 불필요)
-----------------------------------------------

function Update:LightweightResize(frame, unitKey)
	if not frame then return end
	local db = ns.db[unitKey]
	if not db then return end

	local width = (db.size and db.size[1]) or 200
	local height = (db.size and db.size[2]) or 40
	frame:SetSize(width, height)

	-- 기력바 높이 계산
	local powerDB = GetWidgetDB(db, "powerBar")
	local powerH = 0
	if powerDB and powerDB.enabled ~= false and frame.Power then
		powerH = (powerDB.size and powerDB.size.height) or C.POWER_HEIGHT
	end

	if frame.Health then
		frame.Health:ClearAllPoints()
		frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		frame.Health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, powerH)
	end
end

function Update:LightweightPowerHeight(frame, unitKey)
	if not frame or not frame.Power then return end
	local db = ns.db[unitKey]
	if not db then return end

	local pDB = GetWidgetDB(db, "powerBar")
	if not pDB or pDB.enabled == false then return end

	local powerH = (pDB.size and pDB.size.height) or C.POWER_HEIGHT
	frame.Power:SetHeight(powerH)

	-- 체력바 하단 재조정
	if frame.Health then
		frame.Health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, powerH)
	end
end

function Update:LightweightFontSize(frame, unitKey, widgetKey)
	if not frame then return end
	local db = ns.db[unitKey]
	if not db then return end

	local wDB = GetWidgetDB(db, widgetKey)
	if not wDB or not wDB.font then return end

	local textObj
	if widgetKey == "nameText" then
		textObj = frame.NameText
	elseif widgetKey == "healthText" then
		textObj = frame.HealthText
	end

	if textObj then
		local _, defaultSize, defaultFlags = GetFont()
		local fSize = wDB.font.size or defaultSize
		local fOutline = wDB.font.outline or defaultFlags
		local fStyle = wDB.font.style or C.DEFAULT_FONT
		textObj:SetFont(fStyle, fSize, fOutline)
	end
end

function Update:LightweightCastbarSize(frame, unitKey)
	if not frame or not frame.Castbar then return end
	local db = ns.db[unitKey]
	if not db then return end

	local cbDB = GetWidgetDB(db, "castBar")
	if not cbDB then return end

	local cbWidth = cbDB.size and cbDB.size.width
	local cbHeight = cbDB.size and cbDB.size.height

	if cbWidth then frame.Castbar:SetWidth(cbWidth) end
	if cbHeight then
		frame.Castbar:SetHeight(cbHeight)
		if frame.Castbar.Icon then
			frame.Castbar.Icon:SetSize(cbHeight, cbHeight)
		end
	end
end

function Update:LightweightAuraSize(frame, unitKey, auraType)
	if not frame then return end
	local db = ns.db[unitKey]
	if not db then return end

	local widgetName = (auraType == "debuffs") and "debuffs" or "buffs"
	local aDB = GetWidgetDB(db, widgetName)
	if not aDB then return end

	local element = (auraType == "debuffs") and frame.Debuffs or frame.Buffs
	if not element then return end

	local iconSize = (aDB.size and aDB.size.width) or 24
	local num = aDB.maxIcons or 10
	local hSpacing = (aDB.spacing and aDB.spacing.horizontal) or 2

	element.size = iconSize
	element:SetSize(iconSize * num + hSpacing * (num - 1), iconSize)
end

function Update:LightweightClassBarHeight(frame, unitKey)
	if not frame or not frame.ClassPower then return end
	local db = ns.db[unitKey]
	if not db then return end

	local cpDB = GetWidgetDB(db, "classBar")
	if not cpDB or cpDB.enabled == false then return end

	local cpHeight = (cpDB.size and cpDB.size.height) or 4
	for i = 1, #frame.ClassPower do
		frame.ClassPower[i]:SetHeight(cpHeight)
	end
end

-----------------------------------------------
-- [REFACTOR] Element Enable/Disable Helper
-- oUF 제거 후 직접 show/hide + ForceUpdate 호출
-----------------------------------------------

function Update:SetElementEnabled(frame, elementName, enabled)
	if not frame then return end
	if enabled then
		if frame.EnableElement then
			frame:EnableElement(elementName)
		else
			local el = frame[elementName]
			if el and el.Show then el:Show() end
			SafeForceUpdate(el, function() StandaloneRefresh(frame, elementName) end)
		end
	else
		-- [FIX] oUF DisableElement를 호출하더라도, 텍스처/프레임이 자동으로 숨겨지지 않을 수 있으므로 명시적 Hide 호출
		if frame.DisableElement then
			frame:DisableElement(elementName)
		end
		
		local el = frame[elementName]
		if el and el.Hide then el:Hide() end
	end
end

-----------------------------------------------
-- Appearance System (중앙화된 시각 상태 관리)
-- 우선순위: Dead > Offline > Normal -- [12.0.1]
-- OOR은 oUF Range element가 outsideAlpha로 처리
-----------------------------------------------

function Update:UpdateAppearance(frame, unit)
	if not frame or not frame.Health then return end
	unit = unit or frame.unit
	if not unit then return end

	local appearance = ns.db.appearance or {}
	local health = frame.Health

	-- Threat override가 활성화된 경우 스킵
	if health._threatOverride then return end

	-- Priority 1: Dead
	if UnitExists(unit) and UnitIsDeadOrGhost(unit) then
		local alpha = appearance.deadAlpha or C.DEAD_ALPHA
		frame:SetAlpha(alpha)
		if appearance.deadDesaturate then
			health:SetStatusBarColor(0.35, 0.35, 0.35)
			if health.bg then
				health.bg:SetVertexColor(0.1, 0.1, 0.1)
			end
		end
		return
	end

	-- Priority 2: Offline
	if UnitExists(unit) and not UnitIsConnected(unit) then
		local alpha = appearance.offlineAlpha or C.OFFLINE_ALPHA
		frame:SetAlpha(alpha)
		-- [UF-OPTIONS] 오프라인 전용 색상 적용
		local offlineColor = ns.Colors and ns.Colors.unitFrames and ns.Colors.unitFrames.offlineColor
		if offlineColor then
			health:SetStatusBarColor(offlineColor[1], offlineColor[2], offlineColor[3])
			if health.bg then
				health.bg:SetVertexColor(offlineColor[1] * 0.3, offlineColor[2] * 0.3, offlineColor[3] * 0.3)
			end
		elseif appearance.offlineDesaturate then
			health:SetStatusBarColor(0.5, 0.5, 0.5)
			if health.bg then
				health.bg:SetVertexColor(0.15, 0.15, 0.15)
			end
		end
		return
	end

	-- [12.0.1] Priority 3: Normal → 알파 복원 (OOR은 oUF Range element가 처리)
	frame:SetAlpha(1)
end

-----------------------------------------------
-- 편집모드 미리보기 (Cell/DandersFrames 스타일 애니메이션)
-----------------------------------------------

local TEST_CLASSES = {
	"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
	"DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
	"DRUID", "DEMONHUNTER", "EVOKER",
}

local TEST_NAMES = {
	"엘룬빛", "그롬마쉬", "아서스", "실바나스", "볼진",
	"제이나", "스랄", "안두인", "일리단", "티란데",
	"켈투자드", "카드가", "메디브", "렉사르", "발리라",
	"마이에브", "가로쉬", "로테브", "살게라스", "아즈샤라",
	"칼렉고스", "알렉스트라자", "이세라", "노즈도르무", "말리고스",
	"렌서르", "투랄리온", "알레리아", "더카탈", "프라이아",
}

local testFrames = {}
local simDriver = nil    -- OnUpdate 드라이버 프레임
local simActive = false
local simElapsed = 0
local simContainers = {}  -- { party = container, raid = container }
ns.simContainers = simContainers  -- Mover.lua에서 접근 가능하도록

-- 시뮬레이션 상수
local SIM_TICK = 0.03          -- ~30fps 업데이트
local SIM_LERP_SPEED = 3.0    -- 체력바 보간 속도 (초당 값 이동량 배율)
local SIM_EVENT_MIN = 0.8     -- 이벤트 최소 간격(초)
local SIM_EVENT_MAX = 2.5     -- 이벤트 최대 간격(초)
local SIM_DEATH_CHANCE = 0.04 -- 이벤트 시 사망 확률
local SIM_REZ_DELAY = 4.0     -- 사망 후 부활까지 대기(초)
local SIM_LOW_HP = 35         -- 저체력 기준 %

local math_abs = math.abs
local math_min = math.min

local simErrorCount = 0

-----------------------------------------------
-- 그룹 컨테이너 생성 (파티/레이드 통합 이동용)
-----------------------------------------------
local function CreateGroupContainer(name, parent)
	local existing = _G[name]
	if existing then
		existing:SetParent(parent or UIParent)
		existing:Show()
		return existing
	end

	local container = CreateFrame("Frame", name, parent or UIParent)
	container:SetFrameStrata("TOOLTIP")
	container:SetFrameLevel(499)
	-- [EDITMODE-FIX] 마우스 비활성화: Mover를 통해서만 이동 (클릭 관통)
	container:EnableMouse(false)
	container:SetClampedToScreen(true)

	return container
end

-----------------------------------------------
-- Config-Driven 프리뷰 프레임 생성
-- Layout.lua와 동일한 시각적 구조 (Cell isPreview 패턴)
-----------------------------------------------

local function CreatePreviewFrame(name, parent)
	local f = _G[name]
	if f then
		f:SetParent(parent or UIParent)
		f:Show()
		return f
	end

	f = CreateFrame("Frame", name, parent or UIParent)
	f:SetFrameStrata("TOOLTIP")
	f:SetFrameLevel(500)
	f.isPreview = true

	return f
end

-- Layout.lua와 동일한 Backdrop + Health + Power + Texts 구조 적용
local function ApplyPreviewStyle(f, unitKey, width, height)
	local texture = GetTexture()
	local font, fontSize, fontFlags = GetFont()
	local borderSize = F:ScalePixel(C.BORDER_SIZE)
	local inset = 0
	local unitDB = ns.db[unitKey] or {}

	f._previewUnitKey = unitKey -- [12.0.1] RefreshPreview에서 유닛 식별용
	f:SetSize(width, height)

	-- [FIX] DB에서 배경/테두리 색상 읽기 (Layout.lua CreateFrameBackdrop 패턴과 동일)
	local borderDB = unitDB.border or {}
	local bgDB = unitDB.background or {}
	local bgColor = bgDB.color
	if type(bgColor) ~= "table" then bgColor = C.FRAME_BG end
	local borderColor = borderDB.color
	if type(borderColor) ~= "table" then borderColor = C.BORDER_COLOR end

	-- Backdrop (수동 텍스처 방식 - Layout.lua CreateFrameBackdrop 패턴)
	if not f.Backdrop then
		local bd = CreateFrame("Frame", nil, f)
		bd:SetPoint("TOPLEFT", -borderSize, borderSize)
		bd:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
		bd:SetFrameLevel(math_max(0, f:GetFrameLevel() - 1))

		bd.bg = bd:CreateTexture(nil, "BACKGROUND")
		bd.bg:SetPoint("TOPLEFT", borderSize, -borderSize)
		bd.bg:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

		local top = bd:CreateTexture(nil, "BORDER")
		top:SetPoint("TOPLEFT", 0, 0)
		top:SetPoint("TOPRIGHT", 0, 0)
		top:SetHeight(borderSize)
		local bottom = bd:CreateTexture(nil, "BORDER")
		bottom:SetPoint("BOTTOMLEFT", 0, 0)
		bottom:SetPoint("BOTTOMRIGHT", 0, 0)
		bottom:SetHeight(borderSize)
		local left = bd:CreateTexture(nil, "BORDER")
		left:SetPoint("TOPLEFT", 0, 0)
		left:SetPoint("BOTTOMLEFT", 0, 0)
		left:SetWidth(borderSize)
		local right = bd:CreateTexture(nil, "BORDER")
		right:SetPoint("TOPRIGHT", 0, 0)
		right:SetPoint("BOTTOMRIGHT", 0, 0)
		right:SetWidth(borderSize)

		bd.borderTextures = { top, bottom, left, right }
		f.Backdrop = bd
	end
	-- [FIX] 매 갱신마다 DB 색상 반영 (상수 대신 DB 우선)
	f.Backdrop.bg:SetColorTexture(bgColor[1] or 0.08, bgColor[2] or 0.08, bgColor[3] or 0.08, bgColor[4] or 0.85)
	for _, tex in ipairs(f.Backdrop.borderTextures) do
		tex:SetColorTexture(borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1)
	end

	-- Power bar 높이 계산 (Layout.lua와 동일)
	local powerDB = GetWidgetDB(unitDB, "powerBar")
	local powerH = 0
	if powerDB and powerDB.enabled ~= false then
		powerH = (powerDB.size and powerDB.size.height) or C.POWER_HEIGHT
	end

	-- Health bar (Layout.lua CreateHealthBar 패턴)
	if not f.Health then
		f.Health = CreateFrame("StatusBar", nil, f)
		f.Health.bg = f.Health:CreateTexture(nil, "BACKGROUND")
		f.Health.bg:SetAllPoints()
		f.Health.bg.multiplier = C.HEALTH_BG_MULTIPLIER
	end
	f.Health:SetStatusBarTexture(texture)
	f.Health:SetMinMaxValues(0, 100)
	f.Health:ClearAllPoints()
	f.Health:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
	f.Health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset + powerH)
	f.Health.bg:SetTexture(texture)

	-- Heal prediction overlay
	if not f.HealPrediction then
		f.HealPrediction = f.Health:CreateTexture(nil, "ARTWORK", nil, 1)
		f.HealPrediction:SetVertexColor(0.2, 0.8, 0.2, 0.4)
		f.HealPrediction:Hide()
	end
	f.HealPrediction:SetTexture(texture)

	-- Power bar (Layout.lua CreatePowerBar 패턴)
	if powerH > 0 then
		if not f.Power then
			f.Power = CreateFrame("StatusBar", nil, f)
			f.Power.bg = f.Power:CreateTexture(nil, "BACKGROUND")
			f.Power.bg:SetAllPoints()
			f.Power.bg.multiplier = 0.3
		end
		f.Power:SetStatusBarTexture(texture)
		f.Power:SetStatusBarColor(0.2, 0.2, 0.6) -- [FIX] 초기 색상 (핑크바 방지)
		f.Power:SetMinMaxValues(0, 100)
		f.Power:ClearAllPoints()
		f.Power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
		f.Power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
		f.Power:SetHeight(powerH)
		f.Power.bg:SetTexture(texture)
		f.Power.bg:SetVertexColor(0.06, 0.06, 0.06) -- [FIX] 초기 bg 색상 (기본 white 방지)
		f.Power:Show()
	elseif f.Power then
		f.Power:Hide()
	end

	-- [FIX] Name text: DB 설정 반영 (position/font/color)
	local nameDB = GetWidgetDB(unitDB, "nameText")
	if not f.NameText then
		local textParent = f.TextOverlay or f.Health
		f.NameText = textParent:CreateFontString(nil, "OVERLAY")
		f.NameText:SetShadowColor(0, 0, 0, 1)
		f.NameText:SetShadowOffset(1, -1)
	end
	-- 폰트: DB 우선
	local nFont = nameDB and nameDB.font
	local nSize = (nFont and nFont.size) or fontSize
	local nOutline = (nFont and nFont.outline) or fontFlags
	local nStyle = (nFont and nFont.style) or font
	SafeSetFont(f.NameText, nStyle, nSize, nOutline)
	if nFont and nFont.shadow == false then
		f.NameText:SetShadowOffset(0, 0)
	else
		f.NameText:SetShadowColor(0, 0, 0, 1)
		f.NameText:SetShadowOffset(1, -1)
	end
	-- 앵커: DB position 우선, 없으면 유닛별 하드코딩 폴백
	f.NameText:ClearAllPoints()
	local nPos = nameDB and nameDB.position
	if nPos then
		local anchor = f.Health or f
		f.NameText:SetPoint(nPos.point or "LEFT", anchor, nPos.relativePoint or "LEFT", nPos.offsetX or 0, nPos.offsetY or 0)
		if nPos.leftPoint and f.Health then
			f.NameText:SetPoint(nPos.leftPoint, f.Health, nPos.leftRelPoint or nPos.leftPoint, nPos.leftOffsetX or 0, nPos.leftOffsetY or 0)
		end
		if nPos.rightPoint and f.Health then
			f.NameText:SetPoint(nPos.rightPoint, f.Health, nPos.rightRelPoint or nPos.rightPoint, nPos.rightOffsetX or 0, nPos.rightOffsetY or 0)
		end
	elseif unitKey == "raid" then
		f.NameText:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
	elseif unitKey == "party" then
		f.NameText:SetPoint("LEFT", f.Health, "LEFT", 4, 0)
	else
		f.NameText:SetPoint("LEFT", f.Health, "LEFT", 4, 0)
	end
	f.NameText:SetJustifyH((nFont and nFont.justify) or (unitKey == "raid" and "CENTER" or "LEFT"))
	-- width
	local nWidth = nameDB and nameDB.width
	if nWidth and nWidth.type == "length" and nWidth.value and nWidth.value > 0 then
		f.NameText:SetWidth(nWidth.value)
	else
		-- unlimited / anchor / percentage 모두 제약 없음
		f.NameText:SetWidth(0)
	end

	-- [FIX] Health text: DB 설정 반영
	local healthDB = GetWidgetDB(unitDB, "healthText")
	if not f.HealthText then
		local textParent2 = f.TextOverlay or f.Health
		f.HealthText = textParent2:CreateFontString(nil, "OVERLAY")
		f.HealthText:SetShadowColor(0, 0, 0, 1)
		f.HealthText:SetShadowOffset(1, -1)
	end
	local hFont = healthDB and healthDB.font
	local hSize = (hFont and hFont.size) or fontSize
	local hOutline = (hFont and hFont.outline) or fontFlags
	local hStyle = (hFont and hFont.style) or font
	SafeSetFont(f.HealthText, hStyle, hSize, hOutline)
	f.HealthText:ClearAllPoints()
	local hPos = healthDB and healthDB.position
	if hPos then
		local anchor = f.Health or f
		f.HealthText:SetPoint(hPos.point or "RIGHT", anchor, hPos.relativePoint or "CENTER", hPos.offsetX or 0, hPos.offsetY or 0)
	else
		f.HealthText:SetPoint("RIGHT", f.Health, "RIGHT", -4, 0)
	end
	f.HealthText:SetJustifyH((hFont and hFont.justify) or "RIGHT")

	-- Status text (Dead/AFK)
	if not f.StatusText then
		local textParent3 = f.TextOverlay or f.Health
		f.StatusText = textParent3:CreateFontString(nil, "OVERLAY")
		f.StatusText:SetShadowColor(0, 0, 0, 1)
		f.StatusText:SetShadowOffset(1, -1)
		f.StatusText:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
		f.StatusText:Hide()
	end
	SafeSetFont(f.StatusText, font, fontSize + 1, fontFlags)

	-- [FIX] PowerText: DB 설정 반영
	local ptDB = GetWidgetDB(unitDB, "powerText")
	if ptDB and ptDB.enabled ~= false then
		if not f.PowerText then
			local textParentPT = f.TextOverlay or f.Health
			f.PowerText = textParentPT:CreateFontString(nil, "OVERLAY")
			f.PowerText:SetShadowColor(0, 0, 0, 1)
			f.PowerText:SetShadowOffset(1, -1)
		end
		local ptFont = ptDB.font
		local ptSize = (ptFont and ptFont.size) or fontSize
		local ptOutline = (ptFont and ptFont.outline) or fontFlags
		local ptStyle = (ptFont and ptFont.style) or font
		SafeSetFont(f.PowerText, ptStyle, ptSize, ptOutline)
		f.PowerText:ClearAllPoints()
		local ptPos = ptDB.position
		if ptPos then
			local anchor = f.Health or f
			f.PowerText:SetPoint(ptPos.point or "RIGHT", anchor, ptPos.relativePoint or "RIGHT", ptPos.offsetX or 0, ptPos.offsetY or 0)
		elseif f.Power and f.Power:IsShown() then
			f.PowerText:SetPoint("CENTER", f.Power, "CENTER", 0, 0)
		else
			f.PowerText:SetPoint("RIGHT", f.Health, "RIGHT", -4, -8)
		end
		if ptFont and ptFont.rgb then
			f.PowerText:SetTextColor(ptFont.rgb[1] or 1, ptFont.rgb[2] or 1, ptFont.rgb[3] or 1)
		end
		f.PowerText:Show()
	elseif f.PowerText then
		f.PowerText:Hide()
	end

	-- [FIX] 버프 아이콘 프리뷰: DB 설정 반영 (위치/크기/방향/간격)
	local buffDB = GetWidgetDB(unitDB, "buffs")
	if buffDB and buffDB.enabled ~= false then
		if not f._buffIcons then f._buffIcons = {} end
		local iconSize = (buffDB.size and buffDB.size.width) or 24
		local hSpacing = (buffDB.spacing and buffDB.spacing.horizontal) or 2
		local vSpacing = (buffDB.spacing and buffDB.spacing.vertical) or 2
		local numPreview = math_min(buffDB.maxIcons or 10, 5) -- 프리뷰는 최대 5개
		local growDir = buffDB.growDirection or "RIGHT"
		local colGrowDir = buffDB.columnGrowDirection or "UP"

		-- 앵커 컨테이너
		if not f._buffContainer then
			f._buffContainer = CreateFrame("Frame", nil, f)
		end
		f._buffContainer:ClearAllPoints()
		if buffDB.position then
			local pos = buffDB.position
			f._buffContainer:SetPoint(pos.point or "BOTTOMLEFT", f, pos.relativePoint or "TOPLEFT", pos.offsetX or 0, pos.offsetY or 2)
		else
			f._buffContainer:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 5)
		end
		f._buffContainer:SetSize(iconSize * numPreview + hSpacing * (numPreview - 1), iconSize)
		f._buffContainer:Show()

		-- 아이콘 생성/갱신
		for i = 1, numPreview do
			local icon = f._buffIcons[i]
			if not icon then
				icon = CreateFrame("Frame", nil, f._buffContainer)
				-- 테두리 (BACKGROUND: 아이콘 뒤, 프레임 범위 밖으로 확장)
				icon.border = icon:CreateTexture(nil, "BACKGROUND")
				icon.border:SetPoint("TOPLEFT", -1, 1)
				icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
				icon.border:SetColorTexture(0, 0, 0, 1)
				-- 아이콘 텍스처 (ARTWORK: 테두리 위)
				icon.tex = icon:CreateTexture(nil, "ARTWORK")
				icon.tex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
				icon.tex:SetAllPoints()
				f._buffIcons[i] = icon
			end
			icon:SetSize(iconSize, iconSize)
			icon:ClearAllPoints()
			-- 방향별 배치
			local offset = (i - 1) * (iconSize + hSpacing)
			if growDir == "RIGHT" then
				icon:SetPoint("LEFT", f._buffContainer, "LEFT", offset, 0)
			elseif growDir == "LEFT" then
				icon:SetPoint("RIGHT", f._buffContainer, "RIGHT", -offset, 0)
			elseif growDir == "DOWN" then
				icon:SetPoint("TOP", f._buffContainer, "TOP", 0, -offset)
			else -- UP
				icon:SetPoint("BOTTOM", f._buffContainer, "BOTTOM", 0, offset)
			end
			-- 더미 텍스처 (랜덤 스펠 아이콘 시뮬)
			local dummyIcons = { 136243, 135987, 136048, 136105, 136075 }
			icon.tex:SetTexture(dummyIcons[i] or 136243)
			icon:Show()
		end
		-- 초과 아이콘 숨기기
		for i = numPreview + 1, #f._buffIcons do
			f._buffIcons[i]:Hide()
		end
	elseif f._buffContainer then
		f._buffContainer:Hide()
	end

	-- [FIX] 디버프 아이콘 프리뷰: DB 설정 반영
	local debuffDB = GetWidgetDB(unitDB, "debuffs")
	if debuffDB and debuffDB.enabled ~= false then
		if not f._debuffIcons then f._debuffIcons = {} end
		local iconSize = (debuffDB.size and debuffDB.size.width) or 28
		local hSpacing = (debuffDB.spacing and debuffDB.spacing.horizontal) or 2
		local numPreview = math_min(debuffDB.maxIcons or 8, 3) -- 디버프 프리뷰 최대 3개
		local growDir = debuffDB.growDirection or "LEFT"

		if not f._debuffContainer then
			f._debuffContainer = CreateFrame("Frame", nil, f)
		end
		f._debuffContainer:ClearAllPoints()
		if debuffDB.position then
			local pos = debuffDB.position
			f._debuffContainer:SetPoint(pos.point or "BOTTOMRIGHT", f, pos.relativePoint or "TOPRIGHT", pos.offsetX or 0, pos.offsetY or 2)
		elseif unitKey == "raid" then
			f._debuffContainer:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
		elseif f._buffContainer and f._buffContainer:IsShown() then
			f._debuffContainer:SetPoint("LEFT", f._buffContainer, "RIGHT", 8, 0)
		else
			f._debuffContainer:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 5)
		end
		f._debuffContainer:SetSize(iconSize * numPreview + hSpacing * (numPreview - 1), iconSize)
		f._debuffContainer:Show()

		for i = 1, numPreview do
			local icon = f._debuffIcons[i]
			if not icon then
				icon = CreateFrame("Frame", nil, f._debuffContainer)
				icon.border = icon:CreateTexture(nil, "BACKGROUND")
				icon.border:SetPoint("TOPLEFT", -1, 1)
				icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
				icon.tex = icon:CreateTexture(nil, "ARTWORK")
				icon.tex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
				icon.tex:SetAllPoints()
				f._debuffIcons[i] = icon
			end
			icon:SetSize(iconSize, iconSize)
			icon:ClearAllPoints()
			local offset = (i - 1) * (iconSize + hSpacing)
			if growDir == "LEFT" then
				icon:SetPoint("RIGHT", f._debuffContainer, "RIGHT", -offset, 0)
			elseif growDir == "RIGHT" then
				icon:SetPoint("LEFT", f._debuffContainer, "LEFT", offset, 0)
			elseif growDir == "DOWN" then
				icon:SetPoint("TOP", f._debuffContainer, "TOP", 0, -offset)
			else
				icon:SetPoint("BOTTOM", f._debuffContainer, "BOTTOM", 0, offset)
			end
			-- 디버프 색상 테두리
			local debuffColors = { {0.8,0.0,0.0}, {0.6,0.0,1.0}, {0.6,0.4,0.0} }
			local dc = debuffColors[i] or debuffColors[1]
			icon.border:SetColorTexture(dc[1], dc[2], dc[3], 1)
			local dummyDebuffs = { 135813, 135994, 136118 }
			icon.tex:SetTexture(dummyDebuffs[i] or 135813)
			icon:Show()
		end
		for i = numPreview + 1, #f._debuffIcons do
			f._debuffIcons[i]:Hide()
		end
	elseif f._debuffContainer then
		f._debuffContainer:Hide()
	end

	-- [FIX] 캐스트바 프리뷰: DB 설정 반영 (위치/크기)
	local castBarDB = GetWidgetDB(unitDB, "castBar")
	if castBarDB and castBarDB.enabled ~= false and unitKey ~= "party" and unitKey ~= "raid" then
		if not f.CastBar then
			f.CastBar = CreateFrame("StatusBar", nil, f)
			f.CastBar.bg = f.CastBar:CreateTexture(nil, "BACKGROUND")
			f.CastBar.bg:SetAllPoints()
			f.CastBar.Text = f.CastBar:CreateFontString(nil, "OVERLAY")
			f.CastBar.Timer = f.CastBar:CreateFontString(nil, "OVERLAY")
		end
		f.CastBar:SetStatusBarTexture(texture)
		-- [FIX] 글로벌 ns.Colors.castBar 우선 적용
		local initColor = (ns.Colors and ns.Colors.castBar and ns.Colors.castBar.interruptible) or (castBarDB.colors and castBarDB.colors.interruptible) or C.CASTBAR_COLOR or { 1.0, 0.7, 0.0 }
		f.CastBar:SetStatusBarColor(unpack(initColor))
		f.CastBar:SetMinMaxValues(0, 100)
		f.CastBar:SetValue(45) -- 시뮬: 45%
		f.CastBar.bg:SetTexture(texture)
		f.CastBar.bg:SetVertexColor(0.06, 0.06, 0.06)

		local cbH = (castBarDB.size and castBarDB.size.height) or 20
		f.CastBar:ClearAllPoints()
		if not castBarDB.anchorToParent and castBarDB.detachedPosition then
			local pos = castBarDB.detachedPosition
			local cbW = (castBarDB.size and castBarDB.size.width) or width
			f.CastBar:SetSize(cbW, cbH)
			f.CastBar:SetPoint(pos.point or "TOP", f, pos.relativePoint or "BOTTOM", pos.offsetX or 0, pos.offsetY or -4)
		else
			f.CastBar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
			f.CastBar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
			f.CastBar:SetHeight(cbH)
		end
		SafeSetFont(f.CastBar.Text, font, fontSize - 1, fontFlags)
		f.CastBar.Text:SetPoint("LEFT", f.CastBar, "LEFT", 4, 0)
		f.CastBar.Text:SetText("시뮬 시전")
		SafeSetFont(f.CastBar.Timer, font, fontSize - 1, fontFlags)
		f.CastBar.Timer:SetPoint("RIGHT", f.CastBar, "RIGHT", -4, 0)
		f.CastBar.Timer:SetText("1.5s")
		f.CastBar:Show()
	elseif f.CastBar then
		f.CastBar:Hide()
	end

	-- [FIX] 역할 아이콘 프리뷰 (파티/레이드 전용)
	local roleIconDB = GetWidgetDB(unitDB, "groupRoleIndicator")
	if (unitKey == "party" or unitKey == "raid") and roleIconDB and roleIconDB.enabled ~= false then
		if not f.RoleIcon then
			f.RoleIcon = f:CreateTexture(nil, "OVERLAY")
		end
		local riSize = (roleIconDB.size and roleIconDB.size.width) or 14
		f.RoleIcon:SetSize(riSize, riSize)
		f.RoleIcon:ClearAllPoints()
		if roleIconDB.position then
			local pos = roleIconDB.position
			f.RoleIcon:SetPoint(pos.point or "TOPLEFT", f, pos.relativePoint or "TOPLEFT", pos.offsetX or 0, pos.offsetY or 0)
		else
			f.RoleIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
		end
		-- 더미 힐러 아이콘
		f.RoleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
		f.RoleIcon:SetTexCoord(0.3125, 0.609375, 0.34375, 0.640625) -- HEALER
		f.RoleIcon:Show()
	elseif f.RoleIcon then
		f.RoleIcon:Hide()
	end

	-- [FIX] 레이드 타겟 아이콘 프리뷰
	local rtiDB = GetWidgetDB(unitDB, "raidTargetIndicator")
	if rtiDB and rtiDB.enabled ~= false then
		if not f.RaidTargetIcon then
			f.RaidTargetIcon = f:CreateTexture(nil, "OVERLAY")
		end
		local rtiSize = (rtiDB.size and rtiDB.size.width) or 16
		f.RaidTargetIcon:SetSize(rtiSize, rtiSize)
		f.RaidTargetIcon:ClearAllPoints()
		if rtiDB.position then
			local pos = rtiDB.position
			f.RaidTargetIcon:SetPoint(pos.point or "CENTER", f, pos.relativePoint or "TOP", pos.offsetX or 0, pos.offsetY or 0)
		else
			f.RaidTargetIcon:SetPoint("CENTER", f, "TOP", 0, 0)
		end
		f.RaidTargetIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		f.RaidTargetIcon:SetTexCoord(0, 0.25, 0, 0.25) -- 해골
		f.RaidTargetIcon:Hide() -- 기본 숨김, 시뮬에서 일부만 표시
	end

	return f
end

-----------------------------------------------
-- 시뮬레이션 상태 초기화
-----------------------------------------------
local function InitSimState(frame, index, isRaid)
	local classIndex = ((index - 1) % #TEST_CLASSES) + 1
	local class = TEST_CLASSES[classIndex]
	local color = RAID_CLASS_COLORS[class] or { r = 1, g = 1, b = 1 }
	local nameIdx = ((index - 1) % #TEST_NAMES) + 1

	-- 초기에 현재HP와 목표HP 차이를 크게 → 바로 보간 애니메이션 시작
	local initCurrent = 30 + math_random(40)   -- 30~70
	local initTarget = 60 + math_random(40)    -- 60~100 (항상 current보다 높은 경향)

	-- [FIX] DB에서 colorType 읽기 (편집모드 진입 시 기존 설정 반영)
	local unitKey = frame._previewUnitKey
	local unitDB = unitKey and ns.db[unitKey] or {}

	frame._sim = {
		class = class,
		color = { r = color.r, g = color.g, b = color.b },
		currentHP = initCurrent,
		targetHP = initTarget,
		currentPower = 50 + math_random(50),
		targetPower = 50 + math_random(50),
		isDead = false,
		deathTimer = 0,
		nextEventTime = 0.3 + math_random() * 1.0, -- 첫 이벤트 빠르게
		isHealing = false,
		healAmount = 0,
		healTimer = 0,
		name = isRaid and TEST_NAMES[nameIdx] or ("파티원" .. index),
		isRaid = isRaid,
		-- [FIX] DB colorType 동기화 → UpdateFrameVisual이 올바른 색상 사용
		healthBarColorType = unitDB.healthBarColorType,
		healthBarColor = unitDB.healthBarColor,
		healthLossColorType = unitDB.healthLossColorType,
		healthLossColor = unitDB.healthLossColor,
	}

	-- 초기 비주얼 적용 — [FIX] healthBarColorType 반영
	if frame.Health then
		frame.Health:SetMinMaxValues(0, 100)
		frame.Health:SetValue(frame._sim.currentHP)
		local colorType = frame._sim.healthBarColorType
		if colorType == "custom" and frame._sim.healthBarColor then
			local hc = frame._sim.healthBarColor
			frame.Health:SetStatusBarColor(hc[1] or 0.2, hc[2] or 0.2, hc[3] or 0.2, hc[4] or 1)
		elseif colorType == "smooth" then
			local pct = frame._sim.currentHP / 100
			frame.Health:SetStatusBarColor(1 - pct, pct, 0)
		else
			frame.Health:SetStatusBarColor(color.r, color.g, color.b)
		end
		if frame.Health.bg then
			local lossType = frame._sim.healthLossColorType
			if lossType == "custom" and frame._sim.healthLossColor then
				local lc = frame._sim.healthLossColor
				frame.Health.bg:SetVertexColor(lc[1] or 0.5, lc[2] or 0.1, lc[3] or 0.1, lc[4] or 1)
			else
				local mu = frame.Health.bg.multiplier or 0.3
				frame.Health.bg:SetVertexColor(color.r * mu, color.g * mu, color.b * mu)
			end
		end
	end

	if frame.Power and frame.Power:IsShown() then
		frame.Power:SetMinMaxValues(0, 100)
		frame.Power:SetValue(frame._sim.currentPower)
		frame.Power:SetStatusBarColor(0.31, 0.45, 0.63) -- 마나 색상
		if frame.Power.bg then
			frame.Power.bg:SetVertexColor(0.31 * 0.3, 0.45 * 0.3, 0.63 * 0.3)
		end
	end

	if frame.NameText then
		frame.NameText:SetText(frame._sim.name)
		frame.NameText:SetTextColor(color.r, color.g, color.b)
	end

	if frame.HealthText then
		frame.HealthText:SetText(math_floor(frame._sim.currentHP) .. "%")
		frame.HealthText:Show()
	end

	if frame.StatusText then
		frame.StatusText:Hide()
	end

	if frame.HealPrediction then
		frame.HealPrediction:Hide()
	end

	-- [FIX] PowerText 초기값
	if frame.PowerText and frame.PowerText:IsShown() then
		frame.PowerText:SetText(math_floor(frame._sim.currentPower) .. "%")
	end

	-- [FIX] 역할 아이콘: 랜덤 역할 배정
	if frame.RoleIcon then
		local roles = { "TANK", "HEALER", "DAMAGER" }
		local role = roles[((index - 1) % 3) + 1]
		if role == "TANK" then
			frame.RoleIcon:SetTexCoord(0, 0.296875, 0.34375, 0.640625)
		elseif role == "HEALER" then
			frame.RoleIcon:SetTexCoord(0.3125, 0.609375, 0.34375, 0.640625)
		else
			frame.RoleIcon:SetTexCoord(0.3125, 0.609375, 0, 0.296875)
		end
		frame.RoleIcon:Show()
	end

	-- [FIX] 레이드 타겟 아이콘: 일부만 표시
	if frame.RaidTargetIcon then
		if index == 1 or index == 3 then
			frame.RaidTargetIcon:Show()
		else
			frame.RaidTargetIcon:Hide()
		end
	end

	frame:SetAlpha(1)
end

-----------------------------------------------
-- 시뮬레이션 이벤트 처리 (한 프레임에 대해)
-----------------------------------------------
local function ProcessSimEvent(frame)
	local sim = frame._sim
	if not sim or sim.isDead then return end

	local roll = math_random()

	-- 사망 이벤트
	if roll < SIM_DEATH_CHANCE then
		sim.targetHP = 0
		sim.isDead = true
		sim.deathTimer = SIM_REZ_DELAY + math_random() * 2
		return
	end

	-- 대미지 또는 힐 이벤트
	if roll < 0.55 then
		-- 대미지: 5~40% 피해
		local dmg = 5 + math_random(35)
		sim.targetHP = math_max(1, sim.targetHP - dmg)
		-- 큰 대미지는 추가 긴장감
		if sim.targetHP < SIM_LOW_HP and math_random() < 0.3 then
			sim.targetHP = math_max(1, sim.targetHP - math_random(10))
		end
	else
		-- 힐: 10~50% 회복
		local heal = 10 + math_random(40)
		local newHP = math_min(100, sim.targetHP + heal)

		-- 힐 예측 바 표시
		sim.isHealing = true
		sim.healAmount = newHP - sim.targetHP
		sim.healTimer = 0.6 + math_random() * 0.4

		sim.targetHP = newHP
	end

	-- 기력도 변동
	sim.targetPower = math_min(100, math_max(0, sim.targetPower + math_random(-20, 30)))

	-- 다음 이벤트 타이밍
	sim.nextEventTime = SIM_EVENT_MIN + math_random() * (SIM_EVENT_MAX - SIM_EVENT_MIN)
end

-----------------------------------------------
-- 프레임 비주얼 업데이트 (매 틱)
-----------------------------------------------
local function UpdateFrameVisual(frame, dt)
	local sim = frame._sim
	if not sim then return end

	-- 사망 상태 처리
	if sim.isDead then
		-- 부활 타이머
		sim.deathTimer = sim.deathTimer - dt
		if sim.deathTimer <= 0 then
			-- 부활!
			sim.isDead = false
			sim.targetHP = 40 + math_random(30)
			sim.currentHP = sim.targetHP * 0.5
			if frame.StatusText then frame.StatusText:Hide() end
			if frame.HealthText then frame.HealthText:Show() end
			if frame.NameText then
				frame.NameText:SetTextColor(sim.color.r, sim.color.g, sim.color.b)
			end
		else
			-- 사망 비주얼: 체력바→0, 회색, 저알파
			sim.currentHP = math_max(0, sim.currentHP - dt * 80)
			if frame.Health then
				frame.Health:SetValue(sim.currentHP)
				frame.Health:SetStatusBarColor(0.3, 0.3, 0.3)
				if frame.Health.bg then
					frame.Health.bg:SetVertexColor(0.05, 0.05, 0.05)
				end
			end
			frame:SetAlpha(0.5)
			if frame.HealthText then frame.HealthText:Hide() end
			if frame.StatusText then
				frame.StatusText:SetText("|cffcc3333Dead|r")
				frame.StatusText:Show()
			end
			if frame.NameText then
				frame.NameText:SetTextColor(0.5, 0.5, 0.5)
			end
			if frame.HealPrediction then
				frame.HealPrediction:Hide()
			end
			return
		end
	end

	-- 체력 보간 (smooth lerp)
	if sim.currentHP ~= sim.targetHP then
		local diff = sim.targetHP - sim.currentHP
		local step = diff * SIM_LERP_SPEED * dt
		-- 너무 느린 수렴 방지
		if math_abs(step) < 0.1 then
			step = (diff > 0) and 0.1 or -0.1
		end
		-- 오버슛 방지
		if math_abs(step) > math_abs(diff) then
			sim.currentHP = sim.targetHP
		else
			sim.currentHP = sim.currentHP + step
		end
		sim.currentHP = math_max(0, math_min(100, sim.currentHP))
	end

	-- 기력 보간
	if sim.currentPower ~= sim.targetPower then
		local diff = sim.targetPower - sim.currentPower
		local step = diff * 2.0 * dt
		if math_abs(step) < 0.1 then step = (diff > 0) and 0.1 or -0.1 end
		if math_abs(step) > math_abs(diff) then
			sim.currentPower = sim.targetPower
		else
			sim.currentPower = sim.currentPower + step
		end
		sim.currentPower = math_max(0, math_min(100, sim.currentPower))
	end

	-- 체력바 갱신
	if frame.Health then
		frame.Health:SetValue(sim.currentHP)

		-- [FIX] healthBarColorType에 따라 색상 적용 (클래스/커스텀/스무스)
		local colorType = sim.healthBarColorType
		if colorType == "custom" and sim.healthBarColor then
			local hc = sim.healthBarColor
			frame.Health:SetStatusBarColor(hc[1] or 0.2, hc[2] or 0.2, hc[3] or 0.2, hc[4] or 1)
		elseif colorType == "smooth" then
			local pct = sim.currentHP / 100
			frame.Health:SetStatusBarColor(1 - pct, pct, 0)
		else
			-- 기본: 클래스 색 + 저체력 빨강 그라디언트
			local hp = sim.currentHP
			if hp < SIM_LOW_HP then
				local t = hp / SIM_LOW_HP -- 0~1
				local r = sim.color.r * t + 1.0 * (1 - t)
				local g = sim.color.g * t + 0.1 * (1 - t)
				local b = sim.color.b * t + 0.1 * (1 - t)
				frame.Health:SetStatusBarColor(r, g, b)
			else
				frame.Health:SetStatusBarColor(sim.color.r, sim.color.g, sim.color.b)
			end
		end

		-- [FIX] healthLossColorType에 따라 배경색 적용
		if frame.Health.bg then
			local lossType = sim.healthLossColorType
			if lossType == "custom" and sim.healthLossColor then
				local lc = sim.healthLossColor
				frame.Health.bg:SetVertexColor(lc[1] or 0.5, lc[2] or 0.1, lc[3] or 0.1, lc[4] or 1)
			else
				local mu = frame.Health.bg.multiplier or 0.3
				frame.Health.bg:SetVertexColor(sim.color.r * mu, sim.color.g * mu, sim.color.b * mu)
			end
		end
	end

	-- 기력바 갱신
	if frame.Power and frame.Power:IsShown() then
		frame.Power:SetValue(sim.currentPower)
	end

	-- [FIX] 기력 텍스트 갱신
	if frame.PowerText and frame.PowerText:IsShown() then
		frame.PowerText:SetText(math_floor(sim.currentPower + 0.5) .. "%")
	end

	-- 체력 텍스트 갱신
	if frame.HealthText then
		local pct = math_floor(sim.currentHP + 0.5)
		if pct >= 100 then
			frame.HealthText:SetText("")
		else
			frame.HealthText:SetText(pct .. "%")
		end
	end

	-- 힐 예측 바
	if frame.HealPrediction and frame.Health then
		if sim.isHealing and sim.healTimer > 0 then
			sim.healTimer = sim.healTimer - dt
			local barWidth = frame.Health:GetWidth()
			local predWidth = (sim.healAmount / 100) * barWidth
			predWidth = math_min(predWidth, barWidth * 0.4)
			if predWidth > 1 then
				local curFill = (sim.currentHP / 100) * barWidth
				frame.HealPrediction:ClearAllPoints()
				frame.HealPrediction:SetPoint("LEFT", frame.Health, "LEFT", curFill, 0)
				frame.HealPrediction:SetWidth(predWidth)
				frame.HealPrediction:SetHeight(frame.Health:GetHeight())
				frame.HealPrediction:Show()
			end
		else
			sim.isHealing = false
			sim.healAmount = 0
			frame.HealPrediction:Hide()
		end
	end

	-- 알파: 정상
	frame:SetAlpha(1)
end

-----------------------------------------------
-- 메인 시뮬레이션 틱 (OnUpdate)
-----------------------------------------------
local function SimulationTick(self, elapsed)
	if not simActive then return end

	simElapsed = simElapsed + elapsed
	if simElapsed < SIM_TICK then return end
	local dt = simElapsed
	simElapsed = 0

	local ok, err = pcall(function()
		for _, frame in ipairs(testFrames) do
			if frame and frame._sim then
				-- 이벤트 타이머 감소
				frame._sim.nextEventTime = frame._sim.nextEventTime - dt
				if frame._sim.nextEventTime <= 0 then
					ProcessSimEvent(frame)
				end

				-- 비주얼 업데이트 (매 틱)
				UpdateFrameVisual(frame, dt)
			end
		end
	end)

	if not ok then
		simErrorCount = simErrorCount + 1
		if simErrorCount <= 3 then
			ns.Print("|cffff0000[Sim Error]|r " .. tostring(err))
		end
		if simErrorCount >= 10 then
			simActive = false
			ns.Print("|cffff0000편집모드 에러 반복 - 자동 중지|r")
		end
	end
end

-----------------------------------------------
-- 그룹 컨테이너 위치 설정 헬퍼
-----------------------------------------------
local function SetContainerPosition(container, unitDB)
	container:ClearAllPoints()
	local pos = unitDB and unitDB.position
	if pos and type(pos[1]) == "string" then
		local relativeTo = pos[2] and (_G[pos[2]] or UIParent) or UIParent
		container:SetPoint(pos[1], relativeTo, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
	elseif pos and pos.point then
		-- [EDITMODE-FIX] object 형식 position 지원 (ResolvePosition과 동일)
		container:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0)
	elseif pos and type(pos[1]) == "number" then
		local anchor = unitDB.anchorPoint or "TOPLEFT"
		container:SetPoint(anchor, UIParent, anchor, pos[1], pos[2] or 0)
	else
		return false  -- 위치 없음
	end
	return true
end

-----------------------------------------------
-- 편집모드 Enable / Disable
-- Config-Driven: Layout.lua 스타일과 동일한 프리뷰
-----------------------------------------------
function Update:EnableEditMode()
	if InCombatLockdown() then
		ns.Print("|cffff0000전투 중에는 편집모드를 사용할 수 없습니다.|r")
		return
	end

	-- 기존 테스트 프레임 정리
	for _, f in ipairs(testFrames) do
		if f and f.Hide then f:Hide() end
	end
	wipe(testFrames)

	-- OnUpdate 드라이버 프레임 생성
	if not simDriver then
		simDriver = CreateFrame("Frame", "ddingUI_SimDriver", UIParent)
		simDriver:SetScript("OnUpdate", SimulationTick)
	end

	-- [REFACTOR] Party/Raid는 GroupFrames TestMode에 위임
	-- (GF:CreateFrameElements + ApplyLayout 파이프라인 재사용 → 실제와 동일한 미리보기)
	if ns.GroupFrames and ns.GroupFrames.TestMode then
		ns.GroupFrames.TestMode:Enable()
	end

	local ok, err = pcall(function()
		-- ========================
		-- 개별 유닛 프리뷰 (player, target, targettarget, focus, focustarget, pet)
		-- ========================
		local soloUnits = {
			{ key = "player",       name = "Player",      label = "제이나",  fallbackAnchor = "BOTTOM", fallbackX = -260, fallbackY = 200 },
			{ key = "target",       name = "Target",      label = "아서스",  fallbackAnchor = "BOTTOM", fallbackX = 260,  fallbackY = 200 },
			{ key = "focus",        name = "Focus",       label = "일리단", fallbackAnchor = "LEFT",   fallbackX = -300, fallbackY = -100 },
		}
		local simIdx = 30  -- 개별 유닛 인덱스 오프셋 (파티/레이드와 겹치지 않게)

		for _, uInfo in ipairs(soloUnits) do
			local udb = ns.db[uInfo.key]
			if udb and udb.enabled ~= false then -- [EDITMODE-FIX] 비활성 모듈 프리뷰 생략
				local uw = (udb.size and udb.size[1]) or 220
				local uh = (udb.size and udb.size[2]) or 40
				local container = CreateGroupContainer("ddingUI_Sim_" .. uInfo.name, UIParent)
				container:SetSize(uw, uh)
				-- [EDITMODE-FIX] mover 위치 우선 사용 (mover와 simContainer 위치 일치 보장)
				local soloMover = _G["ddingUI_Mover_" .. uInfo.name]
				local soloPlaced = false
				if soloMover then
					local left, top = soloMover:GetLeft(), soloMover:GetTop()
					if left and top then
						container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
						soloPlaced = true
					end
				end
				if not soloPlaced then
					if not SetContainerPosition(container, udb) then
						container:SetPoint(uInfo.fallbackAnchor, UIParent, uInfo.fallbackAnchor, uInfo.fallbackX, uInfo.fallbackY)
					end
				end
				container:Show()
				simContainers[uInfo.key] = container

				local f = CreatePreviewFrame("ddingUI_Test_" .. uInfo.name, container)
				ApplyPreviewStyle(f, uInfo.key, uw, uh)
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
				InitSimState(f, simIdx, false)
				-- 개별 유닛 의미 있는 이름 설정
				if f._sim then f._sim.name = uInfo.label end
				if f.NameText then f.NameText:SetText(uInfo.label) end
				f:Show()
				testFrames[#testFrames + 1] = f
				simIdx = simIdx + 1
			end
		end

		-- 부착형 유닛 (targettarget → target, focustarget → focus, pet → player)
		local childUnits = {
			{ key = "targettarget", name = "ToT",         label = "실바나스",  parentKey = "target", fallbackAP = "BOTTOMLEFT", fallbackRelP = "BOTTOMRIGHT", fallbackX = 5, fallbackY = 0 },
			{ key = "focustarget",  name = "FocusTarget",  label = "카드가",   parentKey = "focus",  fallbackAP = "TOPLEFT",    fallbackRelP = "TOPRIGHT",    fallbackX = 5, fallbackY = 0 },
			{ key = "pet",          name = "Pet",          label = "늑대",     parentKey = "player", fallbackAP = "TOPLEFT",    fallbackRelP = "BOTTOMLEFT",  fallbackX = 0, fallbackY = -5 },
		}

		for _, cInfo in ipairs(childUnits) do
			local cdb = ns.db[cInfo.key]
			if cdb and cdb.enabled ~= false then -- [EDITMODE-FIX] 비활성 모듈 프리뷰 생략
				local cw = (cdb.size and cdb.size[1]) or 100
				local ch = (cdb.size and cdb.size[2]) or 22
				local container = CreateGroupContainer("ddingUI_Sim_" .. cInfo.name, UIParent)
				container:SetSize(cw, ch)

				-- [EDITMODE-FIX] mover 화면 위치 우선 사용 (anchorToParent 시 mover/simContainer 위치 불일치 방지)
				local moverFrame = _G["ddingUI_Mover_" .. cInfo.name]
				local moverPlaced = false
				if moverFrame then
					local left, top = moverFrame:GetLeft(), moverFrame:GetTop()
					if left and top then
						container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
						moverPlaced = true
					end
				end
				if not moverPlaced then
					-- mover 없으면 기존 로직 (부모 컨테이너 부착 또는 DB 위치)
					local parentContainer = simContainers[cInfo.parentKey]
					if cdb.anchorToParent and parentContainer then
						local ap = cdb.anchorPosition
						if ap and type(ap) == "table" and ap.point then
							container:SetPoint(ap.point, parentContainer, ap.relativePoint or ap.point, ap.offsetX or 0, ap.offsetY or 0)
						else
							container:SetPoint(cInfo.fallbackAP, parentContainer, cInfo.fallbackRelP, cInfo.fallbackX, cInfo.fallbackY)
						end
					elseif not SetContainerPosition(container, cdb) then
						local pContainer = simContainers[cInfo.parentKey] or UIParent
						container:SetPoint(cInfo.fallbackAP, pContainer, cInfo.fallbackRelP, cInfo.fallbackX, cInfo.fallbackY)
					end
				end
				container:Show()
				simContainers[cInfo.key] = container

				local f = CreatePreviewFrame("ddingUI_Test_" .. cInfo.name, container)
				ApplyPreviewStyle(f, cInfo.key, cw, ch)
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
				InitSimState(f, simIdx, false)
				if f._sim then f._sim.name = cInfo.label end
				if f.NameText then f.NameText:SetText(cInfo.label) end
				f:Show()
				testFrames[#testFrames + 1] = f
				simIdx = simIdx + 1
			end
		end

		-- ========================
		-- Boss 프리뷰 (5개)
		-- ========================
		local bdb = ns.db.boss
		if bdb and bdb.enabled ~= false then -- [EDITMODE-FIX] 비활성 모듈 프리뷰 생략
			local bw = (bdb.size and bdb.size[1]) or 180
			local bh = (bdb.size and bdb.size[2]) or 35
			local bSpacing = bdb.spacing or 48
			local bGrow = bdb.growDirection or "DOWN"
			local bossCount = 5

			local bossContainer = CreateGroupContainer("ddingUI_SimBoss", UIParent)
			bossContainer:SetSize(bw, bossCount * bh + (bossCount - 1) * bSpacing)
			-- [EDITMODE-FIX] Boss mover 위치 우선 사용 (mover는 boss1 크기, container는 5개 크기 → TOPLEFT 정렬)
			local bossMover = _G["ddingUI_Mover_Boss"]
			local bossPlaced = false
			if bossMover then
				local left, top = bossMover:GetLeft(), bossMover:GetTop()
				if left and top then
					bossContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
					bossPlaced = true
				end
			end
			if not bossPlaced then
				if not SetContainerPosition(bossContainer, bdb) then
					bossContainer:SetPoint("RIGHT", UIParent, "RIGHT", -60, 100)
				end
			end
			bossContainer:Show()
			simContainers.boss = bossContainer

			local bossNames = { "보스 1", "보스 2", "보스 3", "보스 4", "보스 5" }
			for i = 1, bossCount do
				local f = CreatePreviewFrame("ddingUI_TestBoss" .. i, bossContainer)
				ApplyPreviewStyle(f, "boss", bw, bh)
				f:ClearAllPoints()
				local yOff
				if bGrow == "UP" then
					yOff = (i - 1) * (bh + bSpacing)
					f:SetPoint("BOTTOMLEFT", bossContainer, "BOTTOMLEFT", 0, yOff)
				else
					yOff = -(i - 1) * (bh + bSpacing)
					f:SetPoint("TOPLEFT", bossContainer, "TOPLEFT", 0, yOff)
				end
				InitSimState(f, simIdx, false)
				if f._sim then f._sim.name = bossNames[i] end
				if f.NameText then f.NameText:SetText(bossNames[i]) end
				f:Show()
				testFrames[#testFrames + 1] = f
				simIdx = simIdx + 1
			end
		end

		-- ========================
		-- Arena 프리뷰 (3개)
		-- ========================
		local adb = ns.db.arena
		if adb and adb.enabled ~= false then -- [EDITMODE-FIX] 비활성 모듈 프리뷰 생략
			local aw = (adb.size and adb.size[1]) or 180
			local ah = (adb.size and adb.size[2]) or 35
			local aSpacing = adb.spacing or 48
			local aGrow = adb.growDirection or "DOWN"
			local arenaCount = 3

			local arenaContainer = CreateGroupContainer("ddingUI_SimArena", UIParent)
			arenaContainer:SetSize(aw, arenaCount * ah + (arenaCount - 1) * aSpacing)
			-- [EDITMODE-FIX] Arena mover 위치 우선 사용 (TOPLEFT 정렬)
			local arenaMover = _G["ddingUI_Mover_Arena"]
			local arenaPlaced = false
			if arenaMover then
				local left, top = arenaMover:GetLeft(), arenaMover:GetTop()
				if left and top then
					arenaContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
					arenaPlaced = true
				end
			end
			if not arenaPlaced then
				if not SetContainerPosition(arenaContainer, adb) then
					arenaContainer:SetPoint("RIGHT", UIParent, "RIGHT", -60, 100)
				end
			end
			arenaContainer:Show()
			simContainers.arena = arenaContainer

			local arenaNames = { "투기장 1", "투기장 2", "투기장 3" }
			for i = 1, arenaCount do
				local f = CreatePreviewFrame("ddingUI_TestArena" .. i, arenaContainer)
				ApplyPreviewStyle(f, "arena", aw, ah)
				f:ClearAllPoints()
				local yOff
				if aGrow == "UP" then
					yOff = (i - 1) * (ah + aSpacing)
					f:SetPoint("BOTTOMLEFT", arenaContainer, "BOTTOMLEFT", 0, yOff)
				else
					yOff = -(i - 1) * (ah + aSpacing)
					f:SetPoint("TOPLEFT", arenaContainer, "TOPLEFT", 0, yOff)
				end
				InitSimState(f, simIdx, false)
				if f._sim then f._sim.name = arenaNames[i] end
				if f.NameText then f.NameText:SetText(arenaNames[i]) end
				f:Show()
				testFrames[#testFrames + 1] = f
				simIdx = simIdx + 1
			end
		end
	end)

	if not ok then
		ns.Print("|cffff0000편집모드 프레임 생성 오류:|r " .. tostring(err))
		return
	end

	-- 시뮬레이션 시작
	simActive = true
	simElapsed = 0
	simErrorCount = 0
	simDriver:Show()

	ns.Print("|cff00ccff편집모드 ON|r - " .. #testFrames .. "개 미리보기 프레임")
end

-- 하위 호환
Update.EnableTestMode = Update.EnableEditMode

function Update:DisableEditMode()
	-- [REFACTOR] GroupFrames TestMode 종료
	if ns.GroupFrames and ns.GroupFrames.TestMode then
		ns.GroupFrames.TestMode:Disable()
	end

	if not simActive and #testFrames == 0 then return end  -- 이미 비활성

	simActive = false
	if simDriver then
		simDriver:Hide()
	end

	for _, f in ipairs(testFrames) do
		if f and f.Hide then
			f:Hide()
			f:ClearAllPoints()
			f._sim = nil
		end
	end
	wipe(testFrames)

	-- [REFACTOR] party/raid는 TestMode가 관리하므로 개인유닛 컨테이너만 정리
	for key, container in pairs(simContainers) do
		if key ~= "party" and key ~= "raid" and container and container.Hide then
			container:Hide()
		end
	end
	-- party/raid 키를 제외하고 정리
	local keysToRemove = {}
	for key in pairs(simContainers) do
		if key ~= "party" and key ~= "raid" then
			keysToRemove[#keysToRemove + 1] = key
		end
	end
	for _, key in ipairs(keysToRemove) do
		simContainers[key] = nil
	end

	ns.Print("|cff00ccff편집모드 OFF|r")
end

-- 하위 호환
Update.DisableTestMode = Update.DisableEditMode

-----------------------------------------------
-- 편집모드 프리뷰 실시간 갱신 (설정 변경 시)
-- ApplyPreviewStyle 재호출로 Layout 일관성 보장
-----------------------------------------------

function Update:RefreshPreview(unitKey)
	-- [REFACTOR] party/raid/mythicRaid는 GroupFrames TestMode에 위임
	if unitKey == "party" or unitKey == "raid" or unitKey == "mythicRaid" then
		if ns.GroupFrames and ns.GroupFrames.TestMode and ns.GroupFrames.TestMode.active then
			if unitKey == "party" then
				ns.GroupFrames.TestMode:RefreshParty()
			else
				ns.GroupFrames.TestMode:RefreshRaid()
			end
			return
		end
	end

	-- [12.0.1] 개별 유닛 (boss, arena, player, target, focus 등) 실시간 갱신
	-- [FIX] simActive가 아니어도 testFrames가 있으면 갱신 (옵션 패널에서 호출 가능)
	if not simActive and #testFrames == 0 then return end

	local db = ns.db[unitKey] or {}
	local w = (db.size and db.size[1]) or 200
	local h = (db.size and db.size[2]) or 40

	-- 프리뷰 프레임 스타일 재적용
	for _, f in ipairs(testFrames) do
		if f and f._previewUnitKey == unitKey then
			ApplyPreviewStyle(f, unitKey, w, h)
			-- sim state 유지: 비주얼만 갱신 (re-init 불필요)
			if f._sim then
				-- [FIX] sim state에 DB colorType 동기화 → UpdateFrameVisual이 매 틱 올바른 색상 사용
				f._sim.healthBarColorType = db.healthBarColorType
				f._sim.healthBarColor = db.healthBarColor
				f._sim.healthLossColorType = db.healthLossColorType
				f._sim.healthLossColor = db.healthLossColor

				local cc = RAID_CLASS_COLORS[f._sim.class]
				-- [FIX] healthBarColorType 즉시 반영 (다음 틱까지 기다리지 않고)
				if f.Health then
					local colorType = db.healthBarColorType
					if colorType == "custom" and db.healthBarColor then
						local hc = db.healthBarColor
						f.Health:SetStatusBarColor(hc[1] or 0.2, hc[2] or 0.2, hc[3] or 0.2, hc[4] or 1)
					elseif colorType == "smooth" then
						local pct = (f._sim.currentHP or 50) / 100
						f.Health:SetStatusBarColor(1 - pct, pct, 0)
					elseif cc then
						f.Health:SetStatusBarColor(cc.r, cc.g, cc.b)
					end
					f.Health:SetValue(f._sim.currentHP)
				end
				-- [FIX] healthLoss 배경색 즉시 반영
				if f.Health and f.Health.bg then
					local lossType = db.healthLossColorType
					if lossType == "custom" and db.healthLossColor then
						local lc = db.healthLossColor
						f.Health.bg:SetVertexColor(lc[1] or 0.5, lc[2] or 0.1, lc[3] or 0.1, lc[4] or 1)
					elseif cc then
						local m = f.Health.bg.multiplier or 0.3
						f.Health.bg:SetVertexColor(cc.r * m, cc.g * m, cc.b * m)
					end
				end
				if cc and f.NameText then f.NameText:SetTextColor(cc.r, cc.g, cc.b) end
				if f.NameText and f._sim.name then f.NameText:SetText(f._sim.name) end
				if f.HealthText then f.HealthText:SetText(math_floor(f._sim.currentHP) .. "%") end
				if f.Power and f.Power:IsShown() then
					f.Power:SetValue(f._sim.currentPower)
				end
				if f.PowerText and f.PowerText:IsShown() then
					f.PowerText:SetText(math_floor(f._sim.currentPower) .. "%")
				end
			end
		end
	end

	-- 컨테이너 크기 갱신
	local container = simContainers[unitKey]
	if container then
		if unitKey == "boss" or unitKey == "arena" then
			-- boss/arena: 다중 프레임 → 컨테이너 크기 + 자식 위치 재계산
			local spacing = db.spacing or 48
			local growDir = db.growDirection or "DOWN"
			local count = unitKey == "boss" and 5 or 3
			container:SetSize(w, count * h + (count - 1) * spacing)

			local idx = 0
			for _, f in ipairs(testFrames) do
				if f and f._previewUnitKey == unitKey then
					idx = idx + 1
					f:ClearAllPoints()
					if growDir == "UP" then
						local yOff = (idx - 1) * (h + spacing)
						f:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, yOff)
					else
						local yOff = -(idx - 1) * (h + spacing)
						f:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOff)
					end
				end
			end
		else
			-- 개별 유닛: 컨테이너 = 프레임 1:1
			container:SetSize(w, h)
		end
	end
end

-- 하위 호환
Update.RefreshSimFrameSize = Update.RefreshPreview
