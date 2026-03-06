------------------------------------------------------
-- DDingUI_StyleLib :: ColorNames
-- 이름 기반 색상 조회 (inspired by AbstractFramework)
-- 기존 Colors.lua의 테이블 구조와 호환되며 이름으로 빠르게 접근
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local format = string.format

---------------------------------------------------------------------
-- 색상 레지스트리 (이름 → {r,g,b,a})
---------------------------------------------------------------------
local colorRegistry = {
    -- ═══════════════════ 배경 ═══════════════════
    background      = { 0.10, 0.10, 0.10, 0.95 },
    sidebar         = { 0.08, 0.08, 0.08, 0.95 },
    input           = { 0.06, 0.06, 0.06, 0.80 },
    widget          = { 0.06, 0.06, 0.06, 0.80 },
    hover           = { 0.20, 0.20, 0.20, 0.60 },
    selected        = { 0.18, 0.18, 0.22, 0.80 },
    titlebar        = { 0.12, 0.12, 0.12, 0.98 },
    header          = { 0.15, 0.15, 0.18, 1.00 },

    -- ═══════════════════ 텍스트 ═══════════════════
    white           = { 1.00, 1.00, 1.00, 1.00 },
    text            = { 0.85, 0.85, 0.85, 1.00 },
    highlight       = { 1.00, 1.00, 1.00, 1.00 },
    disabled        = { 0.50, 0.50, 0.50, 1.00 },
    dim             = { 0.60, 0.60, 0.60, 1.00 },
    gray            = { 0.50, 0.50, 0.50, 1.00 },

    -- ═══════════════════ 테두리 ═══════════════════
    border          = { 0.25, 0.25, 0.25, 0.50 },
    borderActive    = { 0.40, 0.40, 0.40, 0.70 },
    separator       = { 0.20, 0.20, 0.20, 0.40 },

    -- ═══════════════════ 상태 ═══════════════════
    success         = { 0.30, 0.80, 0.30, 1.00 },
    warning         = { 0.90, 0.75, 0.20, 1.00 },
    error           = { 0.90, 0.25, 0.25, 1.00 },
    info            = { 0.40, 0.70, 1.00, 1.00 },

    -- ═══════════════════ 기본 색상 ═══════════════════
    red             = { 0.90, 0.20, 0.20, 1.00 },
    green           = { 0.20, 0.90, 0.20, 1.00 },
    blue            = { 0.20, 0.60, 1.00, 1.00 },
    yellow          = { 1.00, 0.82, 0.00, 1.00 },
    orange          = { 0.90, 0.45, 0.12, 1.00 },
    purple          = { 0.65, 0.35, 0.85, 1.00 },
    cyan            = { 0.20, 0.75, 0.90, 1.00 },
    pink            = { 1.00, 0.40, 0.60, 1.00 },

    -- ═══════════════════ DDingUI 엑센트 ═══════════════════
    accent          = { 0.90, 0.45, 0.12, 1.00 },  -- CDM 기본 오렌지
    accentLight     = { 1.00, 0.60, 0.25, 1.00 },
    accentDark      = { 0.50, 0.15, 0.04, 1.00 },
    accentGradEnd   = { 0.60, 0.18, 0.05, 1.00 },  -- gradient end (THEME.accentBlue)
    gold            = { 0.90, 0.45, 0.12, 1.00 },  -- 동의어
    gradTop         = { 0.13, 0.13, 0.13, 1.00 },  -- 그라데이션 배경 상단
    gradBottom      = { 0.09, 0.09, 0.09, 1.00 },  -- 그라데이션 배경 하단

    -- ═══════════════════ 소프트 색상 ═══════════════════
    softlime        = { 0.45, 0.92, 0.55, 1.00 },
    softblue        = { 0.50, 0.70, 1.00, 1.00 },
    softpurple      = { 0.70, 0.50, 0.90, 1.00 },
    softred         = { 1.00, 0.50, 0.50, 1.00 },
    softyellow      = { 1.00, 0.90, 0.45, 1.00 },

    -- ═══════════════════ 투명 ═══════════════════
    transparent     = { 0, 0, 0, 0 },
    shadow          = { 0, 0, 0, 0.40 },
}

-- 엑센트 오버라이드 (애드온별)
local addonAccentColors = {}

---------------------------------------------------------------------
-- API
---------------------------------------------------------------------

--- 색상 이름으로 r, g, b, a 반환
--- @param name string  색상 이름 (예: "accent", "background", "red")
--- @return number r, number g, number b, number a
function Lib.GetColor(name)
    local c = colorRegistry[name]
    if c then
        return c[1], c[2], c[3], c[4] or 1
    end
    -- fallback: white
    return 1, 1, 1, 1
end

--- 색상 이름으로 테이블 반환 (참조 — 수정 금지)
--- @param name string
--- @return table {r, g, b, a}
function Lib.GetColorTable(name)
    return colorRegistry[name] or colorRegistry.white
