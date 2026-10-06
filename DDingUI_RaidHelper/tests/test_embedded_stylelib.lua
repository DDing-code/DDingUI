local addonName = "DDingUI_RaidHelper"

strmatch = string.match
unpack = table.unpack
geterrorhandler = function()
    return function(message) error(message, 0) end
end
GetPhysicalScreenSize = function() return 1920, 1080 end
CreateColor = function(r, g, b, a)
    return { r = r, g = g, b = b, a = a }
end

local frameMethods = {
    GetScale = function() return 1 end,
    GetEffectiveScale = function() return 1 end,
    IsShown = function() return false end,
}

local frameMeta = {
    __index = function(_, key)
        return frameMethods[key] or function() end
    end,
}

UIParent = setmetatable({}, frameMeta)
CreateFrame = function()
    return setmetatable({}, frameMeta)
end

assert(loadfile("Libs/LibStub/LibStub.lua"))()
assert(loadfile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"))()

-- Simulate another DDingUI addon already owning the public library.  Loading
-- RaidHelper must neither replace it nor add RaidHelper widget methods to it.
local publicStyleLib = assert(LibStub:NewLibrary("DDingUI-StyleLib-1.0", 999))
publicStyleLib.publicOwnerSentinel = true
DDingUI_StyleLib = publicStyleLib

local styleFiles = {
    "Core.lua",
    "Colors.lua",
    "Gradient.lua",
    "Motion.lua",
    "TableUtils.lua",
    "Delay.lua",
    "ColorNames.lua",
    "DesignTokens.lua",
    "PixelUtil.lua",
    "ObjectPool.lua",
    "Animation.lua",
    "WidgetRefresh.lua",
    "GlowEffects.lua",
    "CascadingMenu.lua",
    "DragSorter.lua",
    "DualRow.lua",
    "Widgets.lua",
    "ProceduralGlow.lua",
}

for _, fileName in ipairs(styleFiles) do
    local chunk = assert(loadfile("Libs/DDingUI_StyleLib/" .. fileName))
    chunk(addonName)
end

local styleLib = assert(DDingUI_RaidHelperStyleLib)
assert(styleLib.__ddingStyleLibLoadOwner == addonName)
assert(DDingUI_StyleLib == publicStyleLib)
assert(DDingUI_StyleLib.publicOwnerSentinel == true)
assert(DDingUI_StyleLib.CreateButton == nil)
assert(type(styleLib.RegisterAddon) == "function")
assert(type(styleLib.RegisterCallback) == "function")
assert(type(styleLib.CreateButton) == "function")
assert(type(styleLib.CreateCheckbox) == "function")
assert(type(styleLib.CreateInputField) == "function")
assert(type(styleLib.CreateHorizontalGradient) == "function")
assert(type(styleLib.GetFont) == "function")
assert(type(styleLib.GetTexture) == "function")
assert(type(styleLib.Colors) == "table")
assert(type(styleLib.Tokens) == "table")

print("RaidHelper embedded StyleLib test OK")
