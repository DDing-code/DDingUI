local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.BigWigs(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local profileData = D.bigwigs
        if not profileData or profileData == "" then
            DUI:Print("BigWigs 프로필 데이터가 없습니다. Data/AddOns/BigWigs.lua에 프로필을 추가해주세요.")
            return
        end

        BigWigsAPI.RegisterProfile(DUI.title, profileData, DUI.profileName, function(callback)
            if callback then
                SE.CompleteSetup(addon)
            end
        end)
    else
        if not BigWigs3DB or not BigWigs3DB.profiles or not BigWigs3DB.profiles[DUI.profileName] then
            SE.RemoveFromDatabase(addon)
            return
        end

        local db = LibStub("AceDB-3.0"):New(BigWigs3DB)
        db:SetProfile(DUI.profileName)
    end
end
