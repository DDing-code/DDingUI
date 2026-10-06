"""Auto width ("fit anchor width", width = 0) runs through one shared rule.

Lua 5.1 checks against the real Utils/Toolkit.lua, GroupSystem/GroupRenderer.lua and
ResourceBars/PrimaryPowerBar.lua:
  * DDingUI:ResolveAutoWidth - no fixed 600/1000 cap, border compensation from the bar's own
    border, invalid (secret / NaN / <= 0 / wider than UIParent) falls back to the bar's last good
    auto width and only then to 200; noStore never writes; anchor change resets the memory,
  * __cdmIconWidth means the icon row width only, keeps the last non-empty row when the group
    empties, uses the phantom row basis before any icon existed, and is deferred with the
    container SetSize while in combat (applied on PLAYER_REGEN_ENABLED),
  * width changes are coalesced into one notification per frame and update the attached
    power bar (listener order, chained bar-to-bar notification).
Frame setters are stubs; in-game rendering is checked separately.
"""
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent

STUBS = r'''
SECRET = setmetatable({}, { __lt = function() error("secret compare") end, __le = function() error("secret compare") end })
function issecretvalue(value) return rawequal(value, SECRET) end
function wipe(t) for key in pairs(t) do t[key] = nil end end
clock = 0
function GetTime() return clock end
combat = false
function InCombatLockdown() return combat end
function IsInRaid() return false end
function IsInGroup() return false end
function hooksecurefunc() end
function EnumerateFrames() return nil end
errors = {}
function geterrorhandler() return function(err) errors[#errors + 1] = err end end
timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = fn end,
    NewTimer = function(delay, fn) timers[#timers + 1] = fn; return { Cancel = function() end, IsCancelled = function() return false end } end,
}
function RunTimers()
    local run = 0
    while #timers > 0 and run < 50 do
        local list = timers; timers = {}
        for _, fn in ipairs(list) do fn() end
        run = run + 1
    end
end

Frame = {}
Frame.__index = Frame
frames = {}
function CreateFrame(kind, name, parent)
    local f = setmetatable({ kind = kind, name = name, parent = parent, width = 0, height = 0, shown = true,
        scripts = {}, events = {}, regions = {} }, Frame)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
function Frame:GetName() return self.name end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:SetWidth(w) self.width = w; self.setWidthCalls = (self.setWidthCalls or 0) + 1 end
function Frame:SetHeight(h) self.height = h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:IsShown() return self.shown end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) self.shown = v end
function Frame:SetScript(k, v) self.scripts[k] = v end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:GetChildren() return end
function Frame:GetRegions() return unpack(self.regions) end
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetFrameStrata", "SetFrameLevel",
    "SetIgnoreParentAlpha", "SetParent", "EnableMouse", "SetAlpha", "SetScale", "SetClipsChildren",
    "SetStatusBarColor", "SetMinMaxValues", "SetValue", "SetJustifyH", "SetShadowOffset", "SetTextColor",
    "SetText", "SetFont", "SetDrawLayer", "SetVertexColor", "SetColorTexture", "SetTexture", "SetBlendMode",
    "SetOrientation", "SetReverseFill" }) do
    Frame[name] = Frame[name] or function() end
end
function Frame:GetParent() return self.parent end
function Frame:GetFrameLevel() return 1 end
function Frame:GetObjectType() return self.kind end
function Frame:CreateTexture() local t = CreateFrame("Texture"); self.regions[#self.regions + 1] = t; return t end
function Frame:CreateFontString() return CreateFrame("FontString") end
function Frame:SetStatusBarTexture(t) self.fill = self.fill or CreateFrame("Texture"); self.fill.texture = t end
function Frame:GetStatusBarTexture() return self.fill end
GameFontNormal = CreateFrame("FontString")
UIParent = CreateFrame("Frame", "UIParent")
UIParent.width, UIParent.height = 3440, 1440
addon = { db = { profile = {} } }
function addon:Scale(v) return v end
function addon:ScaleBorder(v) return math.floor((tonumber(v) or 0) + 0.5) end
function upvalue(fn, wanted)
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value end
    end
end
function MakeIcon()
    local icon = CreateFrame("Button")
    icon._ddLayoutVisible = true
    icon.points = 0
    function icon:SetPoint(p, rel, rp, x, y) self.points = 1; self.anchor = { p, rel, rp, x, y } end
    function icon:ClearAllPoints() self.points = 0 end
    function icon:GetNumPoints() return self.points end
    function icon:GetPoint() local a = self.anchor; return a[1], a[2], a[3], a[4], a[5] end
    return icon
end
'''


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    ns = lua.table(Addon=lua.globals().addon)
    lua.execute((ROOT / "DDingUI_CDM/Utils/Toolkit.lua").read_text(encoding="utf-8"), "DDingUI_CDM", ns)
    return lua, ns


