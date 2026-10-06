local _, ns = ...

local Catalog = {}
ns.CooldownCatalog = Catalog

-- [STYLE] Lorrgs의 직업/전문화/외생기 선택 개념을 RaidHelper 용도에
-- 맞춰 주요 힐업/세미 쿨기/외생기/개인·유틸 네 그룹으로 재구성한다.
local GROUPS = {
    { key = "major", label = "주요 쿨기", description = "현재 전문화의 주요 기술 사용 시점" },
    { key = "semi", label = "보조 쿨기", description = "주요 기술 사이에 사용하는 기술" },
    { key = "external", label = "외생기", description = "특정 대상에게 사용하는 생존 지원기" },
    { key = "personal", label = "개인 · 유틸", description = "개인 생존기와 이동·지원 기술" },
}

local SPECS = {
    [65] = {
        name = "신성 성기사",
        spells = {
            { spellID = 31821, label = "Aura Mastery", category = "major", defaultShown = true },
            { spellID = 31884, label = "Avenging Wrath", category = "major", defaultShown = true },
            { spellID = 375576, label = "Divine Toll", category = "semi", defaultShown = true },
            { spellID = 200025, label = "Beacon of Virtue", category = "semi", defaultShown = true },
            { spellID = 6940, label = "Blessing of Sacrifice", category = "external", defaultShown = false },
            { spellID = 1022, label = "Blessing of Protection", category = "external", defaultShown = false },
            { spellID = 498, label = "Divine Protection", category = "personal", defaultShown = false },
            { spellID = 642, label = "Divine Shield", category = "personal", defaultShown = false },
        },
    },
    [105] = {
        name = "회복 드루이드",
        spells = {
            { spellID = 740, label = "Tranquility", category = "major", defaultShown = true },
            { spellID = 33891, label = "Incarnation: Tree of Life", category = "major", defaultShown = true },
            { spellID = 197721, label = "Flourish", category = "major", defaultShown = true },
            { spellID = 391528, label = "Convoke the Spirits", category = "semi", defaultShown = true },
            { spellID = 102342, label = "Ironbark", category = "external", defaultShown = false },
            { spellID = 5487, label = "Bear Form", category = "personal", defaultShown = false },
            { spellID = 22812, label = "Barkskin", category = "personal", defaultShown = false },
            { spellID = 106898, label = "Stampeding Roar", category = "personal", defaultShown = false },
        },
    },
    [256] = {
        name = "수양 사제",
        spells = {
            { spellID = 62618, label = "Power Word: Barrier", category = "major", defaultShown = true },
            { spellID = 421453, label = "Ultimate Penitence", category = "major", defaultShown = true },
            { spellID = 472433, label = "Voidwraith", category = "major", defaultShown = true },
            { spellID = 246287, label = "Evangelism", category = "semi", defaultShown = true },
            { spellID = 194509, label = "Power Word: Radiance", category = "semi", defaultShown = true },
            { spellID = 33206, label = "Pain Suppression", category = "external", defaultShown = false },
            { spellID = 586, label = "Fade", category = "personal", defaultShown = false },
            { spellID = 19236, label = "Desperate Prayer", category = "personal", defaultShown = false },
            { spellID = 73325, label = "Leap of Faith", category = "personal", defaultShown = false },
        },
    },
    [257] = {
        name = "신성 사제",
        spells = {
            { spellID = 64843, label = "Divine Hymn", category = "major", defaultShown = true },
            { spellID = 64901, label = "Symbol of Hope", category = "major", defaultShown = true },
            { spellID = 265202, label = "Holy Word: Salvation", category = "major", defaultShown = true },
            { spellID = 120517, label = "Halo", category = "semi", defaultShown = true },
            { spellID = 200183, label = "Apotheosis", category = "semi", defaultShown = true },
            { spellID = 47788, label = "Guardian Spirit", category = "external", defaultShown = false },
            { spellID = 586, label = "Fade", category = "personal", defaultShown = false },
            { spellID = 19236, label = "Desperate Prayer", category = "personal", defaultShown = false },
            { spellID = 73325, label = "Leap of Faith", category = "personal", defaultShown = false },
            { spellID = 27827, label = "Spirit of Redemption", category = "personal", defaultShown = false },
        },
    },
    [264] = {
        name = "복원 주술사",
        spells = {
            { spellID = 98008, label = "Spirit Link Totem", category = "major", defaultShown = true },
            { spellID = 108280, label = "Healing Tide Totem", category = "major", defaultShown = true },
            { spellID = 114052, label = "Ascendance", category = "major", defaultShown = true },
            { spellID = 378270, label = "Totemic Recall", category = "semi", defaultShown = true },
            { spellID = 79206, label = "Spiritwalker's Grace", category = "personal", defaultShown = false },
            { spellID = 108271, label = "Astral Shift", category = "personal", defaultShown = false },
            { spellID = 192077, label = "Wind Rush Totem", category = "personal", defaultShown = false },
            { spellID = 381755, label = "Earthliving Weapon", category = "personal", defaultShown = false },
        },
    },
    [270] = {
        name = "운무 수도사",
        spells = {
            { spellID = 115310, label = "Revival", category = "major", defaultShown = true },
            { spellID = 388615, label = "Restoral", category = "major", defaultShown = true },
            { spellID = 322118, label = "Invoke Yu'lon", category = "major", defaultShown = true },
            { spellID = 325197, label = "Invoke Chi-Ji", category = "major", defaultShown = true },
            { spellID = 443028, label = "Celestial Conduit", category = "major", defaultShown = true },
            { spellID = 116680, label = "Thunder Focus Tea", category = "semi", defaultShown = true },
            { spellID = 116849, label = "Life Cocoon", category = "external", defaultShown = false },
            { spellID = 115203, label = "Fortifying Brew", category = "personal", defaultShown = false },
            { spellID = 322109, label = "Touch of Death", category = "personal", defaultShown = false },
        },
    },
    [1468] = {
        name = "보존 기원사",
        spells = {
            { spellID = 359816, label = "Dream Flight", category = "major", defaultShown = true },
            { spellID = 363534, label = "Rewind", category = "major", defaultShown = true },
            { spellID = 370537, label = "Stasis", category = "major", defaultShown = true },
            { spellID = 370564, label = "Emerald Communion", category = "major", defaultShown = true },
            { spellID = 355936, label = "Dream Breath", category = "semi", defaultShown = true },
            { spellID = 370553, label = "Tip the Scales", category = "semi", defaultShown = true },
            { spellID = 374227, label = "Zephyr", category = "semi", defaultShown = true },
            { spellID = 357170, label = "Time Dilation", category = "external", defaultShown = false },
            { spellID = 406789, label = "Stretch Time", category = "external", defaultShown = false },
            { spellID = 406732, label = "Spatial Paradox", category = "external", defaultShown = false },
            { spellID = 363916, label = "Obsidian Scales", category = "personal", defaultShown = false },
            { spellID = 370665, label = "Rescue", category = "personal", defaultShown = false },
            { spellID = 374968, label = "Time Spiral", category = "personal", defaultShown = false },
        },
    },
}

