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
local GroupSystemOptions = ns.CreateGroupSystemOptions
local ProfileOptions = ns.CreateProfileOptions

-- [REFACTOR] AceGUI → StyleLib: AceConfig-3.0, AceConfigDialog-3.0 제거
-- 옵션 테이블은 데이터 구조로 유지, GUI.lua가 커스텀 렌더링

function DDingUI:SetupOptions()
    local options = {
        type = "group",
        name = "DDingUI",
        args = {},
    }

    -- UI Scale Settings (최상위 카테고리)
    options.args.uiScale = {
        type = "group",
        name = L["UI Scale Settings"],
        order = 0,
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
                            print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cff00ff00" .. L["[DDingUI] UI Scale set to"] .. " " .. string.format("%.8f", savedScale) .. "|r") -- [STYLE]
                        end

                        -- [REFACTOR] AceGUI → StyleLib
                        DDingUI:RefreshConfigGUI()
                    else
                        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cffff0000" .. L["[DDingUI] Invalid UI scale value. Please enter a number between 0.33 and 1.0"] .. "|r") -- [STYLE]
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
                        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cff00ff00" .. L["[DDingUI] UI Scale set to"] .. " 0.711111 (1080p)|r") -- [STYLE]
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
                        print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cff00ff00" .. L["[DDingUI] UI Scale set to"] .. " 0.53333333 (1440p)|r") -- [STYLE]
                    end

                    -- [REFACTOR] AceGUI → StyleLib
                    DDingUI:RefreshConfigGUI()
                end,
            },
        },
    }

    -- Display Settings (최상위 카테고리)
    options.args.display = {
        type = "group",
        name = L["Display"] or "표시",
        order = 0.5,
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
            hideOutsideInstanceOnly = {
                type = "toggle",
                name = "인스턴스 밖에서만",
                desc = "위 숨기기 옵션을 인스턴스(던전/레이드/투기장/전장) 밖에서만 적용합니다. 인스턴스 안에서는 항상 표시됩니다.",
                order = 4,
                width = "full",
                disabled = function()
                    local cfg = DDingUI.db.profile.general
                    return not (cfg.hideWhileFlying or cfg.hideWhileMounted or cfg.hideInVehicle)
                end,
                get = function() return DDingUI.db.profile.general.hideOutsideInstanceOnly end,
                set = function(_, val)
                    DDingUI.db.profile.general.hideOutsideInstanceOnly = val
                end,
            },
        },
    }

    -- [DYNAMIC] 아이콘 그룹 무조건 활성 — 개별 메뉴 항상 숨김
    -- Viewers (Cooldown Manager) — 아이콘 그룹에 통합됨
    if ViewerOptions then
        options.args.viewers = ViewerOptions(1)
        options.args.viewers.hidden = true
    end

    -- Resource Bars
    if ResourceBarOptions then
        options.args.resourceBars = ResourceBarOptions(2)
    end

    -- Custom Icons (Dynamic Icons) — 아이콘 그룹에 통합됨
    if CustomIconOptions then
        options.args.customIcons = CustomIconOptions(3)
        options.args.customIcons.hidden = true
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

    -- [DYNAMIC] 아이콘 그룹 (통합 메뉴 — 항상 최상단)
    if GroupSystemOptions then
        options.args.groupSystem = GroupSystemOptions(1)
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
