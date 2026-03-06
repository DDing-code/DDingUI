local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local FLAT = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8" -- [12.0.1]

DDingUI.CustomIcons = DDingUI.CustomIcons or {}
local CustomIcons = DDingUI.CustomIcons

-- Lazy-loaded GUI components (DDingUI.GUI is exported after this file loads)
local Widgets, THEME
local CreateCustomScrollBar, GetSafeScrollRange, PropagateMouseWheelRecursive
local CreateStyledButton, CreateStyledToggle, CreateStyledInput, CreateStyledDropdown -- [REFACTOR] GUI.lua에서 로드
local CreateBackdrop -- [REFACTOR] GUI.lua에서 로드
local function EnsureGUILoaded()
    if not Widgets and DDingUI.GUI then
        Widgets = DDingUI.GUI.Widgets
        THEME = DDingUI.GUI.THEME
        CreateCustomScrollBar = DDingUI.GUI.CreateCustomScrollBar
        GetSafeScrollRange = DDingUI.GUI.GetSafeScrollRange
        PropagateMouseWheelRecursive = DDingUI.GUI.PropagateMouseWheelRecursive
        CreateStyledButton = DDingUI.GUI.CreateStyledButton -- [REFACTOR]
        CreateStyledToggle = DDingUI.GUI.CreateStyledToggle -- [REFACTOR]
        CreateStyledInput = DDingUI.GUI.CreateStyledInput -- [REFACTOR]
        CreateStyledDropdown = DDingUI.GUI.CreateStyledDropdown -- [REFACTOR]
        CreateBackdrop = DDingUI.GUI.CreateBackdrop -- [REFACTOR]
    end
    return Widgets and THEME
end

local LSM = LibStub("LibSharedMedia-3.0", true)

-- [REFACTOR] 공통 TextureBorder 유틸리티 (Toolkit.lua) — CustomIcons는 안쪽 보더(inset=true)
local _CreateTextureBorder = DDingUI.CreateTextureBorder
local UpdateTextureBorderColor = DDingUI.UpdateTextureBorderColor
local _UpdateTextureBorderSize = DDingUI.UpdateTextureBorderSize
local ShowTextureBorder = DDingUI.ShowTextureBorder

-- 안쪽 보더 래퍼 (inset=true 자동 전달)
local function CreateTextureBorder(parent, borderSize, r, g, b, a)
    return _CreateTextureBorder(parent, borderSize, r, g, b, a, true)
end
local function UpdateTextureBorderSize(parent, borderSize)
    return _UpdateTextureBorderSize(parent, borderSize, true)
end

-- Forward declarations
local RefreshAllLayouts
local uiState

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

-- [REFACTOR] CreateBackdrop은 GUI.lua로 이동됨 → EnsureGUILoaded()에서 lazy-load

-- Runtime containers
local runtime = {
    iconFrames = {},  -- [iconKey] = frame
    groupFrames = {}, -- [groupKey] = frame
    dragState = {},
    pendingSpecReload = false,
}

-- UI state containers
local uiFrames = {
    listParent = nil,
    configParent = nil,
    searchBox = nil,
    resultText = nil,
    createFrame = nil,
    loadWindow = nil,
}

-- ------------------------
-- DB helpers
-- ------------------------
local DEFAULT_ICON_SETTINGS = {
    iconSize = 44,
    aspectRatio = 1.0,
    borderSize = 1,
    borderColor = { 0, 0, 0, 1 },
    showCharges = true,
    showCooldown = true,
    showGCDSwipe = false,
    desaturateWhenUnusable = true,
    desaturateOnCooldown = true,
    countSettings = {
        size = 16,
        anchor = "BOTTOMRIGHT",
        offsetX = -2,
        offsetY = 2,
        color = { 1, 1, 1, 1 },
    },
    cooldownSettings = {
        size = 12,
        color = { 1, 1, 1, 1 },
    },
}

local function CopyColor(color)
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], color[4] }
end

-- Infer icon type if missing (for migration from older versions)
local function EnsureIconType(iconData)
    if not iconData then return end
    if iconData.type then return end  -- Already has type

    -- Infer type from data structure
    if iconData.slotID then
        iconData.type = "slot"
    elseif iconData.id then
        -- Try to detect if it's an item or spell
        -- C_Item.GetItemInfo is more reliable for checking if ID is an item
        local itemInfo = C_Item.GetItemInfo(iconData.id)
        if itemInfo then
            iconData.type = "item"
        else
            -- Also try legacy GetItemInfo as fallback
            local itemName = GetItemInfo(iconData.id)
            if itemName then
                iconData.type = "item"
            else
                -- Check if it's a valid spell
                local spellInfo = C_Spell.GetSpellInfo(iconData.id)
                if spellInfo then
                    iconData.type = "spell"
                else
                    -- Default to spell if we can't determine
                    iconData.type = "spell"
                end
            end
        end
    end
end

local function EnsureIconSettings(iconData)
    if not iconData then return end
    EnsureIconType(iconData)  -- Ensure type is set
    iconData.settings = iconData.settings or {}
    local settings = iconData.settings

    -- NOTE: iconSize is intentionally NOT set here to allow group iconSize to be used as fallback
    -- if settings.iconSize == nil then settings.iconSize = DEFAULT_ICON_SETTINGS.iconSize end
    if settings.aspectRatio == nil then settings.aspectRatio = DEFAULT_ICON_SETTINGS.aspectRatio end
    if settings.borderSize == nil then settings.borderSize = DEFAULT_ICON_SETTINGS.borderSize end
    if settings.borderColor == nil then settings.borderColor = CopyColor(DEFAULT_ICON_SETTINGS.borderColor) end
    if settings.showCharges == nil then settings.showCharges = DEFAULT_ICON_SETTINGS.showCharges end
    if settings.showCooldown == nil then settings.showCooldown = DEFAULT_ICON_SETTINGS.showCooldown end
    if settings.showGCDSwipe == nil then settings.showGCDSwipe = DEFAULT_ICON_SETTINGS.showGCDSwipe end
    if settings.desaturateWhenUnusable == nil then settings.desaturateWhenUnusable = DEFAULT_ICON_SETTINGS.desaturateWhenUnusable end
    if settings.desaturateOnCooldown == nil then settings.desaturateOnCooldown = DEFAULT_ICON_SETTINGS.desaturateOnCooldown end

    settings.countSettings = settings.countSettings or {}
    if settings.countSettings.size == nil then settings.countSettings.size = DEFAULT_ICON_SETTINGS.countSettings.size end
    if settings.countSettings.anchor == nil then settings.countSettings.anchor = DEFAULT_ICON_SETTINGS.countSettings.anchor end
    if settings.countSettings.offsetX == nil then settings.countSettings.offsetX = DEFAULT_ICON_SETTINGS.countSettings.offsetX end
    if settings.countSettings.offsetY == nil then settings.countSettings.offsetY = DEFAULT_ICON_SETTINGS.countSettings.offsetY end
    if settings.countSettings.color == nil then settings.countSettings.color = CopyColor(DEFAULT_ICON_SETTINGS.countSettings.color) end

    settings.cooldownSettings = settings.cooldownSettings or {}
    if settings.cooldownSettings.size == nil then settings.cooldownSettings.size = DEFAULT_ICON_SETTINGS.cooldownSettings.size end
    if settings.cooldownSettings.color == nil then settings.cooldownSettings.color = CopyColor(DEFAULT_ICON_SETTINGS.cooldownSettings.color) end

    -- TrinketProc-specific defaults
    if iconData.type == "trinketProc" then
        if settings.procSpellID == nil then settings.procSpellID = 0 end
        if settings.showProcDuration == nil then settings.showProcDuration = true end
        if settings.showItemCooldown == nil then settings.showItemCooldown = true end
        if settings.showProcStacks == nil then settings.showProcStacks = true end
    end
end

local function GetDynamicDB()
    local profile = DDingUI.db.profile
    profile.dynamicIcons = profile.dynamicIcons or {}
    local db = profile.dynamicIcons

    db.iconData = db.iconData or {}
    db.ungrouped = db.ungrouped or {}
    db.groups = db.groups or {}

    return db
end

local function EnsureLoadConditions(iconData)
    EnsureIconSettings(iconData)
    iconData.settings.loadConditions = iconData.settings.loadConditions or {
        enabled = false,
        specs = {},
        inCombat = false,
        outOfCombat = false,
    }
end

-- ------------------------
-- Icon updates
-- ------------------------
local IsCooldownFrameActive

local function UpdateItemIcon(iconFrame, iconData)
    local itemID = iconData.id
    if not itemID or not iconFrame then return end

    local includeCharges = iconData.settings and iconData.settings.showCharges
    local itemCount = C_Item.GetItemCount(itemID, false, includeCharges, false)
    local activeItemID = itemID
    local usedFallback = false

    -- Fallback item logic: if primary item count is 0 and fallbackItems are configured
    if (itemCount == 0 or itemCount == nil) and iconData.settings and iconData.settings.fallbackItems then
        local fallbackItems = iconData.settings.fallbackItems
        if type(fallbackItems) == "string" and fallbackItems ~= "" then
            -- Parse comma-separated item IDs
            for fallbackID in string.gmatch(fallbackItems, "(%d+)") do
                local fID = tonumber(fallbackID)
                if fID then
                    local fCount = C_Item.GetItemCount(fID, false, includeCharges, false)
                    if fCount and fCount > 0 then
                        activeItemID = fID
                        itemCount = fCount
                        usedFallback = true
                        break
                    end
                end
            end
        end
    end

    -- Update icon texture if using fallback item
    if usedFallback then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(activeItemID)
        if itemTexture then
            iconFrame.icon:SetTexture(itemTexture)
        end
    elseif not iconFrame._originalTexture then
        -- Store original texture on first run
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
        iconFrame._originalTexture = itemTexture
    end

    -- If not using fallback, restore original texture
    if not usedFallback and iconFrame._originalTexture then
        iconFrame.icon:SetTexture(iconFrame._originalTexture)
    end

    local start, duration = GetItemCooldown(activeItemID)
    -- SetCooldown is a Blizzard widget call (safe with secret values)
    -- Do NOT compare duration > 1.5 — secret values in combat cannot be compared (WoW 12.0+)
    pcall(function()
        if start and duration then
            iconFrame.cooldown:SetCooldown(start, duration)
            if iconFrame.cooldownProbe then
                iconFrame.cooldownProbe:SetCooldown(start, duration)
            end
        else
            iconFrame.cooldown:Clear()
            if iconFrame.cooldownProbe then
                iconFrame.cooldownProbe:Clear()
            end
        end
    end)
    -- Use visibility-based check to avoid arithmetic on secret values (WoW 12.0+)
    local onCooldown = IsCooldownFrameActive(iconFrame.cooldownProbe or iconFrame.cooldown)

    if iconData.settings and iconData.settings.showCooldown == false then
        iconFrame.cooldown:Hide()
    else
        if onCooldown then
            iconFrame.cooldown:Show()
        else
            iconFrame.cooldown:Hide()
        end
    end

    if iconFrame.count then
        iconFrame.count:SetText(itemCount or 0)
        if iconData.settings and iconData.settings.showCharges == false then
            iconFrame.count:Hide()
        else
            iconFrame.count:Show()
        end
    end

    local allowCooldownDesat = not (iconData.settings and iconData.settings.desaturateOnCooldown == false)
    local allowUnusableDesat = not (iconData.settings and iconData.settings.desaturateWhenUnusable == false)

    local wantDesat = false
    local alpha = 1.0

    if itemCount == 0 or itemCount == nil then
        if allowUnusableDesat then
            wantDesat = true
            alpha = 1.0
        else
            wantDesat = allowCooldownDesat and onCooldown
            alpha = 1.0
        end
    elseif onCooldown then
        wantDesat = allowCooldownDesat
    end

    iconFrame.icon:SetDesaturated(wantDesat == true)
    iconFrame.icon:SetAlpha(alpha)
end

IsCooldownFrameActive = function(cooldownFrame)
    if not cooldownFrame then return false end
    -- Avoid arithmetic/comparisons on "secret" values; rely on the cooldown widget's own visibility.
    local ok, visible = pcall(cooldownFrame.IsVisible, cooldownFrame)
    return ok and visible == true
end

