from pathlib import Path

from lupa.lua51 import LuaRuntime


SOURCE = (Path(__file__).parents[1] / "Media/SharedMedia.lua").read_text(encoding="utf-8-sig")


def test_builtin_sounds_register_only_existing_file_ids():
    for quest_exists in (True, False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            ns, registered = {}, {}
            C_UIFileAsset = {
                GetFileID = function(path)
                    if path == "Sound\\Interface\\AlarmClockWarning1.ogg" then return 123 end
                end,
                IsKnownFile = function(id) return id == 123 or (id == 567439 and questExists) end,
            }
            local media = { Register = function(_, kind, name, value)
                if kind == "sound" then
                    assert(type(value) == "number", "Blizzard sound paths must not reach LibSharedMedia")
                    registered[name] = value
                end
            end }
            function LibStub() return media end
        ''')
        lua.globals().questExists = quest_exists
        lua.execute(SOURCE, "DDingUI_Toolkit", lua.globals().ns)
        registered = lua.globals().registered
        assert registered["Alarm Clock Warning 1"] == 123
        assert registered["Quest Complete"] == (567439 if quest_exists else None)
        assert registered["Bell 01"] is None
        assert registered["None"] is None
