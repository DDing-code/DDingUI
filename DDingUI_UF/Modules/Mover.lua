--[[
	ddingUI UnitFrames
	Modules/Mover.lua - 편집모드 프레임 이동 + 그리드 스냅
	Cell/Cell_UnitFrames 패턴 참고: 색상 코딩, CalcPoint 자동 앵커, Fade 애니메이션
	[12.0.1] ElvUI 스타일: 넛지 패널, 프레임간 스냅, 완료 버튼
]]

local _, ns = ...

local Mover = {}
ns.Mover = Mover

-- [REFACTOR] 공유 유틸리티 참조 (MoverUtils.lua)
local MU = (_G.DDingUI and _G.DDingUI.MoverUtils) or {}

local movers = {}
local isUnlocked = false
local gridFrame = nil
local nudgePanel = nil
local selectedMover = nil
local selectedMovers = {} -- [EDITMODE] 다중 선택 세트 (Shift+클릭)
local undoStack = {} -- [EDITMODE] 언두 스택
local redoStack = {} -- [EDITMODE] 리두 스택 (CDM 패턴)
local MAX_UNDO = 30 -- [EDITMODE] 최대 언두/리두 횟수

local C = ns.Constants
local math_floor = math.floor
local math_abs = math.abs
local math_max = math.max
local select = select

-- [12.0.1] StyleLib 참조 (넛지패널 + 무버 오버레이 공용)
local SL = _G.DDingUI_StyleLib
local fontPath = (SL and SL.Font.path) or "Fonts\\2002.TTF"

-- [STYLE] ON/OFF 상태 색상 hex (모듈 전역)
local _slAccentTbl = SL and { SL.GetAccent("UnitFrames") } or { {0.30, 0.85, 0.45} }
local _accentRGB = _slAccentTbl[1] or {0.30, 0.85, 0.45}
local _dimRGB = (SL and SL.Colors and SL.Colors.text and SL.Colors.text.dim) or {0.50, 0.50, 0.50}
local ACCENT_HEX = string.format("%02x%02x%02x", math_floor((_accentRGB[1] or 0.30)*255+0.5), math_floor((_accentRGB[2] or 0.85)*255+0.5), math_floor((_accentRGB[3] or 0.45)*255+0.5))
local DIM_HEX = string.format("%02x%02x%02x", math_floor((_dimRGB[1] or 0.50)*255+0.5), math_floor((_dimRGB[2] or 0.50)*255+0.5), math_floor((_dimRGB[3] or 0.50)*255+0.5))

-- [12.0.1] Forward declaration (CreateMoverOverlay보다 먼저 참조됨)
local SelectMover

-----------------------------------------------
-- 유닛별 색상 코딩 (Cell_UnitFrames 패턴)
-----------------------------------------------

local MOVER_COLORS = {
	player       = { bg = {1.0, 0.2, 0.2, 0.30}, border = {1.0, 0.3, 0.3, 0.80} },  -- 빨강
	target       = { bg = {1.0, 0.5, 0.0, 0.30}, border = {1.0, 0.6, 0.1, 0.80} },  -- 주황
	targettarget = { bg = {1.0, 1.0, 0.0, 0.25}, border = {1.0, 1.0, 0.2, 0.80} },  -- 노랑
	focus        = { bg = {0.0, 0.8, 0.2, 0.30}, border = {0.1, 0.9, 0.3, 0.80} },  -- 초록
	focustarget  = { bg = {0.2, 0.8, 0.5, 0.25}, border = {0.3, 0.9, 0.5, 0.80} },  -- 청록
	pet          = { bg = {0.0, 0.5, 1.0, 0.30}, border = {0.1, 0.6, 1.0, 0.80} },  -- 파랑
	boss         = { bg = {0.8, 0.0, 0.8, 0.30}, border = {0.9, 0.1, 0.9, 0.80} },  -- 보라
	arena        = { bg = {0.8, 0.0, 0.4, 0.30}, border = {0.9, 0.1, 0.5, 0.80} },  -- 핑크
	party        = { bg = {0.0, 0.7, 0.7, 0.30}, border = {0.1, 0.8, 0.8, 0.80} },  -- 청록
	raid         = { bg = {0.4, 0.6, 1.0, 0.30}, border = {0.5, 0.7, 1.0, 0.80} },  -- 하늘
	castbar      = { bg = {1.0, 0.8, 0.0, 0.30}, border = {1.0, 0.9, 0.2, 0.80} },  -- 금색
	powerbar     = { bg = {0.3, 0.5, 1.0, 0.30}, border = {0.4, 0.6, 1.0, 0.80} },  -- 파워 파랑
}

local DEFAULT_COLOR = { bg = {0, 0.5, 1, 0.3}, border = {0, 0.7, 1, 0.8} }

-- [MOVER] P3 카테고리 필터
local MOVER_CATEGORIES = {
	All   = nil, -- nil = show all
	Party = { player=true, target=true, targettarget=true, focus=true, focustarget=true, pet=true, party=true, boss=true, arena=true, castbar=true, powerbar=true },
	Raid  = { player=true, target=true, targettarget=true, focus=true, focustarget=true, pet=true, raid=true, boss=true, arena=true, castbar=true, powerbar=true },
}
local CATEGORY_ORDER = { "All", "Party", "Raid" }
local _activeCategory = "All"

local function ApplyMoverFilter(category)
	_activeCategory = category or "All"
	local filter = MOVER_CATEGORIES[_activeCategory]
	for _, mover in ipairs(movers) do
		if not filter or filter[mover._colorKey] then
			if isUnlocked then mover:Show() end
		else
			mover:Hide()
		end
	end
	-- [EDITMODE-FIX] simContainer(미리보기)도 카테고리 필터 적용
	if ns.simContainers then
		for key, container in pairs(ns.simContainers) do
			if container then
				if not filter or filter[key] then
					container:Show()
				else
					container:Hide()
				end
			end
		end
	end
end

-----------------------------------------------
-- Mover Config Helper
-----------------------------------------------

local function GetMoverDB()
	if not ns.db then return {} end
	if not ns.db.mover then ns.db.mover = {} end
	-- [CDM-P2] 스냅 설정 마이그레이션 (1회)
	local mdb = ns.db.mover
	if mdb._snapMigrated == nil then
		if mdb.gridSnap ~= nil and mdb.snapToGrid == nil then
			mdb.snapToGrid = mdb.gridSnap
		end
		if mdb.frameSnap ~= nil and mdb.snapToFrames == nil then
			mdb.snapToFrames = mdb.frameSnap
		end
		if mdb.snapToCenter == nil then mdb.snapToCenter = true end
		if mdb.snapThreshold == nil then mdb.snapThreshold = 12 end
		mdb._snapMigrated = true
	end
	return mdb
end

-----------------------------------------------
-- [MOVER] Centralized Mover DB Functions
-----------------------------------------------

local _positionSnapshot = {} -- ESC 취소용 편집 전 위치 스냅샷

-- Mover DB 이름 (movers 네임스페이스 키)
local function GetMoverDBKey(mover)
	return mover._name or mover:GetName() or "Unknown"
end

-- [FIX] anchor point의 화면 좌표 계산 (UIParent ↔ 프레임 상대좌표 변환용)
local function GetAnchorScreenPos(anchorPoint, frame)
	local left, bottom, w, h = frame:GetRect()
	if not left then return nil, nil end
	local ap = anchorPoint or "CENTER"
	local sx, sy
	if ap:find("LEFT") then sx = left
	elseif ap:find("RIGHT") then sx = left + w
	else sx = left + w / 2 end
	if ap:find("TOP") then sy = bottom + h
	elseif ap:find("BOTTOM") then sy = bottom
	else sy = bottom + h / 2 end
	return sx, sy
end

-- [MOVER] movers 네임스페이스에 문자열로 저장 + 레거시 위치도 동기화
local function SaveMoverToDB(mover)
	if not mover or not ns.db then return end

	-- [FIX] SetAllPoints 상태(미이동)인 Mover는 저장 스킵
	-- SetAllPoints → 2개 앵커, 수동 배치(ApplyMoverVisual) → 1개 앵커
	if mover:GetNumPoints() ~= 1 then return end

	local point, relativeTo, relPoint, oX, oY = mover:GetPoint(1)
	if not point then return end

	-- [FIX] 초기 상태(미이동): 자기 _frame에 앵커된 상태 → 저장 스킵
	if relativeTo == mover._frame then return end

	-- [ANCHOR-SYNC] attachTo 프레임 또는 UIParent에 앵커된 경우만 저장
	local relName = (relativeTo and relativeTo ~= UIParent and relativeTo.GetName)
	                and relativeTo:GetName() or "UIParent"

	local x = math_floor((oX or 0) + 0.5)
	local y = math_floor((oY or 0) + 0.5)
	local key = GetMoverDBKey(mover)

	-- movers 네임스페이스에 문자열로 저장 (앵커 프레임 정보 포함)
	if not ns.db.movers then ns.db.movers = {} end
	ns.db.movers[key] = string.format("%s,%s,%s,%d,%d", point, relName, relPoint or point, x, y)

	-- 레거시 위치 동기화 (Spawn.lua 호환)
	local unitKey = mover._unitKey
	if not unitKey then return end

	if mover._isCastbar then
		if ns.db[unitKey] and ns.db[unitKey].castbar then
			ns.db[unitKey].castbar.position = { point, relName, relPoint or point, x, y }
		end
	elseif mover._isPowerBar then
		-- [FIX] UIParent-relative → unitFrame-relative 좌표 변환
		-- Layout.lua가 self(유닛프레임) 기준으로 배치하므로 좌표계 일치 필요
		local unitDB = ns.db[unitKey]
		if unitDB and unitDB.widgets and unitDB.widgets.powerBar
		   and unitDB.widgets.powerBar.detachedPosition then
			local dp = unitDB.widgets.powerBar.detachedPosition
			local unitFrame = ns.frames and ns.frames[unitKey]
			local powerFrame = mover._frame
			if unitFrame and powerFrame and unitFrame:GetRect() and powerFrame:GetRect() then
				local pX, pY = GetAnchorScreenPos(point, powerFrame)
				local fX, fY = GetAnchorScreenPos(point, unitFrame)
				if pX and fX then
					dp.point = point
					dp.relativePoint = point
					dp.offsetX = math_floor(pX - fX + 0.5)
					dp.offsetY = math_floor(pY - fY + 0.5)
				end
			end
		end
	elseif ns.db[unitKey] then
		ns.db[unitKey].position = { point, relName, relPoint or point, x, y }
	end
end

-- [MOVER] movers 네임스페이스에서 로드 (문자열 파싱)
local function LoadMoverFromDB(name)
	if not ns.db or not ns.db.movers then return nil end
	local str = ns.db.movers[name]
	if not str or type(str) ~= "string" then return nil end

	local point, parentName, relPoint, x, y = strsplit(",", str)
	x, y = tonumber(x), tonumber(y)
	if not point or not x or not y then return nil end

	-- [ANCHOR-SYNC] 앵커 프레임 이름에서 실제 프레임 resolve
	local anchorFrame = UIParent
	if parentName and parentName ~= "UIParent" then
		anchorFrame = _G[parentName] or UIParent
	end
	return point, anchorFrame, relPoint or point, x, y
end

-- [MOVER] movers 네임스페이스에서 삭제
local function DeleteMoverFromDB(name)
	if ns.db and ns.db.movers then
		ns.db.movers[name] = nil
	end
end

-- [MOVER] 시각적 이동만 (DB 저장 없음 — 편집 중 사용)
local function ApplyMoverVisual(mover, point, x, y, anchorFrame, relPoint)
	if not mover then return end

	-- [EDITMODE-FIX] ClearAllPoints 전 사이즈 보존 (SetAllPoints 파생 사이즈 손실 방지)
	local mW, mH = mover:GetSize()

	-- 앵커 프레임/relPoint가 명시되지 않으면 기존 값 보존 (CDM 패턴)
	if not anchorFrame or not relPoint then
		local _, existAnchor, existRel = mover:GetPoint(1)
		-- [SAFE] 기존 앵커가 자기 _frame이면 순환 참조 → UIParent 폴백
		if existAnchor and existAnchor == mover._frame then
			existAnchor = UIParent
			existRel = point
		end
		anchorFrame = anchorFrame or existAnchor or UIParent
		relPoint = relPoint or existRel or point
	end

	mover:ClearAllPoints()
	mover:SetPoint(point, anchorFrame, relPoint, x, y)

	-- [EDITMODE-FIX] 사이즈 복원
	if mW and mW > 0 and mH and mH > 0 then
		mover:SetSize(mW, mH)
	end

	-- 실제 프레임도 이동
	if mover._frame and not InCombatLockdown() then
		local fW, fH = mover._frame:GetSize() -- [EDITMODE-FIX] 프레임 사이즈도 보존
		mover._frame:ClearAllPoints()
		mover._frame:SetPoint(point, anchorFrame, relPoint, x, y)
		if fW and fW > 0 and fH and fH > 0 then
			mover._frame:SetSize(fW, fH)
		end
	end

	-- [EDITMODE] simContainer 동기화 (그룹 + 개별 유닛 모두)
	if ns.simContainers and mover._unitKey then
		local sim = ns.simContainers[mover._unitKey]
		if sim and sim:IsShown() then
			local unitDB = ns.db and ns.db[mover._unitKey]
			local growDir = unitDB and unitDB.growDirection or "DOWN"
			
			if (mover._unitKey == "boss" or mover._unitKey == "arena") and growDir == "UP" then
				local left, bottom = mover:GetLeft(), mover:GetBottom()
				if left and bottom then
					sim:ClearAllPoints()
					sim:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
				end
			else
				local left, top = mover:GetLeft(), mover:GetTop()
				if left and top then
					sim:ClearAllPoints()
					sim:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
				end
			end
		end
	end

end

-- [ANCHOR-SYNC] attachTo 기준 상대 좌표로 재앵커링 (CDM 패턴)
-- 드래그/넛지 후 UIParent 기준으로 배치된 무버를, DB의 attachTo 프레임 기준으로 변환
local function ReanchorToAttachTo(mover)
	if not mover or not mover._unitKey then return end
	-- 그룹 무버, 캐스트바, 파워바는 자체 로직 사용
	if mover._isGroupMover or mover._isCastbar or mover._isPowerBar then return end

	local unitDB = ns.db and ns.db[mover._unitKey]
	if not unitDB then return end

	local attachTo = unitDB.attachTo
	if not attachTo or attachTo == "" or attachTo == "UIParent" then return end

	local anchorFrame = _G[attachTo]
	if not anchorFrame or not anchorFrame.GetRect then return end
	if not anchorFrame:GetRect() then return end

	-- selfPoint / anchorPoint 결정
	local selfPt = unitDB.selfPoint or "CENTER"
	local anchorPt = unitDB.anchorPoint or "CENTER"

	-- 무버의 화면 좌표 (selfPoint 기준)
	local moverX, moverY = GetAnchorScreenPos(selfPt, mover)
	if not moverX then return end

	-- 앵커 프레임의 화면 좌표 (anchorPoint 기준)
	local anchorX, anchorY = GetAnchorScreenPos(anchorPt, anchorFrame)
	if not anchorX then return end

	-- 상대 오프셋 계산
	local offsetX = math_floor(moverX - anchorX + 0.5)
	local offsetY = math_floor(moverY - anchorY + 0.5)

	-- 앵커 프레임 기준으로 재앵커링
	ApplyMoverVisual(mover, selfPt, offsetX, offsetY, anchorFrame, anchorPt)
end

-- [MOVER] 모든 무버 위치를 DB에 저장
local function SaveAllMoversToDB()
	for _, mover in ipairs(movers) do
		SaveMoverToDB(mover)
	end
end

-- [MOVER] 편집 전 위치 스냅샷 저장
local function SavePositionSnapshot()
	wipe(_positionSnapshot)
	for _, mover in ipairs(movers) do
		local point, anchor, relPt, oX, oY = mover:GetPoint(1)
		if point then
			_positionSnapshot[GetMoverDBKey(mover)] = {
				point = point,
				anchorFrame = anchor,
				relPoint = relPt,
				x = oX or 0,
				y = oY or 0,
			}
		end
	end
end

-- [MOVER] 스냅샷으로 복원 (ESC 취소)
local function RestorePositionSnapshot()
	for _, mover in ipairs(movers) do
		local key = GetMoverDBKey(mover)
		local snap = _positionSnapshot[key]
		if snap then
			ApplyMoverVisual(mover, snap.point, snap.x, snap.y, snap.anchorFrame, snap.relPoint)
		end
	end
	wipe(_positionSnapshot)
end

-----------------------------------------------
-- CalcPointFromAbsolute: 절대 좌표(bottom-left) → 최적 앵커 + 오프셋
-- [SNAP-FIX] ProcessDragStop에서 최종 위치 기반 앵커 결정용
-- NOTE: CalcPoint보다 먼저 정의해야 함 (Lua local 함수 참조 규칙)
-----------------------------------------------

local function CalcPointFromAbsolute(absLeft, absBottom, w, h, forceCenter)
	local parentW, parentH = UIParent:GetSize()
	local halfW, halfH = parentW / 2, parentH / 2
	local centerX = absLeft + w / 2
	local centerY = absBottom + h / 2

	-- Y축: 화면 중심 기준 TOP/BOTTOM
	local vPoint, oY
	if centerY >= halfH then
		vPoint = "TOP"
		oY = (absBottom + h) - parentH -- top edge → parent top (음수)
	else
		vPoint = "BOTTOM"
		oY = absBottom -- bottom edge → parent bottom (양수)
	end

	-- X축: forceCenter이면 항상 CENTER, 아니면 화면 1/3 기준 LEFT/CENTER/RIGHT
	local hPoint, oX
	if forceCenter then
		-- [FIX] 그룹 프레임: 항상 가운데 기준 앵커 (해상도/크기 변경 시 중앙 유지)
		hPoint = ""
		oX = centerX - halfW
	else
		local thirdW = parentW / 3
		if centerX <= thirdW then
			hPoint = "LEFT"
			oX = absLeft -- left edge → parent left
		elseif centerX >= thirdW * 2 then
			hPoint = "RIGHT"
			oX = (absLeft + w) - parentW -- right edge → parent right (음수)
		else
			hPoint = ""
			oX = centerX - halfW -- center → parent center
		end
	end

	local point = vPoint .. hPoint
	-- TOP/BOTTOM 단독 앵커면 X는 center 기준
	if point == "TOP" or point == "BOTTOM" then
		oX = centerX - halfW
	end

	oX = math_floor(oX + 0.5)
	oY = math_floor(oY + 0.5)

	return point, oX, oY
end

-- [MOVER] 기동 시 movers 네임스페이스에서 저장된 위치 적용
local function ApplyMoverPositions()
	if not ns.db or not ns.db.movers then return end
	for _, mover in ipairs(movers) do
		local key = GetMoverDBKey(mover)
		local point, anchorFrame, relPoint, x, y = LoadMoverFromDB(key)
		if point then
			-- [FIX] 그룹 무버: 기존 LEFT/RIGHT 앵커를 CENTER로 자동 마이그레이션
			if mover._isGroupMover and (point:find("LEFT") or point:find("RIGHT")) then
				local mW, mH = mover:GetSize()
				if mW and mW > 0 and mH and mH > 0 then
					-- SetPoint(point, UIParent, point, x, y) → 절대 좌표 역계산
					local pW, pH = UIParent:GetSize()
					local absLeft, absBottom
					-- X축 역계산
					if point:find("LEFT") then
						absLeft = x  -- LEFT 앵커: x = absLeft
					elseif point:find("RIGHT") then
						absLeft = pW + x - mW  -- RIGHT 앵커: x = (absLeft + mW) - pW
					else
						absLeft = (pW / 2) + x - (mW / 2)
					end
					-- Y축 역계산
					if point:find("TOP") then
						absBottom = pH + y - mH  -- TOP 앵커: y = (absBottom + mH) - pH
					elseif point:find("BOTTOM") then
						absBottom = y  -- BOTTOM 앵커: y = absBottom
					else
						absBottom = (pH / 2) + y - (mH / 2)
					end
					point, x, y = CalcPointFromAbsolute(absLeft, absBottom, mW, mH, true)
					anchorFrame = UIParent
					relPoint = point
					-- DB도 업데이트
					ns.db.movers[key] = string.format("%s,UIParent,%s,%d,%d", point, point, x, y)
				end
			end
			ApplyMoverVisual(mover, point, x, y, anchorFrame, relPoint)
		end
	end
