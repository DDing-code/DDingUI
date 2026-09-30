"""CDM options previews must use the runtime renderer's own calculations.

Loads the real GroupRenderer / IconSkinning / IconCustomization / ActiveEffectOverlay and the
options preview helpers in Lua 5.1 and checks that, for the same settings:
  * GroupRenderer:LayoutGroup (runtime) and GroupRenderer.ComputeGroupLayout (shared pure layout)
    place every icon at the same centre offset and size,
  * the CDM bar preview grid (GroupSystemOptions AssignedGridBuildLayout) is that runtime layout,
  * texture crop, swipe colours, per-icon overrides and state alpha used by the previews are the
    same function objects the runtime calls (no preview-only copies left behind).
Frame/UI setters are recorded by stubs; real WoW rendering is verified in game separately.
"""
from pathlib import Path
import random

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent

STUBS = r'''
SECRET = {}
function issecretvalue(value) return rawequal(value, SECRET) end
function wipe(t) for key in pairs(t) do t[key] = nil end end
function GetTime() return 100 end
function InCombatLockdown() return false end
function IsInRaid() return false end
function IsInGroup() return false end
function hooksecurefunc() end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
function CreateFrame()
    return {
        RegisterEvent = function() end, UnregisterEvent = function() end,
        SetScript = function() end, Hide = function() end, Show = function() end,
    }
end
addon = { db = { profile = { groupSystem = { groups = {} } } } }
function addon:Scale(v) return v end
function addon:ScaleBorder(v) return math.floor(v + 0.5) end
function upvalue(fn, wanted)
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value end
    end
end
'''

MOCKS = r'''
function MakeIcon()
    local icon = { _ddLayoutVisible = true, shown = true, points = 0 }
    function icon:IsShown() return self.shown end
    function icon:Show() self.shown = true end
    function icon:Hide() self.shown = false end
    function icon:SetAlpha(a) self.alpha = a end
    function icon:SetSize(w, h) self.w, self.h = w, h end
    function icon:ClearAllPoints() self.points = 0 end
    function icon:SetPoint(p, rel, rp, x, y) self.points = 1; self.anchor = { p, rel, rp, x, y } end
    function icon:GetNumPoints() return self.points end
    function icon:GetPoint() local a = self.anchor; return a[1], a[2], a[3], a[4], a[5] end
    return icon
end

function RunRuntime(groupSettings, viewerName, count)
    local renderer = addon.GroupRenderer
    local frame = { _managedIcons = {}, _iconCount = count }
    function frame:GetName() return nil end
    function frame:SetSize(w, h) self.w, self.h = w, h end
    for i = 1, count do frame._managedIcons[i] = MakeIcon() end
    renderer:LayoutGroup(frame, renderer.BuildLayoutSettings(groupSettings), viewerName)
    return frame
end

-- Compare the runtime result with the shared pure layout; returns an error string or nil.
function Compare(groupSettings, viewerName, count)
    local renderer = addon.GroupRenderer
    local frame = RunRuntime(groupSettings, viewerName, count)
    local layout = renderer.ComputeGroupLayout(renderer.BuildLayoutSettings(groupSettings), viewerName, count)
    if frame.w ~= layout.containerWidth or frame.h ~= layout.containerHeight then
        return ("container %sx%s vs %sx%s"):format(tostring(frame.w), tostring(frame.h),
            tostring(layout.containerWidth), tostring(layout.containerHeight))
    end
    local placed = 0
    for i = 1, count do
        local icon = frame._managedIcons[i]
        local slot = layout.slots[i]
        if icon.shown then
            placed = placed + 1
            if not slot then return "runtime placed icon " .. i .. " the layout does not have" end
            if icon._ddTargetX ~= slot.x or icon._ddTargetY ~= slot.y then
                return ("icon %d at %s,%s vs %s,%s"):format(i, tostring(icon._ddTargetX),
                    tostring(icon._ddTargetY), tostring(slot.x), tostring(slot.y))
            end
            if icon._ddTargetWidth ~= slot.w or icon._ddTargetHeight ~= slot.h then
                return ("icon %d size %sx%s vs %sx%s"):format(i, tostring(icon._ddTargetWidth),
                    tostring(icon._ddTargetHeight), tostring(slot.w), tostring(slot.h))
            end
        elseif slot then
            return "layout kept icon " .. i .. " that the runtime hid"
        end
    end
    if placed ~= layout.visibleCount then return "visible count mismatch" end
    return nil
end
'''


