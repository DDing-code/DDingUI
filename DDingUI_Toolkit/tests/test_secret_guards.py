from pathlib import Path


def test_premade_group_filter_rejects_secret_tables_and_inaccessible_values() -> None:
    source = (
        Path(__file__).parents[1]
        / "Modules"
        / "PremadeGroupFilter"
        / "PremadeGroupFilter.lua"
    ).read_text(encoding="utf-8-sig")
    start = source.index("local function IsSecret(value)")
    helper = source[start : source.index("local function SafeNumber", start)]

    access_guard = helper.index("not canaccessvalue(value)")
    value_guard = helper.index("issecretvalue(value)")
    table_guard = helper.index("pcall(issecrettable, value)")

    assert access_guard < value_guard < table_guard
    assert "if not ok or secret then return true end" in helper
    assert "return false" in helper


def test_modules_do_not_overwrite_blizzard_ui_state() -> None:
    root = Path(__file__).parents[1] / "Modules"
    item_level = (root / "ItemLevel" / "ItemLevel.lua").read_text(encoding="utf-8-sig")
    talent_bg = (root / "TalentBG" / "TalentBG.lua").read_text(encoding="utf-8-sig")

    assert "InspectGuildFrame_Update = function" not in item_level
    assert "InspectPVPFrame_Update = function" not in item_level
    assert "talentsFrame.backgroundAnims =" not in talent_bg


def test_automatic_instance_prompts_do_not_use_blizzard_popup_pool() -> None:
    root = Path(__file__).parents[1]
    templates = (root / "UI" / "Templates.lua").read_text(encoding="utf-8-sig")

    assert "function UI:ShowConfirmation" in templates
    assert "function UI:HideConfirmation" in templates
    for relative in (
        Path("Modules/RaidLootPass/RaidLootPass.lua"),
        Path("Modules/VoidcoreHelper/VoidcoreHelper.lua"),
    ):
        source = (root / relative).read_text(encoding="utf-8-sig")
        assert "StaticPopup" not in source
