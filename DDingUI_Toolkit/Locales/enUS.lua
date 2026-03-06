--[[
    DDingToolKit - English Localization (Default)
    AceLocale-3.0 based
]]

local L = LibStub("AceLocale-3.0"):NewLocale("DDingUI_Toolkit", "enUS", true)
if not L then return end

-- ==========================================
-- General / Common
-- ==========================================
L["ADDON_LOADED"] = "|cFF00FF00[DDingUI Toolkit]|r Loaded. Type /ddt for settings."
L["ENABLED"] = "Enabled"
L["DISABLED"] = "Disabled"
L["SETTINGS"] = "Settings"
L["POSITION_RESET"] = "Position has been reset."
L["POSITION_LOCKED"] = "Position Locked"
L["SCALE"] = "Scale"
L["TEST_MODE"] = "Test Mode"
L["TEST_ON_OFF"] = "Test ON/OFF"
L["RESET_POSITION"] = "Reset Position"
L["MODULE_ENABLED"] = "Module Enabled"
L["FONT"] = "Font"
L["FONT_SIZE"] = "Font Size"
L["COLOR"] = "Color"
L["TEXT_COLOR"] = "Text Color"
L["SHOW_TEXT"] = "Show Text"
L["SIZE"] = "Size"
L["ICON_SIZE"] = "Icon Size"
L["OVERALL_SIZE"] = "Overall Size"
L["ALL_CHECK_ON"] = "Check All ON"
L["ALL_CHECK_OFF"] = "Check All OFF"

-- ==========================================
-- Main Frame / Tabs
-- ==========================================
L["TAB_GENERAL"] = "General"
L["TAB_TALENTBG"] = "Talent BG"
L["TAB_LFGALERT"] = "LFG Alert"
L["TAB_MAILALERT"] = "Mail Alert"
L["TAB_CURSORTRAIL"] = "Cursor Trail"
L["TAB_ITEMLEVEL"] = "Item Level"
L["TAB_NOTEPAD"] = "Notepad"
L["TAB_COMBATTIMER"] = "Combat Timer"
L["TAB_PARTYTRACKER"] = "Party Tracker"
L["TAB_MYTHICPLUS"] = "M+ Helper"
L["TAB_GOLDSPLIT"] = "Calculator"
L["TAB_DURABILITY"] = "Durability"
L["TAB_BUFFCHECKER"] = "Buff Check"
L["TAB_KEYSTONETRACKER"] = "Key Tracker"
L["TAB_CASTINGALERT"] = "Cast Alert"
L["TAB_FOCUSINTERRUPT"] = "Focus Interrupt"

-- ==========================================
-- General Panel
-- ==========================================
L["MODULE_MANAGEMENT"] = "Module Management"
L["GLOBAL_SETTINGS"] = "Global Settings"
L["SHOW_MINIMAP_BUTTON"] = "Show Minimap Button"
L["SHOW_WELCOME_MESSAGE"] = "Show Welcome Message on Login"
L["MINIMAP_POSITION_RESET"] = "Minimap button position has been reset."
L["MINIMAP_LEFT_CLICK"] = "Left-click to open configuration"
L["MINIMAP_DRAG"] = "Drag to move"
L["INFO"] = "Info"
L["VERSION"] = "Version"
L["AUTHOR"] = "Author"

-- Module descriptions for General panel
L["MODULE_TALENTBG"] = "TalentBG - Talent Frame Background Customizer"
L["MODULE_LFGALERT"] = "Party Alert - Group Application Alert"
L["MODULE_MAILALERT"] = "MailAlert - New Mail Alert"
L["MODULE_CURSORTRAIL"] = "CursorTrail - Cursor Trail Effect"
L["MODULE_ITEMLEVEL"] = "ItemLevel - Item Level/Enchant/Gem Display"
L["MODULE_NOTEPAD"] = "Notepad - Simple Notepad"
L["MODULE_COMBATTIMER"] = "CombatTimer - Combat Timer"
L["MODULE_PARTYTRACKER"] = "Party Status - Battle Res/Bloodlust/Healer Mana"
L["MODULE_MYTHICPLUS"] = "MythicPlusHelper - Dungeon Teleport"
L["MODULE_GOLDSPLIT"] = "GoldSplit - Gold Split Calculator"
L["MODULE_DURABILITY"] = "DurabilityCheck - Durability Alert"
L["MODULE_BUFFCHECKER"] = "BuffChecker - Buff Check (Food/Flask/Rune)"
L["MODULE_KEYSTONETRACKER"] = "KeystoneTracker - Party Keystone Tracker"
L["MODULE_CASTINGALERT"] = "CastingAlert - Enemy Casting Alert"
L["MODULE_FOCUSINTERRUPT"] = "FocusInterrupt - Focus Cast Bar + Interrupt"

-- ==========================================
-- CastingAlert Module
-- ==========================================
L["CASTINGALERT_DESC"] = "Shows enemy spells targeting you near the center of your screen.\nCan alert with sound when 2+ spells target you simultaneously."
L["CASTINGALERT_DISPLAY_SETTINGS"] = "Display Settings"
L["CASTINGALERT_SHOW_TARGET"] = "Show Target's Casts"
L["CASTINGALERT_ONLY_TARGETING_ME"] = "Only Show Spells Targeting Me"
L["CASTINGALERT_MAX_SHOW"] = "Max Icons"
L["CASTINGALERT_DIM_ALPHA"] = "Non-targeted Opacity"
L["CASTINGALERT_UPDATE_RATE"] = "Update Rate (sec)"
L["CASTINGALERT_POSITION_SETTINGS"] = "Position Settings"
L["CASTINGALERT_POS_X"] = "Horizontal Position (X)"
L["CASTINGALERT_POS_Y"] = "Vertical Position (Y)"
L["CASTINGALERT_SOUND_SETTINGS"] = "Sound Settings"
L["CASTINGALERT_SOUND_ENABLED"] = "Sound on Multiple Casts"
L["CASTINGALERT_SOUND_THRESHOLD"] = "Sound Threshold (N or more)"
L["CASTINGALERT_DEFAULT_SOUND"] = "Raid Warning (Default)"
L["CASTINGALERT_TITLE"] = "Casting Alert"

