from pathlib import Path

from test_combat_session import runtime
from test_edit_mode import toolkit_runtime


def test_fraction_font_sizes_fit_each_alignment():
    lua = toolkit_runtime()
    root = Path(__file__).parents[1]
    lua.execute('''
        function methods:GetStringHeight() return (self.fontSize or 12)*1.2 end
        function ns.DDingToolKit:RegisterModule(name,module) ns[name]=module end
    ''')
    for rel in ("Core/Database.lua", "Modules/CombatTimer/CombatTimer.lua"):
        lua.execute((root / rel).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        ns:MergeDefaults(ns.db.profile,ns.defaults.profile)
        local timer=ns.CombatTimer
        timer:OnInitialize(); timer:CreateTimerFrame()
        local frame=DDingToolKit_CombatTimerFrame
        frame.mainText:SetText("12:34"); frame.msText:SetText(".56")
        for _,align in ipairs({"LEFT","CENTER","RIGHT"}) do
            for _,size in ipairs({0,12,48}) do
                timer.db.textAlign=align; timer.db.decimalFontSize=size
                timer:UpdateFrameStyle()
                local x,y,w,h=frame:Rect()
                for _,text in ipairs({frame.mainText,frame.msText}) do
                    local tx,ty,tw,th=text:Rect()
                    assert(tx>=x and tx+tw<=x+w+0.001, "text outside timer width: "..align)
                    assert(ty>=y and ty+th<=y+h+0.001, "text outside timer height: "..align)
                end
            end
        end
    ''')


def test_fraction_font_size_changes_independently_and_keeps_old_profiles():
    lua = runtime()
    root = Path(__file__).parents[1]
    lua.execute(r'''
        ns.modules = modules
        timer = modules.CombatTimer
        for _, candidate in ipairs(frames) do
            if rawget(candidate, "msText") then frame = candidate; break end
        end
        for _, text in ipairs({frame.mainText, frame.msText}) do
            text.SetFont = function(self, font, size) self.size = size end
            text.GetStringHeight = function(self) return self.size or 20 end
        end
        frame.SetSize = function(self, width, height) self.width, self.height = width, height end
        timer.db.fontSize = 36
        timer:UpdateFrameStyle()
        assert(frame.mainText.size == 36 and frame.msText.size == 18)
    ''')
    lua.execute((root / "Core/Database.lua").read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        ns:MergeDefaults(ns.db.profile, ns.defaults.profile)
        timer:UpdateFrameStyle()
        assert(frame.msText.size == 18, "old profiles must keep half of the main font size")
    ''')
    lua.execute((root / "Config_Data.lua").read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute(r'''
        C_AddOns = {GetAddOnMetadata=function() return nil end}
        ns:InitConfigTree()
        local option
        for _, setting in ipairs(ns.ConfigTree.panels.combattimer.settings) do
            if setting.key == "profile.CombatTimer.decimalFontSize" then option = setting; break end
        end
        assert(option and option.min == 0 and option.max == 48 and option.step == 1)
        for _, align in ipairs({"LEFT", "CENTER", "RIGHT"}) do
            timer.db.textAlign = align
            ns:SetDBValue(option.key, 48); option.onChange()
            assert(frame.mainText.size == 36 and frame.msText.size == 48)
            assert(frame.height >= 48 + 8, "large fractional text must fit in the background")
        end
        timer.db.fontSize = 24; timer:UpdateFrameStyle()
        assert(frame.mainText.size == 24 and frame.msText.size == 48)
        ns:SetDBValue(option.key, 0); option.onChange()
        assert(frame.msText.size == 12, "zero restores the previous automatic ratio")
        timer.db.decimalFontSize = "invalid"; timer:UpdateFrameStyle()
        assert(frame.msText.size == 12)
        timer.db.decimalFontSize = 200; timer:UpdateFrameStyle()
        assert(frame.msText.size == 48)
        timer.db.showMilliseconds = false; timer:UpdateFrameStyle()
        assert(frame.height == 32, "hidden fraction must not enlarge the timer")
    ''')


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
