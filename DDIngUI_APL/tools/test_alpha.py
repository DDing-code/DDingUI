"""Run with python DDIngUI_APL/tools/test_alpha.py (uses installed lupa.lua51).
Mocks verify Lua behavior, NOT WoW secret/taint or protected-frame behavior.
"""
import hashlib
import json

from apl_mock import ADDON, lua, ns
lua.execute(r"""
local E=A.Engine
local function value(text,state)
    local ast,err=E.Expression(text)
    assert(ast,err)
    return E.Value(ast,state or {})
end
assert(value("0|1&0")==0)
assert(value("!0&3")==1)
assert(value("9%2")==4.5 and value("-9%%2.5")==-1.5)
assert(value("2<?3")==3 and value("2>?3")==2)
assert(value("floor(2.9)+ceil(2.1)+@-2")==7)
assert(value("ceil(missing)")==E.Unknown)
assert(value("0&missing")==0 and value("1|missing")==1)
assert(value("missing&0")==0 and value("missing|1")==1)
assert(value("!missing")==E.Unknown)
assert(value("1%0")==E.Unknown)
assert(value("1e308*1e308")==E.Unknown)
assert(not E.Expression("1e999"))
assert(not E.Expression("loadstring('hello')"))
assert(not E.Expression(string.rep("(",70).."1"..string.rep(")",70)))
local p=E.Compile("actions=spell_1,if=buff.proc.up\nactions+=/spell_2")
assert(p.valid)
assert(E.Select(p,{values={},ready={spell_1=true,spell_2=true}}).kind=="unknown")
assert(E.Select(p,{values={},ready={spell_1=false,spell_2=true}}).action=="spell_2")
assert(E.Select(p,{values={["buff.proc.up"]=false},ready={spell_1=true,spell_2=true}}).action=="spell_2")
assert(E.Select(p,{values={["buff.proc.up"]=true},ready={spell_1=true,spell_2=true}}).action=="spell_1")
p=E.Compile("actions=/spell_1,target_if=min:health")
assert(p.valid and not p.complete and #p.warnings==1)
assert(E.Select(p,{ready={spell_1=true}}).kind=="blocked")
-- An unrelated/unreached unsupported rule must not reject the entire personal APL.
p=E.Compile("actions.precombat=/snapshot_stats\nactions=/spell_1\nactions.unused=/use_items")
assert(p.valid and E.Select(p,{ready={spell_1=true}}).action=="spell_1")
p=E.Compile("actions=/call_action_list,name=child,if=0\nactions+=/spell_2\nactions.child=/use_items")
assert(E.Select(p,{ready={spell_2=true}}).action=="spell_2")
p=E.Compile("actions=/call_action_list,name=child\nactions+=/spell_2\nactions.child=/use_items")
assert(E.Select(p,{ready={spell_2=true}}).kind=="blocked")
p=E.Compile("actions=/spell_1,target_if=min:health,if=target.health.pct<20\nactions+=/spell_2")
assert(E.Select(p,{values={["target.health.pct"]=100},ready={spell_1=false,spell_2=true}}).kind=="blocked")
assert(E.Select(p,{ready={spell_1=false,spell_2=true},disabled={spell_1=true}}).action=="spell_2")
assert(not E.Compile("actions=/spell_1,if=").valid)
assert(not E.Compile("actions=/spell_1\nos.execute('bad')").valid)
assert(not E.Compile(string.rep("x",262145)).valid)
p=E.Compile("actions=/call_action_list,name=child\nactions+=/spell_2\nactions.child=/spell_1,if=0")
assert(E.Select(p,{ready={spell_2=true}}).action=="spell_2")
p=E.Compile("actions=/run_action_list,name=child\nactions+=/spell_2\nactions.child=/spell_1,if=0")
assert(E.Select(p,{ready={spell_2=true}}).kind=="none")
p=E.Compile("actions=/call_action_list,name=default")
assert(E.Select(p,{}).kind=="blocked")
p=E.Compile("actions=/variable,name=x,op=setif,condition=0,value=5,value_else=2\n"
    .."actions+=/spell_1,if=variable.x=2")
assert(p.valid and E.Select(p,{ready={spell_1=true}}).action=="spell_1")
p=E.Compile("actions=/variable,name=x,op=reset,default=2.7\nactions+=/variable,name=x,op=ceil\nactions+=/spell_1,if=variable.x=3")
assert(p.valid and E.Select(p,{ready={spell_1=true}}).action=="spell_1")
local demo=E.Demo(2)
assert(demo[1].action=="generator" and demo[2].action=="spender" and demo[3].action=="generator")
local count,sourced=0,0
for id,source in pairs(A.Packs.specs) do
    count=count+1
    if source.raw~="" then
        sourced=sourced+1
        local pack=E.Compile(source.raw)
        assert(pack.count>0,source.name)
        assert(pack.valid,source.name.." failed to parse")
    end
end
assert(count==40 and sourced==34)

local API=A.API
assert(API.Query(function()return SECRET end)==nil)
assert(API.Number(SECRET)==nil)
assert(API.Query(function()error("restricted")end)==nil)
assert(API.Query(function()return false end)==false)
assert(not API.Aliases("foo=2\nfoo=3"))
assert(not API.Aliases("foo=1; print(123)"))
assert(API.Aliases("holy=85256").holy==85256)
local pack=E.Compile("actions=/spell_35395,if=buff.spell_1.down")
local bindings=API.Bind(pack,{})
local snapshot=API.Snapshot(pack,bindings,{targets=1})
assert(snapshot.values["buff.spell_1.down"]==true)
C_Secrets.ShouldSpellAuraBeSecret=function()return true end
snapshot=API.Snapshot(pack,bindings,{targets=1})
assert(snapshot.values["buff.spell_1.down"]==nil)
C_Secrets.ShouldSpellAuraBeSecret=function()return false end
C_UnitAuras.GetPlayerAuraBySpellID=function()error("restricted")end
assert(API.Snapshot(pack,bindings,{targets=1}).values["buff.spell_1.down"]==nil)
C_UnitAuras.GetPlayerAuraBySpellID=function()return {spellId=SECRET,applications=SECRET}end
assert(API.Snapshot(pack,bindings,{targets=1}).values["buff.spell_1.down"]==nil)
C_UnitAuras.GetPlayerAuraBySpellID=function()return {spellId=1,applications=2,expirationTime=10,duration=10}end
pack=E.Compile("actions=/spell_35395,if=buff.spell_1.stack=2")
assert(API.Snapshot(pack,API.Bind(pack,{}),{targets=1}).values["buff.spell_1.stack"]==2)
C_Spell.GetSpellCooldown=function()return {startTime=SECRET,duration=SECRET,modRate=1,isEnabled=true}end
assert(API.Snapshot(pack,API.Bind(pack,{}),{targets=1}).ready.spell_35395==nil)
C_Spell.GetSpellCooldown=function()return {startTime=SECRET,duration=SECRET,modRate=SECRET,isEnabled=true,isActive=false}end
assert(API.Snapshot(pack,API.Bind(pack,{}),{targets=1}).ready.spell_35395==true)
C_Spell.GetSpellCooldown=function()return {startTime=SECRET,duration=SECRET,modRate=SECRET,isEnabled=true,isActive=true}end
assert(API.Snapshot(pack,API.Bind(pack,{}),{targets=1}).ready.spell_35395==false)
C_Spell.GetSpellCooldown=function()return {startTime=0,duration=0,modRate=1,isEnabled=SECRET}end
assert(API.Snapshot(pack,API.Bind(pack,{}),{targets=1}).ready.spell_35395==nil)
C_Spell.GetSpellCooldown=function()return {startTime=0,duration=0,modRate=1,isEnabled=true}end
local unlearned=E.Compile("actions=/spell_999,if=buff.proc.up\nactions+=/spell_35395")
assert(E.Select(unlearned,API.Snapshot(unlearned,API.Bind(unlearned,{}),{targets=1})).action=="spell_35395")
UnitPower=function()return SECRET end
pack=E.Compile("actions=/spell_35395,if=holy_power>1")
assert(E.Select(pack,API.Snapshot(pack,API.Bind(pack,{}),{targets=1})).kind=="unknown")
UnitPower=function()return 3 end

A.events.scripts.OnEvent(A.events,"ADDON_LOADED","DDIngUI_APL")
A.events.scripts.OnEvent(A.events,"PLAYER_ENTERING_WORLD")
assert(A.db and A.display and A.spec==70)
assert(A.db.mode=="strict" and A.last.source=="APL" and A.last.kind~="action" and not A.runtimeError,A:Diagnostics())
A.db.mode="auto";A:Tick()
assert(A.last.source=="BLIZZARD" and A.aplResult.kind~="action")
assert(A:Diagnostics():find("APL reason:",1,true))
local ok=A:Import("actions=/spell_85256,if=holy_power>=3\nactions+=/spell_35395","")
assert(ok)
A:Tick()
assert(A.last.source=="APL" and A.last.spellID==85256)
assert(#A.last.queue==1)
assert(not A.display.slots[2]:IsShown() and A.display.forecastNote:IsShown())
assert(A.keys[35395]=="1" and A.keys[85256]=="F")
local before=A:Profile().raw
assert(not A:Import("actions=/spell_35395,if=",""))
assert(A:Profile().raw==before,"failed import replaced active profile")
combat=true
assert(not A:Import("actions=/spell_35395",""))
assert(A:Profile().raw==before)
combat=false
-- Real Core -> API -> Engine -> UI path with Blizzard disabled and 12.1-shaped data.
local nativeAPI=C_AssistedCombat.GetNextCastSpell
local cdAPI=C_Spell.GetSpellCooldown
local rangeAPI=C_Spell.IsSpellInRange
local nativeCalls=0
C_AssistedCombat.GetNextCastSpell=function()nativeCalls=nativeCalls+1;error("Blizzard disabled")end
C_Spell.GetSpellCooldown=function()return {isEnabled=true,isActive=false,startTime=SECRET,duration=SECRET,modRate=SECRET}end
C_Spell.IsSpellInRange=function()return nil end
C_Spell.SpellHasRange=function()return false end
A.db.mode="native"
assert(A:Import("actions.precombat=/snapshot_stats\nactions=/spender,if=holy_power>=3\nactions+=/generator","spender=85256\ngenerator=35395"))
assert(A.db.mode=="strict","applying APL left native mode selected")
combat=true;A:Tick()
assert(A.last.source=="APL" and A.last.spellID==85256 and A.display.slots[1].icon.texture==85256)
UnitPower=function()return 0 end;A:Tick()
assert(A.last.spellID==35395 and A.display.slots[1].icon.texture==35395)
UnitPower=function()return SECRET end;A:Tick()
assert(A.last.kind=="unknown" and A.last.reason=="holy_power" and not A.display.slots[1].icon.texture)
combat=false
assert(A:Import("actions=/generator\nactions+=/spender","spender=85256\ngenerator=35395"))
UnitPower=function()return 3 end;A:Tick()
assert(A.last.spellID==35395,"changing APL order did not change recommendation")
C_Spell.SpellHasRange=function()return true end;A:Tick()
assert(A.last.kind=="unknown" and A.last.reason:find("range",1,true))
C_Spell.IsSpellInRange=rangeAPI
assert(A:Import(before,""));A:Tick()
assert(A.last.spellID==85256 and nativeCalls==0,"APL depended on Blizzard fallback")
C_Spell.GetSpellCooldown=cdAPI;C_AssistedCombat.GetNextCastSpell=nativeAPI
-- Only proven unlearned named actions can be skipped. Missing/ambiguous IDs stay unknown.
A.Packs.spells.test_unlearned={991,992}
assert(API.Resolve("test_unlearned",{})==false)
assert(API.Resolve("no_such_token",{})==nil)
A.Packs.spells.test_ambiguous={35395,85256}
assert(API.Resolve("test_ambiguous",{})==nil)
local named=E.Compile("actions=/test_unlearned,if=buff.proc.up\nactions+=/spell_35395")
assert(E.Select(named,API.Snapshot(named,API.Bind(named,{}),{targets=1})).action=="spell_35395")
-- Simulation commands are not ordinary named spells, even if a DBC name happens to match.
A.Packs.spells.use_items={991}
local special=E.Compile("actions=/use_items\nactions+=/spell_35395")
assert(API.Bind(special,{}).use_items==nil)
assert(E.Select(special,API.Snapshot(special,API.Bind(special,{}),{targets=1})).kind=="blocked")
-- Action-bar visibility/setup must not discard a public recommendation.
local availableAPI=C_AssistedCombat.IsAvailable
C_AssistedCombat.IsAvailable=function()return false,"hidden assistant" end
C_AssistedCombat.GetNextCastSpell=function(visible)assert(visible==false);return 35395 end
assert(API.Native()==35395)
C_AssistedCombat.IsAvailable=availableAPI
-- An empty sample gets only a bounded, desaturated display grace; the engine stays unresolved.
A.db.mode="native";clockTime=100;A:Tick()
assert(A.display.slots[1].icon.texture==35395)
C_AssistedCombat.GetNextCastSpell=function()return nil end
clockTime=100.1;A:Tick()
assert(A.last.nativeStatus=="empty" and not A.last.queue)
assert(A.display.slots[1].icon.texture==35395 and A.display.slots[1].icon.desaturated)
clockTime=100.5;A:Tick();assert(not A.display.slots[1].icon.texture)
C_AssistedCombat.GetNextCastSpell=function()return 85256 end
A:Tick();assert(A.display.slots[1].icon.texture==85256 and not A.display.slots[1].icon.desaturated)
-- Target change and unreadable/unavailable responses must never retain an old icon.
C_AssistedCombat.GetNextCastSpell=function()return nil end
A.events.scripts.OnEvent(A.events,"PLAYER_TARGET_CHANGED")
assert(not A.display.slots[1].icon.texture)
C_AssistedCombat.GetNextCastSpell=function()return 35395 end;A:Tick()
C_AssistedCombat.GetNextCastSpell=function()return SECRET end;A:Tick()
assert(A.last.nativeStatus=="unreadable" and not A.display.slots[1].icon.texture)
C_AssistedCombat.GetNextCastSpell=function()return 35395 end;A:Tick()
C_AssistedCombat.GetNextCastSpell=function()return nil end
C_AssistedCombat.IsAvailable=function()return false,"disabled" end;A:Tick()
assert(A.last.nativeStatus=="unavailable" and not A.display.slots[1].icon.texture)
C_AssistedCombat.IsAvailable=availableAPI
C_AssistedCombat.GetNextCastSpell=function()return 35395 end
-- Slot/key/spell churn must not destroy the loaded APL in combat.
A.db.mode="strict";combat=true
local compiled=A.pack
for _,event in ipairs({"ACTIONBAR_SLOT_CHANGED","UPDATE_BINDINGS","ACTIONBAR_PAGE_CHANGED","SPELLS_CHANGED"}) do
    A.events.scripts.OnEvent(A.events,event)
    assert(A.pack==compiled,event.." discarded APL")
end
A:Tick();assert(A.last.source=="APL" and A.last.spellID==85256)
combat=false;A.events.scripts.OnEvent(A.events,"PLAYER_REGEN_ENABLED")
A.db.mode="auto"
A:OpenOptions()
assert(A.options and A.options:IsShown())
-- [STYLE] C4 BindPanel + title-bar GUI scale (guiScale is the only new DB key, default 1.0).
local o=A.options
assert(A.db.guiScale==1 and o.HideImmediately and o.SetBaseScale and o.titleBar.scaleControl)
assert(o.titleBar.editButton and o.titleBar.editButton.point[2]==o.titleBar.closeBtn,"C12 edit button sits left of close")
assert(o.titleBar.scaleControl.point[1]=="RIGHT" and o.titleBar.scaleControl.point[2]==o.titleBar.editButton,"GUI scale sits left of the edit button")
Advance(.2);assert(o:GetScale()==1 and o:GetAlpha()==1)
o.titleBar.closeBtn.scripts.OnClick(o.titleBar.closeBtn)
assert(o:IsShown() and o._ddslPanelClosing,"close button must use the close motion")
Advance(.2);assert(not o:IsShown())
A.db.guiScale=.8;o:SetBaseScale(.8)
A:OpenOptions();Advance(.2);assert(o:IsShown() and math.abs(o:GetScale()-.8)<1e-6)
A:OpenOptions();Advance(.2);assert(not o:IsShown() and math.abs(o:GetScale()-.8)<1e-6)
A.db.guiScale=1;o:SetBaseScale(1)
A:OpenOptions();Advance(.2);assert(o:IsShown())
-- [STYLE] StaggerIn must settle every row at full alpha; the settings window has no text under 12pt.
local function walk(frame,fn) fn(frame); for _,r in ipairs(frame.regions) do fn(r) end; for _,c in ipairs(frame.children) do walk(c,fn) end end
Advance(.2);Advance(.2) -- stagger cascade (<=0.21s) + 0.16s fade
walk(o,function(x) assert(x.alpha==1,"row left faded") ; if x.kind=="FontString" and x.fontSize then assert(x.fontSize>=12,"text under 12pt") end end)
-- [STYLE] 시안 7: rounded window, tab/body cards 8px inside, logo rings, watermark, selected-tab pill.
local R=LibStub("DDingUI-StyleLib-1.0").Radius
assert(o._ddslRounded and o._ddslRounded.radius==R.window,"options window must be rounded")
for _,c in ipairs({o.tabCard,o.body}) do
    assert(c._ddslRounded and c._ddslRounded.radius==R.card and c.parent==o,"card must be rounded")
    assert(c.point[1]=="TOPLEFT" and c.point[2]==8 and c.width==744,"card must sit 8px inside the window")
end
assert(o.body.point[3]+(-o.body.height)==-662 and o.height==670,"body card must end 8px above the window bottom")
assert(o.logo and o.logo.leftRing and o.logo.rightRing and o.logo.parent==o.titleBar,"title logo rings missing")
assert(o.watermark and o.watermark.parent==o.body and o.watermark.point[1]=="BOTTOMRIGHT","body watermark missing")
assert(#o.tabs==4)
for i,tab in ipairs(o.tabs) do
    assert(tab.parent==o.tabCard and tab.pill)
    tab.scripts.OnClick(tab)
    for j,other in ipairs(o.tabs) do assert(other.pill.shown==(i==j),"only the selected tab shows its pill") end
    assert(o.page==i)
end
o.tabs[1].scripts.OnClick(o.tabs[1])
-- [STYLE] Display (HUD) text also respects the series 12pt minimum.
walk(A.display,function(x) if x.kind=="FontString" and x.fontSize then assert(x.fontSize>=12,"HUD text under 12pt") end end)
A.db.mode="strict";UnitPower=function()return SECRET end;A:Tick()
assert(A.last.kind=="unknown" and A.last.source=="APL")
A.db.mode="auto";A:Tick();assert(A.last.source=="BLIZZARD")
C_AssistedCombat.GetNextCastSpell=function()return SECRET end
A:Tick();assert(A.last.kind=="unknown" and not A.last.spellID)
C_AssistedCombat.GetNextCastSpell=function()return 35395 end
A.preview=true;A:Tick();assert(#A.last.queue==3 and A.last.source=="PREVIEW")
assert(A.display.slots[2]:IsShown() and A.display.slots[3]:IsShown() and not A.display.forecastNote:IsShown())
combat=true
A.events.scripts.OnEvent(A.events,"PLAYER_REGEN_DISABLED")
assert(not A.preview and not A.options:IsShown())
specID=1480
A.events.scripts.OnEvent(A.events,"PLAYER_SPECIALIZATION_CHANGED")
assert(A.pending and A.pack==nil)
combat=false
A.events.scripts.OnEvent(A.events,"PLAYER_REGEN_ENABLED")
assert(A.spec==1480 and not A.pending and A.source.key=="demonhunter_devourer")
A.db.auraSpellID=123;A:ApplyAuraCue()
assert(A.auraProxy and A.auraSpell==123)
local old=A.auraProxy
A.db.auraSpellID=456;A:ApplyAuraCue()
assert(A.auraProxy==old and not old:IsShown(),"reused protected slot for another aura")
for id in pairs(A.Packs.specs) do
    specID=id;A:RefreshProfile();A:Tick()
    assert(A.source.id==id and not A.runtimeError,"spec refresh failed")
end
-- [STYLE] Series minimap button via StyleLib helper (real LDB/LibDBIcon code, mock tooltip).
combat=false
local icons=LibStub("LibDBIcon-1.0")
local obj=LibStub("LibDataBroker-1.1"):GetDataObjectByName("DDIngUI_APL")
assert(icons:IsRegistered("DDIngUI_APL") and obj,"minimap button not registered")
assert(obj.icon==[[Interface\AddOns\DDIngUI_APL\Media\APL_Icon.tga]])
assert(icons:GetMinimapButton("DDIngUI_APL").db==A.db.minimap and A.db.minimap.hide==false)
local tip={lines={}}
function tip:SetText(t)self.title=t end
function tip:AddLine(t)self.lines[#self.lines+1]=t end
obj.OnTooltipShow(tip)
assert(tip.title:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")=="DDingUI APL" and #tip.lines==3,"tooltip must be title + 3 lines")
assert(tip.lines[1]:find("좌클릭",1,true) and tip.lines[1]:find("설정 창 열기/닫기",1,true))
assert(tip.lines[2]:find("우클릭",1,true) and tip.lines[2]:find("편집 모드 · 위치 조정",1,true))
assert(tip.lines[3]:find("드래그",1,true) and tip.lines[3]:find("버튼 위치 이동",1,true))
MINIMAP_TIP=tip
local shown=A.options and A.options:IsShown()
obj.OnClick(nil,"LeftButton");Advance(.2);assert(A.options:IsShown()~=shown) -- [STYLE] animated close/open
obj.OnClick(nil,"LeftButton");Advance(.2);assert(A.options:IsShown()==shown)
-- [STYLE] C12: right click toggles edit mode (lock untouched); blocked in combat. Details: test_editmode.py.
local locked=A.db.locked
obj.OnClick(nil,"RightButton");assert(A.editing and A.db.locked==locked,"right click must enter edit mode")
obj.OnClick(nil,"RightButton");assert(not A.editing and A.db.locked==locked,"right click must leave edit mode")
combat=true;obj.OnClick(nil,"RightButton");assert(not A.editing,"edit mode must not open in combat")
combat=false
A:ToggleDisplayLock();assert(A.db.locked==not locked);A:ToggleDisplayLock();assert(A.db.locked==locked)
A.db.minimap=nil;A.events.scripts.OnEvent(A.events,"ADDON_LOADED","DDIngUI_APL")
assert(type(A.db.minimap)=="table" and A.db.minimap.hide==false and icons:GetMinimapButton("DDIngUI_APL"),"minimap table must be recreated once")
""")

manifest = json.loads((ADDON / "Packs/manifest.json").read_text(encoding="utf-8"))
assert len(manifest["specs"]) == 40
assert sum(bool(s["source"]) for s in manifest["specs"]) == 34
for spec in manifest["specs"]:
    raw = ns.Packs.specs[spec["specID"]].raw
    if spec["sha256"]:
        assert hashlib.sha256(raw.encode()).hexdigest() == spec["sha256"], spec
for file in ADDON.rglob("*.lua"):
    lua.eval("function(s) return assert(loadstring(s)) end")(file.read_text(encoding="utf-8-sig"))
print("minimap tooltip:", lua.globals().MINIMAP_TIP.title, *[lua.globals().MINIMAP_TIP.lines[i] for i in (1, 2, 3)])
print("PASS: Lua 5.1 TOC load + parser/unknown/secret-boundary/import/UI/spec-switch/minimap checks; 40 specs / 34 source hashes.")
