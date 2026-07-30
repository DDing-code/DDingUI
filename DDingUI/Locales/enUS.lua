--[[
    DDingUI Localization - English (enUS)
    Base locale for all English strings
--]]

-- External debug tools probe tables for helper methods such as ToDebugString.
-- Silent fallback keeps those probes from being reported as missing translations.
local L = LibStub("AceLocale-3.0"):NewLocale("DDingUI", "enUS", true, true)

if not L then return end

L["Add Trinket Buff"] = "Add Buff"
L["Remove Trinket Buff"] = "Remove Buff"

-- ============================================================
-- GENERAL
-- ============================================================
L["DDingUI"] = "DDingUI"
L["Left-click to open configuration"] = "Left-click to open configuration"
L["Right-click to open configuration"] = "Right-click to open configuration"
L["Right-click to toggle move mode"] = "Right-click to toggle move mode"

-- ============================================================
-- CONFIG - GENERAL OPTIONS
-- ============================================================
L["Disabled"] = "Disabled"
L["Settings"] = "Settings"
L["Options"] = "Options"

-- ============================================================
-- CONFIG - RESOURCE BARS
-- ============================================================
L["Track a specific buff's stacks and display as a resource bar. Useful for tracking buffs like Fury Warrior's Whirlwind."] = "Track a specific buff's stacks and display as a resource bar. Useful for tracking buffs like Fury Warrior's Whirlwind."
L["The spell ID of the buff to track. Example: 85739 for Whirlwind (Fury Warrior)"] = "The spell ID of the buff to track. Example: 85739 for Whirlwind (Fury Warrior)"
L["Maximum number of stacks for the buff"] = "Maximum number of stacks for the buff"
L["Hide When Zero Stacks"] = "Hide When Zero Stacks"
L["Hide the bar when the buff has no stacks"] = "Hide the bar when the buff has no stacks"
L["Show Stack Count"] = "Show Stack Count"
L["Display current stack count as text"] = "Display current stack count as text"
L["Color of the buff tracker bar"] = "Color of the buff tracker bar"
L["Track a specific buff's stacks and display as a resource bar. Example: Fury Warrior's Whirlwind buff (Spell ID: 85739)."] = "Track a specific buff's stacks and display as a resource bar. Example: Fury Warrior's Whirlwind buff (Spell ID: 85739)."
L["Background color for the bar"] = "Background color for the bar"
-- Manual tracking mode (like IWT)
L["Choose how to track the buff. 'Buff API' uses Blizzard's aura system. 'Manual (Spell Cast)' tracks spell casts like ImprovedWhirlwindTracker - more reliable for some buffs during combat."] = "Choose how to track the buff. 'Buff API' uses Blizzard's aura system. 'Manual (Spell Cast)' tracks spell casts like ImprovedWhirlwindTracker - more reliable for some buffs during combat."
L["Buff API (Default)"] = "Buff API (Default)"
L["Manual (Spell Cast)"] = "Manual (Spell Cast)"
L["Manual mode tracks spell casts instead of buff state. Configure generator spells (gain max stacks) and spender spells (consume 1 stack). Example for Fury Warrior Whirlwind: Generators=190411,6343,435222 Spenders=23881,85288,280735"] = "Manual mode tracks spell casts instead of buff state. Configure generator spells (gain max stacks) and spender spells (consume 1 stack). Example for Fury Warrior Whirlwind: Generators=190411,6343,435222 Spenders=23881,85288,280735"
L["Generator Spell IDs"] = "Generator Spell IDs"
L["Comma-separated spell IDs that grant max stacks. Example: 190411,6343,435222 for Whirlwind, Thunder Clap, Thunder Blast"] = "Comma-separated spell IDs that grant max stacks. Example: 190411,6343,435222 for Whirlwind, Thunder Clap, Thunder Blast"
L["Spender Spell IDs"] = "Spender Spell IDs"
L["Comma-separated spell IDs that consume 1 stack. Example: 23881,85288,280735 for Bloodthirst, Raging Blow, Execute"] = "Comma-separated spell IDs that consume 1 stack. Example: 23881,85288,280735 for Bloodthirst, Raging Blow, Execute"
L["Stack Duration"] = "Stack Duration"
L["How long stacks last before expiring (seconds)"] = "How long stacks last before expiring (seconds)"
L["Reset On Combat End"] = "Reset On Combat End"
L["Reset stacks to zero when leaving combat"] = "Reset stacks to zero when leaving combat"
L["Presets"] = "Presets"
L["Fury Warrior - Whirlwind"] = "Fury Warrior - Whirlwind"
L["Auto-fill settings for tracking Fury Warrior's Whirlwind buff stacks"] = "Auto-fill settings for tracking Fury Warrior's Whirlwind buff stacks"
L["Fury Warrior Whirlwind preset applied!"] = "Fury Warrior Whirlwind preset applied!"
L["Havoc DH - Momentum"] = "Havoc DH - Momentum"
L["Auto-fill settings for tracking Havoc Demon Hunter's Momentum buff duration"] = "Auto-fill settings for tracking Havoc Demon Hunter's Momentum buff duration"
L["Havoc DH Momentum preset applied!"] = "Havoc DH Momentum preset applied!"
L["BM Hunter - Frenzy"] = "BM Hunter - Frenzy"
L["Auto-fill settings for tracking Beast Mastery Hunter's Frenzy buff stacks"] = "Auto-fill settings for tracking Beast Mastery Hunter's Frenzy buff stacks"
L["BM Hunter Frenzy preset applied!"] = "BM Hunter Frenzy preset applied!"
L["Display Mode"] = "Display Mode"
L["Choose what the bar displays: stack count or remaining duration"] = "Choose what the bar displays: stack count or remaining duration"
L["Generator Behavior"] = "Generator Behavior"
L["How generator spells affect stacks: 'Set Max' instantly fills to max stacks (like Whirlwind), 'Add One' adds 1 stack per cast (like Frenzy)"] = "How generator spells affect stacks: 'Set Max' instantly fills to max stacks (like Whirlwind), 'Add One' adds 1 stack per cast (like Frenzy)"
L["Set Max Stacks"] = "Set Max Stacks"
L["Add One Stack"] = "Add One Stack"
L["Comma-separated spell IDs that grant stacks. Example: 190411,6343,435222 for Whirlwind, Thunder Clap, Thunder Blast"] = "Comma-separated spell IDs that grant stacks. Example: 190411,6343,435222 for Whirlwind, Thunder Clap, Thunder Blast"
-- Spell Picker
L["Spells that generate stacks. Click an icon below to add, or manually enter Spell ID."] = "Spells that generate stacks. Click an icon below to add, or manually enter Spell ID."
L["Spells that consume stacks. Click an icon below to add, or manually enter Spell ID."] = "Spells that consume stacks. Click an icon below to add, or manually enter Spell ID."
L["Available Spells:"] = "Available Spells:"
L["No available spells for current spec"] = "No available spells for current spec"
L["Maximum 10 trigger spells allowed"] = "Maximum 10 trigger spells allowed"
L["Maximum 10 consumer spells allowed"] = "Maximum 10 consumer spells allowed"
-- Buff API Presets
L["Buff API Presets"] = "Buff API Presets"
L["These presets use Blizzard's buff API to track proc-based buffs."] = "These presets use Blizzard's buff API to track proc-based buffs."
L["Enh Shaman - Maelstrom Weapon"] = "Enh Shaman - Maelstrom Weapon"
L["Track Maelstrom Weapon stacks (up to 10)"] = "Track Maelstrom Weapon stacks (up to 10)"
L["Enhancement Shaman Maelstrom Weapon preset applied!"] = "Enhancement Shaman Maelstrom Weapon preset applied!"
L["Arcane Mage - Clearcasting"] = "Arcane Mage - Clearcasting"
L["Track Clearcasting stacks (up to 3)"] = "Track Clearcasting stacks (up to 3)"
L["Arcane Mage Clearcasting preset applied!"] = "Arcane Mage Clearcasting preset applied!"
L["Demo Lock - Demonic Core"] = "Demo Lock - Demonic Core"
L["Track Demonic Core stacks (up to 4)"] = "Track Demonic Core stacks (up to 4)"
L["Demonology Warlock Demonic Core preset applied!"] = "Demonology Warlock Demonic Core preset applied!"
L["WW Monk - Hit Combo"] = "WW Monk - Hit Combo"
L["Track Hit Combo stacks (up to 6)"] = "Track Hit Combo stacks (up to 6)"
L["Windwalker Monk Hit Combo preset applied!"] = "Windwalker Monk Hit Combo preset applied!"
L["Fire Mage - Hot Streak"] = "Fire Mage - Hot Streak"
L["Track Hot Streak duration"] = "Track Hot Streak duration"
L["Fire Mage Hot Streak preset applied!"] = "Fire Mage Hot Streak preset applied!"
L["Shadow Priest - Shadowy Insight"] = "Shadow Priest - Shadowy Insight"
L["Track Shadowy Insight proc"] = "Track Shadowy Insight proc"
L["Shadow Priest Shadowy Insight preset applied!"] = "Shadow Priest Shadowy Insight preset applied!"
-- Aura Catalog
L["Available Auras"] = "Available Auras"
L["click to select"] = "click to select"
L["No available auras for current spec"] = "No available auras for current spec"
-- CDM Integration
L["Scan CDM"] = "Scan CDM"
L["Rescan Cooldown Manager frames to update the catalog"] = "Rescan Cooldown Manager frames to update the catalog"
-- Spell Cooldown Mode
-- Spell Bar v2.0 Options
L["Ready"] = "Ready"
-- Manual Tracking Mode
L["Manual"] = "Manual"
L["CDM mode uses Cooldown Manager integration for 100% accurate tracking. Manual mode tracks spell casts."] = "CDM mode uses Cooldown Manager integration for 100% accurate tracking. Manual mode tracks spell casts."
L["No CDM entries found. Make sure Cooldown Manager is enabled."] = "No CDM entries found. Make sure Cooldown Manager is enabled."
L["Spells that generate stacks"] = "Spells that generate stacks"
L["Spells that consume stacks"] = "Spells that consume stacks"
-- Tracked Buffs UI (Foldable list)
L["is already being tracked"] = "is already being tracked"
L["Load"] = "Load"
-- Group & Context Menu (GUI.lua)
L["New Group"] = "New Group"
L["Collapse"] = "Collapse"
L["Expand"] = "Expand"
L["Alerts"] = "Alerts"
L["Click on a frame to select it (ESC to cancel)"] = "Click on a frame to select it (ESC to cancel)"
-- Group Load Conditions
-- Tracker Context Menu
L["Duration (sec)"] = "Duration (sec)"
-- Per-bar position settings (Multi-bar system)
L["Bar Style"] = "Bar Style"
L["Bar Style Desc"] = "Choose the visual style of the bar"
L["Circular"] = "Circular"
L["Square"] = "Square"
L["Donut"] = "Donut"
L["Donut Thickness"] = "Donut Thickness"
L["Donut Thickness Desc"] = "Adjust the ring thickness of the donut style"
L["Hide Bar When Mana"] = "Hide Bar When Mana"
L["Border"] = "Border"
L["Use different width/height when there is no secondary resource bar"] = "Use different width/height when there is no secondary resource bar"

