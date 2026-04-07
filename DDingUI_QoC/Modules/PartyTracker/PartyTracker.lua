--[[
    DDingQoC - PartyTracker Module
    파티/레이드: 전투 부활, 블러드, 힐러 마나
    DDingUI_Toolkit에서 포팅 (12.0 Secret Value 보강)
]]

local addonName, ns = ...
local DDingQoC = ns.DDingQoC
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: "

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

-- 블러드 디버프 스펠 ID
local LUST_DEBUFFS = {
    [57724] = true,  -- 만족함 (피의 욕망)
    [57723] = true,  -- 소진 (영웅심)
    [80354] = true,  -- 시간의 균열 (시간 왜곡)
    [264689] = true, -- 피로 (원시적인 분노)
    [390435] = true, -- 지침 (위상의 열기)
}

------------------------------------------------------------
-- 모듈 라이프사이클
------------------------------------------------------------
function PartyTracker:OnInitialize()
    if ns.db and ns.db.profile and ns.db.profile.PartyTracker then
        self.db = ns.db.profile.PartyTracker
    end
end

function PartyTracker:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.PartyTracker then
            self.db = ns.db.profile.PartyTracker
        else
            return
        end
    end

    isEnabled = true
    self:CreateMainFrame()
    self:UpdateVisibility()
    self:StartUpdate()
end

function PartyTracker:OnDisable()
    isEnabled = false
    if mainFrame then mainFrame:Hide() end
    if updateTicker then updateTicker:Cancel(); updateTicker = nil end
end

------------------------------------------------------------
-- 메인 프레임 생성
------------------------------------------------------------
function PartyTracker:CreateMainFrame()
    if mainFrame then return end
    if not self.db then return end

    local pos = self.db.position or {}
    local frame = CreateFrame("Frame", "DDingQoC_PartyTrackerFrame", UIParent)
    frame:SetSize(150, 350)
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or -500, pos.y or -110)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)

    frame:SetMovable(true)
    frame:EnableMouse(not self.db.locked)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not PartyTracker.db.locked then self:StartMoving() end
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

    if self.db.scale then mainFrame:SetScale(self.db.scale) end

    self:CreateBattleResFrame()
    self:CreateLustFrame()
    self:CreateHealerFrames()
end

