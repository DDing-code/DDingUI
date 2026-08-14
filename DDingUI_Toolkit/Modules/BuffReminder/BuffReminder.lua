--[[
    DDingToolKit - BuffReminder Module
    Lifecycle adapter: Initialize → State Engine → Display
    Bridges DDingToolKit module system with the ported BuffReminders architecture.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local SL = _G.DDingUI_StyleLib
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("ToolKit", "ToolKit") or "|cffffffffDDing|r|cffffa300UI|r |cffd93380ToolKit|r: "

local BuffReminder = {}
BuffReminder.name = "BuffReminder"
ns.BuffReminder = BuffReminder

local isEnabled = false
local isTestMode = false

-- =============================================
-- LIFECYCLE
-- =============================================
function BuffReminder:OnInitialize()
    self.db = ns.db.profile.BuffReminder
end

function BuffReminder:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.BuffReminder then
            self.db = ns.db.profile.BuffReminder
        else
            return
        end
    end

    isEnabled = true

    -- Initialize data layer
    if ns.BuffState then
        ns.BuffState.Init()
    end

    -- Initialize display
    if ns.BuffDisplay then
        ns.BuffDisplay.Initialize()
    end

    print(CHAT_PREFIX .. "|cff40e0d0BuffReminder|r 모듈 활성화됨")
end

function BuffReminder:OnDisable()
    isEnabled = false
    if ns.BuffDisplay then
        ns.BuffDisplay.HideAll()
    end
end

function BuffReminder:ResetPosition()
    if InCombatLockdown() then
        print(CHAT_PREFIX .. "전투 중에는 위치를 초기화할 수 없습니다.")
        return
    end
    if ns.BuffDisplay then
        ns.BuffDisplay.SavePosition("main", "CENTER", 0, 200)
    end
    print(CHAT_PREFIX .. "BuffReminder 위치가 초기화되었습니다.")
end

-- =============================================
-- DO CHECK (compatibility bridge)
-- =============================================
function BuffReminder:DoCheck(force)
    if not isEnabled then return end
    if ns.BuffDisplay then
        ns.BuffDisplay.Update()
    end
end

-- =============================================
-- TEST MODE
-- =============================================
function BuffReminder:TestMode()
    isTestMode = not isTestMode
    self._editPreviewActive = isTestMode

    if isTestMode then
        -- Feed fake entries directly to state
        local BuffState = ns.BuffState
        if BuffState then
            wipe(BuffState.entries)
            local fakeEntries = {
                { key = "int", category = "raid", sortOrder = 1, visible = true, displayType = "count",
                  countText = "2/5", shouldGlow = true },
                { key = "flask", category = "consumable", sortOrder = 1, visible = true, displayType = "text",
                  overlayText = "영약", shouldGlow = true },
                { key = "food", category = "consumable", sortOrder = 2, visible = true, displayType = "text",
                  overlayText = "음식", shouldGlow = true },
                { key = "rune", category = "consumable", sortOrder = 3, visible = true, displayType = "text",
                  overlayText = "룬", shouldGlow = true },
                { key = "weapon", category = "consumable", sortOrder = 4, visible = true, displayType = "text",
                  overlayText = "무기", shouldGlow = true },
                { key = "pet", category = "pet", sortOrder = 1, visible = true, displayType = "text",
                  overlayText = "소환", shouldGlow = true },
            }
            for _, e in ipairs(fakeEntries) do
                BuffState.entries[e.key] = e
            end
        end
        if ns.BuffDisplay then
            ns.BuffDisplay.Update()
        end
    else
        if ns.BuffState then wipe(ns.BuffState.entries) end
        self:DoCheck(true)
    end
end

function BuffReminder:EnterEditPreview()
    self._editPreviewActive = true
    isTestMode = true
    self:TestMode()
    isTestMode = true
    self._editPreviewActive = true
end

function BuffReminder:ExitEditPreview()
    self._editPreviewActive = false
    isTestMode = false
    if ns.BuffState then wipe(ns.BuffState.entries) end
    self:DoCheck(true)
end

-- =============================================
-- MODULE REGISTRATION
-- =============================================
DDingToolKit:RegisterModule("BuffReminder", BuffReminder)
