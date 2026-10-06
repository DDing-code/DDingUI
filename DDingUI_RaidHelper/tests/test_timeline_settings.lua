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

local frame = NewBackdrop()
frame.SetScale = function(self, value) self.scale = value end
frame.SetSize = function(self, width, height)
    self.width = width
    self.height = height
end
frame.Show = function(self) self.shown = true end
frame.Hide = function(self) self.shown = false end
frame.header = { background = NewTexture() }
frame.pastShade = NewTexture()

ns.TimelineUI.frame = frame
ns.TimelineUI.plot = NewBackdrop()
ns.TimelineUI.plot.SetHeight = function(self, value) self.height = value end
ns.TimelineUI.flatTexture = "flat"
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

assert(ns.TimelineUI:ApplyDisplaySettings())
assert(frame.scale == 1.25)
assert(frame.width == 820 and frame.height == 260)
assert(ns.TimelineUI.plot.height == 138)
assert(math.abs(frame.backgroundColor[4] - 0.38) < 0.0001)
assert(math.abs(ns.TimelineUI.plot.backgroundColor[4] - 0.32) < 0.0001)
assert(math.abs(frame.header.background.color[4] - 0.392) < 0.0001)
assert(math.abs(frame.pastShade.color[4] - 0.168) < 0.0001)

ns.db.timelineScale = 5
ns.db.timelineWidth = 5000
ns.db.timelineHeight = 20
ns.db.backgroundAlpha = -1
assert(ns.TimelineUI:ApplyDisplaySettings())
assert(frame.scale == 1.6)
assert(frame.width == 1200 and frame.height == 170)
assert(ns.TimelineUI.plot.height == 48)
assert(frame.backgroundColor[4] == 0)

ns.db.timelineWidth = 100
assert(ns.TimelineUI:ApplyDisplaySettings())
assert(frame.width == 200)

ns.db.windowPast = 12
ns.db.windowFuture = 38
ns.TimelineUI.markerSize = 28

local lane = {}
local marker = {
    parent = lane,
    icon = { SetTexture = function(self, value) self.value = value end },
    countdown = { SetText = function(self, value) self.value = value end },
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
    Show = function(self) self.shown = true end,
}

ns.TimelineUI:ConfigureMarker(marker, {
    t = 0,
    icon = 12345,
    spread = 20,
}, 12, 100, "cooldown")
assert(marker.point == 14)
assert(marker.spread.point - marker.spread.width * 0.5 >= 0)
assert(marker.spread.point + marker.spread.width * 0.5 <= 100)

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

ns.TimelineUI:ConfigureMarker(marker, {
    t = 50,
    icon = 12345,
    spread = 20,
}, 12, 100, "cooldown")
assert(marker.point == 86)
assert(marker.spread.point - marker.spread.width * 0.5 >= 0)
assert(marker.spread.point + marker.spread.width * 0.5 <= 100)

assert(ns.TimelineUI:SetPreviewMode(true))
assert(ns.TimelineUI:IsPreviewMode())
assert(ns.Engine.options.demo and ns.Engine.options.loop)
assert(ns.Engine.options.previewMode and ns.Engine.options.editMode)
assert(frame.shown == true and previewStarts == 1)
assert(ns.TimelineUI:TogglePreviewMode())
assert(not ns.TimelineUI:IsPreviewMode())
assert(frame.shown == false and previewStops == 1)

-- The old edit-mode API remains a compatibility alias for the one preview mode.
assert(ns.TimelineUI:SetEditMode(true))
assert(ns.TimelineUI:IsPreviewMode())
assert(ns.TimelineUI:ToggleEditMode())
assert(not ns.TimelineUI:IsPreviewMode())
assert(previewStarts == 2 and previewStops == 2)

print("RaidHelper timeline display settings test OK")