-- ==========================================
-- FocusInterrupt Module
-- ==========================================
L["FOCUSINTERRUPT_DESC"] = "Shows a cast bar when your focus target is casting.\nChanges color based on interrupt readiness and displays your interrupt icon."
L["FOCUSINTERRUPT_BAR_SETTINGS"] = "Cast Bar Settings"
L["FOCUSINTERRUPT_BAR_WIDTH"] = "Bar Width"
L["FOCUSINTERRUPT_BAR_HEIGHT"] = "Bar Height"
L["FOCUSINTERRUPT_INT_SETTINGS"] = "Interrupt Settings"
L["FOCUSINTERRUPT_NOTINT_HIDE"] = "Hide Non-interruptible"
L["FOCUSINTERRUPT_CD_HIDE"] = "Hide When On Cooldown"
L["FOCUSINTERRUPT_SHOW_KICK_ICON"] = "Show Interrupt Icon"
L["FOCUSINTERRUPT_SHOW_INTERRUPTER"] = "Show Interrupter Name"
L["FOCUSINTERRUPT_SHOW_TARGET"] = "Show Cast Target"
L["FOCUSINTERRUPT_SHOW_TIME"] = "Show Cast Time"
L["FOCUSINTERRUPT_MUTE"] = "Mute Sound Alert"
L["FOCUSINTERRUPT_FADE_TIME"] = "Interrupted Fade Time"
L["FOCUSINTERRUPT_KICK_ICON_SIZE"] = "Interrupt Icon Size"
L["FOCUSINTERRUPT_TEXTURE"] = "Bar Texture"
L["FOCUSINTERRUPT_DEFAULT_SOUND"] = "Raid Warning (Default)"
L["FOCUSINTERRUPT_TITLE"] = "Focus Interrupt"
L["FOCUSINTERRUPT_COLOR_SETTINGS"] = "Color Settings"
L["FOCUSINTERRUPT_INTERRUPTIBLE_COLOR"] = "Interruptible"
L["FOCUSINTERRUPT_NOTINT_COLOR"] = "Not Interruptible"
L["FOCUSINTERRUPT_CD_COLOR"] = "On Cooldown"
L["FOCUSINTERRUPT_INTERRUPTED_COLOR"] = "Interrupted"
L["FOCUSINTERRUPT_INTERRUPTED"] = "Interrupted"

-- ==========================================
-- BuffChecker Module
-- ==========================================
L["BUFFCHECKER_TITLE"] = "Buff Check"
L["BUFFCHECKER_DESC"] = "Displays icons when food/flask/weapon enchant/rune buffs are missing.\nUseful for buff checking in raids or mythic+ dungeons."
L["BUFFCHECKER_CHECK_ITEMS"] = "Check Items"
L["BUFFCHECKER_CHECK_FOOD"] = "Check Food Buff"
L["BUFFCHECKER_CHECK_FLASK"] = "Check Flask Buff"
L["BUFFCHECKER_CHECK_WEAPON"] = "Check Weapon Enchant"
L["BUFFCHECKER_CHECK_RUNE"] = "Check Rune Buff"
L["BUFFCHECKER_DISPLAY_CONDITIONS"] = "Display Conditions"
L["BUFFCHECKER_INSTANCE_ONLY"] = "Show in Instance Only"
L["BUFFCHECKER_DISPLAY_SETTINGS"] = "Display Settings"
L["BUFFCHECKER_TEXT_SETTINGS"] = "Text Settings"
L["BUFFCHECKER_TEXT_FONT"] = "Text Font"
L["BUFFCHECKER_FOOD"] = "Food"
L["BUFFCHECKER_FLASK"] = "Flask"
L["BUFFCHECKER_MAINHAND"] = "Main Hand"
L["BUFFCHECKER_OFFHAND"] = "Off Hand"
L["BUFFCHECKER_RUNE"] = "Rune"

-- ==========================================
-- TalentBG Module
-- ==========================================
L["TALENTBG_TITLE"] = "Talent Background"
L["TALENTBG_DESC"] = "Customize the talent window background image."
L["TALENTBG_MODE"] = "Background Mode"
L["TALENTBG_MODE_SPEC"] = "Per Specialization"
L["TALENTBG_MODE_CLASS"] = "Per Class"
L["TALENTBG_MODE_GLOBAL"] = "Global"
L["TALENTBG_SELECT_IMAGE"] = "Select Image"
L["TALENTBG_CURRENT_SPEC"] = "Current Spec"
L["TALENTBG_PREVIEW"] = "Preview"

-- ==========================================
-- LFGAlert Module
-- ==========================================
L["LFGALERT_TITLE"] = "LFG Alert"
L["LFGALERT_DESC"] = "Alerts when someone applies to your group."
L["LFGALERT_SOUND_ENABLED"] = "Sound Alert"
L["LFGALERT_FLASH_ENABLED"] = "Screen Flash"
L["LFGALERT_SCREEN_ALERT"] = "Screen Alert"
L["LFGALERT_CHAT_ALERT"] = "Chat Alert"
L["LFGALERT_AUTO_OPEN"] = "Auto Open LFG"
L["LFGALERT_LEADER_ONLY"] = "Leader Only"
L["LFGALERT_SOUND_FILE"] = "Alert Sound"
L["LFGALERT_SOUND_CHANNEL"] = "Sound Channel"
L["LFGALERT_POSITION"] = "Alert Position"
L["LFGALERT_DURATION"] = "Alert Duration"
L["LFGALERT_ANIMATION"] = "Animation"
L["LFGALERT_COOLDOWN"] = "Cooldown"
L["LFGALERT_DEFAULT_SOUND"] = "Ready Check (Default)"
L["LFGALERT_NEW_APPLICATION"] = "New application received!"

