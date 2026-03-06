local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

local ViewerOptions = ns.CreateViewerOptions
local ResourceBarOptions = ns.CreateResourceBarOptions
local CustomIconOptions = ns.CreateCustomIconOptions
local IconCustomizationOptions = ns.CreateIconCustomizationOptions
local CastBarOptions = ns.CreateCastBarOptions
local BuffDebuffFramesOptions = ns.CreateBuffDebuffFramesOptions
local BuffBarOptions = ns.CreateBuffBarOptions
local BuffTrackerOptions = ns.CreateBuffTrackerOptions
local ProfileOptions = ns.CreateProfileOptions

-- [REFACTOR] AceGUI → StyleLib: AceConfig-3.0, AceConfigDialog-3.0 제거
-- 옵션 테이블은 데이터 구조로 유지, GUI.lua가 커스텀 렌더링

function DDingUI:SetupOptions()
    local options = {
        type = "group",
        name = "DDingUI",
        args = {},
    }

    -- General Settings (UI Scale)
    options.args.general = {
        type = "group",
        name = L["General"],
        order = 0,
        childGroups = "tab",
        args = {
            -- UI Scale 서브그룹
            uiScale = {
                type = "group",
                name = L["UI Scale Settings"],
                order = 1,
                args = {
                    uiScaleDesc = {
                        type = "description",
                        name = L["Adjust the UI scale for DDingUI elements. This affects UIParent-based frames."],
                        order = 1,
                    },

                    spacer1 = {
                        type = "description",
                        name = " ",
                        order = 2,
                    },

                    -- UI Scale Input
                    uiScaleInput = {
                        type = "input",
                        name = L["UI Scale"],
                        desc = L["Enter a UI scale value (0.33 to 1.0)"],
                        order = 10,
                        width = "full",
                        get = function()
                            local savedScale = DDingUI.db.profile.general.uiScale
                            if savedScale and type(savedScale) == "number" then
                                return string.format("%.8f", savedScale)
                            end

                            local cvarValue = GetCVar("uiscale")
                            if cvarValue then
                                local scale = tonumber(cvarValue)
                                if scale then
                                    return string.format("%.8f", scale)
                                end
                            end

                            local currentScale = UIParent:GetScale()
                            if currentScale then
                                return string.format("%.8f", currentScale)
                            end

                            return "1.00000000"
                        end,
                        set = function(_, val)
                            local numValue = tonumber(val)
                            if numValue then
                                numValue = math.max(0.33, math.min(1.0, numValue))
                                DDingUI.db.profile.general.uiScale = numValue
                            end
                        end,
                    },

                    -- Confirm UI Scale Button
                    confirmUIScale = {
                        type = "execute",
                        name = L["Confirm UI Scale"],
                        desc = L["Apply the UI scale value from the input box above"],
                        order = 11,
                        width = "full",
                        func = function()
                            local savedScale = DDingUI.db.profile.general.uiScale

                            if not savedScale or type(savedScale) ~= "number" then
                                local cvarValue = GetCVar("uiscale")
                                if cvarValue then
                                    savedScale = tonumber(cvarValue)
                                end
                            end

                            if savedScale and type(savedScale) == "number" then
                                savedScale = math.max(0.33, math.min(1.0, savedScale))
                                DDingUI.db.profile.general.uiScale = savedScale

                                if DDingUI.AutoUIScale and DDingUI.AutoUIScale.SetUIScale then
                                    DDingUI.AutoUIScale:SetUIScale(savedScale)
                                    print("|cff00ff00" .. L["[DDingUI] UI Scale set to"] .. " " .. string.format("%.8f", savedScale) .. "|r")
                                end

                                -- [REFACTOR] AceGUI → StyleLib
                                DDingUI:RefreshConfigGUI()
                            else
                                print("|cffff0000" .. L["[DDingUI] Invalid UI scale value. Please enter a number between 0.33 and 1.0"] .. "|r")
                            end
                        end,
                    },

                    spacer2 = {
                        type = "description",
                        name = " ",
                        order = 12,
                    },

                    -- Preset Buttons
                    preset1080p = {
                        type = "execute",
                        name = L["Set for 1080p (0.711111)"],
                        desc = L["Automatically set UI scale to 0.711111 for 1080p displays"],
                        order = 20,
                        width = "full",
                        func = function()
                            local scale1080p = 0.711111
                            DDingUI.db.profile.general.uiScale = scale1080p

                            if DDingUI.AutoUIScale and DDingUI.AutoUIScale.SetUIScale then
                                DDingUI.AutoUIScale:SetUIScale(scale1080p)
                                print("|cff00ff00" .. L["[DDingUI] UI Scale set to"] .. " 0.711111 (1080p)|r")
                            end

                            -- [REFACTOR] AceGUI → StyleLib
                            DDingUI:RefreshConfigGUI()
                        end,
                    },

                    preset1440p = {
                        type = "execute",
                        name = L["Set for 1440p (0.53333333)"],
                        desc = L["Automatically set UI scale to 0.53333333 for 1440p displays"],
                        order = 21,
                        width = "full",
                        func = function()
                            local scale1440p = 0.53333333
                            DDingUI.db.profile.general.uiScale = scale1440p

                            if DDingUI.AutoUIScale and DDingUI.AutoUIScale.SetUIScale then
                                DDingUI.AutoUIScale:SetUIScale(scale1440p)
                                print("|cff00ff00" .. L["[DDingUI] UI Scale set to"] .. " 0.53333333 (1440p)|r")
                            end

                            -- [REFACTOR] AceGUI → StyleLib
                            DDingUI:RefreshConfigGUI()
                        end,
                    },
                },
            },

            -- ========== DISPLAY ==========
            display = {
                type = "group",
                name = L["Display"] or "표시",
                order = 2,
                args = {
                    hideWhileFlying = {
                        type = "toggle",
                        name = L["Hide While Flying"] or "비행 시 숨기기",
                        desc = L["Fade out all DDingUI elements when skyriding/flying."] or "하늘 비행/비행 시 모든 DDingUI 요소를 페이드아웃합니다.",
                        order = 1,
                        width = "full",
                        get = function() return DDingUI.db.profile.general.hideWhileFlying end,
                        set = function(_, val)
                            DDingUI.db.profile.general.hideWhileFlying = val
                            if DDingUI.FlightHide then
                                if val then
                                    DDingUI.FlightHide:EnsureOnUpdate()
                                else
                                    DDingUI.FlightHide:ForceShow()
                                end
                            end
                        end,
                    },
                    hideWhileMounted = {
                        type = "toggle",
                        name = "탈것 탑승 시 숨기기",
                        desc = "탈것에 탑승 중일 때 모든 DDingUI 요소를 페이드아웃합니다.",
                        order = 2,
                        width = "full",
                        get = function() return DDingUI.db.profile.general.hideWhileMounted end,
                        set = function(_, val)
                            DDingUI.db.profile.general.hideWhileMounted = val
                            if DDingUI.FlightHide then
                                if val then
                                    DDingUI.FlightHide:EnsureOnUpdate()
                                else
                                    DDingUI.FlightHide:ForceShow()
                                end
                            end
                        end,
                    },
                    hideInVehicle = {
                        type = "toggle",
                        name = "탈것/퀘스트 UI 시 숨기기",
                        desc = "탈것 전투, 퍼즐 퀘스트 등 비히클 상태에서 모든 DDingUI 요소를 페이드아웃합니다.",
                        order = 3,
                        width = "full",
                        get = function() return DDingUI.db.profile.general.hideInVehicle end,
                        set = function(_, val)
                            DDingUI.db.profile.general.hideInVehicle = val
                            if DDingUI.FlightHide then
                                if val then
                                    DDingUI.FlightHide:EnsureOnUpdate()
                                else
                                    DDingUI.FlightHide:ForceShow()
                                end
                            end
                        end,
                    },
                },
            },

            -- ========== MISSING ALERTS ==========
            missingAlerts = {
                type = "group",
                name = L["Missing Alerts"] or "Missing Alerts",
                order = 30,
                childGroups = "tab",
                args = {
                    -- Pet Missing Subgroup
                    petMissing = {
                        type = "group",
                        name = L["Pet Missing"] or "펫 없음 알림",
                        order = 1,
                        args = {
                            enabled = {
                                type = "toggle",
                                name = L["Enable"] or "활성화",
                                desc = L["Show alert when pet is missing (Hunter/Warlock/Unholy DK)"] or "펫이 없을 때 알림 표시 (사냥꾼/흑마/부정기사)",
                                order = 1,
                                width = "full",
                                get = function() return DDingUI.db.profile.missingAlerts.petMissingEnabled end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.petMissingEnabled = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            text = {
                                type = "input",
                                name = L["Text"] or "텍스트",
                                desc = L["Alert text to display"] or "표시할 알림 텍스트",
                                order = 2,
                                width = "full",
                                get = function() return DDingUI.db.profile.missingAlerts.petText or "PET IS MISSING" end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.petText = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            fontSize = {
                                type = "range",
                                name = L["Font Size"] or "글꼴 크기",
                                order = 3,
                                width = "full",
                                min = 12, max = 96, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.petFontSize or 48 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.petFontSize = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            textColor = {
                                type = "color",
                                name = L["Color"] or "색상",
                                order = 4,
                                width = "full",
                                hasAlpha = true,
                                get = function()
                                    local c = DDingUI.db.profile.missingAlerts.petTextColor or { 0.42, 1, 0, 1 }
                                    return c[1], c[2], c[3], c[4] or 1
                                end,
                                set = function(_, r, g, b, a)
                                    DDingUI.db.profile.missingAlerts.petTextColor = { r, g, b, a }
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            offsetX = {
                                type = "range",
                                name = L["X Offset"] or "X 오프셋",
                                order = 5,
                                width = "full",
                                min = -500, max = 500, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.petOffsetX or 0 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.petOffsetX = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            offsetY = {
                                type = "range",
                                name = L["Y Offset"] or "Y 오프셋",
                                order = 6,
                                width = "full",
                                min = -500, max = 500, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.petOffsetY or 150 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.petOffsetY = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            borderHeader = {
                                type = "header",
                                name = L["Borders"] or "테두리",
                                order = 10,
                            },
                            petBorderSize = {
                                type = "range",
                                name = L["Border Size"] or "테두리 크기",
                                desc = L["Border thickness (0 = no border)"] or "테두리 두께 (0 = 테두리 없음)",
                                order = 11,
                                width = "full",
                                min = 0, max = 10, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.petBorderSize or 0 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.petBorderSize = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            petBorderColor = {
                                type = "color",
                                name = L["Border Color"] or "테두리 색상",
                                order = 12,
                                width = "full",
                                hasAlpha = true,
                                get = function()
                                    local c = DDingUI.db.profile.missingAlerts.petBorderColor or {0, 0, 0, 1}
                                    return c[1], c[2], c[3], c[4] or 1
                                end,
                                set = function(_, r, g, b, a)
                                    DDingUI.db.profile.missingAlerts.petBorderColor = {r, g, b, a}
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            displayHeader = {
                                type = "header",
                                name = L["Display Conditions"] or "표시 조건",
                                order = 20,
                            },
                            petInstanceOnly = {
                                type = "toggle",
                                name = L["Instance Only"] or "인스턴스 안에서만",
                                desc = L["Only show pet alert inside instances (dungeons/raids/arenas/battlegrounds)"] or "인스턴스 안에서만 펫 알림 표시 (던전/레이드/투기장/전장)",
                                order = 21,
                                width = "full",
                                get = function() return DDingUI.db.profile.missingAlerts.petInstanceOnly end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.petInstanceOnly = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                        },
                    },

                    -- Buff Missing Subgroup (DISABLED - 모듈 비활성화됨)
                    buffMissing = {
                        type = "group",
                        name = L["Class Buff Missing"] or "클래스 버프 없음 알림",
                        order = 2,
                        hidden = true,
                        args = {
                            enabled = {
                                type = "toggle",
                                name = L["Enable"] or "활성화",
                                desc = L["Show icon when your class buff is missing (combat only)"] or "전투 중 그룹 내 클래스 버프가 없는 멤버가 있으면 아이콘 표시",
                                order = 1,
                                width = "full",
                                get = function() return DDingUI.db.profile.missingAlerts.buffMissingEnabled end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffMissingEnabled = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            iconHeader = {
                                type = "header",
                                name = L["Icon Settings"] or "아이콘 설정",
                                order = 10,
                            },
                            iconSize = {
                                type = "range",
                                name = L["Icon Size"] or "아이콘 크기",
                                order = 11,
                                width = "full",
                                min = 24, max = 128, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.buffIconSize or 64 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffIconSize = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            borderSize = {
                                type = "range",
                                name = L["Border Size"] or "테두리 크기",
                                order = 12,
                                width = "full",
                                min = 0, max = 10, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.buffBorderSize or 2 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffBorderSize = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            borderColor = {
                                type = "color",
                                name = L["Border Color"] or "테두리 색상",
                                order = 13,
                                width = "full",
                                hasAlpha = true,
                                get = function()
                                    local c = DDingUI.db.profile.missingAlerts.buffBorderColor or {0, 0, 0, 1}
                                    return c[1], c[2], c[3], c[4] or 1
                                end,
                                set = function(_, r, g, b, a)
                                    DDingUI.db.profile.missingAlerts.buffBorderColor = {r, g, b, a}
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            desaturate = {
                                type = "toggle",
                                name = L["Desaturate"] or "흑백",
                                desc = L["Show icon in grayscale"] or "아이콘을 흑백으로 표시",
                                order = 14,
                                width = "full",
                                get = function() return DDingUI.db.profile.missingAlerts.buffDesaturate or false end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffDesaturate = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            textHeader = {
                                type = "header",
                                name = L["Text Settings"] or "텍스트 설정",
                                order = 20,
                            },
                            textFont = {
                                type = "select",
                                name = L["Font"] or "글꼴",
                                order = 21,
                                width = "full",
                                dialogControl = "LSM30_Font",
                                values = function() return DDingUI:GetFontValues() end,
                                get = function() return DDingUI.db.profile.missingAlerts.buffTextFont or DDingUI.DEFAULT_FONT_NAME end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffTextFont = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            textSize = {
                                type = "range",
                                name = L["Text Size"] or "텍스트 크기",
                                order = 22,
                                width = "full",
                                min = 8, max = 32, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.buffTextSize or 14 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffTextSize = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            textOutline = {
                                type = "select",
                                name = L["Text Outline"] or "텍스트 외곽선",
                                order = 23,
                                width = "full",
                                values = {
                                    ["NONE"] = L["None"] or "없음",
                                    ["OUTLINE"] = L["Outline"] or "외곽선",
                                    ["THICKOUTLINE"] = L["Thick Outline"] or "두꺼운 외곽선",
                                },
                                get = function() return DDingUI.db.profile.missingAlerts.buffTextOutline or "OUTLINE" end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffTextOutline = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            textColor = {
                                type = "color",
                                name = L["Text Color"] or "텍스트 색상",
                                order = 24,
                                width = "full",
                                hasAlpha = true,
                                get = function()
                                    local c = DDingUI.db.profile.missingAlerts.buffTextColor or {1, 1, 1, 1}
                                    return c[1], c[2], c[3], c[4] or 1
                                end,
                                set = function(_, r, g, b, a)
                                    DDingUI.db.profile.missingAlerts.buffTextColor = {r, g, b, a}
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            textOffsetY = {
                                type = "range",
                                name = L["Text Y Offset"] or "텍스트 Y 오프셋",
                                desc = L["Vertical position of count text relative to icon"] or "아이콘 기준 텍스트 세로 위치",
                                order = 25,
                                width = "full",
                                min = -50, max = 50, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.buffTextOffsetY or -18 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffTextOffsetY = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            positionHeader = {
                                type = "header",
                                name = L["Position"] or "위치",
                                order = 30,
                            },
                            offsetX = {
                                type = "range",
                                name = L["X Offset"] or "X 오프셋",
                                order = 31,
                                width = "full",
                                min = -500, max = 500, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.buffOffsetX or 0 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffOffsetX = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                            offsetY = {
                                type = "range",
                                name = L["Y Offset"] or "Y 오프셋",
                                order = 32,
                                width = "full",
                                min = -500, max = 500, step = 1,
                                get = function() return DDingUI.db.profile.missingAlerts.buffOffsetY or 230 end,
                                set = function(_, val)
                                    DDingUI.db.profile.missingAlerts.buffOffsetY = val
                                    if DDingUI.MissingAlerts then DDingUI.MissingAlerts:Refresh() end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    -- Viewers (Cooldown Manager)
    if ViewerOptions then
        options.args.viewers = ViewerOptions(1)
    end

    -- Resource Bars
    if ResourceBarOptions then
        options.args.resourceBars = ResourceBarOptions(2)
    end

    -- Custom Icons (Dynamic Icons)
    if CustomIconOptions then
        options.args.customIcons = CustomIconOptions(3)
    end

    -- Icon Customization
    if IconCustomizationOptions then
        options.args.iconCustomization = IconCustomizationOptions(4)
    end

    -- Cast Bars
    if CastBarOptions then
        options.args.castBars = CastBarOptions(5)
    end

    -- Buff/Debuff Frames (hidden - module disabled)
    -- if BuffDebuffFramesOptions then
    --     options.args.buffDebuffFrames = BuffDebuffFramesOptions(6)
    -- end

    -- Buff Bar (Cooldown Viewer Bar Style)
    if BuffBarOptions then
        options.args.buffBar = BuffBarOptions(7)
    end

    -- Buff Tracker
    if BuffTrackerOptions then
        options.args.buffTracker = BuffTrackerOptions(8)
    end

    -- Profiles (using custom ProfileOptions.lua to avoid ElvUI conflicts)
    if ProfileOptions then
        options.args.profiles = ProfileOptions(100)
    end

    -- Version display
    options.args.versionSpacer = {
        type = "description",
        name = " ",
        order = 200,
    }

    options.args.version = {
        type = "description",
        name = function()
            return "|cff00ff00DDingUI v" .. (C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "1.0") .. "|r"
        end,
        order = 201,
    }

    -- [REFACTOR] AceGUI → StyleLib: AceConfig:RegisterOptionsTable 제거
    -- 옵션 테이블은 GUI.lua 커스텀 렌더러가 직접 사용
    self.configOptions = options
end
