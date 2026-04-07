local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupPool = {}
DDingUI.GroupPool = GroupPool

local CreateFrame = CreateFrame
local UIParent = UIParent

GroupPool.frames = {}

function GroupPool:GetContainer(groupName)
    if self.frames[groupName] then return self.frames[groupName] end
    
    local frame = CreateFrame("Frame", "DDingUI_Group_" .. groupName, UIParent)
    frame._groupName = groupName
    
    local gs = DDingUI.GroupSystem and DDingUI.GroupSystem.db
    local settings = gs and gs.groups and gs.groups[groupName]
    
    frame:SetSize(200, 50)
    frame:SetFrameStrata("MEDIUM")
    
    -- Create or fetch proxy anchor for correct dependency resolution
    local proxyName = "DDingUI_Anchor_" .. groupName
    local proxy = _G[proxyName]
    if not proxy then
        proxy = CreateFrame("Frame", proxyName, UIParent)
        proxy:SetSize(2, 2)
        
        if settings then
            local attachTo = settings.attachTo or "UIParent"
            local anchorFrame = _G[attachTo] or UIParent
            local selfPt = settings.selfPoint or "CENTER"
            local anchorPt = settings.anchorPoint or "CENTER"
            local offsetX = settings.offsetX or 0
            local offsetY = settings.offsetY or 0
            
            proxy:SetPoint(selfPt, anchorFrame, anchorPt, offsetX, offsetY)
        else
            proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    
    -- Bind actual container to the proxy anchor
    frame:SetPoint("CENTER", proxy, "CENTER", 0, 0)
    
    -- Sync proxy size for EditMode clickability
    proxy:SetSize(frame:GetSize())
    hooksecurefunc(frame, "SetSize", function(_, w, h)
        if w > 0 and h > 0 then
            proxy:SetSize(w, h)
        end
    end)
    
    self.frames[groupName] = frame
    return frame
end

function GroupPool:HideGroup(groupName)
    local frame = self.frames[groupName]
    if frame and not InCombatLockdown() then
        frame:Hide()
    end
end
