--[[
	oUF Highlight Element (Standalone Plugin)
	Target/Focus/Hover 보더 강조 - DandersFrames 영감
	Phase 1: SOLID 스타일만 구현

	[12.0.1] 신규 oUF element

	사용법:
	- Layout에서 self.Highlight = { target = frame, focus = frame, hover = frame }
	- 각 프레임은 BackdropTemplate 기반 보더 프레임
	- target/focus는 oUF 이벤트로 자동 업데이트
	- hover는 OnEnter/OnLeave로 Layout에서 처리

	oUF Element API:
	- oUF:AddElement(name, update, enable, disable)
	- self:RegisterEvent(event, callback, unitless)
]]

local _, ns = ...
local oUF = ns.oUF

-- [STANDALONE] oUF가 없어도 핵심 로직이 로드되도록
local hasOUF = (oUF ~= nil)

local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit

-----------------------------------------------
-- Update Functions
-----------------------------------------------

-- Target 보더 업데이트
local function UpdateTarget(self)
	local element = self.Highlight
	if not element or not element.target then return end

	local hlDB = element._db
	if not hlDB or not hlDB.target then
		element.target:Hide()
		return
	end

	if self.unit and UnitExists(self.unit) and UnitIsUnit(self.unit, "target") then
		-- [FIX] ns.Colors.highlight.target 글로벌 색상 우선 적용
		local color = (ns.Colors and ns.Colors.highlight and ns.Colors.highlight.target) or hlDB.targetColor or { 1, 0.3, 0.3, 1 }
		element.target:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
		element.target:Show()
	else
		element.target:Hide()
	end
end

-- Focus 보더 업데이트
local function UpdateFocus(self)
	local element = self.Highlight
	if not element or not element.focus then return end

	local hlDB = element._db
	if not hlDB or not hlDB.focus then
		element.focus:Hide()
		return
	end

	if self.unit and UnitExists(self.unit) and UnitIsUnit(self.unit, "focus") then
		-- [FIX] ns.Colors.highlight.focus 글로벌 색상 우선 적용
		local color = (ns.Colors and ns.Colors.highlight and ns.Colors.highlight.focus) or hlDB.focusColor or { 0.3, 0.6, 1, 1 }
		element.focus:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
		element.focus:Show()
	else
		element.focus:Hide()
	end
end

-----------------------------------------------
-- oUF Element Callbacks
-----------------------------------------------

local function Update(self, event, unit)
	-- PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED는 unitless
	-- unit 파라미터가 없거나 자기 유닛일 때만 처리
	if event == "PLAYER_TARGET_CHANGED" then
		UpdateTarget(self)
	elseif event == "PLAYER_FOCUS_CHANGED" then
		UpdateFocus(self)
	else
		-- ForceUpdate 등: 전부 갱신
		UpdateTarget(self)
		UpdateFocus(self)
	end
end

local function Path(self, ...)
	return (self.Highlight and self.Highlight.Override or Update)(self, ...)
end

local function ForceUpdate(element)
	return Path(element.__owner, "ForceUpdate", element.__owner.unit)
end

local function Enable(self, unit)
	local element = self.Highlight
	if not element then return end

	element.__owner = self
	element.ForceUpdate = ForceUpdate

	-- PLAYER_TARGET_CHANGED: unitless 이벤트 -- [12.0.1]
	if element.target then
		self:RegisterEvent("PLAYER_TARGET_CHANGED", Path, true)
	end

	-- PLAYER_FOCUS_CHANGED: unitless 이벤트 -- [12.0.1]
	if element.focus then
		self:RegisterEvent("PLAYER_FOCUS_CHANGED", Path, true)
	end

	-- 초기 상태 갱신
	UpdateTarget(self)
	UpdateFocus(self)

	return true
end

local function Disable(self)
	local element = self.Highlight
	if not element then return end

	if element.target then
		element.target:Hide()
		self:UnregisterEvent("PLAYER_TARGET_CHANGED", Path)
	end

	if element.focus then
		element.focus:Hide()
		self:UnregisterEvent("PLAYER_FOCUS_CHANGED", Path)
	end
end

-- oUF element 등록 -- [12.0.1]
if hasOUF then
	oUF:AddElement("Highlight", Update, Enable, Disable)
end

-- [STANDALONE] ElementDrivers에서 사용
ns.HighlightUpdate = function(frame)
	if frame and frame.Highlight then
		Update(frame, "ForceUpdate", frame.unit)
	end
end
