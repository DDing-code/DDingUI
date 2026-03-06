--[[
    DDingToolKit - ItemLevel Module
    캐릭터/살펴보기 창에 아이템 레벨, 인챈트, 보석 정보 표시
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit

-- 모듈 생성
local ItemLevel = {}
ItemLevel.name = "ItemLevel"
ItemLevel.enabled = false

-- 스캔 툴팁
local scanTip = CreateFrame("GameTooltip", "DDT_ItemLevelScanTip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- 슬롯 ID/우측판별
local SlotNames = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "MainHandSlot", "SecondaryHandSlot"
}
local SlotIDs = {}
for _, s in ipairs(SlotNames) do
    SlotIDs[s] = GetInventorySlotInfo(s)
end

local rightSide = {}
local function InitRightSide()
    rightSide = {
        [SlotIDs.WaistSlot] = true,
        [SlotIDs.LegsSlot] = true,
        [SlotIDs.FeetSlot] = true,
        [SlotIDs.HandsSlot] = true,
        [SlotIDs.Finger0Slot] = true,
        [SlotIDs.Finger1Slot] = true,
        [SlotIDs.Trinket0Slot] = true,
        [SlotIDs.Trinket1Slot] = true,
        [SlotIDs.MainHandSlot] = true,
    }
end

local function IsRight(id)
    return rightSide[id]
end

-- 천 단위 구분
local function Comma(num)
    local n = tostring(num)
    local k
    repeat
        n, k = n:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return n
end

-- 스탯 라벨
local function StatLabel(stat)
    local locale = GetLocale()
    local labels = {
        crit = (locale == "koKR") and "치명타:" or "Critical Strike:",
        haste = (locale == "koKR") and "가속:" or "Haste:",
        mastery = (locale == "koKR") and "특화:" or "Mastery:",
        vers = (locale == "koKR") and "유연성:" or "Versatility:",
        leech = (locale == "koKR") and "생기흡수:" or "Leech:",
        avoidance = (locale == "koKR") and "광역회피:" or "Avoidance:",
        speed = (locale == "koKR") and "이동속도:" or "Speed:",
    }
    return labels[stat] or stat
end

-- 풀 (재사용 객체)
local selfPool = {}
local inspPool = {}
local avgInspectFS = nil

--------------------------------------------------------------------------------
-- 1. 본인: 슬롯별 ilvl/인챈트/보석
--------------------------------------------------------------------------------
local function UpdateSelfSlot(button)
    if not ItemLevel.enabled then return end
    if UnitAffectingCombat("player") then return end
    if not button or type(button.GetID) ~= "function" then return end

    local db = ItemLevel.db
    local id = button:GetID()
    local link = GetInventoryItemLink("player", id)
    local d = selfPool[button]

    if not d then
        d = { gems = {} }
        d.ilvlFS = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        d.ilvlFS:SetFont(STANDARD_TEXT_FONT, db.selfIlvlSize, db.selfIlvlFlags)
        d.enchFS = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        d.enchFS:SetFont(STANDARD_TEXT_FONT, db.selfEnchantSize, db.selfEnchantFlags)
        selfPool[button] = d
    end

    -- 폰트 업데이트
    d.ilvlFS:SetFont(STANDARD_TEXT_FONT, db.selfIlvlSize, db.selfIlvlFlags)
    d.enchFS:SetFont(STANDARD_TEXT_FONT, db.selfEnchantSize, db.selfEnchantFlags)

    d.ilvlFS:Hide()
    d.enchFS:Hide()
    for _, tex in ipairs(d.gems) do
        tex:Hide()
    end

    if not link then return end

    -- 아이템 레벨 표시
    if db.showItemLevel then
        -- 12.0+ ItemLocation 기반 API 사용 (더 정확함)
        local ilvl = 0
        local itemLocation = ItemLocation:CreateFromEquipmentSlot(id)
        if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
            ilvl = C_Item.GetCurrentItemLevel(itemLocation) or GetDetailedItemLevelInfo(link) or 0
        else
            ilvl = GetDetailedItemLevelInfo(link) or 0
        end

        local _, _, quality = C_Item.GetItemInfo(link) -- [12.0.1] GetItemInfo → C_Item.GetItemInfo
        quality = quality or 1
        local col = ITEM_QUALITY_COLORS[quality].color

        d.ilvlFS:SetText(ilvl)
        d.ilvlFS:SetTextColor(col.r, col.g, col.b)
        d.ilvlFS:ClearAllPoints()

        -- 배치
        if id == SlotIDs.MainHandSlot or id == SlotIDs.SecondaryHandSlot then
            d.ilvlFS:SetPoint("TOP", button, "TOP", 0, 15)
            d.ilvlFS:SetJustifyH("CENTER")
        elseif IsRight(id) then
            d.ilvlFS:SetPoint("RIGHT", button, "LEFT", -5, -10)
            d.ilvlFS:SetJustifyH("RIGHT")
        else
            d.ilvlFS:SetPoint("LEFT", button, "RIGHT", 5, -10)
            d.ilvlFS:SetJustifyH("LEFT")
        end
        d.ilvlFS:Show()
    end

    -- 인챈트 표시
    if db.showEnchant and ENCHANTED_TOOLTIP_LINE then
        scanTip:ClearLines()
        scanTip:SetHyperlink(link)
        local ench = ""
        for i = 1, scanTip:NumLines() do
            local ln = _G["DDT_ItemLevelScanTipTextLeft" .. i]
            if ln then
                local text = ln:GetText() or ""
                local pattern = ENCHANTED_TOOLTIP_LINE:gsub("%%s", "(.+)")
                local m = text:match(pattern)
                if m then
                    ench = m:gsub(" [+%-]%d+", "")
                    break
                end
            end
        end

        if ench ~= "" then
            d.enchFS:SetText(ench)
            d.enchFS:SetTextColor(0, 1, 0)
            d.enchFS:ClearAllPoints()

            if id == SlotIDs.MainHandSlot then
                d.enchFS:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", 0, 0)
                d.enchFS:SetJustifyH("LEFT")
            elseif id == SlotIDs.SecondaryHandSlot then
                d.enchFS:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 0, 0)
                d.enchFS:SetJustifyH("RIGHT")
            elseif IsRight(id) then
                d.enchFS:SetPoint("RIGHT", button, "LEFT", -5, 8)
                d.enchFS:SetJustifyH("RIGHT")
            else
                d.enchFS:SetPoint("LEFT", button, "RIGHT", 5, 8)
                d.enchFS:SetJustifyH("LEFT")
            end
            d.enchFS:Show()
        end
    end

    -- 보석 아이콘
    if db.showGems then
        local cnt = C_Item.GetItemNumSockets and C_Item.GetItemNumSockets(link) or 0
        for i = 1, cnt do
            local tex = d.gems[i]
            if not tex then
                tex = button:CreateTexture(nil, "OVERLAY")
                tex:SetSize(db.selfGemSize, db.selfGemSize)
                d.gems[i] = tex
            end
            tex:SetSize(db.selfGemSize, db.selfGemSize)
            tex:ClearAllPoints()

            local gid = C_Item.GetItemGemID and C_Item.GetItemGemID(link, i)
            local icon = gid and C_Item.GetItemIconByID(gid) or "Interface\\ItemSocketingFrame\\UI-EmptySocket"
            tex:SetTexture(icon)

            local spacing = db.selfGemSpacing
            if id == SlotIDs.MainHandSlot or id == SlotIDs.SecondaryHandSlot then
                tex:SetPoint("TOP", d.ilvlFS, "BOTTOM",
                    (i - 1) * (db.selfGemSize + spacing) - ((cnt - 1) * (db.selfGemSize + spacing) / 2), -2)
            elseif IsRight(id) then
                local off = -((i - 1) * (db.selfGemSize + spacing) + 5)
                tex:SetPoint("RIGHT", d.ilvlFS, "LEFT", off, 0)
            else
                local off = (i - 1) * (db.selfGemSize + spacing) + 5
                tex:SetPoint("LEFT", d.ilvlFS, "RIGHT", off, 0)
            end
            tex:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- 2. 본인 평균 아이템 레벨
--------------------------------------------------------------------------------
local function UpdateCustomItemLevel()
    if not ItemLevel.enabled then return end
    local db = ItemLevel.db

    if not db.showAverageIlvl then return end

    local pane = CharacterStatsPane
    if not pane or not pane.ItemLevelFrame then return end

    local avg, eq = GetAverageItemLevel()
    eq = math.floor(eq * 100 + 0.5) / 100
    avg = math.floor(avg * 100 + 0.5) / 100

    pane.ItemLevelFrame.Value:SetFont(STANDARD_TEXT_FONT, db.selfAvgSize, db.selfIlvlFlags)
    if eq == avg then
        pane.ItemLevelFrame.Value:SetFormattedText("%.2f", avg)
    else
        pane.ItemLevelFrame.Value:SetFormattedText("%.2f/%.2f", eq, avg)
    end
    pane.ItemLevelFrame:Show()
end

--------------------------------------------------------------------------------
-- 3. 살펴보기 (상대방)
--------------------------------------------------------------------------------
local function EnsureInspectAverage()
    if avgInspectFS then return end
    local f = InspectPaperDollFrame
    if not f then return end

    local db = ItemLevel.db
    avgInspectFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    avgInspectFS:SetFont(STANDARD_TEXT_FONT, db.inspAvgSize, db.inspIlvlFlags)
    avgInspectFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -26)
