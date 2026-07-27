local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

local Visuals = {}
DDingUI.BuffTrackerConditionalVisuals = Visuals

local SL = _G.DDingUI_StyleLib
local FLAT = "Interface\\Buttons\\WHITE8x8"
local activeClaims = {}
local knownTargets = {}
local targetStates = {}
local stagedClaims
local stagedTargets

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function ResolveTargetFrame(targetKey)
    local cooldownID = targetKey and targetKey:match("^cdm:(%d+)$")
    cooldownID = tonumber(cooldownID)
    if cooldownID then
        local scanner = DDingUI.CDMScanner
        if not scanner or not scanner.FindFrameByCooldownID then return nil end
        local entry = scanner.GetEntry and scanner.GetEntry(cooldownID)
        if entry and entry.iconFrame then
            return entry.iconFrame
        end
        return scanner.FindFrameByCooldownID(cooldownID)
    end

    local iconKey = targetKey and targetKey:match("^custom:(.+)$")
    local customIcons = DDingUI.CustomIcons
    local frames = customIcons and customIcons.GetAllIconFrames and customIcons:GetAllIconFrames()
    return iconKey and frames and frames[iconKey] or nil
end

local function GetIconTexture(frame)
    if not frame then return nil end

    local texture = frame.Icon or frame.icon or frame.Texture
    if texture and texture.SetVertexColor then
        return texture
    end
    if texture and texture.Icon and texture.Icon.SetVertexColor then
        return texture.Icon
    end
    return nil
end

local function StopGlow(state)
    local overlay = state and state.glowOverlay
    if not overlay then return end

    if SL and SL.HideAllGlows then
        SL.HideAllGlows(overlay)
    end
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.ProcGlow_Stop then
        LCG.ProcGlow_Stop(overlay)
    end
    overlay:Hide()
    state.glowSignature = nil
end

local function RestoreTextureState(state)
    if state and state.appearanceTexture then
        state.appearanceTexture:Hide()
    end
    if state then
        state.appearanceSignature = nil
        state.texture = nil
    end
end

local function HideBorder(state)
    if state and state.borderOverlay then
        state.borderOverlay:Hide()
    end
    if state then
        state.borderSignature = nil
    end
end

local function BindTargetState(state, frame)
    if state.frame ~= frame then
        RestoreTextureState(state)
        StopGlow(state)
        HideBorder(state)
        state.frame = frame
    end

    local texture = GetIconTexture(frame)
    if state.texture and state.texture ~= texture then
        RestoreTextureState(state)
    end
    state.texture = texture
end

local function EnsureAppearanceTexture(state)
    local frame = state.frame
    local sourceTexture = state.texture
    if not frame or not sourceTexture then return nil end

    local texture = state.appearanceTexture
    if texture and state.appearanceFrame == frame then
        return texture
    end
    if IsInCombat() then return nil end

    if texture then
        texture:Hide()
    end
    texture = frame:CreateTexture(nil, "ARTWORK", nil, 7)
    state.appearanceTexture = texture
    state.appearanceFrame = frame
    return texture
end

local function EnsureGlowOverlay(state)
    local frame = state.frame
    if not frame then return nil end

    local overlay = state.glowOverlay
    if overlay and overlay:GetParent() == frame then
        overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 15)
        return overlay
    end
    if IsInCombat() then return nil end

    if not overlay then
        overlay = CreateFrame("Frame", nil, frame)
        overlay:EnableMouse(false)
        state.glowOverlay = overlay
    else
        overlay:SetParent(frame)
    end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 15)
    return overlay
end

local function EnsureBorderOverlay(state)
    local frame = state.frame
    if not frame then return nil end

    local overlay = state.borderOverlay
    if overlay and overlay:GetParent() == frame then
        overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 14)
        return overlay
    end
    if IsInCombat() then return nil end

    if not overlay then
        overlay = CreateFrame("Frame", nil, frame)
        overlay:EnableMouse(false)
        overlay.edges = {}
        for i = 1, 4 do
            local edge = overlay:CreateTexture(nil, "OVERLAY")
            edge:SetTexture(FLAT)
            overlay.edges[i] = edge
        end
        state.borderOverlay = overlay
    else
        overlay:SetParent(frame)
    end

    overlay:ClearAllPoints()
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 14)
    return overlay
