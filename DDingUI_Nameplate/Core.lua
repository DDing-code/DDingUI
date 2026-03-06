----------------------------------------------------------------------
-- DDingUI Nameplate - Core.lua
-- Initialization, DB, event hub, StyleLib connection
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- StyleLib -- [NAMEPLATE]
local SL = _G.DDingUI_StyleLib
ns.SL   = SL
ns.FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
ns.FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
ns.FONT_DEFAULT = (SL and SL.Font and SL.Font.default) or "Fonts\\FRIZQT__.TTF"

-- Register accent (purple for Nameplate) -- [NAMEPLATE]
if SL and SL.RegisterAddon then
    SL.RegisterAddon("Nameplate", {
        from  = { 0.65, 0.35, 0.85, 1.0 },
        to    = { 0.35, 0.15, 0.55, 1.0 },
        light = { 0.80, 0.55, 0.95, 1.0 },
        dark  = { 0.25, 0.10, 0.40, 1.0 },
    })
end

----------------------------------------------------------------------
-- Safe color helper -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.GetSLColor(path)
    if not SL or not SL.Colors then return { 0.1, 0.1, 0.1, 0.9 } end
    local t = SL.Colors
    for part in path:gmatch("[^%.]+") do
        t = t[part]
        if not t then return { 0.1, 0.1, 0.1, 0.9 } end
    end
    return t
end

function ns.UnpackColor(tbl)
    if not tbl then return 0.1, 0.1, 0.1, 0.9 end
    return tbl[1] or 0.1, tbl[2] or 0.1, tbl[3] or 0.1, tbl[4] or 1
end

----------------------------------------------------------------------
-- Default DB -- [NAMEPLATE]
----------------------------------------------------------------------
ns.defaults = {
    general = {
        enabled         = true,
        clickThruFriend = false,
        clampToScreen   = true,
    },
    healthBar = {
        enemy = {
            width  = 120,
            height = 12,
        },
        friendly = {
            width  = 100,
            height = 8,
        },
        smoothing       = true,
        colorByReaction  = true,
        colorByClass     = true,    -- player nameplates only
        colorByThreat    = false,   -- overrides reaction when Threat module on
        tappedColor      = { 0.50, 0.50, 0.50, 1 },
        reactionColors   = {
            hostile  = { 0.85, 0.20, 0.20, 1 },
            neutral  = { 0.90, 0.80, 0.20, 1 },
            friendly = { 0.30, 0.85, 0.40, 1 },
        },
    },
    castBar = {
        enabled       = true,
        height        = 10,
        iconSize      = 14,
        showShield    = true,
        showTimer     = true,
        showSpellName = true,
        shieldedColor = { 0.70, 0.20, 0.20, 1 },
    },
    threat = {
        enabled      = true,
        useRoleColor = true,
        -- Tank: aggro=green, losing=orange, lost=red, other tank=gray
        tankAggro    = { 0.20, 0.80, 0.20, 1 },
        tankPulling  = { 1.00, 0.50, 0.00, 1 },
        tankNoAggro  = { 0.85, 0.20, 0.20, 1 },
        tankOther    = { 0.50, 0.50, 0.50, 1 },
        -- DPS/Healer: aggro=red, close=orange, safe=green
        dpsAggro     = { 0.85, 0.20, 0.20, 1 },
        dpsPulling   = { 1.00, 0.50, 0.00, 1 },
        dpsNoAggro   = { 0.30, 0.85, 0.40, 1 },
    },
    text = {
        name = {
            enabled       = true,
            fontSize      = 10,
            outline       = "OUTLINE",
            maxLength     = 20,
        },
        health = {
            enabled  = true,
            fontSize = 9,
            outline  = "OUTLINE",
            format   = "PERCENT", -- CURRENT, PERCENT, CURRENT_PERCENT, CURRENT_MAX, DEFICIT, NONE
        },
        level = {
            enabled           = true,
            fontSize          = 9,
            outline           = "OUTLINE",
            colorByDifficulty = true,
        },
    },
    auras = {
        enabled         = true,
        myDebuffsOnly   = true,
        maxAuras        = 5,
        iconSize        = 20,
        spacing         = 2,
        showCooldown     = true,
        showStacks       = true,
    },
    target = {
        highlight      = true,
        scale          = 1.15,
        arrowIndicator = true,
    },
}

----------------------------------------------------------------------
-- Deep copy + merge (target inherits missing keys from source)
----------------------------------------------------------------------
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = DeepCopy(v) end
    return copy
end

local function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = DeepCopy(v)
        end
    end
end

