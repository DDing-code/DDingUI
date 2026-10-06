------------------------------------------------------
-- DDingUI_StyleLib :: EditMode
-- 시리즈 공통 편집 모드 부품 (StyleLib 1.4) -- [STYLE]
--   리모컨(CreateEditRemote) · 무버 표면(StyleMover) · 선택 HUD(CreateMoverHUD)
--   격자(CreateEditGrid) · 정렬 안내선(CreateEditGuides) · 스냅 계산(Snap*)
-- 위치 모델·저장은 각 애드온이 가진다. 여기는 보이는 것과 입력만 통일한다.
------------------------------------------------------
local ADDON_NAME = ...
local MAJOR = "DDingUI-FX-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end
if Lib.__ddingStyleLibLoadOwner ~= ADDON_NAME and Lib.CreateEditRemote then return end

local C = Lib.Colors
local F = Lib.Font
local FLAT = Lib.Textures and Lib.Textures.flat or [[Interface\Buttons\WHITE8x8]]
local Motion = Lib.Motion

local function u(t) return t[1], t[2], t[3], t[4] or 1 end
local function accentOf(addonName)
    local from = Lib.GetAccent(addonName)
    return from or { 0.9, 0.45, 0.12, 1 }
end
local function SetButtonText(btn, text)
    if btn.label then btn.label:SetText(text) elseif btn.SetText then btn:SetText(text) end
end
local function SetButtonEnabled(btn, on)
    if btn.SetDisabledState then btn:SetDisabledState(not on) elseif btn.SetEnabled then btn:SetEnabled(on) end
