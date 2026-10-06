-- Frame geometry mock adapted from PongPongAura/tests/test_pongpong.py.

P = {}; objects = {}; timers = {}; sounds = {}; units = {}; now = 10; combat = false
UISpecialFrames = {}; SlashCmdList = {}; tinsert = table.insert; tremove = table.remove
strmatch = string.match
SECRET = {}; function issecretvalue(v) return rawequal(v, SECRET) end
function GetTime() return now end
function InCombatLockdown() return combat end
function GetLocale() return "koKR" end
function GetNormalizedRealmName() return "아즈샤라" end
function GetRealmName() return "아즈샤라" end
function UnitFullName(u) if units[u] then return units[u].name, units[u].realm end end
function UnitClass(u) if units[u] then return 'Class', units[u].class end end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitLevel(u) return units[u] and units[u].level end
function UnitCastingInfo(u) local v=units[u] or {}; return nil,nil,nil,nil,nil,false,nil,nil,v.spell,v.bar end
function UnitChannelInfo(u) local v=units[u] or {}; return nil,nil,nil,nil,nil,false,nil,v.channel,false,0,v.channelBar end
function UnitPosition(u) return nil,nil,nil,nil end
C_NamePlate={GetNamePlates=function() return plates or {} end,GetNamePlateForUnit=function(unit)
    for _,p in pairs(plates or {}) do if p.unitToken==unit then return p end end
end}
function UnitIsConnected(u) return units[u] and units[u].connected ~= false end
function UnitGroupRolesAssigned(u) return units[u] and units[u].role or "NONE" end
raid = true; groupSize = 20
function IsInRaid() return raid end
function IsInGroup() return groupSize > 1 end
function GetNumGroupMembers() return groupSize end
function GetNumSubgroupMembers() return groupSize-1 end
function GetRaidRosterInfo(i) return units['raid'..i].name, 0, math.ceil(i/5) end
function GetCursorPosition() return 600, 500 end
function CreateColor(...) return {...} end
function PlaySound(id, channel) sounds[#sounds+1]={id,channel}; return true,#sounds end
function PlaySoundFile(path, channel) sounds[#sounds+1]={path,channel}; return true,#sounds end
function StopSound(handle) end
C_Timer = {NewTimer=function(delay, callback)
    local t = {callback=callback, delay=delay, Cancel=function(self) self.cancelled=true end}
    timers[#timers+1]=t; return t
end}
function ExpireTimers() local pending=timers; timers={} for _,t in ipairs(pending) do if not t.cancelled then t.callback() end end end
methods = {}
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k,v) local old=self.scripts[k]; self.scripts[k]=function(...) if old then old(...) end v(...) end end
function methods:Fire(k,...) if self.scripts[k] then self.scripts[k](self,...) end end
function methods:RegisterEvent(e) self.events[e]=true end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if type(relative)=='number' then x,y,relative,relativePoint=relative,relativePoint,self.parent,point
    elseif relative==nil then relative,relativePoint,x,y=self.parent,point,0,0
    elseif type(relativePoint)=='number' then x,y,relativePoint=relativePoint,x,point end
    self.points[point]={relative or UIParent,relativePoint or point,x or 0,y or 0}
end
function methods:ClearAllPoints() self.points={} end
function methods:SetAllPoints(p) p=p or self.parent; self:ClearAllPoints(); self:SetPoint('TOPLEFT',p,'TOPLEFT',0,0); self:SetPoint('BOTTOMRIGHT',p,'BOTTOMRIGHT',0,0) end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:SetFont(path,size,flags) self.fontPath,self.fontSize,self.fontFlags=path,size,flags; return true end
function methods:SetText(s) self.text=s or ''; self:Fire('OnTextChanged',false) end
function methods:GetText() return self.text or '' end
function methods:SetTextColor(...) self.textColor={...} end
function methods:SetJustifyH(v) self.justify=v end
function methods:SetBackdrop(v) self.backdrop=v end
function methods:SetBackdropColor(...) self.background={...} end
function methods:SetBackdropBorderColor(...) self.border={...} end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetGradient(direction, first, last) self.gradient={direction,first,last} end
function methods:SetAlpha(v) self.alpha=v end
function methods:GetAlpha() return self.alpha or 1 end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:Show() local was=self.shown; self.shown=true; if not was then self:Fire('OnShow') end end
function methods:Hide() local was=self.shown; self.shown=false; if was then self:Fire('OnHide') end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetEnabled(v) self.enabled=v end
function methods:IsEnabled() return self.enabled end
function methods:SetFrameStrata(v) self.strata=v end
function methods:SetFrameLevel(v) self.level=v end
function methods:GetFrameLevel() return self.level or 1 end
function methods:GetEffectiveScale() return 1 end
function methods:GetScale() return 1 end
function methods:IsMouseOver() return mouseOver==self end
function methods:EnableMouse(v) self.mouse=v end
function methods:StartMoving() self.moving=true end
function methods:StopMovingOrSizing() self.moving=false end
function methods:SetVerticalScroll(v) self.scroll=v end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:SetScrollChild(child) child:SetPoint('TOPLEFT',self,'TOPLEFT',0,0); self.scrollChild=child end
function methods:GetParent() return self.parent end
function methods:SetTexture(v) self.texture=v end
local create
function methods:CreateTexture(name,layer) local o=create('Texture',name,self); o.layer=layer; return o end
function methods:CreateFontString(name,layer) local o=create('FontString',name,self); o.layer=layer; return o end
function methods:SetNormalTexture(v) self.normal=self:CreateTexture(); self.normal:SetTexture(v) end
function methods:GetNormalTexture() return self.normal end
for _,key in ipairs({'SetShadowOffset','SetShadowColor','SetWordWrap','SetMovable','SetClampedToScreen','RegisterForDrag','RegisterForClicks','SetAutoFocus','ClearFocus','EnableMouseWheel','SetVertexColor','SetGradientAlpha','SetTexCoord','SetNonSpaceWrap','SetScale','SetSnapToPixelGrid','SetTexelSnappingBias'}) do methods[key]=function() end end
local factors={TOPLEFT={0,1},TOP={.5,1},TOPRIGHT={1,1},LEFT={0,.5},CENTER={.5,.5},RIGHT={1,.5},BOTTOMLEFT={0,0},BOTTOM={.5,0},BOTTOMRIGHT={1,0}}
function methods:Rect()
    if self==UIParent then return 0,0,1280,900 end
    local width=self.width or (self.text and Measure(self.text,self.fontSize or 12)) or 0
    local height=self.height or (self.text and (self.fontSize or 12)*1.2) or 0
    local ax,ay={},{ }
    for point,a in pairs(self.points) do
        local rx,ry,rw,rh=a[1]:Rect(); local f=factors[a[2]]; local own=factors[point]
        ax[#ax+1]={own[1],rx+rw*f[1]+a[3]}; ay[#ay+1]={own[2],ry+rh*f[2]+a[4]}
    end
    local function Solve(points,size)
        for i=1,#points do for j=i+1,#points do if points[i][1]~=points[j][1] then
            size=(points[i][2]-points[j][2])/(points[i][1]-points[j][1]); return points[i][2]-points[i][1]*size,size
        end end end
        if #points>0 then return points[1][2]-points[1][1]*size,size end
        return 0,size
    end
    local x,y; x,width=Solve(ax,width); y,height=Solve(ay,height)
    if self.parent and self.parent.scrollChild==self then y=y+(self.parent.scroll or 0) end
    return x,y,width,height
end
function methods:GetWidth() local _,_,w=self:Rect(); return w end
function methods:GetHeight() local _,_,_,h=self:Rect(); return h end
function methods:GetCenter() local x,y,w,h=self:Rect(); return x+w/2,y+h/2 end
create=function(kind,name,parent)
    local o=setmetatable({kind=kind,name=name,parent=parent,points={},scripts={},events={},shown=true,enabled=true,sequence=#objects+1}, {__index=methods})
    objects[#objects+1]=o; if name then _G[name]=o end; return o
end
CreateFrame=create; UIParent=create('Frame','UIParent'); GameTooltip={SetOwner=function()end,SetText=function()end,AddLine=function()end,Show=function()end,Hide=function()end}