end

-- [REFACTOR] 프로필 전환 시 외부에서 호출 가능한 공개 API
function Mover:ApplyPositions()
	ApplyMoverPositions()
end

-- [REFACTOR] 편집모드 중 프로필 전환 시 안전 종료
function Mover:SafeExitEditMode()
	if isUnlocked then
		self:CancelEditMode()
	end
end

-----------------------------------------------
-- Grid Snap (조건부) -- [EDITMODE] 엣지 스냅 개선
-----------------------------------------------

-- [EDITMODE] 기본 그리드 스냅 (1차원 값)
local function SnapToGrid(value, gridSize)
	local mdb = GetMoverDB()
	if not (mdb.snapToGrid or mdb.gridSnap) then return value end
	gridSize = gridSize or mdb.gridSize or 16
	return math_floor(value / gridSize + 0.5) * gridSize
end

-- [EDITMODE] 엣지 스냅: 센터 + 좌/우/상/하 엣지를 그리드에 맞춤 (dandersFrame 패턴)
local function SnapToGridWithEdges(mover, x, y)
	local mdb = GetMoverDB()
	if not (mdb.snapToGrid or mdb.gridSnap) then return x, y end

	local gridSize = mdb.gridSize or 16
	local snapThreshold = gridSize / 2
	local w, h = mover:GetWidth(), mover:GetHeight()

	-- [12.0.1] 화면 중앙 스냅 (일반 그리드보다 2배 강한 흡착)
	local screenW, screenH = UIParent:GetSize()
	local screenCX, screenCY = screenW / 2, screenH / 2
	local centerPull = gridSize  -- 일반 snapThreshold의 2배
	local centerEnabled = (mdb.snapToCenter ~= false) -- [CDM-P2] 개별 토글

	local snappedX = x
	local snappedY = y

	-- X축: 화면 중앙 우선 체크
	local dScreenCX = math_abs(x - screenCX)
	if centerEnabled and dScreenCX <= centerPull then
		snappedX = screenCX
	else
		-- 일반 그리드 스냅: 센터/좌엣지/우엣지
		local centerSnapX = math_floor(x / gridSize + 0.5) * gridSize
		local leftEdge = x - w / 2
		local rightEdge = x + w / 2
		local leftSnapX = math_floor(leftEdge / gridSize + 0.5) * gridSize
		local rightSnapX = math_floor(rightEdge / gridSize + 0.5) * gridSize

		local dCenter = math_abs(x - centerSnapX)
		local dLeft = math_abs(leftEdge - leftSnapX)
		local dRight = math_abs(rightEdge - rightSnapX)

		if dCenter <= dLeft and dCenter <= dRight and dCenter <= snapThreshold then
			snappedX = centerSnapX
		elseif dLeft <= dRight and dLeft <= snapThreshold then
			snappedX = leftSnapX + w / 2
		elseif dRight <= snapThreshold then
			snappedX = rightSnapX - w / 2
		end
	end

	-- Y축: 화면 중앙 우선 체크
	local dScreenCY = math_abs(y - screenCY)
	if centerEnabled and dScreenCY <= centerPull then
		snappedY = screenCY
	else
		-- 일반 그리드 스냅: 센터/상엣지/하엣지
		local centerSnapY = math_floor(y / gridSize + 0.5) * gridSize
		local topEdge = y + h / 2
		local bottomEdge = y - h / 2
		local topSnapY = math_floor(topEdge / gridSize + 0.5) * gridSize
		local bottomSnapY = math_floor(bottomEdge / gridSize + 0.5) * gridSize

		local dCenterY = math_abs(y - centerSnapY)
		local dTop = math_abs(topEdge - topSnapY)
		local dBottom = math_abs(bottomEdge - bottomSnapY)

		if dCenterY <= dTop and dCenterY <= dBottom and dCenterY <= snapThreshold then
			snappedY = centerSnapY
		elseif dBottom <= dTop and dBottom <= snapThreshold then
			snappedY = bottomSnapY + h / 2
		elseif dTop <= snapThreshold then
			snappedY = topSnapY - h / 2
		end
	end

	return snappedX, snappedY
end

-----------------------------------------------
-- [CDM-P2] 외부 스냅 대상 (CDM 프록시 앵커 + UF 프레임)
-- FindFrameSnap, ProcessDragStop, UpdateSnapPreview 공용
-----------------------------------------------

local EXTERNAL_SNAP_FRAMES = {
	-- DDingUI CDM 프록시 앵커
	{ name = "DDingUI_Anchor_Cooldowns", label = "DDingUI CDM: 핵심" },
	{ name = "DDingUI_Anchor_Buffs",     label = "DDingUI CDM: 강화" },
	{ name = "DDingUI_Anchor_Utility",   label = "DDingUI CDM: 보조" },
	-- UF 프레임
	{ name = "ddingUI_Player", label = "UF: Player" },
	{ name = "ddingUI_Target", label = "UF: Target" },
	{ name = "ddingUI_Focus",  label = "UF: Focus" },
	{ name = "ddingUI_Pet",    label = "UF: Pet" },
}

-- [CDM-P2] 실존하는 외부 프레임 목록 반환 (편집모드 진입 시 캐시 가능)
local function GetExternalSnapTargets(excludeFrame)
	local targets = {}
	for _, entry in ipairs(EXTERNAL_SNAP_FRAMES) do
		local frame = _G[entry.name]
		if frame and frame ~= excludeFrame and frame:IsShown() then
			local oX, oY = frame:GetCenter()
			local oW, oH = frame:GetSize()
			if oX and oY and oW > 0 and oH > 0 then
				targets[#targets + 1] = {
					frame = frame,
					name = entry.name,
					label = entry.label,
					cx = oX, cy = oY,
					w = oW, h = oH,
					left = oX - oW / 2,
					right = oX + oW / 2,
					bottom = oY - oH / 2,
					top = oY + oH / 2,
				}
			end
		end
	end
	-- CDM 그룹 프레임 동적 감지
	local CDM = _G.DDingUI and _G.DDingUI.Movers
	if CDM and CDM.CreatedMovers then
		for moverName, holder in pairs(CDM.CreatedMovers) do
			local parent = holder and holder.parent
			if parent and parent ~= excludeFrame and parent:IsShown() then
				local pName = parent:GetName()
				if pName then
					-- 이미 EXTERNAL_SNAP_FRAMES에 있는 것은 중복 제외
					local isDup = false
					for _, t in ipairs(targets) do
						if t.name == pName then isDup = true; break end
					end
					if not isDup then
						local oX, oY = parent:GetCenter()
						local oW, oH = parent:GetSize()
						if oX and oY and oW > 0 and oH > 0 then
							targets[#targets + 1] = {
								frame = parent,
								name = pName,
								label = "CDM: " .. (holder.mover and holder.mover.displayText or moverName),
								cx = oX, cy = oY,
								w = oW, h = oH,
								left = oX - oW / 2,
								right = oX + oW / 2,
								bottom = oY - oH / 2,
								top = oY + oH / 2,
							}
						end
					end
				end
			end
		end
	end
	return targets
end

-- [CDM-P2] 엣지 관계 분석: 두 프레임 간 selfPoint/anchorPoint 자동 결정
-- CDM Movers.lua OnDragStop 패턴 이식 (hOverlap/vOverlap 기반)
local function DetectSnapRelation(myLeft, myBottom, myW, myH, tLeft, tBottom, tW, tH, threshold)
	-- [REFACTOR] MoverUtils 공유 함수 위임 (중복 제거)
	if MU.DetectSnapRelation then
		return MU.DetectSnapRelation(myLeft, myBottom, myW, myH, tLeft, tBottom, tW, tH, threshold)
	end
	-- fallback: MoverUtils 미로드 시 로컬 구현
	local myRight = myLeft + myW
	local myTop = myBottom + myH
	local tRight = tLeft + tW
	local tTop = tBottom + tH
	local hOverlap = math.min(myRight, tRight) - math.max(myLeft, tLeft)
	local minW = math.min(myW, tW)
	local hRatio = minW > 0 and (hOverlap / minW) or 0
	local vOverlap = math.min(myTop, tTop) - math.max(myBottom, tBottom)
	local minH = math.min(myH, tH)
	local vRatio = minH > 0 and (vOverlap / minH) or 0
	local bestDist = threshold
	local selfPt, anchorPt = nil, nil
	if hRatio > 0.3 then
		local dist = math_abs(myBottom - tTop)
		if dist < bestDist then bestDist = dist; selfPt = "BOTTOM"; anchorPt = "TOP" end
	end
	if hRatio > 0.3 then
		local dist = math_abs(myTop - tBottom)
		if dist < bestDist then bestDist = dist; selfPt = "TOP"; anchorPt = "BOTTOM" end
	end
	if vRatio > 0.3 then
		local dist = math_abs(myRight - tLeft)
		if dist < bestDist then bestDist = dist; selfPt = "RIGHT"; anchorPt = "LEFT" end
	end
	if vRatio > 0.3 then
		local dist = math_abs(myLeft - tRight)
		if dist < bestDist then bestDist = dist; selfPt = "LEFT"; anchorPt = "RIGHT" end
	end
	return selfPt, anchorPt, bestDist
end

-----------------------------------------------
-- Frame Snap (프레임간 스냅)
-- [CDM-P2] 외부 프레임(CDM/UF)도 스냅 대상에 포함
-----------------------------------------------

local function FindFrameSnap(self, x, y, w, h)
	local mdb = GetMoverDB()
	if not (mdb.snapToFrames or mdb.frameSnap) then return x, y end
	local threshold = mdb.snapThreshold or 15 -- [MOVER-FIX] ElvUI 기본 15px

	local selfL, selfB = x, y
	local selfR, selfT = x + w, y + h
	local selfCX, selfCY = x + w / 2, y + h / 2

	local snappedX, snappedY = x, y
	local snapDistX, snapDistY = threshold + 1, threshold + 1

	-- 내부 스냅 검사 함수 (UF movers + 외부 프레임 공용)
	local function CheckSnap(oLeft, oRight, oBottom, oTop, oX, oY)
		-- X축 스냅: 수직으로 겹치거나 인접할 때만
		if selfB <= oTop and oBottom <= selfT then
			local xPairs = {
				{ selfL, oLeft },      -- 왼쪽 정렬
				{ selfR, oRight },     -- 오른쪽 정렬
				{ selfL, oRight },     -- 자기 왼쪽 → 대상 오른쪽 (외부)
				{ selfR, oLeft },      -- 자기 오른쪽 → 대상 왼쪽 (외부)
				{ selfCX, oX },        -- 중심 정렬
			}
			for _, pair in ipairs(xPairs) do
				local d = math_abs(pair[1] - pair[2])
				if d < snapDistX then
					snapDistX = d
					snappedX = x + (pair[2] - pair[1])
				end
			end
		end
		-- Y축 스냅: 수평으로 겹치거나 인접할 때만
		if selfL <= oRight and oLeft <= selfR then
			local yPairs = {
				{ selfB, oBottom },    -- 하단 정렬
				{ selfT, oTop },       -- 상단 정렬
				{ selfB, oTop },       -- 자기 하단 → 대상 상단 (외부)
				{ selfT, oBottom },    -- 자기 상단 → 대상 하단 (외부)
				{ selfCY, oY },        -- 중심 정렬
			}
			for _, pair in ipairs(yPairs) do
				local d = math_abs(pair[1] - pair[2])
				if d < snapDistY then
					snapDistY = d
					snappedY = y + (pair[2] - pair[1])
				end
			end
		end
	end

	-- 1) UF movers 스냅
	for _, other in ipairs(movers) do
		if other ~= self and other:IsShown() and other ~= nudgePanel then
			local oX, oY = other:GetCenter()
			local oW, oH = other:GetSize()
			if oX and oY and oW > 0 and oH > 0 then
				CheckSnap(oX - oW / 2, oX + oW / 2, oY - oH / 2, oY + oH / 2, oX, oY)
			end
		end
	end

	-- 2) [CDM-P2] 외부 프레임 스냅 (CDM 프록시 앵커 + UF 프레임 + CDM 그룹)
	local moverFrame = self._frame  -- 실제 프레임 (스냅 대상에서 자기 프레임 제외용)
	local externals = GetExternalSnapTargets(moverFrame)
	for _, ext in ipairs(externals) do
		CheckSnap(ext.left, ext.right, ext.bottom, ext.top, ext.cx, ext.cy)
	end

	if snapDistX > threshold then snappedX = x end
	if snapDistY > threshold then snappedY = y end
	return snappedX, snappedY
end

-----------------------------------------------
-- CalcPoint: 프레임에서 절대 좌표를 추출하여 CalcPointFromAbsolute 호출
-- (ElvUI CalculateMoverPoints 패턴)
-----------------------------------------------

local function CalcPoint(frame)
	local x, y = frame:GetCenter()
	if not x or not y then return "CENTER", 0, 0 end
	local w, h = frame:GetSize()
	local absLeft = x - (w or 0) / 2
	local absBottom = y - (h or 0) / 2
	return CalcPointFromAbsolute(absLeft, absBottom, w or 0, h or 0)
end

-----------------------------------------------
-- 공통 OnDragStop 로직 (코드 중복 제거)
-- [SNAP-FIX] 절대 좌표 기반 재작성: Frame Snap 우선, 프리뷰와 일치
-----------------------------------------------

