-- DDingUI_Essential: Chat Module -- [ESSENTIAL]
-- ElvUI 수준 채팅 프레임 스킨
-- 1. 패널 시스템 (탭+메시지+에디트박스 통합)
-- 2. 탭 스타일 (악센트 인디케이터, 호버 배경, 플래시)
-- 3. EditBox 하단 배치 + 스킨
-- 4. 복사 버튼 (우상단 -> 전체화면 복사 프레임)
-- 5. URL 감지/링크화 (http/https/www -> 클릭 시 복사 팝업)
-- 6. 직업 색상 (플레이어 이름 직업별 색상) -- [CHATTYNATOR]
-- 7. 채널명 축약 ([길드] -> G. 등) -- [CHATTYNATOR]
-- 8. 탭 플래시 (새 메시지 알림) -- [CHATTYNATOR]
-- 9. 블리자드 UI 요소 완전 제거
-- 10. 패널 단위 페이드

local _, ns = ...

local Chat = {}

------------------------------------------------------------------------
-- StyleLib 참조 -- [ESSENTIAL]
------------------------------------------------------------------------
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local C  = SL and SL.Colors
local F  = SL and SL.Font
local FLAT     = SL and SL.Textures and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local SL_FONT  = F and F.path or "Fonts\\2002.TTF"
local FONT_DEFAULT = F and F.default or "Fonts\\FRIZQT__.TTF"

------------------------------------------------------------------------
-- Constants -- [ESSENTIAL]
------------------------------------------------------------------------
local NUM_CHAT_FRAMES = NUM_CHAT_WINDOWS or 10
local COPY_BTN_SIZE      = 18
local PANEL_PADDING      = 4       -- 패널 여백 -- [ESSENTIAL-DESIGN]
local EDITBOX_HEIGHT     = 22      -- 에디트박스 높이
local SEPARATOR_HEIGHT   = 1       -- 구분선 높이

-- DB에서 읽는 설정값 (Enable 시 갱신) -- [ESSENTIAL]
local TAB_FONT_SIZE      = 12
local EDITBOX_FONT_SIZE  = 13
local BACKDROP_ALPHA     = 0.75

-- 악센트 캐시 (Enable 시 갱신) -- [ESSENTIAL]
local accentFrom, accentTo, accentLight, accentDark
local accentHex = "|cffffd133" -- [ESSENTIAL-DESIGN] 폴백 노란색 (Essential accent)

------------------------------------------------------------------------
-- 색상 헬퍼 (SL.Colors 딥 nil 체크) -- [ESSENTIAL]
------------------------------------------------------------------------
local function GetC(category, key)
    return (C and C[category] and C[category][key]) or nil
end

local function Unpack(tbl, fallR, fallG, fallB, fallA)
    if tbl then return tbl[1], tbl[2], tbl[3], tbl[4] or 1 end
    return fallR or 0.1, fallG or 0.1, fallB or 0.1, fallA or 0.9
end

------------------------------------------------------------------------
-- URL 패턴 (Chattynator 개선 패턴 참고) -- [CHATTYNATOR]
------------------------------------------------------------------------
local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://%S+)",           -- X://Y -- [CHATTYNATOR]
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",   -- www.X.Y/path -- [CHATTYNATOR]
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",       -- www.X.Y -- [CHATTYNATOR]
}

------------------------------------------------------------------------
-- 채널명 축약 매핑 -- [CHATTYNATOR]
------------------------------------------------------------------------
local CHANNEL_ABBREVS = {
    ["GUILD"]                  = "G",
    ["OFFICER"]                = "O",
    ["PARTY"]                  = "P",
    ["PARTY_LEADER"]           = "PL",
    ["RAID"]                   = "R",
    ["RAID_LEADER"]            = "RL",
    ["RAID_WARNING"]           = "RW",
    ["INSTANCE_CHAT"]          = "I",
    ["INSTANCE_CHAT_LEADER"]   = "IL",
    ["SAY"]                    = "S",
    ["YELL"]                   = "Y",
    ["WHISPER"]                = "W",
    ["WHISPER_INFORM"]         = "W",
    ["BN_WHISPER"]             = "BN",
    ["BN_WHISPER_INFORM"]      = "BN",
}

------------------------------------------------------------------------
-- 직업 색상 캐시 -- [CHATTYNATOR]
------------------------------------------------------------------------
local classColorCache = {}
local function GetClassColorHex(classToken)
    if not classToken then return nil end
    if classColorCache[classToken] then return classColorCache[classToken] end
    local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
    if color then
        local hex = string.format("|cff%02x%02x%02x",
            math.floor(color.r * 255 + 0.5),
            math.floor(color.g * 255 + 0.5),
            math.floor(color.b * 255 + 0.5))
        classColorCache[classToken] = hex
        return hex
    end
    return nil
end