def test_resolve_auto_width():
    lua, _ = runtime()
    lua.execute(r'''
        local group = CreateFrame("Frame", "DDingUI_Group_Cooldowns")
        local proxy = CreateFrame("Frame", "DDingUI_Anchor_Cooldowns")
        group.__cdmIconWidth = 930 -- wider than the old 600 cap (user profile: 9 x 42 + spacing at 0.62 UI scale)
        local bar = {}
        local w, resolved = addon:ResolveAutoWidth(proxy, 1, { owner = bar })
        assert(w == 928 and resolved, "old 600 cap still applies: " .. tostring(w))
        w = addon:ResolveAutoWidth(proxy, 3, { owner = bar })
        assert(w == 924, "border compensation must use the bar's own border: " .. tostring(w))

        -- invalid anchor values: fall back to this bar's last good auto width, never to a stored 200
        for _, bad in ipairs({ SECRET, 0/0, 0, -5, 5000 }) do
            group.__cdmIconWidth = bad
            w, resolved = addon:ResolveAutoWidth(proxy, 3, { owner = bar })
            assert(w == 924 and resolved == false, "invalid width not rejected: " .. tostring(bad))
        end
        -- a bar that never resolved uses 200, but does not remember it
        local fresh = {}
        w = addon:ResolveAutoWidth(proxy, 1, { owner = fresh })
        assert(w == 200 and fresh._ddLastAutoWidth == nil, "fallback 200 was remembered")
        group.__cdmIconWidth = 400
        assert(addon:ResolveAutoWidth(proxy, 1, { owner = fresh }) == 398, "recovered anchor stayed at 200")

        -- noStore previews never write the owner
        local preview = { _ddAutoWidthAnchor = "DDingUI_Anchor_Cooldowns", _ddLastAutoWidth = 111 }
        group.__cdmIconWidth = 500
        assert(addon:ResolveAutoWidth(proxy, 1, { owner = preview, noStore = true }) == 498)
        assert(preview._ddLastAutoWidth == 111, "noStore wrote the owner")

        -- anchor change resets the per-bar memory
        local other = CreateFrame("Frame", "SomeOtherFrame")
        other.width = 0
        w = addon:ResolveAutoWidth(other, 1, { owner = bar })
        assert(w == 200, "memory from another anchor leaked: " .. tostring(w))

        -- attached to another DDingUI bar: that bar's frame width, no border compensation
        addon.powerBar = CreateFrame("Frame", "DDingUIPowerBar")
        addon.powerBar.width = 377
        assert(addon:ResolveAutoWidth(addon.powerBar, 1, { owner = {} }) == 377)
        -- UIParent is never an auto width source
        assert(addon:ResolveAutoWidth(UIParent, 1, {}) == 200)
    ''')


def test_notifications_coalesce_in_order():
    lua, _ = runtime()
    lua.execute(r'''
        local log = {}
        addon:RegisterAnchorWidthListener(function() log[#log + 1] = "cast" end, 30)
        addon:RegisterAnchorWidthListener(function() error("boom") end, 20)
        addon:RegisterAnchorWidthListener(function(keys) log[#log + 1] = "power:" .. tostring(keys.Cooldowns) end, 10)
        addon:NotifyAnchorWidthChanged("Cooldowns")
        addon:NotifyAnchorWidthChanged("Cooldowns")
        addon:NotifyAnchorWidthChanged("Buffs")
        assert(#timers == 1, "notifications were not coalesced into one frame")
        RunTimers()
        assert(table.concat(log, ",") == "power:true,cast", "listener order: " .. table.concat(log, ","))
        assert(#errors == 1, "a failing listener must be reported, not silently dropped")
    ''')


