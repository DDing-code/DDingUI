local _, ns = ...
local DDingUI = ns.Addon
local L = LibStub("AceLocale-3.0"):GetLocale("DDingUI")
local SL = DDingUI.GUIBase.SL
local Consumables = {}
DDingUI.ConsumableOptions = Consumables

-- [12.0.1] Ordered item IDs remain the saved source of truth (id + fallbackItems).
local families = {
    concentrated = { name = "Concentrated Silvermoon Health Potion", kind = "health", ids = {271884, 271883} },
    health = { name = "Silvermoon Health Potion", kind = "health", ids = {241304, 241305} },
    light = { name = "Light's Potential", fleetingName = "Fleeting Light's Potential", kind = "stat", ids = {245898, 245897, 241308, 241309} },
    recklessness = { name = "Potion of Recklessness", fleetingName = "Fleeting Potion of Recklessness", kind = "stat", ids = {245902, 245903, 241288, 241289} },
    -- [12.0.1] Liquid Luster: fleeting R2/R1, regular R2/R1.
    luster = { name = "Liquid Luster", fleetingName = "Fleeting Liquid Luster", kind = "stat", ids = {274764, 274763, 271887, 271886} },
    mana = { name = "Lightfused Mana Potion", fleetingName = "Fleeting Lightfused Mana Potion", kind = "mana", ids = {245916, 245917, 241300, 241301} },
}
local kinds = { health = {"concentrated", "health"}, stat = {"light", "recklessness", "luster"}, mana = {"mana"} }
local kindNames = { health = "Health Potions", stat = "Stat Potions", mana = "Mana Potions" }
local items = {}
for key, family in pairs(families) do
    for index, id in ipairs(family.ids) do
        items[id] = { family = key, rank = index % 2 == 1 and 2 or 1,
            fleeting = family.fleetingName ~= nil and index <= 2 }
    end
end

local function T(key) return rawget(L, key) or key end

