--[[
    DDingQoC - MissingBuff Module
    클래스 버프 / 소모품 / 펫 / 자세 누락 감지 및 알림
    모든 누락 항목을 동시에 아이콘으로 표시
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: "
local LCG = LibStub("LibCustomGlow-1.0", true)

------------------------------------------------------------
-- Module table
------------------------------------------------------------
local MissingBuff = {}
MissingBuff.name = "MissingBuff"
ns.MissingBuff = MissingBuff

-- 로컬 상태
local mainFrame = nil
local eventFrame = nil
local iconSlots = {}
local MAX_SLOTS = 10
local isEnabled = false
local isTestMode = false
local checkThrottle = 0.25
local lastCheckTime = 0
local throttlePending = false
local playerClass = nil
local currentSpecId = nil

------------------------------------------------------------
-- 버프 데이터
------------------------------------------------------------

local CLASS_BUFF_MAP = {
    MAGE    = { spellId = 1459,   name = "Arcane Intellect" },
    PRIEST  = { spellId = 21562,  name = "Power Word: Fortitude" },
    WARRIOR = { spellId = 6673,   name = "Battle Shout" },
    DRUID   = { spellId = 1126,   name = "Mark of the Wild" },
    EVOKER  = { spellId = 381748, name = "Blessing of the Bronze",
                extra = {381732, 381741, 381746, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758, 442744, 432658, 432652, 432655} },
    SHAMAN  = { spellId = 462854, name = "Skyfury" },
}

local FLASK_SPELLS = {
    [432021] = true, [431971] = true, [431972] = true, [431973] = true,
    [431974] = true, [1235057] = true, [1235110] = true, [1235111] = true,
}

local WELL_FED_NAME = C_Spell.GetSpellName(19705) or "Well Fed"
local HEARTY_WELL_FED_NAME = C_Spell.GetSpellName(462187) or "Hearty Well Fed"

local WEAPON_IGNORE_MAIN = {
    [7144] = true, [7143] = true, [6498] = true, [5400] = true, [5401] = true,
}
local WEAPON_IGNORE_OFF = {
    [5400] = true, [7587] = true, [7528] = true,
}

local PET_DATA = {
    HUNTER      = { missing = 883,  dead = 982, specIgnore = {[254] = true} },
    WARLOCK     = { missing = 688,  dead = nil, sacrificeSpec = {[265] = true, [267] = true}, sacrificeSpell = 108503 },
    DEATHKNIGHT = { missing = 46584, dead = nil, specOnly = {[252] = true} },
    MAGE        = { missing = 31687, dead = nil, specOnly = {[64] = true}, needsSpell = 31687 },
}

local STANCE_DATA = {
    WARRIOR = {
        { spellId = 386164, name = "Battle Stance" },
        { spellId = 386196, name = "Berserker Stance" },
        { spellId = 386208, name = "Defensive Stance", default = true },
    },
    PALADIN = {
        { spellId = 465,    name = "Devotion Aura", default = true },
        { spellId = 317920, name = "Concentration Aura" },
        { spellId = 32223,  name = "Crusader Aura" },
        { spellId = 210323, name = "Retribution Aura" },
    },
}

local ROGUE_LETHAL = {
    { spellId = 381664 }, { spellId = 2823 },
    { spellId = 315584 }, { spellId = 8679 },
}
local ROGUE_NON_LETHAL = {
    { spellId = 381637 }, { spellId = 5761 }, { spellId = 3408 },
}

------------------------------------------------------------
-- 유틸리티
------------------------------------------------------------

local function safeValue(val)
    if issecretvalue and issecretvalue(val) then return nil end
    return val
end

local function GetSpellIcon(spellId)
    if not spellId then return 136235 end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
    if ok and info then return info.iconID or 136235 end
    local ok2, tex = pcall(C_Spell.GetSpellTexture, spellId)
    if ok2 and tex then return tex end
    return 136235
end

local function ScanPlayerAuras()
    local result = { hasBuff = {}, hasSecretIssues = false }
    local consecutiveNil = 0

    for i = 1, 80 do
        local auraData = nil
        local ok, err = pcall(function()
            auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        end)

        if not ok then
            result.hasSecretIssues = true
            consecutiveNil = 0
        elseif not auraData then
            consecutiveNil = consecutiveNil + 1
            if consecutiveNil >= 3 then break end
        else
            consecutiveNil = 0
            local spellId, auraName
            pcall(function() spellId = auraData.spellId end)
            pcall(function() auraName = auraData.name end)
            spellId = safeValue(spellId)
            auraName = safeValue(auraName)

            if spellId then result.hasBuff[spellId] = true end
            if auraName then result.hasBuff[auraName] = true end
            if not spellId and not auraName then result.hasSecretIssues = true end
        end
    end
    return result
end

------------------------------------------------------------
-- 초기화 / 활성화
------------------------------------------------------------

function MissingBuff:OnInitialize()
    self.db = ns.db.profile.MissingBuff
end

function MissingBuff:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.MissingBuff then
            self.db = ns.db.profile.MissingBuff
        else
            return
        end
    end

    local _, classToken = UnitClass("player")
    playerClass = classToken
    local spec = GetSpecialization()
    if spec then currentSpecId = GetSpecializationInfo(spec) end

    isEnabled = true
    self:CreateMainFrame()
    self:RegisterEvents()

    C_Timer.After(3, function()
        if isEnabled then MissingBuff:DoCheck() end
    end)

    print(CHAT_PREFIX .. "|cff40e0d0MissingBuff|r 모듈 활성화됨 (클래스: |cffffd100" .. (playerClass or "?") .. "|r)")
end

function MissingBuff:OnDisable()
    isEnabled = false
    if mainFrame then mainFrame:Hide() end
    if eventFrame then eventFrame:UnregisterAllEvents() end
end

------------------------------------------------------------
-- 아이콘 슬롯 생성/관리
------------------------------------------------------------

local function CreateIconSlot(parent, index)
    local iconSz = MissingBuff.db and MissingBuff.db.iconSize or 40
    local borderSz = MissingBuff.db and MissingBuff.db.iconBorder or 1
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(iconSz + 4, iconSz + 18)

    -- 아이콘 프레임 (테두리 + 글로우 대상)
    slot.iconFrame = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    slot.iconFrame:SetPoint("TOP", 0, -2)
    slot.iconFrame:SetSize(iconSz + borderSz * 2, iconSz + borderSz * 2)
    slot.iconFrame:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = borderSz })
    slot.iconFrame:SetBackdropColor(0, 0, 0, 0)
    slot.iconFrame:SetBackdropBorderColor(0, 0, 0, 1)

    -- 아이콘 텍스쳐 (iconFrame 안)
    slot.icon = slot.iconFrame:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", borderSz, -borderSz)
    slot.icon:SetPoint("BOTTOMRIGHT", -borderSz, borderSz)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    slot.text = slot:CreateFontString(nil, "OVERLAY")
    local font = (MissingBuff.db and MissingBuff.db.font) or SL_FONT
    local fontSize = (MissingBuff.db and MissingBuff.db.fontSize) or 10
    slot.text:SetFont(font, fontSize, "OUTLINE")
    slot.text:SetPoint("TOP", slot.iconFrame, "BOTTOM", 0, -2)
    slot.text:SetJustifyH("CENTER")
    local c = (MissingBuff.db and MissingBuff.db.textColor) or { r = 1, g = 0.3, b = 0.3 }
    slot.text:SetTextColor(c.r, c.g, c.b, 1)

    slot:Hide()
    return slot
