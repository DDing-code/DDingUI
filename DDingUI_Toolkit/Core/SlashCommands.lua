--[[
    DDingToolKit - Slash Commands
    슬래시 커맨드 핸들러
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local SL = _G.DDingUI_StyleLib -- [STYLE]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]
local CHAT_PREFIX_ERR = "|cFFFF0000" .. ((SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: ") -- [STYLE]

-- 슬래시 커맨드 핸들러
local function SlashHandler(msg)
    local command, arg = msg:match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "" or command == "config" then
        -- 설정 창 열기
        DDingToolKit:ToggleConfig()

    elseif command == "talentbg" or command == "tb" then
        -- TalentBG 탭으로 설정 창 열기
        DDingToolKit:OpenConfig("TalentBG")

    elseif command == "lfg" or command == "alert" then
        -- LFGAlert 탭으로 설정 창 열기
        arg = arg:lower()
        if arg == "test" then
            -- 테스트 알림
            local lfgAlert = DDingToolKit:GetModule("LFGAlert")
            if lfgAlert and lfgAlert.TriggerAlert then
                lfgAlert:TriggerAlert(1, true)
                print(CHAT_PREFIX .. "LFGAlert test triggered.") -- [STYLE]
            end
        else
            DDingToolKit:OpenConfig("LFGAlert")
        end

    elseif command == "mail" then
        -- MailAlert 탭으로 설정 창 열기
        arg = arg:lower()
        if arg == "test" then
            -- 테스트 알림
            local mailAlert = DDingToolKit:GetModule("MailAlert")
            if mailAlert and mailAlert.TriggerAlert then
                mailAlert:TriggerAlert(true)
                print(CHAT_PREFIX .. "MailAlert test triggered.") -- [STYLE]
            end
        else
            DDingToolKit:OpenConfig("MailAlert")
        end

    elseif command == "trail" then
        -- CursorTrail 탭으로 설정 창 열기
        arg = arg:lower()
        if arg == "toggle" then
            -- 토글
            local cursorTrail = DDingToolKit:GetModule("CursorTrail")
            if cursorTrail and cursorTrail.Toggle then
                local enabled = cursorTrail:Toggle()
                if enabled then
                    print(CHAT_PREFIX .. "커서 트레일 활성화") -- [STYLE]
                else
                    print(CHAT_PREFIX .. "커서 트레일 비활성화") -- [STYLE]
                end
            end
        else
            DDingToolKit:OpenConfig("CursorTrail")
        end

    elseif command == "ilvl" or command == "itemlevel" then
        -- ItemLevel 탭으로 설정 창 열기
        DDingToolKit:OpenConfig("ItemLevel")

    elseif command == "notepad" or command == "memo" or command == "note" then
        -- Notepad 메모장 열기
        local notepad = DDingToolKit:GetModule("Notepad")
        if notepad and notepad.ToggleMainFrame then
            notepad:ToggleMainFrame()
        else
            DDingToolKit:OpenConfig("Notepad")
        end

    elseif command == "keys" or command == "keystone" then
        -- 쐐기돌 추적 창 열기
        local keystoneTracker = ns.KeystoneTracker
        if keystoneTracker and keystoneTracker.Toggle then
            keystoneTracker:Toggle()
        else
            DDingToolKit:OpenConfig("KeystoneTracker")
        end

    elseif command == "tp" or command == "teleport" then
        -- 던전 텔레포트 (신화+ 탭 열기)
        local mythicPlusHelper = ns.MythicPlusHelper
        if mythicPlusHelper and mythicPlusHelper.Toggle then
            mythicPlusHelper:Toggle()
        else
            -- PVE 프레임 직접 열기
            PVEFrame_ToggleFrame("ChallengesFrame")
        end

    elseif command == "party" or command == "tracker" then
        -- 파티 트래커 테스트 모드
        local partyTracker = ns.PartyTracker
        if partyTracker and partyTracker.TestMode then
            partyTracker:TestMode()
        else
            DDingToolKit:OpenConfig("PartyTracker")
        end

    elseif command == "enable" then
        -- 모듈 활성화
        if arg and arg ~= "" then
            if DDingToolKit:EnableModule(arg) then
                print(CHAT_PREFIX .. "Module '" .. arg .. "' enabled.") -- [STYLE]
            else
                print(CHAT_PREFIX_ERR .. "Module '" .. arg .. "' not found.") -- [STYLE]
            end
        else
            print(CHAT_PREFIX_ERR .. "Usage: /ddt enable <module>") -- [STYLE]
        end

    elseif command == "disable" then
        -- 모듈 비활성화
        if arg and arg ~= "" then
            if DDingToolKit:DisableModule(arg) then
                print(CHAT_PREFIX .. "Module '" .. arg .. "' disabled.") -- [STYLE]
            else
                print(CHAT_PREFIX_ERR .. "Module '" .. arg .. "' not found.") -- [STYLE]
            end
        else
            print(CHAT_PREFIX_ERR .. "Usage: /ddt disable <module>") -- [STYLE]
        end

    elseif command == "list" then
        -- 모듈 목록
        print(CHAT_PREFIX .. "Modules:") -- [STYLE]
        for name, module in pairs(DDingToolKit.modules) do
            local status = module.enabled and "|cFF00FF00enabled|r" or "|cFFFF0000disabled|r"
            print("  - " .. name .. ": " .. status)
        end

    elseif command == "reset" then
        -- 설정 초기화 확인
        StaticPopupDialogs["DDINGTOOLKIT_RESET_CONFIRM"] = {
            text = "Reset all DDingUI Toolkit settings?\n\n|cFFFFFF00UI will reload.|r",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                DDingUIToolkitDB = nil
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("DDINGTOOLKIT_RESET_CONFIRM")

    else
        -- 도움말
        print(CHAT_PREFIX .. "Commands:") -- [STYLE]
        print("  /ddt - Open config UI")
        print("  /ddt talentbg - Open TalentBG settings")
        print("  /ddt lfg - Open LFGAlert settings")
        print("  /ddt lfg test - Test LFGAlert notification")
        print("  /ddt mail - Open MailAlert settings")
        print("  /ddt mail test - Test MailAlert notification")
        print("  /ddt trail - Open CursorTrail settings")
        print("  /ddt trail toggle - Toggle cursor trail")
        print("  /ddt ilvl - Open ItemLevel settings")
        print("  /ddt notepad - Open Notepad")
        print("  /ddt keys - Open Keystone Tracker")
        print("  /ddt tp - Open M+ Teleport window")
        print("  /ddt party - Toggle PartyTracker test mode")
        print("  /ddt enable <module> - Enable module")
        print("  /ddt disable <module> - Disable module")
        print("  /ddt list - List all modules")
        print("  /ddt reset - Reset all settings")
    end
end

-- 슬래시 커맨드 등록
SLASH_DDINGTOOLKIT1 = "/ddt"
SLASH_DDINGTOOLKIT2 = "/ddingtoolkit"
SlashCmdList["DDINGTOOLKIT"] = SlashHandler
