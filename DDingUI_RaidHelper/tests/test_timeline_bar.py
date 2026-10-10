"""C안 combat bar (2026-10-10): borderless bar, both edges fade, background opacity only.

Runs the shipped Core.lua, Data/Registry.lua, Data/Demo.lua, UI/Timeline.lua and the
embedded StyleLib in Lua 5.1 on the shared frame-geometry mock, then renders the demo
encounter at 0:42.2 (P1, 암흑 붕괴 in 3.8 s, 오라 숙련 in 2.3 s).
In-game drawing (mask sampling, gradients, line masking) remains an in-game check.
"""
import re

from lupa.lua51 import LuaRuntime

from test_raidhelper_edit_mode import ADDON_ROOT, EXTRA, MOCK, STYLE_FILES

BAR_EXTRA = r'''
function methods:SetVertexColor(...) self.vertex = {...} end
function methods:CreateMaskTexture() return CreateFrame('MaskTexture', nil, self) end
function methods:AddMaskTexture(mask) self.masks = (self.masks or 0) + 1; self.mask = mask end
function methods:IsPlaying() return false end
for _, key in ipairs({ "SetTextureSliceMargins", "SetTextureSliceMode", "SetSmoothing" }) do
    if not methods[key] then methods[key] = function() end end
end
'''

