-- DDingUI_Essential: DamageMeter Module -- [ESSENTIAL]
-- ElvUI 수준 Details!/Recount 프레임 스킨: StyleLib 통일, 바 텍스처/폰트/백드롭
-- 참조: ElvUI/Game/Mainline/Skins/DamageMeter.lua

local _, ns = ...

local DamageMeter = {}

------------------------------------------------------------------------
-- StyleLib 참조 -- [ESSENTIAL]
------------------------------------------------------------------------
local SL      = _G.DDingUI_StyleLib
local C       = SL and SL.Colors
local F       = SL and SL.Font
local FLAT    = SL and SL.Textures and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"

local function GetC(category, key)
    return (C and C[category] and C[category][key]) or nil
end

local function Unpack(tbl, fr, fg, fb, fa)
    if tbl then return tbl[1], tbl[2], tbl[3], tbl[4] or 1 end
    return fr or 0.1, fg or 0.1, fb or 0.1, fa or 0.9
end

------------------------------------------------------------------------
-- 상수 -- [ESSENTIAL]
------------------------------------------------------------------------
local MAX_DETAILS_INSTANCES = 10
local MAX_RECOUNT_ROWS     = 50
local WAIT_INTERVAL        = 3
local BAR_FONT_FLAGS       = ""
local TITLE_FONT_FLAGS     = "OUTLINE"

-- DB에서 읽는 설정값 (Enable 시 갱신) -- [ESSENTIAL]
local BAR_FONT_SIZE        = 11
local TITLE_FONT_SIZE      = 12
local BAR_HEIGHT           = 18

-- 훅 중복 방지 -- [ESSENTIAL]
local detailsHooked  = false
local recountHooked  = false

-- 임베드 스킨 -- [ESSENTIAL]
local embedFrame, embedEventFrame

------------------------------------------------------------------------
-- 백드롭 헬퍼 (ns.CreateBackdrop 활용) -- [ESSENTIAL]
------------------------------------------------------------------------
local function ApplyMeterBackdrop(frame, bgPath, borderPath)
    if not frame then return end
    ns.StripTextures(frame)
    local bgColor = {Unpack(GetC(bgPath or "bg", "sidebar"), 0.08, 0.08, 0.08, 0.95)} -- [STYLE]
    local bdColor = {Unpack(GetC(borderPath or "border", "default"), 0.3, 0.3, 0.3, 0.5)}
    ns.CreateBackdrop(frame, bgColor, bdColor)
end

------------------------------------------------------------------------
-- 타이틀바 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinTitleBar(frame)
    if not frame then return end
    ns.StripTextures(frame)
    local bgColor = {Unpack(GetC("bg", "titlebar"), 0.12, 0.12, 0.12, 0.98)} -- [STYLE]
    local bdColor = {Unpack(GetC("border", "separator"), 0.20, 0.20, 0.20, 0.40)} -- [STYLE]
    ns.CreateBackdrop(frame, bgColor, bdColor)
end

