------------------------------------------------------
-- DDingUI_Controller :: EditMode
-- 통합 편집모드 시스템 (EllesmereUI UnlockMode 패턴)
-- 모든 DDingUI 계열 애드온의 mover를 한 곳에서 관리
------------------------------------------------------
local Controller = _G.DDingUI_Controller
if not Controller then return end

local SL = _G.DDingUI_StyleLib
local floor = math.floor
local abs   = math.abs

------------------------------------------------------
-- Constants
------------------------------------------------------
local GRID_SPACING     = 32
local SNAP_THRESH      = 8
local MOVER_ALPHA      = 0.55
local MOVER_HOVER      = 0.85
local MOVER_DRAG       = 0.95
local TRANSITION_DUR   = 0.30
local GRID_ALPHA       = 0.12
local GRID_CENTER_A    = 0.25
local OVERLAY_ALPHA    = 0.40

-- 편집모드 진입점에서의 accent color (fallback)
local ACCENT = { 1, 0.64, 0 }  -- DDingUI orange

------------------------------------------------------
-- State
------------------------------------------------------
local EditMode = {}
Controller.EditMode = EditMode

EditMode._isActive       = false
EditMode._registeredAddons = {}    -- { addonKey = { enterFn, exitFn, getMoversFn } }
EditMode._allMovers      = {}     -- { key = { frame, displayText, addon } }
EditMode._overlayFrame   = nil
EditMode._gridFrame      = nil
EditMode._hudFrame       = nil
EditMode._selectedMover  = nil
EditMode._combatSuspended = false
EditMode._snapshotPositions = {}

-- Settings (Controller DB에서 로드)
EditMode.Settings = {
    gridEnabled   = false,
    gridMode      = "dimmed",        -- "disabled" | "dimmed" | "bright"
    snapEnabled   = true,
    snapToGrid    = true,
    snapToFrames  = true,
    snapToCenter  = true,
    snapThreshold = SNAP_THRESH,
    gridSize      = GRID_SPACING,
}

------------------------------------------------------
-- Registration API — 각 애드온이 자기 Mover 등록
-- EllesmereUI:RegisterUnlockElements() 패턴
------------------------------------------------------

--- 애드온의 편집모드 참여를 등록합니다.
--- @param addonKey string        고유 식별자 (e.g. "CDM", "UF")
--- @param callbacks table        { enter = fn, exit = fn, getMovers = fn() → { {key, frame, text}, ... } }
function EditMode:RegisterAddon(addonKey, callbacks)
    self._registeredAddons[addonKey] = callbacks
end

--- 특정 애드온 등록 해제
function EditMode:UnregisterAddon(addonKey)
    self._registeredAddons[addonKey] = nil
end

------------------------------------------------------
-- Internal: Rebuild mover list from all addons
------------------------------------------------------
local function RebuildMoverList()
    wipe(EditMode._allMovers)
    for addonKey, cbs in pairs(EditMode._registeredAddons) do
        if cbs.getMovers then
            local list = cbs.getMovers()
            if list then
                for _, entry in ipairs(list) do
                    EditMode._allMovers[entry.key] = {
                        frame       = entry.frame,
                        displayText = entry.text or entry.key,
                        addon       = addonKey,
                        parent      = entry.parent,
                    }
                end
            end
        end
    end
end

------------------------------------------------------
-- Overlay (전체 화면 반투명 배경)
------------------------------------------------------
local function CreateOverlay()
    if EditMode._overlayFrame then return EditMode._overlayFrame end

    local overlay = CreateFrame("Frame", "DDingUI_EditMode_Overlay", UIParent)
    overlay:SetFrameStrata("BACKGROUND")
    overlay:SetAllPoints(UIParent)
    overlay:EnableMouse(false)  -- 클릭은 통과

    local bg = overlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, OVERLAY_ALPHA)
    overlay._bg = bg

    overlay:Hide()
    EditMode._overlayFrame = overlay
    return overlay
end

