from pathlib import Path


ROOT = Path(__file__).parent


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_edit_mode_selection_hud_contract():
    toolkit = read("DDingUI_Toolkit/Core/Movers.lua")
    cdm = read("DDingUI_CDM/Core/Movers.lua")
    uf_overlay = read("DDingUI_UF/Modules/MoverOverlay.lua")
    uf_selection = read("DDingUI_UF/Modules/MoverSelectionActions.lua")
    raid_helper = read("DDingUI_RaidHelper/UI/Timeline.lua")

    assert '"X %d  Y %d  ·  %d×%d"' in toolkit
    assert "ov.selectionHUD:SetShown(ov._selected)" in toolkit
    assert "function mover:SetSelectionHUD(selected)" in cdm
    assert "dragFrame:UpdateSelectionHUD()" in cdm
    assert "function mover:SetSelectionHUD(selected)" in uf_overlay
    assert "SetSelectionHUD(self, mover, true)" in uf_selection
    assert "function TimelineUI:UpdateEditHUD()" in raid_helper
    assert "currentFrame._editDragging" in raid_helper


if __name__ == "__main__":
    test_edit_mode_selection_hud_contract()
    print("edit mode selection HUD contract: ok")
