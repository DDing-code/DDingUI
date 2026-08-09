local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

local ELVUI_IMPORTS = {
    { key = "elvui", name = "profile" },
    { key = "elvui_private", name = "private" },
    { key = "elvui_global", name = "global" },
    { key = "elvui_filters", name = "filters" },
}

local function ImportElvUIString(DI, dataString)
    local profileType, profileKey, profileData = DI:Decode(dataString)
    if not profileType or not profileData then
        return false
    end

    if profileType == "profile" then
        DI:SetImportedProfile(profileType, DUI.profileName, profileData, true)
    else
        DI:SetImportedProfile(profileType, profileKey, profileData, true)
    end

    return true
end

function SE.ElvUI(addon, import)
    if not ElvUI then
        DUI:Print("ElvUI is not installed. Skipping ElvUI profile setup.")
        return
    end

    local D = DUI:GetModule("Data")
    local E = unpack(ElvUI)
    local DI = E:GetModule("Distributor")

    if import then
        for _, entry in ipairs(ELVUI_IMPORTS) do
            local profileData = D[entry.key]
            if not profileData or profileData == "" then
                DUI:Print(format("ElvUI %s import data is missing. Check Data/AddOns/ElvUI.lua.", entry.name))
                return
            end

            if not ImportElvUIString(DI, profileData) then
                DUI:Print(format("ElvUI %s import data is invalid or corrupted.", entry.name))
                return
            end
        end

        E.data:SetProfile(DUI.profileName)
        SE.CompleteSetup(addon)
    else
        if not SE.IsProfileExisting(ElvDB) then
            SE.RemoveFromDatabase(addon)
            return
        end

        E.data:SetProfile(DUI.profileName)
    end
end
