--[[
	ddingUI UnitFrames
	Units/Spawn.lua - Unit frame spawning and management (oUF-based)
]]

local _, ns = ...

local Spawn = {}
ns.Spawn = Spawn

local C = ns.Constants
local oUF = ns.oUF

-----------------------------------------------
-- API Upvalue Caching
-----------------------------------------------

local type = type
local select = select
local UIParent = UIParent
local _G = _G

-----------------------------------------------
-- Growth Direction Helpers
-----------------------------------------------

-- growDirection → SecureGroupHeader "point" 속성
-- point는 "이전 프레임의 어느 쪽에 다음 프레임을 붙이는가"
-- H_CENTER/V_CENTER는 내부적으로 DOWN과 동일, 위치만 중앙 정렬
ns.GROW_TO_POINT = {
	DOWN  = "TOP",
	UP    = "BOTTOM",
	RIGHT = "LEFT",
	LEFT  = "RIGHT",
	H_CENTER = "LEFT",  -- 가로 중앙: RIGHT로 성장 + 헤더 가로 중앙 배치
	V_CENTER = "TOP",   -- 세로 중앙: DOWN으로 성장 + 헤더 세로 중앙 배치
}
local GROW_TO_POINT = ns.GROW_TO_POINT

-- columnGrowDirection → SecureGroupHeader "columnAnchorPoint"
ns.COLUMN_GROW_TO_ANCHOR = {
	RIGHT = "LEFT",
	LEFT  = "RIGHT",
	DOWN  = "TOP",
	UP    = "BOTTOM",
}
local COLUMN_GROW_TO_ANCHOR = ns.COLUMN_GROW_TO_ANCHOR

-- growDirection에 따른 offset 키/부호 반환
-- H_CENTER → RIGHT와 동일, V_CENTER → DOWN과 동일 (위치 정렬은 별도 처리)
function ns.GetGrowOffsets(growDir, spacing)
	local sp = spacing or 4
	if growDir == "DOWN" or growDir == "V_CENTER" then
		return "yOffset", -sp, "xOffset", 0
	elseif growDir == "UP" then
		return "yOffset", sp, "xOffset", 0
	elseif growDir == "RIGHT" or growDir == "H_CENTER" then
		return "xOffset", sp, "yOffset", 0
	elseif growDir == "LEFT" then
		return "xOffset", -sp, "yOffset", 0
	end
	return "yOffset", -sp, "xOffset", 0
end
local GetGrowOffsets = ns.GetGrowOffsets

-----------------------------------------------
-- Initialize — oUF 스타일 등록 + 프레임 생성
-----------------------------------------------

-- [STANDALONE] oUF 기반 초기화 비활성화
-- 독자 프레임은 Units/Standalone/Spawn.lua에서 PLAYER_LOGIN 시 초기화됨
function Spawn:Initialize()
	-- [STANDALONE] oUF가 로드되어 있고, standalone 모드가 아닐 때만 oUF 사용
	if not ns.SUF then
		-- oUF 모드 (폴백)
		if oUF then
			oUF:RegisterStyle("ddingUI", function(self, unit)
				if ns.Layout and ns.Layout.StyleUnit then
					ns.Layout:StyleUnit(self, unit)
				end
			end)
			oUF:SetActiveStyle("ddingUI")

			self:SpawnIndividualUnits()
			self:SpawnBossFrames()
			self:SpawnArenaFrames()
			self:SpawnGroupFrames()

			ns.Debug("All unit frames spawned (oUF mode)")
		end
		return
	end

	-- [STANDALONE] 모드에서는 SUF가 프레임을 생성
	-- GroupFrames 초기화 (독자 모듈이므로 항상 수행)
	self:SpawnGroupFrames()

	-- SUF 프레임 생성
	if ns.SUF and ns.SUF.InitializeFrames then
		ns.SUF:InitializeFrames()
	end

	ns.Debug("Spawn:Initialize completed (standalone mode)")
end

-----------------------------------------------
-- Helper: Position Frame
-----------------------------------------------

