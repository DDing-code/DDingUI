--[[
    DDingQoC - BuffChecker Module (Unified Edition)
    개인 소모품(음식/영약/무기/룬), 직업 시너지, 소환수/태세 누락 시 아이콘으로 알려주는 통합 모듈
]]

local addonName, ns = ...
local DDingQoC = ns.DDingQoC
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: "
local LCG = LibStub("LibCustomGlow-1.0", true)

local BuffChecker = {}
BuffChecker.name = "BuffChecker"
ns.BuffChecker = BuffChecker

local mainFrame, eventFrame = nil, nil
local iconSlots = {}
local MAX_SLOTS = 15
local isEnabled, isTestMode = false, false
local lastCheckTime, checkThrottle = 0, 0.25
local playerClass, currentSpecId = nil, nil
local lastMissingKey = ""
local throttlePending = false

-- =====================================
-- CONSTANTS & DATA TABLES
-- =====================================
local CLASS_BUFF_MAP = {
    MAGE = { spellId = 1459, name = "Arcane Intellect" },
    PRIEST = { spellId = 21562, name = "Power Word: Fortitude" },
    WARRIOR = { spellId = 6673, name = "Battle Shout" },
    DRUID = { spellId = 1126, name = "Mark of the Wild" },
    EVOKER = { spellId = 381748, name = "Blessing of the Bronze", extra = {381732, 381741, 381746, 381749} },
    SHAMAN = { spellId = 462854, name = "Skyfury" },
}

local FLASK_SPELLS = {
    [432021] = true, [431971] = true, [431972] = true, [431973] = true,
    [431974] = true, [1235057] = true, [1235110] = true, [1235111] = true, [1235108] = true
}
local TWW_FLASKS = {
    241322, 241324, 241326, 241320, 212301, 212300, 212299,
    212283, 212282, 212281, 212280, 212279, 212278,
    212277, 212276, 212275, 212274, 212273, 212272,
    212271, 212270, 212269
}

local FOOD_SPELLS = { [19705]=true, [462187]=true }
local TWW_FOODS = {
    224652, 222735, 222732, 222734, 222731, 222733, 222730
}

local TWW_OILS = {
    222718, 222717, 222716, 222721, 222720, 222719,
    224578, 224577, 224576, 224581, 224580, 224579
}
local WEAPON_IGNORE_MAIN = { [7144]=true, [7143]=true, [6498]=true, [5400]=true, [5401]=true }
local WEAPON_IGNORE_OFF = { [5400]=true, [7587]=true, [7528]=true }

local RUNE_SPELLS = { [393438] = true, [454659] = true, [430852] = true }
local TWW_RUNES = { 224572, 211880 }

local PET_DATA = {
    HUNTER      = { missing = 883,  dead = 982, specIgnore = {[254] = true} },
    WARLOCK     = { missing = 688,  dead = nil, sacrificeSpec = {[265] = true, [267] = true}, sacrificeSpell = 108503 },
    DEATHKNIGHT = { missing = 46584, dead = nil, specOnly = {[252] = true} },
    MAGE        = { missing = 31687, dead = nil, specOnly = {[64] = true} },
}

local STANCE_DATA = {
    WARRIOR = { { spellId = 386164 }, { spellId = 386196 }, { spellId = 386208, default = true } },
    PALADIN = { { spellId = 465, default = true }, { spellId = 317920 }, { spellId = 32223 }, { spellId = 210323 } },
}

local ROGUE_LETHAL = { {spellId=381664}, {spellId=2823}, {spellId=315584}, {spellId=8679} }
local ROGUE_NON_LETHAL = { {spellId=381637}, {spellId=5761}, {spellId=3408} }

-- =====================================
-- LIFECYCLE
-- =====================================
function BuffChecker:OnInitialize()
    self.db = ns.db.profile.BuffChecker
end

function BuffChecker:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.BuffChecker then
            self.db = ns.db.profile.BuffChecker
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
        if isEnabled then BuffChecker:DoCheck() end
    end)
    print(CHAT_PREFIX .. "|cff40e0d0BuffChecker(통합)|r 모듈 활성화됨")
end

function BuffChecker:OnDisable()
    isEnabled = false
    if mainFrame then mainFrame:Hide() end
    if eventFrame then eventFrame:UnregisterAllEvents() end
