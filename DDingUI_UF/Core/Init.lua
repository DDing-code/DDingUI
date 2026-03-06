--[[
	ddingUI UnitFrames - Independent Unit Frames for WoW 12.0
	Core/Init.lua - Addon initialization and namespace setup
]]

local ADDON_NAME, ns = ...

-----------------------------------------------
-- Addon Namespace Setup
-----------------------------------------------

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "1.0.0"

-- Initialize tables
ns.db = {}
ns.defaults = {}
ns.frames = {}
ns.headers = {}

-- oUF reference (optional — standalone mode에서는 nil)
local oUF = ns.oUF

-----------------------------------------------
-- Utility Functions
-----------------------------------------------

ns.Debug = function(...)
	if ns.db and ns.db.debug then
		local SL = _G.DDingUI_StyleLib
		local prefix = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("UnitFrames", "UnitFrames") or "|cffffffffDDing|r|cffffa300UI|r |cff4dd973UnitFrames|r: " -- [STYLE]
		print(prefix, ...)
	end
end

ns.Print = function(...)
	local SL = _G.DDingUI_StyleLib
	local prefix = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("UnitFrames", "UnitFrames") or "|cffffffffDDing|r|cffffa300UI|r |cff4dd973UnitFrames|r: " -- [STYLE]
	print(prefix, ...)
end

-----------------------------------------------
-- Saved Variables Initialization
-----------------------------------------------

-- Note: DB initialization is now handled by Profiles.lua
-- This provides profile management (create, switch, import/export)

-----------------------------------------------
-- Event Frame
-----------------------------------------------

local eventFrame = CreateFrame("Frame")
local events = {}

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if events[event] then
		for _, callback in ipairs(events[event]) do
			callback(event, ...)
		end
	end
end)

