local ns = select(2, ...)
local DDingUI = ns.Addon

local LayoutPolicy = {}
DDingUI.CustomIconLayoutPolicy = LayoutPolicy

local function ResolveAnchorPoints(anchorPoint)
    if anchorPoint == "TOPLEFT" then
        return "BOTTOMLEFT", "TOPLEFT"
    elseif anchorPoint == "TOPRIGHT" then
        return "BOTTOMRIGHT", "TOPRIGHT"
    elseif anchorPoint == "BOTTOMLEFT" then
        return "TOPLEFT", "BOTTOMLEFT"
    elseif anchorPoint == "BOTTOMRIGHT" then
        return "TOPRIGHT", "BOTTOMRIGHT"
    elseif anchorPoint == "TOP" then
        return "BOTTOM", "TOP"
    elseif anchorPoint == "BOTTOM" then
        return "TOP", "BOTTOM"
    elseif anchorPoint == "LEFT" then
        return "RIGHT", "LEFT"
    elseif anchorPoint == "RIGHT" then
        return "LEFT", "RIGHT"
    end
    return "CENTER", "CENTER"
end

local function GetStartAnchorForGrowth(growth)
    if growth == "LEFT" then
        return "TOPRIGHT"
    elseif growth == "UP" then
        return "BOTTOMLEFT"
    end
    return "TOPLEFT"
end

local function GetDefaultRowGrowth(growth)
    if growth == "LEFT" or growth == "RIGHT" then
        return "DOWN"
    end
    return "RIGHT"
end

local function NormalizeRowGrowth(growth, rowGrowth)
    if growth == "LEFT" or growth == "RIGHT" then
        if rowGrowth ~= "UP" and rowGrowth ~= "DOWN" then
            return "DOWN"
        end
        return rowGrowth
    end
    if rowGrowth ~= "LEFT" and rowGrowth ~= "RIGHT" then
        return "RIGHT"
    end
    return rowGrowth
end

local function GetStartAnchorForGrowthPair(growth, rowGrowth)
    local g = growth or "RIGHT"
    local rg = NormalizeRowGrowth(g, rowGrowth or GetDefaultRowGrowth(g))

    local top = (g == "LEFT" or g == "RIGHT" or rg == "DOWN")
    local left = (g == "RIGHT" or rg == "RIGHT")

    if top and left then return "TOPLEFT" end
    if top and not left then return "TOPRIGHT" end
    if not top and left then return "BOTTOMLEFT" end
    return "BOTTOMRIGHT"
end

local function BuildDefaultSettings(growth)
    local g = growth or "RIGHT"
    local rg = NormalizeRowGrowth(g, GetDefaultRowGrowth(g))
    local startAnchor = GetStartAnchorForGrowthPair(g, rg)
    return {
        growthDirection = g,
        rowGrowthDirection = rg,
        anchorFrom = startAnchor,
        anchorTo = startAnchor,
        spacing = 5,
        iconSize = 40,
        maxIconsPerRow = 10,
        position = {x = 0, y = -200},
    }
end

local function BuildDefaultUngroupedPositionSettings()
    local settings = BuildDefaultSettings("RIGHT")
    settings.anchorFrom = "CENTER"
    settings.anchorTo = "CENTER"
    settings.position = { x = 0, y = 0 }
    return settings
end

local function NormalizeAnchor(settings)
    if not settings then return end
    if settings.anchorPoint and not settings.anchorFrom and not settings.anchorTo then
        settings.anchorFrom = settings.anchorPoint
        settings.anchorTo = settings.anchorPoint
        settings.anchorPoint = nil
    end
    if settings.anchorPoint then
        settings.anchorPoint = nil
    end
    settings.rowGrowthDirection = settings.rowGrowthDirection or GetDefaultRowGrowth(settings.growthDirection or "RIGHT")
    settings.rowGrowthDirection = NormalizeRowGrowth(settings.growthDirection or "RIGHT", settings.rowGrowthDirection)
    if settings.maxIconsPerRow == nil and settings.maxColumns ~= nil then
        settings.maxIconsPerRow = settings.maxColumns
        settings.maxColumns = nil
    end
    settings.anchorFrom = settings.anchorFrom or GetStartAnchorForGrowthPair(settings.growthDirection or "RIGHT", settings.rowGrowthDirection)
    settings.anchorTo = settings.anchorTo or settings.anchorFrom
end

LayoutPolicy.ResolveAnchorPoints = ResolveAnchorPoints
LayoutPolicy.GetStartAnchorForGrowth = GetStartAnchorForGrowth
LayoutPolicy.GetDefaultRowGrowth = GetDefaultRowGrowth
LayoutPolicy.NormalizeRowGrowth = NormalizeRowGrowth
LayoutPolicy.GetStartAnchorForGrowthPair = GetStartAnchorForGrowthPair
LayoutPolicy.BuildDefaultSettings = BuildDefaultSettings
LayoutPolicy.BuildDefaultUngroupedPositionSettings = BuildDefaultUngroupedPositionSettings
LayoutPolicy.NormalizeAnchor = NormalizeAnchor
