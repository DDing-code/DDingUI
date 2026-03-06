--[[
    DDingToolKit - FocusInterrupt Module
    포커스 대상 시전바 + 차단 준비 표시 (MidnightFocusInterrupt 참고)
    12.0 Secret Value: Blizzard C-level API 패턴 적용
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF" -- [12.0.1]
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: " -- [STYLE]

local FocusInterrupt = {}
FocusInterrupt.name = "FocusInterrupt"
ns.FocusInterrupt = FocusInterrupt

-- 직업별 차단기 스펠 ID
local INTERRUPT_BY_CLASS = {
    DEATHKNIGHT = { DEFAULT = 47528 },    -- 정신 얼리기
    DEMONHUNTER = { DEFAULT = 183752 },   -- 와해
    DRUID       = { BALANCE = 78675, DEFAULT = 106839 }, -- 태양 광선 / 두개골 강타
    EVOKER      = { DEFAULT = 351338 },   -- 진압
    HUNTER      = { DEFAULT = 147362, SURVIVAL = 187707 }, -- 역격 / 끊어치기
    MAGE        = { DEFAULT = 2139 },     -- 카운터스펠
    MONK        = { DEFAULT = 116705 },   -- 관수장
    PALADIN     = { DEFAULT = 96231 },    -- 꾸짖기
    PRIEST      = { DEFAULT = 15487 },    -- 침묵
    ROGUE       = { DEFAULT = 1766 },     -- 발차기
    SHAMAN      = { DEFAULT = 57994 },    -- 바람 가르기
    WARLOCK     = { DEFAULT = 19647, DEMONOLOGY = 119914, DEMONOLOGY_SUB = 132409, GRIMOIRE = 1276467 },
    WARRIOR     = { DEFAULT = 6552 },     -- 손가락 걸기
}

-- 로컬 변수
local barFrame = nil
local kickIcon = nil
local eventFrame = nil
local isEnabled = false
local isTestMode = false
local isActive = false
local interruptID = nil
local subInterruptID = nil
local fadeTimer = nil

-- 12.0 Secret Value 대응: ColorMixin 객체 (C_CurveUtil.EvaluateColorFromBoolean용)
local interruptibleColorObj
local notInterruptibleColorObj
local cooldownColorObj
local interruptedColorObj

local function CreateColorObjects(db)
    interruptibleColorObj = CreateColor(db.interruptibleColor[1], db.interruptibleColor[2], db.interruptibleColor[3], 1)
    notInterruptibleColorObj = CreateColor(db.notInterruptibleColor[1], db.notInterruptibleColor[2], db.notInterruptibleColor[3], 1)
    cooldownColorObj = CreateColor(db.cooldownColor[1], db.cooldownColor[2], db.cooldownColor[3], 1)
    interruptedColorObj = CreateColor(db.interruptedColor[1], db.interruptedColor[2], db.interruptedColor[3], 1)
end

-- 직업/전문화에 따른 차단기 ID 가져오기
local function GetInterruptSpellID()
    local _, class = UnitClass("player")
    if not class or not INTERRUPT_BY_CLASS[class] then return nil, nil end

    local classData = INTERRUPT_BY_CLASS[class]
    local mainID = classData.DEFAULT
    local subID = nil

    if class == "WARLOCK" then
        local spec = GetSpecialization()
        if spec == 2 then  -- 악마학
            mainID = classData.DEMONOLOGY
            subID = classData.DEMONOLOGY_SUB
        end
    elseif class == "HUNTER" then
        local spec = GetSpecialization()
        if spec == 3 then  -- 생존
            mainID = classData.SURVIVAL
        end
    elseif class == "DRUID" then
        local spec = GetSpecialization()
        if spec == 1 then  -- 조화
            mainID = classData.BALANCE
        end
    end

    return mainID, subID
end

-- 초기화
function FocusInterrupt:OnInitialize()
    self.db = ns.db.profile.FocusInterrupt
end

-- 활성화
function FocusInterrupt:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.FocusInterrupt then
            self.db = ns.db.profile.FocusInterrupt
        else
            return
        end
    end

    if not self.db.enabled then
        isEnabled = false
        return
    end

    isEnabled = true
    interruptID, subInterruptID = GetInterruptSpellID()
    CreateColorObjects(self.db)
    self:CreateBarFrame()
    self:RegisterEvents()
end

-- 비활성화
function FocusInterrupt:OnDisable()
    isEnabled = false
    isActive = false
    if barFrame then barFrame:Hide() end
    if eventFrame then eventFrame:UnregisterAllEvents() end
    if fadeTimer then fadeTimer:Cancel(); fadeTimer = nil end
end

-- 시전바 프레임 생성
function FocusInterrupt:CreateBarFrame()
    if barFrame then return end

    local db = self.db
    local frame = CreateFrame("Frame", "DDingToolKit_FocusInterruptFrame", UIParent)
    frame:SetSize(db.barWidth or 280, db.barHeight or 30)
    frame:SetPoint("CENTER", UIParent, "CENTER", (db.position and db.position.x or 0), (db.position and db.position.y or 250))
    frame:SetFrameStrata("HIGH")
    frame:SetScale(db.scale or 1.0)
    frame:Hide()

    -- 배경
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetColorTexture(0, 0, 0, db.bgAlpha or 0.3)

    -- 테두리
    frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.border:SetAllPoints()
    frame.border:SetBackdrop({ edgeFile = SL_FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }) -- [12.0.1]
    frame.border:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.border:SetBackdropBorderColor(0, 0, 0, 1)

    -- 아이콘
    local height = db.barHeight or 30
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.icon:SetSize(height, height)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- 상태바
    frame.statusBar = CreateFrame("StatusBar", nil, frame)
    frame.statusBar:SetMinMaxValues(0, 1)
    frame.statusBar:SetValue(0)
    frame.statusBar:SetPoint("RIGHT", frame, "RIGHT")
    frame.statusBar:SetSize((db.barWidth or 280) - height, height)
    frame.statusBar:SetStatusBarTexture(db.texture or "Interface\\TargetingFrame\\UI-StatusBar")

    -- 텍스트 프레임
    frame.textFrame = CreateFrame("Frame", nil, frame)
    frame.textFrame:SetAllPoints()
    frame.textFrame:SetFrameLevel(frame:GetFrameLevel() + 10)

    -- 스펠명 텍스트
    local font = db.font or SL_FONT -- [12.0.1]
    local fontSize = db.fontSize or 12
    frame.spellText = frame.textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.spellText:SetFont(font, fontSize, "OUTLINE")
    frame.spellText:SetPoint("LEFT", frame, "LEFT", height + 4, 0)
    frame.spellText:SetJustifyH("LEFT")

    -- 시간 텍스트
    frame.timeText = frame.textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.timeText:SetFont(font, fontSize, "OUTLINE")
    frame.timeText:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    frame.timeText:SetJustifyH("RIGHT")

    -- 드래그 (테스트 모드에서만)
    frame:SetMovable(true)
    frame:EnableMouse(false)

    barFrame = frame

    -- 차단기 아이콘 생성
    self:CreateKickIcon()
end

-- 차단기 아이콘 생성
function FocusInterrupt:CreateKickIcon()
    if kickIcon then return end
    if not interruptID then return end
    if not self.db.showKickIcon then return end

    local db = self.db
    local size = db.kickIconSize or 30

    kickIcon = CreateFrame("Frame", nil, barFrame, "BackdropTemplate")
    kickIcon:SetSize(size, size)
    kickIcon:SetPoint("BOTTOMLEFT", barFrame, "TOPLEFT", 0, 2)

    kickIcon.border = CreateFrame("Frame", nil, kickIcon, "BackdropTemplate")
    kickIcon.border:SetAllPoints()
    kickIcon.border:SetBackdrop({ edgeFile = SL_FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }) -- [12.0.1]
    kickIcon.border:SetBackdropBorderColor(0, 0, 0, 1)

    kickIcon.icon = kickIcon:CreateTexture(nil, "ARTWORK")
    kickIcon.icon:SetAllPoints()
    kickIcon.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- 아이콘 텍스처 설정
    local spellInfo = C_Spell.GetSpellInfo(interruptID)
    if spellInfo then
        kickIcon.icon:SetTexture(spellInfo.iconID)
    else
        kickIcon.icon:SetTexture(134400)
    end

    kickIcon:Hide()
end

-- 바 색상 설정 (C_CurveUtil.EvaluateColorFromBoolean: secret boolean을 C레벨에서 처리)
local function SetBarColor(interrupted, notInterruptible, isReady)
    if not barFrame then return end

    local color = C_CurveUtil.EvaluateColorFromBoolean(interrupted, interruptedColorObj, interruptibleColorObj)
    color = C_CurveUtil.EvaluateColorFromBoolean(isReady, color, cooldownColorObj)
    color = C_CurveUtil.EvaluateColorFromBoolean(notInterruptible, notInterruptibleColorObj, color)

    barFrame.statusBar:GetStatusBarTexture():SetVertexColor(color:GetRGBA())
end

-- 시전 처리
local function HandleCast()
    if not isEnabled or not barFrame then return end

    local db = FocusInterrupt.db

    -- 채널링 먼저 체크 (notInterruptible은 secret boolean → C API에만 전달)
    local name, _, texture, _, _, _, notInterruptible, _ = UnitChannelInfo("focus")
    local isChannel = false
    if name then
        isChannel = true
    else
        name, _, texture, _, _, _, _, notInterruptible, _ = UnitCastingInfo("focus")
    end

    if not name then
        isActive = false
        barFrame:Hide()
        return
    end

    isActive = true

    -- 아이콘
    barFrame.icon:SetTexture(texture or 134400)

    -- 스펠명 + 타겟 (MidnightFocusInterrupt: target은 secret 아님)
    if db.showTarget then
        local target = UnitSpellTargetName and UnitSpellTargetName("focus") or nil
        if target then
            barFrame.spellText:SetText(string.format("%.16s", name) .. " - " .. target)
        else
            barFrame.spellText:SetText(name)
        end
    else
        barFrame.spellText:SetText(name)
    end

    -- 지속시간
    local duration
    if isChannel then
        duration = UnitChannelDuration("focus")
    else
        duration = UnitCastingDuration("focus")
    end

    if duration then
        barFrame.statusBar:SetMinMaxValues(0, duration:GetTotalDuration())
    end

    -- OnUpdate에서 바 갱신 -- [PERF] elapsed throttle 추가
    local fiElapsed = 0
    local fiLastReady = nil  -- 쿨다운 상태 캐시
    barFrame:SetScript("OnUpdate", function(self, elapsed)
        if not isActive or not duration then return end

        -- [PERF] 바 진행률은 매 프레임, 나머지는 0.05초마다
        local remaining
        if isChannel then
            remaining = duration:GetRemainingDuration()
        else
            remaining = duration:GetElapsedDuration()
        end
        barFrame.statusBar:SetValue(remaining)

        fiElapsed = fiElapsed + elapsed
        if fiElapsed < 0.05 then return end  -- [PERF] 50ms throttle (나머지 로직)
        fiElapsed = 0

        -- 시간 텍스트
        if db.showTime then
            barFrame.timeText:SetText(string.format("%.1f", duration:GetRemainingDuration()))
        end

        -- 차단 준비 여부
        local isReady = false
        if interruptID then
            if C_Spell.GetSpellCooldownDuration then
                local cd = C_Spell.GetSpellCooldownDuration(interruptID)
                if cd then
                    isReady = cd:IsZero()
                end
            elseif C_Spell.GetSpellCooldown then
                local info = C_Spell.GetSpellCooldown(interruptID)
                if info then
                    isReady = (info.duration == 0)
                end
            end
        end

        -- [PERF] 색상/아이콘은 상태 변경 시에만
        SetBarColor(false, notInterruptible, isReady)

        if kickIcon and db.showKickIcon then
            kickIcon:SetAlphaFromBoolean(isReady)
            kickIcon:SetAlphaFromBoolean(notInterruptible, 0, kickIcon:GetAlpha())
            kickIcon:Show()
        end

        barFrame:SetAlpha(1)
        if db.cooldownHide then
            barFrame:SetAlphaFromBoolean(isReady)
        end
        if db.notInterruptibleHide then
            barFrame:SetAlphaFromBoolean(notInterruptible, 0, barFrame:GetAlpha())
        end
    end)

    -- 사운드 -- [12.0.1] ns:PlaySound 통합
    if not db.mute then
        local soundFile = db.soundFile
        local customPath = db.soundCustomPath
        if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, "Master", customPath)
        else
            PlaySound(SOUNDKIT.RAID_WARNING, "Master")
        end
    end

    barFrame:Show()
end

-- 차단됨 처리 (MidnightFocusInterrupt: UNIT_SPELLCAST_INTERRUPTED의 guid 인자 사용)
local function HandleInterrupted(guid)
    if not barFrame then return end
    local db = FocusInterrupt.db

    if guid and db.showInterrupter then
        local name = UnitNameFromGUID(guid)
        if name then
            barFrame.spellText:SetText(L["FOCUSINTERRUPT_INTERRUPTED"] .. ": " .. name)
        else
            barFrame.spellText:SetText(L["FOCUSINTERRUPT_INTERRUPTED"])
        end
    else
        barFrame.spellText:SetText(L["FOCUSINTERRUPT_INTERRUPTED"])
    end

    SetBarColor(true, false, true)
    isActive = false

    if fadeTimer then fadeTimer:Cancel() end
    fadeTimer = C_Timer.NewTimer(db.interruptedFadeTime or 0.75, function()
        fadeTimer = nil
        if barFrame then barFrame:Hide() end
    end)
end

-- 이벤트 등록
function FocusInterrupt:RegisterEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end

    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "focus")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "focus")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "focus")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "focus")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "focus")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "focus")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if not isEnabled then return end

        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "PLAYER_FOCUS_CHANGED" then
            if fadeTimer then fadeTimer:Cancel(); fadeTimer = nil end
            isActive = true
            HandleCast()

        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
            if not fadeTimer then
                isActive = false
                if barFrame then barFrame:Hide() end
            end

        elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            -- MidnightFocusInterrupt 패턴: 4번째 인자가 차단자 GUID
            local _, _, _, guid = ...
            if guid then
                HandleInterrupted(guid)
            else
                if not fadeTimer then
                    isActive = false
                    if barFrame then barFrame:Hide() end
                end
            end

        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            interruptID, subInterruptID = GetInterruptSpellID()
            if kickIcon and interruptID then
                local spellInfo = C_Spell.GetSpellInfo(interruptID)
                if spellInfo then
                    kickIcon.icon:SetTexture(spellInfo.iconID)
                end
            end
        end
    end)
