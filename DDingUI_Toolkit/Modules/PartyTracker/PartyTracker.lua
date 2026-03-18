--[[
    DDingToolKit - PartyTracker Module
    파티/레이드: 전투 부활, 힐러 마나
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF" -- [12.0.1]
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

-- PartyTracker 모듈
local PartyTracker = {}
ns.PartyTracker = PartyTracker

-- 전투 부활 스펠 ID 목록
local BATTLE_RES_SPELLS = {
    20484,   -- 환생 (드루이드)
    61999,   -- 동맹 일으키기 (죽기)
    20707,   -- 영혼석 (흑마)
    391054,  -- 변환 회귀 (기원사)
}

-- 힐러 직업 아이콘 (FileDataID)
local HEALER_CLASS_ICONS = {
    ["DRUID"] = 625999,
    ["PALADIN"] = 626003,
    ["PRIEST"] = 626004,
    ["SHAMAN"] = 626006,
    ["MONK"] = 608952,
    ["EVOKER"] = 4511812,
}

-- 직업 색상
local CLASS_COLORS = {
    ["DRUID"] = {1, 0.49, 0.04},
    ["PALADIN"] = {0.96, 0.55, 0.73},
    ["PRIEST"] = {1, 1, 1},
    ["SHAMAN"] = {0, 0.44, 0.87},
    ["MONK"] = {0, 1, 0.6},
    ["EVOKER"] = {0.2, 0.58, 0.5},
}

-- 로컬 변수
local mainFrame = nil
local manaFrame = nil  -- 분리된 힐러 마나 프레임
local battleResFrame = nil
local lustFrame = nil
local healerFrames = {}
local separateHealerFrames = {}  -- 분리 모드용 힐러 프레임
local updateTicker = nil
local isEnabled = false
local isTestMode = false

-- 블러드 디버프 스펠 ID (만족함, 소진, 시간의 균열, 피로, 지침)
local LUST_DEBUFFS = {
    [57724] = true, -- 만족함 (피의 욕망)
    [57723] = true, -- 소진 (영웅심)
    [80354] = true, -- 시간의 균열 (시간 왜곡)
    [264689] = true, -- 피로 (원시적인 분노)
    [390435] = true, -- 지침 (위상의 열기)
}

-- 초기화
function PartyTracker:OnInitialize()
    self.db = ns.db.profile.PartyTracker
end

-- 활성화
function PartyTracker:OnEnable()
    -- db가 없으면 초기화
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.PartyTracker then
            self.db = ns.db.profile.PartyTracker
        else
            -- 기본값 사용 (모두 비활성화)
            self.db = {
                enabled = false,
                showInParty = false,
                showInRaid = false,
                showLust = true,
                showManaBar = false,
                showManaText = false,
                locked = false,
                iconSize = 33,
                scale = 1.0,
                font = SL_FONT, -- [12.0.1]
                fontSize = 14,
                position = {
                    point = "CENTER",
                    relativePoint = "CENTER",
                    x = -500,
                    y = -110,
                },
            }
        end
    end

    -- enabled 체크
    if not self.db.enabled then
        isEnabled = false
        return
    end

    isEnabled = true
    self:CreateMainFrame()
    self:UpdateVisibility()
    self:StartUpdate()
end

-- 비활성화
function PartyTracker:OnDisable()
    isEnabled = false
    if mainFrame then
        mainFrame:Hide()
    end
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

-- 메인 프레임 생성
function PartyTracker:CreateMainFrame()
    if mainFrame then return end

    -- db 확인
    if not self.db then
        self.db = {
            enabled = false,
            showInParty = false,
            showInRaid = false,
            showLust = true,
            showManaBar = false,
            showManaText = false,
            locked = false,
            iconSize = 33,
            scale = 1.0,
            font = SL_FONT, -- [12.0.1]
            fontSize = 14,
            position = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = -500,
                y = -110,
            },
        }
    end

    local pos = self.db.position or {}
    local frame = CreateFrame("Frame", "DDingToolKit_PartyTrackerFrame", UIParent)
    frame:SetSize(150, 350)  -- 컴팩트 사이즈
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or -500, pos.y or -110)
    frame:SetFrameStrata("HIGH")

    -- 드래그 가능
    frame:SetMovable(true)
    frame:EnableMouse(not self.db.locked)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not PartyTracker.db.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        PartyTracker.db.position.point = point
        PartyTracker.db.position.relativePoint = relativePoint
        PartyTracker.db.position.x = x
        PartyTracker.db.position.y = y
    end)

    mainFrame = frame

    -- 크기 적용
    if self.db.scale then
        mainFrame:SetScale(self.db.scale)
    end

    -- 개별 트래커 프레임 생성
    self:CreateBattleResFrame()
    self:CreateLustFrame()
    self:CreateHealerFrames()
end