ns.RegisterEvent = function(event, callback)
	if not events[event] then
		events[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(events[event], callback)
end

ns.UnregisterEvent = function(event, callback)
	if events[event] then
		for i, cb in ipairs(events[event]) do
			if cb == callback then
				table.remove(events[event], i)
				break
			end
		end
		if #events[event] == 0 then
			events[event] = nil
			eventFrame:UnregisterEvent(event)
		end
	end
end

-----------------------------------------------
-- Addon Initialization
-----------------------------------------------

-- [PERF] 손상된 Mover 위치 데이터 정리 (ADDON_LOADED → PLAYER_LOGIN으로 이동됨)
local function CleanCorruptedMovers()
	if not (ns.db and ns.db.movers) then return end
	local MOVER_NAME_TO_UNIT = {
		Player = "player", Target = "target", ToT = "targettarget",
		Focus = "focus", FocusTarget = "focustarget", Pet = "pet",
		Boss = "boss", Arena = "arena", Party = "party", Raid = "raid",
	}
	for key, str in pairs(ns.db.movers) do
		if str == "TOPLEFT,UIParent,TOPLEFT,0,0" then
			ns.db.movers[key] = nil
			local unitKey = MOVER_NAME_TO_UNIT[key]
			if unitKey and ns.db[unitKey] and ns.defaults[unitKey] and ns.defaults[unitKey].position then
				ns.db[unitKey].position = CopyTable(ns.defaults[unitKey].position)
			end
			if key == "Castbar" then
				local cbDef = ns.defaults.player and ns.defaults.player.castbar and ns.defaults.player.castbar.position
				if ns.db.player and ns.db.player.castbar and cbDef then
					ns.db.player.castbar.position = CopyTable(cbDef)
				end
			end
			local powerUnit = key:match("^(%w+) Power$")
			if powerUnit then
				powerUnit = powerUnit:lower()
				local defDP = ns.defaults[powerUnit] and ns.defaults[powerUnit].widgets
					and ns.defaults[powerUnit].widgets.powerBar and ns.defaults[powerUnit].widgets.powerBar.detachedPosition
				if defDP and ns.db[powerUnit] and ns.db[powerUnit].widgets and ns.db[powerUnit].widgets.powerBar then
					ns.db[powerUnit].widgets.powerBar.detachedPosition = CopyTable(defDP)
				end
			end
			ns.Debug("Mover: corrupted position cleaned for", key)
		end
	end
end

-- [PERF] 색상 복원 (ADDON_LOADED → PLAYER_LOGIN으로 이동됨)
local function RestoreColors()
	if not (ddingUI_UFDB and ddingUI_UFDB.global and ddingUI_UFDB.global.colors and ns.Colors) then return end
	for category, data in pairs(ddingUI_UFDB.global.colors) do
		if type(data) == "table" then
			if not ns.Colors[category] then ns.Colors[category] = {} end
			for k, v in pairs(data) do
				if type(v) == "table" then
					ns.Colors[category][k] = { v[1], v[2], v[3], v[4] }
				else
					ns.Colors[category][k] = v
				end
			end
		end
	end
	-- Constants.POWER_COLORS에 동기화
	if ns.Colors.power and ns.Constants and ns.Constants.POWER_COLORS then
		for token, rgba in pairs(ns.Colors.power) do
			if type(rgba) == "table" then
				ns.Constants.POWER_COLORS[token] = { rgba[1], rgba[2], rgba[3] }
			end
		end
	end
	-- [FIX] Constants.REACTION_COLORS에 동기화
	if ns.Colors.reaction and ns.Constants and ns.Constants.REACTION_COLORS then
		local rc = ns.Colors.reaction
		if rc.friendly then
			for i = 5, 8 do ns.Constants.REACTION_COLORS[i] = { rc.friendly[1], rc.friendly[2], rc.friendly[3] } end
		end
		if rc.neutral then
			ns.Constants.REACTION_COLORS[4] = { rc.neutral[1], rc.neutral[2], rc.neutral[3] }
		end
		if rc.hostile then
			for i = 1, 3 do ns.Constants.REACTION_COLORS[i] = { rc.hostile[1], rc.hostile[2], rc.hostile[3] } end
		end
	end
	-- [FIX] oUF.colors.tapped 동기화 (oUF 로드 시에만)
	if oUF and ns.Colors and ns.Colors.reaction and ns.Colors.reaction.tapped and oUF.colors then
		local t = ns.Colors.reaction.tapped
		if oUF.colors.tapped and oUF.colors.tapped.SetRGBA then
			oUF.colors.tapped:SetRGBA(t[1], t[2], t[3], 1)
		elseif oUF.CreateColor then
			oUF.colors.tapped = oUF:CreateColor(t[1], t[2], t[3])
		end
	end
	-- [FIX] CASTBAR 색상 동기화
	if ns.Colors.castBar and ns.Constants then
		if ns.Colors.castBar.interruptible then
			local c = ns.Colors.castBar.interruptible
			ns.Constants.CASTBAR_COLOR = { c[1], c[2], c[3] }
		end
		if ns.Colors.castBar.nonInterruptible then
			local c = ns.Colors.castBar.nonInterruptible
			ns.Constants.CASTBAR_NOINTERRUPT_COLOR = { c[1], c[2], c[3] }
		end
	end
	-- oUF.colors.power 동기화 (oUF 로드 시에만)
	if oUF and oUF.colors and oUF.colors.power and ns.Colors and ns.Colors.power then
		for token, rgba in pairs(ns.Colors.power) do
			if type(rgba) == "table" then
				local existing = oUF.colors.power[token]
				if existing and existing.SetRGBA then
					existing:SetRGBA(rgba[1], rgba[2], rgba[3], 1)
				else
					oUF.colors.power[token] = oUF:CreateColor(rgba[1], rgba[2], rgba[3])
				end
			end
		end
	end
end

-----------------------------------------------
-- [PERF] 로딩 최적화: BuildDefaults 래핑 (동기 초기화)
--
-- 핵심: Config.lua에서 ns.defaults 구축(60+ CopyDeep)을 BuildDefaults() 함수로 래핑
--       → 파일 파싱 시점의 ~200-400ms 제거
--
-- 초기화 순서:
--   ADDON_LOADED → DB 초기화 (Config, Profiles, Migrations)
--   PLAYER_LOGIN → 프레임 생성 + 모듈 초기화
--   PLAYER_ENTERING_WORLD → 개인 유닛 FullRefresh + GroupFrames 리프레시
-----------------------------------------------

local CreateMinimapButton -- forward declaration
local InitFlightHide -- forward declaration

local function OnAddonLoaded(event, addon)
	if addon ~= ADDON_NAME then return end

	-- Phase 1: DB 초기화 (ADDON_LOADED에서 SavedVariables 사용 가능)
	if ns.Config and ns.Config.Initialize then
		ns.Config:Initialize()
	end

	if ns.Profiles and ns.Profiles.Initialize then
		ns.Profiles:Initialize()
	end

	-- [FIX] 마이그레이션: Profiles 후에 실행해야 ns.db가 실제 SavedVars를 가리킴
	if ns.Config and ns.Config.RunMigrations then
		ns.Config:RunMigrations()
	end

	-- 숫자 축약 config 빌드 (ns.db.numberFormat + ns.db.decimalLength 적용)
	if ns.BuildAbbreviateConfig then
		ns.BuildAbbreviateConfig()
	end

	-- [FIX] 미니맵 버튼: ADDON_LOADED에서 생성 (AddonCompartment 정렬 통일)
	CreateMinimapButton()
end

-----------------------------------------------
-- [12.0.1] Minimap Button (LibDBIcon)
-----------------------------------------------

CreateMinimapButton = function()
	local LDB = LibStub("LibDataBroker-1.1", true)
	local LibDBIcon = LibStub("LibDBIcon-1.0", true)

	if not LDB or not LibDBIcon then return end

	-- minimap 설정이 없으면 기본값 생성
	if not ns.db.minimap then
		ns.db.minimap = { hide = false }
	end

	local dataObj = LDB:NewDataObject(ADDON_NAME, {
		type = "launcher",
		icon = "Interface\\AddOns\\DDingUI_UF\\logo",
		label = "DDingUI UF",
		OnClick = function(_, button)
			if button == "LeftButton" then
				if ns.Options then
					ns.Options:Toggle()
				end
			elseif button == "RightButton" then
				if ns.Mover then
					if ns.db.locked == false then
						ns.db.locked = true
						ns.Mover:LockAll()
						if ns.Update then ns.Update:DisableEditMode() end
					else
						ns.db.locked = false
						ns.Mover:UnlockAll()
						if ns.Update then ns.Update:EnableEditMode() end
					end
				end
			end
		end,
		OnTooltipShow = function(tooltip)
			local SL = _G.DDingUI_StyleLib -- [STYLE]
			local title = (SL and SL.CreateAddonTitle) and SL.CreateAddonTitle("UnitFrames", "UnitFrames") or "|cffffffffDDing|r|cffffa300UI|r UnitFrames"
			tooltip:SetText(title)
			tooltip:AddLine("|cffffffffLeft-click|r  Open settings", 0.7, 0.7, 0.7)
			tooltip:AddLine("|cffffffffRight-click|r  Toggle edit mode", 0.7, 0.7, 0.7)
		end,
	})

	LibDBIcon:Register(ADDON_NAME, dataObj, ns.db.minimap)
end

local function OnPlayerLogin()
	-- Phase 2: 프레임 생성 + 모듈 초기화 (PLAYER_LOGIN에서 유닛 데이터 사용 가능)
	if ns.Functions and ns.Functions.UpdatePixelScale then
		ns.Functions:UpdatePixelScale()
	end

	CleanCorruptedMovers()
	RestoreColors()

	if ns.Spawn and ns.Spawn.Initialize then
		ns.Spawn:Initialize()
	end

	if ns.HideBlizzard then
		ns.HideBlizzard:Apply()
	end

	if ns.Mover and ns.Mover.Initialize then
		ns.Mover:Initialize()
	end

	if ns.Options and ns.Options.Initialize then
		ns.Options:Initialize()
	end

	-- Deferred modules (프레임 생성 후 초기화)
	if ns.ClickCasting and ns.ClickCasting.Initialize then
		ns.ClickCasting:Initialize()
	end
	if ns.TargetedSpells and ns.TargetedSpells.Initialize then
		ns.TargetedSpells:Initialize()
	end
	if ns.MyBuffIndicators and ns.MyBuffIndicators.Initialize then
		ns.MyBuffIndicators:Initialize()
	end


	ns.Print("v" .. ns.VERSION .. " loaded")

	-- MediaChanged 콜백 등록 (폰트/텍스처 변경 시 갱신)
	local SL = _G.DDingUI_StyleLib
	if SL and SL.RegisterCallback then
		SL.RegisterCallback(ns, "MediaChanged", function()
			-- 전역 참조 갱신
			ns.SL = _G.DDingUI_StyleLib
			-- standalone 프레임 갱신
			C_Timer.After(0.1, function()
				if ns.SUF and ns.ElementDrivers then
					for _, frame in ipairs(ns.SUF.allFrames) do
						if frame:IsVisible() and frame.unit then
							ns.ElementDrivers:UpdateAll(frame)
						end
					end
				end
				-- oUF 프레임 갱신 (폴백)
				for _, frame in pairs(ns.frames) do
					if frame.UpdateAllElements then
						frame:UpdateAllElements("MediaChanged")
					end
				end
				local GF = ns.GroupFrames
				if GF and GF.headersInitialized then
					GF:RefreshAll()
				end
			end)
		end)
	end

	-- FlightHide 시스템 초기화
	InitFlightHide()
end

-----------------------------------------------
-- [FLIGHTHIDE] 비행/탑승/비히클 시 UF 숨기기
-----------------------------------------------

local FlightHide = {}
ns.FlightHide = FlightHide
FlightHide.isActive = false
FlightHide._hiding = false
FlightHide._currentAlpha = 1

local fh_wasHidden = false
local fh_currentAlpha = 1
local fh_targetAlpha = 1
local fh_FADE_DURATION = 0.5
local fh_CHECK_INTERVAL = 0.5
local fh_checkElapsed = 0
local fh_onUpdateFrame = nil
local abs = math.abs

local function FH_ShouldHide()
	local db = ns.db
	if not db then return false end
	if db.hideOutsideInstanceOnly then
		local _, instanceType = IsInInstance()
		if instanceType and instanceType ~= "none" then
			return false
		end
	end
	if db.hideWhileFlying and IsFlying() then return true end
	if db.hideWhileMounted and IsMounted() then return true end
	if db.hideInVehicle and UnitInVehicle("player") then return true end
	return false
end

local function FH_AnyEnabled()
	local db = ns.db
	if not db then return false end
	return db.hideWhileFlying or db.hideWhileMounted or db.hideInVehicle
end

local function FH_ApplyAlpha(alpha)
	fh_currentAlpha = alpha
	FlightHide._currentAlpha = alpha
	for _, frame in pairs(ns.frames) do
		if frame.SetAlpha then
			frame:SetAlpha(alpha)
		end
		-- 분리형 파워바: SetParent(UIParent)이라 부모 alpha 전파 안됨
		if frame._powerDetached and frame.Power and frame.Power.SetAlpha then
			frame.Power:SetAlpha(alpha)
			if frame.Power.backdrop and frame.Power.backdrop.SetAlpha then
				frame.Power.backdrop:SetAlpha(alpha)
			end
		end
	end
	-- GroupFrames (파티/레이드 헤더)
	local GF = ns.GroupFrames
	if GF then
		if GF.partyHeader and GF.partyHeader.SetAlpha then
			GF.partyHeader:SetAlpha(alpha)
		end
		if GF.raidHeaders then
			for _, rh in pairs(GF.raidHeaders) do
				if rh and rh.SetAlpha then rh:SetAlpha(alpha) end
			end
		end
		-- [FIX] 개별 그룹 프레임 알파도 복원 (Range 타이머가 0으로 고착시키는 것 방지)
		if alpha >= 1 and GF.allFrames then
			for _, gfFrame in pairs(GF.allFrames) do
				if gfFrame and gfFrame.SetAlpha then
					gfFrame:SetAlpha(gfFrame.gfInRange == false and 0.55 or 1.0)
				end
			end
		end
	end
end

local function FH_OnUpdate(_, elapsed)
	if not FH_AnyEnabled() then
		if fh_currentAlpha < 1 or FlightHide.isActive then
			FlightHide.isActive = false
			FlightHide._hiding = false
			fh_targetAlpha = 1
			FH_ApplyAlpha(1)
		else
			if fh_onUpdateFrame then
				fh_onUpdateFrame:SetScript("OnUpdate", nil)
			end
			return
		end
	else
		fh_checkElapsed = fh_checkElapsed + elapsed
		if fh_checkElapsed >= fh_CHECK_INTERVAL then
			fh_checkElapsed = 0
			local shouldHide = FH_ShouldHide()
			if shouldHide and not fh_wasHidden then
				fh_wasHidden = true
				fh_targetAlpha = 0
				FlightHide._hiding = true
			elseif not shouldHide and fh_wasHidden then
				fh_wasHidden = false
				fh_targetAlpha = 1
				FlightHide.isActive = false
				FlightHide._hiding = false
				FH_ApplyAlpha(1)
			end
		end
	end

	-- Smooth interpolation
	if fh_currentAlpha ~= fh_targetAlpha then
		local speed = elapsed / fh_FADE_DURATION
		local diff = fh_targetAlpha - fh_currentAlpha
		if abs(diff) <= speed then
			fh_currentAlpha = fh_targetAlpha
		else
			fh_currentAlpha = fh_currentAlpha + (diff > 0 and speed or -speed)
		end
		FH_ApplyAlpha(fh_currentAlpha)
		if fh_currentAlpha == 0 then
			FlightHide.isActive = true
		end
	end
end

function FlightHide:EnsureOnUpdate()
	if not fh_onUpdateFrame then
		fh_onUpdateFrame = CreateFrame("Frame")
	end
	fh_onUpdateFrame:SetScript("OnUpdate", FH_OnUpdate)
end

function FlightHide:ForceShow()
	fh_wasHidden = false
	fh_currentAlpha = 1
	fh_targetAlpha = 1
	FlightHide.isActive = false
	FlightHide._hiding = false
	FH_ApplyAlpha(1)
	if fh_onUpdateFrame then
		fh_onUpdateFrame:SetScript("OnUpdate", nil)
	end
end

InitFlightHide = function()
	if FH_AnyEnabled() then
		FlightHide:EnsureOnUpdate()
	end
end

local function OnPlayerEnteringWorld()
	-- Phase 3: 모든 프레임 FullRefresh
	C_Timer.After(0.1, function()
		-- 개인 유닛 프레임 갱신
		-- standalone 모드
		if ns.SUF and ns.ElementDrivers then
			for _, frame in ipairs(ns.SUF.allFrames) do
				if frame:IsVisible() and frame.unit and UnitExists(frame.unit) then
					ns.ElementDrivers:UpdateAll(frame)
				end
			end
		end
		-- oUF 프레임 갱신 (폴백)
		for _, frame in pairs(ns.frames) do
			if frame.UpdateAllElements then
				frame:UpdateAllElements("OnPlayerEnteringWorld")
			end
		end
		-- GroupFrames 리프레시 (헤더 자식 생성 대기 후)
		local GF = ns.GroupFrames
		if GF and GF.headersInitialized then
			GF:RebuildUnitFrameMap()
			GF:RefreshAll()
		end
	end)
end

ns.RegisterEvent("ADDON_LOADED", OnAddonLoaded)
ns.RegisterEvent("PLAYER_LOGIN", OnPlayerLogin)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)

