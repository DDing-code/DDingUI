-- ============================================================
-- DDingUI Missing Alerts Module
-- Pet Missing & Class Buff Missing reminders
-- ============================================================

local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local ALERT_FONT = (SL and SL.Font and SL.Font.default) or "Fonts\\FRIZQT__.TTF" -- [12.0.1]

-- ============================================================
-- PET MISSING ALERT
-- For: Hunter, Warlock, Unholy Death Knight
-- ============================================================

local PET_CLASSES = {
    -- [classFile] = { spellID to check if class has pet ability, specID for spec-specific (optional) }
    ["HUNTER"] = { spellID = 883 },      -- Call Pet
    ["WARLOCK"] = { spellID = 688 },     -- Summon Imp
    ["DEATHKNIGHT"] = { spellID = 46584, specID = 252 },  -- Raise Dead (Unholy only)
}

-- ============================================================
-- MISSING CLASS BUFF ALERT (DISABLED - 모듈 비활성화됨)
-- Shows reminder when YOUR class buff is missing
-- ============================================================
--[[ CLASS BUFF ALERT CODE DISABLED
-- Helper: 안전하게 스펠 이름 가져오기 (로딩 시점 스펠 데이터 미로드 대비)
local function GetSafeSpellName(id, default)
    local info = C_Spell.GetSpellInfo(id)
    return info and info.name or default
end

local CLASS_BUFFS = {
    -- [classFile] = { list of buffs to check }
    -- Each buff: { buffID, spellID, name, specID (optional), checkSelf (only player), checkAny (1명만 있으면 OK) }
    ["WARRIOR"] = {
        { buffID = 6673, spellID = 6673, name = GetSafeSpellName(6673, "Battle Shout") },
    },
    ["PALADIN"] = {
        { buffID = 465, spellID = 465, name = GetSafeSpellName(465, "Devotion Aura"), checkSelf = true },  -- 자신에게만 적용되는 오라
    },
    ["DRUID"] = {
        { buffID = 1126, spellID = 1126, name = GetSafeSpellName(1126, "Mark of the Wild") },
        { buffID = 408673, spellID = 408673, name = GetSafeSpellName(408673, "Symbiosis"), checkSelf = true },
    },
    ["MAGE"] = {
        { buffID = 1459, spellID = 1459, name = GetSafeSpellName(1459, "Arcane Intellect") },
    },
    ["PRIEST"] = {
        { buffID = 21562, spellID = 21562, name = GetSafeSpellName(21562, "Power Word: Fortitude") },
    },
    ["SHAMAN"] = {
        { buffID = 462854, spellID = 462854, name = GetSafeSpellName(462854, "Skyfury") },
        { buffID = 192106, spellID = 192106, name = GetSafeSpellName(192106, "Lightning Shield"), specID = 262, checkSelf = true },
        { buffID = 192106, spellID = 192106, name = GetSafeSpellName(192106, "Lightning Shield"), specID = 263, checkSelf = true },
        { buffID = 974, spellID = 974, name = GetSafeSpellName(974, "Earth Shield"), specID = 264, checkAny = true },
        { buffID = 383648, spellID = 383648, name = GetSafeSpellName(383648, "Earth Shield"), specID = 264, checkSelf = true },
    },
    ["EVOKER"] = {
        { buffID = 381748, spellID = 381748, name = GetSafeSpellName(381748, "Blessing of the Bronze") },
        { buffID = 369459, spellID = 369459, name = GetSafeSpellName(369459, "Source of Magic") },
        { buffID = 412710, spellID = 412710, name = GetSafeSpellName(412710, "Timelessness"), specID = 1473 },
    },
    ["ROGUE"] = {
        { buffID = 381637, spellID = 381637, name = GetSafeSpellName(381637, "Atrophic Poison"), checkSelf = true },
    },
    ["WARLOCK"] = {
        { buffID = 20707, spellID = 20707, name = GetSafeSpellName(20707, "Soulstone"), checkAny = true },
    },
}
--]] -- END CLASS BUFF ALERT CODE DISABLED

-- ============================================================
-- MODULE SETUP
-- ============================================================

local MissingAlerts = {}
DDingUI.MissingAlerts = MissingAlerts

local petAlertFrame = nil
local buffAlertFrame = nil
local isModuleEnabled = false

-- ============================================================
-- PET ALERT FRAME
-- ============================================================