end
local function MakeText(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(F.path, size or F.normal, "")
    fs:SetTextColor(u(color or C.text.normal))
    if justify then fs:SetJustifyH(justify) end
    return fs
end

------------------------------------------------------
-- 공통 규격 (시리즈 표준 C12)
------------------------------------------------------
Lib.EditModeSpec = {
    gridSpacing   = 32,                 -- 기본 격자 간격
    gridChoices   = { 16, 32, 64 },     -- 리모컨에서 순환
    snapThreshold = 8,                  -- 스냅 거리(px)
    nudge         = 1,                  -- 넛지 1px
    nudgeShift    = 10,                 -- Shift 넛지 10px
    remoteWidth   = 300,
    remoteDefault = { point = "TOP", x = 0, y = -55 },
    hudFormat     = "X %d  Y %d  \194\183  %d\195\151%d", -- "X 0  Y 0 · W×H"
    dimAlpha      = 0.18,               -- 편집 중 화면 어둡게
    gridFade      = 0.75,
}
local SPEC = Lib.EditModeSpec

------------------------------------------------------
-- 스냅 계산 (순수 함수)
------------------------------------------------------
--- 격자 간격의 배수로 맞춘다. 거리가 threshold를 넘으면 그대로 돌려준다.
function Lib.SnapToGrid(value, spacing, threshold)
    spacing = spacing or SPEC.gridSpacing
    threshold = threshold or SPEC.snapThreshold
    local snapped = math.floor(value / spacing + 0.5) * spacing
    if math.abs(snapped - value) <= threshold then return snapped, true end
    return value, false
end

--- 0(중앙)에 가까우면 0으로 맞춘다.
function Lib.SnapToCenter(value, threshold)
    threshold = threshold or SPEC.snapThreshold
    if math.abs(value) <= threshold then return 0, true end
    return value, false
end

--- rect = {left, bottom, width, height}. others는 같은 형식의 목록.
--- 가장자리·중앙이 가까우면 보정 dx, dy를 돌려준다(없으면 0).
function Lib.SnapToRects(rect, others, threshold)
    threshold = threshold or SPEC.snapThreshold
    local l, b, w, h = rect[1], rect[2], rect[3], rect[4]
    local r, t, cx, cy = l + w, b + h, l + w / 2, b + h / 2
    local bestDx, bestDy, bestX, bestY = 0, 0, threshold + 1, threshold + 1
    for _, o in ipairs(others or {}) do
        local ol, ob, ow, oh = o[1], o[2], o[3], o[4]
        local orr, ot, ocx, ocy = ol + ow, ob + oh, ol + ow / 2, ob + oh / 2
        for _, pair in ipairs({ { l, ol }, { l, orr }, { r, ol }, { r, orr }, { cx, ocx } }) do
            local d = pair[2] - pair[1]
            if math.abs(d) <= threshold and math.abs(d) < bestX then bestX, bestDx = math.abs(d), d end
        end
        for _, pair in ipairs({ { b, ob }, { b, ot }, { t, ob }, { t, ot }, { cy, ocy } }) do
            local d = pair[2] - pair[1]
            if math.abs(d) <= threshold and math.abs(d) < bestY then bestY, bestDy = math.abs(d), d end
        end
    end
    return bestDx, bestDy
end

------------------------------------------------------
-- 격자
------------------------------------------------------
--- 화면 전체 격자. 중앙에서 시작하는 accent 선 + 어두운 막.
--- @return Frame  :SetSpacing(n), :ShowAnimated(), :HideAnimated(), :GetSpacing()
function Lib.CreateEditGrid(addonName, opts)
    opts = opts or {}
    local accent = accentOf(addonName)
    local grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid:EnableMouse(false)
    grid.dim = grid:CreateTexture(nil, "BACKGROUND")
    grid.dim:SetAllPoints()
    grid.dim:SetColorTexture(0, 0, 0, opts.dimAlpha or SPEC.dimAlpha)
    grid.lines = {}
    grid.spacing = opts.spacing or SPEC.gridSpacing
    grid:Hide()

    local function acquire(i)
        local tex = grid.lines[i]
        if not tex then
            tex = grid:CreateTexture(nil, "ARTWORK")
            grid.lines[i] = tex
        end
        tex:ClearAllPoints()
        tex:Show()
        return tex
    end

    function grid:Rebuild()
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        local cx, cy = w / 2, h / 2
        local s = self.spacing
        local n = 0
        local function line(x, y, isCenter)
            n = n + 1
            local tex = acquire(n)
            local a = isCenter and 0.45 or 0.10
            tex:SetColorTexture(accent[1], accent[2], accent[3], a)
            if x then
                tex:SetSize(1, h)
                tex:SetPoint("BOTTOM", self, "BOTTOMLEFT", x, 0)
            else
                tex:SetSize(w, 1)
                tex:SetPoint("LEFT", self, "BOTTOMLEFT", 0, y)
            end
        end
        local k = 1
        while cx + k * s <= w do line(cx + k * s); line(cx - k * s); k = k + 1 end
        k = 1
        while cy + k * s <= h do line(nil, cy + k * s); line(nil, cy - k * s); k = k + 1 end
        line(cx, nil, true)
        line(nil, cy, true)
        for i = n + 1, #self.lines do self.lines[i]:Hide() end
    end

    function grid:SetSpacing(n)
        self.spacing = n or SPEC.gridSpacing
        if self:IsShown() then self:Rebuild() end
    end
    function grid:GetSpacing() return self.spacing end
    function grid:ShowAnimated()
        self:Rebuild()
        if Motion and Motion.FadeIn then
            if not self:IsShown() then self:SetAlpha(0) end -- 숨겨져 있었으면 0에서 페이드
            Motion.FadeIn(self, opts.fade or SPEC.gridFade)
        else
            self:SetAlpha(1); self:Show()
        end
    end
    function grid:HideAnimated()
        if Motion and Motion.FadeOut then
            Motion.FadeOut(self, 0.2, { hideOnFinish = true })
        else
            self:Hide()
        end
    end
    grid:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:Rebuild() end end)
    return grid
end

