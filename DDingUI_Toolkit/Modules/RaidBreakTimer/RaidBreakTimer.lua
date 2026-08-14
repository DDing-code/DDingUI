--[[
    DDingToolKit - RaidBreakTimer
    Large raid break countdown driven by BigWigs break messages.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local SL = _G.DDingUI_StyleLib

local RaidBreakTimer = {}
ns.RaidBreakTimer = RaidBreakTimer

local DEFAULT_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local DEFAULT_IMAGE_FOLDER = "DDingUI_Backgrounds"
local UPDATE_INTERVAL = 0.05
local PREVIEW_TEXT = "20:00"
local VALID_ANCHORS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local active = false
local callbacksRegistered = false
local editPreview = false
local testMode = false
local expirationTime
local updateElapsed = 0

local function IsSecretValue(value)
    return ns.IsSecretValue and ns.IsSecretValue(value)
        or (issecretvalue and issecretvalue(value))
end

local function SafeNumber(value)
    if value == nil or IsSecretValue(value) then return nil end

    local ok, number = pcall(tonumber, value)
    if not ok or IsSecretValue(number) then return nil end
    return number
end

local function Clamp(value, minimum, maximum, fallback)
    value = SafeNumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

local function NormalizeFolderName(folderName)
    folderName = tostring(folderName or "")
    folderName = folderName:gsub("/", "\\")
    folderName = folderName:gsub("^%s+", ""):gsub("%s+$", "")
    folderName = folderName:gsub("^Interface\\+", "")
    folderName = folderName:gsub("^\\+", ""):gsub("\\+$", "")
    folderName = folderName:gsub("\\+", "\\")
    folderName = folderName:gsub("[<>:\"|%?%*]", "")

    if folderName == "" or folderName:find("..", 1, true) then
        return DEFAULT_IMAGE_FOLDER
    end
    return folderName
end

local function NormalizeFileName(fileName)
    fileName = tostring(fileName or "")
    fileName = fileName:gsub("/", "\\")
    fileName = fileName:match("([^\\]+)$") or fileName
    fileName = fileName:gsub("^%s+", ""):gsub("%s+$", "")
    fileName = fileName:gsub("%.[Tt][Gg][Aa]$", "")
    fileName = fileName:gsub("%.[Bb][Ll][Pp]$", "")
    fileName = fileName:gsub("[<>:\"|%?%*]", "")
    return fileName
end

local function FormatRemainingTime(remaining)
    local totalSeconds = math.max(0, math.ceil(remaining))
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%d:%02d", minutes, seconds)
end

local function NormalizeTextOrder(value)
    if value == "TEXT_TIME" or value == "TIME_TEXT" then return value end
    return "TIME_ONLY"
end

local function NormalizeCustomText(value)
    value = tostring(value or "")
    value = value:gsub("[\r\n]+", " ")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeAnchor(value)
    return VALID_ANCHORS[value] and value or "CENTER"
end

local function IsPlayerInRaid()
    local ok, inRaid = pcall(IsInRaid)
    if not ok or IsSecretValue(inRaid) then return false end
    return inRaid and true or false
end

function RaidBreakTimer:GetImagePath()
    if not self.db then return nil end

    local fileName = NormalizeFileName(self.db.imageFile)
    if fileName == "" then return nil end

    return "Interface\\" .. NormalizeFolderName(self.db.imageFolder) .. "\\" .. fileName
end

function RaidBreakTimer:CreateFrame()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "DDingToolKit_RaidBreakTimerFrame", UIParent)
    frame:SetSize(360, 160)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()

    frame.image = frame:CreateTexture(nil, "ARTWORK")
    frame.image:SetPoint("CENTER")
    frame.image:SetTexCoord(0, 1, 0, 1)
    frame.image:Hide()

    frame.timerText = frame:CreateFontString(nil, "OVERLAY")
    frame.timerText:SetPoint("CENTER")
    frame.timerText:SetJustifyH("CENTER")
    frame.timerText:SetJustifyV("MIDDLE")
    frame.timerText:SetWordWrap(false)

    frame.fadeIn = frame:CreateAnimationGroup()
    local fadeIn = frame.fadeIn:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.18)

    frame.fadeOut = frame:CreateAnimationGroup()
    local fadeOut = frame.fadeOut:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.22)
    frame.fadeOut:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        if editPreview or testMode or not expirationTime then return end

        updateElapsed = updateElapsed + (elapsed or 0)
        if updateElapsed < UPDATE_INTERVAL then return end
        updateElapsed = 0

        local remaining = expirationTime - GetTime()
        if remaining <= 0 then
            expirationTime = nil
            RaidBreakTimer:HideDisplay(false)
            return
        end

        RaidBreakTimer:SetDisplayTime(FormatRemainingTime(remaining))
    end)

    self.frame = frame
    self:ApplyPosition()
    return frame
