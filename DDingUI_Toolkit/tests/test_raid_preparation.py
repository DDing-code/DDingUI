from pathlib import Path

from test_ready_check_assistant import panel_runtime

ROOT = Path(__file__).parents[1]


def raid_runtime(locale="koKR"):
    lua = panel_runtime(locale)
    lua.execute('''
        local methods = getmetatable(UIParent).__index
        for _, name in ipairs({"SetMovable", "EnableMouseWheel", "RegisterForDrag"}) do methods[name]=function() end end
        function methods:GetScript(name) return self.scripts[name] end
        function methods:GetName() return self.name end
        function methods:SetAlpha(alpha) self.alpha=alpha end
        UISpecialFrames, SlashCmdList = {}, {}
        timers = {}
        C_Timer.After = function(delay, fn) timers[#timers+1]={delay=delay,fn=fn} end
        function LibStub() return nil end
    ''')
    lua.execute((ROOT / "Modules/RaidPreparation/RaidPreparation.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        module = ns.RaidPreparation
        function module:RegisterLibDurability() end
        function module:UnregisterLibDurability() end
        function module:UpdateDynamicRoster() end
        function module:ApplyRaidBuffStatus() end
        function module:AnnounceReadyCheckStatus() end
        function module:CollectRoster() return self.roster end
        function module:CanOpenAutomatically() return true end
        module:OnEnable()
        module.roster = {}
        for i=1,20 do
            module.roster[i]={name="Player"..i,classToken="PRIEST",subgroup=1,
                ready=true,food=true,flask=true,rune=true,raidBuff=true,weapon=true,durability=100}
        end
        module:ShowWindow(false,true)
        display = module.frame
    ''')
    return lua


def test_compact_summary_and_auto_close_lifecycle():
    for locale in ("koKR", "enUS"):
        lua = raid_runtime(locale)
        lua.execute('''
            assert(display.width==640 and display.height==264 and #display.rows==9)
            assert(not display.readinessGauge and not display.metricBars and not display.columns)
            assert(module.fullyReady and display.closeElapsed==0)
            display.scripts.OnUpdate(display,1.6)
            assert(display.shown and display.alpha<1 and display.alpha>0)
            module.roster[1].food=false
            module:Refresh()
            assert(not module.fullyReady and display.closeElapsed==nil and display.alpha==1)
            assert(display.headline.text==ns.L.RAIDPREP_RESPONDED)
            module.roster[2].ready=false
            module.roster[3].ready=nil
            module.roster[3].durability=nil
            module:Refresh()
            assert(display.summary.text==string.format(ns.L.RAIDPREP_RESPONSES,19,20))
            assert(display.counts.text==string.format(ns.L.RAIDPREP_COUNTS,18,1,1))
            assert(display.checks.text==string.format(ns.L.RAIDPREP_CHECK_COUNT,2))
            assert(#module.visibleRoster==3 and display.rows[3].detail.text:find("?",1,true))
            for i=1,40 do module.roster[i]={name="Player"..i,ready=true,food=false,durability=100} end
            module:Refresh()
            assert(display.height==372 and display.scrollTrack.shown)
            display.scripts.OnMouseWheel(display,-100)
            assert(display.rows[7].record.name=="Player40")
            local count=0
            for _,row in ipairs(display.rows) do if row.shown then count=count+1 end end
            assert(count==7)
            for _,r in ipairs(module.roster) do
                r.food=true;r.flask=true;r.rune=true;r.raidBuff=true;r.weapon=true
            end
            module:Refresh()
            assert(module.fullyReady)
            display.scripts.OnUpdate(display,1.8)
            assert(not display.shown and display.alpha==1)
            module:ShowWindow(false)
            display.scripts.OnUpdate(display,10)
            assert(display.shown and display.closeElapsed==nil)
            module.db.closeAfterReadyCheck=true
            module:HandleReadyFinished()
            timers[#timers].fn()
            assert(display.shown)
            module:HandleReadyCheck("Player1")
            assert(module.ready.player1==true and display.autoOpened)
            local oldTimer=timers[#timers]
            module:ShowWindow(false)
            oldTimer.fn()
            assert(display.shown and not display.autoOpened)
            local driver
            for _,r in ipairs(regions) do if r.scripts.OnEvent and r~=ReadyCheckFrame then driver=r end end
            driver.scripts.OnEvent(driver,"PLAYER_REGEN_DISABLED")
            assert(not display.shown)
            inCombat=true
            module:ShowWindow(false,true)
            assert(not display.shown)
            inCombat=false
            module.roster={}
            module:ShowWindow(false,true)
            assert(not module.fullyReady and display.closeElapsed==nil)
            module:OnDisable()
            assert(not display.shown)
            assert(display.headline:GetStringWidth()<=display.headline.width)
            assert(display.summary:GetStringWidth()<=display.summary.width)
            assert(display.status.width+18 < 640-14-108-6-82)
        ''')
