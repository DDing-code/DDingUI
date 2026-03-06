-- DDingUI_Essential Core -- [ESSENTIAL]
-- 블리자드 기본 UI 스킨 애드온 (미니맵, 채팅, 버프, 퀘스트추적기, 데미지미터, 행동단축바)

local addonName, ns = ...

------------------------------------------------------------------------
-- StyleLib 로드 -- [ESSENTIAL]
------------------------------------------------------------------------
local SL = _G.DDingUI_StyleLib
local FLAT  = SL and SL.Textures and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local FONT  = SL and SL.Font and SL.Font.path or "Fonts\\2002.TTF"
local FONT_DEFAULT = SL and SL.Font and SL.Font.default or "Fonts\\FRIZQT__.TTF"

ns.SL   = SL
ns.FLAT = FLAT
ns.FONT = FONT
ns.FONT_DEFAULT = FONT_DEFAULT

------------------------------------------------------------------------
-- 색상 헬퍼 -- [ESSENTIAL]
------------------------------------------------------------------------
ns.GetColor = function(path)
    -- path: "bg.main", "border.default", "text.normal" 등
    if not SL or not SL.Colors then return 0.1, 0.1, 0.1, 0.9 end
    local parts = {strsplit(".", path)}
    local t = SL.Colors
    for _, key in ipairs(parts) do
        t = t[key]
        if not t then return 0.1, 0.1, 0.1, 0.9 end
    end
    if type(t) == "table" then
        return t[1] or 0.1, t[2] or 0.1, t[3] or 0.1, t[4] or 1
    end
    return 0.1, 0.1, 0.1, 0.9
end

ns.GetColorTable = function(path)
    local r, g, b, a = ns.GetColor(path)
    return {r, g, b, a}
end

------------------------------------------------------------------------
-- 유틸리티 -- [ESSENTIAL]
------------------------------------------------------------------------
function ns.CreateBackdrop(frame, bgColor, borderColor)
    if not frame then return end
    local bg = bgColor or {ns.GetColor("bg.main")}
    local bd = borderColor or {ns.GetColor("border.default")}

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile   = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
        })
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.9)
        frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1)
    end
end

function ns.StripTextures(frame)
    if not frame or not frame.GetRegions then return end
    for _, region in next, { frame:GetRegions() } do
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            region:SetTexture(nil)
            if region.SetAtlas then region:SetAtlas("") end
            region:Hide()
        end
    end
end

function ns.SetFont(fontString, size, flags)
    if not fontString or not fontString.SetFont then return end
    fontString:SetFont(FONT, size or 12, flags or "")
end

--- 프레임에 1px StyleLib 테두리를 생성 (백드롭과 별개)
function ns.CreateBorder(frame, color)
    if not frame or frame._deBorder then return frame._deBorder end
    local bd = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bd:SetAllPoints()
    bd:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
    bd:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    local r, g, b, a
    if color then
        r, g, b, a = color[1], color[2], color[3], color[4]
    else
        r, g, b, a = ns.GetColor("border.default")
    end
    bd:SetBackdropBorderColor(r, g, b, a or 1)
    frame._deBorder = bd
    return bd
end

--- StatusBar 진행바 색상 그라데이션 (빨강→노랑→초록)
function ns.ColorGradient(perc, ...)
    if perc >= 1 then
        return select(select('#', ...) - 2, ...)
    elseif perc <= 0 then
        return ...
    end
    local num = select('#', ...) / 3
    local segment, relperc = math.modf(perc * (num - 1))
    local r1, g1, b1, r2, g2, b2
    r1, g1, b1 = select((segment * 3) + 1, ...)
    r2, g2, b2 = select((segment * 3) + 4, ...)
    return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
end

------------------------------------------------------------------------
-- 모듈 시스템 -- [ESSENTIAL]
------------------------------------------------------------------------
ns.modules = {}

function ns:RegisterModule(name, module)
    self.modules[name] = module
end

function ns:EnableModule(name)
    local mod = self.modules[name]
    if mod and mod.Enable then
        local ok, err = pcall(mod.Enable, mod)
        if not ok then
            local _pfx = SL and SL.GetChatPrefix and SL.GetChatPrefix("Essential", "Essential") or "|cffffffffDDing|r|cffffa300UI|r |cffffd133Essential|r: " -- [STYLE]
            print(_pfx .. "|cffff0000" .. name .. " 모듈 에러: " .. tostring(err) .. "|r")
        end
    end
