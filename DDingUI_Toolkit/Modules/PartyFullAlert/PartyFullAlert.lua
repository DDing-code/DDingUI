--[[
    DDingToolKit - PartyFullAlert
    Alerts once when an active five-player recruitment reaches its target size.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI
local L = ns.L
local SL = _G.DDingUI_StyleLib
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit")
    or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: "

local PartyFullAlert = {}
ns.PartyFullAlert = PartyFullAlert

local active = false
local editPreview = false
local driver
local pollElapsed = 0

local detection = {
    initialized = false,
    previousCount = 0,
    sawEligibleListing = false,
    lastEligibleListingAt = 0,
    lastAlertAt = 0,
}

local LISTING_CLOSE_GRACE = 1.5

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value)
end

local function SafeNumber(value)
    if IsSecretValue(value) or value == nil then return nil end

    local ok, number = pcall(tonumber, value)
    if not ok or IsSecretValue(number) then return nil end
    return number
end

local function SafeBoolean(value)
    if IsSecretValue(value) or value == nil then return nil end
    return value and true or false
end

local function GetActivityID(entryInfo)
    local activityID = entryInfo.activityID
    if not IsSecretValue(activityID) and type(activityID) == "number" then
        return activityID
    end

    local activityIDs = entryInfo.activityIDs
    if IsSecretValue(activityIDs) or type(activityIDs) ~= "table" then
        return nil
    end

    activityID = activityIDs[1]
    if IsSecretValue(activityID) or type(activityID) ~= "number" then
        return nil
    end
    return activityID
end

local function EnsureDriver()
    if driver then return end

    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, elapsed)
        if not active or editPreview then return end

        pollElapsed = pollElapsed + (elapsed or 0)
        local interval = math.max(0.2, tonumber(PartyFullAlert.db and PartyFullAlert.db.pollInterval) or 0.4)
        if pollElapsed < interval then return end

        pollElapsed = 0
        PartyFullAlert:PollRecruitment()
    end)
    driver:Hide()
end

function PartyFullAlert:OnInitialize()
    self.db = ns.db.profile.PartyFullAlert
    self:CreateAlertFrame()
    self:ApplySettings()
    self.initialized = true
end

function PartyFullAlert:OnEnable()
    if not self.db then self:OnInitialize() end

    active = true
    pollElapsed = 0
    self:ResetDetection()
    EnsureDriver()
    driver:Show()
    self:PollRecruitment()
end

function PartyFullAlert:OnDisable()
    active = false
    editPreview = false
    if driver then driver:Hide() end
    self:HideAlert(true)
    self:ResetDetection()
end

function PartyFullAlert:ResetDetection()
    detection.initialized = false
    detection.previousCount = 0
    detection.sawEligibleListing = false
    detection.lastEligibleListingAt = 0
    detection.lastAlertAt = 0
end

function PartyFullAlert:GetGroupSize()
    local ok, isRaid = pcall(IsInRaid)
    if not ok or IsSecretValue(isRaid) then return nil end
    if isRaid then return nil end

    local sizeOK, size = pcall(GetNumGroupMembers)
    if not sizeOK then return nil end
    size = SafeNumber(size)
    if not size then return nil end
    return math.max(0, math.floor(size + 0.5))
end

function PartyFullAlert:HasEligibleListing()
    if not C_LFGList or not C_LFGList.GetActiveEntryInfo then return false end

    local ok, entryInfo = pcall(C_LFGList.GetActiveEntryInfo)
    if not ok or IsSecretValue(entryInfo) or type(entryInfo) ~= "table" then
        return false
    end

    local activityID = GetActivityID(entryInfo)
    if not activityID or not C_LFGList.GetActivityInfoTable then return false end

    local activityOK, activityInfo = pcall(C_LFGList.GetActivityInfoTable, activityID)
    if not activityOK or IsSecretValue(activityInfo) or type(activityInfo) ~= "table" then
        return false
    end

    local isRaidActivity = SafeBoolean(activityInfo.isCurrentRaidActivity)
    if isRaidActivity then return false end

    local maxPlayers = SafeNumber(activityInfo.maxNumPlayers)
    if not maxPlayers then return false end

    return maxPlayers == 5
end

function PartyFullAlert:PollRecruitment()
    if not active then return end

    local groupSize = self:GetGroupSize()
    if groupSize == nil then return end

    local now = GetTime()
    local hasEligibleListing = self:HasEligibleListing()
    if hasEligibleListing then
        detection.sawEligibleListing = true
        detection.lastEligibleListingAt = now
    end

    local hasRecruitmentContext = detection.sawEligibleListing
        and (now - detection.lastEligibleListingAt <= LISTING_CLOSE_GRACE)

    if not detection.initialized then
        detection.previousCount = groupSize
        detection.initialized = true
        return
    end

    local targetSize = math.max(2, math.min(5, tonumber(self.db.targetSize) or 5))
    local cooldown = math.max(0, tonumber(self.db.cooldown) or 5)
    local reachedTarget = detection.previousCount < targetSize and groupSize >= targetSize

    if hasRecruitmentContext and reachedTarget and now - detection.lastAlertAt >= cooldown then
        detection.lastAlertAt = now
        self:TriggerAlert(false, groupSize)
    end

    detection.previousCount = groupSize

    if not hasEligibleListing and now - detection.lastEligibleListingAt > LISTING_CLOSE_GRACE then
        detection.sawEligibleListing = false
    end
