local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.Plater(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local profileData = D.plater
        if not profileData or profileData == "" then
            DUI:Print("Plater 프로필 데이터가 없습니다. Data/AddOns/Plater.lua에 프로필을 추가해주세요.")
            return
        end

        -- Plater 프로필 생성 후 스크립트 컴파일 훅
        SE:RawHook(Plater, "OnProfileCreated", function(...)
            SE.hooks[Plater]["OnProfileCreated"](...)
            Plater.ImportScriptsFromLibrary()
            Plater.ApplyPatches()
            C_Timer.After(1, function()
                Plater.CompileAllScripts("script")
                Plater.CompileAllScripts("hook")
            end)
            SE:Unhook(Plater, "OnProfileCreated")
        end, true)

        Plater.ImportAndSwitchProfile(DUI.profileName, profileData, false, false, true, true)
        Plater.db:SetProfile(DUI.profileName)
        SE.CompleteSetup(addon)
    else
        if not SE.IsProfileExisting(PlaterDB) then
            SE.RemoveFromDatabase(addon)
            return
        end

        Plater.db:SetProfile(DUI.profileName)
    end
end
