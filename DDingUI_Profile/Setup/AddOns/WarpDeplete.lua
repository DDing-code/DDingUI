local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.WarpDeplete(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local profileData = D.warpdeplete
        if not profileData or type(profileData) ~= "table" then
            DUI:Print("WarpDeplete 프로필 데이터가 없습니다. Data/AddOns/WarpDeplete.lua에 프로필을 추가해주세요.")
            return
        end

        -- WarpDeplete는 직접 테이블 할당 방식
        WarpDepleteDB.profiles[DUI.profileName] = profileData
        WarpDeplete.db:SetProfile(DUI.profileName)
        SE.CompleteSetup(addon)
    else
        if not SE.IsProfileExisting(WarpDepleteDB) then
            SE.RemoveFromDatabase(addon)
            return
        end

        WarpDeplete.db:SetProfile(DUI.profileName)
    end
end
