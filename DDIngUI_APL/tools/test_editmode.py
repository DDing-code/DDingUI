"""C12 edit-mode regression for DDIngUI_APL (lupa.lua51, real TOC load).
Run with python DDIngUI_APL/tools/test_editmode.py.
Mocks verify Lua behavior only, NOT WoW keyboard focus, taint or real cursor movement.
"""
from apl_mock import lua

lua.execute(r"""
UIParent.width,UIParent.height=3440,1440
local cursorX,cursorY,mouseDown,shift,ctrl=0,0,false,false,false
function GetCursorPosition() return cursorX,cursorY end
function IsMouseButtonDown() return mouseDown end
function IsShiftKeyDown() return shift end
function IsControlKeyDown() return ctrl end
local function near(a,b,msg) assert(math.abs(a-b)<1e-6,(msg or "")..": "..tostring(a).." ~= "..tostring(b)) end

A.events.scripts.OnEvent(A.events,"ADDON_LOADED","DDIngUI_APL")
A.events.scripts.OnEvent(A.events,"PLAYER_ENTERING_WORLD")
local db=A.db
assert(db.x==0 and db.y==-150 and db.locked==true and db.editRemotePos==nil)

-- 1) Entry from the options title-bar "편집 모드" button: settings close, remote/mover/HUD/grid appear.
A:OpenOptions();Advance(.3)
local o=A.options
assert(o:IsShown() and o.titleBar.editButton.label:GetText()=="편집 모드")
o.titleBar.editButton.scripts.OnClick(o.titleBar.editButton)
local e=A.edit
assert(A.editing and not o:IsShown(),"entry must close the settings window")
assert(o.titleBar.editButton.label:GetText()=="편집 중")
Advance(.3)
assert(e.remote:IsShown() and e.overlay:IsShown() and e.hud:IsShown() and e.grid:IsShown())
assert(e.mover.brackets[1]:IsShown(),"single mover is selected")
assert(e.overlay.point[1]=="CENTER" and e.overlay.point[2]==UIParent and e.overlay.point[4]==0 and e.overlay.point[5]==-150)
assert(e.overlay.width==236 and e.overlay.height==144)
assert(e.hud.box.text:GetText()=="X 0  Y -150  \194\183  236\195\151144",e.hud.box.text:GetText())
assert(e.remote.nameText:GetText()=="APL 표시창")
assert(e.remote.xField.editBox:GetText()=="0" and e.remote.yField.editBox:GetText()=="-150")
assert(e.grid:GetSpacing()==32 and e.snap.enabled)
local function walk(f,fn) fn(f); for _,r in ipairs(f.regions) do fn(r) end; for _,c in ipairs(f.children) do walk(c,fn) end end
walk(e.remote,function(x) assert(not(x.kind=="FontString" and x.text=="프레임"),"frame-snap check is hidden (noFrames)") end)

-- 2) Keyboard nudge (1px, Shift 10px) and Ctrl+Z / Ctrl+Y.
local key=e.remote.scripts.OnKeyDown
key(e.remote,"UP");assert(db.x==0 and db.y==-149)
shift=true;key(e.remote,"LEFT");shift=false;assert(db.x==-10 and db.y==-149)
assert(A.display.point[4]==-10 and A.display.point[5]==-149,"display follows the mover")
ctrl=true;key(e.remote,"Z");assert(db.x==0 and db.y==-149);key(e.remote,"Y");ctrl=false;assert(db.x==-10)
e.remote.buttons["실행 취소"].scripts.OnClick(e.remote.buttons["실행 취소"]);assert(db.x==0)

-- 3) Typed X/Y and the display-scale conversion (mover = UIParent units, db = display-scale units).
e.remote.xField.editBox:SetText("-30");e.remote.yField.editBox:SetText("-200");e.remote:ApplyXY()
assert(db.x==-30 and db.y==-200,"negative typed X/Y")
e.remote.xField.editBox:SetText("100");e.remote.yField.editBox:SetText("50");e.remote:ApplyXY()
assert(db.x==100 and db.y==50)
db.scale=2;A:ApplyLayout()
assert(e.overlay.width==472 and e.overlay.height==288 and e.overlay.point[4]==200 and e.overlay.point[5]==100)
assert(A.display.point[4]==100 and A.display.scale==2,"display keeps its own scale-unit point")
key(e.remote,"UP");near(db.y,50.5,"1px nudge at scale 2");assert(e.overlay.point[5]==101)
A.edit.remote.xField.editBox:SetText("300");e.remote.yField.editBox:SetText("-40");e.remote:ApplyXY()
assert(db.x==150 and db.y==-20)
assert(e.hud.box.text:GetText()=="X 300  Y -40  \194\183  472\195\151288",e.hud.box.text:GetText())
assert(not A:SetEditPosition(SECRET,0) and db.x==150,"secret/invalid input is refused")
assert(not A:SetEditPosition(0/0,0) and db.x==150)
db.scale=1;A:ApplyLayout()

-- 4) Reset goes to the default position.
e.remote.buttons["초기화"].scripts.OnClick(e.remote.buttons["초기화"])
assert(db.x==A.DEFAULT_X and db.y==A.DEFAULT_Y)

-- 5) Mouse drag: grid snap, Shift bypass, centre snap, screen clamp, guides, undo on release.
local undoBefore=#e.undo
cursorX,cursorY,mouseDown=0,0,true
e.overlay.scripts.OnMouseDown(e.overlay,"LeftButton")
cursorX,cursorY=37,3;Advance(.01)
assert(db.x==32 and db.y==-147,"x snaps to the 32px grid, y is free: "..db.x..","..db.y)
assert(e.guides:IsShown())
shift=true;Advance(.01);shift=false;assert(db.x==37,"Shift bypasses snapping")
cursorX,cursorY=5,146;Advance(.01);assert(db.x==0 and db.y==0,"centre snap")
e.snap.center=false;Advance(.01);assert(db.x==0 and db.y==0,"grid line through the centre still snaps")
e.snap.enabled=false;Advance(.01);assert(db.x==5 and db.y==-4,"snap off");e.snap.enabled,e.snap.center=true,true
e.snap.grid=false;cursorX,cursorY=-1596,0;Advance(.01);assert(db.x==-1602,"left screen-edge snap (always on): "..db.x);e.snap.grid=true
cursorX=5000;Advance(.01);assert(db.x==(3440-236)/2,"clamped to the screen: "..db.x)
mouseDown=false;Advance(.01)
assert(not e.drag and not e.guides:IsShown() and #e.undo==undoBefore+1)
ctrl=true;key(e.remote,"Z");ctrl=false;assert(db.x==A.DEFAULT_X and db.y==A.DEFAULT_Y,"one undo per drag")

-- 6) Esc closes edit mode and reopens the settings window it came from; lock unchanged.
key(e.remote,"ESCAPE")
assert(not A.editing and not e.overlay:IsShown() and not e.hud:IsShown())
Advance(.3)
assert(not e.remote:IsShown() and o:IsShown() and db.locked==true)
assert(o.titleBar.editButton.label:GetText()=="편집 모드")

-- 7) Minimap right click / slash: no settings reopen when edit mode was not entered from it.
o:HideImmediately()
local obj=LibStub("LibDataBroker-1.1"):GetDataObjectByName("DDIngUI_APL")
obj.OnClick(nil,"RightButton");Advance(.3);assert(A.editing and e.remote:IsShown())
SlashCmdList.DDINGUI_APL("edit");Advance(.3)
assert(not A.editing and not e.remote:IsShown() and not o:IsShown())
SlashCmdList.DDINGUI_APL("edit");assert(A.editing);SlashCmdList.DDINGUI_APL("edit");Advance(.3);assert(not A.editing)
SlashCmdList.DDINGUI_APL("lock");assert(db.locked==false);SlashCmdList.DDINGUI_APL("lock");assert(db.locked==true)
-- Title-bar X goes through onDone.
obj.OnClick(nil,"RightButton");Advance(.3)
e.remote.titleBar.closeBtn.scripts.OnClick(e.remote.titleBar.closeBtn);assert(not A.editing)
Advance(.3)

-- 8) Combat: entry blocked, PLAYER_REGEN_DISABLED ends edit mode (mid-drag) without reopen.
combat=true;A:ToggleEditMode();assert(not A.editing,"no entry in combat");combat=false
A:OpenOptions();Advance(.3);assert(o:IsShown())
A:ToggleEditMode();Advance(.3);assert(A.editing and not o:IsShown())
cursorX,cursorY,mouseDown=0,0,true
e.overlay.scripts.OnMouseDown(e.overlay,"LeftButton")
cursorX,cursorY=80,0;Advance(.01);assert(db.x==80)
combat=true
A.events.scripts.OnEvent(A.events,"PLAYER_REGEN_DISABLED")
assert(not A.editing and not e.drag and not e.overlay.scripts.OnUpdate)
assert(not e.remote:IsShown() and not e.grid:IsShown() and not e.overlay:IsShown(),"combat exit is immediate")
assert(not o:IsShown(),"settings stay closed in combat")
cursorX=400;Advance(.01);assert(db.x==80,"no movement after combat start")
mouseDown=false;combat=false
A.events.scripts.OnEvent(A.events,"PLAYER_REGEN_ENABLED")
assert(not A.editing and not o:IsShown())

-- 9) Remote position: saved on drag stop into editRemotePos, validated on load.
A:ToggleEditMode();Advance(.3)
e.remote:ClearAllPoints();e.remote:SetPoint("TOPLEFT",UIParent,"TOPLEFT",40.4,-80.6)
e.remote.titleBar.scripts.OnDragStop(e.remote.titleBar)
assert(db.editRemotePos.point=="TOPLEFT" and db.editRemotePos.x==40 and db.editRemotePos.y==-81 and db.editRemotePos[1]==nil,"series named-key format")
A:StopEditMode(true)
local saved=A.edit
A.edit=nil;local fresh=A:CreateEditMode()
assert(fresh.remote.point[1]=="TOPLEFT" and fresh.remote.point[4]==40 and fresh.remote.point[5]==-81)
db.editRemotePos={point="BAD",x=1,y=2};A.edit=nil;fresh=A:CreateEditMode()
assert(fresh.remote.point[1]=="TOP" and fresh.remote.point[4]==0 and fresh.remote.point[5]==-55,"invalid saved point falls back")
db.editRemotePos={point="TOP",x=SECRET,y=2};A.edit=nil;fresh=A:CreateEditMode()
assert(fresh.remote.point[5]==-55,"secret saved offset falls back")
A.edit=saved

-- Title-bar label follows entry/exit even while the settings window stays open.
A:OpenOptions();Advance(.3);assert(o:IsShown())
obj.OnClick(nil,"RightButton");assert(A.editing and o.titleBar.editButton.label:GetText()=="편집 중")
A:OpenOptions();Advance(.3);assert(o:IsShown() and o.titleBar.editButton.label:GetText()=="편집 중")
o.titleBar.editButton.scripts.OnClick(o.titleBar.editButton)
assert(not A.editing and o:IsShown() and o.titleBar.editButton.label:GetText()=="편집 모드")
o:HideImmediately()
-- No edit button left on the general page (the lock button stays).
local lockFound=false
walk(o.body,function(x) local t=x.kind=="FontString" and x.text
    assert(t~="편집 모드" and t~="편집 중","edit button must live only in the title bar")
    if t=="위치 잠김" or t=="드래그 가능" then lockFound=true end end)
assert(lockFound,"lock button stays on the general page")
-- 10) Display disabled: mover shows the grey badge; DB keys untouched apart from editRemotePos.
db.enabled=false;A:ToggleEditMode();Advance(.3)
assert(e.mover.disabled and e.mover.badge:IsShown())
A:ToggleEditMode();db.enabled=true
local allowed={profiles=1,mode=1,targets=1,scale=1,enabled=1,locked=1,x=1,y=1,minimap=1,guiScale=1,editRemotePos=1,auraSpellID=1}
for k in pairs(db) do assert(allowed[k],"unexpected DB key "..tostring(k)) end
""")
print("PASS: APL C12 edit mode — entry/exit, Esc, nudge/undo/XY save with scale conversion, drag snap/clamp, "
      "minimap right click + /ddapl edit, combat block + REGEN auto-exit, remote position save/validate.")
