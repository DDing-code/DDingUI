local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

local function CopyTable(source)
    if type(source) ~= "table" then return source end

    local copy = {}
    for key, value in pairs(source) do
        copy[CopyTable(key)] = CopyTable(value)
    end
    return copy
end

local function CharacterKey()
    local name, realm = UnitFullName("player")
    name = name or (UnitName and UnitName("player")) or "Unknown"
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Unknown"
    return name .. " - " .. realm
end

local function SetToolkitProfile(profileName)
    if not DDingUIToolkitDB or type(DDingUIToolkitDB.profiles) ~= "table" then
        return false
    end
    if type(DDingUIToolkitDB.profiles[profileName]) ~= "table" then
        return false
    end

    DDingUIToolkitDB.profileKeys = DDingUIToolkitDB.profileKeys or {}
    DDingUIToolkitDB.profileKeys[CharacterKey()] = profileName
    DDingUIToolkitDB.profile = DDingUIToolkitDB.profiles[profileName]
    return true
end

function SE.DDingUI_Toolkit(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local source = D.ddingui_toolkit
        if type(source) ~= "table" then
            DUI:Print("DDingUI_Toolkit 프로필 데이터가 없습니다.")
            return
        end

        local profileData = source.profiles and (source.profiles[DUI.profileName] or source.profiles.Default) or source.profile
        if type(profileData) ~= "table" then
            DUI:Print("DDingUI_Toolkit 프로필 데이터가 유효하지 않습니다.")
            return
        end

        DDingUIToolkitDB = DDingUIToolkitDB or {}
        DDingUIToolkitDB.profiles = DDingUIToolkitDB.profiles or {}
        DDingUIToolkitDB.profiles[DUI.profileName] = CopyTable(profileData)
        if type(source.global) == "table" then DDingUIToolkitDB.global = CopyTable(source.global) end
        if type(source.char) == "table" then DDingUIToolkitDB.char = CopyTable(source.char) end

        if not SetToolkitProfile(DUI.profileName) then
            DUI:Print("DDingUI_Toolkit 프로필 적용에 실패했습니다.")
            return
        end

        SE.CompleteSetup(addon)
    else
        if not SetToolkitProfile(DUI.profileName) then
            SE.RemoveFromDatabase(addon)
        end
    end
end
