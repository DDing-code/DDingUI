-------------------------------------------------------------------------------
--  EllesmereUICooldownManager.lua
--  CDM Look Customization and Cooldown Display
--  Mirrors Blizzard CDM bars with custom styling, cooldown swipes,
--  desaturation, active state animations, and per-spec profiles.
--  Does NOT parse secret values ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ works around restricted APIs.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local ECME = EllesmereUI.Lite.NewAddon("EllesmereUICooldownManager")
ns.ECME = ECME

local PP = EllesmereUI.PP

local function GetCDMOutline() return EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "" end
local function GetCDMUseShadow() return EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() or true end
local function SetCDMFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    local f = GetCDMOutline()
    fs:SetFont(font, size, f)
    if f == "" then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
    else fs:SetShadowOffset(0, 0) end
end

-- Snap a value to the nearest physical pixel at a given bar scale
local function SnapForScale(x, barScale)
    if x == 0 then return 0 end
    local m = PP.perfect / ((UIParent:GetScale() or 1) * (barScale or 1))
    if m == 1 then return x end
    local y = m > 1 and m or -m
    return x - x % (x < 0 and y or -y)
end

local floor, abs, format = math.floor, math.abs, string.format
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo

local DEFAULT_MAPPING_NAME = "Buff Name (eg: Divine Purpose)"

-------------------------------------------------------------------------------
--  Shape Constants (shared with action bars)
-------------------------------------------------------------------------------
local CDM_SHAPE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
local CDM_SHAPE_MASKS = {
    circle   = CDM_SHAPE_MEDIA .. "circle_mask.tga",
    csquare  = CDM_SHAPE_MEDIA .. "csquare_mask.tga",
    diamond  = CDM_SHAPE_MEDIA .. "diamond_mask.tga",
    hexagon  = CDM_SHAPE_MEDIA .. "hexagon_mask.tga",
    portrait = CDM_SHAPE_MEDIA .. "portrait_mask.tga",
    shield   = CDM_SHAPE_MEDIA .. "shield_mask.tga",
    square   = CDM_SHAPE_MEDIA .. "square_mask.tga",
}
local CDM_SHAPE_BORDERS = {
    circle   = CDM_SHAPE_MEDIA .. "circle_border.tga",
    csquare  = CDM_SHAPE_MEDIA .. "csquare_border.tga",
    diamond  = CDM_SHAPE_MEDIA .. "diamond_border.tga",
    hexagon  = CDM_SHAPE_MEDIA .. "hexagon_border.tga",
    portrait = CDM_SHAPE_MEDIA .. "portrait_border.tga",
    shield   = CDM_SHAPE_MEDIA .. "shield_border.tga",
    square   = CDM_SHAPE_MEDIA .. "square_border.tga",
}
local CDM_SHAPE_INSETS = {
    circle = 17, csquare = 17, diamond = 14,
    hexagon = 17, portrait = 17, shield = 13, square = 17,
}
local CDM_SHAPE_ICON_EXPAND = 7
local CDM_SHAPE_ICON_EXPAND_OFFSETS = {
    circle = 2, csquare = 4, diamond = 2, hexagon = 4,
    portrait = 2, shield = 2, square = 4,
}
local CDM_SHAPE_ZOOM_DEFAULTS = {
    none = 0.08, cropped = 0.02, square = 0.06, circle = 0.06, csquare = 0.06,
    diamond = 0.06, hexagon = 0.06, portrait = 0.06, shield = 0.06,
}
local CDM_SHAPE_EDGE_SCALES = {
    circle = 0.75, csquare = 0.75, diamond = 0.70,
    hexagon = 0.65, portrait = 0.70, shield = 0.65, square = 0.75,
}
ns.CDM_SHAPE_MASKS   = CDM_SHAPE_MASKS
ns.CDM_SHAPE_BORDERS = CDM_SHAPE_BORDERS
ns.CDM_SHAPE_ZOOM_DEFAULTS = CDM_SHAPE_ZOOM_DEFAULTS
-------------------------------------------------------------------------------
--  Desaturation Curve for DurationObject evaluation
--  Step curve: returns 0 when remaining <= 0 (off CD), 1 when > 0.001 (on CD)
-------------------------------------------------------------------------------
local ECME_DESAT_CURVE = C_CurveUtil.CreateCurve()
ECME_DESAT_CURVE:SetType(Enum.LuaCurveType.Step)
ECME_DESAT_CURVE:AddPoint(0, 0)
ECME_DESAT_CURVE:AddPoint(0.001, 1)

-- Forward declarations for glow helpers (defined later, used by consolidated helpers)
local StartNativeGlow, StopNativeGlow

-- Reusable helpers to avoid closure allocation in hot-path pcall calls
local _gcdCheckSid
local function _CheckIsGCD()
    local cdData = C_Spell.GetSpellCooldown(_gcdCheckSid)
    return cdData and cdData.isOnGCD
end

-- Multi-charge spell cache: populated out of combat when values are not secret.
-- Falls back to SavedVariables for combat /reload scenarios.
-- Maps spellID ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó true for spells with maxCharges > 1
local _multiChargeSpells = {}
local _maxChargeCount    = {}  -- [spellID] = maxCharges, populated alongside _multiChargeSpells

local function CacheMultiChargeSpell(spellID)
    if not spellID or not C_Spell.GetSpellCharges then return end
    if _multiChargeSpells[spellID] ~= nil then return end
    local charges = C_Spell.GetSpellCharges(spellID)
    if not charges or charges.maxCharges == nil then return end

    if not issecretvalue(charges.maxCharges) then
        -- Out of combat (or non-secret): cache live and persist to DB
        local result = charges.maxCharges > 1
        _multiChargeSpells[spellID] = result or false
        if result then
            _maxChargeCount[spellID] = charges.maxCharges
            -- Only persist confirmed charge spells ΓÇö never persist false so
            -- stale DB entries don't block re-detection on login or talent swap.
            local db = ECME.db
            if db and db.global then
                if not db.global.multiChargeSpells then
                    db.global.multiChargeSpells = {}
                end
                db.global.multiChargeSpells[spellID] = true
            end
        end
    else
        -- Secret (in combat): fall back to persisted DB value if available.
        -- Do NOT cache false here -- after a talent swap the DB may be empty,
        -- and caching false permanently blocks charge detection for the new
        -- spell until the next full cache wipe.
        local db = ECME.db
        if db and db.global and db.global.multiChargeSpells and db.global.multiChargeSpells[spellID] then
            _multiChargeSpells[spellID] = true
        end
        -- If no DB entry: leave nil so we retry next tick when OOC or after talents settle
    end
end
-- Expose charge cache to options file for preview rendering
ns._multiChargeSpells    = _multiChargeSpells
ns._maxChargeCount       = _maxChargeCount
ns.CacheMultiChargeSpell = CacheMultiChargeSpell

-- Cast-count spell cache: identifies spells that use GetSpellCastCount for
-- stack tracking (e.g. Sheilun's Gift, Mana Tea). These spells start at 0
-- stacks and build them in combat, so we cache the last known non-zero count
-- OOC and persist to SavedVariables for combat use.
-- Maps spellID -> last known count (number) or false (confirmed not a cast-count spell)
local _castCountSpells = {}

local function CacheCastCountSpell(spellID)
    if not spellID or not C_Spell.GetSpellCastCount then return end
    -- Already confirmed not a cast-count spell ΓÇö skip
    if _castCountSpells[spellID] == false then return end
    local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
    if not ok or count == nil then return end

    if not (issecretvalue and issecretvalue(count)) then
        -- OOC: if count > 0, remember this spell uses cast counts
        if count > 0 then
            _castCountSpells[spellID] = count
            local db = ECME.db
            if db and db.global then
                if not db.global.castCountSpells then
                    db.global.castCountSpells = {}
                end
                db.global.castCountSpells[spellID] = true
            end
        end
        -- Don't cache false here ΓÇö spell may just not have stacks yet
    elseif _castCountSpells[spellID] == nil then
        -- Secret (combat): check DB for whether we've ever seen this spell with stacks
        local db = ECME.db
        if db and db.global and db.global.castCountSpells and db.global.castCountSpells[spellID] then
            _castCountSpells[spellID] = true
        end
    end
end

-------------------------------------------------------------------------------
--  Per-tick caches: wiped at the start of each UpdateAllCDMBars tick.
--  Avoids redundant C API calls when the same spellID appears on multiple
--  bars or is queried by both ApplySpellCooldown and ApplyStackCount.
-------------------------------------------------------------------------------
local _tickGCDCache   = {}  -- [spellID] = bool|nil (GCD check result)
local _tickChargeCache = {} -- [spellID] = charges table or false
local _tickAuraCache  = {}  -- [spellID] = aura table or false
local _tickBlizzActiveCache = {}  -- [spellID] = true when Blizzard CDM marks spell as active (wasSetFromAura)
local _tickBlizzOverrideCache = {} -- [baseSpellID] = overrideSpellID, built each tick from all CDM viewer children
local _tickBlizzChildCache = {}    -- [overrideSpellID] = blizzChild, for direct charge/cooldown reads on activation overrides
local _tickBlizzAllChildCache = {} -- [resolvedSid] = blizzChild, for all CDM children (used by custom bars)
-- spellID -> cooldownID map built once from C_CooldownViewer.GetCooldownViewerCategorySet (all categories).
-- Rebuilt on PLAYER_LOGIN and spec change. Used by custom bars to find CDM child frames by spellID.
local _spellToCooldownID = {}

local function RebuildSpellToCooldownID()
    wipe(_spellToCooldownID)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then return end
    for cat = 0, 3 do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    if info.spellID and info.spellID > 0 then
                        _spellToCooldownID[info.spellID] = cdID
                    end
                    if info.overrideSpellID and info.overrideSpellID > 0 then
                        _spellToCooldownID[info.overrideSpellID] = cdID
                    end
                end
            end
        end
    end
end

-- Scan all four CDM viewers for a child whose .cooldownID matches the given cooldownID.
-- Returns the child frame, or nil if not found.
local _cdmViewerNames = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}
local function FindCDMChildByCooldownID(cooldownID)
    if not cooldownID then return nil end
    for _, vname in ipairs(_cdmViewerNames) do
        local viewer = _G[vname]
        if viewer then
            for ci = 1, viewer:GetNumChildren() do
                local ch = select(ci, viewer:GetChildren())
                if ch then
                    local chID = ch.cooldownID or (ch.cooldownInfo and ch.cooldownInfo.cooldownID)
                    if chID == cooldownID then
                        return ch
                    end
                end
            end
        end
    end
    return nil
end

-- Keybind cache: built once out-of-combat, looked up per tick
local _cdmKeybindCache       = {}   -- [spellID] -> formatted key string
local _keybindRebuildPending = false
local _keybindCacheReady     = false  -- true after first successful build

-- FormatTime string cache: same floored-second = same string output.
-- Wiped when the integer second changes (not per tick).
local _fmtCache = {}
local _fmtCacheSec = -1

-- Combat state tracked via events (InCombatLockdown() can lag behind PLAYER_REGEN_DISABLED)
local _inCombat = false

-------------------------------------------------------------------------------
--  Consolidated cooldown/desat/charge-text helper (DurationObject approach)
--  Called from all update functions to avoid duplicating this logic.
--
--  Parameters:
--    icon       ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├àΓÇ£ our ECME icon frame (has _cooldown, _tex, _chargeText, etc.)
--    spellID    ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├àΓÇ£ resolved spell ID
--    desatOnCD  ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├àΓÇ£ boolean, whether to desaturate when on cooldown
--    showCharges ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├àΓÇ£ boolean, whether to show charge count text
--    swAlpha    ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├àΓÇ£ swipe alpha (number)
--    skipCD     ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├àΓÇ£ if true, skip cooldown application (e.g. aura already handled)
--
--  Returns: durObj (DurationObject|nil)
-------------------------------------------------------------------------------
local function ApplySpellCooldown(icon, spellID, desatOnCD, showCharges, swAlpha, skipCD)
    -- Ensure charge cache is populated (cheap: skips if already cached)
    CacheMultiChargeSpell(spellID)

    local isChargeSpell = _multiChargeSpells[spellID] == true

    -- Get duration objects directly (C functions handle secret values natively)
    local ccd = isChargeSpell and C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(spellID)
    local scd = C_Spell.GetSpellCooldownDuration(spellID)

    -- GCD check (per-tick cached to avoid pcall garbage per icon)
    local isGCD = _tickGCDCache[spellID]
    if isGCD == nil then
        _gcdCheckSid = spellID
        local okG, gcdVal = pcall(_CheckIsGCD)
        isGCD = okG and gcdVal or false
        _tickGCDCache[spellID] = isGCD
    end

    ---------------------------------------------------------------------------
    -- Dual invisible shadow Cooldown frames for charge state detection.
    --
    -- _scdShadow  (fed SCD, GCD filtered):
    --   During GCD: cleared so GCD doesn't pollute.
    --   Outside GCD: fed real SCD.
    --   IsShown()=true  ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó all charges depleted (only outside GCD)
    --
    -- _ccdShadow  (fed CCD, always live):
    --   IsShown()=true  ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó recharge active (checked only when SCD not shown)
    --
    -- State: isOnCooldown (0 charges), isRecharging (has charges, recharging)
    ---------------------------------------------------------------------------
    local isOnCooldown = false
    local isRecharging = false

    if isChargeSpell then
        if not icon._scdShadow then
            local s = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            s:SetAllPoints(icon)
            s:SetDrawSwipe(false)
            s:SetDrawEdge(false)
            s:SetDrawBling(false)
            s:SetHideCountdownNumbers(true)
            s:SetAlpha(0)
            icon._scdShadow = s
        end
        if not icon._ccdShadow then
            local s = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            s:SetAllPoints(icon)
            s:SetDrawSwipe(false)
            s:SetDrawEdge(false)
            s:SetDrawBling(false)
            s:SetHideCountdownNumbers(true)
            s:SetAlpha(0)
            icon._ccdShadow = s
        end

        -- Feed SCD shadow: clear during GCD, feed real SCD outside GCD
        if isGCD then
            icon._scdShadow:SetCooldown(0, 0)
        else
            icon._scdShadow:Clear()
            if scd then
                icon._scdShadow:SetCooldownFromDurationObject(scd, true)
            else
                icon._scdShadow:SetCooldown(0, 0)
            end
        end

        -- Feed CCD shadow live every tick
        icon._ccdShadow:Clear()
        if ccd then
            icon._ccdShadow:SetCooldownFromDurationObject(ccd, true)
        else
            icon._ccdShadow:SetCooldown(0, 0)
        end

        -- Read state: SCD first, CCD only when SCD not active
        isOnCooldown = icon._scdShadow:IsShown()
        if not isOnCooldown then
            isRecharging = icon._ccdShadow:IsShown()
        end
    end

    -- Cooldown display: always show swipe for charge spells (consistent behavior)
    if not skipCD then
        if isChargeSpell then
            if ccd then
                icon._cooldown:SetCooldownFromDurationObject(ccd, true)
            elseif scd then
                icon._cooldown:SetCooldownFromDurationObject(scd, true)
            else
                icon._cooldown:Clear()
            end
            icon._cooldown:SetDrawSwipe(true)
            icon._cooldown:SetDrawEdge(false)
        else
            if scd then
                icon._cooldown:SetCooldownFromDurationObject(scd, true)
                icon._cooldown:SetDrawSwipe(true)
            else
                icon._cooldown:Clear()
            end
        end
    end

    -- Desaturation: isOnCooldown = 0 charges (only true outside GCD).
    -- isRecharging = has charges but not full. Neither = ready or during GCD.
    local desatApplied = false
    if desatOnCD and not skipCD then
        if isOnCooldown and scd and scd.EvaluateRemainingDuration then
            local desatVal = scd:EvaluateRemainingDuration(ECME_DESAT_CURVE, 0) or 0
            icon._tex:SetDesaturation(desatVal)
            icon._lastDesat = true
            desatApplied = icon._cooldown:IsShown()
        elseif not isChargeSpell and not isGCD and scd and scd.EvaluateRemainingDuration then
            local desatVal = scd:EvaluateRemainingDuration(ECME_DESAT_CURVE, 0) or 0
            icon._tex:SetDesaturation(desatVal)
            icon._lastDesat = true
            desatApplied = icon._cooldown:IsShown()
        else
            if icon._lastDesat then
                icon._tex:SetDesaturation(0)
                icon._lastDesat = false
            end
        end
    elseif icon._lastDesat then
        icon._tex:SetDesaturation(0)
        icon._lastDesat = false
    end

    -- Resource check: desaturate if spell is off CD but not usable (insufficient power)
    if desatOnCD and not desatApplied and not skipCD then
        local usable = C_Spell.IsSpellUsable(spellID)
        if not usable then
            icon._tex:SetDesaturation(1)
            icon._lastDesat = true
        end
    end

    -- Charge text: show spell charges for charge-based spells, or aura stacks as fallback
    if showCharges then
        if isChargeSpell then
            local charges = _tickChargeCache[spellID]
            if charges == nil then
                charges = C_Spell.GetSpellCharges(spellID) or false
                _tickChargeCache[spellID] = charges
            end
            if charges and charges.currentCharges ~= nil then
                icon._chargeText:SetText(charges.currentCharges)
                icon._chargeText:Show()
            else
                icon._chargeText:Hide()
            end
        else
            -- Fallback: show aura stack count for buff spells (per-tick cached)
            local aura = _tickAuraCache[spellID]
            if aura == nil then
                local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
                aura = (ok and res) or false
                _tickAuraCache[spellID] = aura
            end
            if aura and aura.applications and not (issecretvalue and issecretvalue(aura.applications)) and aura.applications > 1 then
                icon._chargeText:SetText(aura.applications)
                icon._chargeText:Show()
            elseif C_Spell.GetSpellCastCount then
                -- Cast count fallback for spells that accumulate stacks via
                -- the cast count system rather than auras.
                -- Only attempt for confirmed cast-count spells (cached OOC).
                -- In combat, returns secret values ΓÇö pass directly to SetText.
                CacheCastCountSpell(spellID)
                if _castCountSpells[spellID] then
                    local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
                    if ok and count then
                        if issecretvalue and issecretvalue(count) then
                            -- Secret (combat): show directly, FontStrings render secrets.
                            -- We cannot compare or read back the value without tainting.
                            icon._chargeText:SetText(count)
                            icon._chargeText:Show()
                        elseif count > 0 then
                            icon._chargeText:SetText(count)
                            icon._chargeText:Show()
                        else
                            icon._chargeText:Hide()
                        end
                    else
                        icon._chargeText:Hide()
                    end
                else
                    icon._chargeText:Hide()
                end
            else
                icon._chargeText:Hide()
            end
        end
    else
        icon._chargeText:Hide()
    end

    return scd
end

-------------------------------------------------------------------------------
--  Trinket cooldown helper (inventory slot based)
--  Handles cooldown display and desaturation for trinket slots.
-------------------------------------------------------------------------------
local function ApplyTrinketCooldown(icon, slot, desatOnCD)
    local start, dur, enable = GetInventoryItemCooldown("player", slot)
    if start and dur and dur > 1.5 and enable == 1 then
        icon._cooldown:SetCooldown(start, dur)
        if desatOnCD then
            icon._tex:SetDesaturation(1)
            icon._lastDesat = true
        elseif icon._lastDesat then
            icon._tex:SetDesaturation(0)
            icon._lastDesat = false
        end
    else
        icon._cooldown:Clear()
        if icon._lastDesat then
            icon._tex:SetDesaturation(0)
            icon._lastDesat = false
        end
    end
    icon._chargeText:Hide()
end

-------------------------------------------------------------------------------
--  Active state animation helper (aura glow / swipe color)
--  Handles transition between active and inactive visual states.
-------------------------------------------------------------------------------
local function ApplyActiveAnimation(icon, auraHandled, barData, barKey, activeAnim, animR, animG, animB, swAlpha)
    local skipActiveAnim = barData.hideBuffsWhenInactive and (barKey == "buffs" or barData.barType == "buffs")
    if not skipActiveAnim and auraHandled and not icon._isActive then
        if activeAnim ~= "none" and activeAnim ~= "hideActive" then
            icon._cooldown:SetSwipeColor(animR, animG, animB, swAlpha)
            local glowIdx = tonumber(activeAnim)
            -- Don't overwrite proc glow with active state glow
            if glowIdx and icon._glowOverlay and not icon._procGlowActive then
                StartNativeGlow(icon._glowOverlay, glowIdx, animR, animG, animB)
            end
        end
    elseif (skipActiveAnim or not auraHandled) and icon._isActive then
        icon._cooldown:SetSwipeColor(0, 0, 0, swAlpha)
        -- Don't stop glow if proc glow is active (it owns the overlay)
        if icon._glowOverlay and not icon._procGlowActive then
            StopNativeGlow(icon._glowOverlay)
        end
    end
    icon._isActive = not skipActiveAnim and auraHandled
end

-------------------------------------------------------------------------------
--  Stack count helper (aura applications text)
--  Hooks blizzChild.Applications Show/Hide to mirror CDM's stack display onto
--  our _stackText. CDM already handles secret values and only shows Applications
--  when stacks > 1, so we trust its Show/Hide as the gate ΓÇö no text comparison needed.
-------------------------------------------------------------------------------
local _stackHookedChildren = {}  -- [blizzChild] = true

local function HookBlizzChildApplications(blizzChild)
    if not blizzChild or _stackHookedChildren[blizzChild] then return end
    local appsFrame = blizzChild.Applications
    if not appsFrame then return end
    local appsText = appsFrame.Applications
    if not appsText then return end

    _stackHookedChildren[blizzChild] = true

    -- CDM only calls Show() on Applications when stacks > 1, so no text check needed.
    -- GetText() returns a secret string in combat ΓÇö pass it directly to SetText,
    -- WoW renders secret values correctly without comparison.
    hooksecurefunc(appsFrame, "Show", function()
        local ourIcon = blizzChild._ecmeIcon
        if not ourIcon or not ourIcon._stackText then return end
        -- Guard against stale refs when the child is reused for a different icon
        if ourIcon._blizzChild ~= blizzChild then return end
        local ok, txt = pcall(appsText.GetText, appsText)
        if ok and txt then
            ourIcon._stackText:SetText(txt)
            ourIcon._stackText:Show()
        end
    end)

    hooksecurefunc(appsFrame, "Hide", function()
        local ourIcon = blizzChild._ecmeIcon
        -- Only hide if this child is still mapped to this icon (guard against stale refs)
        if ourIcon and ourIcon._stackText and ourIcon._blizzChild == blizzChild then
            ourIcon._stackText:Hide()
        end
    end)
end