------------------------------------------------------
-- Grid (스냅 그리드 오버레이)
------------------------------------------------------
local function CreateGrid()
    if EditMode._gridFrame then
        -- 기존 텍스처 정리
        if EditMode._gridFrame._lines then
            for _, tex in ipairs(EditMode._gridFrame._lines) do
                tex:Hide()
                tex:SetParent(nil)
            end
        end
    end

    local gridFrame = EditMode._gridFrame or CreateFrame("Frame", "DDingUI_EditMode_Grid", UIParent)
    gridFrame:SetFrameStrata("BACKGROUND")
    gridFrame:SetFrameLevel(2)
    gridFrame:SetAllPoints(UIParent)

    local lines = {}
    local w, h = UIParent:GetSize()
    local gridSize = EditMode.Settings.gridSize
    if gridSize <= 0 then gridSize = 32 end

    local lineAlpha = EditMode.Settings.gridMode == "bright" and 0.20 or GRID_ALPHA
    local centerAlpha = EditMode.Settings.gridMode == "bright" and 0.40 or GRID_CENTER_A

    -- 수직 선
    local numV = floor(w / gridSize)
    local centerX = floor(w / 2)
    for i = 0, numV do
        local x = i * gridSize
        local tex = gridFrame:CreateTexture(nil, "ARTWORK")
        tex:SetColorTexture(1, 1, 1,
            abs(x - centerX) < gridSize * 0.5 and centerAlpha or lineAlpha)
        tex:SetSize(1, h)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x, 0)
        lines[#lines + 1] = tex
    end

    -- 수평 선
    local numH = floor(h / gridSize)
    local centerY = floor(h / 2)
    for i = 0, numH do
        local y = i * gridSize
        local tex = gridFrame:CreateTexture(nil, "ARTWORK")
        tex:SetColorTexture(1, 1, 1,
            abs(y - centerY) < gridSize * 0.5 and centerAlpha or lineAlpha)
        tex:SetSize(w, 1)
        tex:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -y)
        lines[#lines + 1] = tex
    end

    -- 화면 중앙 십자선 강조
    local crossV = gridFrame:CreateTexture(nil, "OVERLAY")
    crossV:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.3)
    crossV:SetSize(1, h)
    crossV:SetPoint("TOP", gridFrame, "TOP", 0, 0)
    lines[#lines + 1] = crossV

    local crossH = gridFrame:CreateTexture(nil, "OVERLAY")
    crossH:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.3)
    crossH:SetSize(w, 1)
    crossH:SetPoint("LEFT", gridFrame, "LEFT", 0, 0)
    lines[#lines + 1] = crossH

    gridFrame._lines = lines
    gridFrame:Hide()
    EditMode._gridFrame = gridFrame
    return gridFrame
end

------------------------------------------------------
-- HUD (통합 컨트롤 패널 — 화면 상단 중앙)
------------------------------------------------------
local function CreateHUD()
    if EditMode._hudFrame then return EditMode._hudFrame end

    local SOLID = (SL and SL.Textures and SL.Textures.flat) or [[Interface\Buttons\WHITE8x8]]
    local fontPath = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"

    local hud = CreateFrame("Frame", "DDingUI_EditMode_HUD", UIParent, "BackdropTemplate")
    hud:SetSize(520, 56)
    hud:SetPoint("TOP", UIParent, "TOP", 0, -10)
    hud:SetFrameStrata("FULLSCREEN_DIALOG")
    hud:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    hud:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
    hud:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.5)

    -- 타이틀
    local title = hud:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 13, "")
    title:SetPoint("LEFT", 12, 8)
    title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    title:SetText("DDingUI Edit Mode")
    hud._title = title

    -- 선택된 프레임 이름
    local selLabel = hud:CreateFontString(nil, "OVERLAY")
    selLabel:SetFont(fontPath, 12, "")
    selLabel:SetPoint("LEFT", 12, -8)
    selLabel:SetTextColor(0.85, 0.85, 0.85, 1)
    selLabel:SetText("선택: 없음")
    hud._selLabel = selLabel

    -- 좌표 표시
    local posLabel = hud:CreateFontString(nil, "OVERLAY")
    posLabel:SetFont(fontPath, 11, "")
    posLabel:SetPoint("RIGHT", hud, "RIGHT", -160, -8)
    posLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    posLabel:SetText("")
    hud._posLabel = posLabel

    -- 스냅 상태
    local snapLabel = hud:CreateFontString(nil, "OVERLAY")
    snapLabel:SetFont(fontPath, 11, "")
    snapLabel:SetPoint("RIGHT", hud, "RIGHT", -160, 8)
    snapLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    snapLabel:SetText("Snap: ON  Grid: OFF")
    hud._snapLabel = snapLabel

    -- 버튼들 (우측)
    local btnW, btnH = 60, 24

    -- Grid 토글
    local gridBtn = CreateFrame("Button", nil, hud, "BackdropTemplate")
    gridBtn:SetSize(btnW, btnH)
    gridBtn:SetPoint("RIGHT", hud, "RIGHT", -85, 0)
    gridBtn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    gridBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    gridBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    local gridTxt = gridBtn:CreateFontString(nil, "OVERLAY")
    gridTxt:SetFont(fontPath, 11, "")
    gridTxt:SetPoint("CENTER")
    gridTxt:SetTextColor(0.85, 0.85, 0.85, 1)
    gridTxt:SetText("Grid")
    gridBtn:SetScript("OnClick", function()
        EditMode.Settings.gridEnabled = not EditMode.Settings.gridEnabled
        if EditMode.Settings.gridEnabled then
            if EditMode._gridFrame then EditMode._gridFrame:Show() end
        else
            if EditMode._gridFrame then EditMode._gridFrame:Hide() end
        end
        EditMode:UpdateHUD()
    end)
    gridBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
    end)
    gridBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    end)
    hud._gridBtn = gridBtn

    -- Snap 토글
    local snapBtn = CreateFrame("Button", nil, hud, "BackdropTemplate")
    snapBtn:SetSize(btnW, btnH)
    snapBtn:SetPoint("RIGHT", gridBtn, "LEFT", -6, 0)
    snapBtn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    snapBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    snapBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    local snapTxt = snapBtn:CreateFontString(nil, "OVERLAY")
    snapTxt:SetFont(fontPath, 11, "")
    snapTxt:SetPoint("CENTER")
    snapTxt:SetTextColor(0.85, 0.85, 0.85, 1)
    snapTxt:SetText("Snap")
    snapBtn:SetScript("OnClick", function()
        EditMode.Settings.snapEnabled = not EditMode.Settings.snapEnabled
        EditMode:UpdateHUD()
    end)
    snapBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
    end)
    snapBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    end)
    hud._snapBtn = snapBtn

    -- 닫기 버튼
    local closeBtn = CreateFrame("Button", nil, hud, "BackdropTemplate")
    closeBtn:SetSize(btnW, btnH)
    closeBtn:SetPoint("RIGHT", hud, "RIGHT", -12, 0)
    closeBtn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    closeBtn:SetBackdropColor(0.6, 0.15, 0.15, 0.8)
    closeBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.5)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTxt:SetFont(fontPath, 11, "")
    closeTxt:SetPoint("CENTER")
    closeTxt:SetTextColor(1, 1, 1, 1)
    closeTxt:SetText("닫기")
    closeBtn:SetScript("OnClick", function()
        EditMode:Exit()
    end)
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.8, 0.2, 0.2, 0.9)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.6, 0.15, 0.15, 0.8)
    end)
    hud._closeBtn = closeBtn

    -- 드래그 가능
    hud:SetMovable(true)
    hud:SetClampedToScreen(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self) self:StartMoving() end)
    hud:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    hud:Hide()
    EditMode._hudFrame = hud
    return hud