------------------------------------------------------------
-- 아이콘 프레임 템플릿
------------------------------------------------------------
function PartyTracker:CreateIconFrame(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size + 80, size)

    local font = self.db.font or SL_FONT
    local fontSize = self.db.fontSize or 14

    -- 아이콘 컨테이너
    frame.iconFrame = CreateFrame("Frame", nil, frame)
    frame.iconFrame:SetSize(size, size)
    frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)

    frame.bg = frame.iconFrame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 1)

    frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 1, -1)
    frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.cooldown = CreateFrame("Cooldown", nil, frame.iconFrame, "CooldownFrameTemplate")
    frame.cooldown:SetPoint("TOPLEFT", 1, -1)
    frame.cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(true)

    frame.textOverlay = CreateFrame("Frame", nil, frame.iconFrame)
    frame.textOverlay:SetAllPoints()
    frame.textOverlay:SetFrameLevel(frame.cooldown:GetFrameLevel() + 2)

    frame.chargeText = frame.textOverlay:CreateFontString(nil, "OVERLAY")
    frame.chargeText:SetFont(font, fontSize + 4, "OUTLINE")
    frame.chargeText:SetPoint("CENTER", frame.iconFrame, "CENTER", 0, 0)
    frame.chargeText:SetTextColor(1, 1, 1, 1)

    -- 마나바
    local manaBarWidth = self.db.manaBarWidth or 60
    local manaBarHeight = self.db.manaBarHeight or 10
    local manaBarOffsetX = self.db.manaBarOffsetX or 4
    local manaBarOffsetY = self.db.manaBarOffsetY or 6
    local manaBarTexture = self.db.manaBarTexture or "Interface\\TargetingFrame\\UI-StatusBar"

    frame.manaBarBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.manaBarBorder:SetSize(manaBarWidth + 2, manaBarHeight + 2)
    frame.manaBarBorder:SetPoint("LEFT", frame.iconFrame, "RIGHT", manaBarOffsetX - 1, manaBarOffsetY)
    frame.manaBarBorder:SetBackdrop({
        bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame.manaBarBorder:SetBackdropColor(0, 0, 0, 0.8)
    frame.manaBarBorder:SetBackdropBorderColor(0, 0, 0, 1)
    frame.manaBarBorder:Hide()

    frame.manaBar = CreateFrame("StatusBar", nil, frame.manaBarBorder)
    frame.manaBar:SetSize(manaBarWidth, manaBarHeight)
    frame.manaBar:SetPoint("CENTER", frame.manaBarBorder, "CENTER", 0, 0)
    frame.manaBar:SetStatusBarTexture(manaBarTexture)
    frame.manaBar:SetStatusBarColor(0, 0.5, 1, 1)
    frame.manaBar:SetMinMaxValues(0, 100)
    frame.manaBar:SetValue(0)

    frame.manaText = frame.manaBar:CreateFontString(nil, "OVERLAY")
    frame.manaText:SetFont(font, fontSize - 2, "OUTLINE")
    frame.manaText:SetPoint("CENTER", frame.manaBar, "CENTER", 0, 0)
    frame.manaText:SetTextColor(1, 1, 1, 1)

    frame.mainText = frame:CreateFontString(nil, "OVERLAY")
    frame.mainText:SetFont(font, fontSize, "OUTLINE")
    frame.mainText:SetPoint("LEFT", frame.iconFrame, "RIGHT", 4, -6)
    frame.mainText:SetTextColor(1, 1, 1, 1)

    frame.subText = frame:CreateFontString(nil, "OVERLAY")
    frame.subText:SetFont(font, fontSize - 2, "OUTLINE")
    frame.subText:SetPoint("LEFT", frame.mainText, "RIGHT", 4, 0)
    frame.subText:SetTextColor(0.7, 0.7, 0.7, 1)

    return frame
end

------------------------------------------------------------
-- 전투 부활 / 블러드 / 힐러 프레임 생성
------------------------------------------------------------
function PartyTracker:CreateBattleResFrame()
    if battleResFrame then return end
    local frame = self:CreateIconFrame(mainFrame, self.db.iconSize or 33)
    frame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
    frame.icon:SetTexture(136080)
    frame:Show()

    -- 툴팁
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["PT_BATTLE_RES"] or "전투 부활", 1, 0.82, 0)
        local chargeStr = self.chargeText:GetText() or "-"
        local cdStr = self.mainText:GetText()
        GameTooltip:AddLine((L["PT_CHARGES"] or "충전") .. ": " .. chargeStr, 1, 1, 1)
        if cdStr and cdStr ~= "" then
            GameTooltip:AddLine((L["PT_NEXT_CHARGE"] or "다음 충전") .. ": " .. cdStr, 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    battleResFrame = frame
end

function PartyTracker:CreateLustFrame()
    if lustFrame then return end
    local frame = self:CreateIconFrame(mainFrame, self.db.iconSize or 33)
    frame.icon:SetTexture(136012)
    frame:Show()

    -- 툴팁
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["PT_BLOODLUST"] or "블러드", 1, 0.82, 0)
        local statusStr = self.mainText:GetText() or ""
        if statusStr == "READY" then
            GameTooltip:AddLine(L["PT_LUST_READY"] or "사용 가능", 0, 1, 0)
        elseif statusStr ~= "" then
            GameTooltip:AddLine((L["PT_LUST_EXHAUSTION"] or "디버프 남은 시간") .. ": " .. statusStr, 1, 0.2, 0.2)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    lustFrame = frame
end

function PartyTracker:CreateHealerFrames()
    if #healerFrames > 0 then return end
    for i = 1, 6 do
        local frame = self:CreateIconFrame(mainFrame, self.db.iconSize or 33)
        if i > 1 then
            frame:SetPoint("TOPLEFT", healerFrames[i-1], "BOTTOMLEFT", 0, -5)
        end

        -- 힐러 툴팁
        frame:EnableMouse(true)
        frame:SetScript("OnEnter", function(self)
            if not self._healerData then return end
            local h = self._healerData
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local cc = CLASS_COLORS[h.class]
            if cc then
                GameTooltip:AddLine(h.name, cc[1], cc[2], cc[3])
            else
                GameTooltip:AddLine(h.name, 1, 1, 1)
            end
            -- secret value 방어: pcall로 GetText 비교/연결
            pcall(function()
                local manaStr = self.manaText:GetText()
                if manaStr and manaStr ~= "" then
                    GameTooltip:AddLine((L["PT_MANA"] or "마나") .. ": " .. manaStr, 0.3, 0.6, 1)
                end
            end)
            pcall(function()
                local statusStr = self.mainText:GetText()
                if statusStr == "DEAD" then
                    GameTooltip:AddLine(L["PT_DEAD"] or "사망", 1, 0.1, 0.1)
                elseif statusStr == "OFF" then
                    GameTooltip:AddLine(L["PT_OFFLINE"] or "오프라인", 0.5, 0.5, 0.5)
                end
            end)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        frame:Hide()
        healerFrames[i] = frame
    end
end

------------------------------------------------------------
-- 분리 힐러 마나 프레임
------------------------------------------------------------
function PartyTracker:CreateSeparateManaFrame()
    if manaFrame then return end

    local pos = self.db.manaPosition or { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 }
    local frame = CreateFrame("Frame", "DDingQoC_PartyTrackerManaFrame", UIParent)
    frame:SetSize(150, 250)
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -150)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)

    frame:SetMovable(true)
    frame:EnableMouse(not self.db.manaLocked)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not PartyTracker.db.manaLocked then self:StartMoving() end
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

    if self.db.manaScale then frame:SetScale(self.db.manaScale) end
    manaFrame = frame

    for i = 1, 6 do
        local healerFrame = self:CreateIconFrame(manaFrame, self.db.iconSize or 33)
        if i == 1 then
            healerFrame:SetPoint("TOPLEFT", manaFrame, "TOPLEFT", 0, 0)
        else
            healerFrame:SetPoint("TOPLEFT", separateHealerFrames[i-1], "BOTTOMLEFT", 0, -5)
        end

        -- 힐러 툴팁
        healerFrame:EnableMouse(true)
        healerFrame:SetScript("OnEnter", function(self)
            if not self._healerData then return end
            local h = self._healerData
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local cc = CLASS_COLORS[h.class]
            if cc then
                GameTooltip:AddLine(h.name, cc[1], cc[2], cc[3])
            else
                GameTooltip:AddLine(h.name, 1, 1, 1)
            end
            pcall(function()
                local manaStr = self.manaText:GetText()
                if manaStr and manaStr ~= "" then
                    GameTooltip:AddLine((L["PT_MANA"] or "마나") .. ": " .. manaStr, 0.3, 0.6, 1)
                end
            end)
            pcall(function()
                local statusStr = self.mainText:GetText()
                if statusStr == "DEAD" then
                    GameTooltip:AddLine(L["PT_DEAD"] or "사망", 1, 0.1, 0.1)
                elseif statusStr == "OFF" then
                    GameTooltip:AddLine(L["PT_OFFLINE"] or "오프라인", 0.5, 0.5, 0.5)
                end
            end)
            GameTooltip:Show()
        end)
        healerFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        healerFrame:Hide()
        separateHealerFrames[i] = healerFrame
    end
    frame:Hide()
