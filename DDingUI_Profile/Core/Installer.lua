local DUI = unpack(DDingUI_Profile)
local I = DUI:GetModule("Installer")
local SE = DUI:GetModule("Setup")

local function AddonPage(addonName, displayName, setupFunc)
    return function()
        PluginInstallFrame.SubTitle:SetText(displayName)

        if not DUI:IsAddOnEnabled(addonName) then
            PluginInstallFrame.Desc1:SetText(format("%s 애드온이 비활성화 상태입니다.", displayName))
            PluginInstallFrame.Desc2:SetText("이 단계를 건너뛰려면 'Continue'를 클릭하세요.")
            return
        end

        PluginInstallFrame.Desc1:SetText(format("%s 프로필을 적용합니다.", displayName))
        PluginInstallFrame.Option1:Show()
        PluginInstallFrame.Option1:SetScript("OnClick", function()
            if setupFunc then
                setupFunc()
            else
                SE:Setup(addonName, true)
            end
        end)
        PluginInstallFrame.Option1:SetText("적용")
    end
end

-- ElvUI 런타임 감지: 있으면 프로필 적용, 없으면 건너뛰기
local function ElvUIPage()
    PluginInstallFrame.SubTitle:SetText("ElvUI")

    if not ElvUI then
        PluginInstallFrame.Desc1:SetText("ElvUI가 설치되지 않았습니다.")
        PluginInstallFrame.Desc2:SetText("ElvUI 프로필 적용을 건너뜁니다. 'Continue'를 클릭하세요.")
        return
    end

    if not DUI:IsAddOnEnabled("ElvUI") then
        PluginInstallFrame.Desc1:SetText("ElvUI 애드온이 비활성화 상태입니다.")
        PluginInstallFrame.Desc2:SetText("이 단계를 건너뛰려면 'Continue'를 클릭하세요.")
        return
    end

    PluginInstallFrame.Desc1:SetText("ElvUI 프로필을 적용합니다.")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        SE:Setup("ElvUI", true)
    end)
    PluginInstallFrame.Option1:SetText("적용")
end

I.installer = {
    Title = format("%s %s", DUI.title, "|cffffffffProfile|r"),
    Name = DUI.title,
    tutorialImage = "Interface\\AddOns\\DDingUI_Profile\\Media\\Textures\\logo.tga",
    tutorialImagePoint = {0, 40},
    Pages = {
        -- 1. 환영 페이지
        [1] = function()
            PluginInstallFrame.SubTitle:SetFormattedText("%s 프로필 설치", DUI.title)

            if not DUI.db.global.profiles or not next(DUI.db.global.profiles) then
                PluginInstallFrame.Desc1:SetText("DDingUI 프로필 설치를 시작합니다.")
                PluginInstallFrame.Desc2:SetText("'다음'을 클릭하여 각 애드온별 프로필을 설치하세요.")
                return
            end

            PluginInstallFrame.Desc1:SetText("이전에 설치된 프로필을 이 캐릭터에 불러옵니다.")
            PluginInstallFrame.Desc2:SetText("'프로필 불러오기'를 클릭하거나, '다음'으로 다시 설치하세요.")
            PluginInstallFrame.Option1:Show()
            PluginInstallFrame.Option1:SetScript("OnClick", function() DUI:LoadProfiles() end)
            PluginInstallFrame.Option1:SetText("프로필 불러오기")
        end,

        -- 2. ElvUI (선택적)
        [2] = ElvUIPage,

        -- 3. Details
        [3] = AddonPage("Details", "Details!"),

        -- 4. Plater
        [4] = AddonPage("Plater", "Plater Nameplates"),

        -- 5. BigWigs
        [5] = AddonPage("BigWigs", "BigWigs"),

        -- 6. WarpDeplete
        [6] = AddonPage("WarpDeplete", "WarpDeplete"),

        -- 7. DandersFrames (DPS/탱커 + 힐러 선택)
        [7] = function()
            PluginInstallFrame.SubTitle:SetText("DandersFrames")

            if not DUI:IsAddOnEnabled("DandersFrames") then
                PluginInstallFrame.Desc1:SetText("DandersFrames 애드온이 비활성화 상태입니다.")
                PluginInstallFrame.Desc2:SetText("이 단계를 건너뛰려면 '다음'을 클릭하세요.")
                return
            end

            PluginInstallFrame.Desc1:SetText("DandersFrames 프로필을 적용합니다.")
            PluginInstallFrame.Desc2:SetText("역할에 맞는 레이아웃을 선택하세요.")

            PluginInstallFrame.Option1:Show()
            PluginInstallFrame.Option1:SetScript("OnClick", function()
                SE:Setup("DandersFrames", true, "dps")
            end)
            PluginInstallFrame.Option1:SetText("DPS / 탱커")

            PluginInstallFrame.Option2:Show()
            PluginInstallFrame.Option2:SetScript("OnClick", function()
                SE:Setup("DandersFrames", true, "healer")
            end)
            PluginInstallFrame.Option2:SetText("힐러")
        end,

        -- 8. Falcon (Skyriding Falcon)
        [8] = AddonPage("Falcon", "Skyriding Falcon"),

        -- 9. DDingUI
        [9] = AddonPage("DDingUI", "DDingUI"),

        -- 10. 블리자드 편집 모드
        [10] = function()
            PluginInstallFrame.SubTitle:SetText("블리자드 편집 모드")
            PluginInstallFrame.Desc1:SetText("기본 편집 모드 레이아웃을 적용합니다.")
            PluginInstallFrame.Option1:Show()
            PluginInstallFrame.Option1:SetScript("OnClick", function()
                SE:Setup("Blizzard_EditMode", true)
            end)
            PluginInstallFrame.Option1:SetText("적용")
        end,

        -- 11. 전문화별 고급 재사용 대기시간
        [11] = function()
            PluginInstallFrame.SubTitle:SetText("고급 재사용 대기시간")
            PluginInstallFrame.Desc1:SetText("전문화별 고급 재사용 대기시간 레이아웃을 적용합니다.")
            PluginInstallFrame.Option1:Show()
            PluginInstallFrame.Option1:SetScript("OnClick", function()
                SE:Setup("CooldownManager", true)
            end)
            PluginInstallFrame.Option1:SetText("적용")
        end,

        -- 12. 설치 완료
        [12] = function()
            PluginInstallFrame.SubTitle:SetText("설치 완료!")
            PluginInstallFrame.Desc1:SetText("DDingUI 프로필 설치가 완료되었습니다.")
            PluginInstallFrame.Desc2:SetText("'리로드'를 클릭하여 설정을 저장하고 UI를 다시 불러오세요.")
            PluginInstallFrame.Option1:Show()
            PluginInstallFrame.Option1:SetScript("OnClick", function()
                DUI.db.char.loaded = true
                ReloadUI()
            end)
            PluginInstallFrame.Option1:SetText("리로드")
        end,
    },
    StepTitles = {
        [1]  = "환영",
        [2]  = "ElvUI",
        [3]  = "Details!",
        [4]  = "Plater",
        [5]  = "BigWigs",
        [6]  = "WarpDeplete",
        [7]  = "DandersFrames",
        [8]  = "Falcon",
        [9]  = "DDingUI",
        [10] = "편집 모드",
        [11] = "쿨다운 매니저",
        [12] = "설치 완료",
    },
    StepTitlesColor = {1, 1, 1},
    StepTitlesColorSelected = {0, 0.8, 1},
    StepTitleWidth = 200,
    StepTitleButtonWidth = 180,
    StepTitleTextJustification = "RIGHT",
}