SCENARIO = r'''
local ns = ...
local function Noop() end
local clock = 42.2

-- Saved height from the old four-row window must come back as the C안 default.
DDingUI_RaidHelperDB = { timelineHeight = 260, backgroundAlpha = 0.5 }

ns.Engine = {
    running = false, options = {},
    Initialize = Noop,
    IsRunning = function(self) return self.running end,
    StartModel = function(self, model, options)
        self.model, self.options, self.running = model, options, true
        ns.TimelineUI:OnEngineEvent("START", model)
        return true
    end,
    StopEncounter = function(self, success)
        self.running = false
        self.options = {}
        ns.TimelineUI:OnEngineEvent("STOP", success == true, self.model)
    end,
    StartEncounter = Noop,
    GetModel = function(self) return self.model end,
    GetTimelineTime = function() return clock end,
    GetPhaseAt = function(self, t)
        local current = self.model.phases[1]
        for _, phase in ipairs(self.model.phases) do
            if phase.t <= t then current = phase else break end
        end
        return current
    end,
    Tick = Noop,
    GetCooldowns = function(self) return self.model and self.model.cooldowns or {} end,
    GetLiveMechanics = function() return {} end,
}
ns.Options = {
    Initialize = Noop, ApplyPendingSettings = Noop, RefreshPreviewButton = Noop,
    ShouldShowTooltips = function() return false end,
    Open = Noop, Close = Noop,
}
for _, key in ipairs({ "HealerProfileUI", "MinimapButton", "BigWigsSync", "Commands" }) do
    ns[key] = { Initialize = Noop }
end

ns.eventFrame:Fire("OnEvent", "ADDON_LOADED", "DDingUI_RaidHelper")
assert(ns.db.timelineHeight == 98, "legacy height must reset to the C안 default")

local UI = ns.TimelineUI
local frame = UI.frame
local plot = UI.plot
assert(frame.width == 680 and frame.height == 98 and plot.height == 70)
assert(frame.cooldownLayer.height == 28)
assert(not frame.header and not frame.title, "the title bar is gone")

-- Live combat: no outline, transparent window surface.
local model = ns.Registry:GetByKey("demo")
ns.Engine.model, ns.Engine.running, ns.Engine.options = model, true, {}
UI:OnEngineEvent("START", model)
assert(frame.shown and frame.border[4] == 0 and frame.background[4] == 0) -- backdrop: no surface, no edge

-- Every texture inside the bar shares the fade mask; the playhead does not.
assert(UI.fadeMask and UI.fadeMask.texture:find("RaidHelper_FadeMask.tga", 1, true))
assert(frame.barBackground.masks == 1 and frame.pastShade.masks == 1)
assert(not frame.playhead.masks and not frame.playheadGlow.masks)
local columns, lines = 0, 0
for _, column in ipairs(UI.damageColumns) do
    assert(column.masks == 1)
    if column.shown then columns = columns + 1 end
end
for _, line in ipairs(UI.damageLines) do
    assert(line.masks == 1)
    if line.shown then lines = lines + 1 end
end
assert(columns > 60 and lines > 60, "ridge fill and ridge line are drawn")
assert(not UI.lineMaskFailed)
for _, grid in ipairs(UI.gridLines) do assert(grid.line.masks == 1) end
for _, phase in ipairs(UI.phaseMarkers) do assert(phase.ribbon.masks == 1 and phase.line.masks == 1) end

-- Background opacity: bar surface 0.8 * 0.5, past shade 0.35 * 0.5. Ridge untouched.
assert(math.abs(frame.barBackground.vertex[4] - 0.4) < 1e-6)
assert(math.abs(frame.pastShade.color[4] - 0.175) < 1e-6)
local tallest
for _, column in ipairs(UI.damageColumns) do
    if column.shown and (not tallest or column.height > tallest.height) then tallest = column end
end
assert(tallest.gradient and tallest.gradient[3][4] > 0.5, "ridge keeps its own opacity")
assert(tallest.height <= plot.height - 36 + 0.001, "ridge stays below the icon row")

-- Ribbon: the active phase (P1) uses the accent, the next one the warning colour.
local activeRibbons, otherRibbons = 0, 0
for _, phase in ipairs(UI.phaseMarkers) do
    if phase.ribbon.shown then
        if phase.active then activeRibbons = activeRibbons + 1 else otherRibbons = otherRibbons + 1 end
    end
end
assert(activeRibbons == 1 and otherRibbons >= 1)

-- Time readout above the left fade edge.
assert(frame.timeReadout.text == "0:42 · P1", frame.timeReadout.text)
assert(frame.timeReadout.shown and frame.timeReadout.points.BOTTOMLEFT[3] == 82)
assert(not frame.syncText.shown, "no status line during combat")

-- Mechanics: nearest (암흑 붕괴, 3.8 s) is 32 px with the halo and the detail chip.
local nearest, faded, past
for _, marker in ipairs(UI.mechanicMarkers) do
    if marker.shown then
        if marker.data.t == 46 then nearest = marker end
        if marker.data.t == 78 then faded = marker end
        if marker.data.t == 28 then past = marker end
        if marker ~= nearest then assert(marker.width == 28) end
    end
end
assert(nearest and nearest.width == 32 and nearest.glow.shown)
assert(nearest.border[1] == UI.accentLight[1])
local chip = frame.mechanicChip
assert(chip.shown ~= nearest.countdown.shown, "details or icon countdown must be visible")
assert(chip.number.text == "3.8" and chip.name.text == "암흑 붕괴")
assert(chip.info.text:find("52.0M", 1, true) and chip.info.text:find("20명 피격", 1, true))
assert(chip.info.text:find("P2 구간", 1, true))
if chip.shown then
    assert(chip.points.TOPLEFT and math.abs(chip.points.TOPLEFT[3] - (nearest.x + 20)) < 1e-6)
end
-- 78 s sits inside the right fade: partly transparent, still counting.
assert(faded and faded.alpha > 0 and faded.alpha < 1 and faded.countdown.text == "36")
-- Past mechanics are dimmed; anything left of the bar is hidden, not clamped.
assert(not past or past.alpha <= 0.38 + 1e-6)
for _, marker in ipairs(UI.mechanicMarkers) do
    if marker.shown then assert(marker.x > 0 and marker.x < plot:GetWidth()) end
end

-- Cooldown rail: pin + 18 px icon; nearest (오라 숙련, 2.3 s) gets the rail chip.
local cooldownChip = frame.cooldownChip
assert(cooldownChip.shown and cooldownChip.text.text:find("오라 숙련", 1, true))
assert(cooldownChip.text.text:find("2.3s", 1, true))
for _, marker in ipairs(UI.cooldownMarkers) do
    if marker.shown then assert(marker.width == 18 and marker.pin and not marker.countdown) end
end

-- Near the right end the chip flips to the left of the icon. With a 40 s / 10 s window,
-- 파멸의 메아리 (78 s) at 75.5 is 2.5 s ahead at x = 680 of 800 (fade starts at 704).
ns.db.timelineWidth = 800
UI:ApplyDisplaySettings()
ns.db.windowPast, ns.db.windowFuture = 40, 10
clock = 75.5
UI:UpdateView()
assert(chip.shown and chip.name.text == "파멸의 메아리")
assert(chip.points.TOPRIGHT and not chip.points.TOPLEFT)
ns.db.windowPast, ns.db.windowFuture = 12, 38
ns.db.timelineWidth = 680
UI:ApplyDisplaySettings()

-- 0% background: surface and shade vanish, ridge/icons stay.
ns.db.backgroundAlpha = 0
UI:ApplyDisplaySettings()
UI:UpdateView()
assert(frame.barBackground.vertex[4] == 0 and frame.pastShade.color[4] == 0)
assert(tallest.shown)
for _, marker in ipairs(UI.mechanicMarkers) do
    if marker.shown then assert(marker.alpha > 0, "background opacity must not hide icons") end
end

-- Narrow bar: no chips, no readout; the nearest icon shows its own countdown.
ns.db.timelineWidth = 300
UI:ApplyDisplaySettings()
clock = 42.2
UI:UpdateView()
assert(UI.compact and not chip.shown and not cooldownChip.shown and not frame.timeReadout.shown)
for _, marker in ipairs(UI.mechanicMarkers) do
    if marker.shown and marker.data.t == 46 then assert(marker.countdown.shown) end
end
ns.db.timelineWidth = 680
UI:ApplyDisplaySettings()

-- Phase labels must not cover mechanic icons or the nearest mechanic's details.
local sawPhaseLabel = false
for _, width in ipairs({ 200, 300, 400, 680, 1200 }) do
    ns.db.timelineWidth = width
    UI:ApplyDisplaySettings()
    for _, moment in ipairs({ 42.2, 43.9, 44.1, 75.5, 90.6 }) do
        clock = moment
        UI:UpdateView()
        for _, entry in ipairs({
            { chip, UI.mechanicMarkers }, { cooldownChip, UI.cooldownMarkers },
        }) do
            local detail, markers = entry[1], entry[2]
            if detail:IsShown() then
                local left = detail:GetLeft()
                local right = left + detail:GetWidth()
                for _, marker in ipairs(markers) do
                    if marker:IsShown() then
                        local iconLeft = marker:GetLeft()
                        assert(right <= iconLeft or left >= iconLeft + marker:GetWidth(),
                            "detail chip covers an icon at width " .. width)
                    end
                end
            end
        end
        if not chip:IsShown() then
            for _, marker in ipairs(UI.mechanicMarkers) do
                if marker:IsShown() and marker.nearState then
                    assert(marker.countdown:IsShown(), "hidden detail must keep the countdown visible")
                end
            end
        end
        for _, phase in ipairs(UI.phaseMarkers) do
            if phase.chip:IsShown() then
                sawPhaseLabel = true
                local left = phase.chip:GetLeft()
                local right = left + phase.chip:GetWidth()
                for _, marker in ipairs(UI.mechanicMarkers) do
                    if marker:IsShown() then
                        local iconLeft = marker:GetLeft()
                        assert(right <= iconLeft or left >= iconLeft + marker:GetWidth(),
                            "phase label covers a mechanic icon at width " .. width)
                    end
                end
                if chip:IsShown() then
                    local detailLeft = chip:GetLeft()
                    assert(right <= detailLeft or left >= detailLeft + chip:GetWidth(),
                        "phase label covers mechanic details at width " .. width)
                end
            end
        end
    end
end
assert(sawPhaseLabel, "unobstructed phase labels must remain visible")
ns.db.timelineWidth = 680
UI:ApplyDisplaySettings()
clock = 42.2
UI:UpdateView()

-- End of fight: end text, then the bar fades out and hides after 3 s.
ns.Engine.running = false
UI:OnEngineEvent("STOP", true, model)
assert(frame.endText.text == "전투 종료 · 처치" and frame.endText.shown)
assert(frame._slFadeOut, "fade-out started after the 3 s timer")
frame._slFadeOut:Fire("OnFinished")
assert(not frame.shown and frame:GetAlpha() == 1)

-- A new pull cancels a pending fade-out and fades back in.
ns.Engine.running = true
UI:OnEngineEvent("START", model)
assert(frame.shown and not frame.endText.shown)

-- Only editing shows the accent outline and positioning hint.
ns.Engine.running = false
assert(UI:SetEditMode(true))
assert(frame.border[4] == 1 and frame.border[1] == UI.accentFrom[1])
UI:UpdateView()
assert(frame.syncText.shown and frame.syncText.text:find("편집 중", 1, true))
assert(UI:SetEditMode(false))
assert(frame.border[4] == 0)
'''