end

local function UpdateInspectSlot(button, unit)
    if not ItemLevel.enabled then return end
    if UnitAffectingCombat("player") then return end
    if not button or not unit or UnitIsUnit(unit, "player") then return end

    local db = ItemLevel.db
    local id = button:GetID()
    local link = GetInventoryItemLink(unit, id)
    local d = inspPool[button]

    if not d then
        d = { gems = {} }
        d.ilvlFS = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        d.ilvlFS:SetFont(STANDARD_TEXT_FONT, db.inspIlvlSize, db.inspIlvlFlags)
        d.enchFS = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        d.enchFS:SetFont(STANDARD_TEXT_FONT, db.inspEnchantSize, db.inspEnchantFlags)
        inspPool[button] = d
    end

    -- 폰트 업데이트
    d.ilvlFS:SetFont(STANDARD_TEXT_FONT, db.inspIlvlSize, db.inspIlvlFlags)
    d.enchFS:SetFont(STANDARD_TEXT_FONT, db.inspEnchantSize, db.inspEnchantFlags)

    d.ilvlFS:Hide()
    d.enchFS:Hide()
    for _, tex in ipairs(d.gems) do
        tex:Hide()
    end

    if not link then return end

    -- 아이템 레벨 표시
    if db.showItemLevel then
        -- 살펴보기: 툴팁에서 실제 아이템 레벨 파싱 (더 정확함)
        local ilvl = 0
        if ITEM_LEVEL then
            scanTip:ClearLines()
            scanTip:SetHyperlink(link)
            for i = 2, min(5, scanTip:NumLines()) do
                local ln = _G["DDT_ItemLevelScanTipTextLeft" .. i]
                if ln then
                    local text = ln:GetText() or ""
                    -- "아이템 레벨 XXX" 또는 "Item Level XXX" 패턴 매칭
                    local lvl = text:match(ITEM_LEVEL:gsub("%%d", "(%%d+)"))
                    if lvl then
                        ilvl = tonumber(lvl) or 0
                        break
                    end
                end
            end
        end
        -- 폴백
        if ilvl == 0 then
            ilvl = GetDetailedItemLevelInfo(link) or 0
        end

        local _, _, quality = C_Item.GetItemInfo(link) -- [12.0.1] GetItemInfo → C_Item.GetItemInfo
        quality = quality or 1
        local col = ITEM_QUALITY_COLORS[quality].color

        d.ilvlFS:SetText(ilvl)
        d.ilvlFS:SetTextColor(col.r, col.g, col.b)
        d.ilvlFS:ClearAllPoints()

        if id == SlotIDs.MainHandSlot or id == SlotIDs.SecondaryHandSlot then
            d.ilvlFS:SetPoint("TOP", button, "TOP", 0, 15)
            d.ilvlFS:SetJustifyH("CENTER")
        elseif IsRight(id) then
            d.ilvlFS:SetPoint("RIGHT", button, "LEFT", -5, -10)
            d.ilvlFS:SetJustifyH("RIGHT")
        else
            d.ilvlFS:SetPoint("LEFT", button, "RIGHT", 5, -10)
            d.ilvlFS:SetJustifyH("LEFT")
        end
        d.ilvlFS:Show()
    end

    -- 인챈트 표시
    if db.showEnchant and ENCHANTED_TOOLTIP_LINE then
        scanTip:ClearLines()
        scanTip:SetHyperlink(link)
        local ench = ""
        for i = 1, scanTip:NumLines() do
            local ln = _G["DDT_ItemLevelScanTipTextLeft" .. i]
            if ln then
                local text = ln:GetText() or ""
                local pattern = ENCHANTED_TOOLTIP_LINE:gsub("%%s", "(.+)")
                local m = text:match(pattern)
                if m then
                    ench = m:gsub(" [+%-]%d+", "")
                    break
                end
            end
        end

        if ench ~= "" then
            d.enchFS:SetText(ench)
            d.enchFS:SetTextColor(0, 1, 0)
            d.enchFS:ClearAllPoints()

            if id == SlotIDs.MainHandSlot then
                d.enchFS:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", 0, 0)
                d.enchFS:SetJustifyH("LEFT")
            elseif id == SlotIDs.SecondaryHandSlot then
                d.enchFS:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 0, 0)
                d.enchFS:SetJustifyH("RIGHT")
            elseif IsRight(id) then
                d.enchFS:SetPoint("RIGHT", button, "LEFT", -5, 8)
                d.enchFS:SetJustifyH("RIGHT")
            else
                d.enchFS:SetPoint("LEFT", button, "RIGHT", 5, 8)
                d.enchFS:SetJustifyH("LEFT")
            end
            d.enchFS:Show()
        end
    end

    -- 보석 아이콘
    if db.showGems then
        local cnt = C_Item.GetItemNumSockets and C_Item.GetItemNumSockets(link) or 0
        for i = 1, cnt do
            local tex = d.gems[i]
            if not tex then
                tex = button:CreateTexture(nil, "OVERLAY")
                tex:SetSize(db.inspGemSize, db.inspGemSize)
                d.gems[i] = tex
            end
            tex:SetSize(db.inspGemSize, db.inspGemSize)
            tex:ClearAllPoints()

            local gid = C_Item.GetItemGemID and C_Item.GetItemGemID(link, i)
            local icon = gid and C_Item.GetItemIconByID(gid) or "Interface\\ItemSocketingFrame\\UI-EmptySocket"
            tex:SetTexture(icon)

            local spacing = db.inspGemSpacing
            if id == SlotIDs.MainHandSlot or id == SlotIDs.SecondaryHandSlot then
                tex:SetPoint("TOP", d.ilvlFS, "BOTTOM",
                    (i - 1) * (db.inspGemSize + spacing) - ((cnt - 1) * (db.inspGemSize + spacing) / 2), -2)
            elseif IsRight(id) then
                local off = -((i - 1) * (db.inspGemSize + spacing) + 5)
                tex:SetPoint("RIGHT", d.ilvlFS, "LEFT", off, 0)
            else
                local off = (i - 1) * (db.inspGemSize + spacing) + 5
                tex:SetPoint("LEFT", d.ilvlFS, "RIGHT", off, 0)
            end
            tex:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- 4. 강화 수치 (치명타/가속/특화/유연성/생기흡수/광역회피/이동속도)
