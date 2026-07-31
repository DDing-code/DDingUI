--[[
    DDingToolKit - RangeDisplay
    Estimated target/focus range display powered by LibRangeCheck-3.0.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"

local RangeDisplay = {}
ns.RangeDisplay = RangeDisplay

local rangeLib = LibStub("LibRangeCheck-3.0", true)
local frames = {}
local driver
local updateElapsed = 0
local editPreview = false
local testMode = false
local active = false

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value)
end

local function SafeNumber(value)
    if IsSecretValue(value) then return nil end
    if value == nil then return nil end

    local ok, number = pcall(tonumber, value)
    if not ok or IsSecretValue(number) then return nil end
    return number
end

local function SafeUnitExists(unit)
    local ok, exists = pcall(UnitExists, unit)
    if not ok or IsSecretValue(exists) then return nil end
    return exists and true or false
end

local function GetColor(db, key, fallback)
    local color = db and db[key]
    if type(color) ~= "table" then color = fallback end
    return color[1] or fallback[1], color[2] or fallback[2],
        color[3] or fallback[3], color[4] or fallback[4] or 1
end

local function SetFrameColor(frame, colorKey)
    if not frame or not RangeDisplay.db then return end

    local fallbacks = {
        nearColor = { 0.25, 1.00, 0.45, 1 },
        mediumColor = { 1.00, 0.82, 0.20, 1 },
        farColor = { 1.00, 0.25, 0.20, 1 },
        unknownColor = { 0.70, 0.75, 0.82, 1 },
    }
    local r, g, b, a = GetColor(RangeDisplay.db, colorKey, fallbacks[colorKey])
    frame.text:SetTextColor(r, g, b, a)
    frame.accent:SetVertexColor(r, g, b, math.min(a, 0.9))
    frame._colorKey = colorKey
end

local function SetFrameText(frame, text, colorKey)
    if frame._displayText ~= text then
        frame.text:SetText(text)
        frame._displayText = text
    end
    if frame._colorKey ~= colorKey then
        SetFrameColor(frame, colorKey)
    end
end

local function SaveFramePosition(frame)
    if not frame or not RangeDisplay.db then return end

    local position = RangeDisplay.db[frame._positionKey]
    if type(position) ~= "table" then return end

    local point, _, relativePoint, x, y = frame:GetPoint()
    position.point = point or "CENTER"
    position.relativePoint = relativePoint or point or "CENTER"
    position.x = math.floor((x or 0) + 0.5)
    position.y = math.floor((y or 0) + 0.5)
end

local function CreateDisplayFrame(unit, globalName, positionKey)
    local frame = CreateFrame("Frame", globalName, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame._unit = unit
    frame._positionKey = positionKey

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetTexture(SL_FLAT)
    frame.bg:SetVertexColor(0.015, 0.02, 0.035, 0.3)

    frame.accent = frame:CreateTexture(nil, "BORDER")
    frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.accent:SetWidth(2)
    frame.accent:SetTexture(SL_FLAT)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetJustifyH("CENTER")
    frame.text:SetWordWrap(false)

    frame:SetScript("OnDragStart", function(self)
        if not RangeDisplay.db or RangeDisplay.db.locked then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition(self)
    end)

    if ns.EnableRightClickMouselook then
        ns:EnableRightClickMouselook(frame)
    end

    frame:Hide()
    frames[unit] = frame
    return frame
end

local function EnsureDriver()
    if driver then return end

    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, elapsed)
        if not active or editPreview or testMode then return end

        updateElapsed = updateElapsed + (elapsed or 0)
        local interval = math.max(0.05, tonumber(RangeDisplay.db and RangeDisplay.db.updateRate) or 0.2)
        if updateElapsed < interval then return end

        updateElapsed = 0
        RangeDisplay:UpdateAll()
    end)
    driver:Hide()
end

function RangeDisplay:OnInitialize()
    self.db = ns.db.profile.RangeDisplay
    self:CreateFrames()
    self:ApplySettings()
    self.initialized = true
end

function RangeDisplay:OnEnable()
    if not self.db then self:OnInitialize() end

    active = true
    updateElapsed = 0
    EnsureDriver()
    driver:Show()
    self:UpdateAll()
end

function RangeDisplay:OnDisable()
    active = false
    editPreview = false
    testMode = false
    if driver then driver:Hide() end

    for _, frame in pairs(frames) do
        frame:Hide()
    end
end

function RangeDisplay:CreateFrames()
    if not frames.target then
        CreateDisplayFrame("target", "DDingToolKit_RangeDisplayTargetFrame", "targetPosition")
    end
    if not frames.focus then
        CreateDisplayFrame("focus", "DDingToolKit_RangeDisplayFocusFrame", "focusPosition")
    end
end

function RangeDisplay:ApplyPosition()
    if not self.db then return end

    for unit, frame in pairs(frames) do
        local key = unit == "target" and "targetPosition" or "focusPosition"
        local position = self.db[key] or {}
        frame:ClearAllPoints()
        frame:SetPoint(
            position.point or "CENTER",
            UIParent,
            position.relativePoint or "CENTER",
            position.x or 0,
            position.y or 0
        )
    end
end

