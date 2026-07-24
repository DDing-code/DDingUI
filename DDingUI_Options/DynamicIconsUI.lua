local ns = select(2, ...)
local DDingUI = ns.Addon
local CustomIcons = DDingUI and DDingUI.CustomIcons
local API = CustomIcons and CustomIcons.OptionsAPI
if not API then return end

local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local SL = _G.DDingUI_StyleLib
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local LSM = LibStub("LibSharedMedia-3.0", true)
local GUIRefs = {}

local function EnsureGUILoaded()
    if not GUIRefs.Widgets and DDingUI.GUI then
        GUIRefs.Widgets = DDingUI.GUI.Widgets
        GUIRefs.THEME = DDingUI.GUI.THEME
        GUIRefs.CreateCustomScrollBar = DDingUI.GUI.CreateCustomScrollBar
        GUIRefs.GetSafeScrollRange = DDingUI.GUI.GetSafeScrollRange
        GUIRefs.PropagateMouseWheelRecursive = DDingUI.GUI.PropagateMouseWheelRecursive
        GUIRefs.CreateStyledButton = DDingUI.GUI.CreateStyledButton
        GUIRefs.CreateStyledToggle = DDingUI.GUI.CreateStyledToggle
        GUIRefs.CreateStyledInput = DDingUI.GUI.CreateStyledInput
        GUIRefs.CreateStyledDropdown = DDingUI.GUI.CreateStyledDropdown
        GUIRefs.CreateBackdrop = DDingUI.GUI.CreateBackdrop
    end
    return GUIRefs.Widgets and GUIRefs.THEME
end

local runtime = API.runtime
local DEFAULT_ICON_SETTINGS = API.defaultIconSettings
local FALLBACK_ITEM_ICON = API.fallbackItemIcon
local FALLBACK_RACIAL_ICON = API.fallbackRacialIcon
local FALLBACK_SLOT_ICON = API.fallbackSlotIcon
local FALLBACK_SPELL_ICON = API.fallbackSpellIcon
local ApplyIconBorder = API.ApplyIconBorder
local EnsureEventFrame = API.EnsureEventFrame
local EnsureIconType = API.EnsureIconType
local EnsureLoadConditions = API.EnsureLoadConditions
local GetAnchorFrame = API.GetAnchorFrame
local GetDefaultRowGrowth = API.GetDefaultRowGrowth
local GetDynamicDB = API.GetDynamicDB
local GetGroupDisplayName = API.GetGroupDisplayName
local GetPlayerRacialSpellID = API.GetPlayerRacialSpellID
local GetStartAnchorForGrowthPair = API.GetStartAnchorForGrowthPair
local GetStoredIconTexture = API.GetStoredIconTexture
local NonQuestionTexture = API.NonQuestionTexture
local NormalizeRowGrowth = API.NormalizeRowGrowth
local RefreshAllLayouts = API.RefreshAllLayouts
local ReleaseDynamicIconFrame = API.ReleaseDynamicIconFrame
local ResolveAnchorPoints = API.ResolveAnchorPoints
local ResolveItemTexture = API.ResolveItemTexture
local ResolveSpellTexture = API.ResolveSpellTexture
local UpdateDynamicIcon = API.UpdateDynamicIcon
local uiState
local loadWindow

local SPEC_LIST = {
    {id=62, name="Arcane", classID=8, icon=135932},
    {id=63, name="Fire", classID=8, icon=135810},
    {id=64, name="Frost", classID=8, icon=135846},
    {id=65, name="Holy", classID=2, icon=135920},
    {id=66, name="Protection", classID=2, icon=236264},
    {id=70, name="Retribution", classID=2, icon=135873},
    {id=71, name="Arms", classID=1, icon=132355},
    {id=72, name="Fury", classID=1, icon=132347},
    {id=73, name="Protection", classID=1, icon=132341},
    {id=102, name="Balance", classID=11, icon=136096},
    {id=103, name="Feral", classID=11, icon=132115},
    {id=104, name="Guardian", classID=11, icon=132276},
    {id=105, name="Restoration", classID=11, icon=136041},
    {id=250, name="Blood", classID=6, icon=135770},
    {id=251, name="Frost", classID=6, icon=135773},
    {id=252, name="Unholy", classID=6, icon=135775},
    {id=253, name="Beast Mastery", classID=3, icon=461112},
    {id=254, name="Marksmanship", classID=3, icon=236179},
    {id=255, name="Survival", classID=3, icon=461113},
    {id=256, name="Discipline", classID=5, icon=135940},
    {id=257, name="Holy", classID=5, icon=237542},
    {id=258, name="Shadow", classID=5, icon=136207},
    {id=259, name="Assassination", classID=4, icon=236270},
    {id=260, name="Outlaw", classID=4, icon=236286},
    {id=261, name="Subtlety", classID=4, icon=132320},
    {id=262, name="Elemental", classID=7, icon=136048},
    {id=263, name="Enhancement", classID=7, icon=237581},
    {id=264, name="Restoration", classID=7, icon=136052},
    {id=265, name="Affliction", classID=9, icon=136145},
    {id=266, name="Demonology", classID=9, icon=136172},
    {id=267, name="Destruction", classID=9, icon=136186},
    {id=268, name="Brewmaster", classID=10, icon=608951},
    {id=269, name="Windwalker", classID=10, icon=608953},
    {id=270, name="Mistweaver", classID=10, icon=608952},
    {id=577, name="Havoc", classID=12, icon=1247264},
    {id=581, name="Vengeance", classID=12, icon=1247265},
    {id=1480, name="Devourer", classID=12, icon=7455385},
    {id=1467, name="Devastation", classID=13, icon=4511811},
    {id=1468, name="Preservation", classID=13, icon=4511812},
    {id=1473, name="Augmentation", classID=13, icon=5198700},
}

function CustomIcons:ShowLoadConditionsWindow(iconKey, iconData)
    EnsureLoadConditions(iconData)
    -- If a window already exists, discard it and rebuild to guarantee fresh bindings
    if loadWindow then
        loadWindow:Hide()
        loadWindow = nil
    end

    local lc = iconData.settings.loadConditions

    local f = CreateFrame("Frame", "DDingUI_LoadConditions", UIParent, "BackdropTemplate")
    f:SetSize(360, 460)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    f:SetBackdropColor(GUIRefs.THEME.bgDark[1], GUIRefs.THEME.bgDark[2], GUIRefs.THEME.bgDark[3], 0.95)
    f:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], 1)

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
    f.title:SetShadowOffset(1, -1)
    f.title:SetShadowColor(0, 0, 0, 1)
    f.title:SetPoint("TOP", f, "TOP", 0, -10)
    f.title:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1)
    f.title:SetText(L["Load Conditions"] or "Load Conditions")

    f.close = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.close:SetSize(24, 24)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f.close:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    f.close:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.9)
    f.close:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], 1)
    local closeText = f.close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
    closeText:SetShadowOffset(1, -1)
    closeText:SetShadowColor(0, 0, 0, 1)
    closeText:SetPoint("CENTER", 0, 1)
    closeText:SetText("×")
    closeText:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
    f.close:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.8, 0.2, 0.2, 1)
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
        closeText:SetTextColor(1, 1, 1, 1)
    end)
    f.close:SetScript("OnLeave", function(self)
        self:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.9)
        self:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], 1)
        closeText:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
    end)
    f.close:SetScript("OnClick", function() f:Hide() end)

    -- Enable toggle (DDingUI style)
    local enableBtn = CreateFrame("CheckButton", nil, f, "BackdropTemplate")
    enableBtn:SetSize(14, 14)
    enableBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
    enableBtn:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    enableBtn:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.9)
    enableBtn:SetBackdropBorderColor(0, 0, 0, 1)
    local enableCheck = enableBtn:CreateTexture(nil, "OVERLAY")
    enableCheck:SetPoint("TOPLEFT", 1, -1)
    enableCheck:SetPoint("BOTTOMRIGHT", -1, 1)
    enableCheck:SetGradient("HORIZONTAL",
        CreateColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1),
        CreateColor(GUIRefs.THEME.accentDark[1], GUIRefs.THEME.accentDark[2], GUIRefs.THEME.accentDark[3], 1))
    enableBtn:SetCheckedTexture(enableCheck)
    local enableHighlight = enableBtn:CreateTexture(nil, "ARTWORK")
    enableHighlight:SetAllPoints()
    enableHighlight:SetColorTexture(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 0.1)
    enableBtn:SetHighlightTexture(enableHighlight, "ADD")
    local enableLabel = enableBtn:CreateFontString(nil, "OVERLAY")
    enableLabel:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
    enableLabel:SetShadowOffset(1, -1)
    enableLabel:SetShadowColor(0, 0, 0, 1)
    enableLabel:SetTextColor(GUIRefs.THEME.text[1], GUIRefs.THEME.text[2], GUIRefs.THEME.text[3], 1)
    enableLabel:SetPoint("LEFT", enableBtn, "RIGHT", 6, 0)
    enableLabel:SetText(L["Enable Load Conditions"] or "Enable Load Conditions")
    enableBtn:SetChecked(lc.enabled == true)
    enableBtn:SetScript("OnClick", function(self)
        lc.enabled = self:GetChecked() or false
        if RefreshAllLayouts then RefreshAllLayouts() end
    end)

    -- Specs header
    local specHeader = f:CreateFontString(nil, "OVERLAY")
    specHeader:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 13, "")
    specHeader:SetShadowOffset(1, -1)
    specHeader:SetShadowColor(0, 0, 0, 1)
    specHeader:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1)
    specHeader:SetPoint("TOPLEFT", enableBtn, "BOTTOMLEFT", 4, -12)
    specHeader:SetText(L["By Specialization"] or "By Specialization")

    -- Spec scroll (DDingUI custom scrollbar)
    local specScroll = CreateFrame("ScrollFrame", nil, f)
    specScroll:SetPoint("TOPLEFT", specHeader, "BOTTOMLEFT", -4, -8)
    specScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)

    local specChild = CreateFrame("Frame", nil, specScroll)
    specChild:SetWidth(300)
    specChild:SetHeight(400)
    specScroll:SetScrollChild(specChild)

    if GUIRefs.CreateCustomScrollBar then
        local specScrollBar = GUIRefs.CreateCustomScrollBar(f, specScroll)
        specScrollBar:SetPoint("TOPLEFT", specScroll, "TOPRIGHT", 4, 0)
        specScrollBar:SetPoint("BOTTOMLEFT", specScroll, "BOTTOMRIGHT", 4, 0)
        specScroll.ScrollBar = specScrollBar
    end

    local y = 0
    lc.specs = lc.specs or {}
    for _, spec in ipairs(SPEC_LIST) do
        local row = CreateFrame("Frame", nil, specChild)
        row:SetSize(280, 26)
        row:SetPoint("TOPLEFT", specChild, "TOPLEFT", 0, -y)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        icon:SetTexture(spec.icon)

        local name = row:CreateFontString(nil, "OVERLAY")
        name:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        name:SetShadowOffset(1, -1)
        name:SetShadowColor(0, 0, 0, 1)
        name:SetTextColor(GUIRefs.THEME.text[1], GUIRefs.THEME.text[2], GUIRefs.THEME.text[3], 1)
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetText(spec.name)

        local toggle = CreateFrame("CheckButton", nil, row, "BackdropTemplate")
        toggle:SetSize(14, 14)
        toggle:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        toggle:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        toggle:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.9)
        toggle:SetBackdropBorderColor(0, 0, 0, 1)
        local toggleCheck = toggle:CreateTexture(nil, "OVERLAY")
        toggleCheck:SetPoint("TOPLEFT", 1, -1)
        toggleCheck:SetPoint("BOTTOMRIGHT", -1, 1)
        toggleCheck:SetGradient("HORIZONTAL",
            CreateColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1),
            CreateColor(GUIRefs.THEME.accentDark[1], GUIRefs.THEME.accentDark[2], GUIRefs.THEME.accentDark[3], 1))
        toggle:SetCheckedTexture(toggleCheck)
        local toggleHL = toggle:CreateTexture(nil, "ARTWORK")
        toggleHL:SetAllPoints()
        toggleHL:SetColorTexture(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 0.1)
        toggle:SetHighlightTexture(toggleHL, "ADD")
        toggle:SetChecked(lc.specs[spec.id] == true)
        toggle:SetScript("OnClick", function(self)
            lc.specs[spec.id] = self:GetChecked() or false
            if RefreshAllLayouts then RefreshAllLayouts() end
        end)

        y = y + 28
    end
    specChild:SetHeight(y)

    loadWindow = f
