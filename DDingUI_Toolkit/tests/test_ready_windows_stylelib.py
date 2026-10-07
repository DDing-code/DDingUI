"""Both ready-check windows built on the real embedded StyleLib (rounded surfaces, series title bar)."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from test_edit_mode import HARNESS, STYLELIB, runtime  # noqa: E402

EXTRA = r'''
local M = getmetatable(UIParent).__index
for _, k in ipairs({ "SetShadowOffset", "SetShadowColor", "SetMask", "RegisterEvent", "SetBackdrop" }) do
    if not M[k] then M[k] = function() end end
end
if not M.GetName then function M:GetName() return self.name end end
UISpecialFrames = UISpecialFrames or {}
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 262, "Elemental", nil, 136048 end
function UnitClass() return "Shaman", "SHAMAN" end
function GetInventoryItemDurability() return 90, 100 end
function GetWeaponEnchantInfo() return true, 3600000, 0, 1, nil end
function IsInRaid() return false end
function IsInGroup() return true end
function GetInstanceInfo() return "x", "raid" end
C_Timer.NewTicker = function() return { Cancel = function() end } end
ns.Print = function(msg) printed[#printed + 1] = tostring(msg) end
ns.DDingToolKit.RegisterModule = function() end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
ns.DeepCopy = function(_, t) local n = {}; for k, v in pairs(t) do n[k] = v end; return n end
ns.db.profile.ReadyCheckAssistant = { raidLoadouts = "" }
ns.db.profile.RaidPreparation = { position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 10 } }
'''


def stylelib_runtime():
    lua = runtime()
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * .65
    lua.execute(HARNESS)
    lua.execute(EXTRA)
    bundle = ROOT / "Libs/DDingUI_StyleLib"
    for name in STYLELIB:
        lua.execute('local source,owner=...; assert(loadstring(source))(owner)',
                    (bundle / name).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit")
    for rel in ("UI/ReadyStatus.lua", "Modules/RaidPreparation/RaidPreparation.lua",
                "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua"):
        lua.execute('local source,owner,ns=...; assert(loadstring(source))(owner, ns)',
                    (ROOT / rel).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    return lua


def test_windows_use_rounded_stylelib_surfaces_and_series_title_bar():
    lua = stylelib_runtime()
    lua.execute('''
        local SL = DDingUI_StyleLib
        assert(SL and SL.MakeRounded and SL.CreateTitleBar, "real StyleLib expected")
        -- E: personal checklist
        local rca = ns.ReadyCheckAssistant
        rca:OnEnable()
        local panel = rca.frame
        assert(panel._ddslRounded, "panel must be rounded")
        assert(panel.titleBar and panel.titleBar.brandLogo, "series title bar with logo rings")
        assert(panel.closeButton == panel.titleBar.closeBtn and not panel.titleBar.verText:IsShown())
        assert(panel:GetWidth() == 300 and panel:GetHeight() == 220)
        rca:EnterEditPreview()
        assert(panel:IsShown())
        assert(panel.summaryPill.fill._ddslRoundTex and panel.rows[1].card._ddslRoundTex)
        panel.closeButton:GetScript("OnClick")()
        assert(not panel:IsShown())

        -- C: raid strip
        local prep = ns.RaidPreparation
        prep:OnEnable()
        prep.roster = { { name = "A", classToken = "MAGE", ready = true, food = false, flask = true, rune = true,
            raidBuff = true, weapon = true, durability = 100 } }
        function prep:CollectRoster() return self.roster end
        function prep:UpdateDynamicRoster() end
        prep:ShowWindow(false)
        local strip = prep.frame
        assert(strip._ddslRounded and strip:GetWidth() == 372 and strip:GetHeight() == 92)
        assert(strip.icons[1].badge:IsShown() and strip.icons[1].badge.fill._ddslRoundTex)
        assert(strip.gauge.segments[1]._ddslRoundTex)
        assert(strip.icons[1].state == "bad" and strip.icons[1].badgeCount == 1)
        strip.closeButton:GetScript("OnClick")()
        assert(not strip:IsShown())
    ''')


def test_own_item_icons_are_64px_top_left_tga():
    import re
    from PIL import Image

    source = (ROOT / "UI/ReadyStatus.lua").read_text(encoding="utf-8")
    names = re.findall(r'ICON_PATH \.\. "(\w+)"', source)
    assert sorted(names) == ["durability", "flask", "food", "raidbuff", "rune", "weapon"]
    for name in names:
        path = ROOT / f"Media/ReadyStatus/ready_{name}.tga"
        header = path.read_bytes()[:18]
        assert header[2] == 2 and header[16] in (24, 32), name  # uncompressed true-colour
        assert header[17] & 0x20, f"{name}: TGA origin must be top-left"
        with Image.open(path) as image:
            assert image.size == (64, 64), name