-- ==========================================
-- MailAlert Module
-- ==========================================
L["MAILALERT_TITLE"] = "Mail Alert"
L["MAILALERT_DESC"] = "Alerts when you receive new mail."
L["MAILALERT_SOUND_ENABLED"] = "Sound Alert"
L["MAILALERT_FLASH_ENABLED"] = "Screen Flash"
L["MAILALERT_SCREEN_ALERT"] = "Screen Alert"
L["MAILALERT_CHAT_ALERT"] = "Chat Alert"
L["MAILALERT_HIDE_IN_COMBAT"] = "Hide in Combat"
L["MAILALERT_HIDE_IN_INSTANCE"] = "Hide in Instance"
L["MAILALERT_NEW_MAIL"] = "You have new mail!"

-- ==========================================
-- CursorTrail Module
-- ==========================================
L["CURSORTRAIL_TITLE"] = "Cursor Trail"
L["CURSORTRAIL_DESC"] = "Adds visual trail effect to your cursor."
L["CURSORTRAIL_COLORS"] = "Trail Colors"
L["CURSORTRAIL_COLOR_COUNT"] = "Number of Colors"
L["CURSORTRAIL_COLOR_FLOW"] = "Color Flow"
L["CURSORTRAIL_FLOW_SPEED"] = "Flow Speed"
L["CURSORTRAIL_WIDTH"] = "Trail Width"
L["CURSORTRAIL_HEIGHT"] = "Trail Height"
L["CURSORTRAIL_ALPHA"] = "Transparency"
L["CURSORTRAIL_TEXTURE"] = "Texture"
L["CURSORTRAIL_BLEND_MODE"] = "Blend Mode"
L["CURSORTRAIL_PRESETS"] = "Presets"

-- ==========================================
-- ItemLevel Module
-- ==========================================
L["ITEMLEVEL_TITLE"] = "Item Level Display"
L["ITEMLEVEL_DESC"] = "Displays item level on equipment in bags and character panel."
L["ITEMLEVEL_SHOW_BAGS"] = "Show in Bags"
L["ITEMLEVEL_SHOW_CHARACTER"] = "Show on Character"
L["ITEMLEVEL_SHOW_INSPECT"] = "Show on Inspect"
L["ITEMLEVEL_SHOW_QUALITY_COLOR"] = "Quality Color"

-- ==========================================
-- Notepad Module
-- ==========================================
L["NOTEPAD_TITLE"] = "Notepad"
L["NOTEPAD_DESC"] = "Simple in-game notepad for taking notes."
L["NOTEPAD_SAVE"] = "Save"
L["NOTEPAD_CLEAR"] = "Clear"
L["NOTEPAD_SAVED"] = "Note saved!"
L["NOTEPAD_CLEARED"] = "Note cleared!"

-- ==========================================
-- CombatTimer Module
-- ==========================================
L["COMBATTIMER_TITLE"] = "Combat Timer"
L["COMBATTIMER_DESC"] = "Shows elapsed combat time."
L["COMBATTIMER_FORMAT"] = "Time Format"
L["COMBATTIMER_SHOW_MS"] = "Show Milliseconds"
L["COMBATTIMER_HIDE_OOC"] = "Hide Out of Combat"

-- ==========================================
-- PartyTracker Module
-- ==========================================
L["PARTYTRACKER_TITLE"] = "Party Tracker"
L["PARTYTRACKER_DESC"] = "Track party member abilities and cooldowns."
L["PARTYTRACKER_TRACKED_SPELLS"] = "Tracked Spells"
L["PARTYTRACKER_ADD_SPELL"] = "Add Spell"
L["PARTYTRACKER_REMOVE_SPELL"] = "Remove Spell"
L["PARTYTRACKER_BAR_TEXTURE"] = "Bar Texture"
L["PARTYTRACKER_BAR_WIDTH"] = "Bar Width"
L["PARTYTRACKER_BAR_HEIGHT"] = "Bar Height"
L["PARTYTRACKER_GROWTH_DIRECTION"] = "Growth Direction"
L["PARTYTRACKER_SHOW_ICON"] = "Show Icon"
L["PARTYTRACKER_SHOW_NAME"] = "Show Name"
L["PARTYTRACKER_SHOW_TIME"] = "Show Time"

-- ==========================================
-- MythicPlusHelper Module
-- ==========================================
L["MYTHICPLUS_TITLE"] = "Mythic+ Helper"
L["MYTHICPLUS_DESC"] = "Useful tools for mythic+ dungeons."
L["MYTHICPLUS_DEATH_COUNTER"] = "Death Counter"
L["MYTHICPLUS_TIMER"] = "Timer"
L["MYTHICPLUS_ENEMY_FORCES"] = "Enemy Forces"

-- ==========================================
-- GoldSplit Module
-- ==========================================
L["GOLDSPLIT_TITLE"] = "Gold Split"
L["GOLDSPLIT_DESC"] = "Calculate gold split for boosting runs."
L["GOLDSPLIT_TOTAL_GOLD"] = "Total Gold"
L["GOLDSPLIT_NUM_PLAYERS"] = "Number of Players"
L["GOLDSPLIT_CALCULATE"] = "Calculate"
L["GOLDSPLIT_RESULT"] = "Each player gets: %s"
L["GOLDSPLIT_ANNOUNCE"] = "Announce"
L["GOLDSPLIT_CHAT_TYPE"] = "Chat Type"

-- ==========================================
-- DurabilityCheck Module
-- ==========================================
L["DURABILITY_TITLE"] = "Durability Check"
L["DURABILITY_DESC"] = "Alerts when equipment durability is low."
L["DURABILITY_THRESHOLD"] = "Warning Threshold"
L["DURABILITY_SOUND_ENABLED"] = "Sound Alert"
L["DURABILITY_WARNING"] = "Low durability! (%d%%)"

-- ==========================================
-- Sound Channels
-- ==========================================
L["CHANNEL_MASTER"] = "Master"
L["CHANNEL_SFX"] = "Sound Effects"
L["CHANNEL_MUSIC"] = "Music"
L["CHANNEL_AMBIENCE"] = "Ambience"
L["CHANNEL_DIALOG"] = "Dialog"