end

------------------------------------------------------------
-- 메인 프레임 생성 (컨테이너)
------------------------------------------------------------

function MissingBuff:CreateMainFrame()
    if mainFrame then return end

    local pos = self.db.position or {}
    local f = CreateFrame("Frame", "DDingQoC_MissingBuffFrame", UIParent, "BackdropTemplate")
    f:SetSize(48, 64)
    f:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -150)
    f:SetFrameStrata("HIGH")
    f:SetScale(self.db.scale or 1.0)
    f:Hide()

    f:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1 })
    local bgAlpha = self.db.bgAlpha or 0.6
    f:SetBackdropColor(0, 0, 0, bgAlpha)
    local borderAlpha = bgAlpha > 0.05 and math.min(bgAlpha * 1.3, 0.8) or 0
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, borderAlpha)

    -- 드래그
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not MissingBuff.db.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        MissingBuff.db.position.point = point
        MissingBuff.db.position.relativePoint = relativePoint
        MissingBuff.db.position.x = x
        MissingBuff.db.position.y = y
    end)

    -- 펄스 애니메이션
    f.animGroup = f:CreateAnimationGroup()
    local fadeIn = f.animGroup:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.4); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.6); fadeIn:SetOrder(1)
    local fadeOut = f.animGroup:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0.4); fadeOut:SetDuration(0.6); fadeOut:SetOrder(2)
    f.animGroup:SetLooping("REPEAT")

    mainFrame = f

    -- 아이콘 슬롯 풀 미리 생성
    for i = 1, MAX_SLOTS do
        iconSlots[i] = CreateIconSlot(f, i)
    end