end

local function ApplyBorder(state, claim)
    if not claim then
        HideBorder(state)
        return
    end

    local overlay = EnsureBorderOverlay(state)
    if not overlay then return end

    local color = claim.color or { 1, 0, 0, 1 }
    local thickness = math.max(1, tonumber(claim.thickness) or 2)
    local signature = table.concat({
        color[1] or 1,
        color[2] or 0,
        color[3] or 0,
        color[4] or 1,
        thickness,
    }, ":")

    if state.borderSignature ~= signature then
        local top, bottom, left, right = unpack(overlay.edges)
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", overlay, "TOPLEFT", -thickness, thickness)
        top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", thickness, thickness)
        top:SetHeight(thickness)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -thickness, -thickness)
        bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", thickness, -thickness)
        bottom:SetHeight(thickness)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", overlay, "TOPLEFT", -thickness, thickness)
        left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -thickness, -thickness)
        left:SetWidth(thickness)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", thickness, thickness)
        right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", thickness, -thickness)
        right:SetWidth(thickness)

        for _, edge in ipairs(overlay.edges) do
            edge:SetVertexColor(
                color[1] or 1,
                color[2] or 0,
                color[3] or 0,
                color[4] or 1
            )
        end
        state.borderSignature = signature
    end
    overlay:Show()
end

local function ApplyAppearance(state, tintClaim, desaturateClaim)
    if not tintClaim and not desaturateClaim then
        RestoreTextureState(state)
        state.texture = GetIconTexture(state.frame)
        return
    end

    local sourceTexture = state.texture
    local texture = EnsureAppearanceTexture(state)
    if not sourceTexture or not texture then return end

    texture:ClearAllPoints()
    texture:SetAllPoints(sourceTexture)
    local atlas = sourceTexture.GetAtlas and sourceTexture:GetAtlas()
    if atlas and atlas ~= "" then
        texture:SetAtlas(atlas, false)
    else
        texture:SetTexture(sourceTexture:GetTexture())
    end
    texture:SetTexCoord(sourceTexture:GetTexCoord())

    local color = tintClaim and tintClaim.color or { 1, 1, 1, 1 }
    local signature = table.concat({
        color[1] or 1,
        color[2] or 1,
        color[3] or 1,
        color[4] or 1,
        desaturateClaim and 1 or 0,
    }, ":")
    if state.appearanceSignature ~= signature then
        texture:SetVertexColor(
            color[1] or 1,
            color[2] or 1,
            color[3] or 1,
            color[4] or 1
        )
        texture:SetDesaturated(desaturateClaim ~= nil)
        state.appearanceSignature = signature
    end
    texture:Show()
end

local function ApplyGlow(state, claim)
    if not claim then
        StopGlow(state)
        return
    end

    local overlay = EnsureGlowOverlay(state)
    if not overlay or not SL then return end

    local color = claim.color or { 1, 0.82, 0.1, 1 }
    local glowType = claim.glowType or "pixel"
    local lines = math.floor(claim.lines or 8)
    local frequency = claim.frequency or 0.25
    local thickness = claim.thickness or 2
    local signature = table.concat({
        glowType,
        color[1] or 1,
        color[2] or 0.82,
        color[3] or 0.1,
        color[4] or 1,
        lines,
        frequency,
        thickness,
    }, ":")

    if state.glowSignature ~= signature then
        StopGlow(state)
        overlay:Show()
        if glowType == "pixel" and SL.ShowPixelGlow then
            SL.ShowPixelGlow(overlay, color, lines, frequency, nil, thickness, 0, 0)
        elseif glowType == "autocast" and SL.ShowAutocastGlow then
            SL.ShowAutocastGlow(overlay, color, lines, frequency, thickness, 0, 0)
        elseif glowType == "button" and SL.ShowButtonGlow then
            SL.ShowButtonGlow(overlay, color, frequency)
        elseif glowType == "proc" then
            local LCG = LibStub("LibCustomGlow-1.0", true)
            if LCG and LCG.ProcGlow_Start then
                LCG.ProcGlow_Start(overlay, {
                    color = color,
                    duration = frequency,
                    startAnim = true,
                })
            end
        end
        state.glowSignature = signature
    else
        overlay:Show()
    end
