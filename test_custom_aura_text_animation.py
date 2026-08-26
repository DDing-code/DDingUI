from pathlib import Path


ROOT = Path(__file__).parent
RUNTIME = (ROOT / "DDingUI_CDM/Core/RestrictedAuraVisuals.lua").read_text(encoding="utf-8")
BAR = (ROOT / "DDingUI_CDM/Modules/ResourceBars/BuffTrackerBar.lua").read_text(encoding="utf-8")
CONTAINER = (ROOT / "DDingUI_CDM/Modules/ResourceBars/TrackedAuraContainer.lua").read_text(encoding="utf-8")
OPTIONS = (ROOT / "DDingUI_CDM_Option/BuffTrackerOptions.lua").read_text(encoding="utf-8")
PREVIEW = (ROOT / "DDingUI_CDM_Option/BuffTrackerLivePreview.lua").read_text(encoding="utf-8")
GUI = (ROOT / "DDingUI_CDM_Option/BuffTrackerGUI.lua").read_text(encoding="utf-8")


def test_text_animation_contract():
    for preset in ("fade", "pop", "spring", "breathe", "float"):
        assert f'{preset} = true' in RUNTIME
        assert f'{preset} = L[' in OPTIONS

    for legacy, replacement in (("hover", "float"), ("pulse", "breathe"), ("flash", "focus")):
        assert f'{legacy} = "{replacement}"' in RUNTIME

    assert "visuals:ApplyTextMotion(button, style.iconAnimation, style.textFadeInDirection)" in CONTAINER
    assert "ApplyPreviewEffect(host, host.icon, entry, true)" in PREVIEW
    assert '"textFadeInDirection"' in OPTIONS
    assert '"textFadeOutDirection"' in OPTIONS
    assert 'key:find("_textFade", 1, true)' in GUI
    assert "function Visuals:ApplyTextExit" in RUNTIME
    assert "function Visuals:ApplyTextPreviewMotion" in RUNTIME
    assert 'visuals:ApplyTextExit(frame, "fade", settings.textFadeOutDirection)' in BAR
    assert "settings.textFadeInDirection" in BAR
    assert "LEFT = { -14, 0 }" in RUNTIME
    assert "RIGHT = { 14, 0 }" in RUNTIME
    assert "UP = { 0, 14 }" in RUNTIME
    assert "DOWN = { 0, -14 }" in RUNTIME

    motion_section = RUNTIME.split("local TEXT_MOTION_ALIASES", 1)[1].split("local function ResolveGlowType", 1)[0]
    assert ":HookScript(" not in motion_section
    assert ":SetScript(" not in motion_section
    assert 'TEXT_MOTION_ALIASES[value] or TEXT_MOTION_PRESETS[value]' in RUNTIME


if __name__ == "__main__":
    test_text_animation_contract()
    print("custom aura text animation contract: ok")
