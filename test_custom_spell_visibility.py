from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parent


def check_visibility_wiring():
    lifecycle = (ROOT / "DDingUI_CDM/Modules/CustomIcons/FrameLifecycle.lua").read_text(encoding="utf-8")
    custom_icons = (ROOT / "DDingUI_CDM/Modules/CustomIcons/CustomIcons.lua").read_text(encoding="utf-8")
    layout = (ROOT / "DDingUI_CDM/Modules/CustomIcons/DynamicLayout.lua").read_text(encoding="utf-8")
    bridge = (ROOT / "DDingUI_CDM/Modules/GroupSystem/DynamicIconBridge.lua").read_text(encoding="utf-8")

    assert "settings.customID == true" not in lifecycle
    assert "function CustomIcons:IsIconLoadable(iconData)" in custom_icons
    assert "if iconData and IsIconLoadable(iconData) then" in layout
    assert "not ci:IsIconLoadable(iconData)" in bridge


class CustomSpellVisibilityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            addon = {}; ci = {}; known = {}; bases = {}; overrides = {}
            Enum = {SpellBookSpellBank = {Player = 0}}
            C_SpellBook = {
                IsSpellKnown = function(id, bank)
                    assert(bank == Enum.SpellBookSpellBank.Player)
                    return known[id] == true
                end,
                FindBaseSpellByID = function(id) return bases[id] or id end,
                FindSpellOverrideByID = function(id) return overrides[id] or id end,
                -- A listed override need not be learned (Blizzard SpellBook documentation).
                IsSpellInSpellBook = function() return true end,
            }
            IsPlayerSpell = function(id) return known[id] == true end
            function ensure(data)
                data.settings = data.settings or {}
                data.settings.loadConditions = data.settings.loadConditions or {}
            end
            runtime = {iconFrames = {}, groupFrames = {}, loginTime = 0}
            spell = {type = "spell", id = 200, settings = {customID = true}}
            function noop() end
        ''')
        ns = self.lua.table(Addon=self.lua.globals().addon)
        for name in ('FrameLifecycle', 'DynamicLayout'):
            self.lua.execute((ROOT / f'DDingUI_CDM/Modules/CustomIcons/{name}.lua').read_text(
                encoding='utf-8-sig'), 'test', ns)
        self.lua.execute('''
            local _
            _, loadable, spawn = addon.CustomIconFrameLifecycle.Create(
                runtime, ci, nil, nil, ensure)
        ''')

    def test_unselected_talent_replacement_is_hidden(self):
        self.lua.execute('''
            known[100] = true; bases[200] = 100
            assert(not loadable(spell), "unlearned talent must not inherit its base spell's availability")
            assert(not spawn(spell))
        ''')

    def test_selected_talent_and_normal_spells_are_visible(self):
        self.lua.execute('''
            known[200] = true
            assert(loadable(spell) and spawn(spell))
            spell.settings.customID = nil
            assert(loadable(spell) and spawn(spell))
            known[200] = nil
            assert(not loadable(spell) and not spawn(spell))
        ''')

    def test_known_active_override_keeps_base_icon_available(self):
        self.lua.execute('''
            overrides[200] = 300; known[300] = true
            assert(loadable(spell) and spawn(spell))
            known[300] = nil
            assert(not loadable(spell))
        ''')

    def test_missing_optional_helpers_do_not_bypass_known_check(self):
        self.lua.execute('''
            C_SpellBook.FindBaseSpellByID = nil
            C_SpellBook.FindSpellOverrideByID = nil
            assert(not loadable(spell), "spellbook presence is not proof of learning a talent")
            known[200] = true
            assert(loadable(spell))
        ''')

    def test_legacy_known_check_does_not_accept_spellbook_presence(self):
        self.lua.execute('''
            C_SpellBook.IsSpellKnown = nil
            assert(not loadable(spell))
            known[200] = true
            assert(loadable(spell))
        ''')

    def test_api_error_uses_legacy_known_check(self):
        self.lua.execute('''
            C_SpellBook.IsSpellKnown = function() error("not ready") end
            known[200] = true
            assert(loadable(spell))
            known[200] = nil
            assert(not loadable(spell))
        ''')

    def test_missing_apis_do_not_assume_a_talent_is_learned(self):
        self.lua.execute('''
            C_SpellBook = nil; IsPlayerSpell = nil
            assert(not loadable(spell))
        ''')

    def test_talent_switch_releases_and_restores_frame_without_deleting_settings(self):
        self.lua.execute('''
            function GetTime() return 20 end
            function InCombatLockdown() return false end
            C_Timer = {NewTicker = function() error("no login retry expected") end}
            db = {iconData = {manual = spell}, groups = {group = {icons = {"manual"}}}, ungrouped = {}}
            runtime.groupFrames.group = {Hide = noop}
            addon.DynamicIconBridge = {IsActive = function() return true end}
            local function getDB() return db end
            local function create() return {Hide = noop} end
            local function release() releases = (releases or 0) + 1 end
            addon.CustomIconDynamicLayout.Create(runtime, ci, {}, noop,
                function() return {} end, nil, noop, nil, nil, nil, nil,
                getDB, nil, spawn, loadable, ensure, create, release, noop, noop, noop, noop)
            known[100] = true; bases[200] = 100; known[200] = true
            ci:LoadDynamicIcons()
            assert(runtime.iconFrames.manual, "selected talent must create a frame")
            known[200] = nil
            ci:LoadDynamicIcons()
            assert(not runtime.iconFrames.manual and releases == 1,
                "removing talent must release its existing frame")
            assert(db.iconData.manual == spell and db.groups.group.icons[1] == "manual",
                "removing talent must preserve saved icon and group order")
            assert(not ci:EnsureDynamicIconFrame("manual"), "bridge must not recreate an unlearned spell")
            known[200] = true
            ci:LoadDynamicIcons()
            assert(runtime.iconFrames.manual and releases == 1, "relearning must restore the saved icon")
        ''')

    def test_existing_visibility_wiring(self):
        check_visibility_wiring()


if __name__ == "__main__":
    unittest.main()
