from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_group_movement_buffs_are_wired_through_tracker_options_and_defaults() -> None:
    module = (ROOT / "Modules/RaidDefensiveTracker/RaidDefensiveTracker.lua").read_text(encoding="utf-8-sig")
    config = (ROOT / "Config_Data.lua").read_text(encoding="utf-8-sig")
    database = (ROOT / "Core/Database.lua").read_text(encoding="utf-8-sig")
    locales = [
        (ROOT / "Locales/enUS.lua").read_text(encoding="utf-8-sig"),
        (ROOT / "Locales/koKR.lua").read_text(encoding="utf-8-sig"),
    ]

    assert "local MAX_FRAMES = 16" in module
    assert "if db.spells[effect.key] == nil then" in module
    for key, (aura_id, label_key) in {
        "stampedingRoar": (77764, "RDT_STAMPEDING_ROAR"),
        "windRush": (192082, "RDT_WIND_RUSH"),
        "piercingHowl": (12323, "RDT_PIERCING_HOWL"),
    }.items():
        assert f'key = "{key}", ids = {{ {aura_id} }}' in module
        assert f"profile.RaidDefensiveTracker.spells.{key}" in config
        assert f"{key} = true" in database
        assert f'{key} = {{ soundFile = ""' in database
        assert all(f'L["{label_key}"]' in locale for locale in locales)


def test_edit_mode_preview_keeps_four_icons_without_resetting_drag_position() -> None:
    module = (ROOT / "Modules/RaidDefensiveTracker/RaidDefensiveTracker.lua").read_text(encoding="utf-8-sig")
    create_frame = module.split("function RaidDefensiveTracker:CreateFrame()", 1)[1].split(
        "function RaidDefensiveTracker:ApplyPosition()", 1
    )[0]

    assert "local PREVIEW_COUNT = 4" in module
    assert "local function GetPreviewIconCount()" not in module
    assert "iconFrame:SetShown(index <= previewCount)" not in module
    assert "local frameCreated = false" in create_frame
    assert "if frameCreated then\n        self:ApplyPosition()\n    end" in create_frame