local function ProcessDragStop(self)
	self:StopMovingOrSizing()

	local selfW, selfH = self:GetSize()
	local w, h = selfW or 0, selfH or 0

	-- [EDITMODE] 언두 스택에 드래그 전 위치 저장 (OnDragStart에서 캡처)
	if self._preDragPos then
		if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
		undoStack[#undoStack + 1] = { mover = self, point = self._preDragPos.point, x = self._preDragPos.x, y = self._preDragPos.y }
		wipe(redoStack) -- [CDM-P1] 새 동작 시 리두 스택 초기화
		self._preDragPos = nil
		if nudgePanel and nudgePanel.UpdateUndoRedoBtns then nudgePanel:UpdateUndoRedoBtns() end
	end

	-- 절대 좌표 (bottom-left) — 프리뷰와 동일한 좌표계
	local absLeft = self:GetLeft() or 0
	local absBottom = self:GetBottom() or 0

	if not IsShiftKeyDown() then
		-- [SNAP-FIX] 1단계: Frame Snap (프리뷰와 동일한 절대 좌표 계산)
		local fsLeft, fsBottom = FindFrameSnap(self, absLeft, absBottom, w, h)
		local frameSnappedX = (fsLeft ~= absLeft)
		local frameSnappedY = (fsBottom ~= absBottom)
		absLeft, absBottom = fsLeft, fsBottom

		-- [SNAP-FIX] 2단계: Grid Snap (Frame Snap이 적용되지 않은 축만)
		local cx, cy = absLeft + w / 2, absBottom + h / 2
		local snappedCX, snappedCY = SnapToGridWithEdges(self, cx, cy)
		if not frameSnappedX then
			absLeft = snappedCX - w / 2
		end
		if not frameSnappedY then
			absBottom = snappedCY - h / 2
		end
	end

	-- ============================================================
	-- [CDM-P2] 스냅 감지: 인접한 외부 프레임과의 엣지 관계 분석
	-- CDM Movers.lua OnDragStop 패턴 이식
	-- ============================================================
	local unitKey = self._unitKey
	local unitDB = unitKey and ns.db and ns.db[unitKey]
	local mdb = GetMoverDB()
	local SNAP_THRESHOLD = mdb.snapThreshold or 15
	local snapTarget, snapSelfPt, snapAnchorPt = nil, nil, nil

	if unitDB and not self._isGroupMover and not self._isCastbar and not self._isPowerBar
	   and (mdb.snapToFrames or mdb.frameSnap) and not IsShiftKeyDown() then
		local moverFrame = self._frame
		local externals = GetExternalSnapTargets(moverFrame)

		-- UF 프레임도 스냅 대상에 추가 (다른 유닛 프레임)
		for _, other in ipairs(movers) do
			if other ~= self and other:IsShown() and other ~= nudgePanel
			   and other._unitKey and other._frame then
				local fName = other._frame:GetName()
				if fName then
					local oX, oY = other:GetCenter()
					local oW, oH = other:GetSize()
					if oX and oY and oW > 0 and oH > 0 then
						externals[#externals + 1] = {
							frame = other._frame,
							name = fName,
							label = "UF: " .. (other._name or fName),
							cx = oX, cy = oY,
							w = oW, h = oH,
							left = oX - oW / 2,
							right = oX + oW / 2,
							bottom = oY - oH / 2,
							top = oY + oH / 2,
						}
					end
				end
			end
		end

		local bestDist = SNAP_THRESHOLD
		for _, target in ipairs(externals) do
			local sp, ap, dist = DetectSnapRelation(
				absLeft, absBottom, w, h,
				target.left, target.bottom, target.w, target.h,
				bestDist
			)
			if sp and ap and dist < bestDist then
				bestDist = dist
				snapTarget = target
				snapSelfPt = sp
				snapAnchorPt = ap
			end
		end
	end

	if snapTarget and snapSelfPt and snapAnchorPt and unitDB then
		-- ============================================================
		-- [CDM-P2] 스냅 감지됨: attachTo/selfPoint/anchorPoint 자동 설정
		-- ============================================================
		local targetFrame = snapTarget.frame
		local targetName = snapTarget.name

		if targetFrame and targetName then
			-- selfPoint 위치 계산 (mover 기준)
			local myCX, myCY = absLeft + w / 2, absBottom + h / 2
			local selfX = myCX + (snapSelfPt:find("LEFT") and -w/2 or snapSelfPt:find("RIGHT") and w/2 or 0)
			local selfY = myCY + (snapSelfPt:find("TOP") and h/2 or snapSelfPt:find("BOTTOM") and -h/2 or 0)
			-- anchorPoint 위치 계산 (target 기준)
			local tCX, tCY = snapTarget.cx, snapTarget.cy
			local anchorX = tCX + (snapAnchorPt:find("LEFT") and -snapTarget.w/2 or snapAnchorPt:find("RIGHT") and snapTarget.w/2 or 0)
			local anchorY = tCY + (snapAnchorPt:find("TOP") and snapTarget.h/2 or snapAnchorPt:find("BOTTOM") and -snapTarget.h/2 or 0)

			local offsetX = math_floor(selfX - anchorX + 0.5)
			local offsetY = math_floor(selfY - anchorY + 0.5)

			-- DB에 앵커 정보 저장
			unitDB.attachTo = targetName
			unitDB.selfPoint = snapSelfPt
			unitDB.anchorPoint = snapAnchorPt
			unitDB.position = { offsetX, offsetY }

			-- [CDM-P2] 넛지 패널 드롭다운 동기화
			if nudgePanel then
				if nudgePanel.attachDropdown and nudgePanel.attachDropdown.SetSelected then
					nudgePanel.attachDropdown:SetSelected(targetName)
				end
				if nudgePanel.selfPtDropdown and nudgePanel.selfPtDropdown.SetSelected then
					nudgePanel.selfPtDropdown:SetSelected(snapSelfPt)
				end
				if nudgePanel.anchorPtDropdown and nudgePanel.anchorPtDropdown.SetSelected then
					nudgePanel.anchorPtDropdown:SetSelected(snapAnchorPt)
				end
			end

			-- UIParent 기준 좌표도 저장 (mover 위치 복원용)
			local point, oX, oY = CalcPointFromAbsolute(absLeft, absBottom, w, h, false)

			-- [BUG-FIX] mover + 실제 프레임 모두 이동 (기존: mover만 이동)
			ApplyMoverVisual(self, point, oX, oY, UIParent, point)
			ReanchorToAttachTo(self)

			if selfW and selfW > 0 and selfH and selfH > 0 then
				self:SetSize(selfW, selfH)
			end

			-- [BUG-FIX] 드래그 직후 즉시 DB 저장 (리로드 시 초기화 방지)
			SaveMoverToDB(self)

			-- [ANCHOR] AnchorManager 레지스트리 동기화 (스냅 분기)
			local AM_snap = _G.DDingUI and _G.DDingUI.AnchorManager
			if AM_snap and AM_snap.registry then
				local key = GetMoverDBKey(self)
				local e = AM_snap.registry[key]
				if e then
					e.selfPoint = snapSelfPt
					e.attachTo = targetName
					e.anchorPoint = snapAnchorPt
					e.offsetX = unitDB and unitDB.position and unitDB.position[1] or 0
					e.offsetY = unitDB and unitDB.position and unitDB.position[2] or 0
				end
			end

			-- 사용자 피드백
			ns.Print(string.format(
				"|cff00ff00%s|r → |cff80c0ff%s|r (|cffffcc00%s|r → |cffffcc00%s|r)",
				self._name or unitKey,
				snapTarget.label or targetName,
				snapSelfPt, snapAnchorPt
			))

			return point, oX, oY
		end -- if targetFrame and targetName
	end -- if snapTarget

	-- ============================================================
	-- [CDM-P2] 스냅 미감지: 거리 기반 앵커 해제 체크
	-- ============================================================
	if unitDB and not self._isGroupMover and not self._isCastbar and not self._isPowerBar then
		local origAttachTo = unitDB.attachTo or "UIParent"
		if origAttachTo ~= "UIParent" then
			local origFrame = _G[origAttachTo]
			local DETACH_THRESHOLD = SNAP_THRESHOLD * 3
			local shouldDetach = false

			if origFrame and origFrame:GetCenter() then
				local tRect = { origFrame:GetRect() }
				if tRect[1] then
					local tL, tB, tW, tH = tRect[1], tRect[2], tRect[3], tRect[4]
					local tR, tT = tL + tW, tB + tH
					local myR, myT = absLeft + w, absBottom + h

					local hDist = 0
					if myR < tL then hDist = tL - myR
					elseif absLeft > tR then hDist = absLeft - tR end

					local vDist = 0
					if myT < tB then vDist = tB - myT
					elseif absBottom > tT then vDist = absBottom - tT end

					local edgeDist = math.sqrt(hDist * hDist + vDist * vDist)
					if edgeDist > DETACH_THRESHOLD then
						shouldDetach = true
					end
				end
			else
				-- 앵커 프레임이 없으면 무조건 해제
				shouldDetach = true
			end

			if shouldDetach then
				unitDB.attachTo = "UIParent"
				unitDB.selfPoint = nil
				unitDB.anchorPoint = nil

				-- [CDM-P2] 넛지 패널 드롭다운 동기화
				if nudgePanel then
					if nudgePanel.attachDropdown and nudgePanel.attachDropdown.SetSelected then
						nudgePanel.attachDropdown:SetSelected("UIParent")
					end
					if nudgePanel.selfPtDropdown and nudgePanel.selfPtDropdown.SetSelected then
						nudgePanel.selfPtDropdown:SetSelected("CENTER")
					end
					if nudgePanel.anchorPtDropdown and nudgePanel.anchorPtDropdown.SetSelected then
						nudgePanel.anchorPtDropdown:SetSelected("CENTER")
					end
				end

				ns.Print(string.format(
					"|cff00ff00%s|r → |cff80c0ffUIParent|r (|cffffcc00앵커 해제|r)",
					self._name or unitKey
				))
			end
		end
	end

	-- [SNAP-FIX] 3단계: 최종 절대 좌표에서 앵커 결정
	local point, oX, oY
	if self._isGroupMover and self._unitKey then
		-- 그룹 무버: growDirection 기반 앵커 포인트 사용
		local unitDB = ns.db[self._unitKey]
		local growDir = (unitDB and unitDB.growDirection) or "DOWN"
		local groupGrowDir = unitDB and unitDB.groupGrowDirection
		if not groupGrowDir then
			if growDir == "H_CENTER" or growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER" then
				groupGrowDir = "RIGHT"
			else
				groupGrowDir = "DOWN"
			end
		end
		local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
		local yAnc, xAnc
		if priIsVert then
			yAnc = (growDir == "UP") and "BOTTOM" or (growDir == "V_CENTER") and "" or "TOP"
			xAnc = (groupGrowDir == "LEFT") and "RIGHT" or "LEFT"
		else
			xAnc = (growDir == "LEFT") and "RIGHT" or (growDir == "H_CENTER") and "" or "LEFT"
			yAnc = (groupGrowDir == "UP") and "BOTTOM" or "TOP"
		end
		local ancPt = yAnc .. xAnc
		if ancPt == "" then ancPt = "CENTER" end

		-- 해당 앵커 포인트 기준 화면 좌표 계산
		local parentW, parentH = UIParent:GetSize()
		local aX, aY
		if ancPt:find("LEFT") then aX = absLeft
		elseif ancPt:find("RIGHT") then aX = absLeft + w
		else aX = absLeft + w / 2 end
		if ancPt:find("TOP") then aY = absBottom + h
		elseif ancPt:find("BOTTOM") then aY = absBottom
		else aY = absBottom + h / 2 end

		if ancPt:find("LEFT") then oX = aX
		elseif ancPt:find("RIGHT") then oX = aX - parentW
		else oX = aX - parentW / 2 end
		if ancPt:find("TOP") then oY = aY - parentH
		elseif ancPt:find("BOTTOM") then oY = aY
		else oY = aY - parentH / 2 end

		point = ancPt
		oX = math_floor(oX + 0.5)
		oY = math_floor(oY + 0.5)
	else
		local forceCenter = false
		point, oX, oY = CalcPointFromAbsolute(absLeft, absBottom, w, h, forceCenter)
	end

	-- [BUG-FIX] mover + 실제 프레임 모두 이동 (기존: mover만 SetPoint)
	ApplyMoverVisual(self, point, oX, oY, UIParent, point)
	ReanchorToAttachTo(self)

	if selfW and selfW > 0 and selfH and selfH > 0 then
		self:SetSize(selfW, selfH)
	end

	-- [BUG-FIX] 드래그 직후 즉시 DB 저장 (ReanchorToAttachTo 후의 최종 좌표 반영)
	SaveMoverToDB(self)

	-- [ANCHOR] AnchorManager 레지스트리 동기화 (재앵커링 후의 실제 좌표 사용)
	local AM_drag = _G.DDingUI and _G.DDingUI.AnchorManager
	if AM_drag and AM_drag.registry then
		local key = GetMoverDBKey(self)
		local e = AM_drag.registry[key]
		if e then
			local curPt, curRelTo, curRelPt, curOX, curOY = self:GetPoint(1)
			e.selfPoint = curPt or point
			e.attachTo = (curRelTo and curRelTo ~= UIParent and curRelTo.GetName and curRelTo:GetName()) or "UIParent"
			e.anchorPoint = curRelPt or curPt or point
			e.offsetX = curOX or oX
			e.offsetY = curOY or oY
		end
	end

	return point, oX, oY
end

-----------------------------------------------
-- 위치 해석 헬퍼 (3가지 형식 통합)
-----------------------------------------------

local function ResolvePosition(pos, unitDB)
	if not pos then return nil end

	if type(pos[1]) == "string" then
		local relativeTo = (pos[2] and _G[pos[2]]) or UIParent
		return pos[1], relativeTo, pos[3] or pos[1], pos[4] or 0, pos[5] or 0
	elseif pos.point then
		return pos.point, UIParent, pos.relativePoint or pos.point, pos.offsetX or 0, pos.offsetY or 0
	elseif type(pos[1]) == "number" then
		local anchor = (unitDB and unitDB.anchorPoint) or "TOPLEFT"
		return anchor, UIParent, anchor, pos[1], pos[2] or 0
	end
	return nil
end

-----------------------------------------------
-- Grid Overlay (편집모드 배경 격자)
-----------------------------------------------

local function CreateGridOverlay()
	if gridFrame then return gridFrame end

	gridFrame = CreateFrame("Frame", "ddingUI_GridOverlay", UIParent)
	gridFrame:SetAllPoints(UIParent)
	gridFrame:SetFrameStrata("BACKGROUND")
	gridFrame:SetFrameLevel(0)
	gridFrame:Hide()
	gridFrame._gridLines = {}

	local screenW, screenH = UIParent:GetSize()

	-- 중앙선 (고정, RefreshLines에서 재생성 안 함) — [12.0.1] 굵게 + 높은 가시성
	local centerV = gridFrame:CreateTexture(nil, "ARTWORK")
	centerV:SetColorTexture(1, 0.3, 0.3, 0.35)
	centerV:SetSize(2, screenH)
	centerV:SetPoint("TOP", gridFrame, "TOP", 0, 0)

	local centerH = gridFrame:CreateTexture(nil, "ARTWORK")
	centerH:SetColorTexture(1, 0.3, 0.3, 0.35)
	centerH:SetSize(screenW, 2)
	centerH:SetPoint("LEFT", gridFrame, "LEFT", 0, 0)

	-- [12.0.1] 스냅 미리보기 라인 (DandersFrames 스타일: 빨간색 가이드)
	gridFrame.snapV = gridFrame:CreateTexture(nil, "OVERLAY")
	gridFrame.snapV:SetColorTexture(1, 0.2, 0.2, 0.8)
	gridFrame.snapV:SetSize(2, screenH)
	gridFrame.snapV:Hide()

	gridFrame.snapH = gridFrame:CreateTexture(nil, "OVERLAY")
	gridFrame.snapH:SetColorTexture(1, 0.2, 0.2, 0.8)
	gridFrame.snapH:SetSize(screenW, 2)
	gridFrame.snapH:Hide()

	-- [12.0.1] 그리드 라인 생성/재생성 (Grid Size 변경 시 호출)
	function gridFrame:RefreshLines()
		-- 기존 라인 숨기기
		for _, line in ipairs(self._gridLines) do
			line:Hide()
			line:ClearAllPoints()
		end

		local sw, sh = UIParent:GetSize()
		local mdb = GetMoverDB()
		local gs = mdb.gridSize or 16
		local lineAlpha = 0.06
		local majorAlpha = 0.12
		local majorEvery = 5
		local idx = 0

		for x = gs, math_floor(sw), gs do
			idx = idx + 1
			local line = self._gridLines[idx]
			if not line then
				line = self:CreateTexture(nil, "BACKGROUND")
				self._gridLines[idx] = line
			end
			line:SetColorTexture(1, 1, 1, (x % (gs * majorEvery) == 0) and majorAlpha or lineAlpha)
			line:SetSize(1, sh)
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
			line:Show()
		end

		for y = gs, math_floor(sh), gs do
			idx = idx + 1
			local line = self._gridLines[idx]
			if not line then
				line = self:CreateTexture(nil, "BACKGROUND")
				self._gridLines[idx] = line
			end
			line:SetColorTexture(1, 1, 1, (y % (gs * majorEvery) == 0) and majorAlpha or lineAlpha)
			line:SetSize(sw, 1)
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
			line:Show()
		end

		-- 남은 기존 라인 숨기기
		for i = idx + 1, #self._gridLines do
			self._gridLines[i]:Hide()
		end
	end

	-- 초기 라인 생성
	gridFrame:RefreshLines()

	return gridFrame
end

-- [12.0.1] 드래그 중 스냅 미리보기 업데이트
local function UpdateSnapPreview(dragMover)
	if not gridFrame or not gridFrame:IsShown() then return end
	if not gridFrame.snapV then return end

	local mdb = GetMoverDB()
	-- [12.0.1] frameSnap 또는 gridSnap 둘 중 하나라도 켜져있으면 프리뷰 표시
	if not (mdb.snapToFrames or mdb.frameSnap) and not (mdb.snapToGrid or mdb.gridSnap) then
		gridFrame.snapV:Hide()
		gridFrame.snapH:Hide()
		return
	end

	local threshold = mdb.snapThreshold or 15 -- [MOVER-FIX] ElvUI 기본 15px
	local x, y = dragMover:GetCenter()
	if not x or not y then return end
	local w, h = dragMover:GetSize()
	local selfL, selfR = x - w / 2, x + w / 2
	local selfB, selfT = y - h / 2, y + h / 2
	local selfCX, selfCY = x, y

	local bestSnapX, bestDistX = nil, threshold + 1
	local bestSnapY, bestDistY = nil, threshold + 1

	-- [12.0.1] 화면 중앙 스냅 프리뷰 (그리드 스냅 기준 centerPull과 동일)
	local screenW, screenH = UIParent:GetSize()
	local screenCX, screenCY = screenW / 2, screenH / 2
	local gridSize = mdb.gridSize or 16
	local centerPull = gridSize  -- SnapToGridWithEdges와 동일한 threshold

	if (mdb.snapToGrid or mdb.gridSnap) and (mdb.snapToCenter ~= false) then
		local dCX = math_abs(x - screenCX)
		if dCX <= centerPull and dCX < bestDistX then
			bestDistX = dCX
			bestSnapX = screenCX
		end
		local dCY = math_abs(y - screenCY)
		if dCY <= centerPull and dCY < bestDistY then
			bestDistY = dCY
			bestSnapY = screenCY
		end
	end

	-- Frame Snap 프리뷰 (프레임 간)
	if (mdb.snapToFrames or mdb.frameSnap) then
		-- 내부 스냅 프리뷰 검사 함수
		local function CheckPreviewSnap(oL, oR, oB, oT, oX, oY)
			if selfB <= oT and oB <= selfT then
				local xChecks = { selfL, oL, selfR, oR, selfR, oL, selfL, oR, selfCX, oX }
				for i = 1, #xChecks, 2 do
					local d = math_abs(xChecks[i] - xChecks[i + 1])
					if d < bestDistX then
						bestDistX = d
						bestSnapX = xChecks[i + 1]
					end
				end
			end
			if selfL <= oR and oL <= selfR then
				local yChecks = { selfB, oB, selfT, oT, selfT, oB, selfB, oT, selfCY, oY }
				for i = 1, #yChecks, 2 do
					local d = math_abs(yChecks[i] - yChecks[i + 1])
					if d < bestDistY then
						bestDistY = d
						bestSnapY = yChecks[i + 1]
					end
				end
			end
		end

		-- 1) UF movers 프리뷰
		for _, other in ipairs(movers) do
			if other ~= dragMover and other:IsShown() and other ~= nudgePanel then
				local oX, oY = other:GetCenter()
				local oW, oH = other:GetSize()
				if oX and oY and oW > 0 and oH > 0 then
					CheckPreviewSnap(oX - oW / 2, oX + oW / 2, oY - oH / 2, oY + oH / 2, oX, oY)
				end
			end
		end

		-- 2) [CDM-P2] 외부 프레임 프리뷰 (CDM 프록시 앵커 + UF 프레임 + CDM 그룹)
		local moverFrame = dragMover._frame
		local externals = GetExternalSnapTargets(moverFrame)
		for _, ext in ipairs(externals) do
			CheckPreviewSnap(ext.left, ext.right, ext.bottom, ext.top, ext.cx, ext.cy)
		end
	end

	-- 수직 가이드라인
	if bestSnapX and bestDistX <= math.max(threshold, centerPull) then
		gridFrame.snapV:ClearAllPoints()
		gridFrame.snapV:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bestSnapX, y)
		gridFrame.snapV:Show()
	else
		gridFrame.snapV:Hide()
	end

	-- 수평 가이드라인
	if bestSnapY and bestDistY <= math.max(threshold, centerPull) then
		gridFrame.snapH:ClearAllPoints()
		gridFrame.snapH:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, bestSnapY)
		gridFrame.snapH:Show()
	else
		gridFrame.snapH:Hide()
	end
end

-- [12.0.1] 스냅 미리보기 숨기기
local function HideSnapPreview()
	if gridFrame and gridFrame.snapV then
		gridFrame.snapV:Hide()
		gridFrame.snapH:Hide()
	end
end

-----------------------------------------------
-- Calculate Group Mover Size
-----------------------------------------------

local function CalcPartyMoverSize()
	local db = ns.db.party
	if not db then return 120, 180 end

	local w = (db.size and db.size[1]) or 120
	local h = (db.size and db.size[2]) or 36
	local numMembers = db.showPlayer and 5 or 4
	local spacing = db.spacing or 4
	local growDir = db.growDirection or "DOWN"

	-- [FIX] growDirection에 따라 mover 크기 방향 변경
	local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
	if priIsVert then
		local totalH = h * numMembers + spacing * (numMembers - 1)
		-- 2차 방향(열)도 고려
		local maxCols = db.maxColumns or 1
		if maxCols > 1 then
			local upc = db.unitsPerColumn or 5
			local rows = math.min(numMembers, upc)
			local cols = math.ceil(numMembers / upc)
			local colSpacing = db.spacingX or 4
			return w * cols + colSpacing * (cols - 1), h * rows + spacing * (rows - 1)
		end
		return w, totalH
	else
		local totalW = w * numMembers + spacing * (numMembers - 1)
		local maxCols = db.maxColumns or 1
		if maxCols > 1 then
			local upc = db.unitsPerColumn or 5
			local cols = math.min(numMembers, upc)
			local rows = math.ceil(numMembers / upc)
			local colSpacing = db.spacingX or 4
			return w * cols + spacing * (cols - 1), h * rows + colSpacing * (rows - 1)
		end
		return totalW, h
	end
end

local function CalcRaidMoverSize()
	-- [MYTHIC-RAID] 활성 레이드 DB 참조
	local GF = ns.GroupFrames
	local db = (GF and GF.GetActiveRaidDB and GF:GetActiveRaidDB()) or ns.db.raid
	if not db then return 540, 240 end

	local w = (db.size and db.size[1]) or 66
	local h = (db.size and db.size[2]) or 46
	local unitsPerGroup = db.unitsPerColumn or 5
	local spacingY = db.spacingY or db.spacing or 3
	local spacingX = db.spacingX or 3
	local groupSpacing = db.groupSpacing or 5
	local growDir = db.growDirection or "DOWN"

	-- [FIX] 편집모드에서는 previewRaidCount 기준, 아니면 maxGroups 기준
	local moverDB = (ns.db and ns.db.mover) or {}
	local previewCount = moverDB.previewRaidCount or 20
	local previewGroups = math.ceil(previewCount / 5)
	local maxGroups = math.min(previewGroups, db.maxGroups or C.MAX_RAID_GROUPS)

	-- [FIX] growDirection에 따라 mover 크기 방향 변경
	local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
	if priIsVert then
		-- 1차 세로: 유닛이 세로로 쌓임, 그룹은 가로로 나열
		local totalW = w * maxGroups + groupSpacing * (maxGroups - 1)
		local totalH = h * unitsPerGroup + spacingY * (unitsPerGroup - 1)
		return totalW, totalH
	else
		-- 1차 가로: 유닛이 가로로 나열, 그룹은 세로로 쌓임
		local totalW = w * unitsPerGroup + spacingX * (unitsPerGroup - 1)
		local totalH = h * maxGroups + groupSpacing * (maxGroups - 1)
		return totalW, totalH
	end
end

local function CalcBossMoverSize()
	local db = ns.db.boss
	if not db then return 180, 400 end
	local w = (db.size and db.size[1]) or 180
	local h = (db.size and db.size[2]) or 35
	local spacing = db.spacing or 48
	local count = C.MAX_BOSS_FRAMES or 8
	local growDir = db.growDirection or "DOWN"
	if growDir == "UP" or growDir == "DOWN" or growDir == "V_CENTER" then
		return w, h * count + spacing * (count - 1)
	else
		return w * count + spacing * (count - 1), h
	end
end

