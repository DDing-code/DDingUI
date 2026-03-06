local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

-- 메인 디스패처: 각 애드온별 Setup 함수 호출
function SE:Setup(addon, ...)
    local setup = self[addon]

    if not setup then
        DUI:Print(format("'%s' Setup 함수를 찾을 수 없습니다.", addon))
        return
    end

    setup(addon, ...)
end

-- 프로필 설치 완료 마킹
function SE.CompleteSetup(addon)
    DUI.db.global.profiles[addon] = true
    DUI.db.global.version = DUI.version
    DUI:Print(format("|cff00ff00%s|r 프로필 적용 완료!", addon))
end

-- 프로필 존재 여부 확인 (AceDB 기반 애드온용)
function SE.IsProfileExisting(savedVarTable)
    if not savedVarTable or not savedVarTable.profiles then return false end
    return savedVarTable.profiles[DUI.profileName] ~= nil
end

-- 프로필 데이터베이스에서 제거
function SE.RemoveFromDatabase(addon)
    DUI.db.global.profiles[addon] = nil
end
