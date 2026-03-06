local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

-- 고급 재사용 대기시간 관리자 (Cooldown Manager) Setup 함수
function SE.CooldownManager(addon, import)
    if import then
        local specID = DUI:GetPlayerSpecID()
        if not specID then
            DUI:Print("전문화 정보를 가져올 수 없습니다.")
            SE.CompleteSetup(addon)
            return
        end

        local D = DUI:GetModule("Data")
        if not D.specProfiles or not D.specProfiles[specID] then
            DUI:Print(format("현재 전문화(specID: %s)의 고급 재사용 대기시간 데이터가 없습니다.", tostring(specID)))
            SE.CompleteSetup(addon)
            return
        end

        -- [12.0.1] 공통 복사 프레임 헬퍼 사용
        DUI:ShowCopyFrame(
            "cdmFrame",
            "DDingUICDMFrame",
            "|cffffffffDDing|r|cffffa300UI|r - 고급 재사용 대기시간",
            "|cff00ff00Ctrl+A|r → |cff00ff00Ctrl+C|r 로 복사 후  |cffffd200고급 재사용 대기시간 설정 > 가져오기|r 에서 붙여넣기",
            D.specProfiles[specID]
        )
        SE.CompleteSetup(addon)
    end
end
