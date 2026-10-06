local ADDON, FX = ...

-- Same launcher and drag persistence as Toolkit/Core/MinimapButton.lua.
function FX:CreateMinimapButton()
    local icons = LibStub("LibDBIcon-1.0")
    if icons:IsRegistered(ADDON) then return end
    local accent = self.Style.GetAccent("FX")
    self.launcher = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON, {
        type="launcher", label="DDingUI FX",
        icon="Interface\\AddOns\\DDingUI_FX\\Media\\logo.tga",
        iconR=accent[1], iconG=accent[2], iconB=accent[3],
        OnClick=function(_,button)
            if button == "LeftButton" then FX:ToggleUI()
            elseif button == "RightButton" then FX:ToggleEditMode() end
        end,
        OnTooltipShow=function(tooltip)
            tooltip:SetText(FX.Style.CreateAddonTitle("FX","FX"))
            tooltip:AddLine("|cffffffff좌클릭|r  설정 창 열기/닫기", 0.7, 0.7, 0.7)
            tooltip:AddLine("|cffffffff우클릭|r  편집 모드 · 위치 조정", 0.7, 0.7, 0.7)
            tooltip:AddLine("|cffffffff드래그|r  버튼 위치 이동", 0.7, 0.7, 0.7)
        end,
    })
    icons:Register(ADDON,self.launcher,self.db.minimap)
    self.minimapButton = icons:GetMinimapButton(ADDON)
    self.minimapButton.icon:SetDesaturated(true)
end
