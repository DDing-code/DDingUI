local L = LibStub("AceLocale-3.0"):NewLocale("DDingUI_UF", "enUS", true)
if not L then return end

------------------------------------------------------------------------
-- UNIT NAMES
------------------------------------------------------------------------
L["UNIT_PLAYER"]           = "Player"
L["UNIT_TARGET"]           = "Target"
L["UNIT_TARGETTARGET"]     = "Target of Target"
L["UNIT_FOCUS"]            = "Focus"
L["UNIT_FOCUSTARGET"]      = "Focus Target"
L["UNIT_PET"]              = "Pet"
L["UNIT_BOSS"]             = "Boss"
L["UNIT_ARENA"]            = "Arena"
L["UNIT_PARTY"]            = "Party"
L["UNIT_RAID"]             = "Raid"
L["UNIT_PARTY_COUNT"]      = "Party (5)"
L["UNIT_RAID_COUNT"]       = "Raid (20)"

------------------------------------------------------------------------
-- WIDGET NAMES
------------------------------------------------------------------------
L["WIDGET_NAME"]           = "Name"
L["WIDGET_HEALTH_TEXT"]    = "Health Text"
L["WIDGET_POWER_TEXT"]     = "Power Text"
L["WIDGET_LEVEL_TEXT"]     = "Level Text"
L["WIDGET_CUSTOM_TEXT"]    = "Custom Text"
L["WIDGET_BUFFS"]          = "Buffs"
L["WIDGET_DEBUFFS"]        = "Debuffs"
L["WIDGET_DISPELS"]        = "Dispels"
L["WIDGET_RAID_ICON"]      = "Raid Icon"
L["WIDGET_ROLE_ICON"]      = "Role Icon"
L["WIDGET_LEADER_ICON"]    = "Leader Icon"
L["WIDGET_COMBAT_ICON"]    = "Combat Icon"
L["WIDGET_READY_CHECK"]    = "Ready Check"
L["WIDGET_RESTING_ICON"]   = "Resting Icon"
L["WIDGET_RESURRECT_ICON"] = "Resurrect Icon"
L["WIDGET_SUMMON_ICON"]    = "Summon Icon"
L["WIDGET_SHIELD_BAR"]     = "Shield Bar"
L["WIDGET_CAST_BAR"]       = "Cast Bar"
L["WIDGET_CLASS_BAR"]      = "Class Resource"
L["WIDGET_ALT_POWER_BAR"]  = "Alt Power Bar"
L["WIDGET_POWER_BAR"]      = "Power Bar"
L["WIDGET_HEAL_PREDICTION"] = "Heal Prediction"
L["WIDGET_HEAL_ABSORB"]    = "Heal Absorb"
L["WIDGET_FADER"]          = "Fader"
L["WIDGET_HIGHLIGHT"]      = "Highlight"
L["WIDGET_THREAT"]         = "Threat"

------------------------------------------------------------------------
-- TEXTURE / FONT FALLBACK
------------------------------------------------------------------------
L["TEXTURE_FLAT_DEFAULT"]  = "Flat (Default)"
L["FONT_DEFAULT"]          = "Default Font"
L["FONT_BOLD"]             = "Bold Font"

------------------------------------------------------------------------
-- ORIENTATION LIST
------------------------------------------------------------------------
L["ORIENT_LEFT_RIGHT"]     = "Left\226\134\146Right"
L["ORIENT_RIGHT_LEFT"]     = "Right\226\134\146Left"
L["ORIENT_TOP_BOTTOM"]     = "Top\226\134\146Bottom"
L["ORIENT_BOTTOM_TOP"]     = "Bottom\226\134\146Top"

------------------------------------------------------------------------
-- HEALTH FORMAT LIST
------------------------------------------------------------------------
L["FMT_PERCENTAGE"]        = "Percentage"
L["FMT_CURRENT"]           = "Current"
L["FMT_CURRENT_MAX"]       = "Current/Max"
L["FMT_DEFICIT"]           = "Deficit"
L["FMT_CURRENT_PERCENT"]   = "Current (Percent)"
L["FMT_PERCENT_CURRENT"]   = "Percent | Current"
L["FMT_CURRENT_PERCENT2"]  = "Current | Percent"

------------------------------------------------------------------------
-- POWER FORMAT LIST (additional)
------------------------------------------------------------------------
L["FMT_SMART"]             = "Smart"
L["FMT_CURRENT_PERCENT3"]  = "Current(Percent)"
L["FMT_PERCENT_SLASH_CUR"] = "Percent/Current"
L["FMT_CUR_SLASH_PERCENT"] = "Current/Percent"

------------------------------------------------------------------------
-- NAME FORMAT LIST
------------------------------------------------------------------------
L["NAME_FMT_NAME"]         = "Name"
L["NAME_FMT_ABBREV"]       = "Name (Abbrev)"
L["NAME_FMT_SHORT"]        = "Name (Short)"

------------------------------------------------------------------------
-- CATEGORY TREE (top-level)
------------------------------------------------------------------------
L["CAT_GENERAL"]           = "General"
L["CAT_GLOBAL_SETTINGS"]   = "Global Settings"
L["CAT_MEDIA"]             = "Media"
L["CAT_COLORS"]            = "Colors"
L["CAT_MODULES"]           = "Modules"
L["CAT_PROFILES"]          = "Profiles"
L["CAT_UNIT_FRAMES"]       = "Unit Frames"
L["CAT_GROUP_FRAMES"]      = "Group Frames"
L["CAT_ENEMY_FRAMES"]      = "Enemy Frames"

------------------------------------------------------------------------
-- SUBCATEGORY NAMES
------------------------------------------------------------------------
L["SUBCAT_GENERAL"]        = "General"
L["SUBCAT_HEALTH"]         = "Health Bar"
L["SUBCAT_POWER"]          = "Power Bar"
L["SUBCAT_CASTBAR"]        = "Cast Bar"
L["SUBCAT_CLASSBAR"]       = "Class Resource"
L["SUBCAT_BUFFS"]          = "Buffs"
L["SUBCAT_DEBUFFS"]        = "Debuffs"
L["SUBCAT_TEXTS"]          = "Texts"
L["SUBCAT_HEAL_PRED"]      = "Heal Prediction"
L["SUBCAT_FADER"]          = "Fader"
L["SUBCAT_EFFECTS"]        = "Threat/Highlight"
L["SUBCAT_CUSTOM_TEXT"]    = "Custom Text"
L["SUBCAT_ALT_POWER"]     = "Alt Power Bar"
L["SUBCAT_INDICATORS"]     = "Indicators"
L["SUBCAT_LAYOUT"]         = "Layout"
L["SUBCAT_DISPELS"]        = "Dispels"

