----------------------------------------------------------------------
-- DDingUI Nameplate - NamePlate.lua
-- Frame creation, Blizzard element hiding, plate lifecycle
-- CRITICAL: All Blizzard hooks use hooksecurefunc to avoid taint
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FLAT = ns.FLAT
local FONT = ns.FONT

----------------------------------------------------------------------
-- Blizzard element hiding -- [NAMEPLATE]
-- Strategy: SetAlpha(0) on sub-elements, NOT on UnitFrame itself
-- UnitFrame stays visible for click-targeting to work
-- hooksecurefunc keeps elements hidden after Blizzard refreshes
----------------------------------------------------------------------
local hookedPlates = {} -- [plateFrame] = true

local function HideBlizzardElements(plateFrame)
    local uf = plateFrame.UnitFrame
    if not uf then return end

    -- Health bar
    if uf.healthBar then uf.healthBar:SetAlpha(0) end
    -- Name text
    if uf.name then uf.name:SetAlpha(0) end
    -- Cast bar
    if uf.castBar then uf.castBar:SetAlpha(0) end
    -- Selection highlight
    if uf.selectionHighlight then uf.selectionHighlight:SetAlpha(0) end
    -- Aggro highlight
    if uf.aggroHighlight then uf.aggroHighlight:SetAlpha(0) end
    -- Classification (elite/rare dragon)
    if uf.ClassificationFrame then uf.ClassificationFrame:SetAlpha(0) end
    -- Raid target icon (we draw our own)
    if uf.RaidTargetFrame then uf.RaidTargetFrame:SetAlpha(0) end
    -- Buff frame
    if uf.BuffFrame then uf.BuffFrame:SetAlpha(0) end
    -- Softarget glow
    if uf.SoftTargetFrame then uf.SoftTargetFrame:SetAlpha(0) end

    -- Player nameplate: NamePlateDriverFrame controls UnitFrame alpha directly -- [NAMEPLATE]
    -- Hiding individual children is not enough; hide the entire UnitFrame
    -- (Player doesn't need click-targeting on own nameplate, so this is safe)
    local data = ns.plates[plateFrame]
    if data and data.unitID and UnitIsUnit(data.unitID, "player") then
        uf:SetAlpha(0)
    end
end

local function RestoreBlizzardElements(plateFrame)
    local uf = plateFrame.UnitFrame
    if not uf then return end

    if uf.healthBar then uf.healthBar:SetAlpha(1) end
    if uf.name then uf.name:SetAlpha(1) end
    if uf.castBar then uf.castBar:SetAlpha(1) end
    if uf.selectionHighlight then uf.selectionHighlight:SetAlpha(1) end
    if uf.aggroHighlight then uf.aggroHighlight:SetAlpha(1) end
    if uf.ClassificationFrame then uf.ClassificationFrame:SetAlpha(1) end
    if uf.RaidTargetFrame then uf.RaidTargetFrame:SetAlpha(1) end
    if uf.BuffFrame then uf.BuffFrame:SetAlpha(1) end
    if uf.SoftTargetFrame then uf.SoftTargetFrame:SetAlpha(1) end
end

----------------------------------------------------------------------
-- Safe hooks on Blizzard UnitFrame -- [NAMEPLATE]
-- These prevent Blizzard from re-showing hidden elements
----------------------------------------------------------------------
local function SetupBlizzardHooks(plateFrame)
    if hookedPlates[plateFrame] then return end
    local uf = plateFrame.UnitFrame
    if not uf then return end

    -- Hook Show on UnitFrame to re-hide elements
    hooksecurefunc(uf, "Show", function(self)
        if self:IsForbidden() then return end
        if ns.db and ns.db.general.enabled and ns.plates[plateFrame] then
            HideBlizzardElements(plateFrame)
        end
    end)

    -- Hook healthBar SetAlpha to keep it hidden -- [NAMEPLATE]
    if uf.healthBar then
        local lockedHP = false
        hooksecurefunc(uf.healthBar, "SetAlpha", function(self, alpha)
            if lockedHP or self:IsForbidden() then return end
            if ns.db and ns.db.general.enabled and ns.plates[plateFrame] then
                lockedHP = true
                self:SetAlpha(0)
                lockedHP = false
            end
        end)
    end

    -- Hook name SetAlpha -- [NAMEPLATE]
    if uf.name and uf.name.SetAlpha then
        local lockedName = false
        hooksecurefunc(uf.name, "SetAlpha", function(self, alpha)
            if lockedName then return end
            if ns.db and ns.db.general.enabled and ns.plates[plateFrame] then
                lockedName = true
                self:SetAlpha(0)
                lockedName = false
            end
        end)
    end

    -- Hook UnitFrame SetAlpha for player nameplate -- [NAMEPLATE]
    -- NamePlateDriverFrame controls player nameplate alpha directly;
    -- individual child hooks are not enough
    local lockedUF = false
    hooksecurefunc(uf, "SetAlpha", function(self, alpha)
        if lockedUF or self:IsForbidden() then return end
        local d = ns.plates[plateFrame]
        if not d or not d.unitID or not ns.db or not ns.db.general.enabled then return end
        if UnitIsUnit(d.unitID, "player") then
            lockedUF = true
            self:SetAlpha(0)
            lockedUF = false
        end
    end)

    hookedPlates[plateFrame] = true
end

----------------------------------------------------------------------
-- Create custom plate data structure -- [NAMEPLATE]
----------------------------------------------------------------------
local function CreatePlateData(plateFrame)
    local data = {}
    data.plateFrame = plateFrame

    -- Main frame (child of nameplate, sits on top of Blizzard elements)
    local frame = CreateFrame("Frame", nil, plateFrame)
    frame:SetAllPoints(plateFrame)
    frame:SetFrameLevel((plateFrame:GetFrameLevel() or 0) + 2)
    frame:EnableMouse(false)  -- clicks pass through to Blizzard nameplate -- [NAMEPLATE]
    data.frame = frame

    -- Create modules
    if ns.CreateHealthBar then ns.CreateHealthBar(data) end
    if ns.CreateCastBar   then ns.CreateCastBar(data)   end
    if ns.CreateTexts     then ns.CreateTexts(data)      end
    if ns.CreateTarget    then ns.CreateTarget(data)     end
    if ns.CreateAuraFrame then ns.CreateAuraFrame(data)  end
    if ns.CreateRaidTarget then ns.CreateRaidTarget(data) end

    return data
end

----------------------------------------------------------------------
-- CreateOrUpdatePlate -- [NAMEPLATE]
-- Called on NAME_PLATE_UNIT_ADDED
----------------------------------------------------------------------
function ns.CreateOrUpdatePlate(plateFrame, unitID)
    -- Setup hooks (once per plateFrame)
    SetupBlizzardHooks(plateFrame)

    -- Create or reuse plate data (BEFORE hiding, so unitID is available for player detection)
    local data = ns.plates[plateFrame]
    if not data then
        data = CreatePlateData(plateFrame)
        ns.plates[plateFrame] = data
    end

    data.unitID = unitID

    -- Hide Blizzard elements (uses data.unitID to detect player nameplate) -- [NAMEPLATE]
    HideBlizzardElements(plateFrame)

    -- Ensure frame level is above UnitFrame for player nameplate -- [NAMEPLATE]
    if UnitIsUnit(unitID, "player") and plateFrame.UnitFrame then
        local ufLevel = plateFrame.UnitFrame:GetFrameLevel()
        if data.frame:GetFrameLevel() <= ufLevel then
            data.frame:SetFrameLevel(ufLevel + 5)
        end
    end

    data.frame:Show()

    -- Full update
    ns.UpdatePlate(plateFrame, unitID)
end

----------------------------------------------------------------------
-- UpdatePlate (full refresh) -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdatePlate(plateFrame, unitID)
    local data = ns.plates[plateFrame]
    if not data then return end

    local db = ns.db
    unitID = unitID or data.unitID
    if not unitID or not UnitExists(unitID) then return end

    data.unitID = unitID

    -- Determine plate type (enemy/friendly)
    local reaction = UnitReaction(unitID, "player")
    data.isFriendly = reaction and reaction >= 4
    data.isEnemy    = reaction and reaction <= 3
    data.isNeutral  = reaction and reaction == 4

    -- Determine unit info
    data.isPlayer = UnitIsPlayer(unitID)
    data.isTapped = UnitIsTapDenied(unitID)

    -- Resize based on type
    local sizeDB = data.isFriendly and db.healthBar.friendly or db.healthBar.enemy
    local w = sizeDB.width or 120
    local h = sizeDB.height or 12

    -- Update modules
    if ns.UpdateHealthBar   then ns.UpdateHealthBar(data, unitID) end
    if ns.UpdateHealthColor then ns.UpdateHealthColor(data, unitID) end
    if ns.UpdateCastBar     then ns.UpdateCastBar(data, unitID) end
    if ns.UpdateNameText    then ns.UpdateNameText(data, unitID) end
    if ns.UpdateLevelText   then ns.UpdateLevelText(data, unitID) end
    if ns.UpdateHealthText  then ns.UpdateHealthText(data, unitID) end
    if ns.UpdateThreat      then ns.UpdateThreat(data, unitID) end
    if ns.UpdateTargetHighlight then ns.UpdateTargetHighlight(data) end
    if ns.UpdateAuras       then ns.UpdateAuras(data, unitID) end
    if ns.UpdateRaidTarget  then ns.UpdateRaidTarget(data, unitID) end
end

----------------------------------------------------------------------
-- CleanupPlate -- [NAMEPLATE]
-- Called on NAME_PLATE_UNIT_REMOVED
----------------------------------------------------------------------
function ns.CleanupPlate(plateFrame)
    local data = ns.plates[plateFrame]
    if not data then return end

    data.unitID = nil
    -- [PERF] 폰트 캐시 플래그 리셋 (재사용 시 SetFont 1회 실행)
    data._nameFontSet = nil
    data._levelFontSet = nil
    data._healthFontSet = nil
    data._lastFriendly = nil

    -- Hide custom frame
    if data.frame then data.frame:Hide() end

    -- Stop cast bar OnUpdate
    if data.castBar and data.castBar.frame then
        data.castBar.frame:SetScript("OnUpdate", nil)
        data.castBar.frame:Hide()
    end

    -- Hide auras
    if data.auraFrame then
        if ns.HideAllAuras then ns.HideAllAuras(data) end
    end

    -- Hide target highlight
    if data.targetGlow then data.targetGlow:Hide() end
    if data.targetArrow then data.targetArrow:Hide() end
end

----------------------------------------------------------------------
-- UpdateAllTargetHighlights -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateAllTargetHighlights()
    for plateFrame, data in pairs(ns.plates) do
        if data.unitID and ns.UpdateTargetHighlight then
            ns.UpdateTargetHighlight(data)
        end
    end
end