------------------------------------------------------------------------
-- StaticPopup 정의 (URL 복사용) -- [ESSENTIAL]
------------------------------------------------------------------------
StaticPopupDialogs["DDINGUI_URL_COPY"] = {
    text = "URL (Ctrl+C)",
    button1 = CLOSE or "닫기",
    hasEditBox = true,
    editBoxWidth = 350,
    maxLetters = 0,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox -- [ESSENTIAL]
        if eb then
            eb:SetText(data or "")
            eb:HighlightText()
            eb:SetFocus()
        end
        if eb and eb.SetBackdrop then
            eb:SetBackdrop({
                bgFile   = FLAT,
                edgeFile = FLAT,
                edgeSize = 1,
            })
            eb:SetBackdropColor(Unpack(GetC("bg", "input"), 0.06, 0.06, 0.06, 0.8))
            eb:SetBackdropBorderColor(Unpack(GetC("border", "default"), 0.25, 0.25, 0.25, 0.5))
        end
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------------------
-- 전체화면 복사 프레임 (Chattynator CopyChat 참고) -- [CHATTYNATOR]
------------------------------------------------------------------------
local copyFrame

local function CreateCopyFrame()
    if copyFrame then return copyFrame end

    local f = CreateFrame("Frame", "DDingUI_ChatCopyFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(700, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()
    tinsert(UISpecialFrames, "DDingUI_ChatCopyFrame")

    -- 백드롭 -- [ESSENTIAL]
    ns.CreateBackdrop(f,
        {Unpack(GetC("bg", "main"), 0.10, 0.10, 0.10, 0.95)},
        {0, 0, 0, 1})

    -- 타이틀 바 (드래그용) -- [ESSENTIAL]
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    -- 타이틀 배경 -- [ESSENTIAL]
    local titleBG = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBG:SetAllPoints()
    titleBG:SetTexture(FLAT)
    titleBG:SetVertexColor(Unpack(GetC("bg", "titlebar"), 0.12, 0.12, 0.12, 0.98))

    -- 악센트 라인 (타이틀 상단 2px) -- [ESSENTIAL]
    if SL and SL.CreateHorizontalGradient and accentFrom and accentTo then
        local grad = SL.CreateHorizontalGradient(titleBar, accentFrom, accentTo, 2)
        grad:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
        grad:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 0, 0)
    end

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(SL_FONT, F and F.normal or 13, "")
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetTextColor(Unpack(GetC("text", "highlight"), 1, 1, 1, 1))
    titleText:SetText("Ctrl+C 로 복사")
    titleText:SetShadowOffset(1, -1)

    -- 닫기 버튼 -- [ESSENTIAL]
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(28, 24)
    closeBtn:SetPoint("TOPRIGHT", -4, -2)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTex:SetFont(FONT_DEFAULT, F and F.normal or 13, "OUTLINE")
    closeTex:SetPoint("CENTER")
    closeTex:SetText("X")
    closeTex:SetTextColor(Unpack(GetC("text", "dim"), 0.6, 0.6, 0.6, 1))
    closeBtn:SetScript("OnEnter", function()
        closeTex:SetTextColor(Unpack(GetC("status", "error"), 0.90, 0.25, 0.25, 1))
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetTextColor(Unpack(GetC("text", "dim"), 0.6, 0.6, 0.6, 1))
    end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- 스크롤 EditBox -- [CHATTYNATOR]
    local scrollFrame = CreateFrame("ScrollFrame", "DDingUI_ChatCopyScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)

    local editBox = CreateFrame("EditBox", "DDingUI_ChatCopyEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(SL_FONT, F and F.normal or 13, "") -- [STYLE]
    editBox:SetWidth(scrollFrame:GetWidth() or 640)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    editBox:SetTextColor(Unpack(GetC("text", "normal"), 0.85, 0.85, 0.85, 1))
    scrollFrame:SetScrollChild(editBox)

    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        editBox:SetWidth(w)
    end)

    -- 스크롤바 심플 스킨 -- [ESSENTIAL]
    local scrollBar = scrollFrame.ScrollBar or _G["DDingUI_ChatCopyScrollScrollBar"]
    if scrollBar then
        ns.StripTextures(scrollBar)
    end

    f.editBox = editBox
    f.scrollFrame = scrollFrame
    copyFrame = f
    return f
end

------------------------------------------------------------------------
-- 채팅 텍스트 추출 (복사 프레임용) -- [CHATTYNATOR]
------------------------------------------------------------------------
local function ExtractChatText(chatFrame)
    if not chatFrame or not chatFrame.GetNumMessages then return "" end

    local lines = {}
    local numMsg = chatFrame:GetNumMessages()

    for i = 1, numMsg do
        local text = chatFrame:GetMessageInfo(i)
        if text and not (issecretvalue and issecretvalue(text)) then -- [12.0.1] secret string 보호
            text = text:gsub("|T.-|t", "")       -- 텍스처 제거 -- [CHATTYNATOR]
            text = text:gsub("|K.-|k", "???")     -- K 태그 -- [CHATTYNATOR]
            text = text:gsub("|A.-|a", "")         -- Atlas 제거 -- [CHATTYNATOR]
            text = text:gsub("|H.-|h(.-)|h", "%1") -- 하이퍼링크 -> 텍스트 -- [CHATTYNATOR]
            lines[#lines + 1] = text
        end
    end

    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- 복사 프레임 열기 -- [CHATTYNATOR]
------------------------------------------------------------------------
local function ShowCopyFrame(chatFrame)
    local text = ExtractChatText(chatFrame)
    if not text or text == "" then return end

    local f = CreateCopyFrame()
    f.editBox:SetText(text)
    f.editBox:HighlightText()
    f:Show()

    C_Timer.After(0, function()
        f.editBox:SetFocus()
        C_Timer.After(0, function()
            if f.scrollFrame.ScrollToBottom then
                f.scrollFrame:ScrollToBottom()
            end
        end)
    end)
end

------------------------------------------------------------------------
-- URL 감지 / 링크화 -- [ESSENTIAL]
------------------------------------------------------------------------
local function FormatURL(url)
    return format("|Hurl:%s|h%s[%s]|r|h", url, accentHex, url)
end

local function FilterURLs(self, event, msg, ...)
    if not msg then return false, msg, ... end
    if not (msg:find("www%.") or msg:find("://")) then
        return false, msg, ...
    end
    for _, pattern in ipairs(URL_PATTERNS) do
        msg = msg:gsub(pattern, FormatURL)
    end
    return false, msg, ...
end

------------------------------------------------------------------------
-- URL 클릭 핸들러 -- [ESSENTIAL]
------------------------------------------------------------------------
local function OnHyperlinkShow(self, link, text, button)
    if link and link:sub(1, 4) == "url:" then
        local url = link:sub(5)
        StaticPopup_Show("DDINGUI_URL_COPY", nil, nil, url)
    end
end

------------------------------------------------------------------------
-- 직업 색상 필터 -- [CHATTYNATOR]
------------------------------------------------------------------------
local function FilterClassColors(self, event, msg, author, ...)
    if not msg or not author then return false, msg, author, ... end

    local name = Ambiguate(author, "short")

    local _, classToken
    if IsInGroup() or IsInRaid() or IsInGuild() then
        local numGroup = GetNumGroupMembers()
        for i = 1, numGroup do
            local unit = (IsInRaid() and "raid" or "party") .. i
            if UnitExists(unit) then
                local unitName = UnitName(unit)
                if unitName and unitName == name then
                    _, classToken = UnitClass(unit)
                    break
                end
            end
        end
        if not classToken then
            local myName = UnitName("player")
            if myName == name then
                _, classToken = UnitClass("player")
            end
        end
    end

    if classToken then
        local hex = GetClassColorHex(classToken)
        if hex then
            msg = msg:gsub(
                "(|Hplayer.-|h%[?)([^%]|]+)(%]?|h)",
                "%1" .. hex .. "%2|r%3",
                1
            )
        end
    end

    return false, msg, author, ...
end

------------------------------------------------------------------------
-- 채널명 축약 필터 -- [CHATTYNATOR]
------------------------------------------------------------------------
local function FilterShortenChannels(self, event, msg, ...)
    if not msg then return false, msg, ... end

    local chatType = event and event:gsub("CHAT_MSG_", "") or nil
    if not chatType then return false, msg, ... end

    local abbrev = CHANNEL_ABBREVS[chatType]
    if not abbrev then return false, msg, ... end

    msg = msg:gsub(
        "(|Hchannel:[^|]+|h)%[?[^%]|]*%]?(|h)",
        "%1" .. abbrev .. ".%2",
        1
    )

    return false, msg, ...
end

------------------------------------------------------------------------
-- 블리자드 요소 완전 제거 (ElvUI 수준) -- [ESSENTIAL]
------------------------------------------------------------------------
local function HideBlizzardChatElements()
    -- QuickJoin 토스트 버튼 -- [ESSENTIAL]
    if QuickJoinToastButton then
        QuickJoinToastButton:SetAlpha(0)
        QuickJoinToastButton:SetScale(0.001)
        QuickJoinToastButton:ClearAllPoints()
        QuickJoinToastButton:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 9999, -9999)
        QuickJoinToastButton.ClearAllPoints = function() end
        QuickJoinToastButton.SetPoint = function() end
    end

    -- ChatFrameMenuButton -- [ESSENTIAL]
    if ChatFrameMenuButton then
        ChatFrameMenuButton:SetAlpha(0)
        ChatFrameMenuButton:SetSize(0.001, 0.001)
        ChatFrameMenuButton:EnableMouse(false)
    end

    -- ChatFrameChannelButton -- [ESSENTIAL]
    if ChatFrameChannelButton then
        ChatFrameChannelButton:SetAlpha(0)
        ChatFrameChannelButton:SetSize(0.001, 0.001)
        ChatFrameChannelButton:EnableMouse(false)
    end

    -- 소셜 버튼 (FriendsMicroButton or SocialButton) -- [ESSENTIAL]
    local socialBtn = FriendsMicroButton or ChatFrameToggleVoiceDeafenButton
    if socialBtn then
        socialBtn:SetAlpha(0)
        socialBtn:EnableMouse(false)
    end

    -- 보이스 채팅 버튼들 -- [ESSENTIAL]
    local voiceButtons = {
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
    }
    for _, btnName in ipairs(voiceButtons) do
        local btn = _G[btnName]
        if btn then
            btn:SetAlpha(0)
            btn:SetSize(0.001, 0.001)
            btn:EnableMouse(false)
        end
    end

    -- GeneralDockManager 배경 제거 -- [ESSENTIAL]
    if GeneralDockManager then
        ns.StripTextures(GeneralDockManager)
        if GeneralDockManager.SetBackdrop then
            GeneralDockManager:SetBackdrop(nil)
        end
    end
    if GeneralDockManagerOverflowButton then
        ns.StripTextures(GeneralDockManagerOverflowButton)
    end
    if GeneralDockManagerOverflowButtonList then
        ns.StripTextures(GeneralDockManagerOverflowButtonList)
    end
end

------------------------------------------------------------------------
-- 패널 생성 (ElvUI 스타일: 탭+채팅+에디트박스 통합) -- [ESSENTIAL]
------------------------------------------------------------------------
local function CreateChatPanel(chatFrame, index)
    if chatFrame._ddePanel then return chatFrame._ddePanel end

    local panel = CreateFrame("Frame", "DDingUI_ChatPanel" .. index, chatFrame,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetFrameLevel(math.max(0, chatFrame:GetFrameLevel() - 2))

    -- 패널 앵커: 탭 영역부터 에디트박스까지 커버 -- [ESSENTIAL-DESIGN]
    panel:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", -PANEL_PADDING, PANEL_PADDING + 2)
    panel:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", PANEL_PADDING, -(EDITBOX_HEIGHT + PANEL_PADDING + 4))

    -- 배경: sidebar 레벨 다크 -- [STYLE]
    local bgColor = GetC("bg", "sidebar") or { 0.08, 0.08, 0.08, 0.95 }
    local bdColor = { 0, 0, 0, 1 } -- 1px 블랙 테두리 (ElvUI 패턴)

    panel:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
    })
    panel:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], BACKDROP_ALPHA)
    panel:SetBackdropBorderColor(bdColor[1], bdColor[2], bdColor[3], bdColor[4])

    -- 탭 구분선 (탭 영역과 메시지 영역 사이) -- [ESSENTIAL-DESIGN]
    local tabSep = panel:CreateTexture(nil, "ARTWORK")
    tabSep:SetTexture(FLAT)
    tabSep:SetHeight(SEPARATOR_HEIGHT)
    tabSep:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", -PANEL_PADDING, 0)
    tabSep:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", PANEL_PADDING, 0)
    local sepColor = GetC("border", "separator") or { 0.20, 0.20, 0.20, 0.40 }
    tabSep:SetVertexColor(sepColor[1], sepColor[2], sepColor[3], sepColor[4] or 0.40)
    panel._tabSep = tabSep

    -- 에디트박스 구분선 (메시지 영역과 에디트박스 사이) -- [ESSENTIAL-DESIGN]
    local ebSep = panel:CreateTexture(nil, "ARTWORK")
    ebSep:SetTexture(FLAT)
    ebSep:SetHeight(SEPARATOR_HEIGHT)
    ebSep:SetPoint("BOTTOMLEFT", chatFrame, "BOTTOMLEFT", -PANEL_PADDING, -2)
    ebSep:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", PANEL_PADDING, -2)
    ebSep:SetVertexColor(sepColor[1], sepColor[2], sepColor[3], sepColor[4] or 0.40)
    panel._ebSep = ebSep

    chatFrame._ddePanel = panel
    return panel
