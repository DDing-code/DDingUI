"""Run the real shared-group/spec persistence and group actions in Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent


def test_shared_icon_groups():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        function wipe(t) for k in pairs(t) do t[k]=nil end end
        function GetSpecialization() return 1 end
        function GetSpecializationInfo() return 62 end
        function InCombatLockdown() return combat == true end
        C_Timer={After=function()end,NewTimer=function()return {Cancel=function()end}end}
        addon={db={profile={},char={}},defaults={profile={}}}
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    for file in ('Core/SpecProfiles.lua', 'Modules/CustomIcons/IconIdentity.lua',
                 'Modules/GroupSystem/GroupManager.lua'):
        lua.execute((ROOT / 'DDingUI_CDM' / file).read_text(encoding='utf-8-sig'), 'DDingUI_CDM', ns)
    lua.execute('''
        local sp,gm=addon.SpecProfiles,addon.GroupManager
        local function fresh()
            addon.db.profile={
                groupSystem={groups={Cooldowns={groupType="cdm"},Utility={groupType="cdm"}},spellAssignments={}},
                dynamicIcons={enabled=true,groups={},iconData={},ungrouped={},ungroupedPositions={}},
                movers={},powerBar={height=15},specData={}}
            sp.lastSpecID=62
            sp:SaveCurrentSpec()
            return addon.db.profile
        end
        local serial=0
        addon.CustomIcons={CreateDynamicGroup=function(_,name)
            serial=serial+1
            local key="group_"..serial
            addon.db.profile.dynamicIcons.groups[key]={name=name,icons={},settings={}}
            sp:SaveCurrentSpec()
            return key
        end}
        local function addIcon(name,key,id)
            local p=addon.db.profile
            local group=p.groupSystem.groups[name]
            local source=p.dynamicIcons.groups[group.sourceGroupKey]
            p.dynamicIcons.iconData[key]={key=key,type="item",id=id,persistentID="item:"..id,settings={targetCDMGroup=name}}
            source.icons[#source.icons+1]=key
            group.iconOrder=group.iconOrder or {}
            group.iconOrder[#group.iconOrder+1]="dynid:item:"..id
            sp:SaveCurrentSpec()
        end
        local function sharedIcon(p,name)
            local group=p.groupSystem.groups[name]
            local key=p.dynamicIcons.groups[group.sourceGroupKey].icons[1]
            return p.dynamicIcons.iconData[key],key
        end
        local p=fresh()
        assert(gm:CreateGroup("Local"))
        addIcon("Local","local_item",1)
        sp:OnSpecChanged(63)
        assert(not p.groupSystem.groups.Local)
        p.powerBar.height=24
        p.groupSystem.spellAssignments.SharedSpell="Utility"
        sp:SaveCurrentSpec()
        sp:OnSpecChanged(62)
        assert(gm:CreateGroup("Shared",{shared=true}))
        addIcon("Shared","shared_item",2)
        local group=p.groupSystem.groups.Shared
        group.iconSize,group.offsetX=47,120
        p.movers.DDingUI_Group_Shared="CENTER,UIParent,CENTER,120,15"
        assert(gm:AssignSpell("SharedSpell","Shared"))
        sp:OnSpecChanged(63)
        assert(p.groupSystem.groups.Shared.shared and p.groupSystem.groups.Shared.iconSize==47)
        assert(p.groupSystem.groups.Shared.offsetX==120 and p.movers.DDingUI_Group_Shared)
        assert(not p.groupSystem.groups.Local and p.powerBar.height==24)
        assert(sharedIcon(p,"Shared").id==2)
        assert(p.groupSystem.spellAssignments.SharedSpell=="Shared")
        p.groupSystem.groups.Shared.iconSize=55
        sharedIcon(p,"Shared").settings.desaturate=true
        sp:SaveCurrentSpec()
        assert(sp:LoadSpec(63)) -- reload / initial login restore
        assert(p.groupSystem.groups.Shared.iconSize==55)
        sp:OnSpecChanged(62)
        assert(p.groupSystem.groups.Local and p.powerBar.height==15)
        assert(p.groupSystem.groups.Shared.iconSize==55 and sharedIcon(p,"Shared").settings.desaturate)
        assert(gm:SetGroupShared("Shared",false))
        sp:OnSpecChanged(63)
        assert(not p.groupSystem.groups.Shared)
        assert(p.groupSystem.spellAssignments.SharedSpell=="Utility", "restore spec route under shared route")
        sp:OnSpecChanged(62)
        assert(p.groupSystem.groups.Shared and not p.groupSystem.groups.Shared.shared)
        assert(gm:SetGroupShared("Shared",true))
        sp:OnSpecChanged(64) -- never visited specialization
        assert(p.groupSystem.groups.Shared and not p.groupSystem.groups.Local)
        assert(gm:RenameGroup("Shared","Supplies"))
        assert(p.groupSystem.groups.Supplies.name=="Supplies")
        assert(sharedIcon(p,"Supplies").settings.targetCDMGroup=="Supplies")
        sp:OnSpecChanged(62)
        assert(not p.groupSystem.groups.Shared and p.groupSystem.groups.Supplies)
        assert(p.movers.DDingUI_Group_Supplies and not p.movers.DDingUI_Group_Shared)
        -- Match the real delete flow: CustomIcons removes the source, then the wrapper.
        local source=p.groupSystem.groups.Supplies.sourceGroupKey
        local key=p.dynamicIcons.groups[source].icons[1]
        p.dynamicIcons.iconData[key]=nil
        p.dynamicIcons.groups[source]=nil
        assert(gm:DeleteGroup("Supplies"))
        sp:OnSpecChanged(63)
        sp:OnSpecChanged(64)
        assert(not p.groupSystem.groups.Supplies and not p.dynamicIcons.iconData[key])

        p=fresh()
        assert(gm:CreateGroup("Duplicate"))
        sp:OnSpecChanged(63)
        assert(gm:CreateGroup("Duplicate"))
        assert(not gm:SetGroupShared("Duplicate",true), "do not overwrite a different spec group")
        assert(not gm:CreateGroup("Duplicate",{shared=true}))
        assert(not gm:SetGroupShared("Cooldowns",true))
        combat=true
        assert(not gm:CreateGroup("Combat",{shared=true}))
        assert(not gm:SetGroupShared("Duplicate",true))
        combat=false

        -- Copied specs can reuse source keys, icon keys, and stable identities.
        p=fresh()
        assert(gm:CreateGroup("Other"))
        addIcon("Other","same_icon",42)
        local otherSource=p.groupSystem.groups.Other.sourceGroupKey
        sp:OnSpecChanged(63)
        assert(gm:CreateGroup("Common",{shared=true}))
        local oldSource=p.groupSystem.groups.Common.sourceGroupKey
        p.dynamicIcons.groups[otherSource]=p.dynamicIcons.groups[oldSource]
        p.dynamicIcons.groups[oldSource]=nil
        p.groupSystem.groups.Common.sourceGroupKey=otherSource
        addIcon("Common","same_icon",42)
        sharedIcon(p,"Common").settings.common=true
        sp:OnSpecChanged(62)
        local common,key=sharedIcon(p,"Common")
        assert(key~="same_icon" and common.settings.common)
        assert(not p.dynamicIcons.iconData.same_icon.settings.common)
        assert(p.groupSystem.groups.Common.sourceGroupKey~=otherSource)
        local token=p.groupSystem.groups.Common.iconOrder[1]
        assert(addon.CustomIconIdentity:ResolveOrderToken(p.dynamicIcons,token)==key)
        sp:OnSpecChanged(63)
        sp:OnSpecChanged(62)
        assert(sharedIcon(p,"Other").id==42 and sharedIcon(p,"Common").settings.common)
        assert(sp:CopyModulesFromSpec(63,{"__dynamicGroups"}))
        assert(p.groupSystem.groups.Common and sharedIcon(p,"Common").settings.common)
        -- Legacy snapshots without dynamicIcons must keep the current icon payload once.
        p.specData[65]={groupSystem={groups={Cooldowns={groupType="cdm"}},spellAssignments={}}}
        sp:OnSpecChanged(65)
        local count=0
        for _ in pairs(p.dynamicIcons.iconData) do count=count+1 end
        assert(count==1 and p.groupSystem.groups.Common)
        -- A partial profile import keeps live shared groups and preserves conflicting locals.
        addon.db.profiles={Imported={
            groupSystem={groups={Common={name="Common",groupType="dynamic",sourceGroupKey="imported"}}},
            dynamicIcons={groups={imported={name="Common",icons={"imported_item"}}},
                iconData={imported_item={key="imported_item",type="item",id=99,settings={}}}}}}
        assert(sp:CopyModulesFromProfile("Imported",{"__dynamicGroups"}))
        assert(p.groupSystem.groups.Common.shared and not p.groupSystem.groups.Common_2.shared)
        assert(sharedIcon(p,"Common_2").id==99 and sharedIcon(p,"Common").settings.common)
        -- Shared data belongs to the selected profile, never a different profile.
        local previous=p
        p=fresh()
        sp:OnSpecChanged(63)
        assert(not p.groupSystem.groups.Common and previous.groupSystem.groups.Common)
    ''')

    # Use the existing frame doubles, exercising the actual sidebar and menu callbacks.
    from test_dashboard_workspace import STUBS
    lua.execute('testedAddon=addon')
    lua.execute(STUBS)
    lua.execute('''
        testedAddon.GUI,testedAddon.GUIBase=addon.GUI,addon.GUIBase
        addon=testedAddon
        local frameMeta=getmetatable(UIParent)
        frameMeta.RegisterForClicks=function()end
        addon.GUIBase.L=setmetatable({}, {__index=function(_,key)return key end})
        addon.GUIBase.SL={GetAccent=function()return {0.2,0.75,0.9,1}end,
            ShowCascadingMenu=function(_,items)shownMenu=items end}
        addon.GUISearch={}
        addon.Print=function(_,message)lastMessage=message end
        addon.GroupSystem={Refresh=function()refreshes=(refreshes or 0)+1 end,
            OnGroupAdded=function()end,OnGroupDeleted=function()end}
        function StaticPopup_Show(_,_,_,data)popupData=data;return {}end
        function InCombatLockdown()return combat==true end
    ''')
    gui_source = (ROOT / 'DDingUI_CDM_Option/GUI.lua').read_text(encoding='utf-8-sig')
    prefix = gui_source.split('local function CleanupNestedOptionFrames', 1)[0]
    lua.execute(prefix + '\nBuildMenu=BuildSectionMenuData;MakeMenu=CreateSectionMenu;ShowMenu=ShowCDMGroupContextMenu',
                'DDingUI_CDM_Option', ns)
    workspace = (ROOT / 'DDingUI_CDM_Option/GroupSystemWorkspace.lua').read_text(encoding='utf-8-sig')
    prompt = workspace[workspace.index('function GUI.PromptCreateCDMGroup'):workspace.index('function GUI.CreateGroupSystemWorkspace')]
    lua.execute('local DDingUI=addon;local GUI=addon.GUI;local L=addon.GUIBase.L;local function T(k)return k end\n' + prompt)
    lua.execute('''
        local frame={RebuildTreeMenu=function(_,key)rebuilt=key end}
        assert(addon.GroupManager:CreateGroup("UIShared",{shared=true}))
        local data=BuildMenu({args={groupSystem={type="group"}}},frame)
        assert(frame._optionLookup["groupSystem.__addShared"].action=="addSharedGroup")
        local menu=MakeMenu(UIParent,data,{onSelect=function(key)selected=key end})
        menu:SetSelected("groupSystem")
        local row=menu.rowsByKey["groupSystem.__add"]
        assert(row.sharedAdd:IsShown() and row.sharedAdd.label:GetText():find("Add Shared Group",1,true))
        row.sharedAdd.scripts.OnClick()
        assert(selected=="groupSystem.__addShared")
        local sharedRow=menu.rowsByKey["groupSystem.group_UIShared"]
        assert(sharedRow.sharedBadge:IsShown() and sharedRow.icon.vertexColor[2]==0.75)
        assert(ShowMenu(frame,"UIShared","UIShared",sharedRow))
        assert(shownMenu[1].text=="Convert to Specialization Group")
        shownMenu[1].func()
        assert(not addon.db.profile.groupSystem.groups.UIShared.shared and rebuilt)
        assert(ShowMenu(frame,"UIShared","UIShared",sharedRow))
        assert(shownMenu[1].text=="Convert to Shared Group")
        shownMenu[1].func()
        assert(addon.db.profile.groupSystem.groups.UIShared.shared and refreshes==2)
        assert(not ShowMenu(frame,"Cooldowns","Cooldowns",sharedRow))
        combat=true
        ShowMenu(frame,"UIShared","UIShared",sharedRow)
        assert(shownMenu[1].disabled)
        combat=false
        addon.GUI.PromptCreateCDMGroup(function(name)createdName=name end,true)
        popupData.onAccept("CreatedFromButton")
        assert(createdName=="CreatedFromButton" and addon.db.profile.groupSystem.groups[createdName].shared)
        ShowMenu(frame,"UIShared","UIShared",sharedRow)
        shownMenu[3].func()
        popupData.onAccept("RenamedFromMenu")
        assert(addon.db.profile.groupSystem.groups.RenamedFromMenu.shared and refreshes==3)
    ''')

    options = (ROOT / 'DDingUI_CDM_Option/GroupSystemOptions.lua').read_text(encoding='utf-8-sig')
    delete = options[options.index('function DDingUI:RequestDeleteIconGroup'):options.index('local DIRECTION_VALUES')]
    lua.execute('local DDingUI=addon;local PROTECTED_GROUPS={Cooldowns=true,Buffs=true,Utility=true}\n' + delete)
    lua.execute('''
        local p=addon.db.profile
        local key=p.groupSystem.groups.RenamedFromMenu.sourceGroupKey
        assert(addon.GroupManager:AssignSpell("DeleteSpell","RenamedFromMenu"))
        addon.CustomIcons.RemoveGroup=function(_,sourceKey)
            assert(not p.groupSystem.groups.RenamedFromMenu and not p.groupSystem.spellAssignments.DeleteSpell)
            p.dynamicIcons.groups[sourceKey]=nil
            addon.SpecProfiles:SaveCurrentSpec()
        end
        addon.RefreshConfigGUI=function()end
        function StaticPopup_Show()deleteDialog={};return deleteDialog end
        assert(addon:RequestDeleteIconGroup("RenamedFromMenu"))
        deleteDialog.data.onAccept()
        addon.SpecProfiles:OnSpecChanged(66)
        assert(not p.groupSystem.groups.RenamedFromMenu and not p.dynamicIcons.groups[key])
        assert(p.groupSystem.groups.CreatedFromButton.shared, "empty shared group survives first spec visit")
    ''')

    for file in ('DDingUI_CDM/Core/SpecProfiles.lua',
                 'DDingUI_CDM/Modules/GroupSystem/GroupManager.lua',
                 'DDingUI_CDM_Option/GUI.lua', 'DDingUI_CDM_Option/GroupSystemWorkspace.lua',
                 'DDingUI_CDM_Option/GroupSystemOptions.lua',
                 'DDingUI_CDM_Option/Locales/enUS.lua', 'DDingUI_CDM_Option/Locales/koKR.lua'):
        lua.eval('function(source) assert(loadstring(source)) end')((ROOT / file).read_text(encoding='utf-8-sig'))


if __name__ == '__main__':
    test_shared_icon_groups()
    print('Shared icon groups: passed')
