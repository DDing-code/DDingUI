--[[
    DDingToolKit - CombatTimer Module
    전투 타이머 표시
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF" -- [12.0.1]
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: " -- [STYLE]

-- CombatTimer 모듈
local CombatTimer = {}
ns.CombatTimer = CombatTimer

-- 로컬 변수
local startTime = nil
local timerFrame = nil
local eventFrame = nil

-- 초기화
function CombatTimer:OnInitialize()
    self.db = ns.db.profile.CombatTimer
end

-- 활성화
function CombatTimer:OnEnable()
    -- 이벤트 프레임 생성
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end

    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- 전투 시작
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- 전투 종료

    eventFrame:SetScript("OnEvent", function(f, event)
        if event == "PLAYER_REGEN_DISABLED" then
            self:StartTimer()
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:StopTimer()
        end
    end)

    -- 타이머 프레임 생성
    self:CreateTimerFrame()

    -- 이미 전투 중이면 타이머 시작
    if InCombatLockdown() then
        self:StartTimer()
    end
end

-- 비활성화
function CombatTimer:OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if timerFrame then
        timerFrame:Hide()
    end
    startTime = nil
end

-- 타이머 프레임 생성
function CombatTimer:CreateTimerFrame()
    if timerFrame then return end

    local frame = CreateFrame("Frame", "DDingToolKit_CombatTimerFrame", UIParent)
    frame:SetSize(120, 40)
    frame:SetPoint(self.db.position.point or "TOP", UIParent, self.db.position.relativePoint or "TOP", self.db.position.x or 0, self.db.position.y or -100)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- 드래그 가능
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not CombatTimer.db.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        CombatTimer.db.position.point = point
        CombatTimer.db.position.relativePoint = relativePoint
        CombatTimer.db.position.x = x
        CombatTimer.db.position.y = y
    end)

    -- 배경 텍스쳐
    frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture(SL_FLAT) -- [12.0.1]
    frame.bg:SetVertexColor(0, 0, 0, 0.5)
    frame.bg:Hide()

    -- 메인 시간 텍스트 (분:초)
    frame.mainText = frame:CreateFontString(nil, "OVERLAY")
    frame.mainText:SetFont(self.db.font or SL_FONT, self.db.fontSize or 26, "OUTLINE")
    frame.mainText:SetText("0:00")
    frame.mainText:SetTextColor(1, 1, 1, 1)

    -- 밀리초 텍스트
    frame.msText = frame:CreateFontString(nil, "OVERLAY")
    frame.msText:SetFont(self.db.font or SL_FONT, (self.db.fontSize or 26) * 0.5, "OUTLINE")
    frame.msText:SetText(".00")
    frame.msText:SetTextColor(1, 1, 1, 0.8)

    -- 업데이트 스크립트
    frame:SetScript("OnUpdate", function(self, elapsed)
        CombatTimer:UpdateTimer()
    end)

    timerFrame = frame
    self:UpdateFrameStyle()
end

-- 프레임 스타일 업데이트
function CombatTimer:UpdateFrameStyle()
    if not timerFrame then return end

    -- 폰트 업데이트
    local font = self.db.font or SL_FONT
    local size = self.db.fontSize or 26
    timerFrame.mainText:SetFont(font, size, "OUTLINE")
    timerFrame.msText:SetFont(font, size * 0.5, "OUTLINE")

    -- 색상
    local r = self.db.textColor[1] or 1
    local g = self.db.textColor[2] or 1
    local b = self.db.textColor[3] or 1
    timerFrame.mainText:SetTextColor(r, g, b, 1)
    timerFrame.msText:SetTextColor(r, g, b, 0.8)

    -- 밀리초 표시 여부
    if self.db.showMilliseconds then
        timerFrame.msText:Show()
    else
        timerFrame.msText:Hide()
    end

    -- 배경 표시/숨김
    if timerFrame.bg then
        if self.db.showBackground then
            timerFrame.bg:SetVertexColor(0, 0, 0, self.db.bgAlpha or 0.5)
            timerFrame.bg:Show()
        else
            timerFrame.bg:Hide()
        end
    end

    -- 크기 조정
    local scale = self.db.scale or 1
    timerFrame:SetScale(scale)

    -- 텍스트 정렬 업데이트
    self:UpdateTextAlignment()
end

-- 텍스트 정렬 업데이트
function CombatTimer:UpdateTextAlignment()
    if not timerFrame then return end

    local align = self.db.textAlign or "CENTER"
    local padding = 8

    -- 텍스트 크기 계산
    local mainWidth = timerFrame.mainText:GetStringWidth()
    local msWidth = self.db.showMilliseconds and timerFrame.msText:GetStringWidth() or 0
    local totalWidth = mainWidth + msWidth
    local height = timerFrame.mainText:GetStringHeight()

    if totalWidth <= 0 then totalWidth = 80 end
    if height <= 0 then height = 30 end

    -- 프레임 크기 설정
    timerFrame:SetSize(totalWidth + padding * 2, height + padding)

    -- 텍스트 위치 설정
    timerFrame.mainText:ClearAllPoints()
    timerFrame.msText:ClearAllPoints()

    if align == "LEFT" then
        timerFrame.mainText:SetPoint("LEFT", timerFrame, "LEFT", padding, 0)
        timerFrame.msText:SetPoint("LEFT", timerFrame.mainText, "RIGHT", 0, -4)
    elseif align == "RIGHT" then
        if self.db.showMilliseconds then
            timerFrame.msText:SetPoint("RIGHT", timerFrame, "RIGHT", -padding, -4)
            timerFrame.mainText:SetPoint("RIGHT", timerFrame.msText, "LEFT", 0, 4)
        else
            timerFrame.mainText:SetPoint("RIGHT", timerFrame, "RIGHT", -padding, 0)
        end
    else  -- CENTER
        if self.db.showMilliseconds then
            timerFrame.mainText:SetPoint("RIGHT", timerFrame, "CENTER", 0, 0)
            timerFrame.msText:SetPoint("LEFT", timerFrame.mainText, "RIGHT", 0, -4)
        else
            timerFrame.mainText:SetPoint("CENTER", timerFrame, "CENTER", 0, 0)
        end
    end
end

-- 타이머 시작
function CombatTimer:StartTimer()
    startTime = GetTime()
    if timerFrame then
        -- bg가 없으면 생성 (기존 프레임 호환)
        if not timerFrame.bg then
            timerFrame.bg = timerFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
            timerFrame.bg:SetAllPoints(timerFrame)
            timerFrame.bg:SetTexture(SL_FLAT) -- [12.0.1]
            timerFrame.bg:SetVertexColor(0, 0, 0, 0.5)
        end
        timerFrame:Show()
        self:UpdateFrameStyle()  -- 배경, 폰트 등 스타일 적용
        self:UpdateTimer()
    end

    -- 소리 알림 -- [12.0.1] ns:PlaySound 통합
    if self.db.soundOnStart then
        local soundFile = self.db.soundFile
        local customPath = self.db.soundCustomPath
        local channel = self.db.soundChannel or "Master"
        if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, channel, customPath)
        else
            PlaySound(SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_GO or 8959, channel)
        end
    end
