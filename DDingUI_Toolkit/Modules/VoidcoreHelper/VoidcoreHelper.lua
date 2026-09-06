--[[
    DDingToolKit - VoidcoreHelper
    Advises on Nebulous Voidcore bonus rolls without touching protected Blizzard actions.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local Lib = LibStub("DDingUI-StyleLib-1.0")
local SOLID = Lib.Textures and Lib.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local FONT = Lib.Font and Lib.Font.path or "Fonts\\2002.TTF"

local VoidcoreHelper = {}
ns.VoidcoreHelper = VoidcoreHelper

local CONFIRMATION_KEY = "voidcore-instance-guard"
local MIN_KEYSTONE_LEVEL = 10
local RAID_HEROIC_CONTEXT = 5
local RAID_MYTHIC_CONTEXT = 6
local MYTHIC_KEYSTONE_CONTEXT = 16
local MAX_LOOT_ROWS = 12

local KNOWN_VOIDCORE_CURRENCIES = {
    [3418] = true,
    [3513] = true,
}

-- Midnight Season 2 bonus-roll source items. The prompt still works for unknown future sources.
local SOURCE_BY_ITEM = {
    [279618] = { kind = "dungeon", journalInstanceID = 1322, challengeModeID = 588, fallback = "Altar of Fangs" },
    [279620] = { kind = "dungeon", journalInstanceID = 1311, challengeModeID = 586, fallback = "Den of Nalorakk" },
    [279623] = { kind = "dungeon", journalInstanceID = 1304, challengeModeID = 587, fallback = "Murder Row" },
    [279619] = { kind = "dungeon", journalInstanceID = 1309, challengeModeID = 584, fallback = "The Blinding Vale" },
    [279625] = { kind = "dungeon", journalInstanceID = 1313, challengeModeID = 585, fallback = "Voidscar Arena" },
    [279621] = { kind = "dungeon", journalInstanceID = 1041, challengeModeID = 249, fallback = "Kings' Rest" },
    [279622] = { kind = "dungeon", journalInstanceID = 1202, challengeModeID = 399, fallback = "Ruby Life Pools" },
    [279624] = { kind = "dungeon", journalInstanceID = 1030, challengeModeID = 250, fallback = "Temple of Sethraliss" },
    [274708] = { kind = "raid", encounterID = 2849, fallback = "Nymrissa Wavecaller" },
    [278285] = { kind = "raid", encounterID = 2888, fallback = "Nek'zali" },
    [278283] = { kind = "raid", encounterID = 2874, fallback = "Entombed Sentinels" },
    [278286] = { kind = "raid", encounterID = 2894, fallback = "Lost Explorers" },
    [278287] = { kind = "raid", encounterID = 2882, fallback = "Vashnik" },
    [278288] = { kind = "raid", encounterID = 2871, fallback = "Sszorak" },
    [278289] = { kind = "raid", encounterID = 2887, fallback = "Twin Fangs" },
    [278290] = { kind = "raid", encounterID = 2883, fallback = "Coiled Altar" },
    [278284] = { kind = "raid", encounterID = 2895, fallback = "Ula'tek" },
}

local SOURCE_ORDER = {
    dungeon = { 279618, 279623, 279620, 279619, 279625, 279621, 279624, 279622 },
    raid = { 274708, 278285, 278283, 278286, 278287, 278288, 278289, 278290, 278284 },
}

local activeModule
local eventFrame = CreateFrame("Frame")

local function T(key, fallback)
    return (L and L[key]) or fallback
end

local function IsSecret(value)
    return (ns.IsSecretValue and ns.IsSecretValue(value))
        or (issecretvalue and issecretvalue(value))
        or false
end

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function SafeString(value)
    if IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

local function UnpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function PopupColors()
    return ns.UI and ns.UI.popupColors or {
        background = { 0.10, 0.10, 0.10, 0.985 },
        header = { 0.12, 0.12, 0.12, 1 },
        panel = { 0.075, 0.075, 0.08, 0.97 },
        input = { 0.045, 0.045, 0.05, 1 },
        hover = { 0.14, 0.14, 0.15, 0.96 },
        selected = { 0.10, 0.14, 0.15, 0.96 },
        border = { 0.30, 0.30, 0.32, 0.82 },
        borderSoft = { 0.25, 0.25, 0.25, 0.50 },
        separator = { 0.20, 0.20, 0.20, 0.40 },
        accent = { 0.16, 0.58, 0.68, 0.80 },
        accentText = { 0.42, 0.76, 0.82, 1 },
        text = { 0.85, 0.85, 0.85, 1 },
        textBright = { 1, 1, 1, 1 },
        textDim = { 0.60, 0.60, 0.60, 1 },
    }
end

local function SetBackdrop(frame, background, border)
    frame:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    frame:SetBackdropColor(UnpackColor(background))
    frame:SetBackdropBorderColor(UnpackColor(border))
end

local function AddFont(parent, size, color, text, layer)
    local fontString = parent:CreateFontString(nil, layer or "OVERLAY")
    fontString:SetFont(FONT, size, "")
    fontString:SetTextColor(UnpackColor(color))
    fontString:SetText(text or "")
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.9)
    return fontString
end

local function RequestItemData(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function GetItemDisplay(itemID)
    if not C_Item or not C_Item.GetItemInfo then
        return nil, nil
    end

    local ok, name, _, _, _, _, _, _, _, _, icon = pcall(C_Item.GetItemInfo, itemID)
    if not ok or IsSecret(name) or IsSecret(icon) then
        return nil, nil
    end
    if type(name) ~= "string" or name == "" then
        RequestItemData(itemID)
        name = nil
    end
    if type(icon) ~= "number" and C_Item.GetItemIconByID then
        local iconOK, result = pcall(C_Item.GetItemIconByID, itemID)
        if iconOK and not IsSecret(result) and type(result) == "number" then
            icon = result
        end
    end
    return name, icon
end

local function IsBISLootItem(itemID, specID, itemLink)
    if not C_Item or not C_Item.GetItemInfoInstant then return false end
    local ok, _, _, _, equipLoc, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, itemID)
    if not ok or IsSecret(equipLoc) or IsSecret(classID) or IsSecret(subClassID) then return false end
    if classID == nil or equipLoc == nil then
        RequestItemData(itemID)
        return false, true
    end
    local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    local armorClass = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
    local cosmeticSubclass = Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic or 5
    if classID ~= weaponClass and classID ~= armorClass then return false end
    if classID == armorClass and subClassID == cosmeticSubclass then return false end
    if type(equipLoc) ~= "string" or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then return false end

    if C_Item.IsItemDataCachedByID then
        local cacheOK, isCached = pcall(C_Item.IsItemDataCachedByID, itemID)
        if not cacheOK or IsSecret(isCached) then return false end
        if isCached ~= true then
            RequestItemData(itemID)
            return false, true
        end
    end

    if not C_Item.DoesItemContainSpec then return false end
    local classOK, _, _, playerClassID = pcall(UnitClass, "player")
    playerClassID = classOK and SafeNumber(playerClassID) or nil
    specID = SafeNumber(specID)
    if not playerClassID or not specID or specID <= 0 then return false end

    -- Use native class/spec eligibility instead of the optional per-item spec list.
    local specOK, isEligible = pcall(C_Item.DoesItemContainSpec, itemLink or itemID, playerClassID, specID)
    if not specOK or IsSecret(isEligible) then return false end
    if type(isEligible) ~= "boolean" then
        RequestItemData(itemID)
        return false, true
    end
    return isEligible
end

local function NormalizeItemName(text)
    text = SafeString(text)
    if not text then return nil end
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|cn[%w_]+:", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h%[(.-)%]|h", "%1")
    text = text:gsub("^%s*%-%s*", "")
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil end
    return text:lower()