-- 아이콘 프레임 템플릿 생성 (위크오라 스타일 - 컴팩트)
function PartyTracker:CreateIconFrame(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size + 80, size)  -- 텍스트 공간 포함

    -- 폰트 설정
    local font = self.db.font or SL_FONT -- [12.0.1]
    local fontSize = self.db.fontSize or 14

    -- 아이콘 컨테이너
    frame.iconFrame = CreateFrame("Frame", nil, frame)
    frame.iconFrame:SetSize(size, size)
    frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)

    -- 배경 (검정)
    frame.bg = frame.iconFrame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 1)

    -- 아이콘
    frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 1, -1)
    frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- 쿨다운 오버레이
    frame.cooldown = CreateFrame("Cooldown", nil, frame.iconFrame, "CooldownFrameTemplate")
    frame.cooldown:SetPoint("TOPLEFT", 1, -1)
    frame.cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(true)

    -- 텍스트 오버레이 (쿨다운 스와이프 위에 표시)
    frame.textOverlay = CreateFrame("Frame", nil, frame.iconFrame)
    frame.textOverlay:SetAllPoints()
    frame.textOverlay:SetFrameLevel(frame.cooldown:GetFrameLevel() + 2)

    -- 아이콘 위 충전 수 텍스트 (전투부활용)
    frame.chargeText = frame.textOverlay:CreateFontString(nil, "OVERLAY")
    frame.chargeText:SetFont(font, fontSize + 4, "OUTLINE")
    frame.chargeText:SetPoint("CENTER", frame.iconFrame, "CENTER", 0, 0)
    frame.chargeText:SetTextColor(1, 1, 1, 1)

    -- 마나바 (힐러용 - StatusBar는 secret value 직접 수용)
    local manaBarWidth = self.db.manaBarWidth or 60
    local manaBarHeight = self.db.manaBarHeight or 10
    local manaBarOffsetX = self.db.manaBarOffsetX or 4
    local manaBarOffsetY = self.db.manaBarOffsetY or 6
    local manaBarTexture = self.db.manaBarTexture or "Interface\\TargetingFrame\\UI-StatusBar"

    -- 마나바 테두리 (배경 프레임)
    frame.manaBarBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.manaBarBorder:SetSize(manaBarWidth + 2, manaBarHeight + 2)
    frame.manaBarBorder:SetPoint("LEFT", frame.iconFrame, "RIGHT", manaBarOffsetX - 1, manaBarOffsetY)
    frame.manaBarBorder:SetBackdrop({
        bgFile = SL_FLAT, -- [12.0.1]
        edgeFile = SL_FLAT, -- [12.0.1]
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame.manaBarBorder:SetBackdropColor(0, 0, 0, 0.8)
    frame.manaBarBorder:SetBackdropBorderColor(0, 0, 0, 1)
    frame.manaBarBorder:Hide()

    -- 마나바
    frame.manaBar = CreateFrame("StatusBar", nil, frame.manaBarBorder)
    frame.manaBar:SetSize(manaBarWidth, manaBarHeight)
    frame.manaBar:SetPoint("CENTER", frame.manaBarBorder, "CENTER", 0, 0)
    frame.manaBar:SetStatusBarTexture(manaBarTexture)
    frame.manaBar:SetStatusBarColor(0, 0.5, 1, 1)  -- 파란색 (마나)
    frame.manaBar:SetMinMaxValues(0, 100)
    frame.manaBar:SetValue(0)

    -- 마나바 위 텍스트
    frame.manaText = frame.manaBar:CreateFontString(nil, "OVERLAY")
    frame.manaText:SetFont(font, fontSize - 2, "OUTLINE")
    frame.manaText:SetPoint("CENTER", frame.manaBar, "CENTER", 0, 0)
    frame.manaText:SetTextColor(1, 1, 1, 1)

    -- 우측 메인 텍스트 (큰 글씨 - 수치/상태)
    frame.mainText = frame:CreateFontString(nil, "OVERLAY")
    frame.mainText:SetFont(font, fontSize, "OUTLINE")
    frame.mainText:SetPoint("LEFT", frame.iconFrame, "RIGHT", 4, -6)
    frame.mainText:SetTextColor(1, 1, 1, 1)

    -- 우측 서브 텍스트 (작은 글씨 - 이름/추가정보)
    frame.subText = frame:CreateFontString(nil, "OVERLAY")
    frame.subText:SetFont(font, fontSize - 2, "OUTLINE")
    frame.subText:SetPoint("LEFT", frame.mainText, "RIGHT", 4, 0)
    frame.subText:SetTextColor(0.7, 0.7, 0.7, 1)

    return frame
end

-- 폰트 업데이트
function PartyTracker:UpdateFonts()
    local font = self.db.font or SL_FONT -- [12.0.1]
    local fontSize = self.db.fontSize or 14

    local function updateFrame(frame)
        if not frame then return end
        frame.chargeText:SetFont(font, fontSize + 4, "OUTLINE")
        frame.mainText:SetFont(font, fontSize, "OUTLINE")
        frame.subText:SetFont(font, fontSize - 2, "OUTLINE")
        if frame.manaText then
            frame.manaText:SetFont(font, fontSize - 2, "OUTLINE")
        end
    end

    updateFrame(battleResFrame)
    updateFrame(lustFrame)

    for _, frame in ipairs(healerFrames) do
        updateFrame(frame)
    end
end

-- 마나바 크기 업데이트
function PartyTracker:UpdateManaBarSize()
    local width = self.db.manaBarWidth or 60
    local height = self.db.manaBarHeight or 10

    for _, frame in ipairs(healerFrames) do
        if frame.manaBar then
            frame.manaBar:SetSize(width, height)
        end
        if frame.manaBarBorder then
            frame.manaBarBorder:SetSize(width + 2, height + 2)
        end
    end
end

-- 마나바 위치 업데이트
function PartyTracker:UpdateManaBarPosition()
    local offsetX = self.db.manaBarOffsetX or 4
    local offsetY = self.db.manaBarOffsetY or 6

    for _, frame in ipairs(healerFrames) do
        if frame.manaBarBorder and frame.iconFrame then
            frame.manaBarBorder:ClearAllPoints()
            frame.manaBarBorder:SetPoint("LEFT", frame.iconFrame, "RIGHT", offsetX - 1, offsetY)
        end
    end
end

-- 마나바 텍스쳐 업데이트
function PartyTracker:UpdateManaBarTexture()
    local texture = self.db.manaBarTexture or "Interface\\TargetingFrame\\UI-StatusBar"

    for _, frame in ipairs(healerFrames) do
        if frame.manaBar then
            frame.manaBar:SetStatusBarTexture(texture)
        end
    end
end

-- 전투 부활 프레임 생성
function PartyTracker:CreateBattleResFrame()
    if battleResFrame then return end
    local frame = self:CreateIconFrame(mainFrame, self.db.iconSize or 33)
    frame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
    frame.icon:SetTexture(136080)  -- 환생 아이콘
    frame:Show()

    battleResFrame = frame
end

-- 블러드 프레임 생성
function PartyTracker:CreateLustFrame()
    if lustFrame then return end
    local frame = self:CreateIconFrame(mainFrame, self.db.iconSize or 33)
    frame.icon:SetTexture(136012)  -- 블러드 아이콘 (실제 피의 욕망 아이콘)
    frame:Show()

    lustFrame = frame
end

-- 힐러 마나 프레임 생성 (최대 6명)
function PartyTracker:CreateHealerFrames()
    if #healerFrames > 0 then return end
    for i = 1, 6 do
        local frame = self:CreateIconFrame(mainFrame, self.db.iconSize or 33)
        if i > 1 then
            frame:SetPoint("TOPLEFT", healerFrames[i-1], "BOTTOMLEFT", 0, -5)
        end
        frame:Hide()
        healerFrames[i] = frame
    end
end

-- 분리된 힐러 마나 프레임 생성
function PartyTracker:CreateSeparateManaFrame()
    if manaFrame then return end

    local pos = self.db.manaPosition or {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -150,
    }

    local frame = CreateFrame("Frame", "DDingToolKit_PartyTrackerManaFrame", UIParent)
    frame:SetSize(150, 250)
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -150)
    frame:SetFrameStrata("HIGH")

    -- 드래그 가능
    frame:SetMovable(true)
    frame:EnableMouse(not self.db.manaLocked)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not PartyTracker.db.manaLocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        PartyTracker.db.manaPosition = PartyTracker.db.manaPosition or {}
        PartyTracker.db.manaPosition.point = point
        PartyTracker.db.manaPosition.relativePoint = relativePoint
        PartyTracker.db.manaPosition.x = x
        PartyTracker.db.manaPosition.y = y
    end)

    -- 크기 적용
    if self.db.manaScale then
        frame:SetScale(self.db.manaScale)
    end

    manaFrame = frame

    -- 분리용 힐러 프레임 생성 (최대 6명)
    for i = 1, 6 do
        local healerFrame = self:CreateIconFrame(manaFrame, self.db.iconSize or 33)
        if i == 1 then
            healerFrame:SetPoint("TOPLEFT", manaFrame, "TOPLEFT", 0, 0)
        else
            healerFrame:SetPoint("TOPLEFT", separateHealerFrames[i-1], "BOTTOMLEFT", 0, -5)
        end
        healerFrame:Hide()
        separateHealerFrames[i] = healerFrame
    end

    frame:Hide()
