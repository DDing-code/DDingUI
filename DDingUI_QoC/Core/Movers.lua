--[[
    DDingQoC - Movers (편집 모드)
    DDingUI Core/Movers.lua 기반 QoC 이식 (앵커 기능 제외)
]]

local addonName, ns = ...
local DDingQoC = ns.DDingQoC
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: "

--------------------------------------------------------------------------------
-- Movers Namespace
--------------------------------------------------------------------------------
local Movers = {}
ns.QoCMovers = Movers

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
    snapToCenter = true,
    snapToFrames = true,
    snapThreshold = 10,
    gridSize = 32,
}

-- Undo/Redo
Movers.UndoStack = {}
Movers.RedoStack = {}
Movers.MAX_UNDO = 50

-- Dragging state
local isDragging = false
local dragFrame = nil
local dragOffsetX, dragOffsetY = 0, 0

--------------------------------------------------------------------------------
-- Mover Registry — 이동 가능한 프레임 목록
--------------------------------------------------------------------------------
local MoverRegistry = {
    { name = "CombatTimer",       frameName = "DDingQoC_CombatTimerFrame",      posKey = "CombatTimer.position",      displayText = nil, module = "CombatTimer",    defaultSize = {120, 40} },
    { name = "BuffChecker",       frameName = "DDingQoCBuffCheckerFrame",       posKey = "BuffChecker.position",      displayText = nil, module = "BuffChecker",    defaultSize = {200, 50} },
    { name = "CastingAlert",      frameName = "DDingQoC_CastingAlertFrame",    posKey = "CastingAlert.position",     displayText = nil, module = "CastingAlert",   defaultSize = {140, 120} },
    { name = "FocusInterrupt",    frameName = "DDingQoC_FocusInterruptFrame",  posKey = "FocusInterrupt.position",   displayText = nil, module = "FocusInterrupt", defaultSize = {280, 30} },
    { name = "PartyTracker",      frameName = "DDingQoC_PartyTrackerFrame",    posKey = "PartyTracker.position",     displayText = nil, module = "PartyTracker",   defaultSize = {150, 200} },
    { name = "PartyTracker_Mana", frameName = "DDingQoC_PartyTrackerManaFrame", posKey = "PartyTracker.manaPosition", displayText = nil, module = "PartyTracker",   defaultSize = {150, 150} },
}

-- displayText lazy init (L이 로드된 후)
local function EnsureDisplayTexts()
    for _, reg in ipairs(MoverRegistry) do
        if not reg.displayText then
            if reg.name == "CombatTimer" then reg.displayText = L["TAB_COMBATTIMER"] or "전투 타이머"
            elseif reg.name == "BuffChecker" then reg.displayText = L["TAB_BUFFCHECKER"] or "버프 체커"
            elseif reg.name == "CastingAlert" then reg.displayText = L["TAB_CASTINGALERT"] or "타겟 스펠"
            elseif reg.name == "FocusInterrupt" then reg.displayText = L["TAB_FOCUSINTERRUPT"] or "주시 차단"
            elseif reg.name == "PartyTracker" then reg.displayText = L["TAB_PARTYTRACKER"] or "파티 트래커"
            elseif reg.name == "PartyTracker_Mana" then reg.displayText = L["MOVER_PT_MANA"] or "파티 트래커 (힐러 마나)"
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------
local function Round(num) return math.floor(num + 0.5) end

local function GetPoint(obj)
    local point, anchor, secondaryPoint, x, y = obj:GetPoint()
    if not anchor then anchor = UIParent end
    return string.format("%s,%s,%s,%d,%d",
        point or "CENTER",
        anchor:GetName() or "UIParent",
        secondaryPoint or point or "CENTER",
        Round(x or 0), Round(y or 0))
end

local function SetPoint(obj, pointString)
    if not pointString then return end
    local point, anchorName, relativePoint, x, y = strsplit(",", pointString)
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    local anchor = _G[anchorName] or UIParent
    obj:ClearAllPoints()
    obj:SetPoint(point, anchor, relativePoint, x, y)
end

