"""Exercise real item readiness, native/dynamic glow decisions, events and shared options."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
from test_dashboard_workspace import STUBS

ROOT = Path(__file__).parent


def section(text, start, end):
    return text[text.index(start):text.index(end)]


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute('''
        locale={};LibStub=function()return {GetLocale=function()return locale end}end
        function InCombatLockdown()return combat==true end
        function noop()end
        local frame=getmetatable(UIParent)
        frame.Clear=noop
        frame.RegisterEvent=function(self,event)self.events=self.events or {};self.events[event]=true end
        frame.RegisterUnitEvent=frame.RegisterEvent
        C_Timer.After=noop
        C_Spell={GetSpellCooldown=function()return {isActive=false}end}
        C_Item={GetItemSpell=function(id)if spells[id] then return "Use",spells[id] end end,
            GetItemCount=function(id)return bag[id] or 0 end}
        spells={[2]=200};bag={[1]=1,[2]=1}
        addon.CustomIcons={ManagedVisualLocked=function()return false end,
            RestoreActiveIconVisual=noop,SuppressIconFrameVisibility=noop,StopIconDesatUpdater=noop,
            ApplyTrackedTrinketEffect=function()return false end,
            ApplyActiveTrinketEffectState=function()return false end,StopTrackedTrinketEffectGlow=noop,
            GetEquippedSlotItemID=function()return equipped end}
        addon.IconCustomization={UpdateDynamicIconGlow=function(_,frame,settings,show)frame.glowing=show==true end,
            ApplyDynamicIconState=function(_,frame,settings,active,ready)frame.ready=ready end}
        addon.NativeTrinketOverlay={OwnsBaseFrame=function()return nativeOwns==true end}
        function newIcon()
            local f=CreateFrame("Frame",nil,UIParent)
            f.glowing=false
            f.icon=f:CreateTexture();f.cooldown=CreateFrame("Cooldown",nil,f)
            f.count=f:CreateFontString();f.count:SetFont("font",12,"")
            return f
        end
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    custom = (ROOT / 'DDingUI_CDM/Modules/CustomIcons/CustomIcons.lua').read_text(encoding='utf-8-sig')
    native = (ROOT / 'DDingUI_CDM/Modules/IconCustomization/IconCustomization.lua').read_text(encoding='utf-8-sig')
    lua.execute('''
        local DDingUI,CustomIcons=addon,addon.CustomIcons
        local ITEM_SPELL_MAP,ITEM_COMBAT_LOCKOUT_ITEMS={},{}
        local function SafeNumber(v)return type(v)=="number" and v or nil end
        local EnsureCooldownSpanOwner,SetStableIconTexture=noop,noop
        local function ResolveItemTexture(id)return id end
        local function ResolveItemCooldownSpan()return 1,20,onCooldown==true,true end
        local function ApplyCooldownSpan()return true end
        local function ApplyInventorySlotCooldown()return onCooldown==true end
        local function IsItemCombatLocked()return locked==true end
        local function IsFlightHideAlphaLocked()return false end
        local function GetRealSpellCooldownDuration()end
        local function ResolveTrinketProcAuraForIcon()return aura end
        local function GetAuraNumberFieldSafe(data,key)return data[key] end
    ''' + section(custom, 'local function ResolveUsableItemSpellID', 'local function ClearCooldownSpan')
        + section(custom, 'function CustomIcons:GetPreferredItem', 'local function UpdateSpellIconFrame')
        + section(custom, 'local function UpdateSlotIcon', 'local function ResolveTrinketProcAuraForIcon')
        + section(custom, 'local function UpdateTrinketProcIcon', '-- ------------------------\n-- Aura')
        + section(custom, 'function CustomIcons:UpdateDynamicIconStateGlow', 'MarkCustomTimedAuraActive = function')
        + '\nTestItem=UpdateItemIcon;TestSlot=UpdateSlotIcon;TestProc=UpdateTrinketProcIcon')
    lua.execute('''
        ci=addon.CustomIcons
        -- Reuse the same frame when swapping on-use/passive/empty slots (including cached spell IDs).
        for _,native in ipairs({false,true}) do
            nativeOwns=native
            for _,showCooldown in ipairs({false,true}) do
                for _,update in ipairs({TestSlot,TestProc,TestItem}) do
                    local f=newIcon()
                    local data={type="item",slotID=13,settings={showItemCooldown=showCooldown}}
                    for _,id in ipairs({2,1,2,0,1}) do
                        equipped=id~=0 and id or nil;data.id=id
                        for _,cooling in ipairs({false,true}) do
                            onCooldown=cooling;update(f,data)
                            assert(f._ddCustomIconReady==(id==2 and not cooling),
                                "passive/empty/cooling item incorrectly ready")
                        end
                    end
                end
            end
        end
        local f=newIcon();local data={type="item",id=2,settings={}}
        onCooldown=false;bag[2]=0;TestItem(f,data);assert(not f._ddCustomIconReady)
        bag[2]=1;locked=true;TestItem(f,data);assert(not f._ddCustomIconReady);locked=false
        nativeOwns=false;equipped=1;aura={duration=20,expirationTime=25,applications=1}
        TestProc(f,{slotID=13,settings={}})
        assert(f._ddCustomIconProcActive and not f._ddCustomIconReady, "passive proc still activates")
        aura=nil
    ''')
    # Native CDM uses the actual decision function; drawing and cooldown APIs are controlled doubles.
    lua.execute('''
        local IconCustomization=addon.IconCustomization
        local L=locale
        local function GetFrameData(frame)frame.state=frame.state or {};return frame.state end
        local function GetSpellIDFromIcon()return 200 end
        local function GetViewerType()return "Essential" end
        local function GetSpellCustomization()return glowSettings end
        local function IsIconActiveState()return active==true end
        local function IsSpellOnCooldown()return onCooldown==true end
        local function GetChargeState()return true,maxCharges==true end
        local ApplyNativeStateAppearance,UpdateNativeStateSounds=noop,noop
        local function ShowReadyGlow(frame)frame.glowing=true;GetFrameData(frame).readyGlowActive=true end
        local function HideReadyGlow(frame)frame.glowing=false;GetFrameData(frame).readyGlowActive=false end
    ''' + section(native, 'local function UpdateReadyGlow', '-- Hook cooldown frame')
        + section(native, 'local function BuildGlowContextMenuItems', 'local function BuildThresholdContextMenuItem')
        + '\nTestNative=UpdateReadyGlow;TestMenu=BuildGlowContextMenuItems')
    lua.execute('''
        -- Both display paths, old/new ready settings, combat entry/exit and other glow reasons.
        for _,kind in ipairs({"native","dynamic"}) do
            for _,legacy in ipairs({false,true}) do
                local f=newIcon();local data={type="spell",settings={}}
                glowSettings={cooldownReadyGlowCombatOnly=true}
                glowSettings[legacy and "readyGlow" or "cooldownReadyGlow"]=true
                data.settings.customStateGlow=glowSettings
                local function update()
                    f._ddCustomIconReady=not onCooldown;f._ddCustomIconActive=active
                    f._ddCustomIconAtMaxCharges=maxCharges
                    if kind=="native" then TestNative(f,true) else ci:UpdateDynamicIconStateGlow(f,data) end
                end
                for _,fighting in ipairs({false,true,false}) do
                    combat=fighting;active=false;maxCharges=false;onCooldown=false
                    update();assert(f.glowing==fighting)
                    if kind=="dynamic" then assert(f.ready, "combat glow filter must not alter readiness") end
                    onCooldown=true;update();assert(not f.glowing)
                end
                combat=false;onCooldown=false;glowSettings.cooldownReadyGlowCombatOnly=nil
                update();assert(f.glowing, "opt-out preserves ready glow outside combat")
                glowSettings.cooldownReadyGlowCombatOnly=true;glowSettings.activeGlow=true;active=true
                update();assert(f.glowing, "combat-only readiness must not suppress active glow")
                active=false;glowSettings.activeGlow=nil;glowSettings.maxChargesGlow=true;maxCharges=true
                update();assert(f.glowing)
                maxCharges=false;glowSettings.maxChargesGlow=nil
                glowSettings.readyGlow=true;glowSettings.glowTrigger="active";active=true
                update();assert(f.glowing, "legacy active glow unaffected")
            end
        end
        local settings={}
        local function build()
            return TestMenu(function()return settings end,function(k,v)settings[k]=v end,noop,noop,"ready",nil,false,{ready=true})
        end
        local function toggle()
            for _,entry in ipairs(build()) do
                if entry.text=="Ready Glow Only in Combat" then entry.func();return end
            end
            error("missing shared context-menu option")
        end
        toggle();assert(settings.cooldownReadyGlowCombatOnly)
        toggle();assert(not settings.cooldownReadyGlowCombatOnly)
    ''')
    # Actual shared state-studio getters/setters and reset for CDM and dynamic icons.
    lua.execute('''
        addon.GetGroupIconDetailSelection=function()return selection end
        addon.GetGroupIconDetailKey=function()return "chosen" end
        addon.CustomIcons.RefreshDynamicIcon=noop;addon.IconCustomization.RefreshAllGlows=noop
        addon._groupStateStudioSelection={["Drink|chosen"]="ready"}
        addon.db.profile={dynamicIcons={iconData={mana={type="item",id=2,settings={}}}}}
    ''')
    lua.execute((ROOT / 'DDingUI_CDM_Option/GroupStateStudio.lua').read_text(encoding='utf-8-sig'), 'test', ns)
    lua.execute('''
        for _,kind in ipairs({"dynamic","cdm"}) do
            selection={_gridKind=kind,_gridDynamicIconKey="mana",_gridSpellID=200,_gridViewerType="Essential"}
            local args=addon:BuildGroupStateStudioArgs("Drink")
            assert(not args.readyGlowCombatOnly.get())
            args.glowEnabled.set(nil,true);args.readyGlowCombatOnly.set(nil,true)
            assert(args.readyGlowCombatOnly.get())
            local stored=kind=="dynamic" and addon.db.profile.dynamicIcons.iconData.mana.settings.customStateGlow
                or addon.db.profile.iconCustomization.spells["200_Essential"]
            assert(stored.cooldownReadyGlow and stored.cooldownReadyGlowCombatOnly)
            args.resetState.func();assert(not args.readyGlowCombatOnly.get() and not args.glowEnabled.get())
        end
    ''')
    # Verify combat events call the actual runtime refresh routes without unrelated game events.
    lua.execute('''
        local DDingUI,IconCustomization=addon,addon.IconCustomization
        local hookedFrames={}
        local function RefreshAllReadyGlows()nativeRefreshes=(nativeRefreshes or 0)+1 end
    ''' + section(native, 'function IconCustomization:Initialize()', '-- Initialize on load'))
    lua.execute('''
        addon.IconCustomization:Initialize()
        local f=addon.IconCustomization.__eventFrame
        for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do
            assert(f.events[event]);f.scripts.OnEvent(f,event)
        end
        assert(nativeRefreshes==2)
    ''')
    lua.execute('''
        local DDingUI,CustomIcons=addon,ci
        local runtime={}
        local RebuildTimeSpiralGlowFilters,ClearItemCombatLockouts=noop,noop
        local function UpdateAllIcons(_,filter)assert(filter=="all");dynamicRefreshes=(dynamicRefreshes or 0)+1 end
    ''' + section(custom, 'local function SetCustomIconEventsEnabled', 'local function BuildTimedAuraDebugBucket')
        + '\nEnsureEventFrame();TestEventFrame=runtime.eventFrame')
    lua.execute('''
        for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do
            assert(TestEventFrame.events[event]);TestEventFrame.scripts.OnEvent(TestEventFrame,event)
        end
        assert(dynamicRefreshes==2)
    ''')
    options = (ROOT / 'DDingUI_CDM_Option/GroupSystemOptions.lua').read_text(encoding='utf-8-sig')
    lua.execute(section(options, 'local function CopyGlowSettings', 'local function CollectGroupGlowSpellKeys') + '''
        local copy=CopyGlowSettings({cooldownReadyGlowCombatOnly=true,iconSize=99})
        assert(copy.cooldownReadyGlowCombatOnly and not copy.iconSize)
        local target=MergeGlowSettings({cooldownReadyGlowCombatOnly=true,iconSize=42},{})
        assert(not target.cooldownReadyGlowCombatOnly and target.iconSize==42)
    ''')
    for file in ('DDingUI_CDM/Modules/CustomIcons/CustomIcons.lua',
                 'DDingUI_CDM/Modules/IconCustomization/IconCustomization.lua',
                 'DDingUI_CDM_Option/GroupSystemOptions.lua'):
        lua.eval('function(s) assert(loadstring(s)) end')((ROOT / file).read_text(encoding='utf-8-sig'))
    print('Ready glow: passed')


if __name__ == '__main__':
    main()
