--[[
    DDingToolKit - BuffReminder / BuffScanner
    누락 감지 엔진: 레이드 버프, 셀프 버프, 소모품, 펫 상태 스캔
]]

local addonName, ns = ...

local Scanner = {}
ns.BuffScanner = Scanner

-- =============================================
-- UTILS
-- =============================================
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

local function IsSpellKnownSafe(spellId)
    if not spellId then return false end
    local ok, known = pcall(C_SpellBook.IsSpellKnown, spellId)
    if not ok then return false end
    return safeValue(known) == true
end

local function IsPlayerSpellSafe(spellId)
    if not spellId then return false end
    local ok, val = pcall(IsPlayerSpell, spellId)
    if not ok then return false end
    return safeValue(val) == true
end

local function GetBestItemFromList(itemList)
    if not itemList then return nil, 0 end
    if type(itemList) == "table" and #itemList == 0 then
        -- 딕셔너리 형태일 수 있음 → pairs 사용
        for itemID, _ in pairs(itemList) do
            if type(itemID) == "number" then
                local ok, count = pcall(C_Item.GetItemCount, itemID, false, false)
                if ok and count and count > 0 then return itemID, count end
            end
        end
        return nil, 0
    end
    for _, itemID in ipairs(itemList) do
        local ok, count = pcall(C_Item.GetItemCount, itemID, false, false)
        if ok and count and count > 0 then return itemID, count end
    end
    return nil, 0
end

-- CONSUMABLE_ITEMS 딕셔너리에서 아이템 목록을 안전하게 추출
local function GetConsumableItemDict(category)
    local items = ns.CONSUMABLE_ITEMS and ns.CONSUMABLE_ITEMS[category]
    return items -- 딕셔너리(또는 nil)
end

local function GetItemIcon(itemID)
    if not itemID then return 136235 end
    local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
    if ok and icon then return icon end
    return 136235
end

-- =============================================
-- AURA SCANNING
-- =============================================

-- 플레이어 오라 스캔 결과 캐시
local cachedAuras = nil

function Scanner.ScanPlayerAuras()
    local result = { hasBuff = {}, expiration = {}, iconMap = {} }
    for i = 1, 80 do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not auraData then break end
        local sid = safeValue(auraData.spellId)
        local name = safeValue(auraData.name)
        local iconID = safeValue(auraData.icon)
        if sid then
            result.hasBuff[sid] = true
            result.expiration[sid] = auraData.expirationTime
            if iconID then result.iconMap[sid] = iconID end
        end
        if name then
            result.hasBuff[name] = true
            result.expiration[name] = auraData.expirationTime
        end
        -- 아이콘 ID로도 체크 (음식 버프 등)
        if iconID then
            result.hasBuff["icon:" .. iconID] = true
            result.expiration["icon:" .. iconID] = auraData.expirationTime
        end
    end
    cachedAuras = result
    return result
end

-- =============================================
-- RAID BUFF SCANNER
-- =============================================
function Scanner.ScanRaidBuffs(db, playerClass)
    if not db or not db.checkRaidBuff then return {} end

    local results = {}
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
        units[#units + 1] = "player"
    else
        units[#units + 1] = "player"
    end

    for _, buffDef in ipairs(ns.RAID_BUFFS) do
        -- 본인 클래스 캐스터만 체크 (해당 클래스면 누락 감지)
        if buffDef.class == playerClass then
            local castSpell = buffDef.castSpellID
            if castSpell and IsSpellKnownSafe(castSpell) then
                local missingCount = 0
                local totalCount = 0

                for _, u in ipairs(units) do
                    if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
                        local inPhase = true
                        if UnitPhaseReason then
                            inPhase = (UnitPhaseReason(u) == nil)
                        end

                        if inPhase then
                            local inRange = true
                            if u ~= "player" then
                                local okR, rv = pcall(C_Spell.IsSpellInRange, castSpell, u)
                                if okR then
                                    rv = safeValue(rv)
                                    if rv == false or rv == 0 then inRange = false end
                                end
                            end

                            if inRange then
                                totalCount = totalCount + 1
                                local hasBuff = false

                                -- 전투 중이면 combat-safe 방식, 아니면 일반 스캔
                                if InCombatLockdown() then
                                    for _, sid in ipairs(buffDef.spellID) do
                                        if ns.COMBAT_SAFE_SPELLS[sid] then
                                            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, u, sid, "HELPFUL")
                                            if ok and aura then hasBuff = true break end
                                        end
                                    end
                                else
                                    for idx = 1, 40 do
                                        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, u, idx, "HELPFUL")
                                        if not ok or not aura then break end
                                        local sid = safeValue(aura.spellId)
                                        if sid then
                                            for _, defSid in ipairs(buffDef.spellID) do
                                                if sid == defSid then hasBuff = true break end
                                            end
                                        end
                                        if hasBuff then break end
                                    end
                                end

                                if not hasBuff then
                                    missingCount = missingCount + 1
                                end
                            end
                        end
                    end
                end

                if missingCount > 0 then
                    local icon = buffDef.icon or GetSpellIcon(castSpell)
                    local text = missingCount == 1 and "버프 누락" or ("누락 (" .. missingCount .. ")")
                    results[#results + 1] = {
                        key = buffDef.key,
                        category = "raid",
                        icon = icon,
                        text = text,
                        spellId = castSpell,
                        castType = "spell",
                        isMissing = true,
                        isExpiring = false,
                        count = missingCount,
                    }
                end
            end
        end
    end

    return results
