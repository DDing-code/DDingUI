--[[
	ddingUI UnitFrames
	GroupFrames/Headers.lua — SecureGroupHeaderTemplate 생성

	oUF 없이 직접 SecureGroupHeaderTemplate 사용
	DandersFrames InitializeHeaderChild + OnAttributeChanged 패턴
]]

local _, ns = ...
local GF = ns.GroupFrames

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local IsInRaid = IsInRaid
local SecureButton_GetModifiedUnit = SecureButton_GetModifiedUnit
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local UIParent = UIParent
local C_Timer = C_Timer
local wipe = wipe
local issecretvalue = issecretvalue
local SafeVal = ns.SafeVal   -- [REFACTOR] 통합 유틸리티

local C = ns.Constants

-----------------------------------------------
-- [MYTHIC-RAID] 활성 레이드 DB 선택
-----------------------------------------------

-- 현재 난이도에 맞는 레이드 DB 반환
function GF:GetActiveRaidDB()
	if ns._mythicRaidActive and ns.db.mythicRaid and ns.db.mythicRaid.enabled then
		return ns.db.mythicRaid
	end
	return ns.db.raid
end

-----------------------------------------------
-- Growth Direction Helpers (Spawn.lua에서 가져옴)
-----------------------------------------------

local GROW_TO_POINT = ns.GROW_TO_POINT or {
	DOWN  = "TOP",
	UP    = "BOTTOM",
	RIGHT = "LEFT",
	LEFT  = "RIGHT",
	H_CENTER = "LEFT",
	V_CENTER = "TOP",
}

local COLUMN_GROW_TO_ANCHOR = ns.COLUMN_GROW_TO_ANCHOR or {
	RIGHT = "LEFT",
	LEFT  = "RIGHT",
	DOWN  = "TOP",
	UP    = "BOTTOM",
}

local function GetGrowOffsets(growDir, spacing)
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

-----------------------------------------------
-- InitializeHeaderChild (DF 패턴)
-----------------------------------------------