------------------------------------------------------------------------
-- GLOBAL SETTINGS PAGE
------------------------------------------------------------------------
L["GLOBAL_HEADER"]         = "Global Settings"
L["GLOBAL_DESC"]           = "Global settings applied to all unit frames"
L["HIDE_BLIZZARD"]         = "Hide Blizzard Frames"
L["AGGRO_COLOR"]           = "Change health bar color on aggro"
L["FADING_SETTINGS"]       = "Fading Settings"
L["OOR_ALPHA"]             = "Out of Range Alpha"
L["DEAD_ALPHA"]            = "Dead Alpha"
L["OFFLINE_ALPHA"]         = "Offline Alpha"
L["CORE_SYSTEM"]           = "Core System"
L["SMOOTH_BARS"]           = "Smooth Bar Animation"
L["PIXEL_PERFECT"]         = "Pixel Perfect Mode"
L["DEAD_DESAT"]            = "Desaturate on Death"
L["OFFLINE_DESAT"]         = "Desaturate on Offline"
L["NUMBER_FORMAT"]         = "Number Format"
L["UNIT_NOTATION"]         = "Unit Notation"
L["NOTATION_WESTERN"]      = "Western (K, M, B)"
L["NOTATION_KOREAN"]       = "Korean (Man, Eok, Jo)"
L["DECIMAL_PLACES"]        = "Decimal Places"

------------------------------------------------------------------------
-- MEDIA PAGE
------------------------------------------------------------------------
L["MEDIA_HEADER"]          = "Media Settings"
L["MEDIA_DESC"]            = "Font and texture settings"
L["STATUSBAR_TEXTURE"]     = "StatusBar Texture"
L["DEFAULT_TEXTURE"]       = "Default Texture"
L["DEFAULT_FONT"]          = "Default Font"
L["FONT_PREVIEW_TEXT"]     = "AaBb 123"
L["FONT_FACE"]             = "Font Face"

------------------------------------------------------------------------
-- COLORS PAGE
------------------------------------------------------------------------
L["COLORS_HEADER"]         = "Color Settings"
L["COLORS_DESC"]           = "Global color and visual settings"
L["UNITFRAME_COLORS"]      = "Unit Frame Colors"
L["HEALTH_BAR_COLOR"]      = "Health Bar Color"
L["HEALTH_LOSS_COLOR"]     = "Health Loss Color"
L["DEAD_COLOR"]            = "Death Color"
L["OFFLINE_COLOR"]         = "Offline Color"
L["REACTION_COLORS"]       = "Reaction Colors"
L["REACTION_FRIENDLY"]     = "Friendly"
L["REACTION_HOSTILE"]      = "Hostile"
L["REACTION_NEUTRAL"]      = "Neutral"
L["REACTION_TAPPED"]       = "Tapped"
L["CASTBAR_COLORS"]        = "Cast Bar Colors"
L["INTERRUPTIBLE"]         = "Interruptible"
L["NON_INTERRUPTIBLE"]     = "Non-Interruptible"
L["SHIELD_HEAL_PRED"]      = "Shield / Heal Prediction"
L["SHIELD"]                = "Shield"
L["OVER_SHIELD"]           = "Over Shield"
L["HEAL_PREDICTION"]       = "Heal Prediction"
L["HEAL_ABSORB"]           = "Heal Absorb"
L["HIGHLIGHT_COLORS"]      = "Highlight Colors"
L["TARGET_HIGHLIGHT"]      = "Target Highlight"
L["MOUSEOVER_HIGHLIGHT"]   = "Mouseover Highlight"
L["POWER_BAR_COLORS"]      = "Power Bar Colors"

------------------------------------------------------------------------
-- POWER TYPE NAMES
------------------------------------------------------------------------
L["POWER_MANA"]            = "Mana"
L["POWER_RAGE"]            = "Rage"
L["POWER_ENERGY"]          = "Energy"
L["POWER_FOCUS"]           = "Focus"
L["POWER_RUNIC_POWER"]     = "Runic Power"
L["POWER_LUNAR_POWER"]     = "Lunar Power"
L["POWER_MAELSTROM"]       = "Maelstrom"
L["POWER_INSANITY"]        = "Insanity"
L["POWER_FURY"]            = "Fury (DH)"
L["POWER_PAIN"]            = "Pain"

------------------------------------------------------------------------
-- CLASS RESOURCE COLORS
------------------------------------------------------------------------
L["CLASS_RESOURCE_COLORS"] = "Class Resource Colors"
L["COMBO_POINTS_1_7"]     = "Combo Points (1~7)"
L["CHARGED"]               = "Charged"
L["HOLY_POWER"]            = "Holy Power"
L["ARCANE_CHARGES"]        = "Arcane Charges"
L["SOUL_SHARDS"]           = "Soul Shards"
L["RUNES_DK"]              = "Runes (Death Knight)"
L["RUNE_BLOOD"]            = "Blood"
L["RUNE_FROST"]            = "Frost"
L["RUNE_UNHOLY"]           = "Unholy"
L["CHI_MONK"]              = "Chi (Monk)"
L["ESSENCE_EVOKER"]        = "Essence (Evoker)"
L["ESSENCE_COLOR"]         = "Essence Color"