end

-- 분리 마나 프레임 위치 초기화
function PartyTracker:ResetManaPosition()
    self.db.manaPosition = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -150,
    }
    if manaFrame then
        manaFrame:ClearAllPoints()
        manaFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

-- 분리 마나 프레임 반환
function PartyTracker:GetManaFrame()
    return manaFrame
end

-- 분리 모드 토글
function PartyTracker:ToggleSeparateManaFrame(enable)
    self.db.separateManaFrame = enable

    if enable then
        -- 분리 프레임 생성
        if not manaFrame then
            self:CreateSeparateManaFrame()
        end
        -- 메인 프레임의 힐러 숨기기
        for _, frame in ipairs(healerFrames) do
            frame:Hide()
        end
    else
        -- 분리 프레임 숨기기
        if manaFrame then
            manaFrame:Hide()
        end
        for _, frame in ipairs(separateHealerFrames) do
            frame:Hide()
        end
    end

    self:UpdateVisibility()
end

-- 가시성 업데이트
function PartyTracker:UpdateVisibility()
    if not mainFrame then return end

    -- 테스트 모드 중이면 건드리지 않음
    if isTestMode then
        return
    end

    local inGroup = IsInGroup()
    local inRaid = IsInRaid()

    -- 설정 체크
    local showInParty = self.db.showInParty ~= false
    local showInRaid = self.db.showInRaid ~= false
    local separateMode = self.db.separateManaFrame

    -- 그룹이 아니거나 설정에서 비활성화된 경우
    if not inGroup then
        mainFrame:Hide()
        if manaFrame then manaFrame:Hide() end
        return
    end

    if inRaid and not showInRaid then
        mainFrame:Hide()
        if manaFrame then manaFrame:Hide() end
        return
    end

    if not inRaid and not showInParty then
        mainFrame:Hide()
        if manaFrame then manaFrame:Hide() end
        return
    end

    mainFrame:Show()

    -- 분리 모드 처리
    if separateMode then
        -- 분리 프레임 생성 (없으면)
        if not manaFrame then
            self:CreateSeparateManaFrame()
        end
        manaFrame:Show()

        -- 메인 프레임의 힐러 숨기기
        for _, frame in ipairs(healerFrames) do
            frame:Hide()
        end
    else
        -- 분리 프레임 숨기기
        if manaFrame then
            manaFrame:Hide()
        end
        for _, frame in ipairs(separateHealerFrames) do
            frame:Hide()
        end
    end

    -- 전투부활
    battleResFrame:Show()
    local lastActiveFrame = battleResFrame

    -- 블러드 (표시 여부 확인)
    if self.db.showLust ~= false and lustFrame then
        lustFrame:Show()
        lustFrame:SetPoint("TOPLEFT", lastActiveFrame, "BOTTOMLEFT", 0, -5)
        lastActiveFrame = lustFrame
    else
        if lustFrame then lustFrame:Hide() end
    end

    -- 힐러 (분리 모드가 아닐 때 1번 앵커 갱신)
    if not separateMode and #healerFrames > 0 then
        healerFrames[1]:SetPoint("TOPLEFT", lastActiveFrame, "BOTTOMLEFT", 0, -5)
    end
