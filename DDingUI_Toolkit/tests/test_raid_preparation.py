from pathlib import Path


def test_raid_preparation_shows_overall_and_per_check_readiness_gauges() -> None:
    module = (Path(__file__).parents[1] / "Modules/RaidPreparation/RaidPreparation.lua").read_text(
        encoding="utf-8-sig"
    )

    assert 'frame.readinessGauge = CreateFrame("StatusBar", nil, frame.header)' in module
    assert "for index = 1, 9 do" in module
    assert "SetGaugeValue(frame.readinessGauge" in module
    for key in ("food", "flask", "rune", "raidBuff", "weapon", "durability", "ready"):
        assert f'frame.metricBars["{key}"]' in module or f'frame.metricBars[info[5]]' in module
        assert f'key = "{key}"' in module
