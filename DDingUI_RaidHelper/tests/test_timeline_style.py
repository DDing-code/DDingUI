"""Timeline detail options (2026-10-11 사용자 요청): icon sizes, past-icon opacity and one switch
per bar element, applied by the shipped Timeline.lua on the frame mock at 0:42.2 of the demo
(암흑 붕괴 in 3.8 s, 오라 숙련 in 2.3 s). Pixel output in the real client remains an in-game check.
"""
from test_timeline_bar import run

SCENARIO = r'''
local ns = ...
local UI = ns.TimelineUI
local frame, plot = UI.frame, UI.plot
local model = ns.Registry:GetByKey("demo")
ns.Engine.GetTimelineTime = function() return 42.2 end
ns.Engine.model, ns.Engine.running, ns.Engine.options = model, true, {}
UI:OnEngineEvent("START", model)

local function Count(pool, field)
    local count = 0
    for _, entry in ipairs(pool) do
        local region = field and entry[field] or entry
        if region.shown then count = count + 1 end
    end
    return count
end
local function Mechanic(t)
    for _, marker in ipairs(UI.mechanicMarkers) do
        if marker.shown and marker.data.t == t then return marker end
    end
end
local function Apply(style)
    ns.db.timelineStyle = style
    assert(UI:ApplyTimelineStyle())
end
local function Tallest()
    local tallest = 0
    for _, column in ipairs(UI.damageColumns) do
        if column.shown and column.height > tallest then tallest = column.height end
    end
    return tallest
end

-- Defaults are the fixed C안 bar: nothing saved, every element drawn.
assert(type(ns.db.timelineStyle) == "table" and next(ns.db.timelineStyle) == nil)
Apply({})
local mechanics, cooldowns = Count(UI.mechanicMarkers), Count(UI.cooldownMarkers)
local grids, ribbons = Count(UI.gridLines, "line"), Count(UI.phaseMarkers, "ribbon")
local defaultRidge = Tallest()
assert(mechanics >= 2 and cooldowns >= 2 and grids >= 8 and ribbons >= 2 and defaultRidge > 0)
assert(Count(UI.damageColumns) > 60 and Count(UI.cooldownMarkers, "spread") >= 1)
assert(Mechanic(46).width == 32 and frame.cooldownChip.shown and frame.timeReadout.shown)
assert(plot.height == 70 and frame.cooldownLayer.height == 28)

-- Bigger icons: the rail grows with the cooldown icon, the bar keeps the rest of the height,
-- the ridge stays under the larger icon row and both detail chips still sit beside their icons.
Apply({ mechanicSize = 36, cooldownSize = 26 })
assert(frame.height == 98 and frame.cooldownLayer.height == 36 and plot.height == 62)
local nearest = Mechanic(46)
assert(nearest.width == 40 and nearest.height == 40 and nearest.glow.shown)
for _, marker in ipairs(UI.mechanicMarkers) do
    if marker.shown and marker ~= nearest then assert(marker.width == 36) end
end
for _, marker in ipairs(UI.cooldownMarkers) do
    if marker.shown then assert(marker.width == 26 and marker.height == 26) end
end
assert(Tallest() <= plot.height - 44 + 0.001, "ridge stays below the larger icon row")
local chip, cooldownChip = frame.mechanicChip, frame.cooldownChip
if chip.shown and chip.points.TOPLEFT then
    assert(math.abs(chip.points.TOPLEFT[3] - (nearest.x + 24)) < 1e-6)
end
assert(cooldownChip.shown)
local chipPoint = cooldownChip.points.TOPLEFT or cooldownChip.points.TOPRIGHT
assert(chipPoint[4] == -12, "rail chip is centred on the 26 px icon")
for _, entry in ipairs({ { chip, UI.mechanicMarkers }, { cooldownChip, UI.cooldownMarkers } }) do
    local detail, markers = entry[1], entry[2]
    if detail:IsShown() then
        local left = detail:GetLeft()
        for _, marker in ipairs(markers) do
            if marker:IsShown() then
                local iconLeft = marker:GetLeft()
                assert(left + detail:GetWidth() <= iconLeft or left >= iconLeft + marker:GetWidth(),
                    "detail chip covers a resized icon")
            end
        end
    end
end

-- Largest icons: the mechanic icon shrinks until it and its countdown fit the remaining bar.
Apply({ mechanicSize = 40, cooldownSize = 32 })
assert(plot.height == 56 and UI.mechanicSize == 32)
for _, marker in ipairs(UI.mechanicMarkers) do
    if marker.shown and not marker.nearState then
        assert(10 + marker.height + 14 <= plot.height, "icon and countdown stay inside the bar")
    end
end
ns.db.timelineHeight = 80
Apply({ mechanicSize = 40, cooldownSize = 32 })
assert(plot.height == 38 and UI.mechanicSize == 16)
ns.db.timelineHeight = 98

-- Nearest highlight off: same size and border as the others, details stay.
Apply({ highlightNear = false })
nearest = Mechanic(46)
assert(nearest.width == 28 and not nearest.glow.shown and nearest.nearState)
assert(nearest.border[1] == nearest.borderColor[1] and nearest.points.TOP[4] == -10)
assert(chip.shown ~= nearest.countdown.shown and chip.number.text == "3.8")

-- Detail chips off: the nearest mechanic counts under its own icon instead.
Apply({ showMechanicDetail = false, showCooldownDetail = false })
nearest = Mechanic(46)
assert(not chip.shown and not cooldownChip.shown)
assert(nearest.width == 32 and nearest.countdown.shown and nearest.countdown.text == "3.8")

-- Countdown numbers off, also when the detail chip is off or does not fit.
Apply({ showCountdown = false, showMechanicDetail = false })
assert(Count(UI.mechanicMarkers, "countdown") == 0)
Apply({ showCountdown = false })
assert(Count(UI.mechanicMarkers, "countdown") == 0 and Count(UI.mechanicMarkers) == mechanics)

-- Mechanic icons off: no icons or chip; the ridge may use the freed space.
Apply({ showMechanics = false })
assert(Count(UI.mechanicMarkers) == 0 and not chip.shown)
assert(Count(UI.cooldownMarkers) == cooldowns and Tallest() > defaultRidge)

-- Cooldown icons off: the rail is empty, but the reminder keeps announcing the same cooldown.
Apply({ showCooldowns = false })
assert(Count(UI.cooldownMarkers) == 0 and not cooldownChip.shown)
assert(Count(UI.mechanicMarkers) == mechanics)
assert(UI.upcomingRows[1].shown and UI.upcomingRows[1].label.text == "오라 숙련")

-- Timing band, ridge, grid, phases and the time readout each have their own switch.
Apply({ showSpread = false })
assert(Count(UI.cooldownMarkers, "spread") == 0 and Count(UI.cooldownMarkers) == cooldowns)
Apply({ showDamage = false })
assert(Count(UI.damageColumns) == 0 and Count(UI.damageLines) == 0 and not frame.noDataText.shown)
assert(Count(UI.gridLines, "line") == grids)
Apply({ showGrid = false })
assert(Count(UI.gridLines, "line") == 0 and Count(UI.damageColumns) > 60)
Apply({ showPhases = false })
assert(Count(UI.phaseMarkers, "ribbon") == 0 and Count(UI.phaseMarkers, "line") == 0)
assert(Count(UI.phaseMarkers, "chip") == 0)
Apply({ showTimeReadout = false })
assert(not frame.timeReadout.shown)

-- Past icons: opacity is a percentage, 0 hides them.
ns.Engine.GetTimelineTime = function() return 50 end
Apply({ pastAlpha = 80 })
local past = Mechanic(46)
assert(past and math.abs(past.alpha - 0.8) < 1e-6)
Apply({ pastAlpha = 0 })
assert(not Mechanic(46))
for _, marker in ipairs(UI.mechanicMarkers) do
    if marker.shown then assert(marker.data.t >= 50, "only upcoming icons remain") end
end
ns.Engine.GetTimelineTime = function() return 42.2 end

-- Shown range uses the older keys; a wider future window squeezes the same events left.
Apply({})
local before = Mechanic(46).x
ns.db.windowFuture = 60
UI:ApplyTimelineStyle()
assert(Mechanic(46).x < before and UI:GetTimelineStyle().windowFuture == 60)
ns.db.windowFuture = 38

-- Back to an empty table: the fixed bar again.
Apply({})
assert(Count(UI.mechanicMarkers) == mechanics and Count(UI.cooldownMarkers) == cooldowns)
assert(Count(UI.gridLines, "line") == grids and Count(UI.phaseMarkers, "ribbon") == ribbons)
assert(math.abs(Tallest() - defaultRidge) < 1e-6 and Mechanic(46).width == 32 and Mechanic(46).glow.shown)
assert(plot.height == 70 and frame.cooldownLayer.height == 28 and frame.timeReadout.shown)
'''


def test_timeline_detail_options_drive_the_bar():
    run(SCENARIO)


if __name__ == "__main__":
    run(SCENARIO)
    print("PASS: RaidHelper timeline detail options")
