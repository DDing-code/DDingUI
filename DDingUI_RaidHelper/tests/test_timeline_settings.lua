local addonName = "DDingUI_RaidHelper"
local previewStarts = 0
local previewStops = 0
local ns = {
    db = {
        timelineScale = 1.25,
        timelineWidth = 820,
        timelineHeight = 260,
        backgroundAlpha = 0.4,
        showUpcomingCooldowns = true,
    },
    Print = function() end,
    Registry = {
        GetByKey = function(_, key)
            assert(key == "demo")
            return { name = "Preview" }
        end,
    },
    Engine = {
        running = false,
        options = {},
        IsRunning = function(self) return self.running end,
        StartModel = function(self, model, options)
            assert(model.name == "Preview")
            self.running = true
            self.options = options
            previewStarts = previewStarts + 1
            return true
        end,
        StopEncounter = function(self)
            self.running = false
            previewStops = previewStops + 1
        end,
        cooldowns = {},
        GetCooldowns = function(self) return self.cooldowns end,
    },
}

local function NewBackdrop()
    return {
        SetBackdrop = function(self, value) self.backdrop = value end,
        SetBackdropColor = function(self, red, green, blue, alpha)
            self.backgroundColor = { red, green, blue, alpha }
        end,
        SetBackdropBorderColor = function(self, red, green, blue, alpha)
            self.borderColor = { red, green, blue, alpha }
        end,
    }
end

local function NewTexture()
    return {
        SetColorTexture = function(self, red, green, blue, alpha)
            self.color = { red, green, blue, alpha }
        end,
    }
end

assert(loadfile("UI/Timeline.lua"))(addonName, ns)

local function NewLabel()
    return {
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, point, _, _, x, y) self.point = { point, x, y } end,
        SetShown = function(self, value) self.shown = value == true end,
    }
end

local frame = NewBackdrop()
frame.SetScale = function(self, value) self.scale = value end
frame.SetSize = function(self, width, height)
    self.width = width
    self.height = height
end
frame.Show = function(self) self.shown = true end
frame.Hide = function(self) self.shown = false end
frame.barBackground = NewTexture()
frame.barBackground._raidHelperRounded = true
frame.barBackground.SetVertexColor = function(self, red, green, blue, alpha)
    self.vertex = { red, green, blue, alpha }
end
frame.pastShade = NewTexture()
frame.timeReadout = NewLabel()
frame.syncText = NewLabel()

ns.TimelineUI.frame = frame
ns.TimelineUI.plot = NewBackdrop()
ns.TimelineUI.plot.SetHeight = function(self, value) self.height = value end
ns.TimelineUI.cooldownLayer = { SetHeight = function(self, value) self.height = value end }
ns.TimelineUI.flatTexture = "flat"
ns.TimelineUI.accentFrom = { 0.84, 0.36, 1.0, 1.0 }
ns.TimelineUI.colors = {
    bg = {
        main = { 0.1, 0.1, 0.1, 0.95 },
        input = { 0.06, 0.06, 0.06, 0.8 },
        titlebar = { 0.12, 0.12, 0.12, 0.98 },
        sidebar = { 0.08, 0.08, 0.08, 0.95 },
    },
    border = {
        default = { 0.25, 0.25, 0.25, 0.5 },
        separator = { 0.2, 0.2, 0.2, 0.4 },
    },
}

-- [STYLE] C안: 260 is a height from the old four-row window, so it reads as the new
-- default (bar 70 + rail 28) instead of being clamped to 160.
assert(ns.TimelineUI:ApplyDisplaySettings())
assert(frame.scale == 1.25)
assert(frame.width == 820 and frame.height == 98)
assert(ns.TimelineUI.plot.height == 70 and ns.TimelineUI.cooldownLayer.height == 28)
-- Background opacity scales only the bar surface and the past shade; no outline outside edit.
assert(math.abs(frame.barBackground.vertex[4] - 0.32) < 0.0001)
assert(math.abs(frame.pastShade.color[4] - 0.14) < 0.0001)
assert(frame.borderColor[4] == 0)
-- The time readout sits above the left fade edge (12% of 820 = 98).
assert(frame.timeReadout.point[1] == "BOTTOMLEFT" and frame.timeReadout.point[2] == 98)
assert(frame.timeReadout.shown == true and ns.TimelineUI.compact == false)

local resolve = ns.TimelineUI.ResolveTimelineHeight
assert(resolve(nil) == 98 and resolve(20) == 80 and resolve(120) == 120)
assert(resolve(165) == 160 and resolve(170) == 98 and resolve(420) == 98)

