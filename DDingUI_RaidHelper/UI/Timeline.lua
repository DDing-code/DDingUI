local _, ns = ...

local TimelineUI = {}
ns.TimelineUI = TimelineUI

local abs = math.abs
local ceil = math.ceil
local floor = math.floor
local max = math.max
local min = math.min
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
local PAST_ALPHA = 0.38
local UPDATE_INTERVAL = 0.05
local UPCOMING_WINDOW = 12
local UPCOMING_MAX_ROWS = 3
local UPCOMING_ROW_HEIGHT = 24
local UPCOMING_ROW_GAP = 2
local UPCOMING_PANEL_MAX_WIDTH = 320
local FALLBACK_ICON = 134400
local BRAND_ICON = "Interface\\AddOns\\DDingUI_RaidHelper\\Media\\RaidHelper_Icon.tga"
local ADDON_KEY = "RaidHelper"
local EDIT_FRAME_NAME = "공격대 타임라인"
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
    if not IsSecret(icon) and icon then return icon end

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

function TimelineUI:CreateLabel(parent, category, color, layer)
    local size = category == "title" and self.titleFontSize
        or category == "small" and self.smallFontSize
        or self.normalFontSize
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
    local size = kind == "cooldown" and COOLDOWN_SIZE or MECHANIC_SIZE
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