end

------------------------------------------------------------
-- 가시성 / 업데이트
------------------------------------------------------------
function PartyTracker:UpdateVisibility()
    if not mainFrame then return end
    if isTestMode then return end

    local inGroup = IsInGroup()
    local inRaid = IsInRaid()
    local showInParty = self.db.showInParty ~= false
    local showInRaid = self.db.showInRaid ~= false
    local separateMode = self.db.separateManaFrame

    if not inGroup then
        mainFrame:Hide()
        if manaFrame then manaFrame:Hide() end
        return
    end

    if inRaid and not showInRaid then
        mainFrame:Hide(); if manaFrame then manaFrame:Hide() end; return
    end
    if not inRaid and not showInParty then
        mainFrame:Hide(); if manaFrame then manaFrame:Hide() end; return
    end

    mainFrame:Show()

    if separateMode then
        if not manaFrame then self:CreateSeparateManaFrame() end
        manaFrame:Show()
        for _, frame in ipairs(healerFrames) do frame:Hide() end
    else
        if manaFrame then manaFrame:Hide() end
        for _, frame in ipairs(separateHealerFrames) do frame:Hide() end
    end

    battleResFrame:Show()
    local lastActiveFrame = battleResFrame

    if self.db.showLust ~= false and lustFrame then
        lustFrame:Show()
        lustFrame:SetPoint("TOPLEFT", lastActiveFrame, "BOTTOMLEFT", 0, -5)
        lastActiveFrame = lustFrame
    else
        if lustFrame then lustFrame:Hide() end
    end

    if not separateMode and #healerFrames > 0 then
        healerFrames[1]:SetPoint("TOPLEFT", lastActiveFrame, "BOTTOMLEFT", 0, -5)
    end
