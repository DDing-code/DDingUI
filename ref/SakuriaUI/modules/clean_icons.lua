local cleanedButtons = {}

local prefixes = {
    "Action",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "PetAction",
    "Stance",
}

local SAKURA_BG    = "Interface\\AddOns\\SakuriaUI\\backgrounds\\sakuIcon.png"
local FLAT_BG      = "Interface\\Buttons\\WHITE8x8"
local SAKURA_ALPHA = 0.35

local function GetButtonIcon(btn)
    return btn and (btn.icon or btn.Icon or btn.IconTexture)
end

local function ForEachButton(fn)
    for _, prefix in ipairs(prefixes) do
        for i = 1, 12 do
            local btn = _G[prefix .. "Button" .. i]
            if btn then
                fn(btn)
            end
        end
    end
end

local function ResetCooldownVisual(btn)
    local icon = GetButtonIcon(btn)
    if icon then
        icon:SetDesaturation(0)
    end
    if btn then
        btn:SetAlpha(1)
    end
end

-- Curve-based cooldown fading/desaturation (ty WoWUIDev)
local desaturationCurve = C_CurveUtil.CreateCurve()
desaturationCurve:SetType(Enum.LuaCurveType.Step)
desaturationCurve:AddPoint(0, 0)
desaturationCurve:AddPoint(0.001, 1)

local alphaCurve = C_CurveUtil.CreateCurve()
alphaCurve:SetType(Enum.LuaCurveType.Step)
alphaCurve:AddPoint(0, 1)
alphaCurve:AddPoint(0.001, 0.8) -- "on cooldown" alpha

local function Sakuria_UpdateCooldownVisual(btn)
    if not btn then
        return
    end

    local icon = GetButtonIcon(btn)
    if not icon then
        return
    end

    if not btn.action then
        ResetCooldownVisual(btn)
        return
    end

    local durationObj

    local actionType, actionID = GetActionInfo(btn.action)
    if actionType == "item" then
        local startTime, durationSecond = C_Item.GetItemCooldown(actionID)
        if durationSecond and durationSecond > 1.5 then -- ignore GCD
            durationObj = C_DurationUtil.CreateDuration()
            durationObj:SetTimeFromStart(startTime, durationSecond)
        end
    elseif actionType then
        local cooldown = C_ActionBar.GetActionCooldown(btn.action)
        if cooldown and not cooldown.isOnGCD then
            durationObj = C_ActionBar.GetActionCooldownDuration(btn.action)
        end
    end

    if durationObj then
        icon:SetDesaturation(durationObj:EvaluateRemainingDuration(desaturationCurve))
        btn:SetAlpha(durationObj:EvaluateRemainingDuration(alphaCurve))
    else
        ResetCooldownVisual(btn)
    end
end

local cooldownEventFrame
local function EnsureCooldownEventFrame()
    if cooldownEventFrame then
        return
    end

    cooldownEventFrame = CreateFrame("Frame")
    cooldownEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    cooldownEventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")

    cooldownEventFrame:SetScript("OnEvent", function()
        for btn in pairs(cleanedButtons) do
            if btn and btn.GetObjectType then
                Sakuria_UpdateCooldownVisual(btn)
            end
        end
    end)
end

local function HookCooldownVisuals(btn)
    if not btn or btn.__SakuriaUI_CooldownHooked then
        return
    end

    if btn.action then
        if btn.UpdateAction then
            hooksecurefunc(btn, "UpdateAction", Sakuria_UpdateCooldownVisual)
        end

        local cd = btn.cooldown or btn.Cooldown
        if cd and cd.HookScript and not cd.__SakuriaUI_OnDoneHooked then
            cd:HookScript("OnCooldownDone", function()
                Sakuria_UpdateCooldownVisual(btn)
            end)
            cd.__SakuriaUI_OnDoneHooked = true
        end

        EnsureCooldownEventFrame()
        Sakuria_UpdateCooldownVisual(btn)
    end

    btn.__SakuriaUI_CooldownHooked = true
end

local function FlowerEnabled()
    return (SakuriaUI_DB and SakuriaUI_DB.iconFlower) ~= false
end

local function GetBackdropTexture()
    return FlowerEnabled() and SAKURA_BG or FLAT_BG
end

