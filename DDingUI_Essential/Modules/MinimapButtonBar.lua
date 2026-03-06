-- DDingUI_Essential: Minimap Button Bar Module -- [ESSENTIAL]
-- WindTools 스타일: 미니맵 주변 애드온 버튼을 스타일된 바에 수집
-- 참조: WindTools/Modules/Maps/MinimapButtons.lua

local _, ns = ...

local MinimapButtonBar = {}

------------------------------------------------------------------------
-- StyleLib 참조 -- [ESSENTIAL]
------------------------------------------------------------------------
local SL      = _G.DDingUI_StyleLib
local C       = SL and SL.Colors
local F       = SL and SL.Font
local FLAT    = SL and SL.Textures and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local SL_FONT = F and F.path or "Fonts\\2002.TTF"

------------------------------------------------------------------------
-- 블리자드 프레임 화이트리스트 (수집에서 제외) -- [ESSENTIAL]
------------------------------------------------------------------------
local BLIZZARD_WHITELIST = {
    ["MinimapBackdrop"] = true,
    ["MinimapZoneTextButton"] = true,
    ["MiniMapTracking"] = true,
    ["MiniMapTrackingButton"] = true,
    ["MiniMapTrackingFrame"] = true,
    ["MiniMapMailFrame"] = true,
    ["MiniMapMailBorder"] = true,
    ["MiniMapMailIcon"] = true,
    ["GameTimeFrame"] = true,
    ["TimeManagerClockButton"] = true,
    ["MinimapCompassTexture"] = true,
    ["MinimapCluster"] = true,
    ["QueueStatusButton"] = true,
    ["QueueStatusMinimapButton"] = true,
    ["DDingUI_MinimapButton"] = true,
    ["ExpansionLandingPageMinimapButton"] = true,
    ["AddonCompartmentFrame"] = true,
    ["MinimapZoomIn"] = true,
    ["MinimapZoomOut"] = true,
}

-- 추가 패턴 제외
local BLIZZARD_PATTERNS = {
    "^Minimap",
    "^HybridMinimap",
    "^GarrisonLanding",
}

------------------------------------------------------------------------
-- 유틸리티 -- [ESSENTIAL]
------------------------------------------------------------------------
local collectedButtons = {}
local originalData = {} -- 원본 위치/크기 저장
local barFrame, toggleButton
local barVisible = true

local function IsBlizzardFrame(name)
    if not name then return true end
    if BLIZZARD_WHITELIST[name] then return true end
    for _, pattern in ipairs(BLIZZARD_PATTERNS) do
        if name:match(pattern) then return true end
    end
    return false
end

local function IsValidButton(frame)
    if not frame then return false end
    if not frame:IsObjectType("Button") and not frame:IsObjectType("Frame") then return false end
    if not frame:HasScript("OnClick") then return false end
    if not frame:IsShown() then return false end
    local name = frame:GetName()
    if not name then return false end
    if IsBlizzardFrame(name) then return false end
    -- 이미 수집된 버튼 방지
    if originalData[name] then return false end
    return true
end

local function SkinButton(btn, size)
    local name = btn:GetName()
    if not name then return end

    -- 원본 정보 저장
    local point, relativeTo, relativePoint, xOfs, yOfs = btn:GetPoint(1)
    originalData[name] = {
        parent = btn:GetParent(),
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs,
        width = btn:GetWidth(),
        height = btn:GetHeight(),
    }

    btn:SetParent(barFrame)
    btn:SetSize(size, size)
    btn:SetFrameLevel(barFrame:GetFrameLevel() + 2)

    -- 아이콘 정리: overlay/border 숨기고 아이콘 texcoord 정리
    for _, region in next, { btn:GetRegions() } do
        if region and region:IsObjectType("Texture") then
            local texName = region:GetName()
            local drawLayer = region:GetDrawLayer()
            if drawLayer == "OVERLAY" or drawLayer == "BORDER" then
                region:SetTexture(nil)
                region:Hide()
            elseif drawLayer == "BACKGROUND" or drawLayer == "ARTWORK" then
                local tex = region:GetTexture()
                if tex and type(tex) == "string" then
                    local lower = tex:lower()
                    if lower:find("border") or lower:find("overlay") or lower:find("highlight") then
                        region:SetTexture(nil)
                        region:Hide()
                    else
                        region:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                        region:ClearAllPoints()
                        region:SetAllPoints(btn)
                    end
                elseif tex and type(tex) == "number" then
                    region:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    region:ClearAllPoints()
                    region:SetAllPoints(btn)
                end
            end
        end
    end

    -- 배경 추가
    if not btn._deBarBG then
        local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetAllPoints()
        local sbg = (C and C.bg and C.bg.sidebar) or { 0.08, 0.08, 0.08, 0.95 }
        bg:SetColorTexture(sbg[1], sbg[2], sbg[3], 0.5) -- [STYLE]
        btn._deBarBG = bg
    end
end

------------------------------------------------------------------------
-- 버튼 수집 -- [ESSENTIAL]
------------------------------------------------------------------------
local function CollectButtons()
    local Minimap = _G.Minimap
    if not Minimap then return end

    -- 1. Minimap 자식 프레임에서 수집
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if IsValidButton(child) then
            table.insert(collectedButtons, child)
        end
    end

    -- 2. LibDBIcon 버튼 수집 (_G에서 "LibDBIcon10_*" 패턴)
    for name, frame in pairs(_G) do
        if type(name) == "string" and name:match("^LibDBIcon10_") then
            if type(frame) == "table" and frame.IsObjectType and IsValidButton(frame) then
                -- 중복 체크
                local found = false
                for _, btn in ipairs(collectedButtons) do
                    if btn == frame then found = true break end
                end
                if not found then
                    table.insert(collectedButtons, frame)
                end
            end
        end
    end

    -- 이름순 정렬
    table.sort(collectedButtons, function(a, b)
        return (a:GetName() or "") < (b:GetName() or "")
    end)
