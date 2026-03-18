-- DDingUI_Essential: Skins/Content.lua -- [ESSENTIAL]
-- EncounterJournal, LFG, PVPUI, Achievement, PVPMatch, Collections, PetBattle

local _, ns = ...
ns.onDemandSkins = ns.onDemandSkins or {}
local skins = ns.onDemandSkins

------------------------------------------------------------------------
-- EncounterJournal -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_EncounterJournal"] = function()
    local frame = _G.EncounterJournal
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    -- Tabs -- [ESSENTIAL]
    local i = 1
    while _G["EncounterJournalTab"..i] do
        ns.HandleTab(_G["EncounterJournalTab"..i])
        i = i + 1
    end

    if frame.Inset then ns.StripTextures(frame.Inset) end
    if frame.SearchBox then ns.HandleEditBox(frame.SearchBox) end

    -- Instance select -- [ESSENTIAL]
    if frame.instanceSelect then
        ns.StripTextures(frame.instanceSelect)
        if frame.instanceSelect.ScrollBar then
            ns.HandleScrollBar(frame.instanceSelect.ScrollBar)
        end
    end

    -- Encounter panels -- [ESSENTIAL]
    local panels = { "encounter", "instanceSelect", "LootJournal" }
    for _, name in ipairs(panels) do
        local p = frame[name]
        if p then ns.StripTextures(p) end
    end

    -- Encounter info -- [ESSENTIAL]
    if frame.encounter then
        local enc = frame.encounter
        if enc.info then
            ns.StripTextures(enc.info)
            if enc.info.ScrollBar then ns.HandleScrollBar(enc.info.ScrollBar) end
            -- Loot ScrollBar -- [ESSENTIAL]
            if enc.info.LootContainer and enc.info.LootContainer.ScrollBar then
                ns.HandleScrollBar(enc.info.LootContainer.ScrollBar)
            end
        end
    end
end

------------------------------------------------------------------------
-- LFG (PVE Frame) -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_PVPUI"] = function()
    local pve = _G.PVEFrame
    if pve and not pve._ddeSkinned then
        ns.HandleFrame(pve)
        ns.SkinAccentLine(pve)

        local i = 1
        while _G["PVEFrameTab"..i] do
            ns.HandleTab(_G["PVEFrameTab"..i])
            i = i + 1
        end
        if pve.Inset then ns.StripTextures(pve.Inset) end
    end

    -- PVPFrame -- [ESSENTIAL]
    local pvp = _G.PVPQueueFrame
    if pvp then
        if pvp.NewSeasonPopup then
            ns.StripTextures(pvp.NewSeasonPopup)
            ns.CreateBackdrop(pvp.NewSeasonPopup)
            if pvp.NewSeasonPopup.Leave then ns.HandleButton(pvp.NewSeasonPopup.Leave) end
        end
    end

    -- Honor Frame -- [ESSENTIAL]
    local honor = _G.HonorFrame
    if honor then
        if honor.QueueButton then ns.HandleButton(honor.QueueButton) end
        if honor.Inset then ns.StripTextures(honor.Inset) end
    end

    -- Conquest Frame -- [ESSENTIAL]
    local conquest = _G.ConquestFrame
    if conquest then
        if conquest.JoinButton then ns.HandleButton(conquest.JoinButton) end
        if conquest.Inset then ns.StripTextures(conquest.Inset) end
    end
end