local function CalcArenaMoverSize()
	local db = ns.db.arena
	if not db then return 180, 400 end
	local w = (db.size and db.size[1]) or 180
	local h = (db.size and db.size[2]) or 35
	local spacing = db.spacing or 48
	local count = C.MAX_ARENA_FRAMES or 5
	local growDir = db.growDirection or "DOWN"
	if growDir == "UP" or growDir == "DOWN" or growDir == "V_CENTER" then
		return w, h * count + spacing * (count - 1)
	else
		return w * count + spacing * (count - 1), h
	end
end

-----------------------------------------------
-- Fade Animation 헬퍼
-----------------------------------------------

local FADE_DURATION = 0.2

local function FadeIn(frame)
	if not frame then return end
	frame:Show()
	if frame.fadeAnim then
		frame.fadeAnim:Stop()
	end

	local ag = frame.fadeAnim or frame:CreateAnimationGroup()
	frame.fadeAnim = ag

	ag:SetScript("OnPlay", function() frame:SetAlpha(0) end)
	ag:SetScript("OnFinished", function() frame:SetAlpha(1) end)

	local anim = ag.anim or ag:CreateAnimation("Alpha")
	ag.anim = anim
	anim:SetFromAlpha(0)
	anim:SetToAlpha(1)
	anim:SetDuration(FADE_DURATION)
	anim:SetSmoothing("OUT")

	ag:Play()
end

local function FadeOut(frame, onFinish)
	if not frame then return end
	if frame.fadeAnim then
		frame.fadeAnim:Stop()
	end

	local ag = frame.fadeAnim or frame:CreateAnimationGroup()
	frame.fadeAnim = ag

	ag:SetScript("OnPlay", function() frame:SetAlpha(1) end)
	ag:SetScript("OnFinished", function()
		frame:SetAlpha(0)
		frame:Hide()
		if onFinish then onFinish() end
	end)

	local anim = ag.anim or ag:CreateAnimation("Alpha")
	ag.anim = anim
	anim:SetFromAlpha(1)
	anim:SetToAlpha(0)
	anim:SetDuration(FADE_DURATION)
	anim:SetSmoothing("IN")

	ag:Play()
end

-----------------------------------------------
-- [EDITMODE] 다중 선택 해제 헬퍼
-----------------------------------------------

local function DeselectAll()
	for m, _ in pairs(selectedMovers) do
		local c = MOVER_COLORS[m._colorKey] or DEFAULT_COLOR
		m.bd:SetBackdropBorderColor(unpack(c.border))
	end
	wipe(selectedMovers)
	if selectedMover then
		local c = MOVER_COLORS[selectedMover._colorKey] or DEFAULT_COLOR
		selectedMover.bd:SetBackdropBorderColor(unpack(c.border))
	end
	selectedMover = nil
end

-----------------------------------------------
-- [EDITMODE] 무버 선택 (일반 클릭 + Shift=다중 선택)
-- Forward declaration 사용: 파일 상단에서 local SelectMover 선언
-----------------------------------------------

SelectMover = function(mover)
	if IsShiftKeyDown() then
		-- [EDITMODE] Shift+클릭: 다중 선택 토글
		if selectedMovers[mover] then
			-- 이미 다중 선택에 포함 → 제거
			selectedMovers[mover] = nil
			local c = MOVER_COLORS[mover._colorKey] or DEFAULT_COLOR
			mover.bd:SetBackdropBorderColor(unpack(c.border))
			-- 주 선택이었으면 다른 걸로 교체
			if selectedMover == mover then
				selectedMover = next(selectedMovers) or nil
			end
		else
			-- 현재 단일 선택 → 다중 선택 세트에 추가
			if selectedMover and not selectedMovers[selectedMover] then
				selectedMovers[selectedMover] = true
			end
			selectedMovers[mover] = true
			selectedMover = mover
			mover.bd:SetBackdropBorderColor(1, 1, 1, 1)
		end

		-- 타이틀 갱신
		if nudgePanel then
			local count = 0
			for _ in pairs(selectedMovers) do count = count + 1 end
			if count > 1 then
				nudgePanel.title:SetText(count .. "개 선택")
			elseif selectedMover then
				nudgePanel.title:SetText(selectedMover._name or "Frame")
			else
				nudgePanel.title:SetText("Select Frame")
			end
			Mover:UpdateNudgeCoords()
		end
	else
		-- 일반 클릭: 단일 선택 (기존과 동일)
		-- 다중 선택 해제
		for m, _ in pairs(selectedMovers) do
			if m ~= mover then
				local c = MOVER_COLORS[m._colorKey] or DEFAULT_COLOR
				m.bd:SetBackdropBorderColor(unpack(c.border))
			end
		end
		wipe(selectedMovers)

		-- 이전 선택 해제
		if selectedMover and selectedMover ~= mover then
			local oldColors = MOVER_COLORS[selectedMover._colorKey] or DEFAULT_COLOR
			selectedMover.bd:SetBackdropBorderColor(unpack(oldColors.border))
		end

		selectedMover = mover

		-- 선택 표시 (흰색 보더)
		mover.bd:SetBackdropBorderColor(1, 1, 1, 1)

		-- 넛지 패널 갱신
		if nudgePanel then
			nudgePanel.title:SetText(mover._name or "Frame")
			-- [CDM-P1] 선택된 프레임 이름 표시
			if nudgePanel.selectedText then
				local colorKey = mover._colorKey
				local c = MOVER_COLORS[colorKey] or DEFAULT_COLOR
				local cr, cg, cb = c.border[1], c.border[2], c.border[3]
				nudgePanel.selectedText:SetText(string.format("|cff%02x%02x%02x>> %s <<|r", math_floor(cr*255+0.5), math_floor(cg*255+0.5), math_floor(cb*255+0.5), mover._name or "Frame"))
			end
			-- [CDM-P1] 앵커 포인트 드롭다운 동기화
			if nudgePanel.anchorDropdown and nudgePanel.anchorDropdown.SetSelected then
				local pt = select(1, mover:GetPoint(1)) or "CENTER"
				nudgePanel.anchorDropdown:SetSelected(pt)
			end
			-- [CDM 호환] attachTo/selfPoint/anchorPoint 드롭다운 동기화
			local unitKey = mover._unitKey
			local unitDB = unitKey and ns.db[unitKey]
			if unitDB then
				if nudgePanel.attachDropdown and nudgePanel.attachDropdown.SetSelected then
					nudgePanel.attachDropdown:SetSelected(unitDB.attachTo or "UIParent")
				end
				if nudgePanel.selfPtDropdown and nudgePanel.selfPtDropdown.SetSelected then
					nudgePanel.selfPtDropdown:SetSelected(unitDB.selfPoint or "CENTER")
				end
				if nudgePanel.anchorPtDropdown and nudgePanel.anchorPtDropdown.SetSelected then
					nudgePanel.anchorPtDropdown:SetSelected(unitDB.anchorPoint or "CENTER")
				end
			end
			Mover:UpdateNudgeCoords()
		end
	end
end

-----------------------------------------------
-- Create Mover Overlay
-----------------------------------------------

local function CreateMoverOverlay(frame, name, colorKey, overrideW, overrideH)
	if frame._mover then return frame._mover end

	local colors = MOVER_COLORS[colorKey] or DEFAULT_COLOR

	local mover = CreateFrame("Frame", "ddingUI_Mover_" .. name, UIParent)

	if overrideW and overrideH then
		mover:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		mover:SetSize(overrideW, overrideH)
	else
		-- [EDITMODE-FIX] SetAllPoints 대신 명시적 사이즈 설정
		-- SetAllPoints → ClearAllPoints 시 사이즈 0으로 손실되는 문제 방지
		local fW, fH = frame:GetSize()
		if fW and fW > 0 and fH and fH > 0 then
			mover:SetSize(fW, fH)
			mover:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		else
			mover:SetAllPoints(frame) -- 사이즈 미확정 시 fallback
		end
	end

	mover:SetFrameStrata("TOOLTIP")
	mover:SetFrameLevel(510)
	mover:EnableMouse(true)
	mover:SetMovable(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetClampedToScreen(true)
	mover:Hide()

	-- 색상 코딩된 배경
	mover.bg = mover:CreateTexture(nil, "BACKGROUND")
	mover.bg:SetAllPoints()
	mover.bg:SetColorTexture(unpack(colors.bg))

	-- 색상 코딩된 테두리
	mover.bd = CreateFrame("Frame", nil, mover, "BackdropTemplate")
	mover.bd:SetAllPoints()
	mover.bd:SetBackdrop({
		edgeFile = C.FLAT_TEXTURE, -- [12.0.1] 통일
		edgeSize = 1,
	})
	mover.bd:SetBackdropBorderColor(unpack(colors.border))

	-- 라벨
	mover.text = mover:CreateFontString(nil, "OVERLAY")
	mover.text:SetFont(fontPath, 10, "OUTLINE") -- [12.0.1] StyleLib
	mover.text:SetPoint("CENTER")
	mover.text:SetText(name)
	mover.text:SetTextColor(1, 1, 1)


	-- 좌클릭=선택(넛지 패널), 우클릭=설정/리셋/숨기기 -- [12.0.1] ElvUI 스타일 세분화
	mover:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			SelectMover(self)
		elseif button == "RightButton" then
			if IsControlKeyDown() then
				-- Ctrl+우클릭: 위치 리셋
				Mover:ResetMover(self)
			elseif IsShiftKeyDown() then
				-- Shift+우클릭: 임시 숨기기
				self:Hide()
				ns.Print("|cff888888" .. (self._name or "Mover") .. "|r 숨김 (재진입 시 복원)")
			else
				-- 우클릭: 해당 프레임 설정 메뉴 열기
				local unitKey = self._unitKey
				if unitKey and ns.OpenConfig then
					ns.OpenConfig(unitKey)
				end
			end
		end
	end)

	-- 호버: 툴팁 + 다른 Mover 페이드 -- [12.0.1] ElvUI 스타일
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
		GameTooltip:AddLine(self._name or "Mover", 0.6, 0.8, 1)
		GameTooltip:AddLine("좌클릭: 선택  |  Shift+클릭: 다중 선택", 0.7, 0.7, 0.7) -- [EDITMODE]
		GameTooltip:AddLine("드래그: 이동  |  우클릭: 설정", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Ctrl+우: 리셋  |  Shift+우: 숨기기", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("마우스 휠: Y이동  |  Shift+휠: X이동", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("방향키: 넛지  |  Ctrl+방향: 10px", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Ctrl+Z: 되돌리기  |  ESC: 취소", 0.7, 0.7, 0.7) -- [EDITMODE]
		GameTooltip:Show()
		-- [12.0.1] 다른 Mover 페이드아웃 (포커스 강조)
		for _, other in ipairs(movers) do
			if other ~= self and other:IsShown() then
				other:SetAlpha(0.35)
			end
		end
	end)
	mover:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		-- [12.0.1] 모든 Mover 알파 복원
		for _, other in ipairs(movers) do
			if other:IsShown() then
				other:SetAlpha(1)
			end
		end
	end)

	-- [12.0.1] 마우스 휠 넛지 (ElvUI 스타일: Wheel=Y축, Shift+Wheel=X축)
	mover:EnableMouseWheel(true)
	mover:SetScript("OnMouseWheel", function(self, delta)
		SelectMover(self)
		local step = (GetMoverDB().nudgeStep or 1)
		if IsShiftKeyDown() then
			Mover:NudgeSelected(delta * step, 0)
		else
			Mover:NudgeSelected(0, delta * step)
		end
	end)

	-- Drag -- [12.0.1] 드래그 중 스냅 미리보기 + 미리보기 동기화 + 그리드 알파
	mover:SetScript("OnDragStart", function(self)
		SelectMover(self)
		-- [EDITMODE] 드래그 전 위치 저장 (언두용: StartMoving 전에 캡처해야 함)
		local pt, _, _, px, py = self:GetPoint(1)
		if pt then self._preDragPos = { point = pt, x = px or 0, y = py or 0 } end
		self:StartMoving()
		-- 그리드 드래그 시 선명하게
		if gridFrame and gridFrame:IsShown() then
			gridFrame:SetAlpha(1)
		end
		-- OnUpdate: 스냅 미리보기 + 그룹 Mover 동기화
		self:SetScript("OnUpdate", function(s)
			UpdateSnapPreview(s)
			-- [EDITMODE-FIX] 모든 유닛 Mover: 미리보기 컨테이너 실시간 동기화
			-- TOPLEFT 정렬 사용 (CENTER 사용 시 Boss 같은 다중 프레임 컨테이너에서 위치 점프)
			if ns.simContainers and s._unitKey then
				local sim = ns.simContainers[s._unitKey]
				if sim and sim:IsShown() then
					local unitDB = ns.db and ns.db[s._unitKey]
					local growDir = unitDB and unitDB.growDirection or "DOWN"
					
					if (s._unitKey == "boss" or s._unitKey == "arena") and growDir == "UP" then
						local left, bottom = s:GetLeft(), s:GetBottom()
						if left and bottom then
							sim:ClearAllPoints()
							sim:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
						end
					else
						local left, top = s:GetLeft(), s:GetTop()
						if left and top then
							sim:ClearAllPoints()
							sim:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
						end
					end
				end
			end
		end)
	end)

	mover:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil) -- [12.0.1] 드래그 OnUpdate 해제
		HideSnapPreview() -- [12.0.1] 스냅 가이드라인 숨기기
		if gridFrame and gridFrame:IsShown() then gridFrame:SetAlpha(0.4) end
		local point, snapX, snapY = ProcessDragStop(self)
		ApplyMoverVisual(self, point, snapX, snapY, UIParent, point) -- [MOVER] 시각적 이동만 (Done 시 DB 저장)
		ReanchorToAttachTo(self)
		Mover:UpdateNudgeCoords()
	end)

	mover._frame = frame
	mover._name = name
	mover._colorKey = colorKey
	frame._mover = mover

	return mover
end

-----------------------------------------------
-- Initialize
-----------------------------------------------

function Mover:Initialize()
	local frameMappings = {
		{ key = "player",       frame = ns.frames.player,       name = "Player" },
		{ key = "target",       frame = ns.frames.target,       name = "Target" },
		{ key = "targettarget", frame = ns.frames.targettarget, name = "ToT" },
		{ key = "focus",        frame = ns.frames.focus,        name = "Focus" },
		{ key = "focustarget",  frame = ns.frames.focustarget,  name = "FocusTarget" },
		{ key = "pet",          frame = ns.frames.pet,          name = "Pet" },
	}

	for _, mapping in ipairs(frameMappings) do
		local unitDB = ns.db[mapping.key]
		if unitDB and unitDB.enabled ~= false then
			local frame = mapping.frame
			local isPlaceholder = false
			-- [EDITMODE] 프레임 없으면 placeholder 생성
			if not frame then
				isPlaceholder = true
				local phName = "ddingUI_" .. mapping.name .. "Placeholder"
				frame = _G[phName] or CreateFrame("Frame", phName, UIParent)
				local w = (unitDB.size and unitDB.size[1]) or 120
				local h = (unitDB.size and unitDB.size[2]) or 36
				frame:SetSize(w, h)
				frame:Hide()
			end
			local mover = CreateMoverOverlay(frame, mapping.name, mapping.key)
			mover._unitKey = mapping.key
			-- placeholder만 DB 위치로 직접 배치 (실제 프레임은 CreateMoverOverlay가 부착)
			if isPlaceholder then
				local pt, rel, relPt, px, py = ResolvePosition(unitDB.position, unitDB)
				if pt then
					mover:ClearAllPoints()
					mover:SetPoint(pt, rel, relPt, px, py)
					local w = (unitDB.size and unitDB.size[1]) or 120
					local h = (unitDB.size and unitDB.size[2]) or 36
					mover:SetSize(w, h)
				end
			end
			table.insert(movers, mover)
		end
	end

	-- [FIX] Boss mover — Boss1 크기로만 표시 (전용 앵커 프레임 사용)
	do
		local bossDB = ns.db.boss
		if bossDB and bossDB.enabled ~= false then
			local w = (bossDB.size and bossDB.size[1]) or 180
			local h = (bossDB.size and bossDB.size[2]) or 35
			local anchorFrame = CreateFrame("Frame", "ddingUI_BossMoverAnchor", UIParent)
			anchorFrame:SetSize(w, h)
			anchorFrame:Hide()
			local mover = CreateMoverOverlay(anchorFrame, "Boss", "boss", w, h)
			mover._frame = ns.frames.boss1 or anchorFrame
			mover._unitKey = "boss"
			local pt, rel, relPt, px, py = ResolvePosition(bossDB.position, bossDB)
			if pt then
				mover:ClearAllPoints()
				mover:SetPoint(pt, rel, relPt, px, py)
				mover:SetSize(w, h)
			else
				mover:ClearAllPoints()
				mover:SetPoint("RIGHT", UIParent, "RIGHT", -60, 100)
				mover:SetSize(w, h)
			end
			table.insert(movers, mover)
		end
	end

	-- [FIX] Arena mover — Arena1 크기로만 표시 (전용 앵커 프레임 사용)
	do
		local arenaDB = ns.db.arena
		if arenaDB and arenaDB.enabled ~= false then
			local w = (arenaDB.size and arenaDB.size[1]) or 180
			local h = (arenaDB.size and arenaDB.size[2]) or 35
			local anchorFrame = CreateFrame("Frame", "ddingUI_ArenaMoverAnchor", UIParent)
			anchorFrame:SetSize(w, h)
			anchorFrame:Hide()
			local mover = CreateMoverOverlay(anchorFrame, "Arena", "arena", w, h)
			mover._frame = ns.frames.arena1 or anchorFrame
			mover._unitKey = "arena"
			local pt, rel, relPt, px, py = ResolvePosition(arenaDB.position, arenaDB)
			if pt then
				mover:ClearAllPoints()
				mover:SetPoint(pt, rel, relPt, px, py)
				mover:SetSize(w, h)
			else
				mover:ClearAllPoints()
				mover:SetPoint("RIGHT", UIParent, "RIGHT", -60, -200)
				mover:SetSize(w, h)
			end
			table.insert(movers, mover)
		end
	end

	-- [EDITMODE-FIX] Party mover — 항상 전용 앵커 사용 (SecureGroupHeader ._mover 오염 방지)
	do
		local pdb = ns.db.party
		if pdb and pdb.enabled ~= false then
			local w, h = CalcPartyMoverSize()
			-- 항상 전용 앵커 프레임 사용 (실제 헤더의 ._mover 재사용 문제 방지)
			local anchorFrame = CreateFrame("Frame", "ddingUI_PartyMoverAnchor", UIParent)
			anchorFrame:SetSize(w, h)
			anchorFrame:Hide()
			local mover = CreateMoverOverlay(anchorFrame, "Party", "party", w, h)
			-- 실제 헤더를 _frame에 연결 (ApplyMoverVisual에서 이동용)
			mover._frame = ns.headers.gf_party or ns.headers.party or anchorFrame -- [FIX] 키 이름 일치
			mover._unitKey = "party"
			mover._isGroupMover = true
			-- DB 위치로 직접 배치
			local pt, rel, relPt, px, py = ResolvePosition(pdb.position, pdb)
			if pt then
				mover:ClearAllPoints()
				mover:SetPoint(pt, rel, relPt, px, py)
				mover:SetSize(w, h)
			else
				-- 위치 복원 실패 시 기본 위치 보장
				mover:ClearAllPoints()
				mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -40)
				mover:SetSize(w, h)
			end
			table.insert(movers, mover)
		end
	end

	-- [EDITMODE-FIX] Raid mover — 항상 전용 앵커 사용 (SecureGroupHeader ._mover 오염 방지)
	do
		-- [MYTHIC-RAID] 활성 레이드 DB 참조
		local _GF = ns.GroupFrames
		local rdb = (_GF and _GF.GetActiveRaidDB and _GF:GetActiveRaidDB()) or ns.db.raid
		if rdb and rdb.enabled ~= false then
			local w, h = CalcRaidMoverSize()
			-- 항상 전용 앵커 프레임 사용
			local anchorFrame = CreateFrame("Frame", "ddingUI_RaidMoverAnchor", UIParent)
			anchorFrame:SetSize(w, h)
			anchorFrame:Hide()
			local mover = CreateMoverOverlay(anchorFrame, "Raid", "raid", w, h)
			mover._frame = ns.headers.gf_raid_group1 or ns.headers.raid_group1 or anchorFrame -- [FIX] 키 이름 일치
			mover._unitKey = "raid"
			mover._isGroupMover = true
			local pt, rel, relPt, px, py = ResolvePosition(rdb.position, rdb)
			if pt then
				mover:ClearAllPoints()
				mover:SetPoint(pt, rel, relPt, px, py)
				mover:SetSize(w, h)
			else
				mover:ClearAllPoints()
				mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -100)
				mover:SetSize(w, h)
			end
			table.insert(movers, mover)
		end
	end

	-- Player castbar
	if ns.frames.player and ns.frames.player.Castbar then
		local mover = CreateMoverOverlay(ns.frames.player.Castbar, "Castbar", "castbar")
		mover._unitKey = "player"
		mover._isCastbar = true
		mover:SetScript("OnDragStop", function(self)
			self:SetScript("OnUpdate", nil) -- [12.0.1] 드래그 OnUpdate 해제
			HideSnapPreview() -- [12.0.1] 스냅 가이드라인 숨기기
			if gridFrame and gridFrame:IsShown() then gridFrame:SetAlpha(0.4) end
			local point, snapX, snapY = ProcessDragStop(self)
			ApplyMoverVisual(self, point, snapX, snapY, UIParent, point) -- [MOVER] 시각적 이동만
			Mover:UpdateNudgeCoords()
		end)
		table.insert(movers, mover)
	end

	-- [12.0.1] 분리형 파워바 Mover 등록
	for unitKey, frame in pairs(ns.frames) do
		if frame and frame._powerDetached and frame.Power then
			local label = (unitKey:sub(1, 1):upper() .. unitKey:sub(2)) .. " Power"
			local mover = CreateMoverOverlay(frame.Power, label, "powerbar")
			mover._unitKey = unitKey
			mover._isPowerBar = true
			mover:SetScript("OnDragStop", function(self)
				self:SetScript("OnUpdate", nil) -- [12.0.1] 드래그 OnUpdate 해제
				HideSnapPreview() -- [12.0.1] 스냅 가이드라인 숨기기
				if gridFrame and gridFrame:IsShown() then gridFrame:SetAlpha(0.4) end
				local point, snapX, snapY = ProcessDragStop(self)
				ApplyMoverVisual(self, point, snapX, snapY, UIParent, point) -- [MOVER] 시각적 이동만
				Mover:UpdateNudgeCoords()
			end)
			table.insert(movers, mover)
		end
	end

	CreateGridOverlay()

	-- [MOVER] 저장된 movers 위치 적용 (ns.db.movers 네임스페이스)
	ApplyMoverPositions()

	-- [ANCHOR] AnchorManager에 UF 모든 mover 일괄 등록
	local AM_uf = _G.DDingUI and _G.DDingUI.AnchorManager
	if AM_uf and AM_uf.Register then
		for _, mover in ipairs(movers) do
			local moverName = GetMoverDBKey(mover)
			local actualFrame = mover._frame or mover
			local opts = {}
			-- 현재 mover 위치에서 초기 상태 읽기
			local pt, relTo, relPt, ox, oy = mover:GetPoint(1)
			if pt then
				opts.selfPoint = pt
				opts.attachTo = (relTo and relTo:GetName()) or "UIParent"
				opts.anchorPoint = relPt or pt
				opts.offsetX = ox or 0
				opts.offsetY = oy or 0
			end
			AM_uf:Register(moverName, actualFrame, AM_uf.SOURCE_UF, opts)
		end
	end

	-- [12.0.1] 전투 진입 시 자동 편집모드 종료 (ElvUI 패턴: PLAYER_REGEN_DISABLED)
	-- [FIX] PLAYER_LOGOUT 시 편집모드 위치 저장 (/reload 위치 초기화 방지)
	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	eventFrame:RegisterEvent("PLAYER_LOGOUT")
	eventFrame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			if isUnlocked then
				Mover:LockAll()
				ns.Print("|cffff8800전투 진입으로 편집모드가 자동 종료되었습니다.|r")
			end
		elseif event == "PLAYER_LOGOUT" then
			-- 편집모드 중 /reload 시 현재 위치를 DB에 저장
			if isUnlocked then
				SaveAllMoversToDB()
			end
		end
	end)