------------------------------------------------------------------------
-- MODULES PAGE
------------------------------------------------------------------------
L["MODULES_HEADER"]        = "Module Settings"
L["MODULES_DESC"]          = "Enable/disable additional feature modules"
L["CLICK_CASTING"]         = "Click Casting"
L["CLICK_CAST_DESC"]       = "Cast spells via modifier+click on unit frames (cannot change during combat)"
L["CLICK_CAST_ENABLE"]     = "Enable Click Casting"
L["MOD_NONE"]              = "None"
L["BTN_LEFT"]              = "Left Click"
L["BTN_RIGHT"]             = "Right Click"
L["BTN_MIDDLE"]            = "Middle Click"
L["BTN_4"]                 = "Button 4"
L["BTN_5"]                 = "Button 5"
L["BTN_LEFT_SHORT"]        = "L"
L["BTN_RIGHT_SHORT"]       = "R"
L["BTN_MIDDLE_SHORT"]      = "M"
L["BTN_N_SHORT"]           = "Button"
L["NO_BINDING"]            = "(No binding)"
L["SELECT_SPELL"]          = "Select spell..."
L["SPELLBOOK"]             = "Spellbook"
L["SPELLBOOK_SELECT"]      = "Select spell from Spellbook"
L["SPELL_SEARCH"]          = "Search spell name..."
L["OR_ID"]                 = "or ID:"
L["ADD_BINDING"]           = "Add Binding"
L["REMOVE_LAST"]           = "Remove Last"
L["COMBAT_CHANGE_DENIED"]  = "Cannot change click casting during combat."

------------------------------------------------------------------------
-- TARGET SPELL WARNING MODULE
------------------------------------------------------------------------
L["TARGET_SPELL_WARNING"]  = "Target Spell Warning"
L["TARGET_SPELL_DESC"]     = "Highlight frame when enemy casts spell targeting an ally"
L["TARGET_SPELL_ENABLE"]   = "Enable Target Spell Warning"
L["WARNING_COLOR"]         = "Warning Color"

------------------------------------------------------------------------
-- MY BUFF INDICATOR MODULE
------------------------------------------------------------------------
L["MY_BUFF_INDICATOR"]     = "My Buff Indicator"
L["MY_BUFF_DESC"]          = "Show color bar at bottom of health bar when your buff is applied (HoT tracking)"
L["MY_BUFF_ENABLE"]        = "Enable My Buff Indicator"
L["MAX_DISPLAY"]           = "Max Display Count"
L["BAR_HEIGHT"]            = "Bar Height"
L["SPACING"]               = "Spacing"
L["POS_BOTTOM"]            = "Bottom"
L["POS_TOP"]               = "Top"
L["POSITION"]              = "Position"
L["DEFAULT_COLOR_NIL_CLASS"] = "Default Color (nil=Class Color)"
L["RESTORE_CLASS_COLOR"]   = "Restore Class Color"

------------------------------------------------------------------------
-- PRIVATE AURA MODULE
------------------------------------------------------------------------
L["PRIVATE_AURA"]          = "Private Aura"
L["PRIVATE_AURA_DESC"]     = "Show Blizzard-controlled private auras (boss mechanic debuffs, etc.)"
L["PRIVATE_AURA_ENABLE"]   = "Enable Private Aura Display"
L["PRIVATE_AURA_RELOAD"]   = "Private aura changes require /reload to apply."
L["ICON_SIZE"]             = "Icon Size"
L["MAX_COUNT"]             = "Max Count"
L["PRIVATE_AURA_SIZE_RELOAD"] = "Private aura size changes require /reload to apply."
L["PRIVATE_AURA_COUNT_RELOAD"] = "Private aura count changes require /reload to apply."
L["DIR_RIGHT"]             = "Right"
L["DIR_LEFT"]              = "Left"
L["DIR_UP"]                = "Up"
L["DIR_DOWN"]              = "Down"
L["PRIVATE_AURA_DIR_RELOAD"] = "Private aura direction changes require /reload to apply."
L["GROWTH_DIRECTION"]      = "Growth Direction"

------------------------------------------------------------------------
-- DISPEL HIGHLIGHT MODULE
------------------------------------------------------------------------
L["DISPEL_HIGHLIGHT"]      = "Dispel Highlight"
L["DISPEL_HL_DESC"]        = "Highlight frame border when dispellable debuff exists (party/raid)"
L["DISPEL_HL_ENABLE"]      = "Enable Dispel Highlight"
L["DISPEL_HL_RELOAD"]      = "Dispel highlight changes require /reload to apply."
L["DISPEL_ONLY"]           = "Show Only Dispellable"
L["HL_MODE_BORDER"]        = "Border Color"
L["HL_MODE_GLOW"]          = "Glow Effect"
L["HL_MODE_GRADIENT"]      = "Gradient"
L["HL_MODE_ICON"]          = "Icon"
L["HL_MODE"]               = "Highlight Mode"
L["GLOW_PIXEL"]            = "Pixel"
L["GLOW_SHINE"]            = "Shine"
L["GLOW_PROC"]             = "Proc Effect"
L["GLOW_TYPE"]             = "Glow Type"
L["GLOW_THICKNESS"]        = "Glow Thickness"
L["GRADIENT_ALPHA"]        = "Gradient Alpha"
L["ICON_POSITION"]         = "Icon Position"
L["POS_TOPRIGHT"]          = "Top Right"
L["POS_TOPLEFT"]           = "Top Left"
L["POS_BOTTOMRIGHT"]       = "Bottom Right"
L["POS_BOTTOMLEFT"]        = "Bottom Left"
L["POS_CENTER"]            = "Center"

------------------------------------------------------------------------
-- HEALTH GRADIENT MODULE
------------------------------------------------------------------------
L["HEALTH_GRADIENT"]       = "Health Gradient"
L["HEALTH_GRADIENT_DESC"]  = "Display health bar color as gradient based on health % (Red -> Yellow -> Green)"
L["HEALTH_GRADIENT_ENABLE"] = "Enable Health Gradient"
L["HEALTH_GRADIENT_RELOAD"] = "Health gradient changes require /reload to apply."
L["DANGER_0"]              = "Danger (0%)"
L["NORMAL_50"]             = "Normal (50%)"
L["SAFE_100"]              = "Safe (100%)"