end

--- HUD 상태 업데이트
function EditMode:UpdateHUD()
    local hud = self._hudFrame
    if not hud then return end

    -- 선택 프레임
    if self._selectedMover then
        local info = self._allMovers[self._selectedMover]
        local name = info and info.displayText or self._selectedMover
        local addon = info and info.addon or "?"
        hud._selLabel:SetText("선택: |cffffa300" .. name .. "|r  [" .. addon .. "]")

        -- 좌표
        local f = info and info.frame
        if f and f:GetCenter() then
            local cx, cy = f:GetCenter()
            local uiCX, uiCY = UIParent:GetCenter()
            local x = floor((cx - uiCX) + 0.5)
            local y = floor((cy - uiCY) + 0.5)
            hud._posLabel:SetText(string.format("X: %d  Y: %d", x, y))
        end
    else
        hud._selLabel:SetText("선택: |cff666666없음|r  (프레임을 클릭하세요)")
        hud._posLabel:SetText("")
    end

    -- 스냅/그리드 상태
    local snapStr = self.Settings.snapEnabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    local gridStr = self.Settings.gridEnabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    hud._snapLabel:SetText("Snap: " .. snapStr .. "  Grid: " .. gridStr)
end

------------------------------------------------------
-- Snap calculation (프레임 간 + 중앙 + 그리드)
------------------------------------------------------
local function Round(n) return floor(n + 0.5) end

