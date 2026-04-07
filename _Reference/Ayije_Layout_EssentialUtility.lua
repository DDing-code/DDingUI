local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local ctx = CDM._LayoutCtx

local CDM_C = ctx.CDM_C
local GetFrameData = ctx.GetFrameData
local VIEWERS = ctx.VIEWERS
local defensivesHiddenSet = ctx.defensivesHiddenSet

local ResolveBaseSpellID = ctx.ResolveBaseSpellID
local ToSortNumber = ctx.ToSortNumber
local GetLayoutConfig = ctx.GetLayoutConfig
local QueueReanchorRetry = ctx.QueueReanchorRetry
local ComputeEssentialOrUtilityPosition = ctx.ComputeEssentialOrUtilityPosition
local ComputeEssentialContainerSize = ctx.ComputeEssentialContainerSize
local ComputeUtilityContainerSize = ctx.ComputeUtilityContainerSize

local tempIconPositionRecords = {}
local tempIconPositionRecordPool = {}
local tempIconPositionRecordCount = 0
local nextStableFrameSortID = 0
local tempTrinketReorder = {}
local math_floor = math.floor
local GetPixelSizeForRegion = CDM_C.GetPixelSizeForRegion
local ToPixelCountForFrame = CDM_C.ToPixelCountForRegion
local PixelsToUIForRegion = CDM_C.PixelsToUIForRegion
local SetPointPixels = CDM_C.SetPointPixels

local function SnapFrameTopLeftToPixelGrid(frame)
    if not frame or not frame.GetPoint then return end

    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if not point then
        return
    end

    local onePixel = GetPixelSizeForRegion and GetPixelSizeForRegion(frame)
    if not onePixel or onePixel <= 0 then
        return
    end

    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then
        return
    end

    local snappedLeft = (CDM_C.SnapOffsetToPixel and CDM_C.SnapOffsetToPixel(left, frame)) or left
    local snappedTop = (CDM_C.SnapOffsetToPixel and CDM_C.SnapOffsetToPixel(top, frame)) or top
    local dx = snappedLeft - left
    local dy = snappedTop - top

    if math.abs(dx) < (onePixel * 0.05) and math.abs(dy) < (onePixel * 0.05) then
        return
    end

    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, (xOfs or 0) + dx, (yOfs or 0) + dy)
end

local function ResizeLayoutContainerIfAllowed(container, inCombat, width, height)
    if inCombat or not container or not width or not height then
        return
    end
    container:SetSize(width, height)
    -- Containers are center/top anchored; snap rendered top-left after resize so
    -- child TOPLEFT offsets remain aligned to the pixel grid.
    SnapFrameTopLeftToPixelGrid(container)
end

local function PlaceIconTopLeft(frame, container, x, y, usePixelOffsets, pixelRegion)
    if not frame then
        return
    end

    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    if usePixelOffsets then
        SetPointPixels(frame, "TOPLEFT", container, "TOPLEFT", x or 0, y or 0, pixelRegion or frame)
    else
        frame:SetPoint("TOPLEFT", container, "TOPLEFT", x or 0, y or 0)
    end
    frame:Show()
end

local function GetStableFrameSortID(frame)
    local frameData = GetFrameData(frame)
    local sortID = frameData.cdmStableSortID
    if sortID then
        return sortID
    end
    nextStableFrameSortID = nextStableFrameSortID + 1
    frameData.cdmStableSortID = nextStableFrameSortID
    return nextStableFrameSortID
end

ctx.GetStableFrameSortID = GetStableFrameSortID

local function ResetTempIconPositionRecords()
    for i = 1, tempIconPositionRecordCount do
        tempIconPositionRecords[i] = nil
    end
    tempIconPositionRecordCount = 0
end

local function AcquireTempIconPositionRecord()
    tempIconPositionRecordCount = tempIconPositionRecordCount + 1
    local record = tempIconPositionRecordPool[tempIconPositionRecordCount]
    if not record then
        record = {}
        tempIconPositionRecordPool[tempIconPositionRecordCount] = record
    end
    tempIconPositionRecords[tempIconPositionRecordCount] = record
    return record
end