end

function PartyFullAlert:CreateAlertFrame()
    if self.alertFrame then return end

    local frame = CreateFrame("Frame", "DDingToolKit_PartyFullAlertFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 80)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop(UI.backdrop)
    frame:SetBackdropColor(0.02, 0.04, 0.06, 0.96)
    frame:SetBackdropBorderColor(0.20, 0.90, 0.65, 1)
    frame:EnableMouse(false)
    frame:Hide()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(44, 44)
    frame.icon:SetPoint("LEFT", frame, "LEFT", 18, 0)
    frame.icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 15, -7)
    frame.title:SetTextColor(0.25, 1.00, 0.70, 1)

    frame.subText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.subText:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -7)
    frame.subText:SetTextColor(0.80, 0.86, 0.92, 1)

    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    frame.accent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.accent:SetHeight(2)
    frame.accent:SetColorTexture(0.20, 0.90, 0.65, 0.9)

    frame.fadeIn = frame:CreateAnimationGroup()
    local fadeIn = frame.fadeIn:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.2)

    frame.fadeOut = frame:CreateAnimationGroup()
    local fadeOut = frame.fadeOut:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.35)
    frame.fadeOut:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)

    self.alertFrame = frame
    self:ApplyPosition()
end

function PartyFullAlert:ApplyPosition()
    if not self.alertFrame or not self.db then return end

    local position = self.db.position or {}
    self.alertFrame:ClearAllPoints()
    self.alertFrame:SetPoint(
        position.point or "TOP",
        UIParent,
        position.relativePoint or "TOP",
        position.x or 0,
        position.y or -180
    )
end

function PartyFullAlert:ApplySettings()
    if not self.db then return end
    if not self.alertFrame then self:CreateAlertFrame() end

    self.alertFrame:SetScale(math.max(0.5, tonumber(self.db.alertScale) or 1))
    self:ApplyPosition()
end

function PartyFullAlert:ShowAlert(isTest, memberCount)
    if not self.alertFrame then self:CreateAlertFrame() end

    local frame = self.alertFrame
    if frame.fadeIn:IsPlaying() then frame.fadeIn:Stop() end
    if frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end

    local targetSize = math.max(2, math.min(5, tonumber(self.db.targetSize) or 5))
    frame.title:SetText(isTest and L["PARTYFULLALERT_TEST_TITLE"] or L["PARTYFULLALERT_COMPLETE_TITLE"])
    frame.subText:SetText(string.format(
        isTest and L["PARTYFULLALERT_TEST_SUBTEXT"] or L["PARTYFULLALERT_COMPLETE_SUBTEXT"],
        memberCount or targetSize
    ))

    frame:SetAlpha(1)
    frame:Show()
    frame.fadeIn:Play()

    self._alertSerial = (self._alertSerial or 0) + 1
    local serial = self._alertSerial
    if not editPreview then
        C_Timer.After(math.max(1, tonumber(self.db.alertDuration) or 5), function()
            if self._alertSerial == serial then
                self:HideAlert(false)
            end
        end)
    end
end

function PartyFullAlert:HideAlert(immediate)
    if not self.alertFrame then return end

    self._alertSerial = (self._alertSerial or 0) + 1
    local frame = self.alertFrame
    if frame.fadeIn:IsPlaying() then frame.fadeIn:Stop() end
    if frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end

    if immediate or not frame:IsShown() then
        frame:Hide()
        frame:SetAlpha(1)
    else
        frame:SetAlpha(1)
        frame.fadeOut:Play()
    end
end

function PartyFullAlert:TriggerAlert(isTest, memberCount)
    local targetSize = math.max(2, math.min(5, tonumber(self.db.targetSize) or 5))

    if self.db.soundEnabled then
        local soundFile = self.db.soundFile
        local customPath = self.db.soundCustomPath
        local channel = self.db.soundChannel or "Master"
        if (customPath and customPath ~= "") or (soundFile and soundFile ~= "") then
            ns:PlaySound(soundFile, channel, customPath)
        else
            PlaySound((SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, channel)
        end
    end

    if self.db.flashEnabled and FlashClientIcon then
        pcall(FlashClientIcon)
    end

    if self.db.screenAlertEnabled then
        self:ShowAlert(isTest, memberCount or targetSize)
    end

    if self.db.chatAlert then
        if isTest then
            print(CHAT_PREFIX .. L["PARTYFULLALERT_TEST_CHAT"])
        else
            print(string.format(CHAT_PREFIX .. L["PARTYFULLALERT_COMPLETE_CHAT"], memberCount or targetSize))
        end
    end
end

function PartyFullAlert:EnterEditPreview()
    editPreview = true
    self:ShowAlert(true, tonumber(self.db.targetSize) or 5)
end

function PartyFullAlert:RefreshEditPreview()
    if not editPreview then return end
    self:ApplySettings()
    self:ShowAlert(true, tonumber(self.db.targetSize) or 5)
end

function PartyFullAlert:ExitEditPreview()
    editPreview = false
    self:HideAlert(true)
end

function PartyFullAlert:ResetPosition()
    self.db.position = {
        point = "TOP",
        relativePoint = "TOP",
        x = 0,
        y = -180,
    }
    self:ApplyPosition()
end

DDingToolKit:RegisterModule("PartyFullAlert", PartyFullAlert)
