--[[
    DDingToolKit - MainFrame
    메인 설정 창 (탭 컨테이너)
]]

local addonName, ns = ...
local UI = ns.UI
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [STYLE]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

-- 메인 프레임 생성
local function CreateMainFrame()
    local frame = UI:CreateMainFrame(UIParent, 800, 600, "DDingToolKit_MainFrame")

    -- 타이틀바 (버전 표시)
    local titleBar = UI:CreateTitleBar(frame, "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r v" .. DDingToolKit.version)
    frame.titleBar = titleBar

    -- 탭 컨테이너 (2줄)
    local tabContainer = CreateFrame("Frame", nil, frame)
    tabContainer:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    tabContainer:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    tabContainer:SetHeight(68)  -- 2줄 높이
    frame.tabContainer = tabContainer

    -- 탭 배경
    local tabBg = tabContainer:CreateTexture(nil, "BACKGROUND")
    tabBg:SetAllPoints()
    tabBg:SetColorTexture(unpack(UI.colors.background))

    -- 컨텐츠 영역
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", tabContainer, "BOTTOMLEFT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.content = content

    -- 탭 관리
    frame.tabs = {}
    frame.tabPanels = {}

    -- 탭 추가 함수 (2줄 레이아웃 - 11개씩)
    local TABS_PER_ROW = 11
    local TAB_WIDTH = 62
    local TAB_SPACING = 3

    function frame:AddTab(name, label, createPanelFunc)
        local tabIndex = #self.tabs
        local row = math.floor(tabIndex / TABS_PER_ROW)
        local col = tabIndex % TABS_PER_ROW

        local xOffset = 5 + (col * (TAB_WIDTH + TAB_SPACING))
        local yOffset = 2 + (row * 32)

        local tab = UI:CreateTabButton(self.tabContainer, label, TAB_WIDTH)
        tab:SetPoint("BOTTOMLEFT", self.tabContainer, "BOTTOMLEFT", xOffset, yOffset)

        tab.name = name
        tab.createPanel = createPanelFunc

        tab:SetScript("OnClick", function()
            self:SelectTab(name)
        end)

        table.insert(self.tabs, tab)

        -- 패널은 필요할 때 생성 (지연 로딩)
        self.tabPanels[name] = nil

        return tab
    end

    -- 탭 선택
    function frame:SelectTab(name)
        -- 모든 탭 비활성화
        for _, tab in ipairs(self.tabs) do
            tab:SetActive(false)
            if self.tabPanels[tab.name] then
                self.tabPanels[tab.name]:Hide()
            end
        end

        -- 선택된 탭 활성화
        for _, tab in ipairs(self.tabs) do
            if tab.name == name then
                tab:SetActive(true)
                self.activeTab = tab

                -- 패널이 없으면 생성 (wrapper로 감싸서 에러 시 잔상 방지)
                if not self.tabPanels[name] and tab.createPanel then
                    local wrapper = CreateFrame("Frame", nil, self.content)
                    wrapper:SetPoint("TOPLEFT", self.content, "TOPLEFT", 10, -10)
                    wrapper:SetPoint("BOTTOMRIGHT", self.content, "BOTTOMRIGHT", -10, 10)

                    local ok, panel = pcall(tab.createPanel, wrapper)
                    if ok and panel then
                        panel:ClearAllPoints()
                        panel:SetAllPoints(wrapper)
                        -- 배경 통일: 모듈 패널의 backdrop 제거 (메인 프레임 배경색 사용)
                        if panel.SetBackdrop then
                            panel:SetBackdrop(nil)
                        end
                    else
                        -- 에러 시 부분 생성된 프레임 정리
                        wrapper:Hide()
                        wrapper = CreateFrame("Frame", nil, self.content)
                        wrapper:SetPoint("TOPLEFT", self.content, "TOPLEFT", 10, -10)
                        wrapper:SetPoint("BOTTOMRIGHT", self.content, "BOTTOMRIGHT", -10, 10)
                    end
                    self.tabPanels[name] = wrapper
                end

                -- 패널 표시
                if self.tabPanels[name] then
                    self.tabPanels[name]:Show()
                end

                break
            end
        end
    end

    -- ESC로 닫기
    tinsert(UISpecialFrames, "DDingToolKit_MainFrame")

    return frame
end

