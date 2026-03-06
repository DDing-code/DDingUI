--[[
    DDingToolKit - GoldSplit Module (계산기)
    레이드 분배금 계산기 - DDingToolKit 스타일
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [STYLE]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

-- GoldSplit 모듈
local GoldSplit = {}
ns.GoldSplit = GoldSplit

-- 로컬 변수
local totalGold = 0
local mainFrame = nil

-- 골드 형식 변환 함수 (천단위 콤마)
local function FormatGold(value)
    if value >= 1000 then
        return tostring(value):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    end
    return tostring(value)
end

-- 초기화
function GoldSplit:OnInitialize()
    self.db = ns.db.profile.GoldSplit
    if not self.db then
        self.db = {}
        ns.db.profile.GoldSplit = self.db
    end
end

-- 활성화
function GoldSplit:OnEnable()
    self:CreateMainFrame()

    -- 슬래시 커맨드 등록
    SLASH_GOLDSPLIT1 = "/분배금"
    SLASH_GOLDSPLIT2 = "/goldsplit"
    SlashCmdList["GOLDSPLIT"] = function()
        self:Toggle()
    end
end

-- 비활성화
function GoldSplit:OnDisable()
    if mainFrame then
        mainFrame:Hide()
    end
end

-- 토글
function GoldSplit:Toggle()
    if mainFrame then
        if mainFrame:IsShown() then
            mainFrame:Hide()
        else
            mainFrame:Show()
        end
    end
end

-- 표시
function GoldSplit:Show()
    if mainFrame then
        mainFrame:Show()
    end
end

-- 숨기기
function GoldSplit:Hide()
    if mainFrame then
        mainFrame:Hide()
    end
end

-- 골드 텍스트 업데이트
function GoldSplit:UpdateGoldText()
    if mainFrame and mainFrame.goldText then
        mainFrame.goldText:SetText(FormatGold(totalGold) .. "G")
    end
end

-- 메인 프레임 생성 (DDingToolKit 스타일)
function GoldSplit:CreateMainFrame()
    if mainFrame then return end

    -- 메인 프레임
    mainFrame = CreateFrame("Frame", "DDingToolKit_GoldSplitFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(280, 300)
    mainFrame:SetBackdrop(UI.backdrop)
    mainFrame:SetBackdropColor(unpack(UI.colors.background))
    mainFrame:SetBackdropBorderColor(unpack(UI.colors.border))
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    -- 저장된 위치 적용
    self:ApplyPosition()

    -- ESC로 닫기
    tinsert(UISpecialFrames, "DDingToolKit_GoldSplitFrame")

    -- 타이틀바
    local titleBar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(32)
    titleBar:SetBackdrop(UI.backdrop)
    titleBar:SetBackdropColor(unpack(UI.colors.panelLight))
    titleBar:SetBackdropBorderColor(unpack(UI.colors.border))
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        if not self.db.locked then
            mainFrame:StartMoving()
        end
    end)
    titleBar:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        self:SavePosition()
    end)

    -- 타이틀 텍스트
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 12, 0)
    titleText:SetText("|cFFFFA500계산기|r")
    titleText:SetTextColor(unpack(UI.colors.text))

    -- 닫기 버튼
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", -6, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- 컨텐츠 영역
    local content = CreateFrame("Frame", nil, mainFrame)
    content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 10, -10)
    content:SetPoint("BOTTOMRIGHT", -10, 10)

    local yOffset = 0

    -- 총 골드 라벨
    local goldLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldLabel:SetPoint("TOPLEFT", 0, yOffset)
    goldLabel:SetText(L["GOLDSPLIT_TOTAL_GOLD"])
    goldLabel:SetTextColor(unpack(UI.colors.textDim))
    yOffset = yOffset - 20

    -- 총 골드 표시 (큰 글씨)
    local goldText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    goldText:SetPoint("TOPLEFT", 0, yOffset)
    goldText:SetText(FormatGold(totalGold) .. "G")
    goldText:SetTextColor(unpack(UI.colors.warning))
    goldText:SetFont(goldText:GetFont(), 28, "OUTLINE")
    mainFrame.goldText = goldText
    yOffset = yOffset - 45

    -- 구분선
    local divider1 = content:CreateTexture(nil, "ARTWORK")
    divider1:SetPoint("TOPLEFT", 0, yOffset)
    divider1:SetSize(260, 1)
    divider1:SetColorTexture(unpack(UI.colors.border))
    yOffset = yOffset - 15

    -- 금액 직접 입력 버튼
    local inputBtn = UI:CreateButton(content, 260, 32, L["GOLDSPLIT_MANUAL_INPUT"])
    inputBtn:SetPoint("TOPLEFT", 0, yOffset)
    inputBtn:SetScript("OnClick", function()
        self:ShowInputPopup()
    end)
    yOffset = yOffset - 40

    -- 분배금 조정 버튼
    local adjustBtn = UI:CreateButton(content, 260, 32, L["GOLDSPLIT_ADJUST_AMOUNT"])
    adjustBtn:SetPoint("TOPLEFT", 0, yOffset)
    adjustBtn:SetScript("OnClick", function()
        self:ShowAdjustPopup()
    end)
    yOffset = yOffset - 50

    -- 구분선
    local divider2 = content:CreateTexture(nil, "ARTWORK")
    divider2:SetPoint("TOPLEFT", 0, yOffset)
    divider2:SetSize(260, 1)
    divider2:SetColorTexture(unpack(UI.colors.border))
    yOffset = yOffset - 15

    -- 분배금 계산 버튼 (강조)
    local calcBtn = UI:CreateButton(content, 260, 40, L["GOLDSPLIT_CALCULATE_SHARE"])
    calcBtn:SetPoint("TOPLEFT", 0, yOffset)
    calcBtn:SetBackdropColor(unpack(UI.colors.accent))
    calcBtn.text:SetTextColor(1, 1, 1)
    calcBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
        self:SetBackdropColor(unpack(UI.colors.accentHover))
    end)
    calcBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
        self:SetBackdropColor(unpack(UI.colors.accent))
    end)
    calcBtn:SetScript("OnClick", function()
        self:ShowCalculatePopup()
    end)
    yOffset = yOffset - 50

    -- 초기화 버튼
    local resetBtn = UI:CreateButton(content, 260, 28, L["GOLDSPLIT_RESET"])
    resetBtn:SetPoint("TOPLEFT", 0, yOffset)
    resetBtn.text:SetTextColor(unpack(UI.colors.error))
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("GOLDSPLIT_RESET_CONFIRM")
    end)

    -- 확인 다이얼로그
    StaticPopupDialogs["GOLDSPLIT_RESET_CONFIRM"] = {
        text = L["GOLDSPLIT_RESET_CONFIRM"],
        button1 = L["GOLDSPLIT_CONFIRM"],
        button2 = L["GOLDSPLIT_CANCEL"],
        OnAccept = function()
            totalGold = 0
            self:UpdateGoldText()
            print(CHAT_PREFIX .. L["GOLDSPLIT_RESET_DONE"]) -- [STYLE]
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    self.mainFrame = mainFrame
end

-- 위치 저장
function GoldSplit:SavePosition()
    if not mainFrame then return end
    local point, _, relPoint, x, y = mainFrame:GetPoint()
    self.db.position = {
        point = point,
        relativePoint = relPoint,
        x = x,
        y = y,
    }
end

-- 위치 적용
function GoldSplit:ApplyPosition()
    if not mainFrame then return end
    mainFrame:ClearAllPoints()
    local pos = self.db.position
    if pos and pos.point then
        mainFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        mainFrame:SetPoint("CENTER")
    end
end

-- 팝업 스타일 생성 헬퍼
local function CreateStyledPopup(name, width, height, title)
    local popup = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    popup:SetSize(width, height)
    popup:SetPoint("CENTER")
    popup:SetBackdrop(UI.backdrop)
    popup:SetBackdropColor(unpack(UI.colors.background))
    popup:SetBackdropBorderColor(unpack(UI.colors.border))
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

    -- 타이틀바
    local titleBar = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(28)
    titleBar:SetBackdrop(UI.backdrop)
    titleBar:SetBackdropColor(unpack(UI.colors.panelLight))
    titleBar:SetBackdropBorderColor(unpack(UI.colors.border))

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText(title)
    titleText:SetTextColor(unpack(UI.colors.text))

    -- 닫기 버튼
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() popup:Hide() end)

    popup.titleBar = titleBar
    return popup