------------------------------------------------------------------------
-- Enable -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:Enable()
    -- StyleLib 재확인 -- [ESSENTIAL]
    if not SL then
        SL = _G.DDingUI_StyleLib
        C = SL and SL.Colors
        F = SL and SL.Font
        FLAT = SL and SL.Textures and SL.Textures.flat or FLAT
    end

    -- DB 설정 -- [ESSENTIAL]
    local db = ns.db and ns.db.meter or {}
    BAR_FONT_SIZE   = db.barFontSize or (F and F.small or 11)
    TITLE_FONT_SIZE = db.titleFontSize or 12
    BAR_HEIGHT      = db.barHeight or 18

    -- 즉시 감지 -- [ESSENTIAL]
    if self:TrySkinDetails() then
        self:SetupEmbedSkin()
        return
    end
    if self:TrySkinRecount() then return end

    -- 지연 로드 대기 -- [ESSENTIAL]
    local waitFrame = CreateFrame("Frame")
    local elapsed = 0

    waitFrame:RegisterEvent("ADDON_LOADED")
    waitFrame:SetScript("OnEvent", function(self2, event, addonName)
        if addonName == "Details" or addonName == "Details_EncounterDetails"
           or addonName == "Details_DataStorage" then
            C_Timer.After(0.5, function()
                if DamageMeter:TrySkinDetails() then
                    DamageMeter:SetupEmbedSkin()
                    self2:SetScript("OnUpdate", nil)
                    self2:UnregisterAllEvents()
                end
            end)
        elseif addonName == "Recount" then
            C_Timer.After(0.5, function()
                if DamageMeter:TrySkinRecount() then
                    self2:SetScript("OnUpdate", nil)
                    self2:UnregisterAllEvents()
                end
            end)
        end
    end)

    -- [PERF] OnUpdate 폴링 → C_Timer 기반 재시도 (매 프레임 실행 방지)
    local maxWait = 15
    local retryInterval = WAIT_INTERVAL or 3
    local retryAttempt = 0
    local maxAttempts = math.floor(maxWait / retryInterval)
    local function TryDetect()
        retryAttempt = retryAttempt + 1
        if DamageMeter:TrySkinDetails() or DamageMeter:TrySkinRecount() then
            waitFrame:UnregisterAllEvents()
            return
        end
        if retryAttempt < maxAttempts then
            C_Timer.After(retryInterval, TryDetect)
        else
            waitFrame:UnregisterAllEvents()
        end
    end
    C_Timer.After(retryInterval, TryDetect)
end

------------------------------------------------------------------------
-- Details! 감지 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:TrySkinDetails()
    local Details = _G.Details
    if not Details then return false end
    self:SkinAllDetailsInstances()
    self:HookDetails()
    return true
end

------------------------------------------------------------------------
-- Details! 전체 인스턴스 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:SkinAllDetailsInstances()
    local Details = _G.Details
    if not Details then return end

    local count = MAX_DETAILS_INSTANCES
    if Details.GetNumInstances then
        count = math.max(Details:GetNumInstances() or 0, MAX_DETAILS_INSTANCES)
    elseif Details.GetOpenedWindowsAmount then
        count = math.max(Details:GetOpenedWindowsAmount() or 0, MAX_DETAILS_INSTANCES)
    end

    for i = 1, count do
        local instance = Details:GetInstance(i)
        if instance then
            self:SkinDetailsInstance(instance)
        end
    end
end

------------------------------------------------------------------------
-- Details! 훅 설정 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:HookDetails()
    if detailsHooked then return end
    local Details = _G.Details
    if not Details then return end
    detailsHooked = true

    if Details.InstanceRefreshRows then
        hooksecurefunc(Details, "InstanceRefreshRows", function(_, instance)
            if type(instance) == "table" and instance.barras then
                DamageMeter:SkinDetailsBars(instance)
            end
        end)
    end

    if Details.InstanceInit then
        hooksecurefunc(Details, "InstanceInit", function(_, instance)
            if type(instance) == "table" then
                C_Timer.After(0.2, function()
                    DamageMeter:SkinDetailsInstance(instance)
                end)
            end
        end)
    end

    if Details.SetBarSettings then
        hooksecurefunc(Details, "SetBarSettings", function()
            DamageMeter:SkinAllDetailsInstances()
        end)
    end

    if Details.ApplyProfile then
        hooksecurefunc(Details, "ApplyProfile", function()
            C_Timer.After(0.5, function()
                DamageMeter:SkinAllDetailsInstances()
            end)
        end)
    end
end