local edge = ns.TimelineUI.EdgeAlpha
assert(edge(0, 100) == 0 and edge(100, 100) == 0 and edge(-5, 100) == 0 and edge(105, 100) == 0)
assert(edge(50, 100) == 1 and edge(12, 100) == 1 and edge(88, 100) == 1)
assert(edge(6, 100) > 0 and edge(6, 100) < 1)
assert(math.abs(edge(6, 100) - edge(94, 100)) < 0.0001)
assert(edge(3, 100) < edge(6, 100))

ns.db.timelineScale = 5
ns.db.timelineWidth = 5000
ns.db.timelineHeight = 20
ns.db.backgroundAlpha = -1
assert(ns.TimelineUI:ApplyDisplaySettings())
assert(frame.scale == 1.6)
assert(frame.width == 1200 and frame.height == 80)
assert(ns.TimelineUI.plot.height == 52)
assert(frame.barBackground.vertex[4] == 0 and frame.pastShade.color[4] == 0)

ns.db.timelineHeight = 160
assert(ns.TimelineUI:ApplyDisplaySettings())
assert(frame.height == 160 and ns.TimelineUI.plot.height == 132)

ns.db.timelineWidth = 100
assert(ns.TimelineUI:ApplyDisplaySettings())
assert(frame.width == 200)
assert(ns.TimelineUI.compact == true and frame.timeReadout.shown == false)

-- [STYLE] Timeline detail options (2026-10-11): the rail follows the cooldown icon, the bar keeps
-- the rest of the height, and a mechanic icon never outgrows that bar. Broken values clamp.
local resolveStyle = ns.TimelineUI.ResolveTimelineStyle
local defaults = resolveStyle(nil)
assert(defaults.mechanicSize == 28 and defaults.cooldownSize == 18 and defaults.pastAlpha == 38)
assert(defaults.windowPast == 12 and defaults.windowFuture == 38)
for _, key in ipairs({ "showMechanics", "showCooldowns", "showCountdown", "showMechanicDetail",
    "showCooldownDetail", "showSpread", "highlightNear", "showDamage", "showPhases", "showGrid",
    "showTimeReadout" }) do
    assert(defaults[key] == true, key)
end
local broken = resolveStyle({ windowPast = 999, windowFuture = "x",
    timelineStyle = { mechanicSize = 3, cooldownSize = 500, pastAlpha = -4, showGrid = "yes" } })
assert(broken.mechanicSize == 16 and broken.cooldownSize == 32 and broken.pastAlpha == 0)
assert(broken.windowPast == 30 and broken.windowFuture == 38 and broken.showGrid == false)

ns.db.timelineWidth = 680
ns.db.timelineHeight = 98
ns.db.timelineStyle = { cooldownSize = 32, mechanicSize = 40 }
assert(ns.TimelineUI:ApplyTimelineStyle())
assert(frame.height == 98 and ns.TimelineUI.cooldownLayer.height == 42 and ns.TimelineUI.plot.height == 56)
assert(ns.TimelineUI.mechanicSize == 32, "icon + its countdown must stay inside a 56 px bar")
ns.db.timelineStyle.showCountdown = false
assert(ns.TimelineUI:ApplyTimelineStyle())
assert(ns.TimelineUI.mechanicSize == 40, "without the number only the highlight growth needs room")
ns.db.timelineHeight = 80
assert(ns.TimelineUI:ApplyTimelineStyle())
assert(ns.TimelineUI.plot.height == 38 and ns.TimelineUI.mechanicSize == 26, "icon shrinks to the bar")
ns.db.timelineStyle = { mechanicSize = 40 }
ns.db.timelineHeight = 98
assert(ns.TimelineUI:ApplyTimelineStyle())
assert(ns.TimelineUI.plot.height == 70 and ns.TimelineUI.mechanicSize == 40, "largest icon fits the default bar")
ns.db.timelineStyle = {}
ns.db.timelineHeight = 80
assert(ns.TimelineUI:ApplyTimelineStyle())
assert(ns.TimelineUI.plot.height == 52 and ns.TimelineUI.mechanicSize == 28, "defaults unchanged at the smallest height")
ns.db.timelineStyle = { showTimeReadout = false }
assert(ns.TimelineUI:ApplyTimelineStyle())
assert(frame.timeReadout.shown == false and ns.TimelineUI.cooldownLayer.height == 28)
ns.db.timelineStyle = {}
ns.db.timelineWidth = 100
assert(ns.TimelineUI:ApplyTimelineStyle())

ns.db.windowPast = 12
ns.db.windowFuture = 38
local lane = {}
local function NewMarker()
    return {
        parent = lane,
        icon = { SetTexture = function(self, value) self.value = value end },
        spread = {
            ClearAllPoints = function(self) self.point = nil end,
            SetPoint = function(self, _, _, _, x) self.point = x end,
            SetWidth = function(self, value) self.width = value end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
        },
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, _, _, _, x) self.point = x end,
        GetParent = function(self) return self.parent end,
        SetSize = function(self, width, height) self.width, self.height = width, height end,
        SetAlpha = function(self, value) self.alpha = value end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
