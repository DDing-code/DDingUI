"""Exercise the real classification and pre-layout ordering in Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent


def test_cdm_icon_order():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        function wipe(t) for key in pairs(t) do t[key]=nil end end
        SECRET={}
        function issecretvalue(value) return rawequal(value,SECRET) end
        function GetTime() return 10 end
        combat,pvp,holding=false,false,false
        function InCombatLockdown() return combat end
        function CreateFrame()
            return {RegisterEvent=function()end, SetScript=function()end, Hide=function()end}
        end
        live,names,dynamic={},{},{}
        addon={db={profile={}}, IsPvPInstance=function()return pvp end}
        addon.CDMCompat={
            IsPublicValue=function(_,v)return not issecretvalue(v)end,
            IsSettingsOpen=function()return false end,
            GetFrameCooldownID=function(_,f)return f.cooldownID end,
            ResolveFrameSpellID=function(_,f)return f.cooldownID end,
            GetFrameCooldownInfo=function()return nil end,
            GetCooldownInfo=function()return nil end,
        }
        addon.CDMHookEngine={
            GetIconMap=function()return live end,
            GetSpellNameForID=function(_,id)return names[id]end,
            GetIconSource=function()return "EssentialCooldownViewer"end,
            GetDefaultGroupForViewer=function()return "Cooldowns"end,
            IsScanHoldActive=function()return holding end,
        }
        addon.FrameController=addon.CDMHookEngine
        addon.DynamicIconBridge={GetActiveIconsForGroup=function()return dynamic end}
        function cdm(id,name,index)
            local icon={cooldownID=id,layoutIndex=index,IsShown=function()return true end}
            names[id]=name
            return {cooldownID=id,spellName=name,icon=icon,isCDM=true}
        end
        function configure(settings)
            settings.enabled=true
            addon.db.profile={groupSystem={autoClassify=true,groups={Cooldowns=settings}}}
            addon.GroupManager:InvalidateClassificationCache()
            return settings
        end
        function classify(entries,changed)
            wipe(live)
            for _,entry in ipairs(entries) do live[entry.cooldownID]=entry.icon end
            local groups
            if changed then groups=addon.GroupManager:ClassifyChanged(changed)
            else groups=addon.GroupManager:ClassifyAll() end
            return groups.Cooldowns
        end
        function order(entries)
            local result={}
            for _,entry in ipairs(entries) do
                result[#result+1]=entry.isDynamic and entry.iconKey
                    or entry.spellName or entry._ddOrderToken:match("^cdm:(.+)$")
            end
            return table.concat(result,",")
        end
        function expect(entries,wanted,why)
            assert(order(entries)==wanted, why..": "..order(entries).." ~= "..wanted)
        end
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    for name in ("GroupManager.lua", "GroupRenderer.lua"):
        source = (ROOT / "DDingUI_CDM/Modules/GroupSystem" / name).read_text(encoding="utf-8-sig")
        lua.execute(source, "DDingUI_CDM", ns)
    lua.execute(r'''
        local manager,renderer=addon.GroupManager,addon.GroupRenderer
        renderer.IsHiddenSourceBuffIcon=function()return false end
        -- Stop the real UpdateGroup after merging/retention/sorting, before UI setters.
        local stop,captured={},nil
        local patched=false
        for index=1,100 do
            local name=debug.getupvalue(renderer.UpdateGroup,index)
            if not name then break end
            if name=="BuildPlacementHash" then
                debug.setupvalue(renderer.UpdateGroup,index,function(entries)
                    captured=entries; error(stop)
                end)
                patched=true; break
            end
        end
        assert(patched,"ordering checkpoint not found")
        local function render(entries,settings,previous)
            renderer.groupFrames.Cooldowns={_managedIcons=previous or {}}
            captured=nil
            local ok,err=pcall(renderer.UpdateGroup,renderer,"Cooldowns",entries,settings)
            assert(not ok and rawequal(err,stop),tostring(err))
            assert(captured)
            return captured
        end

        local a,b,c=cdm(101,"A",1),cdm(102,"B",2),cdm(103,"C",3)
        local settings=configure({})
        expect(classify({c,a,b}),"A,B,C","initial Blizzard order")
        a.icon.layoutIndex=30; b.icon.layoutIndex=20; c.icon.layoutIndex=10
        expect(classify({c,a,b},{[101]=true,[102]=true,[103]=true}),"A,B,C","recycled layout indices")

        -- A temporarily missing source is appended by UpdateGroup's scan-hold path.
        holding=true; b.icon._ddIsManaged=true
        expect(render({a,c},settings,{a.icon,b.icon,c.icon}),"A,B,C","scan hold moved B to the end")
        holding=false

        local placeholder={isPlaceholder=true,_ddOrderToken="cdm:B",icon={}}
        addon.BuffGroupPlaceholders={BuildPlacements=function()return {placeholder}end}
        settings.iconOrder={"cdm:A","cdm:B","cdm:C"}
        expect(render({a,c},settings),"A,B,C","inactive buff placeholder lost its token")
        addon.BuffGroupPlaceholders=nil

        -- An absent manual anchor must not move B across the custom icon X.
        settings=configure({iconOrder={"cdm:A","dyn:X","cdm:C"},
            _cdmStableOrder={"cdm:A","cdm:B","cdm:C"},sourceGroupKey="custom"})
        dynamic={{iconKey="X",frame={IsShown=function()return true end}}}
        local before=order(render(classify({a,b,c}),settings))
        local absent=render(classify({a,b},{[103]=true}),settings)
        local expected=before:gsub(",C","")
        expect(absent,expected,"missing anchor changed surviving relative order")
        expect(render(classify({a,b,c},{[103]=true}),settings),before,"restored anchor changed order")
        assert(table.concat(settings.iconOrder,",")=="cdm:A,dyn:X,cdm:C","runtime rewrote saved order")

        -- Explicit drag order wins over cached order, while unspecified dynamics keep source order.
        settings.iconOrder={"dyn:X","cdm:C","cdm:B","cdm:A"}
        expect(render(classify({a,b,c}),settings),"X,C,B,A","manual reorder ignored")
        settings=configure({sourceGroupKey="custom"})
        a.icon.layoutIndex=1; b.icon.layoutIndex=2; c.icon.layoutIndex=3
        dynamic={{iconKey="Y",frame={}}, {iconKey="X",frame={}}}
        expect(render(classify({c,b,a}),settings),"A,B,C,Y,X","default dynamic source order")
        b.icon.layoutIndex=SECRET
        expect(render(classify({c,b,a}),settings),"A,B,C,Y,X","secret layout index lost stable order")
        addon.db.profile.dynamicIcons={groups={custom={icons={"Y","X"}}}}
        local retainedY={_ddIconKey="Y",IsShown=function()return true end}
        dynamic={{iconKey="X",frame={}}}; combat=true
        expect(render(classify({a,b,c}),settings,{retainedY}),"A,B,C,Y,X","retained dynamic lost source order")
        combat=false

        -- The same group name in another specialization/profile must not inherit PvP ranks.
        pvp=true; dynamic={}
        settings=configure({_cdmStableOrder={"cdm:A","cdm:B","cdm:C"}})
        expect(render(classify({a,b,c}),settings),"A,B,C","initial PvP order")
        settings=configure({_cdmStableOrder={"cdm:C","cdm:B","cdm:A"}})
        expect(render(classify({a,b,c}),settings),"C,B,A","PvP cache leaked across profiles")
        addon.SpecProfiles={lastSpecID=2}
        settings._cdmStableOrder[1],settings._cdmStableOrder[3]="cdm:A","cdm:C"
        expect(render(classify({a,b,c}),settings),"A,B,C","in-place spec restore kept old PvP order")
        settings._cdmStableOrder=nil
        a.icon.layoutIndex=3; b.icon.layoutIndex=2; c.icon.layoutIndex=1
        expect(render(classify({a,b,c}),settings),"C,B,A","default order reset kept old PvP ranks")
        pvp=false
        print("CDM ordering: classification, retained frames, missing anchors, mixed icons and profiles OK")
    ''')


if __name__ == "__main__":
    test_cdm_icon_order()
