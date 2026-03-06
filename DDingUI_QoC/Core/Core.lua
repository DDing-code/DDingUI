--[[
    DDingQoC - Core
    메인 초기화 및 모듈 관리자
]]

local addonName, ns = ...

-- 전역 애드온 테이블
local DDingQoC = {}
_G.DDingQoC = DDingQoC
_G.DDingToolKit = DDingQoC -- 하위 호환
ns.DDingQoC = DDingQoC
ns.DDingToolKit = DDingQoC -- 하위 호환
ns.MJToolkit = DDingQoC

-- 버전 정보
DDingQoC.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"
local SL = _G.DDingUI_StyleLib
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cd93380ffQoC|r: "

DDingQoC.addonName = addonName

-- 모듈 레지스트리
DDingQoC.modules = {}
ns.modules = DDingQoC.modules


-- 모듈 등록
function DDingQoC:RegisterModule(name, module)
    self.modules[name] = module
    module.name = name
    module.enabled = false
end

-- 모듈 가져오기
function DDingQoC:GetModule(name)
    return self.modules[name]
end

-- 모듈이 활성화되어 있는지 확인
function DDingQoC:IsModuleEnabled(name)
    local module = self.modules[name]
    return module and module.enabled
end

-- 초기화
function DDingQoC:OnInitialize()
    -- 데이터베이스 초기화
    ns:InitDB()

    -- 모듈 초기화 (활성화된 것만)
    for name, module in pairs(self.modules) do
        if ns.db.profile.modules[name] ~= false then
            if module.OnInitialize then
                module:OnInitialize()
            end
        end
    end

    -- 미니맵 버튼 생성 (LibDBIcon)
    self:CreateMinimapButton()
end

-- 활성화
function DDingQoC:OnEnable()
    -- 모듈 활성화 (활성화된 것만)
    for name, module in pairs(self.modules) do
        if ns.db.profile.modules[name] ~= false then
            if module.OnEnable then
                module:OnEnable()
            end
            module.enabled = true
        end
    end

    -- 환영 메시지
    if ns.db.profile.welcomeMessage then
        print(CHAT_PREFIX .. "v" .. self.version .. " loaded.") -- [STYLE]
    end
end

-- 설정 창 열기 -- [REFACTOR] ns.MainFrame → ns.ConfigUI
function DDingQoC:OpenConfig(tab)
    if not ns.ConfigUI then return end
    if tab then
        ns.ConfigUI:SelectModule(tab)
    else
        ns.ConfigUI:Show()
    end
end

-- 설정 창 닫기 -- [REFACTOR]
function DDingQoC:CloseConfig()
    if not ns.ConfigUI then return end
    ns.ConfigUI:Hide()
end

-- 설정 창 토글 -- [REFACTOR]
function DDingQoC:ToggleConfig()
    if not ns.ConfigUI then return end
    ns.ConfigUI:Toggle()
end

-- 리로드 UI 확인 다이얼로그
StaticPopupDialogs["DDINGQOC_RELOAD_UI"] = {
    text = "",  -- 런타임에 설정
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- 모듈 활성화
function DDingQoC:EnableModule(name)
    if not self.modules[name] then return false end
    ns.db.profile.modules[name] = true
    return true
end

-- 모듈 비활성화
function DDingQoC:DisableModule(name)
    if not self.modules[name] then return false end
    ns.db.profile.modules[name] = false
    return true
end

-- 모듈 토글 (리로드 확인 포함)
function DDingQoC:ToggleModule(name, enable)
    ns.db.profile.modules[name] = enable

    -- 리로드 확인
    local L = ns.L
    StaticPopupDialogs["DDINGQOC_RELOAD_UI"].text = L["RELOAD_UI_CONFIRM"]
    StaticPopup_Show("DDINGQOC_RELOAD_UI")
end

-- 이벤트 프레임
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        DDingQoC:OnInitialize()
        print(CHAT_PREFIX .. "v" .. DDingQoC.version .. " loaded. Type |cFFFFFF00/qoc|r to configure.") -- [STYLE]

    elseif event == "PLAYER_LOGIN" then
        DDingQoC:OnEnable()

        -- [CONTROLLER] MediaChanged 콜백 등록
        local SL = _G.DDingUI_StyleLib
        if SL and SL.RegisterCallback then
            SL.RegisterCallback(DDingQoC, "MediaChanged", function()
                -- 활성 모듈 갱신
                for name, module in pairs(DDingQoC.modules) do
                    if module.enabled and module.OnMediaChanged then
                        module:OnMediaChanged()
                    end
                end
            end)
        end
    end
end)