local function CalculateSnap(x, y, w, h, excludeFrame)
    local s = EditMode.Settings
    if not s.snapEnabled then return x, y end

    local thresh = s.snapThreshold
    local snapX, snapY = x, y

    -- 화면 중앙 스냅
    if s.snapToCenter then
        local cx, cy = UIParent:GetCenter()
        if abs(x - cx) < thresh then snapX = cx end
        if abs(y - cy) < thresh then snapY = cy end
    end

    -- 그리드 스냅
    if s.snapToGrid then
        local gs = s.gridSize
        if gs > 0 then
            local gx = Round(x / gs) * gs
            local gy = Round(y / gs) * gs
            if abs(x - gx) < thresh then snapX = gx end
            if abs(y - gy) < thresh then snapY = gy end
        end
    end

    -- 프레임 간 스냅
    if s.snapToFrames then
        local halfW, halfH = w / 2, h / 2
        local myL, myR = x - halfW, x + halfW
        local myT, myB = y + halfH, y - halfH

        for key, info in pairs(EditMode._allMovers) do
            local f = info.frame
            if f and f ~= excludeFrame and f:IsShown() then
                local rect = { f:GetRect() }
                if rect[1] then
                    local tL, tB, tW, tH = rect[1], rect[2], rect[3], rect[4]
                    local tR, tT = tL + tW, tB + tH
                    local tCX, tCY = tL + tW/2, tB + tH/2

                    -- 엣지 스냅
                    if abs(myL - tR) < thresh then snapX = tR + halfW end
                    if abs(myR - tL) < thresh then snapX = tL - halfW end
                    if abs(myL - tL) < thresh then snapX = tL + halfW end
                    if abs(myR - tR) < thresh then snapX = tR - halfW end
                    if abs(myT - tB) < thresh then snapY = tB - halfH end
                    if abs(myB - tT) < thresh then snapY = tT + halfH end
                    if abs(myT - tT) < thresh then snapY = tT - halfH end
                    if abs(myB - tB) < thresh then snapY = tB + halfH end

                    -- 중앙 정렬
                    if abs(x - tCX) < thresh then snapX = tCX end
                    if abs(y - tCY) < thresh then snapY = tCY end
                end
            end
        end
    end

    return snapX, snapY
end

