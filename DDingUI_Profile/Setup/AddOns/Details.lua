local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.Details(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local profileData = D.details
        if not profileData or profileData == "" then
            DUI:Print("Details 프로필 데이터가 없습니다. Data/AddOns/Details.lua에 프로필을 추가해주세요.")
            return
        end

        Details:ImportProfile(profileData, DUI.profileName, false, false, true)
        Details:ApplyProfile(DUI.profileName)
        SE.CompleteSetup(addon)
    else
        if not Details:GetProfile(DUI.profileName) then
            SE.RemoveFromDatabase(addon)
            return
        end

        Details:ApplyProfile(DUI.profileName)
    end
end