end

-- 스타일 업데이트
function FocusInterrupt:UpdateStyle()
    if not barFrame then return end
    local db = self.db
    local height = db.barHeight or 30

    barFrame:SetSize(db.barWidth or 280, height)
    barFrame:ClearAllPoints()
    barFrame:SetPoint("CENTER", UIParent, "CENTER", (db.position and db.position.x or 0), (db.position and db.position.y or 250))
    barFrame:SetScale(db.scale or 1.0)

    barFrame.background:SetColorTexture(0, 0, 0, db.bgAlpha or 0.3)
    barFrame.icon:SetSize(height, height)

    barFrame.statusBar:SetSize((db.barWidth or 280) - height, height)
    barFrame.statusBar:SetStatusBarTexture(db.texture or "Interface\\TargetingFrame\\UI-StatusBar")

    local font = db.font or SL_FONT -- [12.0.1]
    local fontSize = db.fontSize or 12
    barFrame.spellText:SetFont(font, fontSize, "OUTLINE")
    barFrame.spellText:SetPoint("LEFT", barFrame, "LEFT", height + 4, 0)
    barFrame.timeText:SetFont(font, fontSize, "OUTLINE")

    if kickIcon then
        kickIcon:SetSize(db.kickIconSize or 30, db.kickIconSize or 30)
    end

    -- 색상 객체 갱신
    CreateColorObjects(db)
