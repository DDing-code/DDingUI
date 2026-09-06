from pathlib import Path


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