end

function PartyTracker:StartUpdate()
    if updateTicker then updateTicker:Cancel() end
    updateTicker = C_Timer.NewTicker(0.5, function()
        if isEnabled then PartyTracker:Update() end
    end)
end

function PartyTracker:Update()
    if not mainFrame or not mainFrame:IsShown() then return end
    if isTestMode then return end

    if battleResFrame and battleResFrame:IsShown() then self:UpdateBattleRes() end
    if lustFrame and lustFrame:IsShown() then self:UpdateLust() end
    self:UpdateHealerMana()
end

------------------------------------------------------------
-- 전투 부활 업데이트
------------------------------------------------------------
function PartyTracker:UpdateBattleRes()
    if not battleResFrame then return end

    local GetSpellChargesCompat = C_Spell and C_Spell.GetSpellCharges or GetSpellCharges
    local chargeInfo = GetSpellChargesCompat(20484)

    local charges, maxCharges, start, duration
    if type(chargeInfo) == "table" then
        charges = chargeInfo.currentCharges
        maxCharges = chargeInfo.maxCharges
        start = chargeInfo.cooldownStartTime
        duration = chargeInfo.cooldownDuration
    else
        charges, maxCharges, start, duration = GetSpellChargesCompat(20484)
    end

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

    battleResFrame.chargeText:SetText(tostring(charges))
    if charges > 0 then
        battleResFrame.chargeText:SetTextColor(0, 1, 0, 1)
        battleResFrame.icon:SetDesaturated(false)
    else
        battleResFrame.chargeText:SetTextColor(1, 0, 0, 1)
        battleResFrame.icon:SetDesaturated(true)
    end

    if charges < maxCharges and start > 0 and duration > 0 then
        local remaining = (start + duration) - GetTime()
        if remaining > 0 then
            battleResFrame.cooldown:SetCooldown(start, duration)
            battleResFrame.mainText:SetText(string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)))
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

------------------------------------------------------------
-- 블러드 디버프 업데이트
------------------------------------------------------------
function PartyTracker:UpdateLust()
    if not lustFrame or not lustFrame:IsShown() then return end

    local maxExpiration = 0
    local dur = 0
    local hasDebuff = false

    for i = 1, 40 do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
        if not ok or not auraData then break end
        pcall(function()
            local spellId = auraData.spellId
            if spellId and type(spellId) == "number" and LUST_DEBUFFS[spellId] then
                hasDebuff = true
                local expirationTime = auraData.expirationTime
                local d = auraData.duration
                if expirationTime and expirationTime > maxExpiration then
                    maxExpiration = expirationTime
                    dur = d or 0
                end
            end
        end)
    end

    if hasDebuff and maxExpiration > 0 then
        local remaining = maxExpiration - GetTime()
        if remaining > 0 then
            lustFrame.cooldown:SetCooldown(maxExpiration - dur, dur)
            lustFrame.mainText:SetText(string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)))
            lustFrame.mainText:SetTextColor(1, 0.2, 0.2, 1)
        else
            lustFrame.mainText:SetText("")
            lustFrame.cooldown:SetCooldown(0, 0)
        end
        lustFrame.icon:SetDesaturated(true)
        lustFrame.chargeText:SetText("")
    else
        lustFrame.mainText:SetText("READY")
        lustFrame.mainText:SetTextColor(0, 1, 0, 1)
        lustFrame.icon:SetDesaturated(false)
        lustFrame.cooldown:SetCooldown(0, 0)
        lustFrame.chargeText:SetText("")
    end
