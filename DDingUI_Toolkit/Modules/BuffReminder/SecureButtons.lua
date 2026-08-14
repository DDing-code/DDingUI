--[[
    DDingToolKit - BuffReminder: SecureButtons
    Click-to-cast overlays, consumable action buttons, and secure frame sync.
    Ported from BuffReminders/Display/SecureButtons.lua by zerbi.
]]

local _, ns = ...

local floor, max, min = math.floor, math.max, math.min
local tsort = table.sort
local _, playerClass = UnitClass("player")

local SecureButtons = {}
ns.SecureButtons = SecureButtons

-- ============================================================================
-- SPELL HELPERS
-- ============================================================================

local function GetCastableSpellID(spellIDs)
    if spellIDs == nil then return nil end
    if type(spellIDs) ~= "table" then
        return IsPlayerSpell(spellIDs) and spellIDs or nil
    end
    for _, id in ipairs(spellIDs) do
        if IsPlayerSpell(id) then return id end
    end
    return nil
end

local FEL_DOMINATION_ID = 333889

local function GetFelDomPetMacro(petSpellID)
    local felDomName = C_Spell.GetSpellName(FEL_DOMINATION_ID)
    local spellName = C_Spell.GetSpellName(petSpellID)
    if not felDomName or not spellName then return nil end
    return "/cast " .. felDomName .. "\n/cast " .. spellName
end

local function GetActionSpellID(buff)
    if not buff then return nil end
    if buff.excludeSpellID and IsPlayerSpell(buff.excludeSpellID) then return nil end
    if buff.requiresSpellID and not IsPlayerSpell(buff.requiresSpellID) then return nil end
    if buff.requireSpecId then
        local spec = GetSpecialization()
        if spec then
            local specId = GetSpecializationInfo(spec)
            if specId ~= buff.requireSpecId then return nil end
        end
    end
    if not buff.castSpellID and buff.iconByRole then
        local role = ns.BuffState and ns.BuffState.GetPlayerRole()
        local roleSpell = role and buff.iconByRole[role]
        if roleSpell and IsPlayerSpell(roleSpell) then return roleSpell end
    end
    return GetCastableSpellID(buff.castSpellID or buff.spellID)
end

local function ResolveCustomClickAction(buff)
    if not buff then return nil, nil end
    if buff.castMacro and buff.castMacro ~= "" then return "macro", buff.castMacro end
    if buff.castItemID then return "item", buff.castItemID end
    if buff.castSpellID then
        if IsPlayerSpell(buff.castSpellID) then return "spell", buff.castSpellID end
        return nil, nil
    end
    local spellID = buff.spellID
    if type(spellID) == "table" then spellID = spellID[1] end
    if spellID and IsPlayerSpell(spellID) then return "spell", spellID end
    return nil, nil
end

local function HasCustomClickAction(def)
    if not def then return false end
    return def.castSpellID ~= nil or def.castItemID ~= nil or (def.castMacro ~= nil and def.castMacro ~= "")
end

-- ============================================================================
-- LAST TARGET TOOLTIP
-- ============================================================================

local lastTargetTooltip

local function ShowLastTargetTooltip(anchor, name, class)
    if not lastTargetTooltip then
        local tip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        tip:SetFrameStrata("TOOLTIP")
        tip:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        tip:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        tip:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        tip.name = tip:CreateFontString(nil, "OVERLAY")
        tip.name:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
        tip.name:SetPoint("CENTER", 0, 0)
        lastTargetTooltip = tip
    end
    local tip = lastTargetTooltip
    local r, g, b = 1, 1, 1
    if class then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then r, g, b = c.r, c.g, c.b end
    end
    tip.name:SetText(name); tip.name:SetTextColor(r, g, b)
    local tw = tip.name:GetStringWidth()
    local th = tip.name:GetStringHeight()
    tip:SetSize(tw + 24, th + 16)
    tip:ClearAllPoints(); tip:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
    tip:Show()
end

local function HideLastTargetTooltip()
    if lastTargetTooltip then lastTargetTooltip:Hide() end