function GF:InitializeHeaderChild(frame)
	if not frame then return end
	if frame.gfInitialized then return end

	-- 프레임 타입 판별 (부모 이름으로)
	local parent = frame:GetParent()
	local isRaid = false
	if parent then
		local parentName = parent:GetName() or ""
		isRaid = parentName:find("Raid") ~= nil
	end

	frame.isRaidFrame = isRaid
	frame.gfIsHeaderChild = true
	frame.gfEventsEnabled = true

	-- 프레임 크기 설정
	local db = self:GetFrameDB(frame)
	local size = db.size or { 120, 36 }
	-- [FIX] 전투 중 SetSize taint 방지 → ApplyLayout에서 지연 처리
	if not InCombatLockdown() then
		frame:SetSize(size[1], size[2])
	end

	-- 비주얼 요소 생성
	self:CreateFrameElements(frame)

	-- OnAttributeChanged: unit 변경 감지 + unitFrameMap 갱신
	frame:HookScript("OnAttributeChanged", function(self, name, value)
		if name ~= "unit" then return end

		local actualUnit = value and SecureButton_GetModifiedUnit(self) or nil
		local oldUnit = self.unit

		-- GUID 비교로 실제 플레이어 변경 감지 (DF 3단계 최적화)
		-- [REFACTOR] SafeVal 통일: UnitGUID는 secret string 반환 가능
		local newGuid = actualUnit and SafeVal(UnitGUID(actualUnit)) or nil
		local oldGuid = oldUnit and SafeVal(GF.unitGuidCache[oldUnit]) or nil

		-- Level 1: 유닛 문자열 + GUID 모두 동일 → 스킵
		if oldUnit == actualUnit then
			if newGuid and oldGuid and newGuid == oldGuid then
				return
			end
		end

		-- Level 2: 유닛 문자열 다르지만 GUID 동일 → 슬롯 이동만 (맵만 갱신)
		if actualUnit and oldUnit and newGuid and oldGuid and newGuid == oldGuid then
			if GF.unitFrameMap[oldUnit] == self then
				GF.unitFrameMap[oldUnit] = nil
			end
			GF.unitFrameMap[actualUnit] = self
			self.unit = actualUnit
			GF.unitGuidCache[actualUnit] = newGuid
			return
		end

		-- Level 3: 실제 플레이어 변경 → 풀 리프레시
		if oldUnit then
			if GF.unitFrameMap[oldUnit] == self then
				GF.unitFrameMap[oldUnit] = nil
			end
		end

		self.unit = actualUnit
		self.gfCurrentBgKey = nil -- 색상 캐시 초기화
		self.gfInRange = nil     -- 거리 상태 초기화

		if actualUnit then
			GF.unitFrameMap[actualUnit] = self
			-- [REFACTOR] secret GUID는 저장하지 않음 (SafeVal 통일)
			local storeGuid = SafeVal(UnitGUID(actualUnit))
			GF.unitGuidCache[actualUnit] = storeGuid

			local num = actualUnit:match("%d+")
			if num then
				self.index = tonumber(num)
			elseif actualUnit == "player" then
				self.index = 0
			end

			-- 풀 리프레시 (다음 프레임)
			C_Timer.After(0, function()
				if self:IsVisible() and self.unit then
					if GF.FullFrameRefresh then
						GF:FullFrameRefresh(self)
					end
				end
			end)
		end
	end)

	-- [FIX] 초기 유닛 설정: SecureGroupHeaderTemplate이 Show() 시 이미 unit을 할당했지만
	-- HookScript는 그 이후에 등록되므로 OnAttributeChanged가 초기 유닛에 대해 발동 안 함
	-- → 명시적으로 현재 유닛을 읽어서 frame.unit 설정
	local currentUnit = SecureButton_GetModifiedUnit(frame)
	if currentUnit and currentUnit ~= "" then
		frame.unit = currentUnit
		GF.unitFrameMap[currentUnit] = frame
		local storeGuid = SafeVal(UnitGUID(currentUnit))
		GF.unitGuidCache[currentUnit] = storeGuid

		local num = currentUnit:match("%d+")
		if num then
			frame.index = tonumber(num)
		elseif currentUnit == "player" then
			frame.index = 0
		end
	end

	-- allFrames에 등록
	GF.allFrames[#GF.allFrames + 1] = frame

	-- ClickCasting 적용
	local CC = ns.ClickCasting
	if CC and CC.ApplyToFrame then
		CC:ApplyToFrame(frame)
	end

	-- [CLIQUE] 외부 클릭캐스팅 애드온 호환 (Clique, ClickCastFrames 패턴)
	-- oUF:Spawn 프레임은 oUF 내부에서 등록하지만, GroupFrames는 oUF를 거치지 않으므로 직접 등록
	_G.ClickCastFrames = _G.ClickCastFrames or {}
	_G.ClickCastFrames[frame] = true

	-- 레이아웃 적용
	if GF.ApplyLayout then
		GF:ApplyLayout(frame)
	end

	-- [FIX] 초기 유닛이 있으면 즉시 풀 리프레시 (다음 프레임)
	if frame.unit then
		C_Timer.After(0, function()
			if frame:IsVisible() and frame.unit then
				if GF.FullFrameRefresh then
					GF:FullFrameRefresh(frame)
				end
			end
		end)
	end

	frame.gfInitialized = true
end

-----------------------------------------------
-- 헤더 생성 (파티 + 레이드)
-----------------------------------------------

-- XML 템플릿 대신 Lua에서 직접 생성
-- SecureGroupHeaderTemplate이 자식을 생성할 때 initialConfigFunction 사용
local INIT_CONFIG_FUNC = [[
	local header = self:GetParent()
	self:SetWidth(header:GetAttribute("gf-width") or 120)
	self:SetHeight(header:GetAttribute("gf-height") or 36)
]]

function GF:CreateHeaders()
	local db = ns.db
	if not db then return end

	-- 파티 헤더
	if db.party and db.party.enabled then
		self:CreatePartyHeader()
	end

	-- 레이드 헤더
	if db.raid and db.raid.enabled then
		self:CreateRaidHeaders()
	end

	self.headersInitialized = true

	-- BlizzardAuraCache hook 설정
	if GF.SetupBlizzardHooks then
		GF:SetupBlizzardHooks()
	end

	-- 거리 체크 타이머 시작
	if GF.StartRangeTimer then
		GF:StartRangeTimer()
	end

	-- [PERF] 색상 타이머 활성화 (그룹 시에만)
	if GF.UpdateColorTimerState then
		GF:UpdateColorTimerState()
	end
end

-- [REFACTOR] SafeSetAttribute: 값 변경 시에만 SetAttribute 호출 (taint 최소화)
local headerAttrCache = {}
local function SafeSetAttribute(header, key, value)
	local name = header:GetName() or tostring(header)
	if not headerAttrCache[name] then headerAttrCache[name] = {} end
	local cache = headerAttrCache[name]
	if cache[key] == value then return end
	cache[key] = value
	header:SetAttribute(key, value)
end

function GF:CreatePartyHeader()
	local db = ns.db.party
	if not db then return end

	local visibility = "[group:party,nogroup:raid] show; hide"
	if db.showInRaid then
		visibility = "[group:party] show; hide"
	end

	-- groupBy 속성
	local groupByAttr = db.groupBy or "GROUP"
	local useGroupBy = nil
	local groupingOrder = nil
	if groupByAttr == "ROLE" then
		useGroupBy = "ASSIGNEDROLE"
		groupingOrder = "TANK,HEALER,DAMAGER,NONE"
	elseif groupByAttr == "CLASS" then
		useGroupBy = "CLASS"
		groupingOrder = "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,DEATHKNIGHT,SHAMAN,MAGE,WARLOCK,MONK,DRUID,DEMONHUNTER,EVOKER"
	end

	-- 성장 방향
	local growDir = db.growDirection or "DOWN"
	local colGrowDir = db.columnGrowDirection or "RIGHT"
	local point = GROW_TO_POINT[growDir] or "TOP"
	local colAnchor = COLUMN_GROW_TO_ANCHOR[colGrowDir] or "LEFT"
	local priKey, priVal, secKey, secVal = GetGrowOffsets(growDir, db.spacing or 4)
	local colSpacing = (colGrowDir == "LEFT" or colGrowDir == "UP") and -(db.spacingX or 4) or (db.spacingX or 4)

	local size = db.size or { 120, 36 }

	local header = CreateFrame("Frame", "ddingUI_GF_Party", UIParent, "SecureGroupHeaderTemplate")
	SafeSetAttribute(header, "template", "SecureUnitButtonTemplate")
	SafeSetAttribute(header, "showPlayer", db.showPlayer or false)
	SafeSetAttribute(header, "showSolo", false)
	SafeSetAttribute(header, "showParty", true)
	SafeSetAttribute(header, "showRaid", false)
	SafeSetAttribute(header, "point", point)
	SafeSetAttribute(header, priKey, priVal)
	SafeSetAttribute(header, secKey, secVal)
	SafeSetAttribute(header, "maxColumns", db.maxColumns or 1)
	SafeSetAttribute(header, "unitsPerColumn", db.unitsPerColumn or 5)
	SafeSetAttribute(header, "columnSpacing", colSpacing)
	SafeSetAttribute(header, "columnAnchorPoint", colAnchor)
	SafeSetAttribute(header, "sortDir", db.sortDir or "ASC")
	SafeSetAttribute(header, "sortMethod", db.sortBy or "INDEX")
	if useGroupBy then
		SafeSetAttribute(header, "groupBy", useGroupBy)
		SafeSetAttribute(header, "groupingOrder", groupingOrder)
	end
	SafeSetAttribute(header, "gf-width", size[1])
	SafeSetAttribute(header, "gf-height", size[2])

	-- initialConfigFunction: 자식 프레임 초기 설정
	SafeSetAttribute(header, "initialConfigFunction", INIT_CONFIG_FUNC)

	-- 가시성
	RegisterAttributeDriver(header, "state-visibility", visibility)

	-- 위치 -- [EDITMODE-FIX] string-array 형식 지원 (SaveMoverToDB 호환)
	local pos = db.position
	if pos and type(pos) == "table" and pos.point then
		header:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0)
	elseif pos and type(pos[1]) == "string" then
		local relativeTo = (pos[2] and _G[pos[2]]) or UIParent
		header:SetPoint(pos[1], relativeTo, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
	elseif pos and type(pos[1]) == "number" then
		header:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos[1] or 20, pos[2] or -40)
	else
		header:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -40)
	end

	-- [FIX] hook 먼저 등록 후 Show → Show 시점 + 지연 초기화로 자식 생성 대기
	-- [PERF] 3중 C_Timer → debounce 패턴 (중복 InitializeAllChildren 방지)
	local _initPending = false
	local function DebouncedInit(self)
		if _initPending then return end
		_initPending = true
		GF:InitializeAllChildren(self)
		C_Timer.After(0.3, function()
			_initPending = false
			GF:InitializeAllChildren(self)
		end)
	end
	hooksecurefunc(header, "Show", function(self)
		DebouncedInit(self)
	end)

	header:Show()

	-- 기존 자식도 초기화 — [PERF] 3중 → 2단계 (즉시 + 0.5초 후)
	GF:InitializeAllChildren(header)
	C_Timer.After(0.5, function() GF:InitializeAllChildren(header) end)

	-- [FIX] H_CENTER/V_CENTER 중앙 정렬: 멤버 수에 따라 헤더 위치 보정
	if growDir == "H_CENTER" or growDir == "V_CENTER" then
		local maxMembers = (db.showPlayer and 5 or 4)
		local sp = db.spacing or 4
		local frameW, frameH = size[1], size[2]

		-- [FIX] DB에서 매번 최신 위치를 읽는 헬퍼 (무버 이동 반영)
		-- [FIX] ns.db.movers["Party"] 우선 → db.position fallback
		local function ReadBasePosition()
			-- 무버 시스템 위치 우선 (편집모드에서 이동한 최신 위치)
			if ns.db.movers and ns.db.movers["Party"] then
				local mStr = ns.db.movers["Party"]
				if type(mStr) == "string" then
					local pt, _, rp, mx, my = strsplit(",", mStr)
					mx, my = tonumber(mx), tonumber(my)
					if pt and mx and my then
						return pt, UIParent, rp or pt, mx, my
					end
				end
			end
			-- fallback: db.position
			local pos = db.position
			if pos and type(pos) == "table" and pos.point then
				return pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0
			elseif pos and type(pos[1]) == "string" then
				return pos[1], (pos[2] and _G[pos[2]]) or UIParent, pos[3] or pos[1], pos[4] or 0, pos[5] or 0
			elseif pos and type(pos[1]) == "number" then
				return "TOPLEFT", UIParent, "TOPLEFT", pos[1] or 20, pos[2] or -40
			else
				return "TOPLEFT", UIParent, "TOPLEFT", 20, -40
			end
		end

		local function RecenterPartyHeader()
			if InCombatLockdown() then return end
			local count = 0
			for j = 1, 40 do
				local child = header:GetAttribute("child" .. j)
				if child and child:IsShown() then count = count + 1 else break end
			end
			if count == 0 then return end

			-- [FIX] 매번 DB에서 최신 위치 읽기 (무버로 이동한 위치 반영)
			local basePoint, baseRelTo, baseRelPoint, baseOffX, baseOffY = ReadBasePosition()

			header:ClearAllPoints()
			if growDir == "H_CENTER" then
				local maxW = maxMembers * frameW + (maxMembers - 1) * sp
				local actualW = count * frameW + (count - 1) * sp
				-- [FIX] 앵커에 LEFT/RIGHT가 없으면 X축이 이미 중앙 기준
				-- → padX = 0 (CENTER/TOP/BOTTOM 앵커)
				local padX = 0
				if basePoint:find("LEFT") then
					padX = (maxW - actualW) / 2
				elseif basePoint:find("RIGHT") then
					padX = -(maxW - actualW) / 2
				end
				header:SetPoint(basePoint, baseRelTo, baseRelPoint, baseOffX + padX, baseOffY)
			else -- V_CENTER
				local maxH = maxMembers * frameH + (maxMembers - 1) * sp
				local actualH = count * frameH + (count - 1) * sp
				-- [FIX] 앵커에 TOP/BOTTOM이 없으면 Y축이 이미 중앙 기준
				local padY = 0
				if basePoint:find("TOP") then
					padY = (maxH - actualH) / 2
				elseif basePoint:find("BOTTOM") then
					padY = -(maxH - actualH) / 2
				end
				header:SetPoint(basePoint, baseRelTo, baseRelPoint, baseOffX, baseOffY - padY)
			end
		end

		-- 파티 멤버 변경 시 재정렬
		local centerFrame = CreateFrame("Frame")
		centerFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
		centerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		centerFrame:SetScript("OnEvent", function()
			C_Timer.After(0.3, RecenterPartyHeader)
		end)
		-- Show 후에도 재정렬
		hooksecurefunc(header, "Show", function()
			C_Timer.After(0.3, RecenterPartyHeader)
		end)
	end

	self.partyHeader = header
	ns.headers = ns.headers or {}
	ns.headers.gf_party = header