function RangeDisplay:ApplySettings()
    if not self.db then return end
    self:CreateFrames()

    local width = math.max(80, tonumber(self.db.width) or 140)
    local height = math.max(20, tonumber(self.db.height) or 32)
    local fontSize = math.max(8, tonumber(self.db.fontSize) or 20)
    local font = self.db.font or SL_FONT
    local outline = self.db.fontOutline or "OUTLINE"
    local scale = math.max(0.5, tonumber(self.db.scale) or 1)
    local bgAlpha = math.max(0, math.min(1, tonumber(self.db.bgAlpha) or 0))

    for _, frame in pairs(frames) do
        frame:SetSize(width, height)
        frame:SetScale(scale)
        frame:SetFrameStrata(self.db.frameStrata or "MEDIUM")
        frame.text:SetFont(font, fontSize, outline)
        frame.bg:SetVertexColor(0.015, 0.02, 0.035, bgAlpha)
        frame.accent:SetShown(self.db.showAccentLine ~= false)
        frame:EnableMouse(not self.db.locked)
        frame:RegisterForDrag("LeftButton")
        frame._colorKey = nil
    end

    self:ApplyPosition()

    if editPreview or testMode then
        self:ShowPreview()
    else
        self:UpdateAll()
    end
end

function RangeDisplay:IsRestrictedRangeContext()
    if InCombatLockdown() then return true end

    local ok, inInstance = pcall(IsInInstance)
    if not ok or IsSecretValue(inInstance) then return true end
    return inInstance and true or false
end

function RangeDisplay:GetEstimatedRange(unit)
    if not rangeLib then
        rangeLib = LibStub("LibRangeCheck-3.0", true)
    end
    if not rangeLib then return nil, nil end

    local noItems = self:IsRestrictedRangeContext()
    local ok, minRange, maxRange = pcall(
        rangeLib.GetRange,
        rangeLib,
        unit,
        false,
        noItems,
        self.db.updateRate or 0.2
    )

    if not ok and not noItems then
        ok, minRange, maxRange = pcall(
            rangeLib.GetRange,
            rangeLib,
            unit,
            false,
            true,
            self.db.updateRate or 0.2
        )
    end

    if not ok or IsSecretValue(minRange) or IsSecretValue(maxRange) then
        return nil, nil
    end

    return SafeNumber(minRange), SafeNumber(maxRange)
end

function RangeDisplay:FormatRange(minRange, maxRange)
    if maxRange then
        local roundedMax = math.floor(maxRange + 0.5)
        if not minRange or minRange <= 0 then
            return string.format("<= %dm", roundedMax)
        end

        local roundedMin = math.floor(minRange + 0.5)
        if roundedMin == roundedMax then
            return string.format("%dm", roundedMax)
        end
        return string.format("%d-%dm", roundedMin, roundedMax)
    end

    if minRange then
        return string.format("> %dm", math.floor(minRange + 0.5))
    end

    return nil
end

function RangeDisplay:GetColorKey(minRange, maxRange)
    local range = maxRange or minRange
    if not range then return "unknownColor" end

    local nearThreshold = tonumber(self.db.nearThreshold) or 8
    local farThreshold = tonumber(self.db.farThreshold) or 40
    if range <= nearThreshold then
        return "nearColor"
    elseif range <= farThreshold then
        return "mediumColor"
    end
    return "farColor"
end

function RangeDisplay:AddUnitLabel(unit, text)
    if not self.db or not self.db.showUnitLabel then return text end

    local localeKey = unit == "focus" and "RANGEDISPLAY_FOCUS_LABEL" or "RANGEDISPLAY_TARGET_LABEL"
    local label = (L and rawget(L, localeKey))
        or (unit == "focus" and (FOCUS or "Focus") or (TARGET or "Target"))
    return string.format("%s  %s", label, text)
end

function RangeDisplay:UpdateUnit(unit)
    local frame = frames[unit]
    if not frame or not active then return end

    if self.db.combatOnly and not InCombatLockdown() then
        frame:Hide()
        return
    end

    if (unit == "target" and not self.db.showTarget)
        or (unit == "focus" and not self.db.showFocus) then
        frame:Hide()
        return
    end

    local minRange, maxRange = self:GetEstimatedRange(unit)
    local text = self:FormatRange(minRange, maxRange)
    if text then
        SetFrameText(frame, self:AddUnitLabel(unit, text), self:GetColorKey(minRange, maxRange))
        frame:Show()
        return
    end

    if self.db.showUnknown and SafeUnitExists(unit) then
        SetFrameText(frame, self:AddUnitLabel(unit, "?"), "unknownColor")
        frame:Show()
    else
        frame:Hide()
    end
end

function RangeDisplay:UpdateAll()
    if not active or editPreview or testMode then return end
    self:UpdateUnit("target")
    self:UpdateUnit("focus")
end

function RangeDisplay:ShowPreview()
    self:CreateFrames()

    SetFrameText(
        frames.target,
        self:AddUnitLabel("target", "<= 8m"),
        "nearColor"
    )
    frames.target:Show()

    SetFrameText(
        frames.focus,
        self:AddUnitLabel("focus", "30-40m"),
        "mediumColor"
    )
    frames.focus:Show()
end

function RangeDisplay:TestMode()
    if not self.db then self:OnInitialize() end
    if not self.db then return end

    testMode = not testMode
    if testMode then
        self:ShowPreview()
    elseif active then
        self:UpdateAll()
    else
        for _, frame in pairs(frames) do
            frame:Hide()
        end
    end
end

function RangeDisplay:EnterEditPreview()
    if not self.db then self:OnInitialize() end
    if not self.db then return end

    editPreview = true
    self:ShowPreview()
end

function RangeDisplay:RefreshEditPreview()
    if editPreview then self:ShowPreview() end
end

function RangeDisplay:ExitEditPreview()
    editPreview = false
    if testMode then return end
    if active then
        self:UpdateAll()
    else
        for _, frame in pairs(frames) do
            frame:Hide()
        end
    end
end

function RangeDisplay:ResetPosition()
    if not self.db then self:OnInitialize() end
    if not self.db then return end

    self.db.targetPosition = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -180,
    }
    self.db.focusPosition = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -140,
    }
    self:ApplyPosition()
end

DDingToolKit:RegisterModule("RangeDisplay", RangeDisplay)