end

------------------------------------------------------------------------
-- 레이아웃 -- [ESSENTIAL]
------------------------------------------------------------------------
local function LayoutButtons()
    local db = ns.db and ns.db.minimapButtonBar
    if not db or not barFrame then return end

    local size = db.buttonSize or 28
    local perRow = db.buttonsPerRow or 6
    local spacing = db.spacing or 2
    local count = #collectedButtons

    if count == 0 then
        barFrame:SetSize(1, 1)
        barFrame:Hide()
        return
    end

    local cols = math.min(count, perRow)
    local rows = math.ceil(count / perRow)
    local barW = cols * size + (cols - 1) * spacing + 4
    local barH = rows * size + (rows - 1) * spacing + 4

    barFrame:SetSize(barW, barH)

    for i, btn in ipairs(collectedButtons) do
        SkinButton(btn, size)
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 2 + col * (size + spacing), -(2 + row * (size + spacing)))
    end

    if barVisible then barFrame:Show() end
end

------------------------------------------------------------------------
-- 바 생성 -- [ESSENTIAL]
------------------------------------------------------------------------
local function CreateBar()
    local db = ns.db and ns.db.minimapButtonBar
    if not db then return end

    local bgColor = (C and C.bg and C.bg.widget) or { 0.06, 0.06, 0.06, 0.80 } -- [STYLE]
    local bdColor = (C and C.border and C.border.default) or { 0.25, 0.25, 0.25, 0.50 } -- [STYLE]
    local alpha = db.backdropAlpha or 0.6

    barFrame = CreateFrame("Frame", "DDingUI_MinimapButtonBarFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    barFrame:SetSize(1, 1)
    barFrame:SetPoint("TOPRIGHT", _G.Minimap, "BOTTOMRIGHT", 0, -4)
    barFrame:SetFrameStrata("MEDIUM")
    barFrame:SetFrameLevel(10)

    if db.backdrop ~= false then
        barFrame:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
        })
        barFrame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], alpha)
        barFrame:SetBackdropBorderColor(bdColor[1], bdColor[2], bdColor[3], bdColor[4] or 1)
    end

    -- 토글 버튼 (미니맵 좌상단) -- [ESSENTIAL]
    local accentFrom = (SL and SL.GetAccent) and select(1, SL.GetAccent("Essential")) or { 1, 0.82, 0.2, 1 }

    toggleButton = CreateFrame("Button", "DDingUI_MinimapButtonBarToggle", _G.Minimap)
    toggleButton:SetSize(16, 16)
    toggleButton:SetPoint("TOPLEFT", _G.Minimap, "TOPLEFT", 4, -4)
    toggleButton:SetFrameLevel(_G.Minimap:GetFrameLevel() + 5)

    local tbg = toggleButton:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    tbg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], 0.8)
    toggleButton._bg = tbg

    local tIcon = toggleButton:CreateFontString(nil, "OVERLAY")
    tIcon:SetFont(SL_FONT, F and F.small or 11, "OUTLINE") -- [STYLE]
    tIcon:SetPoint("CENTER", 0, 0)
    tIcon:SetText("B")
    tIcon:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3], 1)
    toggleButton._icon = tIcon

    toggleButton:SetScript("OnClick", function()
        barVisible = not barVisible
        if barVisible then
            barFrame:Show()
            tIcon:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3], 1)
        else
            barFrame:Hide()
            local dim = (C and C.text and C.text.dim) or { 0.5, 0.5, 0.5, 1 }
            tIcon:SetTextColor(dim[1], dim[2], dim[3], 1)
        end
    end)

    toggleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Minimap Button Bar", 1, 1, 1)
        GameTooltip:AddLine("Click to toggle", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    toggleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Enable / Disable -- [ESSENTIAL]
------------------------------------------------------------------------
function MinimapButtonBar:Enable()
    if self._deSkinned then return end
    local db = ns.db and ns.db.minimapButtonBar
    if not db or db.enabled == false then return end

    CreateBar()

    -- 초기 수집 + 5초 후 재수집 (늦게 로드되는 애드온 대응) -- [ESSENTIAL]
    C_Timer.After(1, function()
        CollectButtons()
        LayoutButtons()
    end)

    C_Timer.After(5, function()
        -- 추가 버튼 재수집
        local prevCount = #collectedButtons
        CollectButtons()
        if #collectedButtons ~= prevCount then
            LayoutButtons()
        end
    end)

    self._deSkinned = true
end

function MinimapButtonBar:Disable()
    -- 원본 위치 복원
    for name, data in pairs(originalData) do
        local btn = _G[name]
        if btn and data.parent then
            btn:SetParent(data.parent)
            btn:ClearAllPoints()
            if data.point and data.relativeTo then
                btn:SetPoint(data.point, data.relativeTo, data.relativePoint, data.xOfs, data.yOfs)
            end
            btn:SetSize(data.width, data.height)
        end
    end
    wipe(collectedButtons)
    wipe(originalData)
    if barFrame then barFrame:Hide() end
    if toggleButton then toggleButton:Hide() end
end

-- 외부 업데이트 함수 (Config에서 호출) -- [ESSENTIAL]
function MinimapButtonBar:UpdateLayout()
    LayoutButtons()
end

------------------------------------------------------------------------
-- 등록 -- [ESSENTIAL]
------------------------------------------------------------------------
ns:RegisterModule("minimapButtonBar", MinimapButtonBar)
