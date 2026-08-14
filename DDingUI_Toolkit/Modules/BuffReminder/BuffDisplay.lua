--[[
    DDingToolKit - BuffReminder: BuffDisplay
    Display engine: frame pool, icon rendering, category layout, glow management,
    event-driven dirty-flag system, and visibility control.
    Ported from BuffReminders/Display/BuffReminders.lua by zerbi.
]]

local _, ns = ...

local Display = {}
ns.BuffDisplay = Display

local SL = _G.DDingUI_StyleLib
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
local SL_FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"

-- Locals
local floor, max = math.floor, math.max
local pairs, ipairs, wipe = pairs, ipairs, wipe
local tinsert = table.insert
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local IsMounted = IsMounted
local _, playerClass = UnitClass("player")

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_BORDER_SIZE = 2
local DEFAULT_ICON_ZOOM = 0
local TEXCOORD_INSET = 0.07
ns.BR_DEFAULT_BORDER_SIZE = DEFAULT_BORDER_SIZE

local MAX_FRAMES = 30
local CATEGORIES = { "raid", "presence", "targeted", "self", "pet", "consumable", "custom" }
ns.BR_CATEGORIES = CATEGORIES

-- ============================================================================
-- DISPLAY STATE
-- ============================================================================

local mainFrame = nil
local categoryFrames = {}
Display.frames = {} -- key → BuffFrame
local eventFrame = nil

local dirty = false
local lastUpdateTime = 0
local MIN_UPDATE_INTERVAL = 0.5

local inCombat = false
local inEncounter = false
local isResting = false
local testMode = false

local function SetDirty() dirty = true end

-- ============================================================================
-- FONT
-- ============================================================================

local fontPath = SL_FONT

local function ResolveFontPath()
    local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
    if db and db.defaults and db.defaults.fontFace then
        local LSM = LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local path = LSM:Fetch("font", db.defaults.fontFace)
            if path then fontPath = path; return end
        end
    end
    fontPath = SL_FONT
end

function Display.GetFontPath() return fontPath end
function Display.IsTestMode() return testMode end

-- ============================================================================
-- CATEGORY SETTINGS
-- ============================================================================

local CODE_DEFAULTS = {
    iconSize = 64, textSize = 20, iconAlpha = 1, textAlpha = 1,
    textColor = { 1, 1, 1 }, spacing = 0.2, iconZoom = 0, borderSize = 2,
    growDirection = "CENTER",
}

local function GetDB()
    return ns.db and ns.db.profile and ns.db.profile.BuffReminder
end

local function GetCategorySettings(category)
    local db = GetDB()
    if not db then return CODE_DEFAULTS end
    local catSettings = db.categorySettings and db.categorySettings[category]
    local globalDefaults = db.defaults or CODE_DEFAULTS
    if category == "main" or not catSettings or not catSettings.useCustomAppearance then
        return {
            iconSize = globalDefaults.iconSize or 64,
            iconWidth = globalDefaults.iconWidth,
            textSize = globalDefaults.textSize or 20,
            iconAlpha = globalDefaults.iconAlpha or 1,
            textAlpha = globalDefaults.textAlpha or 1,
            textColor = globalDefaults.textColor or { 1, 1, 1 },
            spacing = globalDefaults.spacing or 0.2,
            iconZoom = globalDefaults.iconZoom or 0,
            borderSize = globalDefaults.borderSize or 2,
            growDirection = globalDefaults.growDirection or "CENTER",
            position = catSettings and catSettings.position or { point = "CENTER", x = 0, y = 200 },
        }
    end
    return {
        iconSize = catSettings.iconSize or 64,
        iconWidth = catSettings.iconWidth,
        textSize = catSettings.textSize or 20,
        iconAlpha = catSettings.iconAlpha or 1,
        textAlpha = catSettings.textAlpha or 1,
        textColor = catSettings.textColor or { 1, 1, 1 },
        spacing = catSettings.spacing or 0.2,
        iconZoom = catSettings.iconZoom or 0,
        borderSize = catSettings.borderSize or 2,
        growDirection = catSettings.growDirection or "CENTER",
        position = catSettings.position or { point = "CENTER", x = 0, y = 200 },
    }
