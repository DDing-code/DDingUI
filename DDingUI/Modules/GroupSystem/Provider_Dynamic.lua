local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Provider_Dynamic = {}
DDingUI.Provider_Dynamic = Provider_Dynamic

local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown

-- Hooked frames mapping
local hookedIcons = {}

function Provider_Dynamic:Initialize()
    if self.initialized then return end
    
    local engine = DDingUI.GroupEngine
    if not engine then return end
    
    engine:RegisterProvider("Dynamic", self)
    
    -- Delay CustomIcons load to suppress its native layout
    C_Timer.After(1, function()
        if DDingUI.CustomIcons then
            -- Override original layout
            DDingUI.CustomIcons.LayoutGroup = function() end
            DDingUI.CustomIcons.LayoutAllGroups = function() end
            
            -- Hook aura updates to trigger our engine
            hooksecurefunc(DDingUI.CustomIcons, "UpdateAllSpells", function()
                if DDingUI.GroupEngine then
                    DDingUI.GroupEngine:RequestUpdateAll(0.05)
                end
            end)
        end
    end)
    
    self.initialized = true
end

-- ============================================================
-- Core Visibility Check
-- ============================================================
local function IsIconActive(iconKey, iconData)
    if not iconData then return false end
    
    -- Aura buff checking
    if iconData.type == "aura" and iconData.id then
        local auraData = nil
        pcall(function() auraData = C_UnitAuras.GetPlayerAuraBySpellID(iconData.id) end)
        if not auraData then return false end
    end
    
    -- Load Conditions
    local settings = iconData.settings
    if settings and settings.loadConditions and settings.loadConditions.enabled then
        local lc = settings.loadConditions
        if lc.specs then
            local anySpecSet = false
            for _, v in pairs(lc.specs) do
                if v then anySpecSet = true; break end
            end
            if anySpecSet then
                local currentSpec = GetSpecialization and GetSpecialization() or 0
                local specID = currentSpec and GetSpecializationInfo and GetSpecializationInfo(currentSpec) or 0
                if not lc.specs[specID] then return false end
            end
        end
        if lc.inCombat and not InCombatLockdown() then return false end
        if lc.outOfCombat and InCombatLockdown() then return false end
    end
    
    return true
end

-- ============================================================
-- Engine Provider Interface
-- ============================================================
local function HookDynamicIcon(icon, iconKey)
    if not icon or hookedIcons[icon] then return end
    hookedIcons[icon] = true
    
    -- Taint-safe hijacking
    if icon:GetParent() ~= UIParent then
        icon:SetParent(UIParent)
    end
    
    icon._ddIconKey = iconKey
end

function Provider_Dynamic:GetIconsForGroup(groupName, settings)
    if not DDingUI.CustomIcons then return nil end
    
    local profile = DDingUI.db and DDingUI.db.profile
    if not profile or not profile.dynamicIcons then return nil end
    
    local db = profile.dynamicIcons
    local iconFrames = DDingUI.CustomIcons:GetAllIconFrames() or {}
    
    -- Check if dynamic source maps to this group
    local sourceKey = settings.sourceGroupKey
    if not sourceKey then return nil end
    
    local targetKeys = {}
    if sourceKey == "ungrouped" then
        for iconKey in pairs(db.ungrouped or {}) do targetKeys[iconKey] = true end
    else
        local group = db.groups and db.groups[sourceKey]
        if group and group.icons then
            for _, iconKey in ipairs(group.icons) do targetKeys[iconKey] = true end
        end
    end
    
    local isEditMode = (DDingUI.Movers and DDingUI.Movers.ConfigMode)
    
    local result = {}
    for iconKey in pairs(targetKeys) do
        local frame = iconFrames[iconKey]
        local iconData = db.iconData and db.iconData[iconKey]
        
        if frame and iconData and (isEditMode or IsIconActive(iconKey, iconData)) then
            if not hookedIcons[frame] then
                HookDynamicIcon(frame, iconKey)
            end
            
            -- Dynamic icons are forced to show by the engine later, 
            -- but we MUST strip custom scale/size overrides first
            frame.layoutIndex = db.groups[sourceKey] and db.groups[sourceKey].icons and table.indexof(db.groups[sourceKey].icons, iconKey) or 0
            
            result[#result + 1] = frame
        end
    end
    
    return result
end