--------------------------------------------------------------------------------
local function OverwriteCritStat(statFrame, unit)
    if not ItemLevel.enabled then return end
    if not ItemLevel.db.showEnhancedStats then return end
    if unit ~= "player" then statFrame:Hide() return end

    local rating = GetCombatRating(CR_CRIT_MELEE) or 0
    local percent = max(GetSpellCritChance(2), GetRangedCritChance(), GetCritChance()) or 0
    statFrame.Label:SetText(StatLabel("crit"))
    statFrame.Value:SetText(string.format("%s (%.2f%%)", Comma(rating), percent))
    statFrame.tooltip = string.format("%s %s (%.2f%%)", StatLabel("crit"), Comma(rating), percent)
    statFrame:Show()
end

local function OverwriteHasteStat(statFrame, unit)
    if not ItemLevel.enabled then return end
    if not ItemLevel.db.showEnhancedStats then return end
    if unit ~= "player" then statFrame:Hide() return end

    local rating = GetCombatRating(CR_HASTE_MELEE) or 0
    local percent = GetHaste() or 0
    statFrame.Label:SetText(StatLabel("haste"))
    statFrame.Value:SetText(string.format("%s (%.2f%%)", Comma(rating), percent))
    statFrame.tooltip = string.format("%s %s (%.2f%%)", StatLabel("haste"), Comma(rating), percent)
    statFrame:Show()