def build_cases(seed=12, total=900):
    rng = random.Random(seed)
    directions = ["RIGHT", "LEFT", "CENTERED_HORIZONTAL", "UP", "DOWN", "STATIC", None]
    grows = [None, "UP", "DOWN", "LEFT", "RIGHT"]
    viewers = [None, "BuffIconCooldownViewer", "EssentialCooldownViewer"]
    cases = []
    for _ in range(total):
        settings = {
            "iconSize": rng.choice([None, 24, 32, 33, 37, 44]),
            "spacing": rng.choice([None, 0, 2, 3, 5, -1]),
            "direction": rng.choice(directions),
            "growDirection": rng.choice(grows),
            "rowLimit": rng.choice([None, 0, 1, 3, 4, 6]),
            "aspectRatioCrop": rng.choice([None, 1.0, 1.5, 0.7, 2.0]),
            "overflowMode": rng.choice([None, "wrap", "shrink", "hide"]),
        }
        if rng.random() < 0.25:
            settings["rowIconSizes"] = {1: rng.choice([30, 40]), 2: rng.choice([26, 36])}
        cases.append((settings, rng.choice(viewers), rng.choice([1, 2, 3, 5, 7, 10, 13])))
    return cases


def to_lua(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, item in value.items():
            if item is not None:
                table[key] = to_lua(lua, item)
        return table
    return value


def load_runtime(lua):
    ns = lua.table(Addon=lua.globals().addon)
    for rel in (
        "DDingUI_CDM/Modules/GroupSystem/GroupRenderer.lua",
    ):
        source = (ROOT / rel).read_text(encoding="utf-8-sig")
        lua.execute(source, "DDingUI_CDM", ns)
    lua.execute(MOCKS)


def test_runtime_layout_matches_shared_layout():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    load_runtime(lua)
    compare = lua.globals().Compare
    failures = []
    for settings, viewer, count in build_cases():
        if settings["direction"] == "STATIC":
            continue  # runtime keeps STATIC positions; the preview row is documented as such
        error = compare(to_lua(lua, settings), viewer, count)
        if error:
            failures.append((settings, viewer, count, error))
    assert not failures, "runtime/shared layout mismatch: %r" % (failures[:3],)

    # LayoutGroup and ComputeGroupLayout share the same helper objects.
    lua.execute(r'''
        local renderer = addon.GroupRenderer
        for _, name in ipairs({ "ComputePhantomSize", "ResolveOverflowScale", "CreateRowDimensionResolver",
                                "ComputePhantomShiftY" }) do
            local runtime = upvalue(renderer.LayoutGroup, name)
            assert(runtime and runtime == upvalue(renderer.ComputeGroupLayout, name), name .. " not shared")
        end
    ''')


def load_preview_grid(lua):
    source = (ROOT / "DDingUI_CDM_Option/GroupSystemOptions.lua").read_text(encoding="utf-8")
    segment = source.split("-- Runtime-shaped assigned icon preview.", 1)[1]
    segment = segment.split("local function AssignedGridSetEdges", 1)[0]
    assert "ASSIGNED_DIRECTION_RULES" not in segment, "preview grew its own direction rules again"
    assert "LayoutHorizontal" not in segment and "math.ceil(count" not in segment, \
        "preview grew its own layout math again"
    lua.execute('''
        local DDingUI = addon
        local function GetGS() return addon.db.profile.groupSystem end
        local function CollectCDMRowsForGroup() return {} end
        local function ResolveCDMEntryIconTexture() return 1 end
    ''' + segment + '''
        PreviewLayout = AssignedGridBuildLayout
        PreviewCrop = AssignedGridApplyTexCoord
    ''')


def test_preview_grid_is_runtime_layout():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    load_runtime(lua)
    load_preview_grid(lua)
    lua.execute(r'''
        GroupNames = { [false] = "Custom", EssentialCooldownViewer = "Cooldowns", BuffIconCooldownViewer = "Buffs" }
        function CheckPreview(settings, viewerName, count)
            local groupName = GroupNames[viewerName or false]
            local renderer = addon.GroupRenderer
            local layoutSettings = renderer.BuildLayoutSettings(settings)
            local hide = layoutSettings.overflowMode == "hide"
            if hide then layoutSettings.overflowMode = "wrap" end
            local runtime = renderer.ComputeGroupLayout(layoutSettings, viewerName, count)
            local grid = PreviewLayout(settings, count, groupName)
            if #grid.slots ~= #runtime.slots then return "slot count" end
            for i, slot in ipairs(grid.slots) do
                local r = runtime.slots[i]
                if slot.cx ~= r.x or slot.cy ~= r.y or slot.w ~= r.w or slot.h ~= r.h then
                    return "slot " .. i .. " differs"
                end
                -- top-left box and runtime centre describe the same rectangle
                if math.abs(slot.x + slot.w / 2 + grid.boundsLeft - r.x) > 1e-6
                    or math.abs(grid.boundsBottom + grid.height - slot.y - slot.h / 2 - r.y) > 1e-6 then
                    return "slot " .. i .. " box does not match its centre"
                end
            end
            if hide then
                -- the icons the game keeps sit exactly where the runtime "hide" layout puts them
                local limit = math.floor((tonumber(settings.rowLimit) or 0) + 0.0001)
                if limit > 0 and count > limit then
                    local kept = renderer.ComputeGroupLayout(renderer.BuildLayoutSettings(settings), viewerName, count)
                    for i = 1, limit do
                        if kept.slots[i].x - kept.slots[1].x ~= runtime.slots[i].x - runtime.slots[1].x
                            or kept.slots[i].y - kept.slots[1].y ~= runtime.slots[i].y - runtime.slots[1].y then
                            return "hidden-overflow preview moved a kept icon " .. i
                        end
                        if grid.slots[i].overflowHidden then return "kept icon marked hidden" end
                    end
                    for i = limit + 1, count do
                        if not grid.slots[i].overflowHidden then return "overflow icon not marked" end
                    end
                end
            end
        end
    ''')
    check = lua.globals().CheckPreview
    failures = []
    for settings, viewer, count in build_cases(seed=31, total=500):
        error = check(to_lua(lua, settings), viewer, count)
        if error:
            failures.append((settings, viewer, count, error))
    assert not failures, "preview grid differs from runtime layout: %r" % (failures[:3],)


def test_crop_swipe_and_state_helpers_are_shared():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute(r'''
        addon.CDMCompat = { IsPublicValue = function(_, v) return not issecretvalue(v) end }
        addon.IconViewers = { _iconData = {}, _cdData = {}, _texData = {} }
        addon.GetFont = function() return nil end
        LibStub = setmetatable({}, { __call = function() return nil end })
        UnitClass = function() return "Mage", "MAGE" end
        RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    lua.execute((ROOT / "DDingUI_CDM/Modules/IconViewers/IconSkinning.lua").read_text(encoding="utf-8"),
                "DDingUI_CDM", ns)
    lua.execute((ROOT / "DDingUI_CDM/Modules/CustomIcons/ActiveEffectOverlay.lua").read_text(encoding="utf-8"),
                "DDingUI_CDM", ns)
    load_runtime(lua)
    load_preview_grid(lua)
    lua.execute(r'''
        local viewers = addon.IconViewers
        -- SkinIcon and the preview crop call the same pure function.
        local skinCrop = upvalue(viewers.SkinIcon, "ComputeSkinTexCoord")
        assert(skinCrop and skinCrop == upvalue(viewers.ComputeIconTexCoord, "ComputeSkinTexCoord"),
            "SkinIcon crop is not shared with the preview")
        assert(upvalue(viewers.SkinIcon, "ResolveSkinAspectRatio")
            == upvalue(viewers.ComputeIconTexCoord, "ResolveSkinAspectRatio"))

        local function Texture()
            local t = {}
            function t:SetTexCoord(l, r, top, b) self.c = { l, r, top, b } end
            return t
        end
        -- Preview crop of a CDM icon equals SkinIcon's crop (zoom default 0, "16:9" string honoured).
        for _, s in ipairs({ {}, { zoom = 0.08 }, { aspectRatioCrop = 2 }, { aspectRatio = "16:9", zoom = 0.1 },
                             { aspectRatioCrop = 0.6, zoom = 0.2 } }) do
            local tex = Texture()
            PreviewCrop(tex, s, "cdm")
            local l, r, t, b = skinCrop(upvalue(viewers.ComputeIconTexCoord, "ResolveSkinAspectRatio")(s), s.zoom or 0)
            assert(tex.c[1] == l and tex.c[2] == r and tex.c[3] == t and tex.c[4] == b, "cdm crop differs")
        end
        -- Dynamic icons go through DynamicIconBridge.ApplyTexCoordCrop with the runtime defaults.
        local seen
        addon.DynamicIconBridge = { ApplyTexCoordCrop = function(tex, zoom, aspect) seen = { tex, zoom, aspect } end }
        local tex = Texture()
        PreviewCrop(tex, {}, "dynamic")
        assert(seen and seen[1] == tex and seen[2] == 0.08 and seen[3] == 1.0, "dynamic crop defaults differ")

        -- Swipe colours: SkinIcon/Reconcile use the exported resolvers.
        assert(upvalue(viewers.SkinIcon, "ResolveCooldownSwipeColor") == viewers.ResolveCooldownSwipeColor)
        local r, g, b, a = viewers.ResolveCooldownSwipeColor({})
        assert(r == 0 and g == 0 and b == 0 and a == 0.8)
        r, g, b, a = viewers.ResolveAuraSwipeColor({})
        assert(r == 1 and g == 1 and b == 0.5 and a == 0.8)

        -- Active effect swipe (custom icons): runtime resolver is exported, gold 0.7 default.
        local overlay = addon.CustomIconActiveEffectOverlay
        r, g, b, a = overlay.ResolveSwipeColor({})
        assert(r == 1 and a == 0.7)
        assert(overlay.ResolveSwipeColor({ activeSwipeMode = "hidden" }) == nil)
    ''')


def test_icon_customization_state_helpers_are_shared():
    source = (ROOT / "DDingUI_CDM/Modules/IconCustomization/IconCustomization.lua").read_text(encoding="utf-8")
    # The runtime state path calls the exported pure helpers (no second copy of the rules).
    assert "local visualAlpha = ResolveCooldownStateAlpha(custom, onCooldown)" in source
    assert "return ApplySkinOverrides(settings, ResolveIconCustomization(icon))" in source
    assert "and ResolveActiveBorderColor(custom)" in source
    helpers = source.split("local function ResolveCooldownStateAlpha(custom, onCooldown)", 1)[1]
    helpers = "local function ResolveCooldownStateAlpha(custom, onCooldown)" + helpers.split("IconCustomization.ResolveCooldownStateAlpha", 1)[0]
    lua = LuaRuntime(unpack_returned_tuples=True)
    alpha = lua.execute(helpers + "\nreturn ResolveCooldownStateAlpha")
    assert alpha(lua.table(cooldownStateEffect="lowerAlphaOnCD"), True) == 0.5
    assert alpha(lua.table(cooldownStateEffect="lowerAlphaOnCD", cooldownStateAlpha=0.3), True) == 0.3
    assert alpha(lua.table(cooldownStateEffect="hiddenOnCD"), True) == 0
    assert alpha(lua.table(cooldownStateEffect="hiddenReady"), False) == 0
    assert alpha(None, True) == 1

    studio = (ROOT / "DDingUI_CDM_Option/GroupStateStudio.lua").read_text(encoding="utf-8")
    for call in ("ResolveCooldownStateAlpha", "ApplySkinOverrides", "ResolveActiveBorderColor",
                 "UpdateDynamicIconGlow", "ApplyDynamicIconTextOptions", "ComputeGroupLayout",
                 "ComputeIconTexCoord", "ResolveCooldownSwipeColor", "ResolveAuraSwipeColor"):
        assert call in studio, "state preview no longer uses runtime " + call
    for stale in ('SetText("8.4")', "0.35, 0.02, 0.02", "SetSwipeColor(0, 0, 0, 0.72)"):
        assert stale not in studio, "preview-only drawing came back: " + stale


def test_section_and_aura_previews_copy_runtime_frames():
    section = (ROOT / "DDingUI_CDM_Option/SectionWorkspace.lua").read_text(encoding="utf-8")
    for stale in ('"시전 미리보기"', 'SetText("74%")', 'SetText("3 / 5")', "SetTexture(136243)"):
        assert stale not in section, "section preview draws its own fake bar again: " + stale
    assert "DashboardPreview.Paint(node.visual, node.descriptor.sources" in section
    assert "DDingUI:ShowTestCastBar()" in section
    aura = (ROOT / "DDingUI_CDM_Option/BuffTrackerLivePreview.lua").read_text(encoding="utf-8")
    assert "reader.PaintFit(self.host, sources" in aura
    for stale in ("local function RenderBar", "local function RenderRing", '"8.3"', "GetTime() - 9.6"):
        assert stale not in aura, "custom aura preview draws its own copy again: " + stale


SMOKE = r"""
-- options-side environment on top of the dashboard harness frames
L = {}
function LibStub(name) if name == "AceLocale-3.0" then return { GetLocale = function() return L end } end end
function hooksecurefunc() end
UIParent.scale = 1
local F = getmetatable(UIParent).__index
for _, m in ipairs({ "RegisterForClicks", "SetSwipeTexture" }) do F[m] = F[m] or function() end end
addon.GUIBase.RADIUS = { card = 10, control = 6, row = 8 }
addon.GUIBase.RoundFrame = function(f) f.rounded = true end
addon.GUI.THEME = addon.GUIBase.THEME
function addon:GetGlobalFont() return "font.ttf" end
function addon:GetFont() return "font.ttf" end
function addon:ScaleBorder(v) return v end
addon.GroupRenderer = { BuildLayoutSettings = shared.GroupRenderer.BuildLayoutSettings,
    ComputeGroupLayout = shared.GroupRenderer.ComputeGroupLayout }
calls = {}
function addon.GroupRenderer:ApplyDynamicIconTextOptions(icon, groupName) calls.text = (calls.text or 0) + 1 end
addon.IconViewers = {
    ComputeIconTexCoord = function() return 0.1, 0.9, 0.2, 0.8 end,
    ResolveCooldownSwipeColor = function() return 0.01, 0.02, 0.03, 0.8 end,
    ResolveAuraSwipeColor = function() return 1, 1, 0.5, 0.8 end,
}
addon.IconCustomization = {
    ApplySkinOverrides = function(settings, custom) return settings end,
    ResolveCooldownStateAlpha = function(custom, onCooldown) return onCooldown and 0.5 or 1 end,
    ResolveActiveBorderColor = function() return { 0.9, 0.8, 0.1, 1 } end,
}
function addon.IconCustomization:UpdateDynamicIconGlow(frame, settings, show)
    calls.glow = { frame = frame, settings = settings, show = show }
end
function addon.IconCustomization:ClearDynamicIconGlow(frame) calls.cleared = frame end
addon.db.profile = { groupSystem = { groups = { Cooldowns = { iconSize = 40, aspectRatioCrop = 2, borderSize = 2,
    borderColor = { 0.3, 0.3, 0.3, 1 } } } },
    iconCustomization = { spells = { ["123_Essential"] = { cooldownStateEffect = "lowerAlphaOnCD",
        activeBorderEnabled = true, activeGlow = true, glowType = "pixel", glowColorMode = "custom" } } } }
selection = { _gridKind = "cdm", _gridSpellID = 123, _gridViewerType = "Essential", _gridIconTex = 777 }
function addon:GetGroupIconDetailSelection() return selection end
function addon:GetGroupIconDetailKey() return "cdm:123" end
function addon:SoftRefreshGroupSystemOptions() end
"""

SMOKE_CHECKS = r"""
-- State studio: runtime size (40x20 at aspect 2), runtime crop, border, swipe, alpha, glow and text.
local parent = CreateFrame("Frame", nil, UIParent); parent:SetSize(760, 400)
addon:BuildGroupStateStudioUI(parent, "Cooldowns")
local cards = parent.children
assert(#cards == 6, "six state cards")
local function IconOf(card) return card.children[1].children[1] end
local active = IconOf(cards[3])
assert(active.width == 40 and active.height == 20, "state icon is not the runtime icon size")
assert(active.icon.texCoord[1] == 0.1 and active.icon.texCoord[4] == 0.8, "state icon is not the runtime crop")
assert(calls.glow and calls.glow.frame == active and calls.glow.show == true, "runtime glow not used")
assert(calls.glow.settings.glowType == "pixel" and calls.glow.settings.activeGlow == true)
assert(calls.text and calls.text >= 1, "runtime text styling not used")
local cooldown = IconOf(cards[2])
assert(cooldown.alpha == 0.5, "cooldown alpha does not follow ResolveCooldownStateAlpha")
local swipe
for _, child in ipairs(cooldown.children) do if child.kind == "Cooldown" then swipe = child end end
assert(swipe and swipe.swipeColor[1] == 0.01 and swipe.duration == 10, "cooldown swipe is not the runtime colour")
local unusable = IconOf(cards[6])
for _, region in ipairs(unusable.regions) do
    assert(not (region.vertexColor and region.vertexColor[1] == 0.35 and region.vertexColor[2] == 0.02),
        "invented red unusable tint is back")
end
assert(cards[1].rounded, "state card is not a StyleLib rounded card")
addon:BuildGroupStateStudioUI(CreateFrame("Frame", nil, UIParent), "Cooldowns")
assert(calls.cleared == active, "old preview glow was not released")

-- Custom aura card: copies the runtime tracker frame at its real size.
local tracker = runtime({ 500, 500, 120, 16 }, 4242)
local configs = { { uid = "a", name = "Aura", displayType = "bar" } }
function addon:GetTrackedBuffConfigs() return configs end
function addon:GetTrackedBuffBars() return { tracker } end
function addon:IsBuffTrackerPreviewEnabled() return false end
local card = addon.GUI.CreateTrackerLivePreview(UIParent)
card.host.allPoints = nil; card.host:SetSize(400, 88)
card:Refresh(configs[1], configs)
assert(card.rounded, "aura preview card is not rounded")
local copied = card.host._previewPool and card.host._previewPool.Texture and card.host._previewPool.Texture[1]
assert(copied and copied.shown and copied.visual.texture == 4242, "aura preview did not copy the runtime frame")
near(copied.width, 120)
assert(not card.hint.shown)
tracker.shown = false
card:Refresh(configs[1], configs)
assert(card.hint.shown and card.toggle.shown, "hidden tracker must offer the runtime preview mode")
"""


def test_state_studio_and_aura_card_use_runtime():
    import test_dashboard_workspace as dash
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(dash.STUBS)
    shared = lua.eval("{db=addon.db}")
    lua.execute("realCreateFrame=CreateFrame; CreateFrame=function(...) local f=realCreateFrame(...);"
                " f.RegisterEvent=f.RegisterEvent or function() end; return f end")
    lua.execute((ROOT / "DDingUI_CDM/Modules/GroupSystem/GroupRenderer.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_CDM", lua.table(Addon=shared))
    lua.execute("CreateFrame=realCreateFrame")
    lua.globals().shared = shared
    lua.execute(SMOKE)
    ns = lua.table(Addon=lua.globals().addon)
    for name in ("DashboardPreview.lua", "BuffTrackerLivePreview.lua", "GroupStateStudio.lua"):
        lua.execute((ROOT / "DDingUI_CDM_Option" / name).read_text(encoding="utf-8"), "DDingUI_CDM_Option", ns)
    lua.execute(SMOKE_CHECKS)


if __name__ == "__main__":
    test_runtime_layout_matches_shared_layout()
    test_preview_grid_is_runtime_layout()
    test_crop_swipe_and_state_helpers_are_shared()
    test_icon_customization_state_helpers_are_shared()
    test_section_and_aura_previews_copy_runtime_frames()
    test_state_studio_and_aura_card_use_runtime()
    print("CDM preview/runtime parity: OK")
