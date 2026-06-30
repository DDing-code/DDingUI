local ns = select(2, ...)
local DDingUI = ns.Addon

DDingUI.CustomIconData = DDingUI.CustomIconData or {}
local Data = DDingUI.CustomIconData

Data.SPEC_LIST = {
    {id=62, name="Arcane", classID=8, icon=135932},
    {id=63, name="Fire", classID=8, icon=135810},
    {id=64, name="Frost", classID=8, icon=135846},
    {id=65, name="Holy", classID=2, icon=135920},
    {id=66, name="Protection", classID=2, icon=236264},
    {id=70, name="Retribution", classID=2, icon=135873},
    {id=71, name="Arms", classID=1, icon=132355},
    {id=72, name="Fury", classID=1, icon=132347},
    {id=73, name="Protection", classID=1, icon=132341},
    {id=102, name="Balance", classID=11, icon=136096},
    {id=103, name="Feral", classID=11, icon=132115},
    {id=104, name="Guardian", classID=11, icon=132276},
    {id=105, name="Restoration", classID=11, icon=136041},
    {id=250, name="Blood", classID=6, icon=135770},
    {id=251, name="Frost", classID=6, icon=135773},
    {id=252, name="Unholy", classID=6, icon=135775},
    {id=253, name="Beast Mastery", classID=3, icon=461112},
    {id=254, name="Marksmanship", classID=3, icon=236179},
    {id=255, name="Survival", classID=3, icon=461113},
    {id=256, name="Discipline", classID=5, icon=135940},
    {id=257, name="Holy", classID=5, icon=237542},
    {id=258, name="Shadow", classID=5, icon=136207},
    {id=259, name="Assassination", classID=4, icon=236270},
    {id=260, name="Outlaw", classID=4, icon=236286},
    {id=261, name="Subtlety", classID=4, icon=132320},
    {id=262, name="Elemental", classID=7, icon=136048},
    {id=263, name="Enhancement", classID=7, icon=237581},
    {id=264, name="Restoration", classID=7, icon=136052},
    {id=265, name="Affliction", classID=9, icon=136145},
    {id=266, name="Demonology", classID=9, icon=136172},
    {id=267, name="Destruction", classID=9, icon=136186},
    {id=268, name="Brewmaster", classID=10, icon=608951},
    {id=269, name="Windwalker", classID=10, icon=608953},
    {id=270, name="Mistweaver", classID=10, icon=608952},
    {id=577, name="Havoc", classID=12, icon=1247264},
    {id=581, name="Vengeance", classID=12, icon=1247265},
    {id=1480, name="Devourer", classID=12, icon=7455385},
    {id=1467, name="Devastation", classID=13, icon=4511811},
    {id=1468, name="Preservation", classID=13, icon=4511812},
    {id=1473, name="Augmentation", classID=13, icon=5198700},
}

Data.ITEM_SPELL_MAP = {
    [5512]   = 6262,
    [224464] = 452930,
    [255327] = 336126,
    [255616] = 336126,
    [241304] = 1234768,
    [241305] = 1234768,
    [241308] = 1236616,
    [241309] = 1236616,
    [245898] = 1236616,
    [245897] = 1236616,
    [241288] = 1236994,
    [241289] = 1236994,
    [245902] = 1236994,
    [245903] = 1236994,
    [241300] = 1234770,
    [241301] = 1234770,
    [245917] = 1234770,
    [245916] = 1234770,
    [211878] = 431416,
    [211879] = 431416,
    [211880] = 431416,
}

Data.ITEM_COMBAT_LOCKOUT_ITEMS = {
    [5512] = true,
    [224464] = true,
}

Data.ITEM_COMBAT_LOCKOUT_SPELLS = {
    [6262] = true,
    [452930] = true,
}

Data.QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
Data.FALLBACK_SPELL_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
Data.FALLBACK_ITEM_ICON = "Interface\\Icons\\INV_Potion_93"
Data.FALLBACK_SLOT_ICON = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01"
Data.FALLBACK_RACIAL_ICON = "Interface\\Icons\\Spell_magic_polymorphrabbit"
Data.CUSTOM_ICON_EFFECT_GRACE_SECONDS = 1.5

Data.CUSTOM_AURA_ICON_TEXTURES = {
    [1236616] = 7548911,
    [1236994] = 7548916,
    [1239479] = "Interface\\Icons\\INV_12_Profession_Alchemy_VoidPotion_Blue",
    [374968] = 4622479,
    [2825] = "Interface\\Icons\\Spell_Nature_BloodLust",
}

Data.CUSTOM_AURA_ICON_ITEM_FALLBACKS = {
    [1236616] = 241308,
    [1236994] = 241288,
    [1239479] = 241294,
}

Data.BLOODLUST_AURA_IDS = {
    2825, 32182, 80353, 90355, 160452, 264667, 390386,
    146555, 178207, 230935, 256740, 292686, 309658, 381301, 444257,
}

Data.BLOODLUST_DEBUFFS = {
    [57723]  = 32182,
    [57724]  = 2825,
    [80354]  = 80353,
    [95809]  = 90355,
    [160455] = 264667,
    [264689] = 264667,
    [390435] = 390386,
}

Data.CUSTOM_TIMED_AURA_CONFIGS = {
    [1236616] = { duration = 30, trigger = "spellcast" },
    [1236994] = { duration = 30, trigger = "spellcast" },
    [1239479] = { duration = 10, trigger = "spellcast" },
    [374968]  = { duration = 10, trigger = "timespiral" },
    [2825]    = { duration = 40, trigger = "bloodlust" },
}

Data.TIME_SPIRAL_TRIGGERS = {
    [48265] = true, [195072] = true, [189110] = true, [1850] = true,
    [252216] = true, [358267] = true, [186257] = true, [1953] = true,
    [212653] = true, [361138] = true, [119085] = true, [190784] = true,
    [73325] = true, [2983] = true, [192063] = true, [58875] = true,
    [79206] = true, [48020] = true, [6544] = true,
}

Data.TIME_SPIRAL_GLOW_FILTERS = {
    { talentID = 427640, spells = { 198793, 370965, 195072 } },
    { talentID = 427794, spells = { 195072 } },
    { talentID = 385899, spells = { 385899 } },
}

Data.TIME_SPIRAL_GLOW_SUPPRESS_SECONDS = 1.5

Data.AURA_EQUIVALENT_IDS = {}
for _, spellID in ipairs(Data.BLOODLUST_AURA_IDS) do
    Data.AURA_EQUIVALENT_IDS[spellID] = Data.BLOODLUST_AURA_IDS
end