-- ============================================================
-- CONFIG - ACTION BARS
-- ============================================================
L["Action Bars"] = "Action Bars"
L["Action Bar Settings"] = "Action Bar Settings"
L["Enable Action Bar Styling"] = "Enable Action Bar Styling"
L["Apply custom DDingUI styling to action bars"] = "Apply custom DDingUI styling to action bars"
L["Border Thickness"] = "Border Thickness"
L["Thickness of the action button border (expands outward, WHITE8x8 texture)"] = "Thickness of the action button border (expands outward, WHITE8x8 texture)"
L["Backdrop Color"] = "Backdrop Color"
L["Color of the action button backdrop (using Blizzard's WHITE8x8 texture)"] = "Color of the action button backdrop (using Blizzard's WHITE8x8 texture)"
L["Font Settings"] = "Font Settings"
L["Font used for action bar text elements. Leave as 'Use Global Font' to use the font from General settings."] = "Font used for action bar text elements. Leave as 'Use Global Font' to use the font from General settings."
L["Use Global Font"] = "Use Global Font"
L["Mouseover Settings"] = "Mouseover Settings"
L["Enable Mouseover"] = "Enable Mouseover"
L["Action bars will fade out when not moused over. Use individual bar toggles below to select which bars use mouseover."] = "Action bars will fade out when not moused over. Use individual bar toggles below to select which bars use mouseover."
L["Hidden Alpha"] = "Hidden Alpha"
L["Alpha value for action bars when mouseover is enabled and not moused over"] = "Alpha value for action bars when mouseover is enabled and not moused over"
L["Individual Bar Mouseover"] = "Individual Bar Mouseover"
L["Bar 1 (Main Action Bar)"] = "Bar 1 (Main Action Bar)"
L["Enable mouseover for Bar 1"] = "Enable mouseover for Bar 1"

-- ============================================================
-- CONFIG - CAST BARS
-- ============================================================
L["Cast Bars"] = "Cast Bars"
L["Player Cast Bar"] = "Player Cast Bar"
L["Target Cast Bar"] = "Target Cast Bar"
L["Focus Cast Bar"] = "Focus Cast Bar"
L["Boss Cast Bar"] = "Boss Cast Bar"

