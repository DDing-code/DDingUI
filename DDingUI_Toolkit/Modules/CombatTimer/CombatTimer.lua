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
local CHAT_PREFIX = ns.CHAT_PREFIX -- [STYLE] Core/Core.lua 공통 접두사

-- CombatTimer 모듈
local CombatTimer = {}
ns.CombatTimer = CombatTimer

-- 로컬 변수
local startTime = nil
local timerFrame = nil

-- 초기화
function CombatTimer:OnInitialize()
    self.db = ns.db.profile.CombatTimer
end

-- 활성화
function CombatTimer:OnEnable()
    -- [REFACTOR] 전투 시작/종료는 Core/CombatSession.lua 공용 판정을 따른다.
    -- 짧은 이탈 후 재진입이나 그룹원이 아직 전투 중이면 같은 전투로 이어진다(사망/구원의 영혼 포함).
    local session = ns.CombatSession
    if session then
        session:RegisterCallback(self, function(kind, info)
            if kind == "START" then
                self:StartTimer()
            elseif kind == "END" then
                self:StopTimer(info and info.endedAt)
            end
        end)
    end

    -- 타이머 프레임 생성
    self:CreateTimerFrame()

    -- 이미 전투 중이면 타이머 시작
    if (session and session:IsActive()) or InCombatLockdown() then
        self:StartTimer()
    end
end

-- 비활성화
function CombatTimer:OnDisable()
    if ns.CancelManagedSoundsBySource then ns:CancelManagedSoundsBySource("CombatTimer") end
    if ns.CombatSession then ns.CombatSession:UnregisterCallback(self) end -- [REFACTOR]
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
    if ns.EnableRightClickMouselook then
        ns:EnableRightClickMouselook(frame)
    end
    frame:EnableMouse(false)

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
    timerFrame.mainText:SetTextColor(r, g, b, self.db.textColor[4] or 1)
    timerFrame.msText:SetTextColor(r, g, b, (self.db.textColor[4] or 1) * 0.8)

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
    if startTime then return end

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
        local soundKit = (SOUNDKIT and SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_GO) or 8959
        if ns.RequestSound then
            ns:RequestSound({
                source = "CombatTimer",
                key = "combat-start",
                soundFile = soundFile,
                customPath = customPath,
                soundKit = soundKit,
                channel = channel,
                priority = 55,
            })
        elseif (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, channel, customPath)
        else
            PlaySound(soundKit, channel)
        end
    end
end

-- 타이머 정지
-- endedAt: 공용 판정이 전투가 실제로 끝났다고 본 시각 (확정 대기 시간 제외) -- [REFACTOR]
function CombatTimer:StopTimer(endedAt)
    local stopAt = tonumber(endedAt) or GetTime()
    if startTime and stopAt < startTime then stopAt = GetTime() end
    if timerFrame and startTime then
        -- 최종 시간 표시 유지
        self:UpdateTimer(stopAt)

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
            local combatTime = stopAt - startTime
            local minutes = math.floor(combatTime / 60)
            local seconds = combatTime % 60
            print(string.format(CHAT_PREFIX .. L["COMBATTIMER_TIME_RESULT"], minutes, seconds)) -- [STYLE]
        end
    end

    startTime = nil
end

-- 타이머 업데이트
-- now: 고정할 시각. 없으면 공용 판정의 종료 대기 시작 시각에서 멈추고, 아니면 현재 시각. -- [REFACTOR]
function CombatTimer:UpdateTimer(now)
    if not timerFrame or not startTime then return end

    now = now or (ns.CombatSession and ns.CombatSession:GetClearSince()) or GetTime()
    local combatTime = math.max(0, now - startTime)
    local minutes = math.floor(combatTime / 60)
    local seconds = math.floor(combatTime % 60)
    local oneDecimal = self.db.decimalPlaces == 1
    local fraction = math.floor((combatTime % 1) * (oneDecimal and 10 or 100))

    local newMain = string.format("%d:%02d", minutes, seconds)
    local newMs = string.format(oneDecimal and ".%d" or ".%02d", fraction)

    -- [PERF] 텍스트가 실제로 바뀔 때만 SetText + 정렬 갱신
    local oldMain = timerFrame.mainText:GetText()
    local oldMs = timerFrame.msText:GetText()
    if oldMain ~= newMain or #(oldMs or "") ~= #newMs then
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

-- 편집 모드 연동 (Movers)
function CombatTimer:EnterEditPreview()
    if not timerFrame then
        self:CreateTimerFrame()
    end
    if not startTime then
        startTime = GetTime()
    end
    if timerFrame then
        if not timerFrame.bg then
            timerFrame.bg = timerFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
            timerFrame.bg:SetAllPoints(timerFrame)
            timerFrame.bg:SetTexture(SL_FLAT)
            timerFrame.bg:SetVertexColor(0, 0, 0, 0.5)
        end
        timerFrame:Show()
        self:UpdateFrameStyle()
        self:UpdateTimer()
    end
end

function CombatTimer:ExitEditPreview()
    startTime = nil
    if timerFrame then
        timerFrame:Hide()
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("CombatTimer", CombatTimer)
