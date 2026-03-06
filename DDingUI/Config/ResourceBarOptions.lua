local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = ns.L or LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME, true)
local LSM = LibStub("LibSharedMedia-3.0")
local buildVersion = select(4, GetBuildInfo())

-- [REFACTOR] AceGUI → StyleLib: AceConfigRegistry 폴백 제거
local function RefreshOptions()
    DDingUI:RefreshConfigGUI(true) -- soft refresh: 스크롤/탭 위치 유지
end

-- Debounced RefreshOptions: only fires after 0.5s of no calls (prevents input field losing focus)
local _markerRefreshTimer
local function DebouncedRefresh()
    if _markerRefreshTimer then _markerRefreshTimer:Cancel() end
    _markerRefreshTimer = C_Timer.NewTimer(0.5, RefreshOptions)
end

-- Migrate old marker format { {value=60, color={...}, width=2} } → { 60 }
-- Returns clean numeric array and auto-saves if migration was needed
local function MigrateMarkers(cfgPath)
    local m = cfgPath.markers
    if not m or #m == 0 then return m end
    local needsMigration = false
    local clean = {}
    for _, v in ipairs(m) do
        if type(v) == "table" and v.value then
            needsMigration = true
            local num = tonumber(v.value)
            if num and num > 0 then table.insert(clean, num) end
        elseif type(v) == "number" then
            table.insert(clean, v)
        else
            needsMigration = true -- skip garbage entries
        end
    end
    if needsMigration then
        table.sort(clean)
        cfgPath.markers = clean
    end
    return cfgPath.markers
end

-- Get clean marker value at index (handles old table format)
local function GetMarkerValue(markers, idx)
    if not markers or not markers[idx] then return nil end
    local v = markers[idx]
    if type(v) == "table" and v.value then return tonumber(v.value) end
    if type(v) == "number" then return v end
    return nil
end

-- Mark spec profiles as dirty when config value changes
local function MarkSpecDirty()
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end
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

-- Color reset button helper (기본값 되돌리기)
local function MakeColorReset(order, resetFunc)
    return {
        type = "execute",
        name = L["Reset"] or "Reset",
        desc = L["Reset to Default"] or "Reset to Default",
        order = order,
        width = 0.3,
        func = function()
            resetFunc()
            RefreshOptions()
        end,
    }
end

