from pathlib import Path


ROOT = Path(__file__).parent


def main():
    lifecycle = (ROOT / "DDingUI_CDM/Modules/CustomIcons/FrameLifecycle.lua").read_text(encoding="utf-8")
    custom_icons = (ROOT / "DDingUI_CDM/Modules/CustomIcons/CustomIcons.lua").read_text(encoding="utf-8")
    layout = (ROOT / "DDingUI_CDM/Modules/CustomIcons/DynamicLayout.lua").read_text(encoding="utf-8")
    bridge = (ROOT / "DDingUI_CDM/Modules/GroupSystem/DynamicIconBridge.lua").read_text(encoding="utf-8")

    assert "settings.customID == true" not in lifecycle
    assert "function CustomIcons:IsIconLoadable(iconData)" in custom_icons
    assert "if iconData and IsIconLoadable(iconData) then" in layout
    assert "not ci:IsIconLoadable(iconData)" in bridge


if __name__ == "__main__":
    main()