end

local function SelectClaim(claims, claimType, property)
    local selected
    for _, claim in pairs(claims or {}) do
        if claim.type == claimType and (not property or claim.property == property) then
            if not selected or (claim.priority or 0) >= (selected.priority or 0) then
                selected = claim
            end
        end
    end
    return selected
end

local function RefreshTarget(targetKey)
    local claims = activeClaims[targetKey]
    local frame = ResolveTargetFrame(targetKey)
    local state = targetStates[targetKey]

    if not state then
        state = {}
        targetStates[targetKey] = state
    end
    if not frame then
        RestoreTextureState(state)
        StopGlow(state)
        HideBorder(state)
        state.frame = nil
        return
    end

    BindTargetState(state, frame)
    local targetInfo = knownTargets[targetKey]
    if not IsInCombat() and targetInfo then
        if targetInfo.appearance then EnsureAppearanceTexture(state) end
        if targetInfo.glow then EnsureGlowOverlay(state) end
        if targetInfo.border then EnsureBorderOverlay(state) end
    end

    ApplyAppearance(
        state,
        SelectClaim(claims, "color", "icon"),
        SelectClaim(claims, "desaturate")
    )
    ApplyBorder(state, SelectClaim(claims, "color", "border"))
    ApplyGlow(state, SelectClaim(claims, "glow"))
end

local function RefreshAll()
    local targets = {}
    for targetKey in pairs(targetStates) do targets[targetKey] = true end
    for targetKey in pairs(knownTargets) do targets[targetKey] = true end
    for targetKey in pairs(activeClaims) do targets[targetKey] = true end
    for targetKey in pairs(targets) do RefreshTarget(targetKey) end
end

function Visuals:BeginPass()
    stagedClaims = {}
    stagedTargets = {}
end

function Visuals:SetClaim(sourceIndex, actionIndex, targetKey, claim, actionType, colorTarget)
    if type(targetKey) ~= "string"
        or (not targetKey:match("^cdm:%d+$") and not targetKey:match("^custom:.+$"))
    then
        return
    end

    local claims = stagedClaims or activeClaims
    local targets = stagedTargets or knownTargets
    local ownerKey = tostring(sourceIndex or 0) .. ":" .. tostring(actionIndex or 0)
    local targetInfo = targets[targetKey]
    if not targetInfo then
        targetInfo = {}
        targets[targetKey] = targetInfo
    end
    if actionType == "glow" then
        targetInfo.glow = true
    elseif actionType == "desaturate" or (actionType == "color" and colorTarget == "icon") then
        targetInfo.appearance = true
    elseif actionType == "color" and colorTarget == "border" then
        targetInfo.border = true
    end

    local bucket = claims[targetKey]
    if claim then
        if not bucket then
            bucket = {}
            claims[targetKey] = bucket
        end
        claim.priority = (tonumber(sourceIndex) or 0) * 100 + (tonumber(actionIndex) or 0)
        bucket[ownerKey] = claim
    elseif bucket then
        bucket[ownerKey] = nil
        if not next(bucket) then
            claims[targetKey] = nil
        end
    end

    if not stagedClaims then
        RefreshTarget(targetKey)
    end
end

function Visuals:CommitPass()
    if stagedClaims then
        activeClaims = stagedClaims
        knownTargets = stagedTargets or {}
        stagedClaims = nil
        stagedTargets = nil
    end
    RefreshAll()
end

function Visuals:Clear()
    activeClaims = {}
    knownTargets = {}
    stagedClaims = nil
    stagedTargets = nil
    RefreshAll()
end
