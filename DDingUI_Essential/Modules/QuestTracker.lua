-- DDingUI_Essential: QuestTracker Module -- [ESSENTIAL]
-- ElvUI 수준 퀘스트 추적기 스킨: StyleLib 진행바, 타이머바, 체크마크, 아이템버튼
-- 참조: ElvUI/Game/Mainline/Skins/ObjectiveTracker.lua

local _, ns = ...

local QuestTracker = {}

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

-- 악센트 캐시 -- [ESSENTIAL]
local accentFrom

------------------------------------------------------------------------
-- 진행바 색상 그라데이션 -- [ESSENTIAL]
------------------------------------------------------------------------
local function ColorProgressBar(bar)
    if not bar or not bar.GetValue then return end
    local value = bar:GetValue()
    local _, maxVal = bar:GetMinMaxValues()
    if maxVal and maxVal > 0 then
        local perc = value / maxVal
        -- StyleLib status 색상 기반 그라데이션 (error → warning → success) -- [STYLE]
        local sErr = (C and C.status and C.status.error)   or { 0.90, 0.25, 0.25 }
        local sWrn = (C and C.status and C.status.warning) or { 0.90, 0.75, 0.20 }
        local sOk  = (C and C.status and C.status.success) or { 0.30, 0.80, 0.30 }
        local r, g, b = ns.ColorGradient(perc, sErr[1], sErr[2], sErr[3], sWrn[1], sWrn[2], sWrn[3], sOk[1], sOk[2], sOk[3])
        bar:SetStatusBarColor(r, g, b)
    end
end

------------------------------------------------------------------------
-- 진행바 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinProgressBar(tracker, keyOrBar)
    -- [ESSENTIAL] ElvUI 패턴: hooksecurefunc → (tracker, key), 직접 호출 → (nil, container)
    local container
    if tracker and tracker.usedProgressBars and keyOrBar then
        container = tracker.usedProgressBars[keyOrBar]
    else
        container = keyOrBar
    end
    if not container then return end

    -- 실제 StatusBar: container.Bar (WoW ObjectiveTracker 구조)
    local bar = container.Bar or container
    if not bar or not bar.SetStatusBarTexture then return end
    if bar._deSkinned then return end
    bar._deSkinned = true

    local db = ns.db and ns.db.quest or {}
    bar:SetStatusBarTexture(FLAT)
    bar:SetHeight(db.progressBarHeight or 4)

    -- 배경 바 -- [ESSENTIAL]
    if not bar._deBG then
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(FLAT)
        local r, g, b, a = Unpack(GetC("bg", "input"), 0.12, 0.12, 0.12, 0.8)
        bg:SetVertexColor(r, g, b, a)
        bar._deBG = bg
    end

    -- StyleLib 테두리 -- [ESSENTIAL]
    ns.CreateBorder(bar)

    -- Blizzard 장식 텍스처 숨기기 (container에 있을 수 있음) -- [ESSENTIAL]
    for _, obj in ipairs({container, bar}) do
        if obj.BarBG then obj.BarBG:SetTexture(nil) end
        if obj.BarFrame then obj.BarFrame:Hide() end
        if obj.BarFrame2 then obj.BarFrame2:Hide() end
        if obj.BarFrame3 then obj.BarFrame3:Hide() end
        if obj.BarGlow then obj.BarGlow:Hide() end
        if obj.Sheen then obj.Sheen:Hide() end
        if obj.Starburst then obj.Starburst:Hide() end
        if obj.IconBG then obj.IconBG:SetTexture(nil) end
    end

    -- 아이콘 (bar 또는 container에 있을 수 있음) -- [ESSENTIAL]
    local icon = bar.Icon or container.Icon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
        icon:SetSize(14, 14)
    end

    -- 라벨 폰트 -- [ESSENTIAL]
    local label = bar.Label or container.Label
    if label then
        ns.SetFont(label, F and F.small or 11, "OUTLINE")
    end

    -- 초기 색상 + 값 변경 시 재적용 -- [ESSENTIAL]
    ColorProgressBar(bar)
    if not bar._deHooked then
        bar._deHooked = true
        bar:HookScript("OnValueChanged", function(self)
            ColorProgressBar(self)
        end)
    end
end

