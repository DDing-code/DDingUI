local ns = select(2, ...)
local DDingUI = ns.Addon

local RacialCooldowns = {}
DDingUI.CustomIconRacials = RacialCooldowns

local RACIAL_SPELLS = {
    Orc = { 20572, 33697, 33702 },
    Tauren = { 20549 },
    NightElf = { 58984 },
    Human = { 59752 },
    Dwarf = { 20594 },
    Scourge = { 7744 },
    Troll = { 26297 },
    BloodElf = { 202719, 50613, 25046, 69179, 80483, 155145, 129597, 232633, 28730 },
    Gnome = { 20589 },
    Draenei = { 28880 },
    Worgen = { 68992 },
    Goblin = { 69070 },
    Pandaren = { 107079 },
    VoidElf = { 256948 },
    LightforgedDraenei = { 255647 },
    DarkIronDwarf = { 265221 },
    KulTiran = { 287712 },
    Mechagnome = { 312924 },
    Nightborne = { 260364 },
    HighmountainTauren = { 255654 },
    MagharOrc = { 274738 },
    ZandalariTroll = { 291944 },
    Vulpera = { 312411 },
    Dracthyr = { 357214, 368970 },
    EarthenDwarf = { 436344 },
    Haranir = { 1287685 },
}

local cacheRaceKey
local cacheSpecID
local cacheSpellID
local cacheTexture

local function GetCurrentSpecID()
    if not (GetSpecialization and GetSpecializationInfo) then return 0 end
    local specIndex = GetSpecialization()
    if not specIndex then return 0 end
    local specID = GetSpecializationInfo(specIndex)
    return specID or specIndex or 0
end

local function GetRaceKey()
    local _, raceKey = UnitRace("player")
    return (raceKey or ""):gsub("%s", ""):gsub("^%l", string.upper)
end

local function IsSpellInPlayerBook(spellID)
    if not spellID then return false end

    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.FindBaseSpellByID and C_SpellBook.FindSpellOverrideByID and Enum and Enum.SpellBookSpellBank then
        local bank = Enum.SpellBookSpellBank.Player

        local ok, result = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
        if ok and result then return true end

        ok, result = pcall(C_SpellBook.FindBaseSpellByID, spellID)
        if ok and result and result ~= spellID then
            ok, result = pcall(C_SpellBook.IsSpellKnown, result, bank)
            if ok and result then return true end
        end

        ok, result = pcall(C_SpellBook.FindSpellOverrideByID, spellID)
        if ok and result and result ~= spellID then
            ok, result = pcall(C_SpellBook.IsSpellKnown, result, bank)
            if ok and result then return true end
        end

        return false
    end

    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, result = pcall(C_SpellBook.IsSpellInSpellBook, spellID)
        if ok then return result == true end
    end

    return true
end

local function ResolveOverrideSpellID(spellID)
    if not spellID then return nil end
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local ok, overrideID = pcall(C_SpellBook.FindSpellOverrideByID, spellID)
        if ok and overrideID and overrideID ~= spellID then
            return overrideID
        end
    end
    return spellID
end

local function ResolveSpellTexture(spellID)
    if not spellID then return nil end
    local texture
    if C_Spell and C_Spell.GetSpellTexture then
        texture = C_Spell.GetSpellTexture(spellID)
    end
    if not texture and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        texture = info and info.iconID
    end
    if not texture and C_Spell and C_Spell.RequestLoadSpellData then
        pcall(C_Spell.RequestLoadSpellData, spellID)
    end
    return texture
end

function RacialCooldowns:ClearCache()
    cacheRaceKey = nil
    cacheSpecID = nil
    cacheSpellID = nil
    cacheTexture = nil
end

function RacialCooldowns:GetSpellID()
    local raceKey = GetRaceKey()
    local specID = GetCurrentSpecID()

    if cacheSpellID and cacheRaceKey == raceKey and cacheSpecID == specID then
        return cacheSpellID
    end

    local spellList = RACIAL_SPELLS[raceKey]
    if type(spellList) ~= "table" then
        cacheRaceKey = raceKey
        cacheSpecID = specID
        cacheSpellID = ResolveOverrideSpellID(spellList)
        cacheTexture = nil
        return cacheSpellID
    end

    local fallback = spellList[1]
    local selected
    for _, spellID in ipairs(spellList) do
        if IsSpellInPlayerBook(spellID) then
            selected = spellID
            break
        end
    end

    cacheRaceKey = raceKey
    cacheSpecID = specID
    cacheSpellID = ResolveOverrideSpellID(selected or fallback)
    cacheTexture = nil
    return cacheSpellID
end

function RacialCooldowns:GetTexture(fallback)
    local spellID = self:GetSpellID()
    if not spellID then return fallback end
    if cacheTexture then return cacheTexture end
    cacheTexture = ResolveSpellTexture(spellID) or fallback
    return cacheTexture
end