end

-- =============================================
-- SELF BUFF SCANNER
-- =============================================
function Scanner.ScanSelfBuffs(db, playerClass, currentSpecId, auras)
    local results = {}
    if not db then return results end

    for _, buffDef in ipairs(ns.SELF_BUFFS) do
        if buffDef.class ~= playerClass then
            -- 클래스 불일치 → 스킵
        elseif buffDef.specOnly and not buffDef.specOnly[currentSpecId] then
            -- 특성 조건 불만족
        elseif buffDef.requiresSpellID and not IsPlayerSpellSafe(buffDef.requiresSpellID) then
            -- 필요 특성 미보유
        elseif buffDef.excludeSpellID and IsPlayerSpellSafe(buffDef.excludeSpellID) then
            -- 제외 특성 보유
        else
            -- 태세/오라 체크
            if buffDef.customCheck == "stance" then
                if db.checkStance ~= false then
                    local hasLearnedAny = false
                    for _, stance in ipairs(buffDef.stanceSpells or {}) do
                        if IsSpellKnownSafe(stance.spellId) then
                            hasLearnedAny = true
                            stance._learned = true
                        else
                            stance._learned = false
                        end
                    end
                    if hasLearnedAny then
                        local formIdx = GetShapeshiftForm()
                        if not formIdx or formIdx == 0 then
                            -- 태세 없음 → 누락
                            local castSpell = nil
                            local icon = nil
                            for _, stance in ipairs(buffDef.stanceSpells) do
                                if stance.default and stance._learned then
                                    castSpell = stance.spellId
                                    icon = GetSpellIcon(stance.spellId)
                                    break
                                end
                            end
                            if not castSpell then
                                for _, stance in ipairs(buffDef.stanceSpells) do
                                    if stance._learned then
                                        castSpell = stance.spellId
                                        icon = GetSpellIcon(stance.spellId)
                                        break
                                    end
                                end
                            end
                            if castSpell then
                                results[#results + 1] = {
                                    key = buffDef.key,
                                    category = "self",
                                    icon = icon or 136235,
                                    text = buffDef.overlayText or "누락",
                                    spellId = castSpell,
                                    castType = "spell",
                                    isMissing = true,
                                    isExpiring = false,
                                }
                            end
                        end
                    end
                end
            else
    -- 일반 셀프 버프 확인
                local configKey = "check_" .. buffDef.key
                -- 로그 독: checkRoguePoisons, 주술사: checkShamanBuffs 등
                local shouldCheck = true
                if buffDef.key == "rogueLethal" or buffDef.key == "rogueNonLethal" then
                    shouldCheck = db.checkRoguePoisons ~= false
                elseif buffDef.key:find("^shaman") then
                    shouldCheck = db.checkShamanBuffs ~= false
                elseif buffDef.key:find("^dk") then
                    shouldCheck = db.checkDKRunes ~= false
                end

                if shouldCheck then
                    local hasBuff = false
                    for _, sid in ipairs(buffDef.spellID or {}) do
                        if auras.hasBuff[sid] then
                            hasBuff = true
                            break
                        end
                    end

                    if not hasBuff then
                        local castSpell = buffDef.castSpellID
                        local icon = buffDef.icon or GetSpellIcon(castSpell or buffDef.spellID[1])
                        results[#results + 1] = {
                            key = buffDef.key,
                            category = "self",
                            icon = icon,
                            text = buffDef.overlayText or "누락",
                            spellId = castSpell,
                            castType = castSpell and "spell" or nil,
                            isMissing = true,
                            isExpiring = false,
                        }
                    end
                end
            end
        end
    end

    return results
