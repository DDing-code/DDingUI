from pathlib import Path


ROOT = Path(__file__).parent
OVERLAY = (ROOT / "DDingUI_CDM/Modules/GroupSystem/NativeTrinketOverlay.lua").read_text(encoding="utf-8")
SKINNING = (ROOT / "DDingUI_CDM/Modules/IconViewers/IconSkinning.lua").read_text(encoding="utf-8")


def main():
    active_reader = OVERLAY.split("local function ReadProcActive", 1)[1].split(
        "local function RestoreSuppressedRegion", 1
    )[0]
    assert "if active == true then return true end" in active_reader
    assert 'type(frame.IsActive) ~= "function"' not in active_reader
    assert "shown == true" in active_reader

    pair_state = OVERLAY.split("local function ApplyPairState", 1)[1].split(
        "local function RefreshAllStates", 1
    )[0]
    assert pair_state.index("_ddNativeTrinketActive") < pair_state.index("SetSwipeColor")
    assert "RestoreActiveIconVisual" not in pair_state
    assert "effect.visualActive = visualApplied and true or nil" in pair_state
    assert "effect.visualActive = nil" in pair_state
    assert 'FrameFlagIsTrue(icon, "_ddNativeTrinketActive")' in SKINNING


if __name__ == "__main__":
    main()
    print("native trinket overlay contract: ok")
