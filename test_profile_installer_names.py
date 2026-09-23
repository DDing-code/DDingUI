"""Keep bundled CDM and Ellesmere profiles on their source profile names."""
from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parent


def test_profile_installer_names():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        db = {profiles = {Other = {}}, keys = {profile = "Other"}}
        function db:GetCurrentProfile() return self.keys.profile end
        function db:SetProfile(name)
            self.keys.profile = name
            self.profile = self.profiles[name]
        end
        addon = {db = db}
        function addon:ImportProfileFromString(_, name)
            if self.failImport then return false, "bad import" end
            if name and self.db.profiles[name] then name = name .. " 2" end
            name = name or self.db:GetCurrentProfile()
            self.db.profiles[name] = {imported = true}
            self.db:SetProfile(name)
            return true
        end
        data = {ddingui = "DDUI1:test", ellesmereui = "!EUI:test"}
        setup = {CompleteSetup = function() end, RemoveFromDatabase = function() error("missing profile") end}
        DUI = {
            profileName = "DDingUI",
            GetModule = function(_, name) return name == "Data" and data or setup end,
            Print = function() end,
        }
        DDingUI_Profile = {DUI}
        function LibStub() return {GetAddon = function() return addon end} end
        DDingUIDB = db
        EllesmereUIDB = {profiles = {}}
        EllesmereUI = {
            ImportProfileSilent = function(opts)
                EllesmereUIDB.profiles[opts.profileName] = {}
                return true
            end,
            SetProfile = function(name) EllesmereUIDB.activeProfile = name end,
        }
    """)
    for name in ("DDingUI", "EllesmereUI"):
        source = (ROOT / "DDingUI_Profile" / "Setup" / "AddOns" / f"{name}.lua").read_text(encoding="utf-8-sig")
        lua.execute("assert(loadstring(...))()", source)

    lua.execute("""
        setup.DDingUI("DDingUI", true)
        assert(db.keys.profile == "DDingUI_AD" and db.profiles.DDingUI_AD.imported)
        db:SetProfile("Other")
        setup.DDingUI("DDingUI", true)
        assert(db.keys.profile == "DDingUI_AD" and db.profiles["DDingUI_AD 2"] == nil)
        db:SetProfile("Other")
        addon.failImport = true
        setup.DDingUI("DDingUI", true)
        assert(db.keys.profile == "Other")
        addon.failImport = false
        setup.DDingUI("DDingUI", false)
        assert(db.keys.profile == "DDingUI_AD")
        data.ddingui = {tableImport = true}
        setup.DDingUI("DDingUI", true)
        assert(db.profiles.DDingUI_AD.tableImport)

        setup.EllesmereUI("EllesmereUI", true)
        assert(EllesmereUIDB.profiles.DDing_UI)
        setup.EllesmereUI("EllesmereUI", false)
        assert(EllesmereUIDB.activeProfile == "DDing_UI")
        EllesmereUI.SetProfile = nil
        EllesmereUIDB.activeProfile = nil
        setup.EllesmereUI("EllesmereUI", false)
        assert(EllesmereUIDB.activeProfile == "DDing_UI")
    """)


if __name__ == "__main__":
    test_profile_installer_names()
