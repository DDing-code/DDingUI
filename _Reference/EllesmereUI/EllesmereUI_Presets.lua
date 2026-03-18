-------------------------------------------------------------------------------
--  EllesmereUI_Presets.lua
--
--  Preset system, spec assignment popup, and spec auto-switch handler.
--  Split from EllesmereUI.lua -- see EllesmereUI.lua for the base addon code.
--
--  Load order (via TOC):
--    1. EllesmereUI.lua        -- constants, utils, popups, main frame
--    2. EllesmereUI_Widgets.lua -- shared widget helpers, widget factory
--    3. EllesmereUI_Presets.lua -- THIS FILE
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
local PP = EllesmereUI.PanelPP

-- Utility functions
local SolidTex         = EllesmereUI.SolidTex
local MakeFont         = EllesmereUI.MakeFont
local MakeBorder       = EllesmereUI.MakeBorder
local DisablePixelSnap = EllesmereUI.DisablePixelSnap
local lerp             = EllesmereUI.lerp
local MakeDropdownArrow = EllesmereUI.MakeDropdownArrow
local RegisterWidgetRefresh = EllesmereUI.RegisterWidgetRefresh

-- Widget helpers (from EllesmereUI_Widgets.lua — resolved lazily since Widgets
-- may be deferred; these locals are populated inside BuildPresetSystem)
local MakeStyledButton, WB_COLOURS, RB_COLOURS, DDText
local BuildDropdownMenu, WireDropdownScripts, WD_DD_COLOURS, RD_DD_COLOURS
local BuildSliderCore, BuildDropdownControl

-- Visual constants
local EXPRESSWAY       = EllesmereUI.EXPRESSWAY
local ELLESMERE_GREEN  = EllesmereUI.ELLESMERE_GREEN
local CONTENT_PAD      = EllesmereUI.CONTENT_PAD
local DARK_BG          = EllesmereUI.DARK_BG
local BORDER_COLOR     = EllesmereUI.BORDER_COLOR
local TEXT_WHITE       = EllesmereUI.TEXT_WHITE
local TEXT_DIM         = EllesmereUI.TEXT_DIM
local MEDIA_PATH       = EllesmereUI.MEDIA_PATH
local ICONS_PATH       = EllesmereUI.ICONS_PATH
local CLASS_COLOR_MAP  = EllesmereUI.CLASS_COLOR_MAP
local CLASS_ART_MAP    = EllesmereUI.CLASS_ART_MAP

-- Numeric constants used in preset UI
local TEXT_WHITE_R = EllesmereUI.TEXT_WHITE_R
local TEXT_WHITE_G = EllesmereUI.TEXT_WHITE_G
local TEXT_WHITE_B = EllesmereUI.TEXT_WHITE_B
local TEXT_DIM_R   = EllesmereUI.TEXT_DIM_R
local TEXT_DIM_G   = EllesmereUI.TEXT_DIM_G
local TEXT_DIM_B   = EllesmereUI.TEXT_DIM_B
local TEXT_DIM_A   = EllesmereUI.TEXT_DIM_A
local BORDER_R     = EllesmereUI.BORDER_R
local BORDER_G     = EllesmereUI.BORDER_G
local BORDER_B     = EllesmereUI.BORDER_B
local CB_BOX_R     = EllesmereUI.CB_BOX_R
local CB_BOX_G     = EllesmereUI.CB_BOX_G
local CB_BOX_B     = EllesmereUI.CB_BOX_B
local CB_BRD_A     = EllesmereUI.CB_BRD_A
local CB_ACT_BRD_A = EllesmereUI.CB_ACT_BRD_A
local DD_BG_R      = EllesmereUI.DD_BG_R
local DD_BG_G      = EllesmereUI.DD_BG_G
local DD_BG_B      = EllesmereUI.DD_BG_B
local DD_BG_A      = EllesmereUI.DD_BG_A
local DD_BG_HA     = EllesmereUI.DD_BG_HA
local DD_BRD_A     = EllesmereUI.DD_BRD_A
local DD_BRD_HA    = EllesmereUI.DD_BRD_HA
local DD_TXT_A     = EllesmereUI.DD_TXT_A
local DD_TXT_HA    = EllesmereUI.DD_TXT_HA
local DD_ITEM_HL_A  = EllesmereUI.DD_ITEM_HL_A
local DD_ITEM_SEL_A = EllesmereUI.DD_ITEM_SEL_A
local BTN_BG_R     = EllesmereUI.BTN_BG_R
local BTN_BG_G     = EllesmereUI.BTN_BG_G
local BTN_BG_B     = EllesmereUI.BTN_BG_B
local BTN_BG_A     = EllesmereUI.BTN_BG_A
local BTN_BG_HA    = EllesmereUI.BTN_BG_HA
local BTN_BRD_A    = EllesmereUI.BTN_BRD_A
local BTN_BRD_HA   = EllesmereUI.BTN_BRD_HA
local BTN_TXT_A    = EllesmereUI.BTN_TXT_A
local BTN_TXT_HA   = EllesmereUI.BTN_TXT_HA
local SL_INPUT_A   = EllesmereUI.SL_INPUT_A