end

local function OverwriteMasteryStat(statFrame, unit)
    if not ItemLevel.enabled then return end
    if not ItemLevel.db.showEnhancedStats then return end
    if unit ~= "player" then statFrame:Hide() return end

    local rating = GetCombatRating(CR_MASTERY) or 0
    local percent = GetMasteryEffect() or 0
    statFrame.Label:SetText(StatLabel("mastery"))
    statFrame.Value:SetText(string.format("%s (%.2f%%)", Comma(rating), percent))
    statFrame.tooltip = string.format("%s %s (%.2f%%)", StatLabel("mastery"), Comma(rating), percent)
    statFrame:Show()
end

local function OverwriteVersStat(statFrame, unit)
    if not ItemLevel.enabled then return end
    if not ItemLevel.db.showEnhancedStats then return end
    if unit ~= "player" then statFrame:Hide() return end

    local rating = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0
    local percentAtk = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
    local percentDR = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN) or 0
    statFrame.Label:SetText(StatLabel("vers"))
    statFrame.Value:SetText(string.format("%s (%.2f%%, %.2f%%)", Comma(rating), percentAtk, percentDR))
    statFrame.tooltip = string.format("%s %s (%.2f%%, %.2f%%)", StatLabel("vers"), Comma(rating), percentAtk, percentDR)
    statFrame:Show()
