local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

local function CreateIconCustomizationOptions()
    return {
        type = "group",
        name = L["Icon Customization"] or "Icon Customization",
        order = 5,
        args = {
            header = {
                type = "header",
                name = L["Icon Customization"] or "Icon Customization",
                order = 1,
            },
            description = {
                type = "description",
                name = L["Customize individual spell icons from your cooldown viewers. Click to select • Blue border = Customized"] or "Customize individual spell icons from your cooldown viewers. Click to select • Blue border = Customized",
                order = 2,
            },
            iconCustomizationUI = {
                type = "iconCustomization",
                name = "Icon Customization",
                order = 3,
            },
        },
    }
end

ns.CreateIconCustomizationOptions = CreateIconCustomizationOptions
