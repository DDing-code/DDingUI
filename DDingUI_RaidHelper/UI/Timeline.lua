local _, ns = ...

local TimelineUI = {}
ns.TimelineUI = TimelineUI

local abs = math.abs
local ceil = math.ceil
local floor = math.floor
local max = math.max
local min = math.min
local sin = math.sin
local sort = table.sort
local unpack = unpack

-- [STYLE] C안 릿지 바 (2026-10-10): one borderless bar + a cooldown rail, both edges fade out.
-- timelineHeight is now bar + rail. Values >= LEGACY_HEIGHT_FLOOR come from the old
-- four-row window (170~420) and fall back to the new default instead of clamping.
local FRAME_WIDTH = 680
local FRAME_HEIGHT = 98
local MIN_FRAME_WIDTH = 200
local MAX_FRAME_WIDTH = 1200
local MIN_FRAME_HEIGHT = 80
local MAX_FRAME_HEIGHT = 160
local LEGACY_HEIGHT_FLOOR = 170
local RAIL_HEIGHT = 28
local FADE_SHARE = 0.12
local FADE_MASK = "Interface\\AddOns\\DDingUI_RaidHelper\\Media\\RaidHelper_FadeMask.tga"
local RIDGE_TOP_SPACE = 36
local COMPACT_WIDTH = 400
local MECHANIC_SIZE = 28
local MECHANIC_NEAR_SIZE = 32
local MECHANIC_NEAR_WINDOW = 5
local COOLDOWN_SIZE = 18
local COOLDOWN_NEAR_WINDOW = 4
local UPDATE_INTERVAL = 0.05
-- [STYLE] "곧 사용" countdown: the number pops and a voice counts 셋 · 둘 · 하나.
local COUNTDOWN_FROM = 3
local COUNTDOWN_POP_TIME = 0.28
local ALERT_ENTER_TIME = 0.25
local ALERT_SLIDE_TIME = 0.2
local ALERT_FLASH_TIME = 0.4
local ALERT_EXIT_START = -0.45
local ALERT_EXIT_END = -0.75
local COUNTDOWN_VOICE_SLACK = 0.6
local COUNTDOWN_SOUNDS = {
    ja = "Countdown_%d.ogg",
    ko = "Countdown_KO_%d.ogg",
    en = "Countdown_EN_%d.ogg",
    alarm = "Countdown_Alarm_%d.ogg",
}
TimelineUI.COUNTDOWN_SOUNDS = COUNTDOWN_SOUNDS
local UPCOMING_PANEL_MAX_WIDTH = 320
local ALERT_STYLE_SPEC = {
    iconSize = { default = 26, min = 16, max = 48 },
    nameSize = { default = 14, min = 10, max = 24 },
    countSize = { default = 20, min = 12, max = 36 },
    spacing = { default = 2, min = 0, max = 16 },
    maxRows = { default = 3, min = 1, max = 6 },
    width = { default = UPCOMING_PANEL_MAX_WIDTH, min = 160, max = 600 },
    window = { default = 12, min = 5, max = 30 },
    align = { default = "LEFT", choices = { LEFT = true, CENTER = true, RIGHT = true } },
    grow = { default = "DOWN", choices = { DOWN = true, UP = true } },
    showIcon = { default = true },
    showName = { default = true },
    pop = { default = true },
}
TimelineUI.ALERT_STYLE_SPEC = ALERT_STYLE_SPEC
-- [STYLE] Timeline detail options (2026-10-11 사용자 요청): icon sizes, shown time range,
-- past-icon opacity (%) and one switch per bar element. Saved in ns.db.timelineStyle; `root`
-- entries are the older top-level keys. Defaults reproduce the fixed C안 bar.
local TIMELINE_STYLE_SPEC = {
    mechanicSize = { default = MECHANIC_SIZE, min = 16, max = 40 },
    cooldownSize = { default = COOLDOWN_SIZE, min = 12, max = 32 },
    pastAlpha = { default = 38, min = 0, max = 100 },
    windowPast = { default = 12, min = 2, max = 30, root = true },
    windowFuture = { default = 38, min = 10, max = 90, root = true },
    showMechanics = { default = true },
    showCooldowns = { default = true },
    showCountdown = { default = true },
    showMechanicDetail = { default = true },
    showCooldownDetail = { default = true },
    showSpread = { default = true },
    highlightNear = { default = true },
    showDamage = { default = true },
    showPhases = { default = true },
    showGrid = { default = true },
    showTimeReadout = { default = true },
}
TimelineUI.TIMELINE_STYLE_SPEC = TIMELINE_STYLE_SPEC
local FALLBACK_ICON = 134400
local BRAND_ICON = "Interface\\AddOns\\DDingUI_RaidHelper\\Media\\RaidHelper_Icon.tga"
local ADDON_KEY = "RaidHelper"
local EDIT_FRAME_NAME = "공격대 타임라인"
local ALERT_FRAME_NAME = "리마인더" -- [STYLE] 2026-10-10 사용자 요청: "곧 사용 알림" → "리마인더"
local ALERT_ATTACH_GAP = 6 -- legacy layout: alert right under the timeline
local EDIT_HISTORY_LIMIT = 50

local function IsSecret(value)
    return ns.IsSecret and ns:IsSecret(value) or false
end