end

-- 업데이트 시작
function PartyTracker:StartUpdate()
    if updateTicker then
        updateTicker:Cancel()
    end

    -- [PERF] 0.1→0.5초 틱 (힐러 마나 변화는 느린 정보, 0.5초 충분)
    updateTicker = C_Timer.NewTicker(0.5, function()
        if isEnabled then
            PartyTracker:Update()
        end
    end)
end

-- 전체 업데이트
function PartyTracker:Update()
    if not mainFrame then return end
    if not mainFrame:IsShown() then return end
    if isTestMode then return end

    -- 전투 부활은 파티/레이드 모두 표시
    if battleResFrame and battleResFrame:IsShown() then
        self:UpdateBattleRes()
    end

    if lustFrame and lustFrame:IsShown() then
        self:UpdateLust()
    end

    -- 힐러 마나
    self:UpdateHealerMana()
end

-- 전투 부활 업데이트 (MRT 방식 - 공유 풀 직접 조회)
function PartyTracker:UpdateBattleRes()
    if not battleResFrame then return end

    -- GetSpellCharges 호환성 처리
    local GetSpellChargesCompat = C_Spell and C_Spell.GetSpellCharges or GetSpellCharges

    -- 전투부활 공유 풀 조회 (20484 = 드루이드 환생, 모든 직업에서 공유 풀 조회 가능)
    local chargeInfo = GetSpellChargesCompat(20484)

    -- chargeInfo가 테이블이 아니면 구버전 API 반환값 처리
    local charges, maxCharges, start, duration
    if type(chargeInfo) == "table" then
        charges = chargeInfo.currentCharges
        maxCharges = chargeInfo.maxCharges
        start = chargeInfo.cooldownStartTime
        duration = chargeInfo.cooldownDuration
    else
        -- 구버전 API: charges, maxCharges, start, duration 직접 반환
        charges, maxCharges, start, duration = GetSpellChargesCompat(20484)
    end

    -- 전투부활 정보가 없으면 (인스턴스 밖 등)
    if not charges or (charges == 0 and maxCharges == 0) then
        battleResFrame.chargeText:SetText("-")
        battleResFrame.chargeText:SetTextColor(0.5, 0.5, 0.5, 1)
        battleResFrame.mainText:SetText("")
        battleResFrame.icon:SetDesaturated(true)
        battleResFrame.cooldown:SetCooldown(0, 0)
        return
    end

    charges = charges or 0
    maxCharges = maxCharges or 1
    start = start or 0
    duration = duration or 0

    -- 아이콘 위에 충전 수 표시
    battleResFrame.chargeText:SetText(tostring(charges))

    if charges > 0 then
        battleResFrame.chargeText:SetTextColor(0, 1, 0, 1)  -- 녹색
        battleResFrame.icon:SetDesaturated(false)
    else
        battleResFrame.chargeText:SetTextColor(1, 0, 0, 1)  -- 빨강
        battleResFrame.icon:SetDesaturated(true)
    end

    -- 우측에 쿨다운 표시
    if charges < maxCharges and start > 0 and duration > 0 then
        local remaining = (start + duration) - GetTime()
        if remaining > 0 then
            battleResFrame.cooldown:SetCooldown(start, duration)
            local minutes = math.floor(remaining / 60)
            local seconds = math.floor(remaining % 60)
            battleResFrame.mainText:SetText(string.format("%d:%02d", minutes, seconds))
            battleResFrame.mainText:SetTextColor(1, 1, 1, 1)
        else
            battleResFrame.mainText:SetText("")
            battleResFrame.cooldown:SetCooldown(0, 0)
        end
    else
        battleResFrame.mainText:SetText("")
        battleResFrame.cooldown:SetCooldown(0, 0)
    end
