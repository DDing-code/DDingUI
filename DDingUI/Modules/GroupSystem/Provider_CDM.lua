-- LEGACY / NOT LOADED: DDingUI.toc does not load this file.
-- Active GroupSystem path: FrameController -> GroupManager -> GroupRenderer -> DynamicIconBridge -> GroupInit.
local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Provider_CDM = {}
DDingUI.Provider_CDM = Provider_CDM

local pairs = pairs
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local wipe = wipe

local VIEWERS = {
    { globalName = "EssentialCooldownViewer", targetGroup = "Cooldowns" },
    { globalName = "UtilityCooldownViewer",   targetGroup = "Utility"   },
    { globalName = "BuffIconCooldownViewer",  targetGroup = "Buffs"     },
}

local viewerRefs = {}
local hookedIcons = {}

-- ============================================================
-- Initialization
-- ============================================================
function Provider_CDM:Initialize()
    if self.initialized then return end
    
    local engine = DDingUI.GroupEngine
    if not engine then return end
    
    engine:RegisterProvider("CDM", self)
    self:HookViewers()
    self:InstallSpecHooks()
    
    self.initialized = true
end

-- ============================================================
-- Hook Engine
-- ============================================================
local function OnIconShowHide(icon)
    if not icon._ddTargetGroup then return end
    if DDingUI.GroupEngine then
        -- Trigger engine layout recalculation without forcing icon state
        DDingUI.GroupEngine:RequestUpdate(icon._ddTargetGroup, 0.05)
    end
end

local function HookIcon(icon, targetGroup)
    if not icon or hookedIcons[icon] then return end
    hookedIcons[icon] = true
    
    icon._ddTargetGroup = targetGroup
    
    -- Combate-safe Hijacking: Parent to UIParent directly
    if icon:GetParent() ~= UIParent then
        icon:SetParent(UIParent)
    end
    
    icon:HookScript("OnShow", function(self) OnIconShowHide(self) end)
    icon:HookScript("OnHide", function(self) OnIconShowHide(self) end)
end

function Provider_CDM:HookViewers()
    for _, def in pairs(VIEWERS) do
        local viewer = _G[def.globalName]
        if viewer and viewer.itemFramePool then
            viewerRefs[def.globalName] = { viewer = viewer, group = def.targetGroup }
            
            -- Hook Acquire/Release
            hooksecurefunc(viewer.itemFramePool, "Acquire", function()
                if DDingUI.GroupEngine then
                    DDingUI.GroupEngine:RequestUpdate(def.targetGroup, 0)
                end
            end)
            hooksecurefunc(viewer.itemFramePool, "Release", function()
                if DDingUI.GroupEngine then
                    DDingUI.GroupEngine:RequestUpdate(def.targetGroup, 0)
                end
            end)
            
            -- Hook existing active icons
            for icon in viewer.itemFramePool:EnumerateActive() do
                HookIcon(icon, def.targetGroup)
            end
        end
    end
end

-- ============================================================
-- Spec/Talent Change Handling (Ayije 3-tier Queue)
-- ============================================================
function Provider_CDM:InstallSpecHooks()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    eventFrame:SetScript("OnEvent", function(_, event)
        if not DDingUI.GroupEngine then return end
        
        if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LEVEL_UP" then
            -- 3-tier delayed retry for heavy spec changes
            DDingUI.GroupEngine:RequestUpdateAll(0.3)
            C_Timer.After(1.0, function() DDingUI.GroupEngine:RequestUpdateAll(0) end)
            C_Timer.After(1.5, function() 
                Provider_CDM:HookViewers() -- Refresh refs just in case
                DDingUI.GroupEngine:RequestUpdateAll(0) 
            end)
            C_Timer.After(3.0, function() DDingUI.GroupEngine:RequestUpdateAll(0) end) -- Final parity check
        elseif event == "TRAIT_CONFIG_UPDATED" then
            DDingUI.GroupEngine:RequestUpdateAll(0.6)
        else
            DDingUI.GroupEngine:RequestUpdateAll(0.05)
        end
    end)
end

-- ============================================================
-- Engine Provider Interface
-- ============================================================
function Provider_CDM:GetIconsForGroup(groupName, settings)
    local icons = {}
    local count = 0
    
    for _, ref in pairs(viewerRefs) do
        if ref.group == groupName then
            local viewer = ref.viewer
            if viewer and viewer.itemFramePool then
                for icon in viewer.itemFramePool:EnumerateActive() do
                    if not hookedIcons[icon] then
                        HookIcon(icon, groupName)
                    end
                    
                    -- Ayije filtering relies on IsShown(). 
                    -- Dynamic Engine forces Show, but CDM must respect native IsShown.
                    if icon:IsShown() and not icon._ddingHidden then
                        count = count + 1
                        icons[count] = icon
                    end
                end
            end
        end
    end
    
    return icons
end
