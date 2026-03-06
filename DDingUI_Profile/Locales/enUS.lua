local L = LibStub("AceLocale-3.0"):NewLocale("DDingUI_Profile", "enUS", true)
if not L then return end

------------------------------------------------------------------------
-- CLASS NAMES
------------------------------------------------------------------------
L["CLASS_WARRIOR"]      = "Warrior"
L["CLASS_PALADIN"]      = "Paladin"
L["CLASS_HUNTER"]       = "Hunter"
L["CLASS_ROGUE"]        = "Rogue"
L["CLASS_PRIEST"]       = "Priest"
L["CLASS_DEATHKNIGHT"]  = "Death Knight"
L["CLASS_SHAMAN"]       = "Shaman"
L["CLASS_MAGE"]         = "Mage"
L["CLASS_WARLOCK"]      = "Warlock"
L["CLASS_MONK"]         = "Monk"
L["CLASS_DRUID"]        = "Druid"
L["CLASS_DEMONHUNTER"]  = "Demon Hunter"
L["CLASS_EVOKER"]       = "Evoker"

------------------------------------------------------------------------
-- SPECIALIZATION NAMES
------------------------------------------------------------------------
-- Warrior
L["SPEC_ARMS"]          = "Arms"
L["SPEC_FURY"]          = "Fury"
L["SPEC_PROTECTION_WARRIOR"] = "Protection"
-- Paladin
L["SPEC_HOLY_PALADIN"]  = "Holy"
L["SPEC_PROTECTION_PALADIN"] = "Protection"
L["SPEC_RETRIBUTION"]   = "Retribution"
-- Hunter
L["SPEC_BEASTMASTERY"]  = "Beast Mastery"
L["SPEC_MARKSMANSHIP"]  = "Marksmanship"
L["SPEC_SURVIVAL"]      = "Survival"
-- Rogue
L["SPEC_ASSASSINATION"] = "Assassination"
L["SPEC_OUTLAW"]        = "Outlaw"
L["SPEC_SUBTLETY"]      = "Subtlety"
-- Priest
L["SPEC_DISCIPLINE"]    = "Discipline"
L["SPEC_HOLY_PRIEST"]   = "Holy"
L["SPEC_SHADOW"]        = "Shadow"
-- Death Knight
L["SPEC_BLOOD"]         = "Blood"
L["SPEC_FROST_DK"]      = "Frost"
L["SPEC_UNHOLY"]        = "Unholy"
-- Shaman
L["SPEC_ELEMENTAL"]     = "Elemental"
L["SPEC_ENHANCEMENT"]   = "Enhancement"
L["SPEC_RESTORATION_SHAMAN"] = "Restoration"
-- Mage
L["SPEC_ARCANE"]        = "Arcane"
L["SPEC_FIRE"]          = "Fire"
L["SPEC_FROST_MAGE"]    = "Frost"
-- Warlock
L["SPEC_AFFLICTION"]    = "Affliction"
L["SPEC_DEMONOLOGY"]    = "Demonology"
L["SPEC_DESTRUCTION"]   = "Destruction"
-- Monk
L["SPEC_BREWMASTER"]    = "Brewmaster"
L["SPEC_MISTWEAVER"]    = "Mistweaver"
L["SPEC_WINDWALKER"]    = "Windwalker"
-- Druid
L["SPEC_BALANCE"]       = "Balance"
L["SPEC_FERAL"]         = "Feral"
L["SPEC_GUARDIAN"]      = "Guardian"
L["SPEC_RESTORATION_DRUID"] = "Restoration"
-- Demon Hunter
L["SPEC_HAVOC"]         = "Havoc"
L["SPEC_VENGEANCE"]     = "Vengeance"
-- Evoker
L["SPEC_DEVASTATION"]   = "Devastation"
L["SPEC_PRESERVATION"]  = "Preservation"
L["SPEC_AUGMENTATION"]  = "Augmentation"

------------------------------------------------------------------------
-- SLASH COMMANDS & CHAT MESSAGES
------------------------------------------------------------------------
L["PROFILE_RESET_MSG"]  = "Profile installation status has been reset. /reload to reinstall."
L["USAGE_MSG"]          = "Usage: /ddp [install|load|reset]"
L["COMBAT_LOCKDOWN_MSG"] = "Cannot load profiles during combat."
L["UNKNOWN_SPEC"]       = "Unknown"