------------------------------------------------------------------------
-- Details! 개별 인스턴스 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:SkinDetailsInstance(instance)
    if not instance then return end

    -- 1. 메인 배경 -- [ESSENTIAL]
    local baseframe = instance.baseframe
    if baseframe and not baseframe._deSkinned then
        baseframe._deSkinned = true
        ApplyMeterBackdrop(baseframe)
    end

    -- 2. bgframe 투명화 -- [ESSENTIAL]
    local bgframe = instance.bgframe
    if bgframe then
        ns.StripTextures(bgframe)
        if bgframe.SetBackdropColor then bgframe:SetBackdropColor(0, 0, 0, 0) end
        if bgframe.SetBackdropBorderColor then bgframe:SetBackdropBorderColor(0, 0, 0, 0) end
    end

    -- 3. 타이틀바 -- [ESSENTIAL]
    local toolbar = instance.toolbar_side
    if type(toolbar) == "table" and toolbar.SetBackdrop and not toolbar._deSkinned then
        toolbar._deSkinned = true
        SkinTitleBar(toolbar)
    end

    -- 4. floatingframe -- [ESSENTIAL]
    if instance.floatingframe and not instance.floatingframe._deSkinned then
        instance.floatingframe._deSkinned = true
        ns.StripTextures(instance.floatingframe)
    end

    -- 5. 타이틀 텍스트 폰트 -- [ESSENTIAL]
    if instance.header then
        local headerTitle = instance.header.title
        if headerTitle and headerTitle.SetFont then
            ns.SetFont(headerTitle, TITLE_FONT_SIZE, TITLE_FONT_FLAGS)
        end
    end

    -- 6. 메뉴 버튼 -- [ESSENTIAL]
    self:SkinDetailsMenuButtons(instance)

    -- 7. 스크롤바 -- [ESSENTIAL]
    self:SkinDetailsScrollBar(instance)

    -- 8. 모든 바 -- [ESSENTIAL]
    self:SkinDetailsBars(instance)

    -- 9. 리사이즈 핸들 -- [ESSENTIAL]
    if instance.baseframe then
        local resize = instance.baseframe.resize or instance.baseframe.resizer
        if resize then ns.StripTextures(resize) end
    end
end

------------------------------------------------------------------------
-- Details! 바 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:SkinDetailsBars(instance)
    if not instance or not instance.barras then return end
    for _, bar in ipairs(instance.barras) do
        if bar then self:SkinSingleDetailsBar(bar) end
    end
end

function DamageMeter:SkinSingleDetailsBar(bar)
    if not bar then return end

    local statusbar = bar.statusbar
    if statusbar and statusbar.SetStatusBarTexture then -- [ESSENTIAL] 메서드 방어 체크
        statusbar:SetStatusBarTexture(FLAT)
        statusbar:SetHeight(BAR_HEIGHT)
        local bgTex = statusbar:GetStatusBarTexture()
        if bgTex then bgTex:SetTexture(FLAT) end

        if bar.background then
            bar.background:SetTexture(FLAT)
            local r, g, b = Unpack(GetC("bg", "widget"), 0.06, 0.06, 0.06) -- [STYLE]
            bar.background:SetVertexColor(r, g, b, 0.5)
        end
    end

    -- 왼쪽 텍스트 (이름) -- [ESSENTIAL]
    if bar.texto_esquerdo then
        ns.SetFont(bar.texto_esquerdo, BAR_FONT_SIZE, BAR_FONT_FLAGS)
        bar.texto_esquerdo:SetShadowOffset(1, -1)
    end

    -- 오른쪽 텍스트 (수치) -- [ESSENTIAL]
    if bar.texto_direita then
        ns.SetFont(bar.texto_direita, BAR_FONT_SIZE, BAR_FONT_FLAGS)
        bar.texto_direita:SetShadowOffset(1, -1)
    end

    -- 타임라인 텍스처 -- [ESSENTIAL]
    if bar.timeline and bar.timeline.SetTexture then
        bar.timeline:SetTexture(FLAT)
    end
end

------------------------------------------------------------------------
-- Details! 메뉴 버튼 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:SkinDetailsMenuButtons(instance)
    if not instance then return end

    local buttonNames = { "reset", "segments", "attribute", "report" }
    for _, name in ipairs(buttonNames) do
        local btn = instance[name .. "_button"] or instance["button_" .. name]
        if btn and not btn._deSkinned then
            btn._deSkinned = true
            for j = 1, btn:GetNumRegions() do
                local region = select(j, btn:GetRegions())
                if region and region.IsObjectType and region:IsObjectType("Texture") then
                    local tex = region:GetTexture()
                    if tex and type(tex) == "string" and tex:find("background") then
                        region:SetTexture(nil)
                        region:Hide()
                    end
                end
            end
        end
    end

    local closeBtn = instance.close_button or instance.closeButton
    if closeBtn and not closeBtn._deSkinned then
        closeBtn._deSkinned = true
    end
