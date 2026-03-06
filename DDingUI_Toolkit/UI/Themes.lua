--[[
    DDingToolKit - Themes
    다크 테마 색상/스타일 정의
]]

local addonName, ns = ...

-- UI 네임스페이스
ns.UI = ns.UI or {}

-- 다크 테마 색상 팔레트
ns.UI.colors = {
    -- 배경
    background = { 0.07, 0.07, 0.07, 0.95 },
    panel = { 0.12, 0.12, 0.12, 0.95 },
    panelLight = { 0.15, 0.15, 0.15, 0.95 },

    -- 테두리
    border = { 0.2, 0.2, 0.2, 1 },
    borderHover = { 0.4, 0.4, 0.4, 1 },
    borderFocus = { 0.0, 0.44, 0.87, 1 },

    -- 강조색
    accent = { 0.0, 0.44, 0.87, 1 },        -- 파란색
    accentHover = { 0.1, 0.54, 0.97, 1 },
    accentDark = { 0.0, 0.34, 0.67, 1 },

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
    selected = { 0.0, 0.44, 0.87, 0.3 },
    hover = { 1, 1, 1, 0.05 },

    -- 탭
    tabActive = { 0.15, 0.15, 0.15, 1 },
    tabInactive = { 0.1, 0.1, 0.1, 1 },
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