local function UpdateSpellIconFrame(iconFrame, iconData)
    local spellID = iconData.id
    if not spellID or not iconFrame then return end

    local allowDesat = not (iconData.settings and iconData.settings.desaturateOnCooldown == false)
    local allowUnusableDesat = not (iconData.settings and iconData.settings.desaturateWhenUnusable == false)
    local showGCDSwipe = (iconData.settings and iconData.settings.showGCDSwipe == true)

    -- Get cooldown info with protected call to handle secret values
    local cooldownSet = false
    local isOnCooldown = false
    local ignoreGCD = false
    local isGCDOnly = false
    local ok, cooldownInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and cooldownInfo then
        local setOk = pcall(function()
            -- Ignore GCD-only updates so we don't desaturate just for the global cooldown.
            if cooldownInfo.isOnGCD == true then
                if not showGCDSwipe then
                    iconFrame.cooldown:Clear()
                    if iconFrame.cooldownProbe then
                        iconFrame.cooldownProbe:Clear()
                    end
                    cooldownSet = false
                    ignoreGCD = true
                    return
                end
                isGCDOnly = true
            end

            if cooldownInfo.duration and cooldownInfo.startTime then
                iconFrame.cooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                if iconFrame.cooldownProbe then
                    iconFrame.cooldownProbe:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                end
                cooldownSet = true
            end
        end)
        -- Do not early-return; we still need to handle usability/desat logic
    end

    -- Fallback to old API if C_Spell failed
    local fallbackOk = pcall(function()
        if ignoreGCD then return end
        local start, duration = GetSpellCooldown(spellID)
        if start and duration then
            iconFrame.cooldown:SetCooldown(start, duration)
            if iconFrame.cooldownProbe then
                iconFrame.cooldownProbe:SetCooldown(start, duration)
            end
            cooldownSet = true
        end
    end)

    -- Clear cooldown if we couldn't set it
    if not cooldownSet then
        iconFrame.cooldown:Clear()
        if iconFrame.cooldownProbe then
            iconFrame.cooldownProbe:Clear()
        end
    end

    if iconData.settings and iconData.settings.showCooldown == false then
        iconFrame.cooldown:Hide()
    end

    -- Get charges using C_Spell API with protected call.
    -- Important: for charge spells, we only desaturate when OUT of charges (0),
    -- and we only show the swipe while a charge is recharging.
    local chargesInfo
    local chargesOk = pcall(function()
        chargesInfo = C_Spell.GetSpellCharges(spellID)
    end)
    local isChargeSpell = chargesOk and chargesInfo
    local charges = chargesOk and chargesInfo and chargesInfo.currentCharges

    -- Count display: do not compare charge values (can be secret). Just attempt to set text.
    local hasChargesText = false
    if isChargeSpell and iconData.settings and iconData.settings.showCharges == false then
        iconFrame.count:Hide()
    else
        hasChargesText = pcall(iconFrame.count.SetText, iconFrame.count, charges)
        if hasChargesText then
            iconFrame.count:Show()
        else
            iconFrame.count:SetText("")
            iconFrame.count:Hide()
        end
    end

    -- Cooldown state uses the probe so user "Hide Cooldown" doesn't affect logic.
    local cooldownActive = IsCooldownFrameActive(iconFrame.cooldownProbe or iconFrame.cooldown)
    isOnCooldown = cooldownActive and not isGCDOnly

    local rechargeActive = false
    if isChargeSpell then
        if chargesInfo.cooldownStartTime and chargesInfo.cooldownDuration then
            pcall(function()
                iconFrame.cooldown:SetCooldown(chargesInfo.cooldownStartTime, chargesInfo.cooldownDuration)
                if iconFrame.cooldownChargeProbe then
                    iconFrame.cooldownChargeProbe:SetCooldown(chargesInfo.cooldownStartTime, chargesInfo.cooldownDuration)
                end
            end)
            rechargeActive = IsCooldownFrameActive(iconFrame.cooldownChargeProbe or iconFrame.cooldown)
        else
            iconFrame.cooldown:Clear()
            if iconFrame.cooldownChargeProbe then
                iconFrame.cooldownChargeProbe:Clear()
            end
        end
    end

    -- Only show the cooldown swipe when enabled.
    if not (iconData.settings and iconData.settings.showCooldown == false) then
        if isChargeSpell then
            -- For charge recharges, avoid the dark swipe "background" fill; keep just the edge indicator.
            pcall(iconFrame.cooldown.SetSwipeColor, iconFrame.cooldown, 0, 0, 0, 0)
            pcall(iconFrame.cooldown.SetDrawEdge, iconFrame.cooldown, rechargeActive == true)
            if rechargeActive then
                iconFrame.cooldown:Show()
            else
                iconFrame.cooldown:Hide()
            end
        else
            -- Normal cooldowns use the standard dark swipe fill.
            pcall(iconFrame.cooldown.SetSwipeColor, iconFrame.cooldown, 0, 0, 0, 0.8)
            -- Do not draw an edge for normal spell cooldowns (edge reserved for charge recharge indicator).
            pcall(iconFrame.cooldown.SetDrawEdge, iconFrame.cooldown, false)
            -- If showing GCD swipes, allow display while on GCD but do not desaturate for it.
            local displayActive = cooldownActive
            if isGCDOnly and not showGCDSwipe then
                displayActive = false
            end
            if displayActive then
                iconFrame.cooldown:Show()
            else
                iconFrame.cooldown:Hide()
            end
        end
    else
        -- Cooldown hidden: ensure edge doesn't get stuck on from previous updates.
        pcall(iconFrame.cooldown.SetDrawEdge, iconFrame.cooldown, false)
    end

    -- Check usability (fallback for different WoW versions)
    local usable = false
    if C_Spell and C_Spell.IsSpellUsable then
        local okUsable, usableVal = pcall(C_Spell.IsSpellUsable, spellID)
        if okUsable then
            usable = usableVal == true
        end
    elseif IsUsableSpell then
        local okUsable, usableVal = pcall(IsUsableSpell, spellID)
        if okUsable then
            usable = usableVal == true
        end
    else
        -- Fallback: assume usable if spell exists
        usable = true
    end

    if usable then
        -- For charge spells: only desaturate when you're out of charges, which matches main cooldown active.
        local shouldDesaturate = isOnCooldown
        if allowDesat and shouldDesaturate then
            iconFrame.icon:SetDesaturated(true)
            iconFrame.icon:SetAlpha(1.0)
        else
            iconFrame.icon:SetDesaturated(false)
            iconFrame.icon:SetAlpha(1.0)
        end
    else
        if allowUnusableDesat then
            iconFrame.icon:SetDesaturated(true)
            iconFrame.icon:SetAlpha(1.0)
        else
            iconFrame.icon:SetDesaturated(false)
            iconFrame.icon:SetAlpha(1.0)
        end
    end
end

local function UpdateSlotIcon(iconFrame, iconData)
    local slotID = iconData.slotID
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID then
        iconFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        iconFrame.cooldown:Clear()
        iconFrame.count:Hide()
        return
    end

    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
    if itemTexture then
        iconFrame.icon:SetTexture(itemTexture)
    end

    local start, duration = GetInventoryItemCooldown("player", slotID)
    -- SetCooldown is a Blizzard widget call (safe with secret values)
    -- Do NOT compare duration > 1.5 — secret values in combat cannot be compared (WoW 12.0+)
    pcall(function()
        if start and duration then
            iconFrame.cooldown:SetCooldown(start, duration)
            if iconFrame.cooldownProbe then
                iconFrame.cooldownProbe:SetCooldown(start, duration)
            end
        else
            iconFrame.cooldown:Clear()
            if iconFrame.cooldownProbe then
                iconFrame.cooldownProbe:Clear()
            end
        end
    end)
    -- Use visibility-based check to avoid arithmetic on secret values (WoW 12.0+)
    local onCooldown = IsCooldownFrameActive(iconFrame.cooldownProbe or iconFrame.cooldown)

    if iconData.settings and iconData.settings.showCooldown == false then
        iconFrame.cooldown:Hide()
    else
        if onCooldown then
            iconFrame.cooldown:Show()
        else
            iconFrame.cooldown:Hide()
        end
    end

    local allowDesat = not (iconData.settings and iconData.settings.desaturateOnCooldown == false)
    if allowDesat and onCooldown then
        iconFrame.icon:SetDesaturated(true)
    else
        iconFrame.icon:SetDesaturated(false)
    end
end

local function UpdateTrinketProcIcon(iconFrame, iconData)
    local slotID = iconData.slotID
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID then
        iconFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        iconFrame.cooldown:Clear()
        iconFrame.count:Hide()
        return
    end

    -- Update trinket item texture
    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
    if itemTexture then
        iconFrame.icon:SetTexture(itemTexture)
    end

    -- Determine proc spell ID (auto-detect or manual override)
    local settings = iconData.settings or {}
    local procSpellID = settings.procSpellID

    -- [12.0.1] Secret value safe comparison (procSpellID > 0 can error with secret values)
    local hasProcID = false
    pcall(function() hasProcID = procSpellID and procSpellID > 0 end)

    if not hasProcID then
        pcall(function()
            local spellName, spellID = C_Item.GetItemSpell(itemID)
            procSpellID = spellID
        end)
        pcall(function() hasProcID = procSpellID and procSpellID > 0 end)
    end

    -- [REFACTOR] 3-method buff detection for on-use trinket compatibility
    -- Method A: Direct spell ID → Method B: Cached buff ID → Method C: Name scan
    local procActive = false
    local auraData = nil

    if hasProcID then
        -- Method A: Direct spell ID lookup (O(1), handles most trinkets)
        pcall(function()
            auraData = C_UnitAuras.GetPlayerAuraBySpellID(procSpellID)
        end)

        -- Method B: Cached buff spell ID from previous successful name scan (O(1))
        if not auraData and iconFrame._cachedBuffSpellID then
            pcall(function()
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconFrame._cachedBuffSpellID)
            end)
            if not auraData then
                iconFrame._cachedBuffSpellID = nil  -- cache invalidation
            end
        end

        -- Method C: Spell name scan (on-use trinkets where cast spell ID ≠ buff spell ID)
        if not auraData then
            pcall(function()
                local spellInfo = C_Spell.GetSpellInfo(procSpellID)
                if spellInfo and spellInfo.name then
                    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(a)
                        if a and a.name == spellInfo.name then
                            auraData = a
                            -- Cache actual buff spell ID for fast future lookups
                            if a.spellId and a.spellId ~= procSpellID then
                                iconFrame._cachedBuffSpellID = a.spellId
                            end
                            return true  -- stop iteration
                        end
                    end)
                end
            end)
        end
    end

    if auraData then
        procActive = true
        -- Show proc buff duration via CooldownFrame
        if settings.showProcDuration ~= false then
            pcall(function()
                local startTime = auraData.expirationTime - auraData.duration
                iconFrame.cooldown:SetCooldown(startTime, auraData.duration)
            end)
            if settings.showCooldown ~= false then
                iconFrame.cooldown:Show()
            end
        end
        -- Show stack count
        if settings.showProcStacks ~= false then
            local stacks = auraData.applications or 0
            if stacks > 1 then
                iconFrame.count:SetText(stacks)
                iconFrame.count:Show()
            else
                iconFrame.count:Hide()
            end
        end
        iconFrame.icon:SetDesaturated(false)
    end

    -- 2. Proc not active → show item cooldown as fallback
    if not procActive then
        if settings.showItemCooldown ~= false then
            local start, duration = GetInventoryItemCooldown("player", slotID)
            pcall(function()
                if start and duration then
                    iconFrame.cooldown:SetCooldown(start, duration)
                    if iconFrame.cooldownProbe then
                        iconFrame.cooldownProbe:SetCooldown(start, duration)
                    end
                else
                    iconFrame.cooldown:Clear()
                    if iconFrame.cooldownProbe then
                        iconFrame.cooldownProbe:Clear()
                    end
                end
            end)
            local onCooldown = IsCooldownFrameActive(iconFrame.cooldownProbe or iconFrame.cooldown)
            if settings.showCooldown ~= false and onCooldown then
                iconFrame.cooldown:Show()
            else
                iconFrame.cooldown:Hide()
            end
            local allowDesat = not (settings.desaturateOnCooldown == false)
            if allowDesat and onCooldown then
                iconFrame.icon:SetDesaturated(true)
            else
                iconFrame.icon:SetDesaturated(false)
            end
        else
            iconFrame.cooldown:Clear()
            iconFrame.cooldown:Hide()
            iconFrame.icon:SetDesaturated(false)
        end
        iconFrame.count:Hide()
    end
end

