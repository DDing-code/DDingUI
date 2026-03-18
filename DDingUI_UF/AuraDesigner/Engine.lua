--[[
	ddingUI UnitFrames
	AuraDesigner/Engine.lua — Runtime aura matching + indicator dispatch
	
	DandersFrames Engine.lua 패턴 기반.
	프레임 업데이트 시 오라 수집 → 인디케이터 매칭 → 렌더링 디스패치.
]]

local _, ns = ...

local pairs, ipairs, type, wipe = pairs, ipairs, type, wipe
local table_sort = table.sort
local table_insert = table.insert

local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit

ns.AuraDesigner = ns.AuraDesigner or {}
local Engine = {}
ns.AuraDesigner.Engine = Engine

-- ============================================================
-- FORWARD REFERENCES (set after PLAYER_LOGIN)
-- ============================================================

local Adapter      -- ns.AuraDesigner.Adapter
local Indicators   -- ns.AuraDesigner.Indicators
local LinkedAuras  -- ns.AuraDesigner.LinkedAuras
local Presets      -- ns.AuraDesigner.Presets
local AD           -- ns.AuraDesigner

-- ============================================================
-- DB ACCESS
-- ============================================================

local function GetAuraDesignerDB()
	return ns.db and ns.db.auraDesigner
end

-- spec-scoped aura config
local function GetSpecAuras(spec)
	local adDB = GetAuraDesignerDB()
	if not adDB then return {} end
	if not adDB.auras then adDB.auras = {} end
	spec = spec or Engine:ResolveSpec()
	if not spec then return {} end
	if not adDB.auras[spec] then adDB.auras[spec] = {} end
	return adDB.auras[spec]
end

-- spec-scoped layout groups
local function GetSpecLayoutGroups(spec)
	local adDB = GetAuraDesignerDB()
	if not adDB then return {} end
	if not adDB.layoutGroups then adDB.layoutGroups = {} end
	spec = spec or Engine:ResolveSpec()
	if not spec then return {} end
	if not adDB.layoutGroups[spec] then adDB.layoutGroups[spec] = {} end
	return adDB.layoutGroups[spec]
end

-- ============================================================
-- SPEC RESOLUTION
-- ============================================================

function Engine:ResolveSpec()
	local adDB = GetAuraDesignerDB()
	if not adDB then return nil end
	if adDB.spec == "auto" or not adDB.spec then
		return Adapter and Adapter:GetPlayerSpec()
	end
	return adDB.spec
end

-- ============================================================
-- PRIORITY SORT
-- ============================================================

-- Reusable buffer
local dispatchBuffer = {}

local function PrioritySorter(a, b)
	local pa = a.priority or 5
	local pb = b.priority or 5
	if pa ~= pb then return pa > pb end
	return (a.auraName or "") < (b.auraName or "")
end

-- ============================================================
-- CORE: Update Frame
-- ============================================================

-- frame state table: frame.adState = {
--   frameLevelApplied = { border = true, ... }
--   spec = "RestorationDruid"
-- }

local function EnsureFrameState(frame)
	if not frame.adState then
		frame.adState = {
			frameLevelApplied = {},
			indicatorsRendered = {},
			spec = nil,
		}
	end
	return frame.adState
end