local function ApplyStackCount(icon, resolvedSid, auraInstanceID, auraUnit, showStackCount, blizzChild)
    if not icon._stackText then return end

    if not showStackCount then
        icon._stackText:Hide()
        return
    end

    if blizzChild then
        blizzChild._ecmeIcon = icon
        HookBlizzChildApplications(blizzChild)

        -- Sync current state: mirror whatever CDM currently has showing
        local appsFrame = blizzChild.Applications
        if appsFrame and appsFrame:IsShown() then
            local appsText = appsFrame.Applications
            if appsText then
                local ok, txt = pcall(appsText.GetText, appsText)
                if ok and txt then
                    icon._stackText:SetText(txt)
                    icon._stackText:Show()
                    return
                end
            end
        end
        -- Applications frame not showing ΓÇö fall through to aura lookup below.
        -- Spells like Sheilun's Gift and Mana Tea accumulate stacks as a
        -- player buff but Blizzard's CDM may not populate the Applications
        -- sub-frame for them.
    end

    -- Aura-based stack lookup: check the resolved spell ID for applications
    if resolvedSid and resolvedSid > 0 then
        local aura = _tickAuraCache[resolvedSid]
        if aura == nil then
            local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedSid)
            aura = (ok and res) or false
            _tickAuraCache[resolvedSid] = aura
        end
        if aura then
            local apps = aura.applications
            if apps ~= nil and not (issecretvalue and issecretvalue(apps)) and apps > 1 then
                icon._stackText:SetText(tostring(apps))
                icon._stackText:Show()
                return
            end
        end
    end

    -- Final fallback: use auraInstanceID to look up the aura directly.
    if auraInstanceID and auraUnit then
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, auraUnit, auraInstanceID)
        if ok and auraData then
            local apps = auraData.applications
            if apps ~= nil and not (issecretvalue and issecretvalue(apps)) and apps > 1 then
                icon._stackText:SetText(tostring(apps))
                icon._stackText:Show()
                return
            end
        end
    end

    -- Cast count fallback: spells that accumulate stacks via the cast count
    -- system rather than auras (e.g. Sheilun's Gift clouds, Mana Tea).
    -- Only attempt for spells confirmed to use cast counts (cached OOC).
    -- In combat, GetSpellCastCount returns secret values ΓÇö pass them directly
    -- to SetText (FontStrings render secrets natively), same as charge text.
    if resolvedSid and resolvedSid > 0 and C_Spell.GetSpellCastCount then
        CacheCastCountSpell(resolvedSid)
        if _castCountSpells[resolvedSid] then
            local ok, count = pcall(C_Spell.GetSpellCastCount, resolvedSid)
            if ok and count then
                if issecretvalue and issecretvalue(count) then
                    -- Secret (combat): show directly, FontStrings render secrets.
                    -- We cannot compare or read back the value without tainting.
                    icon._stackText:SetText(count)
                    icon._stackText:Show()
                    return
                elseif count > 0 then
                    icon._stackText:SetText(tostring(count))
                    icon._stackText:Show()
                    return
                end
            end
        end
    end

    icon._stackText:Hide()
end
local BuildAllCDMBars
local RegisterCDMUnlockElements

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local DEFAULTS = {
    global = {
        multiChargeSpells = {},
    },
    profile = {
        _capturedOnce = false,
        -- CDM Look
        reskinBorders   = true,
        utilityScale    = 1.0,
        buffBarScale    = 1.0,
        cooldownBarScale = 1.0,
        -- Bar Glows (per-spec)
        spec            = {},
        activeSpecKey   = "0",
        -- Bar Glows v2 (buff ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó action button glow assignments)
        barGlows = {
            enabled = true,
            selectedBar = 1,
            selectedButton = nil,
            selectedAssignment = 1,
            assignments = {},  -- ["barIdx_btnIdx"] = { {spellID, glowStyle, glowColor, classColor, mode}, ... }
        },
        -- Buff Bars (legacy ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ kept for migration)
        buffBars = {
            enabled     = false,
            width       = 200,
            height      = 18,
            spacing     = 2,
            maxBars     = 8,
            growUp      = false,
            showTimer   = true,
            showIcon    = true,
            iconSize    = 18,
            borderSize  = 1,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            bgAlpha     = 0.4,
            barR        = 0.05, barG = 0.82, barB = 0.62,
            useClassColor = false,
            filterMode  = "all",  -- "all", "whitelist", "blacklist"
            filterList  = "",
            locked      = false,
            offsetX     = 300,
            offsetY     = -200,
        },
        -- Tracked Buff Bars v2 (per-bar buff tracking with individual settings)
        -- Note: not in defaults ΓÇö lazy-initialized by ns.GetTrackedBuffBars() to avoid AceDB merge issues
        -- CDM Bars (our replacement for Blizzard CDM)
        cdmBars = {
            enabled = true,
            hideBlizzard = true,
            -- Default bar template (applied to each bar)
            barDefaults = {
                iconSize    = 36,
                numRows     = 1,
                spacing     = 2,
                borderSize  = 1,
                borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
                borderClassColor = false,
                bgR         = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                iconZoom    = 0.08,
                iconShape   = "none",
                growDirection = "RIGHT",
                verticalOrientation = false,
                barBgEnabled = false,
                barBgAlpha  = 1.0,
                barBgR = 0, barBgG = 0, barBgB = 0,
                showCooldownText = true,
                cooldownFontSize = 12,
                showCharges = true,
                chargeFontSize = 11,
                desaturateOnCD = true,
                swipeAlpha  = 0.7,
                borderThickness = "thin",
                activeStateAnim = "blizzard",
                activeAnimClassColor = false,
                activeAnimR = 1.0, activeAnimG = 0.85, activeAnimB = 0.0,
                anchorTo = "none",
                anchorPosition = "left",
                anchorOffsetX = 0,
                anchorOffsetY = 0,
                barVisibility = "always",
                housingHideEnabled = true,
                hideBuffsWhenInactive = true,
                showStackCount = false,
                stackCountSize = 11,
                stackCountX = 0,
                stackCountY = 0,
                stackCountR = 1, stackCountG = 1, stackCountB = 1,
                showTooltip = false,
                showKeybind = false,
                keybindSize = 10,
                keybindOffsetX = 2,
                keybindOffsetY = -2,
                keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
            },
            -- The 3 default bars (match Blizzard CDM)
            bars = {
                {
                    key = "cooldowns", name = "Cooldowns", enabled = true,
                    barScale = 1.0, iconSize = 42, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false,
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none", growDirection = "RIGHT",
                    verticalOrientation = false, barBgEnabled = false, barBgAlpha = 1.0,
                    barBgR = 0, barBgG = 0, barBgB = 0,
                    showCooldownText = true, cooldownFontSize = 12,
                    showCharges = true, chargeFontSize = 11,
                    desaturateOnCD = true, swipeAlpha = 0.7,
                    borderThickness = "thin", activeStateAnim = "blizzard",
                    activeAnimClassColor = false, activeAnimR = 1.0, activeAnimG = 0.85, activeAnimB = 0.0,
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    hideBuffsWhenInactive = true,
                    showStackCount = false, stackCountSize = 11,
                    stackCountX = 0, stackCountY = 0,
                    stackCountR = 1, stackCountG = 1, stackCountB = 1,
                    showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2,
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
                {
                    key = "utility", name = "Utility", enabled = true,
                    barScale = 1.0, iconSize = 36, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false,
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none", growDirection = "RIGHT",
                    verticalOrientation = false, barBgEnabled = false, barBgAlpha = 1.0,
                    barBgR = 0, barBgG = 0, barBgB = 0,
                    showCooldownText = true, cooldownFontSize = 12,
                    showCharges = true, chargeFontSize = 11,
                    desaturateOnCD = true, swipeAlpha = 0.7,
                    borderThickness = "thin", activeStateAnim = "blizzard",
                    activeAnimClassColor = false, activeAnimR = 1.0, activeAnimG = 0.85, activeAnimB = 0.0,
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    hideBuffsWhenInactive = true,
                    showStackCount = false, stackCountSize = 11,
                    stackCountX = 0, stackCountY = 0,
                    stackCountR = 1, stackCountG = 1, stackCountB = 1,
                    showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2,
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
                {
                    key = "buffs", name = "Buffs", enabled = true,
                    barScale = 1.0, iconSize = 32, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false,
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none", growDirection = "RIGHT",
                    verticalOrientation = false, barBgEnabled = false, barBgAlpha = 1.0,
                    barBgR = 0, barBgG = 0, barBgB = 0,
                    showCooldownText = true, cooldownFontSize = 12,
                    showCharges = true, chargeFontSize = 11,
                    desaturateOnCD = true, swipeAlpha = 0.7,
                    borderThickness = "thin", activeStateAnim = "blizzard",
                    activeAnimClassColor = false, activeAnimR = 1.0, activeAnimG = 0.85, activeAnimB = 0.0,
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    hideBuffsWhenInactive = true,
                    showStackCount = false, stackCountSize = 11,
                    stackCountX = 0, stackCountY = 0,
                    stackCountR = 1, stackCountG = 1, stackCountB = 1,
                    showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2,
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
            },
        },
        -- Saved positions for CDM bars (keyed by bar key)
        cdmBarPositions = {},
        -- Saved positions for tracked buff bars (keyed by bar index string)
        tbbPositions = {},
        -- Per-spec profiles: spell lists, bar glows, buff bars (keyed by specID string)
        specProfiles = {},
    },
}

-------------------------------------------------------------------------------
--  Spec helpers
-------------------------------------------------------------------------------
local function GetCurrentSpecKey()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return "0" end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return tostring(specID or 0)
end

-- Validates that activeSpecKey matches the real spec. If not, triggers a full
-- spec switch. Called from multiple events as a safety net so the CDM can
-- NEVER show the wrong spec's icons.
local _specValidated = false
local function ValidateSpec()
    if not ECME.db then return end
    local realKey = GetCurrentSpecKey()
    if realKey == "0" then return end  -- spec API not ready yet
    local p = ECME.db.profile
    if p.activeSpecKey == realKey then
        _specValidated = true
        return
    end
    -- Mismatch detected ΓÇö force a full spec switch
    _specValidated = true
    -- SwitchSpecProfile is defined later; called via ns reference
    if ns.SwitchSpecProfile then
        ns.SwitchSpecProfile(realKey)
    end
end

local function EnsureSpec(profile, key)
    profile.spec[key] = profile.spec[key] or { mappings = {}, selectedMapping = 1 }
    return profile.spec[key]
end

local function GetStore()
    local p = ECME.db.profile
    return EnsureSpec(p, p.activeSpecKey or "0")
end

local function EnsureMappings(store)
    if not store.mappings then store.mappings = {} end
    if #store.mappings == 0 then
        store.mappings[1] = {
            enabled = false, name = DEFAULT_MAPPING_NAME,
            actionBar = 1, actionButton = 1, cdmSlot = 1,
            hideFromCDM = false, mode = "ACTIVE",
            glowStyle = 1, glowColor = { r = 1, g = 0.82, b = 0.1 },
        }
    end
    store.selectedMapping = tonumber(store.selectedMapping) or 1
    if store.selectedMapping < 1 then store.selectedMapping = 1 end
    if store.selectedMapping > #store.mappings then store.selectedMapping = #store.mappings end
    for _, m in ipairs(store.mappings) do
        if m.enabled == nil then m.enabled = true end
        if m.hideFromCDM == nil then m.hideFromCDM = false end
        if m.mode ~= "MISSING" then m.mode = "ACTIVE" end
        m.glowStyle = tonumber(m.glowStyle) or 1
        if not m.glowColor then m.glowColor = { r = 1, g = 0.82, b = 0.1 } end
        m.name = tostring(m.name or "")
        if type(m.actionBar) ~= "string" or not ns.CDM_BAR_ROOTS[m.actionBar] then
            m.actionBar = tonumber(m.actionBar) or 1
        end
        m.actionButton = tonumber(m.actionButton) or 1
        m.cdmSlot = tonumber(m.cdmSlot) or 1
    end
end

-- Expose for options
ns.DEFAULT_MAPPING_NAME = DEFAULT_MAPPING_NAME
ns.GetStore = GetStore
ns.EnsureMappings = EnsureMappings

-------------------------------------------------------------------------------
--  Per-Spec Profile Helpers
--  Saves/restores spell lists, bar glows, and buff bars per specialization.
--  Bar structure, settings, and positions are shared across all specs.
-------------------------------------------------------------------------------
local MAIN_BAR_KEYS = { cooldowns = true, utility = true, buffs = true }

--- Deep-copy a table (simple values + nested tables, no metatables/functions)
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = DeepCopy(v) end
    return copy
end

--- Save the current spec's per-spec data into specProfiles[specKey]
local function SaveCurrentSpecProfile()
    local p = ECME.db.profile
    local specKey = p.activeSpecKey
    if not specKey or specKey == "0" then return end
    if not p.specProfiles then p.specProfiles = {} end

    local prof = {}

    -- 1) Spell lists for each bar
    prof.barSpells = {}
    for _, barData in ipairs(p.cdmBars.bars) do
        local key = barData.key
        if key then
            local entry = {}
            if MAIN_BAR_KEYS[key] then
                -- trackedSpells are session-ephemeral Blizzard cooldownIDs ΓÇö don't persist them.
                -- Persist removedSpells (spellIDs) so user removals survive reloads.
                entry.extraSpells   = DeepCopy(barData.extraSpells)
                entry.removedSpells = DeepCopy(barData.removedSpells)
            elseif barData.barType ~= "trinkets" then
                -- Custom non-trinket bars: save customSpells
                entry.customSpells = DeepCopy(barData.customSpells)
            end
            -- Trinket/racial/potion bars: nothing to save (refreshed on login)
            prof.barSpells[key] = entry
        end
    end

    -- 2) Bar Glows (full table)
    prof.barGlows = DeepCopy(p.barGlows)

    -- 3) Tracked buff bar state
    if p.trackedBuffBars then
        prof.trackedBuffBars = DeepCopy(p.trackedBuffBars)
    end
    if p.tbbPositions then
        prof.tbbPositions = DeepCopy(p.tbbPositions)
    end

    p.specProfiles[specKey] = prof
end

--- Restore a spec profile into the live data, or initialize fresh if none exists
local function LoadSpecProfile(specKey)
    local p = ECME.db.profile
    if not p.specProfiles then p.specProfiles = {} end
    local prof = p.specProfiles[specKey]

    if prof then
        -- Restore saved spell lists
        if prof.barSpells then
            for _, barData in ipairs(p.cdmBars.bars) do
                local saved = prof.barSpells[barData.key]
                if saved then
                    if MAIN_BAR_KEYS[barData.key] then
                        -- trackedSpells are Blizzard-internal cooldownIDs that are
                        -- session-ephemeral ΓÇö never restore them across reloads.
                        -- Always re-snapshot from the live Blizzard CDM on login.
                        barData.trackedSpells = nil
                        barData.extraSpells   = DeepCopy(saved.extraSpells)
                        barData.removedSpells = DeepCopy(saved.removedSpells)
                    elseif barData.barType ~= "trinkets" then
                        barData.customSpells = DeepCopy(saved.customSpells)
                    end
                else
                    -- Bar exists now but wasn't in the saved profile (new bar added since)
                    if MAIN_BAR_KEYS[barData.key] then
                        barData.trackedSpells = nil  -- will trigger Blizzard snapshot
                        barData.extraSpells = nil
                        barData.removedSpells = nil
                    elseif barData.barType ~= "trinkets" then
                        barData.customSpells = {}
                    end
                end
            end
        end

        -- Restore bar glows
        if prof.barGlows then
            p.barGlows = DeepCopy(prof.barGlows)
        end

        -- Restore tracked buff bar state
        if prof.trackedBuffBars ~= nil then
            p.trackedBuffBars = DeepCopy(prof.trackedBuffBars)
        end
        if prof.tbbPositions ~= nil then
            p.tbbPositions = DeepCopy(prof.tbbPositions)
        end
    else
        -- No saved profile for this spec: initialize fresh
        -- Main bars: clear trackedSpells so SnapshotBlizzardCDM re-captures
        for _, barData in ipairs(p.cdmBars.bars) do
            if MAIN_BAR_KEYS[barData.key] then
                barData.trackedSpells = nil
                barData.extraSpells = nil
                barData.removedSpells = nil
            elseif barData.barType ~= "trinkets" then
                barData.customSpells = {}
            end
        end

        -- Reset bar glows to fresh state
        p.barGlows = {
            enabled = true,
            selectedBar = 1,
            selectedButton = nil,
            selectedAssignment = 1,
            assignments = {},
        }
    end

    -- Fix anchors: if a custom bar is anchored to a bar key that no longer
    -- has spells (went blank on spec switch), un-anchor it.
    -- Only applies to trinket/racial/potion bars anchored to custom bars.
    local barKeySet = {}
    for _, barData in ipairs(p.cdmBars.bars) do
        barKeySet[barData.key] = barData
    end
    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.barType == "trinkets" and barData.anchorTo and barData.anchorTo ~= "none" then
            local anchor = barKeySet[barData.anchorTo]
            if anchor and anchor.barType ~= "trinkets" and not MAIN_BAR_KEYS[anchor.key] then
                -- Anchored to a custom bar ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ check if that bar has spells
                local spells = anchor.customSpells
                if not spells or #spells == 0 then
                    barData.anchorTo = "none"
                    barData.anchorPosition = "left"
                    barData.anchorOffsetX = 0
                    barData.anchorOffsetY = 0
                end
            end
        end
    end
end

--- Full spec switch: save current, load new, rebuild everything
local function SwitchSpecProfile(newSpecKey)
    local p = ECME.db.profile
    local oldSpecKey = p.activeSpecKey

    -- Save current spec (if valid)
    if oldSpecKey and oldSpecKey ~= "0" then
        SaveCurrentSpecProfile()
    end

    -- Update active spec
    p.activeSpecKey = newSpecKey
    EnsureSpec(p, newSpecKey)

    -- Load new spec profile
    LoadSpecProfile(newSpecKey)

    -- Rebuild all CDM systems (deferred so Blizzard CDM frames are ready)
    C_Timer.After(0.5, function()
        BuildAllCDMBars()
        ns.BuildTrackedBuffBars()
        RegisterCDMUnlockElements()
        C_Timer.After(1, ForceResnapshotMainBars)
        C_Timer.After(3, ForceResnapshotMainBars)
        ForcePopulateBlizzardViewers(function()
            ForceResnapshotMainBars()
            StartResnapshotRetry()
        end)

        -- Refresh options panel if open
        if EllesmereUI and EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
            if EllesmereUI.InvalidateContentHeaderCache then
                EllesmereUI:InvalidateContentHeaderCache()
            end
            if EllesmereUI.RefreshPage then
                EllesmereUI:RefreshPage()
            end
        end
    end)
end
ns.SwitchSpecProfile = SwitchSpecProfile

-------------------------------------------------------------------------------
--  CDM Bar Roots
-------------------------------------------------------------------------------
ns.CDM_BAR_ROOTS = {
    CDM_COOLDOWN = "EssentialCooldownViewer",
    CDM_UTILITY  = "UtilityCooldownViewer",
}

-------------------------------------------------------------------------------
--  Action Button Lookup (supports Blizzard and popular bar addons)
-------------------------------------------------------------------------------
local blizzBarNames = {
    [2] = "MultiBarBottomLeftButton",
    [3] = "MultiBarBottomRightButton",
    [4] = "MultiBarRightButton",
    [5] = "MultiBarLeftButton",
    [6] = "MultiBar5Button",
    [7] = "MultiBar6Button",
    [8] = "MultiBar7Button",
}

local actionButtonCache = {}

local function FirstExisting(...)
    for i = 1, select("#", ...) do
        local f = _G[select(i, ...)]
        if f then return f end
    end
end

local function GetActionButton(bar, i)
    bar = bar or 1
    local cacheKey = bar * 100 + i
    if actionButtonCache[cacheKey] then return actionButtonCache[cacheKey] end
    local btn
    if bar == 1 then
        btn = FirstExisting(
            "BT4Button" .. i, "ElvUI_Bar1Button" .. i,
            "DominosActionButton" .. i, "ActionButton" .. i)
    else
        local offset = (bar - 1) * 12
        local blizz = blizzBarNames[bar]
        btn = FirstExisting(
            "BT4Button" .. (offset + i),
            "ElvUI_Bar" .. bar .. "Button" .. i,
            "DominosActionButton" .. (offset + i),
            blizz and (blizz .. i) or nil)
    end
    if btn then actionButtonCache[cacheKey] = btn end
    return btn
end

-------------------------------------------------------------------------------
--  CDM Slot Helpers
-------------------------------------------------------------------------------
local function FindCooldown(frame)
    if not frame then return end
    local cd = frame.cooldown or frame.Cooldown
    if cd then return cd end
    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
        if child and child.GetObjectType and child:GetObjectType() == "Cooldown" then
            return child
        end
    end
end

local function SlotSortComparator(a, b)
    local ax, ay = a:GetCenter()
    local bx, by = b:GetCenter()
    ax, ay, bx, by = ax or 0, ay or 0, bx or 0, by or 0
    if abs(ay - by) > 2 then return ay > by end
    return ax < bx
end

local cachedSlots, cacheTime = nil, 0
local CACHE_DURATION = 0.5

local function GetSortedSlots(forceRefresh)
    local now = GetTime()
    if not forceRefresh and cachedSlots and (now - cacheTime) < CACHE_DURATION then
        return cachedSlots
    end
    local root = _G.BuffIconCooldownViewer
    if not root or not root.GetChildren then cachedSlots = nil; return nil end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetCenter and FindCooldown(c) then
            slots[#slots + 1] = c
        end
    end
    if #slots == 0 then cachedSlots = nil; return nil end
    table.sort(slots, SlotSortComparator)
    cachedSlots = slots
    cacheTime = now
    return slots
end

local function GetAllCDMSlots(root)
    if not root or not root.GetChildren then return {} end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetWidth and c:GetWidth() > 5 then
            slots[#slots + 1] = c
        end
    end
    return slots
end

local function GetCDMBarButton(barKey, slotIndex)
    local rootName = ns.CDM_BAR_ROOTS[barKey]
    if not rootName then return nil end
    local root = _G[rootName]
    if not root or not root.GetChildren then return nil end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetWidth and c:GetWidth() > 5 then
            slots[#slots + 1] = c
        end
    end
    if #slots == 0 then return nil end
    table.sort(slots, SlotSortComparator)
    return slots[slotIndex]
end

local function GetTargetButton(actionBar, actionButtonIndex)
    if type(actionBar) == "string" and ns.CDM_BAR_ROOTS[actionBar] then
        return GetCDMBarButton(actionBar, actionButtonIndex)
    end
    return GetActionButton(tonumber(actionBar) or 1, actionButtonIndex)
end

-------------------------------------------------------------------------------
--  CDM Look: Border Reskinning
-------------------------------------------------------------------------------
local cdmBorderFrames = {}
local safeEq = function(a, b) return a == b end
local cdmBorderBackdrop = { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local function GetOrCreateCDMBorder(slot)
    if cdmBorderFrames[slot] then return cdmBorderFrames[slot] end

    slot.__ECMEHidden   = slot.__ECMEHidden or {}
    slot.__ECMEIcon     = slot.__ECMEIcon or nil
    slot.__ECMECooldown = slot.__ECMECooldown or nil

    if not slot.__ECMEScanned then
        slot.__ECMEHidden = {}
        slot.__ECMEIcon = nil
        slot.__ECMECooldown = nil

        for ri = 1, slot:GetNumRegions() do
            local region = select(ri, slot:GetRegions())
            if region and region.GetObjectType then
                local objType = region:GetObjectType()
                if objType == "MaskTexture" then
                    slot.__ECMEHidden[#slot.__ECMEHidden + 1] = region
                elseif objType == "Texture" then
                    local ok, rawLayer = pcall(region.GetDrawLayer, region)
                    if ok and rawLayer ~= nil then
                        local okB, isBorder   = pcall(safeEq, rawLayer, "BORDER")
                        local okO, isOverlay  = pcall(safeEq, rawLayer, "OVERLAY")
                        local okA, isArtwork  = pcall(safeEq, rawLayer, "ARTWORK")
                        local okG, isBG       = pcall(safeEq, rawLayer, "BACKGROUND")
                        if (okB and isBorder) or (okO and isOverlay) then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = region
                        elseif not slot.__ECMEIcon and ((okA and isArtwork) or (okG and isBG)) then
                            slot.__ECMEIcon = region
                        end
                    end
                end
            end
        end

        for ci = 1, slot:GetNumChildren() do
            local child = select(ci, slot:GetChildren())
            if child and child.GetObjectType then
                local objType = child:GetObjectType()
                if objType == "MaskTexture" then
                    slot.__ECMEHidden[#slot.__ECMEHidden + 1] = child
                elseif objType == "Cooldown" then
                    slot.__ECMECooldown = child
                    for k = 1, child:GetNumChildren() do
                        local cdChild = select(k, child:GetChildren())
                        if cdChild and cdChild.GetObjectType and cdChild:GetObjectType() == "MaskTexture" then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = cdChild
                        end
                    end
                    for k = 1, child:GetNumRegions() do
                        local cdRegion = select(k, child:GetRegions())
                        if cdRegion and cdRegion.GetObjectType and cdRegion:GetObjectType() == "MaskTexture" then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = cdRegion
                        end
                    end
                end
            end
        end
        slot.__ECMEScanned = true
    end

    local iconSize = slot.__ECMEIcon and slot.__ECMEIcon:GetWidth() or slot:GetWidth() or 35
    local edgeSize = iconSize < 35 and 2 or 1

    local border = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    if slot.__ECMEIcon then border:SetAllPoints(slot.__ECMEIcon) else border:SetAllPoints() end
    border:SetFrameLevel(slot:GetFrameLevel() + 5)
    cdmBorderBackdrop.edgeSize = edgeSize
    border:SetBackdrop(cdmBorderBackdrop)
    border:SetBackdropBorderColor(0, 0, 0, 1)

    cdmBorderFrames[slot] = border
    return border
end

local CDM_ROOT_NAMES = {
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
    "EssentialCooldownViewer", "UtilityCooldownViewer",
}

local function UpdateUtilityScale()
    local utility = _G.UtilityCooldownViewer
    if utility and ECME.db then
        utility:SetScale(ECME.db.profile.utilityScale or 1.0)
    end
end

local function UpdateBuffBarScale()
    local buffBar = _G.BuffIconCooldownViewer
    if buffBar and ECME.db then
        buffBar:SetScale(ECME.db.profile.buffBarScale or 1.0)
    end
end

local function UpdateCooldownBarScale()
    local cdBar = _G.EssentialCooldownViewer
    if cdBar and ECME.db then
        cdBar:SetScale(ECME.db.profile.cooldownBarScale or 1.0)
    end
end

local function UpdateAllCDMBorders()
    local reskin = ECME.db and ECME.db.profile.reskinBorders
    local crop = 0.06

    UpdateUtilityScale()
    UpdateBuffBarScale()
    UpdateCooldownBarScale()

    for _, rootName in ipairs(CDM_ROOT_NAMES) do
        local root = _G[rootName]
        if root then
            for _, slot in ipairs(GetAllCDMSlots(root)) do
                local border = GetOrCreateCDMBorder(slot)
                if reskin then
                    border:Show()
                    if slot.__ECMEIcon then slot.__ECMEIcon:SetTexCoord(crop, 1 - crop, crop, 1 - crop) end
                    if slot.__ECMECooldown then
                        slot.__ECMECooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
                    end
                    for _, h in ipairs(slot.__ECMEHidden) do
                        if h and h.Hide then h:Hide() end
                    end
                else
                    border:Hide()
                    if slot.__ECMEIcon then slot.__ECMEIcon:SetTexCoord(0, 1, 0, 1) end
                    if slot.__ECMECooldown then
                        slot.__ECMECooldown:SetSwipeTexture("Interface\\Cooldown\\cooldown-bling")
                    end
                    for _, h in ipairs(slot.__ECMEHidden) do
                        if h and h.Show then h:Show() end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Native Glow System ΓÇö engines provided by shared EllesmereUI_Glows.lua
--  CDM keeps its own GLOW_STYLES (different scale values) and Start/Stop
--  wrappers that handle CDM-specific shape glow (icon masks/borders).
-------------------------------------------------------------------------------
local _G_Glows = EllesmereUI.Glows
local GLOW_STYLES = {
    { name = "Pixel Glow",           procedural = true },
    { name = "Custom Shape Glow",    shapeGlow = true, scale = 1.20 },
    { name = "Action Button Glow",   buttonGlow = true, scale = 1.16 },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook",  scale = 1.41 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",  scale = 1.53 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, scale = 1.03 },
}
ns.GLOW_STYLES = GLOW_STYLES

StartNativeGlow = function(overlay, style, cr, cg, cb)
    if not overlay then return end
    local styleIdx = tonumber(style) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then styleIdx = 1 end
    local entry = GLOW_STYLES[styleIdx]

    _G_Glows.StopAllGlows(overlay)

    local parent = overlay:GetParent()
    if not parent then return end
    local pW, pH = parent:GetWidth(), parent:GetHeight()
    local sz = math.min(pW, pH)
    if sz < 5 then sz = 36 end
    cr = cr or 1; cg = cg or 1; cb = cb or 1

    if entry.shapeGlow then
        -- CDM-specific: read shape mask/border from the icon frame
        local icon = parent
        local shape = icon._shapeApplied and icon._shapeName or nil
        local maskPath   = shape and CDM_SHAPE_MASKS[shape]
        local borderPath = shape and CDM_SHAPE_BORDERS[shape]
        _G_Glows.StartShapeGlow(overlay, sz, cr, cg, cb, entry.scale or 1.20, {
            maskPath   = maskPath,
            borderPath = borderPath,
            shapeMask  = icon._shapeMask,
        })
    elseif entry.procedural then
        local N = 8; local th = 2; local period = 4
        local lineLen = math.floor((sz + sz) * (2 / N - 0.1))
        lineLen = math.min(lineLen, sz)
        if lineLen < 1 then lineLen = 1 end
        _G_Glows.StartProceduralAnts(overlay, N, th, period, lineLen, cr, cg, cb, sz)
    elseif entry.buttonGlow then
        _G_Glows.StartButtonGlow(overlay, sz, cr, cg, cb, entry.scale or 1.16)
    elseif entry.autocast then
        _G_Glows.StartAutoCastShine(overlay, sz, cr, cg, cb, 1.0)
    else
        _G_Glows.StartFlipBookGlow(overlay, sz, entry, cr, cg, cb)
    end

    overlay._glowActive = true
    overlay:SetAlpha(1)
    overlay:Show()
end

StopNativeGlow = function(overlay)
    if not overlay then return end
    _G_Glows.StopAllGlows(overlay)
    overlay._glowActive = false
    overlay:SetAlpha(0)
end
ns.StartNativeGlow = StartNativeGlow
ns.StopNativeGlow = StopNativeGlow

-- Our bar frames (keyed by bar key)
local cdmBarFrames = {}
-- Icon frames per bar (keyed by bar key, array of icon frames)
local cdmBarIcons = {}
-- Fast barData lookup by key (rebuilt in BuildAllCDMBars, avoids linear scan per tick)
local barDataByKey = {}

-- Expose our CDM bar frames so the glow system can reference them
ns.GetCDMBarFrame = function(barKey)
    return cdmBarFrames[barKey]
end
-- Global accessor for cross-addon frame lookups
_G._ECME_GetBarFrame = function(barKey)
    return cdmBarFrames[barKey]
end
-- Global accessors for party/player frame discovery
_G._ECME_FindPlayerPartyFrame = function()
    return FindPlayerPartyFrame()
end
_G._ECME_FindPlayerUnitFrame = function()
    return FindPlayerUnitFrame()
end
ns.GetCDMBarIcons = function(barKey)
    return cdmBarIcons[barKey]
end

-------------------------------------------------------------------------------
--  Proc Glow System: hooks Blizzard's SpellAlertManager to show proc glows
--  on our CDM icons when Blizzard fires ShowAlert/HideAlert on CDM children.
--  Custom bars use SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events instead.
-------------------------------------------------------------------------------
local PROC_GLOW_STYLE = 6  -- "Modern WoW Glow" flipbook

-- Reverse lookup: Blizzard CDM viewer frame name ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó our bar key
local _blizzViewerToBarKey = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer   = "utility",
    BuffIconCooldownViewer  = "buffs",
}

-- Walk up from a frame to find which Blizzard CDM viewer it belongs to
local function GetBarKeyForBlizzChild(frame)
    local current = frame
    while current do
        local parent = current:GetParent()
        if not parent then return nil end
        local name = parent.GetName and parent:GetName()
        if name and _blizzViewerToBarKey[name] then
            return _blizzViewerToBarKey[name], current
        end
        current = parent
    end
    return nil
end

-- Find our icon that mirrors a given Blizzard CDM child
local function FindOurIconForBlizzChild(barKey, blizzChild)
    local icons = cdmBarIcons[barKey]
    if not icons then return nil end
    for _, icon in ipairs(icons) do
        if icon._blizzChild == blizzChild then return icon end
    end
    return nil
end

-- Resolve spellID from a Blizzard CDM child (for IsSpellOverlayed guard)
local function ResolveBlizzChildSpellID(blizzChild)
    local cdID = blizzChild.cooldownID
    if not cdID and blizzChild.cooldownInfo then
        cdID = blizzChild.cooldownInfo.cooldownID
    end
    if cdID then
        local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        if info then return info.overrideSpellID or info.spellID end
    end
    return nil
end

-- Show proc glow on one of our icons (separate from active state glow)
local function ShowProcGlow(icon, cr, cg, cb)
    if not icon or not icon._glowOverlay then return end
    -- Don't double-start if already showing proc glow
    if icon._procGlowActive then return end
    -- If active state glow is running, stop it first (proc glow takes priority)
    if icon._isActive and icon._glowOverlay._glowActive then
        StopNativeGlow(icon._glowOverlay)
    end
    StartNativeGlow(icon._glowOverlay, PROC_GLOW_STYLE, cr, cg, cb)
    icon._procGlowActive = true
end

-- Stop proc glow on one of our icons (restores active state glow if needed)
local function StopProcGlow(icon)
    if not icon or not icon._procGlowActive then return end
    StopNativeGlow(icon._glowOverlay)
    icon._procGlowActive = false
    -- Restore active state glow if the icon is still in active state
    if icon._isActive and icon._glowOverlay then
        local barData = barDataByKey[icon._barKey]
        if barData then
            local activeAnim = barData.activeStateAnim or "blizzard"
            local glowIdx = tonumber(activeAnim)
            if glowIdx then
                local animR, animG, animB = 1.0, 0.85, 0.0
                if barData.activeAnimClassColor then
                    local _, ct = UnitClass("player")
                    if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then animR, animG, animB = cc.r, cc.g, cc.b end end
                elseif barData.activeAnimR then
                    animR = barData.activeAnimR; animG = barData.activeAnimG or 0.85; animB = barData.activeAnimB or 0.0
                end
                StartNativeGlow(icon._glowOverlay, glowIdx, animR, animG, animB)
            end
        end
    end
end

-- Proc glow color: hardcoded gold (#ffc923)
local PROC_GLOW_R, PROC_GLOW_G, PROC_GLOW_B = 1.0, 0.788, 0.137

-- Install hooks on ActionButtonSpellAlertManager (called once during init)
local _procGlowHooksInstalled = false
local function InstallProcGlowHooks()
    if _procGlowHooksInstalled then return end
    if not ActionButtonSpellAlertManager then return end

    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, frame)
        if not frame then return end
        local barKey, cdmChild = GetBarKeyForBlizzChild(frame)
        if not barKey or not cdmChild then return end

        -- Hide Blizzard's built-in SpellActivationAlert on the CDM child
        if cdmChild.SpellActivationAlert then
            cdmChild.SpellActivationAlert:SetAlpha(0)
            cdmChild.SpellActivationAlert:Hide()
        end

        -- Defer by one frame so the icon mapping from UpdateCDMBarIcons is current
        C_Timer.After(0, function()
            local ourIcon = FindOurIconForBlizzChild(barKey, cdmChild)
            if not ourIcon then return end
            -- Re-suppress Blizzard alert (may have been re-shown)
            if cdmChild.SpellActivationAlert then
                cdmChild.SpellActivationAlert:SetAlpha(0)
                cdmChild.SpellActivationAlert:Hide()
            end
            local cr, cg, cb = PROC_GLOW_R, PROC_GLOW_G, PROC_GLOW_B
            ShowProcGlow(ourIcon, cr, cg, cb)
        end)
    end)

    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, frame)
        if not frame then return end
        local barKey, cdmChild = GetBarKeyForBlizzChild(frame)
        if not barKey or not cdmChild then return end
        local ourIcon = FindOurIconForBlizzChild(barKey, cdmChild)
        if not ourIcon or not ourIcon._procGlowActive then return end

        -- Guard: CDM may fire HideAlert during internal refresh cycles even though
        -- the spell is still procced. Check IsSpellOverlayed before killing the glow.
        local spellID = ResolveBlizzChildSpellID(cdmChild)
        if spellID and C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
            local ok, overlayed = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
            if ok and overlayed then
                -- Spell still active ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ suppress Blizzard's alert again and keep our glow
                if cdmChild.SpellActivationAlert then
                    cdmChild.SpellActivationAlert:SetAlpha(0)
                    cdmChild.SpellActivationAlert:Hide()
                end
                return
            end
        end

        StopProcGlow(ourIcon)
    end)

    _procGlowHooksInstalled = true
end

-- Handle proc glow for custom bars via spell activation overlay events.
-- Called from the event handler when SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE fires.
local function OnProcGlowEvent(event, spellID)
    if not spellID then return end
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return end

    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled and barData.isCustom and barData.customSpells then
            local icons = cdmBarIcons[barData.key]
            if icons then
                for i, sid in ipairs(barData.customSpells) do
                    if sid == spellID and icons[i] then
                        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                            ShowProcGlow(icons[i], PROC_GLOW_R, PROC_GLOW_G, PROC_GLOW_B)
                        else
                            StopProcGlow(icons[i])
                        end
                    end
                end
            end
        end
    end
end
ns.OnProcGlowEvent = OnProcGlowEvent


-------------------------------------------------------------------------------
--  CDM Bars: Our replacement for Blizzard's Cooldown Manager
--  Captures Blizzard positions on first login, then creates our own bars.
-------------------------------------------------------------------------------
local CDM_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetCDMFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("cdm")
    end
    return CDM_FONT_FALLBACK
end
local function GetCDMOutline()
    if EllesmereUI and EllesmereUI.GetFontOutlineFlag then
        return EllesmereUI.GetFontOutlineFlag()
    end
    return "OUTLINE"
end
local function GetCDMUseShadow()
    if EllesmereUI and EllesmereUI.GetFontUseShadow then
        return EllesmereUI.GetFontUseShadow()
    end
    return false
end
local function SetBlizzCDMFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    local f = GetCDMOutline()
    fs:SetFont(font, size, f)
    if f == "" then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
    else fs:SetShadowOffset(0, 0) end
end

-- Blizzard CDM frame names
local BLIZZ_CDM_FRAMES = {
    cooldowns = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buffs     = "BuffIconCooldownViewer",
}

-- CDM category numbers per bar key (for C_CooldownViewer API)
local CDM_BAR_CATEGORIES = {
    cooldowns = { 0, 1 },    -- Essential + Utility
    utility   = { 0, 1 },    -- Essential + Utility
    buffs     = { 2, 3 },    -- Tracked Buff + Tracked Debuff
}

-- Maximum number of custom bars a user can create
local MAX_CUSTOM_BARS = 6

-------------------------------------------------------------------------------
--  Party Frame Discovery
--  Scans known party/raid frame addons to find the player's own unit button.
-------------------------------------------------------------------------------
local PARTY_FRAME_PREFIXES = {
    { addon = "ElvUI",  prefix = "ElvUF_PartyGroup1UnitButton", count = 5 },
    { addon = "Cell",   prefix = "CellPartyFrameMember",        count = 5 },
    { addon = nil,      prefix = "CompactPartyFrameMember",     count = 5 },
    { addon = nil,      prefix = "CompactRaidFrame",            count = 40 },
}

local _cachedPartyFrame
local _cachedPartyFrameRoster = 0  -- invalidate on roster change

local function FindPlayerPartyFrame()
    -- Use cache if roster hasn't changed
    local rosterToken = GetNumGroupMembers()
    if _cachedPartyFrame and _cachedPartyFrameRoster == rosterToken then
        if _cachedPartyFrame:IsVisible() then
            return _cachedPartyFrame
        end
    end
    _cachedPartyFrame = nil
    _cachedPartyFrameRoster = rosterToken

    for _, src in ipairs(PARTY_FRAME_PREFIXES) do
        if not src.addon or C_AddOns.IsAddOnLoaded(src.addon) then
            for i = 1, src.count do
                local frame = _G[src.prefix .. i]
                if frame and frame.GetAttribute and frame:GetAttribute("unit") == "player"
                   and frame.IsVisible and frame:IsVisible() then
                    _cachedPartyFrame = frame
                    return frame
                end
            end
        end
    end
    -- Check Dander's party container
    if C_AddOns.IsAddOnLoaded("DandersFrames") then
        local container = _G["DandersPartyContainer"]
        if container and container.IsVisible and container:IsVisible() then
            _cachedPartyFrame = container
            return container
        end
    end

    return nil
end

-------------------------------------------------------------------------------
--  Player Frame Discovery
--  Scans known unit frame addons to find the player's unit frame.
--  Priority: ours ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó ElvUI ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó Dander's party header ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó Blizzard PlayerFrame
-------------------------------------------------------------------------------
local PLAYER_FRAME_SOURCES = {
    { addon = "EllesmereUIUnitFrames", global = "EllesmereUIUnitFrames_Player" },
    { addon = "ElvUI",                 global = "ElvUF_Player" },
}

local _cachedPlayerFrame
local _cachedPlayerFrameRoster = 0

local function FindPlayerUnitFrame()
    -- Invalidate cache when group roster changes (spec swap, join/leave)
    local rosterToken = GetNumGroupMembers()
    if _cachedPlayerFrame and _cachedPlayerFrameRoster == rosterToken then
        -- Also re-verify the unit attribute ΓÇö party header children get
        -- reassigned dynamically by the secure group system.
        if _cachedPlayerFrame:IsVisible() then
            local u = _cachedPlayerFrame.GetAttribute and _cachedPlayerFrame:GetAttribute("unit")
            if not u or UnitIsUnit(u, "player") then
                return _cachedPlayerFrame
            end
        end
    end
    _cachedPlayerFrame = nil
    _cachedPlayerFrameRoster = rosterToken

    -- Check dedicated player frame addons first
    for _, src in ipairs(PLAYER_FRAME_SOURCES) do
        if C_AddOns.IsAddOnLoaded(src.addon) then
            local frame = _G[src.global]
            if frame and frame.IsVisible and frame:IsVisible() then
                _cachedPlayerFrame = frame
                return frame
            end
        end
    end

    -- Check Dander's party header children for the player unit
    if C_AddOns.IsAddOnLoaded("DandersFrames") then
        local header = _G["DandersPartyHeader"]
        if header then
            for i = 1, 5 do
                local child = header:GetAttribute("child" .. i)
                if child and child.GetAttribute and child:GetAttribute("unit") == "player"
                   and child.IsVisible and child:IsVisible() then
                    _cachedPlayerFrame = child
                    return child
                end
            end
        end
    end

    -- Fallback: Blizzard default player frame
    local blizz = _G["PlayerFrame"]
    if blizz and blizz.IsVisible and blizz:IsVisible() then
        _cachedPlayerFrame = blizz
        return blizz
    end

    return nil
end

-------------------------------------------------------------------------------
--  Trinket / Racial / Health Potion data (for "trinkets" bar type)
--  Encoding in customSpells:  positive = spellID,  -13/-14 = trinket slot
-------------------------------------------------------------------------------
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14

-- Racial abilities by internal race name ├â╞Æ├é┬ó├â┬ó├óΓÇÜ┬¼├é┬á├â┬ó├óΓÇÜ┬¼├óΓÇ₧┬ó list of spellIDs
-- Entries with a table { spellID, class="CLASS" } are class-restricted.
local RACE_RACIALS = {
    Scourge            = { 7744 },
    Tauren             = { 20549 },
    Orc                = { 20572, 33697, 33702 },
    BloodElf           = { 202719, 50613, 25046, 69179, 80483, 155145, 129597, 232633, 28730 },
    Dwarf              = { 20594 },
    Troll              = { 26297 },
    Draenei            = { 28880 },
    NightElf           = { 58984 },
    Human              = { 59752 },
    DarkIronDwarf      = { 265221 },
    Gnome              = { 20589 },
    HighmountainTauren = { 69041 },
    Worgen             = { 68992 },
    Goblin             = { 69070 },
    Pandaren           = { 107079 },
    MagharOrc          = { 274738 },
    LightforgedDraenei = { 255647 },
    VoidElf            = { 256948 },
    KulTiran           = { 287712 },
    ZandalariTroll     = { 291944 },
    Vulpera            = { 312411 },
    Mechagnome         = { 312924 },
    Dracthyr           = { 357214, { 368970, class = "EVOKER" } },
    EarthenDwarf       = { 436344 },
    Haranir            = { 1287685 },
}

-- Health potions / healthstones: { itemID, spellID [, class] }
local HEALTH_ITEMS = {
    { itemID = 241304, spellID = 1234768 },                      -- Silvermoon Health Potion
    { itemID = 241308, spellID = 1236616 },                      -- Light's Potential
    { itemID = 5512,   spellID = 6262 },                         -- Healthstone
    { itemID = 224464, spellID = 452930, class = "WARLOCK" },    -- Demonic Healthstone
}

-- Cached player info (set once at PLAYER_LOGIN)
local _playerRace, _playerClass

-- Forward declarations
local BuildCDMBar, LayoutCDMBar, UpdateCDMBarIcons, HideBlizzardCDM, RestoreBlizzardCDM
local CaptureCDMPositions, ApplyCDMBarPosition, ApplyShapeToCDMIcon

-------------------------------------------------------------------------------
--  Capture Blizzard CDM positions (first login only)
-------------------------------------------------------------------------------
CaptureCDMPositions = function()
    local captured = {}
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()

    for barKey, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local frame = _G[frameName]
        if frame then
            local data = {}

            -- Bar scale from the frame's drag-handle scale
            local frameScale = frame:GetScale()
            if frameScale and frameScale > 0.1 then
                data.barScale = frameScale
            end

            -- Icon size + spacing: read from child icons.
            -- Blizzard CDM icons have a base size and a per-icon scale driven
            -- by the IconSize percentage slider. Spacing is measured from the
            -- gap between two adjacent visible icons in parent coordinates.
            local childCount = frame:GetNumChildren()
            local numDistinctY = {}
            local shownIcons = {}
            for ci = 1, childCount do
                local child = select(ci, frame:GetChildren())
                if child and child.Icon then
                    local cw = child:GetWidth()
                    local cs = child:GetScale()
                    if cw and cw > 1 and not data.iconSize then
                        local visual = cw * (cs or 1)
                        data.iconSize = math.floor(visual + 0.5)
                    end
                    -- Collect shown icons for spacing measurement
                    if child:IsShown() then
                        shownIcons[#shownIcons + 1] = child
                        -- Track distinct Y positions for row counting
                        if child:GetPoint(1) then
                            local _, _, _, _, cy = child:GetPoint(1)
                            if cy then
                                numDistinctY[math.floor(cy + 0.5)] = true
                            end
                        end
                    end
                end
            end

            -- Spacing: measure gap between adjacent visible icons
            if #shownIcons >= 2 and data.iconSize then
                -- Sort by left edge so we measure truly adjacent icons
                table.sort(shownIcons, function(a, b)
                    return (a:GetLeft() or 0) < (b:GetLeft() or 0)
                end)
                -- Find the smallest step between any two consecutive sorted icons
                -- GetLeft() returns UIParent-coordinate-space values
                local bestStep = nil
                for si = 1, #shownIcons - 1 do
                    local aLeft = shownIcons[si]:GetLeft()
                    local bLeft = shownIcons[si + 1]:GetLeft()
                    if aLeft and bLeft then
                        local dist = bLeft - aLeft
                        if dist > 0 and (not bestStep or dist < bestStep) then
                            bestStep = dist
                        end
                    end
                end
                if bestStep then
                    -- bestStep is in UIParent coords; iconSize = cw * cs (visual size in parent-of-icon coords)
                    -- Convert bestStep from UIParent coords to icon-parent coords
                    -- icon-parent coord ? UIParent coord multiplier = frame.effectiveScale / UIParent.effectiveScale
                    -- So to go back: divide by that
                    local frameEff = frame:GetEffectiveScale()
                    local uiEff = UIParent:GetEffectiveScale()
                    local parentStep = bestStep * uiEff / frameEff
                    -- Now parentStep is in frame coords; but iconSize = cw * cs, and positions in frame use cw units
                    -- So step in iconSize units = parentStep * cs
                    local cs = shownIcons[1]:GetScale() or 1
                    local stepInIconUnits = parentStep * cs
                    local gap = stepInIconUnits - data.iconSize
                    if gap < 0 then gap = 0 end
                    data.spacing = math.floor(gap + 0.5)
                end
            end

            -- Rows: count distinct Y positions among visible icon children
            local rowCount = 0
            for _ in pairs(numDistinctY) do rowCount = rowCount + 1 end
            if rowCount >= 1 then
                data.numRows = rowCount
            end

            -- Orientation from frame property
            if frame.isHorizontal ~= nil then
                data.isHorizontal = frame.isHorizontal
            end

            -- Position (center-based, in UIParent coordinates)
            if frame:GetPoint(1) then
                local cx, cy = frame:GetCenter()
                if cx and cy then
                    local bScale = frame:GetEffectiveScale()
                    cx = cx * bScale / uiScale
                    cy = cy * bScale / uiScale
                    data.point = "CENTER"
                    data.relPoint = "CENTER"
                    data.x = cx - (uiW / 2)
                    data.y = cy - (uiH / 2)
                end
            end

            captured[barKey] = data
        end
    end

    return captured
end

-------------------------------------------------------------------------------
--  Hide / Restore Blizzard CDM
-------------------------------------------------------------------------------
HideBlizzardCDM = function()
    for _, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local frame = _G[frameName]
        if frame then
            -- Always re-apply hide in case a cinematic or loading screen
            -- restored the frame's position/alpha without clearing our flag.
            if not frame._ecmeHidden then
                frame._ecmeOrigAlpha = frame:GetAlpha()
                frame._ecmeOrigPoints = {}
                for i = 1, frame:GetNumPoints() do
                    frame._ecmeOrigPoints[i] = { frame:GetPoint(i) }
                end
                frame._ecmeHidden = true

                -- Hook SetPoint and SetAlpha so any Blizzard attempt to
                -- reposition or reveal the frame is immediately suppressed.
                -- The hook fires after the original call, so we re-apply our
                -- off-screen position and zero alpha on top of whatever Blizzard set.
                hooksecurefunc(frame, "SetPoint", function(self)
                    if self._ecmeHidden and not self._ecmeRestoring and not self._ecmeSuppressing then
                        self._ecmeSuppressing = true
                        self:ClearAllPoints()
                        self:SetPoint("CENTER", UIParent, "CENTER", 0, 10000)
                        self._ecmeSuppressing = nil
                    end
                end)
                hooksecurefunc(frame, "SetAlpha", function(self, alpha)
                    if self._ecmeHidden and not self._ecmeRestoring and not self._ecmeSuppressing and (alpha or 0) > 0 then
                        self._ecmeSuppressing = true
                        self:SetAlpha(0)
                        self._ecmeSuppressing = nil
                    end
                end)
            end
            frame:SetAlpha(0)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10000)
        end
    end
end

RestoreBlizzardCDM = function()
    for _, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local frame = _G[frameName]
        if frame and frame._ecmeHidden then
            frame._ecmeRestoring = true
            frame:SetAlpha(frame._ecmeOrigAlpha or 1)
            if frame._ecmeOrigPoints then
                frame:ClearAllPoints()
                for _, pt in ipairs(frame._ecmeOrigPoints) do
                    frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
            frame._ecmeHidden = false
            frame._ecmeRestoring = nil
        end
    end
end

-------------------------------------------------------------------------------
--  CDM Bar Position Helpers
-------------------------------------------------------------------------------
local function ApplyBarPositionCentered(frame, pos, w, h, scale)
    if not pos or not pos.point then return end
    frame:ClearAllPoints()
    -- Convert legacy TOPLEFT positions to CENTER so the bar stays centered
    -- when icon count changes across specs.
    if pos.point == "TOPLEFT" and pos.relPoint == "TOPLEFT" then
        local fw, fh = frame:GetWidth() or 0, frame:GetHeight() or 0
        local uiW, uiH = UIParent:GetSize()
        local cx = (pos.x or 0) + fw * 0.5 - uiW * 0.5
        local cy = (pos.y or 0) - fh * 0.5 + uiH * 0.5
        frame:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
        -- Migrate the saved position to CENTER for future loads
        pos.point = "CENTER"
        pos.relPoint = "CENTER"
        pos.x = cx
        pos.y = cy
    else
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    end
end

local function SaveCDMBarPosition(barKey, frame)
    if not frame then return end
    local p = ECME.db.profile
    local scale = frame:GetScale() or 1
    local cx, cy = frame:GetCenter()
    if not cx then return end
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()
    local fScale = frame:GetEffectiveScale()
    cx = cx * fScale / uiScale
    cy = cy * fScale / uiScale
    p.cdmBarPositions[barKey] = {
        point = "CENTER", relPoint = "CENTER",
        x = (cx - uiW / 2) / scale,
        y = (cy - uiH / 2) / scale,
    }
end

-------------------------------------------------------------------------------
--  Helper: get the frame anchor point for a CDM bar.
--  Returns the near-edge center of the frame (the edge that faces away from target).
--  grow RIGHT -> near edge = LEFT, grow LEFT -> RIGHT, grow DOWN -> TOP, grow UP -> BOTTOM
-------------------------------------------------------------------------------
local function CDMFrameAnchorPoint(anchorSide, grow, centered)
    if grow == "RIGHT" then return "LEFT"   end
    if grow == "LEFT"  then return "RIGHT"  end
    if grow == "DOWN"  then return "TOP"    end
    if grow == "UP"    then return "BOTTOM" end
    return "LEFT"
end

-------------------------------------------------------------------------------
--  Recursive click-through helper ΓÇö disables/restores mouse on a frame tree
-------------------------------------------------------------------------------
local function SetFrameClickThrough(frame, clickThrough)
    if not frame then return end
    if clickThrough then
        if frame._cdmMouseWas == nil then
            frame._cdmMouseWas = frame:IsMouseEnabled()
        end
        frame:EnableMouse(false)
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    else
        if frame._cdmMouseWas ~= nil then
            frame:EnableMouse(frame._cdmMouseWas)
            frame._cdmMouseWas = nil
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        SetFrameClickThrough(child, clickThrough)
    end
end

-------------------------------------------------------------------------------
--  Build a single CDM bar frame
-------------------------------------------------------------------------------
BuildCDMBar = function(barIndex)
    local p = ECME.db.profile
    local bars = p.cdmBars.bars
    local barData = bars[barIndex]
    if not barData then return end

    local key = barData.key
    local frame = cdmBarFrames[key]

    if not frame then
        frame = CreateFrame("Frame", "ECME_CDMBar_" .. key, UIParent)
        frame:SetFrameStrata("LOW")
        frame:SetFrameLevel(5)
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
        frame._barKey = key
        frame._barIndex = barIndex
        cdmBarFrames[key] = frame
        cdmBarIcons[key] = {}
    end

    if not barData.enabled then
        if frame._mouseTrack then
            frame:SetScript("OnUpdate", nil)
            frame._mouseTrack = nil
            if frame._preMousePos and not p.cdmBarPositions[key] then
                p.cdmBarPositions[key] = frame._preMousePos
            end
            frame._preMousePos = nil
            SetFrameClickThrough(frame, false)
            if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
        end
        frame:Hide()
        return
    end

    -- Apply scale
    local scale = barData.barScale or 1.0
    if scale < 0.1 then scale = 1.0 end
    frame:SetScale(scale)

    -- Clear any previous mouse-tracking OnUpdate
    if frame._mouseTrack then
        frame:SetScript("OnUpdate", nil)
        frame._mouseTrack = nil
        -- Restore saved position from before mouse anchor
        if frame._preMousePos and not p.cdmBarPositions[key] then
            p.cdmBarPositions[key] = frame._preMousePos
        end
        frame._preMousePos = nil
        -- Restore default strata when leaving cursor anchor
        frame:SetFrameStrata("LOW")
        frame:SetFrameLevel(5)
        -- Restore mouse on frame and all children
        SetFrameClickThrough(frame, false)
        if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
    end
    frame._mouseGrow = nil

    -- Position
    local anchorKey = barData.anchorTo
    if anchorKey == "mouse" then
        -- Stash saved position so it can be restored when unanchoring
        if p.cdmBarPositions[key] then
            frame._preMousePos = p.cdmBarPositions[key]
        end
        -- Anchor position acts as build direction for mouse cursor tracking
        local anchorPos = barData.anchorPosition or "right"
        local oX = barData.anchorOffsetX or 0
        local oY = barData.anchorOffsetY or 0
        -- Determine SetPoint anchor and 15px directional nudge
        local pointFrom, baseOX, baseOY, forceGrow
        if anchorPos == "left" then
            pointFrom = "RIGHT"; forceGrow = "LEFT"
            baseOX = -15 + oX; baseOY = oY
        elseif anchorPos == "right" then
            pointFrom = "LEFT"; forceGrow = "RIGHT"
            baseOX = 15 + oX; baseOY = oY
        elseif anchorPos == "top" then
            pointFrom = "BOTTOM"; forceGrow = "UP"
            baseOX = oX; baseOY = 15 + oY
        elseif anchorPos == "bottom" then
            pointFrom = "TOP"; forceGrow = "DOWN"
            baseOX = oX; baseOY = -15 + oY
        else
            pointFrom = "LEFT"; forceGrow = "RIGHT"
            baseOX = 15 + oX; baseOY = oY
        end
        frame._mouseGrow = forceGrow
        -- Elevate to TOOLTIP strata so the bar renders above all UI
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9980)
        -- Make frame and all children fully click-through while following cursor
        SetFrameClickThrough(frame, true)
        local lastMX, lastMY
        frame:ClearAllPoints()
        frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        frame._mouseTrack = true
        frame:SetScript("OnUpdate", function()
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx = floor(cx / s + 0.5)
            cy = floor(cy / s + 0.5)
            if cx ~= lastMX or cy ~= lastMY then
                lastMX, lastMY = cx, cy
                frame:ClearAllPoints()
                frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", cx + baseOX, cy + baseOY)
            end
        end)
    elseif anchorKey == "partyframe" then
        -- Anchor to the player's party frame
        local partyFrame = FindPlayerPartyFrame()
        if partyFrame then
            frame:ClearAllPoints()
            local side = barData.partyFrameSide or "LEFT"
            local oX = barData.partyFrameOffsetX or 0
            local oY = barData.partyFrameOffsetY or 0
            local grow = barData.growDirection or "RIGHT"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(side, grow, centered)
            frame._anchorSide = side:upper()
            if side == "LEFT" then
                frame:SetPoint(fp, partyFrame, "LEFT", oX, oY)
            elseif side == "RIGHT" then
                frame:SetPoint(fp, partyFrame, "RIGHT", oX, oY)
            elseif side == "TOP" then
                frame:SetPoint(fp, partyFrame, "TOP", oX, oY)
            elseif side == "BOTTOM" then
                frame:SetPoint(fp, partyFrame, "BOTTOM", oX, oY)
            end
        else
            -- No party frame found ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, 1, 1, scale)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "playerframe" then
        -- Anchor to the player's unit frame
        local playerFrame = FindPlayerUnitFrame()
        if playerFrame then
            frame:ClearAllPoints()
            local side = barData.playerFrameSide or "LEFT"
            local oX = barData.playerFrameOffsetX or 0
            local oY = barData.playerFrameOffsetY or 0
            local grow = barData.growDirection or "RIGHT"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(side, grow, centered)
            frame._anchorSide = side:upper()
            if side == "LEFT" then
                frame:SetPoint(fp, playerFrame, "LEFT", oX, oY)
            elseif side == "RIGHT" then
                frame:SetPoint(fp, playerFrame, "RIGHT", oX, oY)
            elseif side == "TOP" then
                frame:SetPoint(fp, playerFrame, "TOP", oX, oY)
            elseif side == "BOTTOM" then
                frame:SetPoint(fp, playerFrame, "BOTTOM", oX, oY)
            end
        else
            -- No player frame found ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, 1, 1, scale)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "erb_castbar" or anchorKey == "erb_powerbar" or anchorKey == "erb_classresource" then
        -- Anchor to EllesmereUI Resource Bars frames
        local erbFrameNames = {
            erb_castbar = "ERB_CastBarFrame",
            erb_powerbar = "ERB_PrimaryBar",
            erb_classresource = "ERB_SecondaryFrame",
        }
        local erbFrame = _G[erbFrameNames[anchorKey]]
        if erbFrame then
            local anchorPos = barData.anchorPosition or "left"
            frame:ClearAllPoints()
            local gap = barData.spacing or 2
            local oX = barData.anchorOffsetX or 0
            local oY = barData.anchorOffsetY or 0
            local grow = barData.growDirection or "RIGHT"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(anchorPos:upper(), grow, centered)
            frame._anchorSide = anchorPos:upper()
            local ok
            if anchorPos == "left" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "LEFT", -gap + oX, oY)
            elseif anchorPos == "right" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "RIGHT", gap + oX, oY)
            elseif anchorPos == "top" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "TOP", oX, gap + oY)
            elseif anchorPos == "bottom" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "BOTTOM", oX, -gap + oY)
            end
            -- Circular anchor detected ΓÇö fall back to center
            if not ok then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        else
            -- Resource Bars frame not available ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, 1, 1, scale)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey and anchorKey ~= "none" and cdmBarFrames[anchorKey] then
        local anchorFrame = cdmBarFrames[anchorKey]
        local anchorPos = barData.anchorPosition or "left"
        frame:ClearAllPoints()
        local gap = barData.spacing or 2
        local oX = barData.anchorOffsetX or 0
        local oY = barData.anchorOffsetY or 0
        local grow = barData.growDirection or "RIGHT"
        local centered = barData.growCentered ~= false
        local fp = CDMFrameAnchorPoint(anchorPos:upper(), grow, centered)
        frame._anchorSide = anchorPos:upper()
        local ok
        if anchorPos == "left" then
            ok = pcall(frame.SetPoint, frame, fp, anchorFrame, "LEFT", -gap + oX, oY)
        elseif anchorPos == "right" then
            ok = pcall(frame.SetPoint, frame, fp, anchorFrame, "RIGHT", gap + oX, oY)
        elseif anchorPos == "top" then
            ok = pcall(frame.SetPoint, frame, fp, anchorFrame, "TOP", oX, gap + oY)
        elseif anchorPos == "bottom" then
            ok = pcall(frame.SetPoint, frame, fp, anchorFrame, "BOTTOM", oX, -gap + oY)
        end
        if not ok then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    else
        local pos = p.cdmBarPositions[key]
        if pos and pos.point then
            ApplyBarPositionCentered(frame, pos, 1, 1, scale)
        else
            -- Default fallback positions
            frame:ClearAllPoints()
            if key == "cooldowns" then
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, -275)
            elseif key == "utility" then
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
            elseif key == "buffs" then
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, -365)
            else
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    end

    frame:Show()
