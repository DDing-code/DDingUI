-- [STYLE] A 월 보드: 공용 제목줄, 캐릭터 칩, 월 격자와 선택 날짜 상세.
local _, ns = ...
local S, L = ns.Schedule, ns.L
local SL = _G.DDingUI_StyleLib
local C, T = SL.Colors, SL.Tokens
local accent, accentTo = SL.GetAccent("MJToolkit")
local HOLIDAY = {1, 0.54, 0.12, 1}
local DARKMOON = {0.70, 0.42, 1, 1}
local DAY = 86400

local function Alpha(c, a) return {c[1], c[2], c[3], a} end
local function Colored(text, c)
    return string.format("|cff%02x%02x%02x%s|r",c[1]*255,c[2]*255,c[3]*255,text)
end
local function ClassColor(char)
    local c = RAID_CLASS_COLORS[char.classFile]
    return c and {c.r, c.g, c.b, 1} or C.text.normal
end
local function HolidayColor(item)
    return (item.title:find("다크문", 1, true) or item.title:lower():find("darkmoon", 1, true)) and DARKMOON or HOLIDAY
end
local function Label(parent, size, color, width)
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont(SL:GetFont(), size, "")
    f:SetTextColor(unpack(color or C.text.normal))
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    if width then f:SetWidth(width) end
    return f
end
local function Fill(parent, color, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(); t:SetColorTexture(unpack(color))
    return t
end
local function Surface(parent, radius, bg, border)
    SL.MakeRounded(parent, radius, bg, border or Alpha(C.text.highlight, 0.05))
end
local function Button(parent, text, width, callback)
    return SL.CreateButton(parent, "MJToolkit", text, callback, {width=width, height=24})
end
local function Tooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, unpack(C.text.highlight))
    for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, unpack(C.text.normal)) end
    GameTooltip:Show()
end

