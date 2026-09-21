from pathlib import Path

from test_ready_check_assistant import panel_runtime

ROOT = Path(__file__).parents[1]


def recruitment_runtime(locale="koKR"):
    lua = panel_runtime(locale)
    lua.execute('''
        local methods = getmetatable(UIParent).__index
        local create = CreateFrame
        function CreateFrame(kind,name,parent,...)
            local f=create(kind,name,parent,...)
            if name then _G[name]=f end
            return f
        end
        function methods:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
        function methods:UnregisterEvent(event) if self.events then self.events[event]=nil end end
        function methods:HookScript(event,fn)
            local previous=self.scripts[event]
            self.scripts[event]=function(...) if previous then previous(...) end;fn(...) end
        end
        function methods:Show()
            local was=self.shown;self.shown=true
            if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function methods:Hide()
            local was=self.shown;self.shown=false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function methods:GetEffectiveScale() return self.scale or 1 end
        function methods:GetRight() return self.right or self.width end
        function methods:GetLeft() return self.left or 0 end
        function methods:GetPoint()
            for point, data in pairs(self.points) do return point,data.relative,data.anchor,data.x,data.y end
        end
        function methods:GetName() return self.name end
        function methods:GetOwner() return self.owner end
        function methods:SetOwner(owner) self.owner=owner;self.lines={} end
        function methods:AddLine(text,r,g,b,wrap)
            assert(wrap==nil or type(wrap)=="boolean")
            self.lines[#self.lines+1]={text=text,r=r,g=g,b=b}
        end
        function hooksecurefunc(target,method,fn)
            if type(target)=="string" then fn=method;method=target;target=_G end
            local previous=target[method]
            target[method]=function(...) previous(...);fn(...) end
        end
        function issecretvalue(value) return type(value)=="table" and rawget(value,"secret")==true end
        function issecrettable(value) return type(value)=="table" and rawget(value,"secretTable")==true end
        secret=setmetatable({secret=true},{__index=function() error("read secret") end})
        secretTable=setmetatable({secretTable=true},{__index=function() error("read secret table") end})
        timers={}
        C_Timer.After=function(_,fn) timers[#timers+1]=fn end
        function flush() local queued=timers;timers={};for _,fn in ipairs(queued) do fn() end end
        function fire(event,...)
            for _,f in ipairs(regions) do
                if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end
            end
        end
        local lib={}
        function lib.RegisterGroup(owner,fn) specCallback=fn end
        function lib.UnregisterGroup(owner) specCallback=nil end
        function LibStub(name) if name=="LibSpecialization" then return lib end end
        ns.modules={}
        SlashCmdList, UISpecialFrames = {}, {}
        function ns.DDingToolKit:RegisterModule(name,object) ns.modules[name]=object end
        PVEFrame=CreateFrame("Frame",nil,UIParent)
        PVEFrame:SetSize(640,500);PVEFrame.left=100;PVEFrame.right=740
        LFGListFrame=CreateFrame("Frame",nil,PVEFrame)
        LFGListFrame.ApplicationViewer=CreateFrame("Frame",nil,LFGListFrame)
        viewer=LFGListFrame.ApplicationViewer
        viewer:Hide()
        GameTooltip=CreateFrame("Frame",nil,UIParent);GameTooltip:SetFont("font",14,"")
        RAID_CLASS_COLORS={PRIEST={r=1,g=1,b=1},WARRIOR={r=.78,g=.61,b=.43}}
        C_Spell={GetSpellName=function(id) return nil end}
        listing={activityIDs={100}};category=3;leader=true;inRaid=true;roster={};inCombat=false
        C_LFGList={GetActiveEntryInfo=function() return listing end,
            GetActivityInfoTable=function(id) assert(id==100);return {categoryID=category} end}
        function IsInRaid() return inRaid end
        function IsInGroup() return #roster>1 end
        function UnitIsGroupLeader() return leader end
        function GetNumGroupMembers() return #roster end
        function GetNumSubgroupMembers() return math.max(0,#roster-1) end
        function data(unit)
            local index=unit=="player" and 1 or tonumber(unit:match("%d+"))
            if unit:find("party",1,true) then index=index+1 end
            return roster[index] or {}
        end
        function GetRaidRosterInfo(index)
            local m=roster[index]
            return m.name,0,m.subgroup or 1,90,m.class,m.class,"",true,false,nil,false,m.role
        end
        function UnitFullName(unit) local m=data(unit);return m.name,m.realm end
        function UnitClass(unit) return data(unit).class,data(unit).class end
        function UnitGroupRolesAssigned(unit) return data(unit).role or "NONE" end
        function UnitIsUnit(unit) return data(unit)==roster[1] end
        function GetNormalizedRealmName() return "Realm" end
        function GetInspectSpecialization(unit) return data(unit).spec or 0 end
        inspectCalls={}
        function CanInspect(unit) return data(unit).canInspect or false end
        function NotifyInspect(unit)
            inspectCalls[#inspectCalls+1]=unit
            if inspectError then error("inspect unavailable") end
        end
        C_SpecializationInfo={GetSpecialization=function() return 1 end,
            GetSpecializationInfo=function() return roster[1] and roster[1].spec or 0 end}
        function GetSpecializationInfoByID(spec)
            local role = spec==257 and "HEALER" or spec==73 and "TANK" or "DAMAGER"
            return spec,"Specialization","",1,role
        end
        ns.db.profile.RaidPartyTooltip={}
    ''')
    for path in ("UI/Templates.lua", "Modules/RaidGroups/RaidGroups.lua",
                 "Modules/RaidPreparation/RaidPreparation.lua", "Modules/RaidPartyTooltip/RaidPartyTooltip.lua"):
        lua.execute((ROOT / path).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        module=ns.RaidPartyTooltip
        module:OnEnable()
        roster={{name="Leader",class="WARRIOR",role="TANK",spec=73}}
        viewer:Show();flush();display=module.recruitmentPanel
    ''')
    return lua


def test_recruiting_composition_counts_specs_and_secret_data():
    for locale in ("koKR", "enUS"):
        lua = recruitment_runtime(locale)
        lua.execute('''
            assert(display:IsVisible() and display.width==320)
            roster={
                {name="Tank",class="WARRIOR",role="TANK",spec=73},
                {name="Healer",class="PRIEST",role="HEALER",spec=257},
                {name="Survival",class="HUNTER",role="DAMAGER",spec=255},
                {name="Devourer",class="DEMONHUNTER",role="DAMAGER",spec=1480},
                {name="Havoc",class="DEMONHUNTER",role="DAMAGER",spec=577},
                {name="Feral",class="DRUID",role="DAMAGER",spec=103},
                {name="Balance",class="DRUID",role="DAMAGER",spec=102},
                {name="Enhance",class="SHAMAN",role="DAMAGER",spec=263},
                {name="Elemental",class="SHAMAN",role="DAMAGER",spec=262},
                {name="Unknown",class="HUNTER",role="DAMAGER"},
                {name="Mage",class="MAGE",role="DAMAGER"},
            }
            fire("GROUP_ROSTER_UPDATE");fire("PLAYER_ROLES_ASSIGNED");flush()
            local s=module:CollectRecruitment()
            assert(s.total==11 and s.positions.TANK==1 and s.positions.HEALER==1)
            assert(s.positions.MELEE==4 and s.positions.RANGED==4 and s.positions.UNKNOWN==1)
            assert(s.armor.PLATE==1 and s.armor.CLOTH==2 and s.armor.MAIL==4 and s.armor.LEATHER==4)
            assert(display.positions.MELEE.text=="4" and display.armor.MAIL.text=="4")
            assert(#module:GetMissingSynergies(s)==4)
            specCallback(253,"DAMAGER","RANGED","Unknown");flush()
            assert(module:CollectRecruitment().positions.RANGED==5)
            specCallback(255,"DAMAGER","MELEE","Unknown-OtherRealm");flush()
            assert(module:CollectRecruitment().positions.RANGED==5)
            fire("PLAYER_SPECIALIZATION_CHANGED","raid10");flush()
            assert(module:CollectRecruitment().positions.UNKNOWN==1)
            roster[10].realm="";roster[10].role="NONE"
            specCallback(255,"DAMAGER","MELEE","Unknown");flush()
            assert(display.positions.MELEE.text=="5" and module:CollectRecruitment().positions.UNKNOWN==0)
            fire("GROUP_ROSTER_UPDATE");flush()
            assert(module:CollectRecruitment().positions.MELEE==5)
            roster[10].realm="Other Realm"
            fire("GROUP_ROSTER_UPDATE");flush()
            specCallback(255,"DAMAGER","MELEE","Unknown");flush()
            assert(module:CollectRecruitment().positions.UNKNOWN==1)
            specCallback(253,"DAMAGER","RANGED","Unknown-OtherRealm");flush()
            assert(module:CollectRecruitment().positions.RANGED==5)
            fire("PLAYER_SPECIALIZATION_CHANGED","raid10");flush()
            specCallback(secret,secret,secret,secret);flush()
            roster[10].spec=secret;roster[10].class=secret;roster[10].role=secret
            fire("GROUP_ROSTER_UPDATE");flush()
            s=module:CollectRecruitment()
            assert(s.unknownClasses==1 and s.unknownArmor==1 and s.positions.UNKNOWN==1)
            assert(display.synergyTitle.text==ns.L.RPT_SYNERGY_UNCERTAIN)
            for _,entry in ipairs(module:GetMissingSynergies(s)) do assert(not s.classes[entry.providerClass]) end
            inRaid=false
            roster={{name="Solo",class="PRIEST",role="NONE",spec=257}}
            fire("GROUP_ROSTER_UPDATE");flush()
            s=module:CollectRecruitment();assert(s.total==1 and s.positions.HEALER==1 and s.armor.CLOTH==1)
            for i=2,5 do roster[i]={name="Member"..i,class="ROGUE",role="DAMAGER"} end
            assert(module:CollectRecruitment().positions.MELEE==4)
            inRaid=true;roster={}
            for i=1,40 do roster[i]={name="Member"..i,class="PRIEST",role="HEALER",subgroup=math.ceil(i/5)} end
            s=module:CollectRecruitment();assert(s.total==40 and s.positions.HEALER==40 and s.armor.CLOTH==40)
            assert(module:CollectGroup(1).total==5 and module:CollectGroup(8).total==5)
            assert(module:CollectGroup(0).total==0 and module:CollectGroup(secret).total==0)
            roster={}
            for _,class in ipairs({"WARRIOR","PRIEST","MAGE","DRUID","SHAMAN","EVOKER",
                "MONK","DEMONHUNTER","HUNTER","PALADIN","ROGUE"}) do
                roster[#roster+1]={name=class,class=class,role="DAMAGER"}
            end
            module:RefreshRecruitment()
            assert(#module:GetMissingSynergies(module:CollectRecruitment())==0 and display.empty.shown)
            for _,row in ipairs(display.synergies) do assert(not row.shown) end
        ''')


def test_recruiting_automatically_acquires_and_retains_missing_specs():
    lua = recruitment_runtime()
    lua.execute('''
        module:OnDisable();LibStub=function() end;module:OnEnable();flush()
        assert(specCallback==nil)
        roster[2]={name="Near",class="HUNTER",role="DAMAGER",canInspect=true}
        roster[3]={name="Far",class="SHAMAN",role="NONE",canInspect=false}
        roster[4]={name="Priest",class="PRIEST",role="NONE",canInspect=true}
        fire("GROUP_ROSTER_UPDATE");flush()
        assert(#inspectCalls==1 and inspectCalls[1]=="raid2")
        module:RefreshRecruitment();assert(#inspectCalls==1)
        roster[2].spec=255;fire("INSPECT_READY","guid-near")
        roster[2].spec=nil;flush()
        assert(display.positions.MELEE.text=="1" and module:CollectRecruitment().positions.UNKNOWN==2)
        clock=clock+4;display.scripts.OnUpdate(display,2)
        assert(#inspectCalls==2 and inspectCalls[2]=="raid4")
        roster[4].spec=257;fire("INSPECT_READY","guid-priest")
        roster[4].spec=nil;flush()
        assert(display.positions.HEALER.text=="1" and module:CollectRecruitment().positions.UNKNOWN==1)
        roster[3].canInspect=true
        clock=clock+4;NotifyInspect("target")
        module:RefreshRecruitment();assert(#inspectCalls==3)
        clock=clock+4
        InspectFrame=CreateFrame("Frame",nil,UIParent)
        module:RefreshRecruitment();assert(#inspectCalls==3)
        InspectFrame:Hide();display.scripts.OnUpdate(display,2)
        assert(#inspectCalls==4 and inspectCalls[4]=="raid3")
        clock=clock+4;display.scripts.OnUpdate(display,2)
        assert(#inspectCalls==4)
        clock=clock+30;inspectError=true;display.scripts.OnUpdate(display,2)
        assert(#inspectCalls==5)
        inspectError=false;module:RefreshRecruitment();assert(#inspectCalls==5)
        roster[3].spec=262;fire("INSPECT_READY","guid-far")
        roster[3].spec=nil;flush()
        assert(display.positions.RANGED.text=="1" and not display._needsSpecRefresh)
        local old=roster[2];roster[2]=roster[3];roster[3]=old
        fire("GROUP_ROSTER_UPDATE");flush()
        assert(module:CollectRecruitment().positions.UNKNOWN==0)
        roster[2].name="NewMember";roster[2].role="DAMAGER"
        fire("GROUP_ROSTER_UPDATE");flush()
        assert(module:CollectRecruitment().positions.UNKNOWN==1)
        clock=clock+30;inCombat=true;fire("PLAYER_REGEN_DISABLED")
        module:RefreshRecruitment();assert(#inspectCalls==5 and not display.shown)
        inCombat=false;viewer:Hide();module:RefreshRecruitment();assert(#inspectCalls==5)
        viewer:Show();flush();assert(#inspectCalls==6)
        clock=clock+30;roster[2].canInspect=secret
        module:RefreshRecruitment();assert(#inspectCalls==6)
        roster[2].canInspect=true;roster[2].name=secret
        module:RefreshRecruitment();assert(#inspectCalls==6)
        roster[2].name="NewMember"
        module.db.showRecruitmentPanel=false;module:ApplySettings();assert(#inspectCalls==6)
        module.db.showRecruitmentPanel=true;module:OnDisable()
        module:RefreshRecruitment();assert(#inspectCalls==6)
        roster={roster[1]}
        for i=2,40 do roster[i]={name="Member"..i,class="HUNTER",role="DAMAGER",canInspect=true} end
        clock=clock+4;module:OnEnable();flush()
        for i=2,39 do clock=clock+4;display.scripts.OnUpdate(display,2) end
        local seen={}
        assert(#inspectCalls==6+39)
        for i=7,#inspectCalls do
            assert(not seen[inspectCalls[i]],"retry starved an uninspected member")
            seen[inspectCalls[i]]=true
        end
    ''')


def test_recruiting_visibility_layout_and_shared_raiderio_anchor():
    for locale in ("koKR", "enUS"):
        lua = recruitment_runtime(locale)
        lua.execute('''
            assert(display.points.TOPLEFT.relative==PVEFrame and display.points.TOPLEFT.anchor=="TOPRIGHT")
            for _,r in ipairs(regions) do
                if r.parent==display and r.kind=="FontString" then
                    assert(r:GetStringWidth()<=r.width,"overflow: "..(r.text or ""))
                end
            end
            for _,row in ipairs(display.synergies) do
                if row.shown then
                    assert(-row.points.TOPLEFT.y+row.height<display.height)
                    row.scripts.OnEnter(row);assert(GameTooltip.owner==row)
                    row.scripts.OnLeave(row);assert(not GameTooltip.shown)
                end
            end
            for _,bad in ipairs({secret,secretTable,{activityIDs=secret},{activityIDs=secretTable},{activityIDs={secret}}}) do
                listing=bad;module:RefreshRecruitment();assert(not display.shown)
            end
            listing={activityIDs={100}}
            for _,bad in ipairs({secret,2,4}) do category=bad;module:RefreshRecruitment();assert(not display.shown) end
            category=3;leader=false;roster[2]={name="Member",class="MAGE",role="DAMAGER"}
            module:RefreshRecruitment();assert(not display.shown)
            leader=secret;module:RefreshRecruitment();assert(not display.shown)
            leader=true;module:RefreshRecruitment();assert(display.shown)
            fire("PLAYER_REGEN_DISABLED");assert(not display.shown)
            inCombat=true;flush();assert(not display.shown)
            inCombat=false;fire("PLAYER_REGEN_ENABLED");flush();assert(display.shown)
            module.db.showRecruitmentPanel=false;module:ApplySettings();assert(not display.shown)
            module.db.showRecruitmentPanel=true;module:ApplySettings();assert(display.shown)
            RaiderIO_ProfileTooltipAnchor=CreateFrame("Frame",nil,PVEFrame)
            local anchor=RaiderIO_ProfileTooltipAnchor
            anchor:SetPoint("TOPLEFT",PVEFrame,"TOPRIGHT",-16,0)
            module:PositionRecruitmentPanel()
            assert(anchor.points.TOPLEFT.relative==display)
            anchor:SetPoint("TOPLEFT",PVEFrame,"TOPRIGHT",-16,0)
            assert(anchor.points.TOPLEFT.relative==display)
            viewer:Hide();assert(not display.shown and anchor.points.TOPLEFT.relative==PVEFrame)
            local filter=CreateFrame("Frame",nil,PVEFrame);filter._attachedSide="RIGHT"
            ns.UI:UpdateGroupFinderSideAnchor(filter);assert(anchor.points.TOPLEFT.relative==filter)
            filter:Hide();viewer:Show();flush()
            assert(anchor.points.TOPLEFT.relative==display)
            PVEFrame:Hide();ns.UI:UpdateGroupFinderSideAnchor()
            assert(not display:IsVisible() and anchor.points.TOPLEFT.relative==PVEFrame)
            PVEFrame:Show();flush();assert(anchor.points.TOPLEFT.relative==display)
            local custom=CreateFrame("Frame",nil,UIParent)
            anchor:SetPoint("TOPLEFT",custom,"TOPRIGHT",2,0)
            module:PositionRecruitmentPanel();assert(anchor.points.TOPLEFT.relative==custom)
            anchor:SetPoint("TOPLEFT",PVEFrame,"TOPRIGHT",-16,0)
            viewer:Hide();PVEFrame.left=1100;PVEFrame.right=1740;viewer:Show();flush()
            assert(display._attachedSide=="LEFT" and display.points.TOPRIGHT.anchor=="TOPLEFT")
            assert(anchor.points.TOPLEFT.relative==PVEFrame)
            viewer:Hide();PVEFrame.left=100;PVEFrame.right=740;viewer:Show();flush()
            assert(display._attachedSide=="RIGHT" and anchor.points.TOPLEFT.relative==display)
            RaiderIO_ProfileTooltip=CreateFrame("Frame",nil,anchor)
            local tooltip=RaiderIO_ProfileTooltip
            tooltip:SetWidth(300)
            PVEFrame.left=800;PVEFrame.right=1440
            viewer:Hide();tooltip:Hide();viewer:Show();flush()
            assert(display._attachedSide=="LEFT" and anchor.points.TOPLEFT.relative==PVEFrame)
            local point=display.points.TOPRIGHT
            for _,width in ipairs({100,500,0,300}) do
                tooltip:Show();tooltip:SetWidth(width)
                if tooltip.scripts.OnSizeChanged then tooltip.scripts.OnSizeChanged(tooltip) end
                tooltip:Hide()
                fire("GROUP_ROSTER_UPDATE");flush();module:PositionRecruitmentPanel()
                assert(display._attachedSide=="LEFT" and display.points.TOPRIGHT==point)
                assert(anchor.points.TOPLEFT.relative==PVEFrame)
            end
            viewer:Hide();tooltip:SetWidth(100);viewer:Show();flush()
            assert(display._attachedSide=="RIGHT" and anchor.points.TOPLEFT.relative==display)
            point=display.points.TOPLEFT
            for _,width in ipairs({500,100,300,0}) do
                tooltip:Show();tooltip:SetWidth(width)
                if tooltip.scripts.OnSizeChanged then tooltip.scripts.OnSizeChanged(tooltip) end
                tooltip:Hide();module:RefreshRecruitment()
                assert(display._attachedSide=="RIGHT" and display.points.TOPLEFT==point)
                assert(anchor.points.TOPLEFT.relative==display)
            end
            local count=#regions;module:RefreshRecruitment();assert(#regions==count)
            module:OnDisable();flush()
            assert(not display.shown and specCallback==nil and anchor.points.TOPLEFT.relative==PVEFrame)
            viewer:Hide();viewer:Show();flush();assert(not display.shown)
            module:OnEnable();flush();assert(display.shown and #regions==count)
            listing=nil;fire("LFG_LIST_ACTIVE_ENTRY_UPDATE");flush();assert(not display.shown)
        ''')
