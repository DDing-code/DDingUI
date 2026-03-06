local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

-- 테이블 딥카피 (원본 D.ddingui 오염 방지)
local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = deepCopy(v)
    end
    return copy
end

function SE.DDingUI(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local profileData = D.ddingui
        if not profileData then
            DUI:Print("DDingUI 프로필 데이터가 없습니다.")
            return
        end

        local ddingAddon = LibStub("AceAddon-3.0"):GetAddon("DDingUI", true)

        -- 문자열 포맷 (DDUI1: 프리픽스)
        if type(profileData) == "string" and profileData ~= "" then
            if ddingAddon and ddingAddon.ImportProfileFromString then
                local ok, err = ddingAddon:ImportProfileFromString(profileData, DUI.profileName)
                if ok then
                    SE.CompleteSetup(addon)
                else
                    DUI:Print("DDingUI 프로필 가져오기 실패: " .. tostring(err))
                end
            else
                DUI:Print("DDingUI 애드온의 ImportProfileFromString 함수를 찾을 수 없습니다.")
            end

        -- 테이블 포맷 (AceDB 직접 할당)
        elseif type(profileData) == "table" then
            local copied = deepCopy(profileData)

            if ddingAddon and ddingAddon.db then
                local db = ddingAddon.db

                -- 프로필 데이터 저장
                DDingUIDB = DDingUIDB or {}
                DDingUIDB.profiles = DDingUIDB.profiles or {}
                DDingUIDB.profiles[DUI.profileName] = copied

                if db.keys.profile == DUI.profileName then
                    -- 같은 프로필이면 db.profile 참조를 새 복사본으로 갱신
                    db.profile = copied
                else
                    db:SetProfile(DUI.profileName)
                end

                -- 즉시 UI 갱신
                if ddingAddon.RefreshAll then
                    ddingAddon:RefreshAll()
                end
                SE.CompleteSetup(addon)
            elseif DDingUIDB then
                -- DDingUI 애드온 객체 없이 SavedVariables만 존재하는 경우
                DDingUIDB.profiles = DDingUIDB.profiles or {}
                DDingUIDB.profiles[DUI.profileName] = copied
                SE.CompleteSetup(addon)
            end
        else
            DUI:Print("DDingUI 프로필 데이터가 유효하지 않습니다.")
        end
    else
        if not SE.IsProfileExisting(DDingUIDB) then
            SE.RemoveFromDatabase(addon)
            return
        end

        local ddingAddon = LibStub("AceAddon-3.0"):GetAddon("DDingUI", true)
        if ddingAddon and ddingAddon.db then
            ddingAddon.db:SetProfile(DUI.profileName)
        end
    end
end
