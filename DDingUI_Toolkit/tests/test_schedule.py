"""일정 캐시/비밀값/로딩 경계와 실제 StyleLib 월 보드의 동작을 검사한다."""
from pathlib import Path
from datetime import date
import re

from test_edit_mode import HARNESS
from ui_runtime import runtime

ROOT = Path(__file__).resolve().parents[1]


def load(lua, file):
    lua.execute((ROOT / file).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)


def schedule_runtime(window=False, locale="koKR"):
    lua = runtime()
    lua.execute(HARNESS)
    lua.execute('''
        ns.modules={}
        ns.IsSecretValue=issecretvalue
        function ns.DDingToolKit:RegisterModule(name,mod) ns.modules[name]=mod end
        function ns.DDingToolKit:OpenConfig(key) configKey=key end
        function LibStub:GetLocale() return ns.L end
        local oldLibStub=LibStub
        setmetatable(LibStub,{__call=function(_,key,silent)
            if key=="AceLocale-3.0" then return {NewLocale=function() return ns.L end} end
            return oldLibStub:GetLibrary(key,silent)
        end})
        serverEpoch=1792360800
        function GetServerTime() return serverEpoch end
        function time() return serverEpoch end
        function date() return {year=2026,month=10,day=19} end
        playerName="띵띵"
        function UnitName() return playerName end
        function UnitClass() return "사제","PRIEST" end
        function GetGuildInfo() return "띵스튜디오" end
        RAID_CLASS_COLORS={PRIEST={r=1,g=1,b=1},SHAMAN={r=0,g=0.44,b=0.87},MONK={r=0,g=1,b=0.6}}
        C_GameRules={IsGameRuleActive=function() return calendarDisabled or false end}
        Enum={GameRule={IngameCalendarDisabled=1}}
        calendarNow={year=2026,month=10,monthDay=19,hour=15,minute=0}
        weeklySeconds=3*86400-7*3600
        C_DateAndTime={GetCurrentCalendarTime=function() assert(not combat); return calendarNow end,
            GetSecondsUntilWeeklyReset=function() return weeklySeconds end}
        selectedMonth=12 -- 블리자드 달력을 다른 달에 둔 경우
        calendarReads,calendarOpens,raidRequests=0,0,0
        C_Calendar={OpenCalendar=function() assert(not combat); calendarOpens=calendarOpens+1 end}
        function C_Calendar.GetMonthInfo(offset)
            assert(not combat); calendarReads=calendarReads+1
            local year=2026+math.floor((selectedMonth+offset-1)/12)
            local month=(selectedMonth+offset-1)%12+1
            return {year=year,month=month,numDays=ns.Schedule:MonthDays(year,month)}
        end
        function C_Calendar.GetNumDayEvents(offset,day)
            assert(not combat); calendarReads=calendarReads+1
            return selectedMonth+offset==10 and day==22 and 2 or 0
        end
        function C_Calendar.GetDayEvent(_,_,index)
            if badEvent then return badEvent end
            if index==1 then return {eventID="100",title="길드 신화 키식스 1~4넴",calendarType="GUILD_EVENT",inviteStatus=1,
                eventType=0,modStatus="",startTime={year=2026,month=10,monthDay=22,hour=20,minute=30}} end
            return {eventID="101",title="할로윈 축제",calendarType="HOLIDAY"}
        end
        function C_Calendar.GetHolidayInfo()
            return {name="할로윈 축제",texture=123,startTime={year=2026,month=10,monthDay=18},endTime={year=2026,month=11,monthDay=1}}
        end
        function RequestRaidInfo() assert(not combat); raidRequests=raidRequests+1 end
        function GetNumSavedInstances() return lockoutCount or 1 end
        function GetSavedInstanceInfo()
            return "키식스", 42, 3*86400, 15, secretLockout and SECRET or true, false, 42, true, 20, "영웅", 8, 6
        end
        ns.UI={ShowConfirmation=function(_,_,opts) confirmation=opts end}
        function ns.Print(msg) lastMessage=msg end
        local M=getmetatable(UIParent).__index
        for _,key in ipairs({"SetShadowOffset","SetShadowColor","SetMask","SetOffset"}) do M[key]=function() end end
        function M:SetStatusBarTexture(path) self.barTexture=path end
        function M:SetStatusBarColor(...) self.barColor={...} end
        function M:GetName() return self.name end
    ''')
    for name in ("Core.lua", "Colors.lua", "Gradient.lua", "Motion.lua", "DesignTokens.lua", "Widgets.lua", "CascadingMenu.lua"):
        lua.execute((ROOT / "Libs/DDingUI_StyleLib" / name).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit")
    load(lua, "Core/Database.lua")
    load(lua, "Locales/enUS.lua")
    if locale == "koKR":
        load(lua, "Locales/koKR.lua")
    load(lua, "Modules/Schedule/Schedule.lua")
    if window:
        load(lua, "Modules/Schedule/Window.lua")
    lua.execute("ns:InitDB(); S=ns.Schedule; S:OnEnable()")
    return lua


def ready(lua):
    lua.execute('Emit("LOADING_SCREEN_DISABLED"); Emit("CALENDAR_UPDATE_EVENT_LIST",true); ExpireTimers(); Emit("UPDATE_INSTANCE_INFO")')


def test_calendar_cache_is_atomic_and_merges_characters_without_moving_native_calendar():
    lua = schedule_runtime()
    lua.execute("assert(calendarReads==0 and calendarOpens==0)")
    ready(lua)
    lua.execute('''
        local char=S.cache.characters["띵띵-아즈샤라"]
        assert(#char.events==1 and #char.lockouts==1 and #S.cache.common.holidays==1)
        assert(char.events[1].hour==20 and char.events[1].minute==30 and selectedMonth==12)
        playerName="띵슈"; S:Refresh()
        S.cache.characters["띵슈-아즈샤라"].events[1].inviteStatus=8
        local items,visible=S:GetDayItems(S:DayNumber(2026,10,22))
        assert(visible==2 and items[1].kind=="reset" and items[1].time=="08:00")
        assert(items[2].kind=="event" and #items[2].members==2)
        assert(items[3].kind=="lockout" and items[4].kind=="holiday")
        local before=S.cache.characters["띵슈-아즈샤라"]
        for _,bad in ipairs({SECRET,{calendarType=SECRET},{calendarType="PLAYER",title=SECRET},
            {calendarType="PLAYER",title="x",startTime=SECRET},
            {calendarType="PLAYER",title="x",startTime={year=2026,month=10,monthDay=22,hour=20,minute=30},eventID=SECRET,inviteStatus=1}}) do
            badEvent=bad; assert(not S:Refresh()); assert(S.cache.characters["띵슈-아즈샤라"]==before)
        end
        badEvent=nil
        assert(S.cache.characters["띵띵-아즈샤라"]==char, "다른 캐릭터는 덮어쓰지 않는다")
    ''')


def test_loading_combat_disable_and_partial_refresh_preserve_saved_data():
    lua = schedule_runtime()
    ready(lua)
    lua.execute('''
        local before=calendarReads
        combat=true; Emit("PLAYER_REGEN_DISABLED"); S:RequestRefresh(); Emit("CALENDAR_UPDATE_EVENT_LIST",true)
        Emit("UPDATE_INSTANCE_INFO"); ExpireTimers()
        assert(calendarReads==before and S.pending)
        combat=false; Emit("PLAYER_REGEN_ENABLED"); ExpireTimers(); assert(calendarReads>before)
        before=calendarReads
        Emit("LOADING_SCREEN_ENABLED"); Emit("CALENDAR_UPDATE_EVENT_LIST",true); ExpireTimers()
        assert(calendarReads==before)
        Emit("LOADING_SCREEN_DISABLED"); ExpireTimers(); assert(calendarReads>before)
        local locks=S.cache.characters["띵띵-아즈샤라"].lockouts
        secretLockout=true; Emit("UPDATE_INSTANCE_INFO")
        assert(S.cache.characters["띵띵-아즈샤라"].lockouts==locks)
        secretLockout=false; lockoutCount=0; Emit("UPDATE_INSTANCE_INFO")
        assert(#S.cache.characters["띵띵-아즈샤라"].lockouts==0)
        S:OnDisable(); before=calendarReads; Emit("CALENDAR_UPDATE_EVENT_LIST",true); ExpireTimers()
        assert(calendarReads==before)
        Emit("LOADING_SCREEN_ENABLED"); Emit("LOADING_SCREEN_DISABLED"); S:OnEnable(); ExpireTimers()
        assert(calendarReads>before)
    ''')


def test_gregorian_dates_reset_fallback_and_expired_lockouts():
    lua = schedule_runtime()
    ready(lua)
    for y, m, d in [(2024, 2, 29), (2026, 12, 31), (2027, 1, 1), (2100, 3, 1)]:
        n = (date(y, m, d) - date(1970, 1, 1)).days
        assert lua.eval(f"S:DayNumber({y},{m},{d})") == n
        assert lua.eval(f"S:DateFromDay({n})") == (y, m, d)
    lua.execute('''
        weeklySeconds=SECRET; assert(S:Refresh())
        local items=S:GetDayItems(S:DayNumber(2026,10,22))
        assert(items[1].time=="08:00")
        local char=S.cache.characters["띵띵-아즈샤라"]
        char.lockouts[1].resetAt=serverEpoch-1
        for _,item in ipairs(S:GetDayItems(S:DayNumber(2026,10,22))) do assert(item.kind~="lockout") end
        S.db.hiddenCharacters["띵띵-아즈샤라"]=true
        local items,visible=S:GetDayItems(S:DayNumber(2026,10,22))
        assert(#items==0 and visible==0)
    ''')


def test_incomplete_calendar_retries_failure_and_disabled_rules():
    lua = schedule_runtime()
    lua.execute('''
        Emit("LOADING_SCREEN_DISABLED"); Emit("CALENDAR_UPDATE_EVENT_LIST",false)
        for i=1,10 do ExpireTimers() end
        assert(S.failed and not next(S.cache.characters), "불완전한 응답으로 빈 캐시를 저장하지 않는다")
        Emit("CALENDAR_UPDATE_EVENT_LIST",true); ExpireTimers()
        assert(not S.failed and S.cache.characters["띵띵-아즈샤라"].updatedAt)
        local before=S.cache.characters["띵띵-아즈샤라"]
        Emit("CALENDAR_UPDATE_EVENT_LIST",false); assert(not S:Refresh())
        assert(S.cache.characters["띵띵-아즈샤라"]==before)
        S:OnDisable(); calendarDisabled=true; S:OnEnable(); assert(S.unavailable)
        local reads=calendarReads; S:RequestRefresh(); ExpireTimers(); assert(calendarReads==reads)
    ''')


def test_real_stylelib_window_month_navigation_filter_detail_and_scale():
    for locale in ("koKR", "enUS"):
        lua = schedule_runtime(window=True, locale=locale)
        ready(lua)
        lua.execute('''
            S:ToggleWindow(); Advance(1)
            local f=S.frame
            assert(f:IsShown() and f._ddslRounded.radius==14 and f:GetWidth()==920 and f:GetHeight()==620)
            assert(f.titleBar and f.titleBar.brandLogo and not f.titleBar.verText:IsShown())
            S:SelectDay(S:DayNumber(2026,10,22)); assert(f.detailRows[2].title:GetText()=="길드 신화 키식스 1~4넴")
            local _,sy,_,sh=f.detailRows[2].source:Rect(); local _,by,_,bh=f.detailRows[2].badge:Rect()
            assert(sy>=by-2 and sy+sh<=by+bh+2, "출처는 응답 줄이 아닌 태그 옆에 놓인다")
            S:MoveMonth(-2); assert(S.month==8 and f.cells[42]:IsShown(), "8월은 6줄")
            local count=#objects; S:Render(); S:Render(); assert(#objects==count,"반복 렌더에서 프레임 재사용")
            f.chips[2]:Fire("OnClick","LeftButton"); assert(S.db.hiddenCharacters["띵띵-아즈샤라"])
            f.chips[1]:Fire("OnClick","LeftButton"); assert(not next(S.db.hiddenCharacters))
            combat=true; Emit("PLAYER_REGEN_DISABLED"); S:Render(); assert(f:IsShown())
            combat=false; f:Hide(); S:ToggleWindow(); Advance(1); assert(f:IsShown())
            local gx,gy,gw,gh=f.grid:Rect(); local dx,dy,dw,dh=f.detail:Rect()
            assert(gx+gw<=dx and gw==654 and dw==242)
            for _,cell in ipairs(f.cells) do if cell:IsShown() then
                local x,y,w,h=cell:Rect(); assert(x>=gx-0.01 and x+w<=gx+gw+0.01 and y>=gy-0.01)
                for _,row in ipairs(cell.rows) do if row:IsShown() then
                    local rx,ry,rw,rh=row:Rect(); assert(ry>=y and ry+rh<=y+h)
                end end
            end end
        ''')


def test_settings_slash_locales_and_existing_profiles():
    lua = schedule_runtime(window=True)
    lua.execute('''
        DDingUIToolkitDB={profile={modules={MailAlert=true},MailAlert={fontSize=27}}}
        ns:InitDB(); assert(ns.db.profile.modules.Schedule==false and ns.db.profile.MailAlert.fontSize==27)
        S:OnInitialize()
        ns.db.profile.modules.Schedule=true
        S.cache.characters.old={name="old",realm="r",classFile="PRIEST",events={},lockouts={}}
        S:DeleteCache(); assert(S.cache.characters.old and confirmation)
        confirmation.onAccept(); assert(not next(S.cache.characters))
        ns.L=setmetatable(ns.L,{__index=function(_,key) return key end})
    ''')
    load(lua, "Config_Data.lua")
    lua.execute('tree=ns:InitConfigTree(); assert(tree.panels.schedule and ns.ConfigModuleMap.schedule=="Schedule")')
    load(lua, "Core/SlashCommands.lua")
    lua.execute('''
        opened=0; S.ToggleWindow=function() opened=opened+1 end
        for _,cmd in ipairs({"schedule","cal","일정"}) do SlashCmdList.DDINGTOOLKIT(cmd) end
        assert(opened==3)
    ''')
    for locale in ("koKR", "enUS"):
        text = (ROOT / f"Locales/{locale}.lua").read_text(encoding="utf-8-sig")
        keys = set(re.findall(r'L\["(SCHEDULE_[A-Z_0-9]+)"\]', text))
        assert len(keys) == 58
    toc = (ROOT / "DDingUI_Toolkit.toc").read_text(encoding="utf-8-sig")
    assert toc.index("Schedule\\Schedule.lua") < toc.index("Schedule\\Window.lua")


def test_profile_switch_keeps_account_cache_and_window_preferences():
    lua = schedule_runtime(window=True)
    ready(lua)
    load(lua, "Core/Profiles.lua")
    lua.execute('''
        ns:InitDB(); S:OnInitialize(); S:ToggleWindow(); Advance(1)
        local slider=S.frame.titleBar.scaleControl.slider
        slider:SetValue(1.3); slider:Fire("OnMouseUp"); Advance(1)
        assert(math.abs(S.db.guiScale-1.3)<0.001 and math.abs(S.frame._ddslMotionBaseScale-1.3)<0.001)
        S.frame:ClearAllPoints(); S.frame:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-50,-70)
        S.frame.titleBar:Fire("OnDragStop")
        assert(S.db.position.point=="TOPRIGHT" and S.db.position.x==-50 and S.db.position.y==-70)
        local cache=S.cache
        assert(ns:CreateToolkitProfile("Alt",false)); ns:InitDB(); S:OnInitialize()
        assert(S.cache==cache and S.cache.characters["띵띵-아즈샤라"].events[1])
        assert(S.db.guiScale==1)
        assert(ns:UseToolkitProfile("Default")); ns:InitDB(); S:OnInitialize()
        assert(S.cache==cache and math.abs(S.db.guiScale-1.3)<0.001 and S.db.position.x==-50)
        S.frame:Hide(); S.frame=nil; S:CreateWindow()
        assert(math.abs(S.frame:GetScale()-1.3)<0.001)
        local p,_,_,x,y=S.frame:GetPoint(1); assert(p=="TOPRIGHT" and x==-50 and y==-70)
    ''')
