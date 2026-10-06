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

local FRAME_WIDTH = 680
local FRAME_HEIGHT = 210
local MIN_FRAME_WIDTH = 200
local MAX_FRAME_WIDTH = 1200
local MIN_FRAME_HEIGHT = 170
local MAX_FRAME_HEIGHT = 420
local FIXED_VERTICAL_SPACE = 122
local UPDATE_INTERVAL = 0.05
local MARKER_SIZE = 22
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

function TimelineUI:CreateMarker(parent, kind)
    local colors = self.colors
    local marker = CreateFrame("Button", nil, parent, "BackdropTemplate")
    marker:SetSize(self.markerSize, self.markerSize)
    marker.kind = kind
    marker.borderColor = kind == "cooldown" and colors.status.success or colors.status.warning
    ApplyBackdrop(marker, self.flatTexture, colors.bg.widget, marker.borderColor)

    marker.spread = marker:CreateTexture(nil, "BACKGROUND")
    marker.spread:SetPoint("CENTER")
    marker.spread:SetHeight(4)
    SetTextureColor(marker.spread, colors.status.success, 0.28)
    marker.spread:Hide()

    marker.icon = marker:CreateTexture(nil, "ARTWORK")
    marker.icon:SetPoint("TOPLEFT", 2, -2)
    marker.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    marker.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    marker.countdown = self:CreateLabel(marker, "small", colors.text.highlight)
    marker.countdown:SetPoint("BOTTOM", marker, "TOP", 0, 1)
    marker.countdown:SetJustifyH("CENTER")

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
    line:SetThickness(1.6)
    self.damageLines[index] = line
    return line
end

function TimelineUI:GetGrid(index)
    local grid = self.gridLines[index]
    if grid then return grid end

    grid = {
        line = self.plot:CreateTexture(nil, "BACKGROUND", nil, 1),
        label = self:CreateLabel(self.plot, "small", self.colors.text.disabled),
    }
    grid.line:SetWidth(1)
    grid.line:SetPoint("TOP")
    grid.line:SetPoint("BOTTOM")
    SetTextureColor(grid.line, self.colors.border.separator)
    grid.label:SetPoint("TOP", grid.line, "TOP", 0, -2)
    self.gridLines[index] = grid
    return grid
end

