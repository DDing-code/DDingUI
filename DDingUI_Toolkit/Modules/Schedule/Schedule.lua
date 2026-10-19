-- [REFACTOR] 계정의 접속한 캐릭터만 갱신하는 월 일정 캐시.
local _, ns = ...
local L = ns.L
local Schedule = {}
ns.Schedule = Schedule
ns.DDingToolKit:RegisterModule("Schedule", Schedule)

local PLAYER_EVENTS = {PLAYER=true, GUILD_EVENT=true, GUILD_ANNOUNCEMENT=true, COMMUNITY_EVENT=true}
local driver = CreateFrame("Frame")
local loading, active, timer, calendarReady = true, false, nil, false
local DAY, WEEK = 86400, 604800

local function Plain(v, kind) return not ns.IsSecretValue(v) and type(v) == kind end
local function Integer(v, low, high)
    return Plain(v, "number") and v >= low and v <= high and v == math.floor(v)
end
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not ns.IsSecretValue(v) then return v end
end
local function Text(v)
    if Plain(v, "string") then return v:gsub("[\r\n]", " "):gsub("|", "||") end
end

-- [12.0.1] 달력 날짜는 PC 시간대/DST와 독립적인 일련번호로 계산한다.
function Schedule:DayNumber(y, m, d)
    y = y - (m <= 2 and 1 or 0)
    local era = math.floor(y / 400)
    local yy = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    return era * 146097 + yy * 365 + math.floor(yy / 4) - math.floor(yy / 100) + doy - 719468
end