end

-- ============================================================================
-- CLICK-TO-CAST OVERLAY
-- ============================================================================

local TEXCOORD_INSET = 0.07

local function CreateClickOverlay(frame)
    local overlay = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("AnyDown", "AnyUp")
    overlay:EnableMouse(false); overlay:Hide()
    RegisterStateDriver(overlay, "visibility", "[combat] hide; show")
    overlay:SetScript("OnShow", function(self)
        if not frame:IsVisible() then self:Hide() end
    end)
    overlay:SetScript("PreClick", function(self)
        if self._br_clickMacroFn then
            self:SetAttribute("macrotext", self._br_clickMacroFn(self._br_clickMacroSpellID))
        end
    end)
    overlay:SetScript("PostClick", function(self)
        if ns.ConsumableMemory then ns.ConsumableMemory.RememberChoice(self.itemID, frame) end
        C_Timer.After(0.3, function()
            if not InCombatLockdown() then
                if ns.BuffState then ns.BuffState.InvalidateItemCache() end
                SecureButtons.InvalidateConsumableCache()
                if ns.BuffDisplay then ns.BuffDisplay.Update() end
            end
        end)
        if self._br_clickMacroFn then
            C_Timer.After(2, function()
                if not InCombatLockdown() then
                    if ns.BuffState then ns.BuffState.InvalidateItemCache() end
                    SecureButtons.InvalidateConsumableCache()
                    if ns.BuffDisplay then ns.BuffDisplay.Update() end
                end
            end)
        end
    end)
    overlay.highlight = overlay:CreateTexture(nil, "HIGHLIGHT")
    overlay.highlight:SetAllPoints()
    overlay.highlight:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
    overlay.highlight:SetColorTexture(1, 1, 1, 0.2)
    overlay:HookScript("OnEnter", function()
        if frame.buffDef and (frame.buffCategory == "targeted" or frame.buffDef.castOnOthers) then
            local name, class2 = ns.StateHelpers and ns.StateHelpers.GetLastTarget(frame.buffDef.key)
            if name then ShowLastTargetTooltip(overlay, name, class2) end
            return
        end
        if frame.buffCategory == "consumable" then
            local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
            if not db or not db.defaults or db.defaults.showConsumableTooltips ~= true then return end
            local itemID = overlay.itemID
            if itemID then
                GameTooltip:SetOwner(overlay, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(itemID); GameTooltip:Show()
            end
        end
    end)
    overlay:HookScript("OnLeave", function()
        HideLastTargetTooltip()
        if frame.buffCategory == "consumable" then GameTooltip:Hide() end
    end)
    frame.clickOverlay = overlay
end

-- ============================================================================
-- CONSUMABLE ACTION BUTTONS
-- ============================================================================

local ACTION_ICON_SCALE = 0.45
local ACTION_ICON_MIN = 18
local ACTION_ICON_OFFSET = -6

local function CreateActionButton()
    local btn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyDown", "AnyUp"); btn:Hide()
    RegisterStateDriver(btn, "visibility", "hide")
    btn:SetScript("OnShow", function(self)
        local bf = self._br_buff_frame
        if not bf or not bf:IsVisible() then self:Hide() end
    end)
    btn:SetScript("PostClick", function(self)
        if ns.ConsumableMemory then ns.ConsumableMemory.RememberChoice(self.itemID, self._br_buff_frame) end
        C_Timer.After(0.3, function()
            if not InCombatLockdown() then
                if ns.BuffState then ns.BuffState.InvalidateItemCache() end
                SecureButtons.InvalidateConsumableCache()
                if ns.BuffDisplay then ns.BuffDisplay.Update() end
            end
        end)
    end)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.count:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)
    btn:SetScript("OnEnter", function(self)
        local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
        if not db or not db.defaults or db.defaults.showConsumableTooltips ~= true then return end
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID); GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

-- Consumable cache
local consumableCache = {}
local consumableCacheDirty = true

