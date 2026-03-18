------------------------------------------------------
-- DDingUI_StyleLib :: DualRow
-- 2-column layout system for option panels (EllesmereUI DualRow pattern)
-- 한 행에 좌/우 위젯 2개를 선언적으로 배치
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local C      = Lib.Colors
local F      = Lib.Font
local T      = Lib.Tokens
local PP     = Lib.PP
local lerp   = T.Lerp
local SOLID  = Lib.Textures.flat

------------------------------------------------------
-- Internal helpers
------------------------------------------------------
local function u(tbl) return unpack(tbl) end

local function SolidBG(parent, r, g, b, a, layer)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(r, g, b, a)
    if PP then PP.DisablePixelSnap(tex) end
    return tex
end

local function MakeLabel(parent, text, size, color)
    size = size or Lib:GetFontSize("normal")
    color = color or T.TEXT_NORMAL
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Lib:GetFont("primary"), size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    if text then fs:SetText(text) end
    return fs
end

--- 교대 행 배경 (EllesmereUI RowBg 패턴)
local _globalRowCount = 0
local function RowBg(frame, parent)
    _globalRowCount = _globalRowCount + 1
    local alpha = T.RowBgAlpha(_globalRowCount)
    local bg = SolidBG(frame, 1, 1, 1, alpha, "BACKGROUND")
    bg:SetAllPoints()
    return bg
end

--- DualRow용 행 카운터 리셋 (새 페이지 시작 시)
function Lib.ResetDualRowCounter()
    _globalRowCount = 0
end

