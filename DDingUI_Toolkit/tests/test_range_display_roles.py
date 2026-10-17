"""사거리 표시: 탱커·힐러·근딜·원딜 체크박스로 전문화별 표시를 켜고 끈다."""
from test_edit_mode import HARNESS, ROOT, runtime
from test_settings_cleanup import config_runtime

SPECS = {"TANK": (73, "TANK"), "HEALER": (65, "HEALER"), "MELEE": (71, "DAMAGER"), "RANGED": (62, "DAMAGER")}


def range_runtime():
    lua = runtime()
    lua.execute(HARNESS)
    lua.execute('''
        local M = getmetatable(UIParent).__index
        for _, k in ipairs({ "SetVertexColor", "SetShadowOffset", "SetShadowColor" }) do
            if not M[k] then M[k] = function() end end
        end
        spec = {73, "TANK"}
        function GetSpecialization() return 1 end
        function GetSpecializationRole() return spec[2] end
        function GetSpecializationInfo() return spec[1], "x", nil, nil, spec[2] end
        function InCombatLockdown() return false end
        function IsInInstance() return false end
        function UnitExists() return true end
        function LibStub() return { GetRange = function() return 5, 8 end } end
        ns.DDingToolKit.RegisterModule = function() end
    ''')
    defaults_source = (ROOT / "Core/Database.lua").read_text(encoding="utf-8-sig")
    lua.execute('local source = ...; local db_ns = {}; '
                'assert(loadstring(source))("DDingUI_Toolkit", db_ns); defaults = db_ns.defaults', defaults_source)
    lua.execute('''
        local copy = {}
        for k, v in pairs(defaults.profile.RangeDisplay) do copy[k] = v end
        ns.db.profile.RangeDisplay = copy
    ''')
    lua.execute('local source,owner,ns=...; assert(loadstring(source))(owner, ns)',
                (ROOT / "Modules/RangeDisplay/RangeDisplay.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        range = ns.RangeDisplay
        range:OnEnable()
        target = _G.DDingToolKit_RangeDisplayTargetFrame
        function shown(id, role) spec = {id, role}; range:UpdateAll(); return target:IsShown() end
    ''')
    return lua


def roles(lua):
    return {name: lua.globals().shown(*spec) for name, spec in SPECS.items()}


def test_every_role_shows_by_default():
    lua = range_runtime()
    assert roles(lua) == {"TANK": True, "HEALER": True, "MELEE": True, "RANGED": True}


def test_unchecked_roles_hide_the_display():
    lua = range_runtime()
    lua.execute("range.db.showTank = false; range.db.showRanged = false")
    assert roles(lua) == {"TANK": False, "HEALER": True, "MELEE": True, "RANGED": False}
    # unreadable spec keeps showing
    lua.execute("function GetSpecialization() return nil end; range:UpdateAll()")
    assert lua.eval("target:IsShown()")


def test_settings_have_four_role_boxes():
    lua = config_runtime()
    lua.execute('''
        for _, k in ipairs({"showTank", "showHealer", "showMelee", "showRanged"}) do
            local s = assert(fields["profile.RangeDisplay." .. k], k)
            assert(ns:GetDBValue("profile.RangeDisplay." .. k) == true, k .. " default on")
        end
        assert(fields["profile.RangeDisplay.showTank"].label == "탱커 전문화")
    ''')
