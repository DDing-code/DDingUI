-- DDingUI_Essential: Skins/World.lua -- [ESSENTIAL]
-- WorldMap, Calendar, Garrison, Gossip, TalkingHead, Taxi, FlightMap, TimeManager

local _, ns = ...
ns.onDemandSkins = ns.onDemandSkins or {}
local skins = ns.onDemandSkins

------------------------------------------------------------------------
-- Calendar -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_Calendar"] = function()
    local frame = _G.CalendarFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if _G.CalendarFilterFrame then ns.StripTextures(_G.CalendarFilterFrame) end

    local create = _G.CalendarCreateEventFrame
    if create then
        ns.HandleFrame(create)
        if create.CreateButton or _G.CalendarCreateEventCreateButton then
            ns.HandleButton(create.CreateButton or _G.CalendarCreateEventCreateButton)
        end
        if _G.CalendarCreateEventInviteButton then ns.HandleButton(_G.CalendarCreateEventInviteButton) end
        if _G.CalendarCreateEventInviteEdit then ns.HandleEditBox(_G.CalendarCreateEventInviteEdit) end
    end

    local view = _G.CalendarViewEventFrame
    if view then ns.HandleFrame(view) end

    local inviteList = _G.CalendarCreateEventInviteListSection
    if inviteList then ns.StripTextures(inviteList) end

    local mass = _G.CalendarMassInviteFrame
    if mass then
        ns.HandleFrame(mass)
        if _G.CalendarMassInviteAcceptButton then ns.HandleButton(_G.CalendarMassInviteAcceptButton) end
    end
end

------------------------------------------------------------------------
-- Garrison -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_GarrisonUI"] = function()
    local lp = _G.GarrisonLandingPage
    if lp and not lp._ddeSkinned then
        ns.HandleFrame(lp)
        ns.SkinAccentLine(lp)
        local i = 1
        while _G["GarrisonLandingPageTab"..i] do
            ns.HandleTab(_G["GarrisonLandingPageTab"..i])
            i = i + 1
        end
    end

    local mf = _G.GarrisonMissionFrame
    if mf and not mf._ddeSkinned then
        ns.HandleFrame(mf)
        ns.SkinAccentLine(mf)
        for i = 1, 3 do
            local tab = mf["Tab"..i]
            if tab then ns.HandleTab(tab) end
        end
        if mf.MissionTab and mf.MissionTab.MissionPage then
            local mp = mf.MissionTab.MissionPage
            if mp.StartMissionButton then ns.HandleButton(mp.StartMissionButton) end
        end
    end

    local bf = _G.GarrisonBuildingFrame
    if bf and not bf._ddeSkinned then
        ns.HandleFrame(bf)
        ns.SkinAccentLine(bf)
        if bf.BuildButton then ns.HandleButton(bf.BuildButton) end
    end

    local cap = _G.GarrisonCapacitiveDisplayFrame
    if cap and not cap._ddeSkinned then
        ns.HandleFrame(cap)
        if cap.StartWorkOrderButton then ns.HandleButton(cap.StartWorkOrderButton) end
        if cap.CreateAllWorkOrdersButton then ns.HandleButton(cap.CreateAllWorkOrdersButton) end
    end

    local ohf = _G.OrderHallMissionFrame
    if ohf and not ohf._ddeSkinned then
        ns.HandleFrame(ohf)
        ns.SkinAccentLine(ohf)
    end

    local bfa = _G.BFAMissionFrame
    if bfa and not bfa._ddeSkinned then
        ns.HandleFrame(bfa)
        ns.SkinAccentLine(bfa)
    end

    local cov = _G.CovenantMissionFrame
    if cov and not cov._ddeSkinned then
        ns.HandleFrame(cov)
        ns.SkinAccentLine(cov)
    end
end

------------------------------------------------------------------------
-- Gossip (NPC) -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_GossipFrame"] = function()
    local frame = _G.GossipFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.GreetingPanel then
        if frame.GreetingPanel.GoodbyeButton then ns.HandleButton(frame.GreetingPanel.GoodbyeButton) end
        if frame.GreetingPanel.ScrollBar then ns.HandleScrollBar(frame.GreetingPanel.ScrollBar) end
    end
    if _G.GossipFrameInset then ns.StripTextures(_G.GossipFrameInset) end

    local itf = _G.ItemTextFrame
    if itf and not itf._ddeSkinned then
        ns.HandleFrame(itf)
        if _G.ItemTextScrollFrame then
            ns.StripTextures(_G.ItemTextScrollFrame)
            if _G.ItemTextScrollFrame.ScrollBar then
                ns.HandleScrollBar(_G.ItemTextScrollFrame.ScrollBar)
            end
        end
    end
end

------------------------------------------------------------------------
-- TalkingHead -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_TalkingHead"] = function()
    local frame = _G.TalkingHeadFrame
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true

    ns.StripTextures(frame)
    ns.CreateBackdrop(frame)
    ns.SkinAccentLine(frame)

    if frame.MainFrame then ns.StripTextures(frame.MainFrame) end
    if frame.CloseButton then ns.HandleCloseButton(frame.CloseButton) end
end

------------------------------------------------------------------------
-- Taxi -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_TaxiUI"] = function()
    local frame = _G.TaxiFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
end

------------------------------------------------------------------------
-- FlightMap -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_FlightMap"] = function()
    local frame = _G.FlightMapFrame
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true

    local borderFrame = frame.BorderFrame
    if borderFrame then
        ns.StripTextures(borderFrame)
        if borderFrame.CloseButton then ns.HandleCloseButton(borderFrame.CloseButton) end
    end
end

------------------------------------------------------------------------
-- TimeManager -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_TimeManager"] = function()
    local frame = _G.TimeManagerFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)

    if _G.StopwatchFrame then
        ns.StripTextures(_G.StopwatchFrame)
        ns.CreateBackdrop(_G.StopwatchFrame)
    end
end

------------------------------------------------------------------------
-- AdventureMap -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_AdventureMap"] = function()
    local frame = _G.AdventureMapQuestChoiceDialog
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)

    if frame.AcceptButton then ns.HandleButton(frame.AcceptButton) end
    if frame.DeclineButton then ns.HandleButton(frame.DeclineButton) end
end