-------------------------------------------------------------------------------
--  SPEC ASSIGNMENT POPUP
--
--  Shows every spec sorted by class with checkboxes in a 3-column layout.
--  Stores assignments in db[dbKey][presetKey] = { [specID] = true, ... }
-------------------------------------------------------------------------------
do
    -- All WoW Retail classes and their specs (as of TWW / 12.0)
    -- Order: alphabetical by class name
    local SPEC_DATA = {
        { class = "DEATHKNIGHT",  name = "Death Knight",  specs = {
            { id = 250, name = "Blood" },
            { id = 251, name = "Frost" },
            { id = 252, name = "Unholy" },
        }},
        { class = "DEMONHUNTER",  name = "Demon Hunter",  specs = {
            { id = 577, name = "Havoc" },
            { id = 581, name = "Vengeance" },
            { id = 1456, name = "Devourer" },
        }},
        { class = "DRUID",        name = "Druid",         specs = {
            { id = 102, name = "Balance" },
            { id = 103, name = "Feral" },
            { id = 104, name = "Guardian" },
            { id = 105, name = "Restoration" },
        }},
        { class = "EVOKER",       name = "Evoker",        specs = {
            { id = 1467, name = "Devastation" },
            { id = 1468, name = "Preservation" },
            { id = 1473, name = "Augmentation" },
        }},
        { class = "HUNTER",       name = "Hunter",        specs = {
            { id = 253, name = "Beast Mastery" },
            { id = 254, name = "Marksmanship" },
            { id = 255, name = "Survival" },
        }},
        { class = "MAGE",         name = "Mage",          specs = {
            { id = 62,  name = "Arcane" },
            { id = 63,  name = "Fire" },
            { id = 64,  name = "Frost" },
        }},
        { class = "MONK",         name = "Monk",          specs = {
            { id = 268, name = "Brewmaster" },
            { id = 270, name = "Mistweaver" },
            { id = 269, name = "Windwalker" },
        }},
        { class = "PALADIN",      name = "Paladin",       specs = {
            { id = 65,  name = "Holy" },
            { id = 66,  name = "Protection" },
            { id = 70,  name = "Retribution" },
        }},
        { class = "PRIEST",       name = "Priest",        specs = {
            { id = 256, name = "Discipline" },
            { id = 257, name = "Holy" },
            { id = 258, name = "Shadow" },
        }},
        { class = "ROGUE",        name = "Rogue",         specs = {
            { id = 259, name = "Assassination" },
            { id = 260, name = "Outlaw" },
            { id = 261, name = "Subtlety" },
        }},
        { class = "SHAMAN",       name = "Shaman",        specs = {
            { id = 262, name = "Elemental" },
            { id = 263, name = "Enhancement" },
            { id = 264, name = "Restoration" },
        }},
        { class = "WARLOCK",      name = "Warlock",       specs = {
            { id = 265, name = "Affliction" },
            { id = 266, name = "Demonology" },
            { id = 267, name = "Destruction" },
        }},
        { class = "WARRIOR",      name = "Warrior",       specs = {
            { id = 71,  name = "Arms" },
            { id = 72,  name = "Fury" },
            { id = 73,  name = "Protection" },
        }},
    }
    EllesmereUI._SPEC_DATA = SPEC_DATA

    -- 5-column layout, sorted alphabetically left-to-right, top-to-bottom:
    --   col1 = DK, Mage, Shaman
    --   col2 = DH, Monk, Warlock
    --   col3 = Druid, Paladin, Warrior
    --   col4 = Evoker, Priest
    --   col5 = Hunter, Rogue
    local NUM_COLS = 5
    local COL_LISTS = { {1,6,11}, {2,7,12}, {3,8,13}, {4,9}, {5,10} }

    local specPopup  -- reusable popup frame

    function EllesmereUI:ShowSpecAssignPopup(opts)
        local db        = opts.db
        local dbKey     = opts.dbKey
        local presetKey = opts.presetKey
        local defaultKey = opts.defaultKey            -- DB key for spec default preset (nil = no default feature)
        local allPresetKeysFn = opts.allPresetKeys    -- function() returns { {key=, name=}, ... } of presets excluding current
        local onDefaultChanged = opts.onDefaultChanged -- callback after default is set
        local onDone = opts.onDone                    -- callback after popup closes (used to apply preset for current spec)

        -- Ensure assignments table exists
        if not db[dbKey] then db[dbKey] = {} end
        if not db[dbKey][presetKey] then db[dbKey][presetKey] = {} end
        local assignments = db[dbKey][presetKey]

        -- Build or reuse the popup
        if not specPopup then
            local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
            local COL_W = 165
            local COL_GAP = 12
            local CONTENT_LEFT = 41      -- left padding (26 + 15px extra)
            local CONTENT_RIGHT = 36     -- right padding (26 + 10px extra)
            local CONTENT_TOP = 120      -- below title + subtitle + check/uncheck links (-20px below links)
            local CLASS_H = 32           -- class header row height
            local CLASS_PAD_TOP = 4      -- extra space above each class title
            local CLASS_PAD_BOT = 2      -- extra space below each class title
            local SPEC_H = 28            -- spec checkbox row height
            local CLASS_GAP = 10         -- extra spacing between class groups

            -- Dynamic popup width based on column count
            local POPUP_W = CONTENT_LEFT + CONTENT_RIGHT + NUM_COLS * COL_W + (NUM_COLS - 1) * COL_GAP
            local POPUP_H = 740

            -- Pixel-perfect scale (includes user panel scale)
            local ppScale = EllesmereUI.GetPopupScale()

            -- Dimmer
            local dimmer = CreateFrame("Frame", "EUISpecAssignDimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:EnableMouseWheel(true)
            dimmer:SetScript("OnMouseWheel", function() end)
            dimmer:Hide()
            dimmer:SetScale(ppScale)

            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0, 0, 0, 0.25)

            -- Popup frame
            local popup = CreateFrame("Frame", "EUISpecAssignPopup", dimmer)
            popup:SetScale(ppScale)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)

            -- Register for scale updates when user changes panel scale
            local pf = EllesmereUI._popupFrames
            if pf then pf[#pf + 1] = { popup = popup, dimmer = dimmer } end
            PP.Size(popup, POPUP_W, POPUP_H)
            PP.Point(popup, "CENTER", EllesmereUI._mainFrame, "CENTER", 0, 0)

            -- Background
            local bg = popup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 1)

            -- Border (2px inset) -- 4 edge textures
            local BRD_A_SP = 0.15
            local spT = popup:CreateTexture(nil, "BORDER"); spT:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spT.SetSnapToPixelGrid then spT:SetSnapToPixelGrid(false); spT:SetTexelSnappingBias(0) end
            spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); PP.Height(spT, 2)
            local spB = popup:CreateTexture(nil, "BORDER"); spB:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spB.SetSnapToPixelGrid then spB:SetSnapToPixelGrid(false); spB:SetTexelSnappingBias(0) end
            spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); PP.Height(spB, 2)
            local spL = popup:CreateTexture(nil, "BORDER"); spL:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spL.SetSnapToPixelGrid then spL:SetSnapToPixelGrid(false); spL:SetTexelSnappingBias(0) end
            spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); PP.Width(spL, 2)
            local spR = popup:CreateTexture(nil, "BORDER"); spR:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spR.SetSnapToPixelGrid then spR:SetSnapToPixelGrid(false); spR:SetTexelSnappingBias(0) end
            spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); PP.Width(spR, 2)

            -- Title
            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT, 22, "")
            title:SetTextColor(1, 1, 1, 1)
            PP.Point(title, "TOP", popup, "TOP", 0, -32)
            title:SetText("Assign Preset to Specs")
            popup._title = title

            -- Subtitle
            local sub = popup:CreateFontString(nil, "OVERLAY")
            sub:SetFont(FONT, 14, "")
            sub:SetTextColor(1, 1, 1, 0.45)
            PP.Point(sub, "TOP", title, "BOTTOM", 0, -8)
            sub:SetWidth(POPUP_W - 60)
            sub:SetJustifyH("CENTER")
            sub:SetWordWrap(true)
            popup._subtitle = sub

            -- Check All / Uncheck All as plain text links
            local LINK_Y = -103
            local LINK_GAP = 20

            local checkAllBtn = CreateFrame("Button", nil, popup)
            checkAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            local checkAllLbl = checkAllBtn:CreateFontString(nil, "OVERLAY")
            checkAllLbl:SetFont(FONT, 14, "")
            checkAllLbl:SetText("Check All")
            checkAllLbl:SetTextColor(1, 1, 1, 0.45)
            checkAllLbl:SetPoint("CENTER")
            checkAllBtn:SetSize(checkAllLbl:GetStringWidth() + 4, 20)
            PP.Point(checkAllBtn, "TOPLEFT", popup, "TOPLEFT", CONTENT_LEFT, LINK_Y)
            checkAllBtn:SetScript("OnEnter", function() checkAllLbl:SetTextColor(1, 1, 1, 0.80) end)
            checkAllBtn:SetScript("OnLeave", function() checkAllLbl:SetTextColor(1, 1, 1, 0.45) end)
            popup._checkAll = checkAllBtn

            -- Small divider between the two links
            local linkDivider = popup:CreateTexture(nil, "OVERLAY", nil, 7)
            linkDivider:SetColorTexture(1, 1, 1, 0.18)
            if linkDivider.SetSnapToPixelGrid then linkDivider:SetSnapToPixelGrid(false); linkDivider:SetTexelSnappingBias(0) end
            PP.Point(linkDivider, "LEFT", checkAllBtn, "RIGHT", LINK_GAP / 2, 0)
            PP.Width(linkDivider, 1)
            PP.Height(linkDivider, 12)

            local uncheckAllBtn = CreateFrame("Button", nil, popup)
            uncheckAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            local uncheckAllLbl = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
            uncheckAllLbl:SetFont(FONT, 14, "")
            uncheckAllLbl:SetText("Uncheck All")
            uncheckAllLbl:SetTextColor(1, 1, 1, 0.45)
            uncheckAllLbl:SetPoint("CENTER")
            uncheckAllBtn:SetSize(uncheckAllLbl:GetStringWidth() + 4, 20)
            PP.Point(uncheckAllBtn, "LEFT", checkAllBtn, "RIGHT", LINK_GAP, 0)
            uncheckAllBtn:SetScript("OnEnter", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.80) end)
            uncheckAllBtn:SetScript("OnLeave", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.45) end)
            popup._uncheckAll = uncheckAllBtn

            -- Column container frames (dynamic count)
            popup._columns = {}
            for colIdx = 1, NUM_COLS do
                local col = CreateFrame("Frame", nil, popup)
                col:SetFrameLevel(popup:GetFrameLevel() + 1)
                local colX = CONTENT_LEFT + (colIdx - 1) * (COL_W + COL_GAP)
                PP.Point(col, "TOPLEFT", popup, "TOPLEFT", colX, -CONTENT_TOP)
                PP.Size(col, COL_W, POPUP_H - CONTENT_TOP - 80)
                col._rows = {}
                popup._columns[colIdx] = col
            end

            -- Bottom area: [Default Dropdown row] then [Done button]
            local BOTTOM_ROW_Y = 88   -- distance from popup bottom to default dropdown container
            local DEFAULT_DD_W = 280
            local DEFAULT_DD_H = 30

            -- Default Profile dropdown container (hidden by default, shown when defaultKey is provided)
            local defDDContainer = CreateFrame("Frame", nil, popup)
            defDDContainer:SetFrameLevel(popup:GetFrameLevel() + 2)
            PP.Size(defDDContainer, POPUP_W - 52, 68)
            PP.Point(defDDContainer, "BOTTOM", popup, "BOTTOM", 0, BOTTOM_ROW_Y)
            defDDContainer:Hide()
            popup._defDDContainer = defDDContainer

            -- Label (above dropdown)
            local defDDLabel = defDDContainer:CreateFontString(nil, "OVERLAY")
            defDDLabel:SetFont(FONT, 14, "")
            defDDLabel:SetTextColor(1, 1, 1, 0.45)
            PP.Point(defDDLabel, "BOTTOM", defDDContainer, "CENTER", 0, 7)
            defDDLabel:SetText("Default Profile (for non-assigned specs)")
            popup._defDDLabel = defDDLabel

            -- Dropdown button (below label, centered)
            local defDDBtn = CreateFrame("Button", nil, defDDContainer)
            defDDBtn:SetFrameLevel(defDDContainer:GetFrameLevel() + 2)
            PP.Size(defDDBtn, DEFAULT_DD_W, DEFAULT_DD_H)
            PP.Point(defDDBtn, "TOP", defDDContainer, "CENTER", 0, -7)

            local defDDBg = defDDBtn:CreateTexture(nil, "BACKGROUND")
            defDDBg:SetAllPoints()
            defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)

            -- Border textures for the default dropdown (also used for flash animation)
            local defBrdT = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdT:SetColorTexture(1, 1, 1, 0.20)
            if defBrdT.SetSnapToPixelGrid then defBrdT:SetSnapToPixelGrid(false); defBrdT:SetTexelSnappingBias(0) end
            defBrdT:SetPoint("TOPLEFT"); defBrdT:SetPoint("TOPRIGHT"); PP.Height(defBrdT, 1)
            local defBrdB = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdB:SetColorTexture(1, 1, 1, 0.20)
            if defBrdB.SetSnapToPixelGrid then defBrdB:SetSnapToPixelGrid(false); defBrdB:SetTexelSnappingBias(0) end
            defBrdB:SetPoint("BOTTOMLEFT"); defBrdB:SetPoint("BOTTOMRIGHT"); PP.Height(defBrdB, 1)
            local defBrdL = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdL:SetColorTexture(1, 1, 1, 0.20)
            if defBrdL.SetSnapToPixelGrid then defBrdL:SetSnapToPixelGrid(false); defBrdL:SetTexelSnappingBias(0) end
            defBrdL:SetPoint("TOPLEFT", defBrdT, "BOTTOMLEFT"); defBrdL:SetPoint("BOTTOMLEFT", defBrdB, "TOPLEFT"); PP.Width(defBrdL, 1)
            local defBrdR = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdR:SetColorTexture(1, 1, 1, 0.20)
            if defBrdR.SetSnapToPixelGrid then defBrdR:SetSnapToPixelGrid(false); defBrdR:SetTexelSnappingBias(0) end
            defBrdR:SetPoint("TOPRIGHT", defBrdT, "BOTTOMRIGHT"); defBrdR:SetPoint("BOTTOMRIGHT", defBrdB, "TOPRIGHT"); PP.Width(defBrdR, 1)
            popup._defBrdEdges = { defBrdT, defBrdB, defBrdL, defBrdR }

            local defDDLbl = defDDBtn:CreateFontString(nil, "OVERLAY")
            defDDLbl:SetFont(FONT, 13, "")
            defDDLbl:SetPoint("LEFT", defDDBtn, "LEFT", 12, 0)
            defDDLbl:SetTextColor(1, 1, 1, 0.50)
            popup._defDDLbl = defDDLbl

            local defArrow = MakeDropdownArrow(defDDBtn, 12, PP)
            popup._defDDBtn = defDDBtn

            -- Flash animation for error state on the default dropdown
            local defFlashFrame = CreateFrame("Frame", nil, defDDBtn)
            defFlashFrame:Hide()
            local defFlashElapsed = 0
            local DEF_FLASH_DUR = 0.7
            defFlashFrame:SetScript("OnUpdate", function(self, elapsed)
                defFlashElapsed = defFlashElapsed + elapsed
                if defFlashElapsed >= DEF_FLASH_DUR then
                    self:Hide()
                    for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.20) end
                    return
                end
                local t = defFlashElapsed / DEF_FLASH_DUR
                local lr = lerp(0.9, 1, t)
                local lg = lerp(0.15, 1, t)
                local lb = lerp(0.15, 1, t)
                local la = lerp(0.7, 0.20, t)
                for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(lr, lg, lb, la) end
            end)
            popup._flashDefaultDD = function()
                defFlashElapsed = 0
                for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(0.9, 0.15, 0.15, 0.7) end
                defFlashFrame:Show()
            end

            -- Default dropdown menu (popout list)
            local defMenu = CreateFrame("Frame", nil, UIParent)
            defMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            defMenu:SetFrameLevel(300)
            defMenu:SetClampedToScreen(true)
            defMenu:SetSize(DEFAULT_DD_W, 4)
            defMenu:SetPoint("TOPLEFT", defDDBtn, "BOTTOMLEFT", 0, -2)
            defMenu:Hide()
            local defMenuBg = defMenu:CreateTexture(nil, "BACKGROUND")
            defMenuBg:SetAllPoints()
            defMenuBg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
            local dmT = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmT:SetColorTexture(1,1,1,0.20)
            if dmT.SetSnapToPixelGrid then dmT:SetSnapToPixelGrid(false); dmT:SetTexelSnappingBias(0) end
            dmT:SetPoint("TOPLEFT"); dmT:SetPoint("TOPRIGHT"); PP.Height(dmT, 1)
            local dmB = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmB:SetColorTexture(1,1,1,0.20)
            if dmB.SetSnapToPixelGrid then dmB:SetSnapToPixelGrid(false); dmB:SetTexelSnappingBias(0) end
            dmB:SetPoint("BOTTOMLEFT"); dmB:SetPoint("BOTTOMRIGHT"); PP.Height(dmB, 1)
            local dmL = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmL:SetColorTexture(1,1,1,0.20)
            if dmL.SetSnapToPixelGrid then dmL:SetSnapToPixelGrid(false); dmL:SetTexelSnappingBias(0) end
            dmL:SetPoint("TOPLEFT", dmT, "BOTTOMLEFT"); dmL:SetPoint("BOTTOMLEFT", dmB, "TOPLEFT"); PP.Width(dmL, 1)
            local dmR = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmR:SetColorTexture(1,1,1,0.20)
            if dmR.SetSnapToPixelGrid then dmR:SetSnapToPixelGrid(false); dmR:SetTexelSnappingBias(0) end
            dmR:SetPoint("TOPRIGHT", dmT, "BOTTOMRIGHT"); dmR:SetPoint("BOTTOMRIGHT", dmB, "TOPRIGHT"); PP.Width(dmR, 1)
            popup._defMenu = defMenu
            popup._defMenuItems = {}

            defDDBtn:SetScript("OnEnter", function()
                defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
                defDDLbl:SetTextColor(1, 1, 1, 0.60)
                for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.30) end
            end)
            defDDBtn:SetScript("OnLeave", function()
                if not defMenu:IsShown() then
                    defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
                    defDDLbl:SetTextColor(1, 1, 1, 0.50)
                    for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.20) end
                end
            end)
            defDDBtn:SetScript("OnClick", function()
                if defMenu:IsShown() then defMenu:Hide() else
                    if popup._rebuildDefMenu then popup._rebuildDefMenu() end
                    defMenu:Show()
                end
            end)
            defDDBtn:HookScript("OnHide", function() defMenu:Hide() end)

            defMenu:SetScript("OnShow", function(self)
                local btnScale = defDDBtn:GetEffectiveScale()
                local uiScale  = UIParent:GetEffectiveScale()
                self:SetScale(btnScale / uiScale)
                self:SetScript("OnUpdate", function(m)
                    if not defDDBtn:IsMouseOver() and not m:IsMouseOver() then
                        if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                    end
                end)
            end)
            defMenu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                if defDDBtn:IsMouseOver() then
                    defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
                    defDDLbl:SetTextColor(1, 1, 1, 0.60)
                    for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.30) end
                else
                    defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
                    defDDLbl:SetTextColor(1, 1, 1, 0.50)
                    for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.20) end
                end
            end)

            -- Done button (pixel-perfect via PixelUtil)
            local EG = ELLESMERE_GREEN
            local closeBtn = CreateFrame("Button", nil, popup)
            closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            PP.Size(closeBtn, 200, 39)
            PP.Point(closeBtn, "BOTTOM", popup, "BOTTOM", 0, 38)
            -- Border texture (full size, peeks out as 1px border)
            local closeBrd = closeBtn:CreateTexture(nil, "BACKGROUND")
            closeBrd:SetAllPoints()
            closeBrd:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
            PP.DisablePixelSnap(closeBrd)
            -- Fill texture (inset 1px on each side)
            local closeFill = closeBtn:CreateTexture(nil, "BORDER")
            PP.Point(closeFill, "TOPLEFT", closeBtn, "TOPLEFT", 1, -1)
            PP.Point(closeFill, "BOTTOMRIGHT", closeBtn, "BOTTOMRIGHT", -1, 1)
            closeFill:SetColorTexture(0.06, 0.08, 0.10, 0.92)
            PP.DisablePixelSnap(closeFill)
            local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
            closeLbl:SetFont(FONT, 16, "")
            closeLbl:SetPoint("CENTER")
            closeLbl:SetText("Done")
            closeLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            closeBtn:SetScript("OnEnter", function()
                closeLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
                closeBrd:SetColorTexture(EG.r, EG.g, EG.b, 1)
            end)
            closeBtn:SetScript("OnLeave", function()
                closeLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
                closeBrd:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
            end)
            popup._closeBtn = closeBtn

            -- Popup eats mouse events so clicks on it don't propagate to dimmer
            popup:EnableMouse(true)

            -- Dimmer click to close (only fires when clicking outside the popup)
            dimmer:SetScript("OnMouseDown", function(self)
                -- Only close if the click is NOT on the popup
                if not popup:IsMouseOver() then
                    self:Hide()
                end
            end)

            -- Escape to close
            popup:EnableKeyboard(true)
            popup:SetScript("OnKeyDown", function(self, key)
                if key == "ESCAPE" then
                    self:SetPropagateKeyboardInput(false)
                    dimmer:Hide()
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)

            -- Store layout constants for reuse in populate phase
            popup._CLASS_H = CLASS_H
            popup._CLASS_PAD_TOP = CLASS_PAD_TOP
            popup._CLASS_PAD_BOT = CLASS_PAD_BOT
            popup._SPEC_H  = SPEC_H
            popup._COL_W   = COL_W
            popup._CLASS_GAP = CLASS_GAP
            popup._dimmer = dimmer
            specPopup = popup
        end

        -- Update title with preset name
        local presetName
        if presetKey == "custom" then presetName = "Custom"
        elseif presetKey == "ellesmereui" then presetName = "EllesmereUI"
        elseif presetKey == "spinthewheel" then presetName = "Spin the Wheel"
        elseif presetKey:sub(1, 5) == "user:" then presetName = presetKey:sub(6)
        else presetName = presetKey end
        specPopup._title:SetText("Assign Preset to Specs")
        specPopup._subtitle:SetText("Select which specs you want " .. presetName .. " to be assigned to")

        -- Populate columns
        local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
        local CLASS_H = specPopup._CLASS_H
        local CLASS_PAD_TOP = specPopup._CLASS_PAD_TOP
        local CLASS_PAD_BOT = specPopup._CLASS_PAD_BOT
        local SPEC_H  = specPopup._SPEC_H
        local COL_W   = specPopup._COL_W
        local CLASS_GAP = specPopup._CLASS_GAP
        local allCheckboxes = {}
        local BOX_SZ = 18
        local CHECK_INSET = 3

        -- Build lookup: specID → presetKey for specs assigned to OTHER presets
        local lockedSpecs = {}  -- [specID] = displayName of the preset that owns it
        do
            local fullMap = db[dbKey]
            if fullMap then
                for pKey, specList in pairs(fullMap) do
                    if pKey ~= presetKey and type(specList) == "table" then
                        for sID in pairs(specList) do
                            -- Resolve display name
                            local dName
                            if pKey == "custom" then dName = "Custom"
                            elseif pKey == "ellesmereui" then dName = "EllesmereUI"
                            elseif pKey == "spinthewheel" then dName = "Spin the Wheel"
                            elseif pKey:sub(1, 5) == "user:" then dName = pKey:sub(6)
                            else dName = pKey end
                            lockedSpecs[sID] = dName
                        end
                    end
                end
            end
        end

        for colIdx = 1, NUM_COLS do
            local col = specPopup._columns[colIdx]
            -- Hide old rows
            for _, row in ipairs(col._rows) do row:Hide() end

            local list = COL_LISTS[colIdx]
            local rowIdx = 0
            local yOff = 0
            local isFirstClass = true

            for _, classIdx in ipairs(list) do
                local cls = SPEC_DATA[classIdx]

                -- Add CLASS_GAP between class groups (not before the first)
                if not isFirstClass then
                    yOff = yOff + CLASS_GAP
                end
                isFirstClass = false

                -- Class header
                yOff = yOff + CLASS_PAD_TOP
                rowIdx = rowIdx + 1
                local hdr = col._rows[rowIdx]
                if not hdr then
                    hdr = CreateFrame("Frame", nil, col)
                    col._rows[rowIdx] = hdr
                end
                PP.Size(hdr, COL_W, CLASS_H)
                hdr:ClearAllPoints()
                PP.Point(hdr, "TOPLEFT", col, "TOPLEFT", 0, -yOff)
                hdr:Show()

                if not hdr._label then
                    hdr._label = hdr:CreateFontString(nil, "OVERLAY")
                    hdr._label:SetFont(FONT, 18, "")
                    PP.Point(hdr._label, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 4, 4)
                end
                local clr = CLASS_COLOR_MAP[cls.class]
                if clr then
                    hdr._label:SetTextColor(clr.r, clr.g, clr.b, 0.9)
                else
                    hdr._label:SetTextColor(1, 1, 1, 0.7)
                end
                hdr._label:SetText(cls.name)
                yOff = yOff + CLASS_H + CLASS_PAD_BOT

                -- Spec checkboxes
                for _, spec in ipairs(cls.specs) do
                    rowIdx = rowIdx + 1
                    local row = col._rows[rowIdx]
                    if not row then
                        row = CreateFrame("Button", nil, col)
                        col._rows[rowIdx] = row

                        -- Checkbox box (frame, not texture, so MakeBorder works)
                        local box = CreateFrame("Frame", nil, row)
                        PP.Size(box, BOX_SZ, BOX_SZ)
                        PP.Point(box, "LEFT", row, "LEFT", 8, 0)
                        box:SetFrameLevel(row:GetFrameLevel() + 1)
                        -- Box background
                        local boxBg = box:CreateTexture(nil, "BACKGROUND")
                        boxBg:SetAllPoints()
                        boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                        PP.DisablePixelSnap(boxBg)
                        row._boxBg = boxBg
                        -- Box border (uses same pattern as WidgetFactory:Checkbox)
                        local boxBorder = MakeBorder(box, BORDER_R, BORDER_G, BORDER_B, CB_BRD_A, PP)
                        row._boxBorder = boxBorder
                        -- Checkmark: solid teal inner square (inset 3px)
                        local check = box:CreateTexture(nil, "ARTWORK")
                        PP.DisablePixelSnap(check)
                        PP.Point(check, "TOPLEFT", box, "TOPLEFT", CHECK_INSET, -CHECK_INSET)
                        PP.Point(check, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECK_INSET, CHECK_INSET)
                        check:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
                        row._check = check
                        row._box = box

                        -- Label
                        local lbl = row:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT, 17, "")
                        PP.Point(lbl, "LEFT", box, "RIGHT", 8, 0)
                        lbl:SetTextColor(1, 1, 1, 0.65)
                        row._lbl = lbl
                    end
                    PP.Size(row, COL_W, SPEC_H)
                    row:ClearAllPoints()
                    PP.Point(row, "TOPLEFT", col, "TOPLEFT", 0, -yOff)
                    row:Show()

                    row._lbl:SetText(spec.name)
                    row._specID = spec.id

                    -- Check if this spec is locked (assigned to another preset)
                    local lockedBy = lockedSpecs[spec.id]
                    row._locked = lockedBy ~= nil

                    -- Set checked state from current assignments
                    local checked = assignments[spec.id] == true
                    row._checked = checked
                    local EG = ELLESMERE_GREEN
                    local function UpdateVisual(r)
                        if r._locked then
                            -- Locked: dimmed checkbox, no checkmark
                            r._check:Hide()
                            r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A * 0.4)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 0.35)
                            r._lbl:SetTextColor(1, 1, 1, 0.25)
                        elseif r._checked then
                            r._check:Show()
                            r._boxBorder:SetColor(EG.r, EG.g, EG.b, CB_ACT_BRD_A)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                            r._lbl:SetTextColor(1, 1, 1, 0.65)
                        else
                            r._check:Hide()
                            r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                            r._lbl:SetTextColor(1, 1, 1, 0.65)
                        end
                    end
                    UpdateVisual(row)
                    allCheckboxes[#allCheckboxes + 1] = row

                    row:SetScript("OnClick", function(self)
                        if self._locked then return end
                        self._checked = not self._checked
                        assignments[spec.id] = self._checked or nil
                        UpdateVisual(self)
                    end)
                    row:SetScript("OnEnter", function(self)
                        if self._locked then return end
                        self._lbl:SetTextColor(1, 1, 1, 0.90)
                    end)
                    row:SetScript("OnLeave", function(self)
                        if self._locked then return end
                        self._lbl:SetTextColor(1, 1, 1, 0.65)
                    end)

                    yOff = yOff + SPEC_H
                end
            end
        end

        -- Check All / Uncheck All wiring (skip locked specs)
        specPopup._checkAll:SetScript("OnClick", function()
            local EG2 = ELLESMERE_GREEN
            for _, row in ipairs(allCheckboxes) do
                if not row._locked then
                    row._checked = true
                    assignments[row._specID] = true
                    row._check:Show()
                    row._boxBorder:SetColor(EG2.r, EG2.g, EG2.b, CB_ACT_BRD_A)
                end
            end
        end)
        specPopup._uncheckAll:SetScript("OnClick", function()
            for _, row in ipairs(allCheckboxes) do
                if not row._locked then
                    row._checked = false
                    assignments[row._specID] = nil
                    row._check:Hide()
                    row._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                end
            end
        end)

        ---------------------------------------------------------------
        --  Default Profile dropdown  (populate phase)
        --  Only shown when defaultKey is provided (spec feature enabled)
        ---------------------------------------------------------------
        local selectedDefaultKey = defaultKey and db[defaultKey] or nil

        if defaultKey and allPresetKeysFn then
            specPopup._defDDContainer:Show()

            -- Set initial label
            local function DefPresetDisplayName(key)
                if not key then return "" end
                if key == "custom" then return "Custom" end
                if key == "ellesmereui" then return "EllesmereUI" end
                if key == "spinthewheel" then return "Spin the Wheel" end
                if key:sub(1, 5) == "user:" then return key:sub(6) end
                return key
            end

            if selectedDefaultKey then
                specPopup._defDDLbl:SetText(DefPresetDisplayName(selectedDefaultKey))
                specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.50)
            else
                specPopup._defDDLbl:SetText("")
                specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.35)
            end

            -- Rebuild the default dropdown menu items
            specPopup._rebuildDefMenu = function()
                local items = specPopup._defMenuItems
                for _, itm in ipairs(items) do itm:Hide() end

                local presetList = allPresetKeysFn()
                local mH = 4
                local ITEM_FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")

                for idx, entry in ipairs(presetList) do
                    local itm = items[idx]
                    if not itm then
                        itm = CreateFrame("Button", nil, specPopup._defMenu)
                        itm:SetHeight(26)
                        itm:SetFrameLevel(specPopup._defMenu:GetFrameLevel() + 1)
                        local lbl = itm:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(ITEM_FONT, 13, "")
                        lbl:SetPoint("LEFT", itm, "LEFT", 10, 0)
                        lbl:SetTextColor(0.55, 0.60, 0.65, 1)
                        itm._lbl = lbl
                        local hl = itm:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints()
                        hl:SetColorTexture(1, 1, 1, 1)
                        hl:SetAlpha(0)
                        itm._hl = hl
                        itm:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 1); hl:SetAlpha(0.08) end)
                        itm:SetScript("OnLeave", function()
                            local isSel = (itm._key == selectedDefaultKey)
                            lbl:SetTextColor(0.55, 0.60, 0.65, 1)
                            hl:SetAlpha(isSel and 0.04 or 0)
                        end)
                        items[idx] = itm
                    end
                    itm:SetPoint("TOPLEFT", specPopup._defMenu, "TOPLEFT", 1, -mH)
                    itm:SetPoint("TOPRIGHT", specPopup._defMenu, "TOPRIGHT", -1, -mH)
                    itm._lbl:SetText(entry.name)
                    itm._key = entry.key
                    local isSel = (entry.key == selectedDefaultKey)
                    itm._hl:SetAlpha(isSel and 0.04 or 0)
                    itm:SetScript("OnClick", function()
                        selectedDefaultKey = entry.key
                        specPopup._defDDLbl:SetText(entry.name)
                        specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.50)
                        specPopup._defMenu:Hide()
                    end)
                    itm:Show()
                    mH = mH + 26
                end
                specPopup._defMenu:SetHeight(mH + 4)
            end
        else
            specPopup._defDDContainer:Hide()
        end

        -- Done button: validate default selection if spec feature is active
        specPopup._closeBtn:SetScript("OnClick", function()
            -- If default feature is active and no default has been selected, flash error
            if defaultKey and allPresetKeysFn and not selectedDefaultKey then
                specPopup._flashDefaultDD()
                return
            end
            -- Save the default preset choice
            if defaultKey and selectedDefaultKey then
                db[defaultKey] = selectedDefaultKey
                if onDefaultChanged then onDefaultChanged() end
            end
            specPopup._dimmer:Hide()
            -- Apply the correct preset for the player's current spec immediately
            if onDone then onDone() end
        end)

        specPopup._dimmer:Show()
    end