------------------------------------------------------
-- BuildSliderHalf — 슬라이더 위젯 (DualRow 한 쪽)
------------------------------------------------------
local function BuildSliderHalf(region, cfg, accent, frameLevel)
    local SL = T.SL
    local PAD = T.DUALROW_PAD

    -- Track
    local trackW = cfg.trackWidth or 160
    local trackFrame = CreateFrame("Frame", nil, region)
    trackFrame:SetSize(trackW, SL.TRACK_H)
    trackFrame:SetPoint("RIGHT", region, "RIGHT", -(PAD + 52 + 12), 0) -- 52=valBox, 12=gap
    local trackBg = SolidBG(trackFrame, SL.TRACK_R, SL.TRACK_G, SL.TRACK_B, SL.TRACK_A)

    -- Thumb (드래그 가능)
    local thumb = CreateFrame("Button", nil, trackFrame)
    thumb:SetSize(SL.THUMB_SZ, SL.THUMB_SZ)
    thumb:SetFrameLevel((frameLevel or region:GetFrameLevel()) + 3)
    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(accent[1], accent[2], accent[3], 1)
    if PP then PP.DisablePixelSnap(thumbTex) end

    -- Fill (accent colored, left portion of track)
    local fill = trackFrame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(accent[1], accent[2], accent[3], SL.FILL_A)
    if PP then PP.DisablePixelSnap(fill) end

    -- Value box (editable)
    local valBox = CreateFrame("EditBox", nil, region, "BackdropTemplate")
    valBox:SetSize(48, 22)
    valBox:SetPoint("RIGHT", region, "RIGHT", -PAD, 0)
    valBox:SetFont(Lib:GetFont("primary"), Lib:GetFontSize("small"), "")
    valBox:SetTextColor(u(T.TEXT_HIGHLIGHT))
    valBox:SetJustifyH("CENTER")
    valBox:SetAutoFocus(false)
    valBox:SetFrameLevel((frameLevel or region:GetFrameLevel()) + 2)
    valBox:SetBackdrop({ bgFile=SOLID, edgeFile=SOLID, edgeSize=1 })
    valBox:SetBackdropColor(SL.INPUT_R, SL.INPUT_G, SL.INPUT_B, SL.INPUT_A)
    valBox:SetBackdropBorderColor(1, 1, 1, SL.INPUT_BRD_A)

    -- Decimals detection
    local step = cfg.step or 1
    local decimals = step < 1 and math.max(1, math.ceil(-math.log10(step))) or 0
    local fmtStr = "%." .. decimals .. "f"
    local mn, mx = cfg.min or 0, cfg.max or 100

    -- Position update
    local function UpdateThumbPos(v)
        local pct = (v - mn) / math.max(mx - mn, 0.001)
        pct = math.max(0, math.min(1, pct))
        local pixW = trackFrame:GetWidth() - SL.THUMB_SZ
        local offX = pct * pixW
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", trackFrame, "LEFT", offX, 0)
        fill:SetWidth(math.max(1, offX + SL.THUMB_SZ * 0.5))
    end

    -- Initial value
    local curValue = cfg.getValue and cfg.getValue() or (cfg.default or mn)
    curValue = math.max(mn, math.min(mx, curValue))
    valBox:SetText(string.format(fmtStr, curValue))

    -- Thumb drag
    local isDragging = false
    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function(self)
        isDragging = true
    end)
    thumb:SetScript("OnDragStop", function(self)
        isDragging = false
    end)
    thumb:SetScript("OnUpdate", function(self)
        if not isDragging then return end
        local cx = select(1, GetCursorPosition()) / (UIParent:GetEffectiveScale())
        local left = trackFrame:GetLeft()
        local right = trackFrame:GetRight()
        if not left or not right then return end
        local pct = (cx - left) / (right - left)
        pct = math.max(0, math.min(1, pct))
        local raw = mn + pct * (mx - mn)
        -- snap to step
        raw = math.floor(raw / step + 0.5) * step
        raw = math.max(mn, math.min(mx, raw))
        raw = tonumber(string.format(fmtStr, raw))
        if raw ~= curValue then
            curValue = raw
            valBox:SetText(string.format(fmtStr, raw))
            UpdateThumbPos(raw)
            if cfg.setValue then cfg.setValue(raw) end
        end
    end)

    -- Mouse wheel on track
    trackFrame:EnableMouseWheel(true)
    trackFrame:SetScript("OnMouseWheel", function(self, delta)
        local newVal = math.max(mn, math.min(mx, curValue + delta * step))
        newVal = tonumber(string.format(fmtStr, newVal))
        if newVal ~= curValue then
            curValue = newVal
            valBox:SetText(string.format(fmtStr, newVal))
            UpdateThumbPos(newVal)
            if cfg.setValue then cfg.setValue(newVal) end
        end
    end)

    -- ValBox editing
    valBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then
            v = math.max(mn, math.min(mx, v))
            v = tonumber(string.format(fmtStr, v))
            curValue = v
            UpdateThumbPos(v)
            if cfg.setValue then cfg.setValue(v) end
        end
        self:ClearFocus()
    end)
    valBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Deferred initial layout (트랙이 사이즈 잡힌 후)
    trackFrame:SetScript("OnSizeChanged", function()
        UpdateThumbPos(curValue)
    end)
    C_Timer.After(0, function()
        if trackFrame:GetWidth() > 0 then
            UpdateThumbPos(curValue)
        end
    end)

    return trackFrame, valBox, fill, thumb
end