end

------------------------------------------------------------
-- 이벤트 등록
------------------------------------------------------------

function MissingBuff:RegisterEvents()
    if not eventFrame then eventFrame = CreateFrame("Frame") end

    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterEvent("PLAYER_UNGHOST")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterEvent("SCENARIO_UPDATE")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")

    eventFrame:SetScript("OnEvent", function(_, event, arg1, ...)
        if not isEnabled then return end
        if event == "UNIT_AURA" then
            if arg1 == "player" then MissingBuff:ThrottledCheck() end
        elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
            or event == "SCENARIO_UPDATE" or event == "CHALLENGE_MODE_START" then
            MissingBuff:ThrottledCheck()
            C_Timer.After(2, function() if isEnabled then MissingBuff:DoCheck() end end)
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
            MissingBuff:ThrottledCheck()
        elseif event == "PLAYER_REGEN_DISABLED" then
            if MissingBuff.db and MissingBuff.db.hideInCombat then
                if mainFrame then mainFrame:Hide() end
            else MissingBuff:ThrottledCheck() end
        elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
            MissingBuff:ThrottledCheck()
        elseif event == "UPDATE_SHAPESHIFT_FORM" then
            C_Timer.After(0.3, function() if isEnabled then MissingBuff:ThrottledCheck() end end)
        elseif event == "UNIT_INVENTORY_CHANGED" then
            if arg1 == "player" then MissingBuff:ThrottledCheck() end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            if arg1 == "player" then
                local spec = GetSpecialization()
                if spec then currentSpecId = GetSpecializationInfo(spec) end
                C_Timer.After(1, function() if isEnabled then MissingBuff:ThrottledCheck() end end)
            end
        elseif event == "UNIT_PET" then
            if arg1 == "player" then
                C_Timer.After(0.5, function() if isEnabled then MissingBuff:ThrottledCheck() end end)
            end
        end
    end)
end

------------------------------------------------------------
-- 쓰로틀 체크
------------------------------------------------------------

function MissingBuff:ThrottledCheck()
    local now = GetTime()
    if now - lastCheckTime < checkThrottle then
        if not throttlePending then
            throttlePending = true
            C_Timer.After(checkThrottle, function()
                throttlePending = false
                if isEnabled then MissingBuff:DoCheck() end
            end)
        end
        return
    end
    self:DoCheck()
end

------------------------------------------------------------
-- 핵심 체크 로직 (모든 누락 항목 수집)
------------------------------------------------------------

