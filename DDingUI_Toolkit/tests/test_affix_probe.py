from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parents[1]


def test_affix_probe_public_signals_lifecycle_and_copy_report():
    lua = LuaRuntime()
    lua.execute('''
        frames, messages = {}, {}
        now, active, combat = 100, false, false
        secret = setmetatable({}, {
            __index=function() error("secret indexed") end,
            __tostring=function() error("secret stringified") end,
            __eq=function() error("secret compared") end,
        })
        ns = {DDingToolKit={}}
        ns.IsSecretValue = function(v) return rawequal(v, secret) end
        function GetTime() return now end
        function GetBuildInfo() return "12.1.0", "123456", "date", 120100 end
        function InCombatLockdown() return combat end
        function print(text) messages[#messages+1] = text end
        function CreateFrame(kind)
            local f = {events={}, scripts={}, kind=kind}
            function f:RegisterEvent(event) self.events[event] = true end
            function f:RegisterUnitEvent(event, unit) self.events[event] = unit end
            function f:UnregisterAllEvents() self.events = {} end
            function f:SetScript(event, callback) self.scripts[event] = callback end
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide() end end
            function f:SetText(text) self.text=text; self.scripts.OnTextChanged() end
            function f:SetFocus() self.focused = true end
            function f:ClearFocus() self.focused = false end
            function f:GetStringHeight() return 400 end
            function f:SetHeight(height) self.height=height end
            for _, method in ipairs({"SetPoint", "SetMultiLine", "SetAutoFocus", "SetFontObject",
                "SetTextColor", "SetJustifyH", "SetWidth", "SetMaxLetters", "SetScrollChild",
                "SetCursorPosition", "SetVerticalScroll", "HighlightText"}) do
                f[method] = function() end
            end
            frames[#frames+1] = f
            return f
        end
        ns.UI = {
            CreateMainFrame=function() return CreateFrame("Report") end,
            CreateTitleBar=function() end,
        }
        C_ChallengeMode = {
            IsChallengeModeActive=function() return active end,
            GetActiveKeystoneInfo=function() return 8, {10, 152}, false end,
            GetActiveChallengeMapID=function() return 555 end,
        }
        timelineInfo = {id=12, source=0, spellID=999, duration=80}
        timelineIDs = {12}
        C_EncounterTimeline = {
            GetEventList=function() return timelineIDs end,
            GetEventInfo=function(id) assert(type(id)=="number"); return timelineInfo end,
            GetEventState=function(id) assert(type(id)=="number"); return 1 end,
            GetEventTimeRemaining=function(id) assert(type(id)=="number"); return secret end,
        }
        auraInfo = {auraInstanceID=101, spellId=456, isHelpful=false, duration=15, expirationTime=115}
        C_UnitAuras = {
            GetAuraDataByIndex=function(unit, index, filter)
                assert(unit=="player")
                if index==1 and filter=="HARMFUL" then return auraInfo end
            end,
            GetAuraDataByAuraInstanceID=function(unit, id)
                assert(unit=="player" and type(id)=="number"); return auraInfo
            end,
        }
        SlashCmdList = {}
    ''')
    for file in ("Core/SlashCommands.lua", "Modules/MythicPlusHelper/AffixProbe.lua"):
        lua.execute((ROOT / file).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        local probe = ns.AffixProbe
        local function command(arg) SlashCmdList.DDINGTOOLKIT("affix "..arg) end
        assert(#frames==0, "Diagnostic must be opt-in, independent of module defaults")
        command("on")
        local frame = frames[1]
        local function event(name, ...)
            now = now + 1
            if frame.events[name] then frame.scripts.OnEvent(frame, name, ...) end
        end
        assert(frame.events.CHALLENGE_MODE_START and not frame.events.UNIT_AURA)
        assert(not probe:GetReport():find("AURA_SNAPSHOT"))
        local before = probe:GetReport()
        command("on")
        assert(probe:GetReport()==before, "Repeated on must not erase a live capture")
        active = true
        event("CHALLENGE_MODE_START")
        assert(frame.events.UNIT_AURA=="player")
        assert(probe:GetReport():find("KEY map=555 level=8 affixes=10,152", 1, true))
        assert(probe:GetReport():find("remaining=restricted", 1, true))
        assert(probe:GetReport():find("AURA_SNAPSHOT id=101 spell=456", 1, true))
        event("UNIT_AURA", "player", {addedAuras={auraInfo}})
        assert(not probe:GetReport():find("AURA_ADD"), "Duplicate aura updates should be silent")
        auraInfo.expirationTime = 130
        event("UNIT_AURA", "player", {updatedAuraInstanceIDs={101}})
        assert(probe:GetReport():find("AURA_UPDATE"))
        event("UNIT_AURA", "player", {removedAuraInstanceIDs={101}})
        assert(probe:GetReport():find("AURA_REMOVE"))
        event("PLAYER_DEAD")
        event("PLAYER_REGEN_ENABLED")
        assert(frame.events.UNIT_AURA, "Local death/combat end must not stop an M+ capture")
        command("mark")
        assert(probe:GetReport():find("MANUAL_AFFIX_MARK"))

        event("ENCOUNTER_TIMELINE_EVENT_ADDED", secret)
        event("ENCOUNTER_TIMELINE_EVENT_ADDED", {id=secret, source=secret, spellID=secret, duration=secret})
        event("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", secret)
        event("ENCOUNTER_TIMELINE_EVENT_REMOVED", secret)
        event("UNIT_AURA", secret, secret)
        event("UNIT_AURA", "player", secret)
        event("UNIT_AURA", "player", {isFullUpdate=secret})
        event("UNIT_AURA", "player", {addedAuras=secret, updatedAuraInstanceIDs=secret, removedAuraInstanceIDs=secret})
        event("UNIT_AURA", "player", {addedAuras={secret, {auraInstanceID=secret, spellId=secret}}})
        event("UNIT_AURA", "player", {updatedAuraInstanceIDs={secret}, removedAuraInstanceIDs={secret}})
        auraInfo, timelineIDs = secret, secret
        event("UNIT_AURA", "player", {isFullUpdate=true})
        event("ENCOUNTER_TIMELINE_STATE_UPDATED")
        C_EncounterTimeline.GetEventInfo = function() error("Removed event must not be queried") end
        event("ENCOUNTER_TIMELINE_EVENT_REMOVED", 12)
        combat = true
        command("report")
        assert(#frames==1 and frame.events.UNIT_AURA, "Report UI must not open or stop collection in combat")
        event("CHALLENGE_MODE_COMPLETED")
        assert(next(frame.events)==nil)
        local stopped = probe:GetReport()
        event("PLAYER_REGEN_DISABLED")
        assert(probe:GetReport()==stopped)
        combat = false
        command("report")
        assert(#frames==4 and frames[2].shown and frames[4].focused)
        assert(frames[4].text==stopped)
        frames[4].scripts.OnEscapePressed()
        assert(not frames[2].shown and not frames[4].focused)
        command("report")
        assert(#frames==4, "Copy window should be reused")

        active, C_EncounterTimeline, C_UnitAuras = false, nil, nil
        command("on")
        active = true
        event("CHALLENGE_MODE_START")
        assert(not frame.events.UNIT_AURA and not frame.events.ENCOUNTER_TIMELINE_EVENT_ADDED)
        active = false
        event("PLAYER_ENTERING_WORLD")
        assert(next(frame.events)==nil and probe:GetReport():find("STOP left%-challenge"))
        command("on")
        for i=1,3000 do probe:Record("BOUNDED") end
        local capped = probe:GetReport()
        assert(capped:find("Lines=2000/2000 running=false", 1, true))
        assert(next(frame.events)==nil)
        probe:Record("SHOULD_NOT_APPEAR")
        assert(probe:GetReport()==capped)
        command("on")
        command("off")
        assert(next(frame.events)==nil and probe:GetReport():find("STOP manual"))
        command("on")
        event("CHALLENGE_MODE_RESET")
        assert(next(frame.events)==nil)
    ''')
    source = (ROOT / "Modules/MythicPlusHelper/AffixProbe.lua").read_text()
    for forbidden in ("COMBAT_LOG_EVENT_UNFILTERED", "SetAttribute", "hooksecurefunc", "C_Timer", "SavedVariables"):
        assert forbidden not in source
    assert "Modules\\MythicPlusHelper\\AffixProbe.lua" in (ROOT / "DDingUI_Toolkit.toc").read_text(encoding="utf-8-sig")
