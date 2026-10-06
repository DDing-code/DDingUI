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
Movers.Guides = nil
Movers.NudgeFrame = nil -- [REFACTOR] StyleLib CreateEditRemote (이름은 호출처 호환용)
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

-- [REFACTOR] 시리즈 공용 편집 모드 부품(StyleLib 1.4 EditMode.lua)을 쓴다.
-- 리모컨·무버 표면·HUD·격자·안내선·스냅 계산은 공용, 위치 모델과 저장은 CDM이 가진다.
local function GetSL()
    return _G.DDingUI_StyleLib
end

local function GetEditSpec()
    local SL = GetSL()
    return SL and SL.EditModeSpec
        or { gridSpacing = 32, gridChoices = { 16, 32, 64 }, snapThreshold = 8, nudge = 1, nudgeShift = 10 }
end

-- 스냅 거리는 시리즈 공용 규격(8)으로 고정한다. 저장된 snapThreshold는 읽어 두기만 하고 쓰지 않는다.
local function GetSnapThreshold()
    return GetEditSpec().snapThreshold or 8
end

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
    ["DDingUI_BuffBarViewer"] = { path = "buffBarViewer", xKey = "offsetX", yKey = "offsetY", attachKey = "attachTo", pointKey = "anchorPoint", selfPointKey = "selfPoint" },
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
    local point, anchorName, relativePoint, x, y
    if type(pointString) == "table" then
        -- 테이블 형식: {point, anchor, relPoint, x, y}
        point = pointString[1]
        local anchorObj = pointString[2]
        anchorName = anchorObj and type(anchorObj) == "table" and anchorObj.GetName and anchorObj:GetName() or "UIParent"
        relativePoint = pointString[3]
        x = tonumber(pointString[4]) or 0
        y = tonumber(pointString[5]) or 0
    else
        point, anchorName, relativePoint, x, y = strsplit(",", pointString)
        x = tonumber(x) or 0
        y = tonumber(y) or 0
    end
    local anchor = _G[anchorName] or UIParent
    -- [FIX] UIParent 앵커는 무조건 CENTER/CENTER 강제
    if anchor == UIParent then
        point = "CENTER"
        relativePoint = "CENTER"
    end
    obj:ClearAllPoints()
    obj:SetPoint(point, anchor, relativePoint, x, y)
end

local function IsBuffTrackerMoverName(name)
    return type(name) == "string" and string.match(name, "^DDingUI_BuffTracker%w+_%d+$") ~= nil
end

local function GetBuffTrackerMoverRecord(name)
    local trackerType, trackerIndex = string.match(name or "", "^DDingUI_BuffTracker(%w+)_(%d+)$")
    local idx = tonumber(trackerIndex)
    if not trackerType or not idx or not DDingUI.db then return nil end

    local profile = DDingUI.db.profile or {}
    local rootCfg = profile.buffTrackerBar or {}
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex) or nil
    local globalStore = DDingUI.db.global and DDingUI.db.global.trackedBuffsPerSpec
    local trackedBuffs = specID and globalStore and globalStore[specID] or rootCfg.trackedBuffs
    local trackedBuff = trackedBuffs and trackedBuffs[idx]
    if not trackedBuff then return nil end

    if trackerType == "Group" and trackedBuff.isGroup then
        trackedBuff.groupSettings = trackedBuff.groupSettings or {}
        return trackerType, idx, trackedBuff, trackedBuff.groupSettings, rootCfg, trackedBuffs
    end

    trackedBuff.settings = trackedBuff.settings or {}
    return trackerType, idx, trackedBuff, trackedBuff.settings, rootCfg, trackedBuffs
end

local function IsMatchingBuffTrackerFrameType(frameType, displayType)
    if frameType == "Bar" then
        return displayType == "bar" or displayType == "ring"
    elseif frameType == "Icon" then
        return displayType == "icon"
    elseif frameType == "Text" then
        return displayType == "text"
    elseif frameType == "Group" then
        return displayType == "group"
    end
    return false
end

local function IsValidBuffTrackerAnchor(anchorName, ownerType, ownerIndex, trackedBuffs)
    local targetType, targetIndexText = string.match(anchorName or "", "^DDingUIBuffTracker(%a+)(%d+)$")
    if not targetType then return true end

    local targetIndex = tonumber(targetIndexText)
    local target = targetIndex and trackedBuffs and trackedBuffs[targetIndex]
    if not target or target.enabled == false then return false end
    if targetType == ownerType and targetIndex == ownerIndex then return false end

    local targetDisplayType = target.displayType or "bar"
    if not IsMatchingBuffTrackerFrameType(targetType, targetDisplayType) then return false end

    local targetSettings = target.settings or {}
    local targetAnchor = targetSettings.attachTo
    if targetType == "Icon" then
        targetAnchor = targetSettings.iconAttachTo or targetAnchor
    elseif targetType == "Text" then
        targetAnchor = targetSettings.textAnchorTo or targetAnchor
    end
    targetAnchor = ATTACH_TO_PROXY[targetAnchor] or targetAnchor

    local ownerFrameName = "DDingUIBuffTracker" .. ownerType .. ownerIndex
    return targetAnchor ~= ownerFrameName
end

local function GetBuffTrackerMoverPointInfo(name)
    local trackerType, trackerIndex, trackedBuff, settings, rootCfg, trackedBuffs = GetBuffTrackerMoverRecord(name)
    if not trackerType then return nil end

    local displayType = trackedBuff.displayType or "bar"
    local attachTo = settings.attachTo or rootCfg.attachTo or "DDingUI_Anchor_Cooldowns"
    local anchorPoint
    local selfPoint

    if trackerType == "Group" then
        attachTo = settings.attachTo or "UIParent"
        anchorPoint = settings.anchorPoint or "CENTER"
        selfPoint = settings.selfPoint or "CENTER"
    elseif trackerType == "Bar" then
        if displayType == "ring" then
            anchorPoint = settings.ringAnchorPoint or "CENTER"
            selfPoint = settings.ringSelfPoint or rootCfg.selfPoint or "CENTER"
        else
            anchorPoint = settings.anchorPoint or rootCfg.anchorPoint or "BOTTOM"
            selfPoint = settings.selfPoint or rootCfg.selfPoint or "CENTER"
        end
    elseif trackerType == "Icon" then
        attachTo = settings.iconAttachTo or attachTo
        anchorPoint = settings.iconAnchorPoint or rootCfg.anchorPoint or "CENTER"
        selfPoint = "CENTER"
    elseif trackerType == "Text" then
        attachTo = settings.textAnchorTo or attachTo
        anchorPoint = settings.textAnchorPoint or settings.textModeAnchorPoint or "CENTER"
        selfPoint = settings.textAnchor or "CENTER"
    else
        anchorPoint = "CENTER"
        selfPoint = "CENTER"
    end

    attachTo = ATTACH_TO_PROXY[attachTo] or attachTo or "UIParent"
    if attachTo == "" then attachTo = "UIParent" end
    if not IsValidBuffTrackerAnchor(attachTo, trackerType, trackerIndex, trackedBuffs) then
        attachTo = "UIParent"
    end
    if attachTo == "UIParent" then
        anchorPoint = "CENTER"
        selfPoint = "CENTER"
    end

    return attachTo, anchorPoint, selfPoint, trackerType, trackedBuff, settings, rootCfg
end

local function SetMoverPointPreservingScreen(mover, selfPoint, anchorFrame, anchorPoint)
    if not mover then return end
    anchorFrame = anchorFrame or UIParent
    selfPoint = selfPoint or "CENTER"
    anchorPoint = anchorPoint or "CENTER"
    if anchorFrame == UIParent then
        selfPoint = "CENTER"
        anchorPoint = "CENTER"
    end

    local selfX, selfY = GetPointPosition(mover, selfPoint)
    if not selfX then
        selfX, selfY = mover:GetCenter()
    end

    local anchorX, anchorY = GetPointPosition(anchorFrame, anchorPoint)
    if not anchorX then
        anchorFrame = UIParent
        selfPoint = "CENTER"
        anchorPoint = "CENTER"
        anchorX, anchorY = UIParent:GetCenter()
    end

    if not selfX or not anchorX then return end

    mover:ClearAllPoints()
    mover:SetPoint(selfPoint, anchorFrame, anchorPoint, Round(selfX - anchorX), Round(selfY - anchorY))
    return selfPoint, anchorPoint
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