local function ReadIDs(iconData)
    local ids, seen = {}, {}
    local function add(id)
        id = tonumber(id)
        if id and not seen[id] then ids[#ids + 1], seen[id] = id, true end
    end
    add(iconData.id)
    for id in tostring(iconData.settings and iconData.settings.fallbackItems or ""):gmatch("(%d+)") do add(id) end
    return ids
end

function Consumables:GetKind(iconData)
    if not iconData or iconData.type ~= "item" or not items[iconData.id] then return nil end
    local kind = families[items[iconData.id].family].kind
    for _, id in ipairs(ReadIDs(iconData)) do
        if not items[id] or families[items[id].family].kind ~= kind then return nil end
    end
    return kind
end

function Consumables:BuildIDs(draft)
    local ids = {}
    for _, key in ipairs(draft.order) do
        if draft.enabled[key] then
            local variants = {}
            for _, id in ipairs(families[key].ids) do variants[#variants + 1] = id end
            table.sort(variants, function(a, b)
                local x, y = items[a], items[b]
                if x.fleeting ~= y.fleeting then return x.fleeting == draft.fleetingFirst end
                if x.rank ~= y.rank then
                    if draft.highRankFirst then return x.rank > y.rank end
                    return x.rank < y.rank
                end
                return a < b
            end)
            for _, id in ipairs(variants) do ids[#ids + 1] = id end
        end
    end
    return ids
end

function Consumables:CreateDraft(kind, iconData)
    if not kinds[kind] or (iconData and self:GetKind(iconData) ~= kind) then return nil end
    local draft = { kind = kind, order = {}, enabled = {}, highRankFirst = true, fleetingFirst = true,
        healerOnly = kind == "mana" and iconData and iconData.settings and iconData.settings.healerOnly == true or false,
        itemCountMode = iconData and iconData.settings and iconData.settings.itemCountMode == "total" and "total" or "selected",
        showItemQuality = not (iconData and iconData.settings and iconData.settings.showItemQuality == false),
        hideWhenEmpty = iconData and iconData.settings and iconData.settings.hideWhenEmpty == true or false }
    local seen = {}
    if iconData then
        draft.ids = ReadIDs(iconData)
        for _, id in ipairs(draft.ids) do
            local item = items[id]
            if not seen[item.family] then
                draft.order[#draft.order + 1] = item.family
                draft.enabled[item.family], seen[item.family] = true, true
            end
        end
        local first = items[draft.ids[1]]
        draft.highRankFirst = first.rank == 2
        draft.fleetingFirst = first.fleeting
    end
    for _, key in ipairs(kinds[kind]) do
        if not seen[key] then
            draft.order[#draft.order + 1] = key
            draft.enabled[key] = iconData == nil
        end
    end
    draft.ids = draft.ids or self:BuildIDs(draft)
    return draft
end

function Consumables:BuildPayload(draft)
    if not draft or not kinds[draft.kind] or #draft.ids == 0 then return nil end
    local fallbacks, seen = {}, {}
    for index, id in ipairs(draft.ids) do
        if not items[id] or families[items[id].family].kind ~= draft.kind or seen[id] then return nil end
        seen[id] = true
        if index > 1 then fallbacks[#fallbacks + 1] = tostring(id) end
    end
    return { type = "item", id = draft.ids[1], settings = {
        fallbackItems = table.concat(fallbacks, ","), hideWhenEmpty = draft.hideWhenEmpty == true,
        itemCountMode = draft.itemCountMode == "total" and "total" or nil,
        showItemQuality = draft.showItemQuality ~= false,
        healerOnly = draft.kind == "mana" and draft.healerOnly == true or nil,
    } }
end

local function ItemLabel(id)
    local item = items[id]
    local family = families[item.family]
    local name = C_Item.GetItemNameByID(id) or T(item.fleeting and family.fleetingName or family.name)
    return string.format(T("%s (Rank %d)"), name, item.rank)
end

local function GetIconData(iconKey)
    local db = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.dynamicIcons
    return db and db.iconData and db.iconData[iconKey]
end

function Consumables:Edit(iconKey, onDone)
    local iconData = GetIconData(iconKey)
    local kind = self:GetKind(iconData)
    if not kind then return false end
    return self:Show(kind, iconData, function(payload)
        if GetIconData(iconKey) ~= iconData then return false end
        iconData.id = payload.id
        iconData.settings = iconData.settings or {}
        local roleChanged = (iconData.settings.healerOnly == true) ~= (payload.settings.healerOnly == true)
        iconData.settings.fallbackItems = payload.settings.fallbackItems
        iconData.settings.hideWhenEmpty = payload.settings.hideWhenEmpty
        iconData.settings.itemCountMode = payload.settings.itemCountMode
        iconData.settings.showItemQuality = payload.settings.showItemQuality
        iconData.settings.healerOnly = payload.settings.healerOnly
        local ci = DDingUI.CustomIcons
        local overlay = DDingUI.CustomIconActiveEffectOverlay
        if overlay then overlay:MarkDirty() end
        if roleChanged then
            ci:LoadDynamicIcons()
        else
            ci:RefreshDynamicIcon(iconKey)
        end
        ci.OptionsAPI.RefreshAllLayouts()
        if DDingUI.SpecProfiles then DDingUI.SpecProfiles:SaveCurrentSpec() end
        if onDone then onDone() end
        return true
    end)
end

local windows = {}
function Consumables:Show(kind, iconData, onApply)
    local draft = self:CreateDraft(kind, iconData)
    if not draft or type(onApply) ~= "function" then return false end
    local windowName = kind == "mana" and "DDingUI_ManaPotionPriority" or "DDingUI_ConsumablePriority"
    -- [REFACTOR] Health/stat share a window; reserve rows for either opening order.
    local familyRows = kind == "mana" and #kinds.mana or math.max(#kinds.health, #kinds.stat)
    local itemRows = 8
    for _, keys in ipairs(kind == "mana" and {kinds.mana} or {kinds.health, kinds.stat}) do
        local count = 0
        for _, key in ipairs(keys) do count = count + #families[key].ids end
        itemRows = math.max(itemRows, count)
    end
    local window = windows[windowName]
    if not window then
        window = CreateFrame("Frame", windowName, UIParent, "BackdropTemplate")
        windows[windowName] = window
        window:SetSize(640, 658)
        window:SetPoint("CENTER")
        -- [FIX] The settings workspace is DIALOG with elevated child frame levels.
        window:SetFrameStrata("FULLSCREEN_DIALOG")
        window:EnableMouse(true)
        window:SetClampedToScreen(true)
        window:SetMovable(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window:SetBackdrop({bgFile = SL.Textures.flat, edgeFile = SL.Textures.flat, edgeSize = 1})
        window:SetBackdropColor(SL.GetColor("background"))
        window:SetBackdropBorderColor(SL.GetColor("border"))
        table.insert(UISpecialFrames, windowName)
        local function label(y, size, color)
            local text = window:CreateFontString(nil, "OVERLAY")
            text:SetFont(DDingUI:GetGlobalFont(), size, "")
            text:SetPoint("TOPLEFT", 20, -y)
            text:SetWidth(600)
            text:SetJustifyH("LEFT")
            text:SetTextColor(SL.GetColor(color or "text"))
            return text
        end
        window.title = label(18, 16, "accent")
        window.hint = label(48, 12, "dim") -- [STYLE]
        window.hint:SetText(T(kind == "mana"
            and "Choose the mana potion priority. The first potion in your bags is displayed."
            or "Check potion types and use the arrows to set priority. The first potion in your bags is displayed."))
        window.families = {}
        for index = 1, familyRows do
            local row = {}
            window.families[index] = row
            row.enabled = SL.CreateCheckbox(window, "CDM", "", true, { onChange = function(value)
                if window.refreshing then return end
                window.draft.enabled[window.draft.order[index]] = value
                window:Reorder()
            end })
            row.enabled:SetPoint("TOPLEFT", 20, -(84 + (index - 1) * 36))
            local function move(delta)
                local order = window.draft.order
                order[index], order[index + delta] = order[index + delta], order[index]
                window:Reorder()
            end
            row.up = SL.CreateButton(window, "CDM", "▲", function() move(-1) end, {width = 28})
            row.up:SetPoint("TOPRIGHT", -56, -(82 + (index - 1) * 36))
            row.down = SL.CreateButton(window, "CDM", "▼", function() move(1) end, {width = 28})
            row.down:SetPoint("TOPRIGHT", -20, -(82 + (index - 1) * 36))
            for _, entry in ipairs({{row.up, "Move up"}, {row.down, "Move down"}}) do
                local button, title = entry[1], entry[2]
                button:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(T(title)); GameTooltip:Show()
                end)
                button:HookScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end
        if kind == "mana" then
            window.healerOnly = SL.CreateCheckbox(window, "CDM", T("Show only for healer specializations"), false, {onChange = function(value)
                if not window.refreshing then window.draft.healerOnly = value end
            end})
            window.healerOnly:SetPoint("TOPLEFT", 20, -120)
        end
        window.fleeting = SL.CreateCheckbox(window, "CDM", T("Prefer fleeting potions"), true, {onChange = function(value)
            if window.refreshing then return end
            window.draft.fleetingFirst = value
            window:Reorder()
        end})
        window.fleeting:SetPoint("TOPLEFT", 20, -164)
        window.rank = SL.CreateCheckbox(window, "CDM", T("Prefer higher rank"), true, {onChange = function(value)
            if window.refreshing then return end
            window.draft.highRankFirst = value
            window:Reorder()
        end})
        window.rank:SetPoint("TOPLEFT", 330, -164)
        window.rules = label(193, 12, "dim") -- [STYLE]
        window.rules:SetText(T("When off: regular potions first / lower rank first. Potion type order takes priority."))
        window.preview = label(228, 13)
        window.orderLabel = label(268, 12, "dim") -- [STYLE]
        window.entries = {}
        for index = 1, itemRows do
            local row = CreateFrame("Frame", nil, window)
            row:SetSize(600, 26)
            row:SetPoint("TOPLEFT", 20, -(292 + (index - 1) * 28))
            row:EnableMouse(true)
            row.text = row:CreateFontString(nil, "OVERLAY")
            row.text:SetFont(DDingUI:GetGlobalFont(), 12, "")
            row.text:SetPoint("LEFT")
            row.text:SetWidth(510)
            row.text:SetJustifyH("LEFT")
            row.count = row:CreateFontString(nil, "OVERLAY")
            row.count:SetFont(DDingUI:GetGlobalFont(), 12, "")
            row.count:SetPoint("RIGHT")
            row.count:SetTextColor(SL.GetColor("dim"))
            row:SetScript("OnEnter", function(self)
                if self.itemID then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            window.entries[index] = row
        end
        window.empty = SL.CreateCheckbox(window, "CDM", T("Hide when all potions are missing"), false, {onChange = function(value)
            if not window.refreshing then window.draft.hideWhenEmpty = value end
        end})
        window.empty:SetPoint("TOPLEFT", 20, -528)
        window.countMode = SL.CreateDropdown(window, "CDM", T("Count display"), {
            {text = T("Separate (selected)"), value = "selected"},
            {text = T("Combined (all)"), value = "total"},
        }, "selected", {width = 178, onChange = function(value)
            if window.refreshing then return end
            window.draft.itemCountMode = value
            window:Refresh()
        end})
        window.countMode:SetPoint("TOPLEFT", 330, -526)
        window.quality = SL.CreateCheckbox(window, "CDM", T("Show item quality on icon"), true, {onChange = function(value)
            if not window.refreshing then window.draft.showItemQuality = value end
        end})
        window.quality:SetPoint("TOPLEFT", 20, -558)
        window.status = label(585, 12, "dim") -- [STYLE]
        window.apply = SL.CreateButton(window, "CDM", T("Apply"), function()
            if InCombatLockdown() then return end
            local payload = Consumables:BuildPayload(window.draft)
            if DDingUI.db.profile ~= window.profile or (GetSpecialization and GetSpecialization() ~= window.spec) then
                window.status:SetText(T("The profile or specialization changed. Reopen this window."))
            elseif payload and window.onApply(payload) then
                window:Hide()
            else
                window.status:SetText(T("Could not apply. Reopen this window and try again."))
            end
        end, {width = 100, height = 28})
        window.apply:SetPoint("BOTTOMRIGHT", -20, 16)
        window.cancel = SL.CreateButton(window, "CDM", T("Cancel"), function() window:Hide() end, {width = 100, height = 28})
        window.cancel:SetPoint("RIGHT", window.apply, "LEFT", -8, 0)
        function window:Reorder()
            self.draft.ids = Consumables:BuildIDs(self.draft)
            self:Refresh()
        end
        function window:Refresh()
            self.refreshing = true
            local d = self.draft
            self.title:SetText(T("Consumables") .. " · " .. T(kindNames[d.kind]))
            for index, key in ipairs(d.order) do
                local row = self.families[index]
                row.enabled:Show()
                row.enabled.label:SetText(index .. ". " .. T(families[key].name))
                row.enabled:SetChecked(d.enabled[key])
                row.up:SetDisabledState(index == 1)
                row.down:SetDisabledState(index == #d.order)
                row.up:SetShown(#d.order > 1)
                row.down:SetShown(#d.order > 1)
            end
            for index = #d.order + 1, #self.families do
                local row = self.families[index]
                row.enabled:Hide(); row.up:Hide(); row.down:Hide()
            end
            self.fleeting:SetShown(d.kind ~= "health")
            self.fleeting:SetChecked(d.fleetingFirst)
            self.rank:SetChecked(d.highRankFirst)
            self.empty:SetChecked(d.hideWhenEmpty)
            self.quality:SetChecked(d.showItemQuality)
            if self.healerOnly then self.healerOnly:SetChecked(d.healerOnly) end
            self.countMode:SetValue(d.itemCountMode)
            local payload = Consumables:BuildPayload(d)
            local selected, count, displayCount
            if payload then selected, count, displayCount = DDingUI.CustomIcons:GetPreferredItem(payload) end
            if count and count > 0 then
                self.preview:SetText(T("Currently displayed") .. ":  " .. ItemLabel(selected) .. " · " .. string.format(T("Icon count: %d"), displayCount))
            else
                self.preview:SetText(T("No potions in bags"))
            end
            local canonical = table.concat(Consumables:BuildIDs(d), ",") == table.concat(d.ids, ",")
            self.orderLabel:SetText(T(canonical and "Display priority" or "Existing item order (changing options updates this list)"))
            for index, row in ipairs(self.entries) do
                local id = d.ids[index]
                row.itemID = id
                row:SetShown(id ~= nil)
                if id then
                    local n = DDingUI.CustomIconRuntimeValues.SafeNumber(C_Item.GetItemCount(id, false, false, false)) or 0
                    row.text:SetText(index .. ".  |T" .. (C_Item.GetItemIconByID(id) or 134830) .. ":22:22|t  " .. ItemLabel(id))
                    row.text:SetTextColor(SL.GetColor(n > 0 and "text" or "dim"))
                    row.count:SetText(string.format(T("%d in bags"), n))
                end
            end
            self.apply:SetDisabledState(not payload or InCombatLockdown())
            self.status:SetText(InCombatLockdown() and T("Apply after combat ends.") or T("Displays an icon only; does not change your use macro."))
            self.refreshing = false
        end
        window:SetScript("OnEvent", function(self) self:Refresh() end)
        window:SetScript("OnHide", function(self)
            self:UnregisterAllEvents()
            self.onApply, self.profile = nil, nil
            GameTooltip:Hide()
        end)
    end
    window.draft, window.onApply = draft, onApply
    window.profile = DDingUI.db.profile
    window.spec = GetSpecialization and GetSpecialization()
    -- [REFACTOR] Make room for every variant without overlapping options below it.
    local familyOffset = math.max(0, #kinds[kind] - 2) * 36
    local itemCount = 0
    for _, key in ipairs(kinds[kind]) do itemCount = itemCount + #families[key].ids end
    local itemOffset = math.max(0, itemCount - 8) * 28
    window:SetHeight(658 + familyOffset + itemOffset)
    for _, entry in ipairs({
        {window.fleeting, 20, 164}, {window.rank, 330, 164},
        {window.rules, 20, 193}, {window.preview, 20, 228}, {window.orderLabel, 20, 268},
        {window.empty, 20, 528 + itemOffset}, {window.countMode, 330, 526 + itemOffset},
        {window.quality, 20, 558 + itemOffset}, {window.status, 20, 585 + itemOffset},
    }) do
        entry[1]:SetPoint("TOPLEFT", entry[2], -(entry[3] + familyOffset))
    end
    for index, row in ipairs(window.entries) do
        row:SetPoint("TOPLEFT", 20, -(292 + familyOffset + (index - 1) * 28))
    end
    window:SetScale(math.min(1, UIParent:GetWidth() / 680, UIParent:GetHeight() / (window:GetHeight() + 34)))
    for _, event in ipairs({"BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do window:RegisterEvent(event) end
    window:Refresh()
    window:Show()
    for _, family in pairs(families) do
        if family.kind == kind then
            for _, id in ipairs(family.ids) do C_Item.RequestLoadItemDataByID(id) end
        end
    end
    return true
end
