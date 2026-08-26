------------------------------------------------------
-- DDingUI_StyleLib :: Colors
-- Common colour palette (design-system single source)
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

Lib.Colors = {
    -- Backgrounds (matched to CLAUDE.md / UF design spec)
    bg = {
        main      = { 0.10, 0.10, 0.10, 0.95 },  -- right content area
        sidebar   = { 0.08, 0.08, 0.08, 0.95 },  -- left tree menu (darker)
        input     = { 0.06, 0.06, 0.06, 0.80 },   -- edit box innards
        widget    = { 0.06, 0.06, 0.06, 0.80 },   -- checkbox/dropdown/slider track bg
        hover     = { 0.20, 0.20, 0.20, 0.60 },   -- hover highlight
        hoverLight= { 0.20, 0.20, 0.20, 0.60 },   -- lighter hover / bgLight
        selected  = { 0.18, 0.18, 0.22, 0.80 },   -- active menu / tab bar
        titlebar  = { 0.12, 0.12, 0.12, 0.98 },   -- top bar
        gradTop   = { 0.13, 0.13, 0.13, 1.0 },   -- gradient top
        gradBottom= { 0.09, 0.09, 0.09, 1.0 },   -- gradient bottom
    },

    -- Text
    text = {
        normal    = { 0.85, 0.85, 0.85, 1.0 },   -- labels, descriptions
        highlight = { 1.00, 1.00, 1.00, 1.0 },    -- selected items, emphasis
        disabled  = { 0.50, 0.50, 0.50, 1.0 },    -- inactive controls
        dim       = { 0.60, 0.60, 0.60, 1.0 },    -- secondary info
        -- section headers use addon accent (resolved at runtime)
    },

    -- Borders
    border = {
        default   = { 0.25, 0.25, 0.25, 0.50 },  -- standard widget outline
        active    = { 0.40, 0.40, 0.40, 0.70 },   -- focused control border
        separator = { 0.20, 0.20, 0.20, 0.40 },
    },

    -- Status
    status = {
        success   = { 0.30, 0.80, 0.30, 1.0 },   -- green
        warning   = { 0.90, 0.75, 0.20, 1.0 },   -- yellow-orange
        error     = { 0.90, 0.25, 0.25, 1.0 },    -- red
    },
}

-- Spacing constants (px)
Lib.Spacing = {
    contentPad    = 14,   -- content area inner padding
    controlGap    = 8,    -- vertical gap between controls
    sectionGap    = 16,   -- vertical gap between sections
    labelGap      = 8,    -- label-to-control horizontal gap
    treeItemGap   = 2,    -- vertical gap between tree items
    inlineGap     = 10,   -- horizontal gap between inline elements
}

-- Font paths & sizes (UF DDINGUI_FONT_* 기준)
Lib.Font = {
    path      = "Fonts\\2002.TTF",
    default   = "Fonts\\FRIZQT__.TTF",  -- [12.0.1] WoW 기본 폰트 (fallback/alert용)
    title     = 14,   -- title bar addon name (UF DDINGUI_FONT_TITLE)
    section   = 14,   -- section headers (UF DDINGUI_FONT_ACCENT)
    normal    = 13,   -- labels, tree items, widgets (UF DDINGUI_FONT_NORMAL)
    small     = 11,   -- version text, slider min/max (UF DDINGUI_FONT_SMALL)
    sizeScale = 1.0,  -- [CONTROLLER] 글로벌 크기 배율 (Controller에서 설정)
}
