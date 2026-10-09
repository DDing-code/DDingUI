"""'곧 사용' alert layout options (2026-10-10): sizes, alignment, growth, rows, width, lead time,
element toggles and the settings sample, applied by the shipped Timeline.lua on the frame mock.
Pixel output and fonts in the real client remain in-game checks.
"""
import re

from lupa.lua51 import LuaRuntime

from test_raidhelper_edit_mode import ADDON_ROOT, EXTRA, MOCK, STYLE_FILES
from test_timeline_bar import BAR_EXTRA

STYLE_EXTRA = r'''
function methods:SetTextScale(value) self.textScale = value end
'''

SCENARIO = r'''
local ns = ...
local function Noop() end
local clock = 37.0
DDingUI_RaidHelperDB = { backgroundAlpha = 1 }

ns.Engine = {
    running = false, options = {}, Initialize = Noop,
    IsRunning = function(self) return self.running end,
    StartModel = function(self, model, options) self.model, self.options, self.running = model, options, true; return true end,
    StopEncounter = function(self) self.running = false end,
    StartEncounter = Noop,
    GetModel = function(self) return self.model end,
    GetTimelineTime = function() return clock end,
    GetPhaseAt = function(self, t)
        local current = self.model.phases[1]
        for _, phase in ipairs(self.model.phases) do if phase.t <= t then current = phase else break end end
        return current
    end,
    Tick = Noop,
    GetCooldowns = function(self) return self.model and self.model.cooldowns or {} end,
    GetLiveMechanics = function() return {} end,
}
ns.Options = {
    Initialize = Noop, ApplyPendingSettings = Noop, RefreshPreviewButton = Noop,
    ShouldShowTooltips = function() return false end, Open = Noop, Close = Noop,
}
for _, key in ipairs({ "HealerProfileUI", "MinimapButton", "BigWigsSync", "Commands" }) do
    ns[key] = { Initialize = Noop }
end
ns.eventFrame:Fire("OnEvent", "ADDON_LOADED", "DDingUI_RaidHelper")
assert(type(ns.db.alertStyle) == "table" and next(ns.db.alertStyle) == nil, "empty saved style = defaults")

local UI = ns.TimelineUI
local panel = UI.upcomingPanel
local model = ns.Registry:GetByKey("demo")
ns.Engine.model, ns.Engine.running = model, true
UI:OnEngineEvent("START", model)
local function At(seconds) clock = seconds; UI:UpdateView() end
local function Shown(pool)
    local count = 0
    for _, row in ipairs(pool) do if row.shown then count = count + 1 end end
    return count
end

-- Defaults reproduce the previous fixed alert: 320 wide, three 30 px lines, 2 px apart.
local style = UI:GetAlertStyle()
assert(style.iconSize == 26 and style.nameSize == 14 and style.countSize == 20)
assert(style.align == "LEFT" and style.grow == "DOWN" and style.maxRows == 3 and style.window == 12)
assert(panel.width == 320 and panel.height == 94)
At(37.0)
local row = UI.upcomingRows[1]
assert(row.height == 30 and row.icon.width == 26 and row.label.fontSize == 14 and row.countdown.fontSize == 20)
assert(row.points.TOPLEFT[1] == panel and row.content.points.LEFT[1] == row)

-- Bigger, right-aligned, growing upward, two lines, wider, 20 s lead time.
ns.db.alertStyle = { iconSize = 40, nameSize = 18, countSize = 28, spacing = 6, maxRows = 2,
    width = 400, align = "RIGHT", grow = "UP", window = 20 }
UI:ApplyAlertStyle()
local height = 44 -- max(40, ceil(18*1.25)=23, ceil(28*1.25)=35) + 4
assert(UI.AlertRowHeight(UI:GetAlertStyle()) == height)
assert(panel.width == 400 and panel.height == 2 * height + 6)
At(41.6) -- 오라 숙련 2.9 s and 재활 18.9 s are both inside the 20 s lead time
assert(Shown(UI.upcomingRows) == 2)
local first, second = UI.upcomingRows[1], UI.upcomingRows[2]
assert(first.points.BOTTOMLEFT[1] == panel and first.points.BOTTOMLEFT[4] == 0, "nearest sits at the bottom")
assert(second.points.BOTTOMLEFT[4] == height + 6, "later ones stack upward")
assert(first.content.points.RIGHT[1] == first, "line group hugs the right edge")
assert(first.icon.points.RIGHT and first.label.points.RIGHT[1] == first.icon and first.label.points.RIGHT[2] == "LEFT")
assert(first.countdown.points.RIGHT[1] == first.label and first.countdown.points.RIGHT[3] == -8)
assert(first.icon.width == 40 and first.label.fontSize == 18 and first.countdown.fontSize == 28)
assert(first.shade.gradient[2][4] == 0 and math.abs(first.shade2.gradient[3][4] - 0.8) < 1e-6, "shade fades leftward")

-- One line only.
ns.db.alertStyle.maxRows = 1
UI:ApplyAlertStyle()
At(41.6)
assert(Shown(UI.upcomingRows) == 1 and panel.height == height)

-- Centred, no name: the number follows the icon; shade fades out on both sides.
ns.db.alertStyle = { align = "CENTER", showName = false }
UI:ApplyAlertStyle()
At(41.6)
row = UI.upcomingRows[1]
assert(row.content.points.CENTER[1] == row and not row.label.shown)
assert(row.countdown.points.LEFT[1] == row.icon and row.countdown.points.LEFT[2] == "RIGHT")
assert(row.shade.gradient[2][4] == 0 and math.abs(row.shade.gradient[3][4] - 0.8) < 1e-6)
assert(math.abs(row.shade2.gradient[2][4] - 0.8) < 1e-6 and row.shade2.gradient[3][4] == 0)

-- Number only.
ns.db.alertStyle = { showName = false, showIcon = false }
UI:ApplyAlertStyle()
At(41.6)
row = UI.upcomingRows[1]
assert(not row.icon.shown and row.countdown.points.LEFT[1] == row.content)

-- Highlight off: crossing into the last seconds does not pop the number.
ns.db.alertStyle = { pop = false }
UI:ApplyAlertStyle()
At(40.0); At(41.6)
row = UI.upcomingRows[1]
assert(row.countdown.text == "3" and (row.countdown.textScale or 1) == 1)
ns.db.alertStyle = {}
UI:ApplyAlertStyle()
At(40.0); At(41.6)
assert(UI.upcomingRows[1].countdown.textScale > 1.3, "highlight on by default")

-- Broken saved values fall back or clamp.
ns.db.alertStyle = { iconSize = 999, countSize = "x", align = "DIAGONAL", grow = 3, maxRows = 0, showIcon = "yes" }
style = UI:ApplyAlertStyle()
assert(style.iconSize == 48 and style.countSize == 20 and style.align == "LEFT" and style.grow == "DOWN")
assert(style.maxRows == 1 and style.showIcon == false)

-- Settings sample: same layout code, follows the style, at most three lines.
ns.db.alertStyle = {}
UI:ApplyAlertStyle()
local holder = CreateFrame("Frame", nil, UIParent)
local sample = UI:CreateAlertSample(holder)
assert(Shown(sample.rows) == 3 and sample.width == 320 and sample.height == 94)
assert(sample.rows[1].countdown.text == "9" and sample.rows[2].countdown.text == "3")
assert(sample.rows[3].countdown.text == "지금")
ns.db.alertStyle = { maxRows = 2, iconSize = 34, align = "RIGHT" }
UI:ApplyAlertStyle()
assert(Shown(sample.rows) == 2 and sample.rows[1].icon.width == 34)
assert(sample.rows[1].content.points.RIGHT, "sample follows alignment")

-- Background opacity reaches the sample, and a media refresh keeps the chosen sizes.
ns.db.backgroundAlpha = 0
UI:ApplyDisplaySettings()
assert(sample.rows[1].shade2.gradient[3][4] == 0 and UI.upcomingRows[1].shade.gradient[2][4] == 0)
ns.db.alertStyle = { nameSize = 21, countSize = 30 }
UI:ApplyAlertStyle()
UI:RefreshMedia()
assert(UI.upcomingRows[1].label.fontSize == 21 and UI.upcomingRows[1].countdown.fontSize == 30)
'''