end

-- 금액 입력 팝업
function GoldSplit:ShowInputPopup()
    if self.inputPopup then
        self.inputPopup.inputBox:SetText(tostring(totalGold))
        self.inputPopup.inputBox:HighlightText()
        self.inputPopup:Show()
        return
    end

    local popup = CreateStyledPopup("GoldSplit_InputPopup", 280, 130, L["GOLDSPLIT_INPUT_TITLE"])

    local inputBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    inputBox:SetSize(180, 28)
    inputBox:SetPoint("TOP", 0, -50)
    inputBox:SetAutoFocus(true)
    inputBox:SetNumeric(true)
    inputBox:SetText(tostring(totalGold))
    inputBox:HighlightText()
    popup.inputBox = inputBox

    local confirmBtn = UI:CreateButton(popup, 100, 28, L["GOLDSPLIT_CONFIRM"])
    confirmBtn:SetPoint("BOTTOMLEFT", 25, 15)
    confirmBtn:SetScript("OnClick", function()
        totalGold = tonumber(inputBox:GetText()) or 0
        self:UpdateGoldText()
        popup:Hide()
    end)

    local cancelBtn = UI:CreateButton(popup, 100, 28, L["GOLDSPLIT_CANCEL"])
    cancelBtn:SetPoint("BOTTOMRIGHT", -25, 15)
    cancelBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    inputBox:SetScript("OnEnterPressed", function()
        confirmBtn:Click()
    end)

    self.inputPopup = popup
    popup:Show()