-- [REFACTOR] 스냅 계산은 StyleLib 공용 함수(SnapToCenter/SnapToGrid/SnapToRects)를 쓴다.
-- 격자 스냅과 보이는 격자는 같은 간격(Settings.gridSize)·같은 원점(화면 중앙)이다.
-- 우선순위: 화면 중앙 > 다른 프레임의 가장자리·중앙 > 격자.
local function CalculateSnap(x, y, width, height, excludeMover)
    local settings = Movers.Settings
    if not settings.snapEnabled then return x, y end
    local SL = GetSL()
    if not (SL and SL.SnapToGrid and SL.SnapToCenter and SL.SnapToRects) then return x, y end

    local threshold = GetSnapThreshold()
    local screenCenterX, screenCenterY = UIParent:GetCenter()
    local snapX, snapY = x, y
    local lockedX, lockedY = false, false

    if settings.snapToCenter and screenCenterX then
        local dx, hitX = SL.SnapToCenter(x - screenCenterX, threshold)
        local dy, hitY = SL.SnapToCenter(y - screenCenterY, threshold)
        if hitX then snapX = screenCenterX + dx; lockedX = true end
        if hitY then snapY = screenCenterY + dy; lockedY = true end
    end

    if settings.snapToGrid and screenCenterX then
        local spacing = Movers:GetGridSpacing()
        if not lockedX then
            local gx, hit = SL.SnapToGrid(x - screenCenterX, spacing, threshold)
            if hit then snapX = screenCenterX + gx end
        end
        if not lockedY then
            local gy, hit = SL.SnapToGrid(y - screenCenterY, spacing, threshold)
            if hit then snapY = screenCenterY + gy end
        end
    end

    if settings.snapToFrames then
        local rects = {}
        for _, target in ipairs(GetSnapTargets(excludeMover)) do
            rects[#rects + 1] = { target.left, target.bottom, target.right - target.left, target.top - target.bottom }
        end
        if #rects > 0 then
            local dx, dy = SL.SnapToRects({ x - width / 2, y - height / 2, width, height }, rects, threshold)
            if dx ~= 0 and not lockedX then snapX = x + dx end
            if dy ~= 0 and not lockedY then snapY = y + dy end
        end
    end

    return snapX, snapY
end

--------------------------------------------------------------------------------
-- 앵커 상대 오프셋 (HUD·리모컨 X/Y의 단일 기준) -- [REFACTOR]
-- 드래그 중에는 무버가 잠시 화면 절대 좌표로 붙으므로, 드래그 시작 때의 앵커로 환산해 보여 준다.
-- 놓은 뒤 앵커가 유지되면 같은 숫자가 저장된다(SyncMoverToModuleSettings와 같은 계산).
--------------------------------------------------------------------------------

local function GetMoverAnchor(mover)
    local drag = mover and mover._dragAnchor
    if drag then
        return drag[1] or "CENTER", drag[2] or UIParent, drag[3] or "CENTER"
    end
    local selfPt, anchor, relPt = mover:GetPoint(1)
    return selfPt or "CENTER", anchor or UIParent, relPt or selfPt or "CENTER"
end

--- @return x, y, selfPoint, anchorFrame, anchorPoint
function Movers:GetMoverOffset(mover)
    if not mover then return 0, 0, "CENTER", UIParent, "CENTER" end
    local selfPt, anchor, relPt = GetMoverAnchor(mover)
    local selfX, selfY = GetPointPosition(mover, selfPt)
    local anchorX, anchorY = GetPointPosition(anchor, relPt)
    if not selfX or not anchorX then
        local _, _, _, x, y = mover:GetPoint(1)
        return x or 0, y or 0, selfPt, anchor, relPt
    end
    return selfX - anchorX, selfY - anchorY, selfPt, anchor, relPt
end

function Movers:RefreshRemoteInfo()
    local remote = self.NudgeFrame
    if remote and remote:IsShown() and remote.UpdateInfo then
        remote:UpdateInfo()
    end
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
    if Movers.Guides then
        Movers.Guides:ShowAt(snapX, snapY)
    end
    if dragFrame.UpdateSelectionHUD then
        dragFrame:UpdateSelectionHUD()
    end

    -- 드래그 중 parent(bar)도 mover를 따라가도록 업데이트
    if dragFrame.parent then
        dragFrame.parent:ClearAllPoints()
        dragFrame.parent:SetPoint("CENTER", UIParent, "BOTTOMLEFT", snapX, snapY)
    end

    Movers:RefreshRemoteInfo()
end

local updateFrame = CreateFrame("Frame")
Movers._dragUpdateFrame = updateFrame -- 테스트·진단용 참조

local function OnDragStart(mover)
    if InCombatLockdown() then return end
    -- [FIX] 프레임 피커 활성 중에는 드래그 방지
    if DDingUI._framePickerActive then return end

    -- 격자가 꺼져 있으면 드래그 동안만 임시로 보여 준다(사용자 설정은 그대로)
    if not Movers.Settings.gridEnabled then
        Movers:ShowGrid(true)
        mover._tempGridShown = true
    end
    Movers:CreateGuides()

    -- Undo용 초기 위치 + HUD 기준 앵커 저장
    mover._dragStartPoint = GetPoint(mover)
    local selfPt, anchor, relPt = mover:GetPoint(1)
    mover._dragAnchor = { selfPt or "CENTER", anchor or UIParent, relPt or selfPt or "CENTER" }

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
    Movers:HideGuides()

    -- 드래그 동안만 보여 준 격자는 다시 숨긴다(사용자 설정은 그대로)
    if mover._tempGridShown then
        Movers:HideGrid(true)
        mover._tempGridShown = nil
    end

    local isBuffTracker = string.match(mover.name, "^DDingUI_BuffTracker%w+_%d+$")

    -- [FIX] 드래그 종료 시 앵커 계산
    -- 1. 다른 프레임에 스냅됐으면 → 스냅 방향에 따라 앵커/기준점 자동 결정
    -- 2. 스냅 안 됐으면 → 기존 기준점 유지, 오프셋만 재계산
    local holder = Movers.CreatedMovers[mover.name]
    local mapping = holder and MoverToModuleMapping[mover.name]
    local cfg = mapping and DDingUI.db and ResolvePath(DDingUI.db.profile, mapping.path)

    if isBuffTracker then
        -- A free drag is an absolute placement. Dynamic tracker anchors can be
        -- hidden or reused when the active specialization changes.
        SetMoverPointPreservingScreen(mover, "CENTER", UIParent, "CENTER")
        mover._ddExplicitAnchorName = "UIParent"
        mover._ddExplicitAnchorPoint = "CENTER"
        mover._ddExplicitSelfPoint = "CENTER"

        local newPoint = GetPoint(mover)
        if mover._dragStartPoint and mover._dragStartPoint ~= newPoint then
            Movers:PushUndo(mover.name, mover._dragStartPoint)
        end
        mover._dragStartPoint = nil
    mover._dragAnchor = nil
        Movers:SaveMoverPosition(mover.name)

        if Movers.NudgeFrame and Movers.NudgeFrame:IsShown() then
            Movers.NudgeFrame:UpdateInfo()
        end
        return
    end

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
    mover._dragAnchor = nil

    if isBuffTracker then
        Movers:SaveMoverPosition(mover.name)
    else
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
    mover:RegisterForClicks("AnyUp")
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    -- [REFACTOR] 표면·HUD는 시리즈 공용 부품(StyleMover / CreateMoverHUD).
    -- 배경·테두리 색을 직접 그리지 않는다(평상시 accent, 오버 밝아짐, 선택 2px+꺾쇠).
    local SL = GetSL()
    if SL and SL.StyleMover then
        mover.surface = SL.StyleMover(mover, "CDM", { label = displayText or name })
        mover.text = mover.surface.label
    else
        local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(displayText or name)
        mover.text = text
    end
    if SL and SL.CreateMoverHUD then
        mover.hud = SL.CreateMoverHUD(mover, "CDM")
    end

    -- HUD 좌표 = 앵커 상대 오프셋(드래그 중과 후가 같다)
    function mover:UpdateSelectionHUD()
        if not self.hud or not self._selected then return end
        local x, y = Movers:GetMoverOffset(self)
        local width, height = self:GetSize()
        self.hud:Update(x, y, width, height)
    end

    function mover:SetSelectionHUD(selected)
        self._selected = selected and true or false
        if self.surface then self.surface:SetSelected(self._selected) end
        if self.hud then
            self.hud:SetShown(self._selected)
            if self._selected then self:UpdateSelectionHUD() end
        end
    end

    -- Store references
    mover.name = name
    mover.parent = parent
    mover.displayText = displayText

    -- Drag handlers
    mover:SetScript("OnDragStart", OnDragStart)
    mover:SetScript("OnDragStop", OnDragStop)

    -- OnMouseUp to stop dragging + handle right-click
    mover:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            if isDragging then
                OnDragStop(self)
            end
            -- Select this mover
            if DDingUI._framePickerActive then return end
            Movers.SelectedMover = self
            if Movers.NudgeFrame then
                Movers.NudgeFrame:UpdateSelection()
            end
        elseif button == "RightButton" then
            if DDingUI._framePickerActive then return end
            if IsShiftKeyDown() then
                Movers:ResetMoverPosition(self.name)
            else
                -- 우클릭 → 해당 프레임의 설정 메뉴 열기 (종료 시 자동 재열기와 겹치지 않게)
                local guiKey = Movers:GetGUIKeyFromMoverName(self.name)
                -- BuffTracker 개별 바: 인덱스 추출 → 설정 창에서 자동 선택
                local btIndex = tonumber(self.name:match("^DDingUI_BuffTracker%w+_(%d+)"))
                if btIndex then
                    DDingUI._pendingBTSelect = btIndex
                end
                Movers._reopenConfigOnExit = nil
                Movers:ExitEditMode()
                C_Timer.After(0.1, function()
                    if DDingUI.OpenConfigGUI then
                        if guiKey then
                            DDingUI:OpenConfigGUI(nil, guiKey)
                        else
                            DDingUI:OpenConfigGUI()
                        end
                    elseif DDingUI.OpenConfig then
                        DDingUI:OpenConfig()
                        if guiKey then
                            C_Timer.After(0.15, function()
                                if DDingUI.OpenConfigGUI then
                                    DDingUI:OpenConfigGUI(nil, guiKey)
                                end
                            end)
                        end
                    end
                    -- BuffTracker 선택 지연 실행 (패널 렌더링 후)
                    if DDingUI._pendingBTSelect then
                        local idx = DDingUI._pendingBTSelect
                        DDingUI._pendingBTSelect = nil
                        C_Timer.After(0.15, function()
                            local configFrame = _G["DDingUI_ConfigFrame"]
                            local btPanel = configFrame and configFrame.contentArea and configFrame.contentArea._btPanel
                            if btPanel and btPanel.SelectTracker then
                                btPanel:SelectTracker(idx)
                            end
                        end)
                    end
                end)
            end
        end
    end)

    mover:SetScript("OnEnter", function(self)
        self._hover = true
        if self.surface then self.surface:SetHover(true) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.displayText or self.name, 1, 1, 1)
        GameTooltip:AddLine(L["Left-click: Select and adjust"] or "Left-click: Select and adjust", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Drag: Move frame"] or "Drag: Move frame", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Right-click: Open settings"] or "Right-click: Open settings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Shift+Right-click: Reset position"] or "Shift+Right-click: Reset position", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    mover:SetScript("OnLeave", function(self)
        self._hover = false
        if self.surface then self.surface:SetHover(false) end
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
        if mover.UpdateSelectionHUD then
            mover:UpdateSelectionHUD()
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
                local trackedBuff = trackedBuffs[idx]
                local settings
                if buffTrackerType == "Group" and trackedBuff.isGroup then
                    trackedBuff.groupSettings = trackedBuff.groupSettings or {}
                    settings = trackedBuff.groupSettings
                else
                    trackedBuff.settings = trackedBuff.settings or {}
                    settings = trackedBuff.settings
                end

                -- anchor 프레임 기준 상대 좌표 계산 -- [FIX: anchor sync]
                -- 모버의 실제 앵커 상태를 우선 사용 (넛지 패널에서 변경 시 반영)
                local savedAttachTo, savedAnchorPoint, savedSelfPoint = GetBuffTrackerMoverPointInfo(name)
                local moverPoint, moverRelTo, moverRelPoint, moverX, moverY = holder.mover:GetPoint(1)
                local moverAnchorName = moverRelTo and moverRelTo:GetName()
                local attachTo = holder.mover._ddExplicitAnchorName
                                 or moverAnchorName
                                 or savedAttachTo
                                 or settings.attachTo
                                 or (DDingUI.db.profile.buffTrackerBar and DDingUI.db.profile.buffTrackerBar.attachTo)
                                 or "DDingUI_Anchor_Cooldowns" -- [PROXY] 프록시 앵커 폴백
                attachTo = ATTACH_TO_PROXY[attachTo] or attachTo

                -- displayType에 따라 적절한 anchorPoint 가져오기
                -- 모버의 실제 앵커 포인트를 우선 사용 -- [FIX: anchor sync]
                local displayType = trackedBuffs[idx].displayType or "bar"
                local anchorPoint = holder.mover._ddExplicitAnchorPoint or moverRelPoint or savedAnchorPoint or "CENTER"

                local forceUIParentCenter = (attachTo == "UIParent" or attachTo == "")
                if forceUIParentCenter then
                    attachTo = "UIParent"
                    anchorPoint = "CENTER"
                end

                -- DragStop/anchor controls already reconnect the mover to its final anchor.
                -- Persist that exact point instead of deriving it again from screen geometry.
                local relX = tonumber(moverX) or 0
                local relY = tonumber(moverY) or 0
                local moverSelfPoint = holder.mover._ddExplicitSelfPoint or moverPoint or savedSelfPoint or "CENTER"
                if forceUIParentCenter then
                    moverSelfPoint = "CENTER"
                elseif buffTrackerType == "Icon" then
                    moverSelfPoint = "CENTER"
                end

                -- 타입별로 다른 설정 키 사용 (anchor 기준 상대 좌표 relX, relY 사용)
                if buffTrackerType == "Bar" then
                    -- 현재 displayType 확인하여 적절한 offset 저장 (displayType은 위에서 이미 선언됨)
                    if displayType == "ring" then
                        trackedBuffs[idx].settings.ringOffsetX = relX
                        trackedBuffs[idx].settings.ringOffsetY = relY
                        trackedBuffs[idx].settings.ringSelfPoint = moverSelfPoint
                    else
                        trackedBuffs[idx].settings.offsetX = relX
                        trackedBuffs[idx].settings.offsetY = relY
                        trackedBuffs[idx].settings.selfPoint = moverSelfPoint
                    end
                elseif buffTrackerType == "Icon" then
                    trackedBuffs[idx].settings.iconOffsetX = relX
                    trackedBuffs[idx].settings.iconOffsetY = relY
                    trackedBuffs[idx].settings.iconAttachTo = attachTo
                elseif buffTrackerType == "Text" then
                    trackedBuffs[idx].settings.textModeOffsetX = relX
                    trackedBuffs[idx].settings.textModeOffsetY = relY
                    trackedBuffs[idx].settings.textAnchor = moverSelfPoint
                    trackedBuffs[idx].settings.textAnchorTo = attachTo
                elseif buffTrackerType == "Group" then
                    settings.offsetX = relX
                    settings.offsetY = relY
                    settings.selfPoint = moverSelfPoint
                end

                -- 앵커 포인트/프레임 변경도 설정에 동기화 -- [FIX: anchor sync]
                settings.attachTo = attachTo
                if displayType == "ring" then
                    settings.ringAnchorPoint = anchorPoint
                elseif buffTrackerType == "Icon" then
                    settings.iconAnchorPoint = anchorPoint
                elseif buffTrackerType == "Text" then
                    settings.textAnchorPoint = anchorPoint
                else
                    settings.anchorPoint = anchorPoint
                end

                -- 버프 트래커 업데이트
                if DDingUI.SyncBuffTrackerMoverPositions then
                    DDingUI:SyncBuffTrackerMoverPositions()
                elseif DDingUI.UpdateBuffTrackerBar then
                    DDingUI:UpdateBuffTrackerBar()
                end
                holder.mover._ddExplicitAnchorName = nil
                holder.mover._ddExplicitAnchorPoint = nil
                holder.mover._ddExplicitSelfPoint = nil
                if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
                    DDingUI.SpecProfiles:SaveCurrentSpec()
                elseif DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
                    DDingUI.SpecProfiles:MarkDirty()
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

            if trackedBuffs and trackedBuffs[idx] then
                local trackedBuff = trackedBuffs[idx]
                local settings
                if buffTrackerType == "Group" and trackedBuff.isGroup then
                    trackedBuff.groupSettings = trackedBuff.groupSettings or {}
                    settings = trackedBuff.groupSettings
                else
                    trackedBuff.settings = trackedBuff.settings or {}
                    settings = trackedBuff.settings
                end

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
                    anchorPoint = settings.iconAnchorPoint or globalCfg.anchorPoint or "CENTER"
                elseif buffTrackerType == "Text" then
                    offsetX = settings.textModeOffsetX
                    offsetY = settings.textModeOffsetY
                    anchorPoint = settings.textAnchorPoint or settings.textModeAnchorPoint or "CENTER"
                elseif buffTrackerType == "Group" then
                    offsetX = settings.offsetX
                    offsetY = settings.offsetY
                    anchorPoint = settings.anchorPoint or "CENTER"
                end

                local defaultAttachTo = settings.attachTo or globalCfg.attachTo or "DDingUI_Anchor_Cooldowns"
                if buffTrackerType == "Icon" then
                    attachTo = settings.iconAttachTo or defaultAttachTo
                elseif buffTrackerType == "Text" then
                    attachTo = settings.textAnchorTo or defaultAttachTo
                else
                    attachTo = defaultAttachTo
                end
                attachTo = ATTACH_TO_PROXY[attachTo] or attachTo
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
                    elseif buffTrackerType == "Text" then
                        selfPoint = settings.textAnchor or "CENTER"
                    elseif buffTrackerType == "Group" then
                        selfPoint = settings.selfPoint or "CENTER"
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
                if not (InCombatLockdown() and holder.parent.IsProtected and holder.parent:IsProtected()) then
                    holder.parent:ClearAllPoints()
                    holder.parent:SetPoint(point, anchor or UIParent, relPoint or point, x or 0, y or 0)
                end
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

    if not (InCombatLockdown() and holder.parent.IsProtected and holder.parent:IsProtected()) then
        holder.parent:ClearAllPoints()
        holder.parent:SetPoint(point, anchor or UIParent, relPoint or point, x or 0, y or 0)
    end
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
                    elseif name == "DDingUI_BuffBarViewer" and DDingUI.RefreshBuffBarCooldownViewer then
                        pcall(DDingUI.RefreshBuffBarCooldownViewer, DDingUI)
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
    ["DDingUI_BuffBarViewer"]     = "buffBar",
}

