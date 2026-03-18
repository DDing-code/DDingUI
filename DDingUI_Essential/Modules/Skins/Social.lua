-- DDingUI_Essential: Skins/Social.lua -- [ESSENTIAL]
-- FriendsFrame, Communities, Guild, ChatConfig, Channels

local _, ns = ...
ns.onDemandSkins = ns.onDemandSkins or {}
local skins = ns.onDemandSkins

------------------------------------------------------------------------
-- FriendsFrame -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_FriendsFrame"] = function()
    local frame = _G.FriendsFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    -- Tabs -- [ESSENTIAL]
    local i = 1
    while _G["FriendsFrameTab"..i] do
        ns.HandleTab(_G["FriendsFrameTab"..i])
        i = i + 1
    end

    -- Insets -- [ESSENTIAL]
    if _G.FriendsFrameInset then ns.StripTextures(_G.FriendsFrameInset) end
    if _G.IgnoreListFrame then ns.StripTextures(_G.IgnoreListFrame) end

    -- ScrollBars -- [ESSENTIAL]
    if _G.FriendsListFrame and _G.FriendsListFrame.ScrollBar then
        ns.HandleScrollBar(_G.FriendsListFrame.ScrollBar)
    end

    -- Buttons -- [ESSENTIAL]
    local btnNames = {
        "FriendsFrameAddFriendButton", "FriendsFrameSendMessageButton",
        "WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton",
        "FriendsFrameIgnorePlayerButton", "FriendsFrameUnsquelchButton",
    }
    for _, name in ipairs(btnNames) do
        if _G[name] then ns.HandleButton(_G[name]) end
    end

    -- WhoFrame -- [ESSENTIAL]
    if _G.WhoFrame then
        ns.StripTextures(_G.WhoFrame)
        if _G.WhoFrameEditBox then ns.HandleEditBox(_G.WhoFrameEditBox) end
    end
    if _G.WhoFrameListInset then ns.StripTextures(_G.WhoFrameListInset) end

    -- AddFriendFrame -- [ESSENTIAL]
    if _G.AddFriendFrame then
        ns.StripTextures(_G.AddFriendFrame)
        ns.CreateBackdrop(_G.AddFriendFrame)
    end
    if _G.AddFriendNameEditBox then ns.HandleEditBox(_G.AddFriendNameEditBox) end
    if _G.AddFriendEntryFrameAcceptButton then ns.HandleButton(_G.AddFriendEntryFrameAcceptButton) end
    if _G.AddFriendEntryFrameCancelButton then ns.HandleButton(_G.AddFriendEntryFrameCancelButton) end

    -- BattleNet -- [ESSENTIAL]
    local bnet = _G.FriendsFrameBattlenetFrame
    if bnet then
        ns.StripTextures(bnet)
        ns.CreateBackdrop(bnet)
        if bnet.BroadcastFrame then
            ns.StripTextures(bnet.BroadcastFrame)
            ns.CreateBackdrop(bnet.BroadcastFrame)
            if bnet.BroadcastFrame.UpdateButton then ns.HandleButton(bnet.BroadcastFrame.UpdateButton) end
            if bnet.BroadcastFrame.CancelButton then ns.HandleButton(bnet.BroadcastFrame.CancelButton) end
            if bnet.BroadcastFrame.EditBox then ns.HandleEditBox(bnet.BroadcastFrame.EditBox) end
        end
    end

    -- QuickJoin -- [ESSENTIAL]
    if _G.QuickJoinFrame then
        if _G.QuickJoinFrame.JoinQueueButton then ns.HandleButton(_G.QuickJoinFrame.JoinQueueButton) end
        if _G.QuickJoinFrame.ScrollBar then ns.HandleScrollBar(_G.QuickJoinFrame.ScrollBar) end
    end
    if _G.QuickJoinRoleSelectionFrame then
        local qjrs = _G.QuickJoinRoleSelectionFrame
        ns.StripTextures(qjrs)
        ns.CreateBackdrop(qjrs)
        if qjrs.AcceptButton then ns.HandleButton(qjrs.AcceptButton) end
        if qjrs.CancelButton then ns.HandleButton(qjrs.CancelButton) end
        if qjrs.CloseButton then ns.HandleCloseButton(qjrs.CloseButton) end
    end

    -- FriendsFriendsFrame -- [ESSENTIAL]
    if _G.FriendsFriendsFrame then
        ns.StripTextures(_G.FriendsFriendsFrame)
        ns.CreateBackdrop(_G.FriendsFriendsFrame)
        if _G.FriendsFriendsFrame.SendRequestButton then ns.HandleButton(_G.FriendsFriendsFrame.SendRequestButton) end
        if _G.FriendsFriendsFrame.CloseButton then ns.HandleButton(_G.FriendsFriendsFrame.CloseButton) end
        if _G.FriendsFriendsFrame.Dropdown then ns.HandleDropdown(_G.FriendsFriendsFrame.Dropdown) end
    end

    -- RAF -- [ESSENTIAL]
    local raf = _G.RecruitAFriendFrame
    if raf then
        if raf.RecruitmentButton then ns.HandleButton(raf.RecruitmentButton) end
        if raf.SplashFrame and raf.SplashFrame.OKButton then ns.HandleButton(raf.SplashFrame.OKButton) end
        if raf.RewardClaiming then
            ns.StripTextures(raf.RewardClaiming)
            ns.CreateBackdrop(raf.RewardClaiming)
            if raf.RewardClaiming.ClaimOrViewRewardButton then ns.HandleButton(raf.RewardClaiming.ClaimOrViewRewardButton) end
        end
    end