end

-- ------------------------
-- GUI (lightweight WeakAuras-like list)
-- ------------------------
uiState = {
    searchText = "",
    selectedIcon = nil,
    selectedGroup = nil,
    collapsedGroups = {},
    selectedIcons = {},  -- Multi-select: { [iconKey] = true }
    multiSelectMode = false,
}

local function MatchesSearch(iconKey, iconData)
    if uiState.searchText == "" then return true end
    local query = string.lower(uiState.searchText)
    local name = ""
    if iconData.type == "item" then
        name = GetItemInfo(iconData.id) or ((L["Item"] or "Item") .. " " .. iconData.id)
    elseif iconData.type == "spell" then
        local info = C_Spell.GetSpellInfo(iconData.id)
        name = (info and info.name) or ((L["Spell"] or "Spell") .. " " .. iconData.id)
    elseif iconData.type == "slot" then
        name = ((L["Slot"] or "Slot") .. " " .. (iconData.slotID or ""))
    elseif iconData.type == "trinketProc" then
        local iid = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID or 13)
        name = (iid and GetItemInfo(iid)) or ("Trinket " .. (iconData.slotID == 14 and "2" or "1"))
    end
    name = string.lower(tostring(name))
    local idStr = tostring(iconData.id or iconData.slotID or "")
    return name:find(query) or idStr:find(query)
end

local function CreateIconNode(parent, iconKey, iconData, groupKey)
    local node = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    node:SetSize(240, 42)
    node:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    -- [STYLE] bg.input 기본, bg.hover 호버, bg.selected 선택
    node:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.80)
    node:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], 0.5)
    node._iconKey = iconKey
    node._hover = false

    local function applyNodeHighlight()
        local isSelected = uiState.selectedIcon == iconKey
        local isMultiSelected = uiState.selectedIcons[iconKey]
        -- [STYLE] default=bgWidget, hover=bgLight, selected=bgMedium
        local bg = GUIRefs.THEME.bgWidget
        local border = GUIRefs.THEME.border
        local alpha = 0.80
        if isSelected or isMultiSelected then
            bg = GUIRefs.THEME.bgMedium
            border = GUIRefs.THEME.accent
            alpha = 0.80
        elseif node._hover then
            bg = GUIRefs.THEME.bgLight
            border = {GUIRefs.THEME.borderLight[1], GUIRefs.THEME.borderLight[2], GUIRefs.THEME.borderLight[3]}
            alpha = 0.60
        end
        node:SetBackdropColor(bg[1], bg[2], bg[3], alpha)
        node:SetBackdropBorderColor(border[1], border[2], border[3], isSelected and 1 or 0.5)
    end

    -- Multi-select checkbox (UF 통일: 14x14, 그라디언트 체크)
    local checkbox = CreateFrame("Button", nil, node, "BackdropTemplate")
    checkbox:SetSize(14, 14)
    checkbox:SetPoint("LEFT", node, "LEFT", 6, 0)
    checkbox:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    checkbox._checked = uiState.selectedIcons[iconKey] or false

    -- 체크 마크 텍스쳐 (UF 통일: 전체 채우기 그라디언트)
    local checkTex = checkbox:CreateTexture(nil, "OVERLAY")
    checkTex:SetPoint("TOPLEFT", 1, -1)
    checkTex:SetPoint("BOTTOMRIGHT", -1, 1)
    checkTex:SetColorTexture(1, 1, 1, 1)
    checkTex:SetGradient("HORIZONTAL",
        CreateColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1),
        CreateColor(GUIRefs.THEME.accentDark[1], GUIRefs.THEME.accentDark[2], GUIRefs.THEME.accentDark[3], 1)
    )
    checkTex:Hide()

    local function updateCheckboxVisual()
        if checkbox._checked then
            checkbox:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.9)
            checkbox:SetBackdropBorderColor(0, 0, 0, 1)
            checkTex:Show()
        else
            checkbox:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.9)
            checkbox:SetBackdropBorderColor(0, 0, 0, 1)
            checkTex:Hide()
        end
    end
    updateCheckboxVisual()
    -- 하이라이트
    local cbHighlight = checkbox:CreateTexture(nil, "ARTWORK")
    cbHighlight:SetColorTexture(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 0.1)
    cbHighlight:SetPoint("TOPLEFT", 1, -1)
    cbHighlight:SetPoint("BOTTOMRIGHT", -1, 1)
    cbHighlight:Hide()
    checkbox:SetScript("OnEnter", function(self)
        if not self._checked then cbHighlight:Show() end
    end)
    checkbox:SetScript("OnLeave", function(self)
        cbHighlight:Hide()
    end)
    checkbox:SetScript("OnClick", function(self)
        self._checked = not self._checked
        if self._checked then
            uiState.selectedIcons[iconKey] = true
        else
            uiState.selectedIcons[iconKey] = nil
        end
        -- Count selected icons
        local count = 0
        for _ in pairs(uiState.selectedIcons) do count = count + 1 end
        uiState.multiSelectMode = count > 0
        if count > 0 then
            uiState.selectedIcon = nil
            uiState.selectedGroup = nil
        end
        updateCheckboxVisual()
        applyNodeHighlight()
        CustomIcons:RefreshDynamicConfigUI()
    end)

    node.iconTex = node:CreateTexture(nil, "ARTWORK")
    node.iconTex:SetSize(32, 32)
    node.iconTex:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    node.iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    if iconData.type == "item" then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(iconData.id)
        node.iconTex:SetTexture(NonQuestionTexture(tex, ResolveItemTexture(iconData.id) or FALLBACK_ITEM_ICON))
    elseif iconData.type == "spell" or iconData.type == "aura" then
        local stored = GetStoredIconTexture(iconData)
        node.iconTex:SetTexture(NonQuestionTexture(ResolveSpellTexture(iconData.id, stored), stored or FALLBACK_SPELL_ICON))
    elseif iconData.type == "slot" or iconData.type == "trinketProc" then
        local iid = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID)
        local _, _, _, _, _, _, _, _, _, tex = iid and GetItemInfo(iid)
        node.iconTex:SetTexture(NonQuestionTexture(tex, ResolveItemTexture(iid, iconData.slotID) or FALLBACK_SLOT_ICON))
    elseif iconData.type == "racial" then
        local racialID = GetPlayerRacialSpellID()
        if racialID then
            if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                local ok, overrideID = pcall(C_SpellBook.FindSpellOverrideByID, racialID)
                if ok and overrideID and overrideID ~= racialID then
                    racialID = overrideID
                end
            end
            local info = C_Spell.GetSpellInfo(racialID)
            local tex = (info and info.iconID) or C_Spell.GetSpellTexture(racialID)
            node.iconTex:SetTexture(NonQuestionTexture(tex, FALLBACK_RACIAL_ICON))
        else
            node.iconTex:SetTexture(FALLBACK_RACIAL_ICON)
        end
    else
        node.iconTex:SetTexture(FALLBACK_SPELL_ICON)
    end

    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
    local label = node:CreateFontString(nil, "OVERLAY")
    label:SetFont(globalFont, 11, "")
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetPoint("LEFT", node.iconTex, "RIGHT", 6, 6)
    label:SetTextColor(GUIRefs.THEME.text[1], GUIRefs.THEME.text[2], GUIRefs.THEME.text[3], 1)

    local displayName = ""
    if iconData.type == "item" then
        displayName = GetItemInfo(iconData.id) or ((L["Item"] or "Item") .. " ID: " .. iconData.id)
    elseif iconData.type == "spell" or iconData.type == "aura" then
        local info = C_Spell.GetSpellInfo(iconData.id)
        displayName = (info and info.name) or ((L["Spell"] or "Spell") .. " ID: " .. iconData.id)
    elseif iconData.type == "slot" then
        displayName = (L["Slot"] or "Slot") .. " " .. tostring(iconData.slotID or "")
    elseif iconData.type == "trinketProc" then
        local iid = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID or 13)
        displayName = (iid and GetItemInfo(iid)) or ("Trinket " .. (iconData.slotID == 14 and "2" or "1"))
    elseif iconData.type == "racial" then
        local racialID = GetPlayerRacialSpellID()
        if racialID then
            if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                local ok, overrideID = pcall(C_SpellBook.FindSpellOverrideByID, racialID)
                if ok and overrideID and overrideID ~= racialID then
                    racialID = overrideID
                end
            end
            local info = C_Spell.GetSpellInfo(racialID)
            displayName = (info and info.name) or "Racial Trait"
        else
            displayName = "Racial Trait"
        end
    end
    label:SetText(displayName)

    local badge = node:CreateFontString(nil, "OVERLAY")
    badge:SetFont(globalFont, 10, "")
    badge:SetShadowOffset(1, -1)
    badge:SetShadowColor(0, 0, 0, 1)
    badge:SetPoint("LEFT", label, "LEFT", 0, -12)
    badge:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 0.9)
    badge:SetText(string.upper(iconData.type))

    local deleteBtn = CreateFrame("Button", nil, node, "BackdropTemplate")
    deleteBtn:SetSize(16, 16)
    deleteBtn:SetPoint("TOPRIGHT", node, "TOPRIGHT", -4, -4)
    deleteBtn:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    deleteBtn:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.9)
    deleteBtn:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], GUIRefs.THEME.border[4] or 0.50)
    local deleteBtnText = deleteBtn:CreateFontString(nil, "OVERLAY")
    deleteBtnText:SetFont(globalFont, 11, "")
    deleteBtnText:SetPoint("CENTER", 0, 1)
    deleteBtnText:SetText("×")
    deleteBtnText:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
    deleteBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(GUIRefs.THEME.error[1], GUIRefs.THEME.error[2], GUIRefs.THEME.error[3], 0.9)
        self:SetBackdropBorderColor(GUIRefs.THEME.error[1], GUIRefs.THEME.error[2], GUIRefs.THEME.error[3], 1)
        deleteBtnText:SetTextColor(1, 1, 1, 1)
    end)
    deleteBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.9)
        self:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], GUIRefs.THEME.border[4] or 0.50)
        deleteBtnText:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
    end)
    deleteBtn:SetScript("OnClick", function()
        CustomIcons:ConfirmDeleteIcon(iconKey, displayName)
    end)

    node:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            -- Clear multi-select and select single icon
            uiState.selectedIcons = {}
            uiState.multiSelectMode = false
            uiState.selectedIcon = iconKey
            uiState.selectedGroup = nil
            CustomIcons:RefreshDynamicListUI()
            CustomIcons:RefreshDynamicConfigUI()
        end
    end)
    node:SetScript("OnEnter", function()
        node._hover = true
        applyNodeHighlight()
        if runtime.dragState.dragging then
            runtime.dragState.targetGroup = groupKey
            runtime.dragState.dropBefore = iconKey
        end
    end)
    node:SetScript("OnLeave", function()
        node._hover = false
        applyNodeHighlight()
        if runtime.dragState.dragging then
            runtime.dragState.dropBefore = nil
        end
    end)

    node:RegisterForDrag("LeftButton")
    node:SetScript("OnDragStart", function()
        runtime.dragState.iconKey = iconKey
        runtime.dragState.sourceGroup = groupKey
        runtime.dragState.dropBefore = nil
        runtime.dragState.dragging = true
        node:SetAlpha(0.35)
    end)
    node:SetScript("OnDragStop", function()
        if runtime.dragState.dragging then
            local targetGroup = runtime.dragState.targetGroup or runtime.dragState.sourceGroup
            local beforeKey = runtime.dragState.dropBefore
            if targetGroup then
                if targetGroup ~= runtime.dragState.sourceGroup then
                    CustomIcons:MoveIconToGroup(iconKey, targetGroup)
                end
                CustomIcons:ReorderIconInGroup(targetGroup, iconKey, beforeKey)
            end
        end
        runtime.dragState.iconKey = nil
        runtime.dragState.targetGroup = nil
        runtime.dragState.dropBefore = nil
        runtime.dragState.dragging = false
        node:SetAlpha(1)
        CustomIcons:RefreshDynamicListUI()
    end)

    applyNodeHighlight()
    return node
