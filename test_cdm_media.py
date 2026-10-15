"""실제 LSM 기본 목록을 사용해 빈 경로 등록과 '소리 없음' 보존을 검사한다."""
from pathlib import Path

import pytest
from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parent


@pytest.mark.parametrize("locale", ("koKR", "enUS"))
def test_media_load_keeps_builtin_none_without_registering_empty_sound(locale):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().GetLocale = lambda: locale
    lua.globals().bit = lua.table_from({"band": lambda a, b: int(a) & int(b)})
    lua.execute('strmatch=string.match; function securecallfunction(fn,...) return fn(...) end')
    for relative in (
        "DDingUI_CDM/Libs/LibStub/LibStub.lua",
        "DDingUI_CDM/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
        "DDingUI_CDM/Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua",
    ):
        lua.execute((ROOT / relative).read_text(encoding="utf-8-sig"))
    lua.execute(r'''
        C_UIFileAsset = {
            GetFileID = function(path)
                if path == "Sound\\Interface\\AlarmClockWarning1.ogg" then return 123 end
                if path == "Sound\\Interface\\igQuestLogOpen.ogg" then return 456 end
            end,
            IsKnownFile = function(id) return id == 123 end,
        }
        LSM=LibStub("LibSharedMedia-3.0")
        local register=LSM.Register
        -- 최신 LSM의 파일 검증 경계: 내장 사운드는 존재하는 파일 번호만 등록한다.
        function LSM:Register(kind,key,path,...)
            assert(path ~= "", "LibSharedMedia-3.0: Attempt to register a file that doesn't exist ('')")
            assert(kind ~= "sound" or (type(path) == "number" and C_UIFileAsset.IsKnownFile(path)))
            return register(self,kind,key,path,...)
        end
        ns={Addon={}}
    ''')
    lua.execute((ROOT / "DDingUI_CDM/Core/Media.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_CDM", lua.globals().ns)
    lua.execute('''
        assert(LSM:IsValid("sound","None"))
        assert(LSM:Fetch("sound","None",true)==1, "Keep LSM's no-sound value")
        assert(LSM:Fetch("sound","Alarm Clock Warning 1",true)==123)
        assert(LSM:Fetch("sound","igQuestLogOpen",true)==nil, "Missing sounds must be skipped")
        local found=false
        for _,name in ipairs(LSM:List("sound")) do
            if name=="None" then found=true end
        end
        assert(found, "No-sound choice must remain in the settings list")
    ''')
