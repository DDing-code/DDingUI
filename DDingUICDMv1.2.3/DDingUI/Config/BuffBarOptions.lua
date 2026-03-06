local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0", true)
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

-- Note: Uses "Middle" label for CENTER (differs from shared GetAnchorOptions which uses "Center")
local function GetAnchorOptions()
    return {
        TOPLEFT     = L["Top Left"] or "Top Left",
        TOP         = L["Top"] or "Top",
        TOPRIGHT    = L["Top Right"] or "Top Right",
        LEFT        = L["Left"] or "Left",
        CENTER      = L["Middle"] or "Middle",
        RIGHT       = L["Right"] or "Right",
        BOTTOMLEFT  = L["Bottom Left"] or "Bottom Left",
        BOTTOM      = L["Bottom"] or "Bottom",
        BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
    }
end

-- Helper function to refresh BuffBar
local function RefreshBuffBar()
    if DDingUI.RefreshBuffBarCooldownViewer then
        DDingUI:RefreshBuffBarCooldownViewer()
    end
end

-- Build the BuffBar options table
local function BuildBuffBarOptions(order)
    local options = {
        type = "group",
        name = L["Buff Bar"],
        order = order,
        childGroups = "tab",
        args = {
            -- General Settings Tab
            generalTab = {
                type = "group",
                name = L["General"],
                order = 1,
                args = {
                    header = {
                        type = "header",
                        name = L["Buff Bar"] .. " " .. L["Settings"],
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = L["Enable"],
                        desc = L["Show/hide the buff bar viewer"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.buffBarViewer.enabled end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.enabled = val
                            RefreshBuffBar()
                        end,
                    },

                    -- Bar Size Settings
                    sizeHeader = {
                        type = "header",
                        name = L["Bar Size"],
                        order = 10,
                    },
                    width = {
                        type = "range",
                        name = L["Bar Width (0 = Auto Size to Essential Viewer)"],
                        desc = L["0 = auto width based on the attached viewer."],
                        order = 11,
                        width = "full",
                        min = 0, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.buffBarViewer.width or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.width = val
                            RefreshBuffBar()
                        end,
                    },
                    height = {
                        type = "range",
                        name = L["Bar Height"],
                        desc = L["Height of each buff bar in pixels"],
                        order = 12,
                        width = "full",
                        min = 8, max = 64, step = 1,
                        get = function() return DDingUI.db.profile.buffBarViewer.height or 16 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.height = val
                            RefreshBuffBar()
                        end,
                    },
                    growDirection = {
                        type = "select",
                        name = L["Bar Growth Direction"] or "Bar Growth Direction",
                        desc = L["Direction bars grow from the anchor point"] or "앵커 포인트에서 바가 자라는 방향",
                        order = 13,
                        width = "full",
                        values = {
                            BOTTOM = L["Bars Grow from Bottom"] or "Bars Grow from Bottom",
                            TOP = L["Bars Grow from Top"] or "Bars Grow from Top",
                        },
                        get = function() return DDingUI.db.profile.buffBarViewer.growDirection or "BOTTOM" end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.growDirection = val
                            RefreshBuffBar()
                        end,
                    },
                    -- disableDynamicLayout removed: grow direction now always works
                    -- without forcing viewer anchor position

                    -- Width Reference Frame
                    anchorHeader = {
                        type = "header",
                        name = "폭 기준 프레임",
                        order = 14,
                    },
                    anchorDesc = {
                        type = "description",
                        name = "바 너비 자동 계산(너비=0)의 기준이 되는 프레임입니다. 비워두면 Essential 뷰어 기준. 위치는 WoW 편집 모드(EditMode)에서 조절하세요.",
                        order = 14.1,
                    },
                    anchorFrame = {
                        type = "input",
                        name = "기준 프레임",
                        desc = "폭 자동 계산의 기준 프레임 이름 (예: EssentialCooldownViewer)",
                        order = 14.2,
                        width = "double",
                        get = function()
                            return DDingUI.db.profile.buffBarViewer.anchorFrame or ""
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.anchorFrame = val or ""
                            RefreshBuffBar()
                        end,
                    },
                    anchorPick = {
                        type = "execute",
                        name = "프레임 선택 (마우스 클릭)",
                        desc = "화면에서 마우스로 기준 프레임을 직접 선택합니다.",
                        order = 14.3,
                        width = "full",
                        func = function()
                            if DDingUI.StartFramePicker then
                                DDingUI:StartFramePicker(function(frameName)
                                    DDingUI.db.profile.buffBarViewer.anchorFrame = frameName or ""
                                    RefreshBuffBar()
                                end)
                            else
                                print("|cffff8800[DDingUI] 프레임 선택기를 사용할 수 없습니다.|r")
                            end
                        end,
                    },
                    anchorClear = {
                        type = "execute",
                        name = "초기화",
                        desc = "기준 프레임을 제거하고 Essential 뷰어 기준으로 되돌립니다.",
                        order = 14.4,
                        width = "normal",
                        func = function()
                            DDingUI.db.profile.buffBarViewer.anchorFrame = ""
                            RefreshBuffBar()
                        end,
                    },

                    -- Bar Appearance Settings
                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"],
                        order = 20,
                    },
                    texture = {
                        type = "select",
                        name = L["Bar Texture"],
                        desc = L["Texture used for the bar fill"],
                        order = 21,
                        width = "full",
                        dialogControl = "LSM30_Statusbar",
                        values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar or {},
                        get = function()
                            return DDingUI.db.profile.buffBarViewer.texture or (DDingUI.db.profile.general.globalTexture or "Meli")
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.texture = val
                            RefreshBuffBar()
                        end,
                    },
                    barColor = {
                        type = "color",
                        name = L["Default Bar Color"],
                        desc = L["Default color for buff bars (can be overridden per-bar)"],
                        order = 22,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.buffBarViewer.barColor or {0.9, 0.9, 0.9, 1}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.buffBarViewer.barColor = {r, g, b, a or 1}
                            RefreshBuffBar()
                        end,
                    },
                    bgColor = {
                        type = "color",
                        name = L["Background Color"],
                        desc = L["Background color of the bar"],
                        order = 23,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.buffBarViewer.bgColor or {0.15, 0.15, 0.15, 1}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.buffBarViewer.bgColor = {r, g, b, a or 1}
                            RefreshBuffBar()
                        end,
                    },

                    -- Border Settings
                    borderHeader = {
                        type = "header",
                        name = L["Borders"],
                        order = 30,
                    },
                    borderSize = {
                        type = "range",
                        name = L["Border Size"],
                        desc = L["Border thickness (0 = no border)"],
                        order = 31,
                        width = "full",
                        min = 0, max = 5, step = 1,
                        get = function() return DDingUI.db.profile.buffBarViewer.borderSize or 1 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.borderSize = val
                            RefreshBuffBar()
                        end,
                    },
                    borderColor = {
                        type = "color",
                        name = L["Border Color"],
                        desc = L["Color of the bar border"],
                        order = 32,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.buffBarViewer.borderColor or {0, 0, 0, 1}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.buffBarViewer.borderColor = {r, g, b, a or 1}
                            RefreshBuffBar()
                        end,
                    },
                },
            },

            -- Icon Settings Tab
            iconTab = {
                type = "group",
                name = L["Icon"],
                order = 2,
                args = {
                    iconHeader = {
                        type = "header",
                        name = L["Icon Settings"],
                        order = 1,
                    },
                    hideIcon = {
                        type = "toggle",
                        name = L["Hide Icon"],
                        desc = L["Hide the buff icon, show only the bar"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.buffBarViewer.hideIcon or false end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.hideIcon = val
                            RefreshBuffBar()
                        end,
                    },
                    hideIconMask = {
                        type = "toggle",
                        name = L["Remove Icon Mask"],
                        desc = L["Remove the circular mask from icons (makes them square)"],
                        width = "full",
                        order = 3,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.hideIcon end,
                        get = function() return DDingUI.db.profile.buffBarViewer.hideIconMask ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.hideIconMask = val
                            RefreshBuffBar()
                        end,
                    },
                    iconZoom = {
                        type = "range",
                        name = L["Icon Zoom"],
                        desc = L["Crops the edges of the icon (higher = more zoom)"],
                        order = 4,
                        width = "full",
                        min = 0, max = 0.45, step = 0.01,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.hideIcon end,
                        get = function() return DDingUI.db.profile.buffBarViewer.iconZoom or 0.08 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.iconZoom = val
                            RefreshBuffBar()
                        end,
                    },

                    -- Icon Border Settings
                    iconBorderHeader = {
                        type = "header",
                        name = L["Icon Border"],
                        order = 10,
                    },
                    iconBorderSize = {
                        type = "range",
                        name = L["Icon Border Size"],
                        desc = L["Border thickness around the icon (0 = no border)"],
                        order = 11,
                        width = "full",
                        min = 0, max = 5, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.hideIcon end,
                        get = function() return DDingUI.db.profile.buffBarViewer.iconBorderSize or 1 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.iconBorderSize = val
                            RefreshBuffBar()
                        end,
                    },
                    iconBorderColor = {
                        type = "color",
                        name = L["Icon Border Color"],
                        desc = L["Color of the icon border"],
                        order = 12,
                        width = "normal",
                        hasAlpha = true,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.hideIcon end,
                        get = function()
                            local c = DDingUI.db.profile.buffBarViewer.iconBorderColor or {0, 0, 0, 1}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.buffBarViewer.iconBorderColor = {r, g, b, a or 1}
                            RefreshBuffBar()
                        end,
                    },
                },
            },

            -- Name Text Settings Tab
            nameTab = {
                type = "group",
                name = L["Name Text"],
                order = 3,
                args = {
                    nameHeader = {
                        type = "header",
                        name = L["Name Text Settings"],
                        order = 1,
                    },
                    showName = {
                        type = "toggle",
                        name = L["Show Name"],
                        desc = L["Display the buff/spell name on the bar"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.buffBarViewer.showName ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.showName = val
                            RefreshBuffBar()
                        end,
                    },
                    nameFont = {
                        type = "select",
                        name = L["Name Font"],
                        desc = L["Font for the buff name"],
                        order = 2.5,
                        width = "full",
                        dialogControl = "LSM30_Font",
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showName == false end,
                        values = function() return DDingUI:GetFontValues() end,
                        get = function() return DDingUI.db.profile.buffBarViewer.nameFont or DDingUI.DEFAULT_FONT_NAME end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.nameFont = val
                            RefreshBuffBar()
                        end,
                    },
                    nameSize = {
                        type = "range",
                        name = L["Name Font Size"],
                        desc = L["Font size for the buff name"],
                        order = 3,
                        width = "full",
                        min = 8, max = 32, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showName == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.nameSize or 14 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.nameSize = val
                            RefreshBuffBar()
                        end,
                    },
                    nameColor = {
                        type = "color",
                        name = L["Name Color"],
                        desc = L["Color for the buff name text"],
                        order = 4,
                        width = "normal",
                        hasAlpha = true,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showName == false end,
                        get = function()
                            local c = DDingUI.db.profile.buffBarViewer.nameColor or {1, 1, 1, 1}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.buffBarViewer.nameColor = {r, g, b, a or 1}
                            RefreshBuffBar()
                        end,
                    },
                    nameAnchor = {
                        type = "select",
                        name = L["Name Anchor"],
                        desc = L["Where to anchor the name text on the bar"],
                        order = 5,
                        width = "normal",
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showName == false end,
                        values = GetAnchorOptions(),
                        get = function() return DDingUI.db.profile.buffBarViewer.nameAnchor or "LEFT" end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.nameAnchor = val
                            RefreshBuffBar()
                        end,
                    },
                    nameOffsetX = {
                        type = "range",
                        name = L["Name X Offset"],
                        desc = L["Horizontal offset for the name text"],
                        order = 6,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showName == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.nameOffsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.nameOffsetX = val
                            RefreshBuffBar()
                        end,
                    },
                    nameOffsetY = {
                        type = "range",
                        name = L["Name Y Offset"],
                        desc = L["Vertical offset for the name text"],
                        order = 7,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showName == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.nameOffsetY or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.nameOffsetY = val
                            RefreshBuffBar()
                        end,
                    },
                },
            },

            -- Duration Text Settings Tab
            durationTab = {
                type = "group",
                name = L["Duration Text"],
                order = 4,
                args = {
                    durationHeader = {
                        type = "header",
                        name = L["Duration Text Settings"],
                        order = 1,
                    },
                    showDuration = {
                        type = "toggle",
                        name = L["Show Duration"],
                        desc = L["Display the remaining duration on the bar"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.buffBarViewer.showDuration ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.showDuration = val
                            RefreshBuffBar()
                        end,
                    },
                    durationFont = {
                        type = "select",
                        name = L["Duration Font"],
                        desc = L["Font for the duration text"],
                        order = 2.5,
                        width = "full",
                        dialogControl = "LSM30_Font",
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showDuration == false end,
                        values = function() return DDingUI:GetFontValues() end,
                        get = function() return DDingUI.db.profile.buffBarViewer.durationFont or DDingUI.DEFAULT_FONT_NAME end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.durationFont = val
                            RefreshBuffBar()
                        end,
                    },
                    durationSize = {
                        type = "range",
                        name = L["Duration Font Size"],
                        desc = L["Font size for the duration text"],
                        order = 3,
                        width = "full",
                        min = 8, max = 32, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showDuration == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.durationSize or 12 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.durationSize = val
                            RefreshBuffBar()
                        end,
                    },
                    durationColor = {
                        type = "color",
                        name = L["Duration Color"],
                        desc = L["Color for the duration text"],
                        order = 4,
                        width = "normal",
                        hasAlpha = true,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showDuration == false end,
                        get = function()
                            local c = DDingUI.db.profile.buffBarViewer.durationColor or {1, 1, 1, 1}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.buffBarViewer.durationColor = {r, g, b, a or 1}
                            RefreshBuffBar()
                        end,
                    },
                    durationAnchor = {
                        type = "select",
                        name = L["Duration Anchor"],
                        desc = L["Where to anchor the duration text on the bar"],
                        order = 5,
                        width = "normal",
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showDuration == false end,
                        values = GetAnchorOptions(),
                        get = function() return DDingUI.db.profile.buffBarViewer.durationAnchor or "RIGHT" end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.durationAnchor = val
                            RefreshBuffBar()
                        end,
                    },
                    durationOffsetX = {
                        type = "range",
                        name = L["Duration X Offset"],
                        desc = L["Horizontal offset for the duration text"],
                        order = 6,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showDuration == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.durationOffsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.durationOffsetX = val
                            RefreshBuffBar()
                        end,
                    },
                    durationOffsetY = {
                        type = "range",
                        name = L["Duration Y Offset"],
                        desc = L["Vertical offset for the duration text"],
                        order = 7,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showDuration == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.durationOffsetY or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.durationOffsetY = val
                            RefreshBuffBar()
                        end,
                    },
                },
            },

            -- Stack/Applications Text Settings Tab
            stackTab = {
                type = "group",
                name = L["Stack Text"],
                order = 5,
                args = {
                    stackHeader = {
                        type = "header",
                        name = L["Stack/Applications Text Settings"],
                        order = 1,
                    },
                    showApplications = {
                        type = "toggle",
                        name = L["Show Stacks"],
                        desc = L["Display the buff stack count"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.buffBarViewer.showApplications ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.showApplications = val
                            RefreshBuffBar()
                        end,
                    },
                    applicationsFont = {
                        type = "select",
                        name = L["Stack Font"],
                        desc = L["Font for the stack count text"],
                        order = 2.5,
                        width = "full",
                        dialogControl = "LSM30_Font",
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showApplications == false end,
                        values = function() return DDingUI:GetFontValues() end,
                        get = function() return DDingUI.db.profile.buffBarViewer.applicationsFont or DDingUI.DEFAULT_FONT_NAME end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.applicationsFont = val
                            RefreshBuffBar()
                        end,
                    },
                    applicationsSize = {
                        type = "range",
                        name = L["Stack Font Size"],
                        desc = L["Font size for the stack count text"],
                        order = 3,
                        width = "full",
                        min = 8, max = 32, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showApplications == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.applicationsSize or 12 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.applicationsSize = val
                            RefreshBuffBar()
                        end,
                    },
                    applicationsColor = {
                        type = "color",
                        name = L["Stack Color"],
                        desc = L["Color for the stack count text"],
                        order = 4,
                        width = "normal",
                        hasAlpha = true,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showApplications == false end,
                        get = function()
                            local c = DDingUI.db.profile.buffBarViewer.applicationsColor or {1, 1, 1, 1}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.buffBarViewer.applicationsColor = {r, g, b, a or 1}
                            RefreshBuffBar()
                        end,
                    },
                    applicationsAnchor = {
                        type = "select",
                        name = L["Stack Anchor"],
                        desc = L["Where to anchor the stack text (relative to icon or bar if icon is hidden)"],
                        order = 5,
                        width = "normal",
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showApplications == false end,
                        values = GetAnchorOptions(),
                        get = function() return DDingUI.db.profile.buffBarViewer.applicationsAnchor or "BOTTOMRIGHT" end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.applicationsAnchor = val
                            RefreshBuffBar()
                        end,
                    },
                    applicationsOffsetX = {
                        type = "range",
                        name = L["Stack X Offset"],
                        desc = L["Horizontal offset for the stack text"],
                        order = 6,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showApplications == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.applicationsOffsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.applicationsOffsetX = val
                            RefreshBuffBar()
                        end,
                    },
                    applicationsOffsetY = {
                        type = "range",
                        name = L["Stack Y Offset"],
                        desc = L["Vertical offset for the stack text"],
                        order = 7,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        disabled = function() return DDingUI.db.profile.buffBarViewer.showApplications == false end,
                        get = function() return DDingUI.db.profile.buffBarViewer.applicationsOffsetY or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.buffBarViewer.applicationsOffsetY = val
                            RefreshBuffBar()
                        end,
                    },
                },
            },

            -- Per-Spec Colors Tab
            colorsTab = {
                type = "group",
                name = L["Per-Spec Colors"],
                order = 6,
                args = {
                    colorsHeader = {
                        type = "header",
                        name = L["Per-Specialization Bar Colors"],
                        order = 1,
                    },
                    colorsDesc = {
                        type = "description",
                        name = L["Set different bar colors for each specialization. These are saved per-spec automatically when you change the color in Blizzard's Cooldown Viewer Settings."],
                        order = 2,
                    },
                    resetColors = {
                        type = "execute",
                        name = L["Reset All Colors"],
                        desc = L["Reset all per-spec and per-bar colors to the default"],
                        order = 3,
                        width = "full",
                        confirm = true,
                        confirmText = L["Are you sure you want to reset all bar colors?"],
                        func = function()
                            DDingUI.db.profile.buffBarViewer.barColors = {}
                            DDingUI.db.profile.buffBarViewer.barColorsBySpec = {}
                            RefreshBuffBar()
                        end,
                    },
                },
            },
        },
    }

    return options
end

-- Export function
ns.CreateBuffBarOptions = BuildBuffBarOptions
