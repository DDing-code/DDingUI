local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- Create namespace
DDingUI.AutoUIScale = DDingUI.AutoUIScale or {}
local AutoUIScale = DDingUI.AutoUIScale

-- Set UI scale for UIParent only
-- Edit Mode viewers are children of UIParent, so they inherit the scale automatically
function AutoUIScale:SetUIScale(scale)
    if not scale or type(scale) ~= "number" then return end

    -- Apply to UIParent only
    if UIParent then
        UIParent:SetScale(scale)
    end
end

function AutoUIScale:ApplySavedScale()
    if DDingUI and DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.general then
        local savedScale = DDingUI.db.profile.general.uiScale
        if savedScale and type(savedScale) == "number" then
            self:SetUIScale(savedScale)
        end
    end
end

function AutoUIScale:Initialize()
    self:ApplySavedScale()

    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:RegisterEvent("PLAYER_LOGIN")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:SetScript("OnEvent", function(frame, event)
            -- Apply scale on login and when entering world
            -- Edit Mode viewers may be created after PLAYER_LOGIN
            AutoUIScale:ApplySavedScale()
        end)
    end
end