-- ============================================================
-- CONFIG - VIEWER OPTIONS
-- ============================================================
L["Viewers"] = "Viewers"
L["Essential Cooldowns"] = "Essential Cooldowns"
L["Utility Cooldowns"] = "Utility Cooldowns"
L["Buff Icons"] = "Buff Icons"
L["Buff Bar"] = "Tracked Bars"
L["Disable Dynamic Layout"] = "Disable Dynamic Layout"
L["Disable automatic bar positioning adjustments"] = "Disable automatic bar positioning adjustments"

-- ============================================================
-- CONFIG - UNIT FRAMES
-- ============================================================
L["Unit Frames"] = "Unit Frames"
L["Frame"] = "Frame"
L["Frame width"] = "Frame width"
L["Frame height"] = "Frame height"
L["Positioning"] = "Positioning"
L["X Position"] = "X Position"
L["Horizontal position of boss frames"] = "Horizontal position of boss frames"
L["Y Position"] = "Y Position"
L["Vertical position of boss frames"] = "Vertical position of boss frames"
L["Direction boss frames grow when multiple are shown"] = "Direction boss frames grow when multiple are shown"
L["Vertical spacing between boss frames"] = "Vertical spacing between boss frames"
L["Boss Frame Positioning"] = "Boss Frame Positioning"
L["Show/hide this unit frame"] = "Show/hide this unit frame"
L["Show boss frames with fake data for testing layout and appearance"] = "Show boss frames with fake data for testing layout and appearance"
L["Color health bar by class color"] = "Color health bar by class color"
L["Health bar foreground color"] = "Health bar foreground color"
L["Color health bar by reaction (hostile/neutral/friendly)"] = "Color health bar by reaction (hostile/neutral/friendly)"
L["Health bar background color"] = "Health bar background color"
L["Automatically anchor this frame to EssentialCooldownViewer. Only available for Player and Target frames."] = "Automatically anchor this frame to EssentialCooldownViewer. Only available for Player and Target frames."
L["Frame name to anchor to (e.g., EssentialCooldownViewer, DDingUI_Player, DDingUI_Target, UIParent)"] = "Frame name to anchor to (e.g., EssentialCooldownViewer, DDingUI_Player, DDingUI_Target, UIParent)"
L["Anchor point on the frame"] = "Anchor point on the frame"
L["Anchor point on parent"] = "Anchor point on parent"
L["Horizontal offset from anchor"] = "Horizontal offset from anchor"
L["Vertical offset from anchor"] = "Vertical offset from anchor"
L["Show the power bar (mana/energy/rage)"] = "Show the power bar (mana/energy/rage)"
L["Height of the power bar"] = "Height of the power bar"
L["Use default colors for power type (mana=blue, energy=yellow, etc.)"] = "Use default colors for power type (mana=blue, energy=yellow, etc.)"
L["Power bar foreground color"] = "Power bar foreground color"
L["Use power type color for background"] = "Use power type color for background"
L["Power bar background color"] = "Power bar background color"
L["Show unit name"] = "Show unit name"
L["Color name by class (player) or reaction (NPC)"] = "Color name by class (player) or reaction (NPC)"
L["Custom name text color"] = "Custom name text color"
L["Clamp displayed name length (0 = no limit)"] = "Clamp displayed name length (0 = no limit)"
L["Append target of target next to the target name without hiding the Target Target frame"] = "Append target of target next to the target name without hiding the Target Target frame"
L["Separator shown between target and its target when inline is enabled"] = "Separator shown between target and its target when inline is enabled"
L["Show health text"] = "Show health text"
L["Choose how health text is displayed"] = "Choose how health text is displayed"
L["Text to use as separator between health numbers (e.g., ' - ', ' / ', ' | '). Only used when Display Style shows both current and percent."] = "Text to use as separator between health numbers (e.g., ' - ', ' / ', ' | '). Only used when Display Style shows both current and percent."
L["Health text color"] = "Health text color"
L["Show power/resource text (mana, energy, etc.)"] = "Show power/resource text (mana, energy, etc.)"
L["Choose how power text is displayed"] = "Choose how power text is displayed"
L["Power text color"] = "Power text color"
L["Display harmful debuffs applied by you"] = "Display harmful debuffs applied by you"
L["Show fake debuff icons to preview layout"] = "Show fake debuff icons to preview layout"
L["Point on the frame where debuffs should anchor"] = "Point on the frame where debuffs should anchor"
L["Direction debuff icons grow within each row"] = "Direction debuff icons grow within each row"
L["Direction rows grow relative to each other"] = "Direction rows grow relative to each other"
L["Size of individual debuff icons"] = "Size of individual debuff icons"
L["Number of debuff icons to display per row"] = "Number of debuff icons to display per row"
L["Spacing between debuff icons"] = "Spacing between debuff icons"

-- ============================================================
-- CONFIG - PARTY/RAID FRAMES
-- ============================================================
L["Party Frames"] = "Party Frames"
L["Raid Frames"] = "Raid Frames"

-- ============================================================
-- CONFIG - CLICK CASTING
-- ============================================================
L["Click Casting"] = "Click Casting"
L["Click-Casting Addon Conflict"] = "Click-Casting Addon Conflict"
L["detected.\n\nWhich click-casting addon would you like to use?"] = "detected.\n\nWhich click-casting addon would you like to use?"
L["Selecting an option will disable the other addon(s)\nand reload your UI."] = "Selecting an option will disable the other addon(s)\nand reload your UI."
L["Use DDingUI"] = "Use DDingUI"
L["Are you sure?"] = "Are you sure?"
L["Having multiple click-casting addons enabled\nmay cause conflicts and unexpected behavior.\n\n|cffff6600Use at your own risk!|r"] = "Having multiple click-casting addons enabled\nmay cause conflicts and unexpected behavior.\n\n|cffff6600Use at your own risk!|r"
L["This warning will not appear again after confirming."] = "This warning will not appear again after confirming."
L["Go Back"] = "Go Back"
L["Confirm"] = "Confirm"
L["Left Click"] = "Left Click"
L["Right Click"] = "Right Click"
L["Middle Click"] = "Middle Click"
L["Scroll Up"] = "Scroll Up"
L["Scroll Down"] = "Scroll Down"
L["Target Unit"] = "Target Unit"
L["Unit Menu"] = "Unit Menu"
L["Set Focus"] = "Set Focus"
L["Assist"] = "Assist"
L["Mouseover"] = "Mouseover"
L["Self"] = "Self"
L["then"] = "then"
L["Unknown"] = "Unknown"
L["No Spell"] = "No Spell"
L["Macro"] = "Macro"
L["Item"] = "Item"
L["Slot"] = "Slot"

