-- DDingUI_Essential: Skins/Misc.lua -- [ESSENTIAL]
-- ChromieTime, Contribution, ItemInteraction, SubscriptionInterstitial, QuestChoice
-- TutorialFrame, BattlefieldMap, GMChat, RaidUI, LossControl, CooldownViewer
-- GarrisonTooltip, LFGuild, CompactRaidFrames, NPE, OrderHall, ExpansionLanding

local _, ns = ...
ns.onDemandSkins = ns.onDemandSkins or {}
local skins = ns.onDemandSkins

skins["Blizzard_ChromieTimeUI"] = function()
    local frame = _G.ChromieTimeFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    if frame.SelectButton then ns.HandleButton(frame.SelectButton) end
    if frame.CloseButton then ns.HandleCloseButton(frame.CloseButton) end
end

skins["Blizzard_Contribution"] = function()
    local frame = _G.ContributionCollectionFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
end

skins["Blizzard_ItemInteractionUI"] = function()
    local frame = _G.ItemInteractionFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    if frame.ButtonFrame and frame.ButtonFrame.ActionButton then
        ns.HandleButton(frame.ButtonFrame.ActionButton)
    end
end

skins["Blizzard_SubscriptionInterstitialUI"] = function()
    local frame = _G.SubscriptionInterstitialFrame
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true
    ns.StripTextures(frame)
    ns.CreateBackdrop(frame)
    if frame.ClosePanelButton then ns.HandleButton(frame.ClosePanelButton) end
end

skins["Blizzard_QuestChoice"] = function()
    local frame = _G.QuestChoiceFrame
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true
    ns.StripTextures(frame)
    ns.CreateBackdrop(frame)
    if frame.CloseButton then ns.HandleCloseButton(frame.CloseButton) end
end

skins["Blizzard_TutorialFrame"] = function()
    local frame = _G.TutorialFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
end

skins["Blizzard_BattlefieldMap"] = function()
    local frame = _G.BattlefieldMapFrame
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true
    ns.StripTextures(frame)
    ns.CreateBackdrop(frame)
    if frame.CloseButton then ns.HandleCloseButton(frame.CloseButton) end
end

skins["Blizzard_GMChatUI"] = function()
    local frame = _G.GMChatFrame
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true
    ns.StripTextures(frame)
    ns.CreateBackdrop(frame)
end

skins["Blizzard_RaidUI"] = function()
    if _G.RaidFrameAllAssistCheckButton then
        ns.HandleCheckButton(_G.RaidFrameAllAssistCheckButton)
    end
end

skins["Blizzard_UIWidgets"] = function()
    local loc = _G.LossOfControlFrame
    if loc and not loc._ddeSkinned then
        loc._ddeSkinned = true
        if loc.Icon then
            ns.HandleIcon(loc.Icon, loc, false)
        end
    end
end

skins["Blizzard_CooldownViewer"] = function()
    local frame = _G.CooldownViewerFrame or _G.SpellCooldownViewerFrame
    if frame and not frame._ddeSkinned then
        ns.HandleFrame(frame)
    end
end

skins["Blizzard_GarrisonTemplates"] = function()
    local tooltips = {
        _G.GarrisonFollowerTooltip,
        _G.FloatingGarrisonFollowerTooltip,
        _G.FloatingGarrisonMissionTooltip,
        _G.FloatingGarrisonShipyardFollowerTooltip,
        _G.GarrisonFollowerAbilityTooltip,
        _G.FloatingGarrisonFollowerAbilityTooltip,
        _G.GarrisonMissionMechanicTooltip,
        _G.GarrisonMissionMechanicFollowerCounterTooltip,
        _G.GarrisonShipyardMapMissionTooltip,
    }
    for _, tt in ipairs(tooltips) do
        if tt and not tt._ddeSkinned then
            tt._ddeSkinned = true
            ns.StripTextures(tt)
            ns.CreateBackdrop(tt)
        end
    end
end

skins["Blizzard_LookingForGuildUI"] = function()
    local frame = _G.LookingForGuildFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    local i = 1
    while _G["LookingForGuildFrameTab"..i] do
        ns.HandleTab(_G["LookingForGuildFrameTab"..i])
        i = i + 1
    end
    if _G.LookingForGuildBrowseButton then ns.HandleButton(_G.LookingForGuildBrowseButton) end
    if _G.LookingForGuildRequestButton then ns.HandleButton(_G.LookingForGuildRequestButton) end
end

skins["Blizzard_CompactRaidFrames"] = function()
    local manager = _G.CompactRaidFrameManager
    if manager and not manager._ddeSkinned then
        manager._ddeSkinned = true
        ns.StripTextures(manager)
    end
end

skins["Blizzard_NewPlayerExperience"] = function()
    local frame = _G.GuideFrame or _G.NPE_TutorialMainFrame
    if frame and not frame._ddeSkinned then
        ns.HandleFrame(frame)
    end
end

skins["Blizzard_OrderHallUI"] = function()
    local frame = _G.OrderHallCommandBar
    if frame and not frame._ddeSkinned then
        frame._ddeSkinned = true
        ns.StripTextures(frame)
        ns.CreateBackdrop(frame)
    end
end

skins["Blizzard_ExpansionLandingPage"] = function()
    local frame = _G.ExpansionLandingPage
    if frame and not frame._ddeSkinned then
        ns.HandleFrame(frame)
        ns.SkinAccentLine(frame)
    end
end