end

local function IsCategorySplit(category)
    local db = GetDB()
    if not db then return false end
    local cs = db.categorySettings and db.categorySettings[category]
    return cs and cs.split == true
end

local function GetEffectiveCategory(frame)
    if not frame.buffCategory then return "main" end
    if IsCategorySplit(frame.buffCategory) then return frame.buffCategory end
    return "main"
end

-- ============================================================================
-- ICON HELPERS
-- ============================================================================

local function GetSpellIcon(spellIdOrList)
    if not spellIdOrList then return 136235 end
    local id = type(spellIdOrList) == "table" and spellIdOrList[1] or spellIdOrList
    local ok, tex = pcall(C_Spell.GetSpellTexture, id)
    if ok and tex then return tex end
    return 136235
end

-- ============================================================================
-- BUFF FRAME CREATION
-- ============================================================================

local framePool = {}
local framePoolSize = 0

local function CreateBuffFrame()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(64, 64)
    f:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)

    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetFont(fontPath, 14, "OUTLINE")
    f.count:SetPoint("TOPRIGHT", -2, -2)

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(fontPath, 11, "OUTLINE")
    f.text:SetPoint("BOTTOM", f, "BOTTOM", 0, 2)

    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetAllPoints()
    f.border:SetColorTexture(0, 0, 0, 0)

    f:Hide()
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self) Display.ShowTooltip(self) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

local function AcquireFrame()
    if #framePool > 0 then
        local f = table.remove(framePool)
        f:Show()
        return f
    end
    return CreateBuffFrame()
end

local function ReleaseFrame(f)
    f:Hide()
    f:ClearAllPoints()
    if ns.BR_Glow then ns.BR_Glow.StopAll(f, "BR_expiration") end
    if ns.BR_Glow then ns.BR_Glow.StopAll(f, "BR_missing") end
    f.key = nil; f.buffDef = nil; f.buffCategory = nil
    f.count:SetText(""); f.text:SetText("")
    tinsert(framePool, f)
end

-- ============================================================================
-- TOOLTIP
-- ============================================================================

function Display.ShowTooltip(frame)
    if not frame or not frame.buffDef then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    local buff = frame.buffDef
    local spellID = type(buff.spellID) == "table" and buff.spellID[1] or buff.spellID
    if spellID then
        GameTooltip:SetSpellByID(spellID)
    else
        GameTooltip:SetText(buff.key or "버프 누락")
    end
    GameTooltip:Show()
end

-- ============================================================================
-- MAIN FRAME & CATEGORY FRAMES
-- ============================================================================

local function CreateMainFrame()
    if mainFrame then return mainFrame end
    mainFrame = CreateFrame("Frame", "DDingToolKitBuffReminderFrame", UIParent)
    mainFrame:SetSize(1, 1)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetClampedToScreen(true)
    local db = GetDB()
    local pos = db and db.categorySettings and db.categorySettings.main and db.categorySettings.main.position
    if pos and pos.point then
        mainFrame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 200)
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
    return mainFrame
end

local function GetCategoryFrame(category)
    if categoryFrames[category] then return categoryFrames[category] end
    local f = CreateFrame("Frame", "DDingToolKitBR_" .. category, UIParent)
    f:SetSize(1, 1)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f.category = category
    local settings = GetCategorySettings(category)
    local pos = settings.position
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
    categoryFrames[category] = f
    return f
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

