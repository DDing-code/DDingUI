local ns = select(2, ...)
local DDingUI = ns.Addon

local DynamicLayout = {}
DDingUI.CustomIconDynamicLayout = DynamicLayout

function DynamicLayout.Create(
    runtime,
    CustomIcons,
    L,
    ApplyIconSettings,
    BuildDefaultSettings,
    BuildDefaultUngroupedPositionSettings,
    NormalizeAnchor,
    GetStartAnchorForGrowth,
    GetDefaultRowGrowth,
    NormalizeRowGrowth,
    GetStartAnchorForGrowthPair,
    GetDynamicDB,
    GetAnchorFrame,
    ShouldIconSpawn,
    IsIconLoadable,
    EnsureLoadConditions,
    CreateDynamicIcon,
    ReleaseDynamicIconFrame,
    ScheduleCustomIconWork,
    UpdateAllIcons,
    EnsureEventFrame
)
    local RefreshAllLayouts
    local function GetGroupSettings(groupKey)
        local db = GetDynamicDB()
        if groupKey == "ungrouped" then
            db.ungroupedSettings = db.ungroupedSettings or BuildDefaultSettings("RIGHT")
            NormalizeAnchor(db.ungroupedSettings)
            return db.ungroupedSettings
        end
        if db.iconData[groupKey] and db.ungrouped[groupKey] then
            db.ungroupedPositions = db.ungroupedPositions or {}
            db.ungroupedPositions[groupKey] = db.ungroupedPositions[groupKey] or BuildDefaultUngroupedPositionSettings()
            NormalizeAnchor(db.ungroupedPositions[groupKey])
            return db.ungroupedPositions[groupKey]
        end
        if db.groups[groupKey] then
            db.groups[groupKey].settings = db.groups[groupKey].settings or BuildDefaultSettings(db.groups[groupKey].growthDirection or "RIGHT")
            NormalizeAnchor(db.groups[groupKey].settings)
            return db.groups[groupKey].settings
        end
        local defaults = BuildDefaultSettings("RIGHT")
        NormalizeAnchor(defaults)
        return defaults
    end

    local function GetGroupDisplayName(groupKey)
        if groupKey == "ungrouped" then
            return L["Ungrouped"] or "Ungrouped"
        end
        local db = GetDynamicDB()
        if db.iconData[groupKey] and db.ungrouped[groupKey] then
            local iconData = db.iconData[groupKey]
            if iconData then
                if iconData.type == "item" then
                    return GetItemInfo(iconData.id) or ((L["Item"] or "Item") .. " " .. iconData.id)
                elseif iconData.type == "spell" then
                    local info = C_Spell.GetSpellInfo(iconData.id)
                    return (info and info.name) or ((L["Spell"] or "Spell") .. " " .. iconData.id)
                elseif iconData.type == "slot" then
                    return ((L["Slot"] or "Slot") .. " " .. (iconData.slotID or ""))
                elseif iconData.type == "trinketProc" then
                    local iid = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID or 13)
                    local itemName = iid and GetItemInfo(iid)
                    return itemName or ("Trinket " .. (iconData.slotID == 14 and "2" or "1"))
                end
            end
        end
        local group = db.groups[groupKey]
        if group and group.name and group.name ~= "" then
            return group.name
        end
        return groupKey
    end

    local function EnsureGroupFrame(groupKey, settings)
        settings = settings or GetGroupSettings(groupKey)
        NormalizeAnchor(settings)
        if runtime.groupFrames[groupKey] then
            return runtime.groupFrames[groupKey]
        end

        -- Create the main container frame
        local container = CreateFrame("Frame", "DDingUI_DynGroup_" .. groupKey, UIParent)
        container:SetSize(100, 100) -- Initial size, will be recalculated
        container:SetMovable(true) -- Container itself must be movable
        container:SetClampedToScreen(true)

        -- Note: Legacy anchor system removed - Movers system (/dduimove) handles positioning

        container._settings = settings
        container._groupKey = groupKey

        -- Position the container
        if settings.position then
            local anchorFrame = GetAnchorFrame(settings.anchorFrame)
            local containerPoint = settings.anchorFrom or GetStartAnchorForGrowth(settings.growthDirection or "RIGHT")
            local anchorPoint = settings.anchorTo or containerPoint
            container:ClearAllPoints()
            container:SetPoint(containerPoint, anchorFrame, anchorPoint, settings.position.x or 0, settings.position.y or 0)
        else
            local containerPoint = GetStartAnchorForGrowth(settings.growthDirection or "RIGHT")
            container:SetPoint(containerPoint, UIParent, containerPoint, 0, -200)
        end

        runtime.groupFrames[groupKey] = container
        return container
    end

    local function LayoutGroup(groupKey, iconKeys)
        -- [DYNAMIC] GroupSystem이 활성이면 레이아웃 스킵 (GroupRenderer가 대신 처리)
        if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
            return
        end
        local db = GetDynamicDB()
        local groupSettings = GetGroupSettings(groupKey)
        local growth = groupSettings.growthDirection or "RIGHT"
        local settings = groupSettings
        growth = settings.growthDirection or growth
        settings.rowGrowthDirection = settings.rowGrowthDirection or GetDefaultRowGrowth(growth)
        settings.rowGrowthDirection = NormalizeRowGrowth(growth, settings.rowGrowthDirection)

        if not iconKeys or #iconKeys == 0 then
            local container = runtime.groupFrames[groupKey]
            if container then
                container:Hide()
            end
            return
        end

        local container = EnsureGroupFrame(groupKey, settings)
        container:Show()

        local spacing = settings.spacing or 5
        local maxPerRow = settings.maxIconsPerRow
        if maxPerRow == nil and settings.maxColumns ~= nil then
            maxPerRow = settings.maxColumns
            settings.maxIconsPerRow = maxPerRow
            settings.maxColumns = nil
        end
        maxPerRow = maxPerRow or 10

        local iconSizes = {}

        for _, iconKey in ipairs(iconKeys) do
            local iconFrame = runtime.iconFrames[iconKey]
            if iconFrame then
                local iconData = db.iconData[iconKey]
                local borderSize = 0
                -- Store group settings on the frame for later use (UpdateDynamicIcon, UpdateAllIcons)
                iconFrame._groupSettings = groupSettings
                if iconData then
                    ApplyIconSettings(iconFrame, iconData, groupSettings)
                    borderSize = math.max((iconData.settings and iconData.settings.borderSize) or 0, 0)
                end
                local w, h = iconFrame:GetWidth(), iconFrame:GetHeight()
                table.insert(iconSizes, {width = w + borderSize * 2, height = h + borderSize * 2, border = borderSize})
            end
        end

        local startAnchor = GetStartAnchorForGrowthPair(growth, settings.rowGrowthDirection)

        local function borderInsetForAnchor(anchor, border)
            if not border or border <= 0 then return 0, 0 end
            local dx = (anchor:find("LEFT") and border) or -border
            local dy = (anchor:find("TOP") and -border) or border
            return dx, dy
        end

        -- Layout in offsets relative to container startAnchor (x right+, y up+)
        local positions = {}
        local minLeft, maxRight = 0, 0
        local minBottom, maxTop = 0, 0

        local rowBaseX, rowBaseY = 0, 0
        local along = 0
        local rowThickness = 0
        local countInRow = 0
        local iconGrowthIsHorizontal = (growth == "LEFT" or growth == "RIGHT")

        local function advanceRow()
            local step = rowThickness + spacing
            local rg = settings.rowGrowthDirection
            if rg == "RIGHT" then
                rowBaseX = rowBaseX + step
            elseif rg == "LEFT" then
                rowBaseX = rowBaseX - step
            elseif rg == "UP" then
                rowBaseY = rowBaseY + step
            else -- DOWN
                rowBaseY = rowBaseY - step
            end
            along = 0
            rowThickness = 0
            countInRow = 0
        end

        local function accumulateBounds(anchor, xOff, yOff, w, h)
            local left, right, top, bottom
            if anchor == "TOPLEFT" then
                left, right = xOff, xOff + w
                top, bottom = yOff, yOff - h
            elseif anchor == "TOPRIGHT" then
                right, left = xOff, xOff - w
                top, bottom = yOff, yOff - h
            elseif anchor == "BOTTOMLEFT" then
                left, right = xOff, xOff + w
                bottom, top = yOff, yOff + h
            else -- BOTTOMRIGHT
                right, left = xOff, xOff - w
                bottom, top = yOff, yOff + h
            end
            minLeft = math.min(minLeft, left)
            maxRight = math.max(maxRight, right)
            minBottom = math.min(minBottom, bottom)
            maxTop = math.max(maxTop, top)
        end

        for i, iconSize in ipairs(iconSizes) do
            local w, h = iconSize.width, iconSize.height
            local xOff, yOff = rowBaseX, rowBaseY

            if growth == "RIGHT" then
                xOff = rowBaseX + along
            elseif growth == "LEFT" then
                xOff = rowBaseX - along
            elseif growth == "UP" then
                yOff = rowBaseY + along
            else -- DOWN
                yOff = rowBaseY - along
            end

            positions[i] = {x = xOff, y = yOff, width = w, height = h, border = iconSize.border or 0}
            accumulateBounds(startAnchor, xOff, yOff, w, h)

            countInRow = countInRow + 1
            if iconGrowthIsHorizontal then
                along = along + w + spacing
                rowThickness = math.max(rowThickness, h)
            else
                along = along + h + spacing
                rowThickness = math.max(rowThickness, w)
            end

            if countInRow >= maxPerRow then
                advanceRow()
            end
        end

        local contentWidth = maxRight - minLeft
        local contentHeight = maxTop - minBottom
        if contentWidth <= 0 then
            contentWidth = container._lastLayoutW or 1
        end
        if contentHeight <= 0 then
            contentHeight = container._lastLayoutH or 1
        end

        for i, iconKey in ipairs(iconKeys) do
            local iconFrame = runtime.iconFrames[iconKey]
            local pos = positions[i]
            if iconFrame and pos then
                local dx, dy = borderInsetForAnchor(startAnchor, pos.border or 0)
                iconFrame:ClearAllPoints()
                iconFrame:SetParent(container)
                iconFrame:SetPoint(startAnchor, container, startAnchor, (pos.x or 0) + dx, (pos.y or 0) + dy)
                iconFrame:Show()
            end
        end

        container:SetSize(contentWidth, contentHeight)
        container._lastLayoutW = contentWidth
        container._lastLayoutH = contentHeight

        -- Re-apply anchor using stored anchor points
        if settings.position then
            local containerPoint = settings.anchorFrom or startAnchor
            local anchorFrame = GetAnchorFrame(settings.anchorFrame)
            local anchorPoint = settings.anchorTo or containerPoint
            container:ClearAllPoints()
            container:SetPoint(containerPoint, anchorFrame, anchorPoint, settings.position.x or 0, settings.position.y or 0)
        end
    end

    function runtime.RunBridgeLayoutRefresh()
        runtime.refreshAllLayoutsPending = nil
        runtime.layoutRefreshDueAt = nil
        if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
            DDingUI.SpecProfiles:MarkDirty()
        end
        if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
            DDingUI.DynamicIconBridge:NotifyIconsChanged(true)
        end
    end

    local function QueueBridgeLayoutRefresh(delay)
        if runtime.refreshAllLayoutsPending then return end
        runtime.refreshAllLayoutsPending = true
        runtime.layoutRefreshDueAt = (GetTime and GetTime() or 0) + (delay or 0)
        ScheduleCustomIconWork()
    end

    RefreshAllLayouts = function()
        if runtime.RequestCustomCooldownWatchRegistration then
            runtime.RequestCustomCooldownWatchRegistration()
        end
        if DDingUI.DynamicIconBridge and DDingUI.DynamicIconBridge:IsActive() then
            QueueBridgeLayoutRefresh((InCombatLockdown and InCombatLockdown()) and 0.12 or 0.04)
            return
        end

        -- SpecProfiles 자동 저장 트리거 (동적 아이콘 설정 변경 감지)
        if DDingUI.SpecProfiles and DDingUI.SpecProfiles.MarkDirty then
            DDingUI.SpecProfiles:MarkDirty()
        end
        local db = GetDynamicDB()

        -- Build ungrouped list (one anchor per ungrouped icon)
        local ungroupedKeys = {}
        for iconKey, _ in pairs(db.ungrouped) do
            table.insert(ungroupedKeys, iconKey)
        end
        table.sort(ungroupedKeys)
        for _, iconKey in ipairs(ungroupedKeys) do
            db.ungroupedPositions = db.ungroupedPositions or {}
            db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
            if ShouldIconSpawn(db.iconData[iconKey]) then
                LayoutGroup(iconKey, {iconKey})
            else
                local cont = runtime.groupFrames[iconKey]
                if cont then cont:Hide() end
                local frame = runtime.iconFrames[iconKey]
                if frame then frame:Hide() end
            end
        end

        -- Groups
        for groupKey, group in pairs(db.groups) do
            -- Check if group is enabled (default true for backwards compatibility)
            if group.enabled == false then
                -- Hide all icons in disabled group
                for _, k in ipairs(group.icons or {}) do
                    local frame = runtime.iconFrames[k]
                    if frame then frame:Hide() end
                end
                local container = runtime.groupFrames[groupKey]
                if container then container:Hide() end
            else
                local keys = {}
                local seen = {}
                for _, k in ipairs(group.icons or {}) do
                    if db.iconData[k] and not seen[k] and ShouldIconSpawn(db.iconData[k]) then
                        table.insert(keys, k)
                        seen[k] = true
                    else
                        local frame = runtime.iconFrames[k]
                        if frame then frame:Hide() end
                    end
                end
                LayoutGroup(groupKey, keys)
            end
        end
    end

    local function FindIconGroup(iconKey, db)
        if db.ungrouped[iconKey] then return "ungrouped" end
        for gk, group in pairs(db.groups) do
            for _, k in ipairs(group.icons or {}) do
                if k == iconKey then
                    return gk
                end
            end
        end
        return "ungrouped"
    end

    function CustomIcons:EnsureDynamicIconFrame(iconKey, iconData)
        if not iconKey then return nil end

        local frame = runtime.iconFrames[iconKey]
        if frame then return frame end

        local db = GetDynamicDB()
        iconData = iconData or (db.iconData and db.iconData[iconKey])
        if not iconData then return nil end

        EnsureLoadConditions(iconData)
        if not IsIconLoadable(iconData) then return nil end

        local groupKey = FindIconGroup(iconKey, db)
        local settings
        if groupKey == "ungrouped" or db.ungrouped[iconKey] then
            db.ungroupedPositions = db.ungroupedPositions or {}
            db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
            settings = db.ungroupedPositions[iconKey]
            groupKey = iconKey
        else
            settings = GetGroupSettings(groupKey)
        end

        frame = CreateDynamicIcon(iconKey, iconData, EnsureGroupFrame(groupKey, settings))
        if frame then
            runtime.iconFrames[iconKey] = frame
            if runtime.RequestCustomCooldownWatchRegistration then
                runtime.RequestCustomCooldownWatchRegistration()
            end
        end
        return frame
    end

    function CustomIcons:LoadDynamicIcons()
        EnsureEventFrame()
        local db = GetDynamicDB()

        -- 프로필 변경 시 기존 프레임 정리: db에 없는 아이콘 제거
        for iconKey, frame in pairs(runtime.iconFrames) do
            if not db.iconData[iconKey] then
                ReleaseDynamicIconFrame(iconKey, frame)
                runtime.iconFrames[iconKey] = nil
            end
        end
        -- 기존 그룹 프레임도 정리
        for groupKey, container in pairs(runtime.groupFrames) do
            if not db.groups[groupKey] and not db.ungrouped[groupKey] and not db.iconData[groupKey] then
                container:Hide()
                container:SetParent(nil)
                runtime.groupFrames[groupKey] = nil
            end
        end

        -- [FIX] 프레임 생성 실패한 아이콘 수집 (아이템 캐시 미준비 등)
        local pendingKeys = {}
        local timeSinceLogin = GetTime() - (runtime.loginTime or GetTime())
        for iconKey, iconData in pairs(db.iconData) do
            EnsureLoadConditions(iconData)
            local isLoadable = IsIconLoadable(iconData)

            -- [FIX] 로그인 직후(10초 이내) 스펠북이 준비 안 되어 false를 반환하는 경우 실패로 간주하지 않고 재시도 대기열에 추가
            if not isLoadable and timeSinceLogin < 10 then
                pendingKeys[#pendingKeys + 1] = iconKey
                if iconData.type == "spell" and iconData.id and C_Spell and C_Spell.RequestLoadSpellData then
                    pcall(C_Spell.RequestLoadSpellData, iconData.id)
                end
            elseif isLoadable then
                local groupKey = FindIconGroup(iconKey, db)
                local settings
                if groupKey == "ungrouped" or db.ungrouped[iconKey] then
                    db.ungroupedPositions = db.ungroupedPositions or {}
                    db.ungroupedPositions[iconKey] = db.ungroupedPositions[iconKey] or BuildDefaultUngroupedPositionSettings()
                    settings = db.ungroupedPositions[iconKey]
                    groupKey = iconKey
                else
                    settings = GetGroupSettings(groupKey)
                end
                local parent = EnsureGroupFrame(groupKey, settings)
                local frame = runtime.iconFrames[iconKey]
                if not frame then
                    frame = CreateDynamicIcon(iconKey, iconData, parent)
                    if frame then
                        runtime.iconFrames[iconKey] = frame
                    else
                        -- 프레임 생성 실패 → 재시도 목록에 추가
                        pendingKeys[#pendingKeys + 1] = iconKey
                        -- 아이템 데이터 프리로드 요청
                        if iconData.type == "item" and iconData.id and C_Item and C_Item.RequestLoadItemDataByID then
                            C_Item.RequestLoadItemDataByID(iconData.id)
                        elseif iconData.type == "trinketProc" and iconData.slotID then
                            local itemID = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID)
                            if itemID and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                        elseif iconData.type == "slot" and iconData.slotID then
                            local itemID = CustomIcons.GetEquippedSlotItemID(nil, iconData.slotID)
                            if itemID and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                        elseif iconData.type == "spell" and iconData.id then
                            if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, iconData.id) end
                        end
                    end
                end
                if frame then
                    frame._ddDeferredLoadRelease = nil
                end
            else
                -- Hide/clear frames for spells not in the spellbook
                local frame = runtime.iconFrames[iconKey]
                if frame then
                    if InCombatLockdown and InCombatLockdown() then
                        frame._ddDeferredLoadRelease = true
                        if iconData.type == "spell" and iconData.id and C_Spell and C_Spell.RequestLoadSpellData then
                            pcall(C_Spell.RequestLoadSpellData, iconData.id)
                        end
                    else
                        ReleaseDynamicIconFrame(iconKey, frame)
                        runtime.iconFrames[iconKey] = nil
                    end
                end
            end
        end

        -- [FIX] GroupSystem이 활성이면 CustomIcons 자체 프레임을 즉시 숨김
        -- CreateDynamicIcon이 Show()를 호출하여 리로드 시 회색 프레임이 잠깐 보이는 것 방지
        -- GroupSystem이 자체 레이아웃으로 관리하므로 CustomIcons 프레임은 보일 필요 없음
        local bridge = DDingUI.DynamicIconBridge
        if bridge and bridge:IsActive() then
            for _, frame in pairs(runtime.iconFrames) do
                if frame and frame.Hide and not frame._ddIsManaged then
                    frame:Hide()
                end
            end
            for _, container in pairs(runtime.groupFrames) do
                if container and container.Hide then
                    container:Hide()
                end
            end
        end

        RefreshAllLayouts()
        -- Initial update to ensure icons show correct state
        UpdateAllIcons(nil, "all")

        -- [FIX] 프레임 생성 실패한 아이콘 재시도 (아이템/스펠 캐시 로드 대기)
        if #pendingKeys > 0 then
            local attempts = 0
            local maxAttempts = 5
            local retryTimer
            retryTimer = C_Timer.NewTicker(1.0, function()
                attempts = attempts + 1
                local stillPending = {}
                for _, iconKey in ipairs(pendingKeys) do
                    if not runtime.iconFrames[iconKey] then
                        local iconData = db.iconData[iconKey]
                        if iconData then
                            local groupKey = FindIconGroup(iconKey, db)
                            local settings
                            if groupKey == "ungrouped" or db.ungrouped[iconKey] then
                                settings = db.ungroupedPositions and db.ungroupedPositions[iconKey]
                                groupKey = iconKey
                            else
                                settings = GetGroupSettings(groupKey)
                            end
                            local parent = EnsureGroupFrame(groupKey, settings)
                            local frame = CreateDynamicIcon(iconKey, iconData, parent)
                            if frame then
                                runtime.iconFrames[iconKey] = frame
                            else
                                stillPending[#stillPending + 1] = iconKey
                            end
                        end
                    end
                end
                pendingKeys = stillPending
                if #pendingKeys == 0 or attempts >= maxAttempts then
                    if retryTimer then retryTimer:Cancel() end
                    RefreshAllLayouts()
                    UpdateAllIcons(nil, "all")
                end
            end)
        end
    end

    function CustomIcons:CreateCustomIconsTrackerFrame()
        if not DDingUI.db.profile.customIcons.enabled then return nil end

        -- Create the main container frame (for backwards compatibility)
        if not DDingUI.customIconsTrackerFrame then
            DDingUI.customIconsTrackerFrame = CreateFrame("Frame", "DDingUI_CustomIconsTrackerFrame", UIParent)
            DDingUI.customIconsTrackerFrame:SetSize(200, 40)
            DDingUI.customIconsTrackerFrame:SetFrameStrata("MEDIUM")
            DDingUI.customIconsTrackerFrame:SetClampedToScreen(true)
            DDingUI.customIconsTrackerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            DDingUI.customIconsTrackerFrame._DDingUI_CustomIconsTracker = true
        end

        -- Load all dynamic icons
        self:LoadDynamicIcons()

        return DDingUI.customIconsTrackerFrame
    end


    return GetGroupSettings, GetGroupDisplayName, EnsureGroupFrame, RefreshAllLayouts
end