------------------------------------------------------
-- BuildToggleHalf — 토글 위젯 (DualRow 한 쪽)
------------------------------------------------------
local function BuildToggleHalf(region, cfg, accent, frameLevel)
    local TG = T.TG
    local PAD = T.DUALROW_PAD

    local toggle = CreateFrame("Button", nil, region)
    toggle:SetSize(TG.TRACK_W, TG.TRACK_H)
    toggle:SetPoint("RIGHT", region, "RIGHT", -PAD, 0)
    toggle:SetFrameLevel((frameLevel or region:GetFrameLevel()) + 2)

    local tBg = SolidBG(toggle, TG.OFF_R, TG.OFF_G, TG.OFF_B, TG.OFF_A)
    local knob = toggle:CreateTexture(nil, "ARTWORK")
    if PP then PP.DisablePixelSnap(knob) end
    knob:SetColorTexture(TG.KNOB_OFF_R, TG.KNOB_OFF_G, TG.KNOB_OFF_B, TG.KNOB_OFF_A)
    knob:SetSize(TG.KNOB_SZ, TG.KNOB_SZ)
    knob:SetPoint("LEFT", toggle, "LEFT", TG.KNOB_PAD, 0)

    local POS_OFF = TG.KNOB_PAD
    local POS_ON  = TG.TRACK_W - TG.KNOB_SZ - TG.KNOB_PAD

    local isOn = cfg.getValue and cfg.getValue() or false
    local animProgress = isOn and 1 or 0
    local animTarget   = animProgress

    local function ApplyVisual(p)
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", toggle, "LEFT", math.floor(lerp(POS_OFF, POS_ON, p) + 0.5), 0)
        tBg:SetColorTexture(
            lerp(TG.OFF_R, accent[1], p),
            lerp(TG.OFF_G, accent[2], p),
            lerp(TG.OFF_B, accent[3], p),
            lerp(TG.OFF_A, TG.ON_A, p))
        knob:SetColorTexture(
            lerp(TG.KNOB_OFF_R, TG.KNOB_ON_R, p),
            lerp(TG.KNOB_OFF_G, TG.KNOB_ON_G, p),
            lerp(TG.KNOB_OFF_B, TG.KNOB_ON_B, p),
            lerp(TG.KNOB_OFF_A, TG.KNOB_ON_A, p))
    end
    ApplyVisual(animProgress)

    local ANIM_DUR = TG.ANIM_DUR
    local function AnimOnUpdate(self, elapsed)
        local dir = (animTarget == 1) and 1 or -1
        animProgress = animProgress + dir * (elapsed / ANIM_DUR)
        if (dir == 1 and animProgress >= 1) or (dir == -1 and animProgress <= 0) then
            animProgress = animTarget
            self:SetScript("OnUpdate", nil)
        end
        ApplyVisual(animProgress)
    end

    toggle:SetScript("OnClick", function()
        local v = not (cfg.getValue and cfg.getValue())
        if cfg.setValue then cfg.setValue(v) end
        animTarget = v and 1 or 0
        toggle:SetScript("OnUpdate", AnimOnUpdate)
    end)

    -- Expose for external refresh
    toggle._applyVisual = ApplyVisual
    toggle._setAnimState = function(v)
        animProgress = v and 1 or 0
        animTarget = animProgress
        ApplyVisual(animProgress)
        toggle:SetScript("OnUpdate", nil)
    end

    return toggle
end