end

------------------------------------------------------------
-- 힐러 마나 업데이트
------------------------------------------------------------
function PartyTracker:UpdateHealerMana()
    local separateMode = self.db.separateManaFrame
    local targetFrames = separateMode and separateHealerFrames or healerFrames

    for _, frame in ipairs(targetFrames) do frame:Hide() end

    local healers = {}
    local inRaid = IsInRaid()
    local numMembers = GetNumGroupMembers()

    if inRaid then
        for i = 1, numMembers do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local _, class = UnitClass(unit)
                if HEALER_CLASS_ICONS[class] and UnitGroupRolesAssigned(unit) == "HEALER" then
                    healers[#healers + 1] = { unit = unit, class = class, name = UnitName(unit) }
                end
            end
        end
    else
        if UnitGroupRolesAssigned("player") == "HEALER" then
            local _, class = UnitClass("player")
            if HEALER_CLASS_ICONS[class] then
                healers[#healers + 1] = { unit = "player", class = class, name = UnitName("player") }
            end
        end
        for i = 1, numMembers - 1 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "HEALER" then
                local _, class = UnitClass(unit)
                if HEALER_CLASS_ICONS[class] then
                    healers[#healers + 1] = { unit = unit, class = class, name = UnitName(unit) }
                end
            end
        end
    end

    for i, healer in ipairs(healers) do
        if i > #targetFrames then break end
        local frame = targetFrames[i]
        frame:Show()
        frame._healerData = healer  -- 툴팁용 데이터 저장
        frame.icon:SetTexture(HEALER_CLASS_ICONS[healer.class])
        frame.chargeText:SetText("")

        local isDead = UnitIsDeadOrGhost(healer.unit)
        local isConnected = UnitIsConnected(healer.unit)

        if not isConnected then
            frame.mainText:SetText("OFF"); frame.mainText:SetTextColor(0.5, 0.5, 0.5, 1)
            frame.icon:SetDesaturated(true); frame.manaBarBorder:Hide()
        elseif isDead then
            frame.mainText:SetText("DEAD"); frame.mainText:SetTextColor(1, 0.1, 0.1, 1)
            frame.icon:SetDesaturated(true); frame.manaBarBorder:Hide()
        else
            local isPlayer = UnitIsPlayer(healer.unit)
            if not isPlayer then
                frame.mainText:SetText("NPC"); frame.mainText:SetTextColor(0.7, 0.7, 0.7, 1)
                frame.icon:SetDesaturated(false); frame.manaBarBorder:Hide()
            else
                frame.icon:SetDesaturated(false)
                frame.mainText:SetText("")

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

        frame.subText:SetText(healer.name)
        if CLASS_COLORS[healer.class] then
            frame.subText:SetTextColor(unpack(CLASS_COLORS[healer.class]))
        end
    end
end

------------------------------------------------------------
-- 유틸리티 함수들
------------------------------------------------------------
function PartyTracker:UpdateFonts()
    local font = self.db.font or SL_FONT
    local fontSize = self.db.fontSize or 14
    local function updateFrame(frame)
        if not frame then return end
        frame.chargeText:SetFont(font, fontSize + 4, "OUTLINE")
        frame.mainText:SetFont(font, fontSize, "OUTLINE")
        frame.subText:SetFont(font, fontSize - 2, "OUTLINE")
        if frame.manaText then frame.manaText:SetFont(font, fontSize - 2, "OUTLINE") end
    end
    updateFrame(battleResFrame)
    updateFrame(lustFrame)
    for _, frame in ipairs(healerFrames) do updateFrame(frame) end
    for _, frame in ipairs(separateHealerFrames) do updateFrame(frame) end
end

function PartyTracker:UpdateManaBarSize()
    local width = self.db.manaBarWidth or 60
    local height = self.db.manaBarHeight or 10
    for _, frame in ipairs(healerFrames) do
        if frame.manaBar then frame.manaBar:SetSize(width, height) end
        if frame.manaBarBorder then frame.manaBarBorder:SetSize(width + 2, height + 2) end
    end
end

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

function PartyTracker:UpdateManaBarTexture()
    local texture = self.db.manaBarTexture or "Interface\\TargetingFrame\\UI-StatusBar"
    for _, frame in ipairs(healerFrames) do
        if frame.manaBar then frame.manaBar:SetStatusBarTexture(texture) end
    end
end

function PartyTracker:UpdateScale()
    if mainFrame then mainFrame:SetScale(self.db.scale or 1.0) end
end

function PartyTracker:UpdateManaScale()
    if manaFrame then manaFrame:SetScale(self.db.manaScale or 1.0) end
end

function PartyTracker:UpdateLockState()
    if mainFrame then mainFrame:EnableMouse(not (self.db and self.db.locked)) end
    if manaFrame then manaFrame:EnableMouse(not (self.db and self.db.manaLocked)) end
end

function PartyTracker:UpdateIconSize()
    local size = self.db.iconSize or 33
    local function updateFrame(frame)
        if not frame then return end
        frame:SetSize(size + 50, size)
        if frame.iconFrame then frame.iconFrame:SetSize(size, size) end
    end
    updateFrame(battleResFrame)
    for _, frame in ipairs(healerFrames) do updateFrame(frame) end
    for _, frame in ipairs(separateHealerFrames) do updateFrame(frame) end
end

function PartyTracker:ResetPosition()
    self.db.position = { point = "CENTER", relativePoint = "CENTER", x = -500, y = -110 }
    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", -500, -110)
    end
    print(CHAT_PREFIX .. (L["POSITION_RESET"] or "위치가 초기화되었습니다."))
end

function PartyTracker:ResetManaPosition()
    self.db.manaPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 }
    if manaFrame then
        manaFrame:ClearAllPoints()
        manaFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
    print(CHAT_PREFIX .. (L["PARTYTRACKER_MANA_POSITION_RESET_MSG"] or "마나 프레임 위치가 초기화되었습니다."))
end

function PartyTracker:ToggleSeparateManaFrame(enable)
    self.db.separateManaFrame = enable
    if enable then
        if not manaFrame then self:CreateSeparateManaFrame() end
        for _, frame in ipairs(healerFrames) do frame:Hide() end
    else
        if manaFrame then manaFrame:Hide() end
        for _, frame in ipairs(separateHealerFrames) do frame:Hide() end
    end
    self:UpdateVisibility()
end

------------------------------------------------------------
-- 테스트 모드
------------------------------------------------------------
function PartyTracker:TestMode()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.PartyTracker then
            self.db = ns.db.profile.PartyTracker
        else
            print(CHAT_PREFIX .. "|cFFFF0000DB를 찾을 수 없습니다.|r")
            return
        end
    end

    local separateMode = self.db.separateManaFrame

    if isTestMode then
        isTestMode = false
        mainFrame:Hide()
        if manaFrame then manaFrame:Hide() end
        if battleResFrame then
            battleResFrame.chargeText:SetText(""); battleResFrame.mainText:SetText(""); battleResFrame.subText:SetText("")
        end
        if lustFrame then
            lustFrame.chargeText:SetText(""); lustFrame.mainText:SetText(""); lustFrame.subText:SetText("")
        end
        for _, frame in ipairs(healerFrames) do
            frame:Hide(); frame.chargeText:SetText(""); frame.mainText:SetText(""); frame.subText:SetText("")
        end
        for _, frame in ipairs(separateHealerFrames) do
            frame:Hide(); frame.chargeText:SetText(""); frame.mainText:SetText(""); frame.subText:SetText("")
        end
        self:StartUpdate()
        if IsInGroup() then self:UpdateVisibility() end
        print(CHAT_PREFIX .. (L["PARTYTRACKER_TEST_END"] or "테스트 모드 종료"))
        return
    end

    isTestMode = true
    if not mainFrame then self:CreateMainFrame() end
    if separateMode and not manaFrame then self:CreateSeparateManaFrame() end
    if updateTicker then updateTicker:Cancel(); updateTicker = nil end

    mainFrame:Show()

    -- 전투 부활 테스트
    battleResFrame:Show()
    battleResFrame.icon:SetTexture(136080); battleResFrame.icon:SetDesaturated(false)
    battleResFrame.chargeText:SetText("1"); battleResFrame.chargeText:SetTextColor(0, 1, 0, 1)
    battleResFrame.mainText:SetText("3:45"); battleResFrame.mainText:SetTextColor(1, 1, 1, 1)
    battleResFrame.subText:SetText(""); battleResFrame.cooldown:SetCooldown(0, 0)

    -- 블러드 테스트
    if self.db.showLust ~= false and lustFrame then
        lustFrame:Show()
        lustFrame.icon:SetTexture(136012); lustFrame.icon:SetDesaturated(true)
        lustFrame.chargeText:SetText("")
        lustFrame.mainText:SetText("8:45"); lustFrame.mainText:SetTextColor(1, 0.2, 0.2, 1)
        lustFrame.subText:SetText("")
        lustFrame.cooldown:SetCooldown(GetTime() - 75, 600)
    end

    -- 힐러 테스트
    local testHealers = {
        {class = "PRIEST", name = "Priest", mana = 85},
        {class = "DRUID", name = "Druid", mana = 42},
    }

    local targetFrames = separateMode and separateHealerFrames or healerFrames
    for _, frame in ipairs(healerFrames) do frame:Hide() end
    for _, frame in ipairs(separateHealerFrames) do frame:Hide() end
    if separateMode and manaFrame then manaFrame:Show() end

    for i, healer in ipairs(testHealers) do
        local frame = targetFrames[i]
        if frame then
            frame:ClearAllPoints()
            if separateMode then
                if i == 1 then frame:SetPoint("TOPLEFT", manaFrame, "TOPLEFT", 0, 0)
                else frame:SetPoint("TOPLEFT", targetFrames[i-1], "BOTTOMLEFT", 0, -5) end
            else
                if i == 1 then
                    local lastFrame = (self.db.showLust ~= false and lustFrame) and lustFrame or battleResFrame
                    frame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -5)
                else frame:SetPoint("TOPLEFT", targetFrames[i-1], "BOTTOMLEFT", 0, -5) end
            end
            frame.icon:SetTexture(HEALER_CLASS_ICONS[healer.class]); frame.icon:SetDesaturated(false)
            frame.chargeText:SetText("")
            frame.manaBar:SetMinMaxValues(0, 100); frame.manaBar:SetValue(healer.mana)
            frame.manaBar:SetStatusBarColor(0, 0.5, 1, 1); frame.manaBarBorder:Show()
            frame.manaText:SetText(healer.mana .. "%")
            if healer.mana <= 30 then frame.manaText:SetTextColor(1, 0.3, 0.3, 1)
            elseif healer.mana <= 60 then frame.manaText:SetTextColor(1, 1, 0.3, 1)
            else frame.manaText:SetTextColor(1, 1, 1, 1) end
            frame.mainText:SetText("")
            frame.subText:SetText(healer.name)
            if CLASS_COLORS[healer.class] then frame.subText:SetTextColor(unpack(CLASS_COLORS[healer.class])) end
            frame.cooldown:SetCooldown(0, 0)
            frame:Show()
        end
    end

    print(CHAT_PREFIX .. (L["PARTYTRACKER_TEST_START"] or "테스트 모드 시작"))
end

------------------------------------------------------------
-- 이벤트 프레임
------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not isEnabled and ns.db and ns.db.profile and ns.db.profile.modules and ns.db.profile.modules.PartyTracker then
            PartyTracker:OnEnable()
        end
    end
    if not isEnabled then return end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if not mainFrame then PartyTracker:CreateMainFrame() end
        if not updateTicker then PartyTracker:StartUpdate() end
        PartyTracker:UpdateVisibility()
    end
end)

