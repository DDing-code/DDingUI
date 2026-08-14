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

local eventFrame
local currentInstanceKey
local currentInstanceName
local popupInstanceKey
local instanceDecisions = {}
local pendingRolls = {}
local passedRolls = {}

local function T(key, fallback)
    return (L and L[key]) or fallback
end

local function IsRaidLeader()
    return UnitIsGroupLeader("player")
end

local function GetCurrentRaidInstance()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then
        return nil
    end

    if not IsInRaid() then
        return nil
    end

    if IsRaidLeader() then
        return nil
    end

    local name, _, difficultyID, difficultyName, _, _, _, instanceMapID = GetInstanceInfo()
    name = name or T("RAIDLOOTPASS_UNKNOWN_INSTANCE", "this instance")

    local key = tostring(instanceMapID or name) .. ":" .. tostring(difficultyID or 0)
    local displayName = difficultyName and difficultyName ~= "" and (name .. " - " .. difficultyName) or name

    return key, displayName
end

local function GetRollName(rollID)
    local _, name, count, quality = GetLootRollItemInfo(rollID)
    if not name then
        local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
        name = link
    end

    if name and count and count > 1 then
        return string.format("%s x%d", name, count)
    end

    return name or ("roll " .. tostring(rollID)), quality
end

local function RollStillActive(rollID)
    if not GetLootRollTimeLeft then
        return true
    end

    local timeLeft = GetLootRollTimeLeft(rollID)
    return timeLeft ~= nil and timeLeft > 0
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
            elseif event == "CANCEL_ALL_LOOT_ROLLS" or event == "LOOT_ROLLS_COMPLETE" then
                wipe(pendingRolls)
                wipe(passedRolls)
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
        StaticPopup_Hide(POPUP_NAME)
        return
    end

    if currentInstanceKey and currentInstanceKey ~= key then
        wipe(pendingRolls)
        wipe(passedRolls)
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
    StaticPopupDialogs[POPUP_NAME].text = T("RAIDLOOTPASS_CONFIRM_TEXT", "%s\n\nAutomatically pass all raid loot rolls in this instance?")
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
    if not self.db.enabled then return false end
    if not currentInstanceKey then
        self:EvaluateInstance()
    end
    if not currentInstanceKey then return false end
    if IsRaidLeader() then return false end
    if instanceDecisions[currentInstanceKey] == true then
        return true
    end
    return false
end

function RaidLootPass:PassRoll(rollID)
    if not rollID then return false end
    if not RollOnLoot then return false end

    local ok = pcall(RollOnLoot, rollID, PASS_ROLL_TYPE)
    if ok and self.db.chatOutput and not passedRolls[rollID] then
        local rollName = GetRollName(rollID)
        print(CHAT_PREFIX .. string.format(T("RAIDLOOTPASS_AUTO_PASSED", "Auto-passed: %s"), rollName))
    end

    if ok then
        passedRolls[rollID] = true
    end

    return ok
end

function RaidLootPass:PassPendingRolls()
    for rollID in pairs(pendingRolls) do
        if RollStillActive(rollID) then
            self:PassRoll(rollID)
        end
        pendingRolls[rollID] = nil
    end
end

function RaidLootPass:HandleLootRoll(rollID)
    if not rollID then return end

    self:EvaluateInstance()

    if self:ShouldAutoPass() then
        self:PassRoll(rollID)
        C_Timer.After(0.2, function()
            if RaidLootPass:ShouldAutoPass() and RollStillActive(rollID) then
                RaidLootPass:PassRoll(rollID)
            end
        end)
        C_Timer.After(0.7, function()
            if RaidLootPass:ShouldAutoPass() and RollStillActive(rollID) then
                RaidLootPass:PassRoll(rollID)
            end
        end)
    elseif currentInstanceKey and instanceDecisions[currentInstanceKey] == nil then
        pendingRolls[rollID] = true
    end
end

function RaidLootPass:ClearPendingRoll(rollID)
    if rollID then
        pendingRolls[rollID] = nil
        passedRolls[rollID] = nil
    end
end

DDingToolKit:RegisterModule("RaidLootPass", RaidLootPass)
