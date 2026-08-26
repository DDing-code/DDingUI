from pathlib import Path


ROOT = Path(__file__).parent
WORKSPACE = (ROOT / "DDingUI_CDM_Option/SectionWorkspace.lua").read_text(encoding="utf-8")
EN = (ROOT / "DDingUI_CDM_Option/Locales/enUS.lua").read_text(encoding="utf-8")
KO = (ROOT / "DDingUI_CDM_Option/Locales/koKR.lua").read_text(encoding="utf-8")


def test_dashboard_workspace_contract():
    dashboard = WORKSPACE.split("local function CreateDashboardWorkspace", 1)[1].split(
        "function GUI.CreateSectionWorkspace", 1
    )[0]
    signature = WORKSPACE.split("local function DashboardSourceSignature", 1)[1].split(
        "local function CreateDashboardQuickRow", 1
    )[0]

    assert 'L["General Settings"] = "Dashboard"' in EN
    assert 'L["General Settings"] = "대시보드"' in KO
    assert 'requestedKind == "general" and not (requestedPath and #requestedPath > 0)' in WORKSPACE
    assert "DashboardFrameRect(descriptor.frame)" in dashboard
    assert "parentFrame:NavigateToSection(self.descriptor.target)" in dashboard
    assert 'target = "groupSystem.group_" .. group.name' in WORKSPACE
    assert '"resourceBars.primary"' in WORKSPACE
    assert '"castBars.general"' in WORKSPACE
    assert '"profiles.importExport"' in dashboard
    assert '"profiles.moduleImport"' in dashboard
    assert "DDingUI.Movers:ToggleConfigMode()" in dashboard
    assert "descriptor.frame:SetParent" not in dashboard
    assert "self._geometryElapsed >= 0.25" in dashboard
    assert "function workspace:RefreshCurrent()" in dashboard
    assert "DashboardGroupTextures(frame, settings)" in signature
    assert '"tracked:" .. tostring(key)' in signature


if __name__ == "__main__":
    test_dashboard_workspace_contract()
    print("dashboard workspace contract: ok")
