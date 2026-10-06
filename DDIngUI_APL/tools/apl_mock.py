"""Shared Lua 5.1 mock runtime for DDIngUI_APL tests (lupa.lua51).
Loads every TOC file into a fresh runtime. Mocks verify Lua behavior, NOT WoW secret/taint
or protected-frame behavior.
"""
from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parents[1]
ROOT = ADDON.parent
sys.path.insert(0, str(ROOT))
from test_dashboard_workspace import STUBS  # reuse the workspace's native-frame double

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
lua.execute(r"""
LibStub=nil
strmatch=string.match;strfind=string.find;strsub=string.sub
local F=getmetatable(UIParent)
for _,method in ipairs({"SetMovable","SetClampedToScreen","RegisterForDrag","StartMoving",
    "StopMovingOrSizing","RegisterEvent","UnregisterEvent","SetMultiLine","SetAutoFocus",
    "SetMaxLetters","SetTextInsets","SetNumeric","ClearFocus","SetFocus","SetEnabled",
    "SetShadowOffset","SetShadowColor","RegisterForClicks","SetPropagateKeyboardInput",
    "SetMouseClickEnabled","SetMouseMotionEnabled","SetToplevel","SetHitRectInsets",
    "SetValueStep","SetObeyStepOnDrag","SetThumbTexture"}) do -- [STYLE] title-bar GUI scale slider
    F[method]=function()end
end
-- [STYLE] C12 edit remote: keyboard capture, focus and saved-point reads.
for _,method in ipairs({"EnableKeyboard","SetClampRectInsets"}) do F[method]=function()end end
function F:HasFocus()return false end
function F:GetPoint()local p=self.point;if not p then return nil end;return p[1],p[2],p[3],p[4],p[5] end
function GetCurrentKeyBoardFocus()return nil end
function IsShiftKeyDown()return false end
function IsControlKeyDown()return false end
-- [STYLE] Record frames so Advance() can drive StyleLib Motion tweens (OnUpdate) in mock time.
OBJECTS={}
local rawCreateFrame=CreateFrame
function CreateFrame(...) local f=rawCreateFrame(...); OBJECTS[#OBJECTS+1]=f; return f end
function Advance(seconds)
    clockTime=clockTime+seconds
    for _,f in ipairs(OBJECTS) do
        if f~=(A and A.events) and f.shown and f.scripts and f.scripts.OnUpdate then f.scripts.OnUpdate(f,seconds) end
    end
end
MINIMAP_STUBS={"SetFixedFrameStrata","SetFixedFrameLevel","SetHighlightTexture"} -- [STYLE] no-op methods LibDBIcon calls on its button
for _,method in ipairs(MINIMAP_STUBS) do if not F[method] then F[method]=function()end end end
local sink;sink=setmetatable({},{__index=function()return function()return sink end end}) -- [STYLE] LibDBIcon fade animation
if not F.CreateAnimationGroup then function F:CreateAnimationGroup()return sink end end
function F:GetCenter()return 400,300 end
function F:SetScrollChild(f)self.scrollChild=f end
function F:SetVerticalScroll(v)self.scroll=v end
function F:GetVerticalScroll()return self.scroll or 0 end
function F:GetStringWidth()return 80 end
function F:SetClipsChildren()end
function F:UpdateAllAuras()end
function F:SetUnit(unit)self.unit=unit end
function F:AddAuraSlot(key,filter,config)
    local b=CreateFrame("Frame",nil,self)
    function b:SetIcon(icon)self.boundIcon=icon end
    function b:SetDurationCooldown(cd)self.boundCooldown=cd end
    function b:SetApplicationCount(fs)self.boundCount=fs end
    config.initializeFrame(b)
    self.slot=b
end
UISpecialFrames={};SlashCmdList={};tinsert=table.insert
Minimap=CreateFrame('Frame','Minimap',UIParent) -- [STYLE] LibDBIcon hooks Minimap at load
GetPhysicalScreenSize=GetPhysicalScreenSize or function()return 3440,1440 end -- [STYLE] series StyleLib PixelUtil
function GetLocale()return "koKR" end
combat=false;specID=70
function InCombatLockdown()return combat end
function GetSpecialization()return 1 end
function GetSpecializationInfo()return specID end
function UnitAffectingCombat()return combat end
function UnitExists()return true end
function UnitCanAttack()return true end
function UnitIsDeadOrGhost()return false end
function UnitPower()return 3 end
function UnitPowerMax()return 5 end
function IsPlayerSpell(id)return id==35395 or id==85256 end
function GetActionBarPage()return 1 end
function GetActionInfo(slot)if slot==1 then return "spell",35395 elseif slot==61 then return "spell",85256 end end
function GetBindingKey(key)return key=="ACTIONBUTTON1" and "1" or key=="MULTIACTIONBAR1BUTTON1" and "F" or nil end
C_Spell={
    GetSpellCooldown=function()return {startTime=0,duration=0,modRate=1,isEnabled=true}end,
    IsSpellUsable=function()return true end,
    IsSpellHarmful=function()return true end,
    IsSpellInRange=function()return true end,
    GetSpellTexture=function(id)return id end,
}
C_UnitAuras={GetPlayerAuraBySpellID=function()return nil end}
C_Secrets={ShouldSpellAuraBeSecret=function()return false end}
C_AssistedCombat={IsAvailable=function()return true end,GetNextCastSpell=function()return 35395 end}
""")
ns = lua.table()
toc = (ADDON / "DDIngUI_APL.toc").read_text(encoding="utf-8-sig")
files = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
for file in files:
    path = ADDON / file.replace("\\", "/")
    assert path.is_file(), file
    lua.execute(path.read_text(encoding="utf-8-sig"), "DDIngUI_APL", ns)
lua.globals().A = ns