-- position DB key 경로에서 테이블 접근
local function ResolvePositionTable(posKey)
    if not ns.db or not ns.db.profile then return nil end
    local parts = { strsplit(".", posKey) }
    local tbl = ns.db.profile
    for i = 1, #parts - 1 do
        tbl = tbl[parts[i]]
        if not tbl then return nil end
    end
    local key = parts[#parts]
    if not tbl[key] then
        tbl[key] = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    end
    return tbl[key]
end

--------------------------------------------------------------------------------
-- Undo / Redo
--------------------------------------------------------------------------------
function Movers:PushUndo(moverName, oldPoint)
    if not moverName or not oldPoint then return end
    wipe(self.RedoStack)
    table.insert(self.UndoStack, { name = moverName, point = oldPoint })
    while #self.UndoStack > self.MAX_UNDO do table.remove(self.UndoStack, 1) end
    if self.NudgeFrame then self.NudgeFrame:UpdateUndoRedoButtons() end
end

function Movers:Undo()
    if #self.UndoStack == 0 then return end
    local entry = table.remove(self.UndoStack)
    local holder = self.CreatedMovers[entry.name]
    if not holder then return end
    table.insert(self.RedoStack, { name = entry.name, point = GetPoint(holder.mover) })
    SetPoint(holder.mover, entry.point)
    self:SyncMoverToPosition(entry.name)
    if self.NudgeFrame then self.NudgeFrame:UpdateUndoRedoButtons(); self.NudgeFrame:UpdateInfo() end
end

function Movers:Redo()
    if #self.RedoStack == 0 then return end
    local entry = table.remove(self.RedoStack)
    local holder = self.CreatedMovers[entry.name]
    if not holder then return end
    table.insert(self.UndoStack, { name = entry.name, point = GetPoint(holder.mover) })
    SetPoint(holder.mover, entry.point)
    self:SyncMoverToPosition(entry.name)
    if self.NudgeFrame then self.NudgeFrame:UpdateUndoRedoButtons(); self.NudgeFrame:UpdateInfo() end
end

function Movers:ClearUndoRedo()
    wipe(self.UndoStack); wipe(self.RedoStack)
    if self.NudgeFrame then self.NudgeFrame:UpdateUndoRedoButtons() end
end

--------------------------------------------------------------------------------
-- Snap
--------------------------------------------------------------------------------
local function GetSnapTargets(excludeMover)
    local targets = {}
    if not Movers.Settings.snapToFrames then return targets end
    for name, holder in pairs(Movers.CreatedMovers) do
        if holder.mover and holder.mover ~= excludeMover and holder.mover:IsShown() then
            local left, bottom, width, height = holder.mover:GetRect()
            if left and bottom then
                targets[#targets+1] = { left=left, right=left+width, top=bottom+height, bottom=bottom, centerX=left+width/2, centerY=bottom+height/2 }
            end
        end
    end
    return targets
end

local function CalculateSnap(x, y, width, height, excludeMover)
    local s = Movers.Settings
    if not s.snapEnabled then return x, y end
    local threshold = s.snapThreshold
    local snapX, snapY = x, y
    local snappedH, snappedV = false, false

    -- 화면 중앙
    if s.snapToCenter then
        local cx, cy = UIParent:GetCenter()
        if math.abs(x - cx) < threshold then snapX = cx; snappedH = true end
        if math.abs(y - cy) < threshold then snapY = cy; snappedV = true end
    end

    -- 그리드
    if s.snapToGrid then
        local gs = s.gridSize > 0 and s.gridSize or 32
        local gx = Round(x / gs) * gs
        local gy = Round(y / gs) * gs
        if not snappedH and math.abs(x - gx) < threshold then snapX = gx end
        if not snappedV and math.abs(y - gy) < threshold then snapY = gy end
    end

    -- 다른 프레임 엣지 정렬
    if s.snapToFrames then
        local fl, fr, ft, fb = x-width/2, x+width/2, y+height/2, y-height/2
        for _, t in ipairs(GetSnapTargets(excludeMover)) do
            if math.abs(fl - t.right) < threshold then snapX = t.right + width/2 end
            if math.abs(fr - t.left) < threshold then snapX = t.left - width/2 end
            if math.abs(fl - t.left) < threshold then snapX = t.left + width/2 end
            if math.abs(fr - t.right) < threshold then snapX = t.right - width/2 end
            if math.abs(ft - t.bottom) < threshold then snapY = t.bottom - height/2 end
            if math.abs(fb - t.top) < threshold then snapY = t.top + height/2 end
            if math.abs(ft - t.top) < threshold then snapY = t.top - height/2 end
            if math.abs(fb - t.bottom) < threshold then snapY = t.bottom + height/2 end
            if math.abs(x - t.centerX) < threshold then snapX = t.centerX end
            if math.abs(y - t.centerY) < threshold then snapY = t.centerY end
        end
    end

    return snapX, snapY
end

--------------------------------------------------------------------------------
-- Drag Handlers (OnUpdate 방식)
--------------------------------------------------------------------------------
local updateFrame = CreateFrame("Frame")

local function OnUpdateDrag(self, elapsed)
    if not isDragging or not dragFrame then return end
    local scale = dragFrame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx = cx / scale; cy = cy / scale
    local targetX = cx + dragOffsetX
    local targetY = cy + dragOffsetY
    local w, h = dragFrame:GetSize()
    local sx, sy = CalculateSnap(targetX, targetY, w, h, dragFrame)
    dragFrame:ClearAllPoints()
    dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
    -- 실제 프레임도 실시간 동기화
    if dragFrame.name then Movers:SyncFrameToMover(dragFrame.name) end
    if Movers.NudgeFrame and Movers.NudgeFrame:IsShown() then Movers.NudgeFrame:UpdateInfo() end
end

local function OnDragStart(mover)
    if InCombatLockdown() then return end
    if not Movers.Settings.gridEnabled then Movers:ShowGrid(); mover._tempGrid = true end
    mover._dragStartPoint = GetPoint(mover)
    local scale = mover:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx = mx / scale; my = my / scale
    local fx, fy = mover:GetCenter()
    if not fx then return end
    dragOffsetX = fx - mx; dragOffsetY = fy - my
    dragFrame = mover; isDragging = true
    updateFrame:SetScript("OnUpdate", OnUpdateDrag)
    Movers.SelectedMover = mover
    if Movers.NudgeFrame then Movers.NudgeFrame:UpdateSelection() end
end

local function OnDragStop(mover)
    if InCombatLockdown() then return end
    if not isDragging then return end
    isDragging = false; dragFrame = nil
    updateFrame:SetScript("OnUpdate", nil)
    if mover._tempGrid then Movers:HideGrid(); mover._tempGrid = nil end
    -- UIParent CENTER 기반으로 재계산
    local cx, cy = mover:GetCenter()
    local uiCX, uiCY = UIParent:GetCenter()
    local x = Round((cx or 0) - (uiCX or 0))
    local y = Round((cy or 0) - (uiCY or 0))
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", x, y)
    -- Undo
    if mover._dragStartPoint then
        local newPoint = GetPoint(mover)
        if mover._dragStartPoint ~= newPoint then
            Movers:PushUndo(mover.name, mover._dragStartPoint)
        end
        mover._dragStartPoint = nil
    end
    Movers:SyncMoverToPosition(mover.name)
    if Movers.NudgeFrame then Movers.NudgeFrame:UpdateInfo() end
end

--------------------------------------------------------------------------------
-- Mover Overlay 생성
--------------------------------------------------------------------------------
local ACCENT = {1, 0.64, 0}  -- #ffa300
local SELECTED_COLOR = {0, 1, 0}

local function CreateMoverOverlay(reg, parent, isPhantom)
    local name = reg.name
    local mover = CreateFrame("Frame", "DDingQoC_Mover_" .. name, UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(100)
    mover:SetClampedToScreen(true)
    mover.name = name
    mover.regData = reg
    mover.displayText = reg.displayText or name
    mover.isPhantom = isPhantom

    -- 크기: 부모 프레임 또는 기본값
    if parent and not isPhantom then
        local pw, ph = parent:GetSize()
        mover:SetSize(math.max(pw, 30), math.max(ph, 20))
    else
        mover:SetSize(reg.defaultSize[1] or 120, reg.defaultSize[2] or 40)
    end

    -- 위치: 부모 프레임 또는 position DB
    if parent and not isPhantom then
        local ok, pt, anchor, relPt, px, py = pcall(parent.GetPoint, parent, 1)
        if ok and pt then
            mover:SetPoint(pt, anchor or UIParent, relPt or pt, px or 0, py or 0)
        else
            mover:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    else
        local pos = ResolvePositionTable(reg.posKey)
        if pos then
            mover:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0)
        else
            mover:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end

    -- 배경
    mover:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1.5 })
    mover:SetBackdropColor(0, 0, 0, isPhantom and 0.3 or 0.4)
    mover:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)

    -- 라벨
    mover.label = mover:CreateFontString(nil, "OVERLAY")
    mover.label:SetFont(SL_FONT, 11, "OUTLINE")
    mover.label:SetPoint("CENTER")
    mover.label:SetText(mover.displayText)
    mover.label:SetTextColor(1, 1, 1, 0.9)

    -- 팬텀 표시
    if isPhantom then
        mover.phantomTag = mover:CreateFontString(nil, "OVERLAY")
        mover.phantomTag:SetFont(SL_FONT, 9, "OUTLINE")
        mover.phantomTag:SetPoint("BOTTOM", mover, "BOTTOM", 0, 3)
        mover.phantomTag:SetText(L["MOVER_PHANTOM"] or "(비활성)")
        mover.phantomTag:SetTextColor(0.6, 0.6, 0.6, 0.7)
    end

    -- 선택 하이라이트 함수
    function mover.UpdateBorderColor(r, g, b, a)
        mover:SetBackdropBorderColor(r, g, b, a or 1)
    end

    -- 드래그
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function() OnDragStart(mover) end)
    mover:SetScript("OnDragStop", function() OnDragStop(mover) end)
    mover:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            Movers.SelectedMover = mover
            if Movers.NudgeFrame then Movers.NudgeFrame:UpdateSelection() end
        end
    end)

    return mover