-- ==========================================
-- Positions
-- ==========================================
L["POS_TOP"] = "Top"
L["POS_BOTTOM"] = "Bottom"
L["POS_LEFT"] = "Left"
L["POS_RIGHT"] = "Right"
L["POS_CENTER"] = "Center"
L["POS_TOPLEFT"] = "Top Left"
L["POS_TOPRIGHT"] = "Top Right"
L["POS_BOTTOMLEFT"] = "Bottom Left"
L["POS_BOTTOMRIGHT"] = "Bottom Right"

-- ==========================================
-- Animations
-- ==========================================
L["ANIM_NONE"] = "None"
L["ANIM_FADE"] = "Fade"
L["ANIM_SLIDE"] = "Slide"
L["ANIM_BOUNCE"] = "Bounce"
L["ANIM_PULSE"] = "Pulse"

-- ==========================================
-- Growth Directions
-- ==========================================
L["GROWTH_UP"] = "Up"
L["GROWTH_DOWN"] = "Down"
L["GROWTH_LEFT"] = "Left"
L["GROWTH_RIGHT"] = "Right"

-- ==========================================
-- Common UI Elements
-- ==========================================
L["ADD"] = "Add"
L["APPLY"] = "Apply"
L["CANCEL"] = "Cancel"
L["CLOSE"] = "Close"
L["DELETE"] = "Delete"
L["EDIT"] = "Edit"
L["SAVE"] = "Save"
L["NEW"] = "New"
L["OPEN"] = "Open"
L["TEST"] = "Test"
L["TEST_ALERT"] = "Test Alert"
L["RESET_TO_DEFAULT"] = "Reset to Default"
L["ALERT_METHOD"] = "Alert Method"
L["SOUND_SETTINGS"] = "Sound Settings"
L["SOUND_CUSTOM_PATH"] = "Custom Path (mp3/ogg/wav)"
L["SOUND_TEST"] = "Test"
L["COMBATTIMER_DEFAULT_SOUND"] = "Default (Countdown)"
L["SCREEN_ALERT_SETTINGS"] = "Screen Alert Settings"
L["DISPLAY_SETTINGS"] = "Display Settings"
L["ALERT_POSITION"] = "Alert Position"
L["ALERT_SIZE"] = "Alert Size"
L["ALERT_COOLDOWN"] = "Alert Cooldown (sec)"
L["DISPLAY_DURATION"] = "Display Duration (sec)"
L["CONDITIONS"] = "Conditions"
L["ANIMATION"] = "Animation"
L["FLASH_TASKBAR"] = "Flash Taskbar"
L["BACKGROUND"] = "Background"
L["BACKGROUND_ALPHA"] = "Background Opacity"
L["SHOW_BACKGROUND"] = "Show Background"
L["LOCKED"] = "Locked"
L["UNLOCKED"] = "Unlocked"
L["COMBAT_ONLY"] = "Combat Only"
L["HIDE_IN_COMBAT"] = "Hide in Combat"
L["HIDE_IN_INSTANCE"] = "Hide in Instance"
L["PRESET"] = "Preset"
L["CUSTOM"] = "Custom"
L["WIDTH"] = "Width"
L["HEIGHT"] = "Height"
L["TRANSPARENCY"] = "Transparency"
L["TEXTURE"] = "Texture"
L["LIFETIME"] = "Lifetime"
L["MAX_COUNT"] = "Max Count"
L["SPACING"] = "Spacing"
L["LAYER"] = "Layer"
L["TEXT_ALIGN"] = "Text Align"
L["ALIGN_LEFT"] = "Left"
L["ALIGN_CENTER"] = "Center"
L["ALIGN_RIGHT"] = "Right"
L["USAGE"] = "Usage"
L["QUICK_ACCESS"] = "Quick Access"
L["SAVED_NOTES"] = "Saved Notes"
L["SHOW_IN_PARTY"] = "Show in Party"
L["SHOW_IN_RAID"] = "Show in Raid"
L["MANA_BAR"] = "Mana Bar"
L["MANA_TEXT"] = "Mana Text"
L["CHAT_SETTINGS"] = "Chat Settings"
L["CHAT_CHANNEL"] = "Chat Channel"
L["DEFAULT_CHAT_CHANNEL"] = "Default Chat Channel"
L["THRESHOLD"] = "Threshold"
L["TITLE_SIZE"] = "Title Size"
L["PERCENT_SIZE"] = "Percent Size"
L["SOUND_ON_START"] = "Sound on Start"
L["PRINT_TO_CHAT"] = "Print to Chat"
L["HIDE_DELAY"] = "Hide Delay"
L["COLOR_BY_TIME"] = "Color by Time"
L["RELOAD_REQUIRED"] = "(Reload Required)"
L["RELOAD_UI_CONFIRM"] = "This change requires a UI reload.\nReload now?"
L["MODULE_DISABLED_MSG"] = "Module is disabled"
L["MODULE_DISABLED_HINT"] = "Enable the module in the General tab"

-- ==========================================
-- TalentBG Extended
-- ==========================================
L["TALENTBG_SCOPE"] = "Apply Scope"
L["TALENTBG_SELECT_BG"] = "Select Background"
L["TALENTBG_ADD_BG"] = "Add Background (filename only)"
L["TALENTBG_DELETE_CONFIRM"] = "Delete background '%s'?"
L["TALENTBG_BG_DELETED"] = "Background deleted: %s"
L["TALENTBG_BG_ADDED"] = "Background added: %s"
L["TALENTBG_BG_EXISTS"] = "Background already exists: %s"
L["TALENTBG_ENTER_FILENAME"] = "Please enter a filename."
L["TALENTBG_APPLIED"] = "Background applied - %s"
L["TALENTBG_SELECT_TEXTURE"] = "Please select a texture."
L["TALENTBG_NOT_IN_COMBAT"] = "Cannot change during combat."
L["TALENTBG_RESET_CONFIRM"] = "Restore to default specialization background?\n\n|cFFFFFF00UI will reload.|r"

