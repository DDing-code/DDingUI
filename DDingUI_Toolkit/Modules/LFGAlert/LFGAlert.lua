--[[
    DDingToolKit - LFGAlert Module
    파티 신청 알림 로직
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [STYLE]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

-- LFGAlert 모듈
local LFGAlert = {}
ns.LFGAlert = LFGAlert

-- 로컬 변수
local previousApplicants = {}
local lastAlertTime = 0
local eventFrame = nil

-- 초기화
function LFGAlert:OnInitialize()
    self.db = ns.db.profile.LFGAlert
end

-- 활성화
function LFGAlert:OnEnable()
    -- 이벤트 프레임 생성
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end

    eventFrame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
    eventFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")

    eventFrame:SetScript("OnEvent", function(f, event, ...)
        if event == "LFG_LIST_APPLICANT_UPDATED" or event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
            self:CheckForNewApplicants()
        end
    end)

    -- 알림 프레임 생성
    self:CreateAlertFrame()
end

-- 비활성화
function LFGAlert:OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if self.alertFrame then
        self.alertFrame:Hide()
    end
end

-- 새 신청자 확인
function LFGAlert:CheckForNewApplicants()
    -- 쿨다운 체크
    if GetTime() - lastAlertTime < self.db.cooldown then
        return
    end

    -- 파티장/부파티장 체크
    if self.db.leaderOnly then
        if not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
            return
        end
    end

    -- 신청자 목록 가져오기
    local applicants = C_LFGList.GetApplicants()
    if not applicants then return end

    -- 새 신청자 수 계산
    local newCount = 0
    for _, applicantID in ipairs(applicants) do
        if not previousApplicants[applicantID] then
            newCount = newCount + 1
        end
    end

    if newCount > 0 then
        self:TriggerAlert(newCount)
        lastAlertTime = GetTime()
    end

    -- 목록 업데이트
    wipe(previousApplicants)
    for _, applicantID in ipairs(applicants) do
        previousApplicants[applicantID] = true
    end
end

-- 알림 트리거
function LFGAlert:TriggerAlert(count, isTest)
    -- 소리 알림 -- [12.0.1] ns:PlaySound 통합
    if self.db.soundEnabled then
        local soundFile = self.db.soundFile
        local customPath = self.db.soundCustomPath
        local channel = self.db.soundChannel or "Master"
        if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, channel, customPath)
        else
            PlaySound(SOUNDKIT.READY_CHECK, channel)
        end
    end

    -- 화면 깜빡임
    if self.db.flashEnabled then
        FlashClientIcon()
    end

    -- 화면 알림
    if self.db.screenAlertEnabled and self.alertFrame then
        self:ShowAlert(count, isTest)
    end

    -- 자동 LFG 창 열기
    if self.db.autoOpenLFG and not InCombatLockdown() and not isTest then
        if PVEFrame and not PVEFrame:IsVisible() then
            PVEFrame_ShowFrame("GroupFinderFrame")
        end
    end

    -- 채팅 알림
    if self.db.chatAlert then
        if isTest then
            print(CHAT_PREFIX .. L["LFGALERT_TEST_MSG"]) -- [STYLE]
        else
            print(string.format(CHAT_PREFIX .. L["LFGALERT_APPLICANTS_ARRIVED"], count)) -- [STYLE]
        end
    end
end

-- 알림 프레임 생성
function LFGAlert:CreateAlertFrame()
    if self.alertFrame then return end

    local frame = CreateFrame("Frame", "DDingToolKit_LFGAlertFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 80)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop(UI.backdrop)
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.0, 0.8, 0.0, 1)
    frame:Hide()

    -- 아이콘
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("LEFT", 18, 0)
    icon:SetTexture("Interface\\LFGFrame\\LFGIcon-ReturntoKarazhan")
    frame.icon = icon

    -- 텍스트
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 15, -8)
    text:SetText(L["LFGALERT_NEW_APPLICANT_TITLE"])
    text:SetTextColor(0, 1, 0)
    frame.text = text

    -- 서브 텍스트
    local subText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
    subText:SetText("")
    subText:SetTextColor(0.8, 0.8, 0.8)
    frame.subText = subText

    -- 애니메이션 그룹들 (한 번만 생성하여 재사용)
    -- 페이드 인
    local fadeIn = frame:CreateAnimationGroup()
    local fadeInAnim = fadeIn:CreateAnimation("Alpha")
    fadeInAnim:SetFromAlpha(0)
    fadeInAnim:SetToAlpha(1)
    fadeInAnim:SetDuration(0.3)
    frame.fadeIn = fadeIn

    -- 페이드 아웃
    local fadeOut = frame:CreateAnimationGroup()
    local fadeOutAnim = fadeOut:CreateAnimation("Alpha")
    fadeOutAnim:SetFromAlpha(1)
    fadeOutAnim:SetToAlpha(0)
    fadeOutAnim:SetDuration(0.3)
    fadeOut:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)
    frame.fadeOut = fadeOut

    -- 바운스 애니메이션 (Alpha 기반으로 변경 - Translation은 불안정)
    local bounce = frame:CreateAnimationGroup()
    bounce:SetLooping("BOUNCE")
    local bounceAnim = bounce:CreateAnimation("Alpha")
    bounceAnim:SetFromAlpha(1)
    bounceAnim:SetToAlpha(0.6)
    bounceAnim:SetDuration(0.3)
    frame.bounce = bounce

    self.alertFrame = frame