function Engine:UpdateFrame(frame, unit)
	if not frame or not unit then return end
	if not UnitExists(unit) then return end

	local adDB = GetAuraDesignerDB()
	if not adDB or not adDB.enabled then
		-- AD disabled → revert all
		if frame.adState then
			self:RevertFrame(frame)
		end
		return
	end

	local spec = self:ResolveSpec()
	if not spec then return end

	-- Gather active auras for this unit
	if not Adapter then return end
	local activeAuras = Adapter:GetUnitAuras(unit, spec)
	if not activeAuras then return end

	-- Merge linked auras (e.g. Symbiotic Relationship)
	if LinkedAuras then
		local extras = LinkedAuras:ProcessUnit(unit, spec, activeAuras)
		if extras then
			for auraName, auraData in pairs(extras) do
				if not activeAuras[auraName] then
					activeAuras[auraName] = auraData
				end
			end
		end
	end

	-- Get spec-scoped aura configs
	local specAuras = GetSpecAuras(spec)

	-- Ensure frame state
	local fState = EnsureFrameState(frame)
	fState.spec = spec

	-- Begin frame (clear previous render)
	if Indicators then
		Indicators:BeginFrame(frame)
	end

	-- Collect dispatch entries
	local dispatchCount = 0
	for auraName, auraData in pairs(activeAuras) do
		local auraCfg = specAuras[auraName]
		if auraCfg then
			dispatchCount = dispatchCount + 1
			local entry = dispatchBuffer[dispatchCount]
			if not entry then
				entry = {}
				dispatchBuffer[dispatchCount] = entry
			end
			entry.auraName = auraName
			entry.auraData = auraData
			entry.priority = auraCfg.priority or 5
			entry.config   = auraCfg
		end
	end

	-- Clear excess buffer entries
	for i = dispatchCount + 1, #dispatchBuffer do
		dispatchBuffer[i] = nil
	end

	-- Sort by priority (highest first)
	if dispatchCount > 1 then
		table_sort(dispatchBuffer, PrioritySorter)
	end

	-- Dispatch: frame-level effects (only winner applies)
	local frameLevelWinner = nil
	for i = 1, dispatchCount do
		local entry = dispatchBuffer[i]
		if not frameLevelWinner then
			frameLevelWinner = entry
		end

		local config = entry.config
		local auraData = entry.auraData

		-- Placed indicators: all render independently
		if config.indicators and Indicators then
			for _, inst in ipairs(config.indicators) do
				local typeKey = inst.type
				if typeKey == "icon" then
					Indicators:ApplyIcon(frame, inst, auraData, entry.auraName)
				elseif typeKey == "square" then
					Indicators:ApplySquare(frame, inst, auraData, entry.auraName)
				elseif typeKey == "bar" then
					Indicators:ApplyBar(frame, inst, auraData, entry.auraName)
				end
			end
		end
	end

	-- Frame-level effects: only highest priority winner
	if frameLevelWinner and Indicators then
		local config = frameLevelWinner.config
		local auraData = frameLevelWinner.auraData

		if config.border then
			Indicators:ApplyBorder(frame, config.border, auraData)
			fState.frameLevelApplied.border = true
		end
		if config.healthbar then
			Indicators:ApplyHealthBar(frame, config.healthbar, auraData)
			fState.frameLevelApplied.healthbar = true
		end
		if config.nametext then
			Indicators:ApplyNameText(frame, config.nametext, auraData)
			fState.frameLevelApplied.nametext = true
		end
		if config.healthtext then
			Indicators:ApplyHealthText(frame, config.healthtext, auraData)
			fState.frameLevelApplied.healthtext = true
		end
		if config.framealpha then
			Indicators:ApplyFrameAlpha(frame, config.framealpha, auraData)
			fState.frameLevelApplied.framealpha = true
		end
	end

	-- End frame (hide unused indicators, revert absent frame-level effects)
	if Indicators then
		Indicators:EndFrame(frame, fState)
	end
end

-- ============================================================
-- REVERT FRAME (AD disabled or stale)
-- ============================================================

function Engine:RevertFrame(frame)
	if not frame.adState then return end
	if Indicators then
		Indicators:RevertAll(frame)
	end
	frame.adState = nil
end

-- ============================================================
-- GROUP FRAMES INTEGRATION
-- ============================================================

function Engine:UpdateGroupFrame(frame)
	if not frame or not frame.unit then return end
	self:UpdateFrame(frame, frame.unit)
end

function Engine:UpdateAllGroupFrames()
	local GF = ns.GroupFrames
	if not GF or not GF.allFrames then return end
	for _, frame in ipairs(GF.allFrames) do
		if frame and frame:IsVisible() and frame.unit then
			self:UpdateFrame(frame, frame.unit)
		end
	end
end

-- ============================================================
-- STANDALONE FRAMES INTEGRATION
-- ============================================================

function Engine:UpdateStandaloneFrame(frame)
	if not frame or not frame.unit then return end
	-- Only party/raid units (not boss/arena/player)
	local unit = frame.unit
	local prefix = unit:match("^(%a+)")
	if prefix ~= "party" and prefix ~= "raid" then return end
	self:UpdateFrame(frame, unit)
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

function Engine:Initialize()
	AD = ns.AuraDesigner
	Adapter = AD.Adapter
	Indicators = AD.Indicators
	LinkedAuras = AD.LinkedAuras
	Presets = AD.Presets

	-- Initialize DB defaults if needed
	if ns.db and not ns.db.auraDesigner then
		ns.db.auraDesigner = {
			enabled = true, -- 프리셋이 있으므로 기본 활성화!
			spec = "auto",
			auras = {},
			layoutGroups = {},
			defaults = {
				iconSize = 20, iconScale = 1.0,
				showDuration = true, showStacks = true,
				durationScale = 1.0, durationOutline = "OUTLINE",
			},
		}
	end

	-- 프리셋 자동 적용: 유저 데이터가 없는 스펙에 기본 프리셋 주입
	if Presets then
		Presets:ApplyAllDefaults()
	end
end

-- Lazy initialization on first UpdateFrame call
local initialized = false
local function EnsureInitialized()
	if initialized then return end
	initialized = true
	Engine:Initialize()
end

-- Wrap UpdateFrame to ensure init
local _origUpdateFrame = Engine.UpdateFrame
function Engine:UpdateFrame(frame, unit)
	EnsureInitialized()
	return _origUpdateFrame(self, frame, unit)
end
