--[[
	ddingUI UnitFrames
	Modules/Mover.lua - 편집모드 프레임 이동 + 그리드 스냅
	Cell/Cell_UnitFrames 패턴 참고: 색상 코딩, CalcPoint 자동 앵커, Fade 애니메이션
	[12.0.1] ElvUI 스타일: 넛지 패널, 프레임간 스냅, 완료 버튼
]]

local _, ns = ...

local Mover = {}
ns.Mover = Mover

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

	local point, relativeTo, _, oX, oY = mover:GetPoint(1)
	if not point then return end

	-- [FIX] UIParent에 앵커되지 않은 무버는 저장 스킵 (초기 상태=미이동)
	-- 초기: SetPoint("TOPLEFT", frame, ...) — frame 기준
	-- 이동 후: ApplyMoverVisual → SetPoint(point, UIParent, ...) — UIParent 기준
	if relativeTo ~= UIParent then return end

	local x = math_floor((oX or 0) + 0.5)
	local y = math_floor((oY or 0) + 0.5)
	local key = GetMoverDBKey(mover)

	-- movers 네임스페이스에 ElvUI 형식 문자열로 저장
	if not ns.db.movers then ns.db.movers = {} end
	ns.db.movers[key] = string.format("%s,UIParent,%s,%d,%d", point, point, x, y)

	-- 레거시 위치 동기화 (Spawn.lua 호환)
	local unitKey = mover._unitKey
	if not unitKey then return end

	if mover._isCastbar then
		if ns.db[unitKey] and ns.db[unitKey].castbar then
			ns.db[unitKey].castbar.position = { point, "UIParent", point, x, y }
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
		ns.db[unitKey].position = { point, "UIParent", point, x, y }
	end
end

-- [MOVER] movers 네임스페이스에서 로드 (문자열 파싱)
local function LoadMoverFromDB(name)
	if not ns.db or not ns.db.movers then return nil end
	local str = ns.db.movers[name]
	if not str or type(str) ~= "string" then return nil end

	local point, parent, relPoint, x, y = strsplit(",", str)
	x, y = tonumber(x), tonumber(y)
	if not point or not x or not y then return nil end
	return point, UIParent, relPoint or point, x, y
end

-- [MOVER] movers 네임스페이스에서 삭제
local function DeleteMoverFromDB(name)
	if ns.db and ns.db.movers then
		ns.db.movers[name] = nil
	end
end

-- [MOVER] 시각적 이동만 (DB 저장 없음 — 편집 중 사용)
local function ApplyMoverVisual(mover, point, x, y)
	if not mover then return end

	-- [EDITMODE-FIX] ClearAllPoints 전 사이즈 보존 (SetAllPoints 파생 사이즈 손실 방지)
	local mW, mH = mover:GetSize()

	mover:ClearAllPoints()
	mover:SetPoint(point, UIParent, point, x, y)

	-- [EDITMODE-FIX] 사이즈 복원
	if mW and mW > 0 and mH and mH > 0 then
		mover:SetSize(mW, mH)
	end

	-- 실제 프레임도 이동
	if mover._frame and not InCombatLockdown() then
		local fW, fH = mover._frame:GetSize() -- [EDITMODE-FIX] 프레임 사이즈도 보존
		mover._frame:ClearAllPoints()
		mover._frame:SetPoint(point, UIParent, point, x, y)
		if fW and fW > 0 and fH and fH > 0 then
			mover._frame:SetSize(fW, fH)
		end
	end

	-- [EDITMODE] simContainer 동기화 (그룹 + 개별 유닛 모두)
	-- TOPLEFT 정렬 사용 (mover와 container 크기가 다를 수 있으므로 화면 좌표 기준)
	if ns.simContainers and mover._unitKey then
		local sim = ns.simContainers[mover._unitKey]
		if sim and sim:IsShown() then
			local left, top = mover:GetLeft(), mover:GetTop()
			if left and top then
				sim:ClearAllPoints()
				sim:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			end
		end
	end

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
		local point, _, _, oX, oY = mover:GetPoint(1)
		if point then
			_positionSnapshot[GetMoverDBKey(mover)] = {
				point = point,
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
			ApplyMoverVisual(mover, snap.point, snap.x, snap.y)
		end
	end
	wipe(_positionSnapshot)
end

-- [MOVER] 기동 시 movers 네임스페이스에서 저장된 위치 적용
local function ApplyMoverPositions()
	if not ns.db or not ns.db.movers then return end
	for _, mover in ipairs(movers) do
		local key = GetMoverDBKey(mover)
		local point, _, relPoint, x, y = LoadMoverFromDB(key)
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
					-- DB도 업데이트
					ns.db.movers[key] = string.format("%s,UIParent,%s,%d,%d", point, point, x, y)
				end
			end
			ApplyMoverVisual(mover, point, x, y)
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
	local myRight = myLeft + myW
	local myTop = myBottom + myH
	local tRight = tLeft + tW
	local tTop = tBottom + tH

	-- 수평 겹침 비율 (상하 스냅 인정 조건)
	local hOverlap = math.min(myRight, tRight) - math.max(myLeft, tLeft)
	local minW = math.min(myW, tW)
	local hRatio = minW > 0 and (hOverlap / minW) or 0

	-- 수직 겹침 비율 (좌우 스냅 인정 조건)
	local vOverlap = math.min(myTop, tTop) - math.max(myBottom, tBottom)
	local minH = math.min(myH, tH)
	local vRatio = minH > 0 and (vOverlap / minH) or 0

	local bestDist = threshold
	local selfPt, anchorPt = nil, nil

	-- A가 B 위에 (A.bottom ≈ B.top) → selfPt=BOTTOM, anchorPt=TOP
	if hRatio > 0.3 then
		local dist = math_abs(myBottom - tTop)
		if dist < bestDist then
			bestDist = dist; selfPt = "BOTTOM"; anchorPt = "TOP"
		end
	end
	-- A가 B 아래에 (A.top ≈ B.bottom) → selfPt=TOP, anchorPt=BOTTOM
	if hRatio > 0.3 then
		local dist = math_abs(myTop - tBottom)
		if dist < bestDist then
			bestDist = dist; selfPt = "TOP"; anchorPt = "BOTTOM"
		end
	end
	-- A 왼쪽에 B (A.right ≈ B.left) → selfPt=RIGHT, anchorPt=LEFT
	if vRatio > 0.3 then
		local dist = math_abs(myRight - tLeft)
		if dist < bestDist then
			bestDist = dist; selfPt = "RIGHT"; anchorPt = "LEFT"
		end
	end
	-- A 오른쪽에 B (A.left ≈ B.right) → selfPt=LEFT, anchorPt=RIGHT
	if vRatio > 0.3 then
		local dist = math_abs(myLeft - tRight)
		if dist < bestDist then
			bestDist = dist; selfPt = "LEFT"; anchorPt = "RIGHT"
		end
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
			local forceCenter = self._isGroupMover or false
			local point, oX, oY = CalcPointFromAbsolute(absLeft, absBottom, w, h, forceCenter)
			self:ClearAllPoints()
			self:SetPoint(point, UIParent, point, oX, oY)
			if selfW and selfW > 0 and selfH and selfH > 0 then
				self:SetSize(selfW, selfH)
			end

			-- 즉시 위치 갱신 (Spawn.lua ApplyUnitPosition 호출)
			if ns.Update and ns.Update.RefreshUnit then
				ns.Update:RefreshUnit(unitKey)
			end

			-- 사용자 피드백
			ns.Print(string.format(
				"|cff00ff00%s|r → |cff80c0ff%s|r (|cffffcc00%s|r → |cffffcc00%s|r)",
				self._name or unitKey,
				snapTarget.label or targetName,
				snapSelfPt, snapAnchorPt
			))

			return point, oX, oY
		end
	end

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

	-- [SNAP-FIX] 3단계: 최종 절대 좌표에서 앵커 결정 (기본 UIParent 기준)
	local forceCenter = self._isGroupMover or false
	local point, oX, oY = CalcPointFromAbsolute(absLeft, absBottom, w, h, forceCenter)

	self:ClearAllPoints()
	self:SetPoint(point, UIParent, point, oX, oY)

	if selfW and selfW > 0 and selfH and selfH > 0 then
		self:SetSize(selfW, selfH)
	end

	-- [CDM-P2] 앵커 해제된 경우에도 position 동기화
	if unitDB and not self._isGroupMover and not self._isCastbar and not self._isPowerBar then
		local curAttach = unitDB.attachTo or "UIParent"
		if curAttach == "UIParent" then
			unitDB.position = { point, "UIParent", point, oX, oY }
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
					local left, top = s:GetLeft(), s:GetTop()
					if left and top then
						sim:ClearAllPoints()
						sim:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
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
		ApplyMoverVisual(self, point, snapX, snapY) -- [MOVER] 시각적 이동만 (Done 시 DB 저장)
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

	-- Boss frames — placeholder 지원
	do
		local bossDB = ns.db.boss
		if bossDB and bossDB.enabled ~= false then
			local frame = ns.frames.boss1
			if not frame then
				frame = _G["ddingUI_BossPlaceholder"] or CreateFrame("Frame", "ddingUI_BossPlaceholder", UIParent)
				local w = (bossDB.size and bossDB.size[1]) or 180
				local h = (bossDB.size and bossDB.size[2]) or 35
				frame:SetSize(w, h)
				frame:Hide()
			end
			local mover = CreateMoverOverlay(frame, "Boss", "boss")
			mover._unitKey = "boss"
			local pt, rel, relPt, px, py = ResolvePosition(bossDB.position, bossDB)
			if pt then
				mover:ClearAllPoints()
				mover:SetPoint(pt, rel, relPt, px, py)
			end
			table.insert(movers, mover)
		end
	end

	-- Arena frames — placeholder 지원
	do
		local arenaDB = ns.db.arena
		if arenaDB and arenaDB.enabled ~= false then
			local frame = ns.frames.arena1
			if not frame then
				frame = _G["ddingUI_ArenaPlaceholder"] or CreateFrame("Frame", "ddingUI_ArenaPlaceholder", UIParent)
				local w = (arenaDB.size and arenaDB.size[1]) or 180
				local h = (arenaDB.size and arenaDB.size[2]) or 35
				frame:SetSize(w, h)
				frame:Hide()
			end
			local mover = CreateMoverOverlay(frame, "Arena", "arena")
			mover._unitKey = "arena"
			local pt, rel, relPt, px, py = ResolvePosition(arenaDB.position, arenaDB)
			if pt then
				mover:ClearAllPoints()
				mover:SetPoint(pt, rel, relPt, px, py)
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
			ApplyMoverVisual(self, point, snapX, snapY) -- [MOVER] 시각적 이동만
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
				ApplyMoverVisual(self, point, snapX, snapY) -- [MOVER] 시각적 이동만
				Mover:UpdateNudgeCoords()
			end)
			table.insert(movers, mover)
		end
	end

	CreateGridOverlay()

	-- [MOVER] 저장된 movers 위치 적용 (ns.db.movers 네임스페이스)
	ApplyMoverPositions()

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
			-- [FIX] 실제 보이는 자식 프레임의 바운딩 박스에서 **위치만** 가져옴
			-- 크기는 항상 CalcPartyMoverSize/CalcRaidMoverSize 기준 (5명/최대그룹 고정)
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
						-- [FIX] 바운딩 박스에서 센터 위치만 추출, 크기는 5명/최대그룹 기준 고정
						local bbCX = (minL + maxR) / 2
						local bbCY = (minB + maxT) / 2
						-- w, h는 CalcPartyMoverSize/CalcRaidMoverSize에서 이미 계산됨
						local mW, mH = w or (maxR - minL), h or (maxT - minB)
						local absLeft = bbCX - mW / 2
						local absBottom = bbCY - mH / 2
						local pt, oX, oY = CalcPointFromAbsolute(absLeft, absBottom, mW, mH, true)
						mover:SetPoint(pt, UIParent, pt, oX, oY)
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

	ns.Print("|cffff8800편집 취소 — 이전 위치로 복원되었습니다.|r")