-- [CDM 호환] 앵커 프레임 이름 해석 (DDingUI CDM ResolveAnchorFrame과 동일 패턴)
local function ResolveAnchorFrame(name)
	if not name or name == "" or name == "UIParent" then
		return UIParent
	end
	-- DDingUI CDM가 로드되어 있으면 통합 해석 사용
	local DDingUI = _G.DDingUI_Addon or (_G.DDingUI and _G.DDingUI.ResolveAnchorFrame and _G.DDingUI)
	if DDingUI and DDingUI.ResolveAnchorFrame then
		return DDingUI:ResolveAnchorFrame(name)
	end
	-- 직접 _G에서 찾기
	return _G[name] or UIParent
end
-- [CDM 호환] ns에 공개 (Update.lua / Mover.lua 에서 사용)
ns.ResolveAnchorFrame = ResolveAnchorFrame

local function ApplyPosition(frame, pos, fallbackPoint, fallbackRelative, fallbackRelPoint, fallbackX, fallbackY)
	if pos then
		-- New object format: { point = "CENTER", relativePoint = "CENTER", offsetX = 0, offsetY = 0 }
		if pos.point then
			local point = pos.point or "CENTER"
			local relPoint = pos.relativePoint or point
			local x = pos.offsetX or 0
			local y = pos.offsetY or 0
			frame:SetPoint(point, UIParent, relPoint, x, y)
		-- Legacy full array format: { "BOTTOMLEFT", "UIParent", "BOTTOM", -260, 200 }
		elseif type(pos[1]) == "string" then
			local relativeTo = pos[2] and (_G[pos[2]] or UIParent) or UIParent
			frame:SetPoint(pos[1], relativeTo, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
		-- Simple offset format: { x, y } - use fallbackPoint with these offsets
		elseif type(pos[1]) == "number" and type(pos[2]) == "number" then
			frame:SetPoint(fallbackPoint, fallbackRelative or UIParent, fallbackRelPoint or fallbackPoint, pos[1], pos[2])
		else
			-- Fallback
			frame:SetPoint(fallbackPoint, fallbackRelative or UIParent, fallbackRelPoint or fallbackPoint, fallbackX or 0, fallbackY or 0)
		end
	else
		frame:SetPoint(fallbackPoint, fallbackRelative or UIParent, fallbackRelPoint or fallbackPoint, fallbackX or 0, fallbackY or 0)
	end
end

-- [CDM 호환] 유닛 설정의 attachTo/selfPoint/anchorPoint 기반 위치 적용
local function ApplyUnitPosition(frame, cfg, fallbackPoint, fallbackRelative, fallbackRelPoint, fallbackX, fallbackY)
	local attachTo = cfg and cfg.attachTo
	local selfPoint = cfg and cfg.selfPoint
	local anchorPoint = cfg and cfg.anchorPoint
	local pos = cfg and cfg.position

	-- attachTo가 UIParent가 아닌 프레임이면 CDM 스타일 앵커
	if attachTo and attachTo ~= "UIParent" and attachTo ~= "" then
		local anchor = ResolveAnchorFrame(attachTo)
		local sp = selfPoint or "CENTER"
		local ap = anchorPoint or "CENTER"
		local oX, oY = 0, 0

		if pos then
			if pos.offsetX then
				-- object format: { point = ..., offsetX = ..., offsetY = ... }
				oX = pos.offsetX or 0
				oY = pos.offsetY or 0
			elseif type(pos[1]) == "string" then
				-- legacy array format: { "BOTTOM", "ddingUI_Player", "CENTER", -323, 485 }
				-- selfPoint/anchorPoint는 cfg에서 이미 가져왔으므로 오프셋만 추출
				oX = pos[4] or 0
				oY = pos[5] or 0
			elseif type(pos[1]) == "number" then
				-- simple offset format: { x, y }
				oX = pos[1] or 0
				oY = pos[2] or 0
			end
		end

		frame:SetPoint(sp, anchor, ap, oX, oY)
		return
	end

	-- 기존 UIParent 기반 위치 적용
	ApplyPosition(frame, pos, fallbackPoint, fallbackRelative, fallbackRelPoint, fallbackX, fallbackY)
end
-- [CDM 호환] ns에 공개 (Update.lua에서 위치 재적용 시 사용)
ns.ApplyUnitPosition = ApplyUnitPosition

-----------------------------------------------
-- Spawn Individual Units
-----------------------------------------------

function Spawn:SpawnIndividualUnits()
	local db = ns.db

	-- Player
	if db.player and db.player.enabled then
		local f = oUF:Spawn("player", "ddingUI_Player")
		ApplyUnitPosition(f, db.player, "BOTTOMLEFT", UIParent, "BOTTOM", -260, 200)
		ns.frames.player = f
	end

	-- Target
	if db.target and db.target.enabled then
		local f = oUF:Spawn("target", "ddingUI_Target")
		ApplyUnitPosition(f, db.target, "BOTTOMRIGHT", UIParent, "BOTTOM", 260, 200)
		ns.frames.target = f
	end

	-- Target of Target (anchored to target)
	if db.targettarget and db.targettarget.enabled then
		local f = oUF:Spawn("targettarget", "ddingUI_TargetTarget")
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
			ApplyPosition(f, cfg.position, "LEFT", parentFrame, "RIGHT", 8, 0)
		end
		ns.frames.targettarget = f
	end

	-- Focus
	if db.focus and db.focus.enabled then
		local f = oUF:Spawn("focus", "ddingUI_Focus")
		ApplyUnitPosition(f, db.focus, "LEFT", UIParent, "LEFT", 80, -100)
		ns.frames.focus = f
	end

	-- Focus Target (anchored to focus)
	if db.focustarget and db.focustarget.enabled then
		local f = oUF:Spawn("focustarget", "ddingUI_FocusTarget")
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
			ApplyPosition(f, cfg.position, "LEFT", parentFrame, "RIGHT", 5, 0)
		end
		ns.frames.focustarget = f
	end

	-- Pet (anchored to player)
	if db.pet and db.pet.enabled then
		local f = oUF:Spawn("pet", "ddingUI_Pet")
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
			ApplyPosition(f, cfg.position, "BOTTOMLEFT", parentFrame, "TOPLEFT", 0, 8)
		end
		ns.frames.pet = f
	end
end

-----------------------------------------------
-- Spawn Boss Frames
-----------------------------------------------

function Spawn:SpawnBossFrames()
	local db = ns.db
	if not db.boss or not db.boss.enabled then return end

	local settings = db.boss
	local spacing = settings.spacing or 48

	for i = 1, C.MAX_BOSS_FRAMES do
		local f = oUF:Spawn("boss" .. i, "ddingUI_Boss" .. i)

		if i == 1 then
			ApplyPosition(f, settings.position, "RIGHT", UIParent, "RIGHT", -60, 100)
		else
			local prev = ns.frames["boss" .. (i - 1)]
			if settings.growDirection == "UP" then
				f:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
			else
				f:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
			end
		end

		ns.frames["boss" .. i] = f
	end
end

-----------------------------------------------
-- Spawn Arena Frames
-----------------------------------------------

function Spawn:SpawnArenaFrames()
	local db = ns.db
	if not db.arena or not db.arena.enabled then return end

	local settings = db.arena
	local spacing = settings.spacing or 48

	for i = 1, C.MAX_ARENA_FRAMES do
		local f = oUF:Spawn("arena" .. i, "ddingUI_Arena" .. i)

		if i == 1 then
			ApplyPosition(f, settings.position, "RIGHT", UIParent, "RIGHT", -60, 100)
		else
			local prev = ns.frames["arena" .. (i - 1)]
			if settings.growDirection == "UP" then
				f:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
			else
				f:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
			end
		end

		ns.frames["arena" .. i] = f
	end
end

-----------------------------------------------
-- Spawn Group Frames (Party + Raid)
-- GroupFrames 모듈 (SecureGroupHeaderTemplate 직접 사용)
-----------------------------------------------

function Spawn:SpawnGroupFrames()
	local GF = ns.GroupFrames
	if GF and GF.Initialize then
		GF:Initialize()
		ns.Debug("GroupFrames module initialized")
	else
		ns.Debug("|cffff0000GroupFrames module not found|r")
	end
end