local function ApplyBackdropStyle(tex)
    if not tex then
        return
    end

    if tex.SetVertexColor then
        if FlowerEnabled() then
            tex:SetVertexColor(1, 1, 1, 1)
        else
            tex:SetVertexColor(0, 0, 0, 1)
        end
    end

    if tex.SetBlendMode then
        tex:SetBlendMode(FlowerEnabled() and "ADD" or "BLEND")
    end
end

local function StripIconMasks(icon, btn)
    if not icon then
        return
    end

    if icon.GetNumMaskTextures and icon.GetMaskTexture and icon.RemoveMaskTexture then
        for i = icon:GetNumMaskTextures(), 1, -1 do
            local m = icon:GetMaskTexture(i)
            if m then
                icon:RemoveMaskTexture(m)
                m:Hide()
                m:SetTexture(nil)
            end
        end
    end

    local candidates = {
        icon.Mask,
        icon.IconMask,
        btn and btn.IconMask,
        btn and btn.SlotArtMask,
        btn and btn.NormalTextureMask,
    }

    if icon.RemoveMaskTexture then
        for _, m in ipairs(candidates) do
            if m then
                icon:RemoveMaskTexture(m)
                m:Hide()
                m:SetTexture(nil)
            end
        end
    else
        for _, m in ipairs(candidates) do
            if m then
                m:Hide()
                m:SetTexture(nil)
            end
        end
    end
end

local function StyleButton(btn)
    if not btn or cleanedButtons[btn] then
        return
    end

    local icon = GetButtonIcon(btn)
    if not icon then
        return
    end

    StripIconMasks(icon, btn)

    if btn.NormalTexture then
        btn.NormalTexture:SetAlpha(0)
    end
    if btn.GetNormalTexture and btn:GetNormalTexture() then
        btn:GetNormalTexture():SetAlpha(0)
    end
    if btn.GetHighlightTexture and btn:GetHighlightTexture() then
        btn:GetHighlightTexture():SetAlpha(0)
    end
    if btn.GetCheckedTexture and btn:GetCheckedTexture() then
        btn:GetCheckedTexture():SetAlpha(0)
    end
    if btn.Border then
        btn.Border:SetAlpha(0)
    end
    if btn.Flash then
        btn.Flash:SetAlpha(0)
    end

    if btn.SlotBackground then
        if not btn.__SakuriaUI_OrigSlotBG then
            local r, g, b, a = 1, 1, 1, 1
            if btn.SlotBackground.GetVertexColor then
                r, g, b, a = btn.SlotBackground:GetVertexColor()
            end

            btn.__SakuriaUI_OrigSlotBG = {
                texture   = btn.SlotBackground.GetTexture and btn.SlotBackground:GetTexture(),
                alpha     = btn.SlotBackground.GetAlpha and btn.SlotBackground:GetAlpha(),
                blendMode = btn.SlotBackground.GetBlendMode and btn.SlotBackground:GetBlendMode(),
                vcR = r, vcG = g, vcB = b, vcA = a,
            }
        end

        btn.SlotBackground:Show()
        btn.SlotBackground:SetTexture(GetBackdropTexture())
        ApplyBackdropStyle(btn.SlotBackground)
        btn.SlotBackground:ClearAllPoints()
        btn.SlotBackground:SetAllPoints(btn)
        btn.SlotBackground:SetDrawLayer("BACKGROUND", -1)
        btn.SlotBackground:SetAlpha(SAKURA_ALPHA)

        if btn.SlotBackground.SetSnapToPixelGrid then
            btn.SlotBackground:SetSnapToPixelGrid(true)
            btn.SlotBackground:SetTexelSnappingBias(0)
        end

        btn.bgTexture = btn.SlotBackground
    else
        if not btn.bgTexture then
            btn.bgTexture = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        end

        btn.bgTexture:Show()
        btn.bgTexture:SetTexture(GetBackdropTexture())
        ApplyBackdropStyle(btn.bgTexture)
        btn.bgTexture:ClearAllPoints()
        btn.bgTexture:SetAllPoints(btn)
        btn.bgTexture:SetAlpha(SAKURA_ALPHA)

        if btn.bgTexture.SetSnapToPixelGrid then
            btn.bgTexture:SetSnapToPixelGrid(true)
            btn.bgTexture:SetTexelSnappingBias(0)
        end
    end

    icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
    icon:ClearAllPoints()
    icon:SetAllPoints(btn)
    icon:SetDrawLayer("BACKGROUND", 0)

    if icon.SetSnapToPixelGrid then
        icon:SetSnapToPixelGrid(true)
        icon:SetTexelSnappingBias(0)
    end

    -- New "button pushed" texture
    local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
    if pushed then
        pushed:SetTexture("Interface\\Buttons\\WHITE8x8")
        pushed:SetVertexColor(0, 0, 0, 0.6)
        pushed:SetBlendMode("BLEND")
        pushed:ClearAllPoints()
        pushed:SetAllPoints(btn)
        pushed:SetDrawLayer("ARTWORK", 2)
    end

    local cd = btn.cooldown or btn.Cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(btn)
        cd:SetFrameLevel(btn:GetFrameLevel() + 4)

        if cd.SetDrawSwipe then
            cd:SetDrawSwipe(true)
        end
        if cd.SetSwipeColor then
            cd:SetSwipeColor(0, 0, 0, 0.75)
        end
        if cd.SetDrawEdge then
            cd:SetDrawEdge(false)
        end

        cd:Show()

        if cd.SetSnapToPixelGrid then
            cd:SetSnapToPixelGrid(true)
            cd:SetTexelSnappingBias(0)
        end
    end

    local charge = btn.chargeCooldown or btn.ChargeCooldown
    if charge then
        charge:ClearAllPoints()
        charge:SetAllPoints(btn)
        charge:SetFrameLevel(btn:GetFrameLevel() + 4)

        if charge.SetDrawSwipe then
            charge:SetDrawSwipe(true)
        end
        if charge.SetSwipeColor then
            charge:SetSwipeColor(0, 0, 0, 0.75)
        end
        if charge.SetDrawEdge then
            charge:SetDrawEdge(false)
        end

        charge:Show()
    end

    if not btn.borderFrame then
        local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        border:SetAllPoints(btn)
        border:SetFrameLevel(btn:GetFrameLevel() + 10)
        border:SetBackdrop({ edgeFile = FLAT_BG, edgeSize = 1 })
        border:SetBackdropBorderColor(0, 0, 0, 1)

        if border.SetSnapToPixelGrid then
            border:SetSnapToPixelGrid(true)
            border:SetTexelSnappingBias(0)
        end

        btn.borderFrame = border
    else
        btn.borderFrame:Show()
        btn.borderFrame:SetFrameLevel(btn:GetFrameLevel() + 10)
    end

    if btn.Count then
        btn.Count:SetDrawLayer("OVERLAY", 7)
    end

    cleanedButtons[btn] = true
    HookCooldownVisuals(btn)
