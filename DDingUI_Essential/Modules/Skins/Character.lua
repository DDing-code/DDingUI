-- DDingUI_Essential: Skins/Character.lua -- [ESSENTIAL]
-- Inspect, DressingRoom, Barber, PlayerChoice, Tabard, GuildRegistrar, Petition

local _, ns = ...
ns.onDemandSkins = ns.onDemandSkins or {}
local skins = ns.onDemandSkins

------------------------------------------------------------------------
-- Inspect -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_InspectUI"] = function()
    local frame = _G.InspectFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    local i = 1
    while _G["InspectFrameTab"..i] do
        ns.HandleTab(_G["InspectFrameTab"..i])
        i = i + 1
    end

    if _G.InspectPaperDollFrame then ns.StripTextures(_G.InspectPaperDollFrame) end
    if _G.InspectModelFrame then ns.StripTextures(_G.InspectModelFrame) end

    -- Inspect item slots -- [ESSENTIAL]
    local slotNames = {
        "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
        "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
        "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
        "MainHandSlot", "SecondaryHandSlot",
    }
    for _, slotName in ipairs(slotNames) do
        local slot = _G["Inspect"..slotName]
        if slot then ns.HandleItemButton(slot) end
    end
end

------------------------------------------------------------------------
-- DressingRoom -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_DressingRoom"] = function()
    local frame = _G.DressUpFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.ResetButton then ns.HandleButton(frame.ResetButton) end
    if _G.DressUpFrameCancelButton then ns.HandleButton(_G.DressUpFrameCancelButton) end
    if _G.DressUpFrameOutfitDropdown then ns.HandleDropdown(_G.DressUpFrameOutfitDropdown) end

    -- SideDressUpFrame -- [ESSENTIAL]
    local side = _G.SideDressUpFrame
    if side then
        ns.HandleFrame(side)
        if side.ResetButton then ns.HandleButton(side.ResetButton) end
    end
end

------------------------------------------------------------------------
-- Barber -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_BarberUI"] = function()
    local frame = _G.BarberShopFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if frame.AcceptButton then ns.HandleButton(frame.AcceptButton) end
    if frame.CancelButton then ns.HandleButton(frame.CancelButton) end
    if frame.ResetButton then ns.HandleButton(frame.ResetButton) end
end

------------------------------------------------------------------------
-- PlayerChoice -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_PlayerChoice"] = function()
    local frame = _G.PlayerChoiceFrame
    if not frame or frame._ddeSkinned then return end
    frame._ddeSkinned = true

    ns.StripTextures(frame)
    ns.CreateBackdrop(frame)
    if frame.CloseButton then ns.HandleCloseButton(frame.CloseButton) end
end

------------------------------------------------------------------------
-- Tabard -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_TabardUI"] = function()
    local frame = _G.TabardFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)
    ns.SkinAccentLine(frame)

    if _G.TabardFrameAcceptButton then ns.HandleButton(_G.TabardFrameAcceptButton) end
    if _G.TabardFrameCancelButton then ns.HandleButton(_G.TabardFrameCancelButton) end
end

------------------------------------------------------------------------
-- GuildRegistrar -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_GuildRegistrar"] = function()
    local frame = _G.GuildRegistrarFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)

    if _G.GuildRegistrarFrameEditBox then ns.HandleEditBox(_G.GuildRegistrarFrameEditBox) end
    if _G.GuildRegistrarFrameGoodbyeButton then ns.HandleButton(_G.GuildRegistrarFrameGoodbyeButton) end
    if _G.GuildRegistrarFramePurchaseButton then ns.HandleButton(_G.GuildRegistrarFramePurchaseButton) end
    if _G.GuildRegistrarFrameCancelButton then ns.HandleButton(_G.GuildRegistrarFrameCancelButton) end
end

------------------------------------------------------------------------
-- Petition -- [ESSENTIAL]
------------------------------------------------------------------------
skins["Blizzard_Petition"] = function()
    local frame = _G.PetitionFrame
    if not frame or frame._ddeSkinned then return end
    ns.HandleFrame(frame)

    if _G.PetitionFrameSignButton then ns.HandleButton(_G.PetitionFrameSignButton) end
    if _G.PetitionFrameRequestButton then ns.HandleButton(_G.PetitionFrameRequestButton) end
    if _G.PetitionFrameRenameButton then ns.HandleButton(_G.PetitionFrameRenameButton) end
    if _G.PetitionFrameCancelButton then ns.HandleButton(_G.PetitionFrameCancelButton) end
end