end

-- UI containers
local uiFrames = {
    listParent = nil,
    configParent = nil,
    searchBox = nil,
    resultText = nil,
    createFrame = nil,
    loadWindow = nil,
}

-- [REFACTOR] GUIRefs.CreateStyledButton/Toggle/Input/Dropdown → DDingUI.GUI로 이동 (EnsureGUILoaded에서 로드)

function CustomIcons:RefreshDynamicListUI()
    if not uiFrames.listParent then return end
    if not EnsureGUILoaded() then return end
    local db = GetDynamicDB()
    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"

    -- Clear children
    for _, child in ipairs({uiFrames.listParent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local y = -5

    -- Multi-select buttons
    local selectBtnFrame = CreateFrame("Frame", nil, uiFrames.listParent)
    selectBtnFrame:SetPoint("TOPLEFT", uiFrames.listParent, "TOPLEFT", 0, y)
    selectBtnFrame:SetSize(240, 24)

    local selectAllBtn = GUIRefs.CreateStyledButton(selectBtnFrame, "전체 선택", 75, 22)
    selectAllBtn:SetPoint("LEFT", selectBtnFrame, "LEFT", 0, 0)
    selectAllBtn:SetScript("OnClick", function()
        -- Select all visible icons
        for iconKey, _ in pairs(db.iconData) do
            uiState.selectedIcons[iconKey] = true
        end
        local count = 0
        for _ in pairs(uiState.selectedIcons) do count = count + 1 end
        uiState.multiSelectMode = count > 0
        if count > 0 then
            uiState.selectedIcon = nil
            uiState.selectedGroup = nil
        end
        CustomIcons:RefreshDynamicListUI()
        CustomIcons:RefreshDynamicConfigUI()
    end)

    local deselectAllBtn = GUIRefs.CreateStyledButton(selectBtnFrame, "선택 해제", 75, 22)
    deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 4, 0)
    deselectAllBtn:SetScript("OnClick", function()
        uiState.selectedIcons = {}
        uiState.multiSelectMode = false
        CustomIcons:RefreshDynamicListUI()
        CustomIcons:RefreshDynamicConfigUI()
    end)

    -- Selected count
    local selectedCount = 0
    for _ in pairs(uiState.selectedIcons) do selectedCount = selectedCount + 1 end
    local countText = selectBtnFrame:CreateFontString(nil, "OVERLAY")
    countText:SetFont(globalFont, 10, "")
    countText:SetShadowOffset(1, -1)
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetPoint("LEFT", deselectAllBtn, "RIGHT", 8, 0)
    if selectedCount > 0 then
        countText:SetText("|cff00ff00" .. selectedCount .. "개 선택됨|r")
    else
        countText:SetText("")
    end

    y = y - 30
    local shown = 0
    local total = 0

    local function renderSection(title, iconKeys, groupKey)
        local isCollapsed = uiState.collapsedGroups[groupKey] == true
        local isSelectedGroup = uiState.selectedGroup == groupKey
        local headerHover = false
        -- Check if this group is disabled (only for actual groups, not ungrouped)
        local group = db.groups[groupKey]
        local isDisabled = group and group.enabled == false

        local box = CreateFrame("Frame", nil, uiFrames.listParent, "BackdropTemplate")
        box:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        })
        -- [STYLE] 그룹 헤더 bg.widget, border.default
        box:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.80)
        box:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], 0.50)
        box:SetPoint("TOPLEFT", uiFrames.listParent, "TOPLEFT", -2, y)
        box:SetPoint("TOPRIGHT", uiFrames.listParent, "TOPRIGHT", 2, y)

        local header = CreateFrame("Button", nil, box)
        header:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
        header:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -4)
        header:SetHeight(22)

        local headerText = header:CreateFontString(nil, "OVERLAY")
        headerText:SetFont(globalFont, 11, "")
        headerText:SetShadowOffset(1, -1)
        headerText:SetShadowColor(0, 0, 0, 1)
        headerText:SetPoint("LEFT", header, "LEFT", 4, 0)
        if isDisabled then
            headerText:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 0.6)
            headerText:SetText(title .. " |cff888888[OFF]|r")
        else
            headerText:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1)
            headerText:SetText(title)
        end

        local arrowBtn = CreateFrame("Button", nil, header, "BackdropTemplate")
        arrowBtn:SetSize(20, 20)
        arrowBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
        arrowBtn:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        arrowBtn:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.8)
        arrowBtn:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], GUIRefs.THEME.border[4] or 0.50)
        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        local arrowText = arrowBtn:CreateFontString(nil, "OVERLAY")
        arrowText:SetFont(globalFont, 11, "")
        arrowText:SetShadowOffset(1, -1)
        arrowText:SetShadowColor(0, 0, 0, 1)
        arrowText:SetPoint("CENTER", 0, 0)
        arrowText:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
        local function updateArrow()
            if uiState.collapsedGroups[groupKey] == true then
                arrowText:SetText("▶")
            else
                arrowText:SetText("▼")
            end
        end
        updateArrow()
        arrowBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 0.2)
            self:SetBackdropBorderColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 0.6)
            arrowText:SetTextColor(GUIRefs.THEME.text[1], GUIRefs.THEME.text[2], GUIRefs.THEME.text[3], 1)
        end)
        arrowBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(GUIRefs.THEME.bgWidget[1], GUIRefs.THEME.bgWidget[2], GUIRefs.THEME.bgWidget[3], 0.8)
            self:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], GUIRefs.THEME.border[4] or 0.50)
            arrowText:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
        end)

        local function applyBoxHighlight()
            -- [STYLE] default=bgWidget, selected=bgMedium, hover=accent border
            local bg = isSelectedGroup and GUIRefs.THEME.bgMedium or GUIRefs.THEME.bgWidget
            local alpha = isSelectedGroup and 0.80 or 0.80
            local border = (isSelectedGroup or headerHover) and GUIRefs.THEME.accent or GUIRefs.THEME.border
            local borderAlpha = (isSelectedGroup or headerHover) and 1 or 0.50
            -- Dim disabled groups
            if isDisabled then
                alpha = alpha * 0.5
                border = GUIRefs.THEME.border
                borderAlpha = 0.3
            end
            box:SetBackdropColor(bg[1], bg[2], bg[3], alpha)
            box:SetBackdropBorderColor(border[1], border[2], border[3], borderAlpha)
        end
        applyBoxHighlight()

        header:SetScript("OnEnter", function()
            headerHover = true
            if runtime.dragState.iconKey then
                runtime.dragState.targetGroup = groupKey
            end
            applyBoxHighlight()
        end)
        header:SetScript("OnLeave", function()
            headerHover = false
            if runtime.dragState.targetGroup == groupKey then
                runtime.dragState.targetGroup = nil
            end
            applyBoxHighlight()
        end)
        header:SetScript("OnMouseUp", function()
            uiState.selectedGroup = groupKey
            uiState.selectedIcon = nil
            isSelectedGroup = true
            applyBoxHighlight()
            CustomIcons:RefreshDynamicListUI()
            CustomIcons:RefreshDynamicConfigUI()
        end)
        header:SetScript("OnClick", nil)

        arrowBtn:SetScript("OnClick", function()
            uiState.collapsedGroups[groupKey] = not (uiState.collapsedGroups[groupKey] == true)
            CustomIcons:RefreshDynamicListUI()
        end)

        local innerY = -28
        if not isCollapsed then
            for _, iconKey in ipairs(iconKeys) do
                local iconData = db.iconData[iconKey]
                if iconData then
                    total = total + 1
                    if MatchesSearch(iconKey, iconData) then
                        local node = CreateIconNode(box, iconKey, iconData, groupKey)
                        node:SetPoint("TOPLEFT", box, "TOPLEFT", 8, innerY)
                        innerY = innerY - 46
                        shown = shown + 1
                    end
                end
            end
        else
            -- Count totals even when collapsed for result text
            for _, iconKey in ipairs(iconKeys) do
                if db.iconData[iconKey] then
                    total = total + 1
                end
            end
        end

        local boxHeight = math.abs(innerY) + 8
        box:SetHeight(boxHeight)
        y = y - boxHeight - 8
    end

    -- Ungrouped
    local ungroupedKeys = {}
    for k in pairs(db.ungrouped) do
        table.insert(ungroupedKeys, k)
    end
    table.sort(ungroupedKeys)
    renderSection(L["Ungrouped Icons"] or "Ungrouped Icons", ungroupedKeys, "ungrouped")

    for groupKey, group in pairs(db.groups) do
        local keys = {}
        local seen = {}
        for _, k in ipairs(group.icons or {}) do
            if db.iconData[k] and not seen[k] then
                table.insert(keys, k)
                seen[k] = true
            end
        end
        renderSection(GetGroupDisplayName(groupKey), keys, groupKey)
    end

    if uiFrames.resultText then
        uiFrames.resultText:SetText(string.format("Showing %d of %d icons", shown, total))
    end

    uiFrames.listParent:SetHeight(math.abs(y) + 20)

    -- 자식 위젯 위에서도 스크롤 가능하도록 마우스 휠 전파
    local listScroll = uiFrames.listParent:GetParent()
    if listScroll and GUIRefs.PropagateMouseWheelRecursive then
        GUIRefs.PropagateMouseWheelRecursive(uiFrames.listParent, listScroll)
    end