-- ==========================================
-- LFGAlert Extended
-- ==========================================
L["LFGALERT_FLASH_DESC"] = "Flash Taskbar"
L["LFGALERT_SCREEN_DESC"] = "Show Screen Alert"
L["LFGALERT_CHAT_DESC"] = "Chat Alert"
L["LFGALERT_AUTO_OPEN_DESC"] = "Auto Open LFG Window"
L["LFGALERT_LEADER_ONLY_DESC"] = "Alert Only for Leader/Assistant"
L["LFGALERT_TEST_MSG"] = "LFGAlert test alert!"
L["LFGALERT_NEW_APPLICANTS"] = "%d new applicant(s) waiting."

-- ==========================================
-- MailAlert Extended
-- ==========================================
L["MAILALERT_CONDITION_SETTINGS"] = "Condition Settings"
L["MAILALERT_HIDE_IN_COMBAT_DESC"] = "Hide Alert in Combat"
L["MAILALERT_HIDE_IN_INSTANCE_DESC"] = "Hide in Dungeon/Raid"
L["MAILALERT_TEST_MSG"] = "MailAlert test alert!"
L["MAILALERT_NEW_MAIL_MSG"] = "You have new mail!"

-- ==========================================
-- CursorTrail Extended
-- ==========================================
L["CURSORTRAIL_BASIC_SETTINGS"] = "Basic Settings"
L["CURSORTRAIL_ENABLE"] = "Enable Cursor Trail"
L["CURSORTRAIL_COLOR_PRESETS"] = "Color Presets"
L["CURSORTRAIL_COLOR_SETTINGS"] = "Color Settings"
L["CURSORTRAIL_COLOR_NUM"] = "Number of Colors"
L["CURSORTRAIL_COLOR_N"] = "Color %d"
L["CURSORTRAIL_COLOR_FLOW_DESC"] = "Color Flow (Rainbow Effect)"
L["CURSORTRAIL_APPEARANCE"] = "Appearance"
L["CURSORTRAIL_PERFORMANCE"] = "Performance (FPS Impact)"
L["CURSORTRAIL_PERFORMANCE_WARNING"] = "|cffff6600Warning: Longer lifetime and more dots will decrease FPS!|r"
L["CURSORTRAIL_DOT_LIFETIME"] = "Dot Lifetime (sec)"
L["CURSORTRAIL_MAX_DOTS"] = "Max Dot Count"
L["CURSORTRAIL_DOT_SPACING"] = "Dot Spacing"
L["CURSORTRAIL_DISPLAY_CONDITIONS"] = "Display Conditions"
L["CURSORTRAIL_COMBAT_ONLY"] = "Show Only in Combat"
L["CURSORTRAIL_HIDE_INSTANCE"] = "Hide in Dungeon/Raid"
L["CURSORTRAIL_DISPLAY_LAYER"] = "Display Layer"
L["CURSORTRAIL_BLEND_ADD"] = "Glow (ADD)"
L["CURSORTRAIL_BLEND_BLEND"] = "Opaque (BLEND)"
L["CURSORTRAIL_LAYER_TOP"] = "Top (TOOLTIP)"
L["CURSORTRAIL_LAYER_BG"] = "Background (BACKGROUND)"

-- ==========================================
-- ItemLevel Extended
-- ==========================================
L["ITEMLEVEL_DISPLAY_SETTINGS"] = "Display Settings"
L["ITEMLEVEL_SHOW_ILVL"] = "Show Item Level"
L["ITEMLEVEL_SHOW_ENCHANT"] = "Show Enchant"
L["ITEMLEVEL_SHOW_GEMS"] = "Show Gem Icons"
L["ITEMLEVEL_SHOW_AVG"] = "Show Average iLvl (2 decimals)"
L["ITEMLEVEL_SHOW_ENHANCED"] = "Show Enhanced Stats (value + percent)"
L["ITEMLEVEL_SELF_SETTINGS"] = "Your Character Settings"
L["ITEMLEVEL_SELF_ILVL_SIZE"] = "Item Level Font Size"
L["ITEMLEVEL_SELF_ENCHANT_SIZE"] = "Enchant Font Size"
L["ITEMLEVEL_SELF_GEM_SIZE"] = "Gem Icon Size"
L["ITEMLEVEL_SELF_AVG_SIZE"] = "Average iLvl Size"
L["ITEMLEVEL_INSPECT_SETTINGS"] = "Inspect Settings"
L["ITEMLEVEL_INSPECT_ILVL_SIZE"] = "Item Level Font Size"
L["ITEMLEVEL_INSPECT_ENCHANT_SIZE"] = "Enchant Font Size"
L["ITEMLEVEL_INSPECT_GEM_SIZE"] = "Gem Icon Size"
L["ITEMLEVEL_RESET_MSG"] = "ItemLevel settings have been reset."

-- ==========================================
-- Notepad Extended
-- ==========================================
L["NOTEPAD_BASIC_SETTINGS"] = "Basic Settings"
L["NOTEPAD_SHOW_PVE_BUTTON"] = "Show Notepad Button in LFG Window"
L["NOTEPAD_USAGE_TITLE"] = "Usage"
L["NOTEPAD_USAGE_TEXT"] = "|cFFFFFF001.|r Click 'Notepad' button in LFG window\n|cFFFFFF002.|r Or type |cFF00CCFF/ddt notepad|r\n|cFFFFFF003.|r Click 'New' button to add memo\n|cFFFFFF004.|r Click memo in list to view/edit/delete"
L["NOTEPAD_OPEN"] = "Open Notepad"
L["NOTEPAD_COUNT"] = "Saved Notes: %d"
L["NOTEPAD_EMPTY"] = "No saved notes."
L["NOTEPAD_NEW_MEMO"] = "New Memo"
L["NOTEPAD_MEMO_LIST"] = "Memo List"
L["NOTEPAD_WRITE_MEMO"] = "Write Memo"
L["NOTEPAD_DETAIL_VIEW"] = "Memo Detail"
L["NOTEPAD_MEMO_NAME"] = "Memo Name"
L["NOTEPAD_PARTY_NAME"] = "Party Name"
L["NOTEPAD_DETAILS"] = "Details"
L["NOTEPAD_DELETE_CONFIRM"] = "Are you sure you want to delete '%s' memo?"
L["NOTEPAD_YES"] = "Yes"
L["NOTEPAD_NO"] = "No"