local function SafeSetBackdrop(frame, backdropInfo, borderColor)
    if not frame or not frame.SetBackdrop then return end
        if InCombatLockdown() then
            if not DDingUI.__cdmPendingBackdrops then
                DDingUI.__cdmPendingBackdrops = {}
            end
        DDingUI.__cdmPendingBackdrops[frame] = {backdropInfo = backdropInfo, borderColor = borderColor}
            if not DDingUI.__cdmBackdropEventFrame then
                local eventFrame = CreateFrame("Frame")
                eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:SetScript("OnEvent", function()
                for pending, settings in pairs(DDingUI.__cdmPendingBackdrops) do
                    if pending and pending.SetBackdrop then
                        pcall(pending.SetBackdrop, pending, settings.backdropInfo)
                                        if settings.borderColor then
                            pcall(pending.SetBackdropBorderColor, pending, unpack(settings.borderColor))
                        end
                            end
                        end
                        DDingUI.__cdmPendingBackdrops = {}
                end)
                DDingUI.__cdmBackdropEventFrame = eventFrame
            end
        return
    end

    pcall(frame.SetBackdrop, frame, backdropInfo)
    if borderColor then
        pcall(frame.SetBackdropBorderColor, frame, unpack(borderColor))
    end
end

local function ApplyIconBorder(iconFrame, settings)
    if not iconFrame or not iconFrame.border then return end
    local edgeSize = settings.borderSize or 0
    if edgeSize <= 0 then
        ShowTextureBorder(iconFrame.border, false)
        iconFrame.border:Hide()
        return
    end

    -- Use texture-based borders (no SetBackdrop = no taint)
    local borderColor = settings.borderColor or {0, 0, 0, 1}
    if not iconFrame.border.__dduiBorders then
        CreateTextureBorder(iconFrame.border, edgeSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    else
        UpdateTextureBorderSize(iconFrame.border, edgeSize)
        UpdateTextureBorderColor(iconFrame.border, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    end
    ShowTextureBorder(iconFrame.border, true)
    iconFrame.border:Show()
end

local function BuildCountSettings(iconSettings)
    local cs = iconSettings.countSettings or {}
    return {
        size = cs.size or 16,
        anchor = cs.anchor or "BOTTOMRIGHT",
        offsetX = cs.offsetX or -2,
        offsetY = cs.offsetY or 2,
        color = cs.color or {1, 1, 1, 1},
        font = cs.font,  -- Font name from LSM, nil means use global font
    }
end

local function ApplyCooldownTextStyle(cooldown, iconData)
    if not cooldown or not cooldown.GetRegions then return end

    local fontString
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            fontString = region
            break
        end
    end
    if not fontString then return end

    local cds = (iconData.settings and iconData.settings.cooldownSettings) or {}
    local fontPath = DDingUI:GetGlobalFont()
    local size = cds.size or 12
    local color = cds.color or { 1, 1, 1, 1 }

    -- Reuse general viewer shadow offsets for consistency
    local shadowOffsetX = 1
    local shadowOffsetY = -1
    if DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.viewers and DDingUI.db.profile.viewers.general then
        shadowOffsetX = DDingUI.db.profile.viewers.general.cooldownShadowOffsetX or shadowOffsetX
        shadowOffsetY = DDingUI.db.profile.viewers.general.cooldownShadowOffsetY or shadowOffsetY
    end

    local _, _, flags = fontString:GetFont()
    fontString:SetFont(fontPath, size, flags)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fontString:SetShadowOffset(shadowOffsetX, shadowOffsetY)
end

local function ApplyAspectRatioCrop(texture, aspect, baseZoom)
    if not texture or not texture.SetTexCoord then return end

    aspect = tonumber(aspect) or 1.0
    if aspect <= 0 then aspect = 1.0 end

    baseZoom = tonumber(baseZoom) or 0
    if baseZoom < 0 then baseZoom = 0 end
    if baseZoom > 0.499 then baseZoom = 0.499 end

    local left, right, top, bottom = baseZoom, 1 - baseZoom, baseZoom, 1 - baseZoom
    local regionW = right - left
    local regionH = bottom - top

    if regionW > 0 and regionH > 0 and aspect ~= 1.0 then
        local currentRatio = regionW / regionH
        if aspect > currentRatio then
            local desiredH = regionW / aspect
            local cropH = (regionH - desiredH) / 2
            top = top + cropH
            bottom = bottom - cropH
        elseif aspect < currentRatio then
            local desiredW = regionH * aspect
            local cropW = (regionW - desiredW) / 2
            left = left + cropW
            right = right - cropW
        end
    end

    texture:SetTexCoord(left, right, top, bottom)
end

local function ApplyIconSettings(iconFrame, iconData, groupSettings)
    EnsureIconSettings(iconData)
    local settings = iconData.settings or {}
    -- Use icon's own size if useOwnSize is true, otherwise fall back to group size, then default
    local size
    if settings.useOwnSize then
        size = settings.iconSize or DEFAULT_ICON_SETTINGS.iconSize
    else
        size = settings.iconSize or (groupSettings and groupSettings.iconSize) or DEFAULT_ICON_SETTINGS.iconSize
    end
    local aspect = settings.aspectRatio or 1.0
    local width = size
    local height = size
    if aspect > 1.0 then
        height = size / aspect
    elseif aspect < 1.0 then
        width = size * aspect
    end
    -- [FIX] DynamicIconBridge 관리 아이콘은 GroupSystem이 크기를 관리하므로 건너뜀
    -- CustomIcons의 aspectRatio와 GroupSystem의 aspectRatioCrop이 다르면
    -- SetSize → snap-back 훅 → 1프레임 깜빡임 발생 방지
    if not iconFrame._ddIsManaged then
        iconFrame:SetSize(width, height)
    end

    if iconFrame.icon and not iconFrame._ddIsManaged then
        iconFrame.icon:ClearAllPoints()
        iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
        iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
        -- Mirror CooldownViewer behavior: crop instead of stretching when aspect ratio changes.
        ApplyAspectRatioCrop(iconFrame.icon, aspect, 0.08)
    end

    ApplyIconBorder(iconFrame, {
        borderSize = settings.borderSize or DEFAULT_ICON_SETTINGS.borderSize,
        borderColor = settings.borderColor or DEFAULT_ICON_SETTINGS.borderColor,
    })

    local cs = BuildCountSettings(settings)
    local fontPath = DDingUI:GetGlobalFont()
    if cs.font and LSM then
        local fetchedFont = LSM:Fetch("font", cs.font)
        if fetchedFont then
            fontPath = fetchedFont
        end
    end
    iconFrame.count:SetFont(fontPath, cs.size, "OUTLINE")
    if cs.color then
        iconFrame.count:SetTextColor(unpack(cs.color))
    end
    iconFrame.count:ClearAllPoints()
    iconFrame.count:SetPoint(cs.anchor, iconFrame, cs.anchor, cs.offsetX, cs.offsetY)

    -- Apply cooldown text settings
    local cooldownSettings = settings.cooldownSettings or {size = 12, color = {1, 1, 1, 1}}
    if iconFrame.cooldown.SetCountdownFont then
        local cdFontPath = DDingUI:GetGlobalFont()
        iconFrame.cooldown:SetCountdownFont(cdFontPath, cooldownSettings.size, "OUTLINE")
    end
    ApplyCooldownTextStyle(iconFrame.cooldown, iconData)
    -- Note: Cooldown text color is not directly controllable with standard WoW cooldown frames.
    -- The color setting is saved but may not be applied depending on WoW API limitations.
end

-- ------------------------
-- Event-based update system
-- ------------------------
local function UpdateAllIcons()
    -- Update all active icon frames
    for iconKey, frame in pairs(runtime.iconFrames) do
        if frame and frame:IsVisible() then
            local db = GetDynamicDB()
            local iconData = db.iconData[iconKey]
            if iconData then
                -- Group settings will be applied via frame._groupSettings if available
                ApplyIconSettings(frame, iconData, frame._groupSettings)
                if iconData.type == "item" then
                    UpdateItemIcon(frame, iconData)
                elseif iconData.type == "spell" then
                    UpdateSpellIconFrame(frame, iconData)
                elseif iconData.type == "slot" then
                    UpdateSlotIcon(frame, iconData)
                elseif iconData.type == "trinketProc" then
                    UpdateTrinketProcIcon(frame, iconData)
                end
            end
        end
    end
end

local function HandleCooldownDone(cooldownFrame)
    local parent = cooldownFrame and cooldownFrame:GetParent()
    local iconKey = parent and parent._iconKey
    if iconKey and runtime.UpdateDynamicIcon then
        runtime.UpdateDynamicIcon(iconKey)
        return
    end
    UpdateAllIcons()
end

local function ScheduleSpecReload()
    if runtime.pendingSpecReload then return end
    runtime.pendingSpecReload = true

    C_Timer.After(0.05, function()
        runtime.pendingSpecReload = false
        if CustomIcons and CustomIcons.LoadDynamicIcons then
            CustomIcons:LoadDynamicIcons()
        else
            if RefreshAllLayouts then RefreshAllLayouts() end
            UpdateAllIcons()
        end
    end)
end

local function EnsureEventFrame()
    if runtime.eventFrame then return end
    runtime.eventFrame = CreateFrame("Frame")

    -- Register for events that should trigger icon updates
    runtime.eventFrame:RegisterEvent("BAG_UPDATE")                    -- Bag contents change
    runtime.eventFrame:RegisterEvent("ITEM_COUNT_CHANGED")             -- Item counts change
    runtime.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")          -- Spell cooldowns change
    runtime.eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")           -- Spell charges change
    runtime.eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")            -- Spells become usable/unusable (often at cooldown end)
    runtime.eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")      -- Cooldown updates (reliable at cooldown end)
    runtime.eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")         -- Equipment changes
    runtime.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")       -- Equipment changes (alternative event)
    runtime.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")  -- Spec change
    runtime.eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")   -- Talent group/spec change (alternative event)
    runtime.eventFrame:RegisterEvent("SPELLS_CHANGED")                -- Spellbook changes (often after spec change)
    runtime.eventFrame:RegisterEvent("UNIT_AURA")                      -- Trinket proc buff tracking

    runtime.eventFrame:SetScript("OnEvent", function(self, event, ...)
        local arg1 = ...

        -- Only update for events that affect the player
        if event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_AURA" then
            if arg1 ~= "player" then return end
        end

        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
            return
        end

        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "SPELLS_CHANGED" then
            ScheduleSpecReload()
            return
        end

        -- Update all icons when relevant events fire
        UpdateAllIcons()
    end)
end

-- ------------------------
-- Visual helpers
-- ------------------------
local function GetAnchorFrame(anchorName)
    if not anchorName or anchorName == "" then
        return UIParent
    end
    return _G[anchorName] or UIParent
end

local function IsSpellInPlayerBook(spellID)
    if not spellID then return false end

    -- Use the new Dragonflight API that checks if spell is actually known for current spec
    -- Includes handling of spell overrides/replacements
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.FindBaseSpellByID and C_SpellBook.FindSpellOverrideByID and Enum and Enum.SpellBookSpellBank then
        local bank = Enum.SpellBookSpellBank.Player

        -- Direct check first
        local ok, result = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
        if ok and result then
            return true
        end

        -- Check base spell if this might be an override
        ok, result = pcall(C_SpellBook.FindBaseSpellByID, spellID)
        if ok and result and result ~= spellID then
            ok, result = pcall(C_SpellBook.IsSpellKnown, result, bank)
            if ok and result then
                return true
            end
        end

        -- Check override spell if this might be a base
        ok, result = pcall(C_SpellBook.FindSpellOverrideByID, spellID)
        if ok and result and result ~= spellID then
            ok, result = pcall(C_SpellBook.IsSpellKnown, result, bank)
            if ok and result then
                return true
            end
        end

        return false
    end

    -- Fallback to old API for backward compatibility
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, result = pcall(C_SpellBook.IsSpellInSpellBook, spellID)
        if ok then
            return result == true
        end
    end

    -- Fallback: assume available if API missing/failed
    return true
end

local function IsIconLoadable(iconData)
    if not iconData then return false end
    if iconData.type == "spell" then
        return IsSpellInPlayerBook(iconData.id)
    end
    return true
end

-- (moved above UpdateSpellIconFrame via forward declaration)

local function GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local id = GetSpecializationInfo(specIndex)
        return id
    end
    return nil
end

local function ShouldIconSpawn(iconData)
    if not iconData then return false end
    -- Spellbook gating
    if iconData.type == "spell" and not IsSpellInPlayerBook(iconData.id) then
        return false
    end

    EnsureLoadConditions(iconData)
    local lc = iconData.settings.loadConditions or {}
    if not lc.enabled then
        return true
    end


    -- Spec conditions
    if lc.specs then
        local anySpecSet = false
        for _, v in pairs(lc.specs) do
            if v then anySpecSet = true break end
        end
        if anySpecSet then
            local currentSpec = GetCurrentSpecID()
            if not currentSpec or not lc.specs[currentSpec] then
                return false
            end
        end
    end

    return true
end

local function ResolveAnchorPoints(anchorPoint)
    if anchorPoint == "TOPLEFT" then
        return "BOTTOMLEFT", "TOPLEFT"
    elseif anchorPoint == "TOPRIGHT" then
        return "BOTTOMRIGHT", "TOPRIGHT"
    elseif anchorPoint == "BOTTOMLEFT" then
        return "TOPLEFT", "BOTTOMLEFT"
    elseif anchorPoint == "BOTTOMRIGHT" then
        return "TOPRIGHT", "BOTTOMRIGHT"
    elseif anchorPoint == "TOP" then
        return "BOTTOM", "TOP"
    elseif anchorPoint == "BOTTOM" then
        return "TOP", "BOTTOM"
    elseif anchorPoint == "LEFT" then
        return "RIGHT", "LEFT"
    elseif anchorPoint == "RIGHT" then
        return "LEFT", "RIGHT"
    end
    return "CENTER", "CENTER"
end

function CustomIcons:ShowLoadConditionsWindow(iconKey, iconData)
    EnsureLoadConditions(iconData)
    -- If a window already exists, discard it and rebuild to guarantee fresh bindings
    if uiFrames.loadWindow then
        uiFrames.loadWindow:Hide()
        uiFrames.loadWindow = nil
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
    f:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.95)
    f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
    f.title:SetShadowOffset(1, -1)
    f.title:SetShadowColor(0, 0, 0, 1)
    f.title:SetPoint("TOP", f, "TOP", 0, -10)
    f.title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
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
    f.close:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
    f.close:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
    local closeText = f.close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
    closeText:SetShadowOffset(1, -1)
    closeText:SetShadowColor(0, 0, 0, 1)
    closeText:SetPoint("CENTER", 0, 1)
    closeText:SetText("×")
    closeText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    f.close:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.8, 0.2, 0.2, 1)
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
        closeText:SetTextColor(1, 1, 1, 1)
    end)
    f.close:SetScript("OnLeave", function(self)
        self:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
        self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        closeText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
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
    enableBtn:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
    enableBtn:SetBackdropBorderColor(0, 0, 0, 1)
    local enableCheck = enableBtn:CreateTexture(nil, "OVERLAY")
    enableCheck:SetPoint("TOPLEFT", 1, -1)
    enableCheck:SetPoint("BOTTOMRIGHT", -1, 1)
    enableCheck:SetGradient("HORIZONTAL",
        CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),
        CreateColor(THEME.accentDark[1], THEME.accentDark[2], THEME.accentDark[3], 1))
    enableBtn:SetCheckedTexture(enableCheck)
    local enableHighlight = enableBtn:CreateTexture(nil, "ARTWORK")
    enableHighlight:SetAllPoints()
    enableHighlight:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.1)
    enableBtn:SetHighlightTexture(enableHighlight, "ADD")
    local enableLabel = enableBtn:CreateFontString(nil, "OVERLAY")
    enableLabel:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
    enableLabel:SetShadowOffset(1, -1)
    enableLabel:SetShadowColor(0, 0, 0, 1)
    enableLabel:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
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
    specHeader:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
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

    if CreateCustomScrollBar then
        local specScrollBar = CreateCustomScrollBar(f, specScroll)
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
        name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
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
        toggle:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
        toggle:SetBackdropBorderColor(0, 0, 0, 1)
        local toggleCheck = toggle:CreateTexture(nil, "OVERLAY")
        toggleCheck:SetPoint("TOPLEFT", 1, -1)
        toggleCheck:SetPoint("BOTTOMRIGHT", -1, 1)
        toggleCheck:SetGradient("HORIZONTAL",
            CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),
            CreateColor(THEME.accentDark[1], THEME.accentDark[2], THEME.accentDark[3], 1))
        toggle:SetCheckedTexture(toggleCheck)
        local toggleHL = toggle:CreateTexture(nil, "ARTWORK")
        toggleHL:SetAllPoints()
        toggleHL:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.1)
        toggle:SetHighlightTexture(toggleHL, "ADD")
        toggle:SetChecked(lc.specs[spec.id] == true)
        toggle:SetScript("OnClick", function(self)
            lc.specs[spec.id] = self:GetChecked() or false
            if RefreshAllLayouts then RefreshAllLayouts() end
        end)

        y = y + 28
    end
    specChild:SetHeight(y)

    uiFrames.loadWindow = f