function MissingBuff:DoCheck()
    if not isEnabled or not mainFrame then return end
    if isTestMode then return end
    lastCheckTime = GetTime()

    if UnitIsDeadOrGhost("player") then self:HideAll(); return end
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then self:HideAll(); return end
    if self.db.ignoreWhileMounted and (IsMounted() or UnitOnTaxi("player") or UnitInVehicle("player") or UnitHasVehicleUI("player")) then self:HideAll(); return end
    if self.db.hideInCombat and InCombatLockdown() then self:HideAll(); return end
    if self.db.ignoreWhileResting and IsResting and IsResting() then self:HideAll(); return end
    if not self:ShouldCheckInZone() then self:HideAll(); return end

    local auras = ScanPlayerAuras()

    if auras.hasSecretIssues then
        local hasAnyBuff = false
        for _ in pairs(auras.hasBuff) do hasAnyBuff = true; break end
        if not hasAnyBuff then self:HideAll(); return end
    end

    local missingList = {}
    local inCombat = InCombatLockdown()

    -- 1. 태세/오라
    if self.db.checkStance then
        local r = self:CheckStance()
        if r then missingList[#missingList + 1] = r end
    end

    -- 2. 클래스 버프
    if self.db.checkClassBuff and not inCombat then
        local r = self:CheckClassBuff(auras)
        if r then missingList[#missingList + 1] = r end
    end

    -- 3. 도적 독 (치명독 + 비치명독 각각)
    if self.db.checkRoguePoisons and playerClass == "ROGUE" and not inCombat then
        local results = self:CheckRoguePoisonsAll(auras)
        if results then
            for _, r in ipairs(results) do missingList[#missingList + 1] = r end
        end
    end

    -- 4. 펫
    if self.db.checkPet then
        local r = self:CheckPet()
        if r then missingList[#missingList + 1] = r end
    end

    -- 5. 플라스크
    if self.db.checkFlask and not inCombat then
        local r = self:CheckFlask(auras)
        if r then missingList[#missingList + 1] = r end
    end

    -- 6. 음식
    if self.db.checkFood and not inCombat then
        local r = self:CheckFood(auras)
        if r then missingList[#missingList + 1] = r end
    end

    -- 7. 무기 기름 (주무기 + 보조무기 각각)
    if self.db.checkWeaponOil and not inCombat then
        local results = self:CheckWeaponOilAll()
        if results then
            for _, r in ipairs(results) do missingList[#missingList + 1] = r end
        end
    end

    if #missingList > 0 then
        self:ShowMissingList(missingList)
    else
        self:HideAll()
    end
end

------------------------------------------------------------
-- 존 조건 체크
------------------------------------------------------------

function MissingBuff:ShouldCheckInZone()
    local inInstance, instanceType = IsInInstance()
    local zoneCheck = self.db.zoneCheck or "always"
    if zoneCheck == "always" then return true
    elseif zoneCheck == "instance" then
        return inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario")
    elseif zoneCheck == "group" then return IsInGroup() or IsInRaid()
    elseif zoneCheck == "instanceOrGroup" then
        return (IsInGroup() or IsInRaid()) or (inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario"))
    end
    return true
end

------------------------------------------------------------
-- 개별 체크 함수들
------------------------------------------------------------

function MissingBuff:CheckClassBuff(auras)
    local data = CLASS_BUFF_MAP[playerClass]
    if not data then return nil end
    if auras.hasBuff[data.spellId] then return nil end
    if data.extra then
        for _, id in ipairs(data.extra) do
            if auras.hasBuff[id] then return nil end
        end
    end
    return { icon = GetSpellIcon(data.spellId), text = "버프 누락" }
end

function MissingBuff:CheckFlask(auras)
    for spellId in pairs(FLASK_SPELLS) do
        if auras.hasBuff[spellId] then return nil end
    end
    return { icon = GetSpellIcon(432021), text = "영약 없음" }
end

function MissingBuff:CheckFood(auras)
    if auras.hasBuff[WELL_FED_NAME] or auras.hasBuff[HEARTY_WELL_FED_NAME] then return nil end
    return { icon = 133943, text = "음식 없음" }
end

--- 무기 오일 체크 (주무기 + 보조무기 전부 반환)
function MissingBuff:CheckWeaponOilAll()
    local ok, hasMain, mainExp, _, mainId, hasOff, offExp, _, offId = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    hasMain = safeValue(hasMain)
    mainId = safeValue(mainId)
    hasOff = safeValue(hasOff)
    offId = safeValue(offId)
    if hasMain == nil then return nil end

    local results = {}

    if not hasMain then
        local mainWeapon = GetInventoryItemID("player", 16)
        if mainWeapon and not WEAPON_IGNORE_MAIN[mainId or 0] then
            results[#results + 1] = { icon = 609892, text = "주무기 기름" }
        end
    end

    if not hasOff then
        local itemID = GetInventoryItemID("player", 17)
        if itemID then
            local ok2, classID = pcall(function()
                return select(6, C_Item.GetItemInfoInstant(itemID))
            end)
            if ok2 and classID == Enum.ItemClass.Weapon and not WEAPON_IGNORE_OFF[offId or 0] then
                results[#results + 1] = { icon = 609892, text = "보조무기 기름" }
            end
        end
    end

    return #results > 0 and results or nil
end

function MissingBuff:CheckStance()
    local stances = STANCE_DATA[playerClass]
    if not stances then return nil end
    local hasLearnedAny = false
    for _, stance in ipairs(stances) do
        local ok, known = pcall(C_SpellBook.IsSpellKnown, stance.spellId)
        if ok and known then hasLearnedAny = true; stance._learned = true
        else stance._learned = false end
    end
    if not hasLearnedAny then return nil end
    local formIdx = GetShapeshiftForm()
    if formIdx and formIdx > 0 then return nil end
    for _, stance in ipairs(stances) do
        if stance.default and stance._learned then
            return { icon = GetSpellIcon(stance.spellId), text = "태세 사용" }
        end
    end
    for _, stance in ipairs(stances) do
        if stance._learned then
            return { icon = GetSpellIcon(stance.spellId), text = "태세 사용" }
        end
    end
    return nil
end

--- 도적 독 체크 (치명독 + 비치명독 각각 반환)
function MissingBuff:CheckRoguePoisonsAll(auras)
    local results = {}

    local hasLethal = false
    for _, p in ipairs(ROGUE_LETHAL) do
        if auras.hasBuff[p.spellId] then hasLethal = true; break end
    end
    if not hasLethal then
        results[#results + 1] = { icon = GetSpellIcon(315584), text = "치명독" }
    end

    local hasNonLethal = false
    for _, p in ipairs(ROGUE_NON_LETHAL) do
        if auras.hasBuff[p.spellId] then hasNonLethal = true; break end
    end
    if not hasNonLethal then
        results[#results + 1] = { icon = GetSpellIcon(3408), text = "비치명독" }
    end

    return #results > 0 and results or nil
end

function MissingBuff:CheckPet()
    local petInfo = PET_DATA[playerClass]
    if not petInfo then return nil end
    if petInfo.specOnly and not petInfo.specOnly[currentSpecId] then return nil end
    if petInfo.specIgnore and petInfo.specIgnore[currentSpecId] then return nil end
    if petInfo.sacrificeSpec and petInfo.sacrificeSpec[currentSpecId] then
        if petInfo.sacrificeSpell then
            local ok, known = pcall(C_SpellBook.IsSpellKnown, petInfo.sacrificeSpell)
            if ok and known then return nil end
        end
    end
    if petInfo.needsSpell then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, petInfo.needsSpell)
        if not ok or not known then return nil end
    end
    if IsMounted() or UnitOnTaxi("player") or UnitInVehicle("player") then return nil end

    if UnitExists("pet") then
        if UnitIsDead("pet") then
            return { icon = GetSpellIcon(petInfo.dead or petInfo.missing), text = "펫 부활" }
        end
        return nil
    else
        return { icon = GetSpellIcon(petInfo.missing), text = "펫 소환" }
    end
end

------------------------------------------------------------
-- 다중 아이콘 표시 (가로 배치)
------------------------------------------------------------

function MissingBuff:ShowMissingList(list)
    if not mainFrame then return end

    local iconSz = self.db.iconSize or 40
    local borderSz = self.db.iconBorder or 1
    local gap = 4
    local showText = self.db.showText
    local frameSz = iconSz + borderSz * 2
    local slotW = frameSz + 4
    local slotH = frameSz + (showText and 18 or 4)
    local count = math.min(#list, MAX_SLOTS)

    -- 아이콘 슬롯 업데이트
    for i = 1, MAX_SLOTS do
        local slot = iconSlots[i]
        if not slot then break end

        if i <= count then
            local item = list[i]
            slot.icon:SetTexture(item.icon)

            -- iconFrame 크기 업데이트
            if slot.iconFrame then
                slot.iconFrame:SetSize(frameSz, frameSz)
                slot.iconFrame:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = math.max(borderSz, 0.5) })
                slot.iconFrame:SetBackdropColor(0, 0, 0, 0)
                slot.iconFrame:SetBackdropBorderColor(0, 0, 0, borderSz > 0 and 1 or 0)
                slot.icon:ClearAllPoints()
                slot.icon:SetPoint("TOPLEFT", borderSz, -borderSz)
                slot.icon:SetPoint("BOTTOMRIGHT", -borderSz, borderSz)
            end

            if showText then
                slot.text:SetText(item.text or "")
                slot.text:Show()
            else
                slot.text:Hide()
            end

            -- 폰트 업데이트
            local font = self.db.font or SL_FONT
            local fontSize = self.db.fontSize or 10
            slot.text:SetFont(font, fontSize, "OUTLINE")
            local c = self.db.textColor or { r = 1, g = 0.3, b = 0.3 }
            slot.text:SetTextColor(c.r, c.g, c.b, 1)

            slot:SetSize(slotW, slotH)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4 + (i - 1) * (slotW + gap), -4)
            slot:Show()

            -- 글로우 적용 (아이콘에만)
            self:ApplyGlow(slot)
        else
            self:StopGlow(slot)
            slot:Hide()
        end
    end

    -- 컨테이너 크기
    local totalW = count * slotW + (count - 1) * gap + 8
    local totalH = slotH + 8
    mainFrame:SetSize(totalW, totalH)

    mainFrame:Show()

    if self.db.pulseAnimation and not mainFrame.animGroup:IsPlaying() then
        mainFrame.animGroup:Play()
    elseif not self.db.pulseAnimation and mainFrame.animGroup:IsPlaying() then
        mainFrame.animGroup:Stop()
        mainFrame:SetAlpha(1)
    end
end

function MissingBuff:HideAll()
    if not mainFrame then return end
    mainFrame:Hide()
    if mainFrame.animGroup:IsPlaying() then
        mainFrame.animGroup:Stop()
        mainFrame:SetAlpha(1)
    end
    for i = 1, MAX_SLOTS do
        if iconSlots[i] then
            self:StopGlow(iconSlots[i])
            iconSlots[i]:Hide()
        end
    end
end

------------------------------------------------------------
-- 글로우 적용/해제 (LibCustomGlow)
------------------------------------------------------------

function MissingBuff:ApplyGlow(slot)
    if not LCG or not slot.iconFrame then return end
    -- 먼저 기존 글로우 제거
    self:StopGlow(slot)

    local glowType = self.db.glowType or "pixel"
    if glowType == "none" then return end

    local gc = self.db.glowColor or { r = 0.95, g = 0.2, b = 0.2 }
    local color = { gc.r, gc.g, gc.b, 1 }
    local speed = self.db.glowSpeed or 0.25
    local target = slot.iconFrame

    if glowType == "pixel" then
        local lines = self.db.glowLines or 8
        local thickness = self.db.glowThickness or 2
        LCG.PixelGlow_Start(target, color, lines, speed, nil, thickness, 0, 0, false, "MB")
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(target, color, 4, speed, 1, 0, 0, "MB")
    elseif glowType == "button" then
        LCG.ButtonGlow_Start(target, color, speed)
    end
end

function MissingBuff:StopGlow(slot)
    if not LCG or not slot.iconFrame then return end
    local target = slot.iconFrame
    pcall(LCG.PixelGlow_Stop, target, "MB")
    pcall(LCG.AutoCastGlow_Stop, target, "MB")
    pcall(LCG.ButtonGlow_Stop, target)
end

------------------------------------------------------------
-- 테스트 모드
------------------------------------------------------------

function MissingBuff:TestMode()
    if not mainFrame then self:CreateMainFrame() end

    isTestMode = not isTestMode
    if isTestMode then
        -- 활성화된 설정에 따라 가능한 모든 누락 항목 표시
        local testList = {}
        if self.db.checkStance then
            testList[#testList + 1] = { icon = GetSpellIcon(386164), text = "태세 사용" }
        end
        if self.db.checkClassBuff then
            local data = CLASS_BUFF_MAP[playerClass]
            local spId = data and data.spellId or 1459
            testList[#testList + 1] = { icon = GetSpellIcon(spId), text = "버프 누락" }
        end
        if self.db.checkRoguePoisons then
            testList[#testList + 1] = { icon = GetSpellIcon(315584), text = "치명독" }
            testList[#testList + 1] = { icon = GetSpellIcon(3408), text = "비치명독" }
        end
        if self.db.checkPet then
            local petInfo = PET_DATA[playerClass]
            local spId = petInfo and petInfo.missing or 883
            testList[#testList + 1] = { icon = GetSpellIcon(spId), text = "펫 소환" }
        end
        if self.db.checkFlask then
            testList[#testList + 1] = { icon = GetSpellIcon(432021), text = "영약 없음" }
        end
        if self.db.checkFood then
            testList[#testList + 1] = { icon = 133943, text = "음식 없음" }
        end
        if self.db.checkWeaponOil then
            testList[#testList + 1] = { icon = 609892, text = "주무기 기름" }
            testList[#testList + 1] = { icon = 609892, text = "보조무기 기름" }
        end
        -- 아무것도 없으면 기본 표시
        if #testList == 0 then
            testList = {
                { icon = GetSpellIcon(1459), text = "버프 누락" },
                { icon = GetSpellIcon(432021), text = "영약 없음" },
                { icon = 133943, text = "음식 없음" },
            }
        end
        self:ShowMissingList(testList)
        print(CHAT_PREFIX .. "Missing Buff 테스트 |cff00ff00ON|r (" .. #testList .. "개 표시)")
    else
        isTestMode = false
        self:HideAll()
        print(CHAT_PREFIX .. "Missing Buff 테스트 |cffff0000OFF|r")
        C_Timer.After(0.1, function()
            if isEnabled then MissingBuff:DoCheck() end
        end)
    end
end

function MissingBuff:IsTestMode()
    return isTestMode
end

------------------------------------------------------------
-- 설정 업데이트
------------------------------------------------------------

function MissingBuff:UpdateVisuals()
    if not mainFrame then return end

    local bgAlpha = self.db.bgAlpha or 0.6
    mainFrame:SetBackdropColor(0, 0, 0, bgAlpha)
    local borderAlpha = bgAlpha > 0.05 and math.min(bgAlpha * 1.3, 0.8) or 0
    mainFrame:SetBackdropBorderColor(0.15, 0.15, 0.15, borderAlpha)

    mainFrame:SetScale(self.db.scale or 1.0)

    -- 슬롯들 업데이트
    local iconSz = self.db.iconSize or 40
    local font = self.db.font or SL_FONT
    local fontSize = self.db.fontSize or 10
    local c = self.db.textColor or { r = 1, g = 0.3, b = 0.3 }
    local borderSz = self.db.iconBorder or 1

    for i = 1, MAX_SLOTS do
        local slot = iconSlots[i]
        if slot then
            -- 아이콘 프레임 + 테두리 업데이트
            if slot.iconFrame then
                slot.iconFrame:SetSize(iconSz + borderSz * 2, iconSz + borderSz * 2)
                slot.iconFrame:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = math.max(borderSz, 0.5) })
                slot.iconFrame:SetBackdropColor(0, 0, 0, 0)
                slot.iconFrame:SetBackdropBorderColor(0, 0, 0, borderSz > 0 and 1 or 0)
                slot.icon:ClearAllPoints()
                slot.icon:SetPoint("TOPLEFT", borderSz, -borderSz)
                slot.icon:SetPoint("BOTTOMRIGHT", -borderSz, borderSz)
            end

            slot.text:SetFont(font, fontSize, "OUTLINE")
            slot.text:SetTextColor(c.r, c.g, c.b, 1)
            if self.db.showText then slot.text:Show() else slot.text:Hide() end

            -- 글로우 재적용 (표시 중인 슬롯만)
            if slot:IsShown() then
                self:ApplyGlow(slot)
            end
        end
    end

    -- 펄스 애니메이션
    if self.db.pulseAnimation and mainFrame:IsShown() and not mainFrame.animGroup:IsPlaying() then
        mainFrame.animGroup:Play()
    elseif not self.db.pulseAnimation and mainFrame.animGroup:IsPlaying() then
        mainFrame.animGroup:Stop()
        mainFrame:SetAlpha(1)
    end

    -- 즉시 재체크
    if isEnabled and mainFrame:IsShown() then
        C_Timer.After(0.05, function()
            if isEnabled then MissingBuff:DoCheck() end
        end)
    end
end

function MissingBuff:ResetPosition()
    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        self.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 }
        print(CHAT_PREFIX .. "Missing Buff 위치 초기화됨")
    end
end

------------------------------------------------------------
-- 모듈 등록
------------------------------------------------------------
DDingToolKit:RegisterModule("MissingBuff", MissingBuff)
