-- DDingUI_Essential: Config Panel -- [ESSENTIAL-DESIGN]
-- /des 또는 /ddessential 로 설정 패널 열기
-- StyleLib 위젯만 사용, 하드코딩 금지

local _, ns = ...

------------------------------------------------------------------------
-- 상수 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local ADDON_NAME   = "Essential"
local WIDGET_WIDTH = 300
local WIDGET_GAP   = 6

------------------------------------------------------------------------
-- 상태 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local panel
local treeMenu
local pageFrames   = {}
local pageBuilders = {}
local moduleWidgets = {} -- key → { widget1, widget2, ... }

------------------------------------------------------------------------
-- 트리 메뉴 데이터 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local MENU_DATA = {
    { text = "미니맵",         key = "minimap" },
    { text = "버튼 바",        key = "minimapButtonBar" },
    { text = "채팅창",         key = "chat" },
    { text = "버프/디버프",    key = "buffs" },
    { text = "퀘스트 추적기",  key = "quest" },
    { text = "데미지 미터",    key = "meter" },
    { text = "행동 단축바",    key = "actionbars", children = {
        { text = "아이콘 스킨",    key = "actionbars.skin" },
        { text = "텍스트",         key = "actionbars.text" },
        { text = "배경/장식",      key = "actionbars.bg" },
        { text = "페이드/숨기기",  key = "actionbars.fade" },
    }},
}

------------------------------------------------------------------------
-- 헬퍼: StyleLib 참조 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local function GetSL()
    if not ns.SL then
        local sl = _G.DDingUI_StyleLib
        if sl then ns.SL = sl end
    end
    return ns.SL
end

------------------------------------------------------------------------
-- 헬퍼: 위젯 수직 레이아웃 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local function LayoutY(page, widgets)
    local yOff = 0
    for _, w in ipairs(widgets) do
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -yOff)
        w:SetPoint("RIGHT", page, "RIGHT", 0, 0)
        yOff = yOff + (w:GetHeight() or 24) + WIDGET_GAP
    end
    local totalH = math.max(yOff + 40, 400)
    page:SetHeight(totalH)
    -- 스크롤 영역 동기화 -- [ESSENTIAL-DESIGN]
    local parent = page:GetParent()
    if parent and parent.SetHeight then
        parent:SetHeight(totalH + 24)
    end
end

------------------------------------------------------------------------
-- 헬퍼: 안내 텍스트 (StyleLib 색상/폰트 사용) -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local function CreateDimText(parent, text)
    local SL = GetSL()
    if not SL then return CreateFrame("Frame", nil, parent) end
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(18)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(SL.Font.path, SL.Font.small, "")
    fs:SetPoint("LEFT", 2, 0)
    fs:SetJustifyH("LEFT")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    local c = SL.Colors.text.dim
    fs:SetTextColor(c[1], c[2], c[3], 0.7)
    fs:SetText(text)
    return f
end

------------------------------------------------------------------------
-- 헬퍼: 위젯 활성/비활성 (회색 처리) -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local function SetWidgetsEnabled(key, enabled)
    local mw = moduleWidgets[key]
    if not mw then return end
    for _, w in ipairs(mw) do
        if w.SetAlpha then w:SetAlpha(enabled and 1.0 or 0.35) end
        if w.EnableMouse then w:EnableMouse(enabled) end
    end
end

------------------------------------------------------------------------
-- 헬퍼: 카테고리 초기화 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local function ResetCategory(dbKey, pageKey)
    pageKey = pageKey or dbKey
    local defs = ns.defaults and ns.defaults[dbKey]
    if not defs or not ns.db or not ns.db[dbKey] then return end
    for k, v in pairs(defs) do
        if type(v) == "table" then
            ns.db[dbKey][k] = CopyTable(v)
        else
            ns.db[dbKey][k] = v
        end
    end
    -- 페이지 파괴 후 재빌드 -- [ESSENTIAL-DESIGN]
    if pageFrames[pageKey] then
        pageFrames[pageKey]:Hide()
        pageFrames[pageKey] = nil
    end
    moduleWidgets[pageKey] = nil
    -- ShowPage가 재빌드함 -- [ESSENTIAL-DESIGN]
    if panel and panel.contentChild then
        local page = CreateFrame("Frame", nil, panel.contentChild)
        page:SetPoint("TOPLEFT", 16, -12)
        page:SetPoint("TOPRIGHT", -16, -12)
        page:SetHeight(600)
        pageFrames[pageKey] = page
        if pageBuilders[pageKey] then
            pageBuilders[pageKey](page)
        end
        page:Show()
    end
    local _sl = GetSL() -- [STYLE]
    local _pfx = _sl and _sl.GetChatPrefix and _sl.GetChatPrefix("Essential", "Essential") or "|cffffffffDDing|r|cffffa300UI|r |cffffd133Essential|r: "
    print(_pfx .. dbKey .. " 설정이 초기화되었습니다.")