end

-- =============================================
-- CONSUMABLE SCANNER
-- =============================================
function Scanner.ScanConsumables(db, playerClass, auras)
    local results = {}
    if not db then return results end

    local threshold = (db.threshold or 5) * 60

    -- === 영약 ===
    if db.checkFlask ~= false then
        local hasFlask = false
        local isExpiring = false
        for _, sid in ipairs(ns.CONSUMABLE_FLASK_SPELLS) do
            if auras.hasBuff[sid] then
                hasFlask = true
                local exp = auras.expiration[sid]
                if exp and exp > 0 then
                    local remain = exp - GetTime()
                    if remain < threshold and remain > 0 then
                        isExpiring = true
                    end
                end
                break
            end
        end

        if not hasFlask or isExpiring then
            local bestId, count = GetBestItemFromList(GetConsumableItemDict("flask"))
            local icon, text, macroText
            if bestId then
                icon = GetItemIcon(bestId)
                text = isExpiring and "영약 갱신" or "영약 사용"
                macroText = "/use item:" .. bestId
            else
                icon = GetSpellIcon(1235057)
                text = "영약 없음"
            end
            results[#results + 1] = {
                key = "flask",
                category = "consumable",
                icon = icon,
                text = text,
                macroText = macroText,
                castType = macroText and "macro" or nil,
                isMissing = not hasFlask,
                isExpiring = isExpiring,
                count = count or 0,
            }
        end
    end

    -- === 음식 ===
    if db.checkFood ~= false then
        local hasFood = auras.hasBuff["icon:" .. ns.CONSUMABLE_FOOD_ICON_ID]
        local isExpiring = false
        if hasFood then
            local exp = auras.expiration["icon:" .. ns.CONSUMABLE_FOOD_ICON_ID]
            if exp and exp > 0 then
                local remain = exp - GetTime()
                if remain < threshold and remain > 0 then
                    isExpiring = true
                end
            end
        end

        if not hasFood or isExpiring then
            local bestId, count = GetBestItemFromList(GetConsumableItemDict("food"))
            local icon, text, macroText
            if bestId then
                icon = GetItemIcon(bestId)
                text = isExpiring and "음식 갱신" or "음식 사용"
                macroText = "/use item:" .. bestId
            else
                icon = 136000 -- 음식 아이콘
                text = "음식 없음"
            end
            results[#results + 1] = {
                key = "food",
                category = "consumable",
                icon = icon,
                text = text,
                macroText = macroText,
                castType = macroText and "macro" or nil,
                isMissing = not hasFood,
                isExpiring = isExpiring,
                count = count or 0,
            }
        end
    end

    -- === 증강 룬 ===
    if db.checkRune ~= false then
        local hasRune = false
        for _, sid in ipairs(ns.CONSUMABLE_RUNE_SPELLS) do
            if auras.hasBuff[sid] then
                hasRune = true
                break
            end
        end

        if not hasRune then
            local bestId, count = GetBestItemFromList(GetConsumableItemDict("rune"))
            local icon, text, macroText
            if bestId then
                icon = GetItemIcon(bestId)
                text = "룬 사용"
                macroText = "/use item:" .. bestId
            else
                icon = GetSpellIcon(393438)
                text = "룬 없음"
            end
            results[#results + 1] = {
                key = "rune",
                category = "consumable",
                icon = icon,
                text = text,
                macroText = macroText,
                castType = macroText and "macro" or nil,
                isMissing = true,
                isExpiring = false,
                count = count or 0,
            }
        end
    end

    -- === 무기 강화 (오일/숫돌) ===
    if db.checkWeapon ~= false then
        -- 자체 imbue 보유 클래스는 제외
        local hasOwnImbue = false
        for _, sid in ipairs(ns.WEAPON_BUFF_EXCLUDE_SPELLS) do
            if IsSpellKnownSafe(sid) then
                hasOwnImbue = true
                break
            end
        end

        if not hasOwnImbue then
            local ok, hasMain, mainExp, _, mainId, hasOff, offExp, _, offId = pcall(GetWeaponEnchantInfo)
            if ok then
                hasMain = safeValue(hasMain)
                hasOff = safeValue(hasOff)

                local bestId, count = GetBestItemFromList(GetConsumableItemDict("weapon"))
                local macroText = bestId and ("/use item:" .. bestId) or nil
                local icon = bestId and GetItemIcon(bestId) or GetSpellIcon(1237006)

                if hasMain ~= nil and not hasMain then
                    local mainWeapon = GetInventoryItemID("player", 16)
                    if mainWeapon then
                        results[#results + 1] = {
                            key = "weaponMH",
                            category = "consumable",
                            icon = icon,
                            text = "주무기 강화",
                            macroText = macroText,
                            castType = macroText and "macro" or nil,
                            isMissing = true,
                            isExpiring = false,
                            count = count or 0,
                        }
                    end
                end

                if hasOff ~= nil and not hasOff then
                    local offWeapon = GetInventoryItemID("player", 17)
                    if offWeapon then
                        local okI, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, offWeapon)
                        if okI and classID == Enum.ItemClass.Weapon then
                            results[#results + 1] = {
                                key = "weaponOH",
                                category = "consumable",
                                icon = icon,
                                text = "보조무기 강화",
                                macroText = macroText,
                                castType = macroText and "macro" or nil,
                                isMissing = true,
                                isExpiring = false,
                                count = count or 0,
                            }
                        end
                    end
                end
            end
        end
    end

    return results
