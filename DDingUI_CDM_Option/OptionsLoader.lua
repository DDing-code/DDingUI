-- DDingUI_Options: Namespace bridge
-- Populates DDingUI_Options namespace with DDingUI data
-- so Config files can use `local ADDON_NAME, ns = ...` unchanged.

local ADDON_NAME, ns = ...

local DDingUI = LibStub("AceAddon-3.0"):GetAddon("DDingUI")
if not DDingUI then
    error("DDingUI_Options: DDingUI addon not found!")
end

ns.Addon = DDingUI
ns.L = LibStub("AceLocale-3.0"):GetLocale("DDingUI", true)
ns.db = DDingUI.db

local mainNS = DDingUI._ns
if mainNS then
    for k, v in pairs(mainNS) do
        if ns[k] == nil then
            ns[k] = v
        end
    end
end