------------------------------------------------------
-- Mover overlay creation (각 프레임 위에 드래그 핸들)
------------------------------------------------------
local function CreateMoverOverlay(key, info)
    local f = info.frame
    if not f then return nil end

    local fontPath = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
    local SOLID = (SL and SL.Textures and SL.Textures.flat) or [[Interface\Buttons\WHITE8x8]]

    local mover = CreateFrame("Button", "DDingUI_EM_" .. key, UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(100)
    mover:SetClampedToScreen(true)

    -- 크기 동기화
    local function SyncSize()
        local pw = f:GetWidth()
        local ph = f:GetHeight()
        if pw > 0 and ph > 0 then
            mover:SetSize(math.max(pw, 20), math.max(ph, 12))
        else
            mover:SetSize(100, 20)
        end
    end
    SyncSize()

    -- 위치 동기화 (parent center와 같은 위치)
    local function SyncPos()
        local cx, cy = f:GetCenter()
        if cx and cy then
            mover:ClearAllPoints()
            mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        end
    end
    SyncPos()

    -- 배경
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.2, 0.4, MOVER_ALPHA)
    mover._bg = bg

    -- 테두리 (4-edge)
    local brd = {}
    for i = 1, 4 do
        brd[i] = mover:CreateTexture(nil, "OVERLAY", nil, 7)
        brd[i]:SetColorTexture(0.4, 0.6, 1, 0.7)
    end
    brd[1]:SetHeight(1); brd[1]:SetPoint("TOPLEFT"); brd[1]:SetPoint("TOPRIGHT")
    brd[2]:SetHeight(1); brd[2]:SetPoint("BOTTOMLEFT"); brd[2]:SetPoint("BOTTOMRIGHT")
    brd[3]:SetWidth(1);  brd[3]:SetPoint("TOPLEFT", brd[1], "BOTTOMLEFT"); brd[3]:SetPoint("BOTTOMLEFT", brd[2], "TOPLEFT")
    brd[4]:SetWidth(1);  brd[4]:SetPoint("TOPRIGHT", brd[1], "BOTTOMRIGHT"); brd[4]:SetPoint("BOTTOMRIGHT", brd[2], "TOPRIGHT")
    mover._border = brd

    -- 이름 표시
    local label = mover:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath, 10, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetTextColor(1, 1, 1, 1)
    label:SetText(info.displayText or key)
    mover._label = label

    -- 드래그
    local isDragging = false
    local dragOffX, dragOffY = 0, 0

    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        isDragging = true
        bg:SetColorTexture(0.15, 0.3, 0.6, MOVER_DRAG)

        local scale = self:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        mx, my = mx / scale, my / scale
        local cx, cy = self:GetCenter()
        if cx and cy then
            dragOffX = cx - mx
            dragOffY = cy - my
        end

        -- 그리드 임시 표시
        if not EditMode.Settings.gridEnabled and EditMode._gridFrame then
            EditMode._gridFrame:Show()
            self._tempGrid = true
        end

        -- 스냅샷 저장
        EditMode._snapshotPositions[key] = { self:GetCenter() }

        EditMode._selectedMover = key
        EditMode:UpdateHUD()
    end)

    local updateDrag = CreateFrame("Frame")
    mover._updateDrag = updateDrag

    mover:SetScript("OnDragStop", function(self)
        if not isDragging then return end
        isDragging = false
        updateDrag:SetScript("OnUpdate", nil)
        bg:SetColorTexture(0.1, 0.2, 0.4, MOVER_ALPHA)

        -- 임시 그리드 숨김
        if self._tempGrid then
            if not EditMode.Settings.gridEnabled and EditMode._gridFrame then
                EditMode._gridFrame:Hide()
            end
            self._tempGrid = nil
        end

        -- parent 위치 동기화
        if f then
            local cx, cy = self:GetCenter()
            if cx and cy then
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
            end
        end

        -- 위치 저장 콜백
        local addonCbs = EditMode._registeredAddons[info.addon]
        if addonCbs and addonCbs.onMoverStop then
            addonCbs.onMoverStop(key, mover)
        end

        EditMode:UpdateHUD()
    end)

    -- OnUpdate 기반 드래그 (OnDragStart에서 활성화)
    mover:HookScript("OnDragStart", function(self)
        updateDrag:SetScript("OnUpdate", function(_, elapsed)
            if not isDragging then return end
            local scale = self:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            mx, my = mx / scale, my / scale

            local targetX = mx + dragOffX
            local targetY = my + dragOffY
            local w, h = self:GetSize()
            local sx, sy = CalculateSnap(targetX, targetY, w, h, self)

            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)

            -- parent live follow
            if f then
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
            end

            EditMode:UpdateHUD()
        end)
    end)

    -- 호버
    mover:SetScript("OnEnter", function(self)
        if not isDragging then
            bg:SetColorTexture(0.15, 0.3, 0.6, MOVER_HOVER)
            for i = 1, 4 do brd[i]:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1) end
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(info.displayText or key, 1, 1, 1)
        GameTooltip:AddLine("[" .. info.addon .. "]", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("좌클릭+드래그: 이동", 0.5, 0.8, 0.5)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function(self)
        if not isDragging then
            bg:SetColorTexture(0.1, 0.2, 0.4, MOVER_ALPHA)
            for i = 1, 4 do brd[i]:SetColorTexture(0.4, 0.6, 1, 0.7) end
        end
        GameTooltip:Hide()
    end)

    -- 클릭 (선택)
    mover:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            EditMode._selectedMover = key
            EditMode:UpdateHUD()
        end
    end)

    mover._key = key
    mover._info = info
    mover._syncSize = SyncSize
    mover._syncPos = SyncPos
    mover:Hide()

    return mover
