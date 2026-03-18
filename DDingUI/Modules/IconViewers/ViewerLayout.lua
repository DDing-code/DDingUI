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

-- ============================================
-- CDM Viewer Proxy Anchors (더미 앵커 프레임)
-- CDM 뷰어가 재생성되어도 프록시는 항상 존재 → 앵커 끊어짐/엘레베이터 방지
-- ResourceBars, CastBars 등은 CDM 뷰어 대신 프록시에 앵커링
-- 편집모드에서도 안정적인 앵커 선택지 제공
-- ============================================

local PROXY_MAP = {
    ["EssentialCooldownViewer"] = "DDingUI_Anchor_Cooldowns",
    ["UtilityCooldownViewer"]   = "DDingUI_Anchor_Utility",
    ["BuffIconCooldownViewer"]  = "DDingUI_Anchor_Buffs",
}

-- 프록시 → 대응 그룹 이름
local VIEWER_TO_GROUP_NAME = {
    ["EssentialCooldownViewer"] = "Cooldowns",
    ["UtilityCooldownViewer"]   = "Utility",
    ["BuffIconCooldownViewer"]  = "Buffs",
}

-- 역방향 맵핑 (프록시 이름 → 뷰어 이름)
local PROXY_TO_VIEWER = {}
for viewerName, proxyName in pairs(PROXY_MAP) do
    PROXY_TO_VIEWER[proxyName] = viewerName
end

local proxyFrames = {}

local function CreateProxyAnchors()
    for viewerName, proxyName in pairs(PROXY_MAP) do
        if not proxyFrames[viewerName] then
            local proxy = CreateFrame("Frame", proxyName, UIParent)
            -- [FIX] 리로드 시 CDM 뷰어 준비 전까지 합리적인 기본 크기 사용
            -- 아이콘 36px × 5칸 + 간격 2px × 4 = 188, 세로 36px
            proxy:SetSize(188, 36)
            proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            proxy:Show()
            proxy._isProxyAnchor = true
            proxy._sourceViewer = viewerName
            proxyFrames[viewerName] = proxy
        end
    end
end

-- CDM 뷰어 → _CDM_Container 이름 매핑 (Containers.lua의 CreateBaseContainer 패턴)
-- CDM이 anchorContainers = {} 으로 Lua 테이블을 wipe 해도
-- 전역 _G["EssentialCooldownViewer_CDM_Container"] 프레임 자체는 파괴되지 않음
-- → 뷰어가 일시적으로 숨겨져도 컨테이너는 올바른 위치/크기를 유지
local VIEWER_TO_CDM_CONTAINER = {
    ["EssentialCooldownViewer"] = "EssentialCooldownViewer_CDM_Container",
    ["UtilityCooldownViewer"]   = "UtilityCooldownViewer_AnchorContainer",
    ["BuffIconCooldownViewer"]  = "BuffIconCooldownViewer_CDM_Container",
}

-- 프록시 → CDM 뷰어/그룹 위치/크기 동기화
-- 프록시와 소스 모두 UIParent 자식 → 동일 좌표계
local PROXY_SYNC_THROTTLE = 0.05
local _nextProxySyncTime = 0