def run(extra=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * 0.65
    lua.execute(MOCK.read_text(encoding="utf-8"))
    lua.execute(EXTRA)
    lua.execute(BAR_EXTRA)
    for relative in STYLE_FILES + (r"Libs\DDingUI_StyleLib\Animation.lua",):
        source = (ADDON_ROOT / relative.replace("\\", "/")).read_text(encoding="utf-8-sig")
        lua.execute("local source = ...; assert(loadstring(source))('DDingUI_RaidHelper')", source)
    ns = lua.table()
    for relative in ("Data/Registry.lua", "Data/Demo.lua", "UI/Timeline.lua", "Core.lua"):
        source = (ADDON_ROOT / relative).read_text(encoding="utf-8-sig")
        lua.execute("local source, ns = ...; assert(loadstring(source))('DDingUI_RaidHelper', ns)", source, ns)
    lua.execute(SCENARIO, ns)
    if extra:
        lua.execute(extra, ns)


def test_combat_bar_renders_the_c_layout():
    run()


def test_only_selected_mechanics_are_drawn_when_bigwigs_adds_bars():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
local major = { t = 46, label = "주요 기믹", icon = 12345 }
local later = { t = 64, label = "다음 주요 기믹", icon = 12346 }
local anchor = { t = 43, label = "동기화 전용", syncOnly = true }
local live = {
    major = { t = 46, matched = major },
    anchor = { t = 43, matched = anchor },
    unknown = { t = 44, label = "미선정 BigWigs 바" },
}
ns.Engine.GetLiveMechanics = function() return live end
UI:UpdateMechanics({ mechanics = { major, later } }, 42.2, 680)
local visible = 0
for _, marker in ipairs(UI.mechanicMarkers) do
    if marker:IsShown() then
        visible = visible + 1
        assert(marker.data == major or marker.data == later, "unselected bars must stay hidden")
        if marker.data == major then assert(marker.nearState, "hidden bars must not steal the detail chip") end
    end
end
assert(visible == 2, "selected mechanics must be shown once each")
assert(live.anchor.matched == anchor and live.unknown, "bar tracking stays available for synchronization")
UI:UpdateMechanics({ mechanics = {} }, 42.2, 680)
for _, marker in ipairs(UI.mechanicMarkers) do assert(not marker:IsShown()) end
''')


def test_wcl_ascendance_icons_use_numeric_file_ids_on_the_rail_and_reminder():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
local marker = UI:GetMarker(UI.cooldownMarkers, 1, UI.cooldownLayer, "cooldown")
local row = UI:CreateUpcomingRow(1)
for _, spell in ipairs({ {114050, 8026697}, {114051, 8026696}, {114052, 8026698} }) do
    local data = { t = 46, spellID = spell[1], icon = "Interface\\Icons\\" .. spell[2] .. ".jpg" }
    assert(UI:ConfigureMarker(marker, data, 42.2, 680, "cooldown"))
    assert(marker.icon.texture == spell[2], "WCL's numeric jpg name is a FileDataID, not an icon path")
    UI:FillUpcomingRow(row, data, 3.8, 100, UI:GetAlertStyle())
    assert(row.icon.texture == spell[2], "reminder must use the same new Ascendance icon")
end
''')


if __name__ == "__main__":
    run()
    print("PASS: RaidHelper C안 combat bar")
