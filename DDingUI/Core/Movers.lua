local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = ns.L or {}

-- Mover system namespace (ElvUI style)
DDingUI.Movers = DDingUI.Movers or {}
local Movers = DDingUI.Movers

-- State
Movers.CreatedMovers = {}
Movers.ConfigMode = false
Movers.Grid = nil
Movers.NudgeFrame = nil
Movers.SelectedMover = nil

-- Settings
Movers.Settings = {
    gridEnabled = false,
    snapEnabled = true,
    snapToGrid = true,
    snapToFrames = true,
    snapToCenter = true,
    snapThreshold = 10,  -- pixels
    gridSize = 32,
}

-- Undo/Redo 스택 (함수는 GetPoint/SetPoint 정의 이후에)
Movers.UndoStack = {}
Movers.RedoStack = {}
Movers.MAX_UNDO = 50  -- 최대 저장 개수

-- Dragging state
local isDragging = false
local dragFrame = nil
local dragOffsetX, dragOffsetY = 0, 0

-- [FIX] Forward declaration: 파일 하단에서 정의되지만 OnDragStop에서 사용
local ResolvePath

-- Mover 이름과 모듈 설정 경로 매핑 (파일 상단에 정의하여 모든 함수에서 접근 가능)
local MoverToModuleMapping = {
    ["DDingUI_PowerBar"] = { path = "powerBar", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", selfPointKey = "selfPoint", hasBarAnchorFlip = true },
    ["DDingUI_SecondaryPowerBar"] = { path = "secondaryPowerBar", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", selfPointKey = "selfPoint" },
    ["DDingUI_PlayerCastBar"] = { path = "castBar", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", selfPointKey = "selfPoint" },
    ["DDingUI_BuffTrackerBar"] = { path = "buffTrackerBar", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", selfPointKey = "selfPoint" },
    -- Missing Alerts
    ["DDingUI_PetMissingAlert"] = { path = "missingAlerts", xKey = "petOffsetX", yKey = "petOffsetY", pointKey = "petAnchorPoint" },
    ["DDingUI_BuffMissingAlert"] = { path = "missingAlerts", xKey = "buffOffsetX", yKey = "buffOffsetY", pointKey = "buffAnchorPoint" },
    -- [GROUP SYSTEM] 그룹별 Mover 매핑 (동적 등록)
    ["DDingUI_Group_Buffs"] = { path = "groupSystem.groups.Buffs", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", selfPointKey = "selfPoint" },
    ["DDingUI_Group_Cooldowns"] = { path = "groupSystem.groups.Cooldowns", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", selfPointKey = "selfPoint" },
    ["DDingUI_Group_Utility"] = { path = "groupSystem.groups.Utility", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", selfPointKey = "selfPoint" },
}

-- [V5] CDM 뷰어/구 프레임 → 프록시 앵커 통합 매핑
-- MigrateAnchorPoints + LoadMoverPosition 인라인 마이그레이션 공용
local ATTACH_TO_PROXY = {
    -- CDM 뷰어 → 프록시
    ["EssentialCooldownViewer"] = "DDingUI_Anchor_Cooldowns",
    ["UtilityCooldownViewer"]   = "DDingUI_Anchor_Utility",
    ["BuffIconCooldownViewer"]  = "DDingUI_Anchor_Buffs",
    -- DDingUI 그룹 → 프록시
    ["DDingUI_Group_Cooldowns"] = "DDingUI_Anchor_Cooldowns",
    ["DDingUI_Group_Utility"]   = "DDingUI_Anchor_Utility",
    ["DDingUI_Group_Buffs"]     = "DDingUI_Anchor_Buffs",
    -- 구버전 호환 (v1.2.3 이전: 리소스바가 PowerBar 프레임 직접 참조)
    ["DDingUIPowerBar"]         = "DDingUI_Anchor_Cooldowns",
}

-- [FIX] 동적 그룹 등 런타임에 MoverToModuleMapping 추가 API
function Movers:RegisterModuleMapping(moverName, mapping)
    if not moverName or not mapping then return end
    MoverToModuleMapping[moverName] = mapping
end

-- 앵커 포인트 변환 (모듈 설정 ↔ 실제 SetPoint)
-- TOP 앵커: 바를 anchor 위에 배치 → barAnchorPoint = BOTTOM
-- BOTTOM 앵커: 바를 anchor 아래에 배치 → barAnchorPoint = TOP
local function AnchorToBarAnchor(anchorPoint)
    if anchorPoint == "TOP" then
        return "BOTTOM"
    elseif anchorPoint == "BOTTOM" then
        return "TOP"
    else
        return anchorPoint
    end
end

-- 역변환 (실제 SetPoint → 모듈 설정)
local function BarAnchorToAnchor(barAnchorPoint)
    if barAnchorPoint == "BOTTOM" then
        return "TOP"
    elseif barAnchorPoint == "TOP" then
        return "BOTTOM"
    else
        return barAnchorPoint
    end
end

-- 프레임의 특정 anchor point 위치 반환 (GetCenter 대신 사용)
local function GetPointPosition(frame, anchorPoint)
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

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local function Round(num)
    return math.floor(num + 0.5)
end

local function GetPoint(obj)
    local point, anchor, secondaryPoint, x, y = obj:GetPoint()
    if not anchor then anchor = UIParent end
    local anchorName = anchor:GetName() or "UIParent"
    return string.format("%s,%s,%s,%d,%d",
        point or "CENTER",
        anchorName,
        secondaryPoint or point or "CENTER",
        Round(x or 0),
        Round(y or 0)
    )
end

local function SetPoint(obj, pointString)
    if not pointString then return end
    local point, anchorName, relativePoint, x, y = strsplit(",", pointString)
    local anchor = _G[anchorName] or UIParent
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    -- [FIX] UIParent 앵커는 무조건 CENTER/CENTER 강제
    if anchor == UIParent then
        point = "CENTER"
        relativePoint = "CENTER"
    end
    obj:ClearAllPoints()
    obj:SetPoint(point, anchor, relativePoint, x, y)
end

--------------------------------------------------------------------------------
-- Undo/Redo Functions (GetPoint/SetPoint 정의 이후에 배치)
--------------------------------------------------------------------------------

function Movers:PushUndo(moverName, oldPoint)
    if not moverName or not oldPoint then return end

    -- Redo 스택 초기화 (새 동작이 들어오면)
    wipe(self.RedoStack)

    -- Undo 스택에 추가
    table.insert(self.UndoStack, {
        name = moverName,
        point = oldPoint,
    })

    -- 최대 개수 초과 시 오래된 것 제거
    while #self.UndoStack > self.MAX_UNDO do
        table.remove(self.UndoStack, 1)
    end

    -- UI 업데이트
    if self.NudgeFrame then
        self.NudgeFrame:UpdateUndoRedoButtons()
    end
end

function Movers:Undo()
    if #self.UndoStack == 0 then return end

    local entry = table.remove(self.UndoStack)
    local holder = self.CreatedMovers[entry.name]
    if not holder then return end

    -- 현재 위치를 Redo 스택에 저장
    local currentPoint = GetPoint(holder.mover)
    table.insert(self.RedoStack, {
        name = entry.name,
        point = currentPoint,
    })

    -- 이전 위치로 복원
    SetPoint(holder.mover, entry.point)
    self:UpdateParentPosition(entry.name)
    self:SaveMoverPosition(entry.name)

    -- 선택된 mover 업데이트
    if self.SelectedMover and self.SelectedMover.name == entry.name then
        if self.NudgeFrame then
            self.NudgeFrame:UpdateInfo()
        end
    end

    -- UI 업데이트
    if self.NudgeFrame then
        self.NudgeFrame:UpdateUndoRedoButtons()
    end
end

function Movers:Redo()
    if #self.RedoStack == 0 then return end

    local entry = table.remove(self.RedoStack)
    local holder = self.CreatedMovers[entry.name]
    if not holder then return end

    -- 현재 위치를 Undo 스택에 저장 (PushUndo 사용하면 Redo가 초기화되므로 직접 추가)
    local currentPoint = GetPoint(holder.mover)
    table.insert(self.UndoStack, {
        name = entry.name,
        point = currentPoint,
    })

    -- Redo 위치로 복원
    SetPoint(holder.mover, entry.point)
    self:UpdateParentPosition(entry.name)
    self:SaveMoverPosition(entry.name)

    -- 선택된 mover 업데이트
    if self.SelectedMover and self.SelectedMover.name == entry.name then
        if self.NudgeFrame then
            self.NudgeFrame:UpdateInfo()
        end
    end

    -- UI 업데이트
    if self.NudgeFrame then
        self.NudgeFrame:UpdateUndoRedoButtons()
    end
end

function Movers:ClearUndoRedo()
    wipe(self.UndoStack)
    wipe(self.RedoStack)
    if self.NudgeFrame then
        self.NudgeFrame:UpdateUndoRedoButtons()
    end
end

--------------------------------------------------------------------------------
-- ElvUI Style Position Calculation (9-point system)
--------------------------------------------------------------------------------

function Movers:CalculateMoverPoints(mover, nudgeX, nudgeY)
    local centerX, centerY = UIParent:GetCenter()
    local width = UIParent:GetRight()
    local x, y = mover:GetCenter()

    if not x or not y then
        return 0, 0, "CENTER", "CENTER", "CENTER"
    end

    local point = "BOTTOM"
    local nudgePoint = "BOTTOM"
    local nudgeInversePoint = "TOP"

    -- 세로 위치 판단 (상단/하단)
    if y >= centerY then
        point = "TOP"
        nudgePoint = "TOP"
        nudgeInversePoint = "BOTTOM"
        y = -(UIParent:GetTop() - mover:GetTop())
    else
        y = mover:GetBottom()
    end

    -- 가로 위치 판단 (좌/중/우)
    if x >= (width * 2 / 3) then
        point = point .. "RIGHT"
        nudgePoint = "RIGHT"
        nudgeInversePoint = "LEFT"
        x = mover:GetRight() - width
    elseif x <= (width / 3) then
        point = point .. "LEFT"
        nudgePoint = "LEFT"
        nudgeInversePoint = "RIGHT"
        x = mover:GetLeft()
    else
        x = x - centerX
    end

    -- 미세 조정 (Nudge) 적용
    x = x + (nudgeX or 0)
    y = y + (nudgeY or 0)

    return Round(x), Round(y), point, nudgePoint, nudgeInversePoint
end

--------------------------------------------------------------------------------
-- Snap Functions
--------------------------------------------------------------------------------

local function GetSnapTargets(excludeMover)
    local targets = {}

    -- 다른 Mover들
    if Movers.Settings.snapToFrames then
        for name, holder in pairs(Movers.CreatedMovers) do
            if holder.mover and holder.mover ~= excludeMover and holder.mover:IsShown() then
                local left, bottom, width, height = holder.mover:GetRect()
                if left and bottom then
                    table.insert(targets, {
                        left = left,
                        right = left + width,
                        top = bottom + height,
                        bottom = bottom,
                        centerX = left + width/2,
                        centerY = bottom + height/2,
                        name = name,
                    })
                end
            end
        end
    end

    -- [CDM-P3] UF 프레임도 스냅 대상에 포함 (양방향 등록)
    if Movers.Settings.snapToFrames and DDingUI.UF_ANCHOR_FRAMES then
        for _, uf in ipairs(DDingUI.UF_ANCHOR_FRAMES) do
            local frame = _G[uf.name]
            if frame and frame ~= excludeMover and frame:IsShown() then
                local left, bottom, w, h = frame:GetRect()
                if left and bottom and w > 0 and h > 0 then
                    -- 중복 방지: CreatedMovers에 이미 등록된 프레임은 스킵
                    local isDuplicate = false
                    for _, holder in pairs(Movers.CreatedMovers) do
                        if holder.parent == frame or holder.mover == frame then
                            isDuplicate = true
                            break
                        end
                    end
                    if not isDuplicate then
                        table.insert(targets, {
                            left = left,
                            right = left + w,
                            top = bottom + h,
                            bottom = bottom,
                            centerX = left + w/2,
                            centerY = bottom + h/2,
                            name = uf.name,
                        })
                    end
                end
            end
        end
    end

    return targets
end

local function CalculateSnap(x, y, width, height, excludeMover)
    local settings = Movers.Settings
    if not settings.snapEnabled then return x, y, nil end

    local threshold = settings.snapThreshold
    local snapX, snapY = x, y
    local snapInfo = nil

    local frameLeft = x - width/2
    local frameRight = x + width/2
    local frameTop = y + height/2
    local frameBottom = y - height/2

    -- 화면 중앙 스냅
    if settings.snapToCenter then
        local screenCenterX, screenCenterY = UIParent:GetCenter()

        -- 수평 중앙
        if math.abs(x - screenCenterX) < threshold then
            snapX = screenCenterX
            snapInfo = "CENTER_H"
        end

        -- 수직 중앙
        if math.abs(y - screenCenterY) < threshold then
            snapY = screenCenterY
            snapInfo = snapInfo and "CENTER" or "CENTER_V"
        end
    end

    -- 그리드 스냅
    if settings.snapToGrid then
        local gridSize = settings.gridSize
        if not gridSize or gridSize <= 0 then gridSize = 32 end

        local nearestGridX = Round(x / gridSize) * gridSize
        local nearestGridY = Round(y / gridSize) * gridSize

        if math.abs(x - nearestGridX) < threshold and snapInfo ~= "CENTER_H" and snapInfo ~= "CENTER" then
            snapX = nearestGridX
        end

        if math.abs(y - nearestGridY) < threshold and snapInfo ~= "CENTER_V" and snapInfo ~= "CENTER" then
            snapY = nearestGridY
        end
    end

    -- 다른 프레임 스냅
    if settings.snapToFrames then
        local targets = GetSnapTargets(excludeMover)

        for _, target in ipairs(targets) do
            -- 좌측 엣지 → 타겟 우측 엣지
            if math.abs(frameLeft - target.right) < threshold then
                snapX = target.right + width/2
            end
            -- 우측 엣지 → 타겟 좌측 엣지
            if math.abs(frameRight - target.left) < threshold then
                snapX = target.left - width/2
            end
            -- 좌측 엣지 정렬
            if math.abs(frameLeft - target.left) < threshold then
                snapX = target.left + width/2
            end
            -- 우측 엣지 정렬
            if math.abs(frameRight - target.right) < threshold then
                snapX = target.right - width/2
            end

            -- 상단 엣지 → 타겟 하단 엣지
            if math.abs(frameTop - target.bottom) < threshold then
                snapY = target.bottom - height/2
            end
            -- 하단 엣지 → 타겟 상단 엣지
            if math.abs(frameBottom - target.top) < threshold then
                snapY = target.top + height/2
            end
            -- 상단 엣지 정렬
            if math.abs(frameTop - target.top) < threshold then
                snapY = target.top - height/2
            end
            -- 하단 엣지 정렬
            if math.abs(frameBottom - target.bottom) < threshold then
                snapY = target.bottom + height/2
            end

            -- 중앙 정렬
            if math.abs(x - target.centerX) < threshold then
                snapX = target.centerX
            end
            if math.abs(y - target.centerY) < threshold then
                snapY = target.centerY
            end
        end
    end

    return snapX, snapY, snapInfo
end

--------------------------------------------------------------------------------
-- Drag Handlers (OnUpdate 방식)
--------------------------------------------------------------------------------

local function OnUpdateDrag(self, elapsed)
    if not isDragging or not dragFrame then return end

    local scale = dragFrame:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x = x / scale
    y = y / scale

    -- 커서 위치에 오프셋 적용
    local targetX = x + dragOffsetX
    local targetY = y + dragOffsetY

    -- 스냅 계산
    local width, height = dragFrame:GetSize()
    local snapX, snapY = CalculateSnap(targetX, targetY, width, height, dragFrame)

    dragFrame:ClearAllPoints()
    dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", snapX, snapY)

    -- 드래그 중 parent(bar)도 mover를 따라가도록 업데이트
    if dragFrame.parent then
        dragFrame.parent:ClearAllPoints()
        dragFrame.parent:SetPoint("CENTER", UIParent, "BOTTOMLEFT", snapX, snapY)
    end

    -- Update nudge frame coordinates during drag
    if Movers.NudgeFrame and Movers.NudgeFrame:IsShown() then
        Movers.NudgeFrame:UpdateInfo()
    end
end

local updateFrame = CreateFrame("Frame")

local function OnDragStart(mover)
    if InCombatLockdown() then return end
    -- [FIX] 프레임 피커 활성 중에는 드래그 방지
    if DDingUI._framePickerActive then return end

    -- Show grid during drag (always show while dragging for snap reference)
    if not Movers.Settings.gridEnabled then
        Movers:ShowGrid()
        mover._tempGridShown = true
    end

    -- Undo용 초기 위치 저장
    mover._dragStartPoint = GetPoint(mover)

    -- Calculate offset from mouse to frame center
    local scale = mover:GetEffectiveScale()
    local mouseX, mouseY = GetCursorPosition()
    mouseX = mouseX / scale
    mouseY = mouseY / scale

    local frameX, frameY = mover:GetCenter()
    if not frameX or not frameY then return end
    dragOffsetX = frameX - mouseX
    dragOffsetY = frameY - mouseY

    -- Start dragging
    dragFrame = mover
    isDragging = true
    updateFrame:SetScript("OnUpdate", OnUpdateDrag)

    -- Update state
    Movers.SelectedMover = mover

    -- Update nudge frame
    if Movers.NudgeFrame then
        Movers.NudgeFrame:UpdateSelection()
    end
end

local function OnDragStop(mover)
    if InCombatLockdown() then return end
    if not isDragging then return end

    -- Stop dragging
    isDragging = false
    dragFrame = nil
    updateFrame:SetScript("OnUpdate", nil)

    -- Hide grid after drag only if it was temporarily shown
    if mover._tempGridShown then
        Movers:HideGrid()
        -- Restore grid checkbox state
        if Movers.NudgeFrame and Movers.NudgeFrame.gridCheckbox then
            Movers.NudgeFrame.gridCheckbox:SetChecked(false)
        end
        mover._tempGridShown = nil
    end

    -- 버프 트래커는 9-point 재계산 전에 현재 위치로 저장 (center 변경 방지)
    local isBuffTracker = string.match(mover.name, "^DDingUI_BuffTracker%w+_%d+$")
    if isBuffTracker then
        Movers:SaveMoverPosition(mover.name)
    end

    -- [FIX] 드래그 종료 시 앵커 계산
    -- 1. 다른 프레임에 스냅됐으면 → 스냅 방향에 따라 앵커/기준점 자동 결정
    -- 2. 스냅 안 됐으면 → 기존 기준점 유지, 오프셋만 재계산
    local holder = Movers.CreatedMovers[mover.name]
    local mapping = holder and MoverToModuleMapping[mover.name]
    local cfg = mapping and DDingUI.db and ResolvePath(DDingUI.db.profile, mapping.path)

    -- ============================================================
    -- 스냅 감지: 인접한 다른 mover와의 엣지 관계 분석
    -- ============================================================
    local SNAP_DETECT_THRESHOLD = Movers.Settings.snapThreshold or 8
    local snapTarget, snapSelfPt, snapAnchorPt = nil, nil, nil

    if mapping and mapping.attachKey and Movers.Settings.snapToFrames then
        local myRect = { mover:GetRect() }  -- left, bottom, width, height
        if myRect[1] then
            local myLeft = myRect[1]
            local myBottom = myRect[2]
            local myWidth = myRect[3]
            local myHeight = myRect[4]
            local myRight = myLeft + myWidth
            local myTop = myBottom + myHeight
            local myCenterX = myLeft + myWidth / 2
            local myCenterY = myBottom + myHeight / 2

            local bestDist = SNAP_DETECT_THRESHOLD
            local targets = GetSnapTargets(mover)

            -- [FIX] 순환 앵커 방지: 현재 mover의 parent에 이미 앵커된 프레임 제외
            -- 예: PowerBar가 Cooldowns에 앵커 → Cooldowns 드래그 시 PowerBar는 스냅 대상에서 제외
            local myParent = holder and holder.parent
            local function IsAnchoredToMe(targetMoverName)
                local tHolder = Movers.CreatedMovers[targetMoverName]
                if not tHolder or not tHolder.parent then return false end
                -- 타겟 프레임의 앵커 체인을 추적하여 myParent가 있는지 확인
                local current = tHolder.parent
                for _ = 1, 10 do
                    if not current or current == UIParent then return false end
                    local ok, _, nextAnchor = pcall(current.GetPoint, current, 1)
                    if not ok or not nextAnchor then return false end
                    if nextAnchor == myParent then return true end
                    current = nextAnchor
                end
                return false
            end

            for _, target in ipairs(targets) do
                -- [FIX] 이미 나에게 앵커된 프레임은 스냅 대상에서 제외 (상호 앵커 방지)
                if IsAnchoredToMe(target.name) then
                    -- skip: 이 프레임을 앵커 대상으로 하면 순환 참조 발생
                else
                -- 수평 겹침 체크 (X축으로 어느 정도 겹쳐야 상하 스냅으로 인정)
                local hOverlap = math.min(myRight, target.right) - math.max(myLeft, target.left)
                local minW = math.min(myWidth, target.right - target.left)
                local hOverlapRatio = minW > 0 and (hOverlap / minW) or 0

                -- 수직 겹침 체크 (Y축으로 어느 정도 겹쳐야 좌우 스냅으로 인정)
                local vOverlap = math.min(myTop, target.top) - math.max(myBottom, target.bottom)
                local minH = math.min(myHeight, target.top - target.bottom)
                local vOverlapRatio = minH > 0 and (vOverlap / minH) or 0

                -- A가 B 위에 (A.bottom ≈ B.top) → selfPt=BOTTOM, anchorPt=TOP
                if hOverlapRatio > 0.3 then
                    local dist = math.abs(myBottom - target.top)
                    if dist < bestDist then
                        bestDist = dist
                        snapTarget = target
                        snapSelfPt = "BOTTOM"
                        snapAnchorPt = "TOP"
                    end
                end

                -- A가 B 아래에 (A.top ≈ B.bottom) → selfPt=TOP, anchorPt=BOTTOM
                if hOverlapRatio > 0.3 then
                    local dist = math.abs(myTop - target.bottom)
                    if dist < bestDist then
                        bestDist = dist
                        snapTarget = target
                        snapSelfPt = "TOP"
                        snapAnchorPt = "BOTTOM"
                    end
                end

                -- A 왼쪽에 B (A.right ≈ B.left) → selfPt=RIGHT, anchorPt=LEFT
                if vOverlapRatio > 0.3 then
                    local dist = math.abs(myRight - target.left)
                    if dist < bestDist then
                        bestDist = dist
                        snapTarget = target
                        snapSelfPt = "RIGHT"
                        snapAnchorPt = "LEFT"
                    end
                end

                -- A 오른쪽에 B (A.left ≈ B.right) → selfPt=LEFT, anchorPt=RIGHT
                if vOverlapRatio > 0.3 then
                    local dist = math.abs(myLeft - target.right)
                    if dist < bestDist then
                        bestDist = dist
                        snapTarget = target
                        snapSelfPt = "LEFT"
                        snapAnchorPt = "RIGHT"
                    end
                end
                end -- else (IsAnchoredToMe)
            end
        end
    end

    if snapTarget and snapSelfPt and snapAnchorPt then
        -- ============================================================
        -- 스냅 감지됨: 대상 프레임에 앵커 + 기준점 자동 설정
        -- ============================================================
        local targetHolder = Movers.CreatedMovers[snapTarget.name]
        local targetFrame = targetHolder and targetHolder.parent
        local targetName = targetFrame and targetFrame:GetName()

        -- 대상 프레임이 유효하면 앵커 변경
        if targetFrame and targetName then
            local selfX, selfY = GetPointPosition(mover, snapSelfPt)
            local anchorX, anchorY = GetPointPosition(targetFrame, snapAnchorPt)

            if selfX and anchorX then
                local newOffsetX = Round(selfX - anchorX)
                local newOffsetY = Round(selfY - anchorY)

                mover:ClearAllPoints()
                mover:SetPoint(snapSelfPt, targetFrame, snapAnchorPt, newOffsetX, newOffsetY)

                -- 모듈 설정에 앵커 정보 저장
                if cfg then
                    if mapping.attachKey then cfg[mapping.attachKey] = targetName end
                    if mapping.pointKey then cfg[mapping.pointKey] = snapAnchorPt end
                    if mapping.selfPointKey then cfg[mapping.selfPointKey] = snapSelfPt end
                end

                -- 사용자 피드백
                print(string.format(
                    "|cffffffffDDing|r|cffffa300UI|r: |cff00ff00%s|r → |cff80c0ff%s|r (|cffffcc00%s|r → |cffffcc00%s|r)",
                    mover.displayText or mover.name,
                    targetName,
                    snapSelfPt,
                    snapAnchorPt
                ))
            end
        end
    else
        -- ============================================================
        -- 스냅 미감지: 기존 앵커 유지 또는 거리 기반 앵커 해제
        -- ============================================================
        local origAttachTo = (mapping and mapping.attachKey and cfg and cfg[mapping.attachKey]) or "UIParent"
        local origAnchorFrame = DDingUI:ResolveAnchorFrame(origAttachTo)

        -- [FIX] 거리 기반 앵커 해제: 기존 앵커 프레임에서 충분히 멀어지면 앵커 분리
        local DETACH_THRESHOLD = (Movers.Settings.snapThreshold or 8) * 3
        local shouldDetach = false

        if origAnchorFrame and origAnchorFrame ~= UIParent and origAnchorFrame:GetCenter() then
            -- 현재 mover 위치와 기존 앵커 프레임 간 최소 엣지 거리 계산
            local myRect = { mover:GetRect() }
            local tRect = { origAnchorFrame:GetRect() }
            if myRect[1] and tRect[1] then
                local myL, myB, myW, myH = myRect[1], myRect[2], myRect[3], myRect[4]
                local tL, tB, tW, tH = tRect[1], tRect[2], tRect[3], tRect[4]
                local myR, myT = myL + myW, myB + myH
                local tR, tT = tL + tW, tB + tH

                -- 수평/수직 최소 엣지 거리
                local hDist = 0
                if myR < tL then hDist = tL - myR
                elseif myL > tR then hDist = myL - tR end

                local vDist = 0
                if myT < tB then vDist = tB - myT
                elseif myB > tT then vDist = myB - tT end

                local edgeDist = math.sqrt(hDist * hDist + vDist * vDist)
                if edgeDist > DETACH_THRESHOLD then
                    shouldDetach = true
                end
            end
        end

        if shouldDetach or not origAnchorFrame or origAnchorFrame == UIParent or not origAnchorFrame:GetCenter() then
            -- 앵커 해제: UIParent 기준으로 전환
            if shouldDetach and cfg then
                -- 모듈 설정에서 앵커 정보 초기화 → UIParent는 항상 CENTER/CENTER
                if mapping.attachKey then cfg[mapping.attachKey] = "UIParent" end
                if mapping.pointKey then cfg[mapping.pointKey] = "CENTER" end
                if mapping.selfPointKey then cfg[mapping.selfPointKey] = "CENTER" end
            end
            -- [FIX] UIParent 앵커는 항상 CENTER/CENTER — 9-point 자동 계산 사용하지 않음
            -- CalculateMoverPoints는 가장 가까운 엣지 앵커를 반환하지만
            -- UIParent에서는 CENTER가 해상도/스케일 변경에 안정적
            local cx, cy = mover:GetCenter()
            local uiCX, uiCY = UIParent:GetCenter()
            local x = Round((cx or 0) - (uiCX or 0))
            local y = Round((cy or 0) - (uiCY or 0))
            mover:ClearAllPoints()
            mover:SetPoint("CENTER", UIParent, "CENTER", x, y)

            if shouldDetach then
                print(string.format(
                    "|cffffffffDDing|r|cffffa300UI|r: |cff00ff00%s|r → |cff80c0ffUIParent|r (|cffffcc00앵커 해제|r)",
                    mover.displayText or mover.name
                ))
            end
        else
            -- 앵커 유지: 기존 기준점 유지, 오프셋만 재계산
            local selfPt = (mapping and mapping.selfPointKey and cfg and cfg[mapping.selfPointKey]) or "CENTER"
            local anchorPt = (mapping and mapping.pointKey and cfg and cfg[mapping.pointKey]) or "CENTER"

            local moverSelfX, moverSelfY = GetPointPosition(mover, selfPt)
            local anchorPointX, anchorPointY = GetPointPosition(origAnchorFrame, anchorPt)

            if moverSelfX and anchorPointX then
                local newOffsetX = Round(moverSelfX - anchorPointX)
                local newOffsetY = Round(moverSelfY - anchorPointY)

                mover:ClearAllPoints()
                mover:SetPoint(selfPt, origAnchorFrame, anchorPt, newOffsetX, newOffsetY)
            end
        end
    end

    -- Undo 스택에 이전 위치 저장 (위치가 변경된 경우에만)
    local newPoint = GetPoint(mover)
    if mover._dragStartPoint and mover._dragStartPoint ~= newPoint then
        Movers:PushUndo(mover.name, mover._dragStartPoint)
    end
    mover._dragStartPoint = nil

    -- Save position (버프 트래커가 아닌 경우)
    if not isBuffTracker then
        Movers:SaveMoverPosition(mover.name)
        Movers:UpdateParentPosition(mover.name)
    end

    -- Update nudge frame
    if Movers.NudgeFrame and Movers.NudgeFrame:IsShown() then
        Movers.NudgeFrame:UpdateInfo()
    end
end

--------------------------------------------------------------------------------
-- Mover Frame Creation
--------------------------------------------------------------------------------

local function CreateMoverFrame(parent, name, displayText)
    local mover = CreateFrame("Button", name .. "_Mover", UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(100)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    -- Appearance (texture-based to avoid SetBackdrop taint)
    -- Background
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
    mover.bg = bg

    -- Border textures (1px)
    local borderSize = 1
    local borders = {}

    local top = mover:CreateTexture(nil, "BORDER")
    top:SetColorTexture(0.4, 0.6, 1, 1)
    top:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", mover, "TOPRIGHT", 0, 0)
    top:SetHeight(borderSize)
    borders.top = top

    local bottom = mover:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(0.4, 0.6, 1, 1)
    bottom:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(borderSize)
    borders.bottom = bottom

    local left = mover:CreateTexture(nil, "BORDER")
    left:SetColorTexture(0.4, 0.6, 1, 1)
    left:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT", 0, 0)
    left:SetWidth(borderSize)
    borders.left = left

    local right = mover:CreateTexture(nil, "BORDER")
    right:SetColorTexture(0.4, 0.6, 1, 1)
    right:SetPoint("TOPRIGHT", mover, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(borderSize)
    borders.right = right

    mover._borders = borders

    -- Helper to change border color (closure, no self needed)
    local function UpdateBorderColor(r, g, b, a)
        for _, tex in pairs(borders) do
            tex:SetColorTexture(r, g, b, a or 1)
        end
    end
    mover.UpdateBorderColor = UpdateBorderColor

    -- Text label
    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(displayText or name)
    text:SetTextColor(1, 1, 1, 1)
    mover.text = text

    -- Store references
    mover.name = name
    mover.parent = parent
    mover.displayText = displayText

    -- Drag handlers
    mover:SetScript("OnDragStart", OnDragStart)
    mover:SetScript("OnDragStop", OnDragStop)

    -- OnMouseUp to stop dragging
    mover:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and isDragging then
            OnDragStop(self)
        end
    end)

    -- Click handlers
    mover:SetScript("OnClick", function(self, button)
        -- [FIX] 프레임 피커 활성 중에는 mover 선택 방지 (앵커 선택 시 SelectedMover 바뀌는 버그)
        if DDingUI._framePickerActive then return end
        if button == "LeftButton" then
            -- Select this mover and show nudge frame
            Movers.SelectedMover = self
            if Movers.NudgeFrame then
                Movers.NudgeFrame:Show()
                Movers.NudgeFrame:UpdateSelection()
                -- NudgeFrame은 고정 위치 유지 (따라다니지 않음)
            end
        elseif button == "RightButton" then
            if IsShiftKeyDown() then
                Movers:ResetMoverPosition(self.name)
            else
                -- [FIX] 우클릭 → 해당 프레임의 설정 메뉴 열기
                local guiKey = Movers:GetGUIKeyFromMoverName(self.name)
                if guiKey then
                    Movers:ExitEditMode()
                    C_Timer.After(0.1, function()
                        DDingUI:OpenConfigGUI(nil, guiKey)
                    end)
                end
            end
        end
    end)

    mover:SetScript("OnEnter", function(self)
        self.UpdateBorderColor(1, 0.8, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.displayText or self.name, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Left-click: Select and adjust"] or "Left-click: Select and adjust", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Drag: Move frame"] or "Drag: Move frame", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Right-click: Open settings"] or "Right-click: Open settings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Shift+Right-click: Reset position"] or "Shift+Right-click: Reset position", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    mover:SetScript("OnLeave", function(self)
        if Movers.SelectedMover == self then
            self.UpdateBorderColor(0, 1, 0, 1)
        else
            self.UpdateBorderColor(0.4, 0.6, 1, 0.8)
        end
        GameTooltip:Hide()
    end)

    return mover
end

--------------------------------------------------------------------------------
-- Mover Registration
--------------------------------------------------------------------------------

function Movers:RegisterMover(parent, name, displayText, defaultPoint)
    if not parent or not name then return end
    if self.CreatedMovers[name] then return self.CreatedMovers[name].mover end

    local mover = CreateMoverFrame(parent, name, displayText)

    -- Store holder info
    self.CreatedMovers[name] = {
        parent = parent,
        mover = mover,
        displayText = displayText,
        defaultPoint = defaultPoint or GetPoint(parent),
    }

    -- Bidirectional reference
    parent.mover = mover

    -- Sync size with parent (minimum 1px for thin bars)
    local MIN_MOVER_HEIGHT = 1
    local function SyncSize()
        if parent:GetWidth() > 0 and parent:GetHeight() > 0 then
            local width = parent:GetWidth()
            local height = math.max(parent:GetHeight(), MIN_MOVER_HEIGHT)
            -- [FIX] 크기가 실제로 변했을 때만 SetSize 호출 → 편집모드 깜빡임 방지
            local curW, curH = mover:GetSize()
            if math.abs((curW or 0) - width) > 0.5 or math.abs((curH or 0) - height) > 0.5 then
                mover:SetSize(width, height)
            end
        else
            local curW, curH = mover:GetSize()
            if math.abs((curW or 0) - 100) > 0.5 or math.abs((curH or 0) - MIN_MOVER_HEIGHT) > 0.5 then
                mover:SetSize(100, MIN_MOVER_HEIGHT)
            end
        end
    end

    SyncSize()

    -- Hook size changes
    if parent.SetSize then
        hooksecurefunc(parent, "SetSize", SyncSize)
    end
    if parent.SetWidth then
        hooksecurefunc(parent, "SetWidth", function()
            local pw = parent:GetWidth()
            if pw > 0 then
                local curW = mover:GetWidth()
                if math.abs((curW or 0) - pw) > 0.5 then
                    mover:SetWidth(pw)
                end
            end
        end)
    end
    if parent.SetHeight then
        hooksecurefunc(parent, "SetHeight", function()
            local ph = parent:GetHeight()
            if ph > 0 then
                local curH = mover:GetHeight()
                if math.abs((curH or 0) - ph) > 0.5 then
                    mover:SetHeight(ph)
                end
            end
        end)
    end

    -- Load saved position or use default
    self:LoadMoverPosition(name)

    return mover
end

function Movers:UnregisterMover(name)
    local holder = self.CreatedMovers[name]
    if not holder then return end

    if holder.parent then
        holder.parent.mover = nil
    end

    holder.mover:Hide()
    holder.mover:SetParent(nil)
    self.CreatedMovers[name] = nil
end

--------------------------------------------------------------------------------
-- Position Management
--------------------------------------------------------------------------------

function Movers:SaveMoverPosition(name)
    local holder = self.CreatedMovers[name]
    if not holder then return end

    if not DDingUI.db then return end

    -- MoverToModuleMapping에 있는 프레임은 모듈 설정에만 저장
    -- (이동모드와 메뉴 설정이 같은 곳에 저장되어 최신 값이 적용됨)
    local mapping = MoverToModuleMapping[name]
    if mapping then
        self:SyncMoverToModuleSettings(name)
        return
    end

    -- 버프 트래커 개별 프레임 처리 (DDingUI_BuffTrackerBar_1, DDingUI_BuffTrackerIcon_2 등)
    local buffTrackerType, buffTrackerIndex = string.match(name, "^DDingUI_BuffTracker(%w+)_(%d+)$")
    if buffTrackerType and buffTrackerIndex then
        local idx = tonumber(buffTrackerIndex)
        if idx and DDingUI.db then
            -- 전문화별 설정 사용 (db.global.trackedBuffsPerSpec - 계정 공유)
            local specIndex = GetSpecialization and GetSpecialization()
            local specID = specIndex and GetSpecializationInfo(specIndex) or nil
            local globalStore = DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec
            local trackedBuffs = nil

            if specID and globalStore and globalStore[specID] then
                trackedBuffs = globalStore[specID]
            elseif DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.trackedBuffs then
                -- 폴백: 레거시 경로
                trackedBuffs = DDingUI.db.profile.buffTrackerBar.trackedBuffs
            end

            if trackedBuffs and trackedBuffs[idx] then
                if not trackedBuffs[idx].settings then
                    trackedBuffs[idx].settings = {}
                end

                -- anchor 프레임 기준 상대 좌표 계산 -- [FIX: anchor sync]
                -- 모버의 실제 앵커 상태를 우선 사용 (넛지 패널에서 변경 시 반영)
                local _, moverRelTo, moverRelPoint = holder.mover:GetPoint(1)
                local attachTo = (moverRelTo and moverRelTo:GetName())
                                 or trackedBuffs[idx].settings.attachTo
                                 or (DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.attachTo)
                                 or "DDingUI_Anchor_Cooldowns" -- [PROXY] 프록시 앵커 폴백
                local anchorFrame = DDingUI:ResolveAnchorFrame(attachTo)

                -- displayType에 따라 적절한 anchorPoint 가져오기
                -- 모버의 실제 앵커 포인트를 우선 사용 -- [FIX: anchor sync]
                local globalCfg = DDingUI.db.profile.buffTrackerBar or {}
                local displayType = trackedBuffs[idx].displayType or "bar"
                local anchorPoint = moverRelPoint
                if not anchorPoint then
                    if displayType == "ring" then
                        anchorPoint = trackedBuffs[idx].settings.ringAnchorPoint or "CENTER"
                    elseif buffTrackerType == "Icon" then
                        anchorPoint = trackedBuffs[idx].settings.iconAnchorPoint or
                                      globalCfg.anchorPoint or "BOTTOM"
                    elseif buffTrackerType == "Text" then
                        anchorPoint = trackedBuffs[idx].settings.textModeAnchorPoint or
                                      globalCfg.anchorPoint or "BOTTOM"
                    else
                        anchorPoint = trackedBuffs[idx].settings.anchorPoint or
                                      globalCfg.anchorPoint or "BOTTOM"
                    end
                end

                local relX, relY = 0, 0
                -- [FIX] 무버의 실제 selfPoint 기준으로 좌표 계산 (CENTER 하드코딩 제거)
                local moverSelfPoint = select(1, holder.mover:GetPoint(1)) or "CENTER"
                local moverRefX, moverRefY = GetPointPosition(holder.mover, moverSelfPoint)
                if not moverRefX then
                    moverRefX, moverRefY = holder.mover:GetCenter()
                end
                if anchorFrame and anchorFrame:IsShown() and moverRefX then
                    -- anchor의 anchorPoint 위치 계산 (CENTER가 아닌 실제 사용되는 anchorPoint)
                    local anchorPointX, anchorPointY = GetPointPosition(anchorFrame, anchorPoint)
                    if anchorPointX then
                        relX = moverRefX - anchorPointX
                        relY = moverRefY - anchorPointY
                    end
                elseif moverRefX then
                    -- anchor가 없으면 UIParent 중심 기준
                    local uiCenterX, uiCenterY = UIParent:GetCenter()
                    if uiCenterX then
                        relX = moverRefX - uiCenterX
                        relY = moverRefY - uiCenterY
                    end
                end

                -- 타입별로 다른 설정 키 사용 (anchor 기준 상대 좌표 relX, relY 사용)
                if buffTrackerType == "Bar" then
                    -- 현재 displayType 확인하여 적절한 offset 저장 (displayType은 위에서 이미 선언됨)
                    if displayType == "ring" then
                        trackedBuffs[idx].settings.ringOffsetX = relX
                        trackedBuffs[idx].settings.ringOffsetY = relY
                    else
                        trackedBuffs[idx].settings.offsetX = relX
                        trackedBuffs[idx].settings.offsetY = relY
                    end
                elseif buffTrackerType == "Icon" then
                    trackedBuffs[idx].settings.iconOffsetX = relX
                    trackedBuffs[idx].settings.iconOffsetY = relY
                elseif buffTrackerType == "Text" then
                    trackedBuffs[idx].settings.textModeOffsetX = relX
                    trackedBuffs[idx].settings.textModeOffsetY = relY
                end

                -- 앵커 포인트/프레임 변경도 설정에 동기화 -- [FIX: anchor sync]
                trackedBuffs[idx].settings.attachTo = attachTo
                if displayType == "ring" then
                    trackedBuffs[idx].settings.ringAnchorPoint = anchorPoint
                elseif buffTrackerType == "Icon" then
                    trackedBuffs[idx].settings.iconAnchorPoint = anchorPoint
                elseif buffTrackerType == "Text" then
                    trackedBuffs[idx].settings.textModeAnchorPoint = anchorPoint
                else
                    trackedBuffs[idx].settings.anchorPoint = anchorPoint
                end

                -- 버프 트래커 업데이트
                if DDingUI.UpdateBuffTrackerBar then
                    DDingUI:UpdateBuffTrackerBar()
                end
                return
            end
        end
    end

    -- CustomIcons 동적 그룹 프레임 처리 (DDingUI_DynGroup_*) -- [FIX: anchor sync]
    local dynGroupKey = string.match(name, "^DDingUI_DynGroup_(.+)$")
    if dynGroupKey and DDingUI.db and DDingUI.db.profile.dynamicIcons then
        local dynDB = DDingUI.db.profile.dynamicIcons
        local settings = nil
        if dynGroupKey == "ungrouped" then
            settings = dynDB.ungroupedSettings
        elseif dynDB.iconData and dynDB.iconData[dynGroupKey] and dynDB.ungrouped and dynDB.ungrouped[dynGroupKey] then
            dynDB.ungroupedPositions = dynDB.ungroupedPositions or {}
            settings = dynDB.ungroupedPositions[dynGroupKey]
        elseif dynDB.groups and dynDB.groups[dynGroupKey] then
            settings = dynDB.groups[dynGroupKey] and dynDB.groups[dynGroupKey].settings
        end

        if settings then
            local moverPt, moverRelTo, moverRelPt, moverX, moverY = holder.mover:GetPoint(1)
            local anchorName = (moverRelTo and moverRelTo:GetName()) or ""
            -- [FIX] UIParent 앵커는 무조건 CENTER/CENTER 강제
            if anchorName == "" or anchorName == "UIParent" then
                anchorName = "UIParent"
                moverPt = "CENTER"
                moverRelPt = "CENTER"
            end
            settings.anchorFrame = anchorName
            settings.anchorTo = moverRelPt or settings.anchorTo or "CENTER"
            settings.anchorFrom = moverPt or settings.anchorFrom or "CENTER"
            if not settings.position then settings.position = {} end
            settings.position.x = moverX or 0
            settings.position.y = moverY or 0
        end
    end

    -- MoverToModuleMapping에 없는 프레임은 기존 방식 (movers 테이블에 저장)
    if not DDingUI.db.profile.movers then
        DDingUI.db.profile.movers = {}
    end

    DDingUI.db.profile.movers[name] = GetPoint(holder.mover)

    -- [FIX] 무버 위치 변경 시 스펙별 스냅샷에 반영
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

-- [GROUP SYSTEM] 점으로 구분된 경로 해석 헬퍼
-- "groupSystem.groups.Buffs" → profile.groupSystem.groups.Buffs
ResolvePath = function(root, path)
    if not root or not path then return nil end
    -- 단일 레벨 경로 (기존 호환)
    if not path:find("%.") then
        return root[path]
    end
    -- 다중 레벨 경로
    local current = root
    for segment in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[segment]
        if current == nil then return nil end
    end
    return current
end

function Movers:LoadMoverPosition(name)
    local holder = self.CreatedMovers[name]
    if not holder then return end

    -- MoverToModuleMapping에 있는 프레임은 모듈 설정에서 읽음
    -- (이동모드와 메뉴 설정이 같은 곳에 저장되어 최신 값이 적용됨)
    local mapping = MoverToModuleMapping[name]
    -- [FIX] dot-path 해석: "groupSystem.groups.Buffs" → profile.groupSystem.groups.Buffs
    local mappedCfg = mapping and DDingUI.db and ResolvePath(DDingUI.db.profile, mapping.path)
    if mappedCfg then
        -- [FIX] 구 프로필 movers 문자열 → 모듈 설정 인라인 마이그레이션
        -- 구 버전에서는 MoverToModuleMapping 프레임도 profile.movers에 문자열로 저장했음
        -- AceDB 기본값 때문에 mappedCfg가 항상 존재하여 movers 폴백에 도달 못함
        local moversTable = DDingUI.db.profile.movers
        local savedMoverString = moversTable and moversTable[name]
        if savedMoverString and type(savedMoverString) == "string" then
            local mPoint, mAnchorName, mRelPoint, mX, mY = strsplit(",", savedMoverString)
            mX = tonumber(mX) or 0
            mY = tonumber(mY) or 0
            mRelPoint = mRelPoint or "CENTER"
            mPoint = mPoint or "CENTER"

            if DDingUI.db.profile.profileVersion then
                -- [마이그레이션 완료] 뷰어 → 프록시 변환 + movers 엔트리 삭제
                mAnchorName = ATTACH_TO_PROXY[mAnchorName] or mAnchorName or "UIParent"
                if mAnchorName == "UIParent" or mAnchorName == "" then
                    mAnchorName = "UIParent"
                    mRelPoint = "CENTER"
                    mPoint = "CENTER"
                end
                if mapping.xKey then mappedCfg[mapping.xKey] = mX end
                if mapping.yKey then mappedCfg[mapping.yKey] = mY end
                if mapping.attachKey then mappedCfg[mapping.attachKey] = mAnchorName end
                if mapping.pointKey then mappedCfg[mapping.pointKey] = mRelPoint end
                if mapping.selfPointKey then mappedCfg[mapping.selfPointKey] = mPoint end
                moversTable[name] = nil
            else
                -- [미마이그레이션] 오프셋/포인트만 전달, 앵커 이름 원본 유지
                -- ResolveAnchorFrame이 런타임에 뷰어→프록시 자동 치환
                if mapping.xKey then mappedCfg[mapping.xKey] = mX end
                if mapping.yKey then mappedCfg[mapping.yKey] = mY end
                if mapping.pointKey then mappedCfg[mapping.pointKey] = mRelPoint end
                if mapping.selfPointKey then mappedCfg[mapping.selfPointKey] = mPoint end
                -- attachTo, movers 엔트리 유지 (마이그레이션 대기)
            end
        end
        local cfg = mappedCfg
        -- DDingUI:Scale 사용 (픽셀퍼펙트 스케일, v1.1.5.5와 일관성)
        local anchorPoint = cfg[mapping.pointKey] or "CENTER"
        local attachTo = cfg[mapping.attachKey] or "UIParent"
        local offsetX = DDingUI:Scale(cfg[mapping.xKey] or 0)
        local offsetY = DDingUI:Scale(cfg[mapping.yKey] or 0)
        local anchorFrame = DDingUI:ResolveAnchorFrame(attachTo)

        -- 저장된 기준점 사용 -- [FIX: selfPoint support]
        local selfPoint = mapping.selfPointKey and cfg[mapping.selfPointKey]
        if not selfPoint then
            selfPoint = "CENTER"
        end



        -- [FIX] UIParent 앵커는 무조건 CENTER/CENTER 강제
        if anchorFrame == UIParent then
            anchorPoint = "CENTER"
            selfPoint = "CENTER"
        end
        holder.mover:ClearAllPoints()
        holder.mover:SetPoint(selfPoint, anchorFrame, anchorPoint, offsetX, offsetY)

        self:UpdateParentPosition(name)
        return
    end

    -- 버프 트래커 개별 프레임 처리 (DDingUI_BuffTrackerBar_1, DDingUI_BuffTrackerIcon_2 등)
    local buffTrackerType, buffTrackerIndex = string.match(name, "^DDingUI_BuffTracker(%w+)_(%d+)$")
    if buffTrackerType and buffTrackerIndex then
        local idx = tonumber(buffTrackerIndex)
        if idx and DDingUI.db then
            -- 전문화별 설정 사용 (db.global.trackedBuffsPerSpec - 계정 공유)
            local specIndex = GetSpecialization and GetSpecialization()
            local specID = specIndex and GetSpecializationInfo(specIndex) or nil
            local globalStore = DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec
            local trackedBuffs = nil

            if specID and globalStore and globalStore[specID] then
                trackedBuffs = globalStore[specID]
            elseif DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.trackedBuffs then
                -- 폴백: 레거시 경로
                trackedBuffs = DDingUI.db.profile.buffTrackerBar.trackedBuffs
            end

            if trackedBuffs and trackedBuffs[idx] and trackedBuffs[idx].settings then
                local settings = trackedBuffs[idx].settings

                local globalCfg = DDingUI.db.profile.buffTrackerBar or {}
                local displayType = trackedBuffs[idx].displayType or "bar"
                local offsetX, offsetY, anchorPoint, attachTo

                -- 타입별로 다른 설정 키 사용
                -- BuffTrackerBar.lua와 동일한 기본값 사용: 바=BOTTOM, 링=CENTER
                if buffTrackerType == "Bar" then
                    if displayType == "ring" then
                        offsetX = settings.ringOffsetX
                        offsetY = settings.ringOffsetY
                        anchorPoint = settings.ringAnchorPoint or "CENTER"
                    else
                        offsetX = settings.offsetX
                        offsetY = settings.offsetY
                        anchorPoint = settings.anchorPoint or globalCfg.anchorPoint or "BOTTOM"
                    end
                elseif buffTrackerType == "Icon" then
                    offsetX = settings.iconOffsetX
                    offsetY = settings.iconOffsetY
                    anchorPoint = settings.iconAnchorPoint or globalCfg.anchorPoint or "BOTTOM"
                elseif buffTrackerType == "Text" then
                    offsetX = settings.textModeOffsetX
                    offsetY = settings.textModeOffsetY
                    anchorPoint = settings.textModeAnchorPoint or globalCfg.anchorPoint or "BOTTOM"
                end

                attachTo = settings.attachTo or globalCfg.attachTo or "DDingUI_Anchor_Cooldowns" -- [PROXY] 프록시 앵커 폴백
                local anchorFrame = DDingUI:ResolveAnchorFrame(attachTo)

                if offsetX ~= nil and offsetY ~= nil then
                    -- [FIX] selfPoint를 설정에서 읽기 (BuffTrackerBar.lua와 일치)
                    local selfPoint
                    if buffTrackerType == "Bar" then
                        if displayType == "ring" then
                            selfPoint = settings.ringSelfPoint or (globalCfg and globalCfg.selfPoint) or "CENTER"
                        else
                            selfPoint = settings.selfPoint or (globalCfg and globalCfg.selfPoint) or "CENTER"
                        end
                    else
                        selfPoint = "CENTER"
                    end
                    -- [FIX] UIParent 앵커는 무조건 CENTER/CENTER 강제
                    if anchorFrame == UIParent then
                        anchorPoint = "CENTER"
                        selfPoint = "CENTER"
                    end
                    holder.mover:ClearAllPoints()
                    holder.mover:SetPoint(selfPoint, anchorFrame, anchorPoint, DDingUI:Scale(offsetX), DDingUI:Scale(offsetY))
                    self:UpdateParentPosition(name)
                    return
                end
            end
        end
    end

    -- CustomIcons 동적 그룹 프레임 (DDingUI_DynGroup_*) — dynamicIcons settings에서 읽기
    -- SaveMoverPosition의 DynGroup 처리(1095~1118행)와 대칭으로 로드
    local dynGroupKey = string.match(name, "^DDingUI_DynGroup_(.+)$")
    if dynGroupKey and DDingUI.db and DDingUI.db.profile.dynamicIcons then
        local dynDB = DDingUI.db.profile.dynamicIcons
        local settings = nil
        local isGroup = false
        local groupObj = nil
        if dynGroupKey == "ungrouped" then
            settings = dynDB.ungroupedSettings
        elseif dynDB.iconData and dynDB.iconData[dynGroupKey] and dynDB.ungrouped and dynDB.ungrouped[dynGroupKey] then
            dynDB.ungroupedPositions = dynDB.ungroupedPositions or {}
            settings = dynDB.ungroupedPositions[dynGroupKey]
        elseif dynDB.groups and dynDB.groups[dynGroupKey] then
            groupObj = dynDB.groups[dynGroupKey]
            settings = groupObj and groupObj.settings
            isGroup = true
        end

        if settings then
            -- [FIX] UIParent 앵커일 때 anchorFrom/anchorTo를 CENTER/CENTER로 고정
            -- UIParent에 TOPLEFT 등으로 앵커링하면 좌표 의미가 달라져 마이그레이션 시 위치 틀어짐
            local anchorFrameName = settings.anchorFrame or ""
            local isUIParent = (anchorFrameName == "" or anchorFrameName == "UIParent")
            if isUIParent then
                settings.anchorFrom = "CENTER"
                settings.anchorTo = "CENTER"
            end

            -- [MIGRATION] 그룹 아이콘 크기/종횡비 다수결 마이그레이션
            -- 개별 아이콘에만 설정되어 있고 그룹 settings에 없으면, 다수결로 그룹 설정에 적용
            if isGroup and groupObj and groupObj.icons and #(groupObj.icons) > 0
               and not settings._iconSizeMigrated then
                local sizeCounts = {}
                local aspectCounts = {}
                local totalIcons = 0
                for _, iconKey in ipairs(groupObj.icons) do
                    local iconData = dynDB.iconData and dynDB.iconData[iconKey]
                    if iconData and iconData.settings then
                        totalIcons = totalIcons + 1
                        -- iconSize
                        local s = iconData.settings.iconSize
                        if s then
                            sizeCounts[s] = (sizeCounts[s] or 0) + 1
                        end
                        -- aspectRatio
                        local a = iconData.settings.aspectRatio
                        if a then
                            -- 소수점 2자리로 키 정규화
                            local aKey = math.floor(a * 100 + 0.5) / 100
                            aspectCounts[aKey] = (aspectCounts[aKey] or 0) + 1
                        end
                    end
                end

                -- 다수결 iconSize 적용 (그룹 설정에 없을 때만)
                if not settings.iconSize and totalIcons > 0 then
                    local bestSize, bestCount = nil, 0
                    for s, c in pairs(sizeCounts) do
                        if c > bestCount then bestSize, bestCount = s, c end
                    end
                    if bestSize then
                        settings.iconSize = bestSize
                        -- 그룹 값과 동일한 개별 설정은 nil로 정리 (그룹 폴백 사용)
                        for _, iconKey in ipairs(groupObj.icons) do
                            local iconData = dynDB.iconData and dynDB.iconData[iconKey]
                            if iconData and iconData.settings and iconData.settings.iconSize == bestSize then
                                iconData.settings.iconSize = nil
                            end
                        end
                    end
                end

                -- 다수결 aspectRatio 적용
                if totalIcons > 0 then
                    local bestAspect, bestCount = nil, 0
                    for a, c in pairs(aspectCounts) do
                        if c > bestCount then bestAspect, bestCount = a, c end
                    end
                    if bestAspect and bestAspect ~= 1.0 and not settings.aspectRatio then
                        settings.aspectRatio = bestAspect
                    end
                end

                settings._iconSizeMigrated = true
            end

            if settings.position then
                local anchorFrom = settings.anchorFrom or "CENTER"
                local anchorTo = settings.anchorTo or anchorFrom
                local anchorFrame = DDingUI:ResolveAnchorFrame(anchorFrameName)
                local ox = settings.position.x or 0
                local oy = settings.position.y or 0

                holder.mover:ClearAllPoints()
                holder.mover:SetPoint(anchorFrom, anchorFrame, anchorTo, ox, oy)
                self:UpdateParentPosition(name)
                return
            end
        end
    end

    -- MoverToModuleMapping에 없는 프레임은 기존 방식 (movers 테이블에서 읽음)
    local savedPoint
    if DDingUI.db and DDingUI.db.profile.movers then
        savedPoint = DDingUI.db.profile.movers[name]
    end

    if savedPoint then
        SetPoint(holder.mover, savedPoint)
    else
        local point, anchor, relPoint, x, y = holder.parent:GetPoint(1)
        if point then
            -- [FIX] UIParent 앵커는 무조건 CENTER/CENTER 강제
            if (anchor or UIParent) == UIParent then
                point = "CENTER"
                relPoint = "CENTER"
            end
            holder.mover:ClearAllPoints()
            holder.mover:SetPoint(point, anchor or UIParent, relPoint or point, x or 0, y or 0)
        else
            holder.mover:ClearAllPoints()
            holder.mover:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end

    self:UpdateParentPosition(name)
end

function Movers:UpdateParentPosition(name)
    local holder = self.CreatedMovers[name]
    if not holder or not holder.parent then return end

    -- MoverToModuleMapping에 있는 프레임은 모듈이 자체적으로 위치 설정
    -- (barAnchorPoint 변환 등 모듈 특화 로직이 있으므로)
    -- 이동모드가 아닐 때는 모듈 설정 기반으로 위치가 설정되어야 함
    -- [FIX] 프록시 앵커(DDingUI_Anchor_*)는 예외: 프록시 자체가 마스터 프레임이므로
    -- UpdateParentPosition으로 mover→parent 위치 동기화가 항상 필요
    local mapping = MoverToModuleMapping[name]
    local isProxyAnchor = holder.parent and holder.parent._isProxyAnchor
    if mapping and not self.ConfigMode and not isProxyAnchor then
        -- 이동모드가 아니면 모듈이 자체적으로 위치 설정하도록 스킵
        -- 모듈의 UpdateLayout 등에서 처리됨
        return
    end

    -- 버프 트래커 개별 프레임: 이동모드 중 실시간 드래그 반영
    -- (드래그 끝나면 OnDragStop에서 UpdateParentPosition을 스킵하고 SaveMoverPosition만 사용)
    local buffTrackerType = string.match(name, "^DDingUI_BuffTracker(%w+)_%d+$")
    if buffTrackerType then
        if self.ConfigMode then
            local point, anchor, relPoint, x, y = holder.mover:GetPoint(1)
            if point then
                holder.parent:ClearAllPoints()
                holder.parent:SetPoint(point, anchor or UIParent, relPoint or point, x or 0, y or 0)
            end
        end
        return
    end

    local point, anchor, relPoint, x, y = holder.mover:GetPoint(1)
    if not point then return end

    -- 자기 자신에 앵커 방지 (방어 코드)
    if anchor == holder.parent then
        anchor = UIParent
        relPoint = point
        x, y = holder.mover:GetCenter()  -- 화면 중심 기준 위치 사용
        local uiCenterX, uiCenterY = UIParent:GetCenter()
        if x and uiCenterX then
            x = x - uiCenterX
            y = y - uiCenterY
        else
            x, y = 0, 0
        end
    end

    -- [FIX] 간접 순환 앵커 방지 (A→B→A 감지)
    -- anchor 프레임의 앵커 체인을 따라가서 holder.parent가 있으면 순환
    -- 예: PowerBar→Cooldowns 앵커 상태에서, Cooldowns→PowerBar SetPoint → 순환!
    if anchor and anchor ~= UIParent then
        local visited = { [holder.parent] = true }
        local current = anchor
        local maxDepth = 10
        local isCyclic = false
        for _ = 1, maxDepth do
            if not current or current == UIParent then break end
            if visited[current] then
                isCyclic = true
                break
            end
            visited[current] = true
            -- 다음 앵커 프레임 추적
            local ok, _, nextAnchor = pcall(current.GetPoint, current, 1)
            if ok and nextAnchor then
                current = nextAnchor
            else
                break
            end
        end
        if isCyclic then
            -- 순환 감지: UIParent 기준 절대 좌표로 폴백
            anchor = UIParent
            relPoint = "CENTER"
            point = "CENTER"
            x, y = holder.mover:GetCenter()
            local uiCenterX, uiCenterY = UIParent:GetCenter()
            if x and uiCenterX then
                x = x - uiCenterX
                y = y - uiCenterY
            else
                x, y = 0, 0
            end
        end
    end

    holder.parent:ClearAllPoints()
    holder.parent:SetPoint(point, anchor or UIParent, relPoint or point, x or 0, y or 0)
end

function Movers:ResetMoverPosition(name)
    local holder = self.CreatedMovers[name]
    if not holder then return end

    if DDingUI.db and DDingUI.db.profile.movers then
        DDingUI.db.profile.movers[name] = nil
    end

    -- MoverToModuleMapping에 해당하는 모듈 설정도 초기화
    local mapping = MoverToModuleMapping[name]
    -- [FIX] dot-path 해석
    local resetCfg = mapping and DDingUI.db and ResolvePath(DDingUI.db.profile, mapping.path)
    if resetCfg then
        local cfg = resetCfg
        if mapping.xKey then cfg[mapping.xKey] = 0 end
        if mapping.yKey then cfg[mapping.yKey] = 0 end
        if mapping.pointKey then cfg[mapping.pointKey] = "CENTER" end
        if mapping.selfPointKey then cfg[mapping.selfPointKey] = nil end -- [FIX: selfPoint support] 리셋 시 제거 → 레거시 동작 복원
        if mapping.attachKey then cfg[mapping.attachKey] = "UIParent" end
        cfg._moverSaved = nil  -- [FIX] 뷰어 마이그레이션 다시 허용
    end

    if holder.defaultPoint then
        SetPoint(holder.mover, holder.defaultPoint)
        self:UpdateParentPosition(name)
    end

    if Movers.NudgeFrame and Movers.NudgeFrame:IsShown() then
        Movers.NudgeFrame:UpdateInfo()
    end
end

function Movers:ResetAllPositions()
    for name in pairs(self.CreatedMovers) do
        self:ResetMoverPosition(name)
    end
end

-- 모든 저장된 Mover 위치를 적용 (모듈 설정보다 우선)
function Movers:ApplyAllSavedPositions()
    if not DDingUI.db or not DDingUI.db.profile.movers then return end

    for name, savedPoint in pairs(DDingUI.db.profile.movers) do
        local holder = self.CreatedMovers[name]
        if holder and holder.mover and savedPoint then
            SetPoint(holder.mover, savedPoint)
            self:UpdateParentPosition(name)
        end
    end
end

-- [FIX] GroupSystem 그룹 프레임 생성 후 매핑 모듈 위치 재적용
-- Movers init 시점에 DDingUI_Group_* 프레임이 없어 UIParent로 폴백한 경우
-- 그룹 프레임 생성 후 이 함수를 호출하여 올바른 앵커로 재연결
function Movers:ReloadMappedModulePositions()
    if not DDingUI.db or not DDingUI.db.profile then return end

    for name, holder in pairs(self.CreatedMovers) do
        local mapping = MoverToModuleMapping[name]
        if mapping and holder.mover then
            local cfg = ResolvePath(DDingUI.db.profile, mapping.path)
            if cfg then
                local attachTo = cfg[mapping.attachKey] or "UIParent"
                local anchorFrame = DDingUI:ResolveAnchorFrame(attachTo)
                if anchorFrame and anchorFrame ~= UIParent then
                    -- 앵커 프레임이 이제 사용 가능 → 위치 재적용
                    local anchorPoint = cfg[mapping.pointKey] or "CENTER"
                    local selfPoint = (mapping.selfPointKey and cfg[mapping.selfPointKey]) or "CENTER"
                    local offsetX = DDingUI:Scale(cfg[mapping.xKey] or 0)
                    local offsetY = DDingUI:Scale(cfg[mapping.yKey] or 0)



                    -- mover 재배치
                    holder.mover:ClearAllPoints()
                    holder.mover:SetPoint(selfPoint, anchorFrame, anchorPoint, offsetX, offsetY)
                    self:UpdateParentPosition(name)

                    -- 모듈 레이아웃 업데이트 트리거
                    if name == "DDingUI_PlayerCastBar" and DDingUI.UpdateCastBarLayout then
                        pcall(DDingUI.UpdateCastBarLayout, DDingUI)
                    elseif name == "DDingUI_PowerBar" and DDingUI.UpdatePowerBar then
                        pcall(DDingUI.UpdatePowerBar, DDingUI)
                    elseif name == "DDingUI_SecondaryPowerBar" then
                        local rb = DDingUI.ResourceBars
                        if rb and rb.UpdateSecondaryPowerBar then
                            pcall(rb.UpdateSecondaryPowerBar, rb)
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Mover Name → GUI Tree Key 매핑
--------------------------------------------------------------------------------

-- [FIX] 편집모드 우클릭 → 해당 프레임의 설정 메뉴 열기
local MOVER_TO_GUI = {
    ["DDingUI_PowerBar"]          = "resourceBars.primary",
    ["DDingUI_SecondaryPowerBar"]  = "resourceBars.secondary",
    ["DDingUI_PlayerCastBar"]     = "castBars",
    ["DDingUI_BuffTrackerBar"]    = "buffTracker",
}

function Movers:GetGUIKeyFromMoverName(moverName)
    if not moverName then return nil end

    -- 정적 매핑
    if MOVER_TO_GUI[moverName] then
        return MOVER_TO_GUI[moverName]
    end

    -- GroupSystem 그룹: DDingUI_Group_Cooldowns → groupSystem.group_Cooldowns
    local groupName = moverName:match("^DDingUI_Group_(.+)$")
    if groupName then
        return "groupSystem.group_" .. groupName
    end

    -- 동적 아이콘 그룹: DDingUI_DynGroup_X → groupSystem.group_X (GroupSystem이 통합 관리)
    local dynGroupName = moverName:match("^DDingUI_DynGroup_(.+)$")
    if dynGroupName then
        return "groupSystem.group_" .. dynGroupName
    end

    -- BuffTracker 개별 바: DDingUI_BuffTracker_N → buffTracker
    if moverName:match("^DDingUI_BuffTracker_") then
        return "buffTracker"
    end

    return nil
end

-- 편집모드 종료 (외부 호출용)
function Movers:ExitEditMode()
    if self.ConfigMode then
        self:HideMovers()
        self.ConfigMode = false
    end
end

--------------------------------------------------------------------------------
-- Config Mode
--------------------------------------------------------------------------------

function Movers:ToggleConfigMode()
    if InCombatLockdown() then
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cffff6666" .. (L["Cannot toggle movers in combat"] or "Cannot toggle movers in combat") .. "|r") -- [STYLE]
        return
    end

    self.ConfigMode = not self.ConfigMode

    if self.ConfigMode then
        self:ShowMovers()
    else
        self:HideMovers()
    end
end

function Movers:ShowMovers()
    self.ConfigMode = true

    -- DDingUI 메인 설정 창 닫기
    local configFrame = _G["DDingUI_ConfigFrame"]
    if configFrame and configFrame:IsShown() then
        configFrame:Hide()
    end

    -- 버프 트래커 바들의 레이아웃을 먼저 초기화 (mover 등록 전에)
    if DDingUI.InitializeTrackedBuffBarsForMover then
        DDingUI:InitializeTrackedBuffBarsForMover()
    end

    self:RegisterStandardFrames()

    -- 버프 트래커 프레임이 완전히 생성된 후 mover 등록 (즉시 + 지연)
    self:RegisterBuffTrackerFrames()
    C_Timer.After(0.1, function()
        self:RegisterBuffTrackerFrames()
    end)

    -- [FIX] 편집모드 진입 시 숨김/알파0 그룹 프레임 강제 표시
    -- stale mover 정리 전에 실행해야 Mover가 삭제되지 않음
    self._editModeGroupRestore = self._editModeGroupRestore or {}
    wipe(self._editModeGroupRestore)
    local GR = DDingUI.GroupRenderer
    if GR and GR.groupFrames then
        for groupName, frame in pairs(GR.groupFrames) do
            local wasHidden = not frame:IsShown()
            local wasAlphaZero = frame:GetAlpha() < 0.01
            if wasHidden or wasAlphaZero then
                self._editModeGroupRestore[groupName] = {
                    hidden = wasHidden,
                    alpha = frame:GetAlpha(),
                }
                frame:Show()
                frame:SetAlpha(1)
                -- 빈 그룹은 크기가 너무 작아 Mover가 안 보임 → 최소 크기 보장
                local fw, fh = frame:GetSize()
                if fw < 10 or fh < 10 then
                    frame:SetSize(math.max(fw, 50), math.max(fh, 20))
                end
            end
        end
    end

    -- [FIX] 숨겨진 부모 프레임의 stale mover 사전 정리 (삭제된 그룹 등)
    local staleMoverKeys
    for name, holder in pairs(self.CreatedMovers) do
        if holder.parent and not holder.parent:IsShown() then
            -- 그룹 프레임 mover만 대상 (표준 프레임은 숨겨져 있어도 mover 표시)
            if string.match(name, "^DDingUI_Group_") then
                if not staleMoverKeys then staleMoverKeys = {} end
                staleMoverKeys[#staleMoverKeys + 1] = name
            end
        end
    end
    if staleMoverKeys then
        for _, key in ipairs(staleMoverKeys) do
            self:UnregisterMover(key)
        end
    end

    for name, holder in pairs(self.CreatedMovers) do
        if holder.parent and holder.mover then
            local ok, point, anchor, relPoint, x, y = pcall(holder.parent.GetPoint, holder.parent, 1)
            if ok and point then
                -- [FIX] UIParent 앵커는 무조건 CENTER/CENTER 강제
                if (anchor or UIParent) == UIParent then
                    point = "CENTER"
                    relPoint = "CENTER"
                end
                holder.mover:ClearAllPoints()
                holder.mover:SetPoint(point, anchor or UIParent, relPoint or point, x or 0, y or 0)
            end

            local okSize, pw, ph = pcall(function()
                return holder.parent:GetWidth(), holder.parent:GetHeight()
            end)
            if okSize and pw and pw > 0 and ph and ph > 0 then
                holder.mover:SetSize(pw, math.max(ph, 1))
            end

            -- 시작 위치 저장 (종료 시 비교용)
            holder.mover._startPoint = GetPoint(holder.mover)

            holder.mover:Show()
        end
    end

    -- 그리드 설정에 따라 표시
    if self.Settings.gridEnabled then
        self:ShowGrid()
    end

    -- Nudge Frame 표시
    if self.NudgeFrame then
        self.NudgeFrame:Show()
    end

    -- [FIX] 알파 0으로 숨겨진 CDM 뷰어의 마우스 이벤트 비활성화 + Mover 숨기기
    -- 보이지 않는 뷰어가 Mover 드래그/앵커 선택을 가로채는 것 방지
    self._editModeViewerMouse = {}
    self._editModeHiddenMovers = {}
    local cdmViewers = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
    for _, vname in ipairs(cdmViewers) do
        local viewer = _G[vname]
        if viewer and viewer:GetAlpha() < 0.01 then
            self._editModeViewerMouse[vname] = true
            viewer:EnableMouse(false)
            -- viewerFrame(내부 컨테이너)도 비활성화
            if viewer.viewerFrame then
                viewer.viewerFrame:EnableMouse(false)
            end
            -- 해당 뷰어의 Mover도 숨기기
            local holder = self.CreatedMovers[vname]
            if holder and holder.mover and holder.mover:IsShown() then
                holder.mover:Hide()
                self._editModeHiddenMovers[vname] = true
            end
        end
    end

    print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cff00ff00" .. (L["Mover mode enabled"] or "Mover mode enabled. Click a frame to adjust.") .. "|r") -- [STYLE]
end

-- (ResolvePath는 LoadMoverPosition 앞에 정의됨)

-- Mover 위치를 모듈 설정으로 동기화
function Movers:SyncMoverToModuleSettings(name)
    local holder = self.CreatedMovers[name]
    if not holder or not holder.mover then return end

    local mapping = MoverToModuleMapping[name]
    if not mapping then return end
    if not DDingUI.db then return end

    local cfg = ResolvePath(DDingUI.db.profile, mapping.path)
    if not cfg then return end

    -- 모버의 실제 앵커 상태를 모듈 설정에 반영 -- [FIX: anchor sync]
    local _, moverRelTo, moverRelPoint = holder.mover:GetPoint(1)
    local anchorPoint = moverRelPoint or cfg[mapping.pointKey] or "CENTER"
    local attachToName = (moverRelTo and moverRelTo:GetName()) or (mapping.attachKey and cfg[mapping.attachKey]) or "UIParent"
    local anchorFrame = _G[attachToName] or UIParent

    -- [FIX] 앵커 프레임이 자기 자신이면 UIParent 폴백
    if anchorFrame == holder.parent then
        anchorFrame = UIParent
        attachToName = "UIParent"
    end

    -- [FIX] 앵커 프레임의 GetCenter()가 nil이면 UIParent CENTER로 폴백
    if not anchorFrame:GetCenter() then
        anchorFrame = UIParent
        attachToName = "UIParent"
        anchorPoint = "CENTER"
    end

    -- Mover의 기준점 (self point) 가져오기
    local moverPt = select(1, holder.mover:GetPoint(1)) or "CENTER"

    -- [FIX] UIParent 앵커는 항상 CENTER/CENTER 강제
    -- 9-point 자동 계산(TOPLEFT, BOTTOMRIGHT 등)은 해상도/스케일 변경에 불안정
    if anchorFrame == UIParent then
        anchorPoint = "CENTER"
        moverPt = "CENTER"
    end

    -- Mover의 기준점 위치 (화면 좌표)
    local moverSelfX, moverSelfY = GetPointPosition(holder.mover, moverPt)
    if not moverSelfX then return end

    -- 앵커 프레임의 anchorPoint 위치 (화면 좌표)
    local anchorPointX, anchorPointY = GetPointPosition(anchorFrame, anchorPoint)
    if not anchorPointX then return end

    -- mover 기준점에서 anchor anchorPoint까지의 오프셋
    local rawOffsetX = moverSelfX - anchorPointX
    local rawOffsetY = moverSelfY - anchorPointY

    -- barAnchorPoint 플립 보정 (PrimaryPowerBar: TOP↔BOTTOM 변환)
    -- selfPoint가 명시적으로 설정된 경우 보정 불필요 (모듈이 동일한 selfPoint 사용)
    if mapping.hasBarAnchorFlip and moverPt == "CENTER" and not (mapping.selfPointKey and cfg[mapping.selfPointKey]) then
        local barHeight = holder.mover:GetHeight() or 0
        if anchorPoint == "TOP" then
            rawOffsetY = rawOffsetY - barHeight / 2
        elseif anchorPoint == "BOTTOM" then
            rawOffsetY = rawOffsetY + barHeight / 2
        end
    end

    -- DDingUI:Scale()은 스냅 함수(곱셈 아님)이므로 화면 좌표 그대로 저장
    local offsetX = rawOffsetX
    local offsetY = rawOffsetY

    -- 저장
    cfg[mapping.xKey] = offsetX
    cfg[mapping.yKey] = offsetY

    -- 앵커 포인트/프레임 변경도 모듈 설정에 동기화 -- [FIX: anchor sync]
    if mapping.pointKey then
        cfg[mapping.pointKey] = anchorPoint
    end
    if mapping.attachKey then
        cfg[mapping.attachKey] = attachToName
    end

    -- 기준점 저장 -- [FIX: selfPoint support]
    if mapping.selfPointKey then
        cfg[mapping.selfPointKey] = moverPt
    end

    -- [FIX] 그룹 프레임의 뷰어 마이그레이션 방지 플래그
    -- SyncMoverToModuleSettings로 위치가 저장되면, 리로드 시 뷰어 위치 대신 저장 위치 사용
    if cfg._moverSaved == nil or cfg._moverSaved == false then
        cfg._moverSaved = true
    end

    -- PowerBar 특별 처리: noSecondaryOffsetY도 함께 업데이트
    if name == "DDingUI_PowerBar" then
        cfg.noSecondaryOffsetY = offsetY
    end

    -- [FIX] 무버 위치 변경 시 스펙별 스냅샷에 반영
    -- MarkDirty가 없으면 편집모드에서 변경한 위치가 스펙 전환 시 저장/복원 안 됨
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

function Movers:HideMovers()
    self.ConfigMode = false

    -- 버프 트래커 mover 모드 종료
    if DDingUI.ExitBuffTrackerMoverMode then
        DDingUI:ExitBuffTrackerMoverMode()
    end

    -- 이동모드 종료 시 위치가 변경된 Mover만 모듈 설정으로 동기화
    for name, holder in pairs(self.CreatedMovers) do
        local currentPoint = GetPoint(holder.mover)
        if holder.mover._startPoint and holder.mover._startPoint ~= currentPoint then
            -- 버프 트래커는 OnDragStop에서 이미 SaveMoverPosition으로 저장됨
            -- 9-point 재배치 후 SyncMoverToModuleSettings하면 좌표가 틀어짐
            local isBuffTracker = string.match(name, "^DDingUI_BuffTracker")
            if not isBuffTracker then
                self:SyncMoverToModuleSettings(name)
            end
        end
        holder.mover._startPoint = nil
        holder.mover:Hide()
    end

    self:HideGrid()
    self.Settings.gridEnabled = false  -- 종료 시 그리드 상태 초기화

    if self.NudgeFrame then
        self.NudgeFrame:Hide()
    end

    self.SelectedMover = nil

    -- Undo/Redo 스택 초기화
    self:ClearUndoRedo()

    -- 설정 저장
    self:SaveSettings()

    print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cff00ff00" .. (L["Mover mode disabled"] or "Mover mode disabled. Positions saved.") .. "|r") -- [STYLE]

    -- [FIX] 편집모드 중 강제 표시한 그룹 프레임 복원
    if self._editModeGroupRestore then
        local GR = DDingUI.GroupRenderer
        if GR and GR.groupFrames then
            for groupName, saved in pairs(self._editModeGroupRestore) do
                local frame = GR.groupFrames[groupName]
                if frame then
                    frame:SetAlpha(saved.alpha)
                    if saved.hidden then
                        frame:Hide()
                    end
                end
            end
        end
        wipe(self._editModeGroupRestore)
    end

    -- [FIX] CDM 뷰어 마우스 이벤트 복원
    if self._editModeViewerMouse then
        for vname, _ in pairs(self._editModeViewerMouse) do
            local viewer = _G[vname]
            if viewer then
                viewer:EnableMouse(true)
                if viewer.viewerFrame then
                    viewer.viewerFrame:EnableMouse(true)
                end
            end
        end
        wipe(self._editModeViewerMouse)
    end

    -- [FIX] 편집모드 종료 후 매핑 모듈 위치 강제 재적용
    -- 드래그 중 parent:SetPoint("CENTER", UIParent, "BOTTOMLEFT",...) 절대좌표로 설정됨
    -- 모듈의 _lastXxx 캐시를 무효화하여 다음 Update에서 cfg 기반으로 재배치
    local powerBar = DDingUI.powerBar
    if powerBar then
        powerBar._lastAnchor = nil
        powerBar._lastAnchorPoint = nil
        powerBar._lastOffsetX = nil
        powerBar._lastOffsetY = nil
        powerBar._lastBarAnchorPoint = nil
        powerBar._lastWidth = nil
    end
    local secondaryBar = DDingUI.secondaryPowerBar
    if secondaryBar then
        secondaryBar._lastAnchor = nil
        secondaryBar._lastAnchorPoint = nil
        secondaryBar._lastOffsetX = nil
        secondaryBar._lastOffsetY = nil
        secondaryBar._lastBarAnchorPoint = nil
        secondaryBar._lastWidth = nil
    end
    -- 모듈 Update 트리거 (cfg 설정에서 올바른 위치로 재배치)
    if DDingUI.ResourceBars then
        if DDingUI.ResourceBars.UpdatePowerBar then
            pcall(DDingUI.ResourceBars.UpdatePowerBar, DDingUI.ResourceBars)
        end
        if DDingUI.ResourceBars.UpdateSecondaryPowerBar then
            pcall(DDingUI.ResourceBars.UpdateSecondaryPowerBar, DDingUI.ResourceBars)
        end
    end
end

function Movers:IsConfigMode()
    return self.ConfigMode
end

--------------------------------------------------------------------------------
-- Grid (ElvUI Style Snap Grid)
--------------------------------------------------------------------------------

function Movers:CreateGrid()
    local gridSize = self.Settings.gridSize
    if not gridSize or gridSize <= 0 then gridSize = 32 end
    local width, height = UIParent:GetSize()

    -- 기존 그리드 프레임 재사용 (텍스쳐만 재생성)
    if self.Grid then
        -- 기존 라인 텍스쳐 숨기기
        for _, line in ipairs(self.Grid.lines or {}) do
            line:Hide()
            line:ClearAllPoints()
        end
    else
        local grid = CreateFrame("Frame", "DDingUI_MoverGrid", UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid:Hide()
        grid.lines = {}
        self.Grid = grid
    end

    local grid = self.Grid
    local lineIdx = 0

    -- 기존 텍스쳐 재사용 또는 새로 생성하는 헬퍼
    local function GetOrCreateLine()
        lineIdx = lineIdx + 1
        local line = grid.lines[lineIdx]
        if not line then
            line = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[lineIdx] = line
        end
        line:ClearAllPoints()
        line:Show()
        return line
    end

    -- [FIX] 실제 화면 중앙에 독립 중앙선 그리기 (격자 간격과 무관)
    local centerX = math.floor(width / 2 + 0.5)
    local centerY = math.floor(height / 2 + 0.5)

    -- 수직 중앙선
    local vCenter = GetOrCreateLine()
    vCenter:SetSize(2, height)
    vCenter:SetPoint("TOP", grid, "TOPLEFT", centerX, 0)
    vCenter:SetColorTexture(1, 0.3, 0.3, 0.7)

    -- 수평 중앙선
    local hCenter = GetOrCreateLine()
    hCenter:SetSize(width, 2)
    hCenter:SetPoint("LEFT", grid, "TOPLEFT", 0, -centerY)
    hCenter:SetColorTexture(1, 0.3, 0.3, 0.7)

    -- Create vertical grid lines
    for i = 0, width, gridSize do
        if math.abs(i - centerX) > 1 then -- 중앙선과 겹치지 않게
            local line = GetOrCreateLine()
            line:SetSize(1, height)
            line:SetPoint("TOP", grid, "TOPLEFT", i, 0)
            line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        end
    end

    -- Create horizontal grid lines
    for i = 0, height, gridSize do
        if math.abs(i - centerY) > 1 then -- 중앙선과 겹치지 않게
            local line = GetOrCreateLine()
            line:SetSize(width, 1)
            line:SetPoint("LEFT", grid, "TOPLEFT", 0, -i)
            line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        end
    end

    -- 남은 미사용 라인 숨기기
    for i = lineIdx + 1, #grid.lines do
        grid.lines[i]:Hide()
    end
end

function Movers:ShowGrid()
    if not self.Grid then
        self:CreateGrid()
    end
    self.Grid:Show()
    self.Settings.gridEnabled = true

    -- Update checkbox if nudge frame exists
    if self.NudgeFrame and self.NudgeFrame.gridCheckbox then
        self.NudgeFrame.gridCheckbox:SetChecked(true)
    end
end

function Movers:HideGrid()
    if self.Grid then
        self.Grid:Hide()
    end
    self.Settings.gridEnabled = false

    -- Update checkbox if nudge frame exists
    if self.NudgeFrame and self.NudgeFrame.gridCheckbox then
        self.NudgeFrame.gridCheckbox:SetChecked(false)
    end
end

function Movers:ToggleGrid()
    if self.Settings.gridEnabled then
        self:HideGrid()
    else
        self:ShowGrid()
    end
end

--------------------------------------------------------------------------------
-- Nudge Frame (ElvUI Style - Position near selected mover)
--------------------------------------------------------------------------------

function Movers:PositionNudgeFrame(mover)
    if not self.NudgeFrame or not mover then return end

    local x, y, point, nudgePoint, nudgeInversePoint = self:CalculateMoverPoints(mover)

    -- Position nudge frame on opposite side of mover
    self.NudgeFrame:ClearAllPoints()

    local offsetX, offsetY = 0, 0
    if nudgeInversePoint == "TOP" then
        offsetY = 10
    elseif nudgeInversePoint == "BOTTOM" then
        offsetY = -10
    elseif nudgeInversePoint == "LEFT" then
        offsetX = -10
    elseif nudgeInversePoint == "RIGHT" then
        offsetX = 10
    end

    self.NudgeFrame:SetPoint(nudgePoint, mover, nudgeInversePoint, offsetX, offsetY)
end

function Movers:CreateNudgeFrame()
    if self.NudgeFrame then return end

    local SL = _G.DDingUI_StyleLib
    local accent = SL and { SL.GetAccent("CDM") } or { {0.90, 0.45, 0.12}, {0.60, 0.18, 0.05} }
    local accentFrom = accent[1] or {0.90, 0.45, 0.12}
    local panelBg = SL and SL.Colors.bg.main or {0.10, 0.10, 0.10, 0.95}
    local panelBorder = SL and SL.Colors.border.default or {0.25, 0.25, 0.25, 0.50}

    local nudge = CreateFrame("Frame", "DDingUI_NudgeFrame", UIParent, "BackdropTemplate")
    nudge:SetSize(280, 600)
    nudge:SetPoint("TOP", UIParent, "TOP", 0, -50)
    nudge:SetFrameStrata("FULLSCREEN_DIALOG")
    nudge:SetFrameLevel(200)
    nudge:EnableMouse(true)
    nudge:SetClampedToScreen(true)
    nudge:Hide()

    nudge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    nudge:SetBackdropColor(panelBg[1], panelBg[2], panelBg[3], panelBg[4] or 0.95)
    nudge:SetBackdropBorderColor(panelBorder[1], panelBorder[2], panelBorder[3], panelBorder[4] or 0.50)

    if SL and SL.CreateHorizontalGradient then
        local gradLine = SL.CreateHorizontalGradient(nudge, accentFrom, accent[2] or accentFrom, 2, "OVERLAY")
        if gradLine then
            gradLine:ClearAllPoints()
            gradLine:SetPoint("TOPLEFT", 0, 0)
            gradLine:SetPoint("TOPRIGHT", 0, 0)
        end
    end

    -- 드래그 가능한 타이틀 바 생성
    local titleBar = CreateFrame("Frame", nil, nudge)
    titleBar:SetHeight(16)
    titleBar:SetPoint("TOPLEFT", nudge, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", nudge, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)

    local titleBarDragging = false
    local titleBarOffsetX, titleBarOffsetY = 0, 0

    titleBar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            titleBarDragging = true
            local scale = nudge:GetEffectiveScale()
            local mouseX, mouseY = GetCursorPosition()
            mouseX = mouseX / scale
            mouseY = mouseY / scale
            local frameX, frameY = nudge:GetCenter()
            titleBarOffsetX = frameX - mouseX
            titleBarOffsetY = frameY - mouseY
        end
    end)

    titleBar:SetScript("OnMouseUp", function(self, button)
        titleBarDragging = false
    end)

    nudge:SetScript("OnUpdate", function(self)
        if titleBarDragging then
            local scale = self:GetEffectiveScale()
            local mouseX, mouseY = GetCursorPosition()
            mouseX = mouseX / scale
            mouseY = mouseY / scale
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mouseX + titleBarOffsetX, mouseY + titleBarOffsetY)
        end
    end)

    -- Close button (StyleLib)
    local closeBtn = CreateFrame("Button", nil, nudge)
    closeBtn:SetSize(28, 24)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(0.5, 0.5, 0.5)

    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.5, 0.5, 0.5) end)
    closeBtn:SetScript("OnClick", function()
        if Movers.ConfigMode then
            Movers:ToggleConfigMode()
        else
            nudge:Hide()
        end
    end)

    -- Title
    local title = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    title:SetPoint("TOP", 0, -10)
    title:SetText(L["Position Adjustment"] or "Position Adjustment")
    title:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3])
    nudge.title = title

    -- Selected frame name
    local selectedText = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedText:SetPoint("TOP", title, "BOTTOM", 0, -4)
    selectedText:SetText(L["No frame selected"] or "No frame selected")
    nudge.selectedText = selectedText

    -- Anchor info (더 눈에 띄게)
    local anchorLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchorLabel:SetPoint("TOP", selectedText, "BOTTOM", 0, -8)
    anchorLabel:SetText("Anchor: --")
    anchorLabel:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3])
    nudge.anchorLabel = anchorLabel

    --------------------------------------------------------------------------------
    -- Anchor Point & Frame Dropdowns (StyleLib Flat)
    --------------------------------------------------------------------------------
    local anchorY = -70
    local SOLID = "Interface\\Buttons\\WHITE8x8"
    local ddInputBg = SL and SL.Colors.bg.input or {0.06, 0.06, 0.06, 0.80}
    local ddHoverBg = SL and SL.Colors.bg.hover or {0.15, 0.15, 0.15, 0.80}
    local ddMainBg  = SL and SL.Colors.bg.main  or {0.10, 0.10, 0.10, 0.95}
    local ddBorder  = SL and SL.Colors.border.default or {0.25, 0.25, 0.25, 0.50}

    local ANCHOR_POINTS = {
        "TOPLEFT", "TOP", "TOPRIGHT",
        "LEFT", "CENTER", "RIGHT",
        "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"
    }

    -- Internal: create a StyleLib-style flat dropdown
    local function CreateFlatDropdown(parent, labelText, width, anchorPt, anchorFrame, anchorRelPt, xOff, yOff, items, onSelect)
        local container = CreateFrame("Frame", nil, parent)
        container:SetSize(width + 10, 40)
        container:SetPoint(anchorPt, anchorFrame, anchorRelPt, xOff, yOff)

        local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 0, 0)
        lbl:SetText(labelText)

        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(width, 22)
        btn:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
        btn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
        btn:SetBackdropColor(unpack(ddInputBg))
        btn:SetBackdropBorderColor(unpack(ddBorder))

        local selText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        selText:SetPoint("LEFT", 4, 0)
        selText:SetPoint("RIGHT", -16, 0)
        selText:SetJustifyH("LEFT")
        selText:SetWordWrap(false)

        local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        arrow:SetPoint("RIGHT", -4, 0)
        arrow:SetText("\226\150\188") -- U+25BC ▼

        container._value = nil
        container._text = ""
        container._items = items or {}

        local function SetDisplay(text, value)
            container._value = value
            container._text = text
            selText:SetText(text or "--")
        end

        -- dropdown list
        local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
        list:SetWidth(width)
        list:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
        list:SetBackdropColor(unpack(ddMainBg))
        list:SetBackdropBorderColor(unpack(ddBorder))
        list:Hide()

        -- click-away catcher
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

            -- scroll support
            local needsScroll = #container._items > 10
            local rowParent = list

            for i, item in ipairs(container._items) do
                local row = CreateFrame("Button", nil, rowParent)
                row:SetSize(width - 2, 20)
                row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", 1, -(1 + (i - 1) * 20))

                local rowBG = row:CreateTexture(nil, "BACKGROUND")
                rowBG:SetAllPoints()
                rowBG:SetColorTexture(0, 0, 0, 0)

                local rowText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

        -- initial build
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

        function container:SetValue(val, displayText)
            SetDisplay(displayText or val, val)
        end
        function container:GetValue() return self._value end
        function container:SetItems(newItems) RebuildItems(newItems) end

        container.button = btn
        container.label = lbl
        return container
    end

    -- Anchor Point Dropdown
    local anchorPointItems = {}
    for _, pt in ipairs(ANCHOR_POINTS) do anchorPointItems[#anchorPointItems+1] = {text=pt, value=pt} end

    local anchorPointDropdown = CreateFlatDropdown(nudge,
        L["Anchor Point"] or "앵커 대상", 110,
        "TOPLEFT", nudge, "TOPLEFT", 15, anchorY,
        anchorPointItems,
        function(val)
            local mover = Movers.SelectedMover
            if mover then
                local oldPoint = GetPoint(mover)
                local selfPt, af, _, x, y = mover:GetPoint(1)
                mover:ClearAllPoints()
                mover:SetPoint(selfPt or "CENTER", af or UIParent, val, x or 0, y or 0)
                Movers:PushUndo(mover.name, oldPoint)
                Movers:SaveMoverPosition(mover.name)
                Movers:UpdateParentPosition(mover.name)
                nudge:UpdateInfo()
            end
        end)
    nudge.anchorPointDropdown = anchorPointDropdown

    -- Anchor Frame Dropdown
    local anchorFrameDropdown = CreateFlatDropdown(nudge,
        L["Anchor To"] or "연결 대상", 110,
        "TOPLEFT", nudge, "TOPLEFT", 148, anchorY,
        { {text="UIParent", value="UIParent"} },
        function(val)
            local mover = Movers.SelectedMover
            if mover then
                local targetFrame = _G[val] or UIParent
                local oldPoint = GetPoint(mover)
                local selfPt, _, relPoint, x, y = mover:GetPoint(1)
                mover:ClearAllPoints()
                if val == "UIParent" then
                    mover:SetPoint(selfPt or "CENTER", UIParent, relPoint or "CENTER", x or 0, y or 0)
                else
                    mover:SetPoint(selfPt or "CENTER", targetFrame, relPoint or "CENTER", 0, 0)
                end
                Movers:PushUndo(mover.name, oldPoint)
                Movers:SaveMoverPosition(mover.name)
                Movers:UpdateParentPosition(mover.name)
                nudge:UpdateInfo()
            end
        end)
    nudge.anchorFrameDropdown = anchorFrameDropdown

    -- Self Point Dropdown
    local selfPointDropdown = CreateFlatDropdown(nudge,
        L["Self Point"] or "기준점", 110,
        "TOPLEFT", nudge, "TOPLEFT", 15, anchorY - 48,
        anchorPointItems,
        function(val)
            local mover = Movers.SelectedMover
            if mover then
                local oldPoint = GetPoint(mover)
                local _, af, relPoint, x, y = mover:GetPoint(1)
                mover:ClearAllPoints()
                mover:SetPoint(val, af or UIParent, relPoint or "CENTER", x or 0, y or 0)
                Movers:PushUndo(mover.name, oldPoint)
                Movers:SaveMoverPosition(mover.name)
                Movers:UpdateParentPosition(mover.name)
                nudge:UpdateInfo()
            end
        end)
    nudge.selfPointDropdown = selfPointDropdown

    --------------------------------------------------------------------------------
    -- Anchor Selection Button (앵커 선택 버튼) - StartFramePicker 사용
    --------------------------------------------------------------------------------
    local anchorSelectY = -160

    local anchorSelectBtn = CreateFrame("Button", nil, nudge, "BackdropTemplate")
    anchorSelectBtn:SetSize(250, 24)
    anchorSelectBtn:SetPoint("TOP", nudge, "TOP", 0, anchorSelectY)
    
    local dR = (accentFrom and accentFrom[1] or 0.3) * 0.3
    local dG = (accentFrom and accentFrom[2] or 0.8) * 0.3
    local dB = (accentFrom and accentFrom[3] or 0.4) * 0.3
    
    anchorSelectBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    anchorSelectBtn:SetBackdropColor(dR, dG, dB, 0.8)
    local pB = panelBorder or {0.25, 0.25, 0.25, 0.5}
    anchorSelectBtn:SetBackdropBorderColor(pB[1], pB[2], pB[3], pB[4] or 0.5)

    local txt = anchorSelectBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER")
    txt:SetText(L["Select Anchor"] or "Select Anchor")
    
    anchorSelectBtn:SetScript("OnEnter", function() anchorSelectBtn:SetBackdropColor(math.min(dR+0.12,1), math.min(dG+0.12,1), math.min(dB+0.12,1), 0.95) end)
    anchorSelectBtn:SetScript("OnLeave", function() anchorSelectBtn:SetBackdropColor(dR, dG, dB, 0.8) end)
    nudge.anchorSelectBtn = anchorSelectBtn

    anchorSelectBtn:SetScript("OnClick", function()
        if not Movers.SelectedMover then
            print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cffff6666" .. (L["Select a frame first"] or "Select a frame first") .. "|r")
            return
        end

        -- DDingUI:StartFramePicker 사용
        DDingUI:StartFramePicker(function(frameName)
            if not frameName or not Movers.SelectedMover then return end

            local mv = Movers.SelectedMover
            local targetFrame = _G[frameName] or UIParent
            local holder = Movers.CreatedMovers[mv.name]

            local parentName = holder and holder.parent and holder.parent:GetName()
            local moverBaseName = mv.name

            if targetFrame == mv
               or (holder and targetFrame == holder.parent)
               or frameName == parentName
               or frameName == moverBaseName then
                print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cffff6666" .. (L["Cannot anchor to self"] or "Cannot anchor to self") .. "|r")
                return
            end

            -- Undo용 현재 위치 저장
            local oldPointStr = GetPoint(mv)
            local selfPt, _, relPoint, px, py = mv:GetPoint(1)
            selfPt = selfPt or "CENTER"
            mv:ClearAllPoints()
            mv:SetPoint(selfPt, targetFrame, relPoint or "CENTER", 0, 0)

            Movers:PushUndo(mv.name, oldPointStr)
            Movers:SaveMoverPosition(mv.name)
            Movers:UpdateParentPosition(mv.name)

            local mapping = MoverToModuleMapping[mv.name]
            local anchorCfg = mapping and DDingUI.db and ResolvePath(DDingUI.db.profile, mapping.path)
            if anchorCfg and mapping.attachKey then
                anchorCfg[mapping.attachKey] = frameName
            end

            nudge:UpdateInfo()

            local pickerDisplayName = frameName
            for iterName, iterHolder in pairs(Movers.CreatedMovers or {}) do
                if iterHolder.parent and iterHolder.parent:GetName() == frameName then
                    pickerDisplayName = iterHolder.mover.displayText or iterName
                    break
                end
            end
            nudge.anchorFrameDropdown:SetValue(frameName, pickerDisplayName)
        end)
    end)

    -- Coordinate container
    local coordY = -190

    -- X coordinate
    local inputBg = SL and SL.Colors.bg.input or {0.06, 0.06, 0.06, 0.80}

    local xLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    xLabel:SetPoint("TOPLEFT", nudge, "TOPLEFT", 20, coordY)
    xLabel:SetText("X:")

    local xEditBox = CreateFrame("EditBox", nil, nudge, "BackdropTemplate")
    xEditBox:SetPoint("LEFT", xLabel, "RIGHT", 4, 0)
    xEditBox:SetSize(60, 20)
    xEditBox:SetFontObject("GameFontHighlightSmall")
    xEditBox:SetJustifyH("CENTER")
    xEditBox:SetAutoFocus(false)
    xEditBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    xEditBox:SetBackdropColor(inputBg[1] or 0.06, inputBg[2] or 0.06, inputBg[3] or 0.06, inputBg[4] or 0.8)
    local pB = panelBorder or {0.25, 0.25, 0.25, 0.5}
    xEditBox:SetBackdropBorderColor(pB[1], pB[2], pB[3], pB[4] or 0.5)

    xEditBox:SetScript("OnEditFocusGained", function(self) 
        local pR = accentFrom and accentFrom[1] or 0.3
        local pG = accentFrom and accentFrom[2] or 0.8
        local pB2 = accentFrom and accentFrom[3] or 0.4
        self:SetBackdropBorderColor(pR, pG, pB2, 1) 
    end)
    xEditBox:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(pB[1], pB[2], pB[3], pB[4] or 0.5) end)
    xEditBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and Movers.SelectedMover then
            local currentX = Movers.SelectedMover._lastX or 0
            Movers:NudgeMover(val - currentX, 0)
        end
        self:ClearFocus()
    end)
    xEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    xEditBox:SetScript("OnTabPressed", function() nudge.yEditBox:SetFocus() end)
    nudge.xEditBox = xEditBox

    -- Y coordinate
    local yLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    yLabel:SetPoint("LEFT", xEditBox, "RIGHT", 15, 0)
    yLabel:SetText("Y:")

    local yEditBox = CreateFrame("EditBox", nil, nudge, "BackdropTemplate")
    yEditBox:SetPoint("LEFT", yLabel, "RIGHT", 4, 0)
    yEditBox:SetSize(60, 20)
    yEditBox:SetFontObject("GameFontHighlightSmall")
    yEditBox:SetJustifyH("CENTER")
    yEditBox:SetAutoFocus(false)
    yEditBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    yEditBox:SetBackdropColor(inputBg[1] or 0.06, inputBg[2] or 0.06, inputBg[3] or 0.06, inputBg[4] or 0.8)
    yEditBox:SetBackdropBorderColor(pB[1], pB[2], pB[3], pB[4] or 0.5)

    yEditBox:SetScript("OnEditFocusGained", function(self) 
        local pR = accentFrom and accentFrom[1] or 0.3
        local pG = accentFrom and accentFrom[2] or 0.8
        local pB2 = accentFrom and accentFrom[3] or 0.4
        self:SetBackdropBorderColor(pR, pG, pB2, 1) 
    end)
    yEditBox:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(pB[1], pB[2], pB[3], pB[4] or 0.5) end)
    yEditBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and Movers.SelectedMover then
            local currentY = Movers.SelectedMover._lastY or 0
            Movers:NudgeMover(0, val - currentY)
        end
        self:ClearFocus()
    end)
    yEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    yEditBox:SetScript("OnTabPressed", function() nudge.xEditBox:SetFocus() end)
    nudge.yEditBox = yEditBox

    -- Arrow buttons (Flat UI)
    local arrowCenterY = -240
    local arrowSize = 28
    local nudgeBtnBg = SL and SL.Colors.bg.hover or {0.15, 0.15, 0.15, 0.80}

    local function CreateNudgeBtn(label, dx, dy, offsetX, offsetY)
        local btn = CreateFrame("Button", nil, nudge, "BackdropTemplate")
        btn:SetSize(arrowSize, arrowSize)
        btn:SetPoint("TOP", nudge, "TOP", offsetX, arrowCenterY + offsetY)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        btn:SetBackdropColor(nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, nudgeBtnBg[4] or 0.8)
        local pB = panelBorder or {0.25, 0.25, 0.25, 0.5}
        btn:SetBackdropBorderColor(pB[1], pB[2], pB[3], pB[4] or 0.5)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("CENTER")
        text:SetText(label)
        
        btn:SetScript("OnClick", function()
            local amount = IsShiftKeyDown() and 10 or 1
            Movers:NudgeMover(dx * amount, dy * amount)
        end)
        btn:SetScript("OnEnter", function() 
            local pR = (accentFrom and accentFrom[1] or 0.3) * 0.5
            local pG = (accentFrom and accentFrom[2] or 0.8) * 0.5
            local pB2 = (accentFrom and accentFrom[3] or 0.4) * 0.5
            btn:SetBackdropColor(pR, pG, pB2, 0.9) 
        end)
        btn:SetScript("OnLeave", function() btn:SetBackdropColor(nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, nudgeBtnBg[4] or 0.8) end)
        return btn
    end

    nudge.upBtn = CreateNudgeBtn("^", 0, 1, 0, 20)
    nudge.downBtn = CreateNudgeBtn("v", 0, -1, 0, -36)
    nudge.leftBtn = CreateNudgeBtn("<", -1, 0, -28, -8)
    nudge.rightBtn = CreateNudgeBtn(">", 1, 0, 28, -8)

    --------------------------------------------------------------------------------
    -- Settings Section
    --------------------------------------------------------------------------------
    local settingsY = -330

    -- Separator
    local separator = nudge:CreateTexture(nil, "ARTWORK")
    separator:SetSize(250, 1)
    separator:SetPoint("TOP", nudge, "TOP", 0, settingsY)
    separator:SetColorTexture(accentFrom[1] or 0.9, accentFrom[2] or 0.45, accentFrom[3] or 0.12, 0.4)

    -- Settings label
    local settingsLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsLabel:SetPoint("TOP", separator, "BOTTOM", 0, -6)
    settingsLabel:SetText(L["Settings"] or "Settings")
    settingsLabel:SetTextColor(accentFrom[1] or 0.9, accentFrom[2] or 0.45, accentFrom[3] or 0.12, 1)

    -- Helper function for checkboxes (StyleLib Flat)
    local function CreateCheckbox(label, yOffset, setting, onClick, indent)
        local container = CreateFrame("Frame", nil, nudge)
        container:SetSize(120, 18)
        container:SetPoint("TOPLEFT", nudge, "TOPLEFT", indent or 12, yOffset)

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

        container._checked = Movers.Settings[setting] or false
        if container._checked then fill:Show() else fill:Hide() end

        local text = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", box, "RIGHT", 4, 0)
        text:SetText(label)
        container.label = text

        function container:SetChecked(val)
            self._checked = val
            if val then fill:Show() else fill:Hide() end
        end
        function container:GetChecked() return self._checked end

        box:SetScript("OnClick", function()
            container._checked = not container._checked
            if container._checked then fill:Show() else fill:Hide() end
            Movers.Settings[setting] = container._checked
            if onClick then onClick(container._checked) end
        end)

        return container
    end

    local checkY = settingsY - 22

    -- Grid checkbox
    nudge.gridCheckbox = CreateCheckbox(L["Show Grid"] or "Show Grid", checkY, "gridEnabled", function(checked)
        if checked then Movers:ShowGrid() else Movers:HideGrid() end
    end)

    -- Snap checkbox
    nudge.snapCheckbox = CreateCheckbox(L["Enable Snap"] or "Enable Snap", checkY - 22, "snapEnabled")

    -- Snap sub-options (indented)
    nudge.snapGridCheckbox = CreateCheckbox(L["Grid"] or "Grid", checkY - 44, "snapToGrid", nil, 28)
    nudge.snapFramesCheckbox = CreateCheckbox(L["Frames"] or "Frames", checkY - 66, "snapToFrames", nil, 28)
    nudge.snapCenterCheckbox = CreateCheckbox(L["Center"] or "Center", checkY - 88, "snapToCenter", nil, 28)

    -- Right side: Sliders (StyleLib Flat, CDM Style)
    local sliderX = 140

    -- Internal: CDM-style flat slider
    local function CreateFlatSlider(parent, labelText, minV, maxV, stepV, defaultV, anchorTo, xOff, yOff, onChange)
        local container = CreateFrame("Frame", nil, parent)
        container:SetSize(120, 40)
        container:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", xOff, yOff)

        local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 0, 0)
        lbl:SetText(labelText)
        container.label = lbl

        -- track bg (simple texture, no backdrop)
        local track = CreateFrame("Frame", nil, container)
        track:SetHeight(4)
        track:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)
        track:SetPoint("RIGHT", container, "RIGHT", -50, 0)
        local trackBg = track:CreateTexture(nil, "BACKGROUND")
        trackBg:SetAllPoints()
        trackBg:SetColorTexture(ddInputBg[1] or 0.06, ddInputBg[2] or 0.06, ddInputBg[3] or 0.06, ddInputBg[4] or 0.8)

        local slider = CreateFrame("Slider", nil, container)
        slider:SetPoint("TOPLEFT", track)
        slider:SetPoint("BOTTOMRIGHT", track)
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(stepV)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(math.max(minV, math.min(maxV, defaultV)))
        slider:SetOrientation("HORIZONTAL")
        slider:EnableMouseWheel(true)

        -- accent-color fill bar
        local fill = slider:CreateTexture(nil, "ARTWORK")
        fill:SetHeight(4)
        fill:SetPoint("LEFT", track, "LEFT", 0, 0)
        fill:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 1)
        local function UpdateFill()
            local pct = (slider:GetValue() - minV) / math.max(1, maxV - minV)
            fill:SetWidth(math.max(1, pct * track:GetWidth()))
        end

        -- thumb
        local thumb = slider:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(8, 8)
        thumb:SetColorTexture(accentFrom[1], accentFrom[2], accentFrom[3], 1)
        slider:SetThumbTexture(thumb)

        -- min/max labels
        local minLbl = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        minLbl:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -1)
        minLbl:SetText(tostring(minV))
        minLbl:SetTextColor(0.5, 0.5, 0.5)

        local maxLbl = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        maxLbl:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -1)
        maxLbl:SetText(tostring(maxV))
        maxLbl:SetTextColor(0.5, 0.5, 0.5)

        -- value box
        local valBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
        valBox:SetSize(40, 18)
        valBox:SetPoint("LEFT", track, "RIGHT", 6, 0)
        valBox:SetFontObject("GameFontHighlightSmall")
        valBox:SetJustifyH("CENTER")
        valBox:SetAutoFocus(false)
        valBox:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
        valBox:SetBackdropColor(unpack(ddInputBg))
        valBox:SetBackdropBorderColor(unpack(ddBorder))

        local decimals = stepV < 1 and math.max(1, math.ceil(-math.log10(stepV))) or 0
        local fmtStr = "%." .. decimals .. "f"
        valBox:SetText(string.format(fmtStr, slider:GetValue()))

        slider:SetScript("OnValueChanged", function(self, value)
            value = tonumber(string.format(fmtStr, value))
            valBox:SetText(tostring(value))
            UpdateFill()
            if onChange then onChange(value) end
        end)

        valBox:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then slider:SetValue(math.max(minV, math.min(maxV, v))) end
            self:ClearFocus()
        end)
        valBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * stepV) end)

        -- defer first fill update
        C_Timer.After(0, UpdateFill)

        container.slider = slider
        container.valueBox = valBox
        return container
    end

    -- Grid Size Slider (forward-declare for callback upvalue)
    local gridSizeSliderContainer
    gridSizeSliderContainer = CreateFlatSlider(nudge,
        (L["Grid"] or "격자") .. ": " .. Movers.Settings.gridSize,
        16, 128, 8, Movers.Settings.gridSize,
        nudge, sliderX, checkY,
        function(value)
            Movers.Settings.gridSize = value
            if gridSizeSliderContainer then
                gridSizeSliderContainer.label:SetText((L["Grid"] or "격자") .. ": " .. value)
            end
            if Movers.Settings.gridEnabled then Movers:CreateGrid(); Movers:ShowGrid() end
        end)
    nudge.gridSizeLabel = gridSizeSliderContainer.label
    nudge.gridSizeSlider = gridSizeSliderContainer.slider

    -- Snap Threshold Slider (forward-declare for callback upvalue)
    local snapThresholdSliderContainer
    snapThresholdSliderContainer = CreateFlatSlider(nudge,
        (L["Snap"] or "스냅") .. ": " .. Movers.Settings.snapThreshold,
        5, 30, 1, Movers.Settings.snapThreshold,
        nudge, sliderX, checkY - 50,
        function(value)
            Movers.Settings.snapThreshold = value
            if snapThresholdSliderContainer then
                snapThresholdSliderContainer.label:SetText((L["Snap"] or "스냅") .. ": " .. value)
            end
        end)
    nudge.snapThresholdLabel = snapThresholdSliderContainer.label
    nudge.snapThresholdSlider = snapThresholdSliderContainer.slider

    --------------------------------------------------------------------------------
    -- Button Row (Flat UI)
    --------------------------------------------------------------------------------
    local btnWidth = 58
    local btnSpacing = 6
    local totalWidth = (btnWidth * 4) + (btnSpacing * 3)
    local startX = -totalWidth / 2
    local nudgeBtnBg = SL and SL.Colors.bg.hover or {0.15, 0.15, 0.15, 0.80}

    local function CreateBottomBtn(label, xOff, bgR, bgG, bgB, onClick)
        local btn = CreateFrame("Button", nil, nudge, "BackdropTemplate")
        btn:SetSize(btnWidth, 22)
        btn:SetPoint("BOTTOM", nudge, "BOTTOM", xOff, 12)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        btn:SetBackdropColor(bgR, bgG, bgB, 0.8)
        
        local pB = panelBorder or {0.25, 0.25, 0.25, 0.5}
        btn:SetBackdropBorderColor(pB[1], pB[2], pB[3], pB[4] or 0.5)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("CENTER")
        text:SetText(label)
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function() btn:SetBackdropColor(math.min(bgR+0.12,1), math.min(bgG+0.12,1), math.min(bgB+0.12,1), 0.95) end)
        btn:SetScript("OnLeave", function() btn:SetBackdropColor(bgR, bgG, bgB, 0.8) end)
        return btn
    end

    nudge.resetBtn = CreateBottomBtn(L["Reset"] or "Reset", startX + btnWidth/2, 0.3, 0.15, 0.15, function()
        if Movers.SelectedMover then
            local oldPoint = GetPoint(Movers.SelectedMover)
            Movers:PushUndo(Movers.SelectedMover.name, oldPoint)
            Movers:ResetMoverPosition(Movers.SelectedMover.name)
        end
    end)

    nudge.undoBtn = CreateBottomBtn(L["Undo"] or "Undo", startX + btnWidth + btnSpacing + btnWidth/2, nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, function() Movers:Undo() end)
    nudge.undoBtn._bg = {r = nudgeBtnBg[1] or 0.15, g = nudgeBtnBg[2] or 0.15, b = nudgeBtnBg[3] or 0.15}
    nudge.undoBtn:Disable()
    
    nudge.redoBtn = CreateBottomBtn(L["Redo"] or "Redo", startX + (btnWidth + btnSpacing) * 2 + btnWidth/2, nudgeBtnBg[1] or 0.15, nudgeBtnBg[2] or 0.15, nudgeBtnBg[3] or 0.15, function() Movers:Redo() end)
    nudge.redoBtn._bg = {r = nudgeBtnBg[1] or 0.15, g = nudgeBtnBg[2] or 0.15, b = nudgeBtnBg[3] or 0.15}
    nudge.redoBtn:Disable()
    
    local dR = (accentFrom and accentFrom[1] or 0.3) * 0.35
    local dG = (accentFrom and accentFrom[2] or 0.8) * 0.35
    local dB = (accentFrom and accentFrom[3] or 0.4) * 0.35
    nudge.doneBtn = CreateBottomBtn(L["Done"] or "Done", startX + (btnWidth + btnSpacing) * 3 + btnWidth/2, dR, dG, dB, function() Movers:ToggleConfigMode() end)

    -- Undo/Redo 버튼 상태 업데이트 함수
    function nudge:UpdateUndoRedoButtons()
        if self.undoBtn and self.undoBtn._bg then
            if #Movers.UndoStack > 0 then
                self.undoBtn:Enable()
                self.undoBtn:SetBackdropColor(self.undoBtn._bg.r, self.undoBtn._bg.g, self.undoBtn._bg.b, 0.8)
            else
                self.undoBtn:Disable()
                self.undoBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            end
        end
        if self.redoBtn and self.redoBtn._bg then
            if #Movers.RedoStack > 0 then
                self.redoBtn:Enable()
                self.redoBtn:SetBackdropColor(self.redoBtn._bg.r, self.redoBtn._bg.g, self.redoBtn._bg.b, 0.8)
            else
                self.redoBtn:Disable()
                self.redoBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            end
        end
    end

    -- Update functions
    function nudge:UpdateSelection()
        local mover = Movers.SelectedMover
        if mover then
            self.selectedText:SetText(mover.displayText or mover.name)
            if mover.UpdateBorderColor then
                mover.UpdateBorderColor(0, 1, 0, 1)
            end

            -- Reset other movers' highlight
            for _, holder in pairs(Movers.CreatedMovers) do
                if holder.mover ~= mover and holder.mover.UpdateBorderColor then
                    holder.mover.UpdateBorderColor(0.4, 0.6, 1, 0.8)
                end
            end

            self:UpdateInfo()
        else
            self.selectedText:SetText(L["No frame selected"] or "No frame selected")
            self.anchorLabel:SetText("Anchor: --")
            self.xEditBox:SetText("")
            self.yEditBox:SetText("")
            self.anchorPointDropdown:SetValue(nil, "--")
            self.anchorFrameDropdown:SetValue(nil, "--")
            self.selfPointDropdown:SetValue(nil, "--")
        end
    end

    function nudge:UpdateInfo()
        local mover = Movers.SelectedMover
        if not mover then return end

        -- 앵커 기준 오프셋 계산
        local point, anchorFrame, relPoint, x, y = mover:GetPoint(1)
        if not anchorFrame then anchorFrame = UIParent end

        -- 오프셋 값 (SetPoint의 x, y)
        x = x or 0
        y = y or 0

        mover._lastX = x
        mover._lastY = y

        self.xEditBox:SetText(tostring(math.floor(x + 0.5)))
        self.yEditBox:SetText(tostring(math.floor(y + 0.5)))

        -- 앵커 프레임 정보 표시
        local anchorName = "UIParent"
        if anchorFrame then
            anchorName = anchorFrame:GetName() or "UIParent"
        end

        -- MoverToModuleMapping에 있는 프레임은 relPoint가 실제 anchorPoint
        local mapping = MoverToModuleMapping[mover.name]
        local displayAnchorPoint = relPoint or point or "CENTER"
        local displaySelfPoint = point or "CENTER"

        self.anchorLabel:SetText(displaySelfPoint .. " → " .. displayAnchorPoint .. " @ " .. anchorName)

        -- 앵커 위치 드롭다운 업데이트
        if displayAnchorPoint then
            self.anchorPointDropdown:SetValue(displayAnchorPoint, displayAnchorPoint)
        end

        -- 기준점 드롭다운 업데이트
        if displaySelfPoint then
            self.selfPointDropdown:SetValue(displaySelfPoint, displaySelfPoint)
        end

        -- 앵커 프레임 드롭다운 업데이트
        -- 표시 이름 찾기 (parent의 displayText 사용)
        local displayName = anchorName
        if anchorFrame and anchorFrame ~= UIParent then
            for name, holder in pairs(Movers.CreatedMovers or {}) do
                if holder.parent and holder.parent:GetName() == anchorName then
                    displayName = holder.mover.displayText or name
                    break
                end
            end
        end
        self.anchorFrameDropdown:SetValue(anchorName, displayName)

        -- 앵커 프레임 드롭다운 목록 동적 갱신
        do
            local afItems = { {text="UIParent", value="UIParent"} }
            local currentMover = Movers.SelectedMover
            local currentHolder = currentMover and Movers.CreatedMovers[currentMover.name]
            -- [FIX] alpha=0으로 숨겨진 CDM 뷰어는 앵커 선택 불가 (GroupSystem 대체 시)
            local HIDDEN_CDM_VIEWERS = {
                EssentialCooldownViewer = true,
                UtilityCooldownViewer = true,
                BuffIconCooldownViewer = true,
            }
            for iterName, holder in pairs(Movers.CreatedMovers or {}) do
                if holder.mover and holder.mover ~= currentMover and holder.parent ~= (currentHolder and currentHolder.parent) then
                    local parentFrameName = holder.parent and holder.parent:GetName()
                    if parentFrameName then
                        -- alpha=0으로 숨겨진 CDM 뷰어는 목록에서 제외
                        local isHiddenViewer = HIDDEN_CDM_VIEWERS[parentFrameName]
                            and holder.parent.GetAlpha and holder.parent:GetAlpha() < 0.01
                        if not isHiddenViewer then
                            afItems[#afItems+1] = {text = holder.mover.displayText or iterName, value = parentFrameName}
                        end
                    end
                end
            end
            self.anchorFrameDropdown:SetItems(afItems)
        end
    end

    self.NudgeFrame = nudge
end


function Movers:NudgeMover(dx, dy)
    local mover = self.SelectedMover
    if not mover then return end

    -- Undo용 현재 위치 저장
    local oldPoint = GetPoint(mover)

    local selfPt, anchor, relPoint, x, y = mover:GetPoint(1)
    selfPt = selfPt or "CENTER"
    x = (x or 0) + (dx or 0)
    y = (y or 0) + (dy or 0)

    mover:ClearAllPoints()
    mover:SetPoint(selfPt, anchor or UIParent, relPoint or "CENTER", x, y)

    -- Undo 스택에 저장
    self:PushUndo(mover.name, oldPoint)

    self:SaveMoverPosition(mover.name)
    self:UpdateParentPosition(mover.name)

    if self.NudgeFrame then
        self.NudgeFrame:UpdateInfo()
    end
end

--------------------------------------------------------------------------------
-- Settings Persistence
--------------------------------------------------------------------------------

function Movers:SaveSettings()
    if not DDingUI.db then return end
    if not DDingUI.db.profile.moverSettings then
        DDingUI.db.profile.moverSettings = {}
    end

    DDingUI.db.profile.moverSettings = {
        gridEnabled = self.Settings.gridEnabled,
        snapEnabled = self.Settings.snapEnabled,
        snapToGrid = self.Settings.snapToGrid,
        snapToFrames = self.Settings.snapToFrames,
        snapToCenter = self.Settings.snapToCenter,
        snapThreshold = self.Settings.snapThreshold,
        gridSize = self.Settings.gridSize,
    }
end

function Movers:LoadSettings()
    if not DDingUI.db or not DDingUI.db.profile.moverSettings then return end

    local saved = DDingUI.db.profile.moverSettings
    for key, value in pairs(saved) do
        if self.Settings[key] ~= nil then
            self.Settings[key] = value
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- ============================================================
-- 앵커 마이그레이션 (v1.2.3 → v1.2.4)
-- 조건: 프로필에 profileVersion 없음 (이전 버전 프로필)
-- 규칙: attachTo가 CDM 뷰어/그룹이면 → 프록시 앵커(DDingUI_Anchor_*)로 변환
--       secondaryPowerBar/buffTrackerBar는 DDingUI_PowerBar(주자원바)로 변환
-- ============================================================
-- ATTACH_TO_PROXY는 파일 상단(MoverToModuleMapping 뒤)에 정의됨

function Movers:MigrateAnchorPoints()
    if not DDingUI.db or not DDingUI.db.profile then return end

    local profile = DDingUI.db.profile

    -- 이미 버전값이 있으면 마이그레이션 완료된 프로필
    if profile.profileVersion then return end

    -- profileVersion 세팅 (이후 마이그레이션 재실행 방지)
    local addonVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("DDingUI", "Version")
    profile.profileVersion = addonVersion or "1.2.4"

    -- 구 pendingMoverMigration 플래그 정리
    profile.pendingMoverMigration = nil

    local migratedCount = 0

    -- (1) MoverToModuleMapping: attachTo 치환 + 누락된 selfPoint 보정
    for moverName, mapping in pairs(MoverToModuleMapping) do
        local cfg = ResolvePath(profile, mapping.path)
        if cfg then
            -- attachTo가 CDM 뷰어이면 프록시로 치환
            if mapping.attachKey then
                local oldAttach = cfg[mapping.attachKey]
                local newAttach = oldAttach and ATTACH_TO_PROXY[oldAttach]
                if newAttach then
                    cfg[mapping.attachKey] = newAttach
                    migratedCount = migratedCount + 1
                end
            end
            -- selfPoint가 없으면 CENTER로 채움 (v1.2.3에는 selfPoint 없음)
            if mapping.selfPointKey and not cfg[mapping.selfPointKey] then
                cfg[mapping.selfPointKey] = "CENTER"
            end
        end
    end

    -- (2) movers 테이블: 구 뷰어 앵커 이름을 프록시로 치환 (포인트/오프셋 보존)
    -- 포맷: "selfPoint,anchorName,anchorPoint,x,y"
    if profile.movers then
        for name, pointString in pairs(profile.movers) do
            if type(pointString) == "string" then
                local pt, anchorName, relPt, x, y = strsplit(",", pointString)

                -- MoverToModuleMapping에 있는 항목: 모듈 설정으로 이관 후 삭제
                local mapping = MoverToModuleMapping[name]
                if mapping then
                    local cfg = ResolvePath(profile, mapping.path)
                    if cfg then
                        local mAnchorName = ATTACH_TO_PROXY[anchorName] or anchorName or "UIParent"
                        if mAnchorName == "" then mAnchorName = "UIParent" end
                        local mPoint = pt or "CENTER"
                        local mRelPoint = relPt or "CENTER"
                        local mX = tonumber(x) or 0
                        local mY = tonumber(y) or 0
                        if mapping.xKey then cfg[mapping.xKey] = mX end
                        if mapping.yKey then cfg[mapping.yKey] = mY end
                        if mapping.attachKey then cfg[mapping.attachKey] = mAnchorName end
                        if mapping.pointKey then cfg[mapping.pointKey] = mRelPoint end
                        if mapping.selfPointKey then cfg[mapping.selfPointKey] = mPoint end
                        migratedCount = migratedCount + 1
                    end
                    profile.movers[name] = nil  -- 모듈 설정으로 이관 완료 → 삭제
                elseif anchorName and ATTACH_TO_PROXY[anchorName] then
                    -- MoverToModuleMapping에 없는 일반 movers: 앵커 이름만 치환
                    local newAnchor = ATTACH_TO_PROXY[anchorName]
                    profile.movers[name] = string.format("%s,%s,%s,%s,%s",
                        pt or "CENTER", newAnchor, relPt or "CENTER",
                        x or "0", y or "0")
                    migratedCount = migratedCount + 1
                end
            end
        end
    end

    if migratedCount > 0 then
        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cff00ff00" .. migratedCount .. "개 프레임이 프록시 앵커로 전환되었습니다.|r")
    end
end

-- CompleteMoverMigration: 잔여 정리 전용
function Movers:CompleteMoverMigration()
    if not DDingUI.db or not DDingUI.db.profile then return end
    if DDingUI.db.profile.pendingMoverMigration then
        DDingUI.db.profile.pendingMoverMigration = nil
    end
end

function Movers:Initialize()
    -- [FIX] 마이그레이션은 유저 확인 후 실행 (Main.lua 팝업)

    -- Load saved settings
    self:LoadSettings()

    self:CreateNudgeFrame()

    -- Mover toggle commands
    SLASH_DDINGUIMOVERS1 = "/dduimove"
    SLASH_DDINGUIMOVERS2 = "/ddmove"
    SlashCmdList["DDINGUIMOVERS"] = function()
        Movers:ToggleConfigMode()
    end

    -- Grid toggle command (separate)
    SLASH_DDINGUIGRID1 = "/ddgrid"
    SlashCmdList["DDINGUIGRID"] = function()
        if Movers.ConfigMode then
            Movers:ToggleGrid()
        else
            -- 그리드만 토글하려면 먼저 mover 모드 활성화
            Movers:ToggleConfigMode()
            if Movers.ConfigMode then
                Movers:ShowGrid()
            end
        end
    end

    -- BuffTracker 프레임 새로고침 (이동 모드에서 새 트래커 감지)
    SLASH_DDINGUIREFRESH1 = "/ddrefresh"
    SlashCmdList["DDINGUIREFRESH"] = function()
        if Movers.ConfigMode then
            Movers:RegisterBuffTrackerFrames()
            print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cff00ff00" .. (L["Buff Tracker frames refreshed"] or "Buff Tracker frames refreshed") .. "|r") -- [STYLE]
        else
            print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cffff6666" .. (L["Enter mover mode first (/ddmove)"] or "Enter mover mode first (/ddmove)") .. "|r") -- [STYLE]
        end
    end

    self:RegisterStandardFrames()

    C_Timer.After(2, function()
        self:RegisterStandardFrames()
        self:RegisterBuffTrackerFrames()  -- 초기 버프 트래커 등록
    end)

    -- 프레임 로드 후 마이그레이션 완료 (절대 좌표 변환)
    C_Timer.After(3, function()
        self:CompleteMoverMigration()
    end)

    -- [FIX] GroupSystem이 그룹 프레임 생성 후 (T+3) 매핑 모듈 위치 재적용
    -- Movers init(T+2) 시점에는 DDingUI_Group_* 프레임이 없어 UIParent로 폴백
    -- 그룹 프레임 생성 후 다시 로드하면 올바른 앵커 연결
    C_Timer.After(4, function()
        self:ReloadMappedModulePositions()
    end)

    print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cff00ff00Movers initialized. Use /ddmove to toggle.|r") -- [STYLE]
end

function Movers:RegisterStandardFrames()
    -- [FIX] CastBar는 lazy 생성이라 편집모드 진입 시 아직 없을 수 있음 → 강제 생성
    if not _G["DDingUICastBar"] and not DDingUI.castBar then
        if DDingUI.GetCastBar then
            pcall(function() DDingUI:GetCastBar() end)
        end
    end

    local standardFrames = {
        { global = "DDingUIPowerBar", ref = "powerBar", key = "DDingUI_PowerBar", display = L["Primary Resource"] or "Primary Resource" },
        { global = "DDingUISecondaryPowerBar", ref = "secondaryPowerBar", key = "DDingUI_SecondaryPowerBar", display = L["Secondary Resource"] or "Secondary Resource" },
        { global = "DDingUICastBar", ref = "castBar", key = "DDingUI_PlayerCastBar", display = L["Player Cast Bar"] or "Player Cast Bar" },
        { global = "DDingUIBuffTrackerBar", ref = "buffTrackerBar", key = "DDingUI_BuffTrackerBar", display = L["Buff Tracker Bar"] or "Buff Tracker Bar" },
    }

    for _, info in ipairs(standardFrames) do
        local frame = _G[info.global] or DDingUI[info.ref]
        if frame then
            self:RegisterMover(frame, info.key, info.display)
        end
    end

    -- Cooldown Viewers는 mover에서 제외 (Blizzard EditMode와 taint 충돌 방지)
    -- 뷰어 위치는 Blizzard EditMode에서 조절
    -- 다른 프레임(리소스바, 캐스트바 등)은 뷰어를 앵커로 사용 가능

    -- Custom Icons 그룹 프레임 등록 (동적 아이콘)
    -- [FIX] GroupSystem 활성 시 CustomIcons 무버 등록 억제 (GroupSystem이 통합 관리)
    local gsSettings = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.groupSystem
    local groupSystemActive = gsSettings and gsSettings.enabled
    if not groupSystemActive and DDingUI.CustomIcons then
        local CustomIcons = DDingUI.CustomIcons
        -- GetGroupFrames() 또는 runtime.groupFrames에서 각 그룹 프레임 등록
        local groupFrames = nil
        if CustomIcons.GetGroupFrames then
            groupFrames = CustomIcons.GetGroupFrames()
        elseif CustomIcons.runtime and CustomIcons.runtime.groupFrames then
            groupFrames = CustomIcons.runtime.groupFrames
        end

        if groupFrames then
            for groupKey, container in pairs(groupFrames) do
                if container and container:GetName() then
                    local displayName = (L["Custom Icons"] or "Custom Icons") .. ": " .. groupKey
                    self:RegisterMover(container, "DDingUI_DynGroup_" .. groupKey, displayName)
                end
            end
        end
    end
end

-- BuffTracker 동적 프레임 등록 (바/아이콘/텍스트 모드)
function Movers:RegisterBuffTrackerFrames()
    -- [FIX] 활성(표시된) 프레임만 등록, stale mover 정리
    local activeKeys = {}

    -- 기존 BuffTracker mover 업데이트 또는 새로 등록
    local function RegisterOrUpdateMover(frame, key, displayName)
        if not frame or not frame:GetName() then return end

        -- [FIX] 숨겨진 프레임은 스킵 (삭제된 버프 추적기의 excess 프레임)
        if not frame:IsShown() then return end

        activeKeys[key] = true

        if self.CreatedMovers[key] then
            -- 기존 mover 업데이트 (parent 변경 시)
            local holder = self.CreatedMovers[key]
            if holder.parent ~= frame then
                holder.parent = frame
                -- Mover 크기/위치 업데이트
                local ok, point, anchor, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
                if ok and point and holder.mover then
                    holder.mover:ClearAllPoints()
                    holder.mover:SetPoint(point, anchor or UIParent, relPoint or point, x or 0, y or 0)
                    local okS, pw, ph = pcall(function() return frame:GetWidth(), frame:GetHeight() end)
                    if okS and pw and pw > 0 and ph and ph > 0 then
                        holder.mover:SetSize(pw, math.max(ph, 1))
                    end
                end
            end
        else
            -- 새 mover 등록
            self:RegisterMover(frame, key, displayName)
        end
    end

    -- 바 프레임 등록
    local barFrames = DDingUI.GetTrackedBuffBars and DDingUI:GetTrackedBuffBars() or {}
    for idx, bar in pairs(barFrames) do
        local key = "DDingUI_BuffTrackerBar_" .. idx
        local displayName = (L["Buff Tracker Bar"] or "Buff Tracker Bar") .. " #" .. idx
        RegisterOrUpdateMover(bar, key, displayName)
    end

    -- 아이콘 프레임 등록
    local iconFrames = DDingUI.GetTrackedBuffIcons and DDingUI:GetTrackedBuffIcons() or {}
    for idx, icon in pairs(iconFrames) do
        local key = "DDingUI_BuffTrackerIcon_" .. idx
        local displayName = (L["Buff Tracker Icon"] or "Buff Tracker Icon") .. " #" .. idx
        RegisterOrUpdateMover(icon, key, displayName)
    end

    -- 텍스트 프레임 등록
    local textFrames = DDingUI.GetTrackedBuffTexts and DDingUI:GetTrackedBuffTexts() or {}
    for idx, textFrame in pairs(textFrames) do
        local key = "DDingUI_BuffTrackerText_" .. idx
        local displayName = (L["Buff Tracker Text"] or "Buff Tracker Text") .. " #" .. idx
        RegisterOrUpdateMover(textFrame, key, displayName)
    end

    -- [FIX] stale BuffTracker mover 정리 (삭제된 추적기의 excess mover 제거)
    local staleKeys
    for name in pairs(self.CreatedMovers) do
        if string.match(name, "^DDingUI_BuffTracker%w+_%d+$") and not activeKeys[name] then
            if not staleKeys then staleKeys = {} end
            staleKeys[#staleKeys + 1] = name
        end
    end
    if staleKeys then
        for _, key in ipairs(staleKeys) do
            self:UnregisterMover(key)
        end
    end
end

-- BuffTracker 프레임 스캔 및 등록 (타이머 기반)
function Movers:ScanAndRegisterBuffTrackers()
    if not self.ConfigMode then return end
    self:RegisterBuffTrackerFrames()
end

-- Auto-initialize (전통적 프레임 이벤트 방식)
local moverInitFrame = CreateFrame("Frame")
moverInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
moverInitFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function()
            Movers:Initialize()
        end)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)