function Schedule:DateFromDay(n)
    local z = n + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yy = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yy + era * 400
    local doy = doe - (365 * yy + math.floor(yy / 4) - math.floor(yy / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    return y + (m <= 2 and 1 or 0), m, d
end

function Schedule:MonthDays(y, m)
    local nextY, nextM = y + (m == 12 and 1 or 0), m == 12 and 1 or m + 1
    return self:DayNumber(nextY, nextM, 1) - self:DayNumber(y, m, 1)
end

local function ValidDate(v)
    return Plain(v, "table") and Integer(v.year, 1, 9999) and Integer(v.month, 1, 12)
        and Integer(v.monthDay, 1, Schedule:MonthDays(v.year, v.month))
end
local function ValidTime(v)
    return ValidDate(v) and Integer(v.hour, 0, 23) and Integer(v.minute, 0, 59)
end

function Schedule:ServerTime()
    local epoch = Read(GetServerTime)
    if Plain(epoch, "number") and epoch >= 0 and epoch < math.huge then return epoch end
    return time()
end

function Schedule:Today()
    if self.clock then
        local day = math.floor((self.clock.wall + self:ServerTime() - self.clock.epoch) / DAY)
        return self:DateFromDay(day)
    end
    -- [12.0.1] 서버 시각 준비 전 첫 화면에만 PC 날짜를 사용한다.
    local t = date("*t")
    return t.year, t.month, t.day
end

function Schedule:EpochDay(epoch)
    if not self.clock then return nil end
    return math.floor((self.clock.wall + epoch - self.clock.epoch) / DAY)
end

function Schedule:IsUnavailable()
    return C_GameRules and Enum and Enum.GameRule
        and Read(C_GameRules.IsGameRuleActive, Enum.GameRule.IngameCalendarDisabled) == true
end

function Schedule:OnInitialize()
    self.db = ns.db.profile.Schedule
    self.cache = ns.db.global.Schedule
end

function Schedule:Identity()
    local name, realm = Read(UnitName, "player"), Read(GetRealmName)
    if not Plain(name, "string") or not Plain(realm, "string") then return nil end
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or not Plain(class, "string") then return nil end
    return name .. "-" .. realm, {name=Text(name), realm=Text(realm), classFile=class}
end

function Schedule:ReadCalendar()
    if not calendarReady or not C_Calendar or not C_DateAndTime then return nil end
    local now = Read(C_DateAndTime.GetCurrentCalendarTime)
    local selected = Read(C_Calendar.GetMonthInfo, 0)
    if not ValidTime(now) or not Plain(selected, "table") or not Integer(selected.year, 1, 9999)
        or not Integer(selected.month, 1, 12) then return nil end
    local epoch = self:ServerTime()
    self.clock = {epoch=epoch, wall=self:DayNumber(now.year, now.month, now.monthDay) * DAY + now.hour * 3600 + now.minute * 60 + epoch % 60}
    local seconds = Read(C_DateAndTime.GetSecondsUntilWeeklyReset)
    if Plain(seconds, "number") and seconds >= 0 and seconds <= WEEK then
        -- API는 초 단위 반올림 오차가 있으므로 표시 시각은 분 단위로 맞춘다.
        self.nextReset = math.floor((self.clock.wall + seconds + 30) / 60) * 60
    else
        local today = math.floor(self.clock.wall / DAY)
        local nextDay = today + (5 - ((today + 4) % 7 + 1)) % 7
        self.nextReset = nextDay * DAY + 8 * 3600
        if self.nextReset <= self.clock.wall then self.nextReset = self.nextReset + WEEK end
    end
    local offset = (now.year - selected.year) * 12 + now.month - selected.month
    local events, holidays, seen, seenHoliday = {}, {}, {}, {}
    local guild = Text(Read(GetGuildInfo, "player"))
    for relative = -1, 2 do
        local month = Read(C_Calendar.GetMonthInfo, offset + relative)
        if not Plain(month, "table") or not Integer(month.year, 1, 9999) or not Integer(month.month, 1, 12)
            or not Integer(month.numDays, 28, 31) then return nil end
        for day = 1, month.numDays do
            local count = Read(C_Calendar.GetNumDayEvents, offset + relative, day)
            if not Integer(count, 0, 1000) then return nil end
            for index = 1, count do
                local event = Read(C_Calendar.GetDayEvent, offset + relative, day, index)
                if not Plain(event, "table") or not Plain(event.calendarType, "string") then return nil end
                local kind, title = event.calendarType, Text(event.title)
                if PLAYER_EVENTS[kind] then
                    local start, id = event.startTime, event.eventID
                    if not title or not ValidTime(start) or not Integer(event.inviteStatus, 0, 8)
                        or (not Plain(id, "string") and not Integer(id, 0, 2^53)) then return nil end
                    local key = tostring(id) .. ":" .. self:DayNumber(start.year, start.month, start.monthDay)
                    if not seen[key] then
                        seen[key] = true
                        events[#events + 1] = {eventID=id, title=title, calendarType=kind,
                            eventType=Integer(event.eventType, 0, 5) and event.eventType or nil,
                            year=start.year, month=start.month, day=start.monthDay, hour=start.hour, minute=start.minute,
                            inviteStatus=event.inviteStatus, invitedBy=Text(event.invitedBy), guildName=guild,
                            modStatus=Text(event.modStatus)}
                    end
                elseif kind == "HOLIDAY" then
                    local holiday = Read(C_Calendar.GetHolidayInfo, offset + relative, day, index)
                    if not Plain(holiday, "table") or not ValidDate(holiday.startTime) or not ValidDate(holiday.endTime) then return nil end
                    local start, finish = holiday.startTime, holiday.endTime
                    local first, last = self:DayNumber(start.year, start.month, start.monthDay), self:DayNumber(finish.year, finish.month, finish.monthDay)
                    local name = Text(holiday.name) or title
                    if not name then return nil end
                    local key = name .. ":" .. first
                    if not seenHoliday[key] then
                        seenHoliday[key] = true
                        holidays[#holidays + 1] = {title=name, first=first, last=last,
                            texture=Integer(holiday.texture, 1, 2^53) and holiday.texture or nil}
                    end
                end
            end
        end
    end
    return events, holidays
end

function Schedule:ReadLockouts()
    local count = Read(GetNumSavedInstances)
    if not Integer(count, 0, 1000) then return nil end
    local result, epoch = {}, self:ServerTime()
    for i = 1, count do
        local ok, name, id, reset, difficulty, locked, _, _, isRaid, _, diffName, num, progress = pcall(GetSavedInstanceInfo, i)
        if not ok or not Plain(isRaid, "boolean") or not Plain(locked, "boolean") then return nil end
        if isRaid and locked then
            if not Plain(name, "string") or not Integer(id, 0, 2^53) or not Integer(difficulty, 0, 1000)
                or not Plain(reset, "number") or not (reset >= 0 and reset <= 366 * DAY)
                or not Integer(num, 0, 1000) or not Integer(progress, 0, num) then return nil end
            if reset > 0 then result[#result + 1] = {name=Text(name), instanceID=id, difficultyID=difficulty,
                difficultyName=Text(diffName) or "", numEncounters=num, encounterProgress=progress, resetAt=epoch + reset, isRaid=true} end
        end
    end
    return result
end

local function CancelTimer()
    if timer then timer:Cancel(); timer = nil end
end

function Schedule:RefreshWindow()
    if self.frame and self.frame:IsShown() then self:Render() end
end

function Schedule:Refresh()
    if not active or loading or InCombatLockdown() then self.pending = true; return false end
    local key, identity = self:Identity()
    if not key then return false end
    local events, holidays = self:ReadCalendar()
    if not events then return false end
    local previous = self.cache.characters[key]
    identity.events, identity.lockouts = events, previous and previous.lockouts or {}
    identity.updatedAt = self:ServerTime()
    self.cache.characters[key] = identity
    self.cache.common = {holidays=holidays, updatedAt=identity.updatedAt}
    self.failed, self.pending = nil, nil
    self:RefreshWindow()
    return true
end

function Schedule:QueueRefresh(delay, attempt)
    CancelTimer()
    if not active or loading or InCombatLockdown() then self.pending = true; return end
    timer = C_Timer.NewTimer(delay or 0.25, function()
        timer = nil
        if not active or loading or InCombatLockdown() then self.pending = true; return end
        if not self:Refresh() then
            local tries = (attempt or 0) + 1
            if tries < 10 then self:QueueRefresh(1, tries)
            else self.failed = true; self:RefreshWindow() end
        end
    end)
end

function Schedule:RequestRefresh()
    if not active or loading or InCombatLockdown() then self.pending = true; return end
    Read(C_Calendar and C_Calendar.OpenCalendar)
    Read(RequestRaidInfo)
    self:QueueRefresh(1)
end

function Schedule:OnEnable()
    self:OnInitialize()
    if self:IsUnavailable() then self.unavailable = true; return end
    self.unavailable, active = nil, true
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CALENDAR_UPDATE_EVENT_LIST",
        "CALENDAR_UPDATE_PENDING_INVITES", "UPDATE_INSTANCE_INFO"}) do driver:RegisterEvent(event) end
    self:RequestRefresh()