end

------------------------------------------------------------------------
-- 복사 버튼 생성 (ElvUI 스타일: 미니멀) -- [ESSENTIAL]
------------------------------------------------------------------------
local function CreateCopyButton(chatFrame, index)
    if chatFrame._ddeCopyBtn then return chatFrame._ddeCopyBtn end

    local btn = CreateFrame("Button", "DDingUI_ChatCopyBtn" .. index, chatFrame)
    btn:SetSize(COPY_BTN_SIZE, COPY_BTN_SIZE)
    btn:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", 0, -2)
    btn:SetFrameLevel(chatFrame:GetFrameLevel() + 5)
    btn:SetAlpha(0)

    -- 배경 (둥근 느낌의 다크) -- [ESSENTIAL]
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(FLAT)
    bg:SetVertexColor(0, 0, 0, 0.6)

    -- 복사 아이콘 (작은 텍스트) -- [ESSENTIAL]
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(SL_FONT, F and F.small or 11, "OUTLINE")
    label:SetPoint("CENTER", 0, 0)
    label:SetText("C")
    label:SetTextColor(Unpack(GetC("text", "dim"), 0.60, 0.60, 0.60, 1))
    btn._label = label

    btn:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        self._label:SetTextColor(Unpack(GetC("text", "highlight"), 1, 1, 1, 1))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("채팅 복사", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetAlpha(0)
        self._label:SetTextColor(Unpack(GetC("text", "dim"), 0.60, 0.60, 0.60, 1))
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        ShowCopyFrame(chatFrame)
    end)

    chatFrame:HookScript("OnEnter", function()
        btn:SetAlpha(0.4)
    end)
    chatFrame:HookScript("OnLeave", function()
        if not btn:IsMouseOver() then
            btn:SetAlpha(0)
        end
    end)

    chatFrame._ddeCopyBtn = btn
    return btn
