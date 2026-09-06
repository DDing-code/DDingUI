import re
from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parents[1]
MODULE = "Modules/CalendarInviteAlert/CalendarInviteAlert.lua"


def calendar_runtime(loaded=True):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        ns = {L={}, modules={}}
        ns.DDingToolKit = {version="2.1.6", RegisterModule=function(_, name, module)
            ns.modules[name] = module; module.enabled = false
        end}
        function LibStub() return {NewLocale=function() return ns.L end} end
        function UnitName() return "Test" end
        function GetRealmName() return "Realm" end
        inCombat = false
        function InCombatLockdown() return inCombat end
        calls, sounds, messages, cancellations, flashes, calendarOpens = 0, {}, {}, 0, 0, 0
        SECRET = setmetatable({}, {__lt=function() error("secret comparison") end})
        function ns.IsSecretValue(value) return value == SECRET end
        pendingCount = 0
        C_Calendar = {GetNumPendingInvites=function()
            calls = calls + 1
            if getterError then error("temporarily unavailable") end
            return pendingCount
        end}
        C_GameRules = {IsGameRuleActive=function() return calendarDisabled end}
        Enum = {GameRule={IngameCalendarDisabled=1}}
        function FlashClientIcon() flashes=flashes+1 end
        function ToggleCalendar() calendarOpens=calendarOpens+1 end
        function print(message) messages[#messages+1]=message end
        function ns:RequestSound(request) sounds[#sounds+1]=request end
        function ns:CancelManagedSoundsBySource(source)
            assert(source == "CalendarInviteAlert"); cancellations=cancellations+1
        end
        cancelledKeys = {}
        function ns:CancelManagedSound(key)
            cancelledKeys[key] = true; cancellations=cancellations+1
        end
        function CreateFrame()
            local frame = {events={}, scripts={}}
            function frame:RegisterEvent(event) self.events[event] = true end
            function frame:UnregisterAllEvents() self.events={} end
            function frame:SetScript(event, callback) self.scripts[event]=callback end
            driver = frame
            return frame
        end
        function fire(event) if driver and driver.events[event] then driver.scripts.OnEvent(driver, event) end end
        function ns.CreateCalmPartyAlert(name)
            local frame = {shown=false, subtitle={SetText=function(self,text) self.text=text end}}
            function frame:IsShown() return self.shown end
            local visual = {frame=frame, showCount=0}
            function visual:Apply(db, position) self.db=db; frame.position=position end
            function visual:Show(title, subtitle, options)
                assert(self.db, "visual settings/font must be applied before showing text")
                assert(title ~= nil and subtitle ~= nil)
                self.options=options; frame.shown=true; frame.subtitle.text=subtitle
                frame.titleText=title
                self.state={duration=options.duration, elapsed=0}
                self.showCount=self.showCount+1
            end
            function visual:Hide(immediate) assert(immediate); frame.shown=false; self.state=nil end
            _G[name]=frame
            return visual
        end
    ''')
    for file in ("Core/Database.lua", "Locales/enUS.lua", "Locales/koKR.lua", MODULE, "UI/NewModulePopup.lua"):
        lua.execute((ROOT / file).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    if loaded:
        lua.execute('fire("LOADING_SCREEN_DISABLED")')
    return lua


def test_loading_defers_both_alerts_and_resumes_only_interrupted_notices():
    lua = calendar_runtime(loaded=False)
    lua.execute('''
        ns:InitDB()
        module = ns.CalendarInviteAlert
        pendingCount = 2
        C_DateAndTime = {}
        C_Calendar.GetDayEvent = function() end
        C_Timer = {NewTimer=function(delay, callback)
            timer = {callback=callback, Cancel=function(self) self.cancelled=true end}
            return timer
        end}
        todayReads = 0
        function module:GetTodayEvents()
            todayReads = todayReads + 1
            return {{key="today", hour=20, minute=0, title="Raid"}}, "2026-09-06", 3600
        end
        module:OnEnable()
        fire("PLAYER_ENTERING_WORLD")
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        fire("CALENDAR_UPDATE_EVENT_LIST")
        module:ApplySettings()
        assert(calls == 0 and todayReads == 0 and #sounds == 0 and not timer)

        fire("LOADING_SCREEN_DISABLED")
        assert(#sounds == 1 and module.alertFrame.shown and not module.todayKey)
        local oldTimer = timer
        fire("LOADING_SCREEN_ENABLED")
        assert(oldTimer.cancelled and not module.alertFrame.shown and cancellations > 0)
        oldTimer.callback()
        fire("PLAYER_ENTERING_WORLD")
        assert(#sounds == 1 and timer == oldTimer)
        fire("LOADING_SCREEN_DISABLED")
        assert(#sounds == 2, "interrupted pending alert must restart after loading")

        fire("LOADING_SCREEN_ENABLED")
        pendingCount = 0
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        fire("LOADING_SCREEN_DISABLED")
        assert(#sounds == 3 and sounds[3].key == "today-event")
        assert(module.todayKey == "today", "cancelled invitation must not replay")
        oldTimer = timer
        fire("LOADING_SCREEN_ENABLED")
        oldTimer.callback()
        assert(#sounds == 3 and oldTimer.cancelled and not module.alertFrame.shown)
        fire("LOADING_SCREEN_DISABLED")
        assert(#sounds == 4 and module.todayKey == "today")

        module.alertVisual:Hide(true)
        fire("LOADING_SCREEN_ENABLED")
        fire("LOADING_SCREEN_DISABLED")
        assert(#sounds == 4, "finished today notice must not repeat on zoning")
        fire("LOADING_SCREEN_ENABLED")
        module:OnDisable()
        pendingCount = 3
        fire("LOADING_SCREEN_DISABLED")
        assert(#sounds == 4 and not driver.events.CALENDAR_UPDATE_EVENT_LIST)
        module:OnEnable()
        assert(#sounds == 5, "enabling after loading must not wait for another loading screen")
    ''')


def test_calendar_invite_events_preview_and_settings():
    lua = calendar_runtime()
    lua.execute('''
        assert(calls == 0 and not driver.events.CALENDAR_UPDATE_PENDING_INVITES)
        ns:InitDB()
        assert(ns.db.profile.modules.CalendarInviteAlert == false)
        DDingUIToolkitDB = {profile={modules={MailAlert=true}}}
        ns:InitDB()
        assert(ns.db.profile.modules.CalendarInviteAlert == false and ns.db.profile.modules.MailAlert == true)
        local entries = ns.NewModulePopup:GetEligibleEntries()
        local found = false
        for _, entry in ipairs(entries) do
            if entry.module == "CalendarInviteAlert" then found=true end
        end
        assert(found, "new module notice is missing")
        ns.NewModulePopup:MarkSeen(entries)
        assert(#ns.NewModulePopup:GetEligibleEntries() == 0)

        module = ns.CalendarInviteAlert
        module:OnEnable()
        assert(#sounds == 0 and not module.alertFrame)
        pendingCount = 2
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(#sounds == 1 and #messages == 1 and module.alertFrame.shown)
        assert(sounds[1].source == "CalendarInviteAlert" and sounds[1].key == "pending-invites")
        assert(sounds[1].canQueue and not sounds[1].immediate)
        local shows = module.alertVisual.showCount
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        fire("PLAYER_ENTERING_WORLD")
        assert(#sounds == 1 and module.alertVisual.showCount == shows)
        pendingCount = 1
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(#sounds == 1 and module.alertFrame.subtitle.text == string.format(ns.L.CALENDARALERT_PENDING_TEXT, 1))
        pendingCount = 0
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(not module.alertFrame.shown and cancellations > 0)

        inCombat = true
        pendingCount = 3
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        pendingCount = 4
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(#sounds == 1 and not module.alertFrame.shown)
        inCombat = false
        fire("PLAYER_REGEN_ENABLED")
        assert(#sounds == 2 and module.alertFrame.shown)
        assert(module.alertFrame.subtitle.text == string.format(ns.L.CALENDARALERT_PENDING_TEXT, 4))
        fire("PLAYER_REGEN_ENABLED")
        assert(#sounds == 2)
        inCombat = true
        fire("PLAYER_REGEN_DISABLED")
        assert(not module.alertFrame.shown)
        pendingCount = 5
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        pendingCount = 0
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        inCombat = false
        fire("PLAYER_REGEN_ENABLED")
        assert(#sounds == 2, "cancelled invitation must not notify after combat")

        pendingCount = SECRET
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        getterError = true
        fire("PLAYER_ENTERING_WORLD")
        getterError = false
        for _, invalid in ipairs({-1, 0/0, math.huge, "2"}) do
            pendingCount=invalid; fire("CALENDAR_UPDATE_PENDING_INVITES")
        end
        assert(#sounds == 2)
        pendingCount = 1
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(#sounds == 3)
        module:OnDisable()
        assert(not module.alertFrame.shown and not driver.events.CALENDAR_UPDATE_PENDING_INVITES)
        pendingCount = 10
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        module:CheckPendingInvites()
        assert(#sounds == 3)

        module:EnterEditPreview()
        assert(module.alertVisual.options.persistent and module.alertFrame.shown)
        module.db.position.x = 140
        module.db.animationEnabled = false
        module:ApplySettings()
        assert(module.alertFrame.position.x == 140 and not module.alertVisual.options.animated)
        module:ResetPosition()
        assert(module.db.position.x == 0 and module.db.position.y == -260)
        module:ExitEditPreview()
        assert(not module.alertFrame.shown and #sounds == 3)
        module.db.soundCustomPath="Interface\\\\custom.ogg"
        module:TriggerAlert(true)
        assert(#sounds == 4 and sounds[4].immediate and sounds[4].customPath == module.db.soundCustomPath)
        assert(not module.alertVisual.options.persistent)

        module.db.notifyOnLogin = false
        module:OnEnable()
        fire("PLAYER_ENTERING_WORLD")
        assert(#sounds == 4)
        pendingCount = 11
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(#sounds == 5)
        module:OnDisable()
        module.db.notifyOnLogin = true
        pendingCount = nil
        module:OnEnable()
        assert(#sounds == 5)
        pendingCount = 2
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(#sounds == 6, "delayed login data must still notify once")
        module:OnDisable()
        calendarDisabled = true
        module:OnEnable()
        assert(not driver.events.CALENDAR_UPDATE_PENDING_INVITES and #sounds == 6)
        calendarDisabled = false
        C_Calendar = nil
        module:OnEnable()
        assert(not driver.events.CALENDAR_UPDATE_PENDING_INVITES)

        inCombat = true
        module:OpenCalendar()
        assert(calendarOpens == 0)
        inCombat = false
        module:OpenCalendar()
        assert(calendarOpens == 1)
        CalendarFrame = {IsShown=function() return true end}
        module:OpenCalendar()
        assert(calendarOpens == 1, "Open Calendar must not close an already open calendar")
    ''')


def test_calendar_invite_module_wiring_and_lua_syntax():
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_lua = lua.eval("function(source, name) assert(loadstring(source, name)) end")
    for file in (MODULE, "Core/Database.lua", "Core/Movers.lua", "Config_Data.lua",
                 "Locales/enUS.lua", "Locales/koKR.lua", "UI/Workspace.lua", "UI/NewModulePopup.lua"):
        compile_lua((ROOT / file).read_text(encoding="utf-8-sig"), file)

    config = (ROOT / "Config_Data.lua").read_text(encoding="utf-8-sig")
    panel = config.split('tree.panels["calendarinvitealert"] = {', 1)[1].split("-- CursorTrail", 1)[0]
    assert 'moduleEnableKey = "profile.modules.CalendarInviteAlert"' in panel
    assert 'mod:OnEnable()' in panel and 'mod:OnDisable()' in panel
    assert 'CalendarInviteAlert.soundCustomPath' in panel
    assert 'CalendarInviteAlert.notifyToday' in panel
    assert 'desc = L["CALENDARALERT_NOTIFY_TODAY_DESC"]' in panel
    assert 'label = L["CALENDARALERT_TEST_TODAY"]' in panel
    assert 'calendarinvitealert = "CalendarInviteAlert"' in config
    assert 'Modules\\CalendarInviteAlert\\CalendarInviteAlert.lua' in (ROOT / "DDingUI_Toolkit.toc").read_text(encoding="utf-8-sig")
    workspace = (ROOT / "UI/Workspace.lua").read_text(encoding="utf-8-sig")
    assert '"calendarinvitealert"' in workspace.split('key = "alerts"', 1)[1].split('key = "display"', 1)[0]
    movers = (ROOT / "Core/Movers.lua").read_text(encoding="utf-8-sig")
    mover = movers.split('name = "CalendarInviteAlert"', 1)[1].split("},", 1)[0]
    assert 'dbPath = "CalendarInviteAlert.position"' in mover and 'previewState = "noncombat"' in mover
    keys = set(re.findall(r'L\["([A-Z0-9_]+)"\]', panel + (ROOT / MODULE).read_text(encoding="utf-8-sig")))
    for locale in ("koKR", "enUS"):
        strings = (ROOT / f"Locales/{locale}.lua").read_text(encoding="utf-8-sig")
        assert all(f'L["{key}"]' in strings for key in keys)


def test_today_events_order_filters_deferral_and_daily_deduplication():
    lua = calendar_runtime()
    lua.execute('''
        ns:InitDB()
        module = ns.CalendarInviteAlert
        assert(ns.db.profile.CalendarInviteAlert.notifyToday == true)
        Enum.CalendarStatus = {Invited=0, Available=1, Declined=2, Confirmed=3, Out=4, Standby=5, Signedup=6, NotSignedup=7, Tentative=8}
        serverDate = {year=2026, month=9, monthDay=5, hour=10, minute=30}
        browsedMonth = {year=2027, month=1}
        C_DateAndTime = {GetCurrentCalendarTime=function() return serverDate end}
        C_Calendar.GetMonthInfo = function(offset) assert(offset==0); return browsedMonth end
        dayReads, requests = 0, 0
        dayEvents = {}
        C_Calendar.GetNumDayEvents = function(offset, day)
            dayReads=dayReads+1
            assert(offset == (serverDate.year-browsedMonth.year)*12 + serverDate.month-browsedMonth.month)
            assert(day == serverDate.monthDay)
            if badCount then return badCount end
            return #dayEvents
        end
        C_Calendar.GetDayEvent = function(_, _, index) return dayEvents[index] end
        C_Calendar.OpenCalendar = function()
            requests=requests+1
            if requestError then error("not ready") end
            fire("CALENDAR_UPDATE_EVENT_LIST")
        end
        C_Calendar.SetAbsMonth = function() error("must not change calendar browsing state") end
        C_Calendar.SetMonth = C_Calendar.SetAbsMonth
        C_Calendar.OpenEvent = C_Calendar.SetAbsMonth
        function event(id, hour, minute, title, kind, status, day)
            return {eventID=id, title=title, calendarType=kind or "PLAYER", inviteStatus=status or 1,
                startTime={year=serverDate.year, month=serverDate.month, monthDay=day or serverDate.monthDay, hour=hour, minute=minute}}
        end
        clock, timers = 0, {}
        C_Timer = {NewTimer=function(delay, callback)
            assert(delay > 0)
            local timer = {due=clock+delay, callback=callback, cancelled=false}
            function timer:Cancel() self.cancelled=true end
            timers[#timers+1]=timer
            return timer
        end}
        function advance(seconds)
            local target = clock+seconds
            while true do
                local nextTimer
                for _, timer in ipairs(timers) do
                    if not timer.cancelled and timer.due <= target and (not nextTimer or timer.due < nextTimer.due) then
                        nextTimer=timer
                    end
                end
                local untilTime = nextTimer and nextTimer.due or target
                local visual = module.alertVisual
                if visual and visual.state and visual.frame.shown and not visual.options.persistent then
                    visual.state.elapsed=visual.state.elapsed+untilTime-clock
                    if visual.state.elapsed >= visual.state.duration then visual.frame.shown=false end
                end
                clock=untilTime
                if not nextTimer then return end
                nextTimer.cancelled=true
                nextTimer.callback()
            end
        end
        function activeTimers()
            local count=0
            for _, timer in ipairs(timers) do if not timer.cancelled then count=count+1 end end
            return count
        end

        dayEvents={event("later",21,30,"Guild Raid","GUILD_EVENT",3), event("early",19,0,"Keys"),
            event("festival",0,0,"Holiday","HOLIDAY"), event("lock",12,0,"Lockout","RAID_LOCKOUT"),
            event("reset",12,0,"Reset","RAID_RESET"), event("decline",20,0,"Declined","PLAYER",2),
            event("out",20,0,"Removed","PLAYER",4), event("yesterday",20,0,"Multi-day","PLAYER",1,4)}
        module:OnEnable()
        assert(requests == 1 and #sounds == 1, "synchronous calendar data event must not double-notify")
        assert(module.alertFrame.titleText == string.format(ns.L.CALENDARALERT_TODAY_TITLE,19,0))
        assert(module.alertFrame.subtitle.text == "Keys" and sounds[1].key == "today-event")
        assert(messages[1]:find("19:00",1,true) and activeTimers()==1)
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        fire("PLAYER_ENTERING_WORLD")
        assert(module.alertFrame.shown and module.alertFrame.subtitle.text=="Keys" and #sounds==1)
        advance(6.2)
        assert(module.alertFrame.subtitle.text=="Guild Raid" and #sounds==2)
        advance(6.2)
        local completedSounds=#sounds
        fire("CALENDAR_UPDATE_EVENT_LIST")
        fire("PLAYER_ENTERING_WORLD")
        assert(not module.alertFrame.shown and #sounds==completedSounds and activeTimers()==1)

        inCombat=true
        fire("PLAYER_REGEN_DISABLED")
        inCombat=false
        fire("PLAYER_REGEN_ENABLED")
        assert(#sounds==completedSounds, "an already finished schedule must not replay after combat")
        pendingCount=1
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        advance(6.2)
        assert(#sounds==completedSounds+1 and sounds[#sounds].key=="pending-invites",
            "a later invitation must not replay an already finished schedule")
        pendingCount=0
        fire("CALENDAR_UPDATE_PENDING_INVITES")

        dayEvents[#dayEvents+1] = event("community",22,0,"Community","COMMUNITY_EVENT",8)
        fire("CALENDAR_UPDATE_EVENT_LIST")
        assert(module.alertFrame.subtitle.text=="Community")
        pendingCount=2
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(not module.todayKey and module.alertFrame.titleText==ns.L.CALENDARALERT_ALERT_TITLE)
        assert(cancelledKeys["CalendarInviteAlert:today-event"])
        advance(6.2)
        assert(module.alertFrame.subtitle.text=="Community", "interrupted schedule must resume after invitation alert")
        pendingCount=0
        fire("CALENDAR_UPDATE_PENDING_INVITES")
        assert(module.alertFrame.subtitle.text=="Community" and module.alertFrame.shown)
        assert(cancelledKeys["CalendarInviteAlert:pending-invites"])
        inCombat=true
        fire("PLAYER_REGEN_DISABLED")
        local readsBeforeCombat=dayReads
        fire("CALENDAR_UPDATE_EVENT_LIST")
        advance(30)
        assert(not module.alertFrame.shown and dayReads==readsBeforeCombat and activeTimers()==0)
        inCombat=false
        fire("PLAYER_REGEN_ENABLED")
        assert(module.alertFrame.subtitle.text=="Community" and module.alertFrame.shown)
        dayEvents[#dayEvents]=nil
        fire("CALENDAR_UPDATE_EVENT_LIST")
        assert(not module.alertFrame.shown, "deleted today's event must disappear")

        dayEvents[#dayEvents+1]=event("announce",23,0,"Meeting","GUILD_ANNOUNCEMENT")
        module:EnterEditPreview()
        local soundsBeforePreview=#sounds
        fire("CALENDAR_UPDATE_EVENT_LIST")
        assert(activeTimers()==0 and #sounds==soundsBeforePreview)
        module:ExitEditPreview()
        assert(module.alertFrame.subtitle.text=="Meeting")
        module.db.notifyToday=false
        module:ApplySettings()
        assert(activeTimers()==0 and not module.alertFrame.shown)
        dayEvents[#dayEvents+1]=event("off",23,30,"Disabled")
        fire("CALENDAR_UPDATE_EVENT_LIST")
        assert(not module.alertFrame.shown)
        module.db.notifyToday=true
        module:ApplySettings()
        assert(module.alertFrame.subtitle.text=="Disabled")
        advance(6.2)

        serverDate.hour,serverDate.minute=23,59
        fire("CALENDAR_UPDATE_EVENT_LIST")
        serverDate.monthDay,serverDate.hour,serverDate.minute=6,0,0
        dayEvents={event("next-day",0,0,"Midnight")}
        advance(62)
        assert(requests==2 and module.alertFrame.subtitle.text=="Midnight")
        assert(module.alertFrame.titleText==string.format(ns.L.CALENDARALERT_TODAY_TITLE,0,0))
        advance(6.2)
        module:OnDisable()
        assert(activeTimers()==0)

        -- Late data, request failures and restricted values are retried without consuming an event.
        dayEvents={}
        requestError=true
        module:OnEnable()
        local beforeRequest=#sounds
        assert(activeTimers()==1 and not module.alertFrame.shown)
        requestError=false
        advance(30)
        assert(#sounds==beforeRequest)
        dayEvents={event("late",20,5,"Late data")}
        fire("CALENDAR_UPDATE_EVENT_LIST")
        assert(module.alertFrame.subtitle.text=="Late data")
        advance(6.2)
        local validEvent=event("guard",21,10,"Safe")
        dayEvents={validEvent}
        local beforeSecret=#sounds
        for _, field in ipairs({"title","startTime","eventID","calendarType","inviteStatus"}) do
            local old=validEvent[field]
            validEvent[field]=SECRET
            fire("CALENDAR_UPDATE_EVENT_LIST")
            assert(#sounds==beforeSecret and activeTimers()==1)
            validEvent[field]=old
        end
        validEvent.startTime.hour=SECRET
        fire("CALENDAR_UPDATE_EVENT_LIST")
        assert(#sounds==beforeSecret)
        validEvent.startTime.hour=21
        dayEvents={SECRET}
        fire("CALENDAR_UPDATE_EVENT_LIST")
        assert(#sounds==beforeSecret)
        dayEvents={validEvent}
        for _, invalid in ipairs({SECRET,0/0,math.huge,-1,1.5}) do
            badCount=invalid
            fire("CALENDAR_UPDATE_EVENT_LIST")
            assert(#sounds==beforeSecret)
        end
        badCount=nil
        advance(30)
        assert(#sounds==beforeSecret+1 and module.alertFrame.subtitle.text=="Safe")
        advance(6.2)
        validEvent.startTime.hour=22
        fire("CALENDAR_UPDATE_EVENT_LIST")
        assert(module.alertFrame.titleText==string.format(ns.L.CALENDARALERT_TODAY_TITLE,22,10), "changed start time must notify")
        module:OnDisable()
        assert(activeTimers()==0 and not driver.events.CALENDAR_UPDATE_PENDING_INVITES)
        local afterDisable=#sounds
        advance(86400)
        assert(#sounds==afterDisable)
    ''')
