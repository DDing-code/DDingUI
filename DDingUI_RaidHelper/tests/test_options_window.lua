local addonName = "DDingUI_RaidHelper"
local inCombat = false

local function Noop() end

local objectMethods = {
    SetFont = Noop,
    SetTextColor = Noop,
    SetJustifyH = Noop,
    SetJustifyV = Noop,
    SetWidth = Noop,
    SetHeight = Noop,
    SetSize = Noop,
    SetPoint = Noop,
    SetTexture = Noop,
    SetTexCoord = Noop,
    ClearAllPoints = Noop,
    SetClampedToScreen = Noop,
    SetVerticalScroll = function(self, value) self.verticalScroll = value end,
    SetText = function(self, value) self.text = value end,
    SetDisabledState = function(self, value) self.disabled = value end,
    SetScript = function(self, event, handler) self.scripts[event] = handler end,
    HookScript = function(self, event, handler) self.scripts[event] = handler end,
    SetShown = function(self, shown) self.shown = shown end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown == true end,
}

local function NewObject()
    local object = { shown = true, scripts = {} }
    object.CreateFontString = function() return NewObject() end
    object.CreateTexture = function() return NewObject() end
    return setmetatable(object, { __index = objectMethods })
end

CreateFrame = function() return NewObject() end
InCombatLockdown = function() return inCombat end
GameTooltip = { Hide = Noop }
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
C_Spell = { GetSpellName = function(spellID) return "Spell " .. tostring(spellID) end }

local colors = {
    text = {
        highlight = { 1, 1, 1, 1 },
        normal = { 0.8, 0.8, 0.8, 1 },
        dim = { 0.5, 0.5, 0.5, 1 },
    },
}

local frame = NewObject()
frame.shown = false
frame.ShowAnimated = function(self) self:Show() end
frame.HideAnimated = function(self) self:Hide() end
local titleBar = NewObject()
titleBar.titleText = NewObject()
local contentChild = NewObject()
local contentScroll = NewObject()
local treeFrame = NewObject()

-- RaidHelper only reads its private embedded StyleLib global.
DDingUI_RaidHelperStyleLib = {
    Colors = colors,
    Font = { path = "font", title = 16, normal = 13, small = 11 },
    GetFont = function() return "font" end,
    GetFontSize = function(_, key)
        return ({ title = 16, normal = 13, small = 11 })[key]
    end,
    CreateSettingsPanel = function()
        return {
            frame = frame,
            titleBar = titleBar,
            treeFrame = treeFrame,
            contentScroll = contentScroll,
            contentChild = contentChild,
        }
    end,
    CreateTreeMenu = function(_, _, _, opts)
        local tree = NewObject()
        tree.selected = opts.defaultKey
        tree.GetSelected = function(self) return self.selected end
        tree.SetSelected = function(self, key) self.selected = key end
        return tree
    end,
    CreateCheckbox = function(_, _, _, initial, opts)
        local checkbox = NewObject()
        checkbox.checked = initial
        checkbox.SetChecked = function(self, value)
            self.checked = value
            if opts.onChange then opts.onChange(value) end
        end
        return checkbox
    end,
    CreateSlider = function(_, _, _, _, _, _, initial, opts)
        local container = NewObject()
        local slider = NewObject()
        slider.value = initial
        slider.SetValue = function(self, value)
            self.value = value
            if opts.onChange then opts.onChange(value) end
        end
        slider.GetValue = function(self) return self.value end
        container.slider = slider
        return container
    end,
    CreateSectionHeader = function() return NewObject() end,
    CreateButton = function() return NewObject() end,
}

local ns = {
    addonName = addonName,
    db = {
        showTooltips = false,
        showUpcomingCooldowns = true,
        timelineScale = 1.0,
        timelineWidth = 680,
        timelineHeight = 210,
        backgroundAlpha = 1.0,
        cooldownVisibility = {},
    },
    IsSecret = function() return false end,
    Print = Noop,
    Registry = {
        GetByKey = function() return { name = "Demo" } end,
        GetDataSummary = function()
            return {
                modelCount = 11,
                heroicCount = 9,
                mythicCount = 2,
                latestGeneratedAt = "2026-08-24T10:15:06+00:00",
            }
        end,
    },
    Engine = {
        playerSpecID = 257,
        RefreshPlayerSpecialization = function(self) return self.playerSpecID end,
        GetHealerProfile = function() return nil end,
        GetModel = function() return nil end,
    },
    HealerProfileUI = {
        GetSummary = function() return "현재 전문화의 수집 데이터가 없습니다." end,
    },
}

assert(loadfile("Data/CooldownCatalog.lua"))(addonName, ns)
assert(loadfile("Options.lua"))(addonName, ns)
ns.Options:Initialize()

assert(ns.Options.initialized)
assert(ns.Options.independentWindow)
assert(ns.Options.frame == frame)
assert(ns.Options.activePage == "timeline")
assert(ns.Options.pages.timeline:IsShown())
assert(ns.Options.timelineScaleSlider.slider:GetValue() == 100)
assert(ns.Options.backgroundAlphaSlider.slider:GetValue() == 100)
assert(ns.Options.timelineWidthSlider.slider:GetValue() == 680)
assert(ns.Options.timelineHeightSlider.slider:GetValue() == 98) -- legacy 210 -> C안 default
assert(ns.Options.upcomingCooldownCheckbox.checked == true)
assert(#ns.Options.cooldownCheckboxes[257] >= 10)
assert(not ns.Options.pages.cooldowns:IsShown())
assert(not ns.Options.pages.profile:IsShown())
assert(not ns.Options.pages.data:IsShown())

assert(ns.Options:Open("data"))
assert(frame:IsShown())
assert(ns.Options.activePage == "data")
assert(ns.Options.pages.data:IsShown())
assert(not ns.Options.pages.timeline:IsShown())

assert(ns.Options:Open("cooldowns"))
assert(ns.Options.pages.cooldowns:IsShown())
assert(ns.Options.cooldownSpecFrames[257]:IsShown())

assert(ns.Options:Toggle())
assert(not frame:IsShown())

inCombat = true
assert(ns.Options:Open() == false)
assert(not frame:IsShown())

print("RaidHelper independent options window test OK")
