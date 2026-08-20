local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupSystemIconTextures = {}
DDingUI.GroupSystemIconTextures = GroupSystemIconTextures

GroupSystemIconTextures.DEFAULT_BUFF_ICON_TEXTURE = "Interface\\Icons\\Spell_Holy_PowerWordShield"
GroupSystemIconTextures.DEFAULT_SPELL_ICON_TEXTURE = "Interface\\Icons\\Spell_Nature_TimeStop"
GroupSystemIconTextures.DEFAULT_ITEM_ICON_TEXTURE = "Interface\\Icons\\INV_Potion_93"
GroupSystemIconTextures.DEFAULT_TRINKET_ICON_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01"
GroupSystemIconTextures.DEFAULT_RACIAL_ICON_TEXTURE = "Interface\\Icons\\Spell_magic_polymorphrabbit"

local QUESTION_MARK_TEXTURE = 134400
local QUESTION_MARK_ICON_PATH = "Interface\\Icons\\INV_Misc_QuestionMark"
local CUSTOM_AURA_ICON_TEXTURES = {
    [1236616] = 7548911,
    [1236994] = 7548916,
    [1239479] = "Interface\\Icons\\INV_12_Profession_Alchemy_VoidPotion_Blue",
    [374968] = 4622479,
    [2825] = "Interface\\Icons\\Spell_Nature_BloodLust",
    [29166] = "Interface\\Icons\\Spell_Nature_Lightning",
}
local CUSTOM_AURA_PRESET_SPELL_IDS = {
    [1236616] = true,
    [1236994] = true,
    [1239479] = true,
    [374968] = true,
    [29166] = true,
    [406732] = true,
}
for _, spellID in ipairs({ 2825, 32182, 80353, 90355, 160452, 264667, 390386 }) do
    CUSTOM_AURA_PRESET_SPELL_IDS[spellID] = true
end
local CUSTOM_AURA_PRESET_NAME_IDS = {
    ["Light's Potential"] = 1236616,
    ["Potion of Recklessness"] = 1236994,
    ["Devoured Dreams"] = 1239479,
    ["Potion of Devoured Dreams"] = 1239479,
    ["Time Spiral"] = 374968,
    ["Innervate"] = 29166,
    ["Spatial Paradox"] = 406732,
    ["정신 자극"] = 29166,
    ["공간의 역설"] = 406732,
    ["Bloodlust"] = 2825,
    ["Bloodlust / Heroism"] = 2825,
    ["Heroism"] = 32182,
    ["Time Warp"] = 80353,
    ["Ancient Hysteria"] = 90355,
    ["Fury of the Aspects"] = 390386,
    ["빛의 잠재력"] = 1236616,
    ["무모함의 물약"] = 1236994,
    ["잠식된 꿈"] = 1239479,
    ["시간의 와류"] = 374968,
    ["피의 욕망"] = 2825,
    ["영웅심"] = 32182,
    ["시간 왜곡"] = 80353,
}
local CUSTOM_AURA_ICON_ITEM_FALLBACKS = {
    [1236616] = 241308,
    [1236994] = 241288,
    [1239479] = 241294,
}

