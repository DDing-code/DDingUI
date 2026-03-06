-- This module will be "hidden" in the menu for now, it's more for personal use or for people who know what they are doing lmao have fun!
local GCDTracker = {}
local MAX_HISTORY = 5

local gcdHistory = {}
local spellCache = {}
local iconFrames = {}

local trackerFrame
local enabled = false
local eventFrame

local function GetGCDTrackerDB()
    SakuriaUI_DB = SakuriaUI_DB or {}
    if type(SakuriaUI_DB.GCDTracker) ~= "table" then
        SakuriaUI_DB.GCDTracker = {}
    end
    return SakuriaUI_DB.GCDTracker
end

local function UpdateDisplay()
    for i = 1, MAX_HISTORY do
        local historyIdx = #gcdHistory - (MAX_HISTORY - i)

        if historyIdx > 0 then
            local historyItem = gcdHistory[historyIdx]
            local spellID = historyItem.spellID

            if not spellCache[spellID] then
                spellCache[spellID] = C_Spell.GetSpellInfo(spellID)
            end

            local spellInfo = spellCache[spellID]
            if spellInfo then
                iconFrames[i].texture:SetTexture(spellInfo.iconID)
                iconFrames[i].spellID = spellID
                iconFrames[i].texture:SetAlpha(1.0)
                iconFrames[i]:Show()
            end
        else
            iconFrames[i]:Hide()
        end
    end
end

local function LogGCD(spellID)
    if not spellID then return end

    table.insert(gcdHistory, {
        spellID = spellID,
        time = GetTime(),
    })

    if #gcdHistory > MAX_HISTORY then
        table.remove(gcdHistory, 1)
    end

    UpdateDisplay()
end

local function CreateTrackerFrame()
    trackerFrame = CreateFrame("Frame", "SakuriaGCDTracker", UIParent)
    trackerFrame:SetSize(400, 70)
    trackerFrame:EnableMouse(true)
    trackerFrame:SetMovable(true)
    trackerFrame:RegisterForDrag("LeftButton")

    trackerFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    trackerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOffset, yOffset = self:GetPoint()
        local db = GetGCDTrackerDB()
        db.point = point
        db.relativePoint = relativePoint
        db.xOffset = xOffset
        db.yOffset = yOffset
    end)

    local iconSize = 50
    local spacing = 5

    for i = 1, MAX_HISTORY do
        local iconFrame = CreateFrame("Frame", nil, trackerFrame)
        iconFrame:SetSize(iconSize, iconSize)
        iconFrame:SetPoint("RIGHT", trackerFrame, "RIGHT", -(i - 1) * (iconSize + spacing), 0)

        local texture = iconFrame:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        iconFrame.texture = texture

        iconFrame:SetScript("OnEnter", function(self)
            if self.spellID then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetSpellByID(self.spellID)
                GameTooltip:Show()
            end
        end)

        iconFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        iconFrames[i] = iconFrame
    end

    local db = GetGCDTrackerDB()
    if db.point and db.relativePoint then
        trackerFrame:SetPoint(db.point, UIParent, db.relativePoint, db.xOffset or 0, db.yOffset or 0)
    else
        trackerFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 50)
    end

    trackerFrame:Hide()
end

local function Enable()
    if enabled then return end
    enabled = true

    local db = GetGCDTrackerDB()
    db.enabled = true

    if not trackerFrame then
        CreateTrackerFrame()
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
        if unit == "player" then
            LogGCD(spellID)
        end
    end)

    trackerFrame:Show()
    print("|cffffffffSakuria|r|cffff7abfUI|r: GCD Tracker enabled")
end

local function Disable()
    enabled = false
    local db = GetGCDTrackerDB()
    db.enabled = false

    if trackerFrame then
        trackerFrame:Hide()
    end

    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
        eventFrame = nil
    end

    print("|cffffffffSakuria|r|cffff7abfUI|r: GCD Tracker disabled")
end

-- /sakugcd toggle to opt-in/opt-out
SLASH_SAKUGCD1 = "/sakugcd"
SlashCmdList.SAKUGCD = function(msg)
    local db = GetGCDTrackerDB()
    if db.enabled then
        Disable()
    else
        Enable()
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, addon)
    if addon == "SakuriaUI" then
        local db = GetGCDTrackerDB()
        if db.enabled then
            C_Timer.After(1, function()
                Enable()
            end)
        end
        initFrame:UnregisterEvent("ADDON_LOADED")
    end
end)