-- ============================================================
-- MESSAGES & ERRORS
-- ============================================================
L["DDingUI: Import failed: No data found. Please paste your import string in the Import Profile String field."] = "DDingUI: Import failed: No data found. Please paste your import string in the Import Profile String field."
L["DDingUI: Please enter a profile name for the imported profile."] = "DDingUI: Please enter a profile name for the imported profile."
L["DDingUI: Profile imported as '%s'. Please reload your UI."] = "DDingUI: Profile imported as '%s'. Please reload your UI."
L["DDingUI: Profile imported. Please reload your UI."] = "DDingUI: Profile imported. Please reload your UI."
L["DDingUI: Import failed: %s"] = "DDingUI: Import failed: %s"
L["DDingUI: Invalid Import String."] = "DDingUI: Invalid Import String."
L["No profile loaded."] = "No profile loaded."
L["Export requires AceSerializer-3.0 and LibDeflate."] = "Export requires AceSerializer-3.0 and LibDeflate."
L["Failed to serialize profile."] = "Failed to serialize profile."
L["Failed to compress profile."] = "Failed to compress profile."
L["Failed to encode profile."] = "Failed to encode profile."
L["Import requires AceSerializer-3.0 and LibDeflate."] = "Import requires AceSerializer-3.0 and LibDeflate."
L["No data provided."] = "No data provided."
L["Could not decode string (maybe corrupted)."] = "Could not decode string (maybe corrupted)."
L["Could not decompress data."] = "Could not decompress data."
L["Could not deserialize profile."] = "Could not deserialize profile."
L["Profile system not available."] = "Profile system not available."
-- [REFACTOR] AceGUI → StyleLib: AceConfigDialog 폴백 제거됨
L["[DDingUI] Error: Custom GUI not loaded."] = "[DDingUI] Error: Custom GUI not loaded."
L["[DDingUI] Party/Raid frames GUI not loaded."] = "[DDingUI] Party/Raid frames GUI not loaded."

-- ============================================================
-- ALERT SYSTEM (BuffTracker)
-- ============================================================
L["Alert System"] = "Alert System"
L["Enable Alerts"] = "Enable Alerts"
L["Active"] = "Active"
L["Inactive"] = "Inactive"

-- ============================================================
-- ANCHOR POSITIONS
-- ============================================================
L["Center"] = "Center"
L["Select Frame"] = "Select Frame"
L["Anchor Frame"] = "Anchor Frame"
L["Select Anchor"] = "Select Anchor"
L["No selection"] = "No selection"
L["Cannot anchor to self"] = "Cannot anchor to self"

-- ============================================================
-- CONFIG - BUFF/DEBUFF FRAMES
-- ============================================================

-- ============================================================
-- CONFIG - UI SCALE & GENERAL
-- ============================================================
L["Apply Font to Blizzard UI"] = "Apply Font to Blizzard UI"
L["Apply DDingUI font to Blizzard UI elements (buff durations, damage text, etc.). Disable if using ElvUI or other UI addons."] = "Apply DDingUI font to Blizzard UI elements (buff durations, damage text, etc.). Disable if using ElvUI or other UI addons."
L["[DDingUI] Apply Font to Blizzard UI:"] = "[DDingUI] Apply Font to Blizzard UI:"
L["Reload UI for full effect."] = "Reload UI for full effect."

-- ============================================================
-- CONFIG - ADDITIONAL SETTINGS
-- ============================================================
L["Player"] = "Player"
L["Swing Timer"] = "Swing Timer"
L["Swing Timer Bar"] = "Swing Timer Bar"
L["Swing Timer Bar Settings"] = "Swing Timer Bar Settings"
L["Enable Swing Timer Bar"] = "Enable Swing Timer Bar"
L["Show your auto-attack swing timer"] = "Show your auto-attack swing timer"
L["Main Hand Color"] = "Main Hand Color"
L["Off-Hand Color"] = "Off-Hand Color"
L["Show Off-Hand"] = "Show Off-Hand"
L["Show off-hand swing timer when dual-wielding"] = "Show off-hand swing timer when dual-wielding"
L["Off-Hand Spacing"] = "Off-Hand Spacing"
L["Space between main-hand and off-hand bars"] = "Space between main-hand and off-hand bars"
L["Off-Hand Height"] = "Off-Hand Height"
L["Hide Out of Combat"] = "Hide Out of Combat"
L["Hide the swing timer when not in combat"] = "Hide the swing timer when not in combat"
L["Idle Timeout"] = "Idle Timeout"
L["Seconds after last swing before hiding the bar"] = "Seconds after last swing before hiding the bar"
L["Number of decimal places for the timer text"] = "Number of decimal places for the timer text"
L["Text Font"] = "Text Font"
L["Behavior"] = "Behavior"
L["Custom Icons"] = "Custom Icons"

-- ============================================================
-- CONFIG - BUFF BAR OPTIONS
-- ============================================================
L["Bar Spacing"] = "Bar Spacing"
L["Space between bars"] = "Space between bars"
L["Icon Position"] = "Icon Position"
L["Where the icon sits relative to the bar"] = "Where the icon sits relative to the bar"
L["Icon Left"] = "Icon Left"
L["Icon Right"] = "Icon Right"
L["Icon Gap"] = "Icon Gap"
L["Space between the icon and the bar"] = "Space between the icon and the bar"
L["Glow"] = "Glow"
L["Shine"] = "Shine"

-- ============================================================
-- CONFIG - GUI BUTTONS
-- ============================================================
L["Disable Anchors"] = "Disable Anchors"
L["Enable Anchors"] = "Enable Anchors"
L["Hide draggable anchors for unit, party, and raid frames"] = "Hide draggable anchors for unit, party, raid frames, and dynamic icons"
L["Show draggable anchors for unit, party, raid frames, and action bars (works independently of Edit Mode)"] = "Show draggable anchors for unit, party, raid frames, and dynamic icons (works independently of Edit Mode)"

-- ============================================================
-- CONFIG - BUFF ICON VIEWER SPECIFIC
-- ============================================================
L["Buff Duration Text Settings"] = "Buff Duration Text Settings"
-- [12.0.1] New text options
L["Active Glow"] = "Active Glow"
L["Show glow effect when buff is active (alternative to swipe)"] = "Show glow effect when buff is active (alternative to swipe)"
L["Active Glow Type"] = "Active Glow Type"
L["Type of glow effect to show when buff is active"] = "Type of glow effect to show when buff is active"
L["Active Glow Color"] = "Active Glow Color"
L["Color of the active buff glow effect"] = "Color of the active buff glow effect"
L["Reset all per-segment colors to default"] = "Reset all per-segment colors to default"
L["Aura Glow Type"] = "Aura Glow Type"
L["Aura Glow Color"] = "Aura Glow Color"