end

function BuffChecker:ResetPosition()
    if not mainFrame then return end
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    if self.db then
        self.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 }
    end
    print(CHAT_PREFIX .. "BuffChecker 위치가 초기화되었습니다.")
end

-- =====================================
-- UTILS
-- =====================================
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

local function GetBestItemFromList(itemList)
    for _, itemID in ipairs(itemList) do
        local count = C_Item.GetItemCount(itemID, false, false)
        if count > 0 then return itemID, count end
    end
    return nil, 0
end

local function ScanPlayerAuras()
    local result = { hasBuff = {}, expiration = {} }
    for i = 1, 80 do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not auraData then break end
        local sid = safeValue(auraData.spellId)
        local name = safeValue(auraData.name)
        if sid then
            result.hasBuff[sid] = true
            result.expiration[sid] = auraData.expirationTime
        end
        if name then
            result.hasBuff[name] = true
            result.expiration[name] = auraData.expirationTime
        end
    end
    return result
end

-- =====================================
-- CHECKS
-- =====================================
function BuffChecker:CheckClassBuff()
    local data = CLASS_BUFF_MAP[playerClass]
    if not data then return nil end
    local ok, known = pcall(C_SpellBook.IsSpellKnown, data.spellId)
    if not ok or not safeValue(known) then return nil end

    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units+1] = "raid"..i end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units+1] = "party"..i end
        units[#units+1] = "player"
    else
        units[#units+1] = "player"
    end

    local missingCount = 0
    for _, u in ipairs(units) do
        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
            -- 페이즈 체크
            local inPhase = true
            if UnitPhaseReason then
                inPhase = (UnitPhaseReason(u) == nil)
            end
            if not inPhase then
                -- 페이즈 다른 유닛은 무시 (누락에 포함X)
            else
                -- 범위 체크 (player 자신은 항상 범위 내)
                local inRange = true
                if u ~= "player" then
                    local okR, rangeVal = pcall(C_Spell.IsSpellInRange, data.spellId, u)
                    if okR then
                        local rv = safeValue(rangeVal)
                        -- TWW: 0=범위밖, 1=범위내, nil=확인불가, false=범위밖, true=범위내
                        if rv == false or rv == 0 then inRange = false end
                    end
                end

                if inRange then
                    -- 버프 확인: spell name으로 빠르게 조회
                    local hasBuff = false
                    -- 메인 버프 확인
                    local okA, aura = pcall(AuraUtil.FindAuraByName, data.name, u, "HELPFUL")
                    if okA and aura then
                        hasBuff = true
                    end
                    -- extra 버프 확인 (기원사 등)
                    if not hasBuff and data.extra then
                        for _, exId in ipairs(data.extra) do
                            local okE, exInfo = pcall(C_Spell.GetSpellInfo, exId)
                            if okE and exInfo and exInfo.name then
                                local okA2, aura2 = pcall(AuraUtil.FindAuraByName, exInfo.name, u, "HELPFUL")
                                if okA2 and aura2 then hasBuff = true; break end
                            end
                        end
                    end
                    if not hasBuff then missingCount = missingCount + 1 end
                end
            end
        end
    end

    if missingCount > 0 then
        local txt = missingCount == 1 and "버프 누락" or ("누락 ("..missingCount..")")
        return { icon = GetSpellIcon(data.spellId), text = txt, spellId = data.spellId, type = "spell" }
    end
    return nil
end

function BuffChecker:CheckThreshold(auras, spellDict)
    local threshold = (self.db.threshold or 5) * 60
    for spellId in pairs(spellDict) do
        if auras.hasBuff[spellId] then
            local expire = auras.expiration[spellId]
            if expire and expire > 0 then
                local remain = expire - GetTime()
                if remain < threshold and remain > 0 then
                    return false
                end
            end
            return true
        end
    end
    return false
end

function BuffChecker:CheckFlask(auras)
    if self:CheckThreshold(auras, FLASK_SPELLS) then return nil end
    local bestId, count = GetBestItemFromList(TWW_FLASKS)
    if bestId then
        local icon = C_Item.GetItemIconByID(bestId)
        return { icon = icon, text = "영약 사용", macroText = "/use item:"..bestId, type = "macro", count = count }
    end
    return { icon = GetSpellIcon(1235057), text = "영약 없음" }
end

function BuffChecker:CheckFood(auras)
    if self:CheckThreshold(auras, FOOD_SPELLS) then return nil end
    local bestId, count = GetBestItemFromList(TWW_FOODS)
    if bestId then
        local icon = C_Item.GetItemIconByID(bestId)
        return { icon = icon, text = "음식 사용", macroText = "/use item:"..bestId, type = "macro", count = count }
    end
    return { icon = GetSpellIcon(19705), text = "음식 없음" }
end

function BuffChecker:CheckRune(auras)
    if self:CheckThreshold(auras, RUNE_SPELLS) then return nil end
    local bestId, count = GetBestItemFromList(TWW_RUNES)
    if bestId then
        local icon = C_Item.GetItemIconByID(bestId)
        return { icon = icon, text = "룬 사용", macroText = "/use item:"..bestId, type = "macro", count = count }
    end
    return { icon = GetSpellIcon(393438), text = "룬 없음" }
end

function BuffChecker:CheckWeaponOil()
    local ok, hasMain, mainExp, _, mainId, hasOff, offExp, _, offId = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    hasMain, mainId = safeValue(hasMain), safeValue(mainId)
    hasOff, offId = safeValue(hasOff), safeValue(offId)
    if hasMain == nil then return nil end

    local results = {}
    local bestId, count = GetBestItemFromList(TWW_OILS)
    local macroText = bestId and ("/use item:"..bestId) or nil
    local icon = bestId and C_Item.GetItemIconByID(bestId) or GetSpellIcon(1237006)

    if not hasMain then
        local mainWeapon = GetInventoryItemID("player", 16)
        if mainWeapon and not WEAPON_IGNORE_MAIN[mainId or 0] then
            results[#results + 1] = { icon = icon, text = "주무기 강화", macroText = macroText, type = macroText and "macro" or nil, count = count }
        end
    end
    if not hasOff then
        local offWeapon = GetInventoryItemID("player", 17)
        if offWeapon then
            local cx = select(6, C_Item.GetItemInfoInstant(offWeapon))
            if cx == Enum.ItemClass.Weapon and not WEAPON_IGNORE_OFF[offId or 0] then
                results[#results + 1] = { icon = icon, text = "보조무기", macroText = macroText, type = macroText and "macro" or nil, count = count }
            end
        end
    end
    return #results > 0 and results or nil
end

function BuffChecker:CheckStance()
    local stances = STANCE_DATA[playerClass]
    if not stances then return nil end
    local hasLearnedAny = false
    for _, stance in ipairs(stances) do
        local ok, known = pcall(C_SpellBook.IsSpellKnown, stance.spellId)
        if ok and known then hasLearnedAny = true; stance._learned = true else stance._learned = false end
    end
    if not hasLearnedAny then return nil end
    local formIdx = GetShapeshiftForm()
    if formIdx and formIdx > 0 then return nil end
    for _, stance in ipairs(stances) do
        if stance.default and stance._learned then
            return { icon = GetSpellIcon(stance.spellId), text = "태세 사용", spellId = stance.spellId, type = "spell" }
        end
    end
    for _, stance in ipairs(stances) do
        if stance._learned then
            return { icon = GetSpellIcon(stance.spellId), text = "태세 사용", spellId = stance.spellId, type = "spell" }
        end
    end
    return nil
end

function BuffChecker:CheckRoguePoisons(auras)
    local results = {}
    local hasLethal, hasNonLethal = false, false
    for _, p in ipairs(ROGUE_LETHAL) do if auras.hasBuff[p.spellId] then hasLethal = true break end end
    for _, p in ipairs(ROGUE_NON_LETHAL) do if auras.hasBuff[p.spellId] then hasNonLethal = true break end end

    if not hasLethal then
        results[#results + 1] = { icon = GetSpellIcon(381664), text = "치명 독", spellId = 381664, type = "spell" }
    end
    if not hasNonLethal then
        results[#results + 1] = { icon = GetSpellIcon(381637), text = "비치명 독", spellId = 381637, type = "spell" }
    end
    return #results > 0 and results or nil
end

function BuffChecker:CheckPet(auras)
    local pdata = PET_DATA[playerClass]
    if not pdata then return nil end
    if pdata.specOnly and not pdata.specOnly[currentSpecId] then return nil end
    if pdata.specIgnore and pdata.specIgnore[currentSpecId] then return nil end
    if pdata.sacrificeSpec and pdata.sacrificeSpec[currentSpecId] and pdata.sacrificeSpell and auras.hasBuff[pdata.sacrificeSpell] then return nil end

    if HasPetUI() or UnitExists("pet") then
        if pdata.dead and UnitIsDeadOrGhost("pet") then
            return { icon = GetSpellIcon(pdata.dead), text = "소환수 부활", spellId = pdata.dead, type = "spell" }
        end
        return nil
    end
    return { icon = GetSpellIcon(pdata.missing), text = "소환수 부재", spellId = pdata.missing, type = "spell" }
end

-- =====================================
-- UI / ENGINE
-- =====================================
local function UpdateGlow(slot, isMissing)
    if not LCG then return end
    if not isMissing then
        LCG.PixelGlow_Stop(slot.iconFrame)
        LCG.AutoCastGlow_Stop(slot.iconFrame)
        LCG.ButtonGlow_Stop(slot.iconFrame)
        return
    end

    local db = BuffChecker.db
    local glowType = db.glowType or "autocast"
    local color = db.glowColor or {r=1, g=1, b=0, a=1}
    local colorArr = {color.r, color.g, color.b, color.a}

    if glowType == "pixel" then
        LCG.PixelGlow_Start(slot.iconFrame, colorArr, 8, 0.25, nil, 2)
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(slot.iconFrame, colorArr, 8, 0.25, 1, 2)
    elseif glowType == "button" then
        LCG.ButtonGlow_Start(slot.iconFrame, colorArr)
    elseif glowType == "none" then
        UpdateGlow(slot, false)
    end
end

function BuffChecker:CreateMainFrame()
    if mainFrame then return end
    mainFrame = CreateFrame("Frame", "DDingQoCBuffCheckerFrame", UIParent)
    mainFrame:SetSize(40, 40)

    -- DB에서 저장된 위치 불러오기
    local pos = self.db and self.db.position
    if pos and pos.point then
        mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -150)
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end

    for i = 1, MAX_SLOTS do
        local slot = CreateFrame("Button", "DDingQoCBuffCheckerSlot"..i, mainFrame, "SecureActionButtonTemplate, BackdropTemplate")
        slot:RegisterForClicks("AnyUp", "AnyDown")
        
        slot.iconFrame = CreateFrame("Frame", nil, slot, "BackdropTemplate")
        slot.iconFrame:SetPoint("TOP", 0, -2)
        slot.iconFrame:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT })
        
        slot.icon = slot.iconFrame:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints()
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        slot.countText = slot.iconFrame:CreateFontString(nil, "OVERLAY")
        slot.countText:SetFont(SL_FONT, 12, "OUTLINE")
        slot.countText:SetPoint("TOPRIGHT", slot.iconFrame, "TOPRIGHT", -2, -2)
        slot.countText:SetTextColor(1, 1, 1)

        slot.text = slot:CreateFontString(nil, "OVERLAY")
        slot.text:SetFont(SL_FONT, 12, "OUTLINE")
        slot.text:SetPoint("TOP", slot.iconFrame, "BOTTOM", 0, -2)
        
        slot:Hide()
        iconSlots[i] = slot
    end
end

function BuffChecker:UpdateVisuals()
    if not mainFrame then return end
    local sz = self.db.iconSize or 40
    local spacing = self.db.iconSpacing or 5
    local scale = self.db.scale or 1.0
    local bgAlpha = self.db.bgAlpha or 1.0
    local showText = (self.db.showText ~= false)

    mainFrame:SetScale(scale)

    for i = 1, MAX_SLOTS do
        local slot = iconSlots[i]
        slot.iconFrame:SetSize(sz, sz)
        slot.iconFrame:SetBackdropColor(0,0,0, bgAlpha)
        slot.iconFrame:SetBackdropBorderColor(0,0,0, bgAlpha > 0 and 1 or 0)
        
        slot.text:SetShown(showText)
        slot.text:SetFont(SL_FONT, 12, "OUTLINE")
        
        if self.db.textColor then
            local c = self.db.textColor
            slot.text:SetTextColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
        end
        
        slot:SetSize(sz, sz + (showText and 18 or 0))
        
        slot:ClearAllPoints()
        if i == 1 then
            slot:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
        else
            slot:SetPoint("LEFT", iconSlots[i-1], "RIGHT", spacing, 0)
        end
        
        if slot:IsShown() then
            UpdateGlow(slot, true)
        end
    end
end

function BuffChecker:ShowMissingList(missingList)
    if self._editPreviewActive then return end
    local inCombat = InCombatLockdown()
    local c = 0

    for i, data in ipairs(missingList) do
        c = c + 1
        if c > MAX_SLOTS then break end
        local slot = iconSlots[c]
        slot.icon:SetTexture(data.icon)
        slot.text:SetText(data.text or "")
        
        if data.count and data.count > 0 then
            slot.countText:SetText(data.count)
        else
            slot.countText:SetText("")
        end

        if not inCombat then
            slot:SetAttribute("type", nil)
            slot:SetAttribute("spell", nil)
            slot:SetAttribute("macrotext", nil)

            if data.type == "spell" and data.spellId then
                slot:SetAttribute("type", "spell")
                slot:SetAttribute("spell", data.spellId)
            elseif data.type == "macro" and data.macroText then
                slot:SetAttribute("type", "macro")
                slot:SetAttribute("macrotext", data.macroText)
            end
        end
        
        UpdateGlow(slot, true)
        -- SecureButton: 전투 중 Show/Hide 대신 alpha 사용
        if inCombat then
            slot:SetAlpha(1)
        else
            slot:Show()
            slot:SetAlpha(1)
        end
    end

    for i = c + 1, MAX_SLOTS do
        if not inCombat then
            iconSlots[i]:SetAttribute("type", nil)
        end
        UpdateGlow(iconSlots[i], false)
        -- SecureButton: 전투 중 Show/Hide 대신 alpha 사용
        if inCombat then
            iconSlots[i]:SetAlpha(0)
        else
            iconSlots[i]:Hide()
        end
    end
    self:UpdateVisuals()
end

function BuffChecker:ConditionCheck()
    if isTestMode then return true end
    if self.db.hideInCombat and InCombatLockdown() then return false end
    if self.db.ignoreWhileMounted and IsMounted() then return false end
    if self.db.ignoreWhileResting and IsResting() then return false end
    
    local inInst = IsInInstance()
    local inGrp = IsInGroup() or IsInRaid()
    local zoneOpt = self.db.zoneCheck or "always"
    
    if zoneOpt == "instance" and not inInst then return false end
    if zoneOpt == "group" and not inGrp then return false end
    if zoneOpt == "instanceOrGroup" and not (inInst or inGrp) then return false end
    
    return true
end

-- SecureButton 자식 보유 프레임 안전 표시/숨기기
local function SafeSetVisible(visible)
    if not mainFrame then return end
    if InCombatLockdown() then
        -- 전투 중: SetAlpha만 안전 (Hide/Show/EnableMouse 전부 taint)
        mainFrame:SetAlpha(visible and 1 or 0)
    else
        -- 비전투: 정상 Show/Hide
        if visible then
            mainFrame:SetAlpha(1)
            mainFrame:EnableMouse(true)
            mainFrame:Show()
        else
            mainFrame:EnableMouse(false)
            mainFrame:Hide()
        end
    end
end

function BuffChecker:DoCheck()
    if not isEnabled or throttlePending then return end

    -- 조건 불충족 → 모두 숨기기
    if not self:ConditionCheck() then
        lastMissingKey = ""
        SafeSetVisible(false)
        return
    end

    -- 쓰로틀링
    local now = GetTime()
    if now - lastCheckTime < checkThrottle then
        throttlePending = true
        C_Timer.After(checkThrottle, function()
            throttlePending = false
            self:DoCheck()
        end)
        return
    end
    lastCheckTime = now

    local auras = ScanPlayerAuras()
    local ml = {}

    if self.db.checkClassBuff then
        local r = self:CheckClassBuff()
        if r then ml[#ml+1] = r end
    end
    if self.db.showFlask then
        local r = self:CheckFlask(auras)
        if r then ml[#ml+1] = r end
    end
    if self.db.showFood then
        local r = self:CheckFood(auras)
        if r then ml[#ml+1] = r end
    end
    if self.db.showRune then
        local r = self:CheckRune(auras)
        if r then ml[#ml+1] = r end
    end
    if self.db.showWeapon and (playerClass ~= "HUNTER" and playerClass ~= "EVOKER" and playerClass ~= "WARLOCK" and playerClass ~= "PRIEST" and playerClass ~= "MAGE") then
        local r = self:CheckWeaponOil()
        if r then for _,v in ipairs(r) do ml[#ml+1] = v end end
    end
    if self.db.checkRoguePoisons and playerClass == "ROGUE" then
        local r = self:CheckRoguePoisons(auras)
        if r then for _,v in ipairs(r) do ml[#ml+1] = v end end
    end
    if self.db.checkPet then
        local r = self:CheckPet(auras)
        if r then ml[#ml+1] = r end
    end
    if self.db.checkStance then
        local r = self:CheckStance()
        if r then ml[#ml+1] = r end
    end

    -- 변경 감지 키: 개수 + 텍스트
    local k = tostring(#ml) .. ":"
    for _,v in ipairs(ml) do k = k .. (v.text or "") .. ";" end

    if lastMissingKey ~= k then
        lastMissingKey = k
        self:ShowMissingList(ml)
    end

    -- mainFrame 표시 관리
    SafeSetVisible(#ml > 0)
end

function BuffChecker:RegisterEvents()
    if not eventFrame then eventFrame = CreateFrame("Frame") end
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_ENABLED" then
            -- 전투 해제 → alpha 숨김 → 정상 Show/Hide 전환을 위해 키 리셋
            lastMissingKey = ""
            BuffChecker:DoCheck()
        elseif event == "UNIT_AURA" then
            local u = ...
            if u == "player" or u:match("^party") or u:match("^raid") then BuffChecker:DoCheck() end
        else
            BuffChecker:DoCheck()
        end
    end)
end

function BuffChecker:TestMode()
    isTestMode = not isTestMode
    self._editPreviewActive = isTestMode
    if isTestMode then
        local ml = {
            { icon=136235, text="테스트 영약", count=5, type="macro" },
            { icon=136235, text="테스트 음식", count=23, type="macro" },
            { icon=136235, text="주무기 오일", count=2, type="spell" },
            { icon=136235, text="누락 (3)", count=0, type="spell" },
        }
        self:_ShowTestData(ml)
    else
        lastMissingKey = ""
        BuffChecker:DoCheck()
    end
end

-- 테스트/편집 데이터 직접 표시 (ShowMissingList 가드 우회)
function BuffChecker:_ShowTestData(ml)
    if not mainFrame then self:CreateMainFrame() end
    local c = 0
    for i, data in ipairs(ml) do
        c = c + 1
        if c > MAX_SLOTS then break end
        local slot = iconSlots[c]
        slot.icon:SetTexture(data.icon)
        slot.text:SetText(data.text or "")
        if data.count and data.count > 0 then slot.countText:SetText(data.count)
        else slot.countText:SetText("") end
        UpdateGlow(slot, true)
        slot:Show()
    end
    for i = c + 1, MAX_SLOTS do
        UpdateGlow(iconSlots[i], false)
        iconSlots[i]:Hide()
    end
    if mainFrame then mainFrame:Show() end
    self:UpdateVisuals()
end

-- 편집 모드 연동 (Movers)
function BuffChecker:EnterEditPreview()
    self._editPreviewActive = true
    isTestMode = true
    local ml = {
        { icon=136235, text="테스트 영약", count=5, type="macro" },
        { icon=136235, text="테스트 음식", count=23, type="macro" },
        { icon=136235, text="주무기 오일", count=2, type="spell" },
        { icon=136235, text="누락 (3)", count=0, type="spell" },
    }
    self:_ShowTestData(ml)
end

function BuffChecker:ExitEditPreview()
    self._editPreviewActive = false
    isTestMode = false
    lastMissingKey = ""
    self:DoCheck()
end

-- =====================================
-- MODULE REGISTRATION
-- =====================================
DDingQoC:RegisterModule("BuffChecker", BuffChecker)