end

local function ParseItemID(text)
    if type(text) ~= "string" then return nil end
    local itemID = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
    if not itemID or itemID < 1 then return nil end
    return math.floor(itemID)
end

local function GetClassSpecs()
    local specs = {}
    if not GetNumSpecializations or not C_SpecializationInfo or not C_SpecializationInfo.GetSpecializationInfo then
        return specs
    end

    local ok, count = pcall(GetNumSpecializations)
    count = ok and SafeNumber(count) or nil
    if not count then return specs end

    for index = 1, count do
        local infoOK, specID, name, _, icon = pcall(C_SpecializationInfo.GetSpecializationInfo, index)
        specID = infoOK and SafeNumber(specID) or nil
        name = infoOK and SafeString(name) or nil
        if specID and name then
            specs[#specs + 1] = {
                id = specID,
                name = name,
                icon = SafeNumber(icon) or 134400,
            }
        end
    end
    return specs
end

local function GetCurrentSpecID()
    if GetLootSpecialization then
        local ok, specID = pcall(GetLootSpecialization)
        specID = ok and SafeNumber(specID) or nil
        if specID and specID > 0 then return specID end
    end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        local ok, index = pcall(C_SpecializationInfo.GetSpecialization)
        index = ok and SafeNumber(index) or nil
        if index then
            local infoOK, specID = pcall(C_SpecializationInfo.GetSpecializationInfo, index)
            specID = infoOK and SafeNumber(specID) or nil
            if specID then return specID end
        end
    end
    return 0
end

local function GetSpecInfo(specID)
    for _, spec in ipairs(GetClassSpecs()) do
        if spec.id == specID then return spec end
    end
    return { id = specID, name = T("VCH_UNKNOWN_SPEC", "Unknown specialization"), icon = 134400 }
end

local function GetSourceName(sourceItemID)
    local source = SOURCE_BY_ITEM[sourceItemID]
    if source then
        if source.kind == "dungeon" and EJ_GetInstanceInfo then
            local ok, name = pcall(EJ_GetInstanceInfo, source.journalInstanceID)
            name = ok and SafeString(name) or nil
            if name and name ~= "" then return name, source.kind end
        elseif source.kind == "raid" and EJ_GetEncounterInfo then
            local ok, name = pcall(EJ_GetEncounterInfo, source.encounterID)
            name = ok and SafeString(name) or nil
            if name and name ~= "" then return name, source.kind end
        end
        return source.fallback, source.kind
    end

    local name = GetItemDisplay(sourceItemID)
    return name or T("VCH_UNKNOWN_SOURCE", "Unknown source"), nil
end

local function EnsureEncounterJournal()
    if EJ_SelectInstance and EJ_GetNumLoot and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
        return true
    end
    if InCombatLockdown and InCombatLockdown() then return false end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end
    return EJ_SelectInstance and EJ_GetNumLoot and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex
end

local function IsVoidcoreCurrency(currencyID)
    if KNOWN_VOIDCORE_CURRENCIES[currencyID] then return true end
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return false end

    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if not ok or IsSecret(info) or type(info) ~= "table" then return false end
    local name = SafeString(info.name)
    if not name then return false end
    name = name:lower()
    return name:find("voidcore", 1, true) ~= nil or name:find("공허핵", 1, true) ~= nil
end

local function FindVoidcorePrompt()
    if not GetSpellConfirmationPromptsInfo then return nil end
    local ok, prompts = pcall(GetSpellConfirmationPromptsInfo)
    if not ok or IsSecret(prompts) or type(prompts) ~= "table" then return nil end

    for _, entry in ipairs(prompts) do
        if not IsSecret(entry) and type(entry) == "table" then
            local currencyID = SafeNumber(entry.currencyID)
            if currencyID and IsVoidcoreCurrency(currencyID) then
                local sourceItemID = SafeNumber(entry.displayItemID)
                if sourceItemID then
                    return {
                        currencyID = currencyID,
                        sourceItemID = sourceItemID,
                        itemContext = SafeNumber(entry.itemContext) or 0,
                        keyLevel = SafeNumber(entry.treasureContextLevel) or 0,
                    }
                end
            end
        end
    end
    return nil
end