end

-----------------------------------------------
-- Lock / Unlock (편집모드) + Fade 애니메이션
-----------------------------------------------

-- [CDM 호환] 편집모드 상태 공개 API (Update.lua에서 위치 재적용 스킵 용도)
function Mover:IsUnlocked()
	return isUnlocked
end

function Mover:UnlockAll()
	if InCombatLockdown() then
		ns.Print("|cffff0000전투 중에는 편집모드를 사용할 수 없습니다.|r")
		return
	end

	-- [EDITMODE-FIX] 편집모드 진입 시 열려있는 메뉴/설정 닫기 (dandersFrame 패턴)
	if GameMenuFrame and GameMenuFrame:IsShown() then
		HideUIPanel(GameMenuFrame)
	end
	if SettingsPanel and SettingsPanel:IsShown() then
		HideUIPanel(SettingsPanel)
	end
	-- DDingUI_UF 자체 설정 패널도 닫기
	if ns.Options and ns.Options.frame and ns.Options.frame:IsShown() then
		ns.Options.frame:Hide()
	end

	isUnlocked = true

	-- [MOVER] 편집 전 위치 스냅샷 저장 (ESC 취소용)
	SavePositionSnapshot()

	for _, mover in ipairs(movers) do
		if mover._isGroupMover then
			local w, h
			if mover._unitKey == "party" then
				w, h = CalcPartyMoverSize()
			elseif mover._unitKey == "raid" then
				w, h = CalcRaidMoverSize()
			end
			if w and h then
				mover:SetSize(w, h)
			end

			mover:ClearAllPoints()
			-- [FIX] 실제 보이는 자식 프레임의 바운딩 박스에서 위치 추출
			-- growDirection에 따라 적절한 앵커 포인트 사용
			local positioned = false
			local GF = ns.GroupFrames
			if GF then
				local headers
				if mover._unitKey == "raid" and GF.raidHeaders then
					headers = GF.raidHeaders
				elseif mover._unitKey == "party" and GF.partyHeader then
					headers = { GF.partyHeader }
				end
				if headers then
					local minL, maxR, minB, maxT
					for _, hdr in ipairs(headers) do
						for j = 1, 40 do
							local child = hdr:GetAttribute("child" .. j)
							if not child then break end
							if child:IsShown() then
								local l, b, cw, ch = child:GetRect()
								if l then
									if not minL or l < minL then minL = l end
									if not maxR or (l + cw) > maxR then maxR = l + cw end
									if not minB or b < minB then minB = b end
									if not maxT or (b + ch) > maxT then maxT = b + ch end
								end
							end
						end
					end
					if minL and maxR and minB and maxT then
						local mW, mH = w or (maxR - minL), h or (maxT - minB)

						-- growDirection에 따른 앵커 포인트 결정
						local unitDB = ns.db[mover._unitKey]
						local growDir = (unitDB and unitDB.growDirection) or "DOWN"
						local groupGrowDir = unitDB and unitDB.groupGrowDirection
						if not groupGrowDir then
							if growDir == "H_CENTER" or growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER" then
								groupGrowDir = "RIGHT"
							else
								groupGrowDir = "DOWN"
							end
						end

						-- 1차 방향 → Y축 앵커
						local yAnchor = "TOP" -- 기본: DOWN (위에서 시작)
						if growDir == "UP" then
							yAnchor = "BOTTOM"
						elseif growDir == "V_CENTER" then
							yAnchor = "" -- 센터
						end

						-- 2차 방향 → X축 앵커 (레이드만 의미 있음)
						local xAnchor = "LEFT" -- 기본: RIGHT (왼쪽에서 시작)
						if groupGrowDir == "LEFT" then
							xAnchor = "RIGHT"
						elseif mover._unitKey == "party" then
							-- 파티: 1차 가로 방향일 때
							if growDir == "LEFT" then
								xAnchor = "RIGHT"
							elseif growDir == "H_CENTER" then
								xAnchor = ""
							end
						end

						-- 1차가 가로이면 xAnchor/yAnchor 의미 전환
						local priIsVert = (growDir == "DOWN" or growDir == "UP" or growDir == "V_CENTER")
						if not priIsVert then
							-- 1차 가로: X축이 1차
							xAnchor = "LEFT"
							if growDir == "LEFT" then xAnchor = "RIGHT"
							elseif growDir == "H_CENTER" then xAnchor = "" end
							yAnchor = "TOP"
							if groupGrowDir == "UP" then yAnchor = "BOTTOM"
							elseif groupGrowDir == "DOWN" then yAnchor = "TOP" end
						end

						local anchorPt = yAnchor .. xAnchor
						if anchorPt == "" then anchorPt = "CENTER" end

						-- 바운딩 박스에서 앵커 포인트 위치 추출
						local absX, absY
						if anchorPt:find("LEFT") then absX = minL
						elseif anchorPt:find("RIGHT") then absX = maxR
						else absX = (minL + maxR) / 2 end

						if anchorPt:find("TOP") then absY = maxT
						elseif anchorPt:find("BOTTOM") then absY = minB
						else absY = (minB + maxT) / 2 end

						-- UIParent 기준 오프셋 계산
						local uiW, uiH = UIParent:GetSize()
						local oX, oY
						if anchorPt:find("LEFT") then oX = absX
						elseif anchorPt:find("RIGHT") then oX = absX - uiW
						else oX = absX - uiW / 2 end

						if anchorPt:find("TOP") then oY = absY - uiH
						elseif anchorPt:find("BOTTOM") then oY = absY
						else oY = absY - uiH / 2 end

						oX = math_floor(oX + 0.5)
						oY = math_floor(oY + 0.5)

						mover:SetPoint(anchorPt, UIParent, anchorPt, oX, oY)
						mover:SetSize(mW, mH)
						positioned = true
					end
				end
			end
			-- [FIX] 자식이 없으면 (솔로 등) DB 위치 + 계산 크기로 fallback
			if not positioned then
				local unitDB = ns.db[mover._unitKey]
				local pos = unitDB and unitDB.position
				local pt, rel, relPt, px, py = ResolvePosition(pos, unitDB)
				if pt then
					mover:SetPoint(pt, rel, relPt, px, py)
				else
					mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -100)
				end
			end
		else
			-- [EDITMODE-FIX] 비그룹 Mover 사이즈를 프레임에 동기화 (설정 변경/사이즈 손실 대응)
			if mover._frame then
				local fW, fH = mover._frame:GetSize()
				if fW and fW > 0 and fH and fH > 0 then
					mover:SetSize(fW, fH)
				end
			end
		end
		FadeIn(mover)
	end

	-- 그리드: 설정에 따라 조건부 표시
	local mdb = GetMoverDB()
	if mdb.gridEnabled then
		local grid = CreateGridOverlay()
		if grid then FadeIn(grid) end
	end

	-- [MOVER] 카테고리 필터 리셋
	_activeCategory = "All"

	-- 넛지 패널 표시
	Mover:CreateNudgePanel()
	if nudgePanel then
		nudgePanel:Show()
		if nudgePanel.RefreshFrameList then nudgePanel:RefreshFrameList() end
		if nudgePanel.UpdateFilterBtns then nudgePanel:UpdateFilterBtns() end
	end

	-- [REFACTOR] 편집모드 진입 시 테스트모드 자동 활성화
	if ns.Update and ns.Update.EnableEditMode then
		ns.Update:EnableEditMode()
		ApplyMoverFilter(_activeCategory)
	end
end

function Mover:LockAll()
	isUnlocked = false
	selectedMover = nil
	wipe(selectedMovers) -- [EDITMODE] 다중 선택 해제
	wipe(undoStack) -- [EDITMODE] 언두 스택 초기화
	wipe(redoStack) -- [CDM-P1] 리두 스택 초기화

	-- [MOVER] 모든 무버 위치를 DB에 저장 (Done 시점)
	SaveAllMoversToDB()

	for _, mover in ipairs(movers) do
		FadeOut(mover)
	end

	if gridFrame then FadeOut(gridFrame) end

	if nudgePanel then
		nudgePanel:Hide()
	end

	-- [REFACTOR] 테스트모드 종료
	if ns.Update and ns.Update.DisableEditMode then
		ns.Update:DisableEditMode()
	end

	-- [BUG-FIX] 편집모드 종료 후 실제 프레임 위치를 DB와 동기화
	-- (편집 중 ApplyMoverVisual로 설정된 UIParent 좌표 → DB position 기반 재적용)
	if ns.Update and ns.Update.RefreshAllFrames then
		C_Timer.After(0.1, function()
			ns.Update:RefreshAllFrames()
		end)
	end
end

function Mover:IsUnlocked()
	return isUnlocked
end

-- [MOVER] 편집 취소 (ESC): 스냅샷 복원 + 잠금 (DB 저장 없음)
function Mover:CancelEditMode()
	if not isUnlocked then return end
	isUnlocked = false
	selectedMover = nil
	wipe(selectedMovers) -- [EDITMODE] 다중 선택 해제
	wipe(undoStack) -- [EDITMODE] 언두 스택 초기화
	wipe(redoStack) -- [CDM-P1] 리두 스택 초기화

	-- 편집 전 위치로 복원
	RestorePositionSnapshot()

	for _, mover in ipairs(movers) do
		FadeOut(mover)
	end

	if gridFrame then FadeOut(gridFrame) end

	if nudgePanel then
		nudgePanel:Hide()
	end

	-- [REFACTOR] 테스트모드 종료
	if ns.Update and ns.Update.DisableEditMode then
		ns.Update:DisableEditMode()
	end

	-- [BUG-FIX] 편집 취소 후 실제 프레임 위치를 DB(원래 스냅샷)와 동기화
	if ns.Update and ns.Update.RefreshAllFrames then
		C_Timer.After(0.1, function()
			ns.Update:RefreshAllFrames()
		end)
	end

	ns.Print("|cffff8800편집 취소 — 이전 위치로 복원되었습니다.|r")
end

-----------------------------------------------
-- [CDM 호환] 넛지 패널 (CDM과 동일한 cursorY 흐름 레이아웃)
-- 악센트 컬러만 UF(녹색 계열)로 차별화
-----------------------------------------------

