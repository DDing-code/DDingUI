--[[
    DDingUI Localization System
    Core loader that initializes AceLocale-3.0 and provides access to locale strings
--]]

local ADDON_NAME, ns = ...

-- Get or create locale
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME, true)

-- Store the locale table in the namespace for access from other files
ns.L = L

-- Return the locale table for backwards compatibility
return L
