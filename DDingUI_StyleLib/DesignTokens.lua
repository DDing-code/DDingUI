------------------------------------------------------
-- DDingUI_StyleLib :: DesignTokens
-- 60+ design tokens (inspired by EllesmereUI)
-- Centralized visual constants for CDM + UF
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

-- ============================================
-- Design Tokens — single source of truth
-- ============================================
local Tokens = {}
Lib.Tokens = Tokens

-- ─── Backgrounds ───
Tokens.PANEL_BG       = { 0.067, 0.067, 0.067, 1.0 }   -- 메인 패널 배경
Tokens.SIDEBAR_BG     = { 0.055, 0.055, 0.055, 1.0 }   -- 사이드바 (더 어두움)
Tokens.INPUT_BG       = { 0.045, 0.045, 0.045, 0.85 }   -- 인풋/에디트박스 배경
Tokens.WIDGET_BG      = { 0.050, 0.050, 0.050, 0.80 }   -- 체크박스/드롭다운 트랙 배경
Tokens.TITLEBAR_BG    = { 0.085, 0.085, 0.085, 0.98 }   -- 상단 타이틀바
Tokens.GRAD_TOP       = { 0.090, 0.090, 0.090, 1.0 }    -- 그라디언트 상단
Tokens.GRAD_BOTTOM    = { 0.060, 0.060, 0.060, 1.0 }    -- 그라디언트 하단

-- ─── Hover & Selection ───
Tokens.BG_HOVER       = { 0.14, 0.14, 0.14, 0.65 }      -- 호버 배경
Tokens.BG_HOVER_LIGHT = { 0.18, 0.18, 0.18, 0.50 }      -- 가벼운 호버
Tokens.BG_SELECTED    = { 0.16, 0.16, 0.20, 0.80 }      -- 선택 배경 (약간 파란 틴트)
Tokens.BG_PRESSED     = { 0.22, 0.22, 0.22, 0.85 }      -- 눌림 배경

-- ─── Text ───
Tokens.TEXT_NORMAL     = { 0.85, 0.85, 0.85, 1.0 }      -- 기본 텍스트
Tokens.TEXT_HIGHLIGHT  = { 1.00, 1.00, 1.00, 1.0 }      -- 강조 텍스트
Tokens.TEXT_DIM        = { 0.55, 0.55, 0.55, 1.0 }      -- 보조 텍스트
Tokens.TEXT_DISABLED   = { 0.40, 0.40, 0.40, 1.0 }      -- 비활성 텍스트
Tokens.TEXT_MUTED      = { 0.35, 0.35, 0.35, 1.0 }      -- 힌트/플레이스홀더

-- ─── Borders ───
Tokens.BORDER_DEFAULT  = { 0.22, 0.22, 0.22, 0.50 }     -- 기본 보더
Tokens.BORDER_ACTIVE   = { 0.35, 0.35, 0.35, 0.70 }     -- 활성 보더
Tokens.BORDER_FOCUS    = { 0.50, 0.50, 0.50, 0.80 }     -- 포커스 보더
Tokens.BORDER_SEP      = { 0.18, 0.18, 0.18, 0.40 }     -- 구분선

-- ─── Buttons ───
Tokens.BTN_BG_A         = 0.08     -- 버튼 배경 투명도 (기본)
Tokens.BTN_BG_HA        = 0.15     -- 버튼 배경 투명도 (호버)
Tokens.BTN_BG_PA        = 0.25     -- 버튼 배경 투명도 (눌림)
Tokens.BTN_BRD_A        = 0.12     -- 버튼 보더 투명도 (기본)
Tokens.BTN_BRD_HA       = 0.30     -- 버튼 보더 투명도 (호버)
Tokens.BTN_TXT_A        = 0.85     -- 버튼 텍스트 투명도 (기본)
Tokens.BTN_TXT_HA       = 1.00     -- 버튼 텍스트 투명도 (호버)

-- ─── Sliders ───
Tokens.SL_TRACK_A       = 0.16     -- 슬라이더 트랙 투명도
Tokens.SL_FILL_A        = 0.75     -- 슬라이더 채움 투명도
Tokens.SL_THUMB_SIZE    = 12       -- 슬라이더 썸 크기