-- [FIX] 파티/레이드 구성 변경 시 DB 설정 재적용 (쓰로틀: 1초)
-- 새 파티원이 추가되면 CreateNameText 하드코딩 값만 적용 → UpdateText로 DB 값 덮어쓰기
local lastGroupRefresh = 0
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
	local now = GetTime()
	if now - lastGroupRefresh < 1 then return end
	lastGroupRefresh = now
	C_Timer.After(0.2, function()
		-- 개인 유닛 프레임 설정 재적용
		if ns.Update then
			ns.Update:RefreshPartyFrames()
			ns.Update:RefreshRaidFrames()
		end
		-- GroupFrames: 미초기화 자식 탐색 + unitFrameMap 리빌드 + 전체 리프레시
		local GF = ns.GroupFrames
		if GF and GF.headersInitialized then
			-- [FIX] 새 파티/레이드원 추가 시 SecureGroupHeaderTemplate이 자식 생성
			-- → 미초기화 자식을 탐색하여 초기화
			if GF.InitializeAllChildren then
				if GF.partyHeader then
					GF:InitializeAllChildren(GF.partyHeader)
				end
				if GF.raidHeaders then
					for _, rh in pairs(GF.raidHeaders) do
						GF:InitializeAllChildren(rh)
					end
				end
			end
			GF:RebuildUnitFrameMap()
			GF:RefreshAll()
		end
	end)
end)

-- UI 스케일 변경 시 PixelPerfect 재계산
-- [FIX] 전투 중 SetSize() taint 방지: 전투 종료 후 지연 실행
ns.RegisterEvent("UI_SCALE_CHANGED", function()
	if ns.Functions and ns.Functions.UpdatePixelScale then
		ns.Functions:UpdatePixelScale()
	end
	local function doRefresh()
		if ns.Update and ns.Update.RefreshAllFrames then
			ns.Update:RefreshAllFrames()
		end
	end
	if InCombatLockdown() then
		ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
			ns.UnregisterEvent("PLAYER_REGEN_ENABLED")
			C_Timer.After(0.1, doRefresh)
		end)
	else
		C_Timer.After(0.1, doRefresh)
	end
end)