end

-- 테스트 모드
function FocusInterrupt:TestMode()
    if not barFrame then
        self:CreateBarFrame()
    end

    isTestMode = not isTestMode

    if isTestMode then
        barFrame:EnableMouse(true)
        barFrame:RegisterForDrag("LeftButton")
        barFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        barFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relativePoint, x, y = self:GetPoint()
            if not FocusInterrupt.db.position then
                FocusInterrupt.db.position = {}
            end
            FocusInterrupt.db.position.point = point
            FocusInterrupt.db.position.relativePoint = relativePoint
            FocusInterrupt.db.position.x = x
            FocusInterrupt.db.position.y = y
        end)

        barFrame.icon:SetTexture(134400)
        barFrame.spellText:SetText("Test Spell - Target")
        barFrame.statusBar:SetMinMaxValues(0, 1)
        barFrame.statusBar:SetValue(0.5)
        SetBarColor(false, false, true)

        if kickIcon and self.db.showKickIcon then
            kickIcon:SetAlpha(1)
            kickIcon:Show()
        end

        barFrame:SetScript("OnUpdate", nil)
        barFrame:SetAlpha(1)
        barFrame:Show()

        print(CHAT_PREFIX .. "FocusInterrupt " .. L["TEST_MODE"] .. " ON") -- [STYLE]
    else
        barFrame:EnableMouse(false)
        barFrame:SetScript("OnDragStart", nil)
        barFrame:SetScript("OnDragStop", nil)
        barFrame:Hide()
        if kickIcon then kickIcon:Hide() end
        print(CHAT_PREFIX .. "FocusInterrupt " .. L["TEST_MODE"] .. " OFF") -- [STYLE]
    end
end

function FocusInterrupt:IsTestMode()
    return isTestMode
end

-- 위치 초기화
function FocusInterrupt:ResetPosition()
    if barFrame then
        barFrame:ClearAllPoints()
        barFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
        self.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 250 }
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("FocusInterrupt", FocusInterrupt)