end

-- 알림 표시
function LFGAlert:ShowAlert(count, isTest)
    if not self.alertFrame then return end

    local frame = self.alertFrame

    -- 기존 애니메이션 모두 중지
    if frame.fadeIn and frame.fadeIn:IsPlaying() then frame.fadeIn:Stop() end
    if frame.fadeOut and frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end
    if frame.bounce and frame.bounce:IsPlaying() then frame.bounce:Stop() end

    -- 텍스트 업데이트
    if isTest then
        frame.text:SetText(L["LFGALERT_TEST_TEXT"])
        frame.subText:SetText(L["LFGALERT_WORKING_PROPERLY"])
    else
        frame.text:SetText(L["LFGALERT_NEW_APPLICANT_TITLE"])
        frame.subText:SetText(string.format(L["LFGALERT_WAITING_COUNT"], count))
    end

    -- 위치 설정
    frame:ClearAllPoints()
    local position = self.db.alertPosition or "TOP"
    if position == "TOP" then
        frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    elseif position == "CENTER" then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    elseif position == "BOTTOM" then
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    end

    -- 크기 조절
    local scale = self.db.alertScale or 1.0
    frame:SetScale(scale)

    -- 표시
    frame:Show()
    frame:SetAlpha(1)

    -- 애니메이션
    local animType = self.db.alertAnimation or "bounce"
    if animType == "bounce" then
        self:AnimateBounce()
    elseif animType == "fade" then
        self:AnimateFade()
    end

    -- 자동 숨기기
    local duration = self.db.alertDuration or 5
    C_Timer.After(duration, function()
        if frame:IsShown() then
            self:HideAlert()
        end
    end)
end

-- 알림 숨기기
function LFGAlert:HideAlert()
    if not self.alertFrame then return end

    local frame = self.alertFrame

    -- 바운스 애니메이션 중지
    if frame.bounce and frame.bounce:IsPlaying() then
        frame.bounce:Stop()
    end

    -- 페이드 아웃 재생 (미리 생성된 애니메이션 재사용)
    if frame.fadeOut then
        frame:SetAlpha(1)
        frame.fadeOut:Play()
    else
        frame:Hide()
    end
end

-- 바운스 애니메이션 (미리 생성된 애니메이션 재사용)
function LFGAlert:AnimateBounce()
    if not self.alertFrame or not self.alertFrame.bounce then return end

    local frame = self.alertFrame
    frame.bounce:Play()

    -- 2초 후 바운스 중지
    C_Timer.After(2, function()
        if frame.bounce and frame.bounce:IsPlaying() then
            frame.bounce:Stop()
            frame:SetAlpha(1)
        end
    end)
end

-- 페이드 애니메이션 (미리 생성된 애니메이션 재사용)
function LFGAlert:AnimateFade()
    if not self.alertFrame or not self.alertFrame.fadeIn then return end

    local frame = self.alertFrame
    frame:SetAlpha(0)
    frame.fadeIn:Play()
end

-- 모듈 등록
DDingToolKit:RegisterModule("LFGAlert", LFGAlert)
