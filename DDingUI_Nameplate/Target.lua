----------------------------------------------------------------------
-- DDingUI Nameplate - Target.lua
-- Current target highlight: glow border + scale + arrow indicator
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FLAT = ns.FLAT

----------------------------------------------------------------------
-- Create target indicator elements -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.CreateTarget(data)
    local parent = data.frame

    -- Glow border (highlight when this is current target) -- [NAMEPLATE]
    local glow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    glow:SetBackdrop({
        edgeFile = FLAT,
        edgeSize = 2,
    })
    local activeColor = ns.GetSLColor("border.active")
    glow:SetBackdropBorderColor(ns.UnpackColor(activeColor))
    glow:SetFrameLevel(parent:GetFrameLevel() + 5)
    glow:Hide()

    data.targetGlow = glow

    -- Arrow indicator (small triangle above nameplate) -- [NAMEPLATE]
    local arrow = parent:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(FLAT)
    arrow:SetSize(10, 4)
    arrow:SetVertexColor(ns.UnpackColor(activeColor))
    arrow:Hide()

    data.targetArrow = arrow
end

----------------------------------------------------------------------
-- UpdateTargetHighlight -- [NAMEPLATE]
-- Called on PLAYER_TARGET_CHANGED (for all plates)
----------------------------------------------------------------------
function ns.UpdateTargetHighlight(data)
    if not data or not data.unitID then return end

    local db = ns.db.target
    local isTarget = UnitIsUnit(data.unitID, "target")

    -- Glow border
    if data.targetGlow then
        if isTarget and db.highlight then
            -- Position glow around health bar
            local hb = data.healthBar
            if hb and hb.bar then
                data.targetGlow:ClearAllPoints()
                data.targetGlow:SetPoint("TOPLEFT", hb.bar, "TOPLEFT", -3, 3)
                data.targetGlow:SetPoint("BOTTOMRIGHT", hb.bar, "BOTTOMRIGHT", 3, -3)
            end
            data.targetGlow:Show()
        else
            data.targetGlow:Hide()
        end
    end

    -- Arrow indicator
    if data.targetArrow then
        if isTarget and db.arrowIndicator then
            local hb = data.healthBar
            if hb and hb.bar then
                data.targetArrow:ClearAllPoints()
                data.targetArrow:SetPoint("BOTTOM", hb.bar, "TOP", 0, 14)
            end
            data.targetArrow:Show()
        else
            data.targetArrow:Hide()
        end
    end

    -- Scale -- [NAMEPLATE]
    if data.frame then
        if isTarget and db.scale and db.scale ~= 1 then
            data.frame:SetScale(db.scale)
        else
            data.frame:SetScale(1)
        end
    end
end

----------------------------------------------------------------------
-- Raid target icon -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.CreateRaidTarget(data)
    local parent = data.frame

    local raidIcon = parent:CreateTexture(nil, "OVERLAY")
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidIcon:SetSize(16, 16)
    raidIcon:Hide()

    data.raidIcon = raidIcon
end

-- Raid target icon texcoord lookup
local RAID_ICON_TCOORDS = {
    [1] = { 0,    0.25, 0,    0.25 }, -- Star
    [2] = { 0.25, 0.5,  0,    0.25 }, -- Circle
    [3] = { 0.5,  0.75, 0,    0.25 }, -- Diamond
    [4] = { 0.75, 1,    0,    0.25 }, -- Triangle
    [5] = { 0,    0.25, 0.25, 0.5  }, -- Moon
    [6] = { 0.25, 0.5,  0.25, 0.5  }, -- Square
    [7] = { 0.5,  0.75, 0.25, 0.5  }, -- Cross
    [8] = { 0.75, 1,    0.25, 0.5  }, -- Skull
}

function ns.UpdateRaidTarget(data, unitID)
    if not data.raidIcon then return end

    local index = GetRaidTargetIndex(unitID)
    if index and RAID_ICON_TCOORDS[index] then
        local coords = RAID_ICON_TCOORDS[index]
        data.raidIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])

        -- Position above name
        local hb = data.healthBar
        if hb and hb.bar then
            data.raidIcon:ClearAllPoints()
            data.raidIcon:SetPoint("BOTTOM", hb.bar, "TOP", 0, 16)
        end

        data.raidIcon:Show()
    else
        data.raidIcon:Hide()
    end
end