local function CreatePetAlertFrame()
    if petAlertFrame then return petAlertFrame end

    local frame = CreateFrame("Frame", "DDingUI_PetMissingAlert", UIParent)
    frame:SetSize(400, 80)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Border (background - drawn behind text)
    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", 0, 0)
    border:SetColorTexture(0, 0, 0, 1)
    border:Hide()  -- hidden by default (borderSize = 0)
    frame.border = border

    -- Text
    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont(ALERT_FONT, 48, "THICKOUTLINE")
    text:SetPoint("CENTER")
    text:SetText("PET IS MISSING")
    text:SetTextColor(0.42, 1, 0, 1)  -- Green color from WeakAura
    frame.text = text

    -- Pulse animation (AnimationGroup - C++ 레벨 처리, OnUpdate 불필요)
    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.3)
    fade:SetToAlpha(1.0)
    fade:SetDuration(0.67)  -- ~1.5 fadeSpeed
    fade:SetSmoothing("IN_OUT")
    frame.pulseAnim = ag

    petAlertFrame = frame
    return frame
end

-- ============================================================
-- BUFF ALERT FRAME (Icon-based) (DISABLED - 모듈 비활성화됨)
-- ============================================================
--[[ BUFF ALERT FRAME DISABLED
local function CreateBuffAlertFrame()
    if buffAlertFrame then return buffAlertFrame end

    local frame = CreateFrame("Frame", "DDingUI_BuffMissingAlert", UIParent)
    frame:SetSize(64, 64)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 230)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Border (background - drawn behind icon)
    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0, 0, 0, 1)
    frame.border = border

    -- Icon texture (on top of border)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    frame.icon = icon

    -- Count text (e.g., "10/15")
    local countText = frame:CreateFontString(nil, "OVERLAY")
    countText:SetFont(ALERT_FONT, 14, "OUTLINE")
    countText:SetPoint("BOTTOM", frame, "BOTTOM", 0, -18)
    countText:SetTextColor(1, 1, 1, 1)
    frame.countText = countText

    buffAlertFrame = frame
    return frame
end
--]] -- END BUFF ALERT FRAME DISABLED

-- ============================================================
-- PET CHECK LOGIC
-- ============================================================

local function ShouldShowPetAlert()
    local _, classFile = UnitClass("player")
    local petData = PET_CLASSES[classFile]

    if not petData then return false end

    -- 비행/수영/차량 중에는 표시 안 함
    if IsFalling() or IsFlying() or IsSwimming() or UnitInVehicle("player") or IsMounted() then
        return false
    end

    -- Check spec requirement (for DK - Unholy only)
    if petData.specID then
        local specIndex = GetSpecialization()
        if specIndex then
            local specID = GetSpecializationInfo(specIndex)
            if specID ~= petData.specID then
                return false
            end
        else
            return false
        end
    end

    -- Check if player knows the pet ability (IsPlayerSpell은 전문화 부여 스킬도 감지)
    if not IsSpellKnown(petData.spellID) and not IsPlayerSpell(petData.spellID) then
        return false
    end

    -- Check if pet exists and is alive
    local hasPet = UnitExists("pet")
    local petAlive = not UnitIsDead("pet")

    -- Show alert if no pet or pet is dead
    if not hasPet or not petAlive then
        return true
    end

    return false
end

-- ============================================================
-- BUFF CHECK LOGIC (Group-wide) (DISABLED - 모듈 비활성화됨)
-- ============================================================
--[[ BUFF CHECK LOGIC DISABLED
-- Helper: Check if unit has a specific buff
local function UnitHasBuff(unit, spellID, spellName)
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        local success, match = pcall(function()
            return (aura.spellId == spellID) or (spellName and aura.name == spellName)
        end)
        if success and match then
            return true
        end
    end
    return false
end

local function GetGroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            table.insert(units, "raid" .. i)
        end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i = 1, GetNumGroupMembers() - 1 do
            table.insert(units, "party" .. i)
        end
    else
        table.insert(units, "player")
    end
    return units
end

local function ShouldShowBuffAlert()
    return false, nil, 0, 0
end
--]] -- END BUFF CHECK LOGIC DISABLED

-- ============================================================
-- UPDATE FUNCTIONS
-- ============================================================

local function UpdatePetAlert()
    if not isModuleEnabled then return end

    local cfg = DDingUI.db and DDingUI.db.profile.missingAlerts
    if not cfg or not cfg.petMissingEnabled then
        if petAlertFrame then petAlertFrame:Hide() end
        return
    end

    local frame = CreatePetAlertFrame()

    -- Instance-only check
    if cfg.petInstanceOnly then
        local inInstance = IsInInstance()
        if not inInstance then
            frame:Hide()
            if frame.pulseAnim then frame.pulseAnim:Stop() end
            return
        end
    end

    if ShouldShowPetAlert() then
        -- Update position from settings
        local anchorPoint = cfg.petAnchorPoint or "CENTER"
        frame:ClearAllPoints()
        frame:SetPoint(anchorPoint, UIParent, anchorPoint, cfg.petOffsetX or 0, cfg.petOffsetY or 150)

        -- Update text
        frame.text:SetText(cfg.petText or "PET IS MISSING")

        -- Update font size
        frame.text:SetFont(ALERT_FONT, cfg.petFontSize or 48, "THICKOUTLINE")

        -- Update color
        local color = cfg.petTextColor or { 0.42, 1, 0, 1 }
        frame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

        -- Update border
        local borderSize = cfg.petBorderSize or 0
        if borderSize > 0 then
            frame.border:ClearAllPoints()
            frame.border:SetPoint("TOPLEFT", -borderSize, borderSize)
            frame.border:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
            local bc = cfg.petBorderColor or {0, 0, 0, 1}
            frame.border:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 1)
            frame.border:Show()
        else
            frame.border:Hide()
        end

        frame:Show()
        if frame.pulseAnim and not frame.pulseAnim:IsPlaying() then
            frame.pulseAnim:Play()
        end
    else
        frame:Hide()
        if frame.pulseAnim then
            frame.pulseAnim:Stop()
        end
    end
