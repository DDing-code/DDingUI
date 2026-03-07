local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.DandersFrames(addon, import, role)
    local D = DUI:GetModule("Data")

    if import then
        local profileData
        local profileLabel

        if role == "healer" then
            profileData = D.dandersframes_healer
            profileLabel = "힐러"
        else
            profileData = D.dandersframes
            profileLabel = "DPS / 탱커"
        end

        if not profileData or profileData == "" then
            DUI:Print(format("DandersFrames %s 프로필 데이터가 없습니다.", profileLabel))
            return
        end

        -- DandersFrames는 !DFP1! 프리픽스 문자열 사용
        local DF = _G.DandersFrames or _G.DF

        if DF and DF.ImportProfile then
            -- 문자열 import (카테고리 전체 적용)
            local importData = DF:ValidateImportString(profileData)
            if importData then
                local allCategories = {
                    "position", "layout", "bars", "auras",
                    "text", "icons", "other"
                }
                local allFrameTypes = importData.frameTypes or {}
                local name = DUI.profileName
                if role == "healer" then
                    name = name .. " - Healer"
                end
                DF:ApplyImportedProfile(importData, allCategories, allFrameTypes, name, true)
                DF:SetProfile(name)
                SE.CompleteSetup(addon)
            else
                DUI:Print("DandersFrames 프로필 데이터가 유효하지 않습니다.")
            end
        else
            -- 대안: SavedVariables 직접 할당
            if DandersFramesDB_v2 and type(D.dandersframes_raw) == "table" then
                DandersFramesDB_v2.profiles[DUI.profileName] = D.dandersframes_raw
                SE.CompleteSetup(addon)
            end
        end
    else
        if not DandersFramesDB_v2 or not DandersFramesDB_v2.profiles or not DandersFramesDB_v2.profiles[DUI.profileName] then
            SE.RemoveFromDatabase(addon)
            return
        end

        local DF = _G.DandersFrames or _G.DF
        if DF and DF.SetProfile then
            DF:SetProfile(DUI.profileName)
        end
    end
end
