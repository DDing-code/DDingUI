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
        local measure=methods.GetStringWidth
        function methods:GetStringWidth()
            local text=self.text
            self.text=(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local width=measure(self)
            self.text=text
            return width
        end
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
            assert(display.width==640 and display.height==286 and #display.rows==9)
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
            assert(display.height==394 and display.scrollTrack.shown)
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


def test_incomplete_names_are_separate_fitted_and_updated():
    for locale in ("koKR", "enUS"):
        lua = raid_runtime(locale)
        lua.execute('''
            GameTooltip = {shown=false, lines={}}
            function GameTooltip:SetOwner(owner) self.owner=owner; self.lines={} end
            function GameTooltip:GetOwner() return self.owner end
            function GameTooltip:AddLine(text,r,g,b,wrap)
                assert(wrap==nil or type(wrap)=="boolean")
                self.lines[#self.lines+1]={text=text,r=r,g=g,b=b}
            end
            function GameTooltip:Show() self.shown=true end
            function GameTooltip:Hide() self.shown=false end
            function GameTooltip:IsShown() return self.shown end
            RAID_CLASS_COLORS={PRIEST={r=1,g=1,b=1},MAGE={r=0.25,g=0.78,b=0.92}}
            assert(not display.declinedNames.shown and not display.waitingNames.shown and display.hint.shown)
            module.roster[1].ready=false
            module.roster[1].name="Declined-Realm"
            module.roster[2].ready=nil
            module.roster[2].name="Waiting-Realm"
            module.roster[2].classToken="MAGE"
            module.roster[3].food=false
            module:Refresh()
            assert(display.headline.text==ns.L.RAIDPREP_INCOMPLETE)
            assert(display.declinedNames.text.text==ns.L.RAIDPREP_NOT_READY..": |cffffffffDeclined|r")
            assert(display.waitingNames.text.text==ns.L.RAIDPREP_WAITING..": |cff40c7ebWaiting|r")
            assert(not display.hint.shown)
            assert(#display.declinedNames.records==1 and #display.waitingNames.records==1)
            assert(not display.declinedNames.text.text:find("Player3",1,true), "a ready player missing food is not unready")

            display.declinedNames.scripts.OnEnter(display.declinedNames)
            assert(GameTooltip.shown and GameTooltip.lines[2].text=="Declined-Realm")
            assert(GameTooltip.lines[2].g==1)
            module.roster[4].name="Second-Realm";module.roster[4].ready=false;module.roster[4].classToken="MAGE"
            module:Refresh()
            assert(display.declinedNames.text.text:find("|cffffffffDeclined|r, |cff40c7ebSecond|r",1,true))
            assert(GameTooltip.lines[3].g==0.78)
            module.roster[4].classToken=nil;module:Refresh()
            assert(display.declinedNames.text.text:find("|cffd1d9e6Second|r",1,true))
            module.roster[4].ready=true
            module.roster[1].ready=true
            module:Refresh()
            assert(not display.declinedNames.shown and not GameTooltip.shown)
            assert(display.waitingNames.shown)

            for i=1,40 do
                module.roster[i]={name=string.rep("가",12)..i.."-Realm",classToken="PRIEST",ready=false}
            end
            module:Refresh()
            local line=display.declinedNames
            assert(#line.records==40 and line.text.text:find(" / ",1,true), "long lists need a remaining count")
            local _,starts=line.text.text:gsub("|c", "")
            local _,ends=line.text.text:gsub("|r", "")
            assert(starts>0 and starts==ends and line.text.text:find("|r / ",1,true))
            assert(line.text:GetStringWidth()<=line.width and line.text.width==line.width)
            assert(not display.waitingNames.shown and #display.waitingNames.records==0)
            local before=line.text.text
            display.scripts.OnMouseWheel(display,-100)
            assert(line.text.text==before, "names must not depend on the lower checklist's scroll offset")
            line.scripts.OnEnter(line)
            assert(#GameTooltip.lines==41 and GameTooltip.lines[41].text==module.roster[40].name)
            module.roster[40].ready=true
            module:Refresh()
            assert(GameTooltip.shown and #GameTooltip.lines==40, "hovered list must update when someone replies")

            for _, record in ipairs(module.roster) do record.ready=nil end
            module:Refresh()
            assert(not line.shown and #line.records==0 and not GameTooltip.shown)
            line=display.waitingNames
            assert(#line.records==40 and line.text:GetStringWidth()<=line.width)
            line.scripts.OnEnter(line)
            assert(#GameTooltip.lines==41 and GameTooltip.lines[1].text==ns.L.RAIDPREP_WAITING)
            local first=display.declinedNames.points.TOPLEFT
            local second=display.waitingNames.points.TOPLEFT
            assert(-first.y+display.declinedNames.height <= -second.y)
            assert(-second.y+line.height < -display.counts.points.TOPLEFT.y)
            assert(-display.counts.points.TOPLEFT.y+20 < -display.rows[1].points.TOPLEFT.y)
            display:Hide()
            assert(not GameTooltip.shown, "closing preparation must close its names tooltip")
            module.roster={}
            module:ShowWindow(false)
            assert(display.hint.shown and not display.declinedNames.shown and not display.waitingNames.shown)
        ''')
