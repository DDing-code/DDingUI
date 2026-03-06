------------------------------------------------------
-- DDingUI_StyleLib :: GlowEffects
-- 글로우 효과 래퍼 (LibCustomGlow-1.0 wrapper)
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local LCG = LibStub("LibCustomGlow-1.0", true)
if not LCG then return end

---------------------------------------------------------------------
-- Pixel Glow (픽셀 스타일 글로우)
---------------------------------------------------------------------

--- 프레임에 픽셀 글로우를 표시합니다.
--- @param frame Frame
--- @param color table|string|nil  {r,g,b,a} 또는 색상 이름 (기본: accent)
--- @param lineCount number|nil  선 수 (기본 8)
--- @param frequency number|nil  회전 빈도 (기본 0.25)
--- @param length number|nil  선 길이 (기본 nil = auto)
--- @param thickness number|nil  선 두께 (기본 2)
--- @param xOffset number|nil
--- @param yOffset number|nil
--- @param border boolean|nil  테두리 안쪽에 표시할지 (기본 false)
--- @param key string|nil  글로우 식별 키 (기본 nil)
function Lib.ShowPixelGlow(frame, color, lineCount, frequency, length, thickness, xOffset, yOffset, border, key)
    if type(color) == "string" then
        color = Lib.GetColorTable(color)
    end
    color = color or Lib.GetColorTable("accent")
    LCG.PixelGlow_Start(frame, color, lineCount or 8, frequency or 0.25, length, thickness or 2, xOffset or 0, yOffset or 0, border, key)
end

function Lib.HidePixelGlow(frame, key)
    LCG.PixelGlow_Stop(frame, key)
end

---------------------------------------------------------------------
-- Autocast Glow (즈글즈글 글로우)
---------------------------------------------------------------------

--- @param frame Frame
--- @param color table|string|nil
--- @param particleCount number|nil  기본 4
--- @param frequency number|nil  기본 0.125
--- @param scale number|nil  기본 1
--- @param xOffset number|nil
--- @param yOffset number|nil
--- @param key string|nil
function Lib.ShowAutocastGlow(frame, color, particleCount, frequency, scale, xOffset, yOffset, key)
    if type(color) == "string" then
        color = Lib.GetColorTable(color)
    end
    color = color or Lib.GetColorTable("accent")
    LCG.AutoCastGlow_Start(frame, color, particleCount or 4, frequency or 0.125, scale or 1, xOffset or 0, yOffset or 0, key)
end

function Lib.HideAutocastGlow(frame, key)
    LCG.AutoCastGlow_Stop(frame, key)
end

---------------------------------------------------------------------
-- Button Glow (액션바 스타일)
---------------------------------------------------------------------

--- @param frame Frame
--- @param color table|string|nil
--- @param frequency number|nil
--- @param key string|nil
function Lib.ShowButtonGlow(frame, color, frequency, key)
    if type(color) == "string" then
        color = Lib.GetColorTable(color)
    end
    LCG.ButtonGlow_Start(frame, color, frequency, key)
end

function Lib.HideButtonGlow(frame, key)
    LCG.ButtonGlow_Stop(frame, key)
end

---------------------------------------------------------------------
-- Normal Glow (부드러운 발광)
---------------------------------------------------------------------

--- 프레임 주위에 부드러운 글로우 표시
--- @param frame Frame
--- @param color table|string|nil  색상 (기본 accent)
--- @param size number|nil  글로우 크기 (기본 3)
function Lib.ShowNormalGlow(frame, color, size)
    if type(color) == "string" then
        color = Lib.GetColorTable(color)
    end
    color = color or Lib.GetColorTable("accent")
    size = size or 3

    if not frame._slGlow then
        frame._slGlow = CreateFrame("Frame", nil, frame)
        frame._slGlow:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))

        -- 9-slice glow using simple color textures
        local g = frame._slGlow
        g.edges = {}
        for i = 1, 4 do
            local edge = g:CreateTexture(nil, "BACKGROUND")
            edge:SetColorTexture(1, 1, 1, 1)
            g.edges[i] = edge
        end
        -- top
        g.edges[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -size, size)
        g.edges[1]:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", size, 0)
        -- bottom
        g.edges[2]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -size, 0)
        g.edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size, -size)
        -- left
        g.edges[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", -size, 0)
        g.edges[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
        -- right
        g.edges[4]:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
        g.edges[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size, 0)
    end

    for _, edge in ipairs(frame._slGlow.edges) do
        edge:SetColorTexture(color[1], color[2], color[3], color[4] or 0.3)
    end
    frame._slGlow:Show()
end

function Lib.HideNormalGlow(frame)
    if frame._slGlow then
        frame._slGlow:Hide()
    end
end

---------------------------------------------------------------------
-- 통합 Hide
---------------------------------------------------------------------

--- 프레임의 모든 글로우를 숨깁니다.
function Lib.HideAllGlows(frame, key)
    Lib.HidePixelGlow(frame, key)
    Lib.HideAutocastGlow(frame, key)
    Lib.HideButtonGlow(frame, key)
    Lib.HideNormalGlow(frame)
end
