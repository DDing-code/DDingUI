-- DDingUI_Essential: Skins/UI.lua -- [ESSENTIAL]
-- AddonManager, SettingsPanel, Macro, Binding, Help, Debug, Trainer, CombatLog

local _, ns = ...
ns.onDemandSkins = ns.onDemandSkins or {}
local skins = ns.onDemandSkins

------------------------------------------------------------------------
-- AddonList -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_AddonManager"] = function()
    local frame = _G.AddonList
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.EnableAllButton then ns.HandleButton(frame.EnableAllButton) end
    if frame.DisableAllButton then ns.HandleButton(frame.DisableAllButton) end
    if frame.OkayButton then ns.HandleButton(frame.OkayButton) end
    if frame.CancelButton then ns.HandleButton(frame.CancelButton) end
    if frame.SearchBox then ns.HandleEditBox(frame.SearchBox) end

    -- ScrollBar -- [ESSENTIAL]
    if frame.ScrollBar then ns.HandleScrollBar(frame.ScrollBar) end

    -- CheckButton per addon entry -- [ESSENTIAL]
    for i = 1, 20 do
        local entry = _G["AddonListEntry"..i]
        if entry then
            if entry.Enabled then ns.HandleCheckButton(entry.Enabled) end
            if entry.LoadAddonButton then ns.HandleButton(entry.LoadAddonButton) end
        end
    end
end

------------------------------------------------------------------------
-- SettingsPanel -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_Settings"] = function()
    local frame = _G.SettingsPanel
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true

    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
    ns.StripTextures(frame)
    ns.CreateBackdrop(frame)
    ns.SkinAccentLine(frame)

    if frame.ClosePanelButton then ns.HandleButton(frame.ClosePanelButton) end
    if frame.ApplyButton then ns.HandleButton(frame.ApplyButton) end

    -- CategoryList + ScrollBar -- [ESSENTIAL]
    if frame.CategoryList then
        ns.StripTextures(frame.CategoryList)
        if frame.CategoryList.ScrollBar then
            ns.HandleScrollBar(frame.CategoryList.ScrollBar)
        end
    end

    -- SettingsCanvas + ScrollBar -- [ESSENTIAL]
    if frame.Container then
        if frame.Container.SettingsCanvas then
            ns.StripTextures(frame.Container.SettingsCanvas)
            if frame.Container.SettingsCanvas.ScrollBar then
                ns.HandleScrollBar(frame.Container.SettingsCanvas.ScrollBar)
            end
        end
    end

    -- Controls: CheckBox/Dropdown deferred skin -- [ESSENTIAL]
    local function SkinSettingControls()
        if not frame.Container then return end
        for _, child in next, { frame.Container:GetChildren() } do
            if child and not child._ddeControlsSkinned then
                child._ddeControlsSkinned = true
                if child.CheckBox and not child.CheckBox._ddeSkinned then
                    ns.HandleCheckButton(child.CheckBox)
                end
                if child.Dropdown and not child.Dropdown._ddeSkinned then
                    ns.HandleDropdown(child.Dropdown)
                end
            end
        end
    end
    C_Timer.After(0.3, SkinSettingControls)

    if frame.SearchBox then ns.HandleEditBox(frame.SearchBox) end
end

------------------------------------------------------------------------
-- Macro -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_MacroUI"] = function()
    local frame = _G.MacroFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    for i = 1, 2 do
        local tab = _G["MacroFrameTab"..i]
        if tab then ns.HandleTab(tab) end
    end

    if _G.MacroFrameText then ns.HandleEditBox(_G.MacroFrameText) end
    if _G.MacroEditButton then ns.HandleButton(_G.MacroEditButton) end
    if _G.MacroDeleteButton then ns.HandleButton(_G.MacroDeleteButton) end
    if _G.MacroNewButton then ns.HandleButton(_G.MacroNewButton) end
    if _G.MacroSaveButton then ns.HandleButton(_G.MacroSaveButton) end
    if _G.MacroCancelButton then ns.HandleButton(_G.MacroCancelButton) end
    if _G.MacroFrameInset then ns.StripTextures(_G.MacroFrameInset) end

    -- ScrollBar -- [ESSENTIAL]
    if frame.MacroSelector and frame.MacroSelector.ScrollBar then
        ns.HandleScrollBar(frame.MacroSelector.ScrollBar)
    end

    -- MacroPopupFrame -- [ESSENTIAL]
    local popup = _G.MacroPopupFrame
    if popup then
        ns.HandleFrame(popup)
        if popup.EditBox then ns.HandleEditBox(popup.EditBox) end
        if _G.MacroPopupOkayButton or popup.OkayButton then
            ns.HandleButton(_G.MacroPopupOkayButton or popup.OkayButton)
        end
        if _G.MacroPopupCancelButton or popup.CancelButton then
            ns.HandleButton(_G.MacroPopupCancelButton or popup.CancelButton)
        end
    end
end

------------------------------------------------------------------------
-- Binding -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_BindingUI"] = function()
    local frame = _G.KeyBindingFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if _G.KeyBindingFrameDefaultButton then ns.HandleButton(_G.KeyBindingFrameDefaultButton) end
    if _G.KeyBindingFrameUnbindButton then ns.HandleButton(_G.KeyBindingFrameUnbindButton) end
    if _G.KeyBindingFrameOkayButton then ns.HandleButton(_G.KeyBindingFrameOkayButton) end
    if _G.KeyBindingFrameCancelButton then ns.HandleButton(_G.KeyBindingFrameCancelButton) end
    if frame.OutputText then ns.StripTextures(frame.OutputText) end

    -- ScrollBar -- [ESSENTIAL]
    if frame.ScrollBar then ns.HandleScrollBar(frame.ScrollBar) end
end

------------------------------------------------------------------------
-- Help -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_HelpFrame"] = function()
    local frame = _G.HelpFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
end

------------------------------------------------------------------------
-- Debug / EventTrace -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_DebugTools"] = function()
    local frame = _G.EventTraceFrame
    if frame and not frame._ddeSkinned then
        ns.HandleFrame(frame)
    end
end

------------------------------------------------------------------------
-- Trainer -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_TrainerUI"] = function()
    local frame = _G.ClassTrainerFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if _G.ClassTrainerFrameInset then ns.StripTextures(_G.ClassTrainerFrameInset) end
    if _G.ClassTrainerTrainButton then ns.HandleButton(_G.ClassTrainerTrainButton) end

    if frame.ScrollBar then ns.HandleScrollBar(frame.ScrollBar) end
end

------------------------------------------------------------------------
-- GuildControl -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_GuildControlUI"] = function()
    local frame = _G.GuildControlUI
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.Inset then ns.StripTextures(frame.Inset) end
    if frame.dropdown then ns.HandleDropdown(frame.dropdown) end
end

------------------------------------------------------------------------
-- CombatLog -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_CombatLog"] = function()
    local frame = _G.CombatLogFrame
    if frame and not frame._ddeSkinned then
        frame._ddeSkinned = true
        ns.StripTextures(frame)
    end
end