local function SyncProxyAnchors()
    local now = GetTime()
    if now < _nextProxySyncTime then return end
    _nextProxySyncTime = now + PROXY_SYNC_THROTTLE

    -- [FIX] 전투 중에는 프록시 조작 스킵 (전역 이름 프레임 → taint 위험)
    if InCombatLockdown() then return end

    local uiCX, uiCY = UIParent:GetCenter()
    if not uiCX or not uiCY then return end

    for viewerName, proxy in pairs(proxyFrames) do
        local groupName = VIEWER_TO_GROUP_NAME[viewerName]
        local groupFrame = groupName and _G["DDingUI_Group_" .. groupName]
        local cdmContainerName = VIEWER_TO_CDM_CONTAINER[viewerName]
        local cdmContainer = cdmContainerName and _G[cdmContainerName]
        local viewer = _G[viewerName]

        if groupFrame then
            -- [핵심 3대 그룹] 크기는 LayoutGroup (GroupRenderer.lua)에서 직접 proxy:SetSize 호출
            -- 여기서 중복 호출하면 mover hookscript와 경쟁하여 깜빡임 유발
            -- __cdmIconWidth만 미러링
            proxy.__cdmIconWidth = groupFrame.__cdmIconWidth
            -- [FIX] GroupRenderer가 아직 LayoutGroup을 실행하지 않아 proxy가 1x1이면
            -- groupFrame 크기 또는 DB iconSize fallback 적용 (프록시 "없음" 방지)
            if proxy:GetWidth() <= 1 or proxy:GetHeight() <= 1 then
                local gw, gh = groupFrame:GetWidth(), groupFrame:GetHeight()
                if gw and gw > 1 and gh and gh > 1 then
                    proxy:SetSize(gw, gh)
                    proxy.__cdmIconWidth = gw
                else
                    -- groupFrame도 아직 크기 없으면 DB 기반 fallback
                    local viewerSettings = DDingUI.db and DDingUI.db.profile
                        and DDingUI.db.profile.viewers and DDingUI.db.profile.viewers[viewerName]
                    local iconSize = viewerSettings and viewerSettings.iconSize or 32
                    proxy:SetSize(iconSize, iconSize)
                    proxy.__cdmIconWidth = iconSize
                end
            end
            local gsEnabled = DDingUI.db and DDingUI.db.profile.groupSystem and DDingUI.db.profile.groupSystem.enabled
            local gSettings = DDingUI.db and DDingUI.db.profile.groupSystem and DDingUI.db.profile.groupSystem.groups and DDingUI.db.profile.groupSystem.groups[groupName]
            if gsEnabled and gSettings and gSettings.enabled ~= false then
                proxy:Show()
            else
                proxy:Hide()
            end
        else
            -- [GroupSystem 비활성] CDM 뷰어/컨테이너 → 프록시 정방향 동기화
            local sourceFrame = cdmContainer or viewer

            -- [FIX] 프록시가 Mover에 등록되어 있으면 좌표 덮어쓰기 금지
            -- Mover가 프록시 위치의 마스터 — SyncProxyAnchors가 뷰어 좌표로 오염하면
            -- GroupSystem Disable↔Enable 갭에서 Mover가 설정한 좌표가 파괴됨
            local proxyName = PROXY_MAP[viewerName]
            local isMoverManaged = proxyName and DDingUI.Movers
                and DDingUI.Movers.CreatedMovers
                and DDingUI.Movers.CreatedMovers[proxyName]

            if sourceFrame then
                -- 좌표 동기화: Mover 미등록 상태에서만 (초기 로드 등)
                if not isMoverManaged then
                    local cx, cy = sourceFrame:GetCenter()
                    if cx and cy then
                        local ox = cx - uiCX
                        local oy = cy - uiCY
                        proxy:ClearAllPoints()
                        proxy:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
                        proxy._lastValidOX = ox
                        proxy._lastValidOY = oy
                    elseif proxy._lastValidOX and proxy._lastValidOY then
                        proxy:ClearAllPoints()
                        proxy:SetPoint("CENTER", UIParent, "CENTER", proxy._lastValidOX, proxy._lastValidOY)
                    end
                end

                -- 크기 미러링 (Mover 등록 여부와 무관하게 항상 동기화)
                local w, h = sourceFrame:GetWidth(), sourceFrame:GetHeight()
                if sourceFrame.__cdmIconWidth and sourceFrame.__cdmIconWidth > 0 then
                    w = sourceFrame.__cdmIconWidth
                end
                if w and w > 0 and h and h > 0 then
                    proxy:SetSize(w, h)
                    proxy.__cdmIconWidth = sourceFrame.__cdmIconWidth
                    proxy._lastValidW = w
                    proxy._lastValidH = h
                elseif proxy._lastValidW and proxy._lastValidH then
                    proxy:SetSize(proxy._lastValidW, proxy._lastValidH)
                    proxy.__cdmIconWidth = proxy._lastValidW
                end
                local vSettings = DDingUI.db and DDingUI.db.profile.viewers and DDingUI.db.profile.viewers[viewerName]
                if not vSettings or vSettings.enabled ~= false then
                    proxy:Show()
                else
                    proxy:Hide()
                end
            else
                -- [FIX] 소스 프레임 미생성 시 DB 설정 기반 기본 크기 적용
                -- 리로드 후 강화효과 미활성 → 뷰어 프레임 없음 → 프록시 1x1 → 편집모드에서 안 보임
                if proxy:GetWidth() <= 1 or proxy:GetHeight() <= 1 then
                    local viewerSettings = DDingUI.db and DDingUI.db.profile
                        and DDingUI.db.profile.viewers and DDingUI.db.profile.viewers[viewerName]
                    local iconSize = viewerSettings and viewerSettings.iconSize or 32
                    proxy:SetSize(iconSize, iconSize)
                    proxy.__cdmIconWidth = iconSize
                end
                local vSettings = DDingUI.db and DDingUI.db.profile.viewers and DDingUI.db.profile.viewers[viewerName]
                if not vSettings or vSettings.enabled ~= false then
                    proxy:Show()
                else
                    proxy:Hide()
                end
            end
        end
    end
