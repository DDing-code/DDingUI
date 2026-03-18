------------------------------------------------------
-- DDingUI_StyleLib :: DesignTokens
-- 100+ design tokens (EllesmereUI pattern)
-- Centralized visual constants for all DDingUI modules
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
Tokens.WIDGET_BG      = { 0.050, 0.050, 0.050, 0.80 }   -- 범용 위젯 배경
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

-- ─── Buttons (상태별 세분화) ───
Tokens.BTN_BG_R         = 0.075    -- 버튼 배경 RGB
Tokens.BTN_BG_G         = 0.075
Tokens.BTN_BG_B         = 0.075
Tokens.BTN_BG_A         = 0.08     -- 버튼 배경 투명도 (기본)
Tokens.BTN_BG_HA        = 0.15     -- 버튼 배경 투명도 (호버)
Tokens.BTN_BG_PA        = 0.25     -- 버튼 배경 투명도 (눌림)
Tokens.BTN_BRD_A        = 0.12     -- 버튼 보더 투명도 (기본)
Tokens.BTN_BRD_HA       = 0.30     -- 버튼 보더 투명도 (호버)
Tokens.BTN_TXT_A        = 0.85     -- 버튼 텍스트 투명도 (기본)
Tokens.BTN_TXT_HA       = 1.00     -- 버튼 텍스트 투명도 (호버)

-- ─── Checkboxes (상태별 세분화 — EllesmereUI CB 패턴) ───
Tokens.CB = {
    BOX_R    = 0.075,   -- 체크박스 배경 R
    BOX_G    = 0.113,   -- 체크박스 배경 G
    BOX_B    = 0.141,   -- 체크박스 배경 B
    BRD_A    = 0.25,    -- 체크박스 보더 투명도 (기본)
    ACT_BRD_A = 0.70,   -- 체크박스 보더 투명도 (활성/체크)
    SIZE     = 14,      -- 체크박스 크기 (WoW px)
    CHECK_INSET = 2,    -- 체크마크 안쪽 여백
}

-- ─── Dropdowns (상태별 세분화 — EllesmereUI DD 패턴) ───
Tokens.DD = {
    BG_R     = 0.075,   -- 드롭다운 배경 RGB
    BG_G     = 0.113,
    BG_B     = 0.141,
    BG_A     = 0.80,    -- 드롭다운 배경 투명도 (기본)
    BG_HA    = 0.95,    -- 드롭다운 배경 투명도 (호버)
    BRD_A    = 0.20,    -- 드롭다운 보더 투명도 (기본)
    BRD_HA   = 0.35,    -- 드롭다운 보더 투명도 (호버)
    TXT_A    = 0.55,    -- 드롭다운 텍스트 투명도 (기본)
    TXT_HA   = 0.70,    -- 드롭다운 텍스트 투명도 (호버)
    ITEM_HL_A  = 0.08,  -- 드롭다운 항목 하이라이트 투명도
    ITEM_SEL_A = 0.12,  -- 드롭다운 항목 선택 투명도
    MAX_H    = 200,     -- 드롭다운 최대 높이 (스크롤 임계)
    ITEM_H   = 22,      -- 드롭다운 항목 높이
    ARROW_SZ = 12,      -- 드롭다운 화살표 크기
}

-- ─── Sliders (상태별 세분화 — EllesmereUI SL 패턴) ───
Tokens.SL = {
    TRACK_R  = 0.08,    -- 슬라이더 트랙 RGB
    TRACK_G  = 0.10,
    TRACK_B  = 0.12,
    TRACK_A  = 0.95,    -- 슬라이더 트랙 투명도
    TRACK_H  = 4,       -- 슬라이더 트랙 높이
    FILL_A   = 0.75,    -- 슬라이더 채움 투명도
    INPUT_R  = 0.075,   -- 값 입력 배경 RGB
    INPUT_G  = 0.113,
    INPUT_B  = 0.141,
    INPUT_A  = 0.55,    -- 값 입력 배경 투명도
    INPUT_BRD_A = 0.20, -- 값 입력 보더 투명도
    THUMB_SZ = 12,      -- 썸 크기
}

