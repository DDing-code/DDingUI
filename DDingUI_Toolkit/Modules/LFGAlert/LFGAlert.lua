--[[
    DDingToolKit - LFGAlert Module
    파티 신청 알림 로직
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
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
local editPreview = false

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
    if ns.CancelManagedSoundsBySource then ns:CancelManagedSoundsBySource("LFGAlert") end
    editPreview = false
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    self:HideAlert(true)
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
        local soundKit = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960
        if ns.RequestSound then
            ns:RequestSound({
                source = "LFGAlert",
                key = "applicant",
                soundFile = soundFile,
                customPath = customPath,
                soundKit = soundKit,
                channel = channel,
                priority = 40,
                canQueue = true,
                immediate = isTest == true,
            })
        elseif (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, channel, customPath)
        else
            PlaySound(soundKit, channel)
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
    if type(ns.CreateCalmPartyAlert) ~= "function" then return end

    self.alertVisual = ns.CreateCalmPartyAlert("DDingToolKit_LFGAlertFrame")
    self.alertFrame = self.alertVisual.frame
    self:ApplySettings()
end

function LFGAlert:GetAlertPosition()
    local position = self.db and self.db.alertPosition or "TOP"
    if position == "CENTER" then
        return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 100 }
    elseif position == "BOTTOM" then
        return { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 200 }
    end
    return { point = "TOP", relativePoint = "TOP", x = 0, y = -100 }
end

function LFGAlert:ApplySettings()
    if not self.db then return end
    if not self.alertVisual then
        self:CreateAlertFrame()
        if not self.alertVisual then return end
    end
    self.alertVisual:Apply(self.db, self:GetAlertPosition())

    if editPreview then
        self:ShowAlert(3, true)
    end
end

-- 알림 표시
function LFGAlert:ShowAlert(count, isTest)
    if not self.alertVisual then self:CreateAlertFrame() end
    if not self.alertVisual then return end

    local title
    local subtitle
    if isTest then
        title = L["LFGALERT_TEST_TEXT"]
        subtitle = L["LFGALERT_WORKING_PROPERLY"]
    else
        title = L["LFGALERT_NEW_APPLICANT_TITLE"]
        subtitle = string.format(L["LFGALERT_WAITING_COUNT"], count)
    end

    self.alertVisual:Apply(self.db, self:GetAlertPosition())
    self.alertVisual:Show(title, subtitle, {
        duration = tonumber(self.db.alertDuration) or 5,
        nodeCount = math.max(1, math.min(5, tonumber(count) or 1)),
        animated = self.db.animationEnabled ~= false,
        persistent = editPreview,
        previewDuration = 3.6,
        motionKind = "APPLICATION",
    })
end

-- 알림 숨기기
function LFGAlert:HideAlert(immediate)
    if self.alertVisual then self.alertVisual:Hide(immediate == true) end
end

-- 편집 모드 연동 (Movers)
function LFGAlert:EnterEditPreview()
    editPreview = true
    if not self.alertFrame then self:CreateAlertFrame() end
    self:ShowAlert(3, true)
end

function LFGAlert:RefreshEditPreview()
    if not editPreview then return end
    self:ApplySettings()
end

function LFGAlert:ExitEditPreview()
    editPreview = false
    self:HideAlert(true)
end

function LFGAlert:OnMediaChanged()
    self:ApplySettings()
end

-- 모듈 등록
DDingToolKit:RegisterModule("LFGAlert", LFGAlert)