function Movers:GetGUIKeyFromMoverName(moverName)
    if not moverName then return nil end

    -- 정적 매핑
    if MOVER_TO_GUI[moverName] then
        return MOVER_TO_GUI[moverName]
    end

    -- GroupSystem groups
    local groupName = moverName:match("^DDingUI_Group_(.+)$")
    if groupName then
        return "groupSystem.group_" .. groupName
    end

    -- Dynamic icon groups
    local dynGroupName = moverName:match("^DDingUI_DynGroup_(.+)$")
    if dynGroupName then
        return "groupSystem.group_" .. dynGroupName
    end

    -- CDM proxy anchors
    local anchorGroupName = moverName:match("^DDingUI_Anchor_(.+)$")
    if anchorGroupName then
        return "groupSystem.group_" .. anchorGroupName
    end

    -- Custom aura frames
    if moverName:match("^DDingUI_BuffTracker") then
        return "buffTracker"
    end

    return nil
end

-- 편집모드 종료 (외부 호출용)
function Movers:ExitEditMode(forCombat)
    if not self.ConfigMode then return end

    -- 전투 진입 중에는 OnDragStop이 전투 잠금으로 조기 반환한다. 여기서
    -- 드래그 갱신을 먼저 끊어 전투 중 프레임 재배치가 이어지지 않게 한다.
    if isDragging then
        isDragging = false
        if dragFrame then dragFrame._dragAnchor = nil end
        dragFrame = nil
        updateFrame:SetScript("OnUpdate", nil)
        self:HideGuides()
    end

    self:HideMovers(forCombat == true)