------------------------------------------------------------------------
-- INSTALLER UI - NAVIGATION
------------------------------------------------------------------------
L["NAV_PREV"]           = "\226\151\128 Prev"
L["NAV_NEXT"]           = "Next \226\150\182"
L["NAV_CLOSE"]          = "Close"

------------------------------------------------------------------------
-- INSTALLER - STEP TITLES
------------------------------------------------------------------------
L["STEP_WELCOME"]       = "Welcome"
L["STEP_EDITMODE"]      = "Edit Mode"
L["STEP_CDM"]           = "Cooldown Manager"
L["STEP_COMPLETE"]      = "Complete"

------------------------------------------------------------------------
-- INSTALLER - PAGE CONTENT
------------------------------------------------------------------------
-- Welcome page (page 1)
L["WELCOME_SUBTITLE"]   = "%s Profile Installation"
L["WELCOME_DESC1_FRESH"] = "Starting DDingUI profile installation."
L["WELCOME_DESC2_FRESH"] = "Click 'Next' to install profiles for each addon."
L["WELCOME_DESC1_EXISTING"] = "Loading previously installed profiles for this character."
L["WELCOME_DESC2_EXISTING"] = "Click 'Load Profiles' or click 'Next' to reinstall."
L["LOAD_PROFILES"]      = "Load Profiles"

-- Generic addon page
L["ADDON_DISABLED"]     = "%s addon is disabled."
L["SKIP_STEP"]          = "Click 'Continue' to skip this step."
L["APPLY_PROFILE"]      = "Applying %s profile."
L["APPLY"]              = "Apply"

-- ElvUI page (page 2)
L["ELVUI_NOT_INSTALLED"] = "ElvUI is not installed."
L["ELVUI_SKIP"]         = "Skipping ElvUI profile. Click 'Continue'."

-- DandersFrames page (page 7)
L["DF_SELECT_ROLE"]     = "Select the layout for your role."
L["DF_DPS_TANK"]        = "DPS / Tank"
L["DF_HEALER"]          = "Healer"

-- Blizzard Edit Mode page (page 10)
L["EDITMODE_SUBTITLE"]  = "Blizzard Edit Mode"
L["EDITMODE_DESC"]      = "Apply default Edit Mode layout."

-- Cooldown Manager page (page 11)
L["CDM_SUBTITLE"]       = "Cooldown Manager"
L["CDM_DESC"]           = "Apply specialization Cooldown Manager layout."

-- Complete page (page 12)
L["COMPLETE_SUBTITLE"]  = "Installation Complete!"
L["COMPLETE_DESC1"]     = "DDingUI profile installation is complete."
L["COMPLETE_DESC2"]     = "Click 'Reload' to save settings and reload the UI."
L["RELOAD"]             = "Reload"

------------------------------------------------------------------------
-- SETUP MESSAGES
------------------------------------------------------------------------
L["SETUP_COMPLETE"]     = "|cff00ff00%s|r profile applied!"
L["SETUP_NOT_FOUND"]    = "'%s' Setup function not found."

-- Blizzard EditMode Setup
L["EDITMODE_NO_DATA"]   = "Edit Mode layout data not found."
L["EDITMODE_COPY_TITLE"] = "|cffffffffDDing|r|cffffa300UI|r - Edit Mode Layout"
L["EDITMODE_COPY_DESC"] = "|cff00ff00Ctrl+A|r \226\134\146 |cff00ff00Ctrl+C|r to copy\n|cffffd200Esc > Edit Mode > Layout > Import|r to paste"

-- CooldownManager Setup
L["CDM_NO_SPEC"]        = "Unable to retrieve specialization info."
L["CDM_NO_DATA"]        = "No Cooldown Manager data for current spec (specID: %s)."
L["CDM_COPY_TITLE"]     = "|cffffffffDDing|r|cffffa300UI|r - Cooldown Manager"
L["CDM_COPY_DESC"]      = "|cff00ff00Ctrl+A|r \226\134\146 |cff00ff00Ctrl+C|r to copy  |cffffd200Cooldown Manager Settings > Import|r to paste"

-- DandersFrames Setup
L["DF_NO_DATA"]         = "DandersFrames %s profile data not found."
L["DF_INVALID_DATA"]    = "DandersFrames profile data is invalid."
L["DF_DPS_TANK_LABEL"]  = "DPS / Tank"
L["DF_HEALER_LABEL"]    = "Healer"

------------------------------------------------------------------------
-- COPY FRAME
------------------------------------------------------------------------
L["CONFIRM"]            = "OK"
