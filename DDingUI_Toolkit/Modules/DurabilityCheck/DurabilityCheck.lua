--[[
    DDingToolKit - DurabilityCheck Module
    장비 내구도가 낮을 때 화면에 표시 (전투 중 제외)
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF" -- [12.0.1]
local AlertStyle = ns.CalmAlertStyle
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

-- DurabilityCheck 모듈
local DurabilityCheck = {}
ns.DurabilityCheck = DurabilityCheck

-- 로컬 변수
local alertFrame = nil
local eventFrame = nil
local updateTimer = nil
local isShowing = false
local editPreview = false
local currentPercent = nil
local visualElapsed = 0
local revealProgress = 1
local testToken = 0

local DEFAULT_POSITION = {
    point = "TOP",
    relativePoint = "TOP",
    x = 0,
    y = -150,
}

local function IsSecretValue(value)
    local checker = ns.IsSecretValue or issecretvalue
    if type(checker) ~= "function" then return false end
    local ok, result = pcall(checker, value)
    return ok and result == true
end

local function SafeNumber(value)
    if value == nil or IsSecretValue(value) then return nil end
    local ok, number = pcall(tonumber, value)
    if not ok or IsSecretValue(number) or type(number) ~= "number" or number ~= number then
        return nil
    end
    return number
end

local ALERT_TEXTURES = {
    glowLeft = { "BACKGROUND", -3 },
    glowRight = { "BACKGROUND", -3 },
    panelLeft = { "BACKGROUND", -2 },
    panelRight = { "BACKGROUND", -2 },
    topLeft = { "ARTWORK", -1 },
    topRight = { "ARTWORK", -1 },
    bottomLeft = { "ARTWORK", -1 },
    bottomRight = { "ARTWORK", -1 },
    diamondTopLeft = { "ARTWORK", 1 },
    diamondTopRight = { "ARTWORK", 1 },
    diamondBottomLeft = { "ARTWORK", 1 },
    diamondBottomRight = { "ARTWORK", 1 },
    bottomNodeLeft = { "ARTWORK", 1 },
    bottomNodeRight = { "ARTWORK", 1 },
}
local ALERT_REGION_VERSION = 1

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
    if ns.CancelManagedSoundsBySource then ns:CancelManagedSoundsBySource("DurabilityCheck") end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if alertFrame then
        alertFrame:Hide()
    end
    isShowing = false
    editPreview = false
    currentPercent = nil
    testToken = testToken + 1
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
        local ok, cur, max = pcall(GetInventoryItemDurability, i)
        cur = ok and SafeNumber(cur) or nil
        max = ok and SafeNumber(max) or nil
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
function DurabilityCheck:EnsureAlertRegions()
    if not alertFrame or not AlertStyle then return false end
    if alertFrame._durabilityRegionVersion == ALERT_REGION_VERSION
        and alertFrame.art
        and alertFrame.title
        and alertFrame.percent
        and alertFrame.warningMark then
        return true
    end

    if not alertFrame.art then
        alertFrame.art = CreateFrame("Frame", nil, alertFrame)
        alertFrame.art:SetAllPoints(alertFrame)
    end

    for key, layerInfo in pairs(ALERT_TEXTURES) do
        if not alertFrame[key] then
            alertFrame[key] = AlertStyle.CreateFlatTexture(alertFrame.art, layerInfo[1], layerInfo[2])
        end
    end

    if not alertFrame.title then
        local title = alertFrame.art:CreateFontString(nil, "OVERLAY")
        title:SetPoint("CENTER", alertFrame.art, "CENTER", 0, 9)
        title:SetText(L["DURABILITY_REPAIR_NEEDED"])
        title:SetJustifyH("CENTER")
        title:SetJustifyV("MIDDLE")
        title:SetWordWrap(false)
        title:SetShadowOffset(1, -1)
        title:SetShadowColor(0, 0, 0, 1)
        alertFrame.title = title
    end

    if not alertFrame.percent then
        local percentText = alertFrame.art:CreateFontString(nil, "OVERLAY")
        percentText:SetPoint("CENTER", alertFrame.art, "CENTER", 0, -20)
        percentText:SetJustifyH("CENTER")
        percentText:SetJustifyV("MIDDLE")
        percentText:SetWordWrap(false)
        percentText:SetShadowOffset(1, -1)
        percentText:SetShadowColor(0, 0, 0, 1)
        alertFrame.percent = percentText
    end

    if not alertFrame.warningMark then
        local warningMark = alertFrame.art:CreateFontString(nil, "OVERLAY")
        warningMark:SetText("!")
        warningMark:SetJustifyH("CENTER")
        warningMark:SetJustifyV("MIDDLE")
        warningMark:SetWordWrap(false)
        alertFrame.warningMark = warningMark
    end

    local ready = alertFrame.title ~= nil
        and alertFrame.percent ~= nil
        and alertFrame.warningMark ~= nil
    if ready then
        alertFrame._durabilityRegionVersion = ALERT_REGION_VERSION
    end
    return ready
end

function DurabilityCheck:CreateAlertFrame()
    if not AlertStyle then return end

    if alertFrame then
        if self:EnsureAlertRegions() then
            self.alertFrame = alertFrame
            self:ApplySettings()
        end
        return
    end

    alertFrame = CreateFrame("Frame", "DDingToolKit_DurabilityFrame", UIParent)
    alertFrame:SetSize(460, 120)
    alertFrame:SetFrameStrata("HIGH")
    alertFrame:Hide()

    if not self:EnsureAlertRegions() then return end

    alertFrame:SetScript("OnUpdate", function(_, elapsed)
        DurabilityCheck:UpdateAlertVisual(elapsed)
    end)

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
    if ns.EnableRightClickMouselook then
        ns:EnableRightClickMouselook(alertFrame)
    end

    self.alertFrame = alertFrame
    self:ApplySettings()
end

-- 위치 적용
function DurabilityCheck:ApplyPosition()
    if not alertFrame then return end

    alertFrame:ClearAllPoints()
    local pos = type(self.db.position) == "table" and self.db.position or DEFAULT_POSITION
    alertFrame:SetPoint(
        pos.point or DEFAULT_POSITION.point,
        UIParent,
        pos.relativePoint or pos.point or DEFAULT_POSITION.relativePoint,
        SafeNumber(pos.x) or DEFAULT_POSITION.x,
        SafeNumber(pos.y) or DEFAULT_POSITION.y
    )
end

local function ApplyFont(fontString, font, size, flags)
    local ok, result = pcall(fontString.SetFont, fontString, font, size, flags)
    if not ok or result == false then
        fontString:SetFont(SL_FONT, size, flags)
    end
end

function DurabilityCheck:ApplySettings()
    if not alertFrame or not self.db or not AlertStyle then return end
    if not self:EnsureAlertRegions() then return end

    local width = AlertStyle.Clamp(self.db.width, 320, 700)
    local height = AlertStyle.Clamp(self.db.height, 90, 170)
    local titleSize = AlertStyle.Clamp(self.db.titleSize, 14, 48)
    local percentSize = AlertStyle.Clamp(self.db.percentSize, 20, 72)
    local outline = self.db.fontOutline or "OUTLINE"
    local fontFlags = outline == "NONE" and "" or outline
    local font = self.db.font or SL_FONT

    alertFrame:SetSize(width, height)
    alertFrame:SetScale(AlertStyle.Clamp(self.db.scale, 0.5, 2))
    alertFrame:SetFrameStrata(self.db.frameStrata or "HIGH")
    alertFrame.title:SetWidth(math.max(1, width - 48))
    alertFrame.title:SetHeight(math.max(1, height * 0.28))
    alertFrame.percent:SetWidth(math.max(1, width - 64))
    alertFrame.percent:SetHeight(math.max(1, height * 0.36))
    ApplyFont(alertFrame.title, font, titleSize, fontFlags)
    ApplyFont(alertFrame.percent, font, percentSize, fontFlags)
    ApplyFont(alertFrame.warningMark, font, math.max(12, math.floor(titleSize * 0.58 + 0.5)), "OUTLINE")
    self:ApplyPosition()
    self:UpdateLock()

    if isShowing and currentPercent then
        self:RenderAlert(currentPercent, revealProgress, 1)
    end
end

function DurabilityCheck:RenderAlert(percent, reveal, pulse)
    if not alertFrame or not AlertStyle then return end
    if not self:EnsureAlertRegions() then return end

    reveal = AlertStyle.Clamp01(reveal)
    pulse = AlertStyle.Clamp01(pulse)
    local width = AlertStyle.Clamp(self.db.width, 320, 700)
    local height = AlertStyle.Clamp(self.db.height, 90, 170)
    local titleColor = self.db.titleColor or { 1.00, 0.82, 0.58, 1.00 }
    local lineColor = self.db.lineColor or { 1.00, 0.54, 0.22, 0.88 }
    local panelColor = self.db.panelColor or { 0.12, 0.045, 0.015, 0.82 }
    local glowColor = self.db.glowColor or { 1.00, 0.30, 0.12, 0.20 }
    local blinking = self.db.blinkEnabled ~= false
    local linePulse = blinking and (0.56 + 0.44 * pulse) or 1
    local textPulse = blinking and (0.72 + 0.28 * pulse) or 1
    local shapeReveal = AlertStyle.SmoothStep(reveal)

    alertFrame.art:SetAlpha(1)
    alertFrame.art:SetScale(0.98 + 0.02 * AlertStyle.EaseOutCubic(reveal))

    local panelReveal = 0.20 + 0.80 * AlertStyle.EaseOutCubic(reveal)
    local panelHalfWidth = width * 0.43 * panelReveal
    local panelHeight = height * 0.58
    AlertStyle.SetAnchoredRect(alertFrame.panelLeft, panelHalfWidth, panelHeight, "RIGHT", alertFrame.art, "CENTER", 0, 0)
    AlertStyle.SetAnchoredRect(alertFrame.panelRight, panelHalfWidth, panelHeight, "LEFT", alertFrame.art, "CENTER", 0, 0)
    AlertStyle.SetGradientColor(alertFrame.panelLeft, panelColor, 0, panelColor, 1, shapeReveal * (0.88 + 0.12 * linePulse))
    AlertStyle.SetGradientColor(alertFrame.panelRight, panelColor, 1, panelColor, 0, shapeReveal * (0.88 + 0.12 * linePulse))

    local glowHalfWidth = width * 0.47 * panelReveal
    local glowAlpha = shapeReveal * (blinking and (0.22 + 0.78 * pulse) or 0.58)
    AlertStyle.SetAnchoredRect(alertFrame.glowLeft, glowHalfWidth, height * 0.82, "RIGHT", alertFrame.art, "CENTER", 0, 0)
    AlertStyle.SetAnchoredRect(alertFrame.glowRight, glowHalfWidth, height * 0.82, "LEFT", alertFrame.art, "CENTER", 0, 0)
    AlertStyle.SetGradientColor(alertFrame.glowLeft, glowColor, 0, glowColor, 0.62, glowAlpha)
    AlertStyle.SetGradientColor(alertFrame.glowRight, glowColor, 0.62, glowColor, 0, glowAlpha)

    local topY = height * 0.32
    local bottomY = -height * 0.32
    local railGap = 16
    local railHalfWidth = width * 0.37 * shapeReveal
    AlertStyle.SetAnchoredRect(alertFrame.topLeft, railHalfWidth, 2, "RIGHT", alertFrame.art, "CENTER", -railGap, topY)
    AlertStyle.SetAnchoredRect(alertFrame.topRight, railHalfWidth, 2, "LEFT", alertFrame.art, "CENTER", railGap, topY)
    AlertStyle.SetAnchoredRect(alertFrame.bottomLeft, railHalfWidth * 0.68, 1, "RIGHT", alertFrame.art, "CENTER", -railGap, bottomY)
    AlertStyle.SetAnchoredRect(alertFrame.bottomRight, railHalfWidth * 0.68, 1, "LEFT", alertFrame.art, "CENTER", railGap, bottomY)
    AlertStyle.SetGradientColor(alertFrame.topLeft, glowColor, 0.08, lineColor, 1, shapeReveal * linePulse)
    AlertStyle.SetGradientColor(alertFrame.topRight, lineColor, 1, glowColor, 0.08, shapeReveal * linePulse)
    AlertStyle.SetGradientColor(alertFrame.bottomLeft, glowColor, 0.05, lineColor, 0.58, shapeReveal * linePulse * 0.72)
    AlertStyle.SetGradientColor(alertFrame.bottomRight, lineColor, 0.58, glowColor, 0.05, shapeReveal * linePulse * 0.72)

    local diamondHalf = 9 * shapeReveal
    local diamondEdge = math.sqrt(2) * diamondHalf
    local diamondMid = diamondHalf * 0.5
    AlertStyle.SetCenteredRect(alertFrame.diamondTopLeft, diamondEdge, 2, alertFrame.art, -diamondMid, topY + diamondMid, math.rad(45))
    AlertStyle.SetCenteredRect(alertFrame.diamondTopRight, diamondEdge, 2, alertFrame.art, diamondMid, topY + diamondMid, math.rad(-45))
    AlertStyle.SetCenteredRect(alertFrame.diamondBottomLeft, diamondEdge, 2, alertFrame.art, -diamondMid, topY - diamondMid, math.rad(-45))
    AlertStyle.SetCenteredRect(alertFrame.diamondBottomRight, diamondEdge, 2, alertFrame.art, diamondMid, topY - diamondMid, math.rad(45))
    AlertStyle.SetSolidColor(alertFrame.diamondTopLeft, lineColor, shapeReveal * linePulse)
    AlertStyle.SetSolidColor(alertFrame.diamondTopRight, lineColor, shapeReveal * linePulse)
    AlertStyle.SetSolidColor(alertFrame.diamondBottomLeft, lineColor, shapeReveal * linePulse)
    AlertStyle.SetSolidColor(alertFrame.diamondBottomRight, lineColor, shapeReveal * linePulse)

    local nodeSize = 5 + 2 * linePulse
    AlertStyle.SetCenteredRect(alertFrame.bottomNodeLeft, nodeSize, nodeSize, alertFrame.art, -18, bottomY, math.rad(45))
    AlertStyle.SetCenteredRect(alertFrame.bottomNodeRight, nodeSize, nodeSize, alertFrame.art, 18, bottomY, math.rad(45))
    AlertStyle.SetSolidColor(alertFrame.bottomNodeLeft, lineColor, shapeReveal * linePulse * 0.88)
    AlertStyle.SetSolidColor(alertFrame.bottomNodeRight, lineColor, shapeReveal * linePulse * 0.88)

    local titleReveal = AlertStyle.SmoothStep((reveal - 0.12) / 0.52)
    local percentReveal = AlertStyle.SmoothStep((reveal - 0.22) / 0.48)
    alertFrame.title:ClearAllPoints()
    alertFrame.title:SetPoint("CENTER", alertFrame.art, "CENTER", 0, 10 + (1 - titleReveal) * 4)
    alertFrame.title:SetTextColor(
        AlertStyle.ColorComponent(titleColor, 1, 1),
        AlertStyle.ColorComponent(titleColor, 2, 1),
        AlertStyle.ColorComponent(titleColor, 3, 1),
        AlertStyle.ColorComponent(titleColor, 4, 1) * titleReveal * (0.88 + 0.12 * textPulse)
    )

    local r, g, b = self:GetDurabilityColor(percent)
    alertFrame.percent:ClearAllPoints()
    alertFrame.percent:SetPoint("CENTER", alertFrame.art, "CENTER", 0, -20 + (1 - percentReveal) * 4)
    alertFrame.percent:SetTextColor(r, g, b, percentReveal * textPulse)
    alertFrame.warningMark:ClearAllPoints()
    alertFrame.warningMark:SetPoint("CENTER", alertFrame.art, "CENTER", 0, topY)
    alertFrame.warningMark:SetTextColor(
        AlertStyle.ColorComponent(lineColor, 1, 1),
        AlertStyle.ColorComponent(lineColor, 2, 1),
        AlertStyle.ColorComponent(lineColor, 3, 1),
        AlertStyle.ColorComponent(lineColor, 4, 1) * shapeReveal * linePulse
    )
end

function DurabilityCheck:UpdateAlertVisual(elapsed)
    if not isShowing or not alertFrame or not alertFrame:IsShown() or not currentPercent then return end

    elapsed = SafeNumber(elapsed) or 0
    visualElapsed = visualElapsed + math.max(0, elapsed)
    if revealProgress < 1 then
        revealProgress = math.min(1, revealProgress + elapsed / 0.65)
    end

    local pulse = 1
    if self.db.blinkEnabled ~= false then
        local period = AlertStyle.Clamp(self.db.blinkPeriod, 0.6, 3)
        pulse = 0.5 + 0.5 * math.cos((visualElapsed / period) * math.pi * 2)
    end
    self:RenderAlert(currentPercent, revealProgress, pulse)
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
    if not alertFrame then self:CreateAlertFrame() end
    if not alertFrame or not self:EnsureAlertRegions() then return end

    percent = SafeNumber(percent)
    if not percent then return end
    percent = math.max(0, math.min(100, math.floor(percent + 0.5)))
    local wasShowing = isShowing and alertFrame:IsShown()
    testToken = testToken + 1
    currentPercent = percent
    alertFrame.percent:SetText(percent .. "%")
    if not wasShowing then
        visualElapsed = 0
        revealProgress = 0
    end

    self:ApplySettings()
    alertFrame:Show()
    isShowing = true
    self:RenderAlert(percent, revealProgress, 1)

    -- 반복 내구도 이벤트에서는 같은 경고음을 다시 요청하지 않습니다.
    if self.db.soundEnabled and not isTest and not wasShowing then
        local soundFile = self.db.soundFile
        local customPath = self.db.soundCustomPath
        local channel = self.db.soundChannel or "Master"
        if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            if ns.RequestSound then
                ns:RequestSound({
                    source = "DurabilityCheck",
                    key = "threshold",
                    soundFile = soundFile,
                    customPath = customPath,
                    channel = channel,
                    priority = 20,
                    canQueue = true,
                })
            else
                ns:PlaySound(soundFile, channel, customPath)
            end
        end
    end

    if isTest and not editPreview and not wasShowing then
        local token = testToken
        C_Timer.After(5, function()
            if token == testToken and not editPreview then
                DurabilityCheck:HideAlert()
            end
        end)
    end
end

-- 알림 숨기기
function DurabilityCheck:HideAlert()
    if alertFrame and alertFrame:IsShown() then
        alertFrame:Hide()
    end
    isShowing = false
    currentPercent = nil
    visualElapsed = 0
    revealProgress = 1
    testToken = testToken + 1
end

-- 테스트 알림
function DurabilityCheck:TestAlert()
    self:ShowAlert(math.min(25, tonumber(self.db.threshold) or 25), true)
end

-- 잠금 상태 업데이트
function DurabilityCheck:UpdateLock()
    if alertFrame then
        alertFrame:EnableMouse(not self.db.locked)
    end
end

-- 편집 모드 연동 (Movers)
function DurabilityCheck:EnterEditPreview()
    editPreview = true
    if not alertFrame then self:CreateAlertFrame() end
    self:ShowAlert(math.min(25, tonumber(self.db.threshold) or 25), true)
end

function DurabilityCheck:RefreshEditPreview()
    if not editPreview then return end
    self:ApplySettings()
    if currentPercent then self:RenderAlert(currentPercent, 1, 1) end
end

function DurabilityCheck:ExitEditPreview()
    editPreview = false
    self:HideAlert()
end

function DurabilityCheck:ResetPosition()
    self.db.position = {
        point = DEFAULT_POSITION.point,
        relativePoint = DEFAULT_POSITION.relativePoint,
        x = DEFAULT_POSITION.x,
        y = DEFAULT_POSITION.y,
    }
    self:ApplyPosition()
end

function DurabilityCheck:OnMediaChanged()
    self:ApplySettings()
end

-- 모듈 등록
DDingToolKit:RegisterModule("DurabilityCheck", DurabilityCheck)