end

function ns:DisableModule(name)
    local mod = self.modules[name]
    if mod and mod.Disable then
        mod:Disable()
    end
end

------------------------------------------------------------------------
-- StyleLib 악센트 등록 -- [ESSENTIAL]
------------------------------------------------------------------------
if SL and SL.RegisterAddon then
    SL.RegisterAddon("Essential") -- [ESSENTIAL-DESIGN] AccentPresets.Essential 노란색 사용
end

------------------------------------------------------------------------
-- 기본 DB -- [ESSENTIAL]
------------------------------------------------------------------------
local defaults = {
    general = { -- [ESSENTIAL-DESIGN]
        scale = 1.0,
    },
    minimap = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        shape = "square",           -- 사각형/원형
        size = 180,                 -- 100~300, step 10
        hideButtons = false,        -- 미니맵 버튼 숨기기
        mouseoverButtons = true,    -- 마우스오버 시 버튼 표시
        clock = true,               -- 시계 표시
        zoneText = true,
        mouseWheel = true,
        coordinates = {             -- [ESSENTIAL] 좌표 표시
            enabled = true,
            format = "%.1f",
            updateInterval = 0.5,
        },
        performanceInfo = {         -- [ESSENTIAL] MS/FPS 표시
            enabled = true,
            showMS = true,
            showFPS = true,
            updateInterval = 1,
        },
    },
    minimapButtonBar = { -- [ESSENTIAL-DESIGN] 미니맵 버튼 바
        enabled = true,
        buttonSize = 28,            -- 20~40
        buttonsPerRow = 6,          -- 3~12
        spacing = 2,                -- 0~8
        backdrop = true,
        backdropAlpha = 0.6,        -- 0~1
    },
    chat = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        backdropAlpha = 0.75,       -- 배경 투명도 0~1
        tabFontSize = 12,           -- 탭 폰트 크기 8~16
        fadeTime = 30,              -- 페이드 시간 0~60, step 5
        editboxSkin = true,         -- 입력창 스킨
        scrollButtonSkin = true,    -- 스크롤 버튼 스킨
        -- 하위 호환 유지
        backdrop = true,
        editboxFontSize = 13,
        copyButton = true,
        urlDetect = true,
        classColors = true,
        shortenChannels = false,
        whisperSound = true,        -- [ESSENTIAL] 위스퍼 수신 사운드
    },
    buffs = { -- [ESSENTIAL-DESIGN] 기존 호환 유지
        enabled = true,
        iconTrim = true,
        durationFontSize = 11,
        countFontSize = 12,
        iconSize = 32,              -- [ESSENTIAL] 아이콘 크기 20~48
        growDirection = "LEFT",     -- [ESSENTIAL] LEFT/RIGHT
        wrapAfter = 12,             -- [ESSENTIAL] 줄바꿈 기준 4~20
        sortMethod = "TIME",        -- [ESSENTIAL] TIME/INDEX/NAME
    },
    quest = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        backdropAlpha = 0.8,        -- 배경 투명도 0~1
        headerFontSize = 14,        -- 헤더 폰트 크기 10~18
        itemFontSize = 11,          -- 항목 폰트 크기 8~14
        progressBarHeight = 4,      -- 진행바 높이 2~12
        -- 하위 호환 유지
        progressBar = true,
        timerBar = true,
        headerSkin = true,
    },
    meter = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        detailsSkin = true,         -- Details 스킨
        barHeight = 16,             -- 바 높이 12~24
        barFontSize = 11,           -- 폰트 크기 8~14
        titlebarSkin = true,        -- 타이틀바 스킨
        titleFontSize = 12,
        embedSkin = false,          -- [ESSENTIAL] ElvUI 스타일 임베드 스킨
        combatShow = false,         -- [ESSENTIAL] 전투 시 자동 표시
    },
    actionbars = { -- [ESSENTIAL-DESIGN]
        enabled = true,
        buttonSkin = true,          -- 버튼 스킨
        cooldownFontSize = 14,      -- 쿨다운 폰트 크기 8~18
        hotkeyFontSize = 11,        -- 키바인드 폰트 크기 6~14
        barBackground = false,      -- 바 배경 표시
        barBackgroundAlpha = 0.3,   -- 바 배경 투명도 0~1
        microMenuSkin = true,       -- 마이크로메뉴 스킨
        bagButtonSkin = true,       -- 가방 버튼 스킨
        -- 하위 호환 유지
        iconTrim = true,
        cleanIcons = true,
        slotBackgroundAlpha = 0.3,
        cooldownDesaturate = true,
        cooldownDimAlpha = 0.8,
        shortenKeybinds = true,
        macroName = true,
        macroNameFontSize = 10,
        macroNameMaxChars = 5,
        countFontSize = 14,
        hideBlizzardArt = true,
        fadeBars = {
            MainActionBar = false,
            MultiBarBottomLeft = false,
            MultiBarBottomRight = false,
            MultiBarRight = false,
            MultiBarLeft = false,
            MultiBar5 = false,
            MultiBar6 = false,
            MultiBar7 = false,
        },
        fadeStanceBar = false,
        fadePetBar = false,
        fadeAlpha = 0,
        fadeDuration = 0.3,
        hideMenuBar = false,
        hideBagBar = false,
    },
}