function TimelineUI:CreateUpcomingRow(index)
    local row = self.upcomingRows[index]
    if row then return row end

    local colors = self.colors
    row = CreateFrame("Frame", nil, self.upcomingPanel, "BackdropTemplate")
    row:SetHeight(UPCOMING_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.upcomingPanel, "TOPLEFT", 0, -((index - 1) * (UPCOMING_ROW_HEIGHT + UPCOMING_ROW_GAP)))
    row:SetPoint("TOPRIGHT", self.upcomingPanel, "TOPRIGHT", 0, -((index - 1) * (UPCOMING_ROW_HEIGHT + UPCOMING_ROW_GAP)))
    local background = colors.bg.input
    ApplyBackdrop(row, self.flatTexture, {
        background[1], background[2], background[3], (background[4] or 1) * self:GetBackgroundAlpha(),
    }, colors.border.default)

    row.fill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    row.fill:SetWidth(1)
    SetTextureColor(row.fill, self.accentFrom, 0.18)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.countdown = self:CreateLabel(row, "normal", colors.text.highlight)
    row.countdown:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    row.countdown:SetWidth(42)
    row.countdown:SetJustifyH("RIGHT")

    row.label = self:CreateLabel(row, "normal", colors.text.highlight)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row.countdown, "LEFT", -6, 0)
    row.label:SetJustifyH("LEFT")

    row:Hide()
    self.upcomingRows[index] = row
    return row
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

    frame.upcomingPanel = CreateFrame("Frame", nil, frame)
    frame.upcomingPanel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -6)
    frame.upcomingPanel:SetSize(
        UPCOMING_PANEL_MAX_WIDTH,
        UPCOMING_MAX_ROWS * UPCOMING_ROW_HEIGHT + (UPCOMING_MAX_ROWS - 1) * UPCOMING_ROW_GAP
    )
    frame.upcomingPanel:Hide()

    frame:SetScript("OnDragStart", function(currentFrame)
        if (ns.db.locked and not TimelineUI:IsPreviewMode()) or InCombatLockdown() then return end
        currentFrame:StartMoving()
        currentFrame._editDragging = TimelineUI:IsPreviewMode()
        TimelineUI:UpdateEditHUD()
    end)
    frame:SetScript("OnDragStop", function(currentFrame)
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

-- [STYLE] C5/C12: the frame rectangle in UIParent units (the timeline has its own scale).
function TimelineUI:GetFrameRect()
    local frame = self.frame
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

--- Snap delta (UIParent units) for the frame rectangle: center, then screen edges, then grid.
function TimelineUI:GetSnapDelta(left, bottom, width, height)
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
    -- RaidHelper has one movable frame, so "프레임" snaps to the screen edges and center.
    if snap.frames and not (snappedX and snappedY) then
        local rectX, rectY = styleLib.SnapToRects({ left, bottom, width, height }, {
            { 0, 0, screenWidth, screenHeight },
        })
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

--- Anchor-relative offset of the current frame position in the saved anchor model.
--- While dragging this is computed from the live rectangle so the HUD matches the value saved on drop.
function TimelineUI:GetAnchorOffset(withSnap)
    local position = ns.db.position
    if not (self.frame and self.frame._editDragging) and not withSnap then
        return position.x or 0, position.y or 0
    end

    local left, bottom, width, height, relative = self:GetFrameRect()
    if not left then return position.x or 0, position.y or 0 end
    if withSnap then
        local dx, dy = self:GetSnapDelta(left, bottom, width, height)
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

    local shown = self:IsPreviewMode()
    frame.editHUD:SetShown(shown)

    -- [STYLE] StyleMover is not applied here: this overlay is the live combat window itself,
    -- so the accent edit outline lives on its (otherwise invisible) backdrop.
    self:ApplyEditOutline()
    if shown then
        local x, y = self:GetAnchorOffset(false)
        local width, height = frame:GetSize()
        frame.editHUD:Update(x, y, width, height)
        if frame._editDragging and self.editGuides then
            local left, bottom, rectWidth, rectHeight = self:GetFrameRect()
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
        ApplyBackdrop(row, self.flatTexture, {
            input[1], input[2], input[3], (input[4] or 1) * alpha,
        }, self.colors.border.default)
    end
    self:ApplyEditOutline()
    return true
end

--- Accent outline only while preview/edit is active; otherwise the frame has no edge at all.
function TimelineUI:ApplyEditOutline()
    local frame = self.frame
    if not frame then return end
    if self:IsPreviewMode() then
        local accent = self.accentFrom
        frame:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function TimelineUI:ApplyDisplaySettings()
    if not self.frame then return false end

    local width = self:GetTimelineWidth()
    local height = self:GetTimelineHeight()
    local fade = floor(width * FADE_SHARE + 0.5)
    self.frame:SetSize(width, height)
    self.plot:SetHeight(height - RAIL_HEIGHT)
    if self.upcomingPanel then
        self.upcomingPanel:SetWidth(min(UPCOMING_PANEL_MAX_WIDTH, max(200, floor(width * 0.58))))
    end

    self.compact = width < COMPACT_WIDTH
    local timeReadout = self.frame.timeReadout
    if timeReadout then
        timeReadout:ClearAllPoints()
        timeReadout:SetPoint("BOTTOMLEFT", self.plot, "TOPLEFT", fade, 3)
        timeReadout:SetShown(not self.compact)
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

function TimelineUI:RefreshMedia()
    local styleLib = self.styleLib
    self.fontPath = styleLib.GetFont and styleLib:GetFont("primary") or styleLib.Font.path
    self.titleFontSize = styleLib.GetFontSize and styleLib:GetFontSize("title") or styleLib.Font.title
    self.normalFontSize = styleLib.GetFontSize and styleLib:GetFontSize("normal") or styleLib.Font.normal
    self.smallFontSize = styleLib.GetFontSize and styleLib:GetFontSize("small") or styleLib.Font.small
    self.flatTexture = styleLib.GetTexture and styleLib:GetTexture("flat") or "Interface\Buttons\WHITE8x8"

    for _, label in ipairs(self.fontStrings or {}) do
        local category = label._raidHelperFontCategory
        local size = category == "title" and self.titleFontSize
            or category == "small" and self.smallFontSize
            or self.normalFontSize
        label:SetFont(self.fontPath, size, "OUTLINE")
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
    self:UpdateEditHUD()
end

function TimelineUI:SavePosition()
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    ns.db.position.point = point or "CENTER"
    ns.db.position.relativePoint = relativePoint or "CENTER"
    ns.db.position.x = floor((x or 0) + 0.5)
    ns.db.position.y = floor((y or 0) + 0.5)
    self:UpdateEditHUD()
end

function TimelineUI:ResetPosition()
    self:PushEditHistory()
    ns.db.position = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -180,
    }
    self:ApplyPosition()
