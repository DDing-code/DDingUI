"""Exercise potion ordering, native option callbacks and actual item rendering in Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
from test_dashboard_workspace import STUBS

ROOT = Path(__file__).parent


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute('''
        local frame=getmetatable(UIParent)
        for _,key in ipairs({"SetShadowOffset","SetShadowColor","SetClampedToScreen","SetMovable",
            "RegisterForDrag","StartMoving","StopMovingOrSizing"}) do frame[key]=function()end end
        frame.SetEnabled=function(self,value)self.enabled=value end
        frame.SetFrameStrata=function(self,value)self.strata=value end
        frame.GetFrameStrata=function(self)return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
        frame.RegisterEvent=function(self,event) self.events=self.events or {};self.events[event]=true end
        frame.UnregisterAllEvents=function(self)self.events={} end
        local hide=frame.Hide
        frame.Hide=function(self)hide(self);if self.scripts.OnHide then self.scripts.OnHide(self)end end
        frame.Clear=function(self)self.start,self.duration=nil,nil end
        local create=CreateFrame
        function CreateFrame(kind,name,parent,...)
            local f=create(kind,name,parent,...);if name then _G[name]=f end;return f
        end
        UIParent:SetSize(1920,1080)
        workspace=CreateFrame("Frame",nil,UIParent)
        workspace:SetFrameStrata("DIALOG");workspace:SetFrameLevel(35)
        function assertAboveWorkspace(window)
            local strata={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
            local windowOrder,workspaceOrder=strata[window:GetFrameStrata()],strata[workspace:GetFrameStrata()]
            assert(windowOrder>workspaceOrder or (windowOrder==workspaceOrder and window:GetFrameLevel()>workspace:GetFrameLevel()),
                "potion dialog is covered by the settings workspace")
        end
        UISpecialFrames={}
        shared={}
        locale={}
        local ace={GetLocale=function()return locale end,NewLocale=function()return locale end,
            New=function()return {Fire=function()end}end}
        LibStub=setmetatable({NewLibrary=function()return shared end,GetLibrary=function()return shared end},
            {__call=function()return ace end})
        function GetLocale()return "koKR"end
        function GetSpecialization()return spec or 1 end
        function GetSpecializationRole()return role or "DAMAGER" end
        function GetInventoryItemID()return nil end
        function InCombatLockdown()return combat==true end
        function addon:GetGlobalFont()return "font.ttf"end
        function click(button)if button.enabled~=false then button.scripts.OnClick(button)end end
        function selectCount(window,value)
            local dropdown=window.countMode
            click(dropdown.button)
            local list=dropdown.button.children[1]
            local label=locale[value=="total" and "Combined (all)" or "Separate (selected)"]
            for _,row in ipairs(list.children) do
                for _,region in ipairs(row.regions) do
                    if region.text==label then click(row);assert(dropdown:GetValue()==value);return end
                end
            end
            error("count display option missing")
        end
        bag={};requests={}
        C_Item={GetItemNameByID=function()return nil end,GetItemIconByID=function(id)return id end,
            RequestLoadItemDataByID=function(id)requests[id]=true end,
            GetItemCount=function(id,bank,charges,reagent)
                assert(bank==false and reagent==false, "inventory must exclude banks")
                lastCharges=charges;return bag[id] or 0
            end}
        addon.CustomIcons={}
        addon.db.profile={dynamicIcons={iconData={}}}
        GameTooltip.SetItemByID=function()end
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    for name in ('Core', 'Colors', 'ColorNames', 'Widgets'):
        lua.execute((ROOT / f'DDingUI_CDM/Libs/DDingUI_StyleLib/{name}.lua').read_text(encoding='utf-8-sig'))
    lua.execute('addon.GUIBase.SL=shared')
    for name in ('enUS', 'koKR'):
        lua.execute((ROOT / f'DDingUI_CDM_Option/Locales/{name}.lua').read_text(encoding='utf-8-sig'))
    lua.execute((ROOT / 'DDingUI_CDM/Modules/CustomIcons/RuntimeValues.lua').read_text(encoding='utf-8-sig'), 'test', ns)
    custom = (ROOT / 'DDingUI_CDM/Modules/CustomIcons/CustomIcons.lua').read_text(encoding='utf-8-sig')
    item_update = custom[custom.index('function CustomIcons:GetPreferredItem'):custom.index('local function UpdateSpellIconFrame')]
    lua.execute('''
        local DDingUI=addon
        local CustomIcons=addon.CustomIcons
        local SafeNumber=addon.CustomIconRuntimeValues.SafeNumber
        local ITEM_COMBAT_LOCKOUT_ITEMS={}
        local function IsItemCombatLocked()return false end
        local function IsFlightHideAlphaLocked()return false end
        local function ResolveItemTexture(id)return id end
        local function SetStableIconTexture(frame,texture)frame.icon:SetTexture(texture)end
        local function EnsureCooldownSpanOwner(frame,_,id)frame.cooldownOwner=id end
        local function ResolveUsableItemSpellID()return nil end
        local function ResolveItemCooldownSpan(frame,_,id)
            cooldownItem=id
            return 10,30,hasCooldown==true,true
        end
        local function ApplyCooldownSpan(frame,_,start,duration)
            frame.cooldown:SetCooldown(start,duration);return true
        end
        CustomIcons.ManagedVisualLocked=function()return false end
        CustomIcons.StopIconDesatUpdater=function()end
        CustomIcons.ApplyTrackedTrinketEffect=function()return false end
        CustomIcons.SuppressIconFrameVisibility=function(frame)frame:Hide()end
        CustomIcons.RestoreActiveIconVisual=function(frame)frame:Show()end
    ''' + item_update + '\nTestUpdateItemIcon=UpdateItemIcon')
    lua.execute((ROOT / 'DDingUI_CDM_Option/ConsumableOptions.lua').read_text(encoding='utf-8-sig'), 'test', ns)
    lua.execute('''
        c=addon.ConsumableOptions;ci=addon.CustomIcons
        local function ids(d)return table.concat(d.ids,",")end
        health=c:CreateDraft("health")
        stats=c:CreateDraft("stat")
        assert(ids(health)=="271884,271883,241304,241305")
        assert(ids(stats)=="245898,245897,241308,241309,245902,245903,241288,241289")
        assert(locale["Stat Potions"]=="스탯 물약")
        local mana=c:CreateDraft("mana")
        assert(not mana.healerOnly, "existing display behavior stays the default")
        assert(ids(mana)=="245916,245917,241300,241301")
        local manaPayload=c:BuildPayload(mana)
        bag={[245916]=3,[245917]=5,[241300]=8}
        assert(ci:GetPreferredItem(manaPayload)==245916)
        bag[245916]=nil;assert(ci:GetPreferredItem(manaPayload)==245917)
        bag[245917]=nil;assert(ci:GetPreferredItem(manaPayload)==241300)
        mana.fleetingFirst=false;mana.ids=c:BuildIDs(mana)
        assert(ids(mana)=="241300,241301,245916,245917")
        mana.highRankFirst=false;mana.ids=c:BuildIDs(mana)
        assert(ids(mana)=="241301,241300,245917,245916")
        assert(not c:GetKind({type="item",id=245916,settings={fallbackItems="241308"}}))
        local oldMana={type="item",id=241300,settings={fallbackItems="245917,245916,241301"}}
        assert(ids(c:CreateDraft("mana",oldMana))=="241300,245917,245916,241301")
        assert(not c:CreateDraft("unknown"))
        assert(not c:GetKind({type="spell",id=241308}))
        assert(not c:GetKind({type="item",id=241308,settings={fallbackItems="5512"}}))
        stats.fleetingFirst=false;stats.ids=c:BuildIDs(stats)
        assert(ids(stats)=="241308,241309,245898,245897,241288,241289,245902,245903")
        stats.highRankFirst=false;stats.ids=c:BuildIDs(stats)
        assert(stats.ids[1]==241309 and stats.ids[2]==241308 and stats.ids[3]==245897)
        stats.order={"recklessness","light"};stats.enabled.light=false;stats.ids=c:BuildIDs(stats)
        assert(ids(stats)=="241289,241288,245903,245902")
        stats.enabled.recklessness=false;stats.ids=c:BuildIDs(stats)
        assert(not c:BuildPayload(stats))
        local p=c:BuildPayload(health)
        bag={[271883]=5,[241304]=8}
        local id,n=ci:GetPreferredItem(p);assert(id==271883 and n==5)
        bag[271884]=2;assert(ci:GetPreferredItem(p)==271884)
        bag[271884]=0;bag[271883]=0;assert(ci:GetPreferredItem(p)==241304)
        bag={};id,n=ci:GetPreferredItem(p);assert(id==271884 and n==0)
        bag={[271884]=SECRET,[241305]=4};assert(ci:GetPreferredItem(p)==241305)
        p.settings.showCharges=true;ci:GetPreferredItem(p);assert(lastCharges==true)
        -- Sum every enabled candidate once; selection, empty and protected-count rules stay unchanged.
        for _,kind in ipairs({"health","stat","mana"}) do
            local draft=c:CreateDraft(kind)
            assert(draft.itemCountMode=="selected" and not c:BuildPayload(draft).settings.itemCountMode)
            draft.itemCountMode="total"
            local payload=c:BuildPayload(draft)
            bag={[5512]=1000};local expected=0
            for index,itemID in ipairs(draft.ids) do bag[itemID]=index;expected=expected+index end
            local selected,own,total=ci:GetPreferredItem(payload)
            assert(selected==draft.ids[1] and own==1 and total==expected)
            payload.settings.fallbackItems=payload.settings.fallbackItems..","..payload.id..","..draft.ids[2]
            selected,own,total=ci:GetPreferredItem(payload);assert(own==1 and total==expected)
            bag[payload.id]=SECRET
            selected,own,total=ci:GetPreferredItem(payload)
            assert(selected==draft.ids[2] and own==2 and total==expected-1)
            payload.settings.itemCountMode=nil
            selected,own,total=ci:GetPreferredItem(payload);assert(own==2 and total==2)
            payload.settings.itemCountMode="total";bag={}
            selected,own,total=ci:GetPreferredItem(payload);assert(selected==payload.id and own==0 and total==0)
        end
        local generic={type="item",id=5512,settings={fallbackItems="224464"}}
        bag={[224464]=3};assert(ci:GetPreferredItem(generic)==224464)
        old={type="item",id=241308,key="stable",uid="keep",settings={fallbackItems="245898,245897,241309",iconSize=42}}
        local legacy=c:CreateDraft("stat",old)
        assert(ids(legacy)=="241308,245898,245897,241309")
        assert(legacy.enabled.light and not legacy.enabled.recklessness)
        assert(c:BuildPayload(legacy).settings.fallbackItems==old.settings.fallbackItems)

        -- Actual native UI widgets/callbacks, including cancellation and live bag preview.
        bag={[245897]=4,[241308]=6,[245902]=3};c:Show("stat",nil,function(payload)applied=payload;return true end)
        w=DDingUI_ConsumablePriority
        assertAboveWorkspace(w)
        assert(w:IsShown() and w.title:GetText():find(locale["Stat Potions"],1,true))
        assert(w.preview:GetText():find("4",1,true))
        assert(w.families[1].up.label:GetText()=="▲" and w.families[1].down.label:GetText()=="▼")
        selectCount(w,"total")
        assert(w.preview:GetText():find(string.format(locale["Icon count: %d"],13),1,true))
        assert(w.entries[2].count:GetText()==string.format(locale["%d in bags"],4))
        assert(w.families[1].up.enabled==false and w.families[2].down.enabled==false)
        assert(requests[245898] and requests[241289] and #UISpecialFrames==1)
        click(w.families[2].up);assert(w.draft.ids[1]==245902)
        click(w.fleeting.box);assert(w.draft.ids[1]==241288)
        click(w.rank.box);assert(w.draft.ids[1]==241289)
        click(w.families[1].enabled.box);assert(w.draft.ids[1]==241309)
        assert(w.preview:GetText():find(string.format(locale["Icon count: %d"],10),1,true))
        click(w.families[2].enabled.box);assert(not w.apply.enabled)
        click(w.apply);assert(not applied)
        click(w.families[2].enabled.box)
        click(w.empty.box)
        combat=true;w.scripts.OnEvent(w);assert(not w.apply.enabled)
        click(w.apply);assert(not applied)
        combat=false;w.scripts.OnEvent(w);click(w.apply)
        assert(applied.id==241309 and applied.settings.hideWhenEmpty and not w:IsShown())
        assert(applied.settings.itemCountMode=="total")
        assert(not next(w.events))
        c:Show("health",nil,function()error("cancel must not apply")end)
        assertAboveWorkspace(w)
        assert(not w.fleeting:IsShown() and not w.entries[5]:IsShown())
        click(w.cancel);assert(not w:IsShown())

        -- Mana owns a separate window and draft even while the stat window is open.
        c:Show("stat",nil,function(payload)statApplied=payload;return true end)
        local statDraft=w.draft
        c:Show("mana",nil,function(payload)manaApplied=payload;return true end)
        m=DDingUI_ManaPotionPriority
        assertAboveWorkspace(m)
        assert(m~=w and m:IsShown() and w:IsShown() and w.draft==statDraft)
        assert(m.healerOnly and not w.healerOnly)
        assert(m.healerOnly.label:GetText()=="힐러일 때만 표시")
        click(m.healerOnly.box)
        assert(m.title:GetText():find(locale["Mana Potions"],1,true))
        assert(#m.families==1 and not m.families[1].up:IsShown() and m.fleeting:IsShown())
        assert(not m.entries[5]:IsShown() and #UISpecialFrames==2)
        selectCount(m,"total");assert(w.draft.itemCountMode=="selected")
        assert(m.entries[1].text:GetText():find(string.format(locale["%s (Rank %d)"],locale["Fleeting Lightfused Mana Potion"],2),1,true))
        click(m.fleeting.box);click(m.rank.box)
        assert(m.draft.ids[1]==241301 and w.draft.ids[1]==245898)
        combat=true;m.scripts.OnEvent(m);click(m.apply);assert(not manaApplied)
        combat=false;m.scripts.OnEvent(m);click(m.apply)
        assert(manaApplied.id==241301 and not m:IsShown() and w:IsShown() and not statApplied)
        assert(manaApplied.settings.itemCountMode=="total")
        assert(manaApplied.settings.healerOnly==true and not statDraft.healerOnly)
        click(w.apply);assert(statApplied.id==245898)
        assert(not statApplied.settings.itemCountMode)

        local refreshes,saves=0,0
        ci.RefreshDynamicIcon=function(_,key)assert(key=="stable");refreshes=refreshes+1 end
        ci.OptionsAPI={RefreshAllLayouts=function()refreshes=refreshes+1 end}
        addon.SpecProfiles={SaveCurrentSpec=function()saves=saves+1 end}
        addon.CustomIconActiveEffectOverlay={MarkDirty=function()refreshes=refreshes+1 end}
        addon.db.profile.dynamicIcons.iconData.stable=old
        c:Edit("stable");selectCount(w,"total");click(w.cancel)
        assert(old.id==241308 and old.settings.fallbackItems=="245898,245897,241309")
        assert(not old.settings.itemCountMode)
        c:Edit("stable");selectCount(w,"total");click(w.fleeting.box);click(w.apply)
        assert(old.id==245898 and old.settings.iconSize==42 and old.key=="stable" and old.uid=="keep")
        assert(old.settings.itemCountMode=="total")
        assert(refreshes==3 and saves==1)
        local saved=old.id
        c:Edit("stable");click(w.rank.box);spec=2;click(w.apply)
        assert(old.id==saved and w:IsShown() and saves==1)
        spec=1;click(w.cancel)
        c:Edit("stable");local previous=addon.db.profile;addon.db.profile={};click(w.apply)
        assert(saves==1 and old.id==saved);addon.db.profile=previous;click(w.cancel)
        c:Edit("stable");assert(w.countMode:GetValue()=="total")
        local fallbackOrder=old.settings.fallbackItems
        selectCount(w,"selected");click(w.apply)
        assert(not old.settings.itemCountMode and old.settings.fallbackItems==fallbackOrder and old.id==saved)

        -- Saving the role toggle must create/release frames, and cancellation must not save it.
        local manaIcon={type="item",id=241300,settings={iconSize=42}}
        addon.db.profile.dynamicIcons.iconData.mana=manaIcon
        local reloads=0
        ci.LoadDynamicIcons=function()reloads=reloads+1 end
        c:Edit("mana");click(m.healerOnly.box);click(m.cancel)
        assert(not manaIcon.settings.healerOnly and reloads==0)
        c:Edit("mana");click(m.healerOnly.box);click(m.apply)
        assert(manaIcon.settings.healerOnly and reloads==1 and manaIcon.settings.iconSize==42)
        c:Edit("mana");assert(m.healerOnly:GetChecked())
        click(m.healerOnly.box);click(m.apply)
        assert(not manaIcon.settings.healerOnly and reloads==2)

        -- Actual item renderer uses the same selector for texture, cooldown and count.
        addon.CustomIconActiveEffectOverlay=nil
        local frame=CreateFrame("Frame",nil,UIParent)
        frame.icon=frame:CreateTexture();frame.cooldown=CreateFrame("Cooldown",nil,frame)
        frame.count=frame:CreateFontString();frame.count:SetFont("font.ttf",12,"")
        p.settings.hideWhenEmpty=true
        for _,mode in ipairs({"selected","total"}) do
        p.settings.itemCountMode=mode
        for _,inCombat in ipairs({false,true}) do
            combat=inCombat;hasCooldown=true;bag={[241305]=7}
            TestUpdateItemIcon(frame,p)
            assert(frame.icon:GetTexture()==241305 and frame.cooldownOwner==241305 and cooldownItem==241305)
            assert(frame.count:GetText()==7 and frame.cooldown:IsShown() and frame:IsShown())
            assert(frame.cooldown.duration==30 and frame.icon:GetDesaturation()==1)
            bag[241304]=3;TestUpdateItemIcon(frame,p)
            assert(frame.icon:GetTexture()==241304 and frame.cooldownOwner==241304 and cooldownItem==241304)
            assert(frame.count:GetText()==(mode=="total" and 10 or 3) and frame._ddCombatItemCount==3)
            assert(not frame._ddItemCountEmpty and frame:IsShown())
            bag={};TestUpdateItemIcon(frame,p);assert(not frame:IsShown())
            bag={[271884]=2};hasCooldown=false;TestUpdateItemIcon(frame,p)
            assert(frame:IsShown() and frame.icon:GetTexture()==271884 and frame.count:GetText()==2)
            assert(not frame.cooldown:IsShown() and frame.icon:GetDesaturation()==0)
        end
        end
        p.settings.showCharges=false;TestUpdateItemIcon(frame,p);assert(not frame.count:IsShown())
    ''')
    # Follow the real add-menu -> draft -> existing group insertion path.
    options = (ROOT / 'DDingUI_CDM_Option/GroupSystemOptions.lua').read_text(encoding='utf-8-sig')
    insertion = options[options.index('local function AddDynamicPayloadToGroup'):options.index('function DDingUI:AddTotemSlotToGroup')]
    menu = options[options.index('local function BuildGroupAddPopupItems'):options.index('local function HideGroupAddSubmenu')]
    settings = options[options.index('function DDingUI:BuildAssignedIconSettingsItems'):options.index('function DDingUI:ResetDynamicAssignedIconSettings')]
    lua.execute('''
        local DDingUI=addon;local L=locale
        local function EnsureSourceGroup(name)return name end
        local function CopyDynamicIconSettings(settings)
            local copy={};for k,v in pairs(settings or {})do copy[k]=v end;return copy
        end
        local function BuildDynamicIconSettings(_,_,_,settings)return settings end
        local function SnapshotGroupOrderTokens()return {"existing"}end
        local function MergeDynamicIconSettings()end
        local function AppendGroupOrderToken(_,before,token)assert(before[1]=="existing");addedToken=token end
        local function MakeDynamicOrderToken(key)return key end
        local function ScheduleDynamicIconRefresh(key)addedRefresh=key end
        local function SoftRefreshDynamicIcons()end
        local function SafeItemIcon(id)return id end
    ''' + insertion + menu + settings + '\nTestAddMenu=BuildGroupAddPopupItems')
    lua.execute('''
        combat=false
        addon.db.profile.groupSystem={groups={Common={shared=true}}}
        local added=0
        ci.AddDynamicIcon=function(_,payload)
            added=added+1;addon.db.profile.dynamicIcons.iconData.added=payload;return "added"
        end
        ci.MoveIconToGroup=function(_,key,group)assert(key=="added" and group=="Common")end
        local entries=TestAddMenu("Common",nil,"skill")
        local submenu
        for _,entry in ipairs(entries)do if entry.label==locale.Consumables then submenu=entry.submenu end end
        assert(submenu and submenu[1].action())
        assert(added==0, "opening the priority dialog must not create an icon")
        selectCount(w,"total")
        click(w.apply)
        local new=addon.db.profile.dynamicIcons.iconData.added
        assert(added==1 and new.id==245898 and new.settings.fallbackItems=="245897,241308,241309,245902,245903,241288,241289")
        assert(new.settings.itemCountMode=="total")
        assert(addedToken=="added" and addedRefresh=="added")
        submenu[2].action();click(w.cancel);assert(added==1)
        assert(not addon:ShowConsumableGroupOptions("Deleted","health"))
        addon:ShowConsumableGroupOptions("Common","health")
        addon.db.profile.groupSystem.groups.Common=nil;click(w.apply);assert(added==1)
        click(w.cancel)
        local detail=addon:BuildAssignedIconSettingsItems("Common",{_gridDynamicIconKey="added"})
        assert(detail[1].text==locale["Potion Priority"])
        detail[1].func();assert(w:IsShown() and w.draft.ids[1]==245898);click(w.cancel)
        assert(#addon:BuildAssignedIconSettingsItems("Common",{})==0)
        addon.db.profile.groupSystem.groups.Common={shared=true}
        assert(submenu[3].label==locale["Mana Potions"] and submenu[3].action())
        assert(m:IsShown() and not w:IsShown() and added==1)
        click(m.healerOnly.box)
        click(m.apply)
        local mana=addon.db.profile.dynamicIcons.iconData.added
        assert(added==2 and mana.id==245916 and mana.settings.fallbackItems=="245917,241300,241301")
        assert(mana.settings.healerOnly)
        assert(new.id==245898, "mana addition must not rewrite a stat icon")
        local detail=addon:BuildAssignedIconSettingsItems("Common",{_gridDynamicIconKey="added"})
        detail[1].func();assert(m:IsShown() and m.draft.kind=="mana" and not w:IsShown());click(m.cancel)
    ''')
    # The same role check controls frame creation, standalone layout and the real group bridge.
    lua.execute((ROOT / 'DDingUI_CDM/Modules/CustomIcons/FrameLifecycle.lua').read_text(encoding='utf-8-sig'), 'test', ns)
    lua.execute('''
        local function ensure(data)
            data.settings=data.settings or {};data.settings.loadConditions=data.settings.loadConditions or {}
        end
        local _,loadable,spawn=addon.CustomIconFrameLifecycle.Create({},ci,nil,nil,ensure)
        ci.IsIconLoadable=function(_,data)return loadable(data)end
        TestShouldSpawn=spawn
        local db=addon.db.profile.dynamicIcons
        db.iconData={health=c:BuildPayload(c:CreateDraft("health")),mana=db.iconData.added}
        db.groups={Common={icons={"health","mana"}}};db.ungrouped={}
        ci.GetDynamicDB=function()return db end
        frames={health=CreateFrame("Frame",nil,UIParent),mana=CreateFrame("Frame",nil,UIParent)}
        ci.GetAllIconFrames=function()return frames end
        getmetatable(UIParent).RegisterUnitEvent=function()end
        C_Timer.After=function()end
    ''')
    lua.execute((ROOT / 'DDingUI_CDM/Modules/GroupSystem/DynamicIconBridge.lua').read_text(encoding='utf-8-sig'), 'test', ns)
    lua.execute('''
        local bridge=addon.DynamicIconBridge
        local mana=addon.db.profile.dynamicIcons.iconData.mana
        local health=addon.db.profile.dynamicIcons.iconData.health
        for _,r in ipairs({"HEALER","DAMAGER","TANK","HEALER"}) do
            role=r
            for _,enabled in ipairs({true,false}) do
                mana.settings.healerOnly=enabled
                local eligible=not enabled or role=="HEALER"
                assert(ci:IsIconLoadable(mana)==eligible and TestShouldSpawn(mana)==eligible)
                assert(ci:IsIconLoadable(health) and TestShouldSpawn(health))
                for _,fighting in ipairs({false,true}) do
                    combat=fighting
                    frames.mana._wasVisibleInGroup=true;frames.mana._ddLastDynamicActiveAt=GetTime()
                    frames.mana._ddIsManaged=true;frames.mana._ddContainerRef=UIParent
                    local entries=bridge:GetActiveIconsForGroup("Common")
                    assert(#entries==(eligible and 2 or 1), "filtered mana must not reserve a group slot")
                    assert(entries[1].iconKey=="health")
                end
            end
        end
        role="HEALER";mana.settings.healerOnly=true;mana.settings.hideWhenEmpty=true
        frames.mana._ddItemCountEmpty=true
        assert(#bridge:GetActiveIconsForGroup("Common")==1)
        local getSpec=GetSpecialization;GetSpecialization=function()end
        assert(not ci:IsIconLoadable(mana) and not TestShouldSpawn(mana))
        GetSpecialization=getSpec;assert(ci:IsIconLoadable(mana))
        mana.settings.loadConditions={enabled=true,specs={[105]=true}}
        GetSpecializationInfo=function()return 65 end
        assert(not TestShouldSpawn(mana), "existing specialization restrictions still apply")
    ''')
    addition = custom[custom.index('function CustomIcons:AddDynamicIcon'):custom.index('function CustomIcons:RemoveDynamicIcon')]
    lua.execute('''
        local DDingUI,CustomIcons=addon,ci
        local function noop()end
        local GetDynamicDB=ci.GetDynamicDB
        local function IsIconLoadable(data)return ci:IsIconLoadable(data)end
        local EnsureIconSettings,EnsureLoadConditions,EnsureStoredIconTexture,EnsureEventFrame=noop,noop,noop,noop
        local BuildDefaultUngroupedPositionSettings=function()return {}end
        local EnsureGroupFrame,UpdateDynamicIcon,RefreshAllLayouts=noop,noop,noop
        local runtime={iconFrames={}}
        newFrameCount=0
        local function CreateDynamicIcon()newFrameCount=newFrameCount+1;return {}end
        ci.RefreshDynamicListUI=noop
        addon.SpecProfiles=nil
    ''' + addition)
    lua.execute('''
        combat=false;role="DAMAGER"
        ci:AddDynamicIcon({key="filtered",type="item",id=241300,settings={healerOnly=true}})
        assert(newFrameCount==0 and addon.db.profile.dynamicIcons.iconData.filtered)
        role="HEALER"
        ci:AddDynamicIcon({key="healing",type="item",id=241300,settings={healerOnly=true}})
        assert(newFrameCount==1)
        role="TANK"
        ci:AddDynamicIcon({key="unfiltered",type="item",id=241300,settings={}})
        assert(newFrameCount==2)
    ''')
    for file in ('DDingUI_CDM/Modules/CustomIcons/CustomIcons.lua',
                 'DDingUI_CDM_Option/ConsumableOptions.lua', 'DDingUI_CDM_Option/GroupSystemOptions.lua',
                 'DDingUI_CDM_Option/DynamicIconsUI.lua', 'DDingUI_CDM_Option/Locales/enUS.lua',
                 'DDingUI_CDM_Option/Locales/koKR.lua'):
        lua.eval('function(source) assert(loadstring(source)) end')((ROOT / file).read_text(encoding='utf-8-sig'))
    toc = (ROOT / 'DDingUI_CDM_Option/DDingUI_CDM_Option.toc').read_text(encoding='utf-8-sig')
    assert toc.index('ConsumableOptions.lua') < toc.index('DynamicIconsUI.lua') < toc.index('GroupSystemOptions.lua')
    print('Consumable priorities: passed')


if __name__ == '__main__':
    main()