function TimelineUI:GetPhaseMarker(index)
    local marker = self.phaseMarkers[index]
    if marker then return marker end

    marker = {
        line = self.plot:CreateTexture(nil, "OVERLAY", nil, 1),
        label = self:CreateLabel(self.plot, "normal", self.colors.status.warning),
    }
    marker.line:SetWidth(2)
    marker.line:SetPoint("TOP")
    marker.line:SetPoint("BOTTOM")
    SetTextureColor(marker.line, self.colors.status.warning, 0.55)
    marker.label:SetPoint("BOTTOMLEFT", marker.line, "TOPLEFT", 3, -15)
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

    ApplyBackdrop(frame, self.flatTexture, colors.bg.main, colors.border.default)

    -- [STYLE] C5: series mover HUD (center crosshair + "X Y · W×H" readout below the frame).
    if self.styleLib.CreateMoverHUD then
        frame.editHUD = self.styleLib.CreateMoverHUD(frame, ADDON_KEY)
    end

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(34)
    frame.header.background = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.header.background:SetAllPoints()
    SetTextureColor(frame.header.background, colors.bg.titlebar)

    if self.styleLib.CreateHorizontalGradient then
        frame.header.accentLine = self.styleLib.CreateHorizontalGradient(
            frame.header,
            self.accentFrom,
            self.accentTo,
            2,
            "OVERLAY"
        )
        frame.header.accentLine:SetPoint("TOPLEFT")
        frame.header.accentLine:SetPoint("TOPRIGHT")
    end

    frame.brandIcon = frame.header:CreateTexture(nil, "ARTWORK")
    frame.brandIcon:SetSize(20, 20)
    frame.brandIcon:SetPoint("LEFT", 8, -1)
    frame.brandIcon:SetTexture(BRAND_ICON)

    frame.brand = self:CreateLabel(frame.header, "title", colors.text.highlight)
    frame.brand:SetPoint("LEFT", frame.brandIcon, "RIGHT", 5, -1)
    frame.brand:SetWidth(160)
    frame.brand:SetJustifyH("LEFT")
    if self.styleLib.CreateAddonTitle then
        frame.brand:SetText(self.styleLib.CreateAddonTitle("RaidHelper", "RaidHelper"))
    else
        frame.brand:SetText("DDingUI RaidHelper")
    end

    frame.title = self:CreateLabel(frame.header, "normal", colors.text.normal)
    frame.title:SetPoint("LEFT", frame.brand, "RIGHT", 7, 0)
    frame.title:SetPoint("RIGHT", -114, 0)
    frame.title:SetJustifyH("LEFT")

    frame.phaseText = self:CreateLabel(frame.header, "normal", colors.status.warning)
    frame.phaseText:SetPoint("RIGHT", -72, 0)
    frame.phaseText:SetWidth(36)
    frame.phaseText:SetJustifyH("RIGHT")

    frame.timeText = self:CreateLabel(frame.header, "normal", colors.text.highlight)
    frame.timeText:SetPoint("RIGHT", -9, 0)
    frame.timeText:SetWidth(58)
    frame.timeText:SetJustifyH("RIGHT")

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", 9, -42)
    frame.content:SetPoint("BOTTOMRIGHT", -9, 9)

    frame.mechanicLayer = CreateFrame("Frame", nil, frame.content)
    frame.mechanicLayer:SetPoint("TOPLEFT")
    frame.mechanicLayer:SetPoint("TOPRIGHT")
    frame.mechanicLayer:SetHeight(30)

    frame.plot = CreateFrame("Frame", nil, frame.content, "BackdropTemplate")
    frame.plot:SetPoint("TOPLEFT", frame.mechanicLayer, "BOTTOMLEFT", 0, -3)
    frame.plot:SetPoint("TOPRIGHT", frame.mechanicLayer, "BOTTOMRIGHT", 0, -3)
    frame.plot:SetHeight(88)
    ApplyBackdrop(frame.plot, self.flatTexture, colors.bg.input, colors.border.separator)

    frame.cooldownLayer = CreateFrame("Frame", nil, frame.content)
    frame.cooldownLayer:SetPoint("TOPLEFT", frame.plot, "BOTTOMLEFT", 0, -5)
    frame.cooldownLayer:SetPoint("TOPRIGHT", frame.plot, "BOTTOMRIGHT", 0, -5)
    frame.cooldownLayer:SetHeight(28)

    frame.pastShade = frame.plot:CreateTexture(nil, "BACKGROUND", nil, 2)
    frame.pastShade:SetPoint("TOPLEFT", frame.plot, "TOPLEFT")
    frame.pastShade:SetPoint("BOTTOMLEFT", frame.plot, "BOTTOMLEFT")
    SetTextureColor(frame.pastShade, colors.bg.sidebar, 0.42)

    frame.baseline = frame.plot:CreateTexture(nil, "BACKGROUND", nil, 3)
    frame.baseline:SetPoint("BOTTOMLEFT", 0, 5)
    frame.baseline:SetPoint("BOTTOMRIGHT", 0, 5)
    frame.baseline:SetHeight(1)
    SetTextureColor(frame.baseline, colors.border.separator)

    frame.playhead = frame.content:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.playhead:SetPoint("TOP", frame.content, "TOP")
    frame.playhead:SetPoint("BOTTOM", frame.content, "BOTTOM")
    frame.playhead:SetWidth(2)
    SetTextureColor(frame.playhead, colors.status.error, 0.92)

    frame.noDataText = self:CreateLabel(frame.plot, "normal", colors.text.dim)
    frame.noDataText:SetPoint("CENTER")
    frame.noDataText:SetText("로그 피해 데이터 없음 · 실시간 기믹만 표시")
    frame.noDataText:Hide()

    frame.syncText = self:CreateLabel(frame, "small", colors.text.disabled)
    frame.syncText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, 2)
    frame.syncText:SetJustifyH("LEFT")

    frame.upcomingPanel = CreateFrame("Frame", nil, frame)
    frame.upcomingPanel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
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
    self.content = frame.content
    self.mechanicLayer = frame.mechanicLayer
    self.plot = frame.plot
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
    -- so the accent edit border stays on its backdrop and is restored when editing ends.
    local border = shown and self.accentFrom or self.colors.border.default
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
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

