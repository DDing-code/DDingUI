-- DDingUI_Essential: Skins/Professions.lua -- [ESSENTIAL]
-- Professions, ProfessionsOrders, Archaeology, Socket, ItemUpgrade, ScrappingMachine

local _, ns = ...
ns.onDemandSkins = ns.onDemandSkins or {}
local skins = ns.onDemandSkins

------------------------------------------------------------------------
-- Professions -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_Professions"] = function()
    local frame = _G.ProfessionsFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    -- Tabs -- [ESSENTIAL]
    local i = 1
    while frame["Tab"..i] or _G["ProfessionsFrameTab"..i] do
        local tab = frame["Tab"..i] or _G["ProfessionsFrameTab"..i]
        if tab then ns.HandleTab(tab) end
        i = i + 1
    end

    -- CraftingPage -- [ESSENTIAL]
    if frame.CraftingPage then
        local cp = frame.CraftingPage
        ns.StripTextures(cp)
        if cp.CreateButton then ns.HandleButton(cp.CreateButton) end
        if cp.CreateAllButton then ns.HandleButton(cp.CreateAllButton) end
        if cp.SchematicForm then
            ns.StripTextures(cp.SchematicForm)
            -- Reagent slots -- [ESSENTIAL]
            if cp.SchematicForm.Reagents then
                for _, reagent in next, { cp.SchematicForm.Reagents:GetChildren() } do
                    if reagent and reagent.Button and not reagent.Button._ddeSkinned then
                        ns.HandleItemButton(reagent.Button)
                    end
                end
            end
        end
        -- Recipe list ScrollBar -- [ESSENTIAL]
        if cp.RecipeList and cp.RecipeList.ScrollBar then
            ns.HandleScrollBar(cp.RecipeList.ScrollBar)
        end
        -- Output icon -- [ESSENTIAL]
        if cp.SchematicForm and cp.SchematicForm.OutputIcon then
            ns.HandleItemButton(cp.SchematicForm.OutputIcon)
        end
    end

    -- SpecPage -- [ESSENTIAL]
    if frame.SpecPage then
        ns.StripTextures(frame.SpecPage)
        if frame.SpecPage.ApplyButton then ns.HandleButton(frame.SpecPage.ApplyButton) end
    end

    -- OrdersPage -- [ESSENTIAL]
    if frame.OrdersPage then
        ns.StripTextures(frame.OrdersPage)
        if frame.OrdersPage.BrowseFrame then
            ns.StripTextures(frame.OrdersPage.BrowseFrame)
            if frame.OrdersPage.BrowseFrame.ScrollBar then
                ns.HandleScrollBar(frame.OrdersPage.BrowseFrame.ScrollBar)
            end
        end
    end
end

------------------------------------------------------------------------
-- ProfessionsOrders -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_ProfessionsCustomerOrders"] = function()
    local frame = _G.ProfessionsCustomerOrdersFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    local i = 1
    while _G["ProfessionsCustomerOrdersFrameTab"..i] do
        ns.HandleTab(_G["ProfessionsCustomerOrdersFrameTab"..i])
        i = i + 1
    end

    if frame.Form then
        ns.StripTextures(frame.Form)
        if frame.Form.BackButton then ns.HandleButton(frame.Form.BackButton) end
        if frame.Form.PlaceOrderButton then ns.HandleButton(frame.Form.PlaceOrderButton) end
    end

    if frame.BrowseFrame then
        ns.StripTextures(frame.BrowseFrame)
        if frame.BrowseFrame.SearchButton then ns.HandleButton(frame.BrowseFrame.SearchButton) end
        if frame.BrowseFrame.FavoritesSearchButton then ns.HandleButton(frame.BrowseFrame.FavoritesSearchButton) end
        if frame.BrowseFrame.ScrollBar then ns.HandleScrollBar(frame.BrowseFrame.ScrollBar) end
    end
end

------------------------------------------------------------------------
-- Archaeology -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_ArchaeologyUI"] = function()
    local frame = _G.ArchaeologyFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.Inset then ns.StripTextures(frame.Inset) end
    if _G.ArchaeologyFrameArtifactPageSolveFrameSolveButton then
        ns.HandleButton(_G.ArchaeologyFrameArtifactPageSolveFrameSolveButton)
    end
end

------------------------------------------------------------------------
-- Socket -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_ItemSocketingUI"] = function()
    local frame = _G.ItemSocketingFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if _G.ItemSocketingFrameInset then ns.StripTextures(_G.ItemSocketingFrameInset) end
    if _G.ItemSocketingSocketButton then ns.HandleButton(_G.ItemSocketingSocketButton) end

    for i = 1, MAX_NUM_SOCKETS or 3 do
        local socket = _G["ItemSocketingSocket"..i]
        if socket then
            ns.HandleItemButton(socket)
        end
    end
end

------------------------------------------------------------------------
-- ItemUpgrade -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_ItemUpgradeUI"] = function()
    local frame = _G.ItemUpgradeFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.UpgradeButton then ns.HandleButton(frame.UpgradeButton) end

    -- Item slot icon -- [ESSENTIAL]
    if frame.ItemButton then ns.HandleItemButton(frame.ItemButton) end
end

------------------------------------------------------------------------
-- ScrappingMachine -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_ScrappingMachineUI"] = function()
    local frame = _G.ScrappingMachineFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.ScrapButton then ns.HandleButton(frame.ScrapButton) end

    -- Scrapping item slots -- [ESSENTIAL]
    if frame.ItemSlots then
        for _, slot in next, { frame.ItemSlots:GetChildren() } do
            if slot and not slot._ddeSkinned then
                ns.HandleItemButton(slot)
            end
        end
    end
end

------------------------------------------------------------------------
-- Obliterum -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_ObliterumUI"] = function()
    local frame = _G.ObliterumForgeFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    if frame.ObliterateButton then ns.HandleButton(frame.ObliterateButton) end
end
