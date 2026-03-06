--[[
	ddingUI UnitFrames
	Modules/ClickCasting.lua - 유닛프레임 클릭 시 주문 시전

	마우스 버튼 + 수정키 조합 → 주문 자동 시전
	Secure attribute 기반 (전투 중 변경 불가)
]]

local _, ns = ...

local ClickCasting = {}
ns.ClickCasting = ClickCasting

local InCombatLockdown = InCombatLockdown

-----------------------------------------------
-- Cell 애드온 연동 -- [REFACTOR]
-----------------------------------------------

local cellDetected = nil -- nil = 미확인, true/false = 확인됨

local function IsCellAvailable()
	if cellDetected ~= nil then return cellDetected end
	-- Cell 글로벌 테이블 또는 애드온 로드 확인
	if _G.Cell and _G.Cell.F then
		cellDetected = true
	else
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Cell")
		cellDetected = loaded and _G.Cell and _G.Cell.F and true or false
	end
	return cellDetected
end

-- Cell 클릭캐스팅을 프레임에 적용 (Cell_UF 패턴)
local function ApplyCellClickCasting(frame)
	if InCombatLockdown() then return false end
	local Cell = _G.Cell
	if not Cell or not Cell.F then return false end

	local ok = true

	-- Cell.F.GetBindingSnippet → secure snippet 적용
	if Cell.F.GetBindingSnippet then
		local snippet = Cell.F.GetBindingSnippet()
		if snippet and snippet ~= "" then
			frame:SetAttribute("clickcast_onenter", snippet)
		end
	end

	-- Cell.F.UpdateClickCastOnFrame → 프레임에 클릭캐스트 바인딩 적용
	if Cell.F.UpdateClickCastOnFrame then
		local success, err = pcall(Cell.F.UpdateClickCastOnFrame, frame)
		if not success then
			ok = false
		end
	else
		ok = false
	end

	return ok
end

-- Cell 클릭캐스팅 해제
local function RemoveCellClickCasting(frame)
	if InCombatLockdown() then return end
	-- 기본 바인딩으로 복원
	frame:SetAttribute("clickcast_onenter", nil)
	frame:SetAttribute("type1", "target")
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("type2", "togglemenu")
	frame:SetAttribute("*type2", "togglemenu")
end

-----------------------------------------------
-- Default Bindings
-----------------------------------------------

local defaultBindings = {
	-- { button, modifiers, action, spellName }
	-- button: "1" (left), "2" (right), "3" (middle), "4", "5"
	-- modifiers: "" (none), "shift-", "ctrl-", "alt-", "shift-ctrl-", etc.
	-- action: "spell", "macro", "target", "focus", "menu"
}

-----------------------------------------------
-- Apply Bindings to Frame
-----------------------------------------------

local function ClearBindings(frame)
	if InCombatLockdown() then return end

	-- type1 = target (좌클릭 기본)
	-- type2 = menu (우클릭 기본)
	frame:SetAttribute("type1", "target")
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("type2", "togglemenu")
	frame:SetAttribute("*type2", "togglemenu")

	-- 수정키 조합 제거
	for _, mod in ipairs({"shift-", "ctrl-", "alt-", "shift-ctrl-", "shift-alt-", "ctrl-alt-"}) do
		for btn = 1, 5 do
			frame:SetAttribute(mod .. "type" .. btn, nil)
			frame:SetAttribute(mod .. "spell" .. btn, nil)
			frame:SetAttribute(mod .. "macro" .. btn, nil)
			frame:SetAttribute(mod .. "macrotext" .. btn, nil)
		end
	end
end

local function ApplyBinding(frame, binding)
	if InCombatLockdown() then return end
	if not binding then return end

	local btn = binding.button or "1"
	local mod = binding.modifiers or ""
	local action = binding.action or "spell"
	local value = binding.value or ""

	if action == "spell" then
		frame:SetAttribute(mod .. "type" .. btn, "spell")
		frame:SetAttribute(mod .. "spell" .. btn, value)
	elseif action == "macro" then
		frame:SetAttribute(mod .. "type" .. btn, "macro")
		frame:SetAttribute(mod .. "macrotext" .. btn, value)
	elseif action == "target" then
		frame:SetAttribute(mod .. "type" .. btn, "target")
	elseif action == "focus" then
		frame:SetAttribute(mod .. "type" .. btn, "focus")
	elseif action == "menu" then
		frame:SetAttribute(mod .. "type" .. btn, "togglemenu")
	end
end

-----------------------------------------------
-- Public API
-----------------------------------------------