end

-- 타이머 정지
function CombatTimer:StopTimer()
    if timerFrame and startTime then
        -- 최종 시간 표시 유지
        self:UpdateTimer()

        -- 전투 종료 후 표시 시간
        if self.db.hideDelay > 0 then
            C_Timer.After(self.db.hideDelay, function()
                if not InCombatLockdown() and timerFrame then
                    timerFrame:Hide()
                end
            end)
        else
            timerFrame:Hide()
        end

        -- 채팅에 전투 시간 출력
        if self.db.printToChat then
            local combatTime = GetTime() - startTime
            local minutes = math.floor(combatTime / 60)
            local seconds = combatTime % 60
            print(string.format(CHAT_PREFIX .. L["COMBATTIMER_TIME_RESULT"], minutes, seconds)) -- [STYLE]
        end
    end

    startTime = nil
end

-- 타이머 업데이트
function CombatTimer:UpdateTimer()
    if not timerFrame or not startTime then return end

    local combatTime = GetTime() - startTime
    local minutes = math.floor(combatTime / 60)
    local seconds = math.floor(combatTime % 60)
    local milliseconds = math.floor((combatTime % 1) * 100)

    local newMain = string.format("%d:%02d", minutes, seconds)
    local newMs = string.format(".%02d", milliseconds)

    -- [PERF] 텍스트가 실제로 바뀔 때만 SetText + 정렬 갱신
    local oldMain = timerFrame.mainText:GetText()
    if oldMain ~= newMain then
        timerFrame.mainText:SetText(newMain)
        timerFrame.msText:SetText(newMs)
        self:UpdateTextAlignment()
    else
        timerFrame.msText:SetText(newMs)
    end

    -- 시간대별 색상 변경 (선택적)
    if self.db.colorByTime then
        if combatTime < 30 then
            timerFrame.mainText:SetTextColor(1, 1, 1)  -- 흰색
        elseif combatTime < 60 then
            timerFrame.mainText:SetTextColor(1, 1, 0)  -- 노랑
        elseif combatTime < 120 then
            timerFrame.mainText:SetTextColor(1, 0.5, 0)  -- 주황
        else
            timerFrame.mainText:SetTextColor(1, 0, 0)  -- 빨강
        end
    end
end

-- 테스트 모드
function CombatTimer:TestTimer()
    if startTime then
        self:StopTimer()
    else
        startTime = GetTime()
        if timerFrame then
            -- bg가 없으면 생성 (기존 프레임 호환)
            if not timerFrame.bg then
                timerFrame.bg = timerFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
                timerFrame.bg:SetAllPoints(timerFrame)
                timerFrame.bg:SetTexture(SL_FLAT) -- [12.0.1]
                timerFrame.bg:SetVertexColor(0, 0, 0, 0.5)
            end
            timerFrame:Show()
            self:UpdateFrameStyle()  -- 배경, 폰트 등 스타일 적용
        end
        print(CHAT_PREFIX .. L["COMBATTIMER_TEST_START"]) -- [STYLE]
    end
end

-- 위치 초기화
function CombatTimer:ResetPosition()
    self.db.position = {
        point = "TOP",
        relativePoint = "TOP",
        x = 0,
        y = -100
    }
    if timerFrame then
        timerFrame:ClearAllPoints()
        timerFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("CombatTimer", CombatTimer)
