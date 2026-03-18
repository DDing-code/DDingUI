-- DDingUI_Essential: Skins/Trade.lua -- [ESSENTIAL]
-- AuctionHouse, Mail, Merchant, Trade, GuildBank, BlackMarket

local _, ns = ...
ns.onDemandSkins = ns.onDemandSkins or {}
local skins = ns.onDemandSkins

------------------------------------------------------------------------
-- AuctionHouse -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_AuctionHouseUI"] = function()
    local frame = _G.AuctionHouseFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    -- Tabs -- [ESSENTIAL]
    local i = 1
    while _G["AuctionHouseFrameTab"..i] or (frame.Tabs and frame.Tabs[i]) do
        local tab = _G["AuctionHouseFrameTab"..i] or (frame.Tabs and frame.Tabs[i])
        if tab then ns.HandleTab(tab) end
        i = i + 1
    end

    if frame.SearchBar then
        if frame.SearchBar.SearchBox then ns.HandleEditBox(frame.SearchBar.SearchBox) end
        if frame.SearchBar.SearchButton then ns.HandleButton(frame.SearchBar.SearchButton) end
    end

    -- Buy/Sell -- [ESSENTIAL]
    if frame.BuyTab then ns.StripTextures(frame.BuyTab) end

    -- CommoditiesBuyFrame -- [ESSENTIAL]
    if frame.CommoditiesBuyFrame then
        local cbf = frame.CommoditiesBuyFrame
        if cbf.BuyDisplay then
            if cbf.BuyDisplay.BuyButton then ns.HandleButton(cbf.BuyDisplay.BuyButton) end
            if cbf.BuyDisplay.QuantityInput and cbf.BuyDisplay.QuantityInput.InputBox then
                ns.HandleEditBox(cbf.BuyDisplay.QuantityInput.InputBox)
            end
        end
    end

    -- ItemBuyFrame -- [ESSENTIAL]
    if frame.ItemBuyFrame then
        local ibf = frame.ItemBuyFrame
        if ibf.BuyoutButton then ns.HandleButton(ibf.BuyoutButton) end
        if ibf.BidButton then ns.HandleButton(ibf.BidButton) end
        if ibf.BidFrame and ibf.BidFrame.BidAmount then ns.HandleEditBox(ibf.BidFrame.BidAmount) end
        if ibf.ScrollBar then ns.HandleScrollBar(ibf.ScrollBar) end
    end

    -- ItemSellFrame -- [ESSENTIAL]
    if frame.ItemSellFrame then
        local isf = frame.ItemSellFrame
        if isf.PostButton then ns.HandleButton(isf.PostButton) end
        if isf.QuantityInput and isf.QuantityInput.InputBox then
            ns.HandleEditBox(isf.QuantityInput.InputBox)
        end
        if isf.PriceInput and isf.PriceInput.MoneyInputFrame then
            local mif = isf.PriceInput.MoneyInputFrame
            if mif.GoldBox then ns.HandleEditBox(mif.GoldBox) end
            if mif.SilverBox then ns.HandleEditBox(mif.SilverBox) end
        end
    end

    -- CommoditiesSellFrame -- [ESSENTIAL]
    if frame.CommoditiesSellFrame then
        local csf = frame.CommoditiesSellFrame
        if csf.PostButton then ns.HandleButton(csf.PostButton) end
        if csf.QuantityInput and csf.QuantityInput.InputBox then
            ns.HandleEditBox(csf.QuantityInput.InputBox)
        end
        if csf.PriceInput and csf.PriceInput.MoneyInputFrame then
            local mif = csf.PriceInput.MoneyInputFrame
            if mif.GoldBox then ns.HandleEditBox(mif.GoldBox) end
            if mif.SilverBox then ns.HandleEditBox(mif.SilverBox) end
        end
    end

    if frame.CancelAuctionButton then ns.HandleButton(frame.CancelAuctionButton) end
end

------------------------------------------------------------------------
-- Mail -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_MailUI"] = function()
    local frame = _G.MailFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    for i = 1, 2 do
        local tab = _G["MailFrameTab"..i]
        if tab then ns.HandleTab(tab) end
    end
    if _G.MailFrameInset then ns.StripTextures(_G.MailFrameInset) end

    -- Inbox items -- [ESSENTIAL]
    if _G.InboxFrame then
        ns.StripTextures(_G.InboxFrame)
        for i = 1, 7 do
            local item = _G["MailItem"..i]
            if item then
                ns.StripTextures(item)
                local btn = item.Button or _G["MailItem"..i.."Button"]
                if btn then ns.HandleItemButton(btn) end
            end
        end
    end

    -- Send -- [ESSENTIAL]
    if _G.SendMailFrame then
        ns.StripTextures(_G.SendMailFrame)
        if _G.SendMailNameEditBox then ns.HandleEditBox(_G.SendMailNameEditBox) end
        if _G.SendMailSubjectEditBox then ns.HandleEditBox(_G.SendMailSubjectEditBox) end
        if _G.SendMailBodyEditBox then ns.HandleEditBox(_G.SendMailBodyEditBox) end
        if _G.SendMailMailButton then ns.HandleButton(_G.SendMailMailButton) end
        if _G.SendMailCancelButton then ns.HandleButton(_G.SendMailCancelButton) end
        if _G.SendMailMoneyGold then ns.HandleEditBox(_G.SendMailMoneyGold) end
        if _G.SendMailMoneySilver then ns.HandleEditBox(_G.SendMailMoneySilver) end
        if _G.SendMailMoneyCopper then ns.HandleEditBox(_G.SendMailMoneyCopper) end

        -- Attachment icons -- [ESSENTIAL]
        for i = 1, 16 do
            local att = _G["SendMailAttachment"..i]
            if att then ns.HandleItemButton(att) end
        end
    end

    -- Open mail -- [ESSENTIAL]
    if _G.OpenMailFrame then
        ns.HandleFrame(_G.OpenMailFrame)
        if _G.OpenMailReplyButton then ns.HandleButton(_G.OpenMailReplyButton) end
        if _G.OpenMailDeleteButton then ns.HandleButton(_G.OpenMailDeleteButton) end
        if _G.OpenMailCancelButton then ns.HandleButton(_G.OpenMailCancelButton) end
        if _G.OpenMailReportSpamButton then ns.HandleButton(_G.OpenMailReportSpamButton) end
        if _G.OpenMailScrollFrame and _G.OpenMailScrollFrame.ScrollBar then
            ns.HandleScrollBar(_G.OpenMailScrollFrame.ScrollBar)
        end
        -- Attachment icons -- [ESSENTIAL]
        for i = 1, 16 do
            local att = _G["OpenMailAttachmentButton"..i]
            if att then ns.HandleItemButton(att) end
        end
    end
