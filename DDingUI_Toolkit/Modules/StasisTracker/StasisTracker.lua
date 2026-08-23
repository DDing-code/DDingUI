-- DDingUI Toolkit - Preservation Evoker Stasis tracker

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local SL = _G.DDingUI_StyleLib

local StasisTracker = {}
ns.StasisTracker = StasisTracker

local STASIS_STORE = 370537
local STASIS_RELEASE = 370564
local TIP_THE_SCALES = 370553
local DREAM_BREATH = 355936
local MAX_SLOTS = 3
local RELEASE_DURATION = 30
local DEFAULT_ICON = 134400
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local DEFAULT_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"

local COLOR_DEFAULTS = {
    storedBorder = { 0.20, 0.78, 1.00, 0.95 },
    emptyBorder = { 0.22, 0.28, 0.36, 0.90 },
    slotBackground = { 0.025, 0.035, 0.05, 0.90 },
    emptyIcon = { 1.00, 1.00, 1.00, 1.00 },
    emptyShade = { 0.00, 0.00, 0.00, 0.35 },
    orderText = { 1.00, 1.00, 1.00, 0.95 },
    timerBar = { 0.20, 0.78, 1.00, 0.95 },
    timerBackground = { 0.025, 0.035, 0.05, 0.90 },
    timerText = { 1.00, 1.00, 1.00, 1.00 },
    warning = { 1.00, 0.22, 0.18, 0.95 },
}

-- 12.1 Preservation whitelist. Non-whitelisted abilities, items, and trinkets
-- cannot consume a tracker slot.
local STORABLE_SPELLS = {
    [361509] = 361509,   -- Living Flame (cast result)
    [431442] = 431443,   -- Chrono Flame (talent event alias)
    [431443] = 431443,   -- Chrono Flame (active spell)
    [364343] = 364343,   -- Echo
    [360995] = 360995,   -- Verdant Embrace
    [366155] = 366155,   -- Reversion
    [1256581] = 1256581, -- Merithra's Blessing
    [355913] = 355913,   -- Emerald Blossom
    [374251] = 374251,   -- Cauterizing Flame
    [360823] = 360823,   -- Naturalize
    [373861] = 373861,   -- Temporal Anomaly
    [1291636] = 1291636, -- Temporal Barrier
}

local DREAM_BREATH_IDS = {
    [355936] = true,
    [382614] = true,
}

local FIRE_BREATH_IDS = {
    [357208] = true,
    [382266] = true,
}

local PREVIEW_SPELLS = { 364343, DREAM_BREATH, 360995 }
local DEFAULT_POSITION = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -220,
}

local frame
local eventFrame = CreateFrame("Frame")
local state = {
    collecting = false,
    stored = {},
    expiresAt = nil,
    tipTheScales = false,
    seenCasts = {},
    lastDreamBreathAt = 0,
}
local editPreview = false
local manualPreview = false
local previewExpiresAt = 0
local updateElapsed = 0

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function GetColor(color, fallback)
    color = type(color) == "table" and color or fallback
    return tonumber(color[1]) or fallback[1],
        tonumber(color[2]) or fallback[2],
        tonumber(color[3]) or fallback[3],
        tonumber(color[4]) or fallback[4] or 1
end

local function CopyDefaultPosition()
    return {
        point = DEFAULT_POSITION.point,
        relativePoint = DEFAULT_POSITION.relativePoint,
        x = DEFAULT_POSITION.x,
        y = DEFAULT_POSITION.y,
    }
end

local function EnsureDB()
    local profile = ns.db and ns.db.profile
    if not profile then return nil end
    if type(profile.StasisTracker) ~= "table" then
        local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.StasisTracker
        profile.StasisTracker = defaults and ns:DeepCopy(defaults) or {}
    end
    local db = profile.StasisTracker
    if type(db.position) ~= "table" then
        db.position = CopyDefaultPosition()
    end
    return db
end

local function IsPreviewing()
    return editPreview or manualPreview
end

