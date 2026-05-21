-- ============================================================
-- DDingUI EditModeLock
-- Blizzard 편집모드에서 CDM 뷰어 조작 완전 차단
-- Adapted from CDM_ EditMode.lua (3중 차단 시스템)
-- ============================================================

local AddonName, ns = ...
local DDingUI = LibStub("AceAddon-3.0"):GetAddon("DDingUI")

local LOCK_FRAME_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local selectionState = setmetatable({}, { __mode = "k" })

local function ShouldSkipBlizzardEditModeSideEffects()
    return DDingUI.IsPvPInstance and DDingUI:IsPvPInstance()
end

local function GetSelectionState(selection)
    local state = selectionState[selection]
    if not state then
        state = {}
        selectionState[selection] = state
    end
    return state
end

local function IsCooldownViewerSystemFrame(frame)
    local cooldownSystem = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
    return cooldownSystem and frame and frame.system == cooldownSystem
end

-- 차단 1: Selection 하이라이트/마우스 비활성화
local function DisableSelectionInteraction(frame)
    if not frame then return end
    local selection = frame.Selection
    if not selection then return end
    selection:SetAlpha(0)
    selection:EnableMouse(false)
    pcall(function()
        for _, child in ipairs({ selection:GetRegions() }) do
            if child and child.SetAlpha then child:SetAlpha(0) end
        end
    end)
end

-- 차단 2: 사이드바 체크박스 비활성화
local sidebarDisabled = false
local function DisableSidebarCooldownViewerButtons()
    if sidebarDisabled then return end
    local EditModeManagerFrame = _G.EditModeManagerFrame
    if not EditModeManagerFrame then return end
    local cooldownSystem = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
    if not cooldownSystem then return end
    pcall(function()
        local function DisableCheckbox(container)
            if not container then return end
            for _, child in ipairs({ container:GetChildren() }) do
                if child then
                    local label = child.Label or child.Text or child.label or child.text
                    if label and label.GetText then
                        local text = label:GetText()
                        if text and (text:find("Cooldown") or text:find("재사용") or text:find("cooldown") or text:find("대기시간")) then
                            child:Hide()
                            child:SetHeight(0.01)
                            if child.SetEnabled then child:SetEnabled(false) end
                            if child.Disable then child:Disable() end
                        end
                    end
                end
            end
        end
        if EditModeManagerFrame.AccountSettings then DisableCheckbox(EditModeManagerFrame.AccountSettings) end
    end)
    sidebarDisabled = true
end

-- 차단 3: 설정 다이얼로그 + SelectSystem 차단
local lockNoticeShown = false
local function ShowLockNotice()
    if not lockNoticeShown then
        print("|cffffa300DDingUI|r: 쿨다운 뷰어는 DDingUI 편집모드(/dcm)로 관리됩니다.")
        lockNoticeShown = true
    end
end

local function LockAllCooldownViewers()
    if ShouldSkipBlizzardEditModeSideEffects() then return end
    for _, name in ipairs(LOCK_FRAME_NAMES) do
        local frame = _G[name]
        if IsCooldownViewerSystemFrame(frame) then
            frame:SetMovable(false)
            local selection = frame.Selection
            if selection then
                selection:SetScript("OnDragStart", nil)
                selection:SetScript("OnDragStop", nil)
            end
            DisableSelectionInteraction(frame)
        end
    end
    DisableSidebarCooldownViewerButtons()
end

function DDingUI:SetupEditModeLock()
    if self._editModeLockSetup then return end
    local function TrySetup()
        local EditModeSystemSettingsDialog = _G.EditModeSystemSettingsDialog
        if not (EditModeSystemSettingsDialog and Enum and Enum.EditModeSystem) then return false end

        hooksecurefunc(EditModeSystemSettingsDialog, "AttachToSystemFrame", function(dialog, systemFrame)
            if ShouldSkipBlizzardEditModeSideEffects() then return end
            if not IsCooldownViewerSystemFrame(systemFrame) then return end
            dialog:Hide()
            ShowLockNotice()
        end)

        for _, name in ipairs(LOCK_FRAME_NAMES) do
            local frame = _G[name]
            if IsCooldownViewerSystemFrame(frame) then
                hooksecurefunc(frame, "SelectSystem", function(sf)
                    if ShouldSkipBlizzardEditModeSideEffects() then return end
                    sf:SetMovable(false)
                    if EditModeSystemSettingsDialog.attachedToSystem == sf then
                        EditModeSystemSettingsDialog:Hide()
                    end
                    DisableSelectionInteraction(sf)
                    ShowLockNotice()
                end)
                hooksecurefunc(frame, "HighlightSystem", function(sf)
                    if ShouldSkipBlizzardEditModeSideEffects() then return end
                    DisableSelectionInteraction(sf)
                end)
            end
        end

        self._editModeLockSetup = true
        LockAllCooldownViewers()
        return true
    end

    if not TrySetup() then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", function() TrySetup() end)
    end
end
