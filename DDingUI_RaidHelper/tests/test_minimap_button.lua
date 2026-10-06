local addonName = "DDingUI_RaidHelper"
local toggledOptions = 0
local toggledPreviewMode = 0
local registeredName
local registeredDB
local dataObject

local ns = {
    db = {
        minimap = {
            hide = false,
            minimapPos = 225,
        },
    },
    Options = {
        Toggle = function()
            toggledOptions = toggledOptions + 1
        end,
    },
    TimelineUI = {
        TogglePreviewMode = function()
            toggledPreviewMode = toggledPreviewMode + 1
        end,
    },
}

local fakeButton = { name = "LibDBIcon10_DDingUI_RaidHelper" }
local LDB = {
    NewDataObject = function(_, name, object)
        assert(name == "DDingUI_RaidHelper")
        dataObject = object
        return object
    end,
}
local LibDBIcon = {
    Register = function(_, name, _, db)
        registeredName = name
        registeredDB = db
    end,
    GetMinimapButton = function(_, name)
        assert(name == "DDingUI_RaidHelper")
        return fakeButton
    end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    Refresh = function(self, name, db)
        self.refreshedName = name
        self.refreshedDB = db
    end,
}

LibStub = function(name)
    if name == "LibDataBroker-1.1" then return LDB end
    if name == "LibDBIcon-1.0" then return LibDBIcon end
end

assert(loadfile("UI/MinimapButton.lua"))(addonName, ns)
ns.MinimapButton:Initialize()

assert(ns.MinimapButton.initialized)
assert(ns.MinimapButton.button == fakeButton)
assert(registeredName == "DDingUI_RaidHelper")
assert(registeredDB == ns.db.minimap)
assert(dataObject.icon == "Interface\\AddOns\\DDingUI_RaidHelper\\Media\\RaidHelper_Icon.tga")
assert(dataObject.iconCoords == nil, "RaidHelper must use Toolkit-compatible LibDBIcon coordinates")

dataObject.OnClick(nil, "LeftButton")
dataObject.OnClick(nil, "RightButton")
assert(toggledOptions == 1)
assert(toggledPreviewMode == 1)

assert(ns.MinimapButton:SetShown(false))
assert(ns.db.minimap.hide == true)
assert(LibDBIcon.shown == false)
assert(ns.MinimapButton:SetShown(true))
assert(ns.db.minimap.hide == false)
assert(LibDBIcon.shown == true)

ns.db.minimap.minimapPos = 123
assert(ns.MinimapButton:ResetPosition())
assert(ns.db.minimap.minimapPos == 225)
assert(LibDBIcon.refreshedName == "DDingUI_RaidHelper")
assert(LibDBIcon.refreshedDB == ns.db.minimap)

print("RaidHelper minimap button test OK")