function SecureButtons.InvalidateConsumableCache()
    consumableCacheDirty = true
end

local function RefreshConsumableCache()
    if not consumableCacheDirty then return end
    consumableCacheDirty = false
    if not C_Container or not C_Container.GetContainerNumSlots then
        wipe(consumableCache); return
    end
    local specId = ns.StateHelpers and ns.StateHelpers.GetPlayerSpecId()
    local itemSets = ns.CONSUMABLE_ITEMS or {}
    local buckets = {}
    local maxBags = NUM_BAG_SLOTS or 4
    for bag = 0, maxBags do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                for category, allowedSet in pairs(itemSets) do
                    local allowedEntry = allowedSet[itemID]
                    if allowedEntry and not (buckets[category] and buckets[category][itemID]) then
                        if not buckets[category] then buckets[category] = {} end
                        local ok, count = pcall(C_Item.GetItemCount, itemID, false, true)
                        count = (ok and count) or 0
                        if count > 0 then
                            local info = C_Container.GetContainerItemInfo(bag, slot)
                            local icon = info and info.iconFileID or nil
                            local bucket = { itemID = itemID, count = count, icon = icon }
                            if type(allowedEntry) == "table" then
                                bucket.statLabel = allowedEntry.label
                                bucket.badge = allowedEntry.badge
                            end
                            local hyperlink = info and info.hyperlink
                            if hyperlink then
                                local suffix = hyperlink:match("Quality%-[%w%-]*Tier%d")
                                if suffix then bucket.qualityAtlas = "Professions-Icon-" .. suffix end
                            end
                            local okSpell, _, useSpellID = pcall(GetItemSpell, itemID)
                            if okSpell and useSpellID then bucket.useSpellID = useSpellID end
                            buckets[category][itemID] = bucket
                        end
                    end
                end
            end
        end
    end
    if ns.ConsumableMemory then ns.ConsumableMemory.DetectConsumedItems(buckets, specId) end
    wipe(consumableCache)
    for category, entries in pairs(buckets) do
        local items = {}
        for _, item in pairs(entries) do items[#items + 1] = item end
        local allowedSet = itemSets[category]
        local rememberedSpell = ns.ConsumableMemory and ns.ConsumableMemory.GetRemembered(specId, category)
        tsort(items, function(a, b)
            local aPri = allowedSet and allowedSet[a.itemID]
            local bPri = allowedSet and allowedSet[b.itemID]
            local aNum = type(aPri) == "number" and aPri or (type(aPri) == "table" and aPri.priority) or nil
            local bNum = type(bPri) == "number" and bPri or (type(bPri) == "table" and bPri.priority) or nil
            if (aNum ~= nil) ~= (bNum ~= nil) then return aNum ~= nil end
            if aNum and bNum and aNum ~= bNum then return aNum < bNum end
            if rememberedSpell then
                local aRem = a.useSpellID == rememberedSpell
                local bRem = b.useSpellID == rememberedSpell
                if aRem ~= bRem then return aRem end
            end
            if a.count == b.count then return a.itemID < b.itemID end
            return a.count > b.count
        end)
        consumableCache[category] = items
    end
    if ns.ConsumableMemory then ns.ConsumableMemory.SnapshotCounts(buckets) end
end

local BUFF_KEY_TO_CATEGORY = ns.BUFF_KEY_TO_CATEGORY or {}

local function GetConsumableActionItems(buff)
    if not buff then return nil end
    local category = BUFF_KEY_TO_CATEGORY[buff.key]
    if not category then return nil end
    RefreshConsumableCache()
    local items = consumableCache[category]
    return items and #items > 0 and items or nil
end

function SecureButtons.UpdateConsumableButtons(frame, actionItems, clickable, startIndex)
    if InCombatLockdown() then return end
    startIndex = startIndex or 1
    if not actionItems or #actionItems < startIndex then
        if frame.actionButtons then
            for _, btn in ipairs(frame.actionButtons) do btn._br_visible = false; btn:Hide() end
        end
        return
    end
    if not frame.actionButtons then frame.actionButtons = {} end
    local btnIndex = 0
    for i = startIndex, #actionItems do
        btnIndex = btnIndex + 1
        local item = actionItems[i]
        local btn = frame.actionButtons[btnIndex]
        if not btn then
            btn = CreateActionButton()
            btn._br_buff_frame = frame
            frame.actionButtons[btnIndex] = btn
        end
        btn.itemID = item.itemID
        btn.icon:SetTexture(item.icon or 134400)
        if btn._br_action_item ~= item.itemID then
            if frame.key == "weaponBuff" or frame.key == "weaponBuffOH" then
                local slot = frame.key == "weaponBuffOH" and 17 or 16
                btn:SetAttribute("type", "macro")
                btn:SetAttribute("macrotext", "/use item:" .. tostring(item.itemID) .. "\n/use " .. slot)
            else
                btn:SetAttribute("type", "item")
                btn:SetAttribute("item", "item:" .. tostring(item.itemID))
            end
            btn._br_action_item = item.itemID
        end
        btn:EnableMouse(clickable == true)
        btn._br_visible = true
        btn._br_count = item.count
        btn._br_qualityAtlas = item.qualityAtlas
        btn._br_needs_sync = true
    end
    for i = btnIndex + 1, #frame.actionButtons do
        frame.actionButtons[i]._br_visible = false; frame.actionButtons[i]:Hide()
    end
end

-- ============================================================================
-- SECURE FRAME SYNC
-- ============================================================================

local function DisableOverlay(overlay)
    overlay._br_has_action = false
    overlay._br_clickMacroFn = nil
    overlay._br_clickMacroSpellID = nil
    overlay.itemID = nil
    overlay:EnableMouse(false); overlay:Hide()
    overlay._br_left = nil
end

local function SetPetSpellAttributes(overlay, spellID, db)
    local felMacro = (db and db.defaults or {}).useFelDomination
        and IsPlayerSpell(FEL_DOMINATION_ID)
        and GetFelDomPetMacro(spellID)
    if felMacro then
        overlay:SetAttribute("type", "macro"); overlay:SetAttribute("macrotext", felMacro)
    else
        overlay:SetAttribute("type", "spell"); overlay:SetAttribute("spell", spellID)
    end
end

local function SetItemAttributes(overlay, itemID, weaponSlot)
    overlay.itemID = itemID
    if weaponSlot then
        overlay:SetAttribute("type", "macro")
        overlay:SetAttribute("macrotext", "/use item:" .. itemID .. "\n/use " .. weaponSlot)
    else
        overlay:SetAttribute("type", "item")
        overlay:SetAttribute("item", "item:" .. itemID)
    end
end

local function GetWeaponSlot(frame)
    if frame.key == "weaponBuff" then return 16 end
    if frame.key == "weaponBuffOH" then return 17 end
    return nil
end

function SecureButtons.HideAllSecureFrames()
    if InCombatLockdown() then return end
    local Display = ns.BuffDisplay
    if not Display or not Display.frames then return end
    for _, frame in pairs(Display.frames) do
        if frame.clickOverlay then
            frame.clickOverlay:EnableMouse(false); frame.clickOverlay:Hide()
            frame.clickOverlay._br_left = nil
        end
        if frame.actionButtons then
            for _, btn in ipairs(frame.actionButtons) do
                if btn._br_driver_active then
                    RegisterStateDriver(btn, "visibility", "hide")
                    btn._br_driver_active = false; btn._br_x = nil
                else btn:Hide() end
            end
        end
    end
end

local syncPending = false
function SecureButtons.ScheduleSecureSync()
    if syncPending then return end
    syncPending = true
    C_Timer.After(0, function()
        syncPending = false
        SecureButtons.SyncSecureButtons()
    end)
end

function SecureButtons.SyncSecureButtons()
    if InCombatLockdown() then return end
    local Display = ns.BuffDisplay
    if not Display or not Display.frames then return end
    for _, frame in pairs(Display.frames) do
        local overlay = frame.clickOverlay
        if overlay then
            if frame:IsVisible() then
                if not overlay._br_has_action then
                    overlay:EnableMouse(false); overlay:Hide(); overlay._br_left = nil
                else
                    local left, bottom, width, height = frame:GetRect()
                    if left then
                        if overlay._br_left ~= left or overlay._br_bottom ~= bottom
                            or overlay._br_width ~= width or overlay._br_height ~= height then
                            overlay:ClearAllPoints(); overlay:SetSize(width, height)
                            overlay:SetFrameStrata(frame:GetFrameStrata())
                            overlay:SetFrameLevel(frame:GetFrameLevel() + 5)
                            overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                            overlay._br_left = left; overlay._br_bottom = bottom
                            overlay._br_width = width; overlay._br_height = height
                        end
                        overlay:EnableMouse(true)
                        if not overlay:IsShown() then overlay:Show() end
                    end
                end
            else
                overlay:Hide(); overlay:EnableMouse(false); overlay._br_left = nil
            end
        end
        if frame.actionButtons then
            if frame:IsVisible() then
                local left, bottom, width, height = frame:GetRect()
                if left then
                    local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
                    local size = max(ACTION_ICON_MIN, floor(((db and db.defaults and db.defaults.iconSize) or 64) * ACTION_ICON_SCALE))
                    local btnSpacing = max(2, floor(size * 0.2))
                    local visibleCount = 0
                    for _, btn in ipairs(frame.actionButtons) do
                        if btn._br_visible then visibleCount = visibleCount + 1 end
                    end
                    if visibleCount > 0 then
                        local idx = 0
                        for _, btn in ipairs(frame.actionButtons) do
                            if btn._br_visible then
                                local maxPerRow = max(1, floor((width + btnSpacing) / (size + btnSpacing)))
                                local col = idx % maxPerRow
                                local row = floor(idx / maxPerRow)
                                local thisRowCount = min(maxPerRow, visibleCount - row * maxPerRow)
                                local thisRowWidth = thisRowCount * size + (thisRowCount - 1) * btnSpacing
                                local thisRowStartX = left + (width - thisRowWidth) / 2
                                local btnX = thisRowStartX + col * (size + btnSpacing)
                                local btnY = bottom + ACTION_ICON_OFFSET - size - row * (size + btnSpacing)
                                if btn._br_needs_sync or btn._br_x ~= btnX or btn._br_y ~= btnY or btn._br_size ~= size then
                                    btn:ClearAllPoints(); btn:SetSize(size, size)
                                    btn:SetFrameStrata(frame:GetFrameStrata())
                                    btn:SetFrameLevel(frame:GetFrameLevel() + 4)
                                    btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", btnX, btnY)
                                    btn._br_x = btnX; btn._br_y = btnY; btn._br_size = size
                                    btn.count:SetText(btn._br_count and btn._br_count > 1 and tostring(btn._br_count) or "")
                                    btn._br_needs_sync = false
                                end
                                if not btn._br_driver_active then
                                    RegisterStateDriver(btn, "visibility", "[combat] hide; show")
                                    btn._br_driver_active = true
                                end
                                if not btn:IsShown() then btn:Show() end
                                idx = idx + 1
                            end
                        end
                    end
                    for _, btn in ipairs(frame.actionButtons) do
                        if not btn._br_visible and btn._br_driver_active then
                            RegisterStateDriver(btn, "visibility", "hide")
                            btn._br_driver_active = false; btn._br_x = nil
                        end
                    end
                end
            else
                for _, btn in ipairs(frame.actionButtons) do
                    if btn._br_driver_active then
                        RegisterStateDriver(btn, "visibility", "hide")
                        btn._br_driver_active = false; btn._br_x = nil
                    else btn:Hide() end
                end
            end
        end
    end
end

-- ============================================================================
-- UPDATE ACTION BUTTONS
-- ============================================================================

function SecureButtons.UpdateActionButtons(category)
    if InCombatLockdown() then return end
    local Display = ns.BuffDisplay
    if not Display or not Display.frames then return end
    local db = ns.db and ns.db.profile and ns.db.profile.BuffReminder
    if not db then return end
    local cs = db.categorySettings and db.categorySettings[category]
    local enabled = cs and cs.clickable == true
    local showHighlight = enabled and (cs.clickableHighlight ~= false)

    for _, frame in pairs(Display.frames) do
        if frame.buffCategory == category then
            local frameEnabled = enabled
            local frameHighlight = showHighlight
            if not frameEnabled and category == "custom" and HasCustomClickAction(frame.buffDef) then
                frameEnabled = true; frameHighlight = true
            end
            if frameEnabled then
                if category == "consumable" then
                    local actionItems = GetConsumableActionItems(frame.buffDef)
                    if actionItems and #actionItems > 0 then
                        if not frame.clickOverlay then CreateClickOverlay(frame) end
                        local overlay = frame.clickOverlay
                        overlay._br_has_action = true
                        overlay._br_clickMacroFn = nil; overlay._br_clickMacroSpellID = nil
                        SetItemAttributes(overlay, actionItems[1].itemID, GetWeaponSlot(frame))
                        overlay:EnableMouse(true)
                        if overlay.highlight then overlay.highlight:SetShown(showHighlight) end
                    elseif frame.clickOverlay then
                        frame.clickOverlay._br_has_action = false
                        frame.clickOverlay:EnableMouse(false)
                    end
                    SecureButtons.UpdateConsumableButtons(frame, actionItems, true)
                else
                    local castableID
                    local customActionType, customActionValue
                    if frame._br_pet_spell then
                        castableID = frame._br_pet_spell
                    elseif category == "custom" then
                        customActionType, customActionValue = ResolveCustomClickAction(frame.buffDef)
                        if customActionType == "spell" then
                            castableID = customActionValue; customActionType = nil
                        end
                    else
                        castableID = GetActionSpellID(frame.buffDef)
                    end
                    if customActionType then
                        if not frame.clickOverlay then CreateClickOverlay(frame) end
                        local overlay = frame.clickOverlay
                        overlay._br_has_action = true; overlay.itemID = nil
                        overlay._br_clickMacroFn = nil; overlay._br_clickMacroSpellID = nil
                        if customActionType == "macro" then
                            overlay:SetAttribute("type", "macro")
                            overlay:SetAttribute("macrotext", customActionValue:gsub("\\n", "\n"))
                        elseif customActionType == "item" then
                            overlay:SetAttribute("type", "item")
                            overlay:SetAttribute("item", "item:" .. customActionValue)
                            overlay.itemID = customActionValue
                        end
                        overlay:EnableMouse(true)
                        if overlay.highlight then overlay.highlight:SetShown(frameHighlight) end
                    elseif castableID then
                        if not frame.clickOverlay then CreateClickOverlay(frame) end
                        local overlay = frame.clickOverlay
                        overlay._br_has_action = true; overlay.itemID = nil
                        if frame._br_pet_spell then
                            overlay._br_clickMacroFn = nil; overlay._br_clickMacroSpellID = nil
                            SetPetSpellAttributes(overlay, castableID, db)
                        else
                            overlay._br_clickMacroFn = nil; overlay._br_clickMacroSpellID = nil
                            overlay:SetAttribute("type", "spell")
                            overlay:SetAttribute("spell", castableID)
                            overlay:SetAttribute("unit", category == "raid" and "player" or nil)
                        end
                        overlay:EnableMouse(true)
                        if overlay.highlight then overlay.highlight:SetShown(frameHighlight) end
                    elseif frame.clickOverlay then
                        DisableOverlay(frame.clickOverlay)
                    end
                end
            elseif frame.clickOverlay then
                DisableOverlay(frame.clickOverlay)
            end
        end
    end
    SecureButtons.ScheduleSecureSync()
end

function SecureButtons.GetConsumableActionItems(buff)
    return GetConsumableActionItems(buff)
end