function ClickCasting:ApplyToFrame(frame)
	if not frame or InCombatLockdown() then return end

	-- [REFACTOR] Cell 클릭캐스팅 우선 적용
	local ccDB = ns.db and ns.db.clickCasting
	local useCellCC = ccDB and ccDB.useCell
	if useCellCC and IsCellAvailable() then
		if ApplyCellClickCasting(frame) then
			return -- Cell 바인딩 적용 성공
		end
		-- Cell 적용 실패 시 기본 바인딩으로 fallback
	end

	local bindings = ccDB and ccDB.bindings
	if not bindings or #bindings == 0 then return end

	ClearBindings(frame)

	for _, binding in ipairs(bindings) do
		if binding.enabled ~= false then
			ApplyBinding(frame, binding)
		end
	end
end

function ClickCasting:ApplyToAllFrames()
	if InCombatLockdown() then
		ns.Print("전투 중에는 클릭캐스팅을 변경할 수 없습니다.")
		return
	end

	-- 개별 유닛 프레임
	if ns.frames then
		for _, frame in pairs(ns.frames) do
			self:ApplyToFrame(frame)
		end
	end

	-- 파티 헤더 자식 -- [PERF] GetChildren() 1회만 호출
	if ns.headers and ns.headers.party then
		local children = { ns.headers.party:GetChildren() }
		for _, child in ipairs(children) do
			if child then
				self:ApplyToFrame(child)
			end
		end
	end

	-- 레이드 헤더 자식 -- [PERF] GetChildren() 1회만 호출
	if ns.headers then
		for g = 1, 8 do
			local header = ns.headers["raid_group" .. g]
			if header then
				local children = { header:GetChildren() }
				for _, child in ipairs(children) do
					if child then
						self:ApplyToFrame(child)
					end
				end
			end
		end
	end

	-- GroupFrames 모듈 자식 (oUF 비의존 파티/레이드)
	local GF = ns.GroupFrames
	if GF and GF.allFrames then
		for _, frame in pairs(GF.allFrames) do
			if frame then
				self:ApplyToFrame(frame)
			end
		end
	end
end

function ClickCasting:RemoveFromFrame(frame)
	if not frame or InCombatLockdown() then return end
	-- [REFACTOR] Cell 바인딩도 해제
	local ccDB = ns.db and ns.db.clickCasting
	if ccDB and ccDB.useCell and IsCellAvailable() then
		RemoveCellClickCasting(frame)
	end
	ClearBindings(frame)
end

function ClickCasting:RemoveFromAllFrames()
	if InCombatLockdown() then return end

	if ns.frames then
		for _, frame in pairs(ns.frames) do
			ClearBindings(frame)
		end
	end

	-- [PERF] GetChildren() 1회만 호출
	if ns.headers and ns.headers.party then
		local children = { ns.headers.party:GetChildren() }
		for _, child in ipairs(children) do
			if child then ClearBindings(child) end
		end
	end

	if ns.headers then
		for g = 1, 8 do
			local header = ns.headers["raid_group" .. g]
			if header then
				local children = { header:GetChildren() }
				for _, child in ipairs(children) do
					if child then ClearBindings(child) end
				end
			end
		end
	end

	-- GroupFrames 모듈 자식
	local GF = ns.GroupFrames
	if GF and GF.allFrames then
		for _, frame in pairs(GF.allFrames) do
			if frame then ClearBindings(frame) end
		end
	end
end

function ClickCasting:AddBinding(button, modifiers, action, value)
	if not ns.db.clickCasting then
		ns.db.clickCasting = { enabled = true, bindings = {} }
	end

	table.insert(ns.db.clickCasting.bindings, {
		enabled = true,
		button = button or "1",
		modifiers = modifiers or "",
		action = action or "spell",
		value = value or "",
	})

	self:ApplyToAllFrames()
end

function ClickCasting:RemoveBinding(index)
	if not ns.db.clickCasting or not ns.db.clickCasting.bindings then return end
	table.remove(ns.db.clickCasting.bindings, index)
	self:ApplyToAllFrames()
end

function ClickCasting:Initialize()
	if not ns.db.clickCasting or not ns.db.clickCasting.enabled then return end

	-- [REFACTOR] Cell 감지 상태 초기화
	cellDetected = nil -- 재검사
	if IsCellAvailable() then
		local ccDB = ns.db.clickCasting
		if ccDB.useCell then
			if ns.Print then ns.Print("|cff00ccffCell|r 클릭캐스팅 연동 활성화") end
		end
	end

	self:ApplyToAllFrames()
end

-----------------------------------------------
-- Cell 상태 조회 API -- [REFACTOR]
-----------------------------------------------

function ClickCasting:IsCellDetected()
	return IsCellAvailable()
end

function ClickCasting:SetUseCellClickCasting(enabled)
	if not ns.db.clickCasting then
		ns.db.clickCasting = { enabled = true, bindings = {} }
	end
	ns.db.clickCasting.useCell = enabled
	if not InCombatLockdown() then
		self:ApplyToAllFrames()
	end
end