end

------------------------------------------------------------------------
-- [STYLE] C12 edit mode: StyleLib 1.4 remote, grid, guides, snap, history.
-- The saved model stays ns.db.position = {point, relativePoint, x, y}.
------------------------------------------------------------------------
local function CopyPosition(position)
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

function TimelineUI:PushEditHistory()
    if not self.editSession or not ns.db or not ns.db.position then return end
    local undo = self.editUndo
    undo[#undo + 1] = CopyPosition(ns.db.position)
    if #undo > EDIT_HISTORY_LIMIT then table.remove(undo, 1) end
    self.editRedo = {}
end

function TimelineUI:SetStoredPosition(position)
    local stored = ns.db.position
    stored.point = position.point or "CENTER"
    stored.relativePoint = position.relativePoint or "CENTER"
    stored.x = floor((tonumber(position.x) or 0) + 0.5)
    stored.y = floor((tonumber(position.y) or 0) + 0.5)
    self:ApplyPosition()
end

function TimelineUI:NudgePosition(dx, dy)
    if not self.editSession then return false end
    local position = ns.db.position
    self:PushEditHistory()
    self:SetStoredPosition({
        point = position.point,
        relativePoint = position.relativePoint,
        x = (position.x or 0) + (tonumber(dx) or 0),
        y = (position.y or 0) + (tonumber(dy) or 0),
    })
    return true
end

function TimelineUI:SetPositionOffset(x, y)
    if not self.editSession then return false end
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then return false end
    local position = ns.db.position
    self:PushEditHistory()
    self:SetStoredPosition({
        point = position.point,
        relativePoint = position.relativePoint,
        x = x,
        y = y,
    })
    return true
end

function TimelineUI:UndoPosition()
    local undo = self.editUndo
    if not self.editSession or not undo or #undo == 0 then return false end
    local previous = table.remove(undo)
    self.editRedo[#self.editRedo + 1] = CopyPosition(ns.db.position)
    self:SetStoredPosition(previous)
    return true
end

function TimelineUI:RedoPosition()
    local redo = self.editRedo
    if not self.editSession or not redo or #redo == 0 then return false end
    local nextPosition = table.remove(redo)
    self.editUndo[#self.editUndo + 1] = CopyPosition(ns.db.position)
    self:SetStoredPosition(nextPosition)
    return true
end

--- Drag end: inside an edit session the drop is snapped and written back in the saved anchor model.
function TimelineUI:FinishDrag()
    local frame = self.frame
    if not frame then return end
    local wasEditing = frame._editDragging
    frame._editDragging = false
    if self.editGuides then self.editGuides:Hide() end

    if wasEditing and self.editSession and ns.db.position then
        local x, y = self:GetAnchorOffset(true)
        local position = ns.db.position
        self:PushEditHistory()
        self:SetStoredPosition({
            point = position.point,
            relativePoint = position.relativePoint,
            x = x,
            y = y,
        })
        return
    end
    self:SavePosition()
end

function TimelineUI:RefreshEditSelection(x, y)
    local remote = self.editRemote
    if not (remote and self.editSession and self.frame) then return end
    local position = ns.db.position
    local width, height = self.frame:GetSize()
    remote:SetSelection({
        name = EDIT_FRAME_NAME,
        anchor = "UIParent · " .. tostring(position.point or "CENTER"),
        x = x or position.x or 0,
        y = y or position.y or 0,
        w = width,
        h = height,
    })
    remote:SetUndoState(#(self.editUndo or {}) > 0, #(self.editRedo or {}) > 0)
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
        onNudge = function(dx, dy) TimelineUI:NudgePosition(dx, dy) end,
        onApplyXY = function(x, y) TimelineUI:SetPositionOffset(x, y) end,
        onReset = function() TimelineUI:ResetPosition() end,
        onUndo = function() TimelineUI:UndoPosition() end,
        onRedo = function() TimelineUI:RedoPosition() end,
        onDone = function() TimelineUI:SetPreviewMode(false) end,
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
    return self.editRemote ~= nil
end

function TimelineUI:BeginEditSession()
    if self.editSession then return end
    self.editSession = true
    self.editUndo, self.editRedo = {}, {}

    -- C12: entering edit mode closes the settings window; leaving reopens it (only if it was open).
    local options = ns.Options
    local optionsFrame = options and options.frame
    self.reopenOptions = optionsFrame and optionsFrame:IsShown() and not optionsFrame._ddslPanelClosing and true or false
    if self.reopenOptions and options.Close then options:Close() end

    if self:EnsureEditTools() then
        if self.editRemote.SetGridState then
            self.editRemote:SetGridState(self.editGridEnabled, self.editGridSpacing)
        end
        if self.editGridEnabled then self.editGrid:ShowAnimated() end
        self.editRemote:EnableKeyboard(true)
        self.editRemote:Show()
    end
    self:UpdateEditHUD()
end

function TimelineUI:EndEditSession(reopenOptions)
    if not self.editSession then return end
    local frame = self.frame
    if frame and frame._editDragging then
        frame:StopMovingOrSizing()
        self:FinishDrag()
    end
    self.editSession = false

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
    if ns.Options and ns.Options.RefreshPreviewButton then
        ns.Options:RefreshPreviewButton()
    end
end

--- opts.noReopen: leave the settings window closed (combat / encounter start).
function TimelineUI:SetPreviewMode(enabled, opts)
    enabled = enabled == true
    if enabled == self:IsPreviewMode() then
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

        self.previewMode = true
        -- Compatibility for saved integrations and older slash-command paths.
        self.editMode = true
        ns.Engine:StartModel(model, {
            demo = true,
            loop = true,
            previewMode = true,
            editMode = true,
        })
        if self.frame then self.frame:Show() end
        self:BeginEditSession()
        self:UpdateEditHUD()
        self:RefreshPreviewControl()
        ns:Print("미리보기: 드래그·방향키·편집 리모컨으로 위치를 조정합니다. Esc 또는 완료로 종료합니다.")
        return true
    end

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
    ns:Print("미리보기를 종료하고 위치를 저장했습니다.")
    return true
end

function TimelineUI:TogglePreviewMode()
    return self:SetPreviewMode(not self:IsPreviewMode())
end

-- Backward-compatible API aliases. Preview now includes position editing.
function TimelineUI:SetEditMode(enabled)
    return self:SetPreviewMode(enabled)
end

function TimelineUI:ToggleEditMode()
    return self:TogglePreviewMode()
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
    while tick <= finalTick do
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
    local phases = model.phases or {}
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
    local damage = model.damage or {}
    local values = damage.values or {}
    local interval = damage.interval or 0.5
    local maximum = max(1, damage.max or 1)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = max(0, currentTime - past - interval)
    local rangeEnd = currentTime + future + interval
    local firstIndex = max(1, floor(rangeStart / interval) + 1)
    local finalIndex = min(#values - 1, ceil(rangeEnd / interval) + 1)
    -- [STYLE] C안: the ridge lies on the bar floor and stays below the icon row.
    local amplitude = max(8, height - RIDGE_TOP_SPACE)
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
    self.frame.noDataText:SetShown(#values == 0)
end

--- Places one icon. Nothing is clamped into the bar: icons slide out through the edge fade.
--- Returns false when the icon is fully faded out and therefore hidden.
function TimelineUI:ConfigureMarker(marker, data, currentTime, width, kind, near)
    local x = self:MapTimeToX(data.t or 0, currentTime, width)
    local edge = EdgeAlpha(x, width)
    if edge <= 0 then
        marker:Hide()
        return false
    end

    local remaining = (data.t or 0) - currentTime
    local past = remaining < 0
    marker.data = data
    marker.x = x
    marker.remaining = remaining
    marker.icon:SetTexture(ResolveIcon(data))
    if marker.icon.SetDesaturated then marker.icon:SetDesaturated(past) end
    marker:SetAlpha((past and PAST_ALPHA or 1) * edge)
    marker:ClearAllPoints()

    if kind == "cooldown" then
        marker:SetPoint("TOP", marker:GetParent(), "TOPLEFT", x, -8)
        if type(data.spread) == "number" and data.spread > 0 then
            local secondsWidth = width / (max(1, ns.db.windowPast or 12) + max(1, ns.db.windowFuture or 38))
            local desiredWidth = max(COOLDOWN_SIZE, data.spread * 2 * secondsWidth)
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
        local size = near and MECHANIC_NEAR_SIZE or MECHANIC_SIZE
        marker:SetSize(size, size)
        marker:SetPoint("TOP", marker:GetParent(), "TOPLEFT", x, near and -8 or -10)
        if marker.nearState ~= near then
            marker.nearState = near
            local border = near and self.accentLight or marker.borderColor
            marker:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
            for _, layer in ipairs(marker.glowLayers or {}) do layer:SetShown(near) end
        end
        -- The nearest mechanic shows its countdown in the detail chip (unless the bar is too narrow).
        local showCountdown = not past and (not near or self.compact)
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

--- Detail chip for the single nearest upcoming mechanic: countdown + name, then
--- average damage, players hit and phase. Text is rebuilt only when the mechanic changes.
function TimelineUI:UpdateMechanicChip(marker, model, width)
    local chip = self.frame.mechanicChip
    if not chip then return end
    if self.compact or not marker then
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

    local x = marker.x
    chip:ClearAllPoints()
    if x + 20 + chipWidth > width * (1 - FADE_SHARE) then
        chip:SetPoint("TOPRIGHT", self.plot, "TOPLEFT", x - 20, -10)
    else
        chip:SetPoint("TOPLEFT", self.plot, "TOPLEFT", x + 20, -10)
    end
    chip:SetAlpha(EdgeAlpha(x, width))
    chip:Show()
end

function TimelineUI:UpdateCooldownChip(marker, width)
    local chip = self.frame.cooldownChip
    if not chip then return end
    if self.compact or not marker then
        chip:Hide()
        return
    end

    chip.text:SetText(ResolveLabel(marker.data) .. " "
        .. ColorCode(self.colors.status.success) .. FormatCountdown(marker.remaining) .. "s|r")
    local chipWidth = ceil(chip.text:GetStringWidth()) + 12
    chip:SetWidth(chipWidth)

    local x = marker.x
    chip:ClearAllPoints()
    if x + 14 + chipWidth > width * (1 - FADE_SHARE) then
        chip:SetPoint("TOPRIGHT", self.cooldownLayer, "TOPLEFT", x - 14, -8)
    else
        chip:SetPoint("TOPLEFT", self.cooldownLayer, "TOPLEFT", x + 14, -8)
    end
    chip:SetAlpha(EdgeAlpha(x, width))
    chip:Show()
end

--- Earliest event still ahead within the given window (seconds).
local function NearestUpcoming(nearest, data, currentTime, window)
    local remaining = (data.t or 0) - currentTime
    if remaining > 0 and remaining <= window and (not nearest or (data.t or 0) < (nearest.t or 0)) then
        return data
    end
    return nearest
end

local function IsDrawnLiveMechanic(liveMechanic)
    return not liveMechanic.matched or liveMechanic.matched.syncOnly
end

function TimelineUI:UpdateMechanics(model, currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = currentTime - past
    local rangeEnd = currentTime + future
    local liveMechanics = ns.Engine:GetLiveMechanics()
    local visible = 0
    local nearest

    for _, mechanic in ipairs(model.mechanics or {}) do
        nearest = NearestUpcoming(nearest, mechanic, currentTime, MECHANIC_NEAR_WINDOW)
    end
    for _, liveMechanic in pairs(liveMechanics) do
        if IsDrawnLiveMechanic(liveMechanic) then
            nearest = NearestUpcoming(nearest, liveMechanic, currentTime, MECHANIC_NEAR_WINDOW)
        end
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

    for _, mechanic in ipairs(model.mechanics or {}) do
        Place(mechanic)
    end
    for _, liveMechanic in pairs(liveMechanics) do
        if IsDrawnLiveMechanic(liveMechanic) then Place(liveMechanic) end
    end

    for index = visible + 1, #self.mechanicMarkers do
        self.mechanicMarkers[index]:Hide()
    end
    self:UpdateMechanicChip(nearestMarker, model, width)
end

function TimelineUI:UpdateCooldowns(model, currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = currentTime - past
    local rangeEnd = currentTime + future
    local cooldowns = ns.Engine:GetCooldowns()
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
    window = tonumber(window) or UPCOMING_WINDOW
    maximumRows = tonumber(maximumRows) or UPCOMING_MAX_ROWS
    local upcoming = {}

    for _, cooldown in ipairs(ns.Engine:GetCooldowns() or {}) do
        local eventTime = tonumber(cooldown.t)
        if eventTime then
            local remaining = eventTime - currentTime
            if remaining >= -0.75 and remaining <= window then
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

function TimelineUI:UpdateUpcomingCooldowns(currentTime)
    if not self.upcomingPanel then return end

    local upcoming = self:CollectUpcomingCooldowns(currentTime)
    local panelWidth = max(1, self.upcomingPanel:GetWidth())
    local alpha = self:GetBackgroundAlpha()

    for index, entry in ipairs(upcoming) do
        local row = self:CreateUpcomingRow(index)
        local remaining = entry.remaining
        local urgent = remaining <= 3
        local color = urgent and self.colors.status.warning or self.accentFrom
        local progress = min(1, max(0, remaining / UPCOMING_WINDOW))

        row.data = entry.data
        row.icon:SetTexture(ResolveIcon(entry.data))
        row.label:SetText(ResolveLabel(entry.data))
        row.countdown:SetText(remaining <= 0.75 and "지금" or tostring(ceil(remaining)))
        SetTextColor(row.countdown, color)
        row.fill:SetWidth(max(1, (panelWidth - 2) * progress))
        SetTextureColor(row.fill, color, (urgent and 0.28 or 0.18) * alpha)
        row:SetBackdropBorderColor(color[1], color[2], color[3], urgent and 0.72 or 0.34)
        row:Show()
    end

    for index = #upcoming + 1, #self.upcomingRows do
        self.upcomingRows[index]:Hide()
    end

    if #upcoming > 0 then
        self.upcomingPanel:SetHeight(
            #upcoming * UPCOMING_ROW_HEIGHT + max(0, #upcoming - 1) * UPCOMING_ROW_GAP
        )
        self.upcomingPanel:Show()
    else
        self.upcomingPanel:Hide()
    end
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
        frame.syncText:SetText("PREVIEW · 드래그·방향키로 위치 조정 · Esc로 종료")
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
    if self.elapsed < (self.updateInterval or UPDATE_INTERVAL) then return end

    local step = self.elapsed
    self.elapsed = 0
    ns.Engine:Tick(step)
    self:UpdateView()
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
        self.editMode = isPreview
        if not isPreview then self:EndEditSession(false) end
        self:RefreshPreviewControl()
        self:ShowAnimated()
        self:UpdateEditHUD()
        self:UpdateView()
    elseif event == "STOP" then
        if self:IsPreviewMode() then
            self.previewMode = false
            self.editMode = false
            self:RefreshPreviewControl()
            self:UpdateEditHUD()
        end
        self:EndEditSession(false)
        local success = ...
        self:FinishAnimated(success)
    elseif event == "LOOP" or event == "SYNC" or event == "SPECIALIZATION" then
        self:UpdateView()
    end
end