end

-- ------------------------
-- Base icon creation
-- ------------------------
local function CreateBaseIcon(name, parent)
    local frame = CreateFrame("Button", name, parent, "BackdropTemplate")
    frame:SetSize(40, 40)
    
    -- [FIX] ARTWORK 레이어 사용: BackdropTemplate의 backdrop이 BACKGROUND 레이어를 차지하므로
    -- BACKGROUND에 icon을 만들면 backdrop에 가려져 투명하게 보임
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Border frame (texture-based, no SetBackdrop = no taint)
    local border = CreateFrame("Frame", nil, frame)
    border:SetFrameLevel(frame:GetFrameLevel() + 1)
    border:SetAllPoints(frame)
    border:Hide()
    
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints(frame)
    cd:SetFrameLevel(frame:GetFrameLevel() + 1)
    -- Edge highlight is enabled dynamically (e.g. charge recharge), default off.
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd:SetHideCountdownNumbers(false)
    cd:SetReverse(false)

    -- Probe cooldown: used for cooldown-state checks without being affected by user "Hide Cooldown" setting.
    local cdProbe = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cdProbe:SetAllPoints(frame)
    cdProbe:SetDrawEdge(false)
    cdProbe:SetDrawSwipe(true)
    cdProbe:SetSwipeColor(0, 0, 0, 0)
    cdProbe:SetHideCountdownNumbers(true)
    cdProbe:SetReverse(false)
    cdProbe:SetAlpha(0)

    -- Charge probe: used to detect whether a charge is recharging (show swipe) without affecting main cooldown state.
    local cdChargeProbe = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cdChargeProbe:SetAllPoints(frame)
    cdChargeProbe:SetDrawEdge(false)
    cdChargeProbe:SetDrawSwipe(true)
    cdChargeProbe:SetSwipeColor(0, 0, 0, 0)
    cdChargeProbe:SetHideCountdownNumbers(true)
    cdChargeProbe:SetReverse(false)
    cdChargeProbe:SetAlpha(0)

    cd:SetScript("OnCooldownDone", HandleCooldownDone)
    cdProbe:SetScript("OnCooldownDone", HandleCooldownDone)
    cdChargeProbe:SetScript("OnCooldownDone", HandleCooldownDone)
    
    local countLayer = CreateFrame("Frame", nil, frame)
    countLayer:SetFrameLevel(frame:GetFrameLevel() + 2)
    countLayer:SetAllPoints(frame)

    local count = countLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetJustifyH("RIGHT")
    count:SetTextColor(1, 1, 1, 1)
    count:SetShadowOffset(0, 0)
    count:SetShadowColor(0, 0, 0, 1)

    frame.icon = icon
    frame.cooldown = cd
    frame.cooldownProbe = cdProbe
    frame.cooldownChargeProbe = cdChargeProbe
    frame.count = count
    frame.border = border
    
    frame:EnableMouse(true)
    return frame
end

-- ------------------------
-- Icon creation per type
-- ------------------------
local function CreateItemIcon(iconKey, iconData, parent)
    local itemID = iconData.id
    if not itemID then return nil end

    -- [FIX] Ayije 방식: 프레임은 항상 생성, 텍스처만 나중에 업데이트
    -- GetItemInfo가 nil이어도 프레임은 만들어야 GroupSystem이 추적 가능
    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
    if not itemName then
        C_Item.RequestLoadItemDataByID(itemID)
    end

    local frame = CreateBaseIcon("DDingUI_DynItem_" .. iconKey, parent)
    frame._type = "item"
    frame._itemID = itemID
    frame._iconKey = iconKey
    frame.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    return frame
end