-- ─── Toggles ───
Tokens.TG_OFF_A         = 0.25     -- 토글 OFF 투명도
Tokens.TG_ON_A          = 0.85     -- 토글 ON 투명도
Tokens.TG_TRACK_W       = 28       -- 토글 트랙 너비
Tokens.TG_TRACK_H       = 14       -- 토글 트랙 높이

-- ─── Dropdowns ───
Tokens.DD_BG_A          = 0.80     -- 드롭다운 배경 투명도
Tokens.DD_BRD_A         = 0.25     -- 드롭다운 보더 투명도
Tokens.DD_MAX_H         = 200      -- 드롭다운 최대 높이 (스크롤 임계)
Tokens.DD_ITEM_H        = 22       -- 드롭다운 항목 높이

-- ─── Lists / Rows ───
Tokens.ROW_BG_ODD       = 0.035    -- 리스트 홀수 행 배경
Tokens.ROW_BG_EVEN      = 0.055    -- 리스트 짝수 행 배경
Tokens.ROW_H            = 22       -- 기본 리스트 행 높이
Tokens.ROW_INDENT       = 16       -- 계층 들여쓰기 (px per depth)

-- ─── Status Colors ───
Tokens.SUCCESS          = { 0.27, 0.93, 0.27, 1.0 }     -- 초록
Tokens.WARNING          = { 0.90, 0.75, 0.20, 1.0 }     -- 노랑
Tokens.ERROR            = { 0.90, 0.25, 0.25, 1.0 }     -- 빨강
Tokens.INFO             = { 0.40, 0.70, 0.95, 1.0 }     -- 파랑

-- ─── Animations ───
Tokens.ANIM_FADE_IN     = 0.15     -- 페이드 인 지속시간
Tokens.ANIM_FADE_OUT    = 0.20     -- 페이드 아웃 지속시간
Tokens.ANIM_SLIDE       = 0.25     -- 슬라이드 전환 지속시간
Tokens.ANIM_PULSE_SPEED = 3.0      -- 펄스 속도 배율
Tokens.ANIM_FPS_LIMIT   = 0.033    -- ~30fps 프레임 제한 (초)

-- ─── Pixel Perfect ───
Tokens.PP_BORDER_W      = 1        -- 물리 1px 보더
Tokens.PP_INNER_PAD     = 1        -- 물리 1px 내부 패딩

-- ─── Sizing ───
Tokens.SIDEBAR_W        = 180      -- 사이드바 너비
Tokens.TABBAR_H         = 32       -- 탭바 높이
Tokens.SCROLLBAR_W      = 6        -- 스크롤바 너비
Tokens.TOOLTIP_PAD      = 8        -- 툴팁 패딩

-- ============================================
-- Helper: Get accent-aware token
-- ============================================
--- Returns a button color array for the given accent
--- @param accent table {r, g, b, a}  the addon's primary accent
--- @return table  24-element color array { bg(4), bg_hover(4), border(4), border_hover(4), text(4), text_hover(4) }
function Tokens.MakeButtonColors(accent)
    local r, g, b = accent[1], accent[2], accent[3]
    return {
        -- bg normal, bg hover
        0.08, 0.08, 0.08, Tokens.BTN_BG_A,
        0.12, 0.12, 0.12, Tokens.BTN_BG_HA,
        -- border normal, border hover
        0.20, 0.20, 0.20, Tokens.BTN_BRD_A,
        r, g, b, Tokens.BTN_BRD_HA,
        -- text normal, text hover
        0.85, 0.85, 0.85, Tokens.BTN_TXT_A,
        1.0, 1.0, 1.0, Tokens.BTN_TXT_HA,
    }
end

--- Returns row background alpha for alternating zebra striping
--- @param index number  1-based row index
--- @return number  alpha value
function Tokens.RowBgAlpha(index)
    return (index % 2 == 0) and Tokens.ROW_BG_EVEN or Tokens.ROW_BG_ODD
end
