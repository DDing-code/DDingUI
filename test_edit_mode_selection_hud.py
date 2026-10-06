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

    # StyleLib 1.4 공용 부품(CreateMoverHUD)을 쓰거나, 아직 전환 전이면 기존 계약 문자열을 가진다.
    def uses_kit(source):
        return "CreateMoverHUD(" in source

    assert uses_kit(toolkit) or '"X %d  Y %d  ·  %d×%d"' in toolkit
    assert "ov.selectionHUD:SetShown(ov._selected)" in toolkit or uses_kit(toolkit)
    assert uses_kit(cdm) or ("function mover:SetSelectionHUD(selected)" in cdm
                             and "dragFrame:UpdateSelectionHUD()" in cdm)
    # DDingUI_UF는 개발 중지라 옛 계약 그대로
    assert "function mover:SetSelectionHUD(selected)" in uf_overlay
    assert "SetSelectionHUD(self, mover, true)" in uf_selection
    assert uses_kit(raid_helper) or "function TimelineUI:UpdateEditHUD()" in raid_helper
    assert "currentFrame._editDragging" in raid_helper


if __name__ == "__main__":
    test_edit_mode_selection_hud_contract()
    print("edit mode selection HUD contract: ok")