-- [STYLE] Every damage specialization has a selectable, log-backed timeline.
-- Absent or unselected talent spells remain in the catalog but produce no marker.
local DPS_SPECS = {
    [251] = { "냉기 죽음의 기사", {51271, "Pillar of Frost"}, {47568, "Empower Rune Weapon"} },
    [252] = { "부정 죽음의 기사", {42650, "Army of the Dead"}, {63560, "Dark Transformation"} },
    [577] = { "파멸 악마사냥꾼", {191427, "Metamorphosis"}, {198013, "Eye Beam"} },
    [1480] = { "포식 악마사냥꾼", {1226019, "Reap"}, {1221150, "Collapsing Star", false} },
    [102] = { "조화 드루이드", {102560, "Incarnation: Chosen of Elune"}, {205636, "Force of Nature"} },
    [103] = { "야성 드루이드", {106951, "Berserk"}, {391528, "Convoke the Spirits"} },
    [1467] = { "황폐 기원사", {375087, "Dragonrage"}, {357210, "Deep Breath"} },
    [1473] = { "증강 기원사", {403631, "Breath of Eons"}, {395152, "Ebon Might"} },
    [253] = { "야수 사냥꾼", {19574, "Bestial Wrath"} },
    [254] = { "사격 사냥꾼", {288613, "Trueshot"}, {260243, "Volley"} },
    [255] = { "생존 사냥꾼", {1253859, "Takedown"}, {1264949, "Moonlight Chakram"} },
    [62] = { "비전 마법사", {365350, "Arcane Surge"}, {321507, "Touch of the Magi"} },
    [63] = { "화염 마법사", {190319, "Combustion"}, {153561, "Meteor"} },
    [64] = { "냉기 마법사", {84714, "Frozen Orb", "semi"} },
    [269] = { "풍운 수도사", {123904, "Invoke Xuen"} },
    [70] = { "징벌 성기사", {31884, "Avenging Wrath"}, {255937, "Wake of Ashes"} },
    [258] = { "암흑 사제", {228260, "Void Eruption"}, {10060, "Power Infusion"} },
    [259] = { "암살 도적", {360194, "Deathmark"}, {385627, "Kingsbane"} },
    [260] = { "무법 도적", {13750, "Adrenaline Rush"}, {51690, "Killing Spree"} },
    [261] = { "잠행 도적", {185313, "Shadow Dance"}, {280719, "Secret Technique"} },
    [262] = { "정기 주술사", {114050, "Ascendance"}, {191634, "Stormkeeper"} },
    [263] = { "고양 주술사", {114051, "Ascendance"} },
    [265] = { "고통 흑마법사", {205180, "Summon Darkglare"} },
    [266] = { "악마 흑마법사", {265187, "Summon Demonic Tyrant"} },
    [267] = { "파괴 흑마법사", {1122, "Summon Infernal"} },
    [71] = { "무기 전사", {107574, "Avatar"} },
    [72] = { "분노 전사", {1719, "Recklessness"}, {385059, "Odyn's Fury"} },
}

