--[[
    DDingUI Classic Skin
    Media.lua — 블리자드 기본 UI 텍스처/폰트 상수

    보더 패턴: EnhanceQoL CooldownPanels.applyIconBorder 동일
    SetBackdrop({ edgeFile only, no bgFile }) + SetBackdropColor(0,0,0,0)
]]

local _, ns = ...
local Media = {}
ns.Media = Media

-----------------------------------------------
-- Textures
-----------------------------------------------

-- 보더 텍스처 (기본)
Media.DEFAULT_BORDER_TEXTURE = "Interface/Tooltips/UI-Tooltip-Border"

-- 바 텍스처
Media.BAR_TEXTURE            = "Interface\\TargetingFrame\\UI-StatusBar"

-- 플랫
Media.FLAT_TEXTURE           = "Interface\\Buttons\\WHITE8X8"

-----------------------------------------------
-- 아이콘 보더 설정 (EnhanceQoL applyIconBorder 동일 패턴)
-----------------------------------------------

Media.ICON_BORDER_SIZE       = 12     -- edgeSize (1~64)
Media.ICON_BORDER_OFFSET     = 0      -- 아이콘 밖으로 확장/축소 (-64~64)

-----------------------------------------------
-- 바 보더 설정
-----------------------------------------------

Media.BAR_BORDER_SIZE        = 14     -- edgeSize
Media.BAR_BORDER_OFFSET      = 0      -- 바 밖으로 확장/축소

-----------------------------------------------
-- TexCoord
-----------------------------------------------

Media.ICON_TEXCOORD = { 0.07, 0.93, 0.07, 0.93 }

-----------------------------------------------
-- Colors
-----------------------------------------------

-- 보더 색상
Media.BORDER_COLOR           = { 1.0, 1.0, 1.0, 1.0 }  -- 기본 흰색 (텍스처 원본색)

-- 바 배경
Media.BAR_BG_COLOR           = { 0.0, 0.0, 0.0, 0.8 }
Media.BAR_BORDER_COLOR       = { 1.0, 1.0, 1.0, 1.0 }