function Mover:CreateNudgePanel()
	if nudgePanel then return end

	-- StyleLib 색상 참조 (UF 악센트)
	local accent = SL and { SL.GetAccent("UnitFrames") } or { {0.30, 0.85, 0.45}, {0.12, 0.55, 0.20} }
	local accentFrom = accent[1] or {0.30, 0.85, 0.45}
	local panelBg = SL and SL.Colors.bg.main or {0.10, 0.10, 0.10, 0.95}
	local panelBorder = SL and SL.Colors.border.default or {0.25, 0.25, 0.25, 0.50}
	local inputBg = SL and SL.Colors.bg.input or {0.06, 0.06, 0.06, 0.80}

	local SOLID = C.FLAT_TEXTURE or "Interface\\Buttons\\WHITE8x8"
	local ddInputBg = SL and SL.Colors.bg.input or {0.06, 0.06, 0.06, 0.80}
	local ddHoverBg = SL and SL.Colors.bg.hover or {0.15, 0.15, 0.15, 0.80}
	local ddMainBg  = SL and SL.Colors.bg.main  or {0.10, 0.10, 0.10, 0.95}
	local ddBorder  = SL and SL.Colors.border.default or {0.25, 0.25, 0.25, 0.50}

	local panel = CreateFrame("Frame", "ddingUI_NudgePanel", UIParent, "BackdropTemplate")
	panel:SetSize(240, 764) -- CDM과 동일한 크기
	panel:SetPoint("TOP", UIParent, "TOP", 0, -50)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetFrameLevel(600)
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	panel:Hide()
	panel._editing = false

	-- 배경 (CDM 동일)
	panel:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
	panel:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], panelBg[4] or 0.95)
	panel:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	if SL and SL.CreateHorizontalGradient then
		local gradLine = SL.CreateHorizontalGradient(panel, accentFrom, accent[2] or accentFrom, 2, "OVERLAY")
		if gradLine then
			gradLine:ClearAllPoints()
			gradLine:SetPoint("TOPLEFT", 0, 0)
			gradLine:SetPoint("TOPRIGHT", 0, 0)
		end
	end

	-- 드래그 가능한 타이틀 바 (CDM 동일 패턴)
	local titleBar = CreateFrame("Frame", nil, panel)
	titleBar:SetHeight(16)
	titleBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	titleBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
	titleBar:EnableMouse(true)

	local titleBarDragging = false
	local titleBarOffsetX, titleBarOffsetY = 0, 0

	titleBar:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			titleBarDragging = true
			local scale = panel:GetEffectiveScale()
			local mouseX, mouseY = GetCursorPosition()
			mouseX = mouseX / scale
			mouseY = mouseY / scale
			local frameX, frameY = panel:GetCenter()
			titleBarOffsetX = frameX - mouseX
			titleBarOffsetY = frameY - mouseY
		end
	end)

	titleBar:SetScript("OnMouseUp", function() titleBarDragging = false end)

	panel:SetScript("OnUpdate", function(self)
		if titleBarDragging then
			local scale = self:GetEffectiveScale()
			local mouseX, mouseY = GetCursorPosition()
			mouseX = mouseX / scale
			mouseY = mouseY / scale
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mouseX + titleBarOffsetX, mouseY + titleBarOffsetY)
		end
	end)

	-- Close button (CDM ?숈씪)
	local closeBtn = CreateFrame("Button", nil, panel)
	closeBtn:SetSize(28, 24)
	closeBtn:SetPoint("TOPRIGHT", -4, -4)
	local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	closeText:SetPoint("CENTER")
	closeText:SetText("X")
	closeText:SetTextColor(0.5, 0.5, 0.5)
	closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3) end)
	closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.5, 0.5, 0.5) end)
	closeBtn:SetScript("OnClick", function()
		if isUnlocked then
			Mover:LockAll()
		else
			panel:Hide()
		end
	end)

	-- ================================================================
	-- cursorY 흐름 레이아웃 (CDM과 동일)
	-- ================================================================
	local cursorY = -10
	local PAD = 6
	local SECTION_PAD = 12

	-- Title
	panel.title = panel:CreateFontString(nil, "OVERLAY")
	panel.title:SetFont(fontPath, 12, "OUTLINE")
	panel.title:SetPoint("TOP", 0, cursorY)
	panel.title:SetText("편집 모드")
	panel.title:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3])
	cursorY = cursorY - 16

	-- Selected frame name
	panel.selectedText = panel:CreateFontString(nil, "OVERLAY")
	panel.selectedText:SetFont(fontPath, 10, "OUTLINE")
	panel.selectedText:SetPoint("TOP", 0, cursorY)
	panel.selectedText:SetText("|cff888888프레임을 클릭하세요|r")
	cursorY = cursorY - 14

	-- Anchor info (현재 기준점 + 앵커 프레임) (CDM 동일)
	panel.anchorLabel = panel:CreateFontString(nil, "OVERLAY")
	panel.anchorLabel:SetFont(fontPath, 9, "OUTLINE")
	panel.anchorLabel:SetPoint("TOP", 0, cursorY)
	panel.anchorLabel:SetText("-- → --")
	panel.anchorLabel:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3])
	cursorY = cursorY - 13

	panel.anchorFrameLabel = panel:CreateFontString(nil, "OVERLAY")
	panel.anchorFrameLabel:SetFont(fontPath, 9, "OUTLINE")
	panel.anchorFrameLabel:SetPoint("TOP", 0, cursorY)
	panel.anchorFrameLabel:SetText("@ --")
	panel.anchorFrameLabel:SetTextColor(0.65, 0.65, 0.65)
	cursorY = cursorY - 16

	-- 좌표 (선택된 참조 프레임)
	panel.coords = panel:CreateFontString(nil, "OVERLAY")
	panel.coords:SetFont(fontPath, 1, "OUTLINE")
	panel.coords:SetPoint("TOP", panel.anchorFrameLabel, "BOTTOM", 0, 0)
	panel.coords:SetAlpha(0)

	-- [MOVER] P3 카테고리 필터 버튼 추가
	local filterRow = CreateFrame("Frame", nil, panel)
	filterRow:SetSize(190, 18)
	filterRow:SetPoint("TOP", panel, "TOP", 0, cursorY)
	cursorY = cursorY - 20
	panel.filterBtns = {}

	local filterBtnW = 44
	local filterBtnH = 16
	for idx, cat in ipairs(CATEGORY_ORDER) do
		local xOff = (idx - 2) * (filterBtnW + 2)
		local btn = CreateFrame("Button", nil, filterRow)
		btn:SetSize(filterBtnW, filterBtnH)
		btn:SetPoint("CENTER", filterRow, "CENTER", xOff, 0)
		btn._cat = cat

		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		btn._bg = bg

		local text = btn:CreateFontString(nil, "OVERLAY")
		text:SetFont(fontPath, 8, "OUTLINE")
		text:SetPoint("CENTER")
		text:SetText(cat)
		btn.text = text

		btn:SetScript("OnClick", function()
			ApplyMoverFilter(cat)
			panel:UpdateFilterBtns()
		end)

		table.insert(panel.filterBtns, btn)
	end

	function panel:UpdateFilterBtns()
		for _, btn in ipairs(self.filterBtns) do
			if btn._cat == _activeCategory then
				btn._bg:SetColorTexture(accentFrom[1] * 0.4, accentFrom[2] * 0.4, accentFrom[3] * 0.4, 0.9)
				btn.text:SetTextColor(1, 1, 1)
			else
				btn._bg:SetColorTexture(0.12, 0.12, 0.12, 0.7)
				btn.text:SetTextColor(0.5, 0.5, 0.5)
			end
		end
	end
	panel:UpdateFilterBtns()

	-- ==========================================
	-- [ANCHOR-GRID] 9-point 앵커 선택기 (CDM 동일)
	-- ==========================================
	local ANCHOR_POINTS = {"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}

	local GRID_H_ANCHOR = 150
	local anchorGridContainer = CreateFrame("Frame", nil, panel)
	anchorGridContainer:SetSize(220, GRID_H_ANCHOR)
	anchorGridContainer:SetPoint("TOP", panel, "TOP", 0, cursorY)
	cursorY = cursorY - GRID_H_ANCHOR - PAD

	local CDM_GRID_W = 180
	local CDM_GRID_H = 105
	local CDM_DOT_SZ = 12
	local CDM_DOT_SEL_SZ = 18

	local previewFrame = CreateFrame("Frame", nil, anchorGridContainer, "BackdropTemplate")
	previewFrame:SetSize(CDM_GRID_W, CDM_GRID_H)
	previewFrame:SetPoint("TOP", anchorGridContainer, "TOP", 0, -2)
	previewFrame:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
	previewFrame:SetBackdropColor(0.10, 0.10, 0.10, 0.90)
	previewFrame:SetBackdropBorderColor(0.70, 0.70, 0.70, 0.90)

	-- 크기 텍스트
	local sizeText = anchorGridContainer:CreateFontString(nil, "OVERLAY")
	sizeText:SetFont(fontPath, 9, "OUTLINE")
	sizeText:SetPoint("TOP", previewFrame, "BOTTOM", 0, -4)
	sizeText:SetTextColor(0.9, 0.75, 0.2, 0.9)
	sizeText:SetText("")
	panel._anchorSizeText = sizeText

	panel._anchorDots = {}
	panel._selfPointCurrent = "CENTER"
	panel._anchorPointCurrent = "CENTER"

	local SELF_PT_COLOR = { 0.25, 0.78, 0.88 }
	local ANC_PT_COLOR  = { accentFrom[1], accentFrom[2], accentFrom[3] }
	local BOTH_PT_COLOR = { 1, 0.85, 0.3 }

	local DOT_POSITIONS = {
		TOPLEFT = {x=0, y=0}, TOP = {x=0.5, y=0}, TOPRIGHT = {x=1, y=0},
		LEFT = {x=0, y=0.5}, CENTER = {x=0.5, y=0.5}, RIGHT = {x=1, y=0.5},
		BOTTOMLEFT = {x=0, y=1}, BOTTOM = {x=0.5, y=1}, BOTTOMRIGHT = {x=1, y=1},
	}

	local function UpdateAnchorDots()
		local selfPt = panel._selfPointCurrent or "CENTER"
		local ancPt  = panel._anchorPointCurrent or "CENTER"
		for _, apName in ipairs(ANCHOR_POINTS) do
			local dot = panel._anchorDots[apName]
			if dot then
				local isSelf = (apName == selfPt)
				local isAnc  = (apName == ancPt)
				if isSelf and isAnc then
					dot:SetSize(CDM_DOT_SEL_SZ, CDM_DOT_SEL_SZ)
					dot._bg:SetColorTexture(BOTH_PT_COLOR[1], BOTH_PT_COLOR[2], BOTH_PT_COLOR[3], 1)
					dot._border:SetColorTexture(1, 1, 1, 0.9)
					if dot._glow then dot._glow:SetColorTexture(BOTH_PT_COLOR[1], BOTH_PT_COLOR[2], BOTH_PT_COLOR[3], 0.18); dot._glow:SetSize(CDM_DOT_SEL_SZ+12, CDM_DOT_SEL_SZ+12); dot._glow:Show() end
				elseif isSelf then
					dot:SetSize(CDM_DOT_SEL_SZ, CDM_DOT_SEL_SZ)
					dot._bg:SetColorTexture(SELF_PT_COLOR[1], SELF_PT_COLOR[2], SELF_PT_COLOR[3], 1)
					dot._border:SetColorTexture(1, 1, 1, 0.9)
					if dot._glow then dot._glow:SetColorTexture(SELF_PT_COLOR[1], SELF_PT_COLOR[2], SELF_PT_COLOR[3], 0.18); dot._glow:SetSize(CDM_DOT_SEL_SZ+12, CDM_DOT_SEL_SZ+12); dot._glow:Show() end
				elseif isAnc then
					dot:SetSize(CDM_DOT_SEL_SZ, CDM_DOT_SEL_SZ)
					dot._bg:SetColorTexture(ANC_PT_COLOR[1], ANC_PT_COLOR[2], ANC_PT_COLOR[3], 1)
					dot._border:SetColorTexture(1, 1, 1, 0.9)
					if dot._glow then dot._glow:SetColorTexture(ANC_PT_COLOR[1], ANC_PT_COLOR[2], ANC_PT_COLOR[3], 0.18); dot._glow:SetSize(CDM_DOT_SEL_SZ+12, CDM_DOT_SEL_SZ+12); dot._glow:Show() end
				else
					dot:SetSize(CDM_DOT_SZ, CDM_DOT_SZ)
					dot._bg:SetColorTexture(0.40, 0.40, 0.40, 0.9)
					dot._border:SetColorTexture(0.60, 0.60, 0.60, 0.7)
					if dot._glow then dot._glow:Hide() end
				end
			end
		end
	end
	panel._refreshAnchorGrid = UpdateAnchorDots

	for _, apName in ipairs(ANCHOR_POINTS) do
		local posInfo = DOT_POSITIONS[apName]
		local dot = CreateFrame("Button", nil, previewFrame)
		dot:SetSize(CDM_DOT_SZ, CDM_DOT_SZ)
		dot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		dot:SetPoint("CENTER", previewFrame, "TOPLEFT", posInfo.x * CDM_GRID_W, -posInfo.y * CDM_GRID_H)
		dot:SetFrameLevel(previewFrame:GetFrameLevel() + 3)

		local border = dot:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.60, 0.60, 0.60, 0.7)
		dot._border = border

		local bg = dot:CreateTexture(nil, "ARTWORK")
		bg:SetPoint("TOPLEFT", 1, -1)
		bg:SetPoint("BOTTOMRIGHT", -1, 1)
		bg:SetColorTexture(0.40, 0.40, 0.40, 0.9)
		dot._bg = bg

		local glow = dot:CreateTexture(nil, "OVERLAY")
		glow:SetPoint("CENTER")
		glow:SetSize(CDM_DOT_SEL_SZ + 12, CDM_DOT_SEL_SZ + 12)
		glow:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 0.18)
		glow:Hide()
		dot._glow = glow

		dot:SetScript("OnEnter", function(self)
			local isSelf = (apName == panel._selfPointCurrent)
			local isAnc  = (apName == panel._anchorPointCurrent)
			if not isSelf and not isAnc then
				self._bg:SetColorTexture(0.55, 0.55, 0.55, 1)
				self._border:SetColorTexture(0.8, 0.8, 0.8, 0.8)
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 0)
			if isSelf and isAnc then
				GameTooltip:AddLine("|cffffd633" .. apName .. "|r  (Self + Anchor)", 1, 1, 1)
			elseif isSelf then
				GameTooltip:AddLine("|cff40c8e0" .. apName .. "|r  (Self Point)", 1, 1, 1)
			elseif isAnc then
				GameTooltip:AddLine(apName .. "  (Anchor Point)", accentFrom[1], accentFrom[2], accentFrom[3])
			else
				GameTooltip:AddLine(apName, 1, 1, 1)
			end
			GameTooltip:AddLine("좌클릭 Anchor Point 변경", 0.5, 0.5, 0.5)
			GameTooltip:AddLine("우클릭 Self Point 변경", 0.5, 0.5, 0.5)
			GameTooltip:Show()
		end)
		dot:SetScript("OnLeave", function(self)
			local isSelf = (apName == panel._selfPointCurrent)
			local isAnc  = (apName == panel._anchorPointCurrent)
			if not isSelf and not isAnc then
				self._bg:SetColorTexture(0.35, 0.35, 0.35, 0.9)
				self._border:SetColorTexture(0.55, 0.55, 0.55, 0.6)
			end
			GameTooltip:Hide()
		end)

		dot:SetScript("OnClick", function(_, button)
			if not selectedMover then return end
			local unitKey = selectedMover._unitKey
			local unitDB = unitKey and ns.db[unitKey]

			-- 언두 스냅샷 (변경 전)
			local oldPt, _, _, oldX, oldY = selectedMover:GetPoint(1)
			if oldPt then
				if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
				undoStack[#undoStack + 1] = { mover = selectedMover, point = oldPt, x = oldX or 0, y = oldY or 0 }
				wipe(redoStack)
				if nudgePanel and nudgePanel.UpdateUndoRedoBtns then nudgePanel:UpdateUndoRedoBtns() end
			end

			if button == "LeftButton" then
				if unitDB then unitDB.anchorPoint = apName end
				panel._anchorPointCurrent = apName
			elseif button == "RightButton" then
				if unitDB then unitDB.selfPoint = apName end
				panel._selfPointCurrent = apName
			end

			-- [FIX] 앵커 변경 즉시 무버 위치 재계산
			if unitDB then
				local attachTo = unitDB.attachTo
				if attachTo and attachTo ~= "" and attachTo ~= "UIParent" then
					-- attachTo 프레임 기준: ReanchorToAttachTo 사용
					ReanchorToAttachTo(selectedMover)
				else
					-- UIParent 기준: 화면 절대좌표 유지, 새 selfPoint 기준 오프셋 역산
					local mLeft = selectedMover:GetLeft()
					local mBottom = selectedMover:GetBottom()
					local mW, mH = selectedMover:GetSize()
					if mLeft and mBottom and mW and mW > 0 then
						local pW, pH = UIParent:GetSize()
						local newPt = unitDB.selfPoint or "CENTER"
						local ox, oy

						-- newPt 기준 오프셋 계산 (SetPoint(newPt, UIParent, newPt, ox, oy) 형태)
						-- X축
						if newPt:find("LEFT") then
							ox = mLeft
						elseif newPt:find("RIGHT") then
							ox = (mLeft + mW) - pW
						else
							ox = (mLeft + mW / 2) - pW / 2
						end
						-- Y축
						if newPt:find("TOP") then
							oy = (mBottom + mH) - pH
						elseif newPt:find("BOTTOM") then
							oy = mBottom
						else
							oy = (mBottom + mH / 2) - pH / 2
						end

						ox = math_floor(ox + 0.5)
						oy = math_floor(oy + 0.5)
						ApplyMoverVisual(selectedMover, newPt, ox, oy, UIParent, newPt)
					end
				end
			end

			-- 실제 유닛 프레임 레이아웃 반영
			if ns.Update and ns.Update.RefreshUnit and unitKey then
				ns.Update:RefreshUnit(unitKey)
			end

			UpdateAnchorDots()
			Mover:UpdateNudgeCoords()
		end)

		panel._anchorDots[apName] = dot
	end

	UpdateAnchorDots()

	-- 호환용 anchorDropdown API
	panel.anchorDropdown = {
		SetSelected = function(_, val)
			panel._anchorPointCurrent = val or "CENTER"
			UpdateAnchorDots()
		end,
	}

	-- ==========================================
	-- CreateFlatDropdown 유틸리티 (CDM 동일)
	-- ==========================================
	local function CreateFlatDropdown(parent, labelText, width, anchorPt, anchorFrame_dd, anchorRelPt, xOff, yOff, items, onSelect)
		local container = CreateFrame("Frame", nil, parent)
		container:SetSize(width + 10, 40)
		container:SetPoint(anchorPt, anchorFrame_dd, anchorRelPt, xOff, yOff)

		local lbl = container:CreateFontString(nil, "OVERLAY")
		lbl:SetFont(fontPath, 9, "OUTLINE")
		lbl:SetPoint("TOPLEFT", 0, 0)
		lbl:SetText(labelText)

		local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
		btn:SetSize(width, 22)
		btn:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
		btn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
		btn:SetBackdropColor(unpack(ddInputBg))
		btn:SetBackdropBorderColor(unpack(ddBorder))

		local selText = btn:CreateFontString(nil, "OVERLAY")
		selText:SetFont(fontPath, 9, "OUTLINE")
		selText:SetPoint("LEFT", 4, 0)
		selText:SetPoint("RIGHT", -16, 0)
		selText:SetJustifyH("LEFT")
		selText:SetWordWrap(false)

		local arrow = btn:CreateFontString(nil, "OVERLAY")
		arrow:SetFont(fontPath, 9, "OUTLINE")
		arrow:SetPoint("RIGHT", -4, 0)
		arrow:SetText("\226\150\188") -- ▼

		container._value = nil
		container._text = ""
		container._items = items or {}

		local function SetDisplay(text, value)
			container._value = value
			container._text = text
			selText:SetText(text or "--")
		end

		local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		list:SetFrameStrata("FULLSCREEN_DIALOG")
		list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
		list:SetWidth(width)
		list:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
		list:SetBackdropColor(unpack(ddMainBg))
		list:SetBackdropBorderColor(unpack(ddBorder))
		list:Hide()

		local catcher = CreateFrame("Button", nil, list)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:SetFrameLevel(math.max(0, list:GetFrameLevel() - 1))
		catcher:SetAllPoints(UIParent)
		catcher:SetScript("OnClick", function() list:Hide(); catcher:Hide() end)
		catcher:EnableMouseWheel(true)
		catcher:SetScript("OnMouseWheel", function() list:Hide(); catcher:Hide() end)
		catcher:Hide()

		local rowButtons = {}
		local function RebuildItems(newItems)
			for _, rb in ipairs(rowButtons) do rb:Hide() end
			wipe(rowButtons)
			container._items = newItems or container._items
			local totalH = #container._items * 20 + 2
			list:SetHeight(math.min(totalH, 10 * 20 + 2))

			for i, item in ipairs(container._items) do
				local row = CreateFrame("Button", nil, list)
				row:SetSize(width - 2, 20)
				row:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -(1 + (i - 1) * 20))

				local rowBG = row:CreateTexture(nil, "BACKGROUND")
				rowBG:SetAllPoints()
				rowBG:SetColorTexture(0, 0, 0, 0)

				local rowText = row:CreateFontString(nil, "OVERLAY")
				rowText:SetFont(fontPath, 9, "OUTLINE")
				rowText:SetPoint("LEFT", 4, 0)
				rowText:SetText(item.text or item)
				rowText:SetJustifyH("LEFT")

				row:SetScript("OnEnter", function() rowBG:SetColorTexture(unpack(ddHoverBg)) end)
				row:SetScript("OnLeave", function() rowBG:SetColorTexture(0, 0, 0, 0) end)
				row:SetScript("OnClick", function()
					local val = item.value or item
					local txt = item.text or item
					SetDisplay(txt, val)
					list:Hide()
					catcher:Hide()
					if onSelect then onSelect(val, txt) end
				end)
				rowButtons[#rowButtons + 1] = row
			end
		end

		RebuildItems()
		if #container._items > 0 then
			local first = container._items[1]
			SetDisplay(first.text or first, first.value or first)
		end

		btn:SetScript("OnClick", function()
			if list:IsShown() then list:Hide(); catcher:Hide()
			else list:Show(); catcher:Show() end
		end)
		btn:SetScript("OnEnter", function() btn:SetBackdropColor(unpack(ddHoverBg)) end)
		btn:SetScript("OnLeave", function() btn:SetBackdropColor(unpack(ddInputBg)) end)

		function container:SetValue(val, displayText) SetDisplay(displayText or val, val) end
		function container:GetValue() return self._value end
		function container:SetItems(newItems) RebuildItems(newItems) end

		container.button = btn
		container.label = lbl
		return container
	end

	-- ==========================================
	-- 프레임 선택 드롭다운 (CDM 동일: 모든 무버 리스트)
	-- ==========================================
	local frameSelectDropdown = CreateFlatDropdown(panel,
		"프레임 선택", 170,
		"TOP", panel, "TOP", 0, -900,  -- 임시, cursorY로 옮겨짐
		{ {text="선택 없음", value=""} },
		function(val)
			if not val or val == "" then return end
			for _, m in ipairs(movers) do
				if m._name == val or GetMoverDBKey(m) == val then
					SelectMover(m)
					break
				end
			end
		end)
	panel.frameSelectDropdown = frameSelectDropdown

	-- 무버 리스트 갱신 함수
	function panel:RefreshFrameList()
		-- 프레임 선택 드롭다운
		local items = { {text="선택 없음", value=""} }
		for _, m in ipairs(movers) do
			local name = m._name or GetMoverDBKey(m) or "Unknown"
			items[#items + 1] = { text = name, value = GetMoverDBKey(m) or name }
		end
		table.sort(items, function(a, b) return a.text < b.text end)
		if frameSelectDropdown.SetItems then
			frameSelectDropdown:SetItems(items)
		end

		-- 연결 대상 드롭다운 (CDM 프록시 + UF 프레임)
		if self.anchorFrameDropdown and self.anchorFrameDropdown.SetItems then
			local afItems = { {text="UIParent", value="UIParent"} }
			local CDM_PROXIES = {
				{ name = "DDingUI_Anchor_Cooldowns", label = "CDM: 쿨다운" },
				{ name = "DDingUI_Anchor_Buffs",     label = "CDM: 강화" },
				{ name = "DDingUI_Anchor_Utility",   label = "CDM: 보조" },
			}
			for _, proxy in ipairs(CDM_PROXIES) do
				if _G[proxy.name] then
					afItems[#afItems + 1] = { text = proxy.label, value = proxy.name }
				end
			end
			local UF_FRAMES = {
				{ name = "ddingUI_Player", label = "UF: Player" },
				{ name = "ddingUI_Target", label = "UF: Target" },
				{ name = "ddingUI_Focus",  label = "UF: Focus" },
				{ name = "ddingUI_Pet",    label = "UF: Pet" },
			}
			for _, uf in ipairs(UF_FRAMES) do
				if _G[uf.name] then
					afItems[#afItems + 1] = { text = uf.label, value = uf.name }
				end
			end
			self.anchorFrameDropdown:SetItems(afItems)
		end
	end

	-- Anchor Frame Dropdown (연결 대상) (CDM 동일)
	local anchorFrameDropdown = CreateFlatDropdown(panel,
		"연결 대상", 130,
		"TOP", panel, "TOP", 0, -900,  -- 임시, cursorY로 옮겨짐
		{ {text="UIParent", value="UIParent"} },
		function(val)
			if not selectedMover then return end
			local unitKey = selectedMover._unitKey
			if not unitKey or not ns.db[unitKey] then return end
			ns.db[unitKey].attachTo = val
			if ns.Update and ns.Update.RefreshUnit then
				ns.Update:RefreshUnit(unitKey)
			end
			Mover:UpdateNudgeCoords()
		end)
	panel.anchorFrameDropdown = anchorFrameDropdown

	-- selfPoint/anchorPoint 호환 API
	panel.selfPtDropdown = { SetSelected = function(_, val)
		panel._selfPointCurrent = val or "CENTER"
		if panel._refreshAnchorGrid then panel._refreshAnchorGrid() end
	end }
	panel.anchorPtDropdown = { SetSelected = function(_, val)
		panel._anchorPointCurrent = val or "CENTER"
		if panel._refreshAnchorGrid then panel._refreshAnchorGrid() end
	end }

	-- attachDropdown 호환 API
	panel.attachDropdown = {
		SetSelected = function(_, val)
			local CDM_NAMES = {
				["DDingUI_Anchor_Cooldowns"] = "CDM: 쿨다운",
				["DDingUI_Anchor_Buffs"] = "CDM: 강화",
				["DDingUI_Anchor_Utility"] = "CDM: 보조",
				["ddingUI_Player"] = "UF: Player",
				["ddingUI_Target"] = "UF: Target",
				["ddingUI_Focus"] = "UF: Focus",
				["ddingUI_Pet"] = "UF: Pet",
			}
			if anchorFrameDropdown and anchorFrameDropdown.SetValue then
				anchorFrameDropdown:SetValue(val, CDM_NAMES[val] or val)
			end
		end,
	}

	-- Anchor Selection Button (CDM 동일: Select Anchor)
	local anchorSelectBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
	anchorSelectBtn:SetSize(210, 24)
	anchorSelectBtn:SetPoint("TOP", anchorFrameDropdown, "BOTTOM", 0, -6)

	local selR = accentFrom[1] * 0.3
	local selG = accentFrom[2] * 0.3
	local selB = accentFrom[3] * 0.3

	anchorSelectBtn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
	anchorSelectBtn:SetBackdropColor(selR, selG, selB, 0.8)
	anchorSelectBtn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.5)

	local ancSelText = anchorSelectBtn:CreateFontString(nil, "OVERLAY")
	ancSelText:SetFont(fontPath, 9, "OUTLINE")
	ancSelText:SetPoint("CENTER")
	ancSelText:SetText("Select Anchor")

	anchorSelectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(math.min(selR+0.12,1), math.min(selG+0.12,1), math.min(selB+0.12,1), 0.95) end)
	anchorSelectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(selR, selG, selB, 0.8) end)
	panel.anchorSelectBtn = anchorSelectBtn

	-- UF 프레임 선택 (CDM과 동일 패턴)
	local function UF_StartFramePicker(callback)
		if ns._framePickerActive then return end
		ns._framePickerActive = true
		panel:EnableKeyboard(false)

		local knownFrames = {
			"ddingUI_Player", "ddingUI_Target", "ddingUI_TargetTarget",
			"ddingUI_Focus", "ddingUI_FocusTarget", "ddingUI_Pet",
			"ddingUI_Boss1", "ddingUI_Boss2", "ddingUI_Boss3",
		}
		local cdmProxies = {
			"DDingUI_Anchor_Cooldowns", "DDingUI_Anchor_Buffs", "DDingUI_Anchor_Utility",
		}

		local function IsMouseOverFrame(frame)
			if not frame or not frame:IsShown() then return false end
			if frame.GetAlpha and frame:GetAlpha() < 0.01 then return false end
			local scale = frame:GetEffectiveScale()
			local x, y = GetCursorPosition()
			x, y = x / scale, y / scale
			local left, bottom, width, height = frame:GetRect()
			if not left then return false end
			return x >= left and x <= left + width and y >= bottom and y <= bottom + height
		end

		local function GetFrameUnderMouse(excludeFrame)
			for _, frameName in ipairs(knownFrames) do
				local frame = _G[frameName]
				if frame and frame ~= excludeFrame and IsMouseOverFrame(frame) then
					return frame
				end
			end
			for _, frameName in ipairs(cdmProxies) do
				local frame = _G[frameName]
				if frame and IsMouseOverFrame(frame) then
					return frame
				end
			end
			for _, m in ipairs(movers) do
				if m and m ~= excludeFrame and m._frame and IsMouseOverFrame(m._frame) then
					return m._frame
				end
			end
			return nil
		end

		local pickerFrame = CreateFrame("Frame", "DDingUI_UF_FramePicker", UIParent)
		pickerFrame:SetFrameStrata("TOOLTIP")
		pickerFrame:SetAllPoints(UIParent)
		pickerFrame:EnableMouse(false)

		local hint = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		hint:SetPoint("TOP", pickerFrame, "TOP", 0, -50)
		hint:SetText("프레임을 클릭하세요 (ESC로 취소)")
		hint:SetTextColor(1, 1, 0, 1)

		local highlight = CreateFrame("Frame", nil, pickerFrame, "BackdropTemplate")
		highlight:SetBackdrop({ edgeFile = SOLID, edgeSize = 2 })
		highlight:SetBackdropBorderColor(0, 1, 0, 0.8)
		highlight:Hide()

		local nameLabel = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		nameLabel:SetPoint("BOTTOM", highlight, "TOP", 0, 5)
		nameLabel:SetTextColor(0, 1, 0, 1)

		local currentFrame = nil
		local clickHandled = false

		local function Cleanup()
			clickHandled = true
			if pickerFrame then pickerFrame:Hide(); pickerFrame:SetScript("OnUpdate", nil) end
			panel:EnableKeyboard(true)
			C_Timer.After(0.2, function() ns._framePickerActive = nil end)
		end

		pickerFrame:SetScript("OnUpdate", function()
			local focusFrame = GetFrameUnderMouse(pickerFrame)
			if focusFrame and focusFrame:GetName() then
				currentFrame = focusFrame
				highlight:ClearAllPoints()
				highlight:SetPoint("TOPLEFT", focusFrame, "TOPLEFT", -2, 2)
				highlight:SetPoint("BOTTOMRIGHT", focusFrame, "BOTTOMRIGHT", 2, -2)
				highlight:Show()
				nameLabel:SetText(focusFrame:GetName())
			else
				currentFrame = nil
				highlight:Hide()
				nameLabel:SetText("")
			end
			if IsKeyDown("ESCAPE") then Cleanup(); return end
			if clickHandled then return end
			if IsMouseButtonDown("LeftButton") then
				if currentFrame then
					local frameName = currentFrame:GetName()
					if frameName and callback then
						clickHandled = true
						Cleanup()
						callback(frameName)
						ns.Print("프레임 선택: |cFFFFFF00" .. frameName .. "|r")
						return
					end
				end
				Cleanup()
			elseif IsMouseButtonDown("RightButton") then
				Cleanup()
			end
		end)
	end

	anchorSelectBtn:SetScript("OnClick", function()
		if not selectedMover then return end
		local unitKey = selectedMover._unitKey
		if not unitKey then return end

		local function OnFramePicked(frameName)
			if not frameName or not ns.db[unitKey] then return end
			ns.db[unitKey].attachTo = frameName
			if not ns.db[unitKey].selfPoint then ns.db[unitKey].selfPoint = "CENTER" end
			if not ns.db[unitKey].anchorPoint then ns.db[unitKey].anchorPoint = "CENTER" end
			ns.db[unitKey].position = { 0, 0 }
			if panel.attachDropdown and panel.attachDropdown.SetSelected then
				panel.attachDropdown:SetSelected(frameName)
			end
			if ns.Update and ns.Update.RefreshUnit then
				ns.Update:RefreshUnit(unitKey)
			end
		end

		local DDingUI = _G.DDingUI_Addon or _G.DDingUI
		if DDingUI and DDingUI.StartFramePicker then
			DDingUI:StartFramePicker(OnFramePicked)
		else
			UF_StartFramePicker(OnFramePicked)
		end
	end)

	-- ==========================================
	-- X/Y 좌표 입력 (CDM 동일)
	-- ==========================================
	local xLabel = panel:CreateFontString(nil, "OVERLAY")
	xLabel:SetFont(fontPath, 10, "OUTLINE")
	xLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, cursorY)
	xLabel:SetText("X:")

	local xEditBox = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
	xEditBox:SetPoint("LEFT", xLabel, "RIGHT", 4, 0)
	xEditBox:SetSize(60, 20)
	xEditBox:SetFont(fontPath, 10, "OUTLINE")
	xEditBox:SetJustifyH("CENTER")
	xEditBox:SetAutoFocus(false)
	xEditBox:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
	xEditBox:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	xEditBox:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)
	xEditBox:SetTextColor(1, 1, 1)
	xEditBox:SetMaxLetters(7)

	xEditBox:SetScript("OnEditFocusGained", function(self)
		panel._editing = true
		self:SetBackdropBorderColor(accentFrom[1], accentFrom[2], accentFrom[3], 1)
	end)
	xEditBox:SetScript("OnEditFocusLost", function(self)
		panel._editing = false
		self:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)
	end)
	panel.xBox = xEditBox

	local yLabel = panel:CreateFontString(nil, "OVERLAY")
	yLabel:SetFont(fontPath, 10, "OUTLINE")
	yLabel:SetPoint("LEFT", xEditBox, "RIGHT", 15, 0)
	yLabel:SetText("Y:")

	local yEditBox = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
	yEditBox:SetPoint("LEFT", yLabel, "RIGHT", 4, 0)
	yEditBox:SetSize(60, 20)
	yEditBox:SetFont(fontPath, 10, "OUTLINE")
	yEditBox:SetJustifyH("CENTER")
	yEditBox:SetAutoFocus(false)
	yEditBox:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
	yEditBox:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	yEditBox:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)
	yEditBox:SetTextColor(1, 1, 1)
	yEditBox:SetMaxLetters(7)

	yEditBox:SetScript("OnEditFocusGained", function(self)
		panel._editing = true
		self:SetBackdropBorderColor(accentFrom[1], accentFrom[2], accentFrom[3], 1)
	end)
	yEditBox:SetScript("OnEditFocusLost", function(self)
		panel._editing = false
		self:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)
	end)
	panel.yBox = yEditBox

	local function ApplyEditBoxCoords()
		if not selectedMover then return end
		local xVal = tonumber(panel.xBox:GetText())
		local yVal = tonumber(panel.yBox:GetText())
		if not xVal or not yVal then return end
		local point = select(1, selectedMover:GetPoint(1)) or "CENTER"
		ApplyMoverVisual(selectedMover, point, xVal, yVal)
		ReanchorToAttachTo(selectedMover)
		Mover:UpdateNudgeCoords()
		panel.xBox:ClearFocus()
		panel.yBox:ClearFocus()
	end

	for _, box in ipairs({ panel.xBox, panel.yBox }) do
		box:SetScript("OnEnterPressed", ApplyEditBoxCoords)
		box:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			Mover:UpdateNudgeCoords()
		end)
		box:SetScript("OnTabPressed", function(self)
			if self == panel.xBox then panel.yBox:SetFocus() else panel.xBox:SetFocus() end
		end)
	end
	cursorY = cursorY - 24

	-- ==========================================
	-- 방향키 버튼 (CDM 동일)
	-- ==========================================
	local ARROW_SZ = 28
	local nudgeBtnBg = SL and SL.Colors.bg.hover or {0.15, 0.15, 0.15, 0.80}

	local function CreateNudgeBtn(label, dx, dy, anchorPoint_btn, anchorTo_btn, anchorRelPoint_btn, ox, oy)
		local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
		btn:SetSize(ARROW_SZ, ARROW_SZ)
		btn:SetPoint(anchorPoint_btn, anchorTo_btn, anchorRelPoint_btn, ox, oy)
		btn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
		btn:SetBackdropColor(nudgeBtnBg[1], nudgeBtnBg[2], nudgeBtnBg[3], nudgeBtnBg[4] or 0.8)
		btn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.5)

		local text = btn:CreateFontString(nil, "OVERLAY")
		text:SetFont(fontPath, 12, "OUTLINE")
		text:SetPoint("CENTER")
		text:SetText(label)

		btn:SetScript("OnClick", function()
			if not selectedMover then return end
			local mdb = GetMoverDB()
			local step = IsControlKeyDown() and 10 or (mdb.nudgeStep or 1)
			Mover:NudgeSelected(dx * step, dy * step)
		end)
		btn:SetScript("OnEnter", function()
			btn:SetBackdropColor(accentFrom[1]*0.5, accentFrom[2]*0.5, accentFrom[3]*0.5, 0.9)
		end)
		btn:SetScript("OnLeave", function()
			btn:SetBackdropColor(nudgeBtnBg[1], nudgeBtnBg[2], nudgeBtnBg[3], nudgeBtnBg[4] or 0.8)
		end)
		return btn
	end

	panel.upBtn    = CreateNudgeBtn("^", 0, 1,  "TOP",  panel, "TOP", 0, cursorY)
	cursorY = cursorY - ARROW_SZ - 2
	panel.leftBtn  = CreateNudgeBtn("<", -1, 0, "TOP",  panel, "TOP", -(ARROW_SZ/2 + 2), cursorY)
	panel.rightBtn = CreateNudgeBtn(">", 1, 0,  "LEFT", panel.leftBtn, "RIGHT", 4, 0)
	cursorY = cursorY - ARROW_SZ - 2
	panel.downBtn  = CreateNudgeBtn("v", 0, -1, "TOP",  panel, "TOP", 0, cursorY)
	cursorY = cursorY - ARROW_SZ - SECTION_PAD

	-- ==========================================
	-- 프레임 선택 / 연결 대상 드롭다운 옮겨짐 (CDM 동일)
	-- ==========================================
	frameSelectDropdown:ClearAllPoints()
	frameSelectDropdown:SetPoint("TOP", panel, "TOP", 0, cursorY)
	cursorY = cursorY - 40

	anchorFrameDropdown:ClearAllPoints()
	anchorFrameDropdown:SetPoint("TOP", panel, "TOP", 0, cursorY)
	cursorY = cursorY - 40

	anchorSelectBtn:ClearAllPoints()
	anchorSelectBtn:SetPoint("TOP", panel, "TOP", 0, cursorY)
	cursorY = cursorY - 24 - SECTION_PAD

	-- ==========================================
	-- 설정 섹션 (CDM 동일 패턴)
	-- ==========================================
	local separator = panel:CreateTexture(nil, "ARTWORK")
	separator:SetSize(210, 1)
	separator:SetPoint("TOP", panel, "TOP", 0, cursorY)
	separator:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 0.4)
	cursorY = cursorY - PAD

	local settingsLabel = panel:CreateFontString(nil, "OVERLAY")
	settingsLabel:SetFont(fontPath, 10, "OUTLINE")
	settingsLabel:SetPoint("TOP", panel, "TOP", 0, cursorY)
	settingsLabel:SetText("Settings")
	settingsLabel:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3], 1)
	cursorY = cursorY - 16

	-- Helper: 체크박스 (CDM 동일 스타일)
	local function CreateCheckbox(labelStr, settingKey, onClick, indent)
		local container = CreateFrame("Frame", nil, panel)
		container:SetSize(120, 18)
		container:SetPoint("TOPLEFT", panel, "TOPLEFT", indent or 14, cursorY)

		local box = CreateFrame("Button", nil, container, "BackdropTemplate")
		box:SetSize(14, 14)
		box:SetPoint("LEFT", 0, 0)
		box:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
		box:SetBackdropColor(unpack(ddInputBg))
		box:SetBackdropBorderColor(unpack(ddBorder))

		local fill = box:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetPoint("BOTTOMRIGHT", -1, 1)
		fill:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 1)

		local mdb = GetMoverDB()
		container._checked = mdb[settingKey] ~= false
		if container._checked then fill:Show() else fill:Hide() end

		local text = container:CreateFontString(nil, "OVERLAY")
		text:SetFont(fontPath, 9, "OUTLINE")
		text:SetPoint("LEFT", box, "RIGHT", 4, 0)
		text:SetText(labelStr)
		container.label = text

		function container:SetChecked(val) self._checked = val; if val then fill:Show() else fill:Hide() end end
		function container:GetChecked() return self._checked end

		box:SetScript("OnClick", function()
			container._checked = not container._checked
			if container._checked then fill:Show() else fill:Hide() end
			mdb[settingKey] = container._checked
			if onClick then onClick(container._checked) end
		end)

		cursorY = cursorY - 20
		return container
	end

	-- Grid 체크박스
	panel.gridCheckbox = CreateCheckbox("Show Grid", "gridEnabled", function(checked)
		if checked then
			local grid = CreateGridOverlay()
			if grid then FadeIn(grid) end
		elseif gridFrame then
			FadeOut(gridFrame)
		end
	end)

	-- Snap 체크박스
	panel.snapCheckbox = CreateCheckbox("Enable Snap", "snapEnabled")
	panel.snapGridCheckbox = CreateCheckbox("Grid", "snapToGrid", nil, 30)
	panel.snapFramesCheckbox = CreateCheckbox("Frames", "snapToFrames", nil, 30)
	panel.snapCenterCheckbox = CreateCheckbox("Center", "snapToCenter", nil, 30)

	cursorY = cursorY - PAD

	-- Sliders (CDM 동일: CreateFlatSlider)
	local function CreateFlatSlider(parent, labelText, minV, maxV, stepV, defaultV, xOff, yOff, onChange)
		local container = CreateFrame("Frame", nil, parent)
		container:SetSize(210, 40)
		container:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)

		local lbl = container:CreateFontString(nil, "OVERLAY")
		lbl:SetFont(fontPath, 9, "OUTLINE")
		lbl:SetPoint("TOPLEFT", 0, 0)
		lbl:SetText(labelText)
		container.label = lbl

		local track = CreateFrame("Frame", nil, container)
		track:SetHeight(4)
		track:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)
		track:SetPoint("RIGHT", container, "RIGHT", -4, 0)
		local trackBg = track:CreateTexture(nil, "BACKGROUND")
		trackBg:SetAllPoints()
		trackBg:SetColorTexture(ddInputBg[1], ddInputBg[2], ddInputBg[3], ddInputBg[4] or 0.8)

		local slider = CreateFrame("Slider", nil, container)
		slider:SetPoint("TOPLEFT", track)
		slider:SetPoint("BOTTOMRIGHT", track)
		slider:SetMinMaxValues(minV, maxV)
		slider:SetValueStep(stepV)
		slider:SetObeyStepOnDrag(true)
		slider:SetValue(math_max(minV, math.min(maxV, defaultV)))
		slider:SetOrientation("HORIZONTAL")
		slider:EnableMouseWheel(true)

		local fillBar = slider:CreateTexture(nil, "ARTWORK")
		fillBar:SetHeight(4)
		fillBar:SetPoint("LEFT", track, "LEFT", 0, 0)
		fillBar:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 1)
		local function UpdateFill()
			local pct = (slider:GetValue() - minV) / math_max(1, maxV - minV)
			fillBar:SetWidth(math_max(1, pct * track:GetWidth()))
		end

		local thumb = slider:CreateTexture(nil, "OVERLAY")
		thumb:SetSize(8, 8)
		thumb:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 1)
		slider:SetThumbTexture(thumb)

		slider:SetScript("OnValueChanged", function(self, value)
			UpdateFill()
			if onChange then onChange(value) end
		end)
		slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * stepV) end)
		C_Timer.After(0, UpdateFill)

		container.slider = slider
		return container
	end

	local mdb = GetMoverDB()

	-- Grid Size Slider
	local gridSliderContainer = CreateFlatSlider(panel,
		"격자: " .. (mdb.gridSize or 16), 4, 64, 2, mdb.gridSize or 16,
		14, cursorY,
		function(value)
			local mdb2 = GetMoverDB()
			mdb2.gridSize = math_floor(value + 0.5)
			if gridSliderContainer then gridSliderContainer.label:SetText("격자: " .. mdb2.gridSize) end
			if gridFrame and gridFrame:IsShown() and gridFrame.RefreshLines then gridFrame:RefreshLines() end
		end)
	panel._gridSlider = gridSliderContainer.slider
	cursorY = cursorY - 44

	-- Snap Threshold Slider
	local snapSliderContainer = CreateFlatSlider(panel,
		"스냅: " .. (mdb.snapThreshold or 12), 1, 30, 1, mdb.snapThreshold or 12,
		14, cursorY,
		function(value)
			local mdb2 = GetMoverDB()
			mdb2.snapThreshold = math_floor(value + 0.5)
			if snapSliderContainer then snapSliderContainer.label:SetText("스냅: " .. mdb2.snapThreshold) end
		end)
	cursorY = cursorY - 44

	-- Raid Preview Slider
	local raidSliderContainer = CreateFlatSlider(panel,
		"레이드 " .. (mdb.previewRaidCount or 20), 10, 30, 5, mdb.previewRaidCount or 20,
		14, cursorY,
		function(value)
			local mdb2 = GetMoverDB()
			mdb2.previewRaidCount = math_floor(value + 0.5)
			if raidSliderContainer then raidSliderContainer.label:SetText("레이드 " .. mdb2.previewRaidCount) end
			local TM = ns.GroupFrames and ns.GroupFrames.TestMode
			if TM and TM.active then TM:RefreshRaid() end
		end)
	cursorY = cursorY - 44

	-- ==========================================
	-- Button Row (CDM 동일: Reset | Undo | Redo | Done)
	-- ==========================================
	local btnWidth = 50
	local btnSpacing = 4
	local totalWidth = (btnWidth * 4) + (btnSpacing * 3)
	local startX = -totalWidth / 2

	local function CreateBottomBtn(label, xOff, bgR, bgG, bgB, onClick)
		local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
		btn:SetSize(btnWidth, 22)
		btn:SetPoint("BOTTOM", panel, "BOTTOM", xOff, 12)
		btn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
		btn:SetBackdropColor(bgR, bgG, bgB, 0.8)
		btn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.5)

		local text = btn:CreateFontString(nil, "OVERLAY")
		text:SetFont(fontPath, 10, "OUTLINE")
		text:SetPoint("CENTER")
		text:SetText(label)
		btn.text = text

		btn:SetScript("OnClick", onClick)
		btn:SetScript("OnEnter", function() btn:SetBackdropColor(math.min(bgR+0.12,1), math.min(bgG+0.12,1), math.min(bgB+0.12,1), 0.95) end)
		btn:SetScript("OnLeave", function() btn:SetBackdropColor(bgR, bgG, bgB, 0.8) end)
		return btn
	end

	panel.resetBtn = CreateBottomBtn("Reset", startX + btnWidth/2, 0.3, 0.15, 0.15, function()
		if not selectedMover then return end
		local pt, _, _, ox, oy = selectedMover:GetPoint(1)
		if pt then
			if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
			undoStack[#undoStack + 1] = { mover = selectedMover, point = pt, x = ox or 0, y = oy or 0 }
			wipe(redoStack)
		end
		Mover:ResetMover(selectedMover)
		if panel.UpdateUndoRedoBtns then panel:UpdateUndoRedoBtns() end
	end)

	panel.undoBtn = CreateBottomBtn("Undo", startX + btnWidth + btnSpacing + btnWidth/2, nudgeBtnBg[1], nudgeBtnBg[2], nudgeBtnBg[3], function() Mover:Undo() end)
	panel.undoBtn._bgR, panel.undoBtn._bgG, panel.undoBtn._bgB = nudgeBtnBg[1], nudgeBtnBg[2], nudgeBtnBg[3]
	panel.undoBtn:Disable()

	panel.redoBtn = CreateBottomBtn("Redo", startX + (btnWidth + btnSpacing) * 2 + btnWidth/2, nudgeBtnBg[1], nudgeBtnBg[2], nudgeBtnBg[3], function() Mover:Redo() end)
	panel.redoBtn._bgR, panel.redoBtn._bgG, panel.redoBtn._bgB = nudgeBtnBg[1], nudgeBtnBg[2], nudgeBtnBg[3]
	panel.redoBtn:Disable()

	local doneR = accentFrom[1] * 0.35
	local doneG = accentFrom[2] * 0.35
	local doneB = accentFrom[3] * 0.35
	panel.doneBtn = CreateBottomBtn("Done", startX + (btnWidth + btnSpacing) * 3 + btnWidth/2, doneR, doneG, doneB, function()
		Mover:LockAll()
	end)

	-- Undo/Redo 상태 업데이트 (CDM 동일)
	function panel:UpdateUndoRedoBtns()
		if self.undoBtn then
			if #undoStack > 0 then
				self.undoBtn:Enable()
				self.undoBtn:SetBackdropColor(self.undoBtn._bgR or 0.15, self.undoBtn._bgG or 0.15, self.undoBtn._bgB or 0.15, 0.8)
			else
				self.undoBtn:Disable()
				self.undoBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
			end
		end
		if self.redoBtn then
			if #redoStack > 0 then
				self.redoBtn:Enable()
				self.redoBtn:SetBackdropColor(self.redoBtn._bgR or 0.15, self.redoBtn._bgG or 0.15, self.redoBtn._bgB or 0.15, 0.8)
			else
				self.redoBtn:Disable()
				self.redoBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
			end
		end
	end
	panel:UpdateUndoRedoBtns()

	-- UpdateSelection (CDM 동일)
	function panel:UpdateSelection()
		if selectedMover then
			self.selectedText:SetText(selectedMover._name or GetMoverDBKey(selectedMover) or "Unknown")
			if self.frameSelectDropdown and self.frameSelectDropdown.SetValue then
				self.frameSelectDropdown:SetValue(GetMoverDBKey(selectedMover), selectedMover._name or GetMoverDBKey(selectedMover))
			end
			self:UpdateInfo()
		else
			self.selectedText:SetText("|cff888888프레임을 클릭하세요|r")
			self.anchorLabel:SetText("-- → --")
			self.anchorFrameLabel:SetText("@ --")
			if self.xBox then self.xBox:SetText("") end
			if self.yBox then self.yBox:SetText("") end
		end
	end

	-- UpdateInfo (CDM 동일)
	function panel:UpdateInfo()
		if not selectedMover then return end
		local pt, ancFrame, relPt, x, y = selectedMover:GetPoint(1)
		if not ancFrame then ancFrame = UIParent end
		x = x or 0
		y = y or 0

		if self.xBox and not self._editing then self.xBox:SetText(tostring(math_floor(x + 0.5))) end
		if self.yBox and not self._editing then self.yBox:SetText(tostring(math_floor(y + 0.5))) end

		-- [FIX] DB 기준 selfPoint/anchorPoint/attachTo 표시 (편집모드 내부 좌표 대신)
		local unitKey = selectedMover._unitKey
		local unitDB = unitKey and ns.db[unitKey]
		local displaySelfPoint, displayAnchorPoint, anchorName
		if unitDB then
			displaySelfPoint = unitDB.selfPoint or pt or "CENTER"
			displayAnchorPoint = unitDB.anchorPoint or relPt or pt or "CENTER"
			local attachTo = unitDB.attachTo
			if attachTo and attachTo ~= "" and attachTo ~= "UIParent" then
				anchorName = attachTo
			else
				anchorName = (ancFrame and ancFrame:GetName()) or "UIParent"
			end
		else
			displaySelfPoint = pt or "CENTER"
			displayAnchorPoint = relPt or pt or "CENTER"
			anchorName = (ancFrame and ancFrame:GetName()) or "UIParent"
		end

		self.anchorLabel:SetText(displaySelfPoint .. " → " .. displayAnchorPoint)
		self.anchorFrameLabel:SetText("@ " .. anchorName)

		if self._anchorSizeText and selectedMover then
			local mW, mH = selectedMover:GetSize()
			if mW and mH then
				self._anchorSizeText:SetText(string.format("%d x %d", math_floor(mW + 0.5), math_floor(mH + 0.5)))
			end
		end

		-- 앙커 프레임 드롭다운 목록 동적 갱신
		do
			local afItems = { {text="UIParent", value="UIParent"} }
			local CDM_PROXIES_DD = {
				{ name = "DDingUI_Anchor_Cooldowns", label = "CDM: 쿨다운" },
				{ name = "DDingUI_Anchor_Buffs",     label = "CDM: 강화" },
				{ name = "DDingUI_Anchor_Utility",   label = "CDM: 보조" },
			}
			for _, proxy in ipairs(CDM_PROXIES_DD) do
				if _G[proxy.name] then
					afItems[#afItems + 1] = { text = proxy.label, value = proxy.name }
				end
			end
			local UF_FRAMES_DD = {
				{ name = "ddingUI_Player", label = "UF: Player" },
				{ name = "ddingUI_Target", label = "UF: Target" },
				{ name = "ddingUI_Focus",  label = "UF: Focus" },
				{ name = "ddingUI_Pet",    label = "UF: Pet" },
			}
			for _, uf in ipairs(UF_FRAMES_DD) do
				if _G[uf.name] then
					afItems[#afItems + 1] = { text = uf.label, value = uf.name }
				end
			end
			if self.anchorFrameDropdown and self.anchorFrameDropdown.SetItems then
				self.anchorFrameDropdown:SetItems(afItems)
			end
			if self.anchorFrameDropdown and self.anchorFrameDropdown.SetValue then
				local CDM_NAMES = {
					["DDingUI_Anchor_Cooldowns"] = "CDM: 쿨다운",
					["DDingUI_Anchor_Buffs"] = "CDM: 강화",
					["DDingUI_Anchor_Utility"] = "CDM: 보조",
					["ddingUI_Player"] = "UF: Player",
					["ddingUI_Target"] = "UF: Target",
					["ddingUI_Focus"] = "UF: Focus",
					["ddingUI_Pet"] = "UF: Pet",
				}
				self.anchorFrameDropdown:SetValue(anchorName, CDM_NAMES[anchorName] or anchorName)
			end
		end
	end

	-- 키보드 넛지 (CDM 동일)
	panel:EnableKeyboard(true)
	panel:SetPropagateKeyboardInput(true)
	panel:SetScript("OnKeyDown", function(self, key)
		if self._editing then
			self:SetPropagateKeyboardInput(true)
			return
		end
		if not selectedMover then
			self:SetPropagateKeyboardInput(true)
			return
		end

		local mdb2 = GetMoverDB()
		local step = IsControlKeyDown() and 10 or (mdb2.nudgeStep or 1)

		if key == "UP" then
			self:SetPropagateKeyboardInput(false)
			Mover:NudgeSelected(0, step)
		elseif key == "DOWN" then
			self:SetPropagateKeyboardInput(false)
			Mover:NudgeSelected(0, -step)
		elseif key == "LEFT" then
			self:SetPropagateKeyboardInput(false)
			Mover:NudgeSelected(-step, 0)
		elseif key == "RIGHT" then
			self:SetPropagateKeyboardInput(false)
			Mover:NudgeSelected(step, 0)
		elseif key == "Z" and IsControlKeyDown() then
			self:SetPropagateKeyboardInput(false)
			Mover:Undo()
		elseif key == "Y" and IsControlKeyDown() then
			self:SetPropagateKeyboardInput(false)
			Mover:Redo()
		elseif key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			Mover:CancelEditMode()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	nudgePanel = panel
end

-----------------------------------------------
-- [CDM-P1] Undo/Redo 함수
-----------------------------------------------

function Mover:Undo()
	if #undoStack == 0 then return end
	local entry = table.remove(undoStack)
	if not entry.mover then return end

	-- 현재 위치를 Redo 스택에 저장
	local curPt, curAnc, curRel, curX, curY = entry.mover:GetPoint(1)
	if curPt then
		if #redoStack >= MAX_UNDO then table.remove(redoStack, 1) end
		redoStack[#redoStack + 1] = { mover = entry.mover, point = curPt, anchorFrame = curAnc, relPoint = curRel, x = curX or 0, y = curY or 0 }
	end

	-- 이전 위치로 복원
	ApplyMoverVisual(entry.mover, entry.point, entry.x, entry.y, entry.anchorFrame, entry.relPoint)
	SelectMover(entry.mover)
	self:UpdateNudgeCoords()
	if nudgePanel and nudgePanel.UpdateUndoRedoBtns then nudgePanel:UpdateUndoRedoBtns() end
	if nudgePanel and nudgePanel.anchorDropdown then nudgePanel.anchorDropdown:SetSelected(entry.point) end
end

function Mover:Redo()
	if #redoStack == 0 then return end
	local entry = table.remove(redoStack)
	if not entry.mover then return end

	-- 현재 위치를 Undo 스택에 저장
	local curPt, curAnc, curRel, curX, curY = entry.mover:GetPoint(1)
	if curPt then
		if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
		undoStack[#undoStack + 1] = { mover = entry.mover, point = curPt, anchorFrame = curAnc, relPoint = curRel, x = curX or 0, y = curY or 0 }
	end

	-- Redo 위치로 이동
	ApplyMoverVisual(entry.mover, entry.point, entry.x, entry.y, entry.anchorFrame, entry.relPoint)
	SelectMover(entry.mover)
	self:UpdateNudgeCoords()
	if nudgePanel and nudgePanel.UpdateUndoRedoBtns then nudgePanel:UpdateUndoRedoBtns() end
	if nudgePanel and nudgePanel.anchorDropdown then nudgePanel.anchorDropdown:SetSelected(entry.point) end
end

-----------------------------------------------
-- [12.0.1] 넛지 이동 실행
-----------------------------------------------

function Mover:NudgeSelected(dx, dy)
	if not selectedMover then return end

	-- [EDITMODE] 다중 선택 시 모든 선택된 무버를 함께 이동
	local targets = {}
	if next(selectedMovers) then
		for m, _ in pairs(selectedMovers) do
			targets[#targets + 1] = m
		end
	else
		targets[1] = selectedMover
	end

	-- [EDITMODE] 넛지 전 위치를 언두 스택에 저장 (주 선택 무버만)
	local mainPt, mainAnc, mainRel, mainX, mainY = selectedMover:GetPoint(1)
	if mainPt then
		if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
		undoStack[#undoStack + 1] = { mover = selectedMover, point = mainPt, anchorFrame = mainAnc, relPoint = mainRel, x = mainX or 0, y = mainY or 0 }
		wipe(redoStack) -- [CDM-P1] 새 동작 시 리두 스택 초기화
		if nudgePanel and nudgePanel.UpdateUndoRedoBtns then nudgePanel:UpdateUndoRedoBtns() end
	end

	for _, mover in ipairs(targets) do
		local point, _, _, oX, oY = mover:GetPoint(1)
		if point then
			local newX = math_floor((oX or 0) + dx + 0.5) -- [MOVER] 정수 반올림
			local newY = math_floor((oY or 0) + dy + 0.5)
			ApplyMoverVisual(mover, point, newX, newY) -- [MOVER] 시각적 이동만
		end
	end
	self:UpdateNudgeCoords()
end

function Mover:UpdateNudgeCoords()
	if not nudgePanel or not selectedMover then return end
	local pt, _, _, oX, oY = selectedMover:GetPoint(1)
	local x = math_floor((oX or 0) + 0.5)
	local y = math_floor((oY or 0) + 0.5)
	nudgePanel.coords:SetText(x .. ", " .. y)
	-- EditBox 동기화
	if nudgePanel.xBox and not nudgePanel._editing then
		nudgePanel.xBox:SetText(tostring(x))
	end
	if nudgePanel.yBox and not nudgePanel._editing then
		nudgePanel.yBox:SetText(tostring(y))
	end
	-- [ANCHOR-GRID] 9-point 그리드 동기화 (selfPoint + anchorPoint)
	if selectedMover and selectedMover._unitKey and ns.db[selectedMover._unitKey] then
		local unitDB = ns.db[selectedMover._unitKey]
		if nudgePanel._selfPointCurrent ~= nil then
			nudgePanel._selfPointCurrent = unitDB.selfPoint or pt or "CENTER"
		end
		if nudgePanel._anchorPointCurrent ~= nil then
			nudgePanel._anchorPointCurrent = unitDB.anchorPoint or pt or "CENTER"
		end
	end
	if nudgePanel._refreshAnchorGrid then
		nudgePanel._refreshAnchorGrid()
	end
	-- [ANCHOR-GRID] 크기 텍스트 업데이트
	if nudgePanel._anchorSizeText and selectedMover then
		local mW, mH = selectedMover:GetSize()
		if mW and mH then
			nudgePanel._anchorSizeText:SetText(string.format("%d x %d", math_floor(mW + 0.5), math_floor(mH + 0.5)))
		end
	end
	-- [FIX] 앵커 정보 텍스트 동기화 (selfPoint → anchorPoint, @ frame)
	if nudgePanel.UpdateInfo then
		nudgePanel:UpdateInfo()
	end
end

-----------------------------------------------
-- [12.0.1] 개별 무버 리셋
-----------------------------------------------

function Mover:ResetMover(mover)
	if not mover then return end
	local unitKey = mover._unitKey
	if not unitKey then return end

	-- [MOVER] movers 네임스페이스에서 삭제
	DeleteMoverFromDB(GetMoverDBKey(mover))

	-- 레거시 DB도 기본값으로 복원
	if mover._isCastbar then
		local defaultCB = ns.defaults[unitKey] and ns.defaults[unitKey].castbar and ns.defaults[unitKey].castbar.position
		if ns.db[unitKey] and ns.db[unitKey].castbar then
			ns.db[unitKey].castbar.position = defaultCB and CopyTable(defaultCB) or nil
		end
	elseif mover._isPowerBar then
		local unitDB = ns.db[unitKey]
		if unitDB and unitDB.widgets and unitDB.widgets.powerBar then
			local defaults = ns.defaults[unitKey]
			local defPos = defaults and defaults.widgets and defaults.widgets.powerBar and defaults.widgets.powerBar.detachedPosition
			unitDB.widgets.powerBar.detachedPosition = defPos and CopyTable(defPos) or nil
		end
	else
		local defaultPos = ns.defaults[unitKey] and ns.defaults[unitKey].position
		if ns.db[unitKey] then
			ns.db[unitKey].position = defaultPos and CopyTable(defaultPos) or nil
		end
	end

	-- 기본 위치로 이동
	local newPos
	if mover._isCastbar then
		newPos = ns.db[unitKey] and ns.db[unitKey].castbar and ns.db[unitKey].castbar.position
	elseif mover._isPowerBar then
		local unitDB = ns.db[unitKey]
		local dp = unitDB and unitDB.widgets and unitDB.widgets.powerBar and unitDB.widgets.powerBar.detachedPosition
		if dp then
			newPos = { dp.point, "UIParent", dp.relativePoint or dp.point, dp.offsetX or 0, dp.offsetY or 0 }
		end
	else
		newPos = ns.db[unitKey] and ns.db[unitKey].position
	end

	if newPos then
		local pt, rel, relPt, px, py = ResolvePosition(newPos, ns.db[unitKey])
		if pt then
			ApplyMoverVisual(mover, pt, px, py) -- [MOVER] 시각적 이동
		end
	else
		if mover._frame then
			mover:ClearAllPoints()
			mover:SetPoint("TOPLEFT", mover._frame, "TOPLEFT", 0, 0)
		end
	end

	self:UpdateNudgeCoords()
	ns.Print("|cff00ccff" .. (mover._name or unitKey) .. "|r 위치 초기화")
end
