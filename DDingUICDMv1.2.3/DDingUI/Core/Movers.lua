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

-- Mover 이름과 모듈 설정 경로 매핑 (파일 상단에 정의하여 모든 함수에서 접근 가능)
local MoverToModuleMapping = {
    ["DDingUI_PowerBar"] = { path = "powerBar", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", hasBarAnchorFlip = true },
    ["DDingUI_SecondaryPowerBar"] = { path = "secondaryPowerBar", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint" },
    ["DDingUI_PlayerCastBar"] = { path = "castBar", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint" },
    ["DDingUI_BuffTrackerBar"] = { path = "buffTrackerBar", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint" },
    -- Missing Alerts
    ["DDingUI_PetMissingAlert"] = { path = "missingAlerts", xKey = "petOffsetX", yKey = "petOffsetY", pointKey = "petAnchorPoint" },
    ["DDingUI_BuffMissingAlert"] = { path = "missingAlerts", xKey = "buffOffsetX", yKey = "buffOffsetY", pointKey = "buffAnchorPoint" },
}

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

    -- Calculate final position (ElvUI style 9-point system)
    local x, y, point = Movers:CalculateMoverPoints(mover)
    mover:ClearAllPoints()

    -- 앵커 포인트를 일치시켜야 정확한 위치에 배치됨
    mover:SetPoint(point, UIParent, point, x, y)

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
            mover:SetSize(width, height)
        else
            mover:SetSize(100, MIN_MOVER_HEIGHT)
        end
    end

    SyncSize()

    -- Hook size changes
    if parent.SetSize then
        hooksecurefunc(parent, "SetSize", SyncSize)
    end
    if parent.SetWidth then
        hooksecurefunc(parent, "SetWidth", function()
            if parent:GetWidth() > 0 then
                mover:SetWidth(parent:GetWidth())
            end
        end)
    end
    if parent.SetHeight then
        hooksecurefunc(parent, "SetHeight", function()
            if parent:GetHeight() > 0 then
                mover:SetHeight(parent:GetHeight())
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
                                 or "EssentialCooldownViewer"
                local anchorFrame = _G[attachTo]

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
                local moverCenterX, moverCenterY = holder.mover:GetCenter()
                if anchorFrame and anchorFrame:IsShown() and moverCenterX then
                    -- anchor의 anchorPoint 위치 계산 (CENTER가 아닌 실제 사용되는 anchorPoint)
                    local anchorPointX, anchorPointY = GetPointPosition(anchorFrame, anchorPoint)
                    if anchorPointX then
                        -- DDingUI:Scale()은 스냅 함수(곱셈 아님)이므로 / mult 하면 안 됨
                        -- 저장값이 DDingUI:Scale(x)로 그대로 사용되므로 UI 좌표 그대로 저장
                        relX = moverCenterX - anchorPointX
                        relY = moverCenterY - anchorPointY
                    end
                elseif moverCenterX then
                    -- anchor가 없으면 UIParent 중심 기준
                    local uiCenterX, uiCenterY = UIParent:GetCenter()
                    if uiCenterX then
                        relX = moverCenterX - uiCenterX
                        relY = moverCenterY - uiCenterY
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
end

function Movers:LoadMoverPosition(name)
    local holder = self.CreatedMovers[name]
    if not holder then return end

    -- MoverToModuleMapping에 있는 프레임은 모듈 설정에서 읽음
    -- (이동모드와 메뉴 설정이 같은 곳에 저장되어 최신 값이 적용됨)
    local mapping = MoverToModuleMapping[name]
    if mapping and DDingUI.db and DDingUI.db.profile[mapping.path] then
        local cfg = DDingUI.db.profile[mapping.path]
        -- DDingUI:Scale 사용 (픽셀퍼펙트 스케일, v1.1.5.5와 일관성)
        local anchorPoint = cfg[mapping.pointKey] or "CENTER"
        local attachTo = cfg[mapping.attachKey] or "UIParent"
        local offsetX = DDingUI:Scale(cfg[mapping.xKey] or 0)
        local offsetY = DDingUI:Scale(cfg[mapping.yKey] or 0)
        local anchorFrame = _G[attachTo] or UIParent

        -- 모듈과 동일하게 CENTER 사용 (모듈들이 SetPoint("CENTER", anchor, anchorPoint, ...) 사용)
        holder.mover:ClearAllPoints()
        holder.mover:SetPoint("CENTER", anchorFrame, anchorPoint, offsetX, offsetY)

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

                attachTo = settings.attachTo or globalCfg.attachTo or "EssentialCooldownViewer"
                local anchorFrame = _G[attachTo] or UIParent

                if offsetX ~= nil and offsetY ~= nil then
                    holder.mover:ClearAllPoints()
                    holder.mover:SetPoint("CENTER", anchorFrame, anchorPoint, DDingUI:Scale(offsetX), DDingUI:Scale(offsetY))
                    self:UpdateParentPosition(name)
                    return
                end
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
    local mapping = MoverToModuleMapping[name]
    if mapping and not self.ConfigMode then
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
    if mapping and DDingUI.db and DDingUI.db.profile[mapping.path] then
        local cfg = DDingUI.db.profile[mapping.path]
        if mapping.xKey then cfg[mapping.xKey] = 0 end
        if mapping.yKey then cfg[mapping.yKey] = 0 end
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

--------------------------------------------------------------------------------
-- Config Mode
--------------------------------------------------------------------------------

function Movers:ToggleConfigMode()
    if InCombatLockdown() then
        print("|cffff6666DDingUI:|r " .. (L["Cannot toggle movers in combat"] or "Cannot toggle movers in combat"))
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

    for name, holder in pairs(self.CreatedMovers) do
        if holder.parent and holder.mover then
            local ok, point, anchor, relPoint, x, y = pcall(holder.parent.GetPoint, holder.parent, 1)
            if ok and point then
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

    print("|cff00ff00DDingUI:|r " .. (L["Mover mode enabled"] or "Mover mode enabled. Click a frame to adjust."))
end

-- Mover 위치를 모듈 설정으로 동기화
function Movers:SyncMoverToModuleSettings(name)
    local holder = self.CreatedMovers[name]
    if not holder or not holder.mover then return end

    local mapping = MoverToModuleMapping[name]
    if not mapping then return end
    if not DDingUI.db or not DDingUI.db.profile[mapping.path] then return end

    local cfg = DDingUI.db.profile[mapping.path]

    -- 모버의 실제 앵커 상태를 모듈 설정에 반영 -- [FIX: anchor sync]
    local _, moverRelTo, moverRelPoint = holder.mover:GetPoint(1)
    local anchorPoint = moverRelPoint or cfg[mapping.pointKey] or "CENTER"
    local attachToName = (moverRelTo and moverRelTo:GetName()) or (mapping.attachKey and cfg[mapping.attachKey]) or "UIParent"
    local anchorFrame = _G[attachToName] or UIParent

    -- 앵커 프레임이 자기 자신이면 UIParent 폴백
    if anchorFrame == holder.parent then
        anchorFrame = UIParent
        attachToName = "UIParent"
    end

    -- 앵커 프레임이 보이지 않으면 UIParent CENTER로 폴백
    if not anchorFrame:IsShown() or not anchorFrame:GetCenter() then
        anchorFrame = UIParent
        attachToName = "UIParent"
        anchorPoint = "CENTER"
        if mapping.attachKey then
            cfg[mapping.attachKey] = attachToName
        end
        if mapping.pointKey then
            cfg[mapping.pointKey] = anchorPoint
        end
    end

    -- Mover의 시각적 CENTER 위치 (화면 좌표)
    local moverCenterX, moverCenterY = holder.mover:GetCenter()
    if not moverCenterX then return end

    -- 앵커 프레임의 anchorPoint 위치 (화면 좌표)
    local anchorPointX, anchorPointY = GetPointPosition(anchorFrame, anchorPoint)
    if not anchorPointX then return end

    -- mover CENTER에서 anchor anchorPoint까지의 오프셋
    local rawOffsetX = moverCenterX - anchorPointX
    local rawOffsetY = moverCenterY - anchorPointY

    -- barAnchorPoint 플립 보정 (PrimaryPowerBar: TOP↔BOTTOM 변환)
    if mapping.hasBarAnchorFlip then
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

    -- PowerBar 특별 처리: noSecondaryOffsetY도 함께 업데이트
    if name == "DDingUI_PowerBar" then
        cfg.noSecondaryOffsetY = offsetY
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

    print("|cff00ff00DDingUI:|r " .. (L["Mover mode disabled"] or "Mover mode disabled. Positions saved."))
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

    -- 기존 그리드 프레임 재사용 (텍스처만 재생성)
    if self.Grid then
        -- 기존 라인 텍스처 숨기기
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

    -- 기존 텍스처 재사용 또는 새로 생성하는 헬퍼
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

    -- Create vertical grid lines
    for i = 0, width, gridSize do
        local line = GetOrCreateLine()
        line:SetSize(1, height)
        line:SetPoint("TOP", grid, "TOPLEFT", i, 0)

        -- Center line is highlighted
        if math.abs(i - width/2) < gridSize/2 then
            line:SetColorTexture(1, 0.3, 0.3, 0.7)
            line:SetSize(2, height)
        else
            line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        end
    end

    -- Create horizontal grid lines
    for i = 0, height, gridSize do
        local line = GetOrCreateLine()
        line:SetSize(width, 1)
        line:SetPoint("LEFT", grid, "TOPLEFT", 0, -i)

        -- Center line is highlighted
        if math.abs(i - height/2) < gridSize/2 then
            line:SetColorTexture(1, 0.3, 0.3, 0.7)
            line:SetSize(width, 2)
        else
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

    local nudge = CreateFrame("Frame", "DDingUI_NudgeFrame", UIParent, "BackdropTemplate")
    nudge:SetSize(280, 490)
    nudge:SetPoint("TOP", UIParent, "TOP", 0, -50)
    nudge:SetFrameStrata("FULLSCREEN_DIALOG")
    nudge:SetFrameLevel(200)
    nudge:EnableMouse(true)
    nudge:SetClampedToScreen(true)
    nudge:Hide()

    nudge:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    nudge:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    nudge:SetBackdropBorderColor(0.4, 0.6, 1, 1)

    -- 드래그 가능한 타이틀 바 생성
    local titleBar = CreateFrame("Frame", nil, nudge)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", nudge, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", nudge, "TOPRIGHT", -24, -4)
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

    -- Close button
    local closeBtn = CreateFrame("Button", nil, nudge, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        -- 패널 닫으면 이동 모드도 종료
        if Movers.ConfigMode then
            Movers:ToggleConfigMode()
        else
            nudge:Hide()
        end
    end)

    -- Title
    local title = nudge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText(L["Position Adjustment"] or "Position Adjustment")
    title:SetTextColor(0.4, 0.8, 1, 1)
    nudge.title = title

    -- Selected frame name
    local selectedText = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    selectedText:SetPoint("TOP", title, "BOTTOM", 0, -4)
    selectedText:SetText(L["No frame selected"] or "No frame selected")
    selectedText:SetTextColor(1, 0.8, 0, 1)
    nudge.selectedText = selectedText

    -- Anchor info (더 눈에 띄게)
    local anchorLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchorLabel:SetPoint("TOP", selectedText, "BOTTOM", 0, -4)
    anchorLabel:SetText("Anchor: --")
    anchorLabel:SetTextColor(0.5, 1, 0.5, 1)
    nudge.anchorLabel = anchorLabel

    --------------------------------------------------------------------------------
    -- Anchor Point & Frame Dropdowns
    --------------------------------------------------------------------------------
    local anchorY = -70

    -- Anchor Points list
    local ANCHOR_POINTS = {
        "TOPLEFT", "TOP", "TOPRIGHT",
        "LEFT", "CENTER", "RIGHT",
        "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"
    }

    -- Anchor Point Label
    local anchorPointLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchorPointLabel:SetPoint("TOPLEFT", nudge, "TOPLEFT", 15, anchorY)
    anchorPointLabel:SetText(L["Anchor Point"] or "Anchor Point")

    -- Anchor Point Dropdown
    local anchorPointDropdown = CreateFrame("Frame", "DDingUI_AnchorPointDropdown", nudge, "UIDropDownMenuTemplate")
    anchorPointDropdown:SetPoint("TOPLEFT", anchorPointLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(anchorPointDropdown, 100)
    nudge.anchorPointDropdown = anchorPointDropdown

    local function AnchorPointDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, point in ipairs(ANCHOR_POINTS) do
            info.text = point
            info.value = point
            info.func = function(self)
                UIDropDownMenu_SetSelectedValue(anchorPointDropdown, self.value)
                UIDropDownMenu_SetText(anchorPointDropdown, self.value)
                -- Apply anchor change
                local mover = Movers.SelectedMover
                if mover then
                    -- Undo용 현재 위치 저장
                    local oldPoint = GetPoint(mover)
                    local _, anchorFrame, _, x, y = mover:GetPoint(1)
                    mover:ClearAllPoints()

                    -- 모듈과 동일하게 CENTER 사용
                    mover:SetPoint("CENTER", anchorFrame or UIParent, self.value, x or 0, y or 0)

                    Movers:PushUndo(mover.name, oldPoint)
                    Movers:SaveMoverPosition(mover.name)
                    Movers:UpdateParentPosition(mover.name)
                    nudge:UpdateInfo()
                end
            end
            info.checked = (UIDropDownMenu_GetSelectedValue(anchorPointDropdown) == point)
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(anchorPointDropdown, AnchorPointDropdown_Initialize)

    -- Anchor Frame Label
    local anchorFrameLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchorFrameLabel:SetPoint("TOPLEFT", nudge, "TOPLEFT", 150, anchorY)
    anchorFrameLabel:SetText(L["Anchor To"] or "Anchor To")

    -- Anchor Frame Dropdown
    local anchorFrameDropdown = CreateFrame("Frame", "DDingUI_AnchorFrameDropdown", nudge, "UIDropDownMenuTemplate")
    anchorFrameDropdown:SetPoint("TOPLEFT", anchorFrameLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(anchorFrameDropdown, 100)
    nudge.anchorFrameDropdown = anchorFrameDropdown

    local function AnchorFrameDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()

        -- UIParent option
        info.text = "UIParent"
        info.value = "UIParent"
        info.func = function(self)
            UIDropDownMenu_SetSelectedValue(anchorFrameDropdown, self.value)
            UIDropDownMenu_SetText(anchorFrameDropdown, self.value)
            local mover = Movers.SelectedMover
            if mover then
                -- Undo용 현재 위치 저장
                local oldPoint = GetPoint(mover)
                local _, _, relPoint, x, y = mover:GetPoint(1)
                mover:ClearAllPoints()
                -- 모듈과 동일하게 CENTER 사용, relPoint (anchorPoint) 유지
                mover:SetPoint("CENTER", UIParent, relPoint or "CENTER", x or 0, y or 0)
                Movers:PushUndo(mover.name, oldPoint)
                Movers:SaveMoverPosition(mover.name)
                Movers:UpdateParentPosition(mover.name)
                nudge:UpdateInfo()
            end
        end
        info.checked = (UIDropDownMenu_GetSelectedValue(anchorFrameDropdown) == "UIParent")
        UIDropDownMenu_AddButton(info, level)

        -- Other movers (parent 프레임 이름 사용)
        local currentMover = Movers.SelectedMover
        local currentHolder = currentMover and Movers.CreatedMovers[currentMover.name]
        for name, holder in pairs(Movers.CreatedMovers or {}) do
            -- 현재 선택된 mover의 parent는 제외 (자기 앵커 방지)
            if holder.mover and holder.mover ~= currentMover and holder.parent ~= (currentHolder and currentHolder.parent) then
                local parentName = holder.parent and holder.parent:GetName()
                if parentName then
                    info.text = holder.mover.displayText or name
                    info.value = parentName  -- parent 프레임 이름 사용
                    info.func = function(self)
                        UIDropDownMenu_SetSelectedValue(anchorFrameDropdown, self.value)
                        UIDropDownMenu_SetText(anchorFrameDropdown, self.arg1 or self.value)
                        local mover = Movers.SelectedMover
                        if mover then
                            local targetFrame = _G[self.value]
                            if targetFrame then
                                -- Undo용 현재 위치 저장
                                local oldPoint = GetPoint(mover)
                                local _, _, relPoint, x, y = mover:GetPoint(1)
                                mover:ClearAllPoints()
                                -- 모듈과 동일하게 CENTER 사용, relPoint (anchorPoint) 유지, 오프셋은 0으로 리셋
                                mover:SetPoint("CENTER", targetFrame, relPoint or "CENTER", 0, 0)
                                Movers:PushUndo(mover.name, oldPoint)
                                Movers:SaveMoverPosition(mover.name)
                                Movers:UpdateParentPosition(mover.name)
                                nudge:UpdateInfo()
                            end
                        end
                    end
                    info.arg1 = holder.mover.displayText or name
                    info.checked = (UIDropDownMenu_GetSelectedValue(anchorFrameDropdown) == parentName)
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
    end
    UIDropDownMenu_Initialize(anchorFrameDropdown, AnchorFrameDropdown_Initialize)

    --------------------------------------------------------------------------------
    -- Anchor Selection Button (앵커 선택 버튼) - StartFramePicker 사용
    --------------------------------------------------------------------------------
    local anchorSelectY = -110

    -- Anchor Selection Button
    local anchorSelectBtn = CreateFrame("Button", nil, nudge, "UIPanelButtonTemplate")
    anchorSelectBtn:SetSize(250, 24)
    anchorSelectBtn:SetPoint("TOP", nudge, "TOP", 0, anchorSelectY)
    anchorSelectBtn:SetText(L["Select Anchor"] or "Select Anchor")
    nudge.anchorSelectBtn = anchorSelectBtn

    anchorSelectBtn:SetScript("OnClick", function()
        if not Movers.SelectedMover then
            print("|cffff6666DDingUI:|r " .. (L["Select a frame first"] or "Select a frame first"))
            return
        end

        -- DDingUI:StartFramePicker 사용 (다른 메뉴와 동일한 기능)
        DDingUI:StartFramePicker(function(frameName)
            if not frameName or not Movers.SelectedMover then return end

            local mv = Movers.SelectedMover
            local targetFrame = _G[frameName] or UIParent
            local holder = Movers.CreatedMovers[mv.name]

            -- 자기 자신 또는 parent 프레임은 앵커로 선택 불가
            -- 1. mover 자체와 비교
            -- 2. holder.parent와 비교
            -- 3. 프레임 이름으로도 비교 (holder가 nil인 경우 대비)
            local parentName = holder and holder.parent and holder.parent:GetName()
            local moverBaseName = mv.name  -- mover.name은 parent 프레임 이름과 동일

            if targetFrame == mv
               or (holder and targetFrame == holder.parent)
               or frameName == parentName
               or frameName == moverBaseName then
                print("|cffff6666DDingUI:|r " .. (L["Cannot anchor to self"] or "Cannot anchor to self"))
                return
            end

            -- Undo용 현재 위치 저장
            local oldPointStr = GetPoint(mv)
            local _, _, relPoint, px, py = mv:GetPoint(1)
            mv:ClearAllPoints()
            -- 모듈과 동일하게 CENTER 사용, relPoint (anchorPoint) 유지, 오프셋 0으로 리셋
            mv:SetPoint("CENTER", targetFrame, relPoint or "CENTER", 0, 0)

            Movers:PushUndo(mv.name, oldPointStr)
            Movers:SaveMoverPosition(mv.name)
            -- 실제 parent 프레임도 같이 이동
            Movers:UpdateParentPosition(mv.name)

            -- 모듈 설정에도 새 앵커 저장
            local mapping = MoverToModuleMapping[mv.name]
            if mapping and DDingUI.db and DDingUI.db.profile[mapping.path] then
                local cfg = DDingUI.db.profile[mapping.path]
                if mapping.attachKey then
                    cfg[mapping.attachKey] = frameName
                end
            end

            nudge:UpdateInfo()

            -- 드롭다운 업데이트
            UIDropDownMenu_SetSelectedValue(nudge.anchorFrameDropdown, frameName)
            UIDropDownMenu_SetText(nudge.anchorFrameDropdown, frameName)
        end)
    end)

    -- Coordinate container
    local coordY = -140

    -- X coordinate
    local xLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    xLabel:SetPoint("TOPLEFT", nudge, "TOPLEFT", 20, coordY)
    xLabel:SetText("X:")

    local xEditBox = CreateFrame("EditBox", nil, nudge, "InputBoxTemplate")
    xEditBox:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)
    xEditBox:SetSize(70, 20)
    xEditBox:SetAutoFocus(false)
    xEditBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and Movers.SelectedMover then
            local currentX = Movers.SelectedMover._lastX or 0
            Movers:NudgeMover(val - currentX, 0)
        end
        self:ClearFocus()
    end)
    nudge.xEditBox = xEditBox

    -- Y coordinate
    local yLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    yLabel:SetPoint("LEFT", xEditBox, "RIGHT", 20, 0)
    yLabel:SetText("Y:")

    local yEditBox = CreateFrame("EditBox", nil, nudge, "InputBoxTemplate")
    yEditBox:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)
    yEditBox:SetSize(70, 20)
    yEditBox:SetAutoFocus(false)
    yEditBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and Movers.SelectedMover then
            local currentY = Movers.SelectedMover._lastY or 0
            Movers:NudgeMover(0, val - currentY)
        end
        self:ClearFocus()
    end)
    nudge.yEditBox = yEditBox

    -- Arrow buttons
    local arrowCenterY = -190
    local arrowSize = 28

    local function CreateArrowButton(direction, xOff, yOff)
        local btn = CreateFrame("Button", nil, nudge)
        btn:SetSize(arrowSize, arrowSize)
        btn:SetPoint("TOP", nudge, "TOP", xOff, arrowCenterY + yOff)

        local texPath = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
        btn:SetNormalTexture(texPath)
        btn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

        local rotation = 0
        if direction == "UP" then rotation = 90
        elseif direction == "DOWN" then rotation = 270
        elseif direction == "LEFT" then rotation = 180
        end

        btn:GetNormalTexture():SetRotation(math.rad(rotation))
        btn:GetPushedTexture():SetRotation(math.rad(rotation))

        btn:SetScript("OnClick", function()
            local amount = IsShiftKeyDown() and 10 or 1
            if direction == "UP" then Movers:NudgeMover(0, amount)
            elseif direction == "DOWN" then Movers:NudgeMover(0, -amount)
            elseif direction == "LEFT" then Movers:NudgeMover(-amount, 0)
            elseif direction == "RIGHT" then Movers:NudgeMover(amount, 0)
            end
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(direction, 1, 1, 1)
            GameTooltip:AddLine("Shift = 10px", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        return btn
    end

    nudge.upBtn = CreateArrowButton("UP", 0, 20)
    nudge.downBtn = CreateArrowButton("DOWN", 0, -20)
    nudge.leftBtn = CreateArrowButton("LEFT", -35, 0)
    nudge.rightBtn = CreateArrowButton("RIGHT", 35, 0)

    --------------------------------------------------------------------------------
    -- Settings Section
    --------------------------------------------------------------------------------
    local settingsY = -245

    -- Separator
    local separator = nudge:CreateTexture(nil, "ARTWORK")
    separator:SetSize(250, 1)
    separator:SetPoint("TOP", nudge, "TOP", 0, settingsY)
    separator:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Settings label
    local settingsLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsLabel:SetPoint("TOP", separator, "BOTTOM", 0, -6)
    settingsLabel:SetText(L["Settings"] or "Settings")
    settingsLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Helper function for checkboxes
    local function CreateCheckbox(label, yOffset, setting, onClick, indent)
        local cb = CreateFrame("CheckButton", nil, nudge, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", nudge, "TOPLEFT", indent or 12, yOffset)
        cb:SetChecked(Movers.Settings[setting])

        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        text:SetText(label)
        cb.label = text

        cb:SetScript("OnClick", function(self)
            Movers.Settings[setting] = self:GetChecked()
            if onClick then onClick(self:GetChecked()) end
        end)

        return cb
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

    -- Right side: Sliders
    local sliderX = 150

    -- Grid Size
    local gridSizeLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gridSizeLabel:SetPoint("TOPLEFT", nudge, "TOPLEFT", sliderX, checkY)
    gridSizeLabel:SetText((L["Grid"] or "Grid") .. ": " .. Movers.Settings.gridSize)
    nudge.gridSizeLabel = gridSizeLabel

    local gridSizeSlider = CreateFrame("Slider", nil, nudge, "OptionsSliderTemplate")
    gridSizeSlider:SetSize(100, 14)
    gridSizeSlider:SetPoint("TOPLEFT", gridSizeLabel, "BOTTOMLEFT", 0, -2)
    gridSizeSlider:SetMinMaxValues(16, 128)
    gridSizeSlider:SetValueStep(8)
    gridSizeSlider:SetObeyStepOnDrag(true)
    gridSizeSlider:SetValue(Movers.Settings.gridSize)
    gridSizeSlider.Low:SetText("16")
    gridSizeSlider.High:SetText("128")
    gridSizeSlider.Text:SetText("")
    gridSizeSlider:SetScript("OnValueChanged", function(self, value)
        value = Round(value)
        Movers.Settings.gridSize = value
        gridSizeLabel:SetText((L["Grid"] or "Grid") .. ": " .. value)
        if Movers.Settings.gridEnabled then
            Movers:CreateGrid()
            Movers:ShowGrid()
        end
    end)
    nudge.gridSizeSlider = gridSizeSlider

    -- Snap Range
    local snapThresholdLabel = nudge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    snapThresholdLabel:SetPoint("TOPLEFT", gridSizeSlider, "BOTTOMLEFT", 0, -14)
    snapThresholdLabel:SetText((L["Snap"] or "Snap") .. ": " .. Movers.Settings.snapThreshold)
    nudge.snapThresholdLabel = snapThresholdLabel

    local snapThresholdSlider = CreateFrame("Slider", nil, nudge, "OptionsSliderTemplate")
    snapThresholdSlider:SetSize(100, 14)
    snapThresholdSlider:SetPoint("TOPLEFT", snapThresholdLabel, "BOTTOMLEFT", 0, -2)
    snapThresholdSlider:SetMinMaxValues(5, 30)
    snapThresholdSlider:SetValueStep(1)
    snapThresholdSlider:SetObeyStepOnDrag(true)
    snapThresholdSlider:SetValue(Movers.Settings.snapThreshold)
    snapThresholdSlider.Low:SetText("5")
    snapThresholdSlider.High:SetText("30")
    snapThresholdSlider.Text:SetText("")
    snapThresholdSlider:SetScript("OnValueChanged", function(self, value)
        value = Round(value)
        Movers.Settings.snapThreshold = value
        snapThresholdLabel:SetText((L["Snap"] or "Snap") .. ": " .. value)
    end)
    nudge.snapThresholdSlider = snapThresholdSlider

    --------------------------------------------------------------------------------
    -- Button Row: Reset | Undo | Redo | Done
    --------------------------------------------------------------------------------
    local btnWidth = 58
    local btnSpacing = 6
    local totalWidth = (btnWidth * 4) + (btnSpacing * 3)
    local startX = -totalWidth / 2

    -- Reset 버튼 (선택된 프레임 리셋)
    local resetBtn = CreateFrame("Button", nil, nudge, "UIPanelButtonTemplate")
    resetBtn:SetSize(btnWidth, 22)
    resetBtn:SetPoint("BOTTOM", nudge, "BOTTOM", startX + btnWidth/2, 12)
    resetBtn:SetText(L["Reset"] or "Reset")
    resetBtn:SetScript("OnClick", function()
        if Movers.SelectedMover then
            -- Undo용 현재 위치 저장
            local oldPoint = GetPoint(Movers.SelectedMover)
            Movers:PushUndo(Movers.SelectedMover.name, oldPoint)
            Movers:ResetMoverPosition(Movers.SelectedMover.name)
        end
    end)
    nudge.resetBtn = resetBtn

    -- Undo 버튼
    local undoBtn = CreateFrame("Button", nil, nudge, "UIPanelButtonTemplate")
    undoBtn:SetSize(btnWidth, 22)
    undoBtn:SetPoint("BOTTOM", nudge, "BOTTOM", startX + btnWidth + btnSpacing + btnWidth/2, 12)
    undoBtn:SetText(L["Undo"] or "Undo")
    undoBtn:SetScript("OnClick", function()
        Movers:Undo()
    end)
    undoBtn:Disable()  -- 초기에는 비활성화
    nudge.undoBtn = undoBtn

    -- Redo 버튼
    local redoBtn = CreateFrame("Button", nil, nudge, "UIPanelButtonTemplate")
    redoBtn:SetSize(btnWidth, 22)
    redoBtn:SetPoint("BOTTOM", nudge, "BOTTOM", startX + (btnWidth + btnSpacing) * 2 + btnWidth/2, 12)
    redoBtn:SetText(L["Redo"] or "Redo")
    redoBtn:SetScript("OnClick", function()
        Movers:Redo()
    end)
    redoBtn:Disable()  -- 초기에는 비활성화
    nudge.redoBtn = redoBtn

    -- Done 버튼 (이동모드 종료)
    local doneBtn = CreateFrame("Button", nil, nudge, "UIPanelButtonTemplate")
    doneBtn:SetSize(btnWidth, 22)
    doneBtn:SetPoint("BOTTOM", nudge, "BOTTOM", startX + (btnWidth + btnSpacing) * 3 + btnWidth/2, 12)
    doneBtn:SetText(L["Done"] or "Done")
    doneBtn:SetScript("OnClick", function()
        Movers:ToggleConfigMode()
    end)
    nudge.doneBtn = doneBtn

    -- Undo/Redo 버튼 상태 업데이트 함수
    function nudge:UpdateUndoRedoButtons()
        if self.undoBtn then
            if #Movers.UndoStack > 0 then
                self.undoBtn:Enable()
            else
                self.undoBtn:Disable()
            end
        end
        if self.redoBtn then
            if #Movers.RedoStack > 0 then
                self.redoBtn:Enable()
            else
                self.redoBtn:Disable()
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
            UIDropDownMenu_SetText(self.anchorPointDropdown, "--")
            UIDropDownMenu_SetText(self.anchorFrameDropdown, "--")
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

        self.anchorLabel:SetText(displayAnchorPoint .. " @ " .. anchorName)

        -- 드롭다운 업데이트
        if displayAnchorPoint then
            UIDropDownMenu_SetSelectedValue(self.anchorPointDropdown, displayAnchorPoint)
            UIDropDownMenu_SetText(self.anchorPointDropdown, displayAnchorPoint)
        end

        -- 앵커 프레임 드롭다운 업데이트
        UIDropDownMenu_SetSelectedValue(self.anchorFrameDropdown, anchorName)
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
        UIDropDownMenu_SetText(self.anchorFrameDropdown, displayName)

        -- 앵커 프레임 드롭다운 메뉴 다시 초기화 (현재 선택된 mover 제외)
        UIDropDownMenu_Initialize(self.anchorFrameDropdown, function(dropdown, level)
            local info = UIDropDownMenu_CreateInfo()

            -- UIParent option
            info.text = "UIParent"
            info.value = "UIParent"
            info.func = function(self)
                UIDropDownMenu_SetSelectedValue(nudge.anchorFrameDropdown, self.value)
                UIDropDownMenu_SetText(nudge.anchorFrameDropdown, self.value)
                local mv = Movers.SelectedMover
                if mv then
                    -- Undo용 현재 위치 저장
                    local oldPoint = GetPoint(mv)
                    local _, _, relPoint, px, py = mv:GetPoint(1)
                    mv:ClearAllPoints()
                    -- 모듈과 동일하게 CENTER 사용, relPoint (anchorPoint) 유지
                    mv:SetPoint("CENTER", UIParent, relPoint or "CENTER", px or 0, py or 0)
                    Movers:PushUndo(mv.name, oldPoint)
                    Movers:SaveMoverPosition(mv.name)
                    Movers:UpdateParentPosition(mv.name)
                    nudge:UpdateInfo()
                end
            end
            info.checked = (anchorName == "UIParent")
            UIDropDownMenu_AddButton(info, level)

            -- Other movers (parent 프레임 이름 사용)
            local currentMover = Movers.SelectedMover
            local currentHolder = currentMover and Movers.CreatedMovers[currentMover.name]
            for name, holder in pairs(Movers.CreatedMovers or {}) do
                -- 현재 선택된 mover의 parent는 제외
                if holder.mover and holder.mover ~= currentMover and holder.parent ~= (currentHolder and currentHolder.parent) then
                    local parentFrameName = holder.parent and holder.parent:GetName()
                    if parentFrameName then
                        info.text = holder.mover.displayText or name
                        info.value = parentFrameName  -- parent 프레임 이름 사용
                        info.func = function(self)
                            UIDropDownMenu_SetSelectedValue(nudge.anchorFrameDropdown, self.value)
                            UIDropDownMenu_SetText(nudge.anchorFrameDropdown, self.arg1 or self.value)
                            local mv = Movers.SelectedMover
                            if mv then
                                local targetFrame = _G[self.value]
                                if targetFrame then
                                    -- Undo용 현재 위치 저장
                                    local oldPoint = GetPoint(mv)
                                    local _, _, relPoint, px, py = mv:GetPoint(1)
                                    mv:ClearAllPoints()
                                    -- 모듈과 동일하게 CENTER 사용, relPoint (anchorPoint) 유지, 오프셋 0으로 리셋
                                    mv:SetPoint("CENTER", targetFrame, relPoint or "CENTER", 0, 0)
                                    Movers:PushUndo(mv.name, oldPoint)
                                    Movers:SaveMoverPosition(mv.name)
                                    Movers:UpdateParentPosition(mv.name)
                                    nudge:UpdateInfo()
                                end
                            end
                        end
                        info.arg1 = holder.mover.displayText or name
                        info.checked = (anchorName == parentFrameName)
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end
        end)
    end

    self.NudgeFrame = nudge
end

function Movers:NudgeMover(dx, dy)
    local mover = self.SelectedMover
    if not mover then return end

    -- Undo용 현재 위치 저장
    local oldPoint = GetPoint(mover)

    local _, anchor, relPoint, x, y = mover:GetPoint(1)
    x = (x or 0) + (dx or 0)
    y = (y or 0) + (dy or 0)

    mover:ClearAllPoints()
    -- 모듈과 동일하게 CENTER 사용
    mover:SetPoint("CENTER", anchor or UIParent, relPoint or "CENTER", x, y)

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

-- 앵커 포인트 마이그레이션 (V2: barAnchorPoint 변환 도입)
-- 기존: anchorPoint = point = relativePoint (동일)
-- 새로운: anchorPoint = relativePoint, barAnchorPoint = AnchorToBarAnchor(anchorPoint)
local ANCHOR_MIGRATION_VERSION = 3

function Movers:MigrateAnchorPoints()
    if not DDingUI.db or not DDingUI.db.profile then return end

    local currentVersion = DDingUI.db.profile.anchorMigrationVersion

    -- 새 사용자 (버전 없음): 마이그레이션 불필요, 바로 최신 버전 설정
    if not currentVersion then
        DDingUI.db.profile.anchorMigrationVersion = ANCHOR_MIGRATION_VERSION
        return
    end

    -- 이미 최신 버전: 마이그레이션 불필요
    if currentVersion >= ANCHOR_MIGRATION_VERSION then return end

    -- 프레임 로드 후 절대 좌표 변환 필요
    -- 플래그 설정하여 나중에 처리
    DDingUI.db.profile.pendingMoverMigration = true

    -- 버전 업데이트
    DDingUI.db.profile.anchorMigrationVersion = ANCHOR_MIGRATION_VERSION

    print("|cff00ff00DDingUI:|r 앵커 시스템이 개선되었습니다. 프레임 위치가 절대 좌표로 변환됩니다.")
end

-- 프레임 로드 후 절대 좌표 변환 (지연 마이그레이션)
function Movers:CompleteMoverMigration()
    if not DDingUI.db or not DDingUI.db.profile then return end
    if not DDingUI.db.profile.pendingMoverMigration then return end

    local migratedCount = 0
    -- DDingUI.mult 사용 (픽셀퍼펙트 스케일, 모듈과 일관성)
    local mult = DDingUI.mult or 1
    if mult == 0 then mult = 1 end

    -- 1. MoverToModuleMapping 프레임들 처리 (리소스바, 캐스트바 등)
    for moverName, mapping in pairs(MoverToModuleMapping) do
        local cfg = DDingUI.db.profile[mapping.path]
        if cfg then
            local attachTo = cfg[mapping.attachKey]
            local anchorFrame = attachTo and _G[attachTo]

            -- UIParent가 아닌 다른 프레임에 앵커된 경우 절대 좌표 계산
            if anchorFrame and anchorFrame ~= UIParent and attachTo ~= "UIParent" then
                local frame = _G[moverName]
                if frame and frame.GetCenter then
                    local centerX, centerY = frame:GetCenter()
                    local uiCenterX, uiCenterY = UIParent:GetCenter()

                    if centerX and uiCenterX then
                        local absX = (centerX - uiCenterX) / mult
                        local absY = (centerY - uiCenterY) / mult

                        cfg[mapping.xKey] = Round(absX)
                        cfg[mapping.yKey] = Round(absY)
                        cfg[mapping.attachKey] = "UIParent"
                        cfg[mapping.pointKey] = "CENTER"
                        migratedCount = migratedCount + 1
                    end
                end
            elseif attachTo == "UIParent" or not attachTo then
                -- 이미 UIParent면 anchorPoint 변환만
                local oldAnchorPoint = cfg[mapping.pointKey]
                if oldAnchorPoint then
                    cfg[mapping.pointKey] = BarAnchorToAnchor(oldAnchorPoint)
                    migratedCount = migratedCount + 1
                end
            end
        end
    end

    -- 2. movers 테이블 프레임들 처리 (뷰어 등)
    local movers = DDingUI.db.profile.movers
    if movers then
        for name, pointString in pairs(movers) do
            if pointString and type(pointString) == "string" then
                local point, anchorName, relPoint, x, y = strsplit(",", pointString)
                x = tonumber(x) or 0
                y = tonumber(y) or 0

                local anchorFrame = _G[anchorName]

                if anchorFrame and anchorFrame ~= UIParent and anchorName ~= "UIParent" then
                    -- 다른 프레임에 앵커된 경우: 임시 프레임으로 절대 좌표 계산
                    local tempFrame = CreateFrame("Frame", nil, UIParent)
                    tempFrame:SetSize(50, 50)
                    tempFrame:SetPoint(point, anchorFrame, relPoint, x, y)

                    local centerX, centerY = tempFrame:GetCenter()
                    local uiCenterX, uiCenterY = UIParent:GetCenter()

                    if centerX and uiCenterX then
                        local absX = centerX - uiCenterX
                        local absY = centerY - uiCenterY

                        movers[name] = string.format("CENTER,UIParent,CENTER,%d,%d",
                            Round(absX), Round(absY))
                        migratedCount = migratedCount + 1
                    end

                    tempFrame:Hide()
                    tempFrame:SetParent(nil)
                elseif anchorName == "UIParent" then
                    -- 이미 UIParent면 barAnchorPoint 변환만
                    if point == relPoint then
                        local anchorPoint = relPoint
                        local barAnchorPoint = AnchorToBarAnchor(anchorPoint)
                        movers[name] = string.format("%s,UIParent,%s,%d,%d",
                            barAnchorPoint, anchorPoint, Round(x), Round(y))
                        migratedCount = migratedCount + 1
                    end
                end
            end
        end
    end

    DDingUI.db.profile.pendingMoverMigration = nil

    if migratedCount > 0 then
        print("|cff00ff00DDingUI:|r " .. migratedCount .. "개 프레임 위치가 절대 좌표로 변환되었습니다.")
    end
end

function Movers:Initialize()
    -- 앵커 포인트 마이그레이션 실행
    self:MigrateAnchorPoints()

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
            print("|cff00ff00DDingUI:|r " .. (L["Buff Tracker frames refreshed"] or "Buff Tracker frames refreshed"))
        else
            print("|cffff6666DDingUI:|r " .. (L["Enter mover mode first (/ddmove)"] or "Enter mover mode first (/ddmove)"))
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

    print("|cff00ff00DDingUI:|r Movers initialized. Use /ddmove to toggle.")
end

function Movers:RegisterStandardFrames()
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
    if DDingUI.CustomIcons then
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
    -- 기존 BuffTracker mover 업데이트 또는 새로 등록
    local function RegisterOrUpdateMover(frame, key, displayName)
        if not frame or not frame:GetName() then return end

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
