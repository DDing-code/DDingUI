from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_delve_exclusion_guards_both_combat_alerts():
    source = (ROOT / "Modules/CombatStateAlert/CombatStateAlert.lua").read_text(encoding="utf-8")
    show_alert = source.split("function CombatStateAlert:ShowAlert", 1)[1].split(
        "function CombatStateAlert:TestAlert", 1
    )[0]

    assert "difficultyID == 208" in source
    assert "if db.excludeDelves and IsInDelve() then return end" in show_alert
    assert 'kind == "START"' in show_alert
    assert 'kind == "END"' in show_alert


def test_delve_exclusion_is_exposed_and_disabled_by_default():
    database = (ROOT / "Core/Database.lua").read_text(encoding="utf-8")
    config = (ROOT / "Config_Data.lua").read_text(encoding="utf-8")

    assert "excludeDelves = false" in database
    assert "profile.CombatStateAlert.excludeDelves" in config
    assert 'L["CSA_EXCLUDE_DELVES"]' in config