end

-- 블러드 디버프 업데이트
function PartyTracker:UpdateLust()
    if not lustFrame or not lustFrame:IsShown() then return end

    local maxExpiration = 0
    local duration = 0
    local hasDebuff = false

    -- pcall로 감싸서 시크릿밸류 오라를 안전하게 스킵
    for i = 1, 40 do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
        if not ok or not auraData then break end
        -- 필드 접근 자체가 시크릿일 수 있으므로 전체를 pcall로 감쌈
        pcall(function()
            local spellId = auraData.spellId
            if spellId and type(spellId) == "number" and LUST_DEBUFFS[spellId] then
                hasDebuff = true
                local expirationTime = auraData.expirationTime
                local dur = auraData.duration
                if expirationTime and expirationTime > maxExpiration then
                    maxExpiration = expirationTime
                    duration = dur or 0
                end
            end
        end)
    end

    if hasDebuff and maxExpiration > 0 then
        local remaining = maxExpiration - GetTime()
        if remaining > 0 then
            lustFrame.cooldown:SetCooldown(maxExpiration - duration, duration)
            local minutes = math.floor(remaining / 60)
            local seconds = math.floor(remaining % 60)
            lustFrame.mainText:SetText(string.format("%d:%02d", minutes, seconds))
            lustFrame.mainText:SetTextColor(1, 0.2, 0.2, 1) -- 빨간색
        else
            lustFrame.mainText:SetText("")
            lustFrame.cooldown:SetCooldown(0, 0)
        end
        lustFrame.icon:SetDesaturated(true)
        lustFrame.chargeText:SetText("")
    else
        lustFrame.mainText:SetText("READY")
        lustFrame.mainText:SetTextColor(0, 1, 0, 1) -- 초록색
        lustFrame.icon:SetDesaturated(false)
        lustFrame.cooldown:SetCooldown(0, 0)
        lustFrame.chargeText:SetText("")
    end
end

-- 힐러 마나 업데이트
function PartyTracker:UpdateHealerMana()
    local separateMode = self.db.separateManaFrame
    local targetFrames = separateMode and separateHealerFrames or healerFrames

    -- 모든 힐러 프레임 숨기기
    for _, frame in ipairs(targetFrames) do
        frame:Hide()
    end

    -- 힐러 찾기
    local healers = {}
    local inRaid = IsInRaid()
    local numMembers = GetNumGroupMembers()

    if inRaid then
        -- 레이드: 전체 힐러 표시 (12.0+ secret value로 마나 표시 가능)
        for i = 1, numMembers do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local _, class = UnitClass(unit)
                -- 힐러 직업 클래스 체크
                if HEALER_CLASS_ICONS[class] then
                    local role = UnitGroupRolesAssigned(unit)
                    -- HEALER 역할만 표시 (역할 미지정은 너무 많아짐)
                    if role == "HEALER" then
                        table.insert(healers, {
                            unit = unit,
                            class = class,
                            name = UnitName(unit),
                        })
                    end
                end
            end
        end
    else
        -- 파티: player + party1 ~ partyN 체크
        -- 본인 체크
        if UnitGroupRolesAssigned("player") == "HEALER" then
            local _, class = UnitClass("player")
            if HEALER_CLASS_ICONS[class] then
                table.insert(healers, {
                    unit = "player",
                    class = class,
                    name = UnitName("player"),
                })
            end
        end

        -- 파티원 체크
        for i = 1, numMembers - 1 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "HEALER" then
                local _, class = UnitClass(unit)
                if HEALER_CLASS_ICONS[class] then
                    table.insert(healers, {
                        unit = unit,
                        class = class,
                        name = UnitName(unit),
                    })
                end
            end
        end
    end

    -- 힐러 프레임 업데이트
    for i, healer in ipairs(healers) do
        if i > #targetFrames then break end

        local frame = targetFrames[i]
        frame:Show()

        -- 아이콘 설정
        frame.icon:SetTexture(HEALER_CLASS_ICONS[healer.class])
        frame.chargeText:SetText("")

        -- 상태 체크
        local isDead = UnitIsDeadOrGhost(healer.unit)
        local isConnected = UnitIsConnected(healer.unit)

        if not isConnected then
            frame.mainText:SetText("OFF")
            frame.mainText:SetTextColor(0.5, 0.5, 0.5, 1)
            frame.icon:SetDesaturated(true)
            frame.manaBarBorder:Hide()
        elseif isDead then
            frame.mainText:SetText("DEAD")
            frame.mainText:SetTextColor(1, 0.1, 0.1, 1)
            frame.icon:SetDesaturated(true)
            frame.manaBarBorder:Hide()
        else
            -- NPC 동료인지 체크
            local isPlayer = UnitIsPlayer(healer.unit)

            if not isPlayer then
                -- NPC 동료
                frame.mainText:SetText("NPC")
                frame.mainText:SetTextColor(0.7, 0.7, 0.7, 1)
                frame.icon:SetDesaturated(false)
                frame.manaBarBorder:Hide()
            else
                -- 12.0+ Secret Value 대응 (ArcUI 방식)
                frame.icon:SetDesaturated(false)
                frame.mainText:SetText("")

                -- 마나바 표시 옵션
                if self.db.showManaBar then
                    local rawPower = UnitPower(healer.unit, Enum.PowerType.Mana)
                    local rawPowerMax = UnitPowerMax(healer.unit, Enum.PowerType.Mana)
                    frame.manaBar:SetMinMaxValues(0, rawPowerMax)
                    frame.manaBar:SetValue(rawPower)
                    frame.manaBar:SetStatusBarColor(0, 0.5, 1, 1)
                    frame.manaBarBorder:Show()
                else
                    frame.manaBarBorder:Hide()
                end

                -- 마나 퍼센트 텍스트 표시 옵션
                if self.db.showManaText and UnitPowerPercent then
                    local scaleTo100 = CurveConstants and CurveConstants.ScaleTo100 or 5
                    local pct = UnitPowerPercent(healer.unit, Enum.PowerType.Mana, false, scaleTo100)
                    if pct then
                        frame.manaText:SetFormattedText("%.0f%%", pct)
                        frame.manaText:SetTextColor(1, 1, 1, 1)
                    else
                        frame.manaText:SetText("")
                    end
                else
                    frame.manaText:SetText("")
                end
            end
        end

        -- 이름 표시 (서브텍스트)
        frame.subText:SetText(healer.name)
        if CLASS_COLORS[healer.class] then
            frame.subText:SetTextColor(unpack(CLASS_COLORS[healer.class]))
        end
    end
