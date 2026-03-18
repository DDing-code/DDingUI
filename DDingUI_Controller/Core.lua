------------------------------------------------------
-- DDingUI_Controller :: Core
-- Initialization, DB loading, slash commands
------------------------------------------------------
local Controller = _G.DDingUI_Controller
if not Controller then return end

------------------------------------------------------
-- Deep merge (defaults into saved)
------------------------------------------------------
local function DeepMerge(defaults, saved)
    if type(defaults) ~= "table" then return saved end
    if type(saved) ~= "table" then return defaults end
    local result = {}
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            result[k] = v
        elseif type(v) == "table" and type(saved[k]) == "table" then
            result[k] = DeepMerge(v, saved[k])
        else
            result[k] = saved[k]
        end
    end
    -- saved에만 있는 키도 보존
    for k, v in pairs(saved) do
        if result[k] == nil then
            result[k] = v
        end
    end
    return result
end

------------------------------------------------------
-- Event handling
------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DDingUI_Controller" then
        -- StyleLib에 CallbackHandler 확실히 초기화 -- [CONTROLLER]
        -- (StyleLib 로딩 시점에 CBH가 없었을 수 있음)
        local SL = _G.DDingUI_StyleLib
        local CBH = LibStub("CallbackHandler-1.0", true)
        if SL and CBH and not SL.callbacks then
            SL.callbacks = CBH:New(SL)
        end

        -- SavedVariables 로드 + 기본값 병합
        DDingUI_ControllerDB = DeepMerge(DDingUI_ControllerDefaults, DDingUI_ControllerDB or {})
        Controller.db = DDingUI_ControllerDB

        -- StyleLib에 초기 설정 적용
        Controller:ApplyToStyleLib()

        -- EditMode 설정 DB에서 복원
        if Controller.EditMode and Controller.db.editMode and Controller.db.editMode.settings then
            for k, v in pairs(Controller.db.editMode.settings) do
                Controller.EditMode.Settings[k] = v
            end
        end

        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- 슬래시 커맨드 등록
        SLASH_DDINGUI_CONTROLLER1 = "/ddingui"
        SLASH_DDINGUI_CONTROLLER2 = "/controller"
        SLASH_DDINGUI_CONTROLLER3 = "/ddc"
        SLASH_DDINGUI_CONTROLLER4 = "/dui"
        SlashCmdList["DDINGUI_CONTROLLER"] = function(msg)
            msg = strtrim(msg or ""):lower()
            if msg == "edit" or msg == "unlock" or msg == "move" then
                -- 통합 편집모드 토글
                if Controller.EditMode then
                    Controller.EditMode:Toggle()
                else
                    print("|cffffffffDDing|r|cffffa300UI|r |cff999999Controller|r: EditMode 모듈이 로드되지 않았습니다")
                end
            elseif msg == "reset" then
                -- 기본값 복원
                Controller:ResetToDefaults()
            else
                -- 설정 패널 토글
                if Controller.ToggleSettings then
                    Controller:ToggleSettings()
                else
                    local SL0 = _G.DDingUI_StyleLib
                    if SL0 and SL0.GetChatPrefix then
                        print(SL0.GetChatPrefix("Controller", "Controller") .. "설정 패널 로드 중...")
                    else
                        print("|cffffffffDDing|r|cffffa300UI|r |cff999999Controller:|r 설정 패널 로드 중...")
                    end
                end
            end
        end

        -- 로드 완료 메시지 -- [STYLE]
        local SL = _G.DDingUI_StyleLib
        local version = C_AddOns and C_AddOns.GetAddOnMetadata("DDingUI_Controller", "Version") or "1.0.0"
        if SL and SL.CreateAddonTitle then
            print(SL.CreateAddonTitle("Controller", "Controller") .. " v" .. version .. " |cff888888로드 완료.|r")
            print("  |cffcccccc/dui|r — 설정  |cffcccccc/dui edit|r — 편집모드")
        else
            print("|cffffffffDDing|r|cffffa300UI|r |cff999999Controller|r v" .. version .. " 로드 완료.")
            print("  /dui — 설정  /dui edit — 편집모드")
        end

        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

------------------------------------------------------
-- Public API
------------------------------------------------------

--- 설정 변경 후 저장 + StyleLib에 적용
function Controller:SaveAndApply()
    DDingUI_ControllerDB = self.db
    self:ApplyToStyleLib()
end

--- 기본값으로 초기화
function Controller:ResetToDefaults()
    self.db = DeepMerge(DDingUI_ControllerDefaults, {})
    DDingUI_ControllerDB = self.db
    self:ApplyToStyleLib()
    -- UI 갱신
    if self.RefreshSettingsUI then
        self:RefreshSettingsUI()
    end
end