end

------------------------------------------------------------------------
-- 탭 플래시 애니메이션 생성 -- [CHATTYNATOR]
------------------------------------------------------------------------
local function CreateTabFlash(tab)
    if tab._ddeFlash then return end

    local flash = tab:CreateTexture(nil, "BORDER")
    flash:SetTexture(FLAT)
    flash:SetPoint("BOTTOMLEFT", 4, 0)
    flash:SetPoint("BOTTOMRIGHT", -4, 0)
    flash:SetHeight(2)
    flash:SetAlpha(0)
    -- 악센트 light 색상으로 플래시 -- [ESSENTIAL]
    if accentLight then
        flash:SetVertexColor(accentLight[1], accentLight[2], accentLight[3])
    elseif accentFrom then
        flash:SetVertexColor(accentFrom[1], accentFrom[2], accentFrom[3])
    else
        flash:SetVertexColor(1.00, 0.82, 0.20) -- [ESSENTIAL-DESIGN] Essential accent 노란색
    end

    local flashTicker
    local flashVisible = false

    tab._ddeFlash = flash
    tab._ddeStartFlash = function()
        if flashTicker then return end
        flash:Show()
        flashVisible = true
        flash:SetAlpha(1)
        flashTicker = C_Timer.NewTicker(0.6, function()
            flashVisible = not flashVisible
            flash:SetAlpha(flashVisible and 1 or 0)
        end)
    end
    tab._ddeStopFlash = function()
        if flashTicker then
            flashTicker:Cancel()
            flashTicker = nil
        end
        flash:SetAlpha(0)
        flash:Hide()
    end
end