end

-- 프록시 앵커 생성 및 동기화 OnUpdate 설정
CreateProxyAnchors()

local proxySyncFrame = CreateFrame("Frame")
proxySyncFrame:SetScript("OnUpdate", SyncProxyAnchors)

-- Export
DDingUI.ProxyAnchors = proxyFrames
DDingUI.PROXY_MAP = PROXY_MAP
DDingUI.PROXY_TO_VIEWER = PROXY_TO_VIEWER

-- 프록시 크기 캐시 무효화 (프로필/전문화 전환 시 호출)
-- _lastSyncW/H를 nil로 리셋 → 다음 SyncProxyAnchors에서 강제 갱신
function DDingUI:InvalidateProxySizeCache()
    for _, proxy in pairs(proxyFrames) do
        proxy._lastSyncW = nil
        proxy._lastSyncH = nil
    end
    _nextProxySyncTime = 0
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
    -- [FIX] 전투 중 CDM이 프레임 재사용 시 layoutIndex가 일시적으로 nil일 수 있음
    -- layoutIndex만으로 판단하면 실제 활성 버프를 placeholder로 필터링하는 버그 발생
    -- Ayije_CDM 패턴: cooldownInfo/IsActive/cooldownID 등 복합 체크
    if not iconFrame then return true end

    -- layoutIndex가 존재하면 확실히 활성 아이콘
    local ok, hasLayout = pcall(function()
        return iconFrame.layoutIndex ~= nil
    end)
    if ok and hasLayout then return false end

    -- layoutIndex가 nil이더라도 다른 방법으로 활성 상태 판단
    -- cooldownInfo: CDM이 쿨다운 데이터를 할당한 프레임
    if iconFrame.cooldownInfo then return false end
    -- cooldownID: CDM이 쿨다운 ID를 할당한 프레임
    local okID, hasCooldownID = pcall(function()
        return iconFrame.cooldownID ~= nil
    end)
    if okID and hasCooldownID then return false end
    -- IsActive: CDM 프레임의 활성 상태 메서드
    if iconFrame.IsActive and type(iconFrame.IsActive) == "function" then
        local okActive, isActive = pcall(iconFrame.IsActive, iconFrame)
        if okActive and isActive then return false end
    end

    -- 모든 체크 실패 → placeholder
    return true
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
            -- [FIX] layoutIndex가 secret value일 수 있으므로 pcall로 안전하게 체크
            local hasLayout = false
            pcall(function() hasLayout = icon.layoutIndex ~= nil end)
            if not hasLayout and not icon:GetID() then
                local id = GetIconData(icon)
                if not id.creationOrder then
                    id.creationOrder = index
                end
            end
        end
    end

    -- [FIX] secret value 안전 비교 (Ayije_CDM ToSortNumber 패턴)
    local function SafeLayoutIndex(frame)
        local val = 0
        pcall(function()
            local li = frame.layoutIndex
            if li and type(li) == "number" then val = li end
        end)
        if val == 0 then
            val = frame:GetID() or 0
        end
        if val == 0 then
            local id = iconData[frame]
            val = (id and id.creationOrder) or 0
        end
        return val
    end

    table.sort(icons, function(a, b)
        local la = SafeLayoutIndex(a)
        local lb = SafeLayoutIndex(b)
        if la == lb then
            local aid = iconData[a]
            local bid = iconData[b]
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
-- [REFACTOR] Use viewerState weak table instead of writing __dduiOrigAnchors
-- directly onto CooldownViewer frames (prevents taint propagation to EditMode)
local function SaveOriginalAnchors(viewer)
    local state = GetViewerState(viewer)
    if state.origAnchors then return end
    local n = viewer:GetNumPoints()
    if n == 0 then return end
    state.origAnchors = {}
    for i = 1, n do
        local point, relativeTo, relativePoint, offsetX, offsetY = viewer:GetPoint(i)
        table.insert(state.origAnchors, { point, relativeTo, relativePoint, offsetX, offsetY })
    end
end

local function RestoreOriginalAnchors(viewer)
    local state = GetViewerState(viewer)
    local saved = state.origAnchors
    if not saved or #saved == 0 then return end
    viewer:ClearAllPoints()
    for _, a in ipairs(saved) do
        viewer:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end
    state.origAnchors = nil
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

-- [FIX] CMC Runtime:IsReady() 패턴: 뷰어가 아직 초기화되지 않았으면 레이아웃 스킵
-- EditMode 레이아웃 적용 중이거나 뷰어가 IsInitialized() false이면 건드리지 않음
-- ApplyViewerLayout/RescanViewer/CenterBuffIcons 등 모든 뷰어 함수에서 사용
local function IsViewerReady(viewer)
    if not viewer then return false end
    -- IsInitialized가 없는 뷰어는 (이미 초기화된 것으로) 통과
    if viewer.IsInitialized and not viewer:IsInitialized() then return false end
    -- EditMode 레이아웃 적용 중이면 스킵 (secret value / taint 방지)
    if EditModeManagerFrame and EditModeManagerFrame.layoutApplyInProgress then return false end
    return true
end
-- Export for external use
IconViewers.IsViewerReady = IsViewerReady

function IconViewers:ApplyViewerLayout(viewer)
    if not viewer or not viewer.GetName then return end
    -- [FIX] CMC IsReady 패턴: 뷰어 초기화 미완료 시 스킵 (3개 뷰어 모두 적용)
    if IsViewerReady and not IsViewerReady(viewer) then return end
    -- Skip during EditMode to prevent overriding Blizzard nudge/snap positioning
    if IsInEditMode() then return end
    -- FlightHide: skip layout during flight
    if DDingUI.FlightHide and DDingUI.FlightHide.isActive then return end
    -- [REPARENT] GroupSystem이 활성 상태면 ViewerLayout 완전 스킵
    -- GroupRenderer가 모든 레이아웃을 담당 — ViewerLayout과 충돌 방지
    if DDingUI.GroupSystem and DDingUI.GroupSystem.enabled then return end
    -- (fallback) ContainerSync로 은닉된 뷰어는 레이아웃 스킵
    if DDingUI.ContainerSync then
        local vs = DDingUI.ContainerSync
        local viewerName = viewer:GetName()
        if vs._isViewerHidden and vs._isViewerHidden(viewerName) then return end
    end

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
    -- [REPARENT] GroupSystem이 활성 상태면 RescanViewer 완전 스킵
    if DDingUI.GroupSystem and DDingUI.GroupSystem.enabled then return end
    -- (fallback) ContainerSync로 은닉된 뷰어는 스킵
    if DDingUI.ContainerSync then
        local vs = DDingUI.ContainerSync
        local viewerName = viewer:GetName()
        if vs._isViewerHidden and vs._isViewerHidden(viewerName) then return end
    end

    local name = viewer:GetName()
    local settings = DDingUI.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    -- [FIX] CMC IsReady 패턴: 뷰어 초기화 미완료 시 스킵
    if not IsViewerReady(viewer) then return end

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

local centerBuffsThrottle = 0.05  -- [PERF] 20Hz 충분
local nextCenterBuffsUpdate = 0

-- Reusable tables (avoid per-frame GC pressure)
local _visibleBuffIcons = {}

local function CenterBuffIcons()
    -- [FIX] 뷰어가 초기화 미완료 상태면 스킵 (CMC IsReady 패턴)
    local bv = _G["BuffIconCooldownViewer"]
    if not IsViewerReady(bv) then return end

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

    local BuffIconCooldownViewer = bv

    -- [REPARENT] GroupSystem이 활성 상태면 CenterBuffIcons 완전 스킵
    -- GroupRenderer가 모든 레이아웃을 담당 — CenterBuffIcons와 충돌 방지
    -- ContainerSync._isViewerHidden만 체크하면 managed < total일 때 여전히 실행되어
    -- DDingUI 컨테이너 + CDM 뷰어 양쪽에서 아이콘이 배치되는 "2줄, 이빠짐" 발생
    if DDingUI.GroupSystem and DDingUI.GroupSystem.enabled then return end
    -- (fallback) GroupSystem OFF일 때 ContainerSync 은닉 체크
    if DDingUI.ContainerSync and DDingUI.ContainerSync._isViewerHidden then
        if DDingUI.ContainerSync._isViewerHidden("BuffIconCooldownViewer") then return end
    end

    local settings = DDingUI.db and DDingUI.db.profile.viewers["BuffIconCooldownViewer"]
    if settings and settings.enabled == false then return end
    if settings and settings.centerBuffs == false then return end

    -- 아이콘 수집 (reuse table) -- [PERF] O(n²) select(i, GetChildren()) → O(n) 변환
    local visibleCount = 0
    local children = { BuffIconCooldownViewer:GetChildren() }
    for _, childFrame in ipairs(children) do
        -- Note: SetParent된 아이콘은 GetChildren()에 포함되지 않음 (자연 제외)
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

    -- [FIX] secret value 안전 비교
    table.sort(_visibleBuffIcons, function(a, b)
        local la, lb = 0, 0
        pcall(function()
            if a.layoutIndex and type(a.layoutIndex) == "number" then la = a.layoutIndex end
        end)
        pcall(function()
            if b.layoutIndex and type(b.layoutIndex) == "number" then lb = b.layoutIndex end
        end)
        return la < lb
    end)

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

-- ============================================
-- [REFACTOR] BCDM/CMC 패턴: CDM settle 제거 → IsViewerReady + RefreshLayout 훅
-- BCDM: 매 프레임 _G 조회 + OnUpdate 폴링 (settle 없음)
-- CMC: RefreshLayout 훅 + IsReady() 가드
-- DDingUI: 둘의 장점 결합 — OnUpdate 폴링 + IsViewerReady 가드 + RefreshLayout 훅
-- ============================================

-- BuffIconCooldownViewer 센터링: OnUpdate 활성/비활성
-- BCDM처럼 항상 _G 조회하므로 뷰어 재생성에 자연 대응
do
    local function SetupCenterBuffsOnUpdate()
        local viewer = _G["BuffIconCooldownViewer"]
        if not viewer then return false end
        -- 이미 활성이면 스킵
        if centerBuffsActive then return true end
        if viewer:IsShown() then EnableCenterBuffs() end
        hooksecurefunc(viewer, "Show", EnableCenterBuffs)
        hooksecurefunc(viewer, "Hide", DisableCenterBuffs)
        return true
    end

    if not SetupCenterBuffsOnUpdate() then
        local retryCount = 0
        local function RetrySetup()
            retryCount = retryCount + 1
            if not SetupCenterBuffsOnUpdate() and retryCount < 10 then
                C_Timer.After(0.5, RetrySetup)
            end
        end
        C_Timer.After(1, RetrySetup)
    end
end

-- ============================================
-- [Ayije_CDM 패턴] 로딩 화면 플래그 + 스펙 변경 가드 + OnHide 재표시 훅
-- 스펙/특성 변경 중에는 블리자드가 뷰어를 재구축하므로 재표시 억제
-- 재구축 완료 후(3초 뒤)에만 Hide 방지 작동
-- ============================================
local _loadingScreenActive = false
local _pendingSpecChange = false  -- 스펙/특성 변경 중 재표시 억제
local _pendingSpecChangeToken = 0
local _viewerOnHideHooked = setmetatable({}, { __mode = "k" })  -- 뷰어 객체 → true

do
    local lsFrame = CreateFrame("Frame")
    lsFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
    lsFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
    lsFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    lsFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    lsFrame:SetScript("OnEvent", function(_, event)
        if event == "LOADING_SCREEN_ENABLED" then
            _loadingScreenActive = true
        elseif event == "LOADING_SCREEN_DISABLED" then
            _loadingScreenActive = false
        else
            -- 스펙/특성 변경 시 3초간 OnHide 재표시 억제
            -- 블리자드가 뷰어를 재구축하는 동안 Show() 호출 방지
            _pendingSpecChange = true
            _pendingSpecChangeToken = _pendingSpecChangeToken + 1
            local myToken = _pendingSpecChangeToken
            C_Timer.After(3, function()
                if myToken == _pendingSpecChangeToken then
                    _pendingSpecChange = false
                end
            end)
        end
    end)
end

local function HookViewerOnHideReshow(viewerName)
    local viewer = _G[viewerName]
    if not viewer or _viewerOnHideHooked[viewer] then return end
    _viewerOnHideHooked[viewer] = true
    viewer:HookScript("OnHide", function()
        if InCombatLockdown() then return end
        if _loadingScreenActive then return end
        if _pendingSpecChange then return end  -- 스펙/특성 변경 중 재표시 억제
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            if _loadingScreenActive then return end
            if _pendingSpecChange then return end
            if not viewer:IsShown() then
                viewer:Show()
            end
        end)
    end)