-----------------------------------------------
-- [MYTHIC-RAID] 난이도 감지 시스템
-----------------------------------------------

local function DetectRaidDifficulty()
	local _, _, difficultyID = GetInstanceInfo()
	local wasMythic = ns._mythicRaidActive
	ns._mythicRaidActive = (difficultyID == 16)  -- 16 = 신화 레이드

	if wasMythic ~= ns._mythicRaidActive then
		-- 난이도 변경됨 → 레이아웃 전환
		local function ApplyMythicSwitch()
			local GF = ns.GroupFrames
			if GF and GF.ApplyRaidLayoutFromDB then
				GF:ApplyRaidLayoutFromDB(GF:GetActiveRaidDB())
			end
		end
		if not InCombatLockdown() then
			ApplyMythicSwitch()
		else
			ns._pendingRaidLayoutUpdate = true
		end
	end
end

-- 초기 감지 (PLAYER_ENTERING_WORLD는 이미 등록됨, 여기서 후처리)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	C_Timer.After(0.5, DetectRaidDifficulty)
end)

-- 실시간 난이도 변경 감지
ns.RegisterEvent("PLAYER_DIFFICULTY_CHANGED", function()
	C_Timer.After(0.5, DetectRaidDifficulty)
end)

-- 인스턴스 전환 감지
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
	C_Timer.After(0.5, DetectRaidDifficulty)
end)

-- 전투 종료 시 대기 중인 레이아웃 업데이트 적용
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if ns._pendingRaidLayoutUpdate then
		ns._pendingRaidLayoutUpdate = false
		C_Timer.After(0.1, function()
			local GF = ns.GroupFrames
			if GF and GF.ApplyRaidLayoutFromDB then
				GF:ApplyRaidLayoutFromDB(GF:GetActiveRaidDB())
			end
		end)
	end
end)

-----------------------------------------------
-- Slash Commands
-----------------------------------------------

SLASH_DDINGUI_UF1 = "/duf"
SLASH_DDINGUI_UF2 = "/ddinguf"

