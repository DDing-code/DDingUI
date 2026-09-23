local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")
local PROFILE_NAME = "DDing_UI"

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
            profileName = PROFILE_NAME,
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
        if not EllesmereUIDB or not EllesmereUIDB.profiles or type(EllesmereUIDB.profiles[PROFILE_NAME]) ~= "table" then
            SE.RemoveFromDatabase(addon)
            return
        end

        if EllesmereUI and type(EllesmereUI.SetProfile) == "function" then
            EllesmereUI.SetProfile(PROFILE_NAME)
        else
            EllesmereUIDB.activeProfile = PROFILE_NAME
        end
    end
end