end

-- 분배금 조정 팝업
function GoldSplit:ShowAdjustPopup()
    if self.adjustPopup then
        self.adjustPopup.inputBox:SetText("0")
        self.adjustPopup.inputBox:HighlightText()
        self.adjustPopup:Show()
        return
    end

    local popup = CreateStyledPopup("GoldSplit_AdjustPopup", 280, 130, L["GOLDSPLIT_ADJUST_TITLE"])

    local inputBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    inputBox:SetSize(140, 28)
    inputBox:SetPoint("TOP", 0, -50)
    inputBox:SetAutoFocus(true)
    inputBox:SetNumeric(true)
    inputBox:SetText("0")
    inputBox:HighlightText()
    popup.inputBox = inputBox

    local addBtn = UI:CreateButton(popup, 70, 28, "+")
    addBtn:SetPoint("BOTTOMLEFT", 20, 15)
    addBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
    addBtn:SetScript("OnClick", function()
        local value = tonumber(inputBox:GetText()) or 0
        totalGold = totalGold + value
        self:UpdateGoldText()
        popup:Hide()
    end)

    local subBtn = UI:CreateButton(popup, 70, 28, "-")
    subBtn:SetPoint("BOTTOM", 0, 15)
    subBtn:SetBackdropColor(0.5, 0.2, 0.2, 1)
    subBtn:SetScript("OnClick", function()
        local value = tonumber(inputBox:GetText()) or 0
        totalGold = math.max(0, totalGold - value)
        self:UpdateGoldText()
        popup:Hide()
    end)

    local cancelBtn = UI:CreateButton(popup, 70, 28, L["GOLDSPLIT_CANCEL"])
    cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    cancelBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    self.adjustPopup = popup
    popup:Show()
end