function TimelineUI:GetTimelineHeight()
    return ClampNumber(ns.db and ns.db.timelineHeight, MIN_FRAME_HEIGHT, MAX_FRAME_HEIGHT, FRAME_HEIGHT)
end

function TimelineUI:GetBackgroundAlpha()
    return ClampNumber(ns.db and ns.db.backgroundAlpha, 0, 1, 1.0)
end

function TimelineUI:ApplyBackgroundStyle()
    if not self.frame then return false end

    local alpha = self:GetBackgroundAlpha()
    local main = self.colors.bg.main
    local titlebar = self.colors.bg.titlebar
    local input = self.colors.bg.input

    ApplyBackdrop(self.frame, self.flatTexture, {
        main[1], main[2], main[3], (main[4] or 1) * alpha,
    }, self.colors.border.default)
    ApplyBackdrop(self.plot, self.flatTexture, {
        input[1], input[2], input[3], (input[4] or 1) * alpha,
    }, self.colors.border.separator)
    SetTextureColor(self.frame.header.background, titlebar, (titlebar[4] or 1) * alpha)
    SetTextureColor(self.frame.pastShade, self.colors.bg.sidebar, 0.42 * alpha)
    for _, row in ipairs(self.upcomingRows or {}) do
        ApplyBackdrop(row, self.flatTexture, {
            input[1], input[2], input[3], (input[4] or 1) * alpha,
        }, self.colors.border.default)
    end
    return true
end

function TimelineUI:ApplyDisplaySettings()
    if not self.frame then return false end

    local width = self:GetTimelineWidth()
    local height = self:GetTimelineHeight()
    self.frame:SetSize(width, height)
    self.plot:SetHeight(max(48, height - FIXED_VERTICAL_SPACE))
    if self.upcomingPanel then
        self.upcomingPanel:SetWidth(min(UPCOMING_PANEL_MAX_WIDTH, max(200, floor(width * 0.58))))
    end
    local compactHeader = width < 400
    if self.frame.brand then self.frame.brand:SetShown(not compactHeader) end
    if self.frame.title then self.frame.title:SetShown(not compactHeader) end
    if self.frame.phaseText then self.frame.phaseText:SetShown(not compactHeader) end
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
    self.flatTexture = styleLib.GetTexture and styleLib:GetTexture("flat") or "Interface\\Buttons\\WHITE8x8"

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
        end
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
    self.accentFrom, self.accentTo = styleLib.GetAccent("RaidHelper")
    self.markerSize = self.tokens.ROW_H or MARKER_SIZE
    self.updateInterval = self.tokens.ANIM_FPS_LIMIT or UPDATE_INTERVAL
    self.damageLines = {}
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

    while tick <= finalTick do
        visible = visible + 1
        local grid = self:GetGrid(visible)
        local x = self:MapTimeToX(tick, currentTime, width)
        grid.line:ClearAllPoints()
        grid.line:SetPoint("TOP", self.plot, "TOPLEFT", x, 0)
        grid.line:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", x, 0)
        grid.label:SetText(FormatTime(tick))
        grid.line:Show()
        grid.label:Show()
        tick = tick + 5
    end

    for index = visible + 1, #self.gridLines do
        self.gridLines[index].line:Hide()
        self.gridLines[index].label:Hide()
    end
end

