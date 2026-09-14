local _, ns = ...
local Probe = {}
ns.AffixProbe = Probe

local LIMIT = 2000
local lines, auras = {}, {}
local running, collecting, startedAt = false, false, 0
local eventFrame, reportFrame
local IsSecret = ns.IsSecretValue
local runEvents = {
    "ENCOUNTER_TIMELINE_EVENT_ADDED", "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
    "ENCOUNTER_TIMELINE_EVENT_REMOVED", "ENCOUNTER_TIMELINE_STATE_UPDATED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE",
}

local function PublicTable(value)
    return not IsSecret(value) and type(value) == "table"
end

local function PublicNumber(value)
    return not IsSecret(value) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end

-- Never stringify names, GUIDs, or restricted values, even for diagnostics.
local function Scalar(value)
    if IsSecret(value) then return "restricted" end
    if PublicNumber(value) or type(value) == "boolean" then return tostring(value) end
    return "unknown"
end

function Probe:Stop(reason)
    if running then
        self:Record("STOP " .. reason)
        running, collecting = false, false
        eventFrame:UnregisterAllEvents()
        auras = {}
        print("DDT affix: stopped. /ddt affix report")
    end
end

function Probe:Record(text)
    if not running then return end
    if #lines >= LIMIT then return end
    lines[#lines + 1] = string.format("%.3f %s", GetTime() - startedAt, text)
    if #lines == LIMIT then
        running, collecting = false, false
        eventFrame:UnregisterAllEvents()
        auras = {}
        print("DDT affix: log limit reached. /ddt affix report")
    end
end

function Probe:Timeline(kind, info)
    if not PublicTable(info) then
        self:Record(kind .. " info=restricted-or-unavailable")
        return
    end
    local id = info.id
    local state, remaining
    if PublicNumber(id) then
        state = C_EncounterTimeline.GetEventState(id)
        remaining = C_EncounterTimeline.GetEventTimeRemaining(id)
    end
    self:Record(kind .. " id=" .. Scalar(id) .. " source=" .. Scalar(info.source)
        .. " spell=" .. Scalar(info.spellID) .. " duration=" .. Scalar(info.duration)
        .. " state=" .. Scalar(state) .. " remaining=" .. Scalar(remaining))
end

function Probe:SnapshotTimeline()
    if not collecting or not C_EncounterTimeline then return end
    local ids = C_EncounterTimeline.GetEventList()
    if not PublicTable(ids) then
        self:Record("TIMELINE_LIST unavailable")
        return
    end
    local count = 0
    for _, id in ipairs(ids) do
        if not collecting then break end
        count = count + 1
        if PublicNumber(id) then
            self:Timeline("TIMELINE_SNAPSHOT", C_EncounterTimeline.GetEventInfo(id))
        else
            self:Record("TIMELINE_SNAPSHOT id=restricted-or-unavailable")
        end
    end
    self:Record("TIMELINE_LIST count=" .. count)
end

function Probe:Aura(kind, info)
    if not PublicTable(info) then return end
    local id, spellID = info.auraInstanceID, info.spellId
    if not PublicNumber(id) or not PublicNumber(spellID) then return end
    local data = " spell=" .. Scalar(spellID) .. " helpful=" .. Scalar(info.isHelpful)
        .. " duration=" .. Scalar(info.duration) .. " expires=" .. Scalar(info.expirationTime)
    if auras[id] == data and kind ~= "AURA_SNAPSHOT" then return end
    auras[id] = data
    self:Record(kind .. " id=" .. Scalar(id) .. data)
end

function Probe:SnapshotAuras()
    if not collecting or not C_UnitAuras then return end
    auras = {}
    for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
        -- Bounded diagnostic snapshot; normal collection uses UNIT_AURA deltas.
        for index = 1, 255 do
            if not collecting then return end
            local info = C_UnitAuras.GetAuraDataByIndex("player", index, filter)
            if IsSecret(info) then
                self:Record("AURA_SNAPSHOT restricted")
                break
            end
            if info == nil then break end
            self:Aura("AURA_SNAPSHOT", info)
        end
    end
end

function Probe:UnitAura(unit, update)
    if IsSecret(unit) or unit ~= "player" then return end
    if not PublicTable(update) or IsSecret(update.isFullUpdate) then return end
    if update.isFullUpdate then self:SnapshotAuras(); return end
    if PublicTable(update.addedAuras) then
        for _, info in ipairs(update.addedAuras) do
            if not collecting then return end
            self:Aura("AURA_ADD", info)
        end
    end
    if PublicTable(update.updatedAuraInstanceIDs) and C_UnitAuras then
        for _, id in ipairs(update.updatedAuraInstanceIDs) do
            if not collecting then return end
            if PublicNumber(id) then
                self:Aura("AURA_UPDATE", C_UnitAuras.GetAuraDataByAuraInstanceID("player", id))
            end
        end
    end
    if PublicTable(update.removedAuraInstanceIDs) then
        for _, id in ipairs(update.removedAuraInstanceIDs) do
            if not collecting then return end
            if PublicNumber(id) and auras[id] then
                self:Record("AURA_REMOVE id=" .. Scalar(id) .. auras[id])
                auras[id] = nil
            end
        end
    end
end

function Probe:Context(event)
    self:Record(event)
    local active = C_ChallengeMode.IsChallengeModeActive()
    if IsSecret(active) then return end
    if not active then
        if collecting then self:Stop("left-challenge") end
        return
    end
    local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()
    local ids = {}
    if PublicTable(affixes) then
        for _, id in ipairs(affixes) do ids[#ids + 1] = Scalar(id) end
    end
    self:Record("KEY map=" .. Scalar(C_ChallengeMode.GetActiveChallengeMapID())
        .. " level=" .. Scalar(level) .. " affixes=" .. table.concat(ids, ","))
    if collecting or not running then return end
    collecting = true
    for _, name in ipairs(runEvents) do
        if C_EncounterTimeline or not name:match("^ENCOUNTER_TIMELINE") then
            eventFrame:RegisterEvent(name)
        end
    end
    if C_UnitAuras then eventFrame:RegisterUnitEvent("UNIT_AURA", "player") end
    self:SnapshotTimeline()
    self:SnapshotAuras()
end

function Probe:OnEvent(event, arg, update)
    if not running then return end
    if event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
        self:Stop(event)
    elseif event == "CHALLENGE_MODE_START" or event == "PLAYER_ENTERING_WORLD" then
        self:Context(event)
    elseif not collecting then
        return
    elseif event == "UNIT_AURA" then
        self:UnitAura(arg, update)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        self:Timeline(event, arg)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        if PublicNumber(arg) then self:Timeline(event, C_EncounterTimeline.GetEventInfo(arg)) end
    elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        -- Removed events can no longer be queried.
        self:Record(event .. " id=" .. Scalar(arg))
    elseif event == "ENCOUNTER_TIMELINE_STATE_UPDATED" then
        self:SnapshotTimeline()
    else
        self:Record(event)
    end
end

function Probe:Start()
    if running then print("DDT affix: already collecting/armed."); return end
    if not C_ChallengeMode or not C_ChallengeMode.IsChallengeModeActive then
        print("DDT affix: ChallengeMode API unavailable."); return
    end
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)
    end
    lines, auras = {}, {}
    startedAt, running, collecting = GetTime(), true, false
    local _, build, _, interface = GetBuildInfo()
    self:Record("PROBE v1 interface=" .. Scalar(interface) .. " build=" .. (tonumber(build) or 0)
        .. " clock=" .. Scalar(startedAt) .. " timeline=" .. tostring(C_EncounterTimeline ~= nil))
    for _, name in ipairs({"CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET", "PLAYER_ENTERING_WORLD"}) do
        eventFrame:RegisterEvent(name)
    end
    self:Context("ARMED")
    print("DDT affix: armed for M+. /ddt affix mark when visible; report before /reload.")
end

function Probe:GetReport()
    return "DDT affix probe (public metadata only; not a timer)\n"
        .. "Missing/restricted data does not prove an affix is absent. Source IDs are not affix classifications.\n"
        .. "Lines=" .. #lines .. "/" .. LIMIT .. " running=" .. tostring(running) .. "\n"
        .. table.concat(lines, "\n")
end

function Probe:ShowReport()
    if InCombatLockdown() then print("DDT affix: open report out of combat."); return end
    if not reportFrame then
        reportFrame = ns.UI:CreateMainFrame(UIParent, 660, 420)
        ns.UI:CreateTitleBar(reportFrame, "Affix probe")
        local scroll = CreateFrame("ScrollFrame", nil, reportFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -46)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal)
        box:SetTextColor(0.9, 0.9, 0.9)
        box:SetJustifyH("LEFT")
        box:SetWidth(600)
        box:SetMaxLetters(0)
        scroll:SetScrollChild(box)
        box:SetScript("OnTextChanged", function()
            box:SetHeight(math.max(350, box:GetStringHeight() + 16))
        end)
        box:SetScript("OnEscapePressed", function() reportFrame:Hide() end)
        reportFrame:SetScript("OnHide", function() box:ClearFocus() end)
        reportFrame.box, reportFrame.scroll = box, scroll
    end
    self:Stop("report")
    reportFrame:Show()
    reportFrame.box:SetText(self:GetReport())
    reportFrame.box:SetCursorPosition(0)
    reportFrame.scroll:SetVerticalScroll(0)
    reportFrame.box:SetFocus()
    reportFrame.box:HighlightText()
end

function Probe:Command(arg)
    arg = arg:lower()
    if arg == "on" then self:Start()
    elseif arg == "off" then self:Stop("manual")
    elseif arg == "report" then self:ShowReport()
    elseif arg == "mark" and collecting then
        self:Record("MANUAL_AFFIX_MARK")
        self:SnapshotTimeline()
        self:SnapshotAuras()
        print("DDT affix: marked.")
    else
        print("DDT affix: /ddt affix on | mark (in M+) | off | report. Runtime only; /reload clears the log.")
    end
end