------------------------------------------------------------------------
-- PROFILES PAGE
------------------------------------------------------------------------
L["PROFILES_HEADER"]       = "Profile Management"
L["PROFILES_DESC"]         = "Create, switch, import/export settings profiles"
L["CURRENT_PROFILE"]       = "Current Profile"
L["SWITCH"]                = "Switch"
L["CREATE_PROFILE"]        = "Create Profile"
L["NEW_PROFILE_NAME"]      = "New Profile Name:"
L["PROFILE_NAME_PLACEHOLDER"] = "Enter profile name..."
L["COPY_SOURCE"]           = "Copy Source:"
L["CREATE_PROFILE_BTN"]    = "Create Profile"
L["ERROR_PREFIX"]          = "Error: "
L["UNKNOWN_ERROR"]         = "Unknown error"
L["ENTER_PROFILE_NAME"]    = "Please enter a profile name."
L["DELETE_PROFILE"]        = "Delete Profile"
L["CANNOT_DELETE_DEFAULT"]  = "Cannot delete default profile."
L["RESET_PROFILE"]         = "Reset Profile"
L["RESET_CURRENT"]         = "Reset Current Profile"
L["IMPORT_EXPORT"]         = "Import / Export"
L["EXPORT"]                = "Export"
L["IMPORT"]                = "Import"
L["PROFILE_IMPORT_DONE"]   = "Profile import complete: "

------------------------------------------------------------------------
-- STATIC POPUP DIALOGS
------------------------------------------------------------------------
L["DELETE"]                = "Delete"
L["CANCEL"]                = "Cancel"
L["RESET_CONFIRM"]         = "Reset current profile to defaults?\nThis cannot be undone."
L["RESET_CONFIRM_BTN"]     = "Reset"
L["RESET_ALL_CONFIRM"]     = "Are you sure you want to reset all settings?\nThis cannot be undone."
L["CONFIRM"]               = "OK"
L["EXPORT_POPUP_TEXT"]      = "Profile Export\nCopy the string below:"
L["IMPORT_POPUP_TEXT"]      = "Profile Import\nPaste the export string:"
L["IMPORT_BTN"]            = "Import"

------------------------------------------------------------------------
-- UNIT GENERAL PAGE
------------------------------------------------------------------------
L["GENERAL_SETTINGS_FMT"]  = "%s General Settings"
L["GENERAL_DESC"]          = "Frame size, position, appearance settings"
L["ENABLE"]                = "Enable"
L["SIZE"]                  = "Size"
L["WIDTH"]                 = "Width"
L["HEIGHT"]                = "Height"
L["ANCHOR_SETTINGS"]       = "Anchor Settings"
L["ATTACH_TO_PARENT"]      = "Attach to Parent Frame"
L["BORDER"]                = "Border"
L["SHOW_BORDER"]           = "Show Border"
L["THICKNESS"]             = "Thickness"
L["BORDER_COLOR"]          = "Border Color"
L["BACKGROUND"]            = "Background"
L["BACKGROUND_COLOR"]      = "Background Color"
L["COPY_SETTINGS"]         = "Copy Settings"
L["COPY_FROM_OTHER"]       = "Copy from other unit:"
L["COPY"]                  = "Copy"
L["RESET_SECTION"]         = "Reset"
L["RESET_UNIT_DEFAULT"]    = "Reset this unit to defaults"

------------------------------------------------------------------------
-- HEALTH BAR PAGE
------------------------------------------------------------------------
L["HEALTH_BAR_FMT"]        = "%s Health Bar"
L["HEALTH_BAR_DESC"]       = "Health bar detail settings"
L["COLOR_SETTINGS"]        = "Color Settings"
L["HEALTH_BAR_COLOR_LBL"]  = "Health Bar Color"
L["COLOR_CLASS"]           = "Class Color"
L["COLOR_REACTION"]        = "Reaction Color"
L["COLOR_GRADIENT"]        = "Gradient"
L["COLOR_CUSTOM"]          = "Custom"
L["CUSTOM_COLOR"]          = "Custom Color"
L["LOSS_HEALTH_COLOR"]     = "Loss Health Color"
L["LOSS_COLOR_TYPE_LBL"]   = "Loss Health Color"
L["LOSS_CUSTOM"]           = "Custom"
L["LOSS_CLASS_DARK"]       = "Class Color (Dark)"
L["LOSS_HEALTH_COLOR_CP"]  = "Loss Health Color"
L["TEXTURE"]               = "Texture"
L["HEALTH_BAR_TEXTURE"]    = "Health Bar Texture"
L["HEALTH_BAR_OPTIONS"]    = "Health Bar Options"
L["REVERSE_FILL"]          = "Reverse Health Bar Fill"
L["BG_LOSS_COLOR"]         = "Health Loss Color"
L["BG_TEXTURE"]            = "Background Texture"

------------------------------------------------------------------------
-- POWER BAR PAGE
------------------------------------------------------------------------
L["POWER_BAR_FMT"]         = "%s Power Bar"
L["POWER_BAR_DESC"]        = "Power bar detail settings"
L["POWER_BAR_ENABLE"]      = "Enable Power Bar"
L["SAME_WIDTH_AS_HEALTH"]  = "Use Same Width as Health Bar"
L["USE_POWER_COLOR"]       = "Use Power Type Color"
L["USE_CLASS_COLOR"]       = "Use Class Color"
L["CUSTOM_POWER_COLOR"]    = "Custom Color"
L["DISPLAY_CONDITIONS"]    = "Display Conditions"
L["HIDE_OOC"]              = "Hide When Not in Combat"
L["POWER_BAR_TEXTURE"]     = "Power Bar Texture"
L["ORIENT_AND_DETACH"]     = "Orientation & Detach"
L["BAR_FILL_DIRECTION"]    = "Bar Fill Direction"
L["DETACH_FROM_FRAME"]     = "Detach from Frame"

