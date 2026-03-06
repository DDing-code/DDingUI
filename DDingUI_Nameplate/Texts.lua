----------------------------------------------------------------------
-- DDingUI Nameplate - Texts.lua
-- Name, level, health text creation and formatting
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FONT = ns.FONT
local floor = math.floor

----------------------------------------------------------------------
-- Create all text elements -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.CreateTexts(data)
    local parent = data.frame
    local textColor = ns.GetSLColor("text.normal")
    local r, g, b = ns.UnpackColor(textColor)

    -- Name text -- [NAMEPLATE]
    local nameText = parent:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(FONT, ns.db.text.name.fontSize or 10, ns.db.text.name.outline or "OUTLINE")
    nameText:SetTextColor(r, g, b)
    nameText:SetJustifyH("CENTER")

    -- Level text -- [NAMEPLATE]
    local levelText = parent:CreateFontString(nil, "OVERLAY")
    levelText:SetFont(FONT, ns.db.text.level.fontSize or 9, ns.db.text.level.outline or "OUTLINE")
    levelText:SetTextColor(r, g, b)
    levelText:SetJustifyH("LEFT")

    -- Health text -- [NAMEPLATE]
    local healthText = parent:CreateFontString(nil, "OVERLAY")
    healthText:SetFont(FONT, ns.db.text.health.fontSize or 9, ns.db.text.health.outline or "OUTLINE")
    healthText:SetTextColor(r, g, b)
    healthText:SetJustifyH("CENTER")

    data.nameText   = nameText
    data.levelText  = levelText
    data.healthText = healthText

    -- Layout
    ns.LayoutTexts(data)
end

----------------------------------------------------------------------
-- Layout text positions -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.LayoutTexts(data)
    local hb = data.healthBar
    if not hb or not hb.bar then return end

    -- Name: above health bar
    if data.nameText then
        data.nameText:ClearAllPoints()
        data.nameText:SetPoint("BOTTOM", hb.bar, "TOP", 0, 2)
    end

    -- Level: left of name
    if data.levelText then
        data.levelText:ClearAllPoints()
        data.levelText:SetPoint("BOTTOMRIGHT", hb.bar, "TOPLEFT", -2, 2)
    end

    -- Health: inside health bar
    if data.healthText then
        data.healthText:ClearAllPoints()
        data.healthText:SetPoint("CENTER", hb.bar, "CENTER", 0, 0)
    end
end

----------------------------------------------------------------------
-- Abbreviate long names -- [NAMEPLATE]
----------------------------------------------------------------------
local function AbbreviateName(name, maxLen)
    if not name then return "" end
    maxLen = maxLen or 20
    if #name <= maxLen then return name end

    -- Try to cut at word boundary
    local abbrev = name:sub(1, maxLen - 1) .. "..."
    return abbrev
end

----------------------------------------------------------------------
-- Update name text -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateNameText(data, unitID)
    if not data.nameText then return end
    local db = ns.db.text.name

    if not db.enabled then
        data.nameText:Hide()
        return
    end

    local name = UnitName(unitID)
    if not name then
        data.nameText:SetText("")
        return
    end

    name = AbbreviateName(name, db.maxLength)

    -- Class color for players
    if data.isPlayer then
        local _, class = UnitClass(unitID)
        if class then
            local cc = RAID_CLASS_COLORS[class]
            if cc then
                data.nameText:SetTextColor(cc.r, cc.g, cc.b)
            end
        end
    else
        local textColor = ns.GetSLColor("text.normal")
        data.nameText:SetTextColor(ns.UnpackColor(textColor))
    end

    data.nameText:SetText(name)
    -- [PERF] SetFont는 CreateOrUpdatePlate에서 1회만 (매 UNIT_HEALTH마다 호출 방지)
    if not data._nameFontSet then
        data.nameText:SetFont(FONT, db.fontSize or 10, db.outline or "OUTLINE")
        data._nameFontSet = true
    end
    data.nameText:Show()
end

----------------------------------------------------------------------
-- Update level text -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateLevelText(data, unitID)
    if not data.levelText then return end
    local db = ns.db.text.level

    if not db.enabled then
        data.levelText:Hide()
        return
    end

    local level = UnitLevel(unitID)
    if not level or level <= 0 then
        -- Boss or unknown level
        data.levelText:SetText("??")
        data.levelText:SetTextColor(1, 0, 0)
        data.levelText:Show()
        return
    end

    -- Classification suffix (elite/rare)
    local classification = UnitClassification(unitID)
    local suffix = ""
    if classification == "elite" or classification == "worldboss" then
        suffix = "+"
    elseif classification == "rareelite" then
        suffix = "+"
    elseif classification == "rare" then
        suffix = "r"
    end

    data.levelText:SetText(level .. suffix)

    -- Color by difficulty -- [NAMEPLATE]
    if db.colorByDifficulty then
        local color = GetCreatureDifficultyColor(level)
        if color then
            data.levelText:SetTextColor(color.r, color.g, color.b)
        end
    else
        local textColor = ns.GetSLColor("text.normal")
        data.levelText:SetTextColor(ns.UnpackColor(textColor))
    end

    -- [PERF] SetFont는 CreateOrUpdatePlate에서 1회만
    if not data._levelFontSet then
        data.levelText:SetFont(FONT, db.fontSize or 9, db.outline or "OUTLINE")
        data._levelFontSet = true
    end
    data.levelText:Show()
end

----------------------------------------------------------------------
-- Health format helpers -- [NAMEPLATE]
----------------------------------------------------------------------
local function ShortNumber(value)
    if value >= 1e9 then
        return string.format("%.1fB", value / 1e9)
    elseif value >= 1e6 then
        return string.format("%.1fM", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.1fK", value / 1e3)
    else
        return tostring(floor(value))
    end
end

local function FormatHealth(health, healthMax, fmt)
    if healthMax == 0 then healthMax = 1 end
    local pct = floor(health / healthMax * 100 + 0.5)

    if fmt == "CURRENT" then
        return ShortNumber(health)
    elseif fmt == "PERCENT" then
        return pct .. "%"
    elseif fmt == "CURRENT_PERCENT" then
        return ShortNumber(health) .. "  " .. pct .. "%"
    elseif fmt == "CURRENT_MAX" then
        return ShortNumber(health) .. " / " .. ShortNumber(healthMax)
    elseif fmt == "DEFICIT" then
        local deficit = healthMax - health
        if deficit > 0 then
            return "-" .. ShortNumber(deficit)
        else
            return ""
        end
    else -- "NONE"
        return ""
    end
end

----------------------------------------------------------------------
-- Update health text -- [NAMEPLATE]
----------------------------------------------------------------------
function ns.UpdateHealthText(data, unitID)
    if not data.healthText then return end
    local db = ns.db.text.health

    if not db.enabled then
        data.healthText:Hide()
        return
    end

    local health    = UnitHealth(unitID)
    local healthMax = UnitHealthMax(unitID)

    local text = FormatHealth(health, healthMax, db.format)
    data.healthText:SetText(text)
    -- [PERF] SetFont는 CreateOrUpdatePlate에서 1회만
    if not data._healthFontSet then
        data.healthText:SetFont(FONT, db.fontSize or 9, db.outline or "OUTLINE")
        data._healthFontSet = true
    end

    local textColor = ns.GetSLColor("text.highlight")
    data.healthText:SetTextColor(ns.UnpackColor(textColor))
    data.healthText:Show()
end