skins["Blizzard_LookingForGroupUI"] = function()
    local lfg = _G.LFGListFrame
    if lfg then
        if lfg.SearchPanel then
            local sp = lfg.SearchPanel
            if sp.SearchBox then ns.HandleEditBox(sp.SearchBox) end
            if sp.SignUpButton then ns.HandleButton(sp.SignUpButton) end
            if sp.RefreshButton then ns.HandleButton(sp.RefreshButton) end
            if sp.BackToGroupButton then ns.HandleButton(sp.BackToGroupButton) end
            if sp.ScrollBar then ns.HandleScrollBar(sp.ScrollBar) end
        end
        if lfg.EntryCreation then
            local ec = lfg.EntryCreation
            if ec.ListGroupButton then ns.HandleButton(ec.ListGroupButton) end
            if ec.CancelButton then ns.HandleButton(ec.CancelButton) end
            if ec.Name then ns.HandleEditBox(ec.Name) end
            if ec.ItemLevel and ec.ItemLevel.EditBox then ns.HandleEditBox(ec.ItemLevel.EditBox) end
            if ec.VoiceChat and ec.VoiceChat.EditBox then ns.HandleEditBox(ec.VoiceChat.EditBox) end
        end
        if lfg.ApplicationViewer then
            local av = lfg.ApplicationViewer
            if av.RefreshButton then ns.HandleButton(av.RefreshButton) end
            if av.RemoveEntryButton then ns.HandleButton(av.RemoveEntryButton) end
            if av.EditButton then ns.HandleButton(av.EditButton) end
            if av.Inset then ns.StripTextures(av.Inset) end
            if av.ScrollBar then ns.HandleScrollBar(av.ScrollBar) end
        end
    end

    -- LFDFrame / RaidFinderFrame -- [ESSENTIAL]
    local lfd = _G.LFDParentFrame
    if lfd then
        ns.StripTextures(lfd)
        if lfd.Inset then ns.StripTextures(lfd.Inset) end
    end
    if _G.LFDQueueFrameFindGroupButton then ns.HandleButton(_G.LFDQueueFrameFindGroupButton) end

    local rf = _G.RaidFinderFrame or _G.RaidFinderQueueFrame
    if rf then
        ns.StripTextures(rf)
        if rf.Inset then ns.StripTextures(rf.Inset) end
    end
    if _G.RaidFinderFrameFindRaidButton then ns.HandleButton(_G.RaidFinderFrameFindRaidButton) end
end

------------------------------------------------------------------------
-- Achievement -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_AchievementUI"] = function()
    local frame = _G.AchievementFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    -- Tabs -- [ESSENTIAL]
    local i = 1
    while _G["AchievementFrameTab"..i] do
        ns.HandleTab(_G["AchievementFrameTab"..i])
        i = i + 1
    end

    -- Sub frames -- [ESSENTIAL]
    local sub = { "Header", "AchievementsContainer", "CategoriesContainer" }
    for _, name in ipairs(sub) do
        local s = frame[name] or _G["AchievementFrame"..name]
        if s then ns.StripTextures(s) end
    end

    if frame.SearchBox then ns.HandleEditBox(frame.SearchBox) end
    if _G.AchievementFrameComparisonFrame then
        ns.StripTextures(_G.AchievementFrameComparisonFrame)
    end

    -- ScrollBars -- [ESSENTIAL]
    if frame.ScrollBar then ns.HandleScrollBar(frame.ScrollBar) end
    if _G.AchievementFrameCategoriesContainerScrollBar then
        ns.HandleScrollBar(_G.AchievementFrameCategoriesContainerScrollBar)
    end

    -- Achievement status bars -- [ESSENTIAL]
    hooksecurefunc("AchievementButton_DisplayAchievement", function(button)
        if button and button.StatusBar and not button.StatusBar._ddeSkinned then
            ns.HandleStatusBar(button.StatusBar)
        end
    end)
end

------------------------------------------------------------------------
-- PVPMatch -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_PVPMatch"] = function()
    local frame = _G.PVPMatchScoreboard
    if frame and not frame._ddeSkinned then
        ns.HandleFrame(frame)
        if frame.CloseButton then ns.HandleCloseButton(frame.CloseButton) end
        if frame.ScrollBar then ns.HandleScrollBar(frame.ScrollBar) end
    end
    local results = _G.PVPMatchResults
    if results and not results._ddeSkinned then
        ns.HandleFrame(results)
        if results.CloseButton then ns.HandleCloseButton(results.CloseButton) end
        if results.buttonContainer then
            if results.buttonContainer.LeaveButton then ns.HandleButton(results.buttonContainer.LeaveButton) end
            if results.buttonContainer.RequeueButton then ns.HandleButton(results.buttonContainer.RequeueButton) end
        end
    end
end

