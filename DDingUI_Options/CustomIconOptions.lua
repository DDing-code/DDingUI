local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")

local function CreateCustomIconOptions()
    local options = {
        type = "group",
        name = L["Dynamic Icons"] or "Dynamic Icons",
        order = 6,
        args = {
            header = {
                type = "header",
                name = L["Dynamic Icons"] or "Dynamic Icons",
                order = 1,
            },
            description = {
                type = "description",
                name = L["Build custom spell, item, and equipment-slot trackers. Use the UI below to add icons, configure visuals, and organize groups."] or "Build custom spell, item, and equipment-slot trackers. Use the UI below to add icons, configure visuals, and organize groups.",
                order = 2,
            },
            dynamicUI = {
                type = "dynamicIcons",
                name = "Dynamic Icons",
                order = 3,
            },
        },
    }

    -- Add spec profile options (at order 0, before header)
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.AddSpecProfileOptions then
        DDingUI.SpecProfiles:AddSpecProfileOptions(
            options.args,
            "dynamicIcons",
            L["Dynamic Icons"] or "Dynamic Icons",
            0,
            function()
                if DDingUI.RefreshAll then
                    DDingUI:RefreshAll()
                end
            end
        )
    end

    return options
end

ns.CreateCustomIconOptions = CreateCustomIconOptions