end
local marker = NewMarker()

-- [STYLE] C안: icons are not clamped into the bar; at the very edge they fade to nothing.
assert(ns.TimelineUI:ConfigureMarker(marker, { t = 0, icon = 12345, spread = 20 }, 12, 100, "cooldown") == false)
assert(marker.shown == false)

-- Inside the fade zone the icon is partly transparent; the ± band stays inside the bar.
assert(ns.TimelineUI:ConfigureMarker(marker, { t = 1, icon = 12345, spread = 20 }, 12, 100, "cooldown"))
assert(marker.shown == true and marker.point == 2)
assert(marker.alpha > 0 and marker.alpha < 1)
assert(marker.spread.point - marker.spread.width * 0.5 >= 0)
assert(marker.spread.point + marker.spread.width * 0.5 <= 100)

-- Fully inside: full opacity for upcoming, 38% for past events.
assert(ns.TimelineUI:ConfigureMarker(marker, { t = 30, icon = 12345 }, 12, 100, "cooldown"))
assert(marker.alpha == 1 and marker.spread.shown == false and marker.remaining == 18)
assert(ns.TimelineUI:ConfigureMarker(marker, { t = 10, icon = 12345 }, 12, 100, "cooldown"))
assert(math.abs(marker.alpha - 0.38) < 0.0001)
assert(marker.width == 18)
-- Past-icon opacity is a setting; 0% hides past icons, and the ± band has its own switch.
ns.db.timelineStyle = { pastAlpha = 70, cooldownSize = 24, showSpread = false }
ns.TimelineUI:ApplyTimelineStyle()
assert(ns.TimelineUI:ConfigureMarker(marker, { t = 10, icon = 12345, spread = 20 }, 12, 100, "cooldown"))
assert(math.abs(marker.alpha - 0.7) < 0.0001 and marker.width == 24 and marker.spread.shown == false)
ns.db.timelineStyle = { pastAlpha = 0 }
ns.TimelineUI:ApplyTimelineStyle()
assert(ns.TimelineUI:ConfigureMarker(marker, { t = 10, icon = 12345 }, 12, 100, "cooldown") == false)
assert(ns.TimelineUI:ConfigureMarker(marker, { t = 30, icon = 12345 }, 12, 100, "cooldown"))
ns.db.timelineStyle = {}
ns.TimelineUI:ApplyTimelineStyle()

ns.Engine.cooldowns = {
    { t = 22, spellID = 4 },
    { t = 9.5, spellID = 1 },
    { t = 15, spellID = 2 },
    { t = 18, spellID = 3 },
    { t = 30, spellID = 5 },
}
local upcoming = ns.TimelineUI:CollectUpcomingCooldowns(10, 12, 3)
assert(#upcoming == 3)
assert(upcoming[1].data.spellID == 1 and upcoming[1].remaining == -0.5)
assert(upcoming[2].data.spellID == 2 and upcoming[2].remaining == 5)
assert(upcoming[3].data.spellID == 3 and upcoming[3].remaining == 8)
ns.db.showUpcomingCooldowns = false
assert(#ns.TimelineUI:CollectUpcomingCooldowns(10, 12, 3) == 0)
ns.db.showUpcomingCooldowns = true

assert(ns.TimelineUI:ConfigureMarker(marker, { t = 49, icon = 12345, spread = 20 }, 12, 100, "cooldown"))
assert(marker.point == 98 and marker.alpha > 0 and marker.alpha < 1)
assert(marker.spread.point - marker.spread.width * 0.5 >= 0)
assert(marker.spread.point + marker.spread.width * 0.5 <= 100)
assert(ns.TimelineUI:ConfigureMarker(marker, { t = 50, icon = 12345 }, 12, 100, "cooldown") == false)

assert(ns.TimelineUI:SetPreviewMode(true))
assert(ns.TimelineUI:IsPreviewMode())
assert(ns.Engine.options.demo and ns.Engine.options.loop)
assert(ns.Engine.options.previewMode and not ns.Engine.options.editMode)
assert(frame.shown == true and previewStarts == 1)
assert(ns.TimelineUI:TogglePreviewMode())
assert(not ns.TimelineUI:IsPreviewMode())
assert(frame.shown == false and previewStops == 1)

-- Editing is separate from the watch-only preview, while still using the demo engine.
assert(ns.TimelineUI:SetEditMode(true))
assert(ns.TimelineUI:IsPreviewMode())
assert(ns.TimelineUI:ToggleEditMode())
assert(not ns.TimelineUI:IsPreviewMode())
assert(previewStarts == 2 and previewStops == 2)

print("RaidHelper timeline display settings test OK")