------------------------------------------------------------------------
-- 탭 스타일 (ElvUI 수준) -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinTab(tab, index)
    if not tab or tab._ddeSkinned then return end

    ns.StripTextures(tab)

    -- 선택 인디케이터/하이라이트 텍스처 제거 -- [ESSENTIAL]
    if tab.leftSelectedTexture  then tab.leftSelectedTexture:SetTexture(nil) end
    if tab.middleSelectedTexture then tab.middleSelectedTexture:SetTexture(nil) end
    if tab.rightSelectedTexture then tab.rightSelectedTexture:SetTexture(nil) end

    if tab.leftHighlightTexture  then tab.leftHighlightTexture:SetTexture(nil) end
    if tab.middleHighlightTexture then tab.middleHighlightTexture:SetTexture(nil) end
    if tab.rightHighlightTexture then tab.rightHighlightTexture:SetTexture(nil) end

    -- 탭 텍스트 폰트 + 기본 색상 -- [ESSENTIAL]
    local tabText = tab.Text or tab:GetFontString() or _G["ChatFrame" .. index .. "TabText"]
    if tabText then
        ns.SetFont(tabText, TAB_FONT_SIZE)
        tabText:SetShadowOffset(1, -1)
        local dimColor = GetC("text", "dim") or { 0.60, 0.60, 0.60, 1 }
        tabText:SetTextColor(dimColor[1], dimColor[2], dimColor[3], dimColor[4] or 1)
    end
    tab._ddeText = tabText

    -- 탭 호버 배경 (미묘한 하이라이트) -- [ESSENTIAL-DESIGN]
    local hoverBg = tab:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetTexture(FLAT)
    hoverBg:SetAllPoints()
    hoverBg:SetVertexColor(1, 1, 1, 0.03)
    hoverBg:SetAlpha(0)
    tab._ddeHoverBg = hoverBg

    -- 선택 인디케이터: 하단 악센트 라인 -- [ESSENTIAL]
    local indicator = tab:CreateTexture(nil, "ARTWORK")
    indicator:SetTexture(FLAT)
    indicator:SetPoint("BOTTOMLEFT", 4, 0)
    indicator:SetPoint("BOTTOMRIGHT", -4, 0)
    indicator:SetHeight(2)
    indicator:SetAlpha(0)
    if accentFrom then
        indicator:SetVertexColor(accentFrom[1], accentFrom[2], accentFrom[3])
    else
        indicator:SetVertexColor(1.00, 0.82, 0.20) -- [ESSENTIAL-DESIGN] Essential accent 노란색
    end
    tab._ddeIndicator = indicator

    -- 플래시 생성 -- [CHATTYNATOR]
    CreateTabFlash(tab)

    -- 호버/선택 상태 관리 -- [ESSENTIAL]
    tab:HookScript("OnEnter", function(self)
        self._ddeHoverBg:SetAlpha(1)
        if self._ddeText then
            local hlColor = GetC("text", "highlight") or { 1, 1, 1, 1 }
            self._ddeText:SetTextColor(hlColor[1], hlColor[2], hlColor[3])
        end
    end)

    tab:HookScript("OnLeave", function(self)
        self._ddeHoverBg:SetAlpha(0)
        local cf = _G["ChatFrame" .. index]
        if cf and cf == SELECTED_CHAT_FRAME then
            -- 선택된 탭: 밝은 텍스트 유지 -- [ESSENTIAL]
            if self._ddeText then
                local nColor = GetC("text", "normal") or { 0.85, 0.85, 0.85, 1 }
                self._ddeText:SetTextColor(nColor[1], nColor[2], nColor[3])
            end
        else
            -- 비선택 탭: 어두운 텍스트 -- [ESSENTIAL]
            if self._ddeText then
                local dimColor = GetC("text", "dim") or { 0.60, 0.60, 0.60, 1 }
                self._ddeText:SetTextColor(dimColor[1], dimColor[2], dimColor[3])
            end
        end
    end)

    -- 탭 클릭: 전체 탭 상태 갱신 -- [ESSENTIAL]
    tab:HookScript("OnClick", function()
        for i = 1, NUM_CHAT_FRAMES do
            local otherTab = _G["ChatFrame" .. i .. "Tab"]
            if otherTab and otherTab._ddeSkinned then
                local cf = _G["ChatFrame" .. i]
                if cf and cf == SELECTED_CHAT_FRAME then
                    if otherTab._ddeIndicator then
                        otherTab._ddeIndicator:SetAlpha(1)
                    end
                    if otherTab._ddeText then
                        local nColor = GetC("text", "normal") or { 0.85, 0.85, 0.85, 1 }
                        otherTab._ddeText:SetTextColor(nColor[1], nColor[2], nColor[3])
                    end
                    if otherTab._ddeStopFlash then
                        otherTab._ddeStopFlash()
                    end
                else
                    if otherTab._ddeIndicator then
                        otherTab._ddeIndicator:SetAlpha(0)
                    end
                    if otherTab._ddeText then
                        local dimColor = GetC("text", "dim") or { 0.60, 0.60, 0.60, 1 }
                        otherTab._ddeText:SetTextColor(dimColor[1], dimColor[2], dimColor[3])
                    end
                end
            end
        end
    end)

    -- 초기 상태 -- [ESSENTIAL]
    local cf = _G["ChatFrame" .. index]
    if cf and cf == SELECTED_CHAT_FRAME then
        indicator:SetAlpha(1)
        if tabText then
            local nColor = GetC("text", "normal") or { 0.85, 0.85, 0.85, 1 }
            tabText:SetTextColor(nColor[1], nColor[2], nColor[3])
        end
    end

    tab._ddeSkinned = true
end