end

function RaidBreakTimer:SetDisplayText(text)
    local frame = self.frame or self:CreateFrame()
    if frame._displayText == text then return end
    frame._displayText = text
    frame.timerText:SetText(text)
end

function RaidBreakTimer:BuildDisplayText(timeText)
    timeText = tostring(timeText or "")
    local customText = NormalizeCustomText(self.db and self.db.customText)
    local textOrder = NormalizeTextOrder(self.db and self.db.textOrder)

    if customText == "" or textOrder == "TIME_ONLY" then
        return timeText
    elseif textOrder == "TEXT_TIME" then
        return customText .. " " .. timeText
    end
    return timeText .. " " .. customText
end

function RaidBreakTimer:SetDisplayTime(timeText)
    self:SetDisplayText(self:BuildDisplayText(timeText))
end

function RaidBreakTimer:ShowDisplay()
    local frame = self.frame or self:CreateFrame()
    if frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end

    frame:SetAlpha(1)
    if not frame:IsShown() then
        frame:Show()
        frame.fadeIn:Play()
    end
end

function RaidBreakTimer:HideDisplay(immediate)
    local frame = self.frame
    if not frame then return end

    if frame.fadeIn:IsPlaying() then frame.fadeIn:Stop() end
    if frame.fadeOut:IsPlaying() then frame.fadeOut:Stop() end

    if immediate or not frame:IsShown() then
        frame:Hide()
        frame:SetAlpha(1)
    else
        frame.fadeOut:Play()
    end
end

function RaidBreakTimer:ApplyPosition()
    local frame = self.frame or self:CreateFrame()
    if not self.db then return end

    local position = self.db.position or {}
    frame:ClearAllPoints()
    frame:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or "CENTER",
        SafeNumber(position.x) or 0,
        SafeNumber(position.y) or 100
    )
end

function RaidBreakTimer:ApplySettings()
    if not self.db then return end
    local frame = self.frame or self:CreateFrame()

    local font = type(self.db.font) == "string" and self.db.font ~= "" and self.db.font or DEFAULT_FONT
    local fontSize = Clamp(self.db.fontSize, 24, 160, 72)
    local outline = self.db.fontOutline
    if outline ~= "OUTLINE" and outline ~= "THICKOUTLINE" then outline = "" end
    if not frame.timerText:SetFont(font, fontSize, outline) then
        frame.timerText:SetFont(DEFAULT_FONT, fontSize, outline)
    end

    local color = type(self.db.textColor) == "table" and self.db.textColor or { 1, 1, 1, 1 }
    frame.timerText:SetTextColor(
        SafeNumber(color[1]) or 1,
        SafeNumber(color[2]) or 1,
        SafeNumber(color[3]) or 1,
        SafeNumber(color[4]) or 1
    )

    local textOffsetX = Clamp(self.db.textOffsetX, -600, 600, 0)
    local textOffsetY = Clamp(self.db.textOffsetY, -600, 600, 0)
    if self.db.textLayer == "BEHIND" then
        frame.timerText:SetDrawLayer("ARTWORK", -1)
    else
        frame.timerText:SetDrawLayer("OVERLAY", 0)
    end
    frame.timerText:ClearAllPoints()
    frame.timerText:SetPoint("CENTER", frame, "CENTER", textOffsetX, textOffsetY)

    frame:SetScale(Clamp(self.db.scale, 0.5, 2, 1))

    local imageWidth = Clamp(self.db.imageWidth, 32, 1200, 360)
    local imageHeight = Clamp(self.db.imageHeight, 32, 1200, 180)
    local imageOffsetX = Clamp(self.db.imageOffsetX, -600, 600, 0)
    local imageOffsetY = Clamp(self.db.imageOffsetY, -600, 600, 0)
    local imagePath = self:GetImagePath()
    local hasImage = self.db.showImage and imagePath ~= nil
    local imageAnchor = NormalizeAnchor(self.db.imageAnchor)

    frame.image:ClearAllPoints()
    frame.image:SetPoint(imageAnchor, frame, imageAnchor, imageOffsetX, imageOffsetY)
    frame.image:SetSize(imageWidth, imageHeight)
    frame.image:SetAlpha(Clamp(self.db.imageAlpha, 0, 1, 0.85))

    if hasImage then
        frame.image:SetTexture(imagePath)
        frame.image:Show()
    else
        frame.image:SetTexture(nil)
        frame.image:Hide()
    end

    local frameWidth = math.max(360, 360 + math.abs(textOffsetX) * 2)
    local frameHeight = math.max(160, 160 + math.abs(textOffsetY) * 2)
    if hasImage then
        frameWidth = math.max(frameWidth, imageWidth + math.abs(imageOffsetX) * 2)
        frameHeight = math.max(frameHeight, imageHeight + math.abs(imageOffsetY) * 2)
    end
    frame:SetSize(frameWidth, frameHeight)
    self:ApplyPosition()
    self:UpdateVisibility()