end

--------------------------------------------------------------------------------
-- Position Sync (Mover → DB)
--------------------------------------------------------------------------------
function Movers:SyncMoverToPosition(name)
    local holder = self.CreatedMovers[name]
    if not holder or not holder.mover then return end
    local reg = holder.reg
    local pos = ResolvePositionTable(reg.posKey)
    if not pos then return end
    local _, _, relPt, x, y = holder.mover:GetPoint()
    pos.point = "CENTER"
    pos.relativePoint = "CENTER"
    pos.x = Round(x or 0)
    pos.y = Round(y or 0)
    -- 실제 프레임도 동기화
    self:SyncFrameToMover(name)
end

--- 실제 모듈 프레임을 무버 위치에 동기화
function Movers:SyncFrameToMover(name)
    local holder = self.CreatedMovers[name]
    if not holder or not holder.mover then return end
    local parent = holder.parent or _G[holder.reg.frameName]
    if not parent or holder.isPhantom then return end
    local cx, cy = holder.mover:GetCenter()
    local uiCX, uiCY = UIParent:GetCenter()
    if not cx or not uiCX then return end
    local x = Round(cx - uiCX)
    local y = Round(cy - uiCY)
    parent:ClearAllPoints()
    parent:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function Movers:ResetMoverPosition(name)
    local holder = self.CreatedMovers[name]
    if not holder or not holder.mover then return end
    local reg = holder.reg
    local pos = ResolvePositionTable(reg.posKey)
    if pos then pos.point = "CENTER"; pos.relativePoint = "CENTER"; pos.x = 0; pos.y = 0 end
    holder.mover:ClearAllPoints()
    holder.mover:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self:SyncFrameToMover(name)
    if self.NudgeFrame then self.NudgeFrame:UpdateInfo() end