end

------------------------------------------------------------------------
-- Merchant -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_MerchantFrame"] = function()
    local frame = _G.MerchantFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    for i = 1, 2 do
        local tab = _G["MerchantFrameTab"..i]
        if tab then ns.HandleTab(tab) end
    end
    if _G.MerchantFrameInset then ns.StripTextures(_G.MerchantFrameInset) end

    if _G.MerchantBuyBackItem then ns.StripTextures(_G.MerchantBuyBackItem) end
    if _G.MerchantRepairAllButton then ns.HandleButton(_G.MerchantRepairAllButton) end
    if _G.MerchantRepairItemButton then ns.HandleButton(_G.MerchantRepairItemButton) end
    if _G.MerchantGuildBankRepairButton then ns.HandleButton(_G.MerchantGuildBankRepairButton) end
    if _G.MerchantNextPageButton then ns.HandleButton(_G.MerchantNextPageButton) end
    if _G.MerchantPrevPageButton then ns.HandleButton(_G.MerchantPrevPageButton) end

    -- Item slots with icon TexCoord -- [ESSENTIAL]
    for i = 1, MERCHANT_ITEMS_PER_PAGE or 10 do
        local btn = _G["MerchantItem"..i.."ItemButton"]
        if btn then
            ns.HandleItemButton(btn)
        end
        local item = _G["MerchantItem"..i]
        if item then ns.StripTextures(item) end
    end

    -- Buyback -- [ESSENTIAL]
    local bb = _G.MerchantBuyBackItemItemButton
    if bb then ns.HandleItemButton(bb) end
end

------------------------------------------------------------------------
-- Trade -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_TradeFrame"] = function()
    local frame = _G.TradeFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if _G.TradeFrameInset then ns.StripTextures(_G.TradeFrameInset) end
    if _G.TradeFrameTradeButton then ns.HandleButton(_G.TradeFrameTradeButton) end
    if _G.TradeFrameCancelButton then ns.HandleButton(_G.TradeFrameCancelButton) end

    -- Money -- [ESSENTIAL]
    if _G.TradePlayerInputMoneyFrameGold then ns.HandleEditBox(_G.TradePlayerInputMoneyFrameGold) end
    if _G.TradePlayerInputMoneyFrameSilver then ns.HandleEditBox(_G.TradePlayerInputMoneyFrameSilver) end
    if _G.TradePlayerInputMoneyFrameCopper then ns.HandleEditBox(_G.TradePlayerInputMoneyFrameCopper) end

    -- Trade item slots -- [ESSENTIAL]
    for i = 1, 7 do
        local playerBtn = _G["TradePlayerItem"..i.."ItemButton"]
        if playerBtn then ns.HandleItemButton(playerBtn) end
        local targetBtn = _G["TradeRecipientItem"..i.."ItemButton"]
        if targetBtn then ns.HandleItemButton(targetBtn) end
    end
end

------------------------------------------------------------------------
-- GuildBank -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_GuildBankUI"] = function()
    local frame = _G.GuildBankFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    for i = 1, 8 do
        local tab = _G["GuildBankTab"..i]
        if tab then
            ns.StripTextures(tab)
            if tab.Button then ns.HandleItemButton(tab.Button) end
        end
    end
    if _G.GuildBankFrameDepositButton then ns.HandleButton(_G.GuildBankFrameDepositButton) end
    if _G.GuildBankFrameWithdrawButton then ns.HandleButton(_G.GuildBankFrameWithdrawButton) end
    if _G.GuildBankFramePurchaseButton then ns.HandleButton(_G.GuildBankFramePurchaseButton) end
    if _G.GuildBankInfoSaveButton then ns.HandleButton(_G.GuildBankInfoSaveButton) end

    -- Item slots -- [ESSENTIAL]
    for col = 1, 7 do
        for btn = 1, 14 do
            local slot = _G["GuildBankColumn"..col.."Button"..btn]
            if slot then ns.HandleItemButton(slot) end
        end
    end
end

------------------------------------------------------------------------
-- BlackMarket -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_BlackMarketUI"] = function()
    local frame = _G.BlackMarketFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.Inset then ns.StripTextures(frame.Inset) end
    if frame.BidButton then ns.HandleButton(frame.BidButton) end
    if frame.MoneyFrameBorder then ns.StripTextures(frame.MoneyFrameBorder) end
    if frame.ScrollBar then ns.HandleScrollBar(frame.ScrollBar) end
end