end

--[[ UPDATE BUFF ALERT DISABLED
local function UpdateBuffAlert()
    if not isModuleEnabled then return end
    local cfg = DDingUI.db and DDingUI.db.profile.missingAlerts
    if not cfg or not cfg.buffMissingEnabled then
        if buffAlertFrame then buffAlertFrame:Hide() end
        return
    end
    -- ... (전체 코드 비활성화됨)
end
--]] -- END UPDATE BUFF ALERT DISABLED

local function UpdateAllAlerts()
    UpdatePetAlert()
    -- UpdateBuffAlert() -- DISABLED: 클래스 버프 알림 비활성화됨
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================

local eventFrame = CreateFrame("Frame")
local throttleTime = 0
local THROTTLE_INTERVAL = 0.2

eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- Throttle updates
    local now = GetTime()
    if now - throttleTime < THROTTLE_INTERVAL then
        return
    end
    throttleTime = now

    UpdateAllAlerts()
end)

-- ============================================================
-- PUBLIC API
-- ============================================================

local groupBuffTicker = nil

function MissingAlerts:Enable()
    if isModuleEnabled then return end
    isModuleEnabled = true

    -- Register events (UNIT_AURA는 플레이어만, 그룹 버프는 타이머로 체크)
    eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")  -- 플레이어 오라만 이벤트로
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")  -- Party/raid changes
    eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")  -- Member comes online
    eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE") -- Member goes offline

    -- 그룹 버프 체크 타이머 (DISABLED - 클래스 버프 알림 비활성화됨)
    --[[ if not groupBuffTicker then
        groupBuffTicker = C_Timer.NewTicker(2.0, function()
            if isModuleEnabled and not InCombatLockdown() then
                UpdateBuffAlert()
            end
        end)
    end --]]

    -- Initial update
    C_Timer.After(0.5, UpdateAllAlerts)
end

function MissingAlerts:Disable()
    if not isModuleEnabled then return end
    isModuleEnabled = false

    -- Unregister events
    eventFrame:UnregisterAllEvents()

    -- 그룹 버프 타이머 정리
    if groupBuffTicker then
        groupBuffTicker:Cancel()
        groupBuffTicker = nil
    end

    -- Hide frames
    if petAlertFrame then petAlertFrame:Hide() end
    if buffAlertFrame then buffAlertFrame:Hide() end
end

function MissingAlerts:Refresh()
    UpdateAllAlerts()
end

function MissingAlerts:Initialize()
    -- Register movers first (needs frames created)
    self:CreateMovers()

    local cfg = DDingUI.db and DDingUI.db.profile.missingAlerts
    -- Enable if pet alerts are enabled (buff alert disabled)
    if cfg and cfg.petMissingEnabled then
        self:Enable()
    end
end

-- ============================================================
-- MOVER SUPPORT
-- ============================================================

function MissingAlerts:CreateMovers()
    if not DDingUI.Movers then return end

    local cfg = DDingUI.db and DDingUI.db.profile.missingAlerts

    -- Pet Alert Mover
    local petFrame = CreatePetAlertFrame()
    local petAnchor = cfg and cfg.petAnchorPoint or "CENTER"
    local petDefaultX = cfg and cfg.petOffsetX or 0
    local petDefaultY = cfg and cfg.petOffsetY or 150
    DDingUI.Movers:RegisterMover(
        petFrame,
        "DDingUI_PetMissingAlert",
        "Pet Missing Alert",
        { petAnchor, UIParent, petAnchor, petDefaultX, petDefaultY }
    )

    -- Buff Alert Mover (DISABLED - 클래스 버프 알림 비활성화됨)
    --[[ local buffFrame = CreateBuffAlertFrame()
    local buffAnchor = cfg and cfg.buffAnchorPoint or "CENTER"
    local buffDefaultX = cfg and cfg.buffOffsetX or 0
    local buffDefaultY = cfg and cfg.buffOffsetY or 230
    DDingUI.Movers:RegisterMover(
        buffFrame,
        "DDingUI_BuffMissingAlert",
        "Missing Buff Alert",
        { buffAnchor, UIParent, buffAnchor, buffDefaultX, buffDefaultY }
    ) --]]
end