-- ─── Toggles (상태별 세분화 — EllesmereUI TG 패턴) ───
Tokens.TG = {
    OFF_R    = 0.10,    -- OFF 트랙 RGB
    OFF_G    = 0.12,
    OFF_B    = 0.14,
    OFF_A    = 0.70,    -- OFF 트랙 투명도
    ON_A     = 0.85,    -- ON 트랙 투명도 (색은 accent)
    KNOB_OFF_R = 0.30,  -- OFF 노브 RGB
    KNOB_OFF_G = 0.32,
    KNOB_OFF_B = 0.34,
    KNOB_OFF_A = 0.80,  -- OFF 노브 투명도
    KNOB_ON_R  = 1.0,   -- ON 노브 RGB
    KNOB_ON_G  = 1.0,
    KNOB_ON_B  = 1.0,
    KNOB_ON_A  = 1.0,   -- ON 노브 투명도
    TRACK_W  = 40,      -- 토글 트랙 너비
    TRACK_H  = 20,      -- 토글 트랙 높이
    KNOB_SZ  = 16,      -- 노브 크기
    KNOB_PAD = 3,       -- 노브 트랙 내 패딩
    ANIM_DUR = 0.075,   -- 토글 애니메이션 시간 (초)
}

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

-- ─── DualRow Layout ───
Tokens.DUALROW_H        = 50       -- DualRow 기본 행 높이
Tokens.DUALROW_PAD      = 20       -- DualRow 각 끝 내부 패딩
Tokens.CONTENT_PAD      = 14       -- 컨텐츠 영역 좌우 패딩

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
        Tokens.BTN_BG_R, Tokens.BTN_BG_G, Tokens.BTN_BG_B, Tokens.BTN_BG_A,
        Tokens.BTN_BG_R, Tokens.BTN_BG_G, Tokens.BTN_BG_B, Tokens.BTN_BG_HA,
        -- border normal, border hover (hover = accent color)
        1, 1, 1, Tokens.BTN_BRD_A,
        r, g, b, Tokens.BTN_BRD_HA,
        -- text normal, text hover
        0.85, 0.85, 0.85, Tokens.BTN_TXT_A,
        1.0, 1.0, 1.0, Tokens.BTN_TXT_HA,
    }
end

--- Returns dropdown color arrays for the given accent
--- @param accent table {r, g, b, a}
--- @return table DD colors { bg(4), bg_hover(4), brd(4), brd_hover(4), txt(4), txt_hover(4) }
function Tokens.MakeDropdownColors(accent)
    local DD = Tokens.DD
    local r, g, b = accent[1], accent[2], accent[3]
    return {
        DD.BG_R, DD.BG_G, DD.BG_B, DD.BG_A,
        DD.BG_R, DD.BG_G, DD.BG_B, DD.BG_HA,
        1, 1, 1, DD.BRD_A,
        r, g, b, DD.BRD_HA,
        1, 1, 1, DD.TXT_A,
        1, 1, 1, DD.TXT_HA,
    }
end

--- Returns toggle color arrays for the given accent
--- @param accent table {r, g, b, a}
--- @return table  { track_off(4), track_on(4), knob_off(4), knob_on(4) }
function Tokens.MakeToggleColors(accent)
    local TG = Tokens.TG
    local r, g, b = accent[1], accent[2], accent[3]
    return {
        -- track OFF
        TG.OFF_R, TG.OFF_G, TG.OFF_B, TG.OFF_A,
        -- track ON (accent)
        r, g, b, TG.ON_A,
        -- knob OFF
        TG.KNOB_OFF_R, TG.KNOB_OFF_G, TG.KNOB_OFF_B, TG.KNOB_OFF_A,
        -- knob ON
        TG.KNOB_ON_R, TG.KNOB_ON_G, TG.KNOB_ON_B, TG.KNOB_ON_A,
    }
end

--- Returns slider color arrays
--- @return table  { track(4), input(4) }
function Tokens.MakeSliderColors()
    local SL = Tokens.SL
    return {
        SL.TRACK_R, SL.TRACK_G, SL.TRACK_B, SL.TRACK_A,
        SL.INPUT_R, SL.INPUT_G, SL.INPUT_B, SL.INPUT_A,
    }
end

--- Returns row background alpha for alternating zebra striping
--- @param index number  1-based row index
--- @return number  alpha value
function Tokens.RowBgAlpha(index)
    return (index % 2 == 0) and Tokens.ROW_BG_EVEN or Tokens.ROW_BG_ODD
end

--- linear interpolation: a + (b - a) * t
--- @param a number
--- @param b number
--- @param t number  0~1
--- @return number
function Tokens.Lerp(a, b, t)
    return a + (b - a) * t
end
