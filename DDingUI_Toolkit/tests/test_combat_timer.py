from pathlib import Path

from test_combat_session import runtime


def test_death_transition_keeps_the_original_combat_timer():
    source = (Path(__file__).parents[1] / "Modules/CombatTimer/CombatTimer.lua").read_text(encoding="utf-8")
    start_timer = source.split("function CombatTimer:StartTimer()", 1)[1].split("function CombatTimer:StopTimer(", 1)[0]
    on_enable = source.split("function CombatTimer:OnEnable()", 1)[1].split("function CombatTimer:OnDisable()", 1)[0]

    assert start_timer.index("if startTime then return end") < start_timer.index("startTime = GetTime()")
    # Stop only on the shared session's confirmed END (group still fighting / re-entry continue it).
    # Behaviour is covered by tests/test_combat_session.py.
    assert "session:RegisterCallback(self" in on_enable
    assert 'kind == "END"' in on_enable
    assert "PLAYER_REGEN_ENABLED" not in on_enable


def test_fraction_digits_saved_and_applied_during_combat():
    lua = runtime()
    lua.execute(r'''
        ns.modules = modules
        local timer = modules.CombatTimer
        frame = nil
        for _, candidate in ipairs(frames) do
            if rawget(candidate, "msText") then frame = candidate; break end
        end
        assert(frame)
        for _, text in ipairs({ frame.mainText, frame.msText }) do
            text.SetText = function(self, value) self.text = value end
            text.GetText = function(self) return self.text end
            text.GetStringWidth = function(self) return #(self.text or "") * 10 end
        end
        frame.mainText.text, frame.msText.text = "0:00", ".00"
        frame.SetSize = function(self, width) self.width = width end
        timer:StartTimer()
        now = 101.25
        timer:UpdateTimer()
        assert(frame.msText.text == ".25" and frame.width == 86) -- old profiles default to two digits
    ''')
    root = Path(__file__).parents[1]
    lua.execute((root / "Core/Database.lua").read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        assert(ns.defaults.profile.CombatTimer.decimalPlaces == 2)
        local oldProfile = { CombatTimer = { showMilliseconds = true } }
        ns:MergeDefaults(oldProfile, ns.defaults.profile)
        assert(oldProfile.CombatTimer.decimalPlaces == 2)
    ''')
    lua.execute((root / "Config_Data.lua").read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute(r'''
        C_AddOns = { GetAddOnMetadata = function() return nil end }
        ns:InitConfigTree()
        local option
        for _, setting in ipairs(ns.ConfigTree.panels.combattimer.settings) do
            if setting.key == "profile.CombatTimer.decimalPlaces" then option = setting; break end
        end
        assert(option and option.min == 1 and option.max == 2 and option.step == 1)
        ns:SetDBValue(option.key, 1)
        option.onChange()
        assert(ns:GetDBValue(option.key) == 1)
        assert(frame.msText.text == ".2" and frame.width == 76)
        ns:SetDBValue(option.key, 2)
        option.onChange()
        assert(frame.msText.text == ".25" and frame.width == 86)
    ''')