local function ExtractLootEntries(prompt, specID)
    if not C_TooltipInfo or not C_TooltipInfo.GetItemByID then return nil end

    local ok, data
    if prompt.itemContext == MYTHIC_KEYSTONE_CONTEXT then
        ok, data = pcall(C_TooltipInfo.GetItemByID, prompt.sourceItemID, nil, prompt.itemContext, prompt.keyLevel)
    else
        ok, data = pcall(C_TooltipInfo.GetItemByID, prompt.sourceItemID, nil, prompt.itemContext)
    end
    if not ok or IsSecret(data) or type(data) ~= "table" then return nil end
    if IsSecret(data.lines) or type(data.lines) ~= "table" then return nil end

    local entries = {}
    local seen = {}
    local loading = false
    local sourceItemsByName
    for _, line in ipairs(data.lines) do
        if not IsSecret(line) and type(line) == "table" then
            local rawText = SafeString(line.leftText)
            local prefixText = rawText and rawText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
            local plainName = NormalizeItemName(rawText)
            if rawText and plainName and prefixText:match("^%s*%-") then
                local hyperlink = SafeString(line.hyperlink) or rawText:match("|H(item:.-)|h")
                local itemID = SafeNumber(line.itemID) or ParseItemID(hyperlink) or ParseItemID(rawText)
                if not itemID then
                    if not sourceItemsByName then
                        sourceItemsByName = {}
                        local sourceItems, _, sourceLoading = VoidcoreHelper:GetSourceLoot(prompt.sourceItemID, specID)
                        loading = loading or not sourceItems or sourceLoading == true
                        for _, item in ipairs(sourceItems or {}) do
                            local name = NormalizeItemName(item.name)
                            if name then sourceItemsByName[name] = item end
                        end
                    end
                    local sourceItem = sourceItemsByName[plainName]
                    if sourceItem then
                        itemID, hyperlink = sourceItem.itemID, sourceItem.link
                    end
                    if not itemID then loading = true end
                end
                local isLootable, itemDataLoading = false, false
                if itemID then
                    isLootable, itemDataLoading = IsBISLootItem(itemID, specID, hyperlink)
                end
                if itemDataLoading then loading = true end
                if isLootable and not seen[itemID] then
                    seen[itemID] = true
                    entries[#entries + 1] = {
                        itemID = itemID,
                        name = plainName,
                        displayName = (rawText:gsub("^.-%-%s*", "")),
                    }
                end
            end
        end
    end
    return entries, loading
end

local function IsEligiblePrompt(prompt, sourceKind)
    if prompt.itemContext == MYTHIC_KEYSTONE_CONTEXT then
        local keyLevel = prompt.keyLevel
        if keyLevel < 1 and C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
            local ok, activeLevel = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
            keyLevel = ok and SafeNumber(activeLevel) or keyLevel
        end
        return keyLevel >= MIN_KEYSTONE_LEVEL, "dungeon", keyLevel
    end
    if prompt.itemContext == RAID_HEROIC_CONTEXT or prompt.itemContext == RAID_MYTHIC_CONTEXT then
        return true, "raid", 0
    end
    return false, sourceKind, prompt.keyLevel
end

function VoidcoreHelper:GetDB()
    if self.db then return self.db end
    ns.db.profile.VoidcoreHelper = ns.db.profile.VoidcoreHelper or {}
    self.db = ns.db.profile.VoidcoreHelper
    self.db.bisBySpec = self.db.bisBySpec or {}
    self.db.bisSourcesBySpec = self.db.bisSourcesBySpec or {}
    return self.db
end

function VoidcoreHelper:GetTargets(specID, create)
    local db = self:GetDB()
    local key = tostring(specID or 0)
    if create and type(db.bisBySpec[key]) ~= "table" then
        db.bisBySpec[key] = {}
    end
    return type(db.bisBySpec[key]) == "table" and db.bisBySpec[key] or {}
end

function VoidcoreHelper:GetTargetSources(specID, create)
    local db = self:GetDB()
    local key = tostring(specID or 0)
    if create and type(db.bisSourcesBySpec[key]) ~= "table" then
        db.bisSourcesBySpec[key] = {}
    end
    return type(db.bisSourcesBySpec[key]) == "table" and db.bisSourcesBySpec[key] or {}
end

function VoidcoreHelper:GetSourceLoot(sourceItemID, specID)
    self.lootCache = self.lootCache or {}
    local cacheKey = tostring(specID) .. ":" .. tostring(sourceItemID)
    if self.lootCache[cacheKey] then return self.lootCache[cacheKey] end
    if InCombatLockdown and InCombatLockdown() then return nil, nil, true end

    local source = SOURCE_BY_ITEM[sourceItemID]
    if not source or not EnsureEncounterJournal() then
        return nil, T("VCH_BIS_JOURNAL_ERROR", "The Encounter Journal could not be loaded.")
    end
    if EncounterJournal and EncounterJournal:IsShown() then
        return nil, T("VCH_BIS_CLOSE_JOURNAL", "Close the Encounter Journal and select the source again.")
    end

    local classOK, _, _, classID = pcall(UnitClass, "player")
    classID = classOK and SafeNumber(classID) or nil
    if not classID or not specID or specID == 0 then
        return nil, T("VCH_BIS_JOURNAL_ERROR", "The Encounter Journal could not be loaded.")
    end

    local previous = {
        difficulty = EJ_GetDifficulty and EJ_GetDifficulty() or nil,
        instanceID = EncounterJournal and SafeNumber(EncounterJournal.instanceID) or nil,
        encounterID = EncounterJournal and SafeNumber(EncounterJournal.encounterID) or nil,
        slotFilter = C_EncounterJournal.GetSlotFilter and C_EncounterJournal.GetSlotFilter() or nil,
    }
    if EJ_GetLootFilter then
        local previousClassID, previousSpecID = EJ_GetLootFilter()
        previous.classID = SafeNumber(previousClassID)
        previous.specID = SafeNumber(previousSpecID)
    end

    local journalInstanceID = source.journalInstanceID
    if source.kind == "raid" and EJ_GetEncounterInfo then
        local infoOK, _, _, _, _, _, result = pcall(EJ_GetEncounterInfo, source.encounterID)
        journalInstanceID = infoOK and SafeNumber(result) or nil
    end

    local items = {}
    local itemDataLoading = false
    self.readingSourceLoot = true
    local ok = journalInstanceID and pcall(function()
        if EJ_ClearSearch then EJ_ClearSearch() end
        if EJ_ResetLootFilter then EJ_ResetLootFilter() end
        EJ_SelectInstance(journalInstanceID)
        EJ_SetDifficulty(source.kind == "raid" and 16 or 23)
        if source.kind == "raid" then EJ_SelectEncounter(source.encounterID) end
        EJ_SetLootFilter(classID, specID)
        if C_EncounterJournal.ResetSlotFilter then C_EncounterJournal.ResetSlotFilter() end

        local count = SafeNumber(EJ_GetNumLoot()) or 0
        if EJ_IsLootListOutOfDate then
            itemDataLoading = EJ_IsLootListOutOfDate() == true
        else
            itemDataLoading = count == 0
        end
        local seen = {}
        for index = 1, count do
            local info = C_EncounterJournal.GetLootInfoByIndex(index)
            if not IsSecret(info) and type(info) == "table" then
                local itemID = SafeNumber(info.itemID)
                local slot = SafeString(info.slot) or ""
                local isLootable, loading = false, false
                if itemID then
                    isLootable, loading = IsBISLootItem(itemID, specID, SafeString(info.link))
                else
                    itemDataLoading = true
                end
                if loading then itemDataLoading = true end
                if isLootable and not seen[itemID] then
                    seen[itemID] = true
                    local name = SafeString(info.name)
                    local icon = SafeNumber(info.icon)
                    if not name or not icon then
                        local itemName, itemIcon = GetItemDisplay(itemID)
                        name = name or itemName
                        icon = icon or itemIcon
                    end
                    if not name then itemDataLoading = true end
                    items[#items + 1] = {
                        itemID = itemID,
                        name = name,
                        icon = icon,
                        slot = slot,
                        link = SafeString(info.link),
                    }
                end
            else
                itemDataLoading = true
            end
        end
    end)

    if previous.instanceID then
        pcall(EJ_SelectInstance, previous.instanceID)
        if previous.encounterID then pcall(EJ_SelectEncounter, previous.encounterID) end
    end
    if previous.difficulty then pcall(EJ_SetDifficulty, previous.difficulty) end
    if previous.classID ~= nil and EJ_SetLootFilter then
        pcall(EJ_SetLootFilter, previous.classID, previous.specID or 0)
    elseif EJ_ResetLootFilter then
        pcall(EJ_ResetLootFilter)
    end
    if previous.slotFilter ~= nil and C_EncounterJournal.SetSlotFilter then
        pcall(C_EncounterJournal.SetSlotFilter, previous.slotFilter)
    end
    self.readingSourceLoot = nil

    if not ok then
        return nil, T("VCH_BIS_JOURNAL_ERROR", "The Encounter Journal could not be loaded.")
    end
    table.sort(items, function(left, right)
        if left.slot == right.slot then return (left.name or "") < (right.name or "") end
        return left.slot < right.slot
    end)
    if not itemDataLoading and #items > 0 then self.lootCache[cacheKey] = items end
    return items, nil, itemDataLoading
