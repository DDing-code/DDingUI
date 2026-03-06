SakuriaUI_HideBags = {
    Enable = function()
        if BagsBar then BagsBar:Hide() end
        if BagBarExpandToggle then BagBarExpandToggle:Hide() end

        local buttons = {
            MainMenuBarBackpackButton,
            CharacterReagentBag0Slot,
            CharacterBag0Slot,
            CharacterBag1Slot,
            CharacterBag2Slot,
            CharacterBag3Slot,
        }

        for _, btn in ipairs(buttons) do
            if btn then btn:Hide() end
        end
    end,
    Disable = function()
        if BagsBar then BagsBar:Show() end
        if BagBarExpandToggle then BagBarExpandToggle:Show() end

        local buttons = {
            MainMenuBarBackpackButton,
            CharacterReagentBag0Slot,
            CharacterBag0Slot,
            CharacterBag1Slot,
            CharacterBag2Slot,
            CharacterBag3Slot,
        }

        for _, btn in ipairs(buttons) do
            if btn then btn:Show() end
        end
    end,
}