end

--------------------------------------------------------------------------------
-- Grid
--------------------------------------------------------------------------------
function Movers:CreateGrid()
    if self.Grid then self.Grid:Hide() end
    local grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid:SetFrameLevel(0)
    grid.lines = {}
    local size = self.Settings.gridSize
    if size <= 0 then size = 32 end
    local w, h = UIParent:GetSize()
    local cx, cy = w / 2, h / 2
    -- 수직선
    for x = 0, w, size do
        local line = grid:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(1, 1, 1, (math.abs(x - cx) < 1) and 0.4 or 0.08)
        line:SetSize(1, h)
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
        grid.lines[#grid.lines+1] = line
    end
    -- 수평선
    for y = 0, h, size do
        local line = grid:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(1, 1, 1, (math.abs(y - cy) < 1) and 0.4 or 0.08)
        line:SetSize(w, 1)
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
        grid.lines[#grid.lines+1] = line
    end
    grid:Hide()
    self.Grid = grid
end

function Movers:ShowGrid()
    if not self.Grid then self:CreateGrid() end
    self.Grid:Show()
end

function Movers:HideGrid()
    if self.Grid then self.Grid:Hide() end
end

--------------------------------------------------------------------------------
-- NudgeFrame (하단 컨트롤 패널)
--------------------------------------------------------------------------------
function Movers:CreateNudgeFrame()
    if self.NudgeFrame then return end
    EnsureDisplayTexts()

    local nudge = CreateFrame("Frame", "DDingQoC_NudgeFrame", UIParent, "BackdropTemplate")
    nudge:SetSize(300, 240)
    nudge:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 30)
    nudge:SetFrameStrata("FULLSCREEN_DIALOG")
    nudge:SetFrameLevel(200)
    nudge:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1 })
    nudge:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
    nudge:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.7)
    nudge:SetMovable(true)
    nudge:EnableMouse(true)
    nudge:RegisterForDrag("LeftButton")
    nudge:SetScript("OnDragStart", function(self) self:StartMoving() end)
    nudge:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    nudge:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "DDingQoC_NudgeFrame")

    -- ═══ 상단: 제목 + 선택 프레임 ═══
    local title = nudge:CreateFontString(nil, "OVERLAY")
    title:SetFont(SL_FONT, 13, "OUTLINE")
    title:SetPoint("TOP", nudge, "TOP", 0, -10)
    title:SetText("|cffffa300QoC|r " .. (L["MOVER_TITLE"] or "편집 모드"))
    title:SetTextColor(1, 1, 1, 0.9)

    nudge.selectedText = nudge:CreateFontString(nil, "OVERLAY")
    nudge.selectedText:SetFont(SL_FONT, 11, "OUTLINE")
    nudge.selectedText:SetPoint("TOP", title, "BOTTOM", 0, -4)
    nudge.selectedText:SetText(L["MOVER_NO_SELECTION"] or "선택 없음")
    nudge.selectedText:SetTextColor(0.8, 0.8, 0.8, 1)

    -- ═══ 구분선 ═══
    local sep1 = nudge:CreateTexture(nil, "ARTWORK")
    sep1:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    sep1:SetSize(260, 1)
    sep1:SetPoint("TOP", nudge, "TOP", 0, -46)

    -- ═══ 중단 좌측: 좌표 + D-pad ═══
    local xLabel = nudge:CreateFontString(nil, "OVERLAY")
    xLabel:SetFont(SL_FONT, 10, "OUTLINE")
    xLabel:SetPoint("TOPLEFT", nudge, "TOPLEFT", 20, -56)
    xLabel:SetText("X:")
    xLabel:SetTextColor(0.6, 0.6, 0.6)

    nudge.xText = nudge:CreateFontString(nil, "OVERLAY")
    nudge.xText:SetFont(SL_FONT, 11, "OUTLINE")
    nudge.xText:SetPoint("LEFT", xLabel, "RIGHT", 4, 0)
    nudge.xText:SetText("0")
    nudge.xText:SetTextColor(1, 1, 1)

    local yLabel = nudge:CreateFontString(nil, "OVERLAY")
    yLabel:SetFont(SL_FONT, 10, "OUTLINE")
    yLabel:SetPoint("LEFT", nudge.xText, "RIGHT", 16, 0)
    yLabel:SetText("Y:")
    yLabel:SetTextColor(0.6, 0.6, 0.6)

    nudge.yText = nudge:CreateFontString(nil, "OVERLAY")
    nudge.yText:SetFont(SL_FONT, 11, "OUTLINE")
    nudge.yText:SetPoint("LEFT", yLabel, "RIGHT", 4, 0)
    nudge.yText:SetText("0")
    nudge.yText:SetTextColor(1, 1, 1)

    -- D-pad 방향키 (좌측 영역, 중앙 정렬)
    local nudgeStep = 1
    local dpadCenterX = -55  -- 프레임 중앙에서 좌측으로 55px
    local dpadCenterY = -125  -- TOP에서 125px 아래
    local dpadSpacing = 30    -- 버튼 중심 간 거리

    local function NudgeMover(dx, dy)
        local m = Movers.SelectedMover
        if not m then return end
        local oldPt = GetPoint(m)
        local _, _, _, ox, oy = m:GetPoint()
        m:ClearAllPoints()
        m:SetPoint("CENTER", UIParent, "CENTER", (ox or 0) + dx, (oy or 0) + dy)
        Movers:PushUndo(m.name, oldPt)
        Movers:SyncMoverToPosition(m.name)
        if Movers.NudgeFrame then Movers.NudgeFrame:UpdateInfo() end
    end

    local function CreateArrowBtn(label, xOff, yOff, dx, dy)
        local btn = CreateFrame("Button", nil, nudge, "BackdropTemplate")
        btn:SetSize(26, 26)
        btn:SetPoint("CENTER", nudge, "TOP", dpadCenterX + xOff, dpadCenterY + yOff)
        btn:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1 })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
        local t = btn:CreateFontString(nil, "OVERLAY")
        t:SetFont(SL_FONT, 13, "OUTLINE"); t:SetPoint("CENTER"); t:SetText(label)
        btn:SetScript("OnClick", function() NudgeMover(dx * nudgeStep, dy * nudgeStep) end)
        btn:SetScript("OnEnter", function() btn:SetBackdropColor(0.25, 0.25, 0.25, 0.9) end)
        btn:SetScript("OnLeave", function() btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8) end)
        return btn
    end

    CreateArrowBtn("▲",  0,  dpadSpacing,  0,  1)   -- 위
    CreateArrowBtn("▼",  0, -dpadSpacing,  0, -1)   -- 아래
    CreateArrowBtn("◀", -dpadSpacing,  0, -1,  0)   -- 왼쪽
    CreateArrowBtn("▶",  dpadSpacing,  0,  1,  0)   -- 오른쪽

    -- ═══ 중단 우측: 체크박스 ═══
    local function CreateCheckbox(label, x, y, getter, setter)
        local cb = CreateFrame("CheckButton", nil, nudge, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", nudge, "TOPLEFT", x, y)
        cb:SetChecked(getter())
        cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
        local text = cb:CreateFontString(nil, "OVERLAY")
        text:SetFont(SL_FONT, 10, "OUTLINE")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        text:SetText(label)
        text:SetTextColor(0.8, 0.8, 0.8)
        return cb
    end

    nudge.gridCheckbox = CreateCheckbox(L["MOVER_GRID"] or "그리드", 175, -98,
        function() return Movers.Settings.gridEnabled end,
        function(v)
            Movers.Settings.gridEnabled = v
            if v then Movers:ShowGrid() else Movers:HideGrid() end
        end)

    nudge.snapCheckbox = CreateCheckbox(L["MOVER_SNAP"] or "스냅", 175, -126,
        function() return Movers.Settings.snapEnabled end,
        function(v) Movers.Settings.snapEnabled = v end)

    -- ═══ 구분선 ═══
    local sep2 = nudge:CreateTexture(nil, "ARTWORK")
    sep2:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    sep2:SetSize(260, 1)
    sep2:SetPoint("BOTTOM", nudge, "BOTTOM", 0, 44)

    -- ═══ 하단: 액션 버튼 ═══
    local btnWidth = 62
    local btnSpacing = 6
    local totalW = btnWidth * 4 + btnSpacing * 3
    local startX = -totalW / 2

    local function CreateBottomBtn(label, xOff, r, g, b, onClick)
        local btn = CreateFrame("Button", nil, nudge, "BackdropTemplate")
        btn:SetSize(btnWidth, 24)
        btn:SetPoint("BOTTOM", nudge, "BOTTOM", xOff, 12)
        btn:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1 })
        btn:SetBackdropColor(r, g, b, 0.8)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
        local t = btn:CreateFontString(nil, "OVERLAY")
        t:SetFont(SL_FONT, 10, "OUTLINE"); t:SetPoint("CENTER"); t:SetText(label)
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function() btn:SetBackdropColor(math.min(r+0.12,1), math.min(g+0.12,1), math.min(b+0.12,1), 0.95) end)
        btn:SetScript("OnLeave", function() btn:SetBackdropColor(r, g, b, 0.8) end)
        return btn
    end

    nudge.resetBtn = CreateBottomBtn(L["MOVER_RESET"] or "초기화", startX + btnWidth/2, 0.3, 0.12, 0.12, function()
        if Movers.SelectedMover then
            local old = GetPoint(Movers.SelectedMover)
            Movers:PushUndo(Movers.SelectedMover.name, old)
            Movers:ResetMoverPosition(Movers.SelectedMover.name)
        end
    end)

    nudge.undoBtn = CreateBottomBtn(L["MOVER_UNDO"] or "실행취소", startX + btnWidth + btnSpacing + btnWidth/2, 0.15, 0.15, 0.15, function() Movers:Undo() end)
    nudge.undoBtn._bgR, nudge.undoBtn._bgG, nudge.undoBtn._bgB = 0.15, 0.15, 0.15
    nudge.undoBtn:Disable()

    nudge.redoBtn = CreateBottomBtn(L["MOVER_REDO"] or "재실행", startX + (btnWidth + btnSpacing) * 2 + btnWidth/2, 0.15, 0.15, 0.15, function() Movers:Redo() end)
    nudge.redoBtn._bgR, nudge.redoBtn._bgG, nudge.redoBtn._bgB = 0.15, 0.15, 0.15
    nudge.redoBtn:Disable()

    nudge.doneBtn = CreateBottomBtn(L["MOVER_DONE"] or "완료", startX + (btnWidth + btnSpacing) * 3 + btnWidth/2, 0.12, 0.30, 0.15, function() Movers:ToggleConfigMode() end)

    -- Update helpers
    function nudge:UpdateUndoRedoButtons()
        if self.undoBtn then
            if #Movers.UndoStack > 0 then self.undoBtn:Enable(); self.undoBtn:SetBackdropColor(self.undoBtn._bgR, self.undoBtn._bgG, self.undoBtn._bgB, 0.8)
            else self.undoBtn:Disable(); self.undoBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.4) end
        end
        if self.redoBtn then
            if #Movers.RedoStack > 0 then self.redoBtn:Enable(); self.redoBtn:SetBackdropColor(self.redoBtn._bgR, self.redoBtn._bgG, self.redoBtn._bgB, 0.8)
            else self.redoBtn:Disable(); self.redoBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.4) end
        end
    end

    function nudge:UpdateSelection()
        local m = Movers.SelectedMover
        if m then
            self.selectedText:SetText(m.displayText or m.name)
            m.UpdateBorderColor(SELECTED_COLOR[1], SELECTED_COLOR[2], SELECTED_COLOR[3], 1)
            for _, holder in pairs(Movers.CreatedMovers) do
                if holder.mover ~= m and holder.mover.UpdateBorderColor then
                    holder.mover.UpdateBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
                end
            end
            self:UpdateInfo()
        else
            self.selectedText:SetText(L["MOVER_NO_SELECTION"] or "선택 없음")
            self.xText:SetText("-"); self.yText:SetText("-")
        end
    end

    function nudge:UpdateInfo()
        local m = Movers.SelectedMover
        if not m then return end
        local _, _, _, x, y = m:GetPoint()
        self.xText:SetText(tostring(Round(x or 0)))
        self.yText:SetText(tostring(Round(y or 0)))
    end

    nudge:Hide()
    self.NudgeFrame = nudge