end

function VoidcoreHelper:GetTargetSets(specID)
    local ids, names = {}, {}
    local loading = false
    for _, itemID in ipairs(self:GetTargets(specID, false)) do
        if type(itemID) == "number" then
            ids[itemID] = true
            local name = GetItemDisplay(itemID)
            name = NormalizeItemName(name)
            if name then
                names[name] = true
            else
                loading = true
            end
        end
    end
    return ids, names, loading
end

function VoidcoreHelper:ToggleTarget(specID, itemID, sourceItemID)
    local targets = self:GetTargets(specID, true)
    local sources = self:GetTargetSources(specID, true)
    for index, existingID in ipairs(targets) do
        if existingID == itemID then
            table.remove(targets, index)
            sources[tostring(itemID)] = nil
            self:RefreshBISFrame()
            self:RefreshCurrentPrompt()
            return
        end
    end

    targets[#targets + 1] = itemID
    sources[tostring(itemID)] = sourceItemID
    RequestItemData(itemID)
    self:RefreshBISFrame()
    self:RefreshCurrentPrompt()
end

function VoidcoreHelper:ClearTargets(specID)
    wipe(self:GetTargets(specID, true))
    wipe(self:GetTargetSources(specID, true))
    self:RefreshBISFrame()
    self:SetBISMessage(T("VCH_BIS_CLEARED", "All BIS targets for this specialization were cleared."), false)
    self:RefreshCurrentPrompt()
end

function VoidcoreHelper:SetBISMessage(text, isError)
    if not self.bisMessage then return end
    self.bisMessage:SetText(text or "")
    self.bisMessage:SetTextColor(isError and 1 or 0.35, isError and 0.35 or 0.85, isError and 0.35 or 0.55, 1)
end

function VoidcoreHelper:CreateBISFrame()
    if self.bisFrame then return self.bisFrame end
    local P = PopupColors()
    local frame = CreateFrame("Frame", "DDingToolKitVoidcoreBISFrame", UIParent, "BackdropTemplate")
    frame:SetSize(780, 560)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(180)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    SetBackdrop(frame, P.background, P.border)

    local header = frame:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    header:SetHeight(48)
    header:SetColorTexture(UnpackColor(P.header))

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    accent:SetColorTexture(UnpackColor(P.accent))

    local title = AddFont(frame, 18, P.textBright, T("VCH_BIS_TITLE", "Voidcore BIS Settings"))
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -16)

    local close = ns.ToolkitControls.CreateButton(frame, "MJToolkit", "X", function() frame:Hide() end, { width = 28, height = 26 })
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -11)

    frame.specButtons = {}
    for index = 1, 4 do
        local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
        button:SetHeight(34)
        SetBackdrop(button, P.input, P.borderSoft)
        button.label = AddFont(button, 12, P.text, "")
        button.label:SetPoint("CENTER")
        button:SetScript("OnClick", function(self)
            VoidcoreHelper.selectedSpecID = self.specID
            if frame.itemScroll then frame.itemScroll:SetVerticalScroll(0) end
            VoidcoreHelper:SetBISMessage("", false)
            VoidcoreHelper:RefreshBISFrame()
        end)
        button:SetScript("OnEnter", function(self)
            if self.specID ~= VoidcoreHelper.selectedSpecID then
                self:SetBackdropColor(UnpackColor(P.hover))
            end
        end)
        button:SetScript("OnLeave", function()
            VoidcoreHelper:RefreshSpecButtons()
        end)
        frame.specButtons[index] = button
    end

    frame.sourceKindButtons = {}
    local sourceKinds = {
        { id = "dungeon", label = T("VCH_BIS_DUNGEONS", "Dungeons") },
        { id = "raid", label = T("VCH_BIS_RAID_BOSSES", "Raid Bosses") },
    }
    for index, kind in ipairs(sourceKinds) do
        local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
        button:SetSize(110, 28)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 24 + ((index - 1) * 116), -104)
        button.kind = kind.id
        SetBackdrop(button, P.input, P.borderSoft)
        button.label = AddFont(button, 12, P.text, kind.label)
        button.label:SetPoint("CENTER")
        button:SetScript("OnClick", function(self)
            if VoidcoreHelper.selectedSourceKind == self.kind then return end
            VoidcoreHelper.selectedSourceKind = self.kind
            VoidcoreHelper.selectedSourceItemID = nil
            if frame.itemScroll then frame.itemScroll:SetVerticalScroll(0) end
            VoidcoreHelper:RefreshBISFrame()
        end)
        button:SetScript("OnEnter", function(self)
            if self.kind ~= VoidcoreHelper.selectedSourceKind then self:SetBackdropColor(UnpackColor(P.hover)) end
        end)
        button:SetScript("OnLeave", function() VoidcoreHelper:RefreshSourceButtons() end)
        frame.sourceKindButtons[index] = button
    end

    frame.sourceButtons = {}
    for index = 1, 9 do
        local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
        button:SetSize(226, 36)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -142 - ((index - 1) * 40))
        SetBackdrop(button, index % 2 == 0 and P.panel or P.input, P.borderSoft)
        button.label = AddFont(button, 12, P.text, "")
        button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -10, 0)
        button.label:SetJustifyH("LEFT")
        button.label:SetWordWrap(false)
        button:SetScript("OnClick", function(self)
            VoidcoreHelper.selectedSourceItemID = self.sourceItemID
            if frame.itemScroll then frame.itemScroll:SetVerticalScroll(0) end
            VoidcoreHelper:RefreshBISFrame()
        end)
        button:SetScript("OnEnter", function(self)
            if self.sourceItemID ~= VoidcoreHelper.selectedSourceItemID then self:SetBackdropColor(UnpackColor(P.hover)) end
        end)
        button:SetScript("OnLeave", function() VoidcoreHelper:RefreshSourceButtons() end)
        frame.sourceButtons[index] = button
    end

    frame.sourceHeader = AddFont(frame, 14, P.textBright, "")
    frame.sourceHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 274, -108)
    frame.sourceHeader:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -210, -108)
    frame.sourceHeader:SetJustifyH("LEFT")

    local clear = ns.ToolkitControls.CreateButton(frame, "MJToolkit", T("VCH_BIS_CLEAR", "Clear Current Spec"), function()
        VoidcoreHelper:ClearTargets(VoidcoreHelper.selectedSpecID)
    end, { width = 160, height = 28 })
    clear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -104)

    frame.specSummary = AddFont(frame, 12, P.textDim, "")
    frame.specSummary:SetPoint("TOPLEFT", frame, "TOPLEFT", 274, -134)

    self.bisMessage = AddFont(frame, 11, P.textDim, "")
    self.bisMessage:SetPoint("TOPLEFT", frame, "TOPLEFT", 274, -157)
    self.bisMessage:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -157)
    self.bisMessage:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 274, -180)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -42, 24)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(438, 1)
    scroll:SetScrollChild(content)
    frame.itemScroll = scroll
    frame.scrollContent = content
    frame.rows = {}

    self.bisFrame = frame
    table.insert(UISpecialFrames, frame:GetName())
    return frame