-- 편집 모드 연동 (Movers)
function PartyTracker:EnterEditPreview()
    if isTestMode then return end
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.PartyTracker then
            self.db = ns.db.profile.PartyTracker
        else return end
    end
    local separateMode = self.db.separateManaFrame
    isTestMode = true
    if not mainFrame then self:CreateMainFrame() end
    if separateMode and not manaFrame then self:CreateSeparateManaFrame() end
    if updateTicker then updateTicker:Cancel(); updateTicker = nil end
    mainFrame:Show()
    -- 전투 부활
    battleResFrame:Show()
    battleResFrame.icon:SetTexture(136080); battleResFrame.icon:SetDesaturated(false)
    battleResFrame.chargeText:SetText("1"); battleResFrame.chargeText:SetTextColor(0, 1, 0, 1)
    battleResFrame.mainText:SetText("3:45"); battleResFrame.mainText:SetTextColor(1, 1, 1, 1)
    battleResFrame.subText:SetText(""); battleResFrame.cooldown:SetCooldown(0, 0)
    -- 블러드
    if self.db.showLust ~= false and lustFrame then
        lustFrame:Show()
        lustFrame.icon:SetTexture(136012); lustFrame.icon:SetDesaturated(true)
        lustFrame.chargeText:SetText("")
        lustFrame.mainText:SetText("8:45"); lustFrame.mainText:SetTextColor(1, 0.2, 0.2, 1)
        lustFrame.subText:SetText("")
        lustFrame.cooldown:SetCooldown(GetTime() - 75, 600)
    end
    -- 힐러
    local testHealers = { {class="PRIEST", name="Priest", mana=85}, {class="DRUID", name="Druid", mana=42} }
    local targetFrames = separateMode and separateHealerFrames or healerFrames
    for _, frame in ipairs(healerFrames) do frame:Hide() end
    for _, frame in ipairs(separateHealerFrames) do frame:Hide() end
    if separateMode and manaFrame then manaFrame:Show() end
    for i, healer in ipairs(testHealers) do
        local frame = targetFrames[i]
        if frame then
            frame:ClearAllPoints()
            if separateMode then
                if i == 1 then frame:SetPoint("TOPLEFT", manaFrame, "TOPLEFT", 0, 0)
                else frame:SetPoint("TOPLEFT", targetFrames[i-1], "BOTTOMLEFT", 0, -5) end
            else
                if i == 1 then
                    local lastFrame = (self.db.showLust ~= false and lustFrame) and lustFrame or battleResFrame
                    frame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -5)
                else frame:SetPoint("TOPLEFT", targetFrames[i-1], "BOTTOMLEFT", 0, -5) end
            end
            frame.icon:SetTexture(HEALER_CLASS_ICONS[healer.class]); frame.icon:SetDesaturated(false)
            frame.chargeText:SetText("")
            frame.manaBar:SetMinMaxValues(0, 100); frame.manaBar:SetValue(healer.mana)
            frame.manaBar:SetStatusBarColor(0, 0.5, 1, 1); frame.manaBarBorder:Show()
            frame.manaText:SetText(healer.mana .. "%")
            if healer.mana <= 30 then frame.manaText:SetTextColor(1, 0.3, 0.3, 1)
            elseif healer.mana <= 60 then frame.manaText:SetTextColor(1, 1, 0.3, 1)
            else frame.manaText:SetTextColor(1, 1, 1, 1) end
            frame.mainText:SetText("")
            frame.subText:SetText(healer.name)
            if CLASS_COLORS[healer.class] then frame.subText:SetTextColor(unpack(CLASS_COLORS[healer.class])) end
            frame.cooldown:SetCooldown(0, 0)
            frame:Show()
        end
    end
end

function PartyTracker:ExitEditPreview()
    if not isTestMode then return end
    isTestMode = false
    if mainFrame then mainFrame:Hide() end
    if manaFrame then manaFrame:Hide() end
    if battleResFrame then
        battleResFrame.chargeText:SetText(""); battleResFrame.mainText:SetText(""); battleResFrame.subText:SetText("")
    end
    if lustFrame then
        lustFrame.chargeText:SetText(""); lustFrame.mainText:SetText(""); lustFrame.subText:SetText("")
    end
    for _, frame in ipairs(healerFrames) do
        frame:Hide(); frame.chargeText:SetText(""); frame.mainText:SetText(""); frame.subText:SetText("")
    end
    for _, frame in ipairs(separateHealerFrames) do
        frame:Hide(); frame.chargeText:SetText(""); frame.mainText:SetText(""); frame.subText:SetText("")
    end
    self:StartUpdate()
    if IsInGroup() then self:UpdateVisibility() end
end

------------------------------------------------------------
-- 모듈 등록
------------------------------------------------------------
DDingQoC:RegisterModule("PartyTracker", PartyTracker)
