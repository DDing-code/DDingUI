"""Run the shipped reminder against the frame mock through motion and row reuse."""
from test_upcoming_countdown import run


SETUP = r'''
local ns = ...
local UI = ns.TimelineUI
ns.db.alertStyle, ns.db.backgroundAlpha = {}, 1
ns.db.showUpcoming, ns.db.countdownVoice = true, false
UI:ApplyAlertStyle()
UI:ResetUpcomingMotion()
local entries = {
    { t = 5, spellID = 31821, label = "오라 숙련" },
    { t = 8.6, spellID = 115310, label = "재활" },
    { t = 12.3, spellID = 740, label = "평온" },
    { t = 16.8, spellID = 64843, label = "천상의 찬가" },
}
ns.Engine.GetCooldowns = function() return entries end
local clock = 0
ns.Engine.GetTimelineTime = function() return clock end
local function At(t)
    now = 100 + t
    clock = t
    UI:UpdateUpcomingCooldowns(t)
    return UI.upcomingRows[1]
end
local function Near(a, b) return math.abs(a - b) < 0.001 end
'''


def test_enter_urgent_flash_exit_and_frame_rate_update():
    run(SETUP + r'''
local row = At(0)
assert(row.alpha == 0 and row.points.TOPLEFT[3] == -10, "enter starts transparent, 10px left")
now = now + 0.125
UI.elapsed = 0
UI:OnUpdate(0.01)
assert(Near(row.alpha, 0.75) and Near(row.points.TOPLEFT[3], -2.5), "entry runs between model ticks")
At(0.25)
assert(row.alpha == 1 and row.points.TOPLEFT[3] == 0)
At(2.1)
assert(row.countdown.text == "3" and row.countdown.textScale > 1.3)
assert(row.tint.alpha == 0.45 and row.drain.shown and Near(row.drain.width, 316 * 2.9 / 3))
assert(row.glowLayers[1].shown)
At(2.4)
assert(row.countdown.textScale == 1, "pop finishes without restarting each update")
At(5)
assert(row.countdown.text == "지금" and row.countdown.textColor[2] == UI.colors.text.highlight[2])
assert(row.flash.alpha == 1 and not row.drain.shown)
At(5.2)
assert(Near(row.flash.alpha, 0.25))
At(5.4)
assert(Near(row.flash.alpha, 0))
At(5.6)
assert(Near(row.alpha, 0.5) and Near(row.points.TOPLEFT[4], 4.5), "exit fades while rising 6px")
At(5.8)
assert(row.data ~= entries[1], "expired event leaves the pool")
''')


def test_survivors_keep_identity_and_slide_without_overlapping_new_rows():
    run(SETUP + r'''
At(0.3)
At(0.6)
At(0.9)
local first, second, third = UI.upcomingRows[1], UI.upcomingRows[2], UI.upcomingRows[3]
local secondEntered = second.enterStarted
At(5.6)
At(5.8)
local fourth = UI.upcomingRows[3]
assert(UI.upcomingRows[1] == second and UI.upcomingRows[2] == third, "row identity follows the event")
assert(second.enterStarted == secondEntered and second.alpha == 1, "survivor never re-enters")
assert(fourth == first and fourth.data == entries[4], "expired frame is reused")
assert(Near(second.motionY - third.motionY, 32) and Near(third.motionY - fourth.motionY, 32))
At(5.9)
assert(Near(second.motionY, -8) and Near(third.motionY, -40) and Near(fourth.motionY, -72), "all lines move together")
At(6.01)
assert(Near(second.motionY, 0) and Near(third.motionY, -32) and Near(fourth.motionY, -64))
for n = 1, 12 do At(6 + n * 1.6) end
assert(#UI.upcomingRows == 3, "the frame pool stays bounded")
''')


def test_toggle_resync_upward_growth_and_stop_clear_motion():
    run(SETUP + r'''
At(0); At(0.3); At(5)
local row = UI.upcomingRows[1]
assert(row.flash.alpha == 1)
At(4)
assert(row.nowStarted == nil and row.flash.alpha == 0, "backward resync clears now flash")
ns.db.alertStyle.pop = false
UI:ApplyAlertStyle()
assert(row.alpha == 1 and row.countdown.textScale == 1 and row.points.TOPLEFT[3] == 0)
assert(row.tint.alpha == 0 and row.flash.alpha == 0 and not row.drain.shown and not row.glowLayers[1].shown)
At(5.6)
assert(row.alpha == 1 and row.points.TOPLEFT[4] == row.targetY, "disabled means no exit movement")
ns.db.alertStyle = { grow = "UP", align = "RIGHT" }
UI:ApplyAlertStyle()
UI:ResetUpcomingMotion()
At(0.3); At(0.6); At(0.9)
local second = UI.upcomingRows[2]
assert(second.points.BOTTOMLEFT and Near(second.motionY, 32))
At(5.8); At(5.9)
assert(UI.upcomingRows[1] == second and Near(second.motionY, 8), "upward rows also retain identity")
At(6.1)
assert(Near(second.motionY, 0))
ns.Engine.running = false
UI:OnEngineEvent("STOP", false)
assert(not UI.upcomingPanel.shown)
for _, line in ipairs(UI.upcomingRows) do assert(not line.shown and line.data == nil) end
''')
