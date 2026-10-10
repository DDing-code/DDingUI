local addonName, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local BUTTON_KEY = "DDingUI_RaidHelper"
local BRAND_ICON = "Interface\\AddOns\\DDingUI_RaidHelper\\Media\\RaidHelper_Icon.tga"

function MinimapButton:Initialize()
    if self.initialized then return end

    local libStub = _G.LibStub
    local LDB = libStub and libStub("LibDataBroker-1.1", true)
    local LibDBIcon = libStub and libStub("LibDBIcon-1.0", true)
    if not LDB or not LibDBIcon or not ns.db or not ns.db.minimap then return end

    local dataObject = LDB:NewDataObject(BUTTON_KEY, {
        type = "launcher",
        icon = BRAND_ICON,
        -- Keep LibDBIcon's default coordinates, matching Toolkit. LibDBIcon
        -- already applies its own mouse-up crop; an additional crop here made
        -- the custom icon stay visibly enlarged after every click.
        label = "DDingUI RaidHelper",
        OnClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                if ns.TimelineUI and ns.TimelineUI.ToggleEditMode then
                    ns.TimelineUI:ToggleEditMode()
                end
            elseif mouseButton == "LeftButton" and ns.Options then
                ns.Options:Toggle()
            end
        end,
        OnTooltipShow = function(tooltip)
            local styleLib = ns.GetStyleLib and ns:GetStyleLib()
                or _G.DDingUI_RaidHelperStyleLib -- [REFACTOR] private embedded copy only
            local title = styleLib and styleLib.CreateAddonTitle
                and styleLib.CreateAddonTitle("RaidHelper", "RaidHelper")
                or "DDingUI RaidHelper"
            tooltip:SetText(title)
            tooltip:AddLine("|cffffffff좌클릭|r  설정 창 열기/닫기", 0.7, 0.7, 0.7)
            tooltip:AddLine("|cffffffff우클릭|r  편집 모드 · 위치 조정", 0.7, 0.7, 0.7)
            tooltip:AddLine("|cffffffff드래그|r  버튼 위치 이동", 0.7, 0.7, 0.7)
        end,
    })
    if not dataObject then return end

    LibDBIcon:Register(BUTTON_KEY, dataObject, ns.db.minimap)

    self.dataObject = dataObject
    self.lib = LibDBIcon
    self.button = LibDBIcon:GetMinimapButton(BUTTON_KEY)
    self.initialized = true
end

function MinimapButton:SetShown(shown)
    if not self.lib or not ns.db or not ns.db.minimap then return false end
    ns.db.minimap.hide = shown ~= true
    if shown then
        self.lib:Show(BUTTON_KEY)
    else
        self.lib:Hide(BUTTON_KEY)
    end
    return true
end

function MinimapButton:ResetPosition()
    if not self.lib or not ns.db or not ns.db.minimap then return false end
    ns.db.minimap.minimapPos = 225
    self.lib:Refresh(BUTTON_KEY, ns.db.minimap)
    return true
end
