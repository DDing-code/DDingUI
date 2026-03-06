--[[
    DDingToolKit - BuffChecker Module
    음식/영약/무기인챈트/룬 버프 체크
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF" -- [12.0.1]
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: " -- [STYLE]

local BuffChecker = {}
BuffChecker.name = "BuffChecker"
ns.BuffChecker = BuffChecker

-- 음식 버프 아이콘 ID (MRT 방식 - 모든 확장팩 공통)
local FOOD_BUFF_ICONS = {
    [136000] = true,  -- Well Fed (공통 아이콘)
    [134062] = true,  -- 음식 버프 (대체 아이콘)
    [132805] = true,  -- 음식 관련
    [133950] = true,  -- 음식 관련
}

local FLASK_SPELL_IDS = {
    432021,  -- Flask of Alchemical Chaos
    432473,  -- Flask of Tempered Versatility
    431971,  -- Flask of Tempered Aggression
    431974,  -- Flask of Tempered Mastery
    431972,  -- Flask of Tempered Swiftness
    431973,  -- Flask of Tempered Critical Strike
}

local RUNE_SPELL_IDS = {
    1242347, -- Augment Rune (TWW S2, 11.2.5)
    1234969, -- Augment Rune (TWW S1, 11.1.5)
    453250,  -- Crystallized Augment Rune (TWW)
    393438,  -- Draconic Augment Rune
}

-- 소모품 아이템 ID (가방 검색용, 클릭 사용)
local FLASK_ITEMS = {
    -- TWW Cauldron flasks
    212741, 212740, 212739,  -- Alchemical Chaos (Cauldron)
    212747, 212746, 212745,  -- Tempered Versatility (Cauldron)
    212728, 212727, 212725,  -- Tempered Aggression (Cauldron)
    212731, 212730, 212729,  -- Tempered Mastery (Cauldron)
    212738, 212736, 212735,  -- Tempered Swiftness (Cauldron)
    212734, 212733, 212732,  -- Tempered Crit (Cauldron)
    -- TWW Regular flasks
    212283, 212282, 212281,  -- Flask of Alchemical Chaos
    212301, 212300, 212299,  -- Flask of Tempered Versatility
    212271, 212270, 212269,  -- Flask of Tempered Aggression
    212274, 212273, 212272,  -- Flask of Tempered Mastery
    212280, 212279, 212278,  -- Flask of Tempered Swiftness
    212277, 212276, 212275,  -- Flask of Tempered Crit
}

local RUNE_ITEMS = {
    243191,  -- Crystallized Augment Rune (Unlimited, TWW)
    224572,  -- Crystallized Augment Rune (TWW)
    246492,  -- Augment Rune (alternate)
}

-- TWW Weapon Enchant Items (oils, sharpening stones, weightstones)
local WEAPON_ENCHANT_ITEMS = {
    -- Algari Mana Oil
    222508, 222509, 222510,
    -- Bubbling Wax
    222502, 222503, 222504,
    -- Ironclaw Whetstone
    222894, 222895, 222896,
    -- Ironclaw Weightstone
    222891, 222892, 222893,
    -- Ironclaw Sharpening Stone
    222888, 222889, 222890,
    -- Algari Grinding Stone
    224105, 224106, 224107,
    -- Algari Weighted Sharpening Stone
    224108, 224109, 224110,
    -- Algari Mana Embossment
    224111, 224112, 224113,
    -- TWW Season oils
    219906, 219907, 219908,
    219909, 219910, 219911,
    219912, 219913, 219914,
    -- Misc
    210494,
}

-- 아이콘 (WeakAura 기준)
local ICONS = {
    food = 133943,       -- Food Tracker
    flask = 5931173,     -- Flask Tracker
    mainhand = 609892,   -- Weapon Enchant
    offhand = 609892,    -- Weapon Enchant
    rune = 4549102,      -- Augment Rune Tracker
}

-- 로컬 변수
local mainFrame = nil
local iconFrames = {}
local updateTicker = nil
local isEnabled = false
local isTestMode = false

-- [FIX] 전투 중 SecureActionButton 자식 때문에 Hide/Show blocked 방지
local pendingHide = false
local function _Hide(frame)
    if not frame then return end
    if InCombatLockdown() then
        pendingHide = true
        return
    end
    frame:Hide()
    pendingHide = false
end
local function _Show(frame)
    if not frame then return end
    if InCombatLockdown() then
        pendingHide = false
        return
    end
    frame:Show()
    pendingHide = false
end

-- 초기화
function BuffChecker:OnInitialize()
    self.db = ns.db.profile.BuffChecker
end

-- 활성화
function BuffChecker:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.BuffChecker then
            self.db = ns.db.profile.BuffChecker
        else
            self.db = {
                enabled = false,
                showFood = false,
                showFlask = false,
                showWeapon = false,
                showRune = false,
                instanceOnly = true,
                iconSize = 40,
                scale = 1.0,
                locked = false,
                showText = true,
                textSize = 10,
                textFont = SL_FONT, -- [12.0.1]
                textColor = { r = 1, g = 0.3, b = 0.3 },
                alignment = "CENTER",  -- LEFT, CENTER, RIGHT
                position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 },
            }
        end
    end

    if not self.db.enabled then
        isEnabled = false
        return
    end

    isEnabled = true
    self:CreateMainFrame()
    self:StartUpdate()
end

-- 비활성화
function BuffChecker:OnDisable()
    isEnabled = false
    if mainFrame then _Hide(mainFrame) end
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

-- 메인 프레임 생성
function BuffChecker:CreateMainFrame()
    if mainFrame then return end

    local pos = self.db.position or {}
    local frame = CreateFrame("Frame", "DDingToolKit_BuffCheckerFrame", UIParent)
    frame:SetSize(250, 60)
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -200)
    frame:SetFrameStrata("HIGH")
    frame:SetScale(self.db.scale or 1.0)

    -- 드래그
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not BuffChecker.db.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        BuffChecker.db.position.point = point
        BuffChecker.db.position.relativePoint = relativePoint
        BuffChecker.db.position.x = x
        BuffChecker.db.position.y = y
    end)

    mainFrame = frame

    -- 아이콘 프레임 생성
    self:CreateIconFrames()