------------------------------------------------------------------------
-- EditBox 스킨 (하단 배치, ElvUI 스타일) -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinEditBox(chatFrame, index)
    local editBox = chatFrame.editBox or _G["ChatFrame" .. index .. "EditBox"]
    if not editBox or editBox._ddeSkinned then return end

    ns.StripTextures(editBox)

    -- left/right/mid 텍스처 제거 (Chattynator 패턴) -- [CHATTYNATOR]
    for _, texName in ipairs({"Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid"}) do
        local tex = _G["ChatFrame" .. index .. "EditBox" .. texName]
            or editBox[texName] or editBox[texName:lower()]
        if tex then
            tex:SetTexture(nil)
            tex:Hide()
        end
    end

    -- 에디트박스 배경: 패널과 통합 (더 어두운 input 배경) -- [STYLE]
    local inputBg = editBox:CreateTexture(nil, "BACKGROUND", nil, -1)
    inputBg:SetTexture(FLAT)
    inputBg:SetAllPoints()
    local ibColor = GetC("bg", "input") or { 0.06, 0.06, 0.06, 0.80 }
    inputBg:SetVertexColor(ibColor[1], ibColor[2], ibColor[3], ibColor[4] or 0.80)
    editBox._ddeInputBg = inputBg

    -- 입력창 폰트 -- [ESSENTIAL]
    ns.SetFont(editBox, EDITBOX_FONT_SIZE)
    editBox:SetTextColor(Unpack(GetC("text", "normal"), 0.85, 0.85, 0.85, 1))

    -- 헤더 폰트 -- [ESSENTIAL]
    local header = editBox.header or _G["ChatFrame" .. index .. "EditBoxHeader"]
    if header then
        ns.SetFont(header, EDITBOX_FONT_SIZE)
        -- 헤더 악센트 색상 -- [ESSENTIAL-DESIGN]
        if accentFrom then
            header:SetTextColor(accentFrom[1], accentFrom[2], accentFrom[3], 1)
        end
    end

    -- 하단 배치 (ElvUI 스타일: 채팅 메시지 아래) -- [ESSENTIAL-DESIGN]
    editBox:ClearAllPoints()
    editBox:SetPoint("TOPLEFT", chatFrame, "BOTTOMLEFT", -PANEL_PADDING, -3)
    editBox:SetPoint("TOPRIGHT", chatFrame, "BOTTOMRIGHT", PANEL_PADDING, -3)
    editBox:SetHeight(EDITBOX_HEIGHT)

    -- 포커스 시 시각 피드백 -- [ESSENTIAL-DESIGN]
    editBox:HookScript("OnEditFocusGained", function(self)
        if self._ddeInputBg then
            local hvColor = GetC("bg", "hover") or { 0.20, 0.20, 0.20, 0.60 }
            self._ddeInputBg:SetVertexColor(hvColor[1], hvColor[2], hvColor[3], 0.3)
        end
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        if self._ddeInputBg then
            local ibCol = GetC("bg", "input") or { 0.06, 0.06, 0.06, 0.80 }
            self._ddeInputBg:SetVertexColor(ibCol[1], ibCol[2], ibCol[3], ibCol[4] or 0.80)
        end
    end)

    editBox._ddeSkinned = true
end

------------------------------------------------------------------------
-- 스크롤바 정리 + 스크롤투바텀 미니버튼 -- [ESSENTIAL]
------------------------------------------------------------------------
local function CleanScrollbar(chatFrame, index)
    local scrollBar = chatFrame.ScrollBar or _G["ChatFrame" .. index .. "ScrollBar"]
    if scrollBar then
        ns.StripTextures(scrollBar)
        scrollBar:SetAlpha(0)
    end

    -- 기존 스크롤투바텀 버튼 스킨 -- [ESSENTIAL]
    local scrollToBottom = chatFrame.ScrollToBottomButton
        or _G["ChatFrame" .. index .. "ScrollToBottomButton"]
    if scrollToBottom then
        ns.StripTextures(scrollToBottom)
        scrollToBottom:SetAlpha(0)
    end

    -- CombatLogQuickButtonFrame 처리 (전투 로그) -- [ESSENTIAL]
    if index == 2 then
        local qlbf = CombatLogQuickButtonFrame
        if qlbf then
            ns.StripTextures(qlbf)
        end
        local qlbfBg = CombatLogQuickButtonFrame_Custom
            or _G["CombatLogQuickButtonFrame_Custom"]
        if qlbfBg then
            ns.StripTextures(qlbfBg)
        end
    end
end

------------------------------------------------------------------------
-- Blizzard 채팅 텍스처 제거 -- [ESSENTIAL]
------------------------------------------------------------------------
local function StripChatTextures(chatFrame, index)
    local bg = _G["ChatFrame" .. index .. "Background"]
    if bg then bg:SetTexture(nil); bg:Hide() end

    local names = { "TopTexture", "BottomTexture", "LeftTexture", "RightTexture" }
    for _, name in ipairs(names) do
        local tex = _G["ChatFrame" .. index .. name]
        if tex then tex:SetTexture(nil) end
    end

    local buttonFrame = _G["ChatFrame" .. index .. "ButtonFrame"]
    if buttonFrame then
        buttonFrame:Hide()
        buttonFrame:SetScript("OnShow", buttonFrame.Hide)
    end

    local resizeTop = _G["ChatFrame" .. index .. "ResizeTop"]
    local resizeBottom = _G["ChatFrame" .. index .. "ResizeBottom"]
    if resizeTop then resizeTop:SetTexture(nil) end
    if resizeBottom then resizeBottom:SetTexture(nil) end

    -- 추가: 최소화 버튼, 기타 프레임 요소 -- [ESSENTIAL]
    local minBtn = _G["ChatFrame" .. index .. "ButtonFrameMinimizeButton"]
    if minBtn then minBtn:Hide() end
end