local function SetTextureColor(texture, color, alpha)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function SetTextColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function ApplyBackdrop(frame, texture, background, border)
    frame:SetBackdrop({
        bgFile = texture,
        edgeFile = texture,
        edgeSize = 1,
    })
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function ClampNumber(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return min(maximum, max(minimum, value))
end

local function FormatTime(seconds)
    seconds = max(0, floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

local function FormatDamage(value)
    value = tonumber(value) or 0
    if value >= 1000000000 then
        return string.format("%.2fB", value / 1000000000)
    elseif value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.0fK", value / 1000)
    end
    return tostring(floor(value + 0.5))
end

local function FormatCountdown(remaining)
    if remaining < 10 then
        return string.format("%.1f", max(0, remaining))
    end
    return tostring(ceil(remaining))
end

local function ColorCode(color)
    return string.format("|cff%02x%02x%02x",
        floor(color[1] * 255 + 0.5), floor(color[2] * 255 + 0.5), floor(color[3] * 255 + 0.5))
end

--- Opacity of something centred at x on a bar of the given width: 0 at both ends,
--- 1 once it is FADE_SHARE of the width inside. Matches RaidHelper_FadeMask.tga.
local function EdgeAlpha(x, width)
    local fade = max(1, width * FADE_SHARE)
    local edge = min(x, width - x) / fade
    if edge <= 0 then return 0 end
    if edge >= 1 then return 1 end
    return edge * edge * (3 - 2 * edge)
end
TimelineUI.EdgeAlpha = EdgeAlpha

local function ResolveIcon(data)
    local icon = data and data.icon
    if not IsSecret(icon) and icon then
        -- [REFACTOR] Existing WCL packs wrap FileDataIDs in web-image paths.
        if type(icon) == "string" then
            icon = icon:gsub("%.jpg$", "")
            icon = tonumber(icon:match("^Interface\\Icons\\(%d+)$")) or tonumber(icon) or icon
        end
        return icon
    end

    local spellID = data and data.spellID
    if IsSecret(spellID) then spellID = nil end
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(spellID)
        if not IsSecret(icon) and icon then return icon end
    end
    if spellID and GetSpellTexture then
        icon = GetSpellTexture(spellID)
        if not IsSecret(icon) and icon then return icon end
    end
    return FALLBACK_ICON
end

local function ResolveLabel(data)
    local spellID = data and data.spellID
    if IsSecret(spellID) then spellID = nil end
    if spellID and C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if not IsSecret(name) and name then return name end
    end
    local label = data and data.label
    if not IsSecret(label) and label then return label end
    return "Timeline event"
end

function TimelineUI:GetCategoryFontSize(category)
    if category == "title" then return self.titleFontSize end
    if category == "small" then return self.smallFontSize end
    if category == "count" then return self:GetAlertStyle().countSize end
    if category == "alertName" then return self:GetAlertStyle().nameSize end
    return self.normalFontSize
end

function TimelineUI:CreateLabel(parent, category, color, layer)
    local size = self:GetCategoryFontSize(category)
    local label = parent:CreateFontString(nil, layer or "OVERLAY")
    label:SetFont(self.fontPath, size, "OUTLINE")
    label:SetWordWrap(false)
    if label.SetMaxLines then label:SetMaxLines(1) end
    label._raidHelperFontCategory = category
    SetTextColor(label, color)
    self.fontStrings[#self.fontStrings + 1] = label
    return label
end

-- [STYLE] C안: every texture drawn inside the bar shares one stretched fade mask, so the
-- fade follows the bar width. Returns false when the client cannot mask the region.
function TimelineUI:MaskRegion(region)
    local mask = self.fadeMask
    if not (mask and region and region.AddMaskTexture) then return false end
    return pcall(region.AddMaskTexture, region, mask) == true
end

function TimelineUI:StyleChip(chip)
    local styleLib = self.styleLib
    local background, border = chip.backgroundColor, chip.borderColor
    if styleLib and styleLib.MakeRounded then
        styleLib.MakeRounded(chip, chip.radius, background, border)
    else
        ApplyBackdrop(chip, self.flatTexture, background, border)
    end
end

--- Small rounded label box used for the nearest-event details and phase labels.
function TimelineUI:CreateChip(parent, borderColor, borderAlpha, radius, backgroundColor)
    local chip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    chip.radius = radius or 4
    chip.backgroundColor = backgroundColor
    chip.borderColor = { borderColor[1], borderColor[2], borderColor[3], borderAlpha or 1 }
    self:StyleChip(chip)
    chip:SetFrameLevel(parent:GetFrameLevel() + 6)
    chip:Hide()
    self.chips[#self.chips + 1] = chip
    return chip
end

function TimelineUI:CreateMarker(parent, kind)
    local colors = self.colors
    local marker = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local size = kind == "cooldown" and self:GetTimelineStyle().cooldownSize
        or self.mechanicSize or MECHANIC_SIZE
    marker:SetSize(size, size)
    marker.kind = kind
    marker.borderColor = kind == "cooldown" and colors.status.success or colors.status.warning
    ApplyBackdrop(marker, self.flatTexture, colors.bg.widget, marker.borderColor)

    if kind == "cooldown" then
        -- Pin from the bar's bottom edge down to the icon, plus the ± timing band behind it.
        marker.pin = marker:CreateTexture(nil, "BACKGROUND")
        marker.pin:SetSize(1, 8)
        marker.pin:SetPoint("BOTTOM", marker, "TOP", 0, 0)
        SetTextureColor(marker.pin, colors.status.success, 0.9)

        marker.spread = marker:CreateTexture(nil, "BACKGROUND")
        marker.spread:SetHeight(2)
        SetTextureColor(marker.spread, colors.status.success, 0.25)
        marker.spread:Hide()
    else
        -- Soft accent halo for the nearest upcoming mechanic: three rounded layers, fainter
        -- outward, so the overlap falls off like a shadow (≈0.38 / 0.23 / 0.10 alpha bands).
        marker.glowLayers = {}
        for layerIndex, spec in ipairs({ { 6, 0.10, 8 }, { 4, 0.14, 6 }, { 2, 0.20, 4 } }) do
            local inset, alpha, radius = spec[1], spec[2], spec[3]
            local layer = marker:CreateTexture(nil, "BACKGROUND", nil, -8 + layerIndex)
            layer:SetPoint("TOPLEFT", marker, "TOPLEFT", -inset, inset)
            layer:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", inset, -inset)
            if self.styleLib.RoundTexture then
                self.styleLib.RoundTexture(layer, radius)
                layer:SetVertexColor(self.accentFrom[1], self.accentFrom[2], self.accentFrom[3], alpha)
            else
                SetTextureColor(layer, self.accentFrom, alpha)
            end
            layer:Hide()
            marker.glowLayers[layerIndex] = layer
        end
        marker.glow = marker.glowLayers[1]

        marker.countdown = self:CreateLabel(marker, "small", colors.text.highlight)
        marker.countdown:SetPoint("TOP", marker, "BOTTOM", 0, -1)
        marker.countdown:SetJustifyH("CENTER")
    end

    marker.icon = marker:CreateTexture(nil, "ARTWORK")
    marker.icon:SetPoint("TOPLEFT", 1, -1)
    marker.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    marker.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    marker:SetScript("OnEnter", function(button)
        local showTooltips = ns.Options and ns.Options:ShouldShowTooltips()
            or (ns.db and ns.db.showTooltips == true)
        if showTooltips then
            TimelineUI:ShowMarkerTooltip(button)
        end
    end)
    marker:SetScript("OnLeave", function(button)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(button)) then
            GameTooltip:Hide()
        end
    end)
    return marker
end

function TimelineUI:GetMarker(pool, index, parent, kind)
    if not pool[index] then
        pool[index] = self:CreateMarker(parent, kind)
    end
    return pool[index]
end

function TimelineUI:GetDamageLine(index)
    local line = self.damageLines[index]
    if line or not self.plot.CreateLine then return line end

    line = self.plot:CreateLine(nil, "ARTWORK", nil, 2)
    line:SetThickness(1.5)
    local light = self.accentLight
    line:SetColorTexture(light[1], light[2], light[3], 0.9)
    -- Lines are masked like every other bar texture; if this client refuses, the ridge
    -- falls back to per-segment edge alpha in UpdateDamage.
    if not self:MaskRegion(line) then self.lineMaskFailed = true end
    self.damageLines[index] = line
    return line
end

--- Vertical gradient column under the ridge for one 0.5 s damage cell.
function TimelineUI:GetDamageColumn(index)
    local column = self.damageColumns[index]
    if column then return column end

    column = self.plot:CreateTexture(nil, "ARTWORK", nil, 1)
    column:SetColorTexture(1, 1, 1, 1)
    column.topColor = CreateColor(1, 1, 1, 1)
    self:MaskRegion(column)
    self.damageColumns[index] = column
    return column
end

function TimelineUI:GetGrid(index)
    local grid = self.gridLines[index]
    if grid then return grid end

    grid = { line = self.plot:CreateTexture(nil, "BORDER", nil, 1) }
    grid.line:SetWidth(1)
    self:MaskRegion(grid.line)
    self.gridLines[index] = grid
    return grid
end

function TimelineUI:GetPhaseMarker(index)
    local marker = self.phaseMarkers[index]
    if marker then return marker end

    local colors = self.colors
    marker = {
        ribbon = self.plot:CreateTexture(nil, "ARTWORK", nil, 4),
        line = self.plot:CreateTexture(nil, "ARTWORK", nil, 3),
        chip = self:CreateChip(self.mechanicLayer, colors.status.warning, 0.45, 3,
            { colors.bg.input[1], colors.bg.input[2], colors.bg.input[3], 0.9 }),
    }
    marker.ribbon:SetHeight(2)
    marker.line:SetWidth(1)
    SetTextureColor(marker.line, colors.status.warning, 0.45)
    self:MaskRegion(marker.ribbon)
    self:MaskRegion(marker.line)
    marker.label = self:CreateLabel(marker.chip, "small", colors.status.warning)
    marker.label:SetPoint("CENTER", marker.chip, "CENTER", 0, 0)
    marker.chip:SetHeight(16)
    self.phaseMarkers[index] = marker
    return marker
end

-- [STYLE] "곧 사용" alert (2026-10-10): NSRT memo style. Each line is icon + spell name +
-- a large countdown, on a soft shade that fades out to the right instead of a boxed bar.
-- [STYLE] "곧 사용" alert layout options (2026-10-10 사용자 요청): icon/text sizes, alignment,
-- growth direction, spacing, rows, width, lead time, element toggles. Saved in ns.db.alertStyle;
-- anything missing or invalid falls back to ALERT_STYLE_SPEC defaults.
local function ResolveStyleValue(spec, value)
    if spec.choices then
        return spec.choices[value] and value or spec.default
    elseif spec.min then
        value = tonumber(value)
        return value and floor(min(spec.max, max(spec.min, value)) + 0.5) or spec.default
    elseif value == nil then
        return spec.default
    end
    return value == true
end

local function ResolveAlertStyle(saved)
    saved = type(saved) == "table" and saved or {}
    local style = {}
    for key, spec in pairs(ALERT_STYLE_SPEC) do
        style[key] = ResolveStyleValue(spec, saved[key])
    end
    return style
end
TimelineUI.ResolveAlertStyle = ResolveAlertStyle

--- Timeline detail options from the saved variables table (see TIMELINE_STYLE_SPEC).
local function ResolveTimelineStyle(db)
    db = type(db) == "table" and db or {}
    local saved = type(db.timelineStyle) == "table" and db.timelineStyle or {}
    local style = {}
    for key, spec in pairs(TIMELINE_STYLE_SPEC) do
        local value = saved[key]
        if spec.root then value = db[key] end
        style[key] = ResolveStyleValue(spec, value)
    end
    return style
end
TimelineUI.ResolveTimelineStyle = ResolveTimelineStyle

function TimelineUI:GetTimelineStyle()
    if not self.timelineStyleCache then
        self.timelineStyleCache = ResolveTimelineStyle(ns.db)
    end
    return self.timelineStyleCache
end

function TimelineUI:GetAlertStyle()
    if not self.alertStyleCache then
        self.alertStyleCache = ResolveAlertStyle(ns.db and ns.db.alertStyle)
    end
    return self.alertStyleCache
end

local function AlertRowHeight(style)
    local icon = style.showIcon and style.iconSize or 0
    local name = style.showName and ceil(style.nameSize * 1.25) or 0
    return max(icon, name, ceil(style.countSize * 1.25)) + 4
end
TimelineUI.AlertRowHeight = AlertRowHeight

-- Fixed room for the number so a centred line does not wobble as it ticks (fits "지금" at 1.4x).
local function AlertCountSlot(style)
    return ceil(style.countSize * 3)
end

function TimelineUI:GetAlertPanelHeight(style, rows)
    style = style or self:GetAlertStyle()
    rows = rows or style.maxRows
    return rows * AlertRowHeight(style) + max(0, rows - 1) * style.spacing
end

-- Shade opacity at the left end, middle, middle, right end (two half-width gradients).
local SHADE_STOPS = {
    LEFT = { 1, 0.5, 0.5, 0 },
    RIGHT = { 0, 0.5, 0.5, 1 },
    CENTER = { 0, 1, 1, 0 },
}

local function SetRowGradient(row, layer, color, alpha)
    local stops = SHADE_STOPS[row.align or "LEFT"] or SHADE_STOPS.LEFT
    local colors = row[layer .. "Colors"]
    for index, current in ipairs(colors) do
        local value = (color[4] or 1) * alpha * stops[index]
        if current.SetRGBA then
            current:SetRGBA(color[1], color[2], color[3], value)
        else
            colors[index] = CreateColor(color[1], color[2], color[3], value)
        end
    end
    row[layer]:SetGradient("HORIZONTAL", colors[1], colors[2])
    row[layer .. "2"]:SetGradient("HORIZONTAL", colors[3], colors[4])
end

function TimelineUI:SetUpcomingRowShade(row, alpha)
    SetRowGradient(row, "shade", self.colors.bg.input, alpha)
    SetRowGradient(row, "tint", self.accentFrom, 0.22 * alpha)
    SetRowGradient(row, "flash", self.accentLight, 0.55 * alpha)
end

function TimelineUI:PositionUpcomingRow(row, x, y)
    local edge = row.grow == "UP" and "BOTTOM" or "TOP"
    row:ClearAllPoints()
    row:SetPoint(edge .. "LEFT", row.panel, edge .. "LEFT", x, y)
    row:SetPoint(edge .. "RIGHT", row.panel, edge .. "RIGHT", x, y)
end

--- One alert line. panel/pool default to the live alert; the settings sample passes its own.
function TimelineUI:CreateUpcomingRow(index, panel, pool)
    panel = panel or self.upcomingPanel
    pool = pool or self.upcomingRows
    local row = pool[index]
    if row then return row end

    local colors = self.colors
    row = CreateFrame("Frame", nil, panel)
    row.panel = panel
    row.index = index

    row.motionStatic = panel ~= self.upcomingPanel
    for level, layer in ipairs({ "shade", "tint", "flash" }) do
        row[layer] = row:CreateTexture(nil, "BACKGROUND", nil, level)
        row[layer]:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row[layer]:SetPoint("BOTTOMRIGHT", row, "BOTTOM", 0, 0)
        row[layer]:SetColorTexture(1, 1, 1, 1)
        row[layer .. "2"] = row:CreateTexture(nil, "BACKGROUND", nil, level)
        row[layer .. "2"]:SetPoint("TOPLEFT", row, "TOP", 0, 0)
        row[layer .. "2"]:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row[layer .. "2"]:SetColorTexture(1, 1, 1, 1)
        row[layer .. "Colors"] = {}
        for index2 = 1, 4 do
            row[layer .. "Colors"][index2] = CreateColor(1, 1, 1, 0)
        end
    end
    row.drain = row:CreateTexture(nil, "ARTWORK")
    row.drain:SetHeight(2)
    SetTextureColor(row.drain, self.accentFrom)

    -- Icon, name and number live in one holder so the whole line can be aligned as a group.
    row.content = CreateFrame("Frame", nil, row)
    row.icon = row.content:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.glowLayers = {}
    for index2, spec in ipairs({ { 6, 0.10, 8 }, { 4, 0.14, 6 }, { 2, 0.20, 4 } }) do
        local layer = row.content:CreateTexture(nil, "BACKGROUND", nil, -8 + index2)
        layer:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -spec[1], spec[1])
        layer:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", spec[1], -spec[1])
        if self.styleLib.RoundTexture then
            self.styleLib.RoundTexture(layer, spec[3])
            layer:SetVertexColor(self.accentFrom[1], self.accentFrom[2], self.accentFrom[3], spec[2])
        else
            SetTextureColor(layer, self.accentFrom, spec[2])
        end
        row.glowLayers[index2] = layer
    end
    row.label = self:CreateLabel(row.content, "alertName", colors.text.highlight)
    row.countdown = self:CreateLabel(row.content, "count", self.accentLight)

    pool[index] = row
    self:LayoutUpcomingRow(row, index, self:GetAlertStyle())
    row:Hide()
    return row
end

--- Places a line for the current style: growth direction, alignment, sizes and toggles.
function TimelineUI:LayoutUpcomingRow(row, index, style)
    local panel = row.panel
    local height = AlertRowHeight(style)
    local offset = (index - 1) * (height + style.spacing)
    local target = style.grow == "UP" and offset or -offset
    if row.layoutVersion ~= self.alertLayoutVersion or row.motionStatic or not style.pop then
        row.motionY, row.slideStarted = target, nil
    elseif row.targetY ~= target then
        row.slideFrom = row.motionY or target
        row.slideStarted = type(GetTime) == "function" and GetTime() or 0
    end
    row.index, row.grow, row.targetY = index, style.grow, target
    row.motionY = row.motionY or target
    row:SetHeight(height)
    self:PositionUpcomingRow(row, 0, row.motionY)
    row.drain:ClearAllPoints()
    local drainEdge = style.align == "RIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT"
    row.drain:SetPoint(drainEdge, row, drainEdge, style.align == "RIGHT" and -2 or 2, 0)

    local align = style.align
    row.align = align
    local edge = align == "RIGHT" and "RIGHT" or "LEFT"
    local toward = align == "RIGHT" and "LEFT" or "RIGHT"
    local sign = align == "RIGHT" and -1 or 1

    local content = row.content
    content:ClearAllPoints()
    content:SetHeight(height)
    if align == "CENTER" then
        content:SetPoint("CENTER", row, "CENTER", 0, 0)
    elseif align == "RIGHT" then
        content:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    else
        content:SetPoint("LEFT", row, "LEFT", 2, 0)
    end

    row.icon:SetSize(style.iconSize, style.iconSize)
    row.icon:ClearAllPoints()
    row.icon:SetPoint(edge, content, edge, 0, 0)
    row.icon:SetShown(style.showIcon)

    row.label:SetFont(self.fontPath, style.nameSize, "OUTLINE")
    row.label:SetJustifyH(edge)
    row.label:ClearAllPoints()
    if style.showIcon then
        row.label:SetPoint(edge, row.icon, toward, sign * 7, 0)
    else
        row.label:SetPoint(edge, content, edge, 0, 0)
    end
    row.label:SetShown(style.showName)

    row.countdown:SetFont(self.fontPath, style.countSize, "OUTLINE")
    row.countdown:SetJustifyH(edge)
    row.countdown:ClearAllPoints()
    if style.showName then
        row.countdown:SetPoint(edge, row.label, toward, sign * 8, 0)
    elseif style.showIcon then
        row.countdown:SetPoint(edge, row.icon, toward, sign * 7, 0)
    else
        row.countdown:SetPoint(edge, content, edge, 0, 0)
    end

    row.layoutVersion = self.alertLayoutVersion
    self:SetUpcomingRowShade(row, self:GetBackgroundAlpha())
end

--- Re-reads ns.db.alertStyle and re-lays the live alert and the settings sample.
function TimelineUI:ApplyAlertStyle()
    self.alertStyleCache = nil
    local style = self:GetAlertStyle()
    self.alertLayoutVersion = (self.alertLayoutVersion or 0) + 1
    local panel = self.upcomingPanel
    if panel then
        panel:SetSize(style.width, self:GetAlertPanelHeight(style))
        for index, row in ipairs(self.upcomingRows or {}) do
            self:LayoutUpcomingRow(row, index, style)
            if row.data then self:AnimateUpcomingRow(row, type(GetTime) == "function" and GetTime() or 0, style) end
            if index > style.maxRows then
                row.data = nil
                row:Hide()
            end
        end
    end
    self:RefreshAlertSample()
    if self.editSession then self:UpdateEditHUD() end
    return style
end

-- Settings sample: three lines (counting, urgent, now) drawn with the same layout code.
local ALERT_SAMPLE = {
    { data = { spellID = 740, label = "평온", icon = 136107 }, remaining = 8.4 },
    { data = { spellID = 31821, label = "오라 숙련", icon = 135872 }, remaining = 2.6 },
    { data = { spellID = 115310, label = "재활", icon = 1020466 }, remaining = 0 },
}

function TimelineUI:CreateAlertSample(parent)
    local sample = CreateFrame("Frame", nil, parent)
    sample.rows = {}
    self.alertSample = sample
    self:RefreshAlertSample()
    return sample
end

function TimelineUI:RefreshAlertSample()
    local sample = self.alertSample
    if not sample then return end
    local style = self:GetAlertStyle()
    local count = min(style.maxRows, #ALERT_SAMPLE)
    sample:SetSize(style.width, self:GetAlertPanelHeight(style, count))
    for index = 1, count do
        local row = self:CreateUpcomingRow(index, sample, sample.rows)
        self:LayoutUpcomingRow(row, index, style)
        local entry = ALERT_SAMPLE[index]
        self:FillUpcomingRow(row, entry.data, entry.remaining, 0, style)
    end
    for index = count + 1, #sample.rows do
        sample.rows[index]:Hide()
    end
end

--- Writes one entry into a line: icon, name, countdown text/colour, name clamp, group width.
function TimelineUI:FillUpcomingRow(row, data, remaining, now, style)
    if row.layoutVersion ~= self.alertLayoutVersion then
        self:LayoutUpcomingRow(row, row.index or 1, style)
    end

    local urgent = remaining <= COUNTDOWN_FROM
    local text = remaining <= 0 and "지금" or tostring(ceil(remaining))
    if row.data ~= data then
        row.data = data
        row.icon:SetTexture(ResolveIcon(data))
        row.label:SetText(ResolveLabel(data))
        row.lastCount = nil
        row.popStarted = nil
        row.enterStarted = now
        row.nowStarted = nil
    end
    row.remaining, row.updatedAt = remaining, now
    if remaining <= 0 then
        if not row.nowStarted then row.nowStarted = now end
    else
        row.nowStarted = nil
    end
    if row.lastCount ~= text then
        if urgent and row.lastCount and style.pop then row.popStarted = now end
        row.lastCount = text
        row.countdown:SetText(text)
        SetTextColor(row.countdown, remaining <= 0 and self.colors.text.highlight or urgent and self.colors.status.warning or self.accentLight)
    end

    -- [STYLE] Keep long names from pushing the enlarged countdown out of the line.
    local iconPart = style.showIcon and (style.iconSize + 7) or 0
    local slot = min(AlertCountSlot(style), max(1, row:GetWidth() - 4 - iconPart - (style.showName and 9 or 0)))
    row.popLimit = min(1.4, slot / max(1, row.countdown:GetStringWidth()))
    local contentWidth = iconPart + slot
    if style.showName then
        row.label:SetWidth(0)
        local labelWidth = min(row.label:GetStringWidth(), max(1, row:GetWidth() - 4 - iconPart - 8 - slot))
        row.label:SetWidth(labelWidth)
        contentWidth = contentWidth + labelWidth + 8
    end
    row.content:SetWidth(contentWidth)
    self:AnimateUpcomingRow(row, now, style)
    row:Show()
end

function TimelineUI:CreateFrame()
    local colors = self.colors
    local frame = CreateFrame("Frame", "DDingUI_RaidHelperTimeline", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    -- [STYLE] C안: no window surface and no outline in combat. The backdrop only carries
    -- the accent edit outline while preview/edit is active (UpdateEditHUD).
    ApplyBackdrop(frame, self.flatTexture, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })

    -- [STYLE] C5: series mover HUD (center crosshair + "X Y · W×H" readout below the frame).
    if self.styleLib.CreateMoverHUD then
        frame.editHUD = self.styleLib.CreateMoverHUD(frame, ADDON_KEY)
    end

    frame.content = frame

    frame.plot = CreateFrame("Frame", nil, frame)
    frame.plot:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.plot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.plot:SetHeight(FRAME_HEIGHT - RAIL_HEIGHT)
    self.plot = frame.plot

    if frame.plot.CreateMaskTexture then
        frame.fadeMask = frame.plot:CreateMaskTexture()
        frame.fadeMask:SetTexture(FADE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        frame.fadeMask:SetAllPoints(frame.plot)
        self.fadeMask = frame.fadeMask
    end

    frame.barBackground = frame.plot:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.barBackground:SetAllPoints(frame.plot)
    if self.styleLib.RoundTexture and self.styleLib.Radius then
        self.styleLib.RoundTexture(frame.barBackground, self.styleLib.Radius.control or 6)
        frame.barBackground._raidHelperRounded = true
    end
    self:MaskRegion(frame.barBackground)

    frame.pastShade = frame.plot:CreateTexture(nil, "BACKGROUND", nil, 2)
    frame.pastShade:SetPoint("TOPLEFT", frame.plot, "TOPLEFT")
    frame.pastShade:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT")
    self:MaskRegion(frame.pastShade)

    frame.mechanicLayer = CreateFrame("Frame", nil, frame.plot)
    frame.mechanicLayer:SetAllPoints(frame.plot)
    frame.mechanicLayer:SetFrameLevel(frame.plot:GetFrameLevel() + 2)
    self.mechanicLayer = frame.mechanicLayer

    frame.cooldownLayer = CreateFrame("Frame", nil, frame)
    frame.cooldownLayer:SetPoint("TOPLEFT", frame.plot, "BOTTOMLEFT", 0, 0)
    frame.cooldownLayer:SetPoint("TOPRIGHT", frame.plot, "BOTTOMRIGHT", 0, 0)
    frame.cooldownLayer:SetHeight(RAIL_HEIGHT)
    frame.cooldownLayer:SetFrameLevel(frame.plot:GetFrameLevel() + 2)

    -- Playhead above the icons; never masked so it stays visible at any window split.
    frame.overlay = CreateFrame("Frame", nil, frame)
    frame.overlay:SetAllPoints(frame)
    frame.overlay:SetFrameLevel(frame.plot:GetFrameLevel() + 5)
    frame.playheadGlow = frame.overlay:CreateTexture(nil, "OVERLAY", nil, 6)
    frame.playheadGlow:SetWidth(6)
    SetTextureColor(frame.playheadGlow, self.accentFrom, 0.35)
    frame.playhead = frame.overlay:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.playhead:SetWidth(2)
    SetTextureColor(frame.playhead, self.accentLight, 1)

    frame.noDataText = self:CreateLabel(frame.overlay, "small", colors.text.dim)
    frame.noDataText:SetPoint("CENTER", frame.plot, "CENTER", 0, 0)
    frame.noDataText:SetText("로그 피해 데이터 없음 · 실시간 기믹만 표시")
    frame.noDataText:Hide()

    frame.endText = self:CreateLabel(frame.overlay, "small", colors.text.highlight)
    frame.endText:SetPoint("CENTER", frame.plot, "CENTER", 0, 0)
    frame.endText:Hide()

    -- The only text outside the bar: elapsed time and phase, above the left fade edge.
    frame.timeReadout = self:CreateLabel(frame.overlay, "small", colors.text.dim)
    frame.timeReadout:SetJustifyH("LEFT")

    -- Preview-only hint, above the right fade edge (the upcoming list sits below the rail).
    frame.syncText = self:CreateLabel(frame.overlay, "small", colors.text.disabled)
    frame.syncText:SetJustifyH("RIGHT")
    frame.syncText:Hide()

    frame.mechanicChip = self:CreateChip(frame.mechanicLayer, self.accentFrom, 0.55, 4,
        { colors.bg.sidebar[1], colors.bg.sidebar[2], colors.bg.sidebar[3], 0.96 })
    frame.mechanicChip.number = self:CreateLabel(frame.mechanicChip, "title", self.accentLight)
    frame.mechanicChip.number:SetPoint("TOPLEFT", frame.mechanicChip, "TOPLEFT", 6, -3)
    frame.mechanicChip.name = self:CreateLabel(frame.mechanicChip, "small", colors.text.highlight)
    frame.mechanicChip.name:SetPoint("BOTTOMLEFT", frame.mechanicChip.number, "BOTTOMRIGHT", 4, 0)
    frame.mechanicChip.info = self:CreateLabel(frame.mechanicChip, "small", colors.text.normal)
    frame.mechanicChip.info:SetPoint("TOPLEFT", frame.mechanicChip.number, "BOTTOMLEFT", 0, -2)

    frame.cooldownChip = self:CreateChip(frame.cooldownLayer, colors.status.success, 0.5, 4,
        { colors.bg.sidebar[1], colors.bg.sidebar[2], colors.bg.sidebar[3], 0.96 })
    frame.cooldownChip.text = self:CreateLabel(frame.cooldownChip, "small", colors.text.highlight)
    frame.cooldownChip.text:SetPoint("LEFT", frame.cooldownChip, "LEFT", 6, 0)
    frame.cooldownChip:SetHeight(18)

    -- [STYLE] The alert is its own edit module but stays a child of the timeline frame, so it
    -- shares the timeline's fade in/out and "전체 크기" scale. ApplyAlertPosition anchors it.
    frame.upcomingPanel = CreateFrame("Frame", "DDingUI_RaidHelperAlert", frame)
    frame.upcomingPanel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -ALERT_ATTACH_GAP)
    frame.upcomingPanel:SetSize(UPCOMING_PANEL_MAX_WIDTH, 94) -- ApplyAlertStyle sets the real size
    frame.upcomingPanel:Hide()

    frame:SetScript("OnMouseDown", function()
        if TimelineUI.editSession then TimelineUI:SelectEditModule("timeline") end
    end)
    frame:SetScript("OnDragStart", function(currentFrame)
        if (TimelineUI:IsPreviewMode() and not TimelineUI:IsEditSessionActive())
            or (ns.db.locked and not TimelineUI:IsEditSessionActive()) or InCombatLockdown() then return end
        if TimelineUI.editSession then TimelineUI:SelectEditModule("timeline") end
        currentFrame:StartMoving()
        currentFrame._editDragging = TimelineUI:IsEditSessionActive()
        TimelineUI:UpdateEditHUD()
    end)
    frame:SetScript("OnDragStop", function(currentFrame)
        if TimelineUI:IsPreviewMode() and not TimelineUI:IsEditSessionActive() then return end
        currentFrame:StopMovingOrSizing()
        TimelineUI:FinishDrag()
    end)
    frame:SetScript("OnUpdate", function(currentFrame, elapsed)
        TimelineUI:OnUpdate(elapsed)
        if currentFrame._editDragging then
            TimelineUI:UpdateEditHUD()
        end
    end)

    self.frame = frame
    self.content = frame
    self.cooldownLayer = frame.cooldownLayer
    self.upcomingPanel = frame.upcomingPanel
    self:ApplyDisplaySettings()
end

-- [STYLE] Edit modules (2026-10-10): the combat timeline and the "곧 사용" alert are moved
-- separately. Each has its own saved anchor: timeline = ns.db.position, alert =
-- ns.db.alertPosition (nil = still attached under the timeline, the pre-split layout).
local EDIT_MODULES = { "timeline", "alert" }
local EDIT_MODULE_NAMES = { timeline = EDIT_FRAME_NAME, alert = ALERT_FRAME_NAME }

function TimelineUI:GetModuleFrame(id)
    if id == "alert" then return self.upcomingPanel end
    return self.frame
end

--- Saved anchor of a module, or nil for an alert that still follows the timeline.
function TimelineUI:GetModulePosition(id)
    if not ns.db then return nil end
    if id == "alert" then return ns.db.alertPosition end
    return ns.db.position
end

function TimelineUI:GetFrameRect(id)
    local frame = self:GetModuleFrame(id)
    if not frame then return nil end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not (left and bottom and width and height) then return nil end
    local relative = 1
    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale()
    local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    if frameScale and parentScale and parentScale > 0 then
        relative = frameScale / parentScale
    end
    return left * relative, bottom * relative, width * relative, height * relative, relative
end

local function PointCoordinate(point, left, bottom, width, height)
    point = point or "CENTER"
    local x, y = left + width * 0.5, bottom + height * 0.5
    if point:find("LEFT") then x = left elseif point:find("RIGHT") then x = left + width end
    if point:find("TOP") then y = bottom + height elseif point:find("BOTTOM") then y = bottom end
    return x, y
end

--- Snap delta (UIParent units) for a module rectangle: center, then the other module's
--- edges and the screen edges ("프레임"), then the grid.
function TimelineUI:GetSnapDelta(left, bottom, width, height, id)
    local styleLib, snap = self.styleLib, self.editSnap
    if not (styleLib and styleLib.SnapToGrid and snap and snap.enabled) then return 0, 0 end

    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local centerX = left + width * 0.5 - screenWidth * 0.5
    local centerY = bottom + height * 0.5 - screenHeight * 0.5
    local dx, dy, snappedX, snappedY = 0, 0, false, false

    if snap.center then
        local value, ok = styleLib.SnapToCenter(centerX)
        if ok then dx, snappedX = value - centerX, true end
        value, ok = styleLib.SnapToCenter(centerY)
        if ok then dy, snappedY = value - centerY, true end
    end
    if snap.frames and not (snappedX and snappedY) then
        local others = { { 0, 0, screenWidth, screenHeight } }
        for _, other in ipairs(EDIT_MODULES) do
            local otherFrame = self:GetModuleFrame(other)
            if other ~= (id or "timeline") and otherFrame and otherFrame:IsShown() then
                local otherLeft, otherBottom, otherWidth, otherHeight = self:GetFrameRect(other)
                if otherLeft then others[#others + 1] = { otherLeft, otherBottom, otherWidth, otherHeight } end
            end
        end
        local rectX, rectY = styleLib.SnapToRects({ left, bottom, width, height }, others)
        if not snappedX and rectX ~= 0 then dx, snappedX = rectX, true end
        if not snappedY and rectY ~= 0 then dy, snappedY = rectY, true end
    end
    -- Grid origin is the screen center, same as CreateEditGrid.
    if snap.grid and self.editGridEnabled ~= false then
        local spacing = self.editGridSpacing
        if not snappedX then
            local value, ok = styleLib.SnapToGrid(centerX, spacing)
            if ok then dx = value - centerX end
        end
        if not snappedY then
            local value, ok = styleLib.SnapToGrid(centerY, spacing)
            if ok then dy = value - centerY end
        end
    end
    return dx, dy
end

--- Anchor-relative offset of a module in its saved anchor model. While dragging (or when
--- asked) it is computed from the live rectangle so the HUD matches the value saved on drop.
function TimelineUI:GetAnchorOffset(withSnap, id, anchor)
    id = id or "timeline"
    local position = anchor or self:GetModulePosition(id)
    local frame = self:GetModuleFrame(id)
    if position and not (frame and frame._editDragging) and not withSnap and not anchor then
        return position.x or 0, position.y or 0
    end
    position = position or { point = "TOPLEFT", relativePoint = "CENTER" }

    local left, bottom, width, height, relative = self:GetFrameRect(id)
    if not left then return position.x or 0, position.y or 0 end
    if withSnap then
        local dx, dy = self:GetSnapDelta(left, bottom, width, height, id)
        left, bottom = left + dx, bottom + dy
    end
    local frameX, frameY = PointCoordinate(position.point, left, bottom, width, height)
    local parentX, parentY = PointCoordinate(
        position.relativePoint, 0, 0, UIParent:GetWidth(), UIParent:GetHeight()
    )
    return (frameX - parentX) / relative, (frameY - parentY) / relative
end

function TimelineUI:UpdateEditHUD()
    local frame = self.frame
    if not frame or not frame.editHUD then return false end

    local shown = self:IsEditSessionActive()
    local target = self.editTarget or "timeline"
    frame.editHUD:SetShown(shown and target == "timeline")
    local alertHUD = self.upcomingPanel and self.upcomingPanel.editHUD
    if alertHUD then alertHUD:SetShown(shown and self.editSession == true and target == "alert") end

    -- [STYLE] StyleMover is not applied to the timeline: this overlay is the live combat window
    -- itself, so the accent edit outline lives on its (otherwise invisible) backdrop.
    self:ApplyEditOutline()
    if shown then
        local moduleFrame = self:GetModuleFrame(target)
        local x, y = self:GetAnchorOffset(false, target)
        local width, height = moduleFrame:GetSize()
        local hud = target == "alert" and alertHUD or frame.editHUD
        if hud then
            hud:Update(x, y, width, height)
            -- [STYLE] A nearby module must not sit under the selected module's coordinates.
            local box = hud.box
            local other = self:GetModuleFrame(target == "alert" and "timeline" or "alert")
            box:ClearAllPoints()
            box:SetPoint("TOPRIGHT", moduleFrame, "BOTTOMRIGHT", 0, -4)
            if other and other:IsShown() and other:GetLeft() and box:GetLeft()
                and box:GetLeft() < other:GetLeft() + other:GetWidth()
                and box:GetLeft() + box:GetWidth() > other:GetLeft()
                and box:GetBottom() < other:GetTop() and box:GetTop() > other:GetBottom() then
                box:SetPoint("TOPRIGHT", moduleFrame, "BOTTOMRIGHT", 0,
                    other:GetBottom() - moduleFrame:GetBottom() - 4)
            end
        end
        if moduleFrame._editDragging and self.editGuides then
            local left, bottom, rectWidth, rectHeight = self:GetFrameRect(target)
            if left then
                self.editGuides:ShowAt(left + rectWidth * 0.5, bottom + rectHeight * 0.5)
            end
        end
        self:RefreshEditSelection(x, y)
    end
    return true
end

function TimelineUI:GetTimelineScale()
    return ClampNumber(ns.db and ns.db.timelineScale, 0.6, 1.6, 1.0)
end

function TimelineUI:GetTimelineWidth()
    return ClampNumber(ns.db and ns.db.timelineWidth, MIN_FRAME_WIDTH, MAX_FRAME_WIDTH, FRAME_WIDTH)
end

--- Height of bar + rail. Old four-row values (>= 170) are not clamped to 160: they mean
--- a different layout, so they read as the new default.
function TimelineUI.ResolveTimelineHeight(value)
    value = tonumber(value)
    if not value or value >= LEGACY_HEIGHT_FLOOR then return FRAME_HEIGHT end
    return min(MAX_FRAME_HEIGHT, max(MIN_FRAME_HEIGHT, value))
end

function TimelineUI:GetTimelineHeight()
    return TimelineUI.ResolveTimelineHeight(ns.db and ns.db.timelineHeight)
end

function TimelineUI:GetBackgroundAlpha()
    return ClampNumber(ns.db and ns.db.backgroundAlpha, 0, 1, 1.0)
end

-- [STYLE] C안: "배경 불투명도" scales only the bar surface and the past-time shade.
-- Ridge, ticks, icons and text keep full opacity, so 0% leaves them floating on screen.
function TimelineUI:ApplyBackgroundStyle()
    if not self.frame then return false end

    local alpha = self:GetBackgroundAlpha()
    local input = self.colors.bg.input
    local background = self.frame.barBackground
    local backgroundAlpha = (input[4] or 1) * alpha
    if background._raidHelperRounded then
        background:SetVertexColor(input[1], input[2], input[3], backgroundAlpha)
    else
        background:SetColorTexture(input[1], input[2], input[3], backgroundAlpha)
    end
    self.frame.pastShade:SetColorTexture(0, 0, 0, 0.35 * alpha)
    for _, row in ipairs(self.upcomingRows or {}) do
        self:SetUpcomingRowShade(row, alpha)
    end
    for _, row in ipairs(self.alertSample and self.alertSample.rows or {}) do
        self:SetUpcomingRowShade(row, alpha)
    end
    self:ApplyEditOutline()
    return true
end

--- Accent outline only while editing; otherwise the frame has no edge at all.
function TimelineUI:ApplyEditOutline()
    local frame = self.frame
    if not frame then return end
    if self:IsEditSessionActive() then
        -- Full accent when the timeline is the selected edit module, dimmed otherwise.
        local accent = self.accentFrom
        local selected = not self.editSession or (self.editTarget or "timeline") == "timeline"
        frame:SetBackdropBorderColor(accent[1], accent[2], accent[3], selected and (accent[4] or 1) or 0.4)
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function TimelineUI:ApplyDisplaySettings()
    if not self.frame then return false end

    local width = self:GetTimelineWidth()
    local height = self:GetTimelineHeight()
    local fade = floor(width * FADE_SHARE + 0.5)
    -- [STYLE] The rail follows the cooldown icon; the bar keeps what is left of the height, and
    -- the mechanic icon never outgrows that bar: 10 px above it, then its countdown (14 px) or,
    -- without the number, just the nearest-highlight growth.
    self.timelineStyleCache = nil
    local style = self:GetTimelineStyle()
    local rail = style.cooldownSize + RAIL_HEIGHT - COOLDOWN_SIZE
    local barHeight = height - rail
    self.mechanicSize = min(style.mechanicSize,
        max(TIMELINE_STYLE_SPEC.mechanicSize.min, barHeight - (style.showCountdown and 24 or 12)))
    self.ridgeTopSpace = style.showMechanics
        and (self.mechanicSize + RIDGE_TOP_SPACE - MECHANIC_SIZE) or 20
    self.frame:SetSize(width, height)
    self.plot:SetHeight(barHeight)
    self.cooldownLayer:SetHeight(rail)
    -- [STYLE] The alert is its own module now: its size comes from the alert style options.
    self:ApplyAlertStyle()

    self.compact = width < COMPACT_WIDTH
    local timeReadout = self.frame.timeReadout
    if timeReadout then
        timeReadout:ClearAllPoints()
        timeReadout:SetPoint("BOTTOMLEFT", self.plot, "TOPLEFT", fade, 3)
        timeReadout:SetShown(not self.compact and style.showTimeReadout)
    end
    local syncText = self.frame.syncText
    if syncText then
        syncText:ClearAllPoints()
        syncText:SetPoint("BOTTOMRIGHT", self.plot, "TOPRIGHT", -fade, 3)
    end
    if self.compact then
        if self.frame.mechanicChip then self.frame.mechanicChip:Hide() end
        if self.frame.cooldownChip then self.frame.cooldownChip:Hide() end
    end

    self.frame:SetScale(self:GetTimelineScale())
    self:ApplyBackgroundStyle()
    self:UpdateEditHUD()
    return true
end

--- Re-reads ns.db.timelineStyle (and the window keys) and redraws a running bar at once.
function TimelineUI:ApplyTimelineStyle()
    if not self.frame then return false end
    for _, marker in ipairs(self.mechanicMarkers or {}) do
        marker.nearState = nil
    end
    self:ApplyDisplaySettings()
    if ns.Engine and ns.Engine.IsRunning and ns.Engine:IsRunning() then self:UpdateView() end
    return self:GetTimelineStyle()
end

function TimelineUI:RefreshMedia()
    local styleLib = self.styleLib
    self.fontPath = styleLib.GetFont and styleLib:GetFont("primary") or styleLib.Font.path
    self.titleFontSize = styleLib.GetFontSize and styleLib:GetFontSize("title") or styleLib.Font.title
    self.normalFontSize = styleLib.GetFontSize and styleLib:GetFontSize("normal") or styleLib.Font.normal
    self.smallFontSize = styleLib.GetFontSize and styleLib:GetFontSize("small") or styleLib.Font.small
    self.flatTexture = styleLib.GetTexture and styleLib:GetTexture("flat") or "Interface\\Buttons\\WHITE8x8"

    for _, label in ipairs(self.fontStrings or {}) do
        label:SetFont(self.fontPath, self:GetCategoryFontSize(label._raidHelperFontCategory), "OUTLINE")
    end

    if self.frame then
        self:ApplyBackgroundStyle()
    end
    for _, pool in ipairs({ self.mechanicMarkers or {}, self.cooldownMarkers or {} }) do
        for _, marker in ipairs(pool) do
            ApplyBackdrop(marker, self.flatTexture, self.colors.bg.widget, marker.borderColor)
            marker.nearState = nil
        end
    end
    for _, chip in ipairs(self.chips or {}) do
        self:StyleChip(chip)
        chip.contentKey = nil
    end
end

function TimelineUI:ApplyPosition()
    local position = ns.db.position
    self.frame:ClearAllPoints()
    self.frame:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or "CENTER",
        position.x or 0,
        position.y or -180
    )
    self:ApplyAlertPosition()
    self:UpdateEditHUD()
end

--- The alert follows the timeline until it gets its own anchor (first edit session or reset).
function TimelineUI:ApplyAlertPosition()
    local panel = self.upcomingPanel
    if not panel then return end
    local position = ns.db and ns.db.alertPosition
    panel:ClearAllPoints()
    if type(position) == "table" then
        panel:SetPoint(
            position.point or "TOPLEFT",
            UIParent,
            position.relativePoint or "CENTER",
            position.x or 0,
            position.y or 0
        )
    else
        panel:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", 0, -ALERT_ATTACH_GAP)
    end
end

--- Where the attached alert sits right now, as its own UIParent anchor.
function TimelineUI:GetAttachedAlertPosition()
    local panel = self.upcomingPanel
    local saved = ns.db.alertPosition
    ns.db.alertPosition = nil
    self:ApplyAlertPosition()
    local anchor = { point = "TOPLEFT", relativePoint = "CENTER" }
    local x, y = self:GetAnchorOffset(false, "alert", anchor)
    ns.db.alertPosition = saved
    self:ApplyAlertPosition()
    anchor.x, anchor.y = floor(x + 0.5), floor(y + 0.5)
    return anchor, panel
end

--- Gives a still-attached alert its own saved anchor at its current place, so moving the
--- timeline no longer drags it along.
function TimelineUI:DetachAlert()
    if not ns.db or type(ns.db.alertPosition) == "table" or not self.upcomingPanel then return false end
    ns.db.alertPosition = (self:GetAttachedAlertPosition())
    self:ApplyAlertPosition()
    return true
end

function TimelineUI:SavePosition()
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    ns.db.position.point = point or "CENTER"
    ns.db.position.relativePoint = relativePoint or "CENTER"
    ns.db.position.x = floor((x or 0) + 0.5)
    ns.db.position.y = floor((y or 0) + 0.5)
    self:UpdateEditHUD()
end

local function DefaultTimelinePosition()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }
end

--- Remote "초기화" resets the selected module. Outside edit mode (settings "위치 초기화",
--- /drh reset) both go back: timeline to its default, alert back under the timeline.
function TimelineUI:ResetPosition(id)
    if not self.editSession then
        ns.db.position = DefaultTimelinePosition()
        ns.db.alertPosition = nil
        self:ApplyPosition()
        return
    end
    id = id or self.editTarget or "timeline"
    self:PushEditHistory(id)
    if id == "alert" then
        ns.db.alertPosition = nil
        self:ApplyAlertPosition()
        self:DetachAlert()
        self:UpdateEditHUD()
        return
    end
    ns.db.position = DefaultTimelinePosition()
    self:ApplyPosition()
end

------------------------------------------------------------------------
-- [STYLE] C12 edit mode: StyleLib 1.4 remote, grid, guides, snap, history.
-- Saved anchors: ns.db.position (timeline) and ns.db.alertPosition (alert), both
-- {point, relativePoint, x, y} relative to UIParent.
------------------------------------------------------------------------
local function CopyPosition(position)
    if type(position) ~= "table" then return false end
    return {
        point = position.point or "CENTER",
        relativePoint = position.relativePoint or "CENTER",
        x = position.x or 0,
        y = position.y or 0,
    }
end

local function GetAddonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(getMetadata) == "function" then
        return getMetadata(ns.addonName or "DDingUI_RaidHelper", "Version") or ""
    end
    return ""
end

function TimelineUI:IsEditSessionActive()
    return self.editSession == true
end

--- Undo entries remember which module moved: { id =, position = copy or false (attached) }.
function TimelineUI:PushEditHistory(id)
    if not self.editSession or not ns.db then return end
    id = id or self.editTarget or "timeline"
    local undo = self.editUndo
    undo[#undo + 1] = { id = id, position = CopyPosition(self:GetModulePosition(id)) }
    if #undo > EDIT_HISTORY_LIMIT then table.remove(undo, 1) end
    self.editRedo = {}
end

function TimelineUI:SetStoredPosition(position, id)
    id = id or self.editTarget or "timeline"
    if id == "alert" then
        if position then
            ns.db.alertPosition = {
                point = position.point or "TOPLEFT",
                relativePoint = position.relativePoint or "CENTER",
                x = floor((tonumber(position.x) or 0) + 0.5),
                y = floor((tonumber(position.y) or 0) + 0.5),
            }
        else
            ns.db.alertPosition = nil
        end
        self:ApplyAlertPosition()
        self:UpdateEditHUD()
        return
    end
    local stored = ns.db.position
    stored.point = position.point or "CENTER"
    stored.relativePoint = position.relativePoint or "CENTER"
    stored.x = floor((tonumber(position.x) or 0) + 0.5)
    stored.y = floor((tonumber(position.y) or 0) + 0.5)
    self:ApplyPosition()
end

--- Selected module for the remote (nudge, X/Y, reset). Clicking a module also selects it.
function TimelineUI:SelectEditModule(id)
    if id ~= "alert" then id = "timeline" end
    self.editTarget = id
    if self.upcomingPanel and self.upcomingPanel.moverStyle then
        self.upcomingPanel.moverStyle:SetSelected(id == "alert")
    end
    if self.editRemote and self.editRemote.RefreshFrames and self.editRemote.selectedModule ~= id then
        self.editRemote.selectedModule = id
        self.editRemote:RefreshFrames(id)
    end
    self:UpdateEditHUD()
    return true
end

function TimelineUI:NudgePosition(dx, dy)
    if not self.editSession then return false end
    local id = self.editTarget or "timeline"
    if id == "alert" then self:DetachAlert() end
    local position = self:GetModulePosition(id)
    self:PushEditHistory(id)
    self:SetStoredPosition({
        point = position.point,
        relativePoint = position.relativePoint,
        x = (position.x or 0) + (tonumber(dx) or 0),
        y = (position.y or 0) + (tonumber(dy) or 0),
    }, id)
    return true
end

function TimelineUI:SetPositionOffset(x, y)
    if not self.editSession then return false end
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then return false end
    local id = self.editTarget or "timeline"
    if id == "alert" then self:DetachAlert() end
    local position = self:GetModulePosition(id)
    self:PushEditHistory(id)
    self:SetStoredPosition({
        point = position.point,
        relativePoint = position.relativePoint,
        x = x,
        y = y,
    }, id)
    return true
end

function TimelineUI:UndoPosition()
    local undo = self.editUndo
    if not self.editSession or not undo or #undo == 0 then return false end
    local previous = table.remove(undo)
    self.editRedo[#self.editRedo + 1] = {
        id = previous.id, position = CopyPosition(self:GetModulePosition(previous.id)),
    }
    self:SetStoredPosition(previous.position, previous.id)
    self:SelectEditModule(previous.id)
    return true
end

function TimelineUI:RedoPosition()
    local redo = self.editRedo
    if not self.editSession or not redo or #redo == 0 then return false end
    local nextEntry = table.remove(redo)
    self.editUndo[#self.editUndo + 1] = {
        id = nextEntry.id, position = CopyPosition(self:GetModulePosition(nextEntry.id)),
    }
    self:SetStoredPosition(nextEntry.position, nextEntry.id)
    self:SelectEditModule(nextEntry.id)
    return true
end

--- Drag end: inside an edit session the drop is snapped and written back in the module's
--- saved anchor model.
function TimelineUI:FinishDrag(id)
    id = id or "timeline"
    local frame = self:GetModuleFrame(id)
    if not frame then return end
    local wasEditing = frame._editDragging
    frame._editDragging = false
    if self.editGuides then self.editGuides:Hide() end

    if wasEditing and self.editSession then
        if id == "alert" then
            -- The live rect is already the dropped place; keep the attached anchor model.
            local anchor = self:GetModulePosition("alert") or { point = "TOPLEFT", relativePoint = "CENTER" }
            local x, y = self:GetAnchorOffset(true, "alert", anchor)
            self:PushEditHistory("alert")
            self:SetStoredPosition({ point = anchor.point, relativePoint = anchor.relativePoint, x = x, y = y }, "alert")
            return
        end
        local x, y = self:GetAnchorOffset(true, "timeline")
        local position = ns.db.position
        self:PushEditHistory("timeline")
        self:SetStoredPosition({
            point = position.point,
            relativePoint = position.relativePoint,
            x = x,
            y = y,
        }, "timeline")
        return
    end
    if id == "timeline" then self:SavePosition() end
end

function TimelineUI:RefreshEditSelection(x, y)
    local remote = self.editRemote
    if not (remote and self.editSession and self.frame) then return end
    local id = self.editTarget or "timeline"
    local frame = self:GetModuleFrame(id)
    local position = self:GetModulePosition(id) or {}
    local width, height = frame:GetSize()
    remote:SetSelection({
        name = EDIT_MODULE_NAMES[id],
        anchor = "UIParent · " .. tostring(position.point or "CENTER"),
        x = x or position.x or 0,
        y = y or position.y or 0,
        w = width,
        h = height,
    })
    remote:SetUndoState(#(self.editUndo or {}) > 0, #(self.editRedo or {}) > 0)
end

--- Edit surface for the alert: series mover look, drag + click to select, own HUD.
function TimelineUI:EnsureAlertMover()
    local panel = self.upcomingPanel
    if not panel or panel.mover then return panel ~= nil end
    local styleLib = self.styleLib

    panel.mover = CreateFrame("Frame", nil, panel)
    panel.mover:SetAllPoints(panel)
    panel.mover:SetFrameLevel(panel:GetFrameLevel() + 10)
    if styleLib.StyleMover then
        panel.moverStyle = styleLib.StyleMover(panel.mover, ADDON_KEY, { label = ALERT_FRAME_NAME })
    end
    if styleLib.CreateMoverHUD then
        panel.editHUD = styleLib.CreateMoverHUD(panel, ADDON_KEY)
    end
    panel.mover:Hide()

    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnMouseDown", function()
        if TimelineUI.editSession then TimelineUI:SelectEditModule("alert") end
    end)
    panel:SetScript("OnDragStart", function(currentPanel)
        if not TimelineUI.editSession or InCombatLockdown() then return end
        TimelineUI:SelectEditModule("alert")
        TimelineUI:DetachAlert()
        currentPanel:StartMoving()
        currentPanel._editDragging = true
        TimelineUI:UpdateEditHUD()
    end)
    panel:SetScript("OnDragStop", function(currentPanel)
        currentPanel:StopMovingOrSizing()
        TimelineUI:FinishDrag("alert")
    end)
    panel:SetScript("OnUpdate", function(currentPanel)
        if currentPanel._editDragging then TimelineUI:UpdateEditHUD() end
    end)
    return true
end

--- Edit surfaces on while editing; outside it the alert never catches the mouse.
function TimelineUI:SetAlertEditable(enabled)
    local panel = self.upcomingPanel
    if not panel then return end
    self:EnsureAlertMover()
    panel:EnableMouse(enabled == true)
    panel.mover:SetShown(enabled == true)
    if panel.moverStyle then panel.moverStyle:SetSelected(enabled and self.editTarget == "alert") end
    if enabled then
        panel:Show()
    elseif not (self.upcomingRows[1] and self.upcomingRows[1]:IsShown()) then
        panel:Hide()
    end
end

function TimelineUI:EnsureEditTools()
    if self.editRemote then return true end
    local styleLib = self.styleLib
    if not (styleLib and styleLib.CreateEditRemote and styleLib.CreateEditGrid) then return false end

    local spec = styleLib.EditModeSpec or {}
    self.editGridEnabled = self.editGridEnabled ~= false
    self.editGridSpacing = self.editGridSpacing or spec.gridSpacing or 32
    self.editSnap = self.editSnap or { enabled = true, center = true, grid = true, frames = true }

    self.editGrid = styleLib.CreateEditGrid(ADDON_KEY, { spacing = self.editGridSpacing })
    if styleLib.CreateEditGuides then
        self.editGuides = styleLib.CreateEditGuides(ADDON_KEY)
    end

    self.editRemote = styleLib.CreateEditRemote(ADDON_KEY, {
        title = "편집 모드",
        version = GetAddonVersion(),
        frames = function()
            local list = {}
            for _, id in ipairs(EDIT_MODULES) do
                list[#list + 1] = { text = EDIT_MODULE_NAMES[id], value = id }
            end
            return list
        end,
        onSelectFrame = function(value) TimelineUI:SelectEditModule(value) end,
        onNudge = function(dx, dy) TimelineUI:NudgePosition(dx, dy) end,
        onApplyXY = function(x, y) TimelineUI:SetPositionOffset(x, y) end,
        onReset = function() TimelineUI:ResetPosition() end,
        onUndo = function() TimelineUI:UndoPosition() end,
        onRedo = function() TimelineUI:RedoPosition() end,
        onDone = function() TimelineUI:SetEditMode(false) end,
        grid = {
            enabled = self.editGridEnabled,
            spacing = self.editGridSpacing,
            onToggle = function(enabled)
                TimelineUI.editGridEnabled = enabled and true or false
                if not TimelineUI.editSession then return end
                if enabled then
                    TimelineUI.editGrid:ShowAnimated()
                else
                    TimelineUI.editGrid:HideAnimated()
                end
            end,
            onSpacing = function(spacing)
                TimelineUI.editGridSpacing = spacing
                TimelineUI.editGrid:SetSpacing(spacing)
            end,
        },
        snap = {
            enabled = self.editSnap.enabled,
            center = self.editSnap.center,
            grid = self.editSnap.grid,
            frames = self.editSnap.frames,
            onChange = function(key, enabled)
                TimelineUI.editSnap[key] = enabled and true or false
            end,
        },
        -- Approved SavedVariables key: editRemotePos = { point =, x =, y = } (named keys).
        loadPosition = function()
            local saved = ns.db and ns.db.editRemotePos
            if type(saved) == "table" and type(saved.point) == "string" then
                return saved.point, tonumber(saved.x) or 0, tonumber(saved.y) or 0
            end
        end,
        savePosition = function(point, x, y)
            if not ns.db then return end
            ns.db.editRemotePos = { point = point or "TOP", x = x or 0, y = y or 0 }
        end,
    })
    -- [STYLE] Keep both selection labels at their top anchors in the taller two-module remote.
    self.editRemote.nameText:SetJustifyV("TOP")
    self.editRemote.infoText:SetJustifyV("TOP")
    return self.editRemote ~= nil
end

function TimelineUI:BeginEditSession()
    if self.editSession then return end
    self.editSession = true
    self.editUndo, self.editRedo = {}, {}
    self.editTarget = "timeline"

    -- C12: entering edit mode closes the settings window; leaving reopens it (only if it was open).
    local options = ns.Options
    local optionsFrame = options and options.frame
    self.reopenOptions = optionsFrame and optionsFrame:IsShown() and not optionsFrame._ddslPanelClosing and true or false
    if self.reopenOptions and options.Close then options:Close() end

    -- Split the modules: an alert still riding under the timeline keeps its place but gets
    -- its own anchor, so each one moves on its own from now on.
    self:SetAlertEditable(true)
    self:DetachAlert()

    if self:EnsureEditTools() then
        if self.editRemote.SetGridState then
            self.editRemote:SetGridState(self.editGridEnabled, self.editGridSpacing)
        end
        if self.editGridEnabled then self.editGrid:ShowAnimated() end
        self.editRemote:EnableKeyboard(true)
        self.editRemote:Show()
    end
    self:SelectEditModule("timeline")
end

function TimelineUI:EndEditSession(reopenOptions)
    if not self.editSession then return end
    for _, id in ipairs(EDIT_MODULES) do
        local moduleFrame = self:GetModuleFrame(id)
        if moduleFrame and moduleFrame._editDragging then
            moduleFrame:StopMovingOrSizing()
            self:FinishDrag(id)
        end
    end
    self.editSession = false
    self:SetAlertEditable(false)
    if self.upcomingPanel and self.upcomingPanel.editHUD then self.upcomingPanel.editHUD:Hide() end

    local remote = self.editRemote
    if remote then
        -- [12.0.1] Stop key capture at once: the remote's OnKeyDown calls SetPropagateKeyboardInput,
        -- which must not run once combat lockdown starts (the close motion lasts ~0.14s).
        remote:EnableKeyboard(false)
        if remote:IsShown() then
            if not reopenOptions and remote.HideImmediately then
                remote:HideImmediately()
            else
                remote:Hide()
            end
        end
    end
    if self.editGrid and self.editGrid:IsShown() then self.editGrid:HideAnimated() end
    if self.editGuides then self.editGuides:Hide() end

    local reopen = reopenOptions and self.reopenOptions
    self.reopenOptions = false
    if reopen and ns.Options and ns.Options.Open then ns.Options:Open() end
end

function TimelineUI:IsPreviewMode()
    return self.previewMode == true or self.editMode == true
end

function TimelineUI:RefreshPreviewControl()
    -- [STYLE] Watch the actual UI above settings, without enabling drag or edit overlays.
    if self.frame and self.frame.EnableMouse then
        local watching = self:IsPreviewMode() and not self.editMode
        self.frame:EnableMouse(not watching)
        self.frame:SetFrameStrata(watching and "FULLSCREEN_DIALOG" or "MEDIUM")
    end
    if ns.Options and ns.Options.RefreshPreviewButton then
        ns.Options:RefreshPreviewButton()
    end
end

--- opts.editMode enables positioning; opts.noReopen keeps settings closed on combat start.
function TimelineUI:SetPreviewMode(enabled, opts)
    enabled = enabled == true
    local editing = enabled and opts and opts.editMode == true or false
    if enabled == self:IsPreviewMode() and editing == (self.editMode == true) then
        self:RefreshPreviewControl()
        return true
    end
    if enabled and InCombatLockdown and InCombatLockdown() then
        ns:Print("전투 중에는 미리보기를 시작할 수 없습니다.")
        return false
    end

    if enabled then
        local engineOptions = ns.Engine.options or {}
        if ns.Engine:IsRunning() and not (engineOptions.previewMode or engineOptions.editMode) then
            ns:Print("실행 중인 타임라인을 먼저 종료해 주세요.")
            return false
        end
        local model = ns.Registry and ns.Registry:GetByKey("demo")
        if not model then
            ns:Print("미리보기 데이터를 불러오지 못했습니다.")
            return false
        end

        if not editing then self:EndEditSession(true) end
        self.previewMode = true
        self.editMode = editing
        ns.Engine:StartModel(model, {
            demo = true,
            loop = true,
            previewMode = true,
            editMode = editing,
        })
        if self.frame then self.frame:Show() end
        if editing then self:BeginEditSession() end
        self:UpdateEditHUD()
        self:RefreshPreviewControl()
        ns:Print(editing and "편집 모드: 드래그·방향키·편집 리모컨으로 위치를 조정합니다. Esc 또는 완료로 종료합니다."
            or "미리보기: 견본 전투를 반복 재생합니다. 미리보기 종료 버튼으로 닫습니다.")
        return true
    end

    local wasEditing = self.editMode == true
    self.previewMode = false
    self.editMode = false
    self:EndEditSession(not (opts and opts.noReopen))
    local engineOptions = ns.Engine.options or {}
    if ns.Engine:IsRunning() and (engineOptions.previewMode or engineOptions.editMode) then
        ns.Engine:StopEncounter(false)
    end
    self:UpdateEditHUD()
    if self.frame then self.frame:Hide() end
    self:RefreshPreviewControl()
    ns:Print(wasEditing and "편집 모드를 종료하고 위치를 저장했습니다." or "미리보기를 종료했습니다.")
    return true
end

function TimelineUI:TogglePreviewMode()
    return self:SetPreviewMode(not self:IsPreviewMode())
end

-- [STYLE] Editing still uses the demo, but only this entry point opens the C12 remote.
function TimelineUI:SetEditMode(enabled)
    return self:SetPreviewMode(enabled, { editMode = enabled == true })
end

function TimelineUI:ToggleEditMode()
    return self:SetEditMode(not self:IsEditSessionActive())
end

function TimelineUI:Initialize()
    if self.initialized then return end

    local styleLib = ns.GetStyleLib and ns:GetStyleLib()
        or _G.DDingUI_RaidHelperStyleLib -- [REFACTOR] private embedded copy only
    if not styleLib or not styleLib.Colors then
        ns:Print("RaidHelper 내장 StyleLib을 불러오지 못했습니다.")
        return
    end

    self.styleLib = styleLib
    self.colors = styleLib.Colors
    self.tokens = styleLib.Tokens or {}
    self.fontStrings = {}
    self.fontPath = styleLib.GetFont and styleLib:GetFont("primary") or styleLib.Font.path
    self.titleFontSize = styleLib.GetFontSize and styleLib:GetFontSize("title") or styleLib.Font.title
    self.normalFontSize = styleLib.GetFontSize and styleLib:GetFontSize("normal") or styleLib.Font.normal
    self.smallFontSize = styleLib.GetFontSize and styleLib:GetFontSize("small") or styleLib.Font.small
    self.flatTexture = styleLib.GetTexture and styleLib:GetTexture("flat") or "Interface\\Buttons\\WHITE8x8"
    self.accentFrom, self.accentTo, self.accentLight, self.accentDark = styleLib.GetAccent("RaidHelper")
    self.accentLight = self.accentLight or self.accentFrom
    self.accentDark = self.accentDark or self.accentTo
    self.ridgeBottomColor = CreateColor(self.accentDark[1], self.accentDark[2], self.accentDark[3], 0.12)
    self.updateInterval = self.tokens.ANIM_FPS_LIMIT or UPDATE_INTERVAL
    self.chips = {}
    self.damageLines = {}
    self.damageColumns = {}
    self.gridLines = {}
    self.phaseMarkers = {}
    self.mechanicMarkers = {}
    self.cooldownMarkers = {}
    self.upcomingRows = {}
    self.elapsed = 0

    self:CreateFrame()
    self:ApplyPosition()
    if styleLib.RegisterCallback then
        styleLib.RegisterCallback(self, "MediaChanged", function()
            TimelineUI:RefreshMedia()
        end)
    end
    self.initialized = true
end

function TimelineUI:MapTimeToX(eventTime, currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    return ((eventTime - currentTime + past) / (past + future)) * width
end

function TimelineUI:UpdateGrid(currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local firstTick = ceil((currentTime - past) / 5) * 5
    local finalTick = currentTime + future
    local visible = 0
    local tick = firstTick

    -- [STYLE] C안: unlabelled ticks rising from the bar floor; 10 s ticks are taller.
    local showGrid = self:GetTimelineStyle().showGrid
    while showGrid and tick <= finalTick do
        visible = visible + 1
        local grid = self:GetGrid(visible)
        local major = tick % 10 == 0
        if grid.major ~= major then
            grid.major = major
            grid.line:SetHeight(major and 7 or 4)
            grid.line:SetColorTexture(1, 1, 1, major and 0.28 or 0.18)
        end
        grid.line:ClearAllPoints()
        grid.line:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", self:MapTimeToX(tick, currentTime, width), 0)
        grid.line:Show()
        tick = tick + 5
    end

    for index = visible + 1, #self.gridLines do
        self.gridLines[index].line:Hide()
    end
end

local function PhaseLabel(phase, fallbackIndex)
    return phase.label or ("P" .. tostring(phase.index or fallbackIndex or 1))
end

function TimelineUI:UpdatePhases(model, currentTime, width, activePhase)
    local phases = self:GetTimelineStyle().showPhases and model.phases or {}
    local colors = self.colors
    local visible = 0

    for index, phase in ipairs(phases) do
        local startX = self:MapTimeToX(phase.t or 0, currentTime, width)
        local nextPhase = phases[index + 1]
        local endX = nextPhase and self:MapTimeToX(nextPhase.t or 0, currentTime, width) or (width + 1)
        local left, right = max(0, startX), min(width, endX)
        if right > left then
            visible = visible + 1
            local marker = self:GetPhaseMarker(visible)
            local active = phase == activePhase
            if marker.active ~= active then
                marker.active = active
                if active then
                    SetTextureColor(marker.ribbon, self.accentFrom, 1)
                else
                    SetTextureColor(marker.ribbon, colors.status.warning, 0.5)
                end
            end
            marker.ribbon:ClearAllPoints()
            marker.ribbon:SetPoint("TOPLEFT", self.plot, "TOPLEFT", left, 0)
            marker.ribbon:SetWidth(right - left)
            marker.ribbon:Show()

            local edge = (startX >= 0 and startX <= width) and EdgeAlpha(startX, width) or 0
            if edge > 0 then
                marker.line:ClearAllPoints()
                marker.line:SetPoint("TOP", self.plot, "TOPLEFT", startX, 0)
                marker.line:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", startX, 0)
                marker.line:Show()
                marker.label:SetText(PhaseLabel(phase, index))
                marker.chip:SetWidth(ceil(marker.label:GetStringWidth()) + 8)
                marker.chip:ClearAllPoints()
                marker.chip:SetPoint("TOP", self.plot, "TOPLEFT", startX, -4)
                marker.chip:SetAlpha(edge)
                marker.chip:Show()
            else
                marker.line:Hide()
                marker.chip:Hide()
            end
        end
    end

    for index = visible + 1, #self.phaseMarkers do
        local marker = self.phaseMarkers[index]
        marker.ribbon:Hide()
        marker.line:Hide()
        marker.chip:Hide()
    end
end

function TimelineUI:SetColumnRatio(column, ratio)
    if column.ratio and abs(column.ratio - ratio) < 0.01 then return end
    column.ratio = ratio
    local from, dark = self.accentFrom, self.accentDark
    local red = dark[1] + (from[1] - dark[1]) * ratio
    local green = dark[2] + (from[2] - dark[2]) * ratio
    local blue = dark[3] + (from[3] - dark[3]) * ratio
    local alpha = 0.12 + 0.58 * ratio
    if column.topColor.SetRGBA then
        column.topColor:SetRGBA(red, green, blue, alpha)
    else
        column.topColor = CreateColor(red, green, blue, alpha)
    end
    -- VERTICAL gradients run bottom -> top: dark 12% at the floor, accent 70% at full height.
    column:SetGradient("VERTICAL", self.ridgeBottomColor, column.topColor)
end

function TimelineUI:UpdateDamage(model, currentTime, width, height)
    local showDamage = self:GetTimelineStyle().showDamage
    local damage = model.damage or {}
    local values = showDamage and damage.values or {}
    local interval = damage.interval or 0.5
    local maximum = max(1, damage.max or 1)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = max(0, currentTime - past - interval)
    local rangeEnd = currentTime + future + interval
    local firstIndex = max(1, floor(rangeStart / interval) + 1)
    local finalIndex = min(#values - 1, ceil(rangeEnd / interval) + 1)
    -- [STYLE] C안: the ridge lies on the bar floor and stays below the icon row.
    local amplitude = max(8, height - (self.ridgeTopSpace or RIDGE_TOP_SPACE))
    local light = self.accentLight
    local visible = 0

    for index = firstIndex, finalIndex do
        local firstValue = values[index]
        local secondValue = values[index + 1]
        if firstValue and secondValue then
            visible = visible + 1
            local firstX = self:MapTimeToX((index - 1) * interval, currentTime, width)
            local secondX = self:MapTimeToX(index * interval, currentTime, width)
            local firstRatio = min(1, max(0, firstValue / maximum))
            local secondRatio = min(1, max(0, secondValue / maximum))

            local column = self:GetDamageColumn(visible)
            local ratio = (firstRatio + secondRatio) * 0.5
            local columnHeight = ratio * amplitude
            if columnHeight < 0.5 then
                column:Hide()
            else
                column:ClearAllPoints()
                column:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", firstX, 1)
                column:SetSize(max(0.5, secondX - firstX + 0.5), columnHeight)
                self:SetColumnRatio(column, ratio)
                column:Show()
            end

            local line = self:GetDamageLine(visible)
            if line then
                line:SetStartPoint("BOTTOMLEFT", self.plot, firstX, 1 + firstRatio * amplitude)
                line:SetEndPoint("BOTTOMLEFT", self.plot, secondX, 1 + secondRatio * amplitude)
                if self.lineMaskFailed then
                    local edge = EdgeAlpha((firstX + secondX) * 0.5, width)
                    line:SetColorTexture(light[1], light[2], light[3], 0.9 * edge)
                end
                line:Show()
            end
        end
    end

    for index = visible + 1, #self.damageLines do
        self.damageLines[index]:Hide()
    end
    for index = visible + 1, #self.damageColumns do
        self.damageColumns[index]:Hide()
    end
    self.frame.noDataText:SetShown(showDamage and #values == 0)
end

--- Places one icon. Nothing is clamped into the bar: icons slide out through the edge fade.
--- Returns false when the icon is fully faded out and therefore hidden.
function TimelineUI:ConfigureMarker(marker, data, currentTime, width, kind, near)
    local style = self:GetTimelineStyle()
    local x = self:MapTimeToX(data.t or 0, currentTime, width)
    local edge = EdgeAlpha(x, width)
    local remaining = (data.t or 0) - currentTime
    local past = remaining < 0
    local pastAlpha = style.pastAlpha / 100
    if edge <= 0 or (past and pastAlpha <= 0) then
        marker:Hide()
        return false
    end

    marker.data = data
    marker.x = x
    marker.remaining = remaining
    marker.icon:SetTexture(ResolveIcon(data))
    if marker.icon.SetDesaturated then marker.icon:SetDesaturated(past) end
    marker:SetAlpha((past and pastAlpha or 1) * edge)
    marker:ClearAllPoints()

    if kind == "cooldown" then
        local size = style.cooldownSize
        marker:SetSize(size, size)
        marker:SetPoint("TOP", marker:GetParent(), "TOPLEFT", x, -8)
        if style.showSpread and type(data.spread) == "number" and data.spread > 0 then
            local secondsWidth = width / (max(1, ns.db.windowPast or 12) + max(1, ns.db.windowFuture or 38))
            local desiredWidth = max(size, data.spread * 2 * secondsWidth)
            local spreadLeft = max(0, x - desiredWidth * 0.5)
            local spreadRight = min(width, x + desiredWidth * 0.5)
            if spreadRight > spreadLeft then
                marker.spread:ClearAllPoints()
                marker.spread:SetPoint("CENTER", marker:GetParent(), "TOPLEFT", (spreadLeft + spreadRight) * 0.5, -4)
                marker.spread:SetWidth(spreadRight - spreadLeft)
                marker.spread:Show()
            else
                marker.spread:Hide()
            end
        else
            marker.spread:Hide()
        end
    else
        near = near == true and not past
        -- "가까운 기믹 강조" off: the nearest one keeps its detail chip but not the size and halo.
        local highlight = near and style.highlightNear
        local size = (self.mechanicSize or MECHANIC_SIZE)
            + (highlight and (MECHANIC_NEAR_SIZE - MECHANIC_SIZE) or 0)
        marker:SetSize(size, size)
        marker:SetPoint("TOP", marker:GetParent(), "TOPLEFT", x, highlight and -8 or -10)
        if marker.nearState ~= near or marker.highlighted ~= highlight then
            marker.nearState, marker.highlighted = near, highlight
            local border = highlight and self.accentLight or marker.borderColor
            marker:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
            for _, layer in ipairs(marker.glowLayers or {}) do layer:SetShown(highlight) end
        end
        -- The nearest mechanic shows its countdown in the detail chip (unless the chip is off
        -- or the bar is too narrow).
        local showCountdown = style.showCountdown and not past
            and (not near or self.compact or not style.showMechanicDetail)
        if showCountdown then
            marker.countdown:SetText(FormatCountdown(remaining))
            marker.countdown:Show()
        else
            marker.countdown:Hide()
        end
    end
    marker:Show()
    return true
end

local function NumberField(value)
    if type(value) ~= "number" or (type(issecretvalue) == "function" and issecretvalue(value)) then
        return nil
    end
    return value
end

function TimelineUI:FindPhaseLabel(model, index)
    index = NumberField(index)
    if not index then return nil end
    for position, phase in ipairs(model and model.phases or {}) do
        if phase.index == index then return PhaseLabel(phase, position) end
    end
    return nil
end

-- [STYLE] Use either side of the icon only when the detail fits without covering other icons.
function TimelineUI:PlaceDetailChip(chip, marker, width, kind)
    local cooldown = kind == "cooldown"
    -- Beside the icon whatever its size (18 px rail icon -> 14, 32 px nearest mechanic -> 20);
    -- the rail chip stays centred on its icon.
    local offset = marker:GetWidth() * 0.5 + (cooldown and 5 or 4)
    local top = cooldown and -(8 + floor((marker:GetHeight() - chip:GetHeight()) * 0.5 + 0.5)) or -10
    local parent = cooldown and self.cooldownLayer or self.plot
    local markers = cooldown and self.cooldownMarkers or self.mechanicMarkers
    local chipWidth = chip:GetWidth()
    local function Fits(left)
        local right = left + chipWidth
        if left < width * FADE_SHARE or right > width * (1 - FADE_SHARE) then return false end
        for _, other in ipairs(markers) do
            if other ~= marker and other:IsShown()
                and left < other.x + other:GetWidth() * 0.5 + 2
                and right > other.x - other:GetWidth() * 0.5 - 2 then
                return false
            end
        end
        return true
    end

    chip:ClearAllPoints()
    if Fits(marker.x + offset) then
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", marker.x + offset, top)
    elseif Fits(marker.x - offset - chipWidth) then
        chip:SetPoint("TOPRIGHT", parent, "TOPLEFT", marker.x - offset, top)
    else
        chip:Hide()
        return false
    end
    chip:SetAlpha(EdgeAlpha(marker.x, width))
    chip:Show()
    return true
end

--- Detail chip for the single nearest upcoming mechanic: countdown + name, then
--- average damage, players hit and phase. Text is rebuilt only when the mechanic changes.
function TimelineUI:UpdateMechanicChip(marker, model, width)
    local chip = self.frame.mechanicChip
    if not chip then return end
    local style = self:GetTimelineStyle()
    if self.compact or not marker or not style.showMechanicDetail then
        chip:Hide()
        chip.data = nil
        return
    end

    local data = marker.data
    if chip.data ~= data or not chip.contentKey then
        chip.data = data
        chip.contentKey = true
        chip.name:SetText(ResolveLabel(data))
        local parts = {}
        local damage = NumberField(data.avgDamage)
        if damage then parts[#parts + 1] = ColorCode(self.colors.status.warning) .. FormatDamage(damage) .. "|r" end
        local players = NumberField(data.affectedPlayers)
        if players then parts[#parts + 1] = tostring(floor(players + 0.5)) .. "명 피격" end
        local phaseLabel = self:FindPhaseLabel(model, data.phase)
        if phaseLabel then parts[#parts + 1] = phaseLabel .. " 구간" end
        chip.info:SetText(table.concat(parts, " · "))
        chip.info:SetShown(#parts > 0)
        chip.hasInfo = #parts > 0
    end
    chip.number:SetText(FormatCountdown(marker.remaining))

    local firstLine = chip.number:GetStringWidth() + 4 + chip.name:GetStringWidth()
    local secondLine = chip.hasInfo and chip.info:GetStringWidth() or 0
    local chipWidth = ceil(max(firstLine, secondLine)) + 12
    chip:SetSize(chipWidth, chip.hasInfo and 35 or 21)

    if not self:PlaceDetailChip(chip, marker, width, "mechanic") and style.showCountdown then
        marker.countdown:SetText(FormatCountdown(marker.remaining))
        marker.countdown:Show()
    end
end

function TimelineUI:UpdateCooldownChip(marker, width)
    local chip = self.frame.cooldownChip
    if not chip then return end
    if self.compact or not marker or not self:GetTimelineStyle().showCooldownDetail then
        chip:Hide()
        return
    end

    chip.text:SetText(ResolveLabel(marker.data) .. " "
        .. ColorCode(self.colors.status.success) .. FormatCountdown(marker.remaining) .. "s|r")
    local chipWidth = ceil(chip.text:GetStringWidth()) + 12
    chip:SetWidth(chipWidth)

    self:PlaceDetailChip(chip, marker, width, "cooldown")
end

--- Earliest event still ahead within the given window (seconds).
local function NearestUpcoming(nearest, data, currentTime, window)
    local remaining = (data.t or 0) - currentTime
    if remaining > 0 and remaining <= window and (not nearest or (data.t or 0) < (nearest.t or 0)) then
        return data
    end
    return nearest
end

function TimelineUI:UpdateMechanics(model, currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = currentTime - past
    local rangeEnd = currentTime + future
    local visible = 0
    local nearest
    local mechanics = self:GetTimelineStyle().showMechanics and model.mechanics or {}

    -- [REFACTOR] BigWigs bars also track hidden sync anchors; only selected mechanics are drawn.
    for _, mechanic in ipairs(mechanics) do
        nearest = NearestUpcoming(nearest, mechanic, currentTime, MECHANIC_NEAR_WINDOW)
    end

    local nearestMarker
    local function Place(data)
        local eventTime = data.t or 0
        if eventTime < rangeStart or eventTime > rangeEnd then return end
        visible = visible + 1
        local marker = self:GetMarker(self.mechanicMarkers, visible, self.mechanicLayer, "mechanic")
        if self:ConfigureMarker(marker, data, currentTime, width, "mechanic", data == nearest)
            and data == nearest then
            nearestMarker = marker
        end
    end

    for _, mechanic in ipairs(mechanics) do
        Place(mechanic)
    end
    for index = visible + 1, #self.mechanicMarkers do
        self.mechanicMarkers[index]:Hide()
    end
    self:UpdateMechanicChip(nearestMarker, model, width)

    -- [STYLE] Keep phase lines/ribbons, but do not let their labels cover mechanic details.
    local detail = self.frame.mechanicChip
    for _, phase in ipairs(self.phaseMarkers) do
        if phase.chip:IsShown() then
            local left = phase.chip:GetLeft()
            local right = left + phase.chip:GetWidth()
            if detail:IsShown() and left < detail:GetLeft() + detail:GetWidth() + 2
                and right > detail:GetLeft() - 2 then
                phase.chip:Hide()
            else
                for _, marker in ipairs(self.mechanicMarkers) do
                    if marker:IsShown() and left < marker:GetLeft() + marker:GetWidth() + 2
                        and right > marker:GetLeft() - 2 then
                        phase.chip:Hide()
                        break
                    end
                end
            end
        end
    end
end

function TimelineUI:UpdateCooldowns(model, currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = currentTime - past
    local rangeEnd = currentTime + future
    local cooldowns = self:GetTimelineStyle().showCooldowns and ns.Engine:GetCooldowns() or {}
    local visible = 0
    local nearest, nearestMarker

    for _, cooldown in ipairs(cooldowns) do
        nearest = NearestUpcoming(nearest, cooldown, currentTime, COOLDOWN_NEAR_WINDOW)
    end

    for _, cooldown in ipairs(cooldowns) do
        local eventTime = cooldown.t or 0
        if eventTime >= rangeStart and eventTime <= rangeEnd then
            visible = visible + 1
            local marker = self:GetMarker(self.cooldownMarkers, visible, self.cooldownLayer, "cooldown")
            if self:ConfigureMarker(marker, cooldown, currentTime, width, "cooldown")
                and cooldown == nearest then
                nearestMarker = marker
            end
        end
    end

    for index = visible + 1, #self.cooldownMarkers do
        self.cooldownMarkers[index]:Hide()
    end
    self:UpdateCooldownChip(nearestMarker, width)
end

function TimelineUI:CollectUpcomingCooldowns(currentTime, window, maximumRows)
    if ns.db and ns.db.showUpcomingCooldowns == false then return {} end

    currentTime = tonumber(currentTime) or 0
    local style = self:GetAlertStyle()
    window = tonumber(window) or style.window
    maximumRows = tonumber(maximumRows) or style.maxRows
    local upcoming = {}

    for _, cooldown in ipairs(ns.Engine:GetCooldowns() or {}) do
        local eventTime = tonumber(cooldown.t)
        if eventTime then
            local remaining = eventTime - currentTime
            if remaining >= ALERT_EXIT_END and remaining <= window then
                upcoming[#upcoming + 1] = {
                    data = cooldown,
                    remaining = remaining,
                }
            end
        end
    end

    sort(upcoming, function(first, second)
        return first.remaining < second.remaining
    end)
    while #upcoming > maximumRows do
        upcoming[#upcoming] = nil
    end
    return upcoming
end

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

--- Short pop on the countdown number each time it ticks in the last COUNTDOWN_FROM seconds.
function TimelineUI:AnimateCountdown(row, now)
    local label = row.countdown
    if not label.SetTextScale then return end
    local started = row.popStarted
    local progress = started and (now - started) / COUNTDOWN_POP_TIME or 1
    if progress >= 1 then
        if row.popScale ~= 1 then
            row.popScale = 1
            label:SetTextScale(1)
        end
        return
    end
    local ease = 1 - progress
    row.popScale = min(1 + 0.4 * ease * ease, row.popLimit or 1.4)
    label:SetTextScale(row.popScale)
end

-- [STYLE] The approved reminder motion shares the existing pop toggle and the frame update.
function TimelineUI:AnimateUpcomingRow(row, now, style)
    if not row.data then return end
    local motion = self.styleLib.Motion
    local remaining = row.remaining - min(UPDATE_INTERVAL, max(0, now - row.updatedAt))
    local enabled = style.pop
    local urgent = enabled and remaining <= COUNTDOWN_FROM
    local isNow = remaining <= 0
    local x, exitY, alpha = 0, 0, 1
    if enabled and not row.motionStatic then
        local entered = motion.EaseOutQuad(motion.Clamp01((now - row.enterStarted) / ALERT_ENTER_TIME))
        alpha, x = entered, -10 * (1 - entered)
        if row.slideStarted then
            local progress = motion.Clamp01((now - row.slideStarted) / ALERT_SLIDE_TIME)
            row.motionY = motion.Lerp(row.slideFrom, row.targetY, motion.EaseOutQuad(progress))
            if progress == 1 then row.slideStarted = nil end
        end
        if remaining < ALERT_EXIT_START then
            local progress = motion.Clamp01((ALERT_EXIT_START - remaining) / (ALERT_EXIT_START - ALERT_EXIT_END))
            alpha = alpha * (1 - progress)
            exitY = 6 * motion.EaseOutQuad(progress)
        end
    else
        row.motionY, row.slideStarted = row.targetY, nil
        if not enabled then row.popStarted, row.nowStarted = nil, nil end
    end
    self:PositionUpcomingRow(row, x, row.motionY + exitY)
    row:SetAlpha(alpha)
    local tint = urgent and (isNow and 0.55 or 0.45) or 0
    row.tint:SetAlpha(tint)
    row.tint2:SetAlpha(tint)
    local flash = enabled and not row.motionStatic and row.nowStarted
        and (1 - motion.Clamp01((now - row.nowStarted) / ALERT_FLASH_TIME)) ^ 2 or 0
    row.flash:SetAlpha(flash)
    row.flash2:SetAlpha(flash)
    row.drain:SetWidth(max(0.5, (row:GetWidth() - 4) * motion.Clamp01(remaining / COUNTDOWN_FROM)))
    row.drain:SetShown(urgent and not isNow)
    local pulse = 0.5 + 0.5 * sin((now - row.enterStarted) * 2 * math.pi / 1.2)
    for _, layer in ipairs(row.glowLayers) do
        layer:SetShown(urgent and style.showIcon)
        layer:SetAlpha(isNow and 0.9 or 0.3 + 0.45 * pulse)
    end
    self:AnimateCountdown(row, now)
end

function TimelineUI:ResetUpcomingMotion()
    for _, row in ipairs(self.upcomingRows or {}) do
        row.data = nil
        row:Hide()
    end
    if self.upcomingPanel then self.upcomingPanel:Hide() end
end

function TimelineUI:ShouldPlayCountdownVoice()
    return not ns.db or ns.db.countdownVoice ~= false
end

function TimelineUI:GetCountdownVoicePack()
    local pack = ns.db and ns.db.countdownVoicePack
    return type(pack) == "string" and COUNTDOWN_SOUNDS[pack] and pack or "ja"
end

function TimelineUI:PlayCountdownVoice(number)
    if type(PlaySoundFile) ~= "function" then return false end
    -- [STYLE] A resync can advance two counts before the previous sound finishes.
    if self.countdownSoundHandle and type(StopSound) == "function" then
        StopSound(self.countdownSoundHandle)
    end
    -- "Master" so the count is heard even when game sound effects are muted (as NSRT does).
    local filename = COUNTDOWN_SOUNDS[self:GetCountdownVoicePack()]:format(number)
    local played, handle = PlaySoundFile("Interface\\AddOns\\DDingUI_RaidHelper\\Media\\Sounds\\" .. filename, "Master")
    self.countdownSoundHandle = played and handle or nil
    return played and true or false
end

--- Settings "미리 듣기": the full 셋 · 둘 · 하나 one second apart, outside the encounter logic.
function TimelineUI:PreviewCountdownVoice()
    local token = (self.countdownPreviewToken or 0) + 1
    self.countdownPreviewToken = token
    for number = COUNTDOWN_FROM, 1, -1 do
        local delay = COUNTDOWN_FROM - number
        if delay == 0 or not (C_Timer and C_Timer.After) then
            self:PlayCountdownVoice(number)
        else
            C_Timer.After(delay, function()
                if TimelineUI.countdownPreviewToken == token then
                    TimelineUI:PlayCountdownVoice(number)
                end
            end)
        end
    end
end

function TimelineUI:ResetCountdownVoice()
    self.countdownSpoken = {}
    self.countdownPreviewToken = (self.countdownPreviewToken or 0) + 1
end

--- Speaks 셋 · 둘 · 하나 for the nearest upcoming cooldown only, once per number, so two
--- close cooldowns never talk over each other. A late jump from a BigWigs resync skips
--- numbers it has already passed instead of speaking them late.
function TimelineUI:UpdateCountdownVoice(upcoming)
    if self:IsPreviewMode() or not self:ShouldPlayCountdownVoice() then return end

    local nearest
    for _, entry in ipairs(upcoming) do
        if entry.remaining > 0 then
            nearest = entry
            break
        end
    end
    if not nearest then return end

    self.countdownSpoken = self.countdownSpoken or {}
    for number = COUNTDOWN_FROM, 1, -1 do
        if nearest.remaining <= number and nearest.remaining > number - COUNTDOWN_VOICE_SLACK then
            local last = self.countdownSpoken[nearest.data]
            if not last or last > number then
                self.countdownSpoken[nearest.data] = number
                self:PlayCountdownVoice(number)
            end
            return
        end
    end
end

function TimelineUI:UpdateUpcomingCooldowns(currentTime)
    if not self.upcomingPanel then return end

    local upcoming = self:CollectUpcomingCooldowns(currentTime)
    local now = Now()
    local style = self:GetAlertStyle()

    -- [STYLE] Keep each spell's frame through reordering, so survivors slide instead of re-entering.
    local rows, ordered, used = self.upcomingRows, {}, {}
    for index, entry in ipairs(upcoming) do
        for _, row in ipairs(rows) do
            if row.data == entry.data then
                ordered[index], used[row] = row, true
                break
            end
        end
    end
    for index, entry in ipairs(upcoming) do
        local row = ordered[index]
        if not row then
            for _, candidate in ipairs(rows) do
                if not used[candidate] then row = candidate; break end
            end
            row = row or self:CreateUpcomingRow(#rows + 1)
            ordered[index], used[row] = row, true
            local step = (AlertRowHeight(style) + style.spacing) * (style.grow == "UP" and 1 or -1)
            row.motionY = index > 1 and ordered[index - 1].motionY + step or 0
            row.data, row.targetY = nil, nil
        end
        if row.index ~= index or row.targetY == nil or row.layoutVersion ~= self.alertLayoutVersion then
            self:LayoutUpcomingRow(row, index, style)
        end
        self:FillUpcomingRow(row, entry.data, entry.remaining, now, style)
    end
    for _, row in ipairs(rows) do
        if not used[row] then
            row.data = nil
            row:Hide()
            ordered[#ordered + 1] = row
        end
    end
    self.upcomingRows = ordered

    if self.upcomingPanel.moverStyle then
        self.upcomingPanel.moverStyle.label:SetShown(#upcoming == 0)
    end
    -- Fixed box for the chosen line count, so the alert keeps one size as an edit module.
    if #upcoming > 0 or self.editSession then
        self.upcomingPanel:Show()
    else
        self.upcomingPanel:Hide()
    end
    self:UpdateCountdownVoice(upcoming)
end

function TimelineUI:ShowMarkerTooltip(marker)
    local data = marker.data
    if not data then return end

    local colors = self.colors
    GameTooltip:SetOwner(marker, "ANCHOR_TOP")
    GameTooltip:SetText(ResolveLabel(data), colors.text.highlight[1], colors.text.highlight[2], colors.text.highlight[3])
    GameTooltip:AddDoubleLine("기준 시각", FormatTime(data.t), colors.text.dim[1], colors.text.dim[2], colors.text.dim[3], colors.text.highlight[1], colors.text.highlight[2], colors.text.highlight[3])

    if data.avgDamage then
        GameTooltip:AddDoubleLine("평균 피해", FormatDamage(data.avgDamage), colors.text.dim[1], colors.text.dim[2], colors.text.dim[3], colors.status.error[1], colors.status.error[2], colors.status.error[3])
    end
    if data.affectedPlayers then
        GameTooltip:AddDoubleLine("평균 피격 인원", tostring(data.affectedPlayers), colors.text.dim[1], colors.text.dim[2], colors.text.dim[3], colors.text.highlight[1], colors.text.highlight[2], colors.text.highlight[3])
    end
    if data.usage then
        GameTooltip:AddDoubleLine("상위 로그 사용률", string.format("%.0f%%", data.usage * 100), colors.text.dim[1], colors.text.dim[2], colors.text.dim[3], colors.status.success[1], colors.status.success[2], colors.status.success[3])
    end
    if data.spread then
        GameTooltip:AddDoubleLine("시점 오차 범위", string.format("±%.1f초", data.spread), colors.text.dim[1], colors.text.dim[2], colors.text.dim[3], colors.text.highlight[1], colors.text.highlight[2], colors.text.highlight[3])
    end
    if data.source then
        GameTooltip:AddDoubleLine("동기화", tostring(data.source), colors.text.dim[1], colors.text.dim[2], colors.text.dim[3], colors.text.highlight[1], colors.text.highlight[2], colors.text.highlight[3])
    end
    GameTooltip:Show()
end

function TimelineUI:UpdateView()
    local model = ns.Engine:GetModel()
    if not model then return end

    local frame = self.frame
    local currentTime = ns.Engine:GetTimelineTime()
    local width = max(1, self.plot:GetWidth())
    local height = max(1, self.plot:GetHeight())
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local playheadX = (past / (past + future)) * width
    local phase = ns.Engine:GetPhaseAt(currentTime)

    -- Playhead runs 4 px past the bar on both sides, with a soft accent halo behind it.
    for _, texture in ipairs({ frame.playheadGlow, frame.playhead }) do
        texture:ClearAllPoints()
        texture:SetPoint("TOP", self.plot, "TOPLEFT", playheadX, 4)
        texture:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", playheadX, -4)
    end
    frame.pastShade:SetWidth(max(0.5, playheadX))

    frame.timeReadout:SetText(FormatTime(currentTime) .. (phase and (" · " .. PhaseLabel(phase)) or ""))
    if self:IsPreviewMode() and not self.compact then
        frame.syncText:SetText(self:IsEditSessionActive()
            and "편집 중 · 드래그·방향키로 위치 조정 · Esc로 종료"
            or "미리보기 · 견본 전투 재생 중")
        frame.syncText:Show()
    else
        frame.syncText:Hide()
    end

    self:UpdateGrid(currentTime, width)
    self:UpdatePhases(model, currentTime, width, phase)
    self:UpdateDamage(model, currentTime, width, height)
    self:UpdateMechanics(model, currentTime, width)
    self:UpdateCooldowns(model, currentTime, width)
    self:UpdateUpcomingCooldowns(currentTime)
end

function TimelineUI:OnUpdate(elapsed)
    if not ns.Engine:IsRunning() then return end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= (self.updateInterval or UPDATE_INTERVAL) then
        local step = self.elapsed
        self.elapsed = 0
        ns.Engine:Tick(step)
        self:UpdateView()
    end
    local now, style = Now(), self:GetAlertStyle()
    for _, row in ipairs(self.upcomingRows) do
        if row:IsShown() then self:AnimateUpcomingRow(row, now, style) end
    end
end

--- 0.25 s fade-in on START; any pending end-of-fight fade-out is cancelled.
function TimelineUI:ShowAnimated()
    local frame = self.frame
    self.stopToken = (self.stopToken or 0) + 1
    frame.endText:Hide()
    local styleLib = self.styleLib
    if styleLib.FadeIn and frame.CreateAnimationGroup then
        styleLib.FadeIn(frame, 0.25, 0, 1)
    else
        frame:SetAlpha(1)
        frame:Show()
    end
end

--- End text fades in, then after 3 s the whole bar fades out over 0.4 s and hides.
function TimelineUI:FinishAnimated(success)
    local frame = self.frame
    local styleLib = self.styleLib
    local token = (self.stopToken or 0) + 1
    self.stopToken = token

    frame.noDataText:Hide()
    frame.endText:SetText(success and "전투 종료 · 처치" or "전투 종료")
    if styleLib.FadeIn and frame.endText.CreateAnimationGroup then
        styleLib.FadeIn(frame.endText, 0.2, 0, 1)
    else
        frame.endText:SetAlpha(1)
        frame.endText:Show()
    end

    C_Timer.After(3, function()
        if TimelineUI.stopToken ~= token or ns.Engine:IsRunning() then return end
        local function Finish()
            if TimelineUI.stopToken ~= token or ns.Engine:IsRunning() then return end
            frame:Hide()
            frame:SetAlpha(1)
            frame.endText:Hide()
        end
        if styleLib.FadeOut and frame.CreateAnimationGroup then
            styleLib.FadeOut(frame, 0.4, nil, 0, false, Finish)
        else
            Finish()
        end
    end)
end

function TimelineUI:OnEngineEvent(event, ...)
    if not self.initialized then return end

    if event == "START" then
        local engineOptions = ns.Engine.options or {}
        local isPreview = engineOptions.previewMode == true or engineOptions.editMode == true
        self.previewMode = isPreview
        self.editMode = engineOptions.editMode == true
        if not self.editMode then self:EndEditSession(false) end
        self:ResetCountdownVoice()
        self:ResetUpcomingMotion()
        self:RefreshPreviewControl()
        self:ShowAnimated()
        self:UpdateEditHUD()
        self:UpdateView()
    elseif event == "STOP" then
        self:ResetUpcomingMotion()
        local options = ns.Engine.options or {}
        local wasPreview = self:IsPreviewMode() or options.previewMode or options.editMode
        self.previewMode = false
        self.editMode = false
        self:EndEditSession(false)
        self:RefreshPreviewControl()
        self:UpdateEditHUD()
        if wasPreview then self.frame:Hide(); return end
        local success = ...
        self:FinishAnimated(success)
    elseif event == "LOOP" or event == "SYNC" or event == "SPECIALIZATION" then
        if event == "LOOP" then
            self:ResetCountdownVoice()
            self:ResetUpcomingMotion()
        end
        self:UpdateView()
    end
end