------------------------------------------------------------------------
-- CAST BAR PAGE
------------------------------------------------------------------------
L["CASTBAR_FMT"]           = "%s Cast Bar"
L["CASTBAR_DESC"]          = "Cast bar detail settings"
L["CASTBAR_ENABLE"]        = "Enable Cast Bar"
L["CASTBAR_DETACH"]        = "Detach from Frame"
L["ICON"]                  = "Icon"
L["SHOW_SPELL_ICON"]       = "Show Spell Icon"
L["ICON_POS"]              = "Icon Position"
L["ICON_POS_LEFT"]         = "Left"
L["ICON_POS_RIGHT"]        = "Right"
L["TEXT"]                   = "Text"
L["SHOW_SPELL_NAME"]       = "Show Spell Name"
L["SHOW_TIMER"]            = "Show Timer"
L["SPELL_FONT"]            = "Spell Font"
L["TIMER_FONT"]            = "Timer Font"
L["CASTBAR_TEXTURE"]       = "Cast Bar Texture"
L["COLOR_OPTIONS"]         = "Color Options"
L["CASTBAR_USE_CLASS"]     = "Use Class Color"
L["SHOW_INTERRUPT_ONLY"]   = "Show Interruptible Only"
L["INTERRUPTIBLE_COLOR"]   = "Interruptible Color"
L["NON_INTERRUPT_COLOR"]   = "Non-Interruptible Color"
L["CASTBAR_BG"]            = "Cast Bar Background"
L["SPARK_PROGRESS"]        = "Spark (Progress Indicator)"
L["SHOW_SPARK"]            = "Show Spark"
L["SPARK_WIDTH"]           = "Spark Width"
L["DETACHED_POSITION"]     = "Detached Position"

------------------------------------------------------------------------
-- AURA (BUFF/DEBUFF) PAGE
------------------------------------------------------------------------
L["AURA_BUFF"]             = "Buff"
L["AURA_DEBUFF"]           = "Debuff"
L["SIZE_AND_LAYOUT"]       = "Size & Layout"
L["ICON_SIZE_AURA"]        = "Icon Size"
L["MAX_AURAS"]             = "Max Count"
L["H_SPACING"]             = "Horizontal Spacing"
L["V_SPACING"]             = "Vertical Spacing"
L["PER_LINE"]              = "Per Line"
L["DISPLAY_OPTIONS"]       = "Display Options"
L["SHOW_DURATION"]         = "Show Duration"
L["SHOW_STACKS"]           = "Show Stacks"
L["SHOW_TOOLTIP"]          = "Show Tooltip"
L["FILTER"]                = "Filter"
L["DISPEL_ONLY_FILTER"]    = "Show Only Dispellable"
L["BOSS_AURA_PRIORITY"]    = "Boss Aura Priority"
L["MY_AURAS"]              = "My Auras"
L["OTHER_AURAS"]           = "Others' Auras"
L["PLAYERS_ONLY"]          = "Players Only"
L["HIDE_NO_DURATION"]      = "Hide No Duration"
L["MIN_DURATION_SEC"]      = "Min Duration (sec)"
L["MAX_DURATION_SEC"]      = "Max Duration (sec)"
L["DIR_AND_POS"]           = "Direction & Position"
L["INTERACTION"]           = "Interaction"
L["CLICK_THROUGH"]         = "Click Through"
L["HIDE_IN_COMBAT"]        = "Hide in Combat"
L["WHITELIST_BLACKLIST"]   = "Whitelist / Blacklist"
L["USE_WHITELIST"]         = "Use Whitelist"
L["WL_PRIORITY"]           = "Priority Mode (Ignore Other Filters)"
L["WHITELIST_SPELL_ID"]    = "Whitelist (Spell ID)"
L["USE_BLACKLIST"]         = "Use Blacklist"
L["BLACKLIST_SPELL_ID"]    = "Blacklist (Spell ID)"

------------------------------------------------------------------------
-- TEXTS PAGE
------------------------------------------------------------------------
L["TEXTS_FMT"]             = "%s Texts"
L["TEXTS_DESC"]            = "Text widget settings (font, position, color, format)"
L["NAME_TEXT"]              = "Name Text"
L["SHOW_NAME"]             = "Show Name"
L["NAME_FORMAT"]           = "Name Format"
L["NAME_COLOR"]            = "Name Color"
L["HEALTH_TEXT"]            = "Health Text"
L["SHOW_HEALTH_TEXT"]      = "Show Health Text"
L["HEALTH_FORMAT"]         = "Health Format"
L["SEPARATOR"]             = "Separator"
L["HEALTH_TEXT_COLOR"]     = "Health Text Color"
L["DEAD_STATUS"]           = "Show Dead Status"
L["POWER_TEXT"]             = "Power Text"
L["SHOW_POWER_TEXT"]       = "Show Power Text"
L["POWER_FORMAT"]          = "Power Format"
L["POWER_COLOR"]           = "Power Color"
L["ANCHOR_TO_POWER"]       = "Anchor to Power Bar"

------------------------------------------------------------------------
-- LAYOUT PAGE (Group/Raid)
------------------------------------------------------------------------
L["LAYOUT_FMT"]            = "%s Layout"
L["LAYOUT_DESC"]           = "Group layout settings"
L["GROWTH_DIR"]            = "Growth Direction"
L["GROWTH_DOWN"]           = "Down"
L["GROWTH_UP"]             = "Up"
L["GROWTH_RIGHT"]          = "Right"
L["GROWTH_LEFT"]           = "Left"
L["H_SPACING_LAYOUT"]      = "Horizontal Spacing"
L["V_SPACING_LAYOUT"]      = "Vertical Spacing"
L["GROUP_SPACING"]         = "Group Spacing"
L["UNITS_PER_COL"]         = "Units Per Column"
L["MAX_COLUMNS"]           = "Max Columns"
L["GROUP_BY"]              = "Group By"
L["GROUP_BY_GROUP"]        = "Group"
L["GROUP_BY_ROLE"]         = "Role"
L["GROUP_BY_CLASS"]        = "Class"
L["MAX_GROUPS"]            = "Max Groups"
L["SORT_DIR"]              = "Sort Direction"
L["SORT_ASC"]              = "Ascending"
L["SORT_DESC"]             = "Descending"
L["SORT_METHOD"]           = "Sort Method"
L["SORT_INDEX"]            = "Index"
L["SORT_NAME"]             = "Name"
L["PARTY_SPACING"]         = "Spacing"
L["SHOW_PLAYER_IN_PARTY"]  = "Show Player in Party"
L["SHOW_IN_RAID"]          = "Show in Raid"

