local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local GroupStyle = {}
DDingUI.GroupStyle = GroupStyle

local pcall = pcall

function GroupStyle:ApplyToGroup(icons, settings)
    if not icons or #icons == 0 then return end
    
    local viewers = DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.viewers
    
    for _, icon in ipairs(icons) do
        local alpha = 1.0
        local fh = DDingUI.FlightHide
        if fh and fh.IsFadedOrFading and fh:IsFadedOrFading() then
            alpha = (fh.GetCurrentAlpha and fh:GetCurrentAlpha()) or 0.0
        elseif fh and fh.isActive then
            alpha = 0.0
        end
        icon:SetAlpha(alpha)
        
        -- 2. Skinning (Bridge to existing IconViewers)
        if DDingUI.IconViewers and DDingUI.IconViewers.SkinIcon then
            local viewerName = icon._ddSourceViewer or "EssentialCooldownViewer"
            local skinSettings = viewers and viewers[viewerName]
            if skinSettings then
                -- Safe pcall to prevent Blizzard hook errors from crashing the engine
                pcall(DDingUI.IconViewers.SkinIcon, DDingUI.IconViewers, icon, skinSettings, settings)
            end
        end
    end
end