end

function SakuriaUI_EnableCleanIcons()
    ForEachButton(StyleButton)
end

function SakuriaUI_DisableCleanIcons()
    for btn in pairs(cleanedButtons) do
        if btn and btn.GetObjectType then
            local icon = GetButtonIcon(btn)
            if icon then
                icon:SetDesaturation(0)
                icon:SetTexCoord(0, 1, 0, 1)
                icon:ClearAllPoints()
                icon:SetAllPoints(btn)
            end

            btn:SetAlpha(1)

            if btn.bgTexture then
                btn.bgTexture:Hide()
                if btn.bgTexture ~= btn.SlotBackground then
                    btn.bgTexture:SetTexture(nil)
                end
            end

            if btn.SlotBackground and btn.bgTexture == btn.SlotBackground and btn.__SakuriaUI_OrigSlotBG then
                local orig = btn.__SakuriaUI_OrigSlotBG
                btn.SlotBackground:SetTexture(orig.texture)
                if orig.alpha ~= nil then
                    btn.SlotBackground:SetAlpha(orig.alpha)
                end
                if orig.blendMode ~= nil and btn.SlotBackground.SetBlendMode then
                    btn.SlotBackground:SetBlendMode(orig.blendMode)
                end
                if btn.SlotBackground.SetVertexColor and orig.vcR then
                    btn.SlotBackground:SetVertexColor(orig.vcR, orig.vcG, orig.vcB, orig.vcA or 1)
                end
                btn.SlotBackground:Show()
            end

            if btn.borderFrame then
                btn.borderFrame:Hide()
            end
        end
    end

    wipedata(cleanedButtons)
end