end

-- 메인 프레임 반환
function PartyTracker:GetMainFrame()
    return mainFrame
end

-- 메인 프레임 크기 업데이트
function PartyTracker:UpdateScale()
    if mainFrame then
        mainFrame:SetScale(self.db.scale or 1.0)
    end
end

-- 잠금 상태 업데이트 (마우스 상호작용)
function PartyTracker:UpdateLockState()
    if mainFrame then
        local locked = self.db and self.db.locked
        mainFrame:EnableMouse(not locked)
    end
    if manaFrame then
        local manaLocked = self.db and self.db.manaLocked
        manaFrame:EnableMouse(not manaLocked)
    end
end

-- 잠금 상태 업데이트 (마우스 상호작용)
function PartyTracker:UpdateLockState()
    if mainFrame then
        local locked = self.db and self.db.locked
        mainFrame:EnableMouse(not locked)
    end
    if manaFrame then
        local manaLocked = self.db and self.db.manaLocked
        manaFrame:EnableMouse(not manaLocked)
    end
end

-- 마나 프레임 크기 업데이트
function PartyTracker:UpdateManaScale()
    if manaFrame then
        manaFrame:SetScale(self.db.manaScale or 1.0)
    end
end

-- 아이콘 크기 업데이트
function PartyTracker:UpdateIconSize()
    local size = self.db.iconSize or 33

    local function updateFrame(frame)
        if not frame then return end
        frame:SetSize(size + 50, size)
        if frame.iconFrame then
            frame.iconFrame:SetSize(size, size)
        end
    end

    updateFrame(battleResFrame)

    for _, frame in ipairs(healerFrames) do
        updateFrame(frame)
    end

    for _, frame in ipairs(separateHealerFrames) do
        updateFrame(frame)
    end
end

-- 위치 초기화
function PartyTracker:ResetPosition()
    self.db.position = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = -500,
        y = -110,
    }
    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", -500, -110)
    end
end