end

--------------------------------------------------------------------------------
-- Config Mode Toggle
--------------------------------------------------------------------------------
function Movers:ToggleConfigMode()
    if InCombatLockdown() then
        print(CHAT_PREFIX .. "|cffff6666" .. (L["MOVER_COMBAT"] or "전투 중에는 편집 모드를 사용할 수 없습니다.") .. "|r")
        return
    end
    self.ConfigMode = not self.ConfigMode
    if self.ConfigMode then self:ShowMovers() else self:HideMovers() end
end

function Movers:ShowMovers()
    self.ConfigMode = true
    EnsureDisplayTexts()

    -- NudgeFrame 생성
    if not self.NudgeFrame then self:CreateNudgeFrame() end

    -- 각 레지스트리 항목에 대해 Mover 오버레이 생성
    for _, reg in ipairs(MoverRegistry) do
        if not self.CreatedMovers[reg.name] then
            local parent = _G[reg.frameName]
            local isPhantom = (parent == nil)
            local mover = CreateMoverOverlay(reg, parent, isPhantom)
            self.CreatedMovers[reg.name] = { mover = mover, parent = parent, reg = reg, isPhantom = isPhantom }
        else
            -- 기존 mover 재표시
            local holder = self.CreatedMovers[reg.name]
            local parent = _G[reg.frameName]
            -- 부모가 새로 생겼으면 팬텀→실제로 전환
            if holder.isPhantom and parent then
                holder.isPhantom = false
                holder.parent = parent
                holder.mover.isPhantom = false
                if holder.mover.phantomTag then holder.mover.phantomTag:Hide() end
                local pw, ph = parent:GetSize()
                holder.mover:SetSize(math.max(pw, 30), math.max(ph, 20))
            end
            -- 부모 위치 동기화
            if parent and not holder.isPhantom then
                local ok, pt, anchor, relPt, px, py = pcall(parent.GetPoint, parent, 1)
                if ok and pt then
                    holder.mover:ClearAllPoints()
                    holder.mover:SetPoint(pt, anchor or UIParent, relPt or pt, px or 0, py or 0)
                end
                local okSize, pw, ph = pcall(function() return parent:GetWidth(), parent:GetHeight() end)
                if okSize and pw and pw > 0 and ph and ph > 0 then
                    holder.mover:SetSize(pw, math.max(ph, 1))
                end
            end
        end
        local holder = self.CreatedMovers[reg.name]
        holder.mover._startPoint = GetPoint(holder.mover)
        holder.mover:Show()
    end

    -- 모듈 테스트 모드 진입 (EnterEditPreview)
    local notifiedModules = {}
    for _, reg in ipairs(MoverRegistry) do
        if not notifiedModules[reg.module] then
            notifiedModules[reg.module] = true
            local mod = ns.modules and ns.modules[reg.module]
            if mod and mod.EnterEditPreview then
                mod:EnterEditPreview()
            end
        end
    end

    -- 그리드
    if self.Settings.gridEnabled then self:ShowGrid() end

    -- NudgeFrame 표시
    self.NudgeFrame:Show()

    print(CHAT_PREFIX .. "|cff00ff00" .. (L["MOVER_ENABLED"] or "편집 모드 활성화. 프레임을 드래그하여 위치를 조정하세요.") .. "|r")
