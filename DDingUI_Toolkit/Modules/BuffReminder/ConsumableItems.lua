--[[
    DDingToolKit - BuffReminder: Consumable Items
    Lookup tables of known consumable item IDs, keyed by consumable type.
    Ported from BuffReminders by zerbi.
]]

local _, ns = ...
local L = ns.L

-- Consumable items database
-- Values: true for simple membership, or table with { label, badge, priority }
ns.CONSUMABLE_ITEMS = {
    food = {
        -- TWW 11.0.0
        [222702] = { label = "2차" }, -- Skewered Fillet
        [222703] = { label = "2차" }, -- Simple Stew
        [222704] = { label = "2차" }, -- Unseasoned Field Steak
        [222705] = { label = "2차" }, -- Roasted Mycobloom
        [222706] = { label = "2차" }, -- Pan-Seared Mycobloom
        [222707] = { label = "2차" }, -- Hallowfall Chili
        [222708] = { label = "2차" }, -- Coreway Kabob
        [222709] = { label = "2차" }, -- Flashfire Fillet
        [222710] = { label = "체힘" }, -- Meat and Potatoes
        [222711] = { label = "체민" }, -- Rib Stickers
        [222712] = { label = "체지" }, -- Sweet and Sour Meatballs
        [222713] = { label = "체력" }, -- Tender Twilight Jerky
        [222714] = { label = "가속" }, -- Zesty Nibblers
        [222715] = { label = "치명" }, -- Fiery Fish Sticks
        [222716] = { label = "특화" }, -- Ginger-Glazed Fillet
        [222717] = { label = "유연" }, -- Salty Dog
        [222718] = { label = "가치" }, -- Deepfin Patty
        [222719] = { label = "가특" }, -- Sweet and Spicy Soup
        [222720] = { label = "고급" }, -- The Sushi Special
        [222721] = { label = "치특" }, -- Fish and Chips
        [222722] = { label = "유치" }, -- Salt Baked Seafood
        [222723] = { label = "유특" }, -- Marinated Tenderloins
        [222724] = { label = "체힘" }, -- Sizzling Honey Roast
        [222725] = { label = "체민" }, -- Mycobloom Risotto
        [222726] = { label = "체지" }, -- Stuffed Cave Peppers
        [222727] = { label = "체력" }, -- Angler's Delight
        [222728] = { label = "고급" }, -- Beledar's Bounty
        [222729] = { label = "고급" }, -- Empress' Farewell
        [222730] = { label = "고급" }, -- Jester's Board
        [222731] = { label = "고급" }, -- Outsider's Provisions
        [222732] = { label = "만찬" }, -- Feast of the Divine Day
        [222733] = { label = "만찬" }, -- Feast of the Midnight Masquerade
        [222735] = { label = "2차" }, -- Everything Stew
        [222736] = { label = "유가" }, -- Chippy Tea
        [222750] = { label = "2차", badge = "H" }, -- Hearty Skewered Fillet
        [222751] = { label = "2차", badge = "H" }, -- Hearty Simple Stew
        [222752] = { label = "2차", badge = "H" }, -- Hearty Unseasoned Field Steak
        [222753] = { label = "2차", badge = "H" }, -- Hearty Roasted Mycobloom
        [222754] = { label = "2차", badge = "H" }, -- Hearty Pan-Seared Mycobloom
        [222755] = { label = "2차", badge = "H" }, -- Hearty Hallowfall Chili
        [222756] = { label = "2차", badge = "H" }, -- Hearty Coreway Kabob
        [222757] = { label = "2차", badge = "H" }, -- Hearty Flashfire Fillet
        [222758] = { label = "체힘", badge = "H" }, -- Hearty Meat and Potatoes
        [222759] = { label = "체민", badge = "H" }, -- Hearty Rib Stickers
        [222760] = { label = "체지", badge = "H" }, -- Hearty Sweet and Sour Meatballs
        [222761] = { label = "체력", badge = "H" }, -- Hearty Tender Twilight Jerky
        [222762] = { label = "가속", badge = "H" }, -- Hearty Zesty Nibblers
        [222763] = { label = "치명", badge = "H" }, -- Hearty Fiery Fish Sticks
        [222764] = { label = "특화", badge = "H" }, -- Hearty Ginger-Glazed Fillet
        [222765] = { label = "유연", badge = "H" }, -- Hearty Salty Dog
        [222766] = { label = "가치", badge = "H" }, -- Hearty Deepfin Patty
        [222767] = { label = "가특", badge = "H" }, -- Hearty Sweet and Spicy Soup
        [222768] = { label = "고급", badge = "H" }, -- Hearty Sushi Special
        [222769] = { label = "치특", badge = "H" }, -- Hearty Fish and Chips
        [222770] = { label = "유치", badge = "H" }, -- Hearty Salt Baked Seafood
        [222771] = { label = "유특", badge = "H" }, -- Hearty Marinated Tenderloins
        [222772] = { label = "체힘", badge = "H" }, -- Hearty Sizzling Honey Roast
        [222773] = { label = "체민", badge = "H" }, -- Hearty Mycobloom Risotto
        [222774] = { label = "체지", badge = "H" }, -- Hearty Stuffed Cave Peppers
        [222775] = { label = "체력", badge = "H" }, -- Hearty Angler's Delight
        [222776] = { label = "고급", badge = "H" }, -- Hearty Beledar's Bounty
        [222777] = { label = "고급", badge = "H" }, -- Hearty Empress' Farewell
        [222778] = { label = "고급", badge = "H" }, -- Hearty Jester's Board
        [222779] = { label = "고급", badge = "H" }, -- Hearty Outsider's Provisions
        [222780] = { label = "만찬", badge = "H" }, -- Hearty Feast of the Divine Day
        [222781] = { label = "만찬", badge = "H" }, -- Hearty Feast of the Midnight Masquerade
        [222783] = { label = "2차", badge = "H" }, -- Hearty Everything Stew
        [222784] = { label = "유가", badge = "H" }, -- Hearty Chippy Tea
        [223966] = { label = "랜덤" }, -- Everything-on-a-Stick
        [223967] = { label = "2차" }, -- Protein Slurp
        [223968] = { label = "2차" }, -- Spongey Scramble
        [225592] = { label = "이속" }, -- Exquisitely Eviscerated Muscle

        -- TWW 11.1.0
        [235805] = { label = "고급" }, -- Authentic Undermine Clam Chowder
        [235853] = { label = "고급", badge = "H" }, -- Hearty Authentic Undermine Clam Chowder

        -- Midnight 12.0.0
        [242272] = { label = "고급" }, -- Quel'dorei Medley
        [242273] = { label = "고급" }, -- Blooming Feast
        [242274] = { label = "고급" }, -- Champion's Bento
        [242275] = { label = "1차" }, -- Royal Roast
        [242276] = { label = "특화" }, -- Braised Blood Hunter
        [242277] = { label = "가속" }, -- Crimson Calamari
        [242278] = { label = "치명" }, -- Tasty Smoked Tetra
        [242279] = { label = "중급" }, -- Baked Lucky Loa
        [242280] = { label = "특화" }, -- Buttered Root Crab
        [242281] = { label = "유연" }, -- Glitter Skewers
        [242282] = { label = "가속" }, -- Null and Void Plate
        [242283] = { label = "치명" }, -- Sun-Seared Lumifin
        [242284] = { label = "특화" }, -- Void-Kissed Fish Rolls
        [242285] = { label = "유연" }, -- Warped Wise Wings
        [242286] = { label = "가속" }, -- Fel-Kissed Filet
        [242287] = { label = "치명" }, -- Arcano Cutlets
        [242288] = { label = "중급" }, -- Twilight Angler's Medley
        [242289] = { label = "중급" }, -- Spellfire Filet
        [242290] = { label = "치특" }, -- Wise Tails
        [242291] = { label = "유특" }, -- Fried Bloomtail
        [242292] = { label = "유치" }, -- Eversong Pudding
        [242293] = { label = "가특" }, -- Sunwell Delight
        [242294] = { label = "특화" }, -- Felberry Figs
        [242295] = { label = "가치" }, -- Hearthflame Supper
        [242296] = { label = "유가" }, -- Bloodthistle-wrapped Cutlets
        [242302] = { label = "저급" }, -- Bloom Skewers
        [242303] = { label = "저급" }, -- Mana-Infused Stew
        [242304] = { label = "치특" }, -- Spiced Biscuits
        [242305] = { label = "유특" }, -- Silvermoon Standard
        [242306] = { label = "유치" }, -- Forager's Medley
        [242307] = { label = "가특" }, -- Quick Sandwich
        [242308] = { label = "가치" }, -- Portable Snack
        [242309] = { label = "유가" }, -- Farstrider Rations
        [242532] = { label = "저급" }, -- [PH] Vegetarian Recipe
        [242744] = { label = "고급", badge = "H" }, -- Hearty Quel'dorei Medley
        [242745] = { label = "고급", badge = "H" }, -- Hearty Blooming Feast
        [242746] = { label = "고급", badge = "H" }, -- Hearty Champion's Bento
        [242747] = { label = "1차", badge = "H" }, -- Hearty Royal Roast
        [242748] = { label = "특화", badge = "H" }, -- Hearty Braised Blood Hunter
        [242749] = { label = "가속", badge = "H" }, -- Hearty Crimson Calamari
        [242750] = { label = "치명", badge = "H" }, -- Hearty Tasty Smoked Tetra
        [242751] = { label = "중급", badge = "H" }, -- Hearty Rootland Surprise
        [242752] = { label = "특화", badge = "H" }, -- Hearty Buttered Root Crab
        [242753] = { label = "유연", badge = "H" }, -- Hearty Glitter Skewers
        [242754] = { label = "가속", badge = "H" }, -- Hearty Null and Void Plate
        [242755] = { label = "치명", badge = "H" }, -- Hearty Sun-Seared Lumifin
        [242756] = { label = "특화", badge = "H" }, -- Hearty Void-Kissed Fish Rolls
        [242757] = { label = "유연", badge = "H" }, -- Hearty Warped Wise Wings
        [242758] = { label = "가속", badge = "H" }, -- Hearty Fel-Kissed Filet
        [242759] = { label = "치명", badge = "H" }, -- Hearty Arcano Cutlets
        [242760] = { label = "중급", badge = "H" }, -- Hearty Twilight Angler's Medley
        [242761] = { label = "중급", badge = "H" }, -- Hearty Spellfire Filet
        [242762] = { label = "치특", badge = "H" }, -- Hearty Wise Tails
        [242763] = { label = "유특", badge = "H" }, -- Hearty Fried Bloomtail
        [242764] = { label = "유치", badge = "H" }, -- Hearty Eversong Pudding
        [242765] = { label = "가특", badge = "H" }, -- Hearty Sunwell Delight
        [242766] = { label = "특화", badge = "H" }, -- Hearty Felberry Figs
        [242767] = { label = "가치", badge = "H" }, -- Hearty Hearthflame Supper
        [242768] = { label = "유가", badge = "H" }, -- Hearty Bloodthistle-Wrapped Cutlets
        [242769] = { label = "저급", badge = "H" }, -- Hearty Bloom Skewers
        [242770] = { label = "저급", badge = "H" }, -- Hearty Mana-Infused Stew
        [242771] = { label = "치특", badge = "H" }, -- Hearty Spiced Biscuits
        [242772] = { label = "유특", badge = "H" }, -- Hearty Silvermoon Standard
        [242773] = { label = "유치", badge = "H" }, -- Hearty Forager's Medley
        [242774] = { label = "가특", badge = "H" }, -- Hearty Quick Sandwich
        [242775] = { label = "가치", badge = "H" }, -- Hearty Portable Snack
        [242776] = { label = "유가", badge = "H" }, -- Hearty Farstrider Rations
        [255845] = { label = "만찬" }, -- Silvermoon Parade
        [255846] = { label = "만찬" }, -- Harandar Celebration
        [255847] = { label = "1차" }, -- Impossibly Royal Roast
        [255848] = { label = "고급" }, -- Flora Frenzy
        [266985] = { label = "만찬", badge = "H" }, -- Hearty Silvermoon Parade
        [266986] = { label = "고급", badge = "H" }, -- Hearty Quel'dorei Medley
        [266996] = { label = "만찬", badge = "H" }, -- Hearty Harandar Celebration
        [267000] = { label = "고급", badge = "H" }, -- Hearty Flora Frenzy
        [268679] = { label = "1차", badge = "H" }, -- Hearty Impossibly Royal Roast
        [268680] = { label = "고급", badge = "H" }, -- Hearty Flora Frenzy
    },
    flask = {
        -- TWW 11.0.0 (3 quality tiers)
        [212269] = { label = "치명" }, -- Flask of Tempered Aggression
        [212270] = { label = "치명" }, -- Flask of Tempered Aggression (quality 2)
        [212271] = { label = "치명" }, -- Flask of Tempered Aggression (quality 3)
        [212272] = { label = "가속" }, -- Flask of Tempered Swiftness
        [212273] = { label = "가속" }, -- Flask of Tempered Swiftness (quality 2)
        [212274] = { label = "가속" }, -- Flask of Tempered Swiftness (quality 3)
        [212275] = { label = "특화" }, -- Flask of Tempered Versatility
        [212276] = { label = "특화" }, -- Flask of Tempered Versatility (quality 2)
        [212277] = { label = "특화" }, -- Flask of Tempered Versatility (quality 3)
        [212278] = { label = "유연" }, -- Flask of Tempered Mastery
        [212279] = { label = "유연" }, -- Flask of Tempered Mastery (quality 2)
        [212280] = { label = "유연" }, -- Flask of Tempered Mastery (quality 3)
        [212281] = { label = "랜덤" }, -- Flask of Alchemical Chaos
        [212282] = { label = "랜덤" }, -- Flask of Alchemical Chaos (quality 2)
        [212283] = { label = "랜덤" }, -- Flask of Alchemical Chaos (quality 3)
        [212299] = { label = "힐링" }, -- Flask of Saving Graces
        [212300] = { label = "힐링" }, -- Flask of Saving Graces (quality 2)
        [212301] = { label = "힐링" }, -- Flask of Saving Graces (quality 3)
        -- TWW 11.0.0 (fleeting/cauldron)
        [212725] = { label = "치명", badge = "F", priority = 1 },
        [212727] = { label = "치명", badge = "F", priority = 1 },
        [212728] = { label = "치명", badge = "F", priority = 1 },
        [212729] = { label = "가속", badge = "F", priority = 1 },
        [212730] = { label = "가속", badge = "F", priority = 1 },
        [212731] = { label = "가속", badge = "F", priority = 1 },
        [212732] = { label = "특화", badge = "F", priority = 1 },
        [212733] = { label = "특화", badge = "F", priority = 1 },
        [212734] = { label = "특화", badge = "F", priority = 1 },
        [212735] = { label = "유연", badge = "F", priority = 1 },
        [212736] = { label = "유연", badge = "F", priority = 1 },
        [212738] = { label = "유연", badge = "F", priority = 1 },
        [212739] = { label = "랜덤", badge = "F", priority = 1 },
        [212740] = { label = "랜덤", badge = "F", priority = 1 },
        [212741] = { label = "랜덤", badge = "F", priority = 1 },
        [212745] = { label = "힐링", badge = "F", priority = 1 },
        [212746] = { label = "힐링", badge = "F", priority = 1 },
        [212747] = { label = "힐링", badge = "F", priority = 1 },
        -- Midnight 12.0.0 (2 quality tiers)
        [241320] = { label = "특화" }, -- Flask of Thalassian Resistance
        [241321] = { label = "특화" },
        [241322] = { label = "유연" }, -- Flask of the Magisters
        [241323] = { label = "유연" },
        [241324] = { label = "가속" }, -- Flask of the Blood Knights
        [241325] = { label = "가속" },
        [241326] = { label = "치명" }, -- Flask of the Shattered Sun
        [241327] = { label = "치명" },
        [241334] = { label = "PvP" }, -- Vicious Thalassian Flask of Honor
        [241335] = { label = "PvP" },
        -- Midnight 12.0.0 (fleeting)
        [245926] = { label = "특화", badge = "F", priority = 1 },
        [245927] = { label = "특화", badge = "F", priority = 1 },
        [245928] = { label = "치명", badge = "F", priority = 1 },
        [245929] = { label = "치명", badge = "F", priority = 1 },
        [245930] = { label = "가속", badge = "F", priority = 1 },
        [245931] = { label = "가속", badge = "F", priority = 1 },
        [245932] = { label = "유연", badge = "F", priority = 1 },
        [245933] = { label = "유연", badge = "F", priority = 1 },
    },
    rune = {
        [259085] = 1, -- Void-Touched Augment Rune (Midnight)
        [243191] = 2, -- Ethereal Augment Rune (TWW permanent)
        [246492] = 3, -- Soulgorged Augment Rune (TWW, persists through death)
        [224572] = 4, -- Crystallized Augment Rune (TWW single use)
        [211495] = 5, -- Dreambound Augment Rune (Dragonflight)
        [201325] = 6, -- Draconic Augment Rune (Dragonflight)
        [181468] = 7, -- Veiled Augment Rune (Shadowlands)
    },
    weapon = {
        -- Midnight 12.0.0
        [237367] = true, -- Refulgent Weightstone
        [237369] = true, -- Refulgent Weightstone (quality 2)
        [237370] = true, -- Refulgent Whetstone
        [237371] = true, -- Refulgent Whetstone (quality 2)
        [243733] = true, -- Thalassian Phoenix Oil
        [243734] = true, -- Thalassian Phoenix Oil (quality 2)
        [243735] = true, -- Oil of Dawn
        [243736] = true, -- Oil of Dawn (quality 2)
        [243737] = true, -- Smuggler's Enchanted Edge
        [243738] = true, -- Smuggler's Enchanted Edge (quality 2)
        [257749] = true, -- Laced Zoomshots
        [257750] = true, -- Laced Zoomshots (quality 2)
        [257751] = true, -- Weighted Boomshots
        [257752] = true, -- Weighted Boomshots (quality 2)
    },
}

-- Fleeting flask item IDs (should NOT be remembered — overwrite regular preference)
ns.FLEETING_FLASK_ITEMS = {
    [245926] = true,
    [245927] = true,
    [245928] = true,
    [245929] = true,
    [245930] = true,
    [245931] = true,
    [245932] = true,
    [245933] = true,
}