-- ============================================================
-- CONFIG - SPEC PROFILES
-- ============================================================
L["Spec Profiles"] = "Spec Profiles"
L["Use Spec Profiles"] = "Use Spec Profiles"
L["Save/load settings per specialization automatically."] = "Save/load settings per specialization automatically."
L["Settings are automatically saved when changing specs or every 30 seconds."] = "Settings are automatically saved when changing values or specs."
L["Enable Spec Profiles"] = "Enable Spec Profiles"
L["Automatically save/load settings when changing specialization."] = "Automatically save/load settings when changing specialization."
L["Current Spec:"] = "Current Spec:"
L["Save Now"] = "Save Now"
L["Manually save current settings immediately."] = "Manually save current settings immediately."
L["Revert to Saved"] = "Revert to Saved"
L["Discard current changes and load saved settings."] = "Discard current changes and load saved settings."
L["Discard current changes and revert to saved settings?"] = "Discard current changes and revert to saved settings?"
L["Delete Spec Profile"] = "Delete Spec Profile"
L["Are you sure you want to delete this spec profile?"] = "Are you sure you want to delete this spec profile?"
L["Global Settings"] = "Global Settings"
L["Save as Global"] = "Save as Global"
L["Save current settings as the global (shared) preset."] = "Save current settings as the global (shared) preset."
L["Load from Global"] = "Load from Global"
L["Load the global (shared) settings. This will overwrite current settings."] = "Load the global (shared) settings. This will overwrite current settings."
L["Load global settings? This will overwrite your current settings."] = "Load global settings? This will overwrite your current settings."
L["Copy Between Specs"] = "Copy Between Specs"
L["Copy From Spec"] = "Copy From Spec"
L["Copy settings from another spec to current. This will overwrite current settings."] = "Copy settings from another spec to current. This will overwrite current settings."
L["Copy settings from this spec? This will overwrite your current settings."] = "Copy settings from this spec? This will overwrite your current settings."
L["Saved Specs:"] = "Saved Specs:"
L["spec profiles enabled."] = "spec profiles enabled."
L["settings saved for"] = "settings saved for"
L["settings loaded for"] = "settings loaded for"
L["saved as global settings."] = "saved as global settings."
L["global settings loaded."] = "global settings loaded."
L["settings copied from"] = "settings copied from"
L["to"] = "to"
L["spec profile deleted for"] = "spec profile deleted for"
L["Automatically switch the entire profile when you change specialization."] = "Automatically switch the entire profile when you change specialization."
L["Automatically switch the entire profile when you change specialization.\nEach spec can use a different profile with completely separate settings."] = "Automatically switch the entire profile when you change specialization.\nEach spec can use a different profile with completely separate settings."
L["Profile per Specialization"] = "Profile per Specialization"
L["Primary Power Bar"] = "Primary Power Bar"
L["Secondary Power Bar"] = "Secondary Power Bar"
L["Settings are automatically saved when changing values or specs."] = "Settings are automatically saved when changing values or specs."

-- ============================================================
-- CONFIG - SOUND MODE
-- ============================================================
L["Custom Sound File"] = "Custom Sound File"
L["CustomSoundDesc"] = "Enter a .ogg, .mp3, or .wav file path relative to the WoW folder. Example: Interface\\AddOns\\DDingUI\\sounds\\alert.ogg\nIf set, this overrides the Sound selection above."
L["Path to a custom sound file (e.g. Interface\\AddOns\\MyAddon\\alert.ogg). Supports .ogg, .mp3, .wav. Overrides the Sound selection above."] = "Path to a custom sound file (e.g. Interface\\AddOns\\MyAddon\\alert.ogg). Supports .ogg, .mp3, .wav. Overrides the Sound selection above."
L["Interval Seconds"] = "Interval Seconds"
L["Minimum Stacks"] = "Minimum Stacks"
L["Sound only plays when stacks >= this value"] = "Sound only plays when stacks >= this value"

-- ============================================================
-- CONFIG - THRESHOLD COLORS
-- ============================================================
L["Change bar color based on resource value"] = "Change bar color based on resource value"
L["Threshold Mode"] = "Threshold Mode"
L["How to interpret threshold values"] = "How to interpret threshold values"
L["Percent"] = "Percent"
L["Percentage"] = "Percentage"
L["Absolute Value"] = "Absolute Value"
L["Threshold 1 (Low Priority)"] = "Threshold 1 (Low Priority)"
L["Threshold 2 (Medium Priority)"] = "Threshold 2 (Medium Priority)"
L["Threshold 3 (High Priority)"] = "Threshold 3 (High Priority)"
L["When"] = "When"

-- ============================================================
-- CONFIG - TEXT MODE
-- ============================================================

-- ============================================================
-- CONFIG - ADVANCED ANIMATIONS
-- ============================================================
L["Pixel Glow"] = "Pixel Glow"
L["Glow Color"] = "Glow Color"

-- ============================================================
-- CONFIG - ASSIST HIGHLIGHT (보조 강조 효과)
-- ============================================================

-- ============================================================
-- CONFIG - COOLDOWN TEXT FORMAT (v1.1.2)
-- ============================================================

-- ============================================================
-- CONFIG - FRAME PICKER (v1.1.2)
-- ============================================================

-- ============================================================
-- CONFIG - TEXTURE OPTIONS (v1.1.2)
-- ============================================================

-- ============================================================
-- CONFIG - CAST BAR INTERRUPTED FADE (v1.1.2)
-- ============================================================

-- ============================================================
-- CONFIG - FRAME PICKER BUTTON (v1.1.2)
-- ============================================================
L["Click on a frame to select it (ESC to cancel)"] = "Click on a frame to select it (ESC to cancel)"
L["Frame selected:"] = "Frame selected:"

-- ============================================================
-- CONFIG - SECONDARY POWER BAR PERCENT OPTIONS (v1.1.2)
-- ============================================================