for specID, data in pairs(DPS_SPECS) do
    SPECS[specID] = {
        name = data[1],
        spells = {
            { spellID = data[2][1], label = data[2][2], category = data[2][3] or "major", defaultShown = true },
        },
    }
    if data[3] then
        table.insert(SPECS[specID].spells, {
            spellID = data[3][1], label = data[3][2], category = "semi",
            defaultShown = data[3][3] ~= false,
        })
    end
end

-- 12.1 KB에서 Spell ID와 재사용 대기시간이 확인된 추가 딜/생존 기술.
-- 실제 타임라인 시점은 수집한 WCL 시전 기록이 있을 때만 생성된다.
local DPS_EXTRA_SPELLS = {
    [251] = { {279302, "Frostwyrm's Fury", "major"}, {1249658, "Breath of Sindragosa", "major"}, {48707, "Anti-Magic Shell", "personal"}, {51052, "Anti-Magic Zone", "external"} },
    [252] = { {1233448, "Dark Transformation", "major"}, {1247378, "Putrefy", "semi"}, {48707, "Anti-Magic Shell", "personal"}, {51052, "Anti-Magic Zone", "external"} },
    [577] = { {258860, "Essence Break", "semi"}, {370965, "The Hunt", "semi"}, {212800, "Blur", "personal"}, {196718, "Darkness", "external"} },
    [1480] = { {1245412, "Voidblade", "semi"}, {1234195, "Void Nova", "semi"}, {1241937, "Soul Immolation", "major"}, {1246167, "The Hunt", "semi"}, {212800, "Blur", "personal"}, {196718, "Darkness", "external"} },
    [102] = { {202770, "Fury of Elune", "semi"}, {194223, "Celestial Alignment", "major"}, {22812, "Barkskin", "personal"}, {106898, "Stampeding Roar", "personal"} },
    [103] = { {274837, "Feral Frenzy", "semi"}, {102543, "Incarnation: Avatar of Ashamane", "major"}, {22812, "Barkskin", "personal"}, {106898, "Stampeding Roar", "personal"} },
    [1467] = { {359073, "Eternity Surge", "semi"}, {370553, "Tip the Scales", "semi"}, {363916, "Obsidian Scales", "personal"}, {374227, "Zephyr", "external"} },
    [1473] = { {396286, "Upheaval", "semi"}, {404977, "Time Skip", "semi"}, {363916, "Obsidian Scales", "personal"}, {374227, "Zephyr", "external"} },
    [253] = { {264735, "Survival of the Fittest", "personal"}, {186265, "Aspect of the Turtle", "personal"}, {109304, "Exhilaration", "personal"}, {34477, "Misdirection", "external"} },
    [254] = { {212431, "Explosive Shot", "semi"}, {264735, "Survival of the Fittest", "personal"}, {186265, "Aspect of the Turtle", "personal"} },
    [255] = { {1261193, "Boomstick", "semi"}, {186289, "Aspect of the Eagle", "semi"}, {264735, "Survival of the Fittest", "personal"}, {186265, "Aspect of the Turtle", "personal"} },
    [62] = { {12051, "Evocation", "semi"}, {205025, "Presence of Mind", "semi"}, {45438, "Ice Block", "personal"}, {342245, "Alter Time", "personal"} },
    [63] = { {45438, "Ice Block", "personal"}, {342245, "Alter Time", "personal"}, {55342, "Mirror Image", "personal"} },
    [64] = { {205021, "Ray of Frost", "semi"}, {45438, "Ice Block", "personal"}, {342245, "Alter Time", "personal"}, {235219, "Cold Snap", "personal"} },
    [269] = { {392983, "Strike of the Windlord", "semi"}, {1249625, "Zenith", "major"}, {1217413, "Slicing Winds", "semi"}, {443028, "Celestial Conduit", "major"}, {115203, "Fortifying Brew", "personal"} },
    [70] = { {343527, "Execution Sentence", "semi"}, {403876, "Divine Protection", "personal"}, {642, "Divine Shield", "personal"}, {6940, "Blessing of Sacrifice", "external"} },
    [258] = { {263165, "Void Torrent", "semi"}, {47585, "Dispersion", "personal"}, {19236, "Desperate Prayer", "personal"} },
    [259] = { {31224, "Cloak of Shadows", "personal"}, {5277, "Evasion", "personal"}, {381623, "Thistle Tea", "semi"} },
    [260] = { {315508, "Roll the Bones", "semi"}, {271877, "Blade Rush", "semi"}, {381989, "Keep It Rolling", "semi"}, {31224, "Cloak of Shadows", "personal"}, {5277, "Evasion", "personal"} },
    [261] = { {121471, "Shadow Blades", "major"}, {426591, "Goremaw", "semi"}, {31224, "Cloak of Shadows", "personal"}, {5277, "Evasion", "personal"} },
    [262] = { {198067, "Fire Elemental", "major"}, {192249, "Storm Elemental", "major"}, {108271, "Astral Shift", "personal"}, {192077, "Wind Rush Totem", "personal"} },
    [263] = { {197214, "Sundering", "semi"}, {384352, "Doom Winds", "semi"}, {108271, "Astral Shift", "personal"}, {192077, "Wind Rush Totem", "personal"} },
    [265] = { {1257052, "Dark Harvest", "major"}, {104773, "Unending Resolve", "personal"}, {108416, "Dark Pact", "personal"}, {48020, "Demonic Circle: Teleport", "personal"} },
    [266] = { {1276672, "Summon Doomguard", "major"}, {1276452, "Grimoire: Imp Lord", "major"}, {1276467, "Grimoire: Fel Ravager", "major"}, {104773, "Unending Resolve", "personal"}, {108416, "Dark Pact", "personal"} },
    [267] = { {152108, "Cataclysm", "semi"}, {80240, "Havoc", "semi"}, {104773, "Unending Resolve", "personal"}, {108416, "Dark Pact", "personal"} },
    [71] = { {167105, "Colossus Smash", "semi"}, {227847, "Bladestorm", "semi"}, {97462, "Rallying Cry", "external"}, {118038, "Die by the Sword", "personal"} },
    [72] = { {228920, "Ravager", "semi"}, {227847, "Bladestorm", "semi"}, {97462, "Rallying Cry", "external"}, {184364, "Enraged Regeneration", "personal"} },
}
for specID, spells in pairs(DPS_EXTRA_SPELLS) do
    for _, spell in ipairs(spells) do
        local category = spell[3]
        table.insert(SPECS[specID].spells, {
            spellID = spell[1], label = spell[2], category = category,
            defaultShown = category == "major" or category == "semi",
        })
    end