end

------------------------------------------------------
-- Enter / Exit
------------------------------------------------------

--- 통합 편집모드 진입
function EditMode:Enter()
    if InCombatLockdown() then
        print("|cffffffffDDing|r|cffffa300UI|r |cff999999Controller|r: |cffff6666전투 중에는 편집모드를 사용할 수 없습니다|r")
        return
    end

    if self._isActive then return end
    self._isActive = true

    -- 설정 패널 닫기
    if Controller.ToggleSettings then
        local panel = Controller._settingsPanel
        if panel and panel.frame and panel.frame:IsShown() then
            panel.frame:Hide()
        end
    end

    -- 1. 각 애드온에 편집모드 진입 통보
    for addonKey, cbs in pairs(self._registeredAddons) do
        if cbs.enter then
            pcall(cbs.enter)
        end
    end

    -- 2. Mover 목록 수집
    RebuildMoverList()

    -- 3. 오버레이 생성/표시
    local overlay = CreateOverlay()
    overlay:Show()

    -- 4. 그리드 생성
    CreateGrid()
    if self.Settings.gridEnabled and self._gridFrame then
        self._gridFrame:Show()
    end

    -- 5. Mover 오버레이 생성/표시
    for key, info in pairs(self._allMovers) do
        if not info._moverOverlay then
            info._moverOverlay = CreateMoverOverlay(key, info)
        end
        if info._moverOverlay then
            info._moverOverlay._syncSize()
            info._moverOverlay._syncPos()
            info._moverOverlay:Show()
        end
    end

    -- 6. HUD 생성/표시
    local hud = CreateHUD()
    hud:Show()
    self:UpdateHUD()

    -- 7. 페이드 인 애니메이션
    if overlay then
        overlay._bg:SetAlpha(0)
        local fadeIn = CreateFrame("Frame")
        local elapsed = 0
        fadeIn:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            local t = math.min(elapsed / TRANSITION_DUR, 1)
            overlay._bg:SetAlpha(OVERLAY_ALPHA * t)
            if t >= 1 then self:SetScript("OnUpdate", nil) end
        end)
    end

    -- ESC로 종료
    local frameName = "DDingUI_EditMode_HUD"
    local alreadyRegistered = false
    for _, name in ipairs(UISpecialFrames) do
        if name == frameName then alreadyRegistered = true; break end
    end
    if not alreadyRegistered then
        tinsert(UISpecialFrames, frameName)
    end

    print("|cffffffffDDing|r|cffffa300UI|r |cff999999Controller|r: |cff00ff00편집모드 활성화|r — 프레임을 드래그하여 이동하세요")
end