-- 테스트 모드
function PartyTracker:TestMode()
    local separateMode = self.db.separateManaFrame

    -- 토글 종료
    if isTestMode then
        isTestMode = false

        -- 프레임 숨기기
        mainFrame:Hide()
        if manaFrame then manaFrame:Hide() end

        -- 테스트 데이터 초기화
        if battleResFrame then
            battleResFrame.chargeText:SetText("")
            battleResFrame.mainText:SetText("")
            battleResFrame.subText:SetText("")
        end
        if lustFrame then
            lustFrame.chargeText:SetText("")
            lustFrame.mainText:SetText("")
            lustFrame.subText:SetText("")
        end
        for _, frame in ipairs(healerFrames) do
            frame:Hide()
            frame.chargeText:SetText("")
            frame.mainText:SetText("")
            frame.subText:SetText("")
        end
        for _, frame in ipairs(separateHealerFrames) do
            frame:Hide()
            frame.chargeText:SetText("")
            frame.mainText:SetText("")
            frame.subText:SetText("")
        end

        -- 업데이트 재시작
        self:StartUpdate()

        -- 그룹에 있을 때만 다시 표시
        if IsInGroup() then
            self:UpdateVisibility()
        end

        print(CHAT_PREFIX .. L["PARTYTRACKER_TEST_END"]) -- [STYLE]
        return
    end

    isTestMode = true

    if not mainFrame then
        self:CreateMainFrame()
    end

    -- 분리 모드 시 마나 프레임 생성
    if separateMode and not manaFrame then
        self:CreateSeparateManaFrame()
    end

    -- 업데이트 중지 (테스트 중에는 실제 데이터로 덮어쓰지 않도록)
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end

    mainFrame:Show()

    -- 전투 부활 테스트
    battleResFrame:Show()
    battleResFrame.icon:SetTexture(136080)  -- 환생 아이콘
    battleResFrame.icon:SetDesaturated(false)
    battleResFrame.chargeText:SetText("1")
    battleResFrame.chargeText:SetTextColor(0, 1, 0, 1)
    battleResFrame.mainText:SetText("3:45")
    battleResFrame.mainText:SetTextColor(1, 1, 1, 1)
    battleResFrame.subText:SetText("")
    battleResFrame.cooldown:SetCooldown(0, 0)

    -- 블러드 테스트
    if self.db.showLust ~= false and lustFrame then
        lustFrame:Show()
        lustFrame.icon:SetTexture(136012)
        lustFrame.icon:SetDesaturated(true)
        lustFrame.chargeText:SetText("")
        lustFrame.mainText:SetText("8:45")
        lustFrame.mainText:SetTextColor(1, 0.2, 0.2, 1)
        lustFrame.subText:SetText("")
        lustFrame.cooldown:SetCooldown(GetTime() - 75, 600)
    end

    -- 힐러 테스트 데이터
    local testHealers = {
        {class = "PRIEST", name = "Priest", mana = 85},
        {class = "DRUID", name = "Druid", mana = 42},
    }

    -- 분리 모드에 따라 타겟 프레임 선택
    local targetFrames = separateMode and separateHealerFrames or healerFrames

    -- 모든 힐러 프레임 먼저 숨기기
    for _, frame in ipairs(healerFrames) do
        frame:Hide()
    end
    for _, frame in ipairs(separateHealerFrames) do
        frame:Hide()
    end

    -- 분리 모드 시 마나 프레임 표시
    if separateMode and manaFrame then
        manaFrame:Show()
    end

    -- 테스트 힐러 표시 (마나바 사용)
    for i, healer in ipairs(testHealers) do
        local frame = targetFrames[i]
        if frame then
            frame:ClearAllPoints()
            if separateMode then
                if i == 1 then
                    frame:SetPoint("TOPLEFT", manaFrame, "TOPLEFT", 0, 0)
                else
                    frame:SetPoint("TOPLEFT", targetFrames[i-1], "BOTTOMLEFT", 0, -5)
                end
            else
                if i == 1 then
                    local lastFrame = (self.db.showLust ~= false and lustFrame) and lustFrame or battleResFrame
                    frame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -5)
                else
                    frame:SetPoint("TOPLEFT", targetFrames[i-1], "BOTTOMLEFT", 0, -5)
                end
            end

            frame.icon:SetTexture(HEALER_CLASS_ICONS[healer.class])
            frame.icon:SetDesaturated(false)
            frame.chargeText:SetText("")

            -- 마나바로 표시 (실제 동작과 동일하게)
            frame.manaBar:SetMinMaxValues(0, 100)
            frame.manaBar:SetValue(healer.mana)
            frame.manaBar:SetStatusBarColor(0, 0.5, 1, 1)
            frame.manaBarBorder:Show()

            -- 마나바 위 텍스트
            frame.manaText:SetText(healer.mana .. "%")
            if healer.mana <= 30 then
                frame.manaText:SetTextColor(1, 0.3, 0.3, 1)
            elseif healer.mana <= 60 then
                frame.manaText:SetTextColor(1, 1, 0.3, 1)
            else
                frame.manaText:SetTextColor(1, 1, 1, 1)
            end

            -- mainText는 비움 (실제 동작과 동일)
            frame.mainText:SetText("")

            frame.subText:SetText(healer.name)
            if CLASS_COLORS[healer.class] then
                frame.subText:SetTextColor(unpack(CLASS_COLORS[healer.class]))
            end

            frame.cooldown:SetCooldown(0, 0)
            frame:Show()
        end
    end

    print(CHAT_PREFIX .. L["PARTYTRACKER_TEST_START"]) -- [STYLE]
end

-- 이벤트 프레임
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- PLAYER_ENTERING_WORLD에서 모듈이 활성화 안됐으면 수동 활성화
    if event == "PLAYER_ENTERING_WORLD" then
        if not isEnabled and ns.db and ns.db.profile and ns.db.profile.modules and ns.db.profile.modules.PartyTracker then
            PartyTracker:OnEnable()
        end
    end

    if not isEnabled then return end

    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        -- 프레임이 없으면 생성
        if not mainFrame then
            PartyTracker:CreateMainFrame()
        end
        -- ticker가 없으면 시작
        if not updateTicker then
            PartyTracker:StartUpdate()
        end
        PartyTracker:UpdateVisibility()
    end
end)

