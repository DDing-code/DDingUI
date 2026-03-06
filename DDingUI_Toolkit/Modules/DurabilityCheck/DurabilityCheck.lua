--[[
    DDingToolKit - DurabilityCheck Module
    장비 내구도가 낮을 때 화면에 표시 (전투 중 제외)
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF" -- [12.0.1]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

-- DurabilityCheck 모듈
local DurabilityCheck = {}
ns.DurabilityCheck = DurabilityCheck

-- 로컬 변수
local alertFrame = nil
local eventFrame = nil
local updateTimer = nil
local isShowing = false

-- 초기화
function DurabilityCheck:OnInitialize()
    self.db = ns.db.profile.DurabilityCheck
    if not self.db then
        self.db = {}
        ns.db.profile.DurabilityCheck = self.db
    end
end

-- 활성화
function DurabilityCheck:OnEnable()
    self:CreateAlertFrame()
    self:RegisterEvents()

    -- 슬래시 커맨드
    SLASH_DURABILITYCHECK1 = "/내구도"
    SLASH_DURABILITYCHECK2 = "/durability"
    SlashCmdList["DURABILITYCHECK"] = function()
        self:CheckDurability(true)
    end

    -- 초기 체크
    C_Timer.After(2, function()
        self:CheckDurability()
    end)
end

-- 비활성화
function DurabilityCheck:OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if alertFrame then
        alertFrame:Hide()
    end
    if updateTimer then
        updateTimer:Cancel()
        updateTimer = nil
    end
end

-- 이벤트 등록
function DurabilityCheck:RegisterEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end

    -- 내구도 관련 이벤트
    eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("MERCHANT_CLOSED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- 전투 종료
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- 전투 시작
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    eventFrame:SetScript("OnEvent", function(f, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            -- 전투 시작 - 숨기기
            self:HideAlert()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- 전투 종료 - 다시 체크
            C_Timer.After(0.5, function()
                self:CheckDurability()
            end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(2, function()
                self:CheckDurability()
            end)
        else
            -- 내구도 변경 이벤트
            C_Timer.After(0.2, function()
                self:CheckDurability()
            end)
        end
    end)
end

-- 내구도 계산
function DurabilityCheck:GetLowestDurability()
    local minPercent = 101
    local minSlot = nil

    for i = 1, 18 do
        local cur, max = GetInventoryItemDurability(i)
        if cur and max and max > 0 then
            local percent = (cur / max) * 100
            if percent < minPercent then
                minPercent = percent
                minSlot = i
            end
        end
    end

    if minPercent <= 100 then
        return math.floor(minPercent), minSlot
    else
        return nil, nil
    end
end

-- 내구도 색상
function DurabilityCheck:GetDurabilityColor(percent)
    if percent <= 25 then
        return 1, 0.2, 0.2  -- 빨강 (위험)
    elseif percent <= 50 then
        return 1, 0.56, 0.36  -- 주황 (경고)
    elseif percent <= 75 then
        return 1, 1, 0.3  -- 노랑 (주의)
    else
        return 0.3, 1, 0.3  -- 녹색 (양호)
    end
end

-- 알림 프레임 생성
function DurabilityCheck:CreateAlertFrame()
    if alertFrame then return end

    alertFrame = CreateFrame("Frame", "DDingToolKit_DurabilityFrame", UIParent)
    alertFrame:SetSize(200, 80)
    alertFrame:SetFrameStrata("HIGH")
    alertFrame:Hide()

    -- 제목 텍스트
    local title = alertFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(self.db.font or SL_FONT, self.db.titleSize or 24, "OUTLINE") -- [12.0.1]
    title:SetPoint("TOP", 0, -10)
    title:SetTextColor(1, 0.56, 0.36, 1)
    title:SetText(L["DURABILITY_REPAIR_NEEDED"])
    title:SetShadowOffset(2, -2)
    title:SetShadowColor(0, 0, 0, 1)
    alertFrame.title = title

    -- 퍼센트 텍스트
    local percent = alertFrame:CreateFontString(nil, "OVERLAY")
    percent:SetFont(self.db.font or SL_FONT, self.db.percentSize or 36, "OUTLINE") -- [12.0.1]
    percent:SetPoint("TOP", title, "BOTTOM", 0, -5)
    percent:SetShadowOffset(2, -2)
    percent:SetShadowColor(0, 0, 0, 1)
    alertFrame.percent = percent

    -- 드래그 가능
    alertFrame:SetMovable(true)
    alertFrame:EnableMouse(true)
    alertFrame:RegisterForDrag("LeftButton")
    alertFrame:SetScript("OnDragStart", function(self)
        if not DurabilityCheck.db.locked then
            self:StartMoving()
        end
    end)
    alertFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- 위치 저장
        local point, _, relPoint, x, y = self:GetPoint()
        DurabilityCheck.db.position = {
            point = point,
            relativePoint = relPoint,
            x = x,
            y = y,
        }
    end)

    -- 저장된 위치 적용
    self:ApplyPosition()

    self.alertFrame = alertFrame
end

-- 위치 적용
function DurabilityCheck:ApplyPosition()
    if not alertFrame then return end

    alertFrame:ClearAllPoints()
    local pos = self.db.position
    if pos and pos.point then
        alertFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        -- 기본 위치 (DurabilityFrame 근처)
        alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end

    -- 크기 조절
    local scale = self.db.scale or 1.0
    alertFrame:SetScale(scale)
end

-- 내구도 체크 및 표시
function DurabilityCheck:CheckDurability(isTest)
    if not alertFrame then return end

    -- 전투 중이면 표시 안함
    if InCombatLockdown() and not isTest then
        self:HideAlert()
        return
    end

    local percent = self:GetLowestDurability()

    -- 테스트 모드
    if isTest then
        percent = percent or 50
        print(string.format(CHAT_PREFIX .. L["DURABILITY_CHECK_MSG"], percent)) -- [STYLE]
    end

    if not percent then
        self:HideAlert()
        return
    end

    -- 임계값 체크
    local threshold = self.db.threshold or 25
    if percent > threshold and not isTest then
        self:HideAlert()
        return
    end

    -- 표시
    self:ShowAlert(percent, isTest)
end

-- 알림 표시
function DurabilityCheck:ShowAlert(percent, isTest)
    if not alertFrame then return end

    local r, g, b = self:GetDurabilityColor(percent)

    alertFrame.percent:SetTextColor(r, g, b, 1)
    alertFrame.percent:SetText(percent .. "%")

    -- 위치 적용
    self:ApplyPosition()

    alertFrame:Show()
    isShowing = true

    -- 소리 재생 (처음 표시될 때만) -- [12.0.1] ns:PlaySound 통합
    if self.db.soundEnabled and not isTest then
        local soundFile = self.db.soundFile
        local customPath = self.db.soundCustomPath
        local channel = self.db.soundChannel or "Master"
        if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, channel, customPath)
        end
    end
end

-- 알림 숨기기
function DurabilityCheck:HideAlert()
    if alertFrame and alertFrame:IsShown() then
        alertFrame:Hide()
        isShowing = false
    end
end

-- 테스트 알림
function DurabilityCheck:TestAlert()
    self:CheckDurability(true)
end

-- 잠금 상태 업데이트
function DurabilityCheck:UpdateLock()
    if alertFrame then
        alertFrame:EnableMouse(not self.db.locked)
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("DurabilityCheck", DurabilityCheck)