end

-- 아이콘 프레임 생성
function BuffChecker:CreateIconFrames()
    local size = self.db.iconSize or 40
    local types = {"food", "flask", "mainhand", "offhand", "rune"}

    for i, t in ipairs(types) do
        local f = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
        f:SetSize(size, size)
        f:SetBackdrop({
            bgFile = SL_FLAT, -- [12.0.1]
            edgeFile = SL_FLAT, -- [12.0.1]
            edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.6)
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

        -- 아이콘
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetPoint("TOPLEFT", 2, -2)
        f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        f.icon:SetTexture(ICONS[t])
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- 라벨
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("BOTTOM", f, "BOTTOM", 0, -14)
        local textSize = self.db.textSize or 10
        local textFont = self.db.textFont or SL_FONT -- [12.0.1]
        f.text:SetFont(textFont, textSize, "OUTLINE")
        local color = self.db.textColor or { r = 1, g = 0.3, b = 0.3 }
        f.text:SetTextColor(color.r, color.g, color.b, 1)
        if not self.db.showText then
            f.text:Hide()
        end

        f.type = t
        f:Hide()

        -- 클릭 가능 오버레이 (음식 제외 - 아이템이 너무 다양함)
        if t ~= "food" then
            local clickBtn = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
            clickBtn:SetAllPoints()
            clickBtn:RegisterForClicks("AnyUp", "AnyDown")
            if t == "mainhand" then
                clickBtn:SetAttribute("type", "item")
                clickBtn:SetAttribute("target-slot", 16)
            elseif t == "offhand" then
                clickBtn:SetAttribute("type", "item")
                clickBtn:SetAttribute("target-slot", 17)
            else
                clickBtn:SetAttribute("type", "macro")
            end
            clickBtn:Hide()

            -- 툴팁
            clickBtn:SetScript("OnEnter", function(btn)
                if btn.itemID then
                    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
                    GameTooltip:SetItemByID(btn.itemID)
                    GameTooltip:Show()
                end
            end)
            clickBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            f.clickButton = clickBtn
        end

        iconFrames[t] = f
    end

    self:UpdateLayout()
end

-- 레이아웃 업데이트
function BuffChecker:UpdateLayout()
    local size = self.db.iconSize or 40
    local spacing = 5
    local alignment = self.db.alignment or "CENTER"
    local visibleFrames = {}

    for _, f in pairs(iconFrames) do
        f:SetSize(size, size)
        if f:IsShown() or (f:GetAlpha() > 0 and f.pendingShow) then
            table.insert(visibleFrames, f)
        end
    end

    local totalWidth = #visibleFrames * size + (#visibleFrames - 1) * spacing

    for i, f in ipairs(visibleFrames) do
        f:ClearAllPoints()
        if alignment == "LEFT" then
            local xPos = (i - 1) * (size + spacing)
            f:SetPoint("LEFT", mainFrame, "LEFT", xPos, 0)
        elseif alignment == "RIGHT" then
            local xPos = -((#visibleFrames - i) * (size + spacing))
            f:SetPoint("RIGHT", mainFrame, "RIGHT", xPos, 0)
        else -- CENTER
            local startX = -totalWidth / 2 + size / 2
            f:SetPoint("CENTER", mainFrame, "CENTER", startX + (i - 1) * (size + spacing), 0)
        end
    end
end

-- 클릭 가능 버튼 업데이트
function BuffChecker:UpdateClickables()
    if InCombatLockdown() then return end

    local function UpdateClickButton(frame, itemList, attrType)
        if not frame or not frame.clickButton then return end
        if not frame:IsShown() then
            frame.clickButton:Hide()
            return
        end

        local itemID, count = BuffChecker:FindItemInBags(itemList)
        if itemID and count > 0 then
            local itemName = C_Item.GetItemInfo(itemID) -- [12.0.1] GetItemInfo → C_Item.GetItemInfo
            if itemName then
                if attrType == "item" then
                    frame.clickButton:SetAttribute("item", itemName)
                else
                    frame.clickButton:SetAttribute("macrotext1", string.format("/stopmacro [combat]\n/use %s", itemName))
                end
                frame.clickButton.itemID = itemID
                frame.clickButton:Show()
                return
            end
        end
        frame.clickButton:Hide()
    end

    UpdateClickButton(iconFrames.flask, FLASK_ITEMS, "macro")
    UpdateClickButton(iconFrames.mainhand, WEAPON_ENCHANT_ITEMS, "item")
    UpdateClickButton(iconFrames.offhand, WEAPON_ENCHANT_ITEMS, "item")
    UpdateClickButton(iconFrames.rune, RUNE_ITEMS, "macro")
end

-- MRT 방식: GetAuraDataByIndex로 순회하며 spellId/icon 비교
-- 음식: 아이콘 ID로 감지, 영약/룬: spellId로 감지
function BuffChecker:ScanAuras()
    local result = { food = false, flask = false, rune = false }
    local flaskLookup = {}
    for _, id in ipairs(FLASK_SPELL_IDS) do flaskLookup[id] = true end
    local runeLookup = {}
    for _, id in ipairs(RUNE_SPELL_IDS) do runeLookup[id] = true end

    for i = 1, 60 do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not auraData then break end

        -- 음식: 아이콘 기반
        local ok2, icon = pcall(function() return auraData.icon end)
        if ok2 and icon and FOOD_BUFF_ICONS[icon] then
            result.food = true
        end

        -- 영약/룬: spellId 기반
        local ok3, spellId = pcall(function() return auraData.spellId end)
        if ok3 and spellId then
            if flaskLookup[spellId] then result.flask = true end
            if runeLookup[spellId] then result.rune = true end
        end
    end
    return result
end

-- 무기 인챈트 체크 (8값 전체 unpack)
function BuffChecker:HasWeaponEnchant(slot)
    local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID,
          hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantID = GetWeaponEnchantInfo()
    if slot == "main" then
        return hasMainHandEnchant, mainHandEnchantID
    else
        return hasOffHandEnchant, offHandEnchantID
    end
end

-- 보조무기 장착 여부 (무기만 인챈트 가능, 방패/장신구 제외)
function BuffChecker:HasOffhand()
    local offhandItemID = GetInventoryItemID("player", 17)
    if not offhandItemID then return false end
    local _, _, _, _, _, itemClassID = GetItemInfoInstant(offhandItemID)
    return itemClassID == 2  -- Enum.ItemClass.Weapon
end

-- 가방에서 아이템 검색
function BuffChecker:FindItemInBags(itemIDs)
    for _, id in ipairs(itemIDs) do
        local count = GetItemCount(id, false, true)
        if count and count > 0 then
            return id, count
        end
    end
    return nil, 0
end

-- 인스턴스 체크
function BuffChecker:IsInInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario")
end

-- 파티/레이드 체크
function BuffChecker:IsInGroup()
    return IsInGroup() or IsInRaid()
end

-- 업데이트
function BuffChecker:Update()
    if not isEnabled or not mainFrame then return end
    if isTestMode then return end
    if InCombatLockdown() then return end -- [FIX] 전투 중 SecureFrame 조작 방지

    -- 오라 1회 스캔 (음식/영약/룬 동시 감지)
    local auras = self:ScanAuras()
    local anyMissing = false

    -- 음식 체크
    if self.db.showFood then
        if auras.food then
            _Hide(iconFrames.food)
        else
            _Show(iconFrames.food)
            iconFrames.food.text:SetText(L["BUFFCHECKER_FOOD"])
            anyMissing = true
        end
    else
        _Hide(iconFrames.food)
    end

    -- 영약 체크
    if self.db.showFlask then
        if auras.flask then
            _Hide(iconFrames.flask)
        else
            _Show(iconFrames.flask)
            iconFrames.flask.text:SetText(L["BUFFCHECKER_FLASK"])
            anyMissing = true
        end
    else
        _Hide(iconFrames.flask)
    end

    -- 무기 인챈트 체크
    if self.db.showWeapon then
        if self:HasWeaponEnchant("main") then
            _Hide(iconFrames.mainhand)
        else
            _Show(iconFrames.mainhand)
            iconFrames.mainhand.text:SetText(L["BUFFCHECKER_MAINHAND"])
            anyMissing = true
        end

        if self:HasOffhand() then
            if self:HasWeaponEnchant("off") then
                _Hide(iconFrames.offhand)
            else
                _Show(iconFrames.offhand)
                iconFrames.offhand.text:SetText(L["BUFFCHECKER_OFFHAND"])
                anyMissing = true
            end
        else
            _Hide(iconFrames.offhand)
        end
    else
        _Hide(iconFrames.mainhand)
        _Hide(iconFrames.offhand)
    end

    -- 룬 체크
    if self.db.showRune then
        if auras.rune then
            _Hide(iconFrames.rune)
        else
            _Show(iconFrames.rune)
            iconFrames.rune.text:SetText(L["BUFFCHECKER_RUNE"])
            anyMissing = true
        end
    else
        _Hide(iconFrames.rune)
    end

    -- 레이아웃 업데이트
    self:UpdateLayout()

    -- 클릭 가능 버튼 업데이트
    self:UpdateClickables()

    -- 프레임 표시/숨김
    if anyMissing then
        _Show(mainFrame)
    else
        _Hide(mainFrame)
    end
end

-- 업데이트 시작 (레디체크 이벤트만 감지)
function BuffChecker:StartUpdate()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end

    _Hide(mainFrame)

    if not mainFrame.eventFrame then
        mainFrame.eventFrame = CreateFrame("Frame")
        mainFrame.eventFrame:RegisterEvent("READY_CHECK")
        mainFrame.eventFrame:RegisterEvent("READY_CHECK_FINISHED")
        mainFrame.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        mainFrame.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- [FIX] deferred hide
        mainFrame.eventFrame:SetScript("OnEvent", function(_, event)
            if event == "READY_CHECK" then
                -- 레디체크 시작 → 즉시 스캔 + 반복 스캔 시작
                BuffChecker:Update()
                if updateTicker then updateTicker:Cancel() end
                updateTicker = C_Timer.NewTicker(1, function()
                    BuffChecker:Update()
                end)
            elseif event == "READY_CHECK_FINISHED" or event == "PLAYER_REGEN_DISABLED" then
                -- 레디체크 종료 or 전투 시작 → 반복 스캔 중지 + 숨김
                if updateTicker then
                    updateTicker:Cancel()
                    updateTicker = nil
                end
                _Hide(mainFrame)
            elseif event == "PLAYER_REGEN_ENABLED" then
                -- [FIX] 전투 종료 → deferred hide 처리
                if pendingHide and mainFrame and not InCombatLockdown() then
                    mainFrame:Hide()
                    pendingHide = false
                end
            end
        end)
    end
end

-- 메인 프레임 반환
function BuffChecker:GetMainFrame()
    return mainFrame
end

-- 테스트 모드 (토글)
function BuffChecker:TestMode()
    if not mainFrame then
        self:CreateMainFrame()
    end

    isTestMode = not isTestMode

    if isTestMode then
        -- 모든 아이콘 표시
        for _, f in pairs(iconFrames) do
            _Show(f)
        end
        iconFrames.food.text:SetText(L["BUFFCHECKER_FOOD"])
        iconFrames.flask.text:SetText(L["BUFFCHECKER_FLASK"])
        iconFrames.mainhand.text:SetText(L["BUFFCHECKER_MAINHAND"])
        iconFrames.offhand.text:SetText(L["BUFFCHECKER_OFFHAND"])
        iconFrames.rune.text:SetText(L["BUFFCHECKER_RUNE"])

        self:UpdateLayout()
        self:UpdateClickables()
        _Show(mainFrame)

        print(CHAT_PREFIX .. "BuffChecker " .. L["TEST_MODE"] .. " ON") -- [STYLE]
    else
        print(CHAT_PREFIX .. "BuffChecker " .. L["TEST_MODE"] .. " OFF") -- [STYLE]
        self:Update()
    end
end

function BuffChecker:IsTestMode()
    return isTestMode
end

-- 텍스트 설정 업데이트
function BuffChecker:UpdateTextSettings()
    local textSize = self.db.textSize or 10
    local textFont = self.db.textFont or SL_FONT -- [12.0.1]
    local color = self.db.textColor or { r = 1, g = 0.3, b = 0.3 }
    local showText = self.db.showText

    for _, f in pairs(iconFrames) do
        if f.text then
            f.text:SetFont(textFont, textSize, "OUTLINE")
            f.text:SetTextColor(color.r, color.g, color.b, 1)
            if showText then
                f.text:Show()
            else
                f.text:Hide()
            end
        end
    end
end

-- 위치 초기화
function BuffChecker:ResetPosition()
    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
        self.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -200 }
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("BuffChecker", BuffChecker)