end

--------------------------------------------------------------------------------
-- Config Mode
--------------------------------------------------------------------------------

function Movers:ToggleConfigMode()
    if InCombatLockdown() then
        DDingUI:Print("|cffff6666" .. (L["Cannot toggle movers in combat"] or "Cannot toggle movers in combat") .. "|r") -- [STYLE]
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
    local silent = self._silentToggle
    self:RefreshEditModeButtons()

    -- DDingUI 메인 설정 창 닫기
    if not silent then
        local configFrame = _G["DDingUI_ConfigFrame"]
        if configFrame and configFrame:IsShown() then
            -- [STYLE] edit-mode handoff closes without the exit motion
            -- [REFACTOR] C12: 진입 때 열려 있던 설정창은 종료 때 다시 연다
            self._reopenConfigOnExit = true
            if configFrame.HideImmediately then configFrame:HideImmediately() else configFrame:Hide() end
        end
    end

    -- 버프 트래커 바들의 레이아웃을 먼저 초기화 (mover 등록 전에)
    if DDingUI.InitializeTrackedBuffBarsForMover then
        DDingUI:InitializeTrackedBuffBarsForMover()
    end

    self:RegisterStandardFrames()

    -- 버프 트래커 프레임이 완전히 생성된 후 mover 등록 (즉시 + 지연)
    self:RegisterBuffTrackerFrames()
    if self.NudgeFrame and self.NudgeFrame.UpdateSelection then
        self.NudgeFrame:UpdateSelection()
    end
    C_Timer.After(0.1, function()
        if not self.ConfigMode then return end
        self:RegisterBuffTrackerFrames()
        if self.NudgeFrame and self.NudgeFrame.UpdateSelection then
            self.NudgeFrame:UpdateSelection()
        end
    end)

    -- [FIX] 편집모드 진입 시 숨김/알파0/크기<10 그룹 프레임 강제 표시
    -- stale mover 정리 전에 실행해야 Mover가 삭제되지 않음
    self._editModeGroupRestore = self._editModeGroupRestore or {}
    wipe(self._editModeGroupRestore)
    local GR = DDingUI.GroupRenderer
    if GR and GR.groupFrames then
        for groupName, frame in pairs(GR.groupFrames) do
            local wasHidden = not frame:IsShown()
            local wasAlphaZero = frame:GetAlpha() < 0.01
            local fw, fh = frame:GetSize()
            local wasTooSmall = (fw < 10 or fh < 10)
            if wasHidden or wasAlphaZero or wasTooSmall then
                self._editModeGroupRestore[groupName] = {
                    hidden = wasHidden,
                    alpha = frame:GetAlpha(),
                    width = fw,
                    height = fh,
                    tooSmall = wasTooSmall,
                }
                if wasHidden then frame:Show() end
                if wasAlphaZero then frame:SetAlpha(1) end
                -- 크기<10 그룹: 레이아웃 설정 기반 팬텀 크기 계산
                if wasTooSmall and GR.ComputeEditModeSize then
                    local calcW, calcH = GR:ComputeEditModeSize(groupName)
                    if calcW and calcH then
                        frame:SetSize(calcW, calcH)
                    else
                        frame:SetSize(math.max(fw, 50), math.max(fh, 20))
                    end
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

            if not silent then
                UIFrameFadeIn(holder.mover, 0.2, 0, 1)
            end
        end
    end

    if not silent then
        -- 편집모드 진입 시 DDingUI 스타일의 은은한 기준 그리드를 자동 표시
        self:ShowGrid()

        -- 리모컨 표시 (StyleLib CreateEditRemote)
        self:ShowRemote()

        -- [FIX] 알파 0으로 숨겨진 CDM 뷰어의 마우스 이벤트 비활성화 + Mover 숨기기
        self._editModeViewerMouse = {}
        self._editModeHiddenMovers = {}
        local cdmViewers = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
        for _, vname in ipairs(cdmViewers) do
            local viewer = _G[vname]
            if viewer and viewer:GetAlpha() < 0.01 then
                self._editModeViewerMouse[vname] = true
                viewer:EnableMouse(false)
                if viewer.viewerFrame then
                    viewer.viewerFrame:EnableMouse(false)
                end
                local holder = self.CreatedMovers[vname]
                if holder and holder.mover and holder.mover:IsShown() then
                    holder.mover:Hide()
                    self._editModeHiddenMovers[vname] = true
                end
            end
        end

        DDingUI:Print("|cff00ff00" .. (L["Mover mode enabled"] or "Mover mode enabled. Click a frame to adjust.") .. "|r") -- [STYLE]
    end
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