------------------------------------------------------
-- BuildDropdownHalf — 드롭다운 위젯 (DualRow 한 쪽)
------------------------------------------------------
local function BuildDropdownHalf(region, cfg, accent, frameLevel)
    local DD = T.DD
    local PAD = T.DUALROW_PAD
    local ddW = cfg.width or 170

    local ddBtn = CreateFrame("Button", nil, region, "BackdropTemplate")
    ddBtn:SetSize(ddW, 24)
    ddBtn:SetPoint("RIGHT", region, "RIGHT", -PAD, 0)
    ddBtn:SetFrameLevel((frameLevel or region:GetFrameLevel()) + 2)
    ddBtn:SetBackdrop({ bgFile=SOLID, edgeFile=SOLID, edgeSize=1 })
    ddBtn:SetBackdropColor(DD.BG_R, DD.BG_G, DD.BG_B, DD.BG_A)
    ddBtn:SetBackdropBorderColor(1, 1, 1, DD.BRD_A)

    -- Label
    local ddLbl = MakeLabel(ddBtn, nil, Lib:GetFontSize("normal"))
    ddLbl:SetTextColor(1, 1, 1, DD.TXT_A)
    ddLbl:SetPoint("LEFT", 8, 0)
    ddLbl:SetPoint("RIGHT", -20, 0)
    ddLbl:SetJustifyH("LEFT")
    ddLbl:SetWordWrap(false)

    -- Arrow
    local arrow = MakeLabel(ddBtn, "▼", Lib:GetFontSize("small"), T.TEXT_DIM)
    arrow:SetPoint("RIGHT", -6, 0)

    -- Hover
    ddBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(DD.BG_R, DD.BG_G, DD.BG_B, DD.BG_HA)
        self:SetBackdropBorderColor(1, 1, 1, DD.BRD_HA)
        ddLbl:SetTextColor(1, 1, 1, DD.TXT_HA)
    end)
    ddBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(DD.BG_R, DD.BG_G, DD.BG_B, DD.BG_A)
        self:SetBackdropBorderColor(1, 1, 1, DD.BRD_A)
        ddLbl:SetTextColor(1, 1, 1, DD.TXT_A)
    end)

    -- Build options list
    local values = cfg.values or {}
    local order  = cfg.order
    -- Normalize values: support both ordered list and map
    local displayItems = {}  -- { {key=, text=}, ... }
    if order then
        for _, k in ipairs(order) do
            local v = values[k]
            local txt = type(v) == "table" and v.text or tostring(v or k)
            displayItems[#displayItems + 1] = { key = k, text = txt }
        end
    else
        -- values is an array of { text, value } or flat strings
        for i, o in ipairs(values) do
            if type(o) == "table" then
                displayItems[#displayItems + 1] = { key = o.value or o[2] or o[1], text = o.text or o[1] }
            else
                displayItems[#displayItems + 1] = { key = o, text = tostring(o) }
            end
        end
    end

    -- Resolve label from current value
    local function ResolveLabel(curKey)
        for _, item in ipairs(displayItems) do
            if item.key == curKey then return item.text end
        end
        return tostring(curKey or "")
    end

    -- Initial label
    local curVal = cfg.getValue and cfg.getValue()
    ddLbl:SetText(ResolveLabel(curVal))

    -- Dropdown list (popup)
    local list = CreateFrame("Frame", nil, ddBtn, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -1)
    list:SetWidth(ddW)
    local maxVisible = cfg.maxVisible or 10
    local totalH = math.min(#displayItems, maxVisible) * DD.ITEM_H + 2
    list:SetHeight(totalH)
    list:SetBackdrop({ bgFile=SOLID, edgeFile=SOLID, edgeSize=1 })
    list:SetBackdropColor(DD.BG_R, DD.BG_G, DD.BG_B, 0.98)
    list:SetBackdropBorderColor(1, 1, 1, DD.BRD_A)
    list:Hide()

    -- Scroll support
    local needsScroll = #displayItems > maxVisible
    local rowParent = list
    if needsScroll then
        local listScroll = CreateFrame("ScrollFrame", nil, list)
        listScroll:SetPoint("TOPLEFT", 1, -1)
        listScroll:SetPoint("BOTTOMRIGHT", -1, 1)
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetWidth(ddW - 2)
        listChild:SetHeight(#displayItems * DD.ITEM_H)
        listScroll:SetScrollChild(listChild)
        listScroll:EnableMouseWheel(true)
        listScroll:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local maxS = math.max(0, listChild:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * DD.ITEM_H)))
        end)
        rowParent = listChild
    end

    -- Click-away catcher
    local catcher = CreateFrame("Button", nil, list)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(math.max(0, list:GetFrameLevel() - 1))
    catcher:SetAllPoints(UIParent)
    catcher:SetScript("OnClick", function() list:Hide(); catcher:Hide() end)
    catcher:EnableMouseWheel(true)
    catcher:SetScript("OnMouseWheel", function() list:Hide(); catcher:Hide() end)
    catcher:Hide()

    -- Rows
    for i, item in ipairs(displayItems) do
        local row = CreateFrame("Button", nil, rowParent)
        row:SetSize(ddW - 2, DD.ITEM_H)
        row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", needsScroll and 0 or 1,
            -(needsScroll and ((i-1) * DD.ITEM_H) or (1 + (i-1) * DD.ITEM_H)))

        local rowBG = row:CreateTexture(nil, "BACKGROUND")
        rowBG:SetAllPoints()
        rowBG:SetColorTexture(0, 0, 0, 0)
        local rowText = MakeLabel(row, item.text, Lib:GetFontSize("normal"))
        rowText:SetPoint("LEFT", 8, 0)

        row:SetScript("OnEnter", function() rowBG:SetColorTexture(1, 1, 1, DD.ITEM_HL_A) end)
        row:SetScript("OnLeave", function() rowBG:SetColorTexture(0, 0, 0, 0) end)
        row:SetScript("OnClick", function()
            if cfg.setValue then cfg.setValue(item.key) end
            ddLbl:SetText(item.text)
            list:Hide(); catcher:Hide()
        end)
    end

    -- Toggle list
    ddBtn:SetScript("OnClick", function()
        if list:IsShown() then
            list:Hide(); catcher:Hide()
        else
            list:Show(); catcher:Show()
        end
    end)

    -- Expose for refresh
    ddBtn._ddLbl = ddLbl
    ddBtn._resolveLabel = ResolveLabel
    ddBtn._ddMenu = list

    return ddBtn, ddLbl
end

------------------------------------------------------
-- CreateDualRow — 핵심 레이아웃 시스템
------------------------------------------------------
--- 2-column 행 하나를 생성합니다. 좌/우에 각각 위젯을 배치합니다.
--- rightCfg가 nil이면 leftCfg가 전체 행 너비를 사용합니다.
---
--- cfg 형식:
---   { type = "slider"|"dropdown"|"toggle",
---     text = "라벨 텍스트",
---     getValue = function() return currentValue end,
---     setValue = function(v) db.someKey = v end,
---     min = 0, max = 100, step = 1,     -- slider용
---     values = {}, order = {},           -- dropdown용
---     disabled = function() return bool end,  -- 비활성 조건 (선택)
---     tooltip = "설명",                  -- 호버 툴팁 (선택)
---   }
---
--- @param parent Frame        부모 프레임 (contentChild 등)
--- @param addonName string    액센트 프리셋 키
--- @param yOffset number      부모 TOPLEFT 기준 Y 오프셋 (음수)
--- @param leftCfg table       좌측 위젯 설정
--- @param rightCfg table|nil  우측 위젯 설정 (nil → 단일 컬럼)
--- @return Frame row          행 프레임
--- @return number totalHeight 이 행이 차지하는 총 높이 (다음 yOffset 계산용)
function Lib.CreateDualRow(parent, addonName, yOffset, leftCfg, rightCfg)
    local ROW_H = T.DUALROW_H
    local CONTENT_PAD = T.CONTENT_PAD
    local SIDE_PAD = T.DUALROW_PAD

    local accent = Lib.GetAccent(addonName)

    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    if totalW <= 0 then totalW = 400 end  -- fallback
    frame:SetSize(totalW, ROW_H)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    -- Alternating row background
    RowBg(frame, parent)

    -- Half regions
    local fullWidth = not rightCfg
    local halfW = math.floor(totalW / 2)

    local leftRegion = CreateFrame("Frame", nil, frame)
    leftRegion:SetSize(fullWidth and totalW or halfW, ROW_H)
    leftRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local rightRegion
    if rightCfg then
        rightRegion = CreateFrame("Frame", nil, frame)
        rightRegion:SetSize(halfW, ROW_H)
        rightRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    end

    --- 한쪽 영역에 위젯 배치
    local function BuildHalf(region, cfg)
        if not cfg then return end
        local t = cfg.type

        -- Label (모든 타입 공통)
        local label = MakeLabel(region, cfg.text, Lib:GetFontSize("normal"), T.TEXT_NORMAL)
        label:SetPoint("LEFT", region, "LEFT", SIDE_PAD, 0)
        region._label = label

        -- Disabled 상태 지원
        local controlFrame
        local function ApplyDisabledState()
            if not cfg.disabled then return end
            local off = cfg.disabled()
            label:SetAlpha(off and 0.3 or 1)
            if controlFrame then
                controlFrame:EnableMouse(not off)
                controlFrame:SetAlpha(off and 0.3 or 1)
            end
        end

        if t == "slider" then
            local trackFrame, valBox = BuildSliderHalf(region, cfg, accent, frame:GetFrameLevel())
            controlFrame = trackFrame
            -- Register refresh
            if Lib.WidgetRefresh then
                local WR = Lib.WidgetRefresh
                local ctx = WR._lastContext
                if ctx then
                    ctx:Register(function()
                        if cfg.getValue then
                            local v = cfg.getValue()
                            local step = cfg.step or 1
                            local decimals = step < 1 and math.max(1, math.ceil(-math.log10(step))) or 0
                            valBox:SetText(string.format("%." .. decimals .. "f", v))
                        end
                        ApplyDisabledState()
                    end)
                end
            end

        elseif t == "dropdown" then
            local ddBtn, ddLbl = BuildDropdownHalf(region, cfg, accent, frame:GetFrameLevel())
            controlFrame = ddBtn
            if Lib.WidgetRefresh then
                local WR = Lib.WidgetRefresh
                local ctx = WR._lastContext
                if ctx then
                    ctx:Register(function()
                        if cfg.getValue and ddBtn._resolveLabel then
                            ddLbl:SetText(ddBtn._resolveLabel(cfg.getValue()))
                        end
                        ApplyDisabledState()
                    end)
                end
            end

        elseif t == "toggle" then
            local toggle = BuildToggleHalf(region, cfg, accent, frame:GetFrameLevel())
            controlFrame = toggle
            if Lib.WidgetRefresh then
                local WR = Lib.WidgetRefresh
                local ctx = WR._lastContext
                if ctx then
                    ctx:Register(function()
                        if cfg.getValue and toggle._setAnimState then
                            toggle._setAnimState(cfg.getValue())
                        end
                        ApplyDisabledState()
                    end)
                end
            end
        end

        -- 초기 disabled 적용
        ApplyDisabledState()
    end

    BuildHalf(leftRegion, leftCfg)
    if rightCfg and rightRegion then
        BuildHalf(rightRegion, rightCfg)
    end

    return frame, ROW_H
end

------------------------------------------------------
-- CreateSectionHeaderRow — 섹션 헤더 (DualRow 시스템용)
------------------------------------------------------
--- 옵션 패널 내 섹션 제목 행.
--- EllesmereUI의 대문자 좌안 정렬 + 구분선 패턴.
--- @param parent Frame
--- @param addonName string
--- @param text string       섹션 제목 (자동 대문자 변환)
--- @param yOffset number    부모 TOPLEFT 기준 Y 오프셋
--- @param opts table|nil    { height, isFirst, noUpperCase }
--- @return Frame row
--- @return number totalHeight
function Lib.CreateSectionHeaderRow(parent, addonName, text, yOffset, opts)
    opts = opts or {}
    local accent = Lib.GetAccent(addonName)
    local CONTENT_PAD = T.CONTENT_PAD
    local ROW_H = opts.height or 36
    local displayText = (opts.noUpperCase) and text or string.upper(text)

    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    if totalW <= 0 then totalW = 400 end
    frame:SetSize(totalW, ROW_H)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    -- 섹션 제목
    local label = MakeLabel(frame, displayText, Lib:GetFontSize("section"))
    label:SetTextColor(accent[1], accent[2], accent[3], 0.9)
    label:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 8)

    -- 구분선
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    sep:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    sep:SetColorTexture(accent[1], accent[2], accent[3], 0.15)
    if PP then PP.DisablePixelSnap(sep) end

    frame._label = label
    frame._sep = sep
    return frame, ROW_H
end