-- ============================================================
-- MOVER SYSTEM (v1.1.2)
-- ============================================================
L["Move Frames"] = "Move Frames"
L["Toggle frame mover mode to reposition DDingUI elements"] = "Toggle frame mover mode to reposition DDingUI elements"
L["Primary Resource"] = "Primary Resource"
L["Secondary Resource"] = "Secondary Resource"
L["Player Cast Bar"] = "Player Cast Bar"
L["Target Cast Bar"] = "Target Cast Bar"
L["Focus Cast Bar"] = "Focus Cast Bar"
L["Boss Cast Bar"] = "Boss Cast Bar"
L["Buff Tracker Bar"] = "Custom Aura Bar"
L["Position Adjustment"] = "Position Adjustment"
L["No frame selected"] = "No frame selected"
L["Left-click"] = "Left-click: Drag to move"
L["Shift+Right-click"] = "Shift+Right-click: Reset position"
L["Reset"] = "Reset"
L["Mover mode enabled"] = "Mover mode enabled. Drag frames to reposition."
L["Mover mode disabled"] = "Mover mode disabled. Positions saved."
L["Cannot toggle movers in combat"] = "Cannot toggle movers in combat"
L["Anchor To"] = "Anchor To"
L["Select Anchor"] = "Select Anchor"
L["Grid"] = "Grid"
L["Snap"] = "Snap"
L["Undo"] = "Undo"
L["Redo"] = "Redo"
L["Left-click: Change Anchor Point"] = "Left-click: Change Anchor Point"
L["Right-click: Change Self Point"] = "Right-click: Change Self Point"
L["Done"] = "Done"
L["Buff Tracker Icon"] = "Custom Aura Icon"
L["Buff Tracker Text"] = "Custom Aura Text"
L["Enable Group"] = "Enable Group"
L["Toggle this group on/off"] = "Toggle this group on/off"
L["Left-click: Select and adjust"] = "Left-click: Select and adjust"
L["Drag: Move frame"] = "Drag: Move frame"
L["Right-click: Open settings"] = "Right-click: Open settings"
L["Shift+Right-click: Reset position"] = "Shift+Right-click: Reset position"
L["Select a frame first"] = "Select a frame first"
L["Cannot anchor to self"] = "Cannot anchor to self"
L["Show Grid"] = "Show Grid"
L["Enable Snap"] = "Enable Snap"
L["Frames"] = "Frames"
L["Buff Tracker frames refreshed"] = "Custom Aura frames refreshed"
L["Enter mover mode first (/ddmove)"] = "Enter mover mode first (/ddmove)"

-- ============================================================
-- ICON CUSTOMIZATION (v1.1.5)
-- ============================================================
L["Scan Icons"] = "Scan Icons"
L["Click to select • Blue border = Customized"] = "Click to select • Blue border = Customized"
L["Editing: %s"] = "Editing: %s"
L["Deselect"] = "Deselect"
L["Reset Icon"] = "Reset Icon"
L["Reset Glow"] = "Reset Glow"
L["Ready State Glow"] = "State Glow"
L["Glow Type"] = "Glow Type"
L["Action Button Glow"] = "Action Button Glow"
L["Autocast Shine"] = "Autocast Shine"
L["Proc Effect"] = "Proc Effect"
L["Glow Frequency"] = "Glow Frequency"
L["Line Amount"] = "Line Amount"
L["Line Thickness"] = "Line Thickness"
L["Glow Trigger"] = "Glow Trigger"
L["When Ready (Cooldown)"] = "When Ready (Cooldown)"
L["When Active (Buff)"] = "When Active (Buff)"
L["More Settings..."] = "More Settings..."
L["Unassign"] = "Unassign"
L["State Glow"] = "State Glow"
L["Icon State"] = "Icon State"
L["Active State"] = "Active State"
L["Active Effect Display"] = "Active Effect Display"
L["Active Swipe"] = "Active Swipe"
L["Swipe and Glow"] = "Swipe and Glow"
L["Swipe Only"] = "Swipe Only"
L["Glow Only"] = "Glow Only"
L["Glow and Duration"] = "Glow and Duration"
L["Hide Active Effect"] = "Hide Active Effect"
L["Cooldown Swipe"] = "Cooldown Swipe"
L["Cooldown Edge"] = "Cooldown Edge"
L["Cooldown Finish Flash"] = "Cooldown Finish Flash"
L["Active Duration Text"] = "Active Duration Text"
L["Threshold Text"] = "Threshold Text"
L["Threshold Seconds"] = "Threshold Seconds"
L["Threshold Decimals"] = "Threshold Decimals"
L["Threshold Color"] = "Threshold Color"
L["Threshold Text Color"] = "Threshold Text Color"
L["Always Show Buff"] = "Always Show Buff"
L["Desaturate Inactive"] = "Desaturate Inactive"
L["Inactive Opacity"] = "Inactive Opacity"
L["Desaturate"] = "Desaturate"
L["Full Color"] = "Full Color"
L["Proc Glow"] = "Proc Glow"
L["Active State Glow"] = "Active State Glow"
L["Max Charges Glow"] = "Max Charges Glow"
L["Cooldown Ready Glow"] = "Cooldown Ready Glow"
L["Glow Color Mode"] = "Glow Color Mode"
L["Blizzard Glow"] = "Blizzard Default Glow"
L["Keep Blizzard Default Glow Color"] = "Blizzard Default Color"
L["Custom Glow Color"] = "Custom Glow Color"
L["Custom"] = "Custom"
L["Swipe Color"] = "Swipe Color"
L["Class Color"] = "Class Color"
L["Hide Active State"] = "Hide Active State"
L["Active Swipe Color"] = "Active Swipe Color"
L["Active Border"] = "Active Border"
L["Active Border Color"] = "Active Border Color"
L["Non Active State"] = "Non Active State"
L["Desaturate When Not Active"] = "Desaturate When Not Active"
L["Cooldown State Effect"] = "Cooldown State Effect"
L["Lower Alpha on Cooldown"] = "Lower Alpha on Cooldown"
L["Hidden on Cooldown"] = "Hidden on Cooldown"
L["Hidden When Ready"] = "Hidden When Ready"
L["Cooldown State Opacity"] = "Cooldown State Opacity"
L["Charge Count"] = "Charge Count"
L["Hide Recharge Swipe"] = "Hide Recharge Swipe"
L["Hide Recharge Edge"] = "Hide Recharge Edge"
L["Hide Duration With Charges"] = "Hide Duration With Charges"
L["Charge Display"] = "Charge Display"
L["Audio on Buff Gain"] = "Audio on Buff Gain"
L["Audio on Buff Loss"] = "Audio on Buff Loss"
L["Audio Effect on Cooldown Ready"] = "Audio Effect on Cooldown Ready"
L["On"] = "On"
L["None"] = "None"
L["Default"] = "Default"
L["Show"] = "Show"
L["Hide"] = "Hide"
L["Normal"] = "Normal"
L["Reverse"] = "Reverse"
L["Hidden"] = "Hidden"
L["Show Cooldown Swipe"] = "Show Cooldown Swipe"
L["Show Charges"] = "Show Charges"
L["Desaturate on Cooldown"] = "Desaturate on Cooldown"
L["Desaturate When Unusable"] = "Desaturate When Unusable"
L["Hide When Empty"] = "Hide When Empty"
L["Show Proc Duration"] = "Show Proc Duration"
L["Show Proc Stacks"] = "Show Proc Stacks"
L["Show Item Cooldown"] = "Show Item Cooldown"
L["Pixel Glow Settings"] = "Pixel Glow Settings"
L["Group Assignment"] = "Group Assignment"
L["Off"] = "Off"
L["Ready"] = "Ready"
L["Active"] = "Active"
L["Drag to reorder | Right-click for options"] = "Drag to reorder | Right-click for options"
L["Drag to reorder | Left-click for glow | Right-click for options"] = "Drag to reorder | Left-click for glow | Right-click for options"
L["Drag to reorder | Right-click for options | Middle-click to unassign"] = "Drag to reorder | Right-click for options | Middle-click to unassign"
L["Drag to reorder | Right-click for options | Middle-click to remove"] = "Drag to reorder | Right-click for options | Middle-click to remove"