-- 디버그: 힐러 마나 정보 출력 (12.0+ UnitPowerPercent 사용)
SLASH_PTDEBUG1 = "/ptdebug"
SlashCmdList["PTDEBUG"] = function()
    local inRaid = IsInRaid()
    local numMembers = GetNumGroupMembers()
    local scaleTo100 = CurveConstants and CurveConstants.ScaleTo100 or 5

    print(CHAT_PREFIX .. "Debug - InRaid:", inRaid, "Members:", numMembers) -- [STYLE]
    print("  UnitPowerPercent:", UnitPowerPercent and "exists" or "nil")
    print("  CurveConstants.ScaleTo100:", CurveConstants and CurveConstants.ScaleTo100 or "nil (using 5)")

    local function printUnitMana(unit, name, class, role)
        -- UnitPowerPercent 사용 (secret value 대응)
        local pct = UnitPowerPercent and UnitPowerPercent(unit, Enum.PowerType.Mana, false, scaleTo100)
        local pctStr = pct and string.format("%.1f%%", pct) or "N/A"

        if role then
            print(string.format("  %s: %s (%s) role=%s pct=%s",
                unit, name or "?", class or "?", role or "NONE", pctStr))
        else
            print(string.format("  %s: %s (%s) pct=%s",
                unit, name or "?", class or "?", pctStr))
        end
    end

    if inRaid then
        for i = 1, numMembers do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local _, class = UnitClass(unit)
                local role = UnitGroupRolesAssigned(unit)

                -- 힐러 클래스만 출력
                if HEALER_CLASS_ICONS and HEALER_CLASS_ICONS[class] then
                    printUnitMana(unit, name, class, role)
                end
            end
        end
    else
        -- 파티
        local unit = "player"
        local name = UnitName(unit)
        local _, class = UnitClass(unit)
        printUnitMana(unit, name, class)

        for i = 1, 4 do
            unit = "party" .. i
            if UnitExists(unit) then
                name = UnitName(unit)
                _, class = UnitClass(unit)
                local role = UnitGroupRolesAssigned(unit)
                printUnitMana(unit, name, class, role)
            end
        end
    end
end

-- 옵션 토글 명령어
SLASH_PT1 = "/pt"
SLASH_PT2 = "/partytracker"
SlashCmdList["PT"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word:lower())
    end

    local cmd = args[1]

    if not cmd or cmd == "help" then
        print(CHAT_PREFIX .. L["PARTYTRACKER_COMMANDS"]) -- [STYLE]
        print("  /pt enable - enable module")
        print("  /pt disable - disable module")
        print("  /pt party - toggle party display")
        print("  /pt raid - toggle raid display")
        print("  /pt bar - toggle mana bar")
        print("  /pt text - toggle mana text")
        print("  /pt status - show current settings")
        print("  /pt all - enable all options")
        return
    end

    local db = PartyTracker.db
    if not db then
        print(CHAT_PREFIX .. "|cFFFF0000" .. L["PARTYTRACKER_SETTINGS_NOT_FOUND"] .. "|r") -- [STYLE]
        return
    end

    if cmd == "enable" then
        db.enabled = true
        print(CHAT_PREFIX .. L["PARTYTRACKER_MODULE_ENABLED_MSG"]) -- [STYLE]
    elseif cmd == "disable" then
        db.enabled = false
        print(CHAT_PREFIX .. L["PARTYTRACKER_MODULE_DISABLED_MSG"]) -- [STYLE]
    elseif cmd == "party" then
        db.showInParty = not db.showInParty
        print(CHAT_PREFIX .. L["PARTYTRACKER_PARTY_DISPLAY"], db.showInParty and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"]) -- [STYLE]
        PartyTracker:UpdateVisibility()
    elseif cmd == "raid" then
        db.showInRaid = not db.showInRaid
        print(CHAT_PREFIX .. L["PARTYTRACKER_RAID_DISPLAY"], db.showInRaid and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"]) -- [STYLE]
        PartyTracker:UpdateVisibility()
    elseif cmd == "bar" then
        db.showManaBar = not db.showManaBar
        print(CHAT_PREFIX .. L["PARTYTRACKER_MANA_BAR_DISPLAY"], db.showManaBar and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"]) -- [STYLE]
    elseif cmd == "text" then
        db.showManaText = not db.showManaText
        print(CHAT_PREFIX .. L["PARTYTRACKER_MANA_TEXT_DISPLAY"], db.showManaText and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"]) -- [STYLE]
    elseif cmd == "status" then
        print(CHAT_PREFIX .. L["PARTYTRACKER_CURRENT_SETTINGS"]) -- [STYLE]
        print("  " .. L["PARTYTRACKER_MODULE_ACTIVE"], db.enabled and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"])
        print("  " .. L["PARTYTRACKER_PARTY_DISPLAY"], db.showInParty and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"])
        print("  " .. L["PARTYTRACKER_RAID_DISPLAY"], db.showInRaid and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"])
        print("  " .. L["PARTYTRACKER_MANA_BAR_DISPLAY"], db.showManaBar and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"])
        print("  " .. L["PARTYTRACKER_MANA_TEXT_DISPLAY"], db.showManaText and L["PARTYTRACKER_ON"] or L["PARTYTRACKER_OFF"])
    elseif cmd == "all" then
        db.enabled = true
        db.showInParty = true
        db.showInRaid = true
        db.showManaBar = true
        db.showManaText = true
        print(CHAT_PREFIX .. L["PARTYTRACKER_ALL_ENABLED"]) -- [STYLE]
    else
        print(CHAT_PREFIX .. "|cFFFF0000" .. L["PARTYTRACKER_UNKNOWN_CMD"] .. "|r") -- [STYLE]
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("PartyTracker", PartyTracker)