-- 일반 탭 패널 생성
local function CreateGeneralPanel(parent)
    local scrollContainer = UI:CreateScrollablePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20, 620)
    scrollContainer:SetPoint("TOPLEFT", 10, -10)

    local panel = scrollContainer.content
    local yOffset = -10

    -- 모듈 관리 섹션
    local moduleHeader = UI:CreateSectionHeader(panel, L["MODULE_MANAGEMENT"])
    moduleHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- 모듈 체크박스들
    local modules = {
        { name = "TalentBG", display = L["MODULE_TALENTBG"] },
        { name = "LFGAlert", display = L["MODULE_LFGALERT"] },
        { name = "MailAlert", display = L["MODULE_MAILALERT"] },
        { name = "CursorTrail", display = L["MODULE_CURSORTRAIL"] },
        { name = "ItemLevel", display = L["MODULE_ITEMLEVEL"] },
        { name = "Notepad", display = L["MODULE_NOTEPAD"] },
        { name = "CombatTimer", display = L["MODULE_COMBATTIMER"] },
        { name = "PartyTracker", display = L["MODULE_PARTYTRACKER"] },
        { name = "MythicPlusHelper", display = L["MODULE_MYTHICPLUS"] },
        { name = "GoldSplit", display = L["MODULE_GOLDSPLIT"] },
        { name = "DurabilityCheck", display = L["MODULE_DURABILITY"] },
        { name = "KeystoneTracker", display = L["MODULE_KEYSTONETRACKER"] },
        { name = "BuffChecker", display = L["MODULE_BUFFCHECKER"] },
        { name = "CastingAlert", display = L["MODULE_CASTINGALERT"] },
        { name = "FocusInterrupt", display = L["MODULE_FOCUSINTERRUPT"] },
        { name = "AutoRepair", display = L["MODULE_AUTOREPAIR"] },
    }

    -- 2열 레이아웃
    local COLUMN_SPACING = 370
    local ROW_HEIGHT = 30
    local MODULES_PER_COLUMN = 11
    local startY = yOffset

    for i, mod in ipairs(modules) do
        local col = math.floor((i - 1) / MODULES_PER_COLUMN)  -- 0 또는 1
        local row = (i - 1) % MODULES_PER_COLUMN

        local xPos = 15 + (col * COLUMN_SPACING)
        local yPos = startY - (row * ROW_HEIGHT)

        local checkbox = UI:CreateCheckbox(panel, mod.display, function(checked)
            if checked then
                DDingToolKit:EnableModule(mod.name)
            else
                DDingToolKit:DisableModule(mod.name)
            end
        end)
        checkbox:SetPoint("TOPLEFT", xPos, yPos)
        checkbox:SetChecked(ns.db.profile.modules[mod.name] ~= false)
    end

    -- 6줄만큼 yOffset 이동
    yOffset = startY - (MODULES_PER_COLUMN * ROW_HEIGHT) - 20

    -- 전역 설정 섹션
    local globalHeader = UI:CreateSectionHeader(panel, L["GLOBAL_SETTINGS"])
    globalHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 30

    -- 미니맵 버튼
    local minimapCheckbox = UI:CreateCheckbox(panel, L["SHOW_MINIMAP_BUTTON"], function(checked)
        ns.db.profile.minimap.hide = not checked
        if DDingToolKit.UpdateMinimapButton then
            DDingToolKit:UpdateMinimapButton()
        end
    end)
    minimapCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    minimapCheckbox:SetChecked(not ns.db.profile.minimap.hide)

    -- 미니맵 버튼 위치 초기화
    local resetPosBtn = UI:CreateButton(panel, 120, 24, L["RESET_POSITION"])
    resetPosBtn:SetPoint("LEFT", minimapCheckbox, "RIGHT", 150, 0)
    resetPosBtn:SetScript("OnClick", function()
        ns.db.profile.minimap.minimapPos = 225
        local LibDBIcon = ns.LibDBIcon
        if LibDBIcon then
            LibDBIcon:Refresh(addonName)
        end
        print(CHAT_PREFIX .. L["MINIMAP_POSITION_RESET"]) -- [STYLE]
    end)
    yOffset = yOffset - 30

    -- 환영 메시지
    local welcomeCheckbox = UI:CreateCheckbox(panel, L["SHOW_WELCOME_MESSAGE"], function(checked)
        ns.db.profile.welcomeMessage = checked
    end)
    welcomeCheckbox:SetPoint("TOPLEFT", 15, yOffset)
    welcomeCheckbox:SetChecked(ns.db.profile.welcomeMessage)
    yOffset = yOffset - 50

    -- 정보 섹션
    local infoHeader = UI:CreateSectionHeader(panel, L["INFO"])
    infoHeader:SetPoint("TOPLEFT", 10, yOffset)
    yOffset = yOffset - 25

    local versionText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("TOPLEFT", 15, yOffset)
    versionText:SetText(L["VERSION"] .. ": " .. DDingToolKit.version)
    versionText:SetTextColor(unpack(UI.colors.textDim))
    yOffset = yOffset - 20

    local authorText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    authorText:SetPoint("TOPLEFT", 15, yOffset)
    authorText:SetText(L["AUTHOR"] .. ": DDing")
    authorText:SetTextColor(unpack(UI.colors.textDim))

    return scrollContainer