end

function GF:CreateRaidHeaders()
	local db = self:GetActiveRaidDB()
	if not db then return end

	local raidVisibility = db.visibility or "[group:raid] show; hide"

	local groupByAttr = db.groupBy or "GROUP"
	local useGroupBy = nil
	local groupingOrder = nil
	if groupByAttr == "ROLE" then
		useGroupBy = "ASSIGNEDROLE"
		groupingOrder = "TANK,HEALER,DAMAGER,NONE"
	elseif groupByAttr == "CLASS" then
		useGroupBy = "CLASS"
		groupingOrder = "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,DEATHKNIGHT,SHAMAN,MAGE,WARLOCK,MONK,DRUID,DEMONHUNTER,EVOKER"
	end

	local growDir = db.growDirection or "DOWN"
	local groupGrowDir = db.groupGrowDirection -- [REFACTOR] 그룹 간 배치 방향 독립 제어
	local point = GROW_TO_POINT[growDir] or "TOP"
	local priKey, priVal, secKey, secVal = GetGrowOffsets(growDir, db.spacingY or 3)
	local size = db.size or { 66, 46 }
	local maxGroups = db.maxGroups or (C and C.MAX_RAID_GROUPS or 8)

	self.raidHeaders = {}

	for i = 1, maxGroups do
		local header = CreateFrame("Frame", "ddingUI_GF_Raid_Group" .. i, UIParent, "SecureGroupHeaderTemplate")
		SafeSetAttribute(header, "template", "SecureUnitButtonTemplate")
		SafeSetAttribute(header, "showPlayer", true)
		SafeSetAttribute(header, "showSolo", false)
		SafeSetAttribute(header, "showParty", false)
		SafeSetAttribute(header, "showRaid", true)
		SafeSetAttribute(header, "groupFilter", tostring(i))
		SafeSetAttribute(header, "point", point)
		SafeSetAttribute(header, priKey, priVal)
		SafeSetAttribute(header, secKey, secVal)
		SafeSetAttribute(header, "unitsPerColumn", db.unitsPerColumn or 5)
		SafeSetAttribute(header, "maxColumns", db.maxColumns or 1)
		SafeSetAttribute(header, "sortDir", db.sortDir or "ASC")
		SafeSetAttribute(header, "sortMethod", db.sortBy or "INDEX")
		if useGroupBy then
			SafeSetAttribute(header, "groupBy", useGroupBy)
			SafeSetAttribute(header, "groupingOrder", groupingOrder)
		end
		SafeSetAttribute(header, "gf-width", size[1])
		SafeSetAttribute(header, "gf-height", size[2])
		SafeSetAttribute(header, "initialConfigFunction", INIT_CONFIG_FUNC)

		RegisterAttributeDriver(header, "state-visibility", raidVisibility)

		-- 위치 -- [EDITMODE-FIX] string-array 형식 지원 (SaveMoverToDB 호환)
		if i == 1 then
			local pos = db.position
			if pos and type(pos) == "table" and pos.point then
				header:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0)
			elseif pos and type(pos[1]) == "string" then
				local relativeTo = (pos[2] and _G[pos[2]]) or UIParent
				header:SetPoint(pos[1], relativeTo, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
			elseif pos and type(pos[1]) == "number" then
				header:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos[1] or 20, pos[2] or -100)
			else
				header:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -100)
			end
		else
			local prev = self.raidHeaders[i - 1]
			local gSpacing = db.groupSpacing or 5
			-- [REFACTOR] groupGrowDirection 독립 제어, 미설정 시 기존 로직 유지
			local gGrow = groupGrowDir
			if not gGrow then
				-- [FIX] 유닛 수직 성장(DOWN/UP/V_CENTER) → 그룹 오른쪽
				--       유닛 수평 성장(RIGHT/LEFT/H_CENTER) → 그룹 아래 (수직 교차)
				if growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER" then
					gGrow = "RIGHT"
				else
					gGrow = "DOWN"
				end
			end
			-- [FIX] 그룹 간 앵커: growDirection에 따라 정렬 기준선 결정
			-- 유닛 DOWN → 그룹 TOP 정렬, 유닛 UP → 그룹 BOTTOM 정렬
			local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
			if gGrow == "RIGHT" or gGrow == "LEFT" then
				-- 가로 배치: Y축 정렬은 growDirection 기반
				local yEdge = "TOP" -- 기본: DOWN (위 정렬)
				if not priIsVert then
					yEdge = "TOP" -- 가로 유닛일 때 기본값
				elseif growDir == "UP" then
					yEdge = "BOTTOM"
				end
				if gGrow == "RIGHT" then
					header:SetPoint(yEdge .. "LEFT", prev, yEdge .. "RIGHT", gSpacing, 0)
				else -- LEFT
					header:SetPoint(yEdge .. "RIGHT", prev, yEdge .. "LEFT", -gSpacing, 0)
				end
			elseif gGrow == "DOWN" or gGrow == "UP" then
				-- 세로 배치: X축 정렬은 growDirection 기반
				local xEdge = "LEFT" -- 기본: RIGHT (왼쪽 정렬)
				if priIsVert then
					xEdge = "LEFT" -- 세로 유닛일 때 기본값
				elseif growDir == "LEFT" then
					xEdge = "RIGHT"
				end
				if gGrow == "DOWN" then
					header:SetPoint("TOP" .. xEdge, prev, "BOTTOM" .. xEdge, 0, -gSpacing)
				else -- UP
					header:SetPoint("BOTTOM" .. xEdge, prev, "TOP" .. xEdge, 0, gSpacing)
				end
			else
				-- fallback
				header:SetPoint("TOPLEFT", prev, "TOPRIGHT", gSpacing, 0)
			end
		end

		-- [PERF] hook: 즉시 초기화 + 디바운스 지연 (per-header 3× C_Timer → 1× 디바운스)
		hooksecurefunc(header, "Show", function(self)
			GF:InitializeAllChildren(self)
			-- 디바운스: 동일 프레임 내 여러 Show 호출을 0.3초 후 1회로 병합
			if not self._initQueued then
				self._initQueued = true
				C_Timer.After(0.3, function()
					self._initQueued = nil
					GF:InitializeAllChildren(self)
				end)
			end
		end)

		header:Show()

		self.raidHeaders[i] = header
		ns.headers = ns.headers or {}
		ns.headers["gf_raid_group" .. i] = header
	end

	-- [PERF] 레이드 헤더 일괄 지연 초기화 (per-header 3× C_Timer → 일괄 2×)
	C_Timer.After(0.3, function()
		for _, rh in ipairs(self.raidHeaders) do
			if rh then GF:InitializeAllChildren(rh) end
		end
	end)
	C_Timer.After(1, function()
		for _, rh in ipairs(self.raidHeaders) do
			if rh then GF:InitializeAllChildren(rh) end
		end
		GF:RebuildUnitFrameMap()
	end)

	-- [FIX] H_CENTER/V_CENTER 중앙 정렬: 각 그룹 헤더의 자식 수에 따라 위치 보정 (무버 동기화 포함)
	if growDir == "H_CENTER" or growDir == "V_CENTER" then
		local maxMembers = 5
		local sp = db.spacingY or db.spacing or 3
		local frameW, frameH = size[1], size[2]

		local function ReadBaseRaidPosition()
			-- 무버 시스템 위치 우선 (편집모드에서 이동한 최신 위치)
			if ns.db.movers and ns.db.movers["Raid"] then
				local mStr = ns.db.movers["Raid"]
				if type(mStr) == "string" then
					local pt, _, rp, mx, my = strsplit(",", mStr)
					mx, my = tonumber(mx), tonumber(my)
					if pt and mx and my then
						return pt, UIParent, rp or pt, mx, my
					end
				end
			end
			-- fallback: db.position 
			local pos = db.position
			if pos and type(pos) == "table" and pos.point then
				return pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0
			elseif pos and type(pos[1]) == "string" then
				return pos[1], (pos[2] and _G[pos[2]]) or UIParent, pos[3] or pos[1], pos[4] or 0, pos[5] or 0
			elseif pos and type(pos[1]) == "number" then
				return "TOPLEFT", UIParent, "TOPLEFT", pos[1] or 20, pos[2] or -100
			else
				return "TOPLEFT", UIParent, "TOPLEFT", 20, -100
			end
		end

		local function RecenterRaidHeaders()
			if InCombatLockdown() then return end
			for idx, hdr in ipairs(self.raidHeaders) do
				if not hdr then break end
				local count = 0
				for j = 1, 40 do
					local child = hdr:GetAttribute("child" .. j)
					if child and child:IsShown() then count = count + 1 else break end
				end
				-- 첫 번째 헤더만 자체 중앙 정렬, 나머지는 prev 기준 상대 배치라 자동 따라감
				if idx == 1 and count > 0 then
					local bPoint, bRelTo, bRelPoint, bOffX, bOffY = ReadBaseRaidPosition()

					hdr:ClearAllPoints()
					if growDir == "H_CENTER" then
						local maxW = maxMembers * frameW + (maxMembers - 1) * sp
						local actualW = count * frameW + (count - 1) * sp
						local padX = 0
						if bPoint:find("LEFT") then
							padX = (maxW - actualW) / 2
						elseif bPoint:find("RIGHT") then
							padX = -(maxW - actualW) / 2
						end
						hdr:SetPoint(bPoint, bRelTo, bRelPoint, bOffX + padX, bOffY)
					else -- V_CENTER
						local maxH = maxMembers * frameH + (maxMembers - 1) * sp
						local actualH = count * frameH + (count - 1) * sp
						local padY = 0
						if bPoint:find("TOP") then
							padY = (maxH - actualH) / 2
						elseif bPoint:find("BOTTOM") then
							padY = -(maxH - actualH) / 2
						end
						hdr:SetPoint(bPoint, bRelTo, bRelPoint, bOffX, bOffY - padY)
					end
				end
			end
		end

		local raidCenterFrame = CreateFrame("Frame")
		raidCenterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
		raidCenterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		raidCenterFrame:SetScript("OnEvent", function()
			C_Timer.After(0.3, RecenterRaidHeaders)
		end)
		-- Show 후에도 재정렬
		if self.raidHeaders[1] then
			hooksecurefunc(self.raidHeaders[1], "Show", function()
				C_Timer.After(0.3, RecenterRaidHeaders)
			end)
		end
	end
