--[[
    DDingToolKit - RaidLootPass Module
    Raid-instance scoped pass-roll automation after explicit approval.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: "

local RaidLootPass = {}
ns.RaidLootPass = RaidLootPass

local PASS_ROLL_TYPE = LOOT_ROLL_TYPE_PASS or 0
local POPUP_NAME = "DDINGTOOLKIT_RAID_LOOT_PASS_CONFIRM"

local DECISION_PASS = 1
local DECISION_PROTECT = 2
local DECISION_WAIT = 3

local ITEM_CLASS_RECIPE = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
local ITEM_CLASS_QUEST = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
local ITEM_CLASS_MISC = Enum and Enum.ItemClass and Enum.ItemClass.Miscellaneous or 15
local ITEM_CLASS_BATTLEPET = Enum and Enum.ItemClass and Enum.ItemClass.Battlepet or 17
local ITEM_CLASS_HOUSING = Enum and Enum.ItemClass and Enum.ItemClass.Housing or 20
local ITEM_SUBCLASS_COMPANION_PET = Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.CompanionPet or 2
local ITEM_SUBCLASS_MOUNT = Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Mount or 5
local ITEM_SUBCLASS_DECOR = Enum and Enum.ItemHousingSubclass and Enum.ItemHousingSubclass.Decor or 0

local CLASSIFICATION_RETRY_DELAYS = { 0.15, 0.35, 0.75, 1.5, 3, 5 }
local PASS_RETRY_DELAYS = { 0.2, 0.7 }
local PROTECTION_KEYS = {
    "protectRecipes",
    "protectToys",
    "protectMounts",
    "protectPets",
    "protectAppearanceUnlocks",
    "protectHousingDecor",
    "protectQuestItems",
}

local eventFrame
local currentInstanceKey
local currentInstanceName
local popupInstanceKey
local instanceDecisions = {}
local pendingRolls = {}
local passedRolls = {}
local protectedRolls = {}

local function T(key, fallback)
    return (L and L[key]) or fallback
end

local function IsSecretValue(value)
    return (ns.IsSecretValue and ns.IsSecretValue(value))
        or (issecretvalue and issecretvalue(value))
        or false
end

local function IsRaidLeader()
    local ok, isLeader = pcall(UnitIsGroupLeader, "player")
    if not ok or IsSecretValue(isLeader) then
        return true
    end
    return isLeader == true
end

local function GetCurrentRaidInstance()
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok or IsSecretValue(inInstance) or IsSecretValue(instanceType) then
        return nil
    end
    if inInstance ~= true or instanceType ~= "raid" then
        return nil
    end

    local raidOK, inRaid = pcall(IsInRaid)
    if not raidOK or IsSecretValue(inRaid) or inRaid ~= true then
        return nil
    end
    if IsRaidLeader() then
        return nil
    end

    local infoOK, name, _, difficultyID, difficultyName, _, _, _, instanceMapID = pcall(GetInstanceInfo)
    if not infoOK
        or IsSecretValue(name)
        or IsSecretValue(difficultyID)
        or IsSecretValue(difficultyName)
        or IsSecretValue(instanceMapID)
    then
        return nil
    end

    name = name or T("RAIDLOOTPASS_UNKNOWN_INSTANCE", "this instance")
    local key = tostring(instanceMapID or name) .. ":" .. tostring(difficultyID or 0)
    local displayName = difficultyName and difficultyName ~= "" and (name .. " - " .. difficultyName) or name
    return key, displayName
end

local function GetRollItemLink(rollID)
    if not GetLootRollItemLink then
        return nil
    end

    local ok, itemLink = pcall(GetLootRollItemLink, rollID)
    if not ok or IsSecretValue(itemLink) or type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end
    return itemLink
end

local function GetRollName(rollID)
    local name
    local count

    if GetLootRollItemInfo then
        local ok, _, resultName, resultCount = pcall(GetLootRollItemInfo, rollID)
        if ok then
            if not IsSecretValue(resultName) and type(resultName) == "string" and resultName ~= "" then
                name = resultName
            end
            if not IsSecretValue(resultCount) and type(resultCount) == "number" then
                count = resultCount
            end
        end
    end

    name = name or GetRollItemLink(rollID)
    if name and count and count > 1 then
        return string.format("%s x%d", name, count)
    end
    return name or ("roll " .. tostring(rollID))
end

local function RollStillActive(rollID)
    if not GetLootRollTimeLeft then
        return true
    end

    local ok, timeLeft = pcall(GetLootRollTimeLeft, rollID)
    if not ok or IsSecretValue(timeLeft) or type(timeLeft) ~= "number" then
        return true
    end
    return timeLeft > 0
end

local function RequestItemData(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function GetItemBasics(itemLink)
    if not C_Item or not C_Item.GetItemInfoInstant then
        return nil
    end

    local ok, itemID, itemType, itemSubType, equipLoc, icon, classID, subClassID = pcall(C_Item.GetItemInfoInstant, itemLink)
    if not ok
        or IsSecretValue(itemID)
        or IsSecretValue(equipLoc)
        or IsSecretValue(classID)
        or IsSecretValue(subClassID)
        or type(itemID) ~= "number"
        or type(classID) ~= "number"
    then
        return nil
    end

    return {
        itemID = itemID,
        equipLoc = type(equipLoc) == "string" and equipLoc or "",
        classID = classID,
        subClassID = type(subClassID) == "number" and subClassID or -1,
    }
end

local function IsItemDataReady(itemID)
    if not C_Item or not C_Item.IsItemDataCachedByID then
        return true
    end

    local ok, isCached = pcall(C_Item.IsItemDataCachedByID, itemID)
    if not ok or IsSecretValue(isCached) then
        return false
    end
    if isCached ~= true then
        RequestItemData(itemID)
        return false
    end
    return true
end

local function IsToyItem(itemID)
    if not C_ToyBox or not C_ToyBox.GetToyInfo then
        return nil
    end

    local ok, toyItemID = pcall(C_ToyBox.GetToyInfo, itemID)
    if not ok or IsSecretValue(toyItemID) then
        return nil
    end
    return toyItemID ~= nil
end

local function IsMountItem(itemID, classID, subClassID)
    if classID == ITEM_CLASS_MISC and subClassID == ITEM_SUBCLASS_MOUNT then
        return true
    end
    if not C_MountJournal or not C_MountJournal.GetMountFromItem then
        return false
    end

    local ok, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
    if not ok or IsSecretValue(mountID) then
        return nil
    end
    return mountID ~= nil
end

local function IsPetItem(itemID, classID, subClassID)
    if classID == ITEM_CLASS_BATTLEPET
        or (classID == ITEM_CLASS_MISC and subClassID == ITEM_SUBCLASS_COMPANION_PET)
    then
        return true
    end
    if not C_PetJournal or not C_PetJournal.GetPetInfoByItemID then
        return false
    end

    local ok, petName = pcall(C_PetJournal.GetPetInfoByItemID, itemID)
    if not ok or IsSecretValue(petName) then
        return nil
    end
    return petName ~= nil
end

local function IsHousingDecor(itemID, classID, subClassID)
    if classID == ITEM_CLASS_HOUSING and subClassID == ITEM_SUBCLASS_DECOR then
        return true
    end
    if not C_Item or not C_Item.IsDecorItem then
        return false
    end

    local ok, isDecor = pcall(C_Item.IsDecorItem, itemID)
    if not ok or IsSecretValue(isDecor) then
        return nil
    end
    return isDecor == true
end

local function IsAppearanceUnlockItem(itemLink, item)
    if C_Item and C_Item.GetItemLearnTransmogSet then
        local ok, setID = pcall(C_Item.GetItemLearnTransmogSet, itemLink)
        if not ok or IsSecretValue(setID) then
            return nil
        end
        if setID ~= nil then
            -- Ensembles and arsenals stay eligible for auto-pass.
            return false
        end
    end

    if not C_Item or not C_Item.IsDressableItemByID then
        return false
    end

    local ok, isDressable = pcall(C_Item.IsDressableItemByID, item.itemID)
    if not ok or IsSecretValue(isDressable) then
        return nil
    end
    if isDressable ~= true then
        return false
    end

    if C_Item.IsEquippableItem then
        local equipOK, isEquippable = pcall(C_Item.IsEquippableItem, item.itemID)
        if not equipOK or IsSecretValue(isEquippable) or type(isEquippable) ~= "boolean" then
            return nil
        end
        return not isEquippable
    end

    return item.equipLoc == "INVTYPE_NON_EQUIP_IGNORE"
end

function RaidLootPass:OnInitialize()
    self.db = ns.db.profile.RaidLootPass
    if not self.db then
        self.db = {}
        ns.db.profile.RaidLootPass = self.db
    end
end

function RaidLootPass:OnEnable()
    self:RegisterPopup()
    self:RegisterEvents()
    C_Timer.After(1, function()
        self:EvaluateInstance()
    end)
end

function RaidLootPass:OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    StaticPopup_Hide(POPUP_NAME)
    currentInstanceKey = nil
    currentInstanceName = nil
    popupInstanceKey = nil
    wipe(instanceDecisions)
    wipe(pendingRolls)
    wipe(passedRolls)
    wipe(protectedRolls)
end

function RaidLootPass:RegisterPopup()
    StaticPopupDialogs[POPUP_NAME] = {
        text = "",
        button1 = YES,
        button2 = NO,
        OnAccept = function(_, key)
            RaidLootPass:ApproveInstance(key or popupInstanceKey)
        end,
        OnCancel = function(_, key)
            RaidLootPass:DeclineInstance(key or popupInstanceKey)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function RaidLootPass:RegisterEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "START_LOOT_ROLL" then
                RaidLootPass:HandleLootRoll(...)
            elseif event == "CANCEL_LOOT_ROLL" then
                RaidLootPass:ClearPendingRoll(...)
            elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
                RaidLootPass:HandleItemDataReceived(...)
            elseif event == "CANCEL_ALL_LOOT_ROLLS" or event == "LOOT_ROLLS_COMPLETE" then
                wipe(pendingRolls)
                wipe(passedRolls)
                wipe(protectedRolls)
            else
                C_Timer.After(0.5, function()
                    RaidLootPass:EvaluateInstance()
                end)
            end
        end)
    end

    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("START_LOOT_ROLL")
    eventFrame:RegisterEvent("CANCEL_LOOT_ROLL")
    eventFrame:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
    eventFrame:RegisterEvent("LOOT_ROLLS_COMPLETE")
    eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
end

function RaidLootPass:ApplySettings()
    if self.db.enabled then
        self:EvaluateInstance()
    else
        StaticPopup_Hide(POPUP_NAME)
        popupInstanceKey = nil
        wipe(instanceDecisions)
        wipe(pendingRolls)
        wipe(passedRolls)
        wipe(protectedRolls)
    end
end

function RaidLootPass:EvaluateInstance()
    if not self.db.enabled then
        return
    end

    local key, displayName = GetCurrentRaidInstance()
    if not key then
        currentInstanceKey = nil
        currentInstanceName = nil
        popupInstanceKey = nil
        wipe(pendingRolls)
        wipe(passedRolls)
        wipe(protectedRolls)
        StaticPopup_Hide(POPUP_NAME)
        return
    end

    if currentInstanceKey and currentInstanceKey ~= key then
        wipe(pendingRolls)
        wipe(passedRolls)
        wipe(protectedRolls)
        StaticPopup_Hide(POPUP_NAME)
    end

    currentInstanceKey = key
    currentInstanceName = displayName

    if instanceDecisions[key] == true then
        self:PassPendingRolls()
    end
    if instanceDecisions[key] ~= nil then
        return
    end

    self:ShowConfirmPopup(key, displayName)
end

function RaidLootPass:ShowConfirmPopup(key, displayName)
    popupInstanceKey = key
    StaticPopupDialogs[POPUP_NAME].text = T("RAIDLOOTPASS_CONFIRM_TEXT", "%s\n\nAutomatically pass eligible raid loot rolls in this instance?")
    StaticPopup_Show(POPUP_NAME, displayName or T("RAIDLOOTPASS_UNKNOWN_INSTANCE", "this instance"), nil, key)
end

function RaidLootPass:ApproveInstance(key)
    if not key then return end

    instanceDecisions[key] = true
    popupInstanceKey = nil

    if self.db.chatOutput then
        print(CHAT_PREFIX .. string.format(T("RAIDLOOTPASS_APPROVED", "Auto-pass enabled for %s."), currentInstanceName or key))
    end
    self:PassPendingRolls()
end

function RaidLootPass:DeclineInstance(key)
    if not key then return end

    instanceDecisions[key] = false
    popupInstanceKey = nil
    wipe(pendingRolls)

    if self.db.chatOutput then
        print(CHAT_PREFIX .. string.format(T("RAIDLOOTPASS_DECLINED", "Auto-pass disabled for %s."), currentInstanceName or key))
    end
end

function RaidLootPass:ShouldAutoPass()
    if not self.db.enabled or not currentInstanceKey or IsRaidLeader() then
        return false
    end
    return instanceDecisions[currentInstanceKey] == true
end

function RaidLootPass:HasProtectionRules()
    if not self.db.excludeSelectedItems then
        return false
    end

    for _, key in ipairs(PROTECTION_KEYS) do
        if self.db[key] then
            return true
        end
    end
    return false
end

function RaidLootPass:GetRollDecision(rollID)
    if not self:HasProtectionRules() then
        return DECISION_PASS
    end

    local itemLink = GetRollItemLink(rollID)
    if not itemLink then
        return DECISION_WAIT
    end

    local item = GetItemBasics(itemLink)
    if not item then
        return DECISION_WAIT
    end
    if not IsItemDataReady(item.itemID) then
        return DECISION_WAIT, nil, item.itemID
    end

    if self.db.protectRecipes and item.classID == ITEM_CLASS_RECIPE then
        return DECISION_PROTECT, T("RAIDLOOTPASS_REASON_RECIPE", "Recipe"), item.itemID
    end
    if self.db.protectQuestItems and item.classID == ITEM_CLASS_QUEST then
        return DECISION_PROTECT, T("RAIDLOOTPASS_REASON_QUEST", "Quest item"), item.itemID
    end

    if self.db.protectToys then
        local isToy = IsToyItem(item.itemID)
        if isToy == nil then
            return DECISION_WAIT, nil, item.itemID
        end
        if isToy then
            return DECISION_PROTECT, T("RAIDLOOTPASS_REASON_TOY", "Toy"), item.itemID
        end
    end

    if self.db.protectMounts then
        local isMount = IsMountItem(item.itemID, item.classID, item.subClassID)
        if isMount == nil then
            return DECISION_WAIT, nil, item.itemID
        end
        if isMount then
            return DECISION_PROTECT, T("RAIDLOOTPASS_REASON_MOUNT", "Mount"), item.itemID
        end
    end

    if self.db.protectPets then
        local isPet = IsPetItem(item.itemID, item.classID, item.subClassID)
        if isPet == nil then
            return DECISION_WAIT, nil, item.itemID
        end
        if isPet then
            return DECISION_PROTECT, T("RAIDLOOTPASS_REASON_PET", "Battle pet"), item.itemID
        end
    end

    if self.db.protectHousingDecor then
        local isDecor = IsHousingDecor(item.itemID, item.classID, item.subClassID)
        if isDecor == nil then
            return DECISION_WAIT, nil, item.itemID
        end
        if isDecor then
            return DECISION_PROTECT, T("RAIDLOOTPASS_REASON_DECOR", "Housing decor"), item.itemID
        end
    end

    if self.db.protectAppearanceUnlocks then
        local isAppearanceUnlock = IsAppearanceUnlockItem(itemLink, item)
        if isAppearanceUnlock == nil then
            return DECISION_WAIT, nil, item.itemID
        end
        if isAppearanceUnlock then
            return DECISION_PROTECT, T("RAIDLOOTPASS_REASON_APPEARANCE_UNLOCK", "Appearance unlock item"), item.itemID
        end
    end

    return DECISION_PASS, nil, item.itemID
end

function RaidLootPass:PassRoll(rollID)
    if not rollID or not RollOnLoot then return false end

    local ok = pcall(RollOnLoot, rollID, PASS_ROLL_TYPE)
    if ok and self.db.chatOutput and not passedRolls[rollID] then
        print(CHAT_PREFIX .. string.format(T("RAIDLOOTPASS_AUTO_PASSED", "Auto-passed: %s"), GetRollName(rollID)))
    end
    if ok then
        passedRolls[rollID] = true
    end
    return ok
end

function RaidLootPass:ScheduleClassificationRetry(rollID, state)
    if state.retryScheduled then
        return
    end

    local nextAttempt = (state.retryCount or 0) + 1
    local delay = CLASSIFICATION_RETRY_DELAYS[nextAttempt]
    if not delay then
        return
    end

    state.retryCount = nextAttempt
    state.retryScheduled = true
    C_Timer.After(delay, function()
        if pendingRolls[rollID] ~= state then
            return
        end
        state.retryScheduled = false
        RaidLootPass:ProcessRoll(rollID)
    end)
end

function RaidLootPass:SchedulePassRetries(rollID)
    for _, delay in ipairs(PASS_RETRY_DELAYS) do
        C_Timer.After(delay, function()
            if not protectedRolls[rollID]
                and RaidLootPass:ShouldAutoPass()
                and RollStillActive(rollID)
            then
                RaidLootPass:PassRoll(rollID)
            end
        end)
    end
end

function RaidLootPass:ProcessRoll(rollID)
    local state = pendingRolls[rollID]
    if not state or not self:ShouldAutoPass() then
        return
    end
    if not RollStillActive(rollID) then
        self:ClearPendingRoll(rollID)
        return
    end

    local decision, reason, itemID = self:GetRollDecision(rollID)
    state.itemID = itemID or state.itemID

    if decision == DECISION_WAIT then
        self:ScheduleClassificationRetry(rollID, state)
        return
    end

    pendingRolls[rollID] = nil
    if decision == DECISION_PROTECT then
        if not protectedRolls[rollID] then
            protectedRolls[rollID] = reason or true
            if self.db.chatOutput then
                print(CHAT_PREFIX .. string.format(
                    T("RAIDLOOTPASS_PROTECTED", "Kept for manual roll (%s): %s"),
                    reason or T("RAIDLOOTPASS_REASON_COLLECTIBLE", "Collectible"),
                    GetRollName(rollID)
                ))
            end
        end
        return
    end

    self:PassRoll(rollID)
    self:SchedulePassRetries(rollID)
end

function RaidLootPass:PassPendingRolls()
    local rollIDs = {}
    for rollID in pairs(pendingRolls) do
        rollIDs[#rollIDs + 1] = rollID
    end

    for _, rollID in ipairs(rollIDs) do
        if RollStillActive(rollID) then
            self:ProcessRoll(rollID)
        else
            self:ClearPendingRoll(rollID)
        end
    end
end

function RaidLootPass:HandleLootRoll(rollID)
    if not rollID or IsSecretValue(rollID) or passedRolls[rollID] or protectedRolls[rollID] then
        return
    end

    self:EvaluateInstance()
    if not currentInstanceKey then
        return
    end

    if instanceDecisions[currentInstanceKey] == true then
        pendingRolls[rollID] = pendingRolls[rollID] or { retryCount = 0 }
        self:ProcessRoll(rollID)
    elseif instanceDecisions[currentInstanceKey] == nil then
        pendingRolls[rollID] = pendingRolls[rollID] or { retryCount = 0 }
    end
end

function RaidLootPass:HandleItemDataReceived(itemID)
    if IsSecretValue(itemID) or type(itemID) ~= "number" then
        return
    end

    local rollIDs = {}
    for rollID, state in pairs(pendingRolls) do
        if state.itemID == itemID then
            rollIDs[#rollIDs + 1] = rollID
        end
    end
    for _, rollID in ipairs(rollIDs) do
        self:ProcessRoll(rollID)
    end
end

function RaidLootPass:ClearPendingRoll(rollID)
    if rollID and not IsSecretValue(rollID) then
        pendingRolls[rollID] = nil
        passedRolls[rollID] = nil
        protectedRolls[rollID] = nil
    end
end

DDingToolKit:RegisterModule("RaidLootPass", RaidLootPass)