--- 통합 편집모드 종료
function EditMode:Exit()
    if not self._isActive then return end
    self._isActive = false

    -- 1. Mover 오버레이 숨김
    for key, info in pairs(self._allMovers) do
        if info._moverOverlay then
            info._moverOverlay:Hide()
        end
    end

    -- 2. 오버레이/그리드/HUD 숨김
    if self._overlayFrame then self._overlayFrame:Hide() end
    if self._gridFrame then self._gridFrame:Hide() end
    if self._hudFrame then self._hudFrame:Hide() end

    -- 3. 각 애드온에 편집모드 종료 통보
    for addonKey, cbs in pairs(self._registeredAddons) do
        if cbs.exit then
            pcall(cbs.exit)
        end
    end

    self._selectedMover = nil

    -- 4. 설정 저장
    if Controller.db then
        Controller.db.editMode = Controller.db.editMode or {}
        Controller.db.editMode.settings = self.Settings
        DDingUI_ControllerDB = Controller.db
    end

    print("|cffffffffDDing|r|cffffa300UI|r |cff999999Controller|r: |cff00ff00편집모드 종료|r — 위치가 저장되었습니다")
end

--- 토글 (진입/종료)
function EditMode:Toggle()
    if self._isActive then
        self:Exit()
    else
        self:Enter()
    end
end

--- 활성 상태 반환
function EditMode:IsActive()
    return self._isActive
end

------------------------------------------------------
-- Combat auto-suspend
------------------------------------------------------
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- 전투 진입: 편집모드 일시 중지
        if EditMode._isActive then
            EditMode._combatSuspended = true
            -- Mover 오버레이만 숨김 (상태는 유지)
            for key, info in pairs(EditMode._allMovers) do
                if info._moverOverlay then info._moverOverlay:Hide() end
            end
            if EditMode._overlayFrame then EditMode._overlayFrame:Hide() end
            if EditMode._gridFrame then EditMode._gridFrame:Hide() end
            if EditMode._hudFrame then EditMode._hudFrame:Hide() end
            print("|cffffffffDDing|r|cffffa300UI|r |cff999999Controller|r: |cffffcc00전투 중 편집모드 일시 정지|r")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- 전투 종료: 편집모드 복귀
        if EditMode._combatSuspended then
            EditMode._combatSuspended = false
            -- 다시 표시
            for key, info in pairs(EditMode._allMovers) do
                if info._moverOverlay then
                    info._moverOverlay._syncSize()
                    info._moverOverlay._syncPos()
                    info._moverOverlay:Show()
                end
            end
            if EditMode._overlayFrame then EditMode._overlayFrame:Show() end
            if EditMode.Settings.gridEnabled and EditMode._gridFrame then EditMode._gridFrame:Show() end
            if EditMode._hudFrame then EditMode._hudFrame:Show() end
            EditMode:UpdateHUD()
            print("|cffffffffDDing|r|cffffa300UI|r |cff999999Controller|r: |cff00ff00편집모드 복귀|r")
        end
    end
end)

