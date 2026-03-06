--[[
    DDingUI Classic Skin
    Skins/Icons.lua — CDM 아이콘 보더를 블리자드 기본 UI 스타일로 변환

    패턴: EnhanceQoL CooldownPanels.applyIconBorder() 동일
    - BackdropTemplate + SetBackdrop({ edgeFile only })
    - SetBackdropColor(0,0,0,0) — 배경 투명
    - SetBackdropBorderColor로 보더 색상 제어
    - offset으로 아이콘 밖 확장 제어
]]

local _, ns = ...
local Media = ns.Media
local ClassicSkin = ns.ClassicSkin

local SkinIcons = {}
ns.SkinIcons = SkinIcons

-- Weak table for per-icon skin state
local iconSkinState = setmetatable({}, { __mode = "k" })

local function GetState(icon)
    local s = iconSkinState[icon]
    if not s then
        s = {}
        iconSkinState[icon] = s
    end
    return s
end

-----------------------------------------------
-- PostSkinIcon: CDM SkinIcon 완료 후 블리자드 보더 적용
-- (EnhanceQoL applyIconBorder 패턴 동일)
-----------------------------------------------

function SkinIcons:PostSkinIcon(icon, settings)
    if not icon then return end
    if icon.IsForbidden and icon:IsForbidden() then return end

    local iconTexture = icon.icon or icon.Icon
    if not iconTexture then return end

    local state = GetState(icon)

    -- ================================================
    -- 1. DDingUI 플랫 보더 숨기기
    -- ================================================

    local IconViewers = ns.IconViewers
    if IconViewers and IconViewers._iconData then
        local id = IconViewers._iconData[icon]
        if id and id.borders then
            for _, borderTex in ipairs(id.borders) do
                borderTex:SetShown(false)
            end
        end
    end

    -- ================================================
    -- 2. BackdropTemplate 보더 프레임 (edgeFile only)
    --    EnhanceQoL applyIconBorder() 동일 패턴
    -- ================================================

    if not state.border then
        local border = CreateFrame("Frame", nil, icon, "BackdropTemplate")
        border:SetFrameLevel(icon:GetFrameLevel() + 2)
        state.border = border
    end

    local border = state.border
    local edgeSize = Media.ICON_BORDER_SIZE
    local offset = Media.ICON_BORDER_OFFSET
    local edgeFile = Media.DEFAULT_BORDER_TEXTURE
    local color = Media.BORDER_COLOR

    -- SetBackdrop: edgeFile만, bgFile 없음 (EnhanceQoL 동일)
    if border._edgeFile ~= edgeFile or border._edgeSize ~= edgeSize then
        border:SetBackdrop({
            edgeFile = edgeFile,
            edgeSize = edgeSize,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        border:SetBackdropColor(0, 0, 0, 0)  -- 배경 완전 투명
        border._edgeFile = edgeFile
        border._edgeSize = edgeSize
    end

    -- 위치: offset으로 확장/축소 제어
    if border._offset ~= offset then
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", -offset, offset)
        border:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", offset, -offset)
        border._offset = offset
    end

    -- 보더 색상
    border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    border:Show()

    -- ================================================
    -- 3. TexCoord 블리자드 기본값
    -- ================================================

    local tc = Media.ICON_TEXCOORD
    iconTexture:SetTexCoord(tc[1], tc[2], tc[3], tc[4])

    -- ================================================
    -- 4. 쿨다운 스와이프 블리자드 기본
    -- ================================================

    if icon.Cooldown then
        icon.Cooldown:SetSwipeTexture("")
    end

    state.skinned = true
end

-----------------------------------------------
-- RemoveClassicSkin
-----------------------------------------------

function SkinIcons:RemoveClassicSkin(icon)
    local state = iconSkinState[icon]
    if not state then return end

    if state.border then
        state.border:Hide()
    end

    -- CDM 보더 복구
    local IconViewers = ns.IconViewers
    if IconViewers and IconViewers._iconData then
        local id = IconViewers._iconData[icon]
        if id and id.borders then
            local s = id.settings
            local edgeSize = s and s.borderSize or 1
            for _, borderTex in ipairs(id.borders) do
                borderTex:SetShown(edgeSize > 0)
            end
        end
    end

    state.skinned = false
end