function TimelineUI:UpdatePhases(model, currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = currentTime - past
    local rangeEnd = currentTime + future
    local visible = 0

    for _, phase in ipairs(model.phases or {}) do
        local phaseTime = phase.t or 0
        if phaseTime >= rangeStart and phaseTime <= rangeEnd then
            visible = visible + 1
            local marker = self:GetPhaseMarker(visible)
            local x = self:MapTimeToX(phaseTime, currentTime, width)
            marker.line:ClearAllPoints()
            marker.line:SetPoint("TOP", self.plot, "TOPLEFT", x, 0)
            marker.line:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", x, 0)
            marker.label:SetText(phase.label or ("P" .. tostring(phase.index or visible)))
            marker.line:Show()
            marker.label:Show()
        end
    end

    for index = visible + 1, #self.phaseMarkers do
        self.phaseMarkers[index].line:Hide()
        self.phaseMarkers[index].label:Hide()
    end
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
    local visible = 0

    for index = firstIndex, finalIndex do
        local firstValue = values[index]
        local secondValue = values[index + 1]
        if firstValue and secondValue then
            visible = visible + 1
            local line = self:GetDamageLine(visible)
            if line then
                local firstTime = (index - 1) * interval
                local secondTime = index * interval
                local firstRatio = min(1, max(0, firstValue / maximum))
                local secondRatio = min(1, max(0, secondValue / maximum))
                local ratio = max(firstRatio, secondRatio)
                local color = self.accentFrom
                if ratio >= 0.74 then
                    color = self.colors.status.error
                elseif ratio < 0.32 then
                    color = self.colors.text.dim
                end
                line:SetColorTexture(color[1], color[2], color[3], 0.94)
                line:SetStartPoint("BOTTOMLEFT", self.plot, self:MapTimeToX(firstTime, currentTime, width), 5 + firstRatio * (height - 11))
                line:SetEndPoint("BOTTOMLEFT", self.plot, self:MapTimeToX(secondTime, currentTime, width), 5 + secondRatio * (height - 11))
                line:Show()
            end
        end
    end

    for index = visible + 1, #self.damageLines do
        self.damageLines[index]:Hide()
    end
    self.frame.noDataText:SetShown(#values == 0)
end

function TimelineUI:ConfigureMarker(marker, data, currentTime, width, kind)
    local x = self:MapTimeToX(data.t or 0, currentTime, width)
    local halfMarker = (self.markerSize or MARKER_SIZE) * 0.5
    local markerMinX = min(width, halfMarker)
    local markerMaxX = max(markerMinX, width - halfMarker)
    local markerX = min(markerMaxX, max(markerMinX, x))
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", marker:GetParent(), "LEFT", markerX, kind == "cooldown" and 0 or -2)
    marker.icon:SetTexture(ResolveIcon(data))
    marker.data = data
    marker.countdown:SetText(tostring(ceil((data.t or 0) - currentTime)))

    if kind == "cooldown" and type(data.spread) == "number" and data.spread > 0 then
        local secondsWidth = width / (max(1, ns.db.windowPast or 12) + max(1, ns.db.windowFuture or 38))
        local desiredWidth = max(self.markerSize, data.spread * 2 * secondsWidth)
        local spreadLeft = max(0, markerX - desiredWidth * 0.5)
        local spreadRight = min(width, markerX + desiredWidth * 0.5)
        marker.spread:ClearAllPoints()
        marker.spread:SetPoint("CENTER", marker:GetParent(), "LEFT", (spreadLeft + spreadRight) * 0.5, 0)
        marker.spread:SetWidth(max(1, spreadRight - spreadLeft))
        marker.spread:Show()
    else
        marker.spread:Hide()
    end
    marker:Show()
end

function TimelineUI:UpdateMechanics(model, currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = currentTime - past
    local rangeEnd = currentTime + future
    local visible = 0

    for _, mechanic in ipairs(model.mechanics or {}) do
        local eventTime = mechanic.t or 0
        if eventTime >= rangeStart and eventTime <= rangeEnd then
            visible = visible + 1
            local marker = self:GetMarker(self.mechanicMarkers, visible, self.mechanicLayer, "mechanic")
            self:ConfigureMarker(marker, mechanic, currentTime, width, "mechanic")
        end
    end

    for _, liveMechanic in pairs(ns.Engine:GetLiveMechanics()) do
        local eventTime = liveMechanic.t or 0
        if (not liveMechanic.matched or liveMechanic.matched.syncOnly)
            and eventTime >= rangeStart and eventTime <= rangeEnd then
            visible = visible + 1
            local marker = self:GetMarker(self.mechanicMarkers, visible, self.mechanicLayer, "mechanic")
            self:ConfigureMarker(marker, liveMechanic, currentTime, width, "mechanic")
        end
    end

    for index = visible + 1, #self.mechanicMarkers do
        self.mechanicMarkers[index]:Hide()
    end
end

function TimelineUI:UpdateCooldowns(model, currentTime, width)
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local rangeStart = currentTime - past
    local rangeEnd = currentTime + future
    local visible = 0

    for _, cooldown in ipairs(ns.Engine:GetCooldowns()) do
        local eventTime = cooldown.t or 0
        if eventTime >= rangeStart and eventTime <= rangeEnd then
            visible = visible + 1
            local marker = self:GetMarker(self.cooldownMarkers, visible, self.cooldownLayer, "cooldown")
            self:ConfigureMarker(marker, cooldown, currentTime, width, "cooldown")
        end
    end

    for index = visible + 1, #self.cooldownMarkers do
        self.cooldownMarkers[index]:Hide()
    end
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

    local currentTime = ns.Engine:GetTimelineTime()
    local width = max(1, self.plot:GetWidth())
    local height = max(1, self.plot:GetHeight())
    local past = max(1, ns.db.windowPast or 12)
    local future = max(1, ns.db.windowFuture or 38)
    local playheadX = (past / (past + future)) * width
    local phase = ns.Engine:GetPhaseAt(currentTime)

    local encounterTitle = ns.Engine.encounterName or model.name or "Unknown Encounter"
    self.frame.title:SetText(encounterTitle .. (ns.Engine.difficultyName and (" · " .. ns.Engine.difficultyName) or ""))
    self.frame.timeText:SetText(FormatTime(currentTime))
    self.frame.phaseText:SetText(phase and (phase.label or ("P" .. tostring(phase.index or 1))) or "")
    self.frame.playhead:ClearAllPoints()
    self.frame.playhead:SetPoint("TOP", self.content, "TOPLEFT", playheadX, 0)
    self.frame.playhead:SetPoint("BOTTOM", self.content, "BOTTOMLEFT", playheadX, 0)
    self.frame.pastShade:SetWidth(playheadX)

    local lastSync = ns.Engine.lastSync
    if lastSync then
        self.frame.syncText:SetText("SYNC · " .. tostring(lastSync.source) .. (ns.Engine.playerSpecName and (" · " .. ns.Engine.playerSpecName) or ""))
    elseif self:IsPreviewMode() then
        self.frame.syncText:SetText("PREVIEW · 드래그·방향키로 위치 조정 · Esc로 종료")
    elseif model.dataStatus == "demo" then
        self.frame.syncText:SetText("PREVIEW · 상위 로그 10개 집계 형식" .. (ns.Engine.playerSpecName and (" · " .. ns.Engine.playerSpecName) or ""))
    elseif model.dataStatus == "missing" then
        self.frame.syncText:SetText("LIVE · 로그 데이터 팩 대기" .. (ns.Engine.playerSpecName and (" · " .. ns.Engine.playerSpecName) or ""))
    else
        self.frame.syncText:SetText("LIVE" .. (ns.Engine.playerSpecName and (" · " .. ns.Engine.playerSpecName) or ""))
    end

    self:UpdateGrid(currentTime, width)
    self:UpdatePhases(model, currentTime, width)
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

function TimelineUI:OnEngineEvent(event, ...)
    if not self.initialized then return end

    if event == "START" then
        local engineOptions = ns.Engine.options or {}
        local isPreview = engineOptions.previewMode == true or engineOptions.editMode == true
        self.previewMode = isPreview
        self.editMode = isPreview
        if not isPreview then self:EndEditSession(false) end
        self:RefreshPreviewControl()
        self.frame:Show()
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
        self.frame.syncText:SetText(success and "전투 종료 · 처치" or "전투 종료")
        C_Timer.After(3, function()
            if not ns.Engine:IsRunning() then
                TimelineUI.frame:Hide()
            end
        end)
    elseif event == "LOOP" or event == "SYNC" or event == "SPECIALIZATION" then
        self:UpdateView()
    end
end