------------------------------------------------------------------------
-- HEAL PREDICTION PAGE
------------------------------------------------------------------------
L["HEAL_PRED_FMT"]         = "%s Heal Prediction"
L["HEAL_PRED_DESC"]        = "Heal prediction, heal absorb, shield bar settings"
L["HEAL_PRED_SECTION"]     = "Heal Prediction (Incoming Heal)"
L["SHOW_HEAL_PRED"]        = "Show Heal Prediction"
L["SHOW_OVERHEAL"]         = "Show Overheal"
L["HEAL_PRED_COLOR"]       = "Heal Prediction Color"
L["OVERHEAL_COLOR"]        = "Overheal Color"
L["PRED_BAR_ALPHA"]        = "Prediction Bar Alpha"
L["OVERHEAL_ALPHA"]        = "Overheal Alpha"
L["HEAL_ABSORB_SECTION"]   = "Heal Absorb (Anti-Heal)"
L["SHOW_HEAL_ABSORB"]      = "Show Heal Absorb"
L["HEAL_ABSORB_COLOR"]     = "Heal Absorb Color"
L["SHIELD_BAR_SECTION"]    = "Shield Bar (Absorb Shield)"
L["SHOW_SHIELD_BAR"]       = "Show Shield Bar"
L["SHOW_OVER_SHIELD"]      = "Show Over Shield"
L["REVERSE_FILL_SHIELD"]   = "Reverse Fill"
L["SHIELD_COLOR"]          = "Shield Color"
L["OVER_SHIELD_COLOR"]     = "Over Shield Color"

------------------------------------------------------------------------
-- DISPELS PAGE
------------------------------------------------------------------------
L["DISPELS_FMT"]           = "%s Dispels"
L["DISPELS_DESC"]          = "Dispellable debuff overlay settings"
L["DISPEL_OVERLAY_ENABLE"] = "Enable Dispel Overlay"
L["HL_TYPE"]               = "Highlight Type"
L["HL_TYPE_CURRENT"]       = "Current Debuff"
L["HL_TYPE_ENTIRE"]        = "Entire Frame"
L["DISPEL_TYPES"]          = "Dispel Types"
L["DTYPE_MAGIC"]           = "Magic"
L["DTYPE_CURSE"]           = "Curse"
L["DTYPE_DISEASE"]         = "Disease"
L["DTYPE_POISON"]          = "Poison"
L["DTYPE_BLEED"]           = "Bleed"
L["DTYPE_ENRAGE"]          = "Enrage"
L["ICON_STYLE"]            = "Icon Style"
L["ICON_STYLE_NONE"]       = "None"
L["ICON_STYLE_ICON"]       = "Icon"

------------------------------------------------------------------------
-- THREAT/HIGHLIGHT PAGE
------------------------------------------------------------------------
L["THREAT_HL_FMT"]         = "%s Threat/Highlight"
L["THREAT_HL_DESC"]        = "Threat display and highlight settings"
L["THREAT_DISPLAY"]        = "Threat Display"
L["THREAT_ENABLE"]         = "Enable Threat Display"
L["THREAT_STYLE"]          = "Threat Style"
L["THREAT_BORDER"]         = "Border"
L["THREAT_GLOW"]           = "Glow"
L["BORDER_THICKNESS"]      = "Border Thickness"
L["HIGH_THREAT"]           = "High Threat"
L["MAX_THREAT"]            = "Max Threat"
L["TANKING"]               = "Tanking"
L["HIGHLIGHT_SECTION"]     = "Highlight"
L["HIGHLIGHT_ENABLE"]      = "Enable Highlight"
L["MOUSEOVER_HL"]          = "Mouseover Highlight"
L["TARGET_HL"]             = "Target Highlight"
L["TARGET_COLOR"]          = "Target Color"
L["MOUSEOVER_COLOR"]       = "Mouseover Color"

------------------------------------------------------------------------
-- FADER PAGE
------------------------------------------------------------------------
L["FADER_FMT"]             = "%s Fader"
L["FADER_DESC"]            = "Automatically fade frame based on conditions"
L["FADER_ENABLE"]          = "Enable Fader System"
L["FADE_CONDITIONS"]       = "Fade Conditions (Checked = Stay Opaque)"
L["IN_RANGE"]              = "In Range"
L["IN_COMBAT"]             = "In Combat"
L["MOUSEOVER"]             = "Mouseover"
L["IS_TARGET"]             = "Is Target"
L["UNIT_IS_TARGET"]        = "Unit is Target"
L["ALPHA_SETTINGS"]        = "Alpha Settings"
L["MAX_ALPHA"]             = "Max Alpha"
L["MIN_ALPHA"]             = "Min Alpha"
L["FADE_DURATION"]         = "Transition Duration (sec)"

------------------------------------------------------------------------
-- CUSTOM TEXT PAGE
------------------------------------------------------------------------
L["CUSTOM_TEXT_FMT"]       = "%s Custom Text"
L["CUSTOM_TEXT_DESC"]      = "Up to 3 custom text widget settings"
L["CUSTOM_TEXT_ENABLE"]    = "Enable Custom Text System"
L["FMT_NONE_MANUAL"]      = "None (Manual Input)"
L["TEXT_SLOT_FMT"]         = "Text Slot %d"
L["TEXT_FORMAT"]           = "Text Format"
L["TAG_PLACEHOLDER"]       = "e.g. [name] - [health:percent]"
L["TAG_HELP"]              = "Tags: [name] [health:percent] [health:current] [power:current] [level] [class] [status]"
L["COLOR"]                 = "Color"

------------------------------------------------------------------------
-- ALT POWER BAR PAGE
------------------------------------------------------------------------
L["ALT_POWER_FMT"]         = "%s Alt Power Bar"
L["ALT_POWER_DESC"]        = "Alt power bar (alternate power) settings"
L["ALT_POWER_ENABLE"]      = "Enable Alt Power Bar"
L["BAR_TEXTURE"]           = "Bar Texture"

------------------------------------------------------------------------
-- INDICATORS PAGE
------------------------------------------------------------------------
L["INDICATORS_FMT"]        = "%s Indicators"
L["INDICATORS_DESC"]       = "Icon and indicator settings"
L["INDICATOR_RESURRECT"]   = "Resurrect"
L["INDICATOR_SUMMON"]      = "Summon"
L["RESTING_ICON"]          = "Resting Icon"
L["SHOW_RESTING"]          = "Show Resting Icon"
L["HIDE_MAX_LEVEL"]        = "Hide at Max Level"

