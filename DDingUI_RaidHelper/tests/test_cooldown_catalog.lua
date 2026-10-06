local addonName = "DDingUI_RaidHelper"
local ns = {
    db = { cooldownVisibility = {} },
    IsSecret = function() return false end,
}

C_Spell = {
    GetSpellName = function(spellID)
        return spellID == 120517 and "후광" or nil
    end,
}

assert(loadfile("Data/CooldownCatalog.lua"))(addonName, ns)
assert(loadfile("Runtime/Engine.lua"))(addonName, ns)

local holy = ns.CooldownCatalog:GetSpec(257)
assert(holy and holy.name == "신성 사제")
local halo = ns.CooldownCatalog:GetEntry(257, 120517)
assert(halo and halo.category == "semi" and halo.defaultShown == true)
assert(ns.CooldownCatalog:GetSpellName(257, 120517) == "후광")
assert(#ns.CooldownCatalog:GetSpecIDs() == 34, "all healer and DPS specs need a catalog")
assert(ns.CooldownCatalog:GetEntry(1480, 1226019).category == "major")

ns.Engine.model = {
    cooldownsBySpec = {
        [257] = {
            { spellID = 120517, label = "Halo", t = 10 },
            { spellID = 47788, label = "Guardian Spirit", t = 20 },
        },
    },
}
ns.Engine.playerSpecID = 257

local visible = ns.Engine:GetCooldowns()
assert(#visible == 1 and visible[1].spellID == 120517)

ns.db.cooldownVisibility[257] = {
    [120517] = false,
    [47788] = true,
}
visible = ns.Engine:GetCooldowns()
assert(#visible == 1 and visible[1].spellID == 47788)

ns.Engine.model = {
    dpsProfilesBySpec = { [251] = { specID = 251 } },
    cooldownsBySpec = { [251] = { { spellID = 51271, t = 10 } } },
}
ns.Engine.playerSpecID = 251
assert(#ns.Engine:GetCooldowns() == 1)
assert(ns.Engine:GetHealerProfile().specID == 251)
ns.Engine.playerSpecID = 252
assert(#ns.Engine:GetCooldowns() == 0)

print("RaidHelper cooldown catalog test OK")