----------------------------------------------------------------------
-- State -- [NAMEPLATE]
----------------------------------------------------------------------
ns.plates       = {}   -- plateFrame → plateData
ns.playerIsTank = false
ns.tankCache    = {}   -- [unitName] = true
ns.playerRole   = "DAMAGER"  -- TANK / HEALER / DAMAGER

----------------------------------------------------------------------
-- Refresh all active plates -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateAllPlates()
    for plateFrame, data in pairs(ns.plates) do
        if data.unitID and plateFrame:IsShown() then
            ns.UpdatePlate(plateFrame, data.unitID)
        end
    end
end

----------------------------------------------------------------------
-- Event frame -- [NAMEPLATE]
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if ns.events[event] then
        ns.events[event](...)
    end
end)

ns.events = {}
ns.eventFrame = eventFrame

----------------------------------------------------------------------
-- ADDON_LOADED -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.events.ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end

    -- Initialize SavedVariables
    if not DDingUI_NameplateDB then DDingUI_NameplateDB = {} end
    MergeDefaults(DDingUI_NameplateDB, ns.defaults)
    ns.db = DDingUI_NameplateDB

    -- Check player role
    ns.UpdatePlayerRole()

    -- Register nameplate events (P0 core)
    local ef = ns.eventFrame
    ef:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ef:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    ef:RegisterEvent("PLAYER_TARGET_CHANGED")
    ef:RegisterEvent("UNIT_HEALTH")
    ef:RegisterEvent("UNIT_MAXHEALTH")
    ef:RegisterEvent("UNIT_AURA")
    ef:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    ef:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")

    -- Cast bar events
    ef:RegisterEvent("UNIT_SPELLCAST_START")
    ef:RegisterEvent("UNIT_SPELLCAST_STOP")
    ef:RegisterEvent("UNIT_SPELLCAST_FAILED")
    ef:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    ef:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    ef:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    ef:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    ef:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    ef:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    ef:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")

    -- Role/group events
    ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ef:RegisterEvent("GROUP_ROSTER_UPDATE")
    ef:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Level/reaction events
    ef:RegisterEvent("UNIT_LEVEL")
    ef:RegisterEvent("UNIT_FACTION")
    ef:RegisterEvent("RAID_TARGET_UPDATE")

    ef:UnregisterEvent("ADDON_LOADED")

    -- Slash command
    SLASH_DDNAMEPLATE1 = "/dnp"
    SLASH_DDNAMEPLATE2 = "/ddnameplate"
    SlashCmdList.DDNAMEPLATE = function(msg)
        if ns.ToggleConfig then
            ns.ToggleConfig()
        else
            local SL0 = _G.DDingUI_StyleLib -- [STYLE]
            if SL0 and SL0.GetChatPrefix then
                print(SL0.GetChatPrefix("Nameplate", "Nameplate") .. "설정창이 아직 로드되지 않았습니다.")
            else
                print("|cffffffffDDing|r|cffffa300UI|r |cffa659d9Nameplate|r|cff888888:|r 설정창이 아직 로드되지 않았습니다.")
            end
        end
    end

    -- [CONTROLLER] MediaChanged 콜백 등록
    local SL = _G.DDingUI_StyleLib
    if SL and SL.RegisterCallback then
        SL.RegisterCallback(ns, "MediaChanged", function()
            -- 폰트/텍스처 변수 갱신
            SL = _G.DDingUI_StyleLib
            ns.SL = SL
            ns.FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
            ns.FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
            ns.FONT_DEFAULT = (SL and SL.Font and SL.Font.default) or "Fonts\\FRIZQT__.TTF"
            -- 활성 네임플레이트 갱신
            for _, plateFrame in pairs(C_NamePlate.GetNamePlates()) do
                local unitID = plateFrame.namePlateUnitToken
                if unitID then
                    ns.CreateOrUpdatePlate(plateFrame, unitID)
                end
            end
        end)
    end

    -- [STYLE]
    if SL and SL.CreateAddonTitle then
        print(SL.CreateAddonTitle("Nameplate", "Nameplate") .. " v1.0.0 로드됨. |cff888888/dnp|r 로 설정")
    else
        print("|cffffffffDDing|r|cffffa300UI|r |cffa659d9Nameplate|r v1.0.0 로드됨. |cff888888/dnp|r 로 설정")
    end
end

----------------------------------------------------------------------
-- Nameplate events → module dispatchers -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.events.NAME_PLATE_UNIT_ADDED(unitID)
    if not ns.db.general.enabled then return end
    local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
    if not plateFrame then return end
    ns.CreateOrUpdatePlate(plateFrame, unitID)
end