local function ResolveSpellTexture(spellID)
    local texture
    if C_Spell and C_Spell.GetSpellTexture then
        texture = C_Spell.GetSpellTexture(spellID)
    elseif _G.GetSpellTexture then
        texture = _G.GetSpellTexture(spellID)
    end
    if IsSecret(texture) or texture == nil then
        return DEFAULT_ICON
    end
    return texture
end

local function IsPreservationEvoker()
    local _, class = UnitClass("player")
    if IsSecret(class) or class ~= "EVOKER" then return false end

    local specIndex = GetSpecialization and GetSpecialization()
    if IsSecret(specIndex) or specIndex == nil then return false end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if IsSecret(specID) or specID == nil then return false end
    return specID == 1468
end

local function SetBorderColor(slot, r, g, b, a)
    slot.borderTop:SetColorTexture(r, g, b, a)
    slot.borderBottom:SetColorTexture(r, g, b, a)
    slot.borderLeft:SetColorTexture(r, g, b, a)
    slot.borderRight:SetColorTexture(r, g, b, a)
end

local function SetBorderFromSetting(slot, color, fallback)
    SetBorderColor(slot, GetColor(color, fallback))
end

local function SetFlatTextureColor(texture, color, fallback)
    texture:SetColorTexture(GetColor(color, fallback))
end

local function SetFontColor(fontString, color, fallback)
    fontString:SetTextColor(GetColor(color, fallback))
end

local function CreateSlot(parent, index)
    local slot = CreateFrame("Frame", nil, parent)
    slot:EnableMouse(false)

    slot.background = slot:CreateTexture(nil, "BACKGROUND")
    slot.background:SetAllPoints()
    slot.background:SetColorTexture(0.025, 0.035, 0.05, 0.9)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    slot.shade = slot:CreateTexture(nil, "OVERLAY")
    slot.shade:SetAllPoints(slot.icon)
    slot.shade:SetColorTexture(0, 0, 0, 0.35)

    slot.emptyNumber = slot:CreateFontString(nil, "OVERLAY")
    slot.emptyNumber:SetPoint("CENTER")
    slot.emptyNumber:SetFont(DEFAULT_FONT, 15, "OUTLINE")
    slot.emptyNumber:SetText(tostring(index))
    slot.emptyNumber:SetTextColor(0.42, 0.48, 0.56, 1)

    slot.order = slot:CreateFontString(nil, "OVERLAY")
    slot.order:SetPoint("TOPLEFT", 4, -3)
    slot.order:SetFont(DEFAULT_FONT, 10, "OUTLINE")
    slot.order:SetText(tostring(index))
    slot.order:SetTextColor(1, 1, 1, 0.95)

    slot.borderTop = slot:CreateTexture(nil, "OVERLAY")
    slot.borderTop:SetPoint("TOPLEFT")
    slot.borderTop:SetPoint("TOPRIGHT")
    slot.borderTop:SetHeight(1)
    slot.borderBottom = slot:CreateTexture(nil, "OVERLAY")
    slot.borderBottom:SetPoint("BOTTOMLEFT")
    slot.borderBottom:SetPoint("BOTTOMRIGHT")
    slot.borderBottom:SetHeight(1)
    slot.borderLeft = slot:CreateTexture(nil, "OVERLAY")
    slot.borderLeft:SetPoint("TOPLEFT")
    slot.borderLeft:SetPoint("BOTTOMLEFT")
    slot.borderLeft:SetWidth(1)
    slot.borderRight = slot:CreateTexture(nil, "OVERLAY")
    slot.borderRight:SetPoint("TOPRIGHT")
    slot.borderRight:SetPoint("BOTTOMRIGHT")
    slot.borderRight:SetWidth(1)
    SetBorderColor(slot, 0.22, 0.28, 0.36, 0.9)

    return slot
end

