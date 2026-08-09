local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

local function SetActiveProfileKey(profileName)
    UUFDB = UUFDB or {}
    UUFDB.profileKeys = UUFDB.profileKeys or {}
    UUFDB.global = UUFDB.global or {}

    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if name and realm and name ~= "" and realm ~= "" then
        UUFDB.profileKeys[name .. " - " .. realm] = profileName
    end

    if UUFDB.global.UseGlobalProfile then
        UUFDB.global.GlobalProfile = profileName
        UUFDB.global.GlobalProfileName = profileName
    end
end

function SE.UnhaltedUnitFrames(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local profileData = D.uuf
        if not profileData or profileData == "" then
            DUI:Print("UnhaltedUnitFrames 프로필 데이터가 없습니다.")
            return
        end

        if not _G.UUFG or type(_G.UUFG.ImportUUF) ~= "function" then
            DUI:Print("UnhaltedUnitFrames 가져오기 함수를 찾을 수 없습니다.")
            return
        end

        _G.UUFG:ImportUUF(profileData, DUI.profileName)
        SetActiveProfileKey(DUI.profileName)

        if not UUFDB or not UUFDB.profiles or type(UUFDB.profiles[DUI.profileName]) ~= "table" then
            DUI:Print("UnhaltedUnitFrames 프로필 가져오기에 실패했습니다.")
            return
        end

        SE.CompleteSetup(addon)
    else
        if not UUFDB or not UUFDB.profiles or type(UUFDB.profiles[DUI.profileName]) ~= "table" then
            SE.RemoveFromDatabase(addon)
            return
        end

        SetActiveProfileKey(DUI.profileName)
    end
end