end

-------------------------------------------------------------------------------
--  Layout icons within a CDM bar
-------------------------------------------------------------------------------
LayoutCDMBar = function(barKey)
    local frame = cdmBarFrames[barKey]
    local icons = cdmBarIcons[barKey]
    if not frame or not icons then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end

    local barScale = barData.barScale or 1.0
    if barScale < 0.1 then barScale = 1.0 end
    local iconW = SnapForScale(barData.iconSize or 36, barScale)
    local iconH = iconW
    local shape = barData.iconShape or "none"
    if shape == "cropped" then
        iconH = SnapForScale(math.floor((barData.iconSize or 36) * 0.80 + 0.5), barScale)
    end
    local spacing = SnapForScale(barData.spacing or 2, barScale)
    local grow = frame._mouseGrow or barData.growDirection or "RIGHT"
    local numRows = barData.numRows or 1
    if numRows < 1 then numRows = 1 end

    -- Collect visible icons (reuse buffer to avoid garbage)
    local visibleIcons = frame._visibleIconsBuf
    if not visibleIcons then visibleIcons = {}; frame._visibleIconsBuf = visibleIcons else wipe(visibleIcons) end
    for _, icon in ipairs(icons) do
        if icon:IsShown() then
            visibleIcons[#visibleIcons + 1] = icon
        end
    end

    local count = #visibleIcons
    if count == 0 then
        frame:SetSize(1, 1)
        if frame._barBg then frame._barBg:Hide() end
        return
    end

    local isHoriz = (grow == "RIGHT" or grow == "LEFT")
    local stride = math.ceil(count / numRows)

    -- Container size (already snapped values)
    local totalW, totalH
    if isHoriz then
        totalW = stride * iconW + (stride - 1) * spacing
        totalH = numRows * iconH + (numRows - 1) * spacing
    else
        totalW = numRows * iconW + (numRows - 1) * spacing
        totalH = stride * iconH + (stride - 1) * spacing
    end
    frame:SetSize(totalW, totalH)

    -- Bar opacity (affects entire bar, but respect visibility overrides)
    local vis = barData.barVisibility or "always"
    if vis == "always" or (vis == "in_combat" and _inCombat) then
        frame:SetAlpha(barData.barBgAlpha or 1)
    elseif vis == "mouseover" then
        local state = _cdmHoverStates[barKey]
        if state and state.isHovered then
            frame:SetAlpha(barData.barBgAlpha or 1)
        end
    end

    -- Bar background
    if barData.barBgEnabled then
        if not frame._barBg then
            frame._barBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        end
        frame._barBg:ClearAllPoints()
        frame._barBg:SetPoint("TOPLEFT", 0, 0)
        frame._barBg:SetPoint("BOTTOMRIGHT", 0, 0)
        frame._barBg:SetColorTexture(barData.barBgR or 0, barData.barBgG or 0, barData.barBgB or 0, 0.5)
        PP.DisablePixelSnap(frame._barBg)
        frame._barBg:Show()
    elseif frame._barBg then
        frame._barBg:Hide()
    end

    local stepW = iconW + spacing
    local stepH = iconH + spacing

    -- Position each icon in a grid anchored to the frame's corners.
    -- Frame bounding box == icon grid, so frame CENTER == icon grid center.
    -- Partial rows (fewer icons than stride) are centered within the frame width.
    for i, icon in ipairs(visibleIcons) do
        PP.Size(icon, iconW, iconH)
        if icon._glowOverlay then
            icon._glowOverlay:SetSize(iconW + 6, iconH + 6)
        end
        icon:ClearAllPoints()

        local idx = i - 1
        local col = idx % stride
        local row = math.floor(idx / stride)

        -- Count how many icons are in this row to detect partial rows
        local rowStart = row * stride
        local iconsInRow = math.min(stride, count - rowStart)

        if grow == "RIGHT" then
            local flippedRow = (numRows - 1) - row
            -- Center partial rows: offset by half the missing icons' width
            local rowOffset = math.floor((stride - iconsInRow) * stepW / 2)
            PP.Point(icon, "TOPLEFT", frame, "TOPLEFT",
                col * stepW + rowOffset,
                -(flippedRow * stepH))
        elseif grow == "LEFT" then
            local flippedRow = (numRows - 1) - row
            local rowOffset = math.floor((stride - iconsInRow) * stepW / 2)
            PP.Point(icon, "TOPRIGHT", frame, "TOPRIGHT",
                -(col * stepW + rowOffset),
                -(flippedRow * stepH))
        elseif grow == "DOWN" then
            local flippedRow = (numRows - 1) - row
            local rowOffset = math.floor((stride - iconsInRow) * stepH / 2)
            PP.Point(icon, "TOPLEFT", frame, "TOPLEFT",
                flippedRow * stepW,
                -(col * stepH + rowOffset))
        elseif grow == "UP" then
            local rowOffset = math.floor((stride - iconsInRow) * stepH / 2)
            PP.Point(icon, "BOTTOMLEFT", frame, "BOTTOMLEFT",
                row * stepW,
                col * stepH + rowOffset)
        end
    end
end

-------------------------------------------------------------------------------
--  Create a single icon frame for a CDM bar
-------------------------------------------------------------------------------
local function CreateCDMIcon(barKey, index)
    local frame = cdmBarFrames[barKey]
    if not frame then return end

    local barData = barDataByKey[barKey]
    if not barData then return end

    local barScale = barData.barScale or 1.0
    if barScale < 0.1 then barScale = 1.0 end
    local iconSize = barData.iconSize or 36
    local borderSize = SnapForScale(barData.borderSize or 1, barScale)
    local zoom = barData.iconZoom or 0.08

    local icon = CreateFrame("Frame", "ECME_CDMIcon_" .. barKey .. "_" .. index, frame)
    icon:SetSize(SnapForScale(iconSize, barScale), SnapForScale(iconSize, barScale))
    icon:EnableMouse(false)  -- click-through by default
    if icon.EnableMouseMotion then icon:EnableMouseMotion(false) end

    -- Background
    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08, barData.bgB or 0.08, barData.bgA or 0.6)
    PP.DisablePixelSnap(bg)
    icon._bg = bg

    -- Icon texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
    tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
    tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    PP.DisablePixelSnap(tex)
    icon._tex = tex

    -- Cooldown overlay (frame level above icon so swipe renders on top of texture)
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetFrameLevel(icon:GetFrameLevel() + 1)
    cd:EnableMouse(false)
    cd:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
    cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetDrawBling(false)
    cd:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    cd:SetHideCountdownNumbers(not barData.showCooldownText)
    cd:SetReverse(false)
    icon._cooldown = cd

    -- Cooldown text styling
    -- Defer cooldown text font styling (avoids closure per icon ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ uses icon._pendingFont)
    if barData.showCooldownText then
        icon._pendingFontPath = GetCDMFont(); icon._pendingFontSize = barData.cooldownFontSize or 12
    end

    -- Text overlay frame: sits above the cooldown swipe so charge/stack text
    -- is always visible on top of the swipe animation
    local textOverlay = CreateFrame("Frame", nil, icon)
    textOverlay:SetAllPoints(icon)
    textOverlay:SetFrameLevel(icon:GetFrameLevel() + 2)
    textOverlay:EnableMouse(false)
    icon._textOverlay = textOverlay

    -- Charge count text
    local chargeText = textOverlay:CreateFontString(nil, "OVERLAY")
    chargeText:SetFont(GetCDMFont(), barData.stackCountSize or 11, "OUTLINE")
    chargeText:SetShadowOffset(0, 0)
    chargeText:SetPoint("BOTTOMRIGHT", textOverlay, "BOTTOMRIGHT", barData.stackCountX or 0, (barData.stackCountY or 0) + 2)
    chargeText:SetJustifyH("RIGHT")
    chargeText:SetTextColor(barData.stackCountR or 1, barData.stackCountG or 1, barData.stackCountB or 1)
    chargeText:Hide()
    icon._chargeText = chargeText

    -- Stack count text
    local stackText = textOverlay:CreateFontString(nil, "OVERLAY")
    stackText:SetFont(GetCDMFont(), barData.stackCountSize or 11, "OUTLINE")
    stackText:SetShadowOffset(0, 0)
    stackText:SetPoint("BOTTOMRIGHT", textOverlay, "BOTTOMRIGHT", barData.stackCountX or 0, (barData.stackCountY or 0) + 2)
    stackText:SetJustifyH("RIGHT")
    stackText:SetTextColor(barData.stackCountR or 1, barData.stackCountG or 1, barData.stackCountB or 1)
    stackText:Hide()
    icon._stackText = stackText

    -- Glow overlay (for active state animations ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ extends 3px beyond icon so pixel glow ants are visible outside border)
    local glowOverlay = CreateFrame("Frame", nil, icon)
    glowOverlay:ClearAllPoints()
    glowOverlay:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -3,  3)
    glowOverlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  3, -3)
    glowOverlay:SetFrameLevel(icon:GetFrameLevel() + 3)
    glowOverlay:SetAlpha(0)
    glowOverlay:EnableMouse(false)
    icon._glowOverlay = glowOverlay

    -- Keybind text overlay (top-left corner of icon)
    local keybindText = textOverlay:CreateFontString(nil, "OVERLAY")
    keybindText:SetFont(GetCDMFont(), barData.keybindSize or 10, "OUTLINE")
    keybindText:SetShadowOffset(0, 0)
    keybindText:SetPoint("TOPLEFT", textOverlay, "TOPLEFT", barData.keybindOffsetX or 2, barData.keybindOffsetY or -2)
    keybindText:SetJustifyH("LEFT")
    keybindText:SetTextColor(barData.keybindR or 1, barData.keybindG or 1, barData.keybindB or 1, barData.keybindA or 0.9)
    keybindText:Hide()
    icon._keybindText = keybindText

    -- Tooltip on hover ΓÇö uses OnUpdate cursor check so the icon stays click-through
    -- (EnableMouse stays false; we poll IsMouseOver each frame instead)
    local tooltipOverlay = CreateFrame("Frame", nil, icon)
    tooltipOverlay:SetAllPoints(icon)
    tooltipOverlay:SetFrameLevel(icon:GetFrameLevel() + 4)
    tooltipOverlay:EnableMouse(false)
    icon._tooltipShown = false
    icon:SetScript("OnUpdate", function(self)
        local bd = barDataByKey[self._barKey]
        if not bd or not bd.showTooltip then
            if self._tooltipShown then
                GameTooltip:Hide()
                self._tooltipShown = false
            end
            return
        end
        local over = self:IsMouseOver()
        if over and not self._tooltipShown then
            local sid = self._spellID
            if sid then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetSpellByID(sid)
                GameTooltip:Show()
                self._tooltipShown = true
            end
        elseif not over and self._tooltipShown then
            GameTooltip:Hide()
            self._tooltipShown = false
        end
    end)
    icon._tooltipOverlay = tooltipOverlay

    -- Border (4 edges)
    local edges = {}
    for i = 1, 4 do        local e = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        e:SetColorTexture(barData.borderR or 0, barData.borderG or 0, barData.borderB or 0, barData.borderA or 1)
        PP.DisablePixelSnap(e)
        edges[i] = e
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(borderSize)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(borderSize)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(borderSize)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(borderSize)
    icon._edges = edges

    -- State tracking
    icon._spellID = nil
    icon._isActive = false
    icon._barKey = barKey

    -- Apply saved icon shape on creation
    local shape = barData.iconShape or "none"
    if shape ~= "none" then
        ApplyShapeToCDMIcon(icon, shape, barData)
    end

    icon:Hide()
    return icon
