from pathlib import Path

from lupa.lua51 import LuaRuntime


def test_casting_alert_preview_passes_only_class_token_to_color_api() -> None:
    lua = LuaRuntime()
    lua.execute('''
        ns = { DDingToolKit = { RegisterModule = function() end } }
        GetTime = function() return 100 end
        UnitName = function() return "Player" end
        UnitClass = function() return "Warlock", "WARLOCK", 9 end
        playerColor = { r = 0.58, g = 0.51, b = 0.79 }
        colorCalls = 0
        C_ClassColor = { GetClassColor = function(className, tintColor)
            assert(className == "WARLOCK")
            assert(tintColor == nil, "bad argument #2: class ID passed as tintColor")
            colorCalls = colorCalls + 1
            return playerColor
        end }
        C_Timer = { NewTicker = function(_, callback)
            previewTick = callback
            return { Cancel = function() tickerCancelled = true end }
        end }
    ''')
    source = (
        Path(__file__).parents[1] / "Modules/CastingAlert/CastingAlert.lua"
    ).read_text(encoding="utf-8-sig")
    lua.execute(source, "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        local module = ns.CastingAlert
        -- 프레임 생성·그리기만 생략하고 실제 미리보기 호출 경로를 실행한다.
        module.CreateMainFrame = function() end
        module.RenderList = function(_, list) rendered = list end
        module:EnterEditPreview()
        assert(module:IsTestMode() and #rendered == 3)
        assert(rendered[1].targetClassColor == playerColor)
        assert(rendered[1].targetsPlayerNamePlain)
        assert(rendered[2].targetClassColor == nil)
        assert(rendered[3].targetClassColor == nil)
        previewTick()
        assert(colorCalls == 2 and #rendered == 3)
        module.db.maxShow = 1
        module:UpdateStyle()
        assert(colorCalls == 3 and #rendered == 1)
        module:ExitEditPreview()
        assert(not module:IsTestMode() and tickerCancelled and #rendered == 0)
        module:EnterPreview()
        assert(colorCalls == 4 and rendered[1].targetClassColor == playerColor)
        module:ExitPreview()
    ''')


def test_casting_alert_renders_sorted_casts_into_contiguous_slots() -> None:
    source = (
        Path(__file__).parents[1] / "Modules/CastingAlert/CastingAlert.lua"
    ).read_text(encoding="utf-8-sig")
    render = source.split("function CastingAlert:RenderList(list)", 1)[1].split(
        "function CastingAlert:Render()", 1
    )[0]

    assert "castSlots" not in source
    assert render.count("for index, info in ipairs(list) do") == 3
    assert "self:UpdateIconFrame(self:CreateIconFrame(index), info, index)" in render
    assert "self:UpdateBarFrame(self:CreateBarFrame(index), info, index)" in render
    assert "self:UpdateDualFrame(self:CreateDualFrame(index), info, index)" in render
    assert "HideFrames(iconFrames, #list + 1)" in render
    assert "HideFrames(barFrames, #list + 1)" in render
    assert "HideFrames(dualFrames, #list + 1)" in render
    assert "IsSecretValue(level)" in source
    assert "SetCooldownFromDurationObject(info.durationObject)" in source
    assert "SetTimerDuration(info.durationObject" in source


def test_casting_alert_exposes_all_three_display_modes() -> None:
    root = Path(__file__).parents[1]
    config = (root / "Config_Data.lua").read_text(encoding="utf-8-sig")
    defaults = (root / "Core/Database.lua").read_text(encoding="utf-8-sig")

    assert 'key = "profile.CastingAlert.displayMode"' in config
    assert '{ text = L["CASTINGALERT_MODE_ICON"], value = "ICON" }' in config
    assert '{ text = L["CASTINGALERT_MODE_BAR"], value = "BAR" }' in config
    assert '{ text = L["CASTINGALERT_MODE_DUAL"], value = "ICON_TEXT_ICON" }' in config
    assert 'displayMode = "ICON"' in defaults