-- ==========================================
-- CombatTimer Extended
-- ==========================================
L["COMBATTIMER_DISPLAY_SETTINGS"] = "Display Settings"
L["COMBATTIMER_SHOW_MS"] = "Show Milliseconds (.XX)"
L["COMBATTIMER_SHOW_BG"] = "Show Background"
L["COMBATTIMER_COLOR_BY_TIME"] = "Change Color by Time (30s/60s/120s)"
L["COMBATTIMER_FONT_SETTINGS"] = "Font Settings"
L["COMBATTIMER_ALERT_SETTINGS"] = "Alert Settings"
L["COMBATTIMER_SOUND_ON_START"] = "Sound on Combat Start"
L["COMBATTIMER_PRINT_TO_CHAT"] = "Print Time to Chat on Combat End"
L["COMBATTIMER_TIMING_SETTINGS"] = "Timing Settings"
L["COMBATTIMER_HIDE_DELAY"] = "Show After Combat Ends (sec)"
L["COMBATTIMER_POSITION_RESET"] = "Combat timer position has been reset."

-- ==========================================
-- PartyTracker Extended
-- ==========================================
L["PARTYTRACKER_MODULE_ENABLE"] = "Module Enable"
L["PARTYTRACKER_ENABLE_DESC"] = "Enable PartyTracker (Reload Required)"
L["PARTYTRACKER_DISPLAY_SETTINGS"] = "Display Settings"
L["PARTYTRACKER_SHOW_PARTY"] = "Show in Party (Battle Res/Bloodlust/Healer Mana)"
L["PARTYTRACKER_SHOW_RAID"] = "Show in Raid (Healer Mana Only)"
L["PARTYTRACKER_SHOW_MANA_BAR"] = "Show Healer Mana Bar"
L["PARTYTRACKER_SHOW_MANA_TEXT"] = "Show Healer Mana Percent Text"
L["PARTYTRACKER_SIZE_SETTINGS"] = "Size Settings"
L["PARTYTRACKER_FONT_SETTINGS"] = "Font Settings"
L["PARTYTRACKER_MANA_BAR_SETTINGS"] = "Healer Mana Bar Settings"
L["PARTYTRACKER_MANA_BAR_WIDTH"] = "Mana Bar Width"
L["PARTYTRACKER_MANA_BAR_HEIGHT"] = "Mana Bar Height"
L["PARTYTRACKER_MANA_BAR_OFFSET_X"] = "Mana Bar X Offset"
L["PARTYTRACKER_MANA_BAR_OFFSET_Y"] = "Mana Bar Y Offset"
L["PARTYTRACKER_MANA_BAR_TEXTURE"] = "Mana Bar Texture"
L["PARTYTRACKER_POSITION_RESET"] = "PartyTracker position has been reset."
L["PARTYTRACKER_MANA_POSITION_RESET"] = "Reset Mana Position"
L["PARTYTRACKER_MANA_POSITION_RESET_MSG"] = "Healer mana frame position has been reset."
L["PARTYTRACKER_SEPARATE_MANA"] = "Separate Healer Mana Frame"
L["PARTYTRACKER_SEPARATE_MANA_DESC"] = "Display healer mana in a separate draggable frame"
L["PARTYTRACKER_MANA_LOCKED"] = "Lock Mana Frame Position"
L["PARTYTRACKER_MANA_SCALE"] = "Mana Frame Scale"
L["PARTYTRACKER_BREZ_LUST"] = "Brez+Lust"
L["PARTYTRACKER_HEALER_MANA"] = "Healer Mana"
L["PARTYTRACKER_INFO_TITLE"] = "Tracker Info"
L["PARTYTRACKER_INFO_TEXT"] = "|cFFFFFFFFParty (5-man)|r\n• Battle Res - Charge Count & Cooldown\n• Bloodlust - Buff/Exhaustion Status\n• Healer Mana - Mana Bar\n\n|cFFFFFFFFRaid|r\n• Battle Res - Charge Count & Cooldown\n• Healer Mana - Up to 6 healers\n\n|cFFFFFFFFDisplay Conditions|r\n• Auto show when in Party/Raid\n• Drag to move position"
L["PARTYTRACKER_HEALERS_TITLE"] = "Supported Healer Specs"
L["PARTYTRACKER_HEALERS_TEXT"] = "• Restoration Druid\n• Holy/Discipline Priest\n• Holy Paladin\n• Restoration Shaman\n• Mistweaver Monk\n• Preservation Evoker"

-- ==========================================
-- MythicPlusHelper Extended
-- ==========================================
L["MYTHICPLUS_TITLE_FULL"] = "Mythic+ Dungeon Helper"
L["MYTHICPLUS_DESC_FULL"] = "Shows dungeon name, completion level, and score on dungeon icons\nin the M+ tab, and casts teleport on click."
L["MYTHICPLUS_ENABLE_OVERLAY"] = "Enable Overlay"
L["MYTHICPLUS_TEXT_SIZE"] = "Text Size"
L["MYTHICPLUS_OPEN_TAB"] = "Open M+ Dungeon Tab"
L["MYTHICPLUS_USAGE_TITLE"] = "Usage"
L["MYTHICPLUS_USAGE_TEXT"] = "- Use /ddt tp command to open M+ dungeon tab\n- Dungeon name abbreviation shows above icon\n- Large number in center is highest completed level\n- Number below is dungeon score\n- Color changes based on score (white→green→blue→purple→orange)\n- Clicking dungeon icon casts teleport\n- Teleport is learned after completing +20 or higher"