------------------------------------------------------
-- Auto-register DDingUI addons (CDM / UF)
------------------------------------------------------
local autoRegFrame = CreateFrame("Frame")
autoRegFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
autoRegFrame._done = false
autoRegFrame:SetScript("OnEvent", function(self)
    if self._done then return end
    self._done = true

    -- ── DDingUI (CDM) ─────────────────────────────
    -- AceAddon 기반: LibStub를 통해 접근
    local ok, CDM_Addon = pcall(function()
        return LibStub("AceAddon-3.0"):GetAddon("DDingUI", true)
    end)
    if not ok then CDM_Addon = nil end

    if CDM_Addon and CDM_Addon.Movers then
        local Movers = CDM_Addon.Movers
        EditMode:RegisterAddon("CDM", {
            enter = function()
                if Movers.ShowMovers then
                    Movers._silentToggle = true
                    Movers:ShowMovers()
                    Movers._silentToggle = nil
                end
            end,
            exit = function()
                if Movers.HideMovers then
                    Movers._silentToggle = true
                    Movers:HideMovers()
                    Movers._silentToggle = nil
                end
            end,
            getMovers = function()
                local list = {}
                if Movers.CreatedMovers then
                    for name, holder in pairs(Movers.CreatedMovers) do
                        if holder.mover and holder.parent then
                            list[#list + 1] = {
                                key    = "CDM_" .. name,
                                frame  = holder.parent,
                                text   = holder.displayText or name,
                                parent = holder.parent,
                            }
                        end
                    end
                end
                return list
            end,
            onMoverStop = function(key, moverOverlay)
                local name = key:gsub("^CDM_", "")
                if Movers.CreatedMovers and Movers.CreatedMovers[name] then
                    local holder = Movers.CreatedMovers[name]
                    if holder.mover and moverOverlay then
                        local cx, cy = moverOverlay:GetCenter()
                        if cx and cy then
                            holder.mover:ClearAllPoints()
                            holder.mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
                        end
                    end
                    if Movers.SyncMoverToModuleSettings then
                        Movers:SyncMoverToModuleSettings(name)
                    end
                    if Movers.SaveMoverPosition then
                        Movers:SaveMoverPosition(name)
                    end
                end
            end,
        })
    end

    -- ── DDingUI_UF ────────────────────────────────
    -- namespace 기반: C_AddOns로 로드 확인 후 Mover 접근
    local ufLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DDingUI_UF")
    if ufLoaded then
        -- UF의 Mover 시스템은 ns.Mover (Init.lua → OnPlayerLogin에서 초기화)
        -- 약간 지연 후 등록 (UF 초기화 완료 대기)
        C_Timer.After(1.0, function()
            -- UF의 ns는 글로벌에 노출되지 않으므로, 공개 프레임 이름으로 탐색
            local UF_Mover = nil
            -- DDingUI_UF가 글로벌에 노출하는 Mover 객체 탐색
            -- UF는 oUF 또는 standalone 프레임을 _G에 등록 (e.g. "ddingUI_Player")
            local UF_UNITS = {
                { key = "UF_Player",       globalName = "ddingUI_Player",       text = "Player" },
                { key = "UF_Target",       globalName = "ddingUI_Target",       text = "Target" },
                { key = "UF_ToT",          globalName = "ddingUI_TargetTarget", text = "Target of Target" },
                { key = "UF_Focus",        globalName = "ddingUI_Focus",        text = "Focus" },
                { key = "UF_FocusTarget",  globalName = "ddingUI_FocusTarget",  text = "Focus Target" },
                { key = "UF_Pet",          globalName = "ddingUI_Pet",          text = "Pet" },
            }

            EditMode:RegisterAddon("UF", {
                enter = function()
                    -- UF는 별도 편집모드가 있지만, Controller 통합 모드에서는 passthrough
                end,
                exit = function()
                    -- 저장은 onMoverStop에서 처리
                end,
                getMovers = function()
                    local list = {}
                    for _, info in ipairs(UF_UNITS) do
                        local frame = _G[info.globalName]
                        if frame and frame.GetCenter then
                            list[#list + 1] = {
                                key    = info.key,
                                frame  = frame,
                                text   = info.text,
                                parent = frame,
                            }
                        end
                    end
                    return list
                end,
                onMoverStop = function(key, moverOverlay)
                    -- UF 프레임 위치를 SavedVariables에 저장
                    -- ddingUI_UFDB.movers 에 포인트 문자열로 저장
                    if not moverOverlay then return end
                    local cx, cy = moverOverlay:GetCenter()
                    if not cx then return end

                    -- 프레임 위치 동기화
                    for _, info in ipairs(UF_UNITS) do
                        if info.key == key then
                            local frame = _G[info.globalName]
                            if frame then
                                frame:ClearAllPoints()
                                frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
                            end
                            -- ddingUI_UFDB에 저장
                            if ddingUI_UFDB then
                                local db = ddingUI_UFDB
                                -- 현재 프로필의 movers에 저장
                                if db.profiles then
                                    for _, profile in pairs(db.profiles) do
                                        if profile.movers then
                                            local moverName = info.text
                                            profile.movers[moverName] = string.format(
                                                "CENTER,UIParent,BOTTOMLEFT,%d,%d",
                                                floor(cx + 0.5), floor(cy + 0.5)
                                            )
                                            break
                                        end
                                    end
                                end
                            end
                            break
                        end
                    end
                end,
            })
        end)
    end

    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)

