"""캐릭터 위치 마커: 사거리 색 변경을 탱커·근딜·원딜·힐러별로 켜고 끈다."""
from test_settings_cleanup import config_runtime, load

SPECS = {  # specID, role, range spell
    "TANK": (73, "TANK"), "MELEE": (71, "DAMAGER"), "RANGED": (62, "DAMAGER"), "HEALER": (65, "HEALER"),
}


def marker_runtime(profile_lua=""):
    lua = config_runtime()
    lua.execute('''
        spec = {73, "TANK"}
        function GetSpecialization() return 1 end
        function GetSpecializationRole() return spec[2] end
        function GetSpecializationInfo() return spec[1], "x", nil, nil, spec[2] end
        function UnitExists() return true end
        function UnitCanAttack() return true end
        function UnitIsDeadOrGhost() return false end
        C_Spell = { IsSpellInRange = function() return false end, GetSpellName = function() return "x" end }
        -- own saved table (the shared runtime points ns.db.profile at the defaults)
        ns.db = {profile = {CharacterPositionMarker = {}}}
    ''')
    lua.execute(profile_lua)
    load(lua, "Modules/CharacterPositionMarker/CharacterPositionMarker.lua")
    lua.execute('''
        marker = ns.CharacterPositionMarker
        marker:OnInitialize()
        marker.db.rangeSpell = "100"
        function checked(id, role) spec = {id, role}; return marker:IsOutOfMeleeRange() end
    ''')
    return lua


def check_roles(lua):
    return {name: lua.globals().checked(*spec) for name, spec in SPECS.items()}


def test_every_role_checks_range_by_default():
    lua = marker_runtime()
    assert check_roles(lua) == {"TANK": True, "MELEE": True, "RANGED": True, "HEALER": True}


def test_each_role_box_turns_off_only_that_role():
    lua = marker_runtime()
    lua.execute("marker.db.rangeCheckTank = false; marker.db.rangeCheckHealer = false")
    assert check_roles(lua) == {"TANK": False, "MELEE": True, "RANGED": True, "HEALER": False}
    lua.execute("marker.db.rangeCheck = false")
    assert not any(check_roles(lua).values())


def test_old_melee_only_choice_becomes_melee_box():
    lua = marker_runtime("ns.db.profile.CharacterPositionMarker = {meleeDpsOnly = true, rangeModeVersion = 2}")
    assert check_roles(lua) == {"TANK": False, "MELEE": True, "RANGED": False, "HEALER": False}
    db = lua.eval("marker.db")
    assert db.meleeDpsOnly is True, "old value is kept, not deleted"


def test_settings_show_four_boxes_only_while_range_check_is_on():
    lua = marker_runtime()
    lua.execute('''
        local keys = {"rangeCheckTank", "rangeCheckMelee", "rangeCheckRanged", "rangeCheckHealer"}
        for _, k in ipairs(keys) do assert(fields["profile.CharacterPositionMarker." .. k], k) end
        assert(not fields["profile.CharacterPositionMarker.meleeDpsOnly"], "old single box removed")
        ns.db.profile.CharacterPositionMarker.rangeCheck = true
        for _, k in ipairs(keys) do assert(fields["profile.CharacterPositionMarker." .. k].visible()) end
        ns.db.profile.CharacterPositionMarker.rangeCheck = false
        for _, k in ipairs(keys) do assert(not fields["profile.CharacterPositionMarker." .. k].visible()) end
        -- labels say "거리 체크" so they are not mistaken for the "전문화별 표시" boxes
        assert(fields["profile.CharacterPositionMarker.rangeCheckTank"].label == "탱커 거리 체크")
        assert(fields["profile.CharacterPositionMarker.rangeCheckHealer"].label == "힐러 거리 체크")
        assert(fields["profile.CharacterPositionMarker.showTank"].label == "탱커 전문화")
    ''')