end


-------------------------------------------------------------------------------
--  SPEC AUTO-SWITCH EVENT HANDLER
--
--  Listens for PLAYER_SPECIALIZATION_CHANGED and auto-loads the assigned
--  preset for the current spec.  Each registered preset system (by dbPrefix)
--  is checked independently.
-------------------------------------------------------------------------------
do
    local specSwitchFrame = CreateFrame("Frame")
    specSwitchFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    -- Registry: { { dbFunc, dbPrefix, presetKeys, defaults, refreshFn, applySnapshot, applyDefaults } }
    EllesmereUI._specSwitchRegistry = EllesmereUI._specSwitchRegistry or {}

    function EllesmereUI:RegisterSpecAutoSwitch(cfg)
        local entry = {
            dbFunc     = cfg.dbFunc,
            pfx        = cfg.dbPrefix or "",
            presetKeys = cfg.presetKeys,
            defaults   = cfg.defaults,
            refreshFn  = cfg.refreshFn,
        }
        -- Avoid duplicate registrations for the same prefix
        for i, e in ipairs(self._specSwitchRegistry) do
            if e.pfx == entry.pfx and e.dbFunc == entry.dbFunc then
                self._specSwitchRegistry[i] = entry
                return
            end
        end
        self._specSwitchRegistry[#self._specSwitchRegistry + 1] = entry
    end

    specSwitchFrame:SetScript("OnEvent", function(self, event, unit)
        if event ~= "PLAYER_SPECIALIZATION_CHANGED" then return end
        if unit ~= "player" then return end

        local specID = GetSpecializationInfo(GetSpecialization() or 0)
        if not specID then return end

        -- Helper: apply a preset key to the DB
        local function ApplyPresetKey(entry, db, presetKey)
            local K_PRESETS = entry.pfx .. "_presets"
            local K_SNAP    = entry.pfx .. "_builtinSnapshot"
            local K_CUSTOM  = entry.pfx .. "_customPreset"
            if presetKey == "ellesmereui" then
                for _, key in ipairs(entry.presetKeys) do
                    local def = entry.defaults[key]
                    if type(def) == "table" and def.r then
                        db[key] = { r = def.r, g = def.g, b = def.b }
                    else
                        db[key] = def
                    end
                end
                db[K_SNAP] = nil  -- will be re-snapped on UI open
            elseif presetKey == "custom" then
                if db[K_CUSTOM] then
                    for _, key in ipairs(entry.presetKeys) do
                        local v = db[K_CUSTOM][key]
                        if v ~= nil then
                            if type(v) == "table" and v.r then
                                db[key] = { r = v.r, g = v.g, b = v.b }
                            else
                                db[key] = v
                            end
                        else
                            db[key] = nil
                        end
                    end
                end
            elseif presetKey == "spinthewheel" then
                -- Spin the Wheel is randomized -- just mark it active, snapshot on UI open
                db[K_SNAP] = nil
            elseif presetKey:sub(1, 5) == "user:" then
                local name = presetKey:sub(6)
                local snap = db[K_PRESETS] and db[K_PRESETS][name]
                if snap then
                    for _, key in ipairs(entry.presetKeys) do
                        local v = snap[key]
                        if v ~= nil then
                            if type(v) == "table" and v.r then
                                db[key] = { r = v.r, g = v.g, b = v.b }
                            else
                                db[key] = v
                            end
                        else
                            db[key] = nil
                        end
                    end
                end
            end
            db[K_SNAP] = nil
        end

        for _, entry in ipairs(EllesmereUI._specSwitchRegistry) do
            local db = entry.dbFunc()
            if db then
                local K_SPEC_ASSIGN  = entry.pfx .. "_specAssignments"
                local K_ACTIVE       = entry.pfx .. "_activePreset"
                local K_SPEC_DEFAULT = entry.pfx .. "_specDefaultPreset"
                local specMap = db[K_SPEC_ASSIGN]

                -- Check if ANY spec assignments exist at all (to know if this system is active)
                local hasAnyAssignment = false
                if specMap then
                    for _, specList in pairs(specMap) do
                        if next(specList) then hasAnyAssignment = true; break end
                    end
                end

                if hasAnyAssignment then
                    -- Find which preset has this specID assigned
                    local foundMatch = false
                    for presetKey, specList in pairs(specMap) do
                        if specList[specID] then
                            foundMatch = true
                            local currentActive = db[K_ACTIVE] or "ellesmereui"
                            if currentActive ~= presetKey then
                                db[K_ACTIVE] = presetKey
                                ApplyPresetKey(entry, db, presetKey)
                                if entry.refreshFn then entry.refreshFn() end
                            end
                            break  -- first matching preset wins
                        end
                    end
                    -- No spec-specific assignment found -- fall back to default preset
                    if not foundMatch and db[K_SPEC_DEFAULT] then
                        local defaultPreset = db[K_SPEC_DEFAULT]
                        local currentActive = db[K_ACTIVE] or "ellesmereui"
                        if currentActive ~= defaultPreset then
                            db[K_ACTIVE] = defaultPreset
                            ApplyPresetKey(entry, db, defaultPreset)
                            if entry.refreshFn then entry.refreshFn() end
                        end
                    end
                end
                -- If no spec assignments exist at all, do nothing (standard behavior)
            end
        end
        -- If the options panel is open, refresh it to reflect the new active preset
        if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
            EllesmereUI:InvalidatePageCache()
            EllesmereUI:RefreshPage(true)
        end
    end)
end


-------------------------------------------------------------------------------
--  PRESET SYSTEM  (shared by all modules)
--
--  Usage:
--    local checkDrift = EllesmereUI:BuildPresetSystem({
--        presetKeys  = { "key1", "key2", ... },
--        dbFunc      = function() return MyAddonDB end,
--        dbValFunc   = function(key) ... end,   -- read with fallback to defaults
--        defaults    = myDefaults,
--        dbPrefix    = ""  or "_color",
--        randomizeFn = function(db) ... end,
--        refreshFn   = function() ... end,
--        headerParent = frame,       -- for content-header mode
--        inlineParent = frame,       -- for inline (scroll area) mode
--        yOffset      = 0,           -- inline Y offset
--        titleText    = "Presets",   -- optional label
--    })
--  Returns: checkDrift function (+ rowH when inlineParent is set)
--  Hook checkDrift into widget callbacks to auto-detect setting changes.
-------------------------------------------------------------------------------
function EllesmereUI:BuildPresetSystem(cfg)
    -- Lazy-resolve Widget helpers (Widgets may have been deferred)
    if not MakeStyledButton then
        MakeStyledButton    = EllesmereUI.MakeStyledButton
        WB_COLOURS          = EllesmereUI.WB_COLOURS
        RB_COLOURS          = EllesmereUI.RB_COLOURS
        DDText              = EllesmereUI.DDText
        BuildDropdownMenu   = EllesmereUI.BuildDropdownMenu
        WireDropdownScripts = EllesmereUI.WireDropdownScripts
        WD_DD_COLOURS       = EllesmereUI.WD_DD_COLOURS
        RD_DD_COLOURS       = EllesmereUI.RD_DD_COLOURS
        BuildSliderCore     = EllesmereUI.BuildSliderCore
        BuildDropdownControl = EllesmereUI.BuildDropdownControl
    end
    local headerParent = cfg.headerParent
    local inlineParent = cfg.inlineParent
    local inlineY      = cfg.yOffset or 0
    local presetKeys   = cfg.presetKeys
    local pfx          = cfg.dbPrefix or ""
    local isInline     = (inlineParent ~= nil)
    local DDS = EllesmereUI.DD_STYLE or {}

    -- Module-provided DB accessors
    local DBFunc   = cfg.dbFunc
    local DBValFn  = cfg.dbValFunc
    local defaults = cfg.defaults

    -- Inline mode: create a widget row frame in the scroll area
    local rowFrame, rowH
    local anchorParent = headerParent
    if isInline then
        local CP = EllesmereUI.CONTENT_PAD or 45
        local BTN_H_INLINE = 30
        rowH = 15 + BTN_H_INLINE + 15  -- topPad + button + bottomPad
        rowFrame = CreateFrame("Frame", nil, inlineParent)
        PP.Size(rowFrame, inlineParent:GetWidth() - CP * 2, rowH)
        PP.Point(rowFrame, "TOPLEFT", inlineParent, "TOPLEFT", CP, inlineY)
        anchorParent = rowFrame
    end

    local PRESET_W, PRESET_H = 210, 30
    local ACTION_BTN_W = 110                   -- width for Save / Assign buttons
    local ACTION_BTN_GAP = 8                   -- gap between the two action buttons
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")

    -- DB key helpers using prefix
    local K_PRESETS   = pfx .. "_presets"
    local K_ORDER     = pfx .. "_presetOrder"
    local K_CUSTOM    = pfx .. "_customPreset"
    local K_ACTIVE    = pfx .. "_activePreset"
    local K_SNAP      = pfx .. "_builtinSnapshot"
    local K_SPEC_ASSIGN = pfx .. "_specAssignments"
    local K_SPEC_DEFAULT = pfx .. "_specDefaultPreset"

    -- Deep-copy a color table
    local function CopyColor(c) return { r = c.r, g = c.g, b = c.b } end

    local function SnapshotSettings(reuseTable)
        local snap = reuseTable or {}
        for _, key in ipairs(presetKeys) do
            local v = DBValFn(key)
            if type(v) == "table" and v.r then
                local existing = snap[key]
                if existing and type(existing) == "table" then
                    existing.r, existing.g, existing.b = v.r, v.g, v.b
                else
                    snap[key] = CopyColor(v)
                end
            else
                snap[key] = v
            end
        end
        return snap
    end

    local function ApplySnapshot(snap)
        local db = DBFunc()
        for _, key in ipairs(presetKeys) do
            if snap[key] ~= nil then
                local v = snap[key]
                if type(v) == "table" and v.r then
                    db[key] = CopyColor(v)
                else
                    db[key] = v
                end
            else
                db[key] = nil
            end
        end
    end

    local function ApplyDefaults()
        local db = DBFunc()
        for _, key in ipairs(presetKeys) do
            local def = defaults[key]
            if type(def) == "table" and def.r then
                db[key] = { r = def.r, g = def.g, b = def.b }
            else
                db[key] = def
            end
        end
    end

    -- Shared state that must survive RefreshPage(true) rebuilds.
    -- RefreshPage(true) destroys and re-runs BuildPresetSystem, creating new
    -- closure locals.  If a popup callback still references the OLD closure's
    -- applyingPreset / driftPopupPending, the NEW CheckDrift won't see them.
    -- Storing on a per-prefix table on EllesmereUI makes the state durable.
    if not EllesmereUI._presetState then EllesmereUI._presetState = {} end
    if not EllesmereUI._presetState[pfx] then
        EllesmereUI._presetState[pfx] = { applying = false, popupPending = false }
    end
    local pState = EllesmereUI._presetState[pfx]

    local db = DBFunc()
    if not db[K_PRESETS] then db[K_PRESETS] = {} end
    if not db[K_ORDER]   then db[K_ORDER]   = {} end

    -- Returns true if any preset in specAssignments has at least one spec checked
    local function HasAnySpecAssignment()
        local specMap = db[K_SPEC_ASSIGN]
        if not specMap then return false end
        for _, specList in pairs(specMap) do
            if next(specList) then return true end
        end
        return false
    end

    -- Returns the preset key that SHOULD be active for the current spec, or nil
    local function GetSpecActiveKey()
        if not cfg.enableSpecFeature then return nil end
        if not HasAnySpecAssignment() then return nil end
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID  = specIdx and specIdx > 0 and GetSpecializationInfo(specIdx) or nil
        if not specID then return nil end
        local specMap = db[K_SPEC_ASSIGN]
        if specMap then
            for pKey, specList in pairs(specMap) do
                if specList[specID] then return pKey end
            end
        end
        -- No direct match -- fall back to default
        if db[K_SPEC_DEFAULT] then return db[K_SPEC_DEFAULT] end
        return nil
    end

    local function ApplyAndRefresh()
        local specKey = GetSpecActiveKey()
        if specKey and activePresetKey ~= specKey then
            -- User is browsing a different preset -- DB currently has the browsed
            -- preset's values (written by DoApply).  Update preview + widgets with
            -- those values, then silently restore the spec-active snapshot to DB
            -- and refresh only real nameplates.
            if cfg.previewRefreshFn then cfg.previewRefreshFn() end
            EllesmereUI:RefreshPage()
            -- Re-apply spec-active snapshot to DB so real nameplates stay correct
            if specKey == "ellesmereui" then
                ApplyDefaults()
            elseif specKey == "custom" then
                if db[K_CUSTOM] then ApplySnapshot(db[K_CUSTOM]) end
            elseif specKey:sub(1, 5) == "user:" then
                local name = specKey:sub(6)
                if db[K_PRESETS] and db[K_PRESETS][name] then ApplySnapshot(db[K_PRESETS][name]) end
            end
            -- Refresh only real nameplates (not the preview which already shows the browsed preset)
            if cfg.plateRefreshFn then cfg.plateRefreshFn() end
        else
            -- Normal case: no spec override, or user selected the spec-active preset
            if cfg.refreshFn then cfg.refreshFn() end
            EllesmereUI:RefreshPage()
        end
    end

    local builtinPresets = { "ellesmereui", "spinthewheel" }
    local builtinNames   = { ellesmereui = "EllesmereUI", spinthewheel = "Spin the Wheel" }

    local activePresetKey = db[K_ACTIVE] or "ellesmereui"

    -----------------------------------------------------------
    --  Title
    -----------------------------------------------------------
    local titleLabel
    if cfg.titleText then
        titleLabel = anchorParent:CreateFontString(nil, "OVERLAY")
        titleLabel:SetFont(FONT, 12, "")
        titleLabel:SetTextColor(0.45, 0.50, 0.55, 1)
        if isInline then
            titleLabel:SetPoint("TOP", anchorParent, "TOP", 0, 0)
        else
            titleLabel:SetPoint("TOP", anchorParent, "TOP", 0, -15)
        end
        titleLabel:SetText(cfg.titleText)
    end

    -----------------------------------------------------------
    --  Action button layout (computed early so dropdown can share TOTAL_W)
    -----------------------------------------------------------
    local enableSpecFeature = cfg.enableSpecFeature
    local NUM_ACTION_BTNS = enableSpecFeature and 3 or 2
    local FULL_TOTAL_W = PRESET_W + 12 + ACTION_BTN_W * NUM_ACTION_BTNS + ACTION_BTN_GAP * (NUM_ACTION_BTNS - 1)

    -----------------------------------------------------------
    --  Dropdown button
    -----------------------------------------------------------
    local ddBtn = CreateFrame("Button", nil, anchorParent)
    ddBtn:SetSize(PRESET_W, PRESET_H)
    do
        local ddY = isInline and -15 or -21
        ddBtn:SetPoint("TOPRIGHT", anchorParent, "TOP", -(FULL_TOTAL_W / 2) + PRESET_W, ddY)
    end
    ddBtn:SetFrameLevel(anchorParent:GetFrameLevel() + 10)

    local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints()
    ddBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, DDS.BG_A or 0.9)

    local function mkBrd(p)
        local t = p:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 1, 1, DDS.BRD_A or 0.20)
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        return t
    end
    local bT = mkBrd(ddBtn); bT:SetPoint("TOPLEFT"); bT:SetPoint("TOPRIGHT"); PP.Height(bT, 1)
    local bB = mkBrd(ddBtn); bB:SetPoint("BOTTOMLEFT"); bB:SetPoint("BOTTOMRIGHT"); PP.Height(bB, 1)
    local bL = mkBrd(ddBtn); bL:SetPoint("TOPLEFT", bT, "BOTTOMLEFT"); bL:SetPoint("BOTTOMLEFT", bB, "TOPLEFT"); PP.Width(bL, 1)
    local bR = mkBrd(ddBtn); bR:SetPoint("TOPRIGHT", bT, "BOTTOMRIGHT"); bR:SetPoint("BOTTOMRIGHT", bB, "TOPRIGHT"); PP.Width(bR, 1)

    local ddLabel = ddBtn:CreateFontString(nil, "OVERLAY")
    ddLabel:SetFont(FONT, 13, "")
    ddLabel:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
    ddLabel:SetTextColor(1, 1, 1, DDS.TXT_A or 0.50)

    -- "(default)" suffix label -- 2px smaller, dimmer
    local ddDefaultLabel = ddBtn:CreateFontString(nil, "OVERLAY")
    ddDefaultLabel:SetFont(FONT, 11, "")
    ddDefaultLabel:SetPoint("LEFT", ddLabel, "RIGHT", 4, 0)
    ddDefaultLabel:SetTextColor(1, 1, 1, (DDS.TXT_A or 0.50) * 0.65)
    ddDefaultLabel:SetText("(default)")

    local arrow = MakeDropdownArrow(ddBtn, 12, PP)

    local function PresetDisplayName(key)
        if key == "custom" then return "Custom" end
        if builtinNames[key] then return builtinNames[key] end
        if key and key:sub(1, 5) == "user:" then return key:sub(6) end
        return "EllesmereUI"
    end

    --- Update the dropdown label text + "(default)" / "(inactive)" suffixes
    local function SetDropdownLabelText(key)
        ddLabel:SetText(PresetDisplayName(key))
        local hasAssignments = HasAnySpecAssignment()
        local isDefault = hasAssignments and db[K_SPEC_DEFAULT] and key == db[K_SPEC_DEFAULT]
        local specKey = GetSpecActiveKey()
        local isInactive = specKey and key ~= specKey

        if isDefault and isInactive then
            ddDefaultLabel:SetText("(default - inactive)")
            ddDefaultLabel:Show()
        elseif isDefault then
            ddDefaultLabel:SetText("(default)")
            ddDefaultLabel:Show()
        elseif isInactive then
            ddDefaultLabel:SetText("(inactive)")
            ddDefaultLabel:Show()
        else
            ddDefaultLabel:Hide()
        end
    end
    -- Expose on pState so closures that survive page rebuilds can call the
    -- latest version instead of a stale upvalue captured before the rebuild.
    pState.SetDropdownLabelText = SetDropdownLabelText

    SetDropdownLabelText(activePresetKey)

    -----------------------------------------------------------
    --  Dropdown menu
    -----------------------------------------------------------
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(200)
    menu:SetClampedToScreen(true)
    menu:SetSize(PRESET_W, 4)
    menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
    menu:Hide()
    local menuBg = menu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints()
    menuBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, DDS.BG_HA or 0.98)
    local mT = mkBrd(menu); mT:SetPoint("TOPLEFT"); mT:SetPoint("TOPRIGHT"); PP.Height(mT, 1)
    local mB = mkBrd(menu); mB:SetPoint("BOTTOMLEFT"); mB:SetPoint("BOTTOMRIGHT"); PP.Height(mB, 1)
    local mL = mkBrd(menu); mL:SetPoint("TOPLEFT", mT, "BOTTOMLEFT"); mL:SetPoint("BOTTOMLEFT", mB, "TOPLEFT"); PP.Width(mL, 1)
    local mR = mkBrd(menu); mR:SetPoint("TOPRIGHT", mT, "BOTTOMRIGHT"); mR:SetPoint("BOTTOMRIGHT", mB, "TOPRIGHT"); PP.Width(mR, 1)

    local menuItems = {}
    local function MakeMenuItem(parent)
        local item = CreateFrame("Button", nil, parent)
        item:SetHeight(26)
        item:SetFrameLevel(parent:GetFrameLevel() + 1)
        local lbl = item:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT, 13, "")
        lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
        lbl:SetTextColor(0.55, 0.60, 0.65, 1)
        item._lbl = lbl
        -- "(default)" suffix for the default preset
        local defSuffix = item:CreateFontString(nil, "OVERLAY")
        defSuffix:SetFont(FONT, 11, "")
        defSuffix:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        defSuffix:SetTextColor(0.55, 0.60, 0.65, 0.65)
        defSuffix:SetText("(default)")
        defSuffix:Hide()
        item._defSuffix = defSuffix
        -- "(spec active)" suffix for the spec-assigned preset (accent color)
        local specSuffix = item:CreateFontString(nil, "OVERLAY")
        specSuffix:SetFont(FONT, 11, "")
        -- Anchor will be updated dynamically in RebuildMenu based on defSuffix visibility
        specSuffix:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        local EG = ELLESMERE_GREEN
        specSuffix:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        specSuffix:SetText("(spec active)")
        specSuffix:Hide()
        item._specSuffix = specSuffix
        local hl = item:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 1)
        hl:SetAlpha(0)
        item._hl = hl
        item._isSelected = false

        -- Icon paths
        local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
        local ICON_SIZE = 14
        local ICON_GAP = 4

        -- Delete icon (close-3.png) -- right side
        local delBtn = CreateFrame("Button", nil, item)
        delBtn:SetSize(ICON_SIZE, ICON_SIZE)
        PP.Point(delBtn, "RIGHT", item, "RIGHT", -8, 0)
        delBtn:SetFrameLevel(item:GetFrameLevel() + 2)
        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
        PP.Size(delIcon, ICON_SIZE, ICON_SIZE)
        PP.Point(delIcon, "CENTER", delBtn, "CENTER", 0, 0)
        if delIcon.SetSnapToPixelGrid then delIcon:SetSnapToPixelGrid(false); delIcon:SetTexelSnappingBias(0) end
        delIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
        delBtn:SetAlpha(0.75)
        delBtn._icon = delIcon
        delBtn:Hide()
        item._delBtn = delBtn

        -- Edit icon (edit-3.png) -- left of delete
        local editBtn = CreateFrame("Button", nil, item)
        editBtn:SetSize(ICON_SIZE, ICON_SIZE)
        PP.Point(editBtn, "RIGHT", delBtn, "LEFT", -ICON_GAP, 0)
        editBtn:SetFrameLevel(item:GetFrameLevel() + 2)
        local editIcon = editBtn:CreateTexture(nil, "OVERLAY")
        PP.Size(editIcon, ICON_SIZE, ICON_SIZE)
        PP.Point(editIcon, "CENTER", editBtn, "CENTER", 0, 0)
        if editIcon.SetSnapToPixelGrid then editIcon:SetSnapToPixelGrid(false); editIcon:SetTexelSnappingBias(0) end
        editIcon:SetTexture(MEDIA .. "icons\\eui-edit.png")
        editBtn:SetAlpha(0.75)
        editBtn._icon = editIcon
        editBtn:Hide()
        item._editBtn = editBtn

        item:SetScript("OnEnter", function()
            lbl:SetTextColor(1, 1, 1, 1)
            if delBtn:IsShown() then delBtn:SetAlpha(1) end
            if editBtn:IsShown() then editBtn:SetAlpha(1) end
            hl:SetAlpha(DDS.ITEM_HL_A or 0.08)
        end)
        item:SetScript("OnLeave", function()
            lbl:SetTextColor(0.55, 0.60, 0.65, 1)
            if delBtn:IsShown() then delBtn:SetAlpha(0.75) end
            if editBtn:IsShown() then editBtn:SetAlpha(0.75) end
            hl:SetAlpha(item._isSelected and (DDS.ITEM_SEL_A or 0.04) or 0)
        end)
        return item
    end

    local menuDivider
    local function EnsureDivider()
        if menuDivider then return menuDivider end
        menuDivider = menu:CreateTexture(nil, "ARTWORK")
        PP.Height(menuDivider, 1)
        menuDivider:SetColorTexture(1, 1, 1, 0.10)
        return menuDivider
    end

    -----------------------------------------------------------
    --  Rebuild menu
    -----------------------------------------------------------
    local function RebuildMenu()
        for _, item in ipairs(menuItems) do item:Hide() end
        if menuDivider then menuDivider:Hide() end

        local mH = 4
        local idx = 0

        -- Determine which preset is spec-active for the player's current spec
        local specActiveKey
        if enableSpecFeature and HasAnySpecAssignment() then
            local specIdx = GetSpecialization and GetSpecialization() or 0
            local specID  = specIdx and specIdx > 0 and GetSpecializationInfo(specIdx) or nil
            if specID then
                local specMap = db[K_SPEC_ASSIGN]
                if specMap then
                    for pKey, specList in pairs(specMap) do
                        if specList[specID] then specActiveKey = pKey; break end
                    end
                end
                -- Fall back to default if no direct assignment
                if not specActiveKey and db[K_SPEC_DEFAULT] then
                    specActiveKey = db[K_SPEC_DEFAULT]
                end
            end
        end

        local function AddItem(displayName, key)
            idx = idx + 1
            local item = menuItems[idx]
            if not item then
                item = MakeMenuItem(menu)
                menuItems[idx] = item
            end
            item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
            item._lbl:SetText(displayName)
            item._isSelected = (key == activePresetKey)
            item._hl:SetAlpha(item._isSelected and (DDS.ITEM_SEL_A or 0.04) or 0)

            -- Show "(default)" suffix only for the user-chosen default preset
            local showDefault = HasAnySpecAssignment() and db[K_SPEC_DEFAULT] and key == db[K_SPEC_DEFAULT]
            if showDefault then
                item._defSuffix:Show()
            else
                item._defSuffix:Hide()
            end

            -- Show "(spec active)" suffix on the preset assigned to the current spec
            -- but NOT if this item already shows "(default)" -- default takes priority
            local showSpecActive = specActiveKey and key == specActiveKey and not showDefault
            if showSpecActive then
                item._specSuffix:ClearAllPoints()
                if showDefault then
                    item._specSuffix:SetPoint("LEFT", item._defSuffix, "RIGHT", 4, 0)
                else
                    item._specSuffix:SetPoint("LEFT", item._lbl, "RIGHT", 4, 0)
                end
                item._specSuffix:Show()
            else
                item._specSuffix:Hide()
            end

            -- Show edit + delete icons for custom and user presets only
            local isDeletable = (key == "custom") or (key:sub(1, 5) == "user:")
            -- Edit is only for named user presets (not "custom" or builtins)
            local isEditable = key:sub(1, 5) == "user:"
            if isDeletable then
                item._delBtn:Show()
                item._delBtn:SetAlpha(0.75)
                item._delBtn:SetScript("OnEnter", function()
                    item._delBtn:SetAlpha(1)
                    item._lbl:SetTextColor(1, 1, 1, 1)
                    item._hl:SetAlpha(DDS.ITEM_HL_A or 0.08)
                end)
                item._delBtn:SetScript("OnLeave", function()
                    if item:IsMouseOver() then return end
                    item._delBtn:SetAlpha(0.75)
                    item._lbl:SetTextColor(0.55, 0.60, 0.65, 1)
                    item._hl:SetAlpha(item._isSelected and (DDS.ITEM_SEL_A or 0.04) or 0)
                end)
                item._delBtn:SetScript("OnClick", function()
                    menu:Hide()
                    local deleteName = displayName
                    EllesmereUI:ShowConfirmPopup({
                        title = "Delete Preset",
                        message = "Are you sure you want to delete \"" .. deleteName .. "\"?",
                        confirmText = "Delete",
                        cancelText = "Cancel",
                        onConfirm = function()
                            if key == "custom" then
                                db[K_CUSTOM] = nil
                            elseif key:sub(1, 5) == "user:" then
                                local name = key:sub(6)
                                db[K_PRESETS][name] = nil
                                for i, n in ipairs(db[K_ORDER]) do
                                    if n == name then table.remove(db[K_ORDER], i); break end
                                end
                            end
                            -- Clean up spec assignments for the deleted preset FIRST
                            -- so that label updates below see the correct state
                            if db[K_SPEC_ASSIGN] then
                                db[K_SPEC_ASSIGN][key] = nil
                                -- Purge any leftover empty sub-tables so
                                -- HasAnySpecAssignment() returns false cleanly
                                local emptyKeys = {}
                                for pKey, specList in pairs(db[K_SPEC_ASSIGN]) do
                                    if type(specList) ~= "table" or not next(specList) then
                                        emptyKeys[#emptyKeys + 1] = pKey
                                    end
                                end
                                for _, ek in ipairs(emptyKeys) do
                                    db[K_SPEC_ASSIGN][ek] = nil
                                end
                            end
                            -- If deleted preset was the default, clear the default
                            if db[K_SPEC_DEFAULT] and db[K_SPEC_DEFAULT] == key then
                                db[K_SPEC_DEFAULT] = nil
                            end
                            -- If no spec assignments remain at all, clear the default too
                            if not HasAnySpecAssignment() then
                                db[K_SPEC_DEFAULT] = nil
                            end
                            -- If the deleted preset was active, fall back to next in line
                            if activePresetKey == key then
                                pState.applying = true
                                local nextKey, nextDisplay
                                if key ~= "custom" and db[K_CUSTOM] then
                                    nextKey = "custom"
                                    nextDisplay = "Custom"
                                end
                                if not nextKey then
                                    for _, n in ipairs(db[K_ORDER]) do
                                        if db[K_PRESETS][n] then
                                            nextKey = "user:" .. n
                                            nextDisplay = n
                                            break
                                        end
                                    end
                                end
                                if nextKey then
                                    activePresetKey = nextKey
                                    db[K_ACTIVE] = nextKey
                                    SetDropdownLabelText(nextKey)
                                    if nextKey == "custom" then
                                        if db[K_CUSTOM] then ApplySnapshot(db[K_CUSTOM]) end
                                        db[K_SNAP] = nil
                                    else
                                        local n = nextKey:sub(6)
                                        if db[K_PRESETS][n] then ApplySnapshot(db[K_PRESETS][n]) end
                                        db[K_SNAP] = nil
                                    end
                                else
                                    activePresetKey = "ellesmereui"
                                    db[K_ACTIVE] = "ellesmereui"
                                    SetDropdownLabelText("ellesmereui")
                                    ApplyDefaults()
                                    db[K_SNAP] = SnapshotSettings()
                                end
                                ApplyAndRefresh()
                                pState.applying = false
                            else
                                -- Deleted preset wasn't the active one -- still need to
                                -- refresh the dropdown label in case suffixes changed
                                -- Use pState reference in case a page rebuild created
                                -- new UI elements since this closure was captured.
                                if pState.SetDropdownLabelText then
                                    pState.SetDropdownLabelText(db[K_ACTIVE] or activePresetKey)
                                end
                            end
                            if pState.UpdateSaveBtnState then pState.UpdateSaveBtnState() end
                            -- Update Set as Default button visibility (use pState to
                            -- get the latest function in case a page rebuild created
                            -- new button instances since this closure was captured)
                            if pState.UpdateDefaultBtnState then pState.UpdateDefaultBtnState() end
                        end,
                    })
                end)
            else
                item._delBtn:Hide()
            end

            -- Edit (rename) icon -- user presets only (not Custom or builtins)
            if isEditable then
                item._editBtn:Show()
                item._editBtn:SetAlpha(0.75)
                item._editBtn:SetScript("OnEnter", function()
                    item._editBtn:SetAlpha(1)
                    item._lbl:SetTextColor(1, 1, 1, 1)
                    item._hl:SetAlpha(DDS.ITEM_HL_A or 0.08)
                end)
                item._editBtn:SetScript("OnLeave", function()
                    if item:IsMouseOver() then return end
                    item._editBtn:SetAlpha(0.75)
                    item._lbl:SetTextColor(0.55, 0.60, 0.65, 1)
                    item._hl:SetAlpha(item._isSelected and (DDS.ITEM_SEL_A or 0.04) or 0)
                end)
                item._editBtn:SetScript("OnClick", function()
                    menu:Hide()
                    local oldName = key:sub(6)
                    EllesmereUI:ShowInputPopup({
                        title = "Rename Preset",
                        message = "Enter a new name for \"" .. oldName .. "\":",
                        placeholder = oldName,
                        confirmText = "Rename",
                        cancelText = "Cancel",
                        onConfirm = function(newName)
                            if newName == oldName then return end
                            -- Move snapshot to new name
                            db[K_PRESETS][newName] = db[K_PRESETS][oldName]
                            db[K_PRESETS][oldName] = nil
                            -- Update order list
                            for i, n in ipairs(db[K_ORDER]) do
                                if n == oldName then db[K_ORDER][i] = newName; break end
                            end
                            -- Update active preset key if this was active
                            local oldKey = "user:" .. oldName
                            local newKey = "user:" .. newName
                            if activePresetKey == oldKey then
                                activePresetKey = newKey
                                db[K_ACTIVE] = newKey
                                SetDropdownLabelText(newKey)
                            end
                            -- Update spec assignments if any
                            if db[K_SPEC_ASSIGN] and db[K_SPEC_ASSIGN][oldKey] then
                                db[K_SPEC_ASSIGN][newKey] = db[K_SPEC_ASSIGN][oldKey]
                                db[K_SPEC_ASSIGN][oldKey] = nil
                            end
                            -- Update default preset if this was the default
                            if db[K_SPEC_DEFAULT] and db[K_SPEC_DEFAULT] == oldKey then
                                db[K_SPEC_DEFAULT] = newKey
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    })
                end)
            else
                item._editBtn:Hide()
            end

            item:SetScript("OnClick", function()
                menu:Hide()
                local function DoApply()
                    pState.applying = true
                    activePresetKey = key
                    db[K_ACTIVE] = key
                    SetDropdownLabelText(key)
                    if key == "ellesmereui" then
                        ApplyDefaults()
                        db[K_SNAP] = SnapshotSettings()
                    elseif key == "spinthewheel" then
                        cfg.randomizeFn(DBFunc())
                        db[K_SNAP] = SnapshotSettings()
                    elseif key == "custom" then
                        if db[K_CUSTOM] then ApplySnapshot(db[K_CUSTOM]) end
                        db[K_SNAP] = nil
                    elseif key:sub(1, 5) == "user:" then
                        local name = key:sub(6)
                        if db[K_PRESETS][name] then ApplySnapshot(db[K_PRESETS][name]) end
                        db[K_SNAP] = nil
                    end
                    ApplyAndRefresh()
                    pState.applying = false
                    if UpdateSaveBtnState then UpdateSaveBtnState() end
                end
                DoApply()
            end)
            item:Show()
            mH = mH + 26
        end

        if db[K_CUSTOM] then AddItem("Custom", "custom") end
        for _, name in ipairs(db[K_ORDER]) do
            if db[K_PRESETS][name] then AddItem(name, "user:" .. name) end
        end
        local hasCustomSection = db[K_CUSTOM] or (#db[K_ORDER] > 0)
        if hasCustomSection then
            mH = mH + 6
            local div = EnsureDivider()
            div:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -mH)
            div:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -10, -mH)
            div:Show()
            mH = mH + 1 + 6
        end
        for _, key in ipairs(builtinPresets) do AddItem(builtinNames[key], key) end
        menu:SetHeight(mH + 4)
    end

    -----------------------------------------------------------
    --  Drift detection
    -----------------------------------------------------------
    local function HasSettingsDrifted()
        if activePresetKey == "custom" then return false end
        if activePresetKey and activePresetKey:sub(1, 5) == "user:" then
            local name = activePresetKey:sub(6)
            local snap = db[K_PRESETS] and db[K_PRESETS][name]
            if not snap then return true end
            for _, key in ipairs(presetKeys) do
                local cur = DBValFn(key)
                local saved = snap[key]
                if type(cur) == "table" and cur.r then
                    if not saved or math.abs(cur.r - saved.r) > 0.001 or math.abs(cur.g - saved.g) > 0.001 or math.abs(cur.b - saved.b) > 0.001 then
                        return true
                    end
                else
                    if cur ~= saved then return true end
                end
            end
            return false
        end
        local snap = db[K_SNAP]
        if snap then
            for _, key in ipairs(presetKeys) do
                local cur = DBValFn(key)
                local saved = snap[key]
                if type(cur) == "table" and cur.r then
                    if type(saved) ~= "table" or not saved.r then return true end
                    if math.abs(cur.r - saved.r) > 0.001 or math.abs(cur.g - saved.g) > 0.001 or math.abs(cur.b - saved.b) > 0.001 then
                        return true
                    end
                else
                    if cur ~= saved then return true end
                end
            end
            return false
        end
        if activePresetKey == "ellesmereui" then
            for _, key in ipairs(presetKeys) do
                local cur = DBValFn(key)
                local def = defaults[key]
                if type(cur) == "table" and cur.r then
                    if type(def) ~= "table" or not def.r then return true end
                    if math.abs(cur.r - def.r) > 0.001 or math.abs(cur.g - def.g) > 0.001 or math.abs(cur.b - def.b) > 0.001 then
                        return true
                    end
                else
                    if cur ~= def then return true end
                end
            end
            return false
        end
        return false
    end

    -- Forward-declare
    local UpdateSaveBtnState

    local function CheckDrift()
        if pState.applying then return end
        if pState.popupPending then return end
        -- Defer drift detection while Blizzard's color picker is open
        if EllesmereUI._colorPickerOpen then
            EllesmereUI._deferredDriftChecks = EllesmereUI._deferredDriftChecks or {}
            EllesmereUI._deferredDriftChecks[CheckDrift] = true
            return
        end
        -- Defer drift detection while a slider is being dragged
        if EllesmereUI._sliderDragging then
            EllesmereUI._deferredDriftChecks = EllesmereUI._deferredDriftChecks or {}
            EllesmereUI._deferredDriftChecks[CheckDrift] = true
            return
        end
        if activePresetKey == "custom" then
            db[K_CUSTOM] = SnapshotSettings(db[K_CUSTOM])
            if UpdateSaveBtnState then UpdateSaveBtnState() end
            return
        end
        if not HasSettingsDrifted() then
            if UpdateSaveBtnState then UpdateSaveBtnState() end
            return
        end
        local isBuiltin = builtinNames[activePresetKey] ~= nil
        local isUserPreset = activePresetKey and activePresetKey:sub(1, 5) == "user:"
        if isUserPreset then
            local name = activePresetKey:sub(6)
            if db[K_PRESETS][name] then db[K_PRESETS][name] = SnapshotSettings(db[K_PRESETS][name]) end
            if UpdateSaveBtnState then UpdateSaveBtnState() end
            return
        end
        if isBuiltin and db[K_CUSTOM] then
            local revertSnapshot = db[K_SNAP]
            pState.popupPending = true
            EllesmereUI:ShowConfirmPopup({
                title = "Custom Preset Exists",
                message = "You already have a Custom preset. What would you like to do with your current changes?",
                confirmText = "Save as New",
                cancelText = "Overwrite Custom",
                onConfirm = function()
                    pState.popupPending = false
                    EllesmereUI:ShowInputPopup({
                        title = "New Preset",
                        message = "Enter a name for your new preset:",
                        placeholder = "My Preset",
                        confirmText = "Save",
                        cancelText = "Cancel",
                        onConfirm = function(name)
                            db[K_PRESETS][name] = SnapshotSettings()
                            local found = false
                            for _, n in ipairs(db[K_ORDER]) do
                                if n == name then found = true; break end
                            end
                            if not found then table.insert(db[K_ORDER], 1, name) end
                            activePresetKey = "user:" .. name
                            db[K_ACTIVE] = activePresetKey
                            db[K_SNAP] = nil
                            SetDropdownLabelText(activePresetKey)
                            if UpdateSaveBtnState then UpdateSaveBtnState() end
                        end,
                        onCancel = function()
                            if revertSnapshot then ApplySnapshot(revertSnapshot) end
                            ApplyAndRefresh()
                        end,
                    })
                end,
                onCancel = function()
                    pState.popupPending = false
                    db[K_CUSTOM] = SnapshotSettings()
                    activePresetKey = "custom"
                    db[K_ACTIVE] = "custom"
                    SetDropdownLabelText("custom")
                    if UpdateSaveBtnState then UpdateSaveBtnState() end
                    EllesmereUI:RefreshPage()
                end,
                onDismiss = function()
                    pState.popupPending = false
                    if revertSnapshot then
                        pState.applying = true
                        ApplySnapshot(revertSnapshot)
                        ApplyAndRefresh()
                        pState.applying = false
                    end
                end,
            })
        else
            db[K_CUSTOM] = SnapshotSettings()
            activePresetKey = "custom"
            db[K_ACTIVE] = "custom"
            SetDropdownLabelText("custom")
            if UpdateSaveBtnState then UpdateSaveBtnState() end
        end
    end

    -----------------------------------------------------------
    --  Dropdown button scripts
    -----------------------------------------------------------
    ddBtn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() else
            RebuildMenu(); menu:Show()
        end
    end)
    ddBtn:SetScript("OnEnter", function()
        ddBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, DDS.BG_HA or 0.98)
        ddLabel:SetTextColor(1, 1, 1, DDS.TXT_HA or 0.60)
        ddDefaultLabel:SetTextColor(1, 1, 1, (DDS.TXT_HA or 0.60) * 0.65)
        for _, t in ipairs({bT, bB, bL, bR}) do t:SetColorTexture(1, 1, 1, DDS.BRD_HA or 0.30) end
    end)
    ddBtn:SetScript("OnLeave", function()
        if not menu:IsShown() then
            ddBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, DDS.BG_A or 0.9)
            ddLabel:SetTextColor(1, 1, 1, DDS.TXT_A or 0.50)
            ddDefaultLabel:SetTextColor(1, 1, 1, (DDS.TXT_A or 0.50) * 0.65)
            for _, t in ipairs({bT, bB, bL, bR}) do t:SetColorTexture(1, 1, 1, DDS.BRD_A or 0.20) end
        end
    end)
    ddBtn:HookScript("OnHide", function() menu:Hide() end)

    menu:SetScript("OnShow", function(self)
        local btnScale = ddBtn:GetEffectiveScale()
        local uiScale  = UIParent:GetEffectiveScale()
        self:SetScale(btnScale / uiScale)
        self:SetScript("OnUpdate", function(m)
            if not ddBtn:IsMouseOver() and not m:IsMouseOver() then
                if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide(); return end
            end
            -- Close when the bottom edge of the dropdown button leaves the visible scroll area
            -- Only applies when the dropdown is inline (inside the scroll child)
            if isInline then
                local sf = EllesmereUI:GetScrollFrame()
                if sf then
                    local sfTop = sf:GetTop()
                    local sfBot = sf:GetBottom()
                    local btnBot = ddBtn:GetBottom()
                    if sfTop and sfBot and btnBot then
                        if btnBot < sfBot or btnBot > sfTop then m:Hide() end
                    end
                end
            end
        end)
    end)
    menu:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if ddBtn:IsMouseOver() then
            ddBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, DDS.BG_HA or 0.98)
            ddLabel:SetTextColor(1, 1, 1, DDS.TXT_HA or 0.60)
            ddDefaultLabel:SetTextColor(1, 1, 1, (DDS.TXT_HA or 0.60) * 0.65)
            for _, t in ipairs({bT, bB, bL, bR}) do t:SetColorTexture(1, 1, 1, DDS.BRD_HA or 0.30) end
        else
            ddBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, DDS.BG_A or 0.9)
            ddLabel:SetTextColor(1, 1, 1, DDS.TXT_A or 0.50)
            ddDefaultLabel:SetTextColor(1, 1, 1, (DDS.TXT_A or 0.50) * 0.65)
            for _, t in ipairs({bT, bB, bL, bR}) do t:SetColorTexture(1, 1, 1, DDS.BRD_A or 0.20) end
        end
    end)

    -- Take initial builtin snapshot if needed
    if builtinNames[activePresetKey] and not db[K_SNAP] then
        db[K_SNAP] = SnapshotSettings()
    end
    CheckDrift()

    -----------------------------------------------------------
    --  Action buttons
    --  When spec features are enabled (cfg.enableSpecFeature):
    --    [Dropdown 210] [12px] [Save 110] [8px] [Set Default 110] [8px] [Assign 110]
    --  Otherwise (e.g. colors tab):
    --    [Dropdown 210] [12px] [Save 110] [8px] [Assign 110]
    -----------------------------------------------------------
    local btnY = isInline and -15 or -21

    -- Helper: compute X offset for the Nth action button (1-based, after the dropdown)
    local function ActionBtnX(n)
        return -(FULL_TOTAL_W / 2) + PRESET_W + 12 + (n - 1) * (ACTION_BTN_W + ACTION_BTN_GAP)
    end

    -- Dynamically recenter dropdown + action buttons based on which are visible.
    -- Called whenever button visibility changes (e.g. Set as Default hides/shows).
    local actionButtons = {}  -- populated after buttons are created
    local function RecenterButtons()
        local visCount = 0
        for _, btn in ipairs(actionButtons) do
            if btn:IsShown() then visCount = visCount + 1 end
        end
        if visCount == 0 then visCount = 1 end  -- at minimum Save is always visible
        local totalW = PRESET_W + 12 + ACTION_BTN_W * visCount + ACTION_BTN_GAP * (visCount - 1)
        -- Reposition dropdown
        local ddY = isInline and -15 or -21
        ddBtn:ClearAllPoints()
        ddBtn:SetPoint("TOPRIGHT", anchorParent, "TOP", -(totalW / 2) + PRESET_W, ddY)
        -- Reposition visible action buttons sequentially
        local idx = 0
        for _, btn in ipairs(actionButtons) do
            if btn:IsShown() then
                idx = idx + 1
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", anchorParent, "TOP",
                    -(totalW / 2) + PRESET_W + 12 + (idx - 1) * (ACTION_BTN_W + ACTION_BTN_GAP), btnY)
            end
        end
    end

    -----------------------------------------------------------
    --  Add New Preset button  (1st action button)
    -----------------------------------------------------------
    local SAVE_BTN_W, SAVE_BTN_H = ACTION_BTN_W, PRESET_H
    local saveBtn = CreateFrame("Button", nil, anchorParent)
    saveBtn:SetSize(SAVE_BTN_W, SAVE_BTN_H)
    saveBtn:SetPoint("TOPLEFT", anchorParent, "TOP", ActionBtnX(1), btnY)
    saveBtn:SetFrameLevel(anchorParent:GetFrameLevel() + 10)

    local saveBg = saveBtn:CreateTexture(nil, "BACKGROUND")
    saveBg:SetAllPoints()
    saveBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.6)

    local sbT = mkBrd(saveBtn); sbT:SetPoint("TOPLEFT"); sbT:SetPoint("TOPRIGHT"); PP.Height(sbT, 1)
    local sbB = mkBrd(saveBtn); sbB:SetPoint("BOTTOMLEFT"); sbB:SetPoint("BOTTOMRIGHT"); PP.Height(sbB, 1)
    local sbL = mkBrd(saveBtn); sbL:SetPoint("TOPLEFT", sbT, "BOTTOMLEFT"); sbL:SetPoint("BOTTOMLEFT", sbB, "TOPLEFT"); PP.Width(sbL, 1)
    local sbR = mkBrd(saveBtn); sbR:SetPoint("TOPRIGHT", sbT, "BOTTOMRIGHT"); sbR:SetPoint("BOTTOMRIGHT", sbB, "TOPRIGHT"); PP.Width(sbR, 1)

    local saveLbl = saveBtn:CreateFontString(nil, "OVERLAY")
    saveLbl:SetFont(FONT, 11, "")
    saveLbl:SetPoint("CENTER")
    saveLbl:SetText("Add New")
    saveLbl:SetTextColor(1, 1, 1, 0.55)

    UpdateSaveBtnState = function() end  -- no-op, button is always active
    pState.UpdateSaveBtnState = UpdateSaveBtnState

    saveBtn:SetScript("OnEnter", function()
        saveLbl:SetTextColor(1, 1, 1, 0.70)
        for _, t in ipairs({sbT, sbB, sbL, sbR}) do t:SetColorTexture(1, 1, 1, DDS.BRD_HA or 0.30) end
        saveBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.65)
    end)
    saveBtn:SetScript("OnLeave", function()
        saveLbl:SetTextColor(1, 1, 1, 0.55)
        for _, t in ipairs({sbT, sbB, sbL, sbR}) do t:SetColorTexture(1, 1, 1, DDS.BRD_A or 0.20) end
        saveBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.6)
    end)
    saveBtn:SetScript("OnClick", function()
        EllesmereUI:ShowInputPopup({
            title = "New Preset",
            message = "Enter a name for your new preset:",
            placeholder = "My Preset",
            confirmText = "Save",
            cancelText = "Cancel",
            onConfirm = function(name)
                db[K_PRESETS][name] = SnapshotSettings()
                local found = false
                for i, n in ipairs(db[K_ORDER]) do
                    if n == name then found = true; break end
                end
                if not found then table.insert(db[K_ORDER], 1, name) end
                db[K_CUSTOM] = nil
                activePresetKey = "user:" .. name
                db[K_ACTIVE] = activePresetKey
                SetDropdownLabelText(activePresetKey)
            end,
        })
    end)

    -----------------------------------------------------------
    --  Forward declaration for Set as Default button (created later)
    -----------------------------------------------------------
    local defaultBtn, UpdateDefaultBtnState

    -----------------------------------------------------------
    --  Helper: after spec popup closes, apply the correct preset
    --  for the player's current spec immediately (so the user
    --  doesn't have to switch away and back).
    -----------------------------------------------------------
    local function ApplyForCurrentSpec()
        if not enableSpecFeature then return end

        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID  = specIdx and specIdx > 0 and GetSpecializationInfo(specIdx) or nil

        local specMap = db[K_SPEC_ASSIGN]
        local hasAny = false
        if specMap then
            for _, sl in pairs(specMap) do if next(sl) then hasAny = true; break end end
        end

        -- Determine which preset should be active for the current spec
        local targetPreset
        if hasAny and specID then
            for pKey, specList in pairs(specMap) do
                if specList[specID] then targetPreset = pKey; break end
            end
            if not targetPreset and db[K_SPEC_DEFAULT] then
                targetPreset = db[K_SPEC_DEFAULT]
            end
        end

        -- Apply the spec-active preset to DB and refresh real nameplates,
        -- but do NOT change the dropdown selection or rebuild the page.
        -- The user should keep viewing whatever preset they had selected.
        if targetPreset then
            -- Write spec-active snapshot to DB
            if targetPreset == "ellesmereui" then
                ApplyDefaults()
            elseif targetPreset == "custom" then
                if db[K_CUSTOM] then ApplySnapshot(db[K_CUSTOM]) end
            elseif targetPreset:sub(1, 5) == "user:" then
                local name = targetPreset:sub(6)
                if db[K_PRESETS][name] then ApplySnapshot(db[K_PRESETS][name]) end
            end
            db[K_SNAP] = nil
            -- Refresh real nameplates only (not preview, not page)
            if cfg.plateRefreshFn then cfg.plateRefreshFn() end
        end

        -- Always refresh labels/buttons since spec assignments may have changed
        SetDropdownLabelText(activePresetKey)
        if UpdateDefaultBtnState then UpdateDefaultBtnState() end

        -- Now re-apply the VIEWED preset's snapshot back to DB so that
        -- widgets/preview stay consistent with what the user is looking at
        if targetPreset and targetPreset ~= activePresetKey then
            if activePresetKey == "ellesmereui" then
                ApplyDefaults()
            elseif activePresetKey == "custom" then
                if db[K_CUSTOM] then ApplySnapshot(db[K_CUSTOM]) end
            elseif activePresetKey:sub(1, 5) == "user:" then
                local aName = activePresetKey:sub(6)
                if db[K_PRESETS][aName] then ApplySnapshot(db[K_PRESETS][aName]) end
            end
        end
    end

    -----------------------------------------------------------
    --  Assign to Spec button  (2nd action button)
    -----------------------------------------------------------
    local ASSIGN_BTN_W, ASSIGN_BTN_H = ACTION_BTN_W, PRESET_H
    local assignBtn = CreateFrame("Button", nil, anchorParent)
    assignBtn:SetSize(ASSIGN_BTN_W, ASSIGN_BTN_H)
    assignBtn:SetPoint("TOPLEFT", anchorParent, "TOP", ActionBtnX(2), btnY)
    assignBtn:SetFrameLevel(anchorParent:GetFrameLevel() + 10)

    local assignBg = assignBtn:CreateTexture(nil, "BACKGROUND")
    assignBg:SetAllPoints()
    assignBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.6)

    local abT = mkBrd(assignBtn); abT:SetPoint("TOPLEFT"); abT:SetPoint("TOPRIGHT"); PP.Height(abT, 1)
    local abB = mkBrd(assignBtn); abB:SetPoint("BOTTOMLEFT"); abB:SetPoint("BOTTOMRIGHT"); PP.Height(abB, 1)
    local abL = mkBrd(assignBtn); abL:SetPoint("TOPLEFT", abT, "BOTTOMLEFT"); abL:SetPoint("BOTTOMLEFT", abB, "TOPLEFT"); PP.Width(abL, 1)
    local abR = mkBrd(assignBtn); abR:SetPoint("TOPRIGHT", abT, "BOTTOMRIGHT"); abR:SetPoint("BOTTOMRIGHT", abB, "TOPRIGHT"); PP.Width(abR, 1)

    local assignLbl = assignBtn:CreateFontString(nil, "OVERLAY")
    assignLbl:SetFont(FONT, 11, "")
    assignLbl:SetPoint("CENTER")
    assignLbl:SetText("Assign to Spec")
    assignLbl:SetTextColor(1, 1, 1, 0.55)

    assignBtn:SetScript("OnEnter", function()
        assignLbl:SetTextColor(1, 1, 1, 0.70)
        for _, t in ipairs({abT, abB, abL, abR}) do t:SetColorTexture(1, 1, 1, DDS.BRD_HA or 0.30) end
        assignBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.65)
    end)
    assignBtn:SetScript("OnLeave", function()
        assignLbl:SetTextColor(1, 1, 1, 0.55)
        for _, t in ipairs({abT, abB, abL, abR}) do t:SetColorTexture(1, 1, 1, DDS.BRD_A or 0.20) end
        assignBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.6)
    end)
    assignBtn:SetScript("OnClick", function()
        -- If the active preset is "custom", force the user to name it first
        if activePresetKey == "custom" then
            EllesmereUI:ShowInputPopup({
                title = "Name Your Preset",
                message = "Please name your custom preset before assigning specs:",
                placeholder = "My Preset",
                confirmText = "Save & Continue",
                cancelText = "Cancel",
                onConfirm = function(name)
                    db[K_PRESETS][name] = SnapshotSettings()
                    local found = false
                    for i, n in ipairs(db[K_ORDER]) do
                        if n == name then found = true; break end
                    end
                    if not found then table.insert(db[K_ORDER], 1, name) end
                    db[K_CUSTOM] = nil
                    activePresetKey = "user:" .. name
                    db[K_ACTIVE] = activePresetKey
                    SetDropdownLabelText(activePresetKey)
                    UpdateSaveBtnState()
                    if UpdateDefaultBtnState then UpdateDefaultBtnState() end
                    -- Now open the spec assign popup with the newly named preset
                    EllesmereUI:ShowSpecAssignPopup({
                        db        = db,
                        dbKey     = K_SPEC_ASSIGN,
                        presetKey = activePresetKey,
                        defaultKey = K_SPEC_DEFAULT,
                        allPresetKeys = function()
                            local list = {}
                            if db[K_CUSTOM] and "custom" ~= activePresetKey then
                                list[#list + 1] = { key = "custom", name = "Custom" }
                            end
                            for _, n2 in ipairs(db[K_ORDER]) do
                                local k = "user:" .. n2
                                if db[K_PRESETS][n2] and k ~= activePresetKey then
                                    list[#list + 1] = { key = k, name = n2 }
                                end
                            end
                            for _, bk in ipairs(builtinPresets) do
                                if bk ~= activePresetKey then
                                    list[#list + 1] = { key = bk, name = builtinNames[bk] }
                                end
                            end
                            return list
                        end,
                        onDefaultChanged = function()
                            SetDropdownLabelText(activePresetKey)
                            if UpdateDefaultBtnState then UpdateDefaultBtnState() end
                        end,
                        onDone = ApplyForCurrentSpec,
                    })
                end,
            })
            return
        end
        EllesmereUI:ShowSpecAssignPopup({
            db        = db,
            dbKey     = K_SPEC_ASSIGN,
            presetKey = activePresetKey,
            defaultKey = K_SPEC_DEFAULT,
            allPresetKeys = function()
                -- Build list of all available preset keys excluding the current one
                local list = {}
                if db[K_CUSTOM] and "custom" ~= activePresetKey then
                    list[#list + 1] = { key = "custom", name = "Custom" }
                end
                for _, n in ipairs(db[K_ORDER]) do
                    local k = "user:" .. n
                    if db[K_PRESETS][n] and k ~= activePresetKey then
                        list[#list + 1] = { key = k, name = n }
                    end
                end
                for _, bk in ipairs(builtinPresets) do
                    if bk ~= activePresetKey then
                        list[#list + 1] = { key = bk, name = builtinNames[bk] }
                    end
                end
                return list
            end,
            onDefaultChanged = function()
                -- Refresh main UI to show/update (default) label and Set as Default button
                SetDropdownLabelText(activePresetKey)
                if UpdateDefaultBtnState then UpdateDefaultBtnState() end
            end,
            onDone = ApplyForCurrentSpec,
        })
    end)

    -----------------------------------------------------------
    --  Set as Default button  (3rd action button, spec feature only)
    --  Only visible when spec assignments exist.
    --  Grayed out / non-interactable when the active preset IS the default.
    -----------------------------------------------------------
    if enableSpecFeature then
        defaultBtn = CreateFrame("Button", nil, anchorParent)
        defaultBtn:Hide()  -- hidden until UpdateDefaultBtnState decides to show it
        defaultBtn:SetSize(ACTION_BTN_W, PRESET_H)
        defaultBtn:SetPoint("TOPLEFT", anchorParent, "TOP", ActionBtnX(3), btnY)
        defaultBtn:SetFrameLevel(anchorParent:GetFrameLevel() + 10)

        local defBg = defaultBtn:CreateTexture(nil, "BACKGROUND")
        defBg:SetAllPoints()
        defBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.6)

        local dbT2 = mkBrd(defaultBtn); dbT2:SetPoint("TOPLEFT"); dbT2:SetPoint("TOPRIGHT"); PP.Height(dbT2, 1)
        local dbB2 = mkBrd(defaultBtn); dbB2:SetPoint("BOTTOMLEFT"); dbB2:SetPoint("BOTTOMRIGHT"); PP.Height(dbB2, 1)
        local dbL2 = mkBrd(defaultBtn); dbL2:SetPoint("TOPLEFT", dbT2, "BOTTOMLEFT"); dbL2:SetPoint("BOTTOMLEFT", dbB2, "TOPLEFT"); PP.Width(dbL2, 1)
        local dbR2 = mkBrd(defaultBtn); dbR2:SetPoint("TOPRIGHT", dbT2, "BOTTOMRIGHT"); dbR2:SetPoint("BOTTOMRIGHT", dbB2, "TOPRIGHT"); PP.Width(dbR2, 1)

        local defLbl = defaultBtn:CreateFontString(nil, "OVERLAY")
        defLbl:SetFont(FONT, 11, "")
        defLbl:SetPoint("CENTER")
        defLbl:SetText("Set as Default")

        local defaultBtnEnabled = false
        UpdateDefaultBtnState = function()
            local hasAssignments = HasAnySpecAssignment()
            local isCurrentDefault = db[K_SPEC_DEFAULT] and activePresetKey == db[K_SPEC_DEFAULT]
            defaultBtnEnabled = hasAssignments and not isCurrentDefault
            if not hasAssignments then
                defaultBtn:Hide()
            else
                defaultBtn:Show()
                if defaultBtnEnabled then
                    defLbl:SetTextColor(1, 1, 1, 0.55)
                    for _, t in ipairs({dbT2, dbB2, dbL2, dbR2}) do t:SetColorTexture(1, 1, 1, DDS.BRD_A or 0.20) end
                    defBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.6)
                else
                    defLbl:SetTextColor(1, 1, 1, 0.20)
                    for _, t in ipairs({dbT2, dbB2, dbL2, dbR2}) do t:SetColorTexture(1, 1, 1, 0.08) end
                    defBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.3)
                end
            end
            RecenterButtons()
        end
        pState.UpdateDefaultBtnState = UpdateDefaultBtnState

        defaultBtn:SetScript("OnEnter", function()
            if not defaultBtnEnabled then return end
            defLbl:SetTextColor(1, 1, 1, 0.70)
            for _, t in ipairs({dbT2, dbB2, dbL2, dbR2}) do t:SetColorTexture(1, 1, 1, DDS.BRD_HA or 0.30) end
            defBg:SetColorTexture(DDS.BG_R or 0.075, DDS.BG_G or 0.113, DDS.BG_B or 0.141, 0.65)
        end)
        defaultBtn:SetScript("OnLeave", function() if UpdateDefaultBtnState then UpdateDefaultBtnState() end end)
        defaultBtn:SetScript("OnClick", function()
            if not defaultBtnEnabled then return end
            db[K_SPEC_DEFAULT] = activePresetKey
            SetDropdownLabelText(activePresetKey)
            if UpdateDefaultBtnState then UpdateDefaultBtnState() end
        end)
        UpdateDefaultBtnState()
    end

    -- Register all action buttons for dynamic recentering
    actionButtons[1] = saveBtn
    actionButtons[2] = assignBtn
    if defaultBtn then actionButtons[3] = defaultBtn end
    RecenterButtons()

    -- Ensure save/default button states update on fast-path RefreshPage (preset switches, widget refreshes)
    RegisterWidgetRefresh(function()
        UpdateSaveBtnState()
        if UpdateDefaultBtnState then UpdateDefaultBtnState() end
    end)
    EllesmereUI:RegisterSpecAutoSwitch({
        dbFunc     = DBFunc,
        dbPrefix   = pfx,
        presetKeys = presetKeys,
        defaults   = defaults,
        refreshFn  = cfg.refreshFn,
    })

    if isInline then
        return CheckDrift, rowH
    end
    return CheckDrift
end
