"""Run the actual Lua 5.1 dashboard and preview code against read-only UI doubles."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent

STUBS = r"""
SECRET = setmetatable({}, {__add=function() error("secret arithmetic") end})
function issecretvalue(value) return rawequal(value, SECRET) end
function LibStub() return nil end
function UnitClass() return "Monk", "MONK" end
function UnitPowerType() return 0 end
function GetCursorPosition() return 0, 0 end
clockTime=0
function GetTime() return clockTime end
function IsMouseButtonDown() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function CreateColor(...) return {...} end
RAID_CLASS_COLORS = {MONK={r=0, g=1, b=0.6}}
C_Timer = {After=function(_, fn) fn() end, NewTimer=function(_, fn)
    return {Cancel=function() end}
end}

local Frame = {}
Frame.__index = Frame
created = 0
function CreateFrame(kind, name, parent)
    created = created + 1
    local f = setmetatable({kind=kind, name=name, parent=parent, children={}, regions={},
        width=100, height=30, shown=true, level=1, alpha=1, scale=1, scripts={}}, Frame)
    if parent then parent.children[#parent.children+1] = f end
    return f
end
function Frame:CreateTexture()
    local r = CreateFrame("Texture", nil, nil)
    r.parent = self; self.regions[#self.regions+1] = r
    return r
end
function Frame:CreateMaskTexture() local t=self:CreateTexture(); t.kind="MaskTexture"; return t end
function Frame:CreateFontString() local t=self:CreateTexture(); t.kind="FontString"; return t end
function Frame:IsForbidden() return self.forbidden or false end
function Frame:GetObjectType() return self.kind end
function Frame:GetParent() return self.parent end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetRegions() return unpack(self.regions) end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:GetAlpha() return self.alpha end
function Frame:GetScale() return self.scale end
function Frame:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Frame:GetEffectiveAlpha() return self.alpha * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
function Frame:GetFrameLevel() return self.level end
function Frame:GetWidth() return self.allPoints and self.allPoints:GetWidth() or self.width end
function Frame:GetHeight() return self.allPoints and self.allPoints:GetHeight() or self.height end
function Frame:GetRect(...)
    assert(select("#", ...)==0, "unexpected widget arguments")
    if self.rect then return unpack(self.rect) end
    if self.allPoints then return self.allPoints:GetRect() end
    local x,y = 0,0
    if self.point and self.point[2] then x,y=self.point[2]:GetRect() end
    return x+(self.point and self.point[4] or 0), y+(self.point and self.point[5] or 0), self.width,self.height
end
function Frame:GetFont() return self.font, self.fontSize, self.flags end
function Frame:GetText() return self.text end
function Frame:GetTextColor() return unpack(self.textColor or {1,1,1,1}) end
function Frame:GetTexture() return self.texture end
function Frame:GetAtlas() return self.atlas end
function Frame:GetTexCoord() return unpack(self.texCoord or {0,1,0,1}) end
function Frame:GetVertexColor() return unpack(self.vertexColor or {1,1,1,1}) end
function Frame:IsDesaturated() return self.desaturated or false end
function Frame:GetDesaturation() return self.desaturation or (self.desaturated and 1 or 0) end
function Frame:GetBlendMode() return "BLEND" end
function Frame:GetDrawLayer() return self.layer or "ARTWORK", self.sublevel or 0 end
function Frame:GetJustifyH() return "CENTER" end
function Frame:GetJustifyV() return "MIDDLE" end
function Frame:GetNumMaskTextures() return #(self.masks or {}) end
function Frame:GetMaskTexture(i) return self.masks[i] end
function Frame:GetStatusBarTexture() return self.fill end
function Frame:GetMinMaxValues() return self.minimum or 0, self.maximum or 100 end
function Frame:GetValue() return self.value or 0 end
function Frame:GetStatusBarColor() return unpack(self.barColor or {1,1,1,1}) end
function Frame:GetOrientation() return "HORIZONTAL" end
function Frame:GetReverseFill() return false end
function Frame:GetCooldownTimes() return self.start, self.duration end
function Frame:GetDrawSwipe() return self.drawSwipe ~= false end
function Frame:GetDrawEdge() return false end
function Frame:GetReverse() return self.reverse or false end
function Frame:GetRotation() return 0 end

local function setter(name, fn)
    Frame[name] = function(self, ...)
        assert(not self.readOnly, "source mutated: "..name)
        return fn(self, ...)
    end
end
setter("SetSize", function(s,w,h) assert(type(w)=="number" and type(h)=="number"); s.width=w; s.height=h end)
setter("SetWidth", function(s,w) s.width=w end)
setter("SetHeight", function(s,h) s.height=h end)
setter("SetPoint", function(s,...) s.point={...} end)
setter("SetAllPoints", function(s,r) s.allPoints=r or s.parent end)
setter("ClearAllPoints", function(s) s.point=nil; s.allPoints=nil end)
setter("SetFrameLevel", function(s,v) s.level=v end)
setter("SetScale", function(s,v) s.scale=v end)
setter("SetAlpha", function(s,v) s.alpha=v end)
setter("SetParent", function(s,p) s.parent=p end)
setter("SetScript", function(s,k,v) s.scripts[k]=v end)
setter("HookScript", function(s,k,v)
    local prev=s.scripts[k]; s.scripts[k]=function(...) if prev then prev(...) end; v(...) end
end)
setter("Show", function(s) s.shown=true end)
setter("Hide", function(s) s.shown=false end)
setter("SetShown", function(s,b) s.shown=b end)
setter("SetFont", function(s,f,z,flags)
    if not f or z<=0 then return false end
    s.font=f; s.fontSize=z; s.flags=flags; return true
end)
setter("SetText", function(s,t) assert(s.font, "Font not set"); s.text=t end)
setter("SetFormattedText", function(s,fmt,...) s:SetText(string.format(fmt,...)) end)
setter("SetTextColor", function(s,...) s.textColor={...} end)
setter("SetTexture", function(s,t) s.texture=t; s.atlas=nil end)
setter("SetAtlas", function(s,t) s.atlas=t end)
setter("SetTexCoord", function(s,...) s.texCoord={...} end)
setter("SetVertexColor", function(s,...) s.vertexColor={...} end)
setter("SetDesaturated", function(s,b)
    s.desaturated=b; s.desaturation=issecretvalue(b) and b or (b and 1 or 0)
end)
setter("SetDesaturation", function(s,v) s.desaturation=v end)
setter("SetDrawLayer", function(s,l,z) assert(z>=-8 and z<=7); s.layer=l; s.sublevel=z end)
setter("SetColorTexture", function(s,...) s.texture="solid"; s.vertexColor={...} end)
setter("SetDrawSwipe", function(s,b) s.drawSwipe=b end)
setter("SetReverse", function(s,b) s.reverse=b end)
setter("SetCooldown", function(s,a,b) assert(type(a)=="number" and type(b)=="number"); s.start=a; s.duration=b end)
setter("SetSwipeColor", function(s,...) s.swipeColor={...} end)
setter("SetMinMaxValues", function(s,a,b) s.minimum=a; s.maximum=b end)
setter("SetValue", function(s,v) s.value=v end)
setter("SetStatusBarTexture", function(s,t)
    s.fill=s.fill or s:CreateTexture(); s.fill:SetTexture(t)
end)
setter("SetStatusBarColor", function(s,...) s.barColor={...} end)
setter("SetGradient", function(s,...) s.gradient={...} end)
setter("AddMaskTexture", function(s,m) s.masks=s.masks or {}; s.masks[#s.masks+1]=m end)
setter("RemoveMaskTexture", function(s,m)
    for i,v in ipairs(s.masks or {}) do if v==m then table.remove(s.masks,i); break end end
end)
for _, method in ipairs({"SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
    "EnableMouse", "EnableMouseWheel", "SetFrameStrata", "SetClipsChildren", "SetHitRectInsets",
    "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetBlendMode", "SetRotation",
    "SetDrawBling", "SetHideCountdownNumbers", "SetDrawEdge",
    "SetOrientation", "SetReverseFill"}) do
    setter(method, function() end)
end
UIParent=CreateFrame("Frame")
UIParent.rect={0,0,3440,1440}
GameTooltip={SetOwner=function()end, SetText=function()end, AddLine=function()end,
    AddDoubleLine=function()end, Show=function()end, Hide=function()end}
local colors=setmetatable({}, {__index=function(t,k) local c={0.2,0.3,0.4,1}; rawset(t,k,c); return c end})
addon={GUI={}, GUIBase={L={}, FLAT="flat", THEME=colors}, db={profile={},
    GetCurrentProfile=function()return"AD"end}}
function addon.GUI.CreateStyledButton(parent, text, width, height)
    local f=CreateFrame("Button",nil,parent); f:SetSize(width,height); return f
end
function runtime(rect, texture, parent)
    local f=CreateFrame("Frame",nil,parent or UIParent); f.rect=rect
    if texture then f.Icon=f:CreateTexture(); f.Icon:SetAllPoints(f); f.Icon:SetTexture(texture) end
    return f
end
function freeze(f)
    f.readOnly=true
    for _,r in ipairs(f.regions) do r.readOnly=true end
    for _,c in ipairs(f.children) do freeze(c) end
end
function near(a,b) assert(math.abs(a-b)<0.00001, tostring(a).." ~= "..tostring(b)) end
"""

CHECKS = r"""
local preview = addon.GUI.DashboardPreview
local a = runtime({100,200,40,20},101)
local b = runtime({144,200,40,20},102)
a.Icon:SetTexCoord(0.08,0.92,0.29,0.71)
a.Icon:SetVertexColor(0.6,0.7,0.8,1)
a.Icon:SetDesaturated(true)
local count=a:CreateFontString()
count:SetAllPoints(a); count:SetFont("font.ttf",12,"OUTLINE"); count:SetText("3")
local cooldown=CreateFrame("Cooldown",nil,a)
cooldown:SetAllPoints(a); cooldown.start=1000; cooldown.duration=5000; cooldown.reverse=true
addon.IconViewers={_cdData={[cooldown]={previewSwipeColor={0.9,0.5,0.2,0.7}}}}
local group=runtime({100,200,84,20})
group._managedIcons={a,b}; group._iconCount=2
addon.GroupRenderer={groupFrames={Cooldowns=group},
    IsManagedIconInLayout=function(_,f)return not f.filtered end}
addon.db.profile={groupSystem={groups={
    Cooldowns={iconOrder={"cdm:Merithra", "dynid:slot:13"}, rowLimit=0, aspectRatioCrop=2},
    Utility={}, Empty={}}},
    powerBar={enabled=false}, secondaryPowerBar={enabled=false}, castBar={enabled=false}}
local descriptors=api.build()
assert(#descriptors==2 and #descriptors[1].sources==2)
assert(descriptors[1].sources[1]==a, "identity must come from the runtime frame")
assert(#descriptors[2].sources==0, "empty group must not invent icons")
a.filtered=true
assert(#api.build()[1].sources==1)
a.filtered=nil
for i=3,30 do group._managedIcons[i]=runtime({100+(i-1)*44,200,40,20},100+i) end
group._iconCount=30
assert(#api.build()[1].sources==30, "24-icon truncation returned")
group._iconCount=2

local bars,icons,texts={},{},{}
local tracked={
    {uid="bar", displayType="bar", settings={}}, {uid="ring", displayType="ring", settings={}},
    {uid="icon", displayType="icon", settings={}}, {uid="text", displayType="text", settings={}},
    {uid="sound", displayType="sound"}, {isGroup=true}, {uid="disabled", displayType="bar",disabled=true}}
bars[1]=runtime({100,160,180,12},201); bars[2]=runtime({290,150,32,32},202)
icons[3]=runtime({330,150,32,32},203); texts[4]=runtime({370,150,80,16},204)
bars[7]=runtime({900,900,100,20},207)
addon.GetTrackedBuffConfigs=function()return tracked end
addon.GetTrackedBuffBars=function()return bars end
addon.GetTrackedBuffIcons=function()return icons end
addon.GetTrackedBuffTexts=function()return texts end
addon.GetTrackedBuffGroups=function()error("stale group cache must not be used")end
local ds=api.build()
assert(#ds==6)
assert(ds[3].frame==bars[1] and ds[4].frame==bars[2] and ds[5].frame==icons[3] and ds[6].frame==texts[4])
tracked[1].displayType="icon"; icons[1]=icons[3]
assert(api.build()[3].frame==icons[1], "display type must refresh immediately")
tracked[1].displayType="bar"
addon.GetTrackedBuffConfigs=function()return{}end

-- Fit the content, using one scale on ultrawide and portrait canvases.
for _,size in ipairs({{800,450},{700,700},{500,900}}) do
    local v=api.viewport({{left=900,bottom=400,width=400,height=100}},preview.Rect(UIParent),size[1],size[2])
    near(size[1]/v.width,size[2]/v.height)
    near(v.left+v.width/2,1100); near(v.bottom+v.height/2,450)
    assert(400*v.scale<=size[1] and 100*v.scale<=size[2])
end
local scaled=runtime({10,20,40,20},301)
scaled.scale=2
local r=preview.Rect(scaled); near(r.left,20); near(r.width,80)

-- Actual textures, crop, desaturation, text, and timing; originals reject every setter.
freeze(a); freeze(b)
local host=CreateFrame("Frame",nil,UIParent)
local rect={left=100,bottom=200,width=84,height=20}
local painted,partial=preview.Paint(host,{a,b},rect,2)
assert(painted==4 and not partial)
local texture=host._previewPool.Texture[1].visual
assert(texture.texture==101 and texture.desaturation==1)
near(texture.texCoord[3],0.29); near(texture.vertexColor[1],0.6)
near(host._previewPool.Texture[1].width,80); near(host._previewPool.Texture[1].height,40)
assert(host._previewPool.FontString[1].visual.text=="3")
near(host._previewPool.FontString[1].visual.fontSize,24)
assert(host._previewPool.Cooldown[1].start==1 and host._previewPool.Cooldown[1].duration==5)
assert(host._previewPool.Cooldown[1].reverse)
near(host._previewPool.Cooldown[1].swipeColor[1],0.9)
local allocations=created
for i=1,20 do preview.Paint(host,{a,b},rect,2) end
assert(created==allocations, "refresh allocated new frames")
-- Inner geometry changes even though the group's outside bounds do not.
a.rect={100,200,32,20}; b.rect={136,200,48,20}
preview.Paint(host,{a,b},rect,2)
near(host._previewPool.Texture[1].width,64); near(host._previewPool.Texture[2].point[4],72)
a.Icon.texCoord={0.1,0.9,0.25,0.75}; count.text="8"
preview.Paint(host,{a,b},rect,2)
near(texture.texCoord[3],0.25); assert(host._previewPool.FontString[1].visual.text=="8")

-- Secret values and forbidden descendants are omitted, never compared or guessed.
cooldown.start=SECRET
a.Icon.GetTexture=function()return SECRET end
painted,partial=preview.Paint(host,{a,b},rect,2)
assert(partial and not host._previewPool.Texture[1].shown and not host._previewPool.Cooldown[1].shown)
local forbidden=runtime({10,10,30,30},999)
forbidden.forbidden=true
forbidden.GetRect=function()error("forbidden getter called")end
forbidden.GetChildren=forbidden.GetRect
forbidden.GetRegions=forbidden.GetRect
assert(preview.Rect(forbidden)==nil)
painted,partial=preview.Paint(host,{forbidden},rect,2)
assert(painted==0 and partial)
assert(not host._previewPool.FontString[1].shown, "stale text remained visible")
a.Icon.GetTexture=nil; cooldown.start=1000

-- Native CDM textures can expose numeric desaturation but deny the boolean accessor.
-- The old mirror dropped every native icon while the custom icon and group bounds survived.
local nativeSources, booleanReads = {}, 0
for index=1,18 do
    local icon=runtime({100+(index-1)%9*40,200-math.floor((index-1)/9)*20,40,20},700+index)
    icon.Icon.IsDesaturated=function() booleanReads=booleanReads+1; error("desaturation access denied") end
    icon.Icon.GetDesaturation=function() return SECRET end
    freeze(icon)
    nativeSources[index]=icon
end
nativeSources[19]=runtime({260,160,40,20},719)
freeze(nativeSources[19])
local nativeHost=CreateFrame("Frame",nil,UIParent)
local nativeBounds={left=100,bottom=160,width=360,height=60}
painted,partial=preview.Paint(nativeHost,nativeSources,nativeBounds,2)
assert(painted==19 and not partial, "native CDM icons vanished when desaturation was protected: "..painted.."/19")
assert(booleanReads==0, "restricted boolean accessor used instead of numeric desaturation")
for index=1,18 do
    local cell=nativeHost._previewPool.Texture[index]
    assert(cell.shown and cell.visual.texture==700+index and rawequal(cell.visual.desaturation,SECRET))
end

-- Only allowed display setters receive secret values; coordinates and hierarchy stay public.
local native=nativeSources[1]
native.Icon.GetEffectiveAlpha=function() return SECRET end
native.Icon.GetAlpha=native.Icon.GetEffectiveAlpha
native.Icon.GetVertexColor=function() return SECRET,0.7,0.8,1 end
native.Icon.GetTexCoord=function() return SECRET,0,0,1,1,0,1,1 end
local nativeText=native:CreateFontString()
nativeText:SetAllPoints(native); nativeText:SetFont("font.ttf",12,"OUTLINE")
nativeText.text=SECRET; nativeText.textColor={SECRET,1,1,1}
freeze(native)
painted,partial=preview.Paint(nativeHost,{native},nativeBounds,2)
local nativeCell=nativeHost._previewPool.Texture[1]
assert(painted==2 and not partial, "permitted secret display values were dropped")
assert(rawequal(nativeCell.alpha,SECRET) and rawequal(nativeCell.visual.vertexColor[1],SECRET))
assert(rawequal(nativeCell.visual.texCoord[1],SECRET))
assert(rawequal(nativeHost._previewPool.FontString[1].visual.text,SECRET))
assert(rawequal(nativeHost._previewPool.FontString[1].visual.textColor[1],SECRET))
assert(preview.Read(native.Icon,"GetAlpha")==nil, "public read boundary exposed a secret")
-- Reused cells must replace secret state with the next source's actual public state.
native.Icon.GetDesaturation=function() return 0.35 end
native.Icon.GetEffectiveAlpha=false -- Regions can provide only GetAlpha.
native.Icon.GetAlpha=function() return 0.6 end
native.Icon.GetVertexColor=nil; native.Icon.GetTexCoord=nil
nativeText.text="4"; nativeText.textColor=nil
preview.Paint(nativeHost,{native},nativeBounds,2)
near(nativeCell.visual.desaturation,0.35); near(nativeCell.alpha,0.6)
near(nativeCell.visual.vertexColor[1],1); near(nativeCell.visual.texCoord[1],0)
assert(nativeHost._previewPool.FontString[1].visual.text=="4")
native.Icon.GetRect=function() return SECRET,200,40,20 end
assert(preview.Rect(native.Icon)==nil)
painted,partial=preview.Paint(nativeHost,{native},nativeBounds,2)
assert(partial and not nativeCell.shown, "secret geometry reached layout arithmetic")
native.Icon.GetRect=nil
native.Icon.GetVertexColor=function() error("getter unavailable") end
painted,partial=preview.Paint(nativeHost,{native},nativeBounds,2)
assert(partial and not nativeCell.shown, "failed native copy left a stale icon visible")
native.Icon.GetVertexColor=nil
preview.Paint(nativeHost,{native},nativeBounds,2)
assert(nativeCell.shown, "icon did not recover after getter became accessible")

-- Bars keep the actual fill length, color and border/segment regions, not a 72% sample.
local bar=runtime({100,100,180,12})
local status=CreateFrame("StatusBar",nil,bar)
status:SetAllPoints(bar)
status.fill=status:CreateTexture()
status.fill.rect={100,100,37,12}; status.fill:SetTexture("bar.tga")
status.fill:SetVertexColor(0,0.9,0.4,1)
status.value=37; status.maximum=180; status.barColor={0,0.9,0.4,1}
local border=bar:CreateTexture()
border.rect={99,99,182,1}; border:SetTexture("border.tga")
local barHost=CreateFrame("Frame",nil,UIParent)
freeze(bar)
preview.Paint(barHost,{bar},preview.Rect(bar),2,{1,0,0,1})
local foundFill,foundBorder
for _,cell in ipairs(barHost._previewPool.Texture) do
    if cell.visual.texture=="border.tga" then foundBorder=true; near(cell.height,2) end
end
local mirrored=barHost._previewPool.StatusBar[1]
foundFill=mirrored.shown and mirrored.fill.texture=="bar.tga"
near(mirrored.width,360); near(mirrored.maximum,180); near(mirrored.value,37)
near(mirrored.barColor[2],0.9)
assert(foundFill and foundBorder)
-- Engine-owned fills need not be returned by GetRegions().
status.regions={}
preview.Paint(barHost,{bar},preview.Rect(bar),2)
assert(barHost._previewPool.StatusBar and barHost._previewPool.StatusBar[1].shown,
    "native StatusBar fill disappeared when GetRegions omitted it")
near(barHost._previewPool.StatusBar[1].value,37)
status.value=SECRET; status.maximum=SECRET
local _,restricted=preview.Paint(barHost,{bar},preview.Rect(bar),2)
assert(not restricted and rawequal(mirrored.value,SECRET) and rawequal(mirrored.maximum,SECRET),
    "secret bar values must pass straight to allowed native setters")
status.value=37; status.maximum=180
local gradient={0.1,0.2,0.3,1,gradientMode="GRADIENT",gradientColor={0.7,0.8,0.9,1}}
status._ddingBarGradientActive=true
preview.Paint(barHost,{bar},preview.Rect(bar),2,gradient)
assert(mirrored._ddingBarGradientActive and mirrored.fill.gradient)
near(mirrored.fill.gradient[3][1],0.7)
status._ddingBarGradientActive=nil; status.barColor={SECRET,0.9,0.4,1}
preview.Paint(barHost,{bar},preview.Rect(bar),2)
assert(not mirrored._ddingBarGradientActive and rawequal(mirrored.barColor[1],SECRET),
    "reused gradient bar lost the native secret color")
near(mirrored.fill.gradient[2][1],1)
status.barColor={0,0.9,0.4,1}
status.fill.rect[3]=0
local _,limited=preview.Paint(barHost,{bar},preview.Rect(bar),2)
-- A zero-width fill is empty, not restricted data.
status.fill.width=0
_,limited=preview.Paint(barHost,{bar},preview.Rect(bar),2)
assert(not limited)

-- Mask pools remove previously attached masks when the next source is unmasked.
local masked=runtime({100,100,40,40},401)
local mask=masked:CreateMaskTexture()
mask:SetAllPoints(masked); mask:SetTexture("ring.tga")
masked.Icon:AddMaskTexture(mask)
preview.Paint(host,{masked},preview.Rect(masked),1)
assert(#host._previewPool.Texture[1].visual.masks==1)
masked.Icon:RemoveMaskTexture(mask)
preview.Paint(host,{masked},preview.Rect(masked),1)
assert(#host._previewPool.Texture[1].visual.masks==0)

-- Construct the real workspace: nil helpers and widget misuse must fail here.
local parent=CreateFrame("Frame",nil,UIParent)
parent.contentArea=CreateFrame("Frame",nil,parent)
parent.scrollFrame=CreateFrame("Frame",nil,parent)
function parent:NavigateToSection(target) self.destination=target end
-- Idle buffs and hidden resource/cast bars still belong to the configured layout.
local buff=runtime({100,250,40,20},601); buff:Hide(); buff.filtered=true
local buffs=runtime({100,250,400,20})
buffs._managedIcons={buff}; buffs._iconCount=1
addon.GroupRenderer.groupFrames.Buffs=buffs
addon.db.profile.groupSystem.groups.Buffs={iconSize=40, aspectRatioCrop=2, direction="CENTERED_HORIZONTAL"}
catalogRows={
    {isBuffSpell=true, spellName="buff:one", entry={icon=601,cooldownID=1}},
    {isBuffSpell=true, spellName="buff:two", entry={icon=602,cooldownID=2}},
    {isBuffSpell=false, spellName="unrelated", entry={icon=999,cooldownID=3}},
    {isBuffSpell=true, spellName="stale", entry=nil},
}
addon.powerBar=bar; bar.shown=false
addon.secondaryPowerBar=runtime({100,180,180,6}); addon.secondaryPowerBar:Hide()
addon.castBar=runtime({100,80,180,12}); addon.castBar:Hide()
addon.db.profile.powerBar={enabled=true,height=90,color={1,0,0,1},texture="power.tga"}
addon.db.profile.secondaryPowerBar={enabled=true, texture="secondary.tga"}
addon.db.profile.castBar={enabled=true, useClassColor=true, texture="cast.tga"}
freeze(addon.secondaryPowerBar); freeze(addon.castBar); freeze(buffs); freeze(buff)
api.create(CreateFrame("Frame",nil,parent),parent)
local w=parent.contentArea._sectionWorkspace
w.stage:SetSize(800,450); w:RefreshCurrent()
local node=w.nodeByKey["group:Cooldowns"]
assert(node and node:IsShown())
local originalIcons,originalCount=group._managedIcons,group._iconCount
group._managedIcons=nativeSources; group._iconCount=#nativeSources
w:RefreshCurrent()
near(node._sourceRect.width,360); near(node._sourceRect.height,60)
for index=1,19 do
    local cell=node.visual._previewPool.Texture[index]
    assert(cell and cell.shown and cell.visual.texture==700+index,
        "dashboard collection or painting lost native icon "..index)
end
group._managedIcons=originalIcons; group._iconCount=originalCount
w:RefreshCurrent()
for _,key in ipairs({"group:Buffs","power","secondaryPower","cast"}) do
    local idle=w.nodeByKey[key]
    assert(idle and idle:IsShown() and idle._idle, key.." missing from idle dashboard")
end
local buffNode=w.nodeByKey["group:Buffs"]
assert(#buffNode.idleVisual.icons==2, "idle preview included unrelated or stale spells")
near(buffNode._sourceRect.height,20)
near(buffNode._sourceRect.bottom,250)
near(buffNode.idleVisual.icons[1].texCoord[3],0.29)
local powerNode=w.nodeByKey.power
near(powerNode._sourceRect.height,12) -- actual frame, not stale saved height=90
assert(not powerNode.idleVisual.bar.leftText:IsShown())
near(w.nodeByKey.cast.idleVisual.bar.barColor[2],1) -- current class color
addon.ResourceBars={GetSecondaryResource=function()return nil end}
w:RefreshCurrent()
assert(not w.nodeByKey.secondaryPower, "unavailable resource from the previous spec leaked into the layout")
addon.ResourceBars=nil
w:RefreshCurrent()
-- No spellcast yet: resolve the cast bar from its configured anchor without creating a live frame.
addon.castBar=nil
addon.db.profile.castBar.width=180; addon.db.profile.castBar.height=12
addon.db.profile.castBar.attachTo="anchor"; addon.db.profile.castBar.anchorPoint="TOPLEFT"
addon.db.profile.castBar.selfPoint="BOTTOMLEFT"; addon.db.profile.castBar.offsetY=8
addon.ResolveAnchorFrame=function()return group end
addon.GetTexture=function(_,name)return name end
w:RefreshCurrent()
near(w.nodeByKey.cast._sourceRect.left,100); near(w.nodeByKey.cast._sourceRect.bottom,228)
assert(addon.castBar==nil, "preview instantiated a runtime bar")
-- Active values replace the idle surface; removal/disabled settings remove its preview too.
bar.shown=true; buff.shown=true; buff.filtered=nil
w:RefreshCurrent()
assert(not powerNode._idle and not powerNode.idleVisual:IsShown())
assert(powerNode.visual._previewPool.StatusBar[1]:IsShown())
assert(not buffNode._idle and not buffNode.idleVisual:IsShown())
buff.shown=false; buff.filtered=true
w:RefreshCurrent()
assert(buffNode._idle and buffNode.idleVisual:IsShown())
catalogRows={}; clockTime=clockTime+1; w:RefreshCurrent()
assert(not buffNode:IsShown(), "empty assignment kept stale idle buff icons")
addon.db.profile.powerBar.enabled=false; addon.db.profile.secondaryPowerBar.enabled=false
addon.db.profile.castBar.enabled=false; w:RefreshCurrent()
assert(not w.nodeByKey.power and not powerNode:IsShown())
near(node._layoutWidth/node._layoutHeight,84/20)
assert(w.stage.selectionReadout:IsShown(), "selection guide disappeared")
near(w.stage.selectionCenter.point[4],node._stageX+node._layoutWidth/2)
local firstScale=w.viewRect.scale
group._managedIcons[3]=runtime({3000,1000,40,40},888)
group._managedIcons[3].filtered=true; group._iconCount=3
w:RefreshCurrent(); near(w.viewRect.scale,firstScale)
group._iconCount=2
local stable=created
for i=1,20 do w:RefreshCurrent() end
assert(created==stable and w.nodeByKey["group:Cooldowns"]==node, "keyed node reuse failed")
w._drag={x=0,y=0,panX=0,panY=0}
w.scripts.OnUpdate(w,0.3)
assert(w._drag==nil, "mouse release outside the canvas left panning active")
local previous=w.selectedKey
node.scripts.OnEnter(node)
assert(w.selectedKey==previous, "hover changed selection")
node.scripts.OnClick(node)
assert(parent.destination=="groupSystem.group_Cooldowns")
addon.db.profile.groupSystem.groups.Cooldowns.enabled=false
w:RefreshCurrent()
assert(not w.nodeByKey["group:Cooldowns"] and not node:IsShown())
addon.db.profile.groupSystem.groups.Cooldowns.enabled=true
w:RefreshCurrent()
assert(w.nodeByKey["group:Cooldowns"]==node, "retired node not reused")
local selectedIndex
parent.contentArea._btPanel={SelectTracker=function(_,i)selectedIndex=i end}
w:OpenDescriptor({target="buffTracker",trackerIndex=4})
assert(selectedIndex==4)
w:Release()
assert(w.scripts.OnUpdate==nil)
for _, pool in pairs(node.visual._previewPool) do
    for _,cell in ipairs(pool)do assert(not cell:IsShown())end
end
"""


def test_dashboard_workspace():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    ns = lua.table(Addon=lua.globals().addon)
    gradient_source = (ROOT / "DDingUI_StyleLib/Gradient.lua").read_text(encoding="utf-8")
    lua.execute("local Lib={}; _G.DDingUI_StyleLib=Lib; local function ReadColor" +
                gradient_source.split("local function ReadColor", 1)[1])
    group_source = (ROOT / "DDingUI_CDM_Option/GroupSystemOptions.lua").read_text(encoding="utf-8")
    assignment = group_source.split("local function GetUsableSpellAssignment", 1)[1].split("-- [12.0.1]", 1)[0]
    lua.execute('''
        local DDingUI=addon
        local dirty=0
        local function MarkSpecProfileDirty()dirty=dirty+1 end
        local function GetUsableSpellAssignment''' + assignment + '''
        local gs={groups={}, spellAssignments={stale="deleted"}}
        assert(GetUsableSpellAssignment(gs,"stale",nil,true)==nil)
        assert(gs.spellAssignments.stale=="deleted" and dirty==0, "preview mutated saved assignments")
        GetUsableSpellAssignment(gs,"stale")
        assert(gs.spellAssignments.stale==nil and dirty==1, "existing editor cleanup changed")
    ''')
    layout = group_source.split("local ASSIGNED_DIRECTION_RULES =", 1)[1]
    layout = "local ASSIGNED_DIRECTION_RULES =" + layout.split("local function AssignedGridSetEdges", 1)[0]
    lua.execute('''
        local DDingUI=addon
        local function GetGS()return addon.db.profile.groupSystem end
        local function CollectCDMRowsForGroup(_,_,_,trackedOnly,readOnly)
            assert(trackedOnly==false and readOnly==true)
            return catalogRows or {}
        end
        local function ResolveCDMEntryIconTexture(entry)return entry and entry.icon end
    ''' + layout)
    for name in ("DashboardPreview.lua", "SectionWorkspace.lua"):
        source = (ROOT / "DDingUI_CDM_Option" / name).read_text(encoding="utf-8")
        if name == "SectionWorkspace.lua":
            source += "\nreturn {create=CreateDashboardWorkspace, build=BuildDashboardDescriptors, viewport=DashboardViewportRect}"
            lua.globals().api = lua.execute(source, "DDingUI_CDM_Option", ns)
        else:
            lua.execute(source, "DDingUI_CDM_Option", ns)
    lua.execute(CHECKS)
    skinning = (ROOT / "DDingUI_CDM/Modules/IconViewers/IconSkinning.lua").read_text(encoding="utf-8")
    hook = skinning.split('hooksecurefunc(icon.Cooldown, "SetSwipeColor", function(self, r, g, b, a)', 1)[1]
    hook = hook.split("local s = cd.settings", 1)[0]
    lua.execute("local cdData = addon.IconViewers._cdData; captured = function(self,r,g,b,a) " + hook + " end")
    lua.execute('''
        local frame={}
        local data={bypassColorHook=true}
        addon.IconViewers._cdData[frame]=data
        captured(frame, 0.1, 0.2, 0.3, 0)
        assert(data.previewSwipeColor[4]==0, "nested transparent override was lost")
        local reused=data.previewSwipeColor
        captured(frame, 0.4, 0.5, 0.6, 1)
        assert(data.previewSwipeColor==reused, "color cache allocates on every setter")
        captured(frame, SECRET, 0, 0, 1)
        assert(data.previewSwipeColor==nil)
    ''')


if __name__ == "__main__":
    test_dashboard_workspace()
    print("dashboard Lua 5.1 runtime checks: OK")
