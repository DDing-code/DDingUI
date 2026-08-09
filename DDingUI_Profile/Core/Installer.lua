local DUI = unpack(DDingUI_Profile)
local I = DUI:GetModule("Installer")
local SE = DUI:GetModule("Setup")

local DDINGUI_PROFILE_TITLE = format("%s %s", DUI.title, "|cffffffffProfile|r")

local function AddonPage(addonName, displayName, setupFunc)
    return function()
        PluginInstallFrame.SubTitle:SetText(displayName)

        if not DUI:IsAddOnEnabled(addonName) then
            PluginInstallFrame.Desc1:SetText(format("%s 애드온이 비활성화 상태입니다.", displayName))
            PluginInstallFrame.Desc2:SetText("이 단계를 건너뛰려면 '다음'을 클릭하세요.")
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

I.installer = {
    Title = DDINGUI_PROFILE_TITLE,
    Name = DDINGUI_PROFILE_TITLE,
    tutorialImage = "Interface\\AddOns\\DDingUI_Profile\\Media\\Textures\\logo.tga",
    tutorialImagePoint = {0, 40},
    Pages = {
        -- 1. 환영 페이지
        [1] = function()
            PluginInstallFrame.SubTitle:SetFormattedText("%s 설치", DDINGUI_PROFILE_TITLE)

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

        -- 2. BigWigs
        [2] = AddonPage("BigWigs", "BigWigs"),

        -- 3. DDingUI_CDM
        [3] = AddonPage("DDingUI", "DDingUI_CDM"),

        -- 4. DDingUI_Toolkit
        [4] = AddonPage("DDingUI_Toolkit", "DDingUI_Toolkit"),

        -- 5. EllesmereUI
        [5] = AddonPage("EllesmereUI", "EllesmereUI"),

        -- 6. WarpDeplete
        [6] = AddonPage("WarpDeplete", "WarpDeplete"),

        -- 7. Platynator
        [7] = AddonPage("Platynator", "Platynator"),

        -- 8. 설치 완료
        [8] = function()
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
        [2]  = "BigWigs",
        [3]  = "DDingUI_CDM",
        [4]  = "DDingUI_Toolkit",
        [5]  = "EllesmereUI",
        [6]  = "WarpDeplete",
        [7]  = "Platynator",
        [8]  = "설치 완료",
    },
    StepTitlesColor = {1, 1, 1},
    StepTitlesColorSelected = {0, 0.8, 1},
    StepTitleWidth = 200,
    StepTitleButtonWidth = 180,
    StepTitleTextJustification = "RIGHT",
}