------------------------------------------------------------------------
-- 아이템 버튼 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinItemButton(button)
    if not button or button._deSkinned then return end
    button._deSkinned = true

    -- Blizzard 텍스처 숨기기 -- [ESSENTIAL]
    if button.NormalTexture then button.NormalTexture:SetTexture(nil) end
    if button.PushedTexture then button.PushedTexture:SetTexture(nil) end
    if button.HighlightTexture then button.HighlightTexture:SetTexture(nil) end

    -- 아이콘 텍스코드 -- [ESSENTIAL]
    local icon = button.icon or button.Icon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDrawLayer("ARTWORK")
    end

    -- StyleLib 테두리 -- [ESSENTIAL]
    ns.CreateBorder(button)

    -- 쿨다운 카운트 폰트 -- [ESSENTIAL]
    local cooldown = button.Cooldown or button.cooldown
    if cooldown then
        local cd = cooldown:GetRegions()
        if cd and cd.SetFont then
            ns.SetFont(cd, F and F.small or 11, "OUTLINE")
        end
    end

    -- 스택 카운트 폰트 -- [ESSENTIAL]
    local count = button.Count or button.count
    if count and count.SetFont then
        ns.SetFont(count, F and F.small or 11, "OUTLINE")
    end
end

------------------------------------------------------------------------
-- 체크마크 스킨 (악센트 색상 사용) -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinCheckMark(check)
    if not check or check._deSkinned then return end
    check._deSkinned = true

    if check.SetVertexColor then
        -- 악센트 from 색상 사용 (Essential accent) -- [ESSENTIAL-DESIGN]
        if accentFrom then
            check:SetVertexColor(accentFrom[1], accentFrom[2], accentFrom[3], 1.0)
        else
            local r, g, b = Unpack(GetC("status", "success"), 0.30, 0.85, 0.45)
            check:SetVertexColor(r, g, b, 1.0)
        end
    end
    if check.SetDesaturated then
        check:SetDesaturated(true)
    end
end

------------------------------------------------------------------------
-- 타이머바 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinTimerBar(tracker, keyOrBar)
    -- [ESSENTIAL] ElvUI 패턴: hooksecurefunc → (tracker, key), 직접 호출 → (nil, container)
    local container
    if tracker and tracker.usedTimerBars and keyOrBar then
        container = tracker.usedTimerBars[keyOrBar]
    else
        container = keyOrBar
    end
    if not container then return end

    local bar = container.Bar or container
    if not bar or not bar.SetStatusBarTexture then return end
    if bar._deSkinned then return end
    bar._deSkinned = true

    local dbT = ns.db and ns.db.quest or {}
    bar:SetStatusBarTexture(FLAT)
    bar:SetHeight(dbT.progressBarHeight or 4)

    -- 배경 -- [ESSENTIAL]
    if not bar._deBG then
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(FLAT)
        local r, g, b, a = Unpack(GetC("bg", "input"), 0.12, 0.12, 0.12, 0.8)
        bg:SetVertexColor(r, g, b, a)
        bar._deBG = bg
    end

    -- 테두리 -- [ESSENTIAL]
    ns.CreateBorder(bar)

    -- Blizzard 프레임 숨기기 -- [ESSENTIAL]
    for _, obj in ipairs({container, bar}) do
        if obj.BarBG then obj.BarBG:SetTexture(nil) end
        if obj.BarFrame then obj.BarFrame:Hide() end
    end

    -- 타이머바 색상: StyleLib status.warning -- [ESSENTIAL]
    local r, g, b = Unpack(GetC("status", "warning"), 0.90, 0.60, 0.15)
    bar:SetStatusBarColor(r, g, b, 1.0)

    -- 라벨 폰트 -- [ESSENTIAL]
    local label = bar.Label or container.Label
    if label then
        ns.SetFont(label, dbT.itemFontSize or 11, "OUTLINE")
    end
end

------------------------------------------------------------------------
-- 블록 내부 요소 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinBlock(block)
    if not block then return end

    local db = ns.db and ns.db.quest or {}
    local itemFS = db.itemFontSize or 11

    -- 아이템 버튼 -- [ESSENTIAL]
    local itemBtn = block.ItemButton or block.itemButton
    if itemBtn then SkinItemButton(itemBtn) end

    -- 현재 라인 체크마크 + 폰트 -- [ESSENTIAL]
    if block.currentLine then
        if block.currentLine.Check then SkinCheckMark(block.currentLine.Check) end
        if block.currentLine.Text then ns.SetFont(block.currentLine.Text, itemFS, "") end
    end

    -- usedLines 내 체크마크 + 폰트 순회 -- [ESSENTIAL]
    if block.usedLines then
        for _, line in pairs(block.usedLines) do
            if line.Check then SkinCheckMark(line.Check) end
            if line.Text then ns.SetFont(line.Text, itemFS, "") end
        end
    end
end