local function LayoutFrames(parentFrame, frames, settings)
    if #frames == 0 then return end
    local iconSize = settings.iconSize or 64
    local iconWidth = settings.iconWidth or iconSize
    local spacing = floor(iconSize * (settings.spacing or 0.2))
    local growDir = settings.growDirection or "CENTER"
    local borderSize = settings.borderSize or 2
    local iconAlpha = settings.iconAlpha or 1
    local zoom = (settings.iconZoom or 0) / 100
    local inset = TEXCOORD_INSET + zoom * 0.5

    for i, f in ipairs(frames) do
        f:SetSize(iconWidth, iconSize)
        f:SetAlpha(iconAlpha)
        f.icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset)

        -- Border
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = SL_FLAT, edgeFile = SL_FLAT, edgeSize = borderSize })
            f:SetBackdropColor(0, 0, 0, 0.6)
            f:SetBackdropBorderColor(0, 0, 0, 1)
        end

        -- Font
        f.count:SetFont(fontPath, max(10, floor(iconSize * 0.22)), "OUTLINE")
        f.text:SetFont(fontPath, max(9, floor(iconSize * 0.17)), "OUTLINE")
        if settings.textColor then
            f.text:SetTextColor(unpack(settings.textColor))
        end

        -- Position
        f:ClearAllPoints()
        local offset = (i - 1) * (iconWidth + spacing)
        if growDir == "LEFT" then
            f:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -offset, 0)
        elseif growDir == "RIGHT" then
            f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", offset, 0)
        elseif growDir == "UP" then
            f:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 0, offset)
        elseif growDir == "DOWN" then
            f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, -offset)
        else -- CENTER
            local totalWidth = #frames * iconWidth + (#frames - 1) * spacing
            local startX = -totalWidth / 2
            f:SetPoint("LEFT", parentFrame, "CENTER", startX + offset, 0)
        end
        f:SetParent(parentFrame)
        f:Show()
    end
end

-- ============================================================================
-- UPDATE (Main Render Loop)
-- ============================================================================

