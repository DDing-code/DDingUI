local DUI = unpack(DDingUI_Profile)
local SE = DUI:GetModule("Setup")

function SE.Blizzard_EditMode(addon, import)
    local D = DUI:GetModule("Data")

    if import then
        local layoutData = D.blizzard_editmode
        if not layoutData or layoutData == "" then
            DUI:Print("편집 모드 레이아웃 데이터가 없습니다.")
            return
        end

        -- [12.0.1] 공통 복사 프레임 헬퍼 사용
        DUI:ShowCopyFrame(
            "editModeFrame",
            "DDingUIEditModeFrame",
            "|cffffffffDDing|r|cffffa300UI|r - 편집 모드 레이아웃",
            "|cff00ff00Ctrl+A|r → |cff00ff00Ctrl+C|r 로 복사 후\n|cffffd200Esc > 편집 모드 > 레이아웃 > 가져오기|r 에서 붙여넣기",
            layoutData
        )
        SE.CompleteSetup(addon)
    end
end