end

-- Batch edit state (temporary values before applying)
local batchEditState = {
    iconSize = 40,
    aspectRatio = 1.0,
    borderSize = 1,
    borderColor = {1, 1, 1, 1},
    showCooldown = true,
    showCharges = true,
    desaturateOnCooldown = true,
    desaturateWhenUnusable = true,
    showGCDSwipe = false,
}

function CustomIcons:ApplyBatchSettings(settings)
    local db = GetDynamicDB()
    for iconKey, _ in pairs(uiState.selectedIcons) do
        local iconData = db.iconData[iconKey]
        if iconData then
            iconData.settings = iconData.settings or {}
            for key, val in pairs(settings) do
                if key == "borderColor" then
                    iconData.settings.borderColor = {unpack(val)}
                else
                    iconData.settings[key] = val
                end
            end
            if runtime.UpdateDynamicIcon then
                runtime.UpdateDynamicIcon(iconKey)
            end
        end
    end
    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
end

function CustomIcons:RefreshDynamicConfigUI()
    if not uiFrames.configParent then return end
    if not EnsureGUILoaded() then return end
    -- 자식 프레임 정리
    for _, child in ipairs({uiFrames.configParent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    -- FontString/Texture 등 Region 정리
    for _, region in ipairs({uiFrames.configParent:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end

    local db = GetDynamicDB()

    -- Check for multi-select mode
    local selectedCount = 0
    for _ in pairs(uiState.selectedIcons) do selectedCount = selectedCount + 1 end

    if selectedCount > 1 then
        -- Batch Edit UI
        local y = 0

        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        local header = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
        header:SetFont(globalFont, 14, "")
        header:SetShadowOffset(1, -1)
        header:SetShadowColor(0, 0, 0, 1)
        header:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
        header:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1)
        header:SetText(selectedCount .. "개 아이콘 일괄 편집")
        y = y + 30

        local desc = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
        desc:SetFont(globalFont, 10, "")
        desc:SetShadowOffset(1, -1)
        desc:SetShadowColor(0, 0, 0, 1)
        desc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
        desc:SetText("아래 설정을 조정 후 '일괄 적용' 버튼을 눌러주세요")
        desc:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
        y = y + 25

        -- Icon Size
        local sizeSlider = GUIRefs.Widgets.CreateRange(uiFrames.configParent, {
            name = "아이콘 크기",
            min = 16, max = 128, step = 1,
            get = function() return batchEditState.iconSize end,
            set = function(_, val) batchEditState.iconSize = val end,
            width = "full",
        }, y, {})
        sizeSlider.slider:SetObeyStepOnDrag(true)
        sizeSlider.slider:SetValue(batchEditState.iconSize)
        y = y + 36

        -- Aspect Ratio
        local aspectSlider = GUIRefs.Widgets.CreateRange(uiFrames.configParent, {
            name = "종횡비",
            min = 0.5, max = 2.0, step = 0.01,
            get = function() return batchEditState.aspectRatio end,
            set = function(_, val) batchEditState.aspectRatio = val end,
            width = "full",
        }, y, {})
        aspectSlider.slider:SetObeyStepOnDrag(true)
        aspectSlider.slider:SetValue(batchEditState.aspectRatio)
        y = y + 36

        -- Border Size
        local borderSlider = GUIRefs.Widgets.CreateRange(uiFrames.configParent, {
            name = "테두리 크기",
            min = 0, max = 10, step = 1,
            get = function() return batchEditState.borderSize end,
            set = function(_, val) batchEditState.borderSize = val end,
            width = "full",
        }, y, {})
        borderSlider.slider:SetObeyStepOnDrag(true)
        borderSlider.slider:SetValue(batchEditState.borderSize)
        y = y + 36

        -- Border Color
        GUIRefs.Widgets.CreateColor(uiFrames.configParent, {
            name = "테두리 색상",
            get = function() return unpack(batchEditState.borderColor) end,
            set = function(_, r, g, b, a) batchEditState.borderColor = {r, g, b, a} end,
            width = "full",
        }, y)
        y = y + 40

        -- Toggles
        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "쿨다운 표시",
            get = function() return batchEditState.showCooldown end,
            set = function(_, val) batchEditState.showCooldown = val end,
            width = "full",
        }, y)
        y = y + 32

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "충전/횟수 표시",
            get = function() return batchEditState.showCharges end,
            set = function(_, val) batchEditState.showCharges = val end,
            width = "full",
        }, y)
        y = y + 32

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "쿨다운 시 흑백",
            get = function() return batchEditState.desaturateOnCooldown end,
            set = function(_, val) batchEditState.desaturateOnCooldown = val end,
            width = "full",
        }, y)
        y = y + 32

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "사용 불가 시 흑백",
            get = function() return batchEditState.desaturateWhenUnusable end,
            set = function(_, val) batchEditState.desaturateWhenUnusable = val end,
            width = "full",
        }, y)
        y = y + 32

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "GCD 스와이프 표시",
            get = function() return batchEditState.showGCDSwipe end,
            set = function(_, val) batchEditState.showGCDSwipe = val end,
            width = "full",
        }, y)
        y = y + 40

        -- Apply Button
        GUIRefs.Widgets.CreateExecute(uiFrames.configParent, {
            name = "|cff00ff00일괄 적용|r",
            func = function()
                CustomIcons:ApplyBatchSettings({
                    iconSize = batchEditState.iconSize,
                    aspectRatio = batchEditState.aspectRatio,
                    borderSize = batchEditState.borderSize,
                    borderColor = batchEditState.borderColor,
                    showCooldown = batchEditState.showCooldown,
                    showCharges = batchEditState.showCharges,
                    desaturateOnCooldown = batchEditState.desaturateOnCooldown,
                    desaturateWhenUnusable = batchEditState.desaturateWhenUnusable,
                    showGCDSwipe = batchEditState.showGCDSwipe,
                })
                print(((SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: ") .. "|cff00ff00" .. selectedCount .. "개 아이콘에 설정이 적용되었습니다.|r") -- [STYLE]
            end,
            width = "full",
        }, y)
        y = y + 50

        -- Delete Selected Button
        local deleteBtn = GUIRefs.Widgets.CreateExecute(uiFrames.configParent, {
            name = "|cffff4040선택 삭제 (" .. selectedCount .. "개)|r",
            func = function()
                CustomIcons:ConfirmDeleteSelected()
            end,
            width = "full",
        }, y)
        if deleteBtn and deleteBtn.text then
            deleteBtn.text:SetTextColor(0.90, 0.25, 0.25, 1)
        end

        return  -- Don't show single icon config
    end

    local iconKey = uiState.selectedIcon
    local groupKey = uiState.selectedGroup
    local iconData = iconKey and db.iconData[iconKey]
    if iconData then
        EnsureIconType(iconData)  -- Ensure type is set for config UI
    end
    local selectedGroup = groupKey and db.groups[groupKey]

    local y = 0
    local function addSlider(text, min, max, step, getter, setter)
        local slider = GUIRefs.Widgets.CreateRange(uiFrames.configParent, {
            name = text,
            min = min,
            max = max,
            step = step,
            get = function() return getter() end,
            set = function(_, val)
                setter(val)
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y, {})  -- Pass empty optionsTable
        slider.slider:SetObeyStepOnDrag(true)
        slider.slider:SetValue(getter())
        y = y + 36
    end

    local function showIconConfig()
        addSlider(L["Icon Size"] or "Icon Size", 16, 128, 1, function() return iconData.settings.iconSize or 40 end, function(val) iconData.settings.iconSize = val end)

        -- Use Own Size toggle (ignore group size)
        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = L["Use Own Size"] or "Use Own Size",
            desc = L["Ignore group icon size and use this icon's own size setting"] or "Ignore group icon size and use this icon's own size setting",
            get = function() return iconData.settings.useOwnSize or false end,
            set = function(_, val)
                iconData.settings.useOwnSize = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
            end,
            width = "full",
        }, y)
        y = y + 30

        addSlider(L["Aspect Ratio"] or "Aspect Ratio", 0.5, 2.0, 0.01, function() return iconData.settings.aspectRatio or 1.0 end, function(val) iconData.settings.aspectRatio = val end)
        addSlider(L["Border Size"] or "Border Size", 0, 10, 1, function() return iconData.settings.borderSize or DEFAULT_ICON_SETTINGS.borderSize end, function(val) iconData.settings.borderSize = val end)

        -- Border Color
        GUIRefs.Widgets.CreateColor(uiFrames.configParent, {
            name = L["Border Color"] or "Border Color",
            get = function() return unpack(iconData.settings.borderColor or {1, 1, 1, 1}) end,
            set = function(_, r, g, b, a)
                iconData.settings.borderColor = {r, g, b, a}
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        addSlider(L["Count Size"] or "Count Size", 4, 64, 1, function() return (iconData.settings.countSettings and iconData.settings.countSettings.size) or 16 end, function(val)
            iconData.settings.countSettings = iconData.settings.countSettings or {}
            iconData.settings.countSettings.size = val
        end)

        -- Count Font Type
        do
            local fontValues = {}
            if LSM then
                local hashTable = LSM:HashTable("font")
                for name, _ in pairs(hashTable) do
                    fontValues[name] = name
                end
            end
            GUIRefs.Widgets.CreateSelect(uiFrames.configParent, {
                name = L["Count Font Type"] or "Count Font Type",
                values = fontValues,
                get = function()
                    local cs = iconData.settings.countSettings or {}
                    return cs.font or (DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.general and DDingUI.db.profile.general.globalFont) or "Expressway"
                end,
                set = function(_, val)
                    iconData.settings.countSettings = iconData.settings.countSettings or {}
                    iconData.settings.countSettings.font = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                    RefreshAllLayouts()
                    CustomIcons:RefreshDynamicListUI()
                end,
                width = "full",
            }, y, nil, nil, nil)
            y = y + 40
        end

        -- Count Color
        GUIRefs.Widgets.CreateColor(uiFrames.configParent, {
            name = L["Count Color"] or "Count Color",
            get = function()
                local cs = iconData.settings.countSettings or {}
                return unpack(cs.color or {1, 1, 1, 1})
            end,
            set = function(_, r, g, b, a)
                iconData.settings.countSettings = iconData.settings.countSettings or {}
                iconData.settings.countSettings.color = {r, g, b, a}
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        -- Count X Offset
        addSlider(L["Count X Offset"] or "Count X Offset", -50, 50, 1, function()
            local cs = iconData.settings.countSettings or {}
            return cs.offsetX or -2
        end, function(val)
            iconData.settings.countSettings = iconData.settings.countSettings or {}
            iconData.settings.countSettings.offsetX = val
            if iconKey and runtime.UpdateDynamicIcon then
                runtime.UpdateDynamicIcon(iconKey)
            end
            RefreshAllLayouts()
            CustomIcons:RefreshDynamicListUI()
        end)

        -- Count Y Offset
        addSlider(L["Count Y Offset"] or "Count Y Offset", -50, 50, 1, function()
            local cs = iconData.settings.countSettings or {}
            return cs.offsetY or 2
        end, function(val)
            iconData.settings.countSettings = iconData.settings.countSettings or {}
            iconData.settings.countSettings.offsetY = val
            if iconKey and runtime.UpdateDynamicIcon then
                runtime.UpdateDynamicIcon(iconKey)
            end
            RefreshAllLayouts()
            CustomIcons:RefreshDynamicListUI()
        end)

        -- Count Anchor Point
        GUIRefs.Widgets.CreateSelect(uiFrames.configParent, {
            name = L["Count Anchor Point"] or "Count Anchor Point",
            values = {
                TOPLEFT = L["Top Left"] or "Top Left",
                TOP = L["Top"] or "Top",
                TOPRIGHT = L["Top Right"] or "Top Right",
                LEFT = L["Left"] or "Left",
                RIGHT = L["Right"] or "Right",
                BOTTOMLEFT = L["Bottom Left"] or "Bottom Left",
                BOTTOM = L["Bottom"] or "Bottom",
                BOTTOMRIGHT = L["Bottom Right"] or "Bottom Right",
            },
            get = function()
                local cs = iconData.settings.countSettings or {}
                return cs.anchor or "BOTTOMRIGHT"
            end,
            set = function(_, val)
                iconData.settings.countSettings = iconData.settings.countSettings or {}
                iconData.settings.countSettings.anchor = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y, nil, nil, nil)
        y = y + 40

        -- Cooldown Text Size
        addSlider(L["Cooldown Text Size"] or "Cooldown Text Size", 4, 64, 1, function()
            local cds = iconData.settings.cooldownSettings or {}
            return cds.size or 12
        end, function(val)
            iconData.settings.cooldownSettings = iconData.settings.cooldownSettings or {}
            iconData.settings.cooldownSettings.size = val
        end)

        -- Cooldown Text Color
        GUIRefs.Widgets.CreateColor(uiFrames.configParent, {
            name = "Cooldown Text Color",
            get = function()
                local cds = iconData.settings.cooldownSettings or {}
                return unpack(cds.color or {1, 1, 1, 1})
            end,
            set = function(_, r, g, b, a)
                iconData.settings.cooldownSettings = iconData.settings.cooldownSettings or {}
                iconData.settings.cooldownSettings.color = {r, g, b, a}
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "Show Cooldown",
            get = function() return iconData.settings.showCooldown ~= false end,
            set = function(_, val)
                iconData.settings.showCooldown = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "Show GCD Swipe",
            get = function() return iconData.settings.showGCDSwipe == true end,
            set = function(_, val)
                iconData.settings.showGCDSwipe = val == true
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "Show Charges/Count",
            get = function() return iconData.settings.showCharges ~= false end,
            set = function(_, val)
                iconData.settings.showCharges = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        -- TrinketProc-specific settings
        if iconData.type == "trinketProc" then
            -- Separator
            local trinketHeader = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
            trinketHeader:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 12, "")
            trinketHeader:SetShadowOffset(1, -1)
            trinketHeader:SetShadowColor(0, 0, 0, 1)
            trinketHeader:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1)
            trinketHeader:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            trinketHeader:SetText("━━━ Trinket Proc Settings ━━━")
            trinketHeader:SetJustifyH("LEFT")
            y = y + 24

            GUIRefs.Widgets.CreateInput(uiFrames.configParent, {
                name = "Proc Spell ID (0 = Auto)",
                get = function() return tostring(iconData.settings.procSpellID or 0) end,
                set = function(_, val)
                    iconData.settings.procSpellID = tonumber(val) or 0
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                end,
                width = "full",
            }, y)
            y = y + 30

            local procDesc = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
            procDesc:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 10, "")
            procDesc:SetShadowOffset(1, -1)
            procDesc:SetShadowColor(0, 0, 0, 1)
            procDesc:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
            procDesc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            procDesc:SetText("0: Use: 효과 자동 감지 / 수동: 패시브 프록 spellID 입력")
            procDesc:SetJustifyH("LEFT")
            y = y + 20

            GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
                name = "Show Proc Duration",
                get = function() return iconData.settings.showProcDuration ~= false end,
                set = function(_, val)
                    iconData.settings.showProcDuration = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                end,
                width = "full",
            }, y)
            y = y + 32

            GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
                name = "Show Item Cooldown",
                get = function() return iconData.settings.showItemCooldown ~= false end,
                set = function(_, val)
                    iconData.settings.showItemCooldown = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                end,
                width = "full",
            }, y)
            y = y + 32

            GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
                name = "Show Proc Stacks",
                get = function() return iconData.settings.showProcStacks ~= false end,
                set = function(_, val)
                    iconData.settings.showProcStacks = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                end,
                width = "full",
            }, y)
            y = y + 32
        end

        -- Fallback Item IDs (show for item type or unknown type with id)
        local isItemType = (iconData.type == "item") or (iconData.type ~= "spell" and iconData.type ~= "slot" and iconData.type ~= "trinketProc" and iconData.id)
        if isItemType then
            GUIRefs.Widgets.CreateInput(uiFrames.configParent, {
                name = "Fallback Item IDs",
                get = function() return iconData.settings.fallbackItems or "" end,
                set = function(_, val)
                    iconData.settings.fallbackItems = val
                    if iconKey and runtime.UpdateDynamicIcon then
                        runtime.UpdateDynamicIcon(iconKey)
                    end
                    RefreshAllLayouts()
                end,
                width = "full",
            }, y)
            y = y + 30

            local fallbackDesc = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
            fallbackDesc:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 10, "")
            fallbackDesc:SetShadowOffset(1, -1)
            fallbackDesc:SetShadowColor(0, 0, 0, 1)
            fallbackDesc:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
            fallbackDesc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            fallbackDesc:SetText("예: 3성 물약ID, 2성ID, 1성ID (쉼표 구분)")
            fallbackDesc:SetJustifyH("LEFT")
            y = y + 20
        end

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "Desaturate on Cooldown",
            get = function() return iconData.settings.desaturateOnCooldown ~= false end,
            set = function(_, val)
                iconData.settings.desaturateOnCooldown = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "Desaturate When Unusable",
            get = function() return iconData.settings.desaturateWhenUnusable ~= false end,
            set = function(_, val)
                iconData.settings.desaturateWhenUnusable = val
                if iconKey and runtime.UpdateDynamicIcon then
                    runtime.UpdateDynamicIcon(iconKey)
                end
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y)
        y = y + 32

        GUIRefs.Widgets.CreateExecute(uiFrames.configParent, {
            name = L["Load Conditions..."] or "Load Conditions...",
            func = function() CustomIcons:ShowLoadConditionsWindow(iconKey, iconData) end,
            width = "full",
        }, y)
        y = y + 40

        -- Update scroll child height
        uiFrames.configParent:SetHeight(y + 20)
        -- 마우스 휠 전파 (아이콘 설정)
        if uiFrames.configScroll and GUIRefs.PropagateMouseWheelRecursive then
            GUIRefs.PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
        end
    end

    local function ensureGroupDefaults(group)
        group.settings = group.settings or {}
        local s = group.settings
        s.growthDirection = s.growthDirection or "RIGHT"
        s.rowGrowthDirection = s.rowGrowthDirection or GetDefaultRowGrowth(s.growthDirection)
        s.rowGrowthDirection = NormalizeRowGrowth(s.growthDirection, s.rowGrowthDirection)
        if s.maxIconsPerRow == nil and s.maxColumns ~= nil then
            s.maxIconsPerRow = s.maxColumns
            s.maxColumns = nil
        end
        if s.anchorPoint and not s.anchorFrom and not s.anchorTo then
            s.anchorFrom = s.anchorPoint
            s.anchorTo = s.anchorPoint
            s.anchorPoint = nil
        end
        s.anchorFrom = s.anchorFrom or GetStartAnchorForGrowthPair(s.growthDirection, s.rowGrowthDirection)
        s.anchorTo = s.anchorTo or s.anchorFrom
        s.spacing = s.spacing or 5
        s.iconSize = s.iconSize or 40
        s.position = s.position or {x = 100, y = -100}
        s.anchorFrame = s.anchorFrame or ""
    end

    local function showGroupConfig()
        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        if not selectedGroup then
            local label = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
            label:SetFont(globalFont, 13, "")
            label:SetShadowOffset(1, -1)
            label:SetShadowColor(0, 0, 0, 1)
            label:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, 20)
            label:SetText("Select an icon or group")
            label:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
            return
        end
        ensureGroupDefaults(selectedGroup)
        local s = selectedGroup.settings

        -- Enabled toggle at the top
        GUIRefs.Widgets.CreateToggle(uiFrames.configParent, {
            name = "Enable Group",
            desc = "Show or hide all icons in this group",
            get = function() return selectedGroup.enabled ~= false end,
            set = function(_, val)
                selectedGroup.enabled = val
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 35

        GUIRefs.Widgets.CreateInput(uiFrames.configParent, {
            name = "Group Name",
            get = function() return selectedGroup.name or "" end,
            set = function(_, val)
                selectedGroup.name = val or "Group"
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        GUIRefs.Widgets.CreateSelect(uiFrames.configParent, {
            name = "Growth Direction",
            values = {RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down"},
            get = function() return s.growthDirection end,
            set = function(_, val)
                s.growthDirection = val
                s.rowGrowthDirection = NormalizeRowGrowth(val, s.rowGrowthDirection or GetDefaultRowGrowth(val))
                s.anchorFrom = GetStartAnchorForGrowthPair(val, s.rowGrowthDirection)
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "normal",
        }, y, nil, nil, nil)
        y = y + 40

        GUIRefs.Widgets.CreateSelect(uiFrames.configParent, {
            name = "Row Growth",
            values = {RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down"},
            get = function() return s.rowGrowthDirection end,
            set = function(_, val)
                s.rowGrowthDirection = NormalizeRowGrowth(s.growthDirection or "RIGHT", val)
                s.anchorFrom = GetStartAnchorForGrowthPair(s.growthDirection or "RIGHT", s.rowGrowthDirection)
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "normal",
        }, y, nil, nil, nil)
        y = y + 40

        GUIRefs.Widgets.CreateSelect(uiFrames.configParent, {
            name = "Anchor Frame Point",
            values = {
                TOPLEFT="TOPLEFT", TOP="TOP", TOPRIGHT="TOPRIGHT",
                LEFT="LEFT", CENTER="CENTER", RIGHT="RIGHT",
                BOTTOMLEFT="BOTTOMLEFT", BOTTOM="BOTTOM", BOTTOMRIGHT="BOTTOMRIGHT",
            },
            get = function() return s.anchorTo end,
            set = function(_, val)
                s.anchorTo = val
                RefreshAllLayouts()
                CustomIcons:RefreshDynamicConfigUI()
            end,
            width = "full",
        }, y, nil, nil, nil)
        y = y + 40

        addSlider(L["Icon Size"] or "Icon Size", 16, 128, 1, function() return s.iconSize or 40 end, function(val) s.iconSize = val end)

        -- Apply size to all icons in group button
        GUIRefs.Widgets.CreateExecute(uiFrames.configParent, {
            name = L["Apply Size to All Icons"] or "Apply Size to All Icons",
            func = function()
                if selectedGroup and selectedGroup.icons then
                    for _, iKey in ipairs(selectedGroup.icons) do
                        local iData = db.iconData[iKey]
                        if iData and iData.settings then
                            iData.settings.iconSize = nil  -- Clear individual size
                            iData.settings.useOwnSize = false  -- Use group size
                        end
                    end
                    RefreshAllLayouts()
                    CustomIcons:RefreshDynamicListUI()
                    print(((SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: ") .. "|cff00ff00Applied group size to all icons|r") -- [STYLE]
                end
            end,
            width = "full",
        }, y)
        y = y + 35

        addSlider(L["Spacing"] or "Spacing", -10, 10, 1, function() return s.spacing or 5 end, function(val) s.spacing = val end)
        addSlider(L["Max Icons Per Row"] or "Max Icons Per Row", 1, 40, 1, function() return s.maxIconsPerRow or 10 end, function(val) s.maxIconsPerRow = val end)
        addSlider(L["Position X"] or "Position X", -1000, 1000, 1, function() return (s.position and s.position.x) or 0 end, function(val)
            s.position = s.position or {}
            s.position.x = val
        end)
        addSlider(L["Position Y"] or "Position Y", -1000, 1000, 1, function() return (s.position and s.position.y) or 0 end, function(val)
            s.position = s.position or {}
            s.position.y = val
        end)

        GUIRefs.Widgets.CreateInput(uiFrames.configParent, {
            name = "Anchor Frame",
            get = function() return s.anchorFrame or "" end,
            set = function(_, val)
                s.anchorFrame = val or ""
                if not s.anchorFrame or s.anchorFrame == "" then
                    s.anchorFrame = ""
                end
                -- Avoid rebuilding the config UI while typing; just update layout shortly after change
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.05, RefreshAllLayouts)
                else
                    RefreshAllLayouts()
                end
            end,
            width = "full",
        }, y)
        y = y + 30

        -- 앵커 선택 버튼: 마우스로 프레임 직접 선택
        local pickBtn = GUIRefs.Widgets.CreateExecute(uiFrames.configParent, {
            name = "앵커 선택 (마우스 클릭)",
            func = function()
                DDingUI:StartFramePicker(function(frameName)
                    s.anchorFrame = frameName or ""
                    RefreshAllLayouts()
                    CustomIcons:RefreshDynamicConfigUI()
                end)
            end,
            width = "full",
        }, y)
        if pickBtn and pickBtn.text then
            pickBtn.text:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1)
        end
        y = y + 40

        local deleteGroupBtn = GUIRefs.Widgets.CreateExecute(uiFrames.configParent, {
            name = "Delete Group",
            func = function()
                CustomIcons:ConfirmDeleteGroup(groupKey, selectedGroup.name or groupKey)
            end,
            width = "full",
        }, y)
        -- [STYLE] Delete 버튼: status.error 컬러 텍스트
        if deleteGroupBtn and deleteGroupBtn.text then
            deleteGroupBtn.text:SetTextColor(0.90, 0.25, 0.25, 1)
        end
        y = y + 40

        -- Update scroll child height
        uiFrames.configParent:SetHeight(y + 20)
        -- 마우스 휠 전파 (그룹 설정)
        if uiFrames.configScroll and GUIRefs.PropagateMouseWheelRecursive then
            GUIRefs.PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
        end
    end

    if iconData then
        showIconConfig()
        return
    end
    if selectedGroup then
        showGroupConfig()
        return
    end

    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
    local label = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
    label:SetFont(globalFont, 13, "")
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, 20)
    label:SetText("Select an icon or group")
    label:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)

    -- 자식 위젯 위에서도 스크롤 가능하도록 마우스 휠 전파
    if uiFrames.configScroll and GUIRefs.PropagateMouseWheelRecursive then
        GUIRefs.PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
    end
end

function CustomIcons:ConfirmDeleteIcon(iconKey, label)
    if not EnsureGUILoaded() then return end
    if not uiFrames.confirmFrame then
        local f = CreateFrame("Frame", "DDingUI_DynIconConfirm", UIParent, "BackdropTemplate")
        f:SetSize(320, 140)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(GUIRefs.THEME.bgDark[1], GUIRefs.THEME.bgDark[2], GUIRefs.THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1)

        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        f.text:SetShadowOffset(1, -1)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetPoint("TOP", f, "TOP", 0, -38)
        f.text:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)

        f.confirm = GUIRefs.CreateStyledButton(f, "Confirm", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)

        f.cancel = GUIRefs.CreateStyledButton(f, "Cancel", 100, 26)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)

        f:Hide()
        uiFrames.confirmFrame = f
    end

    local f = uiFrames.confirmFrame
    f.title:SetText(L["Confirm Deletion"] or "Confirm Deletion")
    f.text:SetText((L["Delete \"%s\"?\nThis cannot be undone."] or "Delete \"%s\"?\nThis cannot be undone."):format(label or "icon"))
    f.confirm:SetScript("OnClick", function()
        f:Hide()
        CustomIcons:RemoveDynamicIcon(iconKey)
    end)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:Show()
end

function CustomIcons:ConfirmDeleteGroup(groupKey, label)
    if not EnsureGUILoaded() then return end
    if not uiFrames.confirmGroupFrame then
        local f = CreateFrame("Frame", "DDingUI_DynGroupConfirm", UIParent, "BackdropTemplate")
        f:SetSize(320, 160)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(GUIRefs.THEME.bgDark[1], GUIRefs.THEME.bgDark[2], GUIRefs.THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(0.90, 0.25, 0.25, 1)  -- Red for warning (GUIRefs.THEME error color)

        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        f.text:SetShadowOffset(1, -1)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetPoint("TOP", f, "TOP", 0, -38)
        f.text:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
        f.text:SetWidth(280)
        f.text:SetJustifyH("CENTER")

        f.confirm = GUIRefs.CreateStyledButton(f, "Delete", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        f.confirm:SetBackdropColor(0.5, 0.1, 0.1, 1)  -- Red tint for delete

        f.cancel = GUIRefs.CreateStyledButton(f, "Cancel", 100, 26)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)

        f:Hide()
        uiFrames.confirmGroupFrame = f
    end

    local f = uiFrames.confirmGroupFrame
    f.title:SetText(L["Delete Group?"] or "Delete Group?")
    f.text:SetText((L["Are you sure you want to delete group \"%s\"?\n\nAll icons in this group will be deleted.\nThis cannot be undone."] or "Are you sure you want to delete group \"%s\"?\n\nAll icons in this group will be deleted.\nThis cannot be undone."):format(label or "group"))
    f.confirm:SetScript("OnClick", function()
        f:Hide()
        CustomIcons:RemoveGroup(groupKey)
    end)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:Show()
end

function CustomIcons:ConfirmDeleteSelected()
    if not EnsureGUILoaded() then return end
    if not uiState.selectedIcons then return end

    local count = 0
    for _ in pairs(uiState.selectedIcons) do
        count = count + 1
    end
    if count == 0 then return end

    if not uiFrames.confirmBatchFrame then
        local f = CreateFrame("Frame", "DDingUI_DynBatchConfirm", UIParent, "BackdropTemplate")
        f:SetSize(320, 160)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetBackdrop({
            bgFile = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(GUIRefs.THEME.bgDark[1], GUIRefs.THEME.bgDark[2], GUIRefs.THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(GUIRefs.THEME.border[1], GUIRefs.THEME.border[2], GUIRefs.THEME.border[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(0.90, 0.25, 0.25, 1)

        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        f.text:SetShadowOffset(1, -1)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetPoint("TOP", f, "TOP", 0, -38)
        f.text:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
        f.text:SetWidth(280)
        f.text:SetJustifyH("CENTER")

        f.confirm = GUIRefs.CreateStyledButton(f, "Delete", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        f.confirm:SetBackdropColor(0.5, 0.1, 0.1, 1)

        f.cancel = GUIRefs.CreateStyledButton(f, "Cancel", 100, 26)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)

        f:Hide()
        uiFrames.confirmBatchFrame = f
    end

    local f = uiFrames.confirmBatchFrame
    f.title:SetText(L["Delete Selected?"] or "Delete Selected?")
    f.text:SetText((L["Are you sure you want to delete %d selected icons?\n\nThis cannot be undone."] or "Are you sure you want to delete %d selected icons?\n\nThis cannot be undone."):format(count))
    f.confirm:SetScript("OnClick", function()
        f:Hide()
        local db = GetDynamicDB()
        for iconKey in pairs(uiState.selectedIcons) do
            db.iconData[iconKey] = nil
            db.ungrouped[iconKey] = nil
            if db.ungroupedPositions then
                db.ungroupedPositions[iconKey] = nil
            end
            for _, group in pairs(db.groups) do
                for i = #group.icons, 1, -1 do
                    if group.icons[i] == iconKey then
                        table.remove(group.icons, i)
                    end
                end
            end
            local frame = runtime.iconFrames[iconKey]
            if frame then
                ReleaseDynamicIconFrame(iconKey, frame)
                runtime.iconFrames[iconKey] = nil
            end
        end
        uiState.selectedIcons = {}
        uiState.multiSelectMode = false
        RefreshAllLayouts()
        CustomIcons:RefreshDynamicListUI()
        CustomIcons:RefreshDynamicConfigUI()
    end)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:Show()
end

function CustomIcons:BuildDynamicIconsUI(parent)
    EnsureEventFrame()

    -- Ensure GUI components are loaded
    if not EnsureGUILoaded() then
        print(((SL and SL.GetChatPrefix and SL.GetChatPrefix("CDM", "CDM")) or "|cffffffffDDing|r|cffffa300UI|r |cffe6731fCDM|r: ") .. "|cffff0000Dynamic Icons: GUI not loaded yet|r") -- [STYLE]
        return
    end

    -- 이전 uiFrames 참조 초기화 (재진입 시 잔상 방지)
    uiFrames.listParent = nil
    uiFrames.configParent = nil
    uiFrames.configScroll = nil
    uiFrames.searchBox = nil
    uiFrames.resultText = nil

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)

    -- Search bar
    local search = GUIRefs.Widgets.CreateInput(container, {
        name = "Search by name or ID...",
        width = "full",
        get = function() return uiState.searchText end,
        set = function(_, val)
            uiState.searchText = val or ""
            CustomIcons:RefreshDynamicListUI()
        end,
    }, 0)
    if search.editBox then
        search.editBox:SetHeight(28)
    end

    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
    local resultText = container:CreateFontString(nil, "OVERLAY")
    resultText:SetFont(globalFont, 10, "")
    resultText:SetShadowOffset(1, -1)
    resultText:SetShadowColor(0, 0, 0, 1)
    if search.editBox then
        resultText:SetPoint("TOPLEFT", search.editBox, "BOTTOMLEFT", 4, -6)
    else
        resultText:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -34)
    end
    resultText:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
    uiFrames.resultText = resultText

    -- Buttons
    local createIconBtn = GUIRefs.Widgets.CreateExecute(container, {
        name = "+ Create Icon",
        func = function() CustomIcons:ShowCreateIconDialog() end,
        width = "normal",
    }, 40)
    -- [STYLE] 악센트 텍스트
    if createIconBtn.text then createIconBtn.text:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1) end
    if search.editBox then
        createIconBtn:SetPoint("TOPLEFT", search.editBox, "BOTTOMLEFT", 0, -18)
    else
        createIconBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -52)
    end

    local createGroupBtn = GUIRefs.Widgets.CreateExecute(container, {
        name = "+ " .. (L["New Group"] or "Create Group"),
        func = function()
            CustomIcons:CreateDynamicGroup(L["New Group"] or "New Group")
        end,
        width = "normal",
    }, 40)
    -- [STYLE] 악센트 텍스트
    if createGroupBtn.text then createGroupBtn.text:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1) end
    createGroupBtn:SetPoint("LEFT", createIconBtn, "RIGHT", 8, 0)

    -- Left list scroll (DDingUI custom scrollbar)
    local listScroll = CreateFrame("ScrollFrame", nil, container)
    listScroll:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -80)
    listScroll:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    listScroll:SetWidth(260)

    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(250)
    listChild:SetHeight(400)
    listScroll:SetScrollChild(listChild)

    local listScrollBar = GUIRefs.CreateCustomScrollBar(container, listScroll)
    listScrollBar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 4, 0)
    listScrollBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 4, 0)
    listScroll.ScrollBar = listScrollBar

    uiFrames.listParent = listChild

    -- [STYLE] 좌우 구분선 (border.separator)
    local separator = container:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 5, 0)
    separator:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 5, 0)
    separator:SetColorTexture(0.20, 0.20, 0.20, 0.40)

    -- [STYLE] 우측 설정 영역: bg.sidebar 배경, border.default 테두리
    local configContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    configContainer:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 12, 0)
    configContainer:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    GUIRefs.CreateBackdrop(configContainer, GUIRefs.THEME.bgDark, GUIRefs.THEME.border)

    local configScroll = CreateFrame("ScrollFrame", nil, configContainer)
    configScroll:SetPoint("TOPLEFT", configContainer, "TOPLEFT", 8, -8)
    configScroll:SetPoint("BOTTOMRIGHT", configContainer, "BOTTOMRIGHT", -14, 8)

    local configChild = CreateFrame("Frame", nil, configScroll)
    configChild:SetWidth(configScroll:GetWidth() or 400)
    configChild:SetHeight(800)  -- Will be adjusted dynamically
    configScroll:SetScrollChild(configChild)

    local configScrollBar = GUIRefs.CreateCustomScrollBar(configContainer, configScroll)
    configScrollBar:SetPoint("TOPLEFT", configScroll, "TOPRIGHT", 4, 0)
    configScrollBar:SetPoint("BOTTOMLEFT", configScroll, "BOTTOMRIGHT", 4, 0)
    configScroll.ScrollBar = configScrollBar

    uiFrames.configParent = configChild
    uiFrames.configScroll = configScroll

    CustomIcons:RefreshDynamicListUI()
    CustomIcons:RefreshDynamicConfigUI()