end

function VoidcoreHelper:RefreshSpecButtons()
    local frame = self.bisFrame
    if not frame then return end
    local P = PopupColors()
    local specs = GetClassSpecs()
    local found = false
    for _, spec in ipairs(specs) do
        if spec.id == self.selectedSpecID then found = true break end
    end
    if not found then
        self.selectedSpecID = GetCurrentSpecID()
        if self.selectedSpecID == 0 and specs[1] then self.selectedSpecID = specs[1].id end
    end

    local count = math.max(1, #specs)
    local width = math.floor((732 - ((count - 1) * 6)) / count)
    for index, button in ipairs(frame.specButtons) do
        local spec = specs[index]
        button:ClearAllPoints()
        if spec then
            button.specID = spec.id
            button:SetSize(width, 34)
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 24 + ((index - 1) * (width + 6)), -60)
            button.label:SetText(string.format("|T%s:16:16:0:0|t %s", spec.icon, spec.name))
            local selected = spec.id == self.selectedSpecID
            button:SetBackdropColor(UnpackColor(selected and P.selected or P.input))
            button:SetBackdropBorderColor(UnpackColor(selected and P.accent or P.borderSoft))
            button.label:SetTextColor(UnpackColor(selected and P.textBright or P.text))
            button:Show()
        else
            button.specID = nil
            button:Hide()
        end
    end
end

function VoidcoreHelper:RefreshSourceButtons()
    local frame = self.bisFrame
    if not frame then return end
    local P = PopupColors()
    if not SOURCE_ORDER[self.selectedSourceKind] then self.selectedSourceKind = "dungeon" end
    local order = SOURCE_ORDER[self.selectedSourceKind]
    local selectedFound = false
    for _, sourceItemID in ipairs(order) do
        if sourceItemID == self.selectedSourceItemID then selectedFound = true break end
    end
    if not selectedFound then self.selectedSourceItemID = order[1] end

    for _, button in ipairs(frame.sourceKindButtons) do
        local selected = button.kind == self.selectedSourceKind
        button:SetBackdropColor(UnpackColor(selected and P.selected or P.input))
        button:SetBackdropBorderColor(UnpackColor(selected and P.accent or P.borderSoft))
        button.label:SetTextColor(UnpackColor(selected and P.textBright or P.text))
    end

    for index, button in ipairs(frame.sourceButtons) do
        local sourceItemID = order[index]
        if sourceItemID then
            button.sourceItemID = sourceItemID
            button.label:SetText(GetSourceName(sourceItemID))
            local selected = sourceItemID == self.selectedSourceItemID
            button:SetBackdropColor(UnpackColor(selected and P.selected or (index % 2 == 0 and P.panel or P.input)))
            button:SetBackdropBorderColor(UnpackColor(selected and P.accent or P.borderSoft))
            button.label:SetTextColor(UnpackColor(selected and P.textBright or P.text))
            button:Show()
        else
            button.sourceItemID = nil
            button:Hide()
        end
    end
end

function VoidcoreHelper:GetBISRow(index)
    local frame = self.bisFrame
    local row = frame.rows[index]
    if row then return row end
    local P = PopupColors()

    row = CreateFrame("Button", nil, frame.scrollContent, "BackdropTemplate")
    row:SetSize(436, 40)
    SetBackdrop(row, index % 2 == 0 and P.panel or P.input, P.borderSoft)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = AddFont(row, 12, P.textBright, "")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -34, -6)
    row.name:SetJustifyH("LEFT")
    row.slot = AddFont(row, 10, P.textDim, "")
    row.slot:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
    row.checkBox = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.checkBox:SetSize(17, 17)
    row.checkBox:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    SetBackdrop(row.checkBox, P.input, P.border)
    row.check = row.checkBox:CreateTexture(nil, "ARTWORK")
    row.check:SetPoint("TOPLEFT", row.checkBox, "TOPLEFT", 3, -3)
    row.check:SetPoint("BOTTOMRIGHT", row.checkBox, "BOTTOMRIGHT", -3, 3)
    row.check:SetColorTexture(UnpackColor(P.accentText))
    row:SetScript("OnClick", function(self)
        if self.itemID then
            VoidcoreHelper:ToggleTarget(VoidcoreHelper.selectedSpecID, self.itemID, VoidcoreHelper.selectedSourceItemID)
        end
    end)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(UnpackColor(P.hover))
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(UnpackColor(self.selected and P.selected or (self.rowIndex % 2 == 0 and P.panel or P.input)))
        GameTooltip:Hide()
    end)
    frame.rows[index] = row
    return row
