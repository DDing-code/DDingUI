local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

-- Use shared helper from ConfigHelpers (with fallback)
local function GetViewerOptions()
    if DDingUI.GetViewerOptions then
        return DDingUI:GetViewerOptions()
    end
    -- Fallback: 프록시 앵커 프레임 우선
    return {
        ["DDingUI_Anchor_Cooldowns"] = L["Essential Cooldowns"] or "핵심 능력",
        ["DDingUI_Anchor_Buffs"] = L["Buff Icons"] or "강화 효과",
        ["DDingUI_Anchor_Utility"] = L["Utility Cooldowns"] or "보조 능력",
    }
end

local function CreateCastBarOptions()
    return {
        type = "group",
        name = L["Player Cast Bar"] or "플레이어 시전바",
        order = 5,
        args = {
                    header = {
                        type = "header",
                        name = L["Player Cast Bar Settings"],
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = L["Enable Cast Bar"],
                        desc = L["Show a bar when casting or channeling spells"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.castBar.enabled end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.enabled = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    testCast = {
                        type  = "execute",
                        name  = L["Test Cast Bar"],
                        desc  = L["Show a fake cast so you can preview and tweak the bar without casting."],
                        order = 3,
                        func  = function()
                            DDingUI:ShowTestCastBar()
                        end,
                    },
                    positionHeader = {
                        type = "header",
                        name = L["Position & Size"],
                        order = 10,
                    },
                    attachTo = {
                        type = "select",
                        name = L["Attach To"],
                        desc = L["Which frame to attach this bar to"],
                        order = 11,
                        width = "double",
                        values = function()
                            local opts = {}
                            if DDingUI.db.profile.unitFrames and DDingUI.db.profile.unitFrames.enabled then
                                opts["DDingUI_Player"] = L["Player Frame (Custom)"]
                            end
                            local viewerOpts = GetViewerOptions()
                            for k, v in pairs(viewerOpts) do
                                opts[k] = v
                            end
                            opts["UIParent"] = L["Screen Center"]
                            -- 현재 커스텀 값이 목록에 없으면 추가
                            local current = DDingUI.db.profile.castBar.attachTo
                            if current and not opts[current] then
                                opts[current] = current .. " (Custom)"
                            end
                            return opts
                        end,
                        get = function() return DDingUI.db.profile.castBar.attachTo end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.attachTo = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    pickFrame = {
                        type = "execute",
                        name = L["Pick Frame"] or "프레임 선택",
                        desc = L["Click to select a frame from the UI"] or "UI에서 프레임을 클릭하여 선택",
                        order = 11.5,
                        width = "half",
                        func = function()
                            DDingUI:StartFramePicker(function(frameName)
                                if frameName then
                                    DDingUI.db.profile.castBar.attachTo = frameName
                                    DDingUI:UpdateCastBarLayout()
                                end
                            end)
                        end,
                    },
                    anchorPoint = {
                        type = "select",
                        name = L["Anchor Point"],
                        desc = L["Which point of the attached frame to anchor to (moves with frame when it resizes)"],
                        order = 12,
                        width = "full",
                        values = {
                            ["TOPLEFT"] = L["Top Left"],
                            ["TOP"] = L["Top"],
                            ["TOPRIGHT"] = L["Top Right"],
                            ["LEFT"] = L["Left"],
                            ["CENTER"] = L["Center"],
                            ["RIGHT"] = L["Right"],
                            ["BOTTOMLEFT"] = L["Bottom Left"],
                            ["BOTTOM"] = L["Bottom"],
                            ["BOTTOMRIGHT"] = L["Bottom Right"],
                        },
                        get = function() return DDingUI.db.profile.castBar.anchorPoint or "CENTER" end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.anchorPoint = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    selfPoint = {
                        type = "select",
                        name = L["Self Anchor"] or "기준점",
                        desc = L["Which point of this bar to use as the anchor reference"] or "이 바의 어느 지점을 기준으로 위치를 잡을지",
                        order = 12.05,
                        width = "normal",
                        values = {
                            TOPLEFT = L["Top Left"],
                            TOP = L["Top"],
                            TOPRIGHT = L["Top Right"],
                            LEFT = L["Left"],
                            CENTER = L["Center"],
                            RIGHT = L["Right"],
                            BOTTOMLEFT = L["Bottom Left"],
                            BOTTOM = L["Bottom"],
                            BOTTOMRIGHT = L["Bottom Right"],
                        },
                        get = function() return DDingUI.db.profile.castBar.selfPoint or "CENTER" end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.selfPoint = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    frameStrata = {
                        type = "select",
                        name = L["Frame Strata"] or "Frame Strata",
                        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar. Higher strata appear on top of lower ones.",
                        order = 12.1,
                        width = "normal",
                        values = {
                            BACKGROUND = "BACKGROUND",
                            LOW = "LOW",
                            MEDIUM = "MEDIUM",
                            HIGH = "HIGH",
                            DIALOG = "DIALOG",
                        },
                        get = function() return DDingUI.db.profile.castBar.frameStrata or "MEDIUM" end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.frameStrata = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    height = {
                        type = "range",
                        name = L["Height"],
                        order = 12,
                        width = "normal",
                        min = 6, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.castBar.height end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.height = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    width = {
                        type = "range",
                        name = L["Width"],
                        desc = L["0 = automatic width based on icons"],
                        order = 13,
                        width = "normal",
                        min = 0, max = 1000, step = 1,
                        get = function() return DDingUI.db.profile.castBar.width end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.width = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    offsetY = {
                        type = "range",
                        name = L["Vertical Offset"],
                        desc = L["Distance from the icon viewer"],
                        order = 14,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.castBar.offsetY end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.offsetY = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    offsetX = {
                        type = "range",
                        name = L["Horizontal Offset"],
                        desc = L["Horizontal distance from the anchor point"],
                        order = 15,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.castBar.offsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.offsetX = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },

                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"],
                        order = 20,
                    },
                    showSpark = {
                        type = "toggle",
                        name = L["Show Spark"] or "스파크 표시",
                        desc = L["Show a spark effect at the end of the cast bar"] or "시전바 끝부분에 세로로 긴 반짝임 효과를 표시합니다",
                        order = 20.5,
                        width = "normal",
                        get = function() return DDingUI.db.profile.castBar.showSpark end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.showSpark = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    texture = {
                        type = "select",
                        name = L["Texture"],
                        order = 21,
                        width = "full",
                        values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar or {},
                        get = function() 
                            local override = DDingUI.db.profile.castBar.texture
                            if override and override ~= "" then
                                return override
                            end
                            -- Return global texture name when override is nil
                            return DDingUI.db.profile.general.globalTexture or "Meli"
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.texture = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    useClassColor = {
                        type = "toggle",
                        name = L["Use Class Color"],
                        desc = L["Use your class color instead of custom color"],
                        order = 22,
                        width = "normal",
                        get = function() return DDingUI.db.profile.castBar.useClassColor end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.useClassColor = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    barColor = {
                        type = "color",
                        name = L["Custom Color"],
                        desc = L["Used when class color is disabled"],
                    order = 23,
                    width = "normal",
                    hasAlpha = true,
                    get = function()
                            local c = DDingUI.db.profile.castBar.color
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1, 0.7, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.castBar.color = { r, g, b, a }
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    bgColor = {
                        type = "color",
                        name = L["Background Color"],
                        desc = L["Color of the bar background"],
                        order = 24,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.castBar.bgColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.1, 0.1, 0.1, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.castBar.bgColor = { r, g, b, a }
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    interruptedColor = {
                        type = "color",
                        name = L["Interrupted Color"] or "중단 색상",
                        desc = L["Color briefly used when the cast is interrupted"] or "시전이 중단될 때 잠시 사용되는 색상",
                        order = 24.1,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.castBar.interruptedColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.9, 0.2, 0.2, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.castBar.interruptedColor = { r, g, b, a }
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    interruptedFadeEnabled = {
                        type = "toggle",
                        name = L["Interrupted Fade Effect"] or "시전 중단 페이드 효과",
                        desc = L["Show a fade-out animation when cast is interrupted"] or "시전이 끊겼을 때 페이드아웃 효과 표시",
                        order = 24.2,
                        width = "normal",
                        get = function() return DDingUI.db.profile.castBar.interruptedFadeEnabled ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.interruptedFadeEnabled = val
                        end,
                    },
                    interruptedFadeDuration = {
                        type = "range",
                        name = L["Fade Duration"] or "페이드 시간",
                        desc = L["Duration of the fade-out effect in seconds"] or "페이드아웃 효과 지속 시간 (초)",
                        order = 24.3,
                        width = "normal",
                        min = 0.1, max = 2.0, step = 0.1,
                        get = function() return DDingUI.db.profile.castBar.interruptedFadeDuration or 0.5 end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.interruptedFadeDuration = val
                        end,
                    },
                    textHeader = {
                        type = "header",
                        name = L["Text Settings"] or "텍스트 설정",
                        order = 24.4,
                    },
                    showSpellText = {
                        type = "toggle",
                        name = L["Show Spell Name"] or "스킬 이름 표시",
                        desc = L["Show the name of the spell being cast"] or "시전 중인 스킬 이름 표시",
                        order = 24.5,
                        width = "normal",
                        get = function() return DDingUI.db.profile.castBar.showSpellText ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.showSpellText = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    spellTextFont = {
                        type = "select",
                        name = L["Spell Font"] or "스킬 폰트",
                        desc = L["Font used for the spell name"] or "스킬 이름에 사용될 폰트",
                        order = 24.6,
                        width = "normal",
                        dialogControl = "LSM30_Font",
                        values = function() return DDingUI:GetFontValues() end,
                        get = function()
                            return DDingUI.db.profile.castBar.spellTextFont or DDingUI.db.profile.castBar.textFont or DDingUI.DEFAULT_FONT_NAME
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.spellTextFont = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    spellTextSize = {
                        type = "range",
                        name = L["Spell Text Size"] or "스킬 이름 크기",
                        order = 24.7,
                        width = "normal",
                        min = 6, max = 30, step = 1,
                        get = function() return DDingUI.db.profile.castBar.spellTextSize or DDingUI.db.profile.castBar.textSize or 10 end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.spellTextSize = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    spellTextOffsetX = {
                        type = "range",
                        name = L["Spell Text X"] or "스킬 이름 가로 오프셋",
                        order = 24.8,
                        width = "normal",
                        min = -100, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.castBar.spellTextOffsetX or 4 end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.spellTextOffsetX = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    spellTextOffsetY = {
                        type = "range",
                        name = L["Spell Text Y"] or "스킬 이름 세로 오프셋",
                        order = 24.9,
                        width = "normal",
                        min = -100, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.castBar.spellTextOffsetY or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.spellTextOffsetY = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    blankText1 = {
                        type = "description",
                        name = " ",
                        order = 25.0,
                        width = "full",
                    },
                    showTimeText = {
                        type = "toggle",
                        name = L["Show Time Text"] or "시간 분수 표시",
                        desc = L["Show the remaining cast time on the cast bar"],
                        order = 25.1,
                        width = "normal",
                        get = function() return DDingUI.db.profile.castBar.showTimeText ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.showTimeText = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    timeTextFormat = {
                        type = "select",
                        name = L["Time Text Format"],
                        desc = L["Choose how the cast time is displayed"],
                        order = 25.2,
                        width = "normal",
                        values = {
                            ["current/total"] = "1.5/3.0 (경과/총)",
                            ["remaining/total"] = "1.5/3.0 (남은/총)",
                            ["remaining"] = "1.5 (남은 시간만)",
                        },
                        get = function() return DDingUI.db.profile.castBar.timeTextFormat or "current/total" end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.timeTextFormat = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    timeTextFont = {
                        type = "select",
                        name = L["Time Font"] or "시간 폰트",
                        desc = L["Font used for the time text"] or "시간 표시에 사용될 폰트",
                        order = 25.3,
                        width = "normal",
                        dialogControl = "LSM30_Font",
                        values = function() return DDingUI:GetFontValues() end,
                        get = function()
                            return DDingUI.db.profile.castBar.timeTextFont or DDingUI.db.profile.castBar.textFont or DDingUI.DEFAULT_FONT_NAME
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.timeTextFont = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    timeTextSize = {
                        type = "range",
                        name = L["Time Text Size"] or "시간 텍스트 크기",
                        order = 25.4,
                        width = "normal",
                        min = 6, max = 30, step = 1,
                        get = function() return DDingUI.db.profile.castBar.timeTextSize or DDingUI.db.profile.castBar.textSize or 10 end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.timeTextSize = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    timeTextOffsetX = {
                        type = "range",
                        name = L["Time Text X"] or "시간 가로 오프셋",
                        order = 25.5,
                        width = "normal",
                        min = -100, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.castBar.timeTextOffsetX or -4 end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.timeTextOffsetX = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    timeTextOffsetY = {
                        type = "range",
                        name = L["Time Text Y"] or "시간 세로 오프셋",
                        order = 25.6,
                        width = "normal",
                        min = -100, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.castBar.timeTextOffsetY or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.timeTextOffsetY = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    showIcon = {
                        type = "toggle",
                        name = L["Show Cast Icon"],
                        desc = L["Hide the spell icon if you prefer a bar-only look"],
                        order = 27,
                        width = "normal",
                        get = function() return DDingUI.db.profile.castBar.showIcon ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.showIcon = val
                            DDingUI:UpdateCastBarLayout()
                        end,
                    },
                    empoweredHeader = {
                        type = "header",
                        name = L["Empowered Cast Settings"],
                        order = 28,
                    },
                    showEmpoweredTicks = {
                        type = "toggle",
                        name = L["Show Empowered Cast Ticks"],
                        desc = L["Show tick marks on empowered casts to indicate stage boundaries"],
                        order = 29,
                        width = "normal",
                        get = function() 
                            local val = DDingUI.db.profile.castBar.showEmpoweredTicks
                            return val ~= false  -- Default to true if nil
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.showEmpoweredTicks = val
                            -- Reinitialize empowered stages if currently showing an empowered cast
                            if DDingUI.castBar and DDingUI.castBar.isEmpowered and DDingUI.castBar.numStages and DDingUI.castBar.numStages > 0 then
                                if DDingUI.CastBars and DDingUI.CastBars.InitializeEmpoweredStages then
                                    -- Force reinitialize to apply the setting change
                                    C_Timer.After(0.01, function()
                                        if DDingUI.castBar and DDingUI.castBar.isEmpowered then
                                            DDingUI.CastBars:InitializeEmpoweredStages(DDingUI.castBar)
                                        end
                                    end)
                                end
                            end
                        end,
                    },
                    showEmpoweredStageColors = {
                        type = "toggle",
                        name = L["Show Empowered Stage Colors"],
                        desc = L["Show colored backgrounds and foregrounds for each stage. Disable to only show ticks."],
                        order = 29.5,
                        width = "normal",
                        get = function() 
                            local val = DDingUI.db.profile.castBar.showEmpoweredStageColors
                            return val ~= false  -- Default to true if nil
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.castBar.showEmpoweredStageColors = val
                            -- Reinitialize empowered stages if currently showing an empowered cast
                            if DDingUI.castBar and DDingUI.castBar.isEmpowered and DDingUI.castBar.numStages and DDingUI.castBar.numStages > 0 then
                                if DDingUI.CastBars and DDingUI.CastBars.InitializeEmpoweredStages then
                                    -- Force reinitialize to apply the setting change
                                    C_Timer.After(0.01, function()
                                        if DDingUI.castBar and DDingUI.castBar.isEmpowered then
                                            DDingUI.CastBars:InitializeEmpoweredStages(DDingUI.castBar)
                                        end
                                    end)
                                end
                            end
                        end,
                    },
                    empoweredStage1Color = {
                        type = "color",
                        name = L["Stage 1 Color"],
                        desc = L["Background and foreground color for stage 1 of empowered casts"],
                        order = 30,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.castBar.empoweredStageColors and DDingUI.db.profile.castBar.empoweredStageColors[1]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.3, 0.75, 1, 1
                        end,
                        set = function(_, r, g, b, a)
                            if not DDingUI.db.profile.castBar.empoweredStageColors then
                                DDingUI.db.profile.castBar.empoweredStageColors = {}
                            end
                            DDingUI.db.profile.castBar.empoweredStageColors[1] = { r, g, b, a or 1 }
                        end,
                    },
                    empoweredStage2Color = {
                        type = "color",
                        name = L["Stage 2 Color"],
                        desc = L["Background and foreground color for stage 2 of empowered casts"],
                        order = 31,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.castBar.empoweredStageColors and DDingUI.db.profile.castBar.empoweredStageColors[2]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.4, 1, 0.4, 1
                        end,
                        set = function(_, r, g, b, a)
                            if not DDingUI.db.profile.castBar.empoweredStageColors then
                                DDingUI.db.profile.castBar.empoweredStageColors = {}
                            end
                            DDingUI.db.profile.castBar.empoweredStageColors[2] = { r, g, b, a or 1 }
                        end,
                    },
                    empoweredStage3Color = {
                        type = "color",
                        name = L["Stage 3 Color"],
                        desc = L["Background and foreground color for stage 3 of empowered casts"],
                        order = 32,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.castBar.empoweredStageColors and DDingUI.db.profile.castBar.empoweredStageColors[3]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1, 0.85, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            if not DDingUI.db.profile.castBar.empoweredStageColors then
                                DDingUI.db.profile.castBar.empoweredStageColors = {}
                            end
                            DDingUI.db.profile.castBar.empoweredStageColors[3] = { r, g, b, a or 1 }
                        end,
                    },
                    empoweredStage4Color = {
                        type = "color",
                        name = L["Stage 4 Color"],
                        desc = L["Background and foreground color for stage 4 of empowered casts"],
                        order = 33,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.castBar.empoweredStageColors and DDingUI.db.profile.castBar.empoweredStageColors[4]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1, 0.5, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            if not DDingUI.db.profile.castBar.empoweredStageColors then
                                DDingUI.db.profile.castBar.empoweredStageColors = {}
                            end
                            DDingUI.db.profile.castBar.empoweredStageColors[4] = { r, g, b, a or 1 }
                        end,
                    },
                    empoweredStage5Color = {
                        type = "color",
                        name = L["Stage 5 Color"],
                        desc = L["Background and foreground color for stage 5 of empowered casts"],
                        order = 34,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.castBar.empoweredStageColors and DDingUI.db.profile.castBar.empoweredStageColors[5]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1, 0.2, 0.2, 1
                        end,
                        set = function(_, r, g, b, a)
                            if not DDingUI.db.profile.castBar.empoweredStageColors then
                                DDingUI.db.profile.castBar.empoweredStageColors = {}
                            end
                            DDingUI.db.profile.castBar.empoweredStageColors[5] = { r, g, b, a or 1 }
                        end,
                    },
            --[[ Target/Focus/Boss cast bar options removed
            target = {
                type = "group",
                name = L["Target"],
                order = 2,
                hidden = true,
                args = {
                    header = {
                        type = "header",
                        name = L["Target Cast Bar Settings"],
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = L["Enable Target Cast Bar"],
                        desc = L["Show a bar when your target is casting or channeling spells"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.targetCastBar.enabled end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.enabled = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    testCast = {
                        type  = "execute",
                        name  = L["Test Target Cast Bar"],
                        desc  = L["Show a fake cast so you can preview and tweak the bar without a target casting. Unit Must Be active to test."],
                        order = 3,
                        func  = function()
                            DDingUI:ShowTestTargetCastBar()
                        end,
                    },
                    positionHeader = {
                        type = "header",
                        name = L["Position & Size"],
                        order = 10,
                    },
                    attachTo = {
                        type = "select",
                        name = L["Attach To"],
                        desc = L["Which frame to attach this bar to"],
                        order = 11,
                        width = "double",
                        values = function()
                            local opts = {}
                            if DDingUI.db.profile.unitFrames and DDingUI.db.profile.unitFrames.enabled then
                                opts["DDingUI_Target"] = L["Target Frame (Custom)"]
                            end
                            local viewerOpts = GetViewerOptions()
                            for k, v in pairs(viewerOpts) do
                                opts[k] = v
                            end
                            opts["TargetFrame"] = L["Default Target Frame"]
                            opts["UIParent"] = L["Screen Center"]
                            local current = DDingUI.db.profile.targetCastBar.attachTo
                            if current and not opts[current] then
                                opts[current] = current .. " (Custom)"
                            end
                            return opts
                        end,
                        get = function() return DDingUI.db.profile.targetCastBar.attachTo end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.attachTo = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    pickFrameTarget = {
                        type = "execute",
                        name = L["Pick Frame"] or "프레임 선택",
                        order = 11.5,
                        width = "half",
                        func = function()
                            DDingUI:StartFramePicker(function(frameName)
                                if frameName then
                                    DDingUI.db.profile.targetCastBar.attachTo = frameName
                                    DDingUI:UpdateTargetCastBarLayout()
                                end
                            end)
                        end,
                    },
                    anchorPoint = {
                        type = "select",
                        name = L["Anchor Point"],
                        desc = L["Which point of the attached frame to anchor to (moves with frame when it resizes)"],
                        order = 12,
                        width = "full",
                        values = {
                            ["TOPLEFT"] = L["Top Left"],
                            ["TOP"] = L["Top"],
                            ["TOPRIGHT"] = L["Top Right"],
                            ["LEFT"] = L["Left"],
                            ["CENTER"] = L["Center"],
                            ["RIGHT"] = L["Right"],
                            ["BOTTOMLEFT"] = L["Bottom Left"],
                            ["BOTTOM"] = L["Bottom"],
                            ["BOTTOMRIGHT"] = L["Bottom Right"],
                        },
                        get = function() return DDingUI.db.profile.targetCastBar.anchorPoint or "CENTER" end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.anchorPoint = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    frameStrata = {
                        type = "select",
                        name = L["Frame Strata"] or "Frame Strata",
                        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar. Higher strata appear on top of lower ones.",
                        order = 12.1,
                        width = "normal",
                        values = {
                            BACKGROUND = "BACKGROUND",
                            LOW = "LOW",
                            MEDIUM = "MEDIUM",
                            HIGH = "HIGH",
                            DIALOG = "DIALOG",
                        },
                        get = function() return DDingUI.db.profile.targetCastBar.frameStrata or "MEDIUM" end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.frameStrata = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    height = {
                        type = "range",
                        name = L["Height"],
                        order = 12,
                        width = "normal",
                        min = 6, max = 40, step = 1,
                        get = function() return DDingUI.db.profile.targetCastBar.height end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.height = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    width = {
                        type = "range",
                        name = L["Width"],
                        desc = L["0 = automatic width based on icons"],
                        order = 13,
                        width = "normal",
                        min = 0, max = 1000, step = 1,
                        get = function() return DDingUI.db.profile.targetCastBar.width end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.width = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    offsetY = {
                        type = "range",
                        name = L["Vertical Offset"],
                        desc = L["Distance from the anchor frame"],
                        order = 14,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.targetCastBar.offsetY end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.offsetY = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    offsetX = {
                        type = "range",
                        name = L["Horizontal Offset"],
                        desc = L["Horizontal distance from the anchor point"],
                        order = 15,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.targetCastBar.offsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.offsetX = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },

                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"],
                        order = 20,
                    },
                    texture = {
                        type = "select",
                        name = L["Bar Texture"],
                        order = 21,
                        width = "full",
                        values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar or {},
                        get = function() 
                            local override = DDingUI.db.profile.targetCastBar.texture
                            if override and override ~= "" then
                                return override
                            end
                            -- Return global texture name when override is nil
                            return DDingUI.db.profile.general.globalTexture or "Meli"
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.texture = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    barColor = {
                        type = "color",
                        name = L["Interruptible Color"],
                        desc = L["Color when the cast can be interrupted"],
                        order = 22,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.targetCastBar.interruptibleColor or DDingUI.db.profile.targetCastBar.color
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1, 0, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.targetCastBar.interruptibleColor = { r, g, b, a }
                            -- keep base color in sync for legacy fallback
                            DDingUI.db.profile.targetCastBar.color = { r, g, b, a }
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    nonInterruptibleColor = {
                        type = "color",
                        name = L["Non-Interruptible Color"],
                        desc = L["Color when the cast cannot be interrupted"],
                        order = 23,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.targetCastBar.nonInterruptibleColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.6, 0.6, 0.6, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.targetCastBar.nonInterruptibleColor = { r, g, b, a }
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    interruptedColor = {
                        type = "color",
                        name = L["Interrupted Color"],
                        desc = L["Color briefly used when the cast is interrupted"],
                        order = 24,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.targetCastBar.interruptedColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.8, 0.2, 0.2, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.targetCastBar.interruptedColor = { r, g, b, a }
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    interruptedFadeEnabled = {
                        type = "toggle",
                        name = L["Interrupted Fade Effect"] or "시전 중단 페이드 효과",
                        desc = L["Show a fade-out animation when cast is interrupted"] or "시전이 끊겼을 때 페이드아웃 효과 표시",
                        order = 24.1,
                        width = "normal",
                        get = function() return DDingUI.db.profile.targetCastBar.interruptedFadeEnabled ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.interruptedFadeEnabled = val
                        end,
                    },
                    interruptedFadeDuration = {
                        type = "range",
                        name = L["Fade Duration"] or "페이드 시간",
                        desc = L["Duration of the fade-out effect in seconds"] or "페이드아웃 효과 지속 시간 (초)",
                        order = 24.2,
                        width = "normal",
                        min = 0.1, max = 2.0, step = 0.1,
                        get = function() return DDingUI.db.profile.targetCastBar.interruptedFadeDuration or 0.5 end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.interruptedFadeDuration = val
                        end,
                    },
                    bgColor = {
                        type = "color",
                        name = L["Background Color"],
                        desc = L["Color of the bar background"],
                        order = 25,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.targetCastBar.bgColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.1, 0.1, 0.1, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.targetCastBar.bgColor = { r, g, b, a }
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    textFont = {
                        type = "select",
                        name = L["Font"],
                        desc = L["Font used for cast bar text"],
                        order = 25.5,
                        width = "full",
                        dialogControl = "LSM30_Font",
                        values = function() return DDingUI:GetFontValues() end,
                        get = function()
                            return DDingUI.db.profile.targetCastBar.textFont or DDingUI.DEFAULT_FONT_NAME
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.textFont = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    textSize = {
                        type = "range",
                        name = L["Text Size"],
                        order = 26,
                        width = "normal",
                        min = 6, max = 20, step = 1,
                        get = function() return DDingUI.db.profile.targetCastBar.textSize end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.textSize = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    showTimeText = {
                        type = "toggle",
                        name = L["Show Time Text"],
                        desc = L["Show the remaining cast time on the cast bar"],
                        order = 27,
                        width = "normal",
                        get = function() return DDingUI.db.profile.targetCastBar.showTimeText ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.showTimeText = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    timeTextFormat = {
                        type = "select",
                        name = L["Time Text Format"],
                        desc = L["Choose how the cast time is displayed"],
                        order = 27.5,
                        width = "normal",
                        values = {
                            ["current/total"] = "1.5/3.0 (경과/총)",
                            ["remaining/total"] = "1.5/3.0 (남은/총)",
                            ["remaining"] = "1.5 (남은 시간만)",
                        },
                        get = function() return DDingUI.db.profile.targetCastBar.timeTextFormat or "current/total" end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.timeTextFormat = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                    showIcon = {
                        type = "toggle",
                        name = L["Show Cast Icon"],
                        desc = L["Hide the spell icon if you prefer a bar-only look"],
                        order = 28,
                        width = "normal",
                        get = function() return DDingUI.db.profile.targetCastBar.showIcon ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.targetCastBar.showIcon = val
                            DDingUI:UpdateTargetCastBarLayout()
                        end,
                    },
                },
            },
            focus = {
                type = "group",
                name = L["Focus"],
                order = 3,
                hidden = true,
                args = {
                    header = {
                        type = "header",
                        name = L["Focus Cast Bar Settings"],
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = L["Enable Focus Cast Bar"],
                        desc = L["Show a bar when your focus is casting or channeling spells"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.focusCastBar.enabled end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.enabled = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    testCast = {
                        type  = "execute",
                        name  = L["Test Focus Cast Bar"],
                        desc  = L["Show a fake cast so you can preview and tweak the bar without a focus casting. Unit Must Be active to test."],
                        order = 3,
                        func  = function()
                            DDingUI:ShowTestFocusCastBar()
                        end,
                    },
                    positionHeader = {
                        type = "header",
                        name = L["Position & Size"],
                        order = 10,
                    },
                    attachTo = {
                        type = "select",
                        name = L["Attach To"],
                        desc = L["Which frame to attach this bar to"],
                        order = 11,
                        width = "double",
                        values = function()
                            local opts = {}
                            if DDingUI.db.profile.unitFrames and DDingUI.db.profile.unitFrames.enabled then
                                opts["DDingUI_Focus"] = L["Focus Frame (Custom)"]
                            end
                            local viewerOpts = GetViewerOptions()
                            for k, v in pairs(viewerOpts) do
                                opts[k] = v
                            end
                            opts["FocusFrame"] = L["Default Focus Frame"]
                            opts["UIParent"] = L["Screen Center"]
                            local current = DDingUI.db.profile.focusCastBar.attachTo
                            if current and not opts[current] then
                                opts[current] = current .. " (Custom)"
                            end
                            return opts
                        end,
                        get = function() return DDingUI.db.profile.focusCastBar.attachTo end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.attachTo = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    pickFrameFocus = {
                        type = "execute",
                        name = L["Pick Frame"] or "프레임 선택",
                        order = 11.5,
                        width = "half",
                        func = function()
                            DDingUI:StartFramePicker(function(frameName)
                                if frameName then
                                    DDingUI.db.profile.focusCastBar.attachTo = frameName
                                    DDingUI:UpdateFocusCastBarLayout()
                                end
                            end)
                        end,
                    },
                    anchorPoint = {
                        type = "select",
                        name = L["Anchor Point"],
                        desc = L["Which point of the attached frame to anchor to (moves with frame when it resizes)"],
                        order = 12,
                        width = "full",
                        values = {
                            ["TOPLEFT"] = L["Top Left"],
                            ["TOP"] = L["Top"],
                            ["TOPRIGHT"] = L["Top Right"],
                            ["LEFT"] = L["Left"],
                            ["CENTER"] = L["Center"],
                            ["RIGHT"] = L["Right"],
                            ["BOTTOMLEFT"] = L["Bottom Left"],
                            ["BOTTOM"] = L["Bottom"],
                            ["BOTTOMRIGHT"] = L["Bottom Right"],
                        },
                        get = function() return DDingUI.db.profile.focusCastBar.anchorPoint or "CENTER" end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.anchorPoint = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    frameStrata = {
                        type = "select",
                        name = L["Frame Strata"] or "Frame Strata",
                        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar. Higher strata appear on top of lower ones.",
                        order = 12.1,
                        width = "normal",
                        values = {
                            BACKGROUND = "BACKGROUND",
                            LOW = "LOW",
                            MEDIUM = "MEDIUM",
                            HIGH = "HIGH",
                            DIALOG = "DIALOG",
                        },
                        get = function() return DDingUI.db.profile.focusCastBar.frameStrata or "MEDIUM" end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.frameStrata = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    height = {
                        type = "range",
                        name = L["Height"],
                        order = 12,
                        width = "normal",
                        min = 6, max = 40, step = 1,
                        get = function() return DDingUI.db.profile.focusCastBar.height end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.height = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    width = {
                        type = "range",
                        name = L["Width"],
                        desc = L["0 = automatic width based on icons"],
                        order = 13,
                        width = "normal",
                        min = 0, max = 1000, step = 1,
                        get = function() return DDingUI.db.profile.focusCastBar.width end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.width = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    offsetY = {
                        type = "range",
                        name = L["Vertical Offset"],
                        desc = L["Distance from the anchor frame"],
                        order = 14,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.focusCastBar.offsetY end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.offsetY = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    offsetX = {
                        type = "range",
                        name = L["Horizontal Offset"],
                        desc = L["Horizontal distance from the anchor point"],
                        order = 15,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.focusCastBar.offsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.offsetX = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },

                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"],
                        order = 20,
                    },
                    texture = {
                        type = "select",
                        name = L["Bar Texture"],
                        order = 21,
                        width = "full",
                        values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar or {},
                        get = function() 
                            local override = DDingUI.db.profile.focusCastBar.texture
                            if override and override ~= "" then
                                return override
                            end
                            -- Return global texture name when override is nil
                            return DDingUI.db.profile.general.globalTexture or "Meli"
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.texture = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    barColor = {
                        type = "color",
                        name = L["Interruptible Color"],
                        desc = L["Color when the cast can be interrupted"],
                        order = 22,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.focusCastBar.interruptibleColor or DDingUI.db.profile.focusCastBar.color
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1, 0, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.focusCastBar.interruptibleColor = { r, g, b, a }
                            -- keep base color in sync for legacy fallback
                            DDingUI.db.profile.focusCastBar.color = { r, g, b, a }
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    nonInterruptibleColor = {
                        type = "color",
                        name = L["Non-Interruptible Color"],
                        desc = L["Color when the cast cannot be interrupted"],
                        order = 23,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.focusCastBar.nonInterruptibleColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.6, 0.6, 0.6, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.focusCastBar.nonInterruptibleColor = { r, g, b, a }
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    interruptedColor = {
                        type = "color",
                        name = L["Interrupted Color"],
                        desc = L["Color briefly used when the cast is interrupted"],
                        order = 24,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.focusCastBar.interruptedColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.8, 0.2, 0.2, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.focusCastBar.interruptedColor = { r, g, b, a }
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    interruptedFadeEnabled = {
                        type = "toggle",
                        name = L["Interrupted Fade Effect"] or "시전 중단 페이드 효과",
                        desc = L["Show a fade-out animation when cast is interrupted"] or "시전이 끊겼을 때 페이드아웃 효과 표시",
                        order = 24.1,
                        width = "normal",
                        get = function() return DDingUI.db.profile.focusCastBar.interruptedFadeEnabled ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.interruptedFadeEnabled = val
                        end,
                    },
                    interruptedFadeDuration = {
                        type = "range",
                        name = L["Fade Duration"] or "페이드 시간",
                        desc = L["Duration of the fade-out effect in seconds"] or "페이드아웃 효과 지속 시간 (초)",
                        order = 24.2,
                        width = "normal",
                        min = 0.1, max = 2.0, step = 0.1,
                        get = function() return DDingUI.db.profile.focusCastBar.interruptedFadeDuration or 0.5 end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.interruptedFadeDuration = val
                        end,
                    },
                    bgColor = {
                        type = "color",
                        name = L["Background Color"],
                        desc = L["Color of the bar background"],
                        order = 25,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.focusCastBar.bgColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.1, 0.1, 0.1, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.focusCastBar.bgColor = { r, g, b, a }
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    textFont = {
                        type = "select",
                        name = L["Font"],
                        desc = L["Font used for cast bar text"],
                        order = 25.5,
                        width = "full",
                        dialogControl = "LSM30_Font",
                        values = function() return DDingUI:GetFontValues() end,
                        get = function()
                            return DDingUI.db.profile.focusCastBar.textFont or DDingUI.DEFAULT_FONT_NAME
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.textFont = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    textSize = {
                        type = "range",
                        name = L["Text Size"],
                        order = 26,
                        width = "normal",
                        min = 6, max = 20, step = 1,
                        get = function() return DDingUI.db.profile.focusCastBar.textSize end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.textSize = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    showTimeText = {
                        type = "toggle",
                        name = L["Show Time Text"],
                        desc = L["Show the remaining cast time on the cast bar"],
                        order = 27,
                        width = "normal",
                        get = function() return DDingUI.db.profile.focusCastBar.showTimeText ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.showTimeText = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    timeTextFormat = {
                        type = "select",
                        name = L["Time Text Format"],
                        desc = L["Choose how the cast time is displayed"],
                        order = 27.5,
                        width = "normal",
                        values = {
                            ["current/total"] = "1.5/3.0 (경과/총)",
                            ["remaining/total"] = "1.5/3.0 (남은/총)",
                            ["remaining"] = "1.5 (남은 시간만)",
                        },
                        get = function() return DDingUI.db.profile.focusCastBar.timeTextFormat or "current/total" end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.timeTextFormat = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                    showIcon = {
                        type = "toggle",
                        name = L["Show Cast Icon"],
                        desc = L["Hide the spell icon if you prefer a bar-only look"],
                        order = 28,
                        width = "normal",
                        get = function() return DDingUI.db.profile.focusCastBar.showIcon ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.focusCastBar.showIcon = val
                            DDingUI:UpdateFocusCastBarLayout()
                        end,
                    },
                },
            },
            boss = {
                type = "group",
                name = L["Boss"],
                order = 4,
                hidden = true,
                args = {
                    header = {
                        type = "header",
                        name = L["Boss Cast Bar Settings"],
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = L["Enable Boss Cast Bars"],
                        desc = L["Show cast bars when boss units are casting or channeling spells"],
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.bossCastBar.enabled end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.enabled = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    testCast = {
                        type  = "execute",
                        name  = L["Test Boss Cast Bars"],
                        desc  = L["Show fake casts on boss frames so you can preview and tweak the bars. Boss frames must be in preview mode."],
                        order = 3,
                        func  = function()
                            DDingUI:ShowTestBossCastBars()
                        end,
                    },
                    positionHeader = {
                        type = "header",
                        name = L["Position & Size"],
                        order = 10,
                    },
                    anchorPoint = {
                        type = "select",
                        name = L["Anchor Point"],
                        desc = L["Which point of the attached frame to anchor to"],
                        order = 12,
                        width = "full",
                        values = {
                            ["TOPLEFT"] = L["Top Left"],
                            ["TOP"] = L["Top"],
                            ["TOPRIGHT"] = L["Top Right"],
                            ["LEFT"] = L["Left"],
                            ["CENTER"] = L["Center"],
                            ["RIGHT"] = L["Right"],
                            ["BOTTOMLEFT"] = L["Bottom Left"],
                            ["BOTTOM"] = L["Bottom"],
                            ["BOTTOMRIGHT"] = L["Bottom Right"],
                        },
                        get = function() return DDingUI.db.profile.bossCastBar.anchorPoint or "BOTTOM" end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.anchorPoint = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    frameStrata = {
                        type = "select",
                        name = L["Frame Strata"] or "Frame Strata",
                        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar. Higher strata appear on top of lower ones.",
                        order = 12.1,
                        width = "normal",
                        values = {
                            BACKGROUND = "BACKGROUND",
                            LOW = "LOW",
                            MEDIUM = "MEDIUM",
                            HIGH = "HIGH",
                            DIALOG = "DIALOG",
                        },
                        get = function() return DDingUI.db.profile.bossCastBar.frameStrata or "MEDIUM" end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.frameStrata = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    height = {
                        type = "range",
                        name = L["Height"],
                        order = 13,
                        width = "normal",
                        min = 6, max = 40, step = 1,
                        get = function() return DDingUI.db.profile.bossCastBar.height end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.height = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    width = {
                        type = "range",
                        name = L["Width"],
                        desc = L["0 = automatic width based on anchor"],
                        order = 14,
                        width = "normal",
                        min = 0, max = 1000, step = 1,
                        get = function() return DDingUI.db.profile.bossCastBar.width end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.width = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    offsetX = {
                        type = "range",
                        name = L["Horizontal Offset"],
                        order = 15,
                        width = "normal",
                        min = -200, max = 200, step = 1,
                        get = function() return DDingUI.db.profile.bossCastBar.offsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.offsetX = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    offsetY = {
                        type = "range",
                        name = L["Vertical Offset"],
                        order = 16,
                        width = "normal",
                        min = -100, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.bossCastBar.offsetY or -1 end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.offsetY = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"],
                        order = 20,
                    },
                    texture = {
                        type = "select",
                        name = L["Bar Texture"],
                        desc = L["Texture used for the cast bar"],
                        order = 21,
                        width = "full",
                        dialogControl = "LSM30_Statusbar",
                        values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar or {},
                        get = function() return DDingUI.db.profile.bossCastBar.texture end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.texture = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    interruptibleColor = {
                        type = "color",
                        name = L["Interruptible Color"],
                        desc = L["Color used for interruptible casts"],
                        order = 22,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.bossCastBar.interruptibleColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.5, 0.5, 1.0, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.bossCastBar.interruptibleColor = { r, g, b, a }
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    nonInterruptibleColor = {
                        type = "color",
                        name = L["Non-Interruptible Color"],
                        desc = L["Color used for non-interruptible casts"],
                        order = 23,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.bossCastBar.nonInterruptibleColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.6, 0.6, 0.6, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.bossCastBar.nonInterruptibleColor = { r, g, b, a }
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    interruptedColor = {
                        type = "color",
                        name = L["Interrupted Color"],
                        desc = L["Color briefly used when the cast is interrupted"],
                        order = 24,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.bossCastBar.interruptedColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.8, 0.2, 0.2, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.bossCastBar.interruptedColor = { r, g, b, a }
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    interruptedFadeEnabled = {
                        type = "toggle",
                        name = L["Interrupted Fade Effect"] or "시전 중단 페이드 효과",
                        desc = L["Show a fade-out animation when cast is interrupted"] or "시전이 끊겼을 때 페이드아웃 효과 표시",
                        order = 24.1,
                        width = "normal",
                        get = function() return DDingUI.db.profile.bossCastBar.interruptedFadeEnabled ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.interruptedFadeEnabled = val
                        end,
                    },
                    interruptedFadeDuration = {
                        type = "range",
                        name = L["Fade Duration"] or "페이드 시간",
                        desc = L["Duration of the fade-out effect in seconds"] or "페이드아웃 효과 지속 시간 (초)",
                        order = 24.2,
                        width = "normal",
                        min = 0.1, max = 2.0, step = 0.1,
                        get = function() return DDingUI.db.profile.bossCastBar.interruptedFadeDuration or 0.5 end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.interruptedFadeDuration = val
                        end,
                    },
                    bgColor = {
                        type = "color",
                        name = L["Background Color"],
                        desc = L["Color of the bar background"],
                        order = 25,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.bossCastBar.bgColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.1, 0.1, 0.1, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.bossCastBar.bgColor = { r, g, b, a }
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    showTimeText = {
                        type = "toggle",
                        name = L["Show Time Text"],
                        desc = L["Show the remaining cast time on the cast bar"],
                        order = 27,
                        width = "normal",
                        get = function() return DDingUI.db.profile.bossCastBar.showTimeText ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.showTimeText = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    timeTextFormat = {
                        type = "select",
                        name = L["Time Text Format"],
                        desc = L["Choose how the cast time is displayed"],
                        order = 27.5,
                        width = "normal",
                        values = {
                            ["current/total"] = "1.5/3.0 (경과/총)",
                            ["remaining/total"] = "1.5/3.0 (남은/총)",
                            ["remaining"] = "1.5 (남은 시간만)",
                        },
                        get = function() return DDingUI.db.profile.bossCastBar.timeTextFormat or "current/total" end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.timeTextFormat = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                    showIcon = {
                        type = "toggle",
                        name = L["Show Cast Icon"],
                        desc = L["Hide the spell icon if you prefer a bar-only look"],
                        order = 28,
                        width = "normal",
                        get = function() return DDingUI.db.profile.bossCastBar.showIcon ~= false end,
                        set = function(_, val)
                            DDingUI.db.profile.bossCastBar.showIcon = val
                            DDingUI:UpdateAllBossCastBarLayouts()
                        end,
                    },
                },
            },
            --]] -- End Target/Focus/Boss cast bar options
        },
    }
end

ns.CreateCastBarOptions = CreateCastBarOptions

