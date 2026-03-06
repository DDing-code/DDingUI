--[[
	ddingUI UnitFrames
	Units/Standalone/Spawn.lua — 독자 프레임 생성 (oUF:Spawn 대체)
	
	기존 Units/Spawn.lua의 모든 ApplyUnitPosition/ApplyPosition 로직 재사용
	→ CDM 앵커 호환성 100% 유지
]]

local _, ns = ...

local SUF = ns.SUF
local C = ns.Constants

local type = type
local UIParent = UIParent
local _G = _G

-----------------------------------------------
-- Initialize — 모든 개별 유닛 프레임 생성
-----------------------------------------------

local function Initialize()
	-- Layout.lua가 아직 oUF 참조를 시도할 수 있으므로,
	-- oUF가 없을 때를 위한 shim 확인
	if not ns.oUF then
		-- oUF shim이 Core/Init.lua에서 설정되어야 함
		-- fallback: 빈 테이블
		ns.oUF = ns.oUF or {
			Tags = { Methods = ns.TextFormats and ns.TextFormats.Methods or {}, Events = {} },
		}
	end

	local db = ns.db
	if not db then return end

	-- 위치 적용 함수 재사용 (Spawn.lua에서 이미 ns에 공개)
	local ApplyUnitPosition = ns.ApplyUnitPosition

	-- Player
	if db.player and db.player.enabled then
		local f = SUF:SpawnUnit("player", "ddingUI_Player")
		ApplyUnitPosition(f, db.player, "BOTTOMLEFT", UIParent, "BOTTOM", -260, 200)
		ns.frames.player = f
		SUF:HookOnShow(f)
		f:Show()
	end

	-- Target
	if db.target and db.target.enabled then
		local f = SUF:SpawnUnit("target", "ddingUI_Target")
		ApplyUnitPosition(f, db.target, "BOTTOMRIGHT", UIParent, "BOTTOM", 260, 200)
		ns.frames.target = f
		SUF:HookOnShow(f)

		-- [FIX] RegisterUnitWatch 사용: Blizzard secure API로 Show/Hide 처리
		-- 수동 PLAYER_TARGET_CHANGED + Show/Hide는 TargetNearestEnemy 등
		-- secure 실행 경로에서 ADDON_ACTION_BLOCKED 에러 유발
		f:SetAttribute("unit", "target")
		RegisterUnitWatch(f)

		-- PLAYER_TARGET_CHANGED는 UI 업데이트용으로만 사용 (Show/Hide 제외)
		f:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_TARGET_CHANGED" then
				if UnitExists("target") then
					-- RegisterUnitWatch가 Show를 처리하므로 여기서는 데이터만 갱신
					if ns.ElementDrivers and ns.ElementDrivers.UpdateAll then
						ns.ElementDrivers:UpdateAll(self)
					end
				end
			end
		end)
		f:RegisterEvent("PLAYER_TARGET_CHANGED")
	end

	-- Target of Target
	if db.targettarget and db.targettarget.enabled then
		local f = SUF:SpawnUnit("targettarget", "ddingUI_TargetTarget")
		local parentFrame = ns.frames.target or UIParent
		local cfg = db.targettarget
		if cfg.anchorToParent and parentFrame then
			local ap = cfg.anchorPosition
			if ap and type(ap) == "table" and ap.point then
				f:SetPoint(ap.point, parentFrame, ap.relativePoint or ap.point, ap.offsetX or 0, ap.offsetY or 0)
			else
				f:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMRIGHT", 5, 0)
			end
		else
			local ApplyPosition = function(frame, pos, fp, fr, frp, fx, fy)
				if pos and pos.point then
					frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0)
				elseif pos and type(pos[1]) == "string" then
					frame:SetPoint(pos[1], _G[pos[2]] or UIParent, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
				else
					frame:SetPoint(fp, fr or UIParent, frp or fp, fx or 0, fy or 0)
				end
			end
			ApplyPosition(f, cfg.position, "LEFT", parentFrame, "RIGHT", 8, 0)
		end
		ns.frames.targettarget = f
		SUF:HookOnShow(f)
		f:Show()
	end

	-- Focus
	if db.focus and db.focus.enabled then
		local f = SUF:SpawnUnit("focus", "ddingUI_Focus")
		ApplyUnitPosition(f, db.focus, "LEFT", UIParent, "LEFT", 80, -100)
		ns.frames.focus = f
		SUF:HookOnShow(f)

		-- [FIX] RegisterUnitWatch 사용: secure Show/Hide 처리
		f:SetAttribute("unit", "focus")
		RegisterUnitWatch(f)

		f:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_FOCUS_CHANGED" then
				if UnitExists("focus") then
					if ns.ElementDrivers and ns.ElementDrivers.UpdateAll then
						ns.ElementDrivers:UpdateAll(self)
					end
				end
			end
		end)
		f:RegisterEvent("PLAYER_FOCUS_CHANGED")
	end

	-- Focus Target
	if db.focustarget and db.focustarget.enabled then
		local f = SUF:SpawnUnit("focustarget", "ddingUI_FocusTarget")
		local parentFrame = ns.frames.focus or UIParent
		local cfg = db.focustarget
		if cfg.anchorToParent and parentFrame then
			local ap = cfg.anchorPosition
			if ap and type(ap) == "table" and ap.point then
				f:SetPoint(ap.point, parentFrame, ap.relativePoint or ap.point, ap.offsetX or 0, ap.offsetY or 0)
			else
				f:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", 5, 0)
			end
		else
			local ApplyPosition = function(frame, pos, fp, fr, frp, fx, fy)
				if pos and pos.point then
					frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0)
				elseif pos and type(pos[1]) == "string" then
					frame:SetPoint(pos[1], _G[pos[2]] or UIParent, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
				else
					frame:SetPoint(fp, fr or UIParent, frp or fp, fx or 0, fy or 0)
				end
			end
			ApplyPosition(f, cfg.position, "LEFT", parentFrame, "RIGHT", 5, 0)
		end
		ns.frames.focustarget = f
		SUF:HookOnShow(f)
		f:Show()
	end

	-- Pet
	if db.pet and db.pet.enabled then
		local f = SUF:SpawnUnit("pet", "ddingUI_Pet")
		local parentFrame = ns.frames.player or UIParent
		local cfg = db.pet
		if cfg.anchorToParent and parentFrame then
			local ap = cfg.anchorPosition
			if ap and type(ap) == "table" and ap.point then
				f:SetPoint(ap.point, parentFrame, ap.relativePoint or ap.point, ap.offsetX or 0, ap.offsetY or 0)
			else
				f:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 0, -5)
			end
		else
			ApplyUnitPosition(f, cfg, "BOTTOMLEFT", parentFrame, "TOPLEFT", 0, 8)
		end
		ns.frames.pet = f
		SUF:HookOnShow(f)
		f:Show()
	end

	-- Boss Frames
	if db.boss and db.boss.enabled then
		local settings = db.boss
		local spacing = settings.spacing or 48

		for i = 1, C.MAX_BOSS_FRAMES do
			local unitId = "boss" .. i
			local f = SUF:SpawnUnit(unitId, "ddingUI_Boss" .. i)

			if i == 1 then
				local ApplyPosition = function(frame, pos, fp, fr, frp, fx, fy)
					if pos and pos.point then
						frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0)
					elseif pos and type(pos[1]) == "string" then
						frame:SetPoint(pos[1], _G[pos[2]] or UIParent, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
					else
						frame:SetPoint(fp, fr or UIParent, frp or fp, fx or 0, fy or 0)
					end
				end
				ApplyPosition(f, settings.position, "RIGHT", UIParent, "RIGHT", -60, 100)
			else
				local prev = ns.frames["boss" .. (i - 1)]
				if settings.growDirection == "UP" then
					f:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
				else
					f:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
				end
			end

			ns.frames[unitId] = f
			SUF:HookOnShow(f)
			f:Show()
		end
	end

	-- Arena Frames
	if db.arena and db.arena.enabled then
		local settings = db.arena
		local spacing = settings.spacing or 48

		for i = 1, C.MAX_ARENA_FRAMES do
			local unitId = "arena" .. i
			local f = SUF:SpawnUnit(unitId, "ddingUI_Arena" .. i)

			if i == 1 then
				local ApplyPosition = function(frame, pos, fp, fr, frp, fx, fy)
					if pos and pos.point then
						frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0)
					elseif pos and type(pos[1]) == "string" then
						frame:SetPoint(pos[1], _G[pos[2]] or UIParent, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
					else
						frame:SetPoint(fp, fr or UIParent, frp or fp, fx or 0, fy or 0)
					end
				end
				ApplyPosition(f, settings.position, "RIGHT", UIParent, "RIGHT", -60, 100)
			else
				local prev = ns.frames["arena" .. (i - 1)]
				if settings.growDirection == "UP" then
					f:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
				else
					f:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
				end
			end

			ns.frames[unitId] = f
			SUF:HookOnShow(f)
			f:Show()
		end
	end

	-- 초기 갱신 (약간의 딜레이 후)
	C_Timer.After(0.1, function()
		for _, frame in ipairs(SUF.allFrames) do
			if frame:IsVisible() and frame.unit and UnitExists(frame.unit) then
				ns.ElementDrivers:UpdateAll(frame)
			end
		end
	end)

	ns.Debug("Standalone Spawn: All individual units spawned (" .. #SUF.allFrames .. " frames)")
end

-- [STANDALONE] ns.SUF.InitializeFrames 함수로 노출
-- Init.lua의 PLAYER_LOGIN → Spawn:Initialize()에서 호출됨
function SUF.InitializeFrames()
	Initialize()
end

-- 타이밍 안전장치: Init.lua에서 호출하지 않는 경우를 대비한 fallback
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		-- Init.lua에서 이미 초기화했으면 스킵
		if #SUF.allFrames > 0 then
			self:UnregisterEvent("PLAYER_ENTERING_WORLD")
			return
		end
		-- GroupFrames 초기화 (기존 모듈 유지)
		local GF = ns.GroupFrames
		if GF and GF.Initialize and not GF.headersInitialized then
			GF:Initialize()
			ns.Debug("GroupFrames module initialized (standalone fallback)")
		end
		-- 독자 개별 프레임 초기화
		Initialize()
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	end
end)

ns.Debug("Standalone Spawn.lua loaded")