end

-- Creation dialog
CustomIcons.slotOptions = CustomIcons.slotOptions or {
    {text = "Trinket 0 (Slot 13)", slotID = 13},
    {text = "Trinket 1 (Slot 14)", slotID = 14},
    {text = "Main Hand (16)", slotID = 16},
    {text = "Off Hand (17)", slotID = 17},
    {text = "Head (1)", slotID = 1},
    {text = "Neck (2)", slotID = 2},
    {text = "Shoulder (3)", slotID = 3},
    {text = "Back (15)", slotID = 15},
    {text = "Chest (5)", slotID = 5},
    {text = "Wrist (9)", slotID = 9},
    {text = "Hands (10)", slotID = 10},
    {text = "Waist (6)", slotID = 6},
    {text = "Legs (7)", slotID = 7},
    {text = "Feet (8)", slotID = 8},
    {text = "Finger 0 (11)", slotID = 11},
    {text = "Finger 1 (12)", slotID = 12},
}

-- Keep dropdown menus above the create dialog so they don't get obscured
function CustomIcons.RaiseDropDownMenus()
    for i = 1, 2 do
        local list = _G["DropDownList"..i]
        if list then
            list:SetFrameStrata("TOOLTIP")
            if uiFrames.createFrame then
                list:SetFrameLevel(uiFrames.createFrame:GetFrameLevel() + 10)
            end
            if not list.__dduiStrataHooked then
                list:HookScript("OnShow", CustomIcons.RaiseDropDownMenus)
                list.__dduiStrataHooked = true
            end
        end
    end