------------------------------------------------------
-- 정렬 안내선 (드래그 중 무버 중심을 지나는 화면 전체 선)
------------------------------------------------------
function Lib.CreateEditGuides(addonName)
    local accent = accentOf(addonName)
    local guides = CreateFrame("Frame", nil, UIParent)
    guides:SetAllPoints(UIParent)
    guides:SetFrameStrata("HIGH")
    guides:EnableMouse(false)
    guides.v = guides:CreateTexture(nil, "OVERLAY")
    guides.h = guides:CreateTexture(nil, "OVERLAY")
    guides.v:SetColorTexture(accent[1], accent[2], accent[3], 0.6)
    guides.h:SetColorTexture(accent[1], accent[2], accent[3], 0.6)
    guides:Hide()
    --- cx, cy는 UIParent 왼쪽 아래 기준 좌표
    function guides:ShowAt(cx, cy)
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        self.v:ClearAllPoints(); self.v:SetSize(1, h); self.v:SetPoint("BOTTOM", self, "BOTTOMLEFT", cx, 0)
        self.h:ClearAllPoints(); self.h:SetSize(w, 1); self.h:SetPoint("LEFT", self, "BOTTOMLEFT", 0, cy)
        self:Show()
    end
    return guides
end

------------------------------------------------------
-- 무버 표면
------------------------------------------------------
--- 애드온이 만든 overlay 프레임에 공통 표면을 입힌다.
--- 평상시: accent 테두리 1px + accent 12% 채움 / 오버: 밝아짐 / 선택: 2px 테두리 + 모서리 꺾쇠
--- @return table handle  :SetSelected(bool), :SetHover(bool), :SetLabel(text), :SetDisabled(bool)
function Lib.StyleMover(overlay, addonName, opts)
    opts = opts or {}
    local accent = accentOf(addonName)
    local st = overlay._ddslMover
    if st then return st end
    st = { overlay = overlay, selected = false, hover = false, disabled = false }
    overlay._ddslMover = st

    st.bg = overlay:CreateTexture(nil, "BACKGROUND")
    st.bg:SetAllPoints()
    st.edges = {}
    for i = 1, 4 do
        local e = overlay:CreateTexture(nil, "BORDER")
        st.edges[i] = e
    end
    st.brackets = {}
    for i = 1, 8 do
        local b = overlay:CreateTexture(nil, "OVERLAY")
        b:Hide()
        st.brackets[i] = b
    end
    st.label = MakeText(overlay, F.normal, C.text.normal, "CENTER")
    st.label:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    st.label:SetText(opts.label or "")
    st.badge = MakeText(overlay, F.small, C.text.dim, "RIGHT")
    st.badge:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -4, -3)
    st.badge:Hide()

    local function layoutEdges(thick)
        local e = st.edges
        e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(thick)
        e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(thick)
        e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(thick)
        e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(thick)
    end
    local function layoutBrackets()
        local b, L, T = st.brackets, 12, 2
        local pts = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
        for i, p in ipairs(pts) do
            local hx, vx = b[i * 2 - 1], b[i * 2]
            hx:ClearAllPoints(); hx:SetSize(L, T); hx:SetPoint(p, overlay, p, 0, 0)
            vx:ClearAllPoints(); vx:SetSize(T, L); vx:SetPoint(p, overlay, p, 0, 0)
        end
    end

    function st:Refresh()
        local a = accent
        local r, g, b = a[1], a[2], a[3]
        if self.disabled then r, g, b = 0.42, 0.42, 0.42 end
        local borderA = self.selected and 1 or (self.hover and 1 or 0.88)
        local fillA = self.selected and 0.82 or (self.hover and 0.70 or 0.58)
        local fillMul = self.selected and 0.20 or (self.hover and 0.16 or 0.12)
        self.bg:SetColorTexture(r * fillMul, g * fillMul, b * fillMul, fillA)
        layoutEdges(self.selected and 2 or 1)
        for _, e in ipairs(self.edges) do e:SetColorTexture(r, g, b, borderA) end
        layoutBrackets()
        for _, br in ipairs(self.brackets) do
            br:SetColorTexture(r, g, b, 1)
            br:SetShown(self.selected)
        end
        self.label:SetTextColor(u(self.disabled and C.text.dim or C.text.normal))
    end
    function st:SetSelected(v) self.selected = v and true or false; self:Refresh() end
    function st:SetHover(v) self.hover = v and true or false; self:Refresh() end
    function st:SetDisabled(v, text)
        self.disabled = v and true or false
        self.badge:SetText(text or "")
        self.badge:SetShown(self.disabled and text ~= nil)
        self:Refresh()
    end
    function st:SetLabel(text) self.label:SetText(text or "") end
    st:Refresh()
    return st
end

