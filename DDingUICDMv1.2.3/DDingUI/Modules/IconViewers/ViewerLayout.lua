local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

local IconViewers = DDingUI.IconViewers
if not IconViewers then
    error("DDingUI: IconViewers module not initialized! Load IconViewers.lua first.")
end

-- Reference shared weak table for icon data (avoids tainting Blizzard frames)
local iconData = IconViewers._iconData

local function GetIconData(frame)
    local d = iconData[frame]
    if not d then d = {}; iconData[frame] = d end
    return d
end

-- Access shared viewer state weak table from IconViewers (avoids tainting Blizzard viewer frames)
local function GetViewerState(viewer)
    if IconViewers._GetViewerState then
        return IconViewers._GetViewerState(viewer)
    end
    -- Fallback
    local state = IconViewers._viewerState and IconViewers._viewerState[viewer]
    if not state then
        state = {}
        if IconViewers._viewerState then
            IconViewers._viewerState[viewer] = state
        end
    end
    return state
end

local ceil = math.ceil
local abs = math.abs
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup

-- Group state offset: returns (x, y) offset based on party/raid state
local function GetGroupOffset(settings)
    local offsets = settings and settings.groupOffsets
    if not offsets then return 0, 0 end
    if IsInRaid() then
        local r = offsets.raid
        return r and r.x or 0, r and r.y or 0
    elseif IsInGroup() then
        local p = offsets.party
        return p and p.x or 0, p and p.y or 0
    end
    return 0, 0
end

local DIRECTION_RULES = {
    CENTERED_HORIZONTAL = { type = "HORIZONTAL", defaultSecondary = "DOWN", allowed = { UP = true, DOWN = true } },
    LEFT                = { type = "HORIZONTAL", defaultSecondary = "DOWN", allowed = { UP = true, DOWN = true } },
    RIGHT               = { type = "HORIZONTAL", defaultSecondary = "DOWN", allowed = { UP = true, DOWN = true } },
    UP                  = { type = "VERTICAL",   defaultSecondary = "RIGHT", allowed = { LEFT = true, RIGHT = true } },
    DOWN                = { type = "VERTICAL",   defaultSecondary = "RIGHT", allowed = { LEFT = true, RIGHT = true } },
    STATIC              = { type = "STATIC" },
}

local trackedViewers = {}
IconViewers._trackedViewers = trackedViewers

local function PixelSnap(value)
    return math.max(0, math.floor((value or 0) + 0.5))
end

local function ResetTrackedViewerAnchors()
    if not trackedViewers then return end

    for viewer in pairs(trackedViewers) do
        if viewer and viewer.GetName then
            local state = GetViewerState(viewer)
            state.anchorShiftX = 0
            state.anchorShiftY = 0
            -- Prevent a post-EditMode snap by skipping the next anchor adjust
            state.skipNextAnchorAdjust = true

            -- BuffIconCooldownViewer의 경우 기준 아이콘 개수 리셋
            -- 다음 CenterBuffIcons 호출 시 현재 개수가 새 기준으로 설정됨
            if viewer:GetName() == "BuffIconCooldownViewer" then
                state.baseIconCount = nil
            end

            IconViewers:ApplyViewerLayout(viewer)
        else
            trackedViewers[viewer] = nil
        end
    end
end

local editModeHooksInstalled = false
local editModeHookTimer = false
local editModeHookListener = nil

local function EnsureEditModeHooks()
    if editModeHooksInstalled then return end

    if not EditModeManagerFrame then
        if IsLoggedIn and IsLoggedIn() then
            if not editModeHookTimer then
                editModeHookTimer = true
                C_Timer.After(0.25, function()
                    editModeHookTimer = false
                    EnsureEditModeHooks()
                end)
            end
        elseif not editModeHookListener then
            local listener = CreateFrame("Frame")
            listener:RegisterEvent("PLAYER_LOGIN")
            listener:SetScript("OnEvent", function(self)
                if EditModeManagerFrame then
                    EnsureEditModeHooks()
                    self:UnregisterAllEvents()
                    self:SetScript("OnEvent", nil)
                end
            end)
            editModeHookListener = listener
        end
        return
    end

    editModeHooksInstalled = true

    -- On EnterEditMode: restore original Blizzard viewer sizes so snap grid is correct
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if InCombatLockdown() then return end
        for viewer in pairs(trackedViewers) do
            if viewer and viewer.GetName then
                local state = GetViewerState(viewer)
                if state.origWidth and state.origHeight then
                    pcall(viewer.SetSize, viewer, state.origWidth, state.origHeight)
                end
            end
        end
    end)

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", ResetTrackedViewerAnchors)
end

local function TrackViewer(viewer)
    if not viewer then return end
    trackedViewers[viewer] = true
    EnsureEditModeHooks()
end

