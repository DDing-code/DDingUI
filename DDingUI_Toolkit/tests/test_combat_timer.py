from pathlib import Path

from test_combat_session import runtime
from test_edit_mode import toolkit_runtime


RETAIL_PICKER = '''
    ColorPickerFrame = {
        SetupColorPickerAndShow = function(self, info)
            self.info = info
            self.r, self.g, self.b, self.alpha = info.r, info.g, info.b, info.opacity
        end,
        GetColorRGB = function(self) return self.r, self.g, self.b end,
        GetColorAlpha = function(self) return self.alpha end,
    }
'''


def test_retail_color_picker_preserves_alpha_for_solid_and_gradient_colors():
    lua = toolkit_runtime()
    # Retail passes info.opacity directly to SetColorAlpha; opening must not invert it.
    lua.execute(RETAIL_PICKER)
    lua.execute('''
        for _, alpha in ipairs({1, 0.35, 0}) do
            local saved
            local color = {1, 0.8, 0, alpha, gradientMode="GRADIENT",
                gradientColor={0.5, 0.4, 0, alpha}}
            local row = ns.ToolkitControls.CreateColor(UIParent, "Toolkit", "Color", color, {
                hasAlpha=true, supportsGradient=true,
                onChange=function(r,g,b,a) saved={r,g,b,a} end,
            })
            for _, button in ipairs({row.swatch, row.gradientEndSwatch}) do
                button:Fire("OnClick")
                assert(ColorPickerFrame:GetColorAlpha() == alpha, "opening changed opacity")
                ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b = 0.2, 0.3, 0.4
                ColorPickerFrame.info.swatchFunc()
                ColorPickerFrame.info.opacityFunc()
                if button == row.swatch then
                    assert(saved[1] == 0.2 and saved[4] == alpha)
                else
                    assert(row:GetColorSpec().gradientColor[4] == alpha)
                end
                ColorPickerFrame.alpha = 0.6
                ColorPickerFrame.info.opacityFunc()
                ColorPickerFrame.info.cancelFunc()
                local restored = button == row.swatch and row:GetColorSpec()
                    or row:GetColorSpec().gradientColor
                assert(restored[4] == alpha, "cancel must restore even zero opacity")
            end
        end
    ''')


def test_legacy_color_picker_keeps_inverted_opacity_slider():
    lua = toolkit_runtime()
    lua.execute('''
        OpacitySliderFrame = {GetValue=function(self) return self.value end}
        ColorPickerFrame = {
            SetColorRGB=function(self,r,g,b) self.r,self.g,self.b=r,g,b end,
            GetColorRGB=function(self) return self.r,self.g,self.b end,
            Show=function(self) OpacitySliderFrame.value=self.opacity end,
        }
        for _, alpha in ipairs({1, 0.35, 0}) do
            local saved
            local row=ns.ToolkitControls.CreateColor(UIParent,"Toolkit","Color",{1,1,1,alpha}, {
                hasAlpha=true, onChange=function(r,g,b,a) saved=a end,
            })
            row.swatch:Fire("OnClick")
            assert(ColorPickerFrame.opacity == 1-alpha)
            ColorPickerFrame.func()
            assert(math.abs(saved-alpha)<0.000001)
        end
    ''')


def test_correcting_transparent_timer_color_refreshes_both_texts_immediately():
    lua = toolkit_runtime()
    root = Path(__file__).parents[1]
    lua.execute('''
        function methods:GetStringHeight() return (self.fontSize or 12)*1.2 end
        function ns.DDingToolKit:RegisterModule(name,module) ns[name]=module end
    ''')
    for rel in ("Core/Database.lua", "Modules/CombatTimer/CombatTimer.lua", "Config_Data.lua"):
        lua.execute((root / rel).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute(RETAIL_PICKER)
    lua.execute('''
        ns:MergeDefaults(ns.db.profile,ns.defaults.profile)
        ns.modules={CombatTimer=ns.CombatTimer}
        C_AddOns={GetAddOnMetadata=function() return nil end}
        local timer=ns.CombatTimer
        timer:OnInitialize()
        timer.db.showBackground=false
        timer.db.textColor={1,0.8,0,0}
        timer:CreateTimerFrame(); timer:StartTimer()
        local frame=DDingToolKit_CombatTimerFrame
        assert(frame:IsShown() and not frame.bg:IsShown())
        assert(frame.mainText.textColor[4]==0 and frame.msText.textColor[4]==0)
        local tree=ns:InitConfigTree()
        local option
        for _,setting in ipairs(tree.panels.combattimer.settings) do
            if setting.key=="profile.CombatTimer.textColor" then option=setting; break end
        end
        assert(option and option.onChange, "timer color changes must refresh the active frame")
        local row=ns.ToolkitControls.CreateColor(UIParent,"Toolkit","Color",timer.db.textColor, {
            hasAlpha=option.hasAlpha,
            onChange=function(r,g,b,a)
                ns:SetDBValue(option.key,{r,g,b,a}); option.onChange()
            end,
        })
        row.swatch:Fire("OnClick")
        ColorPickerFrame.alpha=1
        ColorPickerFrame.info.opacityFunc()
        assert(timer.db.textColor[4]==1)
        assert(frame:IsShown() and frame.mainText.textColor[4]==1 and frame.msText.textColor[4]==0.8)
        row.swatch:Fire("OnClick")
        ColorPickerFrame.info.swatchFunc()
        assert(timer.db.textColor[4]==1, "choosing another RGB color must keep the timer visible")
    ''')


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
