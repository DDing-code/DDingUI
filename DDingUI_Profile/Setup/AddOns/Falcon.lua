local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.Falcon(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local profileData = D.falcon
        if not profileData or type(profileData) ~= "table" then
            DUI:Print("Falcon 프로필 데이터가 없습니다.")
            return
        end

        if not FalconAddOnDB then FalconAddOnDB = {} end
        if not FalconAddOnDB.Settings then FalconAddOnDB.Settings = {} end

        -- FalconGlobalSettings 적용
        FalconAddOnDB.Settings.FalconGlobalSettings = CopyTable(profileData)
        FalconAddOnDB.FalconGlobalSettingsEnabled = true

        SE.CompleteSetup(addon)
    else
        if not FalconAddOnDB or not FalconAddOnDB.Settings or not FalconAddOnDB.Settings.FalconGlobalSettings then
            SE.RemoveFromDatabase(addon)
            return
        end
        -- 이미 적용됨 (글로벌 설정이므로 프로필 전환 불필요)
    end
end