function Display.Update()
    local BuffState = ns.BuffState
    if not BuffState then return end

    local db = GetDB()
    if not db then return end

    -- Visibility checks
    if db.hideInCombat and inCombat then Display.HideAll(); return end
    if db.hideWhileResting and isResting then Display.HideAll(); return end
    if db.hideWhileMounted and IsMounted() then Display.HideAll(); return end
    if db.hideWhileLeveling then
        local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 80
        if UnitLevel("player") < maxLevel then Display.HideAll(); return end
    end
    if db.hideInLegacyInstances and BuffState.IsLegacyInstance() then Display.HideAll(); return end
    if db.showOnlyInGroup and GetNumGroupMembers() <= 1 then Display.HideAll(); return end
    if db.hideAllInVehicle and BuffState.GetInVehicle() then Display.HideAll(); return end

    -- Refresh state
    BuffState.Refresh()

    -- Release all current frames
    for key, frame in pairs(Display.frames) do
        ReleaseFrame(frame)
        Display.frames[key] = nil
    end

    -- Build new frames from state entries
    local categoryBuckets = {}
    for _, entry in pairs(BuffState.entries) do
        if entry.visible then
            local cat = entry.category
            if not categoryBuckets[cat] then categoryBuckets[cat] = {} end
            tinsert(categoryBuckets[cat], entry)
        end
    end

    -- Sort within categories
    for _, bucket in pairs(categoryBuckets) do
        table.sort(bucket, function(a, b) return (a.sortOrder or 0) < (b.sortOrder or 0) end)
    end

    -- Build and position frames
    if not mainFrame then CreateMainFrame() end
    local mainBucket = {}
    local splitBuckets = {}

    for _, cat in ipairs(CATEGORIES) do
        local entries = categoryBuckets[cat]
        if entries and #entries > 0 then
            if IsCategorySplit(cat) then
                splitBuckets[cat] = entries
            else
                for _, e in ipairs(entries) do tinsert(mainBucket, e) end
            end
        end
    end

    -- Render main frame
    local mainDisplayFrames = {}
    local Glow = ns.BR_Glow
    for _, entry in ipairs(mainBucket) do
        local buff = ns.BUFF_TABLES and ns.BUFF_TABLES[entry.category]
        local buffDef
        if buff then
            for _, b in ipairs(buff) do
                if b.key == entry.key then buffDef = b; break end
            end
        end

        local f = AcquireFrame()
        f.key = entry.key
        f.buffCategory = entry.category
        f.buffDef = buffDef

        -- Icon
        local iconTex = entry.dynamicIcon
        if not iconTex and buffDef then
            if buffDef.displayIcon then
                iconTex = buffDef.displayIcon
            else
                iconTex = GetSpellIcon(buffDef.spellID)
            end
        end
        f.icon:SetTexture(iconTex or 136235)

        -- Text
        if entry.displayType == "count" then
            f.count:SetText(entry.countText or "")
            f.text:SetText("")
        elseif entry.displayType == "expiring" then
            f.count:SetText(entry.countText or "")
            f.text:SetText("")
        else
            f.count:SetText("")
            f.text:SetText(entry.overlayText or "")
        end

        -- Glow
        if Glow then
            if entry.shouldGlow then
                local glowKind = entry.glowKindOverride or (entry.displayType == "expiring" and "expiring" or "missing")
                Glow.SetExpiration(f, true, entry.category)
            else
                Glow.SetExpiration(f, false, entry.category)
            end
        end

        Display.frames[entry.key] = f
        tinsert(mainDisplayFrames, f)
    end

    -- Layout main
    local mainSettings = GetCategorySettings("main")
    LayoutFrames(mainFrame, mainDisplayFrames, mainSettings)
    mainFrame:Show()

    -- Render split categories
    for cat, entries in pairs(splitBuckets) do
        local catFrame = GetCategoryFrame(cat)
        local catDisplayFrames = {}
        for _, entry in ipairs(entries) do
            local buff = ns.BUFF_TABLES and ns.BUFF_TABLES[entry.category]
            local buffDef
            if buff then
                for _, b in ipairs(buff) do
                    if b.key == entry.key then buffDef = b; break end
                end
            end
            local f = AcquireFrame()
            f.key = entry.key; f.buffCategory = entry.category; f.buffDef = buffDef
            local iconTex = entry.dynamicIcon
            if not iconTex and buffDef then
                iconTex = buffDef.displayIcon or GetSpellIcon(buffDef.spellID)
            end
            f.icon:SetTexture(iconTex or 136235)
            if entry.displayType == "count" then
                f.count:SetText(entry.countText or ""); f.text:SetText("")
            elseif entry.displayType == "expiring" then
                f.count:SetText(entry.countText or ""); f.text:SetText("")
            else
                f.count:SetText(""); f.text:SetText(entry.overlayText or "")
            end
            if Glow then
                Glow.SetExpiration(f, entry.shouldGlow, entry.category)
            end
            Display.frames[entry.key] = f
            tinsert(catDisplayFrames, f)
        end
        local catSettings = GetCategorySettings(cat)
        LayoutFrames(catFrame, catDisplayFrames, catSettings)
        catFrame:Show()
    end

    -- Hide empty category frames
    for cat, cf in pairs(categoryFrames) do
        if not splitBuckets[cat] then cf:Hide() end
    end

    -- Sync secure buttons
    if ns.SecureButtons and not InCombatLockdown() then
        ns.SecureButtons.ScheduleSecureSync()
    end
end

-- ============================================================================
-- HIDE ALL
-- ============================================================================

function Display.HideAll()
    for key, frame in pairs(Display.frames) do
        ReleaseFrame(frame)
        Display.frames[key] = nil
    end
    if mainFrame then mainFrame:Hide() end
    for _, cf in pairs(categoryFrames) do cf:Hide() end
end

-- ============================================================================
-- EVENT HANDLER
-- ============================================================================

