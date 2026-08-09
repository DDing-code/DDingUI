local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

local function SetCurrentProfile(profileName)
    if type(PLATYNATOR_CONFIG) ~= "table" or type(PLATYNATOR_CONFIG.Profiles) ~= "table" then
        return false
    end
    if type(PLATYNATOR_CONFIG.Profiles[profileName]) ~= "table" then
        return false
    end

    PLATYNATOR_CURRENT_PROFILE = profileName
    return true
end

local function ImportString(importString, importName)
    if type(importString) ~= "string" or importString == "" then
        return false, "empty"
    end
    if not Platynator or not Platynator.API or type(Platynator.API.ImportString) ~= "function" then
        return false, "missing api"
    end

    local ok, err = pcall(Platynator.API.ImportString, importString, importName)
    if not ok then
        return false, err
    end
    return true
end

function SE.Platynator(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local ok, err = ImportString(D.platynator_profile, DUI.profileName)
        if not ok then
            DUI:Print("Platynator 프로필 가져오기에 실패했습니다: " .. tostring(err))
            return
        end

        ok, err = ImportString(D.platynator_style, DUI.profileName)
        if not ok then
            DUI:Print("Platynator 스타일 가져오기에 실패했습니다: " .. tostring(err))
            return
        end

        SetCurrentProfile(DUI.profileName)
        SE.CompleteSetup(addon)
    else
        if not SetCurrentProfile(DUI.profileName) then
            SE.RemoveFromDatabase(addon)
        end
    end
end
