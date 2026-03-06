--[[
    DDingToolKit - Minimap Button
    LibDBIcon-1.0 기반 미니맵 버튼
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L

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
                DDingToolKit:ToggleConfig()
            end
        end,
        OnTooltipShow = function(tooltip)
            local SL = _G.DDingUI_StyleLib -- [STYLE]
            local title = (SL and SL.CreateAddonTitle) and SL.CreateAddonTitle("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r Toolkit"
            tooltip:SetText(title)
            tooltip:AddLine("|cffffffffLeft-click|r  " .. (L["MINIMAP_LEFT_CLICK"] or "Open settings"), 0.7, 0.7, 0.7)
            tooltip:AddLine("|cffffffffDrag|r  " .. (L["MINIMAP_DRAG"] or "Move button"), 0.7, 0.7, 0.7)
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
