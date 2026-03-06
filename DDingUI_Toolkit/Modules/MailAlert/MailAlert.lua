--[[
    DDingToolKit - MailAlert Module
    새 메일 알림 로직
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [STYLE]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

-- MailAlert 모듈
local MailAlert = {}
ns.MailAlert = MailAlert

-- 로컬 변수
local hadMail = false
local lastAlertTime = 0
local eventFrame = nil

-- 초기화
function MailAlert:OnInitialize()
    self.db = ns.db.profile.MailAlert
end

-- 활성화
function MailAlert:OnEnable()
    -- 이벤트 프레임 생성
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end

    eventFrame:RegisterEvent("UPDATE_PENDING_MAIL")
    eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    eventFrame:SetScript("OnEvent", function(f, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            -- 초기 메일 상태 저장
            hadMail = HasNewMail()
        elseif event == "UPDATE_PENDING_MAIL" or event == "MAIL_INBOX_UPDATE" then
            self:CheckForNewMail()
        end
    end)

    -- 알림 프레임 생성
    self:CreateAlertFrame()
end

-- 비활성화
function MailAlert:OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if self.alertFrame then
        self.alertFrame:Hide()
    end
end

-- 새 메일 확인
function MailAlert:CheckForNewMail()
    -- 쿨다운 체크
    if GetTime() - lastAlertTime < self.db.cooldown then
        return
    end

    -- 전투 중 숨기기
    if self.db.hideInCombat and InCombatLockdown() then
        return
    end

    -- 인스턴스 내 숨기기
    if self.db.hideInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena") then
            return
        end
    end

    -- 새 메일 확인
    local hasNewMail = HasNewMail()

    if hasNewMail and not hadMail then
        self:TriggerAlert()
        lastAlertTime = GetTime()
    end

    hadMail = hasNewMail
end

-- 알림 트리거
function MailAlert:TriggerAlert(isTest)
    -- 소리 알림 -- [12.0.1] ns:PlaySound 통합
    if self.db.soundEnabled then
        local soundFile = self.db.soundFile
        local customPath = self.db.soundCustomPath
        local channel = self.db.soundChannel or "Master"
        if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, channel, customPath)
        else
            PlaySound(SOUNDKIT.TELL_MESSAGE, channel)
        end
    end

    -- 화면 깜빡임
    if self.db.flashEnabled then
        FlashClientIcon()
    end

    -- 화면 알림
    if self.db.screenAlertEnabled and self.alertFrame then
        self:ShowAlert(isTest)
    end

    -- 채팅 알림
    if self.db.chatAlert then
        if isTest then
            print(CHAT_PREFIX .. L["MAILALERT_TEST_MSG"]) -- [STYLE]
        else
            print(CHAT_PREFIX .. L["MAILALERT_NEW_MAIL_ARRIVED"]) -- [STYLE]
        end
    end
end

-- 플레이어 진영 가져오기
function MailAlert:GetPlayerFaction()
    local faction = UnitFactionGroup("player")
    return faction or "Alliance"
end

-- 알림 프레임 생성
function MailAlert:CreateAlertFrame()
    if self.alertFrame then return end

    -- WeakAuras 원본 비율: 411x63 + 메일 아이콘 64x64
    local frame = CreateFrame("Frame", "DDingToolKit_MailAlertFrame", UIParent)
    frame:SetSize(475, 64)  -- 배경(411) + 아이콘(64)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()

    -- 진영 배경 텍스처 (원본 비율 411x63)
    local factionBg = frame:CreateTexture(nil, "BACKGROUND")
    factionBg:SetSize(411, 63)
    factionBg:SetPoint("LEFT", frame, "LEFT", 0, 0)
    factionBg:SetTexCoord(0, 1, 0, 1)  -- 선명하게
    frame.factionBg = factionBg

    -- 메일 아이콘 (WeakAuras의 communities-icon-invitemail)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("LEFT", factionBg, "RIGHT", -15, 0)  -- 진영 배경 오른쪽, 15px 왼쪽으로 붙임
    icon:SetAtlas("communities-icon-invitemail")
    frame.icon = icon

    -- 메인 텍스트 (배경 중앙에 배치, 약간 오른쪽으로)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", factionBg, "CENTER", 20, 0)
    text:SetText(L["MAILALERT_NEW_MAIL_TEXT"])
    text:SetTextColor(1, 1, 1)
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    frame.text = text

    -- 서브 텍스트 (숨김 - 필요시 사용)
    local subText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subText:SetPoint("BOTTOMLEFT", factionBg, "BOTTOMLEFT", 10, 5)
    subText:SetText("")
    subText:SetTextColor(1, 1, 1)
    subText:Hide()
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

    -- 펄스 애니메이션 (Alpha 기반으로 변경 - Scale은 불안정)
    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local pulseAnim = pulse:CreateAnimation("Alpha")
    pulseAnim:SetFromAlpha(1)
    pulseAnim:SetToAlpha(0.7)
    pulseAnim:SetDuration(0.5)
    frame.pulse = pulse

    self.alertFrame = frame
end

-- 알림 표시
function MailAlert:ShowAlert(isTest)
    if not self.alertFrame then return end

    local frame = self.alertFrame

    -- 기존 애니메이션 모두 중지
    if frame.fadeIn and frame.fadeIn:IsPlaying() then frame.fadeIn:Stop() end
    if frame.fadeOut and frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end
    if frame.pulse and frame.pulse:IsPlaying() then frame.pulse:Stop() end

    -- 텍스트 업데이트
    if isTest then
        frame.text:SetText(L["MAILALERT_TEST_TEXT"])
    else
        frame.text:SetText(L["MAILALERT_NEW_MAIL_TEXT"])
    end

    -- 진영별 배경 설정 (Atlas 사용)
    local faction = self:GetPlayerFaction()
    if faction == "Horde" then
        frame.factionBg:SetAtlas("Objective-Header-CampaignHorde")
    else
        frame.factionBg:SetAtlas("Objective-Header-CampaignAlliance")
    end

    -- 위치 설정
    frame:ClearAllPoints()
    local position = self.db.alertPosition or "CENTER"
    if position == "TOP" then
        frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    elseif position == "CENTER" then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
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
    local animType = self.db.alertAnimation or "pulse"
    if animType == "pulse" then
        self:AnimatePulse()
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
function MailAlert:HideAlert()
    if not self.alertFrame then return end

    local frame = self.alertFrame

    -- 펄스 애니메이션 중지
    if frame.pulse and frame.pulse:IsPlaying() then
        frame.pulse:Stop()
    end

    -- 페이드 아웃 재생 (미리 생성된 애니메이션 재사용)
    if frame.fadeOut then
        frame:SetAlpha(1)
        frame.fadeOut:Play()
    else
        frame:Hide()
    end
end

-- 펄스 애니메이션 (미리 생성된 애니메이션 재사용)
function MailAlert:AnimatePulse()
    if not self.alertFrame or not self.alertFrame.pulse then return end

    local frame = self.alertFrame
    frame.pulse:Play()

    -- 3초 후 펄스 중지
    C_Timer.After(3, function()
        if frame.pulse and frame.pulse:IsPlaying() then
            frame.pulse:Stop()
            frame:SetAlpha(1)
        end
    end)
end

-- 페이드 애니메이션 (미리 생성된 애니메이션 재사용)
function MailAlert:AnimateFade()
    if not self.alertFrame or not self.alertFrame.fadeIn then return end

    local frame = self.alertFrame
    frame:SetAlpha(0)
    frame.fadeIn:Play()
end

-- 모듈 등록
DDingToolKit:RegisterModule("MailAlert", MailAlert)