end

-----------------------------------------------
-- [MYTHIC-RAID] 레이드 레이아웃 동적 적용 (난이도 전환용)
-----------------------------------------------

function GF:ApplyRaidLayoutFromDB(db)
	if InCombatLockdown() then
		ns._pendingRaidLayoutUpdate = true
		return
	end
	if not self.raidHeaders then return end

	local growDir = db.growDirection or "DOWN"
	local groupGrowDir = db.columnGrowDirection
	local point = GROW_TO_POINT[growDir] or "TOP"
	local priKey, priVal, secKey, secVal = GetGrowOffsets(growDir, db.spacingY or 3)
	local size = db.size or { 66, 46 }
	local maxGroups = db.maxGroups or (C and C.MAX_RAID_GROUPS or 8)
	local gSpacing = db.groupSpacing or 5

	for i, header in ipairs(self.raidHeaders) do
		if i <= maxGroups then
			SafeSetAttribute(header, "point", point)
			SafeSetAttribute(header, priKey, priVal)
			SafeSetAttribute(header, secKey, secVal)
			SafeSetAttribute(header, "unitsPerColumn", db.unitsPerColumn or 5)
			SafeSetAttribute(header, "maxColumns", db.maxColumns or 1)
			SafeSetAttribute(header, "sortDir", db.sortDir or "ASC")
			SafeSetAttribute(header, "sortMethod", db.sortBy or "INDEX")
			SafeSetAttribute(header, "gf-width", size[1])
			SafeSetAttribute(header, "gf-height", size[2])

			-- 그룹 간 배치 재계산 (i > 1)
			if i > 1 then
				local prev = self.raidHeaders[i - 1]
				local gGrow = groupGrowDir
				if not gGrow then
					if growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER" then
						gGrow = "RIGHT"
					else
						gGrow = "DOWN"
					end
				end
				-- [FIX] 그룹 간 앵커: growDirection에 따라 정렬 기준선 결정
				header:ClearAllPoints()
				local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
				if gGrow == "RIGHT" or gGrow == "LEFT" then
					local yEdge = "TOP"
					if priIsVert and growDir == "UP" then
						yEdge = "BOTTOM"
					end
					if gGrow == "RIGHT" then
						header:SetPoint(yEdge .. "LEFT", prev, yEdge .. "RIGHT", gSpacing, 0)
					else
						header:SetPoint(yEdge .. "RIGHT", prev, yEdge .. "LEFT", -gSpacing, 0)
					end
				elseif gGrow == "DOWN" or gGrow == "UP" then
					local xEdge = "LEFT"
					if not priIsVert and growDir == "LEFT" then
						xEdge = "RIGHT"
					end
					if gGrow == "DOWN" then
						header:SetPoint("TOP" .. xEdge, prev, "BOTTOM" .. xEdge, 0, -gSpacing)
					else
						header:SetPoint("BOTTOM" .. xEdge, prev, "TOP" .. xEdge, 0, gSpacing)
					end
				else
					header:SetPoint("TOPLEFT", prev, "TOPRIGHT", gSpacing, 0)
				end
			end
			header:Show()
		else
			header:Hide()
		end
	end

	-- 자식 프레임 크기 갱신
	for i = 1, maxGroups do
		local header = self.raidHeaders[i]
		if header then
			for j = 1, 40 do
				local child = header:GetAttribute("child" .. j)
				if not child then break end
				child:SetSize(size[1], size[2])
				-- 레이아웃 재적용
				if ns.Update and ns.Update.ApplyLayout then
					ns.Update:ApplyLayout(child)
				end
			end
		end
	end
end

-----------------------------------------------
-- InitializeAllChildren: 헤더의 모든 자식 초기화
-----------------------------------------------

function GF:InitializeAllChildren(header)
	if not header then return end

	for i = 1, 40 do
		local child = header:GetAttribute("child" .. i)
		if child then
			if not child.gfInitialized then
				-- 첫 초기화
				self:InitializeHeaderChild(child)
			elseif not child.unit then
				-- [FIX] 이미 초기화됐지만 unit 없는 프레임 복구
				-- SecureGroupHeaderTemplate이 Show() 이후 unit을 할당하는 경우
				local secUnit = SecureButton_GetModifiedUnit(child)
				if secUnit and secUnit ~= "" then
					child.unit = secUnit
					GF.unitFrameMap[secUnit] = child
					local storeGuid = SafeVal(UnitGUID(secUnit))
					GF.unitGuidCache[secUnit] = storeGuid
					-- 풀 리프레시 예약
					C_Timer.After(0, function()
						if child:IsVisible() and child.unit then
							if GF.FullFrameRefresh then
								GF:FullFrameRefresh(child)
							end
						end
					end)
				end
			end
		else
			break
		end
	end
end
