"""Run with python test_custom_aura_alerts.py (installed lupa.lua51).

Exercises actual Lua policy, sound registration, alert evaluation and options.
WoW API boundaries are stubs; this does not simulate taint or an in-game encounter.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent
RB = "DDingUI_CDM/Modules/ResourceBars/"


def source(path):
    return (ROOT / path).read_text(encoding="utf-8-sig")


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        function noop() end
        function wipe(t) for k in pairs(t) do t[k] = nil end end
        function CreateFrame()
            return {SetScript=noop, RegisterEvent=noop, UnregisterAllEvents=noop}
        end
        C_Timer = {After=noop, NewTicker=function() return {Cancel=noop} end}
        function GetBuildInfo() return "12.1.0", "test", "", 120100 end
        function GetSpecialization() return 4 end
        function GetSpecializationInfo() return 105 end
        function IsInInstance() return false, "none" end
        function InCombatLockdown() return combat or false end
        UnitAffectingCombat = InCombatLockdown
        function GetTime() return 100 end
        C_Secrets = {ShouldAurasBeSecret=function() return restricted or false end}
        Enum = {UnitAuraSoundTrigger={Added=0, ApplicationsIncreased=1, Removed=2}}
        media = {Fetch=function(_, _, key) if key == "Cat" then return "cat.ogg" end end}
        function LibStub() return media end
        L = setmetatable({}, {__index=function(_, k) return k end})
        DDingUI = {ResourceBars={}, TrackedAuraContainer={}, UpdateBuffTrackerBar=noop}
        ns = {Addon=DDingUI, L=L}
        Engine = DDingUI.TrackedAuraContainer
        ResourceBars = DDingUI.ResourceBars
        function TrackerCooldownID(t) return t.cooldownID or 0 end
        function TrackerSpellID(t) return t.spellID or 0 end
        function Engine:GetTrackedSpellIDs(t) return {t.spellID} end
        registrations, removed, nextID = {}, 0, 0
        C_UnitAuras = {
            AddAuraSound=function(event, info)
                assert(not combat and not restricted)
                nextID = nextID + 1
                registrations[nextID] = {event=event, info=info}
                return nextID
            end,
            RemoveAuraSound=function(id)
                assert(not combat and not restricted)
                registrations[id] = nil; removed = removed + 1
            end,
            GetPlayerAuraBySpellID=function() error("unexpected aura read") end,
        }
        C_Spell = {GetSpellName=function() return "Lifebloom" end}
        function tracker(kind, value)
            return {spellID=33763, cooldownID=9020, isAura=true, displayType="trigger", settings={
                alerts={enabled=true, triggers={{type=kind, op="==", value=value}},
                    actions={{type="sound", condition="any", soundFile="Cat", soundMode="once"}}}}}
        end
    ''')
    container = source(RB + "TrackedAuraContainer.lua")
    lua.execute(container[container.index("function Engine:IsAutomaticAuraTracker"):
                          container.index("local function AddInfoSpellIDs")])
    for name in ("TrackedAuraProtectedAlerts", "TrackedAuraSounds", "TrackedAuraProtectedGlow"):
        lua.execute(source(RB + name + ".lua"), "DDingUI_CDM", lua.globals().ns)
    lua.execute('''
        t = tracker("active", true)
        a = t.settings.alerts.actions[1]
        sounds = DDingUI.TrackedAuraSounds
        for _, event in ipairs({"start", "end", "applications"}) do
            t.displayType = "sound"; t.settings.soundTrigger = event; t.settings.soundFile = "Cat"
            t.settings.alerts.enabled = false
            sounds:Sync({t})
            assert(sounds:IsNative(t))
            local expected = ({start=0, ["end"]=2, applications=1})[event]
            for _, r in pairs(registrations) do assert(r.event == expected and r.info.spellID == 33763) end
        end
        t.displayType = "trigger"; t.settings.alerts.enabled = true
        for _, kind in ipairs({"active", "applications"}) do
            t.settings.alerts.triggers[1].type = kind
            sounds:Sync({t}); assert(sounds:IsNativeAlertAction(a))
            for _, r in pairs(registrations) do assert(r.event == (kind == "active" and 0 or 1)) end
        end
        t.settings.alerts.triggers[1] = {type="active", op="!=", value=true}
        sounds:Sync({t})
        for _, r in pairs(registrations) do assert(r.event == 2) end
        for _, kind in ipairs({"duration", "duration_percent", "stacks"}) do
            t.settings.alerts.triggers[1] = {type=kind, op="<=", value=4}
            sounds:Sync({t})
            assert(not sounds:IsNativeAlertAction(a) and next(registrations) == nil)
            assert(Engine:GetAlertActionIssue(t, a))
        end
        t.settings.alerts.triggers = {{type="active", op="==", value=true}, {type="combat", op="==", value=true}}
        assert(Engine:GetAlertConditionKind(t, "any") == nil)
        a.condition = "trigger1"; combat = true
        local before = nextID
        sounds:Sync({t}); assert(nextID == before and sounds:GetDiagnostics().pending)
        combat = false; sounds:Invalidate(); sounds:Sync({t})
        assert(sounds:IsNativeAlertAction(a))
        restricted = true; a.condition = "trigger2"; before = nextID
        sounds:Sync({t}); assert(sounds:GetDiagnostics().pending and nextID == before)
        restricted = false; sounds:Invalidate(); sounds:Sync({t})
        a.condition = "trigger1"
        a.soundMode = "repeat"; sounds:Sync({t})
        assert(not sounds:IsNativeAlertAction(a))
        assert(Engine:GetAlertActionIssue(t, a) == "Aura Alert Event Sound Only")
        a.condition = "trigger2"; assert(not Engine:GetAlertActionIssue(t, a))
        a.soundMode = "once"; a.condition = "trigger1"
        t.settings.alerts.actions[2] = {type="glow", condition="trigger1", visualTarget="cdm:9020"}
        local presentation = Engine:GetProtectedTriggerPresentation(t)
        assert(presentation and #presentation.actions == 1 and presentation.actions[1].type == "glow")
        t.settings.alerts.actions[3] = {type="glow", condition="trigger1", visualTarget="custom:other"}
        assert(not Engine:GetProtectedTriggerPresentation(t))
        t.settings.alerts.actions[3] = nil
        t.displayType = "icon"; local glow = t.settings.alerts.actions[2]; glow.visualTarget = "self"
        assert(not Engine:GetAlertActionIssue(t, glow))
        glow.type = "color"; glow.colorTarget = "group"
        assert(Engine:GetAlertActionIssue(t, glow) == "Aura Alert Self Visual Only")
    ''')

    bar = source(RB + "BuffTrackerBar.lua")
    lua.execute('''
        function IsSecretValue(v) return v == "secret" end
        function IsAccessibleNumber(v) return type(v) == "number" end
        function HasAuraInstanceID(v) return v ~= nil end
        function IsProtectedAuraObservation(s, id) return id == "secret" end
        LegacyAuraDriver = {ResolvePlayerAuraPresence=function() error("unexpected presence read") end}
        LegacyDurationDriver = {ReadTiming=function() return 10, 103, 3, false end}
        cdmVisibility = {protectedConditionsSkipped=0}
        played = 0
        function PlayTrackerSound() played = played + 1 end
        math_max = math.max
        soundHost = {}
        function GetSoundTracker() return soundHost end
        function ResourceBars:CancelTrackedBuffSoundTimer() end
    ''')
    evaluation = bar[bar.index("local alertRuntimeOwners ="):
                     bar.index("local function ScheduleAlertEvaluation")]
    lua.execute(evaluation + "\nEvaluate, Apply = EvaluateAlerts, ApplyAlertActions")
    sound_update = bar[bar.index("function ResourceBars:UpdateSingleTrackedBuffSound"):
                       bar.index("function ResourceBars:UpdateSingleTrackedBuffText")]
    lua.execute(sound_update)
    trigger_update = bar[bar.index("function ResourceBars:UpdateSingleTrackedBuffTrigger"):
                         bar.index("function ResourceBars:UpdateBuffTrackerBar()")]
    lua.execute('''
        EvaluateAlerts, ApplyAlertActions = Evaluate, Apply
        host = {Hide=noop, GetFrameLevel=function() return 1 end}
        function GetTrackedBuffBar() return host end
        function HasTrackedAuraData() return false end
        function ScheduleAlertEvaluation() end
        function ResolveTrackedFrame() error("unexpected CDM observation") end
        DDingUI.TrackedAuraFrameResolver = {AttachAuraContainer=function() return true end}
    ''')
    lua.execute(trigger_update)
    lua.execute('''
        t = tracker("duration", 4); t.settings.alerts.triggers[1].op = "<="
        frame = {}
        for _, id in ipairs({42, "secret"}) do
            local result = Evaluate(t, 1, true, id, "player")
            assert(result.combined == false and result.protectedTriggers[1])
            Apply(result, t, frame, 1); assert(played == 0)
        end
        t.trackingMode = "manual"
        local result = Evaluate(t, 1, true, 42, "player")
        assert(result.combined)
        Apply(result, t, frame, 1); Apply(result, t, frame, 1); assert(played == 1)
        t.trackingMode = nil; t.settings.alerts.triggers[1] = {type="combat", op="==", value=true}
        combat = true; frame = {}
        Apply(Evaluate(t, 0, false), t, frame, 1); assert(played == 2)
        combat = false
        t.settings.alerts.triggers[2] = {type="active", op="==", value=true}
        t.settings.alerts.actions[1].condition = "trigger1"
        t.settings.alerts.actions[2] = {type="glow", condition="trigger2", visualTarget="cdm:9020"}
        combat = true
        ResourceBars:UpdateSingleTrackedBuffTrigger(1, t, {}); assert(played == 3)
        combat = false
        t.displayType="sound"; t.settings.soundTrigger="endBefore"
        ResourceBars:UpdateSingleTrackedBuffSound(1, t, {}) -- must not read aura state
        assert(played == 3 and not soundHost.initialized)
    ''')

    group_source = source("DDingUI_CDM/Core/ConditionalActions.lua")
    group_eval = group_source[:group_source.index("local function EvaluateGroupTriggers")]
    lua.execute(group_eval + "\nEvaluateGroupSet = EvaluateSetTriggers", "DDingUI_CDM", lua.globals().ns)
    lua.execute('''
        local group = {controlledChildren={1}}
        local rule = {triggers={{source="child", childIndex=1, condition="inactive"}}}
        assert(not EvaluateGroupSet(rule, group, {t}))
        assert(not EvaluateGroupSet(rule, group, {}))
    ''')

    lua.execute('''
        t = tracker("duration", 4); t.settings.alerts.triggers[1].op = "<="
        t.expanded = true
        DDingUI.db = {global={trackedBuffsPerSpec={[105]={t}}}, profile={buffTrackerBar={}}}
    ''')
    helpers = source("DDingUI_CDM_Option/ConfigHelpers.lua")
    lua.execute("local _, ns = ...\n" + helpers[helpers.index("local OPTION_BUILDER_INTERNAL_KEYS ="):],
                "DDingUI_CDM_Option", lua.globals().ns)
    lua.execute(source("DDingUI_CDM_Option/BuffTrackerOptions.lua"), "DDingUI_CDM_Option", lua.globals().ns)
    lua.execute('''
        local options = ns.CreateTrackedBuffOptions(1, 0, true)
        local types = options.tracked1_alertT1_type.values()
        assert(types.applications and types.active and types.combat)
        assert(types.duration:find("Unsupported in 12.1") and not types.stacks)
        assert(options.tracked1_alertT1_value.disabled())
        assert(t.settings.alerts.triggers[1].type == "duration" and t.settings.alerts.triggers[1].value == 4)
        options.tracked1_alertT1_type.set(nil, "stacks")
        assert(t.settings.alerts.triggers[1].type == "duration")
        options.tracked1_alertT1_type.set(nil, "applications")
        assert(options.tracked1_alertT1_op.hidden() and options.tracked1_alertT1_value.hidden())
        local args = options.tracked1_alertAction1.args
        assert(args.type.values().sound and not args.type.values().color)
        assert(not args.soundMode.values()["repeat"])
        t.trackingMode = "manual"
        assert(options.tracked1_alertT1_type.values().stacks)
        assert(not options.tracked1_alertT1_value.disabled() and args.soundMode.values()["repeat"])
        t.settings.alerts.triggers = {{type="active"}, {type="combat"}, {type="stacks"}}
        t.settings.alerts.actions = {{type="sound",condition="trigger2"}, {type="sound",condition="trigger3"}}
        options.tracked1_alertT2_remove.func()
        assert(t.settings.alerts.actions[1].condition == "none")
        assert(t.settings.alerts.actions[2].condition == "trigger2")
    ''')
    lua.execute('''
        function media:GetLocale() return L end
        t.trackingMode = nil
        manual = tracker("active", true); manual.trackingMode = "manual"
        group = {isGroup=true, controlledChildren={1,2}, groupSettings={
            conditionalActions={enabled=true, sets={{triggers={{source="child",childIndex=1}}, actions={}}}}}}
        DDingUI.db.global.trackedBuffsPerSpec[105] = {t, manual, group}
    ''')
    lua.execute(source("DDingUI_CDM_Option/BuffTrackerGroupOptions.lua"), "DDingUI_CDM_Option", lua.globals().ns)
    lua.execute('''
        local options = ns.CreateGroupOptions(3)
        assert(not options.set_add.disabled())
        options.set_add.func()
        assert(group.groupSettings.conditionalActions.sets[2].triggers[1].childIndex == 2)
        manual.trackingMode = nil
        options = ns.CreateGroupOptions(3)
        assert(options.set_add.disabled())
    ''')
    print("PASS: native aura events, restricted registration, unsupported saved alerts, combat/manual alerts, glow+sound, group unknown state, options and deletion references")


if __name__ == "__main__":
    main()