------------------------------------------------------------------------
-- CLASS RESOURCE PAGE
------------------------------------------------------------------------
L["CLASS_RESOURCE_HEADER"] = "Player Class Resource"
L["CLASS_RESOURCE_DESC"]   = "Class-specific resource bar settings"
L["CLASS_BAR_ENABLE"]      = "Enable Class Resource Bar"
L["HIDE_OOC_CLASS"]        = "Hide When Not in Combat"
L["SAME_WIDTH_HEALTH"]     = "Same Width as Health Bar"
L["VERTICAL_FILL"]         = "Vertical Fill"
L["CLASS_BAR_TEXTURE"]     = "Class Resource Bar Texture"
L["SHOW_BORDER_CLASS"]     = "Show Border"
L["SHOW_BG"]               = "Show Background"
L["BG_TEXTURE_CLASS"]      = "Background Texture"

------------------------------------------------------------------------
-- MOVER (Edit Mode)
------------------------------------------------------------------------
L["MOVER_LCLICK_SELECT"]   = "Left-click: Select  |  Shift+Click: Multi-select"
L["MOVER_DRAG_MOVE"]       = "Drag: Move  |  Right-click: Settings"
L["MOVER_WHEEL_Y"]         = "Scroll Wheel: Y-Move  |  Shift+Wheel: X-Move"
L["MOVER_ARROW_NUDGE"]     = "Arrow Keys: Nudge  |  Ctrl+Arrow: 10px"
L["MOVER_GRID_TOGGLE"]     = "Left-click: Grid ON/OFF"
L["MOVER_GRID_PRESET"]     = "Right-click: Preset Cycle (8/16/32/64)"
L["MOVER_GRID_SLIDER"]     = "Slider: 4-64px Continuous"
L["MOVER_MULTI_SELECT"]    = "%d Selected"
L["EDIT_MODE"]             = "Edit Mode"

------------------------------------------------------------------------
-- INIT (Slash commands)
------------------------------------------------------------------------
L["SLASH_COMMANDS"]        = "Commands:"
L["SLASH_OPTIONS"]         = "/duf - Open Options Panel"
L["SLASH_UNLOCK"]          = "/duf unlock|edit - Edit Mode ON (ESC: Cancel, Done: Save)"
L["SLASH_LOCK"]            = "/duf lock - Edit Mode OFF"
L["SLASH_RESET"]           = "/duf reset - Reset Settings"
L["SLASH_DEBUG"]            = "/duf debug - Toggle Debug Mode"
L["SLASH_DIAG"]            = "/duf diag - Print Diagnostic Info"
L["SLASH_PROFILE_LIST"]    = "/duf profile list - Profile List"
L["SLASH_PROFILE_SWITCH"]  = "/duf profile switch <name> - Switch Profile"
L["SLASH_PROFILE_NEW"]     = "/duf profile new <name> - New Profile"
L["DEBUG_LABEL"]           = "Debug:"
L["EDIT_MODE_OFF"]         = "Edit Mode OFF"
L["EDIT_MODE_ON"]          = "Edit Mode ON - Drag to Move | ESC: Cancel | Done: Save"

------------------------------------------------------------------------
-- DIAGNOSTICS
------------------------------------------------------------------------
L["DIAG_HEADER"]           = "=== ddingUI UF Diagnostic ==="
L["DIAG_MODULES"]          = "Module Load: "
L["DIAG_MISSING"]          = "Missing: "
L["DIAG_DB_UNITS"]         = "ns.db Units: "
L["DIAG_FRAMES"]           = "Frames: "
L["DIAG_FRAMES_FMT"]       = "Frames: %d"
L["DIAG_NO_FRAME"]         = "No frame! Spawn failed?"
L["DIAG_HEADERS"]          = "Headers: "
L["DIAG_HEADERS_FMT"]      = "Headers: %d"
L["DIAG_UPDATE_OK"]        = "Update Functions: All OK"
L["DIAG_SV"]               = "SavedVariables: "
L["DIAG_SV_FMT"]           = "SavedVariables: %d profiles"
L["DIAG_SYS_ENABLED"]      = "System enabled: "
L["DIAG_TOTAL_SLOTS"]      = "Total Slots: "
L["DIAG_OUF_TAGS"]         = "oUF registered tags: "
L["DIAG_DDINGUI_TAGS"]     = "ddingui tag registrations: "
L["DIAG_RESULT"]           = "Result: "
L["DIAG_MAIN_FRAME"]       = "Main Frame:"
L["DIAG_SIZE_FMT"]         = "Size:"
L["DIAG_CHILDREN"]         = "Child Frames: "
L["DIAG_NO_FRAME_UNIT"]    = "No Frame:"
L["DIAG_HEALTH_DBG"]       = "Health Text Debug:"

------------------------------------------------------------------------
-- PROFILES (Core/Profiles.lua)
------------------------------------------------------------------------
L["PROFILE_SWITCH"]        = "Profile Switch: "
L["PROFILE_CREATE"]        = "Profile Create: "
L["PROFILE_DELETE"]        = "Profile Delete: "
L["PROFILE_RENAME"]        = "Profile Rename: "
L["PROFILE_COPY"]          = "Profile Copy: "
L["PROFILE_RESET"]         = "Profile Reset: "
L["PROFILE_IMPORT_DONE"]   = "Profile Import Complete: "
L["PROFILE_SYSTEM_NA"]     = "Profile system not available"
L["PROFILE_LIST"]          = "Profile List:"
L["PROFILE_CURRENT"]       = "(Current)"
L["PROFILE_COMMANDS"]      = "Profile Commands:"

------------------------------------------------------------------------
-- CONFIG (defaults)
------------------------------------------------------------------------
L["INTERRUPTED"]           = "Interrupted"
L["DEAD"]                  = "Dead"