------------------------------------------------------------------------
-- 이벤트 처리 -- [ESSENTIAL]
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- SavedVariables 초기화 (이전 DDing_EssentialDB → DDingUI_EssentialDB 마이그레이션)
        if not DDingUI_EssentialDB then
            DDingUI_EssentialDB = DDing_EssentialDB or {}
            DDing_EssentialDB = nil -- 구버전 정리
        end
        local db = DDingUI_EssentialDB
        -- 딥 머지: 기존 DB에 새 키 추가 (기존 값 유지, 3단계 깊이) -- [ESSENTIAL]
        for k, v in pairs(defaults) do
            if db[k] == nil then
                db[k] = CopyTable(v)
            elseif type(v) == "table" then
                for subK, subV in pairs(v) do
                    if db[k][subK] == nil then
                        if type(subV) == "table" then
                            db[k][subK] = CopyTable(subV)
                        else
                            db[k][subK] = subV
                        end
                    elseif type(subV) == "table" and type(db[k][subK]) == "table" then
                        -- 3단계: fadeBars 등 중첩 테이블 머지 -- [ESSENTIAL]
                        for subSubK, subSubV in pairs(subV) do
                            if db[k][subK][subSubK] == nil then
                                db[k][subK][subSubK] = subSubV
                            end
                        end
                    end
                end
            end
        end
        ns.db = db
        ns.defaults = defaults -- [ESSENTIAL-DESIGN] Config.lua Reset 참조용

    elseif event == "PLAYER_LOGIN" then
        -- StyleLib 재확인 (다른 애드온이 나중에 로드될 수 있음)
        if not SL then
            SL = _G.DDingUI_StyleLib
            ns.SL = SL
            if SL then
                FLAT = SL.Textures and SL.Textures.flat or FLAT
                FONT = SL.Font and SL.Font.path or FONT
                ns.FLAT = FLAT
                ns.FONT = FONT
                -- 악센트 재등록 -- [ESSENTIAL-DESIGN]
                if SL.RegisterAddon then
                    SL.RegisterAddon("Essential") -- AccentPresets.Essential 노란색 사용
                end
            end
        end

        -- 모듈 활성화
        for name, mod in pairs(ns.modules) do
            local dbEntry = ns.db[name]
            if dbEntry and dbEntry.enabled ~= false then
                ns:EnableModule(name)
            end
        end

        -- [CONTROLLER] MediaChanged 콜백 등록
        if SL and SL.RegisterCallback then
            SL.RegisterCallback(ns, "MediaChanged", function()
                -- 폰트/텍스처 변수 갱신
                SL = _G.DDingUI_StyleLib
                ns.SL = SL
                FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
                FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
                FONT_DEFAULT = (SL and SL.Font and SL.Font.default) or "Fonts\\FRIZQT__.TTF"
                ns.FLAT = FLAT
                ns.FONT = FONT
                ns.FONT_DEFAULT = FONT_DEFAULT
            end)
        end

        self:UnregisterAllEvents()
    end
end)

ns.frame = frame
