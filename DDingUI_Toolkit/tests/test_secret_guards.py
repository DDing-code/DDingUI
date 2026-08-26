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
