--[[
    DDingQoC - Slash Commands
    슬래시 커맨드 핸들러
]]

local addonName, ns = ...
local DDingQoC = ns.DDingQoC
local SL = _G.DDingUI_StyleLib -- [STYLE]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: " -- [STYLE]
local CHAT_PREFIX_ERR = "|cFFFF0000" .. ((SL and SL.GetChatPrefix) and SL.GetChatPrefix("QoC", "QoC") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380QoC|r: ") -- [STYLE]

-- 슬래시 커맨드 핸들러
local function SlashHandler(msg)
    local command, arg = msg:match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "" or command == "config" then
        DDingQoC:ToggleConfig()

    elseif command == "enable" then
        if arg and arg ~= "" then
            if DDingQoC:EnableModule(arg) then
                print(CHAT_PREFIX .. "Module '" .. arg .. "' enabled.") -- [STYLE]
            else
                print(CHAT_PREFIX_ERR .. "Module '" .. arg .. "' not found.") -- [STYLE]
            end
        else
            print(CHAT_PREFIX_ERR .. "Usage: /qoc enable <module>") -- [STYLE]
        end

    elseif command == "disable" then
        if arg and arg ~= "" then
            if DDingQoC:DisableModule(arg) then
                print(CHAT_PREFIX .. "Module '" .. arg .. "' disabled.") -- [STYLE]
            else
                print(CHAT_PREFIX_ERR .. "Module '" .. arg .. "' not found.") -- [STYLE]
            end
        else
            print(CHAT_PREFIX_ERR .. "Usage: /qoc disable <module>") -- [STYLE]
        end

    elseif command == "list" then
        print(CHAT_PREFIX .. "Modules:") -- [STYLE]
        for name, module in pairs(DDingQoC.modules) do
            local status = module.enabled and "|cFF00FF00enabled|r" or "|cFFFF0000disabled|r"
            print("  - " .. name .. ": " .. status)
        end

    elseif command == "reset" then
        StaticPopupDialogs["DDINGQOC_RESET_CONFIRM"] = {
            text = "Reset all DDingUI QoC settings?\n\n|cFFFFFF00UI will reload.|r",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                DDingUIQoCDB = nil
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("DDINGQOC_RESET_CONFIRM")

    else
        print(CHAT_PREFIX .. "Commands:") -- [STYLE]
        print("  /qoc - Open config UI")
        print("  /qoc enable <module> - Enable module")
        print("  /qoc disable <module> - Disable module")
        print("  /qoc list - List all modules")
        print("  /qoc reset - Reset all settings")
    end
end

-- 슬래시 커맨드 등록
SLASH_DDINGQOC1 = "/qoc"
SLASH_DDINGQOC2 = "/ddingqoc"
SlashCmdList["DDINGQOC"] = SlashHandler
