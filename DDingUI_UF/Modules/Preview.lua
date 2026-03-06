--[[
	ddingUI UnitFrames
	Modules/Preview.lua - 설정 패널 미리보기 시스템 -- [PREVIEW]
	Cell 패턴: SetScale 기반, isPreview 플래그, 이벤트 차단, 더미 데이터
]]

local ADDON_NAME, ns = ...
local Widgets = ns.Widgets
local C = ns.Constants

local Preview = {}
ns.Preview = Preview

-----------------------------------------------
-- Constants -- [PREVIEW]
-----------------------------------------------
local PREVIEW_SCALE = 1.5 -- [PREVIEW]
local PREVIEW_PAD = 12
local PREVIEW_GAP = 4 -- 프레임 간 간격
local LABEL_HEIGHT = 18

-----------------------------------------------
-- Media -- [PREVIEW]
-----------------------------------------------
local function GetFlat()
	local SL = ns.StyleLib
	return (C and C.FLAT_TEXTURE) or (SL and SL.Textures and SL.Textures.flat) or [[Interface\Buttons\WHITE8x8]]
end

local function GetFont()
	local SL = ns.StyleLib
	return (SL and SL.Font and SL.Font.path) or [[Fonts\2002.TTF]]
end

-----------------------------------------------
-- Dummy Data -- [PREVIEW]
-- 다양한 상태를 보여주는 가짜 데이터
-----------------------------------------------
local DUMMY_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "PALADIN", "DRUID", "WARLOCK", "SHAMAN", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
local DUMMY_NAMES = { "탱커", "힐러", "마법사", "도적", "사냥꾼", "성기사", "드루이드", "흑마", "주술사", "죽기", "수도승", "악사", "용술사", "전사", "사제", "비전술사", "암살자", "저격수", "보호기사", "회복드루" }
local DUMMY_SPELL_IDS = { 2060, 116, 8042, 408, 100, 33763, 774, 48438 } -- Flash Heal, Frostbolt, Earth Shock, KS, Charge, Lifebloom, Rejuv, WildGrowth
local DUMMY_BUFF_IDS = { 1459, 21562, 6673, 1126 } -- Arcane Intellect, PW:Fortitude, Battle Shout, Mark of the Wild
local DUMMY_DEBUFF_IDS = { 589, 172, 8042, 122 } -- Shadow Word: Pain, Corruption, Earth Shock, Frost Nova

local function GetPlayerClassColor()
	local _, cls = UnitClass("player")
	if cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls] then
		local cc = RAID_CLASS_COLORS[cls]
		return cc.r, cc.g, cc.b, 1
	end
	return 0.5, 0.5, 0.5, 1
end

local function GetClassColor(class)
	if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local cc = RAID_CLASS_COLORS[class]
		return cc.r, cc.g, cc.b, 1
	end
	return 0.5, 0.5, 0.5, 1
end

-- 단일 유닛 더미 데이터
local function GetSingleDummy()
	local name = UnitName("player") or "플레이어"
	local _, cls = UnitClass("player")
	return {
		name = name,
		class = cls or "WARRIOR",
		healthPct = 0.72,
		powerPct = 0.85,
		healPct = 0.40, -- [PREVIEW] 오버힐 글로우 미리보기용
		casting = false,
		castSpellId = nil,
		dead = false,
		combat = true,
		shieldPct = 0.15,
	}
end

-- 파티 더미 데이터 (5인, 다양한 상태)
local PARTY_DUMMIES = {
	{ name = "탱커", class = "WARRIOR", healthPct = 0.95, powerPct = 0.60, healPct = 0.15, role = "TANK", leader = true, combat = true, shieldPct = 0.20 },
	{ name = "힐러", class = "PRIEST", healthPct = 0.88, powerPct = 0.45, healPct = 0.30, role = "HEALER", casting = true, castSpellId = 2060, combat = true },
	{ name = "마법사", class = "MAGE", healthPct = 0.28, powerPct = 0.70, healPct = 0.50, role = "DAMAGER", combat = true, shieldPct = 0.10 }, -- 위험 + 큰 힐 들어오는 중
	{ name = "도적", class = "ROGUE", healthPct = 0.55, powerPct = 0.90, role = "DAMAGER", combat = true },
	{ name = "사냥꾼", class = "HUNTER", healthPct = 0, powerPct = 0, role = "DAMAGER", dead = true },
}

