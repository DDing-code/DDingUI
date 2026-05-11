local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0", true)
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

-- IMPORTANT: Use weak table to store DDingUI data instead of adding fields to Blizzard frames
-- This prevents taint propagation that causes secret value errors in WoW 12.0+
local FrameData = setmetatable({}, { __mode = "k" })  -- weak keys

local function GetFrameData(frame)
    if not frame then return nil end
    if not FrameData[frame] then
        FrameData[frame] = {}
    end
    return FrameData[frame]
end

-- Helper to clear layout cache on a viewer without tainting Blizzard frames
local function ClearViewerLayoutCache(viewer)
    if not viewer then return end
    local data = GetFrameData(viewer)
    data.lastGrowthDirection = nil
    data.lastAppearanceKey = nil
end

-- Helper function to ensure viewer settings table exists
local function EnsureViewerSettings(viewerKey)
    if not DDingUI.db or not DDingUI.db.profile then return nil end
    if not DDingUI.db.profile.viewers then
        DDingUI.db.profile.viewers = {}
    end
    if not DDingUI.db.profile.viewers[viewerKey] then
        DDingUI.db.profile.viewers[viewerKey] = {}
    end
    return DDingUI.db.profile.viewers[viewerKey]
end

-- Helper function to get viewer settings safely
local function GetViewerSetting(viewerKey, key, default)
    if not DDingUI.db or not DDingUI.db.profile then return default end
    local viewers = DDingUI.db.profile.viewers
    if viewers and viewers[viewerKey] and viewers[viewerKey][key] ~= nil then
        return viewers[viewerKey][key]
    end
    return default
end

-- Helper function to set viewer settings safely
local function SetViewerSetting(viewerKey, key, value)
    local settings = EnsureViewerSettings(viewerKey)
    if settings then
        settings[key] = value
    end
    -- [FIX] 뷰어 설정 변경을 SpecProfiles 스냅샷에 반영
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
end

-- Helper function to get charge anchor options (uses MIDDLE instead of CENTER)
local function GetChargeAnchorOptions()
    return {
        TOPLEFT     = L["Top Left"] or "Top Left",
        TOP         = L["Top"] or "Top",
        TOPRIGHT    = L["Top Right"] or "Top Right",
        LEFT        = L["Left"] or "Left",
        MIDDLE      = L["Middle"] or "Middle",
        RIGHT       = L["Right"] or "Right",
        BOTTOMLEFT  = L["Bottom Left"] or "Bottom Left",
        BOTTOM      = L["Bottom"] or "Bottom",
        BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
    }
end

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

-- [GROUP SYSTEM] Viewer → Group default mapping
local VIEWER_GROUP_MAP = {
    ["EssentialCooldownViewer"] = "Cooldowns",
    ["BuffIconCooldownViewer"]  = "Buffs",
    ["UtilityCooldownViewer"]   = "Utility",
}

local FILTER_VALUES = {
    ["HELPFUL"]  = L["Buffs"] or "버프",
    ["HARMFUL"]  = L["Debuffs"] or "디버프",
    ["COOLDOWN"] = L["Cooldowns"] or "쿨다운",
    ["UTILITY"]  = L["Utility"] or "유틸리티",
    ["ALL"]      = L["All"] or "전체",
}

local function GetGS()
    if not DDingUI.db or not DDingUI.db.profile then return nil end
    return DDingUI.db.profile.groupSystem
end

local function RefreshGroupSystem()
    if DDingUI.GroupSystem and DDingUI.GroupSystem.Refresh then
        DDingUI.GroupSystem:Refresh()
    end
end