end

function Movers:HideMovers()
    self.ConfigMode = false

    -- 모듈 테스트 모드 종료 (ExitEditPreview)
    local notifiedModules = {}
    for _, reg in ipairs(MoverRegistry) do
        if not notifiedModules[reg.module] then
            notifiedModules[reg.module] = true
            local mod = ns.modules and ns.modules[reg.module]
            if mod and mod.ExitEditPreview then
                mod:ExitEditPreview()
            end
        end
    end

    -- 위치 동기화 + Mover 숨기기
    for name, holder in pairs(self.CreatedMovers) do
        local currentPoint = GetPoint(holder.mover)
        if holder.mover._startPoint and holder.mover._startPoint ~= currentPoint then
            self:SyncMoverToPosition(name)
        end
        holder.mover._startPoint = nil
        holder.mover:Hide()
    end

    self:HideGrid()
    self.Settings.gridEnabled = false
    if self.NudgeFrame then self.NudgeFrame:Hide() end
    self.SelectedMover = nil
    self:ClearUndoRedo()

    print(CHAT_PREFIX .. "|cff00ff00" .. (L["MOVER_DISABLED"] or "편집 모드 종료. 위치가 저장되었습니다.") .. "|r")
end

function Movers:IsConfigMode()
    return self.ConfigMode
end

--------------------------------------------------------------------------------
-- 전투 진입 시 자동 종료
--------------------------------------------------------------------------------
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function()
    if Movers.ConfigMode then
        Movers:HideMovers()
        print(CHAT_PREFIX .. "|cffff6666" .. (L["MOVER_COMBAT_EXIT"] or "전투 진입으로 편집 모드가 자동 종료되었습니다.") .. "|r")
    end
end)