-- 레이드 더미 데이터 (20인)
local function GetRaidDummies()
	local dummies = {}
	for i = 1, 20 do
		local classIdx = ((i - 1) % #DUMMY_CLASSES) + 1
		local nameIdx = ((i - 1) % #DUMMY_NAMES) + 1
		local hp = (i == 7) and 0 or (0.3 + math.random() * 0.7) -- 7번은 사망
		dummies[i] = {
			name = DUMMY_NAMES[nameIdx],
			class = DUMMY_CLASSES[classIdx],
			healthPct = (i == 7) and 0 or hp,
			powerPct = math.random() * 0.8 + 0.2,
			dead = (i == 7),
		}
	end
	return dummies
end

-- 보스 더미 데이터
local BOSS_DUMMIES = {
	{ name = "대왕거미", healthPct = 0.65, casting = true, castSpellId = 408 },
	{ name = "보스 부관", healthPct = 0.40, casting = false },
	{ name = "정예 부하", healthPct = 0.85, casting = false },
}

-- 투기장 더미 데이터
local ARENA_DUMMIES = {
	{ name = "적 전사", class = "WARRIOR", healthPct = 0.70, powerPct = 0.50 },
	{ name = "적 사제", class = "PRIEST", healthPct = 0.55, powerPct = 0.30, casting = true, castSpellId = 2060 },
	{ name = "적 도적", class = "ROGUE", healthPct = 0.90, powerPct = 0.80 },
}

-----------------------------------------------
-- Internal State -- [PREVIEW]
-----------------------------------------------
local container = nil  -- 메인 컨테이너 프레임
local frames = {}      -- 생성된 미리보기 프레임 풀
local currentUnit = nil
local optionsFrame = nil -- Options.lua mainFrame 참조

-- [PREVIEW] 시뮬레이션 시스템
local previewSimDriver = nil
local previewSimElapsed = 0
local simFrames = {}

-- [PREVIEW] 오라 쿨다운 추적
local activePreviewAuras = {}
local previewAuraElapsed = 0

-- [PREVIEW] 시뮬레이션 상수
local PREVIEW_SIM_TICK = 0.03       -- ~30fps
local PREVIEW_SIM_LERP = 3.0       -- 체력 보간 속도
local PREVIEW_EVENT_MIN = 1.0       -- 이벤트 최소 간격(초)
local PREVIEW_EVENT_MAX = 3.0       -- 이벤트 최대 간격(초)
local PREVIEW_AURA_TICK = 0.2       -- 오라 텍스트 갱신 5fps
local PREVIEW_AURA_CYCLE = 13       -- 오라 쿨다운 주기(초, Cell 패턴)

-----------------------------------------------
-- 시뮬레이션 드라이버 (전방 선언) -- [PREVIEW]
-----------------------------------------------
local StopPreviewSim  -- 전방 선언

-----------------------------------------------
-- 오라 지속시간 포맷 -- [PREVIEW]
-----------------------------------------------
local function FormatPreviewDuration(remaining)
	if remaining >= 60 then
		return string.format("%dm", math.floor(remaining / 60))
	elseif remaining >= 1 then
		return string.format("%d", math.floor(remaining))
	else
		return string.format("%.1f", remaining)
	end
end

-----------------------------------------------
-- 오라 지속시간 타이머 (5fps) -- [PREVIEW]
-----------------------------------------------
local function UpdatePreviewAuraDurations(elapsed)
	previewAuraElapsed = previewAuraElapsed + elapsed
	if previewAuraElapsed < PREVIEW_AURA_TICK then return end
	previewAuraElapsed = 0

	local now = GetTime()
	for iconFrame in pairs(activePreviewAuras) do
		if not iconFrame:IsShown() then
			activePreviewAuras[iconFrame] = nil
		elseif iconFrame.duration then
			local startTime = iconFrame._previewCooldownStart or 0
			local dur = iconFrame._previewDuration or PREVIEW_AURA_CYCLE
			local totalElapsed = now - startTime
			local cyclePos = totalElapsed % dur
			local remaining = dur - cyclePos
			iconFrame.duration:SetText(FormatPreviewDuration(remaining))
			-- 주기 완료 시 새 쿨다운 시작
			if totalElapsed >= dur then
				local cycles = math.floor(totalElapsed / dur)
				local newStart = startTime + cycles * dur
				iconFrame.cooldown:SetCooldown(newStart, dur)
				iconFrame._previewCooldownStart = newStart
			end
		end
	end
end

-----------------------------------------------
-- 캐스트바 애니메이션 업데이트 -- [PREVIEW]
-----------------------------------------------
local function UpdatePreviewCastBar(castBar, dt)
	local sb = castBar._statusBar
	if not sb then return end

	local now = GetTime()
	local elapsed = now - (castBar._castStart or now)
	local dur = castBar._castDuration or 2.5
	local progress = elapsed / dur

	if progress >= 1.0 then
		-- 시전 완료 → 0.8초 대기 후 새 시전 시작
		castBar._castStart = now + 0.8
		castBar._castDuration = 2.0 + math.random() * 1.5
		sb:SetValue(0)
	elseif progress < 0 then
		-- 대기 중
		sb:SetValue(0)
	else
		sb:SetValue(progress)
	end

	-- 타이머 텍스트
	if castBar._timerText then
		if progress >= 0 and progress < 1 then
			local remaining = math.max(0, dur - elapsed)
			castBar._timerText:SetText(string.format("%.1fs", remaining))
		else
			castBar._timerText:SetText("")
		end
	end
end

-----------------------------------------------
-- 시뮬레이션 이벤트 처리 -- [PREVIEW]
-----------------------------------------------
local function InitPreviewSimState(frame, dummy, unit)
	if dummy.dead then
		frame._sim = nil
		return
	end
	local r, g, b = GetClassColor(dummy.class)
	local settings = unit and ns.db[unit]
	frame._sim = {
		currentHP = (dummy.healthPct or 0.72) * 100,
		targetHP = (dummy.healthPct or 0.72) * 100,
		currentPower = (dummy.powerPct or 0.85) * 100,
		targetPower = (dummy.powerPct or 0.85) * 100,
		nextEventTime = 0.5 + math.random() * 1.5,
		classColor = { r or 0.5, g or 0.5, b or 0.5 },
		healthBarColorType = settings and settings.healthBarColorType or "class", -- [FIX]
		healthBarColor = settings and settings.healthBarColor, -- [FIX]
	}
end

local function ProcessPreviewEvent(frame)
	local sim = frame._sim
	if not sim then return end

	if math.random() < 0.5 then
		-- 피해
		local dmg = 5 + math.random(25)
		sim.targetHP = math.max(15, sim.targetHP - dmg)
	else
		-- 회복
		local heal = 10 + math.random(30)
		sim.targetHP = math.min(100, sim.targetHP + heal)
	end
	sim.targetPower = math.max(10, math.min(100,
		sim.targetPower + math.random(-15, 20)))
	sim.nextEventTime = PREVIEW_EVENT_MIN + math.random() * (PREVIEW_EVENT_MAX - PREVIEW_EVENT_MIN)
end

local function UpdatePreviewVisual(frame, dt)
	local sim = frame._sim
	if not sim then return end

	-- 체력 LERP
	if sim.currentHP ~= sim.targetHP then
		local diff = sim.targetHP - sim.currentHP
		local step = diff * PREVIEW_SIM_LERP * dt
		if math.abs(step) < 0.1 then step = (diff > 0) and 0.1 or -0.1 end
		if math.abs(step) > math.abs(diff) then
			sim.currentHP = sim.targetHP
		else
			sim.currentHP = sim.currentHP + step
		end
		sim.currentHP = math.max(0, math.min(100, sim.currentHP))
	end

	-- 기력 LERP
	if sim.currentPower ~= sim.targetPower then
		local diff = sim.targetPower - sim.currentPower
		local step = diff * 2.0 * dt
		if math.abs(step) < 0.1 then step = (diff > 0) and 0.1 or -0.1 end
		if math.abs(step) > math.abs(diff) then
			sim.currentPower = sim.targetPower
		else
			sim.currentPower = sim.currentPower + step
		end
		sim.currentPower = math.max(0, math.min(100, sim.currentPower))
	end

	-- 체력바 StatusBar 업데이트
	if frame._healthBar then
		frame._healthBar:SetValue(sim.currentHP)
		-- [FIX] healthBarColorType 설정 반영 (시뮬레이션 중)
		local hp = sim.currentHP
		local colorType = sim.healthBarColorType
		if colorType == "smooth" then
			-- 체력 그라데이션: 빨강→노랑→초록
			local pct = hp / 100
			if pct > 0.5 then
				frame._healthBar:SetStatusBarColor((1 - pct) * 2, 1, 0, 1)
			else
				frame._healthBar:SetStatusBarColor(1, pct * 2, 0, 1)
			end
		elseif colorType == "custom" and sim.healthBarColor then
			local c = sim.healthBarColor
			frame._healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
		else
			-- class (기본): 저체력 시 빨강 블렌드
			local cc = sim.classColor
			if hp < 35 then
				local t = hp / 35
				frame._healthBar:SetStatusBarColor(
					cc[1] * t + 1.0 * (1 - t),
					cc[2] * t + 0.1 * (1 - t),
					cc[3] * t + 0.1 * (1 - t))
			else
				frame._healthBar:SetStatusBarColor(cc[1], cc[2], cc[3])
			end
		end
	end

	-- 기력바 업데이트
	if frame._powerBar then
		frame._powerBar:SetValue(sim.currentPower)
	end

	-- 체력 텍스트 업데이트
	if frame._healthText and frame._healthText:IsShown() then
		local pct = math.floor(sim.currentHP + 0.5)
		if pct >= 100 then
			frame._healthText:SetText("")
		else
			frame._healthText:SetFormattedText("%d%%", pct)
		end
	end

	-- 캐스트바 진행
	if frame._castBar and frame._castBar._statusBar then
		UpdatePreviewCastBar(frame._castBar, dt)
	end
end

-----------------------------------------------
-- 시뮬레이션 드라이버 -- [PREVIEW]
-----------------------------------------------
local function PreviewSimTick(self, elapsed)
	previewSimElapsed = previewSimElapsed + elapsed
	if previewSimElapsed < PREVIEW_SIM_TICK then return end
	local dt = previewSimElapsed
	previewSimElapsed = 0

	for _, frame in ipairs(simFrames) do
		if frame._sim then
			frame._sim.nextEventTime = frame._sim.nextEventTime - dt
			if frame._sim.nextEventTime <= 0 then
				ProcessPreviewEvent(frame)
			end
			UpdatePreviewVisual(frame, dt)
		end
	end

	-- 오라 지속시간 텍스트 업데이트 (동일 OnUpdate)
	UpdatePreviewAuraDurations(elapsed)
end

local function StartPreviewSim()
	if not previewSimDriver then
		previewSimDriver = CreateFrame("Frame", "DDingUI_UF_PreviewSimDriver", UIParent)
	end
	previewSimElapsed = 0
	previewAuraElapsed = 0
	previewSimDriver:SetScript("OnUpdate", PreviewSimTick)
	previewSimDriver:Show()
end

StopPreviewSim = function()
	if previewSimDriver then
		previewSimDriver:SetScript("OnUpdate", nil)
		previewSimDriver:Hide()
	end
	wipe(simFrames)
	wipe(activePreviewAuras)
end

-----------------------------------------------
-- 오라 아이콘 생성 헬퍼 -- [PREVIEW]
-- CooldownFrame + 지속시간 텍스트 (Cell 패턴)
-----------------------------------------------
local function CreatePreviewAuraIcon(parent, w, h, spellId, isDebuff, staggerIndex)
	local FLAT = GetFlat()
	local fontPath = GetFont()

	local iconFrame = CreateFrame("Frame", nil, parent)
	iconFrame.isPreview = true
	iconFrame:SetSize(w, h)
	iconFrame:SetFrameLevel(parent:GetFrameLevel() + 5)

	-- 테두리
	iconFrame.border = iconFrame:CreateTexture(nil, "BACKGROUND")
	iconFrame.border:SetPoint("TOPLEFT", -1, 1)
	iconFrame.border:SetPoint("BOTTOMRIGHT", 1, -1)
	iconFrame.border:SetTexture(FLAT)
	if isDebuff then
		iconFrame.border:SetVertexColor(0.8, 0.1, 0.1, 0.9)
	else
		iconFrame.border:SetVertexColor(0, 0, 0, 0.8)
	end

	-- 아이콘 텍스처
	iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
	iconFrame.texture:SetAllPoints()
	iconFrame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
	iconFrame.texture:SetTexture(info and info.iconID or 136243)

	-- 쿨다운 스파이럴 (CooldownFrameTemplate)
	iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
	iconFrame.cooldown:SetAllPoints(iconFrame.texture)
	iconFrame.cooldown:SetDrawEdge(false)
	iconFrame.cooldown:SetDrawSwipe(true)
	iconFrame.cooldown:SetReverse(true)
	iconFrame.cooldown:SetHideCountdownNumbers(true)
	iconFrame.cooldown.noCooldownCount = true -- OmniCC 등 간섭 방지

	-- 텍스트 오버레이 (쿨다운 위)
	iconFrame.textOverlay = CreateFrame("Frame", nil, iconFrame)
	iconFrame.textOverlay:SetAllPoints()
	iconFrame.textOverlay:SetFrameLevel(iconFrame.cooldown:GetFrameLevel() + 5)
	iconFrame.textOverlay:EnableMouse(false)

	-- 지속시간 텍스트
	iconFrame.duration = iconFrame.textOverlay:CreateFontString(nil, "OVERLAY")
	iconFrame.duration:SetFont(fontPath, math.max(7, math.floor(math.min(w, h) * 0.38)), "OUTLINE")
	iconFrame.duration:SetPoint("CENTER", 0, 0)
	iconFrame.duration:SetTextColor(1, 1, 1, 1)

	-- 13초 주기 쿨다운 시작 (Cell 패턴, stagger로 분산)
	local offset = (staggerIndex or 0) * 3
	iconFrame._previewCooldownStart = GetTime() - offset
	iconFrame._previewDuration = PREVIEW_AURA_CYCLE
	iconFrame.cooldown:SetCooldown(GetTime() - offset, PREVIEW_AURA_CYCLE)

	-- 공유 타이머 등록
	activePreviewAuras[iconFrame] = true

	return iconFrame
end

-----------------------------------------------
-- Frame Pool 관리 -- [PREVIEW]
-----------------------------------------------
local function RecycleFrames()
	-- [PREVIEW] 시뮬레이션 먼저 중지
	StopPreviewSim()

	for i, f in ipairs(frames) do
		-- [PREVIEW] 오라 CooldownFrame 정리
		if f._auraIcons then
			for _, icon in ipairs(f._auraIcons) do
				if icon.cooldown then icon.cooldown:SetCooldown(0, 0) end
				activePreviewAuras[icon] = nil
				icon:Hide()
				icon:SetParent(nil)
			end
			wipe(f._auraIcons)
		end
		-- [PREVIEW] 캐스트바 StatusBar 정리
		if f._castBar and f._castBar._statusBar then
			f._castBar._statusBar:Hide()
		end
		-- [PREVIEW] 시뮬레이션 상태 초기화
		f._sim = nil
		f:Hide()
		f:ClearAllPoints()
	end
end

local function GetOrCreateFrame(index)
	if frames[index] then return frames[index] end

	local f = CreateFrame("Frame", "DDingUI_UF_Preview" .. index, container, "BackdropTemplate")
	f.isPreview = true -- [PREVIEW] Cell 패턴
	f:UnregisterAllEvents() -- [PREVIEW] 이벤트 차단
	f:EnableMouse(false) -- [PREVIEW] 마우스 비활성
	f:Hide()
	frames[index] = f
	return f
end

-----------------------------------------------
-- 텍스트 포맷 헬퍼 -- [PREVIEW]
-----------------------------------------------
local function FormatNameText(name, format)
	if not name then return "" end
	if format == "name:abbrev" then
		-- 약어: 각 단어 첫 글자 (한글은 첫 2자)
		if #name > 4 then return name:sub(1, 6) .. "." end -- UTF-8 한글 2자 ≈ 6바이트
		return name
	elseif format == "name:short" then
		if #name > 8 then return name:sub(1, 9) .. ".." end
		return name
	end
	return name -- "name" 또는 기본값
end

local function FormatHealthText(pct, format, separator, isDead)
	if isDead then return "사망" end
	local pctStr = math.floor(pct * 100) .. "%"
	local maxHP = 100000
	local curHP = math.floor(maxHP * pct)
	local defHP = maxHP - curHP
	local sep = separator or "/"

	local curStr = curHP >= 10000 and string.format("%.1f만", curHP / 10000) or tostring(curHP)
	local maxStr = maxHP >= 10000 and string.format("%.1f만", maxHP / 10000) or tostring(maxHP)
	local defStr = defHP >= 10000 and string.format("%.1f만", defHP / 10000) or tostring(defHP)

	if format == "current" then return curStr
	elseif format == "current-max" then return curStr .. sep .. maxStr
	elseif format == "deficit" then return defHP > 0 and ("-" .. defStr) or ""
	elseif format == "current-percentage" then return curStr .. " (" .. pctStr .. ")"
	elseif format == "percent-current" then return pctStr .. " | " .. curStr
	elseif format == "current-percent" then return curStr .. " | " .. pctStr
	end
	return pctStr -- "percentage" 또는 기본값
end

-----------------------------------------------
-- 단일 프레임 위젯 구축 -- [PREVIEW]
-- settings: DB 설정, dummy: 더미 데이터
-----------------------------------------------
local function BuildFrameWidgets(frame, unit, dummy)
	-- 기존 자식 텍스처/폰트스트링 정리
	if frame._children then
		for _, child in ipairs(frame._children) do
			if child.Hide then child:Hide() end
			if child.SetParent then child:SetParent(nil) end
		end
	end
	frame._children = {}
	if frame._castBar then
		frame._castBar:Hide()
		frame._castBar:SetParent(nil)
		frame._castBar = nil
	end
	if frame._classBarFrame then
		frame._classBarFrame:Hide()
		frame._classBarFrame:SetParent(nil)
		frame._classBarFrame = nil
	end

	local settings = ns.db[unit]
	if not settings then return end

	local FLAT = GetFlat()
	local fontPath = GetFont()

	local unitW = (settings.size and settings.size[1]) or 200
	local unitH = (settings.size and settings.size[2]) or 40

	frame:SetSize(unitW, unitH)

	-- 테두리 & 배경
	local rawBorderSize = (settings.border and settings.border.size) or 1
	-- Cell 방식: PixelUtil.GetNearestPixelSize 사용 (실제 유닛프레임과 동일)
	local F = ns.Functions
	local borderSize = (F and F.ScalePixel) and F:ScalePixel(rawBorderSize) or rawBorderSize
	local borderColor = (settings.border and settings.border.color) or { 0, 0, 0, 1 }
	local bgColor = (settings.background and settings.background.color) or { 0.08, 0.08, 0.08, 0.85 }
	local borderEnabled = not settings.border or settings.border.enabled ~= false

	if borderEnabled then
		frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = borderSize })
		frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.85)
		frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	else
		frame:SetBackdrop({ bgFile = FLAT })
		frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.85)
	end

	local inset = 0
	local wdb = settings.widgets or {}

	-- 파워바
	local powerDB = wdb.powerBar
	local powerEnabled = powerDB and powerDB.enabled ~= false
	local powerH = powerEnabled and ((powerDB and powerDB.size and powerDB.size.height) or 8) or 0
	local powerW = unitW -- 자원바 너비
	if powerEnabled and powerDB then
		if powerDB.sameWidthAsHealthBar then
			powerW = unitW
		elseif powerDB.size and powerDB.size.width then
			powerW = powerDB.size.width
		end
	end

	-- 사망 상태
	local isDead = dummy.dead
	local healthPct = isDead and 0 or (dummy.healthPct or 1)
	local frameAlpha = isDead and 0.4 or 1

	-- 체력바 텍스처
	local healthTexPath = settings.healthBarTexture or FLAT

	-- ===== 체력바 (StatusBar) ===== -- [PREVIEW]
	local healthBar = CreateFrame("StatusBar", nil, frame)
	healthBar:SetStatusBarTexture(healthTexPath)
	healthBar:SetMinMaxValues(0, 100)
	healthBar:SetValue(healthPct * 100)
	healthBar:SetFrameLevel(frame:GetFrameLevel() + 1)
	if isDead then
		healthBar:SetStatusBarColor(0.3, 0.3, 0.3, 1)
	elseif settings.healthBarColorType == "class" and dummy.class then
		local r, g, b = GetClassColor(dummy.class)
		healthBar:SetStatusBarColor(r, g, b, 1)
	elseif settings.healthBarColorType == "smooth" then
		local hp = healthPct
		if hp > 0.5 then
			healthBar:SetStatusBarColor((1 - hp) * 2, 1, 0, 1)
		else
			healthBar:SetStatusBarColor(1, hp * 2, 0, 1)
		end
	elseif settings.healthBarColorType == "custom" and settings.healthBarColor then
		local c = settings.healthBarColor
		healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	elseif settings.healthBarColor then
		local c = settings.healthBarColor
		healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	else
		healthBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
	end

	-- 체력바 위치/크기
	local barWidth = unitW - inset * 2
	if settings.reverseHealthFill then
		healthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
		healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset + powerH)
		healthBar:SetWidth(barWidth)
		healthBar:SetReverseFill(true)
	else
		healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
		healthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset + powerH)
		healthBar:SetWidth(barWidth)
	end
	frame._healthBar = healthBar  -- [PREVIEW] 시뮬레이션 참조
	table.insert(frame._children, healthBar)

	-- 체력 손실 영역
	local healthLoss = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	healthLoss:SetTexture(settings.healthBgTexture or healthTexPath)
	-- 손실 색상
	if settings.healthLossColorType == "class_dark" and dummy.class then
		local r, g, b = GetClassColor(dummy.class)
		healthLoss:SetVertexColor(r * 0.3, g * 0.3, b * 0.3, 1)
	elseif settings.healthLossColor then
		local lc = settings.healthLossColor
		healthLoss:SetVertexColor(lc[1], lc[2], lc[3], lc[4] or 1)
	else
		healthLoss:SetVertexColor(0.15, 0.15, 0.15, 1)
	end
	-- [PREVIEW] StatusBar 기반: 전체 체력바 영역 커버 (StatusBar 채움 뒤 배경)
	healthLoss:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
	healthLoss:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset + powerH)
	table.insert(frame._children, healthLoss)

	-- ===== 파워바 =====
	if powerEnabled and powerH > 0 then
		-- 배경
		local pBgTex = (powerDB and powerDB.background and powerDB.background.texture) or settings.powerBarTexture or FLAT
		local powerBg = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
		powerBg:SetTexture(pBgTex)
		local pBgCol = (powerDB and powerDB.background and powerDB.background.color) or { 0, 0, 0, 0.7 }
		powerBg:SetVertexColor(pBgCol[1] or 0, pBgCol[2] or 0, pBgCol[3] or 0, pBgCol[4] or 0.7)
		powerBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
		powerBg:SetSize(powerW, powerH)
		table.insert(frame._children, powerBg)
		-- 전경 (StatusBar) -- [PREVIEW]
		local powerTexPath = settings.powerBarTexture or FLAT
		local powerBar = CreateFrame("StatusBar", nil, frame)
		powerBar:SetStatusBarTexture(powerTexPath)
		powerBar:SetMinMaxValues(0, 100)
		powerBar:SetValue((dummy.powerPct or 1) * 100)
		powerBar:SetFrameLevel(frame:GetFrameLevel() + 2)
		if isDead then
			powerBar:SetStatusBarColor(0.2, 0.2, 0.2, 1)
		elseif powerDB and powerDB.colorClass and dummy.class then
			local r, g, b = GetClassColor(dummy.class)
			powerBar:SetStatusBarColor(r, g, b, 1)
		elseif powerDB and powerDB.customColor then
			local pc = powerDB.customColor
			powerBar:SetStatusBarColor(pc[1], pc[2], pc[3], pc[4] or 1)
		else
			powerBar:SetStatusBarColor(0.0, 0.55, 1.0, 1)
		end
		powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
		powerBar:SetSize(powerW, powerH)
		frame._powerBar = powerBar  -- [PREVIEW] 시뮬레이션 참조
		table.insert(frame._children, powerBar)
	end

	-- ===== 이름 텍스트 =====
	local nameDB = wdb.nameText
	if nameDB and nameDB.enabled ~= false then
		local nFont = nameDB.font
		local nSize = (nFont and nFont.size) or 12
		local nFlags = (nFont and nFont.outline) or "OUTLINE"
		local nameText = frame:CreateFontString(nil, "OVERLAY")
		nameText:SetFont(fontPath, math.max(7, nSize), nFlags)
		nameText:SetWordWrap(false) -- [FIX] 한 줄 강제
		nameText:SetNonSpaceWrap(false)
		nameText:SetMaxLines(1)
		-- 이름 형식 적용
		local nameFormat = nameDB.format or "name"
		local displayName = FormatNameText(dummy.name, nameFormat)
		nameText:SetText(isDead and (displayName .. " (사망)") or displayName)
		-- 클래스 색상
		local nColor = nameDB.color
		local nColorType = nColor and nColor.type or "class_color"
		if isDead then
			nameText:SetTextColor(0.5, 0.5, 0.5)
		elseif nColorType == "class_color" and dummy.class then
			local r, g, b = GetClassColor(dummy.class)
			nameText:SetTextColor(r, g, b)
		elseif nColorType == "custom" and nColor.rgb then
			nameText:SetTextColor(nColor.rgb[1], nColor.rgb[2], nColor.rgb[3], 1)
		elseif nColorType == "reaction_color" then
			nameText:SetTextColor(0.0, 1.0, 0.0) -- 미리보기: 우호(초록)
		elseif nColorType == "power_color" then
			nameText:SetTextColor(0.0, 0.55, 1.0) -- 미리보기: 마나(파랑)
		elseif nColorType == "health_gradient" then
			local hp = healthPct
			if hp > 0.5 then nameText:SetTextColor((1-hp)*2, 1, 0)
			else nameText:SetTextColor(1, hp*2, 0) end
		else
			nameText:SetTextColor(1, 1, 1)
		end
		local nPos = nameDB.position
		local nPt = (nPos and nPos.point) or "TOPLEFT"
		local nRel = (nPos and nPos.relativePoint) or "CENTER"
		local nX = (nPos and nPos.offsetX) or 2
		local nY = (nPos and nPos.offsetY) or 8
		nameText:SetPoint(nPt, frame, nRel, nX, nY)
		table.insert(frame._children, nameText)
	end

	-- ===== 체력 텍스트 =====
	local htDB = wdb.healthText
	if htDB and htDB.enabled ~= false then
		local htFont = htDB.font
		local htSize = (htFont and htFont.size) or 11
		local htFlags = (htFont and htFont.outline) or "OUTLINE"
		local htText = frame:CreateFontString(nil, "OVERLAY")
		htText:SetFont(fontPath, math.max(7, htSize), htFlags)
		htText:SetWordWrap(false) -- [FIX] 한 줄 강제
		htText:SetMaxLines(1)
		-- 체력 형식 적용
		local htFormat = htDB.format or "percentage"
		local htSep = htDB.separator or "/"
		htText:SetText(FormatHealthText(healthPct, htFormat, htSep, isDead))
		-- 체력 텍스트 색상
		local htColor = htDB.color
		local htColorType = htColor and htColor.type or "custom"
		if isDead then
			htText:SetTextColor(0.5, 0.5, 0.5)
		elseif htColorType == "class_color" and dummy.class then
			local r, g, b = GetClassColor(dummy.class)
			htText:SetTextColor(r, g, b)
		elseif htColorType == "custom" and htColor and htColor.rgb then
			htText:SetTextColor(htColor.rgb[1], htColor.rgb[2], htColor.rgb[3], 1)
		elseif htColorType == "reaction_color" then
			htText:SetTextColor(0.0, 1.0, 0.0)
		elseif htColorType == "power_color" then
			htText:SetTextColor(0.0, 0.55, 1.0)
		elseif htColorType == "health_gradient" then
			local hp = healthPct
			if hp > 0.5 then htText:SetTextColor((1-hp)*2, 1, 0)
			else htText:SetTextColor(1, hp*2, 0) end
		else
			htText:SetTextColor(1, 1, 1)
		end
		local htPos = htDB.position
		local htPt = (htPos and htPos.point) or "RIGHT"
		local htRel = (htPos and htPos.relativePoint) or "CENTER"
		local htX = (htPos and htPos.offsetX) or 0
		local htY = (htPos and htPos.offsetY) or 0
		htText:SetPoint(htPt, frame, htRel, htX, htY)
		frame._healthText = htText  -- [PREVIEW] 시뮬레이션 참조
		table.insert(frame._children, htText)
	end

	-- ===== 파워 텍스트 =====
	local ptDB = wdb.powerText
	if ptDB and ptDB.enabled ~= false and not isDead then
		local ptFont = ptDB.font
		local ptSize = (ptFont and ptFont.size) or 10
		local ptFlags = (ptFont and ptFont.outline) or "OUTLINE"
		local ptText = frame:CreateFontString(nil, "OVERLAY")
		ptText:SetFont(fontPath, math.max(6, ptSize), ptFlags)
		ptText:SetWordWrap(false) -- [FIX] 한 줄 강제
		ptText:SetMaxLines(1)
		-- 자원 텍스트 형식
		local ptFormat = ptDB.format or "percentage"
		local pPct = dummy.powerPct or 1
		local pText = math.floor(pPct * 100) .. "%"
		if ptFormat == "current" then pText = tostring(math.floor(1000 * pPct))
		elseif ptFormat == "current-max" then pText = math.floor(1000 * pPct) .. "/" .. "1000"
		elseif ptFormat == "deficit" then local d = 1000 - math.floor(1000 * pPct); pText = d > 0 and ("-" .. d) or ""
		elseif ptFormat == "current-percentage" then pText = math.floor(1000 * pPct) .. " (" .. math.floor(pPct * 100) .. "%)"
		end
		ptText:SetText(pText)
		-- 자원 텍스트 색상
		local ptColor = ptDB.color
		local ptColorType = ptColor and ptColor.type or "power_color"
		if ptColorType == "class_color" and dummy.class then
			local r, g, b = GetClassColor(dummy.class)
			ptText:SetTextColor(r, g, b)
		elseif ptColorType == "power_color" then
			-- 미리보기: 마나(파랑) 기본
			ptText:SetTextColor(0.0, 0.55, 1.0)
		elseif ptColorType == "custom" and ptColor and ptColor.rgb then
			ptText:SetTextColor(ptColor.rgb[1], ptColor.rgb[2], ptColor.rgb[3], 1)
		elseif ptColorType == "reaction_color" then
			ptText:SetTextColor(0.0, 1.0, 0.0)
		elseif ptColorType == "health_gradient" then
			local hp = healthPct
			if hp > 0.5 then ptText:SetTextColor((1-hp)*2, 1, 0)
			else ptText:SetTextColor(1, hp*2, 0) end
		else
			ptText:SetTextColor(1, 1, 1)
		end
		local ptPos = ptDB.position
		local ptPt = (ptPos and ptPos.point) or "BOTTOMRIGHT"
		local ptRel = (ptPos and ptPos.relativePoint) or "CENTER"
		local ptX = (ptPos and ptPos.offsetX) or 0
		local ptY = (ptPos and ptPos.offsetY) or 0
		ptText:SetPoint(ptPt, frame, ptRel, ptX, ptY)
		table.insert(frame._children, ptText)
	end

	-- ===== 레이드 아이콘 ===== (OVERLAY, sublevel 7 - 체력바 위)
	local riDB = wdb.raidIcon
	if riDB and riDB.enabled ~= false and not isDead then
		local riSize = (riDB.size and riDB.size[1]) or 16
		local riIcon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		riIcon:SetSize(riSize, riSize)
		riIcon:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
		riIcon:SetTexCoord(0, 0.25, 0, 0.25)
		local riPos = riDB.position
		local riPt = (riPos and riPos.point) or "TOP"
		local riRel = (riPos and riPos.relativePoint) or "TOP"
		local riX = (riPos and riPos.offsetX) or 0
		local riY = (riPos and riPos.offsetY) or 0
		riIcon:SetPoint(riPt, frame, riRel, riX, riY)
		table.insert(frame._children, riIcon)
	end

	-- ===== 역할 아이콘 =====
	local roleDB = wdb.roleIcon
	if roleDB and roleDB.enabled ~= false and dummy.role then
		local roleSize = (roleDB.size and roleDB.size[1]) or 14
		local roleIcon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		roleIcon:SetSize(roleSize, roleSize)
		local roleTex = [[Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES]]
		roleIcon:SetTexture(roleTex)
		if dummy.role == "TANK" then
			roleIcon:SetTexCoord(0, 19/64, 22/64, 41/64)
		elseif dummy.role == "HEALER" then
			roleIcon:SetTexCoord(20/64, 39/64, 1/64, 20/64)
		else -- DAMAGER
			roleIcon:SetTexCoord(20/64, 39/64, 22/64, 41/64)
		end
		local rolePos = roleDB.position
		local rolePt = (rolePos and rolePos.point) or "TOPRIGHT"
		local roleRel = (rolePos and rolePos.relativePoint) or "CENTER"
		local roleX = (rolePos and rolePos.offsetX) or 0
		local roleY = (rolePos and rolePos.offsetY) or 0
		roleIcon:SetPoint(rolePt, frame, roleRel, roleX, roleY)
		table.insert(frame._children, roleIcon)
	end

	-- ===== 리더 아이콘 =====
	local leaderDB = wdb.leaderIcon
	if leaderDB and leaderDB.enabled ~= false and dummy.leader then
		local lSize = (leaderDB.size and leaderDB.size[1]) or 14
		local leaderIcon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		leaderIcon:SetSize(lSize, lSize)
		leaderIcon:SetTexture([[Interface\GroupFrame\UI-Group-LeaderIcon]])
		local lPos = leaderDB.position
		local lPt = (lPos and lPos.point) or "TOPLEFT"
		local lRel = (lPos and lPos.relativePoint) or "CENTER"
		local lX = (lPos and lPos.offsetX) or 0
		local lY = (lPos and lPos.offsetY) or 12
		leaderIcon:SetPoint(lPt, frame, lRel, lX, lY)
		table.insert(frame._children, leaderIcon)
	end

	-- ===== 전투 아이콘 =====
	local combatDB = wdb.combatIcon
	if combatDB and combatDB.enabled ~= false and dummy.combat then
		local cSize = (combatDB.size and combatDB.size[1]) or 20
		local combatIcon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		combatIcon:SetSize(cSize, cSize)
		combatIcon:SetTexture([[Interface\CharacterFrame\UI-StateIcon]])
		combatIcon:SetTexCoord(0.5, 1, 0, 0.49) -- 전투 아이콘 (칼)
		local cPos = combatDB.position
		local cPt = (cPos and cPos.point) or "CENTER"
		local cRel = (cPos and cPos.relativePoint) or "CENTER"
		local cX = (cPos and cPos.offsetX) or 0
		local cY = (cPos and cPos.offsetY) or 0
		combatIcon:SetPoint(cPt, frame, cRel, cX, cY)
		table.insert(frame._children, combatIcon)
	end

	-- ===== 힐 예측 바 + 오버힐 글로우 ===== -- [PREVIEW]
	local hpDB = wdb.healthPrediction
	if hpDB and hpDB.enabled ~= false and dummy.healPct and dummy.healPct > 0 and not isDead and healthBar then
		local barW = unitW - inset * 2
		local barH = unitH - inset * 2 - powerH
		local healTotal = dummy.healPct
		local overhealAmt = math.max(0, (healthPct + healTotal) - 1) -- 1.0 초과분 = 오버힐
		local healVisible = math.min(healTotal, 1 - healthPct) -- 실제 회복 가능량

		-- 힐 예측 바 (초록 반투명)
		if healVisible > 0 then
			local healBar = frame:CreateTexture(nil, "ARTWORK", nil, 1)
			healBar:SetTexture(healthTexPath)
			local healColor = (hpDB.color) or { 0.0, 0.8, 0.2, 0.5 }
			healBar:SetVertexColor(healColor[1], healColor[2], healColor[3], healColor[4] or 0.5)
			healBar:SetHeight(barH)
			healBar:SetWidth(math.max(1, barW * healVisible))
			-- [PREVIEW] StatusBar 기반: frame 기준 절대 오프셋으로 배치
			if settings.reverseHealthFill then
				healBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(inset + barW * healthPct), -inset)
			else
				healBar:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + barW * healthPct, -inset)
			end
			table.insert(frame._children, healBar)
		end

		-- 오버힐 글로우 (체력바 끝에 발광 효과)
		if overhealAmt > 0 then
			local SL = ns.StyleLib
			local glowR, glowG, glowB = 0.3, 1.0, 0.5
			local accent = SL and SL.GetAccent and SL.GetAccent("UnitFrames")
			if accent and accent.from then
				glowR = accent.from[1] or glowR
				glowG = accent.from[2] or glowG
				glowB = accent.from[3] or glowB
			end
			local glowTex = frame:CreateTexture(nil, "ARTWORK", nil, 3)
			glowTex:SetTexture(FLAT)
			glowTex:SetVertexColor(glowR, glowG, glowB, 0.7)
			glowTex:SetSize(3, barH)
			if settings.reverseHealthFill then
				glowTex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
			else
				glowTex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
			end
			table.insert(frame._children, glowTex)
		end
	end

	-- ===== 보호막 바 (shieldBar) =====
	local shieldDB = wdb.shieldBar
	if shieldDB and shieldDB.enabled ~= false and dummy.shieldPct and dummy.shieldPct > 0 and not isDead and healthBar then
		local shieldTex = shieldDB.texture or FLAT
		local shieldColor = shieldDB.color or { 1, 1, 0, 0.4 }
		local shieldPct = math.min(dummy.shieldPct, 1)
		local shieldBar = frame:CreateTexture(nil, "ARTWORK", nil, 2)
		shieldBar:SetTexture(shieldTex)
		shieldBar:SetVertexColor(shieldColor[1], shieldColor[2], shieldColor[3], shieldColor[4] or 0.4)
		-- 체력바 끝에서 보호막 표시 (체력 채움의 오른쪽에 노란 바)
		local barW = unitW - inset * 2
		local shieldW = math.max(1, barW * shieldPct)
		shieldBar:SetHeight(unitH - inset * 2 - powerH)
		shieldBar:SetWidth(shieldW)
		-- [PREVIEW] StatusBar 기반: frame 기준 절대 오프셋
		if settings.reverseHealthFill then
			shieldBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(inset + barW * healthPct), -inset)
		else
			shieldBar:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + barW * healthPct, -inset)
		end
		table.insert(frame._children, shieldBar)
	end

	-- ===== 캐스트바 (시전중인 더미만) =====
	local castDB = wdb.castBar
	if castDB and castDB.enabled ~= false and dummy.casting and not isDead then
		local cbW = (castDB.size and castDB.size.width) or unitW
		local cbH = (castDB.size and castDB.size.height) or 20
		local castBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		castBar.isPreview = true
		castBar:UnregisterAllEvents()
		castBar:SetSize(cbW, cbH)
		-- [FIX] 캐스트바 위치 설정 반영
		local cbPos = castDB.position
		if cbPos then
			local cbPt = cbPos.point or "TOP"
			local cbRel = cbPos.relativePoint or "BOTTOM"
			local cbPX = cbPos.offsetX or 0
			local cbPY = cbPos.offsetY or -3
			castBar:SetPoint(cbPt, frame, cbRel, cbPX, cbPY)
		else
			castBar:SetPoint("TOP", frame, "BOTTOM", 0, -3)
		end
		local castBorderPx = (F and F.ScalePixel) and F:ScalePixel(1) or 1
		-- [FIX] 캐스트바 배경 텍스처 반영
		local cbBgTex = (castDB.colors and castDB.colors.backgroundTexture) or FLAT
		castBar:SetBackdrop({ bgFile = cbBgTex, edgeFile = FLAT, edgeSize = castBorderPx })
		local cbBgCol = (castDB.colors and castDB.colors.background) or { 0, 0, 0, 0.8 }
		castBar:SetBackdropColor(cbBgCol[1] or 0, cbBgCol[2] or 0, cbBgCol[3] or 0, cbBgCol[4] or 0.8)
		-- [FIX] 캐스트바 테두리 색상 DB 반영
		local cbBorderCol = (castDB.colors and castDB.colors.border) or (castDB.borderColor) or { 0, 0, 0, 1 }
		castBar:SetBackdropBorderColor(cbBorderCol[1] or 0, cbBorderCol[2] or 0, cbBorderCol[3] or 0, cbBorderCol[4] or 1)

		-- [PREVIEW] 캐스트바 StatusBar (애니메이션)
		local cbStatusBar = CreateFrame("StatusBar", nil, castBar)
		cbStatusBar:SetStatusBarTexture(castDB.texture or FLAT)
		local cbColors = castDB.colors
		local cbR, cbG, cbB = 0.2, 0.57, 0.5
		if cbColors and cbColors.interruptible then
			cbR = cbColors.interruptible[1] or cbR
			cbG = cbColors.interruptible[2] or cbG
			cbB = cbColors.interruptible[3] or cbB
		end
		cbStatusBar:SetStatusBarColor(cbR, cbG, cbB, 1)
		cbStatusBar:SetMinMaxValues(0, 1)
		cbStatusBar:SetValue(0)
		cbStatusBar:SetPoint("TOPLEFT", castBar, "TOPLEFT", 1, -1)
		cbStatusBar:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -1, 1)
		cbStatusBar:SetFrameLevel(castBar:GetFrameLevel() + 1)
		castBar._statusBar = cbStatusBar  -- [PREVIEW] 시뮬레이션 참조
		castBar._castDuration = 2.0 + math.random() * 1.5
		castBar._castStart = GetTime()

		-- 스펠 이름
		if castDB.showSpell ~= false then
			local spellCfg = castDB.spell
			local cbText = castBar:CreateFontString(nil, "OVERLAY")
			local cbFS = (spellCfg and spellCfg.size) or 11
			cbText:SetFont(fontPath, math.max(7, cbFS), "OUTLINE")
			-- [PREVIEW] 실제 spellId로 이름 표시
			local spellName = "주문 시전"
			if dummy.castSpellId then
				local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(dummy.castSpellId)
				if info and info.name then
					spellName = info.name
				end
			end
			cbText:SetText(spellName)
			-- [FIX] 캐스트바 스펠명 색상 DB 반영
			local spellCol = (spellCfg and spellCfg.color) or { 1, 1, 1 }
			cbText:SetTextColor(spellCol[1] or 1, spellCol[2] or 1, spellCol[3] or 1)
			cbText:SetPoint("LEFT", castBar, "LEFT", 3, 0)
		end

		-- 타이머
		local timerCfg = castDB.timer
		if timerCfg and timerCfg.enabled ~= false then
			local tText = castBar:CreateFontString(nil, "OVERLAY")
			local tFS = (timerCfg.size) or 11
			tText:SetFont(fontPath, math.max(7, tFS), "OUTLINE")
			tText:SetText("")  -- [PREVIEW] 시뮬레이션에서 갱신
			-- [FIX] 캐스트바 타이머 색상 DB 반영
			local timerCol = (timerCfg and timerCfg.color) or { 1, 1, 1 }
			tText:SetTextColor(timerCol[1] or 1, timerCol[2] or 1, timerCol[3] or 1)
			tText:SetPoint("RIGHT", castBar, "RIGHT", -3, 0)
			castBar._timerText = tText  -- [PREVIEW] 시뮬레이션 참조
		end

		-- 아이콘
		local iconCfg = castDB.icon
		if iconCfg and iconCfg.enabled ~= false and iconCfg.position ~= "none" then
			local cbIcon = castBar:CreateTexture(nil, "OVERLAY")
			cbIcon:SetSize(cbH, cbH)
			-- [PREVIEW] 실제 spellId 아이콘
			local iconTex = [[Interface\Icons\INV_Misc_QuestionMark]]
			if dummy.castSpellId then
				local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(dummy.castSpellId)
				if info and info.iconID then
					iconTex = info.iconID
				end
			end
			cbIcon:SetTexture(iconTex)
			cbIcon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
			if iconCfg.position == "right" then
				cbIcon:SetPoint("LEFT", castBar, "RIGHT", 1, 0)
			else
				cbIcon:SetPoint("RIGHT", castBar, "LEFT", -1, 0)
			end
		end

		frame._castBar = castBar
	end

	-- ===== 버프 아이콘 (CooldownFrame + 지속시간) ===== -- [PREVIEW]
	if not frame._auraIcons then frame._auraIcons = {} end
	local buffDB = wdb.buffs
	if buffDB and buffDB.enabled ~= false and not isDead then
		local buffScale = buffDB.scale or 1.0
		local bW = ((buffDB.size and buffDB.size.width) or 24) * buffScale
		local bH = ((buffDB.size and buffDB.size.height) or 24) * buffScale
		local bSpH = (buffDB.spacing and buffDB.spacing.horizontal) or 2
		local bPos = buffDB.position
		local bPt = (bPos and bPos.point) or "BOTTOMLEFT"
		local bRel = (bPos and bPos.relativePoint) or "TOPLEFT"
		local bX = (bPos and bPos.offsetX) or 0
		local bY = (bPos and bPos.offsetY) or 2
		local numBuffs = math.min(#DUMMY_BUFF_IDS, buffDB.maxIcons or 10)
		for bi = 1, numBuffs do
			local iconFrame = CreatePreviewAuraIcon(frame, bW, bH, DUMMY_BUFF_IDS[bi], false, bi)
			if bi == 1 then
				iconFrame:SetPoint(bPt, frame, bRel, bX, bY)
			else
				iconFrame:SetPoint("LEFT", frame._auraIcons[#frame._auraIcons], "RIGHT", bSpH, 0)
			end
			iconFrame:Show()
			table.insert(frame._auraIcons, iconFrame)
			table.insert(frame._children, iconFrame)
		end
	end

	-- ===== 디버프 아이콘 (CooldownFrame + 지속시간) ===== -- [PREVIEW]
	local debuffDB = wdb.debuffs
	if debuffDB and debuffDB.enabled ~= false and not isDead then
		local debuffScale = debuffDB.scale or 1.0
		local dW = ((debuffDB.size and debuffDB.size.width) or 24) * debuffScale
		local dH = ((debuffDB.size and debuffDB.size.height) or 24) * debuffScale
		local dSpH = (debuffDB.spacing and debuffDB.spacing.horizontal) or 2
		local dPos = debuffDB.position
		local dPt = (dPos and dPos.point) or "BOTTOMRIGHT"
		local dRel = (dPos and dPos.relativePoint) or "TOPRIGHT"
		local dX = (dPos and dPos.offsetX) or 0
		local dY = (dPos and dPos.offsetY) or 2
		local numDebuffs = math.min(#DUMMY_DEBUFF_IDS, debuffDB.maxIcons or 10)
		local debuffStartIdx = #frame._auraIcons  -- 버프 개수 오프셋
		for di = 1, numDebuffs do
			local iconFrame = CreatePreviewAuraIcon(frame, dW, dH, DUMMY_DEBUFF_IDS[di], true, debuffStartIdx + di)
			if di == 1 then
				iconFrame:SetPoint(dPt, frame, dRel, dX, dY)
			else
				iconFrame:SetPoint("RIGHT", frame._auraIcons[#frame._auraIcons], "LEFT", -dSpH, 0)
			end
			iconFrame:Show()
			table.insert(frame._auraIcons, iconFrame)
			table.insert(frame._children, iconFrame)
		end
	end

	-- ===== 직업 자원바 (classBar) =====
	local cbDB = wdb.classBar
	if cbDB and cbDB.enabled ~= false and unit == "player" then
		local cbSpacing = cbDB.spacing or 2
		local cbTexPath = cbDB.texture or FLAT
		local cbVertical = cbDB.verticalFill or false
		local cbSameSize = cbDB.sameSizeAsHealthBar
		local cbW = (cbSameSize and unitW) or (cbDB.size and cbDB.size.width) or 200
		local cbH = (cbDB.size and cbDB.size.height) or 6
		local cbPos = cbDB.position
		local cbPt = (cbPos and cbPos.point) or "BOTTOMLEFT"
		local cbRel = (cbPos and cbPos.relativePoint) or "TOPLEFT"
		local cbX = (cbPos and cbPos.offsetX) or 0
		local cbY = (cbPos and cbPos.offsetY) or 2

		-- 직업 자원 컨테이너 (BackdropTemplate: 테두리+배경 지원)
		local cbContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		cbContainer.isPreview = true
		cbContainer:UnregisterAllEvents()
		cbContainer:SetSize(cbW, cbH)
		cbContainer:SetPoint(cbPt, frame, cbRel, cbX, cbY)
		frame._classBarFrame = cbContainer
		table.insert(frame._children, cbContainer)

		-- 테두리 & 배경
		local cbBorder = cbDB.border
		local cbBg = cbDB.background
		local cbBorderEnabled = cbBorder and cbBorder.enabled ~= false
		local cbBgEnabled = cbBg and cbBg.enabled ~= false
		if cbBorderEnabled then
			local cbRawBorder = (cbBorder and cbBorder.size) or 1
			local cbBorderSize = (F and F.ScalePixel) and F:ScalePixel(cbRawBorder) or cbRawBorder
			local cbBorderColor = (cbBorder and cbBorder.color) or { 0, 0, 0, 1 }
			local cbBgColor = (cbBgEnabled and cbBg and cbBg.color) or { 0.05, 0.05, 0.05, 0.8 }
			cbContainer:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = cbBorderSize })
			cbContainer:SetBackdropColor(cbBgColor[1], cbBgColor[2], cbBgColor[3], cbBgColor[4] or 0.8)
			cbContainer:SetBackdropBorderColor(cbBorderColor[1], cbBorderColor[2], cbBorderColor[3], cbBorderColor[4] or 1)
		elseif cbBgEnabled then
			local cbBgColor = (cbBg and cbBg.color) or { 0.05, 0.05, 0.05, 0.8 }
			cbContainer:SetBackdrop({ bgFile = FLAT })
			cbContainer:SetBackdropColor(cbBgColor[1], cbBgColor[2], cbBgColor[3], cbBgColor[4] or 0.8)
		end

		-- 더미 세그먼트 (5개 = 콤보 포인트 등)
		local numSegments = 5
		local activeSegments = 3
		local segSpacing = cbSpacing
		local segW = (cbW - segSpacing * (numSegments - 1)) / numSegments
		for si = 1, numSegments do
			local seg = cbContainer:CreateTexture(nil, "ARTWORK")
			seg:SetTexture(cbTexPath)
			seg:SetSize(math.max(1, segW), cbH)
			if si == 1 then
				seg:SetPoint("LEFT", cbContainer, "LEFT", 0, 0)
			else
				seg:SetPoint("LEFT", cbContainer["_seg" .. (si - 1)], "RIGHT", segSpacing, 0)
			end
			-- 활성/비활성 색상
			if si <= activeSegments then
				-- [FIX] 클래스바 활성 색상: DB → 클래스 → 기본 노랑
				local activeCol = cbDB.activeColor
				if activeCol then
					seg:SetVertexColor(activeCol[1], activeCol[2], activeCol[3], activeCol[4] or 1)
				elseif dummy.class then
					local r, g, b = GetClassColor(dummy.class)
					seg:SetVertexColor(r, g, b, 1)
				else
					seg:SetVertexColor(1.0, 0.96, 0.41, 1)
				end
			else
				-- [FIX] 클래스바 비활성 색상 DB 반영
				local inactiveCol = cbDB.inactiveColor or { 0.15, 0.15, 0.15, 0.6 }
				seg:SetVertexColor(inactiveCol[1], inactiveCol[2], inactiveCol[3], inactiveCol[4] or 0.6)
			end
			cbContainer["_seg" .. si] = seg
			table.insert(frame._children, seg)
		end
	end

	frame:SetAlpha(frameAlpha)
end

-----------------------------------------------
-- 컨테이너 생성 -- [PREVIEW]
-----------------------------------------------
local function CreateContainer()
	if container then return container end

	local SL = ns.StyleLib
	container = CreateFrame("Frame", "DDingUI_UF_PreviewContainer", UIParent, "BackdropTemplate")
	container.isPreview = true -- [PREVIEW]
	container:UnregisterAllEvents() -- [PREVIEW]
	container:SetFrameStrata("DIALOG")
	container:SetClampedToScreen(true)
	Widgets:StylizeFrame(container, SL and SL.Colors.bg.main or { 0.08, 0.08, 0.08, 0.95 })

	-- 라벨
	local label = container:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
	label:SetPoint("TOP", 0, -4)
	label:SetText("미리보기")
	label:SetTextColor(0.5, 0.5, 0.5)
	container._label = label

	container:Hide()
	return container
end

-----------------------------------------------
-- 유닛별 프레임 수 -- [PREVIEW]
-----------------------------------------------
local UNIT_FRAME_COUNTS = {
	player = 1, target = 1, targettarget = 1,
	focus = 1, focustarget = 1, pet = 1,
	party = 1, -- [FIX] 그룹 프레임 미리보기: 대표 1프레임
	raid = 1, -- [FIX] 레이드 미리보기: 대표 1프레임
	boss = 3,
	arena = 3,
}

-----------------------------------------------
-- 유닛별 더미 데이터 -- [PREVIEW]
-----------------------------------------------
local function GetDummiesForUnit(unit)
	if unit == "party" then
		return PARTY_DUMMIES
	elseif unit == "raid" then
		return GetRaidDummies()
	elseif unit == "boss" then
		return BOSS_DUMMIES
	elseif unit == "arena" then
		return ARENA_DUMMIES
	else
		return { GetSingleDummy() }
	end
end

-----------------------------------------------
-- 유닛 이름 표시 -- [PREVIEW]
-----------------------------------------------
local UNIT_LABELS = {
	player = "플레이어", target = "대상", targettarget = "대상의 대상",
	focus = "주시 대상", focustarget = "주시 대상의 대상", pet = "소환수",
	party = "파티", raid = "공격대",
	boss = "우두머리", arena = "투기장",
}

-----------------------------------------------
-- Show -- [PREVIEW]
-----------------------------------------------
function Preview:Show(unit, optsFrame)
	if InCombatLockdown() then return end -- [PREVIEW] 전투 중 안전

	if optsFrame then
		optionsFrame = optsFrame
	end

	if not container then
		CreateContainer()
	end

	-- 같은 유닛이면 스킵
	if currentUnit == unit and container:IsShown() then return end
	currentUnit = unit

	RecycleFrames()

	local settings = ns.db[unit]
	if not settings then
		container:Hide()
		return
	end

	local count = UNIT_FRAME_COUNTS[unit] or 1
	local dummies = GetDummiesForUnit(unit)
	local sc = PREVIEW_SCALE

	local unitW = (settings.size and settings.size[1]) or 200
	local unitH = (settings.size and settings.size[2]) or 40

	-- 캐스트바 높이 계산
	local wdb = settings.widgets or {}
	local castDB = wdb.castBar
	local castH = 0
	if castDB and castDB.enabled ~= false then
		castH = (castDB.size and castDB.size.height or 20) + 3
	end
	local frameFullH = unitH + castH

	-- [FIX] 그룹 프레임: DB 성장방향/간격 반영 레이아웃
	local isGroup = (unit == "party" or unit == "raid")
	local isVertical = (unit == "boss" or unit == "arena")
	local growDir, colGrowDir, spacing, colSpacing
	if isGroup then
		growDir = settings.growDirection or "DOWN"
		colGrowDir = settings.columnGrowDirection or "RIGHT"
		spacing = settings.spacing or settings.spacingY or 4
		colSpacing = settings.spacingX or settings.groupSpacing or 4
	end

	-- 레이아웃 계산
	local cols, rows
	if isGroup then
		local upc = settings.unitsPerColumn or 5
		cols = math.ceil(count / upc)
		rows = math.min(count, upc)
	elseif isVertical then
		cols = 1
		rows = count
	else
		cols = count
		rows = 1
	end

	-- 그룹 프레임 성장방향별 사이즈 계산
	local contentW, contentH
	if isGroup then
		-- 1차 방향이 세로(DOWN/UP/V_CENTER)면 rows=프레임수, cols=열수
		local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
		if priIsVert then
			contentW = cols * unitW + math.max(0, cols - 1) * colSpacing
			contentH = rows * frameFullH + math.max(0, rows - 1) * spacing
		else
			-- 1차 방향이 가로(RIGHT/LEFT/H_CENTER)
			contentW = rows * unitW + math.max(0, rows - 1) * spacing
			contentH = cols * frameFullH + math.max(0, cols - 1) * colSpacing
		end
	else
		contentW = cols * unitW + (cols - 1) * PREVIEW_GAP
		contentH = rows * frameFullH + (rows - 1) * PREVIEW_GAP
	end
	local panelW = (contentW + PREVIEW_PAD * 2) * sc
	local panelH = (contentH + LABEL_HEIGHT + PREVIEW_PAD * 2) * sc

	container:SetSize(panelW, panelH)
	local dirLabel = isGroup and (" [" .. (growDir or "DOWN") .. "]") or ""
	container._label:SetText((UNIT_LABELS[unit] or unit) .. dirLabel .. " 미리보기")

	-- 프레임 생성 & 배치
	wipe(simFrames) -- [PREVIEW] 시뮬레이션 프레임 초기화
	for i = 1, count do
		local f = GetOrCreateFrame(i)
		f:SetScale(sc)
		f:SetParent(container)

		local dummy = dummies[i] or dummies[1]
		BuildFrameWidgets(f, unit, dummy)

		-- [PREVIEW] 시뮬레이션 상태 초기화
		InitPreviewSimState(f, dummy, unit)
		if f._sim then
			simFrames[#simFrames + 1] = f
		end

		f:ClearAllPoints()
		local baseX = PREVIEW_PAD * sc
		local baseY = -(LABEL_HEIGHT + PREVIEW_PAD) * sc

		if isGroup then
			-- DB 성장방향 기반 배치
			local upc = settings.unitsPerColumn or 5
			local priIdx = ((i - 1) % upc)    -- 1차 방향 인덱스
			local secIdx = math.floor((i - 1) / upc) -- 2차(열) 방향 인덱스
			local xOff, yOff = 0, 0
			local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")

			if priIsVert then
				-- 1차: 세로, 2차: 가로
				local ySign = (growDir == "UP") and -1 or 1
				local xSign = (colGrowDir == "LEFT") and -1 or 1
				yOff = priIdx * (frameFullH + spacing) * ySign
				xOff = secIdx * (unitW + colSpacing) * xSign
				if growDir == "UP" then
					-- UP: 아래에서 위로 → 기준을 하단으로
					baseY = -(LABEL_HEIGHT + PREVIEW_PAD + contentH) * sc
					yOff = -yOff
				end
				if colGrowDir == "LEFT" then
					baseX = (PREVIEW_PAD + contentW) * sc
					xOff = -math.abs(xOff)
				end
			else
				-- 1차: 가로, 2차: 세로
				local xSign = (growDir == "LEFT") and -1 or 1
				local ySign = (colGrowDir == "UP") and -1 or 1
				xOff = priIdx * (unitW + spacing) * xSign
				yOff = secIdx * (frameFullH + colSpacing) * ySign
				if growDir == "LEFT" then
					baseX = (PREVIEW_PAD + contentW) * sc
					xOff = -math.abs(xOff)
				end
				if colGrowDir == "UP" then
					baseY = -(LABEL_HEIGHT + PREVIEW_PAD + contentH) * sc
					yOff = -math.abs(yOff)
				end
			end
			f:SetPoint("TOPLEFT", container, "TOPLEFT", baseX + xOff * sc, baseY - yOff * sc)
		else
			-- 기존: 보스/투기장/단일
			local col = ((i - 1) % cols)
			local row = math.floor((i - 1) / cols)
			local xOff = col * (unitW + PREVIEW_GAP)
			local yOff = row * (frameFullH + PREVIEW_GAP)
			f:SetPoint("TOPLEFT", container, "TOPLEFT", baseX + xOff * sc, baseY - yOff * sc)
		end
		f:Show()
	end

	-- 위치 배치: 옵션 창 기준
	container:ClearAllPoints()
	if optionsFrame then
		if unit == "party" or unit == "raid" then
			-- 파티/레이드: 상단
			container:SetPoint("BOTTOMLEFT", optionsFrame, "TOPLEFT", 0, 8)
		else
			-- 단일/보스/투기장: 왼쪽
			container:SetPoint("TOPRIGHT", optionsFrame, "TOPLEFT", -8, 0)
		end
	end

	container:Show()

	-- [PREVIEW] 시뮬레이션 시작
	StartPreviewSim()
end

-----------------------------------------------
-- Hide -- [PREVIEW]
-----------------------------------------------
function Preview:Hide()
	StopPreviewSim() -- [PREVIEW] 시뮬레이션 중지
	if container then
		container:Hide()
	end
	currentUnit = nil
end

-----------------------------------------------
-- Refresh -- [PREVIEW]
-- 설정 변경 시 현재 미리보기 즉시 갱신
-----------------------------------------------
function Preview:Refresh()
	if not container or not currentUnit or not container:IsShown() then return end

	-- [FIX] 전체 다시 그리기: Show를 재호출 (currentUnit 초기화 후)
	-- 이렇게 하면 레이아웃 + 위젯 + 컨테이너 크기가 모두 일관성 있게 갱신됨
	local unit = currentUnit
	currentUnit = nil -- Show()의 same-unit 스킵 방지
	self:Show(unit)
end

-----------------------------------------------
-- SetOptionsFrame -- [PREVIEW]
-- Options.lua에서 mainFrame 참조 전달
-----------------------------------------------
function Preview:SetOptionsFrame(frame)
	optionsFrame = frame
end

-----------------------------------------------
-- GetCurrentUnit -- [PREVIEW]
-----------------------------------------------
function Preview:GetCurrentUnit()
	return currentUnit
end