end

function VoidcoreHelper:RefreshBISFrame()
    local frame = self.bisFrame
    if not frame or not frame:IsShown() then return end
    self:RefreshSpecButtons()
    self:RefreshSourceButtons()

    local spec = GetSpecInfo(self.selectedSpecID)
    local targets = self:GetTargets(self.selectedSpecID, false)
    frame.specSummary:SetText(string.format(T("VCH_BIS_SPEC_FORMAT", "%s BIS targets: %d"), spec.name, #targets))
    frame.sourceHeader:SetText(GetSourceName(self.selectedSourceItemID))

    local targetSet = {}
    for _, itemID in ipairs(targets) do targetSet[itemID] = true end
    local items, errorText, loading = self:GetSourceLoot(self.selectedSourceItemID, self.selectedSpecID)
    items = items or {}
    local sources = self:GetTargetSources(self.selectedSpecID, true)
    for _, item in ipairs(items) do
        local itemKey = tostring(item.itemID)
        if targetSet[item.itemID] and not sources[itemKey] then
            sources[itemKey] = self.selectedSourceItemID
        end
    end
    local loadingText = loading and (RETRIEVING_ITEM_INFO or "Loading item information...")
    self:SetBISMessage(errorText or loadingText or T("VCH_BIS_PICK_HELP", "Select a source, then check your BIS items."), errorText ~= nil)

    local P = PopupColors()
    for index, item in ipairs(items) do
        local row = self:GetBISRow(index)
        local name, icon = item.name, item.icon
        if not name or not icon then
            local loadedName, loadedIcon = GetItemDisplay(item.itemID)
            name = name or loadedName
            icon = icon or loadedIcon
        end
        row.itemID = item.itemID
        row.rowIndex = index
        row.selected = targetSet[item.itemID] == true
        row.icon:SetTexture(icon or 134400)
        row.name:SetText(name or RETRIEVING_ITEM_INFO or "Loading item information...")
        row.slot:SetText(item.slot or "")
        row.check:SetShown(row.selected)
        row:SetBackdropColor(UnpackColor(row.selected and P.selected or (index % 2 == 0 and P.panel or P.input)))
        row:SetBackdropBorderColor(UnpackColor(row.selected and P.accent or P.borderSoft))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 0, -((index - 1) * 44))
        row:Show()
    end
    for index = #items + 1, #frame.rows do
        frame.rows[index]:Hide()
    end

    if not frame.empty then
        frame.empty = AddFont(frame.scrollContent, 12, P.textDim, "")
        frame.empty:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", 4, -12)
    end
    frame.empty:SetText(errorText or loadingText or T("VCH_BIS_NO_LOOT", "No loot is listed for this specialization."))
    frame.empty:SetShown(#items == 0)
    frame.scrollContent:SetHeight(math.max(320, #items * 44))
end

function VoidcoreHelper:OpenBISSettings()
    self:GetDB()
    self.lootCache = nil
    EnsureEncounterJournal()
    local frame = self:CreateBISFrame()
    self.selectedSpecID = GetCurrentSpecID()
    self.selectedSourceKind = SOURCE_ORDER[self.selectedSourceKind] and self.selectedSourceKind or "dungeon"
    self:SetBISMessage("", false)
    frame:Show()
    frame:Raise()
    self:RefreshBISFrame()
end

function VoidcoreHelper:CreateAdvisorFrame()
    if self.advisorFrame then return self.advisorFrame end
    local P = PopupColors()
    local frame = CreateFrame("Frame", "DDingToolKitVoidcoreAdvisorFrame", UIParent, "BackdropTemplate")
    frame:SetSize(390, 180)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(170)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    SetBackdrop(frame, P.background, P.border)

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    accent:SetColorTexture(UnpackColor(P.accent))

    frame.title = AddFont(frame, 16, P.textBright, T("VCH_TITLE", "Voidcore Helper"))
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.source = AddFont(frame, 12, P.text, "")
    frame.source:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -10)
    frame.spec = AddFont(frame, 11, P.textDim, "")
    frame.spec:SetPoint("TOPLEFT", frame.source, "BOTTOMLEFT", 0, -5)
    frame.status = AddFont(frame, 16, P.textBright, "")
    frame.status:SetPoint("TOPLEFT", frame.spec, "BOTTOMLEFT", 0, -11)
    frame.status:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    frame.status:SetJustifyH("LEFT")
    frame.chance = AddFont(frame, 12, P.text, "")
    frame.chance:SetPoint("TOPLEFT", frame.status, "BOTTOMLEFT", 0, -6)
    frame.listTitle = AddFont(frame, 11, P.accentText, T("VCH_REMAINING_LOOT", "Remaining loot"))
    frame.listTitle:SetPoint("TOPLEFT", frame.chance, "BOTTOMLEFT", 0, -10)
    frame.rows = {}
    for index = 1, MAX_LOOT_ROWS do
        local row = AddFont(frame, 11, P.text, "")
        row:SetPoint("TOPLEFT", frame.listTitle, "BOTTOMLEFT", 0, -4 - ((index - 1) * 16))
        row:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        row:SetJustifyH("LEFT")
        frame.rows[index] = row
    end
    frame.note = AddFont(frame, 10, P.textDim, T("VCH_MANUAL_NOTE", "Use the Blizzard confirmation buttons directly."))
    frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 10)
    frame.promptCheckElapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.promptCheckElapsed = self.promptCheckElapsed + elapsed
        if self.promptCheckElapsed < 0.1 then return end
        self.promptCheckElapsed = 0
        if not FindVoidcorePrompt() then VoidcoreHelper:HideAdvisor() end
    end)
    frame:Hide()

    self.advisorFrame = frame
    return frame
end

function VoidcoreHelper:AnchorAdvisor()
    local frame = self:CreateAdvisorFrame()
    frame:ClearAllPoints()
    if BonusRollFrame and BonusRollFrame:IsShown() then
        frame:SetPoint("TOPLEFT", BonusRollFrame, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
    end
end

function VoidcoreHelper:IsGuardActive()
    local db = self:GetDB()
    if not db.guardNonTargets then return false end
    if not db.entryPrompt then return true end
    return self.sessionGuard == true
end

local function AnalyzePromptTargets(self, prompt, specID)
    local targetIDs, targetNames, targetDataLoading = self:GetTargetSets(specID)
    local lootEntries, lootDataLoading = ExtractLootEntries(prompt, specID)
    local targetCount = 0
    if lootEntries then
        for _, entry in ipairs(lootEntries) do
            entry.isTarget = (entry.itemID and targetIDs[entry.itemID]) or targetNames[entry.name] or false
            if entry.isTarget then targetCount = targetCount + 1 end
        end
    end
    return lootEntries, #self:GetTargets(specID, false), targetCount, targetDataLoading or lootDataLoading
end

local function GetStoredSourceTargetState(self, specID, sourceItemID)
    local targets = self:GetTargets(specID, false)
    if #targets == 0 then return false, false end

    local sources = self:GetTargetSources(specID, false)
    local complete = true
    for _, itemID in ipairs(targets) do
        local storedSourceID = sources[tostring(itemID)]
        if storedSourceID == sourceItemID then return true, true end
        if type(storedSourceID) ~= "number" then complete = false end
    end
    return false, complete
end

function VoidcoreHelper:TryAutoDecline(spellID, prompt)
    if not spellID or not prompt or not self:IsGuardActive() or not DeclineSpellConfirmationPrompt then return false end

    local _, sourceKind = GetSourceName(prompt.sourceItemID)
    local eligible = IsEligiblePrompt(prompt, sourceKind)
    if not eligible then
        DeclineSpellConfirmationPrompt(spellID)
        return true
    end

    local specID = GetCurrentSpecID()
    local hasStoredTarget, sourceMapComplete = GetStoredSourceTargetState(self, specID, prompt.sourceItemID)
    if SOURCE_BY_ITEM[prompt.sourceItemID] and sourceMapComplete and not hasStoredTarget then
        DeclineSpellConfirmationPrompt(spellID)
        return true
    end

    local lootEntries, configuredTargetCount, targetCount, targetDataLoading = AnalyzePromptTargets(self, prompt, specID)
    if configuredTargetCount == 0 then
        DeclineSpellConfirmationPrompt(spellID)
        return true
    end
    if lootEntries and #lootEntries > 0 and not targetDataLoading and targetCount == 0 then
        DeclineSpellConfirmationPrompt(spellID)
        return true
    end
    return false
end

function VoidcoreHelper:RenderPrompt(prompt)
    local db = self:GetDB()
    if db.showAdvisor == false then return true end

    local frame = self:CreateAdvisorFrame()
    local sourceName, sourceKind = GetSourceName(prompt.sourceItemID)
    local eligible, resolvedKind, keyLevel = IsEligiblePrompt(prompt, sourceKind)
    local specID = GetCurrentSpecID()
    local spec = GetSpecInfo(specID)
    local lootEntries, configuredTargetCount, targetCount, targetDataLoading = AnalyzePromptTargets(self, prompt, specID)

    frame.source:SetText(string.format(T("VCH_SOURCE_FORMAT", "Source: %s"), sourceName))
    frame.spec:SetText(string.format(T("VCH_SPEC_FORMAT", "Loot specialization: %s"), spec.name))

    local statusText
    local statusColor
    if not eligible then
        if resolvedKind == "dungeon" then
            statusText = string.format(T("VCH_STATUS_LOW_KEY", "Not recommended: below +%d"), MIN_KEYSTONE_LEVEL)
        else
            statusText = T("VCH_STATUS_RAID_DIFFICULTY", "Not recommended: not Heroic/Mythic")
        end
        statusColor = { 1, 0.42, 0.32, 1 }
    elseif configuredTargetCount == 0 then
        statusText = T("VCH_STATUS_NO_BIS", "Set BIS targets first")
        statusColor = { 1, 0.78, 0.24, 1 }
    elseif not lootEntries or #lootEntries == 0 or (targetDataLoading and targetCount == 0) then
        statusText = T("VCH_STATUS_LOADING", "Loading remaining loot...")
        statusColor = { 1, 0.78, 0.24, 1 }
    elseif targetCount > 0 then
        statusText = T("VCH_STATUS_RECOMMENDED", "Recommended source")
        statusColor = { 0.35, 1, 0.55, 1 }
    elseif self:IsGuardActive() then
        statusText = T("VCH_STATUS_GUARDED", "No BIS remains: do not use")
        statusColor = { 1, 0.30, 0.30, 1 }
    else
        statusText = T("VCH_STATUS_NO_TARGET", "No BIS remains")
        statusColor = { 1, 0.55, 0.30, 1 }
    end
    frame.status:SetText(statusText)
    frame.status:SetTextColor(UnpackColor(statusColor))

    local totalCount = lootEntries and #lootEntries or 0
    if totalCount > 0 and not targetDataLoading then
        local percent = (targetCount / totalCount) * 100
        frame.chance:SetText(string.format(T("VCH_CHANCE_FORMAT", "Estimated chance: %d/%d (%.1f%%)"), targetCount, totalCount, percent))
    else
        frame.chance:SetText(T("VCH_CHANCE_UNAVAILABLE", "Estimated chance: unavailable"))
    end

    local visibleRows = 0
    if db.showLootTable ~= false and lootEntries then
        for index, entry in ipairs(lootEntries) do
            if index > MAX_LOOT_ROWS then break end
            visibleRows = index
            local prefix = entry.isTarget and "|cff59ff8cBIS|r  " or "|cff777777- |r"
            frame.rows[index]:SetText(prefix .. (entry.displayName or entry.name))
            frame.rows[index]:SetTextColor(entry.isTarget and 0.82 or 0.78, entry.isTarget and 1 or 0.78, entry.isTarget and 0.86 or 0.78, 1)
            frame.rows[index]:Show()
        end
    end
    for index = visibleRows + 1, MAX_LOOT_ROWS do
        frame.rows[index]:Hide()
    end
    frame.listTitle:SetShown(db.showLootTable ~= false)

    local listHeight = db.showLootTable ~= false and math.max(1, visibleRows) * 16 or 0
    frame:SetHeight(158 + listHeight + 28)
    frame.note:SetText(keyLevel and keyLevel > 0
        and string.format(T("VCH_KEY_NOTE", "+%d / equal-chance estimate / choose manually"), keyLevel)
        or T("VCH_MANUAL_NOTE", "Equal-chance estimate; use the Blizzard confirmation buttons directly."))
    self:AnchorAdvisor()
    frame:Show()
    return lootEntries ~= nil and #lootEntries > 0 and not targetDataLoading
end

function VoidcoreHelper:RefreshCurrentPrompt()
    if self.currentPrompt and self.advisorFrame and self.advisorFrame:IsShown() then
        self:RenderPrompt(self.currentPrompt)
    end
end

function VoidcoreHelper:QueuePromptScan()
    self.promptToken = (self.promptToken or 0) + 1
    local token = self.promptToken
    local scan
    scan = function(attempt)
        if activeModule ~= self or token ~= self.promptToken then return end
        local prompt = FindVoidcorePrompt()
        if prompt then
            self.currentPrompt = prompt
            local ready = self:RenderPrompt(prompt)
            if not ready and attempt < 6 then
                C_Timer.After(0.15, function() scan(attempt + 1) end)
            end
        elseif attempt < 6 then
            C_Timer.After(0.15, function() scan(attempt + 1) end)
        end
    end
    C_Timer.After(0, function() scan(1) end)
end

function VoidcoreHelper:HideAdvisor()
    self.currentPrompt = nil
    self.promptToken = (self.promptToken or 0) + 1
    if self.advisorFrame then self.advisorFrame:Hide() end
end

local function GetCurrentInstance()
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok or IsSecret(inInstance) or IsSecret(instanceType) then return nil end
    if inInstance ~= true or (instanceType ~= "party" and instanceType ~= "raid") then return nil end

    local infoOK, name, _, difficultyID, difficultyName, _, _, _, instanceID = pcall(GetInstanceInfo)
    if not infoOK or IsSecret(name) or IsSecret(difficultyID) or IsSecret(difficultyName) or IsSecret(instanceID) then
        return nil
    end
    name = SafeString(name) or T("VCH_UNKNOWN_INSTANCE", "Current instance")
    difficultyID = SafeNumber(difficultyID) or 0
    instanceID = SafeNumber(instanceID) or name
    local displayName = SafeString(difficultyName)
    displayName = displayName and displayName ~= "" and (name .. " - " .. displayName) or name
    return tostring(instanceID), displayName
end

function VoidcoreHelper:EvaluateInstance()
    local db = self:GetDB()
    local key, displayName = GetCurrentInstance()
    if not key then
        self.currentInstanceKey = nil
        self.sessionGuard = nil
        ns.UI:HideConfirmation(CONFIRMATION_KEY)
        return
    end
    if self.currentInstanceKey == key then return end

    self.currentInstanceKey = key
    self.sessionGuard = db.entryPrompt and nil or db.guardNonTargets == true
    ns.UI:HideConfirmation(CONFIRMATION_KEY)
    if db.entryPrompt and db.guardNonTargets then
        ns.UI:ShowConfirmation(CONFIRMATION_KEY, {
            text = string.format(
                T("VCH_ENTRY_CONFIRM", "%s\n\nAutomatically decline Voidcore bonus loot when no configured BIS remains or the difficulty is ineligible?"),
                displayName
            ),
            acceptText = T("VCH_ENTRY_ENABLE", "Enable auto-decline"),
            cancelText = NO,
            onAccept = function() VoidcoreHelper.sessionGuard = true end,
            onCancel = function() VoidcoreHelper.sessionGuard = false end,
        })
    end
end

function VoidcoreHelper:ApplySettings()
    local db = self:GetDB()
    if db.showAdvisor == false then
        self:HideAdvisor()
    elseif BonusRollFrame and BonusRollFrame:IsShown() and activeModule == self then
        self:QueuePromptScan()
    end
    if not db.entryPrompt or not db.guardNonTargets then
        ns.UI:HideConfirmation(CONFIRMATION_KEY)
        self.sessionGuard = db.guardNonTargets == true
    else
        self.currentInstanceKey = nil
        C_Timer.After(0, function()
            if activeModule == VoidcoreHelper then VoidcoreHelper:EvaluateInstance() end
        end)
    end
    self:RefreshCurrentPrompt()
end

function VoidcoreHelper:OnInitialize()
    self:GetDB()
end

function VoidcoreHelper:OnEnable()
    activeModule = self
    C_Timer.After(1, function()
        if activeModule == self then self:EvaluateInstance() end
    end)
end

function VoidcoreHelper:OnDisable()
    if activeModule == self then activeModule = nil end
    ns.UI:HideConfirmation(CONFIRMATION_KEY)
    self:HideAdvisor()
    if self.bisFrame then self.bisFrame:Hide() end
    self.currentInstanceKey = nil
    self.sessionGuard = nil
end

eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
eventFrame:RegisterEvent("BONUS_ROLL_ACTIVATE")
eventFrame:RegisterEvent("BONUS_ROLL_DEACTIVATE")
eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT"
        or event == "EJ_LOOT_DATA_RECIEVED" or event == "PLAYER_REGEN_ENABLED" then
        if VoidcoreHelper.readingSourceLoot then return end
        VoidcoreHelper.lootCache = nil
        local frame = VoidcoreHelper.bisFrame
        if not (frame and frame:IsShown()) and not VoidcoreHelper.currentPrompt then return end
        if VoidcoreHelper.lootRefreshPending then return end
        VoidcoreHelper.lootRefreshPending = true
        C_Timer.After(0, function()
            VoidcoreHelper.lootRefreshPending = nil
            VoidcoreHelper:RefreshBISFrame()
            if activeModule then activeModule:RefreshCurrentPrompt() end
        end)
        return
    end

    local self = activeModule
    if not self then return end
    if event == "SPELL_CONFIRMATION_PROMPT" then
        local spellID, _, _, _, currencyID, _, _, sourceItemID, itemContext, keyLevel = ...
        spellID = SafeNumber(spellID)
        currencyID = SafeNumber(currencyID)
        sourceItemID = SafeNumber(sourceItemID)
        if spellID and currencyID and sourceItemID and IsVoidcoreCurrency(currencyID) then
            local prompt = {
                currencyID = currencyID,
                sourceItemID = sourceItemID,
                itemContext = SafeNumber(itemContext) or 0,
                keyLevel = SafeNumber(keyLevel) or 0,
            }
            if self:TryAutoDecline(spellID, prompt) then return end
        end
        self:QueuePromptScan()
    elseif event == "BONUS_ROLL_ACTIVATE" then
        self:QueuePromptScan()
    elseif event == "BONUS_ROLL_DEACTIVATE" or event == "BONUS_ROLL_RESULT" then
        self:HideAdvisor()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "CHALLENGE_MODE_START" then
        C_Timer.After(0.5, function()
            if activeModule == self then self:EvaluateInstance() end
        end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LOOT_SPEC_UPDATED" then
        self.selectedSpecID = GetCurrentSpecID()
        self:RefreshBISFrame()
        self:RefreshCurrentPrompt()
    end
end)

DDingToolKit:RegisterModule("VoidcoreHelper", VoidcoreHelper)