SlashCmdList["DDINGUI_UF"] = function(msg)
	local cmd, arg1, arg2 = msg:match("^(%S+)%s*(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		-- Open options panel
		if ns.Options then
			ns.Options:Toggle()
		end
	elseif cmd == "help" then
		ns.Print("명령어:")
		ns.Print("  /duf - 옵션 패널 열기")
		ns.Print("  /duf unlock|edit - 편집모드 ON (ESC: 취소, Done: 저장)")
		ns.Print("  /duf lock - 편집모드 OFF")
		ns.Print("  /duf reset - 설정 초기화")
		ns.Print("  /duf debug - 디버그 모드 토글")
		ns.Print("  /duf diag - 진단 정보 출력")
		ns.Print("  /duf profile list - 프로필 목록")
		ns.Print("  /duf profile switch <이름> - 프로필 전환")
		ns.Print("  /duf profile new <이름> - 프로필 생성")
	elseif cmd == "reset" then
		if ns.Profiles then
			ns.Profiles:ResetCurrent()
		else
			ddingUI_UFDB = nil
			ReloadUI()
		end
	elseif cmd == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print("디버그:", ns.db.debug and "ON" or "OFF")
	elseif cmd == "lock" then
		ns.db.locked = true
		if ns.Mover then ns.Mover:LockAll() end
		if ns.Update then ns.Update:DisableEditMode() end
		ns.Print("편집모드 OFF")
	elseif cmd == "unlock" or cmd == "edit" then -- [MOVER] /duf edit 별칭
		ns.db.locked = false
		if ns.Mover then ns.Mover:UnlockAll() end
		if ns.Update then ns.Update:EnableEditMode() end
		ns.Print("편집모드 ON - 드래그하여 이동 | ESC: 취소 | Done: 저장")
	elseif cmd == "diag" then
		ns.Print("=== ddingUI UF 진단 ===")
		-- 1. 핵심 모듈 체크
		local modules = { "Config", "Constants", "Functions", "Profiles", "Update", "Layout", "Spawn", "Widgets", "Options", "Mover", "HideBlizzard" }
		local loaded = {}
		local missing = {}
		for _, m in ipairs(modules) do
			if ns[m] then
				table.insert(loaded, m)
			else
				table.insert(missing, m)
			end
		end
		ns.Print("모듈 로드: " .. #loaded .. "/" .. #modules)
		if #missing > 0 then
			ns.Print("|cffff0000누락:|r " .. table.concat(missing, ", "))
		end

		-- 2. ns.db 상태
		if ns.db then
			local unitKeys = {}
			for k, v in pairs(ns.db) do
				if type(v) == "table" then
					table.insert(unitKeys, k)
				end
			end
			ns.Print("ns.db 유닛: " .. table.concat(unitKeys, ", "))
		else
			ns.Print("|cffff0000ns.db가 nil!|r")
		end

		-- 3. ns.frames 상태
		local frameCount = 0
		local frameList = {}
		for k, v in pairs(ns.frames) do
			frameCount = frameCount + 1
			local shown = v:IsShown() and "O" or "X"
			local unit = v.unit or "nil"
			table.insert(frameList, k .. "(" .. unit .. "," .. shown .. ")")
		end
		ns.Print("프레임: " .. frameCount .. "개")
		if frameCount > 0 then
			ns.Print("  " .. table.concat(frameList, ", "))
		else
			ns.Print("|cffff0000프레임 없음! Spawn 실패?|r")
		end

		-- 4. ns.headers 상태
		local headerCount = 0
		local headerList = {}
		for k, v in pairs(ns.headers) do
			headerCount = headerCount + 1
			local childCount = 0
			if v.GetChildren then
				childCount = select("#", v:GetChildren())
			end
			table.insert(headerList, k .. "(" .. childCount .. "children)")
		end
		ns.Print("헤더: " .. headerCount .. "개")
		if headerCount > 0 then
			ns.Print("  " .. table.concat(headerList, ", "))
		end

		-- 5. Update 함수 존재 체크
		if ns.Update then
			local funcs = { "UpdateHealth", "UpdateSize", "UpdatePower", "UpdateCastBar", "UpdateTexts", "UpdateAuras", "RefreshFrame", "RefreshAllFrames" }
			local existFuncs = {}
			local missingFuncs = {}
			for _, fn in ipairs(funcs) do
				if ns.Update[fn] then
					table.insert(existFuncs, fn)
				else
					table.insert(missingFuncs, fn)
				end
			end
			if #missingFuncs > 0 then
				ns.Print("|cffff0000Update 함수 누락:|r " .. table.concat(missingFuncs, ", "))
			else
				ns.Print("Update 함수: 모두 정상 (" .. #existFuncs .. "개)")
			end
		end

		-- 6. GroupFrames 상태
		local GF = ns.GroupFrames
		if GF then
			ns.Print("GroupFrames: init=" .. tostring(GF.initialized) .. " headers=" .. tostring(GF.headersInitialized))
			ns.Print("  allFrames: " .. #GF.allFrames .. "개")
			local mapCount = 0
			for u, f in pairs(GF.unitFrameMap) do
				mapCount = mapCount + 1
			end
			ns.Print("  unitFrameMap: " .. mapCount .. "개")
			-- [FIX] 헤더별 자식 상태 상세 출력
			local function PrintHeaderChildren(label, header)
				if not header then return end
				local vis = header:IsVisible() and "VISIBLE" or "HIDDEN"
				local childCount = 0
				local initCount = 0
				local unitCount = 0
				for ci = 1, 40 do
					local child = header:GetAttribute("child" .. ci)
					if child then
						childCount = childCount + 1
						if child.gfInitialized then initCount = initCount + 1 end
						if child.unit then unitCount = unitCount + 1 end
					else
						break
					end
				end
				ns.Print("  " .. label .. ": " .. vis .. " children=" .. childCount .. " init=" .. initCount .. " unit=" .. unitCount)
			end
			if GF.partyHeader then
				PrintHeaderChildren("파티 헤더", GF.partyHeader)
			end
			if GF.raidHeaders then
				ns.Print("  레이드 헤더: " .. #GF.raidHeaders .. "개")
				for ri, rh in ipairs(GF.raidHeaders) do
					PrintHeaderChildren("  레이드 그룹 " .. ri, rh)
				end
			end
		else
			ns.Print("GroupFrames: 미로드")
		end

		-- 7. SavedVariables 상태
		if ddingUI_UFDB then
			local profileCount = 0
			for _ in pairs(ddingUI_UFDB) do profileCount = profileCount + 1 end
			ns.Print("SavedVariables: " .. profileCount .. "개 프로필")
		else
			ns.Print("|cffff0000ddingUI_UFDB가 nil!|r")
		end

		ns.Print("=== 진단 완료 ===")

	elseif cmd == "debugtag" then
		-- [FIX] 커스텀 텍스트 디버그: 전체 상태 출력
		local unitKey = (arg1 ~= "" and arg1) or "player"
		ns.Print("=== 커스텀 텍스트 디버그: " .. unitKey .. " ===")

		-- 1. DB 상태
		local db = ns.db and ns.db[unitKey]
		if not db then
			ns.Print("|cffff0000ns.db['" .. unitKey .. "'] 없음!|r")
		else
			local ctDB = db.widgets and db.widgets.customText
			if not ctDB then
				ns.Print("|cffff0000widgets.customText 없음!|r")
			else
				ns.Print("시스템 enabled: " .. tostring(ctDB.enabled))
				if ctDB.texts then
					for slotKey, textDB in pairs(ctDB.texts) do
						ns.Print("  " .. slotKey .. ": enabled=" .. tostring(textDB.enabled)
							.. " textFormat=" .. tostring(textDB.textFormat or "(nil)"))
					end
				else
					ns.Print("|cffff0000texts 테이블 없음!|r")
				end
			end
		end

		-- 2. Frame 상태
		local frame = ns.frames[unitKey]
		if not frame then
			ns.Print("|cffff0000ns.frames['" .. unitKey .. "'] 없음!|r")
		else
			ns.Print("frame.unit: " .. tostring(frame.unit))
			ns.Print("frame:IsShown(): " .. tostring(frame:IsShown()))
			if not frame._customTexts then
				ns.Print("|cffff0000frame._customTexts 없음!|r (CreateCustomText 미호출?)")
			else
				local count = 0
				for slotKey, fs in pairs(frame._customTexts) do
					count = count + 1
					local txt = fs:GetText() or "(nil)"
					local shown = fs:IsShown()
					local hasTag = fs.UpdateTag ~= nil
					local font, size, flags = fs:GetFont()
					local parent = fs:GetParent() and fs:GetParent():GetName() or "(unnamed)"
					ns.Print("  " .. slotKey .. ": shown=" .. tostring(shown)
						.. " hasTag=" .. tostring(hasTag)
						.. " text='" .. txt .. "'"
						.. " font=" .. tostring(size) .. "/" .. tostring(flags)
						.. " parent=" .. parent)
				end
				ns.Print("총 슬롯: " .. count)
			end

			-- 3. oUF.Tags 상태
			local oUF = ns.oUF
			if oUF and oUF.Tags and oUF.Tags.Methods then
				local tagCount = 0
				for _ in pairs(oUF.Tags.Methods) do tagCount = tagCount + 1 end
				ns.Print("oUF.Tags.Methods: " .. tagCount .. "개")
			else
				ns.Print("|cffff0000oUF.Tags.Methods 없음!|r")
			end

			-- 4. oUF 엘리먼트 상태
			ns.Print("Health: " .. tostring(frame.Health ~= nil))
			ns.Print("Power: " .. tostring(frame.Power ~= nil))
			ns.Print("__tags: " .. tostring(frame.__tags ~= nil))
		end

		-- 5. oUF.Tags.Methods에서 ddingui 태그 확인
		local oUF = ns.oUF
		local tagMethods = oUF and oUF.Tags and oUF.Tags.Methods
		if tagMethods then
			local ddingiuTags = {}
			for k in pairs(tagMethods) do
				if type(k) == "string" and k:find("^ddingui:") then
					table.insert(ddingiuTags, k)
				end
			end
			table.sort(ddingiuTags)
			ns.Print("ddingui 태그 등록: " .. #ddingiuTags .. "개")
			if #ddingiuTags == 0 then
				ns.Print("|cffff0000Tags.lua 로드 안 됨!|r")
			end
		else
			ns.Print("|cffff0000oUF.Tags.Methods 없음!|r")
		end

		ns.Print("=== 디버그 완료 ===")

	elseif cmd == "pt" then
		-- 자원 텍스트 전체 진단: /duf pt [unit]
		local unitKey = (arg1 ~= "" and arg1) or "player"
		print("|cff00ff00=== /duf pt: " .. unitKey .. " ===|r")

		-- 1. DB 전체 덤프
		local db = ns.db and ns.db[unitKey]
		if not db then
			print("|cffff0000[1] ns.db[" .. unitKey .. "] = nil|r")
		elseif not db.widgets then
			print("|cffff0000[1] widgets = nil|r")
		elseif not db.widgets.powerText then
			print("|cffff0000[1] widgets.powerText = nil — 이것이 원인!|r")
		else
			local pt = db.widgets.powerText
			print("[1] DB: enabled=" .. tostring(pt.enabled) .. " format=" .. tostring(pt.format)
				.. " hideIfEmptyOrFull=" .. tostring(pt.hideIfEmptyOrFull)
				.. " separator=" .. tostring(pt.separator))
			if pt.font then
				print("  font: size=" .. tostring(pt.font.size) .. " outline=" .. tostring(pt.font.outline))
			end
			if pt.color then
				print("  color: type=" .. tostring(pt.color.type))
			end
			if pt.position then
				print("  position: " .. tostring(pt.position.point) .. " -> " .. tostring(pt.position.relativePoint) .. " (" .. tostring(pt.position.offsetX) .. "," .. tostring(pt.position.offsetY) .. ")")
			end
		end

		-- 1.5. Raw WoW API 테스트 (pcall 보호 - secret value 안전)
		local rawUnit = unitKey
		if UnitExists(rawUnit) then
			local ok1, rawPow = pcall(UnitPower, rawUnit)
			local ok2, rawMax = pcall(UnitPowerMax, rawUnit)
			local ok3, _, pToken = pcall(UnitPowerType, rawUnit)
			local isSecPow = ok1 and rawPow and issecretvalue and issecretvalue(rawPow)
			local isSecMax = ok2 and rawMax and issecretvalue and issecretvalue(rawMax)
			-- secret value는 tostring()이 에러 날 수 있으므로 분리 출력
			local powStr = isSecPow and "SECRET" or (ok1 and tostring(rawPow) or "ERR")
			local maxStr = isSecMax and "SECRET" or (ok2 and tostring(rawMax) or "ERR")
			local typeStr = ok3 and tostring(pToken) or "ERR"
			print("[1.5] RAW: UnitPower=" .. powStr .. " UnitPowerMax=" .. maxStr .. " type=" .. typeStr)
		else
			print("[1.5] UnitExists(" .. rawUnit .. ")=false")
		end

		-- 2. defaults 확인
		local def = ns.defaults and ns.defaults[unitKey]
		local defPT = def and def.widgets and def.widgets.powerText
		print("[2] defaults.powerText = " .. (defPT and "EXISTS (enabled=" .. tostring(defPT.enabled) .. ", format=" .. tostring(defPT.format) .. ")" or "|cffff0000nil|r"))

		-- 3. Frame/PowerText 상태
		local frame = ns.frames[unitKey]
		if not frame then
			print("|cffff0000[3] ns.frames[" .. unitKey .. "] = nil|r")
		else
			print("[3] frame.unit = " .. tostring(frame.unit) .. ", __tags=" .. tostring(frame.__tags ~= nil) .. ", Health=" .. tostring(frame.Health ~= nil) .. ", Power=" .. tostring(frame.Power ~= nil))
			if frame.PowerText then
				local ptParent = frame.PowerText:GetParent()
				local ptParentName = ptParent and (ptParent:GetName() or tostring(ptParent)) or "nil"
				local ptParentShown = ptParent and ptParent:IsShown()
				print("[3] PowerText: shown=" .. tostring(frame.PowerText:IsShown())
					.. " visible=" .. tostring(frame.PowerText:IsVisible())
					.. " text='" .. tostring(frame.PowerText:GetText() or "") .. "'"
					.. " hasUpdateTag=" .. tostring(frame.PowerText.UpdateTag ~= nil))
				print("[3] PowerText parent=" .. ptParentName .. " parentShown=" .. tostring(ptParentShown)
					.. " alpha=" .. tostring(frame.PowerText:GetAlpha()))
			else
				print("|cffff0000[3] frame.PowerText = nil — CreatePowerText 미실행 또는 실패|r")
			end

			-- 4. oUF Tag 상태 확인
			if frame.PowerText then
				print("[4] PowerText __tags = " .. tostring(frame.__tags and frame.__tags[frame.PowerText] ~= nil or false))
				local ptDB2 = db and db.widgets and db.widgets.powerText
				local regFmt = ptDB2 and ptDB2.format or "percentage"
				print("[4] DB format='" .. regFmt .. "'")
			else
				print("[4] PowerText=" .. (frame.PowerText and "exists" or "nil"))
			end

			-- 4.5. RAW API 직접 테스트 (pcall 보호)
			do
				local rawU = frame.unit or unitKey
				print("[4.5] RAW API (unit=" .. tostring(rawU) .. "):")
				local ok1, rPow = pcall(UnitPower, rawU)
				local ok2, rMax = pcall(UnitPowerMax, rawU)
				local ok3, _, rToken = pcall(UnitPowerType, rawU)
				-- secret value는 tostring() 불가 → issecretvalue 체크 후 안전 출력
				local isPowSec = ok1 and rPow and issecretvalue and issecretvalue(rPow)
				local isMaxSec = ok2 and rMax and issecretvalue and issecretvalue(rMax)
				local powStr = isPowSec and "SECRET" or (ok1 and tostring(rPow) or "ERR")
				local maxStr = isMaxSec and "SECRET" or (ok2 and tostring(rMax) or "ERR")
				print("  UnitPower=" .. powStr .. " UnitPowerMax=" .. maxStr
					.. " type=" .. (ok3 and tostring(rToken) or "ERR"))
				print("  secret: pow=" .. tostring(isPowSec) .. " max=" .. tostring(isMaxSec))
				-- GetPowerSafe 직접 호출
				if ns.GetPowerSafe then
					local ok4, c, m, p = pcall(ns.GetPowerSafe, rawU)
					if ok4 then
						print("  GetPowerSafe=" .. tostring(c) .. "/" .. tostring(m) .. "/" .. tostring(p) .. "%")
					else
						print("  |cffff0000GetPowerSafe ERR: " .. tostring(c) .. "|r")
					end
				else
					print("  |cffff0000ns.GetPowerSafe=nil|r")
				end
			end

			-- 5. 태그 내부 로직 단계별 추적
			local tagUnit = frame.unit or unitKey
			if tagUnit and UnitExists(tagUnit) then
				print("[5] 태그 내부 로직 추적 (unit=" .. tagUnit .. "):")

				-- 5a: hideIfEmptyOrFull 직접 확인
				local baseUnit5 = tagUnit:gsub("%d", "")
				local ptDB5 = ns.db and ns.db[baseUnit5] and ns.db[baseUnit5].widgets and ns.db[baseUnit5].widgets.powerText
				local hideFlag = ptDB5 and ptDB5.hideIfEmptyOrFull
				print("[5a] hideIfEmptyOrFull=" .. tostring(hideFlag) .. " (type=" .. type(hideFlag) .. ")")

				-- 5b: GetPowerSafe 결과 + hideIfEmptyOrFull 판정
				if ns.GetPowerSafe then
					local ok, c, m, p = pcall(ns.GetPowerSafe, tagUnit)
					if ok then
						print("[5b] GetPowerSafe: cur=" .. tostring(c) .. " max=" .. tostring(m) .. " pct=" .. tostring(p))
						if m == 0 and p == 0 then
							print("|cffff0000[5b] max==0 AND pct==0 → 여기서 '' 반환!|r")
						elseif hideFlag == true and (p <= 0 or p >= 100) then
							print("|cffff0000[5b] hideIfEmptyOrFull=true AND pct=" .. tostring(p) .. " → 이것이 '' 원인!|r")
						else
							print("[5b] hideIfEmptyOrFull 통과 → 포맷 함수 실행 가능")
						end
					else
						print("|cffff0000[5b] GetPowerSafe ERR: " .. tostring(c) .. "|r")
					end
				end

				-- 5c: oUF.Tags.Methods power 태그 테스트
				print("[5c] power 태그별 결과:")
				local oUF_t = ns.oUF
				local tagMethodsT = oUF_t and oUF_t.Tags and oUF_t.Tags.Methods
				if tagMethodsT then
					local ptTags = {"ddingui:pt:pct", "ddingui:pt:cur", "ddingui:pt:curmax", "ddingui:pt:smart"}
					for _, tName in ipairs(ptTags) do
						local fn = tagMethodsT[tName]
						if fn then
							local ok, result = pcall(fn, tagUnit)
							local display = ok and ("'" .. tostring(result) .. "'") or ("|cffff0000ERR:" .. tostring(result) .. "|r")
							print("  " .. tName .. " → " .. display)
						else
							print("  " .. tName .. " → |cffff0000미등록|r")
						end
					end
				else
					print("|cffff0000[5c] oUF.Tags.Methods 없음!|r")
				end
			else
				print("[5] unit=" .. tostring(tagUnit) .. " — 대상 없음, 태그 테스트 스킵")
			end

			-- 6. UpdateTag 컴파일 함수 테스트
			if frame.PowerText and frame.PowerText.UpdateTag then
				print("[6] 컴파일된 UpdateTag 호출...")
				local ok, err = pcall(frame.PowerText.UpdateTag, frame.PowerText)
				if ok then
					print("[6] 결과: '" .. tostring(frame.PowerText:GetText() or "") .. "'")
				else
					print("|cffff0000[6] UpdateTag 에러: " .. tostring(err) .. "|r")
				end
			else
				print("|cffff0000[6] UpdateTag 없음 — Tag 미등록!|r")
			end
		end

		print("|cff00ff00=== 완료 ===|r")

	elseif cmd == "ptfix" then
		-- 자원 텍스트 강제 복구: /duf ptfix [unit]
		local unitKey = (arg1 ~= "" and arg1) or "player"
		print("|cff00ff00=== /duf ptfix: " .. unitKey .. " 강제 복구 ===|r")

		local frame = ns.frames[unitKey]
		if not frame then
			print("|cffff0000프레임 없음|r")
		elseif not frame.PowerText then
			print("|cffff0000PowerText 없음 — /reload 필요|r")
		else
			-- DB에 powerText 보장
			local db = ns.db[unitKey]
			if db then
				if not db.widgets then db.widgets = {} end
				if not db.widgets.powerText then
					local defPT = ns.WidgetDefaults and ns.WidgetDefaults.powerText
					if defPT then
						local function SimpleCopy(t)
							if type(t) ~= "table" then return t end
							local c = {}; for k,v in pairs(t) do c[k] = type(v) == "table" and SimpleCopy(v) or v end; return c
						end
						db.widgets.powerText = SimpleCopy(defPT)
						local baseUnit = unitKey:gsub("%d", "")
						if baseUnit == "player" or baseUnit == "target" or baseUnit == "focus" then
							db.widgets.powerText.enabled = true
						end
						print("DB 복구 완료: powerText defaults 적용")
					end
				end

				local ptDB = db.widgets.powerText
				if ptDB then
					local fmt = ptDB.format or "percentage"
					print("format=" .. fmt)

					-- oUF re-tag로 리바인딩
					if frame.Untag and frame.Tag and frame.PowerText then
						frame:Untag(frame.PowerText)
						local ptTagStr2 = (ns.POWER_FORMAT_TO_TAG and ns.POWER_FORMAT_TO_TAG[fmt]) or "[ddingui:pt:pct]"
						frame:Tag(frame.PowerText, ptTagStr2)
						print("oUF re-tag 완료: " .. ptTagStr2)
					end
					-- Show
					if ptDB.enabled ~= false then
						frame.PowerText:Show()
					end
					-- 즉시 갱신
					if frame.UpdateTags then
						frame:UpdateTags()
					end
					print("결과: '" .. tostring(frame.PowerText:GetText() or "") .. "'")
				end
			end
		end
		print("|cff00ff00=== ptfix 완료 ===|r")

	elseif cmd == "clickdebug" then
		-- [FIX] 클릭 영역 디버그: 자식 프레임 EnableMouse 상태 출력
		local unitKey = (arg1 ~= "" and arg1) or "target"
		local frame = ns.frames[unitKey]
		if not frame then
			ns.Print("프레임 없음:", unitKey)
			return
		end
		ns.Print("=== 클릭 디버그:", unitKey, "===")
		ns.Print("메인 프레임:", frame:GetName() or "?", "크기:", format("%.0fx%.0f", frame:GetWidth(), frame:GetHeight()))
		ns.Print("  EnableMouse:", tostring(frame:IsMouseEnabled()), "| IsVisible:", tostring(frame:IsVisible()))
		ns.Print("  RegisteredClicks:", frame.GetRegisteredClicks and table.concat({frame:GetRegisteredClicks()}, ",") or "?")

		local children = { frame:GetChildren() }
		ns.Print("자식 프레임 수:", #children)
		for i, child in ipairs(children) do
			local mouseEnabled = child.IsMouseEnabled and child:IsMouseEnabled()
			local name = child:GetName() or child:GetObjectType()
			local w, h = child:GetWidth(), child:GetHeight()
			local visible = child:IsShown()
			local level = child:GetFrameLevel()
			-- 마우스 활성화된 자식만 상세 출력
			if mouseEnabled then
				ns.Print(format("  [%d] |cffff4444MOUSE ON|r %s (%.0fx%.0f) lv=%d vis=%s", i, name, w, h, level, tostring(visible)))
				-- 위치 정보
				local numPoints = child:GetNumPoints()
				for p = 1, numPoints do
					local point, rel, relP, x, y = child:GetPoint(p)
					local relName = rel and (rel.GetName and rel:GetName() or rel:GetObjectType()) or "nil"
					ns.Print(format("    → %s, %s, %s, %.1f, %.1f", point or "?", relName, relP or "?", x or 0, y or 0))
				end
			elseif visible then
				ns.Print(format("  [%d] %s (%.0fx%.0f) lv=%d", i, name, w, h, level))
			end
		end

		-- GetMouseFocus 힌트
		ns.Print("|cffffcc00팁: 프레임 위에 마우스를 올리고 /run print(GetMouseFocus():GetName() or GetMouseFocus():GetObjectType()) 실행|r")
		ns.Print("=== 진단 완료 ===")

	elseif cmd == "healthdbg" then
		ns._healthDbg = not ns._healthDbg
		ns.Print("체력 텍스트 디버그:", ns._healthDbg and "ON" or "OFF")
		if ns._healthDbg then
			-- 즉시 현재 상태 출력
			for unitKey, frame in pairs(ns.frames) do
				if frame.HealthText then
					local db = ns.db and ns.db[unitKey]
					local healthDB = db and db.widgets and db.widgets.healthText
					local dbFmt = healthDB and healthDB.format or "(nil)"
					local elemFmt = frame.Health and frame.Health._healthFormat or "(nil)"
					local curText = frame.HealthText:GetText() or "(empty)"
					local unit = frame.unit or "(nil)"
					print("|cff00ff00[UF-HP]|r", unitKey, ": unit=" .. tostring(unit),
						"dbFmt=" .. tostring(dbFmt),
						"elemFmt=" .. tostring(elemFmt),
						"text=" .. tostring(curText),
						"shown=" .. tostring(frame.HealthText:IsShown()))
					-- 추가: Health StatusBar 위의 모든 FontString 개수
					if frame.Health then
						local fsCount = 0
						local regions = { frame.Health:GetRegions() }
						for _, r in ipairs(regions) do
							if r:IsObjectType("FontString") then
								fsCount = fsCount + 1
								local fsText = r:GetText() or ""
								local fsShown = r:IsShown()
								if fsText ~= "" or fsShown then
									print("  |cffff9900FontString:|r text=" .. tostring(fsText), "shown=" .. tostring(fsShown))
								end
							end
						end
						print("  |cff9999ff총 FontString:|r", fsCount)
					end
				end
			end
		end
	elseif cmd == "textdbg" then
		-- [FIX] 텍스트 포맷/색상 변경 디버그: 모든 단계를 추적
		local unitKey = (arg1 ~= "" and arg1) or "player"
		local frame = ns.frames[unitKey]
		local p = function(...) print("|cff00ccff[TextDBG]|r", ...) end

		p("===== 텍스트 디버그 시작:", unitKey, "=====")

		-- Step 1: 프레임 확인
		if not frame then
			p("|cffff0000[1] ns.frames['" .. unitKey .. "'] = nil!|r 프레임이 등록되지 않았습니다")
			p("  등록된 프레임:", table.concat((function() local t={} for k in pairs(ns.frames) do t[#t+1]=k end return t end)(), ", "))
			return
		end
		p("[1] frame =", frame:GetName() or frame:GetObjectType(), "| unit =", tostring(frame.unit))

		-- Step 2: oUF tag 상태 확인
		p("[2] __tags =", tostring(frame.__tags ~= nil))
		p("  Health =", tostring(frame.Health ~= nil), "| Power =", tostring(frame.Power ~= nil))

		-- Step 3: DB 값 확인
		local db = ns.db[unitKey]
		if not db then
			p("|cffff0000[3] ns.db['" .. unitKey .. "'] = nil!|r")
			return
		end
		local wdb = db.widgets
		p("[3] db.widgets =", tostring(wdb ~= nil))

		-- Step 3a: Power text DB
		local ptDB = wdb and wdb.powerText
		p("[3a] powerText DB =", tostring(ptDB ~= nil))
		if ptDB then
			p("  format =", tostring(ptDB.format), "| enabled =", tostring(ptDB.enabled))
			p("  color =", ptDB.color and ("type=" .. tostring(ptDB.color.type)) or "nil")
		end

		-- Step 3b: Health text DB
		local htDB = wdb and wdb.healthText
		p("[3b] healthText DB =", tostring(htDB ~= nil))
		if htDB then
			p("  format =", tostring(htDB.format), "| enabled =", tostring(htDB.enabled))
		end

		-- Step 3c: Name text DB
		local ntDB = wdb and wdb.nameText
		p("[3c] nameText DB =", tostring(ntDB ~= nil))
		if ntDB then
			p("  format =", tostring(ntDB.format), "| enabled =", tostring(ntDB.enabled))
		end

		-- Step 4: 태그 매핑 확인
		p("[4] POWER_FORMAT_TO_TAG =", tostring(ns.POWER_FORMAT_TO_TAG ~= nil))
		p("  HEALTH_FORMAT_TO_TAG =", tostring(ns.HEALTH_FORMAT_TO_TAG ~= nil))
		p("  NAME_FORMAT_TO_TAG =", tostring(ns.NAME_FORMAT_TO_TAG ~= nil))

		local ptFmt = (ptDB and ptDB.format) or "percentage"
		local ptTagStr = ns.POWER_FORMAT_TO_TAG and ns.POWER_FORMAT_TO_TAG[ptFmt]
		p("  Power: fmt='" .. ptFmt .. "' → tag='" .. tostring(ptTagStr) .. "'")

		local htFmt = (htDB and htDB.format) or "percentage"
		local htTagStr = ns.HEALTH_FORMAT_TO_TAG and ns.HEALTH_FORMAT_TO_TAG[htFmt]
		p("  Health: fmt='" .. htFmt .. "' → tag='" .. tostring(htTagStr) .. "'")

		local ntFmt = (ntDB and ntDB.format) or "name"
		local ntTagStr = ns.NAME_FORMAT_TO_TAG and ns.NAME_FORMAT_TO_TAG[ntFmt]
		p("  Name: fmt='" .. ntFmt .. "' → tag='" .. tostring(ntTagStr) .. "'")

		-- Step 5: FontString 상태
		p("[5] FontStrings:")
		if frame.PowerText then
			p("  PowerText: text='" .. tostring(frame.PowerText:GetText()) .. "' shown=" .. tostring(frame.PowerText:IsShown()))
			p("    __tags =", tostring(frame.__tags ~= nil))
		else
			p("  |cffff0000PowerText = nil!|r")
		end
		if frame.HealthText then
			p("  HealthText: text='" .. tostring(frame.HealthText:GetText()) .. "' shown=" .. tostring(frame.HealthText:IsShown()))
			p("    __tags =", tostring(frame.__tags ~= nil))
		else
			p("  |cffff0000HealthText = nil!|r")
		end
		if frame.NameText then
			p("  NameText: text='" .. tostring(frame.NameText:GetText()) .. "' shown=" .. tostring(frame.NameText:IsShown()))
			p("    __tags =", tostring(frame.__tags ~= nil))
		else
			p("  |cffff0000NameText = nil!|r")
		end

		-- Step 6: oUF.Tags 상태 확인
		local oUF_d = ns.oUF
		local tagMethodsD = oUF_d and oUF_d.Tags and oUF_d.Tags.Methods
		p("[6] oUF.Tags.Methods =", tostring(tagMethodsD ~= nil))
		if tagMethodsD then
			local ptMethodName = ptTagStr and ptTagStr:match("^%[(.+)%]$")
			p("  Methods['" .. tostring(ptMethodName) .. "'] =", tostring(tagMethodsD[ptMethodName or ""] ~= nil))
			local htMethodName = htTagStr and htTagStr:match("^%[(.+)%]$")
			p("  Methods['" .. tostring(htMethodName) .. "'] =", tostring(tagMethodsD[htMethodName or ""] ~= nil))
		end

		-- Step 7: oUF UpdateAllElements 시뮬레이션
		if frame.UpdateAllElements and frame.unit and UnitExists(frame.unit) then
			p("[7] UpdateAllElements 시뮬레이션...")
			local ok4, err4 = pcall(frame.UpdateAllElements, frame, "DiagRefresh")
			p("  결과:", ok4 and "|cff00ff00성공|r" or ("|cffff0000실패: " .. tostring(err4) .. "|r"))
			if ok4 and frame.PowerText then
				p("  PowerText after refresh: '" .. tostring(frame.PowerText:GetText()) .. "'")
			end
			if ok4 and frame.HealthText then
				p("  HealthText after refresh: '" .. tostring(frame.HealthText:GetText()) .. "'")
			end
		end

		p("===== 텍스트 디버그 완료 =====")

	elseif cmd == "profile" then
		if not ns.Profiles then
			ns.Print("프로필 시스템 사용 불가")
			return
		end

		if arg1 == "list" or arg1 == "" then
			local profiles = ns.Profiles:GetList()
			local current = ns.Profiles:GetCurrent()
			ns.Print("프로필 목록:")
			for _, name in ipairs(profiles) do
				if name == current then
					ns.Print("  > " .. name .. " (현재)")
				else
					ns.Print("  - " .. name)
				end
			end
		elseif arg1 == "switch" and arg2 ~= "" then
			ns.Profiles:Switch(arg2)
		elseif arg1 == "new" and arg2 ~= "" then
			ns.Profiles:Create(arg2)
		elseif arg1 == "delete" and arg2 ~= "" then
			ns.Profiles:Delete(arg2)
		else
			ns.Print("프로필 명령어:")
			ns.Print("  /duf profile list - 프로필 목록")
			ns.Print("  /duf profile switch <이름> - 프로필 전환")
			ns.Print("  /duf profile new <이름> - 프로필 생성")
			ns.Print("  /duf profile delete <이름> - 프로필 삭제")
		end
	-- debugborder 명령어 제거 (디버프 테두리 수정 완료)
	end
end