-- ==========================================
-- GoldSplit Extended
-- ==========================================
L["GOLDSPLIT_TITLE_FULL"] = "GoldSplit - Distribution Calculator"
L["GOLDSPLIT_DESC_FULL"] = "Calculate and share raid gold distribution.\n\n|cFFFFFF00Slash Commands:|r /분배금, /goldsplit\n\n|cFFFFFF00Features:|r\n• Manual amount input and adjustment\n• N+1 distribution calculation\n• Auto share to party/raid chat"
L["GOLDSPLIT_DEFAULT_CHANNEL"] = "Default Chat Channel"
L["GOLDSPLIT_SAY"] = "Say (SAY)"
L["GOLDSPLIT_PARTY"] = "Party (PARTY)"
L["GOLDSPLIT_RAID"] = "Raid (RAID)"
L["GOLDSPLIT_NOTE"] = "|cFFFFFF00Note:|r Automatically uses party/raid channel when in group."
L["GOLDSPLIT_POSITION_SETTINGS"] = "Position Settings"
L["GOLDSPLIT_POSITION_RESET_MSG"] = "Window position has been reset."
L["GOLDSPLIT_DRAG_TIP"] = "|cFFFFFF00TIP:|r Drag the title bar to move the window."
L["GOLDSPLIT_OPEN_WINDOW"] = "Open GoldSplit Window"

-- ==========================================
-- DurabilityCheck Extended
-- ==========================================
L["DURABILITY_DESC_FULL"] = "Shows alert when durability falls below threshold.\nAutomatically hides during combat.\n\nSlash Commands: /내구도, /durability"
L["DURABILITY_DISPLAY_CONDITIONS"] = "Display Conditions"
L["DURABILITY_THRESHOLD_DESC"] = "Durability Threshold (%)"
L["DURABILITY_THRESHOLD_NOTE"] = "(Shows when below this value)"
L["DURABILITY_ALERT_SETTINGS"] = "Alert Settings"
L["DURABILITY_SOUND_DESC"] = "Sound Alert (on threshold)"
L["DURABILITY_SCREEN_SETTINGS"] = "Screen Settings"
L["DURABILITY_POSITION_RESET_MSG"] = "Durability alert position has been reset."
L["DURABILITY_DRAG_TIP"] = "|cFFFFFF00TIP:|r Drag the alert window to move position."

-- ==========================================
-- Module Runtime Messages
-- ==========================================
-- CombatTimer
L["COMBATTIMER_TIME_RESULT"] = "Combat time: %d:%05.2f"
L["COMBATTIMER_TEST_START"] = "Combat timer test started (click again to stop)"

-- MailAlert
L["MAILALERT_TEST_MSG"] = "MailAlert test alert!"
L["MAILALERT_NEW_MAIL_ARRIVED"] = "You have new mail!"

-- LFGAlert
L["LFGALERT_TEST_MSG"] = "LFGAlert test alert!"
L["LFGALERT_APPLICANTS_ARRIVED"] = "%d new applicant(s) arrived!"

-- GoldSplit
L["GOLDSPLIT_RESET_DONE"] = "Distribution amount has been reset."

-- MythicPlusHelper
L["MYTHICPLUS_ENABLED_MSG"] = "MythicPlusHelper enabled (M+ dungeon tab enhanced)"

-- PartyTracker
L["PARTYTRACKER_TEST_END"] = "PartyTracker test mode ended"
L["PARTYTRACKER_TEST_START"] = "PartyTracker test mode (click again to stop)"
L["PARTYTRACKER_COMMANDS"] = "Commands:"
L["PARTYTRACKER_SETTINGS_NOT_FOUND"] = "Settings not found."
L["PARTYTRACKER_MODULE_ENABLED_MSG"] = "Module |cFF00FF00enabled|r (reload required: /reload)"
L["PARTYTRACKER_MODULE_DISABLED_MSG"] = "Module |cFFFF0000disabled|r (reload required: /reload)"
L["PARTYTRACKER_PARTY_DISPLAY"] = "Party display:"
L["PARTYTRACKER_RAID_DISPLAY"] = "Raid display:"
L["PARTYTRACKER_MANA_BAR_DISPLAY"] = "Mana bar display:"
L["PARTYTRACKER_MANA_TEXT_DISPLAY"] = "Mana text display:"
L["PARTYTRACKER_CURRENT_SETTINGS"] = "Current settings:"
L["PARTYTRACKER_MODULE_ACTIVE"] = "Module enabled:"
L["PARTYTRACKER_ALL_ENABLED"] = "All options |cFF00FF00enabled|r (reload required: /reload)"
L["PARTYTRACKER_UNKNOWN_CMD"] = "Unknown command. Use /pt help for help"
L["PARTYTRACKER_ON"] = "|cFF00FF00ON|r"
L["PARTYTRACKER_OFF"] = "|cFFFF0000OFF|r"

-- DurabilityCheck
L["DURABILITY_CHECK_MSG"] = "Durability check: %d%%"

-- KeystoneTracker
L["KEYSTONETRACKER_ENABLED"] = "KeystoneTracker enabled. Open with /ddt keys"
L["KEYSTONETRACKER_PARTY_KEYS"] = "Party Keystones"
L["KEYSTONETRACKER_NO_KEY"] = "No keystone"
L["KEYSTONETRACKER_NO_INFO"] = "No info"

-- KeystoneTracker Config
L["KEYSTONETRACKER_TITLE"] = "Keystone Tracker"
L["KEYSTONETRACKER_DESC"] = "Track and share party members' keystone info."
L["KEYSTONETRACKER_SHOW_IN_PARTY"] = "Show in Party"
L["KEYSTONETRACKER_SHOW_IN_RAID"] = "Show in Raid"
L["KEYSTONETRACKER_TOGGLE_WINDOW"] = "Open/Close Window"
L["KEYSTONETRACKER_USAGE_TITLE"] = "|cFFFFD100Usage:|r"
L["KEYSTONETRACKER_USAGE_TEXT"] = "- Keystone info is automatically exchanged when joining a party\n- Info is automatically shared between DDingToolKit users\n- Use /dding keys command to open the window"


-- ==========================================
-- Additional Runtime Messages
-- ==========================================
-- MailAlert frame text
L["MAILALERT_NEW_MAIL_TEXT"] = "You have new mail!"
L["MAILALERT_TEST_TEXT"] = "Test alert!"

