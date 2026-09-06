from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parents[1]


def calm_runtime(locale="koKR"):
    """Record the actual Lua draw calls for tests and the calendar mockup."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        local methods = {}
        regions = {}
        local function region(kind, name, parent, layer, subLevel)
            local value = setmetatable({kind=kind, name=name, parent=parent,
                layer=layer, subLevel=subLevel or 0, shown=true, alpha=1, scale=1, scripts={}}, {__index=methods})
            regions[#regions+1] = value
            return value
        end
        function CreateFrame(kind, name, parent) return region(kind, name, parent) end
        function methods:CreateTexture(name, layer, template, subLevel)
            return region("Texture", name, self, layer, subLevel)
        end
        function methods:CreateFontString(name, layer) return region("FontString", name, self, layer) end
        function methods:SetPoint(point, relative, relativePoint, x, y)
            self.point, self.relative, self.relativePoint, self.x, self.y = point, relative, relativePoint, x, y
        end
        function methods:ClearAllPoints() self.point=nil end
        function methods:SetAllPoints(parent) self.allPoints=parent end
        function methods:SetSize(width, height) self.width=width; self.height=height end
        function methods:SetWidth(width) self.width=width end
        function methods:SetHeight(height) self.height=height end
        function methods:SetRotation(rotation) self.rotation=rotation end
        function methods:SetAlpha(alpha) self.alpha=alpha end
        function methods:SetScale(scale) self.scale=scale end
        function methods:SetTexture(texture) self.texture=texture end
        function methods:SetColorTexture(...) self.color={...}; self.gradient=nil end
        function methods:SetGradient(direction, from, to) self.gradient={from,to} end
        function methods:SetTextColor(...) self.color={...} end
        function methods:SetFont(font,size,flags) self.font=font; self.fontSize=size; self.fontFlags=flags; return true end
        function methods:SetText(text) assert(self.fontSize, "Font not set"); self.text=text end
        function methods:SetScript(name, callback) self.scripts[name]=callback end
        function methods:IsShown() return self.shown end
        function methods:Show() self.shown=true end
        function methods:Hide() self.shown=false end
        for _, name in ipairs({"RegisterEvent", "SetClampedToScreen", "EnableMouse", "SetFrameStrata", "SetJustifyH", "SetJustifyV", "SetWordWrap"}) do
            methods[name] = function() end
        end
        function CreateColor(...) return {...} end
        UIParent = CreateFrame("Frame")
        ns = {L={}, DDingToolKit={RegisterModule=function() end}}
        function LibStub() return {NewLocale=function() return ns.L end} end
    ''')
    for file in ("Core/Database.lua", f"Locales/{locale}.lua", "Modules/LFGAlert/AlertFrame.lua",
                 "Modules/CalendarInviteAlert/CalendarInviteAlert.lua"):
        lua.execute((ROOT / file).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        ns.db = {profile=ns.defaults.profile}
        ns.CalendarInviteAlert:CreateAlertFrame()
        visual = ns.CalendarInviteAlert.alertVisual
    ''')
    return lua


def test_calendar_emblem_layout_and_shared_motion():
    for locale in ("koKR", "enUS"):
        lua = calm_runtime(locale)
        lua.execute('''
            local frame = visual.frame
            assert(#frame.calendarMark == 11)
            ns.CalendarInviteAlert:ShowAlert(true)
            visual:OnUpdate(1)
            assert(frame:IsShown() and frame.art.alpha == 1)
            assert(frame.diamondTopLeft.alpha == 0)
            assert(frame.calendarMark[1].alpha == 1)
            assert(frame.topLeft.x == -18 and frame.topRight.x == 18)
            assert(frame.title.text == ns.L.CALENDARALERT_ALERT_TITLE)
            assert(frame.subtitle.text == string.format(ns.L.CALENDARALERT_PENDING_TEXT, 3))
            local allocated = #regions
            visual:OnUpdate(4.8)
            assert(frame.art.alpha > 0 and frame.art.alpha < 1)
            visual:OnUpdate(0.21)
            assert(not frame:IsShown() and not visual.state and #regions == allocated)

            for _, dimensions in ipairs({{320,80}, {500,112}, {760,170}}) do
                local db = ns.db.profile.CalendarInviteAlert
                db.width, db.height, db.fontSize = dimensions[1], dimensions[2], 36
                db.accentColor = {0.9,0.2,0.3,0.7}
                db.animationEnabled = false
                ns.CalendarInviteAlert:ShowAlert(true)
                assert(frame.calendarMark[1].color[1] == 0.9 and frame.calendarMark[1].color[4] == 0.7)
                local titleTop = frame.title.y + frame.title.fontSize * 0.5
                local titleBottom = frame.title.y - frame.title.fontSize * 0.5
                local subtitleTop = frame.subtitle.y + frame.subtitle.fontSize * 0.5
                assert(titleTop < frame.calendarMark[4].y, "title overlaps calendar emblem")
                assert(subtitleTop < titleBottom, "title overlaps invitation count")
                local titleY = frame.title.y
                visual:OnUpdate(0.2)
                assert(frame.title.y == titleY and frame.art.alpha == 1, "motion OFF must stay static")
                ns.CalendarInviteAlert:ShowAlert(true, nil, {key="test", hour=20, minute=30, title=ns.L.CALENDARALERT_TODAY_EXAMPLE})
                assert(frame.title.text == string.format(ns.L.CALENDARALERT_TODAY_TITLE, 20, 30))
                assert(frame.subtitle.text == ns.L.CALENDARALERT_TODAY_EXAMPLE)
            end
            visual:Hide(true)
            assert(not frame:IsShown() and not visual.state)

            for _, kind in ipairs({"APPLICATION", "COMPLETE"}) do
                local party = ns.CreateCalmPartyAlert("PartyTest")
                party:Apply(ns.db.profile.PartyFullAlert)
                party:Show("Party", "Ready", {animated=true, duration=6, motionKind=kind, nodeCount=5})
                party:OnUpdate(1)
                assert(not party.frame.calendarMark, "calendar art must not leak into other alerts")
                assert(party.frame.diamondTopLeft.alpha == 1)
                assert(party.frame.title.y == 9 and party.frame.subtitle.y == -17)
                assert(party.frame.topLeft.x == -10 and party.frame.nodes[5]:IsShown())
                assert(party.motionKind == kind)
                party:OnUpdate(5.1)
                assert(not party.frame:IsShown())
            end
        ''')