------------------------------------------------------------------------
-- 개별 Tracker 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinTracker(tracker)
    if not tracker or tracker._deSkinned then return end
    tracker._deSkinned = true

    local db = ns.db and ns.db.quest or {}

    -- 헤더 배경 제거 -- [ESSENTIAL]
    if db.headerSkin ~= false and tracker.Header then
        local header = tracker.Header
        if header.Background then
            header.Background:SetAtlas(nil)
            header.Background:Hide()
        end
        if header.Text then
            local r, g, b = Unpack(GetC("text", "highlight"), 0.9, 0.9, 0.9)
            header.Text:SetTextColor(r, g, b)
            ns.SetFont(header.Text, db.headerFontSize or 14, "") -- [ESSENTIAL] DB 크기 적용
        end
    end

    -- 진행바 Hook -- [ESSENTIAL]
    if db.progressBar ~= false and tracker.GetProgressBar then
        hooksecurefunc(tracker, "GetProgressBar", SkinProgressBar)
    end

    -- 타이머바 Hook -- [ESSENTIAL]
    if db.timerBar ~= false and tracker.GetTimerBar then
        hooksecurefunc(tracker, "GetTimerBar", SkinTimerBar)
    end

    -- 블록 추가 시 스킨 Hook -- [ESSENTIAL]
    if tracker.AddBlock then
        hooksecurefunc(tracker, "AddBlock", function(self, block)
            SkinBlock(block)
        end)
    end
end

------------------------------------------------------------------------
-- 기존 진행바/타이머바 소급 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function RetroSkinBars(tracker)
    if not tracker then return end

    if tracker.usedProgressBars then
        for _, container in pairs(tracker.usedProgressBars) do
            SkinProgressBar(nil, container)
        end
    end

    if tracker.usedTimerBars then
        for _, container in pairs(tracker.usedTimerBars) do
            SkinTimerBar(nil, container)
        end
    end
end

------------------------------------------------------------------------
-- 메인 헤더 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinMainHeader()
    local otf = _G.ObjectiveTrackerFrame
    if not otf or not otf.Header then return end

    local db = ns.db and ns.db.quest or {}
    if db.headerSkin == false then return end

    local header = otf.Header

    if header.Background then
        header.Background:SetAtlas(nil)
        header.Background:Hide()
    end

    -- 최소화 버튼 -- [ESSENTIAL]
    local minBtn = header.MinimizeButton
    if minBtn and not minBtn._deSkinned then
        minBtn._deSkinned = true
        minBtn:SetSize(16, 16)
        minBtn:SetHitRectInsets(-5, -5, -5, -5)
    end

    -- 제목 텍스트 색상 + 크기 -- [ESSENTIAL]
    if header.Text then
        local r, g, b = Unpack(GetC("text", "highlight"), 0.9, 0.9, 0.9)
        header.Text:SetTextColor(r, g, b)
        ns.SetFont(header.Text, db.headerFontSize or 14, "")
    end
end

------------------------------------------------------------------------
-- 모든 Tracker 순회 및 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinObjectiveTracker()
    SkinMainHeader()

    -- WoW 12.x 트래커 목록 (ElvUI 참조: InitiativeTasksObjectiveTracker 추가) -- [ESSENTIAL]
    local trackers = {
        _G.ScenarioObjectiveTracker,
        _G.UIWidgetObjectiveTracker,
        _G.CampaignQuestObjectiveTracker,
        _G.QuestObjectiveTracker,
        _G.AdventureObjectiveTracker,
        _G.AchievementObjectiveTracker,
        _G.MonthlyActivitiesObjectiveTracker,
        _G.ProfessionsRecipeTracker,
        _G.BonusObjectiveTracker,
        _G.WorldQuestObjectiveTracker,
        _G.InitiativeTasksObjectiveTracker, -- ElvUI 참조 추가
        _G.ContentTrackingTracker,           -- 추가 트래커
    }

    for _, tracker in ipairs(trackers) do
        if tracker then
            SkinTracker(tracker)
            RetroSkinBars(tracker)
        end
    end

    -- 기존 배경 프레임 제거 -- [ESSENTIAL]
    local otf = _G.ObjectiveTrackerFrame
    if otf and otf._deBg then
        otf._deBg:Hide()
        otf._deBg = nil
    end
end

------------------------------------------------------------------------
-- Enable / Disable -- [ESSENTIAL]
------------------------------------------------------------------------
function QuestTracker:Enable()
    -- StyleLib 재확인 -- [ESSENTIAL]
    if not SL then
        SL = _G.DDingUI_StyleLib
        C = SL and SL.Colors
        F = SL and SL.Font
        FLAT = SL and SL.Textures and SL.Textures.flat or FLAT
    end

    -- 악센트 캐시 -- [ESSENTIAL]
    if SL and SL.GetAccent then
        local from = SL.GetAccent("Essential")
        accentFrom = from
    end

    if C_AddOns.IsAddOnLoaded("Blizzard_ObjectiveTracker") then
        SkinObjectiveTracker()
    else
        EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", SkinObjectiveTracker)
    end
end

function QuestTracker:Disable()
    -- ReloadUI 필요 -- [ESSENTIAL]
end

ns:RegisterModule("quest", QuestTracker)
