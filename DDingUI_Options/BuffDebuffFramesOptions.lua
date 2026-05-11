local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local LSM = LibStub("LibSharedMedia-3.0")

-- Helper function to get anchor point options (all 8 points)
local function GetAnchorPointOptions()
    return {
        TOPLEFT = L["Top Left"],
        TOP = L["Top"],
        TOPRIGHT = L["Top Right"],
        LEFT = L["Left"],
        CENTER = L["Middle"],
        RIGHT = L["Right"],
        BOTTOMLEFT = L["Bottom Left"],
        BOTTOM = L["Bottom"],
        BOTTOMRIGHT = L["Bottom Right"],
    }
end


-- Create options for a specific type (buffs or debuffs)
local function CreateTypeOptions(typeKey, displayName, order)
    local db = DDingUI.db.profile.buffDebuffFrames
    if not db then return {} end

    local isBuffs = typeKey == "buffs"
    local headerText = isBuffs and L["Buffs Settings"] or L["Debuffs Settings"]
    local enableText = isBuffs and L["Enable Buffs Frame Styling"] or L["Enable Debuffs Frame Styling"]
    local enableDesc = isBuffs and L["Apply custom DDingUI styling to buffs frames"] or L["Apply custom DDingUI styling to debuffs frames"]
    local iconSizeDesc = isBuffs and L["Size of buffs icons in pixels"] or L["Size of debuffs icons in pixels"]

    return {
        type = "group",
        name = displayName,
        order = order,
        args = {
            header = {
                type = "header",
                name = headerText,
                order = 1,
            },
            enabled = {
                type = "toggle",
                name = enableText,
                desc = enableDesc,
                width = "full",
                order = 2,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return false end
                    if not db.enabled then return false end
                    if not db[typeKey] then return true end
                    return db[typeKey].enabled ~= false
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then
                        DDingUI.db.profile.buffDebuffFrames = {}
                        db = DDingUI.db.profile.buffDebuffFrames
                    end
                    if not db.enabled then db.enabled = true end
                    if not db[typeKey] then db[typeKey] = {} end
                    db[typeKey].enabled = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            spacer0 = {
                type = "description",
                name = " ",
                order = 3,
            },
            iconSizeHeader = {
                type = "header",
                name = L["Icon Size"],
                order = 10,
            },
            iconSize = {
                type = "range",
                name = L["Icon Size (use this to also adjust spacing)"],
                desc = iconSizeDesc,
                order = 11,
                width = "full",
                min = 16,
                max = 96,
                step = 1,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 36 end
                    return db[typeKey].iconSize or 36
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    db[typeKey].iconSize = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 12,
            },
            countHeader = {
                type = "header",
                name = L["Stack Count Text"],
                order = 19,
            },
            countEnabled = {
                type = "toggle",
                name = L["Enable Stack Count Text"],
                desc = L["Show/hide stack count text"],
                width = "full",
                order = 21,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return true end
                    local textConfig = db[typeKey].count or {}
                    return textConfig.enabled ~= false
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].count then db[typeKey].count = {} end
                    db[typeKey].count.enabled = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            countFont = {
                type = "select",
                name = L["Stack Count Font"],
                desc = L["Font for stack count text"],
                order = 21.5,
                width = "full",
                dialogControl = "LSM30_Font",
                values = function() return DDingUI:GetFontValues() end,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] or not db[typeKey].count then return DDingUI.DEFAULT_FONT_NAME end
                    return db[typeKey].count.font or DDingUI.DEFAULT_FONT_NAME
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].count then db[typeKey].count = {} end
                    db[typeKey].count.font = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            countFontSize = {
                type = "range",
                name = L["Stack Count Font Size"],
                desc = L["Font size for stack count text"],
                order = 22,
                width = "full",
                min = 6,
                max = 32,
                step = 1,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 12 end
                    local textConfig = db[typeKey].count or {}
                    return textConfig.fontSize or 12
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].count then db[typeKey].count = {} end
                    db[typeKey].count.fontSize = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            countAnchorPoint = {
                type = "select",
                name = L["Stack Count Anchor Point"],
                desc = L["Where to anchor stack count text relative to icon"],
                order = 23,
                width = "full",
                values = GetAnchorPointOptions(),
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return "TOPRIGHT" end
                    local textConfig = db[typeKey].count or {}
                    return textConfig.anchorPoint or "TOPRIGHT"
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].count then db[typeKey].count = {} end
                    db[typeKey].count.anchorPoint = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            countOffsetX = {
                type = "range",
                name = L["Stack Count X Offset"],
                desc = L["Horizontal offset for stack count text"],
                order = 24,
                width = "full",
                min = -50,
                max = 50,
                step = 1,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 0 end
                    local textConfig = db[typeKey].count or {}
                    return textConfig.offsetX or 0
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].count then db[typeKey].count = {} end
                    db[typeKey].count.offsetX = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            countOffsetY = {
                type = "range",
                name = L["Stack Count Y Offset"],
                desc = L["Vertical offset for stack count text"],
                order = 25,
                width = "full",
                min = -50,
                max = 50,
                step = 1,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 0 end
                    local textConfig = db[typeKey].count or {}
                    return textConfig.offsetY or 0
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].count then db[typeKey].count = {} end
                    db[typeKey].count.offsetY = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            countTextColor = {
                type = "color",
                name = L["Stack Count Text Color"],
                desc = L["Color for stack count text"],
                order = 26,
                width = "full",
                hasAlpha = true,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 1, 1, 1, 1 end
                    local textConfig = db[typeKey].count or {}
                    local color = textConfig.textColor or {1, 1, 1, 1}
                    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
                end,
                set = function(_, r, g, b, a)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].count then db[typeKey].count = {} end
                    db[typeKey].count.textColor = {r, g, b, a or 1}
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            spacer3 = {
                type = "description",
                name = " ",
                order = 27,
            },
            durationHeader = {
                type = "header",
                name = L["Duration Text"],
                order = 30,
            },
            durationEnabled = {
                type = "toggle",
                name = L["Enable Duration Text"],
                desc = L["Show/hide duration/cooldown text"],
                width = "full",
                order = 31,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return true end
                    local textConfig = db[typeKey].duration or {}
                    return textConfig.enabled ~= false
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].duration then db[typeKey].duration = {} end
                    db[typeKey].duration.enabled = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            durationFont = {
                type = "select",
                name = L["Duration Font"],
                desc = L["Font for duration text"],
                order = 31.5,
                width = "full",
                dialogControl = "LSM30_Font",
                values = function() return DDingUI:GetFontValues() end,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] or not db[typeKey].duration then return DDingUI.DEFAULT_FONT_NAME end
                    return db[typeKey].duration.font or DDingUI.DEFAULT_FONT_NAME
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].duration then db[typeKey].duration = {} end
                    db[typeKey].duration.font = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            durationFontSize = {
                type = "range",
                name = L["Duration Font Size"],
                desc = L["Font size for duration text"],
                order = 32,
                width = "full",
                min = 6,
                max = 32,
                step = 1,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 12 end
                    local textConfig = db[typeKey].duration or {}
                    return textConfig.fontSize or 12
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].duration then db[typeKey].duration = {} end
                    db[typeKey].duration.fontSize = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            durationAnchorPoint = {
                type = "select",
                name = L["Duration Anchor Point"],
                desc = L["Where to anchor duration text relative to icon"],
                order = 33,
                width = "full",
                values = GetAnchorPointOptions(),
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return "CENTER" end
                    local textConfig = db[typeKey].duration or {}
                    return textConfig.anchorPoint or "CENTER"
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].duration then db[typeKey].duration = {} end
                    db[typeKey].duration.anchorPoint = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            durationOffsetX = {
                type = "range",
                name = L["Duration X Offset"],
                desc = L["Horizontal offset for duration text"],
                order = 34,
                width = "full",
                min = -50,
                max = 50,
                step = 1,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 0 end
                    local textConfig = db[typeKey].duration or {}
                    return textConfig.offsetX or 0
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].duration then db[typeKey].duration = {} end
                    db[typeKey].duration.offsetX = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            durationOffsetY = {
                type = "range",
                name = L["Duration Y Offset"],
                desc = L["Vertical offset for duration text"],
                order = 35,
                width = "full",
                min = -50,
                max = 50,
                step = 1,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 0 end
                    local textConfig = db[typeKey].duration or {}
                    return textConfig.offsetY or 0
                end,
                set = function(_, val)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].duration then db[typeKey].duration = {} end
                    db[typeKey].duration.offsetY = val
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
            durationTextColor = {
                type = "color",
                name = L["Duration Text Color"],
                desc = L["Color for duration text"],
                order = 36,
                width = "full",
                hasAlpha = true,
                get = function()
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db or not db[typeKey] then return 1, 1, 1, 1 end
                    local textConfig = db[typeKey].duration or {}
                    local color = textConfig.textColor or {1, 1, 1, 1}
                    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
                end,
                set = function(_, r, g, b, a)
                    local db = DDingUI.db.profile.buffDebuffFrames
                    if not db then return end
                    if not db[typeKey] then db[typeKey] = {} end
                    if not db[typeKey].duration then db[typeKey].duration = {} end
                    db[typeKey].duration.textColor = {r, g, b, a or 1}
                    if DDingUI.BuffDebuffFrames and DDingUI.BuffDebuffFrames.RefreshAll then
                        DDingUI.BuffDebuffFrames:RefreshAll()
                    end
                end,
            },
        },
    }
end

local function CreateBuffDebuffFramesOptions(order)
    return {
        type = "group",
        name = L["Buff/Debuffs"],
        order = order or 6,
        childGroups = "tab",
        args = {
            buffs = CreateTypeOptions("buffs", L["Buffs"], 1),
            debuffs = CreateTypeOptions("debuffs", L["Debuffs"], 2),
        },
    }
end

ns.CreateBuffDebuffFramesOptions = CreateBuffDebuffFramesOptions
