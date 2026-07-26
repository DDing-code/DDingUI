local _, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local context = ns.BuffTrackerOptionsContext
if not context then return end

local GetSpecConfig = context.GetSpecConfig
local GetViewerOptions = context.GetViewerOptions
local MarkSpecDirty = context.MarkSpecDirty

local function CreateGlobalBuffTrackerSettings()
    local options = {}

    options["header"] = {
        type = "header",
        name = L["Buff Tracker Bar Settings"] or "Buff Tracker Bar Settings",
        order = 1,
    }
    options["description"] = {
        type = "description",
        name = L["Track spell casts to display stacks as a resource bar. Configure trigger spells that generate stacks and consumer spells that spend stacks."] or "Track spell casts to display stacks as a resource bar. Configure trigger spells that generate stacks and consumer spells that spend stacks.",
        order = 1.5,
    }
    options["enabled"] = {
        type = "toggle",
        name = L["Enable Buff Tracker Bar"] or "Enable Buff Tracker Bar",
        desc = L["Show a bar that tracks a specific buff's stacks"] or "Show a bar that tracks a specific buff's stacks",
        width = "full",
        order = 2,
        get = function() return DDingUI.db.profile.buffTrackerBar.enabled end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.enabled = val
            local cfg = GetSpecConfig()
            if cfg and not cfg.trackingMode then
                cfg.trackingMode = "cdm"
            end
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["previewMode"] = {
        type = "toggle",
        name = L["Preview Mode"] or "Preview Mode",
        desc = L["Show all tracked buffs for configuration (ignores hideWhenZero)"] or "Show all tracked buffs for configuration (ignores hideWhenZero)",
        width = "full",
        order = 2.5,
        get = function()
            return DDingUI.IsBuffTrackerPreviewEnabled and DDingUI:IsBuffTrackerPreviewEnabled() or false
        end,
        set = function(_, val)
            if val then
                DDingUI:EnableBuffTrackerPreview()
            else
                DDingUI:DisableBuffTrackerPreview()
            end
        end,
    }

    options["growthDirectionHeader"] = {
        type = "description",
        name = "|cffffcc00" .. (L["Growth Direction"] or "Growth Direction") .. "|r",
        order = 3, width = "full", fontSize = "medium",
    }
    options["growthDirection"] = {
        type = "select",
        name = L["Growth Direction"] or "Growth Direction",
        desc = L["Direction in which multiple bars/rings stack"] or "Direction in which multiple bars/rings stack",
        order = 3.1, width = 0.8,
        values = {
            ["DOWN"] = L["Down"] or "Down",
            ["UP"] = L["Up"] or "Up",
            ["LEFT"] = L["Left"] or "Left",
            ["RIGHT"] = L["Right"] or "Right",
        },
        get = function() return DDingUI.db.profile.buffTrackerBar.growthDirection or "DOWN" end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.growthDirection = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }
    options["growthSpacing"] = {
        type = "range",
        name = L["Growth Spacing"] or "Growth Spacing",
        desc = L["Spacing between stacked bars/rings"] or "Spacing between stacked bars/rings",
        order = 3.2, width = 0.8,
        min = 0, max = 50, step = 1,
        get = function() return DDingUI.db.profile.buffTrackerBar.growthSpacing or 20 end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.growthSpacing = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    options["positionHeader"] = {
        type = "description",
        name = "|cffffcc00" .. (L["Position & Anchor"] or "Position & Anchor") .. "|r",
        order = 3.3, width = "full", fontSize = "medium",
    }
    options["attachTo"] = {
        type = "select",
        name = L["Attach To"] or "Attach To",
        desc = L["Which frame to attach this bar to"] or "Which frame to attach this bar to",
        order = 3.31, width = "double",
        values = function()
            local opts = {}
            opts["UIParent"] = L["Screen (UIParent)"] or "Screen (UIParent)"
            if DDingUI.db.profile.unitFrames and DDingUI.db.profile.unitFrames.enabled then
                opts["DDingUI_Player"] = L["Player Frame (Custom)"] or "Player Frame (Custom)"
            end
            opts["PlayerFrame"] = L["Default Player Frame"] or "Default Player Frame"
            local viewerOpts = GetViewerOptions()
            for k, v in pairs(viewerOpts) do
                opts[k] = v
            end
            local current = DDingUI.db.profile.buffTrackerBar.attachTo
            if current and not opts[current] then
                opts[current] = current .. " (Custom)"
            end
            return opts
        end,
        get = function() return DDingUI.db.profile.buffTrackerBar.attachTo end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.attachTo = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["pickFrameGlobal"] = {
        type = "execute",
        name = L["Pick Frame"] or "Pick Frame",
        desc = L["Click to select a frame from the UI"] or "Click to select a frame from the UI",
        order = 3.315, width = "half",
        func = function()
            DDingUI:StartFramePicker(function(frameName)
                if frameName then
                    DDingUI.db.profile.buffTrackerBar.attachTo = frameName
                    DDingUI:UpdateBuffTrackerBar()
                end
            end)
        end,
    }
    options["anchorPoint"] = {
        type = "select",
        name = L["Anchor Point"] or "Anchor Point",
        desc = L["Which point on the anchor frame to attach to"] or "Which point on the anchor frame to attach to",
        order = 3.32, width = "normal",
        values = {
            TOPLEFT = L["Top Left"] or "Top Left", TOP = L["Top"] or "Top", TOPRIGHT = L["Top Right"] or "Top Right",
            LEFT = L["Left"] or "Left", CENTER = L["Center"] or "Center", RIGHT = L["Right"] or "Right",
            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left", BOTTOM = L["Bottom"] or "Bottom", BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
        },
        get = function() return DDingUI.db.profile.buffTrackerBar.anchorPoint or "TOP" end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.anchorPoint = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["selfPoint"] = {
        type = "select",
        name = L["Self Point"] or "Self Point",
        desc = L["Which point of the bar itself is used for anchoring"] or "Which point of the bar itself is used for anchoring",
        order = 3.325, width = "normal",
        values = {
            TOPLEFT = L["Top Left"] or "Top Left", TOP = L["Top"] or "Top", TOPRIGHT = L["Top Right"] or "Top Right",
            LEFT = L["Left"] or "Left", CENTER = L["Center"] or "Center", RIGHT = L["Right"] or "Right",
            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left", BOTTOM = L["Bottom"] or "Bottom", BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
        },
        get = function() return DDingUI.db.profile.buffTrackerBar.selfPoint or "TOP" end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.selfPoint = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["offsetX"] = {
        type = "range",
        name = L["X Offset"] or "X Offset",
        desc = L["Horizontal offset from anchor point"] or "Horizontal offset from anchor point",
        order = 3.33, width = "normal",
        min = -500, max = 500, step = 1,
        get = function() return DDingUI.db.profile.buffTrackerBar.offsetX or 0 end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.offsetX = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["offsetY"] = {
        type = "range",
        name = L["Y Offset"] or "Y Offset",
        desc = L["Vertical offset from anchor point"] or "Vertical offset from anchor point",
        order = 3.34, width = "normal",
        min = -500, max = 500, step = 1,
        get = function() return DDingUI.db.profile.buffTrackerBar.offsetY or 18 end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.offsetY = val
            DDingUI:UpdateBuffTrackerBar()
            if DDingUI.Movers and DDingUI.Movers.LoadMoverPosition then
                DDingUI.Movers:LoadMoverPosition("DDingUI_BuffTrackerBar")
            end
            MarkSpecDirty()
        end,
    }
    options["frameStrata"] = {
        type = "select",
        name = L["Frame Strata"] or "Frame Strata",
        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar.",
        order = 3.5, width = "normal",
        values = {
            BACKGROUND = "BACKGROUND", LOW = "LOW", MEDIUM = "MEDIUM", HIGH = "HIGH", DIALOG = "DIALOG",
        },
        get = function() return DDingUI.db.profile.buffTrackerBar.frameStrata or "MEDIUM" end,
        set = function(_, val)
            DDingUI.db.profile.buffTrackerBar.frameStrata = val
            DDingUI:UpdateBuffTrackerBar()
        end,
    }

    return options
end

ns.CreateGlobalBuffTrackerSettings = CreateGlobalBuffTrackerSettings
