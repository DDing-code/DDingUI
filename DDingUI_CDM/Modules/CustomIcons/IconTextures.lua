local ns = select(2, ...)
local DDingUI = ns.Addon

DDingUI.CustomIcons = DDingUI.CustomIcons or {}
local CustomIcons = DDingUI.CustomIcons

local IconTextures = {}
DDingUI.CustomIconTextures = IconTextures

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local FALLBACK_SPELL_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
local FALLBACK_ITEM_ICON = "Interface\\Icons\\INV_Potion_93"
local FALLBACK_SLOT_ICON = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01"
local FALLBACK_RACIAL_ICON = "Interface\\Icons\\Spell_magic_polymorphrabbit"
local FALLBACK_TOTEM_ICON = 310731
local CUSTOM_AURA_ICON_TEXTURES = {
    [1236616] = 7548911, -- Light's Potential
    [1236994] = 7548916, -- Potion of Recklessness
    [1239479] = "Interface\\Icons\\INV_12_Profession_Alchemy_VoidPotion_Blue", -- Potion of Devoured Dreams
    [374968] = 4622479, -- Time Spiral
    [2825] = "Interface\\Icons\\Spell_Nature_BloodLust", -- Bloodlust
}
local CUSTOM_AURA_ICON_ITEM_FALLBACKS = {
    [1236616] = 241308, -- Light's Potential
    [1236994] = 241288, -- Potion of Recklessness
    [1239479] = 241294, -- Potion of Devoured Dreams
}

local function IsQuestionTexture(texture)
    if texture == 0 or texture == "" then return true end
    if type(texture) == "string" then
        return texture:gsub("/", "\\"):lower():find("inv_misc_questionmark", 1, true) ~= nil
    end
    return texture == 134400 or texture == QUESTION_MARK_ICON or texture == 0 or texture == ""
end

local function NonQuestionTexture(texture, fallback)
    if texture and not IsQuestionTexture(texture) then return texture end
    if fallback and not IsQuestionTexture(fallback) then return fallback end
    return FALLBACK_SPELL_ICON
end

local function GetCustomAuraPresetIconTexture(spellID)
    local texture = CUSTOM_AURA_ICON_TEXTURES[tonumber(spellID)]
    if texture and not IsQuestionTexture(texture) then return texture end
    return nil
end

local function ResolveItemTexture(itemID, slotID)
    local tex = nil
    if slotID then
        tex = GetInventoryItemTexture("player", slotID)
        if IsQuestionTexture(tex) then
            tex = nil
        end
    end
    if not tex and itemID and C_Item and C_Item.GetItemIconByID then
        tex = C_Item.GetItemIconByID(itemID)
        if IsQuestionTexture(tex) then
            tex = nil
        end
    end
    if not tex and itemID then
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
        tex = itemTexture
        if IsQuestionTexture(tex) then
            tex = nil
        end
    end
    if not tex and itemID and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return tex
end

local function ResolveSpellTexture(spellID, fallbackTexture)
    local tex = GetCustomAuraPresetIconTexture(spellID)
    if tex then return tex end

    tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
    if IsQuestionTexture(tex) then
        tex = nil
    end
    if not tex and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        tex = info and info.iconID
        if IsQuestionTexture(tex) then
            tex = nil
        end
    end
    if not tex then
        local fallbackItemID = CUSTOM_AURA_ICON_ITEM_FALLBACKS[tonumber(spellID)]
        if fallbackItemID then
            tex = ResolveItemTexture(fallbackItemID)
        end
    end
    if not tex and fallbackTexture and not IsQuestionTexture(fallbackTexture) then
        tex = fallbackTexture
    end
    if not tex and C_Spell and C_Spell.RequestLoadSpellData then
        C_Spell.RequestLoadSpellData(spellID)
    end
    return tex
end

local function GetStoredIconTexture(iconData)
    if iconData and (iconData.type == "spell" or iconData.type == "aura") then
        local preset = GetCustomAuraPresetIconTexture(iconData.id)
        if preset then return preset end
    end

    local settings = iconData and iconData.settings
    if type(settings) ~= "table" then return nil end
    local texture = settings.iconTexture or settings.fallbackIcon or settings.icon
    if texture and not IsQuestionTexture(texture) then return texture end
    return nil
end

local function EnsureStoredIconTexture(iconData)
    if not iconData then return nil end
    iconData.settings = iconData.settings or {}
    if iconData.type == "spell" or iconData.type == "aura" then
        local preset = GetCustomAuraPresetIconTexture(iconData.id)
        if preset then
            iconData.settings.iconTexture = preset
            iconData.settings.auraIcon = preset
            return preset
        end
    end

    local stored = GetStoredIconTexture(iconData)
    if stored then return stored end

    local texture
    if iconData.type == "item" then
        texture = ResolveItemTexture(iconData.id)
    elseif iconData.type == "spell" or iconData.type == "aura" then
        texture = ResolveSpellTexture(iconData.id)
    elseif iconData.type == "slot" or iconData.type == "trinketProc" then
        local itemID = iconData.slotID and CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID)
        texture = ResolveItemTexture(itemID, iconData.slotID)
    elseif iconData.type == "racial" then
        local racials = DDingUI.CustomIconRacials
        texture = racials and racials:GetTexture(FALLBACK_RACIAL_ICON) or FALLBACK_RACIAL_ICON
    elseif iconData.type == "totem" then
        texture = FALLBACK_TOTEM_ICON
    end

    if texture and not IsQuestionTexture(texture) then
        iconData.settings.iconTexture = texture
        return texture
    end
    return nil
end

IconTextures.fallbackSpellIcon = FALLBACK_SPELL_ICON
IconTextures.fallbackItemIcon = FALLBACK_ITEM_ICON
IconTextures.fallbackSlotIcon = FALLBACK_SLOT_ICON
IconTextures.fallbackRacialIcon = FALLBACK_RACIAL_ICON
IconTextures.fallbackTotemIcon = FALLBACK_TOTEM_ICON
IconTextures.IsQuestionTexture = IsQuestionTexture
IconTextures.NonQuestionTexture = NonQuestionTexture
IconTextures.GetCustomAuraPresetIconTexture = GetCustomAuraPresetIconTexture
IconTextures.ResolveItemTexture = ResolveItemTexture
IconTextures.ResolveSpellTexture = ResolveSpellTexture
IconTextures.GetStoredIconTexture = GetStoredIconTexture
IconTextures.EnsureStoredIconTexture = EnsureStoredIconTexture