end

local SPEC_IDS = {}
for specID, spec in pairs(SPECS) do
    SPEC_IDS[#SPEC_IDS + 1] = specID
    spec.bySpell = {}
    for _, spell in ipairs(spec.spells) do
        spec.bySpell[spell.spellID] = spell
    end
end
table.sort(SPEC_IDS)

function Catalog:GetSpecIDs()
    return SPEC_IDS
end

function Catalog:GetGroups()
    return GROUPS
end

function Catalog:GetSpec(specID)
    specID = tonumber(specID)
    return specID and SPECS[specID] or nil
end

function Catalog:GetEntry(specID, spellID)
    local spec = self:GetSpec(specID)
    spellID = tonumber(spellID)
    return spec and spellID and spec.bySpell[spellID] or nil
end

function Catalog:GetSpellName(specID, spellID)
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif type(GetSpellInfo) == "function" then
        name = GetSpellInfo(spellID)
    end
    if (not ns.IsSecret or not ns:IsSecret(name)) and name then
        return name
    end
    local entry = self:GetEntry(specID, spellID)
    return entry and entry.label or ("주문 " .. tostring(spellID))
end

function Catalog:GetOverride(visibility, specID, spellID)
    if type(visibility) ~= "table" then return nil end
    local specValues = visibility[specID] or visibility[tostring(specID)]
    if type(specValues) ~= "table" then return nil end
    local value = specValues[spellID]
    if value == nil then value = specValues[tostring(spellID)] end
    if value == nil then return nil end
    return value == true
end

function Catalog:IsShown(specID, spellID, visibility)
    local override = self:GetOverride(visibility, specID, spellID)
    if override ~= nil then return override end
    local entry = self:GetEntry(specID, spellID)
    if not entry then return true end
    return entry.defaultShown ~= false
end