function Movers:RestoreEditModeViewerMouse()
    if not self._editModeViewerMouse then return end

    for vname in pairs(self._editModeViewerMouse) do
        local viewer = _G[vname]
        if viewer then
            viewer:EnableMouse(true)
            if viewer.viewerFrame then
                viewer.viewerFrame:EnableMouse(true)
            end
        end
    end

    wipe(self._editModeViewerMouse)
    self._restoreViewerMouseAfterCombat = nil
end

function Movers:HideMovers(forCombat)
    local combatExit = forCombat == true or InCombatLockdown()
    self.ConfigMode = false
    self:RefreshEditModeButtons()

    for name, holder in pairs(self.CreatedMovers) do
        if string.match(name, "^DDingUI_BuffTracker") and holder.mover then
            local currentPoint = GetPoint(holder.mover)
            if holder.mover._startPoint and holder.mover._startPoint ~= currentPoint then
                self:SaveMoverPosition(name)
            end
        end
    end

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
        if holder.mover.SetSelectionHUD then
            holder.mover:SetSelectionHUD(false)
        end
        UIFrameFadeOut(holder.mover, 0.2, 1, 0)
        -- [FIX] 페이드아웃 후 투명 상태로 마우스 클릭을 가로채지 않도록 확실히 Hide 처리
        C_Timer.After(0.25, function()
            if not self.ConfigMode and holder.mover then
                holder.mover:Hide()
            end
        end)
    end

    -- 격자는 숨기되 사용자 설정(gridEnabled)은 그대로 두어 실제 값이 저장되게 한다
    self:HideGrid(true)
    self:HideGuides()
    self:HideRemote()

    self.SelectedMover = nil

    -- Undo/Redo 스택 초기화
    self:ClearUndoRedo()

    -- 설정 저장
    self:SaveSettings()

    if not self._silentToggle then
        DDingUI:Print("|cff00ff00" .. (L["Mover mode disabled"] or "Mover mode disabled. Positions saved.") .. "|r") -- [STYLE]
    end

    -- [REFACTOR] C12: 진입 때 닫은 설정창을 다시 연다 (전투 종료는 제외)
    if self._reopenConfigOnExit then
        self._reopenConfigOnExit = nil
        if not combatExit and DDingUI.OpenConfig then
            C_Timer.After(0, function()
                if not Movers.ConfigMode and not InCombatLockdown() then DDingUI:OpenConfig() end
            end)
        end
    end

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
                    if saved.tooSmall and saved.width and saved.height then
                        frame:SetSize(saved.width, saved.height)
                    end
                end
            end
        end
        wipe(self._editModeGroupRestore)
    end

    -- 기본 CDM 프레임의 입력 속성은 전투 종료 후 복원한다.
    if self._editModeViewerMouse then
        if combatExit then
            self._restoreViewerMouseAfterCombat = true
        else
            self:RestoreEditModeViewerMouse()
        end
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
    if DDingUI.RefreshBuffBarCooldownViewer then
        pcall(DDingUI.RefreshBuffBarCooldownViewer, DDingUI)
    end
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge.NotifyIconsChanged then
        DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
    end
end

function Movers:IsConfigMode()
    return self.ConfigMode
end

--------------------------------------------------------------------------------
-- Grid / Guides (StyleLib CreateEditGrid / CreateEditGuides) -- [REFACTOR]
-- 보이는 격자와 스냅 격자는 같은 간격(Settings.gridSize)·같은 원점(화면 중앙)을 쓴다.
-- 간격은 리모컨의 격자 버튼(16/32/64)이 바꾼다.
--------------------------------------------------------------------------------

function Movers:GetGridSpacing()
    local spacing = tonumber(self.Settings.gridSize)
    if not spacing or spacing <= 0 then spacing = GetEditSpec().gridSpacing or 32 end
    return spacing
end

function Movers:CreateGrid()
    if self.Grid then return self.Grid end
    local SL = GetSL()
    if not (SL and SL.CreateEditGrid) then return nil end
    self.Grid = SL.CreateEditGrid("CDM", { spacing = self:GetGridSpacing() })
    return self.Grid
end

function Movers:CreateGuides()
    if self.Guides then return self.Guides end
    local SL = GetSL()
    if not (SL and SL.CreateEditGuides) then return nil end
    self.Guides = SL.CreateEditGuides("CDM")
    return self.Guides
end

function Movers:HideGuides()
    if self.Guides then self.Guides:Hide() end
end

-- 리모컨 격자 체크 상태를 맞춘다. 공용 체크박스는 SetChecked에서도 onChange를 부르므로 재진입을 막는다.
local function SyncRemoteGrid(on, spacing)
    local remote = Movers.NudgeFrame
    if not (remote and remote.SetGridState) or Movers._syncingRemoteGrid then return end
    Movers._syncingRemoteGrid = true
    remote:SetGridState(on, spacing)
    Movers._syncingRemoteGrid = nil
end

--- 격자 간격을 바꾼다(보이는 격자와 스냅이 함께). 리모컨 버튼이 부른다.
function Movers:SetGridSpacing(spacing)
    spacing = tonumber(spacing)
    if not spacing or spacing <= 0 then return end
    self.Settings.gridSize = spacing
    if self.Grid then self.Grid:SetSpacing(spacing) end
    SyncRemoteGrid(nil, spacing)
end

-- keepSetting이면 사용자 설정(gridEnabled)은 건드리지 않는다(드래그 중 임시 표시, 편집 모드 종료).
function Movers:ShowGrid(keepSetting)
    local grid = self:CreateGrid()
    self._gridVisible = true
    if grid then
        grid:SetSpacing(self:GetGridSpacing())
        grid:ShowAnimated()
    end
    if not keepSetting then
        self.Settings.gridEnabled = true
        SyncRemoteGrid(true)
    end
end

function Movers:HideGrid(keepSetting)
    self._gridVisible = false
    if self.Grid then self.Grid:HideAnimated() end
    if not keepSetting then
        self.Settings.gridEnabled = false
        SyncRemoteGrid(false)
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
-- Edit Remote (StyleLib CreateEditRemote) -- [REFACTOR]
-- 공용: 프레임 선택·선택 정보·X/Y·▲▼◀▶(Shift ×10)·격자 표시/간격·스냅·초기화/실행 취소/다시 실행/완료,
--       Esc 종료·방향키·Ctrl+Z/Y, 둥근 창·시리즈 제목줄, 옮긴 위치 저장(moverSettings.editRemotePos).
-- CDM 전용(opts.extra): 9점 앵커 격자(좌클릭 앵커점 / 우클릭 기준점), 연결 대상 드롭다운, 연결 대상 선택(프레임 피커).
-- 기존 이름 NudgeFrame과 UpdateSelection/UpdateInfo/UpdateUndoRedoButtons는 호출처 호환을 위해 유지한다.
--------------------------------------------------------------------------------

local ANCHOR_POINTS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

local DOT_POSITIONS = {
    TOPLEFT = { x = 0, y = 0 }, TOP = { x = 0.5, y = 0 }, TOPRIGHT = { x = 1, y = 0 },
    LEFT = { x = 0, y = 0.5 }, CENTER = { x = 0.5, y = 0.5 }, RIGHT = { x = 1, y = 0.5 },
    BOTTOMLEFT = { x = 0, y = 1 }, BOTTOM = { x = 0.5, y = 1 }, BOTTOMRIGHT = { x = 1, y = 1 },
}

-- [FIX] alpha=0으로 숨겨진 CDM 뷰어는 앵커 선택 불가 (GroupSystem 대체 시)
local HIDDEN_CDM_VIEWERS = {
    EssentialCooldownViewer = true,
    UtilityCooldownViewer = true,
    BuffIconCooldownViewer = true,
}

