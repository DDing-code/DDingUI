import re
from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parents[1]


def test_talent_background_locale_keys_are_registered():
    keys = set()
    for path in (ROOT / "Modules/TalentBG").glob("*.lua"):
        keys.update(re.findall(r'\bL\["([^"]+)"\]', path.read_text(encoding="utf-8-sig")))
    assert "TALENTBG_NO_SELECTION" in keys

    for language in ("enUS", "koKR", "frFR"):
        lua = LuaRuntime()
        lua.execute('''
            local language = ...
            function GetLocale() return language end
            function geterrorhandler() return error end
            strmatch = string.match
            ns = {}
        ''', language)
        for name in ("Libs/LibStub/LibStub.lua", "Libs/AceLocale-3.0/AceLocale-3.0.lua",
                     "Locales/enUS.lua", "Locales/koKR.lua", "Locales/Locale.lua"):
            lua.execute((ROOT / name).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
        read = lua.eval("function(key) return ns.L[key] end")
        for key in sorted(keys):
            assert read(key) and read(key) != key, (language, key)
        if language == "koKR":
            assert read("TALENTBG_NO_SELECTION") != "No selection"
        else:
            assert read("TALENTBG_NO_SELECTION") == "No selection"