local function CreateResourceBarOptions()
    local options = {
        type = "group",
        name = L["Resource Bars"] or "Resource Bars",
        order = 4,
        childGroups = "tab",
        args = {
            primary = {
                type = "group",
                name = L["Primary"] or "Primary",
                order = 1,
                args = {
                    header = {
                        type = "header",
                        name = L["Primary Power Bar Settings"] or "Primary Power Bar Settings",
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = L["Enable Primary Power Bar"] or "Enable Primary Power Bar",
                        desc = L["Show your main resource (mana, energy, rage, etc.)"] or "Show your main resource (mana, energy, rage, etc.)",
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.powerBar.enabled end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.enabled = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    smoothProgress = {
                        type = "toggle",
                        name = L["Smooth Progress"] or "Smooth Progress",
                        desc = L["Enable smooth animation for bar updates (requires WoW 12.0+)"] or "Enable smooth animation for bar updates (requires WoW 12.0+)",
                        width = "full",
                        order = 3,
                        hidden = function() return buildVersion < 120000 end,
                        get = function() return DDingUI.db.profile.powerBar.smoothProgress end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.smoothProgress = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    updateFrequency = {
                        type = "range",
                        name = L["Update Frequency"] or "Update Frequency",
                        desc = "|cffff0000" .. (L["WARNING: Lower values = more frequent updates = higher CPU usage!"] or "WARNING: Lower values = more frequent updates = higher CPU usage!") .. "|r " .. (L["How often to update the bar (in seconds)."] or "How often to update the bar (in seconds)."),
                        order = 4,
                        width = "full",
                        min = 0.01,
                        max = 0.5,
                        step = 0.01,
                        get = function() return DDingUI.db.profile.powerBar.updateFrequency end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.updateFrequency = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    positionHeader = {
                        type = "header",
                        name = L["Position & Size"] or "Position & Size",
                        order = 10,
                    },
                    attachTo = {
                        type = "select",
                        name = L["Attach To"] or "Attach To",
                        desc = L["Which frame to attach this bar to"] or "Which frame to attach this bar to",
                        order = 11,
                        width = "double",
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
                            -- 커스텀 값이 목록에 없으면 추가
                            local current = DDingUI.db.profile.powerBar.attachTo
                            if current and not opts[current] then
                                opts[current] = current .. " (Custom)"
                            end
                            return opts
                        end,
                        get = function() return DDingUI.db.profile.powerBar.attachTo end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.attachTo = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    pickFrame = {
                        type = "execute",
                        name = L["Pick Frame"] or "프레임 선택",
                        desc = L["Click to select a frame from the UI"] or "UI에서 프레임을 클릭하여 선택",
                        order = 11.05,
                        width = "half",
                        func = function()
                            DDingUI:StartFramePicker(function(frameName)
                                if frameName then
                                    DDingUI.db.profile.powerBar.attachTo = frameName
                                    DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                                end
                            end)
                        end,
                    },
                    anchorPoint = {
                        type = "select",
                        name = L["Anchor Point"] or "Anchor Point",
                        desc = L["Which point on the anchor frame to attach to"] or "Which point on the anchor frame to attach to",
                        order = 11.1,
                        width = "normal",
                        values = {
                            TOPLEFT = L["Top Left"] or "Top Left",
                            TOP = L["Top"] or "Top",
                            TOPRIGHT = L["Top Right"] or "Top Right",
                            LEFT = L["Left"] or "Left",
                            CENTER = L["Center"] or "Center",
                            RIGHT = L["Right"] or "Right",
                            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left",
                            BOTTOM = L["Bottom"] or "Bottom",
                            BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
                        },
                        get = function() return DDingUI.db.profile.powerBar.anchorPoint or "CENTER" end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.anchorPoint = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    selfPoint = {
                        type = "select",
                        name = L["Self Anchor"] or "기준점",
                        desc = L["Which point of this bar to use as the anchor reference"] or "이 바의 어느 지점을 기준으로 위치를 잡을지",
                        order = 11.15,
                        width = "normal",
                        values = {
                            TOPLEFT = L["Top Left"] or "Top Left",
                            TOP = L["Top"] or "Top",
                            TOPRIGHT = L["Top Right"] or "Top Right",
                            LEFT = L["Left"] or "Left",
                            CENTER = L["Center"] or "Center",
                            RIGHT = L["Right"] or "Right",
                            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left",
                            BOTTOM = L["Bottom"] or "Bottom",
                            BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
                        },
                        get = function() return DDingUI.db.profile.powerBar.selfPoint or "CENTER" end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.selfPoint = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    frameStrata = {
                        type = "select",
                        name = L["Frame Strata"] or "Frame Strata",
                        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar. Higher strata appear on top of lower ones.",
                        order = 11.2,
                        width = "normal",
                        values = {
                            BACKGROUND = "BACKGROUND",
                            LOW = "LOW",
                            MEDIUM = "MEDIUM",
                            HIGH = "HIGH",
                            DIALOG = "DIALOG",
                        },
                        get = function() return DDingUI.db.profile.powerBar.frameStrata or "MEDIUM" end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.frameStrata = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    height = {
                        type = "range",
                        name = L["Height"] or "Height",
                        order = 12,
                        width = "normal",
                        min = 2, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.height end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.height = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    width = {
                        type = "range",
                        name = L["Width"] or "Width",
                        desc = L["0 = automatic width based on icons"] or "0 = automatic width based on icons",
                        order = 13,
                        width = "normal",
                        min = 0, max = 1000, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.width end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.width = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    offsetY = {
                        type = "range",
                        name = L["Vertical Offset"] or "Vertical Offset",
                        desc = L["Distance from the icon viewer"] or "Distance from the icon viewer",
                        order = 14,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.offsetY end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.offsetY = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    offsetX = {
                        type = "range",
                        name = L["Horizontal Offset"] or "Horizontal Offset",
                        desc = L["Horizontal distance from the anchor point"] or "Horizontal distance from the anchor point",
                        order = 15,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.offsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.offsetX = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },

                    noSecondaryHeader = {
                        type = "header",
                        name = L["No Secondary Resource Size"] or "No Secondary Resource Size",
                        order = 16,
                    },
                    noSecondaryDesc = {
                        type = "description",
                        name = L["These settings are used when your class has no secondary resource (e.g., Mage, Hunter, Priest)."] or "These settings are used when your class has no secondary resource (e.g., Mage, Hunter, Priest).",
                        order = 16.1,
                    },
                    useNoSecondarySize = {
                        type = "toggle",
                        name = L["Use Different Size When No Secondary"] or "Use Different Size When No Secondary",
                        desc = "Use different width/height when there is no secondary resource or when secondary bar is disabled",
                        order = 16.2,
                        width = "full",
                        get = function() return DDingUI.db.profile.powerBar.useNoSecondarySize end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.useNoSecondarySize = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    noSecondaryHeight = {
                        type = "range",
                        name = L["Height (No Secondary)"] or "Height (No Secondary)",
                        desc = L["Height when there is no secondary resource"] or "Height when there is no secondary resource",
                        order = 16.3,
                        width = "normal",
                        min = 2, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.noSecondaryHeight or DDingUI.db.profile.powerBar.height or 6 end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.noSecondaryHeight = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                        disabled = function() return not DDingUI.db.profile.powerBar.useNoSecondarySize end,
                    },
                    noSecondaryWidth = {
                        type = "range",
                        name = L["Width (No Secondary)"] or "Width (No Secondary)",
                        desc = L["Width when there is no secondary resource (0 = automatic)"] or "Width when there is no secondary resource (0 = automatic)",
                        order = 16.4,
                        width = "normal",
                        min = 0, max = 1000, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.noSecondaryWidth or DDingUI.db.profile.powerBar.width or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.noSecondaryWidth = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                        disabled = function() return not DDingUI.db.profile.powerBar.useNoSecondarySize end,
                    },
                    noSecondaryOffsetY = {
                        type = "range",
                        name = L["Y Offset (No Secondary)"] or "Y Offset (No Secondary)",
                        desc = L["Vertical offset when there is no secondary resource (bar anchors from bottom)"] or "Vertical offset when there is no secondary resource (bar anchors from bottom)",
                        order = 16.5,
                        width = "normal",
                        min = -200, max = 200, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.noSecondaryOffsetY or 27 end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.noSecondaryOffsetY = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                        disabled = function() return not DDingUI.db.profile.powerBar.useNoSecondarySize end,
                    },

                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"] or "Appearance",
                        order = 20,
                    },
                    texture = {
                        type = "select",
                        name = L["Bar Texture"] or "Bar Texture",
                        order = 21,
                        width = "full",
                        values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar or {},
                        get = function() 
                            local override = DDingUI.db.profile.powerBar.texture
                            if override and override ~= "" then
                                return override
                            end
                            -- Return global texture name when override is nil
                            return DDingUI.db.profile.general.globalTexture or "Meli"
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.texture = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    borderSize = {
                        type = "range",
                        name = L["Border Size"] or "Border Size",
                        desc = L["Size of the border around the resource bar"] or "Size of the border around the resource bar",
                        order = 22,
                        width = "normal",
                        min = 0, max = 5, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.borderSize end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.borderSize = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    borderColor = {
                        type = "color",
                        name = L["Border Color"] or "Border Color",
                        desc = L["Color of the border around the resource bar"] or "Color of the border around the resource bar",
                        order = 23,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerBar.borderColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0, 0, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerBar.borderColor = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    
                    displayHeader = {
                        type = "header",
                        name = L["Display Options"] or "Display Options",
                        order = 30,
                    },
                    showText = {
                        type = "toggle",
                        name = L["Show Resource Number"] or "Show Resource Number",
                        desc = L["Display current resource amount as text"] or "Display current resource amount as text",
                        order = 31,
                        width = "normal",
                        get = function() return DDingUI.db.profile.powerBar.showText end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.showText = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    showManaAsPercent = {
                        type = "toggle",
                        name = L["Show Mana as Percent"] or "Show Mana as Percent",
                        desc = L["Display mana as percentage instead of raw value"] or "Display mana as percentage instead of raw value",
                        order = 32,
                        width = "normal",
                        get = function() return DDingUI.db.profile.powerBar.showManaAsPercent end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.showManaAsPercent = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textPrecision = {
                        type = "select",
                        name = L["Decimal Places"] or "Decimal Places",
                        desc = L["Number of decimal places for percentage display"] or "Number of decimal places for percentage display",
                        order = 32.5,
                        width = "normal",
                        hidden = function() return not DDingUI.db.profile.powerBar.showManaAsPercent end,
                        values = {
                            [0] = "0 (50%)",
                            [1] = "1 (50.5%)",
                            [2] = "2 (50.55%)",
                        },
                        get = function() return DDingUI.db.profile.powerBar.textPrecision or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.textPrecision = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    showPercentSign = {
                        type = "toggle",
                        name = L["Show % Sign"] or "Show % Sign",
                        desc = L["Display % symbol after the percentage value"] or "Display % symbol after the percentage value",
                        order = 32.6,
                        width = "normal",
                        hidden = function() return not DDingUI.db.profile.powerBar.showManaAsPercent end,
                        get = function() return DDingUI.db.profile.powerBar.showPercentSign end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.showPercentSign = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    showTicks = {
                        type = "toggle",
                        name = L["Show Ticks"] or "Show Ticks",
                        desc = L["Show segment markers for combo points, chi, etc."] or "Show segment markers for combo points, chi, etc.",
                        order = 33,
                        width = "normal",
                        get = function() return DDingUI.db.profile.powerBar.showTicks end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.showTicks = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    tickWidth = {
                        type = "range",
                        name = L["Tick Width"] or "Tick Width",
                        desc = L["Width of the segment markers"] or "Width of the segment markers",
                        order = 33.1,
                        width = "normal",
                        min = 1, max = 5, step = 1,
                        hidden = function() return not DDingUI.db.profile.powerBar.showTicks end,
                        get = function() return DDingUI.db.profile.powerBar.tickWidth or 2 end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.tickWidth = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    hideWhenMana = {
                        type = "toggle",
                        name = L["Hide Bar When Mana (DPS Only)"] or "Hide Bar When Mana (DPS Only)",
                        desc = L["Hide the resource bar when current power is mana and specialization is DPS. Healers will still see mana."] or "Hide the resource bar when current power is mana and specialization is DPS. Healers will still see mana.",
                        order = 33.5,
                        width = "normal",
                        get = function() return DDingUI.db.profile.powerBar.hideWhenMana end,
                        set = function(_, val)
                            if InCombatLockdown() then
                                return
                            end
                            DDingUI.db.profile.powerBar.hideWhenMana = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    hideBarShowText = {
                        type = "toggle",
                        name = L["Hide Bar, Show Text Only"] or "Hide Bar, Show Text Only",
                        desc = L["Hide the resource bar visual but keep the text visible"] or "Hide the resource bar visual but keep the text visible",
                        order = 33.6,
                        width = "normal",
                        get = function() return DDingUI.db.profile.powerBar.hideBarShowText end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.hideBarShowText = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textFont = {
                        type = "select",
                        name = L["Font"] or "Font",
                        desc = L["Font used for power bar text"] or "Font used for power bar text",
                        order = 33.7,
                        width = "full",
                        dialogControl = "LSM30_Font",
                        values = function() return DDingUI:GetFontValues() end,
                        get = function()
                            return DDingUI.db.profile.powerBar.textFont or DDingUI.DEFAULT_FONT_NAME
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.textFont = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textSize = {
                        type = "range",
                        name = L["Text Size"] or "Text Size",
                        order = 34,
                        width = "normal",
                        min = 6, max = 24, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.textSize end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.textSize = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textX = {
                        type = "range",
                        name = L["Text Horizontal Offset"] or "Text Horizontal Offset",
                        order = 35,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.textX end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.textX = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textY = {
                        type = "range",
                        name = L["Text Vertical Offset"] or "Text Vertical Offset",
                        order = 36,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.textY end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.textY = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },

                    -- ========== THRESHOLD COLORS ==========
                    thresholdHeader = {
                        type = "header",
                        name = L["Threshold Colors"] or "Threshold Colors",
                        order = 40,
                    },
                    thresholdDesc = {
                        type = "description",
                        name = L["Change bar color when resource reaches certain values. Higher priority thresholds override lower ones."] or "Change bar color when resource reaches certain values. Higher priority thresholds override lower ones.",
                        order = 40.1,
                    },
                    thresholdEnabled = {
                        type = "toggle",
                        name = L["Enable Threshold Colors"] or "Enable Threshold Colors",
                        width = "full",
                        order = 41,
                        get = function()
                            return DDingUI.db.profile.powerBar.thresholdEnabled
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.thresholdEnabled = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    thresholdInfo = {
                        type = "description",
                        name = "|cff888888" .. (L["Colors change at 35% (red) and 70% (yellow) thresholds."] or "Colors change at 35% (red) and 70% (yellow) thresholds.") .. "|r",
                        order = 42,
                        fontSize = "small",
                    },
                    -- Custom Markers
                    markerHeader = {
                        type = "header",
                        name = L["Custom Markers"] or "Custom Markers",
                        order = 50,
                    },
                    markerPositions = {
                        type = "input",
                        name = L["Marker Positions"] or "Marker Positions",
                        desc = L["Marker Positions Desc"] or "Enter resource values separated by commas. Example: 30, 70, 100",
                        order = 51,
                        width = 1.2,
                        get = function()
                            local m = MigrateMarkers(DDingUI.db.profile.powerBar)
                            if m and #m > 0 then
                                local strs = {}
                                for _, v in ipairs(m) do
                                    table.insert(strs, tostring(v))
                                end
                                return table.concat(strs, ", ")
                            end
                            return ""
                        end,
                        set = function(_, val)
                            local cfg = DDingUI.db.profile.powerBar
                            local oldMarkers = MigrateMarkers(cfg) or {}
                            local oldColors = cfg.markerBarColors or {}
                            local colorMap = {}
                            for i, mVal in ipairs(oldMarkers) do
                                if oldColors[i] then colorMap[mVal] = oldColors[i] end
                            end

                            local values = {}
                            for numStr in string.gmatch(val, "([%d%.]+)") do
                                local num = tonumber(numStr)
                                if num and num > 0 then
                                    table.insert(values, num)
                                end
                            end
                            table.sort(values)
                            cfg.markers = values

                            local newColors = {}
                            for i, mVal in ipairs(values) do
                                if colorMap[mVal] then newColors[i] = colorMap[mVal] end
                            end
                            cfg.markerBarColors = newColors

                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                            DebouncedRefresh()
                        end,
                    },
                    markerColor = {
                        type = "color",
                        name = L["Marker Color"] or "Marker Color",
                        order = 52,
                        width = 0.5,
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerBar.markerColor
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1, 1, 1, 0.8
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerBar.markerColor = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    markerWidth = {
                        type = "range",
                        name = L["Marker Width"] or "Marker Width",
                        order = 53,
                        width = 0.7,
                        min = 1, max = 5, step = 1,
                        get = function() return DDingUI.db.profile.powerBar.markerWidth or 2 end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.markerWidth = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    markerColorChange = {
                        type = "toggle",
                        name = L["Change Bar Color at Marker"] or "Change Bar Color at Marker",
                        desc = L["Change the bar color when resource exceeds a marker value"] or "Change the bar color when resource exceeds a marker value",
                        order = 54,
                        width = "full",
                        hidden = function()
                            local m = DDingUI.db.profile.powerBar.markers
                            return not m or #m == 0
                        end,
                        get = function() return DDingUI.db.profile.powerBar.markerColorChange end,
                        set = function(_, val)
                            DDingUI.db.profile.powerBar.markerColorChange = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                            RefreshOptions()
                        end,
                    },
                    markerBarColorDesc = {
                        type = "description",
                        name = "|cff888888" .. (L["Color applied when resource >= marker value. Highest matched marker wins."] or "Color applied when resource >= marker value. Highest matched marker wins.") .. "|r",
                        order = 54.1,
                        fontSize = "small",
                        hidden = function()
                            local cfg = DDingUI.db.profile.powerBar
                            return not cfg.markerColorChange or not cfg.markers or #cfg.markers == 0
                        end,
                    },
                    markerBarColor1 = {
                        type = "color", name = "", order = 54.2, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 1 end,
                        get = function()
                            local c = DDingUI.db.profile.powerBar.markerBarColors[1]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1, 0.3, 0.3, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerBar.markerBarColors[1] = {r, g, b, a}
                            DDingUI:UpdatePowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor1Label = {
                        type = "description", order = 54.21, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 1 end,
                        name = function()
                            local m = DDingUI.db.profile.powerBar.markers
                            local v = GetMarkerValue(m, 1); return v and (">= " .. v) or ""
                        end,
                    },
                    markerBarColor2 = {
                        type = "color", name = "", order = 54.3, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 2 end,
                        get = function()
                            local c = DDingUI.db.profile.powerBar.markerBarColors[2]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1, 1, 0.3, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerBar.markerBarColors[2] = {r, g, b, a}
                            DDingUI:UpdatePowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor2Label = {
                        type = "description", order = 54.31, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 2 end,
                        name = function()
                            local m = DDingUI.db.profile.powerBar.markers
                            local v = GetMarkerValue(m, 2); return v and (">= " .. v) or ""
                        end,
                    },
                    markerBarColor3 = {
                        type = "color", name = "", order = 54.4, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 3 end,
                        get = function()
                            local c = DDingUI.db.profile.powerBar.markerBarColors[3]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 0.3, 1, 0.3, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerBar.markerBarColors[3] = {r, g, b, a}
                            DDingUI:UpdatePowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor3Label = {
                        type = "description", order = 54.41, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 3 end,
                        name = function()
                            local m = DDingUI.db.profile.powerBar.markers
                            local v = GetMarkerValue(m, 3); return v and (">= " .. v) or ""
                        end,
                    },
                    markerBarColor4 = {
                        type = "color", name = "", order = 54.5, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 4 end,
                        get = function()
                            local c = DDingUI.db.profile.powerBar.markerBarColors[4]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 0.3, 0.7, 1, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerBar.markerBarColors[4] = {r, g, b, a}
                            DDingUI:UpdatePowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor4Label = {
                        type = "description", order = 54.51, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 4 end,
                        name = function()
                            local m = DDingUI.db.profile.powerBar.markers
                            local v = GetMarkerValue(m, 4); return v and (">= " .. v) or ""
                        end,
                    },
                    markerBarColor5 = {
                        type = "color", name = "", order = 54.6, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 5 end,
                        get = function()
                            local c = DDingUI.db.profile.powerBar.markerBarColors[5]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1, 0.5, 1, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerBar.markerBarColors[5] = {r, g, b, a}
                            DDingUI:UpdatePowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor5Label = {
                        type = "description", order = 54.61, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.powerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 5 end,
                        name = function()
                            local m = DDingUI.db.profile.powerBar.markers
                            local v = GetMarkerValue(m, 5); return v and (">= " .. v) or ""
                        end,
                    },
                },
            },
            secondary = {
                type = "group",
                name = L["Secondary"] or "Secondary",
                order = 2,
                args = {
                    header = {
                        type = "header",
                        name = L["Secondary Power Bar Settings"] or "Secondary Power Bar Settings",
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = L["Enable Secondary Power Bar"] or "Enable Secondary Power Bar",
                        desc = L["Show your secondary resource (combo points, chi, runes, etc.)"] or "Show your secondary resource (combo points, chi, runes, etc.)",
                        width = "full",
                        order = 2,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.enabled end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.enabled = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    smoothProgress = {
                        type = "toggle",
                        name = L["Smooth Progress"] or "Smooth Progress",
                        desc = L["Enable smooth animation for bar updates (requires WoW 12.0+)"] or "Enable smooth animation for bar updates (requires WoW 12.0+)",
                        width = "full",
                        order = 3,
                        hidden = function() return buildVersion < 120000 end,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.smoothProgress end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.smoothProgress = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    updateFrequency = {
                        type = "range",
                        name = L["Update Frequency"] or "Update Frequency",
                        desc = "|cffff0000" .. (L["WARNING: Lower values = more frequent updates = higher CPU usage!"] or "WARNING: Lower values = more frequent updates = higher CPU usage!") .. "|r " .. (L["How often to update the bar (in seconds)."] or "How often to update the bar (in seconds)."),
                        order = 4,
                        width = "full",
                        min = 0.01,
                        max = 0.5,
                        step = 0.01,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.updateFrequency end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.updateFrequency = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    positionHeader = {
                        type = "header",
                        name = L["Position & Size"] or "Position & Size",
                        order = 10,
                    },
                    attachTo = {
                        type = "select",
                        name = L["Attach To"] or "Attach To",
                        desc = L["Which frame to attach this bar to"] or "Which frame to attach this bar to",
                        order = 11,
                        width = "double",
                        values = function()
                            local opts = {}
                            opts["UIParent"] = L["Screen (UIParent)"] or "Screen (UIParent)"
                            opts["DDingUIPowerBar"] = L["Primary Power Bar"] or "주 자원바"
                            if DDingUI.db.profile.unitFrames and DDingUI.db.profile.unitFrames.enabled then
                                opts["DDingUI_Player"] = L["Player Frame (Custom)"] or "Player Frame (Custom)"
                            end
                            opts["PlayerFrame"] = L["Default Player Frame"] or "Default Player Frame"
                            local viewerOpts = GetViewerOptions()
                            for k, v in pairs(viewerOpts) do
                                opts[k] = v
                            end
                            local current = DDingUI.db.profile.secondaryPowerBar.attachTo
                            if current and not opts[current] then
                                opts[current] = current .. " (Custom)"
                            end
                            return opts
                        end,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.attachTo end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.attachTo = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    pickFrame2 = {
                        type = "execute",
                        name = L["Pick Frame"] or "프레임 선택",
                        desc = L["Click to select a frame from the UI"] or "UI에서 프레임을 클릭하여 선택",
                        order = 11.05,
                        width = "half",
                        func = function()
                            DDingUI:StartFramePicker(function(frameName)
                                if frameName then
                                    DDingUI.db.profile.secondaryPowerBar.attachTo = frameName
                                    DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                                end
                            end)
                        end,
                    },
                    anchorPoint = {
                        type = "select",
                        name = L["Anchor Point"] or "Anchor Point",
                        desc = L["Which point on the anchor frame to attach to"] or "Which point on the anchor frame to attach to",
                        order = 11.1,
                        width = "normal",
                        values = {
                            TOPLEFT = L["Top Left"] or "Top Left",
                            TOP = L["Top"] or "Top",
                            TOPRIGHT = L["Top Right"] or "Top Right",
                            LEFT = L["Left"] or "Left",
                            CENTER = L["Center"] or "Center",
                            RIGHT = L["Right"] or "Right",
                            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left",
                            BOTTOM = L["Bottom"] or "Bottom",
                            BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
                        },
                        get = function() return DDingUI.db.profile.secondaryPowerBar.anchorPoint or "CENTER" end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.anchorPoint = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    selfPoint = {
                        type = "select",
                        name = L["Self Point"] or "기준점",
                        desc = L["Which point of the bar itself is used for anchoring"] or "이 바의 어느 지점을 기준으로 앵커할지 선택",
                        order = 11.15,
                        width = "normal",
                        values = {
                            TOPLEFT = L["Top Left"] or "Top Left",
                            TOP = L["Top"] or "Top",
                            TOPRIGHT = L["Top Right"] or "Top Right",
                            LEFT = L["Left"] or "Left",
                            CENTER = L["Center"] or "Center",
                            RIGHT = L["Right"] or "Right",
                            BOTTOMLEFT = L["Bottom Left"] or "Bottom Left",
                            BOTTOM = L["Bottom"] or "Bottom",
                            BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
                        },
                        get = function() return DDingUI.db.profile.secondaryPowerBar.selfPoint or "CENTER" end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.selfPoint = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    frameStrata = {
                        type = "select",
                        name = L["Frame Strata"] or "Frame Strata",
                        desc = L["Controls the drawing layer of this bar. Higher strata appear on top of lower ones."] or "Controls the drawing layer of this bar. Higher strata appear on top of lower ones.",
                        order = 11.2,
                        width = "normal",
                        values = {
                            BACKGROUND = "BACKGROUND",
                            LOW = "LOW",
                            MEDIUM = "MEDIUM",
                            HIGH = "HIGH",
                            DIALOG = "DIALOG",
                        },
                        get = function() return DDingUI.db.profile.secondaryPowerBar.frameStrata or "MEDIUM" end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.frameStrata = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    height = {
                        type = "range",
                        name = L["Height"] or "Height",
                        order = 12,
                        width = "normal",
                        min = 2, max = 30, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.height end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.height = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    width = {
                        type = "range",
                        name = L["Width"] or "Width",
                        desc = L["0 = automatic width based on icons"] or "0 = automatic width based on icons",
                        order = 13,
                        width = "normal",
                        min = 0, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.width end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.width = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    offsetY = {
                        type = "range",
                        name = L["Vertical Offset"] or "Vertical Offset",
                        desc = L["Distance from the icon viewer"] or "Distance from the icon viewer",
                        order = 14,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.offsetY end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.offsetY = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    offsetX = {
                        type = "range",
                        name = L["Horizontal Offset"] or "Horizontal Offset",
                        desc = L["Horizontal distance from the anchor point"] or "Horizontal distance from the anchor point",
                        order = 15,
                        width = "full",
                        min = -500, max = 500, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.offsetX or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.offsetX = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    
                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"] or "Appearance",
                        order = 20,
                    },
                    texture = {
                        type = "select",
                        name = L["Fill Texture"] or "채움 텍스쳐",
                        desc = L["Texture for the filled portion of the bar"] or "바의 차오르는 부분 텍스쳐",
                        order = 21,
                        width = "full",
                        values = AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar or {},
                        get = function()
                            local override = DDingUI.db.profile.secondaryPowerBar.texture
                            if override and override ~= "" then
                                return override
                            end
                            -- Return global texture name when override is nil
                            return DDingUI.db.profile.general.globalTexture or "Meli"
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.texture = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    bgTexture = {
                        type = "select",
                        name = L["Background Texture"] or "배경 텍스쳐",
                        desc = L["Texture for the background of the bar (leave empty for solid color)"] or "바 배경 텍스쳐 (비워두면 단색)",
                        order = 21.5,
                        width = "full",
                        values = function()
                            local vals = { [""] = L["None (Solid Color)"] or "없음 (단색)" }
                            if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar then
                                for k, v in pairs(AceGUIWidgetLSMlists.statusbar) do
                                    vals[k] = v
                                end
                            end
                            return vals
                        end,
                        get = function()
                            return DDingUI.db.profile.secondaryPowerBar.bgTexture or ""
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.bgTexture = (val ~= "") and val or nil
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    borderSize = {
                        type = "range",
                        name = L["Border Size"] or "Border Size",
                        desc = L["Size of the border around the resource bar"] or "Size of the border around the resource bar",
                        order = 22,
                        width = "normal",
                        min = 0, max = 5, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.borderSize end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.borderSize = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    borderColor = {
                        type = "color",
                        name = L["Border Color"] or "Border Color",
                        desc = L["Color of the border around the resource bar"] or "Color of the border around the resource bar",
                        order = 23,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.borderColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0, 0, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.borderColor = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    
                    displayHeader = {
                        type = "header",
                        name = L["Display Options"] or "Display Options",
                        order = 30,
                    },
                    showText = {
                        type = "toggle",
                        name = L["Show Resource Number"] or "Show Resource Number",
                        desc = L["Display current resource amount as text"] or "Display current resource amount as text",
                        order = 31,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.showText end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.showText = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    showManaAsPercent = {
                        type = "toggle",
                        name = L["Show Mana as Percent"] or "Show Mana as Percent",
                        desc = L["Display mana as percentage instead of raw value for mana-based secondary resources"] or "Display mana as percentage instead of raw value for mana-based secondary resources",
                        order = 31.5,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.showManaAsPercent end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.showManaAsPercent = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textPrecision = {
                        type = "select",
                        name = L["Decimal Places"] or "Decimal Places",
                        desc = L["Number of decimal places for percentage display"] or "Number of decimal places for percentage display",
                        order = 31.6,
                        width = "normal",
                        values = {
                            [0] = "0 (50%)",
                            [1] = "1 (50.5%)",
                            [2] = "2 (50.55%)",
                        },
                        get = function() return DDingUI.db.profile.secondaryPowerBar.textPrecision or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.textPrecision = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    showPercentSign = {
                        type = "toggle",
                        name = L["Show % Sign"] or "Show % Sign",
                        desc = L["Display % symbol after the percentage value"] or "Display % symbol after the percentage value",
                        order = 31.7,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.showPercentSign end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.showPercentSign = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    showTicks = {
                        type = "toggle",
                        name = L["Show Ticks"] or "Show Ticks",
                        desc = L["Show segment markers between resources"] or "Show segment markers between resources",
                        order = 32,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.showTicks end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.showTicks = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    tickWidth = {
                        type = "range",
                        name = L["Tick Width"] or "Tick Width",
                        desc = L["Width of the segment markers"] or "Width of the segment markers",
                        order = 32.1,
                        width = "normal",
                        min = 1, max = 5, step = 1,
                        hidden = function() return not DDingUI.db.profile.secondaryPowerBar.showTicks end,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.tickWidth or 2 end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.tickWidth = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    hideWhenMana = {
                        type = "toggle",
                        name = L["Hide Bar When Mana (DPS Only)"] or "Hide Bar When Mana (DPS Only)",
                        desc = L["Hide the bar when current power is mana and specialization is DPS. Healers will still see mana."] or "Hide the bar when current power is mana and specialization is DPS. Healers will still see mana.",
                        order = 32.3,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.hideWhenMana end,
                        set = function(_, val)
                            if InCombatLockdown() then
                                return
                            end
                            DDingUI.db.profile.secondaryPowerBar.hideWhenMana = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    hideBarShowText = {
                        type = "toggle",
                        name = L["Hide Bar, Show Text Only"] or "Hide Bar, Show Text Only",
                        desc = L["Hide the resource bar visual but keep the text visible"] or "Hide the resource bar visual but keep the text visible",
                        order = 32.5,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.hideBarShowText end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.hideBarShowText = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    -- No Primary Resource Size (주자원 마나 숨김 시 보조자원 승격)
                    noPrimaryHeader = {
                        type = "header",
                        name = L["No Primary Resource Size"] or "No Primary Resource Size",
                        order = 33,
                    },
                    noPrimaryDesc = {
                        type = "description",
                        name = L["When primary bar is hidden (mana), use these settings for the secondary bar. Useful for Enhancement Shaman, Balance Druid, etc."] or "When primary bar is hidden (mana), use these settings for the secondary bar. Useful for Enhancement Shaman, Balance Druid, etc.",
                        order = 33.1,
                    },
                    useNoPrimarySize = {
                        type = "toggle",
                        name = L["Use Different Size When No Primary"] or "Use Different Size When No Primary",
                        desc = L["Use different size/position when primary bar is hidden due to mana or disabled"] or "Use different size/position when primary bar is hidden due to mana or disabled",
                        order = 33.2,
                        width = "full",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.useNoPrimarySize end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.useNoPrimarySize = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    noPrimaryHeight = {
                        type = "range",
                        name = L["Height (No Primary)"] or "Height (No Primary)",
                        desc = L["Height when primary bar is hidden"] or "Height when primary bar is hidden",
                        order = 33.3,
                        width = "normal",
                        min = 2, max = 100, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.noPrimaryHeight or DDingUI.db.profile.secondaryPowerBar.height or 4 end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.noPrimaryHeight = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.useNoPrimarySize end,
                    },
                    noPrimaryWidth = {
                        type = "range",
                        name = L["Width (No Primary)"] or "Width (No Primary)",
                        desc = L["Width when primary bar is hidden (0 = automatic)"] or "Width when primary bar is hidden (0 = automatic)",
                        order = 33.4,
                        width = "normal",
                        min = 0, max = 1000, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.noPrimaryWidth or DDingUI.db.profile.secondaryPowerBar.width or 0 end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.noPrimaryWidth = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.useNoPrimarySize end,
                    },
                    noPrimaryOffsetY = {
                        type = "range",
                        name = L["Y Offset (No Primary)"] or "Y Offset (No Primary)",
                        desc = L["Vertical offset when primary bar is hidden"] or "Vertical offset when primary bar is hidden",
                        order = 33.5,
                        width = "normal",
                        min = -200, max = 200, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.noPrimaryOffsetY or 10 end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.noPrimaryOffsetY = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.useNoPrimarySize end,
                    },

                    textFont = {
                        type = "select",
                        name = L["Font"] or "Font",
                        desc = L["Font used for secondary power bar text"] or "Font used for secondary power bar text",
                        order = 34,
                        width = "full",
                        dialogControl = "LSM30_Font",
                        values = function() return DDingUI:GetFontValues() end,
                        get = function()
                            return DDingUI.db.profile.secondaryPowerBar.textFont or DDingUI.DEFAULT_FONT_NAME
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.textFont = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textSize = {
                        type = "range",
                        name = L["Text Size"] or "Text Size",
                        order = 33,
                        width = "normal",
                        min = 6, max = 24, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.textSize end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.textSize = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textX = {
                        type = "range",
                        name = L["Text Horizontal Offset"] or "Text Horizontal Offset",
                        order = 34,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.textX end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.textX = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    textY = {
                        type = "range",
                        name = L["Text Vertical Offset"] or "Text Vertical Offset",
                        order = 35,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.textY end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.textY = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },

                    -- ========== THRESHOLD COLORS ==========
                    thresholdHeader = {
                        type = "header",
                        name = L["Threshold Colors"] or "Threshold Colors",
                        order = 36,
                    },
                    thresholdEnabled2 = {
                        type = "toggle",
                        name = L["Enable Threshold Colors"] or "Enable Threshold Colors",
                        width = "full",
                        order = 37,
                        get = function()
                            return DDingUI.db.profile.secondaryPowerBar.thresholdEnabled
                        end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.thresholdEnabled = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    thresholdInfo2 = {
                        type = "description",
                        name = "|cff888888" .. (L["Colors change at 35% (red) and 70% (yellow) thresholds."] or "Colors change at 35% (red) and 70% (yellow) thresholds.") .. "|r",
                        order = 38,
                        fontSize = "small",
                    },
                    -- ========== ADVANCED COLOR OPTIONS ==========
                    advancedColorHeader = {
                        type = "header",
                        name = L["Advanced Color Options"] or "Advanced Color Options",
                        order = 39,
                    },
                    chargedColor = {
                        type = "color",
                        name = L["Charged Point Color"] or "Charged Point Color",
                        desc = L["Color overlay for charged combo points"] or "Color overlay for charged combo points",
                        order = 39.1,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.chargedColor or {0.22, 0.62, 1.0, 0.8}
                            return c[1], c[2], c[3], c[4] or 0.8
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.chargedColor = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    enableMaxColor = {
                        type = "toggle",
                        name = L["Enable Max Color"] or "Enable Max Color",
                        desc = L["Change bar color when resource is at maximum"] or "Change bar color when resource is at maximum",
                        order = 39.2,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.enableMaxColor end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.enableMaxColor = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    maxColor = {
                        type = "color",
                        name = L["Max Resource Color"] or "Max Resource Color",
                        desc = L["Bar color when resource is at maximum"] or "Bar color when resource is at maximum",
                        order = 39.3,
                        width = "normal",
                        hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enableMaxColor end,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.maxColor or {1.0, 0.3, 0.3, 1.0}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.maxColor = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    useRechargeColor = {
                        type = "toggle",
                        name = L["Custom Recharge Color"] or "Custom Recharge Color",
                        desc = L["Use a custom color for recharging runes/essence instead of dimmed base color"] or "Use a custom color for recharging runes/essence instead of dimmed base color",
                        order = 39.4,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.useRechargeColor end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.useRechargeColor = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    rechargeColor = {
                        type = "color",
                        name = L["Recharge Color"] or "Recharge Color",
                        desc = L["Color for recharging runes/essence segments"] or "Color for recharging runes/essence segments",
                        order = 39.5,
                        width = "normal",
                        hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.useRechargeColor end,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.rechargeColor or {0.4, 0.4, 0.4, 1.0}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.rechargeColor = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    enablePerPointColors = {
                        type = "toggle",
                        name = L["Per-Point Colors"] or "Per-Point Colors",
                        desc = L["Set individual colors for each point (combo points, chi, holy power, etc.)"] or "Set individual colors for each point (combo points, chi, holy power, etc.)",
                        order = 40,
                        width = "full",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.enablePerPointColors = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    perPointColor1 = {
                        type = "color", name = "1", order = 40.1, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[1]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 0.2,1,0.2,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[1]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor2 = {
                        type = "color", name = "2", order = 40.2, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[2]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 0.4,1,0.2,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[2]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor3 = {
                        type = "color", name = "3", order = 40.3, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[3]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 0.6,1,0.2,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[3]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor4 = {
                        type = "color", name = "4", order = 40.4, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[4]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 0.8,1,0.2,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[4]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor5 = {
                        type = "color", name = "5", order = 40.5, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[5]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 1,0.8,0.2,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[5]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor6 = {
                        type = "color", name = "6", order = 40.6, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[6]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 1,0.5,0.2,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[6]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor7 = {
                        type = "color", name = "7", order = 40.7, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[7]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 1,0.3,0.2,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[7]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor8 = {
                        type = "color", name = "8", order = 40.8, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[8]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 1,0.2,0.2,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[8]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor9 = {
                        type = "color", name = "9", order = 40.9, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[9]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 1,0.1,0.1,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[9]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    perPointColor10 = {
                        type = "color", name = "10", order = 40.95, width = 0.3, hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
                        get = function() local c = DDingUI.db.profile.secondaryPowerBar.perPointColors[10]; if c then return c[1],c[2],c[3],c[4] or 1 end; return 1,0,0,1 end,
                        set = function(_,r,g,b,a) DDingUI.db.profile.secondaryPowerBar.perPointColors[10]={r,g,b,a}; DDingUI:UpdateSecondaryPowerBar() end,
                    },
                    enableOverflowColor = {
                        type = "toggle",
                        name = L["Overflow Color"] or "Overflow Color",
                        desc = L["When points exceed threshold, overflow wraps back from first segment with a different color"] or "When points exceed threshold, overflow wraps back from first segment with a different color",
                        order = 40.96,
                        width = "full",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.enableOverflowColor end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.enableOverflowColor = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    overflowThreshold = {
                        type = "range",
                        name = L["Overflow Threshold"] or "Overflow Threshold",
                        desc = L["Number of points before overflow starts (e.g. 5 = 6th point overlays 1st segment)"] or "Number of points before overflow starts (e.g. 5 = 6th point overlays 1st segment)",
                        order = 40.97,
                        width = "normal",
                        min = 1, max = 10, step = 1,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enableOverflowColor end,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.overflowThreshold or 5 end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.overflowThreshold = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    overflowColor = {
                        type = "color",
                        name = L["Overflow Color"] or "Overflow Color",
                        desc = L["Color for overflow segments beyond threshold"] or "Color for overflow segments beyond threshold",
                        order = 40.98,
                        width = "normal",
                        hasAlpha = true,
                        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enableOverflowColor end,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.overflowColor or {1.0, 0.3, 0.3, 1.0}
                            return c[1], c[2], c[3], c[4] or 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.overflowColor = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runeTimerHeader = {
                        type = "header",
                        name = L["Rune Timer Options"] or "Rune Timer Options",
                        order = 50,
                    },
                    showFragmentedPowerBarText = {
                        type = "toggle",
                        name = L["Show Rune Timers"] or "Show Rune Timers",
                        desc = L["Show cooldown timers on individual runes (Death Knight only)"] or "Show cooldown timers on individual runes (Death Knight only)",
                        order = 51,
                        width = "normal",
                        get = function() return DDingUI.db.profile.secondaryPowerBar.showFragmentedPowerBarText end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.showFragmentedPowerBarText = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runeTimerFont = {
                        type = "select",
                        name = L["Rune Timer Font"] or "Rune Timer Font",
                        desc = L["Font for the rune timer text"] or "Font for the rune timer text",
                        order = 51.5,
                        width = "normal",
                        dialogControl = "LSM30_Font",
                        values = function() return DDingUI:GetFontValues() end,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.runeTimerFont or DDingUI.DEFAULT_FONT_NAME end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.runeTimerFont = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runeTimerTextSize = {
                        type = "range",
                        name = L["Rune Timer Text Size"] or "Rune Timer Text Size",
                        desc = L["Font size for the rune timer text"] or "Font size for the rune timer text",
                        order = 52,
                        width = "normal",
                        min = 6, max = 24, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.runeTimerTextSize end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.runeTimerTextSize = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runeTimerTextX = {
                        type = "range",
                        name = L["Rune Timer Text X Position"] or "Rune Timer Text X Position",
                        desc = L["Horizontal offset for the rune timer text"] or "Horizontal offset for the rune timer text",
                        order = 53,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.runeTimerTextX end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.runeTimerTextX = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runeTimerTextY = {
                        type = "range",
                        name = L["Rune Timer Text Y Position"] or "Rune Timer Text Y Position",
                        desc = L["Vertical offset for the rune timer text"] or "Vertical offset for the rune timer text",
                        order = 54,
                        width = "normal",
                        min = -50, max = 50, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.runeTimerTextY end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.runeTimerTextY = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    -- Custom Markers
                    markerHeader = {
                        type = "header",
                        name = L["Custom Markers"] or "Custom Markers",
                        order = 60,
                    },
                    markerPositions = {
                        type = "input",
                        name = L["Marker Positions"] or "Marker Positions",
                        desc = L["Marker Positions Desc"] or "Enter resource values separated by commas. Example: 3, 5",
                        order = 61,
                        width = 1.2,
                        get = function()
                            local m = MigrateMarkers(DDingUI.db.profile.secondaryPowerBar)
                            if m and #m > 0 then
                                local strs = {}
                                for _, v in ipairs(m) do
                                    table.insert(strs, tostring(v))
                                end
                                return table.concat(strs, ", ")
                            end
                            return ""
                        end,
                        set = function(_, val)
                            local cfg = DDingUI.db.profile.secondaryPowerBar
                            local oldMarkers = MigrateMarkers(cfg) or {}
                            local oldColors = cfg.markerBarColors or {}
                            local colorMap = {}
                            for i, mVal in ipairs(oldMarkers) do
                                if oldColors[i] then colorMap[mVal] = oldColors[i] end
                            end

                            local values = {}
                            for numStr in string.gmatch(val, "([%d%.]+)") do
                                local num = tonumber(numStr)
                                if num and num > 0 then
                                    table.insert(values, num)
                                end
                            end
                            table.sort(values)
                            cfg.markers = values

                            local newColors = {}
                            for i, mVal in ipairs(values) do
                                if colorMap[mVal] then newColors[i] = colorMap[mVal] end
                            end
                            cfg.markerBarColors = newColors

                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                            DebouncedRefresh()
                        end,
                    },
                    markerColor = {
                        type = "color",
                        name = L["Marker Color"] or "Marker Color",
                        order = 62,
                        width = 0.5,
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.markerColor
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1, 1, 1, 0.8
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.markerColor = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    markerWidth = {
                        type = "range",
                        name = L["Marker Width"] or "Marker Width",
                        order = 63,
                        width = 0.7,
                        min = 1, max = 5, step = 1,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.markerWidth or 2 end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.markerWidth = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    markerColorChange = {
                        type = "toggle",
                        name = L["Change Bar Color at Marker"] or "Change Bar Color at Marker",
                        desc = L["Change the bar color when resource exceeds a marker value"] or "Change the bar color when resource exceeds a marker value",
                        order = 64,
                        width = "full",
                        hidden = function()
                            local m = DDingUI.db.profile.secondaryPowerBar.markers
                            return not m or #m == 0
                        end,
                        get = function() return DDingUI.db.profile.secondaryPowerBar.markerColorChange end,
                        set = function(_, val)
                            DDingUI.db.profile.secondaryPowerBar.markerColorChange = val
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                            RefreshOptions()
                        end,
                    },
                    markerBarColorDesc = {
                        type = "description",
                        name = "|cff888888" .. (L["Color applied when resource >= marker value. Highest matched marker wins."] or "Color applied when resource >= marker value. Highest matched marker wins.") .. "|r",
                        order = 64.1,
                        fontSize = "small",
                        hidden = function()
                            local cfg = DDingUI.db.profile.secondaryPowerBar
                            return not cfg.markerColorChange or not cfg.markers or #cfg.markers == 0
                        end,
                    },
                    markerBarColor1 = {
                        type = "color", name = "", order = 64.2, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 1 end,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.markerBarColors[1]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1, 0.3, 0.3, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.markerBarColors[1] = {r, g, b, a}
                            DDingUI:UpdateSecondaryPowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor1Label = {
                        type = "description", order = 64.21, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 1 end,
                        name = function()
                            local m = DDingUI.db.profile.secondaryPowerBar.markers
                            local v = GetMarkerValue(m, 1); return v and (">= " .. v) or ""
                        end,
                    },
                    markerBarColor2 = {
                        type = "color", name = "", order = 64.3, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 2 end,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.markerBarColors[2]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1, 1, 0.3, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.markerBarColors[2] = {r, g, b, a}
                            DDingUI:UpdateSecondaryPowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor2Label = {
                        type = "description", order = 64.31, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 2 end,
                        name = function()
                            local m = DDingUI.db.profile.secondaryPowerBar.markers
                            local v = GetMarkerValue(m, 2); return v and (">= " .. v) or ""
                        end,
                    },
                    markerBarColor3 = {
                        type = "color", name = "", order = 64.4, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 3 end,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.markerBarColors[3]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 0.3, 1, 0.3, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.markerBarColors[3] = {r, g, b, a}
                            DDingUI:UpdateSecondaryPowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor3Label = {
                        type = "description", order = 64.41, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 3 end,
                        name = function()
                            local m = DDingUI.db.profile.secondaryPowerBar.markers
                            local v = GetMarkerValue(m, 3); return v and (">= " .. v) or ""
                        end,
                    },
                    markerBarColor4 = {
                        type = "color", name = "", order = 64.5, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 4 end,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.markerBarColors[4]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 0.3, 0.7, 1, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.markerBarColors[4] = {r, g, b, a}
                            DDingUI:UpdateSecondaryPowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor4Label = {
                        type = "description", order = 64.51, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 4 end,
                        name = function()
                            local m = DDingUI.db.profile.secondaryPowerBar.markers
                            local v = GetMarkerValue(m, 4); return v and (">= " .. v) or ""
                        end,
                    },
                    markerBarColor5 = {
                        type = "color", name = "", order = 64.6, width = 0.35, hasAlpha = true,
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 5 end,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.markerBarColors[5]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1, 0.5, 1, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.markerBarColors[5] = {r, g, b, a}
                            DDingUI:UpdateSecondaryPowerBar(); MarkSpecDirty()
                        end,
                    },
                    markerBarColor5Label = {
                        type = "description", order = 64.61, width = 0.35, fontSize = "small",
                        hidden = function() local cfg = DDingUI.db.profile.secondaryPowerBar; return not cfg.markerColorChange or not cfg.markers or #cfg.markers < 5 end,
                        name = function()
                            local m = DDingUI.db.profile.secondaryPowerBar.markers
                            local v = GetMarkerValue(m, 5); return v and (">= " .. v) or ""
                        end,
                    },
                },
            },
            colors = {
                type = "group",
                name = L["Colors"] or "Colors",
                order = 4,
                args = {
                    useClassColor = {
                        type = "toggle",
                        name = L["Use Class Color"] or "Use Class Color",
                        desc = L["Use your class color for resource bars instead of power type colors"] or "Use your class color for resource bars instead of power type colors",
                        width = "full",
                        order = 1,
                        get = function() return DDingUI.db.profile.powerTypeColors.useClassColor end,
                        set = function(_, val)
                            DDingUI.db.profile.powerTypeColors.useClassColor = val
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    backgroundHeader = {
                        type = "header",
                        name = L["Global Background Colors"] or "Global Background Colors",
                        order = 2,
                    },
                    primaryBgColor = {
                        type = "color",
                        name = L["Primary Bar Background"] or "Primary Bar Background",
                        desc = L["Background color for primary power bars"] or "Background color for primary power bars",
                        order = 3,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerBar.bgColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.15, 0.15, 0.15, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerBar.bgColor = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    secondaryBgColor = {
                        type = "color",
                        name = L["Secondary Bar Background"] or "Secondary Bar Background",
                        desc = L["Background color for secondary power bars"] or "Background color for secondary power bars",
                        order = 4,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.secondaryPowerBar.bgColor
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.15, 0.15, 0.15, 1
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.secondaryPowerBar.bgColor = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    primaryHeader = {
                        type = "header",
                        name = L["Primary Power Types"] or "Primary Power Types",
                        order = 10,
                    },
                    manaColor = {
                        type = "color",
                        name = L["Mana"] or "Mana",
                        desc = L["Color for mana bars"] or "Color for mana bars",
                        order = 11,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Mana]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.00, 0.00, 1.00, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Mana] = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    rageColor = {
                        type = "color",
                        name = L["Rage"] or "Rage",
                        desc = L["Color for rage bars"] or "Color for rage bars",
                        order = 12,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Rage]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1.00, 0.00, 0.00, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Rage] = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    focusColor = {
                        type = "color",
                        name = L["Focus (Power)"] or "Focus",
                        desc = L["Color for focus bars"] or "Color for focus bars",
                        order = 13,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Focus]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1.00, 0.50, 0.25, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Focus] = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    energyColor = {
                        type = "color",
                        name = L["Energy"] or "Energy",
                        desc = L["Color for energy bars"] or "Color for energy bars",
                        order = 14,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Energy]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1.00, 1.00, 0.00, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Energy] = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runicPowerColor = {
                        type = "color",
                        name = L["Runic Power"] or "Runic Power",
                        desc = L["Color for runic power bars"] or "Color for runic power bars",
                        order = 15,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.RunicPower]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.00, 0.82, 1.00, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.RunicPower] = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    lunarPowerColor = {
                        type = "color",
                        name = L["Astral Power"] or "Astral Power",
                        desc = L["Color for astral power bars"] or "Color for astral power bars",
                        order = 16,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.LunarPower]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.30, 0.52, 0.90, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.LunarPower] = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    furyColor = {
                        type = "color",
                        name = L["Fury"] or "Fury",
                        desc = L["Color for fury bars"] or "Color for fury bars",
                        order = 17,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Fury]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.79, 0.26, 0.99, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Fury] = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    maelstromColor = {
                        type = "color",
                        name = L["Maelstrom"] or "Maelstrom",
                        desc = L["Color for maelstrom bars"] or "Color for maelstrom bars",
                        order = 18,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Maelstrom]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.00, 0.50, 1.00, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Maelstrom] = { r, g, b, a }
                            DDingUI:UpdatePowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    secondaryHeader = {
                        type = "header",
                        name = L["Secondary Power Types"] or "Secondary Power Types",
                        order = 20,
                    },
                    runesColor = {
                        type = "color",
                        name = L["Runes"] or "Runes",
                        desc = L["Color for rune bars"] or "Color for rune bars",
                        order = 21,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Runes]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.77, 0.12, 0.23, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Runes] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runeBloodColor = {
                        type = "color",
                        name = L["Runes (Blood)"] or "Runes (Blood)",
                        desc = L["Color for blood DK rune bars"] or "Color for blood DK rune bars",
                        order = 21.1,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors["RUNE_BLOOD"]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 1.00, 0.25, 0.25, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors["RUNE_BLOOD"] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runeFrostColor = {
                        type = "color",
                        name = L["Runes (Frost)"] or "Runes (Frost)",
                        desc = L["Color for frost DK rune bars"] or "Color for frost DK rune bars",
                        order = 21.2,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors["RUNE_FROST"]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 0.25, 1.00, 1.00, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors["RUNE_FROST"] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    runeUnholyColor = {
                        type = "color",
                        name = L["Runes (Unholy)"] or "Runes (Unholy)",
                        desc = L["Color for unholy DK rune bars"] or "Color for unholy DK rune bars",
                        order = 21.3,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors["RUNE_UNHOLY"]
                            if c then return c[1], c[2], c[3], c[4] or 1 end
                            return 0.25, 1.00, 0.25, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors["RUNE_UNHOLY"] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    soulFragmentsColor = {
                        type = "color",
                        name = L["Soul Fragments"] or "Soul Fragments",
                        desc = L["Color for soul fragment bars"] or "Color for soul fragment bars",
                        order = 22,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors["SOUL"]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.64, 0.19, 0.79, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors["SOUL"] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    comboPointsColor = {
                        type = "color",
                        name = L["Combo Points"] or "Combo Points",
                        desc = L["Color for combo point bars"] or "Color for combo point bars",
                        order = 23,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.ComboPoints]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1.00, 0.96, 0.41, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.ComboPoints] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    essenceColor = {
                        type = "color",
                        name = L["Essence"] or "Essence",
                        desc = L["Color for essence bars"] or "Color for essence bars",
                        order = 24,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Essence]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.20, 0.58, 0.50, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Essence] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    arcaneChargesColor = {
                        type = "color",
                        name = L["Arcane Charges"] or "Arcane Charges",
                        desc = L["Color for arcane charge bars"] or "Color for arcane charge bars",
                        order = 25,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.ArcaneCharges]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.20, 0.60, 1.00, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.ArcaneCharges] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    staggerLightColor = {
                        type = "color",
                        name = L["Light Stagger"] or "Light Stagger",
                        desc = L["Color for stagger bars when stagger is less than 30% of max health"] or "Color for stagger bars when stagger is less than 30% of max health",
                        order = 26,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors["STAGGER_LIGHT"]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.52, 1.00, 0.52, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors["STAGGER_LIGHT"] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    staggerMediumColor = {
                        type = "color",
                        name = L["Medium Stagger"] or "Medium Stagger",
                        desc = L["Color for stagger bars when stagger is 30-59% of max health"] or "Color for stagger bars when stagger is 30-59% of max health",
                        order = 26.1,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors["STAGGER_MEDIUM"]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1.00, 0.98, 0.72, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors["STAGGER_MEDIUM"] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    staggerHeavyColor = {
                        type = "color",
                        name = L["Heavy Stagger"] or "Heavy Stagger",
                        desc = L["Color for stagger bars when stagger is 60% or more of max health"] or "Color for stagger bars when stagger is 60% or more of max health",
                        order = 26.2,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors["STAGGER_HEAVY"]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 1.00, 0.42, 0.42, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors["STAGGER_HEAVY"] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    chiColor = {
                        type = "color",
                        name = L["Chi"] or "Chi",
                        desc = L["Color for chi bars"] or "Color for chi bars",
                        order = 27,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Chi]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.00, 1.00, 0.59, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Chi] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    holyPowerColor = {
                        type = "color",
                        name = L["Holy Power"] or "Holy Power",
                        desc = L["Color for holy power bars"] or "Color for holy power bars",
                        order = 28,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.HolyPower]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.95, 0.90, 0.60, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.HolyPower] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    soulShardsColor = {
                        type = "color",
                        name = L["Soul Shards"] or "Soul Shards",
                        desc = L["Color for soul shard bars"] or "Color for soul shard bars",
                        order = 29,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.SoulShards]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.58, 0.51, 0.79, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.SoulShards] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                    maelstromWeaponColor = {
                        type = "color",
                        name = L["Maelstrom Weapon"] or "Maelstrom Weapon",
                        desc = L["Color for maelstrom weapon bars"] or "Color for maelstrom weapon bars",
                        order = 30,
                        width = "normal",
                        hasAlpha = true,
                        get = function()
                            local c = DDingUI.db.profile.powerTypeColors.colors["MAELSTROM_WEAPON"]
                            if c then
                                return c[1], c[2], c[3], c[4] or 1
                            end
                            return 0.00, 0.50, 1.00, 1.0
                        end,
                        set = function(_, r, g, b, a)
                            DDingUI.db.profile.powerTypeColors.colors["MAELSTROM_WEAPON"] = { r, g, b, a }
                            DDingUI:UpdateSecondaryPowerBar()
                            MarkSpecDirty()
                        end,
                    },
                },
            },
        },
    }

    -- ===== Color Reset Buttons (기본값 되돌리기) =====
    local primaryArgs = options.args.primary.args
    local secondaryArgs = options.args.secondary.args
    local colorArgs = options.args.colors.args

    -- Primary bar: border color
    primaryArgs.borderColorReset = MakeColorReset(23.01, function()
        DDingUI.db.profile.powerBar.borderColor = { 0, 0, 0, 1 }
        DDingUI:UpdatePowerBar()
    end)

    -- Secondary bar: border color
    secondaryArgs.borderColorReset = MakeColorReset(23.01, function()
        DDingUI.db.profile.secondaryPowerBar.borderColor = { 0, 0, 0, 1 }
        DDingUI:UpdateSecondaryPowerBar()
    end)

    -- Secondary bar: charged color
    secondaryArgs.chargedColorReset = MakeColorReset(39.11, function()
        DDingUI.db.profile.secondaryPowerBar.chargedColor = { 0.22, 0.62, 1.0, 0.8 }
        DDingUI:UpdateSecondaryPowerBar()
    end)

    -- Secondary bar: max color
    secondaryArgs.maxColorReset = MakeColorReset(39.31, function()
        DDingUI.db.profile.secondaryPowerBar.maxColor = { 1.0, 0.3, 0.3, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)

    -- Secondary bar: recharge color
    secondaryArgs.rechargeColorReset = MakeColorReset(39.51, function()
        DDingUI.db.profile.secondaryPowerBar.rechargeColor = { 0.4, 0.4, 0.4, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)

    -- Secondary bar: reset all per-point colors
    secondaryArgs.resetPerPointColors = {
        type = "execute",
        name = L["Reset All"] or "Reset All",
        desc = L["Reset all per-point colors to default"] or "Reset all per-point colors to default",
        order = 40.955,
        width = 0.5,
        disabled = function() return not DDingUI.db.profile.secondaryPowerBar.enablePerPointColors end,
        func = function()
            DDingUI.db.profile.secondaryPowerBar.perPointColors = {}
            DDingUI:UpdateSecondaryPowerBar()
            RefreshOptions()
        end,
    }

    -- Secondary bar: overflow color
    secondaryArgs.overflowColorReset = MakeColorReset(40.981, function()
        DDingUI.db.profile.secondaryPowerBar.overflowColor = { 1.0, 0.3, 0.3, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)


    -- Colors tab: background colors
    colorArgs.primaryBgColorReset = MakeColorReset(3.01, function()
        DDingUI.db.profile.powerBar.bgColor = { 0.15, 0.15, 0.15, 1 }
        DDingUI:UpdatePowerBar()
    end)
    colorArgs.secondaryBgColorReset = MakeColorReset(4.01, function()
        DDingUI.db.profile.secondaryPowerBar.bgColor = { 0.15, 0.15, 0.15, 1 }
        DDingUI:UpdateSecondaryPowerBar()
    end)

    -- Colors tab: primary power types
    colorArgs.manaColorReset = MakeColorReset(11.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Mana] = { 0.00, 0.00, 1.00, 1.0 }
        DDingUI:UpdatePowerBar()
    end)
    colorArgs.rageColorReset = MakeColorReset(12.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Rage] = { 1.00, 0.00, 0.00, 1.0 }
        DDingUI:UpdatePowerBar()
    end)
    colorArgs.focusColorReset = MakeColorReset(13.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Focus] = { 1.00, 0.50, 0.25, 1.0 }
        DDingUI:UpdatePowerBar()
    end)
    colorArgs.energyColorReset = MakeColorReset(14.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Energy] = { 1.00, 1.00, 0.00, 1.0 }
        DDingUI:UpdatePowerBar()
    end)
    colorArgs.runicPowerColorReset = MakeColorReset(15.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.RunicPower] = { 0.00, 0.82, 1.00, 1.0 }
        DDingUI:UpdatePowerBar()
    end)
    colorArgs.lunarPowerColorReset = MakeColorReset(16.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.LunarPower] = { 0.30, 0.52, 0.90, 1.0 }
        DDingUI:UpdatePowerBar()
    end)
    colorArgs.furyColorReset = MakeColorReset(17.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Fury] = { 0.79, 0.26, 0.99, 1.0 }
        DDingUI:UpdatePowerBar()
    end)
    colorArgs.maelstromColorReset = MakeColorReset(18.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Maelstrom] = { 0.00, 0.50, 1.00, 1.0 }
        DDingUI:UpdatePowerBar()
    end)

    -- Colors tab: secondary power types
    colorArgs.runesColorReset = MakeColorReset(21.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Runes] = { 0.77, 0.12, 0.23, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.runeBloodColorReset = MakeColorReset(21.11, function()
        DDingUI.db.profile.powerTypeColors.colors["RUNE_BLOOD"] = { 1.00, 0.25, 0.25, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.runeFrostColorReset = MakeColorReset(21.21, function()
        DDingUI.db.profile.powerTypeColors.colors["RUNE_FROST"] = { 0.25, 1.00, 1.00, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.runeUnholyColorReset = MakeColorReset(21.31, function()
        DDingUI.db.profile.powerTypeColors.colors["RUNE_UNHOLY"] = { 0.25, 1.00, 0.25, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.soulFragmentsColorReset = MakeColorReset(22.01, function()
        DDingUI.db.profile.powerTypeColors.colors["SOUL"] = { 0.64, 0.19, 0.79, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.comboPointsColorReset = MakeColorReset(23.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.ComboPoints] = { 1.00, 0.96, 0.41, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.essenceColorReset = MakeColorReset(24.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Essence] = { 0.20, 0.58, 0.50, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.arcaneChargesColorReset = MakeColorReset(25.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.ArcaneCharges] = { 0.20, 0.60, 1.00, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.staggerLightColorReset = MakeColorReset(26.01, function()
        DDingUI.db.profile.powerTypeColors.colors["STAGGER_LIGHT"] = { 0.52, 1.00, 0.52, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.staggerMediumColorReset = MakeColorReset(26.11, function()
        DDingUI.db.profile.powerTypeColors.colors["STAGGER_MEDIUM"] = { 1.00, 0.98, 0.72, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.staggerHeavyColorReset = MakeColorReset(26.21, function()
        DDingUI.db.profile.powerTypeColors.colors["STAGGER_HEAVY"] = { 1.00, 0.42, 0.42, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.chiColorReset = MakeColorReset(27.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.Chi] = { 0.00, 1.00, 0.59, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.holyPowerColorReset = MakeColorReset(28.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.HolyPower] = { 0.95, 0.90, 0.60, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.soulShardsColorReset = MakeColorReset(29.01, function()
        DDingUI.db.profile.powerTypeColors.colors[Enum.PowerType.SoulShards] = { 0.58, 0.51, 0.79, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)
    colorArgs.maelstromWeaponColorReset = MakeColorReset(30.01, function()
        DDingUI.db.profile.powerTypeColors.colors["MAELSTROM_WEAPON"] = { 0.00, 0.50, 1.00, 1.0 }
        DDingUI:UpdateSecondaryPowerBar()
    end)

    -- Add spec profile options to each submenu (at order 0, before header)
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.AddSpecProfileOptions then
        DDingUI.SpecProfiles:AddSpecProfileOptions(
            options.args.primary.args,
            "powerBar",
            L["Primary Power Bar"] or "Primary Power Bar",
            0,
            function() DDingUI:UpdatePowerBar() end
        )
        DDingUI.SpecProfiles:AddSpecProfileOptions(
            options.args.secondary.args,
            "secondaryPowerBar",
            L["Secondary Power Bar"] or "Secondary Power Bar",
            0,
            function() DDingUI:UpdateSecondaryPowerBar() end
        )
    end

    return options
end

ns.CreateResourceBarOptions = CreateResourceBarOptions