------------------------------------------------------------------------
-- 패널 페이드 설정 (마우스 진입/이탈 시 전체 패널) -- [ESSENTIAL]
------------------------------------------------------------------------
local function SetupPanelFade(chatFrame, index)
    local panel = chatFrame._ddePanel
    if not panel then return end

    -- 초기 알파: 낮은 상태 -- [ESSENTIAL-DESIGN]
    panel:SetAlpha(0.35)

    -- 패널 마우스 감지 프레임 (패널 위에 투명하게) -- [ESSENTIAL]
    local sensor = CreateFrame("Frame", nil, panel)
    sensor:SetAllPoints(panel)
    sensor:SetFrameLevel(panel:GetFrameLevel() + 1)
    sensor:EnableMouse(false)  -- 클릭 통과
    chatFrame._ddePanelSensor = sensor

    -- 패널 페이드 -- [ESSENTIAL]
    -- [PERF] C_Timer.NewTicker(0.02) 50Hz → UIFrameFadeOut/UIFrameFadeIn 네이티브 대체
    local function FadePanel(targetAlpha)
        local current = panel:GetAlpha()
        if math.abs(targetAlpha - current) < 0.02 then
            panel:SetAlpha(targetAlpha)
            return
        end
        local duration = 0.15
        if UIFrameFade then
            UIFrameFade(panel, {
                mode = targetAlpha > current and "IN" or "OUT",
                timeToFade = duration,
                startAlpha = current,
                endAlpha = targetAlpha,
                finishedFunc = function() panel:SetAlpha(targetAlpha) end,
            })
        else
            panel:SetAlpha(targetAlpha)
        end
    end

    -- 채팅 프레임 마우스 이벤트 훅 -- [ESSENTIAL]
    chatFrame:HookScript("OnEnter", function()
        FadePanel(BACKDROP_ALPHA)
    end)
    chatFrame:HookScript("OnLeave", function()
        if not chatFrame:IsMouseOver() then
            FadePanel(0.35)
        end
    end)

    -- 패널 자체 마우스 이벤트 -- [ESSENTIAL]
    panel:EnableMouse(true)
    panel:SetScript("OnEnter", function()
        FadePanel(BACKDROP_ALPHA)
    end)
    panel:SetScript("OnLeave", function()
        if not chatFrame:IsMouseOver() and not panel:IsMouseOver() then
            FadePanel(0.35)
        end
    end)
end

------------------------------------------------------------------------
-- 단일 채팅 프레임 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:SkinChatFrame(index, db)
    local cf = _G["ChatFrame" .. index]
    if not cf or cf._ddeChatSkinned then return end
    db = db or (ns.db and ns.db.chat) or {}

    StripChatTextures(cf, index)

    -- 패널 생성 (탭+채팅+에디트박스 통합) -- [ESSENTIAL-DESIGN]
    if db.backdrop ~= false then
        CreateChatPanel(cf, index)
    end

    local tab = _G["ChatFrame" .. index .. "Tab"]
    SkinTab(tab, index)

    -- 채팅 텍스트 폰트 (기존 사이즈 유지) -- [ESSENTIAL]
    local _, size, flags = cf:GetFont()
    cf:SetFont(SL_FONT, size or 13, flags or "")

    SkinEditBox(cf, index)
    CleanScrollbar(cf, index)

    if db.copyButton ~= false then
        CreateCopyButton(cf, index)
    end

    -- 패널 페이드 설정 -- [ESSENTIAL]
    if cf._ddePanel then
        SetupPanelFade(cf, index)
    end

    cf._ddeChatSkinned = true
end

------------------------------------------------------------------------
-- 필터 이벤트 테이블 -- [ESSENTIAL]
------------------------------------------------------------------------
local URL_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_BN_INLINE_TOAST_ALERT",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local CLASS_COLOR_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local SHORTEN_EVENTS = {
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
}

------------------------------------------------------------------------
-- 필터 등록 함수 -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:RegisterURLFilter()
    for _, event in ipairs(URL_EVENTS) do
        ChatFrame_AddMessageEventFilter(event, FilterURLs)
    end
end

function Chat:RegisterClassColors()
    for _, event in ipairs(CLASS_COLOR_EVENTS) do
        ChatFrame_AddMessageEventFilter(event, FilterClassColors)
    end
end

function Chat:RegisterShortenChannels()
    for _, event in ipairs(SHORTEN_EVENTS) do
        ChatFrame_AddMessageEventFilter(event, FilterShortenChannels)
    end
end

------------------------------------------------------------------------
-- URL 클릭 핸들러 등록 -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:RegisterURLClickHandler()
    for i = 1, NUM_CHAT_FRAMES do
        local cf = _G["ChatFrame" .. i]
        if cf then
            cf:HookScript("OnHyperlinkClick", OnHyperlinkShow)
        end
    end
end

------------------------------------------------------------------------
-- 새 임시 채팅창 훅 -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:HookTemporaryWindows()
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        for i = 1, NUM_CHAT_FRAMES do
            local cf = _G["ChatFrame" .. i]
            if cf and not cf._ddeChatSkinned then
                self:SkinChatFrame(i)
                cf:HookScript("OnHyperlinkClick", OnHyperlinkShow)
            end
        end
    end)
end

------------------------------------------------------------------------
-- 탭 활성 상태 갱신 훅 -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:HookTabAlpha()
    if FCF_DockUpdate then
        hooksecurefunc("FCF_DockUpdate", function()
            for i = 1, NUM_CHAT_FRAMES do
                local tab = _G["ChatFrame" .. i .. "Tab"]
                if tab and tab._ddeSkinned then
                    local cf = _G["ChatFrame" .. i]
                    if cf and cf == SELECTED_CHAT_FRAME then
                        if tab._ddeIndicator then
                            tab._ddeIndicator:SetAlpha(1)
                        end
                        if tab._ddeText then
                            local nColor = GetC("text", "normal") or { 0.85, 0.85, 0.85, 1 }
                            tab._ddeText:SetTextColor(nColor[1], nColor[2], nColor[3])
                        end
                    else
                        if tab._ddeIndicator then
                            tab._ddeIndicator:SetAlpha(0)
                        end
                        if tab._ddeText then
                            local dimColor = GetC("text", "dim") or { 0.60, 0.60, 0.60, 1 }
                            tab._ddeText:SetTextColor(dimColor[1], dimColor[2], dimColor[3])
                        end
                    end
                end
            end
        end)
    end

    if SetChatWindowAlpha then
        hooksecurefunc("SetChatWindowAlpha", function(index, alpha)
            -- 패널 알파는 자체 페이드 시스템에서 관리 -- [ESSENTIAL]
        end)
    end