function StasisTracker:CreateFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "DDingToolKit_StasisTrackerFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame.slots = {}

    for index = 1, MAX_SLOTS do
        frame.slots[index] = CreateSlot(frame, index)
    end

    frame.timer = CreateFrame("StatusBar", nil, frame)
    frame.timer:SetStatusBarTexture(FLAT)
    frame.timer:SetMinMaxValues(0, RELEASE_DURATION)
    frame.timer:SetValue(RELEASE_DURATION)
    frame.timer:SetStatusBarColor(0.20, 0.78, 1.00, 0.95)

    frame.timerBackground = frame.timer:CreateTexture(nil, "BACKGROUND")
    frame.timerBackground:SetAllPoints()
    frame.timerBackground:SetColorTexture(0.025, 0.035, 0.05, 0.9)

    frame.timerText = frame.timer:CreateFontString(nil, "OVERLAY")
    frame.timerText:SetPoint("CENTER", 0, 0)
    frame.timerText:SetFont(DEFAULT_FONT, 12, "OUTLINE")
    frame.timerText:SetTextColor(1, 1, 1, 1)

    frame:SetScript("OnUpdate", function(_, elapsed)
        StasisTracker:OnUpdate(elapsed)
    end)
    frame:Hide()
    return frame
end

function StasisTracker:ApplyPosition()
    local db = self.db or EnsureDB()
    if not db then return end
    local display = self:CreateFrame()
    local position = db.position or DEFAULT_POSITION
    display:ClearAllPoints()
    display:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or position.point or "CENTER",
        tonumber(position.x) or 0,
        tonumber(position.y) or -220
    )
end

function StasisTracker:ApplySettings()
    self.db = EnsureDB()
    if not self.db then return end

    local display = self:CreateFrame()
    local iconSize = Clamp(self.db.iconSize, 24, 80, 44)
    local spacing = Clamp(self.db.spacing, 0, 20, 4)
    local scale = Clamp(self.db.scale, 0.5, 2, 1)
    local timerHeight = self.db.showTimer == false and 0 or 16
    local width = (iconSize * MAX_SLOTS) + (spacing * (MAX_SLOTS - 1))
    local height = iconSize + (timerHeight > 0 and timerHeight + 3 or 0)

    display:SetScale(scale)
    display:SetSize(width, height)
    for index, slot in ipairs(display.slots) do
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", display, "TOPLEFT", (index - 1) * (iconSize + spacing), 0)
        slot:SetSize(iconSize, iconSize)
        slot.emptyNumber:SetFont(self.db.font or DEFAULT_FONT, Clamp(self.db.fontSize, 8, 30, 15), "OUTLINE")
        slot.order:SetFont(self.db.font or DEFAULT_FONT, Clamp(self.db.orderFontSize, 8, 20, 10), "OUTLINE")
        SetFlatTextureColor(slot.background, self.db.slotBackgroundColor, COLOR_DEFAULTS.slotBackground)
        SetFlatTextureColor(slot.shade, self.db.emptyShadeColor, COLOR_DEFAULTS.emptyShade)
        SetFontColor(slot.order, self.db.orderTextColor, COLOR_DEFAULTS.orderText)
    end

    display.timer:ClearAllPoints()
    display.timer:SetPoint("TOPLEFT", display.slots[1], "BOTTOMLEFT", 0, -3)
    display.timer:SetPoint("TOPRIGHT", display.slots[MAX_SLOTS], "BOTTOMRIGHT", 0, -3)
    display.timer:SetHeight(timerHeight > 0 and timerHeight or 1)
    display.timer:SetShown(timerHeight > 0)
    display.timerText:SetFont(self.db.font or DEFAULT_FONT, Clamp(self.db.timerFontSize, 8, 24, 12), "OUTLINE")
    SetFlatTextureColor(display.timerBackground, self.db.timerBackgroundColor, COLOR_DEFAULTS.timerBackground)
    SetFontColor(display.timerText, self.db.timerTextColor, COLOR_DEFAULTS.timerText)
    self:ApplyPosition()
    self:Render()
end

