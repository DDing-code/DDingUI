--[[
    DDingToolKit - Minimap Button
    LibDBIcon-1.0 기반 미니맵 버튼
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
function DDingToolKit:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)

    if not LDB or not LibDBIcon then
        return
    end

    if not ns.db or not ns.db.profile.minimap then
        return
    end

    local dataObj = LDB:NewDataObject(addonName, {
        type = "launcher",
        icon = "Interface\\AddOns\\DDingUI_Toolkit\\logo",
        label = "DDingUI Toolkit",
        OnClick = function(clickedframe, button)
            if button == "LeftButton" then
                DDingToolKit:ToggleConfig()
            elseif button == "RightButton" then
                if ns.ToolkitMovers and ns.ToolkitMovers.ToggleConfigMode then
                    ns.ToolkitMovers:ToggleConfigMode()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            local SL = _G.DDingUI_StyleLib -- [STYLE]
            local title = (SL and SL.CreateAddonTitle) and SL.CreateAddonTitle("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r Toolkit"
            tooltip:SetText(title)
            local ko = GetLocale() == "koKR"
            tooltip:AddLine(ko and "|cffffffff좌클릭|r  설정 창 열기/닫기" or "|cffffffffLeft-click|r  Toggle settings", 0.7, 0.7, 0.7)
            tooltip:AddLine(ko and "|cffffffff우클릭|r  편집 모드 · 위치 조정" or "|cffffffffRight-click|r  Edit mode / adjust position", 0.7, 0.7, 0.7)
            tooltip:AddLine(ko and "|cffffffff드래그|r  버튼 위치 이동" or "|cffffffffDrag|r  Move button", 0.7, 0.7, 0.7)
        end,
    })

    LibDBIcon:Register(addonName, dataObj, ns.db.profile.minimap)
    ns.LibDBIcon = LibDBIcon
end

function DDingToolKit:UpdateMinimapButton()
    local LibDBIcon = ns.LibDBIcon
    if not LibDBIcon then return end

    if ns.db.profile.minimap.hide then
        LibDBIcon:Hide(addonName)
    else
        LibDBIcon:Show(addonName)
    end
end