end
-------------------------------------------------------------------------------
--  Apply custom shape to a CDM icon
-------------------------------------------------------------------------------
ApplyShapeToCDMIcon = function(icon, shape, barData)
    if not icon then return end
    local zoom = barData.iconZoom or 0.08
    local borderSz = barData.borderSize or 1
    local brdR = barData.borderR or 0
    local brdG = barData.borderG or 0
    local brdB = barData.borderB or 0
    local brdA = barData.borderA or 1
    if barData.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end
        end
    end

    if shape == "none" or shape == "cropped" or not shape then
        -- Remove shape mask if previously applied
        if icon._shapeMask then
            local mask = icon._shapeMask
            if icon._tex then pcall(icon._tex.RemoveMaskTexture, icon._tex, mask) end
            if icon._bg then pcall(icon._bg.RemoveMaskTexture, icon._bg, mask) end
            if icon._cooldown then pcall(icon._cooldown.RemoveMaskTexture, icon._cooldown, mask) end
            mask:SetTexture(nil); mask:ClearAllPoints(); mask:SetSize(0.001, 0.001); mask:Hide()
        end
        if icon._shapeBorder then icon._shapeBorder:Hide() end
        icon._shapeApplied = nil
        icon._shapeName = nil

        -- Restore square borders
        if icon._edges then
            for i = 1, 4 do icon._edges[i]:Show() end
            PP.Height(icon._edges[1], borderSz)
            PP.Height(icon._edges[2], borderSz)
            PP.Width(icon._edges[3], borderSz)
            PP.Width(icon._edges[4], borderSz)
            for i = 1, 4 do
                icon._edges[i]:SetColorTexture(brdR, brdG, brdB, brdA)
                icon._edges[i]:SetSnapToPixelGrid(false)
                icon._edges[i]:SetTexelSnappingBias(0)
            end
        end

        -- Restore icon texture coords
        if icon._tex then
            icon._tex:ClearAllPoints()
            PP.Point(icon._tex, "TOPLEFT", icon, "TOPLEFT", borderSz, -borderSz)
            PP.Point(icon._tex, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSz, borderSz)
            if shape == "cropped" then
                icon._tex:SetTexCoord(zoom, 1 - zoom, zoom + 0.10, 1 - zoom - 0.10)
            else
                icon._tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            end
        end

        -- Restore cooldown
        if icon._cooldown then
            icon._cooldown:ClearAllPoints()
            PP.Point(icon._cooldown, "TOPLEFT", icon, "TOPLEFT", borderSz, -borderSz)
            PP.Point(icon._cooldown, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSz, borderSz)
            pcall(icon._cooldown.SetSwipeTexture, icon._cooldown, "Interface\\Buttons\\WHITE8x8")
            if icon._cooldown.SetUseCircularEdge then pcall(icon._cooldown.SetUseCircularEdge, icon._cooldown, false) end
        end

        -- Restore background
        if icon._bg then
            icon._bg:ClearAllPoints(); icon._bg:SetAllPoints()
        end
        return
    end

    -- Custom shape
    local maskTex = CDM_SHAPE_MASKS[shape]
    if not maskTex then return end

    if not icon._shapeMask then
        icon._shapeMask = icon:CreateMaskTexture()
    end
    local mask = icon._shapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    -- Remove existing mask refs before re-adding
    if icon._tex then pcall(icon._tex.RemoveMaskTexture, icon._tex, mask) end
    if icon._bg then pcall(icon._bg.RemoveMaskTexture, icon._bg, mask) end
    if icon._cooldown then pcall(icon._cooldown.RemoveMaskTexture, icon._cooldown, mask) end

    -- Apply mask to icon texture and background
    if icon._tex then icon._tex:AddMaskTexture(mask) end
    if icon._bg then icon._bg:AddMaskTexture(mask) end

    -- Expand icon beyond frame for shape
    local shapeOffset = CDM_SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
    local shapeDefault = CDM_SHAPE_ZOOM_DEFAULTS[shape] or 0.06
    local iconExp = CDM_SHAPE_ICON_EXPAND + shapeOffset + ((zoom - shapeDefault) * 200)
    if iconExp < 0 then iconExp = 0 end
    local halfIE = iconExp / 2
    if icon._tex then
        icon._tex:ClearAllPoints()
        PP.Point(icon._tex, "TOPLEFT", icon, "TOPLEFT", -halfIE, halfIE)
        PP.Point(icon._tex, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Mask position (inset for border)
    mask:ClearAllPoints()
    if borderSz >= 1 then
        PP.Point(mask, "TOPLEFT", icon, "TOPLEFT", 1, -1)
        PP.Point(mask, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    else
        mask:SetAllPoints(icon)
    end

    -- Expand texcoords for shape
    local insetPx = CDM_SHAPE_INSETS[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if icon._tex then icon._tex:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand) end

    -- Hide square borders
    if icon._edges then
        for i = 1, 4 do icon._edges[i]:Hide() end
    end

    -- Shape border texture (on a dedicated frame above the cooldown swipe)
    if not icon._shapeBorderFrame then
        local sbf = CreateFrame("Frame", nil, icon)
        sbf:SetAllPoints(icon)
        sbf:SetFrameLevel(icon:GetFrameLevel() + 2)
        icon._shapeBorderFrame = sbf
    end
    icon._shapeBorderFrame:SetFrameLevel(icon:GetFrameLevel() + 2)
    if not icon._shapeBorder then
        icon._shapeBorder = icon._shapeBorderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = icon._shapeBorder
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(icon)
    if borderSz > 0 and CDM_SHAPE_BORDERS[shape] then
        borderTex:SetTexture(CDM_SHAPE_BORDERS[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:SetSnapToPixelGrid(false)
        borderTex:SetTexelSnappingBias(0)
        borderTex:Show()
    else
        borderTex:Hide()
    end

    -- Apply mask to cooldown so swipe follows shape
    if icon._cooldown then
        icon._cooldown:ClearAllPoints()
        icon._cooldown:SetAllPoints(icon)
        pcall(icon._cooldown.AddMaskTexture, icon._cooldown, mask)
        if icon._cooldown.SetSwipeTexture then
            pcall(icon._cooldown.SetSwipeTexture, icon._cooldown, maskTex)
        end
        local useCircular = (shape ~= "square" and shape ~= "csquare")
        if icon._cooldown.SetUseCircularEdge then pcall(icon._cooldown.SetUseCircularEdge, icon._cooldown, useCircular) end
        local edgeScale = CDM_SHAPE_EDGE_SCALES[shape] or 0.60
        if icon._cooldown.SetEdgeScale then pcall(icon._cooldown.SetEdgeScale, icon._cooldown, edgeScale) end
    end

    -- Restore background to full icon
    if icon._bg then
        icon._bg:ClearAllPoints(); icon._bg:SetAllPoints()
    end

    icon._shapeApplied = true
    icon._shapeName = shape
end
ns.ApplyShapeToCDMIcon = ApplyShapeToCDMIcon

-------------------------------------------------------------------------------
--  Update icons for a CDM bar based on Blizzard CDM children
--  We read the Blizzard CDM bar's children to know which spells are active,
--  then mirror them on our own bar.
-------------------------------------------------------------------------------
-- Shared sort comparator for Blizzard CDM children (avoids closure allocation per tick)
local function SortBlizzChildren(a, b)
    local ai = a.layoutIndex or 0
    local bi = b.layoutIndex or 0
    if ai ~= bi then return ai < bi end
    local ax = a:GetLeft() or 0
    local bx = b:GetLeft() or 0
    return ax < bx
end

-- Reusable buffer for Blizzard CDM children (avoids table allocation per tick)
local _blizzIconsBuf = {}

-- Spell icon texture cache (avoids C_Spell.GetSpellInfo per tick per icon)
local _spellIconCache = {}

-------------------------------------------------------------------------------
--  Update icons for a CDM bar based on Blizzard CDM children
--  Default bars (cooldowns/utility/buffs) mirror Blizzard CDM.
--  Custom bars track user-specified spells directly.
-------------------------------------------------------------------------------
local function UpdateCustomBarIcons(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end


    local spells = barData.customSpells
    if not spells or #spells == 0 then
        -- Hide all icons
        local icons = cdmBarIcons[barKey]
        if icons then
            for _, icon in ipairs(icons) do icon:Hide() end
        end
        frame:SetSize(1, 1)
        return
    end

    local icons = cdmBarIcons[barKey]

    -- Active animation setup (same as tracked/mirrored bar paths)
    local activeAnim = barData.activeStateAnim or "blizzard"
    local animR, animG, animB = 1.0, 0.85, 0.0
    if barData.activeAnimClassColor then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then animR, animG, animB = cc.r, cc.g, cc.b end end
    elseif barData.activeAnimR then
        animR = barData.activeAnimR; animG = barData.activeAnimG or 0.85; animB = barData.activeAnimB or 0.0
    end
    local swAlpha = barData.swipeAlpha or 0.7

    -- Ensure we have enough icon frames
    while #icons < #spells do
        local newIcon = CreateCDMIcon(barKey, #icons + 1)
        icons[#icons + 1] = newIcon
    end

    local visibleCount = 0
    for i, spellID in ipairs(spells) do
        local ourIcon = icons[i]
        if ourIcon then
            -- Skip blank placeholder slots (0 entries from grid reordering)
            if spellID == 0 then
                ourIcon:Hide()
            -- Trinket slot entries use negative IDs (-13, -14)
            elseif spellID < 0 then
                local slot = -spellID
                local itemID = GetInventoryItemID("player", slot)
                if itemID then
                    local tex = C_Item.GetItemIconByID(itemID)
                    if tex and tex ~= ourIcon._lastTex then
                        ourIcon._tex:SetTexture(tex)
                        ourIcon._lastTex = tex
                    end
                    ApplyTrinketCooldown(ourIcon, slot, barData.desaturateOnCD)
                    ourIcon:Show()
                    visibleCount = visibleCount + 1
                else
                    ourIcon:Hide()
                end
            else
            -- Resolve talent override: if the user added Holy Prism but the player
            -- now has Divine Toll selected, display and track Divine Toll instead.
            local resolvedID = spellID
            if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                local overrideID = C_SpellBook.FindSpellOverrideByID(spellID)
                if overrideID and overrideID ~= 0 then
                    resolvedID = overrideID
                end
            end
            -- Second-level runtime override: e.g. spell A (base) -> spell B (talent)
            -- -> spell C (activation override, e.g. Avenging Crusader transforms Crusader Strike).
            -- FindSpellOverrideByID only resolves one level; check the Blizzard CDM
            -- children cache for a deeper override on the already-resolved ID.
            local blizzOverride = _tickBlizzOverrideCache[resolvedID] or _tickBlizzOverrideCache[spellID]
            if blizzOverride then
                resolvedID = blizzOverride
            end
            -- Propagate charge cache from base to override so talent-swapped spells
            -- show charges correctly even before the override ID has been seen OOC.
            -- Always attempt direct detection on the final resolvedID first ΓÇö it may
            -- have charges even if the base spell doesn't (three-level chain).
            if resolvedID ~= spellID then
                -- Always try direct detection on the resolved ID (cheapest path)
                CacheMultiChargeSpell(resolvedID)
                -- If resolved ID still unknown (secret/combat), check if we have a
                -- live Blizzard child for it and mark it as a charge spell so
                -- ApplySpellCooldown uses the charge display path.
                if _multiChargeSpells[resolvedID] == nil and _tickBlizzChildCache[resolvedID] then
                    -- We have a live Blizzard child ΓÇö treat as charge spell so the
                    -- charge display path runs. ApplySpellCooldown will call
                    -- GetSpellCharges which may still be secret, but the shadow
                    -- cooldown frames will correctly reflect the charge state.
                    _multiChargeSpells[resolvedID] = true
                end
                -- If still unknown, try propagating from intermediate (only if true)
                if _multiChargeSpells[resolvedID] == nil then
                    local intermediate = C_SpellBook and C_SpellBook.FindSpellOverrideByID
                        and C_SpellBook.FindSpellOverrideByID(spellID)
                    if intermediate and intermediate ~= 0 and intermediate ~= resolvedID then
                        CacheMultiChargeSpell(intermediate)
                        if _multiChargeSpells[intermediate] == true then
                            _multiChargeSpells[resolvedID] = true
                            if _maxChargeCount[intermediate] then
                                _maxChargeCount[resolvedID] = _maxChargeCount[intermediate]
                            end
                        end
                    end
                end
                -- If still unknown, propagate from base ΓÇö but only if base is true
                if _multiChargeSpells[resolvedID] == nil then
                    CacheMultiChargeSpell(spellID)
                    if _multiChargeSpells[spellID] == true then
                        _multiChargeSpells[resolvedID] = true
                        if _maxChargeCount[spellID] then
                            _maxChargeCount[resolvedID] = _maxChargeCount[spellID]
                        end
                    end
                end
            end
            -- Cache spell icon texture to avoid C_Spell.GetSpellInfo per tick
            local texID = _spellIconCache[resolvedID]
            if not texID then
                local spellInfo = C_Spell.GetSpellInfo(resolvedID)
                if spellInfo then
                    texID = spellInfo.iconID
                    _spellIconCache[resolvedID] = texID
                end
            end
            if texID then
                if texID ~= ourIcon._lastTex then
                    ourIcon._tex:SetTexture(texID)
                    ourIcon._lastTex = texID
                end

                -- Cooldown, desaturation, and charge text (consolidated)
                ourIcon._spellID = resolvedID
                -- Apply cached keybind for this spell if not already set
                if ourIcon._keybindText and barData.showKeybind then
                    local cachedKey = _cdmKeybindCache[resolvedID]
                    if not cachedKey then
                        local n = C_Spell.GetSpellName and C_Spell.GetSpellName(resolvedID)
                        if n then cachedKey = _cdmKeybindCache[n] end
                    end
                    -- Also try the base spellID in case keybind was cached under it
                    if not cachedKey and resolvedID ~= spellID then
                        cachedKey = _cdmKeybindCache[spellID]
                        if not cachedKey then
                            local bn = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                            if bn then cachedKey = _cdmKeybindCache[bn] end
                        end
                    end
                    if cachedKey then
                        ourIcon._keybindText:SetText(cachedKey)
                        ourIcon._keybindText:Show()
                    elseif ourIcon._keybindText:IsShown() then
                        ourIcon._keybindText:Hide()
                    end
                end
                -- Detect active aura state before applying cooldown.
                -- If the spell has an active player aura, show its duration on the
                -- cooldown frame (same as the main bar path for buff bars).
                local auraHandled = false
                local skipCDDisplay = false
                do
                    -- Primary: look up the Blizzard CDM child for this spell via the
                    -- spellID -> cooldownID map, then find the child frame by cooldownID.
                    -- This works for custom bar spells not present in _tickBlizzAllChildCache
                    -- because they may not be visible in any viewer at the moment.
                    local blizzChild = _tickBlizzAllChildCache[resolvedID]
                    if not blizzChild then
                        local cdID = _spellToCooldownID[resolvedID] or _spellToCooldownID[spellID]
                        if cdID then
                            blizzChild = FindCDMChildByCooldownID(cdID)
                        end
                    end
                    local isAura = blizzChild and (blizzChild.wasSetFromAura == true or blizzChild.auraInstanceID ~= nil)
                    local auraID = blizzChild and blizzChild.auraInstanceID
                    local auraUnit = blizzChild and blizzChild.auraDataUnit or "player"

                    -- Fallback: spell not in any CDM viewer ΓÇö check _tickBlizzActiveCache
                    -- which covers all four viewers scanned each tick.
                    if not isAura then
                        if _tickBlizzActiveCache[resolvedID] or _tickBlizzActiveCache[spellID] then
                            isAura = true
                        end
                    end

                    if isAura then
                        local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(resolvedID)
                        local isChargeSid = chargeInfo ~= nil
                        local isBuffBar = (barKey == "buffs" or barData.barType == "buffs")
                        if auraID and (not isChargeSid or isBuffBar) then
                            local ok, auraDurObj = pcall(C_UnitAuras.GetAuraDuration, auraUnit, auraID)
                            if ok and auraDurObj then
                                ourIcon._cooldown:Clear()
                                pcall(ourIcon._cooldown.SetCooldownFromDurationObject, ourIcon._cooldown, auraDurObj, true)
                                ourIcon._cooldown:SetReverse(false)
                                auraHandled = true
                                skipCDDisplay = true
                            else
                                auraHandled = true
                            end
                        else
                            auraHandled = true
                        end
                    end

                    -- Final fallback: _tickBlizzActiveCache covers spells active in CDM viewers
                    if not auraHandled and (_tickBlizzActiveCache[resolvedID] or _tickBlizzActiveCache[spellID]) then
                        auraHandled = true
                    end
                end

                ApplySpellCooldown(ourIcon, resolvedID, barData.desaturateOnCD, barData.showCharges, swAlpha, skipCDDisplay)

                -- If this is a live Blizzard activation override, read the charge
                -- count directly from the Blizzard child's Applications frame.
                -- GetSpellCharges returns secret values in combat for these spells,
                -- but the Applications frame text is always readable.
                if barData.showCharges then
                    local blizzChild = _tickBlizzChildCache[resolvedID]
                    if blizzChild and blizzChild.Applications and blizzChild.Applications.Applications then
                        local ok, txt = pcall(blizzChild.Applications.Applications.GetText, blizzChild.Applications.Applications)
                        if ok and txt and txt ~= "" and txt ~= "0" then
                            ourIcon._chargeText:SetText(txt)
                            ourIcon._chargeText:Show()
                        end
                    end
                end

                if ourIcon._cooldown.SetUseAuraDisplayTime then
                    ourIcon._cooldown:SetUseAuraDisplayTime(false)
                end

                ApplyActiveAnimation(ourIcon, auraHandled, barData, barKey, activeAnim, animR, animG, animB, swAlpha)

                ourIcon:Show()
                visibleCount = visibleCount + 1

                -- Hide buff icons when inactive (aura not active on player) ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ buff bars only
                -- Skip during unlock mode so the bar is fully visible for repositioning
                local isBuffBar = (barKey == "buffs" or barData.barType == "buffs")
                if barData.hideBuffsWhenInactive and isBuffBar and not EllesmereUI._unlockActive
                   and not (EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown()) then
                    -- Use the per-tick active cache built from all CDM viewers
                    if not (_tickBlizzActiveCache[resolvedID] or _tickBlizzActiveCache[spellID]) then
                        ourIcon:Hide()
                        visibleCount = visibleCount - 1
                    end
                end
            else
                ourIcon:Hide()
            end
            end -- spellID < 0 else
        end
    end

    -- Hide excess
    for i = #spells + 1, #icons do
        local ic = icons[i]
        if ic._procGlowActive then
            StopNativeGlow(ic._glowOverlay)
            ic._procGlowActive = false
        end
        ic:Hide()
    end

    -- Only re-layout when visible count changes
    if visibleCount ~= (frame._prevVisibleCount or 0) then
        frame._prevVisibleCount = visibleCount
        LayoutCDMBar(barKey)
    end
end

UpdateCDMBarIcons = function(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end

    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    if not blizzName then return end
    local blizzFrame = _G[blizzName]
    if not blizzFrame then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end

    -- Gather Blizzard CDM icons that have a valid Icon texture.
    -- We do NOT filter by IsShown() because Blizzard children can briefly
    -- hide/show during state transitions (GCD end, cooldown start, etc.),
    -- which causes our icons to flicker.  Instead we check for a texture.
    -- Reuse buffer to avoid table allocation per tick
    local blizzIcons = _blizzIconsBuf
    local blizzCount = 0

    for i = 1, blizzFrame:GetNumChildren() do
        local child = select(i, blizzFrame:GetChildren())
        if child and child.Icon and child.Icon:GetTexture() then
            blizzCount = blizzCount + 1
            blizzIcons[blizzCount] = child
        end
    end
    -- Clear excess entries from previous tick
    for i = blizzCount + 1, #blizzIcons do blizzIcons[i] = nil end

    table.sort(blizzIcons, SortBlizzChildren)

    local icons = cdmBarIcons[barKey]

    -- Ensure we have enough icon frames
    while #icons < #blizzIcons do
        local newIcon = CreateCDMIcon(barKey, #icons + 1)
        icons[#icons + 1] = newIcon
    end

    local desatOnCD = barData.desaturateOnCD
    local showCharges = barData.showCharges
    local swAlpha = barData.swipeAlpha or 0.7
    local activeAnim = barData.activeStateAnim or "blizzard"
    -- Active animation color: class color or custom, full alpha
    local animR, animG, animB = 1.0, 0.85, 0.0
    if barData.activeAnimClassColor then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then animR, animG, animB = cc.r, cc.g, cc.b end end
    elseif barData.activeAnimR then
        animR = barData.activeAnimR; animG = barData.activeAnimG or 0.85; animB = barData.activeAnimB or 0.0
    end

    -- Update each icon to mirror the Blizzard CDM icon
    for i, blizzIcon in ipairs(blizzIcons) do
        local ourIcon = icons[i]
        if ourIcon then
            -- Store mapping so proc glow hooks can find our icon from the Blizzard child
            ourIcon._blizzChild = blizzIcon

            -- Copy the icon texture
            local blizzTex = blizzIcon.Icon
            if blizzTex then
                local texPath = blizzTex:GetTexture()
                if texPath then
                    ourIcon._tex:SetTexture(texPath)
                end
            end

            -- Resolve spell ID from Blizzard CDM child
            local blizzCdID = blizzIcon.cooldownID
            if not blizzCdID and blizzIcon.cooldownInfo then
                blizzCdID = blizzIcon.cooldownInfo.cooldownID
            end
            local resolvedSid
            if blizzCdID then
                local cdViewerInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                    and C_CooldownViewer.GetCooldownViewerCooldownInfo(blizzCdID)
                if cdViewerInfo then
                    resolvedSid = cdViewerInfo.overrideSpellID or cdViewerInfo.spellID
                end
            end

            -- Detect aura/active state
            local isAura = blizzIcon.wasSetFromAura == true or blizzIcon.auraInstanceID ~= nil
            local auraHandled = false
            local skipCDDisplay = false

            if isAura and activeAnim ~= "hideActive" then
                -- Use non-secret charge detection (returns plain table, not DurationObject)
                local chargeInfo = resolvedSid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(resolvedSid)
                local isChargeSid = chargeInfo ~= nil
                -- Buff bars always show buff duration; other bars skip aura duration for charge spells
                local isBuffBar = (barKey == "buffs")
                local auraID = blizzIcon.auraInstanceID
                if auraID and (not isChargeSid or isBuffBar) then
                    -- Show buff duration on the cooldown frame
                    local unit = blizzIcon.auraDataUnit or "player"
                    local ok, auraDurObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraID)
                    if ok and auraDurObj then
                        ourIcon._cooldown:Clear()
                        pcall(ourIcon._cooldown.SetCooldownFromDurationObject, ourIcon._cooldown, auraDurObj, true)
                        ourIcon._cooldown:SetReverse(false)
                        auraHandled = true
                        skipCDDisplay = true
                    else
                        auraHandled = true
                    end
                else
                    -- Charge spell on non-buff bar: mark active for glow, show charge CD
                    auraHandled = true
                end
            end

            -- Spell cooldown + desaturation (uses shared helper)
            if resolvedSid and resolvedSid > 0 then
                ApplySpellCooldown(ourIcon, resolvedSid, desatOnCD, showCharges, swAlpha, skipCDDisplay)
            else
                if desatOnCD and ourIcon._lastDesat then
                    ourIcon._tex:SetDesaturation(0)
                    ourIcon._lastDesat = false
                end
                ourIcon._chargeText:Hide()
            end

            -- Active state animation (consolidated)
            ApplyActiveAnimation(ourIcon, auraHandled, barData, barKey, activeAnim, animR, animG, animB, swAlpha)

            -- Stack count text (consolidated ΓÇö always enabled)
            ApplyStackCount(ourIcon, resolvedSid, blizzIcon.auraInstanceID, blizzIcon.auraDataUnit, true, blizzIcon)

            ourIcon:Show()

            -- Hide buff icons when inactive (aura not active) ├â╞Æ├é┬ó├â┬ó├óΓé¼┼í├é┬¼├â┬ó├óΓÇÜ┬¼├é┬¥ buff bars only
            -- Skip during unlock mode so the bar is fully visible for repositioning
            local isBuffBar = (barKey == "buffs" or barData.barType == "buffs")
            if barData.hideBuffsWhenInactive and isBuffBar and not EllesmereUI._unlockActive
               and not (EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown()) then
                if not (_tickBlizzActiveCache[resolvedSid]) then
                    ourIcon:Hide()
                end
            end
        end
    end

    -- Hide excess icons (with grace period to avoid blink at end of cast)
    for i = #blizzIcons + 1, #icons do
        local ic = icons[i]
        ic._blizzChild = nil
        if ic._procGlowActive then
            StopNativeGlow(ic._glowOverlay)
            ic._procGlowActive = false
        end
        if ic:IsShown() then
            if not ic._hideGraceStart then
                ic._hideGraceStart = GetTime()
            end
            if (GetTime() - ic._hideGraceStart) >= 0.5 then
                ic:Hide()
            end
        end
    end
    -- Clear grace on visible icons
    for i = 1, #blizzIcons do
        if icons[i] then icons[i]._hideGraceStart = nil end
    end

    -- Only re-layout when visible count changes
    -- Count includes grace-period icons still showing
    local visCount = 0
    for i = 1, #icons do
        if icons[i]:IsShown() then visCount = visCount + 1 end
    end
    if visCount ~= (frame._prevVisibleCount or 0) then
        frame._prevVisibleCount = visCount
        LayoutCDMBar(barKey)
    end
end

-------------------------------------------------------------------------------
--  CDM Bar Update Tick (mirrors Blizzard CDM state to our bars)
-------------------------------------------------------------------------------
local cdmUpdateThrottle = 0
local CDM_UPDATE_INTERVAL = 0.1  -- 10fps

-- Refresh visual properties of existing icons (called when settings change)
local function RefreshCDMIconAppearance(barKey)
    local icons = cdmBarIcons[barKey]
    if not icons then return end

    local barData = barDataByKey[barKey]
    if not barData then return end

    local barScale = barData.barScale or 1.0
    if barScale < 0.1 then barScale = 1.0 end
    local borderSize = SnapForScale(barData.borderSize or 1, barScale)
    local zoom = barData.iconZoom or 0.08

    for _, icon in ipairs(icons) do
        -- Update texture zoom
        if icon._tex then
            icon._tex:ClearAllPoints()
            icon._tex:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
            icon._tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
            icon._tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
        -- Update cooldown inset
        if icon._cooldown then
            icon._cooldown:ClearAllPoints()
            icon._cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
            icon._cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
            icon._cooldown:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
            icon._cooldown:SetHideCountdownNumbers(not barData.showCooldownText)
            -- Mark pending font update (applied in batch after frame renders)
            if barData.showCooldownText then
                icon._pendingFontPath = GetCDMFont(); icon._pendingFontSize = barData.cooldownFontSize or 12
            end
        end
        -- Update border edges
        if icon._edges then
            for _, e in ipairs(icon._edges) do
                e:SetColorTexture(barData.borderR or 0, barData.borderG or 0, barData.borderB or 0, barData.borderA or 1)
                PP.DisablePixelSnap(e)
            end
            icon._edges[1]:SetHeight(borderSize)
            icon._edges[2]:SetHeight(borderSize)
            icon._edges[3]:SetWidth(borderSize)
            icon._edges[4]:SetWidth(borderSize)
        end
        -- Update background
        if icon._bg then
            icon._bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08, barData.bgB or 0.08, barData.bgA or 0.6)
            PP.DisablePixelSnap(icon._bg)
        end
        -- Update charge text font/position
        if icon._chargeText then
            icon._chargeText:SetFont(GetCDMFont(), barData.stackCountSize or 11, "OUTLINE")
            icon._chargeText:SetShadowOffset(0, 0)
            icon._chargeText:ClearAllPoints()
            icon._chargeText:SetPoint("BOTTOMRIGHT", barData.stackCountX or 0, (barData.stackCountY or 0) + 2)
            icon._chargeText:SetTextColor(barData.stackCountR or 1, barData.stackCountG or 1, barData.stackCountB or 1)
        end
        -- Update stack count text font/position/color
        if icon._stackText then
            icon._stackText:SetFont(GetCDMFont(), barData.stackCountSize or 11, "OUTLINE")
            icon._stackText:SetShadowOffset(0, 0)
            icon._stackText:ClearAllPoints()
            icon._stackText:SetPoint("BOTTOMRIGHT", barData.stackCountX or 0, (barData.stackCountY or 0) + 2)
            icon._stackText:SetTextColor(barData.stackCountR or 1, barData.stackCountG or 1, barData.stackCountB or 1)
        end

        -- Update keybind text style
        if icon._keybindText then
            icon._keybindText:SetFont(GetCDMFont(), barData.keybindSize or 10, "OUTLINE")
            icon._keybindText:SetShadowOffset(0, 0)
            icon._keybindText:ClearAllPoints()
            icon._keybindText:SetPoint("TOPLEFT", icon._textOverlay, "TOPLEFT", barData.keybindOffsetX or 2, barData.keybindOffsetY or -2)
            icon._keybindText:SetTextColor(barData.keybindR or 1, barData.keybindG or 1, barData.keybindB or 1, barData.keybindA or 0.9)
        end

        -- Update tooltip overlay mouse state
        if icon._tooltipOverlay then
            icon._tooltipOverlay:EnableMouse(false)
        end
        -- Apply custom shape (overrides border/zoom set above)
        local shape = barData.iconShape or "none"
        ApplyShapeToCDMIcon(icon, shape, barData)

        -- Reset active state so glow type change takes effect on next tick
        if icon._glowOverlay then
            StopNativeGlow(icon._glowOverlay)
        end
        icon._isActive = false
        icon._procGlowActive = false
    end
end
ns.RefreshCDMIconAppearance = RefreshCDMIconAppearance

-------------------------------------------------------------------------------
--  Snapshot Blizzard CDM ? populate trackedSpells for a default bar
--  Called once per bar when trackedSpells is nil/empty.
--  Reads the Blizzard viewer children to get cooldownIDs in display order.
-------------------------------------------------------------------------------
local function SnapshotBlizzardCDM(barKey, barData)
    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    if not blizzName then return end
    local blizzFrame = _G[blizzName]
    if not blizzFrame then return end

    local blizzIcons = {}
    for i = 1, blizzFrame:GetNumChildren() do
        local child = select(i, blizzFrame:GetChildren())
        if child and child.Icon then
            blizzIcons[#blizzIcons + 1] = child
        end
    end

    table.sort(blizzIcons, SortBlizzChildren)

    local tracked = {}
    for _, child in ipairs(blizzIcons) do
        local cdID = child.cooldownID
        if not cdID and child.cooldownInfo then
            cdID = child.cooldownInfo.cooldownID
        end
        if cdID then
            tracked[#tracked + 1] = cdID
        end
    end

    -- Only commit if we got actual children — leave nil so the next tick
    -- retries when Blizzard's CDM viewer hasn't populated yet.
    if #tracked == 0 then return false end

    -- Filter out any spells the user has explicitly removed (persisted as spellIDs).
    if barData.removedSpells and next(barData.removedSpells) then
        local filtered = {}
        for _, cdID in ipairs(tracked) do
            local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            local sid = info and (info.overrideSpellID or info.spellID)
            if not sid or not barData.removedSpells[sid] then
                filtered[#filtered + 1] = cdID
            end
        end
        tracked = filtered
    end

    barData.trackedSpells = tracked
    return true
end
ns.SnapshotBlizzardCDM = SnapshotBlizzardCDM

-------------------------------------------------------------------------------
--  Update a self-managed bar using trackedSpells (cooldownIDs)
--  Finds matching Blizzard CDM children to mirror state (secret-safe).
--  Falls back to C_CooldownViewer API for icon texture.
-------------------------------------------------------------------------------
local function UpdateTrackedBarIcons(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end

    local tracked = barData.trackedSpells
    if not tracked or #tracked == 0 then return end

    -- Cache Blizzard CDM children lookup per bar (rebuild when child count changes
    -- or when a tracked cdID is missing from the cache).
    -- Search both viewers for cooldowns/utility so a spell moved between them is found.
    local searchFrameNames = BLIZZ_CDM_SEARCH_FRAMES[barKey]
                          or (BLIZZ_CDM_FRAMES[barKey] and { BLIZZ_CDM_FRAMES[barKey] })
                          or {}
    local blizzName  = BLIZZ_CDM_FRAMES[barKey]
    local blizzFrame = blizzName and _G[blizzName]
    local cache = frame._blizzCache
    local childCount = 0
    for _, fn in ipairs(searchFrameNames) do
        local f = _G[fn]; if f then childCount = childCount + f:GetNumChildren() end
    end

    if not cache or cache._childCount ~= childCount then
        cache = {}
        cache._childCount = childCount
        for _, fn in ipairs(searchFrameNames) do
            local f = _G[fn]
            if f then
                for ci = 1, f:GetNumChildren() do
                    local child = select(ci, f:GetChildren())
                    if child then
                        local cdID = child.cooldownID
                        if not cdID and child.cooldownInfo then
                            cdID = child.cooldownInfo.cooldownID
                        end
                        if cdID then cache[cdID] = child end
                    end
                end
            end
        end
        frame._blizzCache = cache
    end

    -- Build spellID -> cdID map from current cache so stale cdIDs
    -- (spell moved to other viewer, got new cdID) can be remapped in place.
    local sidToNewCdID = {}
    for cid, _ in pairs(cache) do
        if type(cid) ~= "string" then
            local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                and C_CooldownViewer.GetCooldownViewerCooldownInfo(cid)
            if info then
                local sid = info.overrideSpellID or info.spellID
                if sid and sid > 0 then sidToNewCdID[sid] = cid end
            end
        end
    end
                        if not cdID and child.cooldownInfo then
                            cdID = child.cooldownInfo.cooldownID
                        end
                        if cdID then cache[cdID] = child end
                    end
                end
            end
        end
        frame._blizzCache = cache
    end

    -- Build spellID -> cdID map from current cache so stale cdIDs
    -- (spell moved to other viewer, got new cdID) can be remapped in place.
    local sidToNewCdID = {}
    for cid, _ in pairs(cache) do
        if type(cid) ~= "string" then
            local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                and C_CooldownViewer.GetCooldownViewerCooldownInfo(cid)
            if info then
                local sid = info.overrideSpellID or info.spellID
                if sid and sid > 0 then sidToNewCdID[sid] = cid end
            end
        end
    end

    -- 4. Focus color (if enabled)
    if db.focus and UnitIsUnit(unit, "focus") then
        local enabled = defaults.focusColorEnabled
        if db.focusColorEnabled ~= nil then enabled = db.focusColorEnabled end
        if enabled then
            return db.focus.r, db.focus.g, db.focus.b
        end
    end
    -- 5. Neutral
    local reaction = UnitReaction(unit, "player")
    if reaction and reaction == 4 then
        return db.neutral.r, db.neutral.g, db.neutral.b
    end
    if UnitCanAttack("player", unit) and not UnitIsEnemy(unit, "player") then
        return db.neutral.r, db.neutral.g, db.neutral.b
    end
    -- 6. Enemy player class colors
    if UnitIsPlayer(unit) and UnitCanAttack("player", unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            return c.r, c.g, c.b
        end
    end
    -- 7. Miniboss
    local inCombat = UnitAffectingCombat(unit)
    local classification = UnitClassification(unit)
    if classification == "elite" or classification == "worldboss" or classification == "rareelite" then
        local level = UnitLevel(unit)
        local playerLevel = UnitLevel("player")
        if level == -1 or (playerLevel and level >= playerLevel + 1) then
            if type(inCombat) == "boolean" and inCombat then
                return db.miniboss.r, db.miniboss.g, db.miniboss.b
            else
                return DarkenColor(db.miniboss.r, db.miniboss.g, db.miniboss.b)
            end
        end
    end
    -- 8. Caster
    local unitClass = UnitClassBase and UnitClassBase(unit)
    if unitClass == "PALADIN" then
        if type(inCombat) == "boolean" and inCombat then
            return db.caster.r, db.caster.g, db.caster.b
        else
            return DarkenColor(db.caster.r, db.caster.g, db.caster.b)
        end
    end
    -- 9. Tank has aggro (if enabled) â€” below focus/caster/miniboss
    if isThreatUnit and isTankRole and threatStatus >= 3 then
        local enabled = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then enabled = db.tankHasAggroEnabled end
        if enabled then
            return db.tankHasAggro.r, db.tankHasAggro.g, db.tankHasAggro.b
        end
    end
    -- 10. Fallback: enemy in combat / out of combat
    if type(inCombat) == "boolean" and inCombat then
        return db.enemyInCombat.r, db.enemyInCombat.g, db.enemyInCombat.b
    end
    return DarkenColor(db.enemyInCombat.r, db.enemyInCombat.g, db.enemyInCombat.b)
end
local hookedUFs = {}
local hookedHighlights = {}
local npOffscreenParent = CreateFrame("Frame")
npOffscreenParent:Hide()
local storedParents = {}
local function HideBlizzardElement(element)
    if element then
        element:SetAlpha(0)
        element:Hide()
        if element.SetScale then element:SetScale(0.001) end
    end
end
local function MoveToOffscreen(element, unit)
    if not element then return end
    if not storedParents[element] then
        storedParents[element] = element:GetParent()
    end
    element:SetParent(npOffscreenParent)
end
local function RestoreFromOffscreen(element)
    if not element then return end
    local origParent = storedParents[element]
    if origParent then
        element:SetParent(origParent)
        storedParents[element] = nil
    end
end
local function HideBlizzardFrame(nameplate, unit)
    if not nameplate then return end
    local uf = nameplate.UnitFrame
    if not uf then return end
    if unit and UnitCanAttack("player", unit) then
        uf:SetAlpha(0)
        if uf.healthBar then
            uf.healthBar:SetParent(npOffscreenParent)
        end
        -- Move visual children off the UnitFrame so Blizzard's layout engine
        -- stops recalculating bounds from them.
        MoveToOffscreen(uf.HealthBarsContainer, unit)
        MoveToOffscreen(uf.castBar, unit)
        MoveToOffscreen(uf.name, unit)
        MoveToOffscreen(uf.selectionHighlight, unit)
        MoveToOffscreen(uf.aggroHighlight, unit)
        MoveToOffscreen(uf.softTargetFrame, unit)
        MoveToOffscreen(uf.SoftTargetFrame, unit)
        MoveToOffscreen(uf.ClassificationFrame, unit)
        MoveToOffscreen(uf.RaidTargetFrame, unit)
        MoveToOffscreen(uf.PlayerLevelDiffFrame, unit)
        if uf.BuffFrame then uf.BuffFrame:SetAlpha(0) end
        -- Move AurasFrame list frames offscreen â€” we query C_UnitAuras
        -- directly for debuff/CC data so these visual lists are unused.
        if uf.AurasFrame then
            MoveToOffscreen(uf.AurasFrame.DebuffListFrame, unit)
            MoveToOffscreen(uf.AurasFrame.BuffListFrame, unit)
            MoveToOffscreen(uf.AurasFrame.CrowdControlListFrame, unit)
            MoveToOffscreen(uf.AurasFrame.LossOfControlFrame, unit)
        end
        -- Do NOT unregister events on the Blizzard UnitFrame â€” we need its
        -- AurasFrame to keep processing UNIT_AURA so debuffList stays current
        -- for our "important" debuff filtering.  All visual children are already
        -- reparented offscreen so layout recalculations won't shift bounds.
        -- Only silence the castBar events (we render our own cast bar).
        if uf.castBar then
            uf.castBar:UnregisterAllEvents()
        end
        -- Keep WidgetContainer functional but reparent it to the nameplate
        -- itself so its layout doesn't affect the UnitFrame's bounds.
        if uf.WidgetContainer then
            uf.WidgetContainer:SetParent(nameplate)
        end
    end
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self)
            if locked then return end
            locked = true
            local ufUnit = self.unit or (self.GetUnit and self:GetUnit())
            if ufUnit and UnitExists(ufUnit) and UnitCanAttack("player", ufUnit) then
                self:SetAlpha(0)
            end
            locked = false
        end)
    end
    if uf.selectionHighlight and not hookedHighlights[uf.selectionHighlight] then
        hookedHighlights[uf.selectionHighlight] = true
        hooksecurefunc(uf.selectionHighlight, "Show", function(self)
            local parent = self:GetParent()
            if parent == npOffscreenParent then return end
            if parent then
                local ufUnit = parent.unit or (parent.GetUnit and parent:GetUnit())
                if ufUnit and UnitExists(ufUnit) and UnitCanAttack("player", ufUnit) then
                    self:SetAlpha(0)
                    self:Hide()
                end
            end
        end)
        hooksecurefunc(uf.selectionHighlight, "SetShown", function(self, shown)
            if shown then
                local parent = self:GetParent()
                if parent == npOffscreenParent then return end
                if parent then
                    local ufUnit = parent.unit or (parent.GetUnit and parent:GetUnit())
                    if ufUnit and UnitExists(ufUnit) and UnitCanAttack("player", ufUnit) then
                        self:SetAlpha(0)
                        self:Hide()
                    end
                end
            end
        end)
    end
end
-- Restore Blizzard UnitFrame elements when a nameplate is removed, so the
-- recycled nameplate frame is in a clean state for the next unit.
local function RestoreBlizzardFrame(nameplate)
    if not nameplate then return end
    local uf = nameplate.UnitFrame
    if not uf then return end
    -- Restore reparented children
    if uf.healthBar and storedParents[uf.healthBar] then
        uf.healthBar:SetParent(storedParents[uf.healthBar])
        storedParents[uf.healthBar] = nil
    end
    RestoreFromOffscreen(uf.HealthBarsContainer)
    RestoreFromOffscreen(uf.castBar)
    RestoreFromOffscreen(uf.name)
    RestoreFromOffscreen(uf.selectionHighlight)
    RestoreFromOffscreen(uf.aggroHighlight)
    RestoreFromOffscreen(uf.softTargetFrame)
    RestoreFromOffscreen(uf.SoftTargetFrame)
    RestoreFromOffscreen(uf.ClassificationFrame)
    RestoreFromOffscreen(uf.RaidTargetFrame)
    RestoreFromOffscreen(uf.PlayerLevelDiffFrame)
    -- Restore WidgetContainer
    if uf.WidgetContainer then
        uf.WidgetContainer:SetParent(uf)
    end
    -- Restore AurasFrame children
    if uf.AurasFrame then
        local af = uf.AurasFrame
        RestoreFromOffscreen(af.DebuffListFrame)
        RestoreFromOffscreen(af.BuffListFrame)
        RestoreFromOffscreen(af.CrowdControlListFrame)
        RestoreFromOffscreen(af.LossOfControlFrame)
    end
end
ns.HideBlizzardFrame = HideBlizzardFrame
local castFallbackFrame = CreateFrame("Frame")
local fallbackCastCount = 0
castFallbackFrame:SetScript("OnUpdate", function()
    for _, plate in pairs(ns.plates) do
        if plate._castFallback and plate.isCasting and plate.unit and plate.nameplate then
            local bc = plate.nameplate.UnitFrame and plate.nameplate.UnitFrame.castBar
            if bc and bc:IsShown() then
                plate.cast:SetMinMaxValues(bc:GetMinMaxValues())
                plate.cast:SetValue(bc:GetValue())
            else
                if not plate._interrupted then
                    plate.cast:Hide()
                end
                plate.isCasting = false
                plate._castFallback = nil
                fallbackCastCount = fallbackCastCount - 1
                if fallbackCastCount <= 0 then
                    fallbackCastCount = 0
                    castFallbackFrame:Hide()
                end
                NotifyCastEnded()
            end
        end
    end
end)
castFallbackFrame:Hide()

-- Pandemic glow alpha-only tick: only iterates slots with active pandemic glows
local pandemicTickFrame = CreateFrame("Frame")
local pandemicTickAccum = 0
pandemicTickFrame:SetScript("OnUpdate", function(_, elapsed)
    pandemicTickAccum = pandemicTickAccum + elapsed
    if pandemicTickAccum < 0.2 then return end
    pandemicTickAccum = 0
    if not GetPandemicGlow() then return end
    for slot in pairs(ns.activePandemicSlots) do
        local durObj = slot._durationObj
        if durObj and slot.pandemicGlow and slot.pandemicGlow.active then
            slot.pandemicGlow.wrapper:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(durObj:IsZero(), 0, durObj:EvaluateRemainingPercent(ns.pandemicCurve)))
        else
            ns.StopPandemicGlow(slot)
        end
    end
end)

local NameplateFrame = {}
function NameplateFrame:SetUnit(unit, nameplate)
    self.unit = unit
    self.nameplate = nameplate
    self:SetParent(nameplate)
    self:ClearAllPoints()
    -- Single center anchor: the entire plate moves as one unit when the
    -- nameplate bounces by 1px, preventing individual edges from rounding
    -- independently (the "pixel shimmer" / bouncing-sides issue).
    self:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    self:SetSize(1, 1)
    self:SetFrameLevel(nameplate:GetFrameLevel() + 1)
    self:Show()
    -- Stacking bounds: tell WoW to use our visual footprint for stacking,
    -- not the Blizzard UnitFrame's layout bounds (which include AurasFrame).
    -- Height covers name text above + health bar + cast bar below.
    if nameplate.SetStackingBoundsFrame then
        if not self._stackBounds then
            self._stackBounds = CreateFrame("Frame", nil, nameplate)
            -- WoW needs renderable content to measure frame bounds
            local tex = self._stackBounds:CreateTexture(nil, "BACKGROUND")
            tex:SetColorTexture(1, 0, 0, 0)
            tex:SetAllPoints(self._stackBounds)
        end
        self._stackBounds:SetParent(nameplate)
        self._stackBounds:ClearAllPoints()
        local barH = GetHealthBarHeight()
        local castH2 = GetCastBarHeight()
        local nameGap = 4 + GetEnemyNameTextSize()
        local totalH = nameGap + barH + castH2
        local scale = GetStackSpacingScale() / 100
        -- Anchor directly to nameplate to avoid any influence from our
        -- plate frame's scale changes (ApplyCastScale).
        self._stackBounds:SetPoint("CENTER", nameplate, "CENTER", 0, GetNameplateYOffset())
        self._stackBounds:SetSize(GetHealthBarWidth(), totalH * scale)
        self._stackBounds:Show()
        nameplate:SetStackingBoundsFrame(self._stackBounds)
    end
    local castH = GetCastBarHeight()
    -- Focus cast height multiplier
    if unit and UnitIsUnit(unit, "focus") then
        local pct = GetFocusCastHeight()
        if pct ~= 100 then
            castH = math.floor(castH * pct / 100 + 0.5)
        end
    end
    local gap = GetAuraSpacing()
    local debuffY = GetDebuffYOffset()
    self.health:ClearAllPoints()
    self.health:SetPoint("CENTER", self, "CENTER", 0, GetNameplateYOffset())
    self.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    self.absorb:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    self.cast:SetSize(GetHealthBarWidth(), castH)
    self.cast:ClearAllPoints()
    self.cast:SetPoint("TOPLEFT", self.health, "BOTTOMLEFT", 0, 0)
    self.castIconFrame:SetSize(castH, castH)
    self.castIconFrame:ClearAllPoints()
    self.castIconFrame:SetPoint("TOPRIGHT", self.cast, "TOPLEFT", 0, 0)
    -- Apply cast icon visibility and scale
    local showIcon = GetShowCastIcon()
    if showIcon then
        local iconScale = GetCastIconScale()
        self.castIconFrame:SetScale(iconScale)
        self.castIconFrame:Show()
    else
        self.castIconFrame:Hide()
    end
    self.castLeftBorder:SetWidth(1)
    self.castSpark:SetHeight(castH)
    -- Kick tick marker sizing
    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
    -- Enemy name color (per-slot)
    local db = EllesmereUINameplatesDB
    local nameSlotKey = FindSlotForElement("enemyName")
    if nameSlotKey then
        local nr, ng, nb = GetTextSlotColor(nameSlotKey)
        self.name:SetTextColor(nr, ng, nb, 1)
    end
    -- Name position (top = above bar, left/center/right = inside bar)
    self:RefreshNamePosition()
    -- Cast text sizes and colors
    local cns = (db and db.castNameSize) or defaults.castNameSize
    local cts = (db and db.castTargetSize) or defaults.castTargetSize
    local cnc = (db and db.castNameColor) or defaults.castNameColor
    SetFSFont(self.castName, cns, GetNPOutline())
    SetFSFont(self.castTarget, cts, GetNPOutline())
    self.castName:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
    -- Cast target color: class-colored if enabled and target is a player, otherwise use castTargetColor
    local useClassColor = defaults.castTargetClassColor
    if db and db.castTargetClassColor ~= nil then useClassColor = db.castTargetClassColor end
    if useClassColor then
        local appliedCTC = false
        if self.unit then
            local classToken
            if UnitSpellTargetClass then
                classToken = UnitSpellTargetClass(self.unit)
            end
            if not classToken then
                local targetUnit = self.unit .. "target"
                if UnitIsPlayer(targetUnit) then
                    classToken = UnitClassBase(targetUnit)
                end
            end
            if classToken then
                local okC, c = pcall(function() return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] end)
                if okC and c then
                    self.castTarget:SetTextColor(c.r, c.g, c.b, 1)
                    appliedCTC = true
                end
            end
        end
        if not appliedCTC then
            self.castTarget:SetTextColor(1, 1, 1, 1)
        end
    else
        local ctc = (db and db.castTargetColor) or defaults.castTargetColor
        self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
    end
    -- Aura duration text settings (unified across debuffs, buffs, CCs)
    local auraDurSize = (db and db.auraDurationTextSize) or defaults.auraDurationTextSize
    local auraDurColor = (db and db.auraDurationTextColor) or defaults.auraDurationTextColor
    local auraStackSize = (db and db.auraStackTextSize) or defaults.auraStackTextSize
    local auraStackColor = (db and db.auraStackTextColor) or defaults.auraStackTextColor
    -- Aura timer positions (per-type: debuffs, buffs, CCs â€” with "none" to hide)
    local debuffTPos = (db and db.debuffTimerPosition) or (db and db.auraTextPosition) or defaults.debuffTimerPosition
    local buffTPos   = (db and db.buffTimerPosition)   or (db and db.auraTextPosition) or defaults.buffTimerPosition
    local ccTPos     = (db and db.ccTimerPosition)     or (db and db.auraTextPosition) or defaults.ccTimerPosition

    -- Helper: apply timer position to a duration text fontstring
    -- For "none", uses SetHideCountdownNumbers(true) to tell the Blizzard cooldown
    -- system to suppress the text entirely, which is more reliable than hiding the
    -- FontString directly (Blizzard re-shows it) or zeroing alpha/font size (gets
    -- overridden by the cooldown system).
    local function ApplyTimerPosition(durText, auraFrame, pos)
        local cd = auraFrame.cd
        if pos == "none" then
            if cd and cd.SetHideCountdownNumbers then
                cd:SetHideCountdownNumbers(true)
            end
            return
        end
        if cd and cd.SetHideCountdownNumbers then
            cd:SetHideCountdownNumbers(false)
        end
        SetFSFont(durText, auraDurSize, "OUTLINE")
        durText:SetTextColor(auraDurColor.r, auraDurColor.g, auraDurColor.b, 1)
        durText:ClearAllPoints()
        if pos == "center" then
            durText:SetPoint("CENTER", auraFrame, "CENTER", 0, 0)
            durText:SetJustifyH("CENTER")
        elseif pos == "topright" then
            PP.Point(durText, "TOPRIGHT", auraFrame, "TOPRIGHT", 3, 4)
            durText:SetJustifyH("RIGHT")
        else -- topleft (default)
            PP.Point(durText, "TOPLEFT", auraFrame, "TOPLEFT", -3, 4)
            durText:SetJustifyH("LEFT")
        end
    end

    -- Debuff duration text + position + stack count styling
    for i = 1, 4 do
        if self.debuffs[i] and self.debuffs[i].cd and self.debuffs[i].cd.text then
            SetFSFont(self.debuffs[i].cd.text, auraDurSize, "OUTLINE")
            self.debuffs[i].cd.text:SetTextColor(auraDurColor.r, auraDurColor.g, auraDurColor.b, 1)
            ApplyTimerPosition(self.debuffs[i].cd.text, self.debuffs[i], debuffTPos)
        end
        if self.debuffs[i] and self.debuffs[i].count then
            SetFSFont(self.debuffs[i].count, auraStackSize, "OUTLINE")
            self.debuffs[i].count:SetTextColor(auraStackColor.r, auraStackColor.g, auraStackColor.b, 1)
        end
    end
    -- Icon sizes from DB
    local debuffSz = GetDebuffIconSize()
    local buffSz = GetBuffIconSize()
    local ccSz = GetCCIconSize()
    local debuffSlot, buffSlot, ccSlot = GetAuraSlots()
    -- Debuff icon sizes (positions handled in UpdateAuras via PositionAuraSlot)
    for i = 1, 4 do
        PP.Size(self.debuffs[i], debuffSz, debuffSz)
    end
    -- Buff spacing + size + duration/stack text styling + timer position
    for i = 1, 4 do
        PP.Size(self.buffs[i], buffSz, buffSz)
        if self.buffs[i].cd and self.buffs[i].cd.text then
            SetFSFont(self.buffs[i].cd.text, auraDurSize, "OUTLINE")
            self.buffs[i].cd.text:SetTextColor(auraDurColor.r, auraDurColor.g, auraDurColor.b, 1)
            ApplyTimerPosition(self.buffs[i].cd.text, self.buffs[i], buffTPos)
        end
        if self.buffs[i].count then
            SetFSFont(self.buffs[i].count, auraStackSize, "OUTLINE")
            self.buffs[i].count:SetTextColor(auraStackColor.r, auraStackColor.g, auraStackColor.b, 1)
        end
    end
    PositionAuraSlot(self.buffs, 4, buffSlot, self, buffSz, buffSz, gap, GetAuraSlotOffsets("buffSlot"))
    -- CC spacing + size + duration/stack text styling + timer position
    for i = 1, 2 do
        PP.Size(self.cc[i], ccSz, ccSz)
        if self.cc[i].cd and self.cc[i].cd.text then
            SetFSFont(self.cc[i].cd.text, auraDurSize, "OUTLINE")
            self.cc[i].cd.text:SetTextColor(auraDurColor.r, auraDurColor.g, auraDurColor.b, 1)
            ApplyTimerPosition(self.cc[i].cd.text, self.cc[i], ccTPos)
        end
    end
    PositionAuraSlot(self.cc, 2, ccSlot, self, ccSz, ccSz, gap, GetAuraSlotOffsets("ccSlot"))
if self.absorbOverflow then
    self.absorbOverflow:SetHeight(GetHealthBarHeight())
end
    HideBlizzardFrame(nameplate, unit)
    self:RegisterUnitEvent("UNIT_HEALTH", unit)
    self:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    self:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    self:RegisterUnitEvent("UNIT_AURA", unit)
    self:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", unit)
    self:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", unit)
    self:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit)
    self:RegisterUnitEvent("UNIT_FLAGS", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)
    self:UpdateHealth()
    self:UpdateName()
    self:UpdateClassification()
    self:UpdateRaidIcon()
    self:ApplyTarget()
    self:ApplyMouseover()
    self:UpdateAuras()
    self:UpdateCast()
    ApplyHealthBarTexture(self)
end
function NameplateFrame:ClearUnit()
    self:UnregisterAllEvents()
    
    
    if self.isCasting then
        self.isCasting = false
        if self._castFallback then
            self._castFallback = nil
            fallbackCastCount = fallbackCastCount - 1
            if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded()
    end
    
    self.name:SetText("")
    for i = 1, 2 do
        local slot = self.cc[i]
        if slot.cd then
            if slot.cd.Clear then
                slot.cd:Clear()
            elseif CooldownFrame_Clear then
                CooldownFrame_Clear(slot.cd)
            else
                slot.cd:SetCooldown(0, 0)
            end
        end
        slot:Hide()
    end
    for i = 1, 4 do
        local dSlot = self.debuffs[i]
        if dSlot.cd then
            if dSlot.cd.Clear then
                dSlot.cd:Clear()
            elseif CooldownFrame_Clear then
                CooldownFrame_Clear(dSlot.cd)
            else
                dSlot.cd:SetCooldown(0, 0)
            end
        end
        dSlot:Hide()
        ns.StopPandemicGlow(dSlot)
        dSlot._durationObj = nil
        local bSlot = self.buffs[i]
        if bSlot.cd then
            if bSlot.cd.Clear then
                bSlot.cd:Clear()
            elseif CooldownFrame_Clear then
                CooldownFrame_Clear(bSlot.cd)
            else
                bSlot.cd:SetCooldown(0, 0)
            end
        end
        bSlot:Hide()
    end
    self.unit = nil
    self.nameplate = nil
    self._shownAuras = nil
    self.cast:Hide()
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.isCasting = false
    self._castFallback = nil
    self._kickProtected = nil
    self:HideKickTick()
    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end
    self._interrupted = nil
    self.glow:Hide()
    self.highlight:Hide()
    self.raidFrame:Hide()
    self.classFrame:Hide()
    self.leftArrow:Hide()
    self.rightArrow:Hide()
    HideClassPowerOnPlate(self)
    self.absorb:Hide()
    if self.absorbOverflow then
    self.absorbOverflow:Hide()
    self.absorbOverflow:SetWidth(0)
end
if self.absorbOverflowDivider then
    self.absorbOverflowDivider:Hide()
end
    self:Hide()
    self:SetScale(1)
    self:SetParent(UIParent)
    self:ClearAllPoints()
    -- Detach stacking bounds from the old nameplate so it doesn't
    -- confuse the stacking engine when the nameplate is recycled.
    if self._stackBounds then
        self._stackBounds:ClearAllPoints()
        self._stackBounds:SetParent(self)
        self._stackBounds:Hide()
    end
end
function NameplateFrame:UpdateHealthValues()
    local unit = self.unit
    if not unit then return end
    if self.nameplate then
        local actualUnit = self.nameplate.namePlateUnitToken
        if actualUnit and actualUnit ~= unit then
            self.unit = actualUnit
            unit = actualUnit
            self:UpdateName()
        end
    end
    if false and self.hpCalculator and self.hpCalculator.GetMaximumHealth then
        -- NOTE: Disabled because hpCalculator methods now return secret/protected values
        -- on the beta, which cannot be passed to StatusBar:SetValue().
        UnitGetDetailedHealPrediction(unit, nil, self.hpCalculator)
        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
        local maxWithAbsorbs = self.hpCalculator:GetMaximumHealth()
        self.health:SetMinMaxValues(0, maxWithAbsorbs)
        self.absorb:SetMinMaxValues(0, maxWithAbsorbs)
        self.absorb:SetValue(self.hpCalculator:GetDamageAbsorbs())
        self.absorb:Show()
        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        self.health:SetValue(self.hpCalculator:GetCurrentHealth())
    else
        local maxHealth = UnitHealthMax(unit)
        self.health:SetMinMaxValues(0, maxHealth)
        self.health:SetValue(UnitHealth(unit))
        self.absorb:SetMinMaxValues(0, maxHealth)
        self.absorb:SetValue(UnitGetTotalAbsorbs(unit))
        self.absorb:Show()
    end

    -- Hash line positioning (target only)
    local hlEnabled = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.hashLineEnabled)
    local hlPct = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.hashLinePercent) or defaults.hashLinePercent
    local isTarget = unit and UnitIsUnit(unit, "target")
    if hlEnabled and hlPct and hlPct > 0 and isTarget then
        local barW = self.health:GetWidth()
        local xPos = barW * (hlPct / 100)
        self.hashLine:ClearAllPoints()
        self.hashLine:SetPoint("TOP", self.health, "TOPLEFT", xPos, 0)
        self.hashLine:SetPoint("BOTTOM", self.health, "BOTTOMLEFT", xPos, 0)
        local hlc = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.hashLineColor) or defaults.hashLineColor
        self.hashLine:SetColorTexture(hlc.r, hlc.g, hlc.b, 0.8)
        self.hashLine:Show()
    else
        self.hashLine:Hide()
    end

    -- Compute text strings
    local pctText, numText
    if UnitIsDeadOrGhost(unit) then
        pctText = "0%"
        numText = "0"
    elseif UnitHealthPercent then
        pctText = string.format("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
        numText = AbbreviateNumbers(UnitHealth(unit))
    else
        pctText = ""
        numText = ""
    end

    local db = EllesmereUINameplatesDB

    -- Hide all health text first
    self.hpText:Hide()
    self.hpNumber:Hide()

    -- Helper to show a health FontString in a bar slot
    local barSlots = {
        { key = "textSlotRight",  anchor = "RIGHT",  point = "RIGHT",  xOff = -2 },
        { key = "textSlotLeft",   anchor = "LEFT",   point = "LEFT",   xOff = 4 },
        { key = "textSlotCenter", anchor = "CENTER", point = "CENTER", xOff = 0 },
    }
    for _, slot in ipairs(barSlots) do
        local element = GetTextSlot(slot.key)
        local txOff, tyOff = GetTextSlotOffsets(slot.key)
        local slotFontSz = GetTextSlotSize(slot.key)
        local sr, sg, sb = GetTextSlotColor(slot.key)
        if element == "healthPercent" then
            self.hpText:SetParent(self.healthTextFrame)
            SetFSFont(self.hpText, slotFontSz, GetNPOutline())
            self.hpText:SetText(pctText)
            self.hpText:ClearAllPoints()
            if slot.anchor == "CENTER" then
                self.hpText:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(self.hpText, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            self.hpText:SetJustifyH(slot.anchor)
            self.hpText:SetTextColor(sr, sg, sb, 1)
            self.hpText:Show()
        elseif element == "healthNumber" then
            self.hpNumber:SetParent(self.healthTextFrame)
            SetFSFont(self.hpNumber, slotFontSz, GetNPOutline())
            self.hpNumber:SetText(numText)
            self.hpNumber:ClearAllPoints()
            if slot.anchor == "CENTER" then
                self.hpNumber:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(self.hpNumber, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            self.hpNumber:SetJustifyH(slot.anchor)
            self.hpNumber:SetTextColor(sr, sg, sb, 1)
            self.hpNumber:Show()
        elseif element == "healthPctNum" or element == "healthNumPct" then
            self.hpText:SetParent(self.healthTextFrame)
            SetFSFont(self.hpText, slotFontSz, GetNPOutline())
            self.hpText:SetText(FormatCombinedHealth(element, pctText, numText))
            self.hpText:ClearAllPoints()
            if slot.anchor == "CENTER" then
                self.hpText:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(self.hpText, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            self.hpText:SetJustifyH(slot.anchor)
            self.hpText:SetTextColor(sr, sg, sb, 1)
            self.hpText:Show()
        end
    end

    -- Process top slot for health elements
    local topElement = GetTextSlot("textSlotTop")
    if topElement == "healthPercent" or topElement == "healthNumber"
       or topElement == "healthPctNum" or topElement == "healthNumPct" then
        local nameYOff = GetNameYOffset()
        local cpPush = GetClassPowerTopPush(self)
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        local topFontSz = GetTextSlotSize("textSlotTop")
        local tr, tg, tb = GetTextSlotColor("textSlotTop")
        local fs
        if topElement == "healthNumber" then
            fs = self.hpNumber
            fs:SetText(numText)
        else
            fs = self.hpText
            if topElement == "healthPercent" then
                fs:SetText(pctText)
            else
                fs:SetText(FormatCombinedHealth(topElement, pctText, numText))
            end
        end
        SetFSFont(fs, topFontSz, GetNPOutline())      SetFSFont(fs, topFontSz, GetNPOutline())
        fs:SetParent(self.topTextFrame)
        fs:ClearAllPoints()
        PP.Point(fs, "BOTTOM", self.health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(tr, tg, tb, 1)
        fs:Show()
    end
end
function NameplateFrame:UpdateHealthColor()
    local unit = self.unit
    if not unit then return end
    self.health:SetStatusBarColor(GetReactionColor(unit))
    -- Focus overlay: show stripe textures on focus target's health bar
    -- Fill clip frame at full alpha, bg clip frame at half alpha
    if self.focusClipFill then
        local db = EllesmereUINameplatesDB or defaults
        local tex = db.focusOverlayTexture or defaults.focusOverlayTexture
        if tex ~= "none" and UnitIsUnit(unit, "focus") then
            local MEDIA = "Interface\\AddOns\\EllesmereUINameplates\\Media\\"
            local texPath = MEDIA .. tex .. ".png"
            local overlayAlpha = db.focusOverlayAlpha or defaults.focusOverlayAlpha
            local oc = db.focusOverlayColor or defaults.focusOverlayColor
            self.focusOverlayFill:SetTexture(texPath)
            self.focusOverlayFill:SetAlpha(overlayAlpha)
            self.focusOverlayFill:SetVertexColor(oc.r, oc.g, oc.b)
            self.focusClipFill:Show()
            self.focusOverlayBg:SetTexture(texPath)
            self.focusOverlayBg:SetAlpha(overlayAlpha * 0.3)
            self.focusOverlayBg:SetVertexColor(oc.r, oc.g, oc.b)
            self.focusClipBg:Show()
        else
            self.focusClipFill:Hide()
            self.focusClipBg:Hide()
        end
    end
end
function NameplateFrame:UpdateHealth()
    self:UpdateHealthValues()
    self:UpdateHealthColor()
end
function NameplateFrame:UpdateName()
    local unit = self.unit
    if not unit then return end
    if self.nameplate then
        local actualUnit = self.nameplate.namePlateUnitToken
        if actualUnit and actualUnit ~= unit then
            self.unit = actualUnit
            unit = actualUnit
        end
    end
    local name = UnitName(unit)
    if type(name) == "string" then
        self.name:SetText(name)
    end
end
function NameplateFrame:UpdateClassification()
    if not self.unit then return end
    local slot = GetClassificationSlot()
    if slot == "none" or InRealInstancedContent() then
        self.classFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    local c = UnitClassification(self.unit)
    if c == "elite" or c == "worldboss" then
        self.class:SetAtlas("nameplates-icon-elite-gold")
    elseif c == "rareelite" then
        self.class:SetAtlas("nameplates-icon-elite-silver")
    elseif c == "rare" then
        self.class:SetAtlas("nameplates-icon-star")
    else
        self.classFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    local cpPush = GetClassPowerTopPush(self)
    local cxOff, cyOff = GetAuraSlotOffsets("classification")
    local reSize = GetRareEliteIconSize()
    PP.Size(self.classFrame, reSize, reSize)
    self.classFrame:ClearAllPoints()
    if slot == "top" then
        local debuffY = GetDebuffYOffset()
        PP.Point(self.classFrame, "BOTTOM", self.health, "TOP",
            cxOff, debuffY + cpPush + cyOff)
    elseif slot == "left" then
        local sideOff = GetSideAuraXOffset()
        PP.Point(self.classFrame, "RIGHT", self.health, "LEFT",
            -sideOff + cxOff, cyOff)
    elseif slot == "right" then
        local sideOff = GetSideAuraXOffset()
        PP.Point(self.classFrame, "LEFT", self.health, "RIGHT",
            sideOff + cxOff, cyOff)
    elseif slot == "topleft" then
        PP.Point(self.classFrame, "BOTTOMLEFT", self.health, "TOPLEFT", -2 + cxOff, 2 + cpPush + cyOff)
    elseif slot == "topright" then
        PP.Point(self.classFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", 2 + cxOff, 2 + cpPush + cyOff)
    end
    self.classFrame:Show()
    self:UpdateNameWidth()
end
function NameplateFrame:UpdateNameWidth()
    local barW = GetHealthBarWidth()
    local nameSlot = FindSlotForElement("enemyName")
    if nameSlot == "textSlotTop" then
        -- Above the bar: full bar width minus raid marker if shown
        local nameW = barW
        local rmPos = GetRaidMarkerPos()
        if rmPos ~= "none" and self.raidFrame:IsShown() then
            nameW = nameW - 2 * (GetRaidMarkerSize() - 2) - 7
        end
        local clSlot = GetClassificationSlot()
        if clSlot ~= "none" and self.classFrame:IsShown() then
            nameW = nameW - (GetRareEliteIconSize() + 4)
        end
        PP.Width(self.name, math.max(nameW, 20))
    elseif nameSlot then
        -- Inside the bar: estimate how much space health text occupies in
        -- opposing slots, then give the name everything that remains.
        local usedWidth = 0
        local barKeys = { "textSlotRight", "textSlotLeft", "textSlotCenter" }
        for _, key in ipairs(barKeys) do
            if key ~= nameSlot then
                local el = GetTextSlot(key)
                if el ~= "none" and el ~= "enemyName" then
                    usedWidth = usedWidth + EstimateHealthTextWidth(el)
                end
            end
        end
        local nameW = barW - usedWidth
        PP.Width(self.name, math.max(nameW, 20))
    else
        -- Name not in any slot, use minimal width
        PP.Width(self.name, math.max(barW, 20))
    end
end
function NameplateFrame:RefreshNamePosition()
    local nameSlot = FindSlotForElement("enemyName")
    local nameYOff = GetNameYOffset()
    self:UpdateNameWidth()
    self.name:ClearAllPoints()
    if nameSlot == "textSlotLeft" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotLeft")
        SetFSFont(self.name, GetTextSlotSize("textSlotLeft"), GetNPOutline())
        self.name:SetParent(self.healthTextFrame)
        PP.Point(self.name, "LEFT", self.health, "LEFT", 4 + txOff, tyOff)
        self.name:SetJustifyH("LEFT")
        self.name:Show()
    elseif nameSlot == "textSlotCenter" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotCenter")
        SetFSFont(self.name, GetTextSlotSize("textSlotCenter"), GetNPOutline())
        self.name:SetParent(self.healthTextFrame)
        self.name:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    elseif nameSlot == "textSlotRight" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotRight")
        SetFSFont(self.name, GetTextSlotSize("textSlotRight"), GetNPOutline())
        self.name:SetParent(self.healthTextFrame)
        PP.Point(self.name, "RIGHT", self.health, "RIGHT", -2 + txOff, tyOff)
        self.name:SetJustifyH("RIGHT")
        self.name:Show()
    elseif nameSlot == "textSlotTop" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        SetFSFont(self.name, GetTextSlotSize("textSlotTop"), GetNPOutline())
        self.name:SetParent(self.topTextFrame)
        local cpPush = GetClassPowerTopPush(self)
        PP.Point(self.name, "BOTTOM", self.health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    else
        -- Name not assigned to any slot
        self.name:Hide()
    end
    self:UpdateAuras()
    self:UpdateClassification()
end
function NameplateFrame:UpdateRaidIcon()
    if not self.unit then return end
    local pos = GetRaidMarkerPos()
    if pos == "none" then
        self.raidFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    -- type() is taint-safe: returns "nil"/"number" without reading the secret value
    local idx = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
    if type(idx) == "nil" then
        self.raidFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    SetRaidTargetIconTexture(self.raid, idx)
    local sz = GetRaidMarkerSize()
    PP.Size(self.raidFrame, sz, sz)
    local cpPush = GetClassPowerTopPush(self)
    local rxOff, ryOff = GetAuraSlotOffsets("raidMarker")
    self.raidFrame:ClearAllPoints()
    if pos == "top" then
        local debuffY = GetDebuffYOffset()
        PP.Point(self.raidFrame, "BOTTOM", self.health, "TOP",
            rxOff, debuffY + cpPush + ryOff)
    elseif pos == "left" then
        local sideOff = GetSideAuraXOffset()
        PP.Point(self.raidFrame, "RIGHT", self.health, "LEFT",
            -sideOff + rxOff, ryOff)
    elseif pos == "right" then
        local sideOff = GetSideAuraXOffset()
        PP.Point(self.raidFrame, "LEFT", self.health, "RIGHT",
            sideOff + rxOff, ryOff)
    elseif pos == "topleft" then
        PP.Point(self.raidFrame, "BOTTOMLEFT", self.health, "TOPLEFT", -2 + rxOff, cpPush + ryOff)
    elseif pos == "topright" then
        PP.Point(self.raidFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", 2 + rxOff, cpPush + ryOff)
    end
    self.raidFrame:Show()
    self:UpdateNameWidth()
end
function NameplateFrame:ApplyTarget()
    if not self.unit then return end
    local isTarget = UnitIsUnit(self.unit, "target")
    local style = GetTargetGlowStyle()
    if isTarget and style ~= "none" then
        self.glow:Show()
    else
        self.glow:Hide()
    end
    -- Vibrant: override health bar border to white on selected target
    if isTarget and style == "vibrant" then
        for _, tex in ipairs(self.borderFrame._texs) do tex:SetVertexColor(1, 1, 1) end
        for _, tex in ipairs(self._simpleBorderFrame._texs) do tex:SetVertexColor(1, 1, 1) end
    else
        self:ApplyBorderColor()
    end
    if EllesmereUINameplatesDB and EllesmereUINameplatesDB.showTargetArrows then
        if isTarget then
            local sc = EllesmereUINameplatesDB.targetArrowScale or 1.0
            local aw, ah = math.floor(11 * sc + 0.5), math.floor(16 * sc + 0.5)
            PP.Size(self.leftArrow,  aw, ah)
            PP.Size(self.rightArrow, aw, ah)
            self.leftArrow:Show()
            self.rightArrow:Show()
        else
            self.leftArrow:Hide()
            self.rightArrow:Hide()
        end
    else
        self.leftArrow:Hide()
        self.rightArrow:Hide()
    end
    -- Class power pips: show on target, hide on others
    if GetShowClassPower() and classPowerType then
        if isTarget then
            EnsureClassPowerPips(self)
            UpdateClassPowerOnPlate(self)
        else
            HideClassPowerOnPlate(self)
        end
    end
end
function NameplateFrame:ApplyMouseover()
    if not self.unit then return end
    if UnitExists("mouseover") and UnitIsUnit(self.unit, "mouseover") then
        self.highlight:Show()
        currentMouseoverPlate = self
    else
        self.highlight:Hide()
    end
end
function NameplateFrame:UpdateAuras(updateInfo)
    if not self.unit or not self.nameplate then return end
    local unit = self.unit

    local needsFullRefresh = not updateInfo or updateInfo.isFullUpdate or not self._shownAuras
    
    if not needsFullRefresh then
        local hasRelevantChange = false
        if updateInfo.addedAuras and #updateInfo.addedAuras > 0 then
            -- Always refresh when auras are added so the new debuff/buff
            -- can be evaluated against IsAuraFilteredOutByInstanceID.
            hasRelevantChange = true
        end
        if not hasRelevantChange and updateInfo.removedAuraInstanceIDs then
            for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
                if self._shownAuras[id] then
                    hasRelevantChange = true
                    break
                end
            end
        end
        if not hasRelevantChange and updateInfo.updatedAuraInstanceIDs then
            for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if self._shownAuras[id] then
                    hasRelevantChange = true
                    break
                end
            end
        end
        if not hasRelevantChange then
            return
        end
    end

    if not self._shownAuras then
        self._shownAuras = {}
    else
        wipe(self._shownAuras)
    end

    for i = 1, 4 do
        local dSlot = self.debuffs[i]
        local bSlot = self.buffs[i]
        dSlot:Hide()
        if dSlot.pandemicGlow and dSlot.pandemicGlow.active then
            ns.StopPandemicGlow(dSlot)
        end
        dSlot._durationObj = nil
        bSlot:Hide()
        local dCd = dSlot.cd
        if dCd then
            if dCd.Clear then dCd:Clear()
            elseif CooldownFrame_Clear then CooldownFrame_Clear(dCd)
            else dCd:SetCooldown(0, 0) end
        end
        local bCd = bSlot.cd
        if bCd then
            if bCd.Clear then bCd:Clear()
            elseif CooldownFrame_Clear then CooldownFrame_Clear(bCd)
            else bCd:SetCooldown(0, 0) end
        end
    end
    for i = 1, 2 do
        local ccSlot = self.cc[i]
        ccSlot:Hide()
        local cCd = ccSlot.cd
        if cCd then
            if cCd.Clear then cCd:Clear()
            elseif CooldownFrame_Clear then CooldownFrame_Clear(cCd)
            else cCd:SetCooldown(0, 0) end
        end
    end
    -- Get slot assignments; skip processing for any slot set to "none"
    local debuffSlotVal, buffSlotVal, ccSlotVal = GetAuraSlots()
    local dIdx = 1
    local db = EllesmereUINameplatesDB
    if debuffSlotVal ~= "none" then
    local showAll = db and db.showAllDebuffs
    -- Build the "important" set from Blizzard's own nameplate debuff list.
    -- Our UNIT_AURA handler defers via C_Timer.After(0) so Blizzard's
    -- UnitFrame has already processed the event and debuffList is current.
    local importantSet
    if not showAll and self.nameplate then
        importantSet = {}
        local uf = self.nameplate.UnitFrame
        if uf and uf.AurasFrame and uf.AurasFrame.debuffList and uf.AurasFrame.debuffList.Iterate then
            uf.AurasFrame.debuffList:Iterate(function(auraInstanceID)
                importantSet[auraInstanceID] = true
            end)
        end
    end
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local allDebuffs = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|PLAYER")
        if allDebuffs then
            local GetCount = C_UnitAuras.GetAuraApplicationDisplayCount
            local GetDur = C_UnitAuras.GetAuraDuration
            for _, aura in ipairs(allDebuffs) do
                if dIdx > 4 then break end
                local id = aura and aura.auraInstanceID
                if id and (showAll or (importantSet and importantSet[id])) then
                        local slot = self.debuffs[dIdx]
                        slot.icon:SetTexture(aura.icon)
                        if GetCount then
                            slot.count:SetText(GetCount(unit, id, 2, 1000) or "")
                        end
                        local cd = slot.cd
                        if cd and GetDur then
                            local durObj = GetDur(unit, id)
                            if durObj and cd.SetCooldownFromDurationObject then
                                cd:SetCooldownFromDurationObject(durObj)
                                cd:Show()
                            end
                            slot._durationObj = durObj
                        else
                            slot._durationObj = nil
                        end
                        slot:Show()
                        self._shownAuras[id] = true
                        dIdx = dIdx + 1
                end
            end
        end
    end
    local debuffCount = dIdx - 1
    if debuffCount > 0 then
        local spacing = GetAuraSpacing()
        local debuffSz = GetDebuffIconSize()
        for i = 1, debuffCount do
            PP.Size(self.debuffs[i], debuffSz, debuffSz)
        end
        PositionAuraSlot(self.debuffs, debuffCount, debuffSlotVal, self, debuffSz, debuffSz, spacing, GetAuraSlotOffsets("debuffSlot"))
    end
    -- Pandemic glow check for debuffs
    local pandemicEnabled = GetPandemicGlow()
    for i = 1, 4 do
        local slot = self.debuffs[i]
        local pg = slot.pandemicGlow
        if i <= (dIdx - 1) and pandemicEnabled then
            ns.ApplyPandemicGlow(slot)
        else
            if pg and pg.active then
                ns.StopPandemicGlow(slot)
            end
        end
    end
    end -- debuffSlotVal ~= "none"
    if buffSlotVal ~= "none" then
    if UnitCanAttack("player", unit) and C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local allBuffs = C_UnitAuras.GetUnitAuras(unit, "HELPFUL|INCLUDE_NAME_PLATE_ONLY")
        local bIdx = 1
        if allBuffs then
            local GetCount = C_UnitAuras.GetAuraApplicationDisplayCount
            local GetDur = C_UnitAuras.GetAuraDuration
            for _, aura in ipairs(allBuffs) do
                if bIdx > 4 then break end
                local id = aura and aura.auraInstanceID
                if id and type(aura.dispelName) ~= "nil" then
                    local slot = self.buffs[bIdx]
                    slot.icon:SetTexture(aura.icon)
                    if GetCount then
                        slot.count:SetText(GetCount(unit, id, 2, 1000) or "")
                    end
                    local cd = slot.cd
                    if cd and GetDur then
                        local durObj = GetDur(unit, id)
                        if durObj and cd.SetCooldownFromDurationObject then
                            cd:SetCooldownFromDurationObject(durObj)
                            cd:Show()
                        end
                    end
                    slot:Show()
                    self._shownAuras[id] = true
                    bIdx = bIdx + 1
                end
            end
        end
    end
    end -- buffSlotVal ~= "none"
    local ccShown = 0
    if ccSlotVal ~= "none" then
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local ccAuras = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|CROWD_CONTROL")
        if ccAuras then
            local GetDur = C_UnitAuras.GetAuraDuration
            for _, aura in ipairs(ccAuras) do
                if ccShown >= 2 then break end
                if aura and aura.auraInstanceID then
                    ccShown = ccShown + 1
                    local slot = self.cc[ccShown]
                    slot.icon:SetTexture(aura.icon)
                    slot.icon:Show()
                    local cd = slot.cd
                    if cd and GetDur then
                        local durObj = GetDur(unit, aura.auraInstanceID)
                        if durObj and cd.SetCooldownFromDurationObject then
                            cd:SetCooldownFromDurationObject(durObj)
                            cd:Show()
                        end
                    end
                    slot:Show()
                    self._shownAuras[aura.auraInstanceID] = true
                end
            end
        end
    end
    end -- ccSlotVal ~= "none"
    -- Reposition buffs and CC based on actual shown counts (important when in "top" slot for centering)
    if buffSlotVal ~= "none" then
        local buffCount = 0
        for i = 1, 4 do if self.buffs[i]:IsShown() then buffCount = buffCount + 1 end end
        if buffCount > 0 then
            local spacing = GetAuraSpacing()
            local buffSz = GetBuffIconSize()
            PositionAuraSlot(self.buffs, buffCount, buffSlotVal, self, buffSz, buffSz, spacing, GetAuraSlotOffsets("buffSlot"))
        end
    end
    if ccSlotVal ~= "none" and ccShown > 0 then
        local spacing = GetAuraSpacing()
        local ccSz = GetCCIconSize()
        PositionAuraSlot(self.cc, ccShown, ccSlotVal, self, ccSz, ccSz, spacing, GetAuraSlotOffsets("ccSlot"))
    end
    -- Reposition target arrows outside the outermost side auras
    PositionArrowsOutsideAuras(self)
end
function NameplateFrame:UpdateCast()
    if not self.unit then
        self.cast:Hide()
        return
    end
    local name, _, texture, _, _, _, _, kickProtected = UnitCastingInfo(self.unit)
    local isChannel = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected = UnitChannelInfo(self.unit)
        isChannel = true
    end
    if type(name) == "nil" then
        if not self._interrupted then
            self.cast:Hide()
        end
        if self.isCasting then
            if self._castFallback then
                self._castFallback = nil
                fallbackCastCount = fallbackCastCount - 1
                if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
            end
            NotifyCastEnded()
        end
        self.isCasting = false
        self:HideKickTick()
        self:ApplyCastScale()
        -- Reposition class power pips (cast bar gone, pips move back to health bar)
        if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
            UpdateClassPowerOnPlate(self)
        end
        return
    end

    if self._interrupted then
        self._interrupted = nil
        if self._interruptTimer then
            self._interruptTimer:Cancel()
            self._interruptTimer = nil
        end
    end

    self.cast:Show()
    if type(texture) ~= "nil" then
        self.castIcon:SetTexture(texture)
    end
    self.castName:SetText(type(name) ~= "nil" and name or "")
    
    local spellTarget
    local spellTargetClass
    if UnitSpellTargetName then
        spellTarget = UnitSpellTargetName(self.unit)
        if UnitSpellTargetClass then
            spellTargetClass = UnitSpellTargetClass(self.unit)
        end
    end
    if type(spellTarget) == "nil" then
        spellTarget = UnitName(self.unit .. "target")
        spellTargetClass = UnitClassBase(self.unit .. "target")
    end
    self.castTarget:SetText(type(spellTarget) ~= "nil" and spellTarget or "")

    -- Apply class color to cast target text if enabled and target is a player
    local db = EllesmereUINameplatesDB or defaults
    local useClassColor = defaults.castTargetClassColor
    if db.castTargetClassColor ~= nil then useClassColor = db.castTargetClassColor end
    if useClassColor then
        local appliedCTC = false
        if spellTargetClass then
            local okC, c = pcall(function() return RAID_CLASS_COLORS and RAID_CLASS_COLORS[spellTargetClass] end)
            if okC and c then
                self.castTarget:SetTextColor(c.r, c.g, c.b, 1)
                appliedCTC = true
            end
        end
        if not appliedCTC then
            self.castTarget:SetTextColor(1, 1, 1, 1)
        end
    else
        local ctc = (db and db.castTargetColor) or defaults.castTargetColor
        self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
    end

    -- Two-point anchor: castName stretches from LEFT+5 to 5px before castTarget's left edge
    -- This avoids GetStringWidth() which returns tainted secret values on nameplates
    self.castName:SetWidth(0)  -- clear any fixed width
    self.castName:ClearAllPoints()
    self.castName:SetPoint("LEFT", self.cast, "LEFT", 5, 0)
    self.castName:SetPoint("RIGHT", self.castTarget, "LEFT", -5, 0)

    if type(kickProtected) == "nil" then
        kickProtected = false
    end
    self._kickProtected = kickProtected
    local cfg = EllesmereUINameplatesDB or defaults
    local unintColor = cfg.castBarUninterruptible or defaults.castBarUninterruptible
    self.castBarOverlay:SetVertexColor(unintColor.r, unintColor.g, unintColor.b)
    self.castShieldFrame:Show()
    self:ApplyCastColor(kickProtected)
    
    if UnitCastingDuration and self.cast.SetTimerDuration then
        if isChannel then
            local castDuration = UnitChannelDuration(self.unit)
            if castDuration then
                self.cast:SetReverseFill(false)
                self.cast:SetTimerDuration(castDuration, nil, Enum.StatusBarTimerDirection.RemainingTime)
                if not self.isCasting then NotifyCastStarted() end
                self.isCasting = true
            end
        else
            local castDuration = UnitCastingDuration(self.unit)
            if castDuration then
                self.cast:SetReverseFill(false)
                self.cast:SetTimerDuration(castDuration, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            end
            if not self.isCasting then NotifyCastStarted() end
            self.isCasting = true
        end
    else
        if not self.isCasting then
            self.isCasting = true
            self._castFallback = true
            fallbackCastCount = fallbackCastCount + 1
            castFallbackFrame:Show()
            NotifyCastStarted()
        end
    end
    self:ApplyCastScale()
    self:UpdateKickTick(kickProtected, isChannel)
    -- Reposition class power pips (cast bar now visible, pips move below it)
    if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
        UpdateClassPowerOnPlate(self)
    end
end
function NameplateFrame:ApplyCastScale()
    local s = GetCastScale() / 100
    if self.isCasting and s ~= 1 then
        self:SetScale(s)
    else
        self:SetScale(1)
    end
end
function NameplateFrame:ApplyCastColor(uninterruptible)
    local cfg = EllesmereUINameplatesDB or defaults
    local kickReadyTint = cfg.interruptReady or defaults.interruptReady
    local normalCastTint = cfg.castBar or defaults.castBar
    local cr, cg, cb = ComputeCastBarTint(kickReadyTint, normalCastTint)
    self.cast:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
    if self.castBarOverlay.SetAlphaFromBoolean then
        self.castBarOverlay:SetAlphaFromBoolean(uninterruptible)
        self.castShieldFrame:SetAlphaFromBoolean(uninterruptible)
    else
        local a = uninterruptible and 1 or 0
        self.castBarOverlay:SetAlpha(a)
        self.castShieldFrame:SetAlpha(a)
    end
end
function NameplateFrame:HideKickTick()
    self.kickPositioner:Hide()
    self.kickMarker:Hide()
    if self._kickTicker then
        self._kickTicker:Cancel()
        self._kickTicker = nil
    end
end
function NameplateFrame:UpdateKickTick(kickProtected, isChannel)
    if not GetKickTickEnabled() or not activeKickSpell then
        self:HideKickTick()
        return
    end
    -- kickProtected is a secret boolean on Midnight â€” cannot branch on it.
    -- Store it so we can apply visibility via SetAlphaFromBoolean after setup.
    self._kickProtected = kickProtected
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    -- Midnight path: use secret duration objects
    if UnitCastingDuration and self.cast.SetTimerDuration then
        local castDuration = isChannel and UnitChannelDuration(self.unit) or UnitCastingDuration(self.unit)
        if not castDuration then
            self:HideKickTick()
            return
        end
        local totalDur = castDuration:GetTotalDuration()
        local interruptCD = C_Spell.GetSpellCooldownDuration(activeKickSpell)
        if not interruptCD then
            self:HideKickTick()
            return
        end
        -- Size the StatusBars to match the cast bar (positioner uses SetPoint("CENTER"), not SetAllPoints)
        local castH = GetCastBarHeight()
        local barW = self.cast:GetWidth()
        self.kickPositioner:SetSize(barW, castH)
        self.kickPositioner:SetMinMaxValues(0, totalDur)
        self.kickMarker:SetMinMaxValues(0, totalDur)
        self.kickMarker:SetSize(barW, castH)
        -- Both values set ONCE at cast start, never updated in ticker.
        -- (positioner is a static snapshot of elapsed time,
        -- marker's secret duration naturally counts down via the engine.)
        self.kickPositioner:SetValue(castDuration:GetElapsedDuration())
        self.kickMarker:SetValue(interruptCD:GetRemainingDuration())
        -- Apply color
        local kr, kg, kb = GetKickTickColor()
        self.kickTick:SetColorTexture(kr, kg, kb, 1)
        -- Handle channel vs cast fill direction
        if isChannel then
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("RIGHT", self.kickPositioner:GetStatusBarTexture(), "LEFT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("RIGHT", self.kickMarker:GetStatusBarTexture(), "LEFT")
        else
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("LEFT", self.kickPositioner:GetStatusBarTexture(), "RIGHT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
        end
        self.kickPositioner:Show()
        self.kickMarker:Show()
        -- Compute initial tick alpha immediately (avoids split-second delay
        -- from waiting for the first ticker fire at 0.1s).
        if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
            local kickReady = interruptCD:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            self.kickTick:SetAlpha(alpha)
        else
            self.kickTick:SetAlpha(0)
        end
        -- Ticker: only updates tick alpha at 10fps.
        -- Neither positioner nor marker values are updated â€” both are set once
        -- at cast start and left alone.  The marker's
        -- secret duration naturally counts down via the engine, moving the
        -- tick mark as the kick CD expires.
        if self._kickTicker then self._kickTicker:Cancel() end
        self._kickTicker = C_Timer.NewTicker(0.1, function()
            if not self.isCasting or not self.unit then
                self:HideKickTick()
                return
            end
            -- Compute tick visibility: show only when kick is on CD AND cast is interruptible.
            -- Both are secret booleans â€” chain EvaluateColorValueFromBoolean calls
            -- to combine conditions into a single secret alpha.
            local icd = C_Spell.GetSpellCooldownDuration(activeKickSpell)
            if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
                local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
                local kickReady = icd:IsZero()
                local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
                self.kickTick:SetAlpha(alpha)
            end
        end)
    else
        -- Legacy path (non-Midnight): use GetTime() math
        -- Not implementing legacy path since user is on Midnight
        self:HideKickTick()
    end
end
function NameplateFrame:ShowInterrupted(interrupterGUID)
    if self.isCasting then
        if self._castFallback then
            self._castFallback = nil
            fallbackCastCount = fallbackCastCount - 1
            if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded()
    end
    self.isCasting = false
    self:HideKickTick()
    self:ApplyCastScale()

    self._interrupted = true
    self.cast:SetReverseFill(false)
    self.cast:SetMinMaxValues(0, 1)
    self.cast:SetValue(1)
    self.cast:GetStatusBarTexture():SetVertexColor(0.8, 0.0, 0.0)
    self.castName:SetText("Interrupted")

    -- Show interrupter name (class-colored) in cast target position
    local interrupterName
    local interrupterClass
    if interrupterGUID then
        if UnitNameFromGUID then
            interrupterName = UnitNameFromGUID(interrupterGUID)
            local _, class = GetPlayerInfoByGUID(interrupterGUID)
            interrupterClass = class
        else
            local unitToken = UnitTokenFromGUID(interrupterGUID)
            if unitToken then
                interrupterName = UnitName(unitToken)
                interrupterClass = UnitClassBase(unitToken)
            end
        end
    end
    if interrupterName then
        self.castTarget:SetText(interrupterName)
        local cfg = EllesmereUINameplatesDB or defaults
        local useClassColor = defaults.castTargetClassColor
        if cfg.castTargetClassColor ~= nil then useClassColor = cfg.castTargetClassColor end
        if useClassColor then
            if interrupterClass and C_ClassColor then
                local c = C_ClassColor.GetClassColor(interrupterClass)
                if c then
                    self.castTarget:SetTextColor(c:GetRGB())
                else
                    self.castTarget:SetTextColor(1, 1, 1, 1)
                end
            else
                self.castTarget:SetTextColor(1, 1, 1, 1)
            end
        else
            local ctc = (cfg and cfg.castTargetColor) or defaults.castTargetColor
            self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
        end
    else
        self.castTarget:SetText("")
    end

    self.castName:SetWidth(0)
    self.castName:ClearAllPoints()
    self.castName:SetPoint("LEFT", self.cast, "LEFT", 5, 0)
    self.castName:SetPoint("RIGHT", self.castTarget, "LEFT", -5, 0)
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.cast:Show()

    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end

    self._interruptTimer = C_Timer.NewTimer(1.0, function()
        if self._interrupted then
            self._interrupted = nil
            self._interruptTimer = nil
            self.cast:Hide()
        end
    end)
end
function NameplateFrame:UNIT_HEALTH()
    self:UpdateHealthValues()
end
function NameplateFrame:UNIT_ABSORB_AMOUNT_CHANGED()
    self:UpdateHealthValues()
end
function NameplateFrame:UNIT_AURA(_, updateInfo)
    -- Defer aura updates by one frame so Blizzard's UnitFrame has time to
    -- process the same UNIT_AURA event and update its debuffList.  This
    -- prevents a race where our handler runs first and the newly added
    -- aura isn't in the "important" set yet.
    if self._auraDeferTimer then
        self._auraDeferTimer:Cancel()
    end
    local plate = self
    local info = updateInfo
    self._auraDeferTimer = C_Timer.NewTimer(0, function()
        plate._auraDeferTimer = nil
        plate:UpdateAuras(info)
    end)
end
function NameplateFrame:UNIT_NAME_UPDATE()
    self:UpdateName()
end
function NameplateFrame:LOSS_OF_CONTROL_UPDATE()
    self:UpdateAuras()
end
function NameplateFrame:LOSS_OF_CONTROL_ADDED()
    self:UpdateAuras()
end
function NameplateFrame:UNIT_THREAT_LIST_UPDATE()
    self:UpdateHealthColor()
end
function NameplateFrame:UNIT_FLAGS()
    self:UpdateHealthColor()
end
function NameplateFrame:UNIT_SPELLCAST_START()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_START()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_DELAYED()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_UPDATE()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_STOP()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_STOP()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_FAILED()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTED(_, _, _, interrupterGUID)
    self:ShowInterrupted(interrupterGUID)
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTIBLE()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_NOT_INTERRUPTIBLE()
    self:UpdateCast()
end
local manager = CreateFrame("Frame")
manager:RegisterEvent("NAME_PLATE_UNIT_ADDED")
manager:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
manager:RegisterEvent("PLAYER_TARGET_CHANGED")
manager:RegisterEvent("PLAYER_FOCUS_CHANGED")
manager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
manager:RegisterEvent("RAID_TARGET_UPDATE")
manager:RegisterEvent("PLAYER_REGEN_DISABLED")
manager:RegisterEvent("PLAYER_REGEN_ENABLED")
manager:RegisterEvent("DISPLAY_SIZE_CHANGED")
manager:RegisterEvent("UI_SCALE_CHANGED")

local pendingUnits = {}
ns.pendingUnits = pendingUnits
local currentMouseoverPlate = nil
local mouseoverTicker = nil

-- Per-unit event watchers for pending friendly units.
-- Using per-unit frames avoids the global UNIT_FLAGS firehose.
local pendingWatchers = {}
-- Forward declarations so the two watcher creators can reference each other
local CreatePendingWatcher, CreateEnemyWatcher

-- Watches a friendly/pending unit for becoming attackable (e.g. duel start)
local enemyWatchers = {}
CreatePendingWatcher = function(unit, nameplate)
    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_FLAGS", unit)
    watcher:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    watcher:SetScript("OnEvent", function(self, event, u)
        if not UnitCanAttack("player", u) then return end
        -- Unit became attackable â€” promote to enemy plate
        self:UnregisterAllEvents()
        pendingWatchers[u] = nil
        pendingUnits[u] = nil
        -- Remove friendly plate WITHOUT restoring Blizzard UF (we'll suppress it as enemy)
        if ns.RemoveFriendlyPlateNoRestore then
            ns.RemoveFriendlyPlateNoRestore(u)
        elseif ns.RemoveFriendlyPlate then
            ns.RemoveFriendlyPlate(u)
        end
        local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
        if currentPlate then
            local plate = frameCache:Acquire()
            if not plate._mixedIn then
                Mixin(plate, NameplateFrame)
                plate._mixedIn = true
            end
            ns.plates[u] = plate
            plate:SetUnit(u, currentPlate)
        end
        -- Watch for the reverse transition (enemy â†’ friendly, e.g. duel end)
        enemyWatchers[u] = CreateEnemyWatcher(u)
    end)
    return watcher
end

-- Watches a promoted-enemy unit for becoming friendly again (e.g. duel end)
CreateEnemyWatcher = function(unit)
    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_FLAGS", unit)
    watcher:SetScript("OnEvent", function(self, event, u)
        if UnitCanAttack("player", u) then return end
        -- Unit became friendly again â€” tear down enemy plate, restore to pending
        self:UnregisterAllEvents()
        enemyWatchers[u] = nil
        local plate = ns.plates[u]
        if plate then
            if currentMouseoverPlate == plate then
                currentMouseoverPlate = nil
                if mouseoverTicker then
                    mouseoverTicker:Cancel()
                    mouseoverTicker = nil
                end
            end
            plate:ClearUnit()
            frameCache:Release(plate)
            ns.plates[u] = nil
        end
        -- Re-add as pending friendly
        local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
        if currentPlate then
            pendingUnits[u] = currentPlate
            pendingWatchers[u] = CreatePendingWatcher(u, currentPlate)
            if ns.TryAddFriendlyPlate then ns.TryAddFriendlyPlate(u) end
        end
    end)
    return watcher
end

-- Single shared UNIT_FACTION handler â€” avoids N watchers each registering
-- the global event.  Dispatches to the correct watcher's OnEvent handler.
-- Only active in the open world (duels can't happen in instanced content).
local factionFrame = CreateFrame("Frame")
local factionFrameActive = false

local function UpdateFactionFrameForZone()
    local _, instanceType = IsInInstance()
    local shouldBeActive = (instanceType == "none" or instanceType == nil)
    if shouldBeActive and not factionFrameActive then
        factionFrame:RegisterEvent("UNIT_FACTION")
        factionFrameActive = true
    elseif not shouldBeActive and factionFrameActive then
        factionFrame:UnregisterEvent("UNIT_FACTION")
        factionFrameActive = false
    end
end

factionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
factionFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        UpdateFactionFrameForZone()
        return
    end
    -- UNIT_FACTION dispatch
    if pendingWatchers[unit] then
        local w = pendingWatchers[unit]
        w:GetScript("OnEvent")(w, "UNIT_FACTION", unit)
    elseif enemyWatchers[unit] then
        local w = enemyWatchers[unit]
        w:GetScript("OnEvent")(w, "UNIT_FACTION", unit)
    end
end)
local function UpdateMouseover()
    if currentMouseoverPlate then
        currentMouseoverPlate.highlight:Hide()
        currentMouseoverPlate = nil
    end
    if UnitExists("mouseover") then
        for _, plate in pairs(ns.plates) do
            if plate.unit and UnitIsUnit(plate.unit, "mouseover") then
                plate.highlight:Show()
                currentMouseoverPlate = plate
                break
            end
        end
        if not mouseoverTicker then
            mouseoverTicker = C_Timer.NewTicker(0.1, function()
                if not UnitExists("mouseover") then
                    if mouseoverTicker then
                        mouseoverTicker:Cancel()
                        mouseoverTicker = nil
                    end
                    UpdateMouseover()
                end
            end)
        end
    end
end
-- Refresh Y-offset on all visible friendly name-only plates
function ns.RefreshFriendlyNameOnlyOffset()
    local db = EllesmereUINameplatesDB or defaults
    local nameOnly = (db.friendlyNameOnly ~= false)
    local yOff = nameOnly and (db.friendlyNameOnlyYOffset or 0) or 0
    for unit, nameplate in pairs(pendingUnits) do
        if nameplate.UnitFrame then
            local uf = nameplate.UnitFrame
            if yOff ~= 0 then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                nameplate._enoYOffset = true
            elseif nameplate._enoYOffset then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, 0)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
                nameplate._enoYOffset = nil
            end
        end
    end
end

manager:SetScript("OnEvent", function(self, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if not nameplate then return end
        if not UnitCanAttack("player", unit) then
            pendingUnits[unit] = nameplate
            pendingWatchers[unit] = CreatePendingWatcher(unit, nameplate)
            if ns.TryAddFriendlyPlate then ns.TryAddFriendlyPlate(unit) end
            -- Color NPC names green in name-only mode
            if ns.TryColorFriendlyNPCName then ns.TryColorFriendlyNPCName(unit, nameplate) end
            -- Hide NPC health bars in name-only mode (show name only)
            if ns.TrySuppressNPCHealthBar then ns.TrySuppressNPCHealthBar(unit, nameplate) end
            -- Ensure the Blizzard UF is visible for name-only friendly plates.
            -- Nameplate frames are recycled â€” a UF previously used for an enemy
            -- may still have alpha 0 or children parented offscreen.
            local db = EllesmereUINameplatesDB or defaults
            if db.friendlyNameOnly ~= false then
                local uf = nameplate.UnitFrame
                if uf then
                    -- Restore alpha in case the recycled UF was suppressed
                    if uf:GetAlpha() < 0.01 then
                        uf:SetAlpha(1)
                    end
                    -- Restore name FontString if it was moved offscreen
                    if uf.name and uf.name:GetParent() ~= uf then
                        uf.name:SetParent(uf)
                    end
                    -- Ensure UF is parented to the nameplate (not hidden frame)
                    if uf:GetParent() ~= nameplate then
                        uf:SetParent(nameplate)
                        uf:SetAlpha(1)
                        uf:Show()
                    end
                end
                -- Apply Y-offset
                local yOff = db.friendlyNameOnlyYOffset or 0
                if yOff ~= 0 and nameplate.UnitFrame then
                    nameplate.UnitFrame:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                    nameplate.UnitFrame:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                    nameplate._enoYOffset = true
                end
                -- Font is applied globally via SystemFont_NamePlate override
            end
            return
        end
        pendingUnits[unit] = nil
        local plate = frameCache:Acquire()
        if not plate._mixedIn then
            Mixin(plate, NameplateFrame)
            plate._mixedIn = true
        end
        ns.plates[unit] = plate
        plate:SetUnit(unit, nameplate)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        questMobCache[unit] = nil
        -- Restore Blizzard UnitFrame elements so the recycled nameplate is clean
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate then
            RestoreBlizzardFrame(nameplate)
        end
        -- Restore NPC name color if we tinted it
        if nameplate and ns.RestoreFriendlyNPCNameColor then
            ns.RestoreFriendlyNPCNameColor(nameplate)
        end
        -- Restore NPC health bar if we suppressed it
        if nameplate and ns.RestoreNPCHealthBar then
            ns.RestoreNPCHealthBar(nameplate)
        end
        -- Restore name-only Y-offset if we applied one
        if nameplate and nameplate._enoYOffset then
            local uf = nameplate.UnitFrame
            if uf then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, 0)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
            end
            nameplate._enoYOffset = nil
        end
        pendingUnits[unit] = nil
        if pendingWatchers[unit] then
            pendingWatchers[unit]:UnregisterAllEvents()
            pendingWatchers[unit] = nil
        end
        if enemyWatchers[unit] then
            enemyWatchers[unit]:UnregisterAllEvents()
            enemyWatchers[unit] = nil
        end
        local plate = ns.plates[unit]
        if plate then
            if currentMouseoverPlate == plate then
                currentMouseoverPlate = nil
                if mouseoverTicker then
                    mouseoverTicker:Cancel()
                    mouseoverTicker = nil
                end
            end
            plate:ClearUnit()
            frameCache:Release(plate)
            ns.plates[unit] = nil
        end
        if ns.RemoveFriendlyPlate then ns.RemoveFriendlyPlate(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        for _, plate in pairs(ns.plates) do
            plate:ApplyTarget()
        end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        local focusPct = GetFocusCastHeight()
        for _, plate in pairs(ns.plates) do
            plate:UpdateHealthColor()
            -- Refresh cast bar height for focus multiplier (old + new focus)
            if focusPct ~= 100 then
                local castH = GetCastBarHeight()
                if plate.unit and UnitIsUnit(plate.unit, "focus") then
                    castH = math.floor(castH * focusPct / 100 + 0.5)
                end
                plate.cast:SetHeight(castH)
                plate.castIconFrame:SetSize(castH, castH)
                plate.castSpark:SetHeight(castH)
                plate.kickMarker:SetHeight(castH)
            end
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        UpdateMouseover()
    elseif event == "RAID_TARGET_UPDATE" then
        for _, plate in pairs(ns.plates) do
            plate:UpdateRaidIcon()
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        for _, plate in pairs(ns.plates) do
            plate:UpdateHealthColor()
        end
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        if ns.ApplyNamePlateClickArea then
            ns.ApplyNamePlateClickArea()
        end
    end
end)

-------------------------------------------------------------------------------
--  SPEC PRESET LOGIN HANDLER
--  Applies the correct spec-assigned preset on login and on spec change,
--  even before the options UI is ever opened.  Once the UI opens and
--  RegisterSpecAutoSwitch is called, the framework handler takes over for
--  PLAYER_SPECIALIZATION_CHANGED; this early handler ensures the first
--  login is covered.
-------------------------------------------------------------------------------
do
    local function ApplySpecPresetFromDB()
        local db = EllesmereUINameplatesDB
        if not db then return end

        local specIndex = GetSpecialization and GetSpecialization() or 0
        local specID = specIndex and specIndex > 0
                       and GetSpecializationInfo(specIndex) or nil
        if not specID then return end

        local K_ASSIGN  = "_specAssignments"
        local K_ACTIVE  = "_activePreset"
        local K_DEFAULT = "_specDefaultPreset"
        local K_PRESETS = "_presets"
        local K_SNAP    = "_builtinSnapshot"
        local K_CUSTOM  = "_customPreset"

        local specMap = db[K_ASSIGN]
        if not specMap then return end

        -- Check if any spec assignment exists at all
        local hasAny = false
        for _, specList in pairs(specMap) do
            if next(specList) then hasAny = true; break end
        end
        if not hasAny then return end

        -- Find which preset owns this specID
        local targetKey
        for presetKey, specList in pairs(specMap) do
            if specList[specID] then targetKey = presetKey; break end
        end
        -- Fall back to default preset if no direct match
        if not targetKey and db[K_DEFAULT] then
            targetKey = db[K_DEFAULT]
        end
        if not targetKey then return end

        local currentActive = db[K_ACTIVE] or "ellesmereui"
        if currentActive == targetKey then return end  -- already correct

        -- Apply the snapshot for targetKey
        local presetKeys = ns._displayPresetKeys  -- set below
        if not presetKeys then return end

        if targetKey == "ellesmereui" then
            for _, key in ipairs(presetKeys) do
                local def = ns.defaults[key]
                if type(def) == "table" and def.r then
                    db[key] = { r = def.r, g = def.g, b = def.b }
                else
                    db[key] = def
                end
            end
            db[K_SNAP] = nil
        elseif targetKey == "custom" then
            if db[K_CUSTOM] then
                for _, key in ipairs(presetKeys) do
                    local v = db[K_CUSTOM][key]
                    if v ~= nil then
                        if type(v) == "table" and v.r then
                            db[key] = { r = v.r, g = v.g, b = v.b }
                        else
                            db[key] = v
                        end
                    end
                end
            end
        elseif targetKey:sub(1, 5) == "user:" then
            local name = targetKey:sub(6)
            local snap = db[K_PRESETS] and db[K_PRESETS][name]
            if snap then
                for _, key in ipairs(presetKeys) do
                    local v = snap[key]
                    if v ~= nil then
                        if type(v) == "table" and v.r then
                            db[key] = { r = v.r, g = v.g, b = v.b }
                        else
                            db[key] = v
                        end
                    end
                end
            end
        end

        db[K_ACTIVE] = targetKey
        db[K_SNAP] = nil
    end

    -- Store preset keys so the login handler can use them (set once, never changes)
    ns._displayPresetKeys = {
        "borderStyle", "borderColor", "targetGlowStyle", "showTargetArrows",
        "showClassPower", "classPowerPos", "classPowerYOffset", "classPowerXOffset", "classPowerScale",
        "classPowerClassColors", "classPowerCustomColor", "classPowerGap",
        "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter",
        "nameYOffset",
        "healthBarHeight", "healthBarWidth", "castBarHeight",
        "castNameSize", "castNameColor", "castTargetSize", "castTargetClassColor", "castTargetColor",
        "debuffSlot", "buffSlot", "ccSlot",
        "debuffYOffset", "sideAuraXOffset", "auraSpacing",
        "debuffTimerPosition", "buffTimerPosition", "ccTimerPosition",
        "auraDurationTextSize", "auraDurationTextColor",
        "auraStackTextSize", "auraStackTextColor",
        "buffTextSize", "buffTextColor", "ccTextSize", "ccTextColor",
        "raidMarkerPos",
        "classificationSlot",
        -- Slot-based size + XY offsets
        "topSlotSize", "topSlotXOffset", "topSlotYOffset",
        "rightSlotSize", "rightSlotXOffset", "rightSlotYOffset",
        "leftSlotSize", "leftSlotXOffset", "leftSlotYOffset",
        "toprightSlotSize", "toprightSlotXOffset", "toprightSlotYOffset", "toprightSlotGrowth",
        "topleftSlotSize", "topleftSlotXOffset", "topleftSlotYOffset", "topleftSlotGrowth",
        -- Text slot size + XY offsets
        "textSlotTopSize", "textSlotTopXOffset", "textSlotTopYOffset",
        "textSlotRightSize", "textSlotRightXOffset", "textSlotRightYOffset",
        "textSlotLeftSize", "textSlotLeftXOffset", "textSlotLeftYOffset",
        "textSlotCenterSize", "textSlotCenterXOffset", "textSlotCenterYOffset",
        -- Text slot color keys
        "textSlotTopColor", "textSlotRightColor", "textSlotLeftColor", "textSlotCenterColor",
    }

    -- Also handle spec changes that happen before the UI is ever opened
    local specLoginFrame = CreateFrame("Frame")
    specLoginFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specLoginFrame:SetScript("OnEvent", function(_, event, unit)
        if unit ~= "player" then return end
        -- If the framework handler is registered, let it handle this
        if EllesmereUI and EllesmereUI._specSwitchRegistry
           and #EllesmereUI._specSwitchRegistry > 0 then
            return
        end
        ApplySpecPresetFromDB()
        if ns.RefreshAllSettings then ns.RefreshAllSettings() end
    end)

    -- Expose for calling from OnEnable (login time)
    ns._ApplySpecPresetFromDB = ApplySpecPresetFromDB
end

local npAddon = EllesmereUI.Lite.NewAddon("EllesmereUINameplatesInit")
function npAddon:OnInitialize()
    InitDB()
end
function npAddon:OnEnable()
    SetupAuraCVars()
    ApplyClassPowerSetting()
    -- Apply spec-assigned preset on login (before UI is opened)
    if ns._ApplySpecPresetFromDB then ns._ApplySpecPresetFromDB() end
end

