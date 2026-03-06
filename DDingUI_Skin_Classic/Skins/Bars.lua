--[[
    DDingUI Classic Skin
    Skins/Bars.lua — 자원바, 버프추적기 바를 블리자드 기본 UI 스타일로 변환

    패턴: EnhanceQoL applyIconBorder() 동일
    - BackdropTemplate + SetBackdrop({ edgeFile only })
    - SetBackdropColor(0,0,0,0) — 배경 투명
    - SetBackdropBorderColor로 보더 색상 제어
]]

local _, ns = ...
local Media = ns.Media
local ClassicSkin = ns.ClassicSkin

local SkinBars = {}
ns.SkinBars = SkinBars

-- Weak table for per-bar skin state
local barSkinState = setmetatable({}, { __mode = "k" })

local function GetState(bar)
    local s = barSkinState[bar]
    if not s then
        s = {}
        barSkinState[bar] = s
    end
    return s
end

-----------------------------------------------
-- 공통: 바에 edgeFile-only 보더 프레임 추가
-- (EnhanceQoL 동일 패턴)
-----------------------------------------------

local function EnsureBorderFrame(bar, state)
    if state.borderFrame then return state.borderFrame end

    local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    border:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    state.borderFrame = border
    return border
end

local function ApplyBarBorder(bar, state)
    local border = EnsureBorderFrame(bar, state)
    local edgeSize = Media.BAR_BORDER_SIZE
    local offset = Media.BAR_BORDER_OFFSET
    local edgeFile = Media.DEFAULT_BORDER_TEXTURE
    local color = Media.BAR_BORDER_COLOR

    -- SetBackdrop: edgeFile만, bgFile 없음
    if border._edgeFile ~= edgeFile or border._edgeSize ~= edgeSize then
        border:SetBackdrop({
            edgeFile = edgeFile,
            edgeSize = edgeSize,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        border:SetBackdropColor(0, 0, 0, 0)
        border._edgeFile = edgeFile
        border._edgeSize = edgeSize
    end

    if border._offset ~= offset then
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", bar, "TOPLEFT", -offset, offset)
        border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", offset, -offset)
        border._offset = offset
    end

    border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    border:Show()
end

-----------------------------------------------
-- PostSkinPowerBar
-----------------------------------------------

function SkinBars:PostSkinPowerBar(bar)
    if not bar then return end

    local state = GetState(bar)

    -- StatusBar 텍스처 → 블리자드 기본
    if bar.StatusBar then
        bar.StatusBar:SetStatusBarTexture(Media.BAR_TEXTURE)
    end

    -- DDingUI 보더 숨기기
    if bar.Border then
        bar.Border:Hide()
    end

    -- 배경 → 약간 투명한 검은색
    if bar.Background then
        bar.Background:SetColorTexture(
            Media.BAR_BG_COLOR[1], Media.BAR_BG_COLOR[2],
            Media.BAR_BG_COLOR[3], Media.BAR_BG_COLOR[4]
        )
    end

    -- edgeFile-only 보더
    ApplyBarBorder(bar, state)
end

-----------------------------------------------
-- PostSkinSecondaryBar
-----------------------------------------------

function SkinBars:PostSkinSecondaryBar(bar)
    if not bar then return end

    local state = GetState(bar)

    -- 세그먼트 기반 바
    if bar.segments then
        for _, seg in ipairs(bar.segments) do
            if seg.StatusBar then
                seg.StatusBar:SetStatusBarTexture(Media.BAR_TEXTURE)
            elseif seg.SetStatusBarTexture then
                seg:SetStatusBarTexture(Media.BAR_TEXTURE)
            end
        end
    elseif bar.StatusBar then
        bar.StatusBar:SetStatusBarTexture(Media.BAR_TEXTURE)
    end

    if bar.Border then
        bar.Border:Hide()
    end

    if bar.Background then
        bar.Background:SetColorTexture(unpack(Media.BAR_BG_COLOR))
    end

    ApplyBarBorder(bar, state)
end

-----------------------------------------------
-- PostSkinBuffTrackerBar
-----------------------------------------------

function SkinBars:PostSkinBuffTrackerBar(bar)
    if not bar then return end

    local state = GetState(bar)

    if bar.StatusBar then
        bar.StatusBar:SetStatusBarTexture(Media.BAR_TEXTURE)
    end

    if bar.Border then
        bar.Border:Hide()
    end

    if bar.Background then
        bar.Background:SetColorTexture(unpack(Media.BAR_BG_COLOR))
    end

    ApplyBarBorder(bar, state)

    -- 버프 추적기의 아이콘도 동일 패턴으로 보더 적용
    if bar.icons then
        for _, iconFrame in ipairs(bar.icons) do
            if iconFrame and not iconFrame._classicSkinApplied then
                local iconTex = iconFrame.icon or iconFrame.Icon
                if iconTex then
                    -- edgeFile-only 보더 (EnhanceQoL 동일)
                    if not iconFrame._classicBorder then
                        local border = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
                        border:SetFrameLevel(iconFrame:GetFrameLevel() + 2)
                        border:SetBackdrop({
                            edgeFile = Media.DEFAULT_BORDER_TEXTURE,
                            edgeSize = Media.ICON_BORDER_SIZE,
                            insets = { left = 0, right = 0, top = 0, bottom = 0 },
                        })
                        border:SetBackdropColor(0, 0, 0, 0)

                        local offset = Media.ICON_BORDER_OFFSET
                        border:SetPoint("TOPLEFT", iconTex, "TOPLEFT", -offset, offset)
                        border:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", offset, -offset)
                        iconFrame._classicBorder = border
                    end

                    local color = Media.BORDER_COLOR
                    iconFrame._classicBorder:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
                    iconFrame._classicBorder:Show()

                    -- TexCoord 블리자드 기본
                    local tc = Media.ICON_TEXCOORD
                    iconTex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                end

                iconFrame._classicSkinApplied = true
            end
        end
    end
end