end

------------------------------------------------------------------------
-- Details! 스크롤바 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:SkinDetailsScrollBar(instance)
    if not instance then return end

    local scrollFrame = instance.baseframe and instance.baseframe.ScrollBar
    if scrollFrame and not scrollFrame._deSkinned then
        scrollFrame._deSkinned = true
        ns.StripTextures(scrollFrame)
    end

    local scrollUp = instance.baseframe and instance.baseframe.ScrollUpButton
    local scrollDown = instance.baseframe and instance.baseframe.ScrollDownButton
    if scrollUp and not scrollUp._deSkinned then
        scrollUp._deSkinned = true
        ns.StripTextures(scrollUp)
    end
    if scrollDown and not scrollDown._deSkinned then
        scrollDown._deSkinned = true
        ns.StripTextures(scrollDown)
    end
end

------------------------------------------------------------------------
-- Recount 감지 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:TrySkinRecount()
    local Recount = _G.Recount
    if not Recount then return false end
    self:SkinRecountMain()
    self:HookRecount()
    return true
end

------------------------------------------------------------------------
-- Recount 메인 창 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:SkinRecountMain()
    local Recount = _G.Recount
    if not Recount then return end

    local mainWin = Recount.MainWindow
    if mainWin and not mainWin._deSkinned then
        mainWin._deSkinned = true
        ApplyMeterBackdrop(mainWin)

        -- 타이틀 -- [ESSENTIAL]
        if mainWin.Title then
            ns.StripTextures(mainWin.Title)
            SkinTitleBar(mainWin.Title)
            local titleFs = mainWin.Title.GetFontString and mainWin.Title:GetFontString()
            if titleFs then
                ns.SetFont(titleFs, TITLE_FONT_SIZE, TITLE_FONT_FLAGS)
            elseif mainWin.Title.SetFont then
                ns.SetFont(mainWin.Title, TITLE_FONT_SIZE, TITLE_FONT_FLAGS)
            end
        end

        -- 버튼 정리 -- [ESSENTIAL]
        local btns = { mainWin.CloseButton, mainWin.ConfigButton,
                       mainWin.LeftButton, mainWin.RightButton,
                       mainWin.ResetButton, mainWin.FileButton,
                       mainWin.ReportButton }
        for _, btn in ipairs(btns) do
            if btn then ns.StripTextures(btn) end
        end

        -- 스크롤바 -- [ESSENTIAL]
        if mainWin.ScrollBar then ns.StripTextures(mainWin.ScrollBar) end
    end

    self:SkinRecountRows()
end