------------------------------------------------------------------------
-- PREVIEW
------------------------------------------------------------------------
L["PREVIEW_LABEL"]         = "Preview"
L["SPELL_CASTING"]         = "Spell Casting"
L["DUMMY_TANK"]            = "Tank"
L["DUMMY_HEALER"]          = "Healer"
L["DUMMY_MAGE"]            = "Mage"
L["DUMMY_ROGUE"]           = "Rogue"
L["DUMMY_HUNTER"]          = "Hunter"
L["DUMMY_PALADIN"]         = "Paladin"
L["DUMMY_DRUID"]           = "Druid"
L["DUMMY_WARLOCK"]         = "Warlock"
L["DUMMY_SHAMAN"]          = "Shaman"
L["DUMMY_DK"]              = "Death Knight"
L["DUMMY_MONK"]            = "Monk"
L["DUMMY_DH"]              = "Demon Hunter"
L["DUMMY_EVOKER"]          = "Evoker"
L["DUMMY_WARRIOR"]         = "Warrior"
L["DUMMY_PRIEST"]          = "Priest"
L["DUMMY_ARCANIST"]        = "Arcanist"
L["DUMMY_ASSASSIN"]        = "Assassin"
L["DUMMY_SNIPER"]          = "Sniper"
L["DUMMY_PROTECTOR"]       = "Protector"
L["DUMMY_RESTO_DRUID"]     = "Resto Druid"
L["DUMMY_BOSS1"]           = "Giant Spider"
L["DUMMY_BOSS2"]           = "Boss Lieutenant"
L["DUMMY_BOSS3"]           = "Elite Minion"
L["DUMMY_ARENA1"]          = "Enemy Warrior"
L["DUMMY_ARENA2"]          = "Enemy Priest"
L["DUMMY_ARENA3"]          = "Enemy Rogue"

------------------------------------------------------------------------
-- SEARCH (Options.lua search)
------------------------------------------------------------------------
L["SEARCH_RESULTS_FMT"]    = "Search Results  |cff999999(%d found)|r"

------------------------------------------------------------------------
-- TAG REFERENCE
------------------------------------------------------------------------
L["TAG_REFERENCE"]         = "Tag Reference"
L["TAG_COPY_HINT"]         = "Click a tag to copy here"
L["TAG_CLICK_COPY"]        = "Click -> Copy | Ctrl+C to paste"
L["TAG_CAT_NAME"]          = "Name"
L["TAG_CAT_HEALTH"]        = "Health"
L["TAG_CAT_POWER"]         = "Power"
L["TAG_CAT_SHIELD"]        = "Shield / Absorb / Heal"
L["TAG_CAT_COLOR"]         = "Color (prepend, end with |r)"
L["TAG_CAT_STATUS"]        = "Status / Level / Classification"
L["TAG_CAT_EXAMPLE"]       = "Combination Examples"

-- Tag descriptions
L["TAG_FULLNAME"]          = "Full Name"
L["TAG_SHORTNAME"]         = "Short Name (8 chars)"
L["TAG_MEDNAME"]           = "Medium Name (14 chars)"
L["TAG_RAIDNAME"]          = "Raid Name (6 chars)"
L["TAG_VSHORTNAME"]        = "Very Short (4 chars)"
L["TAG_ABBREV"]            = "Abbreviated"
L["TAG_ROLE_NAME"]         = "Role Icon + Name"
L["TAG_HEALTH_SMART"]      = "Smart (Name when full)"
L["TAG_HEALTH_PCT"]        = "Percent (hide 100%)"
L["TAG_HEALTH_PCT_FULL"]   = "Percent (always show)"
L["TAG_HEALTH_CUR"]        = "Current"
L["TAG_HEALTH_MAX"]        = "Max"
L["TAG_HEALTH_CUR_MAX"]    = "Current / Max"
L["TAG_HEALTH_CUR_PCT"]    = "Current | Percent"
L["TAG_HEALTH_DEFICIT"]    = "Deficit"
L["TAG_HEALTH_RAID"]       = "Raid (hide 100%)"
L["TAG_HEALTH_HEALER"]     = "Healer Deficit"
L["TAG_HEALTH_ABSORB"]     = "Current + Shield"
L["TAG_POWER_CUR"]         = "Power Current"
L["TAG_POWER_PCT"]         = "Power Percent"
L["TAG_POWER_CUR_MAX"]     = "Power / Max"
L["TAG_POWER_DEFICIT"]     = "Power Deficit"
L["TAG_POWER_HEALER"]      = "Healer Power"
L["TAG_ABSORB"]            = "Shield (Damage Absorb)"
L["TAG_ABSORB_PCT"]        = "Shield Percent"
L["TAG_HEALABSORB"]        = "Heal Absorb (Necrotic, etc.)"
L["TAG_INCHEAL"]           = "Incoming Heal"
L["TAG_CLASSCOLOR"]        = "Class Color"
L["TAG_HEALTHCOLOR"]       = "Health Ratio Color"
L["TAG_POWERCOLOR"]        = "Power Type Color"
L["TAG_REACTIONCOLOR"]     = "Friendly/Hostile Color"
L["TAG_STATUS"]            = "Dead/Offline/AFK"
L["TAG_LEVEL"]             = "Level"
L["TAG_LEVEL_SMART"]       = "Smart Level (Boss/Elite)"
L["TAG_OUF_NAME"]          = "Name"
L["TAG_OUF_PERHP"]         = "Health%"
L["TAG_OUF_PERPP"]         = "Power%"
L["TAG_OUF_CURHP"]         = "Current HP (raw)"
L["TAG_OUF_MAXHP"]         = "Max HP"
L["TAG_OUF_MISSINGHP"]     = "Missing HP"
L["TAG_OUF_CURPP"]         = "Power"
L["TAG_OUF_LEVEL"]         = "Level"
L["TAG_OUF_DEAD"]          = "Dead"
L["TAG_OUF_OFFLINE"]       = "Offline"
L["TAG_OUF_THREAT"]        = "Threat"
L["TAG_OUF_RAIDCOLOR"]     = "Class Color"
L["TAG_OUF_POWERCOLOR"]    = "Power Color"
L["TAG_EX_CLASS_NAME"]     = "Class Color Name"
L["TAG_EX_HEALTH_PCT"]     = "Health Color Percent"
L["TAG_EX_HEALTH_SHIELD"]  = "Health (Shield)"