-- ============================================================
-- BUFF TRACKER - BAR ORIENTATION & RING STYLE (v1.1.6)
-- ============================================================

-- ============================================================
-- DYNAMIC ICONS UI (v1.1.6)
-- ============================================================
L["Ungrouped"] = "Ungrouped"
L["New Group"] = "New Group"
L["Delete \"%s\"?\nThis cannot be undone."] = "Delete \"%s\"?\nThis cannot be undone."
L["Are you sure you want to delete group \"%s\"?\n\nAll icons in this group will be deleted.\nThis cannot be undone."] = "Are you sure you want to delete group \"%s\"?\n\nAll icons in this group will be deleted.\nThis cannot be undone."
L["Item"] = "Item"
L["Spell"] = "Spell"
L["Slot"] = "Slot"

-- ============================================================
-- RING MODE OPTIONS (v1.1.6)
-- ============================================================
L["Ring Fill Mode"] = "Ring Fill Mode"
L["Show Text"] = "Show Text"

-- ============================================================
-- MISSING ALERTS (v1.1.6)
-- ============================================================
L["Missing Alerts"] = "Missing Alerts"
L["Pet Missing"] = "Pet Missing"
L["Show alert when pet is missing (Hunter/Warlock/Unholy DK)"] = "Show alert when pet is missing (Hunter/Warlock/Unholy DK)"
L["Alert text to display"] = "Alert text to display"
L["Class Buff Missing"] = "Class Buff Missing"
L["Show icon when your class buff is missing"] = "Show icon when your class buff is missing (group-wide check)"
L["Show icon when your class buff is missing (combat only)"] = "Show icon when group members are missing your class buff (combat only)"
L["Desaturate"] = "Desaturate"
L["Show icon in grayscale"] = "Show icon in grayscale"
L["Text Outline"] = "Text Outline"
L["Text Y Offset"] = "Text Y Offset"
L["Vertical position of count text relative to icon"] = "Vertical position of count text relative to icon"
L["Instance Only"] = "Instance Only"
L["Only show pet alert inside instances (dungeons/raids/arenas/battlegrounds)"] = "Only show pet alert inside instances (dungeons/raids/arenas/battlegrounds)"
L["Display Conditions"] = "Display Conditions"

-- ============================================================
-- BUFF TRACKER STACKING DIRECTION (v1.1.6)
-- ============================================================

-- ============================================================
-- FRAME STRATA SETTINGS
-- ============================================================

-- ============================================================
-- CONFIG - RESOURCE BAR OPTIONS (v1.2.0)
-- ============================================================
L["Center"] = "Center"
L["Use different width/height when there is no secondary resource bar"] = "Use different width/height when there is no secondary resource bar"
L["Hide the resource bar completely when current power is mana (prevents errors during druid shapeshifting)"] = "Hide the resource bar completely when current power is mana (prevents errors during druid shapeshifting)"
L["Hide the secondary bar entirely when the current power is mana"] = "Hide the secondary bar entirely when the current power is mana"

-- Advanced Color Options
L["Per-Segment Colors"] = "Per-Segment Colors"
L["Set individual colors for each rune/essence segment (1-6)"] = "Set individual colors for each rune/essence segment (1-6)"

-- Rune Timer Options

-- Resource Bar Colors

-- Primary Power Types

-- Secondary Power Types

-- ============================================================
-- Missing locale keys (auto-generated)
-- ============================================================

-- CastBarOptions

-- BuffTrackerOptions

-- ViewerOptions

-- ProfileOptions
L["Module Import"] = "Module Import"
L["Import selected module settings from another specialization or profile.\nSelected module settings will overwrite the current profile."] = "Import selected module settings from another specialization or profile.\nSelected module settings will overwrite the current profile."
L["Import Source"] = "Import Source"
L["Another Specialization"] = "Another Specialization"
L["Another Profile"] = "Another Profile"
L["Source Specialization"] = "Source Specialization"
L["Source Profile"] = "Source Profile"
L["Modules to Import"] = "Modules to Import"
L["Select All"] = "Select All"
L["Clear All"] = "Clear All"
L["Apply Import"] = "Apply Import"
L["Selected module settings will overwrite the current profile. Continue?"] = "Selected module settings will overwrite the current profile. Continue?"
L["SpecProfiles module not found."] = "SpecProfiles module not found."
L["Please select modules to import."] = "Please select modules to import."
L["Please select an import source."] = "Please select an import source."
L["Import complete: %s"] = "Import complete: %s"
L["Import failed: source data not found."] = "Import failed: source data not found."
L["Default CDM Groups"] = "Default CDM Groups"
L["Dynamic Groups"] = "Dynamic Groups"
L["Shortcut Icons"] = "Shortcut Icons"
L["Aura Tracker"] = "Aura Tracker"
L["Buff Viewer"] = "Buff Viewer"

-- ConfigHelpers

-- CustomIconOptions

-- GUI
L["Open Advanced Cooldown Manager Panel"] = "Open Advanced Cooldown Manager Panel"

-- Movers (key mismatch fix)
L["Shift+Right-click: Reset position"] = "Shift+Right-click: Reset position"