local function MoverItems()
    local items = { { text = L["No selection"] or "선택 없음", value = "" } }
    local list = {}
    for name, holder in pairs(Movers.CreatedMovers or {}) do
        if holder.mover then
            list[#list + 1] = { text = holder.mover.displayText or name, value = name }
        end
    end
    table.sort(list, function(a, b) return a.text < b.text end)
    for _, item in ipairs(list) do items[#items + 1] = item end
    return items
end

local function AnchorItems(mover)
    local list = {}
    local currentHolder = mover and Movers.CreatedMovers[mover.name]
    for iterName, holder in pairs(Movers.CreatedMovers or {}) do
        if holder.mover and holder.mover ~= mover and holder.parent ~= (currentHolder and currentHolder.parent) then
            local parentFrameName = holder.parent and holder.parent:GetName()
            if parentFrameName then
                local isHiddenViewer = HIDDEN_CDM_VIEWERS[parentFrameName]
                    and holder.parent.GetAlpha and holder.parent:GetAlpha() < 0.01
                if not isHiddenViewer then
                    list[#list + 1] = { text = holder.mover.displayText or iterName, value = parentFrameName }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.text < b.text end)
    local items = { { text = "UIParent", value = "UIParent" } }
    for _, item in ipairs(list) do items[#items + 1] = item end
    return items
end

local function FrameDisplayName(frameName)
    if not frameName or frameName == "UIParent" then return "UIParent" end
    for name, holder in pairs(Movers.CreatedMovers or {}) do
        if holder.parent and holder.parent:GetName() == frameName then
            return holder.mover.displayText or name
        end
    end
    return frameName
end

-- 선택한 무버의 연결 대상을 바꾼다 (드롭다운·프레임 피커 공용)
local function ApplyAnchorFrame(mover, frameName)
    if not mover or not frameName or frameName == "" then return false end
    local targetFrame = _G[frameName] or UIParent
    local holder = Movers.CreatedMovers[mover.name]
    local parentName = holder and holder.parent and holder.parent:GetName()
    if targetFrame == mover or (holder and targetFrame == holder.parent) or frameName == parentName or frameName == mover.name then
        DDingUI:Print("|cffff6666" .. (L["Cannot anchor to self"] or "Cannot anchor to self") .. "|r")
        return false
    end

    local oldPointStr = GetPoint(mover)
    local selfPt, _, relPoint = mover:GetPoint(1)
    local isBuffTracker = IsBuffTrackerMoverName(mover.name)
    selfPt = selfPt or "CENTER"
    local anchorPoint = relPoint or "CENTER"
    if targetFrame == UIParent then
        selfPt = "CENTER"
        anchorPoint = "CENTER"
    end

    if isBuffTracker then
        mover._ddExplicitAnchorName = frameName
        mover._ddExplicitAnchorPoint = anchorPoint
        SetMoverPointPreservingScreen(mover, selfPt, targetFrame, anchorPoint)
    else
        mover:ClearAllPoints()
        mover:SetPoint(selfPt, targetFrame, anchorPoint, 0, 0)
    end

    Movers:PushUndo(mover.name, oldPointStr)
    Movers:SaveMoverPosition(mover.name)
    if not isBuffTracker then
        Movers:UpdateParentPosition(mover.name)
    end

    local mapping = MoverToModuleMapping[mover.name]
    local anchorCfg = mapping and DDingUI.db and ResolvePath(DDingUI.db.profile, mapping.path)
    if anchorCfg and mapping.attachKey then
        anchorCfg[mapping.attachKey] = frameName
    end
    return true
end

-- 9점 격자: 좌클릭 = 앵커점(연결 대상의 기준점), 우클릭 = 기준점(이 프레임의 기준점)
local function ApplyAnchorPoint(mover, apName, isSelfPoint)
    if not mover or not apName then return end
    local oldPoint = GetPoint(mover)
    local selfPt, af, relPt, x, y = mover:GetPoint(1)
    local isBuffTracker = IsBuffTrackerMoverName(mover.name)

    if isSelfPoint then
        if isBuffTracker then
            mover._ddExplicitSelfPoint = apName
            SetMoverPointPreservingScreen(mover, apName, af or UIParent, relPt or "CENTER")
        else
            mover:ClearAllPoints()
            mover:SetPoint(apName, af or UIParent, relPt or "CENTER", x or 0, y or 0)
        end
    else
        if isBuffTracker then
            mover._ddExplicitAnchorPoint = apName
            SetMoverPointPreservingScreen(mover, selfPt or "CENTER", af or UIParent, apName)
        else
            mover:ClearAllPoints()
            mover:SetPoint(selfPt or "CENTER", af or UIParent, apName, x or 0, y or 0)
        end
    end

    Movers:PushUndo(mover.name, oldPoint)
    Movers:SaveMoverPosition(mover.name)
    if not isBuffTracker then
        Movers:UpdateParentPosition(mover.name)
    end
end

-- CDM 전용 구역: 리모컨 opts.extra(parent, y) -> height
local function BuildRemoteExtra(remote, parent, y)
    local SL = GetSL()
    local C = SL.Colors
    local accentFrom, accentTo = SL.GetAccent("CDM")
    accentFrom = accentFrom or { 0.90, 0.45, 0.12, 1 }
    accentTo = accentTo or accentFrom
    local PAD = 14
    local top = y

    local header = SL.CreateSectionHeader(parent, "CDM", L["Anchor"] or "연결", { showLine = true })
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    header:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
    y = y - 28

    -- 9점 앵커 격자 (왼쪽)
    local GRID_W, GRID_H, DOT, DOT_SEL = 118, 72, 10, 16
    local gridBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    gridBox:SetSize(GRID_W + 16, GRID_H + 16)
    gridBox:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    SL.MakeRounded(gridBox, SL.Radius.card, C.bg.input, C.border.default)
    local gridArea = CreateFrame("Frame", nil, gridBox)
    gridArea:SetSize(GRID_W, GRID_H)
    gridArea:SetPoint("CENTER")

    remote._anchorDots = {}
    local function RefreshDots()
        local selfPt, ancPt = remote._selfPointCurrent, remote._anchorPointCurrent
        for _, apName in ipairs(ANCHOR_POINTS) do
            local dot = remote._anchorDots[apName]
            local isSelf, isAnc = apName == selfPt, apName == ancPt
            local color
            if isSelf and isAnc then color = C.text.highlight
            elseif isAnc then color = accentFrom
            elseif isSelf then color = accentTo
            end
            if color then
                dot:SetSize(DOT_SEL, DOT_SEL)
                dot.fill:SetColorTexture(color[1], color[2], color[3], 1)
                dot.ring:SetColorTexture(C.text.highlight[1], C.text.highlight[2], C.text.highlight[3], 0.9)
            else
                dot:SetSize(DOT, DOT)
                dot.fill:SetColorTexture(C.text.dim[1], C.text.dim[2], C.text.dim[3], dot._hover and 0.9 or 0.55)
                dot.ring:SetColorTexture(C.border.active[1], C.border.active[2], C.border.active[3], dot._hover and 0.9 or 0.6)
            end
        end
    end
    remote.RefreshAnchorGrid = RefreshDots

    for _, apName in ipairs(ANCHOR_POINTS) do
        local pos = DOT_POSITIONS[apName]
        local dot = CreateFrame("Button", nil, gridArea)
        dot:SetSize(DOT, DOT)
        dot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        dot:SetPoint("CENTER", gridArea, "TOPLEFT", pos.x * GRID_W, -pos.y * GRID_H)
        dot.ring = dot:CreateTexture(nil, "BACKGROUND")
        dot.ring:SetAllPoints()
        dot.fill = dot:CreateTexture(nil, "ARTWORK")
        dot.fill:SetPoint("TOPLEFT", 1, -1)
        dot.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        dot:SetScript("OnEnter", function(self)
            self._hover = true
            RefreshDots()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 0)
            GameTooltip:AddLine(apName, 1, 1, 1)
            GameTooltip:AddLine(L["Left-click: Change Anchor Point"] or "좌클릭: 앵커점 변경", 0.7, 0.7, 0.7)
            GameTooltip:AddLine(L["Right-click: Change Self Point"] or "우클릭: 기준점 변경", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        dot:SetScript("OnLeave", function(self)
            self._hover = nil
            RefreshDots()
            GameTooltip:Hide()
        end)
        dot:SetScript("OnClick", function(_, button)
            local mover = Movers.SelectedMover
            if not mover or isDragging then return end
            ApplyAnchorPoint(mover, apName, button == "RightButton")
            remote:UpdateInfo()
        end)
        remote._anchorDots[apName] = dot
    end
    RefreshDots()

    -- 범례 (격자 아래)
    local legend = parent:CreateFontString(nil, "OVERLAY")
    legend:SetFont(SL.Font.path, SL.Font.small, "")
    legend:SetTextColor(C.text.dim[1], C.text.dim[2], C.text.dim[3], 1)
    legend:SetPoint("TOPLEFT", gridBox, "BOTTOMLEFT", 0, -4)
    legend:SetText((L["Anchor legend"] or "좌클릭 앵커점 · 우클릭 기준점"))

    -- 연결 대상 드롭다운 + 선택 버튼 (오른쪽)
    local rightX = PAD + GRID_W + 16 + 10
    local ddLabel = parent:CreateFontString(nil, "OVERLAY")
    ddLabel:SetFont(SL.Font.path, SL.Font.small, "")
    ddLabel:SetTextColor(C.text.dim[1], C.text.dim[2], C.text.dim[3], 1)
    ddLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", rightX, y - 2)
    ddLabel:SetText(L["Anchor Frame"] or "연결 대상")

    local ddY = y - 18
    local ddWidth = (remote:GetWidth() or 300) - rightX - PAD
    function remote:RefreshAnchorDropdown(anchorName)
        local mover = Movers.SelectedMover
        local items = mover and AnchorItems(mover) or { { text = "UIParent", value = "UIParent" } }
        if anchorName then
            local found = false
            for _, item in ipairs(items) do if item.value == anchorName then found = true end end
            if not found then items[#items + 1] = { text = FrameDisplayName(anchorName), value = anchorName } end
        end
        local parts = {}
        for _, item in ipairs(items) do parts[#parts + 1] = item.value end
        local signature = table.concat(parts, "|")
        if signature ~= self._anchorListSignature or not self.anchorDropdown then
            self._anchorListSignature = signature
            if self.anchorDropdown then self.anchorDropdown:Hide() end
            local dd = SL.CreateDropdown(parent, "CDM", "", items, anchorName or "UIParent", {
                width = ddWidth,
                onChange = function(value)
                    local selected = Movers.SelectedMover
                    if not selected or isDragging then return end
                    if ApplyAnchorFrame(selected, value) then remote:UpdateInfo() end
                end,
            })
            dd:SetPoint("TOPLEFT", parent, "TOPLEFT", rightX, ddY)
            self.anchorDropdown = dd
        elseif anchorName and self.anchorDropdown.SetValue then
            self.anchorDropdown:SetValue(anchorName)
        end
    end
    remote:RefreshAnchorDropdown(nil)

    local pickBtn = SL.CreateButton(parent, "CDM", L["Select Anchor"] or "화면에서 선택", function()
        local mover = Movers.SelectedMover
        if not mover then
            DDingUI:Print("|cffff6666" .. (L["Select a frame first"] or "Select a frame first") .. "|r")
            return
        end
        if not DDingUI.StartFramePicker then return end
        DDingUI:StartFramePicker(function(frameName)
            local selected = Movers.SelectedMover
            if not frameName or not selected then return end
            if ApplyAnchorFrame(selected, frameName) then remote:UpdateInfo() end
        end)
    end, { width = ddWidth, height = 24 })
    pickBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", rightX, ddY - 30)
    remote.anchorSelectBtn = pickBtn

    local bottom = y - (GRID_H + 16) - 18
    return top - bottom + 6
end

local function RemoteSavedPosition()
    local saved = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.moverSettings
    saved = saved and saved.editRemotePos
    if type(saved) == "table" and saved.point then
        return saved.point, tonumber(saved.x) or 0, tonumber(saved.y) or 0
    end
    return nil
end

function Movers:CreateEditRemote()
    if self.NudgeFrame then return self.NudgeFrame end
    local SL = GetSL()
    if not (SL and SL.CreateEditRemote) then return nil end

    local remote
    remote = SL.CreateEditRemote("CDM", {
        title = L["Edit Mode"] or "편집 모드",
        version = DDingUI.VERSION or "",
        frames = function() return MoverItems() end,
        onSelectFrame = function(value)
            if not value or value == "" then return end
            local holder = Movers.CreatedMovers[value]
            if holder and holder.mover then
                Movers.SelectedMover = holder.mover
                remote:UpdateSelection()
            end
        end,
        onNudge = function(dx, dy) Movers:NudgeMover(dx, dy) end,
        onApplyXY = function(x, y) Movers:ApplyMoverOffset(x, y) end,
        onReset = function()
            local mover = Movers.SelectedMover
            if not mover then return end
            Movers:PushUndo(mover.name, GetPoint(mover))
            Movers:ResetMoverPosition(mover.name)
        end,
        onUndo = function() Movers:Undo() end,
        onRedo = function() Movers:Redo() end,
        onDone = function() if Movers.ConfigMode then Movers:ToggleConfigMode() end end,
        grid = {
            enabled = self.Settings.gridEnabled,
            spacing = self:GetGridSpacing(),
            onToggle = function(on)
                if Movers._syncingRemoteGrid then return end
                if on then Movers:ShowGrid() else Movers:HideGrid() end
            end,
            onSpacing = function(n) Movers:SetGridSpacing(n) end,
        },
        snap = {
            enabled = self.Settings.snapEnabled,
            center = self.Settings.snapToCenter,
            grid = self.Settings.snapToGrid,
            frames = self.Settings.snapToFrames,
            onChange = function(key, on)
                local map = { enabled = "snapEnabled", center = "snapToCenter", grid = "snapToGrid", frames = "snapToFrames" }
                if map[key] then Movers.Settings[map[key]] = on and true or false end
            end,
        },
        -- extra는 CreateEditRemote 안에서 불리므로 remote 지역변수 대신 parent(=리모컨)를 쓴다
        extra = function(parent, y) return BuildRemoteExtra(parent, parent, y) end,
        loadPosition = RemoteSavedPosition,
        savePosition = function(point, x, y) Movers:SaveRemotePosition(point, x, y) end,
    })
    remote:Hide()

    function remote:UpdateUndoRedoButtons()
        self:SetUndoState(#Movers.UndoStack > 0, #Movers.RedoStack > 0)
    end

    function remote:UpdateSelection()
        local mover = Movers.SelectedMover
        local items = MoverItems()
        local parts = {}
        for _, item in ipairs(items) do parts[#parts + 1] = item.value end
        local signature = table.concat(parts, "|")
        if signature ~= self._moverListSignature and self.RefreshFrames then
            self._moverListSignature = signature
            self:RefreshFrames(mover and mover.name or "")
        elseif self.frameDropdown and self.frameDropdown.SetValue then
            self.frameDropdown:SetValue(mover and mover.name or "")
        end

        for _, holder in pairs(Movers.CreatedMovers) do
            if holder.mover and holder.mover.SetSelectionHUD then
                holder.mover:SetSelectionHUD(holder.mover == mover)
            end
        end
        self:UpdateInfo()
    end

    function remote:UpdateInfo()
        local mover = Movers.SelectedMover
        if not mover then
            self:SetSelection(nil)
            self._selfPointCurrent, self._anchorPointCurrent = nil, nil
            if self.RefreshAnchorGrid then self:RefreshAnchorGrid() end
            if self.RefreshAnchorDropdown then self:RefreshAnchorDropdown(nil) end
            return
        end
        if mover.UpdateSelectionHUD then mover:UpdateSelectionHUD() end
        local x, y, selfPt, anchorFrame, relPt = Movers:GetMoverOffset(mover)
        local anchorName = (anchorFrame and anchorFrame.GetName and anchorFrame:GetName()) or "UIParent"
        local width, height = mover:GetSize()
        self:SetSelection({
            name = mover.displayText or mover.name,
            anchor = selfPt .. " \226\134\146 " .. relPt .. " @ " .. FrameDisplayName(anchorName),
            x = x, y = y, w = width, h = height,
        })
        self._selfPointCurrent, self._anchorPointCurrent = selfPt, relPt
        if self.RefreshAnchorGrid then self:RefreshAnchorGrid() end
        if self.RefreshAnchorDropdown then self:RefreshAnchorDropdown(anchorName) end
    end

    self.NudgeFrame = remote
    return remote
end

function Movers:SaveRemotePosition(point, x, y)
    if not (DDingUI.db and DDingUI.db.profile) or not point then return end
    local settings = DDingUI.db.profile.moverSettings
    if not settings then
        settings = {}
        DDingUI.db.profile.moverSettings = settings
    end
    settings.editRemotePos = { point = point, x = x or 0, y = y or 0 }
end

-- 설정창 제목줄의 "편집 모드"/"편집 중" 버튼 갱신 (C12)
function Movers:RefreshEditModeButtons()
    local configFrame = _G["DDingUI_ConfigFrame"]
    local button = configFrame and configFrame.editButton
    if button and button.Refresh then button:Refresh() end
end

function Movers:ShowRemote()
    local remote = self:CreateEditRemote()
    if not remote then return end
    remote:UpdateUndoRedoButtons()
    SyncRemoteGrid(self.Settings.gridEnabled, self:GetGridSpacing())
    remote:UpdateSelection()
    if remote.ShowAnimated then remote:ShowAnimated() else remote:Show() end
end

function Movers:HideRemote()
    local remote = self.NudgeFrame
    if not remote then return end
    -- 축소 모션으로 닫는다(전투 중이면 BindPanel이 즉시 숨긴다)
    if remote.HideAnimated then remote:HideAnimated() else remote:Hide() end
end

--- 리모컨 X/Y 입력: 선택한 무버의 앵커 상대 오프셋을 그대로 적용한다.
function Movers:ApplyMoverOffset(x, y)
    local mover = self.SelectedMover
    if not mover or isDragging then return end
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end

    local oldPoint = GetPoint(mover)
    local selfPt, anchor, relPoint = mover:GetPoint(1)
    mover:ClearAllPoints()
    mover:SetPoint(selfPt or "CENTER", anchor or UIParent, relPoint or "CENTER", x, y)
    if GetPoint(mover) ~= oldPoint then
        self:PushUndo(mover.name, oldPoint)
    end
    self:SaveMoverPosition(mover.name)
    if not IsBuffTrackerMoverName(mover.name) then
        self:UpdateParentPosition(mover.name)
    end
    self:RefreshRemoteInfo()
end

function Movers:NudgeMover(dx, dy)
    local mover = self.SelectedMover
    if not mover or isDragging then return end

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
    if not IsBuffTrackerMoverName(mover.name) then
        self:UpdateParentPosition(mover.name)
    end

    self:RefreshRemoteInfo()
end

--------------------------------------------------------------------------------
-- Settings Persistence
--------------------------------------------------------------------------------

-- 기존 키만 갱신한다(테이블을 새로 만들지 않아 editRemotePos 같은 다른 키가 지워지지 않는다).
-- gridEnabled는 종료 시점의 실제 값이다. snapThreshold는 읽은 값을 그대로 돌려 쓴다.
function Movers:SaveSettings()
    if not DDingUI.db then return end
    local settings = DDingUI.db.profile.moverSettings
    if not settings then
        settings = {}
        DDingUI.db.profile.moverSettings = settings
    end
    settings.gridEnabled = self.Settings.gridEnabled and true or false
    settings.snapEnabled = self.Settings.snapEnabled
    settings.snapToGrid = self.Settings.snapToGrid
    settings.snapToFrames = self.Settings.snapToFrames
    settings.snapToCenter = self.Settings.snapToCenter
    settings.snapThreshold = self.Settings.snapThreshold
    settings.gridSize = self.Settings.gridSize
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
    profile.profileVersion = DDingUI.VERSION or "2.2.1"

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
        DDingUI:Print("|cff00ff00" .. migratedCount .. "개 프레임이 프록시 앵커로 전환되었습니다.|r")
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

    self:CreateEditRemote()

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
            DDingUI:Print("|cff00ff00" .. (L["Buff Tracker frames refreshed"] or "Buff Tracker frames refreshed") .. "|r") -- [STYLE]
        else
            DDingUI:Print("|cffff6666" .. (L["Enter mover mode first (/ddmove)"] or "Enter mover mode first (/ddmove)") .. "|r") -- [STYLE]
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

    DDingUI:Print("|cff00ff00로드 완료. |cffffa300/dcm|r|cff00ff00 으로 설정을 열 수 있습니다.|r") -- [STYLE]
end

local function SeedBuffBarViewerMoverConfig(viewer)
    if not viewer or not DDingUI.db or not DDingUI.db.profile then return end

    local cfg = DDingUI.db.profile.buffBarViewer
    if not cfg or cfg._moverSaved or cfg.attachTo then return end

    local vx, vy = viewer:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not vx or not ux then return end

    cfg.attachTo = "UIParent"
    cfg.anchorPoint = "CENTER"
    cfg.selfPoint = "CENTER"
    cfg.offsetX = vx - ux
    cfg.offsetY = vy - uy
    cfg._moverSaved = true
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
        {
            getFrame = function()
                return DDingUI.GetBuffBarMoverFrame and DDingUI:GetBuffBarMoverFrame()
            end,
            key = "DDingUI_BuffBarViewer",
            display = L["Buff Bar"] or "Tracked Bars",
            beforeRegister = SeedBuffBarViewerMoverConfig,
        },
    }

    if self.CreatedMovers["DDingUI_BuffTrackerBar"] then
        self:UnregisterMover("DDingUI_BuffTrackerBar")
    end

    for _, info in ipairs(standardFrames) do
        local frame = info.getFrame and info.getFrame()
            or (info.global and _G[info.global])
            or (info.ref and DDingUI[info.ref])
        if frame then
            if info.beforeRegister then
                info.beforeRegister(frame)
            end
            self:RegisterMover(frame, info.key, info.display)
            if info.key == "DDingUI_BuffBarViewer" and DDingUI.RefreshBuffBarCooldownViewer then
                pcall(DDingUI.RefreshBuffBarCooldownViewer, DDingUI)
            end
        end
    end

    -- Icon cooldown viewers stay excluded to avoid Blizzard CDM taint.
    -- BuffBarCooldownViewer is registered above as a DDingUI mapped module.

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
    local trackedBuffs = DDingUI.GetTrackedBuffConfigs and DDingUI:GetTrackedBuffConfigs() or {}
    local groupedChildren = {}
    for _, trackedBuff in ipairs(trackedBuffs) do
        if trackedBuff.isGroup then
            for _, childIndex in ipairs(trackedBuff.controlledChildren or {}) do
                groupedChildren[childIndex] = true
            end
        end
    end

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
        if not groupedChildren[idx] then
            local key = "DDingUI_BuffTrackerBar_" .. idx
            local displayName = (L["Buff Tracker Bar"] or "Buff Tracker Bar") .. " #" .. idx
            RegisterOrUpdateMover(bar, key, displayName)
        end
    end

    -- 아이콘 프레임 등록
    local iconFrames = DDingUI.GetTrackedBuffIcons and DDingUI:GetTrackedBuffIcons() or {}
    for idx, icon in pairs(iconFrames) do
        if not groupedChildren[idx] then
            local key = "DDingUI_BuffTrackerIcon_" .. idx
            local displayName = (L["Buff Tracker Icon"] or "Buff Tracker Icon") .. " #" .. idx
            RegisterOrUpdateMover(icon, key, displayName)
        end
    end

    -- 텍스트 프레임 등록
    local textFrames = DDingUI.GetTrackedBuffTexts and DDingUI:GetTrackedBuffTexts() or {}
    for idx, textFrame in pairs(textFrames) do
        if not groupedChildren[idx] then
            local key = "DDingUI_BuffTrackerText_" .. idx
            local displayName = (L["Buff Tracker Text"] or "Buff Tracker Text") .. " #" .. idx
            RegisterOrUpdateMover(textFrame, key, displayName)
        end
    end

    local groupFrames = DDingUI.GetTrackedBuffGroups and DDingUI:GetTrackedBuffGroups() or {}
    for idx, groupFrame in pairs(groupFrames) do
        local group = trackedBuffs[idx]
        if group and group.isGroup then
            local key = "DDingUI_BuffTrackerGroup_" .. idx
            local displayName = group.name or ("Group #" .. idx)
            RegisterOrUpdateMover(groupFrame, key, displayName)
        end
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
moverInitFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
moverInitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
moverInitFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function()
            Movers:Initialize()
        end)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_REGEN_DISABLED" then
        Movers:ExitEditMode(true)
    elseif event == "PLAYER_REGEN_ENABLED" and Movers._restoreViewerMouseAfterCombat then
        Movers:RestoreEditModeViewerMouse()
    end
end)