-- Helper function to check if we're in EditMode (avoid modifying frames during EditMode)
local function IsInEditMode()
    if not EditModeManagerFrame then return false end
    local inEditMode = false
    pcall(function()
        inEditMode = EditModeManagerFrame:IsShown() or EditModeManagerFrame.editModeActive
    end)
    return inEditMode
end

local function IsCooldownIconFrame(frame)
    return frame and (frame.icon or frame.Icon) and frame.Cooldown
end

local function IsPlaceholderIcon(iconFrame)
    -- Placeholder icons lack layoutIndex; real active icons always have it set -- [FIX: placeholder detection]
    -- layoutIndex is more reliable than cooldownID (used by BetterCooldownManager/CooldownManagerCentered)
    if not iconFrame then return true end
    local success, hasLayoutIndex = pcall(function()
        return iconFrame.layoutIndex ~= nil
    end)
    if not success then
        return false
    end
    return not hasLayoutIndex
end

local function NormalizeDirectionToken(token)
    if not token or token == "" then
        return nil
    end

    local aliases = {
        CENTEREDHORIZONTAL = "CENTERED_HORIZONTAL",
        CENTERHORIZONTAL   = "CENTERED_HORIZONTAL",
        CENTERED           = "CENTERED_HORIZONTAL",
        CENTER             = "CENTERED_HORIZONTAL",
        CENTRED            = "CENTERED_HORIZONTAL",
        CENTRE             = "CENTERED_HORIZONTAL",
    }

    local cleaned = token:gsub("[%s%-_]+", ""):upper()
    return aliases[cleaned] or cleaned
end

local function ClampRowLimit(value)
    if not value or value <= 0 then
        return 0
    end
    return math.floor(value + 0.0001)
end

local function ResolveDirections(viewerName, settings)
    local primary = NormalizeDirectionToken(settings.primaryDirection)
    local secondary = NormalizeDirectionToken(settings.secondaryDirection)

    local legacyDirection = settings.growthDirection
    if not primary and legacyDirection then
        if legacyDirection == "Static" or legacyDirection == "STATIC" then
            primary = "STATIC"
        elseif legacyDirection:match("^Centered Horizontal and") then
            primary = "CENTERED_HORIZONTAL"
            local token = legacyDirection:match("and%s+(.+)$")
            secondary = NormalizeDirectionToken(token)
        elseif legacyDirection == "Centered Horizontal" then
            primary = "CENTERED_HORIZONTAL"
        else
            local p = legacyDirection:match("^(%w+)")
            primary = NormalizeDirectionToken(p)
            local s = legacyDirection:match("and%s+(.+)$")
            secondary = NormalizeDirectionToken(s)
        end
    end

    if not primary and viewerName == "BuffIconCooldownViewer" and settings.rowGrowDirection then
        primary = "CENTERED_HORIZONTAL"
        if type(settings.rowGrowDirection) == "string" and settings.rowGrowDirection:lower() == "up" then
            secondary = "UP"
        else
            secondary = "DOWN"
        end
    end

    primary = primary or "CENTERED_HORIZONTAL"
    local rule = DIRECTION_RULES[primary]
    if not rule then
        primary = "CENTERED_HORIZONTAL"
        rule = DIRECTION_RULES[primary]
    end

    local rowLimit = ClampRowLimit(settings.rowLimit or 0)

    if rule.type ~= "STATIC" and rowLimit > 0 then
        if not secondary or not rule.allowed[secondary] then
            secondary = rule.defaultSecondary
        end
    else
        secondary = nil
    end

    return primary, secondary, rowLimit, rule.type
end

local function ComputeIconDimensions(settings, sizeOverride)
    local baseSize = sizeOverride or settings.iconSize or 32
    local iconSize = baseSize + 0.1
    local aspectRatioValue = 1.0

    if settings.aspectRatioCrop then
        aspectRatioValue = settings.aspectRatioCrop
    elseif settings.aspectRatio then
        local aspectW, aspectH = settings.aspectRatio:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        if aspectW and aspectH then
            aspectRatioValue = tonumber(aspectW) / tonumber(aspectH)
        end
    end

    local iconWidth = iconSize
    local iconHeight = iconSize

    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            iconHeight = iconSize / aspectRatioValue
        elseif aspectRatioValue < 1.0 then
            iconWidth = iconSize * aspectRatioValue
        end
    end

    -- Snap to whole pixels to keep downstream layout widths stable
    return PixelSnap(iconWidth), PixelSnap(iconHeight)
end

local function GetRowIconSize(settings, rowIndex)
    if not settings or not settings.rowIconSizes then
        return nil
    end

    local value = settings.rowIconSizes[rowIndex]
    if type(value) == "string" then
        value = tonumber(value)
    end

    if type(value) == "number" and value > 0 then
        return value
    end

    return nil
end

local function ComputeSpacing(settings)
    local spacing = settings.spacing or 4
    return PixelSnap(spacing + 2)
end