function Display.Initialize()
    if eventFrame then return end
    CreateMainFrame()

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_LEVEL_UP")

    eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        local BuffState = ns.BuffState
        if not BuffState then return end

        if event == "PLAYER_ENTERING_WORLD" then
            ResolveFontPath()
            BuffState.InvalidateContentTypeCache()
            BuffState.InvalidateSpecCache()
            BuffState.InvalidateSpellCache()
            BuffState.InvalidateItemCache()
            if ns.SecureButtons then ns.SecureButtons.InvalidateConsumableCache() end
            isResting = IsResting()
            if ns.StateHelpers then ns.StateHelpers.ScanEatingState() end
            SetDirty()

        elseif event == "UNIT_AURA" then
            if arg1 == "player" then
                if ns.StateHelpers then ns.StateHelpers.UpdateEatingState(arg2) end
                SetDirty()
            elseif arg1 and (arg1:match("^party") or arg1:match("^raid")) then
                SetDirty()
            end

        elseif event == "GROUP_ROSTER_UPDATE" then
            SetDirty()

        elseif event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            BuffState.SetInCombat(true)
            SetDirty()

        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            if not inEncounter then BuffState.SetInCombat(false) end
            SetDirty()

        elseif event == "ENCOUNTER_START" then
            inEncounter = true
            BuffState.SetInCombat(true)
            SetDirty()

        elseif event == "ENCOUNTER_END" then
            inEncounter = false
            if not UnitAffectingCombat("player") then BuffState.SetInCombat(false) end
            SetDirty()

        elseif event == "READY_CHECK" then
            BuffState.SetReadyCheckState(true)
            SetDirty()

        elseif event == "READY_CHECK_FINISHED" then
            C_Timer.After(6, function()
                BuffState.SetReadyCheckState(false); SetDirty()
            end)

        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            BuffState.InvalidateSpecCache()
            BuffState.InvalidateSpellCache()
            if ns.SecureButtons then ns.SecureButtons.InvalidateConsumableCache() end
            SetDirty()

        elseif event == "BAG_UPDATE_DELAYED" then
            BuffState.InvalidateItemCache()
            if ns.SecureButtons then ns.SecureButtons.InvalidateConsumableCache() end
            SetDirty()

        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            BuffState.InvalidateOffHandCache()
            BuffState.InvalidateItemCache()
            SetDirty()

        elseif event == "PLAYER_UPDATE_RESTING" then
            isResting = IsResting()
            SetDirty()

        elseif event == "ZONE_CHANGED_NEW_AREA" then
            BuffState.InvalidateContentTypeCache()
            BuffState.SetConsumablesDismissed(false)
            SetDirty()

        elseif event == "PLAYER_LEVEL_UP" then
            SetDirty()
        end
    end)

    -- Throttled OnUpdate
    eventFrame:SetScript("OnUpdate", function(_, elapsed)
        if not dirty then return end
        local now = GetTime()
        if now - lastUpdateTime < MIN_UPDATE_INTERVAL then return end
        dirty = false
        lastUpdateTime = now
        Display.Update()
    end)

    -- Initial state
    ns.BuffState.SetPlayerClass(playerClass)
    if ns.StateHelpers then ns.StateHelpers.ScanEatingState() end
    SetDirty()
end

-- ============================================================================
-- POSITION SAVE/LOAD (for mover integration)
-- ============================================================================

function Display.SavePosition(category, point, x, y)
    local db = GetDB()
    if not db then return end
    if not db.categorySettings then db.categorySettings = {} end
    if not db.categorySettings[category] then db.categorySettings[category] = {} end
    db.categorySettings[category].position = { point = point, x = x, y = y }
end

function Display.LoadPosition(category)
    local db = GetDB()
    if not db or not db.categorySettings or not db.categorySettings[category] then
        return "CENTER", 0, 200
    end
    local pos = db.categorySettings[category].position
    if not pos then return "CENTER", 0, 200 end
    return pos.point or "CENTER", pos.x or 0, pos.y or 200
end