end

-----------------------------------------------
-- [12.0.1] 넛지 패널 (ElvUI 스타일 리모컨)
-- 타이틀 + X/Y EditBox + 방향키 + Grid/Reset/Done 버튼
-----------------------------------------------

function Mover:CreateNudgePanel()
	if nudgePanel then return end

	-- StyleLib 색상 참조 -- [12.0.1]
	local accent = SL and { SL.GetAccent("UnitFrames") } or { {0.30, 0.85, 0.45}, {0.12, 0.55, 0.20} }
	local accentFrom = accent[1] or {0.30, 0.85, 0.45}
	local panelBg = SL and SL.Colors.bg.main or {0.10, 0.10, 0.10, 0.95}
	local panelBorder = SL and SL.Colors.border.default or {0.25, 0.25, 0.25, 0.50}
	local inputBg = SL and SL.Colors.bg.input or {0.06, 0.06, 0.06, 0.80}

	local panel = CreateFrame("Frame", "ddingUI_NudgePanel", UIParent, "BackdropTemplate")
	panel:SetSize(260, 560) -- [CDM-P1~P3] 확장: attachTo + selfPoint/anchorPoint + 스냅 슬라이더 + Undo/Redo
	panel:SetPoint("TOP", UIParent, "TOP", 0, -20)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetFrameLevel(600)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetClampedToScreen(true)
	panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
	panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	panel:Hide()
	panel._editing = false

	-- 배경 (StyleLib) -- [12.0.1]
	panel:SetBackdrop({
		bgFile = C.FLAT_TEXTURE,
		edgeFile = C.FLAT_TEXTURE,
		edgeSize = 1,
	})
	panel:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], panelBg[4] or 0.95)
	panel:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	-- 악센트 그라디언트 라인 (상단) -- [12.0.1]
	if SL and SL.CreateHorizontalGradient then
		local gradLine = SL.CreateHorizontalGradient(panel, accentFrom, accent[2] or accentFrom, 2, "OVERLAY")
		if gradLine then
			gradLine:ClearAllPoints()
			gradLine:SetPoint("TOPLEFT", 0, 0)
			gradLine:SetPoint("TOPRIGHT", 0, 0)
		end
	end

	-- 타이틀
	panel.title = panel:CreateFontString(nil, "OVERLAY")
	panel.title:SetFont(fontPath, 12, "OUTLINE")
	panel.title:SetPoint("TOP", 0, -10)
	panel.title:SetText("편집 모드")
	panel.title:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3])

	-- [CDM-P1] 선택된 프레임 이름 표시
	panel.selectedText = panel:CreateFontString(nil, "OVERLAY")
	panel.selectedText:SetFont(fontPath, 10, "OUTLINE")
	panel.selectedText:SetPoint("TOP", panel.title, "BOTTOM", 0, -2)
	panel.selectedText:SetText("|cff888888프레임을 클릭하세요|r")

	-- 좌표 (숨겨진 참조용)
	panel.coords = panel:CreateFontString(nil, "OVERLAY")
	panel.coords:SetFont(fontPath, 1, "OUTLINE")
	panel.coords:SetPoint("TOP", panel.selectedText, "BOTTOM", 0, 0)
	panel.coords:SetAlpha(0)

	-- [MOVER] P3 카테고리 필터 버튼 행
	local filterRow = CreateFrame("Frame", nil, panel)
	filterRow:SetSize(190, 18)
	filterRow:SetPoint("TOP", panel.selectedText, "BOTTOM", 0, -4)
	panel.filterBtns = {}

	local filterBtnW = 44
	local filterBtnH = 16
	for idx, cat in ipairs(CATEGORY_ORDER) do
		local xOff = (idx - 2) * (filterBtnW + 2) -- 3개 균등 배치
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

	-- [CDM-P1] 앵커 포인트 드롭다운 (9-point)
	local anchorRow = CreateFrame("Frame", nil, panel)
	anchorRow:SetSize(190, 22)
	anchorRow:SetPoint("TOP", filterRow, "BOTTOM", 0, -4)

	local anchorLabel = anchorRow:CreateFontString(nil, "OVERLAY")
	anchorLabel:SetFont(fontPath, 8, "OUTLINE")
	anchorLabel:SetPoint("LEFT", 0, 0)
	anchorLabel:SetText("Anchor:")
	anchorLabel:SetTextColor(0.6, 0.6, 0.6)

	-- 간이 드롭다운 (커스텀 구현 — Widgets 의존 없이)
	local ANCHOR_POINTS = {"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}
	local anchorBtn = CreateFrame("Button", nil, anchorRow, "BackdropTemplate")
	anchorBtn:SetSize(110, 18)
	anchorBtn:SetPoint("LEFT", anchorLabel, "RIGHT", 6, 0)
	anchorBtn:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	anchorBtn:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	anchorBtn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local anchorBtnText = anchorBtn:CreateFontString(nil, "OVERLAY")
	anchorBtnText:SetFont(fontPath, 9, "OUTLINE")
	anchorBtnText:SetPoint("CENTER")
	anchorBtnText:SetText("CENTER")
	anchorBtnText:SetTextColor(1, 1, 1)

	local anchorMenu = CreateFrame("Frame", nil, anchorBtn, "BackdropTemplate")
	anchorMenu:SetSize(110, #ANCHOR_POINTS * 16 + 4)
	anchorMenu:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -1)
	anchorMenu:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	anchorMenu:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], 0.98)
	anchorMenu:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], 0.80)
	anchorMenu:SetFrameStrata("TOOLTIP")
	anchorMenu:Hide()

	for i, apName in ipairs(ANCHOR_POINTS) do
		local item = CreateFrame("Button", nil, anchorMenu)
		item:SetSize(106, 16)
		item:SetPoint("TOPLEFT", 2, -(i-1)*16 - 2)
		local itemText = item:CreateFontString(nil, "OVERLAY")
		itemText:SetFont(fontPath, 8, "OUTLINE")
		itemText:SetPoint("CENTER")
		itemText:SetText(apName)
		itemText:SetTextColor(0.8, 0.8, 0.8)
		item:SetScript("OnEnter", function() itemText:SetTextColor(1, 1, 1) end)
		item:SetScript("OnLeave", function() itemText:SetTextColor(0.8, 0.8, 0.8) end)
		item:SetScript("OnClick", function()
			anchorMenu:Hide()
			if not selectedMover then return end
			local oldPt, _, _, oldX, oldY = selectedMover:GetPoint(1)
			if not oldPt then return end
			-- 현재 절대 좌표 계산
			local absLeft = selectedMover:GetLeft() or 0
			local absBottom = selectedMover:GetBottom() or 0
			local mW, mH = selectedMover:GetSize()
			-- 새 앵커 포인트로 오프셋 재계산
			local parentW, parentH = UIParent:GetSize()
			local newX, newY
			local newPt = apName
			-- X 오프셋
			if newPt:find("LEFT") then newX = absLeft
			elseif newPt:find("RIGHT") then newX = (absLeft + mW) - parentW
			else newX = (absLeft + mW/2) - parentW/2 end
			-- Y 오프셋
			if newPt:find("TOP") then newY = (absBottom + mH) - parentH
			elseif newPt:find("BOTTOM") then newY = absBottom
			else newY = (absBottom + mH/2) - parentH/2 end
			newX = math_floor(newX + 0.5)
			newY = math_floor(newY + 0.5)
			-- Undo 저장
			if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
			undoStack[#undoStack + 1] = { mover = selectedMover, point = oldPt, x = oldX or 0, y = oldY or 0 }
			wipe(redoStack)
			if nudgePanel.UpdateUndoRedoBtns then nudgePanel:UpdateUndoRedoBtns() end
			-- 적용
			ApplyMoverVisual(selectedMover, newPt, newX, newY)
			anchorBtnText:SetText(newPt)
			Mover:UpdateNudgeCoords()
		end)
	end

	anchorBtn:SetScript("OnClick", function()
		if anchorMenu:IsShown() then anchorMenu:Hide() else anchorMenu:Show() end
	end)

	panel.anchorDropdown = { SetSelected = function(_, val) anchorBtnText:SetText(val or "CENTER") end }
	panel.anchorMenu = anchorMenu

	-- ==========================================
	-- [CDM 호환] attachTo 드롭다운 행
	-- ==========================================
	local attachRow = CreateFrame("Frame", nil, panel)
	attachRow:SetSize(230, 22)
	attachRow:SetPoint("TOP", anchorRow, "BOTTOM", 0, -4)

	local attachLbl = attachRow:CreateFontString(nil, "OVERLAY")
	attachLbl:SetFont(fontPath, 8, "OUTLINE")
	attachLbl:SetPoint("LEFT", 0, 0)
	attachLbl:SetText("Attach:")
	attachLbl:SetTextColor(0.6, 0.6, 0.6)

	-- attachTo 아이템 목록 (CDM → UF → UIParent 순서)
	local function BuildAttachItems()
		local items = {}
		-- 1) CDM 프록시 앵커 (설치 시 최우선 표시)
		local CDM_PROXIES = {
			{ name = "DDingUI_Anchor_Cooldowns", label = "DDingUI CDM: 핵심" },
			{ name = "DDingUI_Anchor_Buffs",     label = "DDingUI CDM: 강화" },
			{ name = "DDingUI_Anchor_Utility",   label = "DDingUI CDM: 보조" },
		}
		for _, proxy in ipairs(CDM_PROXIES) do
			if _G[proxy.name] then
				items[#items + 1] = { text = proxy.label, value = proxy.name }
			end
		end
		-- 2) UF 프레임
		local UF_FRAMES = {
			{ name = "ddingUI_Player", label = "UF: Player" },
			{ name = "ddingUI_Target", label = "UF: Target" },
			{ name = "ddingUI_Focus",  label = "UF: Focus" },
			{ name = "ddingUI_Pet",    label = "UF: Pet" },
		}
		for _, uf in ipairs(UF_FRAMES) do
			if _G[uf.name] then
				items[#items + 1] = { text = uf.label, value = uf.name }
			end
		end
		-- 3) UIParent (기본값, 항상 마지막)
		items[#items + 1] = { text = "UIParent", value = "UIParent" }
		return items
	end

	local attachBtnText
	local attachMenuFrame

	local attachBtn = CreateFrame("Button", nil, attachRow, "BackdropTemplate")
	attachBtn:SetSize(108, 18)
	attachBtn:SetPoint("LEFT", attachLbl, "RIGHT", 4, 0)
	attachBtn:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	attachBtn:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	attachBtn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	attachBtnText = attachBtn:CreateFontString(nil, "OVERLAY")
	attachBtnText:SetFont(fontPath, 9, "OUTLINE")
	attachBtnText:SetPoint("CENTER")
	attachBtnText:SetText("UIParent")
	attachBtnText:SetTextColor(0.9, 0.9, 0.9)

	attachMenuFrame = CreateFrame("Frame", nil, attachBtn, "BackdropTemplate")
	attachMenuFrame:SetFrameStrata("TOOLTIP")
	attachMenuFrame:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	attachMenuFrame:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], 0.98)
	attachMenuFrame:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], 0.80)
	attachMenuFrame:Hide()

	local function RefreshAttachMenu()
		-- 기존 아이템 제거
		if attachMenuFrame._items then
			for _, item in ipairs(attachMenuFrame._items) do item:Hide() end
		end
		attachMenuFrame._items = {}
		local items = BuildAttachItems()
		local itemH = 16
		attachMenuFrame:SetSize(152, #items * itemH + 4)
		attachMenuFrame:SetPoint("TOP", attachBtn, "BOTTOM", 0, -2)

		for i, entry in ipairs(items) do
			local item = CreateFrame("Button", nil, attachMenuFrame)
			item:SetSize(148, itemH)
			item:SetPoint("TOPLEFT", 2, -(i-1)*itemH - 2)
			local it = item:CreateFontString(nil, "OVERLAY")
			it:SetFont(fontPath, 9, "OUTLINE")
			it:SetPoint("CENTER")
			it:SetText(entry.text)
			it:SetTextColor(0.8, 0.8, 0.8)
			item:SetScript("OnEnter", function() it:SetTextColor(1, 1, 1) end)
			item:SetScript("OnLeave", function() it:SetTextColor(0.8, 0.8, 0.8) end)
			item:SetScript("OnClick", function()
				attachMenuFrame:Hide()
				if not selectedMover then return end
				local unitKey = selectedMover._unitKey
				if not unitKey or not ns.db[unitKey] then return end
				ns.db[unitKey].attachTo = entry.value
				attachBtnText:SetText(entry.text)
				-- 즉시 위치 갱신
				if ns.Update and ns.Update.RefreshUnit then
					ns.Update:RefreshUnit(unitKey)
				end
			end)
			attachMenuFrame._items[i] = item
		end
	end

	attachBtn:SetScript("OnClick", function()
		if attachMenuFrame:IsShown() then
			attachMenuFrame:Hide()
		else
			RefreshAttachMenu()
			attachMenuFrame:Show()
		end
	end)

	panel.attachDropdown = {
		SetSelected = function(_, val)
			local label = val or "UIParent"
			-- 표시 이름 해석
			local CDM_NAMES = {
				["DDingUI_Anchor_Cooldowns"] = "CDM: 핵심",
				["DDingUI_Anchor_Buffs"] = "CDM: 강화",
				["DDingUI_Anchor_Utility"] = "CDM: 보조",
				["ddingUI_Player"] = "UF: Player",
				["ddingUI_Target"] = "UF: Target",
				["ddingUI_Focus"] = "UF: Focus",
				["ddingUI_Pet"] = "UF: Pet",
			}
			attachBtnText:SetText(CDM_NAMES[label] or label)
		end,
	}

	-- ==========================================
	-- [CDM-P5] 프레임 피커 버튼 (attachTo dropdown 오른쪽)
	-- CDM의 StartFramePicker API 사용 또는 UF 자체 구현
	-- ==========================================
	local pickerBtn = CreateFrame("Button", nil, attachRow, "BackdropTemplate")
	pickerBtn:SetSize(20, 18)
	pickerBtn:SetPoint("LEFT", attachBtn, "RIGHT", 2, 0)
	pickerBtn:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	pickerBtn:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	pickerBtn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local pickerIcon = pickerBtn:CreateFontString(nil, "OVERLAY")
	pickerIcon:SetFont(fontPath, 9, "OUTLINE")
	pickerIcon:SetPoint("CENTER")
	pickerIcon:SetText("|cff80c0ff+|r")

	pickerBtn:SetScript("OnEnter", function(self)
		self:SetBackdropColor(
			math.min((inputBg[1] or 0.15) + 0.10, 1),
			math.min((inputBg[2] or 0.15) + 0.10, 1),
			math.min((inputBg[3] or 0.15) + 0.10, 1),
			0.95
		)
		GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
		GameTooltip:AddLine("프레임 선택 (마우스)", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("화면에서 프레임을 클릭하여 연결합니다", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	pickerBtn:SetScript("OnLeave", function(self)
		self:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
		GameTooltip:Hide()
	end)

	-- UF 자체 프레임 피커 (CDM 미설치 시 폴백)
	local function UF_StartFramePicker(callback)
		if ns._framePickerActive then return end
		ns._framePickerActive = true

		-- 넛지 패널의 키보드 비활성화 (ESC 충돌 방지)
		panel:EnableKeyboard(false)

		-- DDingUI UF 프레임 위치 기반 감지
		local knownFrames = {
			"ddingUI_Player", "ddingUI_Target", "ddingUI_TargetTarget",
			"ddingUI_Focus", "ddingUI_FocusTarget", "ddingUI_Pet",
			"ddingUI_Boss1", "ddingUI_Boss2", "ddingUI_Boss3",
		}
		-- CDM 프록시 앵커
		local cdmProxies = {
			"DDingUI_Anchor_Cooldowns", "DDingUI_Anchor_Buffs", "DDingUI_Anchor_Utility",
		}
		-- CDM 그룹 프레임 동적 감지
		local DDingUI = _G.DDingUI_Addon or _G.DDingUI
		if DDingUI and DDingUI.Movers and DDingUI.Movers.CreatedMovers then
			for name, holder in pairs(DDingUI.Movers.CreatedMovers) do
				if name:match("^DDingUI_Group_") and holder.parent and holder.parent:GetName() then
					knownFrames[#knownFrames + 1] = holder.parent:GetName()
				end
			end
		end

		-- 마우스가 프레임 영역 안에 있는지 확인
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

		-- 현재 마우스 아래 프레임 찾기
		local function GetFrameUnderMouse(excludeFrame)
			-- DDingUI 프레임 위치 기반 확인
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
			-- UF movers 확인
			for _, m in ipairs(movers) do
				if m and m ~= excludeFrame and m._frame and IsMouseOverFrame(m._frame) then
					return m._frame
				end
			end
			-- 일반 마우스 포커스
			local mouseFoci = GetMouseFoci and GetMouseFoci()
			if mouseFoci then
				for _, frame in ipairs(mouseFoci) do
					if frame and frame ~= excludeFrame and frame ~= WorldFrame and frame:GetName() then
						return frame
					end
				end
			end
			return nil
		end

		-- 풀스크린 오버레이
		local pickerFrame = CreateFrame("Frame", "DDingUI_UF_FramePicker", UIParent)
		pickerFrame:SetFrameStrata("TOOLTIP")
		pickerFrame:SetAllPoints(UIParent)
		pickerFrame:EnableMouse(false)

		-- 안내 텍스트
		local hint = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		hint:SetPoint("TOP", pickerFrame, "TOP", 0, -50)
		hint:SetText("프레임을 클릭하세요 (ESC로 취소)")
		hint:SetTextColor(1, 1, 0, 1)

		-- 하이라이트 프레임
		local highlight = CreateFrame("Frame", nil, pickerFrame, "BackdropTemplate")
		highlight:SetBackdrop({ edgeFile = C.FLAT_TEXTURE, edgeSize = 2 })
		highlight:SetBackdropBorderColor(0, 1, 0, 0.8)
		highlight:Hide()

		-- 프레임 이름 표시
		local nameLabel = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		nameLabel:SetPoint("BOTTOM", highlight, "TOP", 0, 5)
		nameLabel:SetTextColor(0, 1, 0, 1)

		local currentFrame = nil
		local clickHandled = false

		local function Cleanup()
			clickHandled = true
			if pickerFrame then
				pickerFrame:Hide()
				pickerFrame:SetScript("OnUpdate", nil)
			end
			-- 키보드 복원
			panel:EnableKeyboard(true)
			C_Timer.After(0.2, function()
				ns._framePickerActive = nil
			end)
		end

		pickerFrame:SetScript("OnUpdate", function()
			local focusFrame = GetFrameUnderMouse(pickerFrame)
			if focusFrame then
				local frameName = focusFrame:GetName()
				if frameName then
					currentFrame = focusFrame
					highlight:ClearAllPoints()
					highlight:SetPoint("TOPLEFT", focusFrame, "TOPLEFT", -2, 2)
					highlight:SetPoint("BOTTOMRIGHT", focusFrame, "BOTTOMRIGHT", 2, -2)
					highlight:Show()
					nameLabel:SetText(frameName)
				else
					-- 이름 없는 프레임 — 부모 탐색
					local parent = focusFrame:GetParent()
					while parent and not parent:GetName() do
						parent = parent:GetParent()
					end
					if parent and parent:GetName() then
						currentFrame = parent
						highlight:ClearAllPoints()
						highlight:SetPoint("TOPLEFT", parent, "TOPLEFT", -2, 2)
						highlight:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 2, -2)
						highlight:Show()
						nameLabel:SetText(parent:GetName())
					else
						currentFrame = nil
						highlight:Hide()
						nameLabel:SetText("")
					end
				end
			else
				currentFrame = nil
				highlight:Hide()
				nameLabel:SetText("")
			end

			-- ESC 체크
			if IsKeyDown("ESCAPE") then
				Cleanup()
				return
			end

			-- 마우스 클릭 체크
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

	pickerBtn:SetScript("OnClick", function()
		if not selectedMover then return end
		local unitKey = selectedMover._unitKey
		if not unitKey then return end

		-- 프레임 피커 콜백: 선택된 프레임을 attachTo로 설정
		local function OnFramePicked(frameName)
			if not frameName or not ns.db[unitKey] then return end
			-- attachTo 업데이트
			ns.db[unitKey].attachTo = frameName
			-- 기본 앵커 포인트 설정
			if not ns.db[unitKey].selfPoint then ns.db[unitKey].selfPoint = "CENTER" end
			if not ns.db[unitKey].anchorPoint then ns.db[unitKey].anchorPoint = "CENTER" end
			ns.db[unitKey].position = { 0, 0 }  -- 오프셋 초기화
			-- 드롭다운 동기화
			if panel.attachDropdown and panel.attachDropdown.SetSelected then
				panel.attachDropdown:SetSelected(frameName)
			end
			-- 즉시 위치 갱신
			if ns.Update and ns.Update.RefreshUnit then
				ns.Update:RefreshUnit(unitKey)
			end
		end

		-- CDM StartFramePicker가 있으면 사용, 없으면 UF 자체 피커
		local DDingUI = _G.DDingUI_Addon or _G.DDingUI
		if DDingUI and DDingUI.StartFramePicker then
			DDingUI:StartFramePicker(OnFramePicked)
		else
			UF_StartFramePicker(OnFramePicked)
		end
	end)

	panel.pickerBtn = pickerBtn

	-- ==========================================
	-- [CDM 호환] attachTo 초기화 버튼
	-- ==========================================
	local clearAnchorBtn = CreateFrame("Button", nil, attachRow, "BackdropTemplate")
	clearAnchorBtn:SetSize(20, 18)
	clearAnchorBtn:SetPoint("LEFT", pickerBtn, "RIGHT", 2, 0)
	clearAnchorBtn:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	clearAnchorBtn:SetBackdropColor(0.3, 0.15, 0.15, 0.80)
	clearAnchorBtn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local clearIcon = clearAnchorBtn:CreateFontString(nil, "OVERLAY")
	clearIcon:SetFont(fontPath, 9, "OUTLINE")
	clearIcon:SetPoint("CENTER")
	clearIcon:SetText("|cffff6060X|r")

	clearAnchorBtn:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.5, 0.2, 0.2, 0.95)
		GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
		GameTooltip:AddLine("앵커 초기화", 1, 0.5, 0.5)
		GameTooltip:AddLine("attachTo를 UIParent로 초기화합니다", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	clearAnchorBtn:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.3, 0.15, 0.15, 0.80)
		GameTooltip:Hide()
	end)

	clearAnchorBtn:SetScript("OnClick", function()
		if not selectedMover then return end
		local unitKey = selectedMover._unitKey
		if not unitKey or not ns.db[unitKey] then return end

		-- Undo 저장
		local pt, _, _, ox, oy = selectedMover:GetPoint(1)
		if pt then
			if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
			undoStack[#undoStack + 1] = { mover = selectedMover, point = pt, x = ox or 0, y = oy or 0 }
			wipe(redoStack)
			if nudgePanel and nudgePanel.UpdateUndoRedoBtns then nudgePanel:UpdateUndoRedoBtns() end
		end

		-- 앵커 초기화
		ns.db[unitKey].attachTo = "UIParent"
		ns.db[unitKey].selfPoint = "CENTER"
		ns.db[unitKey].anchorPoint = "CENTER"
		ns.db[unitKey].position = { 0, 0 }

		-- 드롭다운 동기화
		if panel.attachDropdown and panel.attachDropdown.SetSelected then
			panel.attachDropdown:SetSelected("UIParent")
		end
		if panel.selfPtDropdown and panel.selfPtDropdown.SetSelected then
			panel.selfPtDropdown:SetSelected("CENTER")
		end
		if panel.anchorPtDropdown and panel.anchorPtDropdown.SetSelected then
			panel.anchorPtDropdown:SetSelected("CENTER")
		end

		-- 즉시 위치 갱신
		if ns.Update and ns.Update.RefreshUnit then
			ns.Update:RefreshUnit(unitKey)
		end

		ns.Print("|cff00ccff" .. (selectedMover._name or unitKey) .. "|r 앵커 초기화 → UIParent")
	end)

	panel.clearAnchorBtn = clearAnchorBtn

	-- ==========================================
	-- [CDM 호환] selfPoint 드롭다운 행
	-- ==========================================
	local selfPtRow = CreateFrame("Frame", nil, panel)
	selfPtRow:SetSize(230, 22)
	selfPtRow:SetPoint("TOP", attachRow, "BOTTOM", 0, -2)

	local selfPtLabel = selfPtRow:CreateFontString(nil, "OVERLAY")
	selfPtLabel:SetFont(fontPath, 8, "OUTLINE")
	selfPtLabel:SetPoint("LEFT", 0, 0)
	selfPtLabel:SetText("Self Pt:")
	selfPtLabel:SetTextColor(0.6, 0.6, 0.6)

	local selfPtBtn = CreateFrame("Button", nil, selfPtRow, "BackdropTemplate")
	selfPtBtn:SetSize(72, 18)
	selfPtBtn:SetPoint("LEFT", selfPtLabel, "RIGHT", 4, 0)
	selfPtBtn:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	selfPtBtn:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	selfPtBtn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local selfPtBtnText = selfPtBtn:CreateFontString(nil, "OVERLAY")
	selfPtBtnText:SetFont(fontPath, 8, "OUTLINE")
	selfPtBtnText:SetPoint("CENTER")
	selfPtBtnText:SetText("CENTER")
	selfPtBtnText:SetTextColor(0.9, 0.9, 0.9)

	local selfPtMenu = CreateFrame("Frame", nil, selfPtBtn, "BackdropTemplate")
	selfPtMenu:SetSize(74, 9 * 16 + 4)
	selfPtMenu:SetPoint("TOP", selfPtBtn, "BOTTOM", 0, -2)
	selfPtMenu:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	selfPtMenu:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], 0.98)
	selfPtMenu:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], 0.80)
	selfPtMenu:SetFrameStrata("TOOLTIP")
	selfPtMenu:Hide()

	for i, apName in ipairs(ANCHOR_POINTS) do
		local item = CreateFrame("Button", nil, selfPtMenu)
		item:SetSize(70, 16)
		item:SetPoint("TOPLEFT", 2, -(i-1)*16 - 2)
		local it = item:CreateFontString(nil, "OVERLAY")
		it:SetFont(fontPath, 8, "OUTLINE")
		it:SetPoint("CENTER")
		it:SetText(apName)
		it:SetTextColor(0.8, 0.8, 0.8)
		item:SetScript("OnEnter", function() it:SetTextColor(1, 1, 1) end)
		item:SetScript("OnLeave", function() it:SetTextColor(0.8, 0.8, 0.8) end)
		item:SetScript("OnClick", function()
			selfPtMenu:Hide()
			if not selectedMover then return end
			local unitKey = selectedMover._unitKey
			if not unitKey or not ns.db[unitKey] then return end
			ns.db[unitKey].selfPoint = apName
			selfPtBtnText:SetText(apName)
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unitKey) end
		end)
	end
	selfPtBtn:SetScript("OnClick", function()
		if selfPtMenu:IsShown() then selfPtMenu:Hide() else selfPtMenu:Show() end
	end)

	-- anchorPoint (Anchor Pt)
	local anchorPtLabel = selfPtRow:CreateFontString(nil, "OVERLAY")
	anchorPtLabel:SetFont(fontPath, 8, "OUTLINE")
	anchorPtLabel:SetPoint("LEFT", selfPtBtn, "RIGHT", 8, 0)
	anchorPtLabel:SetText("Anc Pt:")
	anchorPtLabel:SetTextColor(0.6, 0.6, 0.6)

	local anchorPtBtn = CreateFrame("Button", nil, selfPtRow, "BackdropTemplate")
	anchorPtBtn:SetSize(72, 18)
	anchorPtBtn:SetPoint("LEFT", anchorPtLabel, "RIGHT", 4, 0)
	anchorPtBtn:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	anchorPtBtn:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	anchorPtBtn:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local anchorPtBtnText = anchorPtBtn:CreateFontString(nil, "OVERLAY")
	anchorPtBtnText:SetFont(fontPath, 8, "OUTLINE")
	anchorPtBtnText:SetPoint("CENTER")
	anchorPtBtnText:SetText("CENTER")
	anchorPtBtnText:SetTextColor(0.9, 0.9, 0.9)

	local anchorPtMenu = CreateFrame("Frame", nil, anchorPtBtn, "BackdropTemplate")
	anchorPtMenu:SetSize(74, 9 * 16 + 4)
	anchorPtMenu:SetPoint("TOP", anchorPtBtn, "BOTTOM", 0, -2)
	anchorPtMenu:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	anchorPtMenu:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], 0.98)
	anchorPtMenu:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], 0.80)
	anchorPtMenu:SetFrameStrata("TOOLTIP")
	anchorPtMenu:Hide()

	for i, apName in ipairs(ANCHOR_POINTS) do
		local item = CreateFrame("Button", nil, anchorPtMenu)
		item:SetSize(70, 16)
		item:SetPoint("TOPLEFT", 2, -(i-1)*16 - 2)
		local it = item:CreateFontString(nil, "OVERLAY")
		it:SetFont(fontPath, 8, "OUTLINE")
		it:SetPoint("CENTER")
		it:SetText(apName)
		it:SetTextColor(0.8, 0.8, 0.8)
		item:SetScript("OnEnter", function() it:SetTextColor(1, 1, 1) end)
		item:SetScript("OnLeave", function() it:SetTextColor(0.8, 0.8, 0.8) end)
		item:SetScript("OnClick", function()
			anchorPtMenu:Hide()
			if not selectedMover then return end
			local unitKey = selectedMover._unitKey
			if not unitKey or not ns.db[unitKey] then return end
			ns.db[unitKey].anchorPoint = apName
			anchorPtBtnText:SetText(apName)
			if ns.Update and ns.Update.RefreshUnit then ns.Update:RefreshUnit(unitKey) end
		end)
	end
	anchorPtBtn:SetScript("OnClick", function()
		if anchorPtMenu:IsShown() then anchorPtMenu:Hide() else anchorPtMenu:Show() end
	end)

	panel.selfPtDropdown = { SetSelected = function(_, val) selfPtBtnText:SetText(val or "CENTER") end }
	panel.anchorPtDropdown = { SetSelected = function(_, val) anchorPtBtnText:SetText(val or "CENTER") end }

	-- X/Y EditBox 행
	local editRow = CreateFrame("Frame", nil, panel)
	editRow:SetSize(230, 22)
	editRow:SetPoint("TOP", selfPtRow, "BOTTOM", 0, -4)

	local function CreateCoordEditBox(labelText, anchor, offX)
		local label = editRow:CreateFontString(nil, "OVERLAY")
		label:SetFont(fontPath, 10, "OUTLINE") -- [12.0.1] StyleLib
		label:SetPoint("LEFT", editRow, anchor, offX, 0)
		label:SetText(labelText)
		label:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3]) -- [12.0.1] StyleLib accent

		local box = CreateFrame("EditBox", nil, editRow, "BackdropTemplate")
		box:SetSize(50, 18)
		box:SetPoint("LEFT", label, "RIGHT", 4, 0)
		box:SetFont(fontPath, 10, "OUTLINE") -- [12.0.1] StyleLib
		box:SetJustifyH("CENTER")
		box:SetAutoFocus(false)
		box:SetNumeric(false)
		box:SetMaxLetters(7)
		box:SetTextColor(1, 1, 1)
		box:SetBackdrop({
			bgFile = C.FLAT_TEXTURE,
			edgeFile = C.FLAT_TEXTURE,
			edgeSize = 1,
		})
		box:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80) -- [12.0.1] StyleLib
		box:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50) -- [12.0.1] StyleLib

		box:SetScript("OnEditFocusGained", function()
			panel._editing = true
			box:SetBackdropBorderColor(accentFrom[1], accentFrom[2], accentFrom[3], 1) -- [12.0.1] StyleLib accent
		end)
		box:SetScript("OnEditFocusLost", function()
			panel._editing = false
			box:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50) -- [12.0.1] StyleLib
		end)

		return box
	end

	panel.xBox = CreateCoordEditBox("X:", "LEFT", 5)
	panel.yBox = CreateCoordEditBox("Y:", "LEFT", 95)

	-- EditBox Enter/Escape/Tab 핸들러
	local function ApplyEditBoxCoords()
		if not selectedMover then return end
		local xVal = tonumber(panel.xBox:GetText())
		local yVal = tonumber(panel.yBox:GetText())
		if not xVal or not yVal then return end

		local point = select(1, selectedMover:GetPoint(1)) or "CENTER"
		ApplyMoverVisual(selectedMover, point, xVal, yVal) -- [MOVER] 시각적 이동만
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
			if self == panel.xBox then
				panel.yBox:SetFocus()
			else
				panel.xBox:SetFocus()
			end
		end)
	end
	
	-- 넛지 방향 버튼 (←↓↑→) 십자 배치
	local btnSize = 26
	local btnCenterY = 20  -- [ESSENTIAL] 위로 이동 (스텝 버튼과 겹치지 않게)

	-- [12.0.1] 넛지 버튼 색상 (StyleLib)
	local nudgeBtnBg = SL and SL.Colors.bg.hover or {0.15, 0.15, 0.15, 0.80}
	local nudgeBtnHover = {
		math.min((nudgeBtnBg[1] or 0.15) + 0.10, 1),
		math.min((nudgeBtnBg[2] or 0.15) + 0.10, 1),
		math.min((nudgeBtnBg[3] or 0.15) + 0.10, 1),
		0.95,
	}

	local function CreateNudgeBtn(label, offsetX, offsetY, dx, dy)
		local btn = CreateFrame("Button", nil, panel)
		btn:SetSize(btnSize, btnSize)
		btn:SetPoint("CENTER", panel, "CENTER", offsetX, offsetY)

		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(nudgeBtnBg[1], nudgeBtnBg[2], nudgeBtnBg[3], nudgeBtnBg[4] or 0.80) -- [12.0.1] StyleLib
		btn._bg = bg

		local bd = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		bd:SetAllPoints()
		bd:SetBackdrop({ edgeFile = C.FLAT_TEXTURE, edgeSize = 1 }) -- [12.0.1] 통일
		bd:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50) -- [12.0.1] StyleLib

		local text = btn:CreateFontString(nil, "OVERLAY")
		text:SetFont(fontPath, 12, "OUTLINE") -- [ESSENTIAL] 기본 폰트
		text:SetPoint("CENTER")
		text:SetText(label)

		btn:SetScript("OnClick", function()
			if not selectedMover then return end
			local mdb = GetMoverDB()
			local step = mdb.nudgeStep or 1
			Mover:NudgeSelected(dx * step, dy * step)
		end)

		btn:SetScript("OnEnter", function(self)
			self._bg:SetColorTexture(nudgeBtnHover[1], nudgeBtnHover[2], nudgeBtnHover[3], nudgeBtnHover[4]) -- [12.0.1] StyleLib
		end)
		btn:SetScript("OnLeave", function(self)
			self._bg:SetColorTexture(nudgeBtnBg[1], nudgeBtnBg[2], nudgeBtnBg[3], nudgeBtnBg[4] or 0.80) -- [12.0.1] StyleLib
		end)

		return btn
	end

	local btnGap = 2
	panel.btnUp    = CreateNudgeBtn("^", 0, btnCenterY + btnSize + btnGap, 0, 1)                -- [ESSENTIAL] ASCII 화살표
	panel.btnDown  = CreateNudgeBtn("v", 0, btnCenterY - btnSize - btnGap, 0, -1)
	panel.btnLeft  = CreateNudgeBtn("<", -(btnSize + btnGap), btnCenterY, -1, 0)
	panel.btnRight = CreateNudgeBtn(">", (btnSize + btnGap), btnCenterY, 1, 0)

	-- [12.0.1] 넛지 스텝 선택 (1px / 5px / 10px)
	local stepY = btnCenterY - (btnSize * 2) - (btnGap * 2) - 6
	local stepBtnW, stepBtnH = 42, 20
	local stepValues = {1, 5, 10}
	panel.stepBtns = {}

	for idx, step in ipairs(stepValues) do
		local xOff = (idx - 2) * (stepBtnW + 4) -- -46, 0, 46
		local btn = CreateFrame("Button", nil, panel)
		btn:SetSize(stepBtnW, stepBtnH)
		btn:SetPoint("CENTER", panel, "CENTER", xOff, stepY)

		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		btn._bg = bg
		btn._step = step

		local bd = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		bd:SetAllPoints()
		bd:SetBackdrop({ edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
		bd:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

		local text = btn:CreateFontString(nil, "OVERLAY")
		text:SetFont(fontPath, 9, "OUTLINE")
		text:SetPoint("CENTER")
		text:SetText(step .. "px")
		btn.text = text

		btn:SetScript("OnClick", function()
			local mdb = GetMoverDB()
			mdb.nudgeStep = step
			panel:UpdateStepBtns()
		end)

		table.insert(panel.stepBtns, btn)
	end

	function panel:UpdateStepBtns()
		local mdb = GetMoverDB()
		local current = mdb.nudgeStep or 1
		for _, btn in ipairs(self.stepBtns) do
			if btn._step == current then
				btn._bg:SetColorTexture(accentFrom[1] * 0.5, accentFrom[2] * 0.5, accentFrom[3] * 0.5, 0.9)
				btn.text:SetTextColor(1, 1, 1)
			else
				btn._bg:SetColorTexture(nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, nudgeBtnBg[4] or 0.80)
				btn.text:SetTextColor(0.6, 0.6, 0.6)
			end
		end
	end
	panel:UpdateStepBtns()

	-- 하단 버튼 행: Grid | Undo | Redo | Reset | Done
	local bottomY = 12
	local bottomBtnW = 36
	local bottomBtnH = 22

	local function CreateBottomBtn(label, anchorX, bgR, bgG, bgB, onClick)
		local btn = CreateFrame("Button", nil, panel)
		btn:SetSize(bottomBtnW, bottomBtnH)
		btn:SetPoint("BOTTOM", panel, "BOTTOM", anchorX, bottomY)

		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(bgR, bgG, bgB, 0.8)
		btn._bg = bg
		btn._r, btn._g, btn._b = bgR, bgG, bgB

		-- [12.0.1] StyleLib border
		local bd = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		bd:SetAllPoints()
		bd:SetBackdrop({ edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
		bd:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

		local text = btn:CreateFontString(nil, "OVERLAY")
		text:SetFont(fontPath, 10, "OUTLINE") -- [12.0.1] StyleLib
		text:SetPoint("CENTER")
		text:SetText(label)
		btn.text = text

		btn:SetScript("OnClick", onClick)

		btn:SetScript("OnEnter", function(self)
			self._bg:SetColorTexture(
				math.min(self._r + 0.12, 1),
				math.min(self._g + 0.12, 1),
				math.min(self._b + 0.12, 1),
				0.95
			)
		end)
		btn:SetScript("OnLeave", function(self)
			self._bg:SetColorTexture(self._r, self._g, self._b, 0.8)
		end)

		return btn
	end

	-- [12.0.1] 그리드 크기 프리셋 사이클
	local GRID_SIZES = {8, 16, 32, 64}

	-- 그리드 토글 (좌클릭=on/off, 우클릭=크기 사이클) -- [12.0.1]
	panel.gridBtn = CreateBottomBtn("Grid", -76, nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, function()
		local mdb = GetMoverDB()
		mdb.gridSnap = not mdb.gridSnap
		mdb.gridEnabled = mdb.gridSnap
		panel:UpdateGridBtnText()
		if mdb.gridEnabled then
			local grid = CreateGridOverlay()
			if grid then FadeIn(grid) end
		elseif gridFrame then
			FadeOut(gridFrame)
		end
	end)
	panel.gridBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	panel.gridBtn:SetScript("OnClick", function(self, button)
		local mdb = GetMoverDB()
		if button == "RightButton" then
			-- [12.0.1] 우클릭: 그리드 크기 사이클 (8→16→32→64→8)
			local currentSize = mdb.gridSize or 16
			local nextIdx = 1
			for i, sz in ipairs(GRID_SIZES) do
				if sz == currentSize then
					nextIdx = (i % #GRID_SIZES) + 1
					break
				end
			end
			mdb.gridSize = GRID_SIZES[nextIdx]
			-- [EDITMODE] 슬라이더 동기화
			if panel._gridSlider then panel._gridSlider:SetValue(mdb.gridSize) end
			if panel._gridValBox then panel._gridValBox:SetText(tostring(mdb.gridSize)) end
			-- 그리드 보이는 중이면 즉시 재생성
			if gridFrame and gridFrame:IsShown() and gridFrame.RefreshLines then
				gridFrame:RefreshLines()
			end
			panel:UpdateGridBtnText()
			ns.Print("|cff00ccff그리드 크기:|r " .. mdb.gridSize .. "px")
		else
			-- 좌클릭: 토글
			mdb.gridSnap = not mdb.gridSnap
			mdb.gridEnabled = mdb.gridSnap
			panel:UpdateGridBtnText()
			if mdb.gridEnabled then
				local grid = CreateGridOverlay()
				if grid then FadeIn(grid) end
			elseif gridFrame then
				FadeOut(gridFrame)
			end
		end
	end)

	-- [12.0.1] Grid 버튼 우클릭 안내 툴팁
	panel.gridBtn:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
		GameTooltip:AddLine("좌클릭: 그리드 ON/OFF", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("우클릭: 프리셋 사이클 (8/16/32/64)", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("슬라이더: 4-64px 연속 조절", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	panel.gridBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

	function panel:UpdateGridBtnText()
		local mdb = GetMoverDB()
		local sz = mdb.gridSize or 16
		if mdb.gridSnap then
			panel.gridBtn.text:SetText("Grid " .. sz .. " |cff" .. ACCENT_HEX .. "ON|r") -- [STYLE]
		else
			panel.gridBtn.text:SetText("Grid " .. sz .. " |cff" .. DIM_HEX .. "OFF|r") -- [STYLE]
		end
	end
	panel:UpdateGridBtnText()

	-- [CDM-P1] Undo 버튼
	panel.undoBtn = CreateBottomBtn("Undo", -36, nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, function()
		Mover:Undo()
	end)

	-- [CDM-P1] Redo 버튼
	panel.redoBtn = CreateBottomBtn("Redo", 0, nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, function()
		Mover:Redo()
	end)

	-- 리셋 버튼
	panel.resetBtn = CreateBottomBtn("Reset", 36, 0.3, 0.15, 0.15, function()
		if not selectedMover then return end
		-- Undo 저장
		local pt, _, _, ox, oy = selectedMover:GetPoint(1)
		if pt then
			if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
			undoStack[#undoStack + 1] = { mover = selectedMover, point = pt, x = ox or 0, y = oy or 0 }
			wipe(redoStack)
		end
		Mover:ResetMover(selectedMover)
		if panel.UpdateUndoRedoBtns then panel:UpdateUndoRedoBtns() end
	end)

	-- 완료 버튼 (편집모드 종료)
	local ar, ag, ab = accentFrom[1] or 0.3, accentFrom[2] or 0.85, accentFrom[3] or 0.45
	panel.doneBtn = CreateBottomBtn(string.format("|cff%02x%02x%02xDone|r", math.floor(ar*255+0.5), math.floor(ag*255+0.5), math.floor(ab*255+0.5)), 76, ar*0.35, ag*0.35, ab*0.35, function()
		Mover:LockAll()
	end)

	-- [CDM-P1] Undo/Redo 버튼 활성화 상태 업데이트
	function panel:UpdateUndoRedoBtns()
		if self.undoBtn then
			if #undoStack > 0 then
				self.undoBtn:SetAlpha(1)
				self.undoBtn:Enable()
			else
				self.undoBtn:SetAlpha(0.4)
				self.undoBtn:Disable()
			end
		end
		if self.redoBtn then
			if #redoStack > 0 then
				self.redoBtn:SetAlpha(1)
				self.redoBtn:Enable()
			else
				self.redoBtn:SetAlpha(0.4)
				self.redoBtn:Disable()
			end
		end
	end
	panel:UpdateUndoRedoBtns()

	-- [EDITMODE] 그리드 크기 슬라이더 (dandersFrame 패턴: 연속 값 4-64)
	local gridSliderY = bottomY + bottomBtnH + 6
	local gridSliderRow = CreateFrame("Frame", nil, panel)
	gridSliderRow:SetSize(180, 20)
	gridSliderRow:SetPoint("BOTTOM", panel, "BOTTOM", 0, gridSliderY)

	local gsLabel = gridSliderRow:CreateFontString(nil, "OVERLAY")
	gsLabel:SetFont(fontPath, 8, "OUTLINE")
	gsLabel:SetPoint("LEFT", 0, 0)
	gsLabel:SetText("Grid:")
	gsLabel:SetTextColor(0.6, 0.6, 0.6)

	local gsValBox = CreateFrame("EditBox", nil, gridSliderRow, "BackdropTemplate")
	gsValBox:SetSize(32, 16)
	gsValBox:SetPoint("RIGHT", 0, 0)
	gsValBox:SetFont(fontPath, 9, "OUTLINE")
	gsValBox:SetJustifyH("CENTER")
	gsValBox:SetAutoFocus(false)
	gsValBox:SetMaxLetters(3)
	gsValBox:SetTextColor(1, 1, 1)
	gsValBox:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	gsValBox:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	gsValBox:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local gsSlider = CreateFrame("Slider", nil, gridSliderRow, "BackdropTemplate")
	gsSlider:SetSize(110, 12)
	gsSlider:SetPoint("LEFT", gsLabel, "RIGHT", 4, 0)
	gsSlider:SetPoint("RIGHT", gsValBox, "LEFT", -4, 0)
	gsSlider:SetOrientation("HORIZONTAL")
	gsSlider:SetMinMaxValues(4, 64)
	gsSlider:SetValueStep(2)
	gsSlider:SetObeyStepOnDrag(true)
	gsSlider:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	gsSlider:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
	gsSlider:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local gsThumb = gsSlider:CreateTexture(nil, "OVERLAY")
	gsThumb:SetSize(8, 14)
	gsThumb:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 0.9)
	gsSlider:SetThumbTexture(gsThumb)

	local gsTrack = gsSlider:CreateTexture(nil, "ARTWORK")
	gsTrack:SetPoint("LEFT", 0, 0)
	gsTrack:SetPoint("RIGHT", 0, 0)
	gsTrack:SetHeight(4)
	gsTrack:SetColorTexture(0.2, 0.2, 0.2, 0.8)

	local function UpdateGridSlider(val)
		local mdb = GetMoverDB()
		mdb.gridSize = math_floor(val + 0.5)
		gsValBox:SetText(tostring(mdb.gridSize))
		panel:UpdateGridBtnText()
		if gridFrame and gridFrame:IsShown() and gridFrame.RefreshLines then
			gridFrame:RefreshLines()
		end
	end

	gsSlider:SetScript("OnValueChanged", function(self, val)
		UpdateGridSlider(val)
	end)

	gsValBox:SetScript("OnEnterPressed", function(self)
		local v = tonumber(self:GetText())
		if v then
			v = math_max(4, math.min(64, math_floor(v + 0.5)))
			gsSlider:SetValue(v)
			UpdateGridSlider(v)
		end
		self:ClearFocus()
	end)
	gsValBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		local mdb = GetMoverDB()
		self:SetText(tostring(mdb.gridSize or 16))
	end)
	gsValBox:SetScript("OnEditFocusGained", function() panel._editing = true end)
	gsValBox:SetScript("OnEditFocusLost", function() panel._editing = false end)

	-- 초기값 설정
	local initGridSize = GetMoverDB().gridSize or 16
	gsSlider:SetValue(initGridSize)
	gsValBox:SetText(tostring(initGridSize))
	panel._gridSlider = gsSlider
	panel._gridValBox = gsValBox

	-- [EDITMODE] 레이드 미리보기 인원수 슬라이더 (10~40명, step 5)
	local raidSliderY = gridSliderY + 24
	local raidSliderRow = CreateFrame("Frame", nil, panel)
	raidSliderRow:SetSize(180, 20)
	raidSliderRow:SetPoint("BOTTOM", panel, "BOTTOM", 0, raidSliderY)

	local rsLabel = raidSliderRow:CreateFontString(nil, "OVERLAY")
	rsLabel:SetFont(fontPath, 8, "OUTLINE")
	rsLabel:SetPoint("LEFT", 0, 0)
	rsLabel:SetText("Raid:")
	rsLabel:SetTextColor(0.6, 0.6, 0.6)

	local rsValBox = CreateFrame("EditBox", nil, raidSliderRow, "BackdropTemplate")
	rsValBox:SetSize(32, 16)
	rsValBox:SetPoint("RIGHT", 0, 0)
	rsValBox:SetFont(fontPath, 9, "OUTLINE")
	rsValBox:SetJustifyH("CENTER")
	rsValBox:SetAutoFocus(false)
	rsValBox:SetMaxLetters(3)
	rsValBox:SetTextColor(1, 1, 1)
	rsValBox:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	rsValBox:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	rsValBox:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local rsSlider = CreateFrame("Slider", nil, raidSliderRow, "BackdropTemplate")
	rsSlider:SetSize(110, 12)
	rsSlider:SetPoint("LEFT", rsLabel, "RIGHT", 4, 0)
	rsSlider:SetPoint("RIGHT", rsValBox, "LEFT", -4, 0)
	rsSlider:SetOrientation("HORIZONTAL")
	rsSlider:SetMinMaxValues(10, 30)
	rsSlider:SetValueStep(5)
	rsSlider:SetObeyStepOnDrag(true)
	rsSlider:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	rsSlider:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
	rsSlider:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local rsThumb = rsSlider:CreateTexture(nil, "OVERLAY")
	rsThumb:SetSize(8, 14)
	rsThumb:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 0.9)
	rsSlider:SetThumbTexture(rsThumb)

	local rsTrack = rsSlider:CreateTexture(nil, "ARTWORK")
	rsTrack:SetPoint("LEFT", 0, 0)
	rsTrack:SetPoint("RIGHT", 0, 0)
	rsTrack:SetHeight(4)
	rsTrack:SetColorTexture(0.2, 0.2, 0.2, 0.8)

	local function UpdateRaidSlider(val)
		local mdb = GetMoverDB()
		mdb.previewRaidCount = math_floor(val + 0.5)
		rsValBox:SetText(tostring(mdb.previewRaidCount))
		-- [REFACTOR] 레이드 프레임만 갱신 (전체 재생성 대신)
		local TM = ns.GroupFrames and ns.GroupFrames.TestMode
		if TM and TM.active then
			TM:RefreshRaid()
		end
	end

	rsSlider:SetScript("OnValueChanged", function(self, val)
		UpdateRaidSlider(val)
	end)

	rsValBox:SetScript("OnEnterPressed", function(self)
		local v = tonumber(self:GetText())
		if v then
			v = math_max(10, math.min(30, math_floor(v / 5 + 0.5) * 5))
			rsSlider:SetValue(v)
			UpdateRaidSlider(v)
		end
		self:ClearFocus()
	end)
	rsValBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		local mdb = GetMoverDB()
		self:SetText(tostring(mdb.previewRaidCount or 20))
	end)
	rsValBox:SetScript("OnEditFocusGained", function() panel._editing = true end)
	rsValBox:SetScript("OnEditFocusLost", function() panel._editing = false end)

	-- 초기값
	local initRaidCount = GetMoverDB().previewRaidCount or 20
	rsSlider:SetValue(initRaidCount)
	rsValBox:SetText(tostring(initRaidCount))
	panel._raidSlider = rsSlider
	panel._raidValBox = rsValBox

	-- [CDM-P2] Snap Threshold 슬라이더
	local snapSliderY = raidSliderY + 24
	local snapSliderRow = CreateFrame("Frame", nil, panel)
	snapSliderRow:SetSize(180, 20)
	snapSliderRow:SetPoint("BOTTOM", panel, "BOTTOM", 0, snapSliderY)

	local stLabel = snapSliderRow:CreateFontString(nil, "OVERLAY")
	stLabel:SetFont(fontPath, 8, "OUTLINE")
	stLabel:SetPoint("LEFT", 0, 0)
	stLabel:SetText("Snap:")
	stLabel:SetTextColor(0.6, 0.6, 0.6)

	local stValBox = CreateFrame("EditBox", nil, snapSliderRow, "BackdropTemplate")
	stValBox:SetSize(32, 16)
	stValBox:SetPoint("RIGHT", 0, 0)
	stValBox:SetFont(fontPath, 9, "OUTLINE")
	stValBox:SetJustifyH("CENTER")
	stValBox:SetAutoFocus(false)
	stValBox:SetMaxLetters(3)
	stValBox:SetTextColor(1, 1, 1)
	stValBox:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	stValBox:SetBackdropColor(inputBg[1], inputBg[2], inputBg[3], inputBg[4] or 0.80)
	stValBox:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local stSlider = CreateFrame("Slider", nil, snapSliderRow, "BackdropTemplate")
	stSlider:SetSize(110, 12)
	stSlider:SetPoint("LEFT", stLabel, "RIGHT", 4, 0)
	stSlider:SetPoint("RIGHT", stValBox, "LEFT", -4, 0)
	stSlider:SetOrientation("HORIZONTAL")
	stSlider:SetMinMaxValues(1, 30)
	stSlider:SetValueStep(1)
	stSlider:SetObeyStepOnDrag(true)
	stSlider:SetBackdrop({ bgFile = C.FLAT_TEXTURE, edgeFile = C.FLAT_TEXTURE, edgeSize = 1 })
	stSlider:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
	stSlider:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

	local stThumb = stSlider:CreateTexture(nil, "OVERLAY")
	stThumb:SetSize(8, 14)
	stThumb:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 0.9)
	stSlider:SetThumbTexture(stThumb)

	local stTrack = stSlider:CreateTexture(nil, "ARTWORK")
	stTrack:SetPoint("LEFT", 0, 0)
	stTrack:SetPoint("RIGHT", 0, 0)
	stTrack:SetHeight(4)
	stTrack:SetColorTexture(0.2, 0.2, 0.2, 0.8)

	stSlider:SetScript("OnValueChanged", function(self, val)
		local mdb = GetMoverDB()
		mdb.snapThreshold = math_floor(val + 0.5)
		stValBox:SetText(tostring(mdb.snapThreshold))
	end)
	stValBox:SetScript("OnEnterPressed", function(self)
		local v = tonumber(self:GetText())
		if v then
			v = math_max(1, math.min(30, math_floor(v + 0.5)))
			stSlider:SetValue(v)
		end
		self:ClearFocus()
	end)
	stValBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	stValBox:SetScript("OnEditFocusGained", function() panel._editing = true end)
	stValBox:SetScript("OnEditFocusLost", function() panel._editing = false end)

	local initSnap = GetMoverDB().snapThreshold or 12
	stSlider:SetValue(initSnap)
	stValBox:SetText(tostring(initSnap))

	-- [CDM-P2] 스냅 세부 토글 행: ☑ Grid  ☑ Frames  ☑ Center
	local snapToggleY = snapSliderY + 22
	local snapToggleRow = CreateFrame("Frame", nil, panel)
	snapToggleRow:SetSize(190, 16)
	snapToggleRow:SetPoint("BOTTOM", panel, "BOTTOM", 0, snapToggleY)

	local function CreateSnapToggle(labelText, settingKey, xOff)
		local cb = CreateFrame("CheckButton", nil, snapToggleRow)
		cb:SetSize(14, 14)
		cb:SetPoint("LEFT", snapToggleRow, "LEFT", xOff, 0)
		local cbBg = cb:CreateTexture(nil, "BACKGROUND")
		cbBg:SetAllPoints()
		cbBg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
		local cbCheck = cb:CreateTexture(nil, "OVERLAY")
		cbCheck:SetSize(10, 10)
		cbCheck:SetPoint("CENTER")
		cbCheck:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 0.9)
		cb._check = cbCheck
		local cbLabel = cb:CreateFontString(nil, "OVERLAY")
		cbLabel:SetFont(fontPath, 8, "OUTLINE")
		cbLabel:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cbLabel:SetText(labelText)
		cbLabel:SetTextColor(0.7, 0.7, 0.7)
		cb:SetScript("OnClick", function(self)
			local mdb = GetMoverDB()
			mdb[settingKey] = not mdb[settingKey]
			self._check:SetShown(mdb[settingKey])
		end)
		local mdb = GetMoverDB()
		cb:SetChecked(mdb[settingKey] ~= false)
		cbCheck:SetShown(mdb[settingKey] ~= false)
		return cb
	end

	CreateSnapToggle("Grid", "snapToGrid", 10)
	CreateSnapToggle("Frames", "snapToFrames", 68)
	CreateSnapToggle("Center", "snapToCenter", 136)

	-- [EDITMODE] 중간 버튼 행: Mythic | Center
	local midY = snapToggleY + 22
	local midBtnW = 52

	-- [MYTHIC-RAID] Raid/Mythic 토글 버튼
	panel.mythicBtn = CreateBottomBtn("Raid", 0, nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, function()
		ns._mythicRaidActive = not ns._mythicRaidActive
		panel:UpdateMythicBtnText()
		-- 테스트모드 재생성으로 프리뷰 전환
		if ns.Update and ns.Update.DisableEditMode then
			ns.Update:DisableEditMode()
		end
		if ns.Update and ns.Update.EnableEditMode then
			ns.Update:EnableEditMode()
			ApplyMoverFilter(_activeCategory)
		end
	end)
	panel.mythicBtn:ClearAllPoints()
	panel.mythicBtn:SetSize(midBtnW, bottomBtnH)
	panel.mythicBtn:SetPoint("BOTTOM", panel, "BOTTOM", -28, midY)

	function panel:UpdateMythicBtnText()
		if ns._mythicRaidActive then
			panel.mythicBtn.text:SetText("|cff" .. ACCENT_HEX .. "Mythic|r")
		else
			panel.mythicBtn.text:SetText("Raid")
		end
	end
	panel:UpdateMythicBtnText()

	panel.centerBtn = CreateBottomBtn("Center", 0, nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, function()
		if not selectedMover then return end
		-- Undo 저장
		local pt, _, _, ox, oy = selectedMover:GetPoint(1)
		if pt then
			if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
			undoStack[#undoStack + 1] = { mover = selectedMover, point = pt, x = ox or 0, y = oy or 0 }
			wipe(redoStack)
			if panel.UpdateUndoRedoBtns then panel:UpdateUndoRedoBtns() end
		end
		ApplyMoverVisual(selectedMover, "CENTER", 0, 0)
		Mover:UpdateNudgeCoords()
		if panel.anchorDropdown then panel.anchorDropdown:SetSelected("CENTER") end
		ns.Print("|cff00ccff" .. (selectedMover._name or "Frame") .. "|r 화면 중앙으로 이동")
	end)
	panel.centerBtn:ClearAllPoints()
	panel.centerBtn:SetSize(midBtnW, bottomBtnH)
	panel.centerBtn:SetPoint("BOTTOM", panel, "BOTTOM", 28, midY)

	-- [12.0.1] 키보드 넛지: 화살표 키로 선택된 무버 이동 (ElvUI 스타일)
	-- Ctrl+Arrow = 10px, Arrow = nudgeStep
	panel:EnableKeyboard(true)
	panel:SetPropagateKeyboardInput(true)
	panel:SetScript("OnKeyDown", function(self, key)
		-- EditBox 포커스 중이면 키 통과
		if self._editing then
			self:SetPropagateKeyboardInput(true)
			return
		end

		if not selectedMover then
			self:SetPropagateKeyboardInput(true)
			return
		end

		local mdb = GetMoverDB()
		local step = IsControlKeyDown() and 10 or (mdb.nudgeStep or 1)

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
			-- [CDM-P1] Ctrl+Z: 언두
			self:SetPropagateKeyboardInput(false)
			Mover:Undo()
		elseif key == "Y" and IsControlKeyDown() then
			-- [CDM-P1] Ctrl+Y: 리두
			self:SetPropagateKeyboardInput(false)
			Mover:Redo()
		elseif key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			Mover:CancelEditMode() -- [MOVER] ESC = 취소+복원 (DB 저장 없음)
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
	local curPt, _, _, curX, curY = entry.mover:GetPoint(1)
	if curPt then
		if #redoStack >= MAX_UNDO then table.remove(redoStack, 1) end
		redoStack[#redoStack + 1] = { mover = entry.mover, point = curPt, x = curX or 0, y = curY or 0 }
	end

	-- 이전 위치로 복원
	ApplyMoverVisual(entry.mover, entry.point, entry.x, entry.y)
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
	local curPt, _, _, curX, curY = entry.mover:GetPoint(1)
	if curPt then
		if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
		undoStack[#undoStack + 1] = { mover = entry.mover, point = curPt, x = curX or 0, y = curY or 0 }
	end

	-- Redo 위치로 이동
	ApplyMoverVisual(entry.mover, entry.point, entry.x, entry.y)
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
	local mainPt, _, _, mainX, mainY = selectedMover:GetPoint(1)
	if mainPt then
		if #undoStack >= MAX_UNDO then table.remove(undoStack, 1) end
		undoStack[#undoStack + 1] = { mover = selectedMover, point = mainPt, x = mainX or 0, y = mainY or 0 }
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
	local _, _, _, oX, oY = selectedMover:GetPoint(1)
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