end

function Schedule:OnDisable()
    active = false
    CancelTimer()
    -- [12.0.1] 비활성 중에도 로딩 상태는 추적해 다시 켰을 때 대기하지 않는다.
    driver:UnregisterAllEvents()
    driver:RegisterEvent("LOADING_SCREEN_ENABLED")
    driver:RegisterEvent("LOADING_SCREEN_DISABLED")
    if self.frame then self.frame:Hide() end
end

driver:RegisterEvent("LOADING_SCREEN_ENABLED")
driver:RegisterEvent("LOADING_SCREEN_DISABLED")
driver:SetScript("OnEvent", function(_, event, complete)
    if event == "LOADING_SCREEN_ENABLED" then loading = true; CancelTimer()
    elseif event == "LOADING_SCREEN_DISABLED" then loading = false; Schedule:RequestRefresh()
    elseif event == "PLAYER_REGEN_DISABLED" then CancelTimer(); Schedule.pending = true; Schedule:RefreshWindow()
    elseif event == "PLAYER_REGEN_ENABLED" then Schedule:RequestRefresh()
    elseif event == "PLAYER_ENTERING_WORLD" then Schedule:QueueRefresh(3)
    elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
        calendarReady = not ns.IsSecretValue(complete) and complete ~= false
        Schedule:QueueRefresh()
    elseif event == "CALENDAR_UPDATE_PENDING_INVITES" then Schedule:QueueRefresh()
    elseif event == "UPDATE_INSTANCE_INFO" then
        if active and not loading and not InCombatLockdown() then
            local key, identity = Schedule:Identity()
            local lockouts = Schedule:ReadLockouts()
            if key and lockouts then
                local char = Schedule.cache.characters[key] or identity
                char.events = char.events or {}
                char.lockouts = lockouts
                Schedule.cache.characters[key] = char
                Schedule:RefreshWindow()
            end
        else Schedule.pending = true end
    end
end)