local function CreateSpellIcon(iconKey, iconData, parent)
    local spellID = iconData.id
    if not spellID then return nil end
    -- [FIX] 스펠북 체크는 IsIconActive에서 하므로 여기서는 프레임만 생성
    -- 유저가 추가한 스펠이 현재 특성에 없더라도 프레임은 존재해야 함

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo then
        if C_Spell.RequestLoadSpellData then
            C_Spell.RequestLoadSpellData(spellID)
        end
    end

    local frame = CreateBaseIcon("DDingUI_DynSpell_" .. iconKey, parent)
    frame._type = "spell"
    frame._spellID = spellID
    frame._iconKey = iconKey
    local tex = (spellInfo and spellInfo.iconID) or (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
    frame.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    return frame
end

local function CreateSlotIcon(iconKey, iconData, parent)
    local slotID = iconData.slotID
    if not slotID then return nil end

    local prefix = (iconData.type == "trinketProc") and "DDingUI_DynTrinket_" or "DDingUI_DynSlot_"
    local frame = CreateBaseIcon(prefix .. iconKey, parent)
    frame._type = iconData.type or "slot"
    frame._slotID = slotID
    frame._iconKey = iconKey

    -- [FIX] 텍스처 항상 설정 — GetItemInfo 캐시 미스 시에도 아이콘 보이도록
    local itemID = GetInventoryItemID("player", slotID)
    local tex = nil
    if itemID then
        -- GetItemInfo보다 GetInventoryItemTexture가 더 신뢰할 수 있음 (캐시 불필요)
        tex = GetInventoryItemTexture("player", slotID)
        if not tex then
            local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            tex = itemTexture
        end
        if not tex then
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    frame.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    return frame
end

local function CreateDynamicIcon(iconKey, iconData, parent)
    if iconData.type == "item" then
        return CreateItemIcon(iconKey, iconData, parent)
    elseif iconData.type == "spell" then
        return CreateSpellIcon(iconKey, iconData, parent)
    elseif iconData.type == "slot" then
        return CreateSlotIcon(iconKey, iconData, parent)
    elseif iconData.type == "trinketProc" then
        return CreateSlotIcon(iconKey, iconData, parent)  -- Reuse slot icon frame
    end
    return nil
end

local function UpdateDynamicIcon(iconKey)
    local db = GetDynamicDB()
    local iconData = db.iconData[iconKey]
    local frame = runtime.iconFrames[iconKey]
    if not iconData or not frame then return end

    -- Group settings are stored on the frame during LayoutGroup
    ApplyIconSettings(frame, iconData, frame._groupSettings)
    if iconData.type == "item" then
        UpdateItemIcon(frame, iconData)
    elseif iconData.type == "spell" then
        UpdateSpellIconFrame(frame, iconData)
    elseif iconData.type == "slot" then
        UpdateSlotIcon(frame, iconData)
    elseif iconData.type == "trinketProc" then
        UpdateTrinketProcIcon(frame, iconData)
    end
end

runtime.UpdateDynamicIcon = UpdateDynamicIcon

-- ------------------------
-- Group layout
-- ------------------------
local function GetStartAnchorForGrowth(growth)
    if growth == "LEFT" then
        return "TOPRIGHT"
    elseif growth == "UP" then
        return "BOTTOMLEFT"
    end
    return "TOPLEFT"
end

local function GetDefaultRowGrowth(growth)
    if growth == "LEFT" or growth == "RIGHT" then
        return "DOWN"
    end
    return "RIGHT"
end

local function NormalizeRowGrowth(growth, rowGrowth)
    if growth == "LEFT" or growth == "RIGHT" then
        if rowGrowth ~= "UP" and rowGrowth ~= "DOWN" then
            return "DOWN"
        end
        return rowGrowth
    end
    if rowGrowth ~= "LEFT" and rowGrowth ~= "RIGHT" then
        return "RIGHT"
    end
    return rowGrowth
end

local function GetStartAnchorForGrowthPair(growth, rowGrowth)
    local g = growth or "RIGHT"
    local rg = NormalizeRowGrowth(g, rowGrowth or GetDefaultRowGrowth(g))

    local top = (g == "LEFT" or g == "RIGHT" or rg == "DOWN")
    local left = (g == "RIGHT" or rg == "RIGHT")

    if top and left then return "TOPLEFT" end
    if top and not left then return "TOPRIGHT" end
    if not top and left then return "BOTTOMLEFT" end
    return "BOTTOMRIGHT"
end

local function BuildDefaultSettings(growth)
    local g = growth or "RIGHT"
    local rg = NormalizeRowGrowth(g, GetDefaultRowGrowth(g))
    local startAnchor = GetStartAnchorForGrowthPair(g, rg)
    return {
        growthDirection = g,
        rowGrowthDirection = rg,
        anchorFrom = startAnchor,
        anchorTo = startAnchor,
        spacing = 5,
        iconSize = 40,
        maxIconsPerRow = 10,
        position = {x = 0, y = -200},
    }
end

local function BuildDefaultUngroupedPositionSettings()
    local settings = BuildDefaultSettings("RIGHT")
    settings.anchorFrom = "CENTER"
    settings.anchorTo = "CENTER"
    settings.position = { x = 0, y = 0 }
    return settings
end

local function NormalizeAnchor(settings)
    if not settings then return end
    if settings.anchorPoint and not settings.anchorFrom and not settings.anchorTo then
        settings.anchorFrom = settings.anchorPoint
        settings.anchorTo = settings.anchorPoint
        settings.anchorPoint = nil
    end
    if settings.anchorPoint then
        settings.anchorPoint = nil
    end
    settings.rowGrowthDirection = settings.rowGrowthDirection or GetDefaultRowGrowth(settings.growthDirection or "RIGHT")
    settings.rowGrowthDirection = NormalizeRowGrowth(settings.growthDirection or "RIGHT", settings.rowGrowthDirection)
    if settings.maxIconsPerRow == nil and settings.maxColumns ~= nil then
        settings.maxIconsPerRow = settings.maxColumns
        settings.maxColumns = nil
    end
    settings.anchorFrom = settings.anchorFrom or GetStartAnchorForGrowthPair(settings.growthDirection or "RIGHT", settings.rowGrowthDirection)
    settings.anchorTo = settings.anchorTo or settings.anchorFrom
end

local function GetGroupSettings(groupKey)
    local db = GetDynamicDB()
    if groupKey == "ungrouped" then
        db.ungroupedSettings = db.ungroupedSettings or BuildDefaultSettings("RIGHT")
        NormalizeAnchor(db.ungroupedSettings)
        return db.ungroupedSettings
    end
    if db.iconData[groupKey] and db.ungrouped[groupKey] then
        db.ungroupedPositions = db.ungroupedPositions or {}
        db.ungroupedPositions[groupKey] = db.ungroupedPositions[groupKey] or BuildDefaultUngroupedPositionSettings()
        NormalizeAnchor(db.ungroupedPositions[groupKey])
        return db.ungroupedPositions[groupKey]
    end
    if db.groups[groupKey] then
        db.groups[groupKey].settings = db.groups[groupKey].settings or BuildDefaultSettings(db.groups[groupKey].growthDirection or "RIGHT")
        NormalizeAnchor(db.groups[groupKey].settings)
        return db.groups[groupKey].settings
    end
    local defaults = BuildDefaultSettings("RIGHT")
    NormalizeAnchor(defaults)
    return defaults
end

local function GetGroupDisplayName(groupKey)
    if groupKey == "ungrouped" then
        return L["Ungrouped"] or "Ungrouped"
    end
    local db = GetDynamicDB()
    if db.iconData[groupKey] and db.ungrouped[groupKey] then
        local iconData = db.iconData[groupKey]
        if iconData then
            if iconData.type == "item" then
                return GetItemInfo(iconData.id) or ((L["Item"] or "Item") .. " " .. iconData.id)
            elseif iconData.type == "spell" then
                local info = C_Spell.GetSpellInfo(iconData.id)
                return (info and info.name) or ((L["Spell"] or "Spell") .. " " .. iconData.id)
            elseif iconData.type == "slot" then
                return ((L["Slot"] or "Slot") .. " " .. (iconData.slotID or ""))
            elseif iconData.type == "trinketProc" then
                local iid = GetInventoryItemID("player", iconData.slotID or 13)
                local itemName = iid and GetItemInfo(iid)
                return itemName or ("Trinket " .. (iconData.slotID == 14 and "2" or "1"))
            end
        end
    end
    local group = db.groups[groupKey]
    if group and group.name and group.name ~= "" then
        return group.name
    end
    return groupKey
end

local function EnsureGroupFrame(groupKey, settings)
    settings = settings or GetGroupSettings(groupKey)
    NormalizeAnchor(settings)
    if runtime.groupFrames[groupKey] then
        return runtime.groupFrames[groupKey]
    end

    -- Create the main container frame
    local container = CreateFrame("Frame", "DDingUI_DynGroup_" .. groupKey, UIParent)
    container:SetSize(100, 100) -- Initial size, will be recalculated
    container:SetMovable(true) -- Container itself must be movable
    container:SetClampedToScreen(true)

    -- Note: Legacy anchor system removed - Movers system (/dduimove) handles positioning

    container._settings = settings
    container._groupKey = groupKey

    -- Position the container
    if settings.position then
        local anchorFrame = GetAnchorFrame(settings.anchorFrame)
        local containerPoint = settings.anchorFrom or GetStartAnchorForGrowth(settings.growthDirection or "RIGHT")
        local anchorPoint = settings.anchorTo or containerPoint
        container:ClearAllPoints()
        container:SetPoint(containerPoint, anchorFrame, anchorPoint, settings.position.x or 0, settings.position.y or 0)
    else
        local containerPoint = GetStartAnchorForGrowth(settings.growthDirection or "RIGHT")
        container:SetPoint(containerPoint, UIParent, containerPoint, 0, -200)
    end

    runtime.groupFrames[groupKey] = container
    return container
end

local function LayoutGroup(groupKey, iconKeys)
    -- [DYNAMIC] GroupSystem이 활성이면 레이아웃 스킵 (GroupRenderer가 대신 처리)
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        return
    end
    local db = GetDynamicDB()
    local groupSettings = GetGroupSettings(groupKey)
    local growth = groupSettings.growthDirection or "RIGHT"
    local settings = groupSettings
    growth = settings.growthDirection or growth
    settings.rowGrowthDirection = settings.rowGrowthDirection or GetDefaultRowGrowth(growth)
    settings.rowGrowthDirection = NormalizeRowGrowth(growth, settings.rowGrowthDirection)

    if not iconKeys or #iconKeys == 0 then
        local container = runtime.groupFrames[groupKey]
        if container then
            container:Hide()
        end
        return
    end

    local container = EnsureGroupFrame(groupKey, settings)
    container:Show()

    local spacing = settings.spacing or 5
    local maxPerRow = settings.maxIconsPerRow
    if maxPerRow == nil and settings.maxColumns ~= nil then
        maxPerRow = settings.maxColumns
        settings.maxIconsPerRow = maxPerRow
        settings.maxColumns = nil
    end
    maxPerRow = maxPerRow or 10

    local iconSizes = {}

    for _, iconKey in ipairs(iconKeys) do
        local iconFrame = runtime.iconFrames[iconKey]
        if iconFrame then
            local iconData = db.iconData[iconKey]
            local borderSize = 0
            -- Store group settings on the frame for later use (UpdateDynamicIcon, UpdateAllIcons)
            iconFrame._groupSettings = groupSettings
            if iconData then
                ApplyIconSettings(iconFrame, iconData, groupSettings)
                borderSize = math.max((iconData.settings and iconData.settings.borderSize) or 0, 0)
            end
            local w, h = iconFrame:GetWidth(), iconFrame:GetHeight()
            table.insert(iconSizes, {width = w + borderSize * 2, height = h + borderSize * 2, border = borderSize})
        end
    end

    local startAnchor = GetStartAnchorForGrowthPair(growth, settings.rowGrowthDirection)

    local function borderInsetForAnchor(anchor, border)
        if not border or border <= 0 then return 0, 0 end
        local dx = (anchor:find("LEFT") and border) or -border
        local dy = (anchor:find("TOP") and -border) or border
        return dx, dy
    end

    -- Layout in offsets relative to container startAnchor (x right+, y up+)
    local positions = {}
    local minLeft, maxRight = 0, 0
    local minBottom, maxTop = 0, 0

    local rowBaseX, rowBaseY = 0, 0
    local along = 0
    local rowThickness = 0
    local countInRow = 0
    local iconGrowthIsHorizontal = (growth == "LEFT" or growth == "RIGHT")

    local function advanceRow()
        local step = rowThickness + spacing
        local rg = settings.rowGrowthDirection
        if rg == "RIGHT" then
            rowBaseX = rowBaseX + step
        elseif rg == "LEFT" then
            rowBaseX = rowBaseX - step
        elseif rg == "UP" then
            rowBaseY = rowBaseY + step
        else -- DOWN
            rowBaseY = rowBaseY - step
        end
        along = 0
        rowThickness = 0
        countInRow = 0
    end

    local function accumulateBounds(anchor, xOff, yOff, w, h)
        local left, right, top, bottom
        if anchor == "TOPLEFT" then
            left, right = xOff, xOff + w
            top, bottom = yOff, yOff - h
        elseif anchor == "TOPRIGHT" then
            right, left = xOff, xOff - w
            top, bottom = yOff, yOff - h
        elseif anchor == "BOTTOMLEFT" then
            left, right = xOff, xOff + w
            bottom, top = yOff, yOff + h
        else -- BOTTOMRIGHT
            right, left = xOff, xOff - w
            bottom, top = yOff, yOff + h
        end
        minLeft = math.min(minLeft, left)
        maxRight = math.max(maxRight, right)
        minBottom = math.min(minBottom, bottom)
        maxTop = math.max(maxTop, top)
    end

    for i, iconSize in ipairs(iconSizes) do
        local w, h = iconSize.width, iconSize.height
        local xOff, yOff = rowBaseX, rowBaseY

        if growth == "RIGHT" then
            xOff = rowBaseX + along
        elseif growth == "LEFT" then
            xOff = rowBaseX - along
        elseif growth == "UP" then
            yOff = rowBaseY + along
        else -- DOWN
            yOff = rowBaseY - along
        end

        positions[i] = {x = xOff, y = yOff, width = w, height = h, border = iconSize.border or 0}
        accumulateBounds(startAnchor, xOff, yOff, w, h)

        countInRow = countInRow + 1
        if iconGrowthIsHorizontal then
            along = along + w + spacing
            rowThickness = math.max(rowThickness, h)
        else
            along = along + h + spacing
            rowThickness = math.max(rowThickness, w)
        end

        if countInRow >= maxPerRow then
            advanceRow()
        end
    end

    local contentWidth = maxRight - minLeft
    local contentHeight = maxTop - minBottom

    for i, iconKey in ipairs(iconKeys) do
        local iconFrame = runtime.iconFrames[iconKey]
        local pos = positions[i]
        if iconFrame and pos then
            local dx, dy = borderInsetForAnchor(startAnchor, pos.border or 0)
            iconFrame:ClearAllPoints()
            iconFrame:SetParent(container)
            iconFrame:SetPoint(startAnchor, container, startAnchor, (pos.x or 0) + dx, (pos.y or 0) + dy)
            iconFrame:Show()
        end
    end

    container:SetSize(contentWidth, contentHeight)

    -- Re-apply anchor using stored anchor points
    if settings.position then
        local containerPoint = settings.anchorFrom or startAnchor
        local anchorFrame = GetAnchorFrame(settings.anchorFrame)
        local anchorPoint = settings.anchorTo or containerPoint
        container:ClearAllPoints()
        container:SetPoint(containerPoint, anchorFrame, anchorPoint, settings.position.x or 0, settings.position.y or 0)
    end
end

local function RefreshAllLayouts()
    -- SpecProfiles 자동 저장 트리거 (동적 아이콘 설정 변경 감지)
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
        DDingUI.SpecProfiles:MarkDirty()
    end

    -- [DYNAMIC] GroupSystem이 활성이면 레이아웃 스킵 → GroupSystem 업데이트 트리거
    if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
        DDingUI.DynamicIconBridge:NotifyIconsChanged()
        return
    end

    local db = GetDynamicDB()

    -- Build ungrouped list (one anchor per ungrouped icon)
    local ungroupedKeys = {}
    for iconKey, _ in pairs(db.ungrouped) do
        table.insert(ungroupedKeys, iconKey)
    end
    table.sort(ungroupedKeys)
    for _, iconKey in ipairs(ungroupedKeys) do
        db.ungroupedPositions = db.ungroupedPositions or {}
        db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
        if ShouldIconSpawn(db.iconData[iconKey]) then
            LayoutGroup(iconKey, {iconKey})
        else
            local cont = runtime.groupFrames[iconKey]
            if cont then cont:Hide() end
            local frame = runtime.iconFrames[iconKey]
            if frame then frame:Hide() end
        end
    end

    -- Groups
    for groupKey, group in pairs(db.groups) do
        -- Check if group is enabled (default true for backwards compatibility)
        if group.enabled == false then
            -- Hide all icons in disabled group
            for _, k in ipairs(group.icons or {}) do
                local frame = runtime.iconFrames[k]
                if frame then frame:Hide() end
            end
            local container = runtime.groupFrames[groupKey]
            if container then container:Hide() end
        else
            local keys = {}
            local seen = {}
            for _, k in ipairs(group.icons or {}) do
                if db.iconData[k] and not seen[k] and ShouldIconSpawn(db.iconData[k]) then
                    table.insert(keys, k)
                    seen[k] = true
                else
                    local frame = runtime.iconFrames[k]
                    if frame then frame:Hide() end
                end
            end
            LayoutGroup(groupKey, keys)
        end
    end
end

local function FindIconGroup(iconKey, db)
    if db.ungrouped[iconKey] then return "ungrouped" end
    for gk, group in pairs(db.groups) do
        for _, k in ipairs(group.icons or {}) do
            if k == iconKey then
                return gk
            end
        end
    end
    return "ungrouped"
end

function CustomIcons:LoadDynamicIcons()
    EnsureEventFrame()
    local db = GetDynamicDB()

    -- 프로필 변경 시 기존 프레임 정리: db에 없는 아이콘 제거
    for iconKey, frame in pairs(runtime.iconFrames) do
        if not db.iconData[iconKey] then
            frame:Hide()
            frame:SetParent(nil)
            runtime.iconFrames[iconKey] = nil
        end
    end
    -- 기존 그룹 프레임도 정리
    for groupKey, container in pairs(runtime.groupFrames) do
        if not db.groups[groupKey] and not db.ungrouped[groupKey] and not db.iconData[groupKey] then
            container:Hide()
            container:SetParent(nil)
            runtime.groupFrames[groupKey] = nil
        end
    end

    -- [FIX] 프레임 생성 실패한 아이콘 수집 (아이템 캐시 미준비 등)
    local pendingKeys = {}
    for iconKey, iconData in pairs(db.iconData) do
        EnsureLoadConditions(iconData)
        if IsIconLoadable(iconData) then
            local groupKey = FindIconGroup(iconKey, db)
            local settings
            if groupKey == "ungrouped" or db.ungrouped[iconKey] then
                db.ungroupedPositions = db.ungroupedPositions or {}
                db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
                settings = db.ungroupedPositions[iconKey]
                groupKey = iconKey
            else
                settings = GetGroupSettings(groupKey)
            end
            local parent = EnsureGroupFrame(groupKey, settings)
            local frame = runtime.iconFrames[iconKey]
            if not frame then
                frame = CreateDynamicIcon(iconKey, iconData, parent)
                if frame then
                    runtime.iconFrames[iconKey] = frame
                else
                    -- 프레임 생성 실패 → 재시도 목록에 추가
                    pendingKeys[#pendingKeys + 1] = iconKey
                    -- 아이템 데이터 프리로드 요청
                    if iconData.type == "item" and iconData.id then
                        C_Item.RequestLoadItemDataByID(iconData.id)
                    elseif iconData.type == "trinketProc" and iconData.slotID then
                        local itemID = GetInventoryItemID("player", iconData.slotID)
                        if itemID then C_Item.RequestLoadItemDataByID(itemID) end
                    elseif iconData.type == "slot" and iconData.slotID then
                        local itemID = GetInventoryItemID("player", iconData.slotID)
                        if itemID then C_Item.RequestLoadItemDataByID(itemID) end
                    elseif iconData.type == "spell" and iconData.id then
                        if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(iconData.id) end
                    end
                end
            end
        else
            -- Hide/clear frames for spells not in the spellbook
            local frame = runtime.iconFrames[iconKey]
            if frame then
                frame:Hide()
                frame:SetParent(nil)
                runtime.iconFrames[iconKey] = nil
            end
        end
    end
    RefreshAllLayouts()
    -- Initial update to ensure icons show correct state
    UpdateAllIcons()

    -- [FIX] 프레임 생성 실패한 아이콘 재시도 (아이템/스펠 캐시 로드 대기)
    if #pendingKeys > 0 then
        local attempts = 0
        local maxAttempts = 5
        local retryTimer
        retryTimer = C_Timer.NewTicker(1.0, function()
            attempts = attempts + 1
            local stillPending = {}
            for _, iconKey in ipairs(pendingKeys) do
                if not runtime.iconFrames[iconKey] then
                    local iconData = db.iconData[iconKey]
                    if iconData then
                        local groupKey = FindIconGroup(iconKey, db)
                        local settings
                        if groupKey == "ungrouped" or db.ungrouped[iconKey] then
                            settings = db.ungroupedPositions and db.ungroupedPositions[iconKey]
                            groupKey = iconKey
                        else
                            settings = GetGroupSettings(groupKey)
                        end
                        local parent = EnsureGroupFrame(groupKey, settings)
                        local frame = CreateDynamicIcon(iconKey, iconData, parent)
                        if frame then
                            runtime.iconFrames[iconKey] = frame
                        else
                            stillPending[#stillPending + 1] = iconKey
                        end
                    end
                end
            end
            pendingKeys = stillPending
            if #pendingKeys == 0 or attempts >= maxAttempts then
                if retryTimer then retryTimer:Cancel() end
                -- 새로 생성된 프레임이 있으면 레이아웃 갱신 + GroupSystem 알림
                RefreshAllLayouts()
                UpdateAllIcons()
            end
        end)
    end
end

function CustomIcons:CreateCustomIconsTrackerFrame()
    if not DDingUI.db.profile.customIcons.enabled then return nil end

    -- Create the main container frame (for backwards compatibility)
    if not DDingUI.customIconsTrackerFrame then
        DDingUI.customIconsTrackerFrame = CreateFrame("Frame", "DDingUI_CustomIconsTrackerFrame", UIParent)
        DDingUI.customIconsTrackerFrame:SetSize(200, 40)
        DDingUI.customIconsTrackerFrame:SetFrameStrata("MEDIUM")
        DDingUI.customIconsTrackerFrame:SetClampedToScreen(true)
        DDingUI.customIconsTrackerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
        DDingUI.customIconsTrackerFrame._DDingUI_CustomIconsTracker = true
    end

    -- Load all dynamic icons
    self:LoadDynamicIcons()

    return DDingUI.customIconsTrackerFrame
end

-- ------------------------
-- Public API
-- ------------------------
function CustomIcons:AddDynamicIcon(iconData)
    local db = GetDynamicDB()
    local iconKey = iconData.key or ("icon_" .. tostring(math.floor(GetTime() * 1000)))
    iconData.key = iconKey
    EnsureIconSettings(iconData)
    EnsureLoadConditions(iconData)

    db.iconData[iconKey] = iconData
    EnsureLoadConditions(db.iconData[iconKey])
    db.ungrouped[iconKey] = true
    db.ungroupedPositions = db.ungroupedPositions or {}
    db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()

    -- Build frame — CreateDynamicIcon은 항상 프레임 반환 (Ayije 방식)
    local frame = CreateDynamicIcon(iconKey, iconData, EnsureGroupFrame(iconKey, db.ungroupedPositions[iconKey]))
    if frame then
        runtime.iconFrames[iconKey] = frame
        UpdateDynamicIcon(iconKey)
        RefreshAllLayouts()
    end

    -- [FIX] GroupSystem 즉시 갱신 — 디바운스 우회하여 아이콘 바로 표시
    C_Timer.After(0.1, function()
        local bridge = DDingUI.DynamicIconBridge
        if bridge and bridge:IsActive() then
            local gs = DDingUI.GroupSystem
            if gs and gs.Refresh then
                gs:Refresh()
            end
        end
    end)

    CustomIcons:RefreshDynamicListUI()
    -- [FIX] SpecProfiles 즉시 저장 — 리로드 시 LoadSpec이 이전 스냅샷으로 복원하여 데이터 손실 방지
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    return iconKey
end

function CustomIcons:RemoveDynamicIcon(iconKey)
    local db = GetDynamicDB()
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
        frame:Hide()
        frame:SetParent(nil)
        runtime.iconFrames[iconKey] = nil
    end

    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
end

function CustomIcons:CreateDynamicGroup(name)
    local db = GetDynamicDB()
    local key = "group_" .. tostring(math.floor(GetTime() * 1000))
    local startAnchor = GetStartAnchorForGrowthPair("RIGHT", "DOWN")
    db.groups[key] = {
        name = name or (L["New Group"] or "New Group"),
        enabled = true,
        icons = {},
        settings = {
            growthDirection = "RIGHT",
            rowGrowthDirection = "DOWN",
            anchorFrom = startAnchor,
            anchorTo = startAnchor,
            spacing = 5,
            maxIconsPerRow = 10,
            -- No default position - will be set when first icon is added
        },
    }
    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
    return key
end

function CustomIcons:RemoveGroup(groupKey)
    local db = GetDynamicDB()
    local group = db.groups[groupKey]
    if not group then return end

    -- 그룹 내 아이콘들을 실제로 삭제
    local iconsToRemove = {}
    for _, iconKey in ipairs(group.icons or {}) do
        iconsToRemove[#iconsToRemove + 1] = iconKey
    end
    -- [FIX] DynamicIconBridge managed 상태도 정리 (DestroyGroup의 ReleaseFrame이 복원하는 것 방지)
    local bridge = DDingUI.DynamicIconBridge
    for _, iconKey in ipairs(iconsToRemove) do
        -- iconData 삭제
        db.iconData[iconKey] = nil
        db.ungrouped[iconKey] = nil
        if db.ungroupedPositions then
            db.ungroupedPositions[iconKey] = nil
        end
        -- bridge managed 상태 정리 (DestroyGroup→ReleaseFrame이 orig.parent로 복원하는 것 방지)
        local frame = runtime.iconFrames[iconKey]
        if frame then
            -- origState 먼저 제거 → ReleaseFrame이 reparent하지 않음
            frame._ddOrigState = nil
            if bridge then
                bridge:ReleaseFrame(frame, iconKey)
            end
            frame:Hide()
            frame:SetParent(nil)
            runtime.iconFrames[iconKey] = nil
        end
    end

    db.groups[groupKey] = nil
    -- [FIX] 그룹 컨테이너 프레임도 정리 (고스트 컨테이너 방지)
    local container = runtime.groupFrames and runtime.groupFrames[groupKey]
    if container then
        container:Hide()
        runtime.groupFrames[groupKey] = nil
    end
    if uiState and uiState.selectedGroup == groupKey then
        uiState.selectedGroup = nil
    end
    RefreshAllLayouts()
    CustomIcons:RefreshDynamicListUI()
    CustomIcons:RefreshDynamicConfigUI()
end

function CustomIcons:MoveIconToGroup(iconKey, targetGroup)
    local db = GetDynamicDB()
    local function removeFromGroup(gkey)
        local group = db.groups[gkey]
        if not group or not group.icons then return end
        for i = #group.icons, 1, -1 do
            if group.icons[i] == iconKey then
                table.remove(group.icons, i)
            end
        end
    end

    if targetGroup == "ungrouped" then
        db.ungrouped[iconKey] = true
        db.ungroupedPositions = db.ungroupedPositions or {}
        db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
    else
        db.ungrouped[iconKey] = nil
        if db.ungroupedPositions then
            db.ungroupedPositions[iconKey] = nil
        end
        if db.groups[targetGroup] then
            db.groups[targetGroup].icons = db.groups[targetGroup].icons or {}
            -- Ensure the icon is not already present to avoid duplicates
            removeFromGroup(targetGroup)

            -- If this is the first icon in the group, position the group at the icon's current location
            if #db.groups[targetGroup].icons == 0 then
                local iconFrame = runtime.iconFrames[iconKey]
                if iconFrame then
                    local iconX, iconY = iconFrame:GetCenter()
                    if iconX and iconY then
                        -- Convert from world coordinates to relative coordinates
                        local uiScale = UIParent:GetEffectiveScale()
                        iconX = iconX / uiScale
                        iconY = iconY / uiScale

                        -- Get the current anchor frame
                        local settings = db.groups[targetGroup].settings or {}
                        local anchorFrame = GetAnchorFrame(settings.anchorFrame)

                        -- Calculate position relative to anchor frame
                        local anchorX, anchorY = anchorFrame:GetCenter()
                        anchorX = anchorX / uiScale
                        anchorY = anchorY / uiScale

                        settings.position = {
                            x = iconX - anchorX,
                            y = iconY - anchorY
                        }
                        db.groups[targetGroup].settings = settings
                    end
                end
            end

            table.insert(db.groups[targetGroup].icons, iconKey)
        end
    end

    -- Remove from other groups
    for gk, group in pairs(db.groups) do
        for i = #group.icons, 1, -1 do
            if group.icons[i] == iconKey and gk ~= targetGroup then
                table.remove(group.icons, i)
            end
        end
    end

    -- Destroy standalone container when moving into a group
    if targetGroup ~= "ungrouped" then
        local cont = runtime.groupFrames[iconKey]
        if cont then
            cont:Hide()
            runtime.groupFrames[iconKey] = nil
        end
    end

    RefreshAllLayouts()
    -- [FIX] GroupSystem 즉시 갱신 — MoveIconToGroup 후 바로 아이콘 표시
    C_Timer.After(0.1, function()
        local bridge = DDingUI.DynamicIconBridge
        if bridge and bridge:IsActive() then
            local gs = DDingUI.GroupSystem
            if gs and gs.Refresh then
                gs:Refresh()
            end
        end
    end)
    CustomIcons:RefreshDynamicListUI()
    -- [FIX] SpecProfiles 즉시 저장 — MoveIconToGroup 후 스냅샷 갱신
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
    -- [FIX] GroupSystem 옵션 트리 재빌드 — 할당 목록에 새 아이콘 즉시 표시
    if DDingUI.RefreshConfigGUI then
        DDingUI:RefreshConfigGUI(true)
    end
end

function CustomIcons:ReorderIconInGroup(groupKey, iconKey, targetKey)
    local db = GetDynamicDB()
    if groupKey == "ungrouped" then
        -- preserve set semantics for ungrouped; sorting not needed
        return
    end
    local group = db.groups[groupKey]
    if not group or not group.icons then return end

    -- [FIX] swap 방식: 두 아이콘의 위치를 교환
    -- insert-before 방식은 1번→2번 드래그 시 동일한 결과가 나옴
    local srcIdx, dstIdx
    for i, k in ipairs(group.icons) do
        if k == iconKey then srcIdx = i end
        if k == targetKey then dstIdx = i end
    end
    if not srcIdx or not dstIdx or srcIdx == dstIdx then return end

    group.icons[srcIdx], group.icons[dstIdx] = group.icons[dstIdx], group.icons[srcIdx]

    RefreshAllLayouts()
end

-- [FIX] 방향 이동 (↑위/↓아래): 그룹 내 아이콘 순서 변경
function CustomIcons:MoveIconInGroup(groupKey, iconKey, direction)
    local db = GetDynamicDB()
    local group = db.groups[groupKey]
    if not group or not group.icons then return end

    local currentIndex
    for i, k in ipairs(group.icons) do
        if k == iconKey then
            currentIndex = i
            break
        end
    end
    if not currentIndex then return end

    local newIndex
    if direction == "up" then
        newIndex = currentIndex - 1
    elseif direction == "down" then
        newIndex = currentIndex + 1
    end
    if not newIndex or newIndex < 1 or newIndex > #group.icons then return end

    -- swap
    group.icons[currentIndex], group.icons[newIndex] = group.icons[newIndex], group.icons[currentIndex]

    RefreshAllLayouts()
    -- SpecProfiles 즉시 저장
    if DDingUI.SpecProfiles and DDingUI.SpecProfiles.SaveCurrentSpec then
        DDingUI.SpecProfiles:SaveCurrentSpec()
    end
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
        local iid = GetInventoryItemID("player", iconData.slotID or 13)
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
    node:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.80)
    node:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.5)
    node._iconKey = iconKey
    node._hover = false

    local function applyNodeHighlight()
        local isSelected = uiState.selectedIcon == iconKey
        local isMultiSelected = uiState.selectedIcons[iconKey]
        -- [STYLE] default=bgWidget, hover=bgLight, selected=bgMedium
        local bg = THEME.bgWidget
        local border = THEME.border
        local alpha = 0.80
        if isSelected or isMultiSelected then
            bg = THEME.bgMedium
            border = THEME.accent
            alpha = 0.80
        elseif node._hover then
            bg = THEME.bgLight
            border = {THEME.borderLight[1], THEME.borderLight[2], THEME.borderLight[3]}
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
        CreateColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1),
        CreateColor(THEME.accentDark[1], THEME.accentDark[2], THEME.accentDark[3], 1)
    )
    checkTex:Hide()

    local function updateCheckboxVisual()
        if checkbox._checked then
            checkbox:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
            checkbox:SetBackdropBorderColor(0, 0, 0, 1)
            checkTex:Show()
        else
            checkbox:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
            checkbox:SetBackdropBorderColor(0, 0, 0, 1)
            checkTex:Hide()
        end
    end
    updateCheckboxVisual()
    -- 하이라이트
    local cbHighlight = checkbox:CreateTexture(nil, "ARTWORK")
    cbHighlight:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.1)
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
        node.iconTex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif iconData.type == "spell" then
        local info = C_Spell.GetSpellInfo(iconData.id)
        node.iconTex:SetTexture((info and info.iconID) or C_Spell.GetSpellTexture(iconData.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    elseif iconData.type == "slot" or iconData.type == "trinketProc" then
        local iid = GetInventoryItemID("player", iconData.slotID)
        local _, _, _, _, _, _, _, _, _, tex = iid and GetItemInfo(iid)
        node.iconTex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    end

    local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
    local label = node:CreateFontString(nil, "OVERLAY")
    label:SetFont(globalFont, 11, "")
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetPoint("LEFT", node.iconTex, "RIGHT", 6, 6)
    label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)

    local displayName = ""
    if iconData.type == "item" then
        displayName = GetItemInfo(iconData.id) or ((L["Item"] or "Item") .. " ID: " .. iconData.id)
    elseif iconData.type == "spell" then
        local info = C_Spell.GetSpellInfo(iconData.id)
        displayName = (info and info.name) or ((L["Spell"] or "Spell") .. " ID: " .. iconData.id)
    elseif iconData.type == "slot" then
        displayName = (L["Slot"] or "Slot") .. " " .. tostring(iconData.slotID or "")
    elseif iconData.type == "trinketProc" then
        local iid = GetInventoryItemID("player", iconData.slotID or 13)
        displayName = (iid and GetItemInfo(iid)) or ("Trinket " .. (iconData.slotID == 14 and "2" or "1"))
    end
    label:SetText(displayName)

    local badge = node:CreateFontString(nil, "OVERLAY")
    badge:SetFont(globalFont, 10, "")
    badge:SetShadowOffset(1, -1)
    badge:SetShadowColor(0, 0, 0, 1)
    badge:SetPoint("LEFT", label, "LEFT", 0, -12)
    badge:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.9)
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
    deleteBtn:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
    deleteBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.50)
    local deleteBtnText = deleteBtn:CreateFontString(nil, "OVERLAY")
    deleteBtnText:SetFont(globalFont, 11, "")
    deleteBtnText:SetPoint("CENTER", 0, 1)
    deleteBtnText:SetText("×")
    deleteBtnText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    deleteBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(THEME.error[1], THEME.error[2], THEME.error[3], 0.9)
        self:SetBackdropBorderColor(THEME.error[1], THEME.error[2], THEME.error[3], 1)
        deleteBtnText:SetTextColor(1, 1, 1, 1)
    end)
    deleteBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.9)
        self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.50)
        deleteBtnText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
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