end

-- [FIX] 모든 뷰어에 RefreshLayout 훅 (BCDM/CMC 패턴)
-- RefreshLayout은 CDM이 내부 레이아웃을 완전히 완료한 후 호출되므로
-- settle 없이 안전하게 스킨/리레이아웃 가능
-- Essential, Utility, BuffIcon 3개 모두 적용
do
    local viewerNames = DDingUI.viewers or { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
    local hookedViewerRefs = {}  -- 뷰어 객체 → true (중복 훅 방지)

    local function HookViewerRefreshLayout(viewerName)
        local viewer = _G[viewerName]
        if not viewer then return end
        if hookedViewerRefs[viewer] then return end  -- 이미 훅된 객체
        hookedViewerRefs[viewer] = true

        -- RefreshLayout: CDM이 모든 내부 레이아웃을 완료한 후 호출됨
        if viewer.RefreshLayout then
            hooksecurefunc(viewer, "RefreshLayout", function()
                if not IsViewerReady(viewer) then return end
                -- 스킨 + 레이아웃 재적용
                if IconViewers.RescanViewer then
                    IconViewers:RescanViewer(viewer)
                end
                -- BuffIcon은 센터링도 필요
                if viewerName == "BuffIconCooldownViewer" then
                    nextCenterBuffsUpdate = 0
                    CenterBuffIcons()
                end
                -- ResourceBars 동기화 (뷰어 크기 변경 시 바 너비 업데이트)
                if DDingUI.ResourceBars and DDingUI.ResourceBars.UpdatePowerBar then
                    DDingUI.ResourceBars:UpdatePowerBar()
                end
                if DDingUI.ResourceBars and DDingUI.ResourceBars.UpdateSecondaryPowerBar then
                    DDingUI.ResourceBars:UpdateSecondaryPowerBar()
                end
            end)
        end
    end

    local function HookAllViewerRefreshLayouts()
        for _, name in ipairs(viewerNames) do
            HookViewerRefreshLayout(name)
            HookViewerOnHideReshow(name)  -- [Ayije_CDM 패턴] OnHide 재표시 훅
        end
    end

    -- 초기 설치
    HookAllViewerRefreshLayouts()
    -- 뷰어가 늦게 생성될 수 있으므로 재시도
    C_Timer.After(1, HookAllViewerRefreshLayouts)
    C_Timer.After(3, HookAllViewerRefreshLayouts)

    -- [FIX] 전문화/레벨업/인스턴스 전환 시 뷰어 재생성 → 훅 + 스킨 재설치
    local function OnMajorStateChange()
        -- 새 뷰어에 RefreshLayout 훅 설치
        HookAllViewerRefreshLayouts()

        -- 모든 뷰어 HookViewers + RefreshAll (OnShow/OnSizeChanged/UNIT_AURA 훅 재설치)
        if IconViewers.HookViewers then
            IconViewers:HookViewers()
        end
        if IconViewers.RefreshAll then
            IconViewers:RefreshAll()
        end

        -- 센터링 즉시 실행
        nextCenterBuffsUpdate = 0
        CenterBuffIcons()

        -- ResourceBars 동기화
        if DDingUI.ResourceBars and DDingUI.ResourceBars.UpdatePowerBar then
            DDingUI.ResourceBars:UpdatePowerBar()
        end
        if DDingUI.ResourceBars and DDingUI.ResourceBars.UpdateSecondaryPowerBar then
            DDingUI.ResourceBars:UpdateSecondaryPowerBar()
        end
    end

    -- [Ayije_CDM 패턴] CountPopulatedFrames: 빈 프레임 감지 → 재시도
    local function CheckAndRecoverUnpopulatedFrames()
        local anyUnpopulated = false
        for _, vName in ipairs(viewerNames) do
            local v = _G[vName]
            if v and v.itemFramePool then
                local total, populated = 0, 0
                for frame in v.itemFramePool:EnumerateActive() do
                    total = total + 1
                    local hasData = false
                    pcall(function()
                        hasData = frame.layoutIndex ~= nil or frame.cooldownID ~= nil
                    end)
                    if hasData then populated = populated + 1 end
                end
                if total > 0 and populated < total then
                    anyUnpopulated = true
                    break
                end
            end
        end
        if anyUnpopulated then
            OnMajorStateChange()
        end
    end

    local viewerRefreshFrame = CreateFrame("Frame")
    viewerRefreshFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    viewerRefreshFrame:RegisterEvent("PLAYER_LEVEL_UP")
    viewerRefreshFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
    viewerRefreshFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    viewerRefreshFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- [FIX] 리로드 직후 강화효과 위치 즉시 보정 (Ayije_CDM RunVisualSetup 패턴)
            -- IsViewerReady 가드를 우회하여 빠르게 CenterBuffIcons 실행
            C_Timer.After(0.1, function()
                nextCenterBuffsUpdate = 0
                CenterBuffIcons()
            end)
            C_Timer.After(0.5, function()
                nextCenterBuffsUpdate = 0
                CenterBuffIcons()
            end)
            C_Timer.After(1.0, OnMajorStateChange)
            return
        end
        -- 뷰어 재생성 대기 후 재설치 시도 (여러 시점에서)
        C_Timer.After(0.3, OnMajorStateChange)
        C_Timer.After(1.0, OnMajorStateChange)
        C_Timer.After(2.5, OnMajorStateChange)
        -- [Ayije_CDM 패턴] 4초 후 빈 프레임 체크 → 미복구 아이콘 강제 재시도
        C_Timer.After(4.0, CheckAndRecoverUnpopulatedFrames)
    end)
end

-- 즉시 실행 버전 — [PERF] throttle 존중: 최근 실행했으면 스킵
local function CenterBuffIconsImmediate()
    local now = GetTime()
    if now < nextCenterBuffsUpdate then return end  -- [PERF] 이미 최근에 실행됨 → 스킵 (OnUpdate가 잡아줌)
    nextCenterBuffsUpdate = 0
    CenterBuffIcons()
end

-- UNIT_AURA 이벤트로 반응 — [PERF] debounce로 버스트 방지
local _centerBuffAuraPending = false
local buffEventFrame = CreateFrame("Frame")
buffEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
buffEventFrame:SetScript("OnEvent", function(_, event, unit)
    if unit == "player" and not _centerBuffAuraPending then
        _centerBuffAuraPending = true
        C_Timer.After(0.05, function()  -- [PERF] 0→0.05s debounce (50ms 내 중복 UNIT_AURA 병합)
            _centerBuffAuraPending = false
            CenterBuffIconsImmediate()
        end)
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