local function PushTempIconPositionRecord(frame, layoutIndex, sortID)
    local record = AcquireTempIconPositionRecord()
    record.frame = frame
    record.layoutIndex = layoutIndex
    record.sortID = sortID
    return record
end

local function CompareIconPositionRecords(a, b)
    if a.layoutIndex ~= b.layoutIndex then
        return a.layoutIndex < b.layoutIndex
    end

    return a.sortID < b.sortID
end

function CDM:PositionEssentialOrUtilityIcons(icons, viewer, vName)
    local sizeEssRow1, sizeEssRow2, sizeUtility, _, spacing, maxRowEss, _, maxRowUtil, utilityVertical = GetLayoutConfig()
    ResetTempIconPositionRecords()

    local isEssential = (vName == VIEWERS.ESSENTIAL)

    local injectedTrinketCount = 0
    local injFrames = isEssential and CDM.GetTrinketInjectionFrames and CDM.GetTrinketInjectionFrames() or nil

    if #icons == 0 and not injFrames then return end

    local container = self:GetOrCreateAnchorContainer(viewer)
    if not container then return end

    local missingDataCount = 0
    for _, frame in ipairs(icons) do
        local spellID = ResolveBaseSpellID(frame)
        if spellID and defensivesHiddenSet[spellID] then
            frame:ClearAllPoints()
            frame:SetParent(viewer)
            frame:Hide()
        elseif spellID or frame.cooldownInfo then
            PushTempIconPositionRecord(frame, ToSortNumber(frame.layoutIndex, 0), GetStableFrameSortID(frame))
        else
            missingDataCount = missingDataCount + 1
        end
    end

    local db = CDM.db or {}
    local injRow = db.trinketsEssentialRow or 1
    local injPos = db.trinketsEssentialPosition or "end"

    if injFrames then
        for i, tFrame in ipairs(injFrames) do
            local record = AcquireTempIconPositionRecord()
            record.frame = tFrame
            if injPos == "start" then
                record.layoutIndex = -1000 + i
            else
                record.layoutIndex = 99000 + i
            end
            record.sortID = 90000 + (tFrame.slotID or i)
        end
        injectedTrinketCount = #injFrames

        if injRow == 2 then
            local essOnlyCount = tempIconPositionRecordCount - injectedTrinketCount
            maxRowEss = math.min(maxRowEss, essOnlyCount)
        end
    end

    local totalIcons = tempIconPositionRecordCount
    if totalIcons > 1 then
        table.sort(tempIconPositionRecords, CompareIconPositionRecords)
    end

    if injectedTrinketCount > 0 then
        if injRow == 2 and injPos == "start" then
            table.wipe(tempTrinketReorder)
            for i = 1, injectedTrinketCount do
                tempTrinketReorder[i] = tempIconPositionRecords[i]
            end
            for i = 1, maxRowEss do
                tempIconPositionRecords[i] = tempIconPositionRecords[injectedTrinketCount + i]
            end
            for i = 1, injectedTrinketCount do
                tempIconPositionRecords[maxRowEss + i] = tempTrinketReorder[i]
            end

        elseif injRow == 1 and injPos == "end" and totalIcons > maxRowEss then
            local insertPos = math.max(1, maxRowEss - injectedTrinketCount + 1)
            table.wipe(tempTrinketReorder)
            for i = 1, injectedTrinketCount do
                tempTrinketReorder[i] = tempIconPositionRecords[totalIcons - injectedTrinketCount + i]
            end
            for i = totalIcons - injectedTrinketCount, insertPos, -1 do
                tempIconPositionRecords[i + injectedTrinketCount] = tempIconPositionRecords[i]
            end
            for i = 1, injectedTrinketCount do
                tempIconPositionRecords[insertPos + i - 1] = tempTrinketReorder[i]
            end
        end
    end

    local placements = {}
    local rowBuckets = {}
    local rowOrderSeen = {}
    local useMeasuredHorizontalLayout = isEssential or (not utilityVertical)

    for index, record in ipairs(tempIconPositionRecords) do
        local frame = record.frame
        local row, _, _, _, x, y = ComputeEssentialOrUtilityPosition(
            index, totalIcons, isEssential, sizeEssRow1, sizeEssRow2, sizeUtility, spacing, maxRowEss, maxRowUtil, utilityVertical
        )

        GetFrameData(frame).cdmRow = row

        self:ApplyStyle(frame, vName)
        local placement = {
            frame = frame,
            row = row,
            x = x,
            y = y,
        }
        placements[#placements + 1] = placement

        if useMeasuredHorizontalLayout then
            local bucket = rowBuckets[row]
            if not bucket then
                bucket = {}
                rowBuckets[row] = bucket
                rowOrderSeen[#rowOrderSeen + 1] = row
            end
            bucket[#bucket + 1] = placement
        end
    end

    local containerWidth, containerHeight
    if isEssential then
        containerWidth, containerHeight = ComputeEssentialContainerSize(
            totalIcons, sizeEssRow1, sizeEssRow2, spacing, maxRowEss
        )
    else
        containerWidth, containerHeight = ComputeUtilityContainerSize(
            totalIcons, sizeUtility, spacing, maxRowUtil, utilityVertical
        )
    end

    local inCombat = InCombatLockdown()
    local gapPx = (CDM_C.GetCooldownIconGapPixels and CDM_C.GetCooldownIconGapPixels(spacing, UIParent))
        or ToPixelCountForFrame(container, spacing, 0)

    if useMeasuredHorizontalLayout and #placements > 0 then
        table.sort(rowOrderSeen)

        local containerWidthPx = 0
        local containerHeightPx = 0
        local rowMetrics = {}

        for orderIndex, row in ipairs(rowOrderSeen) do
            local bucket = rowBuckets[row]
            local rowWidthPx = 0
            local rowHeightPx = 0

            for i, placement in ipairs(bucket) do
                local f = placement.frame
                -- Measure on the container/UIParent pixel grid (final placement space),
                -- not the frame's pre-reparent effective scale.
                local wPx = ToPixelCountForFrame(container, f:GetWidth() or 0, 1)
                local hPx = ToPixelCountForFrame(container, f:GetHeight() or 0, 1)
                placement._wPx = wPx
                placement._hPx = hPx
                rowWidthPx = rowWidthPx + wPx
                if i > 1 then
                    rowWidthPx = rowWidthPx + gapPx
                end
                if hPx > rowHeightPx then
                    rowHeightPx = hPx
                end
            end

            containerWidthPx = math.max(containerWidthPx, rowWidthPx)
            if orderIndex > 1 then
                containerHeightPx = containerHeightPx + gapPx
            end
            rowMetrics[row] = {
                widthPx = rowWidthPx,
                heightPx = rowHeightPx,
                topPx = containerHeightPx,
            }
            containerHeightPx = containerHeightPx + rowHeightPx
        end

        if containerWidthPx > 0 and containerHeightPx > 0 then
            containerWidth = PixelsToUIForRegion(containerWidthPx, container)
            containerHeight = PixelsToUIForRegion(containerHeightPx, container)
        end

        ResizeLayoutContainerIfAllowed(container, inCombat, containerWidth, containerHeight)

        for _, row in ipairs(rowOrderSeen) do
            local bucket = rowBuckets[row]
            local metrics = rowMetrics[row]
            local leftPadPx = math_floor(math.max(0, (containerWidthPx - metrics.widthPx)) * 0.5)
            local cursorPx = leftPadPx
            local yPx = -(metrics.topPx or 0)

            for _, placement in ipairs(bucket) do
                local frame = placement.frame
                PlaceIconTopLeft(frame, container, cursorPx, yPx, true, frame)
                cursorPx = cursorPx + (placement._wPx or 0) + gapPx
            end
        end
    else
        ResizeLayoutContainerIfAllowed(container, inCombat, containerWidth, containerHeight)

        for _, placement in ipairs(placements) do
            local frame = placement.frame
            PlaceIconTopLeft(frame, container, placement.x, placement.y, false)
        end
    end

    if not inCombat then
        local viewerFrame = _G[vName]
        if viewerFrame then
            viewerFrame:ClearAllPoints()
            viewerFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            viewerFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        end

    else
        CDM.combatDirtyViewers[vName] = true
    end

    if missingDataCount > 0 and not self.pendingSpecChange and not self.pendingTalentChange then
        QueueReanchorRetry(self, vName, 0.05)
    end

end