end

------------------------------------------------------------------------
-- Communities -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_Communities"] = function()
    local frame = _G.CommunitiesFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.ChatEditBox then ns.HandleEditBox(frame.ChatEditBox) end
    if frame.InviteButton then ns.HandleButton(frame.InviteButton) end

    if frame.CommunitiesControlFrame then
        local cf = frame.CommunitiesControlFrame
        if cf.GuildRecruitmentButton then ns.HandleButton(cf.GuildRecruitmentButton) end
        if cf.CommunitiesSettingsButton then ns.HandleButton(cf.CommunitiesSettingsButton) end
        if cf.GuildMembersToLookButton then ns.HandleButton(cf.GuildMembersToLookButton) end
    end

    -- MemberList + ScrollBar -- [ESSENTIAL]
    if frame.MemberList then
        ns.StripTextures(frame.MemberList)
        if frame.MemberList.InsetFrame then ns.StripTextures(frame.MemberList.InsetFrame) end
        if frame.MemberList.ScrollBar then ns.HandleScrollBar(frame.MemberList.ScrollBar) end
    end

    -- Chat ScrollBar -- [ESSENTIAL]
    if frame.Chat and frame.Chat.ScrollBar then
        ns.HandleScrollBar(frame.Chat.ScrollBar)
    end

    if frame.ClubFinderFrame then ns.StripTextures(frame.ClubFinderFrame) end
end

------------------------------------------------------------------------
-- GuildUI -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_GuildUI"] = function()
    local frame = _G.GuildFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    local i = 1
    while _G["GuildFrameTab"..i] do
        ns.HandleTab(_G["GuildFrameTab"..i])
        i = i + 1
    end

    if _G.GuildFrameInset then ns.StripTextures(_G.GuildFrameInset) end
end

------------------------------------------------------------------------
-- ChatConfig -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_ChatConfig"] = function()
    local frame = _G.ChatConfigFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)

    if _G.ChatConfigFrameOkayButton then ns.HandleButton(_G.ChatConfigFrameOkayButton) end
    if _G.ChatConfigFrameDefaultButton then ns.HandleButton(_G.ChatConfigFrameDefaultButton) end
    if _G.ChatConfigFrameRedockButton then ns.HandleButton(_G.ChatConfigFrameRedockButton) end

    if _G.ChatConfigCategoryFrame then ns.StripTextures(_G.ChatConfigCategoryFrame) end
    if _G.ChatConfigBackgroundFrame then ns.StripTextures(_G.ChatConfigBackgroundFrame) end

    -- CheckButtons -- [ESSENTIAL]
    for _, child in next, { frame:GetChildren() } do
        if child and child:IsObjectType("CheckButton") and not child._ddeSkinned then
            ns.HandleCheckButton(child)
        end
    end
end

------------------------------------------------------------------------
-- Channels -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_Channels"] = function()
    local frame = _G.ChannelFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.NewButton then ns.HandleButton(frame.NewButton) end
    if frame.SettingsButton then ns.HandleButton(frame.SettingsButton) end
    if frame.ScrollBar then ns.HandleScrollBar(frame.ScrollBar) end
end