end

local function OverwriteLeechStat(statFrame, unit)
    if not ItemLevel.enabled then return end
    if not ItemLevel.db.showEnhancedStats then return end
    if unit ~= "player" then statFrame:Hide() return end

    local rating = GetCombatRating(CR_LIFESTEAL) or 0
    local percent = GetLifesteal() or 0
    statFrame.Label:SetText(StatLabel("leech"))
    statFrame.Value:SetText(string.format("%s (%.2f%%)", Comma(rating), percent))
    statFrame.tooltip = string.format("%s %s (%.2f%%)", StatLabel("leech"), Comma(rating), percent)
    statFrame:Show()
end

local function OverwriteAvoidanceStat(statFrame, unit)
    if not ItemLevel.enabled then return end
    if not ItemLevel.db.showEnhancedStats then return end
    if unit ~= "player" then statFrame:Hide() return end

    local rating = GetCombatRating(CR_AVOIDANCE) or 0
    local percent = GetCombatRatingBonus(CR_AVOIDANCE) or 0
    statFrame.Label:SetText(StatLabel("avoidance"))
    statFrame.Value:SetText(string.format("%s (%.2f%%)", Comma(rating), percent))
    statFrame.tooltip = string.format("%s %s (%.2f%%)", StatLabel("avoidance"), Comma(rating), percent)
    statFrame:Show()
end

local function OverwriteSpeedStat(statFrame, unit)
    if not ItemLevel.enabled then return end
    if not ItemLevel.db.showEnhancedStats then return end
    if unit ~= "player" then statFrame:Hide() return end

    local percent = (select(2, GetUnitSpeed("player")) or 0) / 7 * 100
    statFrame.Label:SetText(StatLabel("speed"))
    statFrame.Value:SetText(string.format("%.2f%%", percent))
    statFrame.tooltip = string.format("%s %.2f%%", StatLabel("speed"), percent)
    statFrame:Show()
end

--------------------------------------------------------------------------------
-- 5. Hook 등록/해제
--------------------------------------------------------------------------------
local hooksRegistered = false

