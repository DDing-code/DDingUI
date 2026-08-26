from pathlib import Path


MODULE = (
    Path(__file__).parents[1]
    / "Modules/PremadeGroupFilter/PremadeGroupFilter.lua"
).read_text(encoding="utf-8-sig")


def test_saved_filters_refresh_cached_results_on_the_next_frame() -> None:
    queue_refresh = MODULE.split("function PremadeGroupFilter:QueueResultRefresh()", 1)[1].split(
        "function PremadeGroupFilter:ApplyNativeFilters(requestSearch)", 1
    )[0]

    assert "C_Timer.After(0, Refresh)" in queue_refresh
    assert queue_refresh.index("PremadeGroupFilter:RequestFilterResultRefresh()") < queue_refresh.index(
        "PremadeGroupFilter:RefreshResultCount()"
    )
    assert "options.activities = BuildSelectedActivityGroups(db)" in MODULE


def test_user_filter_clicks_save_and_run_the_native_dungeon_search() -> None:
    get_options = MODULE.split("local function GetNativeFilterOptions()", 1)[1].split(
        "local function BuildSelectedActivityGroups", 1
    )[0]
    save_options = MODULE.split("local function SaveNativeFilterOptions(options)", 1)[1].split(
        "function PremadeGroupFilter:RefreshResultCount()", 1
    )[0]
    search_refresh = MODULE.split(
        "function PremadeGroupFilter:RequestNativeSearchRefresh()", 1
    )[1].split("function PremadeGroupFilter:QueueResultRefresh()", 1)[0]

    assert "IsChatRestricted()" not in get_options
    assert "IsChatRestricted()" not in save_options
    assert 'issecurevariable("LFGListSearchPanel_DoSearch")' in search_refresh
    assert "pcall(securecallfunction, LFGListSearchPanel_DoSearch, searchPanel)" in search_refresh
    assert "function PremadeGroupFilter:ApplyNativeFilters(requestSearch)" in MODULE
    assert MODULE.count("self:ApplyCurrentResults(true)") == 4