def run(extra=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Measure = lambda text, size: sum(
        0.95 if ord(char) >= 0x1100 else 0.65
        for char in re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)
    ) * size
    lua.execute(MOCK.read_text(encoding="utf-8"))
    lua.execute(EXTRA)
    lua.execute(BAR_EXTRA)
    lua.execute(STYLE_EXTRA)
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


def test_alert_style_options_drive_the_layout():
    run()


def test_largest_alert_elements_fit_the_smallest_width():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
for _, align in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
    ns.db.alertStyle = { width = 160, iconSize = 48, nameSize = 24, countSize = 36, align = align }
    local style = UI:ApplyAlertStyle()
    local row = UI.alertSample.rows[3]
    row.popStarted = 10
    UI:AnimateCountdown(row, 10)
    assert(row.countdown.textScale < 1.4, "large Korean count must limit its pop in a narrow row")
    assert(row.content:GetWidth() <= row:GetWidth() - 4, "alert group escapes minimum width: " .. align)
    local x, _, width = row.countdown:Rect()
    local shownWidth = row.countdown:GetStringWidth() * row.countdown.textScale
    if align == "RIGHT" then
        assert(x + width - shownWidth >= row:GetLeft() + 2, "right-aligned count escapes row")
    else
        assert(x + shownWidth <= row:GetLeft() + row:GetWidth() - 2, "count escapes row")
    end
end
''')


if __name__ == "__main__":
    run()
    print("PASS: RaidHelper alert style options")