function StasisTracker:Render()
    local display = self:CreateFrame()
    local preview = IsPreviewing()
    local spells = preview and PREVIEW_SPELLS or state.stored
    local visible = preview or state.collecting
    if SL and SL.ApplyBarColor then
        SL.ApplyBarColor(display.timer, self.db and self.db.timerBarColor, COLOR_DEFAULTS.timerBar)
    else
        display.timer:SetStatusBarColor(GetColor(self.db and self.db.timerBarColor, COLOR_DEFAULTS.timerBar))
    end

    for index, slot in ipairs(display.slots) do
        local spellID = spells[index]
        if spellID then
            slot.icon:SetTexture(ResolveSpellTexture(spellID))
            slot.icon:SetVertexColor(1, 1, 1, 1)
            slot.icon:Show()
            slot.shade:Hide()
            slot.emptyNumber:Hide()
            slot.order:Show()
            SetBorderFromSetting(slot, self.db and self.db.storedBorderColor, COLOR_DEFAULTS.storedBorder)
        else
            slot.icon:SetTexture(DEFAULT_ICON)
            slot.icon:SetVertexColor(GetColor(self.db and self.db.emptyIconColor, COLOR_DEFAULTS.emptyIcon))
            slot.icon:Show()
            slot.shade:Show()
            slot.emptyNumber:Hide()
            slot.order:Hide()
            SetBorderFromSetting(slot, self.db and self.db.emptyBorderColor, COLOR_DEFAULTS.emptyBorder)
        end
    end

    local full = preview or #state.stored >= MAX_SLOTS
    if display.timer:IsShown() then
        if full then
            local expiresAt = preview and previewExpiresAt or state.expiresAt
            local remaining = expiresAt and math.max(0, expiresAt - GetTime()) or RELEASE_DURATION
            display.timer:SetMinMaxValues(0, RELEASE_DURATION)
            display.timer:SetValue(remaining)
            display.timerText:SetFormattedText("%d", math.ceil(remaining))
        else
            display.timer:SetMinMaxValues(0, MAX_SLOTS)
            display.timer:SetValue(#state.stored)
            display.timerText:SetFormattedText("%d / %d", #state.stored, MAX_SLOTS)
        end
    end

    display:SetShown(visible and (preview or IsPreservationEvoker()))
end

function StasisTracker:ClearState()
    state.collecting = false
    state.expiresAt = nil
    state.tipTheScales = false
    wipe(state.stored)
    wipe(state.seenCasts)
    state.lastDreamBreathAt = 0
    self:Render()
end

function StasisTracker:StartStasis()
    state.collecting = true
    state.expiresAt = nil
    state.tipTheScales = false
    wipe(state.stored)
    wipe(state.seenCasts)
    state.lastDreamBreathAt = 0
    self:Render()
end

function StasisTracker:IsDuplicateCast(castGUID, canonicalSpellID)
    if not IsSecret(castGUID) and castGUID ~= nil then
        if state.seenCasts[castGUID] then return true end
        state.seenCasts[castGUID] = true
    end

    if canonicalSpellID == DREAM_BREATH then
        local now = GetTime()
        if now - state.lastDreamBreathAt < 0.75 then return true end
        state.lastDreamBreathAt = now
    end
    return false
end

function StasisTracker:AddSpell(spellID, castGUID)
    if not state.collecting or #state.stored >= MAX_SLOTS then return end
    if self:IsDuplicateCast(castGUID, spellID) then return end

    state.stored[#state.stored + 1] = spellID
    if #state.stored == MAX_SLOTS then
        state.expiresAt = GetTime() + RELEASE_DURATION
    end
    self:Render()
end

function StasisTracker:HandleSpellSucceeded(unit, castGUID, spellID)
    if IsSecret(unit) or unit ~= "player" or IsSecret(spellID) then return end
    spellID = tonumber(spellID)
    if not spellID then return end

    if spellID == STASIS_STORE then
        self:StartStasis()
        return
    end
    if spellID == STASIS_RELEASE then
        self:ClearState()
        return
    end
    if not state.collecting or #state.stored >= MAX_SLOTS then return end

    local canonicalSpellID = STORABLE_SPELLS[spellID]
    if canonicalSpellID then
        self:AddSpell(canonicalSpellID, castGUID)
        return
    end

    if spellID == TIP_THE_SCALES then
        state.tipTheScales = true
    elseif state.tipTheScales and DREAM_BREATH_IDS[spellID] then
        state.tipTheScales = false
        self:AddSpell(DREAM_BREATH, castGUID)
    elseif state.tipTheScales and FIRE_BREATH_IDS[spellID] then
        state.tipTheScales = false
    end
end

function StasisTracker:HandleEmpowerStop(unit, castGUID, spellID, success)
    if not state.collecting or #state.stored >= MAX_SLOTS then return end
    if IsSecret(unit) or unit ~= "player" or IsSecret(spellID) or IsSecret(success) then return end
    if success ~= true then return end
    spellID = tonumber(spellID)
    if not spellID or not DREAM_BREATH_IDS[spellID] then return end

    state.tipTheScales = false
    self:AddSpell(DREAM_BREATH, castGUID)
end

function StasisTracker:OnUpdate(elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed < 0.05 then return end
    updateElapsed = 0

    if IsPreviewing() then
        if previewExpiresAt <= GetTime() then
            previewExpiresAt = GetTime() + RELEASE_DURATION
        end
        self:Render()
        return
    end

    if not state.collecting or not state.expiresAt then return end
    local remaining = state.expiresAt - GetTime()
    if remaining <= 0 then
        self:ClearState()
        return
    end

    if frame and frame.timer:IsShown() then
        frame.timer:SetValue(remaining)
        frame.timerText:SetFormattedText("%d", math.ceil(remaining))
        local warningAt = Clamp(self.db and self.db.warningThreshold, 1, 15, 5)
        if remaining <= warningAt then
            if SL and SL.ApplyBarColor then
                SL.ApplyBarColor(frame.timer, self.db and self.db.warningColor, COLOR_DEFAULTS.warning)
            else
                frame.timer:SetStatusBarColor(GetColor(self.db and self.db.warningColor, COLOR_DEFAULTS.warning))
            end
            for _, slot in ipairs(frame.slots) do
                SetBorderFromSetting(slot, self.db and self.db.warningColor, COLOR_DEFAULTS.warning)
            end
        else
            if SL and SL.ApplyBarColor then
                SL.ApplyBarColor(frame.timer, self.db and self.db.timerBarColor, COLOR_DEFAULTS.timerBar)
            else
                frame.timer:SetStatusBarColor(GetColor(self.db and self.db.timerBarColor, COLOR_DEFAULTS.timerBar))
            end
        end
    end
end

function StasisTracker:OnInitialize()
    self.db = EnsureDB()
    self.initialized = true
end

function StasisTracker:OnEnable()
    self.db = EnsureDB()
    self.active = true
    self:CreateFrame()
    self:ApplySettings()
    self:ClearState()
end

function StasisTracker:OnDisable()
    self.active = false
    editPreview = false
    manualPreview = false
    self:ClearState()
    if frame then frame:Hide() end
end

function StasisTracker:OnMediaChanged()
    self:ApplySettings()
end

function StasisTracker:ResetPosition()
    self.db = self.db or EnsureDB()
    if not self.db then return end
    self.db.position = CopyDefaultPosition()
    self:ApplyPosition()
end

function StasisTracker:TestMode()
    self.db = self.db or EnsureDB()
    self:CreateFrame()
    manualPreview = not manualPreview
    previewExpiresAt = GetTime() + 23
    self:ApplySettings()
end

function StasisTracker:EnterEditPreview()
    editPreview = true
    previewExpiresAt = GetTime() + 23
    self.db = self.db or EnsureDB()
    self:CreateFrame()
    self:ApplySettings()
end

function StasisTracker:RefreshEditPreview()
    if not editPreview then return end
    previewExpiresAt = GetTime() + 23
    self:ApplySettings()
end

function StasisTracker:ExitEditPreview()
    editPreview = false
    self:Render()
end

eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not StasisTracker.active then return end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        StasisTracker:HandleSpellSucceeded(...)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        StasisTracker:HandleEmpowerStop(...)
    else
        StasisTracker:ClearState()
    end
end)

DDingToolKit:RegisterModule("StasisTracker", StasisTracker)