def test_icon_row_width_owner_and_combat():
    lua, ns = runtime()
    lua.execute("addon.GroupSystem = { enabled = true }")
    lua.execute((ROOT / "DDingUI_CDM/Modules/GroupSystem/GroupRenderer.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_CDM", ns)
    lua.execute(r'''
        local renderer = addon.GroupRenderer
        local notified = {}
        addon:RegisterAnchorWidthListener(function(keys) for k in pairs(keys) do notified[#notified + 1] = k end end, 1)
        local regen
        for _, f in ipairs(frames) do if f.events.PLAYER_REGEN_ENABLED then regen = f.scripts.OnEvent end end
        assert(regen, "combat-end handler not found")

        local settings = renderer.BuildLayoutSettings({ iconSize = 40, spacing = 2, direction = "CENTERED_HORIZONTAL", rowLimit = 9 })
        local frame = CreateFrame("Frame", "DDingUI_Group_Buffs")
        frame._groupName = "Buffs"
        renderer.groupFrames = { Buffs = frame }
        local function layout(count)
            frame._managedIcons, frame._iconCount = {}, count
            for i = 1, count do frame._managedIcons[i] = MakeIcon() end
            renderer:LayoutGroup(frame, settings, "BuffIconCooldownViewer")
            RunTimers()
        end

        -- never had icons: phantom row basis (9 x 40 + 8 x 2), not the container
        layout(0)
        assert(frame.__cdmIconWidth == 376, "empty group basis: " .. tostring(frame.__cdmIconWidth))
        layout(3)
        assert(frame.__cdmIconWidth == 124, "row width: " .. tostring(frame.__cdmIconWidth))
        assert(frame.width == 376, "container keeps the phantom size (icon row width must not follow it)")
        assert(notified[#notified] == "Buffs", "row width change was not announced")
        -- emptied group keeps the last non-empty row width
        local before = #notified
        layout(0)
        assert(frame.__cdmIconWidth == 124, "empty group dropped the last row width: " .. tostring(frame.__cdmIconWidth))
        assert(#notified == before, "unchanged width must not notify")

        -- combat: row width waits for combat end together with the container size
        combat = true
        layout(5)
        assert(frame.__cdmIconWidth == 124, "row width changed during combat")
        assert(frame._pendingIconRowWidth == 208 and frame._pendingLayoutW, "row width not deferred with SetSize")
        combat = false
        regen()
        RunTimers()
        assert(frame.__cdmIconWidth == 208 and frame._pendingIconRowWidth == nil, "deferred row width not applied")
        assert(notified[#notified] == "Buffs", "combat-end width change was not announced")
    ''')


def test_notification_updates_attached_power_bar():
    lua, ns = runtime()
    lua.execute(r'''
        LibStub = function() return { Fetch = function() return "tex" end } end
        UnitPower = function() return 50 end
        UnitPowerMax = function() return 100 end
        UnitPowerPercent = function() return 0.5 end
        UnitClass = function() return "Mage", "MAGE" end
        GetSpecialization = function() return 1 end
        GetSpecializationRole = function() return "DAMAGER" end
        Enum = { PowerType = { Mana = 0 } }
        addon.CreateTextureBorder = function() end
        addon.UpdateTextureBorderColor = function() end
        addon.UpdateTextureBorderSize = function() end
        addon.ShowTextureBorder = function() end
        addon.GetTexture = function() return "tex" end
        addon.GetFont = function() return "font" end
        addon.ResourceBars = {
            GetPrimaryResource = function() return 0 end,
            GetSecondaryResource = function() return nil end,
            GetResourceColor = function() return { r = 0, g = 0.5, b = 1 } end,
            GetPrimaryResourceValue = function() return 50, 100, 50, 50, "number" end,
            tickedPowerTypes = {},
            IsInGracePeriod = function() return false end,
        }
        proxy = CreateFrame("Frame", "DDingUI_Anchor_Cooldowns")
        group = CreateFrame("Frame", "DDingUI_Group_Cooldowns")
        group.__cdmIconWidth = 930
        function addon:ResolveAnchorFrame(name) return _G[name] end
        addon.db.profile.powerBar = { enabled = true, attachTo = "DDingUI_Anchor_Cooldowns", width = 0, borderSize = 1,
            height = 6, anchorPoint = "TOP", offsetY = 2 }
        addon.db.profile.secondaryPowerBar = { enabled = false }
        addon.db.profile.powerTypeColors = { colors = {} }
        RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    ''')
    lua.execute((ROOT / "DDingUI_CDM/Modules/ResourceBars/PrimaryPowerBar.lua").read_text(encoding="utf-8"),
                "DDingUI_CDM", ns)
    lua.execute(r'''
        local rb = addon.ResourceBars
        -- the real ResourceBars listener calls these two updaters
        addon:RegisterAnchorWidthListener(function() rb:UpdatePowerBar() end, 10)
        local chained = 0
        addon:RegisterAnchorWidthListener(function(keys) if keys.powerBar then chained = chained + 1 end end, 30)
        rb:UpdatePowerBar() -- the real updater must run cleanly in this harness
        local bar = addon.powerBar
        assert(bar, "power bar not created")
        assert(bar.width == 928, "initial auto width (no 600 cap): " .. tostring(bar.width))
        RunTimers()
        -- icon row shrinks out of combat -> one notification -> bar follows, dependent bars hear about it
        group.__cdmIconWidth = 500
        addon:NotifyAnchorWidthChanged("Cooldowns")
        RunTimers()
        assert(bar.width == 498, "bar did not follow the anchor width notification: " .. tostring(bar.width))
        assert(chained >= 1, "bars attached to the power bar were not notified")
        assert(#errors == 0, "power bar update raised: " .. tostring(errors[1]))
    ''')


if __name__ == "__main__":
    test_resolve_auto_width()
    test_notifications_coalesce_in_order()
    test_icon_row_width_owner_and_combat()
    test_notification_updates_attached_power_bar()
    print("CDM auto width: shared resolver, icon row owner, combat deferral, notifications OK")