end

-- =============================================
-- PET SCANNER
-- =============================================
function Scanner.ScanPet(db, playerClass, currentSpecId, auras)
    if not db or db.checkPet == false then return {} end

    local pdata = ns.PET_DATA[playerClass]
    if not pdata then return {} end

    -- 특성 조건 체크
    if pdata.specOnly and not pdata.specOnly[currentSpecId] then return {} end
    if pdata.specIgnore and pdata.specIgnore[currentSpecId] then
        -- MM 예외: Unbreakable Bond 특성이 있으면 펫 필요
        if pdata.checkUnbreakableBond and IsPlayerSpellSafe(pdata.checkUnbreakableBond) then
            -- 체크 계속
        else
            return {}
        end
    end

    -- 희생 체크 (흑마)
    if pdata.sacrificeSpec and pdata.sacrificeSpec[currentSpecId] then
        if pdata.sacrificeSpell and auras.hasBuff[pdata.sacrificeSpell] then
            return {}
        end
    end

    local results = {}

    if HasPetUI() or UnitExists("pet") then
        if UnitIsDeadOrGhost("pet") and pdata.deadSpell then
            results[#results + 1] = {
                key = pdata.key .. "_dead",
                category = "pet",
                icon = GetSpellIcon(pdata.deadSpell),
                text = "소환수 부활",
                spellId = pdata.deadSpell,
                castType = "spell",
                isMissing = true,
                isExpiring = false,
            }
        end
    else
        results[#results + 1] = {
            key = pdata.key .. "_missing",
            category = "pet",
            icon = pdata.icon or GetSpellIcon(pdata.missingSpell),
            text = "소환수 부재",
            spellId = pdata.missingSpell,
            castType = "spell",
            isMissing = true,
            isExpiring = false,
        }
    end

    return results
end

-- =============================================
-- FULL SCAN (통합 호출)
-- =============================================
function Scanner.FullScan(db, playerClass, currentSpecId)
    local auras = Scanner.ScanPlayerAuras()
    local all = {}

    -- 1. 레이드 버프
    local raidResults = Scanner.ScanRaidBuffs(db, playerClass)
    for _, v in ipairs(raidResults) do all[#all + 1] = v end

    -- 2. 셀프 버프
    local selfResults = Scanner.ScanSelfBuffs(db, playerClass, currentSpecId, auras)
    for _, v in ipairs(selfResults) do all[#all + 1] = v end

    -- 3. 소모품
    local consumResults = Scanner.ScanConsumables(db, playerClass, auras)
    for _, v in ipairs(consumResults) do all[#all + 1] = v end

    -- 4. 펫
    local petResults = Scanner.ScanPet(db, playerClass, currentSpecId, auras)
    for _, v in ipairs(petResults) do all[#all + 1] = v end

    return all
end