end

-- 초기화
local function Initialize()
    local mainFrame = CreateMainFrame()
    ns.MainFrame = mainFrame

    -- 탭 추가
    mainFrame:AddTab("General", L["TAB_GENERAL"], CreateGeneralPanel)

    -- TalentBG 탭
    mainFrame:AddTab("TalentBG", L["TAB_TALENTBG"], function(parent)
        local module = DDingToolKit:GetModule("TalentBG")
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- LFGAlert 탭
    mainFrame:AddTab("LFGAlert", L["TAB_LFGALERT"], function(parent)
        local module = DDingToolKit:GetModule("LFGAlert")
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- MailAlert 탭
    mainFrame:AddTab("MailAlert", L["TAB_MAILALERT"], function(parent)
        local module = DDingToolKit:GetModule("MailAlert")
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- CursorTrail 탭
    mainFrame:AddTab("CursorTrail", L["TAB_CURSORTRAIL"], function(parent)
        local module = DDingToolKit:GetModule("CursorTrail")
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- ItemLevel 탭
    mainFrame:AddTab("ItemLevel", L["TAB_ITEMLEVEL"], function(parent)
        local module = DDingToolKit:GetModule("ItemLevel")
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- Notepad 탭
    mainFrame:AddTab("Notepad", L["TAB_NOTEPAD"], function(parent)
        local module = DDingToolKit:GetModule("Notepad")
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- CombatTimer 탭
    mainFrame:AddTab("CombatTimer", L["TAB_COMBATTIMER"], function(parent)
        local module = DDingToolKit:GetModule("CombatTimer")
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- PartyTracker 탭
    mainFrame:AddTab("PartyTracker", L["TAB_PARTYTRACKER"], function(parent)
        local module = DDingToolKit:GetModule("PartyTracker")
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- MythicPlusHelper 탭
    mainFrame:AddTab("MythicPlusHelper", L["TAB_MYTHICPLUS"], function(parent)
        local module = ns.MythicPlusHelper
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- GoldSplit (쌀숭이) 탭
    mainFrame:AddTab("GoldSplit", L["TAB_GOLDSPLIT"], function(parent)
        local module = ns.GoldSplit
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- DurabilityCheck (내구도) 탭
    mainFrame:AddTab("DurabilityCheck", L["TAB_DURABILITY"], function(parent)
        local module = ns.DurabilityCheck
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- BuffChecker (버프체크) 탭
    mainFrame:AddTab("BuffChecker", L["TAB_BUFFCHECKER"], function(parent)
        local module = ns.BuffChecker
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- CastingAlert (시전 알림) 탭
    mainFrame:AddTab("CastingAlert", L["TAB_CASTINGALERT"], function(parent)
        local module = ns.CastingAlert
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- FocusInterrupt (포커스 차단) 탭
    mainFrame:AddTab("FocusInterrupt", L["TAB_FOCUSINTERRUPT"], function(parent)
        local module = ns.FocusInterrupt
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- AutoRepair (자동수리) 탭
    mainFrame:AddTab("AutoRepair", L["TAB_AUTOREPAIR"], function(parent)
        local module = ns.AutoRepair
        if module and module.CreateConfigPanel then
            return module:CreateConfigPanel(parent)
        end
        return UI:CreatePanel(parent, parent:GetWidth() - 20, parent:GetHeight() - 20)
    end)

    -- 기본 탭 선택
    mainFrame:SelectTab("General")
end

-- 이벤트 등록
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.1, Initialize)
    end
end)
