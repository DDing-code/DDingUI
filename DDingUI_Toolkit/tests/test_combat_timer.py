from pathlib import Path


def test_death_transition_keeps_the_original_combat_timer():
    source = (Path(__file__).parents[1] / "Modules/CombatTimer/CombatTimer.lua").read_text(encoding="utf-8")
    start_timer = source.split("function CombatTimer:StartTimer()", 1)[1].split("function CombatTimer:StopTimer()", 1)[0]
    on_event = source.split('eventFrame:SetScript("OnEvent"', 1)[1].split("end)", 1)[0]
    regen_enabled = on_event.split('elseif event == "PLAYER_REGEN_ENABLED"', 1)[1]

    assert start_timer.index("if startTime then return end") < start_timer.index("startTime = GetTime()")
    assert "self:WatchGroupCombat()" in regen_enabled
    assert "self:IsGroupStillFighting()" not in regen_enabled