end

--- 색상 이름으로 WoW 색상 코드 문자열 반환
--- @param name string
--- @return string  e.g. "|cffff7320"
function Lib.GetColorStr(name)
    local c = colorRegistry[name]
    if c then
        return format("|cff%02x%02x%02x",
            math.floor(c[1] * 255 + 0.5),
            math.floor(c[2] * 255 + 0.5),
            math.floor(c[3] * 255 + 0.5))
    end
    return "|cffffffff"
end

--- 텍스트를 색상으로 감싸기
--- @param text string
--- @param name string|table  색상 이름 또는 {r,g,b} 테이블
--- @return string  e.g. "|cffff7320text|r"
function Lib.WrapColor(text, name)
    if type(name) == "table" then
        return format("|cff%02x%02x%02x%s|r",
            math.floor(name[1] * 255 + 0.5),
            math.floor(name[2] * 255 + 0.5),
            math.floor(name[3] * 255 + 0.5),
            text)
    end
    return Lib.GetColorStr(name) .. text .. "|r"
end

--- 색상 언패킹 (테이블 → r, g, b, a)
--- @param color table {r, g, b, a}
--- @return number r, number g, number b, number a
function Lib.UnpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

---------------------------------------------------------------------
-- 색상 등록/수정
---------------------------------------------------------------------

--- 새 색상 등록 또는 기존 색상 덮어쓰기
--- @param name string
--- @param r number
--- @param g number
--- @param b number
--- @param a number|nil  기본 1
function Lib.RegisterColor(name, r, g, b, a)
    colorRegistry[name] = { r, g, b, a or 1 }
end

--- 엑센트 색상 변경 (전체)
function Lib.SetAccentColor(r, g, b, a)
    colorRegistry.accent = { r, g, b, a or 1 }
end

--- 애드온별 엑센트 색상 설정
--- @param addonName string
--- @param colorName string  ColorNames 레지스트리의 색상 이름 또는 테이블
function Lib.SetAddonAccentColor(addonName, colorName)
    if type(colorName) == "string" then
        addonAccentColors[addonName] = colorName
    elseif type(colorName) == "table" then
        local name = "_addon_" .. addonName
        colorRegistry[name] = colorName
        addonAccentColors[addonName] = name
    end
end

--- 애드온의 엑센트 색상 가져오기
--- @param addonName string|nil
--- @return number r, number g, number b, number a
function Lib.GetAddonAccentColor(addonName)
    if addonName and addonAccentColors[addonName] then
        return Lib.GetColor(addonAccentColors[addonName])
    end
    return Lib.GetColor("accent")
end

---------------------------------------------------------------------
-- 기존 Colors.lua 테이블과의 호환 브릿지
---------------------------------------------------------------------
-- 기존 Lib.Colors.bg.main → Lib.GetColor("background") 매핑
-- Lib.Colors는 Colors.lua에서 이미 정의됨, 여기서 연동만 수행

-- 기존 THEME 스타일 → 이름 기반 변환 테이블
Lib._themeToName = {
    bgMain      = "background",
    bgSidebar   = "sidebar",
    bgInput     = "input",
    bgWidget    = "widget",
    bgHover     = "hover",
    bgSelected  = "selected",
    bgTitlebar  = "titlebar",
    text        = "text",
    textHighlight = "highlight",
    textDisabled = "disabled",
    textDim     = "dim",
    border      = "border",
    borderActive = "borderActive",
    accent      = "accent",
    gold        = "gold",
    error       = "error",
    warning     = "warning",
    success     = "success",
}

---------------------------------------------------------------------
-- HSV/RGB 변환
---------------------------------------------------------------------

--- HSV → RGB (h: 0~360, s: 0~1, v: 0~1)
function Lib.HSVtoRGB(h, s, v)
    if s == 0 then return v, v, v end
    h = h / 60
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

--- RGB → HSV
function Lib.RGBtoHSV(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local d = max - min
    local h, s, v

    v = max
    if max == 0 then s = 0 else s = d / max end
    if d == 0 then
        h = 0
    elseif max == r then
        h = 60 * ((g - b) / d % 6)
    elseif max == g then
        h = 60 * ((b - r) / d + 2)
    else
        h = 60 * ((r - g) / d + 4)
    end
    if h < 0 then h = h + 360 end
    return h, s, v
end

--- HEX → RGB
function Lib.HexToRGB(hex)
    hex = hex:gsub("#", "")
    return tonumber(hex:sub(1, 2), 16) / 255,
           tonumber(hex:sub(3, 4), 16) / 255,
           tonumber(hex:sub(5, 6), 16) / 255
end

--- RGB → HEX
function Lib.RGBtoHex(r, g, b)
    return format("%02x%02x%02x",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
end