local function RegisterHooks()
    if hooksRegistered then return end
    hooksRegistered = true

    -- 본인 슬롯 업데이트
    if PaperDollItemSlotButton_Update then
        hooksecurefunc("PaperDollItemSlotButton_Update", UpdateSelfSlot)
    end

    -- 본인 평균 아이템 레벨
    if PaperDollFrame_UpdateStats then
        hooksecurefunc("PaperDollFrame_UpdateStats", UpdateCustomItemLevel)
    end

    -- 살펴보기 슬롯 업데이트 (WoW 12.0에서 제거됨)
    if InspectPaperDollItemSlotButton_Update then
        hooksecurefunc("InspectPaperDollItemSlotButton_Update", UpdateInspectSlot)
    end

    -- 강화 수치 (존재 여부 확인)
    if PaperDollFrame_SetCritChance then
        hooksecurefunc("PaperDollFrame_SetCritChance", OverwriteCritStat)
    end
    if PaperDollFrame_SetHaste then
        hooksecurefunc("PaperDollFrame_SetHaste", OverwriteHasteStat)
    end
    if PaperDollFrame_SetMastery then
        hooksecurefunc("PaperDollFrame_SetMastery", OverwriteMasteryStat)
    end
    if PaperDollFrame_SetVersatility then
        hooksecurefunc("PaperDollFrame_SetVersatility", OverwriteVersStat)
    end
    if PaperDollFrame_SetLifesteal then
        hooksecurefunc("PaperDollFrame_SetLifesteal", OverwriteLeechStat)
    end
    if PaperDollFrame_SetAvoidance then
        hooksecurefunc("PaperDollFrame_SetAvoidance", OverwriteAvoidanceStat)
    end
    if PaperDollFrame_SetSpeed then
        hooksecurefunc("PaperDollFrame_SetSpeed", OverwriteSpeedStat)
    end

    -- 살펴보기 프레임 이벤트
    if InspectFrame then
        InspectFrame:HookScript("OnShow", function(self)
            if not ItemLevel.enabled then return end
            if self.unit and self.unit ~= "player" then
                EnsureInspectAverage()
                NotifyInspect(self.unit)
            end
        end)
    end

    -- 오류 방지
    if InspectGuildFrame_Update then
        local orig = InspectGuildFrame_Update
        InspectGuildFrame_Update = function(self)
            if GetGuildInfo("inspect") then
                orig(self)
            end
        end
    end

    if InspectPVPFrame_Update then
        local orig = InspectPVPFrame_Update
        InspectPVPFrame_Update = function(self)
            if InspectFrame and InspectFrame.unit then
                pcall(orig, self)
            end
        end
    end
end

-- INSPECT_READY 이벤트 리스너
local listener = CreateFrame("Frame")
listener:RegisterEvent("INSPECT_READY")
listener:SetScript("OnEvent", function(_, _, guid)
    if not ItemLevel.enabled then return end

    local unit = InspectFrame and InspectFrame.unit
    if unit and UnitGUID(unit) == guid then
        EnsureInspectAverage()
        if avgInspectFS then
            local avg = C_PaperDollInfo.GetInspectItemLevel(unit) or 0
            avgInspectFS:SetText(string.format("%.2f", avg))
            avgInspectFS:Show()
        end
        for _, s in ipairs(SlotNames) do
            local btn = _G["Inspect" .. s]
            if btn then
                UpdateInspectSlot(btn, unit)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- 모듈 인터페이스
--------------------------------------------------------------------------------
function ItemLevel:OnInitialize()
    self.db = ns.db.profile.ItemLevel
    InitRightSide()
end

function ItemLevel:OnEnable()
    self.enabled = true
    RegisterHooks()

    -- 캐릭터 창이 열려있으면 업데이트
    if CharacterFrame and CharacterFrame:IsShown() then
        PaperDollFrame_UpdateStats()
        for _, s in ipairs(SlotNames) do
            local btn = _G["Character" .. s]
            if btn then
                UpdateSelfSlot(btn)
            end
        end
    end
end

function ItemLevel:OnDisable()
    self.enabled = false
    -- 표시 요소들 숨기기
    for _, d in pairs(selfPool) do
        if d.ilvlFS then d.ilvlFS:Hide() end
        if d.enchFS then d.enchFS:Hide() end
        for _, tex in ipairs(d.gems) do tex:Hide() end
    end
    for _, d in pairs(inspPool) do
        if d.ilvlFS then d.ilvlFS:Hide() end
        if d.enchFS then d.enchFS:Hide() end
        for _, tex in ipairs(d.gems) do tex:Hide() end
    end
    if avgInspectFS then
        avgInspectFS:Hide()
    end
end

function ItemLevel:Refresh()
    if not self.enabled then return end
    if CharacterFrame and CharacterFrame:IsShown() then
        PaperDollFrame_UpdateStats()
        for _, s in ipairs(SlotNames) do
            local btn = _G["Character" .. s]
            if btn then
                UpdateSelfSlot(btn)
            end
        end
    end
end

-- 모듈 등록
DDingToolKit:RegisterModule("ItemLevel", ItemLevel)