-- [GROUP SYSTEM] Group System Options
L["Auto Classify"] = "Auto Classify"
L["Automatically classify auras and cooldowns into groups"] = "Automatically classify auras and cooldowns into groups"
L["Primary direction for icon placement"] = "Primary direction for icon placement"
L["Direction for row wrapping"] = "Direction for row wrapping"
L["Spell Assignment"] = "Spell Assignment"
L["No manual assignments"] = "No manual assignments"
L["No manual assignments. Use grid or Spell ID to add."] = "No manual assignments. Use grid or Spell ID to add."
L["No manual assignments. Use Quick Assign or Spell ID below."] = "No manual assignments. Use Quick Assign or Spell ID below."
L["No manual assignments. Use Spell ID below."] = "No manual assignments. Use Spell ID below."
L["Click to unassign spell"] = "Click to unassign spell"
L["Click to unassign dynamic icon"] = "Click to unassign dynamic icon"
L["Drag to reorder | Click to remove"] = "Drag to reorder | Click to remove"
L["Drag to reorder | Right-click to remove"] = "Drag to reorder | Right-click to remove"
L["Drag to reorder | Right-click to unassign"] = "Drag to reorder | Right-click to unassign"
L["Right-click to remove"] = "Right-click to remove"
L["Right-click to unassign"] = "Right-click to unassign"
L["Clear All Assignments"] = "Clear All Assignments"
L["Remove all manual assignments for this group?"] = "Remove all manual assignments for this group?"
L["Enter Spell ID (number) or exact spell name. Buff spells auto-prefix buff_."] = "Enter Spell ID (number) or exact spell name. Buff spells auto-prefix buff_."
L["Spell ID or Name"] = "Spell ID or Name"
L["Quick Assign (Active Icons)"] = "Quick Assign (Active Icons)"
L["Add Spell ID"] = "Add Spell ID"
L["Enter a spell ID to manually assign to this group"] = "Enter a spell ID to manually assign to this group"
L["Add Spell Name"] = "Add Spell Name"
L["Enter a spell name to manually assign to this group. Use Ctrl+Click in edit mode for easier assignment."] = "Enter a spell name to manually assign to this group. Use Ctrl+Click in edit mode for easier assignment."
L["Auto (Default)"] = "Auto (Default)"
L["Open Icon Grid"] = "Open Icon Grid"
L["Visually assign CDM icons to this group"] = "Visually assign CDM icons to this group"
L["Click to assign, Shift+Click to remove"] = "Click: Assign, Shift+Click: Remove"
-- [DYNAMIC] Dynamic group options
L["Manage Icons"] = "Manage Icons"
L["Open Custom Icons settings to add/remove dynamic icons"] = "Open Custom Icons settings to add/remove dynamic icons"
L["Active Icons"] = "Active Icons"
L["No active dynamic icons"] = "No active dynamic icons"
L["This group displays icons from Custom Icons (consumables, healthstones, etc.). Use the button below to manage icons."] = "This group displays icons from Custom Icons (consumables, healthstones, etc.). Use the button below to manage icons."
L["Viewer Detail Settings"] = "Viewer Detail Settings"
L["Click: Assign to this group"] = "Click: Assign to this group"
L["Shift+Click: Remove assignment"] = "Shift+Click: Remove assignment"
L["Refresh"] = "Refresh"
L["Are you sure you want to delete this group?"] = "Are you sure you want to delete this group?"
L["Settings"] = "Settings"
L["Enter a spell name or numeric Spell ID to assign it to this group"] = "Enter a spell name or numeric Spell ID to assign it to this group"
L["Select category to filter available spells in Quick Assign"] = "Select category to filter available spells in Quick Assign"
L["Category"] = "Category"
L["Icon Movement Animation"] = "Icon Movement Animation"
-- [5TAB] GroupSystem 5-tab structure
L["Viewer"] = "Viewer"
L["No additional viewer settings available."] = "No additional viewer settings available."
L["Icon Glow"] = "Icon Glow"
L["Viewer Anchor"] = "Viewer Anchor"
L["Frame Anchor"] = "Frame Anchor"
L["Preview"] = "Preview"
L["Keybind Text"] = "Keybind Text"
-- [12.0.1] GroupSystem 종횡비 + 아이템/장신구 추가 옵션
L["Enter an Item ID to add as a dynamic icon (e.g., trinket, potion)"] = "Enter an Item ID to add as a dynamic icon (e.g., trinket, potion)"
L["Trinket Buff Slot 1"] = "Trinket Buff Slot 1"
L["Trinket Buff Slot 2"] = "Trinket Buff Slot 2"

-- Buff Tracker Refactor (Phase 2 Condition)
L["Add Condition"] = "Add Condition"
L["Remove Condition"] = "Remove Condition"
L["Add Check"] = "Add Check"
L["Time Left"] = "Time Left"
L["Color Override"] = "Color Override"
L["Play Sound"] = "Play Sound"
L["Show Glow"] = "Show Glow"
L["My Trackers"] = "My Trackers"
L["CDM Catalog"] = "CDM Catalog"
L["Conditions"] = "Conditions"

-- Buff Tracker Refactor (Phase 1 TreeGroup)
L["Tracker Groups"] = "Tracker Groups"
L["Add New Group"] = "Add New Group"
L["Sort Method"] = "Sort Method"
L["Sort Direction"] = "Sort Direction"
L["Group Anchor Point"] = "Group Anchor Point"
L["Overview"] = "Overview"
L["No buffs being tracked. Select a buff from the catalog."] = "No buffs being tracked. Select a buff from the catalog."
L["Tracker Group"] = "Tracker Group"

-- Buff Tracker WeakAuras-style Panel

-- Movers / NudgeFrame
L["Select Frame"] = "Select Frame"
L["Show Grid"] = "Show Grid"
L["Enable Snap"] = "Enable Snap"
L["Buff Tracker frames refreshed"] = "Custom Aura frames refreshed"
L["Enter mover mode first (/ddmove)"] = "Enter mover mode first (/ddmove)"

-- Conditional Actions (Group Multi-Trigger)
L["Stacks ≥"] = "Stacks ≥"
L["Stacks ≤"] = "Stacks ≤"
L["Stacks ="] = "Stacks ="
L["Duration ≥"] = "Duration ≥"
L["Duration ≤"] = "Duration ≤"
L["Cooldown Ready"] = "Cooldown Ready"
L["Cooldown Active"] = "Cooldown Active"
L["Bar Color Change"] = "Bar Color Change"
L["Bar Glow"] = "Bar Glow"
L["Icon Glow"] = "Icon Glow"
L["Icon Change"] = "Icon Texture Change"
L["Play Sound"] = "Play Sound"
L["Show Text"] = "Show Alert Text"
L["Primary Power Bar"] = "Primary Power Bar"
L["Secondary Power Bar"] = "Secondary Power Bar"
L["Cast Bar"] = "Cast Bar"
L["Enter mover mode first (/ddmove)"] = "Enter mover mode first (/ddmove)"

-- Spell Cooldown Bar - Dynamic Labels

-- Activation Condition

-- CDM visual effects
L["Add Active Effect Overlay"] = "Add Active Effect Overlay"
L["Active Effect Overlay (%s sec)"] = "Active Effect Overlay (%s sec)"
L["Change Active Effect Duration"] = "Change Duration"
L["Remove Active Effect Overlay"] = "Remove Active Effect Overlay"
L["Enter active effect duration (seconds):"] = "Enter active effect duration (seconds):"
L["Preview Sound"] = "Preview sound"
