--[[
    DDingUI Utils/MoverUtils.lua
    CDM Movers.lua + UF Mover.lua 공용 유틸리티
    - 좌표 계산 (CalcPoint / CalcPointFromAbsolute)
    - 스냅 관계 감지 (DetectSnapRelation)
    - Undo/Redo 스택
    - GetPointPosition (앵커 포인트 → 스크린 좌표)
    - Easing 함수
    - 순환 앵커 감지
    [v1.0] 2026-03-09 - 초기 추출
]]

local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- ============================================================
-- 네임스페이스: DDingUI.MoverUtils
-- ============================================================
DDingUI.MoverUtils = DDingUI.MoverUtils or {}
local MU = DDingUI.MoverUtils

local math_floor = math.floor
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt
local math_sin = math.sin

-- ============================================================
-- 1. Round (반올림)
-- ============================================================

function MU.Round(num)
    return math_floor(num + 0.5)
end

-- ============================================================
-- 2. GetPointPosition
-- 프레임의 특정 anchor point 위치를 스크린 좌표로 반환
-- CDM Movers.lua L100-131, UF Mover.lua L131-144 통합
-- ============================================================

function MU.GetPointPosition(frame, anchorPoint)
    if not frame then return nil, nil end
    local centerX, centerY = frame:GetCenter()
    if not centerX then return nil, nil end

    local width = frame:GetWidth() or 0
    local height = frame:GetHeight() or 0
    local halfW, halfH = width / 2, height / 2

    anchorPoint = anchorPoint or "CENTER"

    if anchorPoint == "TOP" then
        return centerX, centerY + halfH
    elseif anchorPoint == "BOTTOM" then
        return centerX, centerY - halfH
    elseif anchorPoint == "LEFT" then
        return centerX - halfW, centerY
    elseif anchorPoint == "RIGHT" then
        return centerX + halfW, centerY
    elseif anchorPoint == "TOPLEFT" then
        return centerX - halfW, centerY + halfH
    elseif anchorPoint == "TOPRIGHT" then
        return centerX + halfW, centerY + halfH
    elseif anchorPoint == "BOTTOMLEFT" then
        return centerX - halfW, centerY - halfH
    elseif anchorPoint == "BOTTOMRIGHT" then
        return centerX + halfW, centerY - halfH
    else -- CENTER
        return centerX, centerY
    end
end

-- ============================================================
-- 3. CalcPointFromAbsolute
-- 절대 좌표(bottom-left) → 최적 앵커 + 오프셋
-- CDM Movers.lua L272-314, UF Mover.lua L645-691 통합
-- ============================================================

function MU.CalcPointFromAbsolute(absLeft, absBottom, w, h, forceCenter)
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

-- ============================================================
-- 4. CalcPoint
-- 프레임의 현재 위치에서 CalcPointFromAbsolute 호출
-- ============================================================

function MU.CalcPoint(frame)
    local x, y = frame:GetCenter()
    if not x or not y then return "CENTER", 0, 0 end
    local w, h = frame:GetSize()
    local absLeft = x - (w or 0) / 2
    local absBottom = y - (h or 0) / 2
    return MU.CalcPointFromAbsolute(absLeft, absBottom, w or 0, h or 0)
end

-- ============================================================
-- 5. DetectSnapRelation
-- 두 프레임 간 selfPoint/anchorPoint 자동 결정
-- CDM Movers.lua L624-682, UF Mover.lua L510-559 통합
-- ============================================================

function MU.DetectSnapRelation(myLeft, myBottom, myW, myH, tLeft, tBottom, tW, tH, threshold)
    local myRight = myLeft + myW
    local myTop = myBottom + myH
    local tRight = tLeft + tW
    local tTop = tBottom + tH

    -- 수평 겹침 비율 (상하 스냅 인정 조건)
    local hOverlap = math_min(myRight, tRight) - math_max(myLeft, tLeft)
    local minW = math_min(myW, tW)
    local hRatio = minW > 0 and (hOverlap / minW) or 0

    -- 수직 겹침 비율 (좌우 스냅 인정 조건)
    local vOverlap = math_min(myTop, tTop) - math_max(myBottom, tBottom)
    local minH = math_min(myH, tH)
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

-- ============================================================
-- 6. IsCircularAnchor
-- 방문 집합(visited set) 기반 순환 앵커 감지
-- CDM Movers.lua L609-622의 pcall+10단계 제한 → 안전한 패턴
-- ============================================================

function MU.IsCircularAnchor(startFrame, targetName, visited)
    if not startFrame or not targetName then return false end
    visited = visited or {}
    if visited[startFrame] then return true end
    visited[startFrame] = true

    local numPoints = startFrame:GetNumPoints()
    if not numPoints or numPoints == 0 then return false end

    local ok, _, anchor = pcall(startFrame.GetPoint, startFrame, 1)
    if not ok or not anchor or anchor == UIParent then return false end

    local anchorName = anchor:GetName()
    if anchorName == targetName then return true end

    return MU.IsCircularAnchor(anchor, targetName, visited)
end

-- ============================================================
-- 7. EdgeDistance
-- 두 프레임 간 최소 엣지 거리 (앵커 해제 판단용)
-- CDM Movers.lua L736-758 패턴
-- ============================================================

