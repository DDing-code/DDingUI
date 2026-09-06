-- DDingUI Toolkit - pending calendar invitation alerts

local addonName, ns = ...
local L = ns.L
local SL = _G.DDingUI_StyleLib
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "DDingUI Toolkit: "

local CalendarInviteAlert = {}
ns.CalendarInviteAlert = CalendarInviteAlert

local active = false
local editPreview = false
local previousCount
local pendingAlert = false
local eventFrame = CreateFrame("Frame")
local loading = true
local todayTimer
local todayDate
local requestedDate
local seenToday = {}
local PLAYER_EVENTS = { PLAYER = true, GUILD_EVENT = true, GUILD_ANNOUNCEMENT = true, COMMUNITY_EVENT = true }

local function IsPlain(value, kind)
    return not ns.IsSecretValue(value) and type(value) == kind
end

local function IsInteger(value, minimum, maximum)
    return IsPlain(value, "number") and value >= minimum and value <= maximum and value == math.floor(value)
end

local function ReadValue(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    if ok and not ns.IsSecretValue(value) then return value end
end

local function CancelTodayTimer()
    if todayTimer then todayTimer:Cancel(); todayTimer = nil end
end

function CalendarInviteAlert:OnInitialize()
    self.db = ns.db.profile.CalendarInviteAlert
    self.initialized = true
end

function CalendarInviteAlert:GetPendingCount()
    if not C_Calendar or not C_Calendar.GetNumPendingInvites then return nil end
    local ok, count = pcall(C_Calendar.GetNumPendingInvites)
    if not ok or ns.IsSecretValue(count) or type(count) ~= "number" then return nil end
    if not (count >= 0 and count < math.huge) then return nil end
    return math.floor(count)
end

function CalendarInviteAlert:GetTodayEvents()
    if not C_Calendar or not C_Calendar.GetDayEvent or not C_Calendar.GetNumDayEvents
        or not C_DateAndTime or not C_DateAndTime.GetCurrentCalendarTime then return nil end
    local now = ReadValue(C_DateAndTime.GetCurrentCalendarTime)
    if not IsPlain(now, "table") or not IsInteger(now.year, 1, 9999) or not IsInteger(now.month, 1, 12)
        or not IsInteger(now.monthDay, 1, 31) or not IsInteger(now.hour, 0, 23)
        or not IsInteger(now.minute, 0, 59) then return nil end
    local dateKey = string.format("%04d-%02d-%02d", now.year, now.month, now.monthDay)
    -- Request calendar data without opening or moving the calendar UI.
    if requestedDate ~= dateKey then
        requestedDate = dateKey
        if C_Calendar.OpenCalendar and not pcall(C_Calendar.OpenCalendar) then
            requestedDate = nil
            return nil
        end
    end

    -- Offset from the browsed month instead of changing Blizzard's calendar selection.
    local month = ReadValue(C_Calendar.GetMonthInfo, 0)
    if not IsPlain(month, "table") or not IsInteger(month.year, 1, 9999)
        or not IsInteger(month.month, 1, 12) then return nil end
    local offset = (now.year - month.year) * 12 + now.month - month.month
    local count = ReadValue(C_Calendar.GetNumDayEvents, offset, now.monthDay)
    if not IsInteger(count, 0, 1000) then return nil end

    local events = {}
    for index = 1, count do
        local event = ReadValue(C_Calendar.GetDayEvent, offset, now.monthDay, index)
        if not IsPlain(event, "table") or not IsPlain(event.calendarType, "string") then return nil end
        if PLAYER_EVENTS[event.calendarType] then
            local status = event.inviteStatus
            if not IsInteger(status, 0, 8) then return nil end
            if status ~= Enum.CalendarStatus.Declined and status ~= Enum.CalendarStatus.Out then
                local start = event.startTime
                if not IsPlain(start, "table") or not IsPlain(event.title, "string")
                    or not IsInteger(start.year, 1, 9999) or not IsInteger(start.month, 1, 12)
                    or not IsInteger(start.monthDay, 1, 31) or not IsInteger(start.hour, 0, 23)
                    or not IsInteger(start.minute, 0, 59) then return nil end
                if start.year == now.year and start.month == now.month and start.monthDay == now.monthDay then
                    local id = event.eventID
                    if not IsPlain(id, "string") and not IsInteger(id, 0, 2^53) then return nil end
                    local title = event.title:gsub("[\r\n]", " "):gsub("|", "||")
                    events[#events + 1] = {
                        key = string.format("%s:%02d:%02d:%s", tostring(id), start.hour, start.minute, title),
                        title = title, hour = start.hour, minute = start.minute,
                    }
                end
            end
        end
    end
    table.sort(events, function(a, b)
        if a.hour ~= b.hour then return a.hour < b.hour end
        if a.minute ~= b.minute then return a.minute < b.minute end
        return a.key < b.key
    end)
    -- ponytail: minute-precision day check; use a second-precision clock if exact midnight delivery is needed.
    return events, dateKey, (24 - now.hour) * 3600 - now.minute * 60 + 1
end

function CalendarInviteAlert:ScheduleTodayCheck(delay)
    CancelTodayTimer()
    if not active or loading or self.db.notifyToday == false or editPreview then return end
    todayTimer = C_Timer.NewTimer(delay, function()
        todayTimer = nil
        self:CheckTodayEvents()
    end)
end

function CalendarInviteAlert:CheckTodayEvents()
    CancelTodayTimer()
    if not active or loading or editPreview or InCombatLockdown() or self.db.notifyToday == false then return end
    if not C_Calendar or not C_Calendar.GetDayEvent or not C_DateAndTime then return end
    -- Re-read between notices so cancelled or rescheduled events never sit in a stale queue.
    local events, dateKey, nextDay = self:GetTodayEvents()
    if not events then self:ScheduleTodayCheck(30); return end
    if todayDate ~= dateKey then todayDate = dateKey; seenToday = {} end

    if self.todayKey then
        local stillExists = false
        for _, event in ipairs(events) do
            if event.key == self.todayKey then stillExists = true; break end
        end
        if not stillExists then
            self:HideAlert()
            ns:CancelManagedSound("CalendarInviteAlert:today-event")
        end
    end

    local delay = math.max(1, math.min(15, tonumber(self.db.alertDuration) or 6)) + 0.1
    if self.alertFrame and self.alertFrame:IsShown() then
        local state = self.alertVisual.state
        self:ScheduleTodayCheck(state and math.max(0.1, state.duration - state.elapsed + 0.1) or delay)
        return
    end
    for _, event in ipairs(events) do
        if not seenToday[event.key] then
            seenToday[event.key] = true
            self:TriggerAlert(false, nil, event)
            self:ScheduleTodayCheck(delay)
            return
        end
    end
    self:ScheduleTodayCheck(nextDay)
end

function CalendarInviteAlert:CheckAlerts()
    self:CheckPendingInvites()
    self:CheckTodayEvents()
end

function CalendarInviteAlert:CheckPendingInvites()
    if not active or loading then return end
    local count = self:GetPendingCount()
    if count == nil then return end

    local changed = count ~= previousCount
    if previousCount == nil then
        pendingAlert = count > 0 and self.db.notifyOnLogin ~= false
    elseif count > previousCount then
        pendingAlert = true
    end
    previousCount = count

    if count == 0 then
        pendingAlert = false
        ns:CancelManagedSound("CalendarInviteAlert:pending-invites")
        if not editPreview and not self.todayKey then self:HideAlert() end
        return
    end

    if editPreview then return end
    if self.db.hideInCombat and InCombatLockdown() then
        self:HideAlert()
        return
    end

    if pendingAlert then
        pendingAlert = false
        if self.todayKey and self.alertFrame:IsShown() then
            seenToday[self.todayKey] = nil
            ns:CancelManagedSound("CalendarInviteAlert:today-event")
        end
        self:TriggerAlert(false, count)
    elseif changed and not self.todayKey and self.alertFrame and self.alertFrame:IsShown() then
        self.alertFrame.subtitle:SetText(string.format(L["CALENDARALERT_PENDING_TEXT"], count))
    end
end

function CalendarInviteAlert:OnEnable()
    self:OnInitialize()
    if not C_Calendar or not C_Calendar.GetNumPendingInvites then return end
    if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule
        and Enum.GameRule.IngameCalendarDisabled
        and C_GameRules.IsGameRuleActive(Enum.GameRule.IngameCalendarDisabled) then return end

    active = true
    previousCount = nil
    pendingAlert = false
    todayDate, requestedDate = nil, nil
    seenToday = {}
    CancelTodayTimer()
    eventFrame:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES")
    eventFrame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:CheckAlerts()
end

function CalendarInviteAlert:OnDisable()
    active = false
    editPreview = false
    previousCount = nil
    pendingAlert = false
    CancelTodayTimer()
    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
    eventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
    ns:CancelManagedSoundsBySource("CalendarInviteAlert")
    self:HideAlert()
end

function CalendarInviteAlert:CreateAlertFrame()
    if self.alertVisual then return end
    self:OnInitialize()
    self.alertVisual = ns.CreateCalmPartyAlert("DDingToolKit_CalendarInviteAlertFrame", "CALENDAR")
    self.alertFrame = self.alertVisual.frame
    self:ApplyPosition()
end

function CalendarInviteAlert:ApplyPosition()
    if self.alertVisual then self.alertVisual:Apply(self.db, self.db.position) end
end

function CalendarInviteAlert:ApplySettings()
    self.db = ns.db.profile.CalendarInviteAlert
    self:ApplyPosition()
    if editPreview then
        self:ShowAlert(true)
    else
        if not self.db.screenAlertEnabled then self:HideAlert() end
        if self.db.notifyToday == false then
            CancelTodayTimer()
            ns:CancelManagedSound("CalendarInviteAlert:today-event")
            if self.todayKey then self:HideAlert() end
        end
        if not self.db.soundEnabled then ns:CancelManagedSoundsBySource("CalendarInviteAlert") end
        self:CheckAlerts()
    end
end

function CalendarInviteAlert:ShowAlert(isTest, count, todayEvent)
    self:CreateAlertFrame()
    self:ApplyPosition()
    self.todayKey = todayEvent and todayEvent.key or nil
    local title = todayEvent and string.format(L["CALENDARALERT_TODAY_TITLE"], todayEvent.hour, todayEvent.minute) or L["CALENDARALERT_ALERT_TITLE"]
    local subtitle = todayEvent and todayEvent.title or string.format(L["CALENDARALERT_PENDING_TEXT"], isTest and 3 or count)
    self.alertVisual:Show(title, subtitle, {
        duration = self.db.alertDuration,
        animated = self.db.animationEnabled ~= false,
        persistent = editPreview,
        previewDuration = 4,
        nodeCount = 1,
    })
end

function CalendarInviteAlert:HideAlert()
    self.todayKey = nil
    if self.alertVisual then self.alertVisual:Hide(true) end
end

function CalendarInviteAlert:TriggerAlert(isTest, count, todayEvent)
    self.db = ns.db.profile.CalendarInviteAlert
    if self.db.soundEnabled then
        ns:RequestSound({
            source = "CalendarInviteAlert",
            key = todayEvent and "today-event" or "pending-invites",
            soundFile = self.db.soundFile,
            customPath = self.db.soundCustomPath,
            soundKit = (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081,
            channel = self.db.soundChannel,
            priority = 20,
            canQueue = true,
            immediate = isTest == true,
        })
    end
    if self.db.flashEnabled then FlashClientIcon() end
    if self.db.screenAlertEnabled then self:ShowAlert(isTest, count, todayEvent) end
    if self.db.chatAlert then
        local message = todayEvent and string.format(L["CALENDARALERT_TODAY_CHAT"], todayEvent.hour, todayEvent.minute, todayEvent.title)
            or string.format(L["CALENDARALERT_CHAT_TEXT"], isTest and 3 or count)
        print(CHAT_PREFIX .. message)
    end
end

function CalendarInviteAlert:OpenCalendar()
    if InCombatLockdown() then return end
    if _G.CalendarFrame and _G.CalendarFrame:IsShown() then return end
    if ToggleCalendar then ToggleCalendar() end
end

function CalendarInviteAlert:EnterEditPreview()
    CancelTodayTimer()
    editPreview = true
    self:ShowAlert(true)
end

function CalendarInviteAlert:RefreshEditPreview()
    if editPreview then self:ApplySettings() end
end

function CalendarInviteAlert:ExitEditPreview()
    editPreview = false
    self:HideAlert()
    self:CheckAlerts()
end

function CalendarInviteAlert:ResetPosition()
    self.db = ns.db.profile.CalendarInviteAlert
    self.db.position = ns:DeepCopy(ns.defaults.profile.CalendarInviteAlert.position)
    self:ApplyPosition()
end

function CalendarInviteAlert:OnMediaChanged()
    self:ApplySettings()
end

-- Observe loading even while disabled, so enabling in the world needs no new zone transition.
eventFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
eventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "LOADING_SCREEN_ENABLED" then loading = true end
    if event == "LOADING_SCREEN_DISABLED" then loading = false end
    if not active then return end
    if event == "LOADING_SCREEN_ENABLED"
        or (event == "PLAYER_REGEN_DISABLED" and CalendarInviteAlert.db.hideInCombat) then
        CancelTodayTimer()
        ns:CancelManagedSoundsBySource("CalendarInviteAlert")
        if not editPreview then
            if CalendarInviteAlert.alertFrame and CalendarInviteAlert.alertFrame:IsShown() then
                if CalendarInviteAlert.todayKey then
                    seenToday[CalendarInviteAlert.todayKey] = nil
                elseif loading then
                    pendingAlert = true
                end
            end
            CalendarInviteAlert:HideAlert()
        end
    else
        CalendarInviteAlert:CheckAlerts()
    end
end)

ns.DDingToolKit:RegisterModule("CalendarInviteAlert", CalendarInviteAlert)