------------------------------------------------------
-- 선택 HUD (중심 십자선 + 좌표 readout)
------------------------------------------------------
--- overlay에 붙는 HUD. 좌표 기준은 호출자가 넘기는 값 그대로 쓴다(앵커 상대 오프셋 권장).
--- @return Frame hud  :Update(x, y, w, h)
function Lib.CreateMoverHUD(overlay, addonName)
    local accent = accentOf(addonName)
    local hud = CreateFrame("Frame", nil, overlay)
    hud:SetAllPoints(overlay)
    hud:SetFrameLevel(overlay:GetFrameLevel() + 5)
    hud:EnableMouse(false)
    hud.crossV = hud:CreateTexture(nil, "OVERLAY")
    hud.crossV:SetSize(1, 12); hud.crossV:SetPoint("CENTER")
    hud.crossV:SetColorTexture(accent[1], accent[2], accent[3], 0.78)
    hud.crossH = hud:CreateTexture(nil, "OVERLAY")
    hud.crossH:SetSize(12, 1); hud.crossH:SetPoint("CENTER")
    hud.crossH:SetColorTexture(accent[1], accent[2], accent[3], 0.78)

    local box = CreateFrame("Frame", nil, hud)
    box:SetSize(178, 18)
    box:SetPoint("TOPRIGHT", overlay, "BOTTOMRIGHT", 0, -4)
    box:SetClampedToScreen(true)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(C.bg.input[1], C.bg.input[2], C.bg.input[3], 0.94)
    box.stripe = box:CreateTexture(nil, "BORDER")
    box.stripe:SetWidth(2); box.stripe:SetPoint("TOPLEFT"); box.stripe:SetPoint("BOTTOMLEFT")
    box.stripe:SetColorTexture(accent[1], accent[2], accent[3], 1)
    box.text = MakeText(box, F.small, { 0.88, 0.91, 0.96, 1 }, "LEFT")
    box.text:SetPoint("LEFT", box, "LEFT", 8, 0)
    box.text:SetPoint("RIGHT", box, "RIGHT", -6, 0)
    hud.box = box

    function hud:Update(x, y, w, h)
        self.box.text:SetFormattedText(SPEC.hudFormat,
            math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5),
            math.floor((w or 0) + 0.5), math.floor((h or 0) + 0.5))
    end
    hud:Hide()
    return hud
end