function S:ItemLines(item)
    local lines = {}
    if item.kind == "event" then
        lines[#lines + 1] = string.format("%02d:%02d", item.event.hour, item.event.minute) .. " · " .. self:EventTag(item.event)
        local source=item.event.guildName or item.event.invitedBy
        if source and source ~= "" then lines[#lines+1]=source end
    elseif item.kind == "reset" then
        lines[#lines+1]=item.time .. " · " .. L["SCHEDULE_RESET_CONTENT"]
        if item.released > 0 then lines[#lines+1]=string.format(L["SCHEDULE_UNLOCKS"],item.released) end
    end
    for _, member in ipairs(item.members) do
        local text = member.char.name .. "-" .. member.char.realm .. " · "
        if member.event then text = text .. self:Status(member.event)
        else text = text .. string.format("%d/%d", member.lockout.encounterProgress, member.lockout.numEncounters) end
        lines[#lines + 1] = text
    end
    return lines
end

function S:EventTag(event)
    if event.calendarType == "GUILD_EVENT" or event.calendarType == "GUILD_ANNOUNCEMENT" then return L["SCHEDULE_GUILD_EVENT"] end
    if event.calendarType == "COMMUNITY_EVENT" then return L["SCHEDULE_COMMUNITY_EVENT"] end
    return L["SCHEDULE_PLAYER_EVENT"]
end

function S:CacheAge(char)
    if not char.updatedAt then return L["SCHEDULE_LOADING"], true end
    local days = math.max(0, math.floor((self:ServerTime() - char.updatedAt) / DAY))
    return days == 0 and L["SCHEDULE_UPDATED_TODAY"] or string.format(L["SCHEDULE_DAYS_AGO"], days), days >= self.db.staleDays, days
end

function S:CreateWindow()
    if self.frame then return end
    local f = CreateFrame("Frame", "DDingToolKit_ScheduleFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(920, 620); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
    Surface(f, 14, C.bg.main, C.border.default)
    local scale = self.db.guiScale
    f._ddslMotionBaseScale = scale; f:SetScale(scale)
    function f:ShowAnimated()
        if SL.Motion and SL.Motion.PanelOpen then SL.Motion.PanelOpen(self, {baseScale=self._ddslMotionBaseScale}) else self:Show() end
    end
    function f:HideAnimated()
        if SL.Motion and SL.Motion.PanelClose then SL.Motion.PanelClose(self, {baseScale=self._ddslMotionBaseScale}) else self:Hide() end
    end
    f:Hide()
    local title = SL.CreateTitleBar(f, "MJToolkit", "DDingUI " .. L["SCHEDULE_TITLE"], "", {rounded=true, scale={
        min=0.5, max=1.5, step=0.05, target=f, get=function() return self.db.guiScale end,
        set=function(value) self.db.guiScale=value; f._ddslMotionBaseScale=value end,
    }})
    f.titleBar = title
    title:SetHeight(42)
    if title.verText then title.verText:Hide() end
    if title.scaleControl then title.scaleControl:SetWidth(184) end
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint(1)
        self.db.position = {point=point, x=x, y=y}
    end)
    local pos = self.db.position
    f:ClearAllPoints(); f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    tinsert(UISpecialFrames, "DDingToolKit_ScheduleFrame")

    local toolbar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.toolbar = toolbar
    toolbar:SetPoint("TOPLEFT", 8, -50); toolbar:SetSize(904, 44)
    Surface(toolbar, 10, C.bg.sidebar)
    f.previous = Button(toolbar, "‹", 24, function() self:MoveMonth(-1) end)
    f.previous:SetPoint("LEFT", 10, 0)
    f.monthLabel = Label(toolbar, 16, C.text.highlight, 138); f.monthLabel:SetPoint("LEFT", f.previous, "RIGHT", 8, 0)
    f.next = Button(toolbar, "›", 24, function() self:MoveMonth(1) end); f.next:SetPoint("LEFT", f.monthLabel, "RIGHT", 0, 0)
    f.today = Button(toolbar, L["SCHEDULE_TODAY"], 48, function()
        self.year, self.month, self.day = self:Today(); self.focusKey = nil; self:Render()
    end)
    f.today:SetPoint("LEFT", f.next, "RIGHT", 8, 0)
    local sep = Fill(toolbar, T.BORDER_SEP); sep:ClearAllPoints(); sep:SetPoint("LEFT", f.today, "RIGHT", 10, 0); sep:SetSize(1, 20)
    f.chips = {}

    local grid = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.grid = grid; grid:SetPoint("TOPLEFT", 8, -102); grid:SetSize(654, 510)
    Surface(grid, 10, C.bg.sidebar)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, delta) self:MoveMonth(delta > 0 and -1 or 1) end)
    for i=1,7 do
        local label = Label(grid, 12, i == 1 and T.ERROR or i == 7 and T.INFO or C.text.dim, 654/7)
        label:SetJustifyH("CENTER"); label:SetPoint("TOPLEFT", (i-1)*654/7, -5); label:SetText(L["SCHEDULE_DAY_" .. i])
    end
    f.cells = {}
    for index=1,42 do
        local cell = CreateFrame("Button", nil, grid, "BackdropTemplate")
        f.cells[index] = cell; cell.rows = {}
        cell.bg = Fill(cell, Alpha(accent, 0))
        cell.selection = CreateFrame("Frame", nil, cell, "BackdropTemplate"); cell.selection:SetAllPoints()
        cell.selection:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
        cell.date = Label(cell, 12, C.text.normal); cell.date:SetPoint("TOPLEFT", 5, -4)
        cell.todayPill = CreateFrame("Frame", nil, cell); cell.todayPill:SetPoint("TOPLEFT", 3, -2); cell.todayPill:SetSize(25, 18)
        Surface(cell.todayPill, 8, accent, Alpha(accent, 0))
        cell.todayPill._ddslRounded.fill:SetGradient("HORIZONTAL",CreateColor(unpack(accent)),CreateColor(unpack(accentTo)))
        cell.todayText = Label(cell.todayPill, 12, C.bg.input); cell.todayText:SetPoint("CENTER")
        cell.reset = Label(cell, 11, T.WARNING); cell.reset:SetPoint("TOPRIGHT", -4, -5); cell.reset:SetText(L["SCHEDULE_RESET_MARK"])
        cell.bottom = Fill(cell, T.BORDER_SEP); cell.bottom:ClearAllPoints(); cell.bottom:SetPoint("BOTTOMLEFT"); cell.bottom:SetPoint("BOTTOMRIGHT"); cell.bottom:SetHeight(1)
        cell.right = Fill(cell, T.BORDER_SEP); cell.right:ClearAllPoints(); cell.right:SetPoint("TOPRIGHT"); cell.right:SetPoint("BOTTOMRIGHT"); cell.right:SetWidth(1)
        if index % 7 == 0 then cell.right:Hide() end
        cell.holidayBar = CreateFrame("Frame", nil, cell); cell.holidayBar:SetHeight(3)
        cell.holidayName = Label(cell, 11, HOLIDAY, 84); cell.holidayName:SetPoint("TOPLEFT", 4, -23)
        cell.more = CreateFrame("Button", nil, cell); cell.more:SetHeight(15)
        cell.more.label = Label(cell.more, 11, C.text.dim); cell.more.label:SetPoint("LEFT")
        cell:SetScript("OnClick", function() self:SelectDay(cell.dayNumber) end)
        cell.more:SetScript("OnClick", function() self:SelectDay(cell.dayNumber) end)
        cell.more:SetScript("OnEnter", function()
            local lines={}; for _,item in ipairs(cell.items or {}) do lines[#lines+1]=item.title end
            Tooltip(cell.more, L["SCHEDULE_TITLE"], lines)
        end)
        cell.more:SetScript("OnLeave", function() GameTooltip:Hide() end)
        for r=1,4 do
            local row = CreateFrame("Button", nil, cell, "BackdropTemplate"); cell.rows[r] = row
            row:SetHeight(17); Surface(row, 3, Alpha(C.text.highlight, 0.05), Alpha(C.text.highlight, 0))
            row.label = Label(row, 12, C.text.normal); row.label:SetPoint("LEFT", 7, 0); row.label:SetPoint("RIGHT", -3, 0)
            row.stripes = {}; for s=1,3 do row.stripes[s] = row:CreateTexture(nil, "ARTWORK") end
            row:SetScript("OnClick", function() self:SelectDay(cell.dayNumber, row.item and row.item.key) end)
            row:SetScript("OnEnter", function() if row.item then Tooltip(row, row.item.title, self:ItemLines(row.item)) end end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    local detail = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.detail = detail; detail:SetPoint("TOPLEFT", 670, -102); detail:SetSize(242, 510)
    Surface(detail, 10, C.bg.sidebar)
    f.detailTitle = Label(detail, 14, C.text.highlight, 222); f.detailTitle:SetPoint("TOPLEFT", 10, -12)
    f.detailSub = Label(detail, 12, C.text.dim, 222); f.detailSub:SetPoint("TOPLEFT", 10, -34)
    f.detailCount = Label(detail, 12, C.text.dim, 222); f.detailCount:SetPoint("TOPLEFT", 10, -53)
    local scroll = CreateFrame("ScrollFrame", nil, detail)
    f.scroll = scroll; scroll:SetPoint("TOPLEFT", 10, -78); scroll:SetSize(212, 324)
    local child = CreateFrame("Frame", nil, scroll); child:SetSize(212, 1); scroll:SetScrollChild(child)
    f.detailChild = child; f.detailRows = {}
    local slider = CreateFrame("Slider", nil, detail, "BackdropTemplate")
    f.scrollbar = slider; slider:SetPoint("TOPRIGHT", -8, -78); slider:SetSize(6, 324)
    Surface(slider, 2, C.bg.widget)
    slider:SetOrientation("VERTICAL"); slider:SetMinMaxValues(0, 0); slider:SetValueStep(1)
    local thumb = slider:CreateTexture(nil, "ARTWORK"); thumb:SetSize(6, 28); thumb:SetColorTexture(unpack(C.text.disabled)); SL.RoundTexture(thumb, 2)
    slider:SetThumbTexture(thumb)
    slider:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", function(_, delta)
        slider:SetValue(math.max(0, math.min(f.scrollMax or 0, scroll:GetVerticalScroll() - delta * 32)))
    end)
    f.empty = Label(child, 12, C.text.dim, 202); f.empty:SetPoint("TOPLEFT", 4, -16); f.empty:SetWordWrap(true)
    local footerLine = Fill(detail, T.BORDER_SEP); footerLine:ClearAllPoints(); footerLine:SetPoint("TOPLEFT", 10, -414); footerLine:SetSize(222, 1)
    f.footerTitle = Label(detail, 11, C.text.dim, 222); f.footerTitle:SetPoint("TOPLEFT", 10, -425)
    f.footer = Label(detail, 11, C.text.dim, 222); f.footer:SetPoint("TOPLEFT", 10, -444); f.footer:SetHeight(60); f.footer:SetWordWrap(true); f.footer:SetJustifyV("TOP")
    f.footerHover = CreateFrame("Frame", nil, detail); f.footerHover:SetPoint("TOPLEFT", 10, -425); f.footerHover:SetSize(222, 80); f.footerHover:EnableMouse(true)
    f.footerHover:SetScript("OnEnter", function() Tooltip(f.footerHover, L["SCHEDULE_CACHE_STATUS"], f.cacheLines) end)
    f.footerHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:HookScript("OnHide", function() GameTooltip:Hide() end)
end

function S:MoveMonth(delta)
    local index = self.year * 12 + self.month - 1 + delta
    self.year, self.month = math.floor(index / 12), index % 12 + 1
    self.day = math.min(self.day, self:MonthDays(self.year, self.month)); self.focusKey = nil
    self:Render()
    local grid = self.frame.grid
    if grid.CreateAnimationGroup then
        if not grid.transition then
            grid.transition = grid:CreateAnimationGroup()
            grid.fade = grid.transition:CreateAnimation("Alpha"); grid.fade:SetFromAlpha(0.3); grid.fade:SetToAlpha(1); grid.fade:SetDuration(0.15)
            grid.slide = grid.transition:CreateAnimation("Translation"); grid.slide:SetDuration(0.15)
        end
        grid.transition:Stop(); grid.slide:SetOffset(delta > 0 and -6 or 6, 0); grid.transition:Play()
    end
end

function S:SelectDay(day, focus)
    self.year, self.month, self.day = self:DateFromDay(day); self.focusKey = focus; self:Render()
end

function S:CharacterMenu(anchor, key)
    SL.ShowCascadingMenu(anchor, {
        {text=L["SCHEDULE_ONLY_CHARACTER"], func=function()
            for id in pairs(self.cache.characters) do self.db.hiddenCharacters[id] = id ~= key end
            self:Render()
        end},
        {text=L["SCHEDULE_DELETE_CACHE"], func=function() self:DeleteCache(key) end},
    })
end

function S:RenderChips()
    local f, chars = self.frame, self:GetCharacters()
    for _, chip in ipairs(f.chips) do chip:Hide() end
    local entries = {{text=string.format(L["SCHEDULE_ALL"], #chars), all=true}}
    local used = 80
    for _, entry in ipairs(chars) do
        local _, _, age = self:CacheAge(entry.data)
        local text = entry.data.name .. (age and age >= self.db.staleDays and " " .. string.format(L["SCHEDULE_AGE_SHORT"], age) or "")
        local width = math.min(140, 30 + #text * 5)
        if used + width + 6 > 530 then break end
        entries[#entries + 1] = {text=text, char=entry, width=width}; used=used+width+6
    end
    local overflow = #chars - (#entries - 1)
    if overflow > 0 then entries[#entries + 1] = {text="+" .. overflow, overflow=true, width=40} end
    local total=0; for _,entry in ipairs(entries) do total=total+(entry.width or 72)+6 end
    local x=904-10-total+6
    for i, entry in ipairs(entries) do
        local chip = f.chips[i]
        if not chip then
            chip=CreateFrame("Button", nil, f.toolbar, "BackdropTemplate"); f.chips[i]=chip
            chip.label=Label(chip,12,C.text.normal); chip.label:SetPoint("LEFT",21,0); chip.label:SetPoint("RIGHT",-7,0)
            chip.dot=CreateFrame("Frame",nil,chip,"BackdropTemplate"); chip.dot:SetPoint("LEFT",6,0); chip.dot:SetSize(9,9)
            chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        chip:ClearAllPoints(); chip:SetPoint("LEFT",x,0); chip:SetSize(entry.width or 72,22)
        local current = entry
        local color = current.char and ClassColor(current.char.data) or accent
        local hidden = current.char and self.db.hiddenCharacters[current.char.key]
        Surface(chip, 10, C.bg.input, current.all and Alpha(accent,0.7) or C.border.default)
        Surface(chip.dot, 4, hidden and C.bg.input or color, color)
        chip.dot:SetShown(not current.overflow)
        chip.label:ClearAllPoints(); chip.label:SetPoint("LEFT",current.overflow and 6 or 21,0); chip.label:SetPoint("RIGHT",-7,0)
        chip.label:SetText(current.text)
        local targetAlpha=hidden and 0.42 or 1
        if chip._targetAlpha and chip._targetAlpha~=targetAlpha and SL.Motion and SL.Motion.Tween then
            SL.Motion.Tween(chip,chip:GetAlpha(),targetAlpha,0.075,{key="scheduleChip",onUpdate=function(frame,value) frame:SetAlpha(value) end})
        else chip:SetAlpha(targetAlpha) end
        chip._targetAlpha=targetAlpha
        chip:SetScript("OnClick",function(_,button)
            if current.all then self.db.hiddenCharacters={}; self:Render()
            elseif current.overflow then
                local menu={}
                for _,char in ipairs(chars) do
                    local id=char.key
                    menu[#menu+1]={text=char.data.name .. "-" .. char.data.realm, checked=not self.db.hiddenCharacters[id], func=function()
                        self.db.hiddenCharacters[id]=not self.db.hiddenCharacters[id]; self:Render()
                    end}
                end
                SL.ShowCascadingMenu(chip,menu)
            elseif button == "RightButton" then self:CharacterMenu(chip,current.char.key)
            else self.db.hiddenCharacters[current.char.key]=not self.db.hiddenCharacters[current.char.key]; self:Render() end
        end)
        chip:Show(); x=x+(entry.width or 72)+6
    end
end

function S:RenderDetail(items, visible, weekday)
    local f = self.frame
    f.detailTitle:SetText(string.format(L["SCHEDULE_DATE"], self.month, self.day))
    local reset
    for _,item in ipairs(items) do if item.kind == "reset" then reset=item end end
    f.detailSub:SetText(L["SCHEDULE_WEEKDAY_" .. weekday] .. (reset and " · " .. L["SCHEDULE_RESET"] .. " " .. reset.time or ""))
    f.detailCount:SetText(string.format(L["SCHEDULE_ITEM_COUNT"], #items, visible))
    for _,row in ipairs(f.detailRows) do row:Hide() end
    local y, focusY = 0, nil
    for i,item in ipairs(items) do
        local row = f.detailRows[i]
        if not row then
            row=CreateFrame("Button",nil,f.detailChild,"BackdropTemplate"); f.detailRows[i]=row
            row.time=Label(row,12,accent,38); row.time:SetPoint("TOPLEFT",0,-7)
            row.title=Label(row,12,C.text.highlight,166); row.title:SetPoint("TOPLEFT",44,-7)
            row.badge=CreateFrame("Frame",nil,row,"BackdropTemplate"); row.badge:SetPoint("TOPLEFT",44,-25); row.badge:SetHeight(16)
            row.tag=Label(row.badge,11,C.text.dim); row.tag:SetPoint("CENTER")
            row.source=Label(row,11,C.text.dim); row.source:SetPoint("TOPLEFT",row.badge,"TOPRIGHT",5,-2)
            row.members={}
            row.line=Fill(row,T.BORDER_SEP); row.line:ClearAllPoints(); row.line:SetPoint("BOTTOMLEFT"); row.line:SetPoint("BOTTOMRIGHT"); row.line:SetHeight(1)
            row.progress=CreateFrame("StatusBar",nil,row); row.progress:SetPoint("BOTTOMLEFT",44,5); row.progress:SetSize(164,4)
            row.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8"); row.progress:SetStatusBarColor(unpack(accent)); row.progress:SetMinMaxValues(0,1)
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-y); row:SetWidth(212)
        row.title:SetText(item.title)
        row.progress:Hide()
        local timeText, tag, source, tagColor = "", "", "", C.text.disabled
        if item.kind == "event" then
            timeText=string.format("%02d:%02d",item.event.hour,item.event.minute)
            tag=self:EventTag(item.event)
            source=(item.event.calendarType == "GUILD_EVENT" or item.event.calendarType == "GUILD_ANNOUNCEMENT") and item.event.guildName or item.event.invitedBy
            tagColor=(item.event.calendarType == "GUILD_EVENT" or item.event.calendarType == "GUILD_ANNOUNCEMENT") and accent or T.SUCCESS
        elseif item.kind == "reset" then
            timeText=item.time; tag=item.released > 0 and string.format(L["SCHEDULE_UNLOCKS"],item.released) or L["SCHEDULE_RESET_CONTENT"]
            tagColor=T.WARNING
            if item.released > 0 then source=L["SCHEDULE_RESET_CONTENT"] end
        elseif item.kind == "lockout" then timeText=L["SCHEDULE_LOCKOUT"]; tag=L["SCHEDULE_RAID_LOCKOUT"]; tagColor=T.WARNING
        else
            timeText=L["SCHEDULE_HOLIDAY"]
            local _,sm,sd=self:DateFromDay(item.holiday.first); local _,em,ed=self:DateFromDay(item.holiday.last)
            tag=string.format(L["SCHEDULE_HOLIDAY_RANGE"],sm,sd,em,ed)
        end
        row.time:SetText(timeText); row.time:SetTextColor(unpack(item.kind == "holiday" and HolidayColor(item) or accent))
        -- [STYLE] 이전 항목의 제한 폭을 풀고 측정한 뒤 꼬리표 안에서 말줄임한다.
        row.tag:SetWidth(0)
        row.tag:SetText(tag); row.tag:SetTextColor(unpack(tagColor))
        row.badge:SetWidth(math.min(166,row.tag:GetStringWidth()+10)); Surface(row.badge,4,Alpha(tagColor,0.05),Alpha(tagColor,0.6))
        row.tag:SetWidth(row.badge:GetWidth()-10)
        row.source:SetWidth(math.max(1,161-row.badge:GetWidth())); row.source:SetShown(row.badge:GetWidth()<150)
        row.source:SetText(source or "")
        for _,memberRow in ipairs(row.members) do memberRow:Hide() end
        local height=49
        for j,member in ipairs(item.members) do
            local memberRow=row.members[j]
            if not memberRow then
                memberRow=CreateFrame("Frame",nil,row); row.members[j]=memberRow; memberRow:SetSize(166,16)
                memberRow.dot=CreateFrame("Frame",nil,memberRow,"BackdropTemplate"); memberRow.dot:SetSize(14,14); memberRow.dot:SetPoint("LEFT")
                memberRow.initial=Label(memberRow.dot,11,C.text.normal); memberRow.initial:SetPoint("CENTER")
                memberRow.label=Label(memberRow,11,C.text.dim,148); memberRow.label:SetPoint("LEFT",18,0)
            end
            local status=member.event and self:Status(member.event) or string.format("%d/%d",member.lockout.encounterProgress,member.lockout.numEncounters)
            memberRow:ClearAllPoints(); memberRow:SetPoint("TOPLEFT",44,-43-(j-1)*17)
            local color=ClassColor(member.char)
            Surface(memberRow.dot,8,C.bg.input,color)
            memberRow.initial:SetText(member.char.name:match("[%z\1-\127\194-\244][\128-\191]*") or "")
            memberRow.initial:SetTextColor(unpack(color))
            memberRow.label:SetText(Colored(member.char.name,color) .. " " .. status); memberRow:Show()
            height=height+17
        end
        if item.kind == "lockout" then row.progress:SetValue(item.progress); row.progress:Show(); height=height+8 end
        row:SetHeight(height)
        Surface(row,4,Alpha(accent,self.focusKey == item.key and 0.06 or 0),Alpha(accent,0))
        local current=item
        row:SetScript("OnEnter",function() Tooltip(row,current.title,self:ItemLines(current)) end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        row:Show()
        if self.focusKey == item.key then focusY=y end
        y=y+height
    end
    f.empty:SetText(visible == 0 and L["SCHEDULE_NO_CHARACTERS"] or L["SCHEDULE_EMPTY"])
    local hasCalendar=false
    for _,entry in ipairs(self:GetCharacters()) do if entry.data.updatedAt then hasCalendar=true; break end end
    if not hasCalendar then f.empty:SetText(self.failed and L["SCHEDULE_LOAD_FAILED"] or L["SCHEDULE_LOADING"]) end
    f.empty:SetShown(#items == 0)
    f.detailChild:SetHeight(math.max(1,y)); f.scrollMax=math.max(0,y-324)
    f.scrollbar:SetMinMaxValues(0,f.scrollMax); f.scrollbar:SetShown(f.scrollMax>0)
    f.scrollbar:SetValue(math.min(f.scrollMax,focusY or 0))
end

function S:RenderFooter()
    local f, chars = self.frame, self:GetCharacters()
    f.footerTitle:SetText(InCombatLockdown() and L["SCHEDULE_COMBAT_PENDING"] or L["SCHEDULE_CACHE_STATUS"] .. " · " .. #chars)
    f.footerTitle:SetTextColor(unpack(InCombatLockdown() and T.WARNING or C.text.dim))
    local lines, summary={},{ }
    for _,entry in ipairs(chars) do
        local age, stale=self:CacheAge(entry.data)
        local line=entry.data.name .. " · " .. age
        if stale then line=line .. " · " .. L["SCHEDULE_UPDATE_ON_LOGIN"] end
        lines[#lines+1]=line .. " · " .. entry.data.realm
        if #summary<3 then summary[#summary+1]=stale and Colored(line,T.WARNING) or line end
    end
    if #chars>3 then summary[3]="+" .. (#chars-2) .. " · " .. L["SCHEDULE_UPDATE_ON_LOGIN"] end
    f.cacheLines=lines; f.footer:SetText(table.concat(summary,"\n"))
end

function S:Render()
    local f=self.frame
    if not f then return end
    f.monthLabel:SetText(string.format(L["SCHEDULE_MONTH"],self.year,self.month))
    self:RenderChips()
    local first=self:DayNumber(self.year,self.month,1)
    local offset=(first+4)%7
    local weeks=math.max(5,math.ceil((offset+self:MonthDays(self.year,self.month))/7))
    local height=(510-22)/weeks
    local ty,tm,td=self:Today(); local today=self:DayNumber(ty,tm,td)
    local selected=self:DayNumber(self.year,self.month,self.day)
    for i,cell in ipairs(f.cells) do
        if i>weeks*7 then cell:Hide()
        else
            cell:Show(); cell:ClearAllPoints(); cell:SetPoint("TOPLEFT",(i-1)%7*654/7,-22-math.floor((i-1)/7)*height); cell:SetSize(654/7,height)
            local number=first-offset+i-1
            local _,month,day=self:DateFromDay(number)
            cell.dayNumber=number; cell.date:SetText(day); cell.date:SetTextColor(unpack(month==self.month and C.text.normal or T.TEXT_MUTED))
            local chosen,isToday=number==selected,number==today
            cell.bg:SetColorTexture(unpack(month~=self.month and Alpha(C.bg.input,0.25) or Alpha(accent,chosen and 0.12 or isToday and 0.06 or 0)))
            cell.selection:SetBackdropBorderColor(unpack(Alpha(accent,chosen and 0.9 or isToday and 0.35 or 0)))
            cell.todayPill:SetShown(isToday); cell.todayText:SetText(day); cell.date:SetShown(not isToday)
            local items,visible=self:GetDayItems(number); cell.items=items
            cell.reset:Hide(); cell.holidayBar:Hide(); cell.holidayName:Hide()
            local entries,festival={},nil
            for _,item in ipairs(items) do
                if item.kind=="reset" then cell.reset:Show()
                elseif item.kind=="holiday" then festival=festival or item
                elseif item.kind=="event" then entries[#entries+1]=item end
            end
            local top=24
            if festival then
                local color=HolidayColor(festival)
                cell.holidayBar:ClearAllPoints(); cell.holidayBar:SetPoint("TOPLEFT",number==festival.holiday.first and 4 or 0,-19)
                cell.holidayBar:SetWidth(654/7-(number==festival.holiday.first and 4 or 0)-(number==festival.holiday.last and 4 or 0))
                Surface(cell.holidayBar,2,color,Alpha(color,0)); cell.holidayBar:Show()
                if number==festival.holiday.first then cell.holidayName:SetText(festival.title); cell.holidayName:SetTextColor(unpack(color)); cell.holidayName:Show(); top=39 end
            end
            local capacity=math.min(4,math.floor((height-top-3)/19))
            -- [STYLE] 6주 달에도 일정 두 줄이 들어가도록 실제 더 보기 높이만 예약한다.
            if #entries>capacity then capacity=math.max(0,math.min(4,math.floor((height-top-3-cell.more:GetHeight())/19))) end
            for r,row in ipairs(cell.rows) do
                local item=entries[r]
                if r<=capacity and item then
                    row.item=item; row:ClearAllPoints(); row:SetPoint("TOPLEFT",4,-top-(r-1)*19); row:SetWidth(654/7-8); row.label:SetText(item.title)
                    local guild=item.event.calendarType=="GUILD_EVENT" or item.event.calendarType=="GUILD_ANNOUNCEMENT"
                    Surface(row,3,guild and Alpha(accent,0.10) or Alpha(C.text.highlight,0.05),Alpha(accent,0))
                    local count=guild and 1 or math.min(3,#item.members)
                    for j,stripe in ipairs(row.stripes) do
                        if j<=count then
                            stripe:ClearAllPoints(); stripe:SetPoint("TOPLEFT",0,-(j-1)*17/count); stripe:SetSize(3,17/count)
                            stripe:SetColorTexture(unpack(guild and accent or ClassColor(item.members[j].char))); stripe:Show()
                        else stripe:Hide() end
                    end
                    row:Show()
                else row.item=nil; row:Hide() end
            end
            cell.more:ClearAllPoints(); cell.more:SetPoint("TOPLEFT",6,-top-capacity*19); cell.more:SetWidth(654/7-12)
            cell.more.label:SetText(string.format(L["SCHEDULE_MORE"],math.max(0,#entries-capacity))); cell.more:SetShown(#entries>capacity)
        end
    end
    local items,visible=self:GetDayItems(selected)
    self:RenderDetail(items,visible,(selected+4)%7+1)
    self:RenderFooter()
end

function S:ToggleWindow()
    if self:IsUnavailable() then ns.Print(L["SCHEDULE_UNAVAILABLE"]); return end
    if not ns.db.profile.modules.Schedule then ns.DDingToolKit:OpenConfig("schedule"); return end
    if not self.db then self:OnInitialize() end
    self:CreateWindow()
    if self.frame:IsShown() then self.frame:HideAnimated(); return end
    self.year,self.month,self.day=self:Today(); self.focusKey=nil
    self:Render(); self.frame:ShowAnimated()
    local key=self:Identity(); local char=key and self.cache.characters[key]
    if not char or not char.updatedAt or self:ServerTime()-char.updatedAt>=60 then self:RequestRefresh() end
end

function S:ApplySettings() self.db=ns.db.profile.Schedule; self:RefreshWindow() end