-- Helper to create viewer option groups
local function CreateViewerOptions(viewerKey, displayName, order)
    -- Ensure viewer settings table exists before creating options
    EnsureViewerSettings(viewerKey)

    local ret = {
        type = "group",
        name = displayName,
        order = order,
        args = {
            header = {
                type = "header",
                name = displayName .. " " .. L["Settings"],
                order = 1,
            },
            enabled = {
                type = "toggle",
                name = L["Enable"],
                desc = L["Show/hide this icon viewer"],
                width = "full",
                order = 2,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].enabled
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "enabled", val)
                    local viewer = _G[viewerKey]
                    if viewer then
                        if val then
                            viewer:Show()
                        else
                            viewer:Hide()
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            -- [GROUP SYSTEM] 그룹 시스템 설정 (각 뷰어 상단)
            groupSystemHeader = {
                type = "header",
                name = L["Group System"] or "그룹 시스템",
                order = 4,
            },
            groupSystemEnabled = {
                type = "toggle",
                name = L["Enable Group System"] or "그룹 시스템 활성화",
                desc = L["Replace default cooldown viewers with custom group-based system"] or "기본 쿨다운 뷰어를 커스텀 그룹 시스템으로 대체",
                order = 4.1,
                width = "full",
                get = function()
                    local gs = GetGS()
                    return gs and gs.enabled
                end,
                set = function(_, val)
                    local gs = GetGS()
                    if gs then
                        gs.enabled = val
                        if DDingUI.GroupSystem then
                            DDingUI.GroupSystem:Toggle()
                        end
                    end
                end,
            },
            groupEnabled = {
                type = "toggle",
                name = function()
                    local gn = VIEWER_GROUP_MAP[viewerKey] or "Group"
                    return (L["Enable"] or "활성화") .. " " .. gn .. " " .. (L["Group"] or "그룹")
                end,
                order = 4.2,
                width = "full",
                hidden = function()
                    local gs = GetGS()
                    return not (gs and gs.enabled)
                end,
                get = function()
                    local gs = GetGS()
                    local gn = VIEWER_GROUP_MAP[viewerKey]
                    return gn and gs and gs.groups and gs.groups[gn] and gs.groups[gn].enabled
                end,
                set = function(_, val)
                    local gs = GetGS()
                    local gn = VIEWER_GROUP_MAP[viewerKey]
                    if gn and gs and gs.groups and gs.groups[gn] then
                        gs.groups[gn].enabled = val
                        RefreshGroupSystem()
                    end
                end,
            },
            groupAutoFilter = {
                type = "select",
                name = L["Auto Filter"] or "자동 분류",
                desc = L["Automatic classification filter for this group"] or "이 그룹의 자동 분류 필터",
                order = 4.3,
                width = "full",
                hidden = function()
                    local gs = GetGS()
                    return not (gs and gs.enabled)
                end,
                values = FILTER_VALUES,
                get = function()
                    local gs = GetGS()
                    local gn = VIEWER_GROUP_MAP[viewerKey]
                    return gn and gs and gs.groups and gs.groups[gn] and gs.groups[gn].autoFilter or "ALL"
                end,
                set = function(_, val)
                    local gs = GetGS()
                    local gn = VIEWER_GROUP_MAP[viewerKey]
                    if gn and gs and gs.groups and gs.groups[gn] then
                        gs.groups[gn].autoFilter = val
                        RefreshGroupSystem()
                    end
                end,
            },
            -- [REFACTOR] 팝업 다이얼로그 → 인라인 아이콘 그리드
            groupAssignGrid = {
                type = "groupAssignGrid",
                name = L["Icon Assignment"] or "아이콘 할당",
                order = 4.4,
                groupName = VIEWER_GROUP_MAP[viewerKey],
                hidden = function()
                    local gs = GetGS()
                    return not (gs and gs.enabled)
                end,
            },
            -- Icon Layout Section
            iconLayoutHeader = {
                type = "header",
                name = L["Icon Layout"],
                order = 10,
            },
            rowLimit = {
                type = "range",
                name = L["Icons Per Row"],
                desc = L["Maximum icons per row (0 = unlimited, single row). When exceeded, creates new rows that grow from the center."],
                order = 10.9,
                width = "normal",
                min = 0, max = 20, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].rowLimit or 0
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "rowLimit", val)
                    -- Force immediate layout update
                    local viewer = _G[viewerKey]
                    if viewer then
                        ClearViewerLayoutCache(viewer)
                        if DDingUI.IconViewers and DDingUI.IconViewers.ApplyViewerLayout then
                            DDingUI.IconViewers:ApplyViewerLayout(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            iconSize = {
                type = "range",
                name = L["Icon Size"],
                desc = L["Base size of each icon in pixels (longest dimension)"],
                order = 11,
                width = "full",
                min = 16, max = 96, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].iconSize
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "iconSize", val)
                    -- Force re-skin of all icons in this viewer
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                        if DDingUI.IconViewers.ApplyViewerLayout then
                            DDingUI.IconViewers:ApplyViewerLayout(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            rowIconSize1 = {
                type = "range",
                name = L["Row 1 Icon Size"],
                desc = L["Override the icon size for the first row. Set to 0 to use the base Icon Size value."],
                order = 11.1,
                width = "normal",
                min = 0, max = 128, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local sizes = viewers and viewers[viewerKey] and viewers[viewerKey].rowIconSizes
                    return (sizes and sizes[1]) or 0
                end,
                set = function(_, val)
                    local profile = EnsureViewerSettings(viewerKey)
                    if not profile then return end
                    profile.rowIconSizes = profile.rowIconSizes or {}
                    profile.rowIconSizes[1] = (val and val > 0) and val or nil

                    local viewer = _G[viewerKey]
                    if viewer then
                        ClearViewerLayoutCache(viewer)
                        if DDingUI.IconViewers and DDingUI.IconViewers.ApplyViewerLayout then
                            DDingUI.IconViewers:ApplyViewerLayout(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            rowIconSize2 = {
                type = "range",
                name = L["Row 2 Icon Size"],
                desc = L["Override the icon size for the second row. Set to 0 to use the base Icon Size value."],
                order = 11.2,
                width = "normal",
                min = 0, max = 128, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local sizes = viewers and viewers[viewerKey] and viewers[viewerKey].rowIconSizes
                    return (sizes and sizes[2]) or 0
                end,
                set = function(_, val)
                    local profile = EnsureViewerSettings(viewerKey)
                    if not profile then return end
                    profile.rowIconSizes = profile.rowIconSizes or {}
                    profile.rowIconSizes[2] = (val and val > 0) and val or nil

                    local viewer = _G[viewerKey]
                    if viewer then
                        ClearViewerLayoutCache(viewer)
                        if DDingUI.IconViewers and DDingUI.IconViewers.ApplyViewerLayout then
                            DDingUI.IconViewers:ApplyViewerLayout(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            rowIconSize3 = {
                type = "range",
                name = L["Row 3 Icon Size"],
                desc = L["Override the icon size for the third row. Set to 0 to use the base Icon Size value."],
                order = 11.3,
                width = "normal",
                min = 0, max = 128, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local sizes = viewers and viewers[viewerKey] and viewers[viewerKey].rowIconSizes
                    return (sizes and sizes[3]) or 0
                end,
                set = function(_, val)
                    local profile = EnsureViewerSettings(viewerKey)
                    if not profile then return end
                    profile.rowIconSizes = profile.rowIconSizes or {}
                    profile.rowIconSizes[3] = (val and val > 0) and val or nil

                    local viewer = _G[viewerKey]
                    if viewer then
                        ClearViewerLayoutCache(viewer)
                        if DDingUI.IconViewers and DDingUI.IconViewers.ApplyViewerLayout then
                            DDingUI.IconViewers:ApplyViewerLayout(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            aspectRatio = {
                type = "range",
                name = L["Aspect Ratio (Width:Height)"],
                desc = L["Control the icon aspect ratio. 1.0 = square, >1.0 = wider, <1.0 = taller. Examples: 1.0=1:1, 1.78=16:9, 0.56=9:16"],
                order = 12,
                width = "full",
                min = 0.5, max = 2.5, step = 0.01,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local profile = viewers and viewers[viewerKey]
                    if not profile then return 1.0 end
                    -- Convert aspect ratio string to number, or use stored crop value
                    if profile.aspectRatioCrop then
                        return profile.aspectRatioCrop
                    elseif profile.aspectRatio then
                        -- Convert "16:9" format to 1.78
                        local w, h = profile.aspectRatio:match("^(%d+):(%d+)$")
                        if w and h then
                            return tonumber(w) / tonumber(h)
                        end
                    end
                    return 1.0 -- Default to square
                end,
                set = function(_, val)
                    local profile = EnsureViewerSettings(viewerKey)
                    if not profile then return end
                    profile.aspectRatioCrop = val
                    -- Also store as string format for backwards compatibility
                    -- Round to nearest common ratio or use exact value
                    local rounded = math.floor(val * 100 + 0.5) / 100
                    profile.aspectRatio = string.format("%.2f:1", rounded)
                    -- Force re-skin of all icons in this viewer (aspect ratio affects texture coordinates)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                        if DDingUI.IconViewers.ApplyViewerLayout then
                            DDingUI.IconViewers:ApplyViewerLayout(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            spacing = {
                type = "range",
                name = L["Spacing"],
                desc = L["Space between icons (negative = overlap)"],
                order = 13,
                width = "normal",
                min = -20, max = 20, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].spacing
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "spacing", val)
                    -- Force immediate layout update
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers and DDingUI.IconViewers.ApplyViewerLayout then
                        DDingUI.IconViewers:ApplyViewerLayout(viewer)
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            zoom = {
                type = "range",
                name = L["Icon Zoom"],
                desc = L["Crops the edges of icons (higher = more zoom)"],
                order = 14,
                width = "normal",
                min = 0, max = 0.2, step = 0.01,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].zoom
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "zoom", val)
                    -- Force re-skin of all icons in this viewer (zoom affects texture coordinates)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            primaryDirection = {
                type = "select",
                name = L["Primary Growth Direction"],
                desc = L["Direction that icons grow in the first line. CENTERED_HORIZONTAL centers icons and expands left/right. Static keeps icons in original positions (BuffIconCooldownViewer only)."],
                order = 17,
                width = "normal",
                values = function()
                    local values = {
                        ["CENTERED_HORIZONTAL"] = L["Centered Horizontal"],
                        ["RIGHT"] = L["Right"],
                        ["LEFT"] = L["Left"],
                        ["UP"] = L["Up"],
                        ["DOWN"] = L["Down"],
                    }
                    if viewerKey == "BuffIconCooldownViewer" then
                        values["STATIC"] = L["Static"]
                    end
                    return values
                end,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local profile = viewers and viewers[viewerKey]
                    if not profile then return "CENTERED_HORIZONTAL" end
                    if profile.primaryDirection then
                        return profile.primaryDirection
                    end
                    -- Legacy: Parse from growthDirection
                    if profile.growthDirection then
                        if profile.growthDirection == "Static" then
                            return "STATIC"
                        elseif profile.growthDirection == "Centered Horizontal" then
                            return "CENTERED_HORIZONTAL"
                        elseif profile.growthDirection:match("^Centered Horizontal and") then
                            return "CENTERED_HORIZONTAL"
                        else
                            local primary = profile.growthDirection:match("^(%w+)")
                            if primary then
                                return primary:upper()
                            end
                        end
                    end
                    -- Legacy support for rowGrowDirection
                    if profile.rowGrowDirection then
                        return "CENTERED_HORIZONTAL"
                    end
                    return "CENTERED_HORIZONTAL"
                end,
                set = function(_, val)
                    local profile = EnsureViewerSettings(viewerKey)
                    if not profile then return end
                    profile.primaryDirection = val
                    
                    local secondary = profile.secondaryDirection
                    
                    -- Validate and clear invalid secondary directions
                    if val == "STATIC" then
                        secondary = nil
                        profile.secondaryDirection = nil
                    elseif val == "CENTERED_HORIZONTAL" then
                        -- Only allow UP/DOWN for centered horizontal
                        if secondary and secondary ~= "UP" and secondary ~= "DOWN" then
                            secondary = nil
                            profile.secondaryDirection = nil
                        end
                    elseif val == "UP" or val == "DOWN" then
                        -- Vertical primary: only allow LEFT/RIGHT secondary
                        if secondary and secondary ~= "LEFT" and secondary ~= "RIGHT" then
                            secondary = nil
                            profile.secondaryDirection = nil
                        end
                    elseif val == "LEFT" or val == "RIGHT" then
                        -- Horizontal primary: only allow UP/DOWN secondary
                        if secondary and secondary ~= "UP" and secondary ~= "DOWN" then
                            secondary = nil
                            profile.secondaryDirection = nil
                        end
                    end
                    
                    -- Clear legacy settings
                    if profile.rowGrowDirection then
                        profile.rowGrowDirection = nil
                    end
                    if profile.growthDirection then
                        profile.growthDirection = nil
                    end
                    
                    -- Force immediate layout update
                    local viewer = _G[viewerKey]
                    if viewer then
                        ClearViewerLayoutCache(viewer)
                        if DDingUI.IconViewers and DDingUI.IconViewers.ApplyViewerLayout then
                            DDingUI.IconViewers:ApplyViewerLayout(viewer)
                        end
                    end
                    
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                    
                    -- [REFACTOR] AceGUI → StyleLib
                    DDingUI:RefreshConfigGUI(true)
                end,
            },
            secondaryDirection = {
                type = "select",
                name = L["Secondary Growth Direction"],
                desc = L["Direction that new rows/columns grow when icon limit per line is reached."],
                order = 18,
                width = "normal",
                values = function()
                    local viewers = DDingUI.db.profile.viewers
                    local profile = viewers and viewers[viewerKey]
                    if not profile then
                        return {
                            ["UP"] = L["Up"],
                            ["DOWN"] = L["Down"],
                        }
                    end

                    local primary = profile.primaryDirection
                    if not primary then
                        -- Try to parse from legacy growthDirection
                        if profile.growthDirection then
                            if profile.growthDirection == "Static" or profile.growthDirection == "STATIC" then
                                return {}
                            elseif profile.growthDirection == "Centered Horizontal" then
                                primary = "CENTERED_HORIZONTAL"
                            elseif profile.growthDirection:match("^Centered Horizontal and") then
                                primary = "CENTERED_HORIZONTAL"
                            else
                                local p = profile.growthDirection:match("^(%w+)")
                                if p then
                                    primary = p:upper()
                                end
                            end
                        end
                        if not primary then
                            primary = "CENTERED_HORIZONTAL"
                        end
                    end
                    
                    -- Return allowed secondary directions based on primary
                    if primary == "STATIC" then
                        return {}
                    elseif primary == "CENTERED_HORIZONTAL" then
                        -- Centered horizontal: only UP/DOWN allowed
                        return {
                            ["UP"] = L["Up"],
                            ["DOWN"] = L["Down"],
                        }
                    elseif primary == "UP" or primary == "DOWN" then
                        -- Vertical primary: only LEFT/RIGHT allowed
                        return {
                            ["LEFT"] = L["Left"],
                            ["RIGHT"] = L["Right"],
                        }
                    elseif primary == "LEFT" or primary == "RIGHT" then
                        -- Horizontal primary: only UP/DOWN allowed
                        return {
                            ["UP"] = L["Up"],
                            ["DOWN"] = L["Down"],
                        }
                    else
                        -- Default to UP/DOWN
                        return {
                            ["UP"] = L["Up"],
                            ["DOWN"] = L["Down"],
                        }
                    end
                end,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local profile = viewers and viewers[viewerKey]
                    if not profile then return nil end
                    if profile.secondaryDirection then
                        return profile.secondaryDirection
                    end
                    -- Legacy: Parse from growthDirection
                    if profile.growthDirection then
                        local secondary = profile.growthDirection:match("and%s+(%w+)$")
                        if secondary then
                            return secondary:upper()
                        end
                    end
                    -- Legacy support
                    if profile.rowGrowDirection then
                        return profile.rowGrowDirection == "up" and "UP" or "DOWN"
                    end
                    return nil
                end,
                set = function(_, val)
                    local profile = EnsureViewerSettings(viewerKey)
                    if not profile then return end
                    profile.secondaryDirection = val
                    
                    -- Clear legacy settings
                    if profile.rowGrowDirection then
                        profile.rowGrowDirection = nil
                    end
                    if profile.growthDirection then
                        profile.growthDirection = nil
                    end
                    
                    -- Force immediate layout update
                    local viewer = _G[viewerKey]
                    if viewer then
                        ClearViewerLayoutCache(viewer)
                        if DDingUI.IconViewers and DDingUI.IconViewers.ApplyViewerLayout then
                            DDingUI.IconViewers:ApplyViewerLayout(viewer)
                        end
                    end
                    
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            
            -- Border Section
            borderHeader = {
                type = "header",
                name = L["Borders"],
                order = 20,
            },
            borderSize = {
                type = "range",
                name = L["Border Size"],
                desc = L["Border thickness (0 = no border)"],
                order = 21,
                width = "full",
                min = 0, max = 5, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].borderSize
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "borderSize", val)
                    -- Force re-skin of all icons in this viewer (border size affects border display)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            
            -- Charge / Stack Text Section
            chargeTextHeader = {
                type = "header",
                name = L["Charge / Stack Text"],
                order = 30,
            },
            countTextFont = {
                type = "select",
                name = L["Font"],
                desc = L["Font used for charge/stack text"],
                order = 30.5,
                width = "full",
                dialogControl = "LSM30_Font",
                values = function() return DDingUI:GetFontValues() end,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local font = viewers and viewers[viewerKey] and viewers[viewerKey].countTextFont
                    if not font or font == "" then
                        font = (viewers and viewers.general and viewers.general.countTextFont) or DDingUI.DEFAULT_FONT_NAME
                    end
                    return font
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "countTextFont", val)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
                end,
            },
            countTextSize = {
                type = "range",
                name = L["Text Size"],
                desc = L["Font size for charge/stack numbers"],
                order = 31,
                width = "full",
                min = 6, max = 32, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].countTextSize or 16
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "countTextSize", val)
                    -- Force re-skin of all icons in this viewer (text size affects charge/stack text)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            countTextColor = { -- [12.0.1]
                type = "color",
                name = L["Text Color"],
                desc = L["Color for charge/stack numbers"],
                order = 31.5,
                width = "normal",
                hasAlpha = true,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local c = viewers and viewers[viewerKey] and viewers[viewerKey].countTextColor
                    if not c then
                        c = (viewers and viewers.general and viewers.general.countTextColor) or {1, 1, 1, 1}
                    end
                    return c[1], c[2], c[3], c[4] or 1
                end,
                set = function(_, r, g, b, a)
                    local profile = EnsureViewerSettings(viewerKey)
                    if profile then
                        profile.countTextColor = {r, g, b, a or 1}
                    end
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
                end,
            },
            chargeTextAnchor = {
                type = "select",
                name = L["Text Position"],
                desc = L["Where to anchor the charge/stack text"],
                order = 32,
                width = "normal",
                values = GetChargeAnchorOptions(),
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].chargeTextAnchor or "BOTTOMRIGHT"
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "chargeTextAnchor", val)
                    -- Force re-skin of all icons in this viewer (text anchor affects charge/stack text position)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            countTextOffsetX = {
                type = "range",
                name = L["Horizontal Offset"],
                desc = L["Fine-tune text position horizontally"],
                order = 33,
                width = "normal",
                min = -50, max = 50, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].countTextOffsetX or 0
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "countTextOffsetX", val)
                    -- Force re-skin of all icons in this viewer (offset affects charge/stack text position)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            countTextOffsetY = {
                type = "range",
                name = L["Vertical Offset"],
                desc = L["Fine-tune text position vertically"],
                order = 34,
                width = "normal",
                min = -50, max = 50, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].countTextOffsetY or 0
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "countTextOffsetY", val)
                    -- Force re-skin of all icons in this viewer (offset affects charge/stack text position)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },

            -- Cooldown Text Section
            cooldownTextHeader = {
                type = "header",
                name = L["Cooldown Text"],
                order = 40,
            },
            hideDurationText = {
                type = "toggle",
                name = L["Hide Duration Text"] or "Hide Duration Text",
                desc = L["Hide the duration text on cooldown icons"] or "Hide the duration text on cooldown icons",
                order = 40.1,
                width = "full",
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].hideDurationText
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "hideDurationText", val)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            cooldownFont = {
                type = "select",
                name = L["Font"],
                desc = L["Font used for cooldown text"],
                order = 40.5,
                width = "full",
                dialogControl = "LSM30_Font",
                values = function() return DDingUI:GetFontValues() end,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local font = viewers and viewers[viewerKey] and viewers[viewerKey].cooldownFont
                    if not font or font == "" then
                        font = (viewers and viewers.general and viewers.general.cooldownFont) or DDingUI.DEFAULT_FONT_NAME
                    end
                    return font
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "cooldownFont", val)
                    if DDingUI.ApplyGlobalFont then
                        DDingUI:ApplyGlobalFont()
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            cooldownFontSize = {
                type = "range",
                name = L["Font Size"],
                desc = L["Font size for cooldown countdown text"],
                order = 41,
                width = "full",
                min = 8, max = 48, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local size = viewers and viewers[viewerKey] and viewers[viewerKey].cooldownFontSize
                    if not size then
                        size = (viewers and viewers.general and viewers.general.cooldownFontSize) or 18
                    end
                    return size
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "cooldownFontSize", val)
                    -- Refresh all cooldown fonts
                    if DDingUI.ApplyGlobalFont then
                        DDingUI:ApplyGlobalFont()
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            cooldownTextColor = {
                type = "color",
                name = L["Text Color"],
                desc = L["Color for cooldown countdown text"],
                order = 42,
                width = "normal",
                hasAlpha = true,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local c = viewers and viewers[viewerKey] and viewers[viewerKey].cooldownTextColor
                    if not c then
                        c = (viewers and viewers.general and viewers.general.cooldownTextColor) or {1, 1, 1, 1}
                    end
                    return c[1], c[2], c[3], c[4] or 1
                end,
                set = function(_, r, g, b, a)
                    local profile = EnsureViewerSettings(viewerKey)
                    if profile then
                        profile.cooldownTextColor = {r, g, b, a or 1}
                    end
                    -- Refresh all cooldown fonts
                    if DDingUI.ApplyGlobalFont then
                        DDingUI:ApplyGlobalFont()
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            cooldownTextAnchor = { -- [12.0.1]
                type = "select",
                name = L["Text Position"],
                desc = L["Where to anchor the cooldown text"],
                order = 43,
                width = "normal",
                values = GetChargeAnchorOptions(),
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].cooldownTextAnchor or "CENTER"
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "cooldownTextAnchor", val)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
                end,
            },
            cooldownTextOffsetX = { -- [12.0.1]
                type = "range",
                name = L["Horizontal Offset"],
                desc = L["Fine-tune cooldown text position horizontally"],
                order = 44,
                width = "normal",
                min = -50, max = 50, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].cooldownTextOffsetX or 0
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "cooldownTextOffsetX", val)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
                end,
            },
            cooldownTextOffsetY = { -- [12.0.1]
                type = "range",
                name = L["Vertical Offset"],
                desc = L["Fine-tune cooldown text position vertically"],
                order = 45,
                width = "normal",
                min = -50, max = 50, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    return viewers and viewers[viewerKey] and viewers[viewerKey].cooldownTextOffsetY or 0
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "cooldownTextOffsetY", val)
                    local viewer = _G[viewerKey]
                    if viewer and DDingUI.IconViewers then
                        if DDingUI.IconViewers.SkinAllIconsInViewer then
                            DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                        end
                    end
                    if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
                end,
            },
            cooldownTextFormat = {
                type = "select",
                name = L["Time Format"] or "Time Format",
                desc = L["Format for cooldown countdown display"] or "Format for cooldown countdown display",
                order = 46,
                width = "normal",
                hidden = true, -- 개발중 - v1.1.2에서 비활성화
                values = {
                    auto = L["Auto (Blizzard Default)"] or "Auto (Blizzard Default)",
                    seconds = L["Seconds Only"] or "Seconds Only",
                    mmss = L["MM:SS"] or "MM:SS",
                    decimal = L["Decimal (Under 10s)"] or "Decimal (Under 10s)",
                },
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local format = viewers and viewers[viewerKey] and viewers[viewerKey].cooldownTextFormat
                    if not format then
                        format = (viewers and viewers.general and viewers.general.cooldownTextFormat) or "auto"
                    end
                    return format
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "cooldownTextFormat", val)
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            -- Shadow Subsection
            shadowHeader = {
                type = "header",
                name = L["Shadow"],
                order = 43,
            },
            cooldownShadowOffsetX = {
                type = "range",
                name = L["Shadow Offset X"],
                desc = L["Horizontal shadow offset (positive = right, negative = left)"],
                order = 44,
                width = "normal",
                min = -5, max = 5, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local offset = viewers and viewers[viewerKey] and viewers[viewerKey].cooldownShadowOffsetX
                    if not offset then
                        offset = (viewers and viewers.general and viewers.general.cooldownShadowOffsetX) or 1
                    end
                    return offset
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "cooldownShadowOffsetX", val)
                    -- Refresh all cooldown fonts
                    if DDingUI.ApplyGlobalFont then
                        DDingUI:ApplyGlobalFont()
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
            cooldownShadowOffsetY = {
                type = "range",
                name = L["Shadow Offset Y"],
                desc = L["Vertical shadow offset (positive = up, negative = down)"],
                order = 45,
                width = "normal",
                min = -5, max = 5, step = 1,
                get = function()
                    local viewers = DDingUI.db.profile.viewers
                    local offset = viewers and viewers[viewerKey] and viewers[viewerKey].cooldownShadowOffsetY
                    if not offset then
                        offset = (viewers and viewers.general and viewers.general.cooldownShadowOffsetY) or -1
                    end
                    return offset
                end,
                set = function(_, val)
                    SetViewerSetting(viewerKey, "cooldownShadowOffsetY", val)
                    -- Refresh all cooldown fonts
                    if DDingUI.ApplyGlobalFont then
                        DDingUI:ApplyGlobalFont()
                    end
                    if DDingUI.RefreshViewers then
                        DDingUI:RefreshViewers()
                    end
                end,
            },
        },
    }
    
    -- Add keybind options at the top only for Essential and Utility viewers
    if viewerKey == "EssentialCooldownViewer" or viewerKey == "UtilityCooldownViewer" then
        local viewerSettingName = (viewerKey == "EssentialCooldownViewer") and "Essential" or "Utility"
        
        -- Keybind Text Toggle
        ret.args.showKeybinds = {
            type = "toggle",
            name = L["Show Keybind Text"],
            desc = L["Display keybind text from action bars on cooldown icons"],
            order = 2.1,
            width = "full",
            get = function()
                return DDingUI.db.profile["cooldownManager_showKeybinds_" .. viewerSettingName] or false
            end,
            set = function(_, val)
                DDingUI.db.profile["cooldownManager_showKeybinds_" .. viewerSettingName] = val
                if DDingUI.Keybinds then
                    DDingUI.Keybinds:OnSettingChanged(viewerSettingName)
                end
            end,
        }
        
        -- Keybind Text Settings Header
        ret.args.keybindHeader = {
            type = "header",
            name = L["Keybind Text Settings"],
            order = 2.15,
        }

        -- Keybind Font
        ret.args.keybindFont = {
            type = "select",
            name = L["Font"],
            desc = L["Font used for keybind text"],
            order = 2.2,
            width = "full",
            dialogControl = "LSM30_Font",
            values = function() return DDingUI:GetFontValues() end,
            get = function()
                local font = DDingUI.db.profile["cooldownManager_keybindFontName_" .. viewerSettingName]
                if not font or font == "" then
                    font = DDingUI.db.profile.cooldownManager_keybindFontName or DDingUI.DEFAULT_FONT_NAME
                end
                return font
            end,
            set = function(_, val)
                DDingUI.db.profile["cooldownManager_keybindFontName_" .. viewerSettingName] = val
                if DDingUI.Keybinds then
                    DDingUI.Keybinds:ApplyKeybindSettings(viewerKey)
                end
            end,
        }
        
        -- Keybind Font Size
        ret.args.keybindFontSize = {
            type = "range",
            name = L["Font Size"],
            desc = L["Font size for keybind text"],
            order = 2.3,
            width = "full",
            min = 8,
            max = 48, step = 1,

            get = function()
                return DDingUI.db.profile["cooldownManager_keybindFontSize_" .. viewerSettingName] or 14
            end,
            set = function(_, val)
                DDingUI.db.profile["cooldownManager_keybindFontSize_" .. viewerSettingName] = val
                if DDingUI.Keybinds then
                    DDingUI.Keybinds:ApplyKeybindSettings(viewerKey)
                end
            end,
        }
        
        -- Keybind Text Color
        ret.args.keybindFontColor = {
            type = "color",
            name = L["Text Color"],
            desc = L["Color for keybind text"],
            order = 2.4,
            width = "normal",
            hasAlpha = true,
            get = function()
                local c = DDingUI.db.profile["cooldownManager_keybindFontColor_" .. viewerSettingName]
                if not c then
                    c = DDingUI.db.profile.cooldownManager_keybindFontColor or {1, 1, 1, 1}
                end
                return c[1], c[2], c[3], c[4] or 1
            end,
            set = function(_, r, g, b, a)
                DDingUI.db.profile["cooldownManager_keybindFontColor_" .. viewerSettingName] = {r, g, b, a or 1}
                if DDingUI.Keybinds then
                    DDingUI.Keybinds:ApplyKeybindSettings(viewerKey)
                end
            end,
        }

        -- Keybind Anchor Point
        ret.args.keybindAnchor = {
            type = "select",
            name = L["Anchor Point"],
            desc = L["Position anchor for keybind text"],
            order = 2.5,
            width = "normal",
            values = {
                TOP = L["Top"],
                TOPRIGHT = L["Top Right"],
                TOPLEFT = L["Top Left"],
                RIGHT = L["Right"],
                BOTTOMRIGHT = L["Bottom Right"],
                BOTTOM = L["Bottom"],
                BOTTOMLEFT = L["Bottom Left"],
                LEFT = L["Left"],
                CENTER = L["Center"],
            },
            get = function()
                return DDingUI.db.profile["cooldownManager_keybindAnchor_" .. viewerSettingName] or "TOPRIGHT"
            end,
            set = function(_, val)
                DDingUI.db.profile["cooldownManager_keybindAnchor_" .. viewerSettingName] = val
                if DDingUI.Keybinds then
                    DDingUI.Keybinds:ApplyKeybindSettings(viewerKey)
                end
            end,
        }

        -- Keybind X Offset
        ret.args.keybindOffsetX = {
            type = "range",
            name = L["X Offset"],
            desc = L["Horizontal offset for keybind text"],
            order = 2.6,
            width = "normal",
            min = -40,
            max = 40, step = 1,

            get = function()
                return DDingUI.db.profile["cooldownManager_keybindOffsetX_" .. viewerSettingName] or -3
            end,
            set = function(_, val)
                DDingUI.db.profile["cooldownManager_keybindOffsetX_" .. viewerSettingName] = val
                if DDingUI.Keybinds then
                    DDingUI.Keybinds:ApplyKeybindSettings(viewerKey)
                end
            end,
        }

        -- Keybind Y Offset
        ret.args.keybindOffsetY = {
            type = "range",
            name = L["Y Offset"],
            desc = L["Vertical offset for keybind text"],
            order = 2.7,
            width = "normal",
            min = -40,
            max = 40, step = 1,

            get = function()
                return DDingUI.db.profile["cooldownManager_keybindOffsetY_" .. viewerSettingName] or -3
            end,
            set = function(_, val)
                DDingUI.db.profile["cooldownManager_keybindOffsetY_" .. viewerSettingName] = val
                if DDingUI.Keybinds then
                    DDingUI.Keybinds:ApplyKeybindSettings(viewerKey)
                end
            end,
        }
    end

    -- Group offset options for Essential and Utility viewers
    if viewerKey == "EssentialCooldownViewer" or viewerKey == "UtilityCooldownViewer" then
        -- AceDB defaults use metatables for nested tables.
        -- Writing to settings.groupOffsets.party.x modifies the default (not saved).
        -- We must assign the entire groupOffsets table to trigger __newindex on the profile.
        local function SaveGroupOffset(groupType, axis, val)
            local settings = EnsureViewerSettings(viewerKey)
            if not settings then return end
            -- Read current values (may come from defaults metatable)
            local cur = settings.groupOffsets
            local newOffsets = {
                party = {
                    x = cur and cur.party and cur.party.x or 0,
                    y = cur and cur.party and cur.party.y or 0,
                },
                raid = {
                    x = cur and cur.raid and cur.raid.x or 0,
                    y = cur and cur.raid and cur.raid.y or 0,
                },
            }
            newOffsets[groupType][axis] = val
            -- Assign whole table → triggers AceDB __newindex → saved to profile
            settings.groupOffsets = newOffsets
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                DDingUI.IconViewers:ApplyViewerLayout(viewer)
            end
        end

        ret.args.groupOffsetHeader = {
            type = "header",
            name = L["Group Offsets"] or "Group Offsets",
            order = 3.0,
        }
        ret.args.groupOffsetDesc = {
            type = "description",
            name = L["Shift all icons when in a party or raid (e.g. to avoid overlapping party frames)."] or "Shift all icons when in a party or raid (e.g. to avoid overlapping party frames).",
            order = 3.05,
        }
        -- Party Offset X
        ret.args.partyOffsetX = {
            type = "range",
            name = (L["Party"] or "Party") .. " X",
            desc = L["Horizontal offset when in a party (2-5 players)"] or "Horizontal offset when in a party (2-5 players)",
            order = 3.1,
            width = "normal",
            min = -1000, max = 1000, step = 1,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                local offsets = viewers and viewers[viewerKey] and viewers[viewerKey].groupOffsets
                return offsets and offsets.party and offsets.party.x or 0
            end,
            set = function(_, val) SaveGroupOffset("party", "x", val) end,
        }
        -- Party Offset Y
        ret.args.partyOffsetY = {
            type = "range",
            name = (L["Party"] or "Party") .. " Y",
            desc = L["Vertical offset when in a party (2-5 players)"] or "Vertical offset when in a party (2-5 players)",
            order = 3.2,
            width = "normal",
            min = -1000, max = 1000, step = 1,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                local offsets = viewers and viewers[viewerKey] and viewers[viewerKey].groupOffsets
                return offsets and offsets.party and offsets.party.y or 0
            end,
            set = function(_, val) SaveGroupOffset("party", "y", val) end,
        }
        -- Raid Offset X
        ret.args.raidOffsetX = {
            type = "range",
            name = (L["Raid"] or "Raid") .. " X",
            desc = L["Horizontal offset when in a raid (6+ players)"] or "Horizontal offset when in a raid (6+ players)",
            order = 3.3,
            width = "normal",
            min = -1000, max = 1000, step = 1,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                local offsets = viewers and viewers[viewerKey] and viewers[viewerKey].groupOffsets
                return offsets and offsets.raid and offsets.raid.x or 0
            end,
            set = function(_, val) SaveGroupOffset("raid", "x", val) end,
        }
        -- Raid Offset Y
        ret.args.raidOffsetY = {
            type = "range",
            name = (L["Raid"] or "Raid") .. " Y",
            desc = L["Vertical offset when in a raid (6+ players)"] or "Vertical offset when in a raid (6+ players)",
            order = 3.4,
            width = "normal",
            min = -1000, max = 1000, step = 1,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                local offsets = viewers and viewers[viewerKey] and viewers[viewerKey].groupOffsets
                return offsets and offsets.raid and offsets.raid.y or 0
            end,
            set = function(_, val) SaveGroupOffset("raid", "y", val) end,
        }
    end

    -- Custom anchor options for Utility and BuffIcon viewers
    if viewerKey == "UtilityCooldownViewer" or viewerKey == "BuffIconCooldownViewer" then
        local anchorPointOptions = {
            TOPLEFT     = "TOPLEFT",
            TOP         = "TOP",
            TOPRIGHT    = "TOPRIGHT",
            LEFT        = "LEFT",
            CENTER      = "CENTER",
            RIGHT       = "RIGHT",
            BOTTOMLEFT  = "BOTTOMLEFT",
            BOTTOM      = "BOTTOM",
            BOTTOMRIGHT = "BOTTOMRIGHT",
        }

        local function ApplyCustomAnchor()
            local viewer = _G[viewerKey]
            if not viewer then return end
            local s = DDingUI.db.profile.viewers and DDingUI.db.profile.viewers[viewerKey]
            if not s then return end
            local frameName = s.anchorFrame
            if not frameName or frameName == "" then return end
            local target = _G[frameName]
            if not target then return end
            if InCombatLockdown() then return end
            local pt = s.anchorPoint or "CENTER"
            local ox = s.anchorOffsetX or 0
            local oy = s.anchorOffsetY or 0
            viewer:ClearAllPoints()
            viewer:SetPoint(pt, target, pt, ox, oy)
        end

        ret.args.anchorHeader = {
            type = "header",
            name = "앵커 설정",
            order = 3.5,
        }
        ret.args.anchorDesc = {
            type = "description",
            name = "뷰어를 특정 프레임에 고정합니다. 비워두면 기본 위치(EditMode)를 사용합니다.",
            order = 3.55,
        }
        ret.args.anchorFrame = {
            type = "input",
            name = "앵커 프레임",
            desc = "고정할 프레임 이름 (예: PlayerFrame, DDingUI_BuffTrackerBar)",
            order = 3.6,
            width = "double",
            get = function()
                return GetViewerSetting(viewerKey, "anchorFrame", "")
            end,
            set = function(_, val)
                SetViewerSetting(viewerKey, "anchorFrame", val or "")
                ApplyCustomAnchor()
                if DDingUI.RefreshViewers then
                    DDingUI:RefreshViewers()
                end
            end,
        }
        ret.args.anchorPick = {
            type = "execute",
            name = "앵커 선택 (마우스 클릭)",
            desc = "화면에서 마우스로 프레임을 직접 선택합니다.",
            order = 3.65,
            width = "full",
            func = function()
                if DDingUI.StartFramePicker then
                    DDingUI:StartFramePicker(function(frameName)
                        SetViewerSetting(viewerKey, "anchorFrame", frameName or "")
                        ApplyCustomAnchor()
                        if DDingUI.RefreshViewers then
                            DDingUI:RefreshViewers()
                        end
                    end)
                else
                    print("|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: " .. "|cffff8800프레임 선택기를 사용할 수 없습니다.|r") -- [STYLE]
                end
            end,
        }
        ret.args.anchorClear = {
            type = "execute",
            name = "앵커 초기화",
            desc = "커스텀 앵커를 제거하고 기본 위치로 되돌립니다.",
            order = 3.66,
            width = "normal",
            func = function()
                SetViewerSetting(viewerKey, "anchorFrame", "")
                SetViewerSetting(viewerKey, "anchorOffsetX", 0)
                SetViewerSetting(viewerKey, "anchorOffsetY", 0)
                if DDingUI.RefreshViewers then
                    DDingUI:RefreshViewers()
                end
            end,
        }
        ret.args.anchorPoint = {
            type = "select",
            name = "앵커 포인트",
            desc = "뷰어를 대상 프레임의 어느 지점에 고정할지 선택합니다.",
            order = 3.7,
            width = "normal",
            values = anchorPointOptions,
            get = function()
                return GetViewerSetting(viewerKey, "anchorPoint", "CENTER")
            end,
            set = function(_, val)
                SetViewerSetting(viewerKey, "anchorPoint", val)
                ApplyCustomAnchor()
                if DDingUI.RefreshViewers then
                    DDingUI:RefreshViewers()
                end
            end,
        }
        ret.args.anchorOffsetX = {
            type = "range",
            name = "X 오프셋",
            desc = "앵커 지점으로부터의 수평 오프셋",
            order = 3.8,
            width = "normal",
            min = -500, max = 500, step = 1,
            get = function()
                return GetViewerSetting(viewerKey, "anchorOffsetX", 0)
            end,
            set = function(_, val)
                SetViewerSetting(viewerKey, "anchorOffsetX", val)
                ApplyCustomAnchor()
            end,
        }
        ret.args.anchorOffsetY = {
            type = "range",
            name = "Y 오프셋",
            desc = "앵커 지점으로부터의 수직 오프셋",
            order = 3.9,
            width = "normal",
            min = -500, max = 500, step = 1,
            get = function()
                return GetViewerSetting(viewerKey, "anchorOffsetY", 0)
            end,
            set = function(_, val)
                SetViewerSetting(viewerKey, "anchorOffsetY", val)
                ApplyCustomAnchor()
            end,
        }
    end

    -- Add button to open config panel for BuffIconCooldownViewer (at the top)
    if viewerKey == "BuffIconCooldownViewer" then
        -- Insert at the top by using order 1.5 (between header and enabled)
        ret.args.previewBuffIcons = {
            type = "execute",
            name = L["Preview Buff Icons"],
            desc = L["Open the full DDingUI configuration panel"],
            order = 1.5,
            width = "full",
            func = function()
                -- Try to find and open the CooldownViewerSettings frame
                local frame = _G["CooldownViewerSettings"]
                if frame then
                    frame:Show()
                    frame:Raise()
                else
                    -- Fallback: Open the custom GUI and navigate to the Cooldown Manager tab
                    if DDingUI and DDingUI.OpenConfigGUI then
                        DDingUI:OpenConfigGUI(nil, "viewers")
                    end
                end
            end,
        }

        -- Duration Text Settings Header (BuffIconCooldownViewer specific)
        ret.args.buffDurationHeader = {
            type = "header",
            name = L["Buff Duration Text"],
            order = 50,
        }

        -- Duration Text Anchor
        ret.args.durationTextAnchor = {
            type = "select",
            name = L["Duration Text Anchor"],
            desc = L["Where to anchor the duration text on buff icons"],
            order = 51,
            width = "normal",
            values = GetChargeAnchorOptions(),
            get = function()
                local viewers = DDingUI.db.profile.viewers
                return viewers and viewers.BuffIconCooldownViewer and viewers.BuffIconCooldownViewer.durationTextAnchor or "TOP"
            end,
            set = function(_, val)
                SetViewerSetting("BuffIconCooldownViewer", "durationTextAnchor", val)
                -- Force re-skin of all icons
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer and DDingUI.IconViewers then
                    if DDingUI.IconViewers.SkinAllIconsInViewer then
                        DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                    end
                end
                if DDingUI.RefreshViewers then
                    DDingUI:RefreshViewers()
                end
            end,
        }

        -- Duration Text X Offset
        ret.args.durationTextOffsetX = {
            type = "range",
            name = L["Duration Text X Offset"],
            desc = L["Horizontal offset for buff duration text"],
            order = 52,
            width = "normal",
            min = -50, max = 50, step = 1,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                return viewers and viewers.BuffIconCooldownViewer and viewers.BuffIconCooldownViewer.durationTextOffsetX or 0
            end,
            set = function(_, val)
                SetViewerSetting("BuffIconCooldownViewer", "durationTextOffsetX", val)
                -- Force re-skin of all icons
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer and DDingUI.IconViewers then
                    if DDingUI.IconViewers.SkinAllIconsInViewer then
                        DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                    end
                end
                if DDingUI.RefreshViewers then
                    DDingUI:RefreshViewers()
                end
            end,
        }

        -- Duration Text Y Offset
        ret.args.durationTextOffsetY = {
            type = "range",
            name = L["Duration Text Y Offset"],
            desc = L["Vertical offset for buff duration text"],
            order = 53,
            width = "normal",
            min = -50, max = 50, step = 1,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                return viewers and viewers.BuffIconCooldownViewer and viewers.BuffIconCooldownViewer.durationTextOffsetY or 0
            end,
            set = function(_, val)
                SetViewerSetting("BuffIconCooldownViewer", "durationTextOffsetY", val)
                -- Force re-skin of all icons
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer and DDingUI.IconViewers then
                    if DDingUI.IconViewers.SkinAllIconsInViewer then
                        DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                    end
                end
                if DDingUI.RefreshViewers then
                    DDingUI:RefreshViewers()
                end
            end,
        }

        -- [12.0.1] Duration Text Font
        ret.args.durationTextFont = {
            type = "select",
            name = L["Font"],
            desc = L["Font used for buff duration text"],
            order = 54,
            width = "full",
            dialogControl = "LSM30_Font",
            values = function() return DDingUI:GetFontValues() end,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                local font = viewers and viewers.BuffIconCooldownViewer and viewers.BuffIconCooldownViewer.durationTextFont
                if not font or font == "" then
                    font = (viewers and viewers.general and viewers.general.cooldownFont) or DDingUI.DEFAULT_FONT_NAME
                end
                return font
            end,
            set = function(_, val)
                SetViewerSetting("BuffIconCooldownViewer", "durationTextFont", val)
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer and DDingUI.IconViewers then
                    if DDingUI.IconViewers.SkinAllIconsInViewer then
                        DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                    end
                end
                if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
            end,
        }

        -- [12.0.1] Duration Text Size
        ret.args.durationTextSize = {
            type = "range",
            name = L["Font Size"],
            desc = L["Font size for buff duration text"],
            order = 55,
            width = "full",
            min = 6, max = 32, step = 1,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                return viewers and viewers.BuffIconCooldownViewer and viewers.BuffIconCooldownViewer.durationTextSize or 14
            end,
            set = function(_, val)
                SetViewerSetting("BuffIconCooldownViewer", "durationTextSize", val)
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer and DDingUI.IconViewers then
                    if DDingUI.IconViewers.SkinAllIconsInViewer then
                        DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                    end
                end
                if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
            end,
        }

        -- [12.0.1] Duration Text Color
        ret.args.durationTextColor = {
            type = "color",
            name = L["Text Color"],
            desc = L["Color for buff duration text"],
            order = 56,
            width = "normal",
            hasAlpha = true,
            get = function()
                local viewers = DDingUI.db.profile.viewers
                local c = viewers and viewers.BuffIconCooldownViewer and viewers.BuffIconCooldownViewer.durationTextColor
                if not c then
                    c = {1, 1, 1, 1}
                end
                return c[1], c[2], c[3], c[4] or 1
            end,
            set = function(_, r, g, b, a)
                local profile = EnsureViewerSettings("BuffIconCooldownViewer")
                if profile then
                    profile.durationTextColor = {r, g, b, a or 1}
                end
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer and DDingUI.IconViewers then
                    if DDingUI.IconViewers.SkinAllIconsInViewer then
                        DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                    end
                end
                if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
            end,
        }
    end

    -- Animation Settings Header (for all viewers)
    ret.args.animationHeader = {
        type = "header",
        name = L["Animation Settings"],
        order = 60,
    }

    -- Disable Swipe Animation (the rotating dark overlay)
    ret.args.disableSwipeAnimation = {
        type = "toggle",
        name = L["Disable Swipe Animation"],
        desc = L["Disable the rotating dark overlay that shows remaining duration"],
        order = 61,
        width = "full",
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].disableSwipeAnimation or false
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "disableSwipeAnimation", val)
            -- Force re-skin of all icons
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
            if DDingUI.RefreshViewers then
                DDingUI:RefreshViewers()
            end
        end,
    }

    -- Swipe Color
    ret.args.swipeColor = {
        type = "color",
        name = L["Swipe Color"],
        desc = L["Color of the swipe overlay"],
        order = 62,
        hasAlpha = true,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].disableSwipeAnimation
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local c = viewers and viewers[viewerKey] and viewers[viewerKey].swipeColor or {0, 0, 0, 0.8}
            return c[1], c[2], c[3], c[4]
        end,
        set = function(_, r, g, b, a)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.swipeColor = {r, g, b, a}
            end
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
            if DDingUI.RefreshViewers then
                DDingUI:RefreshViewers()
            end
        end,
    }

    -- Reverse Swipe
    ret.args.swipeReverse = {
        type = "toggle",
        name = L["Reverse Swipe"],
        desc = L["Reverse the swipe direction (for buff duration display)"],
        order = 63,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].disableSwipeAnimation
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local val = viewers and viewers[viewerKey] and viewers[viewerKey].swipeReverse
            -- Default: true for BuffIconCooldownViewer, false for others
            if val == nil then
                return viewerKey == "BuffIconCooldownViewer"
            end
            return val
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "swipeReverse", val)
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
            if DDingUI.RefreshViewers then
                DDingUI:RefreshViewers()
            end
        end,
    }

    -- Aura Swipe Color (for buff/survival ability duration)
    ret.args.auraSwipeColor = {
        type = "color",
        name = L["Aura Swipe Color"] .. " " .. (L["(Out of Combat Only)"] or "(Out of Combat Only)"),
        desc = L["Custom color for aura/buff duration swipe (the yellow swipe when survival abilities are active). Leave unchecked to use default yellow."] .. "\n\n|cffff6666" .. (L["Note: Only works outside of combat due to Blizzard taint restrictions. During combat, default yellow will be shown."] or "Note: Only works outside of combat due to Blizzard taint restrictions. During combat, default yellow will be shown.") .. "|r",
        order = 64,
        hasAlpha = true,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local c = viewers and viewers[viewerKey] and viewers[viewerKey].auraSwipeColor
            if c then
                return c[1], c[2], c[3], c[4]
            else
                return 0.95, 0.95, 0.32, 0.8  -- Default yellow for display
            end
        end,
        set = function(_, r, g, b, a)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.auraSwipeColor = {r, g, b, a}
            end
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
        end,
    }

    -- Reset Aura Swipe Color
    ret.args.resetAuraSwipeColor = {
        type = "execute",
        name = L["Reset to Default"],
        desc = L["Reset aura swipe color to default yellow"],
        order = 64.5,
        func = function()
            SetViewerSetting(viewerKey, "auraSwipeColor", nil)
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
            -- [REFACTOR] AceGUI → StyleLib
            local configFrame = _G["DDingUI_ConfigFrame"]
            if configFrame and configFrame:IsShown() then
                if configFrame.RefreshCurrentCategory then
                    configFrame:RefreshCurrentCategory()
                elseif configFrame.FullRefresh then
                    configFrame:FullRefresh()
                end
            end
        end,
    }

    -- ============================================================
    -- Personal 스와이프 (Aura Glow) 섹션
    -- ============================================================
    ret.args.auraGlowHeader = {
        type = "header",
        name = L["Personal Swipe Glow"] or "Personal Swipe Glow",
        order = 65,
    }

    -- Aura Glow (replaces aura swipe with glow)
    ret.args.auraGlow = {
        type = "toggle",
        name = L["Enable Glow Effect"] or "Enable Glow Effect",
        desc = L["Replace aura swipe with glow effect during buff duration (only applies to buff/aura tracking, not regular cooldowns)"] or "Replace aura swipe with glow effect during buff duration",
        order = 65.1,
        width = "full",
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlow or false
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlow", val)
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
        end,
    }

    -- Aura Glow Type
    ret.args.auraGlowType = {
        type = "select",
        name = L["Glow Type"] or "Glow Type",
        desc = L["Type of glow effect to show during buff duration"] or "Type of glow effect",
        order = 65.2,
        values = {
            ["Pixel Glow"] = "Pixel Glow",
            ["Autocast Shine"] = "Autocast Shine",
            ["Action Button Glow"] = "Action Button Glow",
            ["Proc Glow"] = "Proc Glow",
            ["Blizzard Glow"] = "Blizzard Glow",
        },
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey] and viewers[viewerKey].auraGlow)
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowType or "Pixel Glow"
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowType", val)
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
            if DDingUI.GUI and DDingUI.GUI.SoftRefresh then
                DDingUI.GUI.SoftRefresh()
            end
        end,
    }

    -- Aura Glow Color
    ret.args.auraGlowColor = {
        type = "color",
        name = L["Glow Color"] or "Glow Color",
        desc = L["Color of the aura duration glow effect"] or "Color of the glow effect",
        order = 65.3,
        hasAlpha = true,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey] and viewers[viewerKey].auraGlow)
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local c = viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowColor or {0.95, 0.95, 0.32, 1}
            return c[1], c[2], c[3], c[4]
        end,
        set = function(_, r, g, b, a)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.auraGlowColor = {r, g, b, a}
            end
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
        end,
    }

    -- Pixel Glow: Number of Lines
    ret.args.auraGlowPixelLines = {
        type = "range",
        name = L["Pixel Glow Lines"] or "Lines",
        order = 65.4,
        min = 1, max = 20, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local profile = viewers and viewers[viewerKey]
            return not (profile and profile.auraGlow) or (profile and profile.auraGlowType ~= "Pixel Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey]) or viewers[viewerKey].auraGlowType ~= "Pixel Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowPixelLines or 8
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowPixelLines", val)
        end,
    }

    -- Pixel Glow: Frequency (Speed)
    ret.args.auraGlowPixelFrequency = {
        type = "range",
        name = L["Pixel Glow Speed"] or "Speed",
        order = 65.5,
        min = 0.05, max = 1.0, step = 0.05,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local profile = viewers and viewers[viewerKey]
            return not (profile and profile.auraGlow) or (profile and profile.auraGlowType ~= "Pixel Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey]) or viewers[viewerKey].auraGlowType ~= "Pixel Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowPixelFrequency or 0.25
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowPixelFrequency", val)
        end,
    }

    -- Pixel Glow: Thickness
    ret.args.auraGlowPixelThickness = {
        type = "range",
        name = L["Pixel Glow Thickness"] or "Thickness",
        order = 65.6,
        min = 1, max = 5, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local profile = viewers and viewers[viewerKey]
            return not (profile and profile.auraGlow) or (profile and profile.auraGlowType ~= "Pixel Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey]) or viewers[viewerKey].auraGlowType ~= "Pixel Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowPixelThickness or 2
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowPixelThickness", val)
        end,
    }

    -- Pixel Glow: Length
    ret.args.auraGlowPixelLength = {
        type = "range",
        name = L["Pixel Glow Length"] or "Length",
        order = 65.65,
        min = 1, max = 10, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local profile = viewers and viewers[viewerKey]
            return not (profile and profile.auraGlow) or (profile and profile.auraGlowType ~= "Pixel Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey]) or viewers[viewerKey].auraGlowType ~= "Pixel Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowPixelLength or 8
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowPixelLength", val)
        end,
    }

    -- Autocast Shine: Particles
    ret.args.auraGlowAutocastParticles = {
        type = "range",
        name = L["Particles"] or "Particles",
        order = 65.71,
        min = 1, max = 16, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local profile = viewers and viewers[viewerKey]
            return not (profile and profile.auraGlow) or (profile and profile.auraGlowType ~= "Autocast Shine")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey]) or viewers[viewerKey].auraGlowType ~= "Autocast Shine"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowAutocastParticles or 8
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowAutocastParticles", val)
        end,
    }

    -- Autocast Shine: Frequency
    ret.args.auraGlowAutocastFrequency = {
        type = "range",
        name = L["Speed"] or "Speed",
        order = 65.72,
        min = 0.05, max = 1.0, step = 0.05,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local profile = viewers and viewers[viewerKey]
            return not (profile and profile.auraGlow) or (profile and profile.auraGlowType ~= "Autocast Shine")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey]) or viewers[viewerKey].auraGlowType ~= "Autocast Shine"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowAutocastFrequency or 0.25
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowAutocastFrequency", val)
        end,
    }

    -- Autocast Shine: Scale
    ret.args.auraGlowAutocastScale = {
        type = "range",
        name = L["Scale"] or "Scale",
        order = 65.73,
        min = 0.5, max = 3.0, step = 0.1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local profile = viewers and viewers[viewerKey]
            return not (profile and profile.auraGlow) or (profile and profile.auraGlowType ~= "Autocast Shine")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey]) or viewers[viewerKey].auraGlowType ~= "Autocast Shine"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowAutocastScale or 1.0
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowAutocastScale", val)
        end,
    }

    -- Action Button Glow: Frequency
    ret.args.auraGlowButtonFrequency = {
        type = "range",
        name = L["Speed"] or "Speed",
        order = 65.81,
        min = 0.05, max = 1.0, step = 0.05,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local profile = viewers and viewers[viewerKey]
            return not (profile and profile.auraGlow) or (profile and profile.auraGlowType ~= "Action Button Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            return not (viewers and viewers[viewerKey]) or viewers[viewerKey].auraGlowType ~= "Action Button Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].auraGlowButtonFrequency or 0.25
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "auraGlowButtonFrequency", val)
        end,
    }

    -- ============================================================
    -- 아이콘 글로우 (프록) 섹션
    -- ============================================================
    ret.args.procGlowHeader = {
        type = "header",
        name = L["Icon Glow (Proc)"] or "Icon Glow (Proc)",
        order = 66,
    }

    -- Proc Glow Enable
    ret.args.procGlowEnabled = {
        type = "toggle",
        name = L["Enable Proc Glow"] or "Enable Proc Glow",
        desc = L["Show glow effect when abilities proc"] or "Show glow effect when abilities proc",
        order = 66.1,
        width = "full",
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.enabled
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.enabled = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow Type
    ret.args.procGlowType = {
        type = "select",
        name = L["Glow Type"] or "Glow Type",
        order = 66.2,
        values = {
            ["Pixel Glow"] = "Pixel Glow",
            ["Autocast Shine"] = "Autocast Shine",
            ["Action Button Glow"] = "Action Button Glow",
            ["Proc Glow"] = "Proc Glow",
            ["Blizzard Glow"] = "Blizzard Glow",
        },
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled)
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.glowType or "Pixel Glow"
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.glowType = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
            if DDingUI.GUI and DDingUI.GUI.SoftRefresh then DDingUI.GUI.SoftRefresh() end
        end,
    }

    -- Proc Glow Color
    ret.args.procGlowColor = {
        type = "color",
        name = L["Glow Color"] or "Glow Color",
        order = 66.3,
        hasAlpha = true,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled)
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            local c = pg and pg.loopColor or {0.95, 0.95, 0.32, 1}
            return c[1], c[2], c[3], c[4]
        end,
        set = function(_, r, g, b, a)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.loopColor = {r, g, b, a}
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow: Pixel Lines
    ret.args.procGlowPixelLines = {
        type = "range",
        name = L["Pixel Glow Lines"] or "Lines",
        order = 66.4,
        min = 1, max = 20, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled) or (pg and pg.glowType ~= "Pixel Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not pg or pg.glowType ~= "Pixel Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.lcgLines or 10
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.lcgLines = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow: Frequency
    ret.args.procGlowPixelFrequency = {
        type = "range",
        name = L["Pixel Glow Speed"] or "Speed",
        order = 66.5,
        min = 0.05, max = 1.0, step = 0.05,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled) or (pg and pg.glowType ~= "Pixel Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not pg or pg.glowType ~= "Pixel Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.lcgFrequency or 0.25
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.lcgFrequency = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow: Thickness
    ret.args.procGlowPixelThickness = {
        type = "range",
        name = L["Pixel Glow Thickness"] or "Thickness",
        order = 66.6,
        min = 1, max = 5, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled) or (pg and pg.glowType ~= "Pixel Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not pg or pg.glowType ~= "Pixel Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.lcgThickness or 1
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.lcgThickness = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow: Length
    ret.args.procGlowPixelLength = {
        type = "range",
        name = L["Pixel Glow Length"] or "Length",
        order = 66.65,
        min = 1, max = 10, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled) or (pg and pg.glowType ~= "Pixel Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not pg or pg.glowType ~= "Pixel Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.lcgLength or 8
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.lcgLength = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow: Autocast Particles
    ret.args.procGlowAutocastParticles = {
        type = "range",
        name = L["Particles"] or "Particles",
        order = 66.71,
        min = 1, max = 16, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled) or (pg and pg.glowType ~= "Autocast Shine")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not pg or pg.glowType ~= "Autocast Shine"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.autocastParticles or 8
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.autocastParticles = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow: Autocast Frequency
    ret.args.procGlowAutocastFrequency = {
        type = "range",
        name = L["Speed"] or "Speed",
        order = 66.72,
        min = 0.05, max = 1.0, step = 0.05,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled) or (pg and pg.glowType ~= "Autocast Shine")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not pg or pg.glowType ~= "Autocast Shine"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.autocastFrequency or 0.25
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.autocastFrequency = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow: Autocast Scale
    ret.args.procGlowAutocastScale = {
        type = "range",
        name = L["Scale"] or "Scale",
        order = 66.73,
        min = 0.5, max = 3.0, step = 0.1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled) or (pg and pg.glowType ~= "Autocast Shine")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not pg or pg.glowType ~= "Autocast Shine"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.autocastScale or 1.0
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.autocastScale = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- Proc Glow: Action Button Frequency
    ret.args.procGlowButtonFrequency = {
        type = "range",
        name = L["Speed"] or "Speed",
        order = 66.81,
        min = 0.05, max = 1.0, step = 0.05,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not (pg and pg.enabled) or (pg and pg.glowType ~= "Action Button Glow")
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return not pg or pg.glowType ~= "Action Button Glow"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local pg = viewers and viewers[viewerKey] and viewers[viewerKey].procGlow
            return pg and pg.buttonGlowFrequency or 0.25
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.procGlow = profile.procGlow or {}
                profile.procGlow.buttonGlowFrequency = val
            end
            if DDingUI.RefreshViewers then DDingUI:RefreshViewers() end
        end,
    }

    -- ============================================================
    -- 보조 강조 효과 (Assist Highlight) 섹션
    -- ============================================================
    ret.args.assistHighlightHeader = {
        type = "header",
        name = L["Assist Highlight"] or "Assist Highlight",
        order = 67,
    }

    -- Assist Highlight Enable
    ret.args.assistHighlightEnabled = {
        type = "toggle",
        name = L["Enable Assist Highlight"] or "Enable Assist Highlight",
        desc = L["Show highlight on the next suggested spell from Assisted Combat"] or "Show highlight on the next suggested spell from Assisted Combat",
        order = 67.1,
        width = "full",
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return ah and ah.enabled
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.enabled = val
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.OnSettingChanged then
                DDingUI.AssistHighlight:OnSettingChanged()
            end
        end,
    }

    -- Assist Highlight Type
    ret.args.assistHighlightType = {
        type = "select",
        name = L["Highlight Type"] or "Highlight Type",
        order = 67.2,
        values = {
            ["flipbook"] = L["Flipbook (Blizzard)"] or "Flipbook (Blizzard)",
            ["lcg"] = L["LibCustomGlow"] or "LibCustomGlow",
        },
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not (ah and ah.enabled)
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return ah and ah.highlightType or "flipbook"
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.highlightType = val
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
                DDingUI.AssistHighlight:RefreshAll()
            end
            if DDingUI.GUI and DDingUI.GUI.SoftRefresh then DDingUI.GUI.SoftRefresh() end
        end,
    }

    -- Flipbook Scale (only for flipbook type)
    ret.args.assistFlipbookScale = {
        type = "range",
        name = L["Flipbook Scale"] or "Flipbook Scale",
        desc = L["Size of the flipbook highlight animation"] or "Size of the flipbook highlight animation",
        order = 67.3,
        min = 1.0, max = 2.5, step = 0.1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not (ah and ah.enabled)
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not ah or ah.highlightType ~= "flipbook"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return ah and ah.flipbookScale or 1.5
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.flipbookScale = val
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
                DDingUI.AssistHighlight:RefreshAll()
            end
        end,
    }

    -- LCG Glow Type (only for lcg type)
    ret.args.assistGlowType = {
        type = "select",
        name = L["Glow Type"] or "Glow Type",
        order = 67.4,
        values = {
            ["Pixel Glow"] = L["Pixel Glow"] or "Pixel Glow",
            ["Autocast Shine"] = L["AutoCast Glow"] or "Autocast Shine",
            ["Action Button Glow"] = L["Action Button Glow"] or "Action Button Glow",
            ["Proc Glow"] = L["Proc Glow"] or "Proc Glow",
            ["Blizzard Glow"] = L["Blizzard Glow"] or "Blizzard Glow",
        },
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not (ah and ah.enabled)
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not ah or ah.highlightType ~= "lcg"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return ah and ah.glowType or "Pixel Glow"
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.glowType = val
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
                DDingUI.AssistHighlight:RefreshAll()
            end
            if DDingUI.GUI and DDingUI.GUI.SoftRefresh then DDingUI.GUI.SoftRefresh() end
        end,
    }

    -- LCG Glow Color
    ret.args.assistGlowColor = {
        type = "color",
        name = L["Assist Glow Color"] or "Assist Glow Color",
        hasAlpha = true,
        order = 67.5,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not (ah and ah.enabled)
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not ah or ah.highlightType ~= "lcg"
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            local c = ah and ah.color or {0.3, 0.7, 1.0, 1}
            return c[1], c[2], c[3], c[4]
        end,
        set = function(_, r, g, b, a)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.color = {r, g, b, a}
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
                DDingUI.AssistHighlight:RefreshAll()
            end
        end,
    }

    -- LCG Pixel Lines (only for lcg + Pixel Glow)
    ret.args.assistGlowLines = {
        type = "range",
        name = L["Pixel Glow Lines"] or "Lines",
        order = 67.6,
        min = 1, max = 30, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not (ah and ah.enabled)
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not ah or ah.highlightType ~= "lcg" or (ah.glowType and ah.glowType ~= "Pixel Glow")
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return ah and ah.lcgLines or 10
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.lcgLines = val
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
                DDingUI.AssistHighlight:RefreshAll()
            end
        end,
    }

    -- LCG Frequency (only for lcg + Pixel Glow)
    ret.args.assistGlowFrequency = {
        type = "range",
        name = L["Pixel Glow Speed"] or "Speed",
        order = 67.7,
        min = 0.01, max = 1.0, step = 0.01,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not (ah and ah.enabled)
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not ah or ah.highlightType ~= "lcg" or (ah.glowType and ah.glowType ~= "Pixel Glow")
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return ah and ah.lcgFrequency or 0.25
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.lcgFrequency = val
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
                DDingUI.AssistHighlight:RefreshAll()
            end
        end,
    }

    -- LCG Thickness (only for lcg + Pixel Glow)
    ret.args.assistGlowThickness = {
        type = "range",
        name = L["Pixel Glow Thickness"] or "Thickness",
        order = 67.8,
        min = 0.5, max = 5, step = 0.5,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not (ah and ah.enabled)
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not ah or ah.highlightType ~= "lcg" or (ah.glowType and ah.glowType ~= "Pixel Glow")
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return ah and ah.lcgThickness or 1
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.lcgThickness = val
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
                DDingUI.AssistHighlight:RefreshAll()
            end
        end,
    }

    -- Assist Highlight: Length
    ret.args.assistHighlightPixelLength = {
        type = "range",
        name = L["Pixel Glow Length"] or "Length",
        order = 67.85,
        min = 1, max = 10, step = 1,
        disabled = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not (ah and ah.enabled)
        end,
        hidden = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return not ah or ah.highlightType ~= "lcg" or (ah.glowType and ah.glowType ~= "Pixel Glow")
        end,
        get = function()
            local viewers = DDingUI.db.profile.viewers
            local ah = viewers and viewers[viewerKey] and viewers[viewerKey].assistHighlight
            return ah and ah.lcgLength or 8
        end,
        set = function(_, val)
            local profile = EnsureViewerSettings(viewerKey)
            if profile then
                profile.assistHighlight = profile.assistHighlight or {}
                profile.assistHighlight.lcgLength = val
            end
            if DDingUI.AssistHighlight and DDingUI.AssistHighlight.RefreshAll then
                DDingUI.AssistHighlight:RefreshAll()
            end
        end,
    }

    -- Disable Edge Glow
    ret.args.disableEdgeGlow = {
        type = "toggle",
        name = L["Disable Edge Glow"],
        desc = L["Disable the rotating edge glow animation on cooldowns"],
        order = 68,
        width = "full",
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].disableEdgeGlow or false
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "disableEdgeGlow", val)
            -- Force re-skin of all icons
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
            if DDingUI.RefreshViewers then
                DDingUI:RefreshViewers()
            end
        end,
    }

    -- Disable Bling Animation
    ret.args.disableBlingAnimation = {
        type = "toggle",
        name = L["Disable Bling Animation"],
        desc = L["Disable the flash/bling animation when cooldowns finish"],
        order = 69,
        width = "full",
        get = function()
            local viewers = DDingUI.db.profile.viewers
            return viewers and viewers[viewerKey] and viewers[viewerKey].disableBlingAnimation or false
        end,
        set = function(_, val)
            SetViewerSetting(viewerKey, "disableBlingAnimation", val)
            -- Force re-skin of all icons
            local viewer = _G[viewerKey]
            if viewer and DDingUI.IconViewers then
                if DDingUI.IconViewers.SkinAllIconsInViewer then
                    DDingUI.IconViewers:SkinAllIconsInViewer(viewer)
                end
            end
            if DDingUI.RefreshViewers then
                DDingUI:RefreshViewers()
            end
        end,
    }

    -- Add spec profile options (at order 0, before header)
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.AddSpecProfileOptions then
        DDingUI.SpecProfiles:AddSpecProfileOptions(
            ret.args,
            "viewers",
            L["Icon Viewers"] or "Icon Viewers",
            0,
            function()
                if DDingUI.RefreshViewers then
                    DDingUI:RefreshViewers()
                end
            end
        )
    end

    return ret
end

-- Build the full viewers options table
local function BuildViewersOptions(order)
    local viewerNames = GetViewerOptions()
    local options = {
        type = "group",
        name = L["Cooldown Manager"],
        order = order,
        childGroups = "tab",
        args = {},
    }

    -- 명시적 순서 지정: Essential → Utility → Buff
    local viewerOrder = {
        { key = "EssentialCooldownViewer", order = 1 },
        { key = "UtilityCooldownViewer", order = 2 },
        { key = "BuffIconCooldownViewer", order = 3 },
    }

    for _, viewer in ipairs(viewerOrder) do
        local viewerKey = viewer.key
        local displayName = viewerNames[viewerKey]
        if displayName then
            options.args[viewerKey] = CreateViewerOptions(viewerKey, displayName, viewer.order)
        end
    end

    return options
end

-- Export functions
ns.CreateViewerOptions = BuildViewersOptions
ns.CreateSingleViewerOptions = CreateViewerOptions  -- [DYNAMIC] 개별 뷰어 옵션 빌더 (GroupSystemOptions에서 재사용)