-- [REFACTOR] CreateStyledButton/Toggle/Input/Dropdown → DDingUI.GUI로 이동 (EnsureGUILoaded에서 로드)

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

    local selectAllBtn = CreateStyledButton(selectBtnFrame, "전체 선택", 75, 22)
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

    local deselectAllBtn = CreateStyledButton(selectBtnFrame, "선택 해제", 75, 22)
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
        box:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.80)
        box:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.50)
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
            headerText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.6)
            headerText:SetText(title .. " |cff888888[OFF]|r")
        else
            headerText:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
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
        arrowBtn:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.8)
        arrowBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.50)
        local globalFont = DDingUI:GetGlobalFont() or "Fonts\\2002.TTF"
        local arrowText = arrowBtn:CreateFontString(nil, "OVERLAY")
        arrowText:SetFont(globalFont, 11, "")
        arrowText:SetShadowOffset(1, -1)
        arrowText:SetShadowColor(0, 0, 0, 1)
        arrowText:SetPoint("CENTER", 0, 0)
        arrowText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        local function updateArrow()
            if uiState.collapsedGroups[groupKey] == true then
                arrowText:SetText("▶")
            else
                arrowText:SetText("▼")
            end
        end
        updateArrow()
        arrowBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.2)
            self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
            arrowText:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
        end)
        arrowBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(THEME.bgWidget[1], THEME.bgWidget[2], THEME.bgWidget[3], 0.8)
            self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4] or 0.50)
            arrowText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        end)

        local function applyBoxHighlight()
            -- [STYLE] default=bgWidget, selected=bgMedium, hover=accent border
            local bg = isSelectedGroup and THEME.bgMedium or THEME.bgWidget
            local alpha = isSelectedGroup and 0.80 or 0.80
            local border = (isSelectedGroup or headerHover) and THEME.accent or THEME.border
            local borderAlpha = (isSelectedGroup or headerHover) and 1 or 0.50
            -- Dim disabled groups
            if isDisabled then
                alpha = alpha * 0.5
                border = THEME.border
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
    if listScroll and PropagateMouseWheelRecursive then
        PropagateMouseWheelRecursive(uiFrames.listParent, listScroll)
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
        header:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        header:SetText(selectedCount .. "개 아이콘 일괄 편집")
        y = y + 30

        local desc = uiFrames.configParent:CreateFontString(nil, "OVERLAY")
        desc:SetFont(globalFont, 10, "")
        desc:SetShadowOffset(1, -1)
        desc:SetShadowColor(0, 0, 0, 1)
        desc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
        desc:SetText("아래 설정을 조정 후 '일괄 적용' 버튼을 눌러주세요")
        desc:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        y = y + 25

        -- Icon Size
        local sizeSlider = Widgets.CreateRange(uiFrames.configParent, {
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
        local aspectSlider = Widgets.CreateRange(uiFrames.configParent, {
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
        local borderSlider = Widgets.CreateRange(uiFrames.configParent, {
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
        Widgets.CreateColor(uiFrames.configParent, {
            name = "테두리 색상",
            get = function() return unpack(batchEditState.borderColor) end,
            set = function(_, r, g, b, a) batchEditState.borderColor = {r, g, b, a} end,
            width = "full",
        }, y)
        y = y + 40

        -- Toggles
        Widgets.CreateToggle(uiFrames.configParent, {
            name = "쿨다운 표시",
            get = function() return batchEditState.showCooldown end,
            set = function(_, val) batchEditState.showCooldown = val end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "충전/횟수 표시",
            get = function() return batchEditState.showCharges end,
            set = function(_, val) batchEditState.showCharges = val end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "쿨다운 시 흑백",
            get = function() return batchEditState.desaturateOnCooldown end,
            set = function(_, val) batchEditState.desaturateOnCooldown = val end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "사용 불가 시 흑백",
            get = function() return batchEditState.desaturateWhenUnusable end,
            set = function(_, val) batchEditState.desaturateWhenUnusable = val end,
            width = "full",
        }, y)
        y = y + 32

        Widgets.CreateToggle(uiFrames.configParent, {
            name = "GCD 스와이프 표시",
            get = function() return batchEditState.showGCDSwipe end,
            set = function(_, val) batchEditState.showGCDSwipe = val end,
            width = "full",
        }, y)
        y = y + 40

        -- Apply Button
        Widgets.CreateExecute(uiFrames.configParent, {
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
        local deleteBtn = Widgets.CreateExecute(uiFrames.configParent, {
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
        local slider = Widgets.CreateRange(uiFrames.configParent, {
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
        Widgets.CreateToggle(uiFrames.configParent, {
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
        Widgets.CreateColor(uiFrames.configParent, {
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
            Widgets.CreateSelect(uiFrames.configParent, {
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
        Widgets.CreateColor(uiFrames.configParent, {
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
        Widgets.CreateSelect(uiFrames.configParent, {
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
        Widgets.CreateColor(uiFrames.configParent, {
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

        Widgets.CreateToggle(uiFrames.configParent, {
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

        Widgets.CreateToggle(uiFrames.configParent, {
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

        Widgets.CreateToggle(uiFrames.configParent, {
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
            trinketHeader:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            trinketHeader:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            trinketHeader:SetText("━━━ Trinket Proc Settings ━━━")
            trinketHeader:SetJustifyH("LEFT")
            y = y + 24

            Widgets.CreateInput(uiFrames.configParent, {
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
            procDesc:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            procDesc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            procDesc:SetText("0: Use: 효과 자동 감지 / 수동: 패시브 프록 spellID 입력")
            procDesc:SetJustifyH("LEFT")
            y = y + 20

            Widgets.CreateToggle(uiFrames.configParent, {
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

            Widgets.CreateToggle(uiFrames.configParent, {
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

            Widgets.CreateToggle(uiFrames.configParent, {
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
            Widgets.CreateInput(uiFrames.configParent, {
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
            fallbackDesc:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            fallbackDesc:SetPoint("TOPLEFT", uiFrames.configParent, "TOPLEFT", 0, -y)
            fallbackDesc:SetText("예: 3성 물약ID, 2성ID, 1성ID (쉼표 구분)")
            fallbackDesc:SetJustifyH("LEFT")
            y = y + 20
        end

        Widgets.CreateToggle(uiFrames.configParent, {
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

        Widgets.CreateToggle(uiFrames.configParent, {
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

        Widgets.CreateExecute(uiFrames.configParent, {
            name = L["Load Conditions..."] or "Load Conditions...",
            func = function() CustomIcons:ShowLoadConditionsWindow(iconKey, iconData) end,
            width = "full",
        }, y)
        y = y + 40

        -- Update scroll child height
        uiFrames.configParent:SetHeight(y + 20)
        -- 마우스 휠 전파 (아이콘 설정)
        if uiFrames.configScroll and PropagateMouseWheelRecursive then
            PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
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
            label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
            return
        end
        ensureGroupDefaults(selectedGroup)
        local s = selectedGroup.settings

        -- Enabled toggle at the top
        Widgets.CreateToggle(uiFrames.configParent, {
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

        Widgets.CreateInput(uiFrames.configParent, {
            name = "Group Name",
            get = function() return selectedGroup.name or "" end,
            set = function(_, val)
                selectedGroup.name = val or "Group"
                CustomIcons:RefreshDynamicListUI()
            end,
            width = "full",
        }, y)
        y = y + 40

        Widgets.CreateSelect(uiFrames.configParent, {
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

        Widgets.CreateSelect(uiFrames.configParent, {
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

        Widgets.CreateSelect(uiFrames.configParent, {
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
        Widgets.CreateExecute(uiFrames.configParent, {
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

        Widgets.CreateInput(uiFrames.configParent, {
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
        local pickBtn = Widgets.CreateExecute(uiFrames.configParent, {
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
            pickBtn.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        end
        y = y + 40

        local deleteGroupBtn = Widgets.CreateExecute(uiFrames.configParent, {
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
        if uiFrames.configScroll and PropagateMouseWheelRecursive then
            PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
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
    label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)

    -- 자식 위젯 위에서도 스크롤 가능하도록 마우스 휠 전파
    if uiFrames.configScroll and PropagateMouseWheelRecursive then
        PropagateMouseWheelRecursive(uiFrames.configParent, uiFrames.configScroll)
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
        f:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)

        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        f.text:SetShadowOffset(1, -1)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetPoint("TOP", f, "TOP", 0, -38)
        f.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)

        f.confirm = CreateStyledButton(f, "Confirm", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)

        f.cancel = CreateStyledButton(f, "Cancel", 100, 26)
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
        f:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 14, "")
        f.title:SetShadowOffset(1, -1)
        f.title:SetShadowColor(0, 0, 0, 1)
        f.title:SetPoint("TOP", f, "TOP", 0, -12)
        f.title:SetTextColor(0.90, 0.25, 0.25, 1)  -- Red for warning (THEME error color)

        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont(DDingUI:GetGlobalFont() or "Fonts\\2002.TTF", 11, "")
        f.text:SetShadowOffset(1, -1)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetPoint("TOP", f, "TOP", 0, -38)
        f.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        f.text:SetWidth(280)
        f.text:SetJustifyH("CENTER")

        f.confirm = CreateStyledButton(f, "Delete", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        f.confirm:SetBackdropColor(0.5, 0.1, 0.1, 1)  -- Red tint for delete

        f.cancel = CreateStyledButton(f, "Cancel", 100, 26)
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
        f:SetBackdropColor(THEME.bgDark[1], THEME.bgDark[2], THEME.bgDark[3], 0.95)
        f:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)

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
        f.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        f.text:SetWidth(280)
        f.text:SetJustifyH("CENTER")

        f.confirm = CreateStyledButton(f, "Delete", 100, 26)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        f.confirm:SetBackdropColor(0.5, 0.1, 0.1, 1)

        f.cancel = CreateStyledButton(f, "Cancel", 100, 26)
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
                frame:Hide()
                frame:SetParent(nil)
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
    local search = Widgets.CreateInput(container, {
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
    resultText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
    uiFrames.resultText = resultText

    -- Buttons
    local createIconBtn = Widgets.CreateExecute(container, {
        name = "+ Create Icon",
        func = function() CustomIcons:ShowCreateIconDialog() end,
        width = "normal",
    }, 40)
    -- [STYLE] 악센트 텍스트
    if createIconBtn.text then createIconBtn.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1) end
    if search.editBox then
        createIconBtn:SetPoint("TOPLEFT", search.editBox, "BOTTOMLEFT", 0, -18)
    else
        createIconBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -52)
    end

    local createGroupBtn = Widgets.CreateExecute(container, {
        name = "+ " .. (L["New Group"] or "Create Group"),
        func = function()
            CustomIcons:CreateDynamicGroup(L["New Group"] or "New Group")
        end,
        width = "normal",
    }, 40)
    -- [STYLE] 악센트 텍스트
    if createGroupBtn.text then createGroupBtn.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1) end
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

    local listScrollBar = CreateCustomScrollBar(container, listScroll)
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
    CreateBackdrop(configContainer, THEME.bgDark, THEME.border)

    local configScroll = CreateFrame("ScrollFrame", nil, configContainer)
    configScroll:SetPoint("TOPLEFT", configContainer, "TOPLEFT", 8, -8)
    configScroll:SetPoint("BOTTOMRIGHT", configContainer, "BOTTOMRIGHT", -14, 8)

    local configChild = CreateFrame("Frame", nil, configScroll)
    configChild:SetWidth(configScroll:GetWidth() or 400)
    configChild:SetHeight(800)  -- Will be adjusted dynamically
    configScroll:SetScrollChild(configChild)

    local configScrollBar = CreateCustomScrollBar(configContainer, configScroll)
    configScrollBar:SetPoint("TOPLEFT", configScroll, "TOPRIGHT", 4, 0)
    configScrollBar:SetPoint("BOTTOMLEFT", configScroll, "BOTTOMRIGHT", 4, 0)
    configScroll.ScrollBar = configScrollBar

    uiFrames.configParent = configChild
    uiFrames.configScroll = configScroll

    CustomIcons:RefreshDynamicListUI()
    CustomIcons:RefreshDynamicConfigUI()
end

-- Creation dialog
local slotOptions = {
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
local function RaiseDropDownMenus()
    for i = 1, 2 do
        local list = _G["DropDownList"..i]
        if list then
            list:SetFrameStrata("TOOLTIP")
            if uiFrames.createFrame then
                list:SetFrameLevel(uiFrames.createFrame:GetFrameLevel() + 10)
            end
            if not list.__dduiStrataHooked then
                list:HookScript("OnShow", RaiseDropDownMenus)
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
        CreateBackdrop(f, THEME.bgDark, THEME.border)
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
        f.title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        f.title:SetText("Create Icon")

        -- Type toggle buttons (styled)
        f.typeButtons = {}
        local types = { {key = "spell", label = "Spell"}, {key = "item", label = "Item"}, {key = "slot", label = "Slot"}, {key = "trinketProc", label = "Trinket"} }
        local spacing = 85
        local startX = -((#types - 1) * spacing) / 2
        for idx, info in ipairs(types) do
            local btn = CreateStyledToggle(f, info.label, 80)
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
        idLabel:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        f.idLabel = idLabel

        local idBox = CreateStyledInput(f, 200, 28, true)
        idBox:SetPoint("TOPLEFT", idLabel, "BOTTOMLEFT", 0, -4)
        f.idInput = idBox

        -- Slot dropdown (styled)
        local slotLabel = f:CreateFontString(nil, "OVERLAY")
        slotLabel:SetFont(globalFont, 11, "")
        slotLabel:SetShadowOffset(1, -1)
        slotLabel:SetShadowColor(0, 0, 0, 1)
        slotLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -78)
        slotLabel:SetText("Equipment Slot")
        slotLabel:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        slotLabel:Hide()
        f.slotLabel = slotLabel

        local dropdown = CreateStyledDropdown(f, slotOptions, 200)
        dropdown:SetPoint("TOPLEFT", slotLabel, "BOTTOMLEFT", 0, -4)
        dropdown:SetText("Select Slot")
        dropdown:Hide()
        f.slotDropdown = dropdown
        f.selectedSlot = slotOptions[1].slotID
        dropdown.selectedValue = slotOptions[1].slotID

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
        trinketLabel:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        trinketLabel:Hide()
        f.trinketLabel = trinketLabel

        local trinketDD = CreateStyledDropdown(f, trinketSlotOptions, 200)
        trinketDD:SetPoint("TOPLEFT", trinketLabel, "BOTTOMLEFT", 0, -4)
        trinketDD:SetText("Trinket 1 (Slot 13)")
        trinketDD:Hide()
        f.trinketDropdown = trinketDD
        trinketDD.selectedValue = 13

        -- Buttons (styled)
        f.confirm = CreateStyledButton(f, "Create", 100, 28)
        f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)

        f.cancel = CreateStyledButton(f, "Cancel", 100, 28)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
        f.cancel:SetScript("OnClick", function() f:Hide() end)

        f.confirm:SetScript("OnClick", function()
            local t = f.selectedType
            if t == "slot" then
                local slotID = f.slotDropdown.selectedValue or slotOptions[1].slotID
                CustomIcons:AddDynamicIcon({type = "slot", slotID = slotID})
            elseif t == "trinketProc" then
                local slotID = f.trinketDropdown.selectedValue or 13
                CustomIcons:AddDynamicIcon({type = "trinketProc", slotID = slotID})
            else
                local idVal = tonumber(f.idInput:GetText() or "")
                if not idVal or idVal <= 0 then
                    UIErrorsFrame:AddMessage("Enter a valid ID", 1, 0, 0)
                    return
                end
                CustomIcons:AddDynamicIcon({type = t, id = idVal})
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

-- Expose runtime data for external access (Movers system)
CustomIcons.GetGroupFrames = function() return runtime.groupFrames end
CustomIcons.runtime = runtime

-- Auto-load saved icons when DB is available
if DDingUI.db and DDingUI.db.profile then
    CustomIcons:LoadDynamicIcons()
end

-- Missing functions expected by Main.lua
function CustomIcons:ApplyCustomIconsLayout()
    if RefreshAllLayouts then
        RefreshAllLayouts()
    end
end

-- Stub functions for Trinkets/Defensives trackers (not implemented)
function CustomIcons:CreateTrinketsTrackerFrame()
    return nil
end

function CustomIcons:CreateDefensivesTrackerFrame()
    return nil
end

function CustomIcons:ApplyTrinketsLayout()
    -- Not implemented
end

function CustomIcons:ApplyDefensivesLayout()
    -- Not implemented
end

-- [DYNAMIC] GroupSystem DynamicIconBridge용 API
-- 모든 활성 아이콘 프레임 반환 (runtime.iconFrames 참조)
function CustomIcons:GetAllIconFrames()
    return runtime.iconFrames
end