function Schedule:GetCharacters()
    local chars = {}
    for key, char in pairs(self.cache.characters) do chars[#chars + 1] = {key=key, data=char} end
    table.sort(chars, function(a, b)
        if (a.data.updatedAt or 0) ~= (b.data.updatedAt or 0) then return (a.data.updatedAt or 0) > (b.data.updatedAt or 0) end
        return a.key < b.key
    end)
    return chars
end

function Schedule:Status(event)
    if event.modStatus == "CREATOR" then return L["SCHEDULE_HOST"] end
    local status = event.inviteStatus
    if status == 1 or status == 3 or status == 6 then return L["SCHEDULE_ACCEPTED"] end
    if status == 2 or status == 4 then return L["SCHEDULE_DECLINED"] end
    if status == 5 or status == 8 then return L["SCHEDULE_TENTATIVE"] end
    return L["SCHEDULE_UNANSWERED"]
end

function Schedule:GetDayItems(day)
    local items, merged, locks, visible, released = {}, {}, {}, 0, 0
    for _, entry in ipairs(self:GetCharacters()) do
        if not self.db.hiddenCharacters[entry.key] then
            visible = visible + 1
            for _, event in ipairs(entry.data.events or {}) do
                if self:DayNumber(event.year, event.month, event.day) == day then
                    -- [REFACTOR] 제목이 같아도 합치지 않는다. ID와 날짜가 같을 때만 한 줄로 만든다.
                    local key = tostring(event.eventID) .. ":" .. day
                    local item = merged[key]
                    if not item then
                        item = {kind="event", key=key, title=event.title, event=event, members={}, order=event.hour * 60 + event.minute}
                        items[#items + 1], merged[key] = item, item
                    end
                    item.members[#item.members + 1] = {char=entry.data, key=entry.key, event=event}
                end
            end
            if self.db.showLockouts then
                for _, lock in ipairs(entry.data.lockouts or {}) do
                    local expiry = self:EpochDay(lock.resetAt)
                    local today = self.clock and math.floor((self.clock.wall + self:ServerTime() - self.clock.epoch) / DAY)
                    if expiry and lock.resetAt > self:ServerTime() and day >= today and day <= expiry then
                        if expiry == day then released = released + 1 end
                        local key = lock.name .. ":" .. lock.difficultyID
                        local item = locks[key]
                        if not item then
                            item = {kind="lockout", key=key, title=L["SCHEDULE_RAID_LOCKOUT"] .. " · " .. lock.name .. " " .. lock.difficultyName,
                                members={}, order=1500, progress=0}
                            items[#items + 1], locks[key] = item, item
                        end
                        item.members[#item.members + 1] = {char=entry.data, key=entry.key, lockout=lock}
                        item.progress = math.max(item.progress, lock.numEncounters > 0 and lock.encounterProgress / lock.numEncounters or 0)
                    end
                end
            end
        end
    end
    if visible == 0 then return {}, 0 end
    if self.db.showReset and self.nextReset and (day - math.floor(self.nextReset / DAY)) % 7 == 0 then
        local wall = self.nextReset % DAY
        items[#items + 1] = {kind="reset", key="reset", title=L["SCHEDULE_WEEKLY_RESET"], members={}, order=-1,
            released=released,
            time=string.format("%02d:%02d", math.floor(wall / 3600), math.floor(wall % 3600 / 60))}
    end
    if self.db.showHolidays then
        for _, holiday in ipairs(self.cache.common.holidays or {}) do
            if day >= holiday.first and day <= holiday.last then
                items[#items + 1] = {kind="holiday", key=holiday.title .. holiday.first, title=holiday.title, holiday=holiday, members={}, order=1600}
            end
        end
    end
    table.sort(items, function(a,b) if a.order ~= b.order then return a.order < b.order end return a.key < b.key end)
    return items, visible
end

function Schedule:DeleteCache(key)
    if not ns.UI or not ns.UI.ShowConfirmation then return end
    ns.UI:ShowConfirmation("ScheduleCache", {title=L["SCHEDULE_TITLE"], text=L["SCHEDULE_DELETE_CONFIRM"], onAccept=function()
        CancelTimer()
        if key then self.cache.characters[key] = nil; self.db.hiddenCharacters[key] = nil
        else self.cache.characters = {}; self.cache.common = {holidays={}}; self.db.hiddenCharacters = {} end
        self:RefreshWindow()
    end})
end