------------------------------------------------------------------------
-- Collections -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_Collections"] = function()
    local frame = _G.CollectionsJournal
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    local i = 1
    while _G["CollectionsJournalTab"..i] do
        ns.HandleTab(_G["CollectionsJournalTab"..i])
        i = i + 1
    end

    -- MountJournal deep skin -- [ESSENTIAL]
    local mj = _G.MountJournal
    if mj then
        ns.StripTextures(mj)
        if mj.MountButton then ns.HandleButton(mj.MountButton) end
        if mj.SearchBox then ns.HandleEditBox(mj.SearchBox) end
        if mj.BottomLeftInset then ns.StripTextures(mj.BottomLeftInset) end
        -- ScrollBar -- [ESSENTIAL]
        if mj.ScrollBar then ns.HandleScrollBar(mj.ScrollBar) end
        -- Mount list items icon TexCoord -- [ESSENTIAL]
        if mj.ListScrollFrame then
            hooksecurefunc(mj.ListScrollFrame, "update", function(self)
                for _, btn in next, { self:GetChildren() } do
                    if btn and btn.icon and not btn._ddeSkinned then
                        ns.HandleIcon(btn.icon, btn)
                        btn._ddeSkinned = true
                    end
                end
            end)
        end
        -- MountDisplay model cleanup -- [ESSENTIAL]
        if mj.MountDisplay then
            if mj.MountDisplay.ModelScene then
                ns.StripTextures(mj.MountDisplay.ModelScene)
            end
            if mj.MountDisplay.InfoButton then
                ns.StripTextures(mj.MountDisplay.InfoButton)
            end
        end
    end

    -- PetJournal deep skin -- [ESSENTIAL]
    local pj = _G.PetJournalFrame or _G.PetJournal
    if pj then
        ns.StripTextures(pj)
        if pj.SearchBox then ns.HandleEditBox(pj.SearchBox) end
        if pj.SummonButton then ns.HandleButton(pj.SummonButton) end
        if pj.FindBattleButton then ns.HandleButton(pj.FindBattleButton) end
        if pj.ScrollBar then ns.HandleScrollBar(pj.ScrollBar) end

        -- Pet card icons -- [ESSENTIAL]
        if pj.PetCardFrame then
            local card = pj.PetCardFrame
            if card.PetInfo and card.PetInfo.Icon then
                ns.HandleIcon(card.PetInfo.Icon, card.PetInfo)
            end
            -- Ability icons -- [ESSENTIAL]
            for i = 1, 6 do
                local ability = card["spell"..i]
                if ability and ability.icon then
                    ns.HandleIcon(ability.icon, ability, false)
                end
            end
        end

        -- Pet loadout slots -- [ESSENTIAL]
        for i = 1, 3 do
            local slot = pj["Loadout"..i] or _G["PetJournalLoadout"..i]
            if slot then
                ns.StripTextures(slot)
                ns.CreateBackdrop(slot)
                if slot.Pet then
                    if slot.Pet.Icon then ns.HandleIcon(slot.Pet.Icon, slot.Pet) end
                end
            end
        end
    end

    -- ToyBox -- [ESSENTIAL]
    local tb = _G.ToyBox
    if tb then
        ns.StripTextures(tb)
        if tb.SearchBox then ns.HandleEditBox(tb.SearchBox) end
        if tb.PagingFrame then
            if tb.PagingFrame.PrevPageButton then ns.HandleButton(tb.PagingFrame.PrevPageButton) end
            if tb.PagingFrame.NextPageButton then ns.HandleButton(tb.PagingFrame.NextPageButton) end
        end
        -- Toy icons -- [ESSENTIAL]
        for i = 1, 18 do
            local btn = tb["Item"..i]
            if btn then
                ns.HandleItemButton(btn)
            end
        end
    end

    -- HeirloomJournal -- [ESSENTIAL]
    local hj = _G.HeirloomJournal
    if hj then
        ns.StripTextures(hj)
        if hj.SearchBox then ns.HandleEditBox(hj.SearchBox) end
    end

    -- WardrobeFrame -- [ESSENTIAL]
    local wf = _G.WardrobeFrame
    if wf then
        ns.HandleFrame(wf)
    end
end

------------------------------------------------------------------------
-- PetBattle -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_PetBattleUI"] = function()
    local frame = _G.PetBattleFrame
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true

    local bf = frame.BottomFrame
    if bf then
        ns.StripTextures(bf)
        ns.CreateBackdrop(bf)
        if bf.ForfeitButton then ns.HandleButton(bf.ForfeitButton) end
        if bf.CatchButton then ns.HandleButton(bf.CatchButton) end
        if bf.SwitchPetButton then ns.HandleButton(bf.SwitchPetButton) end
    end
end