end

------------------------------------------------------------------------
-- 탭 플래시 훅 (새 메시지) -- [CHATTYNATOR]
------------------------------------------------------------------------
function Chat:HookTabFlash()
    if FCF_StartAlertFlash then
        hooksecurefunc("FCF_StartAlertFlash", function(chatFrame)
            if not chatFrame then return end
            local index = chatFrame:GetID()
            local tab = _G["ChatFrame" .. index .. "Tab"]
            if tab and tab._ddeStartFlash then
                tab._ddeStartFlash()
            end
        end)
    end

    if FCF_StopAlertFlash then
        hooksecurefunc("FCF_StopAlertFlash", function(chatFrame)
            if not chatFrame then return end
            local index = chatFrame:GetID()
            local tab = _G["ChatFrame" .. index .. "Tab"]
            if tab and tab._ddeStopFlash then
                tab._ddeStopFlash()
            end
        end)
    end
end

------------------------------------------------------------------------
-- 채팅 폰트 후처리: SetChatWindowFontSize 훅 -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:HookFontChange()
    hooksecurefunc("FCF_SetChatWindowFontSize", function(self, chatFrame, fontSize)
        if chatFrame then
            chatFrame:SetFont(SL_FONT, fontSize, "")
        end
    end)
end

------------------------------------------------------------------------
-- Enable -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:Enable()
    local db = ns.db and ns.db.chat or {}
    BACKDROP_ALPHA    = db.backdropAlpha or 0.75
    TAB_FONT_SIZE     = db.tabFontSize or 12
    EDITBOX_FONT_SIZE = db.editboxFontSize or 13

    -- StyleLib 재확인 (PLAYER_LOGIN 이후 로드될 수 있음) -- [ESSENTIAL]
    SL = _G.DDingUI_StyleLib
    C  = SL and SL.Colors
    F  = SL and SL.Font
    if SL and SL.Textures then FLAT = SL.Textures.flat or FLAT end
    if F then SL_FONT = F.path or SL_FONT end
    if F then FONT_DEFAULT = F.default or FONT_DEFAULT end

    -- 악센트 캐시 -- [ESSENTIAL]
    if SL and SL.GetAccent then
        accentFrom, accentTo, accentLight, accentDark = SL.GetAccent("Essential")
    end
    if accentFrom then
        accentHex = string.format("|cff%02x%02x%02x",
            math.floor(accentFrom[1] * 255 + 0.5),
            math.floor(accentFrom[2] * 255 + 0.5),
            math.floor(accentFrom[3] * 255 + 0.5))
    end

    -- 0. 블리자드 요소 제거 -- [ESSENTIAL]
    HideBlizzardChatElements()

    -- 1. 모든 기존 채팅 프레임 스킨 -- [ESSENTIAL]
    for i = 1, NUM_CHAT_FRAMES do
        self:SkinChatFrame(i, db)
    end

    -- 2. URL 감지 필터 등록 (DB 조건부) -- [ESSENTIAL]
    if db.urlDetect ~= false then
        self:RegisterURLFilter()
        self:RegisterURLClickHandler()
    end

    -- 3. 임시 채팅창 훅 -- [ESSENTIAL]
    self:HookTemporaryWindows()

    -- 4. 탭 알파 훅 -- [ESSENTIAL]
    self:HookTabAlpha()

    -- 5. 폰트 변경 훅 -- [ESSENTIAL]
    self:HookFontChange()

    -- 6. 탭 플래시 훅 (새 메시지 알림) -- [CHATTYNATOR]
    self:HookTabFlash()

    -- 7. 직업 색상 (DB 조건부) -- [CHATTYNATOR]
    if db.classColors ~= false then
        self:RegisterClassColors()
    end

    -- 8. 채널명 축약 (DB 조건부) -- [CHATTYNATOR]
    if db.shortenChannels then
        self:RegisterShortenChannels()
    end

    -- 9. 페이드 타임 적용 -- [ESSENTIAL]
    local fadeTime = db.fadeTime or 30
    for i = 1, NUM_CHAT_FRAMES do
        local cf = _G["ChatFrame" .. i]
        if cf then
            cf:SetTimeVisible(fadeTime)
            cf:SetFadeDuration(3)
        end
    end

    -- 10. 위스퍼 수신 사운드 -- [ESSENTIAL]
    if db.whisperSound ~= false then
        self:RegisterWhisperSound()
    end
end

------------------------------------------------------------------------
-- 위스퍼 수신 사운드 -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:RegisterWhisperSound()
    if self._whisperSoundRegistered then return end
    local wsFrame = CreateFrame("Frame")
    wsFrame:RegisterEvent("CHAT_MSG_WHISPER")
    wsFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
    wsFrame:SetScript("OnEvent", function()
        local db = ns.db and ns.db.chat
        if db and db.whisperSound ~= false then
            PlaySound(SOUNDKIT.TELL_MESSAGE or 3081)
        end
    end)
    self._whisperSoundRegistered = true
end

------------------------------------------------------------------------
-- Disable -- [ESSENTIAL]
------------------------------------------------------------------------
function Chat:Disable()
    -- ReloadUI 필요 (훅은 해제 불가) -- [ESSENTIAL]
end

------------------------------------------------------------------------
-- 모듈 등록 -- [ESSENTIAL]
------------------------------------------------------------------------
ns:RegisterModule("chat", Chat)
