"""python test_custom_aura_visibility.py — actual Lua bar/options/container paths.

WoW frames are doubles; protected client rendering/taint still needs an in-game check.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent
RB = ROOT / "DDingUI_CDM/Modules/ResourceBars"


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        function noop() end
        RefreshOptions=noop
        function node(parent)
            local n = {parent=parent, alpha=1, shown=true, width=200, height=20}
            local methods = {
                SetAlpha=function(s,v) s.alpha=v end,
                Show=function(s) s.shown=true end, Hide=function(s) s.shown=false end,
                SetShown=function(s,v) s.shown=v end,
                GetParent=function(s) return s.parent end,
                SetParent=function(s,v) s.parent=v end,
                GetWidth=function(s) return s.width end, GetHeight=function(s) return s.height end,
                GetFrameLevel=function() return 1 end, GetFrameStrata=function() return 'MEDIUM' end,
                SetValue=function(s,v) s.value=v end,
                SetText=function(s,v) s.text=v end, GetText=function(s) return s.text end,
                GetStatusBarTexture=function() return node() end,
                SetEnabled=function() assert(not combat, 'protected mutation in combat') end,
                AddAuraSlot=function(s,_,_,info) s.initialize=info.initializeFrame end,
            }
            return setmetatable(n, {__index=function(_,k)
                if methods[k] then return methods[k] end
                if k:match('^Set') or k:match('^Clear') or k:match('^Enable')
                    or k=='UpdateAllAuras' then return noop end
            end})
        end
        function CreateFrame(_,_,parent) return node(parent) end
        UIParent=node()
        function InCombatLockdown() return combat or false end
        UnitAffectingCombat=InCombatLockdown
        function GetTime() return 100 end
        C_Secrets={ShouldAurasBeSecret=InCombatLockdown}
        C_AddOns={IsAddOnLoaded=function() return true end, LoadAddOn=noop}
        C_UnitAuras=setmetatable({}, {__index=function() error('unexpected aura observation') end})
        DDingUI={ResourceBars={}, Scale=function(_,v) return v end,
            ScaleBorder=function(_,v) return v end, GetFont=function() return 'font' end,
            GetTexture=function() return 'texture' end, ResolveAnchorFrame=function() return UIParent end}
        ns={Addon=DDingUI}
        ResourceBars=DDingUI.ResourceBars
        ResourceBars.SetTrackedBuffHiddenInCDM=noop
        ResourceBars.UpdateBuffTrackerBarTicks=noop
        host=node(UIParent)
        for _,k in ipairs({'StatusBar','Background','Border','TextFrame','TextValue','DurationText','TickFrame'}) do
            host[k]=node(host)
        end
        function GetTrackedBuffBar() return host end
        function ResolveTrackedAnchorName(v) return v end
        function ResolveTrackedFrame() return nil end
        function ResolveTrackedAuraCooldownID() return 0 end
        function GetManualStacks() return manualCount or 0, 200 end
        function ResolveTrackedStacks() return manualCount or 0 end
        function HasTrackedAuraData() return false end
        function EvaluateAlerts() return nil end
        ApplyAlertActions=noop; ScheduleAlertEvaluation=noop; GetGroupAlertColorOverride=noop
        function ShouldApplyTrackerFramePosition() return false end
        function IsAccessibleNumber(v) return type(v)=='number' end
        function GetPreviewValues() return 1, 10 end
        UpdateTextureBorderSize=noop; UpdateTextureBorderColor=noop; ShowTextureBorder=noop
        cdmHideState={}; buildVersion=120100
        L=setmetatable({}, {__index=function(_,k) return k end})
        options={}; index=1; orderBase=1; hiddenIfCollapsed=function() return false end
        tracker={spellID=33763, isAura=true, displayType='bar', settings={
            width=200,height=20,barFillMode='stacks',showStacksText=false,showTicks=false}}
        function GetTrackedBuff() return tracker end
        function GetTrackedBuffs() return {tracker} end
        function DDingUI:UpdateBuffTrackerBar()
            ResourceBars:UpdateSingleTrackedBuffBar(1,tracker,{})
        end
    ''')
    lua.execute((RB / "TrackedAuraContainer.lua").read_text(encoding="utf-8-sig"), "CDM", lua.globals().ns)
    lua.execute('''
        Engine=DDingUI.TrackedAuraContainer
        DDingUI.TrackedAuraFrameResolver={
            ShouldReadLegacy=function() return false end,
            AttachAuraContainer=function(_,t,h,s) return Engine:Attach(t,h,s) end,
        }
    ''')
    bar = (RB / "BuffTrackerBar.lua").read_text(encoding="utf-8-sig")
    lua.execute(bar[bar.index("function ResourceBars:UpdateSingleTrackedBuffBar("):
                    bar.index("function ResourceBars:UpdateSingleTrackedBuffRing(")])
    opts = (ROOT / "DDingUI_CDM_Option/BuffTrackerOptions.lua").read_text(encoding="utf-8-sig")
    start = opts.index('    options["tracked" .. index .. "_hideWhenZero"]')
    end = opts.index('\n    options[', opts.index('    options["tracked" .. index .. "_onlyInCombat"]') + 10)
    helper = opts[opts.index("local function CreateTrackedAlwaysShowOption("):
                  opts.index("local function CreateTrackedSettingOption(")]
    lua.execute(helper + opts[start:end])
    lua.execute('''
        assert(options.tracked1_hideWhenZero.hidden(), 'zero-stack toggle removed for auras')
        tracker.trackingMode='spell'
        assert(not options.tracked1_hideWhenZero.hidden(), 'spell charge option retained')
        tracker.trackingMode=nil
        tracker.settings.hideWhenZero=false
        assert(options.tracked1_showInCombat.get()==true, 'legacy inactive display reflected in UI')
        options.tracked1_showInCombat.set(nil,false)
        assert(options.tracked1_showInCombat.get()==false)
        assert(tracker.settings.hideWhenZero==true, 'OFF must override legacy inactive display')
        assert(options.tracked1_showInCombat.name:match('Always show$'))
        Engine:Sync({tracker})
        DDingUI:UpdateBuffTrackerBar()
        assert(Engine:GetDiagnostics().buildSuccess==1)
        local binding=host._auraContainerBinding
        for _,fighting in ipairs({false,true,false}) do
            combat=fighting
            for _,hide in ipairs({true,false,true}) do
                for _,always in ipairs({false,true,false}) do
                    for _,only in ipairs({false,true,false}) do
                        tracker.settings.hideWhenZero=hide -- old saved value must not override the toggle
                        options.tracked1_showInCombat.set(nil,always)
                        options.tracked1_onlyInCombat.set(nil,only)
                        local allowed=not only or combat
                        local idle=always
                        assert(options.tracked1_showInCombat.get()==always)
                        assert(tracker.settings.hideWhenZero==not always)
                        assert(host.shown==(allowed and idle), 'inactive bar visibility')
                        assert(host.Background.alpha==(idle and 1 or 0), 'background must restore after toggling')
                        assert(host.Border.alpha==host.Background.alpha)
                        assert(host.StatusBar.alpha==0, 'native bar owns active progress')
                        assert(binding.proxy.shown==allowed, 'combat gate must reach active native aura')
                        assert(host._auraContainerBinding==binding, 'visibility must not rebuild protected bindings')
                    end
                end
            end
        end
        assert(Engine:GetDiagnostics().buildSuccess==1)
        -- Manual trackers use the same consolidated toggle without a native binding.
        tracker.trackingMode='manual'; Engine:Sync({tracker})
        for _,fighting in ipairs({false,true}) do
            combat=fighting
            for _,count in ipairs({0,1}) do
                manualCount=count
                for _,hide in ipairs({false,true}) do
                    for _,always in ipairs({false,true}) do
                        for _,only in ipairs({false,true}) do
                            tracker.settings.hideWhenZero=hide
                            options.tracked1_showInCombat.set(nil,always)
                            tracker.settings.onlyInCombat=only
                            DDingUI:UpdateBuffTrackerBar()
                            assert(host.shown==((not only or combat) and (count>0 or always)))
                        end
                    end
                end
            end
        end
        isInMoverMode=true; combat=false; manualCount=0
        DDingUI:UpdateBuffTrackerBar(); assert(host.shown, 'mover preview remains visible')
    ''')
    print("PASS: aura visibility toggles, combat transitions, binding reuse, manual mode and UI defaults")


if __name__ == "__main__":
    main()