end

------------------------------------------------------------------------
-- 페이지 전환 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local function ShowPage(key)
    if not panel or not panel.contentChild then return end
    for _, p in pairs(pageFrames) do p:Hide() end
    GetSL() -- 지연 로드 대응
    local page = pageFrames[key]
    if not page then
        page = CreateFrame("Frame", nil, panel.contentChild)
        page:SetPoint("TOPLEFT", 16, -12)
        page:SetPoint("TOPRIGHT", -16, -12)
        page:SetHeight(600)
        pageFrames[key] = page
        if pageBuilders[key] then
            local ok, err = pcall(pageBuilders[key], page)
            if not ok then
                local _sl2 = GetSL() -- [STYLE]
                local _pfx2 = _sl2 and _sl2.GetChatPrefix and _sl2.GetChatPrefix("Essential", "Essential") or "|cffffffffDDing|r|cffffa300UI|r |cffffd133Essential|r: "
                print(_pfx2 .. "|cffff0000" .. key .. " 페이지 에러: " .. tostring(err) .. "|r")
            end
        end
    end
    page:Show()
end

------------------------------------------------------------------------
-- 페이지 빌더: 미니맵 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["minimap"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.minimap or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "미니맵 설정", { isFirst = true })

    w[#w+1] = SL.CreateCheckbox(page, ADDON_NAME, "모듈 활성화", db.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.minimap then ns.db.minimap.enabled = val end
            SetWidgetsEnabled("minimap", val)
        end,
    })

    w[#w+1] = CreateDimText(page, "대부분의 변경사항은 /reload 후 적용됩니다.")

    local dd = SL.CreateDropdown(page, ADDON_NAME, "모양", {
        { text = "사각형", value = "square" },
        { text = "원형",   value = "circle" },
    }, db.shape or "square", {
        width = 140,
        onChange = function(val)
            if ns.db and ns.db.minimap then ns.db.minimap.shape = val end
        end,
    })
    w[#w+1] = dd; mw[#mw+1] = dd

    local sl = SL.CreateSlider(page, ADDON_NAME, "크기", 100, 300, 10, db.size or 180, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.minimap then ns.db.minimap.size = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "버튼 숨기기", db.hideButtons == true, {
        onChange = function(val)
            if ns.db and ns.db.minimap then ns.db.minimap.hideButtons = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "마우스오버 버튼 표시", db.mouseoverButtons ~= false, {
        onChange = function(val)
            if ns.db and ns.db.minimap then ns.db.minimap.mouseoverButtons = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "시계 표시", db.clock ~= false, {
        onChange = function(val)
            if ns.db and ns.db.minimap then ns.db.minimap.clock = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "지역명 표시", db.zoneText ~= false, {
        onChange = function(val)
            if ns.db and ns.db.minimap then ns.db.minimap.zoneText = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "마우스 휠 줌", db.mouseWheel ~= false, {
        onChange = function(val)
            if ns.db and ns.db.minimap then ns.db.minimap.mouseWheel = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    -- 좌표/성능 정보 -- [ESSENTIAL-DESIGN]
    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "정보 오버레이")

    local coordDB = db.coordinates or {}
    cb = SL.CreateCheckbox(page, ADDON_NAME, "좌표 표시", coordDB.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.minimap then
                if not ns.db.minimap.coordinates then ns.db.minimap.coordinates = {} end
                ns.db.minimap.coordinates.enabled = val
            end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    local perfDB = db.performanceInfo or {}
    cb = SL.CreateCheckbox(page, ADDON_NAME, "MS/FPS 표시", perfDB.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.minimap then
                if not ns.db.minimap.performanceInfo then ns.db.minimap.performanceInfo = {} end
                ns.db.minimap.performanceInfo.enabled = val
            end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    w[#w+1] = SL.CreateButton(page, ADDON_NAME, "초기화", function()
        ResetCategory("minimap")
    end, { width = 80, height = 24 })

    LayoutY(page, w)
    moduleWidgets["minimap"] = mw
    if db.enabled == false then SetWidgetsEnabled("minimap", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 미니맵 버튼 바 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["minimapButtonBar"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.minimapButtonBar or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "미니맵 버튼 바", { isFirst = true })

    w[#w+1] = SL.CreateCheckbox(page, ADDON_NAME, "모듈 활성화", db.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.minimapButtonBar then ns.db.minimapButtonBar.enabled = val end
            SetWidgetsEnabled("minimapButtonBar", val)
        end,
    })

    w[#w+1] = CreateDimText(page, "미니맵 주변 애드온 버튼을 바에 수집합니다. /reload 필요")

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "버튼 크기", 20, 40, 2, db.buttonSize or 28, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.minimapButtonBar then ns.db.minimapButtonBar.buttonSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "열당 버튼 수", 3, 12, 1, db.buttonsPerRow or 6, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.minimapButtonBar then ns.db.minimapButtonBar.buttonsPerRow = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "버튼 간격", 0, 8, 1, db.spacing or 2, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.minimapButtonBar then ns.db.minimapButtonBar.spacing = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "배경 투명도", 0, 1, 0.05, db.backdropAlpha or 0.6, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.minimapButtonBar then ns.db.minimapButtonBar.backdropAlpha = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    w[#w+1] = SL.CreateButton(page, ADDON_NAME, "초기화", function()
        ResetCategory("minimapButtonBar")
    end, { width = 80, height = 24 })

    LayoutY(page, w)
    moduleWidgets["minimapButtonBar"] = mw
    if db.enabled == false then SetWidgetsEnabled("minimapButtonBar", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 채팅창 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["chat"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.chat or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "채팅창 설정", { isFirst = true })

    w[#w+1] = SL.CreateCheckbox(page, ADDON_NAME, "모듈 활성화", db.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.enabled = val end
            SetWidgetsEnabled("chat", val)
        end,
    })

    w[#w+1] = CreateDimText(page, "대부분의 변경사항은 /reload 후 적용됩니다.")

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "배경 투명도", 0, 1, 0.05, db.backdropAlpha or 0.75, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.backdropAlpha = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "탭 폰트 크기", 8, 16, 1, db.tabFontSize or 12, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.tabFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "입력창 폰트 크기", 8, 16, 1, db.editboxFontSize or 13, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.editboxFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "배경", db.backdrop ~= false, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.backdrop = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "입력창 스킨", db.editboxSkin ~= false, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.editboxSkin = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "스크롤 버튼 스킨", db.scrollButtonSkin ~= false, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.scrollButtonSkin = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "복사 버튼", db.copyButton ~= false, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.copyButton = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "URL 감지", db.urlDetect ~= false, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.urlDetect = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "직업 색상", db.classColors ~= false, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.classColors = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "채널명 축약", db.shortenChannels == true, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.shortenChannels = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    -- 추가 기능 -- [ESSENTIAL-DESIGN]
    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "추가 기능")

    sl = SL.CreateSlider(page, ADDON_NAME, "페이드 시간 (초)", 5, 60, 5, db.fadeTime or 30, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.fadeTime = val end
            -- 즉시 적용 -- [ESSENTIAL]
            for i = 1, NUM_CHAT_WINDOWS or 10 do
                local cf = _G["ChatFrame" .. i]
                if cf then cf:SetTimeVisible(val) end
            end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    cb = SL.CreateCheckbox(page, ADDON_NAME, "위스퍼 수신 사운드", db.whisperSound ~= false, {
        onChange = function(val)
            if ns.db and ns.db.chat then ns.db.chat.whisperSound = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    w[#w+1] = SL.CreateButton(page, ADDON_NAME, "초기화", function()
        ResetCategory("chat")
    end, { width = 80, height = 24 })

    LayoutY(page, w)
    moduleWidgets["chat"] = mw
    if db.enabled == false then SetWidgetsEnabled("chat", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 버프/디버프 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["buffs"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.buffs or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "버프/디버프 설정", { isFirst = true })

    w[#w+1] = SL.CreateCheckbox(page, ADDON_NAME, "모듈 활성화", db.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.buffs then ns.db.buffs.enabled = val end
            SetWidgetsEnabled("buffs", val)
        end,
    })

    w[#w+1] = CreateDimText(page, "대부분의 변경사항은 /reload 후 적용됩니다.")

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "아이콘 트리밍", db.iconTrim ~= false, {
        onChange = function(val)
            if ns.db and ns.db.buffs then ns.db.buffs.iconTrim = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "지속시간 폰트 크기", 8, 16, 1, db.durationFontSize or 11, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.buffs then ns.db.buffs.durationFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "스택 폰트 크기", 8, 16, 1, db.countFontSize or 12, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.buffs then ns.db.buffs.countFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    -- 레이아웃 -- [ESSENTIAL-DESIGN]
    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "레이아웃")

    sl = SL.CreateSlider(page, ADDON_NAME, "아이콘 크기", 20, 48, 2, db.iconSize or 32, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.buffs then ns.db.buffs.iconSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    local dd = SL.CreateDropdown(page, ADDON_NAME, "성장 방향", {
        { text = "왼쪽", value = "LEFT" },
        { text = "오른쪽", value = "RIGHT" },
    }, db.growDirection or "LEFT", {
        width = 140,
        onChange = function(val)
            if ns.db and ns.db.buffs then ns.db.buffs.growDirection = val end
        end,
    })
    w[#w+1] = dd; mw[#mw+1] = dd

    sl = SL.CreateSlider(page, ADDON_NAME, "줄바꿈 기준", 4, 20, 1, db.wrapAfter or 12, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.buffs then ns.db.buffs.wrapAfter = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    dd = SL.CreateDropdown(page, ADDON_NAME, "정렬 기준", {
        { text = "시간", value = "TIME" },
        { text = "순서", value = "INDEX" },
        { text = "이름", value = "NAME" },
    }, db.sortMethod or "TIME", {
        width = 140,
        onChange = function(val)
            if ns.db and ns.db.buffs then ns.db.buffs.sortMethod = val end
        end,
    })
    w[#w+1] = dd; mw[#mw+1] = dd

    w[#w+1] = SL.CreateButton(page, ADDON_NAME, "초기화", function()
        ResetCategory("buffs")
    end, { width = 80, height = 24 })

    LayoutY(page, w)
    moduleWidgets["buffs"] = mw
    if db.enabled == false then SetWidgetsEnabled("buffs", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 퀘스트 추적기 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["quest"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.quest or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "퀘스트 추적기 설정", { isFirst = true })

    w[#w+1] = SL.CreateCheckbox(page, ADDON_NAME, "모듈 활성화", db.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.quest then ns.db.quest.enabled = val end
            SetWidgetsEnabled("quest", val)
        end,
    })

    w[#w+1] = CreateDimText(page, "대부분의 변경사항은 /reload 후 적용됩니다.")

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "헤더 스킨", db.headerSkin ~= false, {
        onChange = function(val)
            if ns.db and ns.db.quest then ns.db.quest.headerSkin = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "진행바 스킨", db.progressBar ~= false, {
        onChange = function(val)
            if ns.db and ns.db.quest then ns.db.quest.progressBar = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "타이머바 스킨", db.timerBar ~= false, {
        onChange = function(val)
            if ns.db and ns.db.quest then ns.db.quest.timerBar = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    -- 크기 설정 -- [ESSENTIAL-DESIGN]
    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "크기")

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "헤더 폰트 크기", 10, 18, 1, db.headerFontSize or 14, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.quest then ns.db.quest.headerFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "항목 폰트 크기", 8, 14, 1, db.itemFontSize or 11, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.quest then ns.db.quest.itemFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "진행바 높이", 2, 12, 1, db.progressBarHeight or 4, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.quest then ns.db.quest.progressBarHeight = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    w[#w+1] = SL.CreateButton(page, ADDON_NAME, "초기화", function()
        ResetCategory("quest")
    end, { width = 80, height = 24 })

    LayoutY(page, w)
    moduleWidgets["quest"] = mw
    if db.enabled == false then SetWidgetsEnabled("quest", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 데미지 미터 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["meter"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.meter or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "데미지 미터 설정", { isFirst = true })

    w[#w+1] = SL.CreateCheckbox(page, ADDON_NAME, "모듈 활성화", db.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.meter then ns.db.meter.enabled = val end
            SetWidgetsEnabled("meter", val)
        end,
    })

    w[#w+1] = CreateDimText(page, "대부분의 변경사항은 /reload 후 적용됩니다.")

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "바 폰트 크기", 8, 14, 1, db.barFontSize or 11, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.meter then ns.db.meter.barFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "타이틀 폰트 크기", 8, 16, 1, db.titleFontSize or 12, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.meter then ns.db.meter.titleFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "바 높이", 12, 24, 1, db.barHeight or 18, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.meter then ns.db.meter.barHeight = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    -- 임베드 스킨 -- [ESSENTIAL-DESIGN]
    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "임베드 스킨")

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "임베드 스킨 (ElvUI 스타일)", db.embedSkin == true, {
        onChange = function(val)
            if ns.db and ns.db.meter then ns.db.meter.embedSkin = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "전투 시 자동 표시", db.combatShow == true, {
        onChange = function(val)
            if ns.db and ns.db.meter then ns.db.meter.combatShow = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    w[#w+1] = SL.CreateButton(page, ADDON_NAME, "초기화", function()
        ResetCategory("meter")
    end, { width = 80, height = 24 })

    LayoutY(page, w)
    moduleWidgets["meter"] = mw
    if db.enabled == false then SetWidgetsEnabled("meter", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 행동 단축바 (부모) -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["actionbars"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.actionbars or {}
    local w = {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "행동 단축바", { isFirst = true })

    w[#w+1] = SL.CreateCheckbox(page, ADDON_NAME, "모듈 활성화", db.enabled ~= false, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.enabled = val end
            -- 모든 하위 페이지 위젯 상태 전파 -- [ESSENTIAL-DESIGN]
            for _, childKey in ipairs({"actionbars", "actionbars.skin", "actionbars.text", "actionbars.bg", "actionbars.fade"}) do
                SetWidgetsEnabled(childKey, val)
            end
        end,
    })

    w[#w+1] = CreateDimText(page, "좌측 하위 메뉴에서 세부 설정을 조정할 수 있습니다.")

    w[#w+1] = SL.CreateButton(page, ADDON_NAME, "전체 초기화", function()
        ResetCategory("actionbars")
        -- 하위 페이지도 파괴 -- [ESSENTIAL-DESIGN]
        for _, childKey in ipairs({"actionbars.skin", "actionbars.text", "actionbars.bg", "actionbars.fade"}) do
            if pageFrames[childKey] then
                pageFrames[childKey]:Hide()
                pageFrames[childKey] = nil
            end
            moduleWidgets[childKey] = nil
        end
    end, { width = 100, height = 24 })

    LayoutY(page, w)
end

------------------------------------------------------------------------
-- 페이지 빌더: 행동 단축바 > 아이콘 스킨 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["actionbars.skin"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.actionbars or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "아이콘 스킨", { isFirst = true })
    w[#w+1] = CreateDimText(page, "변경사항은 /reload 후 적용됩니다.")

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "버튼 스킨 적용", db.buttonSkin ~= false, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.buttonSkin = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "아이콘 트리밍", db.iconTrim ~= false, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.iconTrim = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "아이콘 클린업 (마스크 제거)", db.cleanIcons ~= false, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.cleanIcons = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "슬롯 배경 투명도", 0, 1, 0.05, db.slotBackgroundAlpha or 0.35, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.slotBackgroundAlpha = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    cb = SL.CreateCheckbox(page, ADDON_NAME, "쿨다운 흑백 효과", db.cooldownDesaturate ~= false, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.cooldownDesaturate = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    sl = SL.CreateSlider(page, ADDON_NAME, "쿨다운 투명도", 0.3, 1, 0.05, db.cooldownDimAlpha or 0.8, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.cooldownDimAlpha = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    LayoutY(page, w)
    moduleWidgets["actionbars.skin"] = mw
    if db.enabled == false then SetWidgetsEnabled("actionbars.skin", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 행동 단축바 > 텍스트 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["actionbars.text"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.actionbars or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "텍스트", { isFirst = true })
    w[#w+1] = CreateDimText(page, "변경사항은 /reload 후 적용됩니다.")

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "쿨다운 폰트 크기", 8, 18, 1, db.cooldownFontSize or 14, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.cooldownFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "키바인드 폰트 크기", 6, 14, 1, db.hotkeyFontSize or 11, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.hotkeyFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "스택 폰트 크기", 8, 18, 1, db.countFontSize or 14, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.countFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "키바인드 축약", db.shortenKeybinds ~= false, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.shortenKeybinds = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "매크로 이름 표시", db.macroName ~= false, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.macroName = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    sl = SL.CreateSlider(page, ADDON_NAME, "매크로 이름 폰트 크기", 8, 14, 1, db.macroNameFontSize or 10, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.macroNameFontSize = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    LayoutY(page, w)
    moduleWidgets["actionbars.text"] = mw
    if db.enabled == false then SetWidgetsEnabled("actionbars.text", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 행동 단축바 > 배경/장식 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["actionbars.bg"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.actionbars or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "배경/장식", { isFirst = true })
    w[#w+1] = CreateDimText(page, "변경사항은 /reload 후 적용됩니다.")

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "바 배경 표시", db.barBackground == true, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.barBackground = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "바 배경 투명도", 0, 1, 0.05, db.barBackgroundAlpha or 0.3, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.barBackgroundAlpha = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    cb = SL.CreateCheckbox(page, ADDON_NAME, "Blizzard 장식 숨기기", db.hideBlizzardArt ~= false, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.hideBlizzardArt = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    LayoutY(page, w)
    moduleWidgets["actionbars.bg"] = mw
    if db.enabled == false then SetWidgetsEnabled("actionbars.bg", false) end
end

------------------------------------------------------------------------
-- 페이지 빌더: 행동 단축바 > 페이드/숨기기 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
pageBuilders["actionbars.fade"] = function(page)
    local SL = GetSL()
    if not SL then return end
    local db = ns.db and ns.db.actionbars or {}
    local w, mw = {}, {}

    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "페이드/숨기기", { isFirst = true })
    w[#w+1] = CreateDimText(page, "변경사항은 /reload 후 적용됩니다.")

    -- 숨기기 섹션 -- [ESSENTIAL-DESIGN]
    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "바 숨기기")

    local cb
    cb = SL.CreateCheckbox(page, ADDON_NAME, "메뉴바 숨기기 (마우스오버 표시)", db.hideMenuBar == true, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.hideMenuBar = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "가방바 숨기기 (마우스오버 표시)", db.hideBagBar == true, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.hideBagBar = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    -- 페이드 섹션 -- [ESSENTIAL-DESIGN]
    w[#w+1] = SL.CreateSectionHeader(page, ADDON_NAME, "바 페이드")

    local sl
    sl = SL.CreateSlider(page, ADDON_NAME, "페이드 투명도", 0, 1, 0.05, db.fadeAlpha or 0, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.fadeAlpha = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    sl = SL.CreateSlider(page, ADDON_NAME, "페이드 시간 (초)", 0.1, 1.0, 0.1, db.fadeDuration or 0.3, {
        width = WIDGET_WIDTH,
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.fadeDuration = val end
        end,
    })
    w[#w+1] = sl; mw[#mw+1] = sl

    -- 개별 바 페이드 체크박스 -- [ESSENTIAL-DESIGN]
    local fadeBars = db.fadeBars or {}
    local barLabels = {
        { key = "MainActionBar",       text = "메인 행동바" },
        { key = "MultiBarBottomLeft",  text = "하단 좌측" },
        { key = "MultiBarBottomRight", text = "하단 우측" },
        { key = "MultiBarRight",       text = "우측 1" },
        { key = "MultiBarLeft",        text = "좌측 1" },
        { key = "MultiBar5",           text = "멀티바 5" },
        { key = "MultiBar6",           text = "멀티바 6" },
        { key = "MultiBar7",           text = "멀티바 7" },
    }

    for _, info in ipairs(barLabels) do
        cb = SL.CreateCheckbox(page, ADDON_NAME, info.text, fadeBars[info.key] == true, {
            onChange = function(val)
                if ns.db and ns.db.actionbars then
                    if not ns.db.actionbars.fadeBars then
                        ns.db.actionbars.fadeBars = {}
                    end
                    ns.db.actionbars.fadeBars[info.key] = val
                end
            end,
        })
        w[#w+1] = cb; mw[#mw+1] = cb
    end

    cb = SL.CreateCheckbox(page, ADDON_NAME, "스탠스바", db.fadeStanceBar == true, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.fadeStanceBar = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    cb = SL.CreateCheckbox(page, ADDON_NAME, "펫바", db.fadePetBar == true, {
        onChange = function(val)
            if ns.db and ns.db.actionbars then ns.db.actionbars.fadePetBar = val end
        end,
    })
    w[#w+1] = cb; mw[#mw+1] = cb

    LayoutY(page, w)
    moduleWidgets["actionbars.fade"] = mw
    if db.enabled == false then SetWidgetsEnabled("actionbars.fade", false) end
end

------------------------------------------------------------------------
-- 패널 생성 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
local function CreateConfigPanel()
    if panel then return panel end

    local SL = GetSL()
    if not SL then
        -- StyleLib 미로드 폴백 -- [ESSENTIAL-DESIGN]
        local f = CreateFrame("Frame", "DDingUIEssentialConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(300, 100)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:Hide()
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
            f:SetBackdropBorderColor(0, 0, 0, 1)
        end
        local msg = f:CreateFontString(nil, "OVERLAY")
        msg:SetFont("Fonts\\2002.TTF", 13, "")
        msg:SetPoint("CENTER")
        msg:SetText("|cffff5555DDingUI_StyleLib이 필요합니다.|r")
        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
        local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
        closeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        closeText:SetPoint("CENTER")
        closeText:SetText("X")
        closeText:SetTextColor(0.8, 0.8, 0.8)
        closeBtn:SetScript("OnClick", function() f:Hide() end)
        tinsert(UISpecialFrames, "DDingUIEssentialConfig")
        panel = { frame = f }
        return panel
    end

    -- CDM/UF 동일 규격 -- [ESSENTIAL-DESIGN]
    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata("DDingUI_Essential", "Version") or "0.3.0"

    panel = SL.CreateSettingsPanel("Essential", "DDingUI Essential", version, {
        width = 920,
        height = 620,
        minWidth = 600,
        minHeight = 400,
        menuWidth = 200,
    })

    panel.frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- 트리 메뉴 -- [ESSENTIAL-DESIGN]
    treeMenu = SL.CreateTreeMenu(panel.treeFrame, ADDON_NAME, MENU_DATA, {
        defaultKey = "minimap",
        onSelect = function(key)
            ShowPage(key)
        end,
    })

    -- OnShow: 트리 메뉴 + 페이지 리프레시 (1프레임 지연: 레이아웃 안정화) -- [ESSENTIAL-DESIGN]
    panel.frame:HookScript("OnShow", function()
        if treeMenu then
            treeMenu:SetMenuData(MENU_DATA)
            treeMenu:SetSelected(treeMenu:GetSelected() or "minimap")
        end
        C_Timer.After(0, function()
            ShowPage(treeMenu and treeMenu:GetSelected() or "minimap")
        end)
    end)

    return panel
end

------------------------------------------------------------------------
-- 슬래시 커맨드 -- [ESSENTIAL-DESIGN]
------------------------------------------------------------------------
SLASH_DDINGUIESSENTIAL1 = "/des"
SLASH_DDINGUIESSENTIAL2 = "/ddessential"

SlashCmdList["DDINGUIESSENTIAL"] = function()
    local p = CreateConfigPanel()
    if p and p.frame then
        if p.frame:IsShown() then
            p.frame:Hide()
        else
            p.frame:Show()
        end
    end
end