end

function RaidBreakTimer:UpdateVisibility()
    if editPreview or testMode then
        self:SetDisplayTime(PREVIEW_TEXT)
        self:ShowDisplay()
        return
    end

    if not active or not expirationTime or not IsPlayerInRaid() then
        self:HideDisplay(true)
        return
    end

    local remaining = expirationTime - GetTime()
    if remaining <= 0 then
        expirationTime = nil
        self:HideDisplay(false)
        return
    end

    self:SetDisplayTime(FormatRemainingTime(remaining))
    self:ShowDisplay()
end

function RaidBreakTimer:StartBreak(seconds)
    seconds = SafeNumber(seconds)
    if not seconds or seconds <= 0 or seconds > 3600 then return end

    expirationTime = GetTime() + seconds
    updateElapsed = 0
    self:UpdateVisibility()
end

function RaidBreakTimer:StopBreak()
    expirationTime = nil
    updateElapsed = 0
    if not editPreview and not testMode then
        self:HideDisplay(false)
    end
end

function RaidBreakTimer:BigWigs_StartBreak(_, _, seconds)
    self:StartBreak(seconds)
end

function RaidBreakTimer:BigWigs_StopBreak()
    self:StopBreak()
end

function RaidBreakTimer:RegisterBigWigsCallbacks()
    if callbacksRegistered then return true end

    local loader = _G.BigWigsLoader
    if not loader or type(loader.RegisterMessage) ~= "function" then return false end

    local startOK = pcall(loader.RegisterMessage, self, "BigWigs_StartBreak")
    local stopOK = pcall(loader.RegisterMessage, self, "BigWigs_StopBreak")
    callbacksRegistered = startOK and stopOK

    if not callbacksRegistered and type(loader.UnregisterMessage) == "function" then
        pcall(loader.UnregisterMessage, self, "BigWigs_StartBreak")
        pcall(loader.UnregisterMessage, self, "BigWigs_StopBreak")
    end
    return callbacksRegistered
end

function RaidBreakTimer:UnregisterBigWigsCallbacks()
    if not callbacksRegistered then return end

    local loader = _G.BigWigsLoader
    if loader and type(loader.UnregisterMessage) == "function" then
        pcall(loader.UnregisterMessage, self, "BigWigs_StartBreak")
        pcall(loader.UnregisterMessage, self, "BigWigs_StopBreak")
    end
    callbacksRegistered = false
end

function RaidBreakTimer:OnInitialize()
    self.db = ns.db.profile.RaidBreakTimer
    self:CreateFrame()
    self:ApplySettings()
    self:RegisterBigWigsCallbacks()
    self.initialized = true
end

function RaidBreakTimer:OnEnable()
    if not self.db then self:OnInitialize() end

    active = true
    self:RegisterBigWigsCallbacks()
    self:UpdateVisibility()
end

function RaidBreakTimer:OnDisable()
    active = false
    editPreview = false
    testMode = false
    self:UnregisterBigWigsCallbacks()
    self:HideDisplay(true)
end

function RaidBreakTimer:TestMode()
    testMode = not testMode
    self:ApplySettings()
end

function RaidBreakTimer:ResetPosition()
    if not self.db then return end

    self.db.position = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 100,
    }
    self:ApplyPosition()
end

function RaidBreakTimer:EnterEditPreview()
    editPreview = true
    self:ApplySettings()
end

function RaidBreakTimer:RefreshEditPreview()
    if not editPreview then return end
    self:ApplySettings()
end

function RaidBreakTimer:ExitEditPreview()
    editPreview = false
    self:UpdateVisibility()
end

function RaidBreakTimer:OnMediaChanged()
    self:ApplySettings()
end

DDingToolKit:RegisterModule("RaidBreakTimer", RaidBreakTimer)