------------------------------------------------------
-- 리모컨
------------------------------------------------------
--- 편집 모드 제어 패널. 둥근 창(시안 7) + 시리즈 제목줄.
--- opts:
---   title(기본 "편집 모드"), version, width(기본 300)
---   frames: function() -> { {text=, value=}, ... }   (프레임 선택 드롭다운, 없으면 생략)
---   onSelectFrame(value)
---   onNudge(dx, dy)            -- Shift는 호출 전에 반영됨
---   onApplyXY(x, y)            -- X/Y 입력 확정
---   onReset(), onUndo(), onRedo(), onDone()   -- 없는 것은 버튼을 만들지 않음
---   grid = { enabled=bool, spacing=n, onToggle(bool), onSpacing(n) }
---   snap = { enabled=bool, center=bool, grid=bool, frames=bool, noFrames=bool, onChange(key, bool) }
---   editRemotePos 저장 형식(시리즈 공통): { point = "TOP", x = 0, y = -55 } (이름 있는 키)
---   extra(parent, y) -> height  -- 애드온 전용 컨트롤 추가 (y는 다음 줄 시작 오프셋)
---   loadPosition() -> point, x, y / savePosition(point, x, y)
--- @return Frame remote  :SetSelection(info), :SetUndoState(canUndo, canRedo), :SetGridState(on, spacing)
function Lib.CreateEditRemote(addonName, opts)
    opts = opts or {}
    local width = opts.width or SPEC.remoteWidth
    local remote = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    remote:SetWidth(width)
    remote:SetFrameStrata("DIALOG")
    remote:SetFrameLevel(200)
    remote:SetMovable(true)
    remote:EnableMouse(true)
    if Lib.AllowOffscreen then Lib.AllowOffscreen(remote, 48) else remote:SetClampedToScreen(true) end
    Lib.MakeRounded(remote, Lib.Radius.window, C.bg.main, C.border.default)
    remote._ddslMotionBaseScale = 1

    local point, x, y = SPEC.remoteDefault.point, SPEC.remoteDefault.x, SPEC.remoteDefault.y
    if opts.loadPosition then
        local p, px, py = opts.loadPosition()
        if p then point, x, y = p, px or 0, py or 0 end
    end
    remote:SetPoint(point, UIParent, point, x, y)

    local bar = Lib.CreateTitleBar(remote, addonName, opts.title or "편집 모드", opts.version or "", { rounded = true })
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() remote:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        remote:StopMovingOrSizing()
        if opts.savePosition then
            local p, _, _, px, py = remote:GetPoint(1)
            opts.savePosition(p, math.floor((px or 0) + 0.5), math.floor((py or 0) + 0.5))
        end
    end)
    remote.titleBar = bar

    local PAD, ROW = 14, 30
    local cy = -(34 + 10) -- 제목줄 아래
    local function row(h) local at = cy; cy = cy - (h or ROW); return at end

    -- 프레임 선택
    if opts.frames then
        local ddY = row(34)
        local function build(selected)
            if remote.frameDropdown then remote.frameDropdown:Hide() end
            local dd = Lib.CreateDropdown(remote, addonName, "", opts.frames() or {}, selected, {
                width = width - PAD * 2 - 80,
                onChange = function(value) if opts.onSelectFrame then opts.onSelectFrame(value) end end,
            })
            dd:SetPoint("TOPLEFT", remote, "TOPLEFT", PAD, ddY)
            remote.frameDropdown = dd
        end
        build(nil)
        --- 목록이 바뀌면 드롭다운을 다시 만든다(위젯은 항목을 고정으로 가진다).
        function remote:RefreshFrames(selected)
            build(selected)
        end
    end

    -- 선택 정보
    remote.nameText = MakeText(remote, F.normal, C.text.highlight or C.text.normal, "LEFT")
    remote.nameText:SetPoint("TOPLEFT", remote, "TOPLEFT", PAD, row(20))
    remote.nameText:SetPoint("RIGHT", remote, "RIGHT", -PAD, 0)
    remote.nameText:SetText("선택된 프레임 없음")
    remote.infoText = MakeText(remote, F.small, C.text.dim, "LEFT")
    remote.infoText:SetPoint("TOPLEFT", remote, "TOPLEFT", PAD, row(22))
    remote.infoText:SetPoint("RIGHT", remote, "RIGHT", -PAD, 0)
    remote.infoText:SetText("")

    -- X / Y 입력 + 넛지
    -- 숫자·소수점·음수 부호만 허용한다(SetNumeric은 '-'를 막으므로 쓰지 않는다).
    local function SignedNumberFilter(eb, userInput)
        if not userInput then return end
        local text = eb:GetText() or ""
        local filtered = text:gsub("[^%d%.%-]", "")
        local head, rest = filtered:match("^(%-?)(.*)$")
        rest = rest:gsub("%-", "")
        local first, tail = rest:match("^([^%.]*%.?)(.*)$")
        filtered = head .. first .. (tail or ""):gsub("%.", "")
        if filtered ~= text then eb:SetText(filtered); eb:SetCursorPosition(#filtered) end
    end
    local xField = Lib.CreateInputField(remote, addonName, "X", "0", {
        width = 96, inputWidth = 64,
        onEnter = function() remote:ApplyXY() end,
    })
    xField:SetPoint("TOPLEFT", remote, "TOPLEFT", PAD, row(0))
    local yField = Lib.CreateInputField(remote, addonName, "Y", "0", {
        width = 96, inputWidth = 64,
        onEnter = function() remote:ApplyXY() end,
    })
    yField:SetPoint("LEFT", xField, "RIGHT", 6, 0)
    for _, f in ipairs({ xField, yField }) do
        if f.editBox and f.editBox.HookScript then f.editBox:HookScript("OnTextChanged", SignedNumberFilter) end
    end
    remote.xField, remote.yField = xField, yField
    function remote:ApplyXY()
        local nx = tonumber(xField.editBox and xField.editBox:GetText() or "")
        local ny = tonumber(yField.editBox and yField.editBox:GetText() or "")
        if nx and ny and opts.onApplyXY then opts.onApplyXY(nx, ny) end
    end

    local function nudge(dx, dy)
        if not opts.onNudge then return end
        local step = IsShiftKeyDown() and SPEC.nudgeShift or SPEC.nudge
        opts.onNudge(dx * step, dy * step)
    end
    local arrows = CreateFrame("Frame", nil, remote)
    arrows:SetSize(84, 56)
    arrows:SetPoint("TOPRIGHT", remote, "TOPRIGHT", -PAD, cy + 2)
    local function arrow(glyph, dx, dy, point, ax, ay)
        local b = Lib.CreateButton(arrows, addonName, glyph, function() nudge(dx, dy) end, { width = 26, height = 26 })
        b:SetPoint(point, arrows, point, ax, ay)
        return b
    end
    arrow("\226\150\178", 0, 1, "TOP", 0, 0)        -- ▲
    arrow("\226\151\128", -1, 0, "LEFT", 0, -14)   -- ◀
    arrow("\226\150\182", 1, 0, "RIGHT", 0, -14)   -- ▶
    arrow("\226\150\188", 0, -1, "BOTTOM", 0, 0)   -- ▼
    row(60)

    -- 격자 / 스냅
    local grid, snap = opts.grid, opts.snap
    if grid or snap then
        local hdr = Lib.CreateSectionHeader(remote, addonName, "격자 · 스냅", { showLine = true })
        hdr:SetPoint("TOPLEFT", remote, "TOPLEFT", PAD, row(26))
        hdr:SetPoint("RIGHT", remote, "RIGHT", -PAD, 0)
    end
    if grid then
        local cb = Lib.CreateCheckbox(remote, addonName, "격자 표시", grid.enabled ~= false, {
            onChange = function(v) if grid.onToggle then grid.onToggle(v) end end,
        })
        cb:SetPoint("TOPLEFT", remote, "TOPLEFT", PAD, row(0))
        remote.gridCheck = cb
        local spacing = grid.spacing or SPEC.gridSpacing
        local btn
        btn = Lib.CreateButton(remote, addonName, ("간격 %d"):format(spacing), function()
            local choices = SPEC.gridChoices
            local idx = 1
            for i, v in ipairs(choices) do if v == spacing then idx = i end end
            spacing = choices[idx % #choices + 1]
            SetButtonText(btn, ("간격 %d"):format(spacing))
            if grid.onSpacing then grid.onSpacing(spacing) end
        end, { width = 88, height = 24 })
        btn:SetPoint("TOPRIGHT", remote, "TOPRIGHT", -PAD, cy + 3)
        remote.gridSpacingBtn = btn
        function remote:SetGridState(on, sp)
            if on ~= nil and cb.SetChecked then cb:SetChecked(on) end
            if sp then spacing = sp; SetButtonText(btn, ("간격 %d"):format(sp)) end
        end
        row(28)
    end
    if snap then
        local function check(label, key, px, py)
            local cb = Lib.CreateCheckbox(remote, addonName, label, snap[key] ~= false, {
                onChange = function(v) if snap.onChange then snap.onChange(key, v) end end,
            })
            cb:SetPoint("TOPLEFT", remote, "TOPLEFT", px, py)
            return cb
        end
        local y0 = row(0)
        check("스냅", "enabled", PAD, y0)
        check("중앙", "center", PAD + 70, y0)
        check("격자", "grid", PAD + 140, y0)
        if not snap.noFrames then check("프레임", "frames", PAD + 210, y0) end -- 맞출 다른 프레임이 없는 애드온은 숨긴다
        row(28)
    end

    -- 애드온 전용 구역
    if opts.extra then
        local h = opts.extra(remote, cy) or 0
        row(h)
    end

    -- 하단 버튼
    local buttons = {}
    local function add(label, fn, w) buttons[#buttons + 1] = { label, fn, w } end
    if opts.onReset then add("초기화", opts.onReset, 60) end
    if opts.onUndo then add("실행 취소", opts.onUndo, 76) end
    if opts.onRedo then add("다시 실행", opts.onRedo, 76) end
    add("완료", function() if opts.onDone then opts.onDone() end end, 60)
    local y0 = row(32)
    -- [STYLE] 버튼 묶음이 좌우 여백 안에 들어오도록 줄이고 창 가운데 정렬한다.
    local gap, totalWidth = 6, 0
    for _, def in ipairs(buttons) do totalWidth = totalWidth + def[3] end
    local gapsWidth = gap * (#buttons - 1)
    local widthScale = math.min(1, (width - PAD * 2 - gapsWidth) / totalWidth)
    local groupWidth = gapsWidth
    for _, def in ipairs(buttons) do
        def[3] = math.floor(def[3] * widthScale)
        groupWidth = groupWidth + def[3]
    end
    local rx = -(width - groupWidth) / 2
    remote.buttons = {}
    for i = #buttons, 1, -1 do
        local def = buttons[i]
        local b = Lib.CreateButton(remote, addonName, def[1], def[2], { width = def[3], height = 26 })
        b:SetPoint("TOPRIGHT", remote, "TOPRIGHT", rx, y0)
        rx = rx - def[3] - gap
        remote.buttons[def[1]] = b
    end
    remote:SetHeight(-cy + PAD)

    function remote:SetUndoState(canUndo, canRedo)
        local uBtn, rBtn = self.buttons["실행 취소"], self.buttons["다시 실행"]
        if uBtn then SetButtonEnabled(uBtn, canUndo and true or false) end
        if rBtn then SetButtonEnabled(rBtn, canRedo and true or false) end
    end

    --- info = { name=, anchor=, x=, y=, w=, h= } 또는 nil
    function remote:SetSelection(info)
        if not info then
            self.nameText:SetText("선택된 프레임 없음")
            self.infoText:SetText("")
            if xField.editBox then xField.editBox:SetText("") end
            if yField.editBox then yField.editBox:SetText("") end
            return
        end
        self.nameText:SetText(info.name or "")
        local parts = {}
        if info.anchor then parts[#parts + 1] = info.anchor end
        if info.w and info.h then parts[#parts + 1] = ("%d\195\151%d"):format(info.w + 0.5, info.h + 0.5) end
        self.infoText:SetText(table.concat(parts, "  \194\183  "))
        if xField.editBox and not xField.editBox:HasFocus() then xField.editBox:SetText(tostring(math.floor((info.x or 0) + 0.5))) end
        if yField.editBox and not yField.editBox:HasFocus() then yField.editBox:SetText(tostring(math.floor((info.y or 0) + 0.5))) end
    end

    -- 키보드: Esc 종료, 방향키 넛지(Shift ×10), Ctrl+Z/Y
    remote:EnableKeyboard(true)
    remote:SetScript("OnKeyDown", function(self, key)
        local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focused then self:SetPropagateKeyboardInput(true); return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            if opts.onEscape then opts.onEscape() elseif opts.onDone then opts.onDone() end
        elseif key == "UP" then self:SetPropagateKeyboardInput(false); nudge(0, 1)
        elseif key == "DOWN" then self:SetPropagateKeyboardInput(false); nudge(0, -1)
        elseif key == "LEFT" then self:SetPropagateKeyboardInput(false); nudge(-1, 0)
        elseif key == "RIGHT" then self:SetPropagateKeyboardInput(false); nudge(1, 0)
        elseif key == "Z" and IsControlKeyDown() and opts.onUndo then self:SetPropagateKeyboardInput(false); opts.onUndo()
        elseif key == "Y" and IsControlKeyDown() and opts.onRedo then self:SetPropagateKeyboardInput(false); opts.onRedo()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- 열기/닫기 모션은 설정창과 같은 프리셋(Show/HideAnimated는 실제로 열고 닫는다).
    -- 제목줄 X는 창을 직접 닫지 않고 onDone으로 보내 애드온이 편집 모드를 끝내게 한다.
    if Motion and Motion.BindPanel then Motion.BindPanel(remote) end
    if bar.closeBtn then
        bar.closeBtn:SetScript("OnClick", function() if opts.onDone then opts.onDone() end end)
    end
    remote:Hide()
    return remote
end