function MU.EdgeDistance(myL, myB, myW, myH, tL, tB, tW, tH)
    local myR, myT = myL + myW, myB + myH
    local tR, tT = tL + tW, tB + tH

    local hDist = 0
    if myR < tL then hDist = tL - myR
    elseif myL > tR then hDist = myL - tR end

    local vDist = 0
    if myT < tB then vDist = tB - myT
    elseif myB > tT then vDist = myB - tT end

    return math_sqrt(hDist * hDist + vDist * vDist)
end

-- ============================================================
-- 8. Easing 함수
-- ============================================================

-- EaseInOutQuad: 부드러운 가속/감속
function MU.EaseInOut(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return 1 - (-2 * t + 2) * (-2 * t + 2) / 2
    end
end

-- 선형 보간
function MU.Lerp(a, b, t)
    return a + (b - a) * t
end

-- ============================================================
-- 9. Undo/Redo 스택 관리
-- CDM Movers.lua L173-266, UF Mover.lua undoStack/redoStack 통합
-- ============================================================

function MU.CreateUndoStack(maxSize)
    return {
        undo = {},
        redo = {},
        max = maxSize or 50,
    }
end

function MU.PushUndo(stack, entry)
    if not stack or not entry then return end
    -- 새 동작 진입 시 Redo 초기화
    wipe(stack.redo)
    -- Undo에 추가
    table.insert(stack.undo, entry)
    -- 초과 시 오래된 것 제거
    while #stack.undo > stack.max do
        table.remove(stack.undo, 1)
    end
end

function MU.PerformUndo(stack)
    if not stack or #stack.undo == 0 then return nil end
    local entry = table.remove(stack.undo)
    table.insert(stack.redo, entry)
    return entry
end

function MU.PerformRedo(stack)
    if not stack or #stack.redo == 0 then return nil end
    local entry = table.remove(stack.redo)
    table.insert(stack.undo, entry)
    return entry
end

function MU.ClearStack(stack)
    if not stack then return end
    wipe(stack.undo)
    wipe(stack.redo)
end

function MU.HasUndo(stack)
    return stack and #stack.undo > 0
end

function MU.HasRedo(stack)
    return stack and #stack.redo > 0
end

-- ============================================================
-- 10. SmoothScroll 모듈
-- Ellesmere SmoothScrollTo 패턴 이식
-- OnUpdate 보간 스크롤 (Linear interpolation + 임계값 스냅)
-- ============================================================

function MU.CreateSmoothScroll(scrollFrame, options)
    if not scrollFrame then return nil end
    options = options or {}
    local SPEED = options.speed or 12
    local STEP = options.step or 60

    local scrollTarget = 0
    local isSmoothing = false
    local smoothFrame = CreateFrame("Frame")
    smoothFrame:Hide()

    -- safe scroll range (secret value 방어)
    local function SafeRange()
        local child = scrollFrame:GetScrollChild()
        if child then
            local ok, result = pcall(function()
                local ch = child:GetHeight() or 0
                local fh = scrollFrame:GetHeight() or 0
                return math_max(0, ch - fh)
            end)
            if ok then return result end
        end
        return 0
    end

    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = scrollFrame:GetVerticalScroll()
        local maxScroll = SafeRange()
        scrollTarget = math_max(0, math_min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math_abs(diff) < 0.5 then
            scrollFrame:SetVerticalScroll(scrollTarget)
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        local newScroll = cur + diff * math_min(1, SPEED * elapsed)
        newScroll = math_max(0, math_min(maxScroll, newScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end)

    local controller = {}

    -- 특정 위치로 부드럽게 스크롤
    function controller:ScrollTo(target)
        local maxScroll = SafeRange()
        scrollTarget = math_max(0, math_min(maxScroll, target))
        if not isSmoothing then
            isSmoothing = true
            smoothFrame:Show()
        end
    end

    -- 마우스 휠 이벤트 처리
    function controller:OnMouseWheel(delta)
        local maxScroll = SafeRange()
        if maxScroll <= 0 then return end
        local base = isSmoothing and scrollTarget or scrollFrame:GetVerticalScroll()
        self:ScrollTo(base - delta * STEP)
    end

    -- 현재 목표 위치 반환
    function controller:GetTarget()
        return scrollTarget
    end

    -- 진행 중 여부
    function controller:IsSmoothing()
        return isSmoothing
    end

    -- 즉시 중지
    function controller:Stop()
        isSmoothing = false
        smoothFrame:Hide()
    end

    return controller
end

-- ============================================================
-- 11. FadeIn/FadeOut with Easing
-- StyleLib 위임 대신 직접 OnUpdate 이징 적용
-- ============================================================

function MU.FadeIn(frame, duration, callback)
    if not frame then return end
    duration = duration or 0.2
    local startAlpha = frame:GetAlpha()
    local elapsed = 0
    frame:Show()
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math_min(1, elapsed / duration)
        local eased = MU.EaseInOut(t)
        self:SetAlpha(startAlpha + (1 - startAlpha) * eased)
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            if callback then callback() end
        end
    end)
end

function MU.FadeOut(frame, duration, callback)
    if not frame then return end
    duration = duration or 0.2
    local startAlpha = frame:GetAlpha()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math_min(1, elapsed / duration)
        local eased = MU.EaseInOut(t)
        self:SetAlpha(startAlpha * (1 - eased))
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(0)
            if callback then callback() end
        end
    end)
end