-- LFGAlert frame text
L["LFGALERT_NEW_APPLICANT_TITLE"] = "New applicant!"
L["LFGALERT_TEST_TEXT"] = "Test alert!"
L["LFGALERT_WORKING_PROPERLY"] = "LFGAlert is working properly."
L["LFGALERT_WAITING_COUNT"] = "%d applicant(s) waiting."

-- GoldSplit UI
L["GOLDSPLIT_TOTAL_GOLD"] = "Total Gold"
L["GOLDSPLIT_MANUAL_INPUT"] = "Manual Input"
L["GOLDSPLIT_ADJUST_AMOUNT"] = "Adjust Amount (+/-)"
L["GOLDSPLIT_CALCULATE_SHARE"] = "Calculate and Share"
L["GOLDSPLIT_RESET"] = "Reset"
L["GOLDSPLIT_RESET_CONFIRM"] = "Reset distribution amount?"
L["GOLDSPLIT_CONFIRM"] = "OK"
L["GOLDSPLIT_CANCEL"] = "Cancel"
L["GOLDSPLIT_INPUT_TITLE"] = "Input Amount"
L["GOLDSPLIT_ADJUST_TITLE"] = "Adjust Amount"
L["GOLDSPLIT_CALC_TITLE"] = "Calculate Distribution"
L["GOLDSPLIT_SPLIT_PLAYERS"] = "Split players:"
L["GOLDSPLIT_PREVIEW_FORMAT"] = "Per person: %sG | Per party: %sG"
L["GOLDSPLIT_SHARE_CHAT"] = "Share to Chat"

-- AutoRepair
L["TAB_AUTOREPAIR"] = "Auto Repair"
L["MODULE_AUTOREPAIR"] = "Auto Repair"
L["AUTOREPAIR_TITLE"] = "Auto Repair"
L["AUTOREPAIR_DESC"] = "Automatically repairs all equipment when visiting a merchant."
L["AUTOREPAIR_USE_GUILD_BANK"] = "Use Guild Bank for repair"
L["AUTOREPAIR_GUILD_BANK_NOTE"] = "Uses guild bank funds first. Falls back to personal gold if unavailable."
L["AUTOREPAIR_CHAT_OUTPUT"] = "Show repair cost in chat"
L["AUTOREPAIR_REPAIRED"] = "Equipment repaired"
L["AUTOREPAIR_GUILD_BANK"] = "Guild Bank"
L["AUTOREPAIR_PERSONAL_GOLD"] = "Personal Gold"

-- DurabilityCheck
L["DURABILITY_REPAIR_NEEDED"] = "Repair Needed"

-- MythicPlusHelper tooltips
L["MYTHICPLUS_NO_TELEPORT_INFO"] = "Teleport spell info not available"
L["MYTHICPLUS_NOT_LEARNED"] = "Not learned (+20 clear required)"
L["MYTHICPLUS_AVAILABLE"] = "Available"
L["MYTHICPLUS_WEEKLY_COUNT"] = "Weekly keystones: %d"

-- ==========================================
-- SkyridingTracker Module
-- ==========================================
L["TAB_SKYRIDINGTRACKER"] = "Skyriding Tracker"
L["MODULE_SKYRIDINGTRACKER"] = "SkyridingTracker - Skyriding Flight Tracker"
L["SKYRIDINGTRACKER_TITLE"] = "Skyriding Tracker"
L["SKYRIDINGTRACKER_DESC"] = "Displays vigor, second wind, and whirling surge on a circular HUD while skyriding."
L["SKYRIDINGTRACKER_ONLY_MOUNTED"] = "Show Only While Mounted"
L["SKYRIDINGTRACKER_FADEOUT"] = "Fade Out Duration (sec)"
L["SKYRIDINGTRACKER_SURGE_POS"] = "Whirling Surge Position"
L["SKYRIDINGTRACKER_SURGE_BOTTOM"] = "Bottom"
L["SKYRIDINGTRACKER_SURGE_TOP"] = "Top"
L["SKYRIDINGTRACKER_BORDER"] = "Border Size"
L["SKYRIDINGTRACKER_POS_X"] = "X Position"
L["SKYRIDINGTRACKER_POS_Y"] = "Y Position"
L["SKYRIDINGTRACKER_HIDE_DDINGUI"] = "Hide DDingUI Elements"
L["SKYRIDINGTRACKER_HIDE_DDINGUI_DESC"] = "Hide DDingUI UF, CDM, Essential frames while flying."
L["SKYRIDINGTRACKER_HIDE_OUTSIDE_ONLY"] = "Hide Outside Instances Only"
L["SKYRIDINGTRACKER_POSITION_RESET_MSG"] = "Tracker position has been reset."
L["SKYRIDINGTRACKER_INFO_TITLE"] = "Tracker Layout"
L["SKYRIDINGTRACKER_INFO_TEXT"] = "• |cFF00CCFFLeft C-shape:|r Vigor charges (up to 6)\n• |cFF00FF00Right reverse-C:|r Second Wind charges (up to 3)\n• |cFFFF8800Bottom curve:|r Whirling Surge cooldown"
L["SKYRIDINGTRACKER_COLOR_VIGOR"] = "Vigor Color"
L["SKYRIDINGTRACKER_COLOR_VIGOR_ACTIVE"] = "Vigor (Active)"
L["SKYRIDINGTRACKER_COLOR_VIGOR_DIM"] = "Vigor (Dim)"
L["SKYRIDINGTRACKER_COLOR_WIND"] = "Second Wind Color"
L["SKYRIDINGTRACKER_COLOR_WIND_ACTIVE"] = "Second Wind (Active)"
L["SKYRIDINGTRACKER_COLOR_WIND_DIM"] = "Second Wind (Dim)"
L["SKYRIDINGTRACKER_COLOR_SURGE"] = "Whirling Surge Color"
L["SKYRIDINGTRACKER_COLOR_SURGE_ACTIVE"] = "Whirling Surge (Active)"
L["SKYRIDINGTRACKER_COLOR_SURGE_DIM"] = "Whirling Surge (Dim)"
