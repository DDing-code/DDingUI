----------------------------------------------------------------------
-- DDingUI Nameplate - Threat.lua
-- Threat color system with tank/dps/healer role auto-detection
-- Based on UnitDetailedThreatSituation() API
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

----------------------------------------------------------------------
-- GetThreatColor -- [NAMEPLATE]
-- Returns r, g, b or nil if threat module disabled
--
-- threatStatus from UnitDetailedThreatSituation:
--   3 = securely tanking
--   2 = insecurely tanking (losing aggro)
--   1 = not tanking but high threat
--   0 = not tanking, low threat
--   nil = no threat data
----------------------------------------------------------------------
function ns.GetThreatColor(unitID)
    local db = ns.db.threat
    if not db.enabled then return nil end

    local isTanking, threatStatus, threatPct, rawThreatPct, threatValue =
        UnitDetailedThreatSituation("player", unitID)

    if threatStatus == nil then return nil end

    if ns.playerIsTank then
        -- TANK MODE -- [NAMEPLATE]
        if isTanking then
            if threatStatus == 3 then
                -- Securely tanking → green (safe)
                return db.tankAggro[1], db.tankAggro[2], db.tankAggro[3]
            elseif threatStatus == 2 then
                -- Insecurely tanking → orange (losing)
                return db.tankPulling[1], db.tankPulling[2], db.tankPulling[3]
            else
                return db.tankAggro[1], db.tankAggro[2], db.tankAggro[3]
            end
        else
            -- Not tanking this mob
            -- Check if another tank has it
            if IsInGroup() and next(ns.tankCache) then
                local targetUnit = unitID .. "target"
                if UnitExists(targetUnit) then
                    local targetName = UnitName(targetUnit)
                    if targetName and ns.tankCache[targetName] then
                        -- Another tank has it → gray
                        return db.tankOther[1], db.tankOther[2], db.tankOther[3]
                    end
                end
            end
            -- Nobody tanking / lost aggro → red
            return db.tankNoAggro[1], db.tankNoAggro[2], db.tankNoAggro[3]
        end
    else
        -- DPS / HEALER MODE -- [NAMEPLATE]
        if isTanking then
            -- I have aggro (bad!) → red
            return db.dpsAggro[1], db.dpsAggro[2], db.dpsAggro[3]
        elseif threatStatus == 1 then
            -- High threat, close to pulling → orange
            return db.dpsPulling[1], db.dpsPulling[2], db.dpsPulling[3]
        else
            -- Safe → green
            return db.dpsNoAggro[1], db.dpsNoAggro[2], db.dpsNoAggro[3]
        end
    end
end

----------------------------------------------------------------------
-- UpdateThreat -- [NAMEPLATE]
-- Called on UNIT_THREAT_LIST_UPDATE / UNIT_THREAT_SITUATION_UPDATE
----------------------------------------------------------------------
function ns.UpdateThreat(data, unitID)
    if not ns.db.threat.enabled then return end
    if not ns.db.healthBar.colorByThreat then return end

    -- Only apply threat colors to enemy/neutral units
    if data.isFriendly then return end

    -- Re-evaluate health bar color (threat has highest priority)
    if ns.UpdateHealthColor then
        ns.UpdateHealthColor(data, unitID)
    end
end
