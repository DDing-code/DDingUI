--[[
    DDingToolKit - Themes
    다크 테마 색상/스타일 정의
]]

local addonName, ns = ...
local SL = _G.DDingUI_StyleLib
local StyleColors = SL and SL.Colors

-- UI 네임스페이스
ns.UI = ns.UI or {}

-- 다크 테마 색상 팔레트
ns.UI.colors = {
    -- 배경
    background = (StyleColors and StyleColors.bg and StyleColors.bg.main) or { 0.10, 0.10, 0.10, 0.95 },
    panel = (StyleColors and StyleColors.bg and StyleColors.bg.sidebar) or { 0.08, 0.08, 0.08, 0.95 },
    panelLight = (StyleColors and StyleColors.bg and StyleColors.bg.titlebar) or { 0.12, 0.12, 0.12, 0.98 },

    -- 테두리
    border = (StyleColors and StyleColors.border and StyleColors.border.default) or { 0.25, 0.25, 0.25, 0.50 },
    borderHover = (StyleColors and StyleColors.border and StyleColors.border.active) or { 0.40, 0.40, 0.40, 0.70 },
    borderFocus = { 0.16, 0.58, 0.68, 0.85 },

    -- 강조색
    accent = { 0.16, 0.58, 0.68, 0.85 },
    accentHover = { 0.20, 0.68, 0.78, 0.92 },
    accentDark = { 0.12, 0.42, 0.50, 0.90 },

    -- 상태 색상
    success = { 0.2, 0.8, 0.2, 1 },         -- 녹색
    warning = { 1.0, 0.82, 0.0, 1 },        -- 골드
    error = { 0.8, 0.2, 0.2, 1 },           -- 빨강
    info = { 0.4, 0.7, 1.0, 1 },            -- 하늘색

    -- 텍스트
    text = { 0.9, 0.9, 0.9, 1 },
    textDim = { 0.6, 0.6, 0.6, 1 },
    textDisabled = { 0.4, 0.4, 0.4, 1 },
    textHighlight = { 1.0, 1.0, 1.0, 1 },

    -- 선택/호버
    selected = { 0.10, 0.14, 0.15, 0.70 },
    hover = { 1, 1, 1, 0.05 },

    -- 탭
    tabActive = (StyleColors and StyleColors.bg and StyleColors.bg.selected) or { 0.18, 0.18, 0.22, 0.80 },
    tabInactive = (StyleColors and StyleColors.bg and StyleColors.bg.sidebar) or { 0.08, 0.08, 0.08, 0.95 },
}

-- Operational popups use the same neutral surfaces as the main workspace.
-- Cyan is reserved for selected states and small accents.
ns.UI.popupColors = {
    background = (StyleColors and StyleColors.bg and StyleColors.bg.main) or { 0.10, 0.10, 0.10, 0.985 },
    header = (StyleColors and StyleColors.bg and StyleColors.bg.titlebar) or { 0.12, 0.12, 0.12, 1 },
    panel = { 0.075, 0.075, 0.08, 0.97 },
    panelAlt = { 0.088, 0.088, 0.095, 0.96 },
    control = (StyleColors and StyleColors.bg and StyleColors.bg.widget) or { 0.06, 0.06, 0.06, 0.94 },
    input = { 0.045, 0.045, 0.05, 1 },
    hover = { 0.14, 0.14, 0.15, 0.96 },
    selected = { 0.10, 0.14, 0.15, 0.96 },
    footer = { 0.075, 0.075, 0.08, 0.98 },
    border = { 0.30, 0.30, 0.32, 0.82 },
    borderSoft = (StyleColors and StyleColors.border and StyleColors.border.default) or { 0.25, 0.25, 0.25, 0.50 },
    separator = (StyleColors and StyleColors.border and StyleColors.border.separator) or { 0.20, 0.20, 0.20, 0.40 },
    accent = { 0.16, 0.58, 0.68, 0.80 },
    accentStrong = { 0.16, 0.68, 0.80, 0.92 },
    accentText = { 0.42, 0.76, 0.82, 1 },
    primary = { 0.09, 0.18, 0.20, 0.98 },
    primaryHover = { 0.11, 0.23, 0.26, 1 },
    primaryBorder = { 0.16, 0.50, 0.57, 0.84 },
    primaryBorderHover = { 0.20, 0.62, 0.70, 0.94 },
    text = (StyleColors and StyleColors.text and StyleColors.text.normal) or { 0.85, 0.85, 0.85, 1 },
    textBright = (StyleColors and StyleColors.text and StyleColors.text.highlight) or { 1, 1, 1, 1 },
    textDim = (StyleColors and StyleColors.text and StyleColors.text.dim) or { 0.60, 0.60, 0.60, 1 },
}

-- 공통 백드롭
ns.UI.backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- 둥근 모서리 백드롭 (있으면)
ns.UI.backdropRounded = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- 폰트 크기
ns.UI.fonts = {
    small = 10,
    normal = 12,
    large = 14,
    header = 16,
    title = 18,
}

-- 간격/패딩
ns.UI.spacing = {
    small = 5,
    normal = 10,
    large = 15,
    section = 20,
}

-- 색상 유틸리티 함수
function ns.UI:GetColor(name)
    return self.colors[name] or self.colors.text
end

function ns.UI:GetColorRGB(name)
    local c = self:GetColor(name)
    return c[1], c[2], c[3]
end

function ns.UI:GetColorRGBA(name)
    local c = self:GetColor(name)
    return c[1], c[2], c[3], c[4] or 1
end

-- 색상 밝기 조절
function ns.UI:Lighten(color, amount)
    amount = amount or 0.1
    return {
        math.min(1, color[1] + amount),
        math.min(1, color[2] + amount),
        math.min(1, color[3] + amount),
        color[4] or 1
    }
end

function ns.UI:Darken(color, amount)
    amount = amount or 0.1
    return {
        math.max(0, color[1] - amount),
        math.max(0, color[2] - amount),
        math.max(0, color[3] - amount),
        color[4] or 1
    }
end