local function BuildDirectionKey(primary, secondary, rowLimit)
    return string.format("%s_%s_%d", primary or "CENTERED_HORIZONTAL", secondary or "NONE", rowLimit or 0)
end

local function BuildAppearanceKey(baseWidth, baseHeight, spacing, rowDimensions)
    local parts = { string.format("%.3f:%.3f:%.3f", baseWidth or 0, baseHeight or 0, spacing or 0) }

    if rowDimensions then
        for i = 1, 3 do
            local dims = rowDimensions[i]
            if dims and dims.width and dims.height then
                parts[#parts + 1] = string.format("r%d:%.3f:%.3f", i, dims.width, dims.height)
            end
        end
    end

    return table.concat(parts, "|")
end

local function PrepareIconOrder(viewerName, icons)
    if viewerName == "BuffIconCooldownViewer" then
        for index, icon in ipairs(icons) do
            if not icon.layoutIndex and not icon:GetID() then
                local id = GetIconData(icon)
                if not id.creationOrder then
                    id.creationOrder = index
                end
            end
        end
    end

    -- Always sort (cache on temporary icons table never persists, matching v1.1.7.1 behavior)
    table.sort(icons, function(a, b)
        local aid = iconData[a]
        local bid = iconData[b]
        local la = a.layoutIndex or a:GetID() or (aid and aid.creationOrder) or 0
        local lb = b.layoutIndex or b:GetID() or (bid and bid.creationOrder) or 0
        if la == lb then
            return ((aid and aid.creationOrder) or 0) < ((bid and bid.creationOrder) or 0)
        end
        return la < lb
    end)
end

local function LayoutHorizontal(icons, container, primary, secondary, spacing, rowLimit, getDimensionsForRow)
    local count = #icons
    if count == 0 then return 0, 0, 0 end

    local iconsPerRow = rowLimit > 0 and math.max(1, rowLimit) or count
    local numRows = ceil(count / iconsPerRow)
    local rowDirection = (secondary == "UP") and 1 or -1

    local rowMeta = {}
    local maxRowWidth = 0
    local totalHeight = 0
    for row = 1, numRows do
        local iconWidth, iconHeight = getDimensionsForRow(row)
        local rowStart = (row - 1) * iconsPerRow + 1
        local rowEnd = math.min(row * iconsPerRow, count)
        local rowCount = rowEnd - rowStart + 1
        local rowWidth = rowCount * iconWidth + (rowCount - 1) * spacing
        if rowWidth < iconWidth then
            rowWidth = iconWidth
        end
        maxRowWidth = math.max(maxRowWidth, rowWidth)
        totalHeight = totalHeight + iconHeight

        rowMeta[row] = {
            startIndex = rowStart,
            count = rowCount,
            width = rowWidth,
            iconWidth = iconWidth,
            iconHeight = iconHeight,
        }
    end

    totalHeight = totalHeight + (numRows - 1) * spacing
    -- Start from the top (for DOWN) or bottom (for UP) so row 1 stays fixed without moving the container
    local anchorY
    if rowDirection == -1 then
        anchorY = (totalHeight / 2) - (rowMeta[1].iconHeight / 2)
    else
        anchorY = -(totalHeight / 2) + (rowMeta[1].iconHeight / 2)
    end

    local currentY = anchorY
    for row = 1, numRows do
        local meta = rowMeta[row]
        local rowLeftEdge = -(maxRowWidth / 2) + (meta.iconWidth / 2)
        local rowRightEdge = (maxRowWidth / 2) - (meta.iconWidth / 2)
        local baseX
        if primary == "CENTERED_HORIZONTAL" then
            baseX = -meta.width / 2 + meta.iconWidth / 2
        elseif primary == "RIGHT" then
            baseX = rowLeftEdge
        else -- LEFT
            baseX = rowRightEdge
        end

        for position = 0, meta.count - 1 do
            local icon = icons[meta.startIndex + position]
            local x
            if primary == "LEFT" then
                x = baseX - position * (meta.iconWidth + spacing)
            else
                x = baseX + position * (meta.iconWidth + spacing)
            end

            icon:SetSize(meta.iconWidth, meta.iconHeight)
            icon:SetPoint("CENTER", container, "CENTER", x, currentY)
        end

        local nextMeta = rowMeta[row + 1]
        if nextMeta then
            local step = (meta.iconHeight / 2) + (nextMeta.iconHeight / 2) + spacing
            currentY = currentY + step * rowDirection
        end
    end

    return maxRowWidth, totalHeight, 0
end

local function LayoutVertical(icons, container, primary, secondary, spacing, rowLimit, getDimensionsForRow)
    local count = #icons
    if count == 0 then return 0, 0, 0 end

    local iconsPerColumn = rowLimit > 0 and math.max(1, rowLimit) or count
    local numColumns = ceil(count / iconsPerColumn)
    local columnDirection = (secondary == "LEFT") and -1 or 1
    local verticalDirection = (primary == "UP") and 1 or -1

    local columnMeta = {}
    local maxColumnHeight = 0
    local totalWidth = 0
    for column = 1, numColumns do
        local iconWidth, iconHeight = getDimensionsForRow(column)
        local columnStart = (column - 1) * iconsPerColumn + 1
        local columnEnd = math.min(column * iconsPerColumn, count)
        local columnCount = columnEnd - columnStart + 1
        local columnHeight = columnCount * iconHeight + (columnCount - 1) * spacing

        maxColumnHeight = math.max(maxColumnHeight, columnHeight)
        totalWidth = totalWidth + iconWidth
        if column > 1 then
            totalWidth = totalWidth + spacing
        end

        columnMeta[column] = {
            startIndex = columnStart,
            count = columnCount,
            height = columnHeight,
            iconWidth = iconWidth,
            iconHeight = iconHeight,
        }
    end

    local totalHeight = maxColumnHeight

    -- Start from left (for RIGHT growth) or right (for LEFT growth) so column 1 stays fixed
    local anchorX
    if columnDirection == 1 then
        anchorX = -(totalWidth / 2) + (columnMeta[1].iconWidth / 2)
    else
        anchorX = (totalWidth / 2) - (columnMeta[1].iconWidth / 2)
    end

    local anchorY
    if verticalDirection == -1 then
        anchorY = (totalHeight / 2) - (columnMeta[1].iconHeight / 2)
    else
        anchorY = -(totalHeight / 2) + (columnMeta[1].iconHeight / 2)
    end

    local currentX = anchorX
    for column = 1, numColumns do
        local meta = columnMeta[column]

        local startY = anchorY
        for position = 0, meta.count - 1 do
            local icon = icons[meta.startIndex + position]
            local y = startY + position * (meta.iconHeight + spacing) * verticalDirection
            icon:SetSize(meta.iconWidth, meta.iconHeight)
            icon:SetPoint("CENTER", container, "CENTER", currentX, y)
        end

        local nextMeta = columnMeta[column + 1]
        if nextMeta then
            local step = (meta.iconWidth / 2) + (nextMeta.iconWidth / 2) + spacing
            currentX = currentX + step * columnDirection
        end
    end

    return totalWidth, totalHeight, 0
end

local function AdjustViewerAnchor(viewer, shiftX, shiftY)
    local state = GetViewerState(viewer)
    if viewer and state.skipNextAnchorAdjust then
        state.skipNextAnchorAdjust = nil
        return
    end

    shiftX = shiftX or 0
    shiftY = shiftY or 0

    local prevX = state.anchorShiftX or 0
    local prevY = state.anchorShiftY or 0
    local deltaX = shiftX - prevX
    local deltaY = shiftY - prevY

    if deltaX == 0 and deltaY == 0 then return end
    if InCombatLockdown() then return end

    local point, relativeTo, relativePoint, xOfs, yOfs = viewer:GetPoint(1)
    if not point then return end

    viewer:ClearAllPoints()
    viewer:SetPoint(point, relativeTo, relativePoint, (xOfs or 0) - deltaX, (yOfs or 0) - deltaY)
    state.anchorShiftX = shiftX
    state.anchorShiftY = shiftY
end

-- Custom anchor: move viewer to a user-specified frame instead of EditMode position
local function SaveOriginalAnchors(viewer)
    if viewer.__dduiOrigAnchors then return end
    local n = viewer:GetNumPoints()
    if n == 0 then return end
    viewer.__dduiOrigAnchors = {}
    for i = 1, n do
        local point, relativeTo, relativePoint, offsetX, offsetY = viewer:GetPoint(i)
        table.insert(viewer.__dduiOrigAnchors, { point, relativeTo, relativePoint, offsetX, offsetY })
    end
end

local function RestoreOriginalAnchors(viewer)
    local saved = viewer.__dduiOrigAnchors
    if not saved or #saved == 0 then return end
    viewer:ClearAllPoints()
    for _, a in ipairs(saved) do
        viewer:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end
    viewer.__dduiOrigAnchors = nil
end

local function ApplyCustomAnchor(viewer, settings)
    if InCombatLockdown() then return end
    if not settings then return end
    local frameName = settings.anchorFrame
    if not frameName or frameName == "" then
        RestoreOriginalAnchors(viewer)
        return
    end
    local target = _G[frameName]
    if not target then return end
    SaveOriginalAnchors(viewer)
    local pt = settings.anchorPoint or "CENTER"
    local ox = settings.anchorOffsetX or 0
    local oy = settings.anchorOffsetY or 0
    viewer:ClearAllPoints()
    viewer:SetPoint(pt, target, pt, ox, oy)
end

function IconViewers:ApplyViewerLayout(viewer)
    if not viewer or not viewer.GetName then return end
    -- Skip during EditMode to prevent overriding Blizzard nudge/snap positioning
    if IsInEditMode() then return end
    -- FlightHide: skip layout during flight
    if DDingUI.FlightHide and DDingUI.FlightHide.isActive then return end

    local name = viewer:GetName()
    local settings = DDingUI.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    -- BuffIconCooldownViewer uses OnUpdate-based centering for stability
    -- Skip manual layout and let CenterBuffIcons handle it continuously
    if name == "BuffIconCooldownViewer" then
        -- Only skin icons, don't reposition - OnUpdate handles positioning
        GetViewerState(viewer).lastLayoutApplied = true
        -- Apply custom anchor if set
        ApplyCustomAnchor(viewer, settings)
        return
    end

    TrackViewer(viewer)

    local container = viewer.viewerFrame or viewer
    local icons = {}

    for _, child in ipairs({ container:GetChildren() }) do
        if IsCooldownIconFrame(child) and child:IsShown() then
            -- Filter out placeholder icons for BuffIconCooldownViewer (those without cooldownID)
            if name == "BuffIconCooldownViewer" and IsPlaceholderIcon(child) then
                -- Hide DDingUI borders on placeholder/recycled frames to prevent black empty borders
                local cid = iconData[child]
                if cid and cid.skinned then
                    if cid.borders then
                        for _, borderTex in ipairs(cid.borders) do
                            borderTex:SetShown(false)
                        end
                    end
                    cid.skinned = nil  -- Reset so frame gets re-skinned when CDM reuses it
                end
            else
                table.insert(icons, child)
            end
        end
    end

    local count = #icons
    if count == 0 then return end

    local vState = GetViewerState(viewer)
    if vState.layoutRunning then
        return
    end
    vState.layoutRunning = true
    local function finishLayout()
        GetViewerState(viewer).layoutRunning = nil
    end

    PrepareIconOrder(name, icons)

    local baseIconWidth, baseIconHeight = ComputeIconDimensions(settings)
    local spacing = ComputeSpacing(settings)
    local primary, secondary, rowLimit, layoutType = ResolveDirections(name, settings)
    local directionKey = BuildDirectionKey(primary, secondary, rowLimit)
    local rowDimensions = {}
    local function GetDimensionsForRow(rowIndex)
        if not rowDimensions[rowIndex] then
            local overrideSize = GetRowIconSize(settings, rowIndex)
            local w, h = ComputeIconDimensions(settings, overrideSize)
            rowDimensions[rowIndex] = { width = w, height = h }
        end
        return rowDimensions[rowIndex].width, rowDimensions[rowIndex].height
    end
    for preload = 1, 3 do
        GetDimensionsForRow(preload)
    end
    local appearanceKey = BuildAppearanceKey(baseIconWidth, baseIconHeight, spacing, rowDimensions)

    if name == "BuffIconCooldownViewer" and primary == "STATIC" then
        local rowWidth, rowHeight = GetDimensionsForRow(1)
        for _, icon in ipairs(icons) do
            icon:SetWidth(rowWidth)
            icon:SetHeight(rowHeight)
            icon:SetSize(rowWidth, rowHeight)
        end
        GetViewerState(viewer).lastGrowthDirection = directionKey
        GetViewerState(viewer).lastAppearanceKey = appearanceKey
        AdjustViewerAnchor(viewer, 0, 0)
        finishLayout()
        return
    end

    for _, icon in ipairs(icons) do
        icon:ClearAllPoints()
    end

    local totalWidth, totalHeight, anchorShift
    if layoutType == "VERTICAL" then
        totalWidth, totalHeight, anchorShift = LayoutVertical(icons, container, primary, secondary, spacing, rowLimit, GetDimensionsForRow)
    else
        totalWidth, totalHeight, anchorShift = LayoutHorizontal(icons, container, primary, secondary, spacing, rowLimit, GetDimensionsForRow)
    end

    local snappedWidth = PixelSnap(totalWidth)
    local snappedHeight = PixelSnap(totalHeight)
    local vState2 = GetViewerState(viewer)
    vState2.iconWidth = snappedWidth
    vState2.iconHeight = snappedHeight
    vState2.lastGrowthDirection = directionKey
    vState2.lastAppearanceKey = appearanceKey

    -- [FIX] 추적 바(BuffTrackerBar 등)가 뷰어 너비를 참조할 수 있도록 동기화
    -- anchor.__cdmIconWidth를 읽는 코드: BuffTrackerBar, PrimaryPowerBar, SecondaryPowerBar, PlayerCastBar
    viewer.__cdmIconWidth = snappedWidth

    -- Apply group offset (party/raid state-based shift) to all icons
    local groupOX, groupOY = GetGroupOffset(settings)
    if groupOX ~= 0 or groupOY ~= 0 then
        local scaledOX = DDingUI:Scale(groupOX)
        local scaledOY = DDingUI:Scale(groupOY)
        for _, icon in ipairs(icons) do
            local pt, rel, relPt, xOfs, yOfs = icon:GetPoint(1)
            if pt then
                icon:ClearAllPoints()
                icon:SetPoint(pt, rel, relPt, (xOfs or 0) + scaledOX, (yOfs or 0) + scaledOY)
            end
        end
    end

    if not InCombatLockdown() then
        local vs = GetViewerState(viewer)
        -- Save original Blizzard size before first override (for EditMode snap grid restoration)
        if not vs.origWidth then
            local ok, w, h = pcall(viewer.GetSize, viewer)
            if ok and w and h and w > 0 and h > 0 then
                vs.origWidth = w
                vs.origHeight = h
            end
        end
        viewer:SetSize(snappedWidth, snappedHeight)
        vs.lastLayoutApplied = true
        -- Apply custom anchor if set (after size is set, overrides EditMode position)
        ApplyCustomAnchor(viewer, settings)
    end

    finishLayout()
end

function IconViewers:RescanViewer(viewer)
    if not viewer or not viewer.GetName then return end
    -- Skip during EditMode to prevent overriding Blizzard nudge/snap positioning
    if IsInEditMode() then return end
    -- FlightHide: skip rescan during flight
    if DDingUI.FlightHide and DDingUI.FlightHide.isActive then return end

    local name = viewer:GetName()
    local settings = DDingUI.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    TrackViewer(viewer)

    local container = viewer.viewerFrame or viewer
    local icons = {}
    local changed = false
    local inCombat = InCombatLockdown()
    local collectAllIcons = (name == "BuffIconCooldownViewer")

    for _, child in ipairs({ container:GetChildren() }) do
        if IsCooldownIconFrame(child) then
            -- Filter out placeholder icons for BuffIconCooldownViewer (those without cooldownID)
            if name == "BuffIconCooldownViewer" and IsPlaceholderIcon(child) then
                -- Hide DDingUI borders on placeholder/recycled frames to prevent black empty borders
                local cid = iconData[child]
                if cid and cid.skinned then
                    if cid.borders then
                        for _, borderTex in ipairs(cid.borders) do
                            borderTex:SetShown(false)
                        end
                    end
                    cid.skinned = nil  -- Reset so frame gets re-skinned when CDM reuses it
                end
            elseif collectAllIcons or child:IsShown() then
                table.insert(icons, child)

                local vid = iconData[child]
                if not (vid and vid.skinned) and not (vid and vid.skinPending) then
                    GetIconData(child).skinPending = true

                    if inCombat then
                        DDingUI.__cdmPendingIcons = DDingUI.__cdmPendingIcons or {}
                        DDingUI.__cdmPendingIcons[child] = { icon = child, settings = settings, viewer = viewer }

                        if not DDingUI.__cdmIconSkinEventFrame then
                            local eventFrame = CreateFrame("Frame")
                            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                            eventFrame:SetScript("OnEvent", function(self)
                                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                                if IconViewers.ProcessPendingIcons then
                                    IconViewers:ProcessPendingIcons()
                                end
                            end)
                            DDingUI.__cdmIconSkinEventFrame = eventFrame
                        end
                        DDingUI.__cdmIconSkinEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                    else
                        local success = pcall(self.SkinIcon, self, child, settings)
                        if success then
                            local vid2 = iconData[child]; if vid2 then vid2.skinPending = nil end
                        end
                    end
                    changed = true
                end
            end
        end
    end

    PrepareIconOrder(name, icons)
    local count = #icons

    local shownIcons = icons
    local shownCount = count
    if collectAllIcons then
        shownIcons = {}
        for _, icon in ipairs(icons) do
            if icon and icon.IsShown and icon:IsShown() then
                shownIcons[#shownIcons + 1] = icon
            end
        end
        shownCount = #shownIcons
    end

    -- Cache expensive computations
    local cacheKey = string.format("%s_%s_%s", name, tostring(settings.iconSize or 32), tostring(settings.spacing or 4))
    local vs = GetViewerState(viewer)
    local cached = vs.layoutCache
    if not cached or cached.cacheKey ~= cacheKey then
        local baseIconWidth, baseIconHeight = ComputeIconDimensions(settings)
        cached = {
            cacheKey = cacheKey,
            baseIconWidth = baseIconWidth,
            baseIconHeight = baseIconHeight,
            spacing = ComputeSpacing(settings),
            directions = {ResolveDirections(name, settings)},
            rowDimensions = {}
        }
        for preload = 1, 3 do
            local overrideSize = GetRowIconSize(settings, preload)
            local w, h = ComputeIconDimensions(settings, overrideSize)
            cached.rowDimensions[preload] = { width = w, height = h }
        end
        cached.appearanceKey = BuildAppearanceKey(cached.baseIconWidth, cached.baseIconHeight, cached.spacing, cached.rowDimensions)
        vs.layoutCache = cached
    end

    local baseIconWidth, baseIconHeight = cached.baseIconWidth, cached.baseIconHeight
    local spacing = cached.spacing
    local primary, secondary, rowLimit = unpack(cached.directions)
    local directionKey = BuildDirectionKey(primary, secondary, rowLimit)
    local rowDimensions = cached.rowDimensions
    local appearanceKey = cached.appearanceKey

    if vs.lastGrowthDirection ~= directionKey then
        vs.lastGrowthDirection = directionKey
        changed = true
    end

    if vs.lastAppearanceKey ~= appearanceKey then
        vs.lastAppearanceKey = appearanceKey
        changed = true
    end

    if vs.iconCount ~= count then
        vs.iconCount = count
        changed = true
    end

    if name == "BuffIconCooldownViewer" and vs.shownIconCount ~= shownCount then
        vs.shownIconCount = shownCount
        changed = true
    end

    -- Simplified spacing check - only check first few icons and cache result
    if name == "BuffIconCooldownViewer" and not changed and shownCount > 1 then
        local spacingCheckKey = string.format("%d_%d", shownCount, math.floor(time() / 5)) -- Check every 5 seconds
        if vs.lastSpacingCheck ~= spacingCheckKey then
            vs.lastSpacingCheck = spacingCheckKey
            -- Only check first 3 icon pairs for performance
            for i = 1, min(3, shownCount - 1) do
                local iconA = shownIcons[i]
                local iconB = shownIcons[i + 1]
                if iconA and iconB then
                    local x1 = iconA:GetCenter()
                    local x2 = iconB:GetCenter()
                    if x1 and x2 then
                        local widthA = (iconA.GetWidth and iconA:GetWidth()) or baseIconWidth
                        local expectedSpacing = widthA + spacing
                        local actualSpacing = abs(x2 - x1)
                        if abs(actualSpacing - expectedSpacing) > 2 then -- Increased tolerance
                            changed = true
                            break
                        end
                    end
                end
            end
        end
    end

    if changed then
        self:ApplyViewerLayout(viewer)

        if DDingUI.ResourceBars and DDingUI.ResourceBars.UpdatePowerBar then
            DDingUI.ResourceBars:UpdatePowerBar()
        end
        if DDingUI.ResourceBars and DDingUI.ResourceBars.UpdateSecondaryPowerBar then
            DDingUI.ResourceBars:UpdateSecondaryPowerBar()
        end
    end
end

DDingUI.ApplyViewerLayout = function(self, viewer) return IconViewers:ApplyViewerLayout(viewer) end
DDingUI.RescanViewer = function(self, viewer) return IconViewers:RescanViewer(viewer) end

-- ============================================
-- Buff Icon Centering (단순화된 버전)
-- 아이콘들을 viewer의 CENTER 기준으로 배치
-- anchor 조정 없음 - 넛지에서 viewer의 point를 CENTER로 설정해야 함
-- ============================================

local centerBuffsThrottle = 0.02
local nextCenterBuffsUpdate = 0

-- Reusable tables (avoid per-frame GC pressure)
local _visibleBuffIcons = {}
local _lastSortKey = ""

local function CenterBuffIcons()
    local currentTime = GetTime()
    if currentTime < nextCenterBuffsUpdate then return end
    nextCenterBuffsUpdate = currentTime + centerBuffsThrottle

    -- Skip during EditMode (check both IsShown and editModeActive)
    if EditModeManagerFrame then
        local inEditMode = false
        pcall(function()
            inEditMode = EditModeManagerFrame:IsShown() or EditModeManagerFrame.editModeActive
        end)
        if inEditMode then return end
    end

    local BuffIconCooldownViewer = _G["BuffIconCooldownViewer"]
    if not BuffIconCooldownViewer then return end

    local settings = DDingUI.db and DDingUI.db.profile.viewers["BuffIconCooldownViewer"]
    if settings and settings.enabled == false then return end
    if settings and settings.centerBuffs == false then return end

    -- 아이콘 수집 (reuse table)
    local visibleCount = 0
    for i = 1, select("#", BuffIconCooldownViewer:GetChildren()) do
        local childFrame = select(i, BuffIconCooldownViewer:GetChildren())
        if childFrame and (childFrame.Icon or childFrame.icon) and childFrame:IsShown() and not IsPlaceholderIcon(childFrame) then
            visibleCount = visibleCount + 1
            _visibleBuffIcons[visibleCount] = childFrame
        end
    end
    -- nil out excess entries
    for i = visibleCount + 1, #_visibleBuffIcons do
        _visibleBuffIcons[i] = nil
    end

    if visibleCount == 0 then return 0 end

    -- Sort key caching: skip sort if order unchanged
    local sortKey = ""
    for i = 1, visibleCount do
        local li = _visibleBuffIcons[i].layoutIndex or 0
        sortKey = sortKey .. tostring(li) .. ","
    end
    if sortKey ~= _lastSortKey then
        _lastSortKey = sortKey
        table.sort(_visibleBuffIcons, function(a, b)
            return (a.layoutIndex or 0) < (b.layoutIndex or 0)
        end)
    end

    -- 아이콘 크기
    local iconWidth = _visibleBuffIcons[1]:GetWidth()
    if not iconWidth or iconWidth <= 0 then
        iconWidth = (settings and settings.iconSize) or 32
    end
    local iconHeight = _visibleBuffIcons[1]:GetHeight()
    if not iconHeight or iconHeight <= 0 then
        iconHeight = iconWidth
    end

    -- isHorizontal 체크: 세로/가로 레이아웃 분기 -- [FIX: vertical layout support]
    local isHorizontal = BuffIconCooldownViewer.isHorizontal
    -- isHorizontal이 nil이면 기본 가로 레이아웃으로 처리
    if isHorizontal == nil then isHorizontal = true end

    local startX = 0
    local startY = 0
    -- [FIX] DDingUI spacing 설정 사용 (Blizzard childXPadding 대신)
    -- CenterBuffIcons가 ApplyViewerLayout과 같은 spacing을 써야 바 너비와 일치함
    local iconSpacing = settings and ComputeSpacing(settings) or (BuffIconCooldownViewer.childXPadding or 0)

    if isHorizontal then
        local totalWidth = (visibleCount * iconWidth) + ((visibleCount - 1) * iconSpacing)
        startX = -totalWidth / 2 + iconWidth / 2
        -- [FIX] __cdmIconWidth 동기화: 주자원바가 이 값을 읽어서 너비를 맞춤
        BuffIconCooldownViewer.__cdmIconWidth = PixelSnap(totalWidth)
    else
        local totalHeight = (visibleCount * iconHeight) + ((visibleCount - 1) * iconSpacing)
        startY = totalHeight / 2 - iconHeight / 2
    end

    for index, iconFrame in ipairs(_visibleBuffIcons) do
        iconFrame:ClearAllPoints()
        if isHorizontal then
            iconFrame:SetPoint("CENTER", BuffIconCooldownViewer, "CENTER", startX + (index - 1) * (iconWidth + iconSpacing), 0)
        else
            iconFrame:SetPoint("CENTER", BuffIconCooldownViewer, "CENTER", 0, startY - (index - 1) * (iconHeight + iconSpacing))
        end
    end

    return visibleCount
end

-- Conditional OnUpdate: only run when viewer is visible
local centerBuffsFrame = CreateFrame("Frame")
local centerBuffsActive = false

local function EnableCenterBuffs()
    if not centerBuffsActive then
        centerBuffsActive = true
        centerBuffsFrame:SetScript("OnUpdate", CenterBuffIcons)
    end
end
local function DisableCenterBuffs()
    if centerBuffsActive then
        centerBuffsActive = false
        centerBuffsFrame:SetScript("OnUpdate", nil)
    end
end

-- Setup conditional OnUpdate after viewer is created
local function SetupConditionalOnUpdate()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then return false end
    if viewer:IsShown() then EnableCenterBuffs() end
    hooksecurefunc(viewer, "Show", EnableCenterBuffs)
    hooksecurefunc(viewer, "Hide", DisableCenterBuffs)
    return true
end
if not SetupConditionalOnUpdate() then
    C_Timer.After(1, SetupConditionalOnUpdate)
end

-- 즉시 실행 버전 (throttle 무시, 캐시 무효화)
local function CenterBuffIconsImmediate()
    nextCenterBuffsUpdate = 0
    CenterBuffIcons()
end

-- UNIT_AURA 이벤트로 즉시 반응
local buffEventFrame = CreateFrame("Frame")
buffEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
buffEventFrame:SetScript("OnEvent", function(_, event, unit)
    if unit == "player" then
        -- 즉시 실행 (다음 프레임)
        C_Timer.After(0, CenterBuffIconsImmediate)
    end
end)

-- Export for external control
IconViewers.CenterBuffIcons = CenterBuffIcons
IconViewers.CenterBuffIconsImmediate = CenterBuffIconsImmediate
DDingUI.CenterBuffIcons = function(self) return CenterBuffIcons() end
DDingUI.CenterBuffIconsImmediate = function(self) return CenterBuffIconsImmediate() end

-- GROUP_ROSTER_UPDATE: re-layout viewers when party/raid state changes
do
    local viewers = DDingUI.viewers or { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
    local groupFrame = CreateFrame("Frame")
    groupFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    groupFrame:SetScript("OnEvent", function()
        for _, name in ipairs(viewers) do
            local viewer = _G[name]
            if viewer and viewer:IsShown() then
                local settings = DDingUI.db and DDingUI.db.profile.viewers[name]
                if settings and settings.groupOffsets then
                    IconViewers:ApplyViewerLayout(viewer)
                end
            end
        end
    end)
end