end

function CustomIcons:ShowCreateIconDialog()
    if not EnsureGUILoaded() then return end
    if not uiFrames.createFrame then
        local f = CreateFrame("Frame", "DDingUI_DynIconCreate", UIParent, "BackdropTemplate")
        f:SetSize(360, 200)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        GUIRefs.CreateBackdrop(f, GUIRefs.THEME.bgDark, GUIRefs.THEME.border)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(globalFont, 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(GUIRefs.THEME.accent[1], GUIRefs.THEME.accent[2], GUIRefs.THEME.accent[3], 1)
        f.title:SetText("Create Icon")

        -- Type toggle buttons (styled)
        f.typeButtons = {}
        local types = { {key = "spell", label = "Spell"}, {key = "item", label = "Item"}, {key = "slot", label = "Slot"}, {key = "trinketProc", label = "Trinket"}, {key = "racial", label = "Racial"} }
        local spacing = 75
        local startX = -((#types - 1) * spacing) / 2
        for idx, info in ipairs(types) do
            local btn = GUIRefs.CreateStyledToggle(f, info.label, 80)
            btn:SetPoint("TOP", f, "TOP", startX + (idx - 1) * spacing, -42)
            btn:SetScript("OnClick", function()
                for _, b in pairs(f.typeButtons) do b:SetChecked(false) end
                btn:SetChecked(true)
                f.selectedType = info.key
                if info.key == "slot" then
                    f.idInput:Hide()
                    f.idLabel:Hide()
                    f.slotDropdown:Show()
                    f.slotLabel:Show()
                    if f.trinketDropdown then f.trinketDropdown:Hide() end
                    if f.trinketLabel then f.trinketLabel:Hide() end
                elseif info.key == "trinketProc" then
                    f.idInput:Hide()
                    f.idLabel:Hide()
                    f.slotDropdown:Hide()
                    f.slotLabel:Hide()
                    if f.trinketDropdown then f.trinketDropdown:Show() end
                    if f.trinketLabel then f.trinketLabel:Show() end
                elseif info.key == "racial" then
                    f.idInput:Hide()
                    f.idLabel:Hide()
                    f.slotDropdown:Hide()
                    f.slotLabel:Hide()
                    if f.trinketDropdown then f.trinketDropdown:Hide() end
                    if f.trinketLabel then f.trinketLabel:Hide() end
                else
                    f.idInput:Show()
                    f.idLabel:Show()
                    f.slotDropdown:Hide()
                    f.slotLabel:Hide()
                    if f.trinketDropdown then f.trinketDropdown:Hide() end
                    if f.trinketLabel then f.trinketLabel:Hide() end
                end
            end)
            f.typeButtons[info.key] = btn
        end
        f.typeButtons.spell:SetChecked(true)
        f.selectedType = "spell"

        -- ID input (styled)
        local idLabel = f:CreateFontString(nil, "OVERLAY")
        idLabel:SetFont(globalFont, 11, "")
        idLabel:SetShadowOffset(1, -1)
        idLabel:SetShadowColor(0, 0, 0, 1)
        idLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -78)
        idLabel:SetText("Spell or Item ID")
        idLabel:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
        f.idLabel = idLabel

        local idBox = GUIRefs.CreateStyledInput(f, 200, 28, true)
        idBox:SetPoint("TOPLEFT", idLabel, "BOTTOMLEFT", 0, -4)
        f.idInput = idBox

        -- Slot dropdown (styled)
        local slotLabel = f:CreateFontString(nil, "OVERLAY")
        slotLabel:SetFont(globalFont, 11, "")
        slotLabel:SetShadowOffset(1, -1)
        slotLabel:SetShadowColor(0, 0, 0, 1)
        slotLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -78)
        slotLabel:SetText("Equipment Slot")
        slotLabel:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
        slotLabel:Hide()
        f.slotLabel = slotLabel

        local dropdown = GUIRefs.CreateStyledDropdown(f, CustomIcons.slotOptions, 200)
        dropdown:SetPoint("TOPLEFT", slotLabel, "BOTTOMLEFT", 0, -4)
        dropdown:SetText("Select Slot")
        dropdown:Hide()
        f.slotDropdown = dropdown
        f.selectedSlot = CustomIcons.slotOptions[1].slotID
        dropdown.selectedValue = CustomIcons.slotOptions[1].slotID

        -- Trinket slot dropdown (for trinketProc type)
        local trinketSlotOptions = {
            {text = "Trinket 1 (Slot 13)", slotID = 13},
            {text = "Trinket 2 (Slot 14)", slotID = 14},
        }
        local trinketLabel = f:CreateFontString(nil, "OVERLAY")
        trinketLabel:SetFont(globalFont, 11, "")
        trinketLabel:SetShadowOffset(1, -1)
        trinketLabel:SetShadowColor(0, 0, 0, 1)
        trinketLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -78)
        trinketLabel:SetText("Trinket Slot")
        trinketLabel:SetTextColor(GUIRefs.THEME.textDim[1], GUIRefs.THEME.textDim[2], GUIRefs.THEME.textDim[3], 1)
        trinketLabel:Hide()
        f.trinketLabel = trinketLabel

        local trinketDD = GUIRefs.CreateStyledDropdown(f, trinketSlotOptions, 200)
        trinketDD:SetPoint("TOPLEFT", trinketLabel, "BOTTOMLEFT", 0, -4)
        trinketDD:SetText("Trinket 1 (Slot 13)")
        trinketDD:Hide()
        f.trinketDropdown = trinketDD
        trinketDD.selectedValue = 13

        -- Buttons (styled)
        f.confirm = GUIRefs.CreateStyledButton(f, "Create", 100, 28)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)

        f.cancel = GUIRefs.CreateStyledButton(f, "Cancel", 100, 28)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
        f.cancel:SetScript("OnClick", function() f:Hide() end)

        f.confirm:SetScript("OnClick", function()
            local t = f.selectedType
            if t == "slot" then
                local slotID = f.slotDropdown.selectedValue or CustomIcons.slotOptions[1].slotID
                CustomIcons:AddDynamicIcon({type = "slot", slotID = slotID})
            elseif t == "trinketProc" then
                local slotID = f.trinketDropdown.selectedValue or 13
                CustomIcons:AddDynamicIcon({type = "trinketProc", slotID = slotID})
            elseif t == "racial" then
                CustomIcons:AddDynamicIcon({type = "racial", id = 0})
            else
                local idVal = f.idInput:GetText() or ""
                -- String (spell name) or Number (spell ID) allowed
                local numId = tonumber(idVal)
                if not numId and idVal ~= "" then
                    local info = C_Spell.GetSpellInfo(idVal)
                    if info and info.spellID then numId = info.spellID end
                end

                if not numId or numId <= 0 then
                    UIErrorsFrame:AddMessage("Enter a valid ID or Spell Name", 1, 0, 0)
                    return
                end
                CustomIcons:AddDynamicIcon({type = t, id = numId})
            end
            f:Hide()
        end)

        uiFrames.createFrame = f
    end

    uiFrames.createFrame:Show()
end

-- Hook into GUI renderer
CustomIcons.BuildDynamicIconsUI = CustomIcons.BuildDynamicIconsUI
CustomIcons.RefreshDynamicListUI = CustomIcons.RefreshDynamicListUI
CustomIcons.RefreshDynamicConfigUI = CustomIcons.RefreshDynamicConfigUI
CustomIcons.ApplyIconBorder = ApplyIconBorder
CustomIcons.ResolveAnchorPoints = ResolveAnchorPoints
CustomIcons.GetAnchorFrame = GetAnchorFrame
CustomIcons.ShowLoadConditionsWindow = CustomIcons.ShowLoadConditionsWindow