------------------------------------------------------------------------
-- Recount 행 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:SkinRecountRows()
    local Recount = _G.Recount
    if not Recount or not Recount.MainWindow then return end

    local rows = Recount.MainWindow.Rows
    if not rows then return end

    for i = 1, math.min(#rows, MAX_RECOUNT_ROWS) do
        if rows[i] then self:SkinSingleRecountRow(rows[i]) end
    end
end

function DamageMeter:SkinSingleRecountRow(row)
    if not row then return end

    if row.StatusBar and row.StatusBar.SetStatusBarTexture then -- [ESSENTIAL] 메서드 방어 체크
        row.StatusBar:SetStatusBarTexture(FLAT)
        row.StatusBar:SetHeight(BAR_HEIGHT)
        local bgTex = row.StatusBar:GetStatusBarTexture()
        if bgTex then bgTex:SetTexture(FLAT) end
    end

    if row.Label then
        ns.SetFont(row.Label, BAR_FONT_SIZE, BAR_FONT_FLAGS)
        row.Label:SetShadowOffset(1, -1)
    end

    if row.RightLabel then
        ns.SetFont(row.RightLabel, BAR_FONT_SIZE, BAR_FONT_FLAGS)
        row.RightLabel:SetShadowOffset(1, -1)
    end

    if row.PercentLabel then
        ns.SetFont(row.PercentLabel, BAR_FONT_SIZE - 1, BAR_FONT_FLAGS)
        row.PercentLabel:SetShadowOffset(1, -1)
    end
end

------------------------------------------------------------------------
-- Recount 훅 -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:HookRecount()
    if recountHooked then return end
    local Recount = _G.Recount
    if not Recount then return end
    recountHooked = true

    if Recount.RefreshMainWindow then
        hooksecurefunc(Recount, "RefreshMainWindow", function()
            DamageMeter:SkinRecountRows()
        end)
    end

    if Recount.ShowMainWindow then
        hooksecurefunc(Recount, "ShowMainWindow", function()
            C_Timer.After(0.1, function()
                DamageMeter:SkinRecountMain()
            end)
        end)
    end

    if Recount.ResetData then
        hooksecurefunc(Recount, "ResetData", function()
            C_Timer.After(0.3, function()
                DamageMeter:SkinRecountRows()
            end)
        end)
    end
end

------------------------------------------------------------------------
-- 임베드 스킨 (ElvUI 스타일) -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:SetupEmbedSkin()
    local db = ns.db and ns.db.meter or {}
    if not db.embedSkin then return end

    local Details = _G.Details
    if not Details then return end

    -- 임베드 컨테이너 생성 -- [ESSENTIAL]
    if not embedFrame then
        local bgColor = {Unpack(GetC("bg", "sidebar"), 0.10, 0.10, 0.12, 0.95)}
        local bdColor = {Unpack(GetC("border", "default"), 0.3, 0.3, 0.3, 0.5)}

        embedFrame = CreateFrame("Frame", "DDingUI_MeterEmbed", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        embedFrame:SetSize(300, 180)
        embedFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -4, 4)
        embedFrame:SetFrameStrata("LOW")
        embedFrame:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
        })
        embedFrame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.95)
        embedFrame:SetBackdropBorderColor(bdColor[1], bdColor[2], bdColor[3], bdColor[4] or 0.5)
    end

    -- 첫 번째 Details 인스턴스를 임베드 프레임에 맞춤 -- [ESSENTIAL]
    local instance = Details:GetInstance(1)
    if instance and instance.baseframe then
        local bf = instance.baseframe
        bf:ClearAllPoints()
        bf:SetParent(embedFrame)
        bf:SetAllPoints(embedFrame)

        -- 타이틀바 숨김
        if instance.toolbar_side and instance.toolbar_side.Hide then
            instance.toolbar_side:Hide()
        end

        -- 이동/리사이즈 잠금
        if instance.SetLocked then
            instance:SetLocked(true)
        end
        if bf.SetMovable then bf:SetMovable(false) end
        if bf.SetResizable then bf:SetResizable(false) end
    end

    -- 전투 자동 표시/숨김 -- [ESSENTIAL]
    if db.combatShow and not embedEventFrame then
        embedEventFrame = CreateFrame("Frame")
        embedEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        embedEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        embedEventFrame:SetScript("OnEvent", function(_, event)
            if not embedFrame then return end
            if event == "PLAYER_REGEN_DISABLED" then
                embedFrame:SetAlpha(1)
                embedFrame:Show()
            elseif event == "PLAYER_REGEN_ENABLED" then
                C_Timer.After(3, function()
                    if not InCombatLockdown() and embedFrame then
                        embedFrame:SetAlpha(0.3)
                    end
                end)
            end
        end)
        -- 초기 상태: 비전투 시 반투명
        if not InCombatLockdown() then
            embedFrame:SetAlpha(0.3)
        end
    end
end

------------------------------------------------------------------------
-- Disable -- [ESSENTIAL]
------------------------------------------------------------------------
function DamageMeter:Disable()
    -- 훅 해제 불가, ReloadUI 필요 -- [ESSENTIAL]
    if embedEventFrame then
        embedEventFrame:UnregisterAllEvents()
        embedEventFrame = nil
    end
end

ns:RegisterModule("meter", DamageMeter)
