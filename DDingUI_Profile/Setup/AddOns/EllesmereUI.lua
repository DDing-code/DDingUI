local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.EllesmereUI(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local profileData = D.ellesmereui
        if type(profileData) ~= "string" or profileData == "" then
            DUI:Print("EllesmereUI 프로필 데이터가 없습니다.")
            return
        end

        if not EllesmereUI or type(EllesmereUI.ImportProfileSilent) ~= "function" then
            DUI:Print("EllesmereUI 가져오기 함수를 찾을 수 없습니다.")
            return
        end

        local ok, err = EllesmereUI.ImportProfileSilent({
            importString = profileData,
            profileName = DUI.profileName,
            cleanSlate = true,
            applyUIScale = true,
            autoAssignSpecs = false,
            disableAddons = {
                "EllesmereUICooldownManager",
            },
        })
        if not ok then
            DUI:Print("EllesmereUI 프로필 가져오기에 실패했습니다: " .. tostring(err))
            return
        end

        SE.CompleteSetup(addon)
    else
        if not EllesmereUIDB or not EllesmereUIDB.profiles or type(EllesmereUIDB.profiles[DUI.profileName]) ~= "table" then
            SE.RemoveFromDatabase(addon)
            return
        end

        if EllesmereUI and type(EllesmereUI.SetProfile) == "function" then
            EllesmereUI.SetProfile(DUI.profileName)
        else
            EllesmereUIDB.activeProfile = DUI.profileName
        end
    end
end