-- 분배금 계산 팝업
function GoldSplit:ShowCalculatePopup()
    if self.calcPopup then
        self.calcPopup.goldInfo:SetText(L["GOLDSPLIT_TOTAL_GOLD"] .. ": |cFFFFD700" .. FormatGold(totalGold) .. "G|r")
        self.calcPopup.inputBox:SetText("1")
        self.calcPopup.nPlusOne:SetChecked(false)
        self.calcPopup:Show()
        -- 미리보기 업데이트 트리거
        self.calcPopup.UpdatePreview()
        return
    end

    local popup = CreateStyledPopup("GoldSplit_CalcPopup", 300, 180, L["GOLDSPLIT_CALC_TITLE"])

    -- 현재 총 골드 표시
    local goldInfo = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldInfo:SetPoint("TOP", 0, -40)
    goldInfo:SetText(L["GOLDSPLIT_TOTAL_GOLD"] .. ": |cFFFFD700" .. FormatGold(totalGold) .. "G|r")
    popup.goldInfo = goldInfo

    -- 인원수 입력
    local label = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 25, -70)
    label:SetText(L["GOLDSPLIT_SPLIT_PLAYERS"])
    label:SetTextColor(unpack(UI.colors.textDim))

    local inputBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    inputBox:SetSize(50, 24)
    inputBox:SetPoint("LEFT", label, "RIGHT", 10, 0)
    inputBox:SetAutoFocus(true)
    inputBox:SetNumeric(true)
    inputBox:SetText("1")
    popup.inputBox = inputBox

    -- N+1 체크박스
    local nPlusOne = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    nPlusOne:SetSize(24, 24)
    nPlusOne:SetPoint("LEFT", inputBox, "RIGHT", 20, 0)
    popup.nPlusOne = nPlusOne

    local nPlusOneLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nPlusOneLabel:SetPoint("LEFT", nPlusOne, "RIGHT", 2, 0)
    nPlusOneLabel:SetText("N+1")
    nPlusOneLabel:SetTextColor(unpack(UI.colors.text))

    -- 결과 미리보기
    local preview = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    preview:SetPoint("TOP", 0, -100)
    preview:SetTextColor(unpack(UI.colors.textDim))

    local function UpdatePreview()
        local playerCount = tonumber(inputBox:GetText()) or 1
        playerCount = math.max(1, playerCount)
        if nPlusOne:GetChecked() then
            playerCount = playerCount + 1
        end
        local perPlayer = math.floor(totalGold / playerCount)
        local perParty = perPlayer * 5
        preview:SetText(string.format(L["GOLDSPLIT_PREVIEW_FORMAT"], FormatGold(perPlayer), FormatGold(perParty)))
    end
    popup.UpdatePreview = UpdatePreview

    inputBox:SetScript("OnTextChanged", UpdatePreview)
    nPlusOne:SetScript("OnClick", UpdatePreview)
    UpdatePreview()

    local confirmBtn = UI:CreateButton(popup, 120, 32, L["GOLDSPLIT_SHARE_CHAT"])
    confirmBtn:SetPoint("BOTTOMLEFT", 25, 15)
    confirmBtn:SetBackdropColor(unpack(UI.colors.accent))
    confirmBtn.text:SetTextColor(1, 1, 1)
    confirmBtn:SetScript("OnClick", function()
        local playerCount = tonumber(inputBox:GetText()) or 1
        playerCount = math.max(1, playerCount)
        if nPlusOne:GetChecked() then
            playerCount = playerCount + 1
        end

        local perPlayer = math.floor(totalGold / playerCount)
        local perParty = perPlayer * 5
        local nPlusText = nPlusOne:GetChecked() and "(N+1)" or ""

        local message = string.format("Total: %sG / Players: %d %s / Per party: %sG / Per person: %sG",
            FormatGold(totalGold), playerCount, nPlusText, FormatGold(perParty), FormatGold(perPlayer))

        -- 채팅으로 전송
        local chatType = self.db.chatType or "SAY"
        if IsInRaid() then
            chatType = "RAID"
        elseif IsInGroup() then
            chatType = "PARTY"
        end

        SendChatMessage(message, chatType)
        popup:Hide()
    end)

    local cancelBtn = UI:CreateButton(popup, 100, 32, L["GOLDSPLIT_CANCEL"])
    cancelBtn:SetPoint("BOTTOMRIGHT", -25, 15)
    cancelBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    inputBox:SetScript("OnEnterPressed", function()
        confirmBtn:Click()
    end)

    self.calcPopup = popup
    popup:Show()
end

-- 모듈 등록
DDingToolKit:RegisterModule("GoldSplit", GoldSplit)
