local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.ElvUI(addon, import)
    -- [12.0.1] ElvUI가 없으면 건너뛰기
    if not ElvUI then
        DUI:Print("ElvUI가 설치되지 않아 ElvUI 프로필 적용을 건너뜁니다.")
        return
    end

    local D = DUI:GetModule("Data")
    local E = unpack(ElvUI)
    local DI = E:GetModule("Distributor")

    if import then
        local profileData = D.elvui
        if not profileData or profileData == "" then
            DUI:Print("ElvUI 프로필 데이터가 없습니다. Data/AddOns/ElvUI.lua에 프로필을 추가해주세요.")
            return
        end

        local profileType, profileKey, profileData = DI:Decode(profileData)
        DI:SetImportedProfile(profileType, DUI.profileName, profileData, true)
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