function ns.events.NAME_PLATE_UNIT_REMOVED(unitID)
    local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
    if not plateFrame then return end
    ns.CleanupPlate(plateFrame)
end

function ns.events.PLAYER_TARGET_CHANGED()
    ns.UpdateAllTargetHighlights()
end

function ns.events.UNIT_HEALTH(unitID)
    local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
    if not plateFrame or not ns.plates[plateFrame] then return end
    local data = ns.plates[plateFrame]
    if ns.UpdateHealthBar then ns.UpdateHealthBar(data, unitID) end
    if ns.UpdateHealthText then ns.UpdateHealthText(data, unitID) end
end

ns.events.UNIT_MAXHEALTH = ns.events.UNIT_HEALTH

function ns.events.UNIT_AURA(unitID)
    local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
    if not plateFrame or not ns.plates[plateFrame] then return end
    local data = ns.plates[plateFrame]
    if ns.UpdateAuras then ns.UpdateAuras(data, unitID) end
end

function ns.events.UNIT_THREAT_LIST_UPDATE(unitID)
    if not unitID then return end
    local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
    if not plateFrame or not ns.plates[plateFrame] then return end
    local data = ns.plates[plateFrame]
    if ns.UpdateThreat then ns.UpdateThreat(data, unitID) end
end

ns.events.UNIT_THREAT_SITUATION_UPDATE = ns.events.UNIT_THREAT_LIST_UPDATE

-- Cast bar events → CastBar module
local CAST_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_INTERRUPTIBLE = true,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
}

for event in pairs(CAST_EVENTS) do
    ns.events[event] = function(unitID, ...)
        if not unitID then return end
        local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
        if not plateFrame or not ns.plates[plateFrame] then return end
        local data = ns.plates[plateFrame]
        if ns.OnCastEvent then ns.OnCastEvent(data, unitID, event, ...) end
    end
end

-- Role/group events
function ns.events.PLAYER_SPECIALIZATION_CHANGED()
    ns.UpdatePlayerRole()
    ns.UpdateAllPlates()
end

-- [PERF] debounce: GROUP_ROSTER_UPDATE/PLAYER_ROLES_ASSIGNED 연속 발생 시 0.5초 내 1회만
local _rosterPending = false
function ns.events.GROUP_ROSTER_UPDATE()
    if _rosterPending then return end
    _rosterPending = true
    C_Timer.After(0.5, function()
        _rosterPending = false
        ns.UpdateTankCache()
        ns.UpdateAllPlates()
    end)
end

ns.events.PLAYER_ROLES_ASSIGNED = ns.events.GROUP_ROSTER_UPDATE

function ns.events.PLAYER_ENTERING_WORLD()
    ns.UpdatePlayerRole()
    ns.UpdateTankCache()
    -- Re-process existing nameplates
    C_Timer.After(0.5, function()
        local nameplates = C_NamePlate.GetNamePlates()
        if nameplates then
            for _, plateFrame in ipairs(nameplates) do
                local unitID = plateFrame.namePlateUnitToken
                if unitID then
                    ns.CreateOrUpdatePlate(plateFrame, unitID)
                end
            end
        end
    end)
end

-- Level/faction/raid target
function ns.events.UNIT_LEVEL(unitID)
    local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
    if not plateFrame or not ns.plates[plateFrame] then return end
    if ns.UpdateLevelText then ns.UpdateLevelText(ns.plates[plateFrame], unitID) end
end

function ns.events.UNIT_FACTION(unitID)
    local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
    if not plateFrame or not ns.plates[plateFrame] then return end
    ns.UpdatePlate(plateFrame, unitID)
end

function ns.events.RAID_TARGET_UPDATE()
    for plateFrame, data in pairs(ns.plates) do
        if data.unitID and ns.UpdateRaidTarget then
            ns.UpdateRaidTarget(data, data.unitID)
        end
    end
end

----------------------------------------------------------------------
-- Player role detection -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdatePlayerRole()
    local spec = GetSpecialization()
    if spec then
        local role = GetSpecializationRole(spec)
        ns.playerRole   = role or "DAMAGER"
        ns.playerIsTank = (role == "TANK")
    else
        ns.playerRole   = "DAMAGER"
        ns.playerIsTank = false
    end
end

----------------------------------------------------------------------
-- Tank cache -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateTankCache()
    wipe(ns.tankCache)
    if not IsInGroup() then return end

    local numMembers = GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, numMembers do
        local unit = prefix .. i
        if UnitExists(unit) then
            local role = UnitGroupRolesAssigned(unit)
            if role == "TANK" then
                local name = UnitName(unit)
                if name then ns.tankCache[name] = true end
            end
        end
    end
end