function GroupSystemIconTextures:CreateRuntime(pendingSpellRefresh, invalidateCache)
    local DEFAULT_BUFF_ICON_TEXTURE = self.DEFAULT_BUFF_ICON_TEXTURE
    local DEFAULT_ITEM_ICON_TEXTURE = self.DEFAULT_ITEM_ICON_TEXTURE

    local function SafeOptionValue(value)
        if issecretvalue and issecretvalue(value) then return nil end
        return value
    end

    local function SafeOptionID(value)
        value = SafeOptionValue(value)
        local id = tonumber(value)
        if id and id > 0 then return id end
        return nil
    end

    local function SafeOptionTexture(value, fallback)
        value = SafeOptionValue(value)
        if value and value ~= 0 and value ~= "" then return value end
        return fallback
    end

    local function IsQuestionTexture(value)
        if value == 0 or value == "" then return true end
        if type(value) == "string" then
            return value:gsub("/", "\\"):lower():find("inv_misc_questionmark", 1, true) ~= nil
        end
        return value == QUESTION_MARK_TEXTURE or value == QUESTION_MARK_ICON_PATH
    end

    local function NonQuestionTexture(value, fallback)
        value = SafeOptionTexture(value)
        if value and not IsQuestionTexture(value) then return value end
        fallback = SafeOptionTexture(fallback)
        if fallback and not IsQuestionTexture(fallback) then return fallback end
        return DEFAULT_BUFF_ICON_TEXTURE
    end

    local function GetCustomAuraPresetIconTexture(spellID)
        spellID = SafeOptionID(spellID)
        local presetTex = spellID and SafeOptionTexture(CUSTOM_AURA_ICON_TEXTURES[spellID])
        if presetTex and not IsQuestionTexture(presetTex) then return presetTex end

        if spellID and C_Spell and C_Spell.GetSpellTexture then
            local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
            texture = SafeOptionTexture(ok and texture)
            if texture and not IsQuestionTexture(texture) then return texture end
        end
        return nil
    end

    local function ResolveCustomAuraPresetIDForTexture(spellName, spellID)
        spellID = SafeOptionID(spellID)
        if spellID and CUSTOM_AURA_PRESET_SPELL_IDS[spellID] then return spellID end

        if type(spellName) == "string" and spellName ~= "" then
            local rawName = spellName:gsub("^buff_", "")
            local mapped = CUSTOM_AURA_PRESET_NAME_IDS[rawName] or CUSTOM_AURA_PRESET_NAME_IDS[spellName]
            if mapped then return mapped end

            if C_Spell and C_Spell.GetSpellInfo then
                for presetID in pairs(CUSTOM_AURA_PRESET_SPELL_IDS) do
                    local ok, info = pcall(C_Spell.GetSpellInfo, presetID)
                    if ok and info and info.name and (info.name == rawName or info.name == spellName) then
                        return presetID
                    end
                end
            end
        end
        return nil
    end

    local function NormalizeCustomAuraPresetIconData(iconData)
        if type(iconData) ~= "table" or not (iconData.type == "spell" or iconData.type == "aura") then return end
        local presetID = ResolveCustomAuraPresetIDForTexture(iconData.settings and iconData.settings.auraName, iconData.id)
        local presetIcon = presetID and GetCustomAuraPresetIconTexture(presetID)
        if not presetIcon then return end

        iconData.id = presetID
        iconData.settings = iconData.settings or {}
        iconData.settings.iconTexture = presetIcon
        iconData.settings.auraIcon = presetIcon
    end

    local function NormalizeCustomAuraPresetDynamicIcons(dynDB)
        local iconDataDB = dynDB and dynDB.iconData
        if type(iconDataDB) ~= "table" then return end
        for _, iconData in pairs(iconDataDB) do
            NormalizeCustomAuraPresetIconData(iconData)
        end
    end

    local function SafeOptionItemTexture(itemID)
        itemID = SafeOptionID(itemID)
        if not itemID then return nil end

        local okIcon, icon = pcall(function()
            return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
        end)
        icon = SafeOptionTexture(okIcon and icon)
        if icon and not IsQuestionTexture(icon) then return icon end

        local okInstant, instantIcon = pcall(function()
            if not C_Item or not C_Item.GetItemInfoInstant then return nil end
            local _, _, _, _, tex = C_Item.GetItemInfoInstant(itemID)
            return tex
        end)
        instantIcon = SafeOptionTexture(okInstant and instantIcon)
        if instantIcon and not IsQuestionTexture(instantIcon) then return instantIcon end

        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
        return NonQuestionTexture(icon or instantIcon, DEFAULT_ITEM_ICON_TEXTURE)
    end

    local function QueueOptionSpellIconRefresh(spellID)
        spellID = SafeOptionID(spellID)
        if not spellID or pendingSpellRefresh[spellID] then return end

        if C_Spell and C_Spell.RequestLoadSpellData then
            pcall(C_Spell.RequestLoadSpellData, spellID)
        end
        if C_Timer and C_Timer.NewTimer then
            local timer
            timer = C_Timer.NewTimer(0.35, function()
                pendingSpellRefresh[spellID] = nil
                invalidateCache()
                local configFrame = _G["DDingUI_ConfigFrame"]
                if configFrame and configFrame:IsShown() and DDingUI.RefreshConfigGUI then
                    DDingUI:RefreshConfigGUI()
                end
            end)
            pendingSpellRefresh[spellID] = timer
        end
    end

    local function SafeOptionSpellTexture(spellID)
        spellID = SafeOptionID(spellID)
        if not spellID then return nil end

        local presetTex = GetCustomAuraPresetIconTexture(spellID)
        if presetTex then return presetTex end

        if not C_Spell then return nil end

        local okInfo, info = pcall(function()
            return C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        end)
        local iconID = okInfo and info and SafeOptionTexture(info.iconID)
        if iconID and not IsQuestionTexture(iconID) then return iconID end

        local okTex, tex = pcall(function()
            return C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
        end)
        tex = SafeOptionTexture(okTex and tex)
        if tex and not IsQuestionTexture(tex) then return tex end

        local fallbackItemID = CUSTOM_AURA_ICON_ITEM_FALLBACKS[spellID]
        local itemTex = fallbackItemID and SafeOptionItemTexture(fallbackItemID)
        if itemTex and not IsQuestionTexture(itemTex) then return itemTex end

        QueueOptionSpellIconRefresh(spellID)
        return iconID or tex or itemTex
    end

    local function AddOptionSpellCandidate(candidates, seen, value)
        local id = SafeOptionID(value)
        if id and not seen[id] then
            seen[id] = true
            candidates[#candidates + 1] = id
        end
    end

    local function GetCooldownInfoSpellCandidates(info, cooldownID, preferredSpellID)
        local candidates, seen = {}, {}
        local compat = DDingUI.CDMCompat
        local identity = compat and compat.GetCooldownSpellIdentity
            and compat:GetCooldownSpellIdentity(cooldownID, info, preferredSpellID)
        if identity and type(identity.spellIDs) == "table" then
            for _, spellID in ipairs(identity.spellIDs) do
                AddOptionSpellCandidate(candidates, seen, spellID)
            end
        end
        if info then
            AddOptionSpellCandidate(candidates, seen, info.overrideTooltipSpellID)
            AddOptionSpellCandidate(candidates, seen, info.overrideSpellID)
            AddOptionSpellCandidate(candidates, seen, info.spellID)
            local linkedSpellIDs = SafeOptionValue(info.linkedSpellIDs)
            if type(linkedSpellIDs) == "table" then
                pcall(function()
                    for _, linkedID in ipairs(linkedSpellIDs) do
                        AddOptionSpellCandidate(candidates, seen, linkedID)
                    end
                end)
            end
        end
        AddOptionSpellCandidate(candidates, seen, cooldownID)
        return candidates
    end

    local function ResolveSpellTextureFromCandidates(candidates, fallback)
        local deferred
        for _, spellID in ipairs(candidates or {}) do
            local tex = SafeOptionSpellTexture(spellID)
            if tex and not IsQuestionTexture(tex) then
                return tex
            end
            deferred = deferred or tex
        end
        return NonQuestionTexture(fallback, deferred or DEFAULT_BUFF_ICON_TEXTURE)
    end

    local function ResolveCDMEntryIconTexture(entry, spellName, fallback)
        local presetID = ResolveCustomAuraPresetIDForTexture(spellName, entry and entry.spellID)
        local presetIcon = presetID and GetCustomAuraPresetIconTexture(presetID)
        if presetIcon then return presetIcon end

        local candidates, seen = {}, {}
        if entry then
            AddOptionSpellCandidate(candidates, seen, entry.iconSpellID)
            AddOptionSpellCandidate(candidates, seen, entry.spellID)
            local cooldownID = SafeOptionID(entry.cooldownID)
            if cooldownID then
                local compat = DDingUI.CDMCompat
                local info = compat and compat:GetCooldownInfo(cooldownID)
                if info then
                    for _, id in ipairs(GetCooldownInfoSpellCandidates(info, entry.cooldownID)) do
                        AddOptionSpellCandidate(candidates, seen, id)
                    end
                else
                    AddOptionSpellCandidate(candidates, seen, cooldownID)
                end
            end
        end

        local rawName = (spellName or (entry and entry.name) or ""):gsub("^buff_", "")
        if rawName ~= "" and C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, rawName)
            if ok and info then
                local iconID = SafeOptionTexture(info.iconID)
                if iconID and not IsQuestionTexture(iconID) then
                    return iconID
                end
                AddOptionSpellCandidate(candidates, seen, info.spellID)
            end
        end

        return ResolveSpellTextureFromCandidates(candidates, fallback)
    end

    return {
        SafeOptionValue = SafeOptionValue,
        SafeOptionID = SafeOptionID,
        SafeOptionTexture = SafeOptionTexture,
        IsQuestionTexture = IsQuestionTexture,
        NonQuestionTexture = NonQuestionTexture,
        GetCustomAuraPresetIconTexture = GetCustomAuraPresetIconTexture,
        ResolveCustomAuraPresetIDForTexture = ResolveCustomAuraPresetIDForTexture,
        NormalizeCustomAuraPresetIconData = NormalizeCustomAuraPresetIconData,
        NormalizeCustomAuraPresetDynamicIcons = NormalizeCustomAuraPresetDynamicIcons,
        SafeOptionItemTexture = SafeOptionItemTexture,
        QueueOptionSpellIconRefresh = QueueOptionSpellIconRefresh,
        SafeOptionSpellTexture = SafeOptionSpellTexture,
        AddOptionSpellCandidate = AddOptionSpellCandidate,
        GetCooldownInfoSpellCandidates = GetCooldownInfoSpellCandidates,
        ResolveSpellTextureFromCandidates = ResolveSpellTextureFromCandidates,
        ResolveCDMEntryIconTexture = ResolveCDMEntryIconTexture,
    }